"""生成应用图标 PNG（无第三方依赖）。

只做一件事：深绿渐变圆角底 + 白色对勾，输出多档尺寸。
之所以手写 PNG，是因为机器上没有 PIL，而图标不该为一次生成引入依赖。
"""

import math
import os
import struct
import sys
import zlib

BG_TOP = (0x3E, 0x7C, 0x6B)
BG_BOTTOM = (0x27, 0x59, 0x51)
FG = (0xFF, 0xFF, 0xFF)


def rounded_rect_alpha(x, y, w, h, r):
    """返回圆角矩形内部的覆盖率（0..1），坐标已归一化到像素。"""
    cx = min(max(x, r), w - r)
    cy = min(max(y, r), h - r)
    dx, dy = x - cx, y - cy
    dist = math.hypot(dx, dy)
    if dist <= r:
        return 1.0
    return max(0.0, 1.0 - (dist - r))


def seg_dist(px, py, ax, ay, bx, by):
    vx, vy = bx - ax, by - ay
    wx, wy = px - ax, py - ay
    length2 = vx * vx + vy * vy
    t = 0.0 if length2 == 0 else max(0.0, min(1.0, (wx * vx + wy * vy) / length2))
    dx, dy = px - (ax + t * vx), py - (ay + t * vy)
    return math.hypot(dx, dy)


def render(size):
    ratio = 0.24 * size          # 圆角
    stroke = 0.072 * size        # 勾的线宽
    pts = [(0.335, 0.525), (0.455, 0.645), (0.675, 0.375)]
    pts = [(x * size, y * size) for x, y in pts]

    rows = []
    for y in range(size):
        row = bytearray()
        bg = tuple(
            int(BG_TOP[i] + (BG_BOTTOM[i] - BG_TOP[i]) * (y / (size - 1)))
            for i in range(3)
        )
        for x in range(size):
            a = rounded_rect_alpha(x + 0.5, y + 0.5, size, size, ratio)
            r, g, b = bg
            if a > 0:
                d = min(
                    seg_dist(x + 0.5, y + 0.5, *pts[0], *pts[1]),
                    seg_dist(x + 0.5, y + 0.5, *pts[1], *pts[2]),
                )
                # 1px 软边，避免锯齿
                cover = max(0.0, min(1.0, stroke / 2 - d + 0.5))
                if cover > 0:
                    r = int(r * (1 - cover) + FG[0] * cover)
                    g = int(g * (1 - cover) + FG[1] * cover)
                    b = int(b * (1 - cover) + FG[2] * cover)
                row += bytes((r, g, b, int(255 * a)))
            else:
                row += b"\x00\x00\x00\x00"
        rows.append(bytes(row))
    return rows


def write_png(path, size, rows):
    raw = b"".join(b"\x00" + r for r in rows)

    def chunk(tag, data):
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    ihdr = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(png)
    print("wrote", path, size)


TARGETS = [
    ("android/app/src/main/res/mipmap-mdpi/ic_launcher.png", 48),
    ("android/app/src/main/res/mipmap-hdpi/ic_launcher.png", 72),
    ("android/app/src/main/res/mipmap-xhdpi/ic_launcher.png", 96),
    ("android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png", 144),
    ("android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png", 192),
    ("../docs/assets/icon-1024.png", 1024),
    ("../docs/assets/icon-512.png", 512),
]

if __name__ == "__main__":
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    os.chdir(root)
    for path, size in TARGETS:
        write_png(path, size, render(size))
    sys.exit(0)
