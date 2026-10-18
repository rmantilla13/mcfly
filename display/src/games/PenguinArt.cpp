#include "PenguinArt.h"

#include <QLinearGradient>
#include <QPainter>
#include <QPainterPath>
#include <QtMath>

#include <cmath>

namespace Penguins {

Palette palette(bool dark)
{
    Palette p;
    if (!dark) {
        p.iceTop = QColor("#D6EAF8");
        p.iceBottom = QColor("#86B3D9");
        p.snow = QColor("#FFFFFF");
        p.iceShade = QColor("#6A97C2");
        p.speck = QColor(255, 255, 255, 120);
        p.rock = QColor("#7D8798");
        p.rockTop = QColor("#A9B2C0");
        p.rockShade = QColor("#5D6677");
        p.water = QColor(46, 128, 190, 225);
        p.waterDeep = QColor(24, 78, 132, 240);
        p.crest = QColor("#BFE6FA");
        p.igloo = QColor("#F4F9FD");
        p.iglooLine = QColor("#A9C7E2");
        p.door = QColor("#24364F");
        p.hatch = QColor("#5E7391");
        p.hatchLine = QColor("#3E4F68");
        p.hatchDoor = QColor("#2B3A50");
        p.rim = QColor("#121823");
    } else {
        p.iceTop = QColor("#A9C6DE");
        p.iceBottom = QColor("#3F6489");
        p.snow = QColor("#E4EEF7");
        p.iceShade = QColor("#2C4B6C");
        p.speck = QColor(255, 255, 255, 70);
        p.rock = QColor("#5D6574");
        p.rockTop = QColor("#868F9E");
        p.rockShade = QColor("#41485A");
        p.water = QColor(38, 104, 160, 225);
        p.waterDeep = QColor(16, 52, 92, 240);
        p.crest = QColor("#8FCBEA");
        p.igloo = QColor("#DCE8F3");
        p.iglooLine = QColor("#8DA9C4");
        p.door = QColor("#0E1828");
        p.hatch = QColor("#4C5F7C");
        p.hatchLine = QColor("#2E3B50");
        p.hatchDoor = QColor("#1E2838");
        p.rim = QColor("#9FB2D2"); // a light rim reads on the night sky
    }
    p.plank = QColor("#C98B4E");
    p.plankTop = QColor("#E8B47A");
    p.plankShade = QColor("#94612F");
    p.body = QColor("#28324A");
    p.belly = QColor("#FFFFFF");
    p.beak = QColor("#F5A524");
    p.eye = QColor("#121823");
    p.blush = QColor(242, 140, 150, 150);
    p.flag = QColor("#F07F5A");
    // The skills' colours, the same on their buttons.
    p.skill = {QColor("#E5484D"), QColor("#E0912A"), QColor("#8E7CE6"), QColor("#3DB37A"), QColor("#4F7CF7")};
    return p;
}

namespace {

QPainterPath shapePath(const Shape &shape)
{
    QPainterPath path;
    if (shape.ellipse) {
        const QRect r = shape.polygon.boundingRect();
        path.addEllipse(QRectF(r.x(), r.y(), r.width() - 1, r.height() - 1));
    } else {
        path.addPolygon(QPolygonF(shape.polygon));
        path.closeSubpath();
    }
    return path;
}

// A small, fixed scatter (no randomness: the same picture every time).
quint32 hash(quint32 x)
{
    x ^= x >> 16;
    x *= 0x7feb352dU;
    x ^= x >> 15;
    x *= 0x846ca68bU;
    x ^= x >> 16;
    return x;
}

// Bands along the top (snow, rock's lit edge) and under overhangs: the layer
// where the pixel `offset` above (or below) is empty.
void addEdge(QImage &layer, int offset, const QColor &color, int alpha = 255)
{
    QImage band = layer;
    {
        QPainter b(&band);
        b.setCompositionMode(QPainter::CompositionMode_SourceIn);
        QColor c = color;
        c.setAlpha(alpha);
        b.fillRect(band.rect(), c);
        b.setCompositionMode(QPainter::CompositionMode_DestinationOut);
        b.drawImage(QPoint(0, offset), layer);
    }
    QPainter l(&layer);
    l.setCompositionMode(QPainter::CompositionMode_SourceAtop);
    l.drawImage(0, 0, band);
}

} // namespace

void paintTerrain(const Level &level, double px, const Palette &pal, QImage &ground, QImage &rock)
{
    const QSize size(qCeil(level.size.width() * px), qCeil(level.size.height() * px));
    ground = QImage(size, QImage::Format_ARGB32_Premultiplied);
    rock = QImage(size, QImage::Format_ARGB32_Premultiplied);
    ground.fill(Qt::transparent);
    rock.fill(Qt::transparent);

    QLinearGradient ice(0, 0, 0, level.size.height());
    ice.setColorAt(0, pal.iceTop);
    ice.setColorAt(1, pal.iceBottom);
    {
        QPainter g(&ground);
        QPainter r(&rock);
        for (QPainter *p : {&g, &r}) {
            p->setRenderHint(QPainter::Antialiasing);
            p->scale(px, px);
            p->setPen(Qt::NoPen);
        }
        for (const Shape &shape : level.shapes) {
            const QPainterPath path = shapePath(shape);
            switch (shape.kind) {
            case Shape::Ground:
                g.setCompositionMode(QPainter::CompositionMode_SourceOver);
                g.fillPath(path, ice);
                r.setCompositionMode(QPainter::CompositionMode_Clear);
                r.fillPath(path, Qt::black);
                break;
            case Shape::Steel:
                r.setCompositionMode(QPainter::CompositionMode_SourceOver);
                r.fillPath(path, pal.rock);
                break;
            case Shape::Cut:
                for (QPainter *p : {&g, &r}) {
                    p->setCompositionMode(QPainter::CompositionMode_Clear);
                    p->fillPath(path, Qt::black);
                }
                break;
            }
        }
        // Specks of frost in the ice, and seams in the rock: a few small
        // marks on a fixed scatter, kept inside each layer.
        g.setCompositionMode(QPainter::CompositionMode_SourceAtop);
        r.setCompositionMode(QPainter::CompositionMode_SourceAtop);
        const int cols = level.size.width() / 12 + 1;
        const int rows = level.size.height() / 12 + 1;
        for (int j = 0; j < rows; ++j) {
            for (int i = 0; i < cols; ++i) {
                const quint32 h = hash(quint32(j * 977 + i * 131 + 7));
                const double x = i * 12 + (h % 12);
                const double y = j * 12 + ((h >> 8) % 12);
                const double len = 2 + ((h >> 16) % 4);
                g.setBrush(pal.speck);
                g.drawEllipse(QPointF(x, y), 0.7, 0.7);
                r.setPen(QPen(pal.rockShade, 0.6, Qt::SolidLine, Qt::RoundCap));
                if ((h >> 20) % 3 == 0)
                    r.drawLine(QPointF(x, y), QPointF(x + len, y + ((h >> 24) % 3) - 1));
            }
        }
    }
    // Snow on every top, a darker edge under every overhang; rock's lit top.
    addEdge(ground, qRound(3 * px), pal.snow);
    addEdge(ground, -qRound(2 * px), pal.iceShade, 200);
    addEdge(rock, qRound(2 * px), pal.rockTop);
    addEdge(rock, -qRound(2 * px), pal.rockShade);
}

QRect paintEdit(QImage &ground, const TerrainEdit &edit, double px, const Palette &pal)
{
    QPainter g(&ground);
    g.setRenderHint(QPainter::Antialiasing);
    g.scale(px, px);
    g.setPen(Qt::NoPen);
    const QRectF r(edit.rect);
    if (edit.kind == TerrainEdit::Cut) {
        g.setCompositionMode(QPainter::CompositionMode_Clear);
        g.fillRect(r, Qt::black);
    } else {
        // A plank: lit along the top, shaded under.
        g.setBrush(pal.plank);
        g.drawRoundedRect(r, 0.5, 0.5);
        g.setBrush(pal.plankTop);
        g.drawRect(QRectF(r.x() + 0.3, r.y(), r.width() - 0.6, 0.6));
        g.setBrush(pal.plankShade);
        g.drawRect(QRectF(r.x() + 0.3, r.bottom() + 1 - 0.5, r.width() - 0.6, 0.5));
    }
    return QRect(qFloor(r.x() * px) - 1, qFloor(r.y() * px) - 1, qCeil(r.width() * px) + 3,
                 qCeil(r.height() * px) + 3) & ground.rect();
}

QImage paintWater(const QRect &rect, double px, const Palette &pal)
{
    QImage image(qCeil(rect.width() * px), qCeil((rect.height() + 2) * px), QImage::Format_ARGB32_Premultiplied);
    image.fill(Qt::transparent);
    QPainter w(&image);
    w.setRenderHint(QPainter::Antialiasing);
    w.scale(px, px);
    w.translate(0, 2); // the crest rises above the surface
    QLinearGradient deep(0, 0, 0, rect.height());
    deep.setColorAt(0, pal.water);
    deep.setColorAt(1, pal.waterDeep);
    QPainterPath body;
    body.moveTo(0, 0);
    for (double x = 0; x <= rect.width(); x += 6)
        body.quadTo(x + 1.5, -1.6, x + 3, 0), body.quadTo(x + 4.5, 1.2, x + 6, 0);
    body.lineTo(rect.width(), rect.height());
    body.lineTo(0, rect.height());
    body.closeSubpath();
    w.setClipRect(QRectF(0, -2, rect.width(), rect.height() + 2));
    w.fillPath(body, deep);
    QPainterPath crest;
    crest.moveTo(0, 0);
    for (double x = 0; x <= rect.width(); x += 6)
        crest.quadTo(x + 1.5, -1.6, x + 3, 0), crest.quadTo(x + 4.5, 1.2, x + 6, 0);
    w.strokePath(crest, QPen(pal.crest, 1.0, Qt::SolidLine, Qt::RoundCap));
    // A few glints.
    w.setPen(QPen(QColor(255, 255, 255, 90), 0.7, Qt::SolidLine, Qt::RoundCap));
    for (int i = 0; i < rect.width() / 22; ++i) {
        const quint32 h = hash(quint32(i * 53 + rect.x()));
        const double x = i * 22 + (h % 14);
        const double y = 4 + (h >> 8) % qMax(1, rect.height() - 6);
        w.drawLine(QPointF(x, y), QPointF(x + 3, y));
    }
    return image;
}

// ---- Penguins
namespace {

struct Pose {
    bool front = false;
    double tilt = 0;            // degrees, about the feet
    double lift = 0;            // the body raised (+) or sunk (-)
    double flipper = 12;        // side: degrees forward from hanging down
    double left = 20, right = 20; // front: each flipper, degrees out from hanging
    double footA = 0, footB = 0;
    double squash = 1;          // < 1 flattens (a hard landing)
};

void drawFlipper(QPainter &p, const QPointF &pivot, double angle, const Palette &pal, double length = 5.0)
{
    p.save();
    p.translate(pivot);
    p.rotate(angle);
    p.setBrush(pal.body);
    p.setPen(QPen(pal.rim, 0.7));
    p.drawEllipse(QRectF(-1.5, -0.6, 3.0, length));
    p.restore();
}

void drawPenguin(QPainter &p, const Pose &pose, const Palette &pal)
{
    p.save();
    p.translate(kFootX, kGround);
    p.rotate(pose.tilt);
    p.scale(1, pose.squash);
    p.translate(-kFootX, -kGround + -pose.lift);

    const QPen rim(pal.rim, 0.8);
    // Feet first: the body sits on them.
    p.setPen(Qt::NoPen);
    p.setBrush(pal.beak);
    if (pose.front) {
        p.drawEllipse(QPointF(11.4 + pose.footA, 25.2), 2.3, 1.05);
        p.drawEllipse(QPointF(16.6 + pose.footB, 25.2), 2.3, 1.05);
    } else {
        p.drawEllipse(QPointF(12.4 + pose.footA, 25.2), 2.3, 1.05);
        p.drawEllipse(QPointF(15.6 + pose.footB, 25.3), 2.3, 1.05);
    }

    QPainterPath torso, head;
    if (pose.front) {
        torso.addEllipse(QPointF(14, 17.8), 6.2, 7.6);
        head.addEllipse(QPointF(14, 12.0), 4.7, 4.5);
    } else {
        torso.addEllipse(QPointF(13.4, 17.8), 5.5, 7.6);
        head.addEllipse(QPointF(14.6, 12.2), 4.4, 4.3);
    }
    const QPainterPath body = torso.united(head);

    p.setPen(rim);
    p.setBrush(pal.body);
    p.drawPath(body);

    // Belly and face.
    p.save();
    p.setClipPath(body);
    p.setPen(Qt::NoPen);
    p.setBrush(pal.belly);
    if (pose.front) {
        p.drawEllipse(QPointF(14, 19.0), 4.4, 6.0);
        p.drawEllipse(QPointF(12.4, 12.6), 2.1, 2.0);
        p.drawEllipse(QPointF(15.6, 12.6), 2.1, 2.0);
    } else {
        p.drawEllipse(QPointF(15.9, 19.2), 3.4, 5.8);
        p.drawEllipse(QPointF(16.6, 12.4), 2.0, 1.9);
    }
    p.restore();

    p.setPen(Qt::NoPen);
    if (pose.front) {
        p.setBrush(pal.eye);
        p.drawEllipse(QPointF(12.5, 12.2), 0.8, 0.95);
        p.drawEllipse(QPointF(15.5, 12.2), 0.8, 0.95);
        p.setBrush(pal.blush);
        p.drawEllipse(QPointF(11.2, 14.4), 1.0, 0.6);
        p.drawEllipse(QPointF(16.8, 14.4), 1.0, 0.6);
        p.setBrush(pal.beak);
        p.drawPolygon(QPolygonF({QPointF(12.9, 13.5), QPointF(15.1, 13.5), QPointF(14.0, 15.4)}));
        drawFlipper(p, QPointF(8.4, 15.2), pose.left, pal, 5.6);
        drawFlipper(p, QPointF(19.6, 15.2), -pose.right, pal, 5.6);
    } else {
        p.setBrush(pal.eye);
        p.drawEllipse(QPointF(16.9, 11.9), 0.85, 0.95);
        p.setBrush(pal.blush);
        p.drawEllipse(QPointF(16.6, 14.3), 1.0, 0.6);
        p.setBrush(pal.beak);
        p.drawPolygon(QPolygonF({QPointF(18.4, 12.3), QPointF(21.8, 13.3), QPointF(18.4, 14.4)}));
        drawFlipper(p, QPointF(12.4, 15.2), pose.flipper, pal, 5.4);
    }
    p.restore();
}

// Sheet frames.
enum Frame {
    Walk = 0, WalkUmbrella = 4, Fall = 8, Float = 10, Block = 12, Dig = 14, Bash = 18, Build = 22,
    Splat = 24, Drown = 27, Exit = 29
};

void drawUmbrellaOpen(QPainter &p, double sway, const Palette &pal)
{
    p.save();
    p.translate(14, 13);
    p.rotate(sway);
    p.setPen(QPen(pal.rim, 0.8, Qt::SolidLine, Qt::RoundCap));
    p.drawLine(QPointF(0, 0), QPointF(0, -9));
    QPainterPath canopy;
    canopy.moveTo(-10, -8);
    canopy.cubicTo(-9, -15.5, 9, -15.5, 10, -8);
    // Scalloped hem.
    for (int i = 0; i < 4; ++i) {
        const double x0 = 10 - i * 5;
        canopy.quadTo(x0 - 2.5, -10, x0 - 5, -8);
    }
    canopy.closeSubpath();
    p.setPen(QPen(pal.rim, 0.7));
    p.setBrush(pal.skill[int(Skill::Float)]);
    p.drawPath(canopy);
    p.setClipPath(canopy);
    p.setPen(Qt::NoPen);
    p.setBrush(QColor(255, 255, 255, 110));
    p.drawEllipse(QPointF(-4, -11), 1.6, 5);
    p.drawEllipse(QPointF(4, -11), 1.6, 5);
    p.restore();
}

void drawUmbrellaFolded(QPainter &p, const Palette &pal)
{
    p.save();
    p.setPen(QPen(pal.skill[int(Skill::Float)], 1.8, Qt::SolidLine, Qt::RoundCap));
    p.drawLine(QPointF(9.0, 21.5), QPointF(7.6, 10.0));
    p.setPen(QPen(pal.rim, 0.7, Qt::SolidLine, Qt::RoundCap));
    p.drawArc(QRectF(7.3, 20.6, 2.6, 2.6), 180 * 16, 180 * 16);
    p.restore();
}

void drawPickaxe(QPainter &p, double angle, const Palette &pal)
{
    p.save();
    p.translate(13.2, 16.0);
    p.rotate(angle);
    p.setPen(QPen(QColor("#8A5A2B"), 1.1, Qt::SolidLine, Qt::RoundCap));
    p.drawLine(QPointF(0, 0), QPointF(9.5, 0));
    QPainterPath head;
    head.moveTo(9.5, -4.2);
    head.quadTo(11.4, 0, 9.5, 4.2);
    head.quadTo(10.6, 0, 9.5, -4.2);
    p.setPen(QPen(pal.rim, 0.5));
    p.setBrush(pal.skill[int(Skill::Bash)]);
    p.drawPath(head);
    p.restore();
}

void drawShovel(QPainter &p, double drop, const Palette &pal)
{
    p.save();
    p.translate(0, drop);
    p.setPen(QPen(QColor("#8A5A2B"), 1.1, Qt::SolidLine, Qt::RoundCap));
    p.drawLine(QPointF(14, 12.5), QPointF(14, 21));
    p.setPen(QPen(pal.rim, 0.5));
    p.setBrush(pal.skill[int(Skill::Dig)]);
    p.drawRoundedRect(QRectF(12.2, 20.4, 3.6, 4.0), 1.2, 1.2);
    p.restore();
}

void drawPlank(QPainter &p, const QPointF &at, const Palette &pal)
{
    p.save();
    p.setPen(QPen(pal.plankShade, 0.5));
    p.setBrush(pal.plank);
    p.drawRoundedRect(QRectF(at.x(), at.y(), 8, 2), 0.5, 0.5);
    p.restore();
}

void drawChips(QPainter &p, int phase, const QColor &c)
{
    p.save();
    p.setPen(Qt::NoPen);
    p.setBrush(c);
    const double up = phase % 2 ? 3 : 0;
    p.drawEllipse(QPointF(6.5 - up * 0.3, 21 - up), 0.9, 0.9);
    p.drawEllipse(QPointF(21.5 + up * 0.3, 20 - up), 0.8, 0.8);
    p.drawEllipse(QPointF(8.5, 18 - up * 1.4), 0.6, 0.6);
    p.restore();
}

void drawFrame(QPainter &p, int frame, const Palette &pal)
{
    Pose pose;
    if (frame >= Walk && frame < Fall) {
        const int f = (frame - Walk) % 4;
        static const double tilt[4] = {-5, 0, 5, 0};
        static const double flip[4] = {22, 10, -4, 10};
        pose.tilt = tilt[f];
        pose.flipper = flip[f];
        pose.lift = f % 2 ? 0.6 : 0;
        pose.footA = f == 0 ? 1.4 : f == 2 ? -0.8 : 0.3;
        pose.footB = f == 2 ? 1.4 : f == 0 ? -0.8 : 0.3;
        if (frame >= WalkUmbrella)
            drawUmbrellaFolded(p, pal);
        drawPenguin(p, pose, pal);
        return;
    }
    switch (frame) {
    case Fall:
    case Fall + 1:
        pose.flipper = frame == Fall ? 150 : 120;
        pose.footA = -0.6;
        pose.footB = 0.8;
        pose.lift = 0.8;
        drawPenguin(p, pose, pal);
        return;
    case Float:
    case Float + 1: {
        const double sway = frame == Float ? -5 : 5;
        drawUmbrellaOpen(p, sway, pal);
        pose.flipper = 175;
        pose.tilt = sway * 0.4;
        pose.lift = 0.5;
        drawPenguin(p, pose, pal);
        return;
    }
    case Block:
    case Block + 1:
        pose.front = true;
        pose.left = pose.right = frame == Block ? 82 : 96;
        pose.footA = -0.8;
        pose.footB = 0.8;
        drawPenguin(p, pose, pal);
        // A stop band across the chest.
        p.setPen(Qt::NoPen);
        p.setBrush(pal.skill[int(Skill::Block)]);
        p.drawRoundedRect(QRectF(9.6, 16.2, 8.8, 1.8), 0.9, 0.9);
        return;
    case Dig:
    case Dig + 1:
    case Dig + 2:
    case Dig + 3: {
        const int f = frame - Dig;
        pose.front = true;
        pose.lift = f % 2 ? -0.6 : 0;
        pose.left = pose.right = f % 2 ? 6 : 24;
        drawPenguin(p, pose, pal);
        drawShovel(p, f % 2 ? 1.6 : -1.0, pal);
        drawChips(p, f, pal.snow.darker(108));
        return;
    }
    case Bash:
    case Bash + 1:
    case Bash + 2:
    case Bash + 3: {
        static const double swing[4] = {-120, -60, 0, 30};
        const int f = frame - Bash;
        pose.flipper = 80 + swing[f] * 0.4;
        pose.tilt = f >= 2 ? 6 : -3;
        drawPenguin(p, pose, pal);
        drawPickaxe(p, swing[f], pal);
        if (f == 2)
            drawChips(p, 1, pal.snow.darker(108));
        return;
    }
    case Build:
    case Build + 1:
        pose.flipper = frame == Build ? 70 : 40;
        pose.tilt = frame == Build ? 0 : 7;
        drawPenguin(p, pose, pal);
        drawPlank(p, frame == Build ? QPointF(15.5, 14.5) : QPointF(17.0, 23.0), pal);
        return;
    case Splat:
    case Splat + 1: {
        pose.squash = frame == Splat ? 0.5 : 0.28;
        pose.flipper = 90;
        pose.footA = -2;
        pose.footB = 2;
        drawPenguin(p, pose, pal);
        p.setPen(Qt::NoPen);
        p.setBrush(QColor("#F6B94A"));
        for (int i = 0; i < 3; ++i) {
            const QPointF c(9 + i * 5, frame == Splat ? 15 : 13);
            p.drawEllipse(c, 0.9, 0.9);
        }
        return;
    }
    case Splat + 2:
        p.setPen(Qt::NoPen);
        p.setBrush(QColor(255, 255, 255, 220));
        p.drawEllipse(QPointF(10, 22), 3.4, 3.0);
        p.drawEllipse(QPointF(15, 20.5), 4.2, 3.8);
        p.drawEllipse(QPointF(19.5, 22.5), 3.0, 2.6);
        p.setBrush(QColor(255, 255, 255, 140));
        p.drawEllipse(QPointF(13, 16), 1.8, 1.8);
        p.drawEllipse(QPointF(18, 15.5), 1.2, 1.2);
        return;
    case Drown:
    case Drown + 1:
        pose.lift = frame == Drown ? -6 : -10;
        pose.flipper = frame == Drown ? 160 : 130;
        drawPenguin(p, pose, pal);
        p.setPen(Qt::NoPen);
        p.setBrush(pal.crest);
        p.drawEllipse(QPointF(7, frame == Drown ? 18 : 20), 0.9, 0.9);
        p.drawEllipse(QPointF(21, frame == Drown ? 17 : 19), 0.9, 0.9);
        return;
    case Exit:
    case Exit + 1:
        pose.front = true;
        pose.left = 18;
        pose.right = frame == Exit ? 160 : 125;
        drawPenguin(p, pose, pal);
        return;
    default:
        return;
    }
}

} // namespace

void paintFrame(QPainter &p, int frame, const Palette &pal)
{
    drawFrame(p, frame, pal);
}

int cellPixels(double px)
{
    return qCeil(kCell * px);
}

QRect sheetCell(int frame, double px)
{
    const int c = cellPixels(px);
    return QRect((frame % kSheetColumns) * c, (frame / kSheetColumns) * c, c, c);
}

QImage paintSheet(double px, const Palette &pal)
{
    const int c = cellPixels(px);
    const int rows = (2 * kFrames + kSheetColumns - 1) / kSheetColumns;
    QImage sheet(c * kSheetColumns, c * rows, QImage::Format_ARGB32_Premultiplied);
    sheet.fill(Qt::transparent);
    QPainter p(&sheet);
    p.setRenderHint(QPainter::Antialiasing);
    for (int f = 0; f < 2 * kFrames; ++f) {
        const QRect cell = sheetCell(f, px);
        p.save();
        p.setClipRect(cell.adjusted(1, 1, -1, -1));
        p.translate(cell.topLeft());
        p.scale(px, px);
        if (f >= kFrames) {
            p.translate(kCell, 0);
            p.scale(-1, 1);
        }
        drawFrame(p, f % kFrames, pal);
        p.restore();
    }
    return sheet;
}

namespace {

int facing(const Penguin &p, int tick)
{
    switch (p.state) {
    case State::Walking: return (p.floater ? WalkUmbrella : Walk) + ((p.x >> 1) & 3);
    case State::Falling: return Fall + ((tick >> 1) & 1);
    case State::Floating: return Float + ((tick >> 3) & 1);
    case State::Blocking: return Block + ((tick >> 4) & 1);
    case State::Digging: return Dig + ((tick >> 1) & 3);
    case State::Bashing: return Bash + qMin(3, ((p.timer - 1) % kBashPeriod) * 4 / kBashPeriod + ((tick >> 2) & 1));
    case State::Building: return Build + (((p.timer - 1) % kBuildPeriod) * 2 >= kBuildPeriod ? 1 : 0);
    case State::Splatting: return Splat + qMin(2, p.timer * 3 / kSplatTicks);
    case State::Drowning: return Drown + ((p.timer >> 2) & 1);
    case State::Exiting: return Exit + ((p.timer >> 2) & 1);
    case State::Saved:
    case State::Lost: return -1;
    }
    return Walk;
}

} // namespace

int frameFor(const Penguin &p, int tick)
{
    const int f = facing(p, tick);
    // Facing us (blocking, digging, waving at the door): no left or right.
    const bool front = (f >= Block && f < Bash) || f >= Exit;
    return f >= 0 && !front && p.dir < 0 ? f + kFrames : f;
}

int skillFrame(Skill skill)
{
    switch (skill) {
    case Skill::Block: return Block;
    case Skill::Dig: return Dig + 1;
    case Skill::Bash: return Bash + 2;
    case Skill::Build: return Build + 1;
    case Skill::Float: return Float;
    case Skill::Count: break;
    }
    return Walk;
}

// ---- Igloo and hatch

void drawIgloo(QPainter &p, const Palette &pal)
{

    // A pennant on a pole.
    p.setPen(QPen(pal.rim, 0.8, Qt::SolidLine, Qt::RoundCap));
    p.drawLine(QPointF(31, 14), QPointF(31, 1.5));
    p.setPen(Qt::NoPen);
    p.setBrush(pal.flag);
    p.drawPolygon(QPolygonF({QPointF(31.3, 1.5), QPointF(38.5, 4), QPointF(31.3, 6.5)}));

    // The dome, in courses of snow blocks.
    QPainterPath dome;
    dome.addEllipse(QRectF(2, 12, 44, 56));
    QPainterPath ground;
    ground.addRect(QRectF(0, 40, 48, 30));
    dome = dome.subtracted(ground);
    p.setPen(QPen(pal.iglooLine, 0.9));
    p.setBrush(pal.igloo);
    p.drawPath(dome);
    p.save();
    p.setClipPath(dome);
    p.setPen(QPen(pal.iglooLine, 0.6));
    for (int row = 0; row < 4; ++row) {
        const double y = 19 + row * 5.5;
        p.drawLine(QPointF(0, y), QPointF(48, y));
        for (int i = 0; i < 6; ++i) {
            const double x = 4 + i * 8 + (row % 2 ? 4 : 0);
            p.drawLine(QPointF(x, y), QPointF(x, y + 5.5));
        }
    }
    p.restore();

    // The way in.
    QPainterPath arch;
    arch.moveTo(16.5, 40);
    arch.lineTo(16.5, 31);
    arch.arcTo(QRectF(16.5, 24, 15, 14), 180, -180);
    arch.lineTo(31.5, 40);
    arch.closeSubpath();
    p.setPen(QPen(pal.iglooLine, 0.9));
    p.setBrush(pal.igloo.darker(106));
    p.drawPath(arch);
    QPainterPath door;
    door.moveTo(19, 40);
    door.lineTo(19, 32);
    door.arcTo(QRectF(19, 27, 10, 10), 180, -180);
    door.lineTo(29, 40);
    door.closeSubpath();
    p.setPen(Qt::NoPen);
    p.setBrush(pal.door);
    p.drawPath(door);
}

QImage paintIgloo(double px, const Palette &pal)
{
    QImage image(qCeil(kIglooSize.width() * px), qCeil(kIglooSize.height() * px), QImage::Format_ARGB32_Premultiplied);
    image.fill(Qt::transparent);
    QPainter p(&image);
    p.setRenderHint(QPainter::Antialiasing);
    p.scale(px, px);
    drawIgloo(p, pal);
    return image;
}

void drawHatch(QPainter &p, int frame, const Palette &pal)
{
    // The doors under the box: shut, swinging, hanging open.
    const double swing = frame == 0 ? 0 : frame == 1 ? 45 : 82;
    p.setPen(QPen(pal.hatchLine, 0.8));
    p.setBrush(pal.hatchDoor);
    for (int side = 0; side < 2; ++side) {
        p.save();
        p.translate(side ? 34 : 6, 17);
        p.rotate(side ? -swing : swing);
        p.drawRoundedRect(side ? QRectF(-14, -1, 14, 2.4) : QRectF(0, -1, 14, 2.4), 0.8, 0.8);
        p.restore();
    }
    // The box, with a snowflake on its side and snow on its lid.
    p.setPen(QPen(pal.hatchLine, 0.9));
    p.setBrush(pal.hatch);
    p.drawRoundedRect(QRectF(3, 2, 34, 15.5), 3, 3);
    p.setPen(Qt::NoPen);
    p.setBrush(pal.snow);
    p.drawRoundedRect(QRectF(2, 0.6, 36, 4.2), 2, 2);
    p.setPen(QPen(pal.snow, 0.9, Qt::SolidLine, Qt::RoundCap));
    const QPointF c(20, 11);
    for (int i = 0; i < 3; ++i) {
        const double a = qDegreesToRadians(30.0 + i * 60);
        const QPointF d(std::cos(a) * 3.6, std::sin(a) * 3.6);
        p.drawLine(c - d, c + d);
    }
}

QImage paintHatch(double px, const Palette &pal)
{
    const int fw = qCeil(kHatchSize.width() * px);
    QImage image(fw * kHatchFrames, qCeil(kHatchSize.height() * px), QImage::Format_ARGB32_Premultiplied);
    image.fill(Qt::transparent);
    QPainter p(&image);
    p.setRenderHint(QPainter::Antialiasing);
    for (int f = 0; f < kHatchFrames; ++f) {
        p.save();
        p.translate(f * fw, 0);
        p.scale(px, px);
        drawHatch(p, f, pal);
        p.restore();
    }
    return image;
}

} // namespace Penguins
