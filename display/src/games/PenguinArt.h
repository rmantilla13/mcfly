#pragma once

#include "PenguinSim.h"

#include <QColor>
#include <QImage>

class QPainter;

// Penguin March's pictures, painted with QPainter at the size they're shown:
// the terrain (two layers: ground, which digging cuts, and rock, which it
// never does), the penguins (a sheet of frames), the hatch, the igloo and
// the water. All of it is our own drawing. `px` is device pixels per world
// pixel throughout.
namespace Penguins {

struct Palette {
    QColor iceTop, iceBottom, snow, iceShade, speck;
    QColor rock, rockTop, rockShade;
    QColor plank, plankTop, plankShade;
    QColor body, rim, belly, beak, eye, blush;
    QColor water, waterDeep, crest;
    QColor igloo, iglooLine, door, flag;
    QColor hatch, hatchLine, hatchDoor;
    std::array<QColor, kSkillCount> skill;
};
// Daylight, or the night scene for dark mode (the penguins keep a light rim
// so they read on a dark sky).
Palette palette(bool dark);

// ---- Terrain
// Paints a level's terrain as it starts. Both images are the world's size
// times px, transparent where there is nothing.
void paintTerrain(const Level &level, double px, const Palette &pal, QImage &ground, QImage &rock);
// Paints one change (a cut or a brick) onto the ground layer; returns the
// pixels it touched.
QRect paintEdit(QImage &ground, const TerrainEdit &edit, double px, const Palette &pal);
QImage paintWater(const QRect &rect, double px, const Palette &pal);

// ---- Penguins: a sheet of frames, kSheetColumns across, each a cell of
// kCell × kCell world pixels with the feet at (kFootX, kGround). The sheet
// holds every frame facing right, then all of them again facing left (drawn
// mirrored: a mirrored image node isn't, on every renderer).
constexpr int kCell = 28;
constexpr double kFootX = 14;
constexpr double kGround = 26;
constexpr int kSheetColumns = 8;
constexpr int kFrames = 31;
QImage paintSheet(double px, const Palette &pal);
// The cell of `frame` (0 .. 2 × kFrames) in a sheet painted at px.
QRect sheetCell(int frame, double px);
int cellPixels(double px);
// The frame to show for a penguin, facing its way; -1 for none.
int frameFor(const Penguin &p, int tick);
// For the skill buttons: a picture of each skill (a frame of the sheet).
int skillFrame(Skill skill);
// One frame, drawn in its cell's world pixels (0..kCell): for pictures of
// a penguin outside the world (the skill buttons, the game's card).
void paintFrame(QPainter &p, int frame, const Palette &pal);

// ---- The igloo (the way home) and the hatch they drop from.
// Sizes in world pixels; the igloo's door, and the hatch's drop point, at
// the anchor.
constexpr QSize kIglooSize{48, 40};
constexpr QPointF kIglooAnchor{24, 40};
constexpr QSize kHatchSize{40, 30};
constexpr QPointF kHatchAnchor{20, 18};
constexpr int kHatchFrames = 3;
QImage paintIgloo(double px, const Palette &pal);
void drawIgloo(QPainter &p, const Palette &pal);
// kHatchFrames frames side by side: shut, opening, open.
QImage paintHatch(double px, const Palette &pal);
void drawHatch(QPainter &p, int frame, const Palette &pal);

} // namespace Penguins
