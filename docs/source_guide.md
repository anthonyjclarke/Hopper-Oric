# Hopper – Source Guide and Toolchain

This chapter is the map of the repository: where everything lives, what the builds need, what each `make` target does
and the rules that keep the source byte-identical to the tape.

---

## Repository Layout

| Path                  | What it is                                             |
|:----------------------|:-------------------------------------------------------|
| `original/HOPPER.TAP` | The original tape image: the reference, never edited   |
| `src/hopper.s`        | The game, reconstructed as ca65 source                 |
| `src/oric.inc`        | Oric hardware: the VIA, the screen and character sets  |
| `src/vars.inc`        | Variables: zero page, page 4, fixed screen locations   |
| `hopper.cfg`          | ld65 config for the Oric: TAP header, then the program |
| `c64/src/`            | The C64 port: the patched game and the platform layer  |
| `c64/cfg/c64.cfg`     | ld65 config for the C64 `.prg`                         |
| `tools/`              | Disassembler, annotations, 6502 core, C64 tools        |
| `docs/`               | The chapters, images, recordings and the handbook      |
| `Makefile`            | The Oric and C64 builds                                |
| `justfile`            | The documentation recipes                              |

---

## Toolchain

| Tool                           | Use                                                |
|:-------------------------------|:---------------------------------------------------|
| cc65 (`ca65`, `ld65`)          | Assemble and link both builds                      |
| Python 3                       | The disassembler, checks and capture tools         |
| Pillow (Homebrew `python3.14`) | The C64 start-up picture and the figures           |
| Auric                          | Oric-1 emulation (`make run`), needs `basic10.rom` |
| VICE (`x64sc`, `c1541`)        | C64 emulation, captures, the disk image            |
| Node.js 20+                    | The handbook                                       |

---

## Build Targets

| Target             | Does                                                                                     |
|:-------------------|:-----------------------------------------------------------------------------------------|
| `make`             | `build/HOPPER.TAP`, with a listing, map and labels                                       |
| `make verify`      | Builds, then checks the tape is byte-identical to `original/HOPPER.TAP`                  |
| `make run`         | Runs it in Auric, Oric-1 mode                                                            |
| `make debug`       | The same with Auric's debugger                                                           |
| `make regen`       | Regenerates `src/hopper.s` from the tape and `tools/annotations.py`: discards hand edits |
| `make c64`         | `c64/build/hopper.prg`                                                                   |
| `make c64-d64`     | `c64/build/hopper.d64`                                                                   |
| `make c64-run`     | Runs the C64 build in VICE with the labels loaded                                        |
| `make c64-diff`    | Every byte of the C64 game image that differs from the Oric program                      |
| `make c64-smoke`   | Builds the scripted test `.prg` and takes VICE captures into `c64/build/`                |
| `make c64-flicker` | Checks the test builds for one-frame display glitches (`tools/c64_glitch.py`)            |
| `make c64-sound`   | Records the tunes and effects into `docs/sound/` (`tools/c64_sound.py`, real time)       |
| `make c64-intro`   | Packs the C64 start-up picture `c64/art/intro.png` into `c64/src/intro.rle`              |
| `make c64-font`    | The Enhanced Oric-style font (`c64/src/oricfont.inc`)                                    |
| `make c64-sprites` | The Enhanced frog and fly sprites (`c64/src/sprites.inc`, from the Oric labels)          |
| `make clean`       | Removes `build/` (the Oric build)                                                        |

Auric is expected at `~/PlatformIO/Projects/Auric` (`build/src/auric`), and `make run AURIC_DIR=/path/to/Auric` points
elsewhere. The game runs in **Oric-1 mode** because it uses Oric-1 ROM locations, which the Atmos ROM keeps elsewhere
([architecture.md](architecture.md#oric-1-rom-locations)). The ROM files are covered in [oric_specs.md](oric_specs.md).
In VS Code, **Terminal → Run Build Task** (⇧⌘B) builds, and the verify and Auric tasks are under **Terminal → Run Task**
(`.vscode/`, with the recommended *ca65* extension for highlighting).

---

## How the Source Was Reconstructed

`tools/gen_source.py` traces the code by recursive descent from its entry points: the tape entry `$0500`, the RESET
handler `$0560` that the game installs itself, and five routines nothing calls. Whatever isn't reached as code is
treated as data. `tools/annotations.py` holds the names, comments and data layouts, and the character graphics are
printed as pixel art in the comments. `src/hopper.s` is now the master and is edited by hand, so `make regen` would
overwrite those edits.

---

## Conventions

- **Every byte at its address.** Pointers are built from immediate bytes (`lda #$BB`), so the code is not relocatable.
  Each instruction keeps its original address in the comment column (`; 0FE0`), and `make verify` must pass.
- **`a:` prefixes.** Absolute-mode instructions on zero-page addresses keep their `a:` prefix, or ca65 shortens them and
  the output differs.
- **Original bugs stay.** `bcs $0FD6` and `jmp $296D` land inside instructions; the source keeps them with labels like
  `BadTarget_296D` ([quirks.md](quirks.md)).
- **TAP header.** The `TAPEHDR` segment writes it; its end address is inclusive.
- **C64 patches.** `c64/src/hopper.s` is a copy of `src/hopper.s` patched in place: every patch fits the bytes it
  replaces (padded with `nop`) and carries `; C64:`. Changes to the Oric source are ported to it by hand
  ([porting.md](porting.md)).
- **Platform code.** C64 platform code keeps to its own zero page (`$60`–`$CF`), never masks interrupts for long, and
  uses `IdleParse` only in waits that are not counted ([platform_layer.md](platform_layer.md)).

---

## Tools

| Tool                         | Does                                                                                                |
|:-----------------------------|:----------------------------------------------------------------------------------------------------|
| `tools/gen_source.py`        | The disassembler that generated `src/hopper.s`                                                      |
| `tools/annotations.py`       | Its names, comments and data layouts                                                                |
| `tools/m6502.py`             | Its 6502 opcode table                                                                               |
| `tools/dis_range.py`         | A quick linear disassembly of an address range                                                      |
| `tools/cpu6502.py`           | A 6502 core (from the [Light Cycle repository](https://github.com/anthonyjclarke/Light-Cycle-Oric)) |
| `tools/trace6502.py`         | An execution tracer on that core                                                                    |
| `tools/oric_screens.py`      | Runs the game's drawing routines and prints the Oric screens                                        |
| `tools/c64_diff.py`          | The C64 game bytes that differ from the Oric program, by routine                                    |
| `tools/c64_screens.py`       | Headless VICE captures of the scripted C64 run                                                      |
| `tools/c64_glitch.py`        | One-frame display glitches in consecutive VICE captures (`make c64-flicker`)                        |
| `tools/c64_sound.py`         | The docs' recordings from the sound build, cut by event (`make c64-sound`)                          |
| `tools/oric_style_font.py`   | The Enhanced Oric-style font (`make c64-font`)                                                      |
| `tools/frog_sprites.py`      | The Enhanced frog and fly sprites (`make c64-sprites`)                                              |
| `tools/instructions_page.py` | The Enhanced instructions page (`c64/src/instrpage.inc`; run by hand)                               |
| `tools/make_intro.py`        | The C64 start-up picture: packs its master; `--from-scans` redraws it from the cover scans          |
| `docs/tools/`                | The handbook generator and the figure tools ([html_documentation.md](html_documentation.md))        |
