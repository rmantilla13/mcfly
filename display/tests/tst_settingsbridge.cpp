#include <QtTest>

#include <QSettings>
#include <QSignalSpy>

#include "hardware/DisplayController.h"
#include "models/SettingsBridge.h"

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
