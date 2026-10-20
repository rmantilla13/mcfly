#include "ColorByNumber.h"

#include <QFont>
#include <QHash>
#include <QPainter>
#include <QSet>

#include <algorithm>
#include <cmath>

namespace Colors {

// colorbynumber.txt, built in (CMakeLists.txt makes ColorByNumberPictures.cpp).
extern const char *const kPictureText;

namespace {

struct Library {
    QList<Category> categories;
    QList<Source> sources;
};

// The file's format is at its top. Anything it can't read becomes a source
// that check() turns down, so a mistake shows in the tests, not as a gap.
const Library &library()
{
    static const Library lib = [] {
        Library out;
        Source *open = nullptr;
        bool wantLegend = false;
        const QStringList lines = QString::fromUtf8(kPictureText).split(QLatin1Char('\n'));
        for (const QString &raw : lines) {
            const QString line = raw.trimmed();
            if (line.startsWith(QLatin1Char('#')))
                continue;
            if (line.isEmpty()) {
                open = nullptr;
                continue;
            }
            if (line.startsWith(QLatin1Char('@'))) {
                const QStringList parts = line.mid(1).split(QLatin1Char('|'));
                out.categories << Category{parts.value(0).trimmed(), parts.value(1).trimmed()};
                continue;
            }
            if (line.startsWith(QLatin1Char('='))) {
                const QStringList parts = line.mid(1).split(QLatin1Char('|'));
                out.sources << Source{parts.value(0).trimmed(), parts.value(1).trimmed(), parts.value(2).trimmed(), {}, {}};
                open = &out.sources.last();
                wantLegend = true;
                continue;
            }
            if (!open)
                continue;
            if (wantLegend) {
                wantLegend = false;
                const QStringList words = line.split(QLatin1Char(' '), Qt::SkipEmptyParts);
                for (int i = 0; i + 1 < words.size(); i += 2) {
                    if (words[i].size() == 1)
                        open->legend << qMakePair(words[i].at(0), words[i + 1]);
                    else
                        open->legend << qMakePair(QChar(), words[i + 1]); // check() refuses it
                }
                if (words.size() % 2)
                    open->legend << qMakePair(QChar(), QString());
                continue;
            }
            open->rows << line;
        }
        return out;
    }();
    return lib;
}

// CIE76 colour difference: how far apart two colours look.
QVector<double> lab(const QColor &c)
{
    auto linear = [](double v) { return v <= 0.04045 ? v / 12.92 : std::pow((v + 0.055) / 1.055, 2.4); };
    const double r = linear(c.redF()), g = linear(c.greenF()), b = linear(c.blueF());
    const double x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047;
    const double y = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    const double z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883;
    auto f = [](double t) { return t > 0.008856 ? std::cbrt(t) : 7.787 * t + 16.0 / 116; };
    return {116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z))};
}

} // namespace

const QList<Category> &categories()
{
    return library().categories;
}

const QList<Source> &sources()
{
    return library().sources;
}

double colorDistance(const QColor &a, const QColor &b)
{
    const QVector<double> p = lab(a), q = lab(b);
    return std::sqrt(std::pow(p[0] - q[0], 2) + std::pow(p[1] - q[1], 2) + std::pow(p[2] - q[2], 2));
}

int indexOf(const QString &id)
{
    const auto &all = pictures();
    for (int i = 0; i < all.size(); ++i) {
        if (all[i].id == id)
            return i;
    }
    return -1;
}

QString check(const Source &source)
{
    if (source.id.isEmpty() || source.title.isEmpty())
        return QStringLiteral("no id or title");
    if (std::none_of(categories().cbegin(), categories().cend(), [&](const Category &c) { return c.id == source.category; }))
        return QStringLiteral("category \"%1\" isn't one").arg(source.category);
    if (source.rows.size() < kMinSize || source.rows.size() > kMaxSize)
        return QStringLiteral("%1 rows (%2 to %3)").arg(source.rows.size()).arg(kMinSize).arg(kMaxSize);
    if (source.legend.isEmpty() || source.legend.size() > kMaxColors)
        return QStringLiteral("%1 colours (1 to %2)").arg(source.legend.size()).arg(kMaxColors);
    const qsizetype width = source.rows.first().size();
    if (width < kMinSize || width > kMaxSize)
        return QStringLiteral("%1 wide (%2 to %3)").arg(width).arg(kMinSize).arg(kMaxSize);
    QSet<QChar> symbols, used;
    for (const auto &entry : source.legend) {
        if (entry.first.isNull() || entry.first == QLatin1Char('.') || symbols.contains(entry.first))
            return QStringLiteral("a legend symbol twice, missing, or the empty one");
        if (!QColor::isValidColorName(entry.second))
            return QStringLiteral("%1 isn't a colour").arg(entry.second);
        symbols.insert(entry.first);
    }
    // Every two colours far enough apart to tell their swatches apart.
    for (int i = 0; i < source.legend.size(); ++i) {
        for (int j = i + 1; j < source.legend.size(); ++j) {
            const double d = colorDistance(QColor(source.legend[i].second), QColor(source.legend[j].second));
            if (d < kMinColorDistance)
                return QStringLiteral("%1 and %2 look alike (%3)").arg(source.legend[i].first).arg(source.legend[j].first).arg(d, 0, 'f', 1);
        }
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
    // Drawn to its edges: no empty row or column round the outside.
    auto emptyColumn = [&](qsizetype column) {
        return std::all_of(source.rows.cbegin(), source.rows.cend(), [&](const QString &row) { return row.at(column) == QLatin1Char('.'); });
    };
    auto emptyRow = [](const QString &row) { return std::all_of(row.cbegin(), row.cend(), [](QChar c) { return c == QLatin1Char('.'); }); };
    if (emptyRow(source.rows.first()) || emptyRow(source.rows.last()) || emptyColumn(0) || emptyColumn(width - 1))
        return QStringLiteral("an empty row or column round the outside");
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
            p.category = source.category;
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

QVariantList ColorByNumberBoard::categories() const
{
    QVariantList out;
    for (const Colors::Category &c : Colors::categories()) {
        const auto &all = Colors::pictures();
        const int count = int(std::count_if(all.cbegin(), all.cend(), [&](const Colors::Picture &p) { return p.category == c.id; }));
        out << QVariantMap{{QStringLiteral("id"), c.id}, {QStringLiteral("title"), c.title}, {QStringLiteral("count"), count}};
    }
    return out;
}

QVariantList ColorByNumberBoard::picturesIn(const QString &category) const
{
    QVariantList out;
    const auto &all = Colors::pictures();
    for (int i = 0; i < all.size(); ++i) {
        if (category.isEmpty() || all[i].category == category)
            out << i;
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
