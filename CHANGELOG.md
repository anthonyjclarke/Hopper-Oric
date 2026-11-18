# Changelog

## [Unreleased] 18-11-2026 – C64 port

### Added

- README and `docs/credits.md` link to the game's entry on oric.org.
- `docs/oric.md`, an appendix on the Oric for readers new to it: history, specifications, memory map, serial attributes
  and the three video modes, the AY-3-8912 and how the VIA reaches it, BASIC examples (run on the Atmos ROM in Auric),
  running the original in an emulator (Auric, ROMs from oric.free.fr), how *Hopper* uses the machine, and further
  reading. Its figures (`oric-palette.png`, `oric-attributes.png`, `oric-envelopes.png`) come from the new
  `docs/tools/render_oric.py`, run by `just docs` and `just docs-graphics`.
- Commodore 64 version in `c64/`, built the Light Cycle way: a faithful re-host. `c64/src/hopper.s` is the Oric source
  with only its hardware patched in place, every game byte at its Oric address; the platform layer shows the Oric screen
  on the VIC-II (row maps for 28 rows on 25, serial attributes to colour RAM and per-row raster splits, double height,
  blink, inverse), plays AY register writes on the SID, reads the CIA keyboard and joystick port 2, and keeps the Oric's
  delays and timer on a CIA clock.
- `make c64`, `c64-d64`, `c64-run`, `c64-diff`, `c64-smoke`.
- `tools/c64_diff.py` (game bytes that differ from the Oric program), `tools/c64_screens.py` (VICE captures of a
  scripted run, `c64/src/autotest.s`), `tools/oric_screens.py` (the Oric screens drawn by the original code on
  `tools/cpu6502.py`).
- `docs/porting.md`: approach, memory map, mapping, decisions and known differences.
- Documentation in `docs/` in the format of the Light Cycle repository, and the offline handbook `docs/HOPPER.html`
  generated from it: player's guide, original release (the cover, the inlay and the PSS advert), screens and graphics,
  sound, architecture, data formats, source guide, porting, platform layer, quirks, maintenance and credits. The
  generator, templates and vendored Marked and Mermaid are carried over unchanged from Light Cycle.
- Documentation tools: `docs/tools/render_graphics.py` (Oric screens drawn by the game's own code, rendered with serial
  attributes; the redefined characters, the frog, the turtle dive), `docs/tools/capture_screens.py` (VICE captures of
  the C64 build), `docs/tools/doc_names.py` (labels named in the docs exist in the source), and a `justfile` with the
  `docs`, `docs-html`, `docs-check`, `docs-watch`, `docs-screens`, `docs-graphics` and `docs-names` recipes.
- C64 start-up picture: a multicolour bitmap made from the PSS cassette cover (`docs/images/original/`) by
  `tools/make_intro.py` (`make c64-intro`), shown for 8 seconds or until a key or fire (`c64/src/intro.s`). It stays
  unpacked in VIC bank 3 and comes back in the attract loop.
- C64 attract loop: the hi-score screen, which on the Oric waited for a key for ever, moves on after about 15 s to the
  picture, then the credits and instructions, then the hi-scores again (`TitleTickC64`). 1 or fire on the picture starts
  a game.
- C64 controls menu choice 2 is now "Redefine keys": asks for left, right, up and down, refusing P, SPACE, RETURN, DEL,
  the frog's characters and repeats, and puts the names in the instructions (`RedefineKeys`).

### Changed

- C64 controls choice 1 is Z, X, K, M (was Z, X, `@`, `/`, which move with host keymaps in VICE).
- C64 Remix: the frog can stand in the outermost playfield columns (2 and 38–39). On the Oric it died on reaching them,
  so the ninth hop sideways from the start killed it on visible grass (`CheckFrogBounds` treats `frog_col`, one less
  than the screen column, as the column). A sideways hop off the playfield is now refused (`StepFrogC64`), and a log or
  turtle carrying the frog past the edge kills it before it moves (`CarryFrogC64`), so the splat never covers a row's
  colour attributes. Oric build unchanged.
- `docs/remix.md`: the C64 Remix's deliberate changes from the original, each with what the Oric did, what the C64
  does, why and where: the frog edges, Redefine keys, the Z X K M set, the joystick, the start-up picture, the attract
  loop and the `EraseFly` hang fix. Linked from the README, `porting.md`, `quirks.md` (new quirk 13) and the handbook.

### Fixed

- C64 hung whenever the frog reached the home row with no fly showing (every home, hedge or full-home death on sheets
  1–2): the Oric's `EraseFly` writes two spaces through `fly_ptr`, which is `$0000` then, so it hit `$00`/`$01`, the
  6510's port, switching BASIC, KERNAL and I/O in. `EraseFlyC64` puts those spaces where the Oric's `tmp0` and
  `key_state` now live instead. Checked in VICE by running `CheckFlyEaten` at the hedge on sheet 1.
- C64 Redefine keys gave the keys the wrong directions (a key chosen for LEFT moved the frog up): the Oric's control
  choice 2, whose table it fills, lists its keys up, down, left, right, with its key bits in that order. `RedefineKeys`
  now writes the bits too, in the order it asks for the keys.
- C64 Redefine keys took a key for LEFT before one was pressed (the key that chose 2, or a bounce), so LEFT could end up
  blank. Each prompt now waits until no key has been down for 5 frames and drops any key seen meanwhile (`WaitNoKeys`).
- C64 controls menu showed in white: its rows are only coloured by a row parse, which the key wait never ran. The menu's
  key wait now parses rows between draws (`ReadMenuKey`, `IdleParse`).
- C64 left edge: columns 0–1 showed as a two-column strip of the row's paper, and each pass of `ParseNextRow` drew a
  black cell in column 0 for one frame, which wandered up and down the river. The copy now covers columns 2–39 and
  `FastRow` / `ParseRow` draw columns 0–1 as the Oric does (column 0 black, column 1 the paper), so the edge is steady.
- C64 text flickered as it appeared: signs and menu text printed on a cleared screen showed for a few frames in the
  wrong colours, or double-height text as two normal copies, until a round-robin parse reached the row. `Present` now
  scans rows that start with a character for new attributes (`ScanRow`), and the raster IRQ reads each row's paper and
  character set live at every row boundary instead of from lists built at the top of the frame.

## [1.0] 08-11-2026

### Added

- Full ca65 source for HOPPER (`src/hopper.s`) reconstructed from `original/HOPPER.TAP`, with named routines, variables
  and data, and character graphics shown as pixel art.
- Hardware and variable include files (`src/oric.inc`, `src/vars.inc`).
- ld65 config that writes a complete TAP file, and a `Makefile` with `build`, `verify`, `run`, `debug` and `regen`
  targets.
- Disassembly tools: `tools/gen_source.py`, `tools/annotations.py`, `tools/m6502.py`, `tools/dis_range.py`.
- VS Code tasks, ca65 syntax association and extension recommendation.
- README describing the build, Auric setup, findings and memory map.
