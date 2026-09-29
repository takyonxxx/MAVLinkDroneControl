// GamepadManager.cpp - DroneControlQt

#include "GamepadManager.h"
#include "SettingsManager.h"

#include <QDebug>
#include <QVariantMap>
#include <cmath>

// Button ids used by checkButton()
enum { GP_BTN_START = 0, GP_BTN_BACK = 1, GP_BTN_L3 = 2, GP_BTN_R3 = 3 };

// ---------------------------------------------------------------------------
// Platform backends

#if defined(Q_OS_WIN)

#include <windows.h>

// Minimal XInput definitions so we do not need the SDK header / import lib
struct XI_GAMEPAD {
    WORD wButtons;
    BYTE bLeftTrigger;
    BYTE bRightTrigger;
    SHORT sThumbLX;
    SHORT sThumbLY;
    SHORT sThumbRX;
    SHORT sThumbRY;
};
struct XI_STATE {
    DWORD dwPacketNumber;
    XI_GAMEPAD Gamepad;
};
typedef DWORD (WINAPI *XInputGetStateFn)(DWORD, XI_STATE *);

static const WORD XI_START = 0x0010;
static const WORD XI_BACK = 0x0020;
static const WORD XI_LEFT_THUMB = 0x0040;
static const WORD XI_RIGHT_THUMB = 0x0080;

struct GamepadManager::Backend {
    HMODULE lib = nullptr;
    XInputGetStateFn getState = nullptr;
    int userIndex = -1;

    Backend()
    {
        const wchar_t *names[] = {L"xinput1_4.dll", L"xinput1_3.dll", L"xinput9_1_0.dll"};
        for (const wchar_t *n : names) {
            lib = LoadLibraryW(n);
            if (lib) {
                getState = reinterpret_cast<XInputGetStateFn>(GetProcAddress(lib, "XInputGetState"));
                if (getState)
                    break;
                FreeLibrary(lib);
                lib = nullptr;
            }
        }
    }
    ~Backend()
    {
        if (lib)
            FreeLibrary(lib);
    }
    bool available() const { return getState != nullptr; }

    bool scan(QString &name)
    {
        if (!getState)
            return false;
        for (DWORD i = 0; i < 4; ++i) {
            XI_STATE st{};
            if (getState(i, &st) == ERROR_SUCCESS) {
                userIndex = int(i);
                name = QStringLiteral("XInput Controller %1").arg(i + 1);
                return true;
            }
        }
        userIndex = -1;
        return false;
    }

    // returns false when the controller went away
    bool read(float &lx, float &ly, float &rx, float &ry, bool btn[4])
    {
        if (!getState || userIndex < 0)
            return false;
        XI_STATE st{};
        if (getState(DWORD(userIndex), &st) != ERROR_SUCCESS)
            return false;
        auto norm = [](SHORT v) { return float(v) / 32767.0f; };
        lx = norm(st.Gamepad.sThumbLX);
        ly = norm(st.Gamepad.sThumbLY);
        rx = norm(st.Gamepad.sThumbRX);
        ry = norm(st.Gamepad.sThumbRY);
        btn[GP_BTN_START] = st.Gamepad.wButtons & XI_START;
        btn[GP_BTN_BACK] = st.Gamepad.wButtons & XI_BACK;
        btn[GP_BTN_L3] = st.Gamepad.wButtons & XI_LEFT_THUMB;
        btn[GP_BTN_R3] = st.Gamepad.wButtons & XI_RIGHT_THUMB;
        return true;
    }
};

#elif defined(Q_OS_LINUX) && !defined(Q_OS_ANDROID)

#include <cerrno>
#include <fcntl.h>
#include <linux/joystick.h>
#include <sys/ioctl.h>
#include <unistd.h>

struct GamepadManager::Backend {
    int fd = -1;
    float axes[8] = {};
    bool buttons[16] = {};

    ~Backend() { closeDev(); }
    bool available() const { return true; }

    void closeDev()
    {
        if (fd >= 0)
            ::close(fd);
        fd = -1;
    }

    bool scan(QString &name)
    {
        closeDev();
        for (int i = 0; i < 4; ++i) {
            const QByteArray path = QByteArrayLiteral("/dev/input/js") + QByteArray::number(i);
            fd = ::open(path.constData(), O_RDONLY | O_NONBLOCK);
            if (fd >= 0) {
                char buf[128] = {};
                if (ioctl(fd, JSIOCGNAME(sizeof(buf)), buf) >= 0)
                    name = QString::fromLocal8Bit(buf);
                else
                    name = QString::fromLatin1(path);
                return true;
            }
        }
        return false;
    }

    bool read(float &lx, float &ly, float &rx, float &ry, bool btn[4])
    {
        if (fd < 0)
            return false;
        js_event e;
        while (true) {
            const ssize_t n = ::read(fd, &e, sizeof(e));
            if (n != ssize_t(sizeof(e))) {
                if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK))
                    break;
                if (n < 0 && errno == ENODEV)
                    return false;
                break;
            }
            const int type = e.type & ~JS_EVENT_INIT;
            if (type == JS_EVENT_AXIS && e.number < 8)
                axes[e.number] = float(e.value) / 32767.0f;
            else if (type == JS_EVENT_BUTTON && e.number < 16)
                buttons[e.number] = e.value != 0;
        }
        // Xbox-style layout: 0=LX 1=LY 3=RX 4=RY (Y axes point down)
        lx = axes[0];
        ly = -axes[1];
        rx = axes[3];
        ry = -axes[4];
        btn[GP_BTN_START] = buttons[7];
        btn[GP_BTN_BACK] = buttons[6];
        btn[GP_BTN_L3] = buttons[9];
        btn[GP_BTN_R3] = buttons[10];
        return true;
    }
};

#else

struct GamepadManager::Backend {
    bool available() const { return false; }
    bool scan(QString &) { return false; }
    bool read(float &, float &, float &, float &, bool[4]) { return false; }
};

#endif

// ---------------------------------------------------------------------------

GamepadManager::GamepadManager(SettingsManager *settings, QObject *parent)
    : QObject(parent)
    , m_backend(new Backend)
{
    if (settings) {
        m_deadzone = settings->gamepadDeadzone();
        m_holdThrottle = settings->gamepadHoldThrottle();
        m_throttleSpeed = settings->throttleSpeed();
        connect(settings, &SettingsManager::gamepadDeadzoneChanged, this,
                [this, settings]() { setDeadzone(settings->gamepadDeadzone()); });
        connect(settings, &SettingsManager::gamepadHoldThrottleChanged, this,
                [this, settings]() { setHoldThrottle(settings->gamepadHoldThrottle()); });
        connect(settings, &SettingsManager::throttleSpeedChanged, this,
                [this, settings]() { setThrottleSpeed(settings->throttleSpeed()); });
    }

    m_pollTimer.setInterval(16);
    connect(&m_pollTimer, &QTimer::timeout, this, &GamepadManager::poll);

    // Rescan for a controller every 2 s while none is connected
    m_scanTimer.setInterval(2000);
    connect(&m_scanTimer, &QTimer::timeout, this, &GamepadManager::scanDevices);

    if (m_backend->available()) {
        QTimer::singleShot(1000, this, &GamepadManager::scanDevices);
        m_scanTimer.start();
    }
}

GamepadManager::~GamepadManager()
{
    delete m_backend;
}

bool GamepadManager::backendAvailable() const
{
    return m_backend->available();
}

void GamepadManager::scanDevices()
{
    if (m_connected)
        return;
    QString name;
    if (m_backend->scan(name)) {
        setConnected(true, name);
        m_pollTimer.start();
        qDebug() << "[GAMEPAD] Controller connected:" << name;
    }
}

void GamepadManager::refreshControllers()
{
    scanDevices();
}

void GamepadManager::setConnected(bool c, const QString &name)
{
    if (m_connected == c && m_name == name)
        return;
    m_connected = c;
    m_name = c ? name : QStringLiteral("No Controller");
    emit controllerChanged();
}

void GamepadManager::poll()
{
    float lx = 0, ly = 0, rx = 0, ry = 0;
    bool btn[4] = {};
    if (!m_backend->read(lx, ly, rx, ry, btn)) {
        m_pollTimer.stop();
        setConnected(false, QString());
        resetAll();
        qDebug() << "[GAMEPAD] Controller disconnected";
        return;
    }
    applyAxes(lx, ly, rx, ry);
    for (int i = 0; i < 4; ++i)
        checkButton(i, btn[i]);
}

float GamepadManager::applyDeadzone(float v) const
{
    if (std::fabs(v) < m_deadzone)
        return 0;
    const float sign = v > 0 ? 1.0f : -1.0f;
    return sign * (std::fabs(v) - m_deadzone) / (1.0f - m_deadzone);
}

void GamepadManager::applyAxes(float lx, float ly, float rx, float ry)
{
    lx = applyDeadzone(lx);
    ly = applyDeadzone(ly);
    rx = applyDeadzone(rx);
    ry = applyDeadzone(ry);

    m_leftX = lx;                                   // yaw
    if (m_holdThrottle) {
        // INCREMENT MODE: holding the stick up keeps increasing throttle
        m_leftY = qBound(-1.0f, m_leftY + ly * m_throttleSpeed, 1.0f);
    } else {
        // DIRECT MODE: stick position = throttle
        m_leftY = ly;
    }
    m_rightX = rx;                                  // roll
    m_rightY = ry;                                  // pitch
    emit sticksChanged();
}

void GamepadManager::checkButton(int id, bool pressed)
{
    const bool was = m_buttonState[id];
    m_buttonState[id] = pressed;
    if (!pressed || was)
        return;   // only on the press edge
    switch (id) {
    case GP_BTN_START: emit armRequested(); break;
    case GP_BTN_BACK: emit disarmRequested(); break;
    case GP_BTN_L3:
    case GP_BTN_R3: resetAll(); break;
    }
}

QVariantMap GamepadManager::manualControlValues() const
{
    QVariantMap m;
    m.insert(QStringLiteral("x"), int(m_rightY * 1000));            // pitch
    m.insert(QStringLiteral("y"), int(m_rightX * 1000));            // roll
    m.insert(QStringLiteral("z"), int((m_leftY + 1.0f) * 500));     // throttle 0..1000
    m.insert(QStringLiteral("r"), int(m_leftX * 1000));             // yaw
    return m;
}

void GamepadManager::resetAll()
{
    m_leftX = 0;
    m_leftY = -1;
    m_rightX = 0;
    m_rightY = 0;
    emit sticksChanged();
}

void GamepadManager::setThrottle(float value)
{
    m_leftY = qBound(-1.0f, value, 1.0f);
    emit sticksChanged();
}

void GamepadManager::setDeadzone(float v)
{
    if (qFuzzyCompare(m_deadzone, v))
        return;
    m_deadzone = v;
    emit settingsChanged();
}

void GamepadManager::setHoldThrottle(bool v)
{
    if (m_holdThrottle == v)
        return;
    m_holdThrottle = v;
    emit settingsChanged();
}

void GamepadManager::setThrottleSpeed(float v)
{
    if (qFuzzyCompare(m_throttleSpeed, v))
        return;
    m_throttleSpeed = v;
    emit settingsChanged();
}
