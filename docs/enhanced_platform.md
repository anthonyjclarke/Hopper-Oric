# Hopper – Enhanced Platform Layer

How the C64 Enhanced version ([enhanced.md](enhanced.md)) fits into the platform layer
([platform_layer.md](platform_layer.md)): the version flag, hooks into the game (none so far), the changes to the raster
interrupt and to `Present`, the sprite driver, memory, frame time, disk hi-scores and testing. The version flag (V0) and
the multicolour lanes (V1) are built, in `c64/src/platform.s` and `c64/src/enhanced.s`; the rest is the plan. Names in
this chapter that don't exist in `c64/src/` yet are listed under [Planned Names](#planned-names).

---

## The Version Flag

**Built.** One zero-page byte, `zEnhanced` (`$90`, in the platform's area): 0 for Classic, `$FF` for Enhanced. `Start`
sets it to `$FF`, so a power-up is in Enhanced. Nothing else writes it but the switch: RESTORE goes through the Oric's
RESET path (`NmiHandler`, `WarmStart`), which doesn't touch the platform's zero page, so the choice survives it. Every
enhancement will test it, and with it clear the platform runs exactly today's code paths. There is one `.prg` with both
looks loaded all the time, so flipping costs nothing but a redraw.

`TitleTickC64`, which already replaces the game's `jsr CheckMenuKeys` in `TitleScroll` (`$2938`), does three things for
the switch:

1. On the screen's first tick (`titleSteps` still 0) it calls `DrawVersionLine`. The line is drawn there and not in
   `HiscoreTableC64`, because the name entry screen also draws the table, and doesn't show the line.
2. Before `CheckMenuKeys`, `VersionKeys` looks for a flip: F1, or a new push of the joystick left or right
   (edge-detected in `joyLR`). `ScanRomKey` reports F1 as `KEY_F1` (`$01`) + `$80` in `ROM_KEY`, like any other key,
   so a held F1 flips once.
3. On a flip, or when `versionReq` says F1 flipped it elsewhere, it sets `titleSteps` back to 1, so the 15-second
   attract timer starts again, and falls into `DrawVersionLine`.

F1 works on every screen before a game. `Present` checks `ROM_KEY` while the ROM interrupt is on (`zRomIrq`, every
screen but play) and calls `TakeF1`, which takes the key out and runs `FlipVersion`: it inverts `zEnhanced`, changes
the font (`SetFontC64`, V7: the screen is blanked for a couple of frames meanwhile) and sets `versionReq` for the home
screen's line. So the menus, the credits and name entry flip in place, and the game's key waits never see F1.
`ReadRomKey` makes the same check after its `Idle`, for an F1 that arrives just after the draw, and reloads `ROM_KEY`
before it returns: the game's key waits branch on its flags. The start-up picture runs with interrupts masked and reads
the keyboard itself: `ShowPicture` returns `PIC_F1` for F1, and `TitleTickC64` flips and goes to the home screen
(`HiscoreScreen`, `$296B`); at power-up `Start` just clears `zEnhanced`.

`DrawVersionLine` writes row 25 of the Oric screen (`SCREEN` + 1000) from `VersionText`: a cyan ink attribute and `[F1]
VERSION`, then each version name after a blue ink attribute. For the chosen one it makes the attribute white and sets
bit 7 of each character, the Oric's inverse, which the port shows as black on white. Because the row starts with a
character and has attributes further in, `ScanRow` sends it to `ParseRow` on its first copy, so it shows in the right
colours at once ([porting.md](porting.md#decisions)).

`make c64-smoke` presses F1 on the home screen (`c64/src/autotest.s`), and its `hiscores` and `version` captures show
both states. The game it then starts is in Classic.

---

## Hooks

**None so far.** The plan expected two hooks, in `SetTurtleFrame` and `SetFrogGfx`, so that the multicolour set could
follow the glyphs the game rewrites. The frog turned out to be rewritten in six places (four directions, the splat and
the frog in a home), with no spare bytes in most of them. So the platform notices the changes itself instead, in
`McDynamic` ([enhanced_graphics.md](enhanced_graphics.md#v1--multicolour-lane-graphics)), and `make c64-diff` shows no
game bytes added for Enhanced.

Everything reads the game's state without changing the game: `turtle_frame`, the glyphs at `CHARSET`, the Oric screen,
and later `frog_row`, `frog_col`, `fly_on`, `fly_ptr`, `lane_speeds` and the AY register copy.

---

## Raster Interrupt

The interrupt runs at the last line of each text row and sets `$D021` and `$D018` for the next row
([platform_layer.md](platform_layer.md#timing)). **Built (V1):** while `zMcPlay` is set, it also writes `$D022` and
`$D023` from `rowMc1` and `rowMc2`, after the two existing stores, and the frame interrupt sets `$D016` bit 4
(multicolour) for the whole screen. `D018Table` gains `D018_MC` for `CS_MC`. VICE shows no seam at row boundaries: the
new stores land before the next row's first pixel line.

`zMcPlay` is `$FF` only while Enhanced is chosen and the play screen's row map is set (`SetRowMap`). On every other
screen, and in Classic, the interrupt skips the writes (about 5 cycles a row), so menus, credits and the attract loop
run at Classic speed in both versions. That matters because the credits' short waits already overrun, and any extra cost
there moves the whole attract loop.

**Built (V6):** the road markings need no extra interrupts. In the interrupts for C64 rows 18 and 20 (`MarkRow`, Oric
rows 20 and 23, below the hidden rows 19 and 22), when that row shows multicolour lanes (`rowCset` = `CS_MC`, so not the
sheet-start signs), the handler waits about 25 cycles, sets `$D021` to grey, waits 64 cycles and sets the row's paper
back. The first line of a text row is a badline, so both stores land in the side border and exactly one raster line
turns grey, on PAL (63 cycles a line) and NTSC (65). Without the 25-cycle lead the first store landed mid-line and left
an 8-pixel grey dash on the line above. About 100 cycles a frame.

**Built (V4):** every row interrupt writes `$D016` from `rowCtl2` (multicolour and fine scroll), 4 cycles before the
`$D021` store, in the right border of the row above's last line. Written after `$D018`, as the multicolour bit first
was, it landed on the row's first line, a badline, too late: that line stayed unshifted. To load it ahead of the delay
the paper now goes through a patched `lda #` (`@paper`), and `EV_DELAY_PAL` / `EV_DELAY_NTSC` drop from 3 to 1, so the
other stores move by only 2 cycles. `SetRowMap` fills `rowCtl2` with `$08`, or `$18` in Enhanced play; `Present` sets
the lane rows ([enhanced_graphics.md](enhanced_graphics.md#v4--smooth-scrolling-lanes)). Still planned: the F1
scroller's fine scroll.

---

## Present and FastRow

| Change                        | Where                 | Does                                                      |
|:------------------------------|:----------------------|:----------------------------------------------------------|
| Multicolour lane rows (built) | `FastRow`, `McSimple` | `McRowSetup`: colour RAM = ink + 8, `CS_MC`, lane colours |
| Glyph tracking (built)        | `Present`             | `McDynamic`: build or update the multicolour set          |
| Space translation (V5)        | `Present`             | `$20` to the row's texture character (`rowSpace`)         |

`ParseRow` calls `McSimple` when it finds a row simple, because after `SetRowMap` every row is parsed once, and a lane
row that never changes its columns 0–1 would otherwise never reach `FastRow`. Each call sits behind `bit zMcPlay`, so
Classic pays a few cycles at most.

`McDynamic` costs about 600 cycles a pass and a full build about 30,000 once per game. The translation (V5) would add a
table lookup per copied cell on the textured rows, about 4,000 cycles a frame. `Present` costs about 10,000, in a game
frame of about 30,000 that the Oric mostly spent waiting ([porting.md](porting.md#decisions)).

---

## Sprites

`UpdateSprites` runs once a frame, from the frame interrupt, when `zEnhanced` is set and a game is on:

- **Frog.** Screen position from `frog_row` and `frog_col`, through the play row map. When either changes, the displayed
  position moves to the new one over 4–5 frames on an arc. Two sprites: multicolour body and hires outline.
- **Fly.** Position from `fly_ptr` while `fly_on` is set, two frames alternating.
- **Death.** The splat (road) or splash (river) in place of the frog during the death sequence.
- **Home screen.** The hopping frog of F1 uses the same frog sprites.

Sprite pointers are at `$83F8`–`$83FF`, after the VIC screen at `$8000`. Sprites go off whenever `zEnhanced` is clear,
on menus and while the start-up picture shows.

---

## Memory

The VIC shows bank 2 (`$8000`–`$BFFF`) during play. In banks 0 and 2 the VIC sees the character ROM at `$9000`–`$9FFF`,
not RAM, so sprites and character sets must go below `$9000` or in `$B800`–`$B9FF`. Code and tables can go anywhere
free.

| Region          | Size    | VIC sees it | Use                                  |
|:----------------|:--------|:------------|:-------------------------------------|
| `$76D9`–`$7E3E` | 1,894 B | No          | Used: V0, V1, V4, V6, V7 code, BSS   |
| `$7E3F`–`$7FFF` | 449 B   | No          | Free                                 |
| `$8400`–`$87FF` | 1,024 B | Yes         | 16 sprite blocks: frog               |
| `$8800`–`$8FFF` | 2,048 B | Yes         | Used: multicolour play set (V1)      |
| `$9000`–`$9722` | 1,827 B | No          | Used: V4 tables; V7 fonts            |
| `$9723`–`$9FFF` | 2,269 B | No          | SID tables, title tune, disk code    |
| `$B800`–`$B9FF` | 512 B   | Yes         | 8 sprite blocks: splat, splash, fly  |
| `$C800`–`$CFFF` | 2,048 B | Bank 3 only | Spare                                |
| `$D000`–`$DFFF` | 4,096 B | No          | Spare (RAM under I/O)                |
| `intro.rle`     | 6,739 B | No          | Spare after `UnpackPicture` has run  |

The BSS now ends at `$7E3E` (`c64/build/hopper.map`), leaving 449 bytes below `$8000`: new tables go in `HIDATA`. Since V7, Enhanced data goes in
the `HIGH` area at `$9000`–`$9FFF` (segment `HIDATA`, `c64/cfg/c64.cfg`). The one-file `.prg` therefore also covers
`$8000`–`$8FFF` (the `GAP` area, zeros), which is harmless because the VIC screen and the multicolour set are written at
run time. The `.prg` grew from 29 KB to 35 KB. The full set of changes needs about 9.5 KB, so it still fits with the
packed picture's space in reserve.

---

## F2 – Hi-Scores Saved to Disk

The hi-score table at `$BA00` (`HISCORES`) is saved to the disk the game loaded from after a new name is entered, and
loaded at start-up if the file is there. Saving needs the KERNAL, which the port banks out, so it runs on a plain screen
after name entry: interrupts masked, KERNAL in, `SAVE`, KERNAL out, the raster interrupt back. The version choice is
saved in the same file. With no disk drive (a `.prg` run from a cartridge or a tape image), it says nothing and carries
on. About 0.4 KB.

---

## Building and Testing

There is one build, `make c64`, and the `.prg` holds both versions. `make c64-smoke` builds two scripted test programs
from the same key script (`c64/src/autotest.s`):

| Build                      | Script                                          | Captures                            |
|:---------------------------|:------------------------------------------------|:------------------------------------|
| `c64/build/test/`          | F1 on the home screen, then play in Classic     | `hiscores`, `version`, `play`…      |
| `c64/build/test-enhanced/` | `-D AUTOTEST_ENHANCED`: no F1, play in Enhanced | `enh-play`, `enh-hops`, `enh-later` |

`tools/c64_screens.py` picks the program by the capture's name (`enh-*`). Classic captures are compared by eye with the
previous build's: the few cycles Enhanced adds to shared paths can move a capture by a frame. Still to check by hand in
VICE: real F1 and joystick presses (F1 on the picture, which reads the keyboard itself, can't be scripted), RUN/STOP
in a game, RESTORE, a full sheet in Enhanced, and NTSC.

The key script leaves at least 25 frames between keys, and 80 between the sound menu and the controls menu: keys
injected at fixed frames are lost if they arrive before the screen that wants them, and the old 15-frame gaps broke as
soon as the code took a few more cycles. F1 goes in at frame 2500 and the game starts at 2600.

---

## Planned Names

Names this section uses that don't exist yet. They are in `docs/tools/doc_names_ignore.txt` until the code exists, and
are removed from there as each one is written.

| Name            | Kind    | For                                        |
|:----------------|:--------|:-------------------------------------------|
| `UpdateSprites` | Routine | Frog, fly and death sprites, the hop tween |
| `rowSpace`      | Table   | Texture character for `$20`, per row       |
