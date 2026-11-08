# Changelog

## [1.0] 08-11-2026

### Added

- Full ca65 source for HOPPER (`src/hopper.s`) reconstructed from `original/HOPPER.TAP`, with named routines, variables and data, and character graphics shown as pixel art.
- Hardware and variable include files (`src/oric.inc`, `src/vars.inc`).
- ld65 config that writes a complete TAP file, and a `Makefile` with `build`, `verify`, `run`, `debug` and `regen` targets.
- Disassembly tools: `tools/gen_source.py`, `tools/annotations.py`, `tools/m6502.py`, `tools/dis_range.py`.
- VS Code tasks, ca65 syntax association and extension recommendation.
- README describing the build, Auric setup, findings and memory map.
