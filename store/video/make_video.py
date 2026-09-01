# -*- coding: utf-8 -*-
"""Build the promo from the screen recordings in raw/.

Every frame of app content here is a real capture from the phone, taken over
adb while driving the app. This script does the part a screen recording is
not: it puts the device on a designed ground, sets the type, and moves things.

The first draft was the recordings full-bleed with a caption bar over them,
and it looked like what it was. What separates a promo from a screen capture
is four things, all of them here:

  the screen is never bare      it sits in a bezel with a shadow, on a plate
  nothing is static             the device settles and drifts; scenes slide
  type is set, not overlaid     a kicker, a headline, no bar behind them
  no dead frames                the windows below are chosen off contact
                                sheets so each scene opens on its payoff

Order matters as much as the look. The speaking correction leads, because it
is the one thing here no other app on the shelf does; the reader follows. The
reader's own surface is dark and everything else is light, which reads as
variety in second place and as inconsistency in first.

Two notes for whoever changes this:

Input seeking (-ss before -i) is wrong for these files. screenrecord writes
variable frame rate with sparse keyframes, and seeking that way landed a whole
second off and left the first frames empty, so the bezel played alone against
the background. Every cut below seeks on the output side and writes a constant
30fps intermediate first.

There are no fade-ins. They cost the first frame, which is the thumbnail and
the one frame a muted feed guarantees you, and the slide between scenes
already carries the reveal.
"""
import os
import subprocess

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(HERE, 'art')
RAW = os.path.join(HERE, 'raw')
ICON = os.path.join(HERE, '..', '..', 'flutter_vocabmaster', 'assets',
                    'images', 'app_icon_composed.png')
OUT = os.path.join(HERE, 'klioai_tanitim_tr.mp4')

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

# source, seek, duration, text plate, kicker, headline. The seek points came
# from contact sheets of the raw files: each one opens a beat before the thing
# it is there to show, and holds a beat after it.
SCENES = [
    ('c1.png', None, 4.3, 't2', 'KONUŞ', 'Konuş, anında düzeltilsin'),
    ('klio_a.mp4', 15.2, 4.6, 't1', 'OKU', 'Bilmediğin kelimeye dokun'),
    ('klio_c.mp4', 18.6, 4.5, 't3', 'TEKRARLA', 'Unutmadan hemen önce'),
    ('klio_d.mp4', 10.8, 3.9, 't4', 'SAKLA', 'Her kelime seninle kalır'),
]
END_SECONDS = 3.4
TRANSITION = 0.45

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
        px[0, y] = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
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


def centre(draw, text, font, y, fill):
    b = draw.textbbox((0, 0), text, font=font)
    draw.text(((W - (b[2] - b[0])) / 2 - b[0], y), text, font=font, fill=fill)


def build_art():
    os.makedirs(ART, exist_ok=True)
    bg = background()
    bg.convert('RGB').save(os.path.join(ART, 'bg.png'))

    m = Image.new('L', (SCREEN[2], SCREEN[3]), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, SCREEN[2] - 1, SCREEN[3] - 1),
                                        radius=40, fill=255)
    m.convert('RGB').save(os.path.join(ART, 'mask.png'))

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
    plate.save(os.path.join(ART, 'plate.png'))

    for _, _, _, name, kicker, headline in SCENES:
        im = Image.new('RGBA', (W, H), (0, 0, 0, 0))
        dd = ImageDraw.Draw(im)
        size = 68
        while size > 40:
            f = ImageFont.truetype(BLACK_F, size)
            if dd.textbbox((0, 0), headline, font=f)[2] <= 940:
                break
            size -= 2
        # drawtext cannot letter-space, and this is set in PIL anyway.
        centre(dd, '  '.join(kicker), ImageFont.truetype(SEMI_F, 30), 168,
               (205, 192, 255, 255))
        centre(dd, headline, f, 224, (255, 255, 255, 255))
        im.save(os.path.join(ART, '%s.png' % name))

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
    centre(ed, 'KlioAI', ImageFont.truetype(BLACK_F, 118), 1010, (255, 255, 255))
    centre(ed, 'İngilizceyi konuşarak, okuyarak öğren',
           ImageFont.truetype(SEMI_F, 44), 1180, (223, 214, 255))
    pill = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(pill).rounded_rectangle((330, 1300, 750, 1400), radius=50,
                                           fill=(255, 255, 255, 245))
    end.alpha_composite(pill)
    centre(ImageDraw.Draw(end), "Google Play'de ücretsiz",
           ImageFont.truetype(SEMI_F, 40), 1327, (58, 36, 160))
    end.convert('RGB').save(os.path.join(ART, 'endcard.png'))
    print('art: bg, mask, plate, 4 text plates, endcard')


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


def build_scenes():
    paths = []
    for i, (src, seek, dur, plate, _, _) in enumerate(SCENES):
        source = os.path.join(RAW if src.endswith('.mp4') else HERE, src)
        if seek is None:
            # A still, pushed in slowly. 0.28 of the height keeps the
            # correction in frame as the zoom tightens.
            first = ("[1:v]crop=1080:2116:0:92,zoompan=z='1+0.10*on/{n}':"
                     "x='iw/2-(iw/zoom/2)':y='ih*0.28-(ih/zoom*0.28)':"
                     "d={n}:s={w}x{h}:fps=30,setsar=1[scr];").format(
                         n=int(dur * 30), w=SCREEN[2], h=SCREEN[3])
            src_args = ['-i', source]
        else:
            seg = os.path.join(HERE, 'seg_%d.mp4' % i)
            run(['-i', source, '-ss', str(seek), '-t', str(dur), '-vf',
                 'fps=30,crop=1080:2116:0:92,scale=%d:%d,setsar=1'
                 % (SCREEN[2], SCREEN[3]), '-an'] + ENC + [seg])
            first = '[1:v]setsar=1[scr];'
            src_args = ['-i', seg]

        out = os.path.join(HERE, 's%d.mp4' % i)
        run(['-loop', '1', '-i', os.path.join(ART, 'bg.png')] + src_args +
            ['-loop', '1', '-i', os.path.join(ART, 'mask.png'),
             '-loop', '1', '-i', os.path.join(ART, 'plate.png'),
             '-loop', '1', '-i', os.path.join(ART, '%s.png' % plate),
             '-filter_complex', first + COMPOSITE, '-map', '[out]',
             '-t', str(dur)] + ENC + [out])
        paths.append((out, dur))
        print('scene %d  %s  %.1fs' % (i + 1, plate, dur))

    end = os.path.join(HERE, 's_end.mp4')
    run(['-loop', '1', '-i', os.path.join(ART, 'endcard.png'),
         '-filter_complex',
         "[0:v]fps=30,scale=%d:%d,setsar=1,zoompan=z='1.03-0.03*min(on/45,1)':"
         "x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=%d:s=%dx%d:fps=30[out]"
         % (W, H, int(END_SECONDS * 30), W, H),
         '-map', '[out]', '-t', str(END_SECONDS)] + ENC + [end])
    paths.append((end, END_SECONDS))
    return paths


def assemble(paths):
    args, chain, offset, prev = [], [], 0.0, '0:v'
    for i, (path, _) in enumerate(paths):
        args += ['-i', path]
    # A silent stereo track: Play and every feed expect one, and a file with
    # no audio stream is rejected by some uploaders outright.
    args += ['-f', 'lavfi', '-i', 'anullsrc=r=44100:cl=stereo']

    total = paths[0][1]
    for i in range(1, len(paths)):
        offset = total - TRANSITION
        label = 'v%d' % i if i < len(paths) - 1 else 'v'
        chain.append('[%s][%d:v]xfade=transition=slideleft:duration=%s:'
                     'offset=%.2f[%s]' % (prev, i, TRANSITION, offset, label))
        total = total + paths[i][1] - TRANSITION
        prev = label

    run(args + ['-filter_complex', ';'.join(chain), '-map', '[v]',
                '-map', '%d:a' % len(paths), '-shortest',
                '-c:v', 'libx264', '-crf', '18', '-preset', 'slow',
                '-pix_fmt', 'yuv420p', '-r', '30', '-c:a', 'aac',
                '-b:a', '96k', '-movflags', '+faststart', OUT])
    print('%s  %.1fs' % (os.path.basename(OUT), total))


if __name__ == '__main__':
    build_art()
    assemble(build_scenes())
