#include <QSet>
#include <QSignalSpy>
#include <QtTest>

#include "games/ColorByNumber.h"

using namespace Colors;

// Color by Number: the pictures, painting and progress (Colors::Sheet), and
// the board's view and touch (ColorByNumberBoard), without QML.
class TestColors : public QObject
{
    Q_OBJECT

    // The first cell (column, row) carrying `number`, or (-1, -1).
    static QPoint firstOf(const Sheet &sheet, int number)
    {
        for (int row = 0; row < sheet.height(); ++row) {
            for (int column = 0; column < sheet.width(); ++column) {
                if (sheet.numberAt(column, row) == number)
                    return {column, row};
            }
        }
        return {-1, -1};
    }

private slots:
    void everyPictureIsWellFormed()
    {
        QSet<QString> ids;
        for (const Source &source : sources()) {
            QVERIFY2(check(source).isEmpty(), qPrintable(source.id + QStringLiteral(": ") + check(source)));
            QVERIFY2(!ids.contains(source.id), qPrintable(source.id));
            ids.insert(source.id);
        }
        // None was dropped for a fault, and there are enough to choose from.
        QCOMPARE(pictures().size(), sources().size());
        QVERIFY(pictures().size() >= 10);
        for (const Picture &p : pictures()) {
            QVERIFY2(p.colors.size() <= kMaxColors, qPrintable(p.id));
            QVERIFY2(p.width >= 8 && p.width <= 24 && p.height >= 8 && p.height <= 24, qPrintable(p.id));
            QCOMPARE(p.cells.size(), p.width * p.height);
            // Every number is used, and no row or column is empty all the way.
            for (int n = 1; n <= p.colors.size(); ++n)
                QVERIFY2(p.cells.contains(n), qPrintable(p.id));
            for (int row = 0; row < p.height; ++row) {
                bool any = false;
                for (int column = 0; column < p.width; ++column)
                    any = any || p.cells.at(row * p.width + column) != 0;
                QVERIFY2(any, qPrintable(QStringLiteral("%1 row %2 is empty").arg(p.id).arg(row)));
            }
        }
        // check() catches a broken one.
        Source broken = sources().first();
        broken.rows[1].chop(1);
        QVERIFY(!check(broken).isEmpty());
        broken = sources().first();
        broken.rows[0][0] = QLatin1Char('z');
        QVERIFY(!check(broken).isEmpty());
    }

    void paintingTakesOnlyItsNumber()
    {
        Sheet sheet(0);
        const QPoint one = firstOf(sheet, 1), two = firstOf(sheet, 2);
        QVERIFY(one.x() >= 0 && two.x() >= 0);
        const int left = sheet.remaining(1);
        QVERIFY(!sheet.paint(two.x(), two.y(), 1)); // the wrong colour does nothing
        QVERIFY(!sheet.paint(-1, 0, 1));
        QVERIFY(sheet.paint(one.x(), one.y(), 1));
        QVERIFY(!sheet.paint(one.x(), one.y(), 1)); // once
        QVERIFY(sheet.isPainted(one.x(), one.y()));
        QCOMPARE(sheet.remaining(1), left - 1);
        QCOMPARE(sheet.painted(), 1);
        QVERIFY(!sheet.done());
    }

    void progressIsSavedAndRestored()
    {
        Sheet sheet(3);
        int painted = 0;
        for (int row = 0; row < sheet.height(); row += 2) {
            for (int column = 0; column < sheet.width(); ++column)
                painted += sheet.paint(column, row, sheet.numberAt(column, row)) ? 1 : 0;
        }
        const QString saved = sheet.save();
        QCOMPARE(saved.size(), sheet.cellCount());
        QCOMPARE(saved.count(QLatin1Char('1')), painted);

        Sheet again(3);
        QVERIFY(again.load(saved));
        QCOMPARE(again.painted(), painted);
        QCOMPARE(again.save(), saved);
        for (int n = 1; n <= again.picture().colors.size(); ++n)
            QCOMPARE(again.remaining(n), sheet.remaining(n));
        // Another picture's progress, or a damaged one, is refused.
        QVERIFY(!again.load(saved.chopped(1)));
        QVERIFY(!again.load(QString(saved.size(), QLatin1Char('x'))));
        QVERIFY(!Sheet(0).load(saved));
    }

    void everyPictureCanBeFinished()
    {
        for (int i = 0; i < pictures().size(); ++i) {
            Sheet sheet(i);
            for (int row = 0; row < sheet.height(); ++row) {
                for (int column = 0; column < sheet.width(); ++column)
                    sheet.paint(column, row, sheet.numberAt(column, row));
            }
            QVERIFY2(sheet.done(), qPrintable(sheet.picture().id));
            QCOMPARE(sheet.painted(), sheet.cellCount());
            QVERIFY(!sheet.save().contains(QLatin1Char('0')));
        }
    }

    void boardPaintsByTouch()
    {
        ColorByNumberBoard board;
        board.setSize(QSizeF(400, 300));
        board.setPicture(0); // 12 x 10: cells of 30
        QCOMPARE(board.cellSize(), 30.0);
        QCOMPARE(board.selected(), 1);
        QSignalSpy finished(&board, &ColorByNumberBoard::finished);

        // Only cells with the selected number take paint.
        Sheet sheet(0);
        const QPoint one = firstOf(sheet, 1), two = firstOf(sheet, 2);
        QCOMPARE(board.numberAt(board.cellCenter(one.x(), one.y())), 1);
        QCOMPARE(board.paintAt(board.cellCenter(two.x(), two.y())), 0);
        QCOMPARE(board.paintAt(board.cellCenter(one.x(), one.y())), 1);
        QCOMPARE(board.painted(), 1);
        QCOMPARE(board.numberAt(QPointF(-5, -5)), 0);

        // A sweep across a row paints every selected cell it crossed.
        const int row = 3;
        int ones = 0;
        for (int column = 0; column < sheet.width(); ++column)
            ones += sheet.numberAt(column, row) == 1 ? 1 : 0;
        QVERIFY(ones > 2);
        QCOMPARE(board.paintLine(board.cellCenter(0, row), board.cellCenter(sheet.width() - 1, row)), ones);

        // Finishing a colour moves on to the next one with cells left.
        for (int r = 0; r < sheet.height(); ++r)
            board.paintLine(board.cellCenter(0, r), board.cellCenter(sheet.width() - 1, r));
        QCOMPARE(board.colors().first().toMap().value(QStringLiteral("remaining")).toInt(), 0);
        QCOMPARE(board.selected(), 2);
        // Then all of them: finished, once.
        for (int n = 2; n <= sheet.picture().colors.size(); ++n) {
            board.setSelected(n);
            for (int r = 0; r < sheet.height(); ++r)
                board.paintLine(board.cellCenter(0, r), board.cellCenter(sheet.width() - 1, r));
        }
        QVERIFY(board.done());
        QCOMPARE(finished.count(), 1);

        // The progress goes out as text and comes back.
        const QString saved = board.saved();
        board.clear();
        QCOMPARE(board.painted(), 0);
        board.setSaved(saved);
        QVERIFY(board.done());
        board.setSaved(QStringLiteral("nonsense"));
        QCOMPARE(board.painted(), 0);
    }

    void boardZoomsAndPans()
    {
        ColorByNumberBoard board;
        board.setSize(QSizeF(400, 300));
        board.setPicture(11); // 16 x 14: cells of 300 / 14
        const qreal fit = board.cellSize();
        QVERIFY(!board.canZoomOut());
        QVERIFY(board.canZoomIn());
        // At fit the picture can't move.
        const QPointF corner = board.cellCenter(0, 0);
        board.panBy(50, 50);
        QCOMPARE(board.cellCenter(0, 0), corner);

        // Zoom in on the middle: bigger cells, never past kMaxCell.
        board.zoomIn();
        QVERIFY(board.cellSize() > fit);
        QVERIFY(board.canZoomOut());
        for (int i = 0; i < 10; ++i)
            board.zoomIn();
        QCOMPARE(board.cellSize(), ColorByNumberBoard::kMaxCell);
        QVERIFY(!board.canZoomIn());
        // Panned as far as it goes, the picture still covers the board.
        board.panBy(10000, 10000);
        QCOMPARE(board.cellCenter(0, 0), QPointF(board.cellSize() / 2, board.cellSize() / 2));
        board.panBy(-10000, -10000);
        const QPointF last = board.cellCenter(15, 13);
        QCOMPARE(last.x() + board.cellSize() / 2, 400.0);
        QCOMPARE(last.y() + board.cellSize() / 2, 300.0);
        // Back to fit.
        board.fit();
        QCOMPARE(board.cellSize(), fit);
        QCOMPARE(board.cellCenter(0, 0), corner);
    }
};

QTEST_MAIN(TestColors)
#include "tst_colors.moc"
