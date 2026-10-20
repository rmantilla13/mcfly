#pragma once

#include <QColor>
#include <QList>
#include <QQuickPaintedItem>
#include <QStringList>
#include <QVariantList>
#include <QVector>

// Color by Number (qml/games/ColorByNumber.qml): pixel pictures whose cells
// carry the number of their colour; pick a colour and paint its cells.
// Written for McFly, after Araib Karim's Color by Number for iOS; none of
// its code or pictures (it has no licence) is used. The pictures are ours.
namespace Colors {

// The most colours a picture has: the palette is a row of 64 px swatches,
// and the narrowest stage (portrait) fits nine.
constexpr int kMaxColors = 9;

// A picture is between these many cells wide and tall.
constexpr int kMinSize = 8;
constexpr int kMaxSize = 24;
// How far apart (CIE76) any two of a picture's colours are, at least, so
// their swatches can be told apart.
constexpr double kMinColorDistance = 10;

// The pictures live in colorbynumber.txt (its format is at its top), built
// into the app; the iPhone app's copy is held to it by its tests.
struct Category {
    QString id;
    QString title;
};
const QList<Category> &categories();

// A picture as written: rows of symbols, "." for an empty cell, and a
// legend giving each symbol its colour. Numbers follow the legend's order.
struct Source {
    QString id;
    QString title;
    QString category;
    QStringList rows;
    QList<QPair<QChar, QString>> legend;
};
const QList<Source> &sources();
// What's wrong with a source, or "" when nothing is.
QString check(const Source &source);
double colorDistance(const QColor &a, const QColor &b);

struct Picture {
    QString id;
    QString title;
    QString category;
    int width = 0;
    int height = 0;
    QList<QColor> colors; // number n is colors[n - 1]
    QVector<int> cells;   // row by row from the top; 0 for an empty cell
};
const QList<Picture> &pictures();
// A picture's place in pictures(), or -1.
int indexOf(const QString &id);

// One picture being painted: which numbered cells are done.
class Sheet
{
public:
    explicit Sheet(int picture = 0);
    int pictureIndex() const { return m_picture; }
    const Picture &picture() const;
    int width() const { return picture().width; }
    int height() const { return picture().height; }
    // 0 for an empty cell or one off the picture.
    int numberAt(int column, int row) const;
    bool isPainted(int column, int row) const;
    // Paints a cell if it carries `number` and isn't painted yet.
    bool paint(int column, int row, int number);
    int total(int number) const;
    int remaining(int number) const;
    int painted() const { return m_paintedCount; }
    int cellCount() const { return m_numbered; }
    bool done() const { return m_numbered > 0 && m_paintedCount == m_numbered; }
    // Progress as text, a 0 or 1 for each numbered cell in order: what the
    // game keeps in LocalStorage. load() takes back what save() gave, and
    // refuses anything else (another picture's, a damaged one).
    QString save() const;
    bool load(const QString &saved);
    void clear();

private:
    int m_picture = 0;
    int m_numbered = 0;
    int m_paintedCount = 0;
    QVector<bool> m_painted;
    QVector<int> m_left; // per number, 1-based
};

} // namespace Colors

// The board: a picture at the size it is shown, drawing only the cells in
// view. Zoom 1 fits the whole picture; up to cells of kMaxCell px. All the
// painting and panning goes through here; QML only passes on touches.
class ColorByNumberBoard : public QQuickPaintedItem
{
    Q_OBJECT
    Q_PROPERTY(int picture READ picture WRITE setPicture NOTIFY pictureChanged)
    Q_PROPERTY(int pictureCount READ pictureCount CONSTANT)
    Q_PROPERTY(QString pictureId READ pictureId NOTIFY pictureChanged)
    Q_PROPERTY(QString title READ title NOTIFY pictureChanged)
    Q_PROPERTY(QString category READ category NOTIFY pictureChanged)
    // [{id, title, count}], in the file's order, for the gallery's chips.
    Q_PROPERTY(QVariantList categories READ categories CONSTANT)
    // [{number, color, ink, total, remaining}], for the swatches.
    Q_PROPERTY(QVariantList colors READ colors NOTIFY progressChanged)
    Q_PROPERTY(int selected READ selected WRITE setSelected NOTIFY selectedChanged)
    Q_PROPERTY(int painted READ painted NOTIFY progressChanged)
    Q_PROPERTY(int total READ total NOTIFY pictureChanged)
    Q_PROPERTY(bool done READ done NOTIFY progressChanged)
    // The progress as text (Colors::Sheet::save()); set it to carry on.
    Q_PROPERTY(QString saved READ saved WRITE setSaved NOTIFY progressChanged)
    Q_PROPERTY(qreal zoom READ zoom NOTIFY viewChanged)
    Q_PROPERTY(qreal cellSize READ cellSize NOTIFY viewChanged)
    Q_PROPERTY(bool canZoomIn READ canZoomIn NOTIFY viewChanged)
    Q_PROPERTY(bool canZoomOut READ canZoomOut NOTIFY viewChanged)
    Q_PROPERTY(bool dark READ dark WRITE setDark NOTIFY darkChanged)
    // A thumbnail: no numbers or grid, unpainted cells a faint tint of their colour.
    Q_PROPERTY(bool preview READ preview WRITE setPreview NOTIFY previewChanged)

public:
    // The biggest a cell gets when zoomed in.
    static constexpr qreal kMaxCell = 96;

    explicit ColorByNumberBoard(QQuickItem *parent = nullptr);

    int picture() const { return m_sheet.pictureIndex(); }
    void setPicture(int picture);
    int pictureCount() const;
    QString pictureId() const { return m_sheet.picture().id; }
    QString title() const { return m_sheet.picture().title; }
    QString category() const { return m_sheet.picture().category; }
    QVariantList categories() const;
    QVariantList colors() const;
    int selected() const { return m_selected; }
    void setSelected(int number);
    int painted() const { return m_sheet.painted(); }
    int total() const { return m_sheet.cellCount(); }
    bool done() const { return m_sheet.done(); }
    QString saved() const { return m_sheet.save(); }
    void setSaved(const QString &saved);
    qreal zoom() const { return m_zoom; }
    qreal cellSize() const { return fitCell() * m_zoom; }
    bool canZoomIn() const { return m_zoom < maxZoom() - 1e-6; }
    bool canZoomOut() const { return m_zoom > 1 + 1e-6; }
    bool dark() const { return m_dark; }
    void setDark(bool dark);
    bool preview() const { return m_preview; }
    void setPreview(bool preview);

    // The number of the cell under a point (0 for none).
    Q_INVOKABLE int numberAt(const QPointF &point) const;
    // Paints the cell under a point, or every cell along a drag from `from`
    // to `to`, that carries the selected number. Returns how many it painted.
    Q_INVOKABLE int paintAt(const QPointF &point);
    Q_INVOKABLE int paintLine(const QPointF &from, const QPointF &to);
    // The middle of a cell, where it is drawn now.
    Q_INVOKABLE QPointF cellCenter(int column, int row) const;
    // The pictures in a category ("" for all), as indexes, in the file's order.
    Q_INVOKABLE QVariantList picturesIn(const QString &category) const;
    Q_INVOKABLE int indexOf(const QString &id) const { return Colors::indexOf(id); }
    Q_INVOKABLE void zoomBy(qreal factor, const QPointF &center);
    Q_INVOKABLE void zoomIn();
    Q_INVOKABLE void zoomOut();
    Q_INVOKABLE void fit();
    Q_INVOKABLE void panBy(qreal dx, qreal dy);
    Q_INVOKABLE void clear();

    void paint(QPainter *painter) override;

signals:
    void pictureChanged();
    void progressChanged();
    void selectedChanged();
    void viewChanged();
    void darkChanged();
    void previewChanged();
    // The last cell of the picture was painted.
    void finished();

protected:
    void geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) override;

private:
    qreal fitCell() const;
    qreal maxZoom() const;
    QSizeF pictureSize() const { return QSizeF(m_sheet.width(), m_sheet.height()) * cellSize(); }
    void place(); // keeps the picture in view (centred where it fits)
    bool cellAt(const QPointF &point, int &column, int &row) const;
    int paintCell(int column, int row);
    void afterPainting(int count);

    Colors::Sheet m_sheet;
    int m_selected = 1;
    qreal m_zoom = 1;
    QPointF m_offset; // the picture's top left, in item coordinates
    bool m_dark = false;
    bool m_preview = false;
};
