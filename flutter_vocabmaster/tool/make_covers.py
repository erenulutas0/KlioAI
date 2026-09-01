# -*- coding: utf-8 -*-
"""Prepare the shelf's cover images from Project Gutenberg.

    python tool/make_covers.py

Writes assets/covers/<slug>.jpg, one per book that has a real cover. The
outputs are committed, so this only needs running when a book is added or one
of these is replaced -- the app never fetches at runtime and the shelf works
with no network at all.

Why these images are usable: every title on this shelf was published before
1929 and its author died long ago (Potter in 1943, the rest earlier), so the
period cover art is public domain along with the text. The covers here are the
original bindings and title pages -- Warne's 1902 Peter Rabbit with Potter's
own drawing, the Victorian Aesop, the 1892 Sherlock in blue cloth. That is the
whole reason to use them rather than anything modern: a jacket designed this
century is still in copyright even when the words inside it are not.

HEART OF DARKNESS IS NOT HERE, ON PURPOSE. What Gutenberg serves for ebook 219
is not a cover at all -- it is a generated placeholder, blue and green
rectangles with "Project Gutenberg" printed across it. It would be the one
tile on the shelf that looked like a broken image, and it carries a name this
app has no business displaying. That book keeps the drawn spine, which is why
the spine had to stay in the code rather than being replaced outright.

Each image is padded, not cropped, to the shelf's aspect. Cropping was the
first idea and it fails on Jekyll and Hyde: at 174x300 it is much narrower
than the slot, and taking the difference off the height cuts the title off the
top. The pad colour is sampled from the image's own corners, so on the old
bindings it disappears into the board and on the title pages it reads as more
paper.
"""
import os
import urllib.request

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', 'assets', 'covers')

# Matches BookSpine's 52x74 slot. Stored at roughly 4.6x so the same file can
# be used somewhere larger later without refetching anything.
TARGET = (240, 342)

# slug -> Project Gutenberg ebook id. The ids are the ones BookLibrary.java
# already records in each book's `source` field; they are not looked up twice.
BOOKS = {
    'peter-rabbit': 14838,
    'aesops-fables': 21,
    'happy-prince': 902,
    'sherlock-adventures': 1661,
    'jekyll-and-hyde': 43,
    # 'heart-of-darkness': 219 -- placeholder, see the note above.
}

URL = 'https://www.gutenberg.org/cache/epub/{id}/pg{id}.cover.medium.jpg'


def pad_colour(im):
    """The average of the four corners, which on a bound book is the board."""
    w, h = im.size
    corners = [im.getpixel(p) for p in
               ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1))]
    return tuple(sum(c[i] for c in corners) // len(corners) for i in range(3))


def prepare(source_bytes, out_path):
    from io import BytesIO
    im = Image.open(BytesIO(source_bytes)).convert('RGB')

    target_ratio = TARGET[0] / TARGET[1]
    ratio = im.width / im.height
    if ratio > target_ratio:          # too wide: grow the height
        box = (im.width, round(im.width / target_ratio))
    else:                             # too tall: grow the width
        box = (round(im.height * target_ratio), im.height)

    canvas = Image.new('RGB', box, pad_colour(im))
    canvas.paste(im, ((box[0] - im.width) // 2, (box[1] - im.height) // 2))
    canvas.resize(TARGET, Image.LANCZOS).save(out_path, 'JPEG', quality=88,
                                              optimize=True)
    return im.size


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    total = 0
    for slug, book_id in BOOKS.items():
        with urllib.request.urlopen(URL.format(id=book_id), timeout=30) as r:
            raw = r.read()
        path = os.path.join(OUT, '%s.jpg' % slug)
        size = prepare(raw, path)
        written = os.path.getsize(path)
        total += written
        print('%-22s %sx%s -> %sx%s  %5d bytes'
              % (slug, size[0], size[1], TARGET[0], TARGET[1], written))
    print('%d covers, %.1f KB total' % (len(BOOKS), total / 1024))
