# Makefile — build des images ROM
#
#   kick  : ROM principale (exec coldstart, M2+) — cible par défaut.
#           chaîne : vasm -Fvobj (un objet par module) -> vlink -> mkrom -> romtool.
#   hello : hello-ROM M0 (écran vert) — smoke test, fichier unique vasm -Fbin.

VASM    ?= vasmm68k_mot
VLINK   ?= vlink
PYTHON  ?= python3
ROMTOOL ?= romtool
# VASMDEF : defines passés à vasm (vide = ROM dev). `make kick-prod` met -DPROD=1 -> variante production
# (sort le harnais de dev du chemin de boot ; cf. src/exec/exec.i). Aucune édition de source requise.
VASMDEF ?=

BUILD   := build
MKROM   := src/rom/mkrom.py

# --- ROM principale : modules exec reliés par vlink ---
EXEC_DIR  := src/exec
EXEC_INC  := $(EXEC_DIR)/exec.i
LDSCRIPT  := $(EXEC_DIR)/kick.ld
# ORDRE LOAD-BEARING : boot.o PREMIER -> son CODE porte l'en-tête à $FC0000.
EXEC_OBJ  := $(BUILD)/boot.o $(BUILD)/lists.o $(BUILD)/memory.o $(BUILD)/library.o $(BUILD)/rawdofmt.o $(BUILD)/tasks.o $(BUILD)/ports.o $(BUILD)/interrupts.o $(BUILD)/resident.o $(BUILD)/libinit.o $(BUILD)/cia.o $(BUILD)/timer.o $(BUILD)/trackdisk.o $(BUILD)/strap.o $(BUILD)/keyboard.o $(BUILD)/input.o $(BUILD)/console.o $(BUILD)/keymap.o $(BUILD)/keymapdata.o $(BUILD)/gameport.o $(BUILD)/expansion.o
# --- piste graphique (M4+) : objets reliés APRÈS exec (boot.o reste premier) ---
GFX_DIR   := src/graphics
GFX_INC   := $(GFX_DIR)/graphics.i
# bootscreen_data.o : palette OCS + incbin des 5 bitplanes de l'écran de boot (généré par mk_bootscreen.py).
GFX_OBJ   := $(BUILD)/gfx.o $(BUILD)/graphics_lib.o $(BUILD)/bootscreen_data.o $(BUILD)/font8x8.o
# loadscreen.o : écran de chargement — démo gatée. Lié UNIQUEMENT quand VASMDEF active LOADSCREEN_DEMO,
# pour que la ROM par défaut reste sans code mort (byte-identique). `make VASMDEF=-DLOADSCREEN_DEMO=1 kick`.
ifneq (,$(findstring LOADSCREEN_DEMO,$(VASMDEF)))
GFX_OBJ   += $(BUILD)/loadscreen.o
endif
# --- piste intuition (M5+) : objets reliés APRÈS graphics ---
INT_DIR   := src/intuition
INT_INC   := $(INT_DIR)/intuition.i
INT_OBJ   := $(BUILD)/intuition_lib.o $(BUILD)/requester.o $(BUILD)/pointer.o
# --- piste dos (M6+) : objets reliés APRÈS intuition ---
DOS_DIR   := src/dos
DOS_INC   := $(DOS_DIR)/dos.i
# ofs.o : lecture seule OFS (D1) — s'appuie sur trackdisk CMD_READ (disk.i) ; include exec.i + disk.i + ofs.i.
# loadseg.o : LoadSeg (D2) — charge un exécutable hunk depuis l'OFS + relocation ; include exec.i + ofs.i.
# process.o : Process + CreateProc + dos_sendpkt (D3) ; include exec.i + dospkt.i.
# handler.o : process file-handler DF0: (D3b) ; include exec.i + ofs.i + dospkt.i.
# conhandler.o : process handler console-série (E1) ; shell.o : shell interactif (E2). include exec.i + dospkt.i.
DOS_OBJ   := $(BUILD)/dos_lib.o $(BUILD)/ofs.o $(BUILD)/loadseg.o $(BUILD)/process.o $(BUILD)/handler.o $(BUILD)/conhandler.o $(BUILD)/shell.o $(BUILD)/diskvalidator.o $(BUILD)/feeder.o
KICK_ROM  := $(BUILD)/kick13.rom

# --- hello-ROM (smoke test M0) ---
HELLO_SRC := src/rom/start.s
HELLO_ROM := $(BUILD)/kick13-hello.rom

.PHONY: all kick kick-prod hello verify clean

all: kick
kick: $(KICK_ROM)
hello: $(HELLO_ROM)

# kick-prod : ROM de PRODUCTION (-DPROD=1) — sort le harnais de dev du chemin de boot (cf. src/exec/exec.i).
# Objets isolés dans build/prod/ (la ROM dev build/*.o reste intacte) ; image finale build/kick13-prod.rom.
kick-prod:
	$(MAKE) BUILD=build/prod VASMDEF=-DPROD=1 KICK_ROM=build/kick13-prod.rom kick

$(BUILD):
	mkdir -p $(BUILD)

# Un objet relogeable (vobj) par module exec ; dépend de l'include partagé.
# -I src/dos : boot.s inclut dospkt.i (constantes Process/packet D3 pour le scaffold de preuve).
$(BUILD)/%.o: $(EXEC_DIR)/%.s $(EXEC_INC) | $(BUILD)
	$(VASM) -Fvobj -m68000 $(VASMDEF) -I $(EXEC_DIR) -I $(DOS_DIR) -o $@ $<
# trackdisk.s inclut aussi disk.i (registres disque B2).
$(BUILD)/trackdisk.o: $(EXEC_DIR)/disk.i
# expansion.s inclut expansion.i (ExpansionBase/ConfigDev/LVO) : relier la dépendance pour rebuild.
$(BUILD)/expansion.o: $(EXEC_DIR)/expansion.i
# boot.s inclut dospkt.i + dos.i (scaffold de preuve D3, montage DeviceNode) : relier les dépendances.
$(BUILD)/boot.o: $(DOS_DIR)/dospkt.i $(DOS_DIR)/dos.i
# dos_lib.o inclut dospkt.i (D3c : Open/Read/Close via packets) : relier la dépendance.
$(BUILD)/dos_lib.o: $(DOS_DIR)/dospkt.i

# Module(s) graphiques (src/graphics) : include exec.i (ABI/LVO) + graphics.i (registres display).
$(BUILD)/%.o: $(GFX_DIR)/%.s $(EXEC_INC) $(GFX_INC) | $(BUILD)
	$(VASM) -Fvobj -m68000 $(VASMDEF) -I $(EXEC_DIR) -I $(GFX_DIR) -o $@ $<
# bootscreen_data.s fait un incbin de bootscreen.raw : relier la dépendance pour rebuild sur régénération.
$(BUILD)/bootscreen_data.o: $(GFX_DIR)/bootscreen.raw
# loadscreen.o (écran de chargement) inclut aussi ofs.i (src/dos, streaming) -> règle dédiée avec -I src/dos.
$(BUILD)/loadscreen.o: $(GFX_DIR)/loadscreen.s $(EXEC_INC) $(GFX_INC) $(DOS_DIR)/ofs.i | $(BUILD)
	$(VASM) -Fvobj -m68000 $(VASMDEF) -I $(EXEC_DIR) -I $(GFX_DIR) -I $(DOS_DIR) -o $@ $<

# Module(s) intuition (src/intuition) : include exec.i (ABI/LVO) + intuition.i (layout IntuitionBase).
$(BUILD)/%.o: $(INT_DIR)/%.s $(EXEC_INC) $(INT_INC) | $(BUILD)
	$(VASM) -Fvobj -m68000 $(VASMDEF) -I $(EXEC_DIR) -I $(INT_DIR) -o $@ $<

# Module(s) dos (src/dos) : include exec.i (ABI/LVO/AllocMem) + dos.i (layout DosLibrary/RootNode/DosInfo, BPTR).
$(BUILD)/%.o: $(DOS_DIR)/%.s $(EXEC_INC) $(DOS_INC) | $(BUILD)
	$(VASM) -Fvobj -m68000 $(VASMDEF) -I $(EXEC_DIR) -I $(DOS_DIR) -o $@ $<
# ofs.o inclut aussi disk.i (CMD_READ) + ofs.i (constantes OFS) : relier les dépendances pour rebuild.
$(BUILD)/ofs.o: $(DOS_DIR)/ofs.i $(EXEC_DIR)/disk.i
$(BUILD)/diskvalidator.o: $(DOS_DIR)/ofs.i $(EXEC_DIR)/disk.i
# loadseg.o inclut ofs.i (IOREQ/constantes) : relier la dépendance pour rebuild.
$(BUILD)/loadseg.o: $(DOS_DIR)/ofs.i
# process.o inclut dospkt.i : relier la dépendance pour rebuild.
$(BUILD)/process.o: $(DOS_DIR)/dospkt.i
# handler.o inclut ofs.i + dospkt.i : relier les dépendances pour rebuild.
$(BUILD)/handler.o: $(DOS_DIR)/ofs.i $(DOS_DIR)/dospkt.i
# conhandler.o inclut dospkt.i (E1) ; shell.o inclut dospkt.i (E2) : relier les dépendances pour rebuild.
$(BUILD)/conhandler.o: $(DOS_DIR)/dospkt.i
$(BUILD)/shell.o: $(DOS_DIR)/dospkt.i

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
