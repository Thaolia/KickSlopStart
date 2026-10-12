# Makefile — build des images ROM
#
#   kick  : ROM principale (exec coldstart, M2+) — cible par défaut.
#           chaîne : vasm -Fvobj (un objet par module) -> vlink -> mkrom -> romtool.
#   hello : hello-ROM M0 (écran vert) — smoke test, fichier unique vasm -Fbin.

VASM    ?= vasmm68k_mot
VLINK   ?= vlink
PYTHON  ?= python3
ROMTOOL ?= romtool

BUILD   := build
MKROM   := src/rom/mkrom.py

# --- ROM principale : modules exec reliés par vlink ---
EXEC_DIR  := src/exec
EXEC_INC  := $(EXEC_DIR)/exec.i
LDSCRIPT  := $(EXEC_DIR)/kick.ld
# ORDRE LOAD-BEARING : boot.o PREMIER -> son CODE porte l'en-tête à $FC0000.
EXEC_OBJ  := $(BUILD)/boot.o $(BUILD)/lists.o $(BUILD)/memory.o $(BUILD)/library.o
KICK_ROM  := $(BUILD)/kick13.rom

# --- hello-ROM (smoke test M0) ---
HELLO_SRC := src/rom/start.s
HELLO_ROM := $(BUILD)/kick13-hello.rom

.PHONY: all kick hello verify clean

all: kick
kick: $(KICK_ROM)
hello: $(HELLO_ROM)

$(BUILD):
	mkdir -p $(BUILD)

# Un objet relogeable (vobj) par module exec ; dépend de l'include partagé.
$(BUILD)/%.o: $(EXEC_DIR)/%.s $(EXEC_INC) | $(BUILD)
	$(VASM) -Fvobj -m68000 -I $(EXEC_DIR) -o $@ $<

# Link à $FC0000 (script) -> binaire brut ; mkrom complète + footer/checksum.
$(BUILD)/kick.bin: $(EXEC_OBJ) $(LDSCRIPT)
	$(VLINK) -b rawbin1 -T $(LDSCRIPT) -o $@ $(EXEC_OBJ)
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
