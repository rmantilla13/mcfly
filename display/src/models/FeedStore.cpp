#include "FeedStore.h"

#include "backend/SupabaseClient.h"

#include <QColor>
#include <QCryptographicHash>
#include <QDateTime>
#include <QDebug>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocale>
#include <QMetaMethod>
#include <QMetaProperty>
#include <QRandomGenerator>
#include <QRegularExpression>
#include <QTimeZone>
#include <QSet>
#include <cmath>
#include <algorithm>
#include <memory>
#include <optional>
#include <vector>

namespace {

constexpr int kSyncIntervalMs = 60 * 1000;
// A sync that failed (no network yet after a reboot, Wi-Fi dropped) is tried
// again after this, then twice as long each time, up to the sync interval.
constexpr int kRetryFirstMs = 2000;
constexpr int kPairPollMs = 3000;
constexpr int kPairRetryMs = 10 * 1000;
constexpr qint64 kCheckInIntervalMs = 5 * 60 * 1000;
// Re-check the date at least this often, so a jump of the clock (NTP setting
// it at boot) is noticed between syncs and in demo mode too.
constexpr qint64 kDayCheckMaxMs = 15 * 60 * 1000;
// A reminder whose time came this recently is still announced (the display
// was starting, or the sync that brought it ran late); older ones are not.
constexpr qint64 kReminderLateMs = 5 * 60 * 1000;
constexpr int kSparklinePoints = 60;

QVariantList toList(const QJsonDocument &doc) { return doc.array().toVariantList(); }

QDateTime parseTimestamp(const QString &s)
{
    QDateTime dt = QDateTime::fromString(s, Qt::ISODateWithMs);
    if (!dt.isValid())
        dt = QDateTime::fromString(s, Qt::ISODate);
    return dt.toLocalTime();
}

QString money(double value, const QString &currency)
{
    const QLocale locale;
    // Big numbers (an index) read better without cents.
    const int decimals = qAbs(value) >= 10000 ? 0 : 2;
    const QString number = locale.toString(value, 'f', decimals);
    if (currency == QLatin1String("USD"))
        return QStringLiteral("$") + number;
    if (currency == QLatin1String("EUR"))
        return QStringLiteral("€") + number;
    if (currency == QLatin1String("GBP"))
        return QStringLiteral("£") + number;
    return number + QLatin1Char(' ') + currency;
}

QString signedNumber(double value, int decimals, const QString &suffix = {})
{
    const QString number = QLocale().toString(qAbs(value), 'f', decimals);
    return (value < 0 ? QStringLiteral("−") : QStringLiteral("+")) + number + suffix;
}

QString signedMoney(double value, const QString &currency)
{
    return (value < 0 ? QStringLiteral("−") : QStringLiteral("+")) + money(qAbs(value), currency);
}

// Volumes and market caps: 48.2M, 3.7T.
QString compactNumber(double value)
{
    static const std::pair<double, const char *> steps[] = {{1e12, "T"}, {1e9, "B"}, {1e6, "M"}, {1e3, "K"}};
    for (const auto &[size, suffix] : steps) {
        if (qAbs(value) >= size) {
            const double n = value / size;
            return QLocale().toString(n, 'f', qAbs(n) >= 100 ? 0 : 1) + QLatin1String(suffix);
        }
    }
    return QLocale().toString(value, 'f', 0);
}

// Whole shares plainly, a fraction to four places without trailing zeros.
QString shareCount(double shares)
{
    if (std::abs(shares - std::round(shares)) < 1e-9)
        return QLocale().toString(shares, 'f', 0);
    QString n = QLocale().toString(shares, 'f', 4);
    while (n.endsWith(QLatin1Char('0')))
        n.chop(1);
    return n;
}

// A number from an agent's free-form `data`: a JSON number, or a string like
// "$1,234.50" or "12%". NaN for anything else.
double dataNumber(const QVariant &v)
{
    if (!v.isValid() || v.isNull() || v.typeId() == QMetaType::Bool)
        return qQNaN();
    bool ok = false;
    double d;
    if (v.typeId() == QMetaType::QString) {
        QString s = v.toString();
        s.remove(QLatin1Char(',')).remove(QLatin1Char('$')).remove(QLatin1Char('%'));
        d = s.trimmed().toDouble(&ok);
    } else {
        d = v.toDouble(&ok);
    }
    return ok && std::isfinite(d) ? d : qQNaN();
}

double firstNumber(const QVariantMap &m, std::initializer_list<const char *> keys)
{
    for (const char *key : keys) {
        const double d = dataNumber(m.value(QLatin1String(key)));
        if (!std::isnan(d))
            return d;
    }
    return qQNaN();
}

// What an agent says about a holding (data.position), with the numbers it
// left out worked out from the ones it sent: value from shares x price, the
// gain from the average cost, today's move from shares x change. Empty when
// there is no holding. `weightLabel` is filled in once every one is known.
QVariantMap positionOf(const QVariantMap &data, double price, double change, const QString &currency)
{
    const QVariantMap p = data.value(QStringLiteral("position")).toMap();
    if (p.isEmpty())
        return {};
    const double shares = firstNumber(p, {"shares", "quantity"});
    double value = firstNumber(p, {"value", "market_value"});
    if (std::isnan(value) && !std::isnan(shares))
        value = shares * price;
    if (std::isnan(value) || (qFuzzyIsNull(value) && (std::isnan(shares) || qFuzzyIsNull(shares))))
        return {};
    const double avgCost = firstNumber(p, {"avg_cost", "average_cost", "average_buy_price"});
    double total = firstNumber(p, {"total_change", "unrealized_pl", "gain"});
    if (std::isnan(total) && !std::isnan(avgCost) && !std::isnan(shares))
        total = value - avgCost * shares;
    double totalPct = firstNumber(p, {"total_change_pct", "unrealized_pl_pct", "gain_pct"});
    if (std::isnan(totalPct) && !std::isnan(total) && value - total > 0)
        totalPct = total / (value - total) * 100;
    double day = firstNumber(p, {"day_change", "today"});
    if (std::isnan(day) && !std::isnan(shares))
        day = shares * change;

    QVariantMap out{{"value", value}, {"valueLabel", money(value, currency)}};
    if (!std::isnan(shares))
        out.insert("sharesLabel", shares == 1 ? QObject::tr("1 share") : QObject::tr("%1 shares").arg(shareCount(shares)));
    if (!std::isnan(avgCost))
        out.insert("avgCostLabel", QObject::tr("avg %1").arg(money(avgCost, currency)));
    if (!std::isnan(day)) {
        out.insert("dayChange", day);
        out.insert("dayChangeLabel", signedMoney(day, currency));
        out.insert("dayUp", day >= 0);
    }
    if (!std::isnan(total)) {
        out.insert("totalChange", total);
        out.insert("totalChangeLabel", signedMoney(total, currency));
        out.insert("totalUp", total >= 0);
        if (!std::isnan(totalPct))
            out.insert("totalPctLabel", signedNumber(totalPct, 1, QStringLiteral("%")));
    }
    const double weight = firstNumber(p, {"weight_pct", "weight"});
    if (!std::isnan(weight))
        out.insert("weight", weight);
    return out;
}

// data.signals: what the agent noticed, as [{ text, tone }] (tone up, down
// or watch). Plain strings count as "watch". At most six, one line each.
QVariantList signalsOf(const QVariantMap &data)
{
    QVariantList out;
    for (const QVariant &v : data.value(QStringLiteral("signals")).toList()) {
        QString text, tone;
        if (v.typeId() == QMetaType::QString) {
            text = v.toString();
        } else {
            const QVariantMap m = v.toMap();
            text = m.value("text").toString();
            tone = m.value("tone").toString();
        }
        text = text.simplified().left(140);
        if (text.isEmpty())
            continue;
        if (tone != QLatin1String("up") && tone != QLatin1String("down"))
            tone = QStringLiteral("watch");
        out << QVariantMap{{"text", text}, {"tone", tone}};
        if (out.size() == 6)
            break;
    }
    return out;
}

// data.stats' day and 52-week ranges, with where the price sits in each
// (0 at the low, 1 at the high): [{ label, lowLabel, highLabel, pos }].
QVariantList rangesOf(const QVariantMap &data, double price, const QString &currency)
{
    const QVariantMap s = data.value(QStringLiteral("stats")).toMap();
    QVariantList out;
    const auto add = [&](const QString &label, const char *lowKey, const char *highKey) {
        const double low = firstNumber(s, {lowKey}), high = firstNumber(s, {highKey});
        if (std::isnan(low) || std::isnan(high) || high < low)
            return;
        const double pos = high > low ? std::clamp((price - low) / (high - low), 0.0, 1.0) : 0.5;
        out << QVariantMap{{"label", label}, {"lowLabel", money(low, currency)}, {"highLabel", money(high, currency)}, {"pos", pos}};
    };
    add(QObject::tr("Today"), "low", "high");
    add(QObject::tr("52 weeks"), "low_52w", "high_52w");
    return out;
}

// data.intraday: the session's bars laid out on the whole session, so the
// line fills in through the day: points as { x, y } (x 0..1 from the open
// to the close, y 0..1 bottom to top over the day's range and the previous
// close), baseY where the previous close sits (-1 without one), up (the
// newest price against it), prices (for a tile's plain sparkline), lowLabel /
// highLabel, and openSecs / closeSecs for the caller's time labels. Empty
// with fewer than two points.
QVariantMap intradayOf(const QVariantMap &data, double prevClose, const QString &currency)
{
    const QVariantMap d = data.value(QStringLiteral("intraday")).toMap();
    const double open = dataNumber(d.value(QStringLiteral("open"))), close = dataNumber(d.value(QStringLiteral("close")));
    if (std::isnan(open) || std::isnan(close) || close <= open)
        return {};
    std::vector<std::pair<double, double>> pts;
    double lo = qInf(), hi = -qInf();
    for (const QVariant &v : d.value(QStringLiteral("points")).toList()) {
        const QVariantList p = v.toList();
        if (p.size() < 2)
            continue;
        const double t = dataNumber(p.at(0)), y = dataNumber(p.at(1));
        if (std::isnan(t) || std::isnan(y) || t < open || t > close)
            continue;
        pts.emplace_back(t, y);
        lo = std::min(lo, y);
        hi = std::max(hi, y);
    }
    if (pts.size() < 2)
        return {};
    std::sort(pts.begin(), pts.end());
    const double dayLow = lo, dayHigh = hi;
    const bool hasBase = !std::isnan(prevClose) && prevClose > 0;
    if (hasBase) {
        lo = std::min(lo, prevClose);
        hi = std::max(hi, prevClose);
    }
    const double span = hi - lo > 0 ? hi - lo : (hi != 0 ? std::abs(hi) * 0.02 : 1);
    QVariantList points, prices;
    for (const auto &[t, y] : pts) {
        points << QVariantMap{{"x", (t - open) / (close - open)}, {"y", (y - lo) / span}};
        prices << y;
    }
    const double last = pts.back().second;
    return QVariantMap{
        {"points", points},
        {"prices", prices},
        {"baseY", hasBase ? (prevClose - lo) / span : -1.0},
        {"up", last >= (hasBase ? prevClose : pts.front().second)},
        {"lowLabel", money(dayLow, currency)},
        {"highLabel", money(dayHigh, currency)},
        {"openSecs", open},
        {"closeSecs", close},
    };
}

// data.stats as [{ label, value }] in a fixed order, only what was sent
// (the ranges are rangesOf's).
QVariantList statsOf(const QVariantMap &data, const QString &currency)
{
    const QVariantMap s = data.value(QStringLiteral("stats")).toMap();
    QVariantList out;
    const auto add = [&out](const QString &label, const QString &value) {
        if (!value.isEmpty())
            out << QVariantMap{{"label", label}, {"value", value}};
    };
    const auto price = [&](const char *key) {
        const double d = firstNumber(s, {key});
        return std::isnan(d) ? QString() : money(d, currency);
    };
    add(QObject::tr("Open"), price("open"));
    add(QObject::tr("Prev close"), price("prev_close"));
    const double volume = firstNumber(s, {"volume"});
    if (!std::isnan(volume)) {
        QString label = compactNumber(volume);
        const double avg = firstNumber(s, {"avg_volume"});
        if (avg > 0)
            label += QStringLiteral(" · %1× avg").arg(QLocale().toString(volume / avg, 'f', 1));
        add(QObject::tr("Volume"), label);
    }
    const double cap = firstNumber(s, {"market_cap"});
    if (!std::isnan(cap))
        add(QObject::tr("Market cap"), (currency == QLatin1String("USD") ? QStringLiteral("$") : QString()) + compactNumber(cap));
    const double pe = firstNumber(s, {"pe", "pe_ratio"});
    if (!std::isnan(pe))
        add(QObject::tr("P/E"), QLocale().toString(pe, 'f', 1));
    const double yield = firstNumber(s, {"dividend_yield"});
    if (!std::isnan(yield))
        add(QObject::tr("Dividend"), QLocale().toString(yield, 'f', 2) + QStringLiteral("%"));
    add(QObject::tr("Earnings"), s.value(QStringLiteral("earnings")).toString().simplified().left(40));
    return out;
}

// The Pulse sections' colors, by key, then by position.
QString sectionColor(const QString &key, int index)
{
    if (key == QLatin1String("s") || key.startsWith(QLatin1String("social")))
        return QStringLiteral("#F07F5A");
    if (key == QLatin1String("a") || key.startsWith(QLatin1String("ad")))
        return QStringLiteral("#F6B94A");
    if (key == QLatin1String("i") || key.startsWith(QLatin1String("ai")))
        return QStringLiteral("#5B7CF5");
    static const QStringList palette{"#7A64E8", "#3DB37A", "#E86A92", "#14C2C2"};
    return palette.at(index % palette.size());
}

QString kindLabel(const QString &kind)
{
    if (kind == QLatin1String("hourly"))
        return QObject::tr("Hourly");
    if (kind == QLatin1String("daily"))
        return QObject::tr("Daily");
    if (kind == QLatin1String("alert"))
        return QObject::tr("Alert");
    return QObject::tr("Update");
}

// ── What stands out: the console's lib/insights.ts and lib/series.ts, ported ──

constexpr qint64 kMinuteMs = 60 * 1000;
constexpr qint64 kHourMs = 60 * kMinuteMs;
constexpr qint64 kFreshMs = 15 * kMinuteMs;       // a quote or metric this new is live
constexpr int kMaxHighlights = 5;
constexpr int kMinHistory = 8;                     // fewer earlier points and a z says more about the sample
constexpr double kAnomalyZ = 3;
constexpr double kShortHistoryPct = 10;            // a metric's jump that counts when z can't be had
constexpr double kBigMovePct = 2;
constexpr double kSwingRatio = 2.5;
constexpr double kSwingFloorPct = 1;               // a 0.4% day is never news, however calm the stock
constexpr qint64 kEventSoonMs = 30 * kMinuteMs;
constexpr qint64 kBriefFreshMs = kHourMs;
constexpr qint64 kQuoteFreshMs = 36 * kHourMs;     // Friday's move isn't "today" on Sunday
const QString kGood = QStringLiteral("#3DB37A");
const QString kBad = QStringLiteral("#F07F5A");

std::optional<double> median(QList<double> values)
{
    if (values.isEmpty())
        return std::nullopt;
    std::sort(values.begin(), values.end());
    const qsizetype mid = values.size() / 2;
    return values.size() % 2 ? values.at(mid) : (values.at(mid - 1) + values.at(mid)) / 2;
}

// How unusual the last value is against the ones before it: (last − median)
// / (1.4826 · MAD), with the mean absolute deviation standing in when over
// half the history is one value. None with too little history or no spread.
std::optional<double> robustZ(const QList<double> &values)
{
    if (values.size() - 1 < kMinHistory)
        return std::nullopt;
    const QList<double> earlier = values.mid(0, values.size() - 1);
    const double mid = *median(earlier);
    QList<double> deviations;
    double sum = 0;
    for (double v : earlier) {
        deviations << qAbs(v - mid);
        sum += qAbs(v - mid);
    }
    double scale = 1.4826 * *median(deviations);
    if (!(scale > 0))
        scale = 1.2533 * (sum / deviations.size());
    if (!(scale > 0))
        return std::nullopt;
    const double z = (values.last() - mid) / scale;
    return std::isfinite(z) ? std::optional<double>(z) : std::nullopt;
}

// The usual day-to-day move in percent: the standard deviation of the daily
// changes, leaving out the last one (today's, the move being judged).
std::optional<double> usualSwing(const QList<double> &closes, int minChanges = 5)
{
    QList<double> changes;
    for (qsizetype i = 1; i < closes.size() - 1; ++i)
        if (closes.at(i - 1) != 0)
            changes << (closes.at(i) - closes.at(i - 1)) / qAbs(closes.at(i - 1)) * 100;
    if (changes.size() < minChanges)
        return std::nullopt;
    double mean = 0;
    for (double c : changes)
        mean += c;
    mean /= changes.size();
    double variance = 0;
    for (double c : changes)
        variance += (c - mean) * (c - mean);
    const double sd = std::sqrt(variance / (changes.size() - 1));
    return std::isfinite(sd) && sd > 0 ? std::optional<double>(sd) : std::nullopt;
}

// Whether up is good news for a metric. Latency, error rates, cost, churn,
// queues and the like should fall; everything else should rise. From the
// unit and the key only, since that is all an agent's push says.
bool upIsGood(const QString &unit, const QString &key)
{
    static const QStringList downPrefixes{
        "latenc", "error", "fail", "crash", "incident", "outage", "downtime", "churn", "cost", "spend",
        "expens", "refund", "backlog", "queue", "bounce", "ttfb", "cancel", "complaint", "defect", "bug"};
    static const QSet<QString> downWords{"lag", "lags", "delay", "delays", "wait", "waits", "debt", "burn", "err", "errs",
                                         "p50", "p75", "p90", "p95", "p99", "p999"};
    static const QSet<QString> downUnits{QStringLiteral("ms"), QStringLiteral("µs"), QStringLiteral("us"), QStringLiteral("ns")};
    static const QRegularExpression split(QStringLiteral("[^a-z0-9]+"));
    static const QRegularExpression percentile(QStringLiteral("^p\\d{2,3}$"));
    if (downUnits.contains(unit.trimmed().toLower()))
        return false;
    for (const QString &word : key.toLower().split(split, Qt::SkipEmptyParts)) {
        if (downWords.contains(word) || percentile.match(word).hasMatch())
            return false;
        for (const QString &prefix : downPrefixes)
            if (word.startsWith(prefix))
                return false;
    }
    return true;
}

QString clip(const QString &text, int max)
{
    const QString t = text.simplified();
    return t.size() <= max ? t : t.left(max - 1).trimmed() + QStringLiteral("…");
}

QString agoLabel(qint64 ms, qint64 nowMs)
{
    const qint64 m = qRound64(double(nowMs - ms) / kMinuteMs);
    if (m < 1)
        return QObject::tr("just now");
    if (m < 60)
        return QObject::tr("%1 min ago").arg(m);
    const qint64 h = qRound64(m / 60.0);
    return h < 48 ? QObject::tr("%1 h ago").arg(h) : QObject::tr("%1 d ago").arg(qRound64(h / 24.0));
}

QString pct1(double value) { return QLocale().toString(qAbs(value), 'f', 1); }

// A time of day on the 24-hour dial: degrees clockwise from midnight.
double dialAngle(const QTime &time) { return time.msecsSinceStartOfDay() / 240000.0; }

// Until just after the next minute on the clock.
int untilNextMinute(const QDateTime &now)
{
    return int(kMinuteMs - now.time().msecsSinceStartOfDay() % kMinuteMs + 50);
}

// A row's low and high over its history (oldest first, ending on the current
// value), labelled, and where the current value sits between them: 0 at the
// low, 1 at the high, the middle when it never moved.
void addRange(QVariantMap &row, const QVariantList &history, const std::function<QString(double)> &label)
{
    if (history.isEmpty())
        return;
    double low = history.first().toDouble(), high = low;
    for (const QVariant &v : history) {
        low = qMin(low, v.toDouble());
        high = qMax(high, v.toDouble());
    }
    const double last = history.last().toDouble();
    row.insert("low", low);
    row.insert("high", high);
    row.insert("lowLabel", label(low));
    row.insert("highLabel", label(high));
    row.insert("rangePos", high > low ? (last - low) / (high - low) : 0.5);
}

// Pushed in the last 15 minutes (a clock a little ahead is forgiven).
bool isFresh(const QDateTime &asOf, const QDateTime &now)
{
    const qint64 age = asOf.msecsTo(now);
    return asOf.isValid() && age <= kFreshMs && age >= -5 * kMinuteMs;
}

} // namespace

FeedStore::FeedStore(SupabaseClient *client, bool forceDemo, QObject *parent)
    : QObject(parent), m_client(client), m_forceDemo(forceDemo)
{
    m_syncTimer.setInterval(kSyncIntervalMs);
    connect(&m_syncTimer, &QTimer::timeout, this, &FeedStore::refresh);
    m_retryTimer.setSingleShot(true);
    connect(&m_retryTimer, &QTimer::timeout, this, &FeedStore::loadLive);

    m_pairTimer.setInterval(kPairPollMs);
    connect(&m_pairTimer, &QTimer::timeout, this, &FeedStore::pollPairing);
    m_pairRetryTimer.setSingleShot(true);
    m_pairRetryTimer.setInterval(kPairRetryMs);
    connect(&m_pairRetryTimer, &QTimer::timeout, this, &FeedStore::startPairing);

    m_today = QDate::currentDate();
    m_dayTimer.setSingleShot(true);
    connect(&m_dayTimer, &QTimer::timeout, this, &FeedStore::rollDay);
    m_minuteTimer.setSingleShot(true);
    m_minuteTimer.setTimerType(Qt::PreciseTimer); // on the minute, not up to 3 s before it
    connect(&m_minuteTimer, &QTimer::timeout, this, &FeedStore::onMinute);
    m_reminderTimer.setSingleShot(true);
    connect(&m_reminderTimer, &QTimer::timeout, this, &FeedStore::fireReminders);

    connect(m_client, &SupabaseClient::sessionChanged, this, [this]() {
        if (m_client->refreshToken().isEmpty())
            return;
        m_settings.setValue("device/refreshToken", m_client->refreshToken());
        // The token signs in as this display: keep the file private (later
        // saves replace it with the same permissions).
        m_settings.sync();
        QFile::setPermissions(m_settings.fileName(), QFileDevice::ReadOwner | QFileDevice::WriteOwner);
    });
    connect(m_client, &SupabaseClient::sessionLost, this, [this]() {
        ++m_generation;
        m_settings.remove("device/refreshToken");
        m_client->clearSession();
        m_syncTimer.stop();
        stopRetrying();
        startPairing();
    });
}

void FeedStore::setSyncIntervalMs(int ms)
{
    m_syncTimer.setInterval(ms);
    if (m_syncTimer.isActive())
        m_syncTimer.start();
}

void FeedStore::start()
{
    updateToday(); // the clock may have been swapped since construction (tests)
    m_minuteTimer.start(untilNextMinute(now()));
    if (m_forceDemo || !m_client->isConfigured()) {
        setMode("demo");
        loadDemo();
    } else if (m_client->refreshToken().isEmpty()) {
        startPairing();
    } else {
        setMode("live");
        loadLive();
        m_syncTimer.start();
    }
}

void FeedStore::setMode(const QString &mode)
{
    if (m_mode == mode)
        return;
    m_mode = mode;
    emit modeChanged();
}

void FeedStore::setOnline(bool online, const QString &error)
{
    if (m_online == online && m_lastError == error)
        return;
    m_online = online;
    m_lastError = error;
    emit statusChanged();
}

QString FeedStore::lastSyncLabel() const
{
    if (m_mode == QLatin1String("demo"))
        return tr("Sample data");
    if (!m_lastSync.isValid())
        return tr("Not synced yet");
    const qint64 secs = m_lastSync.secsTo(now());
    if (secs < 90)
        return tr("Updated just now");
    if (secs < 3600)
        return tr("Updated %1 min ago").arg(secs / 60);
    return tr("Updated %1").arg(QLocale().toString(m_lastSync.time(), QStringLiteral("h:mm ap")));
}

void FeedStore::refresh()
{
    // Each sync re-checks the date too, in case the clock jumped past midnight.
    const bool rolled = rollDay();
    if (m_mode == "live") {
        if (!rolled)
            loadLive();
    } else if (m_mode == "pairing" && m_pairRetryTimer.isActive()) {
        startPairing(); // the last try failed: don't wait for the next one
    }
}

void FeedStore::networkUp()
{
    if (m_online)
        return;
    stopRetrying(); // if this try is still too early, the next is 2 s later
    refresh();
}

void FeedStore::showReport(const QString &reportId)
{
    if (m_shownReportId == reportId)
        return;
    m_shownReportId = reportId;
    rebuild();
}

// Reads the clock: sets `today` and arms the timer for the next check, just
// after local midnight. True if the date changed.
bool FeedStore::updateToday()
{
    const QDateTime current = now();
    const bool changed = current.date() != m_today;
    if (changed) {
        m_today = current.date();
        emit todayChanged();
    }
    const qint64 untilMidnight = current.msecsTo(m_today.addDays(1).startOfDay());
    m_dayTimer.start(int(qBound<qint64>(1000, untilMidnight + 500, kDayCheckMaxMs)));
    return changed;
}

// A new day: the labels ("Today", "Yesterday") move on, and live data is
// fetched again. True if the date changed.
bool FeedStore::rollDay()
{
    if (!updateToday())
        return false;
    if (m_mode == "demo")
        loadDemo();
    else if (m_mode == "live")
        loadLive();
    else
        rebuild();
    return true;
}

// ───────────────────────────── Demo data ─────────────────────────────

void FeedStore::loadDemo()
{
    QFile file(QStringLiteral(":/McFly/resources/demo/feed.json"));
    if (!file.open(QIODevice::ReadOnly)) {
        qWarning() << "demo data missing";
        return;
    }
    const QJsonObject root = QJsonDocument::fromJson(file.readAll()).object();
    const QDateTime nowDt = now();

    m_displayName = root.value("settings").toObject().value("display_name").toString(QStringLiteral("McFly"));
    m_rawAgents = root.value("agents").toArray().toVariantList();
    m_rawCalendarSources.clear();
    for (const QJsonValue &v : root.value("calendar_sources").toArray()) {
        QJsonObject c = v.toObject();
        c.insert("last_synced_at", nowDt.addSecs(-qint64(c.value("minutesAgo").toDouble() * 60)).toString(Qt::ISODateWithMs));
        m_rawCalendarSources << c.toVariantMap();
    }
    m_rawMemories.clear();
    for (const QJsonValue &v : root.value("memories").toArray()) {
        QJsonObject m = v.toObject();
        m.insert("updated_at", nowDt.addSecs(-qint64(m.value("daysAgo").toDouble() * 86400)).toString(Qt::ISODateWithMs));
        m_rawMemories << m.toVariantMap();
    }
    m_rawTodos.clear();
    for (const QJsonValue &v : root.value("todos").toArray()) {
        QJsonObject t = v.toObject();
        // Like the events: a day around today (and a time), so it looks current.
        if (t.contains("dayOffset")) {
            const QString at = t.value("at").toString();
            const QDateTime due(m_today.addDays(t.value("dayOffset").toInt()), at.isEmpty() ? QTime(0, 0) : QTime::fromString(at, "HH:mm"));
            t.insert("due_at", due.toString(Qt::ISODateWithMs));
            t.insert("all_day", at.isEmpty());
        }
        t.insert("id", QStringLiteral("demo-todo-%1").arg(m_rawTodos.size()));
        if (!t.contains("agent_id"))
            t.insert("agent_id", "a-mcfly");
        m_rawTodos << t.toVariantMap();
    }

    // Briefs are stored relative to now so the demo always looks current.
    m_rawBriefs.clear();
    for (const QJsonValue &v : root.value("briefs").toArray()) {
        QJsonObject b = v.toObject();
        const QDateTime at = nowDt.addSecs(-qint64(b.value("hoursAgo").toDouble() * 3600));
        b.insert("published_at", at.toString(Qt::ISODateWithMs));
        if (!b.contains("id"))
            b.insert("id", QStringLiteral("demo-brief-%1").arg(m_rawBriefs.size()));
        m_rawBriefs << b.toVariantMap();
    }

    // Each demo quote carries its own history; it becomes one row per point
    // so live and demo data take the same path through rebuild(). The last
    // row carries the quote's `data` itself.
    m_rawQuotes.clear();
    m_rawQuoteData.clear();
    m_rawSymbols.clear();
    int order = 0;
    for (const QJsonValue &v : root.value("quotes").toArray()) {
        const QJsonObject q = v.toObject();
        const QJsonArray history = q.value("history").toArray();
        const int points = history.size();
        for (int i = 0; i < points; ++i) {
            QVariantMap row;
            row.insert("symbol", q.value("symbol").toString());
            row.insert("name", q.value("name").toString());
            row.insert("currency", q.value("currency").toString(QStringLiteral("USD")));
            row.insert("agent_id", q.value("agent_id").toString());
            const bool last = i == points - 1;
            row.insert("price", last ? q.value("price").toDouble() : history.at(i).toDouble());
            row.insert("change", last ? q.value("change").toVariant() : QVariant());
            row.insert("change_pct", last ? q.value("change_pct").toVariant() : QVariant());
            row.insert("note", last ? q.value("note").toString() : QString());
            QVariantMap data = last ? q.value("data").toObject().toVariantMap() : QVariantMap();
            // The demo's bars move to today's session (New York's 9:30), so its chart is always today's.
            QVariantMap intraday = data.value("intraday").toMap();
            if (!intraday.isEmpty()) {
                const QTimeZone ny("America/New_York");
                const QDate day = nowDt.toTimeZone(ny).date();
                const double shift = double(QDateTime(day, QTime(9, 30), ny).toSecsSinceEpoch()) - intraday.value("open").toDouble();
                intraday.insert("open", intraday.value("open").toDouble() + shift);
                intraday.insert("close", intraday.value("close").toDouble() + shift);
                // Only the bars up to now, as an agent would have them mid-session.
                const double nowSecs = double(nowDt.toSecsSinceEpoch());
                QVariantList moved;
                for (const QVariant &pv : intraday.value("points").toList()) {
                    const QVariantList pt = pv.toList();
                    if (pt.size() >= 2 && pt.at(0).toDouble() + shift <= nowSecs)
                        moved << QVariant(QVariantList{pt.at(0).toDouble() + shift, pt.at(1)});
                }
                // And the price now, as the newest point while the session is on.
                if (!moved.isEmpty() && nowSecs < intraday.value("close").toDouble())
                    moved << QVariant(QVariantList{nowSecs, q.value("price").toDouble()});
                intraday.insert("points", moved);
                data.insert("intraday", intraday);
            }
            row.insert("data", data);
            // One point per trading day, the last one this morning.
            row.insert("as_of", nowDt.addDays(-(points - 1 - i)).toString(Qt::ISODateWithMs));
            m_rawQuotes << row;
        }
        m_rawSymbols << QVariantMap{{"symbol", q.value("symbol").toString()}, {"name", q.value("name").toString()},
                                    {"sort_order", order++}, {"hidden", false}};
    }

    // The reports are Pulse items JSON, the way the agents push them: one
    // under "news", more under "news2", "news3", ... (other sources).
    m_rawReports.clear();
    QList<QJsonObject> reports;
    for (const QString &key : {QStringLiteral("news"), QStringLiteral("news2"), QStringLiteral("news3")}) {
        const QJsonValue value = root.value(key);
        if (value.isArray()) {
            for (const QJsonValue &rv : value.toArray())
                reports << rv.toObject();
        } else if (value.isObject()) {
            reports << value.toObject();
        }
    }
    int reportIndex = 0;
    for (const QJsonObject &report : std::as_const(reports)) {
        if (report.isEmpty())
            continue;
        QVariantMap r;
        r.insert("id", QStringLiteral("demo-report-%1").arg(reportIndex));
        r.insert("slug", report.value("slug").toString(QStringLiteral("today")));
        r.insert("report_date", m_today.toString(Qt::ISODate));
        r.insert("display_date", report.value("date").toString(QLocale().toString(m_today, QStringLiteral("MMM d, yyyy"))));
        r.insert("hero_item", report.value("hero").toString());
        r.insert("published_at", nowDt.addSecs(-7200 - 600 * reportIndex).toString(Qt::ISODateWithMs));
        r.insert("agent_id", report.value("agent_id").toString());
        QVariantList items;
        int sectionOrder = 0;
        for (const QJsonValue &sv : report.value("sections").toArray()) {
            const QJsonObject section = sv.toObject();
            int position = 0;
            for (const QJsonValue &iv : section.value("items").toArray()) {
                const QJsonObject item = iv.toObject();
                const QString url = item.value("url").toString();
                items << QVariantMap{{"section_key", section.value("key").toString()},
                                     {"section_name", section.value("name").toString()},
                                     {"section_order", sectionOrder},
                                     {"item_key", item.value("id").toString(QStringLiteral("item-%1").arg(position))},
                                     {"position", position++},
                                     {"headline", item.value("h").toString()},
                                     {"takeaway", item.value("t").toString()},
                                     {"url", url},
                                     {"image_url", item.value("image").toString()},
                                     {"source_domain", QUrl(url).host().remove(QRegularExpression("^www\\."))}};
            }
            ++sectionOrder;
        }
        r.insert("news_items", items);
        m_rawReports << r;
        ++reportIndex;
    }
    // Projects, metrics, dashboards and events, in their database shapes.
    m_rawProjects.clear();
    for (const QJsonValue &v : root.value("projects").toArray()) {
        QJsonObject pr = v.toObject();
        pr.insert("id", QStringLiteral("demo-project-") + pr.value("key").toString());
        QJsonArray updates;
        for (const QJsonValue &uv : pr.value("updates").toArray()) {
            QJsonObject u = uv.toObject();
            u.insert("happened_at", nowDt.addSecs(-qint64(u.value("hoursAgo").toDouble() * 3600)).toString(Qt::ISODateWithMs));
            updates.append(u);
        }
        pr.insert("project_updates", updates);
        pr.insert("updated_at", nowDt.addSecs(-qint64(pr.value("hoursAgo").toDouble(1) * 3600)).toString(Qt::ISODateWithMs));
        if (pr.contains("stageHoursAgo"))
            pr.insert("stage_since", nowDt.addSecs(-qint64(pr.value("stageHoursAgo").toDouble() * 3600)).toString(Qt::ISODateWithMs));
        m_rawProjects << pr.toVariantMap();
    }
    m_rawMetrics.clear();
    m_rawMetricSettings.clear();
    order = 0;
    for (const QJsonValue &v : root.value("metrics").toArray()) {
        const QJsonObject m = v.toObject();
        const QJsonArray history = m.value("history").toArray();
        for (int i = 0; i < history.size(); ++i) {
            m_rawMetrics << QVariantMap{{"key", m.value("key").toString()}, {"label", m.value("label").toString()},
                                        {"value", i == history.size() - 1 ? m.value("value").toDouble() : history.at(i).toDouble()},
                                        {"unit", m.value("unit").toString()}, {"delta", i == history.size() - 1 ? m.value("delta").toVariant() : QVariant()},
                                        {"delta_pct", i == history.size() - 1 ? m.value("delta_pct").toVariant() : QVariant()},
                                        {"note", i == history.size() - 1 ? m.value("note").toString() : QString()},
                                        {"agent_id", m.value("agent_id").toString()},
                                        {"as_of", nowDt.addDays(-(history.size() - 1 - i)).toString(Qt::ISODateWithMs)}};
        }
        m_rawMetricSettings << QVariantMap{{"key", m.value("key").toString()}, {"label", m.value("label").toString()},
                                           {"group_name", m.value("group").toString()}, {"sort_order", order++}, {"hidden", false}};
    }
    m_rawDashboards.clear();
    order = 0;
    for (const QJsonValue &v : root.value("dashboards").toArray()) {
        QJsonObject d = v.toObject();
        d.insert("id", QStringLiteral("demo-dashboard-") + d.value("key").toString());
        d.insert("sort_order", order++);
        d.insert("hidden", false);
        m_rawDashboards << d.toVariantMap();
    }
    m_rawEvents.clear();
    for (const QJsonValue &v : root.value("events").toArray()) {
        QJsonObject e = v.toObject();
        // Laid out around today: dayOffset and a start hour, so the demo always looks current.
        const QDate day = m_today.addDays(e.value("dayOffset").toInt());
        const bool allDay = e.value("all_day").toBool();
        const QTime start = allDay ? QTime(0, 0) : QTime::fromString(e.value("start").toString(), "HH:mm");
        const double hours = e.value("hours").toDouble(1);
        const QDateTime starts(day, start);
        e.insert("id", QStringLiteral("demo-event-%1").arg(m_rawEvents.size()));
        e.insert("starts_at", starts.toString(Qt::ISODateWithMs));
        e.insert("ends_at", (allDay ? QDateTime(day, QTime(23, 59, 59)) : starts.addSecs(qint64(hours * 3600))).toString(Qt::ISODateWithMs));
        m_rawEvents << e.toVariantMap();
    }
    m_assistantProvider = root.value("settings").toObject().value("assistant_provider").toString(QStringLiteral("claude"));
    m_lastSync = nowDt;
    rebuild();
}

// ───────────────────────────── Live data ─────────────────────────────

void FeedStore::withSession(std::function<void()> fn)
{
    if (m_client->hasSession()) {
        fn();
        return;
    }
    const int generation = m_generation;
    m_client->refreshSession([this, fn, generation](bool ok) {
        if (generation != m_generation)
            return; // re-paired meanwhile
        if (ok) {
            fn();
        } else {
            setOnline(false, tr("Can't reach McFly cloud"));
            retrySoon();
        }
    });
}

// Tries a failed sync again soon instead of at the next sync interval: after
// a reboot the app is up before Wi-Fi, and its first sync always fails.
void FeedStore::retrySoon()
{
    m_retryMs = m_retryMs == 0 ? kRetryFirstMs : qMin(m_retryMs * 2, m_syncTimer.interval());
    m_retryTimer.start(m_retryMs);
}

void FeedStore::stopRetrying()
{
    m_retryTimer.stop();
    m_retryMs = 0;
}

void FeedStore::loadLive()
{
    if (m_mode != "live")
        return;
    withSession([this]() {
        // Rows that arrive after a re-pair belong to the old session: drop them.
        const int generation = m_generation;
        auto onError = [this](const QString &what, const QString &error) {
            qWarning() << "load" << what << "failed:" << error;
            setOnline(false, error);
        };
        // The requests of this sync still out, and whether one has failed.
        // Once all are back, a failure tries again soon; a clean sync ends
        // the retries. (A partial success must not: one table failing every
        // time would retry every 2 s.)
        struct Sync
        {
            int pending = 0;
            bool failed = false;
        };
        auto sync = std::make_shared<Sync>();
        using Apply = std::function<void(const QJsonDocument &)>;
        // One rebuild per sync, once the last answer is in (the optional
        // tables' too): a rebuild re-reads every list.
        auto finish = [this, sync]() {
            if (--sync->pending > 0)
                return;
            if (sync->failed) {
                retrySoon();
            } else {
                stopRetrying();
                m_lastSync = now();
            }
            rebuild();
        };
        auto load = [this, onError, generation, sync, finish](const QString &table, const QUrlQuery &q, Apply apply) {
            ++sync->pending;
            m_client->select(table, q, [this, table, apply, onError, generation, sync, finish](const QJsonDocument &doc, const QString &error) {
                if (generation != m_generation)
                    return;
                if (!error.isEmpty()) {
                    sync->failed = true;
                    onError(table, error);
                } else {
                    setOnline(true);
                    apply(doc);
                }
                finish();
            });
        };

        checkIn();

        load("platform_settings", QUrlQuery("select=display_name,timezone,assistant_provider&limit=1"), [this](const QJsonDocument &d) {
            const QJsonObject s = d.array().first().toObject();
            const QString name = s.value("display_name").toString();
            if (!name.isEmpty())
                m_displayName = name;
            const QString provider = s.value("assistant_provider").toString();
            if (!provider.isEmpty())
                m_assistantProvider = provider;
        });
        // select=* so a newer column (scopes) comes along without breaking an older backend.
        load("agents", QUrlQuery("select=*&order=created_at"), [this](const QJsonDocument &d) { m_rawAgents = toList(d); });
        // Memory arrived later than the other tables: a backend without it
        // must not make every sync fail, so its errors are only logged.
        ++sync->pending;
        m_client->select("memories", QUrlQuery("select=text,pinned,updated_at&agent_id=is.null&order=pinned.desc,updated_at.desc&limit=100"),
                         [this, generation, finish](const QJsonDocument &doc, const QString &error) {
                             if (generation != m_generation)
                                 return;
                             if (!error.isEmpty())
                                 qInfo() << "memories not available:" << error;
                             else
                                 m_rawMemories = toList(doc);
                             finish();
                         });
        // This display's own settings (newer too): optional. Sent on only when
        // the first read or a change arrives, so a sync with nothing new
        // leaves the screen alone.
        const QString deviceId = m_settings.value("device/id").toString();
        if (!deviceId.isEmpty()) {
            m_client->select("devices", QUrlQuery("select=settings&id=eq." + deviceId),
                             [this, generation](const QJsonDocument &doc, const QString &error) {
                                 if (generation != m_generation)
                                     return;
                                 if (!error.isEmpty()) {
                                     qInfo() << "display settings not available:" << error;
                                     return;
                                 }
                                 const QVariantMap settings = doc.array().first().toObject().value("settings").toObject().toVariantMap();
                                 if (m_deviceSettingsSeen && settings == m_deviceSettings)
                                     return;
                                 m_deviceSettingsSeen = true;
                                 m_deviceSettings = settings;
                                 emit deviceSettingsReceived(settings);
                             });
        }
        // Calendar subscriptions (newer too): same, optional.
        ++sync->pending;
        m_client->rpc("list_calendar_sources", QJsonObject(), [this, generation, finish](const QJsonDocument &doc, const QString &error) {
            if (generation != m_generation)
                return;
            if (!error.isEmpty())
                qInfo() << "calendar subscriptions not available:" << error;
            else
                m_rawCalendarSources = toList(doc);
            finish();
        });
        // Todos and reminders (newer too): same, optional. The open ones; a
        // reminder whose time passed before yesterday is over.
        QUrlQuery todos;
        todos.addQueryItem("select", "id,agent_id,kind,title,notes,due_at,all_day,done_at,created_at");
        todos.addQueryItem("done_at", "is.null");
        todos.addQueryItem("or", "(kind.eq.todo,due_at.gte." + QDateTime(m_today.addDays(-1), QTime(0, 0)).toUTC().toString(Qt::ISODate) + ")");
        todos.addQueryItem("order", "due_at.nullslast,created_at");
        todos.addQueryItem("limit", "200");
        ++sync->pending;
        m_client->select("todos", todos, [this, generation, finish](const QJsonDocument &doc, const QString &error) {
            if (generation != m_generation)
                return;
            if (!error.isEmpty())
                qInfo() << "todos not available:" << error;
            else
                m_rawTodos = toList(doc);
            finish();
        });
        load("briefs", QUrlQuery("select=*&order=published_at.desc&limit=100"),
             [this](const QJsonDocument &d) { m_rawBriefs = toList(d); });
        load("symbols", QUrlQuery("select=*&hidden=eq.false&order=sort_order,symbol"),
             [this](const QJsonDocument &d) { m_rawSymbols = toList(d); });
        load("quotes", QUrlQuery("select=id,agent_id,symbol,name,price,change,change_pct,currency,note,as_of&order=as_of.desc,id.desc&limit=2000"),
             [this](const QJsonDocument &d) { m_rawQuotes = toList(d); });
        // The agents' extra fields (holding, signals, stats) only for the
        // newest row of each symbol: the history doesn't need them.
        load("quotes_latest", QUrlQuery("select=symbol,agent_id,as_of,created_at,data"),
             [this](const QJsonDocument &d) { m_rawQuoteData = toList(d); });
        QUrlQuery reports;
        reports.addQueryItem("select", "*,news_items(*)");
        reports.addQueryItem("order", "report_date.desc,published_at.desc");
        reports.addQueryItem("news_items.order", "section_order,position");
        reports.addQueryItem("limit", "14");
        load("news_reports", reports, [this](const QJsonDocument &d) { m_rawReports = toList(d); });

        QUrlQuery projects;
        projects.addQueryItem("select", "*,project_updates(*)");
        projects.addQueryItem("order", "sort_order,updated_at.desc");
        projects.addQueryItem("project_updates.order", "happened_at.desc,id.desc");
        projects.addQueryItem("project_updates.limit", "8");
        load("projects", projects, [this](const QJsonDocument &d) { m_rawProjects = toList(d); });
        load("metric_settings", QUrlQuery("select=*&hidden=eq.false&order=group_name.nullslast,sort_order,key"),
             [this](const QJsonDocument &d) { m_rawMetricSettings = toList(d); });
        load("metrics", QUrlQuery("select=id,agent_id,key,label,value,unit,delta,delta_pct,note,as_of&order=as_of.desc,id.desc&limit=2000"),
             [this](const QJsonDocument &d) { m_rawMetrics = toList(d); });
        load("dashboards", QUrlQuery("select=*&hidden=eq.false&order=sort_order,title"),
             [this](const QJsonDocument &d) { m_rawDashboards = toList(d); });
        QUrlQuery events;
        events.addQueryItem("select", "*");
        events.addQueryItem("ends_at", "gte." + QDateTime(m_today.addDays(-1), QTime(0, 0)).toUTC().toString(Qt::ISODate));
        events.addQueryItem("starts_at", "lt." + QDateTime(m_today.addDays(60), QTime(0, 0)).toUTC().toString(Qt::ISODate));
        events.addQueryItem("order", "starts_at,id");
        events.addQueryItem("limit", "500");
        load("events", events, [this](const QJsonDocument &d) { m_rawEvents = toList(d); });
    });
}

// Tells the console and the phone this display is alive: devices.last_seen_at
// on its own row (RLS devices_touch), at most every few minutes.
void FeedStore::checkIn()
{
    const QString deviceId = m_settings.value("device/id").toString();
    if (deviceId.isEmpty() || (m_lastCheckIn.isValid() && m_lastCheckIn.elapsed() < kCheckInIntervalMs))
        return;
    m_lastCheckIn.start();
    const QJsonObject seen{{"last_seen_at", QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs)}};
    m_client->update("devices", QUrlQuery("id=eq." + deviceId), seen, [](const QJsonDocument &, const QString &error) {
        if (!error.isEmpty())
            qWarning() << "device check-in failed:" << error;
    });
}

// ───────────────────────────── Pairing ─────────────────────────────

void FeedStore::startPairing()
{
    setMode("pairing");
    m_pairTimer.stop();
    m_pairRetryTimer.stop();
    const int attempt = ++m_pairAttempt;

    QByteArray secret(32, Qt::Uninitialized);
    QRandomGenerator::system()->fillRange(reinterpret_cast<quint32 *>(secret.data()), secret.size() / 4);
    m_pairingSecret = QString::fromLatin1(secret.toHex());
    const QString hash = QString::fromLatin1(
        QCryptographicHash::hash(m_pairingSecret.toUtf8(), QCryptographicHash::Sha256).toHex());

    m_client->callFunction("pair-device", {{"action", "start"}, {"secretHash", hash}},
                           [this, attempt](const QJsonDocument &doc, const QString &error) {
                               if (attempt != m_pairAttempt)
                                   return;
                               if (!error.isEmpty()) {
                                   setOnline(false, error);
                                   m_pairRetryTimer.start(); // offline: try again soon
                                   return;
                               }
                               setOnline(true);
                               m_pairingCode = doc.object().value("code").toString();
                               emit pairingChanged();
                               m_pairTimer.start();
                           });
}

void FeedStore::unpair()
{
    if (m_mode == "demo") {
        emit notify(tr("Demo mode has nothing to pair"));
        return;
    }
    ++m_generation;
    m_syncTimer.stop();
    stopRetrying();
    m_settings.remove("device/refreshToken");
    m_settings.remove("device/id");
    m_client->clearSession();

    // Drop the feeds so none of it lingers behind the setup screen.
    m_rawAgents.clear();
    m_rawBriefs.clear();
    m_rawQuotes.clear();
    m_rawQuoteData.clear();
    m_rawSymbols.clear();
    m_rawReports.clear();
    m_rawProjects.clear();
    m_rawMetrics.clear();
    m_rawMetricSettings.clear();
    m_rawDashboards.clear();
    m_rawEvents.clear();
    m_rawTodos.clear();
    m_seen.clear(); // the next account's values are new, not changes
    m_lastSync = QDateTime();
    rebuild();

    startPairing();
}

void FeedStore::pollPairing()
{
    const int attempt = m_pairAttempt;
    m_client->callFunction(
        "pair-device", {{"action", "redeem"}, {"code", m_pairingCode}, {"secret", m_pairingSecret}},
        [this, attempt](const QJsonDocument &doc, const QString &error) {
            // A poll that overlapped the one that paired gets "invalid code"
            // (the code is gone): it must not start pairing over.
            if (attempt != m_pairAttempt || m_mode != "pairing")
                return;
            if (!error.isEmpty()) {
                // Expired or unknown code: show a fresh one.
                if (error.contains("HTTP 410") || error.contains("HTTP 404"))
                    startPairing();
                return;
            }
            const QJsonObject o = doc.object();
            if (o.value("status").toString() != "paired")
                return;

            m_pairTimer.stop();
            ++m_pairAttempt;
            const QJsonObject session = o.value("session").toObject();
            m_client->setSession(session.value("accessToken").toString(), session.value("refreshToken").toString());
            m_settings.setValue("device/id", o.value("deviceId").toString());
            m_lastCheckIn.invalidate(); // a new device row: check in right away
            m_pairingCode.clear();
            emit pairingChanged();

            setMode("live");
            loadLive();
            m_syncTimer.start();
            emit notify(tr("Display connected"));
        });
}

// ───────────────────────────── Shaping ─────────────────────────────

QString FeedStore::dayLabel(const QDate &day) const
{
    if (day == m_today)
        return tr("Today");
    if (day == m_today.addDays(-1))
        return tr("Yesterday");
    if (day > m_today.addDays(-7))
        return QLocale().toString(day, QStringLiteral("dddd"));
    return QLocale().toString(day, QStringLiteral("dddd, MMMM d"));
}

QString FeedStore::dayHeading(const QDate &day) const
{
    const QString name = day == m_today ? tr("Today")
                       : day == m_today.addDays(-1) ? tr("Yesterday")
                       : QLocale().toString(day, QStringLiteral("dddd"));
    return QStringLiteral("%1 %2").arg(name, day.toString(QStringLiteral("MM/dd")));
}

QString FeedStore::timeLabel(const QDateTime &when) const
{
    return QLocale().toString(when.time(), QStringLiteral("h:mm ap"));
}

QString FeedStore::tomorrowLabel() const
{
    return QLocale().toString(m_today.addDays(1), QStringLiteral("dddd"));
}

void FeedStore::showSource(const QString &agentId)
{
    if (m_newsSourceId == agentId)
        return;
    m_newsSourceId = agentId;
    m_shownReportId.clear();
    rebuild();
}

QVariantMap FeedStore::project(const QString &id) const
{
    for (const QVariant &v : m_projects) {
        if (v.toMap().value("id").toString() == id)
            return v.toMap();
    }
    return {};
}

QVariantMap FeedStore::quote(const QString &symbol) const
{
    for (const QVariant &v : m_quotes) {
        if (v.toMap().value("symbol").toString() == symbol)
            return v.toMap();
    }
    return {};
}

void FeedStore::rebuild()
{
    const QDateTime nowDt = now();
    QHash<QString, QVariantMap> agentById;
    m_agents.clear();
    for (const QVariant &v : std::as_const(m_rawAgents)) {
        QVariantMap a = v.toMap();
        a.insert("initial", a.value("name").toString().left(1).toUpper());
        const QDateTime seen = parseTimestamp(a.value("last_seen_at").toString());
        a.insert("seenLabel", seen.isValid() ? (seen.date() == m_today ? timeLabel(seen) : dayLabel(seen.date())) : tr("Never"));
        a.insert("active", a.value("revoked_at").toString().isEmpty());
        QStringList scopeLabels;
        for (const QVariant &sc : a.value("scopes").toList()) {
            const QString scope = sc.toString();
            scopeLabels << (scope == QLatin1String("calendar:read") ? tr("Calendar")
                            : scope == QLatin1String("memory:read")  ? tr("Reads memory")
                            : scope == QLatin1String("memory:write") ? tr("Keeps notes")
                                                                     : scope);
        }
        a.insert("scopeLabels", scopeLabels);
        a.insert("seenRecently", seen.isValid() && seen.secsTo(nowDt) < 6 * 3600);
        agentById.insert(a.value("id").toString(), a);
        m_agents << a;
    }
    auto agentName = [&](const QString &id) { return agentById.value(id).value("name").toString(); };
    auto agentColor = [&](const QString &id) {
        const QString c = agentById.value(id).value("color").toString();
        return c.isEmpty() ? QStringLiteral("#5B7CF5") : c;
    };

    // Briefs: newest first, without the expired ones.
    m_briefs.clear();
    for (const QVariant &v : std::as_const(m_rawBriefs)) {
        QVariantMap b = v.toMap();
        const QDateTime expires = parseTimestamp(b.value("expires_at").toString());
        if (expires.isValid() && expires < nowDt)
            continue;
        const QDateTime at = parseTimestamp(b.value("published_at").toString());
        b.insert("publishedMs", at.toMSecsSinceEpoch());
        b.insert("day", at.date().toString(Qt::ISODate));
        b.insert("dayLabel", dayLabel(at.date()));
        b.insert("timeLabel", timeLabel(at));
        b.insert("whenLabel", at.date() == m_today ? timeLabel(at) : dayLabel(at.date()) + QStringLiteral(" · ") + timeLabel(at));
        b.insert("kindLabel", kindLabel(b.value("kind").toString()));
        b.insert("agentName", agentName(b.value("agent_id").toString()));
        b.insert("agentColor", agentColor(b.value("agent_id").toString()));
        // The first paragraph, for cards.
        const QString body = b.value("body").toString().trimmed();
        const int cut = body.indexOf(QStringLiteral("\n\n"));
        b.insert("summary", (cut > 0 ? body.left(cut) : body).simplified());
        // The body for a reader: its "- " points apart from its paragraphs
        // (an indented line under a point carries on that point). `blocks`
        // keeps them in the body's order, as BriefText.swift does: a
        // paragraph's own line breaks stay (a "## " heading over its text, a
        // numbered list), and a run of points is one block.
        QStringList paragraphs, bullets, text, lines, items;
        QVariantList blocks;
        auto endParagraph = [&]() {
            if (!lines.isEmpty())
                blocks << QVariantMap{{"kind", QStringLiteral("paragraph")}, {"text", lines.join(QLatin1Char('\n'))}};
            lines.clear();
        };
        auto endPoints = [&]() {
            if (!items.isEmpty())
                blocks << QVariantMap{{"kind", QStringLiteral("points")}, {"items", items}};
            items.clear();
        };
        static const QRegularExpression blankLine(QStringLiteral("\\n\\s*\\n"));
        static const QRegularExpression bullet(QStringLiteral("^[-•*]\\s+"));
        for (const QString &block : body.split(blankLine, Qt::SkipEmptyParts)) {
            bool inBullet = false;
            for (const QString &raw : block.split(QLatin1Char('\n'))) {
                const QString line = raw.trimmed();
                if (line.isEmpty())
                    continue;
                const auto point = bullet.match(line);
                if (point.hasMatch()) {
                    if (!text.isEmpty())
                        paragraphs << text.join(QLatin1Char(' '));
                    text.clear();
                    endParagraph();
                    bullets << line.mid(point.capturedLength());
                    items << bullets.last();
                    inBullet = true;
                } else if (inBullet && raw.at(0).isSpace()) {
                    bullets.last() += QLatin1Char(' ') + line;
                    items.last() = bullets.last();
                } else {
                    text << line;
                    endPoints();
                    lines << line;
                    inBullet = false;
                }
            }
            if (!text.isEmpty())
                paragraphs << text.join(QLatin1Char(' '));
            text.clear();
            endParagraph();
            endPoints();
        }
        // A fenced code block can hold "- " lines and blank ones: kept whole.
        if (body.contains(QLatin1String("```")) || body.contains(QLatin1String("~~~")))
            blocks = {QVariantMap{{"kind", QStringLiteral("paragraph")}, {"text", body}}};
        b.insert("paragraphs", paragraphs);
        b.insert("bullets", bullets);
        b.insert("blocks", blocks);
        m_briefs << b;
    }
    std::stable_sort(m_briefs.begin(), m_briefs.end(), [](const QVariant &a, const QVariant &b) {
        return a.toMap().value("publishedMs").toLongLong() > b.toMap().value("publishedMs").toLongLong();
    });
    m_latestBrief = m_briefs.isEmpty() ? QVariantMap() : m_briefs.first().toMap();

    // Quotes: the rows of each symbol, newest first as loaded (demo rows come
    // oldest first, so they are sorted here too).
    QHash<QString, QVariantList> rowsBySymbol;
    // Each agent's newest push. A holding or a signal shows only while it is
    // part of that push: a position the agent stopped sending (sold) goes,
    // though the symbol's price stays. A push's rows share their created_at
    // (live); each quote may carry its own as_of (the last trade), so as_of
    // only stands in where created_at is missing (demo).
    QHash<QString, QDateTime> lastAsOfByAgent;
    for (const QVariant &v : std::as_const(m_rawQuotes)) {
        const QVariantMap row = v.toMap();
        rowsBySymbol[row.value("symbol").toString()] << v;
        const QDateTime at = parseTimestamp(row.value("as_of").toString());
        QDateTime &last = lastAsOfByAgent[row.value("agent_id").toString()];
        if (at.isValid() && (!last.isValid() || at > last))
            last = at;
    }
    // Live: the newest row's `data` and created_at, by symbol (quotes_latest).
    QHash<QString, QVariantMap> latestData;
    QHash<QString, QDateTime> lastPushByAgent;
    for (const QVariant &v : std::as_const(m_rawQuoteData)) {
        const QVariantMap row = v.toMap();
        latestData.insert(row.value("symbol").toString(), row);
        const QDateTime created = parseTimestamp(row.value("created_at").toString());
        QDateTime &last = lastPushByAgent[row.value("agent_id").toString()];
        if (created.isValid() && (!last.isValid() || created > last))
            last = created;
    }
    // The sums, and what each move is measured against: the value before
    // today's move, and the cost, over the holdings that gave them.
    double heldValue = 0, heldDay = 0, heldTotal = 0, dayBase = 0, costBase = 0;
    bool anyDay = false, anyTotal = false;
    int heldCount = 0;
    QString heldCurrency;
    m_quotes.clear();
    for (const QVariant &sv : std::as_const(m_rawSymbols)) {
        const QVariantMap symbol = sv.toMap();
        if (symbol.value("hidden").toBool())
            continue;
        QVariantList rows = rowsBySymbol.value(symbol.value("symbol").toString());
        if (rows.isEmpty())
            continue;
        std::stable_sort(rows.begin(), rows.end(), [](const QVariant &a, const QVariant &b) {
            return parseTimestamp(a.toMap().value("as_of").toString()) > parseTimestamp(b.toMap().value("as_of").toString());
        });
        QVariantMap q = rows.first().toMap();
        const double price = q.value("price").toDouble();
        const QString currency = q.value("currency").toString().isEmpty() ? QStringLiteral("USD") : q.value("currency").toString();
        QVariantList history;
        for (int i = qMin(rows.size(), kSparklinePoints) - 1; i >= 0; --i)
            history << rows.at(i).toMap().value("price").toDouble();
        // A missing change is taken from the previous point.
        double change = q.value("change").toDouble();
        double pct = q.value("change_pct").toDouble();
        if (q.value("change").isNull() && rows.size() > 1) {
            const double previous = rows.at(1).toMap().value("price").toDouble();
            change = price - previous;
            pct = previous != 0 ? change / previous * 100 : 0;
        }
        const QDateTime asOf = parseTimestamp(q.value("as_of").toString());
        q.insert("name", symbol.value("name").toString().isEmpty() ? q.value("name") : symbol.value("name"));
        q.insert("priceLabel", money(price, currency));
        q.insert("change", change);
        q.insert("change_pct", pct);
        q.insert("changeLabel", signedNumber(change, 2));
        q.insert("pctLabel", signedNumber(pct, 2, QStringLiteral("%")));
        q.insert("up", change >= 0);
        q.insert("flat", qFuzzyIsNull(change));
        q.insert("history", history);
        q.insert("asOfLabel", asOf.isValid() ? (asOf.date() == m_today ? timeLabel(asOf) : dayLabel(asOf.date())) : QString());
        q.insert("agentName", agentName(q.value("agent_id").toString()));
        q.insert("agentColor", agentColor(q.value("agent_id").toString()));
        // Its range, how hot today is (±3% is the scale's end), whether it's
        // live, when its price last moved here, and its usual daily swing,
        // from daily closes: each local day's newest row (rows are newest first).
        addRange(q, history, [&currency](double v) { return money(v, currency); });
        q.insert("heat", qBound(-1.0, pct / 3, 1.0));
        q.insert("fresh", isFresh(asOf, nowDt));
        markChange(q, QStringLiteral("q:") + q.value("symbol").toString(), price);
        QList<double> closes;
        QDate closeDay;
        for (const QVariant &rv : std::as_const(rows)) {
            const QDate day = parseTimestamp(rv.toMap().value("as_of").toString()).date();
            if (closes.isEmpty() || day != closeDay)
                closes.prepend(rv.toMap().value("price").toDouble());
            closeDay = day;
        }
        q.insert("swingPct", usualSwing(closes).value_or(0));

        // What the agent added: a holding, signals, the day's numbers.
        QVariantMap data = q.value("data").toMap();
        const QVariantMap latest = latestData.value(q.value("symbol").toString());
        if (!latest.isEmpty() && parseTimestamp(latest.value("as_of").toString()) == asOf)
            data = latest.value("data").toMap();
        bool current;
        const QDateTime created = parseTimestamp(latest.value("created_at").toString());
        if (created.isValid()) {
            current = created == lastPushByAgent.value(latest.value("agent_id").toString());
        } else {
            const QDateTime lastAsOf = lastAsOfByAgent.value(q.value("agent_id").toString());
            current = asOf.isValid() && lastAsOf.isValid() && asOf.secsTo(lastAsOf) <= 120;
        }
        const QVariantMap position = current ? positionOf(data, price, change, currency) : QVariantMap();
        const QVariantList signalList = current ? signalsOf(data) : QVariantList();
        q.remove("data");
        q.insert("held", !position.isEmpty());
        q.insert("position", position);
        q.insert("signals", signalList);
        q.insert("signalTone", signalList.isEmpty() ? QString() : signalList.first().toMap().value("tone").toString());
        q.insert("stats", statsOf(data, currency));
        q.insert("ranges", rangesOf(data, price, currency));
        // Today's chart, labelled in local time; a tile's line is today's
        // prices when there are bars, else the push history.
        QVariantMap intraday = intradayOf(data, price - change, currency);
        if (!intraday.isEmpty()) {
            const QDateTime opens = QDateTime::fromSecsSinceEpoch(qint64(intraday.value("openSecs").toDouble())).toLocalTime();
            const QDateTime closes = QDateTime::fromSecsSinceEpoch(qint64(intraday.value("closeSecs").toDouble())).toLocalTime();
            intraday.insert("openLabel", timeLabel(opens));
            intraday.insert("closeLabel", timeLabel(closes));
            intraday.insert("dayLabel", opens.date() == m_today ? tr("Today") : dayLabel(opens.date()));
        }
        q.insert("intraday", intraday);
        q.insert("tilePoints", intraday.isEmpty() ? history : intraday.value("prices").toList());
        if (!position.isEmpty()) {
            ++heldCount;
            const double value = position.value("value").toDouble();
            heldValue += value;
            if (position.contains("dayChange")) {
                heldDay += position.value("dayChange").toDouble();
                dayBase += value - position.value("dayChange").toDouble();
                anyDay = true;
            }
            if (position.contains("totalChange")) {
                heldTotal += position.value("totalChange").toDouble();
                costBase += value - position.value("totalChange").toDouble();
                anyTotal = true;
            }
            if (heldCurrency.isEmpty())
                heldCurrency = currency;
        }
        m_quotes << q;
    }

    // Each holding's share of them all (unless the agent said), and the total.
    m_portfolio = QVariantMap{{"held", heldCount > 0}, {"count", heldCount}};
    if (heldCount > 0) {
        for (QVariant &v : m_quotes) {
            QVariantMap q = v.toMap();
            QVariantMap position = q.value("position").toMap();
            if (position.isEmpty())
                continue;
            const double weight = position.contains("weight") ? position.value("weight").toDouble()
                                                              : (heldValue > 0 ? position.value("value").toDouble() / heldValue * 100 : 0);
            position.insert("weightLabel", tr("%1% of holdings").arg(QLocale().toString(weight, 'f', weight < 10 ? 1 : 0)));
            q.insert("position", position);
            v = q;
        }
        m_portfolio.insert("valueLabel", money(heldValue, heldCurrency));
        if (anyDay) {
            m_portfolio.insert("dayChangeLabel", signedMoney(heldDay, heldCurrency));
            m_portfolio.insert("dayUp", heldDay >= 0);
            if (dayBase > 0)
                m_portfolio.insert("dayPctLabel", signedNumber(heldDay / dayBase * 100, 2, QStringLiteral("%")));
        }
        if (anyTotal) {
            m_portfolio.insert("totalChangeLabel", signedMoney(heldTotal, heldCurrency));
            m_portfolio.insert("totalUp", heldTotal >= 0);
            if (costBase > 0)
                m_portfolio.insert("totalPctLabel", signedNumber(heldTotal / costBase * 100, 1, QStringLiteral("%")));
        }
    }

    // How the market moved, and its big movers: 2% or more, or 2.5× the
    // usual daily swing (and 1% at least), on a quote from the last 36 h.
    int ups = 0, downs = 0, flats = 0;
    m_movers.clear();
    for (QVariant &v : m_quotes) {
        QVariantMap q = v.toMap();
        const double pct = q.value("change_pct").toDouble();
        if (q.value("flat").toBool())
            ++flats;
        else if (q.value("change").toDouble() > 0)
            ++ups;
        else
            ++downs;
        const QDateTime asOf = parseTimestamp(q.value("as_of").toString());
        const double swing = q.value("swingPct").toDouble();
        const double ratio = swing > 0 ? qAbs(pct) / swing : -1;
        const bool big = qAbs(pct) >= kBigMovePct;
        const bool unusual = ratio >= kSwingRatio && qAbs(pct) >= kSwingFloorPct;
        const bool moved = std::isfinite(pct) && pct != 0 && (!asOf.isValid() || asOf.msecsTo(nowDt) <= kQuoteFreshMs) && (big || unusual);
        q.insert("bigMove", moved);
        v = q;
        if (!moved)
            continue;
        const QString symbol = q.value("symbol").toString();
        const QString dir = pct > 0 ? tr("up") : tr("down");
        QStringList detail{q.value("priceLabel").toString()};
        if (ratio >= 1.5)
            detail << tr("%1× its usual daily move").arg(QLocale().toString(ratio, 'f', 1));
        m_movers << QVariantMap{{"id", QStringLiteral("mover:") + symbol}, {"kind", "mover"}, {"icon", pct > 0 ? "arrow-up" : "arrow-down"},
                                {"tone", pct > 0 ? "good" : "bad"}, {"color", pct > 0 ? kGood : kBad},
                                {"title", tr("%1 is %2 %3%").arg(symbol, dir, pct1(pct))}, {"detail", detail.join(QStringLiteral(" · "))},
                                {"screen", 2}, {"segment", "markets"}, {"itemId", symbol},
                                {"question", tr("Why is %1 %2 %3% today?").arg(symbol, dir, pct1(pct))},
                                {"strength", qMax(qAbs(pct) / kBigMovePct, ratio / kSwingRatio)}};
    }
    std::stable_sort(m_movers.begin(), m_movers.end(), [](const QVariant &a, const QVariant &b) {
        return a.toMap().value("strength").toDouble() > b.toMap().value("strength").toDouble();
    });
    QStringList breadth;
    if (ups)
        breadth << tr("%1 up").arg(ups);
    if (downs)
        breadth << tr("%1 down").arg(downs);
    if (flats)
        breadth << tr("%1 flat").arg(flats);
    m_marketBreadth = QVariantMap{{"up", ups}, {"down", downs}, {"flat", flats}, {"total", int(m_quotes.size())},
                                  {"label", breadth.join(QStringLiteral(" · "))}};

    // News: the sources, every report for the picker, and the shown one in full.
    m_newsSources.clear();
    QSet<QString> seenSources;
    for (const QVariant &rv : std::as_const(m_rawReports)) {
        const QString agent = rv.toMap().value("agent_id").toString();
        if (seenSources.contains(agent))
            continue;
        seenSources.insert(agent);
        m_newsSources << QVariantMap{{"id", agent}, {"name", agentName(agent).isEmpty() ? tr("Source") : agentName(agent)},
                                     {"color", agentColor(agent)}};
    }
    if (!m_newsSourceId.isEmpty() && !seenSources.contains(m_newsSourceId))
        m_newsSourceId.clear(); // that source's reports are gone
    m_newsReports.clear();
    QVariantMap shown;
    for (const QVariant &rv : std::as_const(m_rawReports)) {
        const QVariantMap r = rv.toMap();
        if (!m_newsSourceId.isEmpty() && r.value("agent_id").toString() != m_newsSourceId)
            continue;
        const QDate day = QDate::fromString(r.value("report_date").toString(), Qt::ISODate);
        QVariantMap entry{{"id", r.value("id")},
                          {"slug", r.value("slug")},
                          {"displayDate", r.value("display_date").toString().isEmpty() ? QLocale().toString(day, QStringLiteral("MMM d, yyyy")) : r.value("display_date")},
                          {"dayLabel", day.isValid() ? dayLabel(day) : QString()},
                          {"agentName", agentName(r.value("agent_id").toString())},
                          {"agentColor", agentColor(r.value("agent_id").toString())},
                          {"itemCount", r.value("news_items").toList().size()}};
        m_newsReports << entry;
        if (shown.isEmpty() && (m_shownReportId.isEmpty() || r.value("id").toString() == m_shownReportId))
            shown = r;
    }
    if (shown.isEmpty() && !m_newsReports.isEmpty()) {
        // The picked report is gone: back to the newest of the source.
        const QString firstId = m_newsReports.first().toMap().value("id").toString();
        for (const QVariant &rv : std::as_const(m_rawReports))
            if (rv.toMap().value("id").toString() == firstId)
                shown = rv.toMap();
    }
    m_news.clear();
    m_stories.clear();
    if (!shown.isEmpty()) {
        const QDate day = QDate::fromString(shown.value("report_date").toString(), Qt::ISODate);
        const QString heroKey = shown.value("hero_item").toString();
        QVariantList items = shown.value("news_items").toList();
        std::stable_sort(items.begin(), items.end(), [](const QVariant &a, const QVariant &b) {
            const QVariantMap ma = a.toMap(), mb = b.toMap();
            if (ma.value("section_order").toInt() != mb.value("section_order").toInt())
                return ma.value("section_order").toInt() < mb.value("section_order").toInt();
            return ma.value("position").toInt() < mb.value("position").toInt();
        });
        QVariantList sections;
        QHash<QString, int> sectionIndex;
        QVariantMap hero;
        for (const QVariant &iv : std::as_const(items)) {
            QVariantMap item = iv.toMap();
            const QString key = item.value("section_key").toString();
            if (!sectionIndex.contains(key)) {
                sectionIndex.insert(key, sections.size());
                sections << QVariantMap{{"key", key},
                                        {"name", item.value("section_name")},
                                        {"color", sectionColor(key, sections.size())},
                                        {"items", QVariantList()}};
            }
            const int at = sectionIndex.value(key);
            QVariantMap section = sections.at(at).toMap();
            item.insert("sectionName", section.value("name"));
            item.insert("sectionColor", section.value("color"));
            item.insert("isHero", !heroKey.isEmpty() && item.value("item_key").toString() == heroKey);
            item.insert("imageUrl", item.value("image_url").toString());
            item.insert("sourceDomain", item.value("source_domain").toString());
            if (item.value("isHero").toBool())
                hero = item;
            QVariantList sectionItems = section.value("items").toList();
            sectionItems << item;
            section.insert("items", sectionItems);
            sections[at] = section;
            m_stories << item;
        }
        if (hero.isEmpty() && !m_stories.isEmpty())
            hero = m_stories.first().toMap();
        m_news = QVariantMap{{"id", shown.value("id")},
                             {"slug", shown.value("slug")},
                             {"displayDate", shown.value("display_date").toString().isEmpty() ? QLocale().toString(day, QStringLiteral("MMMM d, yyyy")) : shown.value("display_date")},
                             {"dayLabel", day.isValid() ? dayLabel(day) : QString()},
                             {"isToday", day == m_today},
                             {"agentName", agentName(shown.value("agent_id").toString())},
                             {"agentColor", agentColor(shown.value("agent_id").toString())},
                             {"hero", hero},
                             {"sections", sections},
                             {"itemCount", m_stories.size()}};
    }
    rebuildProductivity(agentById);
    rebuildTimeline(agentById);
    rebuildHighlights();
    m_calendarSources.clear();
    for (const QVariant &v : std::as_const(m_rawCalendarSources)) {
        QVariantMap c = v.toMap();
        const QDateTime at = parseTimestamp(c.value("last_synced_at").toString());
        QVariantMap out{{"name", c.value("name")},
                        {"color", c.value("color").toString().isEmpty() ? QStringLiteral("#14C2C2") : c.value("color")},
                        {"enabled", c.value("enabled", true).toBool()},
                        {"error", c.value("last_error").toString()},
                        {"eventCount", c.value("event_count").toInt()},
                        {"syncedLabel", at.isValid() ? (at.date() == m_today ? timeLabel(at) : dayLabel(at.date())) : tr("Not read yet")}};
        m_calendarSources << out;
    }
    m_memories.clear();
    for (const QVariant &v : std::as_const(m_rawMemories)) {
        QVariantMap m = v.toMap();
        const QDateTime at = parseTimestamp(m.value("updated_at").toString());
        m.insert("pinned", m.value("pinned").toBool());
        m.insert("updatedLabel", at.isValid() ? (at.date() == m_today ? timeLabel(at) : dayLabel(at.date())) : QString());
        m_memories << m;
    }
    // Nothing new (most syncs: the same rows a minute later): say nothing.
    // QML can't tell an equal list from a new one, so a dataChanged rebuilds
    // the delegates of every Store model on all seven screens.
    QVariantList published = publishedState();
    if (published == m_published)
        return;
    m_published = std::move(published);
    emit dataChanged();
}

// What dataChanged announces: every property it is the NOTIFY of, read
// through the meta-object so a property added later is counted too.
QVariantList FeedStore::publishedState() const
{
    QVariantList state;
    const QMetaMethod changed = QMetaMethod::fromSignal(&FeedStore::dataChanged);
    const QMetaObject *meta = metaObject();
    for (int i = meta->propertyOffset(); i < meta->propertyCount(); ++i) {
        const QMetaProperty property = meta->property(i);
        if (property.hasNotifySignal() && property.notifySignal() == changed)
            state << property.read(this);
    }
    return state;
}

namespace {

QString kindIcon(const QString &kind)
{
    if (kind == QLatin1String("commit")) return QStringLiteral("brief");
    if (kind == QLatin1String("pr")) return QStringLiteral("link");
    if (kind == QLatin1String("ci")) return QStringLiteral("check");
    if (kind == QLatin1String("deploy")) return QStringLiteral("send");
    if (kind == QLatin1String("alert")) return QStringLiteral("info");
    if (kind == QLatin1String("done")) return QStringLiteral("check");
    return QStringLiteral("chat");
}

QString statusLabel(const QString &status)
{
    if (status == QLatin1String("blocked")) return QObject::tr("Blocked");
    if (status == QLatin1String("paused")) return QObject::tr("Paused");
    if (status == QLatin1String("done")) return QObject::tr("Done");
    return QObject::tr("Active");
}

QString statusColor(const QString &status)
{
    if (status == QLatin1String("blocked")) return QStringLiteral("#F07F5A");
    if (status == QLatin1String("paused")) return QStringLiteral("#F6B94A");
    if (status == QLatin1String("done")) return QStringLiteral("#8F95A1");
    return QStringLiteral("#3DB37A");
}

int statusRank(const QString &status)
{
    if (status == QLatin1String("blocked")) return 0;
    if (status == QLatin1String("active")) return 1;
    if (status == QLatin1String("paused")) return 2;
    return 3;
}

// A project's `stages` as names: the database's jsonb list, which arrives as
// a list, or (from an older row or a hand-made one) not at all.
QStringList stageNames(const QVariant &stages)
{
    QStringList names;
    for (const QVariant &v : stages.toList()) {
        if (!v.toString().isEmpty())
            names << v.toString();
    }
    return names;
}

// A metric's value as people read it: 1.2M, 4,280, 99.98 %, 212 ms.
QString metricLabel(double value, const QString &unit)
{
    const QLocale locale;
    QString number;
    const double a = qAbs(value);
    if (a >= 1e9) number = locale.toString(value / 1e9, 'f', 1) + QStringLiteral("B");
    else if (a >= 1e6) number = locale.toString(value / 1e6, 'f', 1) + QStringLiteral("M");
    else if (a >= 1e4) number = locale.toString(qRound64(value));
    else if (a == std::floor(a)) number = locale.toString(qRound64(value));
    else number = locale.toString(value, 'f', 2);
    if (unit == QLatin1String("USD")) return QStringLiteral("$") + number;
    if (unit == QLatin1String("%")) return number + QStringLiteral("%");
    return unit.isEmpty() ? number : number + QLatin1Char(' ') + unit;
}

} // namespace

QVariantMap FeedStore::stageTrack(const QStringList &stages, const QString &stage, const QString &status)
{
    const int n = int(stages.size());
    if (!n)
        return {};
    // Each step's name, its state, and the word under it on the stepper.
    auto step = [](const QString &name, const QString &state, int i) {
        QString word;
        if (state == QLatin1String("done")) word = tr("Done");
        else if (state == QLatin1String("current")) word = tr("Now");
        else if (state == QLatin1String("blocked")) word = tr("Blocked here");
        else if (state == QLatin1String("paused")) word = tr("Paused here");
        else word = tr("Stage %1").arg(i + 1);
        return QVariantMap{{"name", name}, {"state", state}, {"word", word}};
    };
    QVariantList steps;
    if (status == QLatin1String("done")) {
        for (int i = 0; i < n; ++i)
            steps << step(stages.at(i), QStringLiteral("done"), i);
        return {{"steps", steps}, {"current", QString()}, {"index", n},
                {"headline", n == 1 ? tr("Done") : tr("All %1 stages done").arg(n)}, {"position", tr("%1 of %2").arg(n).arg(n)}};
    }
    const int index = stage.isEmpty() ? -1 : int(stages.indexOf(stage));
    const QString here = status == QLatin1String("blocked") ? QStringLiteral("blocked")
                         : status == QLatin1String("paused") ? QStringLiteral("paused")
                                                             : QStringLiteral("current");
    for (int i = 0; i < n; ++i)
        steps << step(stages.at(i), i < index ? QStringLiteral("done") : i == index ? here : QStringLiteral("next"), i);
    if (index < 0)
        return {{"steps", steps}, {"current", QString()}, {"index", -1}, {"headline", tr("Not started")},
                {"position", n == 1 ? tr("1 stage") : tr("%1 stages").arg(n)}};
    const QString name = stages.at(index);
    return {{"steps", steps}, {"current", name}, {"index", index},
            {"headline", here == QLatin1String("blocked") ? tr("Blocked in %1").arg(name)
                         : here == QLatin1String("paused") ? tr("Paused in %1").arg(name)
                                                           : name},
            {"position", tr("%1 of %2").arg(index + 1).arg(n)}};
}

QString FeedStore::timeInStage(const QDateTime &since, const QDateTime &now)
{
    if (!since.isValid())
        return {};
    const double hours = double(std::max<qint64>(0, since.msecsTo(now))) / 3600000.0;
    if (hours < 1) return tr("under an hour");
    if (hours < 24) return tr("%1 hr").arg(int(hours));
    const int days = int(hours / 24);
    if (days < 14) return days == 1 ? tr("1 day") : tr("%1 days").arg(days);
    if (days < 60) return tr("%1 wk").arg(days / 7);
    return tr("%1 mo").arg(days / 30);
}

// Projects, metrics, dashboards and the calendar, decorated for QML.
void FeedStore::rebuildProductivity(const QHash<QString, QVariantMap> &agentById)
{
    const QDateTime nowDt = now();
    auto agentName = [&](const QString &id) { return agentById.value(id).value("name").toString(); };
    auto agentColor = [&](const QString &id) {
        const QString c = agentById.value(id).value("color").toString();
        return c.isEmpty() ? QStringLiteral("#5B7CF5") : c;
    };

    // Projects: blocked first, then active, paused, done.
    m_projects.clear();
    for (const QVariant &v : std::as_const(m_rawProjects)) {
        QVariantMap p = v.toMap();
        const QString status = p.value("status").toString();
        p.insert("statusLabel", statusLabel(status));
        p.insert("statusColor", statusColor(status));
        p.insert("statusRank", statusRank(status));
        p.insert("color", p.value("color").toString().isEmpty() ? agentColor(p.value("agent_id").toString()) : p.value("color"));
        p.insert("agentName", agentName(p.value("agent_id").toString()));
        p.insert("hasProgress", !p.value("progress").isNull());
        // Its stages, when the agent lays them out, and how long it has been
        // in the one it is in (not once it's done).
        const QVariantMap track = stageTrack(stageNames(p.value("stages")), p.value("stage").toString(), status);
        p.insert("hasStages", !track.isEmpty());
        p.insert("track", track);
        p.insert("stageFor", !track.value("current").toString().isEmpty()
                                 ? timeInStage(parseTimestamp(p.value("stage_since").toString()), nowDt) : QString());
        const QDateTime updated = parseTimestamp(p.value("updated_at").toString());
        p.insert("updatedLabel", updated.isValid() ? (updated.date() == m_today ? timeLabel(updated) : dayLabel(updated.date())) : QString());
        QVariantList updates = p.value("project_updates").toList();
        std::stable_sort(updates.begin(), updates.end(), [](const QVariant &a, const QVariant &b) {
            return parseTimestamp(a.toMap().value("happened_at").toString()) > parseTimestamp(b.toMap().value("happened_at").toString());
        });
        for (QVariant &uv : updates) {
            QVariantMap u = uv.toMap();
            const QDateTime at = parseTimestamp(u.value("happened_at").toString());
            u.insert("whenLabel", at.isValid() ? (at.date() == m_today ? timeLabel(at) : dayLabel(at.date()) + QStringLiteral(" · ") + timeLabel(at)) : QString());
            u.insert("icon", kindIcon(u.value("kind").toString()));
            uv = u;
        }
        p.insert("updates", updates);
        p.insert("lastUpdate", updates.isEmpty() ? QVariant() : updates.first());
        m_projects << p;
    }
    std::stable_sort(m_projects.begin(), m_projects.end(), [](const QVariant &a, const QVariant &b) {
        const QVariantMap ma = a.toMap(), mb = b.toMap();
        if (ma.value("statusRank").toInt() != mb.value("statusRank").toInt())
            return ma.value("statusRank").toInt() < mb.value("statusRank").toInt();
        return ma.value("sort_order").toInt() < mb.value("sort_order").toInt();
    });

    // Metrics: the visible ones in order, each with its history, then grouped.
    QHash<QString, QVariantList> rowsByKey;
    for (const QVariant &v : std::as_const(m_rawMetrics))
        rowsByKey[v.toMap().value("key").toString()] << v;
    m_metrics.clear();
    m_metricGroups.clear();
    m_anomalies.clear();
    QHash<QString, int> groupIndex;
    for (const QVariant &sv : std::as_const(m_rawMetricSettings)) {
        const QVariantMap setting = sv.toMap();
        if (setting.value("hidden").toBool())
            continue;
        QVariantList rows = rowsByKey.value(setting.value("key").toString());
        if (rows.isEmpty())
            continue;
        std::stable_sort(rows.begin(), rows.end(), [](const QVariant &a, const QVariant &b) {
            return parseTimestamp(a.toMap().value("as_of").toString()) > parseTimestamp(b.toMap().value("as_of").toString());
        });
        QVariantMap m = rows.first().toMap();
        const double value = m.value("value").toDouble();
        const QString unit = m.value("unit").toString();
        QVariantList history;
        for (int i = qMin(rows.size(), kSparklinePoints) - 1; i >= 0; --i)
            history << rows.at(i).toMap().value("value").toDouble();
        const bool rowHasDelta = !m.value("delta").isNull();
        const bool rowHasPct = !m.value("delta_pct").isNull();
        double delta = m.value("delta").toDouble();
        double pct = m.value("delta_pct").toDouble();
        const bool hasDelta = rowHasDelta || rowHasPct;
        if (!hasDelta && rows.size() > 1) {
            const double previous = rows.at(1).toMap().value("value").toDouble();
            delta = value - previous;
            pct = previous != 0 ? delta / previous * 100 : 0;
        }
        const QString label = setting.value("label").toString().isEmpty() ? m.value("label").toString() : setting.value("label").toString();
        const QDateTime asOf = parseTimestamp(m.value("as_of").toString());
        m.insert("label", label.isEmpty() ? m.value("key") : label);
        m.insert("group", setting.value("group_name").toString());
        m.insert("valueLabel", metricLabel(value, unit));
        m.insert("delta", delta);
        m.insert("delta_pct", pct);
        m.insert("hasDelta", hasDelta || rows.size() > 1);
        // The agent's percentage when that is all it sent; otherwise the change itself.
        m.insert("deltaLabel", !rowHasDelta && rowHasPct ? signedNumber(pct, 1, QStringLiteral("%"))
                                                          : signedNumber(delta, qAbs(delta) == std::floor(qAbs(delta)) ? 0 : 2));
        m.insert("pctLabel", signedNumber(pct, 1, QStringLiteral("%")));
        m.insert("up", delta >= 0);
        m.insert("history", history);
        m.insert("asOfLabel", asOf.isValid() ? (asOf.date() == m_today ? timeLabel(asOf) : dayLabel(asOf.date())) : QString());
        m.insert("agentName", agentName(m.value("agent_id").toString()));
        // Which way is good news for it and which way it went (`up` counts a
        // percentage-only change as 0), its range, whether it's live and when
        // its value last moved here.
        const QString key = m.value("key").toString();
        const bool upGood = upIsGood(unit, key);
        const double move = rowHasDelta || !rowHasPct ? delta : pct;
        m.insert("goodDirection", upGood ? "up" : "down");
        m.insert("trend", move > 0 ? "up" : move < 0 ? "down" : "flat");
        m.insert("good", move == 0 || (move > 0) == upGood);
        addRange(m, history, [&unit](double v) { return metricLabel(v, unit); });
        m.insert("fresh", isFresh(asOf, nowDt));
        markChange(m, QStringLiteral("m:") + key, value);
        // Far off its usual: a robust z over the history, or, with too little
        // history (or none that varies) for one, a 10% jump the agent reported.
        QList<double> points;
        for (const QVariant &h : std::as_const(history))
            points << h.toDouble();
        const std::optional<double> usual = median(points.mid(0, points.size() - 1));
        m.insert("usualLabel", usual ? metricLabel(*usual, unit) : QString());
        int dir = 0;
        double strength = 0;
        bool unusual = false;
        if (const std::optional<double> z = robustZ(points)) {
            if (qAbs(*z) >= kAnomalyZ) {
                dir = *z > 0 ? 1 : -1;
                strength = qAbs(*z);
                unusual = true;
            }
        } else if (rowHasPct && qAbs(pct) >= kShortHistoryPct) {
            dir = pct > 0 ? 1 : -1;
            strength = qAbs(pct) / kShortHistoryPct * kAnomalyZ;
        }
        m.insert("anomaly", dir != 0);
        if (dir != 0) {
            const QString name = m.value("label").toString();
            const bool good = (dir > 0) == upGood;
            m_anomalies << QVariantMap{
                {"id", QStringLiteral("metric:") + key}, {"kind", "metric"}, {"icon", "chart"},
                {"tone", good ? "good" : "bad"}, {"color", good ? kGood : kBad},
                {"title", unusual ? tr("%1 is unusually %2").arg(name, dir > 0 ? tr("high") : tr("low"))
                                  : tr("%1 is %2 %3%").arg(name, dir > 0 ? tr("up") : tr("down"), pct1(pct))},
                {"detail", unusual && usual ? tr("%1, against a usual %2").arg(m.value("valueLabel").toString(), metricLabel(*usual, unit))
                                            : m.value("valueLabel").toString()},
                {"screen", 2}, {"segment", "metrics"}, {"itemId", key},
                {"question", tr("What's behind the %1 in %2?").arg(dir > 0 ? tr("rise") : tr("drop"), name)},
                {"strength", strength}};
        }
        m_metrics << m;
        const QString group = m.value("group").toString().isEmpty() ? tr("Metrics") : m.value("group").toString();
        if (!groupIndex.contains(group)) {
            groupIndex.insert(group, m_metricGroups.size());
            m_metricGroups << QVariantMap{{"name", group}, {"metrics", QVariantList()}};
        }
        QVariantMap g = m_metricGroups.at(groupIndex.value(group)).toMap();
        QVariantList list = g.value("metrics").toList();
        list << m;
        g.insert("metrics", list);
        m_metricGroups[groupIndex.value(group)] = g;
    }
    std::stable_sort(m_anomalies.begin(), m_anomalies.end(), [](const QVariant &a, const QVariant &b) {
        return a.toMap().value("strength").toDouble() > b.toMap().value("strength").toDouble();
    });

    // Dashboards: each widget gets display labels so QML needs no math.
    m_dashboards.clear();
    for (const QVariant &v : std::as_const(m_rawDashboards)) {
        QVariantMap d = v.toMap();
        if (d.value("hidden").toBool())
            continue;
        QVariantList widgets;
        for (const QVariant &wv : d.value("widgets").toList()) {
            QVariantMap w = wv.toMap();
            const QString type = w.value("type").toString();
            const QString unit = w.value("unit").toString();
            if (type == QLatin1String("metric")) {
                w.insert("valueLabel", metricLabel(w.value("value").toDouble(), unit));
                const bool hasPct = !w.value("delta_pct").isNull();
                const bool hasDelta = !w.value("delta").isNull();
                w.insert("hasDelta", hasPct || hasDelta);
                w.insert("deltaLabel", hasPct ? signedNumber(w.value("delta_pct").toDouble(), 1, QStringLiteral("%"))
                                              : hasDelta ? signedNumber(w.value("delta").toDouble(), 0) : QString());
                w.insert("up", hasPct ? w.value("delta_pct").toDouble() >= 0 : w.value("delta").toDouble() >= 0);
                // As for metrics: which way is good news, so a falling error
                // rate reads as good. The label stands in for the key.
                const double move = hasPct ? w.value("delta_pct").toDouble() : w.value("delta").toDouble();
                const bool upGood = upIsGood(unit, w.value("label").toString());
                w.insert("trend", move > 0 ? "up" : move < 0 ? "down" : "flat");
                w.insert("good", move == 0 || (move > 0) == upGood);
            } else if (type == QLatin1String("progress")) {
                const double max = w.value("max").toDouble() > 0 ? w.value("max").toDouble() : 100;
                const double value = w.value("value").toDouble();
                w.insert("fraction", qBound(0.0, value / max, 1.0));
                w.insert("valueLabel", unit == QLatin1String("%") || w.value("max").isNull()
                                           ? QStringLiteral("%1%").arg(qRound(value / max * 100))
                                           : QStringLiteral("%1 / %2").arg(metricLabel(value, unit), metricLabel(max, unit)));
            } else if (type == QLatin1String("status")) {
                const QString state = w.value("state").toString();
                w.insert("stateColor", state == QLatin1String("ok") ? QStringLiteral("#3DB37A")
                                       : state == QLatin1String("warn") ? QStringLiteral("#F6B94A")
                                       : state == QLatin1String("down") ? QStringLiteral("#F07F5A") : QStringLiteral("#8F95A1"));
                w.insert("stateLabel", state == QLatin1String("ok") ? tr("OK") : state == QLatin1String("warn") ? tr("Warning")
                                       : state == QLatin1String("down") ? tr("Down") : tr("Unknown"));
            } else if (type == QLatin1String("chart")) {
                const QVariantList points = w.value("points").toList();
                w.insert("valueLabel", points.isEmpty() ? QString() : metricLabel(points.last().toDouble(), unit));
            } else if (type == QLatin1String("list")) {
                QStringList items;
                for (const QVariant &iv : w.value("items").toList())
                    items << iv.toString();
                w.insert("items", items);
            }
            w.insert("wide", type == QLatin1String("chart") || type == QLatin1String("list") || type == QLatin1String("text"));
            // A type this display can't draw yet (a newer agent's) stays in the
            // list, so indexes hold, and QML skips it.
            static const QSet<QString> knownTypes{"metric", "status", "progress", "chart", "list", "text"};
            w.insert("known", knownTypes.contains(type));
            widgets << w;
        }
        d.insert("widgets", widgets);
        d.insert("agentName", agentName(d.value("agent_id").toString()));
        d.insert("agentColor", agentColor(d.value("agent_id").toString()));
        const QDateTime updated = parseTimestamp(d.value("updated_at").toString());
        d.insert("updatedLabel", updated.isValid() ? (updated.date() == m_today ? timeLabel(updated) : dayLabel(updated.date())) : QString());
        m_dashboards << d;
    }

    // Events: by start, with labels; the days from today on; what's next.
    m_events.clear();
    for (const QVariant &v : std::as_const(m_rawEvents)) {
        QVariantMap e = v.toMap();
        const QDateTime start = parseTimestamp(e.value("starts_at").toString());
        const QDateTime end = parseTimestamp(e.value("ends_at").toString());
        if (!start.isValid())
            continue;
        e.insert("startMs", start.toMSecsSinceEpoch());
        e.insert("endMs", end.toMSecsSinceEpoch());
        e.insert("day", start.date().toString(Qt::ISODate));
        e.insert("dayLabel", dayLabel(start.date()));
        e.insert("dayHeading", dayHeading(start.date()));
        e.insert("timeLabel", e.value("all_day").toBool() ? tr("All day") : timeLabel(start) + QStringLiteral(" – ") + timeLabel(end));
        e.insert("startLabel", e.value("all_day").toBool() ? tr("All day") : timeLabel(start));
        e.insert("color", e.value("color").toString().isEmpty() ? agentColor(e.value("agent_id").toString()) : e.value("color"));
        e.insert("now", start <= nowDt && end >= nowDt);
        e.insert("past", end < nowDt);
        m_events << e;
    }
    std::stable_sort(m_events.begin(), m_events.end(), [](const QVariant &a, const QVariant &b) {
        const QVariantMap ma = a.toMap(), mb = b.toMap();
        if (ma.value("day") != mb.value("day"))
            return ma.value("day").toString() < mb.value("day").toString();
        if (ma.value("all_day").toBool() != mb.value("all_day").toBool())
            return ma.value("all_day").toBool();
        return ma.value("startMs").toLongLong() < mb.value("startMs").toLongLong();
    });
    m_eventDays.clear();
    m_upcoming.clear();
    QHash<QString, int> dayIndex;
    for (const QVariant &v : std::as_const(m_events)) {
        const QVariantMap e = v.toMap();
        if (e.value("day").toString() < m_today.toString(Qt::ISODate))
            continue;
        const QString day = e.value("day").toString();
        if (!dayIndex.contains(day)) {
            dayIndex.insert(day, m_eventDays.size());
            m_eventDays << QVariantMap{{"day", day}, {"dayLabel", e.value("dayLabel")}, {"events", QVariantList()},
                                       {"dateLabel", QLocale().toString(QDate::fromString(day, Qt::ISODate), QStringLiteral("MMMM d"))}};
        }
        QVariantMap d = m_eventDays.at(dayIndex.value(day)).toMap();
        QVariantList list = d.value("events").toList();
        list << e;
        d.insert("events", list);
        m_eventDays[dayIndex.value(day)] = d;
        if (!e.value("past").toBool() && m_upcoming.size() < 4)
            m_upcoming << e;
    }
}

QString FeedStore::snapshotText(int maxChars) const
{
    QStringList lines;
    lines << tr("Display: %1. Local time: %2.").arg(m_displayName, QLocale().toString(now(), QStringLiteral("dddd h:mm ap")));
    if (!m_latestBrief.isEmpty()) {
        lines << tr("Latest brief (%1, %2): %3. %4")
                     .arg(m_latestBrief.value("agentName").toString(), m_latestBrief.value("whenLabel").toString(),
                          m_latestBrief.value("title").toString(), m_latestBrief.value("body").toString().simplified().left(600));
    }
    if (!m_quotes.isEmpty()) {
        QStringList parts;
        for (const QVariant &v : m_quotes) {
            const QVariantMap q = v.toMap();
            QString part = QStringLiteral("%1 %2 (%3)").arg(q.value("symbol").toString(), q.value("priceLabel").toString(), q.value("pctLabel").toString());
            const QVariantMap position = q.value("position").toMap();
            if (!position.isEmpty()) {
                QStringList held{position.value("sharesLabel").toString(), position.value("valueLabel").toString()};
                if (position.contains("dayChangeLabel"))
                    held << tr("%1 today").arg(position.value("dayChangeLabel").toString());
                if (position.contains("totalChangeLabel"))
                    held << tr("%1 overall").arg(position.value("totalChangeLabel").toString());
                held.removeAll(QString());
                part += tr(", held: %1").arg(held.join(QStringLiteral(", ")));
            }
            QStringList signalTexts;
            for (const QVariant &sv : q.value("signals").toList())
                signalTexts << sv.toMap().value("text").toString();
            if (!signalTexts.isEmpty())
                part += tr(", signals: %1").arg(signalTexts.join(QStringLiteral("; ")));
            if (!q.value("note").toString().isEmpty())
                part += QStringLiteral(": ") + q.value("note").toString().simplified();
            parts << part;
        }
        lines << tr("Markets: %1.").arg(parts.join(QStringLiteral("; ")));
        if (m_portfolio.value("held").toBool()) {
            QStringList totals{tr("worth %1").arg(m_portfolio.value("valueLabel").toString())};
            if (m_portfolio.contains("dayChangeLabel"))
                totals << tr("%1 today").arg(m_portfolio.value("dayChangeLabel").toString());
            if (m_portfolio.contains("totalChangeLabel"))
                totals << tr("%1 overall").arg(m_portfolio.value("totalChangeLabel").toString());
            lines << tr("Holdings shown (%1 positions): %2.").arg(m_portfolio.value("count").toInt()).arg(totals.join(QStringLiteral(", ")));
        }
    }
    if (!m_stories.isEmpty()) {
        QStringList parts;
        for (const QVariant &v : m_stories) {
            const QVariantMap s = v.toMap();
            parts << QStringLiteral("%1: %2 (%3; %4)").arg(s.value("sectionName").toString(), s.value("headline").toString(),
                                                            s.value("takeaway").toString().simplified(), s.value("sourceDomain").toString());
        }
        lines << tr("Today's stories (%1): %2").arg(m_news.value("displayDate").toString(), parts.join(QStringLiteral(" | ")));
    }
    if (!m_projects.isEmpty()) {
        QStringList parts;
        for (const QVariant &v : m_projects) {
            const QVariantMap p = v.toMap();
            QString part = QStringLiteral("%1 (%2").arg(p.value("name").toString(), p.value("statusLabel").toString().toLower());
            if (p.value("hasProgress").toBool())
                part += QStringLiteral(", %1%").arg(p.value("progress").toInt());
            part += QLatin1Char(')');
            // As the console's assistant reads it: ", stage Build (2 of 4: Plan,
            // Build, Review, Ship)", or ", stages …" before the first.
            const QStringList stages = stageNames(p.value("stages"));
            if (!stages.isEmpty()) {
                const QString stage = p.value("stage").toString();
                const qsizetype at = stage.isEmpty() ? -1 : stages.indexOf(stage);
                part += at < 0 ? tr(", stages %1").arg(stages.join(QStringLiteral(", ")))
                               : tr(", stage %1 (%2 of %3: %4)").arg(stage).arg(at + 1).arg(stages.size()).arg(stages.join(QStringLiteral(", ")));
            }
            if (!p.value("next_step").toString().isEmpty())
                part += tr(": next, %1").arg(p.value("next_step").toString());
            parts << part;
        }
        lines << tr("Projects: %1.").arg(parts.join(QStringLiteral("; ")));
    }
    if (!m_metrics.isEmpty()) {
        QStringList parts;
        for (const QVariant &v : m_metrics) {
            const QVariantMap m = v.toMap();
            parts << QStringLiteral("%1 %2 (%3)").arg(m.value("label").toString(), m.value("valueLabel").toString(), m.value("pctLabel").toString());
        }
        lines << tr("Metrics: %1.").arg(parts.join(QStringLiteral("; ")));
    }
    if (!m_upcoming.isEmpty()) {
        QStringList parts;
        for (const QVariant &v : m_upcoming) {
            const QVariantMap e = v.toMap();
            parts << QStringLiteral("%1 %2 %3").arg(e.value("dayLabel").toString(), e.value("startLabel").toString(), e.value("title").toString());
        }
        lines << tr("Coming up: %1.").arg(parts.join(QStringLiteral("; ")));
    }
    QString text = lines.join(QStringLiteral("\n"));
    if (text.size() > maxChars)
        text = text.left(maxChars - 1) + QStringLiteral("…");
    return text;
}

// Today, as one stream: what arrived and what is planned, in time order.
// Screens are the nav indices in Main.qml: Briefs 1, News 3, Projects 4, Calendar 6.
void FeedStore::rebuildTimeline(const QHash<QString, QVariantMap> &agentById)
{
    m_timeline.clear();
    m_tomorrow.clear();
    auto agentName = [&](const QString &id) { return agentById.value(id).value("name").toString(); };
    auto agentColor = [&](const QString &id) {
        const QString c = agentById.value(id).value("color").toString();
        return c.isEmpty() ? QStringLiteral("#5B7CF5") : c;
    };
    // A row, shaped for the day it sits on: today's stream, or tomorrow's preview.
    auto row = [&](QVariantMap item, const QDateTime &start, const QDateTime &end, const QDate &day) {
        item.insert("startMs", start.toMSecsSinceEpoch());
        item.insert("endMs", (end.isValid() ? end : start).toMSecsSinceEpoch());
        // "3:30" over "pm": the clock face splits them, 12-hour like the rest of the display.
        const QStringList parts = QLocale().toString(start.time(), QStringLiteral("h:mm ap")).split(QLatin1Char(' '));
        const bool allDay = item.value("allDay").toBool();
        item.insert("timeLabel", allDay ? tr("All day") : parts.value(0));
        item.insert("ampm", allDay ? QString() : parts.value(1));
        // On a 24-hour dial (degrees clockwise from midnight at the top): where
        // it starts and how far it runs, cut at midnight. A moment has no
        // sweep; an all-day event goes all the way round.
        const double startAngle = allDay || start.date() < day ? 0 : dialAngle(start.time());
        const double endAngle = !end.isValid() ? startAngle : end.date() > day ? 360 : dialAngle(end.time());
        item.insert("startAngle", startAngle);
        item.insert("sweep", allDay ? 360.0 : qBound(0.0, endAngle - startAngle, 360.0 - startAngle));
        return item;
    };
    auto add = [&](QVariantMap item, const QDateTime &start, const QDateTime &end) {
        m_timeline << row(std::move(item), start, end, m_today);
    };

    // Today's news reports, every source (not just the one News is showing):
    // each report's top story, and how many more.
    for (const QVariant &rv : std::as_const(m_rawReports)) {
        const QVariantMap r = rv.toMap();
        if (QDate::fromString(r.value("report_date").toString(), Qt::ISODate) != m_today)
            continue;
        QVariantList items = r.value("news_items").toList();
        if (items.isEmpty())
            continue;
        std::stable_sort(items.begin(), items.end(), [](const QVariant &a, const QVariant &b) {
            const QVariantMap ma = a.toMap(), mb = b.toMap();
            if (ma.value("section_order").toInt() != mb.value("section_order").toInt())
                return ma.value("section_order").toInt() < mb.value("section_order").toInt();
            return ma.value("position").toInt() < mb.value("position").toInt();
        });
        const QString heroKey = r.value("hero_item").toString();
        QVariantMap hero = items.first().toMap();
        for (const QVariant &iv : std::as_const(items))
            if (!heroKey.isEmpty() && iv.toMap().value("item_key").toString() == heroKey)
                hero = iv.toMap();
        QStringList others;
        for (const QVariant &iv : std::as_const(items)) {
            const QVariantMap item = iv.toMap();
            if (item.value("item_key") != hero.value("item_key") && others.size() < 2)
                others << item.value("headline").toString();
        }
        const int more = int(items.size()) - 1 - int(others.size());
        QString detail = others.join(QStringLiteral(" · "));
        if (more > 0)
            detail += tr(" · %1 more").arg(more);
        QDateTime at = parseTimestamp(r.value("published_at").toString());
        if (!at.isValid() || at.date() != m_today)
            at = m_today.startOfDay(); // written last night for today: it opens the day
        const QString agent = r.value("agent_id").toString();
        const QString source = agentName(agent).isEmpty() ? tr("Daily Pulse") : agentName(agent);
        add(QVariantMap{{"kind", "news"}, {"id", r.value("id")}, {"agentId", agent},
                        {"label", tr("%1 · %2 stories").arg(source).arg(items.size())},
                        {"title", hero.value("headline")}, {"detail", detail}, {"imageUrl", hero.value("image_url")},
                        {"color", agentColor(agent)}, {"target", 3}},
            at, at);
    }

    // Briefs published today.
    for (const QVariant &v : std::as_const(m_briefs)) {
        const QVariantMap b = v.toMap();
        const QDateTime at = QDateTime::fromMSecsSinceEpoch(b.value("publishedMs").toLongLong());
        if (at.date() != m_today)
            continue;
        add(QVariantMap{{"kind", b.value("kind").toString() == QLatin1String("alert") ? "alert" : "brief"}, {"id", b.value("id")},
                        {"label", (b.value("agentName").toString() + QStringLiteral(" · ") + b.value("kindLabel").toString())},
                        {"title", b.value("title")}, {"detail", b.value("summary")}, {"color", b.value("agentColor")}, {"target", 1}},
            at, at);
    }

    // Project updates from today.
    for (const QVariant &v : std::as_const(m_projects)) {
        const QVariantMap p = v.toMap();
        for (const QVariant &uv : p.value("updates").toList()) {
            const QVariantMap u = uv.toMap();
            const QDateTime at = parseTimestamp(u.value("happened_at").toString());
            if (!at.isValid() || at.date() != m_today)
                continue;
            add(QVariantMap{{"kind", "project"}, {"id", p.value("id")}, {"label", p.value("name")}, {"title", u.value("text")},
                            {"detail", p.value("hasProgress").toBool() ? tr("%1% done").arg(p.value("progress").toInt()) : p.value("statusLabel").toString()},
                            {"color", p.value("statusColor")}, {"icon", u.value("icon")}, {"target", 4}},
                at, at);
        }
    }

    // Today's events (all-day ones first in the day), and tomorrow's: the
    // preview under today's last row.
    const QString todayKey = m_today.toString(Qt::ISODate), tomorrowKey = m_today.addDays(1).toString(Qt::ISODate);
    for (const QVariant &v : std::as_const(m_events)) {
        const QVariantMap e = v.toMap();
        const QString day = e.value("day").toString();
        if (day != todayKey && day != tomorrowKey)
            continue;
        const QDateTime start = QDateTime::fromMSecsSinceEpoch(e.value("startMs").toLongLong());
        const QDateTime end = QDateTime::fromMSecsSinceEpoch(e.value("endMs").toLongLong());
        const QString place = e.value("location").toString();
        const QVariantMap item{{"kind", "event"}, {"id", e.value("id")}, {"label", e.value("calendar")}, {"title", e.value("title")},
                               {"detail", e.value("all_day").toBool() ? e.value("calendar").toString()
                                                                     : e.value("timeLabel").toString() + (place.isEmpty() ? QString() : QStringLiteral(" · ") + place)},
                               {"color", e.value("color")}, {"allDay", e.value("all_day")}, {"target", 6}};
        if (day == todayKey)
            add(item, start, end);
        else
            m_tomorrow << row(item, start, end, m_today.addDays(1));
    }

    // Todos and reminders. A reminder sits at its time today; a todo due at a
    // time today sits there too, and one due today (the whole day), overdue
    // or undated heads the day with the all-day rows.
    for (const QVariant &v : std::as_const(m_rawTodos)) {
        const QVariantMap t = v.toMap();
        if (!t.value("done_at").toString().isEmpty())
            continue;
        const bool reminder = t.value("kind").toString() == QLatin1String("reminder");
        const QDateTime due = parseTimestamp(t.value("due_at").toString());
        if (reminder ? !due.isValid() || due.date() != m_today : due.isValid() && due.date() > m_today)
            continue;
        const bool timed = due.isValid() && !t.value("all_day").toBool() && due.date() == m_today;
        // "Grok · To do" over the title, as other rows name their source;
        // under it, when it's due and the notes.
        const QString kindWord = reminder ? tr("Reminder") : tr("To do");
        const QString source = agentName(t.value("agent_id").toString());
        QStringList detail;
        if (!reminder && due.isValid())
            detail << (due.date() < m_today ? tr("Was due %1").arg(dayLabel(due.date()))
                       : timed           ? tr("Due by %1").arg(timeLabel(due))
                                         : tr("Due today"));
        const QString notes = t.value("notes").toString().simplified();
        if (!notes.isEmpty())
            detail << notes;
        const QDateTime at = timed || reminder ? due : m_today.startOfDay();
        add(QVariantMap{{"kind", reminder ? "reminder" : "todo"}, {"id", t.value("id")},
                        {"label", source.isEmpty() ? kindWord : source + QStringLiteral(" · ") + kindWord}, {"title", t.value("title")},
                        {"detail", detail.join(QStringLiteral(" · "))},
                        {"color", agentColor(t.value("agent_id").toString())}, {"allDay", !(timed || reminder)}, {"target", 6}},
            at, at);
        if (!(timed || reminder)) {
            // Not "All day": it's a thing to do, not a day-long event.
            QVariantMap row = m_timeline.takeLast().toMap();
            row.insert("timeLabel", tr("To do"));
            m_timeline << row;
        }
    }

    // All-day first, then by start.
    const auto byStart = [](const QVariant &a, const QVariant &b) {
        const QVariantMap ma = a.toMap(), mb = b.toMap();
        if (ma.value("allDay").toBool() != mb.value("allDay").toBool())
            return ma.value("allDay").toBool();
        return ma.value("startMs").toLongLong() < mb.value("startMs").toLongLong();
    };
    std::stable_sort(m_timeline.begin(), m_timeline.end(), byStart);
    std::stable_sort(m_tomorrow.begin(), m_tomorrow.end(), byStart);
    armReminders();
}

// The next reminder still to come, or one whose time has just come: the
// timer fires then (at least every kDayCheckMaxMs, so a jump of the clock
// is caught). Called after every rebuild, so a new or moved reminder counts.
void FeedStore::armReminders()
{
    if (m_mode != QLatin1String("live")) {
        m_reminderTimer.stop(); // the demo's reminders are for looking at
        return;
    }
    const QDateTime nowDt = now();
    qint64 next = -1;
    for (const QVariant &v : std::as_const(m_rawTodos)) {
        const QVariantMap t = v.toMap();
        if (t.value("kind").toString() != QLatin1String("reminder") || !t.value("done_at").toString().isEmpty()
            || m_reminded.contains(t.value("id").toString()))
            continue;
        const QDateTime due = parseTimestamp(t.value("due_at").toString());
        if (!due.isValid())
            continue;
        const qint64 ms = nowDt.msecsTo(due);
        if (ms <= 0 && ms > -kReminderLateMs)
            next = 0;
        else if (ms > 0 && (next < 0 || ms < next))
            next = ms;
    }
    if (next < 0)
        m_reminderTimer.stop();
    else
        m_reminderTimer.start(int(qMin(next, kDayCheckMaxMs)));
}

void FeedStore::fireReminders()
{
    const QDateTime nowDt = now();
    for (const QVariant &v : std::as_const(m_rawTodos)) {
        const QVariantMap t = v.toMap();
        const QString id = t.value("id").toString();
        if (t.value("kind").toString() != QLatin1String("reminder") || !t.value("done_at").toString().isEmpty() || m_reminded.contains(id))
            continue;
        const QDateTime due = parseTimestamp(t.value("due_at").toString());
        const qint64 late = due.isValid() ? due.msecsTo(nowDt) : -1;
        if (late < 0 || late >= kReminderLateMs)
            continue;
        m_reminded.insert(id);
        emit reminderDue(QVariantMap{{"id", id}, {"title", t.value("title")}, {"notes", t.value("notes").toString().simplified()},
                                     {"timeLabel", timeLabel(due)}});
    }
    armReminders();
}

void FeedStore::pushDeviceSettings(const QVariantMap &patch)
{
    if (m_mode != "live" || patch.isEmpty())
        return;
    withSession([this, patch]() {
        m_client->rpc("device_update_settings", QJsonObject{{"patch", QJsonObject::fromVariantMap(patch)}},
                      [this, patch](const QJsonDocument &doc, const QString &error) {
                          if (!error.isEmpty()) {
                              qWarning() << "saving display settings failed:" << error;
                              return;
                          }
                          // What the server kept of this patch, so the next sync doesn't
                          // re-apply it. Only those keys: the rest of the row it answered
                          // may hold a change made elsewhere since the last sync (the
                          // voice, from the phone), which the next sync must still bring.
                          // A key it dropped (one an older server doesn't know) stays out.
                          const QVariantMap row = doc.object().toVariantMap();
                          for (auto it = patch.cbegin(); it != patch.cend(); ++it)
                              if (row.contains(it.key()))
                                  m_deviceSettings.insert(it.key(), row.value(it.key()));
                      });
    });
}

// ───────────────────────────── What stands out ─────────────────────────────

double FeedStore::nowAngle() const
{
    const QTime t = now().time();
    return (t.hour() * 60 + t.minute()) * 0.25; // 1440 minutes round the dial
}

void FeedStore::onMinute()
{
    // Highlights first, so a listener to both (the assistant's chips) sees
    // the new minute whole on the first signal.
    rebuildHighlights(); // "starts in 12 min", a brief turning an hour old
    emit nowAngleChanged();
    m_minuteTimer.start(untilNextMinute(now()));
}

void FeedStore::markChange(QVariantMap &row, const QString &key, double value)
{
    auto seen = m_seen.find(key);
    if (seen == m_seen.end()) {
        // First sight: 0, no change to show, so the first sync (or the demo,
        // whose rows are stamped "now") animates nothing.
        seen = m_seen.insert(key, Seen{value, 0, true});
    } else if (seen->value != value) {
        seen->changedMs = now().toMSecsSinceEpoch();
        seen->up = value > seen->value;
        seen->value = value;
    }
    row.insert("changedMs", seen->changedMs);
    row.insert("changedUp", seen->up);
}

// What stands out right now, ranked as the console's lib/insights.ts ranks
// it, with a board's status going down after a blocked project. Each points
// at its screen (Main.qml's nav indices: Briefs 1, Markets 2, News 3,
// Projects 4, Boards 5, Calendar 6) and asks a question the assistant can
// answer from the display. Checked after each rebuild and each minute.
void FeedStore::rebuildHighlights()
{
    const qint64 nowMs = now().toMSecsSinceEpoch();
    QVariantList out;
    auto item = [](const QString &id, const QString &kind, const QString &icon, const QString &tone, const QVariant &color,
                   const QString &title, const QString &detail, int screen, const QVariant &itemId, const QString &question) {
        return QVariantMap{{"id", id}, {"kind", kind}, {"icon", icon}, {"tone", tone}, {"color", color},
                           {"title", title}, {"detail", detail}, {"screen", screen}, {"segment", QString()},
                           {"board", -1}, {"itemId", itemId}, {"question", question}};
    };
    // The metrics and movers ranked in rebuild(), the strongest two of each.
    auto strongest = [&out](const QVariantList &ranked) {
        for (int i = 0; i < qMin(2, int(ranked.size())); ++i) {
            QVariantMap m = ranked.at(i).toMap();
            m.remove("strength");
            m.insert("board", -1);
            out << m;
        }
    };

    // 1. A blocked project: the one thing only you can unstick.
    QVariantList blocked;
    for (const QVariant &v : std::as_const(m_projects))
        if (v.toMap().value("status").toString() == QLatin1String("blocked"))
            blocked << v;
    if (!blocked.isEmpty()) {
        const QVariantMap p = blocked.first().toMap();
        const QString name = p.value("name").toString();
        out << item(QStringLiteral("blocked:") + p.value("id").toString(), "blocked", "info", "warn", p.value("color"),
                    blocked.size() > 1 ? tr("%1 and %2 more are blocked").arg(name, QString::number(blocked.size() - 1)) : tr("%1 is blocked").arg(name),
                    p.value("next_step").toString(), 4, p.value("id"), tr("What's blocking %1?").arg(name));
    }

    // 2. A board's status that is down (or warning): the worst, and how many more.
    struct Status
    {
        QVariantMap widget, board;
        int index;
    };
    QList<Status> statuses;
    for (int b = 0; b < m_dashboards.size(); ++b) {
        const QVariantMap d = m_dashboards.at(b).toMap();
        for (const QVariant &wv : d.value("widgets").toList()) {
            const QVariantMap w = wv.toMap();
            const QString state = w.value("state").toString();
            if (w.value("type").toString() == QLatin1String("status") && (state == QLatin1String("down") || state == QLatin1String("warn")))
                statuses << Status{w, d, b};
        }
    }
    std::stable_sort(statuses.begin(), statuses.end(), [](const Status &a, const Status &b) {
        return a.widget.value("state").toString() == QLatin1String("down") && b.widget.value("state").toString() != QLatin1String("down");
    });
    if (!statuses.isEmpty()) {
        const Status &s = statuses.first();
        const QString label = s.widget.value("label").toString();
        const bool down = s.widget.value("state").toString() == QLatin1String("down");
        QStringList detail;
        if (!s.widget.value("detail").toString().isEmpty())
            detail << s.widget.value("detail").toString();
        detail << s.board.value("title").toString();
        if (statuses.size() > 1)
            detail << tr("+%1 more").arg(statuses.size() - 1);
        QVariantMap status = item(QStringLiteral("status:%1:%2").arg(s.board.value("id").toString(), label), "status", "bolt",
                                  down ? "bad" : "warn", s.widget.value("stateColor"),
                                  down ? tr("%1 is down").arg(label) : tr("%1 has a warning").arg(label), detail.join(QStringLiteral(" · ")),
                                  5, s.board.value("id"), down ? tr("Why is %1 down?").arg(label) : tr("What's wrong with %1?").arg(label));
        status.insert("board", s.index);
        out << status;
    }

    // 3. Metrics far from their usual.
    strongest(m_anomalies);

    // 4. A meeting about to start (or that just did). Events are in time order.
    for (const QVariant &v : std::as_const(m_events)) {
        const QVariantMap e = v.toMap();
        const qint64 start = e.value("startMs").toLongLong();
        if (e.value("all_day").toBool() || start - nowMs > kEventSoonMs || nowMs - start > 5 * kMinuteMs)
            continue;
        const qint64 minutes = qRound64(double(start - nowMs) / kMinuteMs);
        const QString title = e.value("title").toString();
        const QString place = e.value("location").toString();
        out << item(QStringLiteral("event:") + e.value("id").toString(), "event", "calendar", minutes <= 10 ? "warn" : "neutral", e.value("color"),
                    start <= nowMs ? tr("%1 has started").arg(title)
                    : minutes < 1  ? tr("%1 starts now").arg(title)
                                   : tr("%1 starts in %2 min").arg(title, QString::number(minutes)),
                    place.isEmpty() ? e.value("timeLabel").toString() : e.value("timeLabel").toString() + QStringLiteral(" · ") + place,
                    6, e.value("id"), tr("What do I need for %1?").arg(title));
        break;
    }

    // 5. Big movers.
    strongest(m_movers);

    // 6. A brief from the last hour.
    if (!m_latestBrief.isEmpty()) {
        const qint64 at = m_latestBrief.value("publishedMs").toLongLong();
        if (nowMs - at < kBriefFreshMs && at - nowMs < 5 * kMinuteMs) {
            const QString agent = m_latestBrief.value("agentName").toString();
            const QString title = clip(m_latestBrief.value("title").toString(), 60);
            const QString summary = m_latestBrief.value("summary").toString();
            const QString ago = agoLabel(at, nowMs);
            out << item(QStringLiteral("brief:") + m_latestBrief.value("id").toString(), "brief", "brief",
                        m_latestBrief.value("kind").toString() == QLatin1String("alert") ? "warn" : "neutral", m_latestBrief.value("agentColor"),
                        agent.isEmpty() ? tr("New brief: “%1”").arg(title) : tr("%1 posted “%2”").arg(agent, title),
                        summary.isEmpty() ? ago : ago + QStringLiteral(" · ") + clip(summary, 120), 1, m_latestBrief.value("id"),
                        agent.isEmpty() ? tr("What's the latest brief?") : tr("What did %1 just say?").arg(agent));
        }
    }

    // 7. Today's Pulse, led by its hero story: the newest report today.
    QVariantMap pulse;
    for (const QVariant &v : std::as_const(m_timeline)) {
        const QVariantMap t = v.toMap();
        if (t.value("kind").toString() == QLatin1String("news")
            && (pulse.isEmpty() || t.value("startMs").toLongLong() > pulse.value("startMs").toLongLong()))
            pulse = t;
    }
    if (!pulse.isEmpty()) {
        const QString headline = pulse.value("title").toString();
        out << item(QStringLiteral("pulse:") + pulse.value("id").toString(), "pulse", "news", "neutral", pulse.value("color"), headline,
                    pulse.value("label").toString(), 3, pulse.value("id"), tr("Tell me more about “%1”").arg(clip(headline, 70)));
    }

    while (out.size() > kMaxHighlights)
        out.removeLast();
    if (out == m_highlights)
        return;
    m_highlights = out;
    emit highlightsChanged();
}

QVariantList FeedStore::boardLayout(int board, int columns) const
{
    if (board < 0 || board >= m_dashboards.size())
        return {};
    const QVariantList widgets = m_dashboards.at(board).toMap().value("widgets").toList();
    const int cols = qMax(1, columns);
    auto typeAt = [&widgets](qsizetype i) { return widgets.at(i).toMap().value("type").toString(); };

    // Each tile's kind and size, in the board's order.
    struct Tile
    {
        QVariantMap entry;
        int row = 0, col = 0, colSpan = 1, rowSpan = 1;
    };
    QList<Tile> tiles;
    bool heroTaken = false;
    for (qsizetype i = 0; i < widgets.size();) {
        if (!widgets.at(i).toMap().value("known").toBool()) {
            ++i;
            continue;
        }
        const QString type = typeAt(i);
        Tile t;
        QString kind = type;
        qsizetype next = i + 1;
        if (type == QLatin1String("status")) {
            while (next < widgets.size() && typeAt(next) == QLatin1String("status"))
                ++next;
            if (next - i < 2)
                next = i + 1; // one on its own stays a tile
        }
        QVariantList indexes;
        for (qsizetype j = i; j < next; ++j)
            indexes << int(j);
        if (next - i >= 2) {
            // A run of statuses: one strip across, its worst state first.
            // A long run wraps (a row a status for each column, three on
            // the small panels) into rows of even length: 7 → 4 + 3.
            kind = QStringLiteral("health");
            t.colSpan = cols;
            const int count = int(next - i), most = cols <= 2 ? 3 : cols;
            t.rowSpan = (count + most - 1) / most;
            t.entry.insert("perRow", (count + t.rowSpan - 1) / t.rowSpan);
            auto rank = [](const QString &s) { return s == QLatin1String("down") ? 3 : s == QLatin1String("warn") ? 2 : s == QLatin1String("ok") ? 0 : 1; };
            QVariantMap worst;
            int down = 0, warn = 0, ok = 0, unknown = 0;
            for (qsizetype j = i; j < next; ++j) {
                const QVariantMap w = widgets.at(j).toMap();
                const QString state = w.value("state").toString();
                if (state == QLatin1String("down"))
                    ++down;
                else if (state == QLatin1String("warn"))
                    ++warn;
                else if (state == QLatin1String("ok"))
                    ++ok;
                else
                    ++unknown;
                if (worst.isEmpty() || rank(state) > rank(worst.value("state").toString()))
                    worst = w;
            }
            QStringList summary;
            if (down)
                summary << tr("%1 down").arg(down);
            if (warn)
                summary << (warn == 1 ? tr("1 warning") : tr("%1 warnings").arg(warn));
            if (unknown)
                summary << tr("%1 unknown").arg(unknown);
            if (ok)
                summary << tr("%1 OK").arg(ok);
            t.entry.insert("state", worst.value("state").toString().isEmpty() ? QStringLiteral("unknown") : worst.value("state").toString());
            t.entry.insert("stateColor", worst.value("stateColor"));
            t.entry.insert("summary", down + warn + unknown == 0 ? tr("All OK") : summary.join(QStringLiteral(" · ")));
        } else if (type == QLatin1String("metric") && !heroTaken) {
            heroTaken = true;
            if (cols >= 4) {
                kind = QStringLiteral("hero");
                t.colSpan = 2;
                t.rowSpan = 2;
            }
        } else if (type == QLatin1String("chart")) {
            t.colSpan = qMin(4, cols);
            t.rowSpan = 2;
        } else if (type == QLatin1String("list") || type == QLatin1String("text")) {
            t.colSpan = qMin(2, cols);
        }
        t.entry.insert("index", int(i));
        t.entry.insert("indexes", indexes);
        t.entry.insert("kind", kind);
        tiles << t;
        i = next;
    }

    // First fit: each tile in order at the first place, in reading order, it fits.
    std::vector<std::vector<int>> grid; // [row][col]: the tile there, or -1
    auto at = [&](int r, int c) { return r < int(grid.size()) ? grid[r][c] : -1; };
    auto take = [&](int n, int r, int c) {
        while (int(grid.size()) <= r)
            grid.emplace_back(cols, -1);
        grid[r][c] = n;
    };
    for (int n = 0; n < tiles.size(); ++n) {
        Tile &t = tiles[n];
        bool placed = false;
        for (int r = 0; !placed; ++r) {
            for (int c = 0; c + t.colSpan <= cols && !placed; ++c) {
                bool free = true;
                for (int y = r; y < r + t.rowSpan && free; ++y)
                    for (int x = c; x < c + t.colSpan && free; ++x)
                        free = at(y, x) < 0;
                if (!free)
                    continue;
                t.row = r;
                t.col = c;
                for (int y = r; y < r + t.rowSpan; ++y)
                    for (int x = c; x < c + t.colSpan; ++x)
                        take(n, y, x);
                placed = true;
            }
        }
    }

    // Then no holes: a tile beside or above a gap grows into it (right, down,
    // left, up) when the gap runs its whole edge. Until nothing grows.
    const int rows = int(grid.size());
    auto empty = [&](int r0, int r1, int c0, int c1) {
        for (int y = r0; y < r1; ++y)
            for (int x = c0; x < c1; ++x)
                if (grid[y][x] >= 0)
                    return false;
        return true;
    };
    auto fill = [&](int n) {
        const Tile &t = tiles[n];
        for (int y = t.row; y < t.row + t.rowSpan; ++y)
            for (int x = t.col; x < t.col + t.colSpan; ++x)
                grid[y][x] = n;
    };
    for (bool grew = true; grew;) {
        grew = false;
        for (int r = 0; r < rows; ++r) {
            for (int c = 0; c < cols; ++c) {
                if (grid[r][c] >= 0)
                    continue;
                if (const int n = c > 0 ? grid[r][c - 1] : -1; n >= 0) {
                    Tile &t = tiles[n];
                    if (t.col + t.colSpan == c && empty(t.row, t.row + t.rowSpan, c, c + 1)) {
                        ++t.colSpan;
                        fill(n);
                        grew = true;
                        continue;
                    }
                }
                if (const int n = r > 0 ? grid[r - 1][c] : -1; n >= 0) {
                    Tile &t = tiles[n];
                    if (t.row + t.rowSpan == r && empty(r, r + 1, t.col, t.col + t.colSpan)) {
                        ++t.rowSpan;
                        fill(n);
                        grew = true;
                        continue;
                    }
                }
                if (const int n = c + 1 < cols ? grid[r][c + 1] : -1; n >= 0) {
                    Tile &t = tiles[n];
                    if (t.col == c + 1 && empty(t.row, t.row + t.rowSpan, c, c + 1)) {
                        --t.col;
                        ++t.colSpan;
                        fill(n);
                        grew = true;
                        continue;
                    }
                }
                if (const int n = r + 1 < rows ? grid[r + 1][c] : -1; n >= 0) {
                    Tile &t = tiles[n];
                    if (t.row == r + 1 && empty(r, r + 1, t.col, t.col + t.colSpan)) {
                        --t.row;
                        ++t.rowSpan;
                        fill(n);
                        grew = true;
                    }
                }
            }
        }
    }

    std::stable_sort(tiles.begin(), tiles.end(), [](const Tile &a, const Tile &b) {
        return a.row != b.row ? a.row < b.row : a.col < b.col;
    });
    QVariantList out;
    for (const Tile &t : std::as_const(tiles)) {
        QVariantMap e = t.entry;
        e.insert("row", t.row);
        e.insert("col", t.col);
        e.insert("rowSpan", t.rowSpan);
        e.insert("colSpan", t.colSpan);
        out << e;
    }
    return out;
}
