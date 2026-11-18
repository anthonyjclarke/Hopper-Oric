# HOPPER – Oric-1 reconstruction

HOPPER is a Frogger-style game for the Oric-1, published by Personal Software
Services (P.S.S.), Coventry. The in-game credits name the author as A.J. Clarke.
The game's entry on oric.org: [Hopper](https://www.oric.org/software/hopper-1427.html).

This repository rebuilds the game from assembly source. `make verify` assembles
`src/hopper.s` and checks that the result is **byte-identical** to the original
tape image in `original/HOPPER.TAP`.

---

## Layout

| Path                    | What it is                                    |
|:------------------------|:----------------------------------------------|
| `original/HOPPER.TAP`   | The original tape image (reference)           |
| `src/hopper.s`          | Full game source (ca65)                       |
| `src/oric.inc`          | Oric hardware: VIA, screen, character sets    |
| `src/vars.inc`          | Game variables: zero page and page 4          |
| `hopper.cfg`            | ld65 config: writes TAP header + program      |
| `Makefile`              | `make`, `make verify`, `make run`, `make debug` |
| `tools/gen_source.py`   | Disassembler that generated `src/hopper.s`    |
| `tools/annotations.py`  | Names, comments and data layout it uses       |
| `tools/dis_range.py`    | Quick linear disassembly of an address range  |
| `.vscode/`              | Build/verify/run tasks and ca65 highlighting  |
| `c64/`                  | The Commodore 64 port                         |
| `docs/`                 | Documentation and the `HOPPER.html` handbook  |
| `justfile`              | Documentation recipes (`just docs`)           |

---

## Commodore 64 version

`c64/` holds a C64 port: the Oric code itself, with only the hardware replaced (the screen, sound chip, keyboard and
timers), running on a small platform layer. See [docs/porting.md](docs/porting.md), and
[docs/HOPPER.html](docs/HOPPER.html), the full documentation in one offline page ([docs/README.md](docs/README.md)
lists the chapters).

```bash
make c64
```

```bash
make c64-run
```

The output is `c64/build/hopper.prg` (`make c64-d64` for a disk image). It opens on a picture made from the PSS
cassette inlay (any key or fire skips it), which comes back in the attract loop: picture, credits and instructions,
hi-scores (1 or fire on the picture starts a game). Keys: choice 1 is Z, X, K, M (left, right, up, down); choice 2 asks for
your own four keys; P pauses; joystick port 2 works with either. RESTORE is the Oric's RESET button.

This is the **C64 Remix**: it plays as the Oric original except for a short list of deliberate changes (Redefine keys,
the Z X K M key set, the joystick, the start-up picture and attract loop, the frog reaching the outermost columns, and
a fix for a hang the Oric code causes on a C64). [docs/remix.md](docs/remix.md) documents each one.

---

## Building

You need the cc65 toolchain (`ca65`, `ld65`) and Python 3.

```bash
brew install cc65
```

```bash
make verify
```

The output is `build/HOPPER.TAP`, plus `build/hopper.lst` (listing),
`build/hopper.map` and `build/hopper.lbl` (labels, handy in a debugger).

In VS Code, **Terminal → Run Build Task** (⇧⌘B) builds. The other tasks
(*Verify against original*, *Run in Auric (Oric-1)*, *Run in Auric with
debugger*) are under **Terminal → Run Task**. Install the recommended
*ca65* extension for syntax highlighting.

---

## Running in Auric

[Auric](https://github.com/pugo/Auric) is built from source in
`~/PlatformIO/Projects/Auric` (`build/src/auric`). It needs the Oric ROM images,
which are not distributed with it. Put them in `~/PlatformIO/Projects/Auric/ROMS/`:

| File           | Needed for                  |
|:---------------|:----------------------------|
| `basic10.rom`  | Oric-1 mode – HOPPER        |
| `basic11b.rom` | Atmos mode (the default)    |
| `microdis.rom` | Microdisc drive (optional)  |

`ROMS/README_ROMS.md` in the Auric folder lists the expected SHA1 of each.

```bash
make run
```

`make run` starts Auric in **Oric-1 mode** with the tape autoloading. `make
debug` does the same with Auric's debugger open; the addresses in the comment
column of `src/hopper.s` and `build/hopper.lbl` match what it shows. If Auric
lives elsewhere: `make run AURIC_DIR=/path/to/Auric`.

Use Oric-1 mode. The game relies on Oric-1 ROM locations (the RESET vector at
`$022B`, the key buffer at `$02DF`, the cursor pointer at `$12`). The Atmos ROM
keeps these elsewhere, so the menus may not respond there.

### Playing

At the sound menu press 1, 2 or 3, then pick a key set:

| Set | Left | Right | Up  | Down |
|:----|:-----|:------|:----|:-----|
| 1   | Z    | X     | '   | /    |
| 2   | ,    | .     | A   | Z    |

P pauses. In attract mode, 1 starts a game and 2 shows the instructions.

---

## How the source was reconstructed

The TAP file holds one machine-code block, `$0500`–`$30D4`, set to autorun.
`tools/gen_source.py` traces the code by recursive descent from the entry
points: the tape entry `$0500` and the RESET handler `$0560`, which the game
installs itself. It also starts from five routines nothing calls. Whatever
isn't reached as code is data. `tools/annotations.py` provides the names,
comments and data formats. Character graphics are printed as pixel art in the
comments.

Every instruction keeps its original address in the comment column. Two
original quirks needed special handling to stay byte-identical (see below).
Instructions that used absolute addressing on a zero-page address are written
with `a:` so ca65 doesn't shorten them.

### Editing workflow

* **Now:** `src/hopper.s` is the master. Edit it directly and run `make
  verify` to check whether you have changed the output.
* `make regen` rewrites `src/hopper.s` from the original TAP and
  `tools/annotations.py`. This is useful while names and comments are still
  being improved, but it **discards hand edits** to `hopper.s`.
* The source is not relocatable yet. Some pointers are built from immediate
  bytes (`lda #$B5` …), so moving code changes behaviour. Keep addresses fixed
  for a faithful build.

---

## Things found in the original

* **Branch into an instruction (`$0FEE`).** `CheckFrogBounds` branches to
  `$0FD6`, one byte into an `inc` instruction. The byte there, `$12`, is an
  illegal opcode that locks up an NMOS 6502. It only runs if the frog row
  reaches 10, which the game should never allow.
* **Jump into an instruction (`$1BE6`).** After the hi-score table, the code
  jumps to `$296D`, one byte into `jsr ClearScreen`. It runs `ORA #$20 / LDY
  #$1A` instead, which is harmless, and skips the screen clear.
* **Hidden exit at `$A800`.** If a certain key combination is held while RESET
  is pressed, the RESET handler jumps to `$A800`. Nothing is there on a normal
  machine. It was probably the author's development monitor.
* **Hi-scores live in character-set RAM.** The table is kept at `$BA00`, in the
  alternate character set, which this game doesn't use. A RESET restarts the
  game at `WarmStart` without reloading it, so hi-scores survive.
* **Leftovers.** There are five routines nothing calls, NOP padding where code
  was removed, and memory fill patterns (`$FF`, `$55`, `$EA`) between routines.
  Most routines start on round addresses, which suggests the game was
  hand-assembled with a monitor.
* **Typo:** the attract screen says "INSTRUCTONS".

---

## Memory map

| Address         | Contents                                      |
|:----------------|:----------------------------------------------|
| `$0400`–`$0462` | Game variables (`vars.inc`)                   |
| `$0500`–`$05CB` | Start-up, RESET handler, pause                |
| `$0600`–`$0947` | Character graphics, colours, lane data, sound |
| `$0948`–`$2206` | Game code with small tables between routines  |
| `$22FF`–`$23FE` | Default hi-score table                        |
| `$2400`–`$2771` | Credits/instructions text and hop path        |
| `$2778`–`$2BF9` | Attract mode, fly, music player               |
| `$2C00`–`$2F29` | In-game tunes and the sound menu text         |
| `$2F30`–`$30AB` | Controls menu, sheet tune                     |
| `$3100`–`$33FF` | Saved ROM font (written at run time)          |
| `$B400`–`$B7FF` | Character set (partly redefined)              |
| `$BA00`–`$BAFF` | Hi-score table (in alternate-charset RAM)     |
| `$BB80`–`$BFDF` | Text screen; row 27 is the status line        |
