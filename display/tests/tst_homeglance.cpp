// HomeGlance::compose: the assistant-first Home's opening lines, from feeds
// that are empty, partial and full (a new account shows the empty one).

#include "models/HomeGlance.h"

#include <QSet>
#include <QTest>

namespace {

// Thursday, October 15, 2026, at a fixed local time.
QDateTime at(int hour, int minute)
{
    return QDateTime(QDate(2026, 10, 15), QTime(hour, minute));
}

QVariantMap calendarEvent(const QString &title, const QDateTime &start, int minutes, bool allDay = false)
{
    return QVariantMap{{"title", title},
                       {"startMs", start.toMSecsSinceEpoch()},
                       {"endMs", start.addSecs(minutes * 60).toMSecsSinceEpoch()},
                       {"startLabel", start.time().toString("h:mm ap")},
                       {"dayLabel", start.date() == QDate(2026, 10, 16) ? "Tomorrow" : "Saturday"},
                       {"all_day", allDay}};
}

QVariantMap project(const QString &name, const QString &status)
{
    return QVariantMap{{"name", name}, {"status", status}};
}

QVariantMap quote(const QString &symbol, double pct)
{
    return QVariantMap{{"symbol", symbol}, {"change_pct", pct}, {"flat", qFuzzyIsNull(pct)}};
}

// Times are glued with a no-break space ("3:30 pm" on one line); compare in plain spaces.
QString headline(const HomeGlance::Feed &feed, const QDateTime &now)
{
    return HomeGlance::compose(feed, now).value("headline").toString().replace(QChar(0x00A0), QLatin1Char(' '));
}

} // namespace

class TestHomeGlance : public QObject
{
    Q_OBJECT

private slots:
    void anEmptyFeedIsAQuietDay()
    {
        const QVariantMap s = HomeGlance::compose({}, at(15, 0));
        QCOMPARE(s.value("headline").toString(), QStringLiteral("Good afternoon. It's a quiet day so far."));
        QVERIFY(s.value("quiet").toBool());
        QVERIFY(s.value("detail").toString().endsWith("Ask me anything."));
        QCOMPARE(s.value("chips").toStringList(), QStringList{"What can you do?"});
        QVERIFY(s.value("next").toMap().isEmpty());
    }

    void theGreetingFollowsTheClock()
    {
        QVERIFY(headline({}, at(3, 0)).startsWith("Good night."));
        QVERIFY(headline({}, at(9, 12)).startsWith("Good morning."));
        QVERIFY(headline({}, at(17, 30)).startsWith("Good afternoon."));
        QVERIFY(headline({}, at(19, 30)).startsWith("Good evening."));
    }

    void theGreetingUsesTheDisplaysName()
    {
        HomeGlance::Feed feed;
        feed.displayName = QStringLiteral("Ricky");
        QVERIFY(headline(feed, at(9, 12)).startsWith("Good morning, Ricky."));
        feed.displayName = QStringLiteral("McFly"); // the default name isn't a person's
        QVERIFY(headline(feed, at(9, 12)).startsWith("Good morning."));
    }

    void theNextEventInMinutesAndHours()
    {
        HomeGlance::Feed feed;
        feed.upcoming = {calendarEvent("Standup", at(9, 30), 15)};
        QCOMPARE(headline(feed, at(9, 12)), QStringLiteral("Good morning. Standup is in 18 minutes."));
        QCOMPARE(headline(feed, at(9, 29)), QStringLiteral("Good morning. Standup is about to start."));
        QCOMPARE(headline(feed, at(9, 35)), QStringLiteral("Good morning. Standup is on now."));
        QCOMPARE(headline(feed, at(7, 0)), QStringLiteral("Good morning. Standup is at 9:30 am."));
        QCOMPARE(HomeGlance::compose(feed, at(9, 12)).value("next").toMap().value("title").toString(), QStringLiteral("Standup"));
    }

    void aTimeDoesNotBreakAcrossLines()
    {
        HomeGlance::Feed feed;
        feed.upcoming = {calendarEvent("Standup", at(9, 30), 15)};
        const QString raw = HomeGlance::compose(feed, at(7, 0)).value("headline").toString();
        QVERIFY(raw.contains(QStringLiteral("9:30") + QChar(0x00A0) + QStringLiteral("am")));
    }

    void aLongTitleAsksAboutTheDay()
    {
        HomeGlance::Feed feed;
        feed.upcoming = {calendarEvent("Pulse review with the team", at(15, 30), 30)};
        QCOMPARE(HomeGlance::compose(feed, at(11, 0)).value("chips").toStringList().first(), QStringLiteral("What else is on today?"));
    }

    void tomorrowStartsTheSentence()
    {
        HomeGlance::Feed feed;
        feed.upcoming = {calendarEvent("Investor call", QDateTime(QDate(2026, 10, 16), QTime(11, 0)), 60)};
        QCOMPARE(headline(feed, at(21, 0)), QStringLiteral("Good evening. Tomorrow starts with Investor call at 11:00 am."));
    }

    void allDayAndFinishedEventsAreSkipped()
    {
        HomeGlance::Feed feed;
        feed.upcoming = {calendarEvent("Holiday", at(0, 0), 24 * 60, true), calendarEvent("Standup", at(9, 30), 15),
                         calendarEvent("Pulse review", at(15, 30), 30)};
        QCOMPARE(headline(feed, at(12, 0)), QStringLiteral("Good afternoon. Pulse review is at 3:30 pm."));
    }

    void blockedProjects()
    {
        HomeGlance::Feed feed;
        feed.projects = {project("Onyx", "blocked"), project("McFly", "active")};
        QCOMPARE(headline(feed, at(10, 0)), QStringLiteral("Good morning. Onyx is blocked."));
        QVERIFY(HomeGlance::compose(feed, at(10, 0)).value("chips").toStringList().contains("What's blocking Onyx?"));
        feed.projects = {project("Onyx", "blocked"), project("Ohana", "blocked")};
        QCOMPARE(headline(feed, at(10, 0)), QStringLiteral("Good morning. Onyx and Ohana are blocked."));
        feed.projects << project("Atlas", "blocked");
        QCOMPARE(headline(feed, at(10, 0)), QStringLiteral("Good morning. Onyx and 2 others are blocked."));
        QCOMPARE(HomeGlance::compose(feed, at(10, 0)).value("blocked").toList().size(), 3);
    }

    void theBiggestMoveLeadsTheMarkets()
    {
        HomeGlance::Feed feed;
        feed.quotes = {quote("SPY", 0.32), quote("MSFT", -1.2), quote("TSLA", 3.96), quote("AAPL", 0.0)};
        const QVariantMap s = HomeGlance::compose(feed, at(10, 0));
        QCOMPARE(s.value("headline").toString(), QStringLiteral("Good morning. TSLA is up 4.0%."));
        const QVariantList movers = s.value("movers").toList();
        QCOMPARE(movers.size(), 2); // a move under 1% isn't news
        QCOMPARE(movers.at(0).toMap().value("symbol").toString(), QStringLiteral("TSLA"));
        QCOMPARE(movers.at(1).toMap().value("symbol").toString(), QStringLiteral("MSFT"));
        QCOMPARE(s.value("chips").toStringList().first(), QStringLiteral("Why is TSLA up?"));
        feed.quotes = {quote("MSFT", -2.04)};
        QCOMPARE(headline(feed, at(10, 0)), QStringLiteral("Good morning. MSFT is down 2.0%."));
        feed.quotes = {quote("SPY", 0.32)};
        QCOMPARE(headline(feed, at(10, 0)), QStringLiteral("Good morning. It's a quiet day so far."));
    }

    void everythingInOneSentence()
    {
        HomeGlance::Feed feed;
        feed.upcoming = {calendarEvent("Standup", at(9, 30), 15)};
        feed.projects = {project("Onyx", "blocked")};
        feed.quotes = {quote("TSLA", 3.96)};
        QCOMPARE(headline(feed, at(9, 12)),
                 QStringLiteral("Good morning. Standup is in 18 minutes, Onyx is blocked, and TSLA is up 4.0%."));
        QCOMPARE(HomeGlance::compose(feed, at(9, 12)).value("chips").toStringList(),
                 (QStringList{"What's on after Standup?", "What's blocking Onyx?", "Why is TSLA up?"}));
    }

    void theNewsAndTheLatestBrief()
    {
        HomeGlance::Feed feed;
        feed.news = QVariantMap{{"agentName", "Daily Pulse"}, {"isToday", true},
                                {"hero", QVariantMap{{"headline", "Google launches Gemini 4 Argon"}}}};
        feed.latestBrief = QVariantMap{{"title", "Hourly check-in."}, {"agentName", "Grok"}};
        const QVariantMap s = HomeGlance::compose(feed, at(16, 10));
        QCOMPARE(s.value("headline").toString(), QStringLiteral("Good afternoon. Nothing is next, and nothing needs you."));
        QCOMPARE(s.value("detail").toString(),
                 QStringLiteral("Today's Daily Pulse leads with Google launches Gemini 4 Argon. Grok's latest: Hourly check-in."));
        QCOMPARE(s.value("chips").toStringList(), (QStringList{"Read me the Daily Pulse", "What did Grok say?", "What can you do?"}));
        feed.news.insert("isToday", false);
        QVERIFY(HomeGlance::compose(feed, at(16, 10)).value("detail").toString().startsWith("The news leads with Google"));
    }

    void neverMoreThanThreeChips()
    {
        HomeGlance::Feed feed;
        feed.upcoming = {calendarEvent("Standup", at(9, 30), 15)};
        feed.projects = {project("Onyx", "blocked")};
        feed.quotes = {quote("TSLA", 3.96)};
        feed.latestBrief = QVariantMap{{"title", "Morning briefing"}, {"agentName", "Grok"}};
        const QStringList chips = HomeGlance::compose(feed, at(9, 12)).value("chips").toStringList();
        QCOMPARE(chips.size(), 3);
        QCOMPARE(QSet<QString>(chips.cbegin(), chips.cend()).size(), 3);
    }

    void withoutAStoreItStillSpeaks()
    {
        HomeGlance glance(nullptr);
        QVERIFY(glance.summary().value("headline").toString().contains("quiet day"));
    }
};

QTEST_GUILESS_MAIN(TestHomeGlance)
#include "tst_homeglance.moc"
