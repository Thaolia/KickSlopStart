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
EXEC_OBJ  := $(BUILD)/boot.o $(BUILD)/lists.o $(BUILD)/memory.o $(BUILD)/library.o $(BUILD)/tasks.o $(BUILD)/ports.o $(BUILD)/interrupts.o $(BUILD)/resident.o $(BUILD)/libinit.o $(BUILD)/cia.o $(BUILD)/timer.o $(BUILD)/trackdisk.o $(BUILD)/strap.o
# --- piste graphique (M4+) : objets reliés APRÈS exec (boot.o reste premier) ---
GFX_DIR   := src/graphics
GFX_INC   := $(GFX_DIR)/graphics.i
# bootscreen_data.o : palette OCS + incbin des 5 bitplanes de l'écran de boot (généré par mk_bootscreen.py).
GFX_OBJ   := $(BUILD)/gfx.o $(BUILD)/graphics_lib.o $(BUILD)/bootscreen_data.o
# --- piste intuition (M5+) : objets reliés APRÈS graphics ---
INT_DIR   := src/intuition
INT_INC   := $(INT_DIR)/intuition.i
INT_OBJ   := $(BUILD)/intuition_lib.o
# --- piste dos (M6+) : objets reliés APRÈS intuition ---
DOS_DIR   := src/dos
DOS_INC   := $(DOS_DIR)/dos.i
# ofs.o : lecture seule OFS (D1) — s'appuie sur trackdisk CMD_READ (disk.i) ; include exec.i + disk.i + ofs.i.
# loadseg.o : LoadSeg (D2) — charge un exécutable hunk depuis l'OFS + relocation ; include exec.i + ofs.i.
# process.o : Process + CreateProc + dos_sendpkt (D3) ; include exec.i + dospkt.i.
# handler.o : process file-handler DF0: (D3b) ; include exec.i + ofs.i + dospkt.i.
DOS_OBJ   := $(BUILD)/dos_lib.o $(BUILD)/ofs.o $(BUILD)/loadseg.o $(BUILD)/process.o $(BUILD)/handler.o
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
# -I src/dos : boot.s inclut dospkt.i (constantes Process/packet D3 pour le scaffold de preuve).
$(BUILD)/%.o: $(EXEC_DIR)/%.s $(EXEC_INC) | $(BUILD)
	$(VASM) -Fvobj -m68000 -I $(EXEC_DIR) -I $(DOS_DIR) -o $@ $<
# trackdisk.s inclut aussi disk.i (registres disque B2).
$(BUILD)/trackdisk.o: $(EXEC_DIR)/disk.i
# boot.s inclut dospkt.i + dos.i (scaffold de preuve D3, montage DeviceNode) : relier les dépendances.
$(BUILD)/boot.o: $(DOS_DIR)/dospkt.i $(DOS_DIR)/dos.i
# dos_lib.o inclut dospkt.i (D3c : Open/Read/Close via packets) : relier la dépendance.
$(BUILD)/dos_lib.o: $(DOS_DIR)/dospkt.i

# Module(s) graphiques (src/graphics) : include exec.i (ABI/LVO) + graphics.i (registres display).
$(BUILD)/%.o: $(GFX_DIR)/%.s $(EXEC_INC) $(GFX_INC) | $(BUILD)
	$(VASM) -Fvobj -m68000 -I $(EXEC_DIR) -I $(GFX_DIR) -o $@ $<
# bootscreen_data.s fait un incbin de bootscreen.raw : relier la dépendance pour rebuild sur régénération.
$(BUILD)/bootscreen_data.o: $(GFX_DIR)/bootscreen.raw

# Module(s) intuition (src/intuition) : include exec.i (ABI/LVO) + intuition.i (layout IntuitionBase).
$(BUILD)/%.o: $(INT_DIR)/%.s $(EXEC_INC) $(INT_INC) | $(BUILD)
	$(VASM) -Fvobj -m68000 -I $(EXEC_DIR) -I $(INT_DIR) -o $@ $<

# Module(s) dos (src/dos) : include exec.i (ABI/LVO/AllocMem) + dos.i (layout DosLibrary/RootNode/DosInfo, BPTR).
$(BUILD)/%.o: $(DOS_DIR)/%.s $(EXEC_INC) $(DOS_INC) | $(BUILD)
	$(VASM) -Fvobj -m68000 -I $(EXEC_DIR) -I $(DOS_DIR) -o $@ $<
# ofs.o inclut aussi disk.i (CMD_READ) + ofs.i (constantes OFS) : relier les dépendances pour rebuild.
$(BUILD)/ofs.o: $(DOS_DIR)/ofs.i $(EXEC_DIR)/disk.i
# loadseg.o inclut ofs.i (IOREQ/constantes) : relier la dépendance pour rebuild.
$(BUILD)/loadseg.o: $(DOS_DIR)/ofs.i
# process.o inclut dospkt.i : relier la dépendance pour rebuild.
$(BUILD)/process.o: $(DOS_DIR)/dospkt.i
# handler.o inclut ofs.i + dospkt.i : relier les dépendances pour rebuild.
$(BUILD)/handler.o: $(DOS_DIR)/ofs.i $(DOS_DIR)/dospkt.i

# Link à $FC0000 (script) -> binaire brut ; mkrom complète + footer/checksum.
$(BUILD)/kick.bin: $(EXEC_OBJ) $(GFX_OBJ) $(INT_OBJ) $(DOS_OBJ) $(LDSCRIPT)
	$(VLINK) -b rawbin1 -T $(LDSCRIPT) -o $@ $(EXEC_OBJ) $(GFX_OBJ) $(INT_OBJ) $(DOS_OBJ)
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
