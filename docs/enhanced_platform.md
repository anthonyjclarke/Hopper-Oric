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

The switch is on the instructions page only. `ScanRomKey` reports F1 as `KEY_F1` (`$01`) + `$80` in `ROM_KEY`, like
any other key, so a held F1 counts once. `Present` checks `ROM_KEY` while the ROM interrupt is on (`zRomIrq`, every
screen but play) and calls `TakeF1`, and `ReadRomKey` makes the same check after its `Idle`, for an F1 that arrives
just after the draw (it reloads `ROM_KEY` before it returns: the game's key waits branch on its flags). `TakeF1` always
takes the key out, so the game's key waits never see F1, and flips only when `versionShown` is set: by
`DrawVersionLine` on Classic's page once the frog has laid it down, and by `EnhancedPage` at once. `SetRowMap` clears it
on every new screen. A flip clears the screen, inverts `zEnhanced`, changes the font (`SetFontC64`, V7: the screen is
blanked for a couple of frames), silences the sound, resets the stack and starts the attract loop again
(`AttractLoop`), so the page comes back in the new look: Classic's frog walk or Enhanced's page (F3).

`DrawVersionLine` writes row 17 of the Oric screen (`versionAt`, set by `CreditsEndC64`) from `VersionText`: a cyan ink attribute and `[F1]
VERSION`, then each version name after a blue ink attribute. For the chosen one it makes the attribute white and sets
bit 7 of each character, the Oric's inverse, which the port shows as black on white. Because the row starts with a
character and has attributes further in, `ScanRow` sends it to `ParseRow` on its first copy, so it shows in the right
colours at once ([porting.md](porting.md#decisions)).

`make c64-smoke` presses F1 on the Enhanced page (`c64/src/autotest.s`): its `instructions` capture shows the page,
and `credits` and `credits-done` the Classic page that follows. The game it then starts is in Classic.

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
sheet-start signs), the row's first line is grey. `FineRow` sets `rowIrqBg` for those rows to grey (`MARK_COLOUR`),
and the interrupt stores `rowIrqBg`, not `rowPaper`, at the row boundary, so the grey starts exactly with the row.
Straight after the boundary stores it puts the row's real paper back as the row's second line starts. The first line
of a text row is a badline, which stalls the CPU to near the line's end, and the frog's sprites take more cycles right
after it, so counting cycles from the boundary left the paper anywhere up to 8 characters into the second line when the
frog was near. The interrupt instead waits for the raster to pass the badline (`cpx $D012`, `bcs`), with the loop
already running before the stall: the line and the paper are immediates in that code, which `IrqArm` writes at the end
of the row interrupt above (`IrqLine` 0 for a row without a marking, which skips the wait). The line is the lane's top
pixel line, which the vehicles leave nearly empty, so each lane's traffic sits between
two lines. (The first version waited 25 and then 64 cycles after the boundary; once V4 and V7 had added code ahead of
it, the grey had drifted to the lane's third line, across the tops of the cars.) About 30 cycles a frame.

**Built (V4):** every row interrupt also writes `$D016` from `rowCtl2` (multicolour and fine scroll). `SetRowMap` fills
`rowCtl2` with `$08`, or `$18` in Enhanced play; `Present` sets the lane rows
([enhanced_graphics.md](enhanced_graphics.md#v4--smooth-scrolling-lanes)). Still planned: the F1 scroller's fine
scroll.

**The store window.** The row's three values (`$D018`, `$D021`, `$D016`) are loaded into Y, A and X first and stored
back to back, 4 cycles apart. They must land between the end of the row above's last line and the start of this row's
first, a badline, which stalls the CPU from near its start; the interrupt itself starts up to 7 cycles late, depending
on the instruction it breaks into. When V4 first spread the stores over 10 cycles, the character set sometimes landed
late, and that row's first line was drawn with the old set: one line of wrong glyphs on double-height text and
multicolour lanes, a flicker every few frames. Measured in VICE (the monitor's line and cycle at each store, over
thousands of row interrupts), the first store now starts at cycle 49–55 of the line and the third by cycle 0 of the
next. A store must start by cycle 8 of the next line: one that starts later reads during the badline and waits for its
end. One cycle earlier and the first store lands before the row above's last line ends (a changed paper shows in its
last 2 pixels on the menus), so the interrupt saves its registers in zero page (`zIrqA`, `zIrqX`, and `zIrqY` with
an absolute store to give one cycle back) instead of pushing them, which put the stores 3 cycles earlier than before.
`IRQ_PAD` `nop`s, for experiments, would move them 2 cycles later each; it is 0.
`$D022`/`$D023` are written after the stall, too late for a row's first line, so a row without multicolour cells (the
water between river lanes, the verges) writes the next row's colours as well, and the lane tops no longer flicker.

**Sprites and the interrupt.** A sprite takes memory cycles from the CPU at the end of every raster line it covers,
where the row interrupt stores, and the frog's sprites (21 lines tall) always cover two or three row boundaries. The
frog's DMA stops the CPU at about cycles 56–62. When it catches the first store, all three come after it, and the third
started at cycle 8 or 9 of the next line: with the frog on the river, a lane's first line in the row above's fine
scroll for a frame now and then. Zero page saving brought that to cycle 4–7, and in Enhanced play the third store is a
register that doesn't change at that boundary, so a late one does no harm. `IrqArmPlay`, called from `IrqArm` for the
next row, compares its character set and paper with the row above's and points the IRQ vector at one of three copies
of the interrupt's start: `IrqBgLast` (paper last: the water between river lanes, where the set and the scroll change),
`IrqCsLast` (character set last: the road, where a marking's paper and the scroll change; it has its own copy of the
marking loop, as a `jmp` to the shared one let the badline catch it before the loop ran) or `IrqHandler` ($D016 last:
the verges, where all three change, and every screen outside play). `SetRowMap` sets the vector back to `IrqHandler`
(`IrqDefault`). Checked with `make c64-flicker` and 300 more frames of play. The sprite Y of a text row is
`FIRST_TEXT_LINE` − 1 (`TEXT_TOP`): a sprite shows from the raster line after its Y.

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

**Built (V2, V3)** in `c64/src/sprites.s`, whose code and variables are in `HIDATA`:

| Routine         | Called from                     | Does                                                             |
|:----------------|:--------------------------------|:-----------------------------------------------------------------|
| `SprSetup`      | `SetRowMap`                     | Sprites off; in Enhanced play, colours and modes for the four    |
| `SprTarget`     | the end of `Present`            | Where the frog and fly are (`PosOf`), as just copied             |
| `SprTick`       | the frame interrupt             | Move the frog (ride, hop, jump), flap the fly, set the registers |
| `SetFrogGfxC64` | `SetFrogGfx` (`$0F20`, patched) | Enhanced play: the sprite frame and blank glyphs; else as before |
| `SplatDrawC64`  | `SetSplatGfx` (`$211B`)         | Enhanced play: the splat frame, glyphs blank again; `DrawFrog`   |

| Sprite | Shows        | Mode                                      |
|:-------|:-------------|:------------------------------------------|
| 0      | Frog outline | Hires black, 1 pixel up and left of 1     |
| 1      | Frog body    | Multicolour: green, light green, yellow   |
| 2      | Fly body     | Hires black                               |
| 3      | Fly wings    | Hires light grey, two frames              |

Sprite pointers are at `$83F8`–`$83FF`, after the VIC screen at `$8000`. Sprites are off everywhere but Enhanced play
(`SprSetup` from every `SetRowMap`). The splat replaces the frog for a death on the road and in the river alike; a
splash is not drawn. The row interrupts still land in the border with up to four sprites on the line: VICE shows no
seam or late colour change. The images load straight into `$8400`–`$877F` (segment `SPRDATA`), so the `.prg` now
carries them in its `$8000`–`$8FFF` stretch.

---

## Memory

The VIC shows bank 2 (`$8000`–`$BFFF`) during play. In banks 0 and 2 the VIC sees the character ROM at `$9000`–`$9FFF`,
not RAM, so sprites and character sets must go below `$9000` or in `$B800`–`$B9FF`. Code and tables can go anywhere
free.

| Region          | Size    | VIC sees it | Use                                  |
|:----------------|:--------|:------------|:-------------------------------------|
| `$76D9`–`$7F7D` | 2,213 B | No          | Used: V0–V7 hooks, code and BSS      |
| `$7F7E`–`$7FFF` | 130 B   | No          | Free                                 |
| `$8400`–`$877F` | 896 B   | Yes         | Used: 14 sprite blocks (V2, V3)      |
| `$8780`–`$87D8` | 89 B    | Yes         | `SPARE`: page frame glyphs (F3)      |
| `$87D9`–`$87FF` | 39 B    | Yes         | Free                                 |
| `$8800`–`$8FFF` | 2,048 B | Yes         | Used: multicolour play set (V1)      |
| `$9000`–`$9D72` | 3,443 B | No          | Used: V4 tables, font, sprites, F1, F3 |
| `$9D73`–`$9FFF` | 653 B   | No          | Spare (the Enhanced test code)       |
| `$B800`–`$B9FF` | 512 B   | Yes         | 8 sprite blocks: splat, splash, fly  |
| `$C800`–`$CAFF` | 768 B   | Bank 3 only | `C64FontCopy` (V7), filled at start  |
| `$CB00`–`$CFFF` | 1,280 B | Bank 3 only | Spare                                |
| `$D000`–`$DFFF` | 4,096 B | No          | Spare (RAM under I/O)                |
| `intro.rle`     | 6,739 B | No          | Spare after `UnpackPicture` has run  |

The BSS now ends at `$7F7D` (`c64/build/hopper.map`), leaving 130 bytes below `$8000`: new code and tables go in
`HIDATA`. Since V7, Enhanced data goes in the `HIGH` area at `$9000`–`$9FFF` (segment `HIDATA`, `c64/cfg/c64.cfg`). The
one-file `.prg` therefore also covers `$8000`–`$8FFF` (the `GAP` area, zeros), which is harmless because the VIC screen
and the multicolour set are written at run time. The `.prg` grew from 29 KB to 35 KB. The full set of changes needs
about 9.5 KB, so it still fits with the packed picture's space in reserve.

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

| Build                      | Script                                        | Captures                            |
|:---------------------------|:----------------------------------------------|:------------------------------------|
| `c64/build/test/`          | F1 on the Enhanced page, then Classic         | `instructions`, `hiscores`, `play`… |
| `c64/build/test-enhanced/` | `-D AUTOTEST_ENHANCED`: no F1, `Drive` steers | `enh-play`, `enh-road`, `enh-ride`… |

In the Enhanced build the frog is not steered by fixed key presses but by `Drive` (`c64/src/autotest.s`): from frame
3030, each frame it looks at the screen where an UP hop would land and hops only when that is safe. On the road it wants
the frog's columns clear in both rows of the lane, with 8 more columns towards the oncoming traffic and 2 on the other
side, unless traffic is within 4 columns of where the frog stands, when its own columns are enough; on the river it
wants a log or turtle under the frog's columns and one either side. It stops on the top river lane and rides it. So the
frog crosses the road, rides the turtles and logs and is carried off the end of the top log, and the captures cover
hops, riding and the edge death without key timings that a few cycles would break. The test code sits in `HIDATA`, out
of main memory.

`make c64-flicker` (`tools/c64_glitch.py`) captures consecutive frames of both test builds and fails on
one-frame glitches: the sound menu (a frame that differs from both neighbours, which match), the hi-score title (its two
double-height rows must move in the same frame) and Enhanced play (pixels on one line of a row only that the lanes'
sideways movement doesn't explain, over 236 frames including the frog crossing the road; and each road marking one whole
grey line that doesn't run on into the next). The captures run in parallel, about three minutes. It was checked against
the faults it looks for: the menu check fails with the row interrupt's stores late (`IRQ_PAD` 5), the title check with
the title sync off, the marking check with the paper put back a line late.

`tools/c64_screens.py` picks the program by the capture's name (`enh-*`). Classic captures are compared by eye with the
previous build's: the few cycles Enhanced adds to shared paths can move a capture by a frame. Still to check by hand in
VICE: real F1 and joystick presses, RUN/STOP
in a game, RESTORE, a frog home and a full sheet in Enhanced, and NTSC.

The key script leaves at least 25 frames between keys, and 80 between the sound menu and the controls menu: keys
injected at fixed frames are lost if they arrive before the screen that wants them, and the old 15-frame gaps broke as
soon as the code took a few more cycles. F1 goes in at frame 520, on the Enhanced page, and the game starts at 2600;
the Enhanced build, whose attract loop runs ahead (its page comes at once), starts its game at 2480.

---

## Planned Names

Names this section uses that don't exist yet. They are in `docs/tools/doc_names_ignore.txt` until the code exists, and
are removed from there as each one is written.

| Name            | Kind    | For                                        |
|:----------------|:--------|:-------------------------------------------|
| `rowSpace`      | Table   | Texture character for `$20`, per row       |
