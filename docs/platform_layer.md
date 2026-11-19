# Hopper – The C64 Platform Layer

The C64 code under the patched game, module by module, read from `c64/src/`. Why it is built this way is in
[porting.md](porting.md); this chapter is the reference for each routine.

---

## Modules

| File                | Holds                                                                |
|:--------------------|:---------------------------------------------------------------------|
| `basic_stub.s`      | `SYS 2061` and a `jmp Start`                                         |
| `hopper.s`          | The game, patched in place (segment `GAME`, run at `$0500`)          |
| `platform.s`        | `Start` and the hooks the patched game calls                         |
| `zp.s`              | The platform's zero page, `$60`–`$8F`                                |
| `timing.s`          | The CIA clock, the waits, the raster interrupt                       |
| `video.s`           | Showing the Oric screen on the VIC-II                                |
| `input.s`           | Keyboard, joystick, the ROM key buffer, redefining keys              |
| `sound.s`           | The AY on the SID                                                    |
| `intro.s`           | The start-up picture                                                 |
| `enhanced.s`        | The C64 Enhanced look ([enhanced_platform.md](enhanced_platform.md)) |
| `autotest.s`        | Scripted keys for the headless test build only                       |
| `hw.inc`, `c64.inc` | C64 registers, the layout constants, hooks, row maps, timings        |

---

## Start-Up and Hooks

`Start` masks interrupts, banks out BASIC and the KERNAL, moves the game image from behind the BASIC stub down to
`$0500`, clears the BSS, puts an `RTI` at `NMI_VECTOR`, unpacks the start-up picture and shows it (`UnpackPicture`,
`ShowPicture`), then runs `InitVideo`, `InitInput`, `InitSound` and `InitTiming` and jumps to `ColdStart`.

| Hook              | Patched in at            | Does                                                                              |
|:------------------|:-------------------------|:----------------------------------------------------------------------------------|
| `InitGameC64`     | `$1001` (`NewGame`)      | ROM interrupt off, the game row map, then `InitGame`                              |
| `RomIrqOn`        | `$20A0` (`InitTimers`)   | The ROM interrupt's jobs back on                                                  |
| `ReadRomKey`      | the key waits            | Draw now and then (`Idle`), then `lda ROM_KEY`; F1 flips (`TakeF1`)               |
| `ReadMenuKey`     | `$2F61` (`ControlsMenu`) | The same, parsing rows between draws (`IdleParse`)                                |
| `SoundMenuC64`    | `$0550`                  | The menu row map, then `SoundMenu`                                                |
| `CreditsIntroC64` | `$2953`                  | The credits row map, then `CreditsIntro`                                          |
| `HiscoreTableC64` | `$2971`, `$1B51`, `$1BD2` | The hi-score row map, the title timer, then `DrawHiScoreTable`                   |
| `TitleTickC64`    | `$2938` (`TitleScroll`)  | `CheckMenuKeys`; after `TITLE_STEPS` steps the picture, then the attract loop     |
| `VersionKeys`     | from `TitleTickC64`      | F1 or joystick left/right: flip `zEnhanced`, restart the timer                    |
| `TakeF1`          | from `Present`           | F1 on any front-end screen: take it out of `ROM_KEY`, then `FlipVersion`          |
| `FlipVersion`     | `TakeF1`, `VersionKeys`  | Invert `zEnhanced`, change the font (`SetFontC64`), set `versionReq`              |
| `QuitGameC64`     | from `ReadKeysC64`       | RUN/STOP in a game: reset the stack, `SilenceAll`, then `GameOver`                |
| `DrawVersionLine` | from `TitleTickC64`      | The version line, row 25 of the hi-score screen ([enhanced.md](enhanced.md))      |
| `EraseFlyC64`     | `$2A1B` (`EraseFly`)     | Erase the fly; with no fly, write to `tmp0` / `key_state`, not the 6510 port      |
| `RedefineKeys`    | `$2F91` (`ControlsMenu`) | Choice 2: ask for the four keys                                                   |

---

## Timing

CIA2's timers A and B are chained into a free-running 24-bit clock of CPU cycles; `ReadClock` reads it into `zNow`. One
C64 cycle stands for one Oric microsecond.

| Routine         | Does                                                                                                                                                                                                                |
|:----------------|:--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `InitTiming`    | PAL or NTSC, the clock, the IRQ and NMI vectors, the raster interrupt                                                                                                                                               |
| `WaitCycles`    | Wait `zWait` cycles to a deadline, carrying any overrun (`zDebt`) into the next wait; meanwhile `Present` at most every `PRESENT_GAP` cycles, `ParseNextRow` when `PARSE_COST` is left, and the hook in `zWaitHook` |
| `DelayXC64`     | The Oric's `DelayX`: X × `DELAYX_UNIT` cycles                                                                                                                                                                       |
| `FrameDelayC64` | The Oric's `FrameDelay`: `game_delay` × `FRAMEDELAY_UNIT`, with `ServiceTimer` as its hook                                                                                                                          |
| `T2Check`       | Stands in for the VIA timer 2 flag: true once per `T2_PERIOD` cycles                                                                                                                                                |
| `AttractWait`   | The credits' wait, by the clock, with `CheckMenuKeys` as the hook                                                                                                                                                   |
| `Idle`          | For key waits: `Present` every `IDLE_TICKS` frames                                                                                                                                                                  |
| `IdleParse`     | As `Idle`, with a `ParseNextRow` in between                                                                                                                                                                         |
| `IrqHandler`    | The raster interrupt (below)                                                                                                                                                                                        |
| `NmiEntry`      | RESTORE: `jmp NMI_VECTOR`, the Oric's RESET path                                                                                                                                                                    |

**The raster interrupt.** An interrupt at the last line of each text row (`RowLine`) sets `$D016`, `$D021` and `$D018`
for the next row from `rowCtl2`, `rowPaper` and `rowCset` as they are at that moment, so a row that `Present` recolours
or turns double height mid-frame is shown right in that frame. `rowCtl2` is `$08` but in Enhanced play, where it adds
multicolour and the lanes' fine scroll (V4, [enhanced_platform.md](enhanced_platform.md#raster-interrupt)). The frame interrupt at line
`FRAME_IRQ_LINE` sets row 0's, counts `zTick`, flips the blink phase every 16 frames, and runs the Oric ROM interrupt's
jobs while `zRomIrq` is set: `ScanRomKey` and `CursorBlink`.

---

## Video

The game draws on its Oric screen at `$BB80`; the VIC shows a text screen at `$8000` in bank 2, with the game's
character set at `$B000` and two double-height sets at `$A000` and `$A800`.

| Routine           | Does                                                                                                                                        |
|:------------------|:--------------------------------------------------------------------------------------------------------------------------------------------|
| `InitVideo`       | Bank 2, text mode, a blank screen, the font, the menu row map                                                                               |
| `BuildFont`       | ASCII `$20`–`$7F` at `CHARSET` from the C64 character ROM (`AsciiToScreen`, `CustomGlyphs`), as the Oric ROM would have left it             |
| `RefreshCharsets` | Rebuild the inverse half and the double-height sets after the game changes glyphs                                                           |
| `SetRowMap`       | Which 25 of the 28 Oric rows to show (`MapMenu`, `MapCredits`, `MapHiscore`, `MapGame`); patches `CopyRows` and marks every row for parsing |
| `Present`         | Copy the 25 rows: simple rows by unrolled code (columns 2–39), complex rows through `ParseRow`                                              |
| `ScanRow`         | After a simple row that starts with a character is copied: any attribute in columns 2–39 sends it to `ParseRow` at once                     |
| `ParseRow`        | One row cell by cell: serial attributes to colour RAM, other papers as inverse cells, double height to a character set, blink, inverse      |
| `FastRow`         | Recolour a simple row when its column 0 or 1 changes, and draw those two cells                                                              |
| `ParseNextRow`    | Parse the next row round-robin, finding rows that gained attributes                                                                         |

The row maps hide the three rows each screen leaves blank: menus 9–11, credits 4, 8 and 9, hi-scores 3, 20 and 21, play
3, 19 and 22.

---

## Input

| Routine        | Does                                                                                                        |
|:---------------|:------------------------------------------------------------------------------------------------------------|
| `InitInput`    | CIA1 port A out (columns), port B in (rows)                                                                 |
| `ReadKeysC64`  | The Oric's `ReadKeys`: `key_state` from `key_rows` / `key_cols` / `key_bits`, plus joystick 2 (`JoyToKeys`); in a game, RUN/STOP goes to `QuitGameC64` |
| `ScanRomKey`   | From the frame interrupt: a newly pressed key into `ROM_KEY` as ASCII + `$80` (`KeyAscii`); F1 is `KEY_F1`  |
| `RedefineKeys` | Controls choice 2: prompts under the menu, fills `keys_set2` and the key names                              |
| `WaitNoKeys`   | Before each prompt: wait until no key has been down for `RELEASE_FRAMES` frames                             |

---

## Sound

| Routine      | Does                                                                               |
|:-------------|:-----------------------------------------------------------------------------------|
| `InitSound`  | SID volume up, voices off                                                          |
| `AyWriteC64` | The Oric's `AYWrite`: store the register in `ayRegs`, update the voices it affects |
| `WaveOf`     | A voice's waveform from the AY mixer: pulse, noise or off                          |
| `SetWave`    | Write the waveform and gate                                                        |
| `SetLevel`   | The AY volume as the voice's sustain level, retriggering when it rises             |
| `SetFreq`    | The AY period as a SID frequency, by `Divide`                                      |

---

## The Start-Up Picture

| Routine         | Does                                                                                     |
|:----------------|:-----------------------------------------------------------------------------------------|
| `UnpackPicture` | Unpack `intro.rle` into bank 3: bitmap `$E000`, colours `$C000`, colour RAM copy `$C400` |
| `ShowPicture`   | Show it with interrupts masked for 8 s or until a key or fire; returns 1 for 1 or fire   |
