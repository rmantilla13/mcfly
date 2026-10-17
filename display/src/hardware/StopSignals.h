#pragma once

#include <QObject>

class QSocketNotifier;

// Turns a stop into a normal quit: SIGTERM (systemctl stop or restart) and
// SIGINT (Ctrl+C on the console).
//
// On the Pi, Qt's eglfs platform (and linuxfb) catches both signals itself
// (QFbVtHandler) and ends the process at once with _exit(1). systemd then
// logs every stop as a failure, and no destructor runs. This takes the two
// signals back. Create it after the QGuiApplication, whose constructor
// installs Qt's handler, and quit on stopRequested: the app then leaves
// exec() and exits 0 through its destructors, Qt's own handing the keyboard
// and cursor back to the console as its _exit path did.
//
// The handler only writes the signal's number to a socket; stopRequested is
// emitted from the event loop. Other signals keep Qt's handlers (Ctrl+Z).
// One at a time; once it is gone, the two signals have their default action.
class StopSignals : public QObject
{
    Q_OBJECT

public:
    explicit StopSignals(QObject *parent = nullptr);
    ~StopSignals() override;

signals:
    void stopRequested(int signal);

private:
    void readSignal();

    QSocketNotifier *m_notifier = nullptr;
};
