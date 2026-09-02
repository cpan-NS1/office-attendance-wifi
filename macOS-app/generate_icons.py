#!/usr/bin/env python3
"""
Generate macOS app icon set from LOGO.png.

How macOS Dock sizing works for non-App-Store apps:
  - macOS does NOT apply rounded corners at runtime for regular .app bundles.
  - The icon file must encode its own shape with transparent corners.
  - The Dock allocates a fixed slot and scales the icon's bounding box to fill it.
  - If the icon PNG has no transparent margin, the artwork fills the slot
    edge-to-edge and looks larger than icons that have natural padding.
  - System icons (Xcode, Safari, etc.) embed their artwork at ~90% of the
    canvas with ~5% transparent margin on each side, which is what gives
    them the consistent visual weight in the Dock.

Strategy used here:
  1. Resize the source logo to 90% of the canvas (5% margin each side).
  2. Composite it onto a transparent canvas of the target size.
  3. Apply a rounded-rectangle mask (radius ≈ 22.37% of the inner artwork size,
     which equals ~20.1% of the full canvas) with anti-aliased edges.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter
import PIL.ImageChops as chops

SRC = Path(__file__).parent / "LOGO.png"
OUT = Path(__file__).parent / "OfficeAttendance/Assets.xcassets/AppIcon.appiconset"

ICONS = [
    ("icon_16x16.png",        16),
    ("icon_16x16@2x.png",     32),
    ("icon_32x32.png",        32),
    ("icon_32x32@2x.png",     64),
    ("icon_64x64.png",        64),
    ("icon_128x128.png",      128),
    ("icon_128x128@2x.png",   256),
    ("icon_256x256.png",      256),
    ("icon_256x256@2x.png",   512),
    ("icon_512x512.png",      512),
    ("icon_512x512@2x.png",   1024),
    ("icon_1024x1024.png",    1024),
]

# 10% transparent margin on each side → artwork occupies 80% of canvas
MARGIN_RATIO = 0.10

# Corner radius as a fraction of the *artwork* size (not the full canvas).
# ~22.37% matches the macOS squircle shape used by App Store icons,
# which is what most system icons replicate.
ARTWORK_RADIUS_RATIO = 0.2237

# Two-layer drop shadow matching CSS:
#   drop-shadow(0 1px 1px rgba(0,0,0,0.18))
#   drop-shadow(0 2px 4px rgba(0,0,0,0.14))
#
# CSS px values are relative to the icon at ~128px display size.
# Scale factor to canvas size: canvas_px / 128.
# offset_y and blur are kept as ratios of canvas size for all icon sizes.
#   layer 1: offset_y=1/128≈0.0078  blur=1/128≈0.0078  opacity=0.18*255≈46
#   layer 2: offset_y=2/128≈0.0156  blur=4/128≈0.0313  opacity=0.14*255≈36
SHADOWS = [
    dict(offset_y_ratio=0.0078, blur_ratio=0.0078, opacity=46),
    dict(offset_y_ratio=0.0156, blur_ratio=0.0313, opacity=36),
]


def make_rounded_mask(size: int, radius: int) -> Image.Image:
    """Greyscale rounded-rect mask at `size`×`size` with 4× supersampling."""
    scale = 4
    big, r = size * scale, radius * scale
    mask = Image.new("L", (big, big), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, big - 1, big - 1], radius=r, fill=255)
    return mask.resize((size, size), Image.LANCZOS)


def make_shadow_layer(artwork: Image.Image, canvas_size: int,
                      offset_y: int, blur_r: int, opacity: int) -> Image.Image:
    """Return a canvas-sized RGBA image with a single blurred drop-shadow layer."""
    margin = (canvas_size - artwork.width) // 2

    # Silhouette of the artwork placed at its final position on the canvas
    silhouette = Image.new("L", (canvas_size, canvas_size), 0)
    silhouette.paste(artwork.split()[3], (margin, margin))

    # Blur → scale to target opacity
    shadow_alpha = silhouette.filter(ImageFilter.GaussianBlur(radius=max(blur_r, 1)))
    shadow_alpha = shadow_alpha.point(lambda p: int(p * opacity / 255))

    # Black fill + blurred alpha, shifted downward
    black = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 255))
    black.putalpha(shadow_alpha)
    shifted = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    shifted.paste(black, (0, offset_y))
    return shifted


def generate():
    src = Image.open(SRC).convert("RGBA")

    # Centre-crop to square
    w, h = src.size
    side = min(w, h)
    src = src.crop(((w - side) // 2, (h - side) // 2,
                    (w + side) // 2, (h + side) // 2))

    for filename, px in ICONS:
        margin   = max(1, round(px * MARGIN_RATIO))
        art_size = px - 2 * margin
        radius   = max(1, round(art_size * ARTWORK_RADIUS_RATIO))

        # Resize artwork and apply rounded-rect mask
        artwork  = src.resize((art_size, art_size), Image.LANCZOS)
        mask     = make_rounded_mask(art_size, radius)
        r, g, b, a = artwork.split()
        artwork  = Image.merge("RGBA", (r, g, b, chops.multiply(a, mask)))

        # Composite: shadow layers first (back to front), then artwork on top
        canvas = Image.new("RGBA", (px, px), (0, 0, 0, 0))
        for s in SHADOWS:
            offset_y = max(1, round(px * s["offset_y_ratio"]))
            blur_r   = max(1, round(px * s["blur_ratio"]))
            canvas   = Image.alpha_composite(
                canvas, make_shadow_layer(artwork, px, offset_y, blur_r, s["opacity"])
            )
        artwork_layer = Image.new("RGBA", (px, px), (0, 0, 0, 0))
        artwork_layer.paste(artwork, (margin, margin), artwork)
        canvas = Image.alpha_composite(canvas, artwork_layer)

        canvas.save(OUT / filename, "PNG", optimize=True)
        print(f"  ✓ {filename:30s} canvas={px}px  art={art_size}px  shadow_blur={blur_r}px")

    print("\nDone.")


if __name__ == "__main__":
    generate()
