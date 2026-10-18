#pragma once

#include <QList>
#include <QPoint>
#include <QPolygon>
#include <QRect>
#include <QSize>
#include <QString>

#include <array>
#include <vector>

// Penguin March's rules: penguins drop from a hatch, walk, turn at walls and
// fall; a fall that is too long is the end of one. Each can be given a skill.
// A level is won by getting enough of them into the igloo.
//
// The world is a grid of world pixels (a penguin is 16 tall) and runs on a
// fixed tick of kTickMs. Everything is whole numbers and nothing is random,
// so a level plays the same way every time from the same assignments: a
// level's recorded solution replays exactly (tests/tst_penguins.cpp).
//
// A penguin's position is its foot: the lowest row of its body. The ground
// it stands on is the row below (y + 1).
namespace Penguins {

constexpr int kTickMs = 50;          // 20 ticks a second
constexpr int kHeight = 16;          // a penguin, foot to crown
constexpr int kStepUp = 4;           // the highest step a walker climbs
constexpr int kStepDown = 4;         // the deepest step it walks down; more is a fall
constexpr int kFallSpeed = 3;        // px a tick
constexpr int kLethalFall = 72;      // more than this, without an umbrella, is fatal
constexpr int kFloatOpen = 12;       // px of falling before the umbrella opens
constexpr int kBlockReach = 7;       // a walker this close to a blocker turns
constexpr int kDigPeriod = 3;        // ticks a stroke
constexpr int kDigHalf = 5;          // a hole 11 wide
constexpr int kBashPeriod = 3;
constexpr int kBashReach = 8;        // cleared ahead of the foot each stroke
constexpr int kBashHeight = 16;      // the tunnel: a penguin tall
constexpr int kBashLook = 16;        // nothing to bash this far ahead: stop
constexpr int kBuildPeriod = 6;
constexpr int kBricks = 12;          // a bridge: 12 steps, 2 up and 4 along each
constexpr int kBrickLength = 8;
constexpr int kExitTicks = 10;
constexpr int kSplatTicks = 14;
constexpr int kDrownTicks = 16;
constexpr int kOpenTicks = 20;       // the hatch opening, before the first penguin

enum class Cell : quint8 { Air, Ground, Steel, Brick };

enum class Skill { Block, Dig, Bash, Build, Float, Count };
constexpr int kSkillCount = int(Skill::Count);
// "block", "dig", "bash", "build", "float": the names QML and the levels use.
QString skillKey(Skill skill);
Skill skillFromKey(const QString &key); // Skill::Count if unknown

enum class State {
    Falling, Floating, Walking, Blocking, Digging, Bashing, Building,
    Exiting, Splatting, Drowning, Saved, Lost
};

struct Penguin {
    int id = 0;
    int x = 0, y = 0;
    int px = 0, py = 0;     // where it was a tick ago, for drawing in between
    int dir = 1;            // 1 right, -1 left
    State state = State::Falling;
    int timer = 0;          // ticks in this state
    int fall = 0;           // px fallen so far in this fall
    int bricks = 0;         // left to lay
    bool floater = false;   // has an umbrella
    bool gone() const { return state == State::Saved || state == State::Lost; }
    // Still on its way somewhere: everything but a blocker, the gone and the going.
    bool moving() const;
};

// A level's terrain is drawn from shapes, in order: ground (diggable snow and
// ice), steel (rock nothing digs) and cuts (back to air).
struct Shape {
    enum Kind { Ground, Steel, Cut };
    Kind kind = Ground;
    QPolygon polygon;       // a rectangle is a four-point polygon
    bool ellipse = false;   // the polygon's bounding box as an ellipse
};

// One assignment of a recorded solution: give `skill` to penguin `id` the
// first tick it can take it at x == atX (any x if -1) and, if atY is set, at
// y >= atY; or at tick atTick if that is set instead. A penguin's steps are
// taken in the order they're listed.
struct Step {
    int id = 0;
    Skill skill = Skill::Dig;
    int atX = -1;
    int atY = -1;
    int atTick = -1;
};

struct Level {
    QString name;
    QString hint;           // what's new in it, a sentence
    QSize size{400, 184};
    int total = 10;         // penguins
    int need = 10;          // to win
    int rate = 40;          // ticks between penguins
    QPoint entrance;        // where they drop in (a foot point)
    int entranceDir = 1;
    QPoint exit;            // a foot point in the doorway
    std::array<int, kSkillCount> skills{};
    QList<Shape> shapes;
    QList<QRect> water;
    QList<Step> solution;
};

// A change to the terrain since the level started, for the view to draw:
// a hole cut (dig, bash) or a brick laid.
struct TerrainEdit {
    enum Kind { Cut, Brick };
    Kind kind;
    QRect rect;
};

class Sim
{
public:
    Sim() = default;
    explicit Sim(const Level &level) { load(level); }

    void load(const Level &level);
    void restart() { load(m_level); }
    // One tick. Nothing happens once the level is over.
    void step();
    void run(int ticks) { for (int i = 0; i < ticks && !m_finished; ++i) step(); }

    // Gives `skill` to penguin `id` if it can take it now and any are left.
    bool assign(Skill skill, int id);
    // The penguin nearest (x, y) that can take `skill`, within `radius`
    // (world px, measured to the middle of its body), or -1.
    int pick(Skill skill, double x, double y, double radius) const;
    bool canTake(const Penguin &p, Skill skill) const;
    // Ends the level now (the Finish button once enough are home): the ones
    // still out don't count.
    void finish();

    const Level &level() const { return m_level; }
    const std::vector<Penguin> &penguins() const { return m_penguins; }
    int tick() const { return m_tick; }
    int released() const { return int(m_penguins.size()); }
    int saved() const { return m_saved; }
    int lost() const { return m_lost; }
    int out() const;        // in the level now: released, not saved or lost
    int left(Skill skill) const { return m_left[int(skill)]; }
    bool finished() const { return m_finished; }
    bool won() const { return m_finished && m_saved >= m_level.need; }
    // The hatch: 0 shut .. 1 open.
    double hatchOpen() const { return qMin(1.0, m_tick / double(kOpenTicks)); }

    Cell cell(int x, int y) const;
    bool solid(int x, int y) const;
    int width() const { return m_w; }
    int height() const { return m_h; }
    // The terrain as it started, a byte a cell (tests, drawing).
    static std::vector<quint8> rasterize(const Level &level);
    // Every change to the terrain so far, in order; edits() grows by append
    // only, so a view can keep its place in it.
    const QList<TerrainEdit> &edits() const { return m_edits; }
    // Bumped by load(): the view starts its terrain over.
    int generation() const { return m_generation; }

private:
    void spawn();
    void update(Penguin &p);
    void fallStep(Penguin &p, int px);
    void walk(Penguin &p);
    void dig(Penguin &p);
    void bash(Penguin &p);
    void build(Penguin &p);
    // After a move: the igloo, the water, the bottom of the world.
    bool arrived(Penguin &p);
    bool groundBelow(const Penguin &p) const { return solid(p.x, p.y + 1); }
    void startFalling(Penguin &p);
    void set(Penguin &p, State state);
    // Clears ground and bricks (never steel) in `rect`; true if it cleared any.
    bool cut(const QRect &rect);
    void brick(const QRect &rect);
    bool inWater(int x, int y) const;
    void checkFinished();

    Level m_level;
    int m_w = 0, m_h = 0;
    std::vector<quint8> m_cells;
    std::vector<Penguin> m_penguins;
    std::array<int, kSkillCount> m_left{};
    QList<TerrainEdit> m_edits;
    int m_tick = 0;
    int m_nextSpawn = 0;
    int m_saved = 0;
    int m_lost = 0;
    bool m_finished = false;
    int m_generation = 0;
};

// Plays recorded steps into a running level: each is applied the first tick
// its penguin can take it.
class Replayer
{
public:
    explicit Replayer(const QList<Step> &steps = {}) : m_steps(steps), m_done(steps.size(), false) {}
    // Applies the steps that are due now (call before each Sim::step()).
    void apply(Sim &sim);
    int applied() const { return m_applied; }
    bool active() const { return !m_steps.isEmpty(); }

private:
    QList<Step> m_steps;
    QList<bool> m_done;
    int m_applied = 0;
};

// Replays steps from the start of the level to its end (or `maxTicks`).
// Returns how many were applied; the sim is left where the level ended.
int replay(Sim &sim, const QList<Step> &steps, int maxTicks = 20 * 60 * 10);

} // namespace Penguins
