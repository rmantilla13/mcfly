#include "DisplayController.h"

#include <QDir>
#include <QEvent>
#include <QFile>
#include <QSet>
#include <QSettings>
#include <QTime>
#include <QTimeZone>

#include <cmath>

namespace {
constexpr int kDefaultIdleSec = 120;
constexpr qreal kNightBrightness = 0.25;
const QTime kNightStart(21, 30);
const QTime kNightEnd(6, 30);
constexpr int kMinutesPerDay = 24 * 60;
constexpr int kSecondsPerDay = kMinutesPerDay * 60;
constexpr int kDefaultBedtime = 22 * 60;        // 10:00 PM
constexpr int kDefaultWakeTime = 6 * 60 + 30;   // 6:30 AM

int wrapMinute(int minute)
{
    return ((minute % kMinutesPerDay) + kMinutesPerDay) % kMinutesPerDay;
}
} // namespace

DisplayController::DisplayController(QObject *parent) : QObject(parent)
{
    const int idleSec = qEnvironmentVariableIntValue("MCFLY_IDLE_SECONDS");
    m_idleTimer.setInterval((idleSec > 0 ? idleSec : kDefaultIdleSec) * 1000);
    m_idleTimer.setSingleShot(true);
    connect(&m_idleTimer, &QTimer::timeout, this, [this]() {
        // Overnight, a screen nobody is using goes off rather than to the screen saver.
        if (m_overnight)
            turnOffNow();
        else
            setIdle(true);
    });
    m_offTimer.setSingleShot(true);
    connect(&m_offTimer, &QTimer::timeout, this, &DisplayController::turnOffNow);

    m_clockTimer.setInterval(60 * 1000);
    connect(&m_clockTimer, &QTimer::timeout, this, [this]() {
        updateNightMode();
        applySchedule(QTime::currentTime());
        refreshWeather();
    });
    m_clockTimer.start();

    if (qEnvironmentVariable("MCFLY_MOOD") == "cycle") {
        m_moodCycle.setInterval(6000);
        connect(&m_moodCycle, &QTimer::timeout, this, [this]() {
            m_cycleIndex = (m_cycleIndex + 1) % 4;
            updateNightMode();
        });
        m_moodCycle.start();
    }

    // MCFLY_SCREENSAVER overrides the saved choice (handy for demos).
    m_screensaver = qEnvironmentVariable("MCFLY_SCREENSAVER");
    if (m_screensaver.isEmpty())
        m_screensaver = QSettings().value("display/screensaver", "ambient").toString();
    // MCFLY_BACKDROP likewise picks the savers' backdrop; a name this build
    // doesn't know is the mesh.
    m_backdrop = qEnvironmentVariable("MCFLY_BACKDROP");
    if (m_backdrop.isEmpty())
        m_backdrop = QSettings().value("display/backdrop", "mesh").toString();
    if (!backdrops().contains(m_backdrop))
        m_backdrop = QStringLiteral("mesh");
    // MCFLY_WEATHER the weather over it; a name this build doesn't know is off.
    m_weather = qEnvironmentVariable("MCFLY_WEATHER");
    if (m_weather.isEmpty())
        m_weather = QSettings().value("display/weather", "off").toString();
    if (!weathers().contains(m_weather))
        m_weather = QStringLiteral("off");
    refreshWeather();
    // MCFLY_HOME_LAYOUT picks Home's layout the same way (screenshots).
    m_homeLayout = qEnvironmentVariable("MCFLY_HOME_LAYOUT");
    if (m_homeLayout.isEmpty())
        m_homeLayout = QSettings().value("display/homeLayout", "today").toString();
    if (!homeLayouts().contains(m_homeLayout))
        m_homeLayout = QStringLiteral("today");
    m_collageLayout = QSettings().value("display/collageLayout", "auto").toString();
    m_animatedTiles = QSettings().value("display/animatedTiles", true).toBool();
    m_darkMode = QSettings().value("display/darkMode", false).toBool();
    m_offAfterSec = qBound(0, QSettings().value("display/offAfterSeconds", 0).toInt(), kSecondsPerDay);
    m_offAtNight = QSettings().value("display/offAtNight", false).toBool();
    m_bedtime = wrapMinute(QSettings().value("display/bedtime", kDefaultBedtime).toInt());
    m_wakeTime = wrapMinute(QSettings().value("display/wakeTime", kDefaultWakeTime).toInt());
    m_overnight = m_offAtNight && inWindow(QTime::currentTime().msecsSinceStartOfDay() / 60000, m_bedtime, m_wakeTime);
    restartTimers();

    const QDir backlights(QStringLiteral("/sys/class/backlight"));
    const QStringList devices = backlights.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    if (!devices.isEmpty()) {
        m_backlightPath = backlights.filePath(devices.first());
        QFile max(m_backlightPath + "/max_brightness");
        if (max.open(QIODevice::ReadOnly))
            m_maxBacklight = max.readAll().trimmed().toInt();
    }
    updateNightMode();
}

void DisplayController::setIdleTimeoutSec(int seconds)
{
    if (seconds <= 0 || seconds == idleTimeoutSec())
        return;
    m_idleTimer.setInterval(seconds * 1000);
    if (!m_idle)
        m_idleTimer.start();
    emit idleTimeoutChanged();
}

void DisplayController::setBrightness(qreal level)
{
    level = qBound<qreal>(0.05, level, 1.0);
    if (qFuzzyCompare(level, m_brightness))
        return;
    m_brightness = level;
    applyBacklight();
    emit brightnessChanged();
}

void DisplayController::wake()
{
    setScreenOff(false);
    setIdle(false);
    restartTimers();
}

void DisplayController::sleepNow()
{
    // Overnight, the preview goes off after the usual idle time. Otherwise
    // the timer finds the screen already idle and does nothing.
    m_idleTimer.start();
    setScreenOff(false);
    setIdle(true);
}

void DisplayController::keepAwake()
{
    if (!m_idle)
        restartTimers();
}

// Activity: the screen saver and sleep both count from now.
void DisplayController::restartTimers()
{
    m_idleTimer.start();
    if (m_offAfterSec > 0)
        m_offTimer.start(m_offAfterSec * 1000);
    else
        m_offTimer.stop();
}

void DisplayController::turnOffNow()
{
    m_idleTimer.stop();
    m_offTimer.stop();
    setIdle(true);
    setScreenOff(true);
}

void DisplayController::applySchedule(const QTime &now)
{
    const bool overnight = m_offAtNight && inWindow(now.msecsSinceStartOfDay() / 60000, m_bedtime, m_wakeTime);
    if (overnight == m_overnight)
        return;
    m_overnight = overnight;
    if (overnight) {
        // Bedtime: the screen saver goes off. Someone using the screen keeps
        // it; it goes off once they leave it (the idle timer).
        if (m_idle)
            turnOffNow();
    } else if (m_screenOff) {
        // Wake time: back to the screen saver, which sleeps again after the
        // usual time if nobody touches it.
        setScreenOff(false);
        if (m_offAfterSec > 0)
            m_offTimer.start(m_offAfterSec * 1000);
    }
}

bool DisplayController::inWindow(int minuteOfDay, int start, int end)
{
    if (start == end)
        return false;
    if (start < end)
        return minuteOfDay >= start && minuteOfDay < end;
    return minuteOfDay >= start || minuteOfDay < end;
}

bool DisplayController::eventFilter(QObject *watched, QEvent *event)
{
    switch (event->type()) {
    case QEvent::TouchBegin:
    case QEvent::MouseButtonPress:
    case QEvent::KeyPress:
        if (m_idle) {
            wake();
            return true; // the wake-up tap shouldn't also press a button
        }
        restartTimers();
        break;
    default:
        break;
    }
    return QObject::eventFilter(watched, event);
}

void DisplayController::setIdle(bool idle)
{
    if (m_idle == idle)
        return;
    m_idle = idle;
    applyBacklight();
    emit idleChanged();
}

void DisplayController::setScreenOff(bool off)
{
    if (m_screenOff == off)
        return;
    m_screenOff = off;
    applyBacklight();
    emit screenOffChanged();
}

void DisplayController::updateNightMode()
{
    // MCFLY_NIGHT_MODE=on|off overrides the schedule (handy for development).
    const QString forced = qEnvironmentVariable("MCFLY_NIGHT_MODE");
    const QTime now = QTime::currentTime();
    const bool night = forced == "on" || (forced != "off" && (now >= kNightStart || now < kNightEnd));

    // MCFLY_MOOD=morning|day|evening|night pins the palette (development, demos).
    QString mood = qEnvironmentVariable("MCFLY_MOOD");
    if (mood == "cycle")
        mood = QStringList{"day", "evening", "night", "morning"}.at(m_cycleIndex);
    if (mood.isEmpty())
        mood = night ? "night" : now.hour() < 11 ? "morning" : now.hour() < 17 ? "day" : "evening";
    if (mood != m_mood) {
        m_mood = mood;
        emit moodChanged();
    }

    if (night == m_nightMode)
        return;
    m_nightMode = night;
    applyBacklight();
    emit nightModeChanged();
}

void DisplayController::applyBacklight()
{
    if (m_backlightPath.isEmpty() || m_maxBacklight <= 0)
        return;
    // TODO(M2): scale by the VEML7700 ambient light reading.
    qreal level = m_brightness;
    if (m_nightMode)
        level = qMin(level, kNightBrightness);
    if (m_screenOff)
        level = 0;
    QFile out(m_backlightPath + "/brightness");
    if (out.open(QIODevice::WriteOnly))
        out.write(QByteArray::number(qRound(level * m_maxBacklight)));
}

void DisplayController::setScreensaver(const QString &style)
{
    static const QStringList styles{"ambient", "clock", "headlines"};
    if (!styles.contains(style) || style == m_screensaver)
        return;
    m_screensaver = style;
    QSettings().setValue("display/screensaver", style);
    emit screensaverChanged();
}

const QStringList &DisplayController::backdrops()
{
    static const QStringList styles{"mesh", "arc", "ribbons", "dawn", "silk", "pillars"};
    return styles;
}

void DisplayController::setBackdrop(const QString &style)
{
    if (!backdrops().contains(style) || style == m_backdrop)
        return;
    m_backdrop = style;
    QSettings().setValue("display/backdrop", style);
    emit backdropChanged();
}

const QStringList &DisplayController::weathers()
{
    static const QStringList kinds{"off", "season", "snow", "petals", "fireflies", "leaves"};
    return kinds;
}

void DisplayController::setWeather(const QString &weather)
{
    if (!weathers().contains(weather) || weather == m_weather)
        return;
    m_weather = weather;
    QSettings().setValue("display/weather", weather);
    emit weatherChanged();
    refreshWeather();
}

void DisplayController::refreshWeather()
{
    const QString kind = weatherFor(m_weather, QDate::currentDate(), QTimeZone::systemTimeZoneId());
    if (kind == m_weatherKind)
        return;
    m_weatherKind = kind;
    emit weatherKindChanged();
}

QString DisplayController::seasonFor(const QDate &date, bool south)
{
    // December to February is winter in the north.
    static const char *const north[] = {"winter", "winter", "spring", "spring", "spring", "summer",
                                        "summer", "summer", "autumn", "autumn", "autumn", "winter"};
    const int month = date.month() - 1;
    return QString::fromLatin1(north[south ? (month + 6) % 12 : month]);
}

bool DisplayController::southernZone(const QByteArray &zone)
{
    // A whole region by prefix where every zone in it is south, one by one
    // elsewhere. Not exhaustive: one missing gets the north's seasons.
    static const QList<QByteArray> prefixes{"Australia/", "Antarctica/", "America/Argentina/", "Chile/", "Brazil/"};
    static const QSet<QByteArray> zones{
        "NZ", "NZ-CHAT", "Pacific/Auckland", "Pacific/Chatham", "Pacific/Fiji", "Pacific/Noumea", "Pacific/Tongatapu",
        "Pacific/Apia", "Pacific/Efate", "Pacific/Norfolk", "Pacific/Tahiti", "Pacific/Easter", "Pacific/Rarotonga",
        "America/Santiago", "America/Punta_Arenas", "America/Montevideo", "America/Asuncion", "America/Sao_Paulo",
        "America/La_Paz", "America/Lima", "America/Recife", "America/Bahia", "America/Maceio", "America/Cuiaba",
        "America/Campo_Grande", "America/Porto_Velho", "America/Rio_Branco",
        "Atlantic/Stanley", "Atlantic/South_Georgia", "Atlantic/St_Helena",
        "Africa/Johannesburg", "Africa/Maputo", "Africa/Harare", "Africa/Lusaka", "Africa/Windhoek", "Africa/Gaborone",
        "Africa/Maseru", "Africa/Mbabane", "Africa/Blantyre", "Africa/Lubumbashi", "Africa/Luanda", "Africa/Dar_es_Salaam",
        "Indian/Antananarivo", "Indian/Mauritius", "Indian/Reunion", "Indian/Mayotte", "Indian/Comoro",
    };
    if (zones.contains(zone))
        return true;
    for (const QByteArray &prefix : prefixes)
        if (zone.startsWith(prefix))
            return true;
    return false;
}

QString DisplayController::weatherFor(const QString &weather, const QDate &date, const QByteArray &zone)
{
    if (weather == QLatin1String("season")) {
        const QString season = seasonFor(date, southernZone(zone));
        if (season == QLatin1String("winter"))
            return QStringLiteral("snow");
        if (season == QLatin1String("spring"))
            return QStringLiteral("petals");
        if (season == QLatin1String("summer"))
            return QStringLiteral("fireflies");
        return QStringLiteral("leaves");
    }
    if (weather == QLatin1String("off") || !weathers().contains(weather))
        return {};
    return weather;
}

int DisplayController::weatherCount(const QString &kind, qreal width, qreal height)
{
    // A phone gets a few; a big screen is not crowded, nor paying for a crowd.
    struct Density { const char *kind; double perPixels; int min; int max; };
    static const Density table[] = {
        {"snow", 26000, 12, 44}, {"petals", 60000, 6, 18}, {"leaves", 85000, 5, 14}, {"fireflies", 65000, 7, 20},
    };
    for (const Density &d : table) {
        if (kind == QLatin1String(d.kind))
            return qBound(d.min, int(std::lround(qMax(0.0, double(width)) * qMax(0.0, double(height)) / d.perPixels)), d.max);
    }
    return 0;
}

const QStringList &DisplayController::homeLayouts()
{
    static const QStringList layouts{"today", "bento", "assistant"};
    return layouts;
}

void DisplayController::setHomeLayout(const QString &layout)
{
    if (!homeLayouts().contains(layout) || layout == m_homeLayout)
        return;
    m_homeLayout = layout;
    QSettings().setValue("display/homeLayout", layout);
    emit homeLayoutChanged();
}

void DisplayController::setCollageLayout(const QString &layout)
{
    static const QStringList layouts{"auto", "classic", "grid", "mosaic", "trio", "columns"};
    if (!layouts.contains(layout) || layout == m_collageLayout)
        return;
    m_collageLayout = layout;
    QSettings().setValue("display/collageLayout", layout);
    emit collageLayoutChanged();
}

void DisplayController::setAnimatedTiles(bool on)
{
    if (on == m_animatedTiles)
        return;
    m_animatedTiles = on;
    QSettings().setValue("display/animatedTiles", on);
    emit animatedTilesChanged();
}

void DisplayController::setDarkMode(bool on)
{
    if (on == m_darkMode)
        return;
    m_darkMode = on;
    QSettings().setValue("display/darkMode", on);
    emit darkModeChanged();
}

void DisplayController::setOffAfterSec(int seconds)
{
    seconds = qBound(0, seconds, kSecondsPerDay);
    if (seconds == m_offAfterSec)
        return;
    m_offAfterSec = seconds;
    QSettings().setValue("display/offAfterSeconds", seconds);
    // Counts from now, like a touch (it was one: this is set from Settings).
    if (seconds == 0)
        m_offTimer.stop();
    else if (!m_screenOff)
        m_offTimer.start(seconds * 1000);
    emit sleepSettingsChanged();
}

void DisplayController::setOffAtNight(bool on)
{
    if (on == m_offAtNight)
        return;
    m_offAtNight = on;
    QSettings().setValue("display/offAtNight", on);
    applySchedule(QTime::currentTime());
    emit sleepSettingsChanged();
}

void DisplayController::setBedtime(int minuteOfDay)
{
    minuteOfDay = wrapMinute(minuteOfDay);
    if (minuteOfDay == m_bedtime)
        return;
    m_bedtime = minuteOfDay;
    QSettings().setValue("display/bedtime", minuteOfDay);
    applySchedule(QTime::currentTime());
    emit sleepSettingsChanged();
}

void DisplayController::setWakeTime(int minuteOfDay)
{
    minuteOfDay = wrapMinute(minuteOfDay);
    if (minuteOfDay == m_wakeTime)
        return;
    m_wakeTime = minuteOfDay;
    QSettings().setValue("display/wakeTime", minuteOfDay);
    applySchedule(QTime::currentTime());
    emit sleepSettingsChanged();
}
