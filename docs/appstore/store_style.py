"""Shared look for the App Store artwork: the landing page's (superagent.computer), an Apple-style
product page: white and #f5f5f7 bands, #1d1d1f headlines in SF Display semibold, #6e6e73
subtitles, one blue (#0071e3), the device big and unframed by anything but itself."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

FRAME = Path(__file__).parent / "frame"

SF = "/System/Library/Fonts/SFNS.ttf"
INK = (29, 29, 31)         # --ink
ACCENT = (0, 113, 227)     # --blue
MUTED = (110, 110, 115)    # --ink-2
GLOW = (0, 113, 227)
BANDS = ((255, 255, 255), (245, 245, 247))  # white and the landing page's .alt


def font(size, weight="Bold"):
    f = ImageFont.truetype(SF, size)
    f.set_variation_by_name(weight)
    return f


def background(w, h, glow_at=None, glow_r=None, glow=None, band=0):
    """A flat landing-page band: white, or #f5f5f7 for the alternate. No glow: Apple's pages have none."""
    return Image.new("RGBA", (w, h), BANDS[band % 2] + (255,))


def framed_phone(path, width, bezel=None):
    """The screen with a dark bezel and a thin lit edge, like the device."""
    shot = Image.open(path).convert("RGB")
    bezel = bezel or max(10, round(width * 0.02))
    inner_w = width - 2 * bezel
    inner_h = round(shot.height * inner_w / shot.width)
    shot = shot.resize((inner_w, inner_h), Image.LANCZOS)
    w, h = width, inner_h + 2 * bezel
    outer_r = round(width * 0.115)
    inner_r = outer_r - bezel
    card = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(card)
    d.rounded_rectangle([0, 0, w - 1, h - 1], outer_r, fill=(6, 7, 10, 255), outline=(78, 84, 102, 255), width=max(3, bezel // 4))
    mask = Image.new("L", shot.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, shot.width - 1, shot.height - 1], inner_r, fill=255)
    screen = shot.convert("RGBA")
    screen.putalpha(mask)
    card.alpha_composite(screen, (bezel, bezel))
    return card, outer_r


def real_iphone(path, width):
    """
    The screen in Apple's own iPhone 17 Pro Max frame (Xcode's DeviceKit art, rendered
    to frame/ by pdf2png.swift): side buttons under the body, the screen clipped to the
    display's rounded shape, the frame on top, and the Dynamic Island. Everything is
    laid out at 3x (1422 x 2970 body, screen inset 51 px) and scaled to `width`.
    """
    body = Image.open(FRAME / "iphone-17-pro-max-frame.png").convert("RGBA")
    bw, bh = body.size
    inset = 51
    margin = 24  # the buttons stand 8 pt (24 px) out of the body
    W, H = bw + 2 * margin, bh
    card = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    # Side buttons, beneath the body: action and volume left, power right.
    for name, side, y_pt in (("btn-action", "l", 180), ("btn-volume", "l", 268), ("btn-volume", "l", 354), ("btn-power", "r", 293)):
        b = Image.open(FRAME / f"{name}.png").convert("RGBA")
        bx = margin - b.width // 2 if side == "l" else margin + bw - b.width // 2
        card.alpha_composite(b, (bx, y_pt * 3))
    # The screen, clipped to the display's own corners.
    sw, sh = bw - 2 * inset, bh - 2 * inset
    shot = Image.open(path).convert("RGB").resize((sw, sh), Image.LANCZOS).convert("RGBA")
    mask = Image.new("L", (sw * 2, sh * 2), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, sw * 2 - 1, sh * 2 - 1], 190 * 2, fill=255)
    mask = mask.resize((sw, sh), Image.LANCZOS)
    shot.putalpha(mask)
    card.alpha_composite(shot, (margin + inset, inset))
    # The frame over it, its fill cut away where the screen shows.
    hole = Image.new("L", (bw * 2, bh * 2), 255)
    ImageDraw.Draw(hole).rounded_rectangle([inset * 2, inset * 2, (bw - inset) * 2 - 1, (bh - inset) * 2 - 1], 190 * 2, fill=0)
    hole = hole.resize((bw, bh), Image.LANCZOS)
    a = body.split()[3]
    body.putalpha(Image.composite(a, Image.new("L", (bw, bh), 0), hole))
    card.alpha_composite(body, (margin, 0))
    # The Dynamic Island: 125 x 37 pt, 11 pt below the screen's top.
    isl = Image.new("L", (125 * 6, 37 * 6), 0)
    ImageDraw.Draw(isl).rounded_rectangle([0, 0, 125 * 6 - 1, 37 * 6 - 1], 37 * 3, fill=255)
    isl = isl.resize((375, 111), Image.LANCZOS)
    black = Image.new("RGBA", (375, 111), (0, 0, 0, 255))
    black.putalpha(isl)
    card.alpha_composite(black, (margin + (bw - 375) // 2, inset + 33))
    h = round(H * width / W)
    return card.resize((width, h), Image.LANCZOS), round(80 * 3 * width / W)


def paste_phone(canvas, path, x, y, width, shadow=True, halo=None, real=False):
    card, r = real_iphone(path, width) if real else framed_phone(path, width)
    if halo:
        hl = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
        ImageDraw.Draw(hl).rounded_rectangle([x - 14, y - 14, x + card.width + 14, y + card.height + 14], r + 14, fill=halo + (170,))
        canvas.alpha_composite(hl.filter(ImageFilter.GaussianBlur(46)))
    if shadow:
        sh = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
        ImageDraw.Draw(sh).rounded_rectangle([x, y + 40, x + card.width, y + card.height + 40], r, fill=(0, 0, 0, 70))
        canvas.alpha_composite(sh.filter(ImageFilter.GaussianBlur(70)))
    canvas.alpha_composite(card, (x, y))
    return card


def headline(canvas, title, sub, y, size, sub_size=None, align="center", x=None, accent=None):
    """Title lines; a word between *stars* is the accent colour. Returns the y below the block."""
    d = ImageDraw.Draw(canvas)
    big = font(size, "Semibold")
    small = font(sub_size or round(size * 0.46), "Regular")
    w = canvas.width
    gap = round(size * 1.12)
    for line in title.split("\n"):
        parts = line.split("*")
        segs = [(t, (accent or ACCENT) if i % 2 else INK) for i, t in enumerate(parts) if t]
        total = sum(d.textlength(t, font=big) for t, _ in segs)
        cx = x if (align == "left" and x is not None) else (w - total) / 2
        for t, c in segs:
            d.text((cx, y), t, font=big, fill=c)
            cx += d.textlength(t, font=big)
        y += gap
    if sub:
        tw = d.textlength(sub, font=small)
        sx = x if (align == "left" and x is not None) else (w - tw) / 2
        d.text((sx, y + round(size * 0.12)), sub, font=small, fill=MUTED)
        y += round((sub_size or size * 0.42) * 1.6)
    return y
