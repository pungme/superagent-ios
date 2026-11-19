#!/usr/bin/env python3
"""
The product page artwork App Store Connect asks for besides screenshots, in the
same look as make-screenshots.py (run that first for the folders):

  Header          3840 x 1646   (also accepted: 5244 x 2950)
  Search results  3840 x 2560   (also accepted: 1920 x 1280, 5244 x 2950)

Output: screenshots/store/header.png and search-results.png.
Keep the important parts in the middle: the header is cropped differently on
different devices and orientations.
"""
from pathlib import Path
from PIL import Image, ImageDraw
from store_style import ACCENT, INK, MUTED, background, font, headline, paste_phone

HERE = Path(__file__).parent
RAW = HERE / "screenshots"
OUT = RAW / "store"
ICON = HERE.parent.parent / "SuperAgent/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"


def icon(size):
    ic = Image.open(ICON).convert("RGBA").resize((size, size), Image.LANCZOS)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size - 1, size - 1], round(size * 0.225), fill=255)
    ic.putalpha(mask)
    return ic


def header():
    w, h = 3840, 1646
    img = background(w, h, glow_at=(2900, 900), glow_r=1100)
    img.alpha_composite(icon(190), (640, 330))
    headline(img, "Your coding agents,\n*in your pocket*", "Follow, answer and approve from your iPhone.", 590, 170, 68, align="left", x=640)
    # Two screens, cropped by the bottom edge, on the right of the middle.
    paste_phone(img, RAW / "iphone/d-01-today.png", 2350, 210, 680, real=True)
    paste_phone(img, RAW / "iphone/f-chat.png", 2900, 120, 720, real=True)
    OUT.mkdir(parents=True, exist_ok=True)
    img.convert("RGB").save(OUT / "header.png", optimize=True)


def search_results():
    w, h = 3840, 2560
    img = background(w, h, glow_at=(w // 2, 1700), glow_r=1500)
    ic = icon(250)
    img.alpha_composite(ic, ((w - 250) // 2, 150))
    headline(img, "Superagent", None, 470, 220)
    d = ImageDraw.Draw(img)
    sub = "Your Mac's coding agents, in your pocket"
    f = font(84, "Medium")
    d.text(((w - d.textlength(sub, font=f)) / 2, 740), sub, font=f, fill=MUTED)
    paste_phone(img, RAW / "iphone/g-approval.png", 560, 1010, 760, real=True)
    paste_phone(img, RAW / "iphone/d-01-today.png", 1530, 930, 780, real=True)
    paste_phone(img, RAW / "iphone/f-chat.png", 2520, 1010, 760, real=True)
    OUT.mkdir(parents=True, exist_ok=True)
    img.convert("RGB").save(OUT / "search-results.png", optimize=True)


if __name__ == "__main__":
    header()
    search_results()
    print("wrote", OUT / "header.png", "and", OUT / "search-results.png")
