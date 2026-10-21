#!/usr/bin/env python3
"""Regenerate display/deploy/boot/boot.mp4, the clip the Pi plays from boot
until the app takes the screen.

The McFly mark, on black: the flux capacitor's Y, three glass tubes in blue,
coral and amber in a dark housing, over the McFly wordmark in Exo 2 Black
Italic. Only the mark moves. Light runs in along the tubes twice a second
while the charge builds for four seconds; then the core flashes, the window
fills with light, and the mark settles back to where it started.

The player stops the clip at any frame and may loop it for up to a minute
while Wi-Fi joins, so there is no intro: every frame shows the whole mark,
and the last frame runs into the first without a seam. Nothing outside the
mark's window changes from frame to frame, and everything around the mark
and the wordmark is exactly black, which mcfly-bootscreen also pads with
and the app fades in from. A fixed dither keeps the glows from banding.
Silent, 1920x1200, 24 fps, H.264 tagged BT.709.

The housing and its lights are the splash of the logo study (option C,
"Flux"); the small mark the display, the apps and the console draw is the
same Y without the housing's window (display/qml/components/FluxMark.qml).

Needs Python 3.10+, numpy and ffmpeg (with libx264 and drawtext). The font
is display/resources/fonts/Exo2-BlackItalic.ttf (SIL OFL 1.1), or set
MCFLY_BOOT_FONT. Writes boot.mp4 next to this script, or to the path given.
The installer ships that mp4; you do not need to run this on the Pi.
"""

from __future__ import annotations

import math
import os
import shutil
import subprocess
import sys

import numpy as np

W, H = 1920, 1200
FPS = 24
DURATION = 6  # seconds; every motion repeats a whole number of times in it
FRAMES = FPS * DURATION


def hex_color(h: str) -> np.ndarray:
    return np.array([int(h[i:i + 2], 16) for i in (1, 3, 5)], np.float32)


CANVAS = hex_color("#000000")
WHITE = hex_color("#FFFFFF")
WORD_INK = hex_color("#F4F4F5")  # the dark palette's text
# The mark's three colours: the day glow in display/qml/Theme.qml, fixed so
# the logo never follows the time of day.
BLUE = hex_color("#5B7CF5")
CORAL = hex_color("#F07F5A")
AMBER = hex_color("#F6B94A")

# The housing: S across, centred on (CX, CY). With the wordmark under it the
# pair sits in the middle of the frame.
S = 430.0
CX, CY = 960.0, 478.0
RADIUS = 0.22 * S
BODY_TOP, BODY_BOTTOM = hex_color("#30323A"), hex_color("#16171B")
WINDOW_INSET = 0.07 * S
WINDOW_FILL = hex_color("#0D0E11")
TUBE = hex_color("#1F2128")
HUB = hex_color("#24262D")
SCREW = hex_color("#3A3D46")
BULB_OFF = hex_color("#2A2D35")
# The Y: unit directions (y down) and colours, 120 degrees apart.
ARMS = (
    ((-math.sin(math.pi / 3), -0.5), BLUE),
    ((math.sin(math.pi / 3), -0.5), CORAL),
    ((0.0, 1.0), AMBER),
)
BULBS = 6  # along each tube, from 0.335 S out to 0.135 S in
CHASE = 0.5  # seconds for the light to run the length of a tube
FLASH = 4.2  # seconds into the loop when the core flashes
REST = 0.32  # how lit the tubes are between charges

WORD = "McFly"
WORD_SIZE = 176
WORD_CY = 886.0  # middle of the wordmark's ink


def find_font() -> str:
    here = os.path.dirname(os.path.abspath(__file__))
    candidates = [
        os.environ.get("MCFLY_BOOT_FONT"),
        os.path.join(here, "..", "..", "resources", "fonts", "Exo2-BlackItalic.ttf"),
    ]
    for path in candidates:
        if path and os.path.isfile(path):
            return os.path.normpath(path)
    sys.exit("Exo 2 Black Italic was not found. Set MCFLY_BOOT_FONT to Exo2-BlackItalic.ttf.")


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


class Box:
    """A rectangle of the frame, with the centres of its pixels."""

    def __init__(self, x0: float, y0: float, x1: float, y1: float):
        x0, y0 = max(0, math.floor(x0)), max(0, math.floor(y0))
        x1, y1 = min(W, math.ceil(x1)), min(H, math.ceil(y1))
        self.x0, self.y0 = x0, y0
        self.slice = (slice(y0, y1), slice(x0, x1))
        self.x = np.arange(x0, x1, dtype=np.float32)[None, :] + 0.5
        self.y = np.arange(y0, y1, dtype=np.float32)[:, None] + 0.5

    def inner(self, x0: float, y0: float, x1: float, y1: float) -> tuple[slice, slice, np.ndarray, np.ndarray]:
        """A part of this box: its slice of the box's arrays, and its pixel centres."""
        h, w = self.y.shape[0], self.x.shape[1]
        a = min(max(0, math.floor(x0) - self.x0), w)
        b = min(max(0, math.ceil(x1) - self.x0), w)
        c = min(max(0, math.floor(y0) - self.y0), h)
        d = min(max(0, math.ceil(y1) - self.y0), h)
        return (slice(c, d), slice(a, b)), self.x[:, a:b], self.y[c:d, :]


def blend(region: np.ndarray, color, alpha: np.ndarray) -> None:
    region += (color - region) * alpha[..., None]


def add(region: np.ndarray, light: np.ndarray) -> None:
    np.minimum(region + light, 255.0, out=region)


def rounded_rect(x, y, left, top, size, radius) -> np.ndarray:
    """Signed distance to a rounded square: negative inside."""
    half = size / 2
    qx = np.abs(x - (left + half)) - (half - radius)
    qy = np.abs(y - (top + half)) - (half - radius)
    outside = np.hypot(np.maximum(qx, 0.0), np.maximum(qy, 0.0))
    return outside + np.minimum(np.maximum(qx, qy), 0.0) - radius


def cover(distance: np.ndarray) -> np.ndarray:
    """Pixel coverage from a signed distance."""
    return np.clip(0.5 - distance, 0.0, 1.0)


def segment(x, y, ax, ay, bx, by) -> np.ndarray:
    vx, vy = bx - ax, by - ay
    t = np.clip(((x - ax) * vx + (y - ay) * vy) / (vx * vx + vy * vy), 0.0, 1.0)
    return np.hypot(x - (ax + t * vx), y - (ay + t * vy))


def glow(distance: np.ndarray, radius: float) -> np.ndarray:
    """A soft spot, as the logo study draws one: 1, 0.6, 0.16, 0 at 0, 0.22, 0.55 and 1 of its radius."""
    return np.interp(distance / radius, (0.0, 0.22, 0.55, 1.0), (1.0, 0.6, 0.16, 0.0)).astype(np.float32)


def render_word(font: str) -> np.ndarray:
    """The wordmark's coverage (0-1), cropped to its ink, from ffmpeg's drawtext."""
    tw, th = 1400, 500
    graph = (
        f"drawtext=fontfile='{font}':text='{WORD}':fontsize={WORD_SIZE}:"
        "fontcolor=white:x=(w-text_w)/2:y=(h-text_h)/2"
    )
    raw = subprocess.check_output(
        [
            "ffmpeg", "-hide_banner", "-loglevel", "error",
            "-f", "lavfi", "-i", f"color=c=black:s={tw}x{th}",
            "-vf", graph, "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "gray", "-",
        ]
    )
    mask = np.frombuffer(raw, np.uint8).reshape(th, tw)
    rows = np.flatnonzero(mask.any(axis=1))
    cols = np.flatnonzero(mask.any(axis=0))
    if rows.size == 0:
        sys.exit("ffmpeg drew no text; check that it was built with drawtext (libfreetype).")
    return mask[rows[0]:rows[-1] + 1, cols[0]:cols[-1] + 1].astype(np.float32) / 255.0


def beat(t: float) -> tuple[float, float, float, float]:
    """The charge at t: how lit the tubes are, where the running light is
    (0 at the outer bulb, 1 back round to it), the core's brightness and the
    flash. All of them are back where they started at the end of the loop."""
    t = t % DURATION
    if t < FLASH:
        level = REST + (1.0 - REST) * float(smoothstep(0.0, FLASH, t)) ** 1.4
    else:
        level = 1.0 - (1.0 - REST) * float(smoothstep(FLASH + 0.05, 5.7, t))
    since = t - FLASH
    flash = math.exp(-since / 0.35) * (1.0 - float(smoothstep(5.2, 5.9, t))) if since >= 0 else 0.0
    chase = (t / CHASE) % 1.0
    return level, chase, 0.35 + 0.5 * level + flash, flash


class Scene:
    def __init__(self, font: str):
        self.base = np.empty((H, W, 3), np.float32)
        self.base[:] = CANVAS
        # One fixed dither pattern (triangular, +-1 level) against banding
        # in the glows. Fixed, so it costs the encoder little; it fades out
        # where the frame is black, so that stays exactly black.
        rng = np.random.default_rng(1985)
        self.dither = rng.random((H, W, 1), np.float32) - rng.random((H, W, 1), np.float32)

        # The housing, drawn once.
        left, top = CX - S / 2, CY - S / 2
        box = self.box = Box(left - 2, top - 2, left + S + 2, top + S + 2)
        x, y = box.x, box.y
        body = self.base[box.slice]
        shade = (y - top) / S
        blend(body, BODY_TOP + (BODY_BOTTOM - BODY_TOP) * np.clip(shade, 0, 1)[..., None], cover(rounded_rect(x, y, left, top, S, RADIUS)))
        rim = np.abs(rounded_rect(x, y, left + 0.012 * S, top + 0.012 * S, 0.976 * S, 0.95 * RADIUS))
        blend(body, WHITE, 0.09 * np.clip(0.004 * S - rim + 0.5, 0.0, 1.0))
        inset = WINDOW_INSET
        self.window = cover(rounded_rect(x, y, left + inset, top + inset, S - 2 * inset, 0.72 * RADIUS))
        blend(body, WINDOW_FILL, self.window)
        r = np.hypot(x - CX, y - CY)
        blend(body, np.array([90, 110, 180], np.float32), 0.16 * np.clip(1.0 - r / (0.45 * S), 0.0, 1.0) * self.window)
        for (dx, dy), _ in ARMS:
            d = segment(x, y, CX + dx * 0.10 * S, CY + dy * 0.10 * S, CX + dx * 0.36 * S, CY + dy * 0.36 * S)
            blend(body, TUBE, cover(d - 0.055 * S))
            ox, oy = -dy * 0.03 * S, dx * 0.03 * S
            d = segment(x, y, CX + dx * 0.12 * S + ox, CY + dy * 0.12 * S + oy, CX + dx * 0.35 * S + ox, CY + dy * 0.35 * S + oy)
            blend(body, WHITE, 0.07 * cover(d - 0.006 * S))
        blend(body, HUB, cover(r - 0.085 * S))
        for sx in (-1, 1):
            for sy in (-1, 1):
                blend(body, SCREW, cover(np.hypot(x - (CX + sx * 0.4 * S), y - (CY + sy * 0.4 * S)) - 0.016 * S))

        # The lights, each a fixed shape whose brightness the beat sets,
        # cut to the window so nothing moves outside the mark.
        win = self.window
        self.glass = []
        self.bulbs = []
        for (dx, dy), color in ARMS:
            d = segment(x, y, CX + dx * 0.12 * S, CY + dy * 0.12 * S, CX + dx * 0.345 * S, CY + dy * 0.345 * S)
            self.glass.append((color, cover(d - 0.025 * S) * win))
            for k in range(BULBS):
                reach = S * (0.335 - k * 0.2 / (BULBS - 1))
                bx, by = CX + dx * reach, CY + dy * reach
                sl, px, py = box.inner(bx - 0.09 * S, by - 0.09 * S, bx + 0.09 * S, by + 0.09 * S)
                d = np.hypot(px - bx, py - by)
                w = win[sl]
                self.bulbs.append((k, color, sl, cover(d - 0.03 * S) * w, glow(d, 0.09 * S) * w, cover(d - 0.012 * S) * w))
        self.core = glow(r, 0.2 * S) * win
        self.hub = cover(r - 0.05 * S)
        self.fill = glow(r, 0.6 * S) * win

        # The wordmark.
        word = render_word(font)
        wh, ww = word.shape
        x0 = round(CX - ww / 2)
        y0 = round(WORD_CY - wh / 2)
        blend(self.base[y0:y0 + wh, x0:x0 + ww], WORD_INK, word)

    def lights(self, t: float) -> np.ndarray:
        """The housing at t."""
        level, chase, core, flash = beat(t)
        out = self.base[self.box.slice].copy()
        for color, shape in self.glass:
            blend(out, color, (0.18 + 0.3 * level) * shape)
        for k, color, sl, disc, spot, dot in self.bulbs:
            dd = (chase - k / BULBS) % 1.0
            dd = min(dd, 1.0 - dd)
            b = level * (0.2 + 0.8 * math.exp(-dd * dd / 0.008))
            region = out[sl]
            blend(region, BULB_OFF + (color - BULB_OFF) * min(1.0, 0.25 + b), disc)
            add(region, (min(1.0, b) * spot)[..., None] * color)
            add(region, (min(1.0, 0.8 * b) * dot)[..., None] * WHITE)
        if flash > 0.0:
            add(out, (0.55 * flash * self.fill)[..., None] * WHITE)
        add(out, (min(1.0, core) * self.core)[..., None] * WHITE)
        blend(out, HUB + (WHITE - HUB) * min(1.0, core), self.hub)
        return out

    def render(self, t: float) -> np.ndarray:
        """The frame at t seconds, unquantized."""
        out = self.base.copy()
        out[self.box.slice] = self.lights(t)
        return out

    def frame(self, t: float) -> np.ndarray:
        """The frame at t seconds, as 8-bit RGB."""
        out = self.render(t)
        lift = np.clip(np.abs(out - CANVAS).max(axis=2, keepdims=True), 0.0, 1.0)
        return np.clip(np.floor(out + 0.5 + self.dither * lift), 0, 255).astype(np.uint8)


def encode(scene: Scene, out: str) -> None:
    cmd = [
        "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
        "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}", "-framerate", str(FPS),
        "-i", "-",
        # Tagged, so a player converts back with the matrix used here.
        "-vf", (
            "scale=out_color_matrix=bt709:out_range=tv:flags=accurate_rnd+full_chroma_int,"
            "format=yuv420p,"
            "setparams=range=tv:color_primaries=bt709:color_trc=bt709:colorspace=bt709"
        ),
        # tune=grain keeps the dither rather than smoothing it back into bands.
        "-an", "-c:v", "libx264", "-preset", "veryslow", "-crf", "20", "-tune", "grain",
        "-movflags", "+faststart",
        out,
    ]
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    assert proc.stdin is not None
    try:
        for i in range(FRAMES):
            proc.stdin.write(scene.frame(i / FPS).tobytes())
    finally:
        proc.stdin.close()
    if proc.wait() != 0:
        sys.exit("ffmpeg failed")


def main() -> None:
    if not shutil.which("ffmpeg"):
        sys.exit("ffmpeg was not found on PATH.")
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "boot.mp4")
    if len(sys.argv) > 1:
        out = sys.argv[1]
    font = find_font()
    encode(Scene(font), out)
    print(f"wrote {out} ({os.path.getsize(out)} bytes, font {font})")


if __name__ == "__main__":
    main()
