#pragma once

#include <QDateTime>
#include <QHash>
#include <QObject>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>

class FeedStore;
class SupabaseClient;
class VoiceClient;

// The household thread for the Messages screen (the messages table,
// migration 20261103000010): what the people at home write here goes to the
// person's phone, and the person's replies come back. One thread for every
// display in the house.
//
// The display writes only through send_message() (who is writing: one of
// `names`, or the display itself) and read_messages() (the person's replies
// it has shown). It reads the thread once, then only what changed
// (`updated_at`, a little overlap so a late commit isn't missed): every few
// seconds while Messages is open or a reply may be on its way, else every
// half minute. A message from the person seen here for the first time is
// `arrived`; Main.qml shows it on a card and reads it out.
//
// `thread` is ready to draw, oldest first: { id, home (written here, at
// home), name, body, timeLabel, dayLabel (on the first of each day, else
// ""), runStart (a new writer, or ten minutes on), status (under home's
// newest message and any that failed: "Sending…", "Sent", "On Dad's
// phone", "Seen by Dad", or why it didn't go), failed, pending, hasAudio,
// audioLabel ("0:12"), caption (a voice note's words, "" for the server's
// own "🎤 Voice note · 0:12") }.
//
// Voice notes (20261104000020): recorded through the voice service
// (startRecording → finishRecording, at most 30 s), uploaded to the
// `voice-notes` bucket in this display's folder, then sent; played through
// the voice service from bytes read here (it never reaches the network).
class MessageStore : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList thread READ thread NOTIFY threadChanged)
    // Who writes here (platform_settings.message_names); empty: the display itself.
    Q_PROPERTY(QStringList names READ names NOTIFY namesChanged)
    // The name picked for the next message ("" until someone picks).
    Q_PROPERTY(QString writer READ writer WRITE setWriter NOTIFY writerChanged)
    // What's typed and not sent, kept while the screen goes idle.
    Q_PROPERTY(QString draft READ draft WRITE setDraft NOTIFY draftChanged)
    // Messages is on screen: replies are marked read as they come, and it polls fast.
    Q_PROPERTY(bool open READ isOpen WRITE setOpen NOTIFY openChanged)
    // The person's replies not yet shown on Messages.
    Q_PROPERTY(int unread READ unread NOTIFY threadChanged)
    // What the person is called (their newest reply's name), for "On Dad's phone".
    Q_PROPERTY(QString personName READ personName NOTIFY threadChanged)
    // Messages a tap sends (the screen's quick row).
    Q_PROPERTY(QStringList quickMessages READ quickMessages CONSTANT)
    // live, demo, or "" (pairing, or a backend without messages).
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)
    // Away mode (platform_settings.away_*, 20261104000010): the person is out,
    // so the screen wakes to Messages. "Still away" is decided here against
    // away_until, each minute. awayLabel: "Dad is out · back around 6:00 pm".
    Q_PROPERTY(bool away READ away NOTIFY awayChanged)
    Q_PROPERTY(QString awayLabel READ awayLabel NOTIFY awayChanged)
    Q_PROPERTY(QString awayNote READ awayNote NOTIFY awayChanged)
    // For the away screen's header: who ("Dad"), when they're back ("Back
    // around 6:00 pm", "Back Thursday around 6:00 pm"; "Out since 3:10 pm"
    // with no time), and how long till then ("1:42:10", "42:10", "2 days
    // 4 h"; "" with no time), each second while Messages is open.
    Q_PROPERTY(QString awayName READ awayName NOTIFY awayChanged)
    Q_PROPERTY(QString awayBack READ awayBack NOTIFY awayChanged)
    Q_PROPERTY(QString awayCountdown READ awayCountdown NOTIFY awayCountdownChanged)
    // Voice notes: the voice service can record and play them here.
    Q_PROPERTY(bool canRecord READ canRecord NOTIFY voiceChanged)
    Q_PROPERTY(bool canPlay READ canPlay NOTIFY voiceChanged)
    // A voice note is being recorded for this screen.
    Q_PROPERTY(bool recording READ recording NOTIFY recordingChanged)
    // The message whose voice note is playing, or "".
    Q_PROPERTY(QString playingId READ playingId NOTIFY playingChanged)

public:
    MessageStore(SupabaseClient *client, FeedStore *store, VoiceClient *voice = nullptr, QObject *parent = nullptr);

    QVariantList thread() const { return m_thread; }
    QStringList names() const { return m_names; }
    QString writer() const { return m_writer; }
    void setWriter(const QString &writer);
    QString draft() const { return m_draft; }
    void setDraft(const QString &draft);
    bool isOpen() const { return m_open; }
    void setOpen(bool open);
    int unread() const { return m_unread; }
    QString personName() const { return m_personName; }
    QStringList quickMessages() const;
    bool available() const { return m_available; }
    bool away() const { return m_away.value("away").toBool(); }
    QString awayLabel() const { return m_away.value("label").toString(); }
    QString awayNote() const { return m_away.value("note").toString(); }
    QString awayName() const { return m_away.value("name").toString(); }
    QString awayBack() const { return m_away.value("back").toString(); }
    QString awayCountdown() const { return m_countdownText; }
    bool canRecord() const;
    bool canPlay() const;
    bool recording() const { return m_recording; }
    QString playingId() const { return m_playingId; }

    // Sends `text` as `writer` (or the display): it shows at once as
    // "Sending…" and joins the thread once the server has it, or stays with
    // why it didn't go and can be tried again. Blank: false, nothing sent.
    Q_INVOKABLE bool send(const QString &text);
    Q_INVOKABLE void retry(const QString &localId);
    Q_INVOKABLE void discard(const QString &localId);
    // A voice note, as `writer`: starts recording (false if it can't), then
    // finishRecording() sends it, or the 30 s running out does;
    // cancelRecording() drops it.
    Q_INVOKABLE bool startRecording();
    Q_INVOKABLE void finishRecording();
    Q_INVOKABLE void cancelRecording();
    // Away mode from here (device_set_away, 20261104000030): on for
    // `minutes` (0: till it's turned off), or off. Anyone at the screen may;
    // the banner follows once the server has it.
    Q_INVOKABLE void setAway(bool away, int minutes = 0);
    // Plays a message's voice note (or stops it, if it's the one playing).
    Q_INVOKABLE void play(const QString &id);
    Q_INVOKABLE void stopPlaying();
    // Sends a recorded voice note (16 kHz mono WAV) as `name`, as send() a text.
    void sendVoiceNote(const QByteArray &wav, int ms, const QString &name);
    // The person's replies up to now have been seen (Messages is open, or the card was).
    Q_INVOKABLE void markRead();
    // Reads what changed now, apart from the timer.
    Q_INVOKABLE void refresh();

    // Rows as the server has them (snake_case), plus messages on their way
    // ({ localId, body, name, createdMs, failure }), shaped for the screen at
    // `now`. A pure function, so tests can check it.
    static QVariantList shape(const QVariantList &rows, const QVariantList &pending, const QDateTime &now,
                              const QString &personName);
    // What a voice note says without a caption, as send_message writes it.
    static QString voiceNoteLabel(int ms);
    // "Today", "Yesterday", the weekday within a week, else "Oct 12".
    static QString dayLabel(const QDate &day, const QDate &today);
    // Away mode from a platform_settings row at `now`: { away, name, label,
    // note, back, untilMs }. Not away without away_since, or once
    // away_until has passed.
    static QVariantMap awayState(const QVariantMap &settings, const QDateTime &now);
    // What's left, for the countdown: "1:42:10", "42:10", "0:09"; a day or
    // more "2 days 4 h".
    static QString countdown(qint64 msLeft);
    // The platform_settings row as read (the names and away mode); tests set it.
    void applySettings(const QVariantMap &settings);

    // Tests: how often it polls, open and not.
    void setPollIntervals(int fastMs, int slowMs);
    // Tests and the demo: how soon the demo's reply comes.
    void setDemoReplyMs(int ms) { m_demoReplyMs = ms; }

signals:
    void threadChanged();
    void namesChanged();
    void writerChanged();
    void draftChanged();
    void openChanged();
    void availableChanged();
    void awayChanged();
    void awayCountdownChanged();
    void voiceChanged();
    void recordingChanged();
    void playingChanged();
    // Something to tell whoever's at the screen ("That was too short to send").
    void notice(const QString &message);
    // A reply from the person, seen for the first time: { id, name, body,
    // timeLabel, audio (it's a voice note) }.
    void arrived(const QVariantMap &message);

private:
    void onModeChanged();
    void loadDemo();
    void poll();
    void loadNames();
    void updateAway();
    void tickCountdown();
    void merge(const QVariantList &rows, bool announce);
    void rebuild();
    void schedule();
    void deliver(const QString &localId);
    void startPlaying(const QString &id, const QByteArray &wav);
    void setRecording(bool on);
    QDateTime now() const;

    SupabaseClient *m_client;
    FeedStore *m_store;
    VoiceClient *m_voice;
    bool m_recording = false;
    QString m_recordingName;     // who started the recording
    QString m_playingId;         // the message playing
    QString m_playingSpeechId;   // the voice service's id for it
    QHash<QString, QByteArray> m_audio; // voice notes' WAVs, by message id
    QString m_mode;
    int m_generation = 0;
    bool m_available = false;
    bool m_loaded = false;      // the first full read is in
    bool m_polling = false;     // a request is out
    bool m_oldColumns = false;  // the backend predates voice notes: no audio_* to ask for
    QDateTime m_cursor;         // the newest updated_at seen
    QHash<QString, QVariantMap> m_rows; // by id
    QVariantList m_pending;     // { localId, body, name, createdMs, failure, audio?, audioMs?, audioPath? }
    QVariantList m_thread;
    QStringList m_names;
    QVariantMap m_settings; // the away_* columns as read
    int m_awayWrites = 0;   // setAway()s sent and landed: a settings read from before one is older
    QVariantMap m_away;     // awayState(m_settings, now)
    QString m_countdownText;
    QTimer m_countdown;     // each second, while away till a time and open
    QString m_writer;
    QString m_draft;
    bool m_open = false;
    int m_unread = 0;
    QString m_personName;
    QTimer m_timer;
    int m_fastMs = 5000;
    int m_slowMs = 30000;
    qint64 m_fastUntilMs = 0;   // after a send: fast for a while, a reply may be coming
    int m_demoReplyMs = 4000;
    int m_localIds = 0;
};
