#!/usr/bin/env python3
"""List every byte of the C64 game image that differs from the Oric program.

  python3 tools/c64_diff.py

The C64 port keeps the game at its Oric addresses ($0500-$30D4) and changes it only where the hardware differs
(docs/porting.md). This compares the GAME image inside c64/build/hopper.prg with original/HOPPER.TAP and prints
each run of changed bytes with the routine it is in, so a stray change shows up. Standard library only.
"""
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
PRG = os.path.join(ROOT, 'c64', 'build', 'hopper.prg')
TAP = os.path.join(ROOT, 'original', 'HOPPER.TAP')
SRC = os.path.join(ROOT, 'src', 'hopper.s')
GAME_LOAD, GAME_RUN = 0x0810, 0x0500


def oric_payload():
    data = open(TAP, 'rb').read()
    start = data[10] << 8 | data[11]
    end = data[8] << 8 | data[9]
    return start, data[14:14 + end - start + 1]


def labels():
    """Routine and data labels with their Oric addresses, from src/hopper.s."""
    out, pending = [], []
    for line in open(SRC):
        m = re.match(r'^([A-Za-z_]\w*):', line)
        if m and not re.match(r'^L[0-9A-F]{4}$', m.group(1)):
            pending.append(m.group(1))
            continue
        a = re.search(r';\s([0-9A-F]{4})\b', line)
        if a and pending:
            for name in pending:
                out.append((int(a.group(1), 16), name))
            pending = []
    return sorted(out)


def where(addr, table):
    name = '?'
    for a, n in table:
        if a > addr:
            break
        name = n if a == addr else '%s+%d' % (n, addr - a)
    return name


def main():
    if not os.path.exists(PRG):
        sys.exit('c64/build/hopper.prg not found: run make c64 first')
    start, oric = oric_payload()
    prg = open(PRG, 'rb').read()
    load = prg[0] | prg[1] << 8
    off = GAME_LOAD - load + 2
    c64 = prg[off:off + len(oric)]
    table = labels()
    runs, i = [], 0
    while i < len(oric):
        if oric[i] != c64[i]:
            j = i
            while j < len(oric) and oric[j] != c64[j]:
                j += 1
            runs.append((i, j))
            i = j
        else:
            i += 1
    total = sum(j - i for i, j in runs)
    for i, j in runs:
        a = start + i
        print('%04X-%04X %3d  %-26s %s -> %s' % (a, start + j - 1, j - i, where(a, table),
                                              oric[i:j][:8].hex(' ').upper(), c64[i:j][:8].hex(' ').upper()))
    print('%d bytes differ in %d runs, of %d' % (total, len(runs), len(oric)))


if __name__ == '__main__':
    main()
