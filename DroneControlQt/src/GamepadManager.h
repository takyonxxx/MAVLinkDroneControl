// GamepadManager.h - DroneControlQt
//
// Port of GamepadManager.swift. Polls a game controller at ~60 Hz and exposes
// normalized stick values (-1..1, Y up) plus the same button actions as the
// iOS/macOS app: START -> ARM, BACK -> DISARM, L3/R3 -> reset sticks.
//
// Backends:
//   Windows : XInput (loaded dynamically, no link-time dependency)
//   Linux   : /dev/input/js* joystick API
//   Android : key/motion events forwarded from QtActivity are not available
//             without a custom Activity, so no gamepad (touch joysticks are used)
//   macOS   : not implemented here (touch/mouse joysticks)

#pragma once

#include <QObject>
#include <QVariantMap>
#include <QTimer>

class SettingsManager;

class GamepadManager : public QObject
{
    Q_OBJECT
    Q_PROPERTY(float leftStickX READ leftStickX NOTIFY sticksChanged)
    Q_PROPERTY(float leftStickY READ leftStickY NOTIFY sticksChanged)
    Q_PROPERTY(float rightStickX READ rightStickX NOTIFY sticksChanged)
    Q_PROPERTY(float rightStickY READ rightStickY NOTIFY sticksChanged)
    Q_PROPERTY(bool controllerConnected READ isControllerConnected NOTIFY controllerChanged)
    Q_PROPERTY(QString controllerName READ controllerName NOTIFY controllerChanged)
    Q_PROPERTY(bool backendAvailable READ backendAvailable CONSTANT)
    Q_PROPERTY(float deadzone READ deadzone WRITE setDeadzone NOTIFY settingsChanged)
    Q_PROPERTY(bool holdThrottle READ holdThrottle WRITE setHoldThrottle NOTIFY settingsChanged)
    Q_PROPERTY(float throttleSpeed READ throttleSpeed WRITE setThrottleSpeed NOTIFY settingsChanged)

public:
    explicit GamepadManager(SettingsManager *settings, QObject *parent = nullptr);
    ~GamepadManager() override;

    float leftStickX() const { return m_leftX; }
    float leftStickY() const { return m_leftY; }
    float rightStickX() const { return m_rightX; }
    float rightStickY() const { return m_rightY; }
    bool isControllerConnected() const { return m_connected; }
    QString controllerName() const { return m_name; }
    bool backendAvailable() const;

    float deadzone() const { return m_deadzone; }
    bool holdThrottle() const { return m_holdThrottle; }
    float throttleSpeed() const { return m_throttleSpeed; }
    void setDeadzone(float v);
    void setHoldThrottle(bool v);
    void setThrottleSpeed(float v);

    // MANUAL_CONTROL values: x=pitch, y=roll, z=throttle 0..1000, r=yaw
    Q_INVOKABLE QVariantMap manualControlValues() const;
    Q_INVOKABLE void resetAll();
    Q_INVOKABLE void setThrottle(float value);
    Q_INVOKABLE void refreshControllers();

signals:
    void sticksChanged();
    void controllerChanged();
    void settingsChanged();
    void armRequested();
    void disarmRequested();

private:
    void poll();
    void scanDevices();
    void applyAxes(float lx, float ly, float rx, float ry);   // raw -1..1, Y up
    void checkButton(int id, bool pressed);
    float applyDeadzone(float v) const;
    void setConnected(bool c, const QString &name);

    QTimer m_pollTimer;
    QTimer m_scanTimer;

    float m_leftX = 0, m_leftY = -1, m_rightX = 0, m_rightY = 0;
    bool m_connected = false;
    QString m_name = QStringLiteral("No Controller");

    float m_deadzone = 0.1f;
    bool m_holdThrottle = true;
    float m_throttleSpeed = 0.010f;

    bool m_buttonState[16] = {};

    struct Backend;
    Backend *m_backend = nullptr;
};
