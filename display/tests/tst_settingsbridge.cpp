#include <QtTest>

#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkProxy>
#include <QSettings>
#include <QSignalSpy>
#include <QWebSocket>
#include <QWebSocketServer>

#include "hardware/DisplayController.h"
#include "models/SettingsBridge.h"
#include "voice/VoiceClient.h"

// The display's settings and the server's copy: applied from the server,
// local changes sent back as a debounced patch, the first empty copy filled
// from the display. (Assistant and voice are covered by their own tests.)
class TestSettingsBridge : public QObject
{
    Q_OBJECT

private slots:
    void initTestCase()
    {
        QCoreApplication::setOrganizationName("McFlyTest");
        QCoreApplication::setApplicationName("settingsbridge");
    }
    void init() { QSettings().clear(); }

    void changedComparesByValue()
    {
        const QVariantMap local{{"idleSeconds", 120}, {"darkMode", true}, {"screensaver", "clock"}};
        const QVariantMap server{{"idleSeconds", 120.0}, {"darkMode", true}, {"screensaver", "ambient"}};
        QCOMPARE(SettingsBridge::changed(local, server), (QVariantMap{{"screensaver", "clock"}}));
        QCOMPARE(SettingsBridge::changed(local, {}).size(), 3);
    }

    void firstEmptyCopyIsFilledFromTheDisplay()
    {
        DisplayController display;
        SettingsBridge bridge(nullptr, &display, nullptr, nullptr);
        QSignalSpy pushed(&bridge, &SettingsBridge::push);
        bridge.receive({});
        QCOMPARE(pushed.size(), 1);
        const QVariantMap sent = pushed.first().first().toMap();
        QCOMPARE(sent.value("screensaver").toString(), display.screensaver());
        QVERIFY(sent.contains("idleSeconds") && sent.contains("bedtime") && sent.contains("darkMode"));
        QCOMPARE(sent.value("backdrop").toString(), display.backdrop());
        QCOMPARE(sent.value("homeLayout").toString(), display.homeLayout());
        // An empty copy later (say, the admin cleared it) is not refilled.
        bridge.receive({});
        QCOMPARE(pushed.size(), 1);
    }

    void serverSettingsApplyWithoutEchoing()
    {
        DisplayController display;
        SettingsBridge bridge(nullptr, &display, nullptr, nullptr);
        QSignalSpy pushed(&bridge, &SettingsBridge::push);
        QVariantMap server = bridge.collect();
        server.insert("screensaver", "clock");
        server.insert("darkMode", true);
        server.insert("idleSeconds", 300.0);
        server.insert("backdrop", "silk");
        server.insert("homeLayout", "bento");
        bridge.receive(server);
        QCOMPARE(display.screensaver(), QStringLiteral("clock"));
        QCOMPARE(display.backdrop(), QStringLiteral("silk"));
        QCOMPARE(display.homeLayout(), QStringLiteral("bento"));
        QVERIFY(display.darkMode());
        QCOMPARE(display.idleTimeoutSec(), 300);
        QTest::qWait(1800);
        QCOMPARE(pushed.size(), 0); // applying isn't a local change
    }

    void unknownHomeLayoutIsIgnored()
    {
        DisplayController display;
        SettingsBridge bridge(nullptr, &display, nullptr, nullptr);
        const QString before = display.homeLayout();
        QVariantMap server = bridge.collect();
        server.insert("homeLayout", "masonry"); // a newer console's layout this build doesn't have
        bridge.receive(server);
        QCOMPARE(display.homeLayout(), before);
        display.setHomeLayout("assistant");
        QCOMPARE(display.homeLayout(), QStringLiteral("assistant"));
        display.setHomeLayout("today");
    }

    void localChangesGoUpAsOnePatch()
    {
        DisplayController display;
        SettingsBridge bridge(nullptr, &display, nullptr, nullptr);
        QSignalSpy pushed(&bridge, &SettingsBridge::push);
        bridge.receive(bridge.collect());
        QCOMPARE(pushed.size(), 0);
        display.setScreensaver(display.screensaver() == QLatin1String("clock") ? "headlines" : "clock");
        display.setDarkMode(!display.darkMode());
        QTRY_COMPARE_WITH_TIMEOUT(pushed.size(), 1, 3000);
        const QVariantMap patch = pushed.first().first().toMap();
        QCOMPARE(patch.size(), 2);
        QVERIFY(patch.contains("screensaver") && patch.contains("darkMode"));
    }

    void aVoiceServiceComingBackTakesTheServersVoice()
    {
        // The voice is the account's: one picked on the phone while the voice
        // service was away reaches it when it's back, and what it ran before
        // isn't sent up over it.
        QNetworkProxy::setApplicationProxy(QNetworkProxy::NoProxy);
        QWebSocketServer service("fake-voice", QWebSocketServer::NonSecureMode);
        QVERIFY(service.listen(QHostAddress::LocalHost));
        QPointer<QWebSocket> peer;
        QString running = "af_heart"; // what the service ran before it went away
        auto hello = [&]() {
            const QJsonObject o{{"type", "hello"}, {"version", "1"}, {"wakeword", true}, {"tts", true}, {"stt", true},
                                {"voice", running}, {"speed", 1.0}, {"wakeword_model", "hey_jarvis"}};
            peer->sendTextMessage(QString::fromUtf8(QJsonDocument(o).toJson(QJsonDocument::Compact)));
        };
        connect(&service, &QWebSocketServer::newConnection, this, [&]() {
            peer = service.nextPendingConnection();
            connect(peer, &QWebSocket::textMessageReceived, this, [&](const QString &t) {
                const QJsonObject m = QJsonDocument::fromJson(t.toUtf8()).object();
                if (m.value("type").toString() != QLatin1String("set"))
                    return;
                if (m.contains("voice"))
                    running = m.value("voice").toString();
                hello(); // the service answers a set with a fresh hello
            });
            hello();
        });

        DisplayController display;
        VoiceClient voice(QUrl(QStringLiteral("ws://127.0.0.1:%1").arg(service.serverPort())));
        voice.setRetryInterval(200);
        SettingsBridge bridge(nullptr, &display, nullptr, &voice);
        QSignalSpy pushed(&bridge, &SettingsBridge::push);
        QVariantMap server = bridge.collect(); // the service isn't there yet: no voice keys
        server.insert("voice", "am_fenrir");
        server.insert("voiceSpeed", 1.0);
        server.insert("wakewordModel", "hey_jarvis");
        server.insert("wakeword", true);
        bridge.receive(server);

        voice.start();
        QTRY_COMPARE(voice.voiceId(), QStringLiteral("am_fenrir"));
        QCOMPARE(running, QStringLiteral("am_fenrir"));
        QTest::qWait(1800);
        for (const QList<QVariant> &p : std::as_const(pushed))
            QVERIFY2(!p.first().toMap().contains("voice"), "the old voice was sent over the account's");

        // Picked on the display itself later: that one goes up.
        voice.setVoiceOptions("af_bella", 0.0, {});
        QTRY_COMPARE_WITH_TIMEOUT(pushed.size() > 0 && pushed.last().first().toMap().value("voice") == QVariant("af_bella"), true, 3000);
    }

    void keysTheServerLacksAreAdded()
    {
        DisplayController display;
        SettingsBridge bridge(nullptr, &display, nullptr, nullptr);
        QSignalSpy pushed(&bridge, &SettingsBridge::push);
        bridge.receive({{"screensaver", "clock"}});
        QCOMPARE(pushed.size(), 1);
        const QVariantMap added = pushed.first().first().toMap();
        QVERIFY(!added.contains("screensaver"));
        QVERIFY(added.contains("darkMode"));
    }
};

QTEST_MAIN(TestSettingsBridge)
#include "tst_settingsbridge.moc"
