#include <QtTest>

#include "games/PenguinLevels.h"
#include "games/PenguinSim.h"

#include <algorithm>

using namespace Penguins;

// Penguin March's rules, on small made-up levels, and every real level won
// by replaying its recorded solution. The simulation alone: no window.
class TestPenguins : public QObject
{
    Q_OBJECT

    // A floor with its top at row 90 (a penguin on it stands at y = 89), one
    // penguin dropping in at x = 20 and no igloo.
    static Level flat(int w = 240, int h = 120)
    {
        Level l;
        l.size = QSize(w, h);
        l.total = 1;
        l.need = 1;
        l.rate = 30;
        l.entrance = QPoint(20, 70);
        l.exit = QPoint(-1000, -1000);
        l.skills.fill(5);
        l.shapes = {rect(0, 90, w, h - 90)};
        return l;
    }

    // Runs until penguin `id` is out and on its feet.
    static void untilWalking(Sim &sim, int id = 0)
    {
        for (int i = 0; i < 400; ++i) {
            if (sim.released() > id && sim.penguins()[size_t(id)].state == State::Walking)
                return;
            sim.step();
        }
        QFAIL("never walked");
    }

    // Runs until penguin `id` is at x (walking), then gives it `skill`.
    static bool assignAt(Sim &sim, int id, Skill skill, int x)
    {
        for (int i = 0; i < 2000; ++i) {
            if (sim.released() > id) {
                const Penguin &p = sim.penguins()[size_t(id)];
                if (p.x == x && p.state == State::Walking)
                    return sim.assign(skill, id);
            }
            sim.step();
        }
        return false;
    }

    static const Penguin &penguin(const Sim &sim, int id = 0) { return sim.penguins()[size_t(id)]; }

private slots:
    void walksStepsUpAndTurnsAtAWall()
    {
        Level l = flat();
        l.shapes << rect(80, 86, 30, 4)    // a step 4 high: climbed
                 << rect(150, 40, 10, 50); // a wall: turned at
        Sim sim(l);
        untilWalking(sim);
        QCOMPARE(penguin(sim).y, 89);
        QCOMPARE(penguin(sim).dir, 1);
        int maxX = 0;
        int yOnStep = -1;
        for (int i = 0; i < 200; ++i) {
            sim.step();
            const Penguin &p = penguin(sim);
            maxX = std::max(maxX, p.x);
            if (p.x == 95)
                yOnStep = p.y;
            QCOMPARE(p.state, State::Walking);
        }
        QCOMPARE(yOnStep, 85);           // on top of the step
        QCOMPARE(maxX, 149);             // up to the wall, never into it
        QCOMPARE(penguin(sim).dir, -1);  // and back
        QVERIFY(penguin(sim).x < 149);

        // The side of the world is a wall too.
        for (int i = 0; i < 400; ++i)
            sim.step();
        QVERIFY(penguin(sim).x >= 0);
    }

    void aLongFallKills()
    {
        Level l = flat();
        l.entrance = QPoint(20, 89 - kLethalFall); // just survivable
        Sim safe(l);
        untilWalking(safe);
        QCOMPARE(penguin(safe).y, 89);

        l.entrance = QPoint(20, 89 - kLethalFall - 3);
        Sim fatal(l);
        fatal.run(200);
        QCOMPARE(penguin(fatal).state, State::Lost);
        QCOMPARE(fatal.lost(), 1);
        QVERIFY(fatal.finished());
        QVERIFY(!fatal.won());

        // Walking off a high ledge is a fall like any other.
        Level ledge = flat(240, 200);
        ledge.shapes = {rect(0, 90, 100, 10), rect(0, 190, 240, 10)};
        Sim off(ledge);
        off.run(400);
        QCOMPARE(penguin(off).state, State::Lost);
    }

    void aFloaterSurvivesTheFall()
    {
        Level l = flat(240, 200);
        l.shapes = {rect(0, 190, 240, 10)};
        l.entrance = QPoint(20, 10);   // 179 px down
        Sim sim(l);
        sim.run(kOpenTicks + 1);
        QCOMPARE(penguin(sim).state, State::Falling);
        sim.run(5);
        QVERIFY(sim.assign(Skill::Float, 0));   // while it falls
        QVERIFY(!sim.assign(Skill::Float, 0));  // only one umbrella
        bool floated = false;
        for (int i = 0; i < 400 && penguin(sim).state != State::Walking; ++i) {
            sim.step();
            floated |= penguin(sim).state == State::Floating;
        }
        QVERIFY(floated);
        QCOMPARE(penguin(sim).state, State::Walking);
        QCOMPARE(penguin(sim).y, 189);
        QCOMPARE(sim.left(Skill::Float), 4);
    }

    void aBlockerTurnsTheOthers()
    {
        Level l = flat();
        l.total = 2;
        l.need = 1;
        Sim sim(l);
        QVERIFY(assignAt(sim, 0, Skill::Block, 100));
        QCOMPARE(penguin(sim, 0).state, State::Blocking);
        int maxX = 0;
        int turns = 0;
        int lastDir = 1;
        for (int i = 0; i < 800; ++i) {
            sim.step();
            if (sim.released() < 2)
                continue;
            const Penguin &p = penguin(sim, 1);
            if (p.state != State::Walking)
                continue;
            maxX = std::max(maxX, p.x);
            if (p.dir != lastDir && p.x > 50)
                ++turns;
            lastDir = p.dir;
        }
        QCOMPARE(maxX, 100 - kBlockReach);  // turned in front of the blocker
        QVERIFY(turns >= 2);                // every time it came back
        QCOMPARE(penguin(sim, 0).x, 100);   // the blocker never moved

        // A blocker stays, so once the rest are home the level is over.
        Level home = flat();
        home.total = 2;
        home.need = 1;
        home.exit = QPoint(100, 89);
        home.entrance = QPoint(60, 70);
        home.entranceDir = -1;
        Sim done(home);
        QVERIFY(assignAt(done, 0, Skill::Block, 50));
        done.run(400);
        QVERIFY(done.finished());
        QVERIFY(done.won());
        QCOMPARE(done.saved(), 1);
    }

    void aDiggerDigsThrough()
    {
        Level l = flat(240, 160);
        l.shapes = {rect(0, 90, 240, 20), rect(0, 140, 240, 20)};
        Sim sim(l);
        QVERIFY(assignAt(sim, 0, Skill::Dig, 60));
        QVERIFY(sim.cell(60, 100) == Cell::Ground);
        for (int i = 0; i < 300 && penguin(sim).y < 139; ++i)
            sim.step();
        untilWalking(sim);
        QCOMPARE(penguin(sim).y, 139);   // through the upper floor, onto the lower
        for (int y = 90; y < 110; ++y) {
            QVERIFY(sim.cell(60 - kDigHalf, y) == Cell::Air);
            QVERIFY(sim.cell(60 + kDigHalf, y) == Cell::Air);
            QVERIFY(sim.cell(60 + kDigHalf + 1, y) == Cell::Ground);
        }
        QVERIFY(!sim.edits().isEmpty());

        // Steel stops it.
        l.shapes << rect(40, 100, 40, 10, Shape::Steel);
        Sim steel(l);
        QVERIFY(assignAt(steel, 0, Skill::Dig, 60));
        steel.run(60);
        QCOMPARE(penguin(steel).state, State::Walking);
        QVERIFY(penguin(steel).y < 100);
        QVERIFY(steel.cell(60, 100) == Cell::Steel);
    }

    void aBasherTunnels()
    {
        Level l = flat();
        l.shapes << rect(100, 40, 30, 50);
        Sim sim(l);
        QVERIFY(assignAt(sim, 0, Skill::Bash, 95));
        int maxX = 0;
        for (int i = 0; i < 300; ++i) {
            sim.step();
            maxX = std::max(maxX, penguin(sim).x);
        }
        QVERIFY(maxX > 140);                           // through the wall
        QCOMPARE(penguin(sim).state, State::Walking);  // and walking on
        QVERIFY(sim.cell(115, 89) == Cell::Air);       // the tunnel
        QVERIFY(sim.cell(115, 89 - kBashHeight + 1) == Cell::Air);
        QVERIFY(sim.cell(115, 89 - kBashHeight - 1) == Cell::Ground); // its roof

        // Steel stops it.
        Level rock = flat();
        rock.shapes << rect(100, 40, 30, 50, Shape::Steel);
        Sim stop(rock);
        QVERIFY(assignAt(stop, 0, Skill::Bash, 90));
        maxX = 0;
        for (int i = 0; i < 300; ++i) {
            stop.step();
            maxX = std::max(maxX, penguin(stop).x);
        }
        QVERIFY(maxX < 100);
        QCOMPARE(penguin(stop).state, State::Walking);
        QCOMPARE(penguin(stop).dir, -1);

        // Nothing to bash: it goes back to walking (and the skill is spent).
        Sim open(flat());
        QVERIFY(assignAt(open, 0, Skill::Bash, 40));
        open.run(5);
        QCOMPARE(penguin(open).state, State::Walking);
        QCOMPARE(open.left(Skill::Bash), 4);
    }

    void aBridgeCanBeWalked()
    {
        // Two floors with a pit between them, out of the bottom of the world.
        Level l = flat();
        l.total = 2;
        l.need = 2;
        l.rate = 60;
        l.shapes = {rect(0, 90, 100, 30), rect(140, 90, 100, 30)};
        l.exit = QPoint(200, 89);
        Sim sim(l);
        QVERIFY(assignAt(sim, 0, Skill::Build, 96));
        QCOMPARE(penguin(sim).bricks, kBricks);
        for (int i = 0; i < 2000 && !sim.finished(); ++i)
            sim.step();
        QVERIFY(sim.finished());
        QCOMPARE(sim.saved(), 2);  // both over the bridge and home
        QVERIFY(sim.won());
        // The bridge: bricks over the pit, rising as they go.
        QVERIFY(sim.cell(110, 84) == Cell::Brick);
        QVERIFY(sim.cell(130, 74) == Cell::Brick);
        int bricks = 0;
        for (const TerrainEdit &e : sim.edits())
            bricks += e.kind == TerrainEdit::Brick ? 1 : 0;
        QCOMPARE(bricks, kBricks);

        // A wall in the way ends the bridge early; the builder walks on.
        Level wall = flat();
        wall.shapes << rect(120, 20, 10, 70);
        Sim short_(wall);
        QVERIFY(assignAt(short_, 0, Skill::Build, 100));
        short_.run(120);
        QVERIFY(penguin(short_).state != State::Building);
        QVERIFY(penguin(short_).x < 120);
    }

    void touchPicksTheNearestThatCanTakeIt()
    {
        Level l = flat(240, 200);
        l.shapes = {rect(0, 190, 240, 10)};
        l.entrance = QPoint(20, 10);
        l.total = 3;
        l.rate = 40;
        Sim sim(l);
        // 0 and 1 on the ground walking, 2 still falling.
        for (int i = 0; i < 2000; ++i) {
            if (sim.released() == 3 && penguin(sim, 2).y > 60)
                break;
            sim.step();
        }
        // (Nobody had an umbrella: 0 and 1 hit the floor too hard.)
        QCOMPARE(penguin(sim, 2).state, State::Falling);
        const Penguin &falling = penguin(sim, 2);
        QCOMPARE(sim.pick(Skill::Float, falling.x + 10, falling.y - 8, 20), 2);
        QCOMPARE(sim.pick(Skill::Dig, falling.x + 10, falling.y - 8, 20), -1); // not in the air
        QCOMPARE(sim.pick(Skill::Float, falling.x + 40, falling.y - 8, 20), -1); // out of reach

        Level two = flat();
        two.total = 2;
        two.rate = 20;
        Sim walkers(two);
        walkers.run(kOpenTicks + 20 + 40);
        const Penguin &a = penguin(walkers, 0);
        const Penguin &b = penguin(walkers, 1);
        QVERIFY(a.x > b.x + 10);
        const double mid = (a.x + b.x) / 2.0;
        QCOMPARE(walkers.pick(Skill::Dig, mid + 2, 81, 40), 0);
        QCOMPARE(walkers.pick(Skill::Dig, mid - 2, 81, 40), 1);
    }

    void levelsAreSound()
    {
        const QList<Level> &all = levels();
        QVERIFY(all.size() >= 12);
        QVERIFY(all.size() <= 20);
        QStringList names;
        for (const Level &l : all) {
            QVERIFY2(!l.name.isEmpty() && !names.contains(l.name), qPrintable(l.name));
            names << l.name;
            QVERIFY2(!l.hint.isEmpty(), qPrintable(l.name));
            QVERIFY2(l.need >= 1 && l.need <= l.total, qPrintable(l.name));
            QCOMPARE(l.size, levels().first().size);
            QVERIFY2(QRect(QPoint(), l.size).contains(l.entrance), qPrintable(l.name));
            Sim sim(l);
            // The igloo stands on the ground.
            QVERIFY2(sim.solid(l.exit.x(), l.exit.y() + 1), qPrintable(l.name));
            QVERIFY2(!sim.solid(l.exit.x(), l.exit.y()), qPrintable(l.name));
            QVERIFY2(!l.solution.isEmpty(), qPrintable(l.name));
        }
    }

    // Like Traffic Jam's solver check: each level's recorded solution wins
    // it, with every step taken as written, and doing nothing doesn't.
    void everyLevelCanBeWon_data()
    {
        QTest::addColumn<int>("index");
        for (int i = 0; i < levels().size(); ++i)
            QTest::newRow(qPrintable(QStringLiteral("%1 %2").arg(i + 1).arg(levels()[i].name))) << i;
    }
    void everyLevelCanBeWon()
    {
        QFETCH(int, index);
        const Level &l = levels()[index];
        Sim sim(l);
        const int applied = replay(sim, l.solution);
        QCOMPARE(applied, l.solution.size());
        QVERIFY2(sim.finished(), "the level ends");
        QVERIFY2(sim.won(), qPrintable(QStringLiteral("saved %1 of %2, needed %3")
                                         .arg(sim.saved()).arg(l.total).arg(l.need)));
        int used[kSkillCount] = {};
        for (const Step &s : l.solution)
            ++used[int(s.skill)];
        for (int k = 0; k < kSkillCount; ++k)
            QVERIFY(used[k] <= l.skills[size_t(k)]);

        Sim idle(l);
        QCOMPARE(replay(idle, {}), 0);
        QVERIFY2(!idle.won(), "it takes skills to win");
    }
};

QTEST_MAIN(TestPenguins)
#include "tst_penguins.moc"
