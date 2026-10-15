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
};

QTEST_GUILESS_MAIN(TestAssistant)
#include "tst_assistant.moc"
