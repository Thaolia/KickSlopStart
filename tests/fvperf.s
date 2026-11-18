; tests/fvperf.s - HUNK test executable (TEST ASSET, NOT ROM code): timing of the graphics.library calls a vector
; animation player (Fantavision) makes on every frame, on a 320x200 LORES 5-plane CUSTOMSCREEN with one BORDERLESS
; 320x200 window (a layer with a single ClipRect). Printed on the serial port (SERDAT, polled), so it runs on a
; production ROM, whose console is not mirrored there. Assemble with -kick1hunks.
;   L: 20 polygon outlines of 20 Draws each (400 lines of 17-23 pixels), pens 1..31
;   A: 50 filled 20-vertex polygons (AreaMove, 19 AreaDraw, AreaEnd; 141 x 121 bounds), pens 1..31
;   B: 20 full-window BltBitMapRastPort copies from an off-screen 5-plane BitMap, minterm $C0, rp_Mask $07
;   R: 50 RectFills of 64 x 48, pens 1..31
;   Q: 5000 VBeamPos calls
;   M: 20 polygon outlines moved by (4, 2) pixels each, pens 1..20, every other one with LinePtrn $F0F0 (SetDrPt)
; After L, A and M, "FV S p0 p1 p2 p3 p4": a fingerprint (rotate-add of the longs) of each plane of the screen, to
; check that two ROMs draw the same pixels.
; Each line: "FV name F L" = elapsed VERTB frames and video line difference (duration ~= F x 313 + L lines of 64 us).
; Clean-room: public structures and calls (NewScreen, NewWindow, RastPort, AreaInfo, TmpRas, BitMap), authored code.

                section code,code
_start:
                movem.l d2-d7/a2-a6,-(sp)
                move.l  4.w,a6
                lea     gfxname(pc),a1
                moveq   #0,d0
                jsr     -552(a6)             ; OpenLibrary
                lea     gfxbase(pc),a0
                move.l  d0,(a0)
                beq     .ret
                lea     intname(pc),a1
                moveq   #0,d0
                jsr     -552(a6)
                lea     intbase(pc),a0
                move.l  d0,(a0)
                beq     .ret
                lea     vbint(pc),a1
                move.b  #2,8(a1)             ; NT_INTERRUPT
                move.b  #-100,9(a1)
                lea     vbname(pc),a0
                move.l  a0,10(a1)
                lea     vbcnt(pc),a0
                move.l  a0,14(a1)
                lea     vbcode(pc),a0
                move.l  a0,18(a1)
                moveq   #5,d0
                jsr     -168(a6)             ; AddIntServer(INTB_VERTB)

                move.l  intbase(pc),a6
                lea     ns(pc),a0
                jsr     -198(a6)             ; OpenScreen
                lea     scr(pc),a0
                move.l  d0,(a0)
                beq     .rem
                lea     nw(pc),a0
                move.l  d0,30(a0)            ; nw_Screen
                jsr     -204(a6)             ; OpenWindow
                lea     win(pc),a0
                move.l  d0,(a0)
                beq     .cs
                move.l  d0,a0
                move.l  50(a0),a2            ; a2 = wd_RPort

                ; TmpRas (one 320 x 200 plane) and AreaInfo (21 vectors)
                move.l  gfxbase(pc),a6
                move.l  #320,d0
                move.l  #200,d1
                jsr     -492(a6)             ; AllocRaster
                lea     tmpbuf(pc),a0
                move.l  d0,(a0)
                beq     .cw
                lea     tmpras(pc),a0
                move.l  d0,a1
                move.l  #8000,d0
                jsr     -468(a6)             ; InitTmpRas
                lea     tmpras(pc),a0
                move.l  a0,12(a2)            ; rp_TmpRas
                lea     ainfo(pc),a0
                lea     abuf(pc),a1
                moveq   #21,d0               ; 20 vertices and the closing one AreaEnd adds
                jsr     -282(a6)             ; InitArea
                lea     ainfo(pc),a0
                move.l  a0,16(a2)            ; rp_AreaInfo

                ; off-screen source BitMap, 5 planes
                lea     srcbm(pc),a0
                moveq   #5,d0
                move.l  #320,d1
                move.l  #200,d2
                jsr     -390(a6)             ; InitBitMap
                lea     srcbm+8(pc),a3       ; bm_Planes
                moveq   #4,d7
.al:
                move.l  #320,d0
                move.l  #200,d1
                jsr     -492(a6)             ; AllocRaster
                move.l  d0,(a3)+
                beq     .fp
                dbra    d7,.al

                lea     t_start(pc),a0
                bsr     puts
                bsr     nl
                bsr     lines
                bsr     sums
                bsr     areas
                bsr     sums
                bsr     copies
                bsr     rects
                bsr     beams
                move.l  a2,a1
                moveq   #0,d0
                jsr     -234(a6)             ; SetRast 0
                bsr     moved
                bsr     sums
                lea     t_end(pc),a0
                bsr     puts
                bsr     nl

.fp:
                move.l  gfxbase(pc),a6
                lea     srcbm+8(pc),a3
                moveq   #4,d7
.fl:
                move.l  (a3)+,d0
                beq.s   .fn
                move.l  d0,a0
                move.l  #320,d0
                move.l  #200,d1
                jsr     -498(a6)             ; FreeRaster
.fn:
                dbra    d7,.fl
                clr.l   12(a2)
                clr.l   16(a2)
                move.l  tmpbuf(pc),a0
                move.l  #320,d0
                move.l  #200,d1
                jsr     -498(a6)
.cw:
                move.l  intbase(pc),a6
                move.l  win(pc),a0
                jsr     -72(a6)              ; CloseWindow
.cs:
                move.l  intbase(pc),a6
                move.l  scr(pc),a0
                jsr     -66(a6)              ; CloseScreen
.rem:
                move.l  4.w,a6
                lea     vbint(pc),a1
                moveq   #5,d0
                jsr     -174(a6)             ; RemIntServer
.ret:
                movem.l (sp)+,d2-d7/a2-a6
                moveq   #0,d0
                rts

vbcode:                                      ; VERTB server: a1 = &vbcnt
                addq.l  #1,(a1)
                moveq   #0,d0
                rts

; pen(d7 = counter): SetAPen 1 + d7 mod 31
pen:
                move.l  a2,a1
                move.w  d7,d0
                ext.l   d0
                divu    #31,d0
                swap    d0
                addq.w  #1,d0
                jmp     -342(a6)             ; SetAPen

lines:
                bsr     start
                moveq   #19,d7
.poly:
                bsr     pen
                lea     pts(pc),a3
                move.l  a2,a1
                move.w  (a3),d0
                move.w  2(a3),d1
                jsr     -240(a6)             ; Move
                moveq   #18,d6
.e:
                addq.l  #4,a3
                move.l  a2,a1
                move.w  (a3),d0
                move.w  2(a3),d1
                jsr     -246(a6)             ; Draw
                dbra    d6,.e
                move.l  a2,a1
                move.w  pts(pc),d0
                move.w  pts+2(pc),d1
                jsr     -246(a6)
                dbra    d7,.poly
                lea     s_l(pc),a0
                bra     stopt

moved:
                bsr     start
                moveq   #19,d7
.poly:
                bsr     pen
                move.w  #$FFFF,d0            ; SetDrPt: LinePtrn, FRST_DOT, linpatcnt 15
                btst    #0,d7
                beq.s   .solid
                move.w  #$F0F0,d0
.solid:
                move.w  d0,34(a2)
                bset    #0,33(a2)
                move.b  #15,30(a2)
                move.w  d7,d4
                lsl.w   #2,d4                ; d4/d5 = offset
                move.w  d7,d5
                add.w   d5,d5
                lea     pts(pc),a3
                move.l  a2,a1
                move.w  (a3),d0
                add.w   d4,d0
                move.w  2(a3),d1
                add.w   d5,d1
                jsr     -240(a6)             ; Move
                moveq   #18,d6
.e:
                addq.l  #4,a3
                move.l  a2,a1
                move.w  (a3),d0
                add.w   d4,d0
                move.w  2(a3),d1
                add.w   d5,d1
                jsr     -246(a6)             ; Draw
                dbra    d6,.e
                move.l  a2,a1
                move.w  pts(pc),d0
                add.w   d4,d0
                move.w  pts+2(pc),d1
                add.w   d5,d1
                jsr     -246(a6)
                dbra    d7,.poly
                move.w  #$FFFF,34(a2)
                lea     s_m(pc),a0
                bra     stopt

areas:
                bsr     start
                moveq   #49,d7
.poly:
                bsr     pen
                lea     pts(pc),a3
                move.l  a2,a1
                move.w  (a3),d0
                move.w  2(a3),d1
                jsr     -252(a6)             ; AreaMove
                moveq   #18,d6
.e:
                addq.l  #4,a3
                move.l  a2,a1
                move.w  (a3),d0
                move.w  2(a3),d1
                jsr     -258(a6)             ; AreaDraw
                dbra    d6,.e
                move.l  a2,a1
                jsr     -264(a6)             ; AreaEnd
                dbra    d7,.poly
                lea     s_a(pc),a0
                bra     stopt

copies:
                move.b  #$07,24(a2)          ; rp_Mask: three planes, as the player's background restores
                bsr     start
                moveq   #19,d7
.c:
                lea     srcbm(pc),a0
                moveq   #0,d0
                moveq   #0,d1
                move.l  a2,a1
                moveq   #0,d2
                moveq   #0,d3
                move.l  #320,d4
                move.l  #200,d5
                move.l  #$C0,d6
                jsr     -606(a6)             ; BltBitMapRastPort
                dbra    d7,.c
                jsr     -228(a6)             ; WaitBlit: the last copy is part of the measurement
                lea     s_b(pc),a0
                bsr     stopt
                move.b  #$FF,24(a2)
                rts

rects:
                bsr     start
                moveq   #49,d7
.r:
                bsr     pen
                move.l  a2,a1
                moveq   #0,d0
                move.w  d7,d0
                and.w   #3,d0
                mulu    #64,d0
                add.w   #16,d0
                moveq   #40,d1
                move.l  d0,d2
                add.w   #63,d2
                moveq   #87,d3
                jsr     -306(a6)             ; RectFill
                dbra    d7,.r
                jsr     -228(a6)
                lea     s_r(pc),a0
                bra     stopt

beams:
                bsr     start
                move.w  #4999,d7
.q:
                jsr     -384(a6)             ; VBeamPos
                dbra    d7,.q
                lea     s_q(pc),a0
                bra     stopt

; sums: "FV S" and the fingerprint of each plane of the window's BitMap, after WaitBlit
sums:
                jsr     -228(a6)             ; WaitBlit
                lea     s_s(pc),a0
                bsr     puts
                move.l  4(a2),a3             ; rp_BitMap
                moveq   #0,d6
                move.b  5(a3),d6             ; bm_Depth
                subq.w  #1,d6
                lea     8(a3),a5             ; bm_Planes
.pl:
                move.l  (a5)+,a0
                move.w  (a3),d5              ; bm_BytesPerRow
                mulu    2(a3),d5             ; x bm_Rows
                lsr.l   #2,d5
                subq.l  #1,d5
                moveq   #0,d0
.lg:
                rol.l   #1,d0
                add.l   (a0)+,d0
                subq.l  #1,d5
                bpl.s   .lg
                bsr     phex8
                dbra    d6,.pl
                bra     nl

; start: records the current instant; stopt(a0 = label): prints "FV label F L"
start:
                bsr.s   now
                movem.l d0-d1,t0
                rts
stopt:
                move.l  a0,-(sp)
                lea     s_fv(pc),a0
                bsr     puts
                move.l  (sp)+,a0
                bsr     puts
                bsr.s   now
                sub.l   t0(pc),d0
                sub.l   t0+4(pc),d1
                bsr     phex8
                move.l  d1,d0
                bsr     phex8
                bra     nl
; now: d0 = frames, d1 = vertical line (0..312), re-read until consistent
now:
                move.l  vbcnt(pc),d0
                move.l  $dff004,d1
                lsr.l   #8,d1
                and.l   #$1ff,d1
                cmp.l   vbcnt(pc),d0
                bne.s   now
                rts

puts:
                move.l  d1,-(sp)
.p:             move.b  (a0)+,d1
                beq.s   .pr
                bsr.s   putc
                bra.s   .p
.pr:            move.l  (sp)+,d1
                rts
nl:             move.l  d1,-(sp)
                moveq   #10,d1
                bsr.s   putc
                move.l  (sp)+,d1
                rts
phex8:
                movem.l d0-d2,-(sp)
                moveq   #' ',d1
                bsr.s   putc
                moveq   #7,d2
.h:             rol.l   #4,d0
                move.w  d0,d1
                and.w   #15,d1
                move.b  digits(pc,d1.w),d1
                bsr.s   putc
                dbra    d2,.h
                movem.l (sp)+,d0-d2
                rts
digits:         dc.b    "0123456789ABCDEF"
putc:
                move.w  d0,-(sp)
.w:             move.w  $DFF018,d0           ; SERDATR: wait for TBE
                btst    #13,d0
                beq.s   .w
                and.w   #$FF,d1
                or.w    #$100,d1             ; stop bit
                move.w  d1,$DFF030           ; SERDAT
                move.w  (sp)+,d0
                rts

gfxname:        dc.b    "graphics.library",0
intname:        dc.b    "intuition.library",0
vbname:         dc.b    "fvperf-vb",0
t_start:        dc.b    "FV START",0
t_end:          dc.b    "FV END",0
s_fv:           dc.b    "FV ",0
s_l:            dc.b    "L",0
s_a:            dc.b    "A",0
s_b:            dc.b    "B",0
s_r:            dc.b    "R",0
s_q:            dc.b    "Q",0
s_m:            dc.b    "M",0
s_s:            dc.b    "FV S",0
                even
pts:            dc.w    230,100,227,119,217,135,201,149,182,157,160,160,138,157,119,149,103,135,93,119
                dc.w    90,100,93,81,103,65,119,51,138,43,160,40,182,43,201,51,217,65,227,81
ns:             dc.w    0,0,320,200,5        ; NewScreen: Left Top Width Height Depth
                dc.b    0,1                  ; DetailPen BlockPen
                dc.w    $0000,$000f          ; LORES, CUSTOMSCREEN
                dc.l    0,0,0,0              ; Font DefaultTitle Gadgets CustomBitMap
nw:             dc.w    0,0,320,200          ; NewWindow: Left Top Width Height
                dc.b    0,1
                dc.l    0,$0800              ; IDCMP, BORDERLESS
                dc.l    0,0,0,0,0            ; FirstGadget CheckMark Title Screen BitMap
                dc.w    0,0,0,0,$000f        ; Min/Max, CUSTOMSCREEN
                cnop    0,4
vbint:          ds.b    22
                cnop    0,4
t0:             ds.l    2
vbcnt:          dc.l    0
gfxbase:        dc.l    0
intbase:        dc.l    0
scr:            dc.l    0
win:            dc.l    0
tmpbuf:         dc.l    0
tmpras:         ds.l    2
ainfo:          ds.b    24
abuf:           ds.b    5*21+1
                cnop    0,4
srcbm:          ds.b    40
