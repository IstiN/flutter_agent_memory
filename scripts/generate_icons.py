#!/usr/bin/env python3
"""Generate favicon and PWA icons from the network-graph logo."""

from pathlib import Path
from typing import Optional

from PIL import Image, ImageDraw

COLORS = {
    "purple": "#8B5CF6",
    "cyan": "#06B6D4",
    "pink": "#F472B6",
    "line": "#334155",
    "bg": "#0B0E14",
}

NODES = [
    (12, 12, 5, COLORS["purple"]),
    (32, 10, 4, COLORS["cyan"]),
    (28, 32, 4, COLORS["pink"]),
    (8, 30, 3, COLORS["purple"]),
]

EDGES = [
    (17, 13, 28, 11),
    (31, 14, 29, 28),
    (11, 27, 24, 31),
    (13, 16, 10, 27),
]

VIEWBOX = 40


def draw_logo(size: int, padding: float = 0.0, background: Optional[str] = COLORS["bg"], line_color: str = COLORS["line"]) -> Image.Image:
    """Render the logo at the requested size.

    ``padding`` is a fraction of the canvas to leave blank around the logo
    (used for maskable icons).
    """
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0) if background is None else background)
    draw = ImageDraw.Draw(img)

    usable = int(size * (1 - 2 * padding))
    offset = (size - usable) // 2
    scale = usable / VIEWBOX

    def tx(x: float, y: float) -> tuple[float, float]:
        return offset + x * scale, offset + y * scale

    line_width = max(1, int(2 * scale))
    for x1, y1, x2, y2 in EDGES:
        draw.line([tx(x1, y1), tx(x2, y2)], fill=line_color, width=line_width)

    for x, y, r, color in NODES:
        cx, cy = tx(x, y)
        radius = r * scale
        draw.ellipse(
            [(cx - radius, cy - radius), (cx + radius, cy + radius)],
            fill=color,
        )

    return img


def save_site_icons(root: Path) -> None:
    root.mkdir(parents=True, exist_ok=True)
    draw_logo(64).save(root / "favicon.png")
    draw_logo(180).save(root / "apple-touch-icon.png")


def save_demo_icons(root: Path) -> None:
    root.mkdir(parents=True, exist_ok=True)
    draw_logo(64).save(root.parent / "favicon.png")
    draw_logo(192).save(root / "Icon-192.png")
    draw_logo(512).save(root / "Icon-512.png")
    # Maskable icons need extra padding so the logo stays inside the safe zone.
    draw_logo(192, padding=0.18).save(root / "Icon-maskable-192.png")
    draw_logo(512, padding=0.18).save(root / "Icon-maskable-512.png")


if __name__ == "__main__":
    repo = Path(__file__).resolve().parents[1]
    save_site_icons(repo / "site")
    save_demo_icons(repo / "demo" / "web" / "icons")
    print("Icons generated:")
    for path in sorted((repo / "site").glob("*.png")):
        print(f"  {path.relative_to(repo)}")
    print(f"  {(repo / 'demo' / 'web' / 'favicon.png').relative_to(repo)}")
    for path in sorted((repo / "demo" / "web" / "icons").glob("*.png")):
        print(f"  {path.relative_to(repo)}")
