; tests/scrollpix_probe.s - pixels of vertical ScrollRaster on a layerless 2-plane BitMap (implementation track,
; authored). For each left edge x0 (0, 1, 4, 7, 15, 16, 17, 31), right edge (x0 + 5, x0 + 40, x0 + 150, 319) and dy (1,
; 3, 9, -1, -5): both planes filled with a fixed pattern, ScrollRaster(dx 0, dy, x0, 4, x1, 50), and one checksum per
; plane printed on SERDAT: "SR <x0> <x1> <dy> <plane 0 sum> <plane 1 sum>", then "SR END". Two ROMs that scroll the
; same way print the same lines. Run by tests/scrollpix_probe.sh.
; LVOs: graphics.i of this repository (InitRastPort -198, ScrollRaster -396, InitBitMap -390); public layouts.

W               EQU 320
H               EQU 64
BPR             EQU W/8
PSIZE           EQU BPR*H

        section code,code
start:
        move.l  ($4).w,a6
        lea     gfxname(pc),a1
        moveq   #0,d0
        jsr     -552(a6)             ; OpenLibrary
        move.l  d0,a5                ; a5 = GfxBase
        tst.l   d0
        beq     .ret
        move.l  #PSIZE*2,d0
        move.l  #$10003,d1           ; MEMF_CHIP|MEMF_PUBLIC|MEMF_CLEAR
        jsr     -198(a6)             ; AllocMem
        move.l  d0,d7                ; d7 = planes
        beq     .close
        move.l  a5,a6
        lea     bm(pc),a0
        moveq   #2,d0
        move.l  #W,d1
        moveq   #H,d2
        jsr     -390(a6)             ; InitBitMap
        lea     bm+8(pc),a0
        move.l  d7,(a0)+
        move.l  d7,d0
        add.l   #PSIZE,d0
        move.l  d0,(a0)
        lea     rp(pc),a1
        jsr     -198(a6)             ; InitRastPort
        lea     rp(pc),a1
        lea     bm(pc),a0
        move.l  a0,4(a1)             ; rp_BitMap
        lea     xs(pc),a2
.x:
        move.w  (a2)+,d4             ; d4 = x0
        bmi     .done
        lea     ws(pc),a3
.w:
        move.w  (a3)+,d5             ; d5 = right edge offset (-1: 319)
        beq.s   .x
        lea     dys(pc),a4
.dy:
        move.w  (a4)+,d6             ; d6 = dy
        beq.s   .w
        bsr     fill
        move.w  d4,d2
        move.w  d5,d0
        bmi.s   .full
        add.w   d4,d0
        bra.s   .edge
.full:
        move.w  #W-1,d0
.edge:
        move.w  d0,d3                ; d3 = x1 (kept for the print)
        lea     rp(pc),a1
        movem.l d2-d7/a2-a4,-(sp)
        move.w  d3,d4                ; xmax
        moveq   #0,d0                ; dx
        move.w  d6,d1                ; dy
        ext.l   d1
        moveq   #4,d3                ; ymin
        moveq   #50,d5               ; ymax
        and.l   #$ffff,d2
        and.l   #$ffff,d4
        jsr     -396(a6)             ; ScrollRaster
        jsr     -228(a6)             ; WaitBlit
        movem.l (sp)+,d2-d7/a2-a4
        lea     m_sr(pc),a0
        bsr     puts
        moveq   #0,d0
        move.w  d4,d0
        bsr     phex8
        moveq   #0,d0
        move.w  d3,d0
        bsr     phex8
        move.w  d6,d0
        ext.l   d0
        bsr     phex8
        move.l  d7,a0
        bsr     cksum
        bsr     phex8
        move.l  d7,a0
        add.l   #PSIZE,a0
        bsr     cksum
        bsr     phex8
        bsr     nl
        bra     .dy
.done:
        lea     m_end(pc),a0
        bsr     puts
        move.l  ($4).w,a6
        move.l  d7,a1
        move.l  #PSIZE*2,d0
        jsr     -210(a6)             ; FreeMem
.close:
        move.l  ($4).w,a6
        move.l  a5,a1
        jsr     -414(a6)             ; CloseLibrary
.ret:
        moveq   #0,d0
        rts

; fill: both planes get a fixed pattern.
fill:
        movem.l d0-d1/a0,-(sp)
        move.l  d7,a0
        move.w  #PSIZE*2-1,d1
        moveq   #$5B,d0
.f:
        move.b  d0,(a0)+
        add.b   #37,d0
        eor.b   d1,d0
        dbra    d1,.f
        movem.l (sp)+,d0-d1/a0
        rts

; cksum(a0 = plane) -> d0
cksum:
        move.l  d1,-(sp)
        moveq   #0,d0
        move.w  #PSIZE/4-1,d1
.c:
        rol.l   #3,d0
        add.l   (a0)+,d0
        dbra    d1,.c
        move.l  (sp)+,d1
        rts

puts:
        move.l  d1,-(sp)
.p:     move.b  (a0)+,d1
        beq.s   .pr
        bsr.s   putc
        bra.s   .p
.pr:    move.l  (sp)+,d1
        rts
nl:     move.l  d1,-(sp)
        moveq   #10,d1
        bsr.s   putc
        move.l  (sp)+,d1
        rts
; phex2(d0.b) / phex8(d0.l): " XX" / " XXXXXXXX"
phex2:
        movem.l d0-d2,-(sp)
        ror.l   #8,d0
        moveq   #1,d2
        bra.s   phex
phex8:
        movem.l d0-d2,-(sp)
        moveq   #7,d2
phex:
        moveq   #' ',d1
        bsr.s   putc
.h:     rol.l   #4,d0
        move.w  d0,d1
        and.w   #15,d1
        move.b  digits(pc,d1.w),d1
        bsr.s   putc
        dbra    d2,.h
        movem.l (sp)+,d0-d2
        rts
digits: dc.b    "0123456789ABCDEF"
; putc(d1.b): polled serial output.
putc:
        move.w  d0,-(sp)
.w:     move.w  $DFF018,d0           ; SERDATR: wait for TBE
        btst    #13,d0
        beq.s   .w
        and.w   #$FF,d1
        or.w    #$100,d1             ; stop bit
        move.w  d1,$DFF030           ; SERDAT
        move.w  (sp)+,d0
        rts

xs:      dc.w   0,1,4,7,15,16,17,31,-1
ws:      dc.w   5,40,150,-1,0
dys:     dc.w   1,3,9,-1,-5,0
gfxname: dc.b   "graphics.library",0
m_sr:    dc.b   "SR",0
m_end:   dc.b   "SR END",10,0
        cnop    0,4
bm:      dcb.b  40,0
rp:      dcb.b  100,0
