# Hopper – Source Guide and Toolchain

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
| `docs/`               | These chapters, the images and the handbook            |
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

| Target           | Does                                                                                    |
|:-----------------|:----------------------------------------------------------------------------------------|
| `make`           | `build/HOPPER.TAP`, with a listing, map and labels                                      |
| `make verify`    | Build, then check the tape is byte-identical to `original/HOPPER.TAP`                   |
| `make run`       | Run in Auric, Oric-1 mode                                                               |
| `make debug`     | The same with Auric's debugger                                                          |
| `make regen`     | Regenerate `src/hopper.s` from the tape and `tools/annotations.py`: discards hand edits |
| `make c64`       | `c64/build/hopper.prg`                                                                  |
| `make c64-d64`   | `c64/build/hopper.d64`                                                                  |
| `make c64-run`   | Run the C64 build in VICE with the labels loaded                                        |
| `make c64-diff`  | Every byte of the C64 game image that differs from the Oric program                     |
| `make c64-smoke` | Build the scripted test `.prg` and take VICE captures into `c64/build/`                 |
| `make c64-intro` | Redraw the C64 start-up picture (`c64/src/intro.rle`)                                   |

---

## How the Source Was Reconstructed

`tools/gen_source.py` traces the code by recursive descent from its entry points: the tape entry `$0500`, the RESET
handler `$0560` that the game installs itself, and five routines nothing calls. Whatever is not reached as code is data.
`tools/annotations.py` holds the names, comments and data layouts; character graphics are printed as pixel art in the
comments. `src/hopper.s` is now the master and is edited by hand; `make regen` would overwrite it.

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
- **Platform code.** C64 code follows the user's house rules: platform zero page `$60`–`$8F`, no long `sei`, and
  `IdleParse` only in waits that are not counted ([platform_layer.md](platform_layer.md)).

---

## Tools

| Tool                    | Does                                                                                         |
|:------------------------|:---------------------------------------------------------------------------------------------|
| `tools/gen_source.py`   | The disassembler that generated `src/hopper.s`                                               |
| `tools/annotations.py`  | Its names, comments and data layouts                                                         |
| `tools/m6502.py`        | Its 6502 opcode table                                                                        |
| `tools/dis_range.py`    | A quick linear disassembly of an address range                                               |
| `tools/cpu6502.py`      | A 6502 core (from the Light Cycle repository)                                                |
| `tools/trace6502.py`    | An execution tracer on that core                                                             |
| `tools/oric_screens.py` | Runs the game's drawing routines and prints the Oric screens                                 |
| `tools/c64_diff.py`     | The C64 game bytes that differ from the Oric program, by routine                             |
| `tools/c64_screens.py`  | Headless VICE captures of the scripted C64 run                                               |
| `tools/make_intro.py`   | The C64 start-up picture from the cover scans                                                |
| `docs/tools/`           | The handbook generator and the figure tools ([html_documentation.md](html_documentation.md)) |
