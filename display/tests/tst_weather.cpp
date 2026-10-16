#include <QtTest>

#include <QColor>
#include <QJSValue>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickItem>

#include "hardware/DisplayController.h"

// Stands in for DisplayController: the palette's inputs, what the weather
// gates its motion on, the kind that falls, and the real count.
class FakeDevice : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString mood READ mood CONSTANT)
    Q_PROPERTY(bool darkMode READ darkMode CONSTANT)
    Q_PROPERTY(bool idle READ idle CONSTANT)
    Q_PROPERTY(bool screenOff READ screenOff CONSTANT)
    Q_PROPERTY(bool animatedTiles READ animatedTiles CONSTANT)
    Q_PROPERTY(QString weatherKind READ weatherKind WRITE setWeatherKind NOTIFY weatherKindChanged)
public:
    QString mood() const { return QStringLiteral("day"); }
    bool darkMode() const { return false; }
    bool idle() const { return false; }
    bool screenOff() const { return false; }
    bool animatedTiles() const { return true; }
    QString weatherKind() const { return m_kind; }
    void setWeatherKind(const QString &kind)
    {
        if (kind == m_kind)
            return;
        m_kind = kind;
        emit weatherKindChanged();
    }
    Q_INVOKABLE int weatherCount(const QString &kind, qreal width, qreal height) const
    {
        return DisplayController::weatherCount(kind, width, height);
    }

signals:
    void weatherKindChanged();

private:
    QString m_kind;
};

static const char *kScene = R"(
import QtQuick
import McFly

Item {
    id: root
    width: 1280
    height: 800
    property alias weather: weather
    property real dusk: 0
    Weather {
        id: weather
        anchors.fill: parent
        darkness: root.dusk
    }
}
)";

// The weather over a saver's backdrop (Weather.qml), offscreen with no
// window, so its clock is stopped and the test steps it by hand.
class TestWeather : public QObject
{
    Q_OBJECT

    FakeDevice m_device;
    QQmlEngine *m_engine = nullptr;
    QObject *m_scene = nullptr;

    QObject *weather() const { return m_scene->property("weather").value<QObject *>(); }
    int built() const { return weather()->property("_drops").value<QObject *>()->property("count").toInt(); }
    QQuickItem *drop(int i) const
    {
        QQuickItem *item = nullptr;
        QMetaObject::invokeMethod(weather()->property("_drops").value<QObject *>(), "itemAt",
                                  Q_RETURN_ARG(QQuickItem *, item), Q_ARG(int, i));
        return item;
    }
    void step(double seconds)
    {
        QMetaObject::invokeMethod(weather(), "_step", Q_ARG(QVariant, seconds));
    }
    void show(const QString &kind)
    {
        m_device.setWeatherKind(kind);
        QCoreApplication::processEvents();   // the reset waits for callLater
    }

private slots:
    void initTestCase()
    {
        QCoreApplication::setOrganizationName("McFly-tests");
        QCoreApplication::setApplicationName("tst_weather");
        static FakeDevice *device = &m_device;
        qmlRegisterSingletonType<FakeDevice>("McFly.Core", 1, 0, "Device", [](QQmlEngine *, QJSEngine *) -> QObject * {
            QJSEngine::setObjectOwnership(device, QJSEngine::CppOwnership);
            return device;
        });
    }

    void init()
    {
        m_device.setWeatherKind(QString());
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

    // Off: nothing is built, and nothing would tick.
    void offBuildsNothing()
    {
        QCOMPARE(weather()->property("count").toInt(), 0);
        QCOMPARE(built(), 0);
        QVERIFY(!weather()->property("playing").toBool());
    }

    // Snow: as many as the screen's share says, and they fall.
    void snowFallsAndComesBackAtTheTop()
    {
        show(QStringLiteral("snow"));
        const int n = DisplayController::weatherCount(QStringLiteral("snow"), 1280, 800);
        QCOMPARE(weather()->property("count").toInt(), n);
        QCOMPARE(built(), n);
        QVERIFY(drop(0));
        const qreal before = drop(0)->y();
        step(0.2);
        QVERIFY2(drop(0)->y() > before || drop(0)->y() < 0, "a flake falls (or has just come in again at the top)");
        // A minute later every flake is still around the screen: those out at
        // the bottom came in again at the top.
        for (int i = 0; i < 600; ++i)
            step(0.1);
        for (int i = 0; i < n; ++i) {
            const QQuickItem *d = drop(i);
            QVERIFY(d->y() > -0.4 * 800 && d->y() < 800 + 60);
            QVERIFY(d->x() > -0.6 * 1280 && d->x() < 1.6 * 1280);
        }
    }

    // Fireflies stay in the lower part of the screen and glow and dim.
    void firefliesWanderLowAndGlow()
    {
        show(QStringLiteral("fireflies"));
        QVERIFY(built() > 0);
        qreal dimmest = 1, brightest = 0;
        for (int i = 0; i < 300; ++i) {
            step(0.1);
            const QQuickItem *d = drop(0);
            const qreal middle = d->y() + d->height() / 2;
            QVERIFY2(middle > 0.2 * 800 && middle < 800, qPrintable(QString::number(middle)));
            dimmest = qMin(dimmest, d->opacity());
            brightest = qMax(brightest, d->opacity());
        }
        QVERIFY(dimmest < 0.3 && brightest > 0.8);
    }

    // Leaves rock as they fall, and turn over.
    void leavesRockAndTurn()
    {
        show(QStringLiteral("leaves"));
        QVERIFY(built() > 0);
        qreal lowest = 1e9, highest = -1e9, flips = 0;
        for (int i = 0; i < 50; ++i) {
            step(0.1);
            lowest = qMin(lowest, drop(0)->rotation());
            highest = qMax(highest, drop(0)->rotation());
            if (drop(0)->property("flip").toReal() < 0)
                ++flips;
        }
        QVERIFY2(highest - lowest > 20, "it rocks");
        QVERIFY2(flips > 0, "it shows its back");
    }

    // At night the snow is lighter, so it shows on the dark canvas.
    void snowLightensAtNight()
    {
        const qreal byDay = weather()->property("snow").value<QColor>().lightnessF();
        m_scene->setProperty("dusk", 1.0);
        const qreal atNight = weather()->property("snow").value<QColor>().lightnessF();
        QVERIFY2(atNight > byDay + 0.15, qPrintable(QStringLiteral("%1 → %2").arg(byDay).arg(atNight)));
        QVERIFY(atNight > 0.85);
    }
};

QTEST_MAIN(TestWeather)
#include "tst_weather.moc"
