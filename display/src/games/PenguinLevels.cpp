#include "PenguinLevels.h"

namespace Penguins {

Shape rect(int x, int y, int w, int h, Shape::Kind kind)
{
    Shape s;
    s.kind = kind;
    s.polygon = QPolygon({QPoint(x, y), QPoint(x + w, y), QPoint(x + w, y + h), QPoint(x, y + h)});
    return s;
}

Shape poly(std::initializer_list<QPoint> points, Shape::Kind kind)
{
    Shape s;
    s.kind = kind;
    s.polygon = QPolygon(QList<QPoint>(points));
    return s;
}

Shape ellipse(int x, int y, int w, int h, Shape::Kind kind)
{
    Shape s = rect(x, y, w, h, kind);
    s.ellipse = true;
    return s;
}

namespace {

using S = Skill;

Step at(int id, Skill skill, int x, int y = -1)
{
    Step s;
    s.id = id;
    s.skill = skill;
    s.atX = x;
    s.atY = y;
    return s;
}

Level base(const QString &name, const QString &hint, int total, int need)
{
    Level l;
    l.name = name;
    l.hint = hint;
    l.total = total;
    l.need = need;
    return l;
}

QList<Level> make()
{
    QList<Level> all;

    // 1. Dig: out of a pen through its floor.
    {
        Level l = base(QStringLiteral("Straight Down"),
                       QStringLiteral("Diggers dig straight down through snow and ice. Tap Dig, then tap a penguin."),
                       10, 8);
        l.entrance = QPoint(70, 32);
        l.exit = QPoint(320, 139);
        l.skills[int(S::Dig)] = 2;
        l.shapes = {rect(20, 70, 200, 20), rect(20, 40, 10, 30), rect(210, 40, 10, 30),
                    rect(0, 140, 400, 44), ellipse(60, 132, 70, 20), ellipse(250, 134, 40, 14)};
        l.solution = {at(0, S::Dig, 120)};
        all << l;
    }
    // 2. Float: off a cliff too high to survive.
    {
        Level l = base(QStringLiteral("Umbrellas Up"),
                       QStringLiteral("A fall this long needs an umbrella. Give each penguin Float before it steps off."),
                       6, 5);
        l.rate = 50;
        l.entrance = QPoint(40, 36);
        l.exit = QPoint(330, 167);
        l.skills[int(S::Float)] = 6;
        l.shapes = {rect(0, 64, 150, 120), poly({{150, 64}, {158, 80}, {150, 184}}), rect(150, 168, 250, 16),
                    ellipse(250, 160, 50, 16)};
        for (int i = 0; i < 6; ++i)
            l.solution << at(i, S::Float, 100);
        all << l;
    }
    // 3. Block: they're walking the wrong way.
    {
        Level l = base(QStringLiteral("Hold the Line"),
                       QStringLiteral("A blocker stands still and turns the others around. These are headed for the water."),
                       10, 9);
        l.rate = 35;
        l.entrance = QPoint(200, 44);
        l.exit = QPoint(60, 103);
        l.skills[int(S::Block)] = 2;
        l.shapes = {rect(0, 104, 270, 80), poly({{270, 104}, {276, 120}, {270, 184}})};
        l.water = {QRect(270, 150, 130, 34)};
        l.solution = {at(0, S::Block, 250)};
        all << l;
    }
    // 4. Build: a bridge over water.
    {
        Level l = base(QStringLiteral("Mind the Gap"),
                       QStringLiteral("Builders lay a bridge of steps ahead of them. Start one at the edge."), 10, 9);
        l.entrance = QPoint(50, 44);
        l.exit = QPoint(340, 103);
        l.skills[int(S::Build)] = 2;
        l.shapes = {rect(0, 104, 150, 80), rect(190, 104, 210, 80)};
        l.water = {QRect(150, 150, 40, 34)};
        l.solution = {at(0, S::Build, 145)};
        all << l;
    }
    // 5. Bash: through a wall.
    {
        Level l = base(QStringLiteral("Break Through"),
                       QStringLiteral("Bashers punch a tunnel straight through a wall."), 10, 9);
        l.entrance = QPoint(60, 60);
        l.exit = QPoint(330, 119);
        l.skills[int(S::Bash)] = 2;
        l.shapes = {rect(0, 120, 400, 64), poly({{170, 120}, {174, 40}, {206, 36}, {210, 120}})};
        l.solution = {at(0, S::Bash, 165)};
        all << l;
    }
    // 6. Build twice: a cliff higher than one bridge.
    {
        Level l = base(QStringLiteral("Upstairs"),
                       QStringLiteral("One bridge won't reach the top. Give the builder Build again before it's done."),
                       10, 9);
        l.entrance = QPoint(40, 80);
        l.exit = QPoint(340, 95);
        l.skills[int(S::Build)] = 3;
        l.shapes = {rect(0, 140, 400, 44), rect(180, 96, 220, 44)};
        l.solution = {at(0, S::Build, 90), at(0, S::Build, 134)};
        all << l;
    }
    // 7. Block and dig: rock everywhere but one patch, behind them.
    {
        Level l = base(QStringLiteral("About Turn"),
                       QStringLiteral("Grey rock can't be dug. Turn them back, then dig through the ice."), 10, 8);
        l.rate = 25;
        l.entrance = QPoint(250, 50);
        l.exit = QPoint(50, 159);
        l.skills[int(S::Block)] = 1;
        l.skills[int(S::Dig)] = 1;
        l.shapes = {rect(0, 90, 300, 24, Shape::Steel), rect(100, 90, 40, 24), rect(0, 160, 300, 24),
                    poly({{300, 160}, {306, 172}, {300, 184}})};
        l.water = {QRect(300, 150, 100, 34)};
        l.solution = {at(0, S::Block, 285), at(1, S::Dig, 120)};
        all << l;
    }
    // 8. Bash, then build.
    {
        Level l = base(QStringLiteral("Tunnel and Bridge"),
                       QStringLiteral("Through the wall, then over the water."), 10, 9);
        l.entrance = QPoint(40, 60);
        l.exit = QPoint(350, 119);
        l.skills[int(S::Bash)] = 1;
        l.skills[int(S::Build)] = 1;
        l.shapes = {rect(0, 120, 230, 64), rect(110, 40, 30, 80), rect(270, 120, 130, 64)};
        l.water = {QRect(230, 150, 40, 34)};
        l.solution = {at(0, S::Bash, 105), at(0, S::Build, 226)};
        all << l;
    }
    // 9. Dig, then bash: down out of a pen, out of a cellar.
    {
        Level l = base(QStringLiteral("Down and Out"),
                       QStringLiteral("Down through the floor, then out through the ice. Rock stops a basher too."), 10, 9);
        l.entrance = QPoint(80, 34);
        l.exit = QPoint(340, 139);
        l.skills[int(S::Dig)] = 2;
        l.skills[int(S::Bash)] = 2;
        l.shapes = {rect(0, 100, 400, 84, Shape::Steel), rect(0, 60, 30, 40, Shape::Steel),
                    rect(170, 60, 90, 40, Shape::Steel), rect(20, 24, 10, 36, Shape::Steel),
                    rect(170, 24, 10, 36, Shape::Steel), rect(30, 80, 140, 20),
                    rect(30, 100, 190, 40, Shape::Cut), rect(220, 100, 40, 40), rect(260, 50, 140, 90, Shape::Cut),
                    ellipse(300, 132, 40, 16)};
        l.solution = {at(0, S::Dig, 100), at(0, S::Bash, 215)};
        all << l;
    }
    // 10. Float, then build: down to an island, over to the shore.
    {
        Level l = base(QStringLiteral("Island Hop"),
                       QStringLiteral("Umbrellas down to the island, then a bridge to the shore."), 8, 6);
        l.entrance = QPoint(40, 24);
        l.exit = QPoint(350, 149);
        l.skills[int(S::Float)] = 8;
        l.skills[int(S::Build)] = 2;
        l.shapes = {rect(0, 50, 110, 134), poly({{110, 50}, {116, 64}, {110, 184}}), ellipse(112, 146, 60, 20),
                    rect(116, 150, 54, 34), rect(210, 150, 190, 34), ellipse(280, 142, 50, 16)};
        l.water = {QRect(170, 156, 40, 28)};
        for (int i = 0; i < 8; ++i)
            l.solution << at(i, S::Float, 80);
        l.solution << at(0, S::Build, 165);
        all << l;
    }
    // 11. Two bridges: one over water, one up onto a ledge.
    {
        Level l = base(QStringLiteral("Two Bridges"),
                       QStringLiteral("Over the water, then up to the ledge. One builder can do both."), 10, 9);
        l.entrance = QPoint(40, 60);
        l.exit = QPoint(360, 95);
        l.skills[int(S::Build)] = 3;
        l.shapes = {rect(0, 120, 140, 64), rect(180, 120, 220, 64), rect(290, 96, 110, 24),
                    ellipse(60, 114, 40, 12)};
        l.water = {QRect(140, 156, 40, 28)};
        l.solution = {at(0, S::Build, 136), at(0, S::Build, 240)};
        all << l;
    }
    // 12. Float, then bash: off a cliff into a walled basin.
    {
        Level l = base(QStringLiteral("Over the Edge"),
                       QStringLiteral("Umbrellas for the drop, then a way through the wall."), 8, 7);
        l.entrance = QPoint(40, 30);
        l.exit = QPoint(345, 159);
        l.skills[int(S::Float)] = 8;
        l.skills[int(S::Bash)] = 2;
        l.shapes = {rect(0, 56, 120, 128), rect(120, 160, 280, 24), poly({{230, 160}, {236, 64}, {262, 70}, {260, 160}}),
                    rect(0, 56, 120, 128), ellipse(150, 152, 50, 16)};
        for (int i = 0; i < 8; ++i)
            l.solution << at(i, S::Float, 100);
        l.solution << at(0, S::Bash, 225);
        all << l;
    }
    // 13. Dig, dig, bash.
    {
        Level l = base(QStringLiteral("Deep Freeze"),
                       QStringLiteral("Two floors down and one wall across."), 10, 8);
        l.entrance = QPoint(60, 30);
        l.exit = QPoint(370, 169);
        l.skills[int(S::Dig)] = 2;
        l.skills[int(S::Bash)] = 1;
        l.shapes = {rect(0, 60, 200, 20), rect(200, 20, 20, 60, Shape::Steel), rect(0, 120, 300, 20),
                    rect(220, 80, 20, 40, Shape::Steel), rect(0, 170, 400, 14), rect(300, 100, 30, 70),
                    ellipse(140, 164, 50, 12)};
        l.solution = {at(0, S::Dig, 100), at(0, S::Dig, 150), at(0, S::Bash, 295)};
        all << l;
    }
    // 14. Block, build, dig.
    {
        Level l = base(QStringLiteral("Crossroads"),
                       QStringLiteral("Turn them, bridge the pit, and dig down to the igloo."), 10, 8);
        l.entrance = QPoint(300, 40);
        l.exit = QPoint(40, 159);
        l.skills[int(S::Block)] = 1;
        l.skills[int(S::Build)] = 1;
        l.skills[int(S::Dig)] = 1;
        l.shapes = {rect(0, 90, 180, 30), rect(215, 90, 125, 30, Shape::Steel), rect(170, 120, 10, 40, Shape::Steel),
                    rect(0, 160, 180, 24), rect(180, 150, 35, 34, Shape::Steel),
                    poly({{340, 90}, {346, 104}, {340, 120}}, Shape::Steel)};
        l.water = {QRect(181, 140, 33, 10), QRect(340, 150, 60, 34)};
        l.solution = {at(0, S::Block, 325), at(1, S::Build, 219), at(1, S::Dig, 80)};
        all << l;
    }
    // 15. Dig, bash, float: out of the ice cap, out of the cave, down the cliff.
    {
        Level l = base(QStringLiteral("The Glacier"),
                       QStringLiteral("Down through the ice cap, out of the cave, and umbrellas for the long way down."),
                       8, 6);
        l.entrance = QPoint(60, 18);
        l.exit = QPoint(360, 175);
        l.skills[int(S::Dig)] = 1;
        l.skills[int(S::Bash)] = 1;
        l.skills[int(S::Float)] = 8;
        l.shapes = {rect(20, 30, 180, 20), rect(10, 6, 10, 44, Shape::Steel), rect(200, 6, 10, 44, Shape::Steel),
                    rect(0, 100, 280, 20, Shape::Steel), rect(0, 120, 280, 64, Shape::Steel),
                    rect(250, 50, 30, 50), poly({{280, 100}, {286, 112}, {280, 184}}, Shape::Steel),
                    rect(280, 176, 120, 8), ellipse(300, 170, 40, 12)};
        l.solution = {at(0, S::Dig, 110), at(0, S::Bash, 245)};
        for (int i = 0; i < 8; ++i)
            l.solution << at(i, S::Float, 278);
        all << l;
    }
    // 16. Everything: turn them, tunnel, bridge, and dig down to the igloo.
    {
        Level l = base(QStringLiteral("Grand March"),
                       QStringLiteral("All the way home: turn them, tunnel, bridge, and dig."), 12, 10);
        l.rate = 30;
        l.entrance = QPoint(220, 26);
        l.exit = QPoint(360, 175);
        l.skills[int(S::Block)] = 1;
        l.skills[int(S::Dig)] = 1;
        l.skills[int(S::Bash)] = 1;
        l.skills[int(S::Build)] = 1;
        l.skills[int(S::Float)] = 2;
        l.shapes = {rect(120, 52, 160, 20), poly({{280, 52}, {286, 62}, {280, 72}}), rect(0, 110, 240, 20),
                    rect(180, 72, 20, 38), rect(280, 110, 120, 20), rect(280, 176, 120, 8),
                    rect(0, 130, 240, 54, Shape::Steel), rect(270, 130, 10, 54, Shape::Steel)};
        l.water = {QRect(240, 160, 30, 24)};
        l.solution = {at(0, S::Block, 265), at(1, S::Bash, 175, 109), at(1, S::Build, 236), at(1, S::Dig, 320)};
        all << l;
    }
    return all;
}

} // namespace

const QList<Level> &levels()
{
    static const QList<Level> all = make();
    return all;
}

} // namespace Penguins
