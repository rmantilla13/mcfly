#pragma once

#include <QDateTime>
#include <QObject>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>

class FeedStore;

// The assistant-first Home's opening (qml/screens/HomeAssistant.qml): McFly
// speaks first. A greeting, one sentence on what matters now (what's on or
// next, what's blocked, the biggest move in the markets), a second line from
// the news and the latest brief, and a few questions to tap. Assembled from
// Store's rows, never written by a model: instant, free, and the same on
// every display. The rows it used ride along (next, blocked, movers) so the
// cards beside it show where each part came from.
class HomeGlance : public QObject
{
    Q_OBJECT
    // { greeting, headline, detail, chips: [question], quiet,
    //   next: event, blocked: [project], movers: [quote] }
    Q_PROPERTY(QVariantMap summary READ summary NOTIFY summaryChanged)

public:
    explicit HomeGlance(FeedStore *store, QObject *parent = nullptr);

    QVariantMap summary() const { return m_summary; }

    // What compose reads, in Store's shapes (FeedStore.h).
    struct Feed {
        QVariantList upcoming;  // the next few events, by start
        QVariantList projects;  // blocked first
        QVariantList quotes;
        QVariantMap latestBrief;
        QVariantMap news;       // the report on show, with its hero story
        QString displayName;    // "Good morning, Ricky" (not for the default "McFly")
    };
    static QVariantMap compose(const Feed &feed, const QDateTime &now);

signals:
    void summaryChanged();

private:
    void refresh();

    FeedStore *m_store;
    QVariantMap m_summary;
    QTimer m_tick; // "in 18 minutes" moves on with the clock
};
