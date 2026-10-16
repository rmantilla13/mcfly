#include "hardware/DisplayController.h"

#include <QSettings>
#include <QtTest>

// Display preferences remembered in QSettings, and when the screen goes idle
// and off. The settings sheet binds its Dark mode and Sleep controls to
// DisplayController.
class tst_Display : public QObject
{
    Q_OBJECT

    // What a touch looks like to the event filter: only the type matters.
    static bool touch(QObject *target)
    {
        QEvent press(QEvent::MouseButtonPress);
        return QCoreApplication::sendEvent(target, &press);
    }

private slots:
    void initTestCase()
    {
        QCoreApplication::setOrganizationName(QStringLiteral("McFly-tests"));
        QCoreApplication::setApplicationName(QStringLiteral("tst_display"));
    }

    // Each test starts from the defaults.
    void init() { QSettings().clear(); }

    void cleanupTestCase() { QSettings().clear(); }

    void darkModeDefaultsOffAndIsRemembered()
    {
        {
            DisplayController device;
            QVERIFY(!device.darkMode());
            device.setDarkMode(true);
            QVERIFY(device.darkMode());
            QCOMPARE(QSettings().value(QStringLiteral("display/darkMode")).toBool(), true);
        }
        {
            DisplayController again;
            QVERIFY(again.darkMode());
            again.setDarkMode(false);
        }
        DisplayController third;
        QVERIFY(!third.darkMode());
    }

    // Media → Screen saver → Collage: a pinned layout stays across restarts;
    // anything but the known names is refused.
    void collageLayoutDefaultsToAutoAndIsRemembered()
    {
        {
            DisplayController device;
            QCOMPARE(device.collageLayout(), QStringLiteral("auto"));
            device.setCollageLayout(QStringLiteral("mosaic"));
            device.setCollageLayout(QStringLiteral("hexagons"));
            QCOMPARE(device.collageLayout(), QStringLiteral("mosaic"));
        }
        DisplayController again;
        QCOMPARE(again.collageLayout(), QStringLiteral("mosaic"));
        again.setCollageLayout(QStringLiteral("auto"));
    }

    // Settings → Backdrop: the savers' sky stays across restarts; anything
    // but the known names is refused, and the mesh is what every display
    // showed before there was a choice.
    void backdropDefaultsToMeshAndIsRemembered()
    {
        {
            DisplayController device;
            QCOMPARE(device.backdrop(), QStringLiteral("mesh"));
            QCOMPARE(DisplayController::backdrops().first(), QStringLiteral("mesh"));
            device.setBackdrop(QStringLiteral("dawn"));
            device.setBackdrop(QStringLiteral("disco"));
            QCOMPARE(device.backdrop(), QStringLiteral("dawn"));
        }
        DisplayController again;
        QCOMPARE(again.backdrop(), QStringLiteral("dawn"));
        again.setBackdrop(QStringLiteral("mesh"));
    }

    // Settings → Weather: off until it is picked, remembered, and only the
    // known names; what falls today follows it at once.
    void weatherDefaultsToOffAndIsRemembered()
    {
        {
            DisplayController device;
            QCOMPARE(device.weather(), QStringLiteral("off"));
            QCOMPARE(device.weatherKind(), QString());
            QCOMPARE(DisplayController::weathers().first(), QStringLiteral("off"));
            QSignalSpy kind(&device, &DisplayController::weatherKindChanged);
            device.setWeather(QStringLiteral("fireflies"));
            device.setWeather(QStringLiteral("rain"));
            QCOMPARE(device.weather(), QStringLiteral("fireflies"));
            QCOMPARE(device.weatherKind(), QStringLiteral("fireflies"));
            QCOMPARE(kind.size(), 1);
        }
        DisplayController again;
        QCOMPARE(again.weather(), QStringLiteral("fireflies"));
        again.setWeather(QStringLiteral("off"));
        QCOMPARE(again.weatherKind(), QString());
    }

    // Seasons are whole months; the south has the north's six months on
    // (the console's and the app's tests have the same cases).
    void seasonsByMonthAndHemisphere()
    {
        QStringList north;
        for (int m = 1; m <= 12; ++m)
            north << DisplayController::seasonFor(QDate(2026, m, 15), false);
        QCOMPARE(north, (QStringList{"winter", "winter", "spring", "spring", "spring", "summer",
                                     "summer", "summer", "autumn", "autumn", "autumn", "winter"}));
        QCOMPARE(DisplayController::seasonFor(QDate(2026, 12, 25), true), QStringLiteral("summer"));
        QCOMPARE(DisplayController::seasonFor(QDate(2026, 7, 4), true), QStringLiteral("winter"));
        QCOMPARE(DisplayController::seasonFor(QDate(2026, 10, 16), true), QStringLiteral("spring"));
        QCOMPARE(DisplayController::seasonFor(QDate(2026, 4, 1), true), QStringLiteral("autumn"));
        QCOMPARE(DisplayController::seasonFor(QDate(2026, 11, 30), false), QStringLiteral("autumn"));
        QCOMPARE(DisplayController::seasonFor(QDate(2026, 12, 1), false), QStringLiteral("winter"));
        for (const char *zone : {"Australia/Sydney", "Pacific/Auckland", "America/Argentina/Buenos_Aires",
                                 "America/Santiago", "America/Sao_Paulo", "Africa/Johannesburg", "Antarctica/McMurdo"})
            QVERIFY2(DisplayController::southernZone(zone), zone);
        for (const char *zone : {"America/Chicago", "Europe/London", "Asia/Tokyo", "Africa/Cairo", "America/Bogota", "UTC", ""})
            QVERIFY2(!DisplayController::southernZone(zone), zone);
    }

    void seasonalWeatherIsTheSeasonsWhereTheDisplayIs()
    {
        QCOMPARE(DisplayController::weatherFor("season", QDate(2026, 12, 20), "America/Chicago"), QStringLiteral("snow"));
        QCOMPARE(DisplayController::weatherFor("season", QDate(2026, 12, 20), "Australia/Sydney"), QStringLiteral("fireflies"));
        QCOMPARE(DisplayController::weatherFor("season", QDate(2026, 4, 20), "America/Chicago"), QStringLiteral("petals"));
        QCOMPARE(DisplayController::weatherFor("season", QDate(2026, 4, 20), "Australia/Sydney"), QStringLiteral("leaves"));
        QCOMPARE(DisplayController::weatherFor("season", QDate(2026, 10, 16), "America/Chicago"), QStringLiteral("leaves"));
        for (const char *kind : {"snow", "petals", "fireflies", "leaves"})
            QCOMPARE(DisplayController::weatherFor(kind, QDate(2026, 1, 1), "America/Chicago"), QString::fromLatin1(kind));
        QCOMPARE(DisplayController::weatherFor("off", QDate(2026, 1, 1), "America/Chicago"), QString());
        QCOMPARE(DisplayController::weatherFor("rain", QDate(2026, 1, 1), "America/Chicago"), QString());
    }

    // A small screen gets a few, a big one is not crowded: the web's numbers.
    void weatherCountsScaleWithTheScreenWithinBounds()
    {
        for (const char *kind : {"snow", "petals", "fireflies", "leaves"}) {
            const int phone = DisplayController::weatherCount(kind, 390, 844);
            const int laptop = DisplayController::weatherCount(kind, 1440, 900);
            const int huge = DisplayController::weatherCount(kind, 5120, 2880);
            QVERIFY2(phone > 0 && phone <= laptop && laptop <= huge, kind);
            QCOMPARE(DisplayController::weatherCount(kind, 0, 0), DisplayController::weatherCount(kind, 1, 1));
            QCOMPARE(huge, DisplayController::weatherCount(kind, 20000, 20000));
            QVERIFY(huge <= 44);
        }
        QCOMPARE(DisplayController::weatherCount("snow", 1440, 900), 44);
        QCOMPARE(DisplayController::weatherCount("petals", 1440, 900), 18);
        QCOMPARE(DisplayController::weatherCount("fireflies", 1440, 900), 20);
        QCOMPARE(DisplayController::weatherCount("leaves", 1440, 900), 14);
        QCOMPARE(DisplayController::weatherCount("rain", 1440, 900), 0);
    }

    // A playing video calls keepAwake(): it holds off the photo frame like a
    // touch would, but never wakes a screen that has already gone idle.
    void keepAwakeOnlyWhileAwake()
    {
        DisplayController device;
        device.setIdleTimeoutSec(1);
        QVERIFY(!device.idle());
        QElapsedTimer playing;
        playing.start();
        while (playing.elapsed() < 2500) {
            device.keepAwake();
            QTest::qWait(200);
            QVERIFY(!device.idle());
        }
        // Stopped: idle a second later.
        QTRY_VERIFY_WITH_TIMEOUT(device.idle(), 3000);
        device.keepAwake();
        QVERIFY(device.idle());
        QTest::qWait(100);
        QVERIFY(device.idle());
        // A touch still wakes it.
        device.wake();
        QVERIFY(!device.idle());
    }

    void sleepIsOffByDefault()
    {
        DisplayController device;
        QCOMPARE(device.offAfterSec(), 0);
        QVERIFY(!device.offAtNight());
        QCOMPARE(device.bedtime(), 22 * 60);
        QCOMPARE(device.wakeTime(), 6 * 60 + 30);
        QVERIFY(!device.screenOff());
    }

    // Screen saver after the idle time, then off after the sleep time, both
    // counted from the last touch. The touch that wakes it is swallowed.
    void sleepTurnsTheScreenOffAndATouchWakesIt()
    {
        DisplayController device;
        QObject target;
        target.installEventFilter(&device);
        device.setIdleTimeoutSec(1);
        device.setOffAfterSec(2);
        QSignalSpy offChanged(&device, &DisplayController::screenOffChanged);

        QTRY_VERIFY_WITH_TIMEOUT(device.idle(), 2000);
        QVERIFY(!device.screenOff());
        QTRY_VERIFY_WITH_TIMEOUT(device.screenOff(), 3000);
        QVERIFY(device.idle());
        QCOMPARE(offChanged.count(), 1);

        QVERIFY(touch(&target)); // swallowed: it doesn't press what's underneath
        QVERIFY(!device.screenOff());
        QVERIFY(!device.idle());
        QVERIFY(!touch(&target)); // awake: touches go through

        // Touches keep it on.
        QElapsedTimer inUse;
        inUse.start();
        while (inUse.elapsed() < 3000) {
            touch(&target);
            QTest::qWait(200);
            QVERIFY(!device.screenOff());
        }

        // Never: the screen saver stays up.
        device.setOffAfterSec(0);
        QTRY_VERIFY_WITH_TIMEOUT(device.idle(), 2000);
        QTest::qWait(2500);
        QVERIFY(!device.screenOff());
    }

    void sleepSettingsAreRemembered()
    {
        {
            DisplayController device;
            device.setOffAfterSec(1800);
            device.setOffAtNight(true);
            device.setBedtime(-30);          // wraps to 11:30 PM
            device.setWakeTime(24 * 60 + 15); // wraps to 12:15 AM
            device.setOffAfterSec(-5);       // clamped to never
            device.setOffAfterSec(1800);
        }
        DisplayController again;
        QCOMPARE(again.offAfterSec(), 1800);
        QVERIFY(again.offAtNight());
        QCOMPARE(again.bedtime(), 23 * 60 + 30);
        QCOMPARE(again.wakeTime(), 15);
    }

    void turnOffNowUntilATouch()
    {
        DisplayController device;
        device.turnOffNow();
        QVERIFY(device.screenOff());
        QVERIFY(device.idle());
        // A playing video doesn't turn it back on.
        device.keepAwake();
        QVERIFY(device.screenOff());
        device.wake();
        QVERIFY(!device.screenOff());
        QVERIFY(!device.idle());
    }

    void windowWrapsPastMidnight()
    {
        QVERIFY(DisplayController::inWindow(23 * 60, 22 * 60, 6 * 60));
        QVERIFY(DisplayController::inWindow(0, 22 * 60, 6 * 60));
        QVERIFY(DisplayController::inWindow(22 * 60, 22 * 60, 6 * 60));
        QVERIFY(!DisplayController::inWindow(6 * 60, 22 * 60, 6 * 60));
        QVERIFY(!DisplayController::inWindow(12 * 60, 22 * 60, 6 * 60));
        QVERIFY(DisplayController::inWindow(14 * 60, 13 * 60, 15 * 60));
        QVERIFY(!DisplayController::inWindow(15 * 60, 13 * 60, 15 * 60));
        QVERIFY(!DisplayController::inWindow(12 * 60, 12 * 60, 12 * 60));
    }

    // Off overnight: the screen saver goes off at bedtime and comes back at
    // wake time. Someone using the screen at bedtime keeps it until they stop.
    void overnightScheduleTurnsOffAndBackOn()
    {
        DisplayController device;
        device.setOffAtNight(true); // 10:00 PM to 6:30 AM
        device.applySchedule(QTime(12, 0));

        device.sleepNow(); // the screen saver is up
        device.applySchedule(QTime(21, 59));
        QVERIFY(!device.screenOff());
        device.applySchedule(QTime(22, 0));
        QVERIFY(device.screenOff());
        device.applySchedule(QTime(3, 0));
        QVERIFY(device.screenOff());
        device.applySchedule(QTime(6, 30));
        QVERIFY(!device.screenOff());
        QVERIFY(device.idle()); // back to the screen saver

        // In use at bedtime: stays on, then goes straight off when left alone.
        device.setIdleTimeoutSec(1);
        device.wake();
        device.applySchedule(QTime(22, 0));
        QVERIFY(!device.screenOff());
        QTRY_VERIFY_WITH_TIMEOUT(device.screenOff(), 2000);

        // A tap at night wakes it; left alone, it goes off again.
        device.wake();
        QVERIFY(!device.screenOff());
        QTRY_VERIFY_WITH_TIMEOUT(device.screenOff(), 2000);

        // Turned off, the schedule leaves the screen alone.
        device.wake();
        device.setOffAtNight(false);
        device.applySchedule(QTime(23, 0));
        QTRY_VERIFY_WITH_TIMEOUT(device.idle(), 2000);
        QVERIFY(!device.screenOff());
    }

    // Wake time also brings back a screen the sleep timer turned off, and
    // the sleep timer then runs again.
    void wakeTimeRestartsTheSleepTimer()
    {
        DisplayController device;
        device.setOffAtNight(true);
        device.applySchedule(QTime(12, 0));
        device.applySchedule(QTime(23, 0));
        device.turnOffNow();
        device.setOffAfterSec(1);
        device.applySchedule(QTime(6, 30));
        QVERIFY(!device.screenOff());
        QTRY_VERIFY_WITH_TIMEOUT(device.screenOff(), 2000);
    }
};

QTEST_GUILESS_MAIN(tst_Display)
#include "tst_display.moc"
