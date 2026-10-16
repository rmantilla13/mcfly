#include <QtTest>

#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkProxy>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QTimer>
#include <QWebSocket>
#include <QWebSocketServer>

#include "backend/SupabaseClient.h"
#include "models/Assistant.h"
#include "models/FeedStore.h"
#include "voice/VoiceClient.h"

// Stands in for DisplayController: the theme reads the mood and dark mode,
// the voice glow whether the screen is idle and Settings → Animated tiles.
class FakeDevice : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString mood READ mood CONSTANT)
    Q_PROPERTY(bool darkMode READ darkMode CONSTANT)
    Q_PROPERTY(bool idle READ idle CONSTANT)
    Q_PROPERTY(bool animatedTiles READ animatedTiles CONSTANT)
public:
    QString mood() const { return QStringLiteral("day"); }
    bool darkMode() const { return false; }
    bool idle() const { return false; }
    bool animatedTiles() const { return true; }
};

// The wake-word card (QuickAnswer.qml) driven the way Main.qml drives it,
// with the real assistant (demo answers) and voice client, against an
// in-process voice service that records what the display asks it to say.
class TestQuickAnswer : public QObject
{
    Q_OBJECT

    QWebSocketServer *m_server = nullptr;
    QPointer<QWebSocket> m_peer;
    QList<QJsonObject> m_received;
    // What the next `listen` turns hear, in order; "" (nothing heard) once
    // they run out. And how long a reply takes to say.
    QStringList m_heard;
    int m_speakMs = 0;
    bool m_reportSpeaking = true; // send "state": "speaking" while saying it, as the service does
    QString m_speaking;           // the id being "said"

    SupabaseClient *m_client = nullptr;
    FeedStore *m_store = nullptr;
    VoiceClient *m_voice = nullptr;
    Assistant *m_ai = nullptr;
    FakeDevice m_device;
    QQmlEngine *m_engine = nullptr;
    QObject *m_quick = nullptr;

    QString phase() const { return m_quick->property("phase").toString(); }
    void call(const char *function, const QVariant &arg = {})
    {
        if (arg.isValid())
            QVERIFY(QMetaObject::invokeMethod(m_quick, function, Q_ARG(QVariant, arg)));
        else
            QVERIFY(QMetaObject::invokeMethod(m_quick, function));
    }
    QStringList spokenTexts() const
    {
        QStringList out;
        for (const QJsonObject &m : m_received)
            if (m.value("type").toString() == "speak")
                out << m.value("text").toString();
        return out;
    }
    int listens() const
    {
        int n = 0;
        for (const QJsonObject &m : m_received)
            n += m.value("type").toString() == "listen" ? 1 : 0;
        return n;
    }
    void sendToDisplay(const QJsonObject &m)
    {
        if (m_peer)
            m_peer->sendTextMessage(QString::fromUtf8(QJsonDocument(m).toJson(QJsonDocument::Compact)));
    }
    void finishSpeech(const QString &id)
    {
        if (id.isEmpty() || id != m_speaking)
            return;
        m_speaking.clear();
        sendToDisplay({{"type", "spoken"}, {"id", id}});
        if (m_reportSpeaking)
            sendToDisplay({{"type", "state"}, {"state", "idle"}});
    }

private slots:
    void initTestCase()
    {
        QCoreApplication::setOrganizationName("McFly-tests");
        QCoreApplication::setApplicationName("tst_quickanswer");
        QSettings().clear();
        QNetworkProxy::setApplicationProxy(QNetworkProxy::NoProxy);

        m_server = new QWebSocketServer("fake-voice", QWebSocketServer::NonSecureMode, this);
        QVERIFY(m_server->listen(QHostAddress::LocalHost));
        connect(m_server, &QWebSocketServer::newConnection, this, [this]() {
            m_peer = m_server->nextPendingConnection();
            connect(m_peer, &QWebSocket::textMessageReceived, this, [this](const QString &t) {
                const QJsonObject m = QJsonDocument::fromJson(t.toUtf8()).object();
                m_received << m;
                const QString type = m.value("type").toString();
                if (type == "speak") {
                    // "Said" after m_speakMs (at once by default).
                    m_speaking = m.value("id").toString();
                    if (m_reportSpeaking)
                        sendToDisplay({{"type", "state"}, {"state", "speaking"}});
                    QTimer::singleShot(m_speakMs, this, [this, id = m_speaking]() { finishSpeech(id); });
                } else if (type == "listen") {
                    // As the service does: cut any speech short, then one
                    // listening turn that hears the next of m_heard.
                    finishSpeech(m_speaking);
                    const QString heard = m_heard.isEmpty() ? QString() : m_heard.takeFirst();
                    sendToDisplay({{"type", "wake"}, {"source", "button"}});
                    sendToDisplay({{"type", "state"}, {"state", "listening"}});
                    QTimer::singleShot(50, this, [this, heard]() {
                        sendToDisplay({{"type", "transcript"}, {"text", heard}, {"final", true}});
                        sendToDisplay({{"type", "state"}, {"state", "idle"}});
                    });
                } else if (type == "cancel") {
                    sendToDisplay({{"type", "state"}, {"state", "idle"}});
                }
            });
            m_peer->sendTextMessage(R"({"type":"hello","version":"1","wakeword":true,"wakeword_name":"hey_jarvis","tts":true,"stt":true})");
            m_peer->sendTextMessage(R"({"type":"state","state":"idle"})");
        });

        m_client = new SupabaseClient(QUrl(), QString(), this);
        m_store = new FeedStore(m_client, true, this);
        m_store->start(); // demo mode
        m_voice = new VoiceClient(QUrl(QStringLiteral("ws://127.0.0.1:%1").arg(m_server->serverPort())), this);
        m_voice->start();
        QTRY_VERIFY(m_voice->available());
        QTRY_VERIFY(m_voice->canSpeak());
        m_ai = new Assistant(m_client, m_store, m_voice, this);

        qmlRegisterSingletonInstance("McFly.Core", 1, 0, "AI", m_ai);
        qmlRegisterSingletonInstance("McFly.Core", 1, 0, "Voice", m_voice);
        qmlRegisterSingletonInstance("McFly.Core", 1, 0, "Device", &m_device);
        m_engine = new QQmlEngine(this);
        m_engine->addImportPath(QStringLiteral(MCFLY_TEST_QML_DIR));
        QQmlComponent component(m_engine);
        // With the voice turns routed to it as Main.qml routes them.
        component.setData("import QtQuick\n"
                          "import McFly\n"
                          "import McFly.Core\n"
                          "QuickAnswer {\n"
                          "    id: quick\n"
                          "    width: 1280\n"
                          "    height: 800\n"
                          "    Connections {\n"
                          "        target: Voice\n"
                          "        function onWoke(source) {\n"
                          "            if (!(quick.followingUp && quick.phase === 'listening')) quick.start()\n"
                          "        }\n"
                          "        function onHeard(text) { if (quick.phase === 'listening') quick.hear(text) }\n"
                          "        function onHeardNothing() { if (quick.phase === 'listening') quick.miss() }\n"
                          "    }\n"
                          "}\n",
                          QUrl());
        m_quick = component.create();
        QVERIFY2(m_quick, qPrintable(component.errorString()));
        m_quick->setParent(this);
    }

    void init()
    {
        call("dismiss", false);
        m_ai->reset();
        m_voice->setFollowUp(true);
        m_quick->setProperty("maxTurns", 6);
        m_quick->setProperty("speechGraceMs", 10000);
        m_quick->setProperty("speechMsPerChar", 90);
        m_heard.clear();
        m_speakMs = 0;
        m_reportSpeaking = true;
        m_speaking.clear();
        QTest::qWait(50);
        m_received.clear();
    }

    void cleanupTestCase() { QSettings().clear(); }

    void answersAndSpeaks()
    {
        m_voice->setFollowUp(false); // the card on its own: one question, one answer
        call("start");
        QCOMPARE(phase(), QStringLiteral("listening"));
        call("hear", QStringLiteral("how are the markets"));
        QCOMPARE(phase(), QStringLiteral("thinking"));
        QTRY_COMPARE(phase(), QStringLiteral("done"));
        QTRY_COMPARE(spokenTexts(), QStringList{m_ai->replyText()});
        // Dismissed 6 s after `spoken`, not before, and the mic stays shut.
        QTest::qWait(4500);
        QCOMPARE(phase(), QStringLiteral("done"));
        QCOMPARE(listens(), 0);
        QTRY_COMPARE_WITH_TIMEOUT(phase(), QStringLiteral("hidden"), 4000);
    }

    // ── Conversations: after an answer is read out, it listens again ──

    void listensForAFollowUp()
    {
        m_heard = {QStringLiteral("what's in the news")};
        call("start");
        call("hear", QStringLiteral("how are the markets"));
        QTRY_COMPARE(spokenTexts().size(), 1);
        // Once it's been said, the card opens the mic again by itself, after
        // the echo has had a moment to fade.
        QCOMPARE(listens(), 0);
        QTRY_COMPARE_WITH_TIMEOUT(listens(), 1, 3000);
        QVERIFY(m_quick->property("followingUp").toBool());
        QCOMPARE(m_quick->property("earlierQuestion").toString(), QStringLiteral("how are the markets"));
        // What it heard is answered and read out in turn, as part of the
        // same conversation (the assistant got the first turn as history).
        QTRY_COMPARE(spokenTexts().size(), 2);
        QVERIFY2(spokenTexts().at(1).startsWith("Top of today"), qPrintable(spokenTexts().at(1)));
        QCOMPARE(m_quick->property("turns").toInt(), 2);
        // Then nobody says anything more: no "didn't catch that", just gone.
        QTRY_COMPARE_WITH_TIMEOUT(listens(), 2, 3000);
        QTRY_COMPARE(phase(), QStringLiteral("hidden"));
        QCOMPARE(spokenTexts().size(), 2);
    }

    void thanksEndsTheConversation()
    {
        m_heard = {QStringLiteral("Okay, thanks McFly.")};
        call("start");
        call("hear", QStringLiteral("how are the markets"));
        QTRY_COMPARE_WITH_TIMEOUT(listens(), 1, 4000);
        QTRY_COMPARE(phase(), QStringLiteral("hidden"));
        QCOMPARE(spokenTexts().size(), 1);           // nothing more said
        QCOMPARE(m_ai->messages()->rowCount(), 2);  // and nothing more asked
        QCOMPARE(listens(), 1);
    }

    void hearingItselfEndsIt()
    {
        call("start");
        call("hear", QStringLiteral("how are the markets"));
        QTRY_COMPARE(spokenTexts().size(), 1);
        // The mic catches the end of the answer, still echoing in the room.
        const QStringList words = spokenTexts().first().split(QLatin1Char(' '), Qt::SkipEmptyParts);
        m_heard = {words.mid(words.size() - 4).join(QLatin1Char(' '))};
        QTRY_COMPARE_WITH_TIMEOUT(listens(), 1, 4000);
        QTRY_COMPARE(phase(), QStringLiteral("hidden"));
        QCOMPARE(spokenTexts().size(), 1);
        QCOMPARE(m_ai->messages()->rowCount(), 2);
    }

    void stopsAfterEnoughTurns()
    {
        m_quick->setProperty("maxTurns", 1);
        call("start");
        call("hear", QStringLiteral("how are the markets"));
        QTRY_COMPARE(spokenTexts().size(), 1);
        QTest::qWait(1500);
        QCOMPARE(listens(), 0);
        QCOMPARE(phase(), QStringLiteral("done")); // closes 6 s after, as without follow-ups
    }

    void aSlowAnswerStillGetsAFollowUp()
    {
        // Kokoro on the Pi speaks slower than real time, so an answer can
        // outlast the card's guess at how long saying it takes. While the
        // service says it's still speaking, the card keeps waiting, and then
        // listens for the follow-up as usual.
        m_quick->setProperty("speechGraceMs", 300);
        m_quick->setProperty("speechMsPerChar", 0);
        m_speakMs = 1500;
        call("start");
        call("hear", QStringLiteral("how are the markets"));
        QTRY_COMPARE(spokenTexts().size(), 1);
        QTest::qWait(800); // past the guess, still being said
        QCOMPARE(phase(), QStringLiteral("done"));
        QCOMPARE(listens(), 0);
        QTRY_COMPARE_WITH_TIMEOUT(listens(), 1, 4000);
        QTRY_COMPARE(phase(), QStringLiteral("hidden")); // that follow-up heard nothing
    }

    void aLateSpokenStillFollowsUp()
    {
        // A service that never reports "speaking": the card stops waiting on
        // its guess, but a `spoken` that comes while it's still up opens the
        // follow-up all the same.
        m_reportSpeaking = false;
        m_quick->setProperty("speechGraceMs", 300);
        m_quick->setProperty("speechMsPerChar", 0);
        m_speakMs = 1500;
        call("start");
        call("hear", QStringLiteral("how are the markets"));
        QTRY_COMPARE(spokenTexts().size(), 1);
        QTRY_COMPARE_WITH_TIMEOUT(listens(), 1, 4000);
        QTRY_COMPARE(phase(), QStringLiteral("hidden"));
    }

    void twoFollowUpsInARow()
    {
        // The conversation keeps going: each answer is followed by another
        // turn, until nothing more is said.
        m_heard = {QStringLiteral("what's in the news"), QStringLiteral("what's blocking Onyx?")};
        call("start");
        call("hear", QStringLiteral("how are the markets"));
        QTRY_COMPARE_WITH_TIMEOUT(spokenTexts().size(), 3, 15000);
        QCOMPARE(m_quick->property("turns").toInt(), 3);
        QTRY_COMPARE_WITH_TIMEOUT(listens(), 3, 3000);
        QTRY_COMPARE(phase(), QStringLiteral("hidden"));
    }

    void tappingCutsIn()
    {
        m_speakMs = 5000; // a long answer, still being read
        call("start");
        call("hear", QStringLiteral("how are the markets"));
        QTRY_COMPARE(spokenTexts().size(), 1);
        QCOMPARE(phase(), QStringLiteral("done"));
        // A tap on the card: McFly stops talking and listens.
        call("followUp");
        QCOMPARE(phase(), QStringLiteral("listening"));
        QTRY_COMPARE(listens(), 1);
        // The cut-short reply's `spoken` doesn't start another follow-up, and
        // the turn hears nothing: the conversation ends.
        QTRY_COMPARE(phase(), QStringLiteral("hidden"));
        QTest::qWait(1200);
        QCOMPARE(listens(), 1);
    }

    void nothingHeard()
    {
        call("start");
        call("miss");
        QCOMPARE(phase(), QStringLiteral("missed"));
        QTRY_COMPARE_WITH_TIMEOUT(phase(), QStringLiteral("hidden"), 4000);
    }

    void dismissWhileThinkingStopsTheAnswer()
    {
        // Tapping outside dismisses the card and stops speech: the answer
        // still on its way must not be read out a moment later.
        call("start");
        call("hear", QStringLiteral("how are the markets"));
        QVERIFY(m_ai->busy());
        call("dismiss", true);
        QCOMPARE(phase(), QStringLiteral("hidden"));
        QTest::qWait(1500); // a demo answer takes about one second
        QVERIFY(!m_ai->busy());
        QCOMPARE(spokenTexts(), QStringList());
    }

    void secondWakeDropsTheEarlierAnswer()
    {
        call("start");
        call("hear", QStringLiteral("how are the markets"));
        call("start"); // the wake word again while the first answer is coming
        QTest::qWait(1500);
        QCOMPARE(phase(), QStringLiteral("listening"));
        QCOMPARE(spokenTexts(), QStringList()); // not read out over the new question
        call("hear", QStringLiteral("what's in the news"));
        QTRY_COMPARE(phase(), QStringLiteral("done"));
        QTRY_COMPARE(spokenTexts().size(), 1);
        QVERIFY2(spokenTexts().first().startsWith("Top of today"),
                 qPrintable(spokenTexts().first()));
    }

    void newQuestionWhileOldAnswerStreams()
    {
        // The second question is heard before the first answer arrived: the
        // card shows "Thinking…" for the new one, not the old turn's ending.
        call("start");
        call("hear", QStringLiteral("how are the markets"));
        call("start");
        call("hear", QStringLiteral("what's in the news"));
        QCOMPARE(phase(), QStringLiteral("thinking"));
        QCOMPARE(m_quick->property("stateLabel").toString(), QStringLiteral("Thinking…"));
        QTRY_COMPARE(phase(), QStringLiteral("done"));
        QTRY_COMPARE(spokenTexts().size(), 1);
    }
};

QTEST_MAIN(TestQuickAnswer)
#include "tst_quickanswer.moc"
