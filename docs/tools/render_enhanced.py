#!/usr/bin/env python3
"""Draw the mock-ups of the C64 Enhanced version (docs/enhanced*.md) from the Oric tape.

  python3 docs/tools/render_enhanced.py

The Enhanced version is planned, not built, so these are mock-ups, not VICE captures. The screens are the real ones:
the game's own routines draw them on tools/cpu6502.py (tools/oric_screens.py), and the C64 shows them the way the
port does (rows hidden per screen, glyphs widened from 6 to 8 pixels by doubling the two middle pixels, the C64 font,
the Pepto palette). On top of that the script applies each planned enhancement as docs/enhanced_graphics.md describes
it. Letters come from VICE's C64 character ROM. Writes docs/images/enhanced/. Needs Pillow. Deterministic.
"""
import math
import os
import sys

from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
OUT = os.path.join(ROOT, 'docs', 'images', 'enhanced')
LBL = os.path.join(ROOT, 'build', 'hopper.lbl')
CHARGEN = '/opt/homebrew/share/vice/C64/chargen-901225-01.bin'
sys.path.insert(0, os.path.join(ROOT, 'tools'))
import oric_screens  # noqa: E402

PEPTO = [(0x00, 0x00, 0x00), (0xFF, 0xFF, 0xFF), (0x68, 0x37, 0x2B), (0x70, 0xA4, 0xB2), (0x6F, 0x3D, 0x86),
         (0x58, 0x8D, 0x43), (0x35, 0x28, 0x79), (0xB8, 0xC7, 0x6F), (0x6F, 0x4F, 0x25), (0x43, 0x39, 0x00),
         (0x9A, 0x67, 0x59), (0x44, 0x44, 0x44), (0x6C, 0x6C, 0x6C), (0x9A, 0xD2, 0x84), (0x6C, 0x5E, 0xB5),
         (0x95, 0x95, 0x95)]
BLACK, WHITE, RED, CYAN, PURPLE, GREEN, BLUE, YELLOW = 0, 1, 2, 3, 4, 5, 6, 7
ORANGE, BROWN, LRED, DGREY, GREY, LGREEN, LBLUE, LGREY = 8, 9, 10, 11, 12, 13, 14, 15
O2C = [BLACK, RED, GREEN, YELLOW, BLUE, PURPLE, CYAN, WHITE]  # C64Colour in c64/src/video.s

SCREEN, CHARSET = 0xBB80, 0xB400
PLAY_HIDDEN, HOME_HIDDEN = (3, 19, 22), (3, 20, 21)            # the port's row maps (docs/porting.md)
FRAME_MS = 30

# Lanes: rows -> lane number; lane direction and frames per step (lane_speeds_init) for the moving figures.
LANES = {4: 0, 5: 0, 7: 1, 8: 1, 10: 2, 11: 2, 13: 3, 14: 3, 17: 4, 18: 4, 20: 5, 21: 5, 23: 6, 24: 6}
LANE_DIR = [-1, 1, -1, 1, -1, 1, -1]
LANE_FRAMES = [11, 5, 7, 5, 7, 13, 6]

# V1: multicolour colours per row: (full = colour RAM 0-7, half = $D022, edge = $D023).
MC_ROW = {4: (BROWN, BLACK, ORANGE), 5: (BROWN, BLACK, ORANGE),
          7: (RED, BROWN, LRED), 8: (RED, BROWN, LRED),
          10: (YELLOW, ORANGE, WHITE), 11: (YELLOW, ORANGE, WHITE),
          13: (RED, BROWN, LRED), 14: (RED, BROWN, LRED),
          17: (CYAN, LBLUE, WHITE), 18: (CYAN, LBLUE, WHITE),
          20: (BLUE, LBLUE, WHITE), 21: (BLUE, LBLUE, WHITE),
          23: (YELLOW, ORANGE, WHITE), 24: (YELLOW, ORANGE, WHITE)}
LANE_TOPS = {4, 7, 10, 13, 17, 20, 23}                         # first row of each lane: the only one with edges
LANE_NAMES = {4: 'Logs (black)', 7: 'Turtles', 10: 'Logs (yellow)', 13: 'Logs (red)', 17: 'Trucks',
              20: 'Cars (blue)', 23: 'Cars (yellow)'}
RIVER = set(range(4, 15))
VERGE = {15, 16, 25, 26}
FROG_ROW = 25
ALL = dict(mc=True, frog=True, fly=True, tex=True, road=True)
NONE = dict(mc=False, frog=False, fly=False, tex=False, road=False)

FLY = [['..ww....ww..',
        '.wwww..wwww.',
        '..wwwkkwww..',
        '....kkkk....',
        '...kkrrkk...',
        '....kkkk....',
        '.....kk.....'],
       ['............',
        '............',
        'wwwwwkkwwwww',
        '.wwwkkkkwww.',
        '...kkrrkk...',
        '....kkkk....',
        '.....kk.....']]
FLY_COL = {'w': LGREY, 'k': BLACK, 'r': RED}


# --- glyphs -------------------------------------------------------------------------------------------------------

def widen(b):
    """An Oric 6-pixel row as the port draws it: 8 pixels, the two middle ones doubled (W6)."""
    return [(b >> i) & 1 for i in (5, 4, 3, 3, 2, 2, 1, 0)]


def glyph_at(mem, addr):
    return [widen(mem[addr + y]) for y in range(8)]


def is_game_code(c):
    return 0x21 <= c <= 0x2F or 0x3A <= c <= 0x3D or 0x5B <= c <= 0x7F


def c64_font():
    """ASCII 32-95 from the C64 character ROM (upper case set), 8 pixels wide, as the port shows text."""
    rom = open(CHARGEN, 'rb').read()
    font = {}
    for code in range(0x20, 0x60):
        screen = code - 0x40 if code >= 0x40 else code
        font[code] = [[(rom[screen * 8 + y] >> (7 - x)) & 1 for x in range(8)] for y in range(8)]
    return font


def to_mc(g, edges=True):
    """Pixel pairs -> 0 paper, 1 half ($D022), 2 edge ($D023), 3 full (colour RAM).

    The edge is the topmost full pair in each pixel column: the top outline of a shape, lit from above. For lanes it
    applies to the top row of characters only (edges=False below), so the grain inside a log stays its own colour."""
    rows = len(g)
    out = []
    seen = [False] * (len(g[0]) // 2)
    for y in range(rows):
        r = []
        for p in range(len(seen)):
            n = g[y][2 * p] + g[y][2 * p + 1]
            if n == 2 and edges and not seen[p]:
                r.append(2)
            else:
                r.append(3 if n == 2 else n)
            if n == 2:
                seen[p] = True
        out.append(r)
    return out


def hash2(a, b):
    h = (a * 374761393 + b * 668265263) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    return h ^ (h >> 16)


# --- the model ----------------------------------------------------------------------------------------------------

class Game:
    def __init__(self):
        g = oric_screens.screen_game()
        h = oric_screens.screen_hiscores()
        self.play = self.parse(g[SCREEN:SCREEN + 1120])
        self.home = self.parse(h[SCREEN:SCREEN + 1120])
        self.glyphs = {c: glyph_at(g, CHARSET + c * 8) for c in range(128) if is_game_code(c)}
        lab = labels()
        t = oric_screens.load()
        self.frog = [[glyph_at(t, lab['frog_gfx'] + d * 32 + k * 8) for k in range(4)] for d in range(4)]
        self.splat = [glyph_at(t, lab['splat_gfx'] + k * 8) for k in range(4)]
        self.font = c64_font()
        for r in (25, 26):                                  # the frog is drawn by the figures, not the model
            for c in range(2, 40):
                if 0x3A <= self.play[r][c]['code'] <= 0x3D:
                    self.play[r][c]['code'] = 0x20

    @staticmethod
    def parse(screen):
        rows = []
        for r in range(28):
            ink, paper, dh, cells = 7, 0, False, []
            for c in range(40):
                b = screen[r * 40 + c]
                inv, v = b & 0x80, b & 0x7F
                if v < 0x20:
                    if v < 8:
                        ink = v
                    elif v < 16:
                        dh = bool(v & 2)
                    elif v < 24:
                        paper = v - 16
                    cells.append(dict(attr=True, code=0x20, ink=ink, paper=paper ^ 7 if inv else paper, dh=dh))
                else:
                    cells.append(dict(attr=False, code=v, ink=ink ^ 7 if inv else ink,
                                      paper=paper ^ 7 if inv else paper, dh=dh))
            rows.append(cells)
        return rows

    def text_glyph(self, code):
        return self.font.get(code) or self.font.get(code & 0x5F) or [[0] * 8 for _ in range(8)]

    def frog_bitmap(self, d):
        q = self.frog[d]
        return [[q[(0 if y < 8 else 2) + (1 if x >= 8 else 0)][y & 7][x & 7] for x in range(16)] for y in range(16)]


def labels():
    out = {}
    for line in open(LBL):
        parts = line.split()
        if len(parts) == 3 and parts[0] == 'al':
            out[parts[2].lstrip('.')] = int(parts[1], 16)
    return out


# --- drawing ------------------------------------------------------------------------------------------------------

class Canvas:
    def __init__(self, w=320, h=200, bg=BLACK):
        self.img = Image.new('RGB', (w, h), PEPTO[bg])
        self.px = self.img.load()
        self.w, self.h = w, h

    def put(self, x, y, ci):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[x, y] = PEPTO[ci]

    def get(self, x, y):
        return self.px[x, y]

    def scaled(self, s):
        return self.img.resize((self.w * s, self.h * s), Image.NEAREST)


def ripple(cx, px, py, phase):
    h = hash2(cx * 7 + (phase & 1) * 131, py)
    if py % 4 != 1 or (h & 7) > 1:
        return -1
    start = (h >> 4) & 6
    return LBLUE if start <= px < start + 4 else -1


def tuft(cx, px, py, row):
    h = hash2(cx * 13 + row * 3, 99)
    if h & 3:
        return -1
    tx, base = ((h >> 3) & 3) * 2, 6 if row in (16, 26) else 5
    colour = ORANGE if row < 20 else LGREEN
    if py == base + 1 and px in (tx, tx + 1):
        return colour
    if py == base and px in (tx + 2, tx + 3):
        return colour
    return -1


def draw_play(game, opt, cv, frog=None, offsets=None, rows=None, phase=0):
    """The playfield on cv (320x200). frog = (col, dir) for the character frog when opt['frog'] is off."""
    vis = [r for r in range(28) if r not in PLAY_HIDDEN]
    offsets = offsets or {}
    for vy, r in enumerate(vis):
        if rows is not None and r not in rows:
            continue
        cells, lane = game.play[r], LANES.get(r)
        off = offsets.get(lane, 0) if lane is not None else 0
        pal = MC_ROW.get(r)
        for py in range(8):
            y = vy * 8 + py
            for x in range(320):
                col = x >> 3
                if col < 2:
                    cv.put(x, y, BLACK if col == 0 else O2C[cells[1]['paper']])
                    continue
                if lane is not None:
                    sx = (x - 16 - off) % 304
                    c, px = 2 + (sx >> 3), sx & 7
                else:
                    c, px = col, x & 7
                cell = cells[c]
                code, ink, paper = cell['code'], O2C[cell['ink']], O2C[cell['paper']]
                if frog and not opt['frog'] and r in (25, 26) and c in (frog[0], frog[0] + 1):
                    g = game.frog[frog[1]][(r - 25) * 2 + (c - frog[0])]
                    cv.put(x, y, BLACK if g[py][px] else paper)
                    continue
                g = game.glyphs.get(code) if is_game_code(code) else (game.text_glyph(code) if code != 0x20 else None)
                ci = paper
                if g:
                    if opt['mc'] and r <= 2:                # hedge: drawn leaf texture instead of the dither
                        v = hash2((x >> 1) + 977, y) % 9
                        ci = GREEN if v < 5 else LGREEN if v < 7 else BROWN if v < 8 else paper
                    elif opt['mc'] and pal and is_game_code(code):
                        v = mc_cache(g, r in LANE_TOPS)[py][px >> 1]
                        ci = (paper, pal[1], pal[2], pal[0])[v]
                    else:
                        ci = ink if g[py][px] else paper
                elif opt['tex']:
                    t = -1
                    if r in RIVER and cell['paper'] == 4:
                        t = ripple(c, px, py, phase + (lane or 0))
                    elif r in VERGE:
                        t = tuft(c, px, py, r)
                    if t >= 0:
                        ci = t
                cv.put(x, y, ci)
    if opt['road']:
        for r in (20, 23):
            y = vis.index(r) * 8
            for x in range(16, 320):
                if cv.get(x, y) == PEPTO[BLACK]:
                    cv.put(x, y, GREY)
    if opt['fly']:
        draw_fly(cv, 20 * 8 + 2, 8 + 2, 0)


_MC = {}


def mc_cache(g, edges):
    k = (id(g), edges)
    if k not in _MC:
        _MC[k] = to_mc(g, edges)
    return _MC[k]


def draw_frog_sprite(game, cv, ox, oy, d, stretch=False):
    """V2: multicolour body (green, light green, yellow) with a hires black outline sprite laid over."""
    mc = to_mc(game.frog_bitmap(d))
    cols = (None, LGREEN, YELLOW, GREEN)
    rows = [0, 1, 2, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 13, 14, 15] if stretch else list(range(16))
    lift = 2 if stretch else 0

    def filled(yy, xx):
        return 0 <= yy < len(rows) and 0 <= xx < 16 and mc[rows[yy]][xx >> 1] > 0
    for yy in range(-1, len(rows) + 1):
        for xx in range(-1, 17):
            if not filled(yy, xx) and (filled(yy - 1, xx) or filled(yy + 1, xx) or filled(yy, xx - 1)
                                       or filled(yy, xx + 1)):
                cv.put(ox + xx, oy + yy - lift, BLACK)
    for yy in range(len(rows)):
        for xx in range(16):
            v = mc[rows[yy]][xx >> 1]
            if v:
                cv.put(ox + xx, oy + yy - lift, cols[v])


def draw_fly(cv, ox, oy, f):
    for y, s in enumerate(FLY[f]):
        for x, ch in enumerate(s):
            if ch != '.':
                cv.put(ox + x, oy + y, FLY_COL[ch])


def text(game, cv, s, x, y, ink, paper=None):
    for i, ch in enumerate(s):
        g = game.text_glyph(ord(ch))
        for yy in range(8):
            for xx in range(8):
                if g[yy][xx]:
                    cv.put(x + i * 8 + xx, y + yy, ink)
                elif paper is not None:
                    cv.put(x + i * 8 + xx, y + yy, paper)


CYCLE = [BLUE, PURPLE, LBLUE, CYAN, LGREEN, YELLOW, WHITE, WHITE, YELLOW, LGREEN, CYAN, LBLUE, PURPLE, BLUE]
SCROLLER = '  HOPPER - P.S.S. 1983 - NOW ON THE COMMODORE 64 - '


def draw_home(game, enhanced, cv, t=0):
    vis = [r for r in range(28) if r not in HOME_HIDDEN]
    for vy, r in enumerate(vis):
        for py in range(8):
            y = vy * 8 + py
            for x in range(320):
                cell, px = game.home[r][x >> 3], x & 7
                ci = O2C[cell['paper']]
                if not cell['attr'] and cell['code'] != 0x20:
                    g = game.text_glyph(cell['code'])
                    gy = (py + (r & 1) * 8) >> 1 if cell['dh'] else py
                    if g[gy][px]:
                        ci = CYCLE[((y + t // 40) >> 1) % len(CYCLE)] if enhanced and cell['dh'] else O2C[cell['ink']]
                cv.put(x, y, ci)
    sel = vis.index(25) * 8                                 # V0: the version line
    text(game, cv, '[F1] VERSION', 3 * 8, sel, CYAN, BLACK)
    text(game, cv, ' CLASSIC ', 17 * 8, sel, GREY if enhanced else BLACK, BLACK if enhanced else YELLOW)
    text(game, cv, ' ENHANCED ', 27 * 8, sel, BLACK if enhanced else GREY, YELLOW if enhanced else BLACK)
    if enhanced:                                            # F1: raster bars, scroller on row 23, hopping frog
        for yb in (-3, 17):
            for k in range(2):
                for x in range(320):
                    cv.put(x, yb + k, CYCLE[(k + 3) % len(CYCLE)])
        y0 = vis.index(23) * 8
        for x in range(320):
            sx = x % (len(SCROLLER) * 8)
            g = game.text_glyph(ord(SCROLLER[sx >> 3]))
            for py in range(8):
                if g[py][sx & 7]:
                    cv.put(x, y0 + py, WHITE if py < 3 else LGREY if py < 6 else GREY)
        draw_frog_sprite(game, cv, 15 * 8, vis.index(19) * 8, 3)


# --- figures ------------------------------------------------------------------------------------------------------

def save(img, name):
    img.save(os.path.join(OUT, name), optimize=True)
    print('docs/images/enhanced/' + name)


def bordered(cv, scale=2, border=BLACK, pad=16):
    out = Image.new('RGB', ((cv.w + pad * 2) * scale, (cv.h + pad * 2) * scale), PEPTO[border])
    out.paste(cv.scaled(scale), (pad * scale, pad * scale))
    return out


def play_screens(game):
    cv = Canvas()
    draw_play(game, NONE, cv, frog=(20, 0))
    save(bordered(cv), 'play-classic.png')
    cv = Canvas()
    draw_play(game, ALL, cv)
    draw_frog_sprite(game, cv, 20 * 8, [r for r in range(28) if r not in PLAY_HIDDEN].index(FROG_ROW) * 8, 0)
    save(bordered(cv), 'play-enhanced.png')
    detail = cv.img.crop((96, 88, 256, 176)).resize((640, 352), Image.NEAREST)
    save(detail, 'play-detail.png')


def home_screens(game):
    for enhanced, name in ((False, 'home-classic.png'), (True, 'home-enhanced.png')):
        cv = Canvas()
        draw_home(game, enhanced, cv)
        save(bordered(cv), name)


def lane_sheet(game):
    """Each lane: a stretch of the original (as the port draws it) beside the multicolour version, and its colours."""
    lab_w, strip_w, sw, scale = 120, 96, 18, 3
    rows = sorted(LANE_NAMES)
    h = 16 * scale + 14
    img = Image.new('RGB', (lab_w + (strip_w * scale + 20) * 2 + sw * 3 + 60, len(rows) * h + 34), (24, 24, 24))
    d = ImageDraw.Draw(img)
    d.text((lab_w, 8), 'Port today (hires)', fill=(200, 200, 200))
    d.text((lab_w + strip_w * scale + 20, 8), 'Enhanced (multicolour)', fill=(200, 200, 200))
    d.text((lab_w + (strip_w * scale + 20) * 2, 8), 'RAM $D022 $D023', fill=(200, 200, 200))
    for i, r in enumerate(rows):
        y0 = 26 + i * h
        d.text((10, y0 + 18), LANE_NAMES[r], fill=(220, 220, 220))
        start = next(c for c in range(2, 40) if is_game_code(game.play[r][c]['code']))
        for k, opt in enumerate((NONE, dict(NONE, mc=True))):
            cv = Canvas(strip_w, 16)
            for rr in (r, r + 1):
                cells = game.play[rr]
                for py in range(8):
                    for x in range(strip_w):
                        c = min(39, start + (x >> 3))
                        cell = cells[c]
                        g = game.glyphs.get(cell['code']) if is_game_code(cell['code']) else None
                        paper, ink = O2C[cell['paper']], O2C[cell['ink']]
                        ci = paper
                        if g:
                            if opt['mc']:
                                ci = (paper, MC_ROW[rr][1], MC_ROW[rr][2], MC_ROW[rr][0])[
                                    mc_cache(g, rr in LANE_TOPS)[py][(x & 7) >> 1]]
                            else:
                                ci = ink if g[py][x & 7] else paper
                        cv.put(x, (rr - r) * 8 + py, ci)
            img.paste(cv.scaled(scale), (lab_w + k * (strip_w * scale + 20), y0))
        for j, ci in enumerate(MC_ROW[r]):
            x0 = lab_w + (strip_w * scale + 20) * 2 + j * (sw + 6)
            d.rectangle((x0, y0 + 12, x0 + sw, y0 + 12 + sw), fill=PEPTO[ci], outline=(90, 90, 90))
    save(img, 'lanes.png')


def sprite_sheet(game):
    cv = Canvas(220, 34, DGREY)
    for i in range(4):
        draw_frog_sprite(game, cv, 8 + i * 26, 6, i)
    draw_frog_sprite(game, cv, 118, 8, 0, True)
    sp = [[game.splat[(2 if y >= 8 else 0) + (1 if x >= 8 else 0)][y & 7][x & 7] for x in range(16)] for y in range(16)]
    for y, row in enumerate(sp):
        for p in range(8):
            n = row[2 * p] + row[2 * p + 1]
            if n:
                for k in (0, 1):
                    cv.put(146 + 2 * p + k, 6 + y, LRED if n == 2 else RED)
    draw_fly(cv, 174, 12, 0)
    draw_fly(cv, 196, 12, 1)
    img = cv.scaled(4)
    d = ImageDraw.Draw(img)
    for x, label in ((32, 'up'), (136, 'down'), (240, 'left'), (344, 'right'), (472, 'hop'), (584, 'splat'),
                     (696, 'fly, 2 frames')):
        d.text((x, 104), label, fill=(230, 230, 230))
    save(img, 'sprites.png')


def hop_gif(game):
    """V2: two hops along the start verge, the port's character frog above the sprite frog."""
    vis = [r for r in range(28) if r not in PLAY_HIDDEN]
    y_frog = vis.index(FROG_ROW) * 8
    frames = []
    for f in range(36):
        n, sub = divmod(f, 18)
        a, b = 18 + n * 2, 20 + n * 2
        hop = min(1.0, sub / 5)
        top, bot = Canvas(), Canvas()
        draw_play(game, NONE, top, frog=(b if sub else a, 3), rows={25, 26})
        draw_play(game, dict(NONE, tex=True, mc=True, frog=True), bot, rows={25, 26})
        e = 1 - (1 - hop) ** 2
        lift = round(math.sin(math.pi * hop) * 5)
        draw_frog_sprite(game, bot, round((a + (b - a) * e) * 8), y_frog - lift, 3, 0 < hop < 1)
        crop = (112, y_frog - 8, 224, y_frog + 16)
        frame = Image.new('RGB', (112 * 4, 24 * 4 * 2 + 8), PEPTO[DGREY])
        frame.paste(top.img.crop(crop).resize((448, 96), Image.NEAREST), (0, 0))
        frame.paste(bot.img.crop(crop).resize((448, 96), Image.NEAREST), (0, 104))
        frames.append(frame)
    frames[0].save(os.path.join(OUT, 'hop.gif'), save_all=True, append_images=frames[1:], duration=40, loop=0)
    print('docs/images/enhanced/hop.gif')


def smooth_gif(game):
    """V4: the yellow logs over 4 steps, whole-character steps (today) above per-pixel scrolling."""
    vis = [r for r in range(28) if r not in PLAY_HIDDEN]
    y = vis.index(10) * 8
    lane, n = 2, LANE_FRAMES[2]
    frames = []
    for f in range(n * 4):
        top, bot = Canvas(), Canvas()
        draw_play(game, NONE, top, offsets={lane: (f // n) * 8 * LANE_DIR[lane]}, rows={10, 11})
        draw_play(game, NONE, bot, offsets={lane: round(f / n * 8) * LANE_DIR[lane]}, rows={10, 11})
        frame = Image.new('RGB', (160 * 3, 16 * 3 * 2 + 6), PEPTO[DGREY])
        frame.paste(top.img.crop((16, y, 176, y + 16)).resize((480, 48), Image.NEAREST), (0, 0))
        frame.paste(bot.img.crop((16, y, 176, y + 16)).resize((480, 48), Image.NEAREST), (0, 54))
        frames.append(frame)
    frames[0].save(os.path.join(OUT, 'smooth-lanes.gif'), save_all=True, append_images=frames[1:],
                   duration=FRAME_MS, loop=0)
    print('docs/images/enhanced/smooth-lanes.gif')


def main():
    if not os.path.exists(LBL):
        sys.exit('build/hopper.lbl not found: run make first')
    os.makedirs(OUT, exist_ok=True)
    game = Game()
    play_screens(game)
    home_screens(game)
    lane_sheet(game)
    sprite_sheet(game)
    hop_gif(game)
    smooth_gif(game)


if __name__ == '__main__':
    main()
