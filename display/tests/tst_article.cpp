#include <QtTest>

#include <QBuffer>
#include <QImage>
#include <QJsonArray>
#include <QNetworkProxy>
#include <QPainter>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickWindow>

#include "FakeServer.h"
#include "backend/SupabaseClient.h"
#include "models/ArticleReader.h"
#include "models/FeedStore.h"
#include "models/QrImageProvider.h"

// Stands in for DisplayController.
class FakeDevice : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString mood READ mood CONSTANT)
    Q_PROPERTY(bool darkMode READ darkMode CONSTANT)
    Q_PROPERTY(bool idle READ idle CONSTANT)
    Q_PROPERTY(bool animatedTiles READ animatedTiles CONSTANT)
public:
    QString mood() const { return QStringLiteral("day"); }
    bool darkMode() const { return false; }
    bool idle() const { return false; }
    bool animatedTiles() const { return false; }
};

// The article behind a story: what the `article` function's answer becomes
// for the News screen (ArticleReader::shape), asking it against a fake
// Supabase (once per story, refreshing an expired token, failing softly),
// and the open story at each panel size with a summary and a full story.
// Pictures go to $MCFLY_TEST_SHOTS when it is set.
class TestArticle : public QObject
{
    Q_OBJECT

    FakeServer m_server;
    using Request = FakeServer::Request;
    // The screen's world, made once: an instance singleton belongs to one engine.
    SupabaseClient *m_offline = nullptr;
    FeedStore *m_store = nullptr;
    ArticleReader *m_reader = nullptr;
    FakeDevice m_device;
    QQmlEngine *m_engine = nullptr;

    static QVariantMap story(const QString &id = QStringLiteral("0b6f3a52-1c1e-4d7e-9b1a-2f0c8e9d7a61"))
    {
        return {{"id", id},
                {"headline", "Fed holds rates"},
                {"takeaway", "Markets expected it; the tone matters more."},
                {"url", "https://paper.test/fed"},
                {"imageUrl", ""},
                {"sourceDomain", "paper.test"},
                {"sectionName", "Markets"}};
    }

    // An article as the function sends it, pictures served by `base`.
    static QJsonObject article(const QString &base = QStringLiteral("https://cdn.test"))
    {
        QJsonArray blocks{
            QJsonObject{{"type", "p"}, {"text", "The Federal Reserve held its benchmark rate steady on Wednesday, as expected."}},
            QJsonObject{{"type", "h"}, {"text", "What changed"}},
            QJsonObject{{"type", "p"}, {"text", "Officials removed a line about further tightening, which markets read as a nod to cuts next year."}},
            QJsonObject{{"type", "image"}, {"url", base + "/chart.png"}, {"caption", "The rate since 2020"}},
            QJsonObject{{"type", "quote"}, {"text", "We are in no hurry."}, {"cite", "The chair"}},
            QJsonObject{{"type", "list"}, {"items", QJsonArray{"Rates unchanged", "Two dissents"}}, {"ordered", true}},
            QJsonObject{{"type", "video"}, {"url", "https://www.youtube.com/watch?v=dQw4w9WgXcQ"}, {"provider", "youtube"},
                        {"poster", base + "/poster.png"}, {"caption", "The press conference"}},
            QJsonObject{{"type", "table"}},
            QJsonObject{{"type", "image"}, {"url", "javascript:alert(1)"}},
            QJsonObject{{"type", "p"}, {"text", "Bond yields fell after the statement, and stocks closed higher."}},
        };
        return {{"item_id", "0b6f3a52-1c1e-4d7e-9b1a-2f0c8e9d7a61"},
                {"status", "ready"},
                {"title", "Fed holds rates"},
                {"byline", "Pat Writer"},
                {"site_name", "The Paper"},
                {"published_at", "2026-10-20T19:00:00.000Z"},
                {"lead_image", base + "/lead.png"},
                {"blocks", blocks},
                {"word_count", 690},
                {"summary", "The Fed held rates and dropped its tightening bias. Markets took it as a hint of cuts next year."},
                {"points", QJsonArray{"Rates unchanged at 4%", "Tightening line removed", "Two officials dissented"}},
                {"summary_model", "claude-sonnet-5-5"},
                {"illustration_url", base + "/drawn.png?token=signed"},
                {"illustration_model", "grok-imagine-image-2.0"}};
    }

    static QByteArray png(const QColor &a, const QColor &b, QSize size = {640, 400})
    {
        QImage image(size, QImage::Format_RGB32);
        QPainter p(&image);
        QLinearGradient g(0, 0, size.width(), size.height());
        g.setColorAt(0, a);
        g.setColorAt(1, b);
        p.fillRect(image.rect(), g);
        p.end();
        QByteArray bytes;
        QBuffer buffer(&bytes);
        buffer.open(QIODevice::WriteOnly);
        image.save(&buffer, "PNG");
        return bytes;
    }

    QList<Request> asks() const { return m_server.requests("POST", "/functions/v1/article"); }

private slots:
    void initTestCase()
    {
        QNetworkProxy::setApplicationProxy(QNetworkProxy::NoProxy);
        QVERIFY(m_server.listen());

        m_offline = new SupabaseClient(QUrl(), QString(), this);
        m_store = new FeedStore(m_offline, true, this);
        m_store->start(); // demo
        m_reader = new ArticleReader(m_offline, true, this);
        qmlRegisterSingletonInstance("McFly.Core", 1, 0, "Store", m_store);
        qmlRegisterSingletonInstance("McFly.Core", 1, 0, "Device", &m_device);
        qmlRegisterSingletonInstance("McFly.Core", 1, 0, "Reader", m_reader);
        m_engine = new QQmlEngine(this);
        m_engine->addImportPath(QStringLiteral(MCFLY_TEST_QML_DIR));
        m_engine->addImageProvider(QStringLiteral("qr"), new QrImageProvider);
    }
    void init() { m_server.reset(); }

    void shapesTheFunctionsArticle()
    {
        const QVariantMap a = ArticleReader::shape(article(), story());
        QCOMPARE(a.value("status").toString(), QStringLiteral("ready"));
        QVERIFY(a.value("hasFullStory").toBool());
        QCOMPARE(a.value("summary").toString(), QStringLiteral("The Fed held rates and dropped its tightening bias. Markets took it as a hint of cuts next year."));
        QVERIFY(!a.value("summaryIsTakeaway").toBool());
        QCOMPARE(a.value("summaryBy").toString(), QStringLiteral("Summarized by Claude"));
        QCOMPARE(a.value("points").toStringList().size(), 3);
        QCOMPARE(a.value("readingTime").toString(), QStringLiteral("3 min read"));
        QVERIFY(a.value("byline").toString().startsWith(QStringLiteral("Pat Writer · paper.test · ")));
        QCOMPARE(a.value("leadImage").toString(), QStringLiteral("https://cdn.test/lead.png"));
        QVERIFY(a.value("note").toString().isEmpty());
        QCOMPARE(a.value("illustration").toString(), QStringLiteral("https://cdn.test/drawn.png?token=signed"));
        QCOMPARE(a.value("illustrationBy").toString(), QStringLiteral("Drawn by Grok"));

        // Unknown and unusable blocks are left out; a list is its lines.
        const QVariantList blocks = a.value("blocks").toList();
        QStringList types;
        for (const QVariant &b : blocks)
            types << b.toMap().value("type").toString();
        QCOMPARE(types, (QStringList{"p", "h", "p", "image", "quote", "list", "video", "p"}));
        QCOMPARE(blocks.at(5).toMap().value("text").toString(), QStringLiteral("1.  Rates unchanged\n2.  Two dissents"));
        QCOMPARE(blocks.at(6).toMap().value("label").toString(), QStringLiteral("YouTube"));
        QCOMPARE(a.value("media").toList().size(), 2);
    }

    void keepsTheTakeawayWhenThePageGivesLittle()
    {
        QJsonObject preview{{"status", "partial"}, {"blocks", QJsonArray{QJsonObject{{"type", "p"}, {"text", "Teaser."}}}}};
        QVariantMap a = ArticleReader::shape(preview, story());
        QVERIFY(!a.value("hasFullStory").toBool());
        QCOMPARE(a.value("summary").toString(), story().value("takeaway").toString());
        QVERIFY(a.value("summaryIsTakeaway").toBool());
        QVERIFY(a.value("summaryBy").toString().isEmpty());
        QVERIFY(a.value("note").toString().startsWith(QStringLiteral("paper.test shares only a preview")));

        // No takeaway: the preview's own words.
        QVariantMap bare = story();
        bare.insert("takeaway", QString());
        QCOMPARE(ArticleReader::shape(preview, bare).value("summary").toString(), QStringLiteral("Teaser."));

        QVERIFY(a.value("illustration").toString().isEmpty());
        QVERIFY(a.value("illustrationBy").toString().isEmpty());
        a = ArticleReader::shape(QJsonObject{{"status", "unavailable"}, {"blocks", QJsonArray()}}, story());
        QVERIFY(a.value("note").toString().startsWith(QStringLiteral("This page can't be shown here")));

        // While loading: the takeaway and no small print.
        a = ArticleReader::shape({}, story());
        QCOMPARE(a.value("summary").toString(), story().value("takeaway").toString());
        QVERIFY(a.value("note").toString().isEmpty());
        QVERIFY(a.value("status").toString().isEmpty());
    }

    void asksOncePerStory()
    {
        m_server.route("/functions/v1/article", [](const Request &) {
            return FakeServer::json(QJsonDocument(QJsonObject{{"article", article()}}), 200, 80);
        });
        SupabaseClient client(m_server.baseUrl(), QStringLiteral("anon"));
        client.setSession(QStringLiteral("access-1"), QStringLiteral("refresh-1"));
        ArticleReader reader(&client, false);

        reader.open(story());
        QCOMPARE(reader.state(), QStringLiteral("loading"));
        QCOMPARE(reader.article().value("summary").toString(), story().value("takeaway").toString());
        QTRY_COMPARE(reader.state(), QStringLiteral("ready"));
        QCOMPARE(asks().size(), 1);
        QCOMPARE(asks().first().body.value("item_id").toString(), story().value("id").toString());
        QCOMPARE(asks().first().auth, QByteArray("Bearer access-1"));
        QVERIFY(reader.article().value("hasFullStory").toBool());

        // Closed and opened again: the kept copy, no second request.
        reader.close();
        QCOMPARE(reader.state(), QString());
        reader.open(story());
        QCOMPARE(reader.state(), QStringLiteral("ready"));
        QCOMPARE(asks().size(), 1);
    }

    void refreshesAnExpiredTokenOnce()
    {
        int calls = 0;
        m_server.route("/functions/v1/article", [&calls](const Request &) {
            return ++calls == 1 ? FakeServer::json("{\"error\":\"expired\"}", 401)
                                : FakeServer::json(QJsonDocument(QJsonObject{{"article", article()}}));
        });
        m_server.route("/auth/v1/token", [](const Request &) {
            return FakeServer::json(R"({"access_token":"access-2","refresh_token":"refresh-2"})");
        });
        SupabaseClient client(m_server.baseUrl(), QStringLiteral("anon"));
        client.setSession(QStringLiteral("access-1"), QStringLiteral("refresh-1"));
        ArticleReader reader(&client, false);
        reader.open(story());
        QTRY_COMPARE(reader.state(), QStringLiteral("ready"));
        QCOMPARE(asks().size(), 2);
        QCOMPARE(asks().last().auth, QByteArray("Bearer access-2"));
    }

    void failsSoftlyAndAsksAgainNextTime()
    {
        m_server.route("/functions/v1/article", [](const Request &) { return FakeServer::json("{\"error\":\"something went wrong\"}", 500); });
        SupabaseClient client(m_server.baseUrl(), QStringLiteral("anon"));
        client.setSession(QStringLiteral("access-1"), QStringLiteral("refresh-1"));
        ArticleReader reader(&client, false);
        reader.open(story());
        QTRY_COMPARE(reader.state(), QStringLiteral("failed"));
        QCOMPARE(reader.article().value("summary").toString(), story().value("takeaway").toString());
        QVERIFY(reader.article().value("note").toString().startsWith(QStringLiteral("The article couldn't be loaded.")));
        QVERIFY(!reader.article().value("hasFullStory").toBool());

        // A failure isn't kept.
        reader.close();
        reader.open(story());
        QTRY_COMPARE(asks().size(), 2);
    }

    // The function answers before Grok is done: what's ready shows at once,
    // with a line saying what's on its way, and the story asks again until
    // the summary and the picture are in.
    void asksAgainWhileWorkIsPending()
    {
        int calls = 0;
        m_server.route("/functions/v1/article", [&calls](const Request &) {
            QJsonObject a = article();
            if (++calls == 1) {
                a.insert("status", "unavailable");
                a.insert("blocks", QJsonArray());
                a.insert("word_count", 0);
                a.remove("summary");
                a.remove("points");
                a.remove("illustration_url");
                a.insert("pending", true);
            } else {
                a.insert("status", "unavailable");
                a.insert("pending", false);
            }
            return FakeServer::json(QJsonDocument(QJsonObject{{"article", a}}));
        });
        SupabaseClient client(m_server.baseUrl(), QStringLiteral("anon"));
        client.setSession(QStringLiteral("access-1"), QStringLiteral("refresh-1"));
        ArticleReader reader(&client, false);
        reader.open(story());
        QTRY_COMPARE(reader.state(), QStringLiteral("ready"));
        QVERIFY(reader.article().value("pending").toBool());
        QCOMPARE(reader.article().value("working").toString(), QStringLiteral("Summarizing the story…"));
        QCOMPARE(reader.article().value("summary").toString(), story().value("takeaway").toString());
        QTRY_VERIFY_WITH_TIMEOUT(!reader.article().value("pending").toBool(), 10000);
        QCOMPARE(asks().size(), 2);
        QVERIFY(reader.article().value("working").toString().isEmpty());
        QVERIFY(reader.article().value("summary").toString().startsWith(QStringLiteral("The Fed held rates")));
        QCOMPARE(reader.article().value("illustrationBy").toString(), QStringLiteral("Drawn by Grok"));
        QTest::qWait(6500);
        QCOMPARE(asks().size(), 2); // done: no more asking
    }

    void aStoryClosedBeforeItsAnswerStaysClosed()
    {
        m_server.route("/functions/v1/article", [](const Request &) {
            return FakeServer::json(QJsonDocument(QJsonObject{{"article", article()}}), 200, 150);
        });
        SupabaseClient client(m_server.baseUrl(), QStringLiteral("anon"));
        client.setSession(QStringLiteral("access-1"), QStringLiteral("refresh-1"));
        ArticleReader reader(&client, false);
        reader.open(story());
        reader.close();
        QTRY_COMPARE(asks().size(), 1);
        QTest::qWait(300);
        QCOMPARE(reader.state(), QString());
        QVERIFY(reader.article().isEmpty());
    }

    // The open story on each panel, summary then full story, with pictures
    // and a video from the fake server and no QML errors.
    void theOpenStoryAtEverySize_data()
    {
        QTest::addColumn<int>("w");
        QTest::addColumn<int>("h");
        QTest::addColumn<QString>("tier");
        QTest::newRow("1280x800") << 1280 << 800 << "compact";
        QTest::newRow("1920x1080") << 1920 << 1080 << "wide";
        QTest::newRow("800x480") << 800 << 480 << "mini";
        QTest::newRow("720x1280") << 720 << 1280 << "tall";
    }
    void theOpenStoryAtEverySize()
    {
        QFETCH(int, w);
        QFETCH(int, h);
        QFETCH(QString, tier);

        const QByteArray lead = png(QColor(0x5B7CF5), QColor(0xF07F5A), {1200, 800});
        const QByteArray chart = png(QColor(0x3DB37A), QColor(0xF6B94A));
        const QByteArray poster = png(QColor(0x222222), QColor(0x7A64E8));
        const QByteArray drawn = png(QColor(0xF6B94A), QColor(0x7A64E8), {1024, 768});
        m_server.route("/img/drawn.png", [drawn](const Request &) { return FakeServer::Reply{200, "image/png", drawn, 0}; });
        m_server.route("/img/lead.png", [lead](const Request &) { return FakeServer::Reply{200, "image/png", lead, 0}; });
        m_server.route("/img/chart.png", [chart](const Request &) { return FakeServer::Reply{200, "image/png", chart, 0}; });
        m_server.route("/img/poster.png", [poster](const Request &) { return FakeServer::Reply{200, "image/png", poster, 0}; });

        QStringList qmlErrors;
        static QStringList *sink = nullptr;
        sink = &qmlErrors;
        const QtMessageHandler previous = qInstallMessageHandler([](QtMsgType type, const QMessageLogContext &, const QString &msg) {
            if (type != QtDebugMsg && msg.contains(QLatin1String(".qml")))
                sink->append(msg);
        });

        ArticleReader &reader = *m_reader;
        auto *theme = m_engine->singletonInstance<QObject *>("McFly", "Theme");
        QVERIFY(theme);
        theme->setProperty("tier", tier);
        theme->setProperty("shortSide", qMin(w, h));

        QQmlComponent component(m_engine);
        component.setData("import QtQuick\nimport McFly\nNewsScreen {}", QUrl());
        QScopedPointer<QObject> screen(component.create());
        QVERIFY2(screen, qPrintable(component.errorString()));
        QQuickWindow window;
        window.resize(w, h);
        auto *item = qobject_cast<QQuickItem *>(screen.get());
        item->setParentItem(window.contentItem());
        item->setSize(QSizeF(w, h));
        window.show();
        QVERIFY(QTest::qWaitForWindowExposed(&window));

        // The hero, with a real-looking article kept for it.
        QVariantMap hero = m_store->news().value("hero").toMap();
        QVERIFY(!hero.value("headline").toString().isEmpty());
        reader.present(hero, article(m_server.baseUrl().toString() + QStringLiteral("/img")));
        screen->setProperty("story", hero);
        QCOMPARE(reader.state(), QStringLiteral("ready"));
        QVERIFY(screen->property("storyOpen").toBool());
        QTest::qWait(600); // the fade in and the pictures
        const QString dir = qEnvironmentVariable("MCFLY_TEST_SHOTS");
        if (!dir.isEmpty())
            window.grabWindow().save(QStringLiteral("%1/article-%2-summary.png").arg(dir, QTest::currentDataTag()));

        screen->setProperty("readMode", "full");
        QVERIFY(screen->property("fullShown").toBool());
        QTest::qWait(400);
        if (!dir.isEmpty())
            window.grabWindow().save(QStringLiteral("%1/article-%2-full.png").arg(dir, QTest::currentDataTag()));

        // Closing clears the reader.
        QMetaObject::invokeMethod(screen.get(), "closeStory");
        QCOMPARE(reader.state(), QString());

        qInstallMessageHandler(previous);
        sink = nullptr;
        QVERIFY2(qmlErrors.isEmpty(), qPrintable(qmlErrors.join(QLatin1Char('\n'))));
    }
};

QTEST_MAIN(TestArticle)
#include "tst_article.moc"
