# Hopper – Enhanced Sound

The sound changes in the C64 Enhanced version ([enhanced.md](enhanced.md)). All are planned; none is built yet.
The game's sound code is unchanged: it still writes AY registers through `AYWrite`, which the port replaces with
`AyWriteC64` ([sound.md](sound.md#c64-playback)). Enhanced changes only how those writes become SID sound. In Classic
the SID plays exactly as in the port.

---

## Today's Playback

The port turns every AY channel into a SID voice with a 50% pulse (or noise), the AY volume as the sustain level and the
shortest envelope. That is faithful but plain: the AY had no envelopes in this game and no filter, so neither does the
port. The notes, lengths and timing are right, and Enhanced keeps them exactly.

Which channel does what, read from the registers each routine writes:

| AY channel | SID voice | Used by                                                                    |
|:-----------|:----------|:---------------------------------------------------------------------------|
| A          | 1         | Hop (`ServiceTimer`), time bonus (`TimeBonus`), sheet tune                 |
| B          | 2         | Fly warble (`FlyWarble`), fly bonus, low time (`CheckTimeLow`), sheet tune |
| C          | 3         | In-game tunes (`MusicTick`), frog home (`HomeJingle`), sheet tune          |

---

## S1 – SID Voicing of the AY Tunes

**What changes.** The same notes get instruments. Voice 3 carries the in-game tunes, so it gets a lead sound: a pulse
whose width sweeps slowly, with a short attack and a gentle release, so repeated notes are separate instead of running
together. Under the sheet tune ([sound.md](sound.md#music)) the lowest of the three parts goes through the SID's
low-pass filter as a bass, and the other two keep a brighter pulse.

**How it works.** `AyWriteC64` already keeps a copy of the 14 AY registers and drives each voice from them. Enhanced
adds a small table of instruments, one per voice and context: waveform, pulse width and its sweep, attack/decay/release,
and whether the voice is filtered. The context is known from where the platform already is: the sheet tune is played
between `DrawScenery` and the start of play, and the in-game tunes and effects during play. The sustain level still
follows the AY volume, so the game's quiet and loud passages and the sound menu's "loud" option still work.

**Cost.** About 0.5 KB for the table and the pulse-width sweep, which runs in the frame interrupt.

---

## S2 – SID Sound Effects

**What changes.** The effects keep their triggers and pitches, and each gets its own SID patch:

| Effect     | Today                | Enhanced                                            |
|:-----------|:---------------------|:----------------------------------------------------|
| Hop        | Pulse steps, voice 1 | Short triangle blip with a fast pitch drop          |
| Fly warble | Pulse, voice 2       | Thin pulse with vibrato                             |
| Frog home  | Jingle, voice 3      | Same notes, bell-like: triangle with a long release |
| Low time   | Pulse tone, voice 2  | Same tone, ring-modulated                           |
| Death      | Falling pulse tone   | Falling tone through a closing low-pass filter      |
| Splash     | (same as death)      | Noise burst, filtered, when the frog drowns         |

The splash is the only new trigger. The platform can tell a drowning from a squash because the frog's row is known
(`frog_row` 5–8 is the river), so it needs no game change.

**Cost.** About 0.4 KB.

---

## S3 – Title Tune

**What changes.** A short SID tune for the home screen and attract loop. The original has no title music, so to stay
close to the game it would be arranged from the sheet tune rather than written fresh. It is the least "subtle" option
and an open question in [enhanced.md](enhanced.md#questions).

**How it works.** A small player in the frame interrupt, running only on the home screen, credits and picture, and
silent when a game starts. The tune and player go in `$9000`–`$9FFF`, which the CPU can use freely
([enhanced_platform.md](enhanced_platform.md#memory)).

**Cost.** About 2.5 KB with the player.

---

## Checking by Ear

Headless VICE has no sound, so `make c64-smoke` can't test any of this. Each change is checked by ear in VICE against
the port's own playback, which itself is still waiting for its first check against the Oric in Auric
([porting.md](porting.md#status)). When recordings exist they go in `docs/sound/` and are embedded here.
