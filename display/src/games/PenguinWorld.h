#pragma once

#include "PenguinArt.h"
#include "PenguinSim.h"

#include <QElapsedTimer>
#include <QImage>
#include <QQuickItem>
#include <QQuickPaintedItem>
#include <QSet>
#include <QTimer>
#include <QVariantMap>

// Penguin March's world on screen: a level running in Penguins::Sim, drawn
// at the item's size (the world's shape; QML sizes and pans it).
//
// The terrain is painted once per level and size, at the panel's resolution,
// into tiles of kTile pixels: a dig or a brick repaints its few pixels and
// uploads only the tiles it touched. Penguins are frames of one painted
// sheet. While running, a timer on the 30 fps slots MotionClock keeps steps
// the simulation (kTickMs a tick, more ticks a frame when fast) and draws the
// penguins between ticks. Paused or over, the timer stops and nothing is
// drawn. The sky is the QML behind it.
class PenguinWorld : public QQuickItem
{
    Q_OBJECT
    Q_PROPERTY(int level READ level WRITE setLevel NOTIFY levelChanged)
    Q_PROPERTY(int levelCount READ levelCount CONSTANT)
    // World pixels: every level is this size.
    Q_PROPERTY(QSize worldSize READ worldSize CONSTANT)
    Q_PROPERTY(bool running READ running WRITE setRunning NOTIFY runningChanged)
    // Ticks per kTickMs: 1, or more for fast-forward.
    Q_PROPERTY(int speed READ speed WRITE setSpeed NOTIFY speedChanged)
    // The skill a tap gives ("block", "dig", "bash", "build", "float").
    Q_PROPERTY(QString skill READ skill WRITE setSkill NOTIFY skillChanged)
    Q_PROPERTY(bool dark READ dark WRITE setDark NOTIFY darkChanged)
    // How far from a tap, in item pixels, a penguin can be and still be the
    // one picked: a finger, not a mouse pointer.
    Q_PROPERTY(qreal reach READ reach WRITE setReach NOTIFY reachChanged)
    // Playing the level's recorded solution ("Show me"), from the start.
    Q_PROPERTY(bool demo READ demo NOTIFY levelChanged)

    // Where the penguins drop in, in world pixels (the view starts there).
    Q_PROPERTY(QPoint hatch READ hatch NOTIFY levelChanged)
    // The igloo's door, in world pixels.
    Q_PROPERTY(QPoint igloo READ igloo NOTIFY levelChanged)
    Q_PROPERTY(QString name READ name NOTIFY levelChanged)
    Q_PROPERTY(QString hint READ hint NOTIFY levelChanged)
    Q_PROPERTY(int total READ total NOTIFY levelChanged)
    Q_PROPERTY(int need READ need NOTIFY levelChanged)
    Q_PROPERTY(int released READ released NOTIFY progressChanged)
    Q_PROPERTY(int saved READ saved NOTIFY progressChanged)
    Q_PROPERTY(int lost READ lost NOTIFY progressChanged)
    Q_PROPERTY(int out READ out NOTIFY progressChanged)
    // Skill key → how many are left.
    Q_PROPERTY(QVariantMap skillsLeft READ skillsLeft NOTIFY progressChanged)
    Q_PROPERTY(bool finished READ finished NOTIFY progressChanged)
    Q_PROPERTY(bool won READ won NOTIFY progressChanged)
    Q_PROPERTY(bool started READ started NOTIFY progressChanged)

public:
    explicit PenguinWorld(QQuickItem *parent = nullptr);
    ~PenguinWorld() override;

    static constexpr int kTile = 256;

    int level() const { return m_level; }
    void setLevel(int index);
    int levelCount() const;
    QSize worldSize() const;
    bool running() const { return m_running; }
    void setRunning(bool on);
    int speed() const { return m_speed; }
    void setSpeed(int speed);
    QString skill() const { return m_skill; }
    void setSkill(const QString &skill);
    bool dark() const { return m_dark; }
    void setDark(bool dark);
    qreal reach() const { return m_reach; }
    void setReach(qreal reach);
    bool demo() const { return m_replayer.active(); }

    QPoint hatch() const { return m_sim.level().entrance; }
    QPoint igloo() const { return m_sim.level().exit; }
    QString name() const { return m_sim.level().name; }
    QString hint() const { return m_sim.level().hint; }
    int total() const { return m_sim.level().total; }
    int need() const { return m_sim.level().need; }
    int released() const { return m_sim.released(); }
    int saved() const { return m_sim.saved(); }
    int lost() const { return m_sim.lost(); }
    int out() const { return m_sim.out(); }
    QVariantMap skillsLeft() const;
    bool finished() const { return m_sim.finished(); }
    bool won() const { return m_sim.won(); }
    bool started() const { return m_sim.tick() > 0; }

    // A level's name, hint, total, need and skills (key → count), for the
    // level picker.
    Q_INVOKABLE QVariantMap info(int index) const;
    // The skill's colour, as the penguins wear it.
    Q_INVOKABLE QColor skillColor(const QString &key) const;
    // Gives the chosen skill to the penguin nearest (x, y), item pixels, that
    // can take it, within `reach`. False if none could.
    Q_INVOKABLE bool tapAt(qreal x, qreal y);
    // The level from the start; with `demo`, playing its solution.
    Q_INVOKABLE void restart(bool demo = false);
    // Ends the level now (the Finish button, once enough are home).
    Q_INVOKABLE void finish();

    // ---- For tests: run ticks now, give a skill by penguin, see them.
    Q_INVOKABLE void advance(int ticks);
    Q_INVOKABLE bool give(const QString &skill, int id);
    Q_INVOKABLE int ticks() const { return m_sim.tick(); }
    // Each penguin: id, x, y (item pixels, the middle of its body), state.
    Q_INVOKABLE QVariantList penguins() const;

signals:
    void levelChanged();
    void runningChanged();
    void speedChanged();
    void skillChanged();
    void darkChanged();
    void reachChanged();
    void progressChanged();
    // A tap gave `skill` to a penguin at (x, y), item pixels.
    void assigned(const QString &skill, qreal x, qreal y);

protected:
    QSGNode *updatePaintNode(QSGNode *old, UpdatePaintNodeData *) override;
    void updatePolish() override;
    void geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) override;
    void itemChange(ItemChange change, const ItemChangeData &value) override;

private:
    void frame();
    void arm();
    void stepOnce();
    void loaded();
    // Paints new terrain edits onto the ground layer, marking its tiles.
    void paintEdits();
    void notify();
    double scale() const; // item pixels per world pixel

    Penguins::Sim m_sim;
    Penguins::Replayer m_replayer;
    int m_level = 0;
    bool m_running = false;
    int m_speed = 1;
    QString m_skill;
    bool m_dark = false;
    qreal m_reach = 72;

    QTimer m_timer;
    QElapsedTimer m_clock;
    qint64 m_last = 0;
    double m_carry = 0;   // ms of simulation owed
    double m_alpha = 1;   // how far between the last two ticks to draw

    // Pictures (GUI thread), uploaded in updatePaintNode.
    QImage m_ground, m_rock, m_sheet, m_igloo, m_hatch;
    QList<QImage> m_water;
    double m_px = 0;      // device pixels per world pixel they were painted at
    double m_dpr = 1;
    bool m_paintedDark = false;
    int m_paintedGeneration = -1;
    int m_edits = 0;      // edits painted onto m_ground
    int m_pictures = 0;   // bumped when they're all painted anew
    QSet<int> m_dirtyTiles;

    struct Counts {
        int released = -1, saved = -1, lost = -1, out = -1, ticks = 0;
        std::array<int, Penguins::kSkillCount> left{};
        bool finished = false;
        bool operator==(const Counts &o) const
        {
            return released == o.released && saved == o.saved && lost == o.lost && out == o.out
                && left == o.left && finished == o.finished && (ticks > 0) == (o.ticks > 0);
        }
    } m_counts;
};

// A penguin doing one skill (or the igloo, or the hatch), as the world draws
// it: for the skill buttons and the game's card. `kind` is a skill key,
// "walk", "igloo" or "hatch".
class PenguinPicture : public QQuickPaintedItem
{
    Q_OBJECT
    Q_PROPERTY(QString kind READ kind WRITE setKind NOTIFY kindChanged)
    Q_PROPERTY(bool dark READ dark WRITE setDark NOTIFY darkChanged)
    Q_PROPERTY(bool mirror READ mirror WRITE setMirror NOTIFY mirrorChanged)
public:
    explicit PenguinPicture(QQuickItem *parent = nullptr);
    QString kind() const { return m_kind; }
    void setKind(const QString &kind);
    bool dark() const { return m_dark; }
    void setDark(bool dark);
    bool mirror() const { return m_mirror; }
    void setMirror(bool mirror);
    void paint(QPainter *painter) override;

signals:
    void kindChanged();
    void darkChanged();
    void mirrorChanged();

private:
    QString m_kind = QStringLiteral("walk");
    bool m_dark = false;
    bool m_mirror = false;
};
