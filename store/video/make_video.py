# -*- coding: utf-8 -*-
"""Build the promo from the screen recordings in raw/.

    python make_video.py tr
    python make_video.py en

Every frame of app content here is a real capture from the phone, taken over
adb while driving the app. This script does the part a screen recording is
not: it puts the device on a designed ground, sets the type, and moves things.

The first draft was the recordings full-bleed with a caption bar over them,
and it looked like what it was. Four things separate a promo from a screen
capture, and all four are here:

  the screen is never bare      it sits in a bezel with a shadow, on a plate
  nothing is static             the device settles and drifts; scenes slide
  type is set, not overlaid     a kicker, a headline, no bar behind them
  no dead frames                the windows below are chosen off contact
                                sheets so each scene opens on its payoff

Order matters as much as the look. The speaking correction leads in both
languages, because it is the one thing here no other app on the shelf does.

The two language sets are NOT translations of each other, and cannot be. The
interface is localised; the saved word meanings are not -- those are data,
written when the account's native language was Turkish. So the review card and
the word list, which are half the Turkish cut, would show Turkish to an
English viewer. The English set replaces them with the daily plan and the
practice hub, which carry the same two claims -- spaced repetition, and
breadth -- without ever printing a stored meaning. The reader survives the
crossing only because tapping an unsaved word fetches its meaning fresh, in
whatever language the profile is set to.

Two notes for whoever changes this:

Input seeking (-ss before -i) is wrong for these files. screenrecord writes
variable frame rate with sparse keyframes, and seeking that way landed a whole
second off on one clip and left the first frames of another empty, so the
bezel played alone against the background. Every cut below seeks on the output
side and writes a constant 30fps intermediate first.

There are no fade-ins. They cost the first frame, which is the thumbnail and
the one frame a muted feed guarantees you, and the slide between scenes
already carries the reveal.
"""
import os
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(HERE, 'raw')
ICON = os.path.join(HERE, '..', '..', 'flutter_vocabmaster', 'assets',
                    'images', 'app_icon_composed.png')

W, H = 1080, 1920
VIOLET, DEEP = (108, 78, 245), (58, 36, 160)
BLACK_F = 'C:/Windows/Fonts/seguibl.ttf'
SEMI_F = 'C:/Windows/Fonts/seguisb.ttf'

# The device, in plate coordinates. The ffmpeg overlays below use these, so
# moving the bezel means moving SCREEN with it.
PLATE = (860, 1590)
BEZEL = (40, 40, 780, 1470)
SCREEN = (60, 50, 740, 1450)
PLATE_X, SCREEN_Y = 110, 400          # where the plate sits on the canvas

END_SECONDS = 3.4
TRANSITION = 0.45

# source, seek, duration, kicker, headline, focus. A .png source is a still
# and gets a slow push-in instead of a seek, held on `focus` -- the fraction of
# the frame's height that must stay in view as the zoom tightens, which is a
# different place in each still and was the difference between framing the
# correction and framing the wallpaper.
#
# The seek points came from contact sheets of the raw files: each scene opens a
# beat before the thing it is there to show, and holds a beat after it.
LANGS = {
    'tr': {
        'scenes': [
            ('c1.png', None, 4.3, 'KONUŞ',
             'Konuş, anında düzeltilsin', 0.28),
            ('klio_a.mp4', 15.2, 4.6, 'OKU',
             'Bilmediğin kelimeye dokun', None),
            ('klio_c.mp4', 18.6, 4.5, 'TEKRARLA',
             'Unutmadan hemen önce', None),
            ('klio_d.mp4', 10.8, 3.9, 'SAKLA',
             'Her kelime seninle kalır', None),
        ],
        'tagline': 'İngilizceyi konuşarak, okuyarak öğren',
        'cta': "Google Play'de ücretsiz",
    },
    'en': {
        'scenes': [
            ('c1_en.png', None, 4.3, 'SPEAK',
             'Speak, and get corrected', 0.36),
            ('klio_en_read.mp4', 5.8, 4.6, 'READ',
             "Tap any word you don't know", None),
            ('klio_en_plan.mp4', 6.5, 4.5, 'REVIEW',
             'Review before you forget', None),
            ('klio_en_practice.mp4', 6.2, 3.9, 'PRACTISE',
             'Every path in one place', None),
        ],
        'tagline': 'Learn English by speaking and reading',
        'cta': 'Free on Google Play',
    },
}

ENC = ['-c:v', 'libx264', '-crf', '18', '-preset', 'veryfast',
       '-pix_fmt', 'yuv420p', '-r', '30']


def run(args):
    subprocess.run(['ffmpeg', '-y', '-v', 'error'] + args, check=True)


def gradient(size, top, bottom):
    w, h = size
    col = Image.new('RGB', (1, h))
    px = col.load()
    for y in range(h):
        t = y / (h - 1)
        px[0, y] = tuple(int(top[i] + (bottom[i] - top[i]) * t)
                         for i in range(3))
    return col.resize(size, Image.LANCZOS)


def radial(size, centre, radius, colour, strength):
    """A soft light. Drawn at an eighth and scaled up, so the blur is free."""
    w, h = size
    s = 8
    small = Image.new('L', (w // s, h // s), 0)
    d = ImageDraw.Draw(small)
    cx, cy, r = centre[0] // s, centre[1] // s, radius // s
    for i in range(r, 0, -max(r // 60, 1)):
        d.ellipse((cx - i, cy - i, cx + i, cy + i),
                  fill=int(strength * (1 - i / r) ** 1.6))
    small = small.filter(ImageFilter.GaussianBlur(r // 6))
    layer = Image.new('RGBA', size, colour + (0,))
    layer.putalpha(small.resize(size, Image.LANCZOS))
    return layer


def rounded(im, r):
    m = Image.new('L', im.size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0) + im.size, radius=r, fill=255)
    out = im.convert('RGBA')
    out.putalpha(m)
    return out


def background():
    bg = gradient((W, H), VIOLET, DEEP).convert('RGBA')
    bg.alpha_composite(radial((W, H), (300, 420), 900, (168, 148, 255), 120))
    bg.alpha_composite(radial((W, H), (880, 1500), 800, (92, 60, 220), 110))
    return bg


def fitted(draw, text, path, start, limit):
    """The largest size at which this line still fits the width it has."""
    size = start
    while size > 26:
        f = ImageFont.truetype(path, size)
        if draw.textbbox((0, 0), text, font=f)[2] <= limit:
            return f
        size -= 2
    return ImageFont.truetype(path, 26)


def centre(draw, text, font, y, fill):
    b = draw.textbbox((0, 0), text, font=font)
    draw.text(((W - (b[2] - b[0])) / 2 - b[0], y), text, font=font, fill=fill)


def build_art(art, cfg):
    os.makedirs(art, exist_ok=True)
    background().convert('RGB').save(os.path.join(art, 'bg.png'))

    m = Image.new('L', (SCREEN[2], SCREEN[3]), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, SCREEN[2] - 1, SCREEN[3] - 1),
                                        radius=40, fill=255)
    m.convert('RGB').save(os.path.join(art, 'mask.png'))

    plate = Image.new('RGBA', PLATE, (0, 0, 0, 0))
    bx, by, bw, bh = BEZEL
    sh = Image.new('RGBA', PLATE, (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle(
        (bx + 10, by + 34, bx + bw + 10, by + bh + 34), radius=58,
        fill=(14, 8, 44, 150))
    plate.alpha_composite(sh.filter(ImageFilter.GaussianBlur(30)))
    d = ImageDraw.Draw(plate)
    d.rounded_rectangle((bx, by, bx + bw, by + bh), radius=56,
                        fill=(17, 14, 38, 255))
    # A hairline along the edge; without it the bezel reads as a black hole
    # rather than as glass.
    d.rounded_rectangle((bx, by, bx + bw, by + bh), radius=56,
                        outline=(150, 130, 240, 90), width=3)
    plate.save(os.path.join(art, 'plate.png'))

    for i, (_, _, _, kicker, headline, _f) in enumerate(cfg['scenes']):
        im = Image.new('RGBA', (W, H), (0, 0, 0, 0))
        dd = ImageDraw.Draw(im)
        # drawtext cannot letter-space, and this is set in PIL anyway.
        centre(dd, '  '.join(kicker), ImageFont.truetype(SEMI_F, 30), 168,
               (205, 192, 255, 255))
        centre(dd, headline, fitted(dd, headline, BLACK_F, 68, 940), 224,
               (255, 255, 255, 255))
        im.save(os.path.join(art, 't%d.png' % i))

    card = Image.new('RGBA', (340, 340), (255, 255, 255, 255))
    mark = Image.open(ICON).convert('RGBA').resize((300, 300), Image.LANCZOS)
    card.alpha_composite(rounded(mark, 66), (20, 20))
    end = background()
    sh = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle((370, 620, 710, 960), radius=80,
                                         fill=(12, 6, 40, 150))
    end.alpha_composite(sh.filter(ImageFilter.GaussianBlur(30)))
    end.alpha_composite(rounded(card, 76), (370, 590))

    ed = ImageDraw.Draw(end)
    centre(ed, 'KlioAI', ImageFont.truetype(BLACK_F, 118), 1010,
           (255, 255, 255))
    centre(ed, cfg['tagline'], fitted(ed, cfg['tagline'], SEMI_F, 44, 940),
           1180, (223, 214, 255))

    # The pill is drawn to the width of the words in it, so a longer call to
    # action does not spill out of its own background.
    cf = ImageFont.truetype(SEMI_F, 40)
    half = ed.textbbox((0, 0), cfg['cta'], font=cf)[2] / 2 + 46
    pill = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(pill).rounded_rectangle(
        (540 - half, 1300, 540 + half, 1400), radius=50,
        fill=(255, 255, 255, 245))
    end.alpha_composite(pill)
    centre(ImageDraw.Draw(end), cfg['cta'], cf, 1327, (58, 36, 160))

    end.convert('RGB').save(os.path.join(art, 'endcard.png'))
    print('art: bg, mask, plate, %d text plates, endcard' % len(cfg['scenes']))


# The device settles into place and then drifts a few pixels; the headline
# does the same, a little faster. Both are exponential, because linear motion
# is the thing that reads as a slideshow.
PHONE_Y = "'%d+22*exp(-6*t)-4*t'" % (SCREEN_Y - SCREEN[1])
TEXT_Y = "'-12*exp(-6*t)'"

COMPOSITE = (
    "[scr][2:v]alphamerge[scrm];"
    "[3:v]format=rgba[pl];"
    "[pl][scrm]overlay={sx}:{sy}:format=auto[ph];"
    "[0:v]scale={W}:{H},setsar=1[bgv];"
    "[bgv][ph]overlay=x={px}:y={py}[s];"
    "[s][4:v]overlay=x=0:y={ty}[out]"
).format(sx=SCREEN[0], sy=SCREEN[1], W=W, H=H, px=PLATE_X, py=PHONE_Y,
         ty=TEXT_Y)


def build_scenes(art, cfg):
    paths = []
    for i, (src, seek, dur, kicker, headline, focus) in enumerate(cfg['scenes']):
        source = os.path.join(RAW if src.endswith('.mp4') else HERE, src)
        if not os.path.exists(source):
            raise SystemExit('missing source: %s' % source)

        if src.endswith('.png'):
            # A still, pushed in slowly, anchored on `focus` so the zoom
            # tightens onto the thing the scene is about.
            first = ("[1:v]crop=1080:2116:0:92,zoompan=z='1+0.10*on/{n}':"
                     "x='iw/2-(iw/zoom/2)':y='ih*{f}-(ih/zoom*{f})':"
                     "d={n}:s={w}x{h}:fps=30,setsar=1[scr];").format(
                         n=int(dur * 30), f=focus, w=SCREEN[2], h=SCREEN[3])
            src_args = ['-i', source]
        else:
            seg = os.path.join(HERE, 'seg_%d.mp4' % i)
            cut = ['-i', source]
            if seek is not None:
                cut += ['-ss', str(seek)]
            run(cut + ['-t', str(dur), '-vf',
                       'fps=30,crop=1080:2116:0:92,scale=%d:%d,setsar=1'
                       % (SCREEN[2], SCREEN[3]), '-an'] + ENC + [seg])
            first = '[1:v]setsar=1[scr];'
            src_args = ['-i', seg]

        out = os.path.join(HERE, 's%d.mp4' % i)
        run(['-loop', '1', '-i', os.path.join(art, 'bg.png')] + src_args +
            ['-loop', '1', '-i', os.path.join(art, 'mask.png'),
             '-loop', '1', '-i', os.path.join(art, 'plate.png'),
             '-loop', '1', '-i', os.path.join(art, 't%d.png' % i),
             '-filter_complex', first + COMPOSITE, '-map', '[out]',
             '-t', str(dur)] + ENC + [out])
        paths.append((out, dur))
        print('scene %d  %-9s %.1fs  %s' % (i + 1, kicker, dur, headline))

    end = os.path.join(HERE, 's_end.mp4')
    run(['-loop', '1', '-i', os.path.join(art, 'endcard.png'),
         '-filter_complex',
         "[0:v]fps=30,scale=%d:%d,setsar=1,zoompan=z='1.03-0.03*min(on/45,1)':"
         "x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=%d:s=%dx%d:fps=30[out]"
         % (W, H, int(END_SECONDS * 30), W, H),
         '-map', '[out]', '-t', str(END_SECONDS)] + ENC + [end])
    paths.append((end, END_SECONDS))
    return paths


def assemble(paths, out_path):
    args, chain, prev = [], [], '0:v'
    for path, _ in paths:
        args += ['-i', path]
    # A silent stereo track: Play and every feed expect one, and some
    # uploaders reject a file with no audio stream outright.
    args += ['-f', 'lavfi', '-i', 'anullsrc=r=44100:cl=stereo']

    total = paths[0][1]
    for i in range(1, len(paths)):
        label = 'v%d' % i if i < len(paths) - 1 else 'v'
        chain.append('[%s][%d:v]xfade=transition=slideleft:duration=%s:'
                     'offset=%.2f[%s]'
                     % (prev, i, TRANSITION, total - TRANSITION, label))
        total = total + paths[i][1] - TRANSITION
        prev = label

    run(args + ['-filter_complex', ';'.join(chain), '-map', '[v]',
                '-map', '%d:a' % len(paths), '-shortest',
                '-c:v', 'libx264', '-crf', '18', '-preset', 'slow',
                '-pix_fmt', 'yuv420p', '-r', '30', '-c:a', 'aac',
                '-b:a', '96k', '-movflags', '+faststart', out_path])
    print('%s  %.1fs' % (os.path.basename(out_path), total))


if __name__ == '__main__':
    lang = sys.argv[1] if len(sys.argv) > 1 else 'tr'
    if lang not in LANGS:
        raise SystemExit('language must be one of: %s' % ', '.join(LANGS))
    config = LANGS[lang]
    artdir = os.path.join(HERE, 'art_%s' % lang)
    build_art(artdir, config)
    assemble(build_scenes(artdir, config),
             os.path.join(HERE, 'klioai_promo_%s.mp4' % lang))
