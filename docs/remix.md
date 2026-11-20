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

| #  | Change                                           | Kind           | Where                         |
|:---|:-------------------------------------------------|:---------------|:------------------------------|
| 1  | The frog can hop to the outermost columns        | Gameplay       | `StepFrogC64`, `CarryFrogC64` |
| 2  | Controls choice 2 is **Redefine keys**           | Controls       | `RedefineKeys` (`input.s`)    |
| 3  | Controls choice 1 is Z, X, K, M                  | Controls       | `keys_set1` data              |
| 4  | Joystick in port 2, with either key choice       | Controls       | `ReadKeysC64`, `JoyToKeys`    |
| 5  | Start-up picture from the PSS cassette cover     | Presentation   | `intro.s`, `make_intro.py`    |
| 6  | Attract loop: hi-scores, picture, credits        | Presentation   | `TitleTickC64`                |
| 7  | No hang when the frog reaches a home with no fly | Fix (hardware) | `EraseFlyC64`                 |
| 8  | Hardware stand-ins: screen, sound, keys, RESET   | Port           | [porting.md](porting.md)      |
| 9  | Version switch (F1) on the instructions page     | Presentation   | `TakeF1`                      |
| 10 | RUN/STOP ends a game, listed in the instructions | Controls       | `QuitGameC64`                 |
| 11 | 3 redefines the keys from the attract loop       | Controls       | `MenuKeyC64`                  |

---

## 1. The Frog Can Hop to the Outermost Columns

**Original.** The playfield is columns 2–39, but an off-by-one in `CheckFrogBounds` kills the frog on reaching column 2
or covering column 39, so the visible grass at either edge can't be stood on, and a carried frog dies one column early
(quirk 13 in [quirks.md](quirks.md)).

**C64 Remix.** The frog may stand anywhere in columns 2–39:

- `CheckFrogBounds` allows `frog_col` 1 to `$25` (`cmp #$02` → `#$01`, `cmp #$25` → `#$26`, `$0FF3`, `$0FFB`).
- A sideways hop that would leave the playfield is not made: the frog turns to face that way and stays put
  (`StepFrogC64`, called from `MoveFrog` at `$1410` instead of `StepFrog`). Hopping off the side is no longer a way to
  die; it was an easy one to do by accident, since the grass looked free.
- A log or turtle carrying the frog past column 2 or 39 still kills it, but where it stands, before it moves
  (`CarryFrogC64`, entered from `CarryFrog` at `$1180`). This keeps the death splat inside the playfield: drawn one
  column further out, as the original rule would now do, it would overwrite the row's paper attribute in column 1 (or
  the next row's column 0) and turn two rows the wrong colour during the death flash.

**Why.** The visible grass at columns 2–3 and 38–39 could never be stood on.

---

## 2. Controls Choice 2 Is Redefine Keys

**Original.** The controls menu offered two fixed key sets: 1 = Z, X, `'`, `/` and 2 = `,`, `.`, A, Z (left, right, up,
down).

**C64 Remix.** Choice 2 is **Redefine keys** (`RedefineKeys`, `input.s`, in place of `cmp #'2' / bne` at `$2F91`). It
asks for left, right, up and down in turn under the menu, and refuses P (pause), SPACE, RETURN, DEL, `:` `;` `=` (the
frog's characters in the credits text), F1 (the version switch) and a key already chosen, showing CAN'T USE in red after
the prompt (`RedefNote`) and waiting for another key. Before each prompt it waits until no key has been down for 5
frames (`WaitNoKeys`), so the key that chose 2, or a bounce, isn't taken as LEFT. It
writes each key's column select, row mask and key bit into the Oric's second key table (`keys_set2`), which the menu's
own code then copies into use as before, and puts the four key names into the instructions text.

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
game. The sound and controls menus still appear only at power-up and on RESTORE; 3 redefines the keys from the
attract loop (change 11).

---

## 7. No Hang When the Frog Reaches a Home With No Fly

**Original.** With no fly showing, erasing the fly writes two harmless spaces to zero page `$00`/`$01` (quirk 12 in
[quirks.md](quirks.md)).

**C64 Remix.** On the C64, `$00`/`$01` is the 6510's port: `$20` in its direction register makes the banking lines
inputs, which float high, so BASIC, KERNAL and I/O switched in and the machine hung in the KERNAL's interrupt code.
`EraseFlyC64` writes them where the Oric's `tmp0` and `key_state` now live instead. Play is unchanged; this is a fix
forced by the hardware, not a design change.

---

## 8. Hardware Stand-Ins

Not remixes, but things that can't be the same on a C64, described in [porting.md](porting.md): the 28-row Oric screen
is shown on 25 rows (three blank rows hidden per screen), in the C64's font, with per-row paper colours; the AY sound
plays on the SID; RESTORE is the Oric's RESET button; the delays run on a CIA clock (PAL plays 1.5% slow, NTSC 2.3%
fast). Its **Known Differences** table lists what shows.

---

## 9. Version Switch on the Instructions Page

**Original.** One version; row 17 of the credits, between the address and the instructions, is blank.

**C64.** F1 on the credits and instructions page picks Classic (the port as this chapter describes it) or the C64
Enhanced look, and shows the page again in it; on other screens F1 does nothing. Classic's page shows the choice on row
17 once the frog has laid the page down (`DrawVersionLine`, from `CreditsEndC64`, patched over the `jsr CreditsEnd` at
`$27C0`). The page lists the keys and redefines them (change 11), so controls and look are chosen in one place. Play is
the same in both; the switch is described in [enhanced.md](enhanced.md#the-version-switch).

---

## 10. RUN/STOP Ends a Game

**Original.** A game ends only when the last life is lost. The RESET button stops it, but goes back to the sound menu.

**C64.** RUN/STOP in a game, or while it is paused, ends it at once: GAME OVER, the hi-score check (the score so far
counts), then the hi-score table. `ReadKeysC64` checks the key on every key read in a game and jumps to
`QuitGameC64`, which resets the stack, silences the sound and enters the game's own `GameOver`. RESTORE still works as
the RESET button. The credits list it with the other keys, `RUN/STOP - QUIT GAME` above `P - PAUSE` (row 19, drawn by
`CreditsEndC64`).

**Why.** A player who wants another go, or the other version, had to play to the end or go back through both menus.

---

## 11. 3 Redefines the Keys from the Attract Loop

**Original.** The controls menu comes once, after the sound menu; only the RESET button brings it back.

**C64 Remix.** **3** on any screen of the attract loop (picture, credits, hi-scores) goes straight to Redefine keys.
`MenuKeyC64` replaces the `jsr ReadRomKey` in `CheckMenuKeys` at `$299F`: on 3 it resets the stack, silences the sound,
clears the screen, puts 2 in `ROM_KEY` and calls `ControlsMenu`, so the menu's own choice 2 runs `RedefineKeys`; then
the attract loop starts again with the credits, which show the new keys. Any other key returns as `ReadRomKey` did.
`CreditsEndC64` adds `PRESS [3] FOR NEW KEYS` in white on row 27, under the blinking `PRESS [1] TO START`; its ink
attribute replaces the row's blink attribute at column 14, so the line holds still.

**Why.** Trying other keys meant RESTORE and both menus again; the instructions page is where the keys are listed.

---

## Kept as in the Original

Everything else, including the original's quirks and bugs: the branch into an instruction in `CheckFrogBounds`, the
jump into `jsr ClearScreen`, the hidden RESET exit, "INSTRUCTONS", the unplayed first note of each tune and the rest of
[quirks.md](quirks.md).
