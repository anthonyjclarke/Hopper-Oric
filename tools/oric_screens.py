#!/usr/bin/env python3
"""Run HOPPER's own Oric drawing routines on a 6502 core and print the screens they draw.

  python3 tools/oric_screens.py [screen ...]

Used to see which of the Oric's 28 text rows each screen uses, so the C64 port knows which three rows it can hide
on its 25-row screen (see docs/porting.md). Each screen is drawn by calling the game's routines from
original/HOPPER.TAP, with the delays and key waits stubbed out. Attribute cells print as '.', graphics characters
(codes $5B-$7F and the redefined $21-$2E, $3A-$3D in game screens) as '#'. Standard library only.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from cpu6502 import CPU  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
SCREEN, ROWS, COLS = 0xBB80, 28, 40
ROM_KEY = 0x02DF
SENTINEL = 0xFFF0

# Routine addresses (src/hopper.s)
A = dict(ColdStart=0x0500, ClearScreen=0x09D8, InitGame=0x0A00, DelayX=0x0DF2, Delay48=0x0DF0,
         FrameDelay=0x0DB8, SoundMenu=0x2280, MarkSoundChoice=0x3085, ControlsMenu=0x2F30,
         CreditsIntro=0x2778, CheckMenuKeys=0x299F, CreditsDelay=0x2811, DrawTitleBar=0x1AA0,
         DrawHiScoreTable=0x1C00, DrawMenuPrompt=0x1D00, TitleScroll=0x2900, ShowEnterName=0x1D30,
         DrawScenery=0x1F00, PlaySheetTune=0x2B82, GameOver=0x1AD0, CheckHiScore=0x1B00,
         RestoreCharset=0x0948, InitTimers=0x209F, AYWrite=0x1FAD, ResetSheet=0x1200)


def load():
    data = open(os.path.join(ROOT, 'original', 'HOPPER.TAP'), 'rb').read()
    start = data[10] << 8 | data[11]
    end = data[8] << 8 | data[9]
    payload = data[14:14 + end - start + 1]
    mem = bytearray(65536)
    mem[start:start + len(payload)] = payload
    for i in range(1, 256):                       # ColdStart's hi-score copy
        mem[0xBA00 - 1 + i] = mem[0x22FF + i]
    return mem


def call(mem, addr, stubs=(), key=None, limit=20_000_000):
    for s in stubs:
        mem[A[s]] = 0x60                          # RTS
    if key is not None:
        mem[ROM_KEY] = ord(key) | 0x80
    cpu = CPU(mem)
    cpu.sp = 0xFD
    cpu.push((SENTINEL - 1) >> 8)
    cpu.push((SENTINEL - 1) & 0xFF)
    cpu.pc = addr
    while cpu.pc != SENTINEL:
        cpu.step()
        if cpu.cycles > limit:
            raise RuntimeError('routine at $%04X did not return' % addr)


def show(mem, title):
    print('== %s' % title)
    print('    ' + ''.join(str(c % 10) for c in range(COLS)))
    for r in range(ROWS):
        row = mem[SCREEN + r * COLS:SCREEN + (r + 1) * COLS]
        text = ''.join('.' if (b & 0x7F) < 0x20 else ('#' if (b & 0x7F) >= 0x7B else chr(b & 0x7F)) for b in row)
        used = any((b & 0x7F) > 0x20 for b in row)
        print('%2d %s %s' % (r, '*' if used else ' ', text))
    print()


def screen_menu():
    mem = load()
    call(mem, A['ClearScreen'])
    call(mem, A['SoundMenu'], key='3')
    call(mem, A['MarkSoundChoice'])
    call(mem, A['ControlsMenu'], key='1')
    return mem


def screen_credits():
    mem = load()
    call(mem, A['ClearScreen'])
    call(mem, A['CreditsIntro'], stubs=('CheckMenuKeys', 'CreditsDelay', 'DelayX', 'AYWrite'))
    return mem


def screen_hiscores():
    mem = load()
    call(mem, A['ClearScreen'])
    call(mem, A['DrawTitleBar'])
    call(mem, A['DrawHiScoreTable'])
    call(mem, A['DrawMenuPrompt'], stubs=('TitleScroll',))
    return mem


def screen_entername():
    mem = load()
    call(mem, A['ClearScreen'])
    call(mem, A['ShowEnterName'])
    call(mem, A['DrawHiScoreTable'])
    return mem


def screen_scenery():
    mem = load()
    call(mem, A['ClearScreen'])
    call(mem, A['DrawScenery'], stubs=('PlaySheetTune', 'AYWrite'))
    return mem


def screen_game():
    mem = load()
    call(mem, A['InitGame'], stubs=('PlaySheetTune', 'AYWrite'))
    return mem


def screen_gameover():
    mem = screen_game()
    call(mem, A['GameOver'], stubs=('DelayX', 'AYWrite', 'RestoreCharset', 'InitTimers', 'CheckHiScore'))
    return mem


SCREENS = dict(menu=screen_menu, credits=screen_credits, hiscores=screen_hiscores, entername=screen_entername,
               scenery=screen_scenery, game=screen_game, gameover=screen_gameover)


def main():
    names = sys.argv[1:] or list(SCREENS)
    for n in names:
        show(SCREENS[n](), n)


if __name__ == '__main__':
    main()
