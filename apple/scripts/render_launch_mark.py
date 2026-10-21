#!/usr/bin/env python3
"""Rasterize the launch screen's mark: the McFly mark (flux_mark.py) on its
dark tile, 120 points across.

The launch screen is black in both appearances (Assets.xcassets/
LaunchBackground), as the Pi's boot clip is, so one image serves both.

Writes LaunchMark.imageset: @2x and @3x, transparent around the tile.
Info.plist's UILaunchScreen centres it on the whole screen at its own size,
and RootView draws the same image in the same place while the app starts,
so the launch screen hands over without a jump. Pure Python (zlib + struct),
like render_app_icon.py.
"""

import struct
import zlib
from pathlib import Path

import flux_mark

MARK = 120  # points
# A clear point all round keeps the tile's anti-aliased edge whole, and an
# even size puts the centred image on whole points.
CANVAS = MARK + 2
SCALES = (2, 3)


def png(rows: list[bytes], size: int) -> bytes:
    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    raw = b"".join(b"\x00" + row for row in rows)
    ihdr = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)  # 8-bit RGBA
    srgb = chunk(b"sRGB", b"\x00")  # the colours are sRGB, as the display's are
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + srgb + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")


def render(scale: int) -> bytes:
    size = CANVAS * scale
    rows = []
    for row in flux_mark.render(size, MARK * scale, tile=True):
        # Straight alpha. Even the clear pixels keep the tile's colour, so
        # nothing light creeps into the edge if the image is filtered.
        rows.append(b"".join(bytes((round(r), round(g), round(b), round(255 * a))) for r, g, b, a in row))
    return png(rows, size)


def main() -> None:
    out_dir = Path(__file__).resolve().parents[1] / "McFly" / "Assets.xcassets" / "LaunchMark.imageset"
    out_dir.mkdir(parents=True, exist_ok=True)
    for old in out_dir.glob("LaunchMark-dark@*.png"):
        old.unlink()
    entries = []
    for scale in SCALES:
        name = f"LaunchMark@{scale}x.png"
        data = render(scale)
        (out_dir / name).write_bytes(data)
        print(f"{name} {CANVAS * scale}px {len(data)} bytes")
        entries.append(f'    {{ "filename" : "{name}", "idiom" : "universal", "scale" : "{scale}x" }}')
    contents = '{\n  "images" : [\n' + ",\n".join(entries) + '\n  ],\n  "info" : { "author" : "xcode", "version" : 1 }\n}\n'
    (out_dir / "Contents.json").write_text(contents)


if __name__ == "__main__":
    main()
