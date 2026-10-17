; src/exec/expansion.i — expansion.library (autoconfig) : ExpansionBase + ConfigDev. ABI publique.
; Offsets LVO confirmés sur AROS rom/expansion/expansion.conf (OpenLib slot0, AddConfigDev slot4 = -30,
; AllocConfigDev slot7 = -48, FindConfigDev slot11 = -72, FreeConfigDev slot13 = -84 ; LVO = -6*(slot+1)).
; Piste IMPLÉMENTATION (« clean ») : AutoDocs expansion.library + NDK libraries/configregs.i/configvars.i. AUCUNE lecture ROM.

                ifnd    EXPANSION_I
EXPANSION_I     equ     1

; --- ExpansionBase (sous-ensemble V34) : Library + eb_Flags + liste des ConfigDev ---
; eb_Flags à l'offset 34 (= LIB_SIZE) : le bootblock Lemmings y pose bit 6 SI OpenLibrary("expansion.library",37)
; réussit — ce qui n'arrive PAS sur notre ROM V34 (gate de version renvoie 0), donc il n'écrit jamais ici.
EB_FLAGS           EQU LIB_SIZE        ; 34 : UBYTE (+ pad)
EB_CONFIGLIST      EQU LIB_SIZE+4      ; 38 : struct List des ConfigDev (Add/Find/FreeConfigDev)
EXPANSIONBASE_SIZE EQU LIB_SIZE+4+14   ; 52 : dataSize pour MakeLibrary

; --- struct ConfigDev + ExpansionRom (libraries/configregs.i) — sous-ensemble pour Add/Find/FreeConfigDev ---
CD_NODE        EQU 0              ; struct Node (14) : chaînage dans EB_CONFIGLIST
CD_FLAGS       EQU 14             ; UBYTE
CD_PAD         EQU 15            ; UBYTE
CD_ROM         EQU 16            ; struct ExpansionRom embarquée
ER_TYPE        EQU CD_ROM+0       ; UBYTE
ER_PRODUCT     EQU CD_ROM+1       ; UBYTE — critère FindConfigDev (product ; -1 = wildcard)
ER_FLAGS       EQU CD_ROM+2       ; UBYTE
ER_MANUFACTURER EQU CD_ROM+4      ; UWORD — critère FindConfigDev (manufacturer ; -1 = wildcard)
CD_SIZEOF      EQU 68             ; sizeof(struct ConfigDev) — AllocConfigDev alloue ça (MEMF_CLEAR)

; --- LVO expansion.library (expansion_lib.fd / AROS expansion.conf) ---
EXP_LVO_ADDCONFIGDEV   EQU -30    ; AddConfigDev(configDev a0)
EXP_LVO_ALLOCCONFIGDEV EQU -48    ; AllocConfigDev() -> d0 = ConfigDev* | 0
EXP_LVO_FINDCONFIGDEV  EQU -72    ; FindConfigDev(oldConfigDev a0, manufacturer d0, product d1) -> d0 = cd | 0
EXP_LVO_FREECONFIGDEV  EQU -84    ; FreeConfigDev(configDev a0)

; EXP_NO_ENQUEUE=1 (RED) : AddConfigDev N'AJOUTE PAS le ConfigDev à EB_CONFIGLIST -> FindConfigDev ne le trouve
; jamais -> « EXPANSION OK » absent (AllocConfigDev + l'ouverture de la lib restent OK). Isole le câblage de la
; liste ConfigDev (le cœur de l'autoconfig). Défaut 0.
EXP_NO_ENQUEUE EQU 0

                endc
