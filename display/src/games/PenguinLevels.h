#pragma once

#include "PenguinSim.h"

#include <initializer_list>

// Penguin March's levels, made for McFly: each brings in one skill, then
// they're combined. Every level carries a recorded solution, replayed by
// tests/tst_penguins.cpp to prove it can be won.
namespace Penguins {

const QList<Level> &levels();

// Shapes for writing levels, in world pixels.
Shape rect(int x, int y, int w, int h, Shape::Kind kind = Shape::Ground);
Shape poly(std::initializer_list<QPoint> points, Shape::Kind kind = Shape::Ground);
Shape ellipse(int x, int y, int w, int h, Shape::Kind kind = Shape::Ground);

} // namespace Penguins
