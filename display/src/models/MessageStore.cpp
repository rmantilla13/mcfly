#include "MessageStore.h"

#include "backend/SupabaseClient.h"
#include "models/FeedStore.h"

#include <QJsonArray>
#include <QJsonObject>
#include <QLocale>
#include <QRegularExpression>
#include <QUrlQuery>
#include <algorithm>

namespace {

constexpr int kLimit = 100;          // read at a time
constexpr int kKeep = 150;           // kept in the thread
constexpr qint64 kOverlapMs = 30000; // each poll looks this far behind the newest change seen
constexpr qint64 kFastAfterSendMs = 5 * 60 * 1000;
constexpr int kUnavailableRetryMs = 10 * 60 * 1000;
constexpr qint64 kRunGapMs = 10 * 60 * 1000;
const char *kColumns = "id,sender_kind,sender_name,body,device_id,via,created_at,updated_at,read_at,notified_at,notify_error";

QDateTime when(const QVariantMap &row, const char *key)
{
    return QDateTime::fromString(row.value(QLatin1String(key)).toString(), Qt::ISODateWithMs);
}

bool earlier(const QVariantMap &a, const QVariantMap &b)
{
    const QDateTime ta = when(a, "created_at"), tb = when(b, "created_at");
    return ta != tb ? ta < tb : a.value("id").toString() < b.value("id").toString();
}

QString timeLabel(const QDateTime &t)
{
    return QLocale().toString(t.toLocalTime().time(), QStringLiteral("h:mm ap"));
}

// A server error as a sentence for a kid: the message without "(HTTP 400)",
// its first letter capitalised.
QString sentence(const QString &error)
{
    static const QRegularExpression status(QStringLiteral("\\s*\\(HTTP \\d+\\)$"));
    QString s = QString(error).remove(status).trimmed();
    if (s.isEmpty())
        s = MessageStore::tr("McFly couldn't be reached");
    s[0] = s[0].toUpper();
    return s;
}

} // namespace

MessageStore::MessageStore(SupabaseClient *client, FeedStore *store, QObject *parent)
    : QObject(parent), m_client(client), m_store(store)
{
    m_timer.setSingleShot(true);
    connect(&m_timer, &QTimer::timeout, this, &MessageStore::poll);
    connect(m_store, &FeedStore::modeChanged, this, &MessageStore::onModeChanged);
    // Away mode runs out on its own: look again each minute.
    connect(m_store, &FeedStore::nowAngleChanged, this, &MessageStore::updateAway);
    onModeChanged();
}

QDateTime MessageStore::now() const
{
    return m_store->now();
}

QStringList MessageStore::quickMessages() const
{
    return {tr("I'm home!"), tr("Can you call me?"), tr("When are you coming home?"), tr("Can I have a snack?"),
            tr("I need help"), tr("Love you!")};
}

void MessageStore::setPollIntervals(int fastMs, int slowMs)
{
    m_fastMs = fastMs;
    m_slowMs = slowMs;
    if (m_timer.isActive())
        schedule();
}

void MessageStore::setWriter(const QString &writer)
{
    if (writer == m_writer)
        return;
    m_writer = writer;
    emit writerChanged();
}

void MessageStore::setDraft(const QString &draft)
{
    if (draft == m_draft)
        return;
    m_draft = draft;
    emit draftChanged();
}

void MessageStore::setOpen(bool open)
{
    if (open == m_open)
        return;
    m_open = open;
    emit openChanged();
    if (open) {
        markRead();
        refresh();
    }
}

void MessageStore::refresh()
{
    if (m_mode == QLatin1String("live") && !m_polling) {
        m_timer.stop();
        poll();
    }
}

// ───────────────────────────── Modes ─────────────────────────────

void MessageStore::onModeChanged()
{
    const QString mode = m_store->mode();
    if (mode == m_mode)
        return;
    m_mode = mode;
    ++m_generation;
    m_timer.stop();
    m_polling = false;
    m_loaded = false;
    m_cursor = {};
    m_rows.clear();
    m_pending.clear();
    m_fastUntilMs = 0;
    const bool available = mode == QLatin1String("demo") || mode == QLatin1String("live");
    if (available != m_available) {
        m_available = available;
        emit availableChanged();
    }
    if (mode == QLatin1String("demo"))
        loadDemo();
    else if (!m_names.isEmpty()) {
        m_names.clear();
        emit namesChanged();
    }
    if (mode != QLatin1String("demo") && mode != QLatin1String("live")) {
        m_settings.clear();
        updateAway();
    }
    rebuild();
    if (mode == QLatin1String("live"))
        poll();
}

// The demo's thread: two at home, the person's replies, and one more on its
// way a few seconds after anything sent here.
void MessageStore::loadDemo()
{
    const QDateTime t = now().toUTC();
    auto row = [&](const QString &id, const QString &kind, const QString &name, const QString &body, int minutesAgo,
                   bool read, bool notified) {
        const QString at = t.addSecs(-60 * minutesAgo).toString(Qt::ISODateWithMs);
        QVariantMap r{{"id", id}, {"sender_kind", kind}, {"sender_name", name}, {"body", body},
                      {"created_at", at}, {"updated_at", at}};
        if (read)
            r.insert("read_at", at);
        if (notified)
            r.insert("notified_at", at);
        m_rows.insert(id, r);
    };
    row("6d000000-0000-0000-0000-000000000001", "display", "Mia", tr("I'm home from school!"), 185, true, true);
    row("6d000000-0000-0000-0000-000000000002", "person", "Parent", tr("Yay! Snack is in the fridge. Homework first 🙂"), 178, true, false);
    row("6d000000-0000-0000-0000-000000000003", "display", "Leo", tr("Can Sam come over to play?"), 24, true, true);
    row("6d000000-0000-0000-0000-000000000004", "person", "Parent", tr("Yes, until 6. Be nice to the dog!"), 20, false, false);
    m_names = {QStringLiteral("Mia"), QStringLiteral("Leo")};
    emit namesChanged();
    m_loaded = true;
}

// ───────────────────────────── Reading ─────────────────────────────

void MessageStore::schedule()
{
    if (m_mode != QLatin1String("live"))
        return;
    const bool fast = m_open || now().toMSecsSinceEpoch() < m_fastUntilMs;
    m_timer.start(fast ? m_fastMs : m_slowMs);
}

void MessageStore::poll()
{
    if (m_mode != QLatin1String("live") || m_polling)
        return;
    m_polling = true;
    const int generation = m_generation;
    m_store->withSession(
        [this, generation]() {
            if (generation != m_generation)
                return;
            QUrlQuery q;
            q.addQueryItem("select", kColumns);
            const bool first = !m_loaded;
            // Nothing seen yet (an empty thread): the whole thread again,
            // which is cheap, until there's a change to read from.
            if (!m_cursor.isValid()) {
                q.addQueryItem("order", "created_at.desc,id.desc");
            } else {
                q.addQueryItem("updated_at", "gt." + m_cursor.addMSecs(-kOverlapMs).toUTC().toString(Qt::ISODateWithMs));
                q.addQueryItem("order", "updated_at");
            }
            q.addQueryItem("limit", QString::number(kLimit));
            m_client->select("messages", q, [this, generation, first](const QJsonDocument &doc, const QString &error) {
                if (generation != m_generation)
                    return;
                m_polling = false;
                if (!error.isEmpty()) {
                    // An older backend: no messages table yet. Look again now and then.
                    if (error.contains("HTTP 404") || error.contains("PGRST205")) {
                        if (m_available) {
                            qInfo() << "messages not available:" << error;
                            m_available = false;
                            emit availableChanged();
                        }
                        m_timer.start(kUnavailableRetryMs);
                        return;
                    }
                    qWarning() << "messages:" << error;
                    schedule();
                    return;
                }
                if (!m_available) {
                    m_available = true;
                    emit availableChanged();
                }
                merge(doc.array().toVariantList(), !first);
                m_loaded = true;
                if (m_open)
                    markRead();
                schedule();
            });
            // The names and away mode: with every read, so away mode shows
            // within a poll. One small row.
            loadNames();
        },
        [this, generation]() {
            if (generation != m_generation)
                return;
            m_polling = false;
            schedule();
        });
}

void MessageStore::loadNames()
{
    const int generation = m_generation;
    QUrlQuery q;
    // Every column: a backend without away mode (or names) still answers.
    q.addQueryItem("select", "*");
    q.addQueryItem("limit", "1");
    m_client->select("platform_settings", q, [this, generation](const QJsonDocument &doc, const QString &error) {
        if (generation != m_generation || !error.isEmpty())
            return;
        applySettings(doc.array().at(0).toObject().toVariantMap());
    });
}

void MessageStore::applySettings(const QVariantMap &settings)
{
    QStringList names;
    for (const QVariant &v : settings.value("message_names").toList())
        if (!v.toString().trimmed().isEmpty())
            names << v.toString();
    if (names != m_names) {
        m_names = names;
        emit namesChanged();
    }
    if (!m_writer.isEmpty() && !m_names.contains(m_writer))
        setWriter(QString());
    QVariantMap away;
    for (const char *key : {"away_since", "away_until", "away_note", "away_name"})
        away.insert(QLatin1String(key), settings.value(QLatin1String(key)));
    m_settings = away;
    updateAway();
}

void MessageStore::updateAway()
{
    const QVariantMap next = awayState(m_settings, now());
    if (next == m_away)
        return;
    m_away = next;
    emit awayChanged();
}

QVariantMap MessageStore::awayState(const QVariantMap &settings, const QDateTime &now)
{
    const QDateTime since = when(settings, "away_since");
    const QDateTime until = when(settings, "away_until");
    if (!since.isValid() || (until.isValid() && until <= now))
        return {{"away", false}};
    QString name = settings.value("away_name").toString().trimmed();
    if (name.isEmpty())
        name = tr("Parent");
    QString label = tr("%1 is out").arg(name);
    if (until.isValid()) {
        const QDateTime local = until.toLocalTime();
        label = local.date() == now.toLocalTime().date()
                    ? tr("%1 is out · back around %2").arg(name, timeLabel(until))
                    : tr("%1 is out · back %2 %3").arg(name, QLocale().toString(local.date(), QStringLiteral("dddd")), timeLabel(until));
    }
    return {{"away", true}, {"name", name}, {"label", label}, {"note", settings.value("away_note").toString()}};
}

void MessageStore::merge(const QVariantList &rows, bool announce)
{
    QVariantList arrivals;
    for (const QVariant &v : rows) {
        QVariantMap row = v.toMap();
        const QString id = row.value("id").toString();
        if (id.isEmpty())
            continue;
        const QDateTime updated = when(row, "updated_at");
        const auto known = m_rows.constFind(id);
        if (known != m_rows.cend()) {
            const QDateTime had = when(*known, "updated_at");
            if (had > updated)
                continue;
            // Read here and not yet on the server: the same copy again keeps it read.
            if (had == updated && !known->value("read_at").isNull() && row.value("read_at").isNull())
                continue;
        }
        if (known == m_rows.cend() && announce && row.value("sender_kind").toString() == QLatin1String("person")
            && row.value("read_at").isNull())
            arrivals << row;
        m_rows.insert(id, row);
        if (!m_cursor.isValid() || updated > m_cursor)
            m_cursor = updated;
    }
    if (m_rows.size() > kKeep) {
        QList<QVariantMap> all = m_rows.values();
        std::sort(all.begin(), all.end(), earlier);
        for (int i = 0; i < all.size() - kKeep; ++i)
            m_rows.remove(all.at(i).value("id").toString());
    }
    rebuild();
    std::sort(arrivals.begin(), arrivals.end(), [](const QVariant &a, const QVariant &b) { return earlier(a.toMap(), b.toMap()); });
    for (const QVariant &v : std::as_const(arrivals)) {
        const QVariantMap row = v.toMap();
        emit arrived({{"id", row.value("id")},
                      {"name", row.value("sender_name")},
                      {"body", row.value("body")},
                      {"timeLabel", timeLabel(when(row, "created_at"))}});
    }
}

void MessageStore::rebuild()
{
    QList<QVariantMap> rows = m_rows.values();
    std::sort(rows.begin(), rows.end(), earlier);
    QString person;
    int unread = 0;
    for (const QVariantMap &r : std::as_const(rows)) {
        if (r.value("sender_kind").toString() != QLatin1String("person"))
            continue;
        person = r.value("sender_name").toString();
        if (r.value("read_at").isNull())
            ++unread;
    }
    QVariantList list;
    for (const QVariantMap &r : std::as_const(rows))
        list << r;
    const QVariantList shaped = shape(list, m_pending, now(), person);
    if (shaped == m_thread && unread == m_unread && person == m_personName)
        return;
    m_thread = shaped;
    m_unread = unread;
    m_personName = person;
    emit threadChanged();
}

// ───────────────────────────── Shaping ─────────────────────────────

QString MessageStore::dayLabel(const QDate &day, const QDate &today)
{
    if (day == today)
        return tr("Today");
    if (day == today.addDays(-1))
        return tr("Yesterday");
    if (day > today.addDays(-7) && day < today)
        return QLocale().toString(day, QStringLiteral("dddd"));
    return QLocale().toString(day, day.year() == today.year() ? QStringLiteral("MMM d") : QStringLiteral("MMM d, yyyy"));
}

QVariantList MessageStore::shape(const QVariantList &rows, const QVariantList &pending, const QDateTime &now,
                                 const QString &personName)
{
    QList<QVariantMap> sorted;
    for (const QVariant &v : rows)
        sorted << v.toMap();
    std::sort(sorted.begin(), sorted.end(), earlier);
    int lastHome = -1;
    for (int i = 0; i < sorted.size(); ++i)
        if (sorted.at(i).value("sender_kind").toString() == QLatin1String("display"))
            lastHome = i;
    // "Parent" is the server's stand-in until the person names themselves: no "Parent's phone".
    const bool named = !personName.isEmpty() && personName != QLatin1String("Parent");

    QVariantList out;
    QDate lastDay;
    QString lastWho;
    qint64 lastMs = 0;
    auto add = [&](QVariantMap item, const QDateTime &at) {
        const QDate day = at.toLocalTime().date();
        item.insert("dayLabel", day != lastDay ? dayLabel(day, now.date()) : QString());
        const QString who = (item.value("home").toBool() ? QStringLiteral("h:") : QStringLiteral("p:")) + item.value("name").toString();
        const qint64 ms = at.toMSecsSinceEpoch();
        item.insert("runStart", day != lastDay || who != lastWho || ms - lastMs >= kRunGapMs);
        item.insert("timeLabel", timeLabel(at));
        lastDay = day;
        lastWho = who;
        lastMs = ms;
        out << item;
    };
    for (int i = 0; i < sorted.size(); ++i) {
        const QVariantMap &r = sorted.at(i);
        const bool home = r.value("sender_kind").toString() == QLatin1String("display");
        QString status;
        if (home && i == lastHome) {
            if (!r.value("read_at").isNull())
                status = named ? tr("Seen by %1").arg(personName) : tr("Seen");
            else if (!r.value("notified_at").isNull())
                status = named ? tr("On %1's phone").arg(personName) : tr("Delivered");
            else
                status = tr("Sent");
        }
        add({{"id", r.value("id")}, {"home", home}, {"name", r.value("sender_name")}, {"body", r.value("body")},
             {"status", status}, {"failed", false}, {"pending", false}},
            when(r, "created_at"));
    }
    for (const QVariant &v : pending) {
        const QVariantMap p = v.toMap();
        const QString failure = p.value("failure").toString();
        add({{"id", p.value("localId")}, {"home", true}, {"name", p.value("name")}, {"body", p.value("body")},
             {"status", failure.isEmpty() ? tr("Sending…") : tr("Didn't send: %1").arg(failure)},
             {"failed", !failure.isEmpty()}, {"pending", true}},
            QDateTime::fromMSecsSinceEpoch(p.value("createdMs").toLongLong()));
    }
    return out;
}

// ───────────────────────────── Writing ─────────────────────────────

bool MessageStore::send(const QString &text)
{
    const QString body = text.trimmed();
    if (body.isEmpty() || !m_available)
        return false;
    const QString localId = QStringLiteral("local-%1").arg(++m_localIds);
    // No one picked: the server signs it with the display's own name.
    m_pending << QVariantMap{{"localId", localId}, {"body", body.left(500)}, {"name", m_writer},
                             {"createdMs", now().toMSecsSinceEpoch()}, {"failure", QString()}};
    m_fastUntilMs = now().toMSecsSinceEpoch() + kFastAfterSendMs;
    rebuild();
    deliver(localId);
    return true;
}

void MessageStore::retry(const QString &localId)
{
    for (QVariant &v : m_pending) {
        QVariantMap p = v.toMap();
        if (p.value("localId").toString() != localId)
            continue;
        p.insert("failure", QString());
        v = p;
        rebuild();
        deliver(localId);
        return;
    }
}

void MessageStore::discard(const QString &localId)
{
    const auto before = m_pending.size();
    m_pending.erase(std::remove_if(m_pending.begin(), m_pending.end(),
                                   [&](const QVariant &v) { return v.toMap().value("localId").toString() == localId; }),
                    m_pending.end());
    if (m_pending.size() != before)
        rebuild();
}

void MessageStore::deliver(const QString &localId)
{
    QVariantMap item;
    for (const QVariant &v : std::as_const(m_pending))
        if (v.toMap().value("localId").toString() == localId)
            item = v.toMap();
    if (item.isEmpty())
        return;
    const int generation = m_generation;
    auto fail = [this, localId, generation](const QString &why) {
        if (generation != m_generation)
            return;
        for (QVariant &v : m_pending) {
            QVariantMap p = v.toMap();
            if (p.value("localId").toString() == localId) {
                p.insert("failure", why);
                v = p;
            }
        }
        rebuild();
    };
    auto landed = [this, localId, generation](const QVariantMap &row) {
        if (generation != m_generation)
            return;
        m_pending.erase(std::remove_if(m_pending.begin(), m_pending.end(),
                                       [&](const QVariant &v) { return v.toMap().value("localId").toString() == localId; }),
                        m_pending.end());
        merge({row}, false);
        schedule();
    };

    if (m_mode == QLatin1String("demo")) {
        QTimer::singleShot(400, this, [this, item, landed, generation]() {
            if (generation != m_generation)
                return;
            const QString at = now().toUTC().toString(Qt::ISODateWithMs);
            const QString name = item.value("name").toString();
            landed({{"id", QStringLiteral("6d000000-demo-%1").arg(item.value("localId").toString())},
                    {"sender_kind", "display"}, {"sender_name", name.isEmpty() ? tr("Kitchen") : name}, {"body", item.value("body")},
                    {"created_at", at}, {"updated_at", at}, {"notified_at", at}});
            // A reply from the person, a few seconds on.
            QTimer::singleShot(m_demoReplyMs, this, [this, generation]() {
                if (generation != m_generation)
                    return;
                static const QStringList replies{tr("On my way!"), tr("Okay, love you!"), tr("Yes, go ahead."),
                                                 tr("I'll call you in 5 minutes.")};
                const QString at = now().toUTC().toString(Qt::ISODateWithMs);
                merge({QVariantMap{{"id", QStringLiteral("6d000000-reply-%1").arg(++m_localIds)},
                                   {"sender_kind", "person"}, {"sender_name", "Parent"},
                                   {"body", replies.at(m_localIds % replies.size())},
                                   {"created_at", at}, {"updated_at", at}}},
                      true);
                if (m_open)
                    markRead();
            });
        });
        return;
    }

    m_store->withSession(
        [this, item, fail, landed, generation]() {
            if (generation != m_generation)
                return;
            QJsonObject args{{"body", item.value("body").toString()}};
            if (!item.value("name").toString().isEmpty())
                args.insert("sender_name", item.value("name").toString());
            m_client->rpc("send_message", args, [fail, landed](const QJsonDocument &doc, const QString &error) {
                if (!error.isEmpty()) {
                    qWarning() << "send_message failed:" << error;
                    fail(sentence(error));
                    return;
                }
                landed(doc.object().toVariantMap());
            });
        },
        [fail]() { fail(tr("McFly couldn't be reached")); });
}

void MessageStore::markRead()
{
    QString newest;
    QDateTime newestAt;
    const QString stamp = now().toUTC().toString(Qt::ISODateWithMs);
    for (auto it = m_rows.begin(); it != m_rows.end(); ++it) {
        if (it->value("sender_kind").toString() != QLatin1String("person") || !it->value("read_at").isNull())
            continue;
        const QDateTime at = when(*it, "created_at");
        if (newest.isEmpty() || at > newestAt) {
            newest = it.key();
            newestAt = at;
        }
        // Read here at once; the server's copy (a newer updated_at) follows.
        it->insert("read_at", stamp);
    }
    if (newest.isEmpty())
        return;
    rebuild();
    if (m_mode != QLatin1String("live"))
        return;
    const int generation = m_generation;
    m_store->withSession([this, newest, generation]() {
        if (generation != m_generation)
            return;
        m_client->rpc("read_messages", QJsonObject{{"up_to", newest}}, [](const QJsonDocument &, const QString &error) {
            if (!error.isEmpty())
                qWarning() << "read_messages failed:" << error;
        });
    });
}
