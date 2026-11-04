#include <QtTest>

#include <QJsonArray>
#include <QNetworkProxy>
#include <QSettings>
#include <QUrlQuery>
#include <memory>

#include "FakeServer.h"
#include "backend/SupabaseClient.h"
#include "models/FeedStore.h"
#include "models/MessageStore.h"

// The household thread (MessageStore) against a stand-in for Supabase: read
// once, then only what changed; a message sent from here; the person's
// replies marked read; and the demo's thread.
class TestMessages : public QObject
{
    Q_OBJECT

    FakeServer m_server;
    using Request = FakeServer::Request;
    using Reply = FakeServer::Reply;
    static Reply json(const QByteArray &body, int status = 200) { return FakeServer::json(body, status); }
    static QByteArray rows(const QJsonArray &a) { return QJsonDocument(a).toJson(QJsonDocument::Compact); }
    static QString iso(const QDateTime &t) { return t.toUTC().toString(Qt::ISODateWithMs); }

    struct Rig
    {
        SupabaseClient client;
        FeedStore store;
        MessageStore messages;
        Rig(const QUrl &url, bool demo) : client(url, QStringLiteral("anon-key")), store(&client, demo), messages(&client, &store) {}
    };
    std::unique_ptr<Rig> rig;

    // What the server holds, by id, and what it was asked.
    QHash<QString, QJsonObject> m_rows;
    QStringList m_sinceAsked;

    static QJsonObject row(const QString &id, const QString &kind, const QString &name, const QString &body, const QDateTime &at)
    {
        return {{"id", id}, {"sender_kind", kind}, {"sender_name", name}, {"body", body}, {"device_id", QJsonValue::Null},
                {"via", kind == "display" ? "display" : "app"}, {"created_at", iso(at)}, {"updated_at", iso(at)},
                {"read_at", QJsonValue::Null}, {"notified_at", QJsonValue::Null}, {"notify_error", QJsonValue::Null}};
    }

    void serve()
    {
        // A token shaped like a JWT, so the display knows its own user (its voice notes' folder).
        m_server.route("/auth/v1/token", [](const Request &) {
            const QByteArray payload = QJsonDocument(QJsonObject{{"sub", "d0000000-0000-0000-0000-000000000001"}})
                                           .toJson(QJsonDocument::Compact)
                                           .toBase64(QByteArray::Base64UrlEncoding | QByteArray::OmitTrailingEquals);
            const QJsonObject session{{"access_token", QString::fromLatin1("eyJhbGciOiJIUzI1NiJ9." + payload + ".sig")},
                                      {"refresh_token", "refresh-2"}};
            return FakeServer::json(QJsonDocument(session));
        });
        m_server.route("/rest/v1/platform_settings", [](const Request &) {
            return json(R"([{"display_name":"Hill Valley","timezone":"America/Chicago","message_names":["Mia","Leo"]}])");
        });
        m_server.route("/rest/v1/messages", [this](const Request &r) {
            const QUrlQuery q(QString::fromUtf8(r.path.mid(r.path.indexOf('?') + 1)));
            const QString since = q.queryItemValue("updated_at", QUrl::FullyDecoded);
            QJsonArray out;
            // As PostgREST: a time it can't read is a 400.
            if (q.hasQueryItem("updated_at") && !QDateTime::fromString(since.mid(3), Qt::ISODateWithMs).isValid())
                return json(R"({"message":"invalid input syntax for type timestamp with time zone"})", 400);
            if (since.startsWith("gt.")) {
                m_sinceAsked << since.mid(3);
                const QDateTime after = QDateTime::fromString(since.mid(3), Qt::ISODateWithMs);
                for (const QJsonObject &o : std::as_const(m_rows))
                    if (QDateTime::fromString(o.value("updated_at").toString(), Qt::ISODateWithMs) > after)
                        out << o;
            } else {
                for (const QJsonObject &o : std::as_const(m_rows))
                    out << o;
            }
            return json(rows(out));
        });
    }

    void startLive()
    {
        QSettings().clear();
        rig = std::make_unique<Rig>(m_server.baseUrl(), false);
        rig->client.setRefreshToken("refresh-1");
        rig->messages.setPollIntervals(150, 300);
        rig->store.start();
        QTRY_VERIFY_WITH_TIMEOUT(rig->store.mode() == QLatin1String("live"), 5000);
    }

    static QVariantMap last(const QVariantList &thread) { return thread.isEmpty() ? QVariantMap() : thread.last().toMap(); }

private slots:
    void initTestCase()
    {
        QCoreApplication::setOrganizationName("McFly-tests");
        QCoreApplication::setApplicationName("tst_messages");
        QNetworkProxy::setApplicationProxy(QNetworkProxy::NoProxy);
        QVERIFY(m_server.listen());
    }
    void init()
    {
        m_server.reset();
        m_rows.clear();
        m_sinceAsked.clear();
        serve();
    }
    void cleanup() { rig.reset(); }
    void cleanupTestCase() { QSettings().clear(); }

    void readsTheThreadThenOnlyWhatChanged()
    {
        const QDateTime now = QDateTime::currentDateTime();
        m_rows.insert("m1", row("m1", "display", "Mia", "I'm home!", now.addSecs(-600)));
        m_rows.insert("m2", row("m2", "person", "Dad", "Snack's in the fridge", now.addSecs(-300)));
        startLive();
        QSignalSpy arrived(&rig->messages, &MessageStore::arrived);
        QTRY_COMPARE(rig->messages.thread().size(), 2);
        QCOMPARE(rig->messages.unread(), 1);
        QCOMPARE(rig->messages.personName(), QStringLiteral("Dad"));
        QTRY_COMPARE(rig->messages.names(), QStringList({"Mia", "Leo"}));
        QCOMPARE(arrived.count(), 0); // nothing on the first read is news
        QCOMPARE(rig->messages.thread().first().toMap().value("home").toBool(), true);
        QCOMPARE(rig->messages.thread().first().toMap().value("status").toString(), QStringLiteral("Sent"));

        // Next: only what changed, from a little before the newest change seen.
        QTRY_VERIFY(!m_sinceAsked.isEmpty());
        const QDateTime asked = QDateTime::fromString(m_sinceAsked.first(), Qt::ISODateWithMs);
        QCOMPARE(asked.toMSecsSinceEpoch(), now.addSecs(-300).addMSecs(-30000).toMSecsSinceEpoch());

        // A reply comes, and home's message is seen on the phone.
        QJsonObject seen = m_rows.value("m1");
        seen.insert("read_at", iso(now));
        seen.insert("updated_at", iso(now));
        m_rows.insert("m1", seen);
        m_rows.insert("m3", row("m3", "person", "Dad", "On my way", now));
        QTRY_COMPARE(arrived.count(), 1);
        QCOMPARE(arrived.first().first().toMap().value("body").toString(), QStringLiteral("On my way"));
        QCOMPARE(arrived.first().first().toMap().value("name").toString(), QStringLiteral("Dad"));
        QCOMPARE(rig->messages.thread().size(), 3);
        QCOMPARE(rig->messages.unread(), 2);
        QCOMPARE(rig->messages.thread().first().toMap().value("status").toString(), QStringLiteral("Seen by Dad"));
        // Read again in the overlap: not news twice.
        QTest::qWait(700);
        QCOMPARE(arrived.count(), 1);
    }

    // The live Pi met this first: no messages at all, so no change to read
    // from. It reads the whole (empty) thread again rather than send an empty
    // time, and the person's first message is news.
    void anEmptyThreadStillHearsTheFirstMessage()
    {
        startLive();
        QSignalSpy arrived(&rig->messages, &MessageStore::arrived);
        QTRY_VERIFY(m_server.requests("GET", "/rest/v1/messages").size() >= 3);
        for (const Request &r : m_server.requests("GET", "/rest/v1/messages"))
            QVERIFY2(!r.path.contains("updated_at=gt.&") && !r.path.endsWith("updated_at=gt."), r.path.constData());
        QVERIFY(rig->messages.available());
        m_rows.insert("p1", row("p1", "person", "Dad", "Anyone home?", QDateTime::currentDateTime()));
        QTRY_COMPARE(arrived.count(), 1);
        QCOMPARE(rig->messages.thread().size(), 1);
        // From here it reads only what changed.
        QTRY_VERIFY(!m_sinceAsked.isEmpty());
    }

    void sendsAsTheWriterAndShowsItAtOnce()
    {
        startLive();
        QTRY_COMPARE(rig->messages.names().size(), 2);
        m_server.route("/rest/v1/rpc/send_message", [this](const Request &r) {
            QJsonObject o = row("s1", "display", r.body.value("sender_name").toString("Kitchen"), r.body.value("body").toString(),
                                QDateTime::currentDateTime());
            o.insert("notified_at", iso(QDateTime::currentDateTime()));
            m_rows.insert("s1", o);
            return FakeServer::json(QJsonDocument(o));
        });
        QVERIFY(!rig->messages.send("   "));
        rig->messages.setWriter("Mia");
        QVERIFY(rig->messages.send("  Can I have a snack?  "));
        // There at once, on its way.
        QCOMPARE(last(rig->messages.thread()).value("pending").toBool(), true);
        QCOMPARE(last(rig->messages.thread()).value("status").toString(), QStringLiteral("Sending…"));
        QCOMPARE(last(rig->messages.thread()).value("name").toString(), QStringLiteral("Mia"));
        QTRY_COMPARE(last(rig->messages.thread()).value("pending").toBool(), false);
        const auto sent = m_server.requests("POST", "/rest/v1/rpc/send_message");
        QCOMPARE(sent.size(), 1);
        QCOMPARE(sent.first().body.value("body").toString(), QStringLiteral("Can I have a snack?"));
        QCOMPARE(sent.first().body.value("sender_name").toString(), QStringLiteral("Mia"));
        QCOMPARE(last(rig->messages.thread()).value("status").toString(), QStringLiteral("Delivered"));
        QCOMPARE(rig->messages.thread().size(), 1);

        // Nobody picked: the server names it after the display.
        rig->messages.setWriter(QString());
        QVERIFY(rig->messages.send("From the kitchen"));
        QTRY_COMPARE(m_server.requests("POST", "/rest/v1/rpc/send_message").size(), 2);
        QVERIFY(!m_server.requests("POST", "/rest/v1/rpc/send_message").last().body.contains("sender_name"));
    }

    void aFailureStaysWithWhyAndCanBeTriedAgain()
    {
        startLive();
        m_server.route("/rest/v1/rpc/send_message", [](const Request &) {
            return json(R"({"message":"slow down: wait a minute before sending another message"})", 400);
        });
        QVERIFY(rig->messages.send("hi"));
        QTRY_COMPARE(last(rig->messages.thread()).value("failed").toBool(), true);
        QCOMPARE(last(rig->messages.thread()).value("status").toString(),
                 QStringLiteral("Didn't send: Slow down: wait a minute before sending another message"));
        m_server.route("/rest/v1/rpc/send_message", [](const Request &r) {
            return FakeServer::json(QJsonDocument(row("ok1", "display", "Kitchen", r.body.value("body").toString(), QDateTime::currentDateTime())));
        });
        rig->messages.retry(last(rig->messages.thread()).value("id").toString());
        QTRY_COMPARE(last(rig->messages.thread()).value("pending").toBool(), false);
        QCOMPARE(last(rig->messages.thread()).value("body").toString(), QStringLiteral("hi"));

        // One given up on goes.
        m_server.route("/rest/v1/rpc/send_message", [](const Request &) { return json(R"({"message":"nope"})", 400); });
        QVERIFY(rig->messages.send("again"));
        QTRY_COMPARE(last(rig->messages.thread()).value("failed").toBool(), true);
        rig->messages.discard(last(rig->messages.thread()).value("id").toString());
        QCOMPARE(last(rig->messages.thread()).value("body").toString(), QStringLiteral("hi"));
    }

    void openOnScreenMarksTheRepliesRead()
    {
        const QDateTime now = QDateTime::currentDateTime();
        m_rows.insert("p1", row("p1", "person", "Dad", "one", now.addSecs(-120)));
        m_rows.insert("p2", row("p2", "person", "Dad", "two", now.addSecs(-60)));
        startLive();
        QTRY_COMPARE(rig->messages.unread(), 2);
        rig->messages.setOpen(true);
        QCOMPARE(rig->messages.unread(), 0); // here at once
        QTRY_COMPARE(m_server.requests("POST", "/rest/v1/rpc/read_messages").size(), 1);
        QCOMPARE(m_server.requests("POST", "/rest/v1/rpc/read_messages").first().body.value("up_to").toString(), QStringLiteral("p2"));
        // Nothing new: nothing more to mark.
        QTest::qWait(400);
        QCOMPARE(m_server.requests("POST", "/rest/v1/rpc/read_messages").size(), 1);
    }

    void anOlderBackendHasNoMessages()
    {
        m_server.route("/rest/v1/messages", [](const Request &) {
            return json(R"({"code":"PGRST205","message":"Could not find the table 'public.messages' in the schema cache"})", 404);
        });
        startLive();
        QTRY_VERIFY(!rig->messages.available());
        QVERIFY(!rig->messages.send("hi"));
    }

    void shapesStatusesDaysAndRuns()
    {
        const QDateTime now = QDateTime::currentDateTime();
        const auto at = [&](int minutesAgo) { return iso(now.addSecs(-60 * minutesAgo)); };
        QVariantList rows{
            QVariantMap{{"id", "a"}, {"sender_kind", "display"}, {"sender_name", "Mia"}, {"body", "x"}, {"created_at", at(3 * 24 * 60)}},
            QVariantMap{{"id", "b"}, {"sender_kind", "display"}, {"sender_name", "Mia"}, {"body", "y"}, {"created_at", at(30)}},
            QVariantMap{{"id", "c"}, {"sender_kind", "display"}, {"sender_name", "Mia"}, {"body", "z"}, {"created_at", at(28)},
                        {"notified_at", at(28)}},
            QVariantMap{{"id", "d"}, {"sender_kind", "display"}, {"sender_name", "Leo"}, {"body", "w"}, {"created_at", at(27)}},
        };
        // Leo's is home's newest: only it says how it stands.
        QVariantList t = MessageStore::shape(rows, {}, now, QStringLiteral("Dad"));
        QCOMPARE(t.size(), 4);
        QVERIFY(!t.at(0).toMap().value("dayLabel").toString().isEmpty());
        QCOMPARE(t.at(1).toMap().value("dayLabel").toString(), now.addSecs(-30 * 60).date() == now.date() ? QStringLiteral("Today") : QStringLiteral("Yesterday"));
        QCOMPARE(t.at(2).toMap().value("dayLabel").toString(), QString());
        QCOMPARE(t.at(2).toMap().value("runStart").toBool(), false); // Mia again, two minutes on
        QCOMPARE(t.at(3).toMap().value("runStart").toBool(), true);  // Leo
        QCOMPARE(t.at(2).toMap().value("status").toString(), QString());
        QCOMPARE(t.at(3).toMap().value("status").toString(), QStringLiteral("Sent"));

        QVariantMap d = rows.last().toMap();
        d.insert("notified_at", at(27));
        rows.last() = d;
        QCOMPARE(MessageStore::shape(rows, {}, now, "Dad").last().toMap().value("status").toString(), QStringLiteral("On Dad's phone"));
        QCOMPARE(MessageStore::shape(rows, {}, now, "Parent").last().toMap().value("status").toString(), QStringLiteral("Delivered"));
        d.insert("read_at", at(1));
        rows.last() = d;
        QCOMPARE(MessageStore::shape(rows, {}, now, "Dad").last().toMap().value("status").toString(), QStringLiteral("Seen by Dad"));
        QCOMPARE(MessageStore::shape(rows, {}, now, "").last().toMap().value("status").toString(), QStringLiteral("Seen"));

        // On its way, and one that didn't go.
        const QVariantList pending{
            QVariantMap{{"localId", "local-1"}, {"body", "on its way"}, {"name", "Mia"}, {"createdMs", now.toMSecsSinceEpoch()}, {"failure", ""}},
            QVariantMap{{"localId", "local-2"}, {"body", "stuck"}, {"name", "Mia"}, {"createdMs", now.toMSecsSinceEpoch()}, {"failure", "Offline"}},
        };
        t = MessageStore::shape(rows, pending, now, "Dad");
        QCOMPARE(t.at(4).toMap().value("status").toString(), QStringLiteral("Sending…"));
        QCOMPARE(t.at(4).toMap().value("pending").toBool(), true);
        QCOMPARE(t.at(5).toMap().value("status").toString(), QStringLiteral("Didn't send: Offline"));
        QCOMPARE(t.at(5).toMap().value("failed").toBool(), true);

        const QDate today(2026, 11, 3);
        QCOMPARE(MessageStore::dayLabel(today, today), QStringLiteral("Today"));
        QCOMPARE(MessageStore::dayLabel(today.addDays(-1), today), QStringLiteral("Yesterday"));
        QCOMPARE(MessageStore::dayLabel(today.addDays(-3), today), QLocale().toString(today.addDays(-3), QStringLiteral("dddd")));
        QCOMPARE(MessageStore::dayLabel(QDate(2025, 12, 24), today), QLocale().toString(QDate(2025, 12, 24), QStringLiteral("MMM d, yyyy")));
    }

    // Away mode from the settings row: on from away_since, off once
    // away_until has passed; the live store reads it with every poll.
    // A voice note: shaped with its length and no caption for the server's
    // own words; sent by uploading into this display's folder, then
    // send_message with the file; a retry after the upload doesn't upload again.
    void voiceNotesUploadThenSend()
    {
        QCOMPARE(MessageStore::voiceNoteLabel(12345), QStringLiteral("🎤 Voice note · 0:12"));
        QCOMPARE(MessageStore::voiceNoteLabel(65000), QStringLiteral("🎤 Voice note · 1:05"));
        const QDateTime now = QDateTime::currentDateTime();
        const QVariantList rows{
            QVariantMap{{"id", "a"}, {"sender_kind", "person"}, {"sender_name", "Dad"}, {"body", "🎤 Voice note · 0:12"},
                        {"audio_path", "x/y.wav"}, {"audio_ms", 12345}, {"created_at", iso(now)}},
            QVariantMap{{"id", "b"}, {"sender_kind", "display"}, {"sender_name", "Mia"}, {"body", "Listen!"},
                        {"audio_path", "x/z.wav"}, {"audio_ms", 4000}, {"created_at", iso(now.addSecs(1))}},
        };
        const QVariantList t = MessageStore::shape(rows, {}, now, "Dad");
        QCOMPARE(t.at(0).toMap().value("hasAudio").toBool(), true);
        QCOMPARE(t.at(0).toMap().value("audioLabel").toString(), QStringLiteral("0:12"));
        QCOMPARE(t.at(0).toMap().value("caption").toString(), QString());
        QCOMPARE(t.at(1).toMap().value("caption").toString(), QStringLiteral("Listen!"));

        startLive();
        QTRY_VERIFY(rig->messages.available());
        int uploads = 0;
        QString uploadedPath;
        m_server.route("/storage/v1/object/voice-notes/", [&](const Request &r) {
            ++uploads;
            uploadedPath = QString::fromUtf8(r.pathOnly().mid(QByteArray("/storage/v1/object/voice-notes/").size()));
            return json(R"({"Key":"voice-notes/x"})");
        });
        bool failOnce = true;
        m_server.route("/rest/v1/rpc/send_message", [&](const Request &r) {
            if (failOnce) {
                failOnce = false;
                return json(R"({"message":"something went wrong"})", 500);
            }
            QJsonObject o = row("v1", "display", "Kitchen", "🎤 Voice note · 0:03", QDateTime::currentDateTime());
            o.insert("audio_path", r.body.value("audio_path"));
            o.insert("audio_ms", r.body.value("audio_ms"));
            m_rows.insert("v1", o);
            return FakeServer::json(QJsonDocument(o));
        });
        rig->messages.sendVoiceNote(QByteArray("RIFF-fake-wav"), 3000, QString());
        QCOMPARE(last(rig->messages.thread()).value("hasAudio").toBool(), true);
        QCOMPARE(last(rig->messages.thread()).value("status").toString(), QStringLiteral("Sending…"));
        QTRY_COMPARE(last(rig->messages.thread()).value("failed").toBool(), true);
        QCOMPARE(uploads, 1);
        QVERIFY2(uploadedPath.startsWith(QStringLiteral("d0000000-0000-0000-0000-000000000001/")) && uploadedPath.endsWith(".wav"),
                 qPrintable(uploadedPath));
        rig->messages.retry(last(rig->messages.thread()).value("id").toString());
        QTRY_COMPARE(last(rig->messages.thread()).value("pending").toBool(), false);
        QCOMPARE(uploads, 1); // uploaded once
        const Request sent = m_server.requests("POST", "/rest/v1/rpc/send_message").last();
        QCOMPARE(sent.body.value("audio_path").toString(), uploadedPath);
        QCOMPARE(sent.body.value("audio_ms").toInt(), 3000);
        QCOMPARE(sent.body.value("body").toString(), QString());
        QCOMPARE(last(rig->messages.thread()).value("audioLabel").toString(), QStringLiteral("0:03"));
        // Without the voice service there's nothing to record or play with.
        QVERIFY(!rig->messages.canRecord());
        QSignalSpy notice(&rig->messages, &MessageStore::notice);
        rig->messages.play(QStringLiteral("v1"));
        QCOMPARE(notice.size(), 1);
    }

    // A backend from before voice notes refuses the audio columns: the store
    // asks again without them, and messages still read.
    void anOlderBackendWithoutVoiceNotes()
    {
        m_rows.insert("m1", row("m1", "display", "Mia", "hi", QDateTime::currentDateTime()));
        m_server.route("/rest/v1/messages", [this](const Request &r) {
            if (r.path.contains("audio_path"))
                return json(R"({"code":"42703","message":"column messages.audio_path does not exist"})", 400);
            QJsonArray out;
            for (const QJsonObject &o : std::as_const(m_rows))
                out << o;
            return json(rows(out));
        });
        startLive();
        QTRY_COMPARE(rig->messages.thread().size(), 1);
        QVERIFY(rig->messages.available());
    }

    void awayModeFromTheSettings()
    {
        const QDateTime now = QDateTime::currentDateTime();
        QVariantMap s{{"away_since", iso(now.addSecs(-600))}, {"away_name", "Dad"}, {"away_note", "At work"}};
        QVariantMap a = MessageStore::awayState(s, now);
        QCOMPARE(a.value("away").toBool(), true);
        QCOMPARE(a.value("label").toString(), QStringLiteral("Dad is out"));
        QCOMPARE(a.value("note").toString(), QStringLiteral("At work"));
        s.insert("away_until", iso(now.addSecs(3600)));
        QVERIFY2(MessageStore::awayState(s, now).value("label").toString().startsWith(QStringLiteral("Dad is out · back ")),
                 qPrintable(MessageStore::awayState(s, now).value("label").toString()));
        s.insert("away_until", iso(now.addSecs(-60)));
        QCOMPARE(MessageStore::awayState(s, now).value("away").toBool(), false);
        s.insert("away_until", QVariant());
        s.insert("away_since", QVariant());
        QCOMPARE(MessageStore::awayState(s, now).value("away").toBool(), false);
        QCOMPARE(MessageStore::awayState({{"away_since", iso(now)}}, now).value("label").toString(), QStringLiteral("Parent is out"));

        m_server.route("/rest/v1/platform_settings", [now](const Request &) {
            return FakeServer::json(QJsonDocument(QJsonArray{QJsonObject{
                {"display_name", "Hill Valley"}, {"timezone", "America/Chicago"}, {"message_names", QJsonArray{"Mia"}},
                {"away_since", iso(now.addSecs(-60))}, {"away_until", QJsonValue::Null}, {"away_note", "At work"}, {"away_name", "Dad"}}}));
        });
        startLive();
        QSignalSpy changed(&rig->messages, &MessageStore::awayChanged);
        QTRY_VERIFY(rig->messages.away());
        QCOMPARE(rig->messages.awayLabel(), QStringLiteral("Dad is out"));
        QCOMPARE(rig->messages.awayNote(), QStringLiteral("At work"));
        QCOMPARE(rig->messages.names(), QStringList({"Mia"}));
        // Home again: the next poll says so.
        m_server.route("/rest/v1/platform_settings", [](const Request &) {
            return json(R"([{"display_name":"Hill Valley","message_names":["Mia"],"away_since":null,"away_until":null,"away_note":null,"away_name":null}])");
        });
        QTRY_VERIFY(!rig->messages.away());
        // An older backend's row, without the columns, is simply not away.
        rig->messages.applySettings({{"message_names", QVariantList{"Mia"}}});
        QVERIFY(!rig->messages.away());
    }

    // Away mode from here: device_set_away, the banner once the server has
    // it, the poll agreeing, and a refusal saying why.
    void setsAwayFromHere()
    {
        auto away = std::make_shared<QJsonObject>(); // the row's away_* (empty: home)
        m_server.route("/rest/v1/platform_settings", [away](const Request &) {
            QJsonObject row{{"display_name", "Hill Valley"}, {"message_names", QJsonArray{"Mia"}}};
            for (auto it = away->begin(); it != away->end(); ++it)
                row.insert(it.key(), it.value());
            return FakeServer::json(QJsonDocument(QJsonArray{row}));
        });
        m_server.route("/rest/v1/rpc/device_set_away", [away](const Request &r) {
            if (r.body.value("away").toBool())
                *away = {{"away_since", iso(QDateTime::currentDateTime())}, {"away_until", r.body.value("until")},
                         {"away_note", QJsonValue::Null}, {"away_name", "Dad"}};
            else
                *away = {};
            return FakeServer::json(QJsonDocument(QJsonObject{
                {"away", !away->isEmpty()}, {"since", away->value("away_since")}, {"until", away->value("away_until")},
                {"note", QJsonValue::Null}, {"name", away->isEmpty() ? QJsonValue(QJsonValue::Null) : QJsonValue("Dad")}}));
        });
        startLive();
        QSignalSpy notices(&rig->messages, &MessageStore::notice);
        rig->messages.setAway(true, 120);
        QTRY_VERIFY(rig->messages.away());
        const QJsonObject sent = m_server.requests("POST", "/rest/v1/rpc/device_set_away").last().body;
        QCOMPARE(sent.value("away").toBool(), true);
        const QDateTime until = QDateTime::fromString(sent.value("until").toString(), Qt::ISODateWithMs);
        QVERIFY2(qAbs(QDateTime::currentDateTime().secsTo(until) - 7200) < 60, qPrintable(sent.value("until").toString()));
        QVERIFY2(rig->messages.awayLabel().startsWith(QStringLiteral("Dad is out · back")), qPrintable(rig->messages.awayLabel()));
        QCOMPARE(notices.size(), 1);
        // The polls after it read the same.
        const int polls = m_server.requests("GET", "/rest/v1/platform_settings").size();
        QTRY_VERIFY(m_server.requests("GET", "/rest/v1/platform_settings").size() >= polls + 2);
        QVERIFY(rig->messages.away());
        // Home: off, with no time.
        rig->messages.setAway(false);
        QTRY_VERIFY(!rig->messages.away());
        QVERIFY(!m_server.requests("POST", "/rest/v1/rpc/device_set_away").last().body.contains("until"));
        // Till they're back: no time either.
        rig->messages.setAway(true);
        QTRY_VERIFY(rig->messages.away());
        QVERIFY(!m_server.requests("POST", "/rest/v1/rpc/device_set_away").last().body.contains("until"));
        QCOMPARE(rig->messages.awayLabel(), QStringLiteral("Dad is out"));
        rig->messages.setAway(false);
        QTRY_VERIFY(!rig->messages.away());
        // A refusal says why, and nothing changes.
        m_server.route("/rest/v1/rpc/device_set_away", [](const Request &) { return json(R"({"message":"not a paired display"})", 400); });
        notices.clear();
        rig->messages.setAway(true);
        QTRY_COMPARE(notices.size(), 1);
        QCOMPARE(notices.first().first().toString(), QStringLiteral("Couldn't change away mode: not a paired display"));
        QVERIFY(!rig->messages.away());
        // A backend from before it.
        m_server.route("/rest/v1/rpc/device_set_away", [](const Request &) {
            return json(R"({"code":"PGRST202","message":"Could not find the function public.device_set_away"})", 404);
        });
        notices.clear();
        rig->messages.setAway(true);
        QTRY_COMPARE(notices.size(), 1);
        QCOMPARE(notices.first().first().toString(), QStringLiteral("Away mode from here needs McFly's newest backend"));
    }

    void theDemoAnswersBack()
    {
        // A request the last test's store had on the way lands now, not in this one.
        QTest::qWait(300);
        QTRY_COMPARE(m_server.pending(), 0);
        m_server.reset();
        serve();
        rig = std::make_unique<Rig>(m_server.baseUrl(), true);
        rig->messages.setDemoReplyMs(50);
        rig->store.start();
        QVERIFY(rig->messages.available());
        QVERIFY(rig->messages.thread().size() >= 4);
        QCOMPARE(rig->messages.names(), QStringList({"Mia", "Leo"}));
        QSignalSpy arrived(&rig->messages, &MessageStore::arrived);
        rig->messages.setWriter("Leo");
        QVERIFY(rig->messages.send("Can we have pizza?"));
        QTRY_COMPARE(arrived.count(), 1);
        QCOMPARE(arrived.first().first().toMap().value("name").toString(), QStringLiteral("Parent"));
        QVERIFY(m_server.requests().isEmpty()); // the demo calls no one
    }
};

QTEST_GUILESS_MAIN(TestMessages)
#include "tst_messages.moc"
