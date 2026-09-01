# -*- coding: utf-8 -*-
"""Build the promo from the screen recordings in raw/.

    python make_video.py tr           # 9:16, for feeds
    python make_video.py en wide      # 16:9, for the Play listing

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

Three notes for whoever changes this:

Input seeking (-ss before -i) is wrong for these files. screenrecord writes
variable frame rate with sparse keyframes, and seeking that way landed a whole
second off on one clip and left the first frames of another empty, so the
bezel played alone against the background. Every cut below seeks on the output
side and writes a constant 30fps intermediate first.

There are no fade-ins. They cost the first frame, which is the thumbnail and
the one frame a muted feed guarantees you, and the slide between scenes
already carries the reveal.

Both shapes exist because YouTube files anything vertical and under three
minutes as a Short no matter which button uploaded it. That is free reach in a
feed, and the wrong thing entirely for a Play listing, whose player is
landscape and does not embed a Short.
"""
import os
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(HERE, 'raw')
ICON = os.path.join(HERE, '..', '..', 'flutter_vocabmaster', 'assets',
                    'images', 'app_icon_composed.png')

VIOLET, DEEP = (108, 78, 245), (58, 36, 160)
BLACK_F = 'C:/Windows/Fonts/seguibl.ttf'
SEMI_F = 'C:/Windows/Fonts/seguisb.ttf'

# The device is drawn once and placed twice. Everything below derives from the
# screen size, so a new frame shape needs only its own row here.
#
# In 'wide' the app screen is 460px against 1080 native, so the interface is
# small and the headline carries more of the message; it sits beside the
# device instead of above it, which is the only arrangement that leaves a tall
# phone room to be tall in a short frame.
BEZEL_PAD = (20, 10)     # the screen's inset inside the bezel
PLATE_PAD = 40           # the bezel's inset inside the plate, for the shadow

LAYOUTS = {
    'tall': {
        'canvas': (1080, 1920),
        'screen': (740, 1450),
        'screen_at': (170, 400),          # where the screen lands on canvas
        'text': {'align': 'center', 'x': 0, 'kicker_y': 168, 'head_y': 224,
                 'width': 940},
        'end': {'icon': 340, 'icon_y': 590, 'mark_y': 1010, 'tag_y': 1180,
                'pill_y': 1300, 'pill_h': 100, 'mark_size': 118,
                'tag_size': 44, 'cta_size': 40},
    },
    'wide': {
        'canvas': (1920, 1080),
        'screen': (460, 902),
        'screen_at': (1250, 69),
        'text': {'align': 'left', 'x': 140, 'kicker_y': 440, 'head_y': 496,
                 'width': 1000},
        'end': {'icon': 260, 'icon_y': 200, 'mark_y': 520, 'tag_y': 680,
                'pill_y': 790, 'pill_h': 92, 'mark_size': 104,
                'tag_size': 40, 'cta_size': 36},
    },
}

# The music is 126 BPM and starts on the downbeat, so a bar is 1.904s. Every
# scene runs two bars plus the transition it hands over with, which puts each
# slide exactly on a downbeat; the end card runs three, and the film stops at
# 20.944s -- a bar line, inside the breath the track takes from 19.5 to 22.5.
# Those numbers are measured, not chosen: see MUSIC.md.
BAR = 1.904
SCENE_SECONDS = 2 * BAR + 0.45
END_SECONDS = 3 * BAR
TRANSITION = 0.45

# Trimmed to the film, with a hair of fade at each end -- in to kill the click
# of starting mid-sample, out to land the ending rather than cut it.
MUSIC = 'Sunset 52 - Jeremy Black.mp3'
MUSIC_GAIN = 0.9
MUSIC_FADE_OUT = 0.5

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
            ('c1.png', None, SCENE_SECONDS, 'KONUŞ',
             'Konuş, anında düzeltilsin', 0.28),
            ('klio_a.mp4', 15.2, SCENE_SECONDS, 'OKU',
             'Bilmediğin kelimeye dokun', None),
            ('klio_c.mp4', 18.6, SCENE_SECONDS, 'TEKRARLA',
             'Unutmadan hemen önce', None),
            ('klio_d.mp4', 10.8, SCENE_SECONDS, 'SAKLA',
             'Her kelime seninle kalır', None),
        ],
        'tagline': 'İngilizceyi konuşarak, okuyarak öğren',
        'cta': "Google Play'de ücretsiz",
    },
    'en': {
        'scenes': [
            ('c1_en.png', None, SCENE_SECONDS, 'SPEAK',
             'Speak, and get corrected', 0.36),
            ('klio_en_read.mp4', 5.8, SCENE_SECONDS, 'READ',
             "Tap any word you don't know", None),
            ('klio_en_plan.mp4', 6.5, SCENE_SECONDS, 'REVIEW',
             'Review before you forget', None),
            ('klio_en_practice.mp4', 6.2, SCENE_SECONDS, 'PRACTISE',
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
    small = small.filter(ImageFilter.GaussianBlur(max(r // 6, 1)))
    layer = Image.new('RGBA', size, colour + (0,))
    layer.putalpha(small.resize(size, Image.LANCZOS))
    return layer


def rounded(im, r):
    m = Image.new('L', im.size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0) + im.size, radius=r, fill=255)
    out = im.convert('RGBA')
    out.putalpha(m)
    return out


def geometry(lay):
    """Everything the device needs, derived from the screen size alone."""
    sw, sh = lay['screen']
    # yuv420p subsamples chroma by two, so libx264 refuses an odd side. The
    # wide layout was first written 460x901 and every scene in it died with a
    # bare exit code -- the failure is loud but says nothing about parity.
    if sw % 2 or sh % 2:
        raise SystemExit('screen %dx%d has an odd side; h264 needs both even'
                         % (sw, sh))
    bw, bh = sw + 2 * BEZEL_PAD[0], sh + 2 * BEZEL_PAD[1]
    plate = (bw + 2 * PLATE_PAD, bh + 2 * PLATE_PAD + 40)
    in_plate = (PLATE_PAD + BEZEL_PAD[0], PLATE_PAD + BEZEL_PAD[1])
    at = (lay['screen_at'][0] - in_plate[0], lay['screen_at'][1] - in_plate[1])
    return {'screen': (sw, sh), 'bezel': (PLATE_PAD, PLATE_PAD, bw, bh),
            'plate': plate, 'in_plate': in_plate, 'plate_at': at}


def background(size):
    w, h = size
    bg = gradient(size, VIOLET, DEEP).convert('RGBA')
    # Placed by fraction so the two lights sit the same way in either frame.
    bg.alpha_composite(radial(size, (int(w * .28), int(h * .22)),
                              int(max(size) * .47), (168, 148, 255), 120))
    bg.alpha_composite(radial(size, (int(w * .81), int(h * .78)),
                              int(max(size) * .42), (92, 60, 220), 110))
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


def place(draw, text, font, y, fill, width, align='center', x=0):
    b = draw.textbbox((0, 0), text, font=font)
    left = x - b[0] if align == 'left' else (width - (b[2] - b[0])) / 2 - b[0]
    draw.text((left, y), text, font=font, fill=fill)


def build_art(art, cfg, lay):
    os.makedirs(art, exist_ok=True)
    W, H = lay['canvas']
    g = geometry(lay)
    sw, sh = g['screen']

    background((W, H)).convert('RGB').save(os.path.join(art, 'bg.png'))

    m = Image.new('L', (sw, sh), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, sw - 1, sh - 1), radius=40,
                                        fill=255)
    m.convert('RGB').save(os.path.join(art, 'mask.png'))

    plate = Image.new('RGBA', g['plate'], (0, 0, 0, 0))
    bx, by, bw, bh = g['bezel']
    shade = Image.new('RGBA', g['plate'], (0, 0, 0, 0))
    ImageDraw.Draw(shade).rounded_rectangle(
        (bx + 10, by + 34, bx + bw + 10, by + bh + 34), radius=58,
        fill=(14, 8, 44, 150))
    plate.alpha_composite(shade.filter(ImageFilter.GaussianBlur(30)))
    d = ImageDraw.Draw(plate)
    d.rounded_rectangle((bx, by, bx + bw, by + bh), radius=56,
                        fill=(17, 14, 38, 255))
    # A hairline along the edge; without it the bezel reads as a black hole
    # rather than as glass.
    d.rounded_rectangle((bx, by, bx + bw, by + bh), radius=56,
                        outline=(150, 130, 240, 90), width=3)
    plate.save(os.path.join(art, 'plate.png'))

    t = lay['text']
    for i, (_, _, _, kicker, headline, _f) in enumerate(cfg['scenes']):
        im = Image.new('RGBA', (W, H), (0, 0, 0, 0))
        dd = ImageDraw.Draw(im)
        # drawtext cannot letter-space, and this is set in PIL anyway.
        place(dd, '  '.join(kicker), ImageFont.truetype(SEMI_F, 30),
              t['kicker_y'], (205, 192, 255, 255), W, t['align'], t['x'])
        place(dd, headline, fitted(dd, headline, BLACK_F, 68, t['width']),
              t['head_y'], (255, 255, 255, 255), W, t['align'], t['x'])
        im.save(os.path.join(art, 't%d.png' % i))

    e = lay['end']
    side = e['icon']
    card = Image.new('RGBA', (side, side), (255, 255, 255, 255))
    inset = side // 17
    mark = Image.open(ICON).convert('RGBA').resize(
        (side - 2 * inset, side - 2 * inset), Image.LANCZOS)
    card.alpha_composite(rounded(mark, side // 5), (inset, inset))

    end = background((W, H))
    ix = (W - side) // 2
    shadow = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        (ix, e['icon_y'] + 30, ix + side, e['icon_y'] + side + 30),
        radius=side // 4, fill=(12, 6, 40, 150))
    end.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(30)))
    end.alpha_composite(rounded(card, int(side / 4.5)), (ix, e['icon_y']))

    ed = ImageDraw.Draw(end)
    place(ed, 'KlioAI', ImageFont.truetype(BLACK_F, e['mark_size']),
          e['mark_y'], (255, 255, 255), W)
    place(ed, cfg['tagline'],
          fitted(ed, cfg['tagline'], SEMI_F, e['tag_size'], W * 0.87),
          e['tag_y'], (223, 214, 255), W)

    # The pill is drawn to the width of the words in it, so a longer call to
    # action does not spill out of its own background.
    cf = ImageFont.truetype(SEMI_F, e['cta_size'])
    half = ed.textbbox((0, 0), cfg['cta'], font=cf)[2] / 2 + e['pill_h'] * .46
    pill = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(pill).rounded_rectangle(
        (W / 2 - half, e['pill_y'], W / 2 + half, e['pill_y'] + e['pill_h']),
        radius=e['pill_h'] // 2, fill=(255, 255, 255, 245))
    end.alpha_composite(pill)
    place(ImageDraw.Draw(end), cfg['cta'], cf,
          e['pill_y'] + (e['pill_h'] - e['cta_size'] * 1.35) / 2,
          (58, 36, 160), W)

    end.convert('RGB').save(os.path.join(art, 'endcard.png'))
    print('art: bg, mask, plate, %d text plates, endcard' % len(cfg['scenes']))


def composite(lay):
    """The graph that puts one screen on the ground, with its motion.

    The device settles into place and then drifts a few pixels; the headline
    does the same, a little faster. Both are exponential, because linear
    motion is the thing that reads as a slideshow.
    """
    W, H = lay['canvas']
    g = geometry(lay)
    px, py = g['plate_at']
    return (
        "[scr][2:v]alphamerge[scrm];"
        "[3:v]format=rgba[pl];"
        "[pl][scrm]overlay={sx}:{sy}:format=auto[ph];"
        "[0:v]scale={W}:{H},setsar=1[bgv];"
        "[bgv][ph]overlay=x={px}:y='{py}+22*exp(-6*t)-4*t'[s];"
        "[s][4:v]overlay=x=0:y='-12*exp(-6*t)'[out]"
    ).format(sx=g['in_plate'][0], sy=g['in_plate'][1], W=W, H=H, px=px, py=py)


def build_scenes(art, cfg, lay):
    W, H = lay['canvas']
    sw, sh = lay['screen']
    graph = composite(lay)
    paths = []

    for i, scene in enumerate(cfg['scenes']):
        src, seek, dur, kicker, headline, focus = scene
        source = os.path.join(RAW if src.endswith('.mp4') else HERE, src)
        if not os.path.exists(source):
            raise SystemExit('missing source: %s' % source)

        if src.endswith('.png'):
            # A still, pushed in slowly, anchored on `focus` so the zoom
            # tightens onto the thing the scene is about.
            first = ("[1:v]crop=1080:2116:0:92,zoompan=z='1+0.10*on/{n}':"
                     "x='iw/2-(iw/zoom/2)':y='ih*{f}-(ih/zoom*{f})':"
                     "d={n}:s={w}x{h}:fps=30,setsar=1[scr];").format(
                         n=int(dur * 30), f=focus, w=sw, h=sh)
            src_args = ['-i', source]
        else:
            seg = os.path.join(HERE, 'seg_%d.mp4' % i)
            cut = ['-i', source]
            if seek is not None:
                cut += ['-ss', str(seek)]
            run(cut + ['-t', str(dur), '-vf',
                       'fps=30,crop=1080:2116:0:92,scale=%d:%d,setsar=1'
                       % (sw, sh), '-an'] + ENC + [seg])
            first = '[1:v]setsar=1[scr];'
            src_args = ['-i', seg]

        out = os.path.join(HERE, 's%d.mp4' % i)
        run(['-loop', '1', '-i', os.path.join(art, 'bg.png')] + src_args +
            ['-loop', '1', '-i', os.path.join(art, 'mask.png'),
             '-loop', '1', '-i', os.path.join(art, 'plate.png'),
             '-loop', '1', '-i', os.path.join(art, 't%d.png' % i),
             '-filter_complex', first + graph, '-map', '[out]',
             '-t', str(dur)] + ENC + [out])
        paths.append((out, dur))
        print('scene %d  %-9s %.1fs  %s' % (i + 1, kicker, dur, headline))

    end = os.path.join(HERE, 's_end.mp4')
    frames = int(END_SECONDS * 30)
    run(['-loop', '1', '-i', os.path.join(art, 'endcard.png'),
         '-filter_complex',
         "[0:v]fps=30,scale=%d:%d,setsar=1,zoompan=z='1.04-0.04*on/%d':"
         "x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=%d:s=%dx%d:fps=30[out]"
         % (W, H, frames, frames, W, H),
         '-map', '[out]', '-t', str(END_SECONDS)] + ENC + [end])
    paths.append((end, END_SECONDS))
    return paths


def assemble(paths, out_path):
    args, chain, prev = [], [], '0:v'
    for path, _ in paths:
        args += ['-i', path]

    total = paths[0][1]
    for i in range(1, len(paths)):
        label = 'v%d' % i if i < len(paths) - 1 else 'v'
        chain.append('[%s][%d:v]xfade=transition=slideleft:duration=%s:'
                     'offset=%.3f[%s]'
                     % (prev, i, TRANSITION, total - TRANSITION, label))
        total = total + paths[i][1] - TRANSITION
        prev = label

    music = os.path.join(HERE, MUSIC)
    if os.path.exists(music):
        args += ['-i', music]
        chain.append(
            '[%d:a]atrim=0:%.3f,asetpts=PTS-STARTPTS,'
            'afade=t=in:st=0:d=0.06,afade=t=out:st=%.3f:d=%s,'
            'volume=%s,aformat=sample_fmts=fltp:sample_rates=44100:'
            'channel_layouts=stereo[a]'
            % (len(paths), total, total - MUSIC_FADE_OUT, MUSIC_FADE_OUT,
               MUSIC_GAIN))
        audio = '[a]'
    else:
        # Still ship a stereo track: Play and every feed expect one, and some
        # uploaders reject a file with no audio stream outright.
        args += ['-f', 'lavfi', '-i', 'anullsrc=r=44100:cl=stereo']
        audio = '%d:a' % len(paths)
        print('no music found at %s -- silent' % MUSIC)

    run(args + ['-filter_complex', ';'.join(chain), '-map', '[v]',
                '-map', audio, '-shortest',
                '-c:v', 'libx264', '-crf', '18', '-preset', 'slow',
                '-pix_fmt', 'yuv420p', '-r', '30', '-c:a', 'aac',
                '-b:a', '160k', '-movflags', '+faststart', out_path])
    print('%s  %.3fs' % (os.path.basename(out_path), total))


if __name__ == '__main__':
    lang = sys.argv[1] if len(sys.argv) > 1 else 'tr'
    shape = sys.argv[2] if len(sys.argv) > 2 else 'tall'
    if lang not in LANGS:
        raise SystemExit('language must be one of: %s' % ', '.join(LANGS))
    if shape not in LAYOUTS:
        raise SystemExit('shape must be one of: %s' % ', '.join(LAYOUTS))

    config, layout = LANGS[lang], LAYOUTS[shape]
    artdir = os.path.join(HERE, 'art_%s_%s' % (lang, shape))
    build_art(artdir, config, layout)
    name = ('klioai_promo_%s.mp4' % lang if shape == 'tall'
            else 'klioai_promo_%s_%s.mp4' % (lang, shape))
    assemble(build_scenes(artdir, config, layout), os.path.join(HERE, name))
