#!/usr/bin/env python3
"""Generates the GtrBoard app icon.

The mark is a warm amber guitar pick on a dark pedalboard surface: readable
at 16 px, unmistakably a guitar tool at 1024 px. Run from the project root:

    python3 Scripts/make_icon.py
"""

from __future__ import annotations

import math
import os
import shutil
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
RESOURCES = ROOT / "Resources"
ICONSET = RESOURCES / "AppIcon.iconset"
MASTER = RESOURCES / "AppIcon-1024.png"
SIZE = 1024


def vertical_gradient(size: int, top: tuple[int, int, int], bottom: tuple[int, int, int]) -> Image.Image:
    image = Image.new("RGB", (1, size))
    pixels = image.load()
    for y in range(size):
        t = y / max(size - 1, 1)
        pixels[0, y] = (
            round(top[0] + (bottom[0] - top[0]) * t),
            round(top[1] + (bottom[1] - top[1]) * t),
            round(top[2] + (bottom[2] - top[2]) * t),
        )
    return image.resize((size, size), Image.Resampling.BILINEAR)


def rounded_mask(size: int, radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
    return mask


def quadratic(p0, p1, p2, steps: int = 40):
    points = []
    for index in range(steps + 1):
        t = index / steps
        x = (1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0]
        y = (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1]
        points.append((x, y))
    return points


def pick_points(cx: float, top: float, width: float, bottom: float):
    """Samples a rounded, downward-pointing guitar pick outline."""
    half = width / 2
    shoulder = top + (bottom - top) * 0.48
    points = []
    points += quadratic((cx - half * 0.92, top + 26), (cx, top - 26), (cx + half * 0.92, top + 26))
    points += quadratic((cx + half * 0.92, top + 26), (cx + half * 1.16, shoulder), (cx + half * 0.72, shoulder + 120))
    points += quadratic((cx + half * 0.72, shoulder + 120), (cx + half * 0.38, bottom - 60), (cx, bottom))
    points += quadratic((cx, bottom), (cx - half * 0.38, bottom - 60), (cx - half * 0.72, shoulder + 120))
    points += quadratic((cx - half * 0.72, shoulder + 120), (cx - half * 1.16, shoulder), (cx - half * 0.92, top + 26))
    return points


def make_icon() -> Image.Image:
    background = vertical_gradient(SIZE, (26, 19, 16), (9, 8, 7))

    # Warm lamp glow in the upper half.
    glow = Image.new("L", (SIZE, SIZE), 0)
    glow_draw = ImageDraw.Draw(glow)
    glow_draw.ellipse((190, -180, 840, 520), fill=120)
    glow = glow.filter(ImageFilter.GaussianBlur(160))
    warm = Image.new("RGB", (SIZE, SIZE), (255, 150, 70))
    background = Image.composite(warm, background, glow.point(lambda value: int(value * 0.55)))

    # A few faint horizontal "board" lines.
    draw = ImageDraw.Draw(background, "RGBA")
    for y in (250, 440, 700, 820):
        draw.line((80, y, SIZE - 80, y), fill=(255, 255, 255, 8), width=2)

    pick = pick_points(SIZE / 2, 205, 565, 855)
    mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(mask).polygon(pick, fill=255)

    amber = vertical_gradient(SIZE, (255, 201, 128), (214, 112, 24))
    amber = amber.filter(ImageFilter.GaussianBlur(0.4))
    background = Image.composite(amber, background, mask)

    pick_layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    pick_draw = ImageDraw.Draw(pick_layer)
    pick_draw.line(pick + [pick[0]], fill=(80, 39, 8, 140), width=8, joint="curve")

    # A dark inner ring like a pedal knob, with the monogram inside.
    ring_box = (SIZE / 2 - 150, SIZE / 2 - 148, SIZE / 2 + 150, SIZE / 2 + 152)
    pick_draw.ellipse(ring_box, fill=(22, 15, 11, 235), outline=(90, 45, 10, 160), width=5)
    pick_draw.ellipse(
        (ring_box[0] + 24, ring_box[1] + 24, ring_box[2] - 24, ring_box[3] - 24),
        outline=(255, 180, 100, 90),
        width=3,
    )

    font = None
    for candidate in (
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/System/Library/Fonts/SFNS.ttf",
    ):
        if os.path.exists(candidate):
            try:
                font = ImageFont.truetype(candidate, 210)
                break
            except Exception:
                continue
    if font is None:
        font = ImageFont.load_default()

    label = "G"
    bbox = pick_draw.textbbox((0, 0), label, font=font)
    text_x = (SIZE - (bbox[2] - bbox[0])) / 2 - bbox[0]
    text_y = (SIZE - (bbox[3] - bbox[1])) / 2 - bbox[1] - 6
    pick_draw.text((text_x, text_y), label, font=font, fill=(255, 206, 138, 255))

    background = Image.alpha_composite(background.convert("RGBA"), pick_layer)

    # Outer border.
    border = ImageDraw.Draw(background)
    border.rounded_rectangle((3, 3, SIZE - 4, SIZE - 4), radius=226, outline=(255, 255, 255, 26), width=3)

    icon = background.convert("RGB")
    icon.putalpha(rounded_mask(SIZE, 226))
    return icon


def main() -> None:
    icon = make_icon()
    RESOURCES.mkdir(parents=True, exist_ok=True)
    icon.save(MASTER, "PNG")

    if ICONSET.exists():
        shutil.rmtree(ICONSET)
    ICONSET.mkdir(parents=True)

    specs = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024),
    ]
    for name, size in specs:
        icon.resize((size, size), Image.Resampling.LANCZOS).save(ICONSET / name, "PNG")

    try:
        subprocess.run(
            ["iconutil", "-c", "icns", str(ICONSET), "-o", str(RESOURCES / "AppIcon.icns")],
            check=True,
        )
        print(f"wrote {RESOURCES / 'AppIcon.icns'}")
    except Exception as error:
        print(f"iconutil failed: {error}")


if __name__ == "__main__":
    main()
