// main.cpp - DroneControlQt
//
// Qt 6 port of the DroneControl iOS/macOS app (MAVLink ground control for
// ArduPilot vehicles). Desktop (Windows/Linux/macOS) and Android.

#include <QFontDatabase>
#include <QGuiApplication>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QSize>
#include <QTimer>

#include "GamepadManager.h"
#include "MavlinkManager.h"
#include "MessagesModel.h"
#include "ParameterModel.h"
#include "SettingsManager.h"

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    app.setOrganizationName(QStringLiteral("Maren"));
    app.setOrganizationDomain(QStringLiteral("marenrobotics.com"));
    app.setApplicationName(QStringLiteral("DroneControl"));
    app.setApplicationDisplayName(QStringLiteral("Drone Control"));
    app.setWindowIcon(QIcon(QStringLiteral(":/icons/app_icon.png")));

    // Material dark style (also the natural choice on Android)
    QQuickStyle::setStyle(QStringLiteral("Material"));

    SettingsManager settings;
    MavlinkManager mavlink;
    GamepadManager gamepad(&settings);

    // Gamepad buttons -> vehicle commands (START = ARM, BACK = DISARM, forced like the iOS app)
    QObject::connect(&gamepad, &GamepadManager::armRequested, &mavlink, &MavlinkManager::arm);
    QObject::connect(&gamepad, &GamepadManager::disarmRequested, &mavlink, &MavlinkManager::disarm);

    // Connection endpoint follows the settings; reconnect (debounced) when they change
    auto applyEndpoint = [&]() {
        bool ok = false;
        int port = settings.connectionPort().toInt(&ok);
        if (!ok || port <= 0 || port > 65535)
            port = 14550;
        mavlink.setEndpoint(settings.connectionHost(), port, 14550);
    };
    applyEndpoint();

    QTimer reconnectTimer;
    reconnectTimer.setSingleShot(true);
    reconnectTimer.setInterval(800);
    QObject::connect(&reconnectTimer, &QTimer::timeout, [&]() {
        mavlink.disconnectVehicle();
        applyEndpoint();
        mavlink.connectVehicle();
    });
    QObject::connect(&settings, &SettingsManager::connectionHostChanged, &reconnectTimer, qOverload<>(&QTimer::start));
    QObject::connect(&settings, &SettingsManager::connectionPortChanged, &reconnectTimer, qOverload<>(&QTimer::start));

    qmlRegisterUncreatableType<ParameterModel>("DroneControl", 1, 0, "ParameterModel", QStringLiteral("owned by MavlinkManager"));
    qmlRegisterUncreatableType<MessagesModel>("DroneControl", 1, 0, "MessagesModel", QStringLiteral("owned by MavlinkManager"));
    qmlRegisterSingletonType(QUrl(QStringLiteral("qrc:/qml/Theme.qml")), "DroneControl", 1, 0, "Theme");

    QQmlApplicationEngine engine;
    QQmlContext *ctx = engine.rootContext();
    ctx->setContextProperty(QStringLiteral("mavlink"), &mavlink);
    ctx->setContextProperty(QStringLiteral("settings"), &settings);
    ctx->setContextProperty(QStringLiteral("gamepad"), &gamepad);
    ctx->setContextProperty(QStringLiteral("fixedFontFamily"),
                            QFontDatabase::systemFont(QFontDatabase::FixedFont).family());
    // Debug aid: DRONECONTROL_SCREENSHOT_DIR=<dir> cycles through the tabs and saves PNGs
    ctx->setContextProperty(QStringLiteral("screenshotDir"), qEnvironmentVariable("DRONECONTROL_SCREENSHOT_DIR"));
    {
        // DRONECONTROL_SCREENSHOT_SIZE=WxH forces the window size (e.g. 400x800 for a phone layout)
        const QStringList wh = qEnvironmentVariable("DRONECONTROL_SCREENSHOT_SIZE").split(QLatin1Char('x'));
        QSize size;
        if (wh.size() == 2)
            size = QSize(wh[0].toInt(), wh[1].toInt());
        ctx->setContextProperty(QStringLiteral("screenshotSize"), size);
    }
#ifdef HAVE_QT_LOCATION
    ctx->setContextProperty(QStringLiteral("hasMapSupport"), true);
#else
    ctx->setContextProperty(QStringLiteral("hasMapSupport"), false);
#endif

    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed, &app,
                     []() { QCoreApplication::exit(-1); }, Qt::QueuedConnection);
    engine.load(QUrl(QStringLiteral("qrc:/qml/Main.qml")));
    if (engine.rootObjects().isEmpty())
        return -1;

    // Like DroneControlApp.swift: connect on launch
    mavlink.connectVehicle();

    return app.exec();
}
