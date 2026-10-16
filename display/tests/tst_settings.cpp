#include <QtTest>

#include <QNetworkProxy>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickWindow>

#include "backend/SupabaseClient.h"
#include "hardware/DisplayController.h"
#include "hardware/PerfMonitor.h"
#include "hardware/SystemController.h"
#include "models/Assistant.h"
#include "models/FeedStore.h"
#include "models/QrImageProvider.h"
#include "voice/VoiceClient.h"

// The settings sheet's tabs, at each panel size: which tab each way of
// opening it lands on, tabs a touch target each that take every tap across
// their own width, pages that fit the sheet, and a sheet that keeps its
// size when the tab changes. Against the real controllers and the demo
// store. Pictures of every tab, light and dark, go to $MCFLY_TEST_SHOTS.
class TestSettings : public QObject
{
    Q_OBJECT

    SupabaseClient *m_client = nullptr;
    FeedStore *m_store = nullptr;
    VoiceClient *m_voice = nullptr;
    Assistant *m_ai = nullptr;
    DisplayController *m_device = nullptr;
    SystemController *m_system = nullptr;
    PerfMonitor *m_perf = nullptr;
    QQmlEngine *m_engine = nullptr;
    QQuickWindow *m_window = nullptr;
    QObject *m_root = nullptr;

    const QStringList m_tabs{QStringLiteral("screen"), QStringLiteral("voice"), QStringLiteral("wifi"),
                             QStringLiteral("account"), QStringLiteral("system"), QStringLiteral("admin")};

    QObject *theme() { return m_engine->singletonInstance<QObject *>("McFly", "Theme"); }
    QObject *sheet() { return m_root->property("sheet").value<QObject *>(); }
    QString tab() { return sheet()->property("tab").toString(); }
    static void collect(QQuickItem *item, const QString &name, QList<QQuickItem *> &out)
    {
        for (QQuickItem *child : item->childItems()) {
            if (child->objectName() == name)
                out << child;
            collect(child, name, out);
        }
    }
    QQuickItem *named(const QString &name)
    {
        QList<QQuickItem *> out;
        collect(m_window->contentItem(), name, out);
        return out.value(0);
    }

    // The sheet in a window of a panel's size, the tier set as Main.qml sets it.
    bool show(int w, int h)
    {
        const QString tier = h > w ? QStringLiteral("tall") : w < 1000 ? QStringLiteral("mini")
                           : w < 1600 ? QStringLiteral("compact") : QStringLiteral("wide");
        theme()->setProperty("tier", tier);
        theme()->setProperty("shortSide", qMin(w, h));
        m_window = new QQuickWindow;
        m_window->resize(w, h);
        QQmlComponent component(m_engine);
        component.setData("import QtQuick\nimport McFly\n"
                          "Rectangle { color: Theme.background; property alias sheet: s; SettingsSheet { id: s } }",
                          QUrl());
        m_root = component.create();
        if (!m_root) {
            qWarning("%s", qPrintable(component.errorString()));
            return false;
        }
        auto *item = qobject_cast<QQuickItem *>(m_root);
        item->setParentItem(m_window->contentItem());
        item->setSize(QSizeF(w, h));
        m_window->show();
        return QTest::qWaitForWindowExposed(m_window);
    }
    void call(const char *method, const QVariant &arg = {})
    {
        if (arg.isValid())
            QMetaObject::invokeMethod(sheet(), method, Q_ARG(QVariant, arg));
        else
            QMetaObject::invokeMethod(sheet(), method);
    }
    void settle() { QTest::qWait(450); } // the sheet's entrance and a tab's fade
    void shoot(const QString &name)
    {
        const QString dir = qEnvironmentVariable("MCFLY_TEST_SHOTS");
        if (!dir.isEmpty())
            m_window->grabWindow().save(dir + QLatin1Char('/') + name + QStringLiteral(".png"));
    }

private slots:
    void initTestCase()
    {
        QCoreApplication::setOrganizationName("McFly-tests");
        QCoreApplication::setApplicationName("tst_settings");
        QSettings().clear();
        QNetworkProxy::setApplicationProxy(QNetworkProxy::NoProxy);

        m_client = new SupabaseClient(QUrl(), QString(), this);
        m_store = new FeedStore(m_client, true, this);
        m_store->start(); // demo mode
        m_voice = new VoiceClient(QUrl(QStringLiteral("ws://127.0.0.1:9")), this); // never started: no voice
        m_ai = new Assistant(m_client, m_store, m_voice, this);
        m_device = new DisplayController(this);
        m_system = new SystemController(this);
        m_perf = new PerfMonitor(false, this);

        qmlRegisterSingletonInstance("McFly.Core", 1, 0, "Store", m_store);
        qmlRegisterSingletonInstance("McFly.Core", 1, 0, "AI", m_ai);
        qmlRegisterSingletonInstance("McFly.Core", 1, 0, "Voice", m_voice);
        qmlRegisterSingletonInstance("McFly.Core", 1, 0, "Device", m_device);
        qmlRegisterSingletonInstance("McFly.Core", 1, 0, "System", m_system);
        qmlRegisterSingletonInstance("McFly.Core", 1, 0, "Perf", m_perf);
        m_engine = new QQmlEngine(this);
        m_engine->addImportPath(QStringLiteral(MCFLY_TEST_QML_DIR));
        m_engine->addImageProvider(QStringLiteral("qr"), new QrImageProvider);
    }

    void cleanup()
    {
        m_device->setDarkMode(false);
        delete m_root;
        m_root = nullptr;
        delete m_window;
        m_window = nullptr;
    }

    void cleanupTestCase() { QSettings().clear(); }

    // The gear opens Screen; setup's Wi-Fi button opens Wi-Fi with a scan;
    // --screen admin opens Admin; anything else, Screen. Closing goes back.
    void opensOnTheRightTab()
    {
        QVERIFY(show(1280, 800));
        call("open");
        QCOMPARE(tab(), QStringLiteral("screen"));
        call("close");
        call("openWifi");
        QCOMPARE(tab(), QStringLiteral("wifi"));
        QVERIFY(sheet()->property("opened").toBool() || sheet()->property("visible").toBool());
        call("close");
        QTRY_COMPARE(tab(), QStringLiteral("screen"));
        call("openAdmin");
        QCOMPARE(tab(), QStringLiteral("admin"));
        call("close");
        call("openTab", QStringLiteral("account"));
        QCOMPARE(tab(), QStringLiteral("account"));
        call("close");
        call("openTab", QStringLiteral("nowhere"));
        QCOMPARE(tab(), QStringLiteral("screen"));
    }

    void tabsAndPages_data()
    {
        QTest::addColumn<int>("w");
        QTest::addColumn<int>("h");
        QTest::newRow("1280x800") << 1280 << 800;
        QTest::newRow("1920x1080") << 1920 << 1080;
        QTest::newRow("800x480") << 800 << 480;
        QTest::newRow("720x1280") << 720 << 1280;
    }

    // Each tab a touch target, edge to edge with the next, and a tap in it
    // picks it. Each page no wider than the sheet's body, and the sheet the
    // same size whichever tab is showing.
    void tabsAndPages()
    {
        QFETCH(int, w);
        QFETCH(int, h);
        QVERIFY(show(w, h));
        call("open");
        settle();
        auto *popup = sheet();
        const qreal height = popup->property("height").toReal();
        QVERIFY2(height > 0 && height <= h, qPrintable(QString::number(height)));
        QQuickItem *body = named(QStringLiteral("settingsBody"));
        QVERIFY(body);
        const qreal touch = theme()->property("touchTarget").toReal();

        QQuickItem *previous = nullptr;
        for (const QString &id : m_tabs) {
            QQuickItem *t = named(QStringLiteral("tab-") + id);
            QVERIFY2(t, qPrintable(id));
            QVERIFY2(t->height() >= touch && t->width() >= touch,
                     qPrintable(QStringLiteral("%1: %2×%3").arg(id).arg(t->width()).arg(t->height())));
            if (previous) {
                const QPointF end = previous->mapToScene(QPointF(previous->width(), 0));
                const QPointF start = t->mapToScene(QPointF(0, 0));
                QVERIFY2(qAbs(end.x() - start.x()) < 0.5, qPrintable(id + QStringLiteral(" doesn't meet the tab before it")));
            }
            previous = t;

            QTest::mouseClick(m_window, Qt::LeftButton, {}, t->mapToScene(QPointF(t->width() / 2, t->height() / 2)).toPoint());
            QTRY_COMPARE(tab(), id);
            settle();
            QCOMPARE(popup->property("height").toReal(), height);

            // Nothing on the page reaches past the body's sides.
            auto *page = sheet()->property("currentPage").value<QQuickItem *>();
            QVERIFY(page);
            QVERIFY2(page->width() <= body->width() + 0.5, qPrintable(id));
            QList<QQuickItem *> stack{page};
            while (!stack.isEmpty()) {
                QQuickItem *item = stack.takeLast();
                if (!item->isVisible() || item->opacity() == 0)
                    continue;
                const QRectF r = item->mapRectToItem(page, QRectF(0, 0, item->width(), item->height()));
                QVERIFY2(r.left() >= -1 && r.right() <= page->width() + 1,
                         qPrintable(QStringLiteral("%1: %2 (%3) at %4..%5 of %6").arg(id, QString::fromLatin1(item->metaObject()->className()),
                                    item->objectName()).arg(r.left()).arg(r.right()).arg(page->width())));
                stack << item->childItems();
            }
            shoot(QStringLiteral("settings-%1x%2-%3").arg(w).arg(h).arg(id));
        }

        m_device->setDarkMode(true);
        QTest::qWait(1200); // the palette's fade
        for (const QString &id : m_tabs) {
            sheet()->setProperty("tab", id);
            settle();
            shoot(QStringLiteral("settings-%1x%2-%3-dark").arg(w).arg(h).arg(id));
        }
    }

    // While the keyboard is up the tabs give the field their room; a page
    // change clears a half-typed Wi-Fi join and any confirmation.
    void changingTabResets()
    {
        QVERIFY(show(1280, 800));
        call("openWifi");
        sheet()->setProperty("joinSsid", QStringLiteral("Upstairs"));
        sheet()->setProperty("confirmingPower", QStringLiteral("reboot"));
        sheet()->setProperty("tab", QStringLiteral("system"));
        QCOMPARE(sheet()->property("joinSsid").toString(), QString());
        QCOMPARE(sheet()->property("confirmingPower").toString(), QString());
        QVERIFY(!sheet()->property("typing").toBool());
        QVERIFY(named(QStringLiteral("settingsTabs"))->isVisible());
    }
};

QTEST_MAIN(TestSettings)
#include "tst_settings.moc"
