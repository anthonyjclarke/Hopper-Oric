# Hopper – Sound

Read from the code. The Oric plays everything on its AY-3-8912 through `AYWrite`; the C64 plays the same register writes
on the SID ([C64 Playback](#c64-playback)). There are no recordings yet.

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
