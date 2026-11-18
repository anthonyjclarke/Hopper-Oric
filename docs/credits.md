# Hopper – Credits and Links

---

## The Game

*Hopper* for the Oric-1 was written by A.J. Clarke and published by PSS (Personal Software Services, Coventry) in 1983.
The game's own credits read `AUTHOR A.J.CLARKE`, `ALL RIGHTS RESERVED`, `P.S.S., 452 STONEY STANTON ROAD, COVENTRY CV6
5DG`, under "PERSONAL SOFTWARE SERVICES PRESENTS"; the default hi-score name is `P.S.S.`. The cover painting and the
inlay are PSS's ([original_release.md](original_release.md)); the artist is not yet credited here.

The game's page on oric.org, the Oric software library: [Hopper](https://www.oric.org/software/hopper-1427.html).

---

## The Reconstruction

The source reconstruction, its annotations, the C64 port and these documents are Anthony Clarke's project; the details
of who did what are for the owner to fill in.

---

## The Documentation

These chapters and the handbook follow the documentation format of Anthony's C64 reconstructions (*Light Cycle*,
*Frak!*, *Thing On A Spring*). The handbook generator and templates are carried over from those repositories unchanged.

---

## Tools

| Tool                                     | Use                                      |
|:-----------------------------------------|:-----------------------------------------|
| [cc65](https://cc65.github.io/)          | `ca65`, `ld65`                           |
| [Auric](https://github.com/pugo/Auric)   | Oric-1 emulation                         |
| [oric.org](https://www.oric.org/)        | Oric software library: the game's entry  |
| [VICE](https://vice-emu.sourceforge.io/) | `x64sc` emulation and captures, `c1541`  |
| [Python](https://www.python.org/)        | Disassembly, checks, figures, captures   |
| [Pillow](https://python-pillow.org/)     | The figures and the C64 start-up picture |
| [Node.js](https://nodejs.org/)           | Handbook generation                      |

---

## Libraries and Fonts

[Marked](https://marked.js.org/) 17.0.5 converts the Markdown and [Mermaid](https://mermaid.js.org/) 10.9.3 draws the
diagrams; both are vendored with their licences in `docs/tools/vendor/`. The handbook's C64 font option uses Style's
[C64 TrueType](https://style64.org/c64-truetype) fonts, embedded unmodified as their licence allows.

---

## Playing the Original

`original/HOPPER.TAP` runs in an Oric emulator in **Oric-1** mode (the game uses the Oric-1 ROM's addresses): Auric with
`basic10.rom` (`make run`), or Oricutron with the Oric-1 ROM. The C64 version is `c64/build/hopper.prg`, or `hopper.d64`
(`make c64-d64`).
