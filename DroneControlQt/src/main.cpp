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
#include <QQuickWindow>
#include <QSize>
#include <QTimer>
#include <QFile>
#ifdef HAVE_QT_WEBVIEW
#include <QtWebView/QtWebView>
#endif

#include "GamepadManager.h"
#include "MavlinkManager.h"
#include "MessagesModel.h"
#include "ParameterModel.h"
#include "SettingsManager.h"
#include "TileCache.h"
#include <QDebug>

// The map page is a Leaflet page (port of the MapWidget) shown in a WebView; the HTML,
// Leaflet JS and CSS are inlined into one document so it also loads in the Android WebView.
static QString loadMapHtml(int tilePort)
{
    auto readAll = [](const QString &path) {
        QFile f(path);
        return f.open(QIODevice::ReadOnly) ? QString::fromUtf8(f.readAll()) : QString();
    };
    QString html = readAll(QStringLiteral(":/web/map.html"));
    const QString css = readAll(QStringLiteral(":/web/leaflet.css"));
    const QString js = readAll(QStringLiteral(":/web/leaflet.js"));
    html.replace(QStringLiteral("/*LEAFLET_CSS*/"), css);
    html.replace(QStringLiteral("/*LEAFLET_JS*/"), js);
    // tiles go through the local cache server (offline support); port 0 = server failed, use the web directly
    html.replace(QStringLiteral("/*TILE_PORT*/0"), QString::number(tilePort));
    qDebug() << "[MAP] map page" << html.size() << "chars (html" << (html.size() - css.size() - js.size())
             << "css" << css.size() << "js" << js.size() << ")";
    if (html.isEmpty() || js.isEmpty())
        qWarning() << "[MAP] web/map.html or web/leaflet.js missing from resources - map will be empty";
    return html;
}

int main(int argc, char *argv[])
{
#ifdef HAVE_QT_WEBVIEW
    // Desktop backend is Qt WebEngine: it needs a shared GL context.
#if !defined(Q_OS_ANDROID) && !defined(Q_OS_IOS)
    QCoreApplication::setAttribute(Qt::AA_ShareOpenGLContexts);
    // Scene graph RHI: WebEngine composites into the Qt Quick scene through shared GL textures.
    // With the D3D11 RHI Chromium runs on ANGLE, which fails on some Intel/NVIDIA hybrid laptops
    // ("Failed to create GLES3 context ... kFatalFailure", then a crash on zoom/pan), so the
    // desktop OpenGL RHI is used everywhere by default. DRONECONTROL_RHI=d3d11|opengl overrides.
    const QByteArray rhi = qgetenv("DRONECONTROL_RHI").toLower();
    if (rhi == "d3d11")
        QQuickWindow::setGraphicsApi(QSGRendererInterface::Direct3D11);
    else if (rhi == "vulkan")
        QQuickWindow::setGraphicsApi(QSGRendererInterface::Vulkan);
    else
        QQuickWindow::setGraphicsApi(QSGRendererInterface::OpenGLRhi);
    qDebug() << "[MAP] scene graph RHI:" << (rhi.isEmpty() ? "opengl (default)" : rhi.constData())
             << " chromium flags:" << qgetenv("QTWEBENGINE_CHROMIUM_FLAGS");
#endif
#if defined(Q_OS_WIN)
    // Qt 6.8+ ships a native WebView2 (Edge) backend on Windows. It is a separate native window
    // (nothing can be drawn over it, no loadHtml base URL, blank page on some machines), so use
    // the Qt WebEngine backend like on Linux/macOS. QT_WEBVIEW_PLUGIN set by the user wins.
    if (!qEnvironmentVariableIsSet("QT_WEBVIEW_PLUGIN"))
        qputenv("QT_WEBVIEW_PLUGIN", "webengine");
#endif
    QtWebView::initialize();   // must run before the application object exists
    qDebug() << "[MAP] Qt WebView initialised";
#else
    qDebug() << "[MAP] built without Qt WebView";
#endif
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
    TileCache tiles;                       // local tile proxy + disk cache for the map (must outlive the engine)

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
    ctx->setContextProperty(QStringLiteral("screenshotDelayMs"), qEnvironmentVariableIntValue("DRONECONTROL_SCREENSHOT_DELAY") > 0
                            ? qEnvironmentVariableIntValue("DRONECONTROL_SCREENSHOT_DELAY") : 2500);
    {
        // DRONECONTROL_SCREENSHOT_SIZE=WxH forces the window size (e.g. 400x800 for a phone layout)
        const QStringList wh = qEnvironmentVariable("DRONECONTROL_SCREENSHOT_SIZE").split(QLatin1Char('x'));
        QSize size;
        if (wh.size() == 2)
            size = QSize(wh[0].toInt(), wh[1].toInt());
        ctx->setContextProperty(QStringLiteral("screenshotSize"), size);
    }
    ctx->setContextProperty(QStringLiteral("tiles"), &tiles);
#ifdef HAVE_QT_WEBVIEW
    ctx->setContextProperty(QStringLiteral("hasWebView"), true);
    ctx->setContextProperty(QStringLiteral("mapHtml"), loadMapHtml(tiles.port()));
#else
    ctx->setContextProperty(QStringLiteral("hasWebView"), false);
    ctx->setContextProperty(QStringLiteral("mapHtml"), QString());
#endif
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
