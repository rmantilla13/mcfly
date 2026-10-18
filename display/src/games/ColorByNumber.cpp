#include "ColorByNumber.h"

#include <QFont>
#include <QHash>
#include <QPainter>
#include <QSet>

#include <algorithm>
#include <cmath>

namespace Colors {

// The pictures, easiest first. Drawn for McFly.
const QList<Source> &sources()
{
    static const QList<Source> list = {
        {QStringLiteral("heart"), QStringLiteral("Heart"),
         {".rrr....rrr.",
          "rwwrr..rrrrr",
          "rwrrrrrrrrrd",
          "rrrrrrrrrrrd",
          "rrrrrrrrrrrd",
          ".rrrrrrrrrd.",
          "..rrrrrrrd..",
          "...rrrrrd...",
          "....rrrd....",
          ".....rd....."},
         {{'r', "#E5484D"}, {'d', "#B8303A"}, {'w', "#FFC9CB"}}},
        {QStringLiteral("strawberry"), QStringLiteral("Strawberry"),
         {"....g..g....",
          "...ghgghg...",
          "..ghhgghhg..",
          ".rrgrrrrgrr.",
          "rrwryrrrryrd",
          "rwrrrrryrrrd",
          "rrryrrrrrrrd",
          ".rrrrryrrrd.",
          ".rryrrrrryd.",
          "..rrrrryrd..",
          "...rryrrd...",
          "....rrdd....",
          ".....dd....."},
         {{'r', "#E5484D"}, {'d', "#B8303A"}, {'y', "#FCE38A"}, {'w', "#FFC9CB"},
          {'g', "#3DB37A"}, {'h', "#23824F"}}},
        {QStringLiteral("rainbow"), QStringLiteral("Rainbow"),
         {"....rrrrrrrr....",
          "..rroooooooorr..",
          ".rooyyyyyyyyoor.",
          "rooyyggggggyyoor",
          "royyggbbbbggyyor",
          "roygbbvvvvbbgyor",
          "roygbv....vbgyor",
          "wwwwbv....vbwwww",
          "cwwwwc....cwwwwc"},
         {{'r', "#E5484D"}, {'o', "#F59E0B"}, {'y', "#FDE047"}, {'g', "#4CBF6B"},
          {'b', "#5B8DEF"}, {'v', "#8E7CE6"}, {'w', "#FFFFFF"}, {'c', "#C9D3E3"}}},
        {QStringLiteral("mushroom"), QStringLiteral("Mushroom"),
         {"....rrrrrr....",
          "..rrwwrrrrrr..",
          ".rrwwwwrrrwwr.",
          ".rrrwwrrrwwwr.",
          "rrrrrrrrrrwwrd",
          "rwwrrrrrrrrrrd",
          "rwwrrrwwrrrrdd",
          ".ddrrrwwrrrdd.",
          "...sssssssst..",
          "...sskssksst..",
          "...sssssssst..",
          "...sssssssst..",
          "....sssssst..."},
         {{'r', "#E5484D"}, {'d', "#B8303A"}, {'w', "#FFFFFF"}, {'s', "#F5E6C8"},
          {'t', "#D9C29A"}, {'k', "#3A2E2A"}}},
        {QStringLiteral("icecream"), QStringLiteral("Ice Cream"),
         {".....s......",
          "....cc......",
          "....cc......",
          "..pppppppp..",
          ".pwwppppppp.",
          "pwwppppppppq",
          "pwpppppppppq",
          "ppppppppppqq",
          "qpqpqpqpqpqq",
          ".klklklklkl.",
          ".lklklklklk.",
          "..klklklkl..",
          "..lklklklk..",
          "...klklkl...",
          "....lklk....",
          ".....kl....."},
         {{'p', "#F7A1C4"}, {'q', "#E27BA6"}, {'w', "#FFE4EF"}, {'k', "#E8A65D"},
          {'l', "#B9773A"}, {'c', "#D7263D"}, {'s', "#3E7C3A"}}},
        {QStringLiteral("flower"), QStringLiteral("Flower"),
         {".....ppp.....",
          "..pp.ppp.pp..",
          ".pppqpppqppp.",
          ".ppppqyqpppp.",
          "..ppqyyoyqpp.",
          "pppqyyooyyqpp",
          "pppqyyyyyyqpp",
          "..ppqyyyyqpp.",
          ".ppppqqqqpppp",
          ".ppp..g..ppp.",
          "......g......",
          "..hh..g......",
          "...hh.g..hh..",
          "....hhghh....",
          "......g......"},
         {{'p', "#F78FB3"}, {'q', "#D9568F"}, {'y', "#FDD34D"}, {'o', "#F2A93B"},
          {'g', "#3DB37A"}, {'h', "#23824F"}}},
        {QStringLiteral("cat"), QStringLiteral("Cat"),
         {"oo..........oo",
          "opo........opo",
          "oppo......oppo",
          "oooooddddooooo",
          "ooooooddoooooo",
          "oogkoooooogkoo",
          "oogkoooooogkoo",
          "dooooowwoooood",
          "dooowwppwwoood",
          ".ooowwwwwwooo.",
          ".oowwkwwkwwoo.",
          "..oowwkkwwoo..",
          "....oooooo...."},
         {{'o', "#F2A04A"}, {'d', "#C46A1E"}, {'w', "#FFF6EA"}, {'p', "#F7A6B5"},
          {'g', "#7FD17A"}, {'k', "#2B2B2B"}}},
        {QStringLiteral("rocket"), QStringLiteral("Rocket"),
         {".....rr.....",
          "....rrrr....",
          "...rrrrrr...",
          "...wwwwwg...",
          "..wwwwwwgg..",
          "..wwnnnngg..",
          "..wwnbbngg..",
          "..wwnbbngg..",
          "..wwnnnngg..",
          "..wwwwwwgg..",
          ".rwwwwwwggr.",
          "rrwwwwwwggrr",
          "rr.wwwwgg.rr",
          "r...oyyo...r",
          "....oyyo....",
          ".....oo....."},
         {{'r', "#E5484D"}, {'w', "#F4F4F6"}, {'g', "#C3C7D1"}, {'n', "#2F4A8A"},
          {'b', "#7FB3F5"}, {'o', "#F59E0B"}, {'y', "#FDE047"}}},
        {QStringLiteral("tree"), QStringLiteral("Apple Tree"),
         {".....gggg.....",
          "...gglggggg...",
          "..glllgggrgg..",
          ".gllgggggggh..",
          ".ggggrgggggggh",
          "gggggggggrgghh",
          "gglgggggggghh.",
          ".gggrgggggghhh",
          ".gggggggggghh.",
          "..hggggghhhh..",
          "....hhthhh....",
          "......tu......",
          "......tu......",
          "......tu......",
          ".....ttuu.....",
          "....tt..uu...."},
         {{'g', "#4CBF6B"}, {'h', "#2E9150"}, {'l', "#8BE09B"}, {'r', "#E5484D"},
          {'t', "#8A5A3B"}, {'u', "#5E3C26"}}},
        {QStringLiteral("house"), QStringLiteral("House"),
         {"...........mm...",
          ".......rr..mm...",
          "......rrrr.mm...",
          ".....rrrrrrmm...",
          "....rrrrrrrr....",
          "...rrrrrrrrrr...",
          ".ssssssssssssss.",
          "..ccccccccccce..",
          "..cbbcnnnncbbe..",
          "..cbbcnnnncbbe..",
          "..ccccnnknccce..",
          "..ccccnnnnccce..",
          "gggggggggggggggg",
          ".g.g.g.g.g.g.g.g"},
         {{'r', "#D64545"}, {'s', "#A83232"}, {'c', "#FFF1D6"}, {'e', "#E9D3A8"},
          {'b', "#7FB3F5"}, {'n', "#8A5A3B"}, {'k', "#F2C14E"}, {'m', "#8C8C94"},
          {'g', "#4CBF6B"}}},
        {QStringLiteral("pip"), QStringLiteral("Pip"),
         {"....hhhhhh....",
          "...gggggggg...",
          "...nnnnnnnn...",
          "..nnnnnnnnnn..",
          ".nnnbbbbbbnnn.",
          ".nnbekbbekbnn.",
          ".nnbbbbbbbbnn.",
          ".nnpbboobbpnn.",
          "nnnbbbbbbbbnnn",
          "nnbbbbbbbbbbnn",
          "nnbbbbbbbbbbnn",
          "nnbbbbbbbbbbnn",
          ".nnbbbbbbbbnn.",
          "..nnbbbbbbnn..",
          "...nnnnnnnn...",
          "..oooo..oooo.."},
         {{'n', "#26345A"}, {'b', "#FFF4DF"}, {'o', "#F29A38"}, {'e', "#FFFFFF"},
          {'k', "#111111"}, {'p', "#F7A6B5"}, {'h', "#FAFAFA"}, {'g', "#3DB37A"}}},
        {QStringLiteral("lotl"), QStringLiteral("Lotl"),
         {"dd............dd",
          "..d..pppppp..d..",
          "ddd.pppppppp.ddd",
          "...pppppppppp...",
          "dddppppppppppddd",
          "..ppwkppppwkpp..",
          "..ppkkppppkkpp..",
          "..pppppmmppppp..",
          "...pppllllppp...",
          "....pllllllp....",
          "...ppllllllpp...",
          "..p.pllllllp.p..",
          "..p..pppppp..p..",
          "......pppp......"},
         {{'p', "#F7A8C8"}, {'d', "#E05A93"}, {'l', "#FDD7E6"}, {'k', "#2B1B2A"},
          {'w', "#FFFFFF"}, {'m', "#B03A6A"}}},
    };
    return list;
}

QString check(const Source &source)
{
    if (source.id.isEmpty() || source.title.isEmpty())
        return QStringLiteral("no id or title");
    if (source.rows.isEmpty())
        return QStringLiteral("no rows");
    if (source.legend.isEmpty() || source.legend.size() > kMaxColors)
        return QStringLiteral("%1 colours (1 to %2)").arg(source.legend.size()).arg(kMaxColors);
    const qsizetype width = source.rows.first().size();
    QSet<QChar> symbols, used;
    for (const auto &entry : source.legend) {
        if (entry.first == QLatin1Char('.') || symbols.contains(entry.first))
            return QStringLiteral("symbol %1 twice, or the empty one").arg(entry.first);
        if (!QColor::isValidColorName(entry.second))
            return QStringLiteral("%1 isn't a colour").arg(entry.second);
        symbols.insert(entry.first);
    }
    for (int r = 0; r < source.rows.size(); ++r) {
        const QString &row = source.rows[r];
        if (row.size() != width)
            return QStringLiteral("row %1 is %2 wide, not %3").arg(r).arg(row.size()).arg(width);
        for (QChar c : row) {
            if (c == QLatin1Char('.'))
                continue;
            if (!symbols.contains(c))
                return QStringLiteral("row %1 has %2, not in the legend").arg(r).arg(c);
            used.insert(c);
        }
    }
    for (QChar c : std::as_const(symbols)) {
        if (!used.contains(c))
            return QStringLiteral("%1 is never used").arg(c);
    }
    return {};
}

const QList<Picture> &pictures()
{
    static const QList<Picture> list = [] {
        QList<Picture> out;
        for (const Source &source : sources()) {
            if (!check(source).isEmpty())
                continue; // the tests say which and why
            Picture p;
            p.id = source.id;
            p.title = source.title;
            p.width = int(source.rows.first().size());
            p.height = int(source.rows.size());
            QHash<QChar, int> number;
            for (const auto &entry : source.legend) {
                p.colors << QColor(entry.second);
                number.insert(entry.first, int(p.colors.size()));
            }
            for (const QString &row : source.rows) {
                for (QChar c : row)
                    p.cells << number.value(c, 0);
            }
            out << p;
        }
        return out;
    }();
    return list;
}

Sheet::Sheet(int picture)
    : m_picture(qBound(0, picture, int(pictures().size()) - 1))
{
    clear();
}

const Picture &Sheet::picture() const
{
    return pictures().at(m_picture);
}

int Sheet::numberAt(int column, int row) const
{
    const Picture &p = picture();
    if (column < 0 || row < 0 || column >= p.width || row >= p.height)
        return 0;
    return p.cells.at(row * p.width + column);
}

bool Sheet::isPainted(int column, int row) const
{
    const Picture &p = picture();
    if (numberAt(column, row) == 0)
        return false;
    return m_painted.at(row * p.width + column);
}

bool Sheet::paint(int column, int row, int number)
{
    const int n = numberAt(column, row);
    if (n == 0 || n != number)
        return false;
    const int i = row * picture().width + column;
    if (m_painted.at(i))
        return false;
    m_painted[i] = true;
    --m_left[n];
    ++m_paintedCount;
    return true;
}

int Sheet::total(int number) const
{
    if (number < 1 || number > picture().colors.size())
        return 0;
    return int(std::count(picture().cells.cbegin(), picture().cells.cend(), number));
}

int Sheet::remaining(int number) const
{
    if (number < 1 || number >= m_left.size())
        return 0;
    return m_left.at(number);
}

QString Sheet::save() const
{
    QString out;
    const Picture &p = picture();
    out.reserve(m_numbered);
    for (int i = 0; i < p.cells.size(); ++i) {
        if (p.cells.at(i) != 0)
            out += m_painted.at(i) ? QLatin1Char('1') : QLatin1Char('0');
    }
    return out;
}

bool Sheet::load(const QString &saved)
{
    if (saved.size() != m_numbered)
        return false;
    for (QChar c : saved) {
        if (c != QLatin1Char('0') && c != QLatin1Char('1'))
            return false;
    }
    clear();
    const Picture &p = picture();
    int k = 0;
    for (int i = 0; i < p.cells.size(); ++i) {
        if (p.cells.at(i) == 0)
            continue;
        if (saved.at(k++) == QLatin1Char('1')) {
            m_painted[i] = true;
            --m_left[p.cells.at(i)];
            ++m_paintedCount;
        }
    }
    return true;
}

void Sheet::clear()
{
    const Picture &p = picture();
    m_painted = QVector<bool>(p.cells.size(), false);
    m_left = QVector<int>(p.colors.size() + 1, 0);
    m_numbered = 0;
    for (int n : p.cells) {
        if (n > 0) {
            ++m_left[n];
            ++m_numbered;
        }
    }
    m_paintedCount = 0;
}

} // namespace Colors

namespace {

QColor mix(const QColor &a, const QColor &b, qreal t)
{
    return QColor::fromRgbF(a.redF() + (b.redF() - a.redF()) * t, a.greenF() + (b.greenF() - a.greenF()) * t,
                            a.blueF() + (b.blueF() - a.blueF()) * t);
}

// Dark ink on a light colour, white on a dark one.
QColor inkOn(const QColor &c)
{
    const qreal luma = 0.2126 * c.redF() + 0.7152 * c.greenF() + 0.0722 * c.blueF();
    return luma > 0.6 ? QColor(QStringLiteral("#2B2522")) : QColor(Qt::white);
}

} // namespace

ColorByNumberBoard::ColorByNumberBoard(QQuickItem *parent)
    : QQuickPaintedItem(parent)
{
    setAntialiasing(true);
}

int ColorByNumberBoard::pictureCount() const
{
    return int(Colors::pictures().size());
}

void ColorByNumberBoard::setPicture(int picture)
{
    picture = qBound(0, picture, pictureCount() - 1);
    if (picture == m_sheet.pictureIndex() && m_sheet.painted() == 0 && m_zoom == 1)
        return;
    m_sheet = Colors::Sheet(picture);
    m_selected = 1;
    m_zoom = 1;
    place();
    emit pictureChanged();
    emit progressChanged();
    emit selectedChanged();
    emit viewChanged();
    update();
}

QVariantList ColorByNumberBoard::colors() const
{
    QVariantList out;
    const auto &colors = m_sheet.picture().colors;
    for (int i = 0; i < colors.size(); ++i) {
        out << QVariantMap{{QStringLiteral("number"), i + 1},
                           {QStringLiteral("color"), colors.at(i)},
                           {QStringLiteral("ink"), inkOn(colors.at(i))},
                           {QStringLiteral("total"), m_sheet.total(i + 1)},
                           {QStringLiteral("remaining"), m_sheet.remaining(i + 1)}};
    }
    return out;
}

void ColorByNumberBoard::setSelected(int number)
{
    number = qBound(1, number, int(m_sheet.picture().colors.size()));
    if (number == m_selected)
        return;
    m_selected = number;
    emit selectedChanged();
    update();
}

void ColorByNumberBoard::setSaved(const QString &saved)
{
    if (saved == m_sheet.save())
        return;
    if (!m_sheet.load(saved))
        m_sheet.clear();
    // Start on a colour that still has cells to paint.
    if (m_sheet.remaining(m_selected) == 0) {
        for (int n = 1; n <= m_sheet.picture().colors.size(); ++n) {
            if (m_sheet.remaining(n) > 0) {
                m_selected = n;
                emit selectedChanged();
                break;
            }
        }
    }
    emit progressChanged();
    update();
}

void ColorByNumberBoard::setDark(bool dark)
{
    if (dark == m_dark)
        return;
    m_dark = dark;
    emit darkChanged();
    update();
}

void ColorByNumberBoard::setPreview(bool preview)
{
    if (preview == m_preview)
        return;
    m_preview = preview;
    emit previewChanged();
    update();
}

qreal ColorByNumberBoard::fitCell() const
{
    if (m_sheet.width() == 0 || m_sheet.height() == 0)
        return 1;
    return qMax<qreal>(1, qMin(width() / m_sheet.width(), height() / m_sheet.height()));
}

qreal ColorByNumberBoard::maxZoom() const
{
    return qMax<qreal>(1, kMaxCell / fitCell());
}

void ColorByNumberBoard::place()
{
    const QSizeF size = pictureSize();
    auto axis = [](qreal offset, qreal picture, qreal view) {
        if (picture <= view)
            return (view - picture) / 2;
        return qBound(view - picture, offset, 0.0);
    };
    m_offset = QPointF(axis(m_offset.x(), size.width(), width()), axis(m_offset.y(), size.height(), height()));
}

bool ColorByNumberBoard::cellAt(const QPointF &point, int &column, int &row) const
{
    const qreal cell = cellSize();
    column = int(std::floor((point.x() - m_offset.x()) / cell));
    row = int(std::floor((point.y() - m_offset.y()) / cell));
    return column >= 0 && row >= 0 && column < m_sheet.width() && row < m_sheet.height();
}

int ColorByNumberBoard::numberAt(const QPointF &point) const
{
    int column, row;
    return cellAt(point, column, row) ? m_sheet.numberAt(column, row) : 0;
}

QPointF ColorByNumberBoard::cellCenter(int column, int row) const
{
    const qreal cell = cellSize();
    return m_offset + QPointF((column + 0.5) * cell, (row + 0.5) * cell);
}

int ColorByNumberBoard::paintCell(int column, int row)
{
    return m_sheet.paint(column, row, m_selected) ? 1 : 0;
}

void ColorByNumberBoard::afterPainting(int count)
{
    if (count == 0)
        return;
    // A colour finished: on to the next one that has cells left.
    if (m_sheet.remaining(m_selected) == 0 && !m_sheet.done()) {
        const int colors = int(m_sheet.picture().colors.size());
        for (int step = 1; step < colors; ++step) {
            const int n = (m_selected - 1 + step) % colors + 1;
            if (m_sheet.remaining(n) > 0) {
                m_selected = n;
                emit selectedChanged();
                break;
            }
        }
    }
    emit progressChanged();
    update();
    if (m_sheet.done())
        emit finished();
}

int ColorByNumberBoard::paintAt(const QPointF &point)
{
    int column, row;
    const int count = cellAt(point, column, row) ? paintCell(column, row) : 0;
    afterPainting(count);
    return count;
}

int ColorByNumberBoard::paintLine(const QPointF &from, const QPointF &to)
{
    // Every cell the finger crossed, so a quick sweep leaves no gaps.
    const qreal step = qMax<qreal>(1, cellSize() / 3);
    const int samples = int(std::ceil(QLineF(from, to).length() / step)) + 1;
    int count = 0;
    for (int i = 0; i <= samples; ++i) {
        int column, row;
        if (cellAt(from + (to - from) * (qreal(i) / samples), column, row))
            count += paintCell(column, row);
    }
    afterPainting(count);
    return count;
}

void ColorByNumberBoard::zoomBy(qreal factor, const QPointF &center)
{
    const qreal zoom = qBound<qreal>(1, m_zoom * factor, maxZoom());
    if (qFuzzyCompare(zoom, m_zoom))
        return;
    const qreal before = cellSize();
    m_zoom = zoom;
    m_offset = center - (center - m_offset) * (cellSize() / before);
    place();
    emit viewChanged();
    update();
}

void ColorByNumberBoard::zoomIn()
{
    zoomBy(1.6, QPointF(width() / 2, height() / 2));
}

void ColorByNumberBoard::zoomOut()
{
    zoomBy(1 / 1.6, QPointF(width() / 2, height() / 2));
}

void ColorByNumberBoard::fit()
{
    if (m_zoom == 1)
        return;
    m_zoom = 1;
    place();
    emit viewChanged();
    update();
}

void ColorByNumberBoard::panBy(qreal dx, qreal dy)
{
    const QPointF before = m_offset;
    m_offset += QPointF(dx, dy);
    place();
    if (m_offset != before) {
        emit viewChanged();
        update();
    }
}

void ColorByNumberBoard::clear()
{
    m_sheet.clear();
    m_selected = 1;
    emit selectedChanged();
    emit progressChanged();
    update();
}

void ColorByNumberBoard::geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry)
{
    QQuickPaintedItem::geometryChange(newGeometry, oldGeometry);
    m_zoom = qMin(m_zoom, maxZoom());
    place();
    emit viewChanged();
    update();
}

void ColorByNumberBoard::paint(QPainter *painter)
{
    const Colors::Picture &p = m_sheet.picture();
    const qreal cell = cellSize();
    // Unpainted cells: white in the light (the board sits on a darker
    // panel, so a picture's own white still shows), a dark grey at night.
    const QColor base = m_dark ? QColor(QStringLiteral("#2C2C31")) : QColor(QStringLiteral("#FFFFFF"));
    const QColor grid = m_dark ? QColor(QStringLiteral("#3D3D45")) : QColor(QStringLiteral("#DED8D0"));
    const QColor number = m_dark ? QColor(QStringLiteral("#A9A9B2")) : QColor(QStringLiteral("#857E77"));
    const bool showNumbers = !m_preview && cell >= 14;
    const int gap = !m_preview && !m_sheet.done() && cell >= 10 ? 1 : 0;

    QFont font = painter->font();
    font.setPixelSize(qMax(8, int(cell * 0.46)));
    QFont bold = font;
    bold.setWeight(QFont::DemiBold);

    // Only the cells in view.
    const int c0 = qMax(0, int(std::floor(-m_offset.x() / cell)));
    const int r0 = qMax(0, int(std::floor(-m_offset.y() / cell)));
    const int c1 = qMin(p.width - 1, int(std::floor((width() - m_offset.x()) / cell)));
    const int r1 = qMin(p.height - 1, int(std::floor((height() - m_offset.y()) / cell)));
    for (int row = r0; row <= r1; ++row) {
        const int y0 = qRound(m_offset.y() + row * cell), y1 = qRound(m_offset.y() + (row + 1) * cell);
        for (int column = c0; column <= c1; ++column) {
            const int n = p.cells.at(row * p.width + column);
            if (n == 0)
                continue;
            const int x0 = qRound(m_offset.x() + column * cell), x1 = qRound(m_offset.x() + (column + 1) * cell);
            const QRect r(x0, y0, x1 - x0, y1 - y0);
            const QColor colour = p.colors.at(n - 1);
            if (m_sheet.isPainted(column, row)) {
                painter->fillRect(r, colour);
                continue;
            }
            const bool chosen = !m_preview && n == m_selected;
            // A thumbnail shows the picture faintly, a hint of what it'll be.
            const QColor fill = chosen ? mix(base, colour, 0.45) : m_preview ? mix(base, colour, 0.22) : base;
            if (gap) {
                painter->fillRect(r, grid);
                painter->fillRect(r.adjusted(0, 0, -gap, -gap), fill);
            } else {
                painter->fillRect(r, fill);
            }
            if (showNumbers) {
                painter->setFont(chosen ? bold : font);
                painter->setPen(chosen ? inkOn(fill) : number);
                painter->drawText(r.adjusted(0, 0, -gap, -gap), Qt::AlignCenter, QString::number(n));
            }
        }
    }
}
