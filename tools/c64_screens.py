#!/usr/bin/env python3
"""Capture VICE screenshots of the C64 port at fixed points of its test script.

  python3 tools/c64_screens.py [--out DIR] [--only NAME]

Each capture boots c64/build/test/hopper.prg (or, for 'intro', the normal c64/build/hopper.prg) (the AUTOTEST build: c64/src/autotest.s presses the keys) in a fresh,
headless x64sc (warp, no sound, random autostart delay off) and saves the screen after a fixed number of CPU cycles,
so the captures repeat exactly. Build the test .prg first (make c64-smoke does both). Standard library only.
"""
import argparse
import os
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
PRG = os.path.join(ROOT, 'c64', 'build', 'test', 'hopper.prg')
MAIN_PRG = os.path.join(ROOT, 'c64', 'build', 'hopper.prg')       # for 'intro'
BOOT = 3_100_000                        # cycles before the script's clock starts (autostart, unpacking)
FRAME = 19_656                          # PAL frame

# name: (frame of the test script, what it shows); see Script in c64/src/autotest.s
CAPTURES = {
    'intro': (100, 'The start-up picture (normal build: the test build skips it)'),
    'sound-menu': (120, 'The sound menu, before any key'),
    'controls': (190, 'Sound chosen; the controls menu'),
    'redefine': (270, 'Redefining: left N, right M, P refused, up Q'),
    'credits': (825, 'The credits, the frog hopping round the screen, keys N M Q A'),
    'credits-done': (1400, 'The credits finished, waiting'),
    'hiscores': (2400, 'The hi-score table, title scrolling; the version line on Enhanced'),
    'version': (2500, 'F1 pressed on the home screen: the version line on Classic'),
    'sheet-start': (2650, 'A new game: the READY / SHEET / SCORE signs'),
    'play': (2945, 'Playing: lanes moving'),
    'hops': (3160, 'Hopping up the road: the frog is hit, the death flash'),
    'later': (3580, 'A little later'),
}


def capture(name, frame, out):
    target = os.path.join(out, name + '.png')
    if os.path.exists(target):
        os.remove(target)
    cycles = BOOT + frame * FRAME
    subprocess.run(['x64sc', '-default', '-console', '-warp', '-sounddev', 'dummy', '+autostart-delay-random',
                    '-limitcycles', str(cycles), '-exitscreenshot', target,
                    '-autostartprgmode', '1', '-autostart', MAIN_PRG if name == 'intro' else PRG],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    if not os.path.exists(target):
        sys.exit('capture failed: ' + name)
    print('%-13s %s' % (name, os.path.relpath(target, ROOT)))


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--out', default=os.path.join(ROOT, 'c64', 'build'))
    parser.add_argument('--only', choices=sorted(CAPTURES))
    args = parser.parse_args()
    if not os.path.exists(PRG):
        sys.exit('%s not found: run make c64-smoke' % os.path.relpath(PRG, ROOT))
    os.makedirs(args.out, exist_ok=True)
    for name, (frame, _) in CAPTURES.items():
        if args.only == name or (args.only is None and name != 'intro'):
            capture(name, frame, args.out)


if __name__ == '__main__':
    main()
