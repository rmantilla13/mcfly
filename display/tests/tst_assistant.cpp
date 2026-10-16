#include <QtTest>

#include <QJsonArray>
#include <QNetworkProxy>
#include <QSettings>

#include "FakeServer.h"
#include "backend/SupabaseClient.h"
#include "models/Assistant.h"
#include "models/FeedStore.h"

// The assistant in live mode against a stand-in for the `assistant`
// function (SSE), and its demo answers.
class TestAssistant : public QObject
{
    Q_OBJECT

    FakeServer m_server;
    using Request = FakeServer::Request;
    using Reply = FakeServer::Reply;

    static QByteArray event(const char *name, const QJsonObject &data)
    {
        return QByteArray("event: ") + name + "\ndata: " + QJsonDocument(data).toJson(QJsonDocument::Compact) + "\n\n";
    }
    static Reply stream(const QList<QByteArray> &events, int delayMs = 0)
    {
        QByteArray body;
        for (const QByteArray &e : events)
            body += e;
        return {200, "text/event-stream", body, delayMs};
    }
    static Reply okStream(const QString &reply)
    {
        return stream({event("delta", {{"text", reply.left(4)}}), event("delta", {{"text", reply.mid(4)}}), event("done", {{"reply", reply}})});
    }

    struct Rig
    {
        SupabaseClient client;
        FeedStore store;
        Assistant ai;
        Rig(const QUrl &url, bool demo) : client(url, QStringLiteral("anon-key")), store(&client, demo), ai(&client, &store, nullptr) {}
    };
    std::unique_ptr<Rig> rig;

    void startLive()
    {
        QSettings().clear();
        m_server.route("/auth/v1/token", [](const Request &) {
            return FakeServer::json(R"({"access_token":"access-1","refresh_token":"refresh-2"})");
        });
        rig = std::make_unique<Rig>(m_server.baseUrl(), false);
        rig->client.setRefreshToken("refresh-1");
        rig->store.start();
        QTRY_VERIFY_WITH_TIMEOUT(rig->store.online(), 5000);
    }
    QString lastReply() const { return rig->ai.messages()->at(rig->ai.messages()->count() - 1).text; }
    QList<Request> asks() const { return m_server.requests("POST", "/functions/v1/assistant"); }

private slots:
    void initTestCase()
    {
        QCoreApplication::setOrganizationName("McFly-tests");
        QCoreApplication::setApplicationName("tst_assistant");
        QNetworkProxy::setApplicationProxy(QNetworkProxy::NoProxy);
        QVERIFY(m_server.listen());
    }
    void init() { m_server.reset(); }
    void cleanup() { rig.reset(); }
    void cleanupTestCase() { QSettings().clear(); }

    void streamsAReplyWithTheHistory()
    {
        startLive();
        m_server.route("/functions/v1/assistant", [](const Request &r) {
            return okStream(r.body.value("mode").toString() == "quick" ? "Quick answer." : "Long answer here.");
        });
        QSignalSpy finished(&rig->ai, &Assistant::replyFinished);
        rig->ai.ask("How are the markets?");
        QVERIFY(rig->ai.busy());
        QTRY_VERIFY(!rig->ai.busy());
        QCOMPARE(rig->ai.replyText(), QStringLiteral("Long answer here."));
        QCOMPARE(lastReply(), QStringLiteral("Long answer here."));
        QCOMPARE(finished.count(), 1);
        QCOMPARE(finished.first().at(1).toString(), QStringLiteral("chat"));
        QCOMPARE(finished.first().at(2).toString(), QString()); // nothing read out: no voice

        const Request first = asks().first();
        QCOMPARE(first.auth, QByteArray("Bearer access-1"));
        QCOMPARE(first.body.value("message").toString(), QStringLiteral("How are the markets?"));
        QCOMPARE(first.body.value("stream").toBool(), true);
        QCOMPARE(first.body.value("history").toArray().size(), 0);
        QVERIFY(!first.body.contains("thread_id"));

        // The next question carries the earlier turns.
        rig->ai.askQuick("And Apple?");
        QTRY_VERIFY(!rig->ai.busy());
        QCOMPARE(rig->ai.replyText(), QStringLiteral("Quick answer."));
        const QJsonArray history = asks().last().body.value("history").toArray();
        QCOMPARE(history.size(), 2);
        QCOMPARE(history.at(0).toObject().value("role").toString(), QStringLiteral("user"));
        QCOMPARE(history.at(1).toObject().value("text").toString(), QStringLiteral("Long answer here."));
        QCOMPARE(rig->ai.messages()->count(), 4);

        rig->ai.reset();
        QCOMPARE(rig->ai.messages()->count(), 0);
        QCOMPARE(rig->ai.replyText(), QString());
    }

    // When the assistant added to the day (or checked a todo off), `done`
    // says so, and the feeds are read again at once rather than in a minute.
    void aChangeRefreshesTheFeeds()
    {
        startLive();
        const auto syncs = [this]() { return m_server.requests("GET", "/rest/v1/events").size(); };
        QTRY_VERIFY(syncs() >= 1);
        const int before = syncs();
        m_server.route("/functions/v1/assistant", [](const Request &r) {
            const bool adds = r.body.value("message").toString().startsWith("Add");
            QJsonObject done{{"reply", adds ? "Added." : "Nothing to add."}};
            if (adds)
                done.insert("changed", QJsonArray{"events"});
            return stream({event("done", done)});
        });
        rig->ai.askQuick("What's next?");
        QTRY_VERIFY(!rig->ai.busy());
        QTest::qWait(300);
        QCOMPARE(syncs(), before); // a plain answer leaves the feeds alone
        rig->ai.askQuick("Add the dentist tomorrow at 3");
        QTRY_VERIFY(!rig->ai.busy());
        QCOMPARE(rig->ai.replyText(), QStringLiteral("Added."));
        QTRY_COMPARE(syncs(), before + 1);
    }

    void anErrorEventKeepsThePartialAnswer()
    {
        startLive();
        m_server.route("/functions/v1/assistant", [](const Request &) {
            return stream({event("delta", {{"text", "Half an "}}), event("error", {{"message", "model went away"}})});
        });
        rig->ai.ask("Hi");
        QTRY_VERIFY(!rig->ai.busy());
        QCOMPARE(lastReply(), QStringLiteral("Half an "));
        QVERIFY(rig->ai.messages()->at(1).failed);
    }

    void anExpiredTokenIsRefreshedOnce()
    {
        startLive();
        int calls = 0;
        m_server.route("/functions/v1/assistant", [&calls](const Request &) {
            if (++calls == 1)
                return FakeServer::json("{\"error\":\"expired\"}", 401);
            return okStream("After refresh.");
        });
        rig->ai.ask("Hi");
        QTRY_VERIFY(!rig->ai.busy());
        QCOMPARE(lastReply(), QStringLiteral("After refresh."));
        QCOMPARE(asks().size(), 2);
        QCOMPARE(m_server.requests("POST", "/auth/v1/token").size(), 2);
    }

    void statusesBecomeSentences()
    {
        startLive();
        m_server.route("/functions/v1/assistant", [](const Request &) { return FakeServer::json("{\"error\":\"no\"}", 403); });
        rig->ai.ask("Hi");
        QTRY_VERIFY(!rig->ai.busy());
        QVERIFY2(lastReply().contains("isn't available"), qPrintable(lastReply()));
        m_server.route("/functions/v1/assistant", [](const Request &) { return FakeServer::json("{\"error\":\"busy\"}", 503); });
        rig->ai.ask("Hi again");
        QTRY_VERIFY(!rig->ai.busy());
        QVERIFY2(lastReply().contains("busy"), qPrintable(lastReply()));
    }

    void stopKeepsWhatArrived()
    {
        startLive();
        m_server.route("/functions/v1/assistant", [](const Request &) {
            return stream({event("delta", {{"text", "Partial"}})}, 200); // never finishes within the test
        });
        rig->ai.ask("Hi");
        QTRY_COMPARE(rig->ai.replyText(), QStringLiteral("Partial"));
        rig->ai.stop();
        QVERIFY(!rig->ai.busy());
        QCOMPARE(lastReply(), QStringLiteral("Partial"));
    }

    void demoAnswersFromTheFeed()
    {
        QSettings().clear();
        rig = std::make_unique<Rig>(QUrl(), true);
        rig->store.start();
        const QString markets = rig->ai.demoAnswer("how are the markets");
        QVERIFY2(markets.contains("SPY") && markets.contains("AAPL"), qPrintable(markets));
        const QString apple = rig->ai.demoAnswer("what's apple doing?");
        QVERIFY2(apple.startsWith("Apple is at $247.90") && apple.contains("Services beat"), qPrintable(apple));
        const QString nvda = rig->ai.demoAnswer("NVDA?");
        QVERIFY2(nvda.startsWith("NVIDIA is at"), qPrintable(nvda));
        const QString news = rig->ai.demoAnswer("what's in the news");
        QVERIFY2(news.startsWith("Top of today's Pulse"), qPrintable(news));
        const QString brief = rig->ai.demoAnswer("what's the latest brief");
        QVERIFY2(brief.startsWith("From Grok at") && brief.contains("Hourly check-in"), qPrintable(brief));
        QVERIFY(rig->ai.demoAnswer("tell me a joke").contains("demo mode"));

        // Streamed word by word, then done.
        QSignalSpy finished(&rig->ai, &Assistant::replyFinished);
        rig->ai.askQuick("how are the markets");
        QVERIFY(rig->ai.busy());
        QTRY_VERIFY_WITH_TIMEOUT(!rig->ai.busy(), 10000);
        QCOMPARE(rig->ai.replyText(), markets);
        QCOMPARE(finished.count(), 1);
        QCOMPARE(finished.first().at(1).toString(), QStringLiteral("quick"));
    }

    // ── Suggestions from the feed, per screen, and answers to all of them ──

    void suggestionsFollowTheFeed()
    {
        // Noon: Onyx is blocked, TSLA is the big mover, the Pulse has a lead,
        // Grok's hourly brief is 24 minutes old.
        startDemoAt(QTime(12, 0));
        QCOMPARE(rig->ai.suggestions(), (QStringList{"What's blocking Onyx?", "Why is TSLA up 4.0% today?",
                                                     "More on Google launches Gemini 4 Argon", "What did Grok just say?"}));
        // 3:10 pm: the 3:30 meeting comes into the window (its title cut to
        // fit a chip). A tenth of a second before the minute, so the store's
        // minute tick comes at once.
        startDemoAt(QTime(15, 10, 59, 900));
        QCOMPARE(rig->ai.suggestions(), (QStringList{"What's blocking Onyx?", "Why is TSLA up 4.0% today?",
                                                     "What do I need for Pulse review with the…?", "More on Google launches Gemini 4 Argon"}));
        for (const QString &s : rig->ai.suggestions())
            QVERIFY2(s.size() <= 42, qPrintable(s));

        // And they move with the clock, not only with a sync: at 4:01 the meeting has gone.
        QSignalSpy changed(&rig->ai, &Assistant::suggestionsChanged);
        m_fake = QDateTime(m_fake.date(), QTime(16, 1, 59, 900));
        QTRY_VERIFY_WITH_TIMEOUT(changed.count() == 1, 3000);
        QVERIFY(!rig->ai.suggestions().join("|").contains("Pulse review"));
        // A tick that changes nothing they show leaves them be.
        QTest::qWait(400);
        QCOMPARE(changed.count(), 1);

        // Nothing synced yet: the questions that fit any day.
        QSettings().clear();
        rig = std::make_unique<Rig>(m_server.baseUrl(), false); // configured, unpaired, no data
        QCOMPARE(rig->ai.suggestions(), (QStringList{"Summarize my day", "Anything I should know?"}));
    }

    void suggestionsForEachScreen()
    {
        startDemoAt(QTime(12, 0));
        const QHash<QString, QString> own{
            {"home", "Summarize my day"},
            {"briefs", "What did Grok just say?"},
            {"markets", "Why is TSLA up 4.0% today?"},
            {"metrics", "What's behind the drop in Error rate?"},
            {"news", "More on Google launches Gemini 4 Argon"},
            {"projects", "What's blocking Onyx?"},
            {"boards", "Why is Search down?"},
            {"calendar", "Prep me for Pulse review with the team"},
        };
        for (auto it = own.cbegin(); it != own.cend(); ++it) {
            const QStringList list = rig->ai.suggestionsFor(it.key());
            QCOMPARE(list.first(), it.value());
            QVERIFY(list.size() <= 4);
            QCOMPARE(QSet<QString>(list.cbegin(), list.cend()).size(), list.size());
            for (const QString &s : list)
                QVERIFY2(s.size() <= 42, qPrintable(s));
        }
        QCOMPARE(rig->ai.suggestionsFor("ask"), rig->ai.suggestions());
    }

    // A screen's own question follows what stands out even when the general
    // four don't move: Search recovering takes "Why is Search down?" off the
    // Boards chips, and the bindings (which follow suggestionsChanged) hear it.
    void screenChipsFollowTheHighlights()
    {
        auto state = std::make_shared<QString>(QStringLiteral("down"));
        m_server.route("/rest/v1/dashboards", [state](const Request &) {
            const QJsonObject board{{"id", "d1"}, {"agent_id", "a1"}, {"key", "ops"}, {"title", "Ops"}, {"sort_order", 0}, {"hidden", false},
                                    {"updated_at", QDateTime::currentDateTimeUtc().toString(Qt::ISODate)},
                                    {"widgets", QJsonArray{QJsonObject{{"type", "status"}, {"label", "Search"}, {"state", *state}, {"detail", "Index rebuilding"}}}}};
            return FakeServer::json(QJsonDocument(QJsonArray{board}));
        });
        startLive();
        QTRY_COMPARE(rig->ai.suggestionsFor("boards").value(0), QStringLiteral("Why is Search down?"));
        QTRY_COMPARE(m_server.pending(), 0);
        const QStringList general = rig->ai.suggestions();
        QSignalSpy changed(&rig->ai, &Assistant::suggestionsChanged);
        *state = QStringLiteral("ok");
        rig->store.refresh();
        QTRY_COMPARE(rig->ai.suggestionsFor("boards").value(0), QStringLiteral("How's Ops looking?"));
        QCOMPARE(rig->ai.suggestions(), general);
        QCOMPARE(changed.count(), 1);
    }

    void demoAnswersWhatItOffers()
    {
        // Every question the display offers (chips, each screen's, the
        // highlights') gets a real answer, morning to evening.
        for (const QTime &time : {QTime(9, 20), QTime(12, 0), QTime(15, 10), QTime(20, 30)}) {
            startDemoAt(time);
            QStringList questions = rig->ai.suggestions();
            for (const QString &screen : {"home", "briefs", "markets", "metrics", "news", "projects", "boards", "calendar"})
                questions << rig->ai.suggestionsFor(screen);
            for (const QVariant &v : rig->store.highlights())
                questions << v.toMap().value("question").toString();
            questions.removeDuplicates();
            for (const QString &q : std::as_const(questions)) {
                const QString answer = rig->ai.demoAnswer(q);
                QVERIFY2(!answer.isEmpty() && !answer.contains("demo mode"), qPrintable(time.toString() + " " + q + " → " + answer));
            }
        }

        startDemoAt(QTime(12, 0));
        auto answer = [this](const char *q) { return rig->ai.demoAnswer(QString::fromUtf8(q)); };
        // (The update is 20 hours back: its hour moves on a DST day, so only up to the day.)
        const QString onyx = answer("What's blocking Onyx?");
        QVERIFY2(onyx.startsWith("Onyx is blocked. What it needs next: App Review's answer on the FSKit entitlement. The last update, yesterday")
                     && onyx.endsWith(": App Review: waiting on the FSKit entitlement."),
                 qPrintable(onyx));
        const QString tsla = answer("Why is TSLA up 4.0% today?");
        QVERIFY2(tsla.startsWith("Tesla is up 3.96% today, at $402.10. Deliveries ahead of consensus. That's 4.8× its usual daily move.")
                     && tsla.contains("top of its recent range ($368.40–$402.10)"),
                 qPrintable(tsla));
        const QString prep = answer("Prep me for Pulse review with the team");
        QVERIFY2(prep.startsWith("Pulse review with the team is today, ") && prep.contains(", at Zoom. It's on your Work calendar.")
                     && prep.contains("Daily Pulse pipeline is active; next: Push to McFly after each run.")
                     && prep.endsWith("From Grok's Morning briefing: The Pulse pipeline ran at 8:06 and found 11 sourced stories."),
                 qPrintable(prep));
        // A chip's cut-short title still finds the event.
        QVERIFY(answer("What do I need for Pulse review with the…?").startsWith("Pulse review with the team is today"));
        const QString day = answer("Summarize my day");
        QVERIFY2(day.startsWith("2 more things on the calendar today; next is Pulse review with the team at ")
                     && day.contains("Standing out: Onyx is blocked; Search is down; Error rate is down 30.0%.")
                     && day.contains("Markets: 4 up · 2 down.") && day.endsWith("Latest from Grok: Hourly check-in."),
                 qPrintable(day));
        QCOMPARE(answer("Why is Search down?"), QStringLiteral("Search is down on the Ops board: Index rebuilding since 3:10."));
        QCOMPARE(answer("What's wrong with Workers?"), QStringLiteral("Workers has a warning on the Ops board: 1 of 4 behind."));
        QVERIFY(answer("How's Ops looking?").startsWith("Ops: API is OK, Workers has a warning, Search is down; Requests 1.2M (+4.2%)"));
        QCOMPARE(answer("What's behind the drop in Error rate?"),
                 QStringLiteral("Error rate is 0.12%, −30.0% since the last reading. That's well off its usual of about 0.18%. "
                                "That's the good direction for it."));
        QCOMPARE(answer("How's Steps?"), QStringLiteral("Steps is 6,420, −8.0% since the last reading. Its usual is about 7,450. "
                                                        "That's the wrong direction for it."));
        QVERIFY(answer("More on Google launches Gemini 4 Argon").startsWith("Google launches Gemini 4 Argon. A stronger model in Search"));
        QVERIFY(answer("Tell me more about “Google launches Gemini 4 Argon”").startsWith("Google launches Gemini 4 Argon."));
        QVERIFY(answer("What did Grok just say?").startsWith("From Grok at"));
        QVERIFY(answer("What did Market desk just say?").contains("TSLA up 4% on deliveries"));
        QVERIFY(answer("Anything I should know?").startsWith("Here's what stands out: Onyx is blocked; Search is down;"));
        QVERIFY(answer("What's next on my calendar?").startsWith("Next: Pulse review with the team, today at "));
        QVERIFY(answer("How are my metrics looking?").startsWith("Your metrics: Sales today $4,280 (+12.5%);"));
        QVERIFY(answer("What's next for McFly?").startsWith("McFly is active, 62% done. Next: Ship the dashboards screen."));
        QVERIFY(answer("How are my projects going?").startsWith("Your projects: Onyx (blocked, 80%);"));
        // The topics still answer as before.
        QVERIFY(answer("what's apple doing?").startsWith("Apple is at $247.90"));
        QVERIFY(answer("what's in the news").startsWith("Top of today's Pulse"));
        QVERIFY(answer("tell me a joke").contains("demo mode"));
    }

private:
    QDateTime m_fake;

    // A demo store and assistant on a fixed clock: today at `time`.
    void startDemoAt(const QTime &time)
    {
        QSettings().clear();
        m_fake = QDateTime(QDate::currentDate(), time);
        rig = std::make_unique<Rig>(QUrl(), true);
        rig->store.setClock([this]() { return m_fake; });
        rig->store.start();
    }
};

QTEST_GUILESS_MAIN(TestAssistant)
#include "tst_assistant.moc"
