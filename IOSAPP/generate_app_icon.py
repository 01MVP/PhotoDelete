#!/usr/bin/env python3

from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parent
ICON_DIR = ROOT / "PhotoDel" / "Assets.xcassets" / "AppIcon.appiconset"
SITE_ICON = ROOT.parent / "site" / "assets" / "app-icon.png"


def lerp(a, b, t):
    return int(a + (b - a) * t)


def rounded_layer(size, rect, radius, fill, outline=None, width=1, angle=0):
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    draw.rounded_rectangle(rect, radius=radius, fill=fill, outline=outline, width=width)
    if angle:
        layer = layer.rotate(angle, resample=Image.Resampling.BICUBIC, center=(size / 2, size / 2))
    return layer


def create_app_icon(size=1024):
    img = Image.new("RGB", (size, size), (10, 11, 13))
    draw = ImageDraw.Draw(img)

    for y in range(size):
        t = y / max(size - 1, 1)
        color = (
            lerp(10, 22, t),
            lerp(11, 24, t),
            lerp(13, 28, t),
        )
        draw.line([(0, y), (size, y)], fill=color)

    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    glow_draw.ellipse(
        [size * 0.18, size * 0.02, size * 0.9, size * 0.55],
        fill=(163, 199, 255, 26),
    )
    img = Image.alpha_composite(img.convert("RGBA"), glow)

    cx = size / 2
    card_w = size * 0.54
    card_h = size * 0.62
    radius = int(size * 0.055)

    cards = [
        (-0.14, -0.05, -8, (42, 47, 53, 245), (255, 255, 255, 38)),
        (0.12, -0.02, 7, (60, 67, 76, 245), (255, 255, 255, 44)),
        (0.0, 0.05, 0, (232, 237, 244, 255), (255, 255, 255, 70)),
    ]

    for dx, dy, angle, fill, outline in cards:
        x0 = cx - card_w / 2 + size * dx
        y0 = size * 0.21 + size * dy
        layer = rounded_layer(
            size,
            [x0, y0, x0 + card_w, y0 + card_h],
            radius,
            fill,
            outline=outline,
            width=max(2, int(size * 0.004)),
            angle=angle,
        )
        img = Image.alpha_composite(img, layer)

    overlay = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)

    front_x0 = cx - card_w / 2
    front_y0 = size * 0.26
    front_x1 = front_x0 + card_w
    front_y1 = front_y0 + card_h

    od.rounded_rectangle(
        [front_x0 + size * 0.07, front_y0 + size * 0.08, front_x1 - size * 0.07, front_y0 + size * 0.14],
        radius=int(size * 0.018),
        fill=(18, 21, 25, 56),
    )
    od.rounded_rectangle(
        [front_x0 + size * 0.07, front_y1 - size * 0.16, front_x1 - size * 0.07, front_y1 - size * 0.1],
        radius=int(size * 0.018),
        fill=(18, 21, 25, 48),
    )

    line_width = max(9, int(size * 0.034))
    start = (front_x0 + size * 0.13, front_y0 + size * 0.42)
    mid = (front_x0 + size * 0.28, front_y0 + size * 0.50)
    end = (front_x1 - size * 0.12, front_y0 + size * 0.36)
    accent = (163, 199, 255, 255)
    shadow = (11, 13, 16, 52)

    od.line([start, mid, end], fill=shadow, width=line_width + max(4, int(size * 0.008)), joint="curve")
    od.line([start, mid, end], fill=accent, width=line_width, joint="curve")

    arrow = [
        (end[0] - size * 0.075, end[1] - size * 0.045),
        end,
        (end[0] - size * 0.055, end[1] + size * 0.066),
    ]
    od.line(arrow, fill=accent, width=line_width, joint="curve")

    dot_r = size * 0.024
    od.ellipse([start[0] - dot_r, start[1] - dot_r, start[0] + dot_r, start[1] + dot_r], fill=(12, 15, 18, 255))
    od.ellipse([start[0] - dot_r * 0.58, start[1] - dot_r * 0.58, start[0] + dot_r * 0.58, start[1] + dot_r * 0.58], fill=accent)

    img = Image.alpha_composite(img, overlay)
    return img.convert("RGB")


def save_icon(size, path):
    icon = create_app_icon(size)
    icon.save(path, "PNG", optimize=True)


def generate_all_sizes():
    ICON_DIR.mkdir(parents=True, exist_ok=True)
    SITE_ICON.parent.mkdir(parents=True, exist_ok=True)

    sizes = [180, 167, 152, 120, 87, 80, 76, 60, 58, 40, 29, 20]

    for size in sizes:
        save_icon(size, ICON_DIR / f"icon_{size}x{size}.png")

    save_icon(1024, ICON_DIR / "Icon-1024.png")
    save_icon(512, SITE_ICON)

    print(f"Generated {len(sizes) + 2} icon files.")


if __name__ == "__main__":
    generate_all_sizes()
