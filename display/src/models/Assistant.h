#pragma once

#include <QHash>
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
// (or Grok) in what the agents pushed: briefs, markets, stories, projects,
// metrics, boards and the calendar. The display keeps the last few turns and
// sends them along as `history`; nothing is stored on the server. Demo mode
// answers from the sample feed, streamed the same way (every suggestion and
// highlight question among them), so the screen is fully usable without a
// backend.
class Assistant : public QObject
{
    Q_OBJECT
    Q_PROPERTY(ChatModel *messages READ messages CONSTANT)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    // Questions to offer, from what is on the display (lib/suggestions.ts):
    // the blocked project, the biggest mover, the next meeting, the Pulse's
    // lead, a fresh brief, then ones that fit any day. At most four, each at
    // most 42 characters so two chips share a row. suggestionsChanged also
    // fires when only a screen's own question (suggestionsFor) changed.
    Q_PROPERTY(QStringList suggestions READ suggestions NOTIFY suggestionsChanged)
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
    QStringList suggestions() const { return m_suggestions; }
    // The suggestions for one screen (a Main.qml screen name: home, briefs,
    // markets, metrics, news, projects, boards, calendar): its own question
    // first (the biggest mover on markets, the blocked project on projects,
    // ...), then the rest of `suggestions`. A binding should read
    // AI.suggestions too, to follow a sync. Any other name gives `suggestions`.
    Q_INVOKABLE QStringList suggestionsFor(const QString &screen) const;
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
    void suggestionsChanged();
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
    void updateSuggestions();
    QStringList buildSuggestions() const;
    QStringList buildSuggestionsFor(const QString &screen, const QStringList &general) const;
    // Demo replies by intent (see demoAnswer).
    QString demoEvent(const QString &q) const;
    QString demoProject(const QString &q) const;
    QString demoDay() const;
    QString demoBoard(const QString &q) const;
    QString demoMetric(const QVariantMap &metric) const;

    SupabaseClient *m_client;
    FeedStore *m_store;
    VoiceClient *m_voice;
    ChatModel m_messages;
    bool m_busy = false;
    QString m_provider;
    QStringList m_suggestions;
    QHash<QString, QStringList> m_forScreen; // suggestionsFor, by screen

    // The reply in flight. Callbacks from older requests carry a stale
    // generation and are ignored.
    int m_generation = 0;
    int m_replyRow = -1;
    QString m_replyMode = QStringLiteral("chat");
    QString m_replyText;
    QPointer<QNetworkReply> m_reply;
};
