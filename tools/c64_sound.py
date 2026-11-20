#!/usr/bin/env python3
"""Record the C64 port's tunes and effects for the docs (make c64-sound).

  python3 tools/c64_sound.py [--keep DIR]

Runs the sound build (c64/build/test-sound/hopper.prg, AUTOTEST_SOUND in c64/src/autotest.s): the test script's menus,
the credits, a game started in Classic with loud sound, one hop up and back, then the frog sits on the verge while
PickTune, patched by the build, plays the four in-game tunes in order until its time runs out.

1. A headless x64sc in warp finds when each sound starts: the monitor stops at CreditsEnd, PlaySheetTune and its rts,
   the first low-time beep and the death that follows it (DeathSequence and its rts), and reads the frame of every PickTune call
   that the build logs in soundLog.
2. A second x64sc records the same run to a WAV file in real time (about three minutes; VICE writes sound only with
   its window open, so it starts minimised).
3. The WAV is cut at those times and each clip converted to AAC with macOS afconvert, into docs/sound/.

Deterministic: the same build gives the same clips. Standard library only (afconvert is part of macOS).
"""
import argparse
import array
import math
import os
import re
import shutil
import subprocess
import sys
import tempfile
import wave

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
PRG = os.path.join(ROOT, 'c64', 'build', 'test-sound', 'hopper.prg')
LBL = os.path.join(ROOT, 'c64', 'build', 'test-sound', 'hopper.lbl')
OUT = os.path.join(ROOT, 'docs', 'sound')
CLOCK = 985_248                         # PAL CPU cycles a second
BOOT = 3_100_000                        # as tools/c64_screens.py: cycles before the script's frame 0
FRAME = 19_656

# The game's own addresses (every game byte stays at its Oric address)
CREDITS_END = 0x2AE8
SHEET_TUNE, SHEET_TUNE_RTS = 0x2B82, 0x2BED
DEATH, DEATH_RTS = 0x2170, 0x2198
LOW_TIME_BEEP = 0x1D5E
HOP_FRAME = 3030                        # the script's one hop (Script in autotest.s)


def vice(args, timeout):
    subprocess.run(['x64sc', '-default', '+autostart-delay-random', '-autostartprgmode', '1'] + args +
                   ['-autostart', PRG], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=timeout,
                   check=False)


def find_events(tmp):
    """Cycle counts of the events, in the order they happen, and the frames of the PickTune calls."""
    lbl = open(LBL).read()
    log_at = int(re.search(r'al ([0-9A-F]+) \.soundLog', lbl).group(1), 16)
    stops = [CREDITS_END, SHEET_TUNE, SHEET_TUNE_RTS, LOW_TIME_BEEP, DEATH, DEATH_RTS]
    cmds = os.path.join(tmp, 'events.txt')
    log = os.path.join(tmp, 'events.log')
    with open(cmds, 'w') as f:
        f.writelines('un %04x\n' % a for a in stops)
        f.write('m %04x %04x\nquit\n' % (log_at, log_at + 127))
    vice(['-console', '-warp', '-sounddev', 'dummy', '-moncommands', cmds, '-monlog', '-monlogname', log], 600)
    text = open(log, encoding='latin-1').read()
    cycles = [int(c) for c in re.findall(r'^\.C:[0-9a-f]{4} .* (\d+)$', text, re.M)][1:]   # [0]: the reset
    if len(cycles) != len(stops):
        sys.exit('event pass: %d of %d stops' % (len(cycles), len(stops)))
    dump = bytes(int(b, 16) for line in re.findall(r'^>C:[0-9a-f]{4}  (.*?)   ', text, re.M)
                 for b in line.split())
    calls = [dump[i] | dump[i + 1] << 8 for i in range(0, 128, 2)]
    return dict(zip(['jingle', 'sheet', 'sheet_end', 'low_time', 'death', 'death_end'], cycles)), calls


def record(tmp, end_cycles):
    path = os.path.join(tmp, 'run.wav')
    print('recording %.0f s in real time...' % (end_cycles / CLOCK))
    vice(['-minimized', '+autostart-warp', '-sound', '-sounddev', 'wav', '-soundarg', path,
          '-limitcycles', str(end_cycles)], end_cycles / CLOCK * 2 + 120)
    return path


def seconds(frame):
    return (BOOT + frame * FRAME) / CLOCK


QUIET = 60                              # RMS of a 16-bit sample window that counts as silence


def quiet_at(samples, rate, start, limit):
    """The first time from start (seconds) at which 50 ms are silent, looking up to limit seconds on; else start."""
    n = rate // 20
    i = int(start * rate)
    while i < int((start + limit) * rate) and i + n <= len(samples):
        w = samples[i:i + n]
        if math.sqrt(sum(x * x for x in w) / n) < QUIET:
            return i / rate
        i += n // 2
    return start


def sound_start(samples, rate, a, b):
    """a, moved on to 0.1 s before the first sound between a and b."""
    n = rate // 20
    for i in range(int(a * rate), min(int(b * rate), len(samples)) - n, n // 2):
        w = samples[i:i + n]
        if math.sqrt(sum(x * x for x in w) / n) >= QUIET:
            return max(a, i / rate - 0.1)
    return a


def sound_end(samples, rate, a, b):
    """b, brought back to 0.25 s after the last sound between a and b."""
    n = rate // 20
    last = a
    for i in range(int(a * rate), min(int(b * rate), len(samples)) - n, n):
        w = samples[i:i + n]
        if math.sqrt(sum(x * x for x in w) / n) >= QUIET:
            last = (i + n) / rate
    return min(b, last + 0.25)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--keep', help='keep the full recording and the monitor logs in this directory')
    args = parser.parse_args()
    for f in (PRG, LBL):
        if not os.path.exists(f):
            sys.exit('%s not found: make c64/build/test-sound/hopper.prg' % os.path.relpath(f, ROOT))
    tmp = args.keep or tempfile.mkdtemp(prefix='c64_sound_')
    os.makedirs(tmp, exist_ok=True)
    try:
        ev, calls = find_events(tmp)
        t = {k: v / CLOCK for k, v in ev.items()}
        # calls[k] starts tune k mod 4 (the build plays them in turn), at the start of the game, at the end of the
        # tune before or after a death. The last of each that played to the next call before the low-time beeps
        # (the frog sitting on the verge, no death in it) is the one recorded.
        tunes = {}
        for k in range(len(calls) - 2, -1, -1):
            if calls[k + 1] > calls[k] and seconds(calls[k + 1]) < t['low_time'] and k % 4 not in tunes:
                tunes[k % 4] = (seconds(calls[k]), seconds(calls[k + 1]))
        if len(tunes) != 4:
            sys.exit('only tunes %s played to their end before the low-time beeps' % sorted(tunes))
        end = ev['death'] + 6 * CLOCK
        wav = record(tmp, end)
        with wave.open(wav) as w:
            rate, width, chans, frames = w.getframerate(), w.getsampwidth(), w.getnchannels(), w.getnframes()
            data = w.readframes(frames)
        if width != 2 or chans != 1:
            sys.exit('expected 16-bit mono from VICE, got %d bytes x %d channels' % (width, chans))
        samples = array.array('h', data)
        # The recording ends at the cycle limit; any time it lacks is missing at the start (autostart)
        offset = end / CLOCK - frames / rate
        sec = {k: v - offset for k, v in t.items()}
        # A tune's last note holds until the next tune's first write, so each tune runs from the gap after its
        # PickTune to the gap after the next one
        clips = []
        for n, (a, b) in sorted(tunes.items()):
            a, b = quiet_at(samples, rate, a - offset, 1.5), quiet_at(samples, rate, b - offset, 1.5)
            clips.append(('tune-%d' % n, sound_start(samples, rate, a, b), b))
        clips += [
            ('tune-sheet', sec['sheet'], sec['sheet_end'] + 0.3),
            ('effect-jingle', sec['jingle'], sound_end(samples, rate, sec['jingle'], sec['jingle'] + 4)),
            ('effect-hop', seconds(HOP_FRAME) - offset, seconds(HOP_FRAME) - offset + 0.6),
            ('effect-death', sec['death'], sec['death_end'] + 0.3),
            ('effect-low-time', sec['low_time'], sec['low_time'] + 4.0),
        ]
        os.makedirs(OUT, exist_ok=True)
        for name, a, b in clips:
            b = max(b, a + 1.05)                        # a player shows 0:00 for anything shorter than a second
            i, j = (max(0, int(x * rate)) * width * chans for x in (a, b))
            part = os.path.join(tmp, name + '.wav')
            with wave.open(part, 'wb') as w:
                w.setnchannels(chans)
                w.setsampwidth(width)
                w.setframerate(rate)
                w.writeframes(data[i:j])
            dst = os.path.join(OUT, name + '.m4a')
            subprocess.run(['afconvert', '-f', 'm4af', '-d', 'aac', '-b', '96000', part, dst], check=True)
            print('%-16s %6.2f s  %s' % (name, b - a, os.path.relpath(dst, ROOT)))
    finally:
        if not args.keep:
            shutil.rmtree(tmp, ignore_errors=True)


if __name__ == '__main__':
    main()
