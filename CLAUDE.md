# HOPPER – Claude context

Target: Oric-1 (6502 @ 1MHz, 6522 VIA, AY-3-8912, 40x28 TEXT mode), emulated
with Auric (`~/PlatformIO/Projects/Auric/build/src/auric`, `--oric1`).
Not a PlatformIO project – toolchain is cc65 (`ca65`/`ld65`) via `Makefile`.

Reconstructed source of P.S.S.'s HOPPER (1983), v1.0 = byte-identical to
`original/HOPPER.TAP` (one block `$0500`–`$30D4`, autorun).

## Rules

- `make verify` must pass after any change meant to be faithful. Never edit
  `original/`.
- Keep every byte at its original address: pointers are built from immediate
  bytes (`lda #$B5`), so the code is not relocatable.
- Absolute-mode instructions on zero-page addresses must keep the `a:` prefix
  or ca65 shortens them and the build diverges.
- `src/hopper.s` is the master once hand-edited. `make regen` regenerates it
  from `tools/annotations.py` and discards hand edits – ask before running it.
- Keep the original address in each instruction's comment column (`; 0FE0`).
- TAP header is emitted by the `TAPEHDR` segment; end address is inclusive.

## Gotchas

- Oric-1 ROM locations are used directly: NMI/RESET vector `$022B`, key
  buffer `$02DF` (bit 7 = new key), cursor pointer `$12/$13`, cursor column
  `$0269`. Atmos ROM differs – always test with `--oric1`.
- The ROM IRQ stays enabled (VIA T1 at 100Hz) for the key buffer; `$12/$13`
  is set to `$C0C0` so the cursor blink writes into ROM, not the screen.
- Hi-score table lives at `$BA00` (alternate charset RAM) and survives RESET.
- Original bugs kept on purpose: `bcs $0FD6` (into an instruction, illegal
  opcode) and `jmp $296D` (into `jsr ClearScreen`). Don't "fix" them in the
  faithful build.
- Zero-page `$20-$23`, `$30/$31` are reused as copy pointers by several
  routines despite their names.
- Auric needs `basic10.rom` in its `ROMS/` folder (not distributed).

## C64 port (`c64/`, docs/porting.md)

- `c64/src/hopper.s` = `src/hopper.s` patched in place: every game byte stays
  at its Oric address. Patches must fit the bytes they replace (pad with
  `nop`) and carry `; C64:`. Check with `make c64-diff`.
- Changes to the Oric source don't flow to the C64 copy; port them by hand.
- Any deliberate C64 deviation from the original ("C64 Remix") goes in
  `docs/remix.md` and its patch comment says `(Remix)`.
- C64 `CHARSET` is `$B000` (VIC 2K alignment); SCREEN/HISCORES stay put.
- `tmp0`/`key_state` live at `$07/$08` on the C64 ($00/$01 is the 6510 port).
- `key_bits` `$08` = down, `$04` = up (the third key slot is down).
- Never leave IRQs masked for long in C64 code: the raster IRQ sets each
  row's paper and charset. Platform zero page is `$60-$CF` (`zp.s`).
- Chars `$3A-$3D` are the frog, also in the credits text: don't show them as
  text (RedefineKeys refuses `:` `;` `=`).
- The VIC picture is one column left: Oric col c -> VIC col c-1 (`rowDst`,
  `rowCol` are row start - 1). Oric col 0 is never written (it would land on
  the row above's col 39, the right margin). `CopyRows` copies cols 2-39;
  col 1 belongs to `FastRow` / `ParseRow` (both must draw it the same way).
- Rows with attributes past column 1 get colour only from a row parse. Plain
  `Idle` never parses: `CheckMenuKeys` runs in counted loops and would slow.
  Uncounted waits that draw such text use `IdleParse`.
- `c64/src/intro.rle` is generated: `make c64-intro` (python3.14 + Pillow)
  packs the hand-editable master `c64/art/intro.png` (320x200, C64 palette,
  black + 3 colours per 8x8). `--from-scans` redraws the master from the
  cover scans and overwrites hand edits: ask first.
  Unpacked once into VIC bank 3 (`$C000`, `$C400` colour copy, `$E000`
  bitmap; `$C800` `C64FontCopy`): keep the rest of bank 3 free.
  `ShowPicture` runs with IRQs masked.
- Main memory below `$8000` is nearly full (BSS ends ~`$7FAF`): put new
  code and tables in `HIDATA` (`$9000`+, not VIC-visible).
- Row IRQ: `$D018`/`$D021`/`$D016` go back to back from registers saved in
  zero page (not pushed). No cycle to spare either way: 1 earlier shows in
  the row above's last pixels, and with the frog's sprite DMA the third store
  starts by cycle 7 of 8. Anything added before them: re-measure (monitor
  line/cycle at the stores, `make c64-flicker`). In Enhanced play
  `IrqArmPlay` points the IRQ vector at the order whose last register doesn't
  change (`IrqBgLast` river, `IrqCsLast` road); `SetRowMap` resets it.
  `$D022/$D023` land after the badline, so non-multicolour rows preload the
  next row's. A marking's paper restore waits on `$D012` in a loop entered
  before the badline stall; its operands are patched by `IrqArm`.
- Enhanced play blanks the glyphs of the frog (`$3A-$3D`) and fly (`$7C/$7D`):
  sprites draw them (`sprites.s`, images `make c64-sprites`). The game still
  draws and collides with the characters; don't rely on those glyphs there.
- `WaitCycles`: under `DelayX` (`catchUp`) debt adds up and Presents thin
  out to keep Oric pace; play (`FrameDelay`) presents every frame and drops
  unpaid debt. Don't change play's rule: smooth scrolling depends on it.
- `make c64-flicker` checks for one-frame glitches; the Enhanced test build
  steers the frog (`Drive`), so its captures follow the drive, not frames.
- Enhanced attract screen (F1, `sprites.s`): `attractOn` gates it;
  `SetRowMap` clears it. Scroller row 24 / frog row 19 keep sprite DMA off
  the scroller row's IRQ.
- F1 flips the version only on the instructions page (`versionShown`);
  elsewhere `TakeF1` just drops it. A flip restarts the attract loop.
- Enhanced instructions page (F3): `tools/instructions_page.py` writes
  `c64/src/instrpage.inc`. Its frames borrow the codes of `{` `}` `|` `~`
  `#` and backtick (`LendPageGlyphs`; `SetRowMap` returns them): no page
  text or key name may use them. `SPARE` (`$8780`) is after the sprites: never in `SPRDATA`.
- Test with `make c64-smoke` (scripted keys, `c64/src/autotest.s`); headless
  VICE has no sound.
