#include "PerfMonitor.h"

#include <QDir>
#include <QFile>
#include <QQuickWindow>
#include <QStandardPaths>

#include <sys/resource.h>

namespace {

QByteArray readFile(const QString &path)
{
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly))
        return {};
    return f.readAll(); // sysfs files report size 0: read to the end
}

// This process's CPU time, all threads (the render thread's too), seconds.
double cpuSeconds()
{
    rusage use{};
    if (getrusage(RUSAGE_SELF, &use) != 0)
        return -1;
    return double(use.ru_utime.tv_sec + use.ru_stime.tv_sec) + double(use.ru_utime.tv_usec + use.ru_stime.tv_usec) / 1e6;
}

QString gpuStatsPath()
{
    for (const QString &base : {QStringLiteral("/sys/devices/platform/axi"), QStringLiteral("/sys/devices/platform")}) {
        const QStringList dirs = QDir(base).entryList({QStringLiteral("*v3d*")}, QDir::Dirs);
        for (const QString &dir : dirs) {
            const QString path = base + QLatin1Char('/') + dir + QStringLiteral("/gpu_stats");
            if (QFile::exists(path))
                return path;
        }
    }
    return {};
}

bool enabledByEnvironment()
{
    const QByteArray v = qgetenv("MCFLY_PERF_HUD").trimmed().toLower();
    return v == "1" || v == "on" || v == "true" || v == "yes";
}

} // namespace

PerfMonitor::PerfMonitor(QObject *parent) : PerfMonitor(enabledByEnvironment(), parent) {}

PerfMonitor::PerfMonitor(bool enabled, QObject *parent) : QObject(parent), m_enabled(enabled)
{
    m_timer.setInterval(1000);
    connect(&m_timer, &QTimer::timeout, this, &PerfMonitor::sample);
}

void PerfMonitor::attach(QQuickWindow *window)
{
    if (!m_enabled || !window || m_window)
        return;
    m_window = window;
    m_gpuStatsPath = gpuStatsPath();
    m_clock.start();
    // Emitted on the render thread with the threaded loop: atomics only.
    connect(window, &QQuickWindow::beforeSynchronizing, this, [this]() {
        m_syncStartNs.store(m_clock.nsecsElapsed(), std::memory_order_relaxed);
    }, Qt::DirectConnection);
    connect(window, &QQuickWindow::afterRendering, this, [this]() {
        const qint64 start = m_syncStartNs.exchange(-1, std::memory_order_relaxed);
        if (start < 0)
            return;
        const qint64 ns = m_clock.nsecsElapsed() - start;
        m_frameNs.fetch_add(ns, std::memory_order_relaxed);
        qint64 max = m_frameMaxNs.load(std::memory_order_relaxed);
        while (ns > max && !m_frameMaxNs.compare_exchange_weak(max, ns, std::memory_order_relaxed)) {
        }
    }, Qt::DirectConnection);
    connect(window, &QQuickWindow::frameSwapped, this, [this]() {
        m_frames.fetch_add(1, std::memory_order_relaxed);
    }, Qt::DirectConnection);
    sample(); // the baselines
    m_timer.start();
}

void PerfMonitor::sample()
{
    if (!m_enabled)
        return;
    if (!m_clock.isValid())
        m_clock.start();
    const qint64 now = m_clock.nsecsElapsed();
    const double dt = double(now - m_lastSampleNs) / 1e9;
    const bool first = m_lastSampleNs == 0 || dt <= 0;
    m_lastSampleNs = now;

    const qint64 frames = m_frames.exchange(0, std::memory_order_relaxed);
    const qint64 frameNs = m_frameNs.exchange(0, std::memory_order_relaxed);
    const qint64 maxNs = m_frameMaxNs.exchange(0, std::memory_order_relaxed);
    const double cpuNow = cpuSeconds();

    qint64 jobs = -1, runtime = -1;
    const bool gpu = !m_gpuStatsPath.isEmpty() && gpuRender(readFile(m_gpuStatsPath), &jobs, &runtime);

    if (!first) {
        m_fps = double(frames) / dt;
        m_frameMs = frames > 0 ? double(frameNs) / double(frames) / 1e6 : 0;
        m_frameMaxMs = double(maxNs) / 1e6;
        m_cpu = cpuNow >= 0 && m_lastCpuSeconds >= 0 ? 100 * (cpuNow - m_lastCpuSeconds) / dt : -1;
        if (gpu && m_lastGpuJobs >= 0) {
            m_gpuJobs = double(jobs - m_lastGpuJobs) / dt;
            m_gpuBusy = 100 * double(runtime - m_lastGpuRuntime) / (dt * 1e9);
        }
    }
    m_lastCpuSeconds = cpuNow;
    if (gpu) {
        m_lastGpuJobs = jobs;
        m_lastGpuRuntime = runtime;
    }

    const qint64 rss = residentKb(readFile(QStringLiteral("/proc/self/status")));
    m_rssMb = rss >= 0 ? double(rss) / 1024 : -1;
    m_tempC = celsius(readFile(QStringLiteral("/sys/class/thermal/thermal_zone0/temp")));
    const QByteArray khz = readFile(QStringLiteral("/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq")).trimmed();
    m_cpuMhz = khz.isEmpty() ? -1 : int(khz.toLongLong() / 1000);
    readThrottle();

    const auto num = [](double v, int decimals = 0) { return QString::number(v, 'f', decimals); };
    m_lines.clear();
    m_lines << QStringLiteral("%1 fps · %2 ms (max %3)").arg(num(m_fps), num(m_frameMs, 1), num(m_frameMaxMs, 1));
    if (m_gpuBusy >= 0)
        m_lines << QStringLiteral("GPU %1% · %2 jobs/s").arg(num(m_gpuBusy), num(m_gpuJobs));
    m_lines << QStringLiteral("CPU %1% · %2").arg(m_cpu >= 0 ? num(m_cpu) : QStringLiteral("–"),
                                                  m_rssMb >= 0 ? num(m_rssMb) + QStringLiteral(" MB") : QStringLiteral("–"));
    QStringList pi;
    if (m_tempC >= 0)
        pi << num(m_tempC, 1) + QStringLiteral(" °C");
    if (m_cpuMhz > 0)
        pi << QString::number(m_cpuMhz) + QStringLiteral(" MHz");
    if (!m_throttle.isEmpty())
        pi << m_throttle;
    if (!pi.isEmpty())
        m_lines << pi.join(QStringLiteral(" · "));
    m_warn = m_tempC >= 80 || (!m_throttle.isEmpty() && !m_throttle.startsWith(QStringLiteral("ok")));
    emit sampled();
}

// vcgencmd, off the GUI thread's back: started once a second if it isn't
// still running, its answer shown at the next sample.
void PerfMonitor::readThrottle()
{
    if (m_vcgencmd && m_vcgencmd->state() != QProcess::NotRunning)
        return;
    static const QString program = QStandardPaths::findExecutable(QStringLiteral("vcgencmd"));
    if (program.isEmpty())
        return;
    if (!m_vcgencmd) {
        m_vcgencmd = new QProcess(this);
        connect(m_vcgencmd, &QProcess::finished, this, [this]() {
            m_throttle = throttleText(m_vcgencmd->readAllStandardOutput());
        });
    }
    m_vcgencmd->start(program, {QStringLiteral("get_throttled")});
}

qint64 PerfMonitor::residentKb(const QByteArray &status)
{
    for (const QByteArray &line : status.split('\n')) {
        if (line.startsWith("VmRSS:")) {
            const QList<QByteArray> f = line.simplified().split(' ');
            return f.size() >= 2 ? f.at(1).toLongLong() : -1;
        }
    }
    return -1;
}

bool PerfMonitor::gpuRender(const QByteArray &gpuStats, qint64 *jobs, qint64 *runtimeNs)
{
    // queue  timestamp  jobs  runtime
    for (const QByteArray &line : gpuStats.split('\n')) {
        const QList<QByteArray> f = line.simplified().split(' ');
        if (f.size() >= 4 && f.at(0) == "render") {
            bool okJobs = false, okRuntime = false;
            *jobs = f.at(2).toLongLong(&okJobs);
            *runtimeNs = f.at(3).toLongLong(&okRuntime);
            return okJobs && okRuntime;
        }
    }
    return false;
}

double PerfMonitor::celsius(const QByteArray &milli)
{
    bool ok = false;
    const qint64 v = milli.trimmed().toLongLong(&ok);
    return ok ? double(v) / 1000 : -1;
}

QString PerfMonitor::throttleText(const QByteArray &vcgencmd)
{
    const int eq = vcgencmd.indexOf('=');
    if (eq < 0)
        return {};
    bool ok = false;
    const uint bits = vcgencmd.mid(eq + 1).trimmed().toUInt(&ok, 16);
    if (!ok)
        return {};
    const auto named = [](uint b) {
        QStringList out;
        if (b & 0x8) out << QStringLiteral("HOT");
        if (b & 0x2) out << QStringLiteral("CAP");
        if (b & 0x4) out << QStringLiteral("THR");
        if (b & 0x1) out << QStringLiteral("UV");
        return out.join(QLatin1Char('+'));
    };
    const QString now = named(bits & 0xf);
    const QString ever = named((bits >> 16) & 0xf);
    if (!now.isEmpty())
        return now;
    return ever.isEmpty() ? QStringLiteral("ok") : QStringLiteral("ok · was ") + ever;
}
