# -*- coding: utf-8 -*-
"""Still images for Reddit and Facebook, in the same language as the clips.

    python make_promo.py

A raw screenshot reads as a bug report; the Play Store frames read as an ad.
These sit between: the screen in a phone -- rounded corners, bezel, shadow --
on the brand gradient, a headline above, one quiet line below. 1080 x 1440,
which every feed shows whole.

The screens come from the phone with the interface in English, taken tonight
(see ../promo/src). The crop is the clip's: under the status bar, above the
app's tab bar.
"""
import os

from PIL import Image, ImageDraw, ImageFilter

from make_clip import BLACK_F, SEMI_F
from make_pro import (ACCENT, BEZEL, CROP_BOTTOM, CROP_TOP, DEEP, DEEP_TOP,
                      DIM, NOTE, WHITE, font)

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, '..', 'promo', 'src')
OUT = os.path.join(HERE, '..', 'promo')

W, H = 1080, 1440
SH = 1000
PY = 250
RADIUS = 44

# (name, screenshot, headline, line under the phone, where the crop ends).
# The reader's word sheet sits at the bottom of the screen, under the clip's
# crop line, so that one is cut lower to keep the definition.
IMAGES = [
    ('card', 'tutor_card.png',
     'Say it wrong, see it said right',
     'Your sentence, the better version, and one line in your language on why.',
     CROP_BOTTOM),
    ('talk', 'tutor_talk.png',
     'Order dinner from a waiter who talks back',
     'Hold the button, speak. Luca answers out loud.',
     CROP_BOTTOM),
    ('reader', 'reader.png',
     'Tap a word, get its meaning in that sentence',
     'One meaning, the one on the page, not nine.',
     2170),
    ('library', 'library.png',
     'Whole books, sorted by level',
     'Beatrix Potter at A1. Wilde at B1. Sherlock Holmes when you are ready.',
     CROP_BOTTOM),
]


def gradient():
    im = Image.new('RGB', (W, H), DEEP)
    d = ImageDraw.Draw(im)
    for y in range(H):
        t = y / float(H - 1)
        d.line([(0, y), (W, y)],
               fill=tuple(int(DEEP_TOP[i] + (DEEP[i] - DEEP_TOP[i]) * t) for i in range(3)))
    glow = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse((-100, 150, W + 100, 1000), fill=ACCENT + (70,))
    glow = glow.filter(ImageFilter.GaussianBlur(200))
    return Image.alpha_composite(im.convert('RGBA'), glow)


def centred(d, y, text, f, fill):
    d.text((W // 2, y), text, font=f, fill=fill, anchor='mt')


def fit(d, text, path, size, max_w, floor=30):
    while size > floor:
        f = font(path, size)
        if d.textlength(text, font=f) <= max_w:
            return f
        size -= 2
    return font(path, floor)


def wrap(d, text, f, max_w):
    words = text.split()
    lines, line = [], ''
    for w in words:
        trial = (line + ' ' + w).strip()
        if d.textlength(trial, font=f) <= max_w:
            line = trial
        else:
            lines.append(line)
            line = w
    lines.append(line)
    return lines


def phone(screen_path, crop_bottom):
    """The screenshot cropped like the clip, scaled to SH, with rounded corners."""
    shot = Image.open(screen_path).convert('RGB')
    sw = int(round(SH * 1080.0 / (crop_bottom - CROP_TOP)))
    shot = shot.crop((0, CROP_TOP, 1080, crop_bottom)).resize((sw, SH), Image.LANCZOS)
    mask = Image.new('L', (sw, SH), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, sw - 1, SH - 1), radius=RADIUS, fill=255)
    shot.putalpha(mask)
    return shot


def compose(name, screen, headline, sub, crop_bottom):
    scr = phone(os.path.join(SRC, screen), crop_bottom)
    SW = scr.width
    PX = (W - SW) // 2
    im = gradient()
    shadow = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        (PX, PY + 34, PX + SW, PY + SH + 34), radius=RADIUS + 12, fill=(0, 0, 0, 170))
    im = Image.alpha_composite(im, shadow.filter(ImageFilter.GaussianBlur(40)))
    d = ImageDraw.Draw(im)
    b = 12
    d.rounded_rectangle((PX - b, PY - b, PX + SW + b, PY + SH + b),
                        radius=RADIUS + b, fill=BEZEL)
    im.alpha_composite(scr, (PX, PY))

    d = ImageDraw.Draw(im)
    # One size for every headline, so the four read as a set; only a line that
    # will not fit at 52 comes down.
    f = fit(d, headline, BLACK_F, 52, W - 140)
    lines = wrap(d, headline, f, W - 140)
    y = 86 if len(lines) == 1 else 56
    for line in lines:
        centred(d, y, line, f, WHITE)
        y += int(f.size * 1.15)
    fs = font(SEMI_F, 30)
    y = PY + SH + 36
    for line in wrap(d, sub, fs, W - 160)[:2]:
        centred(d, y, line, fs, DIM)
        y += 38
    centred(d, H - 46, 'KlioAI  ·  free on Google Play', font(SEMI_F, 27), NOTE)

    out = os.path.join(OUT, 'promo_%s.png' % name)
    im.convert('RGB').save(out)
    print('wrote', out)


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    for name, screen, headline, sub, crop_bottom in IMAGES:
        compose(name, screen, headline, sub, crop_bottom)
