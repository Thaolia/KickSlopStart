; src/exec/coldstart.s — exec.library : coldstart + squelette ExecBase (M2.0)
;
; Piste IMPLEMENTATION (« clean ») : écrit depuis docs/analysis/exec-spec.md (spec
; d'ABI clean-room) + ABI publique (exec/execbase.i). AUCUNE lecture de la ROM.
;
; Au reset, le PC saute ici ($FC00D2). Séquence :
;   1. mode superviseur, gel DMA/IRQ                      -> COLOR00 ROUGE
;   2. coupure de l'overlay (RAM chip à $0), pile à $80000 -> COLOR00 BLEU
;   3. construction du squelette ExecBase                  -> COLOR00 CYAN
;   4. SysBase publié en $4, succès                        -> COLOR00 BLANC
;
; Mapping couleur -> phase (débogueur visuel tant que le série n'est pas capturé) :
;   rouge  = entré, matériel gelé, overlay pas encore coupé
;   bleu   = overlay coupé, pile vivante
;   cyan   = en train de bâtir ExecBase
;   blanc  = ExecBase bâti, SysBase en $4  (= SUCCÈS attendu par boot_test)
; Rester bloqué sur une couleur = la phase suivante a planté.
;
; Pas encore : jump table LVO, fonctions, tâches, scan des résidents (-> M2.1).

; --- Custom chip (Amiga HRM) ---
CUSTOM   EQU $DFF000
DMACON   EQU CUSTOM+$096
INTENA   EQU CUSTOM+$09A
INTREQ   EQU CUSTOM+$09C
SERDAT   EQU CUSTOM+$030
SERPER   EQU CUSTOM+$032
SERDATR  EQU CUSTOM+$018         ; read : bit 13 = TBE
COLOR00  EQU CUSTOM+$180

; --- CIA-A (overlay / LED) ---
CIAA_PRA  EQU $BFE001            ; bit0 = /OVL, bit1 = /LED
CIAA_DDRA EQU $BFE201

; --- Carte mémoire / constantes cible A500 ---
ROMBASE   EQU $FC0000
MAXCHIP   EQU $00080000          ; 512 Ko chip (A500) — sizing réel reporté
STACKTOP  EQU $00080000          ; pile superviseur provisoire au sommet du chip
EXECBASE  EQU $00000400          ; ExecBase juste au-dessus de la table de vecteurs
EXECBASE_FILL EQU $230           ; octets mis à zéro (couvre les champs V34 ~0x22E)

; --- Phases (RGB 12 bits) ---
C_RED    EQU $0F00
C_BLUE   EQU $000F
C_CYAN   EQU $00FF
C_WHITE  EQU $0FFF
C_FAIL   EQU $0F0F           ; magenta = auto-vérification échouée

SERPER_9600_PAL EQU 368

; --- Offsets ExecBase (exec-spec.md / exec/execbase.i, V34) ---
LN_TYPE       EQU $08
LN_NAME       EQU $0A
LIB_VERSION   EQU $14
LIB_REVISION  EQU $16
LIB_IDSTRING  EQU $18
EB_CHKBASE    EQU $26
EB_MAXLOCMEM  EQU $3E
EB_IDNEST     EQU $126
EB_TDNEST     EQU $127
EB_ATTNFLAGS  EQU $128
EB_MEMLIST    EQU $142
EB_RESOURCELIST EQU $150
EB_DEVICELIST EQU $15E
EB_INTRLIST   EQU $16C
EB_LIBLIST    EQU $17A
EB_PORTLIST   EQU $188
EB_TASKREADY  EQU $196
EB_TASKWAIT   EQU $1A4
EB_VBLANKFREQ EQU $212
EB_POWERFREQ  EQU $213
EB_SEMLIST    EQU $214
NT_LIBRARY    EQU 9

        ORG     ROMBASE

; --- En-tête conteneur (identique à un Kickstart 256K authentique) ---
        dc.w    $1111            ; ROM-ID
        dc.w    $4EF9            ; JMP abs.l (SSP de reset bénin)
        dc.l    coldstart        ; +04 : PC de reset
        dc.l    $0000FFFF        ; +08
        dc.l    $00220005        ; +0C : version ROM 34.5
        dc.l    $00220002        ; +10
        dc.l    $FFFFFFFF        ; +14
        dcb.b   ROMBASE+$D0-*,0  ; padding jusqu'à $FC00D0
        dc.w    $4E70            ; $FC00D0 : RESET (magic_reset)

coldstart:                        ; $FC00D2
        ; --- Phase 1 : superviseur + gel matériel (straight-line, PAS de pile) ---
        move.w  #$2700,sr        ; superviseur, IPL7, trace off
        move.w  #$7FFF,DMACON    ; coupe tout le DMA
        move.w  #$7FFF,INTENA    ; masque toutes les IRQ
        move.w  #$7FFF,INTREQ    ; acquitte les IRQ en attente
        move.w  #C_RED,COLOR00

        ; --- Phase 2 : coupe l'overlay puis installe la pile ---
        move.b  #$03,CIAA_DDRA   ; PA0 (OVL) + PA1 (LED) en sortie
        move.b  #$02,CIAA_PRA    ; LED off, OVL off -> RAM chip à $0
        move.l  #STACKTOP,sp     ; pile vivante (jsr/bsr OK à partir d'ici)
        move.w  #C_BLUE,COLOR00
        move.w  #SERPER_9600_PAL,SERPER
        lea     msg_cold(pc),a0
        bsr     ser_puts

        ; --- Phase 3 : construit le squelette ExecBase ---
        move.w  #C_CYAN,COLOR00
        lea     EXECBASE,a0            ; zéro-remplit la zone ExecBase
        move.w  #(EXECBASE_FILL/4)-1,d0
.zf:
        clr.l   (a0)+
        dbf     d0,.zf

        lea     EXECBASE,a6           ; a6 = ExecBase (SysBase) conservé par newlist
        move.b  #NT_LIBRARY,LN_TYPE(a6)
        move.l  #exec_name,LN_NAME(a6)
        move.w  #34,LIB_VERSION(a6)
        move.w  #2,LIB_REVISION(a6)
        move.l  #exec_id,LIB_IDSTRING(a6)
        move.l  #MAXCHIP,EB_MAXLOCMEM(a6)
        move.w  #0,EB_ATTNFLAGS(a6)   ; 68000 pur
        move.b  #50,EB_VBLANKFREQ(a6) ; PAL
        move.b  #50,EB_POWERFREQ(a6)
        move.b  #-1,EB_IDNEST(a6)     ; -1 = hors section critique
        move.b  #-1,EB_TDNEST(a6)
        move.l  #EXECBASE,d0
        not.l   d0
        move.l  d0,EB_CHKBASE(a6)     ; ChkBase = ~SysBase

        lea     EB_MEMLIST(a6),a1
        bsr     newlist
        lea     EB_RESOURCELIST(a6),a1
        bsr     newlist
        lea     EB_DEVICELIST(a6),a1
        bsr     newlist
        lea     EB_INTRLIST(a6),a1
        bsr     newlist
        lea     EB_LIBLIST(a6),a1
        bsr     newlist
        lea     EB_PORTLIST(a6),a1
        bsr     newlist
        lea     EB_TASKREADY(a6),a1
        bsr     newlist
        lea     EB_TASKWAIT(a6),a1
        bsr     newlist
        lea     EB_SEMLIST(a6),a1
        bsr     newlist

        ; --- Phase 4 : publie SysBase ---
        move.l  a6,($4).w             ; AbsExecBase = *(ULONG*)4

        ; --- auto-vérification de cohérence du squelette ---
        move.l  ($4).w,d0
        cmp.l   #EXECBASE,d0          ; SysBase bien publié en $4 ?
        bne     eb_fail
        cmp.w   #34,LIB_VERSION(a6)   ; lib_Version == 34 ?
        bne     eb_fail
        move.l  a6,d0
        not.l   d0
        cmp.l   EB_CHKBASE(a6),d0     ; ChkBase == ~SysBase ?
        bne     eb_fail
        lea     EB_MEMLIST(a6),a0     ; MemList vide bien formée ?
        lea     4(a0),a1
        cmp.l   (a0),a1               ; lh_Head == &lh_Tail ?
        bne     eb_fail

        move.w  #C_WHITE,COLOR00      ; SUCCÈS
        lea     msg_eb(pc),a0
        bsr     ser_puts
freeze:
        bra.s   freeze                ; fond blanc figé = succès

eb_fail:
        move.w  #C_FAIL,COLOR00       ; magenta = squelette incohérent
        lea     msg_fail(pc),a0
        bsr     ser_puts
.ff:
        bra.s   .ff

; --- newlist : initialise une struct List vide (in a1=&List ; conserve a6) ---
; List : lh_Head(0)=&lh_Tail ; lh_Tail(4)=0 ; lh_TailPred(8)=&lh_Head
newlist:
        move.l  a1,a0
        addq.l  #4,a0
        move.l  a0,(a1)
        clr.l   4(a1)
        move.l  a1,8(a1)
        rts

; --- ser_puts : émet une chaîne NUL-terminée sur le série (in a0=chaîne) ---
; Timeout borné sur TBE : si le série n'est pas disponible, abandonne sans geler.
ser_puts:
        movem.l d0/d1/d2/a0,-(sp)
.lp:
        move.b  (a0)+,d0
        beq.s   .done
        move.w  #$2000,d2
.wt:
        move.w  SERDATR,d1
        btst    #13,d1
        bne.s   .tx
        dbra    d2,.wt
        bra.s   .done            ; TBE jamais prêt -> série absent, on abandonne
.tx:
        and.w   #$00FF,d0
        or.w    #$0100,d0         ; stop bit
        move.w  d0,SERDAT
        bra.s   .lp
.done:
        movem.l (sp)+,d0/d1/d2/a0
        rts

exec_name:
        dc.b    "exec.library",0
exec_id:
        dc.b    "exec 34.2 (clean-room reimpl)",13,10,0
msg_cold:
        dc.b    "EXEC coldstart: overlay off, stack live",13,10,0
msg_eb:
        dc.b    "EXEC ExecBase skeleton built, SysBase @ $00000400",13,10,0
msg_fail:
        dc.b    "EXEC ExecBase self-check FAILED",13,10,0
        EVEN
