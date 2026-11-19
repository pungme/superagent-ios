#!/usr/bin/env python3
"""
Turn the raw simulator screenshots in screenshots/{iphone,ipad} into the App Store
set in screenshots/store/: a benefit headline above a framed screen, on dark.

  iPhone 6.9"   1320 x 2868   (iPhone 17 Pro Max)
  iPhone 6.3"   1206 x 2622   (the same images scaled: the slot App Store Connect asks for first)
  iPad 13"      2064 x 2752   (iPad Pro 13")

The first three are what people see in search results, so they carry the story:
what it is, the day, and the one tap that makes it safe. Run from this folder:
  python3 make-screenshots.py
"""
from pathlib import Path
from PIL import Image
from store_style import background, headline, paste_phone

# One colour per screen: (glow, accent word). The strip reads as a set, not a copy.
THEMES = [((70, 96, 255), (150, 176, 255)), ((140, 80, 255), (196, 160, 255)), ((30, 170, 140), (120, 232, 200)),
          ((235, 120, 60), (255, 184, 128)), ((220, 70, 140), (255, 154, 200)), ((40, 140, 255), (130, 205, 255))]

HERE = Path(__file__).parent
RAW = HERE / "screenshots"
OUT = RAW / "store"


def compose(raw, title, sub, canvas, phone_w, name, title_size, top_pad, phone_top, theme):
    w, h = canvas
    img = background(w, h, glow_at=(w // 2, phone_top + round(phone_w * 1.1)), glow_r=round(w * 0.62), glow=theme[0])
    headline(img, title, sub, top_pad, title_size, accent=theme[1])
    # The phone runs off the bottom edge: bigger on screen, and it reads as a real device in hand.
    paste_phone(img, RAW / raw, (w - phone_w) // 2, phone_top, phone_w, halo=theme[0], real=raw.startswith("iphone/"))
    OUT.mkdir(parents=True, exist_ok=True)
    img.convert("RGB").save(OUT / name, optimize=True)


IPHONE = [
    ("iphone/f-chat.png", "Your coding agents,\n*in your pocket*", "Follow, answer and approve from anywhere", "iphone-1-chat.png"),
    ("iphone/d-01-today.png", "Your whole day,\n*on one screen*", "Calendar, to-dos and agents together", "iphone-2-today.png"),
    ("iphone/g-approval.png", "Approve with\n*one tap*", "Commands wait for your yes", "iphone-3-approve.png"),
    ("iphone/f-chat-page.png", "Watch it work,\n*live*", "The Mac's browser floats over the chat", "iphone-4-page.png"),
    ("iphone/e-remote-active.png", "Take over\n*your Mac*", "Screen, trackpad and keyboard, from the couch", "iphone-5-remote.png"),
    ("iphone/d-02-projects.png", "Every project,\n*every chat*", "Pinned, recent and everything between", "iphone-6-projects.png"),
]
IPAD = [
    ("ipad/b-chat-page.png", "Your Mac's agents,\n*on a bigger screen*", "Projects, the conversation and the page side by side", "ipad-1-chat.png"),
    ("ipad/c-approval.png", "Approve with\n*one tap*", "Commands wait for your yes", "ipad-2-approve.png"),
    ("ipad/d-remote.png", "Take over\n*your Mac*", "Screen, trackpad and keyboard, from the couch", "ipad-3-remote.png"),
]

if __name__ == "__main__":
    for i, (raw, title, sub, name) in enumerate(IPHONE):
        compose(raw, title, sub, (1320, 2868), 1130, name, 112, 150, 620, THEMES[i])
    for raw, title, sub, name in IPAD:
        compose(raw, title, sub, (2064, 2752), 1500, name, 168, 190, 840, THEMES[{'ipad-1-chat.png': 0, 'ipad-2-approve.png': 2, 'ipad-3-remote.png': 4}[name]])
    # iPhone Duo's own slot: portrait 2007 x 2853, squarer than a phone.
    duo = OUT / "iphone-duo"
    duo.mkdir(parents=True, exist_ok=True)
    for i, (raw, title, sub, name) in enumerate(IPHONE):
        compose(raw, title, sub, (2007, 2853), 1200, f"duo-{name}", 150, 150, 640, THEMES[i])
        (OUT / f"duo-{name}").replace(duo / name)
    small = OUT / "iphone-6.3"
    small.mkdir(parents=True, exist_ok=True)
    for _, _, _, name in IPHONE:
        Image.open(OUT / name).convert("RGB").resize((1206, 2622), Image.LANCZOS).save(small / name, optimize=True)
    print("wrote", len(IPHONE) + len(IPAD), "images to", OUT, "and", len(IPHONE), "to", small)
