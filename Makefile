# Makefile — hello-ROM M0 (chaîne vasm -> mkrom -> romtool)
#
# vlink n'entre qu'au M2 (quand plusieurs modules relogeables devront être
# liés et placés) ; au M0 une section absolue unique se produit en -Fbin.

VASM    ?= vasmm68k_mot
PYTHON  ?= python3
ROMTOOL ?= romtool

BUILD   := build
SRC     := src/rom

HELLO_BIN := $(BUILD)/hello.bin
HELLO_ROM := $(BUILD)/kick13-hello.rom

.PHONY: all hello verify clean toolcheck

all: hello

toolcheck:
	@command -v $(VASM)    >/dev/null || { echo "manquant : $(VASM) (voir README, build vasm)"; exit 1; }
	@command -v $(ROMTOOL) >/dev/null || echo "note : $(ROMTOOL) absent — 'make verify' partiel"

hello: $(HELLO_ROM)

$(HELLO_BIN): $(SRC)/start.s | $(BUILD)
	$(VASM) -Fbin -m68000 -o $@ $<

$(HELLO_ROM): $(HELLO_BIN) $(SRC)/mkrom.py
	$(PYTHON) $(SRC)/mkrom.py --in $(HELLO_BIN) --out $@ --size 256

$(BUILD):
	mkdir -p $(BUILD)

verify: $(HELLO_ROM)
	@sz=$$(stat -c%s $(HELLO_ROM)); \
	 if [ "$$sz" = "262144" ]; then echo "taille OK : 262144 o"; \
	 else echo "ECHEC taille : $$sz != 262144"; exit 1; fi
	@command -v $(ROMTOOL) >/dev/null && { echo "--- romtool info ---"; $(ROMTOOL) info $(HELLO_ROM) || true; } || true

clean:
	rm -rf $(BUILD)
