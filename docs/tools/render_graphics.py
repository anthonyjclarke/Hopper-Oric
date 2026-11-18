#!/usr/bin/env python3
"""Decode HOPPER's graphics from the Oric tape into the handbook's figures.

  python3 docs/tools/render_graphics.py

Reads the program from original/HOPPER.TAP and finds every table by its label in build/hopper.lbl (run `make`
first). Glyphs are drawn 6 pixels wide, as the Oric shows them. The Oric screens are drawn by the game's own routines
running on tools/cpu6502.py (tools/oric_screens.py), then rendered with the Oric's serial attributes: ink, paper,
double height and inverse. The Oric ROM font is not on the tape, so letters come from VICE's C64 character ROM,
narrowed to 6 pixels. Writes docs/images/graphics/. Needs Pillow. Deterministic.
"""
import os
import sys

from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
OUT = os.path.join(ROOT, 'docs', 'images', 'graphics')
LBL = os.path.join(ROOT, 'build', 'hopper.lbl')
CHARGEN = '/opt/homebrew/share/vice/C64/chargen-901225-01.bin'
sys.path.insert(0, os.path.join(ROOT, 'tools'))
import oric_screens  # noqa: E402

# The Oric's eight colours.
ORIC = [(0, 0, 0), (255, 0, 0), (0, 255, 0), (255, 255, 0), (0, 0, 255), (255, 0, 255), (0, 255, 255),
        (255, 255, 255)]
CHARSET, SCREEN, ROWS, COLS = 0xB400, 0xBB80, 28, 40
GRID = (60, 60, 60)


def labels():
    out = {}
    for line in open(LBL):
        parts = line.split()
        if len(parts) == 3 and parts[0] == 'al':
            out[parts[2].lstrip('.')] = int(parts[1], 16)
    return out


def tape():
    """The program as a 64K memory image (ColdStart's hi-score copy included)."""
    return oric_screens.load()


def glyph(mem, addr, scale, ink=(255, 255, 255), paper=(0, 0, 0)):
    img = Image.new('RGB', (6 * scale, 8 * scale), paper)
    d = ImageDraw.Draw(img)
    for y in range(8):
        bits = mem[addr + y]
        for x in range(6):
            if bits & (0x20 >> x):
                d.rectangle((x * scale, y * scale, x * scale + scale - 1, y * scale + scale - 1), fill=ink)
    return img


def block(mem, addrs, cols, scale, ink=(255, 255, 255), paper=(0, 0, 0)):
    """Characters (8-byte addresses) laid out cols wide, row by row."""
    rows = (len(addrs) + cols - 1) // cols
    img = Image.new('RGB', (cols * 6 * scale, rows * 8 * scale), paper)
    for i, a in enumerate(addrs):
        img.paste(glyph(mem, a, scale, ink, paper), ((i % cols) * 6 * scale, (i // cols) * 8 * scale))
    return img


def row_of(images, gap, bg=(0, 0, 0)):
    w = sum(i.width for i in images) + gap * (len(images) + 1)
    h = max(i.height for i in images) + gap * 2
    out = Image.new('RGB', (w, h), bg)
    x = gap
    for i in images:
        out.paste(i, (x, gap))
        x += i.width + gap
    return out


def save(img, name):
    img.save(os.path.join(OUT, name), optimize=True)
    print('docs/images/graphics/' + name)


def frog_figures(mem, lab):
    green = ORIC[2]
    frogs = [block(mem, [lab['frog_gfx'] + d * 32 + c * 8 for c in range(4)], 2, 8, green) for d in range(4)]
    save(row_of(frogs, 16), 'frog-directions.png')
    save(row_of([block(mem, [lab['frog_gfx'] + c * 8 for c in range(4)], 2, 5, green)], 6), 'frog-icon.png')
    save(row_of([block(mem, [lab['home_gfx'] + c * 8 for c in range(4)], 2, 8, green),
                 block(mem, [lab['splat_gfx'] + c * 8 for c in range(4)], 2, 8, ORIC[1])], 16), 'home-and-splat.png')
    frames = [block(mem, [lab['turtle_frames'] + f * 48 + c * 8 for c in range(6)], 3, 6, ORIC[1], ORIC[4])
              for f in range(7)]
    save(row_of(frames, 12), 'turtle-frames.png')
    order = list(range(7)) + list(range(5, 0, -1))           # down to frame 6 and back up, as AnimateTurtles does
    gif = [row_of([frames[f]], 12) for f in order]
    gif[0].save(os.path.join(OUT, 'turtle-dive.gif'), save_all=True, append_images=gif[1:], duration=180, loop=0)
    print('docs/images/graphics/turtle-dive.gif')


def charset_sheet(mem, lab):
    """Every character the game redefines, with its code: $21-$2A, $5B-$7F (InitGame's copies)."""
    codes = list(range(0x21, 0x2B)) + list(range(0x5B, 0x80))
    srcs = [lab['udg_symbols'] + (c - 0x21) * 8 for c in codes[:10]] + \
           [lab['udg_graphics'] + (c - 0x5B) * 8 for c in codes[10:]]
    scale, cols = 6, 12
    cw, ch = 6 * scale + 10, 8 * scale + 22
    rows = (len(codes) + cols - 1) // cols
    img = Image.new('RGB', (cols * cw + 10, rows * ch + 10), (24, 24, 24))
    d = ImageDraw.Draw(img)
    for i, (code, src) in enumerate(zip(codes, srcs)):
        x, y = 10 + (i % cols) * cw, 10 + (i // cols) * ch
        img.paste(glyph(mem, src, scale), (x, y))
        d.text((x, y + 8 * scale + 4), '$%02X' % code, fill=(200, 200, 200))
    save(img, 'charset.png')


def oric_font(mem):
    """Put a 6-pixel ASCII font at CHARSET $20-$7F, as the Oric ROM would have, from the C64 character ROM."""
    rom = open(CHARGEN, 'rb').read()
    for code in range(0x20, 0x80):
        if 0x61 <= code <= 0x7A:
            screen = code - 0x60                       # lower case: screen codes 1-26 in the lower/upper set
        elif code == 0x40:
            screen = 0
        elif 0x5B <= code <= 0x5F:
            screen = code - 0x40                       # [ \ ] ^ _ -> $1B-$1F
        else:
            screen = code                              # space, digits, punctuation, upper case: same codes
        for y in range(8):
            mem[CHARSET + code * 8 + y] = (rom[0x800 + screen * 8 + y] >> 1) & 0x3F


def render_screen(mem, scale=2):
    """The 40x28 text screen with serial attributes, 240x224 Oric pixels."""
    img = Image.new('RGB', (240, 224))
    px = img.load()
    for r in range(ROWS):
        ink, paper, dbl = 7, 0, False
        for c in range(COLS):
            b = mem[SCREEN + r * COLS + c]
            inv, code = b & 0x80, b & 0x7F
            attr = code < 0x20
            if attr:
                if code < 8:
                    ink = code
                elif code < 16:
                    dbl = bool(code & 2)
                elif code < 24:
                    paper = code & 7
            for y in range(8):
                if attr:
                    bits = 0
                else:
                    line = (y >> 1) + (4 if r & 1 else 0) if dbl else y
                    bits = mem[CHARSET + code * 8 + line]
                for x in range(6):
                    on = bits & (0x20 >> x)
                    col = ORIC[ink] if on else ORIC[paper]
                    if inv:
                        col = tuple(255 - v for v in col)
                    px[c * 6 + x, r * 8 + y] = col
    return img.resize((240 * scale, 224 * scale), Image.NEAREST)


def screens():
    for name, fn, font in (('menu', oric_screens.screen_menu, True), ('credits', oric_screens.screen_credits, True),
                           ('hiscores', oric_screens.screen_hiscores, True), ('scenery', oric_screens.screen_scenery,
                                                                             True),
                           ('game', oric_screens.screen_game, True), ('gameover', oric_screens.screen_gameover, True)):
        orig_load = oric_screens.load

        def load_with_font():
            mem = orig_load()
            oric_font(mem)
            return mem
        oric_screens.load = load_with_font
        try:
            mem = fn()
        finally:
            oric_screens.load = orig_load
        save(render_screen(mem), 'oric-%s.png' % name)


def main():
    if not os.path.exists(LBL):
        sys.exit('build/hopper.lbl not found: run make first')
    os.makedirs(OUT, exist_ok=True)
    lab = labels()
    mem = tape()
    frog_figures(mem, lab)
    charset_sheet(mem, lab)
    screens()


if __name__ == '__main__':
    main()
