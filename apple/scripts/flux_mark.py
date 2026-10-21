"""The McFly mark, rasterized in pure Python (no Pillow): the flux
capacitor's Y, three tubes in blue, coral and amber running in to a white
core, each with a soft glow of its own colour, on a dark tile.

The numbers are the display's (display/qml/components/FluxMark.qml), the
apps' (McFly/Theme/FluxMark.swift) and the console's (admin/components/
Brand.tsx), all fractions of the tile's side. A glow is a Gaussian blur of
its shape, as a canvas shadow draws it (the blur given there is twice sigma).
Used by render_app_icon.py and render_launch_mark.py.
"""

import math

TILE_TOP = (0x30, 0x32, 0x3A)
TILE_BOTTOM = (0x12, 0x13, 0x17)
RADIUS = 0.26  # the tile's corners, where a tile is drawn
CENTER_Y = 0.53
ARM_FROM, ARM_TO, ARM_WIDTH = 0.14, 0.36, 0.12
ARM_SIGMA = 0.06
CORE, CORE_SIGMA = 0.075, 0.08
WHITE = (255, 255, 255)
SIN60 = math.sin(math.pi / 3)
# Direction (y down), colour at the outer end, colour at the inner end.
ARMS = (
    ((-SIN60, -0.5), (0x5B, 0x7C, 0xF5), (0xB5, 0xC4, 0xFA)),
    ((SIN60, -0.5), (0xF0, 0x7F, 0x5A), (0xF8, 0xC5, 0xB5)),
    ((0.0, 1.0), (0xF6, 0xB9, 0x4A), (0xFB, 0xE0, 0xAE)),
)


def _blend(c, top, a):
    return [v + (t - v) * a for v, t in zip(c, top)]


def _rounded(px, py, x0, y0, side, r):
    """Coverage of a rounded square at (x0, y0)."""
    half = side / 2
    qx = abs(px - (x0 + half)) - (half - r)
    qy = abs(py - (y0 + half)) - (half - r)
    d = math.hypot(max(qx, 0.0), max(qy, 0.0)) + min(max(qx, qy), 0.0) - r
    return min(1.0, max(0.0, 0.5 - d))


def render(canvas: int, side: float, tile: bool) -> list[list[tuple[float, float, float, float]]]:
    """Rows of (r, g, b, alpha), 0-255 and 0-1, for a `canvas`-pixel square
    with the mark `side` pixels across in its middle. Without a tile the
    mark fills the square edge to edge (an app icon, which the system masks)."""
    x0 = y0 = (canvas - side) / 2
    cx, cy = x0 + side / 2, y0 + side * CENTER_Y
    arms = []
    for (dx, dy), outer, inner in ARMS:
        ax, ay = cx + dx * side * ARM_FROM, cy + dy * side * ARM_FROM
        bx, by = cx + dx * side * ARM_TO, cy + dy * side * ARM_TO
        arms.append((ax, ay, bx, by, outer, inner))
    half = ARM_WIDTH * side / 2
    s_arm = ARM_SIGMA * side * math.sqrt(2)
    core, s_core = CORE * side, CORE_SIGMA * side * math.sqrt(2)
    rows = []
    for y in range(canvas):
        py = y + 0.5
        shade = min(1.0, max(0.0, (py - y0) / side))
        base = [a + (b - a) * shade for a, b in zip(TILE_TOP, TILE_BOTTOM)]
        row = []
        for x in range(canvas):
            px = x + 0.5
            alpha = _rounded(px, py, x0, y0, side, RADIUS * side) if tile else 1.0
            c = base
            for ax, ay, bx, by, outer, inner in arms:
                vx, vy = ax - bx, ay - by
                t = max(0.0, min(1.0, ((px - bx) * vx + (py - by) * vy) / (vx * vx + vy * vy)))
                u = math.hypot(px - (bx + t * vx), py - (by + t * vy)) - half
                if u < 3 * s_arm:
                    c = _blend(c, outer, 0.5 * math.erfc(u / s_arm))
                    cover = min(1.0, max(0.0, 0.5 - u))
                    if cover:
                        c = _blend(c, _blend(outer, inner, t), cover)
            u = math.hypot(px - cx, py - cy) - core
            if u < 3 * s_core:
                c = _blend(c, WHITE, 0.5 * math.erfc(u / s_core))
                c = _blend(c, WHITE, min(1.0, max(0.0, 0.5 - u)))
            row.append((c[0], c[1], c[2], alpha))
        rows.append(row)
    return rows
