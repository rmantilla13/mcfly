#include "StopSignals.h"

#include <QSocketNotifier>

#include <cerrno>
#include <csignal>
#include <cstring>
#include <fcntl.h>
#include <sys/socket.h>
#include <unistd.h>

namespace {
constexpr int kSignals[] = {SIGTERM, SIGINT};

// [0] is written by the handler, [1] read by the notifier.
int s_fds[2] = {-1, -1};

// Async-signal-safe: one byte to the socket, errno left as it was.
void onStopSignal(int signal)
{
    const int savedErrno = errno;
    const char byte = char(signal);
    [[maybe_unused]] const ssize_t written = ::write(s_fds[0], &byte, 1);
    errno = savedErrno;
}

// Children (SystemController's helpers) do not inherit the socket.
void closeOnExec(int fd)
{
    ::fcntl(fd, F_SETFD, ::fcntl(fd, F_GETFD) | FD_CLOEXEC);
}
} // namespace

StopSignals::StopSignals(QObject *parent)
    : QObject(parent)
{
    if (s_fds[0] != -1) {
        qWarning("McFly display: StopSignals already exists; this one does nothing");
        return;
    }
    if (::socketpair(AF_UNIX, SOCK_STREAM, 0, s_fds) != 0) {
        qWarning("McFly display: socketpair failed (%s); a stop signal keeps Qt's handling",
                 strerror(errno));
        s_fds[0] = s_fds[1] = -1;
        return;
    }
    closeOnExec(s_fds[0]);
    closeOnExec(s_fds[1]);
    // A burst of signals must never block the handler.
    ::fcntl(s_fds[0], F_SETFL, ::fcntl(s_fds[0], F_GETFL) | O_NONBLOCK);

    m_notifier = new QSocketNotifier(s_fds[1], QSocketNotifier::Read, this);
    connect(m_notifier, &QSocketNotifier::activated, this, &StopSignals::readSignal);

    struct sigaction action = {};
    action.sa_handler = onStopSignal;
    sigemptyset(&action.sa_mask);
    action.sa_flags = SA_RESTART;
    for (int signal : kSignals)
        ::sigaction(signal, &action, nullptr);
}

StopSignals::~StopSignals()
{
    if (!m_notifier)
        return;
    for (int signal : kSignals)
        ::signal(signal, SIG_DFL);
    delete m_notifier;
    ::close(s_fds[0]);
    ::close(s_fds[1]);
    s_fds[0] = s_fds[1] = -1;
}

void StopSignals::readSignal()
{
    char byte = 0;
    if (::read(s_fds[1], &byte, 1) == 1)
        emit stopRequested(byte);
}
