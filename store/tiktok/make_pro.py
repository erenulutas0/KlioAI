# -*- coding: utf-8 -*-
"""A TikTok clip that looks made, not captured.

    python make_pro.py waiter

make_voiced.py showed the app; this shows it the way a studio would. The
screen recording sits in a phone -- rounded corners, a bezel, a soft shadow --
on a branded gradient, with a headline that stays up, captions under the phone
that follow Luca's voice line by line (English, and Turkish under it, for the
two thirds of the feed that watches muted), short notes over the moments where
nothing is said (the held button, the transcript landing), a slow push-in, a
freeze and zoom on the card when it lands, and a cross-fade into the end card.

Two passes. The first cuts the moment out of the raw recording -- video to one
file, audio to another, the audio shaped on the way: only Luca, denoised,
brought up -- on the raw file's clock, where -ss after -i puts the filters. The
second composes everything on the cut's own clock, from zero, so every caption,
freeze and zoom is timed against what the viewer sees. One clock per pass is
what makes the timings trustworthy.

The phone is cropped above the app's own tab bar. The chat keeps its newest
bubble at the bottom of the list, right above the microphone panel, so there is
no strip on the screen a caption can sit on without covering the line the
viewer is meant to read; the first cut put them there and they covered exactly
that. Shortening the phone leaves room for them underneath, still above the
band where TikTok draws its description.

TikTok draws its own interface over the video: the tab bar across the top, the
like/comment/share column down the right, and the caption block across the
bottom. Text is kept clear of all three.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

from make_clip import (BLACK_F, BUILD, CROP_TOP, FPS, ICON, OUT, RAW, SEMI_F,
                       duration_of, run)

W, H = 1080, 1920

# Brand.
DEEP = (15, 13, 28)
DEEP_TOP = (28, 24, 54)
ACCENT = (110, 92, 246)
WHITE = (255, 255, 255)
DIM = (196, 192, 220)
NOTE = (186, 176, 255)
BEZEL = (38, 34, 64)

# The phone. The screen is the recording from under the status bar to just
# under the microphone button -- its label, the app's tab bar and the system
# bar are left out. (The button's centre is at y=1735 of the 2340-pixel
# recording; a first pass read it off a scaled screenshot as 1480 and cut
# the button in half.) 700 wide keeps the app's type readable in a feed and
# leaves the captions above the band TikTok draws its description in.
CROP_BOTTOM = 1840
CROP_H = CROP_BOTTOM - CROP_TOP
SW = 700
SH = int(round(SW * CROP_H / 1080.0))
PX, PY = (W - SW) // 2, 330
RADIUS = 48

# Captions: under the phone, above TikTok's description band.
CAP_Y = PY + SH + 44

CLIPS = {
    'waiter': dict(
        src='rec_203050.mp4', start=129.5, end=158.8,
        keep=[(135.8, 142.6), (152.8, 158.8)],
        hook=(u'Yapay zekâ garsonla', u'İngilizce sipariş verdim'),
        zoom='push',
        captions=[
            (0.0, 2.4, None, u'Basılı tut, İngilizce konuş'),
            (2.6, 6.2, None, u'Söylediğin anında yazıya dönüyor'),
            (6.4, 7.6, u'Excellent choice.', u'Harika seçim.'),
            (7.7, 9.6, u'Would you like a side salad with it,', u'Yanında salata ister misiniz,'),
            (9.7, 11.9, u'and any extra Parmesan on top?', u'üstüne biraz da parmesan?'),
            (13.6, 20.3, None, u'Sıra sende: basılı tut, cevap ver'),
            (20.5, 23.9, None, u'Luca dinledi, düşünüyor…'),
            (24.0, 26.1, u'Red wine, glass or bottle?', u'Kırmızı şarap; kadeh mi, şişe mi?'),
            (26.2, 29.3, u'And would you like still or sparkling water with your meal?',
             u'Yemeğin yanına sade su mu, soda mı?'),
        ],
    ),
    'wine': dict(
        src='rec_203050.mp4', start=97.5, end=118.0, fade_out=2.0,
        keep=[(109.8, 118.0)],
        hook=(u'Bunu sen de diyorsun:', u'I prefer glass of wine'),
        # The card lands 13.0 s into the cut, the list settles on it by 13.3
        # and scrolls past it a second later. The picture freezes on the
        # settled frame while Luca goes on talking: the card is what this clip
        # is about. Its title never fits above the reply in this take; the two
        # fixes and their notes do.
        freeze=13.5,
        zoom=('card', 13.5),
        captions=[
            (0.6, 8.4, None, u'Basılı tut, İngilizce söyle — hata yapmak serbest'),
            (8.6, 12.3, None, u'Luca dinliyor…'),
            (12.6, 14.9, u'A glass of our house red will be perfect —',
             u'Ev şarabımızdan bir kadeh harika olur —'),
            (15.2, 17.7, u'would you like a bottle or just one glass?',
             u'şişe mi, tek kadeh mi?'),
            (18.0, 20.5, None, u'Ve hatanı kartla düzeltiyor ↑'),
        ],
    ),
    'wine_fast': dict(
        # The same moment without the wait. The first cut opened on twelve silent
        # seconds -- the button held while the learner spoke, their voice taken out --
        # and the waiter clip, which opened on six, averaged 3.5 seconds of watching on
        # TikTok. This one opens as the sentence lands and jumps the typing dots, so
        # Luca speaks inside a second and a half and the card is up at two.
        src='rec_203050.mp4',
        segments=[(107.6, 108.6), (109.7, 118.0)],
        fade_out=2.0,
        keep=[(109.8, 118.0)],
        hook=(u'Bunu sen de diyorsun:', u'I prefer glass of wine'),
        # On the first frame, not faded in: the first frame is what the feed shows.
        hook_fade=False,
        freeze=2.3,
        zoom=('card', 2.3),
        captions=[
            (0.0, 1.0, None, u'Söyledim, anında yazıya döndü'),
            (1.4, 3.7, u'A glass of our house red will be perfect —',
             u'Ev şarabımızdan bir kadeh harika olur —'),
            (4.0, 6.5, u'would you like a bottle or just one glass?',
             u'şişe mi, tek kadeh mi?'),
            (6.8, 9.3, None, u'Ve hatanı kartla düzeltiyor ↑'),
        ],
    ),
}


def font(path, size):
    return ImageFont.truetype(path, size)


def fit(d, text, path, size, max_w, floor=28):
    """The largest size at or under [size] that keeps [text] inside [max_w]."""
    while size > floor:
        f = font(path, size)
        if d.textlength(text, font=f) <= max_w:
            return f
        size -= 2
    return font(path, floor)


def centred(d, y, text, f, fill):
    d.text((W // 2, y), text, font=f, fill=fill, anchor='mt')


def two_lines(d, text, f, max_w):
    """[text] on one line if it fits, else broken at the space nearest the middle."""
    if d.textlength(text, font=f) <= max_w or ' ' not in text:
        return [text]
    spaces = [i for i, ch in enumerate(text) if ch == ' ']
    cut = min(spaces, key=lambda i: abs(i - len(text) // 2))
    return [text[:cut], text[cut + 1:]]


def gradient():
    im = Image.new('RGB', (W, H), DEEP)
    d = ImageDraw.Draw(im)
    for y in range(H):
        t = y / float(H - 1)
        c = tuple(int(DEEP_TOP[i] + (DEEP[i] - DEEP_TOP[i]) * t) for i in range(3))
        d.line([(0, y), (W, y)], fill=c)
    # A soft brand glow behind the upper half of the phone.
    glow = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse((-100, 200, W + 100, 1300), fill=ACCENT + (70,))
    glow = glow.filter(ImageFilter.GaussianBlur(220))
    return Image.alpha_composite(im.convert('RGBA'), glow)


def background(path):
    """Gradient, glow, the phone's shadow and bezel. The screen is composited
    on top by ffmpeg, through the mask below."""
    im = gradient()
    shadow = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        (PX, PY + 36, PX + SW, PY + SH + 36), radius=RADIUS + 12, fill=(0, 0, 0, 170))
    shadow = shadow.filter(ImageFilter.GaussianBlur(42))
    im = Image.alpha_composite(im, shadow)
    d = ImageDraw.Draw(im)
    b = 12
    d.rounded_rectangle((PX - b, PY - b, PX + SW + b, PY + SH + b),
                        radius=RADIUS + b, fill=BEZEL)
    im.convert('RGB').save(path)


def screen_mask(path):
    """White inside the rounded screen, black outside: alphamerge reads it as alpha."""
    im = Image.new('L', (SW, SH), 0)
    ImageDraw.Draw(im).rounded_rectangle((0, 0, SW - 1, SH - 1), radius=RADIUS, fill=255)
    im.save(path)


def headline(path, line1, line2):
    im = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    centred(d, 166, line1, font(SEMI_F, 42), DIM)
    centred(d, 214, line2, fit(d, line2, BLACK_F, 66, W - 160), WHITE)
    im.save(path)


def caption(path, en, tr):
    """One caption under the phone: English over Turkish, or a single Turkish
    note in the brand colour when nothing is being said."""
    im = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    y = CAP_Y
    if en:
        fe = font(SEMI_F, 40)
        lines = two_lines(d, en, fe, W - 200)
        if len(lines) == 2:
            fe = font(SEMI_F, 37)
        for line in lines:
            centred(d, y, line, fe, WHITE)
            y += 46
        centred(d, y + 4, tr, fit(d, tr, SEMI_F, 31, W - 200), DIM)
    else:
        centred(d, y + 6, tr, fit(d, tr, SEMI_F, 36, W - 200), NOTE)
    im.save(path)


def end_card(path):
    im = gradient()
    icon = Image.open(ICON).convert('RGBA').resize((300, 300), Image.LANCZOS)
    im.paste(icon, (W // 2 - 150, 540), icon)
    d = ImageDraw.Draw(im)
    centred(d, 880, 'KlioAI', font(BLACK_F, 120), WHITE)
    centred(d, 1030, u'Konuşarak İngilizce öğren', font(SEMI_F, 48), DIM)
    centred(d, 1108, u'Restoranda · Kafede · Havalimanında · Otelde',
            font(SEMI_F, 34), NOTE)
    label = u"Play Store'da ücretsiz"
    f = font(SEMI_F, 52)
    tw = d.textlength(label, font=f)
    x0, x1 = W // 2 - tw // 2 - 48, W // 2 + tw // 2 + 48
    d.rounded_rectangle((x0, 1210, x1, 1314), radius=52, fill=ACCENT)
    centred(d, 1234, label, f, WHITE)
    im.convert('RGB').save(path)


def zoom_expr(kind, frames):
    """zoompan expressions on the cut's frame counter."""
    if kind == 'push':
        # 1.00 -> 1.04 over the whole clip: enough to feel alive, not enough
        # to notice.
        return ("1+0.04*on/%d" % frames, 'iw/2-(iw/zoom/2)', 'ih/2-(ih/zoom/2)')
    at = int(round(kind[1] * FPS))
    # 1.00 until the card, then to 1.12 over fifteen frames, anchored to the
    # top: centred, the zoom took the top off the character's name, and what
    # it can spare is the microphone panel at the bottom.
    return ("if(lt(on,%d),1,1+0.12*min(1,(on-%d)/15))" % (at, at),
            'iw/2-(iw/zoom/2)', '0')


def cut(name, c):
    """Pass one: the moment, cropped, at constant rate; Luca's voice beside it."""
    src = os.path.join(RAW, c['src'])
    video = os.path.join(BUILD, name + '_cut.mp4')
    audio_out = os.path.join(BUILD, name + '_cut.m4a')
    length = c['end'] - c['start']
    short_by = max(0.0, c['end'] - duration_of(src))
    run(['ffmpeg', '-v', 'error', '-y', '-i', src,
         '-ss', str(c['start']), '-t', str(length), '-an',
         '-vf', 'crop=1080:%d:0:%d,fps=%d,tpad=stop_mode=clone:stop_duration=%.2f'
                % (CROP_H, CROP_TOP, FPS, short_by + 0.5),
         '-c:v', 'libx264', '-crf', '14', '-preset', 'medium', video])
    audio = 'aresample=48000,aformat=channel_layouts=stereo'
    spans = '+'.join('between(t,%.2f,%.2f)' % (a, b) for a, b in c['keep'])
    audio += ",volume=0:enable='not(%s)'" % spans
    audio += ',afftdn=nf=-28,highpass=f=100,volume=8dB,alimiter=limit=0.95'
    fade = c.get('fade_out', 0.0)
    if fade:
        audio += ',afade=t=out:st=%.2f:d=%.2f' % (c['end'] - fade, fade)
    run(['ffmpeg', '-v', 'error', '-y', '-i', src,
         '-ss', str(c['start']), '-t', str(length), '-vn',
         '-af', audio, '-c:a', 'aac', '-b:a', '160k', audio_out])
    return video, audio_out, length


def cut_segments(name, c):
    """Pass one for a clip made of several moments: each is cut on the raw file's
    clock exactly as [cut] cuts one, so the voice spans and the fade keep meaning
    what they say, and the pieces are joined end to end."""
    parts = []
    last = len(c['segments']) - 1
    for i, (a, b) in enumerate(c['segments']):
        part = dict(c, start=a, end=b, fade_out=c.get('fade_out', 0.0) if i == last else 0.0)
        parts.append(cut('%s_seg%d' % (name, i), part))
    video = os.path.join(BUILD, name + '_cut.mp4')
    audio = os.path.join(BUILD, name + '_cut.m4a')
    n = len(parts)
    args = ['ffmpeg', '-v', 'error', '-y']
    for v, _, _ in parts:
        args += ['-i', v]
    run(args + ['-filter_complex',
                ''.join('[%d:v]' % i for i in range(n)) + 'concat=n=%d:v=1:a=0[v]' % n,
                '-map', '[v]', '-c:v', 'libx264', '-crf', '14', '-preset', 'medium', video])
    args = ['ffmpeg', '-v', 'error', '-y']
    for _, au, _ in parts:
        args += ['-i', au]
    run(args + ['-filter_complex',
                ''.join('[%d:a]' % i for i in range(n)) + 'concat=n=%d:v=0:a=1[a]' % n,
                '-map', '[a]', '-c:a', 'aac', '-b:a', '160k', audio])
    return video, audio, sum(length for _, _, length in parts)


def compose(name, c, video, audio, length):
    """Pass two: everything on the cut's own clock."""
    bg = os.path.join(BUILD, name + '_pro_bg.png')
    mask = os.path.join(BUILD, name + '_pro_mask.png')
    head = os.path.join(BUILD, name + '_pro_head.png')
    end = os.path.join(BUILD, name + '_pro_end.png')
    out = os.path.join(OUT, 'klio_%s_pro.mp4' % name)
    background(bg)
    screen_mask(mask)
    headline(head, *c['hook'])
    end_card(end)

    caps = []
    for i, (a, b, en, tr) in enumerate(c['captions']):
        p = os.path.join(BUILD, '%s_pro_cap%02d.png' % (name, i))
        caption(p, en, tr)
        caps.append((a, b, p))

    frames = int(round(length * FPS))
    z, zx, zy = zoom_expr(c['zoom'], frames)

    still = ['-framerate', str(FPS), '-loop', '1']
    args = ['ffmpeg', '-v', 'warning', '-y',
            '-i', video,                                   # 0
            '-i', audio,                                   # 1
            *still, '-t', str(length), '-i', bg,           # 2
            *still, '-t', str(length), '-i', mask,         # 3
            *still, '-t', str(length), '-i', head]         # 4
    first_cap = 5
    for a, b, p in caps:
        args += [*still, '-t', str(length), '-i', p]
    end_idx = first_cap + len(caps)
    args += [*still, '-t', '3', '-i', end]

    f = []
    src = '0:v'
    freeze = c.get('freeze')
    if freeze:
        # The frame at [freeze] held to the end; the sound goes on underneath.
        f.append('[0:v]split[fa][fb]')
        f.append('[fa]trim=end=%.2f,setpts=PTS-STARTPTS[fa1]' % freeze)
        f.append('[fb]trim=start=%.2f:end=%.2f,setpts=PTS-STARTPTS,'
                 'loop=loop=-1:size=1,trim=end=%.2f,setpts=PTS-STARTPTS[fb1]'
                 % (freeze, freeze + 0.1, length - freeze))
        f.append('[fa1][fb1]concat=n=2:v=1:a=0[fz]')
        src = 'fz'
    f.append("[%s]zoompan=z='%s':x='%s':y='%s':d=1:s=%dx%d:fps=%d[z]"
             % (src, z, zx, zy, SW, SH, FPS))
    f.append('[3:v]format=gray[m]')
    f.append('[z][m]alphamerge[scr]')
    f.append('[2:v][scr]overlay=%d:%d:shortest=1[v0]' % (PX, PY))
    if c.get('hook_fade', True):
        f.append('[4:v]format=rgba,fade=t=in:st=0.15:d=0.5:alpha=1[hl]')
    else:
        f.append('[4:v]format=rgba[hl]')
    f.append('[v0][hl]overlay=0:0[v1]')
    cur = 'v1'
    for i, (a, b, p) in enumerate(caps):
        idx = first_cap + i
        f.append("[%d:v]format=rgba,fade=t=in:st=%.2f:d=0.22:alpha=1,"
                 "fade=t=out:st=%.2f:d=0.22:alpha=1[k%d]" % (idx, a, b - 0.22, i))
        f.append("[%s][k%d]overlay=0:0:enable='between(t,%.2f,%.2f)'[v%d]"
                 % (cur, i, a, b, i + 2))
        cur = 'v%d' % (i + 2)
    f.append('[%s]format=yuv420p[main]' % cur)
    f.append('[%d:v]fps=%d,format=yuv420p[endv]' % (end_idx, FPS))
    f.append('[main][endv]xfade=transition=fade:duration=0.6:offset=%.2f[v]'
             % (length - 0.6))
    f.append('[1:a]apad=pad_dur=2.4[au]')

    run(args + ['-filter_complex', ';'.join(f),
                '-map', '[v]', '-map', '[au]',
                '-c:v', 'libx264', '-crf', '16', '-preset', 'slow',
                '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '160k',
                '-movflags', '+faststart', out])
    print('wrote', out)
    return out


def build(name):
    c = CLIPS[name]
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(BUILD, exist_ok=True)
    video, audio, length = cut_segments(name, c) if 'segments' in c else cut(name, c)
    compose(name, c, video, audio, length)


if __name__ == '__main__':
    build(sys.argv[1] if len(sys.argv) > 1 else 'waiter')
