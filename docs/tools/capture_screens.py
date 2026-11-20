#!/usr/bin/env python3
"""Capture the handbook's VICE screenshots of the C64 build.

  python3 docs/tools/capture_screens.py

Runs tools/c64_screens.py's captures (the scripted test build, plus the start-up picture from the normal build) into
docs/images/screens/. Build both first: `make c64-smoke` builds them (and takes the same captures into c64/build/).
Each capture boots a fresh headless x64sc and saves the screen after a fixed number of cycles, so they repeat exactly.
It also records `enh-smooth.gif`: the river in Enhanced over consecutive frames (V4, smooth-scrolling lanes), one
capture per frame (needs Pillow).
"""
import os
import sys
import tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
import c64_screens  # noqa: E402

OUT = os.path.join(ROOT, 'docs', 'images', 'screens')

SMOOTH_FRAMES = range(3072, 3094)               # Enhanced play, once the screen is drawn
SMOOTH_CROP = (32, 59, 352, 147)                # the river: C64 rows 3-13 inside VICE's border


def smooth_gif():
    from PIL import Image
    frames = []
    with tempfile.TemporaryDirectory() as tmp:
        for f in SMOOTH_FRAMES:
            c64_screens.capture('enh-smooth', f, tmp)
            im = Image.open(os.path.join(tmp, 'enh-smooth.png')).convert('RGB').crop(SMOOTH_CROP)
            frames.append(im.resize((im.width * 2, im.height * 2), Image.NEAREST))
    target = os.path.join(OUT, 'enh-smooth.gif')
    frames[0].save(target, save_all=True, append_images=frames[1:], duration=20, loop=0, optimize=True)
    print('enh-smooth    ' + os.path.relpath(target, ROOT))


def main():
    for prg in (c64_screens.PRG, c64_screens.ENH_PRG, c64_screens.MAIN_PRG):
        if not os.path.exists(prg):
            sys.exit('%s not found: run make c64-smoke' % os.path.relpath(prg, ROOT))
    os.makedirs(OUT, exist_ok=True)
    for name, (frame, _) in c64_screens.CAPTURES.items():
        c64_screens.capture(name, frame, OUT)
    smooth_gif()


if __name__ == '__main__':
    main()
