# HOPPER (Oric-1) - rebuild the tape image from source and verify it
#   make          build build/HOPPER.TAP
#   make verify   build and compare with original/HOPPER.TAP
#   make run      build and launch in the Auric emulator, Oric-1 mode
#   make debug    as run, with Auric's debugger open
#   make regen    regenerate src/hopper.s from the original (overwrites edits!)
#
# C64 port (docs/porting.md):
#   make c64        build c64/build/hopper.prg
#   make c64-d64    disk image c64/build/hopper.d64
#   make c64-run    build and launch in VICE (x64sc)
#   make c64-diff   list every game byte that differs from the Oric program
#   make c64-smoke  boot headless in VICE, screenshots to c64/build/
#   make c64-intro  redraw the start-up picture (c64/src/intro.rle; Pillow)

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

# --- C64 port ------------------------------------------------------------------
VICE    ?= x64sc
C1541   ?= c1541
C64_SRC := c64/src
C64_BLD := c64/build
C64_CFG := c64/cfg/c64.cfg
# basic_stub first: its jmp Start sits at $080D, the game image right after
C64_MODS := basic_stub hopper platform zp timing video input sound enhanced intro
C64_OBJS := $(addprefix $(C64_BLD)/,$(addsuffix .o,$(C64_MODS)))
C64_INCS := $(wildcard $(C64_SRC)/*.inc)
C64_PRG  := $(C64_BLD)/hopper.prg

IMG_PY  ?= $(shell command -v python3.14 || echo python3)

c64: $(C64_PRG)

$(C64_BLD):
	mkdir -p $@

$(C64_BLD)/%.o: $(C64_SRC)/%.s $(C64_INCS) | $(C64_BLD)
	$(CA65) -I $(C64_SRC) -g -l $(C64_BLD)/$*.lst -o $@ $<

$(C64_PRG): $(C64_OBJS) $(C64_CFG)
	$(LD65) -C $(C64_CFG) -m $(C64_BLD)/hopper.map -Ln $(C64_BLD)/hopper.lbl -o $@ $(C64_OBJS)

$(C64_BLD)/intro.o $(C64_BLD)/test/intro.o $(C64_BLD)/test-enhanced/intro.o: $(C64_SRC)/intro.rle

c64-intro:
	$(IMG_PY) tools/make_intro.py

c64-d64: $(C64_PRG)
	$(C1541) -format "hopper,hp" d64 $(C64_BLD)/hopper.d64 -write $(C64_PRG) "hopper" >/dev/null

c64-run: $(C64_PRG)
	$(VICE) -moncommands $(C64_BLD)/hopper.lbl -autostart $(C64_PRG)

c64-diff: $(C64_PRG) $(TAP)
	python3 tools/c64_diff.py

# Test build with scripted keys (c64/src/autotest.s) for headless screenshots
C64_TBLD := $(C64_BLD)/test
C64_TOBJS := $(addprefix $(C64_TBLD)/,$(addsuffix .o,$(C64_MODS) autotest))
C64_TPRG := $(C64_TBLD)/hopper.prg

$(C64_TBLD):
	mkdir -p $@

$(C64_TBLD)/%.o: $(C64_SRC)/%.s $(C64_INCS) | $(C64_TBLD)
	$(CA65) -I $(C64_SRC) -D AUTOTEST -g -o $@ $<

$(C64_TPRG): $(C64_TOBJS) $(C64_CFG)
	$(LD65) -C $(C64_CFG) -Ln $(C64_TBLD)/hopper.lbl -o $@ $(C64_TOBJS)

# The same script left in Enhanced (no F1 on the home screen)
C64_EBLD := $(C64_BLD)/test-enhanced
C64_EOBJS := $(addprefix $(C64_EBLD)/,$(addsuffix .o,$(C64_MODS) autotest))
C64_EPRG := $(C64_EBLD)/hopper.prg

$(C64_EBLD):
	mkdir -p $@

$(C64_EBLD)/%.o: $(C64_SRC)/%.s $(C64_INCS) | $(C64_EBLD)
	$(CA65) -I $(C64_SRC) -D AUTOTEST -D AUTOTEST_ENHANCED -g -o $@ $<

$(C64_EPRG): $(C64_EOBJS) $(C64_CFG)
	$(LD65) -C $(C64_CFG) -Ln $(C64_EBLD)/hopper.lbl -o $@ $(C64_EOBJS)

c64-smoke: $(C64_TPRG) $(C64_EPRG) $(C64_PRG)
	python3 tools/c64_screens.py --out $(C64_BLD)
	python3 tools/c64_screens.py --out $(C64_BLD) --only intro

.PHONY: all verify run debug regen clean c64 c64-d64 c64-run c64-diff c64-smoke c64-intro
