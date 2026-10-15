#pragma once

#include <QJsonObject>
#include <QObject>
#include <QPointer>
#include <QVariantList>

#include "models/ChatModel.h"

class FeedStore;
class QNetworkReply;
class SupabaseClient;
class VoiceClient;

// The McFly assistant behind the "Ask McFly" panel and the wake word.
//
// Live mode streams from the `assistant` edge function, which grounds Claude
// in what the agents pushed: the latest briefs, the markets and today's
// stories. The display keeps the last few turns and sends them along as
// `history`; nothing is stored on the server. Demo mode answers a handful of
// questions from the sample feed, streamed the same way, so the screen is
// fully usable without a backend.
class Assistant : public QObject
{
    Q_OBJECT
    Q_PROPERTY(ChatModel *messages READ messages CONSTANT)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(QStringList suggestions READ suggestions CONSTANT)
    // The reply being written (or the last one): the quick answer card shows it.
    Q_PROPERTY(QString replyText READ replyText NOTIFY replyChanged)
    Q_PROPERTY(QString replyMode READ replyMode NOTIFY replyChanged)
    // Which model answers: "" follows the platform setting (Store.assistantProvider),
    // "claude" or "grok" pins it for this display. Remembered across restarts.
    Q_PROPERTY(QString provider READ provider WRITE setProvider NOTIFY providerChanged)
    Q_PROPERTY(QString effectiveProvider READ effectiveProvider NOTIFY providerChanged)

public:
    Assistant(SupabaseClient *client, FeedStore *store, VoiceClient *voice, QObject *parent = nullptr);

    ChatModel *messages() { return &m_messages; }
    bool busy() const { return m_busy; }
    QStringList suggestions() const;
    QString replyText() const { return m_replyText; }
    QString replyMode() const { return m_replyMode; }
    QString provider() const { return m_provider; }
    void setProvider(const QString &provider);
    QString effectiveProvider() const;

    // A chat message (the assistant panel, push-to-talk).
    Q_INVOKABLE void ask(const QString &text);
    // A short spoken answer (wake word). Speaks the reply when it's done if
    // spoken replies are on.
    Q_INVOKABLE void askQuick(const QString &text);
    // Stops the reply in flight, keeping whatever has arrived.
    Q_INVOKABLE void stop();
    // "New chat": clears the conversation.
    Q_INVOKABLE void reset();

    // The demo answer for a question (also used by tests).
    QString demoAnswer(const QString &question) const;

signals:
    void busyChanged();
    void replyChanged();
    void providerChanged();
    void replyStarted(const QString &mode);
    // speechId is the Voice.speak() id when the reply is being read out, else "".
    void replyFinished(const QString &text, const QString &mode, const QString &speechId);

private:
    void send(const QString &text, const QString &mode);
    void request(int generation, const QString &question, const QString &mode, bool retried);
    void onEvent(const QString &event, const QJsonObject &data);
    void complete(const QString &reply);
    void fail(const QString &message);
    void finishReply(const QString &text, bool failed, bool announce);
    void streamDemo(int generation, const QString &question);
    void streamChunks(int generation, const QStringList &chunks, int next, const QString &answer);
    void setBusy(bool busy);
    QJsonArray history() const;

    SupabaseClient *m_client;
    FeedStore *m_store;
    VoiceClient *m_voice;
    ChatModel m_messages;
    bool m_busy = false;
    QString m_provider;

    // The reply in flight. Callbacks from older requests carry a stale
    // generation and are ignored.
    int m_generation = 0;
    int m_replyRow = -1;
    QString m_replyMode = QStringLiteral("chat");
    QString m_replyText;
    QPointer<QNetworkReply> m_reply;
};
