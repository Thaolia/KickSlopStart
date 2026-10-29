; src/exec/expansion.i — expansion.library (Zorro II autoconfig): ExpansionBase V34, ConfigDev, DiagArea. Public ABI.
; LVO offsets: expansion_lib.fd / AROS rom/expansion/expansion.conf (LVO = -6*(slot+1)).
; IMPLEMENTATION track ("clean"): AutoDocs expansion.library + NDK libraries/configregs.i/configvars.i/expansionbase.i
; + spec docs/analysis/autoconfig-v34.md. NO ROM reading.

                ifnd    EXPANSION_I
EXPANSION_I     equ     1

; --- struct ExpansionBase (V34, dataSize of the resident) ---
EB_FLAGS           EQU $22             ; UBYTE: EBB_CLOGGED (bit 0), EBB_SHORTMEM (bit 1)
EB_EXECBASE        EQU $24
EB_SEGLIST         EQU $28
EB_BINDING         EQU $2C             ; struct CurrentBinding (16 bytes)
EB_BOARDLIST       EQU $3C             ; struct List of the ConfigDevs
EB_MOUNTLIST       EQU $4A             ; struct List of the BootNodes (AddDosNode without dos.library)
EB_ALLOCTABLE      EQU $58             ; 256 bytes, one per 64 KB slot: != 0 free, 0 taken / unavailable
EB_BINDSEM         EQU $158            ; struct SignalSemaphore (Obtain/ReleaseConfigBinding)
EXPANSIONBASE_SIZE EQU $1C8
EBB_CLOGGED        EQU 0
EBB_SHORTMEM       EQU 1
CB_SIZEOF          EQU 16              ; cb_ConfigDev, cb_FileName, cb_ProductString, cb_ToolTypes

; --- struct ConfigDev + ExpansionRom (libraries/configvars.i, configregs.i) ---
CD_FLAGS       EQU 14             ; UBYTE: CDB_SHUTUP (bit 0), CDB_CONFIGME (bit 1)
CD_ROM         EQU 16             ; embedded struct ExpansionRom (16 bytes)
ER_TYPE        EQU CD_ROM+0
ER_PRODUCT     EQU CD_ROM+1
ER_FLAGS       EQU CD_ROM+2
ER_RESERVED03  EQU CD_ROM+3
ER_MANUFACTURER EQU CD_ROM+4      ; UWORD
ER_INITDIAGVEC EQU CD_ROM+10      ; UWORD: offset of the DiagArea in the board
ER_RESERVED0C  EQU CD_ROM+12      ; ULONG: RAM copy of the DiagArea (0 = none)
CD_BOARDADDR   EQU 32
CD_BOARDSIZE   EQU 36
CD_SLOTADDR    EQU 40             ; UWORD, in 64 KB slots
CD_SLOTSIZE    EQU 42             ; UWORD
CD_SIZEOF      EQU 68
CDB_SHUTUP     EQU 0
CDB_CONFIGME   EQU 1
ERTB_DIAGVALID EQU 4              ; er_Type
ERTB_MEMLIST   EQU 5
ERFB_NOSHUTUP  EQU 6              ; er_Flags
ER_ROMBYTES    EQU 17             ; logical bytes read (the 17th overflows onto cd_BoardAddr, as in 1.3)
ER_REREADS     EQU 11             ; check rereads of the ROM
EC_BASEADDR    EQU $12            ; "base address" logical byte (registers $48/$4A)
EC_SHUTUP      EQU $13            ; "shut-up" logical byte (registers $4C/$4E)
E_SLOTSIZE     EQU 16             ; slot <-> address shift (64 KB)
E_IOSLOT_LO    EQU $E8            ; I/O space tried first for boards smaller than 8 slots
E_IOSLOT_HI    EQU $F0
EE_NOEXPANSION EQU 41
EE_NOMEMORY    EQU 42
AN_BADEXPFREE  EQU $0A000001      ; Alert of FreeExpansionMem (slot already free or outside the table)

; --- struct DiagArea (libraries/configregs.i) ---
DA_CONFIG      EQU 0              ; UBYTE: width (bits 7-6), moment (bits 5-4)
DA_SIZE        EQU 2              ; UWORD
DA_DIAGPOINT   EQU 4              ; UWORD
DA_BOOTPOINT   EQU 6              ; UWORD: offset of the boot point in the DiagArea copy
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
NT_BOOTNODE    EQU 16             ; ln_Type of a bootable BootNode (ln_Name = ConfigDev of the board)

; --- expansion.library LVOs ---
EXP_LVO_ADDCONFIGDEV   EQU -30    ; AddConfigDev(configDev a0)
EXP_LVO_ALLOCCONFIGDEV EQU -48    ; AllocConfigDev() -> d0 = ConfigDev* | 0
EXP_LVO_FINDCONFIGDEV  EQU -72    ; FindConfigDev(oldConfigDev a0, manufacturer d0, product d1) -> d0 = cd | 0
EXP_LVO_FREECONFIGDEV  EQU -84    ; FreeConfigDev(configDev a0)
EXP_LVO_OBTAINBINDING  EQU -120   ; ObtainConfigBinding()
EXP_LVO_RELEASEBINDING EQU -126   ; ReleaseConfigBinding()
EXP_LVO_SETBINDING     EQU -132   ; SetCurrentBinding(binding a0, size d0)

; EXP_NO_ENQUEUE=1 (RED): AddConfigDev does NOT ADD the ConfigDev to EB_BOARDLIST -> FindConfigDev never finds
; it -> "EXPANSION OK" absent (AllocConfigDev + opening the lib remain OK). Isolates the wiring of the
; ConfigDev list (the heart of autoconfig). Default 0.
EXP_NO_ENQUEUE EQU 0

                endc
