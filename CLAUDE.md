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
  row's paper and charset. Platform zero page is `$60-$8F`.
- Chars `$3A-$3D` are the frog, also in the credits text: don't show them as
  text (RedefineKeys refuses `:` `;` `=`).
- `CopyRows` copies columns 2-39 only; columns 0-1 belong to `FastRow` /
  `ParseRow` (both must draw them the same way, or col 0 flickers).
- Rows with attributes past column 1 get colour only from a row parse. Plain
  `Idle` never parses: `CheckMenuKeys` runs in counted loops and would slow.
  Uncounted waits that draw such text use `IdleParse`.
- `c64/src/intro.rle` is generated: `make c64-intro` (python3.14 + Pillow),
  from `docs/images/original/cover.png` (a straight scan) and `inlay.png`.
  Unpacked once into VIC bank 3 (`$C000`, `$C400` colour copy, `$E000`
  bitmap): keep bank 3 free. `ShowPicture` runs with IRQs masked.
- Test with `make c64-smoke` (scripted keys, `c64/src/autotest.s`); headless
  VICE has no sound.
