#include <QtTest>

#include <QFile>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickWindow>
#include <QVector2D>
#include <QVector4D>

#include <array>
#include <cstring>

#include "graphics/ScaledShader.h"

// ScaledShader (src/graphics): a ShaderEffect shader's uniform block, filled
// from the properties of the same names at the offsets the shader's own
// reflection gives, the way ShaderEffect fills it, and kept up to date as
// they change. Offscreen there is no RHI to draw with, so what is checked is
// the block the renderer uploads; the drawing itself is checked on the Pi
// (docs/PI_SETUP.md, the bench).
static const char *kScene = R"(
import QtQuick
import McFly.Core

Item {
    width: 400
    height: 300
    property alias sky: sky
    property alias tile: tile
    property alias fed: fed

    // Its own properties: a sky's uniforms (shaders/arc.frag).
    ScaledShader {
        id: sky
        anchors.fill: parent
        visible: false   // nothing to draw with offscreen
        fixedColorBufferWidth: 200
        fixedColorBufferHeight: 150
        readonly property size size: Qt.size(width, height)
        property real time: 12.5
        property real strength: 0.75
        property real seed: 3
        property real dim: 1
        property vector4d canvas: Qt.vector4d(0.1, 0.2, 0.3, 0)
        property vector4d s0: Qt.vector4d(1, 2, 3, 4)
        property vector4d s1
        property vector4d s2
        property vector4d s3
        fragmentShader: "qrc:/McFly/shaders/arc.frag.qsb"
    }

    // Another object's (shaders/gradienttile.frag): a colour arrives
    // premultiplied, as ShaderEffect hands it over.
    QtObject {
        id: fed
        property size size: Qt.size(320, 200)
        property real radius: 24
        property real dpr: 0.75
        property real rings: 2
        property real r1: 120
        property real glass: 1
        property real grain: 0.035
        property real soft: 0
        property vector2d r1c: Qt.vector2d(10, 20)
        property vector2d r2c
        property vector2d b0
        property vector2d b1
        property vector2d b2
        property vector2d b3
        property vector4d lch0
        property vector4d lch1
        property vector4d lch2
        property vector4d tint
        property vector4d hilite
        property color rimColor: Qt.rgba(1, 0.5, 0.25, 0.5)
    }
    ScaledShader {
        id: tile
        visible: false
        uniformSource: fed
        fragmentShader: "qrc:/McFly/shaders/gradienttile.frag.qsb"
    }
}
)";

class TestScaledShader : public QObject
{
    Q_OBJECT

    QQmlEngine *m_engine = nullptr;
    QQuickWindow *m_window = nullptr;
    QObject *m_scene = nullptr;

    ScaledShader *shader(const char *name) const
    {
        return m_scene->property(name).value<ScaledShader *>();
    }

    // Where the shader itself says a uniform lives.
    static int offset(const QString &qsb, const QByteArray &name)
    {
        QFile file(qsb);
        if (!file.open(QIODevice::ReadOnly))
            return -1;
        const QShader shader = QShader::fromSerialized(file.readAll());
        for (const QShaderDescription::UniformBlock &block : shader.description().uniformBlocks())
            for (const QShaderDescription::BlockVariable &member : block.members)
                if (block.binding == 0 && member.name == name)
                    return member.offset;
        return -1;
    }
    template<typename T>
    static T read(ScaledShader *s, const QString &qsb, const QByteArray &name)
    {
        const int at = offset(qsb, name);
        T value{};
        const QByteArray block = s->uniformBlock();
        if (at >= 0 && at + int(sizeof(T)) <= block.size())
            std::memcpy(&value, block.constData() + at, sizeof(T));
        return value;
    }
    static float f(ScaledShader *s, const QByteArray &name)
    {
        return read<float>(s, QStringLiteral(":/McFly/shaders/arc.frag.qsb"), name);
    }

private slots:
    void initTestCase()
    {
        qmlRegisterType<ScaledShader>("McFly.Core", 1, 0, "ScaledShader");
    }

    void init()
    {
        m_engine = new QQmlEngine(this);
        QQmlComponent component(m_engine);
        component.setData(kScene, QUrl());
        m_scene = component.create();
        QVERIFY2(m_scene, qPrintable(component.errorString()));
        // In a window, so a change is read before the next frame (polish).
        m_window = new QQuickWindow;
        qobject_cast<QQuickItem *>(m_scene)->setParentItem(m_window->contentItem());
        m_window->resize(400, 300);
        m_window->show();
    }

    void cleanup()
    {
        delete m_scene;
        m_scene = nullptr;
        delete m_window;
        m_window = nullptr;
        delete m_engine;
        m_engine = nullptr;
    }

    void fillsTheBlockFromItsProperties()
    {
        ScaledShader *s = shader("sky");
        QCOMPARE(s->status(), ScaledShader::Compiled);
        QCOMPARE(s->property("fixedColorBufferWidth").toInt(), 200);
        const QString qsb = QStringLiteral(":/McFly/shaders/arc.frag.qsb");
        // What ShaderEffect fills in: drawn at full opacity (the item's is
        // applied with the picture), the matrix unused by our vertex stage.
        QCOMPARE(f(s, "qt_Opacity"), 1.0f);
        const auto matrix = read<std::array<float, 16>>(s, qsb, "qt_Matrix");
        QCOMPARE(QMatrix4x4(matrix.data()).transposed(), QMatrix4x4());
        QCOMPARE(read<QVector2D>(s, qsb, "size"), QVector2D(400, 300));
        QCOMPARE(f(s, "time"), 12.5f);
        QCOMPARE(f(s, "strength"), 0.75f);
        QCOMPARE(f(s, "seed"), 3.0f);
        QCOMPARE(read<QVector4D>(s, qsb, "canvas"), QVector4D(0.1f, 0.2f, 0.3f, 0));
        QCOMPARE(read<QVector4D>(s, qsb, "s0"), QVector4D(1, 2, 3, 4));
    }

    // Several uniforms change on a clock's tick; the block has them all by
    // the next frame.
    void followsItsProperties()
    {
        ScaledShader *s = shader("sky");
        s->setProperty("time", 20.25);
        s->setProperty("s0", QVector4D(5, 6, 7, 8));
        QTRY_COMPARE(f(s, "time"), 20.25f);
        QCOMPARE(read<QVector4D>(s, QStringLiteral(":/McFly/shaders/arc.frag.qsb"), "s0"), QVector4D(5, 6, 7, 8));
        qobject_cast<QQuickItem *>(m_scene)->setWidth(100);   // the sky fills it
        QTRY_COMPARE(read<QVector2D>(s, QStringLiteral(":/McFly/shaders/arc.frag.qsb"), "size"), QVector2D(100, 300));
    }

    void readsAnotherObjectsProperties()
    {
        ScaledShader *s = shader("tile");
        const QString qsb = QStringLiteral(":/McFly/shaders/gradienttile.frag.qsb");
        QCOMPARE(s->status(), ScaledShader::Compiled);
        QCOMPARE(read<QVector2D>(s, qsb, "size"), QVector2D(320, 200));
        QCOMPARE(read<float>(s, qsb, "radius"), 24.0f);
        QCOMPARE(read<QVector2D>(s, qsb, "r1c"), QVector2D(10, 20));
        const QVector4D rim = read<QVector4D>(s, qsb, "rimColor");   // QColor keeps 16 bits a channel
        QVERIFY2((rim - QVector4D(0.5f, 0.25f, 0.125f, 0.5f)).length() < 1e-3, qPrintable(QDebug::toString(rim)));
        QObject *fed = m_scene->property("fed").value<QObject *>();
        fed->setProperty("radius", 8.0);
        QTRY_COMPARE(read<float>(s, qsb, "radius"), 8.0f);
    }

    void aShaderItCantReadIsAnError()
    {
        ScaledShader *s = shader("sky");
        QTest::ignoreMessage(QtWarningMsg, QRegularExpression("ScaledShader: .*nope.* not a shader"));
        s->setFragmentShader(QUrl(QStringLiteral("qrc:/McFly/shaders/nope.frag.qsb")));
        QCOMPARE(s->status(), ScaledShader::Error);
        QVERIFY(s->uniformBlock().isEmpty());
        s->setFragmentShader(QUrl(QStringLiteral("qrc:/McFly/shaders/arc.frag.qsb")));
        QCOMPARE(s->status(), ScaledShader::Compiled);
        QCOMPARE(f(s, "time"), 12.5f);
    }
};

QTEST_MAIN(TestScaledShader)
#include "tst_scaledshader.moc"
