#pragma once

#include <QDate>
#include <QDateTime>
#include <QElapsedTimer>
#include <QHash>
#include <QObject>
#include <QSet>
#include <QSettings>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>
#include <functional>

class SupabaseClient;

// Single source of feed data for the QML UI: what the agents pushed.
//
// Modes:
//   demo    - no backend configured (or --demo): sample data
//   pairing - backend configured but this display has no session yet
//   live    - signed in as the device user; data synced from Supabase
//
// Rows keep their database shape (snake_case) and are decorated with a few
// display-ready fields (labels, colors, sparkline points) in rebuild().
//
// `today` is the one local date the whole UI treats as today. It moves on at
// local midnight (and when the clock jumps).
class FeedStore : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString mode READ mode NOTIFY modeChanged)
    Q_PROPERTY(bool online READ online NOTIFY statusChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY statusChanged)
    Q_PROPERTY(QString pairingCode READ pairingCode NOTIFY pairingChanged)
    Q_PROPERTY(QString today READ today NOTIFY todayChanged)       // local date, yyyy-MM-dd
    Q_PROPERTY(QString displayName READ displayName NOTIFY dataChanged)
    Q_PROPERTY(QString lastSyncLabel READ lastSyncLabel NOTIFY statusChanged)

    Q_PROPERTY(QVariantList agents READ agents NOTIFY dataChanged)
    // Shared notes McFly keeps about the user (memory), pinned first:
    // { text, pinned, updatedLabel }. Read-only here; edited on the web.
    Q_PROPERTY(QVariantList memories READ memories NOTIFY dataChanged)
    // Calendar subscriptions and their health: { name, color, enabled,
    // syncedLabel, error, eventCount }. Managed on the web.
    Q_PROPERTY(QVariantList calendarSources READ calendarSources NOTIFY dataChanged)
    // Briefs carry `paragraphs` and `bullets` (the body's "- " points), and
    // `blocks`, the two in the body's order for a reader:
    // [{ kind: "paragraph", text } | { kind: "points", items }]. Quotes
    // and metrics carry their range over the history (low, high, lowLabel,
    // highLabel, rangePos 0..1), `fresh` (pushed in the last 15 min) and
    // changedMs / changedUp (when this display saw the value move; 0 until it
    // does). Quotes add `heat` (−1..1, ±3% at the ends), `swingPct` and
    // `bigMove`; metrics add goodDirection, trend, good, anomaly and
    // usualLabel. Board widgets carry `known`: QML skips a type it can't draw.
    Q_PROPERTY(QVariantList briefs READ briefs NOTIFY dataChanged)     // newest first
    Q_PROPERTY(QVariantMap latestBrief READ latestBrief NOTIFY dataChanged)
    Q_PROPERTY(QVariantList quotes READ quotes NOTIFY dataChanged)     // in display order, hidden ones left out
    // The holdings among the shown quotes, summed: { held, count, valueLabel,
    // dayChangeLabel, dayPctLabel, dayUp, totalChangeLabel, totalPctLabel, totalUp }.
    Q_PROPERTY(QVariantMap portfolio READ portfolio NOTIFY dataChanged)
    Q_PROPERTY(QVariantMap news READ news NOTIFY dataChanged)          // the report on show (the newest, or the one picked)
    Q_PROPERTY(QVariantList newsReports READ newsReports NOTIFY dataChanged) // every report, newest first
    Q_PROPERTY(QVariantList stories READ stories NOTIFY dataChanged)   // the shown report's items, flat, in order
    Q_PROPERTY(QVariantList newsSources READ newsSources NOTIFY dataChanged) // agents with a report, newest first
    Q_PROPERTY(QString newsSource READ newsSource NOTIFY dataChanged)  // the agent id filtering the reports, or ""
    Q_PROPERTY(QVariantList projects READ projects NOTIFY dataChanged) // blocked first, done last
    // The projects in a group per status, in the order the list shows them
    // (groupProjects()).
    Q_PROPERTY(QVariantList projectGroups READ projectGroups NOTIFY dataChanged)
    Q_PROPERTY(QVariantList metrics READ metrics NOTIFY dataChanged)   // visible metrics in display order, each with history
    Q_PROPERTY(QVariantList metricGroups READ metricGroups NOTIFY dataChanged) // [{ name, metrics: [...] }]
    Q_PROPERTY(QVariantList dashboards READ dashboards NOTIFY dataChanged) // visible, in order, widgets decorated
    Q_PROPERTY(QVariantList events READ events NOTIFY dataChanged)     // from yesterday on, by start
    Q_PROPERTY(QVariantList eventDays READ eventDays NOTIFY dataChanged) // [{ day, dayLabel, events: [...] }] from today
    Q_PROPERTY(QVariantList upcoming READ upcoming NOTIFY dataChanged) // the next few events from now
    // Today in time order: the Pulse report, briefs, project updates and events,
    // each { kind, startMs, endMs, timeLabel, title, detail, color, target, ... }.
    // Past, now and next are left to QML, which has a ticking clock.
    Q_PROPERTY(QVariantList timeline READ timeline NOTIFY dataChanged)
    // Tomorrow's events, shaped like timeline rows: the preview Home shows
    // under today's last row.
    Q_PROPERTY(QVariantList tomorrow READ tomorrow NOTIFY dataChanged)
    // Tomorrow's weekday ("Friday"), for that preview's heading.
    Q_PROPERTY(QString tomorrowLabel READ tomorrowLabel NOTIFY todayChanged)
    Q_PROPERTY(QString assistantProvider READ assistantProvider NOTIFY dataChanged) // platform_settings: claude | grok
    // What stands out right now, at most five, ranked the way the console's
    // lib/insights.ts ranks them (a board's status going down slots in second):
    // { id, kind, icon, title, detail, color, tone, screen, segment, itemId,
    // question, ... }. Time-relative ("starts in 12 min"), so it is checked
    // again each minute, apart from dataChanged.
    Q_PROPERTY(QVariantList highlights READ highlights NOTIFY highlightsChanged)
    // How the quotes moved today: { up, down, flat, total, label }.
    Q_PROPERTY(QVariantMap marketBreadth READ marketBreadth NOTIFY dataChanged)
    // Where now sits on a 24-hour dial: degrees clockwise from midnight at the
    // top (noon at the bottom), like the timeline's startAngle. Each minute.
    Q_PROPERTY(double nowAngle READ nowAngle NOTIFY nowAngleChanged)

public:
    FeedStore(SupabaseClient *client, bool forceDemo, QObject *parent = nullptr);

    void start();

    QString mode() const { return m_mode; }
    bool online() const { return m_online; }
    QString lastError() const { return m_lastError; }
    QString pairingCode() const { return m_pairingCode; }
    QString today() const { return m_today.toString(Qt::ISODate); }
    QDate todayDate() const { return m_today; }
    QString displayName() const { return m_displayName; }
    QString lastSyncLabel() const;

    QVariantList agents() const { return m_agents; }
    QVariantList memories() const { return m_memories; }
    QVariantList calendarSources() const { return m_calendarSources; }
    // Sends a patch of this display's settings to the server
    // (device_update_settings). Live mode only.
    void pushDeviceSettings(const QVariantMap &patch);
    QVariantList briefs() const { return m_briefs; }
    QVariantMap latestBrief() const { return m_latestBrief; }
    QVariantList quotes() const { return m_quotes; }
    QVariantMap portfolio() const { return m_portfolio; }
    QVariantMap news() const { return m_news; }
    QVariantList newsReports() const { return m_newsReports; }
    QVariantList stories() const { return m_stories; }
    QVariantList newsSources() const { return m_newsSources; }
    QString newsSource() const { return m_newsSourceId; }
    QVariantList projects() const { return m_projects; }
    QVariantList projectGroups() const { return m_projectGroups; }
    QVariantList metrics() const { return m_metrics; }
    QVariantList metricGroups() const { return m_metricGroups; }
    QVariantList dashboards() const { return m_dashboards; }
    QVariantList events() const { return m_events; }
    QVariantList eventDays() const { return m_eventDays; }
    QVariantList upcoming() const { return m_upcoming; }
    QString assistantProvider() const { return m_assistantProvider; }
    QVariantList timeline() const { return m_timeline; }
    QVariantList tomorrow() const { return m_tomorrow; }
    QString tomorrowLabel() const;
    QVariantList highlights() const { return m_highlights; }
    QVariantMap marketBreadth() const { return m_marketBreadth; }
    double nowAngle() const;
    // The store's clock (local time): the wall clock, or the tests' stand-in.
    // The assistant's suggestions use it too, so both agree on "now".
    QDateTime now() const { return m_clock ? m_clock() : QDateTime::currentDateTime(); }

    // A board (an index into `dashboards`) laid out as a bento for a grid of
    // `columns`: [{ index, indexes, col, row, colSpan, rowSpan, kind }], in
    // reading order, with no holes. The first metric is a 2×2 hero from four
    // columns up; two or more status widgets in a row become one full-width
    // "health" strip ({ kind: "health", indexes, state, stateColor, summary,
    // perRow }), one row tall for each row of `perRow` statuses it wraps to
    // (at most one a column, three on two columns, rows evened out);
    // a chart is 4×2 on six columns and full width on four or fewer; lists and
    // notes are 2×1; the rest 1×1. Unknown widget types get no cell. It reads
    // `dashboards`, so a binding should too to follow a sync.
    Q_INVOKABLE QVariantList boardLayout(int board, int columns) const;

    // Syncs now (live), or asks for a pairing code again now if the last try
    // failed (e.g. Wi-Fi was just joined). Also re-checks the date.
    Q_INVOKABLE void refresh();
    // The network is back: sync now if offline, instead of at the next retry.
    void networkUp();
    // Shows another day's report (an id from newsReports); "" goes back to the newest.
    Q_INVOKABLE void showReport(const QString &reportId);
    // Shows only one source's reports (an agent id from newsSources); "" shows every source.
    Q_INVOKABLE void showSource(const QString &agentId);
    // A project by id, decorated like the `projects` rows, or an empty map.
    Q_INVOKABLE QVariantMap project(const QString &id) const;
    // Forgets this display's session and shows a new pairing code (Settings → Re-pair).
    Q_INVOKABLE void unpair();
    // The quote for a symbol, decorated like the `quotes` rows, or an empty map.
    Q_INVOKABLE QVariantMap quote(const QString &symbol) const;

    // A short, spoken-style summary of what's on the display, for the
    // assistant's prompt and the demo answers.
    Q_INVOKABLE QString snapshotText(int maxChars = 6000) const;

    // A project's stages as the console draws them (stageTrack() in
    // admin/lib/feed-layout.ts): { steps: [{ name, state, word }], current,
    // index, headline, position }. Stages before the one it is in are done,
    // that one takes the project's status (blocked or paused, else current),
    // the rest are next; a done project has been through them all. `index`
    // is -1 before the first stage and the count once done. Empty for a
    // project without stages.
    static QVariantMap stageTrack(const QStringList &stages, const QString &stage, const QString &status);
    // How long a project has been in its stage: "under an hour", "5 hr",
    // "3 days", "2 wk", "4 mo"; empty when `since` isn't a time.
    static QString timeInStage(const QDateTime &since, const QDateTime &now);
    // Decorated projects (in `projects` order) as the Projects list groups
    // them, as the console's List view does: Blocked, Active, Paused, Up next
    // (planned), Done, every group present: { status, label, color, count,
    // offset (its first project's place in the whole list), projects }. A
    // status the display doesn't know joins Active.
    static QVariantList groupProjects(const QVariantList &projects);

    // Tests: a stand-in for the wall clock (local time). Call before start().
    void setClock(std::function<QDateTime()> now) { m_clock = std::move(now); }
    // Tests: how often live mode syncs.
    void setSyncIntervalMs(int ms);

signals:
    // This display's settings as the server has them (devices.settings),
    // after each sync that read them; empty when the server has none yet.
    void deviceSettingsReceived(const QVariantMap &settings);
    void modeChanged();
    void statusChanged();
    void pairingChanged();
    void todayChanged();
    void dataChanged();
    void highlightsChanged();
    // Once a minute, on the minute (and nothing else changes with it).
    void nowAngleChanged();
    void notify(const QString &message);
    // A reminder's time has come, once per reminder while this display runs
    // (or within a few minutes of it, at start): { id, title, notes, timeLabel }.
    void reminderDue(const QVariantMap &reminder);

private:
    void setMode(const QString &mode);
    void setOnline(bool online, const QString &error = {});
    void loadDemo();
    void loadLive();
    void withSession(std::function<void()> fn);
    void retrySoon();
    void stopRetrying();
    void checkIn();
    void startPairing();
    void pollPairing();
    void rebuild();
    QVariantList publishedState() const;
    void rebuildProductivity(const QHash<QString, QVariantMap> &agentById);
    void rebuildTimeline(const QHash<QString, QVariantMap> &agentById);
    void armReminders();
    void fireReminders();
    void rebuildHighlights();
    void onMinute();
    // Stamps a quote or metric row with when its value last changed, as this
    // display saw it (0 until it does): { changedMs, changedUp }.
    void markChange(QVariantMap &row, const QString &key, double value);
    bool updateToday();
    bool rollDay();
    QString dayLabel(const QDate &day) const;
    // A day on the calendar's agenda: its name and month/day, "Saturday 10/17".
    QString dayHeading(const QDate &day) const;
    QString timeLabel(const QDateTime &when) const;

    SupabaseClient *m_client;
    QSettings m_settings;
    bool m_forceDemo;
    QString m_mode = QStringLiteral("demo");
    bool m_online = false;
    QString m_lastError;

    QTimer m_syncTimer;
    QTimer m_retryTimer; // a failed sync, tried again before the next one
    int m_retryMs = 0;   // its last delay; 0 after a clean sync
    QTimer m_pairTimer;
    QTimer m_pairRetryTimer;
    QString m_pairingCode;
    QString m_pairingSecret;
    // Bumped for each new code and once paired; answers to older pairing
    // requests (a slow poll, a retry that crossed one) are ignored.
    int m_pairAttempt = 0;
    // Bumped when the device's session is dropped (re-pair, lost session) so
    // answers to requests made before are ignored.
    int m_generation = 0;
    // When this display last set devices.last_seen_at (monotonic; invalid until it has).
    QElapsedTimer m_lastCheckIn;
    QDateTime m_lastSync;

    std::function<QDateTime()> m_clock; // tests only; empty means the real clock
    QDate m_today;
    QTimer m_dayTimer; // fires just after local midnight
    QTimer m_minuteTimer; // fires just after each minute: nowAngle, highlights
    QTimer m_reminderTimer;     // fires at the next reminder's time
    QSet<QString> m_reminded;   // reminders already announced, by id

    // Raw rows as loaded (demo JSON or Supabase).
    QString m_displayName = QStringLiteral("McFly");
    QVariantList m_rawAgents, m_rawBriefs, m_rawQuotes, m_rawSymbols, m_rawReports;
    QVariantList m_rawQuoteData; // quotes_latest: symbol, agent_id, as_of, data
    QVariantList m_rawMemories, m_memories;
    QVariantList m_published; // what the last dataChanged announced (publishedState)
    QVariantList m_rawCalendarSources, m_calendarSources;
    QVariantMap m_deviceSettings;
    bool m_deviceSettingsSeen = false;
    QVariantList m_rawProjects, m_rawMetrics, m_rawMetricSettings, m_rawDashboards, m_rawEvents;
    QVariantList m_rawTodos; // open todos and reminders (todos)
    QString m_shownReportId; // "" = the newest
    QString m_newsSourceId;  // "" = every source
    QString m_assistantProvider = QStringLiteral("claude");

    // Decorated rows for QML.
    QVariantList m_agents, m_briefs, m_quotes, m_newsReports, m_stories, m_newsSources;
    QVariantList m_projects, m_projectGroups, m_metrics, m_metricGroups, m_dashboards, m_events, m_eventDays, m_upcoming;
    QVariantList m_timeline, m_tomorrow;
    QVariantMap m_latestBrief, m_news, m_portfolio;
    QVariantList m_highlights;
    QVariantMap m_marketBreadth;
    // Ranked once per rebuild, for the highlights: the metrics far off their
    // usual and the big movers, strongest first.
    QVariantList m_anomalies, m_movers;

    // The last value seen per quote ("q:SYM") and metric ("m:key"), across
    // rebuilds: QML animates a change from changedMs without needing its
    // delegate to survive the rebuild.
    struct Seen
    {
        double value = 0;
        qint64 changedMs = 0;
        bool up = true;
    };
    QHash<QString, Seen> m_seen;
};
