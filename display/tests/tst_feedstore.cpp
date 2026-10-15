#include <QtTest>

#include <QJsonArray>
#include <QNetworkProxy>
#include <QSettings>

#include "FakeServer.h"
#include "backend/SupabaseClient.h"
#include "models/FeedStore.h"

// The feed store in live mode against a stand-in for Supabase (auth,
// PostgREST, the pair-device function), and its demo mode.
class TestFeedStore : public QObject
{
    Q_OBJECT

    FakeServer m_server;

    using Request = FakeServer::Request;
    using Reply = FakeServer::Reply;
    static Reply json(const QByteArray &body, int status = 200, int delayMs = 0) { return FakeServer::json(body, status, delayMs); }
    static Reply json(const QJsonDocument &doc) { return FakeServer::json(doc); }

    struct Rig
    {
        SupabaseClient client;
        FeedStore store;
        Rig(const QUrl &url, bool demo = false) : client(url, QStringLiteral("anon-key")), store(&client, demo) {}
    };
    std::unique_ptr<Rig> rig;

    // A fresh live store with a session, synced once.
    void startLive(int syncMs = 60 * 1000)
    {
        QSettings().clear();
        QSettings().setValue("device/id", "dev-1");
        rig = std::make_unique<Rig>(m_server.baseUrl());
        rig->client.setRefreshToken("refresh-1");
        rig->store.setSyncIntervalMs(syncMs);
        rig->store.start();
        QTRY_VERIFY_WITH_TIMEOUT(rig->store.online(), 5000);
    }

    static QByteArray rows(const QJsonArray &a) { return QJsonDocument(a).toJson(QJsonDocument::Compact); }
    static QString iso(const QDateTime &dt) { return dt.toUTC().toString(Qt::ISODateWithMs); }

    void serveFeeds()
    {
        const QDateTime now = QDateTime::currentDateTime();
        m_server.route("/auth/v1/token", [](const Request &) {
            return json(R"({"access_token":"access-1","refresh_token":"refresh-2"})");
        });
        m_server.route("/rest/v1/platform_settings", [](const Request &) {
            return json(R"([{"display_name":"Hill Valley","timezone":"America/Chicago"}])");
        });
        // (Built as objects: moc can't read a "#" inside a raw string.)
        m_server.route("/rest/v1/agents", [](const Request &) {
            return json(rows({
                QJsonObject{{"id", "a1"}, {"name", "Grok"}, {"slug", "grok"}, {"kind", "grok"}, {"color", "#7A64E8"},
                            {"last_seen_at", QJsonValue::Null}, {"revoked_at", QJsonValue::Null}},
                QJsonObject{{"id", "a2"}, {"name", "Market desk"}, {"slug", "market-desk"}, {"kind", "stocks"}, {"color", "#3DB37A"},
                            {"last_seen_at", QJsonValue::Null}, {"revoked_at", QJsonValue::Null}},
            }));
        });
        m_server.route("/rest/v1/briefs", [now](const Request &) {
            return json(rows({
                QJsonObject{{"id", "b-old"}, {"agent_id", "a1"}, {"title", "Older"}, {"body", "x"}, {"kind", "daily"},
                            {"published_at", iso(now.addSecs(-7200))}, {"expires_at", QJsonValue::Null}},
                QJsonObject{{"id", "b-new"}, {"agent_id", "a1"}, {"title", "Newest"}, {"body", "First paragraph.\n\nSecond."}, {"kind", "hourly"},
                            {"published_at", iso(now.addSecs(-600))}, {"expires_at", QJsonValue::Null}},
                QJsonObject{{"id", "b-gone"}, {"agent_id", "a2"}, {"title", "Expired alert"}, {"body", "x"}, {"kind", "alert"},
                            {"published_at", iso(now.addSecs(-300))}, {"expires_at", iso(now.addSecs(-60))}},
            }));
        });
        m_server.route("/rest/v1/symbols", [](const Request &) {
            return json(R"([{"symbol":"SPY","name":"S&P 500 ETF","sort_order":0,"hidden":false},{"symbol":"AAPL","name":"Apple","sort_order":1,"hidden":false},{"symbol":"GONE","name":"No rows","sort_order":2,"hidden":false}])");
        });
        m_server.route("/rest/v1/quotes", [now](const Request &) {
            return json(rows({
                QJsonObject{{"id", 3}, {"agent_id", "a2"}, {"symbol", "AAPL"}, {"name", "Apple"}, {"price", 247.9}, {"change", 2.78},
                            {"change_pct", 1.13}, {"currency", "USD"}, {"note", "Services beat"}, {"as_of", iso(now)}},
                QJsonObject{{"id", 2}, {"agent_id", "a2"}, {"symbol", "AAPL"}, {"name", "Apple"}, {"price", 245.12}, {"change", 1.42},
                            {"change_pct", 0.58}, {"currency", "USD"}, {"note", QJsonValue::Null}, {"as_of", iso(now.addDays(-1))}},
                QJsonObject{{"id", 1}, {"agent_id", "a2"}, {"symbol", "SPY"}, {"name", QJsonValue::Null}, {"price", 668.42}, {"change", QJsonValue::Null},
                            {"change_pct", QJsonValue::Null}, {"currency", "USD"}, {"note", QJsonValue::Null}, {"as_of", iso(now)}},
                QJsonObject{{"id", 0}, {"agent_id", "a2"}, {"symbol", "SPY"}, {"name", QJsonValue::Null}, {"price", 660.0}, {"change", QJsonValue::Null},
                            {"change_pct", QJsonValue::Null}, {"currency", "USD"}, {"note", QJsonValue::Null}, {"as_of", iso(now.addDays(-1))}},
                QJsonObject{{"id", 9}, {"agent_id", "a2"}, {"symbol", "HIDDEN"}, {"price", 1}, {"currency", "USD"}, {"as_of", iso(now)}},
            }));
        });
        m_server.route("/rest/v1/projects", [now](const Request &) {
            return json(rows({
                QJsonObject{{"id", "p1"}, {"agent_id", "a1"}, {"key", "mcfly"}, {"name", "McFly"}, {"kind", "code"}, {"status", "active"},
                            {"progress", 62}, {"summary", "The display."}, {"next_step", "Ship it"}, {"link", "https://x/1"}, {"color", QJsonValue::Null},
                            {"sort_order", 1}, {"updated_at", iso(now)},
                            {"project_updates", QJsonArray{
                                 QJsonObject{{"id", 1}, {"kind", "ci"}, {"text", "CI green"}, {"url", QJsonValue::Null}, {"happened_at", iso(now.addSecs(-600))}},
                                 QJsonObject{{"id", 2}, {"kind", "pr"}, {"text", "PR opened"}, {"url", "https://x/pr"}, {"happened_at", iso(now.addSecs(-7200))}}}}},
                QJsonObject{{"id", "p2"}, {"agent_id", "a1"}, {"key", "onyx"}, {"name", "Onyx"}, {"kind", "code"}, {"status", "blocked"},
                            {"progress", QJsonValue::Null}, {"summary", ""}, {"next_step", QJsonValue::Null}, {"link", QJsonValue::Null}, {"color", "#123456"},
                            {"sort_order", 0}, {"updated_at", iso(now.addDays(-1))}, {"project_updates", QJsonArray()}},
            }));
        });
        m_server.route("/rest/v1/metric_settings", [](const Request &) {
            return json(R"([{"key":"sales.today","label":"Sales today","group_name":"Store","sort_order":0,"hidden":false},{"key":"api.p95","label":null,"group_name":"Ops","sort_order":1,"hidden":false},{"key":"gone","label":"Gone","group_name":null,"sort_order":2,"hidden":false}])");
        });
        m_server.route("/rest/v1/metrics", [now](const Request &) {
            return json(rows({
                QJsonObject{{"id", 3}, {"agent_id", "a2"}, {"key", "sales.today"}, {"label", "Sales today"}, {"value", 4280}, {"unit", "USD"},
                            {"delta", QJsonValue::Null}, {"delta_pct", 12.5}, {"note", QJsonValue::Null}, {"as_of", iso(now)}},
                QJsonObject{{"id", 2}, {"agent_id", "a2"}, {"key", "sales.today"}, {"label", "Sales today"}, {"value", 3800}, {"unit", "USD"},
                            {"delta", QJsonValue::Null}, {"delta_pct", QJsonValue::Null}, {"note", QJsonValue::Null}, {"as_of", iso(now.addDays(-1))}},
                QJsonObject{{"id", 1}, {"agent_id", "a2"}, {"key", "api.p95"}, {"label", "API p95"}, {"value", 212}, {"unit", "ms"},
                            {"delta", QJsonValue::Null}, {"delta_pct", QJsonValue::Null}, {"note", "After the cache change."}, {"as_of", iso(now)}},
                QJsonObject{{"id", 0}, {"agent_id", "a2"}, {"key", "api.p95"}, {"label", "API p95"}, {"value", 230}, {"unit", "ms"},
                            {"delta", QJsonValue::Null}, {"delta_pct", QJsonValue::Null}, {"note", QJsonValue::Null}, {"as_of", iso(now.addDays(-1))}},
            }));
        });
        m_server.route("/rest/v1/dashboards", [now](const Request &) {
            return json(rows({
                QJsonObject{{"id", "d1"}, {"agent_id", "a2"}, {"key", "ops"}, {"title", "Ops"}, {"subtitle", QJsonValue::Null}, {"sort_order", 0}, {"hidden", false},
                            {"updated_at", iso(now)},
                            {"widgets", QJsonArray{
                                 QJsonObject{{"type", "metric"}, {"label", "Requests"}, {"value", 1240000}, {"delta_pct", 4.2}},
                                 QJsonObject{{"type", "status"}, {"label", "API"}, {"state", "warn"}, {"detail", "slow"}},
                                 QJsonObject{{"type", "progress"}, {"label", "Storage"}, {"value", 68}, {"max", 100}, {"unit", "%"}},
                                 QJsonObject{{"type", "chart"}, {"label", "Reqs"}, {"points", QJsonArray{1, 2, 3}}, {"unit", "k"}},
                                 QJsonObject{{"type", "list"}, {"title", "On call"}, {"items", QJsonArray{"Ricky"}}},
                                 QJsonObject{{"type", "text"}, {"title", "Note"}, {"body", "Hi"}}}}},
            }));
        });
        m_server.route("/rest/v1/events", [now](const Request &) {
            const QDateTime later = now.addSecs(3600), earlier = now.addSecs(-7200);
            return json(rows({
                QJsonObject{{"id", "e1"}, {"agent_id", "a1"}, {"calendar", "Work"}, {"external_id", "x1"}, {"title", "Standup"}, {"description", QJsonValue::Null},
                            {"location", "Zoom"}, {"starts_at", iso(later)}, {"ends_at", iso(later.addSecs(900))}, {"all_day", false}, {"color", "#5B7CF5"}, {"url", QJsonValue::Null}},
                QJsonObject{{"id", "e2"}, {"agent_id", "a1"}, {"calendar", "Home"}, {"external_id", "x2"}, {"title", "Earlier"}, {"description", QJsonValue::Null},
                            {"location", QJsonValue::Null}, {"starts_at", iso(earlier)}, {"ends_at", iso(earlier.addSecs(600))}, {"all_day", false}, {"color", QJsonValue::Null}, {"url", QJsonValue::Null}},
                QJsonObject{{"id", "e3"}, {"agent_id", "a1"}, {"calendar", "Home"}, {"external_id", "x3"}, {"title", "Trip"}, {"description", QJsonValue::Null},
                            {"location", QJsonValue::Null}, {"starts_at", iso(QDateTime(QDate::currentDate().addDays(2), QTime(0, 0)))},
                            {"ends_at", iso(QDateTime(QDate::currentDate().addDays(2), QTime(23, 59, 59)))}, {"all_day", true}, {"color", "#F6B94A"}, {"url", QJsonValue::Null}},
            }));
        });
        m_server.route("/rest/v1/news_reports", [now](const Request &) {
            return json(rows({
                QJsonObject{{"id", "r2"}, {"agent_id", "a1"}, {"slug", "2026-10-14"}, {"report_date", QDate::currentDate().toString(Qt::ISODate)},
                            {"display_date", "Oct 14, 2026"}, {"hero_item", "two"}, {"published_at", iso(now)},
                            {"news_items", QJsonArray{
                                 QJsonObject{{"id", "i1"}, {"report_id", "r2"}, {"section_key", "s"}, {"section_name", "Social"}, {"section_order", 0},
                                             {"item_key", "one"}, {"position", 0}, {"headline", "One"}, {"takeaway", "t1"},
                                             {"url", "https://x.com/1"}, {"image_url", QJsonValue::Null}, {"source_domain", "x.com"}},
                                 QJsonObject{{"id", "i2"}, {"report_id", "r2"}, {"section_key", "i"}, {"section_name", "AI Tech"}, {"section_order", 1},
                                             {"item_key", "two"}, {"position", 0}, {"headline", "Two"}, {"takeaway", "t2"},
                                             {"url", "https://blog.google/x"}, {"image_url", "https://img/2.jpg"}, {"source_domain", "blog.google"}},
                                 QJsonObject{{"id", "i3"}, {"report_id", "r2"}, {"section_key", "i"}, {"section_name", "AI Tech"}, {"section_order", 1},
                                             {"item_key", "three"}, {"position", 1}, {"headline", "Three"}, {"takeaway", ""},
                                             {"url", "https://a.b/3"}, {"image_url", QJsonValue::Null}, {"source_domain", "a.b"}}}}},
                QJsonObject{{"id", "r1"}, {"agent_id", "a1"}, {"slug", "2026-10-13"}, {"report_date", QDate::currentDate().addDays(-1).toString(Qt::ISODate)},
                            {"display_date", "Oct 13, 2026"}, {"hero_item", QJsonValue::Null}, {"published_at", iso(now.addDays(-1))},
                            {"news_items", QJsonArray{
                                 QJsonObject{{"id", "i0"}, {"report_id", "r1"}, {"section_key", "a"}, {"section_name", "Ads"}, {"section_order", 0},
                                             {"item_key", "old"}, {"position", 0}, {"headline", "Yesterday's"}, {"takeaway", ""},
                                             {"url", "https://a.b/0"}, {"image_url", QJsonValue::Null}, {"source_domain", "a.b"}}}}},
            }));
        });
    }

private slots:
    void initTestCase()
    {
        QCoreApplication::setOrganizationName("McFly-tests");
        QCoreApplication::setApplicationName("tst_feedstore");
        QNetworkProxy::setApplicationProxy(QNetworkProxy::NoProxy);
        QVERIFY(m_server.listen());
    }
    void init()
    {
        m_server.reset();
        serveFeeds();
    }
    void cleanup() { rig.reset(); }
    void cleanupTestCase() { QSettings().clear(); }

    void syncsEveryFeedAndShapesIt()
    {
        startLive();
        QTRY_COMPARE(rig->store.displayName(), QStringLiteral("Hill Valley"));
        QCOMPARE(rig->store.mode(), QStringLiteral("live"));

        // The session was refreshed with the stored token and kept.
        QCOMPARE(m_server.requests("POST", "/auth/v1/token").size(), 1);
        QCOMPARE(QSettings().value("device/refreshToken").toString(), QStringLiteral("refresh-2"));
        // Every request carried the new access token.
        for (const Request &r : m_server.requests("GET", "/rest/v1/"))
            QCOMPARE(r.auth, QByteArray("Bearer access-1"));
        // The device checked in.
        QTRY_COMPARE(m_server.requests("PATCH", "/rest/v1/devices?id=eq.dev-1").size(), 1);

        // Briefs: newest first, expired ones left out, decorated.
        QTRY_COMPARE(rig->store.briefs().size(), 2);
        const QVariantMap newest = rig->store.briefs().first().toMap();
        QCOMPARE(newest.value("title").toString(), QStringLiteral("Newest"));
        QCOMPARE(newest.value("agentName").toString(), QStringLiteral("Grok"));
        QCOMPARE(newest.value("agentColor").toString(), QStringLiteral("#7A64E8"));
        QCOMPARE(newest.value("kindLabel").toString(), QStringLiteral("Hourly"));
        QCOMPARE(newest.value("summary").toString(), QStringLiteral("First paragraph."));
        QCOMPARE(newest.value("dayLabel").toString(), QStringLiteral("Today"));
        QCOMPARE(rig->store.latestBrief().value("id").toString(), QStringLiteral("b-new"));

        // Quotes: in symbol order, hidden and missing symbols left out.
        QCOMPARE(rig->store.quotes().size(), 2);
        const QVariantMap spy = rig->store.quotes().at(0).toMap();
        const QVariantMap aapl = rig->store.quotes().at(1).toMap();
        QCOMPARE(spy.value("symbol").toString(), QStringLiteral("SPY"));
        QCOMPARE(spy.value("name").toString(), QStringLiteral("S&P 500 ETF")); // from symbols
        QCOMPARE(spy.value("priceLabel").toString(), QStringLiteral("$668.42"));
        // No change in the row: taken from the previous point.
        QVERIFY(qAbs(spy.value("change").toDouble() - 8.42) < 0.001);
        QVERIFY(spy.value("up").toBool());
        QCOMPARE(spy.value("history").toList().size(), 2);
        QCOMPARE(spy.value("history").toList().first().toDouble(), 660.0); // oldest first
        QCOMPARE(aapl.value("note").toString(), QStringLiteral("Services beat"));
        QCOMPARE(aapl.value("pctLabel").toString(), QStringLiteral("+1.13%"));
        QCOMPARE(aapl.value("changeLabel").toString(), QStringLiteral("+2.78"));
        QCOMPARE(aapl.value("agentName").toString(), QStringLiteral("Market desk"));
        QCOMPARE(rig->store.quote("AAPL").value("priceLabel").toString(), QStringLiteral("$247.90"));
        QVERIFY(rig->store.quote("NOPE").isEmpty());

        // News: the newest report, its sections in order, the hero.
        QCOMPARE(rig->store.newsReports().size(), 2);
        QCOMPARE(rig->store.newsReports().first().toMap().value("slug").toString(), QStringLiteral("2026-10-14"));
        const QVariantMap news = rig->store.news();
        QCOMPARE(news.value("slug").toString(), QStringLiteral("2026-10-14"));
        QCOMPARE(news.value("displayDate").toString(), QStringLiteral("Oct 14, 2026"));
        QVERIFY(news.value("isToday").toBool());
        const QVariantList sections = news.value("sections").toList();
        QCOMPARE(sections.size(), 2);
        QCOMPARE(sections.at(0).toMap().value("name").toString(), QStringLiteral("Social"));
        QCOMPARE(sections.at(0).toMap().value("color").toString(), QStringLiteral("#F07F5A"));
        QCOMPARE(sections.at(1).toMap().value("items").toList().size(), 2);
        QCOMPARE(news.value("hero").toMap().value("headline").toString(), QStringLiteral("Two"));
        QCOMPARE(rig->store.stories().size(), 3);
        const QVariantMap two = rig->store.stories().at(1).toMap();
        QVERIFY(two.value("isHero").toBool());
        QCOMPARE(two.value("imageUrl").toString(), QStringLiteral("https://img/2.jpg"));
        QCOMPARE(two.value("sectionColor").toString(), QStringLiteral("#5B7CF5"));
        QCOMPARE(two.value("sourceDomain").toString(), QStringLiteral("blog.google"));

        // The snapshot for the assistant mentions all three feeds.
        const QString snapshot = rig->store.snapshotText();
        QVERIFY2(snapshot.contains("Newest") && snapshot.contains("AAPL $247.90 (+1.13%)") && snapshot.contains("AI Tech: Two"), qPrintable(snapshot));
    }

    void shapesTheProductivityFeeds()
    {
        startLive();
        QTRY_COMPARE(rig->store.projects().size(), 2);
        // Blocked first.
        const QVariantMap onyx = rig->store.projects().at(0).toMap();
        QCOMPARE(onyx.value("name").toString(), QStringLiteral("Onyx"));
        QCOMPARE(onyx.value("statusLabel").toString(), QStringLiteral("Blocked"));
        QCOMPARE(onyx.value("color").toString(), QStringLiteral("#123456"));
        QVERIFY(!onyx.value("hasProgress").toBool());
        const QVariantMap mcfly = rig->store.projects().at(1).toMap();
        QCOMPARE(mcfly.value("color").toString(), QStringLiteral("#7A64E8")); // the agent's
        QCOMPARE(mcfly.value("updates").toList().size(), 2);
        QCOMPARE(mcfly.value("lastUpdate").toMap().value("text").toString(), QStringLiteral("CI green"));
        QCOMPARE(mcfly.value("updates").toList().at(1).toMap().value("icon").toString(), QStringLiteral("link"));
        QCOMPARE(rig->store.project("p2").value("key").toString(), QStringLiteral("onyx"));

        // Metrics: in order, grouped, with history; a setting without rows is left out.
        QCOMPARE(rig->store.metrics().size(), 2);
        const QVariantMap sales = rig->store.metrics().at(0).toMap();
        QCOMPARE(sales.value("valueLabel").toString(), QStringLiteral("$4,280"));
        QCOMPARE(sales.value("deltaLabel").toString(), QStringLiteral("+12.5%"));
        QVERIFY(sales.value("up").toBool());
        QCOMPARE(sales.value("history").toList().size(), 2);
        const QVariantMap p95 = rig->store.metrics().at(1).toMap();
        QCOMPARE(p95.value("label").toString(), QStringLiteral("API p95")); // from the row, the setting has none
        QCOMPARE(p95.value("valueLabel").toString(), QStringLiteral("212 ms"));
        QCOMPARE(p95.value("deltaLabel").toString(), QStringLiteral("−18")); // from the previous point
        QVERIFY(!p95.value("up").toBool());
        QCOMPARE(rig->store.metricGroups().size(), 2);
        QCOMPARE(rig->store.metricGroups().at(1).toMap().value("name").toString(), QStringLiteral("Ops"));

        // Dashboards: widgets get their labels.
        QCOMPARE(rig->store.dashboards().size(), 1);
        const QVariantList widgets = rig->store.dashboards().first().toMap().value("widgets").toList();
        QCOMPARE(widgets.size(), 6);
        QCOMPARE(widgets.at(0).toMap().value("valueLabel").toString(), QStringLiteral("1.2M"));
        QCOMPARE(widgets.at(0).toMap().value("deltaLabel").toString(), QStringLiteral("+4.2%"));
        QCOMPARE(widgets.at(1).toMap().value("stateLabel").toString(), QStringLiteral("Warning"));
        QCOMPARE(widgets.at(2).toMap().value("fraction").toDouble(), 0.68);
        QCOMPARE(widgets.at(2).toMap().value("valueLabel").toString(), QStringLiteral("68%"));
        QCOMPARE(widgets.at(3).toMap().value("valueLabel").toString(), QStringLiteral("3 k"));
        QVERIFY(widgets.at(3).toMap().value("wide").toBool());
        QVERIFY(!widgets.at(0).toMap().value("wide").toBool());

        // Events: by start; the earlier one is past, the later one is next; the trip is on a later day.
        QCOMPARE(rig->store.events().size(), 3);
        QVERIFY(rig->store.events().at(0).toMap().value("past").toBool());
        QCOMPARE(rig->store.upcoming().size(), 2);
        QCOMPARE(rig->store.upcoming().at(0).toMap().value("title").toString(), QStringLiteral("Standup"));
        QCOMPARE(rig->store.upcoming().at(0).toMap().value("dayLabel").toString(), QStringLiteral("Today"));
        QCOMPARE(rig->store.upcoming().at(1).toMap().value("startLabel").toString(), QStringLiteral("All day"));
        QVERIFY(rig->store.eventDays().size() >= 2);
        QCOMPARE(rig->store.eventDays().first().toMap().value("day").toString(), QDate::currentDate().toString(Qt::ISODate));
        // The agent's color where the event has none.
        QCOMPARE(rig->store.events().at(0).toMap().value("color").toString(), QStringLiteral("#7A64E8"));
        QCOMPARE(rig->store.assistantProvider(), QStringLiteral("claude"));
        const QString snapshot = rig->store.snapshotText();
        QVERIFY2(snapshot.contains("Onyx (blocked)") && snapshot.contains("Sales today $4,280") && snapshot.contains("Standup"), qPrintable(snapshot));
    }

    void todayTimeline()
    {
        startLive();
        QTRY_VERIFY(!rig->store.timeline().isEmpty());
        const QVariantList timeline = rig->store.timeline();
        const QString today = QDate::currentDate().toString(Qt::ISODate);
        qint64 last = 0;
        bool sawNews = false, sawStandup = false, sawTrip = false;
        for (const QVariant &v : timeline) {
            const QVariantMap item = v.toMap();
            // Only today's things, each pointing at its screen, in time order.
            QCOMPARE(QDateTime::fromMSecsSinceEpoch(item.value("startMs").toLongLong()).date().toString(Qt::ISODate), today);
            QVERIFY(item.value("endMs").toLongLong() >= item.value("startMs").toLongLong());
            QVERIFY(!item.value("timeLabel").toString().isEmpty());
            if (!item.value("allDay").toBool()) {
                QVERIFY(item.value("startMs").toLongLong() >= last);
                last = item.value("startMs").toLongLong();
            }
            const QString kind = item.value("kind").toString();
            if (kind == QLatin1String("news")) {
                sawNews = true;
                QCOMPARE(item.value("title").toString(), QStringLiteral("Two")); // the hero
                QCOMPARE(item.value("target").toInt(), 3);
                QVERIFY(item.value("detail").toString().contains(QStringLiteral("One")));
            }
            if (kind == QLatin1String("event") && item.value("title").toString() == QLatin1String("Standup")) {
                sawStandup = true;
                QCOMPARE(item.value("target").toInt(), 6);
                QVERIFY(item.value("detail").toString().contains(QStringLiteral("Zoom")));
            }
            if (item.value("title").toString() == QLatin1String("Trip"))
                sawTrip = true;
        }
        QVERIFY(sawNews);
        QVERIFY(sawStandup || QTime::currentTime() > QTime(22, 59)); // an hour on can be tomorrow
        QVERIFY(!sawTrip); // two days out

        // Picking yesterday's report on News leaves today's on Home.
        rig->store.showReport(QStringLiteral("r1"));
        QCOMPARE(rig->store.news().value("id").toString(), QStringLiteral("r1"));
        int newsRows = 0;
        for (const QVariant &v : rig->store.timeline())
            if (v.toMap().value("kind").toString() == QLatin1String("news")) {
                ++newsRows;
                QCOMPARE(v.toMap().value("id").toString(), QStringLiteral("r2"));
            }
        QCOMPARE(newsRows, 1);
    }

    void newsSources()
    {
        startLive();
        QTRY_COMPARE(rig->store.newsReports().size(), 2);
        QCOMPARE(rig->store.newsSources().size(), 1);
        rig->store.showSource("a1");
        QCOMPARE(rig->store.newsReports().size(), 2);
        rig->store.showSource("nobody"); // no such source: everything shows
        QCOMPARE(rig->store.newsSource(), QString());
        QCOMPARE(rig->store.newsReports().size(), 2);
    }

    void anotherDaysReport()
    {
        startLive();
        QTRY_COMPARE(rig->store.newsReports().size(), 2);
        rig->store.showReport("r1");
        QCOMPARE(rig->store.news().value("slug").toString(), QStringLiteral("2026-10-13"));
        QVERIFY(!rig->store.news().value("isToday").toBool());
        QCOMPARE(rig->store.stories().size(), 1);
        // The hero falls back to the first story.
        QCOMPARE(rig->store.news().value("hero").toMap().value("headline").toString(), QStringLiteral("Yesterday's"));
        rig->store.showReport("");
        QCOMPARE(rig->store.news().value("slug").toString(), QStringLiteral("2026-10-14"));
    }

    void aFailedTableRetriesSoon()
    {
        m_server.route("/rest/v1/briefs", [](const Request &) { return json("{\"message\":\"boom\"}", 500); });
        startLive();
        // Online (other tables answered), with the error kept.
        QVERIFY(rig->store.online() || !rig->store.lastError().isEmpty());
        QTRY_COMPARE_WITH_TIMEOUT(m_server.requests("GET", "/rest/v1/briefs").size(), 2, 4000); // the retry, 2 s in
        QTRY_COMPARE_WITH_TIMEOUT(m_server.requests("GET", "/rest/v1/briefs").size(), 3, 6000); // then 4 s
        // Quotes still came through.
        QCOMPARE(rig->store.quotes().size(), 2);
    }

    void syncsAgainOnTheInterval()
    {
        startLive(500);
        QTRY_COMPARE_WITH_TIMEOUT(m_server.requests("GET", "/rest/v1/briefs").size(), 3, 3000);
        // One check-in only: devices.last_seen_at every few minutes, not every sync.
        QCOMPARE(m_server.requests("PATCH", "/rest/v1/devices?id=eq.dev-1").size(), 1);
    }

    void aRejectedTokenGoesBackToSetup()
    {
        m_server.route("/auth/v1/token", [](const Request &) { return json("{\"error\":\"invalid_grant\"}", 400); });
        m_server.route("/functions/v1/pair-device", [](const Request &r) {
            if (r.body.value("action").toString() == "start")
                return json(R"({"code":"123456","expiresAt":"2030-01-01T00:00:00Z"})");
            return json(R"({"status":"pending"})");
        });
        QSettings().clear();
        rig = std::make_unique<Rig>(m_server.baseUrl());
        rig->client.setRefreshToken("dead");
        rig->store.start();
        QTRY_COMPARE(rig->store.mode(), QStringLiteral("pairing"));
        QTRY_COMPARE(rig->store.pairingCode(), QStringLiteral("123456"));
        QVERIFY(!QSettings().contains("device/refreshToken"));
    }

    void pairsAndThenSyncs()
    {
        int polls = 0;
        m_server.route("/functions/v1/pair-device", [&polls](const Request &r) {
            const QString action = r.body.value("action").toString();
            if (action == "start") {
                // The display sends a hash, never the secret.
                if (r.body.value("secretHash").toString().size() != 64)
                    return json("{\"error\":\"bad hash\"}", 400);
                return json(R"({"code":"654321","expiresAt":"2030-01-01T00:00:00Z"})");
            }
            if (++polls < 2)
                return json(R"({"status":"pending"})");
            return json(R"({"status":"paired","deviceId":"dev-9","session":{"accessToken":"access-9","refreshToken":"refresh-9","expiresAt":1}})");
        });
        QSettings().clear();
        rig = std::make_unique<Rig>(m_server.baseUrl());
        rig->store.start();
        QTRY_COMPARE(rig->store.mode(), QStringLiteral("pairing"));
        QTRY_COMPARE(rig->store.pairingCode(), QStringLiteral("654321"));
        QSignalSpy notified(&rig->store, &FeedStore::notify);
        QTRY_COMPARE_WITH_TIMEOUT(rig->store.mode(), QStringLiteral("live"), 10000);
        QCOMPARE(QSettings().value("device/id").toString(), QStringLiteral("dev-9"));
        QCOMPARE(QSettings().value("device/refreshToken").toString(), QStringLiteral("refresh-9"));
        QCOMPARE(rig->store.pairingCode(), QString());
        QTRY_VERIFY(rig->store.online());
        QTRY_COMPARE(rig->store.quotes().size(), 2);
        QCOMPARE(notified.count(), 1);
        // Synced as the new device.
        QCOMPARE(m_server.requests("GET", "/rest/v1/quotes").first().auth, QByteArray("Bearer access-9"));
        // No token refresh was needed: the pairing minted the session.
        QCOMPARE(m_server.requests("POST", "/auth/v1/token").size(), 0);

        // Re-pair: forgets everything and shows a new code.
        rig->store.unpair();
        QCOMPARE(rig->store.mode(), QStringLiteral("pairing"));
        QCOMPARE(rig->store.quotes().size(), 0);
        QVERIFY(!QSettings().contains("device/id"));
        QTRY_COMPARE(rig->store.pairingCode(), QStringLiteral("654321"));
    }

    void demoModeHasEveryFeed()
    {
        QSettings().clear();
        rig = std::make_unique<Rig>(QUrl(), true);
        rig->store.start();
        QCOMPARE(rig->store.mode(), QStringLiteral("demo"));
        QCOMPARE(rig->store.displayName(), QStringLiteral("McFly"));
        QVERIFY(rig->store.briefs().size() >= 3);
        QCOMPARE(rig->store.latestBrief().value("dayLabel").toString(), QStringLiteral("Today"));
        QVERIFY(rig->store.quotes().size() >= 4);
        const QVariantMap first = rig->store.quotes().first().toMap();
        QCOMPARE(first.value("symbol").toString(), QStringLiteral("SPY"));
        QVERIFY(first.value("history").toList().size() >= 10);
        QCOMPARE(rig->store.news().value("sections").toList().size(), 3);
        QCOMPARE(rig->store.news().value("hero").toMap().value("item_key").toString(), QStringLiteral("gemini"));
        QVERIFY(rig->store.stories().size() == 6);
        QVERIFY(rig->store.projects().size() >= 4);
        QCOMPARE(rig->store.projects().first().toMap().value("status").toString(), QStringLiteral("blocked"));
        QVERIFY(rig->store.metrics().size() >= 5);
        QVERIFY(rig->store.metricGroups().size() >= 2);
        QVERIFY(rig->store.dashboards().size() >= 2);
        QVERIFY(rig->store.events().size() >= 7);
        QVERIFY(rig->store.eventDays().size() >= 4);
        QVERIFY(rig->store.newsSources().size() >= 1);
        QCOMPARE(rig->store.lastSyncLabel(), QStringLiteral("Sample data"));
        QVERIFY(m_server.requests().isEmpty());
    }

    void demoRollsOverAtMidnight()
    {
        QSettings().clear();
        rig = std::make_unique<Rig>(QUrl(), true);
        QDateTime fake(QDate(2026, 10, 14), QTime(23, 59, 59, 600));
        rig->store.setClock([&fake]() { return fake; });
        rig->store.start();
        QCOMPARE(rig->store.today(), QStringLiteral("2026-10-14"));
        QSignalSpy newDay(&rig->store, &FeedStore::todayChanged);
        fake = QDateTime(QDate(2026, 10, 15), QTime(0, 0, 0, 200));
        QTRY_COMPARE_WITH_TIMEOUT(newDay.count(), 1, 3000);
        QCOMPARE(rig->store.today(), QStringLiteral("2026-10-15"));
    }
};

QTEST_GUILESS_MAIN(TestFeedStore)
#include "tst_feedstore.moc"
