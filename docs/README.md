# Hopper – Documentation

These chapters cover the Commodore 64 version of *Hopper*, the *Frogger*-style game I wrote for the Oric-1 and PSS
published on tape in 1983. The C64 version runs the Oric game code, every byte at its Oric address, on a small platform
layer, and comes in two looks, Classic and Enhanced. The Oric original is kept alongside it: the tape,
`original/HOPPER.TAP`, and its full commented ca65 source in `src/`, which `make verify` assembles back into a
byte-identical tape for any Oric emulator (`make run` starts it in Auric). The [project README](../README.md)
introduces the game.

**[HOPPER.html](HOPPER.html)** gathers every document below into one page, with the images and audio embedded, so it
reads offline in a browser.

---

## The Game and Its Code

| Document                                   | Covers                                                       |
|:-------------------------------------------|:-------------------------------------------------------------|
| [player_guide.md](player_guide.md)         | The rules: menus, controls, the river and road, scoring      |
| [original_release.md](original_release.md) | The PSS cassette cover and the PSS advert                    |
| [graphics.md](graphics.md)                 | Oric screens and glyphs decoded from the tape; C64 captures  |
| [sound.md](sound.md)                       | The AY effects and tunes, the SID, and recordings to play    |
| [architecture.md](architecture.md)         | Boot, memory map, the main loop, timing, both machines       |
| [data_formats.md](data_formats.md)         | Every table: lanes, keys, tunes, text, hi-scores, the status |
| [source_guide.md](source_guide.md)         | Repository layout, toolchain, build targets, conventions     |

---

## Reference

| Document                                       | Covers                                                 |
|:-----------------------------------------------|:-------------------------------------------------------|
| [porting.md](porting.md)                       | The C64 port: approach, memory map, decisions, status  |
| [remix.md](remix.md)                           | C64 Remix: every deliberate change from the original   |
| [platform_layer.md](platform_layer.md)         | The C64 platform layer, module by module               |
| [quirks.md](quirks.md)                         | Places where the original does something unintended    |
| [CHANGELOG.md](../CHANGELOG.md)                | Release history                                        |
| [html_documentation.md](html_documentation.md) | Regenerating the figures, screenshots and the handbook |
| [credits.md](credits.md)                       | Who made the game and this repository; tools and links |

---

## C64 Enhanced

Enhanced is the C64 version's second look, chosen with F1 on the instructions page. It's the same game, using more of
the C64's hardware.

| Document                                     | Covers                                                   |
|:---------------------------------------------|:---------------------------------------------------------|
| [enhanced.md](enhanced.md)                   | Overview, ground rules, the version switch, plan of work |
| [enhanced_graphics.md](enhanced_graphics.md) | Lanes, sprites, markings, scrolling, font, instructions  |
| [enhanced_sound.md](enhanced_sound.md)       | SID voicing of the tunes, effects, a title tune          |
| [enhanced_platform.md](enhanced_platform.md) | Version flag, hooks, raster interrupt, memory, testing   |

---

## Appendix

| Document                           | Covers                                                    |
|:-----------------------------------|:----------------------------------------------------------|
| [oric_history.md](oric_history.md) | History of Oric: Tangerine, the models, clones, community |
| [oric_specs.md](oric_specs.md)     | Oric Tech Specs: hardware, graphics, sound, emulators     |

Oric names and addresses follow the reconstruction ([`src/hopper.s`](../src/hopper.s),
[`src/vars.inc`](../src/vars.inc), [`src/oric.inc`](../src/oric.inc)). C64 names follow `c64/src/`. Where a C64 routine
replaces an Oric one, it carries the Oric name with a `C64` suffix (`ReadKeys` becomes `ReadKeysC64`).
