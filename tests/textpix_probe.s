; tests/textpix_probe.s - pixels of Text with topaz 8 on a layerless 2-plane BitMap (implementation track, authored).
; For each draw mode (JAM1, JAM2, COMPLEMENT, JAM1|INVERSVID, JAM2|INVERSVID), pen pair (1/0, 2/1, 3/2, 0/3) and
; write mask ($FF, $01): both planes are filled with a fixed pattern, then a 23-character string is drawn at x = 0..17
; (every offset within a byte, rows 9 pixels apart), and one checksum per plane is printed on SERDAT:
;   "TP <mode> <fg> <bg> <mask> <plane 0 sum> <plane 1 sum>"   then "TP END".
; Two ROMs that draw text the same way print the same lines. Run by tests/textpix_probe.sh.
; LVOs: graphics.i of this repository (Text -60, SetFont -66, OpenFont -72, CloseFont -78, InitRastPort -198,
; Move -240, SetAPen -342, SetBPen -348, SetDrMd -354, InitBitMap -390); public RastPort/BitMap layouts.

W               EQU 320
H               EQU 48
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
        lea     tattr(pc),a0
        jsr     -72(a6)              ; OpenFont(topaz 8)
        move.l  d0,d6                ; d6 = font
        beq     .free
        move.l  d0,a0
        lea     rp(pc),a1
        jsr     -66(a6)              ; SetFont

        lea     modes(pc),a2
.mode:
        moveq   #0,d5
        move.b  (a2)+,d5             ; d5 = draw mode
        bmi     .done
        lea     pens(pc),a3
.pen:
        move.b  (a3)+,d4             ; fg
        bmi.s   .nextmode
        move.b  (a3)+,d3             ; bg
        lea     masks(pc),a4
.mask:
        move.b  (a4)+,d2
        beq.s   .pen
        bsr     fill
        lea     rp(pc),a1
        move.b  d2,24(a1)            ; rp_Mask
        moveq   #0,d0
        move.b  d4,d0
        jsr     -342(a6)             ; SetAPen
        lea     rp(pc),a1
        moveq   #0,d0
        move.b  d3,d0
        jsr     -348(a6)             ; SetBPen
        lea     rp(pc),a1
        move.l  d5,d0
        jsr     -354(a6)             ; SetDrMd
        bsr     drawall
        lea     m_tp(pc),a0
        bsr     puts
        move.l  d5,d0
        bsr     phex2
        moveq   #0,d0
        move.b  d4,d0
        bsr     phex2
        moveq   #0,d0
        move.b  d3,d0
        bsr     phex2
        moveq   #0,d0
        move.b  d2,d0
        bsr     phex2
        move.l  d7,a0
        bsr     cksum
        bsr     phex8
        move.l  d7,a0
        add.l   #PSIZE,a0
        bsr     cksum
        bsr     phex8
        bsr     nl
        bra.s   .mask
.nextmode:
        bra     .mode
.done:
        lea     m_end(pc),a0
        bsr     puts
        move.l  d6,a1
        jsr     -78(a6)              ; CloseFont
.free:
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

; fill: both planes get a pattern that depends on the byte index and the mode (bits for JAM1 to keep).
fill:
        movem.l d0-d1/a0,-(sp)
        move.l  d7,a0
        move.w  #PSIZE*2-1,d1
        moveq   #0,d0
        move.b  d5,d0
.f:
        move.b  d0,(a0)+
        add.b   #37,d0
        eor.b   d1,d0
        dbra    d1,.f
        movem.l (sp)+,d0-d1/a0
        rts

; drawall: the string at x = 0..17, baselines 7, 16, 25, 34 in turn.
drawall:
        movem.l d2-d3,-(sp)
        moveq   #0,d2                ; x
        moveq   #7,d3                ; baseline
.d:
        lea     rp(pc),a1
        move.l  d2,d0
        move.l  d3,d1
        jsr     -240(a6)             ; Move
        lea     rp(pc),a1
        lea     tstr(pc),a0
        moveq   #TEXTLEN,d0
        jsr     -60(a6)              ; Text
        add.w   #9,d3
        cmp.w   #40,d3
        bls.s   .d1
        moveq   #7,d3
.d1:
        addq.w  #1,d2
        cmp.w   #18,d2
        blo.s   .d
        movem.l (sp)+,d2-d3
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

modes:   dc.b   0,1,2,4,5,-1
pens:    dc.b   1,0,2,1,3,2,0,3,-1
masks:   dc.b   $FF,$01,0
gfxname: dc.b   "graphics.library",0
fontname: dc.b  "topaz.font",0
tstr:    dc.b   "Kickstart 1.3 WgjQ|_@#~"
TEXTLEN  EQU    *-tstr
m_tp:    dc.b   "TP",0
m_end:   dc.b   "TP END",10,0
        cnop    0,4
tattr:   dc.l   fontname
        dc.w    8
        dc.b    0,0
bm:      dcb.b  40,0
rp:      dcb.b  100,0
