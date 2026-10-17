#include "hardware/StopSignals.h"

#include <QSignalSpy>
#include <QTest>

#include <csignal>
#include <unistd.h>

namespace {
// What Qt's eglfs and linuxfb platforms install (QFbVtHandler::handleInt):
// the process ends at once with 1. Reaching it fails the whole test run.
void qtVtHandler(int)
{
    _exit(1);
}

void install(int signal, void (*handler)(int))
{
    struct sigaction action = {};
    action.sa_handler = handler;
    sigemptyset(&action.sa_mask);
    ::sigaction(signal, &action, nullptr);
}

void (*handlerOf(int signal))(int)
{
    struct sigaction action = {};
    ::sigaction(signal, nullptr, &action);
    return action.sa_handler;
}
} // namespace

class TestStopSignals : public QObject
{
    Q_OBJECT

private slots:
    void stopSignalIsAQuitRequest_data();
    void stopSignalIsAQuitRequest();
    void everySignalIsReported();
    void ctrlZKeepsItsHandler();
    void defaultActionOnceGone();
};

void TestStopSignals::stopSignalIsAQuitRequest_data()
{
    QTest::addColumn<int>("signal");
    QTest::newRow("systemctl stop") << int(SIGTERM);
    QTest::newRow("Ctrl+C") << int(SIGINT);
}

// The app's own handler wins over the one Qt installed before it, and the
// signal arrives on the event loop.
void TestStopSignals::stopSignalIsAQuitRequest()
{
    QFETCH(int, signal);
    install(signal, qtVtHandler);
    StopSignals stop;
    QSignalSpy requested(&stop, &StopSignals::stopRequested);

    QCOMPARE(::raise(signal), 0);
    QVERIFY(requested.wait(2000));
    QCOMPARE(requested.size(), 1);
    QCOMPARE(requested.first().first().toInt(), signal);
}

void TestStopSignals::everySignalIsReported()
{
    StopSignals stop;
    QSignalSpy requested(&stop, &StopSignals::stopRequested);

    ::raise(SIGTERM);
    ::raise(SIGINT);
    QTRY_COMPARE(requested.size(), 2);
    QCOMPARE(requested.at(0).first().toInt(), int(SIGTERM));
    QCOMPARE(requested.at(1).first().toInt(), int(SIGINT));
}

// Qt's suspend and resume handling on the console stays as it was.
void TestStopSignals::ctrlZKeepsItsHandler()
{
    install(SIGTSTP, qtVtHandler);
    {
        StopSignals stop;
        QVERIFY(handlerOf(SIGTSTP) == qtVtHandler);
    }
    install(SIGTSTP, SIG_DFL);
}

void TestStopSignals::defaultActionOnceGone()
{
    {
        StopSignals stop;
        QVERIFY(handlerOf(SIGTERM) != SIG_DFL);
    }
    QVERIFY(handlerOf(SIGTERM) == SIG_DFL);
    QVERIFY(handlerOf(SIGINT) == SIG_DFL);

    // And a new one works after the old one is gone.
    StopSignals again;
    QSignalSpy requested(&again, &StopSignals::stopRequested);
    ::raise(SIGTERM);
    QVERIFY(requested.wait(2000));
}

QTEST_GUILESS_MAIN(TestStopSignals)
#include "tst_stopsignals.moc"
