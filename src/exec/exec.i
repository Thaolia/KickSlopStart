; src/exec/exec.i — constantes partagées exec.library (M2.3).
; Inclus par boot.s / lists.s / memory.s / library.s. Uniquement des EQU
; (faits d'ABI publics + carte mémoire du projet) : aucune logique, aucune donnée.
; Piste IMPLÉMENTATION (« clean ») : valeurs issues de docs/analysis/exec-spec.md,
; docs/exec-lvo-table.md et de l'ABI publique. AUCUNE lecture de la ROM.

                ifnd    EXEC_I
EXEC_I          equ     1

; --- Custom chip (Amiga HRM) ---
CUSTOM   EQU $DFF000
DMACON   EQU CUSTOM+$096
INTENA   EQU CUSTOM+$09A
INTREQ   EQU CUSTOM+$09C
SERDAT   EQU CUSTOM+$030
SERPER   EQU CUSTOM+$032
SERDATR  EQU CUSTOM+$018
COLOR00  EQU CUSTOM+$180

; --- CIA-A (overlay / LED) ---
CIAA_PRA  EQU $BFE001
CIAA_DDRA EQU $BFE201

; --- Carte mémoire cible A500 512K ---
MAXCHIP      EQU $00080000
MH_CHIP      EQU $00000400     ; MemHeader chip
TST_LIST     EQU $00000420     ; scratch auto-test (listes)
TST_N1       EQU $00000440
TST_N2       EQU $00000460
HEAP_LOWER   EQU $00001000     ; tas géré
HEAP_UPPER   EQU $0007D000
EXECBASE     EQU $0007F000     ; SysBase (table V34 complète en dessous)
EXEC_NEGSIZE EQU $276          ; 105 vecteurs V34 (cf docs/exec-lvo-table.md)
EXEC_BLOCK   EQU EXECBASE-EXEC_NEGSIZE   ; bas de la jump table
EXEC_POSSIZE EQU $230
STACKTOP     EQU EXEC_BLOCK-$80 ; pile superviseur (gap de garde avant la table)

; --- Phases (RGB 12 bits) ---
C_RED    EQU $0F00
C_BLUE   EQU $000F
C_CYAN   EQU $00FF
C_WHITE  EQU $0FFF
C_FAIL   EQU $0F0F

SERPER_9600_PAL EQU 368
ROMBASE  EQU $FC0000

; --- Offsets struct Node / List / Library / ExecBase (exec-spec.md) ---
LN_SUCC      EQU 0
LN_PRED      EQU 4
LN_NAME      EQU 10
LH_TAIL      EQU 4
LN_TYPE      EQU 8
NT_LIBRARY   EQU 9
LIB_NEGSIZE  EQU $10
LIB_POSSIZE  EQU $12
LIB_VERSION  EQU $14
LIB_REVISION EQU $16
LIB_IDSTRING EQU $18
LIB_OPENCNT  EQU $20
EB_CHKBASE    EQU $26
EB_MAXLOCMEM  EQU $3E
EB_IDNEST     EQU $126
EB_TDNEST     EQU $127
EB_ATTNFLAGS  EQU $128
EB_MEMLIST      EQU $142
EB_RESOURCELIST EQU $150
EB_DEVICELIST   EQU $15E
EB_INTRLIST     EQU $16C
EB_LIBLIST      EQU $17A
EB_PORTLIST     EQU $188
EB_TASKREADY    EQU $196
EB_TASKWAIT     EQU $1A4
EB_VBLANKFREQ   EQU $212
EB_POWERFREQ    EQU $213
EB_SEMLIST      EQU $214

; struct MemHeader / MemChunk + attributs mémoire (exec/memory.i, V34)
NT_MEMORY     EQU 10
MEMF_PUBLIC   EQU $1
MEMF_CHIP     EQU $2
MEMF_CLEAR    EQU $10000
MH_ATTRIBUTES EQU 14
MH_FIRST      EQU 16          ; -> struct MemChunk
MH_LOWER      EQU 20
MH_UPPER      EQU 24
MH_FREE       EQU 28
MC_NEXT       EQU 0
MC_BYTES      EQU 4

; LVO (offsets négatifs confirmés par docs/analysis/exec-spec.md + exec-lvo-table.md)
LVO_OPEN     EQU -6
LVO_CLOSE    EQU -12
LVO_EXPUNGE  EQU -18
LVO_DISABLE  EQU -120
LVO_ENABLE   EQU -126
LVO_FORBID   EQU -132
LVO_PERMIT   EQU -138
LVO_ALLOCMEM EQU -198
LVO_FREEMEM  EQU -210
LVO_ADDHEAD  EQU -240
LVO_ADDTAIL  EQU -246
LVO_REMOVE   EQU -252
LVO_FINDNAME EQU -276

                endc
