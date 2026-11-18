#!/usr/bin/env python3
"""Make the C64 start-up picture from the original PSS cassette inlay, as a multicolour bitmap.

  python3 tools/make_intro.py

Laid out for the C64's multicolour resolution (160x200, double-wide pixels) in C64 colour numbers: on black with
the inlay's blue grid, the cover painting (docs/images/original/cover.png) on the left in its white frame; on
the right the PSS logo (cut from docs/images/original/inlay.png), PERSONAL SOFTWARE SERVICES and a cyan strip with
the strapline, as on the inlay. The painting is converted per 4x8 cell: each cell keeps the shared background
(black) plus the three colours that match it best, then the whole picture is error-diffused within each cell's
four colours.

Writes c64/src/intro.rle (bitmap, screen and colour RAM, each run-length packed; see Unpack in c64/src/intro.s) and
docs/images/graphics/intro-design.png (a preview at double width). Needs Pillow. Same method and packing as the
Light Cycle port's tools/make_intro.py.
"""
import itertools
import os

from PIL import Image, ImageEnhance

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
W, H = 160, 200
COVER = os.path.join(ROOT, 'docs', 'images', 'original', 'cover.png')
INLAY = os.path.join(ROOT, 'docs', 'images', 'original', 'inlay.png')
PREVIEW = os.path.join(ROOT, 'docs', 'images', 'graphics', 'intro-design.png')
OUT = os.path.join(ROOT, 'c64', 'src', 'intro.rle')

# Pepto's measured C64 palette.
PALETTE = [(0, 0, 0), (255, 255, 255), (104, 55, 43), (112, 164, 178), (111, 61, 134), (88, 141, 67), (53, 40, 121),
           (184, 199, 111), (111, 79, 37), (67, 57, 0), (154, 103, 89), (68, 68, 68), (108, 108, 108),
           (154, 210, 132), (108, 94, 181), (149, 149, 149)]
BLACK, WHITE, RED, CYAN, PURPLE, GREEN, BLUE, YELLOW, ORANGE, BROWN, LRED, DGREY, GREY, LGREEN, LBLUE, LGREY = range(16)
BG = BLACK                              # the shared background colour

# Where things go, in multicolour pixels.
PANEL = (8, 4, 80, 196)                 # the cover painting, frame included (x0, y0, x1, y1)
COVER_CROP = (12, 84, 298, 470)         # the painting and its frame in cover.png (a straight scan)
LOGO_CROP = (192, 32, 380, 110)         # the PSS logo in inlay.png
RIGHT_X0, RIGHT_X1 = 86, 156            # the right-hand column
WHITE_BALANCE = (0.88, 1.0, 1.18)      # R, G, B: the scan is warm (aged card); cool it so the sky stays blue
BRIGHTNESS, SATURATION, CONTRAST = 0.9, 1.8, 1.25  # the scan is pale and the C64 palette muted: deepen it
PAINT_EXCLUDE = (RED, PURPLE, LRED)     # never in the painting: they turned the sky and road pink
DIFFUSE = 0.6                           # error carried on; less than 1 keeps flat areas quiet

# 3x5 font for the small lettering (only the characters used); M and W are 5 wide.
SMALL = {
    'A': '010101111101101', 'C': '011100100100011', 'D': '110101101101110', 'E': '111100110100111',
    'F': '111100110100100', 'I': '111010010010111', 'L': '100100100100111', 'M': '1000111011101011000110001',
    'N': '110101101101101', 'O': '010101101101010', 'P': '110101110100100', 'R': '110101110101101',
    'S': '011100010001110', 'T': '111010010010010', 'V': '101101101101010', 'W': '1000110001101011010101010',
    'U': '101101101101111', 'H': '101101111101101', 'G': '011100101101011', 'Y': '101101010010010',
    '6': '011100111101111', '4': '101101111001001', ' ': '000000000000000', '.': '000000000000010',
}


def text_width(text):
    return sum(len(SMALL[ch]) // 5 for ch in text) + len(text) - 1


def small_text(px, text, cx, y, colour):
    x = cx - text_width(text) // 2
    for ch in text:
        bits = SMALL[ch]
        w = len(bits) // 5
        for r in range(5):
            for c in range(w):
                if bits[r * w + c] == '1':
                    px[x + c, y + r] = colour
        x += w + 1


def fill(px, box, colour):
    x0, y0, x1, y1 = box
    for y in range(y0, y1):
        for x in range(x0, x1):
            px[x, y] = colour


def dist(a, b):
    """Squared colour distance, weighted for the eye (redmean)."""
    rm = (a[0] + b[0]) / 2
    dr, dg, db = a[0] - b[0], a[1] - b[1], a[2] - b[2]
    return (2 + rm / 256) * dr * dr + 4 * dg * dg + (2 + (255 - rm) / 256) * db * db


def painting():
    """The cover painting, scaled to the panel: a W x H grid of RGB tuples (None outside)."""
    x0, y0, x1, y1 = PANEL
    src = Image.open(COVER).convert('RGB').crop(COVER_CROP).resize((x1 - x0, y1 - y0), Image.LANCZOS)
    src = Image.merge('RGB', [band.point(lambda v, f=f: min(255, int(v * f)))
                              for band, f in zip(src.split(), WHITE_BALANCE)])
    src = ImageEnhance.Brightness(src).enhance(BRIGHTNESS)
    src = ImageEnhance.Contrast(ImageEnhance.Color(src).enhance(SATURATION)).enhance(CONTRAST)
    grid = [[None] * W for _ in range(H)]
    for y in range(y1 - y0):
        for x in range(x1 - x0):
            grid[y0 + y][x0 + x] = src.getpixel((x, y))
    return grid


def logo_mask(w, h):
    """The PSS logo from the inlay, as a w x h mask: the light-blue lettering, not its dark outline."""
    src = Image.open(INLAY).convert('RGB').crop(LOGO_CROP).resize((w, h), Image.BOX)
    return [[src.getpixel((x, y))[1] > 108 for x in range(w)] for y in range(h)]


def layout():
    """Everything but the painting, as fixed C64 colours (None where the painting goes)."""
    img = Image.new('P', (W, H), BG)
    px = img.load()
    # The inlay's blue grid.
    for y in range(H):
        for x in range(W):
            if y % 20 == 10 or x % 10 == 4:
                px[x, y] = BLUE
    # PSS logo: cyan lettering, a blue drop shadow, on black.
    lw, lh = 64, 26
    lx, ly = (RIGHT_X0 + RIGHT_X1 - lw) // 2, 24
    fill(px, (lx - 2, ly - 3, lx + lw + 3, ly + lh + 3), BLACK)
    mask = logo_mask(lw, lh)
    for y in range(lh):
        for x in range(lw):
            if mask[y][x]:
                px[lx + x + 1, ly + y + 1] = BLUE
    for y in range(lh):
        for x in range(lw):
            if mask[y][x]:
                px[lx + x, ly + y] = CYAN
    cx = (RIGHT_X0 + RIGHT_X1) // 2
    fill(px, (RIGHT_X0, 58, RIGHT_X1, 88), BLACK)
    for i, word in enumerate(('PERSONAL', 'SOFTWARE', 'SERVICES')):
        small_text(px, word, cx, 60 + i * 9, WHITE)
    # The strapline, in the inlay's cyan strip.
    fill(px, (RIGHT_X0, 150, RIGHT_X1, 174), CYAN)
    small_text(px, 'ARCADE ACTION', cx, 154, BLACK)
    small_text(px, 'FOR COMMODORE 64', cx, 164, BLACK)
    return img


def convert(fixed, paint):
    """Choose each cell's colours and error-diffuse the painting into them. Returns a W x H list of C64 colours."""
    fx = fixed.load()
    out = [[fx[x, y] for x in range(W)] for y in range(H)]
    allowed = {}
    for cy in range(25):
        for cx in range(40):
            cells = [(x, y) for y in range(cy * 8, cy * 8 + 8) for x in range(cx * 4, cx * 4 + 4)]
            rgb = [paint[y][x] for x, y in cells if paint[y][x] is not None]
            if not rgb:
                continue
            fixed_cols = {out[y][x] for x, y in cells if paint[y][x] is None} - {BG}
            # error of each pixel against each colour, then the best set of three
            errs = [[dist(p, PALETTE[c]) for c in range(16)] for p in rgb]
            best, best_err = None, None
            for combo in itertools.combinations([c for c in range(1, 16) if c not in PAINT_EXCLUDE], 3):
                if not fixed_cols <= set(combo):
                    continue
                cols = (BG,) + combo
                e = sum(min(row[c] for c in cols) for row in errs)
                if best_err is None or e < best_err:
                    best, best_err = cols, e
            allowed[cx, cy] = best
    # Floyd-Steinberg over the painting, each pixel limited to its cell's colours.
    work = [[list(p) if p is not None else None for p in row] for row in paint]
    for y in range(H):
        for x in range(W):
            p = work[y][x]
            if p is None:
                continue
            cols = allowed[x // 4, y // 8]
            c = min(cols, key=lambda k: dist(p, PALETTE[k]))
            out[y][x] = c
            err = [(p[i] - PALETTE[c][i]) * DIFFUSE for i in range(3)]
            for dx, dy, f in ((1, 0, 7 / 16), (-1, 1, 3 / 16), (0, 1, 5 / 16), (1, 1, 1 / 16)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < W and 0 <= ny < H and work[ny][nx] is not None:
                    q = work[ny][nx]
                    for i in range(3):
                        q[i] += err[i] * f
    return out


def encode(pixels):
    bitmap, screen, colram = bytearray(8000), bytearray(1000), bytearray(1000)
    for cy in range(25):
        for cx in range(40):
            counts = {}
            for y in range(8):
                for x in range(4):
                    c = pixels[cy * 8 + y][cx * 4 + x]
                    if c != BG:
                        counts[c] = counts.get(c, 0) + 1
            chosen = sorted(counts, key=lambda c: -counts[c])
            assert len(chosen) <= 3, (cx, cy, chosen)
            chosen += [BLACK] * (3 - len(chosen))
            slots = {BG: 0, chosen[0]: 1, chosen[1]: 2, chosen[2]: 3}
            screen[cy * 40 + cx] = chosen[0] << 4 | chosen[1]
            colram[cy * 40 + cx] = chosen[2]
            for y in range(8):
                byte = 0
                for x in range(4):
                    byte = byte << 2 | slots[pixels[cy * 8 + y][cx * 4 + x]]
                bitmap[cy * 320 + cx * 8 + y] = byte
    return bitmap, screen, colram


def rle(data):
    """$FE n v = n copies of v (n 1-255); $FE 0 = end; any other byte is itself."""
    out, i = bytearray(), 0
    while i < len(data):
        v, n = data[i], 1
        while i + n < len(data) and data[i + n] == v and n < 255:
            n += 1
        if n >= 4 or v == 0xFE:
            out += bytes((0xFE, n, v))
        else:
            out += bytes([v]) * n
        i += n
    return out + b'\xfe\x00'


def main():
    pixels = convert(layout(), painting())
    bitmap, screen, colram = encode(pixels)
    packed = rle(bitmap) + rle(screen) + rle(colram)
    open(OUT, 'wb').write(packed)
    preview = Image.new('P', (W, H))
    for y in range(H):
        for x in range(W):
            preview.putpixel((x, y), pixels[y][x])
    preview.putpalette([v for rgb in PALETTE for v in rgb])
    os.makedirs(os.path.dirname(PREVIEW), exist_ok=True)
    preview.convert('RGB').resize((W * 2 * 2, H * 2), Image.NEAREST).save(PREVIEW, optimize=True)
    print('%s: %d bytes (from %d)' % (os.path.relpath(OUT, ROOT), len(packed), 10000))
    print(os.path.relpath(PREVIEW, ROOT))


if __name__ == '__main__':
    main()
