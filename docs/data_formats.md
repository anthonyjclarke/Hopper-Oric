# Hopper – Data Formats

Every table the game reads, with its label and Oric address, read from `src/hopper.s`. The C64 port keeps them all at
the same addresses; the few it changes are marked **C64**.

---

## Characters

Each character is 8 bytes, top row first; bits 5–0 are the six pixels, bit 5 on the left (bits 7–6 are unused in the
graphics). **C64:** every glyph byte is widened to 8 pixels at assembly time by `W6`, which doubles the two middle
pixels: `W6(v) = ((v & $38) << 2) | ((v & $0C) << 1) | (v & $07)`.

| Label           | Address | Size             | Copied to                           | By               |
|:----------------|:--------|:-----------------|:------------------------------------|:-----------------|
| `udg_graphics`  | `$0600` | 37 characters    | `$5B`–`$7F`                         | `InitGame`       |
| `udg_symbols`   | `$0728` | 10 characters    | `$21`–`$2A`                         | `InitGame`       |
| `frog_gfx`      | `$0E00` | 4 × 4 characters | `$3A`–`$3D` (up, down, left, right) | `SetFrogGfx`     |
| `home_gfx`      | `$1540` | 4 characters     | `$2B`, `$2C`, `$2E`, `$2F`          | `DrawHomeFrog`   |
| `turtle_frames` | `$1900` | 7 × 6 characters | `$6E`–`$73`                         | `SetTurtleFrame` |
| `splat_gfx`     | `$2207` | 4 characters     | `$3A`–`$3D`                         | `SetSplatGfx`    |

The frog's four characters sit at screen offsets `frog_offsets` (0, 1, 40, 41): top-left, top-right, bottom-left,
bottom-right. The `udg_graphics` copy runs on for 512 bytes into the tables after it, which land harmlessly in
characters past `$7F`.

---

## The Screen

| Label             | Address | Format                                                                                  |
|:------------------|:--------|:----------------------------------------------------------------------------------------|
| `row_colours`     | `$07C8` | 28 pairs (ink `$00`–`$07`, paper `$10`–`$17`) for columns 0–1 of each row               |
| `home_wall_cols`  | `$07A0` | Columns of the hedge (char `$7F`) on rows 1–2, `$FF` ends                               |
| `lane_init`       | `$0850` | Rows 7, 8, 10, 11, 13, 14 at the start: 38 characters each (columns 2–39)               |
| `status_template` | `$0778` | The status line: `SCORE      00`, ink 1, `TIME 99`, ink 4, `LIVES 5`, ink 5, `SHEET  1` |
| `status_save`     | `$2FD7` | Copy of the status line (39 bytes) while the screen is redrawn                          |
| `title_bar`       | `$1A50` | The double-height title bar of rows 0–1                                                 |
| `game_over_text`  | `$1AB0` | GAME OVER, double height                                                                |

The row colours give the river a blue paper (rows 0–14), the middle bank yellow (15–16), the road black (17–24) with
white markings on rows 19 and 22, the start bank green (25–26) and the status line white (27). Inks pick out the lanes:
red turtles (7–8), yellow logs (10–11), red logs (13–14), and the vehicles' colours on the road.

The status line is written from column 2 of row 27. Its fixed fields are found by offset: `SCORE_DIGITS` (six digits at
column 8, then a fixed `0`), `TIME_DIGITS` (column 21), `LIVES_DIGIT` (column 30) and `SHEET_DIGITS` (column 38). Scores
are kept as ASCII digits on the screen and `AddScore` adds to them in place, carrying left.

---

## Lanes

| Label              | Address | Format                                                         |
|:-------------------|:--------|:---------------------------------------------------------------|
| `lane_speeds_init` | `$0940` | Frames between moves, lanes 0–6: `$0B,$05,$07,$05,$07,$0D,$06` |
| `lane_speeds`      | `$09C0` | The working copy; lowered as sheets are cleared                |
| `lane_timer`       | `$40`   | Seven counters, one per lane                                   |

Lane 0 is row 23 and lane 6 row 4: 0–2 are the road (rows 23, 20, 17), 3–6 the river (rows 13, 10, 7, 4). The road lanes
and row 4 are fed by spawners (`SpawnRow23`, `SpawnRow20`, `SpawnRow17`, `SpawnRow4`), each with four bytes in page 4:
the next character of the object to place (`r23_state`, 0 = a gap), a repeat count for its middle part (`r23_len`), a
first-gap flag and a gap countdown, with minimum gaps in `r17_gap_min` … The other river lanes only scroll what
`lane_init` put there, wrapping round.

---

## Keys

| Label       | Address | Format                                                          |
|:------------|:--------|:----------------------------------------------------------------|
| `key_rows`  | `$0EE0` | Five keys (left, right, down, up, pause): keyboard row select   |
| `key_cols`  | `$0EE5` | The column mask of each key                                     |
| `key_bits`  | `$0EEA` | The bit each key sets in `key_state`: `$20, $10, $08, $04, $80` |
| `keys_set1` | `$16C0` | 15 bytes copied over the three tables for control choice 1      |
| `keys_set2` | `$16D0` | The same for choice 2                                           |

Note the order: the third key is **down** (`$08`) and the fourth **up** (`$04`), whatever the comment in the original
listing suggested; `KeysToDir` reads them that way. **C64:** the rows hold the CIA1 port A column select and the columns
the port B row mask; choice 1 is Z X K M, and choice 2 is filled by `RedefineKeys` (key bits included, since the Oric's
choice 2 orders its keys up, down, left, right), which also writes the four key names into the immediate operands
`key_name_left` … that `ControlsMenu` stores into the instructions.

---

## Text

| Label           | Address | Format                                                                      |
|:----------------|:--------|:----------------------------------------------------------------------------|
| `controls_text` | `$1898` | The controls menu: characters and attributes, `$0D` = next row, `$FF` = end |
| `credits_text`  | `$2400` | The credits and instructions, four characters per hop                       |
| `credits_path`  | `$26C8` | The hop direction for each step (2 down, 3 left, 4 right), `$FF` = end      |
| `menu_prompt`   | `$1CB0` | "PRESS [1] FOR A NEW GAME" / "[2] FOR INSTRUCTONS" (sic)                    |

`CreditsIntro` moves a frog along `credits_path` and leaves four characters of `credits_text` behind it at each hop, two
on the upper row and two on the lower, so the text is stored in pairs of pairs. `ControlsMenu` writes the chosen key
names into it at fixed offsets.

---

## Hi-Scores

| Label          | Address | Format                                                                    |
|:---------------|:--------|:--------------------------------------------------------------------------|
| `hiscore_init` | `$22FF` | The default table; `ColdStart` copies bytes 1–255 to `HISCORES` (`$BA00`) |
| `HISCORES`     | `$BA00` | Eight entries of 28 bytes                                                 |
| `hiscore_inks` | `$0800` | The ink of each table row                                                 |

An entry is an 8-character score (right-aligned ASCII digits, spaces in front), then the name, ending `$0D`, padded with
spaces to 28 bytes. `CheckHiScore` compares a score digit by digit with each entry, shifts the lower entries down and
reads a name from `ROM_KEY`. The default table holds a ninth entry (200) that is copied but never shown
([quirks.md](quirks.md)).

---

## Sound

| Label             | Address | Format                                                          |
|:------------------|:--------|:----------------------------------------------------------------|
| `note_periods`    | `$0810` | 12 AY tone periods (low byte) for one octave                    |
| `ay_game_regs`    | `$0820` | AY registers 0–13 at the start of play (mixer `$F8`, volumes 2) |
| `ay_quiet_regs`   | `$0980` | AY registers 0–13, all quiet                                    |
| `tune_ptrs`       | `$0830` | Addresses of the four in-game tunes                             |
| `tune_params`     | `$0840` | Per tune: tempo, length in bytes                                |
| `tune0` …         | `$2C00` | Pairs: note (1–12, 0 = rest), octave × 16 + length              |
| `sheet_tune`      | `$3000` | 29 steps of three bytes, one note per channel                   |
| `sheet_tune_lens` | `$3058` | The length of each sheet-tune step                              |
| `hop_pitches`     | `$1E9E` | Tone periods for the hop sound, steps 2–10                      |
| `bonus_pitches`   | `$1E53` | Tone periods for the fly-bonus beeps                            |
| `timer2_reload`   | `$09A0` | `$606B`: the VIA timer 2 period, the game's time base           |

`MusicTick` advances before it reads, so the first pair of each tune is never played.
