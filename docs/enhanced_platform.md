# Hopper – Enhanced Platform Layer

How the C64 Enhanced version ([enhanced.md](enhanced.md)) fits into the platform layer
([platform_layer.md](platform_layer.md)): the version flag, the two hooks into the game, the changes to the raster
interrupt and to `Present`, the sprite driver, memory, frame time, disk hi-scores and testing. Only the version flag is
built so far; the rest is the plan. Names in this chapter that don't exist in `c64/src/` yet are listed under [Planned
Names](#planned-names).

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
2. Before `CheckMenuKeys`, `VersionKeys` looks for F1 or a new push of the joystick left or right. `ScanRomKey` reports
   F1 as `KEY_F1` (`$01`) + `$80` in `ROM_KEY`, like any other key, so a held F1 flips once. The joystick is
   edge-detected in `joyLR`.
3. On a flip it inverts `zEnhanced`, sets `titleSteps` back to 1, so the 15-second attract timer starts again, and falls
   into `DrawVersionLine`.

`DrawVersionLine` writes row 25 of the Oric screen (`SCREEN` + 1000) from `VersionText`: a cyan ink attribute and `[F1]
VERSION`, then each version name after a blue ink attribute. For the chosen one it makes the attribute white and sets
bit 7 of each character, the Oric's inverse, which the port shows as black on white. Because the row starts with a
character and has attributes further in, `ScanRow` sends it to `ParseRow` on its first copy, so it shows in the right
colours at once ([porting.md](porting.md#decisions)).

`make c64-smoke` presses F1 on the home screen (`c64/src/autotest.s`), and its `hiscores` and `version` captures show
both states. The game it then starts is in Classic.

---

## Hooks

Enhanced needs two changes to the game's bytes, both in routines that copy glyphs into `CHARSET` while the game runs. In
each, the routine's final `rts` (or the `nop`s before it) becomes a `jmp` to platform code that copies the matching
multicolour glyphs into the second character set and returns. Both are marked `; C64: (Enhanced)`.

| Hook                | In                         | Copies                                              |
|:--------------------|:---------------------------|:----------------------------------------------------|
| `SetTurtleFrameC64` | `SetTurtleFrame` (`$1800`) | The multicolour turtle frame for `turtle_frame`     |
| `SetFrogGfxC64`     | `SetFrogGfx` (`$0F20`)     | Blank frog glyphs, and the direction for the sprite |

`SetTurtleFrame` has three spare `nop`s before each of its `rts` (`$1810`, `$1826`, ...), enough for a `jmp`. Both hooks
do nothing when `zEnhanced` is clear. `make c64-diff` lists them.

Everything else reads the game's state without changing the game: `frog_row`, `frog_col`, `fly_on`, `fly_ptr`,
`lane_speeds`, the Oric screen and the AY register copy.

---

## Raster Interrupt

The interrupt already runs at the last line of each text row and sets `$D021` and `$D018` for the next row
([platform_layer.md](platform_layer.md#timing)). Enhanced adds, per row, when `zEnhanced` is set:

| Register | Per row from     | For                                         |
|:---------|:-----------------|:--------------------------------------------|
| `$D018`  | `rowCset`        | The multicolour set at `$8800` on play rows |
| `$D022`  | lane table       | V1 shade                                    |
| `$D023`  | lane table       | V1 highlight                                |
| `$D016`  | lane fine scroll | V4, and the F1 scroller                     |

and two one-line interrupts at the top of play rows 20 and 23 for the road markings (V6). Multicolour mode (`$D016` bit
4) is set for the whole screen in Enhanced. Cells with colour RAM below 8 stay hires, so text is unaffected.

The extra stores cost about 20 cycles a row. They must land before the beam reaches the next row's first character, as
the existing two do.

---

## Present and FastRow

| Change                 | Where     | Does                                                                      |
|:-----------------------|:----------|:--------------------------------------------------------------------------|
| Multicolour lane rows  | `FastRow` | Colour RAM = ink + 8 for the whole row on lane rows                       |
| Space translation (V5) | `Present` | `$20` to the row's texture character (`rowSpace`) on river and verge rows |
| Death flash            | `FastRow` | Lane rows fall back to hires (ink below 8) while the flash shows          |

The translation adds a table lookup per copied cell on the textured rows, about 4,000 cycles a frame. `Present` costs
about 10,000 today, in a game frame of about 30,000 that the Oric mostly spent waiting
([porting.md](porting.md#decisions)).

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

| Region          | Size    | VIC sees it | Use                                 |
|:----------------|:--------|:------------|:------------------------------------|
| `$7643`–`$7FFF` | 2,493 B | No          | Enhanced code                       |
| `$8400`–`$87FF` | 1,024 B | Yes         | 16 sprite blocks: frog              |
| `$8800`–`$8FFF` | 2,048 B | Yes         | Multicolour play character set      |
| `$9000`–`$9FFF` | 4,096 B | No          | SID tables, title tune, disk code   |
| `$B800`–`$B9FF` | 512 B   | Yes         | 8 sprite blocks: splat, splash, fly |
| `$C800`–`$CFFF` | 2,048 B | Bank 3 only | Spare                               |
| `$D000`–`$DFFF` | 4,096 B | No          | Spare (RAM under I/O)               |
| `intro.rle`     | 6,739 B | No          | Spare after `UnpackPicture` has run |

Today's BSS ends at `$7642` (`c64/build/hopper.map`). The full set of changes needs about 9.5 KB, so it fits with the
packed picture's space still in reserve.

---

## F2 – Hi-Scores Saved to Disk

The hi-score table at `$BA00` (`HISCORES`) is saved to the disk the game loaded from after a new name is entered, and
loaded at start-up if the file is there. Saving needs the KERNAL, which the port banks out, so it runs on a plain screen
after name entry: interrupts masked, KERNAL in, `SAVE`, KERNAL out, the raster interrupt back. The version choice is
saved in the same file. With no disk drive (a `.prg` run from a cartridge or a tape image), it says nothing and carries
on. About 0.4 KB.

---

## Building and Testing

There is one build, `make c64`, and the `.prg` holds both versions. `make c64-diff` shows the two hooks as the only game
bytes Enhanced adds.

| Check                | How                                                                    |
|:---------------------|:-----------------------------------------------------------------------|
| Classic unchanged    | `make c64-smoke` with `zEnhanced` clear: captures match today's        |
| Enhanced screens     | The same script with F1 pressed on the home screen first               |
| The switch           | Flip twice: the home screen comes back identical                       |
| Collisions unchanged | A scripted run hops into water and a car in both versions: same deaths |
| Sound                | By ear in VICE (headless VICE is silent)                               |

`c64/src/autotest.s` gains an F1 press in its key script for the Enhanced run, and `tools/c64_screens.py` gains the
Enhanced captures for [graphics.md](graphics.md).

---

## Planned Names

Names this section uses that don't exist yet. They are in `docs/tools/doc_names_ignore.txt` until the code exists, and
are removed from there as each one is written.

| Name                | Kind      | For                                        |
|:--------------------|:----------|:-------------------------------------------|
| `zEnhanced`         | Zero page | The version flag                           |
| `DrawVersionLine`   | Routine   | Row 25 of the home screen                  |
| `SetTurtleFrameC64` | Hook      | Multicolour turtle frames                  |
| `SetFrogGfxC64`     | Hook      | Frog glyphs and sprite direction           |
| `UpdateSprites`     | Routine   | Frog, fly and death sprites, the hop tween |
| `rowSpace`          | Table     | Texture character for `$20`, per row       |
