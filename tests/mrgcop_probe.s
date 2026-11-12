; tests/mrgcop_probe.s - MrgCop merge probe for OUR ROM (implementation track, authored).
; For each case of the table below (the probed lists of docs/analysis/graphics-display-v34.md §5.3-5.4, plus a
; UCopList WAIT below its ViewPort), fills a View and one or two ViewPorts (fake plane addresses $2i000), builds the
; UCopList with CWait/CMove/CBump, calls MakeVPort on each ViewPort then MrgCop, and prints the hardware lists:
;   "MC <n> L <word> ..." (long frame) and, for an interlaced View, "MC <n> S <word> ..." and "MC <n> A <lof> <shf>",
; up to the end WAIT $FFFF,$FFFE; then "MC END". tests/mrgcop_check.py compares them with §5.
; A case whose View Modes word has bit 15 set is shown (LoadView) before its list is printed, after SetRGB4(vp, 1, 0,
; 15, 15) and ScrollVPort with RxOffset 3: both patch the displayed list in place (§7.3); the previous View comes back
; afterwards. Last, "MC KEEP <1|0>": a View whose only ViewPort is VP_HIDE (no CopList to merge) keeps the
; long-frame list it had, pointer and contents (§5.1).
; Run by tests/mrgcop_probe.sh as a CLI command from a startup-sequence.

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018

LVO_AllocMem        EQU -198
LVO_OpenLibrary     EQU -552
LVO_CloseLibrary    EQU -414
LVO_MrgCop          EQU -210
LVO_MakeVPort       EQU -216
LVO_LoadView        EQU -222
LVO_SetRGB4         EQU -288
LVO_ScrollVPort     EQU -588
gb_ActiView         EQU 34
LVO_CBump           EQU -366
LVO_CMove           EQU -372
LVO_CWait           EQU -378
LVO_FreeVPortCopLists EQU -540
LVO_FreeCprList     EQU -564

; structure offsets (graphics/view.h, gfx.h, copper.h, 1.3)
v_ViewPort  EQU 0
v_LOFCprList EQU 4
v_SHFCprList EQU 8
v_DyOffset  EQU 12
v_DxOffset  EQU 14
v_Modes     EQU 16
vp_Next     EQU 0
vp_ColorMap EQU 4
vp_DspIns   EQU 8
vp_UCopIns  EQU 20
vp_DWidth   EQU 24
vp_DHeight  EQU 26
vp_DxOffset EQU 28
vp_DyOffset EQU 30
vp_Modes    EQU 32
vp_RasInfo  EQU 36
VP_SIZE     EQU 40
ri_BitMap   EQU 4
bm_BytesPerRow EQU 0
bm_Rows     EQU 2
bm_Depth    EQU 5
bm_Planes   EQU 8
cm_Count    EQU 2
cm_ColorTable EQU 4

; case: View Modes, then two ViewPorts (vp Modes, DWidth, DHeight, DyOffset, depth, BytesPerRow, ColorMap 0/1,
; UCopList program 0/1/2; vp Modes -1 = no second ViewPort) - 17 words
CASE_SIZE   EQU 34

                section code,code
start:
        move.l  4.w,a6
        lea     gfxname(pc),a1
        moveq   #0,d0
        jsr     LVO_OpenLibrary(a6)
        move.l  d0,a5                ; a5 = GfxBase
        tst.l   d0
        beq     .done
        lea     m_begin(pc),a0
        bsr     puts
        lea     cases(pc),a3
        moveq   #1,d7                ; d7 = case number
.case:
        cmp.w   #$7FFF,(a3)
        beq     .end
        lea     view(pc),a4
        clr.l   v_LOFCprList(a4)
        clr.l   v_SHFCprList(a4)
        move.w  #$2C,v_DyOffset(a4)
        move.w  #$81,v_DxOffset(a4)
        move.w  (a3),d0
        and.w   #$7FFF,d0
        move.w  d0,v_Modes(a4)
        lea     vp0(pc),a0
        move.l  a0,v_ViewPort(a4)
        lea     2(a3),a1
        lea     ri0(pc),a2
        bsr     setvp
        clr.l   vp_Next(a0)
        cmp.w   #-1,18(a3)
        beq.s   .one
        lea     vp1(pc),a2
        move.l  a2,vp_Next(a0)
        move.l  a2,a0
        lea     18(a3),a1
        lea     ri1(pc),a2
        bsr     setvp
        clr.l   vp_Next(a0)
.one:
        lea     vp0(pc),a2           ; MakeVPort on each ViewPort
.mk:
        move.l  a6,-(sp)
        move.l  a5,a6
        move.l  a4,a0
        move.l  a2,a1
        jsr     LVO_MakeVPort(a6)
        move.l  (sp)+,a6
        move.l  vp_Next(a2),d0
        move.l  d0,a2
        bne.s   .mk
        move.l  a6,-(sp)
        move.l  a5,a6
        move.l  a4,a1
        jsr     LVO_MrgCop(a6)
        move.l  (sp)+,a6
        tst.w   (a3)
        bpl.s   .print
        bsr     live
.print:
        moveq   #'L',d0
        move.l  v_LOFCprList(a4),a2
        bsr     plist
        btst    #2,v_Modes+1(a4)
        beq.s   .free
        moveq   #'S',d0
        move.l  v_SHFCprList(a4),a2
        bsr     plist
        bsr     phead
        moveq   #'A',d1
        bsr     putc
        move.l  v_LOFCprList(a4),d0
        bsr     phex8
        move.l  v_SHFCprList(a4),d0
        bsr     phex8
        bsr     nl
.free:
        move.l  a6,-(sp)
        move.l  a5,a6
        tst.w   (a3)
        bpl.s   .notlive
        move.l  oldview(pc),a1       ; the previous display back
        jsr     LVO_LoadView(a6)
.notlive:
        lea     vp0(pc),a2
.fr:
        move.l  a2,a0
        jsr     LVO_FreeVPortCopLists(a6)
        move.l  vp_Next(a2),d0
        move.l  d0,a2
        bne.s   .fr
        move.l  v_LOFCprList(a4),a0
        jsr     LVO_FreeCprList(a6)
        move.l  v_SHFCprList(a4),d0
        beq.s   .fr2
        move.l  d0,a0
        jsr     LVO_FreeCprList(a6)
.fr2:
        move.l  (sp)+,a6
        lea     CASE_SIZE(a3),a3
        addq.w  #1,d7
        bra     .case
.end:
        lea     view(pc),a4          ; no CopList: MrgCop leaves the View's lists alone
        lea     vp0(pc),a0
        move.l  a0,v_ViewPort(a4)
        clr.l   vp_Next(a0)
        move.w  #$2000,vp_Modes(a0)  ; VP_HIDE
        clr.w   v_Modes(a4)
        lea     keepblk(pc),a1
        move.l  a1,v_LOFCprList(a4)
        clr.l   v_SHFCprList(a4)
        move.l  a6,-(sp)
        move.l  a5,a6
        move.l  a4,a1
        jsr     LVO_MrgCop(a6)
        move.l  (sp)+,a6
        moveq   #0,d2
        lea     keepblk(pc),a1
        cmpa.l  v_LOFCprList(a4),a1
        bne.s   .kp
        moveq   #4-1,d0
.kc:    cmp.l   #$5A5A5A5A,(a1)+
        dbne    d0,.kc
        bne.s   .kp
        moveq   #1,d2
.kp:    lea     m_keep(pc),a0
        bsr     puts
        move.l  d2,d0
        bsr     phex8
        bsr     nl
        lea     m_end(pc),a0
        bsr     puts
        move.l  a5,a1
        jsr     LVO_CloseLibrary(a6)
.done:
        moveq   #0,d0
        rts

; live(a4 = View, a5 = GfxBase): shows the View, then SetRGB4 on colour 1 and ScrollVPort with RxOffset 3.
live:
        movem.l d2-d3/a6,-(sp)
        move.l  a5,a6
        lea     oldview(pc),a0
        move.l  gb_ActiView(a6),(a0)
        move.l  a4,a1
        jsr     LVO_LoadView(a6)
        lea     vp0(pc),a0
        moveq   #1,d0
        moveq   #0,d1
        moveq   #15,d2
        moveq   #15,d3
        jsr     LVO_SetRGB4(a6)
        lea     ri0(pc),a0
        move.w  #3,8(a0)             ; ri_RxOffset
        lea     vp0(pc),a0
        jsr     LVO_ScrollVPort(a6)
        movem.l (sp)+,d2-d3/a6
        rts

; setvp(a0 = ViewPort, a1 = its 8 words in the case, a2 = its RasInfo; RasInfo + BitMap follow each other): fills
; the ViewPort, RasInfo, BitMap and planes, the ColorMap and the UCopList. Preserves a0.
setvp:
        movem.l a0/a3,-(sp)
        move.l  a0,a3
        moveq   #VP_SIZE/2-1,d0
.clr:
        clr.w   (a0)+
        dbra    d0,.clr
        move.w  (a1)+,vp_Modes(a3)
        move.w  (a1)+,vp_DWidth(a3)
        move.w  (a1)+,vp_DHeight(a3)
        move.w  (a1)+,vp_DyOffset(a3)
        move.l  a2,vp_RasInfo(a3)
        clr.l   (a2)
        lea     12(a2),a0            ; its BitMap
        move.l  a0,ri_BitMap(a2)
        clr.l   8(a2)
        move.w  2(a1),bm_BytesPerRow(a0)
        move.w  vp_DHeight(a3),bm_Rows(a0)
        move.b  1(a1),bm_Depth(a0)
        lea     bm_Planes(a0),a0
        move.l  #$20000,d0
        moveq   #7,d1
.pl:
        move.l  d0,(a0)+
        add.l   #$1000,d0
        dbra    d1,.pl
        tst.w   4(a1)
        beq.s   .nocm
        lea     cmap(pc),a0
        move.l  a0,vp_ColorMap(a3)
.nocm:
        move.w  6(a1),d0
        beq.s   .ret
        bsr     mkucl
.ret:
        movem.l (sp)+,a0/a3
        rts

; mkucl(a3 = ViewPort, d0.w = program 1/2): a new UCopList (12 bytes, CLEAR, freed by FreeVPortCopLists) filled
; through CWait/CMove/CBump (no UCopperListInit: the first call makes the CopList).
mkucl:
        movem.l d2/a2/a6,-(sp)
        lea     prog1(pc),a2
        cmp.w   #1,d0
        beq.s   .p
        lea     prog2(pc),a2
.p:
        move.l  4.w,a6
        moveq   #12,d0
        move.l  #$10001,d1           ; MEMF_PUBLIC | MEMF_CLEAR
        jsr     LVO_AllocMem(a6)
        move.l  d0,vp_UCopIns(a3)
        beq.s   .ret
        move.l  a5,a6
.ins:
        move.w  (a2)+,d2             ; 0 MOVE, 1 WAIT, -1 end
        bmi.s   .ret
        move.w  (a2)+,d0
        move.w  (a2)+,d1
        move.l  vp_UCopIns(a3),a1
        tst.w   d2
        bne.s   .w
        jsr     LVO_CMove(a6)
        bra.s   .b
.w:
        jsr     LVO_CWait(a6)
.b:
        move.l  vp_UCopIns(a3),a1
        jsr     LVO_CBump(a6)
        bra.s   .ins
.ret:
        movem.l (sp)+,d2/a2/a6
        rts

; plist(d0.b = 'L'/'S', a2 = hardware list): "MC <n> <c> <word> ..." up to WAIT $FFFF,$FFFE (2000 words at most).
plist:
        move.w  d0,-(sp)
        bsr.s   phead
        move.w  (sp)+,d1
        bsr     putc
        move.w  #1000,d6
.ent:
        move.w  (a2)+,d0
        bsr     phex4
        move.w  (a2)+,d0
        bsr     phex4
        cmp.l   #$FFFFFFFE,-4(a2)
        beq.s   .nl
        subq.w  #1,d6
        bne.s   .ent
.nl:
        bra     nl
; phead: "MC <n> "
phead:
        lea     m_mc(pc),a0
        bsr.s   puts
        move.w  d7,d0
        bsr.s   phex4
        moveq   #' ',d1
        bra.s   putc

puts:
        move.b  (a0)+,d1
        beq.s   .r
        bsr.s   putc
        bra.s   puts
.r:     rts
nl:     moveq   #10,d1
        bra.s   putc
; phex8(d0.l): " XXXXXXXX"
phex8:
        move.l  d0,-(sp)
        swap    d0
        bsr.s   phex4
        move.l  (sp)+,d0
        bra.s   phex4c
; phex4(d0.w): " XXXX"
phex4:
        moveq   #' ',d1
        bsr.s   putc
phex4c:
        movem.l d0/d2,-(sp)
        moveq   #3,d2
.h:     rol.w   #4,d0
        move.w  d0,d1
        and.w   #15,d1
        add.b   #'0',d1
        cmp.b   #'9',d1
        bls.s   .o
        addq.b  #7,d1
.o:     bsr.s   putc
        dbra    d2,.h
        movem.l (sp)+,d0/d2
        rts
putc:
        move.w  d0,-(sp)
.w:     move.w  SERDATR,d0
        btst    #13,d0
        beq.s   .w
        and.w   #$FF,d1
        or.w    #$100,d1
        move.w  d1,SERDAT
        move.w  (sp)+,d0
        rts

; UCopList programs: (0 MOVE / 1 WAIT, word 1, word 2), -1 = end
prog1:  dc.w    1,10,0, 0,$180,$F00, 1,20,$40, 0,$180,$0F0, 1,10000,255, -1   ; §5.3
prog2:  dc.w    1,150,0, 0,$180,$00F, 1,10000,255, -1                       ; a WAIT below the ViewPort

cases:
        dc.w    0, $0000,320,200,0,2,40,1,0, -1,0,0,0,0,0,0,0          ; 1 §5.3 LORES 2 planes, ColorMap of 4
        dc.w    0, $0000,320,256,0,2,40,0,0, -1,0,0,0,0,0,0,0          ; 2 256 lines: line 255 at $DE
        dc.w    0, $8000,672,256,0,4,84,0,0, -1,0,0,0,0,0,0,0          ; 3 HIRES 4 planes, DDFSTOP $D4
        dc.w    0, $0000,320,200,0,1,40,0,1, -1,0,0,0,0,0,0,0          ; 4 §5.3 UCopList
        dc.w    0, $0000,320,100,0,1,40,0,0, $8000,640,100,102,1,80,0,0 ; 5 §5.4 stacked, one empty line
        dc.w    0, $0000,320,100,0,1,40,0,0, $0000,320,100,100,1,40,0,0 ; 6 §5.4 contiguous
        dc.w    0, $0000,320,100,0,1,40,0,2, -1,0,0,0,0,0,0,0          ; 7 UCopList WAIT below the ViewPort
        dc.w    4, $0004,320,400,0,1,40,0,0, -1,0,0,0,0,0,0,0          ; 8 §5.3 interlaced
        dc.w    $8000, $0000,320,200,0,2,40,1,0, -1,0,0,0,0,0,0,0      ; 9 case 1 shown, SetRGB4 + ScrollVPort
        dc.w    $7FFF

cmap:   dc.b    0,0
        dc.w    4
        dc.l    ctab
ctab:   dc.w    $000,$F00,$0F0,$FF0

gfxname:  dc.b  "graphics.library",0
m_begin:  dc.b  "MC BEGIN",10,0
m_mc:     dc.b  "MC",0
m_keep:   dc.b  "MC KEEP",0
m_end:    dc.b  "MC END",10,0
                even
keepblk:  dc.l  $5A5A5A5A,$5A5A5A5A,$5A5A5A5A,$5A5A5A5A
                even

                cnop    0,4
oldview:  ds.l  1
view:     ds.b  18
                even
vp0:      ds.b  VP_SIZE
vp1:      ds.b  VP_SIZE
ri0:      ds.b  12+40
ri1:      ds.b  12+40
