AS6801 ?= as6801
VASM ?= vasmm68k_mot
PYTHON ?= python3
OUT := build/torchdiag_6303_pale_green_v09.rom
.PHONY: all clean
all: $(OUT)
build/standalone6303.lst: src/standalone6303.asm
	@mkdir -p build
	cp $< build/standalone6303.asm
	cd build && $(AS6801) -l -o standalone6303.asm
build/6303-base.rom: build/standalone6303.lst tools/listing_to_rom.py
	$(PYTHON) tools/listing_to_rom.py $< $@
build/bootstrap68010.bin: src/bootstrap68010.asm
	@mkdir -p build
	$(VASM) -m68010 -Fbin -L build/bootstrap68010.lst -o $@ $<
$(OUT): build/6303-base.rom build/bootstrap68010.bin assets/torch8x8.bin tools/embed_bootstrap.py
	$(PYTHON) tools/embed_bootstrap.py build/6303-base.rom build/bootstrap68010.bin assets/torch8x8.bin $@
clean:
	rm -f build/*
