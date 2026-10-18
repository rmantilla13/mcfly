#include <QtTest>

#include <QElapsedTimer>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQmlExpression>
#include <QQuickItem>
#include <QQuickWindow>
#include <QTemporaryDir>

#include "games/FourInARowEngine.h"
#include "games/PenguinWorld.h"

// Stands in for DisplayController: the theme reads the mood and dark mode,
// the screen's entrance whether tiles animate.
class FakeDevice : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool idle READ idle CONSTANT)
    Q_PROPERTY(QString mood READ mood CONSTANT)
    Q_PROPERTY(bool darkMode READ darkMode CONSTANT)
    Q_PROPERTY(bool animatedTiles READ animatedTiles CONSTANT)
public:
    bool idle() const { return false; }
    QString mood() const { return QStringLiteral("day"); }
    bool darkMode() const { return false; }
    bool animatedTiles() const { return true; }
};

// The Games tab: GamesScreen.qml and every game, loaded from a copy laid out
// like the app's resources (qrc:/McFly/...), so the relative paths between
// them are the ones the app uses. Fails on any QML error or warning.
class TestGames : public QObject
{
    Q_OBJECT

    FakeDevice m_device;
    FourInARowEngine m_fourInARow;
    QTemporaryDir m_storage;
    QQmlEngine *m_engine = nullptr;
    QQuickWindow *m_window = nullptr;
    QList<QQmlError> m_warnings;

    static QUrl url(const QString &path)
    {
        return QUrl::fromLocalFile(QStringLiteral(MCFLY_GAMES_QML_DIR "/McFly/") + path);
    }

    QQuickItem *create(const QString &path, QSize size = {})
    {
        QQmlComponent component(m_engine, url(path));
        QObject *object = component.create();
        if (!object) {
            qWarning().noquote() << component.errorString();
            return nullptr;
        }
        auto *item = qobject_cast<QQuickItem *>(object);
        item->setParentItem(m_window->contentItem());
        if (size.isValid())
            item->setSize(size);
        return item;
    }

    QVariant eval(QObject *scope, const QString &js)
    {
        QQmlExpression expression(qmlContext(scope), scope, js);
        const QVariant result = expression.evaluate();
        if (expression.hasError())
            qWarning().noquote() << expression.error().toString();
        return result;
    }

    static QString winner(const QStringList &b)
    {
        static const int lines[8][3] = {{0, 1, 2}, {3, 4, 5}, {6, 7, 8}, {0, 3, 6},
                                        {1, 4, 7}, {2, 5, 8}, {0, 4, 8}, {2, 4, 6}};
        for (const auto &l : lines) {
            if (!b[l[0]].isEmpty() && b[l[0]] == b[l[1]] && b[l[0]] == b[l[2]])
                return b[l[0]];
        }
        return {};
    }

    // Every game X can play against Hard McFly: X never gets three in a row.
    void explore(QObject *game, QStringList board, bool xToMove, int &games)
    {
        const QString won = winner(board);
        QVERIFY2(won != QLatin1String("X"), qPrintable(board.join(QLatin1Char(','))));
        if (!won.isEmpty() || !board.contains(QString())) {
            ++games;
            return;
        }
        if (xToMove) {
            for (int i = 0; i < 9; ++i) {
                if (!board[i].isEmpty())
                    continue;
                QStringList next = board;
                next[i] = QStringLiteral("X");
                explore(game, next, false, games);
                if (QTest::currentTestFailed())
                    return;
            }
            return;
        }
        QVariant move;
        QVERIFY(QMetaObject::invokeMethod(game, "bestMove", Q_RETURN_ARG(QVariant, move),
                                          Q_ARG(QVariant, QVariant(board)),
                                          Q_ARG(QVariant, QStringLiteral("O"))));
        const int i = move.toInt();
        QVERIFY(i >= 0 && i < 9 && board[i].isEmpty());
        board[i] = QStringLiteral("O");
        explore(game, board, true, games);
    }

    // Seeds 2048 with one row of tiles (left to right) and the given score.
    void seed2048(QObject *game, const QList<int> &row)
    {
        QStringList columns;
        for (int x = 0; x < 4; ++x) {
            const QString tile = x < row.size() && row[x]
                ? QStringLiteral("{position:{x:%1,y:0},value:%2}").arg(x).arg(row[x])
                : QStringLiteral("null");
            columns << QStringLiteral("[%1,null,null,null]").arg(tile);
        }
        eval(game, QStringLiteral("saved.gameState = JSON.stringify({grid:{size:4,cells:[%1]},"
                                  "score:0,over:false,won:false,keepPlaying:false}); manager.setup()")
                       .arg(columns.join(QLatin1Char(','))));
    }

    // Scoop Shop with its clock in the test's hands and a repeatable shift.
    QQuickItem *shop(QSize size = {816, 752})
    {
        QQuickItem *game = create(QStringLiteral("qml/games/ScoopShop.qml"), size);
        if (game) {
            game->setProperty("autoClock", false);
            game->setProperty("seed", 7);
        }
        return game;
    }

    // The item named `name` under `root`, in the visual tree.
    static QQuickItem *find(QQuickItem *root, const QString &name)
    {
        QList<QQuickItem *> items = root->childItems();
        for (qsizetype i = 0; i < items.size(); ++i) {
            if (items[i]->objectName() == name)
                return items[i];
            items << items[i]->childItems();
        }
        return nullptr;
    }
    // A click in the middle of the item named `name`.
    void tap(QQuickItem *root, const QString &name)
    {
        QQuickItem *item = find(root, name);
        QVERIFY2(item && item->isVisible(), qPrintable(name));
        const QPointF centre = item->mapToScene(QPointF(item->width() / 2, item->height() / 2));
        QTest::mouseClick(m_window, Qt::LeftButton, {}, centre.toPoint());
    }

    // Every tap target showing in `root`: at least 64 px each way, inside
    // the game, and none on top of another.
    void checkTargets(QQuickItem *root, int least)
    {
        QList<QRectF> rects;
        const QRectF bounds(0, 0, root->width(), root->height());
        QList<QQuickItem *> items = root->childItems();
        for (qsizetype i = 0; i < items.size(); ++i)
            items << items[i]->childItems();
        for (QQuickItem *item : std::as_const(items)) {
            if (!item->objectName().startsWith(QLatin1String("tap:")) || !item->isVisible())
                continue;
            const QRectF r = item->mapRectToItem(root, QRectF(0, 0, item->width(), item->height()));
            const QString where = QStringLiteral("%1 at %2,%3 %4x%5 in %6x%7")
                                      .arg(QString::fromLatin1(item->metaObject()->className()))
                                      .arg(r.x()).arg(r.y()).arg(r.width()).arg(r.height())
                                      .arg(root->width()).arg(root->height());
            QVERIFY2(r.width() >= 64 && r.height() >= 64, qPrintable(where));
            QVERIFY2(bounds.adjusted(-0.5, -0.5, 0.5, 0.5).contains(r), qPrintable(where));
            for (const QRectF &other : std::as_const(rects)) {
                const QRectF both = other.intersected(r);
                QVERIFY2(both.width() < 0.5 || both.height() < 0.5, qPrintable(where));
            }
            rects << r;
        }
        QVERIFY2(rects.size() >= least, qPrintable(QString::number(rects.size())));
    }

    // Lays out a four-in-a-row board from a picture, top row first: X, O or
    // "." for an empty hole. `turn` moves next.
    void setRack(QObject *game, const QStringList &picture, const QString &turn)
    {
        QStringList cells(42);
        for (int r = 0; r < 6; ++r) {
            for (int c = 0; c < 7; ++c) {
                const QChar mark = picture[5 - r][c];
                cells[r * 7 + c] = mark == QLatin1Char('.') ? QStringLiteral("\"\"")
                                                            : QStringLiteral("\"%1\"").arg(mark);
            }
        }
        eval(game, QStringLiteral("cells = [%1]; winLine = null; lastMove = -1; turn = \"%2\"")
                       .arg(cells.join(QLatin1Char(',')), turn));
    }

    int dropAt(QObject *game, int column)
    {
        QVariant ok;
        QMetaObject::invokeMethod(game, "play", Q_RETURN_ARG(QVariant, ok), Q_ARG(QVariant, column));
        return ok.toBool();
    }

private slots:
    void initTestCase()
    {
        QVERIFY(m_storage.isValid());
        qmlRegisterSingletonInstance("McFly.Core", 1, 0, "Device", &m_device);
        qmlRegisterSingletonInstance("McFly.Core", 1, 0, "FourInARowEngine", &m_fourInARow);
        qmlRegisterType<PenguinWorld>("McFly.Core", 1, 0, "PenguinWorld");
        qmlRegisterType<PenguinPicture>("McFly.Core", 1, 0, "PenguinPicture");
        m_engine = new QQmlEngine(this);
        m_engine->addImportPath(QStringLiteral(MCFLY_GAMES_QML_DIR));
        m_engine->setOfflineStoragePath(m_storage.path());
        connect(m_engine, &QQmlEngine::warnings, this,
                [this](const QList<QQmlError> &warnings) { m_warnings << warnings; });
        m_window = new QQuickWindow;
        m_window->resize(1280, 800);
        m_window->show();
        QVERIFY(QTest::qWaitForWindowExposed(m_window));
    }

    void cleanupTestCase() { delete m_window; }

    void init() { m_warnings.clear(); }

    void cleanup()
    {
        for (const QQmlError &warning : std::as_const(m_warnings))
            qWarning().noquote() << warning.toString();
        QVERIFY2(m_warnings.isEmpty(), "QML warnings");
    }

    void screenOpensEveryGame()
    {
        QScopedPointer<QQuickItem> screen(create(QStringLiteral("qml/screens/GamesScreen.qml"), {1180, 800}));
        QVERIFY(screen);
        const int count = eval(screen.get(), QStringLiteral("catalog.length")).toInt();
        QCOMPARE(count, 8);
        for (int i = 0; i < count; ++i) {
            QVERIFY(QMetaObject::invokeMethod(screen.get(), "open", Q_ARG(QVariant, i)));
            QTRY_VERIFY2(eval(screen.get(), QStringLiteral("game !== null")).toBool(),
                         qPrintable(eval(screen.get(), QStringLiteral("openGame.title")).toString()));
            QTest::qWait(200);
            QVERIFY(QMetaObject::invokeMethod(screen.get(), "close"));
            QTRY_VERIFY(eval(screen.get(), QStringLiteral("game === null")).toBool());
        }
        // The assistant panel over the page leaves the game open; leaving the
        // tab closes it, and so does Main's closeDetails() (the tab tapped
        // again, the screen saver).
        QVERIFY(QMetaObject::invokeMethod(screen.get(), "open", Q_ARG(QVariant, 0)));
        QTRY_VERIFY(eval(screen.get(), QStringLiteral("game !== null")).toBool());
        screen->setProperty("shown", false);
        QTest::qWait(50);
        QVERIFY(eval(screen.get(), QStringLiteral("game !== null")).toBool());
        screen->setProperty("isCurrent", false);
        QTRY_VERIFY(eval(screen.get(), QStringLiteral("game === null")).toBool());
        screen->setProperty("isCurrent", true);
        screen->setProperty("shown", true);
        QVERIFY(QMetaObject::invokeMethod(screen.get(), "open", Q_ARG(QVariant, 1)));
        QTRY_VERIFY(eval(screen.get(), QStringLiteral("game !== null")).toBool());
        QVERIFY(QMetaObject::invokeMethod(screen.get(), "closeDetail"));
        QTRY_VERIFY(eval(screen.get(), QStringLiteral("game === null")).toBool());

        // Penguin March pauses while it can't be seen (the assistant panel
        // over it), and waits for Play after.
        QVERIFY(QMetaObject::invokeMethod(screen.get(), "open", Q_ARG(QVariant, count - 1)));
        QTRY_VERIFY(eval(screen.get(), QStringLiteral("game !== null")).toBool());
        QCOMPARE(eval(screen.get(), QStringLiteral("openGame.title")).toString(), QStringLiteral("Penguin March"));
        QVERIFY(QMetaObject::invokeMethod(screen->property("game").value<QObject *>(), "start"));
        QTRY_VERIFY(eval(screen.get(), QStringLiteral("game.world.ticks() > 0")).toBool());
        screen->setProperty("shown", false);
        QVERIFY(!eval(screen.get(), QStringLiteral("game.playing")).toBool());
        const int held = eval(screen.get(), QStringLiteral("game.world.ticks()")).toInt();
        QTest::qWait(200);
        QCOMPARE(eval(screen.get(), QStringLiteral("game.world.ticks()")).toInt(), held);
        screen->setProperty("shown", true);
        QVERIFY(!eval(screen.get(), QStringLiteral("game.playing")).toBool());
        QVERIFY(QMetaObject::invokeMethod(screen.get(), "close"));
        QTRY_VERIFY(eval(screen.get(), QStringLiteral("game === null")).toBool());
    }

    void game2048MergesScoresAndRemembers()
    {
        QScopedPointer<QQuickItem> game(create(QStringLiteral("qml/games/Game2048.qml"), {800, 760}));
        QVERIFY(game);
        QCOMPARE(eval(game.get(), QStringLiteral("tiles.length")).toInt(), 2); // a new game
        seed2048(game.get(), {2, 2, 4, 4});
        QVERIFY(QMetaObject::invokeMethod(game.get(), "move", Q_ARG(QVariant, 3))); // left
        QCOMPARE(game->property("score").toInt(), 12);
        QCOMPARE(game->property("best").toInt(), 12);
        QCOMPARE(eval(game.get(), QStringLiteral("manager.grid.cells[0][0].value")).toInt(), 4);
        QCOMPARE(eval(game.get(), QStringLiteral("manager.grid.cells[1][0].value")).toInt(), 8);
        QCOMPARE(eval(game.get(), QStringLiteral("manager.grid.availableCells().length")).toInt(), 13);

        // Closing saves the game; opening it again carries on.
        game.reset();
        game.reset(create(QStringLiteral("qml/games/Game2048.qml"), {800, 760}));
        QVERIFY(game);
        QCOMPARE(game->property("score").toInt(), 12);
        QCOMPARE(game->property("best").toInt(), 12);
        QCOMPARE(eval(game.get(), QStringLiteral("manager.grid.cells[1][0].value")).toInt(), 8);

        QVERIFY(QMetaObject::invokeMethod(game.get(), "restart"));
        QCOMPARE(game->property("score").toInt(), 0);
        QCOMPARE(game->property("best").toInt(), 12);
    }

    void game2048WinThenKeepGoing()
    {
        QScopedPointer<QQuickItem> game(create(QStringLiteral("qml/games/Game2048.qml"), {800, 760}));
        QVERIFY(game);
        seed2048(game.get(), {1024, 1024});
        QVERIFY(QMetaObject::invokeMethod(game.get(), "move", Q_ARG(QVariant, 3)));
        QVERIFY(game->property("won").toBool());
        QVERIFY(game->property("terminated").toBool());
        QVERIFY(QMetaObject::invokeMethod(game.get(), "keepPlaying"));
        QVERIFY(!game->property("terminated").toBool());
        QVERIFY(QMetaObject::invokeMethod(game.get(), "restart"));
    }

    void ticTacToeTwoPlayers()
    {
        QScopedPointer<QQuickItem> game(create(QStringLiteral("qml/games/TicTacToe.qml"), {900, 760}));
        QVERIFY(game);
        auto play = [&](int cell) {
            QVariant ok;
            QMetaObject::invokeMethod(game.get(), "play", Q_RETURN_ARG(QVariant, ok), Q_ARG(QVariant, cell));
            return ok.toBool();
        };
        // X: 0 1 2 across the top; O: 3 4.
        for (int cell : {0, 3, 1, 4, 2})
            QVERIFY(play(cell));
        QCOMPARE(game->property("winner").toString(), QStringLiteral("X"));
        QCOMPARE(eval(game.get(), QStringLiteral("winLine.join(',')")).toString(), QStringLiteral("0,1,2"));
        QCOMPARE(eval(game.get(), QStringLiteral("score.X")).toInt(), 1);
        QVERIFY(!play(5)); // the round is over

        // O starts the next round. A full board with no line is a draw.
        QVERIFY(QMetaObject::invokeMethod(game.get(), "newRound"));
        QCOMPARE(game->property("turn").toString(), QStringLiteral("O"));
        for (int cell : {1, 0, 4, 2, 5, 3, 6, 7, 8})
            QVERIFY(play(cell));
        QVERIFY(game->property("draw").toBool());
        QCOMPARE(eval(game.get(), QStringLiteral("score.draw")).toInt(), 1);
    }

    void ticTacToeHardNeverLoses()
    {
        QScopedPointer<QQuickItem> game(create(QStringLiteral("qml/games/TicTacToe.qml"), {900, 760}));
        QVERIFY(game);
        int games = 0;
        explore(game.get(), QStringList(9, QString()), true, games);   // X first
        explore(game.get(), QStringList(9, QString()), false, games);  // McFly first
        QVERIFY(games > 100);

        // Easy McFly answers a move.
        game->setProperty("vsComputer", true);
        game->setProperty("thinkMs", 10);
        QVERIFY(QMetaObject::invokeMethod(game.get(), "play", Q_ARG(QVariant, 4)));
        QTRY_COMPARE(game->property("turn").toString(), QStringLiteral("X"));
        QCOMPARE(eval(game.get(), QStringLiteral("cells.filter(c => c === 'O').length")).toInt(), 1);
    }

    void fourInARowTwoPlayers()
    {
        QScopedPointer<QQuickItem> game(create(QStringLiteral("qml/games/FourInARow.qml"), {900, 760}));
        QVERIFY(game);
        const QString line = QStringLiteral("winLine.slice().sort((a, b) => a - b).join(',')");

        // Discs stack; X takes column 0 straight up.
        for (int column : {0, 1, 0, 1, 0, 1})
            QVERIFY(dropAt(game.get(), column));
        QCOMPARE(eval(game.get(), QStringLiteral("cells[7]")).toString(), QStringLiteral("X"));
        QCOMPARE(eval(game.get(), QStringLiteral("cells[8]")).toString(), QStringLiteral("O"));
        QCOMPARE(game->property("winner").toString(), QString());
        QVERIFY(dropAt(game.get(), 0));
        QCOMPARE(game->property("winner").toString(), QStringLiteral("X"));
        QCOMPARE(eval(game.get(), line).toString(), QStringLiteral("0,7,14,21"));
        QCOMPARE(eval(game.get(), QStringLiteral("score.X")).toInt(), 1);
        QVERIFY(!dropAt(game.get(), 2)); // the round is over

        // O starts the next round, and takes the bottom row.
        QVERIFY(QMetaObject::invokeMethod(game.get(), "newRound"));
        QCOMPARE(game->property("turn").toString(), QStringLiteral("O"));
        for (int column : {0, 0, 1, 1, 2, 2, 3})
            QVERIFY(dropAt(game.get(), column));
        QCOMPARE(game->property("winner").toString(), QStringLiteral("O"));
        QCOMPARE(eval(game.get(), line).toString(), QStringLiteral("0,1,2,3"));
        QCOMPARE(eval(game.get(), QStringLiteral("score.O")).toInt(), 1);

        // A full column takes no more.
        QVERIFY(QMetaObject::invokeMethod(game.get(), "newRound"));
        for (int i = 0; i < 6; ++i)
            QVERIFY(dropAt(game.get(), 6));
        const QString turn = game->property("turn").toString();
        QVERIFY(!dropAt(game.get(), 6));
        QCOMPARE(game->property("turn").toString(), turn);

        // Corner to corner, both ways.
        setRack(game.get(), {QStringLiteral("......."),
                             QStringLiteral("......."),
                             QStringLiteral("......."),
                             QStringLiteral("..XO..."),
                             QStringLiteral(".XOO..."),
                             QStringLiteral("XOOX...")}, QStringLiteral("X"));
        QVERIFY(dropAt(game.get(), 3));
        QCOMPARE(eval(game.get(), line).toString(), QStringLiteral("0,8,16,24"));
        setRack(game.get(), {QStringLiteral("......."),
                             QStringLiteral("......."),
                             QStringLiteral("......."),
                             QStringLiteral("OX....."),
                             QStringLiteral("OOX...."),
                             QStringLiteral("XOOX...")}, QStringLiteral("X"));
        QVERIFY(dropAt(game.get(), 0));
        QCOMPARE(eval(game.get(), line).toString(), QStringLiteral("3,9,15,21"));

        // A full board with no line is a draw.
        setRack(game.get(), {QStringLiteral("OXOXOX."),
                             QStringLiteral("OXOXOXO"),
                             QStringLiteral("OXOXOXO"),
                             QStringLiteral("XOXOXOX"),
                             QStringLiteral("XOXOXOX"),
                             QStringLiteral("XOXOXOX")}, QStringLiteral("O"));
        const int draws = eval(game.get(), QStringLiteral("score.draw")).toInt();
        QVERIFY(dropAt(game.get(), 6));
        QVERIFY(game->property("draw").toBool());
        QVERIFY(game->property("over").toBool());
        QCOMPARE(eval(game.get(), QStringLiteral("score.draw")).toInt(), draws + 1);
    }

    void fourInARowHardMcFly()
    {
        QScopedPointer<QQuickItem> game(create(QStringLiteral("qml/games/FourInARow.qml"), {900, 760}));
        QVERIFY(game);
        const QString hardMove = QStringLiteral("bestMove(cells, 'O', hardDepth)");

        // Takes a win when it has one.
        setRack(game.get(), {QStringLiteral("......."),
                             QStringLiteral("......."),
                             QStringLiteral("......."),
                             QStringLiteral("......."),
                             QStringLiteral("XX....."),
                             QStringLiteral("OOO.XX.")}, QStringLiteral("O"));
        QCOMPARE(eval(game.get(), hardMove).toInt(), 3);
        // Blocks yours.
        setRack(game.get(), {QStringLiteral("......."),
                             QStringLiteral("......."),
                             QStringLiteral("......."),
                             QStringLiteral("......."),
                             QStringLiteral("O.....O"),
                             QStringLiteral("XXX...O")}, QStringLiteral("O"));
        QCOMPARE(eval(game.get(), hardMove).toInt(), 3);
        // Won't drop a disc that lets you win on top of it.
        setRack(game.get(), {QStringLiteral("......."),
                             QStringLiteral("......."),
                             QStringLiteral("......."),
                             QStringLiteral("......."),
                             QStringLiteral("XXX...O"),
                             QStringLiteral("OOX...O")}, QStringLiteral("O"));
        for (int i = 0; i < 5; ++i)
            QVERIFY(eval(game.get(), hardMove).toInt() != 3);

        // How long a move takes here (the Pi takes a few times longer).
        QElapsedTimer clock;
        setRack(game.get(), QStringList(6, QStringLiteral(".......")), QStringLiteral("O"));
        clock.start();
        eval(game.get(), hardMove);
        qInfo("Four in a Row: Hard's opening move took %lld ms, %lld positions", clock.elapsed(),
              eval(game.get(), QStringLiteral("FourInARowEngine.lastNodes()")).toLongLong());
        setRack(game.get(), {QStringLiteral("......."),
                             QStringLiteral("......."),
                             QStringLiteral("...O..."),
                             QStringLiteral("..XX..."),
                             QStringLiteral("..OXO.."),
                             QStringLiteral(".XOXO..")}, QStringLiteral("O"));
        clock.restart();
        eval(game.get(), hardMove);
        qInfo("Four in a Row: Hard's mid-game move took %lld ms, %lld positions", clock.elapsed(),
              eval(game.get(), QStringLiteral("FourInARowEngine.lastNodes()")).toLongLong());
        // A look too deep to finish stops at the engine's cap, with the
        // deepest look it did finish.
        setRack(game.get(), QStringList(6, QStringLiteral(".......")), QStringLiteral("O"));
        clock.restart();
        const int capped = eval(game.get(), QStringLiteral("bestMove(cells, 'O', 42)")).toInt();
        const qint64 cappedNodes = eval(game.get(), QStringLiteral("FourInARowEngine.lastNodes()")).toLongLong();
        qInfo("Four in a Row: a look 42 discs deep stopped after %lld ms, %lld positions", clock.elapsed(), cappedNodes);
        QVERIFY(capped >= 0 && capped < 7);
        QCOMPARE(cappedNodes, qint64(600001));

        // Hard never loses to someone dropping discs at random.
        const QString match = QStringLiteral(R"(
            (function () {
                let board = Array(42).fill(""), turn = first
                for (;;) {
                    const open = [0, 1, 2, 3, 4, 5, 6].filter(c => landing(board, c) >= 0)
                    if (!open.length)
                        return "draw"
                    const c = turn === "O" ? bestMove(board, "O", hardDepth)
                                           : open[Math.floor(Math.random() * open.length)]
                    const at = landing(board, c)
                    board[at] = turn
                    if (lineThrough(board, at))
                        return turn
                    turn = turn === "X" ? "O" : "X"
                }
            }))");
        int wins = 0;
        for (int i = 0; i < 30; ++i) {
            const QString first = i % 2 ? QStringLiteral("O") : QStringLiteral("X");
            const QString result = eval(game.get(), QStringLiteral("(function (first) { return (%1)() })(\"%2\")")
                                                        .arg(match, first)).toString();
            QVERIFY2(result != QLatin1String("X"), "random play beat Hard");
            wins += result == QLatin1String("O");
        }
        QVERIFY(wins >= 28);

        // Easy McFly answers a move.
        game->setProperty("vsComputer", true);
        game->setProperty("thinkMs", 10);
        QCOMPARE(game->property("turn").toString(), QStringLiteral("X"));
        QVERIFY(dropAt(game.get(), 3));
        QTRY_COMPARE(game->property("turn").toString(), QStringLiteral("X"));
        QCOMPARE(eval(game.get(), QStringLiteral("cells.filter(c => c === 'O').length")).toInt(), 1);
    }

    // Each column stays a full touch target, and the board and controls stay
    // on the stage, on every panel: the 7" (its stage is short), the
    // portrait panel, the 10.1" and a TV, beside McFly's switches too.
    // An open game fills the whole window, over the nav, on every panel; the
    // X closes it and (i) shows how to play over it.
    void gamesOpenFullScreen()
    {
        struct Panel { const char *tier; QSize window; int shortSide; };
        const Panel panels[] = {
            {"mini", {800, 480}, 480},
            {"tall", {720, 1280}, 720},
            {"compact", {1280, 800}, 800},
            {"wide", {1920, 1080}, 1080},
        };
        QObject *theme = nullptr;
        for (const Panel &panel : panels) {
            // On the 7", a stand-in for Main's nav bar under the screen, as
            // Main has it: a game's full screen must keep taps off it.
            QScopedPointer<QQuickItem> nav;
            const bool bar = QLatin1String(panel.tier) == QLatin1String("mini");
            if (bar) {
                QQmlComponent component(m_engine);
                component.setData("import QtQuick\nMouseArea { property int taps: 0; onPressed: taps++ }", QUrl());
                nav.reset(qobject_cast<QQuickItem *>(component.create()));
                QVERIFY(nav);
                nav->setParentItem(m_window->contentItem());
                nav->setPosition(QPointF(0, 480 - 76));
                nav->setSize(QSizeF(800, 76));
            }
            QScopedPointer<QQuickItem> screen(create(QStringLiteral("qml/screens/GamesScreen.qml"), panel.window));
            QVERIFY(screen);
            eval(screen.get(), QStringLiteral("Theme.tier = '%1'; Theme.shortSide = %2")
                                   .arg(QLatin1String(panel.tier)).arg(panel.shortSide));
            theme = eval(screen.get(), QStringLiteral("Theme")).value<QObject *>();
            // The screen is what Main leaves it: the window less the nav.
            screen->setSize(QSizeF(panel.window.width() - eval(screen.get(), QStringLiteral("Theme.navWidth")).toInt(),
                                   panel.window.height() - eval(screen.get(), QStringLiteral("Theme.navHeight")).toInt()));
            const QString where = QLatin1String(panel.tier);
            QVERIFY(QMetaObject::invokeMethod(screen.get(), "open", Q_ARG(QVariant, 0)));
            QTRY_VERIFY(eval(screen.get(), QStringLiteral("game !== null")).toBool());
            QCOMPARE(eval(screen.get(), QStringLiteral("full.width")).toInt(), panel.window.width());
            QCOMPARE(eval(screen.get(), QStringLiteral("full.height")).toInt(), panel.window.height());
            auto *game = eval(screen.get(), QStringLiteral("game")).value<QQuickItem *>();
            auto *full = eval(screen.get(), QStringLiteral("full")).value<QQuickItem *>();
            QVERIFY(game && full);
            // The game takes all but the margins and the buttons' strip.
            const QRectF area = game->mapRectToItem(full, QRectF(0, 0, game->width(), game->height()));
            QVERIFY2(QRectF(0, 0, full->width(), full->height()).contains(area), qPrintable(where));
            // Along the top in portrait and on the 7"; down the right otherwise.
            const bool upright = panel.window.height() > panel.window.width() || where == QLatin1String("mini");
            const qreal strip = 64 + 2 * eval(screen.get(), QStringLiteral("Theme.pageMargin")).toReal()
                                + eval(screen.get(), QStringLiteral("Theme.spacing")).toReal();
            QVERIFY2(upright ? area.height() >= full->height() - strip - 1 : area.width() >= full->width() - strip - 1,
                     qPrintable(where));
            // Neither button sits on the game.
            for (const char *name : {"game:close", "game:info"}) {
                QQuickItem *button = find(full, QLatin1String(name));
                QVERIFY2(button && button->isVisible(), name);
                const QRectF r = button->mapRectToItem(full, QRectF(0, 0, button->width(), button->height()));
                QVERIFY2(r.width() >= 64 && r.height() >= 64 && !r.intersects(area), qPrintable(where + QLatin1Char(' ') + QLatin1String(name)));
            }
            if (bar) {
                QTest::mouseClick(m_window, Qt::LeftButton, {}, QPoint(400, 440));
                QCOMPARE(nav->property("taps").toInt(), 0);
            }
            // The assistant panel over the page: the nav shows beside it.
            screen->setProperty("shown", false);
            QVERIFY(!full->isVisible());
            screen->setProperty("shown", true);
            QVERIFY(full->isVisible());
            // (i) shows how to play over the game; the X closes it.
            QMetaObject::invokeMethod(find(full, QStringLiteral("game:info")), "clicked");
            QVERIFY(screen->property("howToOpen").toBool());
            QMetaObject::invokeMethod(find(full, QStringLiteral("game:close")), "clicked");
            QTRY_VERIFY(eval(screen.get(), QStringLiteral("game === null")).toBool());
            QVERIFY(!screen->property("howToOpen").toBool());
            QVERIFY(!full->isVisible());
            if (bar) { // with the game closed, the same tap reaches the nav
                QTest::mouseClick(m_window, Qt::LeftButton, {}, QPoint(400, 440));
                QCOMPARE(nav->property("taps").toInt(), 1);
            }
        }
        QVERIFY(theme);
        theme->setProperty("tier", QStringLiteral("compact"));
        theme->setProperty("shortSide", 800);
    }

    void fourInARowFitsEveryPanel()
    {
        struct Panel { const char *tier; QSize page; int shortSide; };
        const Panel panels[] = {
            {"mini", {800, 480 - 76}, 480},     // the bottom nav bar
            {"tall", {720, 1280 - 84}, 720},
            {"compact", {1280 - 100, 800}, 800}, // the rail
            {"wide", {1920 - 124, 1080}, 1080},
        };
        QObject *theme = nullptr;
        for (const Panel &panel : panels) {
            QScopedPointer<QQuickItem> screen(create(QStringLiteral("qml/screens/GamesScreen.qml"), panel.page));
            QVERIFY(screen);
            eval(screen.get(), QStringLiteral("Theme.tier = '%1'; Theme.shortSide = %2")
                                   .arg(QLatin1String(panel.tier)).arg(panel.shortSide));
            theme = eval(screen.get(), QStringLiteral("Theme")).value<QObject *>();
            const int index = eval(screen.get(), QStringLiteral("catalog.findIndex(g => g.source.endsWith('FourInARow.qml'))")).toInt();
            QVERIFY(index >= 0);
            QVERIFY(QMetaObject::invokeMethod(screen.get(), "open", Q_ARG(QVariant, index)));
            QTRY_VERIFY(eval(screen.get(), QStringLiteral("game !== null")).toBool());
            auto *game = eval(screen.get(), QStringLiteral("game")).value<QQuickItem *>();
            QVERIFY(game);
            for (bool vsComputer : {false, true}) {
                game->setProperty("vsComputer", vsComputer);
                QTest::qWait(20);
                const QString where = QStringLiteral("%1 %2x%3%4").arg(QLatin1String(panel.tier))
                                          .arg(game->width()).arg(game->height())
                                          .arg(vsComputer ? QStringLiteral(" vs McFly") : QString());
                qInfo().noquote() << "Four in a Row on" << where << "side" << game->property("side").toBool()
                                  << "column" << game->property("colWidth").toReal()
                                  << "disc" << game->property("disc").toReal();
                QVERIFY2(game->property("colWidth").toReal() >= 64, qPrintable(where));
                const QRectF stage = QRectF(0, 0, game->width(), game->height()).adjusted(-0.5, -0.5, 0.5, 0.5);
                const auto rect = [&](const char *id) {
                    const QString name = QLatin1String(id);
                    return QRectF(eval(game, name + QStringLiteral(".x")).toReal(), eval(game, name + QStringLiteral(".y")).toReal(),
                                  eval(game, name + QStringLiteral(".width")).toReal(), eval(game, name + QStringLiteral(".height")).toReal());
                };
                const QRectF board = rect("board");
                QVERIFY2(stage.contains(board), qPrintable(where));
                if (game->property("side").toBool()) {
                    const QRectF stack = rect("stack");
                    QVERIFY2(stage.contains(stack), qPrintable(where));
                    QVERIFY2(stack.left() >= board.right(), qPrintable(where));
                    QVERIFY2(eval(game, QStringLiteral("stack.childrenRect.width <= stack.width + 0.5")).toBool(), qPrintable(where));
                } else {
                    const QRectF header = rect("header");
                    const QRectF button = rect("newRoundButton");
                    QVERIFY2(stage.contains(header) && stage.contains(button), qPrintable(where));
                    QVERIFY2(eval(game, QStringLiteral("header.childrenRect.width <= header.width + 0.5")).toBool(), qPrintable(where));
                    QVERIFY2(header.bottom() <= board.top() && board.bottom() <= button.top(), qPrintable(where));
                }
            }
        }
        QVERIFY(theme);
        theme->setProperty("tier", QStringLiteral("compact"));
        theme->setProperty("shortSide", 800);
    }

    void trafficJamLevelsAreRightAndSolvable()
    {
        QScopedPointer<QQuickItem> game(create(QStringLiteral("qml/games/TrafficJam.qml"), {900, 760}));
        QVERIFY(game);
        const int count = game->property("levelCount").toInt();
        QVERIFY(count >= 30);

        // A breadth-first search with the upstream Board's moves() finds the
        // fewest moves: it has to match each level's par. Returns the moves.
        const QString solve = QStringLiteral(R"(
            (function () {
                const pieces = board.pieces
                const start = pieces.map(p => p.position)
                const solved = s => s[0] % board.size + pieces[0].size === board.size
                const parent = new Map([[start.join(","), null]])
                let frontier = [start], found = null
                while (frontier.length && !found) {
                    const next = []
                    for (const state of frontier) {
                        state.forEach((p, i) => pieces[i].position = p)
                        for (const m of board.moves()) {
                            const s = state.slice()
                            s[m.piece] += m.steps * pieces[m.piece].stride
                            const k = s.join(",")
                            if (parent.has(k))
                                continue
                            parent.set(k, [state.join(","), m.piece, m.steps])
                            next.push(s)
                            if (solved(s)) {
                                found = k
                                break
                            }
                        }
                        if (found)
                            break
                    }
                    frontier = next
                }
                start.forEach((p, i) => pieces[i].position = p)
                const path = []
                for (let k = found; k && parent.get(k); k = parent.get(k)[0])
                    path.unshift([parent.get(k)[1], parent.get(k)[2]])
                return path
            })())");

        int previous = 0;
        for (int i = 0; i < count; ++i) {
            QVERIFY(QMetaObject::invokeMethod(game.get(), "load", Q_ARG(QVariant, i)));
            const int par = game->property("par").toInt();
            QVERIFY2(par >= previous, "levels get harder");
            previous = par;
            QVERIFY(!eval(game.get(), QStringLiteral("board.isSolved()")).toBool());
            QCOMPARE(eval(game.get(), QStringLiteral("board.primaryRow")).toInt(), 2);
            if (par <= 8) { // the rest take long here; make-puzzles.py solved them
                const QVariantList path = eval(game.get(), solve).toList();
                QCOMPARE(path.size(), par);
            }
        }

        // Solve level 1 by sliding the cars, then reopen: progress is kept.
        QVERIFY(QMetaObject::invokeMethod(game.get(), "load", Q_ARG(QVariant, 0)));
        const QVariantList path = eval(game.get(), solve).toList();
        QVERIFY(!path.isEmpty());
        QVariant ok;
        QVERIFY(QMetaObject::invokeMethod(game.get(), "slide", Q_RETURN_ARG(QVariant, ok),
                                          Q_ARG(QVariant, 0), Q_ARG(QVariant, -99)));
        QVERIFY(!ok.toBool()); // not a legal move
        for (const QVariant &step : path) {
            const QVariantList move = step.toList();
            QVERIFY(QMetaObject::invokeMethod(game.get(), "slide", Q_RETURN_ARG(QVariant, ok),
                                              Q_ARG(QVariant, move[0]), Q_ARG(QVariant, move[1])));
            QVERIFY(ok.toBool());
        }
        QVERIFY(game->property("solved").toBool());
        QCOMPARE(game->property("moves").toInt(), path.size());
        QVERIFY(QMetaObject::invokeMethod(game.get(), "load", Q_ARG(QVariant, 1)));
        game.reset();
        game.reset(create(QStringLiteral("qml/games/TrafficJam.qml"), {900, 760}));
        QVERIFY(game);
        QCOMPARE(game->property("level").toInt(), 1);
        QCOMPARE(eval(game.get(), QStringLiteral("best[0]")).toInt(), path.size());

        // Undo walks a move back.
        QVERIFY(QMetaObject::invokeMethod(game.get(), "load", Q_ARG(QVariant, 0)));
        const QString before = eval(game.get(), QStringLiteral("positions.join(',')")).toString();
        const QVariantList first = path.first().toList();
        QVERIFY(QMetaObject::invokeMethod(game.get(), "slide", Q_RETURN_ARG(QVariant, ok),
                                          Q_ARG(QVariant, first[0]), Q_ARG(QVariant, first[1])));
        QVERIFY(QMetaObject::invokeMethod(game.get(), "undo"));
        QCOMPARE(eval(game.get(), QStringLiteral("positions.join(',')")).toString(), before);
        QCOMPARE(game->property("moves").toInt(), 0);
    }

    // Penguin March: the level runs on its own clock while it's drawn and
    // stops when paused; a tap gives the chosen skill to the penguin under
    // it; a win is kept, and so is the level, across a reopen. "Show me"
    // plays the level's solution through without counting as a win. The
    // rules and every level's solution are tests/tst_penguins.cpp.
    void penguinMarchPlaysAndRemembers()
    {
        QScopedPointer<QQuickItem> game(create(QStringLiteral("qml/games/PenguinMarch.qml"), {900, 760}));
        QVERIFY(game);
        QVERIFY(game->property("levelCount").toInt() >= 12);
        QVERIFY(QMetaObject::invokeMethod(game.get(), "load", Q_ARG(QVariant, 0)));
        QVERIFY(!game->property("briefed").toBool()); // the level's card first
        QCOMPARE(eval(game.get(), QStringLiteral("world.ticks()")).toInt(), 0);
        QCOMPARE(game->property("skill").toString(), QStringLiteral("dig")); // its one skill, chosen

        QVERIFY(QMetaObject::invokeMethod(game.get(), "start"));
        QTRY_VERIFY(eval(game.get(), QStringLiteral("world.released")).toInt() >= 1);
        game->setProperty("playing", false);
        const int paused = eval(game.get(), QStringLiteral("world.ticks()")).toInt();
        QTest::qWait(200);
        QCOMPARE(eval(game.get(), QStringLiteral("world.ticks()")).toInt(), paused);

        // The first penguin walking in the pen, away from the hatch (a hole
        // under it would drop the next ones too far): a tap a little off it digs.
        for (int i = 0; i < 200 && !eval(game.get(), QStringLiteral("world.penguins()[0].x > 110 * zoom")).toBool(); ++i)
            eval(game.get(), QStringLiteral("world.advance(1)"));
        QCOMPARE(eval(game.get(), QStringLiteral("world.penguins()[0].state")).toString(), QStringLiteral("walking"));
        QVERIFY(!eval(game.get(), QStringLiteral("world.tapAt(5, 5)")).toBool()); // nobody there
        QVERIFY(eval(game.get(), QStringLiteral("(function () { const p = world.penguins()[0];"
                                                " return world.tapAt(p.x + 20, p.y - 20) })()")).toBool());
        QCOMPARE(eval(game.get(), QStringLiteral("world.penguins()[0].state")).toString(), QStringLiteral("digging"));
        QCOMPARE(eval(game.get(), QStringLiteral("world.skillsLeft.dig")).toInt(), 1);

        eval(game.get(), QStringLiteral("world.advance(3000)"));
        QVERIFY(eval(game.get(), QStringLiteral("world.finished && world.won")).toBool());
        const int saved = eval(game.get(), QStringLiteral("world.saved")).toInt();
        QVERIFY(saved >= eval(game.get(), QStringLiteral("world.need")).toInt());
        QCOMPARE(eval(game.get(), QStringLiteral("best[0]")).toInt(), saved);
        QVERIFY(!game->property("playing").toBool());

        // Show me, on the next level: it wins, and isn't kept.
        QVERIFY(QMetaObject::invokeMethod(game.get(), "load", Q_ARG(QVariant, 1)));
        QVERIFY(QMetaObject::invokeMethod(game.get(), "showMe"));
        QVERIFY(eval(game.get(), QStringLiteral("world.demo")).toBool());
        eval(game.get(), QStringLiteral("world.advance(3000)"));
        QVERIFY(eval(game.get(), QStringLiteral("world.finished && world.won")).toBool());
        QVERIFY(eval(game.get(), QStringLiteral("best[1] === undefined")).toBool());

        game.reset();
        game.reset(create(QStringLiteral("qml/games/PenguinMarch.qml"), {800, 300})); // the 7" shape
        QVERIFY(game);
        QCOMPARE(game->property("level").toInt(), 1);
        QCOMPARE(eval(game.get(), QStringLiteral("best[0]")).toInt(), saved);
        QVERIFY(game->property("slim").toBool());
        QVERIFY(QMetaObject::invokeMethod(game.get(), "start"));
        QTest::qWait(300); // drawn running, in the other layout
        QVERIFY(eval(game.get(), QStringLiteral("world.ticks()")).toInt() > 0);
    }

    void sameGamePlaysAndQuitsToTheList()
    {
        QScopedPointer<QQuickItem> game(create(QStringLiteral("games/samegame/samegame.qml")));
        QVERIFY(game);
        QSignalSpy quit(game.get(), SIGNAL(quitRequested()));
        QTest::mouseClick(m_window, Qt::LeftButton, {}, QPoint(160, 157)); // "1 Player"
        QTRY_COMPARE(game->property("state").toString(), QStringLiteral("in-game"));
        QTest::qWait(1200); // the board fills in, the bars settle
        QTest::mouseClick(m_window, Qt::LeftButton, {}, QPoint(120, 300));
        QTest::qWait(300);
        QTest::mouseClick(m_window, Qt::LeftButton, {}, QPoint(20, 458)); // Quit
        QTRY_COMPARE(quit.count(), 1);
    }

    void scoopShopOrdersFollowTheLevel()
    {
        QScopedPointer<QQuickItem> game(shop());
        QVERIFY(game);
        QCOMPARE(game->property("phase").toString(), QStringLiteral("ready"));
        // Every order is a cone or a cup, with scoops and toppings from what
        // its level offers, as many as it allows. Levels 1 and 2 keep to the
        // first four flavours and level 3 the first three toppings; by
        // level 10 every flavour and topping turns up, and the biggest orders.
        const QString orders = QStringLiteral(R"((function () {
            let biggest = 0
            const seenFlavours = new Set(), seenToppings = new Set()
            for (let lv = 1; lv <= 10; ++lv) {
                const r = rulesFor(lv)
                for (let s = 1; s <= 300; ++s) {
                    const o = orderFor(lv, s * 7919 + lv)
                    const bad = "level " + lv + ": " + JSON.stringify(o)
                    if (o.base !== "cone" && o.base !== "cup")
                        return bad
                    if (o.scoops.length < r.minScoops || o.scoops.length > r.maxScoops || o.scoops.some(f => r.flavours.indexOf(f) < 0))
                        return bad
                    if (o.toppings.length < r.minToppings || o.toppings.length > r.maxToppings
                            || o.toppings.some(t => r.toppings.indexOf(t) < 0) || new Set(o.toppings).size !== o.toppings.length)
                        return bad
                    if (lv === 10) {
                        biggest = Math.max(biggest, o.scoops.length + o.toppings.length)
                        o.scoops.forEach(f => seenFlavours.add(f))
                        o.toppings.forEach(t => seenToppings.add(t))
                    }
                }
            }
            if (rulesFor(2).flavours.length !== 4 || rulesFor(3).flavours.length !== 7)
                return "flavours join at the wrong level"
            if (rulesFor(3).toppings.length !== 3 || rulesFor(4).toppings.length !== 7)
                return "toppings join at the wrong level"
            if (seenFlavours.size !== 7 || seenToppings.size !== 7)
                return "level 10 never asks for some: " + seenFlavours.size + " flavours, " + seenToppings.size + " toppings"
            return biggest === 5 ? "" : "the biggest order at level 10 has " + biggest
        })())");
        QCOMPARE(eval(game.get(), orders).toString(), QString());

        // It gets busier: more seats, bigger orders, less time, sooner.
        const QString curve = QStringLiteral(R"((function () {
            for (let lv = 1; lv < 10; ++lv) {
                const a = rulesFor(lv), b = rulesFor(lv + 1)
                if (b.seats < a.seats || b.maxScoops < a.maxScoops || b.maxToppings < a.maxToppings || b.minScoops < a.minScoops)
                    return "orders shrink at level " + (lv + 1)
                if (b.wait > a.wait || b.perItem > a.perItem || b.arrival > a.arrival)
                    return "more time at level " + (lv + 1)
            }
            const one = rulesFor(1), ten = rulesFor(10)
            if (one.seats !== 2 || one.maxScoops !== 1 || one.maxToppings !== 0 || ten.seats !== 4)
                return "the ends of the curve"
            const order = { base: "cup", scoops: ["mint", "mint", "vanilla"], toppings: ["cherry", "wafer"] }
            if (patienceFor(order, 10) >= patienceFor(order, 5) || patienceFor(order, 5) >= patienceFor(order, 1))
                return "the same order waits as long later on"
            // At the busiest, a full counter of the biggest orders can still
            // be served: four customers, seven taps each, two taps a second.
            if (patienceFor(order, 10) < 4 * 7 * 500)
                return "level 10 is too quick: " + patienceFor(order, 10)
            return ""
        })())");
        QCOMPARE(eval(game.get(), curve).toString(), QString());
        // The pace: a cone of one scoop waits 27 s at level 1 (a tenth under
        // the first tuning's 30 s), and customers come every 6.3 s.
        QCOMPARE(eval(game.get(), QStringLiteral("patienceFor({ base: 'cone', scoops: ['mint'], toppings: [] }, 1)")).toInt(), 27000);
        QCOMPARE(eval(game.get(), QStringLiteral("rulesFor(1).arrival")).toInt(), 6300);
        QCOMPARE(eval(game.get(), QStringLiteral("rulesFor(10).arrival")).toInt(), 2250);
        // Quick scores more than slow, and right scores at least ten a thing.
        QCOMPARE(eval(game.get(), QStringLiteral("pointsFor({ base: 'cone', scoops: ['mint'], toppings: [] }, 1)")).toInt(), 40);
        QCOMPARE(eval(game.get(), QStringLiteral("pointsFor({ base: 'cone', scoops: ['mint'], toppings: [] }, 0)")).toInt(), 20);
    }

    void scoopShopRightOrderScores()
    {
        QScopedPointer<QQuickItem> game(shop());
        QVERIFY(game);
        eval(game.get(), QStringLiteral("start('lotl')"));
        QCOMPARE(game->property("phase").toString(), QStringLiteral("playing"));
        QCOMPARE(game->property("worker").toString(), QStringLiteral("lotl"));
        QCOMPARE(eval(game.get(), QStringLiteral("seats.filter(c => c).length")).toInt(), 0);
        eval(game.get(), QStringLiteral("advance(1000)")); // the first customer, a second in
        QCOMPARE(eval(game.get(), QStringLiteral("seats.filter(c => c).length")).toInt(), 1);
        const int at = eval(game.get(), QStringLiteral("seats.findIndex(c => c)")).toInt();

        // Make their ticket with the buttons' functions, and hand it over.
        eval(game.get(), QStringLiteral("advance(2000)"));
        const QString make = QStringLiteral(
            "(function (i) { const o = seats[i].order; let ok = pickBase(o.base);"
            " o.scoops.forEach(f => { ok = addScoop(f) && ok }); o.toppings.forEach(t => { ok = addTopping(t) && ok });"
            " return ok })(%1)").arg(at);
        QVERIFY(eval(game.get(), make).toBool());
        const int expected = eval(game.get(), QStringLiteral(
            "pointsFor(seats[%1].order, 1 - (now - seats[%1].arrived) / seats[%1].patience)").arg(at)).toInt();
        QVERIFY(expected > 0);
        QCOMPARE(eval(game.get(), QStringLiteral("deliver(%1)").arg(at)).toString(), QStringLiteral("right"));
        QCOMPARE(game->property("score").toInt(), expected);
        QCOMPARE(game->property("served").toInt(), 1);
        QCOMPARE(game->property("hearts").toInt(), 3);
        QCOMPARE(eval(game.get(), QStringLiteral("seats[%1].gone").arg(at)).toString(), QStringLiteral("right"));
        QCOMPARE(eval(game.get(), QStringLiteral("build.base")).toString(), QString()); // a fresh start
        // They're gone once they've walked off; handing them more does nothing.
        QCOMPARE(eval(game.get(), QStringLiteral("deliver(%1)").arg(at)).toString(), QString());
        eval(game.get(), QStringLiteral("advance(700)"));
        QVERIFY(eval(game.get(), QStringLiteral("seats[%1] === null").arg(at)).toBool());
    }

    void scoopShopWrongOrderCostsAHeart()
    {
        QScopedPointer<QQuickItem> game(shop());
        QVERIFY(game);
        eval(game.get(), QStringLiteral("start('pip')"));
        const QString order = QStringLiteral("({ base: 'cone', scoops: ['vanilla', 'chocolate'], toppings: ['cherry', 'sprinkles'] })");

        // The same scoops the other way up is the wrong order.
        eval(game.get(), QStringLiteral("seat(0, %1)").arg(order));
        QVERIFY(eval(game.get(), QStringLiteral("pickBase('cone') && addScoop('chocolate') && addScoop('vanilla')"
                                                " && addTopping('cherry') && addTopping('sprinkles')")).toBool());
        QCOMPARE(eval(game.get(), QStringLiteral("deliver(0)")).toString(), QStringLiteral("wrong"));
        QCOMPARE(game->property("hearts").toInt(), 2);
        QCOMPARE(game->property("score").toInt(), 0);
        QCOMPARE(eval(game.get(), QStringLiteral("seats[0].gone")).toString(), QStringLiteral("wrong"));
        QCOMPARE(eval(game.get(), QStringLiteral("build.scoops.length")).toInt(), 0);

        // Toppings go on in any order.
        eval(game.get(), QStringLiteral("seat(1, %1)").arg(order));
        QVERIFY(eval(game.get(), QStringLiteral("pickBase('cone') && addScoop('vanilla') && addScoop('chocolate')"
                                                " && addTopping('sprinkles') && addTopping('cherry')")).toBool());
        QCOMPARE(eval(game.get(), QStringLiteral("deliver(1)")).toString(), QStringLiteral("right"));
        QCOMPARE(game->property("hearts").toInt(), 2);

        // A cup for a cone is wrong too; nothing made hands nothing over.
        eval(game.get(), QStringLiteral("seat(2, { base: 'cone', scoops: ['mint'], toppings: [] })"));
        QCOMPARE(eval(game.get(), QStringLiteral("deliver(2)")).toString(), QString());
        QVERIFY(eval(game.get(), QStringLiteral("pickBase('cup') && addScoop('mint')")).toBool());
        QCOMPARE(eval(game.get(), QStringLiteral("deliver(2)")).toString(), QStringLiteral("wrong"));
        QCOMPARE(game->property("hearts").toInt(), 1);

        // The counter's own rules: a cone or cup before scoops, three at
        // most, toppings on a scoop, once each; undo takes off the top.
        QVERIFY(!eval(game.get(), QStringLiteral("addScoop('mint')")).toBool());
        QVERIFY(!game->property("hint").toString().isEmpty());
        QVERIFY(eval(game.get(), QStringLiteral("pickBase('cup')")).toBool());
        QVERIFY(!eval(game.get(), QStringLiteral("addTopping('cherry')")).toBool());
        QVERIFY(eval(game.get(), QStringLiteral("addScoop('mint') && addScoop('vanilla') && addScoop('mint')")).toBool());
        QVERIFY(!eval(game.get(), QStringLiteral("addScoop('chocolate')")).toBool());
        QVERIFY(eval(game.get(), QStringLiteral("addTopping('wafer')")).toBool());
        QVERIFY(!eval(game.get(), QStringLiteral("addTopping('wafer')")).toBool());
        QVERIFY(eval(game.get(), QStringLiteral("pickBase('cone')")).toBool()); // a cone instead, scoops and all
        QCOMPARE(eval(game.get(), QStringLiteral("JSON.stringify(build)")).toString(),
                 QStringLiteral(R"({"base":"cone","scoops":["mint","vanilla","mint"],"toppings":["wafer"]})"));
        QVERIFY(eval(game.get(), QStringLiteral("undo() && undo()")).toBool());
        QCOMPARE(eval(game.get(), QStringLiteral("JSON.stringify(build)")).toString(),
                 QStringLiteral(R"({"base":"cone","scoops":["mint","vanilla"],"toppings":[]})"));
        QVERIFY(eval(game.get(), QStringLiteral("undo() && undo() && undo()")).toBool());
        QVERIFY(!eval(game.get(), QStringLiteral("undo()")).toBool());
        QCOMPARE(eval(game.get(), QStringLiteral("build.base")).toString(), QString());
    }

    void scoopShopCustomerGivesUp()
    {
        QScopedPointer<QQuickItem> game(shop());
        QVERIFY(game);
        eval(game.get(), QStringLiteral("start('pip')"));
        const int wait = eval(game.get(), QStringLiteral("seat(0, { base: 'cup', scoops: ['mint'], toppings: [] })")).toInt();
        QCOMPARE(wait, eval(game.get(), QStringLiteral("patienceFor({ base: 'cup', scoops: ['mint'], toppings: [] }, 1)")).toInt());
        QVERIFY(wait >= 20000);
        eval(game.get(), QStringLiteral("advance(%1)").arg(wait - 100));
        QCOMPARE(eval(game.get(), QStringLiteral("seats[0].gone")).toString(), QString());
        QCOMPARE(game->property("hearts").toInt(), 3);
        eval(game.get(), QStringLiteral("advance(200)"));
        QCOMPARE(eval(game.get(), QStringLiteral("seats[0].gone")).toString(), QStringLiteral("late"));
        QCOMPARE(game->property("hearts").toInt(), 2);
        QCOMPARE(game->property("served").toInt(), 0);
    }

    void scoopShopCustomersFlipOut()
    {
        QScopedPointer<QQuickItem> game(shop());
        QVERIFY(game);
        eval(game.get(), QStringLiteral("start('pip')"));
        const int wait = eval(game.get(), QStringLiteral("seat(0, { base: 'cone', scoops: ['mango'], toppings: [] })")).toInt();
        const QString face = QStringLiteral("faceFor(patienceOf(0), seats[0].gone)");
        QCOMPARE(eval(game.get(), face).toString(), QStringLiteral("smile"));
        QVERIFY(!game->property("alarm").toBool());
        eval(game.get(), QStringLiteral("advance(%1)").arg(wait * 6 / 10));
        QCOMPARE(eval(game.get(), face).toString(), QStringLiteral("flat"));
        eval(game.get(), QStringLiteral("advance(%1)").arg(wait * 15 / 100));
        QCOMPARE(eval(game.get(), face).toString(), QStringLiteral("frown"));
        QVERIFY(!game->property("alarm").toBool());
        // The last fifth: they flip out, and the shopkeeper panics.
        eval(game.get(), QStringLiteral("advance(%1)").arg(wait * 1 / 10));
        QCOMPARE(eval(game.get(), face).toString(), QStringLiteral("furious"));
        QVERIFY(game->property("alarm").toBool());
        QTest::qWait(100); // the steam and the shaking run without a warning
        // Served in time, they're happy; the panic stays only while someone
        // else is that close (the customer who came in a second later is).
        QCOMPARE(eval(game.get(), QStringLiteral("pickBase('cone') && addScoop('mango') && deliver(0)")).toString(),
                 QStringLiteral("right"));
        QCOMPARE(eval(game.get(), face).toString(), QStringLiteral("happy"));
        const QString others = QStringLiteral("seats.some((c, i) => i !== 0 && c && !c.gone && patienceOf(i) <= 0.2)");
        QCOMPARE(game->property("alarm").toBool(), eval(game.get(), others).toBool());
        eval(game.get(), QStringLiteral("advance(%1)").arg(wait));
        QVERIFY(!eval(game.get(), others).toBool() || game->property("alarm").toBool());
    }

    void scoopShopClosesAfterThreeHearts()
    {
        QScopedPointer<QQuickItem> game(shop());
        QVERIFY(game);
        eval(game.get(), QStringLiteral("start('pip')"));
        game->setProperty("autoClock", true);
        QVERIFY(eval(game.get(), QStringLiteral("clock.running")).toBool());
        // Nobody served: the customers give up, one after another.
        eval(game.get(), QStringLiteral("advance(600000)"));
        QCOMPARE(game->property("phase").toString(), QStringLiteral("over"));
        QCOMPARE(game->property("hearts").toInt(), 0);
        QVERIFY(!eval(game.get(), QStringLiteral("clock.running")).toBool());
        // The shop is shut: time stands still and taps do nothing.
        const double now = game->property("now").toDouble();
        eval(game.get(), QStringLiteral("advance(5000)"));
        QCOMPARE(game->property("now").toDouble(), now);
        QVERIFY(!eval(game.get(), QStringLiteral("pickBase('cone')")).toBool());
        QCOMPARE(eval(game.get(), QStringLiteral("deliver(0)")).toString(), QString());
        QVERIFY(eval(game.get(), QStringLiteral("chooser.visible")).toBool());
        // The next shift starts fresh.
        game->setProperty("autoClock", false);
        eval(game.get(), QStringLiteral("start('lotl')"));
        QCOMPARE(game->property("phase").toString(), QStringLiteral("playing"));
        QCOMPARE(game->property("hearts").toInt(), 3);
        QCOMPARE(game->property("score").toInt(), 0);
        QCOMPARE(eval(game.get(), QStringLiteral("seats.filter(c => c).length")).toInt(), 0);
    }

    void scoopShopKeepsTheBest()
    {
        QScopedPointer<QQuickItem> game(shop());
        QVERIFY(game);
        const int before = game->property("best").toInt();
        eval(game.get(), QStringLiteral("start('lotl')"));
        // Serve until the score passes the best so far, then close up.
        for (int i = 0; i < 100 && game->property("score").toInt() <= before; ++i) {
            eval(game.get(), QStringLiteral("seat(0, { base: 'cone', scoops: ['vanilla'], toppings: [] })"));
            QCOMPARE(eval(game.get(), QStringLiteral("pickBase('cone') && addScoop('vanilla') && deliver(0)")).toString(),
                     QStringLiteral("right"));
            eval(game.get(), QStringLiteral("advance(700)"));
        }
        const int score = game->property("score").toInt();
        QVERIFY(score > before);
        eval(game.get(), QStringLiteral("endShift()"));
        QVERIFY(game->property("newBest").toBool());
        QCOMPARE(game->property("best").toInt(), score);

        // Kept, with who worked, when the game opens again.
        game.reset();
        game.reset(shop());
        QVERIFY(game);
        QCOMPARE(game->property("best").toInt(), score);
        QCOMPARE(game->property("worker").toString(), QStringLiteral("lotl"));

        // A worse shift leaves it.
        eval(game.get(), QStringLiteral("start('pip')"));
        eval(game.get(), QStringLiteral("advance(600000)"));
        QCOMPARE(game->property("phase").toString(), QStringLiteral("over"));
        QVERIFY(!game->property("newBest").toBool());
        game.reset();
        game.reset(shop());
        QVERIFY(game);
        QCOMPARE(game->property("best").toInt(), score);
        QCOMPARE(game->property("worker").toString(), QStringLiteral("pip"));
    }

    void scoopShopPlaysByTouch()
    {
        // The clock left running, as in the app: only the taps are the test's.
        QScopedPointer<QQuickItem> game(create(QStringLiteral("qml/games/ScoopShop.qml"), {816, 752}));
        QVERIFY(game);
        game->setProperty("seed", 3);
        QTest::qWait(30);
        tap(game.get(), QStringLiteral("tap:pip"));
        QCOMPARE(game->property("phase").toString(), QStringLiteral("playing"));
        QCOMPARE(game->property("worker").toString(), QStringLiteral("pip"));
        // The first customer comes in on the shop's own clock.
        QTRY_VERIFY_WITH_TIMEOUT(eval(game.get(), QStringLiteral("seats.some(c => c)")).toBool(), 3000);
        const int at = eval(game.get(), QStringLiteral("seats.findIndex(c => c)")).toInt();
        const QStringList keys = eval(game.get(), QStringLiteral(
            "(function (o) { return [o.base].concat(o.scoops, o.toppings) })(seats[%1].order)").arg(at)).toStringList();
        QVERIFY(keys.size() >= 2);
        // Their order, tapped together on the buttons, then handed over.
        for (const QString &key : keys) {
            tap(game.get(), QStringLiteral("tap:") + key);
            QTest::qWait(20);
        }
        QCOMPARE(eval(game.get(), QStringLiteral("build.scoops.length")).toInt(), keys.size() - 1);
        tap(game.get(), QStringLiteral("tap:seat%1").arg(at));
        QCOMPARE(eval(game.get(), QStringLiteral("seats[%1].gone").arg(at)).toString(), QStringLiteral("right"));
        QVERIFY(game->property("score").toInt() > 0);
        // Pause stops the clock; Carry on starts it again.
        tap(game.get(), QStringLiteral("tap:pause"));
        QVERIFY(game->property("paused").toBool());
        const double now = game->property("now").toDouble();
        QTest::qWait(300);
        QCOMPARE(game->property("now").toDouble(), now);
        tap(game.get(), QStringLiteral("tap:carryOn"));
        QVERIFY(game->property("playing").toBool());
        QTRY_VERIFY(game->property("now").toDouble() > now);
        tap(game.get(), QStringLiteral("tap:pause"));
        tap(game.get(), QStringLiteral("tap:endShift"));
        QCOMPARE(game->property("phase").toString(), QStringLiteral("over"));
    }

    void scoopShopFitsEveryPanel()
    {
        // The game's stage on the 7" panel, the 10.1" one, portrait and a TV.
        QScopedPointer<QQuickItem> game(shop({768, 296}));
        QVERIFY(game);
        QTest::qWait(30); // the rows lay out
        checkTargets(game.get(), 2); // who works the shift
        eval(game.get(), QStringLiteral("start('pip')"));
        for (int i = 0; i < 4; ++i)
            eval(game.get(), QStringLiteral("seat(%1, { base: 'cone', scoops: ['mint', 'chocolate', 'strawberry'], toppings: ['cherry', 'wafer'] })").arg(i));
        eval(game.get(), QStringLiteral("advance(15000); pickBase('cup'); addScoop('vanilla'); addTopping('sprinkles')"));
        const QList<std::pair<QSize, QString>> stages = {
            // Full screen: the 7", the 10.1", portrait and a TV.
            {{768, 372}, QStringLiteral("side")}, {{1152, 752}, QStringLiteral("side")},
            {{680, 1160}, QStringLiteral("tall")}, {{1752, 1000}, QStringLiteral("side")},
            // In a page, as games were laid out before, and a squarer stage.
            {{768, 296}, QStringLiteral("side")}, {{816, 752}, QStringLiteral("square")},
            {{680, 1076}, QStringLiteral("tall")}, {{1312, 1000}, QStringLiteral("square")},
            {{768, 372}, QStringLiteral("side")}};
        for (const auto &[size, shape] : stages) {
            game->setSize(size);
            QTest::qWait(30);
            QCOMPARE(eval(game.get(), QStringLiteral("shape")).toString(), shape);
            checkTargets(game.get(), 20); // seventeen buttons, two open seats, pause
            if (QTest::currentTestFailed())
                return;
        }
        // Paused, and closed: their buttons are big enough too.
        eval(game.get(), QStringLiteral("pause()"));
        QVERIFY(!game->property("playing").toBool());
        for (const QSize size : {QSize(768, 372), QSize(1752, 1000)}) {
            game->setSize(size);
            QTest::qWait(30);
            checkTargets(game.get(), 2);
        }
        QVERIFY(eval(game.get(), QStringLiteral("endShift(); phase === 'over'")).toBool());
        for (const QSize size : {QSize(768, 372), QSize(1152, 752), QSize(680, 1160), QSize(1752, 1000)}) {
            game->setSize(size);
            QTest::qWait(30);
            checkTargets(game.get(), 2);
        }
    }

    void screenPausesScoopShopAndScrolls()
    {
        QScopedPointer<QQuickItem> screen(create(QStringLiteral("qml/screens/GamesScreen.qml"), {1180, 800}));
        QVERIFY(screen);
        // A tap on its card, in the scrolling list, opens it. It is in the
        // last row, under the fold here: scroll down to it first.
        QTest::qWait(50);
        eval(screen.get(), QStringLiteral("list.contentY = Math.max(0, list.contentHeight - list.height)"));
        QTest::qWait(50);
        tap(screen.get(), QStringLiteral("card:Scoop Shop"));
        QTRY_VERIFY(eval(screen.get(), QStringLiteral("game !== null")).toBool());
        QCOMPARE(eval(screen.get(), QStringLiteral("openGame.title")).toString(), QStringLiteral("Scoop Shop"));
        eval(screen.get(), QStringLiteral("game.start('pip')"));
        QVERIFY(eval(screen.get(), QStringLiteral("game.playing")).toBool());
        // The assistant panel over it pauses the shift; it carries on when
        // the person says so, not when the panel goes.
        screen->setProperty("shown", false);
        QVERIFY(eval(screen.get(), QStringLiteral("game.paused")).toBool());
        screen->setProperty("shown", true);
        QVERIFY(eval(screen.get(), QStringLiteral("game.paused")).toBool());
        eval(screen.get(), QStringLiteral("game.resume()"));
        QVERIFY(eval(screen.get(), QStringLiteral("game.playing")).toBool());
        // So does how to play, over the game on the small tiers.
        screen->setProperty("howToOpen", true);
        QVERIFY(eval(screen.get(), QStringLiteral("game.paused")).toBool());
        QVERIFY(QMetaObject::invokeMethod(screen.get(), "close"));
        QTRY_VERIFY(eval(screen.get(), QStringLiteral("game === null")).toBool());

        // The list: cards of one height in rows, scrolling once they don't fit.
        const int columns = eval(screen.get(), QStringLiteral("cards.columns")).toInt();
        const int rows = (eval(screen.get(), QStringLiteral("catalog.length")).toInt() + columns - 1) / columns;
        QCOMPARE(eval(screen.get(), QStringLiteral("list.contentHeight")).toDouble(),
                 eval(screen.get(), QStringLiteral("%1 * cardHeight + %2 * cards.rowSpacing").arg(rows).arg(rows - 1)).toDouble());
        screen->setHeight(500);
        QTRY_VERIFY(eval(screen.get(), QStringLiteral("list.interactive")).toBool());
        screen->setHeight(800);
    }

    void maroonStartsAWave()
    {
        QScopedPointer<QQuickItem> game(create(QStringLiteral("games/maroon/maroon.qml")));
        QVERIFY(game);
        game->setProperty("passedSplash", true); // the Play button
        QTRY_VERIFY_WITH_TIMEOUT(eval(game.get(), QStringLiteral("gameState.gameRunning")).toBool(), 8000);
        QTest::mouseClick(m_window, Qt::LeftButton, {}, QPoint(100, 300)); // build menu
        QTest::qWait(1500);
    }
};

QTEST_MAIN(TestGames)
#include "tst_games.moc"
