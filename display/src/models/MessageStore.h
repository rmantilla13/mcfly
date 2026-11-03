#pragma once

#include <QDateTime>
#include <QHash>
#include <QObject>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>

class FeedStore;
class SupabaseClient;

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
// phone", "Seen by Dad", or why it didn't go), failed, pending }.
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

public:
    MessageStore(SupabaseClient *client, FeedStore *store, QObject *parent = nullptr);

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

    // Sends `text` as `writer` (or the display): it shows at once as
    // "Sending…" and joins the thread once the server has it, or stays with
    // why it didn't go and can be tried again. Blank: false, nothing sent.
    Q_INVOKABLE bool send(const QString &text);
    Q_INVOKABLE void retry(const QString &localId);
    Q_INVOKABLE void discard(const QString &localId);
    // The person's replies up to now have been seen (Messages is open, or the card was).
    Q_INVOKABLE void markRead();
    // Reads what changed now, apart from the timer.
    Q_INVOKABLE void refresh();

    // Rows as the server has them (snake_case), plus messages on their way
    // ({ localId, body, name, createdMs, failure }), shaped for the screen at
    // `now`. A pure function, so tests can check it.
    static QVariantList shape(const QVariantList &rows, const QVariantList &pending, const QDateTime &now,
                              const QString &personName);
    // "Today", "Yesterday", the weekday within a week, else "Oct 12".
    static QString dayLabel(const QDate &day, const QDate &today);

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
    // A reply from the person, seen for the first time: { id, name, body, timeLabel }.
    void arrived(const QVariantMap &message);

private:
    void onModeChanged();
    void loadDemo();
    void poll();
    void loadNames();
    void merge(const QVariantList &rows, bool announce);
    void rebuild();
    void schedule();
    void deliver(const QString &localId);
    QDateTime now() const;

    SupabaseClient *m_client;
    FeedStore *m_store;
    QString m_mode;
    int m_generation = 0;
    bool m_available = false;
    bool m_loaded = false;      // the first full read is in
    bool m_polling = false;     // a request is out
    QDateTime m_cursor;         // the newest updated_at seen
    QHash<QString, QVariantMap> m_rows; // by id
    QVariantList m_pending;     // { localId, body, name, createdMs, failure }
    QVariantList m_thread;
    QStringList m_names;
    QString m_writer;
    QString m_draft;
    bool m_open = false;
    int m_unread = 0;
    QString m_personName;
    QTimer m_timer;
    int m_fastMs = 5000;
    int m_slowMs = 30000;
    qint64 m_fastUntilMs = 0;   // after a send: fast for a while, a reply may be coming
    int m_namesTick = 0;
    int m_demoReplyMs = 4000;
    int m_localIds = 0;
};
