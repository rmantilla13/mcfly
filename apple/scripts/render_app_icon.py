#!/usr/bin/env python3
"""Rasterize the McFly app icon: a lightning bolt on the blue → coral → amber glow.

Writes AppIcon-<size>.png for every size the asset catalog lists. Pure
Python (zlib + struct), so it runs anywhere without Pillow. iOS masks the
corners, so the image is a full-bleed square with no alpha.
"""

import math
import struct
import zlib
from pathlib import Path

SIZE = 1024
SIZES = (1024, 512, 256, 128, 64, 32, 16)
STOPS = (
    (0.0, (0x5B, 0x7C, 0xF5)),
    (0.55, (0xF0, 0x7F, 0x5A)),
    (1.0, (0xF6, 0xB9, 0x4A)),
)
# A bolt in a 64-unit box, drawn as a polygon.
BOLT = [(36, 8), (16, 36), (30, 36), (26, 56), (48, 26), (34, 26)]


def gradient(x: int, y: int) -> tuple[int, int, int]:
    t = (x + y) / (2 * (SIZE - 1))
    for (t0, c0), (t1, c1) in zip(STOPS, STOPS[1:]):
        if t <= t1:
            u = 0 if t1 == t0 else (t - t0) / (t1 - t0)
            return tuple(round(a + (b - a) * u) for a, b in zip(c0, c1))  # type: ignore[return-value]
    return STOPS[-1][1]


def inside(px: float, py: float, poly: list[tuple[float, float]]) -> bool:
    hit = False
    j = len(poly) - 1
    for i in range(len(poly)):
        xi, yi = poly[i]
        xj, yj = poly[j]
        if (yi > py) != (yj > py) and px < (xj - xi) * (py - yi) / (yj - yi) + xi:
            hit = not hit
        j = i
    return hit


def seg_dist(px: float, py: float, ax: float, ay: float, bx: float, by: float) -> float:
    dx, dy = bx - ax, by - ay
    len2 = dx * dx + dy * dy
    if len2 == 0:
        return math.hypot(px - ax, py - ay)
    u = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / len2))
    return math.hypot(px - (ax + u * dx), py - (ay + u * dy))


def png(rgb: bytes, size: int) -> bytes:
    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    raw = b"".join(b"\x00" + rgb[y * size * 3:(y + 1) * size * 3] for y in range(size))
    ihdr = struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")


def render() -> bytearray:
    scale = SIZE / 64
    poly = [(x * scale, y * scale) for x, y in BOLT]
    edges = list(zip(poly, poly[1:] + poly[:1]))
    soft = 1.5  # anti-aliasing band, in pixels
    buf = bytearray(SIZE * SIZE * 3)
    for y in range(SIZE):
        row = y * SIZE * 3
        for x in range(SIZE):
            r, g, b = gradient(x, y)
            px, py = x + 0.5, y + 0.5
            dist = min(seg_dist(px, py, a[0], a[1], c[0], c[1]) for a, c in edges)
            if inside(px, py, poly):
                t = min(1.0, dist / soft)
            else:
                t = max(0.0, 1 - dist / soft)
            if t:
                r = round(r + (255 - r) * t)
                g = round(g + (255 - g) * t)
                b = round(b + (255 - b) * t)
            buf[row + x * 3:row + x * 3 + 3] = bytes((r, g, b))
    return buf


def downsample(src: bytearray, size: int) -> bytes:
    """Box filter from SIZE to `size` (both powers of two)."""
    factor = SIZE // size
    out = bytearray(size * size * 3)
    area = factor * factor
    for y in range(size):
        for x in range(size):
            sums = [0, 0, 0]
            for dy in range(factor):
                base = ((y * factor + dy) * SIZE + x * factor) * 3
                for dx in range(factor):
                    i = base + dx * 3
                    sums[0] += src[i]
                    sums[1] += src[i + 1]
                    sums[2] += src[i + 2]
            o = (y * size + x) * 3
            out[o:o + 3] = bytes(round(s / area) for s in sums)
    return bytes(out)


def main() -> None:
    out_dir = Path(__file__).resolve().parents[1] / "McFly" / "Assets.xcassets" / "AppIcon.appiconset"
    out_dir.mkdir(parents=True, exist_ok=True)
    full = render()
    for size in SIZES:
        data = png(bytes(full) if size == SIZE else downsample(full, size), size)
        (out_dir / f"AppIcon-{size}.png").write_bytes(data)
        print(f"AppIcon-{size}.png {len(data)} bytes")


if __name__ == "__main__":
    main()
