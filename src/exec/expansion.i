; src/exec/expansion.i — expansion.library (autoconfig Zorro II) : ExpansionBase V34, ConfigDev, DiagArea. ABI publique.
; Offsets LVO : expansion_lib.fd / AROS rom/expansion/expansion.conf (LVO = -6*(slot+1)).
; Piste IMPLÉMENTATION (« clean ») : AutoDocs expansion.library + NDK libraries/configregs.i/configvars.i/expansionbase.i
; + spec docs/analysis/autoconfig-v34.md. AUCUNE lecture ROM.

                ifnd    EXPANSION_I
EXPANSION_I     equ     1

; --- struct ExpansionBase (V34, dataSize du résident) ---
EB_FLAGS           EQU $22             ; UBYTE : EBB_CLOGGED (bit 0), EBB_SHORTMEM (bit 1)
EB_EXECBASE        EQU $24
EB_SEGLIST         EQU $28
EB_BINDING         EQU $2C             ; struct CurrentBinding (16 octets)
EB_BOARDLIST       EQU $3C             ; struct List des ConfigDev
EB_MOUNTLIST       EQU $4A             ; struct List des BootNodes (AddDosNode sans dos.library)
EB_ALLOCTABLE      EQU $58             ; 256 octets, un par slot de 64 Ko : ≠ 0 libre, 0 pris / indisponible
EB_BINDSEM         EQU $158            ; struct SignalSemaphore (Obtain/ReleaseConfigBinding)
EXPANSIONBASE_SIZE EQU $1C8
EBB_CLOGGED        EQU 0
EBB_SHORTMEM       EQU 1
CB_SIZEOF          EQU 16              ; cb_ConfigDev, cb_FileName, cb_ProductString, cb_ToolTypes

; --- struct ConfigDev + ExpansionRom (libraries/configvars.i, configregs.i) ---
CD_FLAGS       EQU 14             ; UBYTE : CDB_SHUTUP (bit 0), CDB_CONFIGME (bit 1)
CD_ROM         EQU 16             ; struct ExpansionRom embarquée (16 octets)
ER_TYPE        EQU CD_ROM+0
ER_PRODUCT     EQU CD_ROM+1
ER_FLAGS       EQU CD_ROM+2
ER_RESERVED03  EQU CD_ROM+3
ER_MANUFACTURER EQU CD_ROM+4      ; UWORD
ER_INITDIAGVEC EQU CD_ROM+10      ; UWORD : décalage de la DiagArea dans la carte
ER_RESERVED0C  EQU CD_ROM+12      ; ULONG : copie RAM de la DiagArea (0 = aucune)
CD_BOARDADDR   EQU 32
CD_BOARDSIZE   EQU 36
CD_SLOTADDR    EQU 40             ; UWORD, en slots de 64 Ko
CD_SLOTSIZE    EQU 42             ; UWORD
CD_SIZEOF      EQU 68
CDB_SHUTUP     EQU 0
CDB_CONFIGME   EQU 1
ERTB_DIAGVALID EQU 4              ; er_Type
ERTB_MEMLIST   EQU 5
ERFB_NOSHUTUP  EQU 6              ; er_Flags
ER_ROMBYTES    EQU 17             ; octets logiques lus (le 17e déborde sur cd_BoardAddr, comme en 1.3)
ER_REREADS     EQU 11             ; relectures de contrôle de la ROM
EC_BASEADDR    EQU $12            ; octet logique « adresse de base » (registres $48/$4A)
EC_SHUTUP      EQU $13            ; octet logique « shut-up » (registres $4C/$4E)
E_SLOTSIZE     EQU 16             ; décalage slot <-> adresse (64 Ko)
E_IOSLOT_LO    EQU $E8            ; espace E/S essayé d'abord pour les cartes de moins de 8 slots
E_IOSLOT_HI    EQU $F0
EE_NOEXPANSION EQU 41
EE_NOMEMORY    EQU 42
AN_BADEXPFREE  EQU $0A000001      ; Alert de FreeExpansionMem (slot déjà libre ou hors table)

; --- struct DiagArea (libraries/configregs.i) ---
DA_CONFIG      EQU 0              ; UBYTE : largeur (bits 7-6), moment (bits 5-4)
DA_SIZE        EQU 2              ; UWORD
DA_DIAGPOINT   EQU 4              ; UWORD
DA_BOOTPOINT   EQU 6              ; UWORD : décalage du point d'amorçage dans la copie de la DiagArea
DA_HDRSIZE     EQU 14
DAC_BUSWIDTH   EQU $C0
DAC_NIBBLEWIDE EQU $00
DAC_BYTEWIDE   EQU $40
DAC_WORDWIDE   EQU $80
DAC_BOOTTIME   EQU $30
DAC_CONFIGTIME EQU $10

; --- struct BootNode (libraries/expansionbase.i) ---
BN_FLAGS       EQU 14             ; UWORD
BN_DEVICENODE  EQU 16
BN_SIZEOF      EQU 20
NT_BOOTNODE    EQU 16             ; ln_Type d'un BootNode amorçable (ln_Name = ConfigDev de la carte)

; --- LVO expansion.library ---
EXP_LVO_ADDCONFIGDEV   EQU -30    ; AddConfigDev(configDev a0)
EXP_LVO_ALLOCCONFIGDEV EQU -48    ; AllocConfigDev() -> d0 = ConfigDev* | 0
EXP_LVO_FINDCONFIGDEV  EQU -72    ; FindConfigDev(oldConfigDev a0, manufacturer d0, product d1) -> d0 = cd | 0
EXP_LVO_FREECONFIGDEV  EQU -84    ; FreeConfigDev(configDev a0)
EXP_LVO_OBTAINBINDING  EQU -120   ; ObtainConfigBinding()
EXP_LVO_RELEASEBINDING EQU -126   ; ReleaseConfigBinding()
EXP_LVO_SETBINDING     EQU -132   ; SetCurrentBinding(binding a0, taille d0)

; EXP_NO_ENQUEUE=1 (RED) : AddConfigDev N'AJOUTE PAS le ConfigDev à EB_BOARDLIST -> FindConfigDev ne le trouve
; jamais -> « EXPANSION OK » absent (AllocConfigDev + l'ouverture de la lib restent OK). Isole le câblage de la
; liste ConfigDev (le cœur de l'autoconfig). Défaut 0.
EXP_NO_ENQUEUE EQU 0

                endc
