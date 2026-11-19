"""Shared look for the App Store artwork: dark, one accent colour, device-framed screens."""
from PIL import Image, ImageDraw, ImageFilter, ImageFont

SF = "/System/Library/Fonts/SFNS.ttf"
INK = (255, 255, 255)
ACCENT = (150, 176, 255)   # the highlighted word
MUTED = (160, 168, 188)
GLOW = (70, 96, 255)


def font(size, weight="Bold"):
    f = ImageFont.truetype(SF, size)
    f.set_variation_by_name(weight)
    return f


def background(w, h, glow_at=None, glow_r=None, glow=None):
    """Graphite, a little lighter toward the bottom, with a soft blue glow behind the phone."""
    top, bottom = (11, 13, 19), (24, 29, 42)
    img = Image.new("RGB", (w, h))
    px = ImageDraw.Draw(img)
    for y in range(h):
        t = y / (h - 1)
        px.line([(0, y), (w, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    img = img.convert("RGBA")
    if glow_at:
        gx, gy = glow_at
        r = glow_r or round(w * 0.6)
        blob = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        ImageDraw.Draw(blob).ellipse([gx - r, gy - r, gx + r, gy + r], fill=(glow or GLOW) + (105,))
        img.alpha_composite(blob.filter(ImageFilter.GaussianBlur(round(r * 0.55))))
    return img


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


def paste_phone(canvas, path, x, y, width, shadow=True, halo=None):
    card, r = framed_phone(path, width)
    if halo:
        hl = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
        ImageDraw.Draw(hl).rounded_rectangle([x - 14, y - 14, x + card.width + 14, y + card.height + 14], r + 14, fill=halo + (170,))
        canvas.alpha_composite(hl.filter(ImageFilter.GaussianBlur(46)))
    if shadow:
        sh = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
        ImageDraw.Draw(sh).rounded_rectangle([x, y + 40, x + card.width, y + card.height + 40], r, fill=(0, 0, 0, 150))
        canvas.alpha_composite(sh.filter(ImageFilter.GaussianBlur(60)))
    canvas.alpha_composite(card, (x, y))
    return card


def headline(canvas, title, sub, y, size, sub_size=None, align="center", x=None, accent=None):
    """Title lines; a word between *stars* is the accent colour. Returns the y below the block."""
    d = ImageDraw.Draw(canvas)
    big = font(size)
    small = font(sub_size or round(size * 0.46), "Medium")
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
        d.text((sx, y + round(size * 0.12)), sub, font=small, fill=(196, 202, 218))
        y += round((sub_size or size * 0.42) * 1.6)
    return y
