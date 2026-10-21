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
    // The first sync's settings have arrived (or were there before the spy): watch from here.
    void settleFirstSync(QSignalSpy &received)
    {
        QTRY_VERIFY(!m_server.requests("GET", "/rest/v1/devices").isEmpty());
        QTRY_COMPARE(m_server.pending(), 0);
        QTest::qWait(200);
        received.clear();
    }
    static QString iso(const QDateTime &dt) { return dt.toUTC().toString(Qt::ISODateWithMs); }
    // "Today" moves at midnight, and the fixtures sit an hour ahead or minutes
    // back from now, so near it they can land on another day.
    static bool nearMidnight()
    {
        const QTime t = QTime::currentTime();
        return t >= QTime(23, 0) || t < QTime(0, 30);
    }

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
        // Added after "/rest/v1/quotes", so it is matched first.
        m_server.route("/rest/v1/quotes_latest", [](const Request &) { return json("[]"); });
        m_server.route("/rest/v1/projects", [now](const Request &) {
            return json(rows({
                QJsonObject{{"id", "p1"}, {"agent_id", "a1"}, {"key", "mcfly"}, {"name", "McFly"}, {"kind", "code"}, {"status", "active"},
                            {"progress", 62}, {"summary", "The display."}, {"next_step", "Ship it"}, {"link", "https://x/1"}, {"color", QJsonValue::Null},
                            {"sort_order", 1}, {"updated_at", iso(now)},
                            // Postgres writes microseconds.
                            {"stages", QJsonArray{"Plan", "Build", "Review", "Ship"}}, {"stage", "Build"},
                            {"stage_since", now.addDays(-3).addSecs(-60).toUTC().toString(QStringLiteral("yyyy-MM-dd'T'HH:mm:ss.zzz")) + QStringLiteral("456+00:00")},
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
        if (!nearMidnight())
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

    // What a market agent adds to a quote (data.position, signals, stats),
    // labelled; a holding left out of the agent's newest push is gone.
    void shapesHoldingsAndSignals()
    {
        const QDateTime now = QDateTime::currentDateTime();
        m_server.route("/rest/v1/symbols", [](const Request &) {
            return json(R"([{"symbol":"AAA","sort_order":0,"hidden":false},{"symbol":"BBB","sort_order":1,"hidden":false},{"symbol":"OLD","sort_order":2,"hidden":false}])");
        });
        m_server.route("/rest/v1/quotes", [now](const Request &) {
            return json(rows({
                QJsonObject{{"id", 1}, {"agent_id", "a2"}, {"symbol", "AAA"}, {"price", 50}, {"change", 1}, {"change_pct", 2.04}, {"currency", "USD"}, {"as_of", iso(now)}},
                QJsonObject{{"id", 2}, {"agent_id", "a2"}, {"symbol", "BBB"}, {"price", 100}, {"change", -2}, {"change_pct", -1.96}, {"currency", "USD"}, {"as_of", iso(now)}},
                QJsonObject{{"id", 3}, {"agent_id", "a2"}, {"symbol", "OLD"}, {"price", 9}, {"change", 0}, {"change_pct", 0}, {"currency", "USD"}, {"as_of", iso(now.addDays(-1))}},
            }));
        });
        m_server.route("/rest/v1/quotes_latest", [now](const Request &) {
            const QJsonObject aaa{
                {"position", QJsonObject{{"shares", 4}, {"avg_cost", 40}}},
                {"signals", QJsonArray{QJsonObject{{"text", "RSI 71, near the overbought line"}, {"tone", "up"}}, "Earnings in 3 days",
                                       QJsonObject{{"text", "  "}, {"tone", "down"}}}},
                {"stats", QJsonObject{{"open", 49}, {"high", 51}, {"low", 48.5}, {"prev_close", 49}, {"volume", 52300000}, {"avg_volume", 41000000},
                                      {"market_cap", 3.7e12}, {"pe", 37.24}, {"low_52w", 30}, {"high_52w", 60}, {"earnings", "Oct 30, after close"}}}};
            const QJsonObject bbb{{"position", QJsonObject{{"shares", "1.5"}, {"value", "150"}, {"day_change", -3}}}};
            return json(rows({
                QJsonObject{{"symbol", "AAA"}, {"agent_id", "a2"}, {"as_of", iso(now)}, {"data", aaa}},
                QJsonObject{{"symbol", "BBB"}, {"agent_id", "a2"}, {"as_of", iso(now)}, {"data", bbb}},
                QJsonObject{{"symbol", "OLD"}, {"agent_id", "a2"}, {"as_of", iso(now.addDays(-1))},
                            {"data", QJsonObject{{"position", QJsonObject{{"shares", 9}}}, {"signals", QJsonArray{"Stale"}}}}},
            }));
        });
        startLive();
        QTRY_COMPARE(rig->store.quotes().size(), 3);

        const QVariantMap aaa = rig->store.quote("AAA");
        QVERIFY(aaa.value("held").toBool());
        const QVariantMap a = aaa.value("position").toMap();
        QCOMPARE(a.value("sharesLabel").toString(), QStringLiteral("4 shares"));
        QCOMPARE(a.value("valueLabel").toString(), QStringLiteral("$200.00"));        // 4 x $50
        QCOMPARE(a.value("avgCostLabel").toString(), QStringLiteral("avg $40.00"));
        QCOMPARE(a.value("dayChangeLabel").toString(), QStringLiteral("+$4.00"));      // 4 x $1
        QCOMPARE(a.value("totalChangeLabel").toString(), QStringLiteral("+$40.00"));   // $200 - 4 x $40
        QCOMPARE(a.value("totalPctLabel").toString(), QStringLiteral("+25.0%"));
        QCOMPARE(a.value("weightLabel").toString(), QStringLiteral("57% of holdings"));
        const QVariantList signalList = aaa.value("signals").toList();
        QCOMPARE(signalList.size(), 2); // the blank one is dropped
        QCOMPARE(signalList.at(0).toMap().value("tone").toString(), QStringLiteral("up"));
        QCOMPARE(signalList.at(1).toMap().value("text").toString(), QStringLiteral("Earnings in 3 days"));
        QCOMPARE(signalList.at(1).toMap().value("tone").toString(), QStringLiteral("watch"));
        QCOMPARE(aaa.value("signalTone").toString(), QStringLiteral("up"));
        QStringList stats;
        for (const QVariant &v : aaa.value("stats").toList())
            stats << v.toMap().value("label").toString() + QLatin1Char('=') + v.toMap().value("value").toString();
        QCOMPARE(stats, QStringList({"Open=$49.00", "Prev close=$49.00", "Volume=52.3M · 1.3× avg", "Market cap=$3.7T", "P/E=37.2",
                                     "Earnings=Oct 30, after close"}));
        // The ranges, with where $50 sits in each.
        const QVariantList ranges = aaa.value("ranges").toList();
        QCOMPARE(ranges.size(), 2);
        QCOMPARE(ranges.at(0).toMap().value("label").toString(), QStringLiteral("Today"));
        QCOMPARE(ranges.at(0).toMap().value("lowLabel").toString(), QStringLiteral("$48.50"));
        QVERIFY(qAbs(ranges.at(0).toMap().value("pos").toDouble() - 0.6) < 1e-9);   // (50 - 48.5) / (51 - 48.5)
        QCOMPARE(ranges.at(1).toMap().value("highLabel").toString(), QStringLiteral("$60.00"));
        QVERIFY(qAbs(ranges.at(1).toMap().value("pos").toDouble() - 2.0 / 3) < 1e-9); // (50 - 30) / (60 - 30)

        // Numbers sent as strings; the value given rather than worked out.
        const QVariantMap b = rig->store.quote("BBB").value("position").toMap();
        QCOMPARE(b.value("sharesLabel").toString(), QStringLiteral("1.5 shares"));
        QCOMPARE(b.value("valueLabel").toString(), QStringLiteral("$150.00"));
        QCOMPARE(b.value("dayChangeLabel").toString(), QStringLiteral("−$3.00"));
        QVERIFY(!b.value("dayUp").toBool());
        QVERIFY(!b.contains("totalChangeLabel")); // no cost given

        // OLD wasn't in the newest push: its price stays, its holding goes.
        const QVariantMap old = rig->store.quote("OLD");
        QCOMPARE(old.value("priceLabel").toString(), QStringLiteral("$9.00"));
        QVERIFY(!old.value("held").toBool());
        QVERIFY(old.value("signals").toList().isEmpty());

        // The total: $350, +$1 on the $349 it opened at, +$40 on the $160 the gain is known for.
        const QVariantMap p = rig->store.portfolio();
        QVERIFY(p.value("held").toBool());
        QCOMPARE(p.value("count").toInt(), 2);
        QCOMPARE(p.value("valueLabel").toString(), QStringLiteral("$350.00"));
        QCOMPARE(p.value("dayChangeLabel").toString(), QStringLiteral("+$1.00"));
        QCOMPARE(p.value("dayPctLabel").toString(), QStringLiteral("+0.29%"));
        QCOMPARE(p.value("totalChangeLabel").toString(), QStringLiteral("+$40.00"));
        QCOMPARE(p.value("totalPctLabel").toString(), QStringLiteral("+25.0%"));

        // The assistant hears about the holdings too.
        const QString snapshot = rig->store.snapshotText();
        QVERIFY2(snapshot.contains("held: 4 shares, $200.00") && snapshot.contains("RSI 71") && snapshot.contains("worth $350.00"), qPrintable(snapshot));
    }

    // Today's bars laid out on the whole session: x from the open to the
    // close, y over the day's range and the previous close.
    void intradayLaysTheDayOnTheSession()
    {
        const QDateTime now = QDateTime::currentDateTime();
        const qint64 open = 1'800'000'000, close = open + 390 * 60;
        m_server.route("/rest/v1/symbols", [](const Request &) {
            return json(R"([{"symbol":"AAA","sort_order":0,"hidden":false},{"symbol":"BBB","sort_order":1,"hidden":false}])");
        });
        m_server.route("/rest/v1/quotes", [now](const Request &) {
            return json(rows({
                QJsonObject{{"id", 1}, {"agent_id", "a2"}, {"symbol", "AAA"}, {"price", 104}, {"change", 4}, {"currency", "USD"}, {"as_of", iso(now)}},
                QJsonObject{{"id", 2}, {"agent_id", "a2"}, {"symbol", "BBB"}, {"price", 9}, {"change", 0}, {"currency", "USD"}, {"as_of", iso(now)}},
                QJsonObject{{"id", 0}, {"agent_id", "a2"}, {"symbol", "BBB"}, {"price", 8}, {"change", 0}, {"currency", "USD"}, {"as_of", iso(now.addDays(-1))}},
            }));
        });
        m_server.route("/rest/v1/quotes_latest", [now, open, close](const Request &) {
            const QJsonObject day{{"interval", "10minute"}, {"open", double(open)}, {"close", double(close)},
                                  {"points", QJsonArray{QJsonArray{double(open), 102}, QJsonArray{double(open + 195 * 60), 108},
                                                        QJsonArray{double(open + 390 * 60 + 60), 1}}}}; // past the close: out
            return json(rows({
                QJsonObject{{"symbol", "AAA"}, {"agent_id", "a2"}, {"as_of", iso(now)}, {"data", QJsonObject{{"intraday", day}}}},
                QJsonObject{{"symbol", "BBB"}, {"agent_id", "a2"}, {"as_of", iso(now)},
                            {"data", QJsonObject{{"intraday", QJsonObject{{"open", double(open)}, {"close", double(close)},
                                                                         {"points", QJsonArray{QJsonArray{double(open), 9}}}}}}}},
            }));
        });
        startLive();
        QTRY_COMPARE(rig->store.quotes().size(), 2);

        const QVariantMap aaa = rig->store.quote("AAA");
        const QVariantMap day = aaa.value("intraday").toMap();
        const QVariantList points = day.value("points").toList();
        QCOMPARE(points.size(), 2);
        // The range is 100 (the previous close, 104 − 4) to 108.
        QCOMPARE(points.at(0).toMap().value("x").toDouble(), 0.0);
        QCOMPARE(points.at(0).toMap().value("y").toDouble(), 0.25);
        QCOMPARE(points.at(1).toMap().value("x").toDouble(), 0.5); // midway through the session
        QCOMPARE(points.at(1).toMap().value("y").toDouble(), 1.0);
        QCOMPARE(day.value("baseY").toDouble(), 0.0);
        QVERIFY(day.value("up").toBool());
        QCOMPARE(day.value("lowLabel").toString(), QStringLiteral("$102.00"));
        QCOMPARE(day.value("highLabel").toString(), QStringLiteral("$108.00"));
        QVERIFY(!day.value("openLabel").toString().isEmpty());
        // A tile draws today's prices.
        QCOMPARE(aaa.value("tilePoints").toList(), QVariantList({102.0, 108.0}));

        // One bar is no chart; the tile keeps the push history.
        const QVariantMap bbb = rig->store.quote("BBB");
        QVERIFY(bbb.value("intraday").toMap().isEmpty());
        QCOMPARE(bbb.value("tilePoints").toList(), QVariantList({8.0, 9.0}));
    }

    // One push is the rows written together (created_at), whatever as_of
    // each quote carries: a close three hours old keeps its holding; a
    // symbol only in an earlier push loses it.
    void aHoldingCountsWhileInTheNewestPush()
    {
        const QDateTime now = QDateTime::currentDateTime();
        const QString pushed = iso(now), earlier = iso(now.addSecs(-900));
        m_server.route("/rest/v1/symbols", [](const Request &) {
            return json(R"([{"symbol":"BTC-USD","sort_order":0,"hidden":false},{"symbol":"AAA","sort_order":1,"hidden":false},{"symbol":"OLD","sort_order":2,"hidden":false}])");
        });
        m_server.route("/rest/v1/quotes", [now](const Request &) {
            return json(rows({
                QJsonObject{{"id", 3}, {"agent_id", "a2"}, {"symbol", "BTC-USD"}, {"price", 100}, {"change", 1}, {"currency", "USD"}, {"as_of", iso(now)}},
                QJsonObject{{"id", 2}, {"agent_id", "a2"}, {"symbol", "AAA"}, {"price", 50}, {"change", 1}, {"currency", "USD"}, {"as_of", iso(now.addSecs(-3 * 3600))}},
                QJsonObject{{"id", 1}, {"agent_id", "a2"}, {"symbol", "OLD"}, {"price", 9}, {"change", 0}, {"currency", "USD"}, {"as_of", iso(now.addSecs(-3 * 3600))}},
            }));
        });
        m_server.route("/rest/v1/quotes_latest", [now, pushed, earlier](const Request &) {
            const QJsonObject held{{"position", QJsonObject{{"shares", 2}}}};
            return json(rows({
                QJsonObject{{"symbol", "BTC-USD"}, {"agent_id", "a2"}, {"as_of", iso(now)}, {"created_at", pushed}, {"data", held}},
                QJsonObject{{"symbol", "AAA"}, {"agent_id", "a2"}, {"as_of", iso(now.addSecs(-3 * 3600))}, {"created_at", pushed}, {"data", held}},
                QJsonObject{{"symbol", "OLD"}, {"agent_id", "a2"}, {"as_of", iso(now.addSecs(-3 * 3600))}, {"created_at", earlier}, {"data", held}},
            }));
        });
        startLive();
        QTRY_COMPARE(rig->store.quotes().size(), 3);
        QVERIFY(rig->store.quote("BTC-USD").value("held").toBool());
        QVERIFY(rig->store.quote("AAA").value("held").toBool());
        QVERIFY(!rig->store.quote("OLD").value("held").toBool());
        QCOMPARE(rig->store.portfolio().value("count").toInt(), 2);
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
        // Stages, shaped as the console's stageTrack(); a row from before
        // stages (Onyx here sends none) has no track.
        QVERIFY(mcfly.value("hasStages").toBool());
        const QVariantMap track = mcfly.value("track").toMap();
        QCOMPARE(track.value("headline").toString(), QStringLiteral("Build"));
        QCOMPARE(track.value("position").toString(), QStringLiteral("2 of 4"));
        QCOMPARE(track.value("index").toInt(), 1);
        QCOMPARE(track.value("steps").toList().size(), 4);
        QCOMPARE(track.value("steps").toList().at(0).toMap().value("state").toString(), QStringLiteral("done"));
        QCOMPARE(track.value("steps").toList().at(1).toMap().value("word").toString(), QStringLiteral("Now"));
        QCOMPARE(mcfly.value("stageFor").toString(), QStringLiteral("3 days"));
        QVERIFY(!onyx.value("hasStages").toBool());
        QVERIFY(onyx.value("track").toMap().isEmpty());
        QVERIFY(onyx.value("stageFor").toString().isEmpty());
        // Grouped for the list: every status, in order, each with its projects.
        const QVariantList groups = rig->store.projectGroups();
        QCOMPARE(groups.size(), 5);
        QStringList labels, counts;
        for (const QVariant &g : groups) {
            labels << g.toMap().value("label").toString();
            counts << QString::number(g.toMap().value("count").toInt());
        }
        QCOMPARE(labels.join(QLatin1Char(',')), QStringLiteral("Blocked,Active,Paused,Up next,Done"));
        QCOMPARE(counts.join(QLatin1Char(',')), QStringLiteral("1,1,0,0,0"));
        QCOMPARE(groups.at(1).toMap().value("offset").toInt(), 1);
        QCOMPARE(groups.at(1).toMap().value("projects").toList().at(0).toMap().value("name").toString(), QStringLiteral("McFly"));

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
        if (!nearMidnight()) {
            QCOMPARE(rig->store.upcoming().at(0).toMap().value("dayLabel").toString(), QStringLiteral("Today"));
            QCOMPARE(rig->store.upcoming().at(0).toMap().value("dayHeading").toString(),
                     QStringLiteral("Today ") + QDate::currentDate().toString(QStringLiteral("MM/dd")));
        }
        QCOMPARE(rig->store.upcoming().at(1).toMap().value("startLabel").toString(), QStringLiteral("All day"));
        // The agenda heads a later day with its name and month/day: "Saturday 10/17".
        {
            const QVariantMap trip = rig->store.events().last().toMap();
            const QDate day = QDate::fromString(trip.value("day").toString(), Qt::ISODate);
            if (day > QDate::currentDate())
                QCOMPARE(trip.value("dayHeading").toString(),
                         QLocale().toString(day, QStringLiteral("dddd")) + QLatin1Char(' ') + day.toString(QStringLiteral("MM/dd")));
        }
        QVERIFY(rig->store.eventDays().size() >= 2);
        QCOMPARE(rig->store.eventDays().first().toMap().value("day").toString(), QDate::currentDate().toString(Qt::ISODate));
        // The agent's color where the event has none.
        QCOMPARE(rig->store.events().at(0).toMap().value("color").toString(), QStringLiteral("#7A64E8"));
        QCOMPARE(rig->store.assistantProvider(), QStringLiteral("claude"));
        const QString snapshot = rig->store.snapshotText();
        QVERIFY2(snapshot.contains("Onyx (blocked)") && snapshot.contains("Sales today $4,280") && snapshot.contains("Standup"), qPrintable(snapshot));
        QVERIFY2(snapshot.contains("McFly (active, 62%), stage Build (2 of 4: Plan, Build, Review, Ship): next, Ship it"), qPrintable(snapshot));
    }

    // The console's cases (admin/tests/feed-layout.test.mjs), so the display
    // and the console tell a project's stages the same way.
    void projectsGroupByStatus()
    {
        auto project = [](const char *name, const char *status) { return QVariant(QVariantMap{{"name", name}, {"status", status}}); };
        // In `projects` order (already ranked); one the display doesn't know joins Active.
        const QVariantList groups = FeedStore::groupProjects({project("Lace", "blocked"), project("Armra", "active"), project("Odd", "archived"),
                                                              project("Holiday", "planned"), project("Taxes", "done")});
        QStringList shape;
        for (const QVariant &g : groups) {
            const QVariantMap m = g.toMap();
            QStringList names;
            for (const QVariant &p : m.value("projects").toList())
                names << p.toMap().value("name").toString();
            shape << QStringLiteral("%1@%2:%3").arg(m.value("label").toString()).arg(m.value("offset").toInt()).arg(names.join(QLatin1Char('+')));
        }
        QCOMPARE(shape.join(QLatin1Char(' ')), QStringLiteral("Blocked@0:Lace Active@1:Armra+Odd Paused@3: Up next@3:Holiday Done@4:Taxes"));
        QCOMPARE(groups.at(3).toMap().value("color").toString(), QStringLiteral("#7C8CF8"));
        QCOMPARE(groups.at(3).toMap().value("status").toString(), QStringLiteral("planned"));
    }

    void projectStagesFollowTheConsole()
    {
        const QStringList stages{"Plan", "Build", "Review", "Ship"};
        auto states = [](const QVariantMap &t) {
            QStringList out;
            for (const QVariant &s : t.value("steps").toList())
                out << s.toMap().value("state").toString();
            return out.join(QLatin1Char(' '));
        };
        const QVariantMap active = FeedStore::stageTrack(stages, "Build", "active");
        QCOMPARE(states(active), QStringLiteral("done current next next"));
        QCOMPARE(active.value("current").toString(), QStringLiteral("Build"));
        QCOMPARE(active.value("index").toInt(), 1);
        QCOMPARE(active.value("headline").toString(), QStringLiteral("Build"));
        QCOMPARE(active.value("position").toString(), QStringLiteral("2 of 4"));
        // Blocked or paused, the stage it's in says so.
        const QVariantMap blocked = FeedStore::stageTrack(stages, "Review", "blocked");
        QCOMPARE(states(blocked), QStringLiteral("done done blocked next"));
        QCOMPARE(blocked.value("headline").toString(), QStringLiteral("Blocked in Review"));
        QCOMPARE(blocked.value("steps").toList().at(2).toMap().value("word").toString(), QStringLiteral("Blocked here"));
        QCOMPARE(blocked.value("steps").toList().at(3).toMap().value("word").toString(), QStringLiteral("Stage 4"));
        const QVariantMap paused = FeedStore::stageTrack(stages, "Ship", "paused");
        QCOMPARE(paused.value("headline").toString(), QStringLiteral("Paused in Ship"));
        QCOMPARE(states(paused), QStringLiteral("done done done paused"));
        // Done: through them all, whatever stage it last named.
        const QVariantMap done = FeedStore::stageTrack(stages, "Build", "done");
        QCOMPARE(states(done), QStringLiteral("done done done done"));
        QVERIFY(done.value("current").toString().isEmpty());
        QCOMPARE(done.value("index").toInt(), 4);
        QCOMPARE(done.value("headline").toString(), QStringLiteral("All 4 stages done"));
        QCOMPARE(done.value("position").toString(), QStringLiteral("4 of 4"));
        QCOMPARE(FeedStore::stageTrack({"Ship"}, QString(), "done").value("headline").toString(), QStringLiteral("Done"));
        // Stages but no stage yet, or one the stages don't name (exactly, as
        // the console's indexOf): none reached.
        const QVariantMap fresh = FeedStore::stageTrack(stages, QString(), "active");
        QCOMPARE(states(fresh), QStringLiteral("next next next next"));
        QCOMPARE(fresh.value("index").toInt(), -1);
        QCOMPARE(fresh.value("headline").toString(), QStringLiteral("Not started"));
        QCOMPARE(fresh.value("position").toString(), QStringLiteral("4 stages"));
        QCOMPARE(FeedStore::stageTrack(stages, "build", "active").value("headline").toString(), QStringLiteral("Not started"));
        QCOMPARE(FeedStore::stageTrack({"Ship"}, QString(), "active").value("position").toString(), QStringLiteral("1 stage"));
        // Planned: none started, whatever stage it names.
        const QVariantMap planned = FeedStore::stageTrack(stages, "Plan", "planned");
        QCOMPARE(states(planned), QStringLiteral("next next next next"));
        QCOMPARE(planned.value("index").toInt(), -1);
        QCOMPARE(planned.value("headline").toString(), QStringLiteral("Planned"));
        QCOMPARE(planned.value("position").toString(), QStringLiteral("4 stages"));
        // No stages, no track.
        QVERIFY(FeedStore::stageTrack({}, QString(), "active").isEmpty());

        // How long it has been in its stage.
        const QDateTime now(QDate(2026, 10, 21), QTime(15, 0));
        auto ago = [&](double hours) { return FeedStore::timeInStage(now.addSecs(-qint64(hours * 3600)), now); };
        QCOMPARE(ago(20.0 / 60), QStringLiteral("under an hour"));
        QCOMPARE(ago(59.0 / 60), QStringLiteral("under an hour"));
        QCOMPARE(ago(1), QStringLiteral("1 hr"));
        QCOMPARE(ago(5 + 10.0 / 60), QStringLiteral("5 hr"));
        QCOMPARE(ago(23.9), QStringLiteral("23 hr"));
        QCOMPARE(ago(24), QStringLiteral("1 day"));
        QCOMPARE(ago(30), QStringLiteral("1 day"));
        QCOMPARE(ago(3 * 24), QStringLiteral("3 days"));
        QCOMPARE(ago(14 * 24 - 1), QStringLiteral("13 days"));
        QCOMPARE(ago(14 * 24), QStringLiteral("2 wk"));
        QCOMPARE(ago(20 * 24), QStringLiteral("2 wk"));
        QCOMPARE(ago(60 * 24 - 1), QStringLiteral("8 wk"));
        QCOMPARE(ago(60 * 24), QStringLiteral("2 mo"));
        QCOMPARE(ago(130 * 24), QStringLiteral("4 mo"));
        QCOMPARE(ago(-1), QStringLiteral("under an hour")); // a clock a little ahead
        QCOMPARE(FeedStore::timeInStage(QDateTime(), now), QString());
    }

    void todayTimeline()
    {
        startLive();
        // The feeds land one reply at a time, so the timeline fills in steps:
        // wait for the news and the standup, not just for the first thing.
        auto shows = [this](const QString &kind, const QString &title) {
            for (const QVariant &v : rig->store.timeline()) {
                const QVariantMap item = v.toMap();
                if (item.value("kind").toString() == kind && (title.isEmpty() || item.value("title").toString() == title))
                    return true;
            }
            return false;
        };
        QTRY_VERIFY(shows(QStringLiteral("news"), QString()));
        QTRY_VERIFY(shows(QStringLiteral("event"), QStringLiteral("Standup")) || QTime::currentTime() > QTime(22, 59));
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

    // Todos and reminders (migration 20261015000020): today's on the
    // timeline; a reminder announced once, when its time comes.
    void tomorrowIsPreviewedUnderToday()
    {
        // Tomorrow's events, shaped like timeline rows: all-day first, then in time order.
        const QDate today = QDate::currentDate(), next = today.addDays(1);
        m_server.route("/rest/v1/events", [today, next](const Request &) {
            return json(rows({
                QJsonObject{{"id", "e1"}, {"agent_id", "a1"}, {"calendar", "Work"}, {"title", "Standup"}, {"location", "Zoom"},
                            {"starts_at", iso(QDateTime(today, QTime(9, 30)))}, {"ends_at", iso(QDateTime(today, QTime(9, 45)))},
                            {"all_day", false}, {"color", "#5B7CF5"}},
                QJsonObject{{"id", "e2"}, {"agent_id", "a1"}, {"calendar", "Work"}, {"title", "Design review"}, {"location", QJsonValue::Null},
                            {"starts_at", iso(QDateTime(next, QTime(14, 0)))}, {"ends_at", iso(QDateTime(next, QTime(15, 30)))},
                            {"all_day", false}, {"color", "#5B7CF5"}},
                QJsonObject{{"id", "e3"}, {"agent_id", "a1"}, {"calendar", "Home"}, {"title", "Day off"}, {"location", QJsonValue::Null},
                            {"starts_at", iso(QDateTime(next, QTime(0, 0)))}, {"ends_at", iso(QDateTime(next, QTime(23, 59, 59)))},
                            {"all_day", true}, {"color", "#F6B94A"}},
                QJsonObject{{"id", "e4"}, {"agent_id", "a1"}, {"calendar", "Work"}, {"title", "Investor call"}, {"location", "Zoom"},
                            {"starts_at", iso(QDateTime(next, QTime(11, 0)))}, {"ends_at", iso(QDateTime(next, QTime(12, 0)))},
                            {"all_day", false}, {"color", QJsonValue::Null}},
            }));
        });
        startLive();
        QTRY_COMPARE(rig->store.tomorrow().size(), 3);
        const QVariantList tomorrow = rig->store.tomorrow();
        QCOMPARE(tomorrow.at(0).toMap().value("title").toString(), QStringLiteral("Day off"));
        QCOMPARE(tomorrow.at(0).toMap().value("timeLabel").toString(), QStringLiteral("All day"));
        const QVariantMap call = tomorrow.at(1).toMap();
        QCOMPARE(call.value("title").toString(), QStringLiteral("Investor call"));
        QCOMPARE(call.value("kind").toString(), QStringLiteral("event"));
        QCOMPARE(call.value("timeLabel").toString(), QStringLiteral("11:00"));
        QCOMPARE(call.value("ampm").toString(), QStringLiteral("am"));
        QCOMPARE(call.value("detail").toString(), QStringLiteral("11:00 am – 12:00 pm · Zoom"));
        QCOMPARE(call.value("color").toString(), QStringLiteral("#7A64E8")); // the agent's, as on today's rows
        QCOMPARE(call.value("target").toInt(), 6);
        QCOMPARE(tomorrow.at(2).toMap().value("title").toString(), QStringLiteral("Design review"));
        for (const QVariant &v : tomorrow)
            QCOMPARE(QDateTime::fromMSecsSinceEpoch(v.toMap().value("startMs").toLongLong()).date(), next);
        QCOMPARE(rig->store.tomorrowLabel(), QLocale().toString(next, QStringLiteral("dddd")));
        // Today's stream still stops at midnight.
        for (const QVariant &v : rig->store.timeline())
            QVERIFY(v.toMap().value("title").toString() != QLatin1String("Investor call"));
    }

    void todosAndReminders()
    {
        // A clock that runs from noon today, so the fixtures (hours either
        // side of it) never straddle midnight, whenever this runs.
        const QDateTime now(QDate::currentDate(), QTime(12, 0));
        auto running = std::make_shared<QElapsedTimer>();
        running->start();
        m_server.route("/rest/v1/todos", [now](const Request &) {
            return json(rows({
                QJsonObject{{"id", "t-undated"}, {"agent_id", "a1"}, {"kind", "todo"}, {"title", "Buy milk"}, {"notes", QJsonValue::Null},
                            {"due_at", QJsonValue::Null}, {"all_day", false}, {"done_at", QJsonValue::Null}},
                QJsonObject{{"id", "t-late"}, {"agent_id", "a1"}, {"kind", "todo"}, {"title", "File taxes"}, {"notes", QJsonValue::Null},
                            {"due_at", iso(QDateTime(QDate::currentDate().addDays(-2), QTime(0, 0)))}, {"all_day", true}, {"done_at", QJsonValue::Null}},
                QJsonObject{{"id", "t-later"}, {"agent_id", "a1"}, {"kind", "todo"}, {"title", "Book flights"}, {"notes", QJsonValue::Null},
                            {"due_at", iso(now.addDays(2))}, {"all_day", false}, {"done_at", QJsonValue::Null}},
                QJsonObject{{"id", "r-soon"}, {"agent_id", "a1"}, {"kind", "reminder"}, {"title", "Call mom"}, {"notes", "landline"},
                            {"due_at", iso(now.addMSecs(2500))}, {"all_day", false}, {"done_at", QJsonValue::Null}},
                QJsonObject{{"id", "r-old"}, {"agent_id", "a1"}, {"kind", "reminder"}, {"title", "Long gone"}, {"notes", QJsonValue::Null},
                            {"due_at", iso(now.addSecs(-3600))}, {"all_day", false}, {"done_at", QJsonValue::Null}},
            }));
        });
        QSettings().clear();
        QSettings().setValue("device/id", "dev-1");
        rig = std::make_unique<Rig>(m_server.baseUrl());
        rig->client.setRefreshToken("refresh-1");
        rig->store.setClock([now, running]() { return now.addMSecs(running->elapsed()); });
        QSignalSpy due(&rig->store, &FeedStore::reminderDue);
        rig->store.start();
        QTRY_VERIFY_WITH_TIMEOUT(rig->store.online(), 5000);
        auto row = [this](const QString &title) {
            for (const QVariant &v : rig->store.timeline())
                if (v.toMap().value("title").toString() == title)
                    return v.toMap();
            return QVariantMap();
        };
        QTRY_VERIFY(!row(QStringLiteral("Buy milk")).isEmpty());

        const QVariantMap milk = row(QStringLiteral("Buy milk"));
        QCOMPARE(milk.value("kind").toString(), QStringLiteral("todo"));
        QVERIFY(milk.value("allDay").toBool()); // heads the day
        QCOMPARE(milk.value("timeLabel").toString(), QStringLiteral("To do"));
        QCOMPARE(milk.value("label").toString(), QStringLiteral("Grok · To do"));
        QCOMPARE(milk.value("detail").toString(), QString());
        QCOMPARE(milk.value("target").toInt(), 6);
        QCOMPARE(milk.value("color").toString(), QStringLiteral("#7A64E8")); // its agent's
        QVERIFY(row(QStringLiteral("File taxes")).value("detail").toString().startsWith(QStringLiteral("Was due ")));
        QVERIFY(row(QStringLiteral("Book flights")).isEmpty()); // not today's
        const QVariantMap mom = row(QStringLiteral("Call mom"));
        QCOMPARE(mom.value("kind").toString(), QStringLiteral("reminder"));
        QVERIFY(!mom.value("allDay").toBool());
        QCOMPARE(mom.value("label").toString(), QStringLiteral("Grok · Reminder"));
        QCOMPARE(mom.value("detail").toString(), QStringLiteral("landline"));
        QCOMPARE(row(QStringLiteral("Long gone")).value("kind").toString(), QStringLiteral("reminder")); // a past row

        // Its time comes: announced once, the old one never.
        QTRY_COMPARE_WITH_TIMEOUT(due.count(), 1, 6000);
        const QVariantMap fired = due.first().first().toMap();
        QCOMPARE(fired.value("id").toString(), QStringLiteral("r-soon"));
        QCOMPARE(fired.value("title").toString(), QStringLiteral("Call mom"));
        QCOMPARE(fired.value("notes").toString(), QStringLiteral("landline"));
        QVERIFY(!fired.value("timeLabel").toString().isEmpty());
        rig->store.refresh(); // the next sync brings it again
        QTest::qWait(800);
        QCOMPARE(due.count(), 1);
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

    // Every list is a model on some screen, and all seven screens are built:
    // a dataChanged rebuilds each of their delegates. A sync that brings the
    // same rows says nothing, and one that brings something new says it once,
    // after its last answer (the optional tables included), not once each.
    void aSyncSaysWhatChangedOnce()
    {
        auto title = std::make_shared<QString>(QStringLiteral("Remember the milk"));
        m_server.route("/rest/v1/memories", [title](const Request &) {
            return json(rows(QJsonArray{QJsonObject{{"text", *title}, {"pinned", false}, {"updated_at", QJsonValue::Null}}}));
        });
        m_server.route("/rest/v1/todos", [](const Request &) { return json("[]"); });
        m_server.route("/rest/v1/rpc/list_calendar_sources", [](const Request &) { return json("[]"); });
        startLive();
        QTRY_COMPARE(rig->store.memories().size(), 1);
        QTRY_COMPARE(m_server.pending(), 0);
        QTest::qWait(100);
        QSignalSpy data(&rig->store, &FeedStore::dataChanged);

        // The same rows twice: nothing to say.
        for (int i = 0; i < 2; ++i) {
            const qsizetype before = m_server.requests("GET", "/rest/v1/todos").size();
            rig->store.refresh();
            QTRY_COMPARE(m_server.requests("GET", "/rest/v1/todos").size(), before + 1);
            QTRY_COMPARE(m_server.pending(), 0);
            QTest::qWait(100);
        }
        QCOMPARE(data.count(), 0);

        // A new memory (an optional table) and the rest the same: once.
        *title = QStringLiteral("Buy the almanac");
        rig->store.refresh();
        QTRY_COMPARE(rig->store.memories().value(0).toMap().value("text").toString(), QStringLiteral("Buy the almanac"));
        QTRY_COMPARE(m_server.pending(), 0);
        QTest::qWait(100);
        QCOMPARE(data.count(), 1);
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

    void aVoiceSetElsewhereSurvivesTheDisplaysOwnSave()
    {
        // The phone sets the account's voice between two syncs, and the display
        // saves a change of its own in between. The answer to that save already
        // holds the phone's voice; the next sync must still bring it to the screen.
        auto row = std::make_shared<QJsonObject>(QJsonObject{{"screensaver", "ambient"}, {"voice", "af_heart"}});
        m_server.route("/rest/v1/devices", [row](const Request &r) {
            if (r.method == "GET")
                return json(rows(QJsonArray{QJsonObject{{"settings", *row}}}));
            return json("[]"); // the check-in
        });
        m_server.route("/rest/v1/rpc/device_update_settings", [row](const Request &r) {
            const QJsonObject patch = r.body.value("patch").toObject();
            for (auto it = patch.begin(); it != patch.end(); ++it)
                row->insert(it.key(), it.value());
            return json(QJsonDocument(*row));
        });
        startLive();
        QSignalSpy received(&rig->store, &FeedStore::deviceSettingsReceived);
        settleFirstSync(received);

        row->insert("voice", "am_fenrir"); // from the phone
        rig->store.pushDeviceSettings({{"screensaver", "clock"}});
        QTRY_COMPARE(m_server.requests("POST", "/rest/v1/rpc/device_update_settings").size(), 1);
        QTest::qWait(100); // its answer handled

        rig->store.refresh();
        QTRY_COMPARE(received.size(), 1);
        QCOMPARE(received.first().first().toMap().value("voice").toString(), QStringLiteral("am_fenrir"));

        // Nothing new after that: a sync leaves the screen alone.
        rig->store.refresh();
        QTest::qWait(500);
        QCOMPARE(received.size(), 1);
    }

    void aKeyTheServerDropsIsNotSentAgainAndAgain()
    {
        // An older server drops a newer display's extra key (clean_device_settings).
        // The display saves once and leaves it at that, rather than every sync.
        auto row = std::make_shared<QJsonObject>(QJsonObject{{"screensaver", "ambient"}});
        m_server.route("/rest/v1/devices", [row](const Request &r) {
            if (r.method == "GET")
                return json(rows(QJsonArray{QJsonObject{{"settings", *row}}}));
            return json("[]");
        });
        m_server.route("/rest/v1/rpc/device_update_settings", [row](const Request &r) {
            const QJsonObject patch = r.body.value("patch").toObject();
            for (auto it = patch.begin(); it != patch.end(); ++it)
                if (it.key() != QLatin1String("futureKey"))
                    row->insert(it.key(), it.value());
            return json(QJsonDocument(*row));
        });
        startLive();
        QSignalSpy received(&rig->store, &FeedStore::deviceSettingsReceived);
        settleFirstSync(received);

        rig->store.pushDeviceSettings({{"futureKey", 1}, {"screensaver", "clock"}});
        QTRY_COMPARE(m_server.requests("POST", "/rest/v1/rpc/device_update_settings").size(), 1);
        QTest::qWait(100);
        rig->store.refresh();
        QTest::qWait(500);
        rig->store.refresh();
        QTest::qWait(500);
        QCOMPARE(received.size(), 0);
        QCOMPARE(m_server.requests("POST", "/rest/v1/rpc/device_update_settings").size(), 1);
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
        if (!nearMidnight())
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
        // The demo's projects have stages, as the console's do, but one.
        {
            const QVariantMap onyx = rig->store.project("demo-project-onyx");
            QCOMPARE(onyx.value("track").toMap().value("headline").toString(), QStringLiteral("Blocked in App Review"));
            QCOMPARE(onyx.value("stageFor").toString(), QStringLiteral("5 days"));
            QCOMPARE(rig->store.project("demo-project-taxes").value("track").toMap().value("headline").toString(), QStringLiteral("All 3 stages done"));
            QVERIFY(rig->store.project("demo-project-taxes").value("stageFor").toString().isEmpty());
            QVERIFY(!rig->store.project("demo-project-pulse").value("hasStages").toBool());
        }
        QVERIFY(rig->store.metrics().size() >= 5);
        QVERIFY(rig->store.metricGroups().size() >= 2);
        QVERIFY(rig->store.dashboards().size() >= 2);
        QVERIFY(rig->store.events().size() >= 7);
        QVERIFY(rig->store.eventDays().size() >= 4);
        QVERIFY(rig->store.newsSources().size() >= 1);
        QCOMPARE(rig->store.lastSyncLabel(), QStringLiteral("Sample data"));
        // Todos and reminders: today's on the timeline.
        QStringList kinds;
        for (const QVariant &v : rig->store.timeline())
            kinds << v.toMap().value("kind").toString();
        QVERIFY(kinds.contains(QStringLiteral("todo")));
        if (!nearMidnight())
            QVERIFY(kinds.contains(QStringLiteral("reminder")));
        // Memory and agent scopes (migration 20261015000001).
        QCOMPARE(rig->store.memories().size(), 3);
        QCOMPARE(rig->store.calendarSources().size(), 2);
        QVERIFY(!rig->store.calendarSources().at(1).toMap().value("error").toString().isEmpty());
        QCOMPARE(rig->store.calendarSources().first().toMap().value("eventCount").toInt(), 14);
        QVERIFY(rig->store.memories().first().toMap().value("pinned").toBool());
        QVERIFY(!rig->store.memories().first().toMap().value("updatedLabel").toString().isEmpty());
        const QVariantMap grok = rig->store.agents().first().toMap();
        QCOMPARE(grok.value("scopeLabels").toStringList(), (QStringList{QStringLiteral("Calendar"), QStringLiteral("Reads memory")}));
        QVERIFY(m_server.requests().isEmpty());
    }

    void boardMetricsKnowGoodNews()
    {
        // A board's falling error rate is good news, as a falling metric is.
        QSettings().clear();
        rig = std::make_unique<Rig>(QUrl(), true);
        rig->store.start();
        QVariantMap errors, signups;
        for (const QVariant &d : rig->store.dashboards())
            for (const QVariant &w : d.toMap().value("widgets").toList()) {
                const QVariantMap m = w.toMap();
                if (m.value("label") == QLatin1String("Errors"))
                    errors = m;
                if (m.value("label") == QLatin1String("Signups"))
                    signups = m;
            }
        QCOMPARE(errors.value("trend").toString(), QStringLiteral("down"));
        QVERIFY(errors.value("good").toBool());
        QVERIFY(!errors.value("up").toBool()); // unchanged: `up` still says which way it went
        QCOMPARE(signups.value("trend").toString(), QStringLiteral("up"));
        QVERIFY(signups.value("good").toBool());
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

    // ── What stands out, ranges, changes, bento boards, the day dial ──

    void demoHighlightsRankWhatStandsOut()
    {
        // 3:10 pm: the 3:30 Pulse review is 20 minutes out.
        startDemoAt(QTime(15, 10));
        const QVariantList highlights = rig->store.highlights();
        QCOMPARE(highlights.size(), 5);
        QStringList kinds;
        for (const QVariant &v : highlights)
            kinds << v.toMap().value("kind").toString();
        // Blocked, a board's status, the metrics far off their usual, then the meeting.
        QCOMPARE(kinds, (QStringList{"blocked", "status", "metric", "metric", "event"}));
        const QStringList icons = iconNames();
        QVERIFY(icons.size() > 20);
        for (const QVariant &v : highlights) {
            const QVariantMap h = v.toMap();
            QVERIFY2(icons.contains(h.value("icon").toString()), qPrintable(h.value("icon").toString()));
            for (const char *field : {"id", "kind", "icon", "title", "detail", "color", "tone", "screen", "segment", "board", "itemId", "question"})
                QVERIFY2(h.contains(field), field);
            QVERIFY(!h.contains("strength"));
        }

        const QVariantMap blocked = highlights.at(0).toMap();
        QCOMPARE(blocked.value("title").toString(), QStringLiteral("Onyx is blocked"));
        QCOMPARE(blocked.value("detail").toString(), QStringLiteral("App Review's answer on the FSKit entitlement"));
        QCOMPARE(blocked.value("screen").toInt(), 4);
        QCOMPARE(blocked.value("itemId").toString(), QStringLiteral("demo-project-onyx"));
        QCOMPARE(blocked.value("question").toString(), QStringLiteral("What's blocking Onyx?"));
        QCOMPARE(blocked.value("tone").toString(), QStringLiteral("warn"));

        // The worst status first (Search is down, Workers only warns).
        const QVariantMap status = highlights.at(1).toMap();
        QCOMPARE(status.value("title").toString(), QStringLiteral("Search is down"));
        QCOMPARE(status.value("detail").toString(), QStringLiteral("Index rebuilding since 3:10 · Ops · +1 more"));
        QCOMPARE(status.value("tone").toString(), QStringLiteral("bad"));
        QCOMPARE(status.value("screen").toInt(), 5);
        QCOMPARE(status.value("board").toInt(), 0);
        QCOMPARE(status.value("question").toString(), QStringLiteral("Why is Search down?"));

        // Seven points: too few for a z, so the agents' own 10% jumps count,
        // strongest first. Errors falling is good news.
        const QVariantMap errors = highlights.at(2).toMap();
        QCOMPARE(errors.value("title").toString(), QStringLiteral("Error rate is down 30.0%"));
        QCOMPARE(errors.value("tone").toString(), QStringLiteral("good"));
        QCOMPARE(errors.value("screen").toInt(), 2);
        QCOMPARE(errors.value("segment").toString(), QStringLiteral("metrics"));
        QCOMPARE(errors.value("question").toString(), QStringLiteral("What's behind the drop in Error rate?"));
        QCOMPARE(highlights.at(3).toMap().value("title").toString(), QStringLiteral("Sales today is up 12.5%"));

        const QVariantMap event = highlights.at(4).toMap();
        QCOMPARE(event.value("title").toString(), QStringLiteral("Pulse review with the team starts in 20 min"));
        QVERIFY(event.value("detail").toString().endsWith(QStringLiteral(" · Zoom")));
        QCOMPARE(event.value("screen").toInt(), 6);
        QCOMPARE(event.value("tone").toString(), QStringLiteral("neutral"));
        QCOMPARE(event.value("question").toString(), QStringLiteral("What do I need for Pulse review with the team?"));

        // At noon nothing is about to start: the big mover takes the slot.
        startDemoAt(QTime(12, 0));
        const QVariantMap mover = rig->store.highlights().at(4).toMap();
        QCOMPARE(mover.value("kind").toString(), QStringLiteral("mover"));
        QCOMPARE(mover.value("title").toString(), QStringLiteral("TSLA is up 4.0%"));
        QCOMPARE(mover.value("detail").toString(), QStringLiteral("$402.10 · 4.8× its usual daily move"));
        QCOMPARE(mover.value("icon").toString(), QStringLiteral("arrow-up"));
        QCOMPARE(mover.value("segment").toString(), QStringLiteral("markets"));
        QCOMPARE(mover.value("itemId").toString(), QStringLiteral("TSLA"));
        QCOMPARE(mover.value("question").toString(), QStringLiteral("Why is TSLA up 4.0% today?"));
    }

    void highlightsMoveWithTheMinute()
    {
        // A second before 3:11: the minute tick comes almost at once.
        startDemoAt(QTime(15, 10, 59, 900));
        QCOMPARE(rig->store.highlights().at(4).toMap().value("title").toString(), QStringLiteral("Pulse review with the team starts in 19 min"));
        QCOMPARE(rig->store.nowAngle(), (15 * 60 + 10) * 0.25);
        QSignalSpy ticked(&rig->store, &FeedStore::nowAngleChanged);
        QSignalSpy changed(&rig->store, &FeedStore::highlightsChanged);
        QSignalSpy data(&rig->store, &FeedStore::dataChanged);
        // (A tenth of a second before the next minute again, so the tick after comes soon too.)
        m_fake = QDateTime(m_fake.date(), QTime(15, 31, 59, 900));
        QTRY_VERIFY_WITH_TIMEOUT(ticked.count() >= 1, 3000);
        QCOMPARE(rig->store.nowAngle(), (15 * 60 + 31) * 0.25);
        QCOMPARE(changed.count(), 1);
        QCOMPARE(data.count(), 0); // nothing else re-binds
        QCOMPARE(rig->store.highlights().at(4).toMap().value("title").toString(), QStringLiteral("Pulse review with the team has started"));
        // The same minute again changes nothing.
        QTRY_VERIFY_WITH_TIMEOUT(ticked.count() >= 2, 3000);
        QCOMPARE(changed.count(), 1);
    }

    void liveHighlights()
    {
        startLive();
        QTRY_COMPARE(rig->store.highlights().size(), 5);
        QTRY_VERIFY(rig->store.highlights().last().toMap().value("kind").toString() == QLatin1String("pulse"));
        QStringList kinds;
        for (const QVariant &v : rig->store.highlights())
            kinds << v.toMap().value("kind").toString();
        // No meeting within 30 min (the standup is an hour out), no big mover.
        QCOMPARE(kinds, (QStringList{"blocked", "status", "metric", "brief", "pulse"}));
        const QVariantMap status = rig->store.highlights().at(1).toMap();
        QCOMPARE(status.value("title").toString(), QStringLiteral("API has a warning"));
        QCOMPARE(status.value("detail").toString(), QStringLiteral("slow · Ops"));
        QCOMPARE(status.value("question").toString(), QStringLiteral("What's wrong with API?"));
        QCOMPARE(status.value("itemId").toString(), QStringLiteral("d1"));
        const QVariantMap brief = rig->store.highlights().at(3).toMap();
        QCOMPARE(brief.value("title").toString(), QStringLiteral("Grok posted “Newest”"));
        QCOMPARE(brief.value("detail").toString(), QStringLiteral("10 min ago · First paragraph."));
        QCOMPARE(brief.value("screen").toInt(), 1);
        QCOMPARE(brief.value("question").toString(), QStringLiteral("What did Grok just say?"));
        const QVariantMap pulse = rig->store.highlights().at(4).toMap();
        QCOMPARE(pulse.value("title").toString(), QStringLiteral("Two"));
        QCOMPARE(pulse.value("detail").toString(), QStringLiteral("Grok · 3 stories"));
        QCOMPARE(pulse.value("itemId").toString(), QStringLiteral("r2"));
        QCOMPARE(pulse.value("question").toString(), QStringLiteral("Tell me more about “Two”"));
    }

    void metricAnomaliesUseARobustZ()
    {
        const QDateTime now = QDateTime::currentDateTime();
        // Ten readings each: a latency spike far past its usual spread; a flat
        // count with a 15% jump reported (no spread, so the jump counts); a
        // varied series whose reported 15% is within its usual (the z wins).
        auto series = [&now](const QString &key, const QString &unit, const QList<double> &values, const QJsonValue &pct) {
            QJsonArray out;
            for (int i = 0; i < values.size(); ++i)
                out.append(QJsonObject{{"id", key + QString::number(i)}, {"agent_id", "a2"}, {"key", key}, {"label", QJsonValue::Null},
                                       {"value", values.at(i)}, {"unit", unit}, {"delta", QJsonValue::Null},
                                       {"delta_pct", i == values.size() - 1 ? pct : QJsonValue::Null}, {"note", QJsonValue::Null},
                                       {"as_of", iso(now.addSecs(-3600 * (values.size() - 1 - i)))}});
            return out;
        };
        QJsonArray all;
        for (const QJsonArray &a : {series("api.latency", "ms", {100, 102, 99, 101, 100, 98, 103, 100, 101, 180}, QJsonValue::Null),
                                    series("orders.open", "", {20, 20, 20, 20, 20, 20, 20, 20, 20, 23}, 15),
                                    series("signups", "", {10, 30, 12, 28, 15, 25, 11, 29, 14, 24}, 15)})
            for (const QJsonValue &v : a)
                all.append(v);
        m_server.route("/rest/v1/metric_settings", [](const Request &) {
            return json(R"([{"key":"api.latency","label":"API latency","group_name":"Ops","sort_order":0,"hidden":false},{"key":"orders.open","label":"Open orders","group_name":"Store","sort_order":1,"hidden":false},{"key":"signups","label":"Signups","group_name":"Store","sort_order":2,"hidden":false}])");
        });
        m_server.route("/rest/v1/metrics", [all](const Request &) { return json(rows(all)); });
        startLive();
        QTRY_COMPARE(rig->store.metrics().size(), 3);
        const QVariantMap latency = rig->store.metrics().at(0).toMap();
        QVERIFY(latency.value("anomaly").toBool());
        QCOMPARE(latency.value("usualLabel").toString(), QStringLiteral("100 ms"));
        QCOMPARE(latency.value("goodDirection").toString(), QStringLiteral("down"));
        QCOMPARE(latency.value("trend").toString(), QStringLiteral("up"));
        QVERIFY(!latency.value("good").toBool());
        QVERIFY(rig->store.metrics().at(1).toMap().value("anomaly").toBool());
        QVERIFY(!rig->store.metrics().at(2).toMap().value("anomaly").toBool());

        QTRY_VERIFY(!rig->store.highlights().isEmpty());
        QVariantList metrics;
        for (const QVariant &v : rig->store.highlights())
            if (v.toMap().value("kind").toString() == QLatin1String("metric"))
                metrics << v;
        QCOMPARE(metrics.size(), 2);
        const QVariantMap spike = metrics.at(0).toMap(); // z ≈ 54, stronger than a 15% jump
        QCOMPARE(spike.value("title").toString(), QStringLiteral("API latency is unusually high"));
        QCOMPARE(spike.value("detail").toString(), QStringLiteral("180 ms, against a usual 100 ms"));
        QCOMPARE(spike.value("tone").toString(), QStringLiteral("bad"));
        QCOMPARE(spike.value("question").toString(), QStringLiteral("What's behind the rise in API latency?"));
        const QVariantMap jump = metrics.at(1).toMap();
        QCOMPARE(jump.value("title").toString(), QStringLiteral("Open orders is up 15.0%"));
        QCOMPARE(jump.value("detail").toString(), QStringLiteral("23"));
        QCOMPARE(jump.value("tone").toString(), QStringLiteral("good"));
    }

    void quotesAndMetricsCarryRangesAndChanges()
    {
        startLive();
        QTRY_COMPARE(rig->store.quotes().size(), 2);
        QTRY_COMPARE(rig->store.metrics().size(), 2);
        const QVariantMap spy = rig->store.quotes().at(0).toMap();
        QCOMPARE(spy.value("low").toDouble(), 660.0);
        QCOMPARE(spy.value("high").toDouble(), 668.42);
        QCOMPARE(spy.value("lowLabel").toString(), QStringLiteral("$660.00"));
        QCOMPARE(spy.value("highLabel").toString(), QStringLiteral("$668.42"));
        QCOMPARE(spy.value("rangePos").toDouble(), 1.0);
        QVERIFY(spy.value("fresh").toBool());
        QVERIFY(qAbs(spy.value("heat").toDouble() - 8.42 / 660 * 100 / 3) < 1e-9);
        QCOMPARE(spy.value("swingPct").toDouble(), 0.0); // two closes: no usual swing yet
        QVERIFY(!spy.value("bigMove").toBool());
        QVERIFY(!spy.contains("good")); // quotes keep up/down
        // First sight: no change to animate.
        QCOMPARE(rig->store.quote("AAPL").value("changedMs").toLongLong(), 0);
        QCOMPARE(spy.value("changedMs").toLongLong(), 0);
        const QVariantMap breadth = rig->store.marketBreadth();
        QCOMPARE(breadth.value("up").toInt(), 2);
        QCOMPARE(breadth.value("down").toInt(), 0);
        QCOMPARE(breadth.value("flat").toInt(), 0);
        QCOMPARE(breadth.value("total").toInt(), 2);
        QCOMPARE(breadth.value("label").toString(), QStringLiteral("2 up"));

        const QVariantMap sales = rig->store.metrics().at(0).toMap();
        QCOMPARE(sales.value("lowLabel").toString(), QStringLiteral("$3,800"));
        QCOMPARE(sales.value("highLabel").toString(), QStringLiteral("$4,280"));
        QCOMPARE(sales.value("rangePos").toDouble(), 1.0);
        QCOMPARE(sales.value("goodDirection").toString(), QStringLiteral("up"));
        QCOMPARE(sales.value("trend").toString(), QStringLiteral("up")); // from the agent's percentage alone
        QVERIFY(sales.value("good").toBool());
        QVERIFY(sales.value("fresh").toBool());
        QVERIFY(sales.value("anomaly").toBool()); // two points, a 12.5% jump
        QCOMPARE(sales.value("usualLabel").toString(), QStringLiteral("$3,800"));
        const QVariantMap p95 = rig->store.metrics().at(1).toMap();
        QCOMPARE(p95.value("goodDirection").toString(), QStringLiteral("down")); // ms, and a p95
        QCOMPARE(p95.value("trend").toString(), QStringLiteral("down"));
        QVERIFY(p95.value("good").toBool()); // latency falling is good news
        QVERIFY(!p95.value("anomaly").toBool());
        QCOMPARE(p95.value("changedMs").toLongLong(), 0);

        // Apple moves on the next sync: only its row says so.
        const QDateTime later = QDateTime::currentDateTime().addSecs(1);
        m_server.route("/rest/v1/quotes", [later](const Request &) {
            return json(rows({
                QJsonObject{{"id", 4}, {"agent_id", "a2"}, {"symbol", "AAPL"}, {"name", "Apple"}, {"price", 250.0}, {"change", 4.88},
                            {"change_pct", 1.99}, {"currency", "USD"}, {"note", QJsonValue::Null}, {"as_of", iso(later)}},
                QJsonObject{{"id", 2}, {"agent_id", "a2"}, {"symbol", "AAPL"}, {"name", "Apple"}, {"price", 245.12}, {"change", 1.42},
                            {"change_pct", 0.58}, {"currency", "USD"}, {"note", QJsonValue::Null}, {"as_of", iso(later.addDays(-1))}},
                QJsonObject{{"id", 1}, {"agent_id", "a2"}, {"symbol", "SPY"}, {"price", 668.42}, {"change", QJsonValue::Null},
                            {"change_pct", QJsonValue::Null}, {"currency", "USD"}, {"as_of", iso(later.addSecs(-1))}},
                QJsonObject{{"id", 0}, {"agent_id", "a2"}, {"symbol", "SPY"}, {"price", 660.0}, {"change", QJsonValue::Null},
                            {"change_pct", QJsonValue::Null}, {"currency", "USD"}, {"as_of", iso(later.addDays(-1))}},
            }));
        });
        m_server.route("/rest/v1/quotes_latest", [](const Request &) { return json("[]"); }); // matched before the route above
        const qint64 before = QDateTime::currentMSecsSinceEpoch();
        rig->store.refresh();
        QTRY_COMPARE(rig->store.quote("AAPL").value("priceLabel").toString(), QStringLiteral("$250.00"));
        const QVariantMap aapl = rig->store.quote("AAPL");
        QVERIFY(aapl.value("changedMs").toLongLong() >= before);
        QVERIFY(aapl.value("changedMs").toLongLong() <= QDateTime::currentMSecsSinceEpoch());
        QVERIFY(aapl.value("changedUp").toBool());
        QCOMPARE(rig->store.quote("SPY").value("changedMs").toLongLong(), 0); // same price
        QCOMPARE(rig->store.metrics().at(1).toMap().value("changedMs").toLongLong(), 0);
        // A rebuild with nothing new (another day's report picked) keeps the stamp.
        const qint64 stamped = aapl.value("changedMs").toLongLong();
        rig->store.showReport(QStringLiteral("r1"));
        QCOMPARE(rig->store.quote("AAPL").value("changedMs").toLongLong(), stamped);
    }

    void briefsSplitPointsFromParagraphs()
    {
        startDemoAt(QTime(12, 0));
        QVariantMap morning;
        for (const QVariant &v : rig->store.briefs())
            if (v.toMap().value("title").toString() == QLatin1String("Morning briefing"))
                morning = v.toMap();
        QCOMPARE(morning.value("paragraphs").toStringList(), (QStringList{"Three things for today.", "Have a good one."}));
        QCOMPARE(morning.value("bullets").toStringList().size(), 3);
        QCOMPARE(morning.value("bullets").toStringList().first(), QStringLiteral("The Fed minutes land at 1 PM CT; markets are pricing a hold."));

        // Live: a point carried onto an indented line, text either side.
        m_server.route("/rest/v1/briefs", [](const Request &) {
            return json(rows({QJsonObject{{"id", "b1"}, {"agent_id", "a1"}, {"title", "Points"}, {"kind", "daily"},
                                          {"body", "Intro line.\n- First point\n  carries on\n- Second point\nOutro.\n\n• Third"},
                                          {"published_at", iso(QDateTime::currentDateTime().addSecs(-60))}, {"expires_at", QJsonValue::Null}}}));
        });
        startLive();
        QTRY_COMPARE(rig->store.briefs().size(), 1);
        const QVariantMap brief = rig->store.briefs().first().toMap();
        QCOMPARE(brief.value("paragraphs").toStringList(), (QStringList{"Intro line.", "Outro."}));
        QCOMPARE(brief.value("bullets").toStringList(), (QStringList{"First point carries on", "Second point", "Third"}));
    }

    // The reader's blocks follow the body: a heading stays over its own
    // points, a leading list stays first, a paragraph keeps its line breaks
    // (Markdown needs them), and a fenced block is left whole.
    void briefBlocksKeepTheBodysOrder()
    {
        auto paragraph = [](const QString &text) { return QVariant(QVariantMap{{"kind", "paragraph"}, {"text", text}}); };
        auto points = [](const QStringList &items) { return QVariant(QVariantMap{{"kind", "points"}, {"items", items}}); };

        startDemoAt(QTime(12, 0));
        QVariantMap morning;
        for (const QVariant &v : rig->store.briefs())
            if (v.toMap().value("title").toString() == QLatin1String("Morning briefing"))
                morning = v.toMap();
        QCOMPARE(morning.value("blocks").toList(),
                 (QVariantList{paragraph("Three things for today."),
                               points({"The Fed minutes land at 1 PM CT; markets are pricing a hold.",
                                       "Apple reports after the close; services is the number to watch.",
                                       "The Pulse pipeline ran at 8:06 and found 11 sourced stories."}),
                               paragraph("Have a good one.")}));

        const QList<QPair<QString, QString>> bodies{
            {"Grouped", "**Markets**\n- SPY flat\n\n**Tech**\n- Apple tonight\n  after the bell"},
            {"Leading", "- a\n- b\n\nSo what"},
            {"Heading", "## Heading\nText\n\n- x\n\n1. one\n2. two"},
            {"Fenced", "Run:\n\n```\n- not a point\n\nstill code\n```\n\n- a point"},
        };
        m_server.route("/rest/v1/briefs", [bodies](const Request &) {
            QJsonArray out;
            for (const auto &[title, body] : bodies)
                out.append(QJsonObject{{"id", title}, {"agent_id", "a1"}, {"title", title}, {"kind", "daily"}, {"body", body},
                                       {"published_at", iso(QDateTime::currentDateTime().addSecs(-60))}, {"expires_at", QJsonValue::Null}});
            return json(rows(out));
        });
        startLive();
        QTRY_COMPARE(rig->store.briefs().size(), 4);
        QHash<QString, QVariantList> blocks;
        for (const QVariant &v : rig->store.briefs())
            blocks.insert(v.toMap().value("title").toString(), v.toMap().value("blocks").toList());
        QCOMPARE(blocks.value("Grouped"), (QVariantList{paragraph("**Markets**"), points({"SPY flat"}), paragraph("**Tech**"),
                                                        points({"Apple tonight after the bell"})}));
        QCOMPARE(blocks.value("Leading"), (QVariantList{points({"a", "b"}), paragraph("So what")}));
        QCOMPARE(blocks.value("Heading"), (QVariantList{paragraph("## Heading\nText"), points({"x"}), paragraph("1. one\n2. two")}));
        QCOMPARE(blocks.value("Fenced"), (QVariantList{paragraph(bodies.at(3).second)}));
    }

    void boardLayoutPacksWithoutHoles()
    {
        startDemoAt(QTime(12, 0));
        QCOMPARE(rig->store.dashboards().size(), 2);
        for (int board = 0; board < 2; ++board) {
            for (int columns : {2, 4, 6})
                checkPacked(rig->store.boardLayout(board, columns), columns, rig->store.dashboards().at(board).toMap().value("widgets").toList());
        }
        // Ops on six: the three statuses as one strip, the first metric a 2×2
        // hero, the chart 4×2.
        const QVariantList ops = rig->store.boardLayout(0, 6);
        const QVariantMap health = ops.at(0).toMap();
        QCOMPARE(health.value("kind").toString(), QStringLiteral("health"));
        QCOMPARE(health.value("indexes").toList(), (QVariantList{0, 1, 2}));
        QCOMPARE(health.value("colSpan").toInt(), 6);
        QCOMPARE(health.value("state").toString(), QStringLiteral("down"));
        QCOMPARE(health.value("stateColor").toString(), QStringLiteral("#F07F5A"));
        QCOMPARE(health.value("summary").toString(), QStringLiteral("1 down · 1 warning · 1 OK"));
        const QVariantMap hero = ops.at(1).toMap();
        QCOMPARE(hero.value("kind").toString(), QStringLiteral("hero"));
        QCOMPARE(hero.value("index").toInt(), 3);
        QCOMPARE(QList<int>({hero.value("row").toInt(), hero.value("col").toInt(), hero.value("colSpan").toInt(), hero.value("rowSpan").toInt()}),
                 QList<int>({1, 0, 2, 2}));
        auto entryFor = [](const QVariantList &layout, int index) {
            for (const QVariant &v : layout)
                if (v.toMap().value("indexes").toList().contains(index))
                    return v.toMap();
            return QVariantMap();
        };
        QCOMPARE(entryFor(ops, 7).value("kind").toString(), QStringLiteral("chart"));
        QCOMPARE(entryFor(ops, 7).value("colSpan").toInt(), 4);
        QCOMPARE(entryFor(ops, 7).value("rowSpan").toInt(), 2);
        // Four columns: the chart goes full width; two: no hero.
        QCOMPARE(entryFor(rig->store.boardLayout(0, 4), 7).value("colSpan").toInt(), 4);
        QCOMPARE(entryFor(rig->store.boardLayout(0, 2), 3).value("kind").toString(), QStringLiteral("metric"));
        QCOMPARE(entryFor(rig->store.boardLayout(0, 2), 7).value("colSpan").toInt(), 2);
        // A lone status stays a tile of its own.
        QCOMPARE(entryFor(rig->store.boardLayout(1, 6), 5).value("kind").toString(), QStringLiteral("status"));
        // Reading order.
        int lastRow = -1, lastCol = -1;
        for (const QVariant &v : ops) {
            const int row = v.toMap().value("row").toInt(), col = v.toMap().value("col").toInt();
            QVERIFY(row > lastRow || (row == lastRow && col > lastCol));
            lastRow = row;
            lastCol = col;
        }
        QVERIFY(rig->store.boardLayout(2, 6).isEmpty());
        QVERIFY(rig->store.boardLayout(-1, 6).isEmpty());
        // The widgets themselves are left as they were, each marked drawable.
        for (const QVariant &v : rig->store.dashboards().first().toMap().value("widgets").toList())
            QVERIFY(v.toMap().value("known").toBool());
    }

    void unknownWidgetsAreMarkedAndSkipped()
    {
        const QDateTime now = QDateTime::currentDateTime();
        m_server.route("/rest/v1/dashboards", [now](const Request &) {
            return json(rows({QJsonObject{{"id", "d1"}, {"agent_id", "a2"}, {"key", "ops"}, {"title", "Ops"}, {"sort_order", 0}, {"hidden", false},
                                          {"updated_at", iso(now)},
                                          {"widgets", QJsonArray{QJsonObject{{"type", "metric"}, {"label", "Requests"}, {"value", 1}},
                                                                 QJsonObject{{"type", "gauge"}, {"label", "From a newer agent"}, {"value", 3}},
                                                                 QJsonObject{{"type", "status"}, {"label", "API"}, {"state", "ok"}},
                                                                 QJsonObject{{"type", "status"}, {"label", "DB"}, {"state", "ok"}},
                                                                 QJsonObject{{"type", "list"}, {"title", "On call"}, {"items", QJsonArray{"Ricky"}}}}}}}));
        });
        startLive();
        QTRY_COMPARE(rig->store.dashboards().size(), 1);
        const QVariantList widgets = rig->store.dashboards().first().toMap().value("widgets").toList();
        QCOMPARE(widgets.size(), 5); // nothing dropped
        QVERIFY(!widgets.at(1).toMap().value("known").toBool());
        QCOMPARE(widgets.at(1).toMap().value("label").toString(), QStringLiteral("From a newer agent"));
        for (int columns : {2, 4, 6}) {
            const QVariantList layout = rig->store.boardLayout(0, columns);
            checkPacked(layout, columns, widgets);
            for (const QVariant &v : layout)
                QVERIFY(!v.toMap().value("indexes").toList().contains(1));
        }
        // On six: the hero, the list grown into the room beside it, the
        // statuses' strip under both.
        const QVariantList layout = rig->store.boardLayout(0, 6);
        QCOMPARE(layout.size(), 3);
        const QVariantMap health = layout.at(2).toMap();
        QCOMPARE(health.value("kind").toString(), QStringLiteral("health"));
        QCOMPARE(health.value("indexes").toList(), (QVariantList{2, 3}));
        QCOMPARE(health.value("row").toInt(), 2);
        QCOMPARE(health.value("summary").toString(), QStringLiteral("All OK"));
        QCOMPARE(health.value("state").toString(), QStringLiteral("ok"));
    }

    // Many statuses don't squeeze into one row: the strip wraps into rows
    // of even length, a row for each, and the board still has no holes.
    void aLongHealthStripWraps()
    {
        const QDateTime now = QDateTime::currentDateTime();
        m_server.route("/rest/v1/dashboards", [now](const Request &) {
            QJsonArray widgets{QJsonObject{{"type", "metric"}, {"label", "Requests"}, {"value", 1}}};
            for (const char *name : {"API", "Web", "DB", "Cache", "Queue", "Search", "Mail"})
                widgets.append(QJsonObject{{"type", "status"}, {"label", name}, {"state", "ok"}});
            widgets.append(QJsonObject{{"type", "list"}, {"title", "On call"}, {"items", QJsonArray{"Ricky"}}});
            return json(rows({QJsonObject{{"id", "d1"}, {"agent_id", "a2"}, {"key", "ops"}, {"title", "Ops"}, {"sort_order", 0}, {"hidden", false},
                                          {"updated_at", iso(now)}, {"widgets", widgets}}}));
        });
        startLive();
        QTRY_COMPARE(rig->store.dashboards().size(), 1);
        const QVariantList widgets = rig->store.dashboards().first().toMap().value("widgets").toList();
        // columns → rows of the strip, statuses in each row
        for (const auto &[columns, lines, perRow] : {std::tuple{2, 3, 3}, std::tuple{4, 2, 4}, std::tuple{6, 2, 4}}) {
            const QVariantList layout = rig->store.boardLayout(0, columns);
            checkPacked(layout, columns, widgets);
            QVariantMap health;
            for (const QVariant &v : layout)
                if (v.toMap().value("kind").toString() == QLatin1String("health"))
                    health = v.toMap();
            QCOMPARE(health.value("indexes").toList().size(), 7);
            QCOMPARE(health.value("colSpan").toInt(), columns);
            QCOMPARE(health.value("rowSpan").toInt(), lines);
            QCOMPARE(health.value("perRow").toInt(), perRow);
        }

        // The demo's three fit one row at any width.
        startDemoAt(QTime(12, 0));
        for (int columns : {2, 4, 6}) {
            const QVariantMap health = rig->store.boardLayout(0, columns).at(0).toMap();
            QCOMPARE(health.value("kind").toString(), QStringLiteral("health"));
            QCOMPARE(health.value("rowSpan").toInt(), 1);
            QCOMPARE(health.value("perRow").toInt(), 3);
        }
    }

    void timelineSitsOnADayDial()
    {
        startDemoAt(QTime(12, 0));
        QCOMPARE(rig->store.nowAngle(), 180.0);
        bool sawStandup = false, sawDinner = false, sawNews = false;
        for (const QVariant &v : rig->store.timeline()) {
            const QVariantMap item = v.toMap();
            const QDateTime start = QDateTime::fromMSecsSinceEpoch(item.value("startMs").toLongLong());
            if (item.value("allDay").toBool())
                QCOMPARE(item.value("sweep").toDouble(), 360.0);
            else
                QCOMPARE(item.value("startAngle").toDouble(), start.time().msecsSinceStartOfDay() / 240000.0);
            QVERIFY(item.value("sweep").toDouble() >= 0 && item.value("startAngle").toDouble() + item.value("sweep").toDouble() <= 360);
            const QString title = item.value("title").toString();
            if (title == QLatin1String("Standup")) {
                sawStandup = true;
                QCOMPARE(item.value("startAngle").toDouble(), 142.5); // 9:30
                QCOMPARE(item.value("sweep").toDouble(), 3.75);       // 15 minutes
            } else if (title == QLatin1String("Dinner with Lina")) {
                sawDinner = true;
                QCOMPARE(item.value("startAngle").toDouble(), 285.0);
                QCOMPARE(item.value("sweep").toDouble(), 30.0);
            } else if (item.value("kind").toString() == QLatin1String("news")) {
                sawNews = true;
                QCOMPARE(item.value("sweep").toDouble(), 0.0); // a moment
            }
        }
        QVERIFY(sawStandup && sawDinner && sawNews);

        // All day goes round; a late event is cut at midnight.
        const QDate today = QDate::currentDate();
        m_server.route("/rest/v1/events", [today](const Request &) {
            return json(rows({
                QJsonObject{{"id", "e1"}, {"agent_id", "a1"}, {"calendar", "Home"}, {"title", "Holiday"}, {"location", QJsonValue::Null},
                            {"starts_at", iso(QDateTime(today, QTime(0, 0)))}, {"ends_at", iso(QDateTime(today, QTime(23, 59, 59)))},
                            {"all_day", true}, {"color", "#F6B94A"}},
                QJsonObject{{"id", "e2"}, {"agent_id", "a1"}, {"calendar", "Work"}, {"title", "Late deploy"}, {"location", QJsonValue::Null},
                            {"starts_at", iso(QDateTime(today, QTime(23, 0)))}, {"ends_at", iso(QDateTime(today.addDays(1), QTime(1, 0)))},
                            {"all_day", false}, {"color", "#5B7CF5"}},
            }));
        });
        startLive();
        auto find = [this](const QString &title) {
            for (const QVariant &v : rig->store.timeline())
                if (v.toMap().value("title").toString() == title)
                    return v.toMap();
            return QVariantMap();
        };
        QTRY_VERIFY(!find(QStringLiteral("Late deploy")).isEmpty());
        QCOMPARE(find(QStringLiteral("Holiday")).value("startAngle").toDouble(), 0.0);
        QCOMPARE(find(QStringLiteral("Holiday")).value("sweep").toDouble(), 360.0);
        QCOMPARE(find(QStringLiteral("Late deploy")).value("startAngle").toDouble(), 345.0);
        QCOMPARE(find(QStringLiteral("Late deploy")).value("sweep").toDouble(), 15.0);
    }

private:
    QDateTime m_fake;

    // A demo store on a fixed clock: today at `time`.
    void startDemoAt(const QTime &time)
    {
        QSettings().clear();
        m_fake = QDateTime(QDate::currentDate(), time);
        rig = std::make_unique<Rig>(QUrl(), true);
        rig->store.setClock([this]() { return m_fake; });
        rig->store.start();
    }

    // The icons Icon.qml can draw.
    static QStringList iconNames()
    {
        QFile file(QFINDTESTDATA("../qml/components/Icon.qml"));
        if (!file.open(QIODevice::ReadOnly))
            return {};
        static const QRegularExpression name(QStringLiteral("^\\s+\"([a-z-]+)\":\\s+\""), QRegularExpression::MultilineOption);
        QStringList out;
        for (auto it = name.globalMatch(QString::fromUtf8(file.readAll())); it.hasNext();)
            out << it.next().captured(1);
        return out;
    }

    // Every cell of the grid, up to its last row, covered by exactly one
    // entry; every drawable widget in exactly one entry.
    static void checkPacked(const QVariantList &layout, int columns, const QVariantList &widgets)
    {
        int rows = 0;
        for (const QVariant &v : layout)
            rows = qMax(rows, v.toMap().value("row").toInt() + v.toMap().value("rowSpan").toInt());
        QList<int> cover(rows * columns, 0);
        QList<int> seen(widgets.size(), 0);
        for (const QVariant &v : layout) {
            const QVariantMap e = v.toMap();
            const int row = e.value("row").toInt(), col = e.value("col").toInt();
            const int colSpan = e.value("colSpan").toInt(), rowSpan = e.value("rowSpan").toInt();
            QVERIFY(colSpan >= 1 && rowSpan >= 1 && col >= 0 && col + colSpan <= columns);
            QCOMPARE(e.value("index").toInt(), e.value("indexes").toList().first().toInt());
            for (int y = row; y < row + rowSpan; ++y)
                for (int x = col; x < col + colSpan; ++x)
                    ++cover[y * columns + x];
            for (const QVariant &i : e.value("indexes").toList())
                ++seen[i.toInt()];
        }
        for (int i = 0; i < cover.size(); ++i)
            QVERIFY2(cover.at(i) == 1, qPrintable(QStringLiteral("cell %1,%2 covered %3 times at %4 columns").arg(i / columns).arg(i % columns).arg(cover.at(i)).arg(columns)));
        for (int i = 0; i < widgets.size(); ++i)
            QCOMPARE(seen.at(i), widgets.at(i).toMap().value("known").toBool() ? 1 : 0);
    }
};

QTEST_GUILESS_MAIN(TestFeedStore)
#include "tst_feedstore.moc"
