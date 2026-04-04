#!/usr/bin/env python3
"""Generate BeatKeys.icns icon file."""

from PIL import Image, ImageDraw, ImageFilter, ImageFont
import numpy as np
import math, os, subprocess

def draw_icon(size):
    s = size / 512
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))

    # ── Background: dark radial gradient with rounded corners ──────────
    bg = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    bg_arr = np.zeros((size, size, 4), dtype=np.uint8)
    cx, cy = size / 2, size / 2
    max_r = size * 0.7
    for y in range(size):
        for x in range(size):
            d = math.sqrt((x - cx)**2 + (y - cy)**2) / max_r
            d = min(d, 1.0)
            r = int(30  + (10  - 30)  * d)
            g = int(30  + (10  - 30)  * d)
            b = int(58  + (26  - 58)  * d)
            bg_arr[y, x] = [r, g, b, 255]
    bg = Image.fromarray(bg_arr, 'RGBA')

    # Apply rounded corners mask
    mask = Image.new('L', (size, size), 0)
    md = ImageDraw.Draw(mask)
    corner = int(110 * s)
    md.rounded_rectangle([0, 0, size-1, size-1], radius=corner, fill=255)
    bg.putalpha(mask)
    img = Image.alpha_composite(img, bg)

    draw = ImageDraw.Draw(img)

    # ── Central glow ────────────────────────────────────────────────────
    glow_size = int(380 * s)
    glow = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    gd = np.zeros((size, size, 4), dtype=np.uint8)
    gcx, gcy = size / 2, size / 2 - 10 * s
    gr = glow_size / 2
    for y in range(size):
        for x in range(size):
            d = math.sqrt((x - gcx)**2 + (y - gcy)**2) / gr
            if d < 1.0:
                # cyan core → purple mid → transparent
                if d < 0.35:
                    t = d / 0.35
                    r = int(0   + t * (123 - 0))
                    g = int(210 + t * (47 - 210))
                    b = int(255 + t * (247 - 255))
                    a = int(115 * (1 - t * 0.4))
                else:
                    t = (d - 0.35) / 0.65
                    r, g, b = 123, 47, 247
                    a = int(50 * (1 - t))
                gd[y, x] = [r, g, b, a]
    glow = Image.fromarray(gd, 'RGBA')
    img = Image.alpha_composite(img, glow)

    draw = ImageDraw.Draw(img)

    # ── Keycap dimensions ───────────────────────────────────────────────
    kw = int(305 * s)
    kh = int(272 * s)
    kx = (size - kw) // 2
    ky = (size - kh) // 2 - int(5 * s)
    kr = int(36 * s)

    # Key shadow (offset down)
    shadow = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle([kx, ky + int(10*s), kx+kw, ky+kh+int(10*s)],
                         radius=kr, fill=(0, 180, 255, 80))
    shadow = shadow.filter(ImageFilter.GaussianBlur(int(22*s)))
    img = Image.alpha_composite(img, shadow)

    draw = ImageDraw.Draw(img)

    # Key base
    draw.rounded_rectangle([kx, ky, kx+kw, ky+kh], radius=kr, fill=(34, 34, 74, 255))

    # Key body
    draw.rounded_rectangle([kx, ky, kx+kw, ky+kh], radius=kr, fill=(42, 42, 74, 255))

    # Key top face (inset)
    inset = int(8*s)
    bot_inset = int(22*s)
    draw.rounded_rectangle(
        [kx+inset, ky+int(6*s), kx+kw-inset, ky+kh-bot_inset],
        radius=max(4, kr-5), fill=(58, 58, 94, 255)
    )

    # Key border glow — draw as outline
    for i in range(3):
        alpha = int(200 - i*60)
        draw.rounded_rectangle(
            [kx+inset-i, ky+int(6*s)-i, kx+kw-inset+i, ky+kh-bot_inset+i],
            radius=max(4, kr-5+i), outline=(0, 210, 255, alpha), width=1
        )

    # ── "BK" text ────────────────────────────────────────────────────────
    font_size = int(115 * s)
    try:
        # Try SF Pro / system bold font
        font = ImageFont.truetype('/System/Library/Fonts/SFCompact.ttf', font_size)
    except:
        try:
            font = ImageFont.truetype('/System/Library/Fonts/Helvetica.ttc', font_size)
        except:
            font = ImageFont.load_default()

    text = 'BK'
    bbox = draw.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    tx = (size - tw) // 2 - bbox[0]
    ty = ky + (kh - bot_inset) // 2 - th // 2 - bbox[1] - int(4*s)

    # Text glow
    glow_layer = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    gd2 = ImageDraw.Draw(glow_layer)
    gd2.text((tx, ty), text, font=font, fill=(0, 210, 255, 160))
    glow_layer = glow_layer.filter(ImageFilter.GaussianBlur(int(8*s)))
    img = Image.alpha_composite(img, glow_layer)

    draw = ImageDraw.Draw(img)
    draw.text((tx, ty), text, font=font, fill=(0, 210, 255, 255))

    return img


# ── Generate iconset ─────────────────────────────────────────────────────
PROJ = os.path.dirname(os.path.abspath(__file__))
ICONSET = os.path.join(PROJ, 'BeatKeys.iconset')
os.makedirs(ICONSET, exist_ok=True)

sizes = [
    ('icon_16x16.png',       16),
    ('icon_16x16@2x.png',    32),
    ('icon_32x32.png',       32),
    ('icon_32x32@2x.png',    64),
    ('icon_128x128.png',     128),
    ('icon_128x128@2x.png',  256),
    ('icon_256x256.png',     256),
    ('icon_256x256@2x.png',  512),
    ('icon_512x512.png',     512),
    ('icon_512x512@2x.png',  1024),
]

print("Generating icon sizes...")
# Generate at 1024 once, downsample for small sizes
base = draw_icon(1024)

for filename, px in sizes:
    if px == 1024:
        icon = base
    else:
        icon = base.resize((px, px), Image.LANCZOS)
    path = os.path.join(ICONSET, filename)
    icon.save(path, 'PNG')
    print(f"  ✓ {filename} ({px}x{px})")

print("\nBuilding .icns...")
result = subprocess.run(
    ['iconutil', '-c', 'icns', ICONSET, '-o', os.path.join(PROJ, 'BeatKeys.icns')],
    capture_output=True, text=True
)
if result.returncode == 0:
    print("  ✅ BeatKeys.icns created!")
else:
    print("  ❌ iconutil failed:", result.stderr)
