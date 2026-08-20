"""Draws the MiDoctor launcher icon.

Generated rather than hand-drawn so the mark, the colours and every derived
size stay in one place — the alternative is a folder of PNGs nobody can
regenerate and which drift apart the first time the brand colour changes.

The mark is a medical cross whose vertical bar steps down into a pulse line:
"care" and "a reading" in one shape, legible at 48px where a literal
stethoscope or heart is mud.

    python tool/make_icon.py
"""

import os

from PIL import Image, ImageDraw

# The product's teal, already used by the splash screen and the web manifest.
TEAL = (14, 131, 136, 255)
TEAL_DEEP = (9, 94, 98, 255)
WHITE = (255, 255, 255, 255)

# Drawn large and downsampled, which is far cheaper than anti-aliasing by hand.
CANVAS = 1024


def draw_mark(size: int = CANVAS, *, background: bool = True) -> Image.Image:
    """A centred medical cross with a pulse cut through it as negative space.

    The pulse is *removed* from the cross rather than drawn beside it, so the
    silhouette stays a clean cross at 48px — where an added stroke turns to mud
    — and only resolves into a reading when the icon is large enough to show it.
    """
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    u = size / 1024  # authored against a 1024 grid

    if background:
        # A vertical wash rather than a flat fill: flat reads as a sticker on a
        # white launcher, and a stronger gradient bands at small sizes.
        for y in range(size):
            t = y / size
            d.line(
                [(0, y), (size, y)],
                fill=tuple(
                    int(a + (b - a) * t) for a, b in zip(TEAL, TEAL_DEEP)
                ),
            )

    c = size / 2
    arm = 132 * u    # half-thickness of a bar
    reach = 340 * u  # half-length of a bar
    radius = 44 * u

    d.rounded_rectangle(
        [c - reach, c - arm, c + reach, c + arm], radius=radius, fill=WHITE
    )
    d.rounded_rectangle(
        [c - arm, c - reach, c + arm, c + reach], radius=radius, fill=WHITE
    )

    # Cut the trace out of the horizontal bar. On a transparent foreground there
    # is no background to cut *to*, so the notch is skipped and the mark stays a
    # plain cross — which is what an adaptive-icon mask wants anyway.
    if background:
        stroke = int(round(58 * u))
        cut = [
            (c - reach - stroke, c),
            (c - 150 * u, c),
            (c - 78 * u, c + 84 * u),
            (c - 6 * u, c - 96 * u),
            (c + 66 * u, c + 40 * u),
            (c + 132 * u, c),
            (c + reach + stroke, c),
        ]
        # Sampled from the wash at the centre line so the cut matches the
        # background it is pretending to reveal.
        mid = tuple(int(a + (b - a) * 0.5) for a, b in zip(TEAL, TEAL_DEEP))
        d.line(cut, fill=mid, width=stroke, joint="curve")

    return img


def rounded(img: Image.Image, radius_ratio: float = 0.22) -> Image.Image:
    """Clips to a squircle-ish rounded square, for platforms that do not mask."""
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, img.size[0] - 1, img.size[1] - 1],
        radius=int(img.size[0] * radius_ratio),
        fill=255,
    )
    out = img.copy()
    out.putalpha(mask)
    return out


def save(img: Image.Image, path: str, size: int) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.resize((size, size), Image.LANCZOS).save(path, "PNG")
    print(f"  {path}  {size}x{size}")


def main() -> None:
    full = draw_mark()

    # The source `flutter_launcher_icons` reads.
    save(full, "assets/icon/icon.png", 1024)
    # Adaptive foreground: the mark alone, inset so Android's mask cannot clip
    # it. The system draws the background from the colour in pubspec.
    fg = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    inner = draw_mark(int(CANVAS * 0.62), background=False)
    fg.paste(inner, (int(CANVAS * 0.19), int(CANVAS * 0.19)), inner)
    save(fg, "assets/icon/icon_foreground.png", 1024)

    # Web needs its own, already masked, plus a favicon.
    save(rounded(full), "web/icons/Icon-192.png", 192)
    save(rounded(full), "web/icons/Icon-512.png", 512)
    save(full, "web/icons/Icon-maskable-192.png", 192)
    save(full, "web/icons/Icon-maskable-512.png", 512)
    save(rounded(full), "web/favicon.png", 32)

    print("done")


if __name__ == "__main__":
    main()
