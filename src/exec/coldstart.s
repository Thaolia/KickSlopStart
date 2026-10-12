; src/exec/coldstart.s — exec.library : coldstart, ExecBase, jump table LVO,
; premières fonctions (M2.0 + M2.1a). Piste IMPLEMENTATION (« clean ») : écrit
; depuis docs/analysis/exec-spec.md + ABI publique. AUCUNE lecture de la ROM.
;
; Reset $FC00D2 -> superviseur + gel HW (ROUGE) -> coupe overlay + pile (BLEU)
; -> ExecBase + jump table (CYAN) -> publie SysBase, auto-vérif + auto-test des
; fonctions via la jump table -> BLANC si tout passe, MAGENTA sinon.
;
; Couleur -> phase (débogueur visuel) : rouge=entré, bleu=overlay off/pile,
; cyan=build ExecBase+table, blanc=SUCCÈS (ExecBase cohérent + fonctions OK),
; magenta=échec d'une vérification.
;
; M2.1a couvre : le MÉCANISME de dispatch (jump table) et le COMPORTEMENT des
; fonctions appelées. Il ne prouve PAS la compatibilité d'offsets avec l'AmigaOS
; 1.3 réel (on appelle ce qu'on a soi-même patché) — cela se validera plus tard
; quand un binaire Amiga réel appellera ces vecteurs (+ cross-check exec_lib.fd V34).

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
MH_CHIP      EQU $00000400     ; MemHeader chip (utilisé en M2.1b)
TST_LIST     EQU $00000420     ; scratch auto-test (listes)
TST_N1       EQU $00000440
TST_N2       EQU $00000460
HEAP_LOWER   EQU $00001000     ; tas géré (M2.1b)
HEAP_UPPER   EQU $0007D000
STACKTOP     EQU $0007EF00     ; pile superviseur (gap de garde avant la table)
EXEC_BLOCK   EQU $0007F000     ; bas de la jump table
EXEC_NEGSIZE EQU $120          ; 48 entrées de 6 octets
EXECBASE     EQU $0007F120     ; SysBase = EXEC_BLOCK + EXEC_NEGSIZE
EXEC_POSSIZE EQU $230

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

; LVO (offsets négatifs confirmés par docs/analysis/exec-spec.md)
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

        ORG     ROMBASE
        dc.w    $1111
        dc.w    $4EF9
        dc.l    coldstart        ; +04 PC de reset
        dc.l    $0000FFFF        ; +08
        dc.l    $00220005        ; +0C version ROM 34.5
        dc.l    $00220002        ; +10
        dc.l    $FFFFFFFF        ; +14
        dcb.b   ROMBASE+$D0-*,0
        dc.w    $4E70            ; $FC00D0 RESET (magic_reset)

coldstart:                        ; $FC00D2
        ; --- Phase 1 : superviseur + gel matériel (straight-line, pas de pile) ---
        move.w  #$2700,sr
        move.w  #$7FFF,DMACON
        move.w  #$7FFF,INTENA
        move.w  #$7FFF,INTREQ
        move.w  #C_RED,COLOR00

        ; --- Phase 2 : coupe overlay puis installe la pile ---
        move.b  #$03,CIAA_DDRA
        move.b  #$02,CIAA_PRA        ; OVL off -> RAM chip à $0
        move.l  #STACKTOP,sp
        move.w  #C_BLUE,COLOR00
        move.w  #SERPER_9600_PAL,SERPER
        lea     msg_cold(pc),a0
        bsr     ser_puts

        ; --- Phase 3 : ExecBase + jump table ---
        move.w  #C_CYAN,COLOR00
        lea     EXECBASE,a0          ; zéro-remplit la zone des champs positifs
        move.w  #(EXEC_POSSIZE/4)-1,d0
.zf:
        clr.l   (a0)+
        dbf     d0,.zf

        lea     EXECBASE,a6          ; a6 = SysBase (convention library base)
        move.b  #NT_LIBRARY,LN_TYPE(a6)
        move.l  #exec_name,LN_NAME(a6)
        move.w  #EXEC_NEGSIZE,LIB_NEGSIZE(a6)
        move.w  #EXEC_POSSIZE,LIB_POSSIZE(a6)
        move.w  #34,LIB_VERSION(a6)
        move.w  #2,LIB_REVISION(a6)
        move.l  #exec_id,LIB_IDSTRING(a6)
        move.l  #MAXCHIP,EB_MAXLOCMEM(a6)
        move.w  #0,EB_ATTNFLAGS(a6)
        move.b  #50,EB_VBLANKFREQ(a6)
        move.b  #50,EB_POWERFREQ(a6)
        move.b  #-1,EB_IDNEST(a6)
        move.b  #-1,EB_TDNEST(a6)
        move.l  #EXECBASE,d0
        not.l   d0
        move.l  d0,EB_CHKBASE(a6)

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

        bsr     build_jumptable

        ; --- Phase 4 : publie SysBase, auto-vérif, auto-test ---
        move.l  a6,($4).w

        move.l  ($4).w,d0
        cmp.l   #EXECBASE,d0
        bne     eb_fail
        cmp.w   #34,LIB_VERSION(a6)
        bne     eb_fail
        move.l  a6,d0
        not.l   d0
        cmp.l   EB_CHKBASE(a6),d0
        bne     eb_fail
        lea     EB_MEMLIST(a6),a0
        lea     LH_TAIL(a0),a1
        cmp.l   (a0),a1              ; lh_Head == &lh_Tail ?
        bne     eb_fail

        bsr     selftest             ; d0 = 0 (OK) / !=0 (échec)
        tst.l   d0
        bne     eb_fail

        move.w  #C_WHITE,COLOR00
        lea     msg_ok(pc),a0
        bsr     ser_puts
freeze:
        bra.s   freeze

eb_fail:
        move.w  #C_FAIL,COLOR00
        lea     msg_fail(pc),a0
        bsr     ser_puts
.ff:
        bra.s   .ff

; ============================ jump table ============================
; Remplit les 48 entrées avec _unimpl puis patche les LVO implémentés.
build_jumptable:                     ; a6 = SysBase ; clobbers d0/d1/a0
        lea     EXEC_BLOCK,a0
        move.w  #(EXEC_NEGSIZE/6)-1,d0
        move.l  #_unimpl,d1
.fill:
        move.w  #$4EF9,(a0)+
        move.l  d1,(a0)+
        dbf     d0,.fill
        move.w  #$4EF9,LVO_OPEN(a6)
        move.l  #exec_Open,LVO_OPEN+2(a6)
        move.w  #$4EF9,LVO_CLOSE(a6)
        move.l  #exec_Close,LVO_CLOSE+2(a6)
        move.w  #$4EF9,LVO_EXPUNGE(a6)
        move.l  #exec_Expunge,LVO_EXPUNGE+2(a6)
        move.w  #$4EF9,LVO_DISABLE(a6)
        move.l  #exec_Disable,LVO_DISABLE+2(a6)
        move.w  #$4EF9,LVO_ENABLE(a6)
        move.l  #exec_Enable,LVO_ENABLE+2(a6)
        move.w  #$4EF9,LVO_FORBID(a6)
        move.l  #exec_Forbid,LVO_FORBID+2(a6)
        move.w  #$4EF9,LVO_PERMIT(a6)
        move.l  #exec_Permit,LVO_PERMIT+2(a6)
        move.w  #$4EF9,LVO_ADDHEAD(a6)
        move.l  #exec_AddHead,LVO_ADDHEAD+2(a6)
        move.w  #$4EF9,LVO_ADDTAIL(a6)
        move.l  #exec_AddTail,LVO_ADDTAIL+2(a6)
        move.w  #$4EF9,LVO_REMOVE(a6)
        move.l  #exec_Remove,LVO_REMOVE+2(a6)
        move.w  #$4EF9,LVO_FINDNAME(a6)
        move.l  #exec_FindName,LVO_FINDNAME+2(a6)
        rts

_unimpl:
        moveq   #0,d0                ; LVO non implémenté : retour neutre
        rts

; ============================ fonctions exec ========================
; Convention Amiga : scratch = d0/d1/a0/a1 ; a6 = library base.

exec_Open:                           ; -> d0 = SysBase
        addq.w  #1,LIB_OPENCNT(a6)
        move.l  a6,d0
        rts
exec_Close:
        subq.w  #1,LIB_OPENCNT(a6)
        moveq   #0,d0
        rts
exec_Expunge:
        moveq   #0,d0                ; exec ne s'expulse jamais
        rts

exec_Forbid:
        addq.b  #1,EB_TDNEST(a6)
        rts
exec_Permit:
        subq.b  #1,EB_TDNEST(a6)
        rts
exec_Disable:
        addq.b  #1,EB_IDNEST(a6)
        move.w  #$4000,INTENA        ; clear INTEN (bit14)
        rts
exec_Enable:
        subq.b  #1,EB_IDNEST(a6)
        bge.s   .nest
        move.w  #$C000,INTENA        ; SET + INTEN
.nest:
        rts

; AddHead(list a0, node a1)
exec_AddHead:
        move.l  (a0),d0              ; old lh_Head
        move.l  d0,(a1)              ; node.Succ = old head
        move.l  a0,LN_PRED(a1)       ; node.Pred = &lh_Head (= list)
        move.l  a1,(a0)              ; lh_Head = node
        move.l  d0,a0                ; a0 = old head
        move.l  a1,LN_PRED(a0)       ; old_head.Pred = node
        rts

; AddTail(list a0, node a1)
exec_AddTail:
        move.l  8(a0),d1             ; old lh_TailPred
        move.l  a0,d0
        addq.l  #LH_TAIL,d0          ; d0 = &lh_Tail
        move.l  d0,(a1)              ; node.Succ = &lh_Tail
        move.l  d1,LN_PRED(a1)       ; node.Pred = old TailPred
        move.l  a1,8(a0)             ; lh_TailPred = node
        move.l  d1,a0                ; a0 = old TailPred
        move.l  a1,(a0)              ; old_TailPred.Succ = node
        rts

; Remove(node a1)
exec_Remove:
        move.l  (a1),d0              ; Succ
        move.l  LN_PRED(a1),a0       ; Pred
        move.l  d0,(a0)              ; Pred.Succ = Succ
        move.l  d0,a0                ; a0 = Succ
        move.l  LN_PRED(a1),LN_PRED(a0) ; Succ.Pred = Pred
        rts

; FindName(list a0, name a1) -> d0 = node | 0
exec_FindName:
        move.l  (a0),a0              ; node = lh_Head
.fn_loop:
        move.l  (a0),d0              ; node->Succ
        beq.s   .fn_none             ; atteint le sentinel (Succ==0)
        move.l  LN_NAME(a0),d1
        beq.s   .fn_next             ; pas de nom
        movem.l d2/a0/a1,-(sp)
        move.l  d1,a0                ; nom du nœud
.fn_cmp:
        move.b  (a0)+,d0
        move.b  (a1)+,d2
        cmp.b   d0,d2
        bne.s   .fn_nomatch
        tst.b   d0
        bne.s   .fn_cmp
        movem.l (sp)+,d2/a0/a1
        move.l  a0,d0                ; match -> retourne le nœud
        rts
.fn_nomatch:
        movem.l (sp)+,d2/a0/a1
.fn_next:
        move.l  (a0),a0              ; node = node->Succ
        bra.s   .fn_loop
.fn_none:
        moveq   #0,d0
        rts

; newlist : struct List vide (a1 = &List ; conserve a6 ; clobbers a0)
newlist:
        move.l  a1,a0
        addq.l  #LH_TAIL,a0
        move.l  a0,(a1)
        clr.l   LH_TAIL(a1)
        move.l  a1,8(a1)
        rts

; ser_puts : chaîne NUL-terminée sur le série (a0) ; timeout borné sur TBE
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
        bra.s   .done
.tx:
        and.w   #$00FF,d0
        or.w    #$0100,d0
        move.w  d0,SERDAT
        bra.s   .lp
.done:
        movem.l (sp)+,d0/d1/d2/a0
        rts

; ============================ auto-test (M2.1a) =====================
; Exerce le dispatch jump-table et le comportement des fonctions.
; Retour : d0 = 0 (tout OK) / 1 (échec).
selftest:
        ; Forbid : TDNestCnt -1 -> 0 ; Permit : 0 -> -1
        jsr     LVO_FORBID(a6)
        cmp.b   #0,EB_TDNEST(a6)
        bne.w   .bad
        jsr     LVO_PERMIT(a6)
        cmp.b   #-1,EB_TDNEST(a6)
        bne.w   .bad
        ; Disable/Enable : IDNestCnt -1 -> 0 -> -1
        jsr     LVO_DISABLE(a6)
        cmp.b   #0,EB_IDNEST(a6)
        bne.w   .bad
        jsr     LVO_ENABLE(a6)
        cmp.b   #-1,EB_IDNEST(a6)
        bne.w   .bad

        ; liste : NEWLIST, AddTail(n1), AddTail(n2), FindName
        lea     TST_LIST,a1
        bsr     newlist
        move.l  #str_alpha,TST_N1+LN_NAME
        move.l  #str_beta,TST_N2+LN_NAME
        lea     TST_LIST,a0
        lea     TST_N1,a1
        jsr     LVO_ADDTAIL(a6)
        lea     TST_LIST,a0
        lea     TST_N2,a1
        jsr     LVO_ADDTAIL(a6)
        ; FindName("beta") == TST_N2
        lea     TST_LIST,a0
        move.l  #str_beta,a1
        jsr     LVO_FINDNAME(a6)
        cmp.l   #TST_N2,d0
        bne.w   .bad
        ; FindName("gamma") == 0
        lea     TST_LIST,a0
        move.l  #str_gamma,a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        bne.w   .bad
        ; Remove(n1) ; FindName("alpha") == 0
        lea     TST_N1,a1
        jsr     LVO_REMOVE(a6)
        lea     TST_LIST,a0
        move.l  #str_alpha,a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        bne.w   .bad
        ; AddHead(n1) ; FindName("alpha") == TST_N1
        lea     TST_LIST,a0
        lea     TST_N1,a1
        jsr     LVO_ADDHEAD(a6)
        lea     TST_LIST,a0
        move.l  #str_alpha,a1
        jsr     LVO_FINDNAME(a6)
        cmp.l   #TST_N1,d0
        bne.w   .bad
        ; Open/Close : OpenCnt +1 puis -1, Open retourne SysBase
        jsr     LVO_OPEN(a6)
        cmp.l   a6,d0
        bne.w   .bad
        jsr     LVO_CLOSE(a6)
        tst.w   LIB_OPENCNT(a6)
        bne.w   .bad

        moveq   #0,d0
        rts
.bad:
        moveq   #1,d0
        rts

; ============================ données ==============================
exec_name:
        dc.b    "exec.library",0
exec_id:
        dc.b    "exec 34.2 (clean-room reimpl)",13,10,0
str_alpha:
        dc.b    "alpha",0
str_beta:
        dc.b    "beta",0
str_gamma:
        dc.b    "gamma",0
msg_cold:
        dc.b    "EXEC coldstart: overlay off, stack live",13,10,0
msg_ok:
        dc.b    "EXEC ExecBase + jump table OK, self-test passed",13,10,0
msg_fail:
        dc.b    "EXEC self-check/self-test FAILED",13,10,0
        EVEN
