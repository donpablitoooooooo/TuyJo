#!/usr/bin/env python3
"""
Tuijo — App Store Screenshot Generator

Takes raw screenshots from screenshots/raw/ and generates professional
App Store images with iPhone frame, gradient background, and localized
marketing text.

Usage:
    python3 frame_screenshots.py                    # all locales
    python3 frame_screenshots.py --locale en        # single locale
    python3 frame_screenshots.py --locale en,it     # multiple locales
    python3 frame_screenshots.py --size 6.7         # iPhone 6.7" (default)
    python3 frame_screenshots.py --size 6.5         # iPhone 6.5"
    python3 frame_screenshots.py --size 5.5         # iPhone 5.5"

Input:  screenshots/raw/01_chat.png, 02_voice_call.png, ...
Output: screenshots/output/{locale}/01_chat.png, ...
"""

import json
import os
import sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter

# ---------------------------------------------------------------------------
# Directory setup
# ---------------------------------------------------------------------------
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_PATH = os.path.join(SCRIPT_DIR, "config.json")
RAW_DIR = os.path.join(SCRIPT_DIR, "raw")
OUTPUT_DIR = os.path.join(SCRIPT_DIR, "output")
FONTS_DIR = os.path.join(SCRIPT_DIR, "fonts")

# ---------------------------------------------------------------------------
# App Store canvas sizes  (width x height)
# ---------------------------------------------------------------------------
CANVAS_SIZES = {
    "6.7": (1290, 2796),   # iPhone 15 Pro Max / 16 Pro Max
    "6.5": (1284, 2778),   # iPhone 14 Plus / 15 Plus
    "5.5": (1242, 2208),   # iPhone 8 Plus (still accepted)
}

# ---------------------------------------------------------------------------
# Brand colors
# ---------------------------------------------------------------------------
TEAL       = (59, 168, 176)
DARK_TEAL  = (20, 90, 96)
WHITE      = (255, 255, 255)
WHITE_80   = (255, 255, 255, 204)
BLACK      = (0, 0, 0)
SHADOW     = (0, 0, 0, 50)

# ---------------------------------------------------------------------------
# Phone frame proportions (relative to canvas width)
# ---------------------------------------------------------------------------
PHONE_WIDTH_RATIO   = 0.82     # phone width = 82% of canvas
PHONE_BEZEL         = 14       # px — thin bezel around screen
PHONE_CORNER_RADIUS = 56       # px — outer corners
SCREEN_CORNER_RADIUS = 44      # px — inner screen corners
ISLAND_W            = 140      # Dynamic Island width
ISLAND_H            = 34       # Dynamic Island height
ISLAND_Y_OFFSET     = 14       # from top of screen


# ===== HELPERS ==============================================================

def load_config():
    with open(CONFIG_PATH) as f:
        return json.load(f)


def get_font(size, bold=False):
    """Return the best available font at the requested size."""
    if bold:
        candidates = [
            os.path.join(FONTS_DIR, "InterDisplay-Bold.ttf"),
            os.path.join(FONTS_DIR, "InterDisplay-SemiBold.ttf"),
            "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
            "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
        ]
    else:
        candidates = [
            os.path.join(FONTS_DIR, "InterDisplay-Medium.ttf"),
            os.path.join(FONTS_DIR, "InterDisplay-Regular.ttf"),
            "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
            "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
        ]
    for path in candidates:
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def create_gradient(width, height, color_top, color_bottom):
    """Fast vertical gradient using a 1px-wide strip scaled horizontally."""
    strip = Image.new("RGB", (1, height))
    for y in range(height):
        t = y / max(height - 1, 1)
        r = int(color_top[0] + (color_bottom[0] - color_top[0]) * t)
        g = int(color_top[1] + (color_bottom[1] - color_top[1]) * t)
        b = int(color_top[2] + (color_bottom[2] - color_top[2]) * t)
        strip.putpixel((0, y), (r, g, b))
    return strip.resize((width, height), Image.NEAREST)


def rounded_rect_mask(width, height, radius):
    """Return an L-mode mask with rounded corners."""
    mask = Image.new("L", (width, height), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, width - 1, height - 1), radius=radius, fill=255
    )
    return mask


def draw_centered_text(draw, text, y, font, fill, canvas_width):
    """Draw horizontally-centred text. Returns the bottom y coordinate."""
    bbox = draw.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    x = (canvas_width - tw) // 2
    draw.text((x, y), text, font=font, fill=fill)
    return y + th


# ===== PHONE FRAME ==========================================================

def create_phone_frame(screenshot_path, phone_width):
    """
    Build an iPhone-style device frame around the raw screenshot.
    Returns an RGBA image of the phone (with transparent background).
    """
    screenshot = Image.open(screenshot_path).convert("RGBA")

    screen_w = phone_width - PHONE_BEZEL * 2
    screen_h = int(screen_w * (screenshot.height / screenshot.width))
    phone_h = screen_h + PHONE_BEZEL * 2

    screenshot = screenshot.resize((screen_w, screen_h), Image.LANCZOS)

    # --- canvas (with room for shadow) ---
    pad = 30  # shadow spread
    frame = Image.new("RGBA", (phone_width + pad * 2, phone_h + pad * 2), (0, 0, 0, 0))
    draw = ImageDraw.Draw(frame)

    ox, oy = pad, pad  # origin offset for body

    # --- shadow (slightly offset, blurred) ---
    shadow_layer = Image.new("RGBA", frame.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow_layer)
    sd.rounded_rectangle(
        (ox + 4, oy + 8, ox + phone_width - 1 + 4, oy + phone_h - 1 + 8),
        radius=PHONE_CORNER_RADIUS,
        fill=(0, 0, 0, 70),
    )
    shadow_layer = shadow_layer.filter(ImageFilter.GaussianBlur(radius=18))
    frame = Image.alpha_composite(frame, shadow_layer)
    draw = ImageDraw.Draw(frame)

    # --- phone body (dark bezel) ---
    draw.rounded_rectangle(
        (ox, oy, ox + phone_width - 1, oy + phone_h - 1),
        radius=PHONE_CORNER_RADIUS,
        fill=(30, 30, 30, 255),
    )

    # --- subtle metallic edge highlight ---
    draw.rounded_rectangle(
        (ox + 1, oy + 1, ox + phone_width - 2, oy + phone_h - 2),
        radius=PHONE_CORNER_RADIUS - 1,
        outline=(80, 80, 80, 100),
        width=1,
    )

    # --- paste screenshot with rounded corners ---
    scr_x = ox + PHONE_BEZEL
    scr_y = oy + PHONE_BEZEL
    scr_mask = rounded_rect_mask(screen_w, screen_h, SCREEN_CORNER_RADIUS)
    frame.paste(screenshot, (scr_x, scr_y), scr_mask)

    # --- Dynamic Island ---
    island_x = ox + (phone_width - ISLAND_W) // 2
    island_y = scr_y + ISLAND_Y_OFFSET
    draw.rounded_rectangle(
        (island_x, island_y, island_x + ISLAND_W, island_y + ISLAND_H),
        radius=ISLAND_H // 2,
        fill=(0, 0, 0, 255),
    )

    return frame


# ===== MAIN GENERATOR =======================================================

def generate_screenshot(
    screenshot_path, headline, subtitle, output_path, canvas_w, canvas_h
):
    """Compose the final App Store screenshot image.

    Layout: text at top, phone large and bleeding off the bottom edge.
    This is the standard App Store screenshot style.
    """

    # --- gradient background ---
    bg = create_gradient(canvas_w, canvas_h, TEAL, DARK_TEAL).convert("RGBA")

    # --- phone frame (full size, will overflow bottom) ---
    phone_w = int(canvas_w * PHONE_WIDTH_RATIO)
    phone = create_phone_frame(screenshot_path, phone_w)

    # --- fonts ---
    font_headline = get_font(int(canvas_w * 0.058), bold=True)
    font_subtitle = get_font(int(canvas_w * 0.032))

    # --- draw text at top ---
    draw = ImageDraw.Draw(bg)
    top_margin = int(canvas_h * 0.05)

    y = top_margin
    y = draw_centered_text(draw, headline, y, font_headline, WHITE, canvas_w)
    y += int(canvas_h * 0.012)
    y = draw_centered_text(draw, subtitle, y, font_subtitle, WHITE_80, canvas_w)
    y += int(canvas_h * 0.03)

    # --- paste phone: starts right after text, overflows bottom ---
    phone_x = (canvas_w - phone.width) // 2
    phone_y = y

    # Composite onto a larger canvas so we don't lose the shadow,
    # then crop to the App Store dimensions.
    composite = Image.new("RGBA", (canvas_w, phone_y + phone.height), (0, 0, 0, 0))
    composite.paste(bg, (0, 0))
    composite.paste(phone, (phone_x, phone_y), phone)

    # Crop to canvas size (cuts off the phone at the bottom)
    final = composite.crop((0, 0, canvas_w, canvas_h))

    # --- save ---
    final.convert("RGB").save(output_path, "PNG", optimize=True)


# ===== CLI ===================================================================

def main():
    config = load_config()

    # parse --locale
    requested_locales = list(config["locales"].keys())
    if "--locale" in sys.argv:
        idx = sys.argv.index("--locale") + 1
        requested_locales = sys.argv[idx].split(",")

    # parse --size
    size_key = "6.7"
    if "--size" in sys.argv:
        idx = sys.argv.index("--size") + 1
        size_key = sys.argv[idx]
    canvas_w, canvas_h = CANVAS_SIZES.get(size_key, CANVAS_SIZES["6.7"])

    print(f"Canvas: {canvas_w}x{canvas_h} (iPhone {size_key}\")")
    print(f"Locales: {', '.join(requested_locales)}")
    print(f"Raw dir: {RAW_DIR}")
    print()

    generated = 0
    missing = 0

    for locale in requested_locales:
        if locale not in config["locales"]:
            print(f"[SKIP] Unknown locale: {locale}")
            continue

        locale_texts = config["locales"][locale]
        locale_out = os.path.join(OUTPUT_DIR, locale)
        os.makedirs(locale_out, exist_ok=True)

        for ss in config["screenshots"]:
            raw_file = os.path.join(RAW_DIR, ss["file"])
            if not os.path.exists(raw_file):
                print(f"  [MISS] {ss['file']} — put raw screenshot in screenshots/raw/")
                missing += 1
                continue

            texts = locale_texts[ss["id"]]
            out_file = os.path.join(locale_out, f"{ss['id']}.png")

            generate_screenshot(
                raw_file,
                texts["headline"],
                texts["subtitle"],
                out_file,
                canvas_w,
                canvas_h,
            )
            generated += 1
            print(f"  [OK]   {locale}/{ss['id']}.png")

    print()
    print(f"Done: {generated} generated, {missing} missing raw files.")
    if missing:
        print("Tip: add raw screenshots to screenshots/raw/ and re-run.")


if __name__ == "__main__":
    main()
