; tests/garea_probe.s - HUNK test executable (TEST ASSET, NOT ROM code).
; Black-box probe "graphics.library fills" (analysis track, docs/analysis/graphics-area-v34.md).
; Run from the startup-sequence of a floppy (tests/garea_probe.sh). Calls InitArea, AreaMove,
; AreaDraw, AreaEnd, AreaEllipse, DrawEllipse, InitTmpRas, Flood, RectFill, WritePixel, ReadPixel through their
; public LVOs on a 32 x 20 BitMap with 2 planes in CHIP, without a layer, and writes the results to the direct
; serial port (SERDAT): one header line per test, then 20 "plane0 plane1" lines in hexadecimal.
; Assembly: vasmm68k_mot -Fhunkexe -kick1hunks -nosym -o build/garea_probe tests/garea_probe.s
; Authored code; public structures (graphics/gfx.h, rastport.h).

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018
SERPER   EQU $DFF032
CHIPSZ   EQU 4096
BPR      EQU 4
ROWS     EQU 20
O_PL0    EQU 0
O_PL1    EQU 80
O_TMP    EQU 256         ; TmpRas (1024 bytes)
O_GRD    EQU 1280        ; guard after an 80-byte TmpRas placed at O_GRD-80 (test T22)

LVO_DrawEllipse EQU -180
LVO_AreaEllipse EQU -186
LVO_InitRastPort EQU -198
LVO_WaitBlit    EQU -228
LVO_Move        EQU -240
LVO_Draw        EQU -246
LVO_AreaMove    EQU -252
LVO_AreaDraw    EQU -258
LVO_AreaEnd     EQU -264
LVO_InitArea    EQU -282
LVO_RectFill    EQU -306
LVO_ReadPixel   EQU -318
LVO_WritePixel  EQU -324
LVO_Flood       EQU -330
LVO_SetAPen     EQU -342
LVO_SetBPen     EQU -348
LVO_SetDrMd     EQU -354
LVO_InitBitMap  EQU -390
LVO_InitTmpRas  EQU -468

; RastPort offsets (rastport.h)
RP_TMPRAS EQU $0C
RP_AREA  EQU $10
RP_PTRN  EQU $08
RP_AOL   EQU $1B
RP_PTSZ  EQU $1D
RP_FLAGS EQU $20

; --- call macros (rp = vars:rp); the D0 result is printed as 4 digits
AM              macro
                move.l  #\1,d0
                move.l  #\2,d1
                lea     rp-vars(a4),a1
                jsr     LVO_AreaMove(a6)
                bsr     pres
                endm
AD              macro
                move.l  #\1,d0
                move.l  #\2,d1
                lea     rp-vars(a4),a1
                jsr     LVO_AreaDraw(a6)
                bsr     pres
                endm
AEL             macro
                move.l  #\1,d0
                move.l  #\2,d1
                move.l  #\3,d2
                move.l  #\4,d3
                lea     rp-vars(a4),a1
                jsr     LVO_AreaEllipse(a6)
                bsr     pres
                endm
DEL             macro
                move.l  #\1,d0
                move.l  #\2,d1
                move.l  #\3,d2
                move.l  #\4,d3
                lea     rp-vars(a4),a1
                jsr     LVO_DrawEllipse(a6)
                endm
AE              macro
                lea     rp-vars(a4),a1
                jsr     LVO_AreaEnd(a6)
                bsr     pres
                endm
PEN             macro
                move.l  #\1,d0
                lea     rp-vars(a4),a1
                jsr     LVO_SetAPen(a6)
                endm
BPEN            macro
                move.l  #\1,d0
                lea     rp-vars(a4),a1
                jsr     LVO_SetBPen(a6)
                endm
MODE            macro
                move.l  #\1,d0
                lea     rp-vars(a4),a1
                jsr     LVO_SetDrMd(a6)
                endm
MV              macro
                move.l  #\1,d0
                move.l  #\2,d1
                lea     rp-vars(a4),a1
                jsr     LVO_Move(a6)
                endm
LDRAW           macro
                move.l  #\1,d0
                move.l  #\2,d1
                lea     rp-vars(a4),a1
                jsr     LVO_Draw(a6)
                endm
FL              macro
                move.l  #\1,d2
                move.l  #\2,d0
                move.l  #\3,d1
                lea     rp-vars(a4),a1
                jsr     LVO_Flood(a6)
                bsr     pres
                endm
WP              macro
                move.l  #\1,d0
                move.l  #\2,d1
                lea     rp-vars(a4),a1
                jsr     LVO_WritePixel(a6)
                bsr     pres
                endm
RPX             macro
                move.l  #\1,d0
                move.l  #\2,d1
                lea     rp-vars(a4),a1
                jsr     LVO_ReadPixel(a6)
                bsr     pres
                endm
RF              macro
                move.l  #\1,d0
                move.l  #\2,d1
                move.l  #\3,d2
                move.l  #\4,d3
                lea     rp-vars(a4),a1
                jsr     LVO_RectFill(a6)
                endm
BEG             macro
                lea     \1(pc),a0
                bsr     begin
                endm

                section code,code
_start:
                movem.l d2-d7/a2-a6,-(sp)
                lea     vars(pc),a4
                move.w  #372,SERPER
                move.l  4.w,a6
                lea     gfxname(pc),a1
                moveq   #0,d0
                jsr     -552(a6)
                move.l  d0,gfxb-vars(a4)
                beq     .out
                move.l  #CHIPSZ,d0
                move.l  #$10003,d1
                jsr     -198(a6)
                move.l  d0,chip-vars(a4)
                beq     .out
                move.l  d0,a5
                lea     m_start(pc),a0
                bsr     puts
                move.l  gfxb-vars(a4),a6
                ; BitMap 32 x 20, 2 planes
                lea     bm-vars(a4),a0
                moveq   #2,d0
                moveq   #32,d1
                moveq   #ROWS,d2
                jsr     LVO_InitBitMap(a6)
                lea     O_PL0(a5),a0
                move.l  a0,bm+8-vars(a4)
                lea     O_PL1(a5),a0
                move.l  a0,bm+12-vars(a4)
                ; T0: InitArea / InitTmpRas
                lea     m_t0(pc),a0
                bsr     puts
                lea     ai-vars(a4),a0
                lea     vbuf-vars(a4),a1
                moveq   #40,d0
                jsr     LVO_InitArea(a6)
                lea     ai-vars(a4),a0
                bsr     dumpai
                lea     tr-vars(a4),a0
                lea     O_TMP(a5),a1
                move.l  #1024,d0
                jsr     LVO_InitTmpRas(a6)
                lea     tr-vars(a4),a0
                cmp.l   a0,d0
                seq     d0
                bsr     phex2
                bsr     sp1
                move.l  tr-vars(a4),d0
                sub.l   a5,d0
                bsr     phex8
                bsr     sp1
                move.l  tr+4-vars(a4),d0
                bsr     phex8
                bsr     nl

; T1: square, introspection of the AreaInfo
                BEG     m_t1
                AM      2,2
                AD      10,2
                AD      10,10
                AD      2,10
                lea     ai-vars(a4),a0
                bsr     dumpai
                AE
                lea     ai-vars(a4),a0
                bsr     dumpai
                bsr     dumpvt
                bsr     dump

; T2: square traced in the other direction, explicit closing
                BEG     m_t2
                AM      2,2
                AD      2,10
                AD      10,10
                AD      10,2
                AD      2,2
                AE
                bsr     dump
; T3: triangle
                BEG     m_t3
                AM      16,1
                AD      28,14
                AD      4,14
                AE
                bsr     dump
; T4: pentagram (even/odd rule?)
                BEG     m_t4
                AM      16,1
                AD      22,18
                AD      6,7
                AD      26,7
                AD      10,18
                AE
                bsr     dump
; T5: two overlapping squares in the same AreaEnd
                BEG     m_t5
                AM      2,2
                AD      14,2
                AD      14,14
                AD      2,14
                AM      8,8
                AD      20,8
                AD      20,18
                AD      8,18
                lea     ai-vars(a4),a0
                bsr     dumpai
                AE
                bsr     dump
; T6: concave C-shaped polygon
                BEG     m_t6
                AM      2,2
                AD      28,2
                AD      28,6
                AD      8,6
                AD      8,12
                AD      28,12
                AD      28,16
                AD      2,16
                AE
                bsr     dump
; T7: AreaEllipse 8 x 6
                BEG     m_t7
                AEL     16,10,8,6
                lea     ai-vars(a4),a0
                bsr     dumpai
                bsr     dumpfl
                AE
                bsr     dump
; T8: small AreaEllipses
                BEG     m_t8
                AEL     3,3,1,1
                AEL     9,3,2,1
                AEL     17,3,3,2
                AEL     26,4,4,3
                AEL     4,13,3,3
                AEL     13,13,4,4
                AEL     24,13,5,5
                AE
                bsr     dump
; T9: same ellipses via DrawEllipse
                BEG     m_t9
                DEL     3,3,1,1
                DEL     9,3,2,1
                DEL     17,3,3,2
                DEL     26,4,4,3
                DEL     4,13,3,3
                DEL     13,13,4,4
                DEL     24,13,5,5
                bsr     dump
; T10: DrawEllipse with zero radii and 1 x 0 / 0 x 1
                BEG     m_t10
                DEL     3,3,0,0
                DEL     9,3,1,0
                DEL     15,3,0,1
                DEL     22,3,3,0
                DEL     28,4,0,3
                DEL     8,13,6,5
                DEL     24,13,1,1
                bsr     dump
; T11: outline AOlPen = 2, APen = 1 (polygon + ellipse)
                BEG     m_t11
                move.b  #2,rp+RP_AOL-vars(a4)
                or.w    #8,rp+RP_FLAGS-vars(a4)
                AM      2,2
                AD      12,2
                AD      12,10
                AD      2,10
                AM      14,4
                AD      28,4
                AD      21,17
                AEL     6,15,4,3
                AE
                and.w   #~8,rp+RP_FLAGS-vars(a4)
                bsr     dump
; T12: outline enabled only after the AreaDraws (per-vertex flag?)
                BEG     m_t12
                AM      2,2
                AD      12,2
                AD      12,10
                AD      2,10
                or.w    #8,rp+RP_FLAGS-vars(a4)
                AE
                and.w   #~8,rp+RP_FLAGS-vars(a4)
                bsr     dump
; T13: 2-line pattern JAM1
                BEG     m_t13
                lea     pat1(pc),a0
                move.l  a0,rp+RP_PTRN-vars(a4)
                move.b  #1,rp+RP_PTSZ-vars(a4)
                AM      2,1
                AD      29,1
                AD      29,7
                AD      2,7
                AE
; T13b: same pattern in JAM2, BPen = 2
                MODE    1
                BPEN    2
                AM      2,10
                AD      29,10
                AD      29,17
                AD      2,17
                AE
                MODE    0
                BPEN    0
                bsr     dump
; T14: multicolour pattern (AreaPtSz = -1), APen 3 JAM2 then APen 1 JAM1
                BEG     m_t14
                lea     pat2(pc),a0
                move.l  a0,rp+RP_PTRN-vars(a4)
                move.b  #-1,rp+RP_PTSZ-vars(a4)
                PEN     3
                MODE    1
                AM      1,1
                AD      30,1
                AD      30,8
                AD      1,8
                AE
                PEN     1
                MODE    0
                AM      1,11
                AD      30,11
                AD      30,18
                AD      1,18
                AE
                clr.l   rp+RP_PTRN-vars(a4)
                clr.b   rp+RP_PTSZ-vars(a4)
                bsr     dump
; T15: RectFill with outline, then in COMPLEMENT over a solid background
                BEG     m_t15
                move.b  #2,rp+RP_AOL-vars(a4)
                or.w    #8,rp+RP_FLAGS-vars(a4)
                RF      2,2,12,9
                lea     rp-vars(a4),a0
                move.w  $24(a0),d0
                bsr     phex4
                bsr     sp1
                move.w  $26(a0),d0
                bsr     phex4
                bsr     sp1
                and.w   #~8,rp+RP_FLAGS-vars(a4)
                PEN     3
                RF      16,1,29,18
                PEN     1
                MODE    2
                or.w    #8,rp+RP_FLAGS-vars(a4)
                RF      18,3,27,8
                and.w   #~8,rp+RP_FLAGS-vars(a4)
                RF      18,11,27,16
                MODE    0
                bsr     dump
; T16: AreaEnd in COMPLEMENT (two successive overlapping squares)
                BEG     m_t16
                MODE    2
                AM      2,2
                AD      14,2
                AD      14,14
                AD      2,14
                AE
                AM      8,8
                AD      20,8
                AD      20,18
                AD      8,18
                AE
                MODE    0
                bsr     dump
; T17: JAM1 with AreaPtSz = 2 and solid pattern (outline removed?)
                BEG     m_t17
                lea     pat3(pc),a0
                move.l  a0,rp+RP_PTRN-vars(a4)
                move.b  #2,rp+RP_PTSZ-vars(a4)
                AM      2,2
                AD      14,2
                AD      14,14
                AD      2,14
                AE
                AM      16,2
                AD      29,17
                AD      18,17
                AE
                clr.l   rp+RP_PTRN-vars(a4)
                clr.b   rp+RP_PTSZ-vars(a4)
                bsr     dump
; T18: Flood mode 1 (colour), diagonal boundary + island of colour 3
                BEG     m_t18
                bsr     floodscene
                PEN     2
                FL      1,20,3
                bsr     dump
; T19: Flood mode 0 (outline AOlPen = 1), same scene
                BEG     m_t19
                bsr     floodscene
                move.b  #1,rp+RP_AOL-vars(a4)
                PEN     2
                FL      0,20,3
                bsr     dump
; T20: Flood without TmpRas, modes 1 then 0
                BEG     m_t20
                bsr     floodscene
                clr.l   rp+RP_TMPRAS-vars(a4)
                move.b  #1,rp+RP_AOL-vars(a4)
                PEN     2
                FL      1,20,3
                FL      0,20,3
                lea     tr-vars(a4),a0
                move.l  a0,rp+RP_TMPRAS-vars(a4)
                bsr     dump
; T21: Flood mode 1 on a point already at the APen colour, mode 0 starting on AOlPen, and pattern
                BEG     m_t21
                bsr     floodscene
                move.b  #1,rp+RP_AOL-vars(a4)
                PEN     1
                FL      0,0,0
                FL      1,5,5
                lea     pat1(pc),a0
                move.l  a0,rp+RP_PTRN-vars(a4)
                move.b  #1,rp+RP_PTSZ-vars(a4)
                PEN     2
                FL      1,2,17
                clr.l   rp+RP_PTRN-vars(a4)
                clr.b   rp+RP_PTSZ-vars(a4)
                bsr     dump
; T22: WritePixel / ReadPixel, returned values and bounds
                BEG     m_t22
                PEN     3
                WP      0,0
                WP      31,19
                WP      32,0
                WP      0,20
                WP      8,1
                WP      17,1
                PEN     2
                WP      5,5
                MODE    2
                WP      5,5
                WP      6,5
                MODE    0
                bsr     nl
                RPX     0,0
                RPX     31,19
                RPX     5,5
                RPX     6,5
                RPX     7,5
                RPX     32,0
                RPX     0,20
                RPX     -1,0
                bsr     dump
; T23: AreaInfo overflows (MaxCount = 3)
                BEG     m_t23
                lea     ai-vars(a4),a0
                lea     vbuf-vars(a4),a1
                moveq   #3,d0
                jsr     LVO_InitArea(a6)
                AM      2,2
                AD      10,2
                AD      10,10
                AD      2,10
                lea     ai-vars(a4),a0
                bsr     dumpai
                AE
                lea     ai-vars(a4),a0
                bsr     dumpai
                bsr     nl
                AM      2,2
                AD      10,2
                AEL     5,5,2,2
                AEL     20,10,3,3
                AE
                bsr     nl
                AM      4,4
                AM      6,6
                lea     ai-vars(a4),a0
                bsr     dumpai
                AE
                bsr     nl
                AM      2,12
                AD      9,12
                AD      9,17
                AE
                lea     ai-vars(a4),a0
                lea     vbuf-vars(a4),a1
                moveq   #40,d0
                jsr     LVO_InitArea(a6)
                bsr     dump
; T24: TmpRas declared too small (Size = 4) for AreaEnd; guards after 80 bytes
                BEG     m_t24
                lea     tr2-vars(a4),a0
                lea     O_GRD-80(a5),a1
                moveq   #4,d0
                jsr     LVO_InitTmpRas(a6)
                lea     O_GRD(a5),a0
                moveq   #15,d0
.g:             move.w  #$7777,(a0)+
                dbra    d0,.g
                lea     tr2-vars(a4),a0
                move.l  a0,rp+RP_TMPRAS-vars(a4)
                AM      0,0
                AD      31,0
                AD      31,19
                AD      0,19
                AE
                jsr     LVO_WaitBlit(a6)
                lea     O_GRD(a5),a0
                moveq   #3,d2
.gp:            move.l  (a0)+,d0
                bsr     phex8
                bsr     sp1
                dbra    d2,.gp
                lea     tr-vars(a4),a0
                move.l  a0,rp+RP_TMPRAS-vars(a4)
                bsr     dump
; T25: degenerate figures (horizontal segment, horizontal, vertical, oblique)
                BEG     m_t25
                AM      5,2
                AD      12,2
                AD      12,2
                AE
                AM      3,5
                AD      20,5
                AE
                AM      3,8
                AD      3,15
                AE
                AM      16,8
                AD      28,16
                AE
                bsr     dump

; T26: AreaEllipse alone, vertex buffer cleared (no leftovers after Count)
                BEG     m_t26
                bsr     zvbuf
                AEL     16,10,8,6
                AE
                bsr     dump
; T27: AreaEllipse alone, buffer pre-filled with (0,0) vertices with flag $03 (one entry too many read?)
                BEG     m_t27
                lea     vbuf-vars(a4),a0
                moveq   #39,d0
.v:             clr.l   (a0)+
                dbra    d0,.v
                moveq   #39,d0
.f:             move.b  #3,(a0)+
                dbra    d0,.f
                AEL     16,10,8,6
                AE
                bsr     dump
; T28: recorded flags (AREAOUTLINE active): horizontal, vertical, oblique, then AreaEllipse
                BEG     m_t28
                bsr     zvbuf
                or.w    #8,rp+RP_FLAGS-vars(a4)
                AM      2,2
                AD      10,2
                AD      10,10
                AD      4,12
                and.w   #~8,rp+RP_FLAGS-vars(a4)
                AD      2,8
                AEL     20,8,4,3
                AD      28,16
                lea     ai-vars(a4),a0
                bsr     dumpai
                bsr     dumpfl
                bsr     dumpvt
                AE
                bsr     dump
; T29: JAM1 + AreaPtSz = 2 (solid pattern) on the left; JAM1 + AreaPtSz = 0 on the right
                BEG     m_t29
                bsr     zvbuf
                MODE    0
                lea     pat3(pc),a0
                move.l  a0,rp+RP_PTRN-vars(a4)
                move.b  #2,rp+RP_PTSZ-vars(a4)
                AM      2,2
                AD      12,2
                AD      12,12
                AD      2,12
                AE
                clr.l   rp+RP_PTRN-vars(a4)
                clr.b   rp+RP_PTSZ-vars(a4)
                AM      16,2
                AD      26,2
                AD      26,12
                AD      16,12
                AE
                bsr     dump
; T30: JAM1 vs JAM2 with pattern over a colour 2 background
                BEG     m_t30
                PEN     2
                RF      0,0,31,19
                PEN     1
                lea     pat1(pc),a0
                move.l  a0,rp+RP_PTRN-vars(a4)
                move.b  #1,rp+RP_PTSZ-vars(a4)
                MODE    0
                AM      2,2
                AD      13,2
                AD      13,12
                AD      2,12
                AE
                MODE    1
                AM      17,2
                AD      29,2
                AD      29,12
                AD      17,12
                AE
                MODE    2
                AM      2,15
                AD      29,15
                AD      29,18
                AD      2,18
                AE
                bsr     dump
; T31: AreaEnd on an empty AreaInfo (returned value); AreaEllipse with zero radii; AreaEllipse then AreaDraw
                BEG     m_t31
                bsr     zvbuf
                AE
                bsr     nl
                AEL     3,3,0,0
                AEL     10,3,3,0
                AEL     20,3,0,2
                AE
                AEL     8,13,4,4
                AD      20,8
                AD      28,16
                lea     ai-vars(a4),a0
                bsr     dumpai
                bsr     dumpfl
                AE
                bsr     dump
; T32: Flood with a huge TmpRas.Size (chip AllocMem impossible)
                BEG     m_t32
                bsr     floodscene
                lea     tr2-vars(a4),a0
                lea     O_TMP(a5),a1
                move.l  #$00F00000,d0
                jsr     LVO_InitTmpRas(a6)
                lea     tr2-vars(a4),a0
                move.l  a0,rp+RP_TMPRAS-vars(a4)
                PEN     2
                FL      1,20,3
                FL      0,20,3
                lea     tr-vars(a4),a0
                move.l  a0,rp+RP_TMPRAS-vars(a4)
                bsr     dump
; T33: Flood mode 1 on a staircase area (connectivity) and a closed diamond-shaped area
                BEG     m_t33
                PEN     1
                MV      16,0
                LDRAW   31,15
                LDRAW   16,19
                MV      16,0
                LDRAW   1,15
                LDRAW   16,19
                PEN     3
                FL      1,16,8
                bsr     dump

                lea     m_end(pc),a0
                bsr     puts
                move.l  a5,a1
                move.l  #CHIPSZ,d0
                move.l  4.w,a6
                jsr     -210(a6)
                move.l  gfxb-vars(a4),a1
                jsr     -414(a6)
.out:           movem.l (sp)+,d2-d7/a2-a6
                moveq   #0,d0
                rts

; --- begin: prints the header (a0), clears the planes, resets the RastPort (pen 1, JAM1)
begin:          bsr     puts
                jsr     LVO_WaitBlit(a6)
                lea     O_PL0(a5),a0
                moveq   #39,d0
.c:             clr.l   (a0)+
                dbra    d0,.c
                lea     rp-vars(a4),a1
                jsr     LVO_InitRastPort(a6)
                lea     rp-vars(a4),a1
                lea     bm-vars(a4),a0
                move.l  a0,4(a1)
                lea     ai-vars(a4),a0
                move.l  a0,RP_AREA(a1)
                lea     tr-vars(a4),a0
                move.l  a0,RP_TMPRAS(a1)
                PEN     1
                rts

; --- floodscene: diagonal (0,0)-(19,19) colour 1, column 24 frame colour 1, 2x2 island colour 3 at (14,3)
floodscene:     PEN     1
                MV      0,0
                LDRAW   19,19
                MV      24,0
                LDRAW   24,19
                PEN     3
                WP      14,3
                WP      15,3
                WP      14,4
                WP      15,4
                bsr     nl
                rts

; --- zvbuf: clears the vertex and flag buffer
zvbuf:          lea     vbuf-vars(a4),a0
                moveq   #49,d0
.z:             clr.l   (a0)+
                dbra    d0,.z
                rts
; --- dumpai: prints the AreaInfo (a0): pointers relative to vbuf, Count, MaxCount, FirstX, FirstY
dumpai:         move.l  a0,a2
                lea     vbuf-vars(a4),a3
                moveq   #3,d2
.l:             move.l  (a2)+,d0
                sub.l   a3,d0
                bsr     phex4
                bsr     sp1
                dbra    d2,.l
                moveq   #3,d2
.w:             move.w  (a2)+,d0
                bsr     phex4
                bsr     sp1
                dbra    d2,.w
                bra     nl
; --- dumpvt: first 6 vertices (x,y) of the table
dumpvt:         lea     vbuf-vars(a4),a2
                moveq   #11,d2
.l:             move.w  (a2)+,d0
                bsr     phex4
                bsr     sp1
                dbra    d2,.l
                bra     nl
; --- dumpfl: first 6 flags
dumpfl:         move.l  ai+8-vars(a4),a2
                moveq   #5,d2
.l:             move.b  (a2)+,d0
                bsr     phex2
                bsr     sp1
                dbra    d2,.l
                bra     nl
; --- dump: 20 "plane0 plane1" lines
dump:           jsr     LVO_WaitBlit(a6)
                bsr     nl
                lea     O_PL0(a5),a2
                moveq   #ROWS-1,d2
.r:             move.l  (a2),d0
                bsr     phex8
                bsr     sp1
                move.l  80(a2),d0
                bsr     phex8
                bsr     nl
                addq.l  #4,a2
                dbra    d2,.r
                rts
; --- pres: prints D0 (word) followed by a space, preserves D0
pres:           move.l  d0,-(sp)
                bsr     phex4
                bsr     sp1
                move.l  (sp)+,d0
                rts

nl:             moveq   #10,d1
                bra     putc
sp1:            moveq   #' ',d1
                bra     putc
phex8:          swap    d0
                bsr.s   phex4
                swap    d0
phex4:          move.w  d0,-(sp)
                lsr.w   #8,d0
                bsr.s   phex2
                move.w  (sp)+,d0
phex2:          move.w  d0,-(sp)
                lsr.b   #4,d0
                bsr.s   .n
                move.w  (sp)+,d0
.n:             move.w  d0,-(sp)
                and.w   #$F,d0
                move.b  hexd(pc,d0.w),d1
                bsr.s   putc
                move.w  (sp)+,d0
                rts
hexd:           dc.b    "0123456789ABCDEF"
puts:           move.b  (a0)+,d1
                beq.s   .e
                bsr.s   putc
                bra.s   puts
.e:             rts
putc:           move.w  d0,-(sp)
.w:             move.w  SERDATR,d0
                btst    #13,d0
                beq.s   .w
                and.w   #$FF,d1
                or.w    #$100,d1
                move.w  d1,SERDAT
                move.w  (sp)+,d0
                rts

pat1:           dc.w    $F0F0,$0F0F
pat2:           dc.w    $FF00,$FF00,$F0F0,$0F0F
pat3:           dc.w    $FFFF,$FFFF,$FFFF,$FFFF

gfxname:        dc.b    "graphics.library",0
m_start:        dc.b    10,"GAP debut",10,0
m_t0:           dc.b    "T0 ",0
m_t1:           dc.b    "T1 ",0
m_t2:           dc.b    "T2 ",0
m_t3:           dc.b    "T3 ",0
m_t4:           dc.b    "T4 ",0
m_t5:           dc.b    "T5 ",0
m_t6:           dc.b    "T6 ",0
m_t7:           dc.b    "T7 ",0
m_t8:           dc.b    "T8 ",0
m_t9:           dc.b    "T9 ",0
m_t10:          dc.b    "T10 ",0
m_t11:          dc.b    "T11 ",0
m_t12:          dc.b    "T12 ",0
m_t13:          dc.b    "T13 ",0
m_t14:          dc.b    "T14 ",0
m_t15:          dc.b    "T15 ",0
m_t16:          dc.b    "T16 ",0
m_t17:          dc.b    "T17 ",0
m_t18:          dc.b    "T18 ",0
m_t19:          dc.b    "T19 ",0
m_t20:          dc.b    "T20 ",0
m_t21:          dc.b    "T21 ",0
m_t22:          dc.b    "T22 ",0
m_t23:          dc.b    "T23 ",0
m_t24:          dc.b    "T24 ",0
m_t25:          dc.b    "T25 ",0
m_t26:          dc.b    "T26 ",0
m_t27:          dc.b    "T27 ",0
m_t28:          dc.b    "T28 ",0
m_t29:          dc.b    "T29 ",0
m_t30:          dc.b    "T30 ",0
m_t31:          dc.b    "T31 ",0
m_t32:          dc.b    "T32 ",0
m_t33:          dc.b    "T33 ",0
m_end:          dc.b    "GAP fin",10,0
                even

vars:
gfxb:           dc.l    0
chip:           dc.l    0
bm:             ds.b    40
ai:             ds.b    24
tr:             ds.b    8
tr2:            ds.b    8
rp:             ds.b    100
vbuf:           ds.b    5*40
                ds.b    16
