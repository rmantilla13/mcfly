#include <QtTest>

#include <QNetworkProxy>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQmlProperty>
#include <QQuickItem>
#include <QQuickWindow>
#include <QTemporaryDir>

#include <functional>

#include "backend/SupabaseClient.h"
#include "graphics/ScaledShader.h"
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
    Q_PROPERTY(bool idle READ idle NOTIFY idleChanged)
    Q_PROPERTY(bool screenOff READ screenOff NOTIFY screenOffChanged)
    Q_PROPERTY(bool animatedTiles READ animatedTiles WRITE setAnimatedTiles NOTIFY animatedTilesChanged)
    // What the screen savers read: the arc sky, no weather, two minutes to idle.
    Q_PROPERTY(QString backdrop READ backdrop CONSTANT)
    Q_PROPERTY(QString screensaver READ screensaver CONSTANT)
    Q_PROPERTY(bool nightMode READ no CONSTANT)
    Q_PROPERTY(QString weather READ weather CONSTANT)
    Q_PROPERTY(QString weatherKind READ weather CONSTANT)
    Q_PROPERTY(int idleTimeoutSec READ idleTimeoutSec CONSTANT)
public:
    QString mood() const { return QStringLiteral("day"); }
    QString backdrop() const { return QStringLiteral("arc"); }
    QString screensaver() const { return QStringLiteral("ambient"); }
    QString weather() const { return QStringLiteral("off"); }
    bool no() const { return false; }
    Q_INVOKABLE int weatherCount(const QString &, qreal, qreal) const { return 0; }
    int idleTimeoutSec() const { return 120; }
    bool darkMode() const { return false; }
    bool idle() const { return m_idle; }
    bool screenOff() const { return m_screenOff; }
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
    void setIdle(bool on)
    {
        if (on == m_idle)
            return;
        m_idle = on;
        emit idleChanged();
    }
    void setScreenOff(bool off)
    {
        if (off == m_screenOff)
            return;
        m_screenOff = off;
        emit screenOffChanged();
    }
signals:
    void animatedTilesChanged();
    void idleChanged();
    void screenOffChanged();

private:
    bool m_animatedTiles = true;
    bool m_idle = false;
    bool m_screenOff = false;
};

// Stands in for SystemController, for the setup screen: online over a wire,
// with no Wi-Fi controls.
class FakeSystem : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool wifiAvailable READ no CONSTANT)
    Q_PROPERTY(bool wifiEnabled READ no CONSTANT)
    Q_PROPERTY(QString wifiSsid READ none CONSTANT)
    Q_PROPERTY(QString ipAddress READ ipAddress CONSTANT)
    Q_PROPERTY(bool busy READ no CONSTANT)
    Q_PROPERTY(QString message READ none CONSTANT)
    Q_PROPERTY(QVariantList networks READ networks CONSTANT)
public:
    bool no() const { return false; }
    QString none() const { return {}; }
    QString ipAddress() const { return QStringLiteral("192.0.2.10"); }
    QVariantList networks() const { return {}; }
    Q_INVOKABLE void refresh() {}
    Q_INVOKABLE void scanWifi() {}
    Q_INVOKABLE void connectWifi(const QString &, const QString &, bool) {}
signals:
    void wifiChanged();
    void ipChanged();
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
    FakeSystem m_system;
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
        qmlRegisterSingletonInstance("McFly.Core", 1, 0, "System", &m_system);
        qmlRegisterSingletonInstance("McFly.Core", 1, 0, "Glance", m_glance);
        qmlRegisterType<ScaledShader>("McFly.Core", 1, 0, "ScaledShader");
        // One engine for them all: an instance singleton belongs to one.
        m_engine = new QQmlEngine(this);
        m_engine->addImportPath(QStringLiteral(MCFLY_TEST_QML_DIR));
    }

    void init()
    {
        m_device.setAnimatedTiles(true);
        m_device.setIdle(false);
    }

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

    // Setup's drifting lights, the card's float and the digits' wave keep the
    // ambient clock (30 updates a second, not every frame the panel draws),
    // along the curves their Animations had. The lights and the float stop
    // while the screen is idle, the float while the keyboard is up, all of
    // them with Animated tiles off; started again, a light rises from below
    // the screen and the digits wave from the first.
    void setupMovesOnTheAmbientClock()
    {
        QVERIFY(show("SetupScreen { sample: true }", 1280, 800, QStringLiteral("compact")));
        QObject *lights = m_screen->findChild<QObject *>(QStringLiteral("lights"));
        QObject *floats = m_screen->findChild<QObject *>(QStringLiteral("float"));
        QObject *wave = m_screen->findChild<QObject *>(QStringLiteral("wave"));
        QQuickItem *card = find("card");
        QVERIFY(lights && floats && wave && card);
        QList<QQuickItem *> found;
        QVector<QQuickItem *> light(6), digit(6);
        collect(m_window->contentItem(), QStringLiteral("light"), found);
        collect(m_window->contentItem(), QStringLiteral("digit"), found);
        QCOMPARE(found.size(), 12);
        for (QQuickItem *item : std::as_const(found))
            (item->objectName() == QLatin1String("light") ? light : digit)[item->property("index").toInt()] = item;
        const auto running = [](QObject *clock) { return clock->property("running").toBool(); };
        const auto offset = [&]() { return QQmlProperty(card, QStringLiteral("anchors.verticalCenterOffset")).read().toReal(); };
        const auto near = [](qreal a, qreal b) { return qAbs(a - b) < 1e-6; };
        for (QObject *clock : {lights, floats, wave}) {
            QVERIFY(running(clock));
            QCOMPARE(clock->property("fps").toInt(), 30);   // Theme.motionFps
            QVERIFY(clock->property("interval").toInt() <= 34);
        }
        const qreal y = light[0]->y(), at = offset();
        QTRY_VERIFY(light[0]->y() < y && light[0]->opacity() > 0 && offset() < at && digit[0]->scale() > 1);

        // The curves, at given times.
        m_device.setAnimatedTiles(false);
        for (QObject *clock : {lights, floats, wave})
            QVERIFY(!running(clock));
        // A light from 100 below the screen to 200 above it, 26 s for the first.
        const qreal riseFrom = m_screen->property("riseFrom").toReal();
        lights->setProperty("time", riseFrom + 13);
        QVERIFY2(near(light[0]->y(), (900 - 200) / 2.0), qPrintable(QString::number(light[0]->y())));
        lights->setProperty("time", riseFrom + 26);
        QVERIFY(near(light[0]->y(), 900));
        // Its light: up to 0.22 over 4 s and down to 0.06 over 6 s, from
        // nothing the first time, after 1.8 s per light.
        const QList<std::tuple<int, qreal, qreal>> glow = {
            {0, 2, 0.11}, {0, 4, 0.22}, {0, 7, 0.14}, {0, 10, 0.06}, {0, 12, 0.14},
            {2, 1, 0}, {2, 5.6, 0.11}, {2, 14.6, 0.06}};
        for (const auto &[i, t, want] : glow) {
            lights->setProperty("time", t);
            QVERIFY2(near(light[i]->opacity(), want), qPrintable(QStringLiteral("light %1 at %2 s: %3").arg(i).arg(t).arg(light[i]->opacity())));
        }
        // The card: up from -10 to -16 over 5 s, then to -4 and back, 5 s each way.
        const QList<std::pair<qreal, qreal>> lift = {{0, -10}, {2.5, -13}, {5, -16}, {7.5, -10}, {10, -4}, {15, -16}};
        for (const auto &[t, want] : lift) {
            floats->setProperty("time", t);
            QVERIFY2(near(offset(), want), qPrintable(QStringLiteral("float at %1 s: %2").arg(t).arg(offset())));
        }
        // A digit: to 1.06 and back, 420 ms each way, 220 ms after the one
        // before, every 4.24 s.
        const qreal waveFrom = digit[0]->property("waveFrom").toReal();
        for (const qreal cycle : {0.0, 4.24}) {
            wave->setProperty("time", waveFrom + cycle + 0.22 + 0.42);
            QVERIFY2(near(digit[1]->scale(), 1.06), qPrintable(QString::number(digit[1]->scale())));
            QVERIFY(digit[0]->scale() > 1 && digit[0]->scale() < 1.06);
            QVERIFY(near(digit[0]->scale(), digit[2]->scale()));
            QCOMPARE(digit[3]->scale(), 1.0);
        }

        // Started again: each light from below the screen, the first digit first.
        m_device.setAnimatedTiles(true);
        for (QObject *clock : {lights, floats, wave})
            QVERIFY(running(clock));
        for (QQuickItem *item : std::as_const(light))
            QVERIFY(near(item->y(), 900));
        for (QQuickItem *item : std::as_const(digit))
            QCOMPARE(item->scale(), 1.0);

        // The keyboard up: no float, the card just above it.
        m_screen->setProperty("keyboardHeight", 300);
        QVERIFY(!running(floats));
        QVERIFY(running(lights) && running(wave));
        QCOMPARE(offset(), -160.0);
        m_screen->setProperty("keyboardHeight", 0);
        QVERIFY(running(floats));

        // Idle: the lights and the float stop; the code's digits go on.
        m_device.setIdle(true);
        QVERIFY(!running(lights) && !running(floats));
        QVERIFY(running(wave));
        m_device.setIdle(false);
        QVERIFY(running(lights) && running(floats));

        // Hidden: nothing.
        qobject_cast<QQuickItem *>(m_screen)->setVisible(false);
        for (QObject *clock : {lights, floats, wave})
            QVERIFY(!running(clock));
    }

    // The screen saver eases off: what moves on it (here the arc's sky)
    // updates Theme.saverFps times a second, then Theme.saverCalmFps once
    // the screen has gone untouched for Theme.saverCalmAfter, which is the
    // saver's own time plus the idle timeout before it came up. Hidden (a
    // touch, the panel asleep) it starts over.
    void saverEasesOff()
    {
        QVERIFY(show("ScreenSaver {}", 1280, 800, QStringLiteral("wide")));
        QCOMPARE(m_screen->property("calmAfter").toInt(), (10 * 60 - 120) * 1000);
        QCOMPARE(m_screen->property("fps").toInt(), 30);
        QObject *content = m_screen->findChild<QObject *>(QStringLiteral("saverContent"));
        QVERIFY(content);
        QTRY_VERIFY(content->property("item").value<QObject *>());
        QObject *ambient = content->property("item").value<QObject *>();
        QObject *sky = nullptr;
        for (QObject *o : ambient->findChildren<QObject *>())
            if (QByteArray(o->metaObject()->className()).startsWith("Backdrop"))
                sky = o;
        QVERIFY(sky);
        QObject *slide = ambient->findChild<QObject *>(QStringLiteral("slide"));
        QVERIFY(slide);
        QCOMPARE(ambient->property("fps").toInt(), 30);
        QCOMPARE(sky->property("maxFps").toInt(), 30);
        QCOMPARE(slide->property("fps").toInt(), 30);

        // The minute's slide against burn-in: from where it is, on the saver's
        // clock, eased to the new spot over 4 s, then the clock stops.
        QVERIFY(!slide->property("running").toBool());
        QMetaObject::invokeMethod(ambient, "_slideTo", Q_ARG(QVariant, 12.0), Q_ARG(QVariant, -6.0));
        QVERIFY(slide->property("running").toBool());
        QCOMPARE(ambient->property("shiftX").toReal(), 0.0);
        QTRY_VERIFY(ambient->property("shiftX").toReal() > 0.5);
        QVERIFY(ambient->property("shiftX").toReal() < 12.0);
        QTRY_VERIFY_WITH_TIMEOUT(!slide->property("running").toBool(), 6000);
        QCOMPARE(ambient->property("shiftX").toReal(), 12.0);
        QCOMPARE(ambient->property("shiftY").toReal(), -6.0);

        m_screen->setProperty("calmAfter", 50);
        QTRY_COMPARE(m_screen->property("fps").toInt(), 15);
        QCOMPARE(ambient->property("fps").toInt(), 15);
        QCOMPARE(sky->property("maxFps").toInt(), 15);
        QCOMPARE(slide->property("fps").toInt(), 15);

        qobject_cast<QQuickItem *>(m_screen)->setVisible(false);
        QCOMPARE(m_screen->property("calm").toBool(), false);
        QCOMPARE(m_screen->property("fps").toInt(), 30);
    }

    // Headlines pushes into a story's picture, to 1.08 over 14 s, on the
    // saver's clock rather than every frame, and slower when it eases off.
    void headlinesPushInOnTheSaverClock()
    {
        QTemporaryDir dir;
        QImage picture(64, 40, QImage::Format_RGB32);
        picture.fill(Qt::darkCyan);
        const QString file = dir.filePath(QStringLiteral("story.png"));
        QVERIFY(picture.save(file));

        QVERIFY(show("HeadlinesSaver {}", 1280, 800, QStringLiteral("wide")));
        // The current slot's picture (a Repeater's slots hang off the item tree).
        QQuickItem *image = nullptr;
        QObject *burns = nullptr;
        std::function<void(QQuickItem *)> walk = [&](QQuickItem *item) {
            if (QObject *clock = item->findChild<QObject *>(QStringLiteral("kenBurns"), Qt::FindDirectChildrenOnly);
                clock && item->parentItem() && item->parentItem()->property("current").toBool()) {
                image = item;
                burns = clock;
            }
            for (QQuickItem *child : item->childItems())
                walk(child);
        };
        walk(qobject_cast<QQuickItem *>(m_screen));
        QVERIFY(image && burns);
        QCOMPARE(burns->property("fps").toInt(), 30);
        QVERIFY(!burns->property("running").toBool());   // no picture yet
        image->setProperty("source", QUrl::fromLocalFile(file));
        QTRY_VERIFY(image->isVisible());
        QVERIFY(burns->property("running").toBool());
        QVERIFY(image->scale() >= 1.0 && image->scale() < 1.005);   // from the start (a tick may be in)
        QTRY_VERIFY(image->scale() > 1.001);
        QVERIFY(image->scale() < 1.08);
        m_screen->setProperty("fps", 15);
        QCOMPARE(burns->property("fps").toInt(), 15);
    }

    // Waiting for a code: ten dots round a ring, from the top and clockwise,
    // fill one by one over a second and empty over the next, on the ambient
    // clock (the Basic BusyIndicator before them redrew every frame). They
    // stop once a code is in, with the panel off, and hidden. The glow
    // behind is shaded at half its pixels, as the field is.
    void setupWaitsOnTheAmbientClock()
    {
        QVERIFY(show("SetupScreen {}", 1280, 800, QStringLiteral("compact"))); // the demo store has no code
        QQuickItem *busy = find("busy");
        QObject *clock = m_screen->findChild<QObject *>(QStringLiteral("busyClock"));
        QVERIFY(busy && clock);
        QCOMPARE(find("glow")->property("resolution").toReal(), 0.5);
        const auto running = [&]() { return clock->property("running").toBool(); };
        QVERIFY(busy->isVisible() && running());
        QCOMPARE(clock->property("fps").toInt(), 30);   // Theme.motionFps
        QList<QQuickItem *> found;
        collect(m_window->contentItem(), QStringLiteral("busyDot"), found);
        QCOMPARE(found.size(), 10);
        QVector<QQuickItem *> dot(10);
        for (QQuickItem *item : std::as_const(found))
            dot[item->property("index").toInt()] = item;
        QVERIFY(dot[0]->y() < dot[5]->y() && qAbs(dot[0]->x() - dot[5]->x()) < 1e-6 && dot[2]->x() > dot[0]->x());
        const auto filled = [&]() {
            QString out;
            for (QQuickItem *item : std::as_const(dot))
                out += item->property("filled").toBool() ? QLatin1Char('#') : QLatin1Char('.');
            return out;
        };
        const QList<std::pair<qreal, QString>> ring = {
            {0, QStringLiteral("..........")}, {0.05, QStringLiteral("#.........")},
            {0.45, QStringLiteral("#####.....")}, {1, QStringLiteral("##########")},
            {1.25, QStringLiteral("...#######")}, {1.5, QStringLiteral("......####")},
            {1.95, QStringLiteral("..........")}, {2.45, QStringLiteral("#####.....")}};
        for (const auto &[t, want] : ring) {
            clock->setProperty("time", t);
            QVERIFY2(filled() == want, qPrintable(QStringLiteral("at %1 s: %2").arg(t).arg(filled())));
        }

        m_screen->setProperty("sample", true);   // a code
        QVERIFY(!busy->isVisible() && !running());
        m_screen->setProperty("sample", false);
        QVERIFY(busy->isVisible() && running());
        m_device.setScreenOff(true);
        QVERIFY(!running());
        m_device.setScreenOff(false);
        QVERIFY(running());
        qobject_cast<QQuickItem *>(m_screen)->setVisible(false);
        QVERIFY(!running());
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

    // The assistant panel opens voice first: nothing has focus, so the
    // on-screen keyboard stays down, and Send waits for something typed. A
    // tap on the field brings the keyboard; sending (Send, or a suggestion,
    // which goes through send() too) takes the focus off the field, so the
    // keyboard goes and a later tap brings it back.
    void assistantPanelKeepsTheKeyboardDown()
    {
        QVERIFY(show("AssistantPanel { open: true }", 1180, 800, QStringLiteral("compact")));
        m_window->requestActivate();
        QVERIFY(QTest::qWaitForWindowActive(m_window));
        QQuickItem *field = find("askField");
        QQuickItem *send = find("sendButton");
        QVERIFY(field && send);
        QVERIFY(!field->hasActiveFocus());
        QVERIFY(!send->isVisible());
        shoot(QStringLiteral("assistant-panel-open"));

        const auto tap = [this](QQuickItem *item) {
            const QPointF c = item->mapToScene(QPointF(item->width() / 2, item->height() / 2));
            QTest::mouseClick(m_window, Qt::LeftButton, Qt::NoModifier, c.toPoint());
        };
        tap(field);
        QTRY_VERIFY(field->hasActiveFocus());
        const qreal wide = field->width();
        field->setProperty("text", QStringLiteral("Summarize my day"));
        QVERIFY(send->isVisible());
        QTRY_VERIFY(field->width() < wide); // Send has taken its place in the bar
        tap(send);
        QVERIFY(!field->hasActiveFocus());
        QCOMPARE(field->property("text").toString(), QString());
        QVERIFY(!send->isVisible());
        QTRY_VERIFY_WITH_TIMEOUT(!m_ai->busy(), 15000);

        tap(field);
        QTRY_VERIFY(field->hasActiveFocus());
        QMetaObject::invokeMethod(m_screen, "send", Q_ARG(QVariant, QStringLiteral("What's blocking Onyx?")));
        QVERIFY(!field->hasActiveFocus());
        QTRY_VERIFY_WITH_TIMEOUT(!m_ai->busy(), 15000);
        shoot(QStringLiteral("assistant-panel-answered"));
        m_ai->reset();
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
