#include <QtTest>

#include <QNetworkProxy>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQmlProperty>
#include <QQuickItem>
#include <QQuickWindow>

#include "backend/SupabaseClient.h"
#include "models/Assistant.h"
#include "models/FeedStore.h"
#include "models/HomeGlance.h"
#include "voice/VoiceClient.h"

// Stands in for DisplayController, with Settings → Animated tiles to turn off.
class FakeDevice : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString mood READ mood CONSTANT)
    Q_PROPERTY(bool darkMode READ darkMode CONSTANT)
    Q_PROPERTY(bool idle READ idle CONSTANT)
    Q_PROPERTY(bool screenOff READ screenOff CONSTANT)
    Q_PROPERTY(bool animatedTiles READ animatedTiles WRITE setAnimatedTiles NOTIFY animatedTilesChanged)
public:
    QString mood() const { return QStringLiteral("day"); }
    bool darkMode() const { return false; }
    bool idle() const { return false; }
    bool screenOff() const { return false; }
    bool animatedTiles() const { return m_animatedTiles; }
    // The rail's moon: counted, so a tap on it can be told from one on Settings.
    Q_INVOKABLE void sleepNow() { ++sleeps; }
    int sleeps = 0;
    void setAnimatedTiles(bool on)
    {
        if (on == m_animatedTiles)
            return;
        m_animatedTiles = on;
        emit animatedTilesChanged();
    }
signals:
    void animatedTilesChanged();

private:
    bool m_animatedTiles = true;
};

// The screens' motion and their new layouts against the real store, its demo
// data at a fixed time of day: the reveal that settles a screen in, the
// insight line turning, Home's countdown ring and its thread with now on it,
// a board's tiles placed from Store.boardLayout (and gliding to a new
// board), and the Briefs outline surviving a sync that makes its rows again.
// Pictures go to $MCFLY_TEST_SHOTS when it is set.
class TestScreens : public QObject
{
    Q_OBJECT

    SupabaseClient *m_client = nullptr;
    FeedStore *m_store = nullptr;
    VoiceClient *m_voice = nullptr;
    Assistant *m_ai = nullptr;
    HomeGlance *m_glance = nullptr;
    FakeDevice m_device;
    QDateTime m_fake;
    QQmlEngine *m_engine = nullptr;
    QQuickWindow *m_window = nullptr;
    QObject *m_screen = nullptr;

    QObject *theme() { return m_engine->singletonInstance<QObject *>("McFly", "Theme"); }

    // A QML object from source, with the module imported.
    QObject *make(const QByteArray &qml)
    {
        QQmlComponent component(m_engine);
        component.setData("import QtQuick\nimport McFly\n" + qml, QUrl());
        QObject *obj = component.create();
        if (!obj)
            qWarning("%s", qPrintable(component.errorString()));
        return obj;
    }
    // A screen in a window of a panel's size, the tier set as Main.qml sets it.
    bool show(const QByteArray &qml, int w, int h, const QString &tier)
    {
        theme()->setProperty("tier", tier);
        theme()->setProperty("shortSide", qMin(w, h));
        m_window = new QQuickWindow;
        m_window->resize(w, h);
        m_screen = make(qml);
        if (!m_screen)
            return false;
        auto *item = qobject_cast<QQuickItem *>(m_screen);
        item->setParentItem(m_window->contentItem());
        item->setSize(QSizeF(w, h));
        m_window->show();
        return QTest::qWaitForWindowExposed(m_window);
    }
    void shoot(const QString &name)
    {
        const QString dir = qEnvironmentVariable("MCFLY_TEST_SHOTS");
        if (!dir.isEmpty())
            m_window->grabWindow().save(dir + QLatin1Char('/') + name + QStringLiteral(".png"));
    }
    QQuickItem *find(const char *name) { return m_screen->findChild<QQuickItem *>(QLatin1String(name)); }
    // Items by name down the visual tree (a Repeater's aren't the screen's QObject children).
    static void collect(QQuickItem *item, const QString &name, QList<QQuickItem *> &out)
    {
        for (QQuickItem *child : item->childItems()) {
            if (child->objectName() == name)
                out << child;
            collect(child, name, out);
        }
    }

private slots:
    void initTestCase()
    {
        QCoreApplication::setOrganizationName("McFly-tests");
        QCoreApplication::setApplicationName("tst_screens");
        QSettings().clear();
        QNetworkProxy::setApplicationProxy(QNetworkProxy::NoProxy);

        // The demo's day at ten past three: Pulse review (3:30) is 20 minutes off.
        m_fake = QDateTime(QDate::currentDate(), QTime(15, 10));
        m_client = new SupabaseClient(QUrl(), QString(), this);
        m_store = new FeedStore(m_client, true, this);
        m_store->setClock([this]() { return m_fake; });
        m_store->start(); // demo mode
        m_voice = new VoiceClient(QUrl(QStringLiteral("ws://127.0.0.1:9")), this); // never started: no voice
        m_ai = new Assistant(m_client, m_store, m_voice, this);
        m_glance = new HomeGlance(m_store, this);

        qmlRegisterSingletonInstance("McFly.Core", 1, 0, "Store", m_store);
        qmlRegisterSingletonInstance("McFly.Core", 1, 0, "AI", m_ai);
        qmlRegisterSingletonInstance("McFly.Core", 1, 0, "Voice", m_voice);
        qmlRegisterSingletonInstance("McFly.Core", 1, 0, "Device", &m_device);
        qmlRegisterSingletonInstance("McFly.Core", 1, 0, "Glance", m_glance);
        // One engine for them all: an instance singleton belongs to one.
        m_engine = new QQmlEngine(this);
        m_engine->addImportPath(QStringLiteral(MCFLY_TEST_QML_DIR));
    }

    void init() { m_device.setAnimatedTiles(true); }

    void cleanup()
    {
        delete m_screen;
        m_screen = nullptr;
        delete m_window;
        m_window = nullptr;
    }

    void cleanupTestCase() { QSettings().clear(); }

    // 0 → 1 over revealDuration once shown, item 0 ahead of item 7, all of it
    // in place by the end; nothing at all with Animated tiles off. (Out of a
    // window, so not the software renderer, which skips arrivals.)
    void revealStaggersAndSettles()
    {
        QScopedPointer<QObject> reveal(make("Reveal { shown: false }"));
        QVERIFY(reveal);
        QCOMPARE(reveal->property("value").toReal(), 1.0);
        QVERIFY(reveal->property("animates").toBool());
        auto at = [&](int i) {
            QVariant out;
            QMetaObject::invokeMethod(reveal.get(), "at", Q_RETURN_ARG(QVariant, out), Q_ARG(QVariant, i));
            return out.toReal();
        };

        reveal->setProperty("shown", true);
        QCOMPARE(reveal->property("value").toReal(), 0.0);
        QCOMPARE(at(0), 0.0);
        QTest::qWait(220);
        QVERIFY2(at(0) > 0.3 && at(0) < 1.0, qPrintable(QString::number(at(0))));
        QCOMPARE(at(7), 0.0);
        QVERIFY(at(1) < at(0));
        // Settled well inside the 1.5 s a still allows.
        QTRY_COMPARE_WITH_TIMEOUT(reveal->property("value").toReal(), 1.0, 900);
        for (int i : {0, 3, 7, 30})
            QCOMPARE(at(i), 1.0);

        // Turned off mid-way: in place at once.
        reveal->setProperty("shown", false);
        reveal->setProperty("shown", true);
        QTest::qWait(100);
        QVERIFY(reveal->property("value").toReal() < 1.0);
        m_device.setAnimatedTiles(false);
        QCOMPARE(reveal->property("value").toReal(), 1.0);
        reveal->setProperty("shown", false);
        reveal->setProperty("shown", true);
        QCOMPARE(reveal->property("value").toReal(), 1.0);
    }

    // A screen arrives when it is picked, not each time the assistant panel
    // closes over it: `shown` (the panel) comes and goes with no replay;
    // `isCurrent` (leaving and coming back) plays it again.
    void revealPlaysOnArrivalNotOnUncover()
    {
        // Out of a window, as above, so the reveal animates.
        m_screen = make("BriefsScreen { width: 1280; height: 800; isCurrent: false; shown: false }");
        QVERIFY(m_screen);
        QObject *reveal = nullptr;
        for (QObject *o : m_screen->findChildren<QObject *>())
            if (QByteArray(o->metaObject()->className()).startsWith("Reveal"))
                reveal = o;
        QVERIFY(reveal);
        m_screen->setProperty("isCurrent", true);
        m_screen->setProperty("shown", true);
        QVERIFY(reveal->property("value").toReal() < 1.0);
        QTRY_COMPARE_WITH_TIMEOUT(reveal->property("value").toReal(), 1.0, 900);

        m_screen->setProperty("shown", false);
        m_screen->setProperty("shown", true);
        QTest::qWait(50);
        QCOMPARE(reveal->property("value").toReal(), 1.0);

        m_screen->setProperty("isCurrent", false);
        m_screen->setProperty("isCurrent", true);
        QVERIFY(reveal->property("value").toReal() < 1.0);
    }

    // Turns one at a time, keeps the one showing when a new list still has
    // it, and starts over (or hides) when it doesn't.
    void insightLineTurnsAndKeepsItsPlace()
    {
        // In a window: out of one, an item is never visible, and the line only turns while it is.
        QVERIFY(show("InsightLine { interval: 150 }", 600, 80, QStringLiteral("compact")));
        QObject *line = m_screen;
        auto item = [](const char *id) {
            return QVariantMap{{"id", id}, {"title", QString::fromLatin1(id).toUpper()}, {"icon", "info"}, {"color", "#5B7CF5"}};
        };
        auto currentId = [&]() { return line->property("current").toMap().value("id").toString(); };
        line->setProperty("items", QVariantList{item("a"), item("b"), item("c")});
        QCOMPARE(currentId(), QStringLiteral("a"));
        QTRY_COMPARE(currentId(), QStringLiteral("b"));
        line->setProperty("running", false);
        QCOMPARE(line->property("index").toInt(), 1);

        // A sync: b moved to the front and is still the one showing.
        line->setProperty("items", QVariantList{item("b"), item("d")});
        QCOMPARE(line->property("index").toInt(), 0);
        QCOMPARE(currentId(), QStringLiteral("b"));
        // It went: back to the first.
        line->setProperty("items", QVariantList{item("e"), item("d")});
        QCOMPARE(currentId(), QStringLiteral("e"));
        line->setProperty("items", QVariantList{});
        QVERIFY(!line->property("visible").toBool());
        line->setProperty("items", QVariantList{item("f")});
        QVERIFY(line->property("visible").toBool());
        QCOMPARE(currentId(), QStringLiteral("f"));
    }

    // Home at 3:10: Pulse review counts down on a ring (20 of 60 minutes
    // left); on at 3:40, the ring goes and the bar shows it half run. The now
    // dot sits on the thread just under the last row that has started.
    void homeCountsDownAndPlacesNow()
    {
        QVERIFY(show("HomeScreen { }", 1280, 800, QStringLiteral("compact")));
        // Home's clock is the wall clock: hold it at the store's.
        auto *tick = m_screen->findChild<QObject *>(QStringLiteral("clockTick"));
        QVERIFY(tick);
        tick->setProperty("running", false);
        m_screen->setProperty("now", m_fake);

        auto *ring = find("countdown");
        QVERIFY(ring);
        QTRY_VERIFY(ring->isVisible());
        QCOMPARE(qRound(ring->property("value").toReal() * 60), 20);
        QVERIFY(!find("elapsed")->isVisible());

        auto *list = find("dayList");
        auto *rail = find("nowRail");
        QVERIFY(list && rail);
        QTRY_VERIFY(rail->property("placed").toBool());
        const QVariantList timeline = m_store->timeline();
        const qint64 t = m_fake.toMSecsSinceEpoch();
        int last = -1;
        for (int i = 0; i < timeline.size(); ++i) {
            const QVariantMap row = timeline.at(i).toMap();
            if (!row.value("allDay").toBool() && row.value("startMs").toLongLong() <= t)
                last = i;
        }
        QVERIFY(last >= 0);
        QQuickItem *row = nullptr;
        QMetaObject::invokeMethod(list, "itemAtIndex", Q_RETURN_ARG(QQuickItem *, row), Q_ARG(int, last));
        QVERIFY(row);
        QTRY_COMPARE(rail->property("nowY").toReal(), row->y() + row->height() + list->property("spacing").toReal() / 2);
        shoot(QStringLiteral("home-1510"));

        // On now: half of Pulse review (3:30–4:00) has run.
        m_screen->setProperty("now", QDateTime(m_fake.date(), QTime(15, 45)));
        QTRY_VERIFY(!ring->isVisible());
        QTRY_VERIFY(find("elapsed")->isVisible());
        shoot(QStringLiteral("home-1545"));
    }

    // The 7" panel's left column at its fullest (what stands out, up next
    // with its ring or its bar and a place, blocked) still fits above the bar.
    // The assistant-first Home on every panel: however much McFly has to
    // say, its summary shows whole (set smaller to fit) and the talk button
    // stays inside its card, not cut off at the bottom. The words are the
    // ones a morning on the 10.1" panel pushed the button out of the card with.
    void assistantCardKeepsItsButton()
    {
        // The morning on the 10.1" panel, and a busier one: longer than any
        // card fits at its full size, on every panel.
        const QList<QByteArray> mornings = {
            "({ headline: 'Good afternoon. Busy is in 4 minutes, Armra J466 BFCM Base Gut Videos and Lace Health"
            " edits (Asana) are blocked, and RXRX is down 3.2%.',"
            " detail: 'The news leads with Meta GEM claims 18.9% more conversions. X watch\\'s latest: 5 Conversations"
            " Dominating X Today.',"
            " chips: ['What\\'s on after Busy?', 'What\\'s blocking Armra J466 BFCM Base Gut Videos?', 'Why is RXRX down?'] })",
            "({ headline: 'Good afternoon. Quarterly planning with the leadership team is in 4 minutes, Armra J466 BFCM"
            " Base Gut Videos, Lace Health edits (Asana) and the Northwind onboarding refresh are blocked, and RXRX is"
            " down 3.2% while PLTR is up 4.1%.',"
            " detail: 'The news leads with Meta GEM claims 18.9% more conversions across every campaign it ran this"
            " quarter. X watch\\'s latest: 5 Conversations Dominating X Today, and two more briefs since noon.',"
            " chips: ['What\\'s on after Quarterly planning with the leadership team?', 'What\\'s blocking Armra J466"
            " BFCM Base Gut Videos?', 'Why is RXRX down 3.2% today?'] })",
        };
        struct Panel { int w; int h; const char *tier; };
        // The pages' area on each panel: the window less the rail or the bar.
        const QList<Panel> panels = {{1180, 800, "compact"}, {1796, 1080, "wide"}, {800, 404, "mini"}, {720, 1196, "tall"}};
        for (qsizetype m = 0; m < mornings.size(); ++m) {
            for (const Panel &p : panels) {
                const QString where = QStringLiteral("%1, morning %2").arg(QLatin1String(p.tier)).arg(m + 1);
                QVERIFY(show("HomeAssistant { summary: " + mornings.at(m) + " }", p.w, p.h, QString::fromLatin1(p.tier)));
                QTest::qWait(50);
                QList<QQuickItem *> cards;
                collect(m_window->contentItem(), QStringLiteral("speakingCard"), cards);
                QQuickItem *card = nullptr;
                for (QQuickItem *c : std::as_const(cards))
                    if (c->isVisible())
                        card = c;
                QVERIFY2(card, qPrintable(where));
                QList<QQuickItem *> buttons, headlines;
                collect(card, QStringLiteral("talkButton"), buttons);
                collect(card, QStringLiteral("headline"), headlines);
                QCOMPARE(buttons.size(), 1);
                QCOMPARE(headlines.size(), 1);
                shoot(QStringLiteral("assistant-%1-%2").arg(QLatin1String(p.tier)).arg(m + 1));
                const QRectF button = buttons.first()->mapRectToItem(card, QRectF(QPointF(0, 0), buttons.first()->size()));
                QVERIFY2(button.top() >= 0 && button.bottom() <= card->height() - 8,
                         qPrintable(QStringLiteral("%1: the button reaches %2 of %3").arg(where).arg(button.bottom()).arg(card->height())));
                // The summary whole, set smaller where it must be; only the 7"
                // panel may run out of room for the busier morning.
                if (m == 0 || qstrcmp(p.tier, "mini") != 0)
                    QVERIFY2(!headlines.first()->property("truncated").toBool(), qPrintable(where + QStringLiteral(": the summary is cut off")));
                cleanup();
            }
        }
    }

    void homeFitsTheSmallPanel()
    {
        QVERIFY(show("HomeScreen { }", 800, 404, QStringLiteral("mini")));
        auto *tick = m_screen->findChild<QObject *>(QStringLiteral("clockTick"));
        QVERIFY(tick);
        tick->setProperty("running", false);
        auto *column = find("moment");
        auto *blocked = find("blockedCard");
        QVERIFY(column && blocked);
        for (const QTime &at : {QTime(15, 10), QTime(15, 45)}) {
            m_screen->setProperty("now", QDateTime(m_fake.date(), at));
            QTest::qWait(50);
            QTRY_VERIFY(blocked->isVisible());
            const qreal bottom = blocked->mapToItem(column, QPointF(0, blocked->height())).y();
            QVERIFY2(bottom <= column->height() + 0.5,
                     qPrintable(QStringLiteral("%1: %2 > %3").arg(at.toString(), QString::number(bottom), QString::number(column->height()))));
            QVERIFY(find("nowRail")->property("placed").toBool());
            QTest::qWait(600); // the now dot glides to its new place first
            shoot(QStringLiteral("home-mini-") + at.toString(QStringLiteral("hhmm")));
        }
    }

    // Every tile where Store.boardLayout puts it; another board, and they
    // glide there rather than jump.
    void boardTilesFollowTheLayoutAndGlide()
    {
        QVERIFY(show("DashboardsScreen { }", 1280, 800, QStringLiteral("compact")));
        const auto tiles = [&]() {
            QList<QQuickItem *> out;
            QList<QQuickItem *> all;
            collect(qobject_cast<QQuickItem *>(m_screen), QStringLiteral("tile"), all);
            for (QQuickItem *t : all)
                if (t->isVisible())
                    out << t;
            std::sort(out.begin(), out.end(), [](QQuickItem *a, QQuickItem *b) {
                return a->property("index").toInt() < b->property("index").toInt();
            });
            return out;
        };
        const auto check = [&](int board) {
            const QVariantList cells = m_store->boardLayout(board, 4);
            const QList<QQuickItem *> shown = tiles();
            if (shown.size() != cells.size())
                return false;
            const qreal colWidth = m_screen->property("colWidth").toReal();
            const qreal gap = m_screen->property("gap").toReal();
            for (int i = 0; i < cells.size(); ++i) {
                const QVariantMap c = cells.at(i).toMap();
                if (qAbs(shown.at(i)->x() - c.value("col").toInt() * (colWidth + gap)) > 0.5
                    || qAbs(shown.at(i)->width() - (c.value("colSpan").toInt() * colWidth + (c.value("colSpan").toInt() - 1) * gap)) > 0.5)
                    return false;
            }
            return true;
        };
        QTRY_VERIFY(check(0));
        // The ops board's hero is on the left, a metric one column in from the right.
        shoot(QStringLiteral("boards-ops"));

        QTest::qWait(300); // past the first placement
        QQuickItem *second = tiles().value(1);
        QVERIFY(second);
        const QPointF from = second->position();
        m_screen->setProperty("index", 1);
        QVERIFY(m_screen->property("gliding").toBool());
        QTest::qWait(120);
        const QPointF mid = second->position();
        QVERIFY2(mid != from, "the tile should be on its way");
        QTRY_VERIFY_WITH_TIMEOUT(check(1), 1500);
        QVERIFY2(mid != second->position(), "the tile should have glided, not jumped");
        QTRY_VERIFY(!m_screen->property("gliding").toBool());
        // The chart tile was kept for the new board's chart (10 points, not
        // 12): its line is drawn from the new points.
        QList<QQuickItem *> charts;
        collect(qobject_cast<QQuickItem *>(m_screen), QStringLiteral("chart"), charts);
        QCOMPARE(charts.size(), 1);
        const QString line = charts.first()->property("linePath").toString();
        QVERIFY(!line.isEmpty());
        QVERIFY2(!line.contains(QLatin1String("NaN")) && line.count(QLatin1Char('L')) == 9, qPrintable(line));
        shoot(QStringLiteral("boards-launch"));
    }

    // A status that needs a look breathes on the ambient clock (30 updates a
    // second, not every frame the panel draws): its halo swells from 0.6 of
    // full size at 0.08 opacity to full size at 0.34 over Theme.breath, from
    // the start each time it starts, and is gone, not frozen, while stopped.
    void statusDotBreathesOnTheAmbientClock()
    {
        QVERIFY(show("StatusDot { size: 16; breathing: true }", 120, 120, QStringLiteral("compact")));
        auto *halo = m_screen->findChild<QQuickItem *>(QStringLiteral("halo"));
        auto *clock = m_screen->findChild<QObject *>(QStringLiteral("breath"));
        QVERIFY(halo && clock);
        QVERIFY(halo->isVisible());
        QVERIFY(clock->property("running").toBool());
        QCOMPARE(clock->property("fps").toInt(), 30);
        QVERIFY(clock->property("interval").toInt() <= 34);
        // Opacity and size move together, along the same eased curve.
        auto f = [&]() { return (halo->opacity() - 0.08) / 0.26; };
        auto inStep = [&]() { return qAbs(f() - (halo->scale() - 0.6) / 0.4) < 1e-6; };
        QTRY_VERIFY(f() > 0.05);
        QVERIFY(f() < 1 && inStep());
        QTRY_VERIFY_WITH_TIMEOUT(f() > 0.98, 4000); // the top, Theme.breath in
        QVERIFY(inStep());

        m_device.setAnimatedTiles(false);
        QVERIFY(!halo->isVisible());
        QVERIFY(!clock->property("running").toBool());
        m_device.setAnimatedTiles(true);
        QVERIFY(halo->isVisible());
        QVERIFY2(qAbs(f()) < 1e-6, qPrintable(QString::number(f()))); // from the start again
        QTRY_VERIFY(f() > 0.05);

        m_screen->setProperty("running", false);
        QVERIFY(!halo->isVisible());
        QVERIFY(!clock->property("running").toBool());
        m_screen->setProperty("running", true);
        m_screen->setProperty("breathing", false);
        QVERIFY(!halo->isVisible());
        QVERIFY(!clock->property("running").toBool());
    }

    // A health strip's statuses line up along the top (the first in a row,
    // with no hairline to stretch it, used to sit lower), and a long run
    // wraps into rows of `perRow`, each starting at the left.
    void healthStripAlignsAndWraps()
    {
        QByteArray statuses = "[";
        for (const char *name : {"API", "Web", "DB", "Cache", "Queue", "Search", "Mail"})
            statuses += QByteArray("{ label: '") + name + "', state: 'ok', stateLabel: 'OK', stateColor: '#3DB37A', detail: 'Fine' },";
        statuses += "]";
        QVERIFY(show("HealthStrip { summary: 'All OK'; perRow: 3; statuses: " + statuses + " }", 700, 380, QStringLiteral("mini")));
        QList<QQuickItem *> cells;
        collect(m_window->contentItem(), QStringLiteral("healthStatus"), cells);
        QCOMPARE(cells.size(), 7);
        auto at = [&](int i) { return cells.at(i)->mapToScene(QPointF(0, 0)); };
        for (int i = 0; i < cells.size(); ++i)
            QCOMPARE(at(i).y(), at(i - i % 3).y());
        QVERIFY(at(3).y() > at(0).y() + 40 && at(6).y() > at(3).y() + 40);
        QCOMPARE(at(3).x(), at(0).x());
        QCOMPARE(at(6).x(), at(0).x());
        QVERIFY(qAbs(cells.at(0)->width() - cells.at(1)->width()) < 24); // shares, give or take the hairline
        shoot(QStringLiteral("health-wrapped"));

        // One row of three, as the demo's Ops board has: still level.
        delete m_screen;
        m_screen = nullptr;
        delete m_window;
        m_window = nullptr;
        QVERIFY(show("HealthStrip { summary: '1 down'; statuses: [{ label: 'API', state: 'ok', stateLabel: 'OK' },"
                     " { label: 'Workers', state: 'warn', stateLabel: 'Warning' }, { label: 'Search', state: 'down', stateLabel: 'Down' }] }",
                     760, 120, QStringLiteral("mini")));
        cells.clear();
        collect(m_window->contentItem(), QStringLiteral("healthStatus"), cells);
        QCOMPARE(cells.size(), 3);
        QCOMPARE(at(0).y(), at(1).y());
        QCOMPARE(at(0).y(), at(2).y());
        shoot(QStringLiteral("health-row"));
    }

    // While an answer is on its way with the panel shut, a ring turns around
    // the Ask button; it fades away after, and holds still with Animated
    // tiles off.
    void navRailThinkingRingTurns()
    {
        QVERIFY(show("NavRail { }", 100, 800, QStringLiteral("compact")));
        QList<QQuickItem *> rings;
        collect(qobject_cast<QQuickItem *>(m_screen), QStringLiteral("thinkingRing"), rings);
        QCOMPARE(rings.size(), 2); // the rail's and the bar's
        QQuickItem *ring = rings.first();
        QVERIFY(!ring->isVisible());

        // An Animator turns it (on the render thread: `rotation` itself only
        // catches up when it stops), so ask the animator.
        auto *spin = ring->findChild<QObject *>(QStringLiteral("spin"));
        QVERIFY(spin);
        QVERIFY(!spin->property("running").toBool());

        m_screen->setProperty("thinking", true);
        QTRY_COMPARE(ring->opacity(), 1.0);
        QVERIFY(spin->property("running").toBool());
        shoot(QStringLiteral("navrail-thinking"));

        m_device.setAnimatedTiles(false);
        QVERIFY(!spin->property("running").toBool());
        QVERIFY(ring->isVisible()); // still says it's thinking, holding still
        m_device.setAnimatedTiles(true);
        QVERIFY(spin->property("running").toBool());

        m_screen->setProperty("thinking", false);
        QTRY_VERIFY(!ring->isVisible());
        QVERIFY(!spin->property("running").toBool());
    }

    // The rail's Ask, Settings and Sleep are discs smaller than a touch
    // target, each in a slot a target tall that it takes taps across: a tap
    // just off a disc still presses it, the gap between two discs is split
    // between them and never presses both, and the slots stay clear of the
    // nav items above and inside the rail below, at both rail tiers.
    void navRailButtonsTakeTapsAcrossTheirSlots()
    {
        struct Rail { int w; int h; const char *tier; qreal disc; };
        const QList<Rail> rails = {{100, 800, "compact", 44}, {124, 1080, "wide", 52}};
        for (const Rail &r : rails) {
            const QString where = QString::fromLatin1(r.tier);
            QVERIFY(show("NavRail { }", r.w, r.h, where));
            QQuickItem *ask = find("railAsk");
            QQuickItem *settings = find("railSettings");
            QQuickItem *sleep = find("railSleep");
            QVERIFY(ask && settings && sleep);
            const qreal slot = theme()->property("touchTarget").toReal();
            const auto box = [](QQuickItem *b) { return b->mapRectToScene(QRectF(0, 0, b->width(), b->height())); };
            QTRY_VERIFY(box(sleep).bottom() > box(ask).bottom());

            QCOMPARE(ask->width(), r.disc);
            QCOMPARE(sleep->height(), r.disc);
            QCOMPARE(box(settings).center().y() - box(ask).center().y(), slot);
            QCOMPARE(box(sleep).center().y() - box(settings).center().y(), slot);
            QVERIFY2(box(sleep).center().y() + slot / 2 <= r.h, qPrintable(where));
            QList<QQuickItem *> items;
            collect(qobject_cast<QQuickItem *>(m_screen), QStringLiteral("navItem"), items);
            QCOMPARE(items.size(), 8);
            QVERIFY2(box(items.last()).bottom() <= box(ask).center().y() - slot / 2, qPrintable(where));

            QSignalSpy asks(m_screen, SIGNAL(askRequested()));
            QSignalSpy opened(m_screen, SIGNAL(settingsRequested()));
            m_device.sleeps = 0;
            const auto tap = [this](qreal x, qreal y) {
                QTest::mouseClick(m_window, Qt::LeftButton, Qt::NoModifier, QPoint(qRound(x), qRound(y)));
            };
            const QPointF a = box(ask).center(), s = box(settings).center(), z = box(sleep).center();
            tap(a.x(), a.y() - slot / 2 + 2);          // above Ask's disc, in its slot
            QCOMPARE(asks.count(), 1);
            tap(a.x(), (a.y() + s.y()) / 2 - 2);       // the gap, Ask's half
            QCOMPARE(asks.count(), 2);
            QCOMPARE(opened.count(), 0);
            tap(a.x(), (a.y() + s.y()) / 2 + 2);       // the gap, Settings' half
            QCOMPARE(asks.count(), 2);
            QCOMPARE(opened.count(), 1);
            tap(z.x() + slot / 2 - 2, z.y());          // beside Sleep's disc, in its slot
            QCOMPARE(m_device.sleeps, 1);
            QCOMPARE(opened.count(), 1);
            shoot(QStringLiteral("navrail-buttons-%1").arg(where));
            cleanup();
        }
    }

    // The picked brief's outline sits on its row, and still does after a
    // sync makes every row again.
    void briefsOutlineSurvivesASync()
    {
        QVERIFY(show("BriefsScreen { }", 1280, 800, QStringLiteral("compact")));
        auto *list = find("briefList");
        auto *outline = find("chosenOutline");
        QVERIFY(list && outline);
        const auto onRow = [&](int index) {
            QQuickItem *row = nullptr;
            QMetaObject::invokeMethod(list, "itemAtIndex", Q_RETURN_ARG(QQuickItem *, row), Q_ARG(int, index));
            return row && outline->isVisible() && qAbs(outline->y() - row->y()) < 0.5 && qAbs(outline->height() - row->height()) < 0.5;
        };
        QTRY_VERIFY(onRow(0));
        QVERIFY(QMetaObject::invokeMethod(m_screen, "pick", Q_ARG(QVariant, 2)));
        QTRY_VERIFY_WITH_TIMEOUT(onRow(2), 1500);

        // A rebuild: the rows are made again, with the same heights.
        m_store->showSource(QStringLiteral("nobody"));
        m_store->showSource(QString());
        QTRY_VERIFY(onRow(2));
        shoot(QStringLiteral("briefs-picked"));
    }
};

QTEST_MAIN(TestScreens)
#include "tst_screens.moc"
