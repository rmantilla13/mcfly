#include "ArticleReader.h"

#include "backend/SupabaseClient.h"

#include <QDateTime>
#include <QJsonArray>
#include <QLocale>
#include <QRegularExpression>
#include <QTimer>
#include <cmath>

// How long a kept article is shown before it is asked for again.
static constexpr qint64 kKeepMs = 6 * 3600 * 1000;
// While work is pending: ask again this often, at most this many times.
static constexpr int kPollMs = 6000;
static constexpr int kMaxPolls = 25;

namespace {

// The status in a SupabaseClient error ("... (HTTP 401)"), or 0.
int httpStatus(const QString &error)
{
    static const QRegularExpression re(QStringLiteral("\\(HTTP (\\d+)\\)$"));
    const auto m = re.match(error);
    return m.hasMatch() ? m.captured(1).toInt() : 0;
}

bool isWeb(const QString &url)
{
    return url.startsWith(QLatin1String("https://")) || url.startsWith(QLatin1String("http://"));
}

// Whose words the summary is, from the model that wrote it.
QString summaryBy(const QString &model)
{
    const QString m = model.toLower();
    if (m.startsWith(QLatin1String("claude")))
        return ArticleReader::tr("Summarized by Claude");
    if (m.startsWith(QLatin1String("grok")))
        return ArticleReader::tr("Summarized by Grok");
    if (m == QLatin1String("demo"))
        return ArticleReader::tr("A demo summary");
    return {};
}

} // namespace

ArticleReader::ArticleReader(SupabaseClient *client, bool demo, QObject *parent)
    : QObject(parent), m_client(client), m_demo(demo)
{
}

QString ArticleReader::keyOf(const QVariantMap &story)
{
    const QString id = story.value("id").toString();
    return id.isEmpty() ? story.value("item_key").toString() + QLatin1Char('|') + story.value("headline").toString() : id;
}

void ArticleReader::set(const QString &state, const QVariantMap &article)
{
    m_state = state;
    m_article = article;
    emit changed();
}

void ArticleReader::open(const QVariantMap &story)
{
    const QString key = keyOf(story);
    if (key == m_openKey && !m_state.isEmpty())
        return;
    m_openKey = key;
    m_polls = 0;
    if (m_kept.contains(key) && QDateTime::currentMSecsSinceEpoch() - m_keptAt.value(key) < kKeepMs) {
        set(QStringLiteral("ready"), m_kept.value(key));
        // Kept while the summary or picture was on its way: see if it's in.
        if (m_kept.value(key).value("pending").toBool() && !m_demo && m_client && m_client->hasSession())
            request(story, false);
        return;
    }
    if (m_demo) {
        present(story, demoArticle(story));
        return;
    }
    if (story.value("id").toString().isEmpty() || !m_client || !m_client->isConfigured()) {
        fail(story);
        return;
    }
    // The takeaway shows while the page is read and summarized.
    set(QStringLiteral("loading"), shape({}, story));
    if (m_client->hasSession()) {
        request(story, false);
        return;
    }
    m_client->refreshSession([this, story](bool ok) {
        if (ok)
            request(story, true);
        else
            fail(story);
    });
}

void ArticleReader::request(const QVariantMap &story, bool retried)
{
    const QString key = keyOf(story);
    m_client->callFunction(QStringLiteral("article"), QJsonObject{{"item_id", story.value("id").toString()}},
                           [this, key, story, retried](const QJsonDocument &doc, const QString &error) {
                               if (error.isEmpty()) {
                                   present(story, doc.object().value("article").toObject());
                                   return;
                               }
                               // The access token expired between syncs: refresh once and ask again.
                               if (!retried && httpStatus(error) == 401) {
                                   m_client->refreshSession([this, story](bool ok) {
                                       if (ok)
                                           request(story, true);
                                       else
                                           fail(story);
                                   });
                                   return;
                               }
                               qWarning("article: %s", qUtf8Printable(error));
                               fail(story);
                           });
}

void ArticleReader::fail(const QVariantMap &story)
{
    const QString key = keyOf(story);
    if (key != m_openKey)
        return;
    // Asking again for a summary or picture: what's shown stays.
    if (m_state == QLatin1String("ready") && m_article.value("pending").toBool()) {
        m_article.insert("pending", false);
        m_article.insert("working", QString());
        set(m_state, m_article);
        return;
    }
    set(QStringLiteral("failed"), shape({}, story, tr("The article couldn't be loaded.")));
}

void ArticleReader::close()
{
    m_openKey.clear();
    set(QString(), {});
}

void ArticleReader::present(const QVariantMap &story, const QJsonObject &article)
{
    const QString key = keyOf(story);
    const QVariantMap shaped = shape(article, story);
    m_kept.insert(key, shaped);
    m_keptAt.insert(key, QDateTime::currentMSecsSinceEpoch());
    if (key != m_openKey)
        return;
    set(QStringLiteral("ready"), shaped);
    // The summary or picture is still being made: ask again in a moment.
    if (shaped.value("pending").toBool() && m_client && m_polls < kMaxPolls) {
        ++m_polls;
        QTimer::singleShot(kPollMs, this, [this, key, story]() {
            if (key == m_openKey)
                request(story, false);
        });
    }
}

QVariantMap ArticleReader::shape(const QJsonObject &a, const QVariantMap &story, const QString &failure)
{
    const QString status = a.value("status").toString(QStringLiteral("unavailable"));
    const QString takeaway = story.value("takeaway").toString().trimmed();
    const QString source = story.value("sourceDomain").toString();

    QVariantList blocks;
    QVariantList media;
    int words = 0;
    for (const QJsonValue &v : a.value("blocks").toArray()) {
        const QJsonObject b = v.toObject();
        const QString type = b.value("type").toString();
        QVariantMap out{{"type", type}};
        if (type == QLatin1String("p") || type == QLatin1String("h") || type == QLatin1String("quote")) {
            const QString text = b.value("text").toString().trimmed();
            if (text.isEmpty())
                continue;
            out.insert("text", text);
            if (type == QLatin1String("quote"))
                out.insert("cite", b.value("cite").toString());
            ++words;
        } else if (type == QLatin1String("list")) {
            const bool ordered = b.value("ordered").toBool();
            QStringList lines;
            for (const QJsonValue &item : b.value("items").toArray()) {
                const QString text = item.toString().trimmed();
                if (!text.isEmpty())
                    lines << (ordered ? QStringLiteral("%1.  %2").arg(lines.size() + 1).arg(text) : QStringLiteral("•  ") + text);
            }
            if (lines.isEmpty())
                continue;
            out.insert("text", lines.join(QLatin1Char('\n')));
            ++words;
        } else if (type == QLatin1String("image") || type == QLatin1String("video")) {
            const QString url = b.value("url").toString();
            if (!isWeb(url))
                continue;
            out.insert("url", url);
            out.insert("caption", b.value("caption").toString());
            if (type == QLatin1String("video")) {
                const QString poster = b.value("poster").toString();
                const QString provider = b.value("provider").toString();
                out.insert("poster", isWeb(poster) ? poster : QString());
                out.insert("label", provider == QLatin1String("youtube") ? QStringLiteral("YouTube")
                                    : provider == QLatin1String("vimeo") ? QStringLiteral("Vimeo")
                                                                         : tr("Video"));
            }
            media << out;
        } else {
            continue; // a block this version doesn't draw
        }
        blocks << out;
    }

    // The summary: the assistant's, else a preview's own words, else the takeaway.
    QString summary = a.value("summary").toString().trimmed();
    bool isTakeaway = false;
    if (summary.isEmpty() && status == QLatin1String("partial") && takeaway.isEmpty() && !blocks.isEmpty()
        && blocks.first().toMap().value("type") == QLatin1String("p"))
        summary = blocks.first().toMap().value("text").toString();
    if (summary.isEmpty()) {
        summary = takeaway;
        isTakeaway = true;
    }
    QStringList points;
    for (const QJsonValue &p : a.value("points").toArray()) {
        const QString text = p.toString().trimmed();
        if (!text.isEmpty())
            points << text;
    }

    const int wordCount = a.value("word_count").toInt();
    const QString readingTime = status == QLatin1String("ready") && wordCount > 0
        ? tr("%1 min read").arg(qMax(1, int(std::lround(wordCount / 230.0))))
        : QString();

    QStringList byline;
    for (const QString &part : {a.value("byline").toString(), source.isEmpty() ? a.value("site_name").toString() : source}) {
        if (!part.trimmed().isEmpty())
            byline << part.trimmed();
    }
    const QDateTime published = QDateTime::fromString(a.value("published_at").toString(), Qt::ISODateWithMs);
    if (published.isValid())
        byline << QLocale().toString(published.toLocalTime().date(), QStringLiteral("MMM d"));

    const QString place = source.isEmpty() ? tr("The page") : source;
    QString note = failure;
    if (!note.isEmpty())
        note += QLatin1Char(' ') + tr("Scan the code to read it on your phone.");
    else if (status == QLatin1String("partial") && !a.isEmpty())
        note = tr("%1 shares only a preview. Scan the code to read it all.").arg(place);
    else if (status == QLatin1String("unavailable") && !a.isEmpty())
        note = tr("This page can't be shown here. Scan the code to read it on your phone.");

    const QString lead = a.value("lead_image").toString();
    const QString illustration = a.value("illustration_url").toString();
    // What is still on its way, said while the function works on it.
    const bool pending = a.value("pending").toBool();
    const QString working = !pending ? QString()
        : isTakeaway ? tr("Summarizing the story…")
        : !isWeb(illustration) ? tr("Grok is drawing a picture of it…")
                               : QString();
    return QVariantMap{
        {"status", a.isEmpty() ? QString() : status},
        {"hasFullStory", status == QLatin1String("ready") && words > 0},
        {"summary", summary},
        {"summaryIsTakeaway", isTakeaway},
        {"summaryBy", isTakeaway ? QString() : summaryBy(a.value("summary_model").toString())},
        {"points", points},
        {"blocks", blocks},
        {"media", media},
        {"readingTime", readingTime},
        {"byline", byline.join(QStringLiteral(" · "))},
        {"leadImage", isWeb(lead) ? lead : story.value("imageUrl").toString()},
        // Grok's picture of the story, shown with the summary.
        {"illustration", isWeb(illustration) ? illustration : QString()},
        {"illustrationBy", isWeb(illustration) ? tr("Drawn by Grok") : QString()},
        {"note", note},
        {"pending", pending},
        {"working", working},
    };
}

QJsonObject ArticleReader::demoArticle(const QVariantMap &story)
{
    const QString headline = story.value("headline").toString();
    const QString takeaway = story.value("takeaway").toString().isEmpty() ? headline : story.value("takeaway").toString();
    const QString source = story.value("sourceDomain").toString().isEmpty() ? tr("its source") : story.value("sourceDomain").toString();
    QJsonArray blocks{
        QJsonObject{{"type", "p"}, {"text", headline + QStringLiteral(". ") + takeaway}},
        QJsonObject{{"type", "p"},
                    {"text", tr("This is the demo, so the article is made up from the story itself. Connected to a McFly "
                                "backend, this page shows the article from %1: its own words, pictures and videos.").arg(source)}},
        QJsonObject{{"type", "h"}, {"text", tr("What it means")}},
        QJsonObject{{"type", "p"}, {"text", takeaway}},
        QJsonObject{{"type", "quote"}, {"text", tr("The full story and a summary appear here when a story is opened.")}},
        QJsonObject{{"type", "list"}, {"items", QJsonArray{tr("The summary comes first"), tr("Full story shows the article's text"),
                                                           tr("Pictures and videos stay in place")}}},
    };
    const QString image = story.value("imageUrl").toString();
    if (isWeb(image))
        blocks.insert(2, QJsonObject{{"type", "image"}, {"url", image}, {"caption", story.value("sectionName").toString()}});
    return QJsonObject{
        {"status", "ready"},
        {"site_name", source},
        {"lead_image", image},
        {"blocks", blocks},
        {"word_count", 180},
        {"summary", takeaway},
        {"points", QJsonArray{story.value("sectionName").toString() + QStringLiteral(": ") + headline, tr("Read on %1").arg(source)}},
        {"summary_model", "demo"},
    };
}
