# HOPPER (Oric-1) - rebuild the tape image from source and verify it
#   make          build build/HOPPER.TAP
#   make verify   build and compare with original/HOPPER.TAP
#   make run      build and launch in the Auric emulator, Oric-1 mode
#   make debug    as run, with Auric's debugger open
#   make regen    regenerate src/hopper.s from the original (overwrites edits!)

CA65  ?= ca65
LD65  ?= ld65
AURIC_DIR ?= $(HOME)/PlatformIO/Projects/Auric

SRC   := src/hopper.s
INCS  := src/oric.inc src/vars.inc
TAP   := build/HOPPER.TAP

all: $(TAP)

build:
	mkdir -p build

build/hopper.o: $(SRC) $(INCS) | build
	$(CA65) -I src -g -l build/hopper.lst -o $@ $(SRC)

$(TAP): build/hopper.o hopper.cfg
	$(LD65) -C hopper.cfg -m build/hopper.map -Ln build/hopper.lbl -o $@ build/hopper.o

verify: $(TAP)
	@cmp $(TAP) original/HOPPER.TAP && echo "OK: $(TAP) is byte-identical to original/HOPPER.TAP"

# Auric reads auric.yaml and ROMS/ from its working directory
run: $(TAP)
	cd "$(AURIC_DIR)" && ./build/src/auric --oric1 --tape "$(abspath $(TAP))"

debug: $(TAP)
	cd "$(AURIC_DIR)" && ./build/src/auric --oric1 --monitor --tape "$(abspath $(TAP))"

regen:
	python3 tools/gen_source.py original/HOPPER.TAP $(SRC)

clean:
	rm -rf build

.PHONY: all verify run debug regen clean
