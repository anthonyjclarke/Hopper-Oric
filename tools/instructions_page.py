#!/usr/bin/env python3
"""The C64 Enhanced instructions page (layout C of docs/enhanced_graphics.md) as Oric screen bytes.

  python3 tools/instructions_page.py

Writes c64/src/instrpage.inc: the 28 Oric rows of 40 bytes, run-length packed as the picture is ($FE n v), for
EnhancedPage (c64/src/platform.s) to unpack into SCREEN, plus the cells where it puts the four key names. The page is
an ordinary Oric screen: ink attributes ($00-$07) before each colour, inverse characters (bit 7) for the keycaps, the
double-height attribute ($0A) for the title, so the port draws it as it draws the original credits. The frames use six
characters the page and the key names never use, which EnhancedPage redefines as line pieces while the page is up.
Rows 4, 8 and 9 are hidden on this screen (MapCredits) and stay blank. Standard library only.
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'c64', 'src', 'instrpage.inc')

BLACK, RED, GREEN, YELLOW, BLUE, MAGENTA, CYAN, WHITE = range(8)
DOUBLE = 0x0A                                   # text attribute: standard set, double height
BOX = {'┌': '{', '┐': '}', '└': '`', '┘': '#', '─': '~', '│': '|'}
GLYPHS = {                                      # the line pieces, 8 rows each (the lines are 2 pixels thick)
    '{': [0, 0, 0, 0x1F, 0x1F, 0x18, 0x18, 0x18],
    '}': [0, 0, 0, 0xF8, 0xF8, 0x18, 0x18, 0x18],
    '`': [0x18, 0x18, 0x18, 0x1F, 0x1F, 0, 0, 0],
    '#': [0x18, 0x18, 0x18, 0xF8, 0xF8, 0, 0, 0],
    '~': [0, 0, 0, 0xFF, 0xFF, 0, 0, 0],
    '|': [0x18] * 8,
}
KEY_ROWS = {'left': 12, 'right': 14, 'up': 16, 'down': 18}
KEY_COL = 11                                    # the middle of each keycap


def a(code):
    return [code]


def t(s):
    return [ord(BOX.get(ch, ch)) for ch in s]


def inv(s):
    return [c | 0x80 for c in t(s)]


def fit(parts, n):
    out = sum(parts, [])
    assert len(out) <= n, (len(out), n, out)
    return out + [0x20] * (n - len(out))


def row(*parts):
    r = fit(list(parts), 40)
    assert len(r) == 40
    return r


def title_box(inner, ink):
    """The title box's middle rows: cyan sides, cols 3-37 inside (35 cells)."""
    return row(a(CYAN), t('│'), a(ink), fit(inner, 35), a(CYAN), t('│'))


def panels(left, right, right_ink=WHITE):
    """A row of both panels: CONTROLS cols 3-16 (14 cells), HOW TO PLAY cols 22-37 (16 cells)."""
    return row(a(BLUE), t('│'), a(CYAN), fit(left, 14), a(BLUE), t('│'),
               a(GREEN), t('│'), a(right_ink), fit(right, 16), a(GREEN), t('│'))


def key_row(name):
    return [t(name.ljust(6)), a(WHITE), inv('   ')]


def points(label, value):
    return [t(label), a(WHITE), t(value.rjust(15 - len(label)))]


def page():
    rows = {r: row() for r in range(28)}
    rows[0] = row(a(CYAN), t('┌' + '─' * 37 + '┐'))
    rows[1] = title_box([t('PERSONAL SOFTWARE SERVICES PRESENTS')], RED)
    for r in (2, 3):
        rows[r] = row(a(CYAN), t('│'), a(DOUBLE), a(GREEN), fit([t(' ' * 11 + 'H O P P E R')], 34), a(CYAN), t('│'))
    rows[5] = title_box([t('  BY A.J.CLARKE   -   P.S.S. 1983')], MAGENTA)
    rows[6] = row(a(CYAN), t('└' + '─' * 37 + '┘'))
    rows[10] = row(a(BLUE), t('┌─'), a(WHITE), t('CONTROLS'), a(BLUE), t('─────┐'),
                   a(GREEN), t('┌─'), a(WHITE), t('HOW TO PLAY'), a(GREEN), t('────┐'))
    for r in range(11, 23):
        rows[r] = panels([], [])
    for k, r in KEY_ROWS.items():
        rows[r] = panels(key_row(k.upper()), [])
    how = {12: 'CROSS THE ROAD', 13: 'AND THE RIVER,', 14: 'GET FIVE FROGS', 15: 'HOME IN TIME.'}
    for r, s in how.items():
        left = key_row(next(k for k, kr in KEY_ROWS.items() if kr == r).upper()) if r in KEY_ROWS.values() else []
        rows[r] = panels(left, [t(s)])
    pts = {17: ('HOP', '10'), 18: ('HOME', '100'), 19: ('FLY', '800+'), 20: ('TIME LEFT', 'X10')}
    for r, (lab, val) in pts.items():
        left = key_row('DOWN') if r == 18 else []
        rows[r] = panels(left, points(lab, val), YELLOW)
    rows[20] = panels([t('P       PAUSE')], points('TIME LEFT', 'X10'), YELLOW)
    rows[21] = panels([t('RUN/STOP  QUIT')], [t(' ' * 7), a(GREEN), t(':;')])
    rows[22] = panels([t('JOYSTICK 2')], [t(' ' * 7), a(GREEN), t('<=')])
    rows[23] = row(a(BLUE), t('└' + '─' * 16 + '┘'), a(GREEN), t('└' + '─' * 18 + '┘'))
    rows[25] = row(t('  '), a(YELLOW), inv(' 1 '), a(WHITE), t('START'), a(CYAN), inv(' 3 '), a(WHITE), t('NEW KEYS'),
                   t(' '), inv(' F1 '), t(' CLASSIC'))
    rows[27] = row(a(BLUE), t('452 STONEY STANTON RD, COVENTRY CV6 5DG'))
    for r in (4, 8, 9):
        assert rows[r] == row(), r
    return rows


def rle(data):
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
    rows = page()
    data = bytes(sum((rows[r] for r in range(28)), []))
    packed = rle(data)
    lines = ['; Generated by tools/instructions_page.py: do not edit.', '',
             '; The Enhanced instructions page: 28 Oric rows x 40, packed ($FE n v = n copies of v, $FE 0 = end).']
    for k, r in KEY_ROWS.items():
        lines.append('PAGE_KEY_%s = %d%s; row %d, col %d' % (k.upper(), r * 40 + KEY_COL,
                                                           ' ' * (4 - len(str(r * 40 + KEY_COL))), r, KEY_COL))
    lines.append('PAGE_GLYPH_CODES = %d' % len(GLYPHS))
    lines.append('PageData:')
    for i in range(0, len(packed), 16):
        lines.append('        .byte   ' + ','.join('$%02X' % b for b in packed[i:i + 16]))
    lines.append('; Line pieces, in the order of PageCodes: in the spare bytes after the sprite images')
    lines.append('        .segment "SPARE"')
    lines.append('PageCodes:')
    lines.append('        .byte   ' + ','.join('$%02X' % ord(c) for c in GLYPHS))
    lines.append('PageGlyphs:')
    for ch, g in GLYPHS.items():
        lines.append('        .byte   ' + ','.join('$%02X' % b for b in g) + '   ; ' + ch)
    lines.append('        .segment "HIDATA"')
    open(OUT, 'w').write('\n'.join(lines) + '\n')
    print('%s: %d bytes packed (from %d)' % (os.path.relpath(OUT, ROOT), len(packed), len(data)))


if __name__ == '__main__':
    main()
