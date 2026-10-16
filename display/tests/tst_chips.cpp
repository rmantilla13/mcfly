#include <QtTest>

#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickWindow>

// Stands in for DisplayController: what the theme reads.
class FakeDevice : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool idle READ idle CONSTANT)
    Q_PROPERTY(QString mood READ mood CONSTANT)
    Q_PROPERTY(bool darkMode READ darkMode CONSTANT)
public:
    bool idle() const { return false; }
    QString mood() const { return QStringLiteral("day"); }
    bool darkMode() const { return false; }
};

// A ChipRow with room around it, so taps just off its chips land on nothing else.
static const char *kScene = R"(
import QtQuick
import McFly

Window {
    width: 640
    height: 300
    property alias chips: chips
    ChipRow {
        id: chips
        x: 20
        y: 100
        width: 600
        model: [{ id: "news", label: "News" }, { id: "ops", label: "Ops" }, { id: "home", label: "Home", color: "#E2604A" }]
        current: "news"
    }
}
)";

// ChipRow's chips are shorter than a touch target, their hit areas not: a
// tap within a touch target's height of a chip picks it, at the chip
// heights the screens use. A tap between two chips picks neither (it would
// pick both if each reached over the gap), and one beyond the target nothing.
class TestChips : public QObject
{
    Q_OBJECT

    FakeDevice m_device;
    QQmlEngine *m_engine = nullptr;
    QScopedPointer<QQuickWindow> m_window;

    QQuickItem *chipRow() const { return m_window->property("chips").value<QQuickItem *>(); }
    // The chips, left to right: the Row's children but its Repeater.
    QList<QQuickItem *> chips() const
    {
        auto *content = chipRow()->property("contentItem").value<QQuickItem *>();
        QList<QQuickItem *> out;
        for (QQuickItem *item : content->childItems().first()->childItems())
            if (!item->inherits("QQuickRepeater"))
                out << item;
        return out;
    }
    // What a click at this point of the window picks.
    QStringList tap(QPointF at)
    {
        QSignalSpy picked(chipRow(), SIGNAL(picked(QString)));
        QTest::mouseClick(m_window.data(), Qt::LeftButton, Qt::NoModifier, at.toPoint());
        QTest::qWait(20);
        QStringList ids;
        for (const QList<QVariant> &args : std::as_const(picked))
            ids << args.first().toString();
        return ids;
    }

private slots:
    void initTestCase()
    {
        qmlRegisterSingletonInstance("McFly.Core", 1, 0, "Device", &m_device);
        m_engine = new QQmlEngine(this);
        m_engine->addImportPath(QStringLiteral(MCFLY_TEST_QML_DIR));
    }

    void init()
    {
        QQmlComponent component(m_engine);
        component.setData(kScene, QUrl());
        m_window.reset(qobject_cast<QQuickWindow *>(component.create()));
        QVERIFY2(m_window, qPrintable(component.errorString()));
        m_window->show();
        QVERIFY(QTest::qWaitForWindowExposed(m_window.data()));
    }

    void cleanup() { m_window.reset(); }

    void tapsLandWithinATouchTarget_data()
    {
        QTest::addColumn<int>("chipHeight");
        QTest::newRow("48 px chips (Settings, Markets, Boards)") << 48;
        QTest::newRow("40 px chips (News)") << 40;
    }

    void tapsLandWithinATouchTarget()
    {
        QFETCH(int, chipHeight);
        chipRow()->setProperty("chipHeight", chipHeight);
        const QList<QQuickItem *> row = chips();
        QCOMPARE(row.size(), 3);
        QTRY_VERIFY(row.last()->width() > 0);
        // A short label's chip is still a touch target wide.
        QCOMPARE(row.at(1)->width(), 64.0);

        // Where the chips are drawn: the row's middle, chipHeight tall.
        const qreal top = chipRow()->mapToScene(QPointF(0, (chipRow()->height() - chipHeight) / 2)).y();
        const qreal bottom = top + chipHeight;
        const qreal reach = (64 - chipHeight) / 2.0;   // Theme.touchTarget
        auto left = [&](int i) { return row.at(i)->mapToScene(QPointF(0, 0)).x(); };
        auto right = [&](int i) { return left(i) + row.at(i)->width(); };
        auto middle = [&](int i) { return (left(i) + right(i)) / 2; };

        QCOMPARE(tap({middle(1), (top + bottom) / 2}), QStringList{"ops"});
        QCOMPARE(tap({middle(0), top - reach + 2}), QStringList{"news"});
        QCOMPARE(tap({middle(2), bottom + reach - 2}), QStringList{"home"});
        QCOMPARE(tap({right(0) - 1, (top + bottom) / 2}), QStringList{"news"});
        QCOMPARE(tap({left(1) + 1, (top + bottom) / 2}), QStringList{"ops"});
        QCOMPARE(tap({(right(0) + left(1)) / 2, (top + bottom) / 2}), QStringList{});
        QCOMPARE(tap({middle(1), top - reach - 4}), QStringList{});
        QCOMPARE(tap({middle(1), bottom + reach + 4}), QStringList{});
    }
};

QTEST_MAIN(TestChips)
#include "tst_chips.moc"
