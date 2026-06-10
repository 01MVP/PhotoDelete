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

    img = img.convert("RGBA")
    overlay = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)

    # Back card: a quiet photo stack signal.
    back_rect = [size * 0.29, size * 0.2, size * 0.77, size * 0.74]
    back = rounded_layer(
        size,
        back_rect,
        int(size * 0.055),
        (54, 60, 68, 255),
        outline=(255, 255, 255, 34),
        width=max(2, int(size * 0.004)),
        angle=7,
    )
    img = Image.alpha_composite(img, back)

    # Front card: slid left, so the icon reads as gesture-first.
    front_rect = [size * 0.18, size * 0.25, size * 0.66, size * 0.79]
    front = rounded_layer(
        size,
        front_rect,
        int(size * 0.06),
        (235, 239, 245, 255),
        outline=(255, 255, 255, 64),
        width=max(2, int(size * 0.004)),
        angle=-7,
    )
    img = Image.alpha_composite(img, front)

    # Minimal photo content lines.
    od.rounded_rectangle(
        [size * 0.29, size * 0.34, size * 0.52, size * 0.39],
        radius=int(size * 0.018),
        fill=(26, 29, 34, 72),
    )
    od.rounded_rectangle(
        [size * 0.28, size * 0.63, size * 0.56, size * 0.69],
        radius=int(size * 0.02),
        fill=(26, 29, 34, 62),
    )

    # Left-swipe track.
    line_width = max(8, int(size * 0.03))
    accent = (163, 199, 255, 255)
    od.line(
        [(size * 0.64, size * 0.52), (size * 0.49, size * 0.58), (size * 0.36, size * 0.55)],
        fill=(9, 11, 14, 54),
        width=line_width + max(4, int(size * 0.008)),
        joint="curve",
    )
    od.line(
        [(size * 0.64, size * 0.52), (size * 0.49, size * 0.58), (size * 0.36, size * 0.55)],
        fill=accent,
        width=line_width,
        joint="curve",
    )
    od.line(
        [(size * 0.43, size * 0.49), (size * 0.36, size * 0.55), (size * 0.43, size * 0.62)],
        fill=accent,
        width=line_width,
        joint="curve",
    )

    # Tiny delete mark, restrained but unmistakable.
    red = (255, 97, 90, 255)
    trash_x = size * 0.68
    trash_y = size * 0.63
    trash_w = size * 0.16
    trash_h = size * 0.18
    od.rounded_rectangle(
        [trash_x, trash_y + trash_h * 0.22, trash_x + trash_w, trash_y + trash_h],
        radius=int(size * 0.018),
        outline=red,
        width=max(6, int(size * 0.015)),
    )
    od.line(
        [(trash_x - trash_w * 0.08, trash_y + trash_h * 0.12), (trash_x + trash_w * 1.08, trash_y + trash_h * 0.12)],
        fill=red,
        width=max(6, int(size * 0.015)),
    )
    od.line(
        [(trash_x + trash_w * 0.32, trash_y), (trash_x + trash_w * 0.68, trash_y)],
        fill=red,
        width=max(5, int(size * 0.012)),
    )

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
