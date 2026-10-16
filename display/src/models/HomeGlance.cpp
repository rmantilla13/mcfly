#include "models/HomeGlance.h"

#include "models/FeedStore.h"

#include <QtMath>
#include <algorithm>

namespace {

QString sentenceCase(QString s)
{
    if (!s.isEmpty())
        s[0] = s.at(0).toUpper();
    return s;
}

// A title as the end of a sentence: no doubled full stop.
QString endSentence(QString s)
{
    s = s.trimmed();
    if (!s.isEmpty() && !QStringLiteral(".!?").contains(s.back()))
        s += QLatin1Char('.');
    return s;
}

// "a", "a, and b", "a, b, and c": independent clauses, so the comma stays.
QString joinClauses(const QStringList &parts)
{
    if (parts.size() <= 1)
        return parts.value(0);
    return HomeGlance::tr("%1, and %2").arg(parts.mid(0, parts.size() - 1).join(QStringLiteral(", ")), parts.last());
}

QString minutesLabel(qint64 minutes)
{
    return minutes == 1 ? HomeGlance::tr("1 minute") : HomeGlance::tr("%1 minutes").arg(minutes);
}

} // namespace

HomeGlance::HomeGlance(FeedStore *store, QObject *parent)
    : QObject(parent)
    , m_store(store)
{
    if (m_store) {
        connect(m_store, &FeedStore::dataChanged, this, &HomeGlance::refresh);
        connect(m_store, &FeedStore::todayChanged, this, &HomeGlance::refresh);
    }
    m_tick.setInterval(30 * 1000);
    connect(&m_tick, &QTimer::timeout, this, &HomeGlance::refresh);
    m_tick.start();
    refresh();
}

void HomeGlance::refresh()
{
    Feed feed;
    if (m_store) {
        feed.upcoming = m_store->upcoming();
        feed.projects = m_store->projects();
        feed.quotes = m_store->quotes();
        feed.latestBrief = m_store->latestBrief();
        feed.news = m_store->news();
        feed.displayName = m_store->displayName();
    }
    const QVariantMap summary = compose(feed, QDateTime::currentDateTime());
    if (summary == m_summary)
        return;
    m_summary = summary;
    emit summaryChanged();
}

QVariantMap HomeGlance::compose(const Feed &feed, const QDateTime &now)
{
    const int hour = now.time().hour();
    // As Home's greeting says it (HomeScreen.qml).
    QString greeting = hour < 5 ? tr("Good night") : hour < 12 ? tr("Good morning") : hour < 18 ? tr("Good afternoon") : tr("Good evening");
    if (!feed.displayName.isEmpty() && feed.displayName != QLatin1String("McFly"))
        greeting = tr("%1, %2").arg(greeting, feed.displayName);
    const qint64 nowMs = now.toMSecsSinceEpoch();

    QStringList clauses; // the headline: what matters now
    QStringList lines;   // the detail: what came in
    QStringList chips;   // questions to tap, the specific ones first
    auto ask = [&chips](const QString &question) {
        if (chips.size() < 3 && !chips.contains(question))
            chips << question;
    };

    // What's on now, else the next timed event (all-day ones don't start).
    // From the times, not Store's flags: those are as of the last sync.
    QVariantMap next;
    bool onNow = false;
    for (const QVariant &v : feed.upcoming) {
        const QVariantMap e = v.toMap();
        const qint64 start = e.value("startMs").toLongLong();
        const qint64 end = qMax(start, e.value("endMs").toLongLong());
        if (e.value("all_day").toBool() || end < nowMs)
            continue;
        next = e;
        onNow = start <= nowMs;
        break;
    }
    if (!next.isEmpty()) {
        const QString title = next.value("title").toString();
        // "3:30 pm" stays on one line in the big type.
        const QString at = next.value("startLabel").toString().replace(QLatin1Char(' '), QChar(0x00A0));
        const QDateTime start = QDateTime::fromMSecsSinceEpoch(next.value("startMs").toLongLong());
        const qint64 minutes = qMax<qint64>(0, (nowMs <= start.toMSecsSinceEpoch() ? now.secsTo(start) + 59 : 0) / 60);
        if (onNow)
            clauses << tr("%1 is on now").arg(title);
        else if (start.date() == now.date() && minutes <= 1)
            clauses << tr("%1 is about to start").arg(title);
        else if (start.date() == now.date() && minutes < 60)
            clauses << tr("%1 is in %2").arg(title, minutesLabel(minutes));
        else if (start.date() == now.date())
            clauses << tr("%1 is at %2").arg(title, at);
        else if (start.date() == now.date().addDays(1))
            clauses << tr("tomorrow starts with %1 at %2").arg(title, at);
        else
            clauses << tr("%1 is next, on %2").arg(title, next.value("dayLabel").toString());
        ask(title.size() <= 20 ? tr("What's on after %1?").arg(title) : tr("What else is on today?"));
    }

    // Anything blocked (Store puts them first).
    QVariantList blocked;
    for (const QVariant &v : feed.projects) {
        if (v.toMap().value("status").toString() == QLatin1String("blocked"))
            blocked << v;
    }
    if (!blocked.isEmpty()) {
        const QString first = blocked.first().toMap().value("name").toString();
        if (blocked.size() == 1)
            clauses << tr("%1 is blocked").arg(first);
        else if (blocked.size() == 2)
            clauses << tr("%1 and %2 are blocked").arg(first, blocked.at(1).toMap().value("name").toString());
        else
            clauses << tr("%1 and %2 others are blocked").arg(first).arg(blocked.size() - 1);
        ask(tr("What's blocking %1?").arg(first));
    }

    // The markets, if something moved: 1% or more, biggest first.
    QVariantList movers;
    for (const QVariant &v : feed.quotes) {
        const QVariantMap q = v.toMap();
        if (!q.value("flat").toBool() && qAbs(q.value("change_pct").toDouble()) >= 1.0)
            movers << q;
    }
    std::stable_sort(movers.begin(), movers.end(), [](const QVariant &a, const QVariant &b) {
        return qAbs(a.toMap().value("change_pct").toDouble()) > qAbs(b.toMap().value("change_pct").toDouble());
    });
    while (movers.size() > 3)
        movers.removeLast();
    if (!movers.isEmpty()) {
        const QVariantMap top = movers.first().toMap();
        const double pct = top.value("change_pct").toDouble();
        const QString symbol = top.value("symbol").toString();
        const QString amount = QString::number(qAbs(pct), 'f', 1) + QLatin1Char('%');
        clauses << (pct >= 0 ? tr("%1 is up %2").arg(symbol, amount) : tr("%1 is down %2").arg(symbol, amount));
        ask(pct >= 0 ? tr("Why is %1 up?").arg(symbol) : tr("Why is %1 down?").arg(symbol));
    }

    // The second line: the news lead and the latest brief.
    const QVariantMap hero = feed.news.value("hero").toMap();
    const QString report = feed.news.value("agentName").toString();
    const QString lead = hero.value("headline").toString().trimmed();
    if (!lead.isEmpty()) {
        lines << (feed.news.value("isToday").toBool() && !report.isEmpty()
                      ? tr("Today's %1 leads with %2").arg(report, endSentence(lead))
                      : tr("The news leads with %1").arg(endSentence(lead)));
        ask(report.isEmpty() ? tr("What's in the news?") : tr("Read me the %1").arg(report));
    }
    const QString briefTitle = feed.latestBrief.value("title").toString().trimmed();
    if (!briefTitle.isEmpty()) {
        const QString agent = feed.latestBrief.value("agentName").toString();
        lines << (agent.isEmpty() ? tr("The latest brief: %1").arg(endSentence(briefTitle))
                                  : tr("%1's latest: %2").arg(agent, endSentence(briefTitle)));
        ask(agent.isEmpty() ? tr("What's the latest brief?") : tr("What did %1 say?").arg(agent));
    }

    const bool quiet = clauses.isEmpty();
    QString headline;
    if (!quiet)
        headline = tr("%1. %2.").arg(greeting, sentenceCase(joinClauses(clauses)));
    else if (lines.isEmpty())
        headline = tr("%1. It's a quiet day so far.").arg(greeting);
    else
        headline = tr("%1. Nothing is next, and nothing needs you.").arg(greeting);
    if (lines.isEmpty() && quiet)
        lines << tr("Nothing is on the calendar and nothing is waiting on you. Ask me anything.");

    // Then the general ones, so there are always a few to tap.
    if (!feed.upcoming.isEmpty())
        ask(tr("What's on today?"));
    if (!feed.quotes.isEmpty())
        ask(tr("How are the markets?"));
    ask(tr("What can you do?"));

    return QVariantMap{{"greeting", greeting},
                       {"headline", headline},
                       {"detail", lines.join(QLatin1Char(' '))},
                       {"chips", chips},
                       {"quiet", quiet},
                       {"next", next},
                       {"blocked", blocked},
                       {"movers", movers}};
}
