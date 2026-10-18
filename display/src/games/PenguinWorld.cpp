#include "PenguinWorld.h"

#include "PenguinLevels.h"

#include <QDateTime>
#include <QPainter>
#include <QQuickWindow>
#include <QSGImageNode>
#include <QSGNode>
#include <QSGTexture>

#include <cmath>
#include <memory>
#include <vector>

using namespace Penguins;

namespace {

constexpr int kFps = 30;          // Theme.motionFps: the slots MotionClock keeps
constexpr int kMostTicksAFrame = 8;

const char *stateKey(State s)
{
    switch (s) {
    case State::Falling: return "falling";
    case State::Floating: return "floating";
    case State::Walking: return "walking";
    case State::Blocking: return "blocking";
    case State::Digging: return "digging";
    case State::Bashing: return "bashing";
    case State::Building: return "building";
    case State::Exiting: return "exiting";
    case State::Splatting: return "splatting";
    case State::Drowning: return "drowning";
    case State::Saved: return "saved";
    case State::Lost: return "lost";
    }
    return "";
}

// The world in the scene graph. It owns the textures its image nodes show,
// so they go with it, on the render thread.
class WorldNode : public QSGNode
{
public:
    WorldNode()
    {
        for (QSGNode *layer : {tiles, rockLayer, iglooLayer, penguins, hatchLayer, water})
            appendChildNode(layer);
    }

    int pictures = -1;
    // Layers, back to front. Nodes are deleted by their parents; the
    // textures, which no node owns, by these. The layers are (identity)
    // transform nodes: the software renderer places a node added later from
    // its parent's cached transform, and caches none for a plain QSGNode.
    QSGTransformNode *tiles = new QSGTransformNode;
    QSGTransformNode *rockLayer = new QSGTransformNode;
    QSGTransformNode *iglooLayer = new QSGTransformNode;
    QSGTransformNode *penguins = new QSGTransformNode;
    QSGTransformNode *hatchLayer = new QSGTransformNode;
    QSGTransformNode *water = new QSGTransformNode;
    std::vector<QSGImageNode *> tileNodes, penguinNodes, waterNodes;
    QSGImageNode *rock = nullptr, *igloo = nullptr, *hatch = nullptr;
    std::vector<std::unique_ptr<QSGTexture>> tileTextures, waterTextures;
    std::unique_ptr<QSGTexture> rockTexture, iglooTexture, hatchTexture, sheetTexture;

    // An image node showing `texture`. The texture is set before the node
    // joins the tree: the software renderer reads it as soon as it does.
    static QSGImageNode *image(QQuickWindow *window, QSGTexture *texture)
    {
        QSGImageNode *node = window->createImageNode();
        node->setFiltering(QSGTexture::Linear);
        node->setOwnsTexture(false);
        node->setTexture(texture);
        return node;
    }

    // `count` nodes in `parent` showing `texture`, made or dropped as needed.
    static void resize(std::vector<QSGImageNode *> &nodes, QSGNode *parent, size_t count, QQuickWindow *window,
                       QSGTexture *texture)
    {
        while (nodes.size() > count) {
            parent->removeChildNode(nodes.back());
            delete nodes.back();
            nodes.pop_back();
        }
        while (nodes.size() < count) {
            nodes.push_back(image(window, texture));
            nodes.back()->setSourceRect(QRectF(QPointF(), texture->textureSize()));
            parent->appendChildNode(nodes.back());
        }
    }
};

} // namespace

PenguinWorld::PenguinWorld(QQuickItem *parent) : QQuickItem(parent)
{
    setFlag(ItemHasContents);
    m_timer.setSingleShot(true);
    m_timer.setTimerType(Qt::PreciseTimer);
    connect(&m_timer, &QTimer::timeout, this, &PenguinWorld::frame);
    m_clock.start();
    if (!levels().isEmpty())
        m_sim.load(levels().first());
    notify();
}

PenguinWorld::~PenguinWorld() = default;

int PenguinWorld::levelCount() const
{
    return int(levels().size());
}

QSize PenguinWorld::worldSize() const
{
    return levels().isEmpty() ? Level().size : levels().first().size;
}

double PenguinWorld::scale() const
{
    return m_sim.width() > 0 ? width() / m_sim.width() : 0;
}

void PenguinWorld::setLevel(int index)
{
    if (levels().isEmpty())
        return;
    index = qBound(0, index, levelCount() - 1);
    m_level = index;
    m_replayer = Replayer();
    m_sim.load(levels()[index]);
    loaded();
}

void PenguinWorld::restart(bool demo)
{
    m_replayer = demo ? Replayer(m_sim.level().solution) : Replayer();
    m_sim.restart();
    loaded();
}

void PenguinWorld::loaded()
{
    m_edits = 0;
    m_carry = 0;
    m_alpha = 1;
    polish();
    update();
    emit levelChanged();
    notify();
    if (m_running) {
        m_last = m_clock.elapsed();
        arm();
    }
}

void PenguinWorld::finish()
{
    m_sim.finish();
    m_timer.stop();
    notify();
    update();
}

void PenguinWorld::setRunning(bool on)
{
    if (m_running == on)
        return;
    m_running = on;
    if (on && !m_sim.finished()) {
        m_last = m_clock.elapsed();
        arm();
    } else {
        m_timer.stop();
    }
    emit runningChanged();
}

void PenguinWorld::setSpeed(int speed)
{
    speed = qBound(1, speed, 8);
    if (m_speed == speed)
        return;
    m_speed = speed;
    emit speedChanged();
}

void PenguinWorld::setSkill(const QString &skill)
{
    if (m_skill == skill)
        return;
    m_skill = skill;
    emit skillChanged();
}

void PenguinWorld::setDark(bool dark)
{
    if (m_dark == dark)
        return;
    m_dark = dark;
    polish();
    emit darkChanged();
}

void PenguinWorld::setReach(qreal reach)
{
    if (qFuzzyCompare(m_reach, reach))
        return;
    m_reach = reach;
    emit reachChanged();
}

QVariantMap PenguinWorld::skillsLeft() const
{
    QVariantMap left;
    for (int k = 0; k < kSkillCount; ++k)
        left.insert(skillKey(Skill(k)), m_sim.left(Skill(k)));
    return left;
}

QVariantMap PenguinWorld::info(int index) const
{
    if (index < 0 || index >= levelCount())
        return {};
    const Level &l = levels()[index];
    QVariantMap skills;
    for (int k = 0; k < kSkillCount; ++k)
        skills.insert(skillKey(Skill(k)), l.skills[size_t(k)]);
    return {{QStringLiteral("name"), l.name}, {QStringLiteral("hint"), l.hint},
            {QStringLiteral("total"), l.total}, {QStringLiteral("need"), l.need},
            {QStringLiteral("skills"), skills}};
}

QColor PenguinWorld::skillColor(const QString &key) const
{
    const Skill k = skillFromKey(key);
    return k == Skill::Count ? QColor() : palette(false).skill[size_t(k)];
}

bool PenguinWorld::tapAt(qreal x, qreal y)
{
    const Skill k = skillFromKey(m_skill);
    const double s = scale();
    if (k == Skill::Count || s <= 0 || m_sim.finished() || demo())
        return false;
    const int id = m_sim.pick(k, x / s, y / s, m_reach / s);
    if (id < 0 || !m_sim.assign(k, id))
        return false;
    const Penguin &p = m_sim.penguins()[size_t(id)];
    emit assigned(m_skill, (p.x + 0.5) * s, (p.y + 1 - kHeight / 2.0) * s);
    notify();
    update();
    return true;
}

void PenguinWorld::advance(int ticks)
{
    for (int i = 0; i < ticks && !m_sim.finished(); ++i)
        stepOnce();
    paintEdits();
    notify();
    update();
}

bool PenguinWorld::give(const QString &skill, int id)
{
    const bool ok = m_sim.assign(skillFromKey(skill), id);
    notify();
    update();
    return ok;
}

QVariantList PenguinWorld::penguins() const
{
    const double s = scale();
    QVariantList list;
    for (const Penguin &p : m_sim.penguins()) {
        list.append(QVariantMap{{QStringLiteral("id"), p.id},
                                {QStringLiteral("x"), (p.x + 0.5) * s},
                                {QStringLiteral("y"), (p.y + 1 - kHeight / 2.0) * s},
                                {QStringLiteral("state"), QString::fromLatin1(stateKey(p.state))}});
    }
    return list;
}

// ---- Running

void PenguinWorld::arm()
{
    // On the wall clock's 1/30 s slots, as MotionClock does, so this and any
    // other motion on screen land on the same frames.
    const double slot = 1000.0 / kFps;
    const double now = double(QDateTime::currentMSecsSinceEpoch());
    m_timer.start(qMax(1, int(std::ceil(slot - std::fmod(now, slot)))));
}

void PenguinWorld::stepOnce()
{
    if (m_replayer.active())
        m_replayer.apply(m_sim);
    m_sim.step();
}

void PenguinWorld::frame()
{
    const qint64 now = m_clock.elapsed();
    // A stall (a busy moment, a debugger) is not made up for past 100 ms.
    const qint64 dt = qBound<qint64>(0, now - m_last, qint64(100));
    m_last = now;
    m_carry += double(dt) * m_speed;
    int n = 0;
    while (m_carry >= kTickMs && !m_sim.finished()) {
        stepOnce();
        m_carry -= kTickMs;
        if (++n >= kMostTicksAFrame) {
            m_carry = 0;
            break;
        }
    }
    m_alpha = m_sim.finished() ? 1.0 : qBound(0.0, m_carry / kTickMs, 1.0);
    paintEdits();
    notify();
    update();
    if (m_running && !m_sim.finished())
        arm();
}

void PenguinWorld::notify()
{
    Counts c;
    c.released = m_sim.released();
    c.saved = m_sim.saved();
    c.lost = m_sim.lost();
    c.out = m_sim.out();
    c.ticks = m_sim.tick();
    for (int k = 0; k < kSkillCount; ++k)
        c.left[size_t(k)] = m_sim.left(Skill(k));
    c.finished = m_sim.finished();
    if (c == m_counts)
        return;
    m_counts = c;
    emit progressChanged();
}

// ---- Drawing

void PenguinWorld::geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry)
{
    QQuickItem::geometryChange(newGeometry, oldGeometry);
    if (newGeometry.size() != oldGeometry.size())
        polish();
}

void PenguinWorld::itemChange(ItemChange change, const ItemChangeData &value)
{
    QQuickItem::itemChange(change, value);
    if (change == ItemSceneChange || change == ItemDevicePixelRatioHasChanged)
        polish();
}

void PenguinWorld::updatePolish()
{
    if (!window() || width() <= 0 || height() <= 0 || m_sim.width() <= 0)
        return;
    const double dpr = window()->effectiveDevicePixelRatio();
    const double px = scale() * dpr;
    if (!m_ground.isNull() && qFuzzyCompare(px, m_px) && m_dark == m_paintedDark
        && m_sim.generation() == m_paintedGeneration)
        return;
    m_px = px;
    m_dpr = dpr;
    m_paintedDark = m_dark;
    m_paintedGeneration = m_sim.generation();
    const Palette pal = palette(m_dark);
    paintTerrain(m_sim.level(), px, pal, m_ground, m_rock);
    m_edits = 0;
    paintEdits();
    m_sheet = paintSheet(px, pal);
    m_igloo = paintIgloo(px, pal);
    m_hatch = paintHatch(px, pal);
    m_water.clear();
    for (const QRect &w : m_sim.level().water)
        m_water.append(paintWater(w, px, pal));
    m_dirtyTiles.clear();
    const int cols = (m_ground.width() + kTile - 1) / kTile;
    const int rows = (m_ground.height() + kTile - 1) / kTile;
    for (int t = 0; t < cols * rows; ++t)
        m_dirtyTiles.insert(t);
    ++m_pictures;
    update();
}

void PenguinWorld::paintEdits()
{
    if (m_ground.isNull() || m_paintedGeneration != m_sim.generation())
        return;
    const QList<TerrainEdit> &edits = m_sim.edits();
    if (m_edits >= edits.size())
        return;
    const Palette pal = palette(m_paintedDark);
    const int cols = (m_ground.width() + kTile - 1) / kTile;
    for (; m_edits < edits.size(); ++m_edits) {
        const QRect r = paintEdit(m_ground, edits[m_edits], m_px, pal);
        if (r.isEmpty())
            continue;
        for (int ty = r.top() / kTile; ty <= r.bottom() / kTile; ++ty) {
            for (int tx = r.left() / kTile; tx <= r.right() / kTile; ++tx)
                m_dirtyTiles.insert(ty * cols + tx);
        }
    }
}

QSGNode *PenguinWorld::updatePaintNode(QSGNode *old, UpdatePaintNodeData *)
{
    auto *n = static_cast<WorldNode *>(old);
    QQuickWindow *w = window();
    if (m_ground.isNull() || !w || width() <= 0) {
        delete n;
        return nullptr;
    }
    if (!n)
        n = new WorldNode;
    const double d = m_dpr;
    const double s = scale();
    auto inItem = [d](const QRectF &r) { return QRectF(r.x() / d, r.y() / d, r.width() / d, r.height() / d); };
    auto texture = [w](const QImage &image) { return std::unique_ptr<QSGTexture>(w->createTextureFromImage(image)); };
    // Where a picture with its anchor at a world point goes, in item pixels.
    auto placed = [&](const QImage &image, const QPointF &anchor, double wx, double wy) {
        return QRectF((wx - anchor.x()) * s, (wy - anchor.y()) * s, image.width() / d, image.height() / d);
    };

    const int cols = (m_ground.width() + kTile - 1) / kTile;
    const int rows = (m_ground.height() + kTile - 1) / kTile;
    if (n->pictures != m_pictures) {
        // Everything painted anew (a level, a size, dark or light): new
        // textures, set on each node before it joins the tree.
        n->pictures = m_pictures;
        n->tiles->removeAllChildNodes();
        qDeleteAll(n->tileNodes);
        n->tileNodes.clear();
        n->tileTextures.clear();
        for (int t = 0; t < cols * rows; ++t) {
            const QRect r = QRect((t % cols) * kTile, (t / cols) * kTile, kTile, kTile) & m_ground.rect();
            n->tileTextures.push_back(texture(m_ground.copy(r)));
            QSGImageNode *node = WorldNode::image(w, n->tileTextures.back().get());
            node->setSourceRect(QRectF(0, 0, r.width(), r.height()));
            node->setRect(inItem(r));
            n->tiles->appendChildNode(node);
            n->tileNodes.push_back(node);
        }
        m_dirtyTiles.clear();

        auto single = [&](QSGImageNode *&node, QSGNode *layer, std::unique_ptr<QSGTexture> &owned, const QImage &image) {
            auto fresh = texture(image);
            if (!node) {
                node = WorldNode::image(w, fresh.get());
                layer->appendChildNode(node);
            } else {
                node->setTexture(fresh.get());
            }
            owned = std::move(fresh);
            node->setSourceRect(QRectF(image.rect()));
        };
        single(n->rock, n->rockLayer, n->rockTexture, m_rock);
        n->rock->setRect(inItem(m_rock.rect()));
        const QPoint door = m_sim.level().exit;
        single(n->igloo, n->iglooLayer, n->iglooTexture, m_igloo);
        n->igloo->setRect(placed(m_igloo, kIglooAnchor, door.x() + 0.5, door.y() + 1));
        single(n->hatch, n->hatchLayer, n->hatchTexture, m_hatch);

        auto sheet = texture(m_sheet);
        for (QSGImageNode *p : n->penguinNodes)
            p->setTexture(sheet.get());
        n->sheetTexture = std::move(sheet);

        n->water->removeAllChildNodes();
        qDeleteAll(n->waterNodes);
        n->waterNodes.clear();
        n->waterTextures.clear();
        for (int i = 0; i < m_water.size(); ++i) {
            n->waterTextures.push_back(texture(m_water[i]));
            QSGImageNode *node = WorldNode::image(w, n->waterTextures.back().get());
            node->setSourceRect(QRectF(m_water[i].rect()));
            const QRect r = m_sim.level().water[i];
            node->setRect(QRectF(r.x() * s, (r.y() - 2) * s, m_water[i].width() / d, m_water[i].height() / d));
            n->water->appendChildNode(node);
            n->waterNodes.push_back(node);
        }
    }

    for (int t : std::as_const(m_dirtyTiles)) {
        if (t < 0 || t >= int(n->tileNodes.size()))
            continue;
        const QRect r = QRect((t % cols) * kTile, (t / cols) * kTile, kTile, kTile) & m_ground.rect();
        auto tex = texture(m_ground.copy(r));
        n->tileNodes[size_t(t)]->setTexture(tex.get());
        n->tileTextures[size_t(t)] = std::move(tex);
    }
    m_dirtyTiles.clear();

    // The hatch: shut, opening, open.
    const QPoint entrance = m_sim.level().entrance;
    const double open = m_sim.hatchOpen();
    const int hatchFrame = open <= 0 ? 0 : open < 1 ? 1 : 2;
    const int fw = m_hatch.width() / kHatchFrames;
    n->hatch->setSourceRect(QRectF(hatchFrame * fw, 0, fw, m_hatch.height()));
    n->hatch->setRect(QRectF((entrance.x() + 0.5 - kHatchAnchor.x()) * s, (entrance.y() + 1 - kHatchAnchor.y()) * s,
                             fw / d, m_hatch.height() / d));

    // The penguins, between their last two ticks.
    std::vector<const Penguin *> shown;
    for (const Penguin &p : m_sim.penguins()) {
        if (!p.gone())
            shown.push_back(&p);
    }
    WorldNode::resize(n->penguinNodes, n->penguins, shown.size(), w, n->sheetTexture.get());
    const double cell = cellPixels(m_px) / d;
    for (size_t i = 0; i < shown.size(); ++i) {
        const Penguin &p = *shown[i];
        const int f = frameFor(p, m_sim.tick());
        const double x = p.px + (p.x - p.px) * m_alpha + 0.5;
        const double y = p.py + (p.y - p.py) * m_alpha + 1;
        // Going in at the door, it gets smaller.
        const double size = p.state == State::Exiting
            ? cell * (1 - 0.6 * qMin(1.0, (p.timer + m_alpha) / kExitTicks)) : cell;
        const double k = size / cell;
        QSGImageNode *node = n->penguinNodes[i];
        node->setSourceRect(QRectF(sheetCell(f, m_px)));
        node->setRect(QRectF(x * s - kFootX * s * k, y * s - kGround * s * k, size, size));
    }
    return n;
}

// ---- PenguinPicture

PenguinPicture::PenguinPicture(QQuickItem *parent) : QQuickPaintedItem(parent)
{
    setAntialiasing(true);
}

void PenguinPicture::setKind(const QString &kind)
{
    if (m_kind == kind)
        return;
    m_kind = kind;
    update();
    emit kindChanged();
}

void PenguinPicture::setDark(bool dark)
{
    if (m_dark == dark)
        return;
    m_dark = dark;
    update();
    emit darkChanged();
}

void PenguinPicture::setMirror(bool mirror)
{
    if (m_mirror == mirror)
        return;
    m_mirror = mirror;
    update();
    emit mirrorChanged();
}

void PenguinPicture::paint(QPainter *painter)
{
    const Palette pal = palette(m_dark);
    const QSizeF box = m_kind == QLatin1String("igloo") ? QSizeF(kIglooSize)
                     : m_kind == QLatin1String("hatch") ? QSizeF(kHatchSize) : QSizeF(kCell, kCell);
    const double k = qMin(width() / box.width(), height() / box.height());
    if (k <= 0)
        return;
    painter->setRenderHint(QPainter::Antialiasing);
    painter->translate((width() - box.width() * k) / 2, (height() - box.height() * k) / 2);
    painter->scale(k, k);
    if (m_mirror) {
        painter->translate(box.width(), 0);
        painter->scale(-1, 1);
    }
    if (m_kind == QLatin1String("igloo")) {
        drawIgloo(*painter, pal);
    } else if (m_kind == QLatin1String("hatch")) {
        drawHatch(*painter, 2, pal);
    } else {
        const Skill skill = skillFromKey(m_kind);
        paintFrame(*painter, skill == Skill::Count ? 1 : skillFrame(skill), pal);
    }
}
