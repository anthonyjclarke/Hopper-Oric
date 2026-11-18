# Hopper – C64 Remix: Changes from the Original

The C64 version runs the Oric game's own code, every byte at its Oric address, so by default it plays exactly like the
1983 tape. This chapter lists every place where it deliberately does **not**: what the original did, what the C64 does
instead, why, and where the change lives. Anything not listed here is meant to behave as on the Oric; if it doesn't,
that is a port bug, not a remix.

Each change to the game's own bytes is marked `; C64:` in `c64/src/hopper.s`, and the gameplay ones also say `(Remix)`.
`make c64-diff` lists every game byte that differs from the Oric program. The Oric build (`src/hopper.s`) is never
changed: `make verify` keeps it byte-identical to the tape.

---

## Summary

| # | Change                                           | Kind           | Where                         |
|:--|:-------------------------------------------------|:---------------|:------------------------------|
| 1 | The frog can hop to the outermost columns        | Gameplay       | `StepFrogC64`, `CarryFrogC64` |
| 2 | Controls choice 2 is **Redefine keys**           | Controls       | `RedefineKeys` (`input.s`)    |
| 3 | Controls choice 1 is Z, X, K, M                  | Controls       | `keys_set1` data              |
| 4 | Joystick in port 2, with either key choice       | Controls       | `ReadKeysC64`, `JoyToKeys`    |
| 5 | Start-up picture from the PSS cassette cover     | Presentation   | `intro.s`, `make_intro.py`    |
| 6 | Attract loop: hi-scores, picture, credits        | Presentation   | `TitleTickC64`                |
| 7 | No hang when the frog reaches a home with no fly | Fix (hardware) | `EraseFlyC64`                 |
| 8 | Hardware stand-ins: screen, sound, keys, RESET   | Port           | [porting.md](porting.md)      |

---

## 1. The Frog Can Hop to the Outermost Columns

**Original.** The playfield is columns 2–39 (columns 0–1 hold each row's colour attributes). The frog is two columns
wide and hops two columns at a time. The game stores its column in `frog_col` as one less than its screen column (it
starts at column 20 with `frog_col` 19), but `CheckFrogBounds` tests `frog_col` as if it were the screen column, killing
the frog at `frog_col` 1 or `$25`: on reaching column 2, or on covering column 39. So from the start the frog gets eight
hops each way; the ninth looks as if it lands on open grass, yet it dies. On the river, a log or turtle carrying the frog
kills it one column before the edge for the same reason. See quirk 13 in [quirks.md](quirks.md).

**C64 Remix.** The frog may stand anywhere in columns 2–39:

- `CheckFrogBounds` allows `frog_col` 1 to `$25` (`cmp #$02` → `#$01`, `cmp #$25` → `#$26`, `$0FF3`, `$0FFB`).
- A sideways hop that would leave the playfield is not made: the frog turns to face that way and stays put
  (`StepFrogC64`, called from `MoveFrog` at `$1410` instead of `StepFrog`). Hopping off the side is no longer a way to
  die; it was an easy one to do by accident, since the grass looked free.
- A log or turtle carrying the frog past column 2 or 39 still kills it, but where it stands, before it moves
  (`CarryFrogC64`, entered from `CarryFrog` at `$1180`). This keeps the death splat inside the playfield: drawn one
  column further out, as the original rule would now do, it would overwrite the row's paper attribute in column 1 (or
  the next row's column 0) and turn two rows the wrong colour during the death flash.

**Why.** The original limit looks like an off-by-one: the visible grass at columns 2–3 and 38–39 could never be stood on.

---

## 2. Controls Choice 2 Is Redefine Keys

**Original.** The controls menu offered two fixed key sets: 1 = Z, X, `'`, `/` and 2 = `,`, `.`, A, Z (left, right, up,
down).

**C64 Remix.** Choice 2 is **Redefine keys** (`RedefineKeys`, `input.s`, in place of `cmp #'2' / bne` at `$2F91`). It
asks for left, right, up and down in turn under the menu, and refuses P (pause), SPACE, RETURN, DEL, `:` `;` `=` (the
frog's characters in the credits text) and a key already chosen. Before each prompt it waits until no key has been down
for 5 frames (`WaitNoKeys`), so the key that chose 2, or a bounce, isn't taken as LEFT. It writes each key's column
select, row mask and key bit into the Oric's second key table (`keys_set2`), which the menu's own code then copies into
use as before, and puts the four key names into the instructions text.

**Why.** Fixed punctuation keys don't survive host keymaps in VICE, and choosing your own keys is the usual C64
convention.

---

## 3. Controls Choice 1 Is Z, X, K, M

**Original.** Z, X, `'`, `/`.

**C64 Remix.** Z, X, K, M (left, right, up, down). Letters only: punctuation moves about with VICE's host keymaps (the
first try, Z X `@` `/`, was unusable).

---

## 4. Joystick in Port 2

**Original.** Keyboard only.

**C64 Remix.** A joystick in port 2 works alongside either key choice (`JoyToKeys` folds it into `key_state`). Fire
starts a game from the start-up picture.

---

## 5. Start-Up Picture

**Original.** The tape went straight to the sound menu.

**C64 Remix.** A multicolour bitmap made from the PSS cassette cover and inlay is shown for 8 seconds or until a key or
fire. It is built by `tools/make_intro.py` (`make c64-intro`) and shown by `ShowPicture` (`intro.s`); the method is in
[porting.md](porting.md).

---

## 6. Attract Loop

**Original.** The hi-score screen scrolled its title and waited for a key for ever; the credits only came back on 2.

**C64 Remix.** After about 15 seconds the hi-score screen moves on to the picture, then the credits and instructions,
then the hi-scores again (`TitleTickC64`, in place of `jsr CheckMenuKeys` at `$2938`). 1 or fire on the picture starts a
game. The sound and controls menus still appear only at power-up and on RESTORE, so keys are chosen once.

---

## 7. No Hang When the Frog Reaches a Home With No Fly

**Original.** `CheckFlyEaten` calls `EraseFly` for every frog that reaches the home row, fly or not. With no fly showing,
`fly_ptr` is `$0000`, so the Oric wrote two harmless spaces to zero page `$00`/`$01` (quirk 12).

**C64 Remix.** On the C64, `$00`/`$01` is the 6510's port: those spaces switched BASIC, KERNAL and I/O in and the
machine hung. `EraseFlyC64` writes them where the Oric's `tmp0` and `key_state` now live instead. Play is unchanged; this
is a fix forced by the hardware, not a design change.

---

## 8. Hardware Stand-Ins

Not remixes, but things that can't be the same on a C64, described in [porting.md](porting.md): the 28-row Oric screen
is shown on 25 rows (three blank rows hidden per screen), in the C64's font, with per-row paper colours; the AY sound
plays on the SID; RESTORE is the Oric's RESET button; the delays run on a CIA clock (PAL plays 1.5% slow, NTSC 2.3%
fast). Its **Known Differences** table lists what shows.

---

## Kept as in the Original

Everything else, including the original's quirks and bugs: the branch into an instruction in `CheckFrogBounds`, the
jump into `jsr ClearScreen`, the hidden RESET exit, "INSTRUCTONS", the unplayed first note of each tune and the rest of
[quirks.md](quirks.md).
