# -*- coding: utf-8 -*-
"""Build the Play Console assets from the screenshots taken on the phone.

Nothing here invents app content. Every screen is a real capture from the
device; this only frames them at the sizes Play accepts and puts a line of
Turkish over each one.

Play's rules, which is why these numbers are what they are:
  icon             512x512 PNG, 32-bit with alpha
  feature graphic  1024x500 PNG or JPEG, no alpha
  phone shots      16:9 or 9:16, each side 320..3840 px

A raw capture from this phone is 1080x2340, which is 9:19.5 and would be
rejected. Framing them on a 1080x1920 canvas is both the fix and what a store
listing looks like anyway.
"""
import io
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = 'C:/flutter-project-main'
RAW = os.path.join(ROOT, 'store', 'raw')
OUT = os.path.join(ROOT, 'store', 'play')
ICON = os.path.join(ROOT, 'flutter_vocabmaster', 'assets', 'images',
                    'app_icon_composed.png')

VIOLET = (108, 78, 245)
VIOLET_DEEP = (67, 44, 178)
INK = (26, 22, 51)
WHITE = (255, 255, 255)

BOLD = 'C:/Windows/Fonts/segoeuib.ttf'
REGULAR = 'C:/Windows/Fonts/segoeui.ttf'

# The phone's own chrome. The clock and the battery belong to the reviewer's
# device, not to this app, and Play listings look wrong with someone else's
# notification icons in them.
STATUS_BAR = 92
NAV_BAR = 132

SHOTS = [
    ('01_today.png', 'Bugün ne yapacağın belli', 'Plan sırayla ilerler'),
    ('02_tutor.png', 'Kafede sipariş ver', 'Sesli rol yapma sahneleri'),
    ('03_words.png', 'Kelimelerin nerede duruyor', 'Güç çubuğu ve kaynak filtresi'),
    ('07_session.png', 'Unutmadan hemen önce', 'Aralıklı tekrar, her gün kısa'),
    ('05_books.png', 'Gerçek kitaplar', 'Seviyene göre, ücretsiz'),
    ('06_reader_word.png', 'Bilmediğin kelimeye dokun', 'Cümlenin içindeki anlamı'),
    ('04_practice.png', 'Her yol tek yerde', 'Çeviri, okuma, yazma, gramer'),
]


def font(path, size):
    return ImageFont.truetype(path, size)


def rounded_shadow(card, radius, blur=28, spread=18, alpha=90):
    """A soft shadow the same shape as the card."""
    w, h = card.size
    shadow = Image.new('RGBA', (w + spread * 4, h + spread * 4), (0, 0, 0, 0))
    mask = Image.new('L', shadow.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (spread * 2, spread * 2 + spread // 2, spread * 2 + w,
         spread * 2 + h + spread // 2),
        radius=radius, fill=alpha)
    shadow.putalpha(mask.filter(ImageFilter.GaussianBlur(blur)))
    return shadow


def round_corners(im, radius):
    mask = Image.new('L', im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0) + im.size, radius=radius,
                                           fill=255)
    out = im.convert('RGBA')
    out.putalpha(mask)
    return out


def gradient(size, top, bottom):
    w, h = size
    base = Image.new('RGB', (1, h))
    px = base.load()
    for y in range(h):
        t = y / max(h - 1, 1)
        px[0, y] = tuple(int(top[i] + (bottom[i] - top[i]) * t)
                         for i in range(3))
    return base.resize(size, Image.LANCZOS)


def centred(draw, text, f, y, width, fill):
    box = draw.textbbox((0, 0), text, font=f)
    draw.text(((width - (box[2] - box[0])) / 2 - box[0], y), text, font=f,
              fill=fill)
    return box[3] - box[1]


def promo(source, headline, subline, out_path):
    canvas = gradient((1080, 1920), VIOLET, VIOLET_DEEP).convert('RGBA')
    draw = ImageDraw.Draw(canvas)

    h = centred(draw, headline, font(BOLD, 66), 96, 1080, WHITE)
    centred(draw, subline, font(REGULAR, 40), 96 + h + 42, 1080,
            (226, 218, 255))

    shot = Image.open(os.path.join(RAW, source)).convert('RGB')
    shot = shot.crop((0, STATUS_BAR, shot.width, shot.height - NAV_BAR))
    target_w = 740
    shot = shot.resize(
        (target_w, int(shot.height * target_w / shot.width)), Image.LANCZOS)

    card = round_corners(shot, 34)
    top = 1920 - card.height - 96
    left = (1080 - card.width) // 2

    shadow = rounded_shadow(card, 34)
    canvas.alpha_composite(shadow, (left - 36, top - 36))
    canvas.alpha_composite(card, (left, top))

    canvas.convert('RGB').save(out_path, 'PNG')
    return canvas.size


def feature_graphic(out_path):
    canvas = gradient((1024, 500), VIOLET, VIOLET_DEEP).convert('RGBA')

    # On a white card, not straight onto the gradient: the icon's own
    # background is the same violet, so the mark read as a slightly lighter
    # square rather than as a logo.
    card = Image.new('RGBA', (268, 268), (255, 255, 255, 255))
    mark = Image.open(ICON).convert('RGBA').resize((236, 236), Image.LANCZOS)
    card.alpha_composite(round_corners(mark, 52), (16, 16))
    canvas.alpha_composite(rounded_shadow(card, 60, blur=22, spread=14),
                           (64 - 28, 116 - 28))
    canvas.alpha_composite(round_corners(card, 60), (64, 116))

    draw = ImageDraw.Draw(canvas)
    draw.text((372, 150), 'KlioAI', font=font(BOLD, 92), fill=WHITE)
    draw.text((378, 268), 'İngilizceyi konuşarak, okuyarak',
              font=font(REGULAR, 36), fill=(226, 218, 255))
    draw.text((378, 316), 've tekrar ederek öğren',
              font=font(REGULAR, 36), fill=(226, 218, 255))

    canvas.convert('RGB').save(out_path, 'PNG')


def play_icon(out_path):
    Image.open(ICON).convert('RGBA').resize((512, 512), Image.LANCZOS) \
        .save(out_path, 'PNG')


os.makedirs(OUT, exist_ok=True)
play_icon(os.path.join(OUT, 'icon_512.png'))
print('icon_512.png                512x512')
feature_graphic(os.path.join(OUT, 'feature_graphic_1024x500.png'))
print('feature_graphic_1024x500.png  1024x500')

for i, (src, head, sub) in enumerate(SHOTS, start=1):
    name = 'screenshot_%02d.png' % i
    size = promo(src, head, sub, os.path.join(OUT, name))
    print('%-28s %dx%d  %s' % (name, size[0], size[1], head))
