#include "PenguinSim.h"

#include <QPainter>

#include <cmath>

namespace Penguins {

QString skillKey(Skill skill)
{
    switch (skill) {
    case Skill::Block: return QStringLiteral("block");
    case Skill::Dig: return QStringLiteral("dig");
    case Skill::Bash: return QStringLiteral("bash");
    case Skill::Build: return QStringLiteral("build");
    case Skill::Float: return QStringLiteral("float");
    case Skill::Count: break;
    }
    return {};
}

Skill skillFromKey(const QString &key)
{
    for (int i = 0; i < kSkillCount; ++i) {
        if (skillKey(Skill(i)) == key)
            return Skill(i);
    }
    return Skill::Count;
}

bool Penguin::moving() const
{
    return !gone() && state != State::Blocking;
}

std::vector<quint8> Sim::rasterize(const Level &level)
{
    // Drawn without antialiasing: a cell is set when its centre is inside a
    // shape. A four-point rectangle (x, y, x + w, y + h) covers w × h cells.
    QImage image(level.size, QImage::Format_RGB32);
    image.fill(Qt::black);
    {
        QPainter painter(&image);
        painter.setPen(Qt::NoPen);
        for (const Shape &shape : level.shapes) {
            const int value = shape.kind == Shape::Ground ? int(Cell::Ground)
                            : shape.kind == Shape::Steel ? int(Cell::Steel) : int(Cell::Air);
            painter.setBrush(QColor(value, value, value));
            if (shape.ellipse)
                painter.drawEllipse(QRectF(shape.polygon.boundingRect().topLeft(),
                                           QSizeF(shape.polygon.boundingRect().size()) - QSizeF(1, 1)));
            else
                painter.drawPolygon(shape.polygon);
        }
    }
    std::vector<quint8> cells(size_t(level.size.width()) * size_t(level.size.height()));
    for (int y = 0; y < image.height(); ++y) {
        const auto *line = reinterpret_cast<const QRgb *>(image.constScanLine(y));
        for (int x = 0; x < image.width(); ++x)
            cells[size_t(y) * size_t(image.width()) + size_t(x)] = quint8(qRed(line[x]));
    }
    return cells;
}

void Sim::load(const Level &level)
{
    m_level = level;
    m_w = level.size.width();
    m_h = level.size.height();
    m_cells = rasterize(level);
    m_penguins.clear();
    m_left = level.skills;
    m_edits.clear();
    m_tick = 0;
    m_nextSpawn = kOpenTicks;
    m_saved = 0;
    m_lost = 0;
    m_finished = false;
    ++m_generation;
}

Cell Sim::cell(int x, int y) const
{
    if (x < 0 || x >= m_w)
        return Cell::Steel; // the sides of the world are walls
    if (y < 0 || y >= m_h)
        return Cell::Air;   // open above, and below: falling out of it
    return Cell(m_cells[size_t(y) * size_t(m_w) + size_t(x)]);
}

bool Sim::solid(int x, int y) const
{
    return cell(x, y) != Cell::Air;
}

int Sim::out() const
{
    int n = 0;
    for (const Penguin &p : m_penguins)
        n += p.gone() ? 0 : 1;
    return n;
}

bool Sim::inWater(int x, int y) const
{
    for (const QRect &rect : m_level.water) {
        if (rect.contains(x, y))
            return true;
    }
    return false;
}

void Sim::step()
{
    if (m_finished)
        return;
    for (Penguin &p : m_penguins) {
        p.px = p.x;
        p.py = p.y;
    }
    if (released() < m_level.total && m_tick >= m_nextSpawn) {
        spawn();
        m_nextSpawn = m_tick + m_level.rate;
    }
    for (size_t i = 0; i < m_penguins.size(); ++i)
        update(m_penguins[i]);
    ++m_tick;
    checkFinished();
}

void Sim::spawn()
{
    Penguin p;
    p.id = int(m_penguins.size());
    p.x = p.px = m_level.entrance.x();
    p.y = p.py = m_level.entrance.y();
    p.dir = m_level.entranceDir < 0 ? -1 : 1;
    p.state = State::Falling;
    m_penguins.push_back(p);
}

void Sim::set(Penguin &p, State state)
{
    p.state = state;
    p.timer = 0;
}

void Sim::update(Penguin &p)
{
    ++p.timer;
    switch (p.state) {
    case State::Falling:
        fallStep(p, kFallSpeed);
        break;
    case State::Floating:
        fallStep(p, p.timer % 2 ? 2 : 1);
        break;
    case State::Walking:
        walk(p);
        break;
    case State::Blocking:
        if (!groundBelow(p))
            startFalling(p);
        break;
    case State::Digging:
        dig(p);
        break;
    case State::Bashing:
        bash(p);
        break;
    case State::Building:
        build(p);
        break;
    case State::Exiting:
        if (p.timer >= kExitTicks) {
            set(p, State::Saved);
            ++m_saved;
        }
        break;
    case State::Splatting:
    case State::Drowning:
        if (p.timer >= (p.state == State::Splatting ? kSplatTicks : kDrownTicks)) {
            set(p, State::Lost);
            ++m_lost;
        }
        break;
    case State::Saved:
    case State::Lost:
        break;
    }
}

void Sim::startFalling(Penguin &p)
{
    set(p, State::Falling);
    p.fall = 0;
}

bool Sim::arrived(Penguin &p)
{
    if (p.y >= m_h + kHeight) {
        set(p, State::Lost);
        ++m_lost;
        return true;
    }
    if (inWater(p.x, p.y)) {
        set(p, State::Drowning);
        return true;
    }
    const QPoint door = m_level.exit;
    if (qAbs(p.x - door.x()) <= 3 && p.y >= door.y() - 4 && p.y <= door.y() + 2) {
        set(p, State::Exiting);
        return true;
    }
    return false;
}

void Sim::fallStep(Penguin &p, int px)
{
    for (int i = 0; i < px; ++i) {
        if (groundBelow(p))
            break;
        ++p.y;
        ++p.fall;
        if (arrived(p))
            return;
        if (p.state == State::Falling && p.floater && p.fall >= kFloatOpen) {
            set(p, State::Floating);
            return;
        }
    }
    if (!groundBelow(p))
        return;
    // Landed. A long fall is fatal without an umbrella open.
    const bool fatal = p.state == State::Falling && p.fall > kLethalFall;
    set(p, fatal ? State::Splatting : State::Walking);
    p.fall = 0;
}

void Sim::walk(Penguin &p)
{
    for (const Penguin &b : m_penguins) {
        if (b.state != State::Blocking || b.id == p.id)
            continue;
        const int ahead = (b.x - p.x) * p.dir;
        if (ahead > 0 && ahead <= kBlockReach && qAbs(b.y - p.y) <= kHeight / 2 + 2) {
            p.dir = -p.dir;
            return;
        }
    }
    const int nx = p.x + p.dir;
    if (!solid(nx, p.y)) {
        // Level or downhill: follow the ground down a step, or fall.
        p.x = nx;
        int down = 0;
        while (down < kStepDown && !groundBelow(p)) {
            ++p.y;
            ++down;
        }
        if (arrived(p))
            return;
        if (!groundBelow(p)) {
            startFalling(p);
            p.fall = down;
        }
        return;
    }
    // Uphill: the lowest free row within a step, or it's a wall.
    for (int up = 1; up <= kStepUp; ++up) {
        if (!solid(nx, p.y - up)) {
            p.x = nx;
            p.y -= up;
            arrived(p);
            return;
        }
    }
    p.dir = -p.dir;
}

void Sim::dig(Penguin &p)
{
    if ((p.timer - 1) % kDigPeriod)
        return;
    for (int x = p.x - 1; x <= p.x + 1; ++x) {
        for (int y = p.y + 1; y <= p.y + 2; ++y) {
            if (cell(x, y) == Cell::Steel) {
                set(p, State::Walking);
                return;
            }
        }
    }
    cut(QRect(p.x - kDigHalf, p.y + 1, 2 * kDigHalf + 1, 2));
    for (int i = 0; i < 2; ++i) {
        if (groundBelow(p))
            break;
        ++p.y;
        if (arrived(p))
            return;
    }
    if (!groundBelow(p))
        startFalling(p);
}

void Sim::bash(Penguin &p)
{
    if ((p.timer - 1) % kBashPeriod)
        return;
    // Rock right in front stops it; so does nothing left to bash.
    for (int c = 1; c <= 4; ++c) {
        for (int y = p.y - 12; y <= p.y; ++y) {
            if (cell(p.x + p.dir * c, y) == Cell::Steel) {
                set(p, State::Walking);
                return;
            }
        }
    }
    bool any = false;
    for (int c = 1; c <= kBashLook && !any; ++c) {
        for (int y = p.y - kBashHeight + 1; y < p.y && !any; ++y) {
            const Cell k = cell(p.x + p.dir * c, y);
            any = k == Cell::Ground || k == Cell::Brick;
        }
    }
    if (!any) {
        set(p, State::Walking);
        return;
    }
    const int left = p.dir > 0 ? p.x + 1 : p.x - kBashReach;
    cut(QRect(left, p.y - kBashHeight + 1, kBashReach, kBashHeight));
    for (int i = 0; i < 2; ++i) {
        if (solid(p.x + p.dir, p.y))
            break;
        p.x += p.dir;
        int down = 0;
        while (down < kStepDown && !groundBelow(p)) {
            ++p.y;
            ++down;
        }
        if (arrived(p))
            return;
        if (!groundBelow(p)) {
            startFalling(p);
            p.fall = down;
            return;
        }
    }
}

void Sim::build(Penguin &p)
{
    if ((p.timer - 1) % kBuildPeriod)
        return;
    const int left = p.dir > 0 ? p.x + 1 : p.x - kBrickLength;
    brick(QRect(left, p.y - 1, kBrickLength, 2));
    --p.bricks;
    // Step up onto it, unless something is in the way: then it walks (and
    // the walk climbs onto a ledge or turns at a wall).
    for (int c = 1; c <= 4; ++c) {
        for (int y = p.y - 10; y <= p.y - 2; ++y) {
            if (solid(p.x + p.dir * c, y)) {
                set(p, State::Walking);
                return;
            }
        }
    }
    p.y -= 2;
    p.x += 4 * p.dir;
    if (arrived(p))
        return;
    if (p.bricks <= 0)
        set(p, State::Walking);
}

bool Sim::cut(const QRect &rect)
{
    const QRect r = rect & QRect(0, 0, m_w, m_h);
    bool any = false;
    for (int y = r.top(); y <= r.bottom(); ++y) {
        for (int x = r.left(); x <= r.right(); ++x) {
            quint8 &c = m_cells[size_t(y) * size_t(m_w) + size_t(x)];
            if (c == quint8(Cell::Ground) || c == quint8(Cell::Brick)) {
                c = quint8(Cell::Air);
                any = true;
            }
        }
    }
    if (any)
        m_edits.append({TerrainEdit::Cut, r});
    return any;
}

void Sim::brick(const QRect &rect)
{
    const QRect r = rect & QRect(0, 0, m_w, m_h);
    bool any = false;
    for (int y = r.top(); y <= r.bottom(); ++y) {
        for (int x = r.left(); x <= r.right(); ++x) {
            quint8 &c = m_cells[size_t(y) * size_t(m_w) + size_t(x)];
            if (c == quint8(Cell::Air)) {
                c = quint8(Cell::Brick);
                any = true;
            }
        }
    }
    if (any)
        m_edits.append({TerrainEdit::Brick, r});
}

bool Sim::canTake(const Penguin &p, Skill skill) const
{
    if (m_finished || p.gone() || p.state == State::Exiting || p.state == State::Splatting
        || p.state == State::Drowning)
        return false;
    const bool grounded = p.state == State::Walking || p.state == State::Digging
                       || p.state == State::Bashing || p.state == State::Building;
    switch (skill) {
    case Skill::Float: return !p.floater;
    case Skill::Block: return grounded;
    case Skill::Dig: return grounded && p.state != State::Digging;
    case Skill::Bash: return grounded && p.state != State::Bashing;
    case Skill::Build: return grounded; // again while building: a longer bridge
    case Skill::Count: break;
    }
    return false;
}

bool Sim::assign(Skill skill, int id)
{
    if (skill == Skill::Count || id < 0 || id >= released() || m_left[int(skill)] <= 0)
        return false;
    Penguin &p = m_penguins[size_t(id)];
    if (!canTake(p, skill))
        return false;
    --m_left[int(skill)];
    switch (skill) {
    case Skill::Float:
        p.floater = true;
        break;
    case Skill::Block:
        set(p, State::Blocking);
        break;
    case Skill::Dig:
        set(p, State::Digging);
        break;
    case Skill::Bash:
        set(p, State::Bashing);
        break;
    case Skill::Build:
        set(p, State::Building);
        p.bricks = kBricks;
        break;
    case Skill::Count:
        break;
    }
    return true;
}

int Sim::pick(Skill skill, double x, double y, double radius) const
{
    int best = -1;
    double bestDistance = radius;
    for (const Penguin &p : m_penguins) {
        if (!canTake(p, skill))
            continue;
        const double d = std::hypot(p.x - x, p.y - kHeight / 2.0 - y);
        if (d <= bestDistance) {
            if (best < 0 || d < bestDistance) {
                best = p.id;
                bestDistance = d;
            }
        }
    }
    return best;
}

void Sim::finish()
{
    m_finished = true;
}

void Sim::checkFinished()
{
    if (released() < m_level.total)
        return;
    for (const Penguin &p : m_penguins) {
        if (p.moving())
            return;
    }
    m_finished = true;
}

void Replayer::apply(Sim &sim)
{
    for (int i = 0; i < m_steps.size(); ++i) {
        const Step &s = m_steps[i];
        if (m_done[i] || s.id >= sim.released())
            continue;
        // A penguin's steps go in order: this one waits for its earlier ones.
        bool waiting = false;
        for (int j = 0; j < i && !waiting; ++j)
            waiting = !m_done[j] && m_steps[j].id == s.id;
        if (waiting)
            continue;
        const Penguin &p = sim.penguins()[size_t(s.id)];
        const bool due = s.atTick >= 0 ? sim.tick() >= s.atTick
                                       : (s.atX < 0 || p.x == s.atX) && (s.atY < 0 || p.y >= s.atY);
        if (due && sim.assign(s.skill, s.id)) {
            m_done[i] = true;
            ++m_applied;
        }
    }
}

int replay(Sim &sim, const QList<Step> &steps, int maxTicks)
{
    sim.restart();
    Replayer replayer(steps);
    while (!sim.finished() && sim.tick() < maxTicks) {
        replayer.apply(sim);
        sim.step();
    }
    return replayer.applied();
}

} // namespace Penguins
