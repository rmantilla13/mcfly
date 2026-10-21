#!/usr/bin/env python3
"""Rasterize the McFly app icon: the McFly mark (flux_mark.py), the flux
capacitor's Y on its dark tile, edge to edge.

Writes AppIcon-<size>.png for every size the asset catalog lists. Pure
Python (zlib + struct), so it runs anywhere without Pillow. iOS masks the
corners, so the image is a full-bleed square with no alpha.
"""

import struct
import zlib
from pathlib import Path

import flux_mark

SIZE = 1024
SIZES = (1024, 512, 256, 128, 64, 32, 16)


def png(rgb: bytes, size: int) -> bytes:
    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    raw = b"".join(b"\x00" + rgb[y * size * 3:(y + 1) * size * 3] for y in range(size))
    ihdr = struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")


def render() -> bytearray:
    buf = bytearray(SIZE * SIZE * 3)
    for y, row in enumerate(flux_mark.render(SIZE, SIZE, tile=False)):
        buf[y * SIZE * 3:(y + 1) * SIZE * 3] = b"".join(bytes((round(r), round(g), round(b))) for r, g, b, _ in row)
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
