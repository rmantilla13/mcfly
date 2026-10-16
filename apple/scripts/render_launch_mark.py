#!/usr/bin/env python3
"""Rasterize the launch screen's mark: the white bolt on the blue-to-coral disc.

The mark the display's nav rail and setup screen draw, and the Pi's boot clip
(display/deploy/boot/make-boot-video.py): a disc with a vertical gradient, top
to bottom, and Icon.qml's bolt stroked in white over it, its 24-unit box 0.54
of the disc and the stroke 2.2 of 24, with round joins. In dark mode the disc
takes the dark palette's blue and coral, as Home and the display draw it there.

Writes LaunchMark.imageset: @2x and @3x, light and dark, transparent around
the disc. Info.plist's UILaunchScreen centres it on the whole screen at its
own size, and RootView draws the same image in the same place while the app
starts, so the launch screen hands over without a jump. Pure Python (zlib +
struct), like render_app_icon.py.
"""

import math
import struct
import zlib
from pathlib import Path

DISC = 120  # points
# A clear point all round keeps the rim's anti-aliasing whole, and an even
# size puts the centred image on whole points.
CANVAS = DISC + 2
SCALES = (2, 3)
# The disc's top and bottom colours: the day palette's blue and coral, and the
# dark palette's (display/qml/Theme.qml, Theme.swift).
VARIANTS = {
    "": ((0x5B, 0x7C, 0xF5), (0xF0, 0x7F, 0x5A)),
    "-dark": ((0x3B, 0x5B, 0xD4), (0xC4, 0x5A, 0x3A)),
}
# Icon.qml's "bolt" (M13 3 5 13.5h6L10 21l8-10.5h-6z) in its 24-unit box.
BOLT = ((13.0, 3.0), (5.0, 13.5), (11.0, 13.5), (10.0, 21.0), (18.0, 10.5), (12.0, 10.5))
BOLT_BOX = 0.54  # of the disc
BOLT_STROKE = 2.2 / 24  # of the box


def seg_dist(px: float, py: float, ax: float, ay: float, bx: float, by: float) -> float:
    dx, dy = bx - ax, by - ay
    u = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    return math.hypot(px - (ax + u * dx), py - (ay + u * dy))


def png(rows: list[bytes], size: int) -> bytes:
    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    raw = b"".join(b"\x00" + row for row in rows)
    ihdr = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)  # 8-bit RGBA
    srgb = chunk(b"sRGB", b"\x00")  # the colours are sRGB, as the display's are
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + srgb + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")


def render(scale: int, top: tuple[int, int, int], bottom: tuple[int, int, int]) -> bytes:
    size = CANVAS * scale
    c = size / 2
    r = DISC * scale / 2
    box = BOLT_BOX * DISC * scale
    unit = box / 24
    points = [(c - box / 2 + x * unit, c - box / 2 + y * unit) for x, y in BOLT]
    edges = list(zip(points, points[1:] + points[:1]))
    half = BOLT_STROKE * box / 2
    rows = []
    for y in range(size):
        py = y + 0.5
        t = max(0.0, min(1.0, (py - (c - r)) / (2 * r)))
        shade = [a + (b - a) * t for a, b in zip(top, bottom)]
        row = bytearray(size * 4)
        for x in range(size):
            px = x + 0.5
            cover = max(0.0, min(1.0, r - math.hypot(px - c, py - c) + 0.5))
            ink = 0.0
            if cover:
                dist = min(seg_dist(px, py, a[0], a[1], b[0], b[1]) for a, b in edges)
                ink = max(0.0, min(1.0, half - dist + 0.5))
            # Straight alpha. Even the clear pixels keep the disc's colour, so
            # nothing dark creeps into the rim if the image is filtered.
            rgb = [round(v + (255 - v) * ink) for v in shade]
            row[x * 4:x * 4 + 4] = bytes((*rgb, round(255 * cover)))
        rows.append(bytes(row))
    return png(rows, size)


def main() -> None:
    out_dir = Path(__file__).resolve().parents[1] / "McFly" / "Assets.xcassets" / "LaunchMark.imageset"
    out_dir.mkdir(parents=True, exist_ok=True)
    entries = []
    for scale in SCALES:
        for suffix, (top, bottom) in VARIANTS.items():
            name = f"LaunchMark{suffix}@{scale}x.png"
            data = render(scale, top, bottom)
            (out_dir / name).write_bytes(data)
            print(f"{name} {CANVAS * scale}px {len(data)} bytes")
            dark = ' "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ],' if suffix else ""
            entries.append(f'    {{{dark} "filename" : "{name}", "idiom" : "universal", "scale" : "{scale}x" }}')
    contents = '{\n  "images" : [\n' + ",\n".join(entries) + '\n  ],\n  "info" : { "author" : "xcode", "version" : 1 }\n}\n'
    (out_dir / "Contents.json").write_text(contents)


if __name__ == "__main__":
    main()
