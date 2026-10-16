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
#include <QRandomGenerator>
#include <QTimeZone>
#include <QSet>
#include <cmath>
#include <algorithm>
#include <memory>

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
    // so live and demo data take the same path through rebuild().
    m_rawQuotes.clear();
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
        auto load = [this, onError, generation, sync](const QString &table, const QUrlQuery &q, Apply apply) {
            ++sync->pending;
            m_client->select(table, q, [this, table, apply, onError, generation, sync](const QJsonDocument &doc, const QString &error) {
                if (generation != m_generation)
                    return;
                if (!error.isEmpty()) {
                    sync->failed = true;
                    onError(table, error);
                } else {
                    setOnline(true);
                    apply(doc);
                }
                if (--sync->pending > 0)
                    return;
                if (sync->failed) {
                    retrySoon();
                } else {
                    stopRetrying();
                    m_lastSync = now();
                }
                rebuild();
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
        m_client->select("memories", QUrlQuery("select=text,pinned,updated_at&agent_id=is.null&order=pinned.desc,updated_at.desc&limit=100"),
                         [this, generation](const QJsonDocument &doc, const QString &error) {
                             if (generation != m_generation)
                                 return;
                             if (!error.isEmpty()) {
                                 qInfo() << "memories not available:" << error;
                                 return;
                             }
                             m_rawMemories = toList(doc);
                             rebuild();
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
        m_client->rpc("list_calendar_sources", QJsonObject(), [this, generation](const QJsonDocument &doc, const QString &error) {
            if (generation != m_generation)
                return;
            if (!error.isEmpty()) {
                qInfo() << "calendar subscriptions not available:" << error;
                return;
            }
            m_rawCalendarSources = toList(doc);
            rebuild();
        });
        // Todos and reminders (newer too): same, optional. The open ones; a
        // reminder whose time passed before yesterday is over.
        QUrlQuery todos;
        todos.addQueryItem("select", "id,agent_id,kind,title,notes,due_at,all_day,done_at,created_at");
        todos.addQueryItem("done_at", "is.null");
        todos.addQueryItem("or", "(kind.eq.todo,due_at.gte." + QDateTime(m_today.addDays(-1), QTime(0, 0)).toUTC().toString(Qt::ISODate) + ")");
        todos.addQueryItem("order", "due_at.nullslast,created_at");
        todos.addQueryItem("limit", "200");
        m_client->select("todos", todos, [this, generation](const QJsonDocument &doc, const QString &error) {
            if (generation != m_generation)
                return;
            if (!error.isEmpty()) {
                qInfo() << "todos not available:" << error;
                return;
            }
            m_rawTodos = toList(doc);
            rebuild();
        });
        load("briefs", QUrlQuery("select=*&order=published_at.desc&limit=100"),
             [this](const QJsonDocument &d) { m_rawBriefs = toList(d); });
        load("symbols", QUrlQuery("select=*&hidden=eq.false&order=sort_order,symbol"),
             [this](const QJsonDocument &d) { m_rawSymbols = toList(d); });
        load("quotes", QUrlQuery("select=id,agent_id,symbol,name,price,change,change_pct,currency,note,as_of&order=as_of.desc,id.desc&limit=2000"),
             [this](const QJsonDocument &d) { m_rawQuotes = toList(d); });
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
    m_rawSymbols.clear();
    m_rawReports.clear();
    m_rawProjects.clear();
    m_rawMetrics.clear();
    m_rawMetricSettings.clear();
    m_rawDashboards.clear();
    m_rawEvents.clear();
    m_rawTodos.clear();
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

QString FeedStore::timeLabel(const QDateTime &when) const
{
    return QLocale().toString(when.time(), QStringLiteral("h:mm ap"));
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
        m_briefs << b;
    }
    std::stable_sort(m_briefs.begin(), m_briefs.end(), [](const QVariant &a, const QVariant &b) {
        return a.toMap().value("publishedMs").toLongLong() > b.toMap().value("publishedMs").toLongLong();
    });
    m_latestBrief = m_briefs.isEmpty() ? QVariantMap() : m_briefs.first().toMap();

    // Quotes: the rows of each symbol, newest first as loaded (demo rows come
    // oldest first, so they are sorted here too).
    QHash<QString, QVariantList> rowsBySymbol;
    for (const QVariant &v : std::as_const(m_rawQuotes))
        rowsBySymbol[v.toMap().value("symbol").toString()] << v;
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
        m_quotes << q;
    }

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
    emit dataChanged();
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
            if (!q.value("note").toString().isEmpty())
                part += QStringLiteral(": ") + q.value("note").toString().simplified();
            parts << part;
        }
        lines << tr("Markets: %1.").arg(parts.join(QStringLiteral("; ")));
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
    auto agentName = [&](const QString &id) { return agentById.value(id).value("name").toString(); };
    auto agentColor = [&](const QString &id) {
        const QString c = agentById.value(id).value("color").toString();
        return c.isEmpty() ? QStringLiteral("#5B7CF5") : c;
    };
    auto add = [this](QVariantMap item, const QDateTime &start, const QDateTime &end) {
        item.insert("startMs", start.toMSecsSinceEpoch());
        item.insert("endMs", (end.isValid() ? end : start).toMSecsSinceEpoch());
        // "3:30" over "pm": the clock face splits them, 12-hour like the rest of the display.
        const QStringList parts = QLocale().toString(start.time(), QStringLiteral("h:mm ap")).split(QLatin1Char(' '));
        const bool allDay = item.value("allDay").toBool();
        item.insert("timeLabel", allDay ? tr("All day") : parts.value(0));
        item.insert("ampm", allDay ? QString() : parts.value(1));
        m_timeline << item;
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

    // Today's events (all-day ones first in the day).
    for (const QVariant &v : std::as_const(m_events)) {
        const QVariantMap e = v.toMap();
        if (e.value("day").toString() != m_today.toString(Qt::ISODate))
            continue;
        const QDateTime start = QDateTime::fromMSecsSinceEpoch(e.value("startMs").toLongLong());
        const QDateTime end = QDateTime::fromMSecsSinceEpoch(e.value("endMs").toLongLong());
        const QString place = e.value("location").toString();
        add(QVariantMap{{"kind", "event"}, {"id", e.value("id")}, {"label", e.value("calendar")}, {"title", e.value("title")},
                        {"detail", e.value("all_day").toBool() ? e.value("calendar").toString()
                                                              : e.value("timeLabel").toString() + (place.isEmpty() ? QString() : QStringLiteral(" · ") + place)},
                        {"color", e.value("color")}, {"allDay", e.value("all_day")}, {"target", 6}},
            start, end);
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

    std::stable_sort(m_timeline.begin(), m_timeline.end(), [](const QVariant &a, const QVariant &b) {
        const QVariantMap ma = a.toMap(), mb = b.toMap();
        if (ma.value("allDay").toBool() != mb.value("allDay").toBool())
            return ma.value("allDay").toBool();
        return ma.value("startMs").toLongLong() < mb.value("startMs").toLongLong();
    });
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
                      [this](const QJsonDocument &doc, const QString &error) {
                          if (!error.isEmpty()) {
                              qWarning() << "saving display settings failed:" << error;
                              return;
                          }
                          // What the server now has, so the next sync doesn't re-apply it.
                          m_deviceSettings = doc.object().toVariantMap();
                      });
    });
}
