#!/usr/bin/env python3
"""生成 KSBall 应用图标（1024×1024，无透明通道）。

只依赖 Python 标准库：用有符号距离场绘制图形并做边缘抗锯齿，再手工编码为 PNG。
图案取自应用本身：屏幕右侧的细长悬浮条，以及围绕它展开的两圈圆形应用图标。

用法：python3 Scripts/generate_app_icon.py
"""

import math
import os
import struct
import zlib

SIZE = 1024
OUTPUT = os.path.join(os.path.dirname(__file__), "..", "KSBall", "Assets.xcassets", "AppIcon.appiconset", "AppIcon.png")

TOP_COLOR = (0x24, 0x33, 0x5C)
BOTTOM_COLOR = (0x0A, 0x0F, 0x1F)
BAR_COLOR = (0xF4, 0xF6, 0xFB)
PALETTE = [
    (0x34, 0xC7, 0x59), (0x0A, 0x84, 0xFF), (0xFF, 0x9F, 0x0A), (0xFF, 0x37, 0x5F),
    (0xBF, 0x5A, 0xF2), (0x64, 0xD2, 0xFF), (0xFF, 0xD6, 0x0A), (0x5E, 0x5C, 0xE6),
    (0x30, 0xD1, 0x58), (0xFF, 0x64, 0x82), (0x66, 0xD4, 0xCF), (0xFF, 0x8A, 0x3D),
]


def lerp(a, b, t):
    return a + (b - a) * t


def coverage(distance):
    """把有符号距离（像素，内部为负）换算成覆盖率，得到 1px 宽的抗锯齿边缘。"""
    return min(1.0, max(0.0, 0.5 - distance))


def main():
    # 背景：自上而下的深色渐变。iOS 会自动裁剪圆角，这里铺满整张画布。
    pixels = []
    for y in range(SIZE):
        t = y / (SIZE - 1)
        color = tuple(lerp(TOP_COLOR[i], BOTTOM_COLOR[i], t) for i in range(3))
        pixels.append([list(color) for _ in range(SIZE)])

    def blend(x, y, color, alpha):
        pixel = pixels[y][x]
        for i in range(3):
            pixel[i] = lerp(pixel[i], color[i], alpha)

    def draw_circle(cx, cy, radius, color, alpha=1.0):
        for y in range(max(0, int(cy - radius - 2)), min(SIZE, int(cy + radius + 3))):
            for x in range(max(0, int(cx - radius - 2)), min(SIZE, int(cx + radius + 3))):
                a = coverage(math.hypot(x + 0.5 - cx, y + 0.5 - cy) - radius) * alpha
                if a > 0.0:
                    blend(x, y, color, a)

    def draw_capsule(cx, cy, width, height, color, alpha=1.0):
        half_straight = max(0.0, height / 2.0 - width / 2.0)
        radius = width / 2.0
        for y in range(max(0, int(cy - height / 2 - 2)), min(SIZE, int(cy + height / 2 + 3))):
            for x in range(max(0, int(cx - radius - 2)), min(SIZE, int(cx + radius + 3))):
                dy = max(0.0, abs(y + 0.5 - cy) - half_straight)
                a = coverage(math.hypot(x + 0.5 - cx, dy) - radius) * alpha
                if a > 0.0:
                    blend(x, y, color, a)

    handle_x, handle_y = 868.0, 512.0

    # 悬浮条后面的柔光，让它在深色背景上更醒目。
    for step in range(6, 0, -1):
        draw_capsule(handle_x, handle_y, 36 + step * 16, 230 + step * 16, BAR_COLOR, 0.035)

    # 两圈扇形排布的应用图标：内圈 5 个组成半圆，外圈 7 个。
    rings = [(250.0, 5, 64.0, math.radians(90), math.radians(270)),
             (450.0, 7, 58.0, math.radians(118), math.radians(242))]
    color_index = 0
    for radius, count, item_radius, start, end in rings:
        for index in range(count):
            angle = lerp(start, end, index / (count - 1))
            cx = handle_x + math.cos(angle) * radius
            cy = handle_y + math.sin(angle) * radius
            color = PALETTE[color_index % len(PALETTE)]
            color_index += 1
            draw_circle(cx, cy + 6, item_radius + 2, (0, 0, 0), 0.28)
            draw_circle(cx, cy, item_radius, color)
            # 左上方的高光模拟图标的立体感。
            draw_circle(cx - item_radius * 0.28, cy - item_radius * 0.32, item_radius * 0.42, (255, 255, 255), 0.16)

    draw_capsule(handle_x, handle_y, 36, 230, BAR_COLOR)

    raw = bytearray()
    for row in pixels:
        raw.append(0)
        for pixel in row:
            raw.extend(int(round(min(255.0, max(0.0, channel)))) for channel in pixel)

    def chunk(kind, data):
        payload = kind + data
        return struct.pack(">I", len(data)) + payload + struct.pack(">I", zlib.crc32(payload) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")

    output = os.path.abspath(OUTPUT)
    os.makedirs(os.path.dirname(output), exist_ok=True)
    with open(output, "wb") as file:
        file.write(png)
    print(output)


if __name__ == "__main__":
    main()
