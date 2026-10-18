#include <QCommandLineParser>
#include <QFile>
#include <QGuiApplication>
#include <QNetworkInformation>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>
#include <QSGRendererInterface>
#include <QSettings>
#include <QTimer>
#if QT_CONFIG(opengl)
#include <QOpenGLContext>
#include <QOpenGLFunctions>
#endif

#include <csignal>

#include "backend/SupabaseClient.h"
#include "games/FourInARowEngine.h"
#include "games/ColorByNumber.h"
#include "games/PenguinWorld.h"
#include "hardware/DisplayController.h"
#include "hardware/PanelPower.h"
#include "hardware/PerfMonitor.h"
#include "hardware/StopSignals.h"
#include "hardware/SystemController.h"
#include "models/Assistant.h"
#include "models/FeedStore.h"
#include "models/SettingsBridge.h"
#include "models/HomeGlance.h"
#include "models/QrImageProvider.h"
#include "voice/VoiceClient.h"

// Environment variables win over the saved settings so a device can be
// reconfigured without touching its config file.
static QString setting(QSettings &settings, const char *env, const QString &key)
{
    const QString fromEnv = qEnvironmentVariable(env);
    return fromEnv.isEmpty() ? settings.value(key).toString() : fromEnv;
}

// The kiosk draws on the HDMI panel. Set that before QGuiApplication, which
// reads the platform plugin once. A desktop session (DISPLAY or WAYLAND) and
// an explicit QT_QPA_PLATFORM, including the offscreen CI run, are left alone.
// --windowed is the development window and must not take the DRM device.
static void preparePanelPlatform(int argc, char **argv)
{
    for (int i = 1; i < argc; ++i) {
        if (qstrcmp(argv[i], "--windowed") == 0)
            return;
    }
    const bool platformSet = !qEnvironmentVariableIsEmpty("QT_QPA_PLATFORM");
    const bool desktop = !qEnvironmentVariableIsEmpty("DISPLAY")
        || !qEnvironmentVariableIsEmpty("WAYLAND_DISPLAY");
#ifdef Q_OS_LINUX
    if (!platformSet && !desktop)
        qputenv("QT_QPA_PLATFORM", QByteArrayLiteral("eglfs"));
#else
    Q_UNUSED(platformSet);
    Q_UNUSED(desktop);
#endif
    if (qgetenv("QT_QPA_PLATFORM") != "eglfs")
        return;
    if (qEnvironmentVariableIsEmpty("QT_QPA_EGLFS_INTEGRATION"))
        qputenv("QT_QPA_EGLFS_INTEGRATION", QByteArrayLiteral("eglfs_kms"));
    if (qEnvironmentVariableIsEmpty("QT_QPA_EGLFS_KMS_CONFIG")
        && QFile::exists(QStringLiteral("/etc/mcfly/kms.json")))
        qputenv("QT_QPA_EGLFS_KMS_CONFIG", QByteArrayLiteral("/etc/mcfly/kms.json"));
    if (qEnvironmentVariableIsEmpty("QT_QPA_EGLFS_HIDECURSOR"))
        qputenv("QT_QPA_EGLFS_HIDECURSOR", QByteArrayLiteral("1"));
    // The console may already have a mode. Set it again so the text console
    // does not stay on HDMI while this process is running.
    if (qEnvironmentVariableIsEmpty("QT_QPA_EGLFS_ALWAYS_SET_MODE"))
        qputenv("QT_QPA_EGLFS_ALWAYS_SET_MODE", QByteArrayLiteral("1"));
}

// Says in the log what draws, so `journalctl -t mcfly-display` on the Pi
// shows whether the GPU is in use ("drawing on V3D ..."). Not `-u`: the
// kiosk's logind session files the app's lines under session-N.scope.
static void reportGraphics(QQmlApplicationEngine &engine)
{
    auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().value(0));
    if (!window)
        return;
    QObject::connect(
        window, &QQuickWindow::beforeRendering, window,
        [window]() {
            if (window->rendererInterface()->graphicsApi() == QSGRendererInterface::Software) {
                qWarning("McFly display: Qt Quick is drawing in software; the GPU is not used");
                return;
            }
#if QT_CONFIG(opengl)
            if (QOpenGLContext *gl = QOpenGLContext::currentContext()) {
                const auto *renderer = reinterpret_cast<const char *>(gl->functions()->glGetString(GL_RENDERER));
                const QByteArray name = renderer ? QByteArray(renderer) : QByteArrayLiteral("an unknown OpenGL device");
                if (name.contains("llvmpipe") || name.contains("softpipe"))
                    qWarning("McFly display: drawing on %s, in software; the GPU is not used", name.constData());
                else
                    qInfo("McFly display: drawing on %s", name.constData());
            }
#endif
        },
        Qt::ConnectionType(Qt::DirectConnection | Qt::SingleShotConnection));
    window->update();
}

int main(int argc, char *argv[])
{
    preparePanelPlatform(argc, argv);
    // The controls are all drawn by hand; a desktop's native style (macOS)
    // would refuse that customization.
    if (qEnvironmentVariableIsEmpty("QT_QUICK_CONTROLS_STYLE"))
        qputenv("QT_QUICK_CONTROLS_STYLE", QByteArrayLiteral("Basic"));
    QGuiApplication app(argc, argv);
    // Right after the app: eglfs installs its own SIGTERM handler in there,
    // which ends every systemctl stop with _exit(1). Quit cleanly instead.
    StopSignals stopSignals;
    QObject::connect(&stopSignals, &StopSignals::stopRequested, &app, [](int signal) {
        qInfo("McFly display: %s, quitting", signal == SIGINT ? "SIGINT" : "SIGTERM");
        QCoreApplication::quit();
    });
    QGuiApplication::setOrganizationName("McFly");
    QGuiApplication::setApplicationName("display");
    QGuiApplication::setApplicationVersion(QStringLiteral(MCFLY_VERSION));

    QCommandLineParser parser;
    parser.setApplicationDescription("McFly display");
    parser.addHelpOption();
    parser.addVersionOption();
    QCommandLineOption windowed("windowed", "Run in a window instead of full screen (development).");
    QCommandLineOption demo("demo", "Ignore backend settings and show sample data.");
    // Read by Main.qml; registered here so the parser doesn't reject it.
    QCommandLineOption noKeyboard("no-keyboard", "Don't load the on-screen keyboard.");
    QCommandLineOption screen("screen", "Open on this screen: home, briefs, markets, news, projects, boards, calendar, games, setup, saver, ask, settings, "
                                      "settings/<tab> (screen, voice, wifi, account, system, admin) or admin.", "name");
    QCommandLineOption screenshot("screenshot", "Save a picture of the window to <file> after a moment and quit.", "file");
    QCommandLineOption size("size", "Window size for --windowed, like 800x480 (default 1280x800).", "WxH");
    QCommandLineOption bench("bench", "Measure every screen, drawn every frame, a line each in the log, then quit "
                                      "(MCFLY_BENCH=1 runs it once at start and carries on).");
    parser.addOptions({windowed, demo, noKeyboard, screen, screenshot, size, bench});
    parser.process(app);

    // A running process with no screen leaves the text console on HDMI and
    // looks healthy to systemctl. Exit so Restart= tries again once the
    // panel or the DRM device is there.
    if (QGuiApplication::screens().isEmpty()) {
        qCritical("McFly display: no screen. The HDMI device was not opened.");
        return 1;
    }

    QSettings settings;
    const QString url = setting(settings, "MCFLY_SUPABASE_URL", "backend/url");
    const QString anonKey = setting(settings, "MCFLY_SUPABASE_ANON_KEY", "backend/anonKey");

    SupabaseClient client(QUrl(url), anonKey);
    client.setRefreshToken(setting(settings, "MCFLY_DEVICE_REFRESH_TOKEN", "device/refreshToken"));

    FeedStore store(&client, parser.isSet(demo));

    // The on-device voice service (wake word, speech in and out) is optional.
    QString voiceUrl = setting(settings, "MCFLY_VOICE_URL", "voice/url");
    if (voiceUrl.isEmpty())
        voiceUrl = QStringLiteral("ws://127.0.0.1:8765");
    VoiceClient voice{QUrl(voiceUrl)};

    Assistant assistant(&client, &store, &voice);
    DisplayController display;
    app.installEventFilter(&display);
    PanelPower panelPower(&display);
    SystemController system;
    system.start();
    // The web console and this screen edit the same settings.
    SettingsBridge settingsBridge(&store, &display, &assistant, &voice);
    HomeGlance glance(&store); // the assistant-first Home's opening lines
    // The performance overlay, with MCFLY_PERF_HUD=1 (development). Always
    // there for QML to read; off, it never samples.
    PerfMonitor perf;

    qmlRegisterSingletonInstance("McFly.Core", 1, 0, "Store", &store);
    qmlRegisterSingletonInstance("McFly.Core", 1, 0, "Device", &display);
    qmlRegisterSingletonInstance("McFly.Core", 1, 0, "System", &system);
    qmlRegisterSingletonInstance("McFly.Core", 1, 0, "AI", &assistant);
    qmlRegisterSingletonInstance("McFly.Core", 1, 0, "Voice", &voice);
    qmlRegisterSingletonInstance("McFly.Core", 1, 0, "Glance", &glance);
    qmlRegisterSingletonInstance("McFly.Core", 1, 0, "Perf", &perf);
    FourInARowEngine fourInARow; // McFly's look-ahead in the Games tab's Four in a Row
    qmlRegisterSingletonInstance("McFly.Core", 1, 0, "FourInARowEngine", &fourInARow);
    qmlRegisterUncreatableType<ChatModel>("McFly.Core", 1, 0, "ChatModel", "Owned by AI");
    // Penguin March's world and pictures (qml/games/PenguinMarch.qml).
    qmlRegisterType<PenguinWorld>("McFly.Core", 1, 0, "PenguinWorld");
    qmlRegisterType<PenguinPicture>("McFly.Core", 1, 0, "PenguinPicture");
    // Color by Number's board and thumbnails (qml/games/ColorByNumber.qml).
    qmlRegisterType<ColorByNumberBoard>("McFly.Core", 1, 0, "ColorByNumberBoard");

    QQmlApplicationEngine engine;
    engine.addImageProvider(QStringLiteral("qr"), new QrImageProvider);
    engine.addImportPath(QStringLiteral("qrc:/"));
    // The on-screen keyboard's style (QtQuick/VirtualKeyboard/Styles/mcfly/).
    engine.addImportPath(QStringLiteral("qrc:/keyboard"));
    engine.rootContext()->setContextProperty("startWindowed", parser.isSet(windowed));
    engine.rootContext()->setContextProperty("startScreen", parser.value(screen));
    const QByteArray benchEnv = qgetenv("MCFLY_BENCH").trimmed().toLower();
    const bool benchByEnv = benchEnv == "1" || benchEnv == "on" || benchEnv == "true" || benchEnv == "yes";
    engine.rootContext()->setContextProperty("startBench", parser.isSet(bench) || benchByEnv);
    engine.rootContext()->setContextProperty("quitAfterBench", parser.isSet(bench));
    // --size: the panel being designed for, in logical pixels.
    QSize startSize(1280, 800);
    const QStringList wh = parser.value(size).split(QLatin1Char('x'));
    if (wh.size() == 2 && wh.at(0).toInt() > 0 && wh.at(1).toInt() > 0)
        startSize = QSize(wh.at(0).toInt(), wh.at(1).toInt());
    engine.rootContext()->setContextProperty("startWidth", startSize.width());
    engine.rootContext()->setContextProperty("startHeight", startSize.height());

    const QUrl mainUrl(QStringLiteral("qrc:/McFly/qml/Main.qml"));
    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreated, &app,
        [mainUrl](QObject *obj, const QUrl &objUrl) {
            if (!obj && objUrl == mainUrl)
                QCoreApplication::exit(1);
        },
        Qt::QueuedConnection);
    engine.load(mainUrl);
    reportGraphics(engine);
    perf.attach(qobject_cast<QQuickWindow *>(engine.rootObjects().value(0)));

    store.start();
    voice.start();

    // --screenshot: for docs and checks. Taken once the data and the first
    // frames are in, then the app quits.
    if (parser.isSet(screenshot)) {
        const QString file = parser.value(screenshot);
        QTimer::singleShot(2500, &app, [&engine, file]() {
            auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().value(0));
            const bool ok = window && window->grabWindow().save(file);
            if (!ok)
                qCritical("McFly display: could not save %s", qUtf8Printable(file));
            QCoreApplication::exit(ok ? 0 : 1);
        });
    }

    // NetworkManager says when Wi-Fi has joined: sync then (after a reboot,
    // the app is up first). Without it (no D-Bus, a container), the store's
    // retries find the network a little later.
    if (QNetworkInformation::loadBackendByFeatures(QNetworkInformation::Feature::Reachability)) {
        QObject::connect(QNetworkInformation::instance(), &QNetworkInformation::reachabilityChanged, &store,
                         [&store](QNetworkInformation::Reachability reachability) {
                             if (reachability == QNetworkInformation::Reachability::Online
                                 || reachability == QNetworkInformation::Reachability::Site)
                                 store.networkUp();
                         });
    }
    return app.exec();
}
