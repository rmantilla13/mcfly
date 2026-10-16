#pragma once

#include <QElapsedTimer>
#include <QObject>
#include <QPointer>
#include <QProcess>
#include <QQuickWindow> // QPointer needs the whole type (GCC 14, Qt 6.8 on the Pi)
#include <QString>
#include <QStringList>
#include <QTimer>

#include <atomic>

// The performance overlay's numbers (MCFLY_PERF_HUD=1, for development):
// how fast the window draws and what it costs, sampled once a second.
//
//   fps        frames the window swapped in the last second
//   frameMs    their average work on the render thread, sync to the end of
//              rendering (not the wait for the panel's refresh), and the
//              longest of them (frameMaxMs)
//   cpu        this process, % of one core; rssMb its memory
//   gpuBusy    the share of the second the GPU spent rendering, and gpuJobs
//              its render jobs (a frame each, plus each cached layer redrawn),
//              from the V3D's own counters on a Pi (-1 elsewhere)
//   tempC      the SoC (-1 where there is no thermal zone); cpuMhz the clock
//   throttle   vcgencmd get_throttled: "ok", or what holds the Pi back now
//              (HOT soft temperature limit, CAP clock capped, THR throttled,
//              UV under-voltage), with what happened since boot after it
//
// Settings → Admin turns it on and off, remembered on this display
// (display/perfHud); MCFLY_PERF_HUD=1 in /etc/mcfly/display.env turns it on
// at every start (`forced`). Off, it holds no connection to the window and
// runs no timer: nothing is sampled and the overlay's properties never change.
class PerfMonitor : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY enabledChanged)
    // On from MCFLY_PERF_HUD at every start, whatever the switch last said.
    Q_PROPERTY(bool forced READ forced CONSTANT)
    Q_PROPERTY(double fps READ fps NOTIFY sampled)
    Q_PROPERTY(double frameMs READ frameMs NOTIFY sampled)
    Q_PROPERTY(double frameMaxMs READ frameMaxMs NOTIFY sampled)
    Q_PROPERTY(double cpu READ cpu NOTIFY sampled)
    Q_PROPERTY(double rssMb READ rssMb NOTIFY sampled)
    Q_PROPERTY(double gpuBusy READ gpuBusy NOTIFY sampled)
    Q_PROPERTY(double gpuJobs READ gpuJobs NOTIFY sampled)
    Q_PROPERTY(double tempC READ tempC NOTIFY sampled)
    Q_PROPERTY(int cpuMhz READ cpuMhz NOTIFY sampled)
    Q_PROPERTY(QString throttle READ throttle NOTIFY sampled)
    // What the overlay shows, a line each: frames, GPU, process, the Pi.
    Q_PROPERTY(QStringList lines READ lines NOTIFY sampled)
    // Hot (80 °C and up, where the Pi 5 starts slowing itself) or held back now.
    Q_PROPERTY(bool warn READ warn NOTIFY sampled)
    // The GPU's busy time per frame shown, ms (-1 without the V3D's counters):
    // under 16.7 the panel's 60 fps can hold, under 33 its 30.
    Q_PROPERTY(double gpuMsPerFrame READ gpuMsPerFrame NOTIFY sampled)
    // Draw every frame (measuring): each frame asks for the next, so `fps`
    // is what the screen can keep up rather than what it happens to draw.
    // Only while sampling; it turns off with the overlay. Never remembered.
    Q_PROPERTY(bool stress READ stress WRITE setStress NOTIFY stressChanged)

public:
    // On if MCFLY_PERF_HUD is 1, on, true or yes, else as the switch was
    // left; the switch is remembered from then on.
    explicit PerfMonitor(QObject *parent = nullptr);
    // On or off as told, remembering nothing (tests).
    PerfMonitor(bool enabled, QObject *parent);

    // The window to watch: its frames are counted while this is on, from now
    // or from when it is switched on.
    void attach(QQuickWindow *window);
    void setEnabled(bool on);
    // Takes a sample now (tests; the timer calls it every second).
    void sample();

    bool enabled() const { return m_enabled; }
    bool forced() const { return m_forced; }
    bool sampling() const { return m_timer.isActive(); }
    double fps() const { return m_fps; }
    double frameMs() const { return m_frameMs; }
    double frameMaxMs() const { return m_frameMaxMs; }
    double cpu() const { return m_cpu; }
    double rssMb() const { return m_rssMb; }
    double gpuBusy() const { return m_gpuBusy; }
    double gpuJobs() const { return m_gpuJobs; }
    double tempC() const { return m_tempC; }
    int cpuMhz() const { return m_cpuMhz; }
    QString throttle() const { return m_throttle; }
    QStringList lines() const { return m_lines; }
    bool warn() const { return m_warn; }
    double gpuMsPerFrame() const { return m_gpuMsPerFrame; }
    bool stress() const { return m_stress; }
    void setStress(bool on);

    // ---- The files, read (public for the tests' fixtures).
    // /proc/<pid>/status: VmRSS, kB; -1 if missing.
    static qint64 residentKb(const QByteArray &status);
    // The V3D's gpu_stats: the render queue's jobs and busy time (ns).
    static bool gpuRender(const QByteArray &gpuStats, qint64 *jobs, qint64 *runtimeNs);
    // A thermal zone's temp (millidegrees): °C, or -1.
    static double celsius(const QByteArray &milli);
    // vcgencmd get_throttled ("throttled=0xe0006"): "ok", "HOT+CAP", and
    // "ok · was HOT+THR" when only the since-boot bits are set; "" if unknown.
    static QString throttleText(const QByteArray &vcgencmd);

signals:
    void sampled();
    void enabledChanged();
    void stressChanged();

private:
    void start();
    void stop();
    void startStress();
    void readThrottle();

    bool m_enabled = false;
    bool m_forced = false;
    bool m_persist = false;     // the switch is saved (not in tests)
    QList<QMetaObject::Connection> m_connections;
    QPointer<QQuickWindow> m_window;
    QTimer m_timer;
    QElapsedTimer m_clock;      // monotonic, for the frame timings and the second
    QProcess *m_vcgencmd = nullptr;
    QString m_gpuStatsPath;

    // Written on the render thread (or the GUI thread, with the basic loop).
    std::atomic<qint64> m_frames{0};
    std::atomic<qint64> m_frameNs{0};
    std::atomic<qint64> m_frameMaxNs{0};
    std::atomic<qint64> m_syncStartNs{-1};

    qint64 m_lastSampleNs = 0;
    double m_lastCpuSeconds = -1;
    qint64 m_lastGpuJobs = -1;
    qint64 m_lastGpuRuntime = -1;

    double m_fps = 0;
    double m_frameMs = 0;
    double m_frameMaxMs = 0;
    double m_cpu = 0;
    double m_rssMb = 0;
    double m_gpuBusy = -1;
    double m_gpuJobs = -1;
    double m_tempC = -1;
    int m_cpuMhz = -1;
    QString m_throttle;
    QStringList m_lines;
    bool m_warn = false;
    double m_gpuMsPerFrame = -1;
    bool m_stress = false;
    QMetaObject::Connection m_stressConnection;
};
