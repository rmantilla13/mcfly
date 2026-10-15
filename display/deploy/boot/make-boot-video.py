#!/usr/bin/env python3
"""Regenerate display/deploy/boot/boot.mp4, the clip the Pi plays from boot
until the app takes the screen.

The McFly mark (the blue-to-coral disc with the white bolt, as the nav rail
and the setup screen draw it) over the McFly wordmark in Inter Bold, on the
day canvas (#F1EFEB). A soft dawn in the day palette drifts behind the mark.
Every six seconds three pulses of light run in along a Y (the flux
capacitor's) and charge the bolt: the disc's halo swells, a ring spreads
out and a glint crosses it.

The player stops the clip at any frame and may loop it for up to a minute
while Wi-Fi joins, so there is no intro: every frame shows the whole mark,
and the last frame runs into the first without a seam. The border stays
exactly the canvas colour, which mcfly-bootscreen also pads with. A fixed
dither keeps the glow from banding. Silent, 1920x1200, 24 fps, H.264 tagged
BT.709.

Needs Python 3.10+, numpy, ffmpeg (with libx264 and drawtext) and Inter Bold
(the fonts-inter package, or set MCFLY_BOOT_FONT). Writes boot.mp4 next to
this script, or to the path given. The installer ships that mp4; you do not
need to run this on the Pi.
"""

from __future__ import annotations

import itertools
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

CANVAS = np.array([241, 239, 235], np.float32)  # #F1EFEB, the day background
INK = np.array([28, 28, 31], np.float32)  # #1C1C1F, the day text
WHITE = np.array([255, 255, 255], np.float32)
# The day glow in display/qml/Theme.qml.
BLUE = np.array([91, 124, 245], np.float32)  # #5B7CF5
CORAL = np.array([240, 127, 90], np.float32)  # #F07F5A
AMBER = np.array([246, 185, 74], np.float32)  # #F6B94A

# The disc: centre and radius. With the wordmark under it, the lockup sits
# a little above the middle of the frame.
CX, CY, R = 960.0, 500.0, 132.0
# The bolt from Icon.qml ("M13 3 5 13.5h6L10 21l8-10.5h-6z") in its 24 px
# box, sized as the setup screen draws it: the box is 0.54 of the disc and
# the stroke 2.2 of 24.
BOLT = ((13.0, 3.0), (5.0, 13.5), (11.0, 13.5), (10.0, 21.0), (18.0, 10.5), (12.0, 10.5))
BOLT_BOX = 0.54 * 2 * R
BOLT_STROKE = 2.2 / 24 * BOLT_BOX
WORD = "McFly"
WORD_SIZE = 124
WORD_TOP = CY + R + 74  # top of the tallest letter

# The beat, as fractions of the loop: the pulses run in until ARRIVE, then
# the disc answers.
ARRIVE = 0.30
PULSE_FROM = 380.0  # distance from the disc's centre where a pulse starts
SINK = 40.0  # how far a pulse runs on behind the disc before it is gone
# Pulse arms, degrees counter-clockwise from 3 o'clock, and their colours.
ARMS = ((90.0, BLUE), (210.0, AMBER), (330.0, CORAL))
# The glow, a dawn behind the mark in the disc's own order: blue overhead,
# coral and amber under it. Colour, strength, home, reach (x, y), sway (x, y),
# phase. Each reaches exactly zero at its reach, well inside the frame.
GLOWS = (
    (BLUE, 0.34, (CX - 40, CY - 130), (660, 290), (70, 16), 0.0),
    (CORAL, 0.30, (CX + 60, CY + 150), (620, 280), (80, 14), 2.1),
    (AMBER, 0.30, (CX - 30, CY + 340), (660, 250), (70, 12), 4.2),
)
EDGE = 160  # the frame fades back to the plain canvas over this border


def find_font() -> str:
    home = os.path.expanduser("~")
    candidates = [
        os.environ.get("MCFLY_BOOT_FONT"),
        "/usr/share/fonts/opentype/inter/Inter-Bold.otf",
        "/usr/share/fonts/truetype/inter/Inter-Bold.ttf",
        "/usr/share/fonts/truetype/inter/Inter-Bold.otf",
        os.path.join(home, "Library/Fonts/Inter-Bold.ttf"),
        os.path.join(home, "Library/Fonts/Inter-Bold.otf"),
        "/Library/Fonts/Inter-Bold.ttf",
        "/Library/Fonts/Inter-Bold.otf",
    ]
    for path in candidates:
        if path and os.path.isfile(path):
            return path
    if shutil.which("fc-list"):
        out = subprocess.check_output(["fc-list", "Inter:style=Bold", "file"], text=True)
        for line in out.splitlines():
            path = line.split(":", 1)[0].strip()
            name = os.path.basename(path)
            # A variable font would draw its default instance, not Bold.
            if os.path.isfile(path) and "Italic" not in name and "Variable" not in name:
                return path
    sys.exit("Inter Bold was not found. Install fonts-inter or set MCFLY_BOOT_FONT.")


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def bump(d2):
    """1 at the centre, exactly 0 from d2 = 1 on (a Gaussian never gets there)."""
    return np.clip(1.0 - d2, 0.0, None) ** 3


class Box:
    """A rectangle of the frame, with the centres of its pixels."""

    def __init__(self, x0: float, y0: float, x1: float, y1: float):
        x0, y0 = max(0, math.floor(x0)), max(0, math.floor(y0))
        x1, y1 = min(W, math.ceil(x1)), min(H, math.ceil(y1))
        self.slice = (slice(y0, y1), slice(x0, x1))
        self.x = np.arange(x0, x1, dtype=np.float32)[None, :] + 0.5
        self.y = np.arange(y0, y1, dtype=np.float32)[:, None] + 0.5


def tint(frame: np.ndarray, box: Box, color, alpha: np.ndarray) -> None:
    region = frame[box.slice]
    region += (color - region) * alpha[..., None]


def vertical(y: np.ndarray, stops) -> np.ndarray:
    """Colours down a vertical gradient: stops are (y, colour), top first."""
    out = np.empty((y.shape[0], 1, 3), np.float32)
    flat = y[:, 0]
    out[:, 0] = stops[0][1]
    for (y0, c0), (y1, c1) in itertools.pairwise(stops):
        u = np.clip((flat - y0) / (y1 - y0), 0.0, 1.0)[:, None]
        mask = flat >= y0
        out[mask, 0] = (c0 + (c1 - c0) * u)[mask]
    return out


def segment_distance(box: Box, points) -> np.ndarray:
    """Distance from each pixel to a closed polyline."""
    dist = np.full((box.y.shape[0], box.x.shape[1]), np.inf, np.float32)
    for (x0, y0), (x1, y1) in zip(points, points[1:] + points[:1], strict=True):
        vx, vy = x1 - x0, y1 - y0
        t = np.clip(((box.x - x0) * vx + (box.y - y0) * vy) / (vx * vx + vy * vy), 0.0, 1.0)
        dist = np.minimum(dist, np.hypot(box.x - (x0 + t * vx), box.y - (y0 + t * vy)))
    return dist


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


class Scene:
    def __init__(self, font: str):
        # The canvas, and the window that brings the border back to it.
        self.canvas = np.empty((H, W, 3), np.float32)
        self.canvas[:] = CANVAS
        xs = np.arange(W, dtype=np.float32) + 0.5
        ys = np.arange(H, dtype=np.float32) + 0.5
        wx = smoothstep(0.0, EDGE, xs) * smoothstep(0.0, EDGE, W - xs)
        wy = smoothstep(0.0, EDGE, ys) * smoothstep(0.0, EDGE, H - ys)
        self.window = (wy[:, None] * wx[None, :])[..., None]
        # One fixed dither pattern (triangular, +-1 level) against banding
        # in the glow. Fixed, so it costs the encoder little; it fades out
        # where the frame is plain canvas, so that stays exactly the canvas.
        rng = np.random.default_rng(1985)
        self.dither = rng.random((H, W, 1), np.float32) - rng.random((H, W, 1), np.float32)

        # The disc and its bolt.
        self.disc = Box(CX - R - 2, CY - R - 2, CX + R + 2, CY + R + 2)
        r = np.hypot(self.disc.x - CX, self.disc.y - CY)
        self.disc_alpha = np.clip(R - r + 0.5, 0.0, 1.0)
        grad = vertical(self.disc.y, ((CY - R, BLUE), (CY + R, CORAL)))
        scale = BOLT_BOX / 24.0
        left, top = CX - BOLT_BOX / 2, CY - BOLT_BOX / 2
        points = [(left + x * scale, top + y * scale) for x, y in BOLT]
        bolt_dist = segment_distance(self.disc, points)
        half = BOLT_STROKE / 2
        bolt = np.clip(half - bolt_dist + 0.5, 0.0, 1.0)
        self.disc_color = grad + (WHITE - grad) * bolt[..., None]
        # Light around the stroke while the bolt is charged.
        outside = np.maximum(bolt_dist - half, 0.0)
        self.bolt_glow = np.exp(-0.5 * (outside / 11.0) ** 2) * (1.0 - bolt)
        diag = ((self.disc.x - CX) + (self.disc.y - CY)) / math.sqrt(2.0)
        self.diag = np.broadcast_to(diag, bolt.shape)

        # Everywhere the glow can reach. It has to fade out on its own, well
        # before the border window would cut it.
        spans = [
            (hx - rx - ox, hy - ry - oy, hx + rx + ox, hy + ry + oy)
            for _, _, (hx, hy), (rx, ry), (ox, oy), _ in GLOWS
        ]
        x0, y0 = min(b[0] for b in spans), min(b[1] for b in spans)
        x1, y1 = max(b[2] for b in spans), max(b[3] for b in spans)
        if min(x0, y0, W - x1, H - y1) < EDGE / 4:
            sys.exit("the glow reaches the edge of the frame")
        self.glow = Box(x0, y0, x1, y1)

        # The halo: the disc's own colours carried out past its edge.
        reach = 320.0
        self.halo = Box(CX - R - reach, CY - R - reach, CX + R + reach, CY + R + reach)
        self.halo_r = np.hypot(self.halo.x - CX, self.halo.y - CY)
        self.halo_color = vertical(
            self.halo.y,
            ((CY - R - 120, BLUE), (CY + R, CORAL), (CY + R + 200, AMBER)),
        )

        # The pulse arms: distance along each arm and across it.
        self.arms = []
        for degrees, color in ARMS:
            a = math.radians(degrees)
            ux, uy = math.cos(a), -math.sin(a)
            x0, y0 = CX + ux * R * 0.8, CY + uy * R * 0.8
            x1, y1 = CX + ux * (PULSE_FROM + 240), CY + uy * (PULSE_FROM + 240)
            pad = 100.0  # past the bloom's reach across the arm
            box = Box(min(x0, x1) - pad, min(y0, y1) - pad, max(x0, x1) + pad, max(y0, y1) + pad)
            along = (box.x - CX) * ux + (box.y - CY) * uy
            across = np.abs((box.x - CX) * uy - (box.y - CY) * ux)
            self.arms.append((box, color, along, across))

        # The wordmark.
        word = render_word(font)
        wh, ww = word.shape
        x0 = round(CX - ww / 2)
        y0 = round(WORD_TOP)
        self.word = Box(x0, y0, x0 + ww, y0 + wh)
        self.word_alpha = word

    def frame(self, t: float) -> np.ndarray:
        """The frame at t seconds, as 8-bit RGB."""
        out = self.render(t)
        lift = np.clip(np.abs(out - CANVAS).max(axis=2, keepdims=True), 0.0, 1.0)
        return np.clip(np.floor(out + 0.5 + self.dither * lift), 0, 255).astype(np.uint8)

    def render(self, t: float) -> np.ndarray:
        """The frame at t seconds, unquantized."""
        phase = (t / DURATION) % 1.0
        turn = 2.0 * math.pi * phase
        # Seconds since the pulses arrived; the answer is over well before
        # they set out again.
        since = ((phase - ARRIVE) % 1.0) * DURATION
        answer = smoothstep(0.0, 0.12, since) * math.exp(-max(since - 0.12, 0.0) / 0.6)
        answer *= smoothstep(3.2, 2.4, since)

        out = self.canvas.copy()

        # 1. The glow. The lobes are mixed into one colour first: tinting
        #    blue and then coral over each other goes grey where they meet.
        box = self.glow
        clear = np.ones((box.y.shape[0], box.x.shape[1]), np.float32)
        paint = np.zeros((*clear.shape, 3), np.float32)
        weight = np.zeros(clear.shape, np.float32)
        for color, strength, (hx, hy), (rx, ry), (ox, oy), offset in GLOWS:
            gx = hx + ox * math.sin(turn + offset)
            gy = hy + oy * math.sin(2.0 * turn + offset)
            breathe = 1.0 + 0.10 * math.sin(turn + offset + 1.0)
            a = strength * breathe * bump(((box.x - gx) / rx) ** 2 + ((box.y - gy) / ry) ** 2)
            clear *= 1.0 - a
            paint += a[..., None] * color
            weight += a
        mixed = paint / np.maximum(weight, 1e-6)[..., None]
        tint(out, box, mixed, 1.0 - clear)

        # 2. The halo, swelling when the pulses arrive, and the ring they set off.
        past = np.maximum(self.halo_r - R, 0.0)
        halo = (0.20 + 0.22 * answer) * bump((past / (150.0 + 40.0 * answer)) ** 2)
        if since < 1.6:
            u = since / 1.6
            ring_r = R + 230.0 * (1.0 - (1.0 - u) ** 3)
            width = 26.0 + 50.0 * u
            swell = smoothstep(0.0, 0.2, since) * (1.0 - u) ** 2
            halo = halo + 0.26 * swell * bump(((self.halo_r - ring_r) / width) ** 2)
        tint(out, self.halo, self.halo_color, np.clip(halo, 0.0, 1.0))

        # 3. The pulses: a bright head and a tail, running in to the disc.
        #    They reach the disc's edge at ARRIVE and sink behind it.
        travel = phase / ARRIVE
        head = PULSE_FROM - (PULSE_FROM - R) * travel * travel
        if head > R - SINK:
            fade = smoothstep(0.0, 0.3, travel) * smoothstep(R - SINK, R + 50.0, head)
            for box, color, along, across in self.arms:
                behind = along - head
                core = np.exp(-0.5 * (behind ** 2 + across ** 2) / 6.0 ** 2)
                length = bump((np.maximum(behind, 0.0) / 220.0) ** 2)
                length = length * smoothstep(-10.0, 4.0, behind)
                tail = length * np.exp(-0.5 * (across / 5.0) ** 2)
                haze = length * np.exp(-0.5 * (across / 18.0) ** 2)
                bloom = np.exp(-0.5 * ((behind / 40.0) ** 2 + (across / 26.0) ** 2))
                glow = 0.60 * tail + 0.22 * haze + 0.38 * bloom
                tint(out, box, color, fade * np.clip(glow, 0.0, 1.0))
                tint(out, box, WHITE, fade * 0.7 * core)

        # 4. The mark, and the charge running through it.
        disc = self.disc_color
        if answer > 0.0:
            disc = disc + (WHITE - disc) * (0.55 * answer * self.bolt_glow)[..., None]
        if 0.0 <= since < 0.9:
            u = smoothstep(0.0, 0.9, since)
            sweep = -R - 60.0 + (2 * R + 120.0) * u
            glint = 0.30 * np.exp(-0.5 * ((self.diag - sweep) / 24.0) ** 2)
            disc = disc + (WHITE - disc) * glint[..., None]
        tint(out, self.disc, disc, self.disc_alpha)

        # 5. The wordmark.
        tint(out, self.word, INK, self.word_alpha)

        return CANVAS + (out - CANVAS) * self.window


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
