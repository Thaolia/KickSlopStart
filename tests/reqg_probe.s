; reqg_probe.s - requester gadgets in the gadget list functions, and a system gadget removed from a window's list
; (implementation track: our own test program; public ABI only: intuition/graphics .fd, intuition.h Gadget, Border,
; Requester, Window, Layer layouts, AutoDocs of Request, EndRequest, AddGList, RemoveGList, RefreshGadgets,
; RefreshGList, OffGadget).
; Two stages like glist_probe.s. A window (20,20) 400 x 100 with sizing, drag, depth and close gadgets, a requester R
; (10,15) 200 x 40 whose gadgets J, K, L (REQGADGET, bordered 30 x 10 boxes at (10,10), (60,10), (110,10) in R) carry
; GadgetID 'J', 'K', 'L'. Serial output:
;   "GQ <step> <d0 long> | <R list> / <window list>"   lists as in glist_probe.s
;   "GQ P <step> <pen J> <pen K> <pen L>"   read in R's layer at the middle of each top border, area cleared before
;   "GS <step> <d0 long> | <window list>"
;   "GS P <step> <front> <back>"           pixels not pen 0 on line 4 of the front / back depth gadget boxes, after
;                                          their area was cleared to pen 0 and RefreshGadgets(Window.FirstGadget)
;   "GQ END"
; Build and run: tests/reqg_probe.sh <out_dir> [rom]

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018
LOADSZ   EQU 8192

_AllocMem   EQU -198
_DoIO       EQU -456
_OpenLibrary EQU -552
_EndRequest EQU -120
_OffGadget  EQU -174
_OpenWindow EQU -204
_OpenWorkBench EQU -210
_RefreshGadgets EQU -222
_RemoveGadget EQU -228
_Request    EQU -240
_RefreshGList EQU -432
_AddGList   EQU -438
_RemoveGList EQU -444
_SetAPen    EQU -342
_RectFill   EQU -306
_ReadPixel  EQU -318

WD_RPORT EQU 50
WD_FIRSTGADGET EQU 62
GG_TYPE  EQU 16
GG_ID    EQU 38
RQ_GAD   EQU 16
RQ_LAYER EQU 32
GSIZE    EQU 44

boot:
        movea.l a1,a5
        move.l  #LOADSZ,d0
        move.l  #$10003,d1
        jsr     _AllocMem(a6)
        tst.l   d0
        beq.s   .ko
        movea.l d0,a4
        move.w  #2,28(a5)
        move.l  #LOADSZ,36(a5)
        move.l  a4,40(a5)
        clr.l   44(a5)
        movea.l a5,a1
        jsr     _DoIO(a6)
        lea     12+stage2-boot(a4),a0
        jmp     (a0)
.ko:    moveq   #-1,d0
        rts

; d7 = IntuitionBase, d6 = window, d5 = GfxBase, a5 = window RastPort, a4 = requester R.
stage2:
        lea     neww+26(pc),a0          ; pointers set at run time (the binary runs where stage 1 loaded it)
        lea     title(pc),a1
        move.l  a1,(a0)
        lea     bord+8(pc),a0
        lea     bxy(pc),a1
        move.l  a1,(a0)
        lea     gJ(pc),a0
        lea     bord(pc),a1
        moveq   #4-1,d0
.rel:   move.l  a1,18(a0)               ; GadgetRender (J, K, L, Z)
        lea     GSIZE(a0),a0
        dbra    d0,.rel
        lea     gK(pc),a0               ; K.Next = L
        lea     gL(pc),a1
        move.l  a1,(a0)
        lea     req(pc),a4
        lea     gJ(pc),a0
        move.l  a0,RQ_GAD(a4)           ; R.ReqGadget = J

        lea     intname(pc),a1
        moveq   #0,d0
        jsr     _OpenLibrary(a6)
        move.l  d0,d7
        beq     hang
        lea     gfxname(pc),a1
        moveq   #0,d0
        jsr     _OpenLibrary(a6)
        move.l  d0,d5
        beq     hang
        move.l  d7,a6
        jsr     _OpenWorkBench(a6)
        lea     neww(pc),a0
        jsr     _OpenWindow(a6)
        move.l  d0,d6
        beq     hang
        move.l  d6,a0
        move.l  WD_RPORT(a0),a5

        move.l  a4,a0                   ; 0: Request(R)
        move.l  d6,a1
        jsr     _Request(a6)
        moveq   #'0',d1
        bsr     qline

        move.l  d6,a0                   ; 1: AddGList(K->L, 0, 2, R)
        lea     gK(pc),a1
        moveq   #0,d0
        moveq   #2,d1
        move.l  a4,a2
        jsr     _AddGList(a6)
        moveq   #'1',d1
        bsr     qline

        move.l  d6,a0                   ; 2: RemoveGList(L, 1)
        lea     gL(pc),a1
        moveq   #1,d0
        jsr     _RemoveGList(a6)
        moveq   #'2',d1
        bsr     qline

        bsr     rclear                  ; 3: RefreshGList(K, 1)
        lea     gK(pc),a0
        move.l  d6,a1
        sub.l   a2,a2
        moveq   #1,d0
        jsr     _RefreshGList(a6)
        moveq   #'3',d0
        bsr     rpens

        bsr     rclear                  ; 4: RefreshGadgets(J) (J is second in R's list)
        lea     gJ(pc),a0
        move.l  d6,a1
        sub.l   a2,a2
        jsr     _RefreshGadgets(a6)
        moveq   #'4',d0
        bsr     rpens

        bsr     rclear                  ; 5: RefreshGList(J, -2)
        lea     gJ(pc),a0
        move.l  d6,a1
        sub.l   a2,a2
        moveq   #-2,d0
        jsr     _RefreshGList(a6)
        moveq   #'5',d0
        bsr     rpens

        bsr     rclear                  ; 6: OffGadget(J)
        lea     gJ(pc),a0
        move.l  d6,a1
        sub.l   a2,a2
        jsr     _OffGadget(a6)
        moveq   #'6',d0
        bsr     rpens

        move.l  d6,a0                   ; 7: AddGList(L, -1, 1, R)
        lea     gL(pc),a1
        moveq   #-1,d0
        moveq   #1,d1
        move.l  a4,a2
        jsr     _AddGList(a6)
        moveq   #'7',d1
        bsr     qline

        move.l  a4,a0                   ; 8: EndRequest(R), then RemoveGList(K, 1)
        move.l  d6,a1
        jsr     _EndRequest(a6)
        move.l  d6,a0
        lea     gK(pc),a1
        moveq   #1,d0
        jsr     _RemoveGList(a6)
        moveq   #'8',d1
        bsr     qline

        lea     gK(pc),a0               ; 9: RefreshGList(K, 1) with R down: must not draw or crash
        move.l  d6,a1
        sub.l   a2,a2
        moveq   #1,d0
        jsr     _RefreshGList(a6)
        moveq   #0,d0
        moveq   #'9',d1
        bsr     qline

        move.l  d6,a0                   ; Z: RemoveGadget of a gadget in no list
        lea     gZ(pc),a1
        jsr     _RemoveGadget(a6)
        moveq   #'Z',d1
        bsr     qline

        moveq   #0,d0                   ; system gadgets
        moveq   #'0',d1
        bsr     sline
        move.l  d6,a0                   ; 1: RemoveGList(Window.FirstGadget, 1)
        move.l  WD_FIRSTGADGET(a0),a1
        moveq   #1,d0
        jsr     _RemoveGList(a6)
        moveq   #'1',d1
        bsr     sline
        bsr     tclear                  ; 2: refresh from the head
        move.l  d6,a1
        move.l  WD_FIRSTGADGET(a1),a0
        sub.l   a2,a2
        jsr     _RefreshGadgets(a6)
        moveq   #'2',d0
        bsr     dpix

        lea     m_end(pc),a0
        bsr     puts
hang:   bra.s   hang

; qline(d0 = value, d1 = step): "GQ <step> <long> | <R list> / <window list>".
qline:
        movem.l d0-d1,-(sp)
        lea     m_gq(pc),a0
        bsr     puts
        move.l  4(sp),d0
        bsr     putc
        move.l  (sp),d0
        bsr     slong
        lea     m_bar(pc),a0
        bsr     puts
        move.l  RQ_GAD(a4),d2
        bsr     plist
        lea     m_sl(pc),a0
        bsr     puts
        move.l  d6,a0
        move.l  WD_FIRSTGADGET(a0),d2
        bsr     plist
        addq.l  #8,sp
        move.l  d7,a6
        bra     nl

; sline(d0 = value, d1 = step): "GS <step> <long> | <window list>".
sline:
        movem.l d0-d1,-(sp)
        lea     m_gs(pc),a0
        bsr     puts
        move.l  4(sp),d0
        bsr     putc
        move.l  (sp),d0
        bsr     slong
        lea     m_bar(pc),a0
        bsr     puts
        move.l  d6,a0
        move.l  WD_FIRSTGADGET(a0),d2
        bsr     plist
        addq.l  #8,sp
        move.l  d7,a6
        bra     nl

; plist(d2 = first gadget): " X" per gadget, system ones "sNN", "!" past 20.
plist:
        moveq   #20-1,d3
.l_lp:  tst.l   d2
        beq.s   .l_end
        move.l  d2,a0
        moveq   #' ',d0
        bsr     putc
        move.w  GG_TYPE(a0),d0
        bmi.s   .l_sys
        move.w  GG_ID(a0),d0
        bsr     putc
        bra.s   .l_nx
.l_sys: moveq   #'s',d0
        bsr     putc
        move.w  GG_TYPE(a0),d0
        bsr     hexb
.l_nx:  move.l  (a0),d2
        dbra    d3,.l_lp
        moveq   #'!',d0
        bsr     putc
.l_end: rts

; rclear: pen 0 over R's layer.
rclear:
        move.l  RQ_LAYER(a4),a1
        move.l  12(a1),a1               ; Layer.rp
        move.l  a1,-(sp)
        move.l  d5,a6
        moveq   #0,d0
        jsr     _SetAPen(a6)
        move.l  (sp)+,a1
        moveq   #0,d0
        moveq   #0,d1
        move.l  #199,d2
        moveq   #39,d3
        jsr     _RectFill(a6)
        move.l  d7,a6
        rts

; rpens(d0 = step): "GQ P <step> <J> <K> <L>", top border middles at R (25,10), (75,10), (125,10).
rpens:
        move.l  d0,-(sp)
        lea     m_qp(pc),a0
        bsr     puts
        move.l  (sp)+,d0
        bsr     putc
        moveq   #25,d2
.rp_lp: move.l  RQ_LAYER(a4),a1
        move.l  12(a1),a1
        move.l  d2,d0
        moveq   #10,d1
        move.l  d5,a6
        jsr     _ReadPixel(a6)
        bsr     shex
        add.w   #50,d2
        cmp.w   #25+3*50,d2
        blo.s   .rp_lp
        move.l  d7,a6
        bra     nl

; tclear: pen 0 over the right end of the title bar (x 340..399, lines 0..9).
tclear:
        move.l  d5,a6
        move.l  a5,a1
        moveq   #0,d0
        jsr     _SetAPen(a6)
        move.l  a5,a1
        move.l  #340,d0
        moveq   #0,d1
        move.l  #399,d2
        moveq   #9,d3
        jsr     _RectFill(a6)
        move.l  d7,a6
        rts

; dpix(d0 = step): "GS P <step> <front> <back>": pixels not pen 0 on line 4, x 371..396 (front) and 347..370 (back).
dpix:
        move.l  d0,-(sp)
        lea     m_sp(pc),a0
        bsr     puts
        move.l  (sp)+,d0
        bsr     putc
        move.w  #371,d2
        move.w  #396,d4
        bsr.s   .count
        move.w  #347,d2
        move.w  #370,d4
        bsr.s   .count
        move.l  d7,a6
        bra     nl
.count: moveq   #0,d3
.c_lp:  move.l  a5,a1
        moveq   #0,d0
        move.w  d2,d0
        moveq   #4,d1
        move.l  d5,a6
        jsr     _ReadPixel(a6)
        tst.l   d0
        beq.s   .c_z
        addq.w  #1,d3
.c_z:   addq.w  #1,d2
        cmp.w   d4,d2
        bls.s   .c_lp
        move.l  d3,d0
        bra     shex

slong:  move.l  d0,-(sp)
        swap    d0
        bsr.s   sword
        move.l  (sp)+,d0
        move.l  d0,-(sp)
        lsr.w   #8,d0
        bsr.s   hexb
        move.l  (sp)+,d0
        bra.s   hexb
sword:  move.l  d0,-(sp)
        lsr.w   #8,d0
        bsr.s   shex
        move.l  (sp)+,d0
        bra.s   hexb
shex:   move.l  d0,-(sp)
        moveq   #' ',d0
        bsr.s   putc
        move.l  (sp)+,d0
hexb:   move.l  d0,-(sp)
        lsr.b   #4,d0
        bsr.s   .dig
        move.l  (sp)+,d0
.dig:   and.w   #$F,d0
        move.b  digits(pc,d0.w),d0
        bra.s   putc
digits: dc.b    "0123456789ABCDEF"

nl:     moveq   #10,d0
        bra.s   putc
puts:   move.b  (a0)+,d0
        beq.s   .ret
        bsr.s   putc
        bra.s   puts
.ret:   rts

putc:   movem.l d0/d2,-(sp)
        move.w  #$4000,d2
.wt:    btst    #13-8,SERDATR
        bne.s   .tx
        dbra    d2,.wt
.tx:    and.w   #$FF,d0
        or.w    #$100,d0
        move.w  d0,SERDAT
        movem.l (sp)+,d0/d2
        rts

neww:   dc.w    20,20,400,100
        dc.b    0,1
        dc.l    0                       ; IDCMP
        dc.l    $100F                   ; ACTIVATE, WINDOWSIZING, WINDOWDRAG, WINDOWDEPTH, WINDOWCLOSE
        dc.l    0,0,0,0,0               ; Title set at run time
        dc.w    100,50,640,200
        dc.w    1                       ; WBENCHSCREEN
intname: dc.b   "intuition.library",0
gfxname: dc.b   "graphics.library",0
title:   dc.b   "reqg",0
m_gq:    dc.b   "GQ ",0
m_gs:    dc.b   "GS ",0
m_bar:   dc.b   " |",0
m_sl:    dc.b   " /",0
m_qp:    dc.b   "GQ P ",0
m_sp:    dc.b   "GS P ",0
m_end:   dc.b   "GQ END",10,0
        even

bord:   dc.w    0,0
        dc.b    1,0,0,5
        dc.l    0,0                     ; XY set at run time
bxy:    dc.w    0,0, 29,0, 29,9, 0,9, 0,0

; Requester (112 bytes): LeftEdge 10, TopEdge 15, 200 x 40, ReqGadget set at run time, BackFill 0.
req:    dc.l    0
        dc.w    10,15,200,40,0,0
        dcb.b   112-16,0

; Gadgets J, K, L: REQGADGET | BOOLGADGET; Z: a window gadget in no list.
gJ:     dc.l    0
        dc.w    10,10,30,10, 0, 1, $1001
        dc.l    0,0,0,0,0
        dc.w    'J'
        dc.l    0
gK:     dc.l    0
        dc.w    60,10,30,10, 0, 1, $1001
        dc.l    0,0,0,0,0
        dc.w    'K'
        dc.l    0
gL:     dc.l    0
        dc.w    110,10,30,10, 0, 1, $1001
        dc.l    0,0,0,0,0
        dc.w    'L'
        dc.l    0
gZ:     dc.l    0
        dc.w    170,70,30,10, 0, 1, 1
        dc.l    0,0,0,0,0
        dc.w    'Z'
        dc.l    0
