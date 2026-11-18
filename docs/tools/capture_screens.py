#!/usr/bin/env python3
"""Capture the handbook's VICE screenshots of the C64 build.

  python3 docs/tools/capture_screens.py

Runs tools/c64_screens.py's captures (the scripted test build, plus the start-up picture from the normal build) into
docs/images/screens/. Build both first: `make c64-smoke` builds them (and takes the same captures into c64/build/).
Each capture boots a fresh headless x64sc and saves the screen after a fixed number of cycles, so they repeat exactly.
"""
import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
import c64_screens  # noqa: E402

OUT = os.path.join(ROOT, 'docs', 'images', 'screens')


def main():
    for prg in (c64_screens.PRG, c64_screens.MAIN_PRG):
        if not os.path.exists(prg):
            sys.exit('%s not found: run make c64-smoke' % os.path.relpath(prg, ROOT))
    os.makedirs(OUT, exist_ok=True)
    for name, (frame, _) in c64_screens.CAPTURES.items():
        c64_screens.capture(name, frame, OUT)


if __name__ == '__main__':
    main()
