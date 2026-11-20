#!/usr/bin/env python3
"""Check the C64 port for one-frame display glitches (make c64-flicker).

  python3 tools/c64_glitch.py [--keep DIR]

Takes consecutive VICE captures of the scripted test builds (tools/c64_screens.py, one fresh headless x64sc per frame)
and fails if any of three checks finds a glitch:

  menu   The sound menu, frames 100-145 of the script. Nothing on it moves but the blinking PRESS, so a frame that
         differs from both neighbours while they match each other is a glitch: a row's first pixel line drawn with the
         row above's character set when the row interrupt's stores land late (double-height text shows it).
  title  The hi-score table, frames 2510-2550. The double-height title scrolls: its top and bottom rows (0 and 1) must
         move in the same frame, or the title tears.
  play   Enhanced play, frames 3066-3100, and 3400-3600 with the driven frog on the road (its sprite DMA delays
         the row interrupt). Each row of a frame should be the previous frame's row shifted sideways (the
         lanes scroll); pixels the shift doesn't explain, all on one pixel line of the row and gone again in the next
         frame, are a late row interrupt (old colours or character set on that line). Frames where most rows change (a screen being drawn) are
         skipped, as are the frames before both road markings are drawn. From then on the two markings must be
         one whole grey line each, with no grey running on into the line below (the paper put back late).

Needs the test builds (make c64-smoke builds them) and Pillow. Deterministic: the same build gives the same result.
"""
import argparse
import contextlib
import io
import multiprocessing
import os
import shutil
import sys
import tempfile

sys.path.insert(0, os.path.dirname(__file__))
import c64_screens  # noqa: E402
from PIL import Image, ImageChops  # noqa: E402

X0, Y0 = 32, 35                         # the text window inside VICE's 384x272 capture
ROWS = 25
MARKS = (18, 20)                        # the rows that start with a road marking (MarkRow)
GREY = 0x94                             # VICE's medium grey (the marking colour), each of R, G and B

CHECKS = {
    'menu': ('flk-menu', range(100, 146)),
    'title': ('flk-title', range(2510, 2551)),
    'play': ('enh-flk', list(range(3066, 3101)) + list(range(3400, 3601))),
}


def capture(job):
    name, f, tmp = job
    d = os.path.join(tmp, '%s-%d' % (name, f))          # one directory a run: they go in parallel
    os.makedirs(d, exist_ok=True)
    with contextlib.redirect_stdout(io.StringIO()):
        c64_screens.capture(name, f, d)
    p = d + '.png'
    os.replace(os.path.join(d, name + '.png'), p)
    os.rmdir(d)
    return p


def frames(name, rng, tmp):
    """Capture each frame of rng as name (the name picks the test build, as in c64_screens): (frame, L, RGB)."""
    with multiprocessing.Pool() as pool:
        paths = pool.map(capture, [(name, f, tmp) for f in rng])
    out = []
    for f, p in zip(rng, paths):
        im = Image.open(p).convert('RGB')
        out.append((f, im.convert('L'), im))
    return out


def count(img):
    return sum(img.histogram()[1:])


def best_shift(a, b, r):
    """Row r: the sideways shift (-10..10) that best maps frame a onto frame b, its leftover pixels and the leftover
    on each of the row's 8 lines."""
    y = Y0 + r * 8
    bb = b.crop((X0 + 12, y, X0 + 308, y + 8))
    best = None
    for s in sorted(range(-10, 11), key=abs):      # ties go to the smallest shift (a still or uniform row: 0)
        d = count(ImageChops.difference(a.crop((X0 + 12 - s, y, X0 + 308 - s, y + 8)), bb))
        if best is None or d < best[1]:
            best = (s, d)
    s = best[0]
    diff = ImageChops.difference(a.crop((X0 + 12 - s, y, X0 + 308 - s, y + 8)), bb)
    return s, best[1], [count(diff.crop((0, k, 296, k + 1))) for k in range(8)]


def check_menu(fr):
    bad = []
    for k in range(1, len(fr) - 1):
        a = ImageChops.difference(fr[k - 1][1], fr[k][1]).getbbox()
        b = ImageChops.difference(fr[k][1], fr[k + 1][1]).getbbox()
        if a and b and not ImageChops.difference(fr[k - 1][1], fr[k + 1][1]).getbbox():
            bad.append('frame %d: one-frame change in %s' % (fr[k][0], a))
    return bad


def check_title(fr):
    bad = []
    for k in range(1, len(fr)):
        (s0, d0, _), (s1, d1, _) = (best_shift(fr[k - 1][1], fr[k][1], r) for r in (0, 1))
        if (s0 != 0) != (s1 != 0):
            bad.append('frame %d: title rows moved apart (top %+d, bottom %+d)' % (fr[k][0], s0, s1))
    return bad


def check_marks(f, im):
    """The road markings of one frame: a whole grey line, none of it running on into the next line."""
    bad = []
    px = im.load()
    for r in MARKS:
        y = Y0 + r * 8
        grey = sum(1 for x in range(X0, X0 + 320) if px[x, y] == (GREY, GREY, GREY))
        run = 0
        while run < 320 and px[X0 + run, y + 1] == (GREY, GREY, GREY):
            run += 1
        if grey < 280:
            bad.append('frame %d: row %d marking missing (%d grey pixels)' % (f, r, grey))
        if run > 8:                                     # a car's grey edge can sit at the margin
            bad.append('frame %d: row %d marking runs %d pixels into its second line' % (f, r, run))
    return bad


def check_play(fr):
    bad = []
    ready = False                                       # both markings drawn: the play screen is up
    for k in range(len(fr)):
        if k > 0 and fr[k][0] != fr[k - 1][0] + 1:
            ready = False                               # a new run of consecutive frames
        marks = check_marks(fr[k][0], fr[k][2])
        if not ready:
            ready = not any('missing' in m for m in marks)
            if ready:
                bad += marks                            # (no earlier play frame to compare with)
            continue                                    # else the screen is still being drawn
        bad += marks
        rows = [best_shift(fr[k - 1][1], fr[k][1], r) for r in range(ROWS)]
        if sum(1 for _, d, _ in rows if d > 30) >= 8:
            continue                                    # a screen being drawn, not a glitch
        for r, (s, d, lines) in enumerate(rows):
            top = max(range(8), key=lambda i: lines[i])
            rest = lines[:top] + lines[top + 1:]
            if lines[top] >= 16 and lines[top] >= 4 * max(rest) and transient(fr, k, r, top):
                bad.append('frame %d: row %d, line %d only (%d pixels)' % (fr[k][0], r, top, lines[top]))
    return bad


def transient(fr, k, r, line):
    """A late interrupt spoils one frame: the frame after it matches the one before (shifted). A change that stays
    (the turtles' dive, a glyph redrawn) is the game's own."""
    if k + 1 >= len(fr) or fr[k + 1][0] != fr[k][0] + 1:
        return True
    return best_shift(fr[k - 1][1], fr[k + 1][1], r)[2][line] < 16


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--keep', help='keep the captures in this directory')
    parser.add_argument('--only', choices=sorted(CHECKS))
    args = parser.parse_args()
    for prg in (c64_screens.PRG, c64_screens.ENH_PRG):
        if not os.path.exists(prg):
            sys.exit('%s not found: run make c64-smoke' % os.path.relpath(prg, c64_screens.ROOT))
    tmp = args.keep or tempfile.mkdtemp(prefix='c64_glitch_')
    os.makedirs(tmp, exist_ok=True)
    failed = False
    try:
        for check, (name, rng) in CHECKS.items():
            if args.only and args.only != check:
                continue
            fr = frames(name, rng, tmp)
            bad = {'menu': check_menu, 'title': check_title, 'play': check_play}[check](fr)
            print('%-6s %3d frames: %s' % (check, len(fr), 'ok' if not bad else '%d glitches' % len(bad)))
            for line in bad[:12]:
                print('         ' + line)
            failed |= bool(bad)
    finally:
        if not args.keep:
            shutil.rmtree(tmp, ignore_errors=True)
    sys.exit(1 if failed else 0)


if __name__ == '__main__':
    main()
