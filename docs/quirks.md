# Hopper – Original Quirks

Places where the Oric code does something unintended or fragile, read from the reconstruction, with what the C64 port
does about each. The port keeps the game's code, so it keeps its quirks unless the hardware forces a change or the C64
Remix changes it on purpose ([remix.md](remix.md)).

---

## The List

| #  | Quirk                                                        | Where                       | C64 decision               |
|:---|:-------------------------------------------------------------|:----------------------------|:---------------------------|
| 1  | A branch into the middle of an instruction                   | `CheckFrogBounds`, `$0FEE`  | Kept                       |
| 2  | A jump into the middle of `jsr ClearScreen`                  | `$1BE6` to `$296D`          | Kept                       |
| 3  | A hidden exit to `$A800` on RESET with a key combination     | `NmiHandler`                | Kept; crashes on the C64   |
| 4  | The hi-scores live in the alternate character set            | `HISCORES`                  | Kept, same address         |
| 5  | A ninth default hi-score is copied but never shown           | `hiscore_init`              | Kept                       |
| 6  | Five routines nothing calls                                  | `L13A0`, `L1E80` …          | Kept                       |
| 7  | The first note of every in-game tune is never played         | `MusicTick`                 | Kept                       |
| 8  | Zero-page bytes reused under other names                     | `fly_on`, `key_state` …     | Kept                       |
| 9  | "INSTRUCTONS" in the attract prompt                          | `menu_prompt`               | Kept                       |
| 10 | Deaths, homes and menu keys jump out of nested `jsr`s        | `LoseLife`, `CheckMenuKeys` | Kept                       |
| 11 | The `udg_graphics` copy runs past the table                  | `InitGame`                  | Kept                       |
| 12 | With no fly, erasing it writes two spaces to `$0000`–`$0001` | `EraseFly`                  | Redirected (`EraseFlyC64`) |
| 13 | The frog dies at the outer columns, not past them            | `CheckFrogBounds`           | Changed (Remix)            |

---

## Notes

**1.** `CheckFrogBounds` branches to `$0FD6`, one byte into an `inc`. The byte there, `$12`, is an illegal opcode that
locks up an NMOS 6502. It runs only if the frog row reaches 10, which the game should never allow.

**2.** After the hi-score table, the code jumps to `$296D`, one byte into `jsr ClearScreen`. It runs `ORA #$20` / `LDY
#$1A` instead, which is harmless, and skips the screen clear. The source names the target `BadTarget_296D`.

**3.** If `key_state` reads `$28` while `NmiHandler` waits after RESET, it jumps to `DEV_MONITOR` (`$A800`). Nothing is
there on a normal machine; it was probably the author's development monitor. On the C64 `$A800` holds a character set,
so the same keys crash it.

**4.** `HISCORES` is `$BA00`, in the alternate character set's RAM, which the game never shows. A RESET restarts at
`WarmStart` without `ColdStart`'s copy, so the table survives it.

**5.** `ColdStart` copies 255 bytes of `hiscore_init`, nine entries and a bit; `DrawHiScoreTable` and `CheckHiScore` use
eight.

**6.** A print-character routine (`L13A0`), a delay loop (`L1E80`) and three others are complete but never called, and
there are `nop` runs where code was taken out (`$10D5`–`$10FC` in `MainLoop`). They suggest the game was edited in place
in a monitor.

**7.** `MusicTick` moves to the next pair before reading it, so each tune starts on its second pair.

**8.** Several zero-page bytes are named for their main use but borrowed as pointers elsewhere: `fly_on` / `fly_timer`
as a pointer into the hi-score table, `tmp0` / `key_state` as a screen pointer in the menus and the credits. On the C64
`tmp0` and `key_state` moved to `$07` / `$08`, because `$00` / `$01` is the 6510's port.

**10.** `LoseLife` and `FrogHome` `jmp NewLife` from inside `MainLoop`'s `jsr`s, and `NewLife` resets the stack pointer,
so nothing builds up in play. `CheckMenuKeys` jumps to `StartGame` or `AttractLoop` from inside `TitleScroll` without
returning, leaving a return address each time; the stack wraps within page 1 and the game never returns that far, so it
is harmless. The C64's `TitleTickC64` does the same.

**11.** `InitGame` copies 512 bytes from `$0600` to `CHARSET+$5B*8`, though the 37 characters of `udg_graphics` are only
296. The rest, the tables after it, lands past character `$7F`, at the start of the alternate character set (`$B800`),
which the game never shows and which stops short of the hi-scores at `$BA00`.

**12.** `CheckFlyEaten` calls `EraseFly` for every frog that reaches the home row, fly or not, and `EraseFly` stores two
spaces through `fly_ptr`. With no fly showing (always on sheets 1 and 2, and after `SheetComplete`, which clears the
pointer's low byte twice and never its high byte) `fly_ptr` is `$0000`, so the Oric overwrote `tmp0` and `key_state`,
harmlessly. On the C64 `$00`/`$01` is the 6510's port: `$20` in the direction register makes the banking lines inputs,
which float high, so BASIC, KERNAL and I/O switch in and the machine hangs in the KERNAL's interrupt code. `EraseFlyC64`
writes the two spaces to `tmp0` and `key_state` at their C64 addresses instead.

**13.** `frog_col` is one less than the frog's screen column (the frog starts at column 20 with `frog_col` 19), but
`CheckFrogBounds` tests it as if it were the column: the frog dies at `frog_col` 1 or `$25`, that is when it reaches
column 2 (the first playfield column) or covers column 39 (the last). Hops are two columns, so from the start the frog
can make eight hops left (to column 4) and eight right; a ninth looks as if it lands on the visible grass but kills it.
The limits also keep every death inside the playfield: the splat is drawn at `frog_pos`, and at one column further out it
would overwrite a row's paper attribute in column 1. Kept in the Oric build; the C64 Remix lets the frog stand in columns
2–39, blocks hops off the side and kills a carried frog before it moves ([remix.md](remix.md), change 1).
