; lace_test.s - interlaced screen test (implementation track, our own test program).
; Opens a 640 x -1 HIRES|LACE custom screen of 2 planes in front of the Workbench, fills a band whose interlaced
; lines alternate pens 1 and 2 (an interlaced display shows thin stripes; a non-interlaced one shows a single
; pen), frames the whole screen, draws the GadgetRender Images of the screen's first two gadgets (front and back
; depth) at (40,230) and (100,230), writes "LACE OPEN" on the CLI output, waits 10 minutes and closes it.
; Build: vasmm68k_mot -Fhunkexe -kick1hunks -o lace_test tests/lace_test.s

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
        move.l  a5,a6
        lea     newscr(pc),a0
        jsr     -198(a6)             ; OpenScreen
        tst.l   d0
        beq     .fail
        move.l  d0,a2                ; a2 = Screen
        lea     84(a2),a1            ; Screen.RastPort
        move.l  a1,d7
        moveq   #40,d6               ; d6 = interlaced line
.band:
        move.l  d7,a1
        moveq   #1,d0
        btst    #0,d6
        beq.s   .pen
        moveq   #2,d0
.pen:
        move.l  a4,a6
        jsr     -342(a6)             ; SetAPen
        move.l  d7,a1
        moveq   #20,d0
        move.w  d6,d1
        move.w  #619,d2
        move.w  d6,d3
        jsr     -306(a6)             ; RectFill
        addq.w  #1,d6
        cmp.w   #200,d6
        bls.s   .band
        move.l  d7,a1
        moveq   #3,d0
        jsr     -342(a6)
        move.l  d7,a1                ; frame of the whole screen
        moveq   #0,d0
        move.w  14(a2),d1            ; Screen.Height - 1
        subq.w  #1,d1
        jsr     -240(a6)             ; Move
        move.l  d7,a1
        move.w  #639,d0
        move.w  14(a2),d1
        subq.w  #1,d1
        jsr     -246(a6)             ; Draw
        move.l  d7,a1
        move.w  #639,d0
        moveq   #12,d1
        jsr     -246(a6)
        move.l  a5,a6
        move.l  326(a2),a0           ; Screen.FirstGadget
        move.l  a0,d5
        beq.s   .noimg
        move.l  18(a0),a1            ; GadgetRender
        move.l  a1,d0
        beq.s   .noimg
        move.l  d7,a0
        moveq   #40,d0
        move.w  #230,d1
        jsr     -114(a6)             ; DrawImage
        move.l  d5,a0
        move.l  (a0),a0              ; second gadget
        move.l  18(a0),a1
        move.l  a1,d0
        beq.s   .noimg
        move.l  d7,a0
        moveq   #100,d0
        move.w  #230,d1
        jsr     -114(a6)
.noimg:
        move.l  a3,a6
        jsr     -60(a6)              ; Output
        move.l  d0,d1
        lea     msg(pc),a0
        move.l  a0,d2
        moveq   #msglen,d3
        jsr     -48(a6)              ; Write
        move.l  #50*600,d1
        jsr     -198(a6)             ; Delay
        move.l  a5,a6
        move.l  a2,a0
        jsr     -66(a6)              ; CloseScreen
        moveq   #0,d0
        rts
.fail:
        moveq   #20,d0
        rts

newscr:
        dc.w    0,0,640,-1,2         ; LeftEdge, TopEdge, Width, Height, Depth
        dc.b    0,1                  ; DetailPen, BlockPen
        dc.w    $8004                ; HIRES|LACE
        dc.w    $000F                ; CUSTOMSCREEN
        dc.l    0,title,0,0          ; Font, DefaultTitle, Gadgets, CustomBitMap
intname:
        dc.b    "intuition.library",0
gfxname:
        dc.b    "graphics.library",0
dosname:
        dc.b    "dos.library",0
title:
        dc.b    "LACE TEST",0
msg:
        dc.b    "LACE OPEN",10
msglen  EQU *-msg
        even
