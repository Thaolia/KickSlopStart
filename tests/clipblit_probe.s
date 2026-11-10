; tests/clipblit_probe.s - ClipBlit within one obscured RastPort (implementation track, authored).
; docs/analysis/graphics-blitter-v34.md §5.3 step 3: a copy inside one RastPort whose rectangles touch must give the
; same picture as a copy through a scratch buffer, however the layer's ClipRects are split.
; Opens a borderless SMART_REFRESH window W1 (240 x 80) on the Workbench screen, fills it with 8-pixel columns of
; pens (x >> 3) & 3, opens a small window W2 over its middle (W1 now has several visible and backed-up ClipRects),
; ClipBlits W1 onto itself 8 pixels to the right (rectangle 200 x 50 at (8, 10)), closes W2 (W1 repaired from its
; backup) and counts the pixels of the destination whose pen is not ((x - 8) >> 3) & 3. Prints "CB BAD <count>"
; then "CB END". Run by tests/clipblit_probe.sh as a CLI command from a startup-sequence.

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018

LVO_OpenLibrary  EQU -552
LVO_CloseLibrary EQU -414
LVO_OpenWindow   EQU -204
LVO_CloseWindow  EQU -72
LVO_SetAPen      EQU -342
LVO_RectFill     EQU -306
LVO_ReadPixel    EQU -318
LVO_ClipBlit     EQU -552
wd_RPort         EQU 50

                section code,code
start:
        move.l  4.w,a6
        lea     intname(pc),a1
        moveq   #0,d0
        jsr     LVO_OpenLibrary(a6)
        move.l  d0,a4                ; a4 = IntuitionBase
        lea     gfxname(pc),a1
        moveq   #0,d0
        jsr     LVO_OpenLibrary(a6)
        move.l  d0,a5                ; a5 = GfxBase
        lea     m_begin(pc),a0
        bsr     puts
        move.l  a4,a6
        lea     nw1(pc),a0
        jsr     LVO_OpenWindow(a6)
        move.l  d0,d7                ; d7 = W1
        beq     .end
        move.l  d0,a0
        move.l  wd_RPort(a0),a3      ; a3 = its RastPort
        move.l  a5,a6
        moveq   #0,d4                ; column
.fill:
        move.l  a3,a1
        move.w  d4,d0
        and.w   #3,d0
        jsr     LVO_SetAPen(a6)
        move.l  a3,a1
        move.w  d4,d0
        lsl.w   #3,d0
        moveq   #0,d1
        move.w  d0,d2
        addq.w  #7,d2
        moveq   #79,d3
        jsr     LVO_RectFill(a6)
        addq.w  #1,d4
        cmp.w   #30,d4
        blo.s   .fill
        moveq   #0,d6                ; the fill itself: pen (x >> 3) & 3 everywhere
        bsr     check
        lea     m_fill(pc),a0
        bsr     puts
        move.w  d5,d0
        bsr     phex4
        moveq   #10,d1
        bsr     putc
        move.l  a4,a6
        lea     nw2(pc),a0
        jsr     LVO_OpenWindow(a6)
        lea     w2(pc),a0
        move.l  d0,(a0)
        move.l  a5,a6
        move.l  a3,a0                ; ClipBlit(W1 rp, 8, 10, W1 rp, 16, 10, 200, 50, $C0)
        moveq   #8,d0
        moveq   #10,d1
        move.l  a3,a1
        moveq   #16,d2
        moveq   #10,d3
        move.l  #200,d4
        moveq   #50,d5
        move.l  #$C0,d6
        jsr     LVO_ClipBlit(a6)
        move.l  a4,a6
        move.l  w2(pc),d0
        tst.l   d0
        beq.s   .nw2
        move.l  d0,a0
        jsr     LVO_CloseWindow(a6)
.nw2:
        moveq   #8,d6                ; the copy: pen ((x - 8) >> 3) & 3
        bsr     check
        lea     m_bad(pc),a0
        bsr     puts
        move.w  d5,d0
        bsr     phex4
        moveq   #10,d1
        bsr     putc
        move.l  a4,a6
        move.l  d7,a0
        jsr     LVO_CloseWindow(a6)
.end:
        lea     m_end(pc),a0
        bsr     puts
        move.l  4.w,a6
        move.l  a5,a1
        jsr     LVO_CloseLibrary(a6)
        move.l  a4,a1
        jsr     LVO_CloseLibrary(a6)
        moveq   #0,d0
        rts

; check(a3 = RastPort, a5 = GfxBase, d6 = shift) -> d5 = pixels of (16..215, 10..59) whose pen is not
; ((x - d6) >> 3) & 3. Clobbers d0-d3/a0/a1/a6.
check:
        move.l  a5,a6
        moveq   #0,d5
        moveq   #10,d3               ; y
.vy:
        moveq   #16,d2               ; x
.vx:
        move.l  a3,a1
        move.w  d2,d0
        move.w  d3,d1
        jsr     LVO_ReadPixel(a6)
        move.w  d2,d1
        sub.w   d6,d1
        lsr.w   #3,d1
        and.w   #3,d1
        cmp.w   d1,d0
        beq.s   .ok
        addq.l  #1,d5
.ok:
        addq.w  #1,d2
        cmp.w   #216,d2
        blo.s   .vx
        addq.w  #1,d3
        cmp.w   #60,d3
        blo.s   .vy
        rts

puts:
        move.b  (a0)+,d1
        beq.s   .r
        bsr.s   putc
        bra.s   puts
.r:     rts
; phex4(d0.w): " XXXX"
phex4:
        movem.l d0/d2,-(sp)
        moveq   #' ',d1
        bsr.s   putc
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

; struct NewWindow: Left, Top, Width, Height, Detail, Block, IDCMP, Flags, FirstGadget, CheckMark, Title, Screen,
; BitMap, MinW, MinH, MaxW, MaxH, Type (WBENCHSCREEN = 1)
nw1:    dc.w    20,30,240,80
        dc.b    0,1
        dc.l    0,$00000800,0,0,0,0,0          ; BORDERLESS, SMART_REFRESH
        dc.w    0,0,0,0,1
nw2:    dc.w    110,50,50,30
        dc.b    0,1
        dc.l    0,$00000800,0,0,0,0,0
        dc.w    0,0,0,0,1
                cnop    0,4
w2:     dc.l    0

intname:  dc.b  "intuition.library",0
gfxname:  dc.b  "graphics.library",0
m_begin:  dc.b  "CB BEGIN",10,0
m_bad:    dc.b  "CB BAD",0
m_fill:   dc.b  "CB FILL",0
m_end:    dc.b  "CB END",10,0
                even
