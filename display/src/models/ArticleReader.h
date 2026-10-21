#pragma once

#include <QHash>
#include <QJsonObject>
#include <QObject>
#include <QVariantMap>

class SupabaseClient;

// The article behind a news story, for the News screen's open story: asks
// the `article` edge function (PLATFORM_SPEC §2.6) the first time a story
// opens and keeps the answer for the session. `article` is ready to draw:
// the summary (or the takeaway while there's none), the key points, the
// blocks in page order (lists already set as lines), the pictures and
// videos, Grok's picture of the story, and the small print. QML binds to it
// and formats nothing. While the function says a summary or picture is still
// under way (`pending`), the open story asks again every few seconds; a kept
// article is asked for again after a few hours.
class ArticleReader : public QObject
{
    Q_OBJECT
    // "" (nothing open), loading, ready or failed.
    Q_PROPERTY(QString state READ state NOTIFY changed)
    Q_PROPERTY(QVariantMap article READ article NOTIFY changed)
public:
    ArticleReader(SupabaseClient *client, bool demo, QObject *parent = nullptr);

    QString state() const { return m_state; }
    QVariantMap article() const { return m_article; }

    // A story map from Store.news (id, headline, takeaway, url, imageUrl,
    // sourceDomain, sectionName). Opening the one already open does nothing.
    Q_INVOKABLE void open(const QVariantMap &story);
    Q_INVOKABLE void close();

    // The function's article for a story, as the overlay draws it. A story
    // that's open gets it at once; any other keeps it for when it opens.
    void present(const QVariantMap &story, const QJsonObject &article);

    // The function's article (or none, with a note) shaped for the overlay.
    static QVariantMap shape(const QJsonObject &article, const QVariantMap &story, const QString &failure = {});
    // Demo mode's article: the story itself laid out as one.
    static QJsonObject demoArticle(const QVariantMap &story);

signals:
    void changed();

private:
    static QString keyOf(const QVariantMap &story);
    void set(const QString &state, const QVariantMap &article);
    void request(const QVariantMap &story, bool retried);
    void fail(const QVariantMap &story);

    SupabaseClient *m_client;
    bool m_demo;
    QString m_openKey;
    QString m_state;
    QVariantMap m_article;
    QHash<QString, QVariantMap> m_kept;
    QHash<QString, qint64> m_keptAt;
    int m_polls = 0;
};
