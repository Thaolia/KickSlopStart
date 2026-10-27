; tests/coldhw_probe.s — bootblock de SONDE boîte noire du coldstart (ASSET DE TEST, PAS du code ROM).
; Assemblé en binaire brut (vasm -Fbin -m68000 -DMODE=n), posé à l'offset +12 du bootblock d'un ADF par
; tests/coldhw_probe.sh. Sert à observer, sous la VRAIE ROM 1.3, l'état laissé par le coldstart (ExecBase,
; MemList, RAM basse, survie au reset) et la chaîne Alert -> reset -> alert.hook. Code AUTEUR : n'utilise que
; l'ABI publique (offsets ExecBase de exec/execbase.i, LVO de exec_lib.fd) et les registres hardware publics.
;
; Compteur de boots : long magique 'CHWM' + compteur à CHIPMARK (et SLOWMARK si de la RAM $C00000 existe).
; Premier boot (compteur = 1) : action du MODE ; boots suivants : rapport seul, puis attente infinie.
;   MODE 0 : rapport seul.
;   MODE 1 : Alert($8100000F) dead-end, A5 -> $CAFEBABE.
;   MODE 2 : Alert($35000001) récupérable, A5 -> $12345678, puis rapport « RET ».
;   MODE 3 : instruction ILLEGAL.
;   MODE 4 : reboot logiciel (RESET + saut dans la ROM via l'adresse 2, technique publique 1.3).
;   MODE 5 : pose ColdCapture/CoolCapture (stubs copiés en RAM chip), recalcule ChkSum, puis reboot MODE 4.

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018
CHIPMARK EQU $60000
SLOWMARK EQU $C40100
STUBS    EQU $61000
        IFND MODE
MODE    EQU 0
        ENDC

start:
        movea.l 4.w,a6
        lea     m_head(pc),a0
        bsr     puts
        moveq   #MODE,d0
        bsr     hex8
        bsr     nl
        ; RAM basse
        lea     m_low(pc),a0
        bsr     puts
        move.l  0.w,d0
        bsr     hex8
        move.l  $100.w,d0
        bsr     hex8
        move.l  $104.w,d0
        bsr     hex8
        bsr     nl
        ; ExecBase et champs
        lea     m_eb(pc),a0
        bsr     puts
        move.l  a6,d0
        bsr     hex8
        move.l  $3E(a6),d0          ; MaxLocMem
        bsr     hex8
        move.l  $4E(a6),d0          ; MaxExtMem
        bsr     hex8
        move.l  $36(a6),d0          ; SysStkUpper
        bsr     hex8
        move.l  $3A(a6),d0          ; SysStkLower
        bsr     hex8
        bsr     nl
        lea     m_cap(pc),a0
        bsr     puts
        move.l  $2A(a6),d0          ; ColdCapture
        bsr     hex8
        move.l  $2E(a6),d0          ; CoolCapture
        bsr     hex8
        move.l  $32(a6),d0          ; WarmCapture
        bsr     hex8
        move.l  $202(a6),d0         ; LastAlert[0]
        bsr     hex8
        move.l  $206(a6),d0         ; LastAlert[1]
        bsr     hex8
        move.w  $128(a6),d0         ; AttnFlags
        bsr     hex8
        move.l  $212(a6),d0         ; VBlankFreq/PowerSupplyFreq (2 octets hauts)
        bsr     hex8
        bsr     nl
        ; MemList
        lea     $142(a6),a2
        movea.l (a2),a2
.ml:    tst.l   (a2)
        beq.s   .mld
        lea     m_mh(pc),a0
        bsr     puts
        move.l  a2,d0
        bsr     hex8
        moveq   #0,d0
        move.b  9(a2),d0            ; LN_PRI
        bsr     hex8
        move.w  $E(a2),d0           ; mh_Attributes
        bsr     hex8
        move.l  $14(a2),d0          ; mh_Lower
        bsr     hex8
        move.l  $18(a2),d0          ; mh_Upper
        bsr     hex8
        move.l  $1C(a2),d0          ; mh_Free
        bsr     hex8
        movea.l $A(a2),a0           ; nom
        bsr     puts
        bsr     nl
        movea.l (a2),a2
        bra.s   .ml
.mld:
        ; marqueurs de survie
        lea     m_mark(pc),a0
        bsr     puts
        lea     CHIPMARK,a3
        bsr     mark
        move.l  d0,d6               ; compteur chip (après incrément)
        move.l  $4E(a6),d1
        cmp.l   #SLOWMARK+16,d1
        bls.s   .noslow
        lea     SLOWMARK,a3
        bsr     mark
.noslow:
        move.l  CHIPMARK+16,d0      ; compteurs ColdCapture/CoolCapture (MODE 5)
        bsr     hex8
        move.l  CHIPMARK+20,d0
        bsr     hex8
        bsr     nl
        cmp.l   #1,d6
        bne     idle
        IFEQ MODE-1
        lea     v_cafe(pc),a5
        move.l  #$8100000F,d7
        jsr     -108(a6)
        ENDC
        IFEQ MODE-2
        lea     v_1234(pc),a5
        move.l  #$35000001,d7
        jsr     -108(a6)
        lea     m_ret(pc),a0
        bsr     puts
        move.l  $202(a6),d0
        bsr     hex8
        move.l  0.w,d0
        bsr     hex8
        bsr     nl
        ENDC
        IFEQ MODE-3
        illegal
        ENDC
        IFEQ MODE-5
        clr.l   CHIPMARK+16
        clr.l   CHIPMARK+20
        lea     stub_cold(pc),a0
        lea     STUBS,a1
        moveq   #(stub_end-stub_cold)/2-1,d0
.cp:    move.w  (a0)+,(a1)+
        dbra    d0,.cp
        move.l  #STUBS,$2A(a6)
        move.l  #STUBS+(stub_cool-stub_cold),$2E(a6)
        ; ChkSum : complément de la somme des mots $22..$50
        lea     $22(a6),a0
        moveq   #0,d1
        moveq   #($52-$22)/2-1,d0
.cs:    add.w   (a0)+,d1
        dbra    d0,.cs
        not.w   d1
        move.w  d1,$52(a6)
        ENDC
        IFGE MODE-4
        lea     m_rb(pc),a0
        bsr     puts
        lea     2.w,a0              ; le bootblock tourne en mode UTILISATEUR : RESET exige Supervisor()
        lea     resetcode(pc),a5
        jsr     -30(a6)
        ENDC
idle:   lea     m_idle(pc),a0
        bsr     puts
.w:     bra.s   .w

        cnop    0,4
resetcode:
        reset
        jmp     (a0)

stub_cold:
        addq.l  #1,CHIPMARK+16
        jmp     (a5)
stub_cool:
        addq.l  #1,CHIPMARK+20
        rts
stub_end:

; mark : A3 = zone ; si 'CHWM' présent incrémente le compteur, sinon l'initialise à 1. Affiche avant/après.
mark:   move.l  (a3),d0
        bsr     hex8
        move.l  4(a3),d0
        bsr     hex8
        cmp.l   #'CHWM',(a3)
        beq.s   .inc
        move.l  #'CHWM',(a3)
        clr.l   4(a3)
.inc:   addq.l  #1,4(a3)
        move.l  4(a3),d0
        rts

; hex8 : affiche D0 en 8 chiffres hexa + espace
hex8:   movem.l d0-d2,-(a7)
        move.l  d0,d2
        moveq   #7,d1
.h:     rol.l   #4,d2
        move.b  d2,d0
        and.b   #$F,d0
        add.b   #'0',d0
        cmp.b   #'9',d0
        bls.s   .o
        addq.b  #7,d0
.o:     bsr.s   putc
        dbra    d1,.h
        moveq   #' ',d0
        bsr.s   putc
        movem.l (a7)+,d0-d2
        rts
nl:     move.l  d0,-(a7)
        moveq   #13,d0
        bsr.s   putc
        moveq   #10,d0
        bsr.s   putc
        move.l  (a7)+,d0
        rts
puts:   move.l  d0,-(a7)
.p:     move.b  (a0)+,d0
        beq.s   .e
        bsr.s   putc
        bra.s   .p
.e:     move.l  (a7)+,d0
        rts
putc:   movem.l d0/d2,-(a7)
        move.w  #$4000,d2
.wt:    btst    #13-8,SERDATR
        bne.s   .tx
        dbra    d2,.wt
.tx:    and.w   #$FF,d0
        or.w    #$100,d0
        move.w  d0,SERDAT
        movem.l (a7)+,d0/d2
        rts

v_cafe: dc.l    $CAFEBABE
v_1234: dc.l    $12345678
m_head: dc.b    "CHW mode ",0
m_low:  dc.b    "LOW 0/100/104 ",0
m_eb:   dc.b    "EB base/MaxLoc/MaxExt/StkUp/StkLo ",0
m_cap:  dc.b    "CAP cold/cool/warm LA0 LA1 Attn VBF ",0
m_mh:   dc.b    "MH adr/pri/attr/lower/upper/free ",0
m_mark: dc.b    "MARK chip(avant cnt) [slow(avant cnt)] coldcnt coolcnt ",0
m_ret:  dc.b    "RET LA0 low0 ",0
m_rb:   dc.b    "REBOOT",13,10,0
m_idle: dc.b    "IDLE",13,10,0
        even
