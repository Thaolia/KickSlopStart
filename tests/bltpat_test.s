; tests/bltpat_test.s - BltPattern on a 32x8, 1-plane BitMap (implementation-side test, graphics-blitter-v34 §8).
; Run from a startup-sequence (tests/garea_probe.sh <rom> <exe> <out>); prints the 8 rows as hex words on the
; serial port (SERDAT, polled).
; Expected rows (word x0-15, word x16-31):
;   0 0000 0000 | 1 3FC0 0000 | 2 3FC0 0000 | 3 0000 0000   mask NULL, rectangle (2,1)-(9,2)
;   4 0000 A500 | 5 0000 FF80                               mask $A5 00 / $FF 80 at (16,4), maxX 24
;   6 0000 F800 | 7 0000 0000                               mask $FF FF at (16,6), maxX 20 (clipped to maxX)

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018
RP_SIZE  EQU 100
RP_BMAP  EQU 4

start:  move.l  4.w,a6
        lea     gfxname(pc),a1
        moveq   #0,d0
        jsr     -552(a6)
        move.l  d0,gfxb
        beq     .out
        move.l  #32,d0                  ; plane: 4 bytes x 8 rows
        move.l  #$10002,d1              ; MEMF_CHIP|MEMF_CLEAR
        jsr     -198(a6)                ; AllocMem
        move.l  d0,plane
        beq     .out
        move.l  gfxb,a6
        lea     bmap,a0
        moveq   #1,d0
        moveq   #32,d1
        moveq   #8,d2
        jsr     -390(a6)                ; InitBitMap(bm, depth 1, 32, 8)
        lea     bmap,a0
        move.l  plane,8(a0)             ; Planes[0]
        lea     rport,a1
        jsr     -198(a6)                ; InitRastPort
        lea     rport,a1
        move.l  #bmap,RP_BMAP(a1)
        moveq   #1,d0
        jsr     -342(a6)                ; SetAPen(1)
        lea     rport,a1
        moveq   #0,d0
        jsr     -354(a6)                ; SetDrMd(JAM1)

        lea     rport,a1
        sub.l   a0,a0
        moveq   #2,d0
        moveq   #1,d1
        moveq   #9,d2
        moveq   #2,d3
        moveq   #0,d4
        jsr     -312(a6)                ; BltPattern(rp, NULL, 2, 1, 9, 2, 0)
        lea     rport,a1
        lea     pmask1(pc),a0
        moveq   #16,d0
        moveq   #4,d1
        moveq   #24,d2
        moveq   #5,d3
        moveq   #2,d4
        jsr     -312(a6)                ; BltPattern(rp, pmask1, 16, 4, 24, 5, 2)
        lea     rport,a1
        lea     pmask2(pc),a0
        moveq   #16,d0
        moveq   #6,d1
        moveq   #20,d2
        moveq   #6,d3
        moveq   #2,d4
        jsr     -312(a6)                ; BltPattern(rp, pmask2, 16, 6, 20, 6, 2)

        lea     m_head(pc),a0
        bsr     puts
        move.l  plane,a2
        moveq   #7,d7
.row:   move.w  (a2)+,d0
        bsr     hex4
        move.w  (a2)+,d0
        bsr     hex4
        lea     m_nl(pc),a0
        bsr     puts
        dbra    d7,.row
        lea     m_end(pc),a0
        bsr     puts
.out:   moveq   #0,d0
        rts

; puts(a0 = NUL-terminated string) on the serial port. Clobbers d1/a0.
puts:   move.b  (a0)+,d1
        beq.s   .e
.w:     btst    #5,SERDATR              ; TBE (bit 13)
        beq.s   .w
        and.w   #$FF,d1
        or.w    #$100,d1
        move.w  d1,SERDAT
        bra.s   puts
.e:     rts
; hex4(d0.w): 4 hex digits and a space.
hex4:   lea     hbuf,a0
        moveq   #3,d1
.dg:    rol.w   #4,d0
        move.w  d0,-(sp)
        and.w   #15,d0
        move.b  hexd(pc,d0.w),(a0)+
        move.w  (sp)+,d0
        dbra    d1,.dg
        move.b  #' ',(a0)+
        clr.b   (a0)
        lea     hbuf,a0
        bra.s   puts
hexd:   dc.b    "0123456789ABCDEF"
pmask1:  dc.b    $A5,$00,$FF,$80
pmask2:  dc.b    $FF,$FF
gfxname: dc.b   "graphics.library",0
m_head: dc.b    13,10,"BLTPAT",13,10,0
m_nl:   dc.b    13,10,0
m_end:  dc.b    "BLTPAT END",13,10,0
        even

        section bss,bss
gfxb:   ds.l    1
plane:  ds.l    1
bmap:   ds.b    40
rport:  ds.b    RP_SIZE
hbuf:   ds.b    8
