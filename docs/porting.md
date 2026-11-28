# Hopper – Porting to the C64

This chapter covers how the Commodore 64 version is built and where it stands. I followed the method of the [Light
Cycle](https://github.com/anthonyjclarke/Light-Cycle-Oric) port, a **faithful re-host**: the game logic is the Oric
code itself, and only the hardware underneath is replaced, behind a small platform layer in `c64/src/`.

---

## Approach

HOPPER is a 40×28 Oric TEXT-mode game that draws by storing bytes into screen memory and tests collisions by reading
them back. So rather than rewrite the drawing, the C64 port keeps the Oric screen as it is and shows it:

1. `c64/src/hopper.s` is `src/hopper.s` with the hardware patched **in place**. Every byte of the game stays at its Oric
   address (`$0500`–`$30D4`), so the pointers built from immediate bytes (`lda #$BB`), the page-aligned tables and both
   original bugs (`bcs $0FD6`, `jmp $296D`) work unchanged. Each patch fits the bytes it replaces and is marked `; C64:`
   in the source. The few deliberate gameplay and front-end changes (the C64 Remix) are listed in
   [remix.md](remix.md).
2. The game still draws on its Oric screen at `$BB80`, hi-scores at `$BA00` and the font save at `$3100`, all ordinary
   RAM on the C64 with BASIC and the KERNAL banked out.
3. The platform layer (`c64/src/*.s`) shows that screen on the VIC-II, plays the AY register writes on the SID, reads
   the keyboard and joystick, and keeps the Oric's timings.

`make c64-diff` lists every byte of the C64 game image that differs from the Oric program, with the routine it's in.
That comes to 854 of 11,221 bytes in 238 runs, and most of them are the widened glyphs and the moved `tmp0` /
`key_state` operands.

---

## Status

| Phase | Scope                                            | State                      |
|:------|:-------------------------------------------------|:---------------------------|
| 0     | Build, `.prg` with BASIC stub, game image mover  | Done 17-11-2026            |
| 1     | Platform layer: display, timing, input, sound    | Done 17-11-2026            |
| 2     | Whole game running: menus, credits, play, scores | Done 17-11-2026, see below |
| 3     | Checked by hand: sound, keys, joystick, NTSC     | Sound and keys play-tested |
| 4     | Release: `.prg`, `.d64`, tag                     | Tagged `v1.0` 21-11-2026   |

`make c64-smoke` (headless captures of a scripted run, `c64/src/autotest.s`) verifies these in VICE: the sound menu with
double height and blink, the credits with the hopping frog, the hi-score table with the scrolling double-height title,
the sheet-start signs, the playfield with every lane moving, the snake, hops, the death flash and the status line, the
start-up picture, and redefining the keys (a refused P and a repeated key). The scripted run doesn't cover the SID
sound (headless VICE has none), which is recorded in real time instead (`make c64-sound`,
[sound.md](sound.md#recordings)). Nor does it cover the joystick, NTSC timing, the name entry or a full sheet. I've
play-tested the sound and the keys by hand in VICE.

---

## Memory Map (C64)

| Range           | Use                                                            |
|:----------------|:---------------------------------------------------------------|
| `$0060`–`$008F` | Platform zero page (the game's stays where it was)             |
| `$0400`–`$0462` | Game variables, as on the Oric                                 |
| `$0500`–`$30D4` | The game, at its Oric addresses                                |
| `$0801`–`$33FF` | Load image: BASIC stub, then the game, moved by `Start`        |
| `$3100`–`$33FF` | Saved font (`ColdStart`), as on the Oric                       |
| `$3400`–`$7FAF` | Platform code, tables, packed start-up picture, BSS            |
| `$8000`–`$83E7` | VIC screen (bank 2); sprite pointers at `$83F8`                |
| `$8400`–`$877F` | Enhanced: frog and fly sprites (`sprites.inc`)                 |
| `$8800`–`$8FFF` | Enhanced: multicolour lane glyphs ([enhanced.md](enhanced.md)) |
| `$9000`–`$9B93` | Enhanced: lane tables, fonts, sprite code (`HIDATA`)           |
| `$A000`–`$AFFF` | Double-height character sets (top, bottom)                     |
| `$B000`–`$B7FF` | `CHARSET`: the game's font, inverse in `$B400`–`$B7FF`         |
| `$BA00`–`$BAFF` | Hi-score table, as on the Oric                                 |
| `$BB80`–`$BFDF` | The Oric screen, 40×28, as on the Oric                         |
| `$C000`–`$C7E7` | Picture: screen colours, colour RAM copy (bank 3)              |
| `$E000`–`$FF3F` | Picture: bitmap (bank 3, RAM under the KERNAL)                 |

`CHARSET` is the one address that moves. The Oric's was `$B400`, and the VIC needs a 2K boundary.

---

## Platform Mapping

| Oric                              | C64                                                         |
|:----------------------------------|:------------------------------------------------------------|
| 40×28 TEXT screen, ULA reads it   | `Present` copies 25 rows to the VIC screen                  |
| Serial attributes: ink per cell   | Colour RAM per cell                                         |
| Serial attributes: paper per cell | `$D021` per row (raster IRQ); other papers as inverse cells |
| Double height (`$0A`, `$0E`)      | Per-row top or bottom half character set                    |
| Blink (`$0C`–`$0F`)               | Cells blanked on alternate 16-frame phases                  |
| Inverse (bit 7)                   | Characters 128–255 are the inverse set                      |
| 6-pixel characters                | 8 pixels: `W6` doubles the two middle pixels                |
| `ReadKeys`: VIA + AY port A       | `ReadKeysC64`: CIA1 matrix, plus joystick port 2            |
| ROM IRQ: `ROM_KEY`, cursor blink  | Raster IRQ, while the Oric code has that IRQ on             |
| `AYWrite`: AY-3-8912              | `AyWriteC64`: SID voices 1–3                                |
| `FrameDelay`, `DelayX` busy loops | Same lengths on a CIA2 clock; the screen is drawn meanwhile |
| VIA timer 2 (`ServiceTimer`)      | `T2Check`: the same `$606B` period on the clock             |
| RESET button (NMI via `$022B`)    | RESTORE (NMI via `$022B`)                                   |

---

## Decisions

**28 rows on 25.** Each screen hides three rows it leaves blank, chosen with `tools/oric_screens.py`, which runs
the game's own drawing routines on a 6502 core and prints the Oric screens. In play the hidden rows are the strip of
river under the homes (3) and the two road markings (19, 22), so the three car lanes sit together, each in its own
colour.
Menus hide 9–11, the credits 4, 8 and 9 (rows the frog crosses only by hopping down, so it is never cut in half),
the hi-score screen 3, 20 and 21. `SetRowMap` switches maps at the calls the patched game makes when a screen starts
(`InitGameC64`, `SoundMenuC64`, `CreditsIntroC64`, `HiscoreTableC64`).

**Drawing in the waits.** The Oric spent about 24 ms of each 30 ms game frame in `FrameDelay` doing nothing. The C64
spends that time in `Present` (about 10,000 cycles) and in parsing rows, then waits out the rest, so the game runs at
the Oric's speed. A wait that the drawing overruns carries the overrun into the next one.

The `DelayX` runs (the death flash, jingles, the sheet tune) needed more than that. There the overrun is added to any
debt a wait couldn't pay, up to 65 ms, `SetFreq`'s division on the SID counts as owed time (`DIVIDE_COST`), and once a
`Present` overruns its wait the next ones come every third frame (`lagging`). That keeps those sequences at the Oric's
pace. The death flash now takes 2.5 s against the Oric's 2.1 s, where it had taken 4.5 s (Classic) and 5.3 s
(Enhanced). Play (`FrameDelay`) keeps a `Present` every frame instead. One C64 cycle counts as one Oric microsecond, so
PAL plays 1.5% slow and NTSC 2.3% fast.

**Simple and complex rows.** Rows whose only attributes are in columns 0–1 (the playfield) are copied by unrolled code
and coloured from those two cells. Rows with attributes further in (the status line, signs, menus) are parsed cell by
cell every time. A simple row that starts with a character (a cleared screen, where signs and menus are printed) is
scanned by `ScanRow` after each copy, so text printed there with its own colours or height is right in the first
frame. Playfield rows aren't scanned. Anything else that gains attributes mid-row is found by `ParseNextRow`, which the waits
run in spare time.

**Columns 0–1 and the margins.** The picture sits one column left of the Oric's. Oric column *c* is VIC column *c*–1,
so the playfield (columns 2–39) is centred with one column of the row's paper on each side. On the left that's Oric
column 1, the row's paper attribute, and on the right it's VIC column 39, a space nothing writes. Oric column 0 is
always an ink attribute that the Oric shows black, and it isn't shown at all. Drawn in place, it left a black strip and
a paper strip on the left and none on the right. The copy covers columns 2–39 only, and column 1 is drawn by `FastRow`
and `ParseRow`, which show it as the Oric does. (When the copy also wrote columns 0–1, every pass of `ParseNextRow` left a black cell in
column 0 for one frame, which wandered up and down the river.)

**The scrolling title.** The hi-score title is double height, with row 0 showing the top halves and row 1 the bottom
halves. `Present` updates them one after the other, so if the beam was drawing them in between, one frame showed the
scrolled top over the old bottom. While the top row is double height, `Present` now starts only when the beam is between lines
67 and 229, past both rows, with time to redo them before it comes back.

**Interrupts.** My game masked interrupts for the whole of play (`sei` at `NewGame`) because only the ROM's keyboard
interrupt was running. On the C64 the raster IRQ has to keep running, so that `sei` (and the one in `LoadAYRegs`) are `nop`s and
the ROM interrupt's on/off state is a flag (`zRomIrq`) set by `InitGameC64` and `RomIrqOn` (`InitTimers`).

**Attract timing.** The credits screen is held by a loop that counts 8 × 65,536 calls of `CheckMenuKeys` (~17.8 s on the
Oric). With the drawing hook in `CheckMenuKeys` that loop would run 1.6 times slower, so `AttractWait` waits the same
time by the clock instead.

**Keys.** Choice 1 is Z, X, K, M (left, right, up, down). I kept to letters, because punctuation keys move about with
VICE's host keymaps, and the first try, Z X `@` `/`, was unusable. Choice 2, the Oric's second fixed set, is now **Redefine keys**
(`RedefineKeys`, [remix.md](remix.md) changes 2 and 11, which also list the keys it refuses). Joystick port 2 works with
either choice. `key_bits` `$08` is **down** and `$04` up (`KeysToDir`); the third table slot is down, the fourth up.

**Row parsing in key waits.** A row only gets colours from attributes past column 1 when it is parsed. The game's key
waits call `Idle`, which only draws, because `CheckMenuKeys` runs inside counted loops (the hi-score scroll) and a parse
there would slow them. The controls menu's wait and the redefine prompts use `IdleParse` (`ReadMenuKey`), which parses a
row between draws, so their red title, inverse header and cyan prompts show.

**Start-up picture.** The Oric game has no start-up picture, so, as in the Light Cycle port, the C64 adds one.
`tools/make_intro.py` lays out the cover painting (`docs/images/original/cover.png`, a straight scan; the first, photographed one was skewed), the PSS logo cut
from the inlay (`inlay.png`) and a C64 strapline on the inlay's blue grid at 160×200. The scan is warm and pale, so it's
cooled and deepened first, and red, purple and light red are kept out of the painting because they turned the sky pink.
Each 4×8 cell then gets its best three colours over black, the painting is error-diffused into them, and bitmap, screen
and colour RAM are packed with a simple RLE (6.7 KB). That result is kept as the master `c64/art/intro.png` (320×200,
indexed in the C64 palette, each multicolour pixel two wide), which is edited by hand from now on. `make c64-intro`
snaps it to the palette, stops on any 8×8 block with more than black and three colours (`--fix` reduces them) and packs
it. `make_intro.py --from-scans` redraws the master from the scans, losing hand edits. `UnpackPicture` (`intro.s`) runs
once from `Start` and leaves it in VIC bank 3, unused by anything else: bitmap at `$E000` (RAM under the banked-out
KERNAL), screen colours at `$C000`, a colour RAM copy at `$C400`. `ShowPicture` copies the colour RAM back, switches the
VIC to bank 3 in multicolour bitmap mode with interrupts masked, waits 8 s on the raster or for a key or fire, then puts
bank 2 text mode back with a blank screen for the next `SetRowMap` to redraw. The test build unpacks but does not show
it at start-up.

**Attract loop** ([remix.md](remix.md), change 6). `TitleTickC64` replaces `TitleScroll`'s `jsr CheckMenuKeys`
(`$2938`): after 170 steps (about 15 s) it drops `TitleScroll`'s return address and shows the picture; 1 or fire there
starts a game (`StartGame`), anything else or the timeout goes to `AttractLoop` (credits and instructions, then
hi-scores).

---

## Sound

`AyWriteC64` keeps a copy of the 14 AY registers and drives the SID from them. A tone of AY period P becomes SID
frequency 1064276 / P (PAL) or 1025275 / P (NTSC); periods under 4 are silent. Mixer bits choose pulse 50%, noise or
nothing per voice. The SID has no per-voice volume, so the AY level 0–15 is the voice's sustain level with the shortest
envelope; a louder level retriggers the envelope, a softer one lets it decay. The game never uses the AY envelope (its
"loud" option doubles levels, none reaching 16). I haven't tested it by ear.

---

## Known Differences

| Oric                                      | C64                                                                                          |
|:------------------------------------------|:---------------------------------------------------------------------------------------------|
| 28 rows                                   | Three blank rows hidden per screen                                                           |
| Paper per cell                            | Other papers shown as inverse cells: their ink is lost                                       |
| Double height per cell                    | Per row: normal characters in a double-height row (the hedge beside GAME OVER) are stretched |
| Paper and colour change in the same frame | Paper is set as the beam reaches each row: a frame drawn mid-change can tear                 |
| Oric ROM font                             | The C64's font (the Oric's is not on the tape)                                               |
| Key sets: `Z X ' /` or `, . A Z`          | `Z X K M`, or keys the player chooses ([remix.md](remix.md))                                 |
| The frog dies at columns 2 and 39         | It can stand there; no hop off the side ([remix.md](remix.md))                               |
| RESET + up-left jumps to `$A800`          | The same; on the C64 that is character data, so it crashes                                   |

---

## Tools

| Command / file          | What it does                                                     |
|:------------------------|:-----------------------------------------------------------------|
| `make c64`              | `c64/build/hopper.prg`                                           |
| `make c64-d64`          | `c64/build/hopper.d64`                                           |
| `make c64-run`          | Launch in VICE with the labels loaded                            |
| `make c64-diff`         | Every game byte that differs from the Oric program               |
| `make c64-smoke`        | Build the scripted test `.prg`, VICE screenshots to `c64/build/` |
| `make c64-flicker`      | One-frame display glitches in the test builds (VICE, Pillow)     |
| `make c64-intro`        | Pack `c64/art/intro.png` into `c64/src/intro.rle` (Pillow)       |
| `make c64-font`         | The Enhanced Oric-style font (`c64/src/oricfont.inc`)            |
| `tools/make_intro.py`   | Pack the picture's master; `--from-scans` redraws it             |
| `tools/oric_screens.py` | Print the Oric screens, row by row, from the original code       |
| `tools/cpu6502.py`      | 6502 core used by `oric_screens.py` (from the Light Cycle repo)  |
