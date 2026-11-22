# Changelog

## [Unreleased] 18-11-2026 – C64 port

### Added

- Handbook sidebar logo: the Enhanced sprite frog beside the Oric frog (`docs/images/enhanced/frog-logo.png`, drawn
  by `frog_logo` in `docs/tools/render_enhanced.py`).
- C64 Enhanced attract screen (F1): in Enhanced the hi-score screen of the attract loop gets a colour-cycled title,
  lines under the title and round a scroller on row 24, and the sprite frog hopping along row 19 (`AttractStart`,
  `AttractPresent`, `AttractTitle` in `c64/src/sprites.s`; `ParseRowAtt` recolours the title right after `Present`
  parses it, and the round-robin parse skips it). The colour is per letter, not per raster line as in the mock-up: the
  row interrupt has no cycles to spare. `C64FontCopy` moves to `$C800` (bank 3 RAM) to make room in `HIDATA`.
- C64 start-up picture master `c64/art/intro.png`, to edit by hand: 320×200, indexed in the C64 palette, each
  multicolour pixel two wide. `make c64-intro` now packs it (snapping to the palette, stopping on 8×8 blocks with more
  than black and three colours, or reducing them with `--fix`); `tools/make_intro.py --from-scans` redraws it from the
  cover scans. The packed picture is unchanged.
- C64 Remix item 11: **3** in the attract loop redefines the keys. `MenuKeyC64` (patched over the `jsr ReadRomKey` in
  `CheckMenuKeys` at `$299F`) enters the controls menu as if 2 had been pressed, then restarts the attract loop; the
  credits add `PRESS [3] FOR NEW KEYS` under `PRESS [1] TO START`.
- Recordings to play in the docs: the four in-game tunes, the sheet tune, the frog-home jingle, a hop, the death and the
  low-time tone, recorded from the C64 port in VICE into `docs/sound/` (AAC) and embedded in `sound.md` and the
  handbook. `make c64-sound` (`tools/c64_sound.py`) runs a new sound build (`-D AUTOTEST_SOUND`: the four tunes in
  order, each `PickTune` call logged), finds each sound with VICE's monitor, records the run in real time and cuts it.
- C64 version switch on the instructions page only: F1 there flips Classic / Enhanced and shows the page again in the
  new look (`TakeF1` restarts the attract loop); on any other screen it is dropped. Classic's page shows the version
  line (`[F1] VERSION  CLASSIC  ENHANCED`, row 17) once the frog has laid it down. The version line on the menus and
  the hi-score screen, the joystick flip on the hi-score screen (`VersionKeys`) and the start-up picture's
  `F1 CLASSIC` / `F1 ENHANCED` sprites (`PicLabel`) are gone.
- C64 Enhanced instructions page (F3, layout C of three mock-ups in `docs/images/enhanced/mockups/`): in Enhanced the
  credits and instructions are one page drawn at once, a framed title, CONTROLS and HOW TO PLAY panels with the chosen
  keys as keycaps, and the 1, 3 and F1 buttons. `tools/instructions_page.py` writes it as an Oric screen
  (`c64/src/instrpage.inc`, 635 bytes packed); `EnhancedPage` unpacks it and lends six unused codes to line pieces for
  the frames (`LendPageGlyphs`, returned by `SetRowMap`). New `SPARE` memory area after the sprite images (`$8780`).
- C64 instructions list RUN/STOP: `RUN/STOP - QUIT GAME` above `P - PAUSE` on the credits (`CreditsEndC64`, patched
  over the `jsr CreditsEnd` at `$27C0`, C64 Remix item 10).
- `make c64-flicker` (`tools/c64_glitch.py`): consecutive VICE captures of the test builds, failing on one-frame
  glitches on the sound menu, a tear in the hi-score title and late first lines in Enhanced play. Checked against the
  faults it looks for (late row-interrupt stores, the title sync off).
- The Enhanced test build steers the frog itself (`Drive` in `c64/src/autotest.s`): it hops when the landing place is
  safe, crosses the road, rides the turtles and logs and is carried off the end of the top log. New captures `enh-road`,
  `enh-ride`; `enh-later` now shows the frog on the turtles and `enh-hops` the death flash at frame 3900. The test code
  moves to `HIDATA`.
- C64 Enhanced sprite frog (V2) and fly (V3), `c64/src/sprites.s`: the frog is a multicolour sprite with a hires black
  outline, made from the game's own `frog_gfx` and `splat_gfx` by the new `tools/frog_sprites.py` (`make c64-sprites`,
  `c64/src/sprites.inc`, loaded at `$8400`); a hop glides over a few frames on a low arc, and on the river the frog
  rides the lane's fine scroll. The fly flaps and bobs in its home. The game still draws and tests both as characters,
  whose glyphs are blank in Enhanced play (`SetFrogGfx` patched at `$0F20`, `SetSplatGfx`'s `jsr DrawFrog` at `$211B`,
  the fly's in `McBuild`). With the frog a sprite, V4's road lane under the frog glides too. Sprite code and variables
  are in `HIDATA`; the `enh-play` capture moves to frame 3066.
- C64 Enhanced smooth-scrolling lanes (V4): between the game's one-character steps each lane row is shifted 0–7 pixels
  with the `$D016` fine scroll, round(`lane_timer` × 8 / `lane_speeds`), so logs, turtles and traffic glide
  (`FineRow`, `FineTab`; `Present` takes each row's value with its copy, `rowCtl2`). The road lane the frog stands in
  stays in whole steps. Every row interrupt now writes `$D016` 4 cycles before `$D021`, in the border (the paper through
  a patched `lda #`, `EV_DELAY` 3 → 1). The tables are in `HIDATA` (main memory has 449 bytes left).
  `docs/tools/capture_screens.py` records `enh-smooth.gif` from VICE in place of the mock-up, and the `enh-play`
  capture moves to frame 3030.
- C64 RUN/STOP ends a game (C64 Remix, `docs/remix.md` item 10): GAME OVER, the hi-score check, then the hi-score
  table. `ReadKeysC64` checks it in play and pause and jumps to `QuitGameC64`.
- C64 F1 flips Classic / Enhanced on every screen before a game, not only the home screen: the menus, the credits and
  name entry flip in place (`Present` calls `TakeF1` while the ROM interrupt is on), and F1 on the start-up picture
  flips and goes to the home screen (`ShowPicture` returns `PIC_F1`; the label `HiscoreScreen` at `$296B`).
- C64 Enhanced Oric-style font (V7): a newly drawn 5 x 7 font with single-pixel strokes, as text art in
  `tools/oric_style_font.py` (`make c64-font` writes `c64/src/oricfont.inc`, `W6` layout). In Enhanced it replaces the
  C64 font on every screen (`KeepC64Font`, `SetFont`); F1 on the home screen swaps the font with the screen blanked
  for a couple of frames, and updates the game's copy at `$3100` (`SetFontC64`). The font and a RAM copy of the C64 font
  are at `$9000`-`$95FF`: `c64/cfg/c64.cfg` gains the `HIGH` area (segment `HIDATA`) and a filled `GAP`, so the `.prg`
  now covers `$0801`-`$95FF`. `render_enhanced.py` draws `font-sheet.png`, `font-screens.png` and `font-credits.png`.
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

- Links to the *Light Cycle* repository (github.com/anthonyjclarke/Light-Cycle-Oric) where the game is named: the
  README's history, `original_release.md`, `credits.md`, `html_documentation.md`, `porting.md` and `source_guide.md`.
- `oric_specs.md`: the ROM and Auric set-up steps are written in the third person, as in *Light Cycle*, so the file
  stays identical in both repositories.
- Docs pass, as in *Light Cycle*: the README and every chapter are in the third person (no "you", no instructions to
  the reader), and both READMEs open on the C64 version, with the Oric original, its commented source, `make verify`
  and `make run` kept alongside it. Stale status brought up to date against the code: the Enhanced chapters (V2–V4,
  F1, F3 built; no game hooks), the port's phase table (`v1.0` tagged), the open questions, and the build tables
  (`make c64-sprites`, `make clean`, `tools/instructions_page.py`, what `just docs` runs).
- Docs review: one home per topic, with links instead of repeats. The README is now a front page (the game, Oric,
  Classic and Enhanced screenshots, the versions, a short history, then a quick start and pointers to the chapters); its
  layout, build, Auric, reconstruction, quirks and memory-map sections are in `source_guide.md`, `architecture.md` and
  `quirks.md` (new quirk 14, padding and fill patterns; the Auric and VS Code notes moved to `source_guide.md`). The
  Redefine keys rules live in `remix.md`, the original quirks in `quirks.md`, the version switch in `enhanced.md` and
  `enhanced_platform.md`; stale "home screen" and "keys chosen once" wording fixed.
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

- C64 version flip on the credits turned the title frog into `:;` `<=`: `SetFontC64` rewrote codes `$3A`–`$3D` with
  the font. It now keeps those four glyphs as the game left them (`frogGlyphs`).
- C64 Redefine keys took a refused key's release as a key: pressing P for UP moved on to DOWN with UP set to RUN/STOP
  (no name in the instructions). `ScanRomKey` reported every key release as key 0 (`ROM_KEY` = `$80`): its `beq` after
  `sta zLastKey` tested the flags of the `cmp` before, which `sta` leaves alone, so it never skipped. The name entry
  and menus ignored code 0; `RedefineKeys` refused nothing for it. A release now reports nothing. A refused key also
  shows CAN'T USE in red after the prompt (`RedefNote`, in `HIDATA`) until a key is accepted.
- C64 Redefine keys lost a key typed within about 0.4 s of the one before: `WaitNoKeys` counted 5 passes of its loop,
  each an `IdleParse` of about 4 frames, then cleared `ROM_KEY`. It now counts 5 frames by `zTick`. (The test script's
  refused P was lost this way; the `redefine` capture moves to frame 410, showing CAN'T USE for the refused N.)
- C64 Enhanced river and road rows had their first line in the row above's fine scroll for a frame now and then while
  the frog sat on a row boundary (`make c64-flicker`: frames 3539 and 3585 on the river). The frog's sprite DMA stops
  the CPU at about cycles 56–62 of the line, right where the row interrupt stores `$D018`, `$D021` and `$D016`; when
  the interrupt was late all three came after it and the third started at cycle 9 of the next line, one cycle after the
  badline holds it to the line's end. The interrupt now saves its registers in zero page instead of pushing them (the
  stores 3 cycles earlier; 4 put the first one too early, in the last pixels of the row above), and in Enhanced play
  stores last a register that doesn't change at that boundary: the paper on the river (`IrqBgLast`), the character
  set on the road (`IrqCsLast`), picked per row by `IrqArmPlay` through the IRQ vector. Measured over 5,800 row
  interrupts the third store now starts by cycle 7; `make c64-flicker` and 300 more play frames are clean. The
  `controls` capture moves to frame 212, the middle of the LOUD line's lit phase.
- C64 death flash, jingles and sheet tune ran up to twice as long as on the Oric (the death 4.5 s in Classic, 5.3 s in
  Enhanced, against the Oric's 2.1 s), now 2.5 s. `WaitCycles` dropped any overrun a wait could not pay back, and each
  SID frequency took a 24-step division. Under `DelayX` (`catchUp`) an overrun now adds to the debt still owed (cap 65
  ms), the division counts as owed time (`DIVIDE_COST`), and once a `Present` overruns its wait the next ones come
  every third frame. The division takes 16 steps and is skipped when a voice's period hasn't changed. Play
  (`FrameDelay`) keeps a `Present` every frame and draws more often than before (every 1.2 frames in Classic, 1.4 in
  Enhanced, from 1.5 and 2.0).
- The handbook's audio players showed 0:00 until played: they now load each clip's length (`preload="metadata"` in
  `build_docs.mjs`).
- C64 Enhanced road markings drew a second, partial grey line (up to 8 characters into the lane) when the frog was near:
  its sprite DMA and the badline stall moved the paper restore late. The row interrupt now waits for the raster to pass
  the badline in a loop entered before the stall, with the line and paper patched in by `IrqArm` from the interrupt
  above. `IRQ_PAD` 1 → 0: with the frog on the road, 1 still left a road row's first line in the old fine scroll about
  one frame in 30. `make c64-flicker` now checks the markings and 200 frames of the frog crossing the road, and
  captures in parallel.
- C64 Enhanced frog sprite sat one line low (its outline over the status line from the bottom verge): a sprite shows
  from the raster line after its Y, so `TEXT_TOP` is `FIRST_TEXT_LINE` − 1.
- C64 Enhanced road markings blinked through the death flash: `FastRow` and `ParseRow` replaced a marked row's grey
  with the new paper until the next `FineRow`. They now leave the grey and change only `rowPaper`, which the interrupt
  puts back after the grey line.
- C64 text and lanes flickered for a frame every few frames: a row's first pixel line was sometimes drawn with the row
  above's character set (double-height menu text, the hi-score table, multicolour lanes) because the row interrupt's
  `$D018` store, spread over 10 cycles with `$D016` and `$D021` since V4, could land after that badline started. The
  three values are now loaded into registers and stored back to back after `IRQ_PAD` nops, set to 1 from VICE
  measurements (0–4 clean on the menu, 5 late; only 0–1 clean with the frog's sprites on a row boundary; later 0). Found
  by decoding the user's VICE recordings and reproduced on headless captures of the sound menu (8 glitches in 46 frames,
  now 0).
- C64 Enhanced log and turtle tops flickered: `$D022`/`$D023` land after the badline stall, so a lane's first line
  sometimes took the colours of the row above. A row without multicolour cells now loads the next row's colours.
- C64 hi-score title tore now and then (scrolled top halves over old bottom halves for a frame): `Present` updated its
  two rows while the beam was between them. With a double-height top row it now starts only with the beam past both.
- C64 Enhanced frog sprite vanished for a frame now and then: `SprTarget` cleared `frogVis`/`flyVis` before working out
  the positions, and a frame interrupt in between switched the sprites off. It now writes them once, at the end.
- C64 Enhanced road markings had drifted to the third pixel line of the car lanes, across the tops of the cars, so the
  traffic looked off the middle of the road: their fixed 25 + 64-cycle waits no longer matched once V4 and V7 added code
  ahead of them. The row interrupt now starts a marked row grey (`rowIrqBg`, set by `FineRow`) and puts the paper back
  straight after the boundary stores, which the row's badline holds to the end of the line: exactly the lane's first
  line, between the lanes.
- C64 keys stopped working, and the screen lost its colours and double height, after some F1 presses: `SetFontC64`
  wrote `$D011` back with bit 7 as it read it, the raster's bit 8, which sets the raster interrupt's line. A flip while
  the beam was below line 255 moved the interrupt to line 256 + n, which a frame never reaches, so the key scan and the
  row splits stopped. It now clears bit 7. (Found from a VICE snapshot: interrupt line 314.)
- C64 Enhanced drew the road markings, and set multicolour, on the blank rows of the READY / SHEET NO signs, which sit
  where the road lanes are. `McSimple` now leaves a row hires when it starts with a character, as the signs' rows do;
  lane rows start with their colour attributes.
- C64 hi-score screen after a game whose score didn't make the table: `ShowHiScores` drew the table without the port's
  hook, so the screen kept the game's row map and double-height set (the title's stars showed as hedge), and had no
  version line. `$1BD2` now calls `HiscoreTableC64`, like `$1B51` and `$2971`.
- C64 picture lopsided: Oric column 0 showed black and column 1 the row's paper on the left, while the playfield ran to
  the border on the right. The picture now sits one column left (Oric column *c* is VIC column *c*–1, `rowDst`,
  `rowCol` and `CopyRows`), so the playfield has one column of the row's paper on each side and Oric column 0 is not
  shown. Both versions; the screenshots and Enhanced mock-ups are redrawn to match.
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
