# Hopper – Sound

Read from the code. The Oric plays everything on its AY-3-8912 through `AYWrite`; the C64 plays the same register writes
on the SID ([C64 Playback](#c64-playback)). The [recordings](#recordings) are of the C64 port in VICE.

---

## The Sound Option

Every effect and tune goes through `SoundWrite`, which applies the choice made on the sound menu (`sound_mode`):

| `sound_mode` | Menu | Does                                            |
|:-------------|:-----|:------------------------------------------------|
| 0            | 1    | No write: silence                               |
| 1            | 2    | The value as given                              |
| 2            | 3    | Writes to the volume registers 8–10 are doubled |

The volumes the game writes go up to 7 (the low-time tone), mostly 2–4, so doubled they still fit the AY's 0–15; it
never uses the AY's envelope generator. `SilenceAll` sets the three volumes to 0; `LoadAYRegs` writes all 14 registers
from a table (`ay_game_regs` at the start of play, `ay_quiet_regs` to stop).

---

## Effects

| Effect     | Routine         | How                                                           |
|:-----------|:----------------|:--------------------------------------------------------------|
| Hop        | `ServiceTimer`  | Ten steps of `hop_pitches` on channel A, one per timer period |
| Fly warble | `FlyWarble`     | A rising and falling tone while the fly shows                 |
| Fly bonus  | `FlyBonus`      | A beep from `bonus_pitches` for each 100 points counted in    |
| Frog home  | `HomeJingle`    | A short jingle                                                |
| Time bonus | `TimeBonus`     | A beep for each unit of TIME counted into the score           |
| Low time   | `CheckTimeLow`  | A short tone each time unit once TIME is below 10             |
| Death      | `DeathSequence` | A falling tone with the squashed frog and the flashing screen |
| Title frog | `CreditsEnd`    | The jingle when the credits frog reaches its place            |

---

## Music

**In-game tunes.** Four tunes at `tune_ptrs`; `PickTune` picks one at random at the start of a sheet and after each
death, and `MusicTick` steps it once per main-loop pass on one channel. Each note is a pair: the note (1–12, 0 = rest)
and the octave in the high nibble with the length in the low one. The tone period is `note_periods` (one octave) shifted
right once per octave. `tune_params` gives each tune's tempo and length.

**Sheet tune.** `PlaySheetTune` plays `sheet_tune` under the sheet-start signs: 29 steps of three bytes, one note per
channel, with the step lengths in `sheet_tune_lens`.

The data layouts are in [data_formats.md](data_formats.md#sound).

---

## C64 Playback

`AyWriteC64` replaces `AYWrite` (the patch is at `$1FAD`): it keeps a copy of the 14 AY registers and drives SID voices
1–3 from them.

| AY                               | SID                                                             |
|:---------------------------------|:----------------------------------------------------------------|
| Tone period P (12 bits)          | Frequency 1064276 / P (PAL) or 1025275 / P (NTSC); P < 4 silent |
| Mixer: tone or noise per channel | Pulse 50% or noise waveform; neither = gate off                 |
| Volume 0–15 per channel          | The voice's sustain level, with the shortest envelope           |
| A louder volume                  | Retriggers the envelope                                         |
| A softer volume                  | Lets the voice decay to the new sustain level                   |

The SID has one master volume, so the per-channel levels become sustain levels. Not yet checked by ear against the Oric
([porting.md](porting.md#sound)).

---

## Recordings

Recorded from the C64 port in VICE (PAL, reSID, loud sound) by `make c64-sound` (`tools/c64_sound.py`), so they are
what the AY's register writes sound like on the SID, not the Oric itself. The sound build plays the four in-game tunes
in order instead of at random (`AUTOTEST_SOUND`); everything else is the game as it runs.

| Recording         | What it is                                   |
|:------------------|:---------------------------------------------|
| `tune-0`–`3`      | The in-game tunes, `tune_ptrs` order         |
| `tune-sheet`      | `PlaySheetTune`, under the sheet-start signs |
| `effect-jingle`   | `HomeJingle`, as `CreditsEnd` plays it       |
| `effect-hop`      | One hop (`ServiceTimer`), over tune 0        |
| `effect-death`    | `DeathSequence`, TIME run out                |
| `effect-low-time` | `CheckTimeLow`'s tone over a tune            |

![Tune 0](sound/tune-0.m4a)

![Tune 1](sound/tune-1.m4a)

![Tune 2](sound/tune-2.m4a)

![Tune 3](sound/tune-3.m4a)

![The sheet tune](sound/tune-sheet.m4a)

![The frog-home jingle (the credits' title frog)](sound/effect-jingle.m4a)

![A hop](sound/effect-hop.m4a)

![Death](sound/effect-death.m4a)

![Low time](sound/effect-low-time.m4a)

Not recorded yet: the fly's warble and bonus beeps and the time bonus, which need a frog in a home (the sound build's
frog sits on the verge). The first note of each tune is never played ([quirks.md](quirks.md)), so each recording starts
on its second.
