#include <QtTest>

#include <QColor>
#include <QJSValue>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QSignalSpy>
#include <QVector2D>
#include <QVector3D>
#include <QVector4D>

#include <algorithm>
#include <cmath>

// Stands in for DisplayController: the palette's inputs, and what the tiles
// and the voice glow gate their motion on.
class FakeDevice : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString mood READ mood WRITE setMood NOTIFY moodChanged)
    Q_PROPERTY(bool darkMode READ darkMode WRITE setDarkMode NOTIFY darkModeChanged)
    Q_PROPERTY(bool idle READ idle CONSTANT)
    Q_PROPERTY(bool screenOff READ screenOff CONSTANT)
    Q_PROPERTY(bool animatedTiles READ animatedTiles WRITE setAnimatedTiles NOTIFY animatedTilesChanged)
public:
    QString mood() const { return m_mood; }
    void setMood(const QString &mood)
    {
        if (mood == m_mood)
            return;
        m_mood = mood;
        emit moodChanged();
    }
    bool darkMode() const { return m_darkMode; }
    void setDarkMode(bool on)
    {
        if (on == m_darkMode)
            return;
        m_darkMode = on;
        emit darkModeChanged();
    }
    bool idle() const { return false; }
    bool screenOff() const { return false; }
    bool animatedTiles() const { return m_animatedTiles; }
    void setAnimatedTiles(bool on)
    {
        if (on == m_animatedTiles)
            return;
        m_animatedTiles = on;
        emit animatedTilesChanged();
    }

signals:
    void moodChanged();
    void darkModeChanged();
    void animatedTilesChanged();

private:
    QString m_mood = QStringLiteral("day");
    bool m_darkMode = false;
    bool m_animatedTiles = true;
};

static const char *kScene = R"(
import QtQuick
import McFly

Item {
    id: root
    width: 1280
    height: 800
    property QtObject theme: Theme
    property alias tile: tile
    property alias glow: glow
    property alias card: card
    property alias clock: clock
    property alias probe: probe
    // What the probe tile is fed, step by step, by paletteFadeHasNoPop.
    property var probeColors: ["#5B7CF5", "#F07F5A", "#F6B94A", "#FBE6B0"]
    property real probeDark: 0
    GradientTile {
        id: tile
        anchors.fill: parent
        radius: 0
        colors: [Theme.glowBlue, Theme.glowCoral, Theme.glowAmber, Theme.glowCream]
        ringScale: 1.3
        period: Theme.saverDrift
    }
    GradientTile {
        id: probe
        width: 400
        height: 300
        colors: root.probeColors
        darkness: root.probeDark
        animated: false
    }
    SpectrumGlow {
        id: glow
        width: 700
        height: 72
        kind: "input"
        ambient: true
    }
    // The card on Home (assistant layout) at 1280x800.
    SpectrumGlow {
        id: card
        width: 778
        height: 760
        cornerRadius: 36
        ambient: true
        intensity: 0.7
    }
    MotionClock { id: clock }
}
)";

// A colour read straight off Theme.dark, eased over Theme.paletteFade (what
// keyboard/style.qml did, and why it now follows `dark` a moment late).
static const char *kKeyboardProbe = R"(
import QtQuick
import McFly
QtObject {
    property color ink: Theme.dark ? "#FFFFFF" : "#000000"
    Behavior on ink { ColorAnimation { duration: Theme.paletteFade } }
}
)";

// The motion foundations: the palette's two fade lengths, a tile through
// a palette fade, the gradient tile's drift, and the voice glow's idle cap. Run offscreen, so the
// shaders' own fallbacks draw; what is checked is the motion they're fed.
class TestMotion : public QObject
{
    Q_OBJECT

    FakeDevice m_device;
    QQmlEngine *m_engine = nullptr;
    QObject *m_scene = nullptr;

    QObject *child(const char *name) const { return m_scene->property(name).value<QObject *>(); }
    QObject *theme() const { return child("theme"); }
    QColor background() const { return theme()->property("background").value<QColor>(); }

    static QVariant plain(QVariant v)
    {
        if (v.metaType() == QMetaType::fromType<QJSValue>())
            v = v.value<QJSValue>().toVariant();
        return v;
    }
    static QVector3D oklab(const QColor &c)
    {
        auto lin = [](double x) { return x <= 0.04045 ? x / 12.92 : std::pow((x + 0.055) / 1.055, 2.4); };
        const double r = lin(c.redF()), g = lin(c.greenF()), b = lin(c.blueF());
        const double l = std::cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
        const double m = std::cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
        const double s = std::cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
        return QVector3D(0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                         1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                         0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s);
    }
    // A palette's four glow colours (the ones the saver backdrops are fed).
    QList<QColor> glowOf(const QString &name) const
    {
        const QVariantMap p = name == QLatin1String("dark")
                                  ? plain(theme()->property("darkPalette")).toMap()
                                  : plain(theme()->property("palettes")).toMap().value(name).toMap();
        QList<QColor> out;
        for (const QVariant &c : p.value(QStringLiteral("glow")).toList())
            out << QColor(c.toString());
        return out;
    }
    // What the probe tile draws, in OKLab: each colour field, and the
    // shader's OKLCh blend of them at a few mixes (shaders/gradienttile.frag).
    QList<QVector3D> probeDrawn() const
    {
        const QVariantList lch = plain(child("probe")->property("_lch")).toList();
        QList<QVector4D> f;
        for (const QVariant &v : lch)
            f << v.value<QVector4D>();
        static const float mixes[][3] = {{1, 0, 0}, {0, 1, 0}, {0, 0, 1}, {.5f, .5f, 0}, {.5f, 0, .5f}, {0, .5f, .5f},
                                         {1 / 3.f, 1 / 3.f, 1 / 3.f}, {.7f, 0, .3f}, {.3f, 0, .7f}, {.7f, .3f, 0}, {.3f, .7f, 0}};
        QList<QVector3D> out;
        for (const auto &w : mixes) {
            const float sum = w[0] + w[1] + w[2];
            const QVector4D c = (f[0] * w[0] + f[1] * w[1] + f[2] * w[2]) / sum;
            out << QVector3D(c.x(), c.y() * std::cos(c.z()), c.y() * std::sin(c.z()));
        }
        return out;
    }
    // A centre of the tile's drift (r1c, r2c, b0..b3) at drift time t.
    QVector2D centre(const char *name, double t) const
    {
        QObject *tile = child("tile");
        tile->setProperty("_t", t);
        QVariant geo = tile->property("_geo");
        if (geo.metaType() == QMetaType::fromType<QJSValue>())
            geo = geo.value<QJSValue>().toVariant();
        return geo.toMap().value(QString::fromLatin1(name)).value<QVector2D>();
    }

private slots:
    void initTestCase()
    {
        QCoreApplication::setOrganizationName("McFly-tests");
        QCoreApplication::setApplicationName("tst_motion");
        // Each test has an engine of its own (so a Theme of its own); they
        // all share the one device.
        static FakeDevice *device = &m_device;
        qmlRegisterSingletonType<FakeDevice>("McFly.Core", 1, 0, "Device", [](QQmlEngine *, QJSEngine *) -> QObject * {
            QJSEngine::setObjectOwnership(device, QJSEngine::CppOwnership);
            return device;
        });
    }

    // A fresh engine, so a fresh Theme, from a day palette that has settled.
    void init()
    {
        m_device.setMood(QStringLiteral("day"));
        m_device.setDarkMode(false);
        m_device.setAnimatedTiles(true);
        m_engine = new QQmlEngine(this);
        m_engine->addImportPath(QStringLiteral(MCFLY_TEST_QML_DIR));
        QQmlComponent component(m_engine);
        component.setData(kScene, QUrl());
        m_scene = component.create();
        QVERIFY2(m_scene, qPrintable(component.errorString()));
        QCOMPARE(background(), QColor("#F1EFEB"));
    }

    void cleanup()
    {
        delete m_scene;
        m_scene = nullptr;
        delete m_engine;
        m_engine = nullptr;
    }

    // A scheduled mood drifts in over seconds, through colours between the
    // two palettes rather than a cut; the Dark mode tap answers within a
    // third of a second.
    void moodDriftsDarkModeAnswers()
    {
        m_device.setMood(QStringLiteral("evening"));
        QCOMPARE(theme()->property("paletteFade").toInt(), theme()->property("moodFade").toInt());
        QVERIFY(theme()->property("moodFade").toInt() >= 2000);
        QTest::qWait(1000);
        const QColor mid = background();
        QVERIFY2(mid != QColor("#F1EFEB") && mid != QColor("#EFEDF3"), qPrintable(mid.name()));
        QTRY_COMPARE_WITH_TIMEOUT(background(), QColor("#EFEDF3"), 6000);

        QElapsedTimer clock;
        clock.start();
        m_device.setDarkMode(true);
        QCOMPARE(theme()->property("paletteFade").toInt(), theme()->property("themeFade").toInt());
        QVERIFY(background() != QColor("#000000"));   // eased, not cut
        QTRY_COMPARE_WITH_TIMEOUT(background(), QColor("#000000"), 2000);
        QVERIFY2(clock.elapsed() < 1000, qPrintable(QString::number(clock.elapsed())));
        // Once it has settled, the next change is a mood's again.
        QTRY_COMPARE(theme()->property("paletteFade").toInt(), theme()->property("moodFade").toInt());
    }

    // The on-screen keyboard (keyboard/style.qml) eases its colours over
    // Theme.paletteFade: a Dark mode tap is a tap there too, not a 4 s mood,
    // although Theme.dark flips before Theme has set that length. The real
    // style, where the virtual keyboard module is installed; else a probe of
    // the plain pattern, which shows why the style follows `dark` late.
    void keyboardAnswersDarkModeQuickly()
    {
        QQmlComponent style(m_engine, QUrl::fromLocalFile(QFINDTESTDATA("../qml/keyboard/style.qml")));
        QScopedPointer<QObject> look(style.create());
        if (!look)
            QSKIP(qPrintable(QStringLiteral("no virtual keyboard module: ") + style.errorString()));
        QCOMPARE(look->property("inkColor").value<QColor>(), QColor("#000000"));
        QElapsedTimer clock;
        clock.start();
        m_device.setDarkMode(true);
        QTRY_COMPARE_WITH_TIMEOUT(look->property("inkColor").value<QColor>(), QColor("#FFFFFF"), 3000);
        QVERIFY2(clock.elapsed() < 800, qPrintable(QString::number(clock.elapsed())));
        // Back again, as quickly; and a mood still takes its seconds.
        clock.restart();
        m_device.setDarkMode(false);
        QTRY_COMPARE_WITH_TIMEOUT(look->property("inkColor").value<QColor>(), QColor("#000000"), 3000);
        QVERIFY2(clock.elapsed() < 800, qPrintable(QString::number(clock.elapsed())));
        m_device.setMood(QStringLiteral("night"));
        QTest::qWait(800);
        const QColor mid = look->property("inkColor").value<QColor>();
        QVERIFY2(mid != QColor("#000000") && mid != QColor("#FFFFFF"), qPrintable(mid.name()));
    }

    // Read straight off Theme.dark, the length is still the last one's.
    void plainPatternWouldLag()
    {
        QQmlComponent component(m_engine);
        component.setData(kKeyboardProbe, QUrl());
        QScopedPointer<QObject> probe(component.create());
        QVERIFY2(probe, qPrintable(component.errorString()));
        m_device.setDarkMode(true);
        QTest::qWait(800);
        QVERIFY(probe->property("ink").value<QColor>() != QColor("#FFFFFF"));
    }

    // A tile's night look follows the same two lengths.
    void tileNightFollowsThePalette()
    {
        QObject *tile = child("tile");
        QCOMPARE(tile->property("darkness").toReal(), 0.0);
        m_device.setDarkMode(true);
        QTRY_COMPARE_WITH_TIMEOUT(tile->property("darkness").toReal(), 1.0, 1000);
        m_device.setDarkMode(false);
        QTRY_COMPARE_WITH_TIMEOUT(tile->property("darkness").toReal(), 0.0, 1000);

        QTRY_COMPARE(theme()->property("paletteFade").toInt(), theme()->property("moodFade").toInt());
        m_device.setMood(QStringLiteral("night"));
        QTest::qWait(1000);
        const qreal partway = tile->property("darkness").toReal();
        QVERIFY2(partway > 0.0 && partway < 0.9, qPrintable(QString::number(partway)));
        QTRY_COMPARE_WITH_TIMEOUT(tile->property("darkness").toReal(), 1.0, 6000);
    }

    // The saver's drift, sampled at its 10 updates a second for ten minutes:
    // every centre keeps moving (no pendulum stops), never doubles back, moves
    // about a pixel per update, and is somewhere else one period later (the
    // old loop came back exactly).
    void driftNeverStopsOrRepeats()
    {
        const double t0 = 12345.0;
        const double period = child("tile")->property("_period").toDouble() / 1000;
        for (const char *name : {"r1c", "r2c", "b0", "b1", "b2", "b3"}) {
            QVector2D last = centre(name, t0), lastStep;
            double total = 0, slowest = 1e9, sharpest = 1;
            const int n = 6000;
            for (int i = 1; i <= n; ++i) {
                const QVector2D p = centre(name, t0 + i * 0.1);
                const QVector2D step = p - last;
                total += step.length();
                slowest = std::min(slowest, double(step.length()));
                if (i > 1)
                    sharpest = std::min(sharpest, double(QVector2D::dotProduct(step.normalized(), lastStep.normalized())));
                last = p;
                lastStep = step;
            }
            const double mean = total / n;
            QVERIFY2(slowest > 0.05 * mean, qPrintable(QStringLiteral("%1 nearly stops: %2 of %3").arg(name).arg(slowest).arg(mean)));
            QVERIFY2(sharpest > 0.9, qPrintable(QStringLiteral("%1 turns sharply: %2").arg(name).arg(sharpest)));
            QVERIFY2(mean < 2.5, qPrintable(QStringLiteral("%1 moves %2 px per update").arg(name).arg(mean)));
            const QVector2D a = centre(name, t0), b = centre(name, t0 + period);
            QVERIFY2((a - b).length() > 1.0, qPrintable(QStringLiteral("%1 repeats after a period").arg(name)));
        }
    }

    // The voice glow idles at its cap and runs at full rate when there is
    // something to show; Settings → Animated tiles holds it still.
    void glowIdlesAtItsCap()
    {
        QObject *glow = child("glow");
        QCOMPARE(glow->property("maxFps").toInt(), 30);  // Theme.motionFps: never under 30
        QVERIFY(!glow->property("_lively").toBool());
        glow->setProperty("processing", true);
        QVERIFY(glow->property("_lively").toBool());
        glow->setProperty("processing", false);
        glow->setProperty("speaking", true);
        QVERIFY(glow->property("_lively").toBool());
        glow->setProperty("speaking", false);
        glow->setProperty("ambient", false);
        QVERIFY(glow->property("_lively").toBool());

        QVERIFY(glow->property("motion").toBool());
        m_device.setAnimatedTiles(false);
        QVERIFY(!glow->property("motion").toBool());

        // Its lobes are worked out up front: each inside the host's width
        // (give or take the drift's overhang) and rising from its bottom.
        for (const char *name : {"_l0", "_l3", "_l6"}) {
            const QVector4D l = glow->property(name).value<QVector4D>();
            QVERIFY2(std::isfinite(l.x()) && l.x() > -500 && l.x() < 1200, name);
            QVERIFY2(l.y() < 72, name);
            QVERIFY2(l.z() > 0, name);
        }
    }

    // Held still, the glow catches up with its inputs and then stops asking
    // for frames, until an input changes.
    void stillGlowStopsOnceCaughtUp()
    {
        QObject *glow = child("glow");
        m_device.setAnimatedTiles(false);
        QVERIFY(glow->property("_changing").toBool());
        auto settle = [glow]() {
            for (int i = 0; i < 400 && !glow->property("_settled").toBool(); ++i)
                QMetaObject::invokeMethod(glow, "_tick", Q_ARG(QVariant, 1.0 / 30));
            return glow->property("_settled").toBool();
        };
        QVERIFY(settle());
        QVERIFY(!glow->property("_changing").toBool());
        QCOMPARE(glow->property("_level").toReal(), 0.5);   // the ambient glow, not a dark one

        glow->setProperty("processing", true);
        QVERIFY(glow->property("_changing").toBool());
        QVERIFY(settle());
        QCOMPARE(glow->property("_process").toReal(), 1.0);

        m_device.setAnimatedTiles(true);
        QVERIFY(glow->property("_changing").toBool());
    }

    // Home's card: the rows above the light aren't drawn at all. The cut sits
    // above everything that adds light (each lobe that shows, the band at its
    // highest, the bottom line up the corners) whatever the glow is doing,
    // and most of the way down the card while it idles. Each lobe's height
    // comes with it as 1 / height, for the shader.
    void glowCutsAboveTheLight()
    {
        QObject *card = child("card");
        auto check = [card](const char *state) {
            const double h = card->property("height").toDouble();
            const double cut = card->property("_cut").toDouble();
            const QVector4D dome = card->property("_dome").value<QVector4D>();
            const double band = h - 36 - 1.6 * card->property("_bandWidth").toDouble()
                                - card->property("_bandBlur").toDouble() - dome.z();
            QVERIFY2(cut >= 0 && cut <= band && cut <= h - 36 - 14, state);
            const QVector4D r0 = card->property("_r0").value<QVector4D>();
            const QVector4D r1 = card->property("_r1").value<QVector4D>();
            const float rh[7] = {r0.x(), r0.y(), r0.z(), r0.w(), r1.x(), r1.y(), r1.z()};
            for (int i = 0; i < 7; ++i) {
                const QVector4D l = card->property(qPrintable(QStringLiteral("_l%1").arg(i))).value<QVector4D>();
                if (l.w() > 2e-4)
                    QVERIFY2(cut <= l.y(), qPrintable(QStringLiteral("%1: lobe %2 lit above the cut").arg(state).arg(i)));
                QVERIFY2(std::abs(rh[i] * std::max(h - l.y(), 1.0) - 1) < 1e-4, state);
            }
            QVERIFY2(std::abs(r1.w() * 2 * card->property("_lobeBlur").toDouble() - 1) < 1e-4, state);
        };
        auto run = [card](double seconds) {
            for (int i = 0; i < seconds * 30; ++i)
                QMetaObject::invokeMethod(card, "_tick", Q_ARG(QVariant, 1.0 / 30));
        };
        run(2);
        check("idle");
        QVERIFY2(card->property("_cut").toDouble() > 0.4 * 760, "idling, the top 40% isn't drawn");
        card->setProperty("speaking", true);
        for (int i = 0; i < 6; ++i) {
            run(0.5);
            check("speaking");
        }
        card->setProperty("speaking", false);
        card->setProperty("processing", true);
        for (int i = 0; i < 6; ++i) {
            run(0.5);
            check("thinking");
        }
    }

    // The clock for QML's own loops (News' Ken Burns, Projects' breath) keeps
    // the ambient slots, 30 updates a second, not the panel's every frame.
    // Stopped, it holds where it was, and starts again from there without a
    // step for the time it stood.
    void motionClockKeepsTheSlots()
    {
        QObject *clock = child("clock");
        QCOMPARE(clock->property("fps").toInt(), 30);   // Theme.motionFps
        QVERIFY(!clock->property("running").toBool());
        clock->setProperty("playing", true);
        QVERIFY(clock->property("running").toBool());
        QVERIFY(clock->property("interval").toInt() <= 34);
        QTRY_VERIFY(clock->property("time").toDouble() > 0.2);
        clock->setProperty("playing", false);
        QVERIFY(!clock->property("running").toBool());
        const double held = clock->property("time").toDouble();
        QTest::qWait(400);
        QCOMPARE(clock->property("time").toDouble(), held);
        QSignalSpy step(clock, SIGNAL(timeChanged()));
        clock->setProperty("playing", true);
        QVERIFY(step.wait(500));
        const double first = clock->property("time").toDouble() - held;
        QVERIFY2(first > 0 && first < 0.08, qPrintable(QString::number(first)));
    }

    // A tile fed the glow colours through a palette fade changes smoothly:
    // no step on the way (the old pastel mapping snapped a field from grey to
    // full colour, and flipped its hue, as dawn's amber faded through grey
    // to day's blue). Every pair of palettes, through Theme's eased OKLab
    // fade in 240 steps: a mood's four seconds at 60 frames a second.
    void paletteFadeHasNoPop()
    {
        QObject *probe = child("probe");
        const QStringList names = {"morning", "day", "evening", "night", "dark"};
        double worst = 0, worstStrong = 0;
        QString where, whereStrong;
        for (const QString &a : names) {
            for (const QString &b : names) {
                if (a == b)
                    continue;
                const QList<QColor> from = glowOf(a), to = glowOf(b);
                const double dkA = a == "night" || a == "dark", dkB = b == "night" || b == "dark";
                // The night look fixed at either end, then fading along.
                for (int mode = 0; mode < 3; ++mode) {
                    QList<QVector3D> last;
                    QVector3D lastStrong;
                    const int n = 240;
                    for (int k = 0; k <= n; ++k) {
                        const double t = 0.5 - 0.5 * std::cos(M_PI * k / n);
                        QVariantList colors;
                        for (int i = 0; i < 4; ++i) {
                            QVariant c;
                            QMetaObject::invokeMethod(theme(), "mixOklab", Q_RETURN_ARG(QVariant, c),
                                                      Q_ARG(QVariant, from[i]), Q_ARG(QVariant, to[i]), Q_ARG(QVariant, t));
                            colors << c;
                        }
                        m_scene->setProperty("probeColors", colors);
                        m_scene->setProperty("probeDark", mode == 2 ? dkA + (dkB - dkA) * t : double(mode));
                        const QList<QVector3D> drawn = probeDrawn();
                        const QVector3D strong = oklab(probe->property("strong").value<QColor>());
                        if (k > 0) {
                            for (qsizetype i = 0; i < drawn.size(); ++i) {
                                const double d = (drawn[i] - last[i]).length();
                                if (d > worst) {
                                    worst = d;
                                    where = QStringLiteral("%1 to %2, mode %3, step %4, mix %5").arg(a, b).arg(mode).arg(k).arg(i);
                                }
                            }
                            // `strong` flips from dark to light ink on purpose
                            // halfway into the night look: only check it at a
                            // fixed one.
                            const double d = (strong - lastStrong).length();
                            if (mode < 2 && d > worstStrong) {
                                worstStrong = d;
                                whereStrong = QStringLiteral("%1 to %2, mode %3, step %4").arg(a, b).arg(mode).arg(k);
                            }
                        }
                        last = drawn;
                        lastStrong = strong;
                    }
                }
            }
        }
        // 0.02 in OKLab is about the smallest difference the eye picks up.
        QVERIFY2(worst < 0.02, qPrintable(QStringLiteral("%1 in one step: %2").arg(worst).arg(where)));
        QVERIFY2(worstStrong < 0.02, qPrintable(QStringLiteral("strong %1 in one step: %2").arg(worstStrong).arg(whereStrong)));
        qInfo("worst step %.4f (%s); strong %.4f (%s)", worst, qPrintable(where), worstStrong, qPrintable(whereStrong));
    }
};

QTEST_MAIN(TestMotion)
#include "tst_motion.moc"
