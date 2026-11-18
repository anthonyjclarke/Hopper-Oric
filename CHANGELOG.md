# Changelog

## [Unreleased] 18-11-2026 – C64 port

### Added

- C64 Enhanced road markings (V6): in an Enhanced game the row interrupts for Oric rows 20 and 23 turn `$D021` grey for
  one raster line, where the port hides the Oric's dashed lines (rows 19 and 22). Only while those rows show lanes, so
  the sheet-start signs are untouched.
- C64 Enhanced multicolour lanes (V1 of `docs/enhanced.md`): in an Enhanced game, logs, turtles, trucks, cars and the
  hedge are drawn in multicolour with a shade and a top-edge highlight per lane, from a second character set at `$8800`
  that `c64/src/enhanced.s` builds from the game's own glyphs (`McBuild`, `McChar`) and keeps in step as the game
  rewrites the frog, home frogs and turtle frames (`McDynamic`, with sentinel glyphs to catch `InitGame`'s copy). The
  raster interrupt sets `$D022`/`$D023` per row; FastRow and ParseRow give lane rows the ink + 8 (`McRowSetup`). No game
  bytes changed. All of it sits behind `zMcPlay` (Enhanced on the play screen), so menus, credits and Classic run as
  before.
- `make c64-smoke` also builds `c64/build/test-enhanced/` (`-D AUTOTEST_ENHANCED`, no F1) for the `enh-play`, `enh-hops`
  and `enh-later` captures.
- C64 version switch (V0 of `docs/enhanced.md`): row 25 of the hi-score screen shows `[F1] VERSION  CLASSIC  ENHANCED`,
  and F1 or the joystick left or right flips it (`VersionKeys`, `DrawVersionLine`, from `TitleTickC64`), restarting the
  attract timer. The choice is the zero-page flag `zEnhanced`, set to Enhanced at power-up and kept through RESTORE.
  Enhanced has no visible changes yet. `RedefineKeys` refuses F1, which `ScanRomKey` now reports as `KEY_F1`.
- A **C64 Enhanced** section in the documentation, for a planned second look the player picks on the home screen
  (F1 flips Classic and Enhanced): `docs/enhanced.md` (overview, ground rules, the version switch, plan of work, open
  questions), `docs/enhanced_graphics.md` (multicolour lanes, sprite frog and fly, water and grass, road markings, an
  Oric-style font, the attract screen, smooth lanes), `docs/enhanced_sound.md` (SID voicing, effects, a title tune) and
  `docs/enhanced_platform.md` (version flag, hooks, raster interrupt, sprites, memory, disk hi-scores, testing). Its
  mock-ups come from the new `docs/tools/render_enhanced.py`, run by `just docs` and `just docs-graphics`. Nothing in it
  is built yet.
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

- The Oric appendix moves out of Reference into its own Appendix group in the handbook and index, and splits in two.
  `oric_history.md` ("History of Oric") is expanded into the full story: Tangerine and the Microtan, the Oric-1 and its
  French success, the 1983 factory fire, Edenspring and the Atmos, the peripherals, the Stratos and the receivers,
  Eureka and the Telestrat, the Pravetz 8D and Nova 64 clones, software and magazines, a timeline and today's community
  and hardware. `oric_specs.md` ("Oric Tech Specs") takes the specifications, memory map, graphics, sound and emulator
  sections, with new tables of the models and their storage. Both are general information on the Oric, with no game
  named, and the same files in every Oric reconstruction; the game's own screen gives way to an Auric capture of the
  HIRES BASIC example (`oric-basic-hires.png`). The founders are corrected to Paul Johnson, Mark Rainer and Nigel Penton
  Tilbury, with Barry Muncaster joining later.
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

- F1 on the hi-score screen was sometimes lost: `CheckMenuKeys` draws a frame before reading the key and dropped an F1
  that arrived meanwhile. `ReadRomKey` now holds F1 back in `versionReq` for `VersionKeys`.
- The scripted test's keys were too close together (15 frames between redefine prompts, 50 between the menus): a few
  extra cycles lost a key and left a menu waiting. The script now leaves 25 frames between keys and 80 between the
  menus, presses F1 at 2500 and starts the game at 2600; every capture frame in `tools/c64_screens.py` moves with it.
- The scripted C64 test (`c64/src/autotest.s`) pressed 1 on the credits screen, so the `hiscores` capture showed the
  credits: the hi-score screen comes later since `AttractWait`. The script now waits for it, presses F1 there (new
  `version` capture) and starts the game 225 frames later; the play captures move with it. `credits-done` moves from
  frame 1125, where the frog was still drawing the credits, to 1400.
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
