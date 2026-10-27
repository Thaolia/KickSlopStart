; gdisp_probe.s — sonde boîte noire de la construction d'affichage de graphics.library (PISTE ANALYSE).
; ASSET DE TEST, PAS du code ROM. Code auteur ; structures publiques (graphics 1.3 : View, ViewPort,
; RasInfo, BitMap, ColorMap, CopList, cprlist, UCopList).
; Deux morceaux dans un même source :
;   - LOADER défini : bootblock qui lit BLOBSZ octets à l'offset disque 1024 dans une zone CHIP et y saute ;
;   - sinon : le corps de la sonde, binaire brut indépendant de la position, chargé par le bootblock.
; Toutes les sorties partent sur la série (SERDAT en scrutation), en hexadécimal.
; Les adresses de plans sont fictives ($2kiii) pour être lisibles dans les listes copper produites.

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018
BLOBSZ   EQU 24576

        IFD LOADER
boot:   movea.l a1,a5                   ; IOStdReq trackdisk fourni par strap
        move.l  #BLOBSZ,d0
        move.l  #$10002,d1              ; MEMF_CHIP|MEMF_CLEAR
        jsr     -198(a6)                ; AllocMem
        tst.l   d0
        beq.s   .ko
        movea.l d0,a4
        move.w  #2,28(a5)               ; io_Command = CMD_READ
        move.l  #BLOBSZ,36(a5)          ; io_Length
        move.l  a4,40(a5)               ; io_Data
        move.l  #1024,44(a5)            ; io_Offset
        movea.l a5,a1
        jsr     -456(a6)                ; DoIO
        jmp     (a4)
.ko:    moveq   #-1,d0
        rts
        ELSE

; ---------------------------------------------------------------- offsets (structures publiques)
V_VP     EQU 0
V_LOF    EQU 4
V_SHF    EQU 8
V_DY     EQU 12
V_DX     EQU 14
V_MODES  EQU 16
VP_NEXT  EQU 0
VP_CM    EQU 4
VP_DSP   EQU 8
VP_SPR   EQU 12
VP_CLR   EQU 16
VP_UCOP  EQU 20
VP_DW    EQU 24
VP_DH    EQU 26
VP_DX    EQU 28
VP_DY    EQU 30
VP_MODES EQU 32
VP_RI    EQU 36

; ---------------------------------------------------------------- variables (base a4)
O_GFX    EQU 0
O_EXEC   EQU 4
O_OLDV   EQU 8
O_VIEW   EQU 12                         ; View 18 octets (+pad)
O_VPS    EQU 32                         ; 2 ViewPorts de 40
O_RI     EQU 112                        ; 2 x (RI 12 + RI2 12)
O_BM     EQU 160                        ; 2 x (BM 40 + BM2 40)
O_UCL    EQU 320                        ; 2 x UCopList 12
O_TMP    EQU 344                        ; 64 octets
O_END    EQU 408

start:  lea     vars(pc),a4
        move.l  4.w,a6
        move.l  a6,O_EXEC(a4)
        lea     gfxname(pc),a1
        moveq   #0,d0
        jsr     -552(a6)                ; OpenLibrary
        move.l  d0,O_GFX(a4)
        movea.l d0,a6
        move.l  $22(a6),O_OLDV(a4)      ; ActiView au moment de la sonde
        lea     m_head(pc),a0
        bsr     puts
        move.l  a6,d0
        bsr     hex8
        move.l  O_OLDV(a4),d0
        bsr     hex8
        bsr     nl

; ----- GfxBase $22..$F0 (mots) et VBlankFrequency d'exec
        lea     m_gb(pc),a0
        bsr     puts
        lea     $22(a6),a0
        moveq   #($F0-$22)/2-1,d1
        bsr     dumpw
        lea     m_vbf(pc),a0
        bsr     puts
        movea.l O_EXEC(a4),a0
        moveq   #0,d0
        move.b  $212(a0),d0
        bsr     hex4
        move.b  $213(a0),d0
        bsr     hex4
        bsr     nl
        bsr     dumpcopinit

; ----- InitView / InitVPort sur zones pré-remplies à $AA
        lea     m_iv(pc),a0
        bsr     puts
        lea     O_TMP(a4),a1
        bsr     fillaa
        lea     O_TMP(a4),a1
        jsr     -360(a6)                ; InitView(a1)
        lea     O_TMP(a4),a0
        moveq   #10-1,d1
        bsr     dumpw
        lea     m_ivp(pc),a0
        bsr     puts
        lea     O_TMP(a4),a1
        bsr     fillaa
        lea     O_TMP(a4),a0
        jsr     -204(a6)                ; InitVPort(a0)
        lea     O_TMP(a4),a0
        moveq   #22-1,d1
        bsr     dumpw

; ----- ColorMap
        lea     m_cm(pc),a0
        bsr     puts
        moveq   #4,d0
        jsr     -570(a6)                ; GetColorMap(4)
        movea.l d0,a3
        bsr     hex8
        move.l  (a3),d0
        bsr     hex8
        move.l  4(a3),d0
        bsr     hex8
        movea.l 4(a3),a0
        moveq   #3,d1
        bsr     dumpw
        lea     m_rgb(pc),a0
        bsr     puts
        moveq   #0,d4
.gr:    movea.l a3,a0
        move.l  d4,d0
        jsr     -582(a6)                ; GetRGB4
        bsr     hex8
        addq.l  #1,d4
        cmp.l   #5,d4
        bne.s   .gr
        movea.l a3,a0
        moveq   #2,d0
        moveq   #15,d1
        moveq   #$10,d2                 ; bits hauts doivent être masqués
        moveq   #$21,d3
        jsr     -630(a6)                ; SetRGB4CM(cm,2,15,$10,$21)
        bsr     hex8
        movea.l a3,a0
        moveq   #4,d0
        moveq   #1,d1
        moveq   #1,d2
        moveq   #1,d3
        jsr     -630(a6)                ; SetRGB4CM(cm,4,...) hors bornes
        bsr     hex8
        suba.l  a0,a0
        moveq   #0,d0
        moveq   #1,d1
        moveq   #1,d2
        moveq   #1,d3
        jsr     -630(a6)                ; SetRGB4CM(NULL,...)
        bsr     hex8
        movea.l a3,a0
        moveq   #2,d0
        jsr     -582(a6)
        bsr     hex8
        bsr     nl
        moveq   #40,d0
        jsr     -570(a6)                ; GetColorMap(40) : au-delà de la table par défaut ?
        movea.l d0,a3
        lea     m_cm40(pc),a0
        bsr     puts
        movea.l 4(a3),a0
        moveq   #40-1,d1
        bsr     dumpw

; ----- configurations MakeVPort + MrgCop
        lea     cfgtab(pc),a2
.cfg:   tst.w   (a2)
        bmi.s   .cfgend
        bsr     build
        bsr     dumpall
        bra.s   .cfg
.cfgend:

; ----- LoadView / ScrollVPort / SetRGB4 / LoadRGB4 / WaitBOVP sur une vue réelle
        lea     cfg_lace(pc),a2
        bsr     build
        movea.l O_GFX(a4),a6
        lea     O_VIEW(a4),a1
        jsr     -222(a6)                ; LoadView(view entrelacée)
        lea     m_lv(pc),a0
        bsr     puts
        bsr     gbview
        bsr     dumpcopinit
        lea     O_VPS(a4),a3
        movea.l VP_RI(a3),a0
        move.w  #16,8(a0)               ; RxOffset
        move.w  #3,10(a0)               ; RyOffset
        movea.l a3,a0
        jsr     -588(a6)                ; ScrollVPort
        lea     m_scr(pc),a0
        bsr     puts
        bsr     nl
        bsr     dumpall2
        ; non entrelacé
        lea     cfg_scr(pc),a2
        bsr     build
        movea.l O_GFX(a4),a6
        lea     O_VIEW(a4),a1
        jsr     -222(a6)                ; LoadView
        lea     m_lv(pc),a0
        bsr     puts
        bsr     gbview
        bsr     dumpcopinit
        lea     O_VPS(a4),a3
        movea.l VP_RI(a3),a0
        move.w  #21,8(a0)
        move.w  #5,10(a0)
        movea.l a3,a0
        jsr     -588(a6)                ; ScrollVPort
        lea     m_scr(pc),a0
        bsr     puts
        bsr     nl
        bsr     dumpall2
        ; couleurs à chaud
        lea     O_VPS(a4),a0
        moveq   #1,d0
        moveq   #1,d1
        moveq   #2,d2
        moveq   #3,d3
        jsr     -288(a6)                ; SetRGB4(vp,1,1,2,3)
        move.l  d0,d4
        lea     O_VPS+40(a4),a0
        lea     rgbtab(pc),a1
        moveq   #2,d0
        jsr     -192(a6)                ; LoadRGB4(vp1,tab,2)
        lea     O_VPS(a4),a0
        moveq   #40,d0
        moveq   #1,d1
        moveq   #2,d2
        moveq   #3,d3
        jsr     -288(a6)                ; SetRGB4(vp,40,...) hors bornes
        move.l  d0,d5
        lea     m_rgbset(pc),a0
        bsr     puts
        move.l  d4,d0
        bsr     hex8
        move.l  d5,d0
        bsr     hex8
        bsr     nl
        bsr     dumpall2
        bsr     dumpcopinit
        ; temps : VBeamPos, WaitTOF, WaitBOVP
        lea     m_beam(pc),a0
        bsr     puts
        jsr     -384(a6)
        bsr     hex8
        jsr     -270(a6)                ; WaitTOF
        jsr     -384(a6)
        bsr     hex8
        lea     O_VPS(a4),a0
        jsr     -402(a6)                ; WaitBOVP(vp0)
        jsr     -384(a6)
        bsr     hex8
        lea     O_VPS+40(a4),a0
        jsr     -402(a6)                ; WaitBOVP(vp1)
        jsr     -384(a6)
        bsr     hex8
        bsr     nl
        ; LoadView(NULL)
        suba.l  a1,a1
        jsr     -222(a6)
        lea     m_lvn(pc),a0
        bsr     puts
        bsr     gbview
        bsr     dumpcopinit
        ; FreeVPortCopLists : pointeurs remis à zéro ?
        lea     O_VPS(a4),a0
        jsr     -540(a6)
        lea     m_fvp(pc),a0
        bsr     puts
        lea     O_VPS(a4),a0
        moveq   #12-1,d1
        bsr     dumpw
        ; restauration
        movea.l O_OLDV(a4),a1
        jsr     -222(a6)
        lea     m_end(pc),a0
        bsr     puts
.idle:  bra.s   .idle

; ---------------------------------------------------------------- construction d'une configuration
; a2 = descripteur : w vModes, vDx(0=défaut), vDy(0=défaut), nvp, puis nvp x 14 mots :
;  modes, DW, DH, Dx, Dy, depth, bpr, rows, rx, ry, depth2, rx2, cmcount, ucop
; En sortie a2 pointe après le descripteur.
build:  movem.l d2-d7/a3/a5,-(a7)
        movea.l O_GFX(a4),a6
        lea     O_VIEW(a4),a0
        move.w  #O_END-O_VIEW-1,d0
.clr:   clr.b   (a0)+
        dbra    d0,.clr
        lea     m_cfg(pc),a0
        bsr     puts
        movea.l a2,a0
        moveq   #4-1,d1
        bsr     dumpw
        lea     O_VIEW(a4),a1
        jsr     -360(a6)                ; InitView
        lea     O_VIEW(a4),a1
        move.w  (a2)+,V_MODES(a1)
        move.w  (a2)+,d0
        beq.s   .ndx
        move.w  d0,V_DX(a1)
.ndx:   move.w  (a2)+,d0
        beq.s   .ndy
        move.w  d0,V_DY(a1)
.ndy:   move.w  (a2)+,d7                ; nvp
        moveq   #0,d6                   ; index vp
        lea     O_VIEW+V_VP(a4),a5      ; adresse du lien précédent
.vp:    cmp.w   d7,d6
        bge     .vpd
        movea.l a2,a0
        moveq   #14-1,d1
        bsr     dumpw
        move.l  d6,d0
        mulu    #40,d0
        lea     O_VPS(a4),a3
        adda.l  d0,a3
        movea.l a3,a0
        jsr     -204(a6)                ; InitVPort
        move.l  a3,(a5)
        movea.l a3,a5                   ; VP_NEXT = 0
        move.w  (a2)+,VP_MODES(a3)
        move.w  (a2)+,VP_DW(a3)
        move.w  (a2)+,VP_DH(a3)
        move.w  (a2)+,VP_DX(a3)
        move.w  (a2)+,VP_DY(a3)
        ; RasInfo + BitMap
        move.l  d6,d0
        mulu    #24,d0
        lea     O_RI(a4),a0
        adda.l  d0,a0                   ; RI
        move.l  a0,VP_RI(a3)
        move.l  d6,d0
        mulu    #80,d0
        lea     O_BM(a4),a1
        adda.l  d0,a1                   ; BM
        move.l  a1,4(a0)
        move.w  (a2)+,d2                ; depth
        move.w  (a2)+,d3                ; bpr
        move.w  (a2)+,d4                ; rows
        move.w  (a2)+,8(a0)             ; RxOffset
        move.w  (a2)+,10(a0)            ; RyOffset
        move.l  #$20000,d5
        move.l  d6,d0
        swap    d0
        add.l   d0,d5                   ; plans vp k : $2k000 + i*$1000
        bsr     setbm
        move.w  (a2)+,d2                ; depth2
        move.w  (a2)+,d0                ; rx2
        tst.w   d2
        beq.s   .npf2
        lea     12(a0),a3               ; RI2 (a3 temporairement)
        move.l  a3,(a0)                 ; RI->Next
        lea     40(a1),a1
        move.l  a1,4(a3)
        move.w  d0,8(a3)
        move.l  #$28000,d5
        move.l  d6,d0
        swap    d0
        add.l   d0,d5
        bsr     setbm
        movea.l a5,a3
.npf2:  move.w  (a2)+,d0                ; cmcount
        beq.s   .ncm
        ext.l   d0
        jsr     -570(a6)                ; GetColorMap
        move.l  d0,VP_CM(a3)
.ncm:   move.w  (a2)+,d0                ; ucop
        beq.s   .nuc
        bsr     mkucop
.nuc:   addq.l  #1,d6
        bra     .vp
.vpd:   ; MakeVPort de chaque vp puis MrgCop
        movea.l O_VIEW+V_VP(a4),a3
.mk:    move.l  a3,d0
        beq.s   .mkd
        lea     O_VIEW(a4),a0
        movea.l a3,a1
        jsr     -216(a6)                ; MakeVPort(view,vp)
        movea.l VP_NEXT(a3),a3
        bra.s   .mk
.mkd:   lea     O_VIEW(a4),a1
        jsr     -210(a6)                ; MrgCop
        movem.l (a7)+,d2-d7/a3/a5
        rts

; a1 = BitMap, d2 depth, d3 bpr, d4 rows, d5 adresse du plan 0
setbm:  move.l  a1,-(a7)
        move.w  d3,(a1)
        move.w  d4,2(a1)
        move.b  d2,5(a1)
        addq.l  #8,a1
        moveq   #8-1,d0
.p:     move.l  d5,(a1)+
        add.l   #$1000,d5
        dbra    d0,.p
        movea.l (a7)+,a1
        rts

; a3 = vp, d6 = index : UCopList CINIT/CWAIT/CMOVE/CBUMP/CEND
mkucop: movem.l a2/a3/a5,-(a7)
        movea.l a3,a5
        move.l  d6,d0
        mulu    #12,d0
        lea     O_UCL(a4),a2
        adda.l  d0,a2
        movea.l a2,a0
        moveq   #10,d0
        jsr     -594(a6)                ; UCopperListInit(ucl,10)
        movea.l a2,a1
        moveq   #10,d0
        moveq   #0,d1
        jsr     -378(a6)                ; CWait(10,0)
        movea.l a2,a1
        jsr     -366(a6)                ; CBump
        movea.l a2,a1
        move.l  #$DFF180,d0
        move.l  #$0F00,d1
        jsr     -372(a6)                ; CMove(COLOR00,$F00)
        movea.l a2,a1
        jsr     -366(a6)
        movea.l a2,a1
        moveq   #20,d0
        moveq   #$40,d1
        jsr     -378(a6)                ; CWait(20,$40)
        movea.l a2,a1
        jsr     -366(a6)
        movea.l a2,a1
        move.l  #$DFF180,d0
        move.l  #$00F0,d1
        jsr     -372(a6)
        movea.l a2,a1
        jsr     -366(a6)
        movea.l a2,a1
        move.l  #10000,d0
        move.l  #255,d1
        jsr     -378(a6)                ; CEND
        movea.l a2,a1
        jsr     -366(a6)
        move.l  a2,VP_UCOP(a5)
        lea     m_ucl(pc),a0
        bsr     puts
        movea.l a2,a0
        moveq   #6-1,d1
        bsr     dumpw
        movem.l (a7)+,a2/a3/a5
        rts

; ---------------------------------------------------------------- dumps
dumpall:                                ; listes intermédiaires de chaque vp + listes matérielles
        movem.l a3,-(a7)
        movea.l O_VIEW+V_VP(a4),a3
.v:     move.l  a3,d0
        beq.s   .d
        lea     m_dsp(pc),a0
        bsr     puts
        movea.l VP_DSP(a3),a0
        bsr     dumpcl
        tst.l   VP_UCOP(a3)
        beq.s   .nu
        lea     m_ucop(pc),a0
        bsr     puts
        movea.l VP_UCOP(a3),a0
        movea.l 4(a0),a0
        bsr     dumpcl
.nu:    movea.l VP_NEXT(a3),a3
        bra.s   .v
.d:     movem.l (a7)+,a3
dumpall2:
        movem.l a3,-(a7)
        lea     m_lof(pc),a0
        bsr     puts
        movea.l O_VIEW+V_LOF(a4),a0
        bsr     dumpcpr
        lea     m_shf(pc),a0
        bsr     puts
        movea.l O_VIEW+V_SHF(a4),a0
        bsr     dumpcpr
        lea     m_cls(pc),a0            ; CopLStart/CopSStart de chaque DspIns
        bsr     puts
        movea.l O_VIEW+V_VP(a4),a3
.v2:    move.l  a3,d0
        beq.s   .d2
        movea.l VP_DSP(a3),a0
        move.l  a0,d0
        beq.s   .n2
        move.l  20(a0),d0
        bsr     hex8
        move.l  24(a0),d0
        bsr     hex8
.n2:    movea.l VP_NEXT(a3),a3
        bra.s   .v2
.d2:    bsr     nl
        movem.l (a7)+,a3
        rts

; a0 = CopList (intermédiaire) : en-tête puis instructions op:a:b ; suit CPRNXTBUF
dumpcl: movem.l d2-d4/a2,-(a7)
        move.l  a0,d0
        bsr     hex8
        beq     .z
        movea.l a0,a2
        move.w  28(a2),d0
        bsr     hex4
        move.w  30(a2),d0
        bsr     hex4
        move.w  32(a2),d0
        bsr     hex4
        bsr     nl
        move.w  #300,d4                 ; garde-fou
.blk:   movea.l 12(a2),a1               ; CopIns
        move.w  28(a2),d3               ; Count
        moveq   #0,d2
.i:     cmp.w   d3,d2
        bge.s   .end
        move.w  (a1),d0
        bsr     hex4
        move.w  2(a1),d0
        bsr     hex4
        move.w  4(a1),d0
        bsr     hex4
        moveq   #'|',d0
        bsr     putc
        move.w  (a1),d0
        and.w   #3,d0
        cmp.w   #2,d0
        bne.s   .nx
        movea.l 2(a1),a2                ; CPRNXTBUF -> CopList suivante
        bsr     nl
        bra.s   .blk
.nx:    addq.l  #6,a1
        addq.w  #1,d2
        move.w  d2,d0
        and.w   #7,d0
        bne.s   .nn
        bsr     nl
.nn:    subq.w  #1,d4
        bne.s   .i
.end:
.z:     bsr     nl
        movem.l (a7)+,d2-d4/a2
        rts

; a0 = cprlist : adresse, start, MaxCount puis mots jusqu'à $FFFF,$FFFE
dumpcpr:
        movem.l d2-d3/a2,-(a7)
        move.l  a0,d0
        bsr     hex8
        beq.s   .z
        movea.l a0,a2
        move.l  (a2),d0
        bsr     hex8
        move.l  4(a2),d0
        bsr     hex8
        move.w  8(a2),d0
        bsr     hex4
        bsr     nl
        movea.l 4(a2),a1
        moveq   #0,d2
        move.w  8(a2),d3
.i:     cmp.w   d3,d2
        bge.s   .z
        move.w  (a1)+,d0
        bsr     hex4
        move.w  (a1)+,d0
        bsr     hex4
        cmpi.w  #$FFFF,-4(a1)
        bne.s   .c
        cmpi.w  #$FFFE,-2(a1)
        beq.s   .z
.c:     addq.w  #1,d2
        move.w  d2,d0
        and.w   #7,d0
        bne.s   .i
        bsr     nl
        bra.s   .i
.z:     bsr     nl
        movem.l (a7)+,d2-d3/a2
        rts

dumpcopinit:
        lea     m_ci(pc),a0
        bsr     puts
        movea.l O_GFX(a4),a0
        movea.l $26(a0),a0
        move.l  a0,d0
        bsr     hex8
        bsr     nl
        moveq   #$C0/2-1,d1
        bra     dumpw

gbview: movea.l O_GFX(a4),a0
        move.l  $22(a0),d0
        bsr     hex8
        move.l  $26(a0),d0
        bsr     hex8
        move.l  $32(a0),d0
        bsr     hex8
        move.l  $36(a0),d0
        bsr     hex8
        move.w  $9E(a0),d0
        bsr     hex4
        lea     O_VIEW(a4),a0
        movea.l V_LOF(a0),a1
        move.l  4(a1),d0
        bsr     hex8
        move.l  V_SHF(a0),d0
        beq.s   .n
        movea.l d0,a1
        move.l  4(a1),d0
        bsr     hex8
.n:     bra     nl

; a0 = adresse, d1 = nombre de mots - 1
dumpw:  move.l  d2,-(a7)
        moveq   #0,d2
.w:     move.w  (a0)+,d0
        bsr     hex4
        addq.w  #1,d2
        move.w  d2,d0
        and.w   #15,d0
        bne.s   .n
        bsr     nl
.n:     dbra    d1,.w
        and.w   #15,d2
        beq.s   .e
        bsr     nl
.e:     move.l  (a7)+,d2
        rts

fillaa: moveq   #64-1,d0
.f:     move.b  #$AA,(a1)+
        dbra    d0,.f
        rts

hex8:   movem.l d0-d2,-(a7)
        moveq   #7,d1
        bra.s   hexn
hex4:   movem.l d0-d2,-(a7)
        swap    d0
        moveq   #3,d1
hexn:   rol.l   #4,d0
        move.l  d0,d2
        and.b   #$F,d0
        add.b   #'0',d0
        cmp.b   #'9',d0
        bls.s   .o
        addq.b  #7,d0
.o:     bsr.s   putc
        move.l  d2,d0
        dbra    d1,hexn
        moveq   #' ',d0
        bsr.s   putc
        movem.l (a7)+,d0-d2
        tst.l   d0
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

; ---------------------------------------------------------------- configurations
; vModes, vDx, vDy, nvp | modes, DW, DH, Dx, Dy, depth, bpr, rows, rx, ry, depth2, rx2, cm, ucop
cfgtab:
c01:    dc.w    0,0,0,1, $0000,320,200,0,0, 2,40,200,0,0, 0,0, 4,0       ; lores 2 plans
c02:    dc.w    0,0,0,1, $8000,640,200,0,0, 4,80,200,0,0, 0,0, 16,0      ; hires 4 plans
c03:    dc.w    4,0,0,1, $0004,320,400,0,0, 1,40,400,0,0, 0,0, 2,0       ; entrelacé
c04:    dc.w    0,0,0,2, $0000,320,100,0,0, 2,40,100,0,0, 0,0, 4,0       ; deux vp empilées
        dc.w             $8000,640,100,0,102, 1,80,100,0,0, 0,0, 2,0
c05:    dc.w    0,0,0,1, $0400,320,200,0,0, 2,40,200,0,0, 2,3, 16,0      ; DUALPF, PF2 rx=3
c06:    dc.w    0,0,0,1, $0800,320,200,0,0, 6,40,200,0,0, 0,0, 16,0      ; HAM
c07:    dc.w    0,0,0,1, $0080,320,200,0,0, 6,40,200,0,0, 0,0, 32,0      ; EHB
c08:    dc.w    0,0,0,1, $4000,320,200,0,0, 2,40,200,0,0, 0,0, 32,0      ; SPRITES
c09:    dc.w    0,0,0,1, $0000,320,200,0,0, 2,80,400,5,3, 0,0, 4,0       ; défilement rx=5 ry=3
c10:    dc.w    0,0,0,1, $0000,320,200,-10,0, 1,40,200,0,0, 0,0, 2,0     ; Dx=-10 (rognage gauche)
c11:    dc.w    0,0,0,1, $0000,400,200,0,0, 1,50,200,0,0, 0,0, 2,0       ; DW=400 (rognage droit)
c12:    dc.w    0,0,0,1, $8000,640,256,0,0, 4,80,256,0,0, 0,0, 16,0      ; hires 4 plans 256 lignes
c13:    dc.w    0,0,0,1, $0000,320,256,0,0, 1,40,256,0,0, 0,0, 2,0       ; lores 256 lignes
c14:    dc.w    0,0,0,1, $0000,320,200,0,0, 1,40,200,0,0, 0,0, 2,1       ; UCopList
c15:    dc.w    0,0,0,2, $0000,320,100,0,0, 1,40,100,0,0, 0,0, 2,0       ; VP_HIDE sur vp1
        dc.w             $2000,320,100,0,110, 1,40,100,0,0, 0,0, 2,0
c16:    dc.w    0,0,0,1, $0000,200,100,20,50, 1,40,200,0,0, 0,0, 2,0     ; Dx=20 Dy=50 DW=200
c17:    dc.w    0,$85,$30,1, $0000,320,200,0,0, 1,40,200,0,0, 0,0, 2,0   ; View Dx=$85 Dy=$30
c18:    dc.w    0,0,0,1, $8000,640,200,0,0, 2,80,200,3,0, 0,0, 4,0       ; hires rx=3
c19:    dc.w    0,0,0,1, $0004,320,400,0,0, 1,40,400,0,0, 0,0, 2,0       ; vp LACE, vue non LACE
c20:    dc.w    4,0,0,1, $0000,320,200,0,0, 1,40,200,0,0, 0,0, 2,0       ; vue LACE, vp non LACE
c21:    dc.w    0,0,0,1, $0000,320,200,0,0, 1,40,200,0,0, 0,0, 0,0       ; sans ColorMap
c22:    dc.w    0,0,0,2, $0000,320,100,0,0, 1,40,100,0,0, 0,0, 2,0       ; vp1 Dy=100 (contiguë)
        dc.w             $0000,320,100,0,100, 1,40,100,0,0, 0,0, 2,0
c23:    dc.w    0,0,0,1, $8000,640,200,0,0, 5,80,200,0,0, 0,0, 32,0      ; hires 5 plans demandés
c24:    dc.w    0,0,0,1, $0400,320,200,0,0, 3,40,200,0,0, 3,0, 16,0      ; DUALPF 3+3
        dc.w    -1
cfg_lace:
        dc.w    4,0,0,2, $0004,320,200,0,0, 2,40,400,0,0, 0,0, 4,0
        dc.w             $8004,640,100,0,210, 1,80,200,0,0, 0,0, 2,0
cfg_scr:
        dc.w    0,0,0,2, $0000,320,100,0,0, 2,80,300,0,0, 0,0, 4,0
        dc.w             $8000,640,80,0,110, 1,80,100,0,0, 0,0, 2,0

rgbtab: dc.w    $0123,$0456

gfxname: dc.b   "graphics.library",0
m_head: dc.b    13,10,"GDISP gfx/actiview ",0
m_gb:   dc.b    "GB22..F0",13,10,0
m_vbf:  dc.b    "VBF ",0
m_ci:   dc.b    "COPINIT ",0
m_iv:   dc.b    "INITVIEW",13,10,0
m_ivp:  dc.b    "INITVPORT",13,10,0
m_cm:   dc.b    "CM4 ptr flags/type/count table ",0
m_rgb:  dc.b    "GETRGB4 0..4 SETCM(2) SETCM(4) SETCM(NULL) GET2 ",0
m_cm40: dc.b    "CM40",13,10,0
m_cfg:  dc.b    "=== CFG ",0
m_ucl:  dc.b    "UCL ",0
m_dsp:  dc.b    "DSP ",0
m_ucop: dc.b    "UCOP ",0
m_lof:  dc.b    "LOF ",0
m_shf:  dc.b    "SHF ",0
m_cls:  dc.b    "CLSTART ",0
m_lv:   dc.b    "LOADVIEW acti copinit LOFlist SHFlist gbModes LOFstart SHFstart ",0
m_lvn:  dc.b    "LOADVIEW(NULL) ",0
m_scr:  dc.b    "SCROLLVPORT",0
m_rgbset: dc.b  "SETRGB4 ret ret40 ",0
m_beam: dc.b    "BEAM avant/apresTOF/apresBOVP0/apresBOVP1 ",0
m_fvp:  dc.b    "FREEVPCL vp ",0
m_end:  dc.b    "END",13,10,0
        even
vars:   ds.b    O_END
        ENDC
