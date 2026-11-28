# Hopper – Credits and Links

---

## The Game

I wrote *Hopper* for the Oric-1, as A.J. Clarke, and PSS (Personal Software Services, Coventry) published it in 1983.
The game's own credits read `AUTHOR A.J.CLARKE`, `ALL RIGHTS RESERVED`, `P.S.S., 452 STONEY STANTON ROAD, COVENTRY CV6
5DG`, under "PERSONAL SOFTWARE SERVICES PRESENTS", and the default hi-score name is `P.S.S.`. The cover painting and
the inlay are PSS's ([original_release.md](original_release.md)); I haven't credited the artist here yet.

The game has a page on oric.org, the Oric software library: [Hopper](https://www.oric.org/software/hopper-1427.html).

---

## The Reconstruction

The source reconstruction, its annotations, the C64 port and these documents are my project; the details of who did
what are still for me to fill in.

---

## The Restoration Toolkit

I restore my own 1980s games with a private toolkit, *Old Code Restoration* (OldCode_Restoration). It covers two
machines, the Commodore C16 and the Oric-1, and holds the shared tools, a user guide, the commissioning briefs and the
`retro-restoration` skill for Claude Code. `new_project.py` copies the tools a game needs into its own `tools/` folder,
so each repository builds without the toolkit.

The toolkit grew out of the games themselves. It began in January 2026 with *Dork's Dilemma* for the C16. That first
attempt converted a 1992 text export of the source, and although it assembled, the game never started. In October 2026
the original disks were captured again with ZoomFloppy and OpenCBM. A new pipeline read the disk image directly, converted
the assembler syntax without fixing anything and compared every byte. It matched the original on 20 October 2026, and I
then used it for *Tycoon Tex*, *Xargon Wars* and *Xargon's Revenge*.

The Oric games came next, in November 2026. Only their cassettes survive, so the job was disassembly rather than a
rebuild from source. *Hopper* was first, as one tape block, and *Light Cycle* followed as a BASIC stub plus the game.
On 20 and 22 November 2026 I wrote what the two games had taught me back into the toolkit:

- the tape format and the Oric-1 ROM workspace both games use;
- the AY wiring and the two disassembly pipelines;
- the build gotchas;
- the habits the two games share.

The same pass added an Oric brief, written for *The Ultra* and *Oric-Mon*, which are next.

The toolkit's method borrows from two MIT-licensed projects:

- David Youd's [retro-archaeology-skills](https://github.com/c64cryptoboy/retro-archaeology-skills): the disassembly
  invariants, routine contracts, behaviour classes and 6502 helper scripts;
- Dave Agent's [MOSaic](https://github.com/Dave-Agent/MOSaic): the evidence ladder, the variable-role protocol and
  working in slices.

The C16 disks were read with [OpenCBM](https://github.com/OpenCBM/OpenCBM), the GPLv2 suite of drivers and tools for
Commodore serial drives. Its maintainers are Spiro Trikaliotis and RETRO Innovations (`go4retro`), and OpenCBM is the
successor of cbm4linux. The disks went through a [ZoomFloppy](https://github.com/go4retro/ZoomFloppy), the USB
interface designed by Nate Lawson and made by RETRO Innovations, whose schematic and PCB are released under CC BY-SA
4.0.

The toolkit's own tools build on [cc65](https://cc65.github.io/), [VICE](https://vice-emu.sourceforge.io/) and
[Auric](https://github.com/pugo/Auric). The user guide is rendered with [Marked](https://marked.js.org/) 17.0.5.

---

## The Documentation

These chapters and the handbook follow the documentation format of my other reconstructions ([*Light
Cycle*](https://github.com/anthonyjclarke/Light-Cycle-Oric), *Frak!*, *Thing On A Spring*). The handbook generator and
templates are carried over from those repositories unchanged.

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

`original/HOPPER.TAP` runs in an Oric emulator in **Oric-1** mode, because the game uses the Oric-1 ROM's addresses.
That means Auric with `basic10.rom` (`make run`), or Oricutron with the Oric-1 ROM. The C64 version is
`c64/build/hopper.prg`, or `hopper.d64` (`make c64-d64`).
