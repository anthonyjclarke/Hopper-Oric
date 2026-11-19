#!/usr/bin/env python3
"""The Oric-style font of the C64 Enhanced version (V7, docs/enhanced_graphics.md).

  python3 tools/oric_style_font.py            write c64/src/oricfont.inc (the W6 layout, as built)

Drawn for this project in the manner of the Oric's text: a 5 x 7 design with single-pixel strokes in a 6-pixel cell
(the left column is the gap), lower case with descenders in row 7. It is not a copy of the Oric ROM font, which is not
on the tape. Each glyph below is 8 rows of 5 columns, '#' set.

Two ways to put the 6-pixel cell into the C64's 8 pixels (W6 chosen 18-11-2026; NARROW kept for the figures):

  W6      the two middle pixels doubled, as the port widens the game's own glyphs (`W6` in c64/src/hopper.s)
  NARROW  the 6 pixels as drawn, with a blank column each side

Standard library only. docs/tools/render_enhanced.py imports this for the figures.
"""
import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
INC = os.path.join(ROOT, 'c64', 'src', 'oricfont.inc')

# ASCII $20-$7F in order, 8 rows each. Blank rows may be left out at the bottom.
ART = r"""
20 space
.....
21 !
..#..
..#..
..#..
..#..
..#..
.....
..#..
22 "
.#.#.
.#.#.
.#.#.
23 #
.#.#.
.#.#.
#####
.#.#.
#####
.#.#.
.#.#.
24 $
..#..
.####
#.#..
.###.
..#.#
####.
..#..
25 %
##...
##..#
...#.
..#..
.#...
#..##
...##
26 &
.#...
#.#..
#.#..
.#...
#.#.#
#..#.
.##.#
27 '
..#..
..#..
.#...
28 (
...#.
..#..
.#...
.#...
.#...
..#..
...#.
29 )
.#...
..#..
...#.
...#.
...#.
..#..
.#...
2A *
.....
..#..
#.#.#
.###.
#.#.#
..#..
2B +
.....
..#..
..#..
#####
..#..
..#..
2C ,
.....
.....
.....
.....
.....
..#..
..#..
.#...
2D -
.....
.....
.....
#####
2E .
.....
.....
.....
.....
.....
.....
..#..
2F /
.....
....#
...#.
..#..
.#...
#....
30 0
.###.
#...#
#..##
#.#.#
##..#
#...#
.###.
31 1
..#..
.##..
..#..
..#..
..#..
..#..
.###.
32 2
.###.
#...#
....#
..##.
.#...
#....
#####
33 3
#####
....#
...#.
..##.
....#
#...#
.###.
34 4
...#.
..##.
.#.#.
#..#.
#####
...#.
...#.
35 5
#####
#....
####.
....#
....#
#...#
.###.
36 6
..##.
.#...
#....
####.
#...#
#...#
.###.
37 7
#####
....#
...#.
..#..
.#...
.#...
.#...
38 8
.###.
#...#
#...#
.###.
#...#
#...#
.###.
39 9
.###.
#...#
#...#
.####
....#
...#.
.##..
3A :
.....
.....
..#..
.....
.....
..#..
3B ;
.....
.....
..#..
.....
.....
..#..
..#..
.#...
3C <
...#.
..#..
.#...
#....
.#...
..#..
...#.
3D =
.....
.....
#####
.....
#####
3E >
.#...
..#..
...#.
....#
...#.
..#..
.#...
3F ?
.###.
#...#
....#
...#.
..#..
.....
..#..
40 @
.###.
#...#
#.###
#.#.#
#.###
#....
.###.
41 A
..#..
.#.#.
#...#
#...#
#####
#...#
#...#
42 B
####.
#...#
#...#
####.
#...#
#...#
####.
43 C
.###.
#...#
#....
#....
#....
#...#
.###.
44 D
####.
#...#
#...#
#...#
#...#
#...#
####.
45 E
#####
#....
#....
####.
#....
#....
#####
46 F
#####
#....
#....
####.
#....
#....
#....
47 G
.####
#....
#....
#..##
#...#
#...#
.####
48 H
#...#
#...#
#...#
#####
#...#
#...#
#...#
49 I
.###.
..#..
..#..
..#..
..#..
..#..
.###.
4A J
..###
...#.
...#.
...#.
...#.
#..#.
.##..
4B K
#...#
#..#.
#.#..
##...
#.#..
#..#.
#...#
4C L
#....
#....
#....
#....
#....
#....
#####
4D M
#...#
##.##
#.#.#
#.#.#
#...#
#...#
#...#
4E N
#...#
#...#
##..#
#.#.#
#..##
#...#
#...#
4F O
.###.
#...#
#...#
#...#
#...#
#...#
.###.
50 P
####.
#...#
#...#
####.
#....
#....
#....
51 Q
.###.
#...#
#...#
#...#
#.#.#
#..#.
.##.#
52 R
####.
#...#
#...#
####.
#.#..
#..#.
#...#
53 S
.###.
#...#
#....
.###.
....#
#...#
.###.
54 T
#####
..#..
..#..
..#..
..#..
..#..
..#..
55 U
#...#
#...#
#...#
#...#
#...#
#...#
.###.
56 V
#...#
#...#
#...#
#...#
#...#
.#.#.
..#..
57 W
#...#
#...#
#...#
#.#.#
#.#.#
#.#.#
.#.#.
58 X
#...#
#...#
.#.#.
..#..
.#.#.
#...#
#...#
59 Y
#...#
#...#
.#.#.
..#..
..#..
..#..
..#..
5A Z
#####
....#
...#.
..#..
.#...
#....
#####
5B [
.###.
.#...
.#...
.#...
.#...
.#...
.###.
5C \
.....
#....
.#...
..#..
...#.
....#
5D ]
.###.
...#.
...#.
...#.
...#.
...#.
.###.
5E ^
..#..
.#.#.
#...#
5F _
.....
.....
.....
.....
.....
.....
.....
#####
60 `
.#...
..#..
...#.
61 a
.....
.....
.###.
....#
.####
#...#
.####
62 b
#....
#....
####.
#...#
#...#
#...#
####.
63 c
.....
.....
.####
#....
#....
#....
.####
64 d
....#
....#
.####
#...#
#...#
#...#
.####
65 e
.....
.....
.###.
#...#
#####
#....
.###.
66 f
..##.
.#..#
.#...
###..
.#...
.#...
.#...
67 g
.....
.....
.####
#...#
#...#
.####
....#
.###.
68 h
#....
#....
####.
#...#
#...#
#...#
#...#
69 i
..#..
.....
.##..
..#..
..#..
..#..
.###.
6A j
...#.
.....
..##.
...#.
...#.
...#.
#..#.
.##..
6B k
#....
#....
#..#.
#.#..
##...
#.#..
#..#.
6C l
.##..
..#..
..#..
..#..
..#..
..#..
.###.
6D m
.....
.....
##.#.
#.#.#
#.#.#
#.#.#
#...#
6E n
.....
.....
####.
#...#
#...#
#...#
#...#
6F o
.....
.....
.###.
#...#
#...#
#...#
.###.
70 p
.....
.....
####.
#...#
#...#
####.
#....
#....
71 q
.....
.....
.####
#...#
#...#
.####
....#
....#
72 r
.....
.....
#.##.
##..#
#....
#....
#....
73 s
.....
.....
.####
#....
.###.
....#
####.
74 t
.#...
.#...
###..
.#...
.#...
.#..#
..##.
75 u
.....
.....
#...#
#...#
#...#
#..##
.##.#
76 v
.....
.....
#...#
#...#
#...#
.#.#.
..#..
77 w
.....
.....
#...#
#...#
#.#.#
#.#.#
.#.#.
78 x
.....
.....
#...#
.#.#.
..#..
.#.#.
#...#
79 y
.....
.....
#...#
#...#
#...#
.####
....#
.###.
7A z
.....
.....
#####
...#.
..#..
.#...
#####
7B {
...##
..#..
..#..
.#...
..#..
..#..
...##
7C |
..#..
..#..
..#..
..#..
..#..
..#..
..#..
..#..
7D }
##...
..#..
..#..
...#.
..#..
..#..
##...
7E ~
.....
.....
.#...
#.#.#
...#.
7F DEL
#####
#####
#####
#####
#####
#####
#####
#####
"""


def glyphs():
    """{code: [8 ints, 5 bits each, bit 4 = left]}."""
    out, code, rows = {}, None, []
    for line in ART.strip().splitlines():
        if line[:1] in '.#':
            rows.append(int(line.replace('.', '0').replace('#', '1'), 2))
            continue
        if code is not None:
            out[code] = (rows + [0] * 8)[:8]
        code, rows = int(line.split()[0], 16), []
    out[code] = (rows + [0] * 8)[:8]
    assert sorted(out) == list(range(0x20, 0x80)), 'one glyph per code $20-$7F'
    for c, g in out.items():
        assert all(r < 32 for r in g), 'glyph $%02X wider than 5 pixels' % c
    return out


def w6(row5):
    """The 6-pixel cell (gap + 5) widened as the port widens the game's glyphs: middle two pixels doubled."""
    b = row5                                  # bits 4..0 = pixels 1..5 of the cell; pixel 0 is the gap (bit 5)
    bits = [(b >> i) & 1 for i in (5, 4, 3, 3, 2, 2, 1, 0)]
    return sum(v << (7 - i) for i, v in enumerate(bits))


def narrow(row5):
    """The 6-pixel cell as drawn, a blank column each side."""
    return row5 << 1


LAYOUTS = {'W6': w6, 'NARROW': narrow}
BUILD_LAYOUT = 'W6'


def c64_bytes(layout):
    """{code: 8 bytes} for the C64's 8-pixel cells; DEL stays the port's solid block."""
    f = LAYOUTS[layout]
    out = {c: [f(r) for r in g] for c, g in glyphs().items()}
    out[0x7F] = [0xFF] * 8
    return out


def main():
    lines = ['; c64/src/oricfont.inc - generated by tools/oric_style_font.py: do not edit.',
             '; The Oric-style font (V7), %s layout: ASCII $20-$7F, 8 bytes each.' % BUILD_LAYOUT, '']
    for layout in (BUILD_LAYOUT,):
        data = c64_bytes(layout)
        lines.append('OricFont%s:' % layout.title())
        for c in range(0x20, 0x80):
            lines.append('        .byte   ' + ','.join('$%02X' % b for b in data[c]) + '  ; $%02X %s' % (c, chr(c) if c < 0x7F else 'DEL'))
        lines.append('')
    with open(INC, 'w') as f:
        f.write('\n'.join(lines))
    print(os.path.relpath(INC, ROOT))


if __name__ == '__main__':
    main()
