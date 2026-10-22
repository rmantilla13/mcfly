#include <QtTest>

#include <QColor>
#include <QJSValue>
#include <QQmlComponent>
#include <QQmlEngine>

#include <cmath>

#include "graphics/ScaledShader.h"

// Stands in for DisplayController: the palette's inputs, and what the
// backdrop gates its motion on.
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
    property alias sky: sky
    // The dusk the backdrop is fed, 0 by day to 1 at night.
    property real dusk: 0
    Backdrop {
        id: sky
        anchors.fill: parent
        style: "dawn"
        darkness: root.dusk
    }
}
)";

// A sky backdrop (Backdrop.qml), run offscreen so its fallback draws: what
// is checked is what its shader is fed. Through the dusk the canvas goes
// from the warm day canvas to the night one, the ink flips in the middle and
// the light goes from a wash to a glow; the stops reach the shader in OKLCh
// with each hue within half a turn of the one before; each style picks its
// own shader and resolution.
class TestBackdrop : public QObject
{
    Q_OBJECT

    FakeDevice m_device;
    QQmlEngine *m_engine = nullptr;
    QObject *m_scene = nullptr;

    QObject *sky() const { return m_scene->property("sky").value<QObject *>(); }
    static QVariant plain(QVariant v)
    {
        if (v.metaType() == QMetaType::fromType<QJSValue>())
            v = v.value<QJSValue>().toVariant();
        return v;
    }
    static qreal lightness(const QVariant &v) { return v.value<QColor>().lightnessF(); }
    void setDusk(qreal dusk) { m_scene->setProperty("dusk", dusk); }

private slots:
    void initTestCase()
    {
        QCoreApplication::setOrganizationName("McFly-tests");
        QCoreApplication::setApplicationName("tst_backdrop");
        static FakeDevice *device = &m_device;
        qmlRegisterType<ScaledShader>("McFly.Core", 1, 0, "ScaledShader");
        qmlRegisterSingletonType<FakeDevice>("McFly.Core", 1, 0, "Device", [](QQmlEngine *, QJSEngine *) -> QObject * {
            QJSEngine::setObjectOwnership(device, QJSEngine::CppOwnership);
            return device;
        });
    }

    // A fresh engine, so a fresh Theme, on a day palette.
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
    }

    void cleanup()
    {
        delete m_scene;
        m_scene = nullptr;
        delete m_engine;
        m_engine = nullptr;
    }

    void followsTheDusk()
    {
        setDusk(0.0);
        QVERIFY(std::abs(lightness(sky()->property("canvas")) - QColor("#F1EFEB").lightnessF()) < 0.02);
        const qreal byDay = sky()->property("strength").toReal();
        QVERIFY2(byDay > 0.3 && byDay < 0.7, qPrintable(QString::number(byDay)));
        QVERIFY(lightness(sky()->property("ink")) < 0.3);
        // With the clock stopped (no window), what the shader is fed follows at once.
        QCOMPARE(sky()->property("_shownStrength").toReal(), byDay);

        setDusk(1.0);
        QVERIFY(std::abs(lightness(sky()->property("canvas")) - QColor("#121317").lightnessF()) < 0.02);
        QVERIFY(sky()->property("strength").toReal() > byDay);
        QVERIFY(lightness(sky()->property("ink")) > 0.8);
        QCOMPARE(sky()->property("_shownStrength").toReal(), sky()->property("strength").toReal());

        // Past the middle of the dusk the canvas is still between the two,
        // and the ink has already turned.
        setDusk(0.6);
        const qreal mid = lightness(sky()->property("canvas"));
        QVERIFY2(mid > 0.2 && mid < 0.9, qPrintable(QString::number(mid)));
        QVERIFY(lightness(sky()->property("ink")) > 0.8);
    }

    void stopsReachTheShaderUnwrapped()
    {
        const QVariantList stops = plain(sky()->property("_shownStops")).toList();
        QCOMPARE(stops.size(), 4);
        double previous = 0;
        for (int i = 0; i < stops.size(); ++i) {
            const QVariantList c = plain(stops[i]).toList();
            QCOMPARE(c.size(), 3);
            QVERIFY(c[0].toDouble() > 0 && c[0].toDouble() < 1);   // lightness
            QVERIFY(c[1].toDouble() > 0.02);                        // chroma: the glow is never grey
            if (i > 0)
                QVERIFY2(std::abs(c[2].toDouble() - previous) <= M_PI, "a hue the long way round");
            previous = c[2].toDouble();
        }
    }

    // The shader is the style's, at the style's resolution; a name this
    // build doesn't know draws the arc. It is shaded at that share of the
    // item's size, in pixels (what a layer's textureSize was), by a
    // ScaledShader: one frame per update, where a layer drew two.
    void picksItsShaderAndResolution()
    {
        auto *fx = sky()->findChild<ScaledShader *>();
        QVERIFY(fx);
        const auto shaded = [fx]() {
            return QSize(fx->property("fixedColorBufferWidth").toInt(), fx->property("fixedColorBufferHeight").toInt());
        };
        QCOMPARE(sky()->property("shader").toString(), QStringLiteral("dawn"));
        QCOMPARE(sky()->property("resolution").toReal(), 0.5);
        QCOMPARE(fx->fragmentShader(), QUrl(QStringLiteral("qrc:/McFly/shaders/dawn.frag.qsb")));
        QCOMPARE(fx->status(), ScaledShader::Compiled);
        QCOMPARE(shaded(), QSize(640, 400));
        sky()->setProperty("style", QStringLiteral("ribbons"));
        QCOMPARE(sky()->property("shader").toString(), QStringLiteral("ribbons"));
        QCOMPARE(sky()->property("resolution").toReal(), 0.4);
        QCOMPARE(fx->fragmentShader(), QUrl(QStringLiteral("qrc:/McFly/shaders/ribbons.frag.qsb")));
        QCOMPARE(shaded(), QSize(512, 320));
        QCOMPARE(fx->vertexShader(), QUrl());
        sky()->setProperty("style", QStringLiteral("disco"));
        QCOMPARE(sky()->property("shader").toString(), QStringLiteral("arc"));
        // The arc works out what depends on the column alone once a column.
        QCOMPARE(fx->vertexShader(), QUrl(QStringLiteral("qrc:/McFly/shaders/arc.vert.qsb")));
        QCOMPARE(fx->status(), ScaledShader::Compiled);
    }
};

QTEST_MAIN(TestBackdrop)
#include "tst_backdrop.moc"
