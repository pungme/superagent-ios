#!/usr/bin/env python3
"""
Turn the raw simulator screenshots in screenshots/{iphone,ipad} into the App Store
set in screenshots/store/: a headline above the screen, on a soft background.

  iPhone 6.9"   1320 x 2868   (iPhone 17 Pro Max)
  iPhone 6.3"   1206 x 2622   (the same images scaled: the slot App Store Connect asks for first)
  iPad 13"      2064 x 2752   (iPad Pro 13")

Run from this folder:  python3 make-screenshots.py
The raw captures come from the simulator with the demo Mac (launch arguments in
README.md, "Store screenshots").
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = Path(__file__).parent
RAW = HERE / "screenshots"
OUT = RAW / "store"
SF = "/System/Library/Fonts/SFNS.ttf"


def font(size: int, weight: str = "Bold") -> ImageFont.FreeTypeFont:
    f = ImageFont.truetype(SF, size)
    f.set_variation_by_name(weight)
    return f


def background(w: int, h: int) -> Image.Image:
    top, bottom = (250, 250, 252), (232, 233, 240)
    img = Image.new("RGB", (w, h), top)
    px = ImageDraw.Draw(img)
    for y in range(h):
        t = y / (h - 1)
        px.line([(0, y), (w, y)], fill=tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return img


def rounded(img: Image.Image, radius: int) -> Image.Image:
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, img.width - 1, img.height - 1], radius, fill=255)
    out = img.convert("RGBA")
    out.putalpha(mask)
    return out


def compose(raw: Path, title: str, sub: str, canvas: tuple[int, int], shot_w: int, name: str) -> None:
    w, h = canvas
    img = background(w, h)
    d = ImageDraw.Draw(img)
    scale = w / 1320
    big, small = font(round(112 * scale)), font(round(54 * scale), "Medium")
    y = round(150 * scale)
    for line in title.split("\n"):
        tw = d.textlength(line, font=big)
        d.text(((w - tw) / 2, y), line, font=big, fill=(17, 18, 23))
        y += round(128 * scale)
    if sub:
        tw = d.textlength(sub, font=small)
        d.text(((w - tw) / 2, y + round(14 * scale)), sub, font=small, fill=(108, 110, 120))
    shot = Image.open(raw).convert("RGB")
    sh = round(shot.height * shot_w / shot.width)
    shot = shot.resize((shot_w, sh), Image.LANCZOS)
    radius = round(shot_w * 0.075)
    x, top = (w - shot_w) // 2, h - sh - round(70 * scale)
    shadow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([x, top + 26, x + shot_w, top + sh + 26], radius, fill=(20, 22, 40, 70))
    img = Image.alpha_composite(img.convert("RGBA"), shadow.filter(ImageFilter.GaussianBlur(34)))
    card = rounded(shot, radius)
    img.alpha_composite(card, (x, top))
    ImageDraw.Draw(img).rounded_rectangle([x, top, x + shot_w, top + sh], radius, outline=(200, 202, 212, 255), width=3)
    OUT.mkdir(parents=True, exist_ok=True)
    img.convert("RGB").save(OUT / name, optimize=True)


IPHONE = [
    ("iphone/d-01-today.png", "Your whole day,\non one screen", "Calendar, to-dos and agents together", "iphone-1-today.png"),
    ("iphone/f-chat.png", "Follow your agent\nfrom anywhere", "See every step, answer its questions", "iphone-2-chat.png"),
    ("iphone/g-approval.png", "Approve what it asks,\nor say no", "Commands wait for your yes", "iphone-3-approve.png"),
    ("iphone/f-chat-page.png", "See the page\nit is working on", "The Mac's browser, floating over the chat", "iphone-4-page.png"),
    ("iphone/e-remote-active.png", "Take over your Mac\nfrom the couch", "Your screen, trackpad and keyboard", "iphone-5-remote.png"),
    ("iphone/d-02-projects.png", "Every project\nand chat, in reach", "Pinned, recent and everything in between", "iphone-6-projects.png"),
]
IPAD = [
    ("ipad/b-chat-page.png", "Your Mac's agents,\non a bigger screen", "Projects beside the conversation and the page", "ipad-1-chat.png"),
    ("ipad/c-approval.png", "Approve what it asks,\nor say no", "Commands wait for you", "ipad-2-approve.png"),
    ("ipad/d-remote.png", "Take over your Mac\nfrom the couch", "Your screen, trackpad and keyboard", "ipad-3-remote.png"),
]

if __name__ == "__main__":
    for raw, title, sub, name in IPHONE:
        compose(RAW / raw, title, sub, (1320, 2868), 1010, name)
    for raw, title, sub, name in IPAD:
        compose(RAW / raw, title, sub, (2064, 2752), 1380, name)
    small = OUT / "iphone-6.3"
    small.mkdir(parents=True, exist_ok=True)
    for _, _, _, name in IPHONE:
        Image.open(OUT / name).convert("RGB").resize((1206, 2622), Image.LANCZOS).save(small / name, optimize=True)
    print("wrote", len(IPHONE) + len(IPAD), "images to", OUT, "and", len(IPHONE), "to", small)
