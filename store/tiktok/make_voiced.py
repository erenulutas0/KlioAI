# -*- coding: utf-8 -*-
"""A TikTok clip with sound: the learner's voice and Luca's, as recorded.

    python make_voiced.py waiter

The September clips (make_clip.py) were silent on purpose -- the voice was Piper
and a reply took three to six seconds, so the card was the thing to show. The
voice is the strongest thing the app has now, so these keep the recording's own
audio: Samsung's screen recorder with "media and microphone", which writes the
learner's English and Luca's reply into one stereo track.

Same shape as before -- hook, moment, name -- and the same crop and scale, so the
two families of clips sit together on the profile. The hook and end cards get a
silent audio track so the three parts concatenate with sound intact.

The cut seeks on the output side (-ss after -i) for the same reason make_clip.py
does: the recorder's timestamps are not uniform, and a sheet cut from the raw
file has disagreed with the segment by up to two seconds.
"""
import os
import subprocess
import sys

from make_clip import (BUILD, CROP_BOTTOM, CROP_TOP, FPS, GROUND, H, OUT, RAW,
                       W, duration_of, end_card, hook_card, run)

CLIPS = {
    # Two full exchanges, both short, no card: the loop the app is sold on --
    # hold, speak, the text lands, Luca answers out loud. Opens on the held
    # mic of the lasagne turn and ends as Luca finishes asking about water.
    'waiter': dict(
        src='rec_203050.mp4',
        start=129.5, end=158.8,
        keep=[(135.8, 142.6), (152.8, 158.8)],
        hook=(u'Yapay zekâ garsonla', u'İngilizce sipariş verdim'),
    ),
    # The learner asks for wine and a recommendation; the card lands at 111
    # with two fixes ("a glass of wine", "as well") while Luca is still
    # talking. His reply runs eighteen seconds, so the clip lets the card sit
    # for seven and fades him out rather than making the viewer wait it out.
    'wine': dict(
        src='rec_203050.mp4',
        start=97.5, end=118.0, fade_out=2.0,
        keep=[(109.8, 118.0)],
        hook=(u'Bunu sen de diyorsun:', u'I prefer glass of wine'),
    ),
}


def build(name):
    c = CLIPS[name]
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(BUILD, exist_ok=True)
    hook = os.path.join(BUILD, name + '_hook.png')
    end = os.path.join(BUILD, name + '_end.png')
    seg = os.path.join(BUILD, name + '_seg.mp4')
    out = os.path.join(OUT, 'klio_%s.mp4' % name)

    hook_card(hook, *c['hook'])
    end_card(end)

    src = os.path.join(RAW, c['src'])
    length = c['end'] - c['start']
    short_by = max(0.0, c['end'] - duration_of(src))
    crop_h = CROP_BOTTOM - CROP_TOP
    fade = c.get('fade_out', 0.0)
    audio = 'aresample=48000,aformat=channel_layouts=stereo'
    keep = c.get('keep')
    if keep:
        # Only Luca. The recorder mixes the microphone and the media into one
        # track, so the learner's own voice cannot be lifted out -- but the
        # turns never overlap: they speak while the button is held, Luca
        # answers after. Everything outside Luca's replies is muted, on the
        # raw file's clock like the fade below. Asked for after the first
        # cut: hearing their own English in the clip felt silly to them, and
        # the clip is about the reply anyway.
        spans = '+'.join('between(t,%.2f,%.2f)' % (a, b) for a, b in keep)
        audio += ",volume=0:enable='not(%s)'" % spans
        # The microphone stayed open while Luca spoke, so his part carries
        # the room. Denoise, cut the rumble, then bring him up to a feed
        # level: his replies sat at -27 dB mean in the take.
        audio += ',afftdn=nf=-28,highpass=f=100,volume=8dB,alimiter=limit=0.95'
    if fade:
        # On the raw file's clock, not the segment's. -ss after -i drops
        # frames after the filters have run, so a fade timed from zero would
        # fire in the first seconds of the raw file -- silence -- and leave
        # the part that is kept already faded out. Measured: the first build
        # of the wine clip had no sound at all.
        audio += ',afade=t=out:st=%.2f:d=%.2f' % (c['end'] - fade, fade)
    run(['ffmpeg', '-v', 'error', '-y',
         '-i', src,
         '-ss', str(c['start']), '-t', str(length),
         '-vf', ('crop=1080:%d:0:%d,scale=-2:%d,'
                 'pad=%d:%d:(ow-iw)/2:0:color=%s,fps=%d,'
                 'tpad=stop_mode=clone:stop_duration=%.2f,format=yuv420p'
                 % (crop_h, CROP_TOP, H, W, H, GROUND, FPS, short_by + 0.5)),
         '-af', audio,
         '-c:v', 'libx264', '-crf', '16', '-preset', 'slow',
         '-c:a', 'aac', '-b:a', '160k', seg])

    run(['ffmpeg', '-v', 'error', '-y', '-i', seg,
         '-vf', 'fps=2,scale=216:-1,tile=8x8', '-frames:v', '1',
         os.path.join(BUILD, name + '_seg_sheet.png')])

    run(['ffmpeg', '-v', 'error', '-y',
         '-loop', '1', '-t', '2', '-i', hook,
         '-i', seg,
         '-loop', '1', '-t', '3', '-i', end,
         '-f', 'lavfi', '-t', '2', '-i', 'anullsrc=r=48000:cl=stereo',
         '-f', 'lavfi', '-t', '3', '-i', 'anullsrc=r=48000:cl=stereo',
         '-filter_complex',
         ('[0]fps=%d,format=yuv420p[a];'
          '[1:v]fps=%d,format=yuv420p[b];'
          '[2]fps=%d,format=yuv420p[c];'
          '[a][3:a][b][1:a][c][4:a]concat=n=3:v=1:a=1[v][au]'
          % (FPS, FPS, FPS)),
         '-map', '[v]', '-map', '[au]',
         '-c:v', 'libx264', '-crf', '16', '-preset', 'slow',
         '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '160k',
         '-movflags', '+faststart', out])
    print('wrote', out)


if __name__ == '__main__':
    build(sys.argv[1] if len(sys.argv) > 1 else 'waiter')
