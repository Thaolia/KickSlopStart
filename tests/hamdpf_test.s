; hamdpf_test.s - HAM and dual-playfield screens (implementation track, our own test program).
; Opens two stacked lores screens:
;   - top (TopEdge 0, 110 lines): HAM, 6 planes. Three bands of 16 columns of 16 pixels hold "modify red", "modify
;     green" and "modify blue" pixels of rising intensity after a black pixel: in HAM they show smooth red, green and
;     blue ramps; without HAM they show unrelated palette colours.
;   - bottom (TopEdge 125, 110 lines): DUALPF. Playfield 1 = the screen's 2 planes (three hollow frames, pens 1-3);
;     playfield 2 = 2 planes of our own, attached as RasInfo->Next (three filled blocks, pens 1-3 = COLOR9-11 set
;     to red, green, blue), shown where playfield 1 is colour 0.
; Writes "HAMDPF OPEN", waits 10 s, scrolls playfield 2 by RxOffset 37 (ScrollVPort), writes "HAMDPF SCROLL",
; waits 10 minutes and closes both screens.
; Build: vasmm68k_mot -Fhunkexe -kick1hunks -o hamdpf_test tests/hamdpf_test.s

        section code,code

start:
        move.l  ($4).w,a6
        lea     intname(pc),a1
        moveq   #0,d0
        jsr     -552(a6)             ; OpenLibrary
        move.l  d0,a5                ; a5 = IntuitionBase
        lea     gfxname(pc),a1
        moveq   #0,d0
        jsr     -552(a6)
        move.l  d0,a4                ; a4 = GfxBase
        lea     dosname(pc),a1
        moveq   #0,d0
        jsr     -552(a6)
        move.l  d0,a3                ; a3 = DOSBase
        move.l  #bm_SIZE+ri_SIZE+rp_SIZE,d0
        move.l  #$10001,d1           ; MEMF_PUBLIC|MEMF_CLEAR
        jsr     -198(a6)             ; AllocMem
        tst.l   d0
        beq     fail
        lea     mem(pc),a0
        move.l  d0,(a0)
        ; ---------------- HAM screen ----------------
        move.l  a5,a6
        lea     ns_ham(pc),a0
        jsr     -198(a6)             ; OpenScreen
        tst.l   d0
        beq     fail
        lea     scr_ham(pc),a0
        move.l  d0,(a0)
        move.l  d0,a2
        moveq   #%100000,d4          ; modify red
        moveq   #20,d5               ; top of the band
        bsr     hamband
        moveq   #%110000,d4          ; modify green
        moveq   #50,d5
        bsr     hamband
        moveq   #%010000,d4          ; modify blue
        moveq   #80,d5
        bsr     hamband
        ; ---------------- dual-playfield screen ----------------
        move.l  a5,a6
        lea     ns_dpf(pc),a0
        jsr     -198(a6)
        tst.l   d0
        beq     fail
        lea     scr_dpf(pc),a0
        move.l  d0,(a0)
        move.l  d0,a2
        moveq   #1,d6                ; playfield 1: hollow frames
        moveq   #30,d7
.pf1:
        move.l  a4,a6
        lea     84(a2),a1
        move.l  d6,d0
        jsr     -342(a6)             ; SetAPen
        move.w  d7,d0
        moveq   #20,d1
        move.w  d7,d2
        add.w   #79,d2
        moveq   #99,d3
        bsr     frame
        add.w   #95,d7
        addq.w  #1,d6
        cmp.w   #3,d6
        bls.s   .pf1
        move.l  mem(pc),a0           ; playfield 2: BitMap, RasInfo, RastPort
        moveq   #2,d0
        move.w  #320,d1
        moveq   #110,d2
        move.l  a4,a6
        jsr     -390(a6)             ; InitBitMap
        moveq   #2-1,d7
        move.l  mem(pc),a0
        lea     8(a0),a0             ; bm_Planes
        move.l  a0,d6
.alloc:
        move.w  #320,d0
        moveq   #110,d1
        jsr     -492(a6)             ; AllocRaster
        tst.l   d0
        beq     fail
        move.l  d6,a0
        move.l  d0,(a0)+
        move.l  a0,d6
        dbra    d7,.alloc
        move.l  mem(pc),a0           ; clear the two planes
        move.l  8(a0),a1
        bsr     clrplane
        move.l  mem(pc),a0
        move.l  12(a0),a1
        bsr     clrplane
        move.l  mem(pc),a0
        lea     bm_SIZE(a0),a1       ; RasInfo
        move.l  a0,4(a1)             ; ri_BitMap
        move.l  80(a2),a0            ; Screen.ViewPort.RasInfo
        move.l  a1,(a0)              ; ri_Next = playfield 2
        move.l  mem(pc),a0
        lea     bm_SIZE+ri_SIZE(a0),a1
        jsr     -198(a6)             ; InitRastPort
        move.l  mem(pc),a0
        lea     bm_SIZE+ri_SIZE(a0),a1
        move.l  a0,4(a1)             ; rp_BitMap
        moveq   #1,d6
        moveq   #10,d7
.pf2:
        move.l  mem(pc),a1
        lea     bm_SIZE+ri_SIZE(a1),a1
        move.l  d6,d0
        jsr     -342(a6)             ; SetAPen
        move.l  mem(pc),a1
        lea     bm_SIZE+ri_SIZE(a1),a1
        move.w  d7,d0
        moveq   #40,d1
        move.w  d7,d2
        add.w   #59,d2
        moveq   #79,d3
        jsr     -306(a6)             ; RectFill
        add.w   #100,d7
        addq.w  #1,d6
        cmp.w   #3,d6
        bls.s   .pf2
        lea     44(a2),a0            ; COLOR9..11 = red, green, blue
        moveq   #9,d0
        moveq   #15,d1
        moveq   #0,d2
        moveq   #0,d3
        jsr     -288(a6)             ; SetRGB4
        lea     44(a2),a0
        moveq   #10,d0
        moveq   #0,d1
        moveq   #15,d2
        moveq   #0,d3
        jsr     -288(a6)
        lea     44(a2),a0
        moveq   #11,d0
        moveq   #0,d1
        moveq   #0,d2
        moveq   #15,d3
        jsr     -288(a6)
        move.l  a5,a6
        move.l  a2,a0
        jsr     -378(a6)             ; MakeScreen
        jsr     -390(a6)             ; RethinkDisplay
        lea     msg1(pc),a0
        bsr     say
        move.l  a3,a6
        move.l  #50*10,d1
        jsr     -198(a6)             ; Delay
        move.l  mem(pc),a0           ; scroll playfield 2
        move.w  #37,bm_SIZE+8(a0)    ; ri_RxOffset
        move.l  a4,a6
        lea     44(a2),a0
        jsr     -588(a6)             ; ScrollVPort
        lea     msg2(pc),a0
        bsr     say
        move.l  a3,a6
        move.l  #50*600,d1
        jsr     -198(a6)
        move.l  a5,a6
        move.l  scr_dpf(pc),a0
        move.l  80(a0),a1
        clr.l   (a1)                 ; detach playfield 2 first
        jsr     -66(a6)              ; CloseScreen
        move.l  scr_ham(pc),a0
        jsr     -66(a6)
        moveq   #0,d0
        rts
fail:
        moveq   #20,d0
        rts

; hamband(a2 = HAM screen, d4 = control bits, d5 = top line): a black column (palette colour 2) at x = 8..23, then
; 16 columns of 16 pixels, column i = d4 | i.
hamband:
        movem.l d6-d7,-(sp)
        moveq   #0,d6
        moveq   #8,d7
.hb_lp:
        move.l  a4,a6
        lea     84(a2),a1
        moveq   #2,d0                ; first column: palette colour 2 (black)
        tst.w   d6
        beq.s   .hb_pen
        move.w  d6,d0
        subq.w  #1,d0
        or.w    d4,d0
.hb_pen:
        jsr     -342(a6)             ; SetAPen
        lea     84(a2),a1
        move.w  d7,d0
        move.w  d5,d1
        move.w  d7,d2
        add.w   #15,d2
        move.w  d5,d3
        add.w   #19,d3
        jsr     -306(a6)             ; RectFill
        add.w   #16,d7
        addq.w  #1,d6
        cmp.w   #16,d6
        bls.s   .hb_lp
        movem.l (sp)+,d6-d7
        rts

; frame(rp = screen a2's RastPort, d0/d1 - d2/d3 = box, a6 = GfxBase): hollow rectangle 4 pixels thick.
frame:
        movem.l d0-d3,-(sp)
        lea     84(a2),a1
        move.w  2(sp),d0             ; top edge
        move.w  6(sp),d1
        move.w  10(sp),d2
        move.w  d1,d3
        addq.w  #3,d3
        jsr     -306(a6)
        lea     84(a2),a1
        move.w  2(sp),d0             ; bottom edge
        move.w  14(sp),d3
        move.w  d3,d1
        subq.w  #3,d1
        move.w  10(sp),d2
        jsr     -306(a6)
        lea     84(a2),a1
        move.w  2(sp),d0             ; left edge
        move.w  6(sp),d1
        move.w  d0,d2
        addq.w  #3,d2
        move.w  14(sp),d3
        jsr     -306(a6)
        lea     84(a2),a1
        move.w  10(sp),d2            ; right edge
        move.w  d2,d0
        subq.w  #3,d0
        move.w  6(sp),d1
        move.w  14(sp),d3
        jsr     -306(a6)
        movem.l (sp)+,d0-d3
        rts

; clrplane(a1 = plane of 40 x 110 bytes)
clrplane:
        move.w  #40*110/4-1,d0
.cp_lp:
        clr.l   (a1)+
        dbra    d0,.cp_lp
        rts

; say(a0 = message, a3 = DOSBase): Write(Output(), message, length up to its 0).
say:
        movem.l d2-d3/a6,-(sp)
        move.l  a0,d2
        moveq   #-1,d3
.sy_len:
        addq.l  #1,d3
        tst.b   (a0)+
        bne.s   .sy_len
        move.l  a3,a6
        move.l  d2,-(sp)
        jsr     -60(a6)              ; Output
        move.l  d0,d1
        move.l  (sp)+,d2
        jsr     -48(a6)              ; Write
        movem.l (sp)+,d2-d3/a6
        rts

bm_SIZE EQU 40
ri_SIZE EQU 12
rp_SIZE EQU 100

mem:     dc.l    0
scr_ham: dc.l    0
scr_dpf: dc.l    0
ns_ham:
        dc.w    0,0,320,110,6        ; LeftEdge, TopEdge, Width, Height, Depth
        dc.b    0,1
        dc.w    $0800                ; HAM
        dc.w    $000F                ; CUSTOMSCREEN
        dc.l    0,t_ham,0,0
ns_dpf:
        dc.w    0,125,320,110,2
        dc.b    0,1
        dc.w    $0400                ; DUALPF
        dc.w    $000F
        dc.l    0,t_dpf,0,0
intname: dc.b    "intuition.library",0
gfxname: dc.b    "graphics.library",0
dosname: dc.b    "dos.library",0
t_ham:   dc.b    "HAM",0
t_dpf:   dc.b    "DUALPF",0
msg1:    dc.b    "HAMDPF OPEN",10,0
msg2:    dc.b    "HAMDPF SCROLL",10,0
        even
