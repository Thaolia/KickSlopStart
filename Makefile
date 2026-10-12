# Makefile — build des images ROM (chaîne vasm -> mkrom -> romtool)
#
#   kick  : ROM principale (exec coldstart, M2+) — cible par défaut.
#   hello : hello-ROM M0 (écran vert) — smoke test de la chaîne.
# vlink entrera quand plusieurs objets relogeables (C + asm) devront être liés.

VASM    ?= vasmm68k_mot
PYTHON  ?= python3
ROMTOOL ?= romtool

BUILD   := build
MKROM   := src/rom/mkrom.py

HELLO_SRC := src/rom/start.s
HELLO_ROM := $(BUILD)/kick13-hello.rom
KICK_SRC  := src/exec/coldstart.s
KICK_ROM  := $(BUILD)/kick13.rom

.PHONY: all kick hello verify clean

all: kick
kick: $(KICK_ROM)
hello: $(HELLO_ROM)

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/kick.bin: $(KICK_SRC) | $(BUILD)
	$(VASM) -Fbin -m68000 -o $@ $<
$(KICK_ROM): $(BUILD)/kick.bin $(MKROM)
	$(PYTHON) $(MKROM) --in $< --out $@ --size 256

$(BUILD)/hello.bin: $(HELLO_SRC) | $(BUILD)
	$(VASM) -Fbin -m68000 -o $@ $<
$(HELLO_ROM): $(BUILD)/hello.bin $(MKROM)
	$(PYTHON) $(MKROM) --in $< --out $@ --size 256

verify: $(KICK_ROM)
	@sz=$$(stat -c%s $(KICK_ROM)); \
	 if [ "$$sz" = "262144" ]; then echo "taille OK : 262144 o"; \
	 else echo "ECHEC taille : $$sz != 262144"; exit 1; fi
	@if command -v $(ROMTOOL) >/dev/null; then \
	   info=$$($(ROMTOOL) info $(KICK_ROM)); echo "$$info"; \
	   if echo "$$info" | grep -qE '^is_kick[[:space:]]+ok' \
	   && echo "$$info" | grep -qE '^chk_sum[[:space:]]+ok'; then \
	     echo "romtool OK : is_kick + chk_sum"; \
	   else echo "ECHEC romtool : is_kick/chk_sum != ok"; exit 1; fi; \
	 else echo "note : $(ROMTOOL) absent — gate romtool sautée"; fi

clean:
	rm -rf $(BUILD)
