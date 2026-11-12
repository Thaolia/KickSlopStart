; tests/bltrp_probe.s - BltBitMapRastPort phase probe for OUR ROM (implementation track, authored).
; Copies rectangles between two 2-plane 320 x 64 CHIP BitMaps (source and destination filled with different
; pseudo-random patterns before each case) with minterm $C0, for every source phase 0-15 in its word, destination
; phases from the source phase to 15 (step 3, plus 15), widths 37 and 150, height 30: large enough for the blitter
; path. Each case checks every pixel of the destination rows dy-1..dy+h and columns dx-16..dx+w+15 of both planes:
; the source pixel inside the rectangle, the destination as filled (a pristine copy) outside. Prints "BR CASES <n> BAD <pixels>" and,
; on a mismatch, "BR FIRST <sx> <dx> <w>" for the first bad case, then "BR END". Run by tests/bltrp_probe.sh.

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018

LVO_OpenLibrary     EQU -552
LVO_CloseLibrary    EQU -414
LVO_AllocMem        EQU -198
LVO_FreeMem         EQU -210
LVO_InitRastPort    EQU -198
LVO_BltBitMapRastPort EQU -606
LVO_WaitBlit        EQU -228
MEMF_CHIP           EQU 2
BPR                 EQU 40
ROWS                EQU 64
PLANE               EQU BPR*ROWS
H                   EQU 30
SY                  EQU 5
DY                  EQU 7

                section code,code
start:
        move.l  4.w,a6
        lea     gfxname(pc),a1
        moveq   #0,d0
        jsr     LVO_OpenLibrary(a6)
        move.l  d0,gfx
        beq     .out
        move.l  #6*PLANE,d0
        moveq   #MEMF_CHIP,d1
        jsr     LVO_AllocMem(a6)
        move.l  d0,mem
        beq     .close
        lea     srcbm(pc),a0
        move.l  d0,8(a0)
        add.l   #PLANE,d0
        move.l  d0,12(a0)
        add.l   #PLANE,d0
        lea     dstbm(pc),a0
        move.l  d0,8(a0)
        add.l   #PLANE,d0
        move.l  d0,12(a0)
        add.l   #PLANE,d0
        lea     origbm(pc),a0
        move.l  d0,(a0)+
        add.l   #PLANE,d0
        move.l  d0,(a0)
        move.l  gfx(pc),a6
        lea     rport(pc),a1
        jsr     LVO_InitRastPort(a6)
        lea     rport(pc),a1
        lea     dstbm(pc),a0
        move.l  a0,4(a1)             ; rp_BitMap
        moveq   #0,d7                ; d7 = source phase
.sph:
        move.w  d7,d6                ; d6 = destination phase
.dph:
        move.w  #37,cw
        bsr     onecase
        move.w  #150,cw
        bsr     onecase
        cmp.w   #15,d6
        beq.s   .dnext
        addq.w  #3,d6
        cmp.w   #15,d6
        bls.s   .dph
        moveq   #15,d6
        bra.s   .dph
.dnext:
        addq.w  #1,d7
        cmp.w   #16,d7
        blo.s   .sph
        lea     m_cases(pc),a0
        bsr     puts
        move.l  ncases(pc),d0
        bsr     phex8
        lea     m_bad(pc),a0
        bsr     puts
        move.l  nbad(pc),d0
        bsr     phex8
        bsr     nl
        tst.l   nbad
        beq.s   .ok
        lea     m_first(pc),a0
        bsr     puts
        move.w  fsx(pc),d0
        bsr     phex4
        move.w  fdx(pc),d0
        bsr     phex4
        move.w  fw(pc),d0
        bsr     phex4
        bsr     nl
.ok:
        move.l  4.w,a6
        move.l  mem(pc),a1
        move.l  #6*PLANE,d0
        jsr     LVO_FreeMem(a6)
.close:
        move.l  4.w,a6
        move.l  gfx(pc),a1
        jsr     LVO_CloseLibrary(a6)
.out:
        lea     m_end(pc),a0
        bsr     puts
        moveq   #0,d0
        rts

; onecase(d7 = source phase, d6 = destination phase, cw = width): sx = 32 + d7, dx = 16 + d6
onecase:
        movem.l d6-d7,-(sp)
        move.l  mem(pc),a0           ; fill all four planes, source and destination differently
        move.l  #$13579BDF,d0
        move.w  #PLANE-1,d1          ; 4 planes in longs = PLANE longs
.fill:
        move.l  d0,(a0)+
        mulu    #$9E37,d0
        add.l   #$7F4A7C15,d0
        swap    d0
        dbra    d1,.fill
        move.l  mem(pc),a0           ; pristine copy of the destination planes
        add.l   #2*PLANE,a0
        lea     2*PLANE(a0),a1
        move.w  #2*PLANE/4-1,d1
.keep:
        move.l  (a0)+,(a1)+
        dbra    d1,.keep
        move.w  d7,d0
        add.w   #32,d0
        move.w  d0,csx
        move.w  d6,d0
        add.w   #16,d0
        move.w  d0,cdx
        move.l  gfx(pc),a6
        lea     srcbm(pc),a0
        move.w  csx(pc),d0
        moveq   #SY,d1
        lea     rport(pc),a1
        move.w  cdx(pc),d2
        moveq   #DY,d3
        move.w  cw(pc),d4
        moveq   #H,d5
        move.l  #$C0,d6
        jsr     LVO_BltBitMapRastPort(a6)
        jsr     LVO_WaitBlit(a6)
        addq.l  #1,ncases
        moveq   #0,d5                ; d5 = bad pixels of this case
        moveq   #1,d4                ; d4 = plane
.pl:
        move.w  #DY-1,d3             ; d3 = destination row
.row:
        move.w  cdx(pc),d2
        sub.w   #16,d2               ; d2 = destination column
        move.w  cdx(pc),d1
        add.w   cw(pc),d1
        add.w   #16,d1               ; d1 = end column (exclusive)
.col:
        movem.l d1-d4,-(sp)
        move.w  d4,d0                ; actual destination bit
        lsl.w   #2,d0
        lea     dstbm(pc),a0
        move.l  8(a0,d0.w),a0
        bsr     getbit
        move.b  d0,-(sp)
        move.w  d2,d0                ; inside the rectangle?
        sub.w   cdx(pc),d0
        bmi.s   .outside
        cmp.w   cw(pc),d0
        bhs.s   .outside
        move.w  d3,d1
        sub.w   #DY,d1
        bmi.s   .outside
        cmp.w   #H,d1
        bhs.s   .outside
        add.w   csx(pc),d0           ; source pixel
        move.w  d0,d2
        move.w  d1,d3
        add.w   #SY,d3
        move.w  d4,d0
        lsl.w   #2,d0
        lea     srcbm(pc),a0
        move.l  8(a0,d0.w),a0
        bsr     getbit
        bra.s   .cmp
.outside:                            ; the destination as filled: the same generator, recomputed
        move.w  d4,d0
        lsl.w   #2,d0
        lea     origbm(pc),a0
        move.l  0(a0,d0.w),a0
        bsr     getbit
.cmp:
        cmp.b   (sp)+,d0
        movem.l (sp)+,d1-d4
        beq.s   .same
        addq.l  #1,d5
.same:
        addq.w  #1,d2
        cmp.w   d1,d2
        blo     .col
        addq.w  #1,d3
        cmp.w   #DY+H+1,d3
        bls     .row
        dbra    d4,.pl
        tst.l   d5
        beq.s   .ret
        tst.l   nbad
        bne.s   .acc
        move.w  csx(pc),fsx
        move.w  cdx(pc),fdx
        move.w  cw(pc),fw
.acc:
        add.l   d5,nbad
.ret:
        movem.l (sp)+,d6-d7
        rts

; getbit(a0 = plane, d2 = x, d3 = y) -> d0.b = 0/1. Clobbers d0/d1/a0.
getbit:
        move.w  d3,d0
        mulu    #BPR,d0
        add.l   d0,a0
        move.w  d2,d0
        lsr.w   #3,d0
        add.w   d0,a0
        move.w  d2,d1
        not.w   d1
        and.w   #7,d1
        moveq   #0,d0
        btst    d1,(a0)
        sne     d0
        and.b   #1,d0
        rts

puts:
        move.b  (a0)+,d1
        beq.s   .r
        bsr.s   putc
        bra.s   puts
.r:     rts
nl:     moveq   #10,d1
        bra.s   putc
phex8:
        move.l  d0,-(sp)
        swap    d0
        bsr.s   phex4
        move.l  (sp)+,d0
        bra.s   phex4c
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

                cnop    0,4
gfx:      dc.l  0
mem:      dc.l  0
ncases:   dc.l  0
nbad:     dc.l  0
csx:      dc.w  0
cdx:      dc.w  0
cw:       dc.w  0
fsx:      dc.w  0
fdx:      dc.w  0
fw:       dc.w  0
srcbm:    dc.w  BPR,ROWS
          dc.b  0,2
          dc.w  0
          dc.l  0,0,0,0,0,0,0,0
dstbm:    dc.w  BPR,ROWS
          dc.b  0,2
          dc.w  0
          dc.l  0,0,0,0,0,0,0,0
origbm:   dc.l  0,0              ; planes of a pristine copy of the destination fill
rport:    dcb.b 100,0
gfxname:  dc.b  "graphics.library",0
m_cases:  dc.b  "BR CASES",0
m_bad:    dc.b  " BAD",0
m_first:  dc.b  "BR FIRST",0
m_end:    dc.b  "BR END",10,0
                even
