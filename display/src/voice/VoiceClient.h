#pragma once

#include <QObject>
#include <QTimer>
#include <QUrl>
#include <QWebSocket>

// Connection to the on-device voice service (voice/, PLATFORM_SPEC.md §5):
// wake word, push-to-talk, speech-to-text and text-to-speech. Audio never
// leaves the Pi; the display only ever sees the final transcript.
//
// The service may start after the display, restart, or not be installed at
// all, so the client keeps retrying every few seconds and the UI checks
// `available` before offering voice.
class VoiceClient : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)
    // idle | listening | transcribing | speaking ("idle" while unavailable)
    Q_PROPERTY(QString state READ state NOTIFY stateChanged)
    // Microphone level 0..1 while listening.
    Q_PROPERTY(qreal level READ level NOTIFY levelChanged)
    Q_PROPERTY(bool wakewordEnabled READ wakewordEnabled WRITE setWakewordEnabled NOTIFY wakewordEnabledChanged)
    Q_PROPERTY(QString wakewordName READ wakewordName NOTIFY infoChanged)
    // The latest transcript; cleared when a new listening turn starts.
    Q_PROPERTY(QString transcript READ transcript NOTIFY transcriptChanged)

    // Extras for the settings sheet and the reply flow.
    Q_PROPERTY(QString wakewordLabel READ wakewordLabel NOTIFY infoChanged) // "Hey Jarvis"
    Q_PROPERTY(bool canSpeak READ canSpeak NOTIFY infoChanged)              // service has TTS
    Q_PROPERTY(bool canTranscribe READ canTranscribe NOTIFY infoChanged)    // service has STT
    Q_PROPERTY(QString micName READ micName NOTIFY infoChanged)             // the open mic, "" for none
    // The spoken replies' Kokoro voice (af_heart, af_bella, am_michael,
    // am_fenrir; "" when another engine speaks), speed, and the wake word's
    // model, as the service reports them.
    Q_PROPERTY(QString voiceId READ voiceId NOTIFY infoChanged)
    Q_PROPERTY(qreal speechSpeed READ speechSpeed NOTIFY infoChanged)
    Q_PROPERTY(QString wakewordModel READ wakewordModel NOTIFY infoChanged)
    Q_PROPERTY(QString url READ urlString CONSTANT)
    // Read quick answers out loud (QSettings voice/speakReplies, default on).
    Q_PROPERTY(bool speakReplies READ speakReplies WRITE setSpeakReplies NOTIFY speakRepliesChanged)

public:
    explicit VoiceClient(const QUrl &url, QObject *parent = nullptr);
    ~VoiceClient() override;

    void start();
    void setRetryInterval(int ms) { m_retry.setInterval(ms); }

    bool available() const { return m_available; }
    QString state() const { return m_state; }
    qreal level() const { return m_level; }
    bool wakewordEnabled() const { return m_wakewordEnabled; }
    QString wakewordName() const { return m_wakewordName; }
    QString wakewordLabel() const;
    QString transcript() const { return m_transcript; }
    bool canSpeak() const { return m_tts; }
    bool canTranscribe() const { return m_stt; }
    QString micName() const { return m_micName; }
    QString voiceId() const { return m_voiceId; }
    qreal speechSpeed() const { return m_speechSpeed; }
    QString wakewordModel() const { return m_wakewordModel; }
    QString urlString() const { return m_url.toString(); }
    bool speakReplies() const { return m_speakReplies; }
    void setSpeakReplies(bool on);

    // Push-to-talk: a listening turn without the wake word.
    Q_INVOKABLE void listen();
    Q_INVOKABLE void cancel();
    // Returns the id the service echoes in `spoken`, or "" if nothing was sent.
    Q_INVOKABLE QString speak(const QString &text);
    Q_INVOKABLE void stopSpeaking();
    Q_INVOKABLE void setWakewordEnabled(bool enabled);
    // Any of: voice (a Kokoro voice id), speed (0.5..2), wakewordModel. The
    // service answers with a fresh hello carrying what it applied.
    Q_INVOKABLE void setVoiceOptions(const QString &voice, qreal speed, const QString &wakewordModel);

signals:
    void availableChanged();
    void stateChanged();
    void levelChanged();
    void wakewordEnabledChanged();
    void infoChanged();
    void transcriptChanged();
    void speakRepliesChanged();

    // A listening turn started: source is "wakeword" or "button".
    void woke(const QString &source);
    // Final, non-empty transcript.
    void heard(const QString &text);
    // The turn ended with an empty transcript (nothing was heard).
    void heardNothing();
    // Speech with this id finished or was stopped.
    void spoken(const QString &id);
    void errorOccurred(const QString &message);

private:
    void connectNow();
    void scheduleRetry();
    void onConnected();
    void onDisconnected();
    void onMessage(const QString &text);
    bool send(const QJsonObject &message);
    void setAvailable(bool available);
    void setState(const QString &state);
    void setLevel(qreal level);
    void setTranscript(const QString &text);

    QUrl m_url;
    QWebSocket m_socket;
    QTimer m_retry;
    QTimer m_connectTimeout;
    bool m_loggedFailure = false;

    bool m_available = false;
    QString m_state = QStringLiteral("idle");
    qreal m_level = 0;
    bool m_wakewordEnabled = false;
    QString m_wakewordName;
    QString m_micName;
    QString m_voiceId;
    qreal m_speechSpeed = 1.0;
    QString m_wakewordModel;
    bool m_tts = false;
    bool m_stt = false;
    QString m_transcript;
    bool m_speakReplies = true;
    int m_nextSpeechId = 1;
};
