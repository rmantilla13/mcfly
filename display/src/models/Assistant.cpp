#include "Assistant.h"

#include "backend/SupabaseClient.h"
#include "models/FeedStore.h"
#include "voice/VoiceClient.h"

#include <QJsonArray>
#include <QLocale>
#include <QNetworkReply>
#include <QRandomGenerator>
#include <QRegularExpression>
#include <QSet>
#include <QSettings>
#include <QTimer>

namespace {
constexpr int kDemoThinkMs = 650;  // pause before a demo reply starts streaming
constexpr int kHistoryTurns = 10;  // earlier messages sent with a question

// Suggestions: lib/suggestions.ts's rules.
constexpr int kMaxSuggestions = 4;
constexpr int kMaxSuggestionChars = 42; // two chips share a row (SuggestionChips)
constexpr qint64 kMinuteMs = 60 * 1000;
constexpr qint64 kHourMs = 60 * kMinuteMs;
constexpr double kMoverMinPct = 1;              // below this, "why is it up?" has no answer worth asking
constexpr qint64 kQuoteFreshMs = 36 * kHourMs;  // Friday's move isn't "today" on Sunday
constexpr qint64 kEventWindowMs = 3 * kHourMs;
constexpr qint64 kBriefFreshMs = 3 * kHourMs;

int httpStatus(const QString &error)
{
    static const QRegularExpression re(QStringLiteral("\\(HTTP (\\d+)\\)$"));
    const auto m = re.match(error);
    return m.hasMatch() ? m.captured(1).toInt() : 0;
}

// before + value + after in kMaxSuggestionChars, the value cut at a word with
// an ellipsis when it has to be; empty when too little of it would fit.
QString fit(const QString &before, const QString &value, const QString &after)
{
    const QString v = value.simplified();
    if (v.isEmpty())
        return {};
    const int room = kMaxSuggestionChars - int(before.size()) - int(after.size());
    if (v.size() <= room)
        return before + v + after;
    if (room < 8)
        return {};
    QString cut = v.left(room - 1);
    // Back up to the last whole word, unless the cut already fell between two.
    const qsizetype space = cut.lastIndexOf(QLatin1Char(' '));
    if (v.at(room - 1) != QLatin1Char(' ') && space >= (room - 1) * 0.6)
        cut = cut.left(space);
    static const QRegularExpression trailing(QStringLiteral("[\\s,.;:!?'\"“”‘’–—-]+$"));
    cut.remove(trailing);
    return before + cut + QStringLiteral("…") + after;
}

// At most four, none too long, none twice.
QStringList firstFour(const QStringList &candidates)
{
    QStringList out;
    for (const QString &s : candidates) {
        if (s.isEmpty() || s.size() > kMaxSuggestionChars || out.contains(s))
            continue;
        out << s;
        if (out.size() == kMaxSuggestions)
            break;
    }
    return out;
}

QString pct1(double value) { return QLocale().toString(qAbs(value), 'f', 1); }

// The biggest move today worth asking about: 1% or more, on a fresh quote.
QVariantMap biggestMover(const FeedStore *store, qint64 nowMs)
{
    QVariantMap best;
    for (const QVariant &v : store->quotes()) {
        const QVariantMap q = v.toMap();
        const double pct = q.value("change_pct").toDouble();
        QDateTime asOf = QDateTime::fromString(q.value("as_of").toString(), Qt::ISODateWithMs);
        if (!asOf.isValid())
            asOf = QDateTime::fromString(q.value("as_of").toString(), Qt::ISODate);
        if (!std::isfinite(pct) || qAbs(pct) < kMoverMinPct || (asOf.isValid() && nowMs - asOf.toMSecsSinceEpoch() > kQuoteFreshMs))
            continue;
        if (best.isEmpty() || qAbs(pct) > qAbs(best.value("change_pct").toDouble()))
            best = q;
    }
    return best;
}

QString moverQuestion(const QVariantMap &quote)
{
    const double pct = quote.value("change_pct").toDouble();
    const QString move = QObject::tr("%1 %2 %3%").arg(quote.value("symbol").toString(), pct > 0 ? QObject::tr("up") : QObject::tr("down"), pct1(pct));
    const QString full = QObject::tr("Why is %1 today?").arg(move);
    if (full.size() <= kMaxSuggestionChars)
        return full;
    const QString shorter = QObject::tr("Why is %1?").arg(move);
    return shorter.size() <= kMaxSuggestionChars ? shorter : QString();
}

// The next timed event from now, within `withinMs` (any time when 0).
QVariantMap nextEvent(const FeedStore *store, qint64 nowMs, qint64 withinMs)
{
    for (const QVariant &v : store->events()) {
        const QVariantMap e = v.toMap();
        const qint64 start = e.value("startMs").toLongLong();
        if (!e.value("all_day").toBool() && start > nowMs && (withinMs <= 0 || start - nowMs <= withinMs))
            return e;
    }
    return {};
}

// Today's lead story: the newest Pulse report's hero (the timeline has every source's).
QString leadHeadline(const FeedStore *store)
{
    QVariantMap lead;
    for (const QVariant &v : store->timeline()) {
        const QVariantMap t = v.toMap();
        if (t.value("kind").toString() == QLatin1String("news")
            && (lead.isEmpty() || t.value("startMs").toLongLong() > lead.value("startMs").toLongLong()))
            lead = t;
    }
    return lead.value("title").toString();
}

// The latest brief if it is from the last three hours.
QVariantMap freshBrief(const FeedStore *store, qint64 nowMs)
{
    const QVariantMap brief = store->latestBrief();
    const qint64 at = brief.value("publishedMs").toLongLong();
    if (brief.isEmpty() || nowMs - at >= kBriefFreshMs || at - nowMs >= 5 * kMinuteMs)
        return {};
    return brief;
}

// A sentence: ends with a full stop unless it already ends a sentence.
QString sentence(const QString &text)
{
    const QString t = text.simplified();
    if (t.isEmpty() || QStringLiteral(".!?…").contains(t.back()))
        return t;
    return t + QLatin1Char('.');
}

// "Today" reads as "today" mid-sentence (also in "Yesterday · 4:00 pm");
// weekdays keep their capital.
QString inSentence(const QString &label)
{
    for (const QString &day : {QObject::tr("Today"), QObject::tr("Yesterday")})
        if (label.startsWith(day))
            return day.toLower() + label.mid(day.size());
    return label;
}

// What a question asks about after its lead-in ("prep me for", "more on"):
// without quotes, a trailing ellipsis or question mark.
QString subjectAfter(const QString &q, const QString &lead)
{
    const qsizetype at = q.indexOf(lead);
    if (at < 0)
        return {};
    QString subject = q.mid(at + lead.size());
    static const QRegularExpression edges(QStringLiteral("^[\\s“”\"'‘’]+|[\\s“”\"'‘’…?.!]+$"));
    return subject.remove(edges).simplified();
}
} // namespace

Assistant::Assistant(SupabaseClient *client, FeedStore *store, VoiceClient *voice, QObject *parent)
    : QObject(parent), m_client(client), m_store(store), m_voice(voice)
{
    m_provider = QSettings().value("assistant/provider").toString();
    if (m_provider != QLatin1String("claude") && m_provider != QLatin1String("grok"))
        m_provider.clear();
    connect(m_store, &FeedStore::dataChanged, this, &Assistant::providerChanged);
    // A re-paired display is a different device user: start over.
    connect(m_store, &FeedStore::modeChanged, this, [this]() {
        if (m_store->mode() == "pairing")
            reset();
    });
    // The suggestions follow the feeds, the clock (a meeting coming into
    // the three-hour window, a brief getting old) and what stands out (a
    // board's status or a metric is a screen's own question).
    connect(m_store, &FeedStore::dataChanged, this, &Assistant::updateSuggestions);
    connect(m_store, &FeedStore::nowAngleChanged, this, &Assistant::updateSuggestions);
    connect(m_store, &FeedStore::highlightsChanged, this, &Assistant::updateSuggestions);
    updateSuggestions();
}

void Assistant::setProvider(const QString &provider)
{
    const QString value = provider == QLatin1String("claude") || provider == QLatin1String("grok") ? provider : QString();
    if (value == m_provider)
        return;
    m_provider = value;
    if (value.isEmpty())
        QSettings().remove("assistant/provider");
    else
        QSettings().setValue("assistant/provider", value);
    emit providerChanged();
}

QString Assistant::effectiveProvider() const
{
    if (!m_provider.isEmpty())
        return m_provider;
    const QString platform = m_store->assistantProvider();
    return platform.isEmpty() ? QStringLiteral("claude") : platform;
}

void Assistant::updateSuggestions()
{
    // Every screen's list too: a screen's own question can change while the
    // general four don't (a board's status recovering), and bindings follow
    // suggestionsChanged alone.
    const QStringList next = buildSuggestions();
    QHash<QString, QStringList> forScreen;
    for (const char *screen : {"home", "briefs", "markets", "metrics", "news", "projects", "boards", "calendar"})
        forScreen.insert(QLatin1String(screen), buildSuggestionsFor(QLatin1String(screen), next));
    if (next == m_suggestions && forScreen == m_forScreen)
        return; // the chips stay put through a sync that changed nothing they show
    m_suggestions = next;
    m_forScreen = forScreen;
    emit suggestionsChanged();
}

// Built from what is on the display so each chip points at something real,
// then questions that fit any day, skipping ones about empty feeds.
QStringList Assistant::buildSuggestions() const
{
    const qint64 nowMs = m_store->now().toMSecsSinceEpoch();
    QStringList out;
    for (const QVariant &v : m_store->projects()) {
        if (v.toMap().value("status").toString() == QLatin1String("blocked")) {
            out << fit(tr("What's blocking "), v.toMap().value("name").toString(), QStringLiteral("?"));
            break;
        }
    }
    const QVariantMap mover = biggestMover(m_store, nowMs);
    if (!mover.isEmpty())
        out << moverQuestion(mover);
    const QVariantMap next = nextEvent(m_store, nowMs, kEventWindowMs);
    if (!next.isEmpty())
        out << fit(tr("What do I need for "), next.value("title").toString(), QStringLiteral("?"));
    const QString lead = leadHeadline(m_store);
    if (!lead.isEmpty())
        out << fit(tr("More on "), lead, QString());
    const QVariantMap brief = freshBrief(m_store, nowMs);
    if (!brief.value("agentName").toString().isEmpty())
        out << fit(tr("What did "), brief.value("agentName").toString(), tr(" just say?"));

    out << tr("Summarize my day");
    if (!m_store->upcoming().isEmpty())
        out << tr("What's next on my calendar?");
    if (!m_store->quotes().isEmpty())
        out << tr("How are the markets doing?");
    if (!m_store->metrics().isEmpty())
        out << tr("How are my metrics looking?");
    out << tr("Anything I should know?");
    return firstFour(out);
}

QStringList Assistant::suggestionsFor(const QString &screen) const
{
    return m_forScreen.value(screen, m_suggestions);
}

QStringList Assistant::buildSuggestionsFor(const QString &screen, const QStringList &general) const
{
    const qint64 nowMs = m_store->now().toMSecsSinceEpoch();
    // A highlight's own question, when it fits on a chip.
    auto highlightQuestion = [this](const QString &kind) {
        for (const QVariant &v : m_store->highlights()) {
            const QVariantMap h = v.toMap();
            if (h.value("kind").toString() == kind && h.value("question").toString().size() <= kMaxSuggestionChars)
                return h.value("question").toString();
        }
        return QString();
    };
    QString own;
    if (screen == QLatin1String("home")) {
        own = tr("Summarize my day");
    } else if (screen == QLatin1String("briefs")) {
        const QVariantMap brief = freshBrief(m_store, nowMs);
        own = !brief.value("agentName").toString().isEmpty() ? fit(tr("What did "), brief.value("agentName").toString(), tr(" just say?"))
              : !m_store->briefs().isEmpty()                 ? tr("What's the latest brief?")
                                                             : QString();
    } else if (screen == QLatin1String("markets")) {
        const QVariantMap mover = biggestMover(m_store, nowMs);
        own = !mover.isEmpty() ? moverQuestion(mover) : !m_store->quotes().isEmpty() ? tr("How are the markets doing?") : QString();
    } else if (screen == QLatin1String("metrics")) {
        own = highlightQuestion(QStringLiteral("metric"));
        if (own.isEmpty() && !m_store->metrics().isEmpty())
            own = tr("How are my metrics looking?");
    } else if (screen == QLatin1String("news")) {
        const QString lead = leadHeadline(m_store);
        own = !lead.isEmpty() ? fit(tr("More on "), lead, QString()) : !m_store->stories().isEmpty() ? tr("What's in the news today?") : QString();
    } else if (screen == QLatin1String("projects")) {
        // The blocked one first (projects are sorted blocked first), else what's next on an active one.
        for (const QVariant &v : m_store->projects()) {
            const QVariantMap p = v.toMap();
            const QString status = p.value("status").toString();
            if (status == QLatin1String("blocked"))
                own = fit(tr("What's blocking "), p.value("name").toString(), QStringLiteral("?"));
            else if (status == QLatin1String("active"))
                own = fit(tr("What's next for "), p.value("name").toString(), QStringLiteral("?"));
            if (!own.isEmpty())
                break;
        }
        if (own.isEmpty() && !m_store->projects().isEmpty())
            own = tr("How are my projects going?");
    } else if (screen == QLatin1String("boards")) {
        own = highlightQuestion(QStringLiteral("status"));
        if (own.isEmpty() && !m_store->dashboards().isEmpty())
            own = fit(tr("How's "), m_store->dashboards().first().toMap().value("title").toString(), tr(" looking?"));
    } else if (screen == QLatin1String("calendar")) {
        const QVariantMap next = nextEvent(m_store, nowMs, 0);
        own = !next.isEmpty() ? fit(tr("Prep me for "), next.value("title").toString(), QString()) : tr("What's next on my calendar?");
    }
    return firstFour(QStringList{own} + general);
}

void Assistant::setBusy(bool busy)
{
    if (m_busy == busy)
        return;
    m_busy = busy;
    emit busyChanged();
}

void Assistant::ask(const QString &text)
{
    send(text, QStringLiteral("chat"));
}

void Assistant::askQuick(const QString &text)
{
    send(text, QStringLiteral("quick"));
}

void Assistant::stop()
{
    if (!m_busy)
        return;
    ++m_generation; // ignore anything still on its way
    if (m_reply)
        m_reply->abort();
    m_reply = nullptr;
    const ChatModel::Message &m = m_messages.at(m_replyRow);
    const bool partial = !m.text.trimmed().isEmpty();
    finishReply(partial ? m.text : tr("Stopped."), partial, false);
}

void Assistant::reset()
{
    stop();
    m_messages.reset();
    m_replyRow = -1;
    m_replyText.clear();
    emit replyChanged();
}

// The conversation so far, oldest first, without the turn being answered.
QJsonArray Assistant::history() const
{
    QJsonArray out;
    const QList<ChatModel::Message> rows = m_messages.rows();
    // The last two rows are the question just asked and its empty reply.
    const int end = qMax(0, rows.size() - 2);
    const int start = qMax(0, end - kHistoryTurns);
    for (int i = start; i < end; ++i) {
        const ChatModel::Message &m = rows.at(i);
        if (m.text.trimmed().isEmpty())
            continue;
        out.append(QJsonObject{{"role", m.role}, {"text", m.text}});
    }
    return out;
}

void Assistant::send(const QString &text, const QString &mode)
{
    const QString question = text.trimmed();
    if (question.isEmpty())
        return;
    if (m_busy) {
        // The wake word wins over a reply still streaming; a typed message waits.
        if (mode != "quick")
            return;
        stop();
    }

    m_messages.append({QStringLiteral("user"), question, {}, false, false, mode});
    m_replyRow = m_messages.append({QStringLiteral("assistant"), QString(), {}, true, false, mode});
    m_replyMode = mode;
    m_replyText.clear();
    emit replyChanged();
    setBusy(true);
    emit replyStarted(mode);

    const int generation = ++m_generation;
    if (m_store->mode() != "live") {
        streamDemo(generation, question);
        return;
    }
    if (m_client->hasSession()) {
        request(generation, question, mode, false);
        return;
    }
    m_client->refreshSession([this, generation, question, mode](bool ok) {
        if (generation != m_generation)
            return;
        if (ok)
            request(generation, question, mode, false);
        else
            fail(tr("I couldn't reach McFly cloud just now. Try again in a moment."));
    });
}

void Assistant::request(int generation, const QString &question, const QString &mode, bool retried)
{
    QJsonObject body{{"message", question}, {"mode", mode}, {"stream", true}, {"history", history()}};
    if (!m_provider.isEmpty())
        body.insert("provider", m_provider);

    m_reply = m_client->streamFunction(
        "assistant", body,
        [this, generation](const QString &event, const QJsonObject &data) {
            if (generation == m_generation)
                onEvent(event, data);
        },
        [this, generation, question, mode, retried](const QString &error) {
            if (generation != m_generation || !m_busy)
                return; // superseded, or `done` / `error` already ended the turn
            m_reply = nullptr;
            const ChatModel::Message &m = m_messages.at(m_replyRow);
            const bool nothingYet = m.text.isEmpty();
            if (error.isEmpty()) {
                qWarning() << "assistant stream ended without a reply";
                fail(tr("Sorry, I lost the connection partway through. Try again?"));
                return;
            }
            const int status = httpStatus(error);
            if (!retried && nothingYet && status == 401) {
                // The access token expired between syncs: refresh once and resend.
                m_client->refreshSession([this, generation, question, mode](bool ok) {
                    if (generation != m_generation)
                        return;
                    if (ok)
                        request(generation, question, mode, true);
                    else
                        fail(tr("I couldn't reach McFly cloud just now. Try again in a moment."));
                });
                return;
            }
            qWarning() << "assistant failed:" << error;
            if (status == 403)
                fail(tr("The assistant isn't available for this display right now."));
            else if (status == 429 || status == 503)
                fail(tr("McFly is a little busy. Try again in a moment."));
            else
                fail(tr("I couldn't reach McFly cloud just now. Try again in a moment."));
        });
}

void Assistant::onEvent(const QString &event, const QJsonObject &data)
{
    if (!m_busy)
        return;
    if (event == "delta") {
        const QString text = data.value("text").toString();
        m_messages.appendText(m_replyRow, text);
        m_replyText += text;
        emit replyChanged();
    } else if (event == "done") {
        // It added to the day or checked something off: show it now, not at
        // the next sync.
        if (!data.value("changed").toArray().isEmpty())
            m_store->refresh();
        complete(data.value("reply").toString());
    } else if (event == "error") {
        const QString message = data.value("message").toString();
        qWarning() << "assistant stream error:" << message;
        fail(message.isEmpty() ? tr("Something went wrong on my side. Try again?") : message);
    }
}

void Assistant::complete(const QString &reply)
{
    QString text = reply.trimmed();
    if (text.isEmpty())
        text = m_replyText.trimmed().isEmpty() ? tr("I don't have an answer for that.") : m_replyText.trimmed();
    finishReply(text, false, true);
}

void Assistant::fail(const QString &message)
{
    // Keep a partial answer (marked as cut short); otherwise say what happened.
    const ChatModel::Message &m = m_messages.at(m_replyRow);
    const bool partial = !m.text.trimmed().isEmpty();
    finishReply(partial ? m.text : message, partial, true, true);
}

void Assistant::finishReply(const QString &text, bool failed, bool announce, bool error)
{
    m_reply = nullptr;
    m_messages.finish(m_replyRow, text, {}, failed);
    m_replyText = text;
    emit replyChanged();
    setBusy(false);
    if (!announce)
        return; // stopped on purpose: nothing to read out

    QString speechId;
    if (m_replyMode == "quick" && m_voice && m_voice->speakReplies() && m_voice->canSpeak())
        speechId = m_voice->speak(text);
    emit replyFinished(text, m_replyMode, speechId, error);
}

// ───────────────────────────── Conversations ─────────────────────────────

namespace {
// Lowercase words, apostrophes kept ("that's"), and without the name:
// Whisper writes "Thanks, McFly." as readily as "thanks".
QStringList spokenWords(const QString &text)
{
    QString t = text.toLower();
    t.replace(QChar(0x2019), QLatin1Char('\''));
    static const QRegularExpression nonWord(QStringLiteral("[^a-z0-9']+"));
    QStringList words;
    for (QString w : t.split(nonWord, Qt::SkipEmptyParts)) {
        while (w.startsWith(QLatin1Char('\'')))
            w.remove(0, 1);
        while (w.endsWith(QLatin1Char('\'')))
            w.chop(1);
        if (!w.isEmpty() && w != QLatin1String("mcfly"))
            words << w;
    }
    return words;
}

struct Phrase
{
    QStringList words;
    bool closes; // false: a filler, which closes nothing on its own ("okay", "no")
};
} // namespace

bool Assistant::isClosingRemark(const QString &heard)
{
    // A remark closes the conversation when it is made of these phrases and
    // nothing else, at least one of them a closing one: "okay, thanks",
    // "no, that's all for now", "thanks, bye". "Okay", "no" or "yes" alone
    // may answer something McFly asked, so they go to the assistant.
    static const QList<Phrase> phrases = [] {
        const char *const closing[] = {
            "thanks", "thank you", "thanks so much", "thank you so much", "thanks a lot",
            "thank you very much", "many thanks", "cheers", "that's all", "that's it",
            "that is all", "that is it", "that'll be all", "that's everything", "i'm done",
            "we're done", "done", "i'm good", "all good", "i'm all set", "all set", "never mind",
            "nevermind", "forget it", "nothing", "nothing else", "no thanks", "no thank you", "stop",
            "stop talking", "cancel", "enough", "be quiet", "quiet", "shut up", "bye", "bye bye",
            "goodbye", "good bye", "good night", "goodnight", "see you", "see you later",
            "talk later", "talk to you later", "later",
            // What Whisper writes for a moment of noise and nobody speaking.
            "thanks for watching", "thank you for watching",
        };
        const char *const fillers[] = {
            "ok", "okay", "alright", "all right", "oh", "well", "so", "um", "uh", "hmm", "great",
            "perfect", "cool", "nice", "awesome", "got it", "no", "nope", "nah", "yes", "yeah", "yep",
            "i think", "for now", "for today", "then",
        };
        QList<Phrase> out;
        for (const char *p : closing)
            out.append({QString::fromLatin1(p).split(QLatin1Char(' ')), true});
        for (const char *p : fillers)
            out.append({QString::fromLatin1(p).split(QLatin1Char(' ')), false});
        return out;
    }();

    const QStringList words = spokenWords(heard);
    if (words.isEmpty())
        return false;
    if (words == QStringList{QStringLiteral("you")})
        return true; // Whisper's other word for silence
    // reach[i]: the first i words are covered by phrases, 1 with fillers
    // only, 2 with a closing phrase among them (0: they aren't).
    QList<int> reach(words.size() + 1, 0);
    reach[0] = 1;
    for (qsizetype i = 0; i < words.size(); ++i) {
        if (reach[i] == 0)
            continue;
        for (const Phrase &p : phrases) {
            const qsizetype end = i + p.words.size();
            if (end > words.size())
                continue;
            bool match = true;
            for (qsizetype k = 0; k < p.words.size() && match; ++k)
                match = words.at(i + k) == p.words.at(k);
            if (match)
                reach[end] = qMax(reach[end], p.closes ? 2 : reach[i]);
        }
    }
    return reach.last() == 2;
}

bool Assistant::soundsLikeReply(const QString &heard, const QString &reply)
{
    // Two words or more, nearly all of them from the end of the reply: the
    // part that was still echoing round the room when the mic opened.
    const QStringList words = spokenWords(heard);
    if (words.size() < 2)
        return false;
    const QStringList said = spokenWords(reply);
    const QSet<QString> tail(said.end() - qMin<qsizetype>(said.size(), 15), said.end());
    qsizetype found = 0;
    for (const QString &w : words)
        found += tail.contains(w) ? 1 : 0;
    return found * 5 >= words.size() * 4;
}

// ───────────────────────────── Demo replies ─────────────────────────────

void Assistant::streamDemo(int generation, const QString &question)
{
    const QString answer = demoAnswer(question);
    // Word by word, every 30–60 ms, like a live reply.
    static const QRegularExpression wordEnd(QStringLiteral("(?<=\\s)"));
    const QStringList chunks = answer.split(wordEnd, Qt::SkipEmptyParts);

    QTimer::singleShot(kDemoThinkMs, this, [this, generation, chunks, answer]() {
        if (generation != m_generation)
            return;
        streamChunks(generation, chunks, 0, answer);
    });
}

void Assistant::streamChunks(int generation, const QStringList &chunks, int next, const QString &answer)
{
    if (generation != m_generation)
        return;
    if (next >= chunks.size()) {
        onEvent(QStringLiteral("done"), {{"reply", answer}});
        return;
    }
    onEvent(QStringLiteral("delta"), {{"text", chunks.at(next)}});
    const int delay = QRandomGenerator::global()->bounded(30, 61);
    QTimer::singleShot(delay, this, [this, generation, chunks, next, answer]() {
        streamChunks(generation, chunks, next + 1, answer);
    });
}

// The demo reply: intents first ("what's blocking", "prep me for", "more
// on"...), so a name inside one (an event called "Pulse review", a headline
// about Apple) doesn't send it to the topics below; then a symbol, a metric,
// the calendar and the topics, the way the questions people ask go.
QString Assistant::demoAnswer(const QString &question) const
{
    const QString q = question.toLower();
    static const QRegularExpression word(QStringLiteral("[^a-z0-9.^]+"));
    const QStringList words = q.split(word, Qt::SkipEmptyParts);

    if (q.contains(QLatin1String("prep me for")) || q.contains(QLatin1String("need for")) || q.contains(QLatin1String("prepare for"))
        || q.contains(QLatin1String("ready for")))
        return demoEvent(q);

    // A story: "More on …", "Tell me more about “…”".
    QString about = q.startsWith(QLatin1String("more on ")) ? subjectAfter(q, QStringLiteral("more on "))
                                                            : subjectAfter(q, QStringLiteral("tell me more about "));
    if (about.size() >= 4) {
        for (const QVariant &v : m_store->stories()) {
            const QVariantMap s = v.toMap();
            const QString headline = s.value("headline").toString();
            if (!headline.toLower().startsWith(about) && !headline.toLower().contains(about))
                continue;
            QString answer = sentence(headline);
            if (!s.value("takeaway").toString().isEmpty())
                answer += QLatin1Char(' ') + sentence(s.value("takeaway").toString());
            return answer + tr(" It's in %1, from %2.").arg(s.value("sectionName").toString(), s.value("sourceDomain").toString());
        }
    }

    if (q.contains(QLatin1String("blocking")) || q.contains(QLatin1String("blocked")) || q.contains(QLatin1String("next for"))
        || q.contains(QLatin1String("project"))) {
        const QString answer = demoProject(q);
        if (!answer.isEmpty())
            return answer;
    }

    if (q.contains(QLatin1String("summarize")) || q.contains(QLatin1String("summarise")) || q.contains(QLatin1String("my day")))
        return demoDay();

    // "What did Grok just say?": that agent's newest brief.
    if (q.contains(QLatin1String("just say")) || q.contains(QLatin1String("just post")) || q.contains(QLatin1String("just send"))) {
        QVariantMap brief = m_store->latestBrief();
        for (const QVariant &v : m_store->briefs()) {
            const QString agent = v.toMap().value("agentName").toString().toLower();
            if (!agent.isEmpty() && q.contains(agent)) {
                brief = v.toMap();
                break;
            }
        }
        if (brief.isEmpty())
            return tr("No briefs have come in yet.");
        return tr("From %1 at %2: %3. %4").arg(brief.value("agentName").toString(), brief.value("timeLabel").toString(),
                                                brief.value("title").toString(), brief.value("summary").toString());
    }

    // A metric by name ("What's behind the drop in Error rate?"), before the
    // symbols: a metric can share a word with a company.
    const bool behind = q.contains(QLatin1String("behind the"));
    for (const QVariant &v : m_store->metrics()) {
        const QString label = v.toMap().value("label").toString().toLower();
        if (behind && !label.isEmpty() && q.contains(label))
            return demoMetric(v.toMap());
    }

    // A board's status or a board by name.
    if (const QString board = demoBoard(q); !board.isEmpty())
        return board;

    // A symbol or a company named in the question.
    for (const QVariant &v : m_store->quotes()) {
        const QVariantMap quote = v.toMap();
        const QString symbol = quote.value("symbol").toString();
        const QString name = quote.value("name").toString();
        if (words.contains(symbol.toLower()) || (!name.isEmpty() && q.contains(name.toLower()))) {
            const QString who = name.isEmpty() ? symbol : name;
            if (!words.contains(QLatin1String("why"))) {
                QString answer = tr("%1 is at %2, %3 today.").arg(who, quote.value("priceLabel").toString(), quote.value("pctLabel").toString());
                if (!quote.value("note").toString().isEmpty())
                    answer += QLatin1Char(' ') + quote.value("note").toString();
                return answer;
            }
            // Why it moved: the agent's note, how big a move it is for this
            // stock, and where it sits in its recent range.
            const double pct = quote.value("change_pct").toDouble();
            QString answer = quote.value("flat").toBool()
                                 ? tr("%1 is flat today, at %2.").arg(who, quote.value("priceLabel").toString())
                                 : tr("%1 is %2 %3% today, at %4.").arg(who, pct > 0 ? tr("up") : tr("down"),
                                                                         QLocale().toString(qAbs(pct), 'f', 2), quote.value("priceLabel").toString());
            answer += QLatin1Char(' ') + (quote.value("note").toString().isEmpty() ? tr("No agent has said why yet.")
                                                                                   : sentence(quote.value("note").toString()));
            const double swing = quote.value("swingPct").toDouble();
            if (swing > 0 && qAbs(pct) / swing >= 1.5)
                answer += tr(" That's %1× its usual daily move.").arg(QLocale().toString(qAbs(pct) / swing, 'f', 1));
            const double position = quote.value("rangePos").toDouble();
            if (quote.value("history").toList().size() >= 5 && (position >= 0.95 || position <= 0.05))
                answer += (position >= 0.95 ? tr(" It's at the top of its recent range (%1–%2).") : tr(" It's at the bottom of its recent range (%1–%2)."))
                              .arg(quote.value("lowLabel").toString(), quote.value("highLabel").toString());
            return answer;
        }
    }

    for (const QVariant &v : m_store->metrics()) {
        const QString label = v.toMap().value("label").toString().toLower();
        if (label.size() >= 4 && q.contains(label))
            return demoMetric(v.toMap());
    }

    if (q.contains(QLatin1String("calendar")) || q.contains(QLatin1String("schedule")) || q.contains(QLatin1String("next on"))
        || q.contains(QLatin1String("meeting"))) {
        const QVariantList upcoming = m_store->upcoming();
        if (upcoming.isEmpty())
            return tr("Nothing's coming up on your calendar.");
        QStringList parts;
        for (int i = 0; i < qMin(3, int(upcoming.size())); ++i) {
            const QVariantMap e = upcoming.at(i).toMap();
            parts << (e.value("all_day").toBool() ? tr("%1, %2, all day").arg(e.value("title").toString(), inSentence(e.value("dayLabel").toString()))
                                                  : tr("%1, %2 at %3").arg(e.value("title").toString(), inSentence(e.value("dayLabel").toString()),
                                                                           e.value("startLabel").toString()));
        }
        return tr("Next: %1.").arg(parts.join(tr("; then ")));
    }

    if (q.contains(QLatin1String("metric"))) {
        QStringList parts;
        for (const QVariant &v : m_store->metrics()) {
            const QVariantMap m = v.toMap();
            parts << (m.value("hasDelta").toBool() ? QStringLiteral("%1 %2 (%3)").arg(m.value("label").toString(), m.value("valueLabel").toString(),
                                                                                         m.value("deltaLabel").toString())
                                                   : QStringLiteral("%1 %2").arg(m.value("label").toString(), m.value("valueLabel").toString()));
            if (parts.size() == 6)
                break;
        }
        if (parts.isEmpty())
            return tr("No metrics have come in yet.");
        QString answer = tr("Your metrics: %1.").arg(parts.join(QStringLiteral("; ")));
        QStringList standing;
        for (const QVariant &v : m_store->highlights())
            if (v.toMap().value("kind").toString() == QLatin1String("metric"))
                standing << v.toMap().value("title").toString();
        if (!standing.isEmpty())
            answer += tr(" Standing out: %1.").arg(standing.join(QStringLiteral("; ")));
        return answer;
    }

    if (q.contains("market") || q.contains("stock") || q.contains("portfolio") || q.contains("trading")) {
        QStringList parts;
        for (const QVariant &v : m_store->quotes()) {
            const QVariantMap quote = v.toMap();
            parts << QStringLiteral("%1 %2 (%3)").arg(quote.value("symbol").toString(), quote.value("priceLabel").toString(),
                                                      quote.value("pctLabel").toString());
        }
        return parts.isEmpty() ? tr("No quotes have come in yet.") : tr("Markets right now: %1.").arg(parts.join(QStringLiteral(", ")));
    }

    if (q.contains("news") || q.contains("stories") || q.contains("headline") || q.contains("pulse")) {
        const QVariantList stories = m_store->stories();
        if (stories.isEmpty())
            return tr("There's no Pulse report yet today.");
        QStringList parts;
        for (int i = 0; i < qMin(3, stories.size()); ++i)
            parts << stories.at(i).toMap().value("headline").toString();
        return tr("Top of today's Pulse: %1.").arg(parts.join(QStringLiteral("; ")));
    }

    // "Anything I should know?": what stands out, the way Home ranks it.
    if (q.contains(QLatin1String("should i know")) || q.contains(QLatin1String("anything")) || q.contains(QLatin1String("stand out"))
        || q.contains(QLatin1String("stands out"))) {
        QStringList titles;
        for (const QVariant &v : m_store->highlights()) {
            titles << v.toMap().value("title").toString();
            if (titles.size() == 3)
                break;
        }
        if (!titles.isEmpty())
            return tr("Here's what stands out: %1.").arg(titles.join(QStringLiteral("; ")));
    }

    if (q.contains("brief") || q.contains("update") || q.contains("latest") || q.contains("should i know") || q.contains("today")) {
        const QVariantMap brief = m_store->latestBrief();
        if (brief.isEmpty())
            return tr("No briefs have come in yet.");
        return tr("From %1 at %2: %3. %4").arg(brief.value("agentName").toString(), brief.value("timeLabel").toString(),
                                                brief.value("title").toString(), brief.value("summary").toString());
    }

    return tr("In demo mode I can tell you about the briefs, the markets, your metrics, projects, boards and calendar, "
              "and today's stories. Connect McFly cloud for the full assistant.");
}

// "Prep me for X" / "What do I need for X?": when and where, and anything on
// the display that mentions it.
QString Assistant::demoEvent(const QString &q) const
{
    QString subject;
    for (const QString &lead : {QStringLiteral("prep me for "), QStringLiteral("need for "), QStringLiteral("prepare for "), QStringLiteral("ready for ")})
        if (subject.isEmpty())
            subject = subjectAfter(q, lead);
    if (subject.startsWith(QLatin1String("the ")))
        subject = subject.mid(4);
    // The event named (its title in the question, or the question's words
    // starting it when a chip cut it short), one still to come first.
    QVariantMap pick, past;
    for (const QVariant &v : m_store->events()) {
        const QVariantMap e = v.toMap();
        const QString title = e.value("title").toString().toLower();
        if (title.isEmpty() || !(q.contains(title) || (subject.size() >= 6 && title.startsWith(subject))))
            continue;
        if (!e.value("past").toBool()) {
            pick = e;
            break;
        }
        past = e;
    }
    if (pick.isEmpty())
        pick = past;
    if (pick.isEmpty())
        pick = nextEvent(m_store, m_store->now().toMSecsSinceEpoch(), 0);
    if (pick.isEmpty())
        return tr("Nothing's coming up on your calendar.");

    const QString title = pick.value("title").toString();
    const QString day = inSentence(pick.value("dayLabel").toString());
    const QString time = pick.value("all_day").toBool() ? tr("all day") : pick.value("timeLabel").toString();
    QString answer = pick.value("past").toBool() ? tr("%1 was %2, %3").arg(title, day, time)
                     : pick.value("now").toBool() ? tr("%1 is on now, %2").arg(title, time)
                                                  : tr("%1 is %2, %3").arg(title, day, time);
    if (!pick.value("location").toString().isEmpty())
        answer += tr(", at %1").arg(pick.value("location").toString());
    answer += QLatin1Char('.');
    if (!pick.value("calendar").toString().isEmpty())
        answer += tr(" It's on your %1 calendar.").arg(pick.value("calendar").toString());
    if (!pick.value("description").toString().isEmpty())
        answer += QLatin1Char(' ') + sentence(pick.value("description").toString());

    // Related: a project or a brief's point that shares a word with it.
    QStringList keys;
    static const QRegularExpression split(QStringLiteral("[^a-z0-9]+"));
    for (const QString &w : title.toLower().split(split, Qt::SkipEmptyParts))
        if (w.size() >= 5)
            keys << w;
    auto mentions = [&keys](const QString &text) {
        const QString t = text.toLower();
        for (const QString &k : keys)
            if (t.contains(k))
                return true;
        return false;
    };
    for (const QVariant &v : m_store->projects()) {
        const QVariantMap p = v.toMap();
        if (!mentions(p.value("name").toString()))
            continue;
        answer += tr(" %1 is %2").arg(p.value("name").toString(), p.value("statusLabel").toString().toLower());
        answer += p.value("next_step").toString().isEmpty() ? QStringLiteral(".") : tr("; next: %1.").arg(p.value("next_step").toString());
        break;
    }
    for (const QVariant &v : m_store->briefs()) {
        const QVariantMap b = v.toMap();
        for (const QVariant &point : b.value("bullets").toList()) {
            if (!mentions(point.toString()))
                continue;
            return answer + tr(" From %1's %2: %3").arg(b.value("agentName").toString(), b.value("title").toString(), sentence(point.toString()));
        }
    }
    return answer;
}

// "What's blocking X?", "What's next for X?", "How are my projects going?".
// Empty when the question names no project and asks about none.
QString Assistant::demoProject(const QString &q) const
{
    const QVariantList projects = m_store->projects();
    QVariantMap named; // the longest name in the question
    for (const QVariant &v : projects) {
        const QString name = v.toMap().value("name").toString().toLower();
        if (!name.isEmpty() && q.contains(name) && name.size() > named.value("name").toString().size())
            named = v.toMap();
    }
    QString answer;
    if (named.isEmpty() && (q.contains(QLatin1String("blocking")) || q.contains(QLatin1String("blocked")))) {
        QStringList blocked;
        for (const QVariant &v : projects)
            if (v.toMap().value("status").toString() == QLatin1String("blocked"))
                blocked << v.toMap().value("name").toString();
        if (blocked.isEmpty())
            return tr("Nothing is blocked right now.");
        if (blocked.size() > 1)
            answer = tr("%1 projects are blocked: %2. ").arg(QString::number(blocked.size()), blocked.join(QStringLiteral(", ")));
        named = projects.first().toMap(); // blocked ones sort first
    }
    if (named.isEmpty()) {
        if (!q.contains(QLatin1String("project")))
            return {};
        QStringList parts;
        for (const QVariant &v : projects) {
            const QVariantMap p = v.toMap();
            parts << (p.value("hasProgress").toBool() ? tr("%1 (%2, %3%)").arg(p.value("name").toString(), p.value("statusLabel").toString().toLower(),
                                                                               QString::number(p.value("progress").toInt()))
                                                      : tr("%1 (%2)").arg(p.value("name").toString(), p.value("statusLabel").toString().toLower()));
        }
        return parts.isEmpty() ? tr("No projects have come in yet.") : tr("Your projects: %1.").arg(parts.join(QStringLiteral("; ")));
    }

    const QString name = named.value("name").toString();
    const QString next = named.value("next_step").toString();
    if (named.value("status").toString() == QLatin1String("blocked")) {
        answer += next.isEmpty() ? tr("%1 is blocked.").arg(name) : tr("%1 is blocked. What it needs next: %2").arg(name, sentence(next));
    } else {
        answer += named.value("hasProgress").toBool()
                      ? tr("%1 is %2, %3% done.").arg(name, named.value("statusLabel").toString().toLower(), QString::number(named.value("progress").toInt()))
                      : tr("%1 is %2.").arg(name, named.value("statusLabel").toString().toLower());
        if (!next.isEmpty())
            answer += tr(" Next: %1").arg(sentence(next));
    }
    const QVariantMap last = named.value("lastUpdate").toMap();
    if (!last.isEmpty())
        answer += tr(" The last update, %1: %2").arg(inSentence(last.value("whenLabel").toString()), sentence(last.value("text").toString()));
    return answer;
}

// "Summarize my day": what's left on the calendar, what stands out, the
// markets in a line and the latest brief.
QString Assistant::demoDay() const
{
    QStringList parts;
    QVariantList left;
    for (const QVariant &v : m_store->events()) {
        const QVariantMap e = v.toMap();
        if (e.value("day").toString() == m_store->today() && !e.value("past").toBool() && !e.value("all_day").toBool())
            left << e;
    }
    if (left.isEmpty())
        parts << tr("Your calendar is clear for the rest of the day.");
    else if (left.size() == 1)
        parts << tr("One more thing on the calendar today: %1 at %2.").arg(left.first().toMap().value("title").toString(),
                                                                           left.first().toMap().value("startLabel").toString());
    else
        parts << tr("%1 more things on the calendar today; next is %2 at %3.")
                     .arg(QString::number(left.size()), left.first().toMap().value("title").toString(), left.first().toMap().value("startLabel").toString());
    QStringList standing;
    for (const QVariant &v : m_store->highlights()) {
        const QVariantMap h = v.toMap();
        if (h.value("kind").toString() == QLatin1String("event"))
            continue; // the calendar line has it
        standing << h.value("title").toString();
        if (standing.size() == 3)
            break;
    }
    if (!standing.isEmpty())
        parts << tr("Standing out: %1.").arg(standing.join(QStringLiteral("; ")));
    const QString breadth = m_store->marketBreadth().value("label").toString();
    if (!breadth.isEmpty())
        parts << tr("Markets: %1.").arg(breadth);
    const QVariantMap brief = m_store->latestBrief();
    if (!brief.isEmpty())
        parts << tr("Latest from %1: %2.").arg(brief.value("agentName").toString(), brief.value("title").toString());
    return parts.join(QLatin1Char(' '));
}

// A board's status ("Why is Search down?") or a board ("How's Ops looking?")
// named in the question; empty when none is.
QString Assistant::demoBoard(const QString &q) const
{
    static const QRegularExpression split(QStringLiteral("[^a-z0-9]+"));
    const QStringList words = q.split(split, Qt::SkipEmptyParts);
    auto named = [&](const QString &label) {
        const QString l = label.toLower().simplified();
        return !l.isEmpty() && (l.contains(QLatin1Char(' ')) ? q.contains(l) : words.contains(l));
    };
    auto stateOf = [](const QVariantMap &w) {
        const QString state = w.value("state").toString(), label = w.value("label").toString();
        return state == QLatin1String("down")   ? tr("%1 is down").arg(label)
               : state == QLatin1String("warn") ? tr("%1 has a warning").arg(label)
               : state == QLatin1String("ok")   ? tr("%1 is OK").arg(label)
                                                : tr("%1 hasn't reported").arg(label);
    };
    const QVariantList boards = m_store->dashboards();
    for (const QVariant &bv : boards) {
        const QVariantMap board = bv.toMap();
        for (const QVariant &wv : board.value("widgets").toList()) {
            const QVariantMap w = wv.toMap();
            if (w.value("type").toString() != QLatin1String("status") || !named(w.value("label").toString()))
                continue;
            const QString detail = w.value("detail").toString();
            return tr("%1 on the %2 board").arg(stateOf(w), board.value("title").toString())
                   + (detail.isEmpty() ? QStringLiteral(".") : QStringLiteral(": ") + sentence(detail));
        }
    }
    for (const QVariant &bv : boards) {
        const QVariantMap board = bv.toMap();
        if (!named(board.value("title").toString()))
            continue;
        QStringList statuses, numbers;
        for (const QVariant &wv : board.value("widgets").toList()) {
            const QVariantMap w = wv.toMap();
            const QString type = w.value("type").toString();
            if (type == QLatin1String("status"))
                statuses << stateOf(w);
            else if (type == QLatin1String("metric"))
                numbers << (w.value("hasDelta").toBool() ? QStringLiteral("%1 %2 (%3)").arg(w.value("label").toString(), w.value("valueLabel").toString(),
                                                                                              w.value("deltaLabel").toString())
                                                         : QStringLiteral("%1 %2").arg(w.value("label").toString(), w.value("valueLabel").toString()));
            else if (type == QLatin1String("progress"))
                numbers << QStringLiteral("%1 %2").arg(w.value("label").toString(), w.value("valueLabel").toString());
        }
        QStringList parts;
        if (!statuses.isEmpty())
            parts << statuses.join(QStringLiteral(", "));
        if (!numbers.isEmpty())
            parts << numbers.join(QStringLiteral(", "));
        return parts.isEmpty() ? tr("The %1 board is empty.").arg(board.value("title").toString())
                               : tr("%1: %2.").arg(board.value("title").toString(), parts.join(QStringLiteral("; ")));
    }
    return {};
}

// A metric: its value and change, the agent's note, its usual, and whether
// the change is good news for it.
QString Assistant::demoMetric(const QVariantMap &m) const
{
    QString answer = tr("%1 is %2").arg(m.value("label").toString(), m.value("valueLabel").toString());
    if (m.value("hasDelta").toBool())
        answer += tr(", %1 since the last reading").arg(m.value("deltaLabel").toString());
    answer += QLatin1Char('.');
    if (!m.value("note").toString().isEmpty())
        answer += QLatin1Char(' ') + sentence(m.value("note").toString());
    if (!m.value("usualLabel").toString().isEmpty())
        answer += (m.value("anomaly").toBool() ? tr(" That's well off its usual of about %1.") : tr(" Its usual is about %1."))
                      .arg(m.value("usualLabel").toString());
    if (m.value("trend").toString() != QLatin1String("flat"))
        answer += m.value("good").toBool() ? tr(" That's the good direction for it.") : tr(" That's the wrong direction for it.");
    return answer;
}
