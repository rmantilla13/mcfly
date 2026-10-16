#include "Assistant.h"

#include "backend/SupabaseClient.h"
#include "models/FeedStore.h"
#include "voice/VoiceClient.h"

#include <QJsonArray>
#include <QNetworkReply>
#include <QRandomGenerator>
#include <QRegularExpression>
#include <QSettings>
#include <QTimer>

namespace {
constexpr int kDemoThinkMs = 650;  // pause before a demo reply starts streaming
constexpr int kHistoryTurns = 10;  // earlier messages sent with a question

int httpStatus(const QString &error)
{
    static const QRegularExpression re(QStringLiteral("\\(HTTP (\\d+)\\)$"));
    const auto m = re.match(error);
    return m.hasMatch() ? m.captured(1).toInt() : 0;
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

QStringList Assistant::suggestions() const
{
    return {tr("What's the latest brief?"), tr("How are the markets?"), tr("What's in the news today?"),
            tr("Anything I should know?")};
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
    finishReply(partial ? m.text : message, partial, true);
}

void Assistant::finishReply(const QString &text, bool failed, bool announce)
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
    emit replyFinished(text, m_replyMode, speechId);
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

QString Assistant::demoAnswer(const QString &question) const
{
    const QString q = question.toLower();

    // A symbol or a company named in the question.
    for (const QVariant &v : m_store->quotes()) {
        const QVariantMap quote = v.toMap();
        const QString symbol = quote.value("symbol").toString();
        const QString name = quote.value("name").toString();
        static const QRegularExpression word(QStringLiteral("[^a-z0-9.^]+"));
        const QStringList words = q.split(word, Qt::SkipEmptyParts);
        if (words.contains(symbol.toLower()) || (!name.isEmpty() && q.contains(name.toLower()))) {
            QString answer = tr("%1 is at %2, %3 today.").arg(name.isEmpty() ? symbol : name, quote.value("priceLabel").toString(),
                                                              quote.value("pctLabel").toString());
            if (!quote.value("note").toString().isEmpty())
                answer += QLatin1Char(' ') + quote.value("note").toString();
            return answer;
        }
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

    if (q.contains("brief") || q.contains("update") || q.contains("latest") || q.contains("should i know") || q.contains("today")) {
        const QVariantMap brief = m_store->latestBrief();
        if (brief.isEmpty())
            return tr("No briefs have come in yet.");
        return tr("From %1 at %2: %3. %4").arg(brief.value("agentName").toString(), brief.value("timeLabel").toString(),
                                                brief.value("title").toString(), brief.value("summary").toString());
    }

    return tr("In demo mode I can tell you about the latest brief, the markets and today's stories. "
              "Connect McFly cloud for the full assistant.");
}
