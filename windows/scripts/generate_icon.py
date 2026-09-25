from __future__ import annotations

import math
import struct
import zlib
from pathlib import Path


def _png_chunk(kind: bytes, data: bytes) -> bytes:
    payload = kind + data
    return struct.pack(">I", len(data)) + payload + struct.pack(">I", zlib.crc32(payload) & 0xFFFFFFFF)


def _segment_distance(px: float, py: float, ax: float, ay: float, bx: float, by: float) -> float:
    dx, dy = bx - ax, by - ay
    length = dx * dx + dy * dy
    if not length:
        return math.hypot(px - ax, py - ay)
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / length))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def make_icon(size: int = 64, scale: int = 4) -> bytes:
    side = size * scale
    pixels = bytearray()
    for y in range(side):
        for x in range(side):
            px, py = (x + 0.5) / scale, (y + 0.5) / scale
            edge_x = max(14 - px, 0, px - (size - 14))
            edge_y = max(14 - py, 0, py - (size - 14))
            inside = math.hypot(edge_x, edge_y) <= 14
            color = (32, 33, 38, 255) if inside else (0, 0, 0, 0)
            radius = math.hypot(px - 32, py - 32)
            if abs(radius - 22) <= 2.3:
                color = (235, 133, 102, 255)
            if _segment_distance(px, py, 32, 32, 32, 18) <= 1.8 or _segment_distance(px, py, 32, 32, 42, 38) <= 1.8:
                color = (248, 248, 250, 255)
            pixels.extend(color)

    rows = bytearray()
    stride = side * 4
    for y in range(size):
        rows.append(0)
        for x in range(size):
            accum = [0, 0, 0, 0]
            for sy in range(scale):
                start = ((y * scale + sy) * side + x * scale) * 4
                for sx in range(scale):
                    i = start + sx * 4
                    for c in range(4):
                        accum[c] += pixels[i + c]
            count = scale * scale
            rows.extend((value // count for value in accum))

    png = bytearray(b"\x89PNG\r\n\x1a\n")
    png.extend(_png_chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)))
    png.extend(_png_chunk(b"IDAT", zlib.compress(bytes(rows), 9)))
    png.extend(_png_chunk(b"IEND", b""))
    return bytes(png)


def main() -> None:
    destination = Path(__file__).resolve().parents[1] / "tokei_windows" / "assets" / "tokei.ico"
    destination.parent.mkdir(parents=True, exist_ok=True)
    png = make_icon()
    header = struct.pack("<HHH", 0, 1, 1)
    entry = struct.pack("<BBBBHHII", 64, 64, 0, 0, 1, 32, len(png), 22)
    destination.write_bytes(header + entry + png)


if __name__ == "__main__":
    main()
