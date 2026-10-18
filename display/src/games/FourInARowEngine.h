#pragma once

#include <QObject>
#include <QStringList>

// McFly's look-ahead in Four in a Row (qml/games/FourInARow.qml). The rules
// and the board stay in QML; this only picks a column. In JavaScript the
// same search took seconds a move on a Mac, all of it on the thread that
// draws the screen; here, on bitboards, Hard's look of up to ten discs
// ahead takes milliseconds, and a move that would weigh too many positions
// keeps the deepest look it finished.
class FourInARowEngine : public QObject
{
    Q_OBJECT

public:
    using QObject::QObject;

    // The column `player` ("X" or "O") should drop a disc in, looking up to
    // `depth` discs ahead: wins soonest, loses latest, and picks at random
    // between equally good columns so games don't repeat. -1 when the board
    // is full. `cells` is the QML board: 42 holes, bottom row first
    // (index = row * 7 + column), "" for an empty one.
    Q_INVOKABLE int bestMove(const QStringList &cells, const QString &player, int depth);

    // Positions weighed by the last bestMove(), for the log and the tests.
    Q_INVOKABLE qint64 lastNodes() const { return m_nodes; }

private:
    int search(quint64 mine, quint64 theirs, int left, int ply, int alpha, int beta);
    int evaluate(quint64 mine, quint64 theirs) const;

    qint64 m_nodes = 0;
    bool m_aborted = false;
};
