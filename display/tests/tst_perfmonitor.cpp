#include <QtTest>

#include <QQuickItem>
#include <QQuickWindow>

#include "hardware/PerfMonitor.h"

// The performance overlay's sampler: the files it reads on a Pi, from
// fixtures (as a Pi 5 on Raspberry Pi OS Trixie writes them), that off it is
// never attached and never samples, and that on it counts a window's frames.
class TestPerfMonitor : public QObject
{
    Q_OBJECT

private slots:
    void initTestCase()
    {
        QCoreApplication::setOrganizationName("McFly-tests");
        QCoreApplication::setApplicationName("tst_perfmonitor");
        QSettings().clear();
    }
    void cleanupTestCase() { QSettings().clear(); }

    void residentMemoryFromStatus()
    {
        const QByteArray status = "Name:\tmcfly-display\nUmask:\t0022\nState:\tS (sleeping)\n"
                                  "VmPeak:\t 2133420 kB\nVmRSS:\t  241664 kB\nRssAnon:\t  122000 kB\n";
        QCOMPARE(PerfMonitor::residentKb(status), qint64(241664));
        QCOMPARE(PerfMonitor::residentKb("Name:\tx\n"), qint64(-1));
        QCOMPARE(PerfMonitor::residentKb({}), qint64(-1));
    }

    void gpuRenderQueueFromStats()
    {
        const QByteArray stats = "queue\ttimestamp\tjobs\truntime\n"
                                 "bin\t4402732540407\t290996\t94885634724\n"
                                 "render\t4402732540407\t290996\t1499850715793\n"
                                 "tfu\t4402732540407\t0\t0\n"
                                 "csd\t4402732540407\t0\t0\n";
        qint64 jobs = 0, runtime = 0;
        QVERIFY(PerfMonitor::gpuRender(stats, &jobs, &runtime));
        QCOMPARE(jobs, qint64(290996));
        QCOMPARE(runtime, qint64(1499850715793));
        QVERIFY(!PerfMonitor::gpuRender("queue\ttimestamp\tjobs\truntime\nbin\t1\t2\t3\n", &jobs, &runtime));
        QVERIFY(!PerfMonitor::gpuRender("render\t1\tlots\t3\n", &jobs, &runtime));
    }

    void temperatureFromMillidegrees()
    {
        QCOMPARE(PerfMonitor::celsius("74350\n"), 74.35);
        QCOMPARE(PerfMonitor::celsius({}), -1.0);
        QCOMPARE(PerfMonitor::celsius("warm"), -1.0);
    }

    // The bits of vcgencmd get_throttled: what holds the Pi back now, else
    // what did since boot.
    void throttleInWords()
    {
        QCOMPARE(PerfMonitor::throttleText("throttled=0x0\n"), QStringLiteral("ok"));
        QCOMPARE(PerfMonitor::throttleText("throttled=0xe0006\n"), QStringLiteral("CAP+THR"));
        QCOMPARE(PerfMonitor::throttleText("throttled=0xe0008"), QStringLiteral("HOT"));
        QCOMPARE(PerfMonitor::throttleText("throttled=0xe0000"), QStringLiteral("ok · was HOT+CAP+THR"));
        QCOMPARE(PerfMonitor::throttleText("throttled=0x50005"), QStringLiteral("THR+UV"));
        QCOMPARE(PerfMonitor::throttleText("vcgencmd: not found"), QString());
        QCOMPARE(PerfMonitor::throttleText("throttled=zz"), QString());
    }

    // Off (MCFLY_PERF_HUD unset, the switch never turned on): attaching
    // starts nothing, and a sample is never taken, so the overlay's bindings
    // never change.
    void offCostsNothing()
    {
        qunsetenv("MCFLY_PERF_HUD");
        PerfMonitor perf;
        QVERIFY(!perf.enabled());
        QQuickWindow window;
        perf.attach(&window);
        QVERIFY(!perf.sampling());
        QSignalSpy sampled(&perf, &PerfMonitor::sampled);
        perf.sample();
        QCOMPARE(sampled.count(), 0);
        QVERIFY(perf.lines().isEmpty());
        // The variable's spellings.
        for (const char *on : {"1", "on", "TRUE", "yes"}) {
            qputenv("MCFLY_PERF_HUD", on);
            QVERIFY2(PerfMonitor().enabled(), on);
        }
        qputenv("MCFLY_PERF_HUD", "0");
        QVERIFY(!PerfMonitor().enabled());
        qunsetenv("MCFLY_PERF_HUD");
    }

    // On: the frames a window swaps are counted, and the overlay gets its
    // lines once a second (or when asked).
    void onCountsFrames()
    {
        PerfMonitor perf(true, nullptr);
        QQuickWindow window;
        window.resize(200, 120);
        auto *box = new QQuickItem(window.contentItem());
        box->setSize(QSizeF(50, 50));
        window.show();
        QVERIFY(QTest::qWaitForWindowExposed(&window));
        perf.attach(&window);
        QVERIFY(perf.sampling());
        QCOMPARE(perf.lines(), QStringList{QStringLiteral("Measuring…")});
        QSignalSpy sampled(&perf, &PerfMonitor::sampled);
        for (int i = 0; i < 10; ++i) {
            box->setX(i);       // a change, so a frame
            window.update();
            QTest::qWait(30);
        }
        perf.sample();
        QCOMPARE(sampled.count(), 1);
        QVERIFY2(perf.fps() > 0, qPrintable(QString::number(perf.fps())));
        QVERIFY(perf.frameMs() >= 0 && perf.frameMaxMs() >= perf.frameMs());
        QVERIFY(perf.lines().size() >= 2);
        QVERIFY(perf.lines().first().contains(QStringLiteral("fps")));
        // And the timer keeps sampling.
        QTRY_VERIFY_WITH_TIMEOUT(sampled.count() >= 2, 2500);
    }

    // Settings → Admin: the switch turns sampling on and off at once, is
    // remembered for the next start, and MCFLY_PERF_HUD still turns it on
    // at every start whatever the switch was left at.
    void switchesAtRuntimeAndRemembers()
    {
        qunsetenv("MCFLY_PERF_HUD");
        QSettings().clear();
        QQuickWindow window;
        window.resize(200, 120);
        window.show();
        QVERIFY(QTest::qWaitForWindowExposed(&window));
        {
            PerfMonitor perf;
            QVERIFY(!perf.enabled());
            QVERIFY(!perf.forced());
            perf.attach(&window);
            QVERIFY(!perf.sampling());
            QSignalSpy changed(&perf, &PerfMonitor::enabledChanged);
            perf.setEnabled(true);
            QCOMPARE(changed.count(), 1);
            QVERIFY(perf.sampling());
            QCOMPARE(perf.lines(), QStringList{QStringLiteral("Measuring…")});
            perf.setEnabled(true); // no change, no signal
            QCOMPARE(changed.count(), 1);
            perf.setEnabled(false);
            QCOMPARE(changed.count(), 2);
            QVERIFY(!perf.sampling());
            QVERIFY(perf.lines().isEmpty());
            perf.setEnabled(true);
        }
        QVERIFY(PerfMonitor().enabled()); // left on: on at the next start
        {
            PerfMonitor perf;
            perf.setEnabled(false);
        }
        QVERIFY(!PerfMonitor().enabled());
        qputenv("MCFLY_PERF_HUD", "1");
        PerfMonitor forced;
        QVERIFY(forced.enabled());
        QVERIFY(forced.forced());
        qunsetenv("MCFLY_PERF_HUD");
    }
};

QTEST_MAIN(TestPerfMonitor)
#include "tst_perfmonitor.moc"
