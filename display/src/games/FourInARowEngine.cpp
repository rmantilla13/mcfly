#include "FourInARowEngine.h"

#include <QRandomGenerator>
#include <QtAlgorithms>

#include <array>
#include <limits>

namespace {

// Bitboards: bit column * 7 + row, row 0 at the bottom. Each column has a
// spare bit on top, so a line can't run from one column into the next.
constexpr int Columns = 7;
constexpr int Rows = 6;
constexpr int Stride = Rows + 1;
constexpr std::array<int, Columns> Order = {3, 2, 4, 1, 5, 0, 6}; // the middle first
constexpr int Win = 1000000;
// The most positions one move may weigh: about 40 ms on a Mac, under 200 on
// the Pi. Most moves finish ten discs ahead well inside it.
constexpr qint64 NodeCap = 600000;

constexpr quint64 bit(int column, int row) { return quint64(1) << (column * Stride + row); }
constexpr quint64 bottom(int column) { return bit(column, 0); }
constexpr quint64 top(int column) { return bit(column, Rows - 1); }
constexpr quint64 columnMask(int column) { return ((quint64(1) << Rows) - 1) << (column * Stride); }

bool fourInARow(quint64 b)
{
    for (int shift : {1, Stride, Stride - 1, Stride + 1}) { // down, across, both diagonals
        const quint64 pairs = b & (b >> shift);
        if (pairs & (pairs >> (2 * shift)))
            return true;
    }
    return false;
}

// Every line of four holes on the board, as masks.
const std::array<quint64, 69> &windows()
{
    static const std::array<quint64, 69> list = [] {
        std::array<quint64, 69> w{};
        int n = 0;
        const int steps[4][2] = {{1, 0}, {0, 1}, {1, 1}, {1, -1}};
        for (int c = 0; c < Columns; ++c) {
            for (int r = 0; r < Rows; ++r) {
                for (const auto &s : steps) {
                    const int endC = c + 3 * s[0], endR = r + 3 * s[1];
                    if (endC < 0 || endC >= Columns || endR < 0 || endR >= Rows)
                        continue;
                    quint64 mask = 0;
                    for (int k = 0; k < 4; ++k)
                        mask |= bit(c + k * s[0], r + k * s[1]);
                    w[n++] = mask;
                }
            }
        }
        return w;
    }();
    return list;
}

} // namespace

// How good the board looks for `mine`: open threes and twos, and the middle
// column, which takes part in the most lines.
int FourInARowEngine::evaluate(quint64 mine, quint64 theirs) const
{
    int total = 0;
    for (quint64 w : windows()) {
        const int a = int(qPopulationCount(mine & w)), b = int(qPopulationCount(theirs & w));
        if (b == 0)
            total += a == 3 ? 5 : a == 2 ? 2 : 0;
        else if (a == 0)
            total -= b == 3 ? 4 : b == 2 ? 2 : 0;
    }
    total += 3 * (int(qPopulationCount(mine & columnMask(3))) - int(qPopulationCount(theirs & columnMask(3))));
    return total;
}

// Negamax with alpha-beta: the value of the board for `mine`, to move.
int FourInARowEngine::search(quint64 mine, quint64 theirs, int left, int ply, int alpha, int beta)
{
    if (m_aborted || ++m_nodes > NodeCap) {
        m_aborted = true;
        return 0;
    }
    const quint64 both = mine | theirs;
    if (left == 0)
        return evaluate(mine, theirs);
    int best = std::numeric_limits<int>::min();
    for (int c : Order) {
        if (both & top(c))
            continue;
        const quint64 drop = (both + bottom(c)) & columnMask(c);
        const quint64 next = mine | drop;
        const int v = fourInARow(next) ? Win - ply : -search(theirs, next, left - 1, ply + 1, -beta, -alpha);
        if (v > best)
            best = v;
        if (best > alpha)
            alpha = best;
        if (alpha >= beta)
            break;
    }
    return best == std::numeric_limits<int>::min() ? 0 : best; // a full board: a draw
}

int FourInARowEngine::bestMove(const QStringList &cells, const QString &player, int depth)
{
    m_nodes = 0;
    quint64 mine = 0, theirs = 0;
    for (int i = 0; i < qMin<qsizetype>(cells.size(), Columns * Rows); ++i) {
        if (cells[i].isEmpty())
            continue;
        (cells[i] == player ? mine : theirs) |= bit(i % Columns, i / Columns);
    }
    const quint64 both = mine | theirs;
    QList<int> legal;
    for (int c : Order) {
        if (!(both & top(c)))
            legal << c;
    }
    if (legal.isEmpty())
        return -1;

    // A disc deeper each time, keeping the last look that finished: a
    // tangled board stops short of `depth` rather than hold the screen.
    QList<int> choices = legal;
    m_aborted = false;
    for (int d = 1; d <= qMax(1, depth); ++d) {
        int bestValue = std::numeric_limits<int>::min();
        QList<int> found;
        for (int c : legal) {
            const quint64 next = mine | ((both + bottom(c)) & columnMask(c));
            int v = Win - 1;
            if (!fourInARow(next)) {
                // A column only has to be shown worse than the best so far;
                // one as good comes back exact, so ties are found.
                const int alpha = found.isEmpty() ? -Win - 1 : bestValue - 1;
                v = -search(theirs, next, d - 1, 2, -Win - 1, -alpha);
            }
            if (m_aborted)
                break;
            if (v > bestValue) {
                bestValue = v;
                found = {c};
            } else if (v == bestValue) {
                found << c;
            }
        }
        if (m_aborted)
            break;
        choices = found;
        // A sure win or loss won't change with a deeper look.
        if (qAbs(bestValue) >= Win - Columns * Rows)
            break;
    }
    return choices[QRandomGenerator::global()->bounded(int(choices.size()))];
}
