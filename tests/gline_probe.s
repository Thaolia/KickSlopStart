; tests/gline_probe.s - HUNK test executable (TEST ASSET, NOT ROM code).
; Black-box probe "graphics.library Move, Draw, PolyDraw" (docs/analysis/graphics-line-v34.md §11, expected
; values §10). Run from the startup-sequence of a floppy (tests/gline_probe.sh). Calls Move, Draw, PolyDraw and
; their neighbours (SetAPen, SetBPen, SetDrMd, InitRastPort, AreaMove/AreaDraw/AreaEnd, layers.library) through
; their public LVOs and writes the results to the direct serial port (SERDAT).
; Test BitMap: 64 x 32, 2 planes (BytesPerRow 8, 256 bytes per plane) in CHIP, between two 512-byte guards.
; Header line per step: "<id> cp=<x>,<y> fl=<Flags> 1e=<byte +$1E> 1f=<byte +$1F>" (hex).
; Dumps: "<row> <plane0 8 bytes> <plane1 8 bytes>" (hex). Pixel lists: " x,y" (decimal), ":c" when colour != 1.
; Assembly: vasmm68k_mot -Fhunkexe -kick1hunks -nosym -m68000 -o build/gline_probe tests/gline_probe.s
; Authored code; public structures (graphics/rastport.h, gfx.h, clip.h, gfxbase.h).

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018
SERPER   EQU $DFF032
DMACONR  EQU $DFF002
O_G0     EQU 0           ; guard before plane 0 (512 bytes)
O_PL0    EQU 512         ; plane 0 (256 bytes)
O_PL1    EQU 768         ; plane 1 (256 bytes)
O_G1     EQU 1024        ; guard after plane 1 (512 bytes)
O_TMP    EQU 1536        ; TmpRas (2048 bytes)
O_BIG    EQU 3584        ; 16 x 1024 x 1 plane (2048 bytes)
CHIPSZ   EQU 5632
PLSZ     EQU 256

; graphics LVOs checked against AROS rom/graphics/graphics.conf (bias 30, 6 bytes per slot)
LVO_InitRastPort EQU -198
LVO_WaitBlit     EQU -228
LVO_Move         EQU -240
LVO_Draw         EQU -246
LVO_AreaMove     EQU -252
LVO_AreaDraw     EQU -258
LVO_AreaEnd      EQU -264
LVO_InitArea     EQU -282
LVO_BltClear     EQU -300
LVO_PolyDraw     EQU -336
LVO_SetAPen      EQU -342
LVO_SetBPen      EQU -348
LVO_SetDrMd      EQU -354
LVO_InitBitMap   EQU -390
LVO_InitTmpRas   EQU -468
; layers LVOs checked against AROS rom/hyperlayers/layers.conf
LVO_CreateUpfrontLayer EQU -36
LVO_DeleteLayer        EQU -90
LVO_NewLayerInfo       EQU -144
LVO_DisposeLayerInfo   EQU -150

; RastPort (rastport.h)
RP_BM    EQU $04
RP_TMPRAS EQU $0C
RP_AREA  EQU $10
RP_MASK  EQU $18
RP_FG    EQU $19
RP_BG    EQU $1A
RP_AOL   EQU $1B
RP_MODE  EQU $1C
RP_LPC   EQU $1E         ; linpatcnt
RP_PC    EQU $1F         ; byte after linpatcnt
RP_FLAGS EQU $20
RP_PTRN  EQU $22
RP_CPX   EQU $24
RP_CPY   EQU $26
RP_MINT  EQU $28
LR_RP    EQU $0C         ; Layer.rp (clip.h)
GB_BLITLOCK EQU $AA      ; GfxBase.BlitLock (gfxbase.h)

; --- call macros on the RastPort pointed to by rpa
PEN             macro
                move.l  #\1,d0
                move.l  rpa-vars(a4),a1
                jsr     LVO_SetAPen(a6)
                endm
BPEN            macro
                move.l  #\1,d0
                move.l  rpa-vars(a4),a1
                jsr     LVO_SetBPen(a6)
                endm
MODE            macro
                move.l  #\1,d0
                move.l  rpa-vars(a4),a1
                jsr     LVO_SetDrMd(a6)
                endm
MV              macro
                move.l  #\1,d0
                move.l  #\2,d1
                move.l  rpa-vars(a4),a1
                jsr     LVO_Move(a6)
                endm
LDRAW              macro
                move.l  #\1,d0
                move.l  #\2,d1
                move.l  rpa-vars(a4),a1
                jsr     LVO_Draw(a6)
                endm
; PB/PW offset,value: pokes a byte/word of the RastPort
PB              macro
                move.l  rpa-vars(a4),a0
                move.b  #\2,\1(a0)
                endm
PW              macro
                move.l  rpa-vars(a4),a0
                move.w  #\2,\1(a0)
                endm
HDR             macro
                lea     \1(pc),a0
                bsr     hdr
                endm
MSG             macro
                lea     \1(pc),a0
                bsr     puts
                endm
DUMP            macro
                moveq   #\1,d6
                moveq   #\2,d7
                bsr     dump
                endm
; MROW mode,row: rightward row (0..40) on row, leftward row (40..0) on row+1
MROW            macro
                MODE    \1
                MV      0,\2
                LDRAW      40,\2
                MV      40,\2+1
                LDRAW      0,\2+1
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
                lea     layname(pc),a1
                moveq   #0,d0
                jsr     -552(a6)
                move.l  d0,layb-vars(a4)
                beq     .closeg
                move.l  #CHIPSZ,d0
                move.l  #$10003,d1
                jsr     -198(a6)
                move.l  d0,chip-vars(a4)
                beq     .closel
                move.l  d0,a5
                MSG     m_start
                move.l  gfxb-vars(a4),a6
                lea     bm-vars(a4),a0
                moveq   #2,d0
                moveq   #64,d1
                moveq   #32,d2
                jsr     LVO_InitBitMap(a6)
                lea     O_PL0(a5),a0
                move.l  a0,bm+8-vars(a4)
                lea     O_PL1(a5),a0
                move.l  a0,bm+12-vars(a4)

                bsr     t_l0
                bsr     t_l1
                bsr     t_l2
                bsr     t_l3
                bsr     t_l4
                bsr     t_l5
                bsr     t_l6
                bsr     t_l7
                bsr     t_l8
                bsr     t_l9

                MSG     m_end
                move.l  4.w,a6
                move.l  a5,a1
                move.l  #CHIPSZ,d0
                jsr     -210(a6)
.closel:        move.l  4.w,a6
                move.l  layb-vars(a4),a1
                jsr     -414(a6)
.closeg:        move.l  4.w,a6
                move.l  gfxb-vars(a4),a1
                jsr     -414(a6)
.out:           movem.l (sp)+,d2-d7/a2-a6
                moveq   #0,d0
                rts

; --- L0: registers changed by Move, Draw, PolyDraw (markers in d0-d7/a0/a2-a5; d0/d1 low words = arguments)
t_l0:           bsr     fresh
                MSG     m_l0m
                move.l  #$11110005,mk-vars(a4)
                move.l  #$22220006,mk+4-vars(a4)
                move.w  #LVO_Move,d0
                bsr     regt
                MSG     m_l0d
                move.l  #$1111000C,mk-vars(a4)
                move.l  #$2222000E,mk+4-vars(a4)
                move.w  #LVO_Draw,d0
                bsr     regt
                MSG     m_l0p
                move.l  #$33330001,mk-vars(a4)
                lea     ptab0(pc),a0
                move.l  a0,mk+32-vars(a4)
                move.w  #LVO_PolyDraw,d0
                bsr     regt
                move.l  #$A0A0A0A0,mk+32-vars(a4)
                HDR     m_l0h
                bra     plist

; --- L1: fields written by InitRastPort, Set*Pen/SetDrMd, Move, Draw, PolyDraw
t_l1:           bsr     fresh0
                HDR     m_l1i
                bsr     pmisc
                PEN     1
                HDR     m_l1a
                bsr     pmisc
                PB      RP_PC,3
                PW      RP_FLAGS,0
                BPEN    2
                HDR     m_l1b
                bsr     pmisc
                PB      RP_PC,3
                PW      RP_FLAGS,0
                MODE    0
                HDR     m_l1m
                bsr     pmisc
                PB      RP_PC,3
                PW      RP_FLAGS,0
                MV      3,4
                HDR     m_l1v
                LDRAW      10,4
                HDR     m_l1d1
                LDRAW      20,9
                HDR     m_l1d2
                moveq   #3,d0
                lea     ptab3(pc),a0
                move.l  rpa-vars(a4),a1
                jsr     LVO_PolyDraw(a6)
                HDR     m_l1p3
                moveq   #0,d0
                lea     ptab0(pc),a0
                move.l  rpa-vars(a4),a1
                jsr     LVO_PolyDraw(a6)
                HDR     m_l1p0
                rts

; --- L2: pixel sets, each line of §10.1 in both directions
t_l2:           lea     l2tab(pc),a3
.l:             movem.w (a3)+,d2-d5
                cmp.w   #-1,d2
                beq.s   .e
                bsr.s   l2one
                exg     d2,d4
                exg     d3,d5
                bsr.s   l2one
                bra.s   .l
.e:             rts
; l2one(d2,d3 = start, d4,d5 = end): clear, Move, Draw, "L2 x0,y0>x1,y1" + fields, pixel list
l2one:          movem.l d2-d5,-(sp)
                bsr     fresh
                move.w  d2,d0
                ext.l   d0
                move.w  d3,d1
                ext.l   d1
                move.l  rpa-vars(a4),a1
                jsr     LVO_Move(a6)
                move.w  d4,d0
                ext.l   d0
                move.w  d5,d1
                ext.l   d1
                move.l  rpa-vars(a4),a1
                jsr     LVO_Draw(a6)
                MSG     m_l2
                move.w  d2,d0
                bsr     pdec
                bsr     comma
                move.w  d3,d0
                bsr     pdec
                moveq   #'>',d1
                bsr     putc
                move.w  d4,d0
                bsr     pdec
                bsr     comma
                move.w  d5,d0
                bsr     pdec
                HDR     m_none
                bsr     plist
                movem.l (sp)+,d2-d5
                rts

; --- L3: patterns
t_l3:           bsr     fresh
                PW      RP_PTRN,$FF00
                MV      0,1
                LDRAW      40,1
                HDR     m_l3a
                MV      40,3
                LDRAW      0,3
                HDR     m_l3b
                MV      0,5
                LDRAW      40,6
                HDR     m_l3c
                MV      0,8
                LDRAW      10,8
                HDR     m_l3d1
                LDRAW      10,18
                HDR     m_l3d2
                LDRAW      30,18
                HDR     m_l3d3
                MV      40,8
                LDRAW      40,30
                HDR     m_l3e
                MV      60,30
                LDRAW      45,10
                HDR     m_l3f
                MSG     m_l3dump
                DUMP    0,31
                ; six draw modes, FgPen 1, BgPen 2
                bsr     fresh
                PW      RP_PTRN,$FF00
                BPEN    2
                MROW    0,1
                MROW    1,4
                MROW    4,7
                MROW    5,10
                MROW    2,13
                MROW    6,16
                MSG     m_l3modes
                DUMP    0,18
                ; $8001: after Move (row 1), InitRastPort+SetAPen without Move (row 3), +$1F 3 / +$1E 9 (row 4),
                ; InitRastPort alone without Move (row 6, FgPen $FF)
                bsr     fresh
                PW      RP_PTRN,$8001
                MV      0,1
                LDRAW      40,1
                HDR     m_l3g
                bsr     rpinit0
                PEN     1
                PW      RP_PTRN,$8001
                PW      RP_CPX,0
                PW      RP_CPY,3
                HDR     m_l3h0
                LDRAW      40,3
                HDR     m_l3h
                bsr     rpinit
                PW      RP_PTRN,$8001
                MV      0,4
                PB      RP_PC,3
                PB      RP_LPC,9
                LDRAW      40,4
                HDR     m_l3i
                bsr     rpinit0
                PW      RP_PTRN,$8001
                PW      RP_CPX,0
                PW      RP_CPY,6
                HDR     m_l3j0
                LDRAW      40,6
                HDR     m_l3j
                MSG     m_l38001
                DUMP    0,7
                rts

; --- L4: COMPLEMENT continuation (§10.3), FgPen 1, all planes
t_l4:           bsr     fresh
                MODE    2
                MV      2,2
                LDRAW      12,2
                LDRAW      12,12
                HDR     m_l4a
                MV      20,2
                LDRAW      30,2
                LDRAW      20,2
                HDR     m_l4b
                PW      RP_PTRN,$FFDF
                MV      34,2
                LDRAW      44,2
                LDRAW      44,12
                HDR     m_l4c
                PW      RP_PTRN,$FFFF
                MV      20,6
                LDRAW      30,6
                LDRAW      30,6
                HDR     m_l4d
                MV      2,20
                LDRAW      12,20
                MV      12,20
                LDRAW      12,30
                HDR     m_l4e
                MODE    6
                MV      14,26
                LDRAW      40,26
                HDR     m_l4f
                MSG     m_l4dump
                DUMP    0,31
                rts

; --- L5: ONE_DOT (Flags bit 1 set directly), then Mask
t_l5:           bsr     fresh
                move.l  rpa-vars(a4),a0
                or.w    #2,RP_FLAGS(a0)
                MV      0,1
                LDRAW      12,4
                MV      20,1
                LDRAW      23,12
                MV      30,2
                LDRAW      40,2
                MV      50,2
                LDRAW      42,2
                MV      20,20
                LDRAW      30,20
                LDRAW      30,25
                HDR     m_l5a
                bsr     rpinit
                PEN     3
                PB      RP_MASK,1
                MV      0,28
                LDRAW      40,28
                HDR     m_l5b
                bsr     rpinit
                PB      RP_MASK,2
                MODE    2
                MV      0,30
                LDRAW      40,30
                HDR     m_l5c
                MSG     m_l5dump
                DUMP    0,31
                rts

; --- L6: out of bounds, no layer; FgPen 3 so that writes reach both planes as set bits; guard bytes reported
t_l6:           bsr     fresh
                PEN     3
                MV      -4,3
                LDRAW      4,3
                MV      4,5
                LDRAW      -4,5
                MV      -4,7
                LDRAW      -1,10
                MV      60,12
                LDRAW      70,12
                MV      10,29
                LDRAW      10,34
                MV      20,-2
                LDRAW      20,2
                HDR     m_l6
                MSG     m_l6dump
                DUMP    0,31
                MSG     m_l6g
                move.l  #O_G0,d7
.g:             cmp.l   #O_PL0,d7
                bne.s   .g1
                move.l  #O_G1,d7
.g1:            cmp.l   #O_G1+512,d7
                beq.s   .ge
                tst.b   0(a5,d7.l)
                beq.s   .gn
                bsr     sp1
                move.w  d7,d0
                sub.w   #O_PL0,d0
                bsr     pdec
                moveq   #'=',d1
                bsr     putc
                move.b  0(a5,d7.l),d0
                bsr     phex2
.gn:            addq.l  #1,d7
                bra.s   .g
.ge:            bra     nl

; --- L7: asynchrony and length limit, BitMap 16 x 1024 x 1
t_l7:           bsr     fresh
                lea     bm2-vars(a4),a0
                moveq   #1,d0
                moveq   #16,d1
                move.l  #1024,d2
                jsr     LVO_InitBitMap(a6)
                lea     O_BIG(a5),a0
                move.l  a0,bm2+8-vars(a4)
                bsr     clrbig
                move.l  rpa-vars(a4),a0
                lea     bm2-vars(a4),a1
                move.l  a1,RP_BM(a0)
                MV      3,0
                LDRAW      3,1000
                move.w  DMACONR,d4
                move.w  GB_BLITLOCK(a6),d5
                jsr     LVO_WaitBlit(a6)
                MSG     m_l7a
                move.w  d4,d0
                bsr     phex4
                MSG     m_l7b
                move.w  d5,d0
                bsr     phex4
                bsr     big
                bsr     clrbig
                MV      0,0
                LDRAW      1,1100
                MSG     m_l7c
                bsr     big
                move.l  rpa-vars(a4),a0
                lea     bm-vars(a4),a1
                move.l  a1,RP_BM(a0)
                rts
clrbig:         jsr     LVO_WaitBlit(a6)
                lea     O_BIG(a5),a1
                move.l  #2048,d0
                moveq   #1,d1
                jmp     LVO_BltClear(a6)
; big: " rows=<rows with a pixel> last=<last such row>" of the 16 x 1024 plane
big:            jsr     LVO_WaitBlit(a6)
                lea     O_BIG(a5),a2
                moveq   #0,d2
                moveq   #-1,d3
                moveq   #0,d4
.r:             tst.w   (a2)+
                beq.s   .n
                addq.w  #1,d2
                move.w  d4,d3
.n:             addq.w  #1,d4
                cmp.w   #1024,d4
                blo.s   .r
                MSG     m_rows
                move.w  d2,d0
                bsr     pdec
                MSG     m_last
                move.w  d3,d0
                bsr     pdec
                bra     nl

; --- L8: layers. Back layer (8,4)-(55,27) SMART then SIMPLE, SIMPLE layer (30,0)-(63,15) in front;
; then a single SIMPLE layer at (8,4)-(55,27) for the phase vectors.
t_l8:           MSG     m_l8smart
                moveq   #2,d5
                bsr     l8two
                MSG     m_l8simple
                moveq   #1,d5
                bsr     l8two
                MSG     m_l8one
                bsr     fresh
                bsr     newli
                beq     .r
                moveq   #8,d0
                moveq   #4,d1
                moveq   #55,d2
                moveq   #27,d3
                moveq   #1,d4
                bsr     newly
                move.l  d0,lyb-vars(a4)
                beq     .fail
                bsr     lyrp
                PW      RP_PTRN,$FF00
                MV      0,1
                LDRAW      20,1
                HDR     m_l8i1
                LDRAW      40,1
                HDR     m_l8i2
                MV      0,3
                LDRAW      47,3
                HDR     m_l8j
                MV      -8,5
                LDRAW      40,5
                HDR     m_l8k
                MV      40,7
                LDRAW      -8,7
                HDR     m_l8l
                MV      -3,9
                LDRAW      10,9
                HDR     m_l8m1
                LDRAW      30,9
                HDR     m_l8m2
                PB      RP_LPC,4
                MV      -8,11
                LDRAW      40,11
                HDR     m_l8n
                PB      RP_LPC,0
                MSG     m_l8dump
                DUMP    0,31
                move.l  lyb-vars(a4),a1
                bsr     dellay
.fail:          bra     displi
.r:             rts

; l8two(d5 = back layer flags): the two-layer sequences of §10.5
l8two:          bsr     fresh
                bsr     newli
                beq     .r
                moveq   #8,d0
                moveq   #4,d1
                moveq   #55,d2
                moveq   #27,d3
                move.l  d5,d4
                bsr     newly
                move.l  d0,lyb-vars(a4)
                beq     .fail
                moveq   #30,d0
                moveq   #0,d1
                moveq   #63,d2
                moveq   #15,d3
                moveq   #1,d4
                bsr     newly
                move.l  d0,lyf-vars(a4)
                beq     .fail1
                bsr     lyrp
                PW      RP_PTRN,$F0F0
                MV      1,1
                HDR     m_l8a0
                LDRAW      10,1
                HDR     m_l8a1
                LDRAW      10,6
                HDR     m_l8a2
                MV      2,8
                LDRAW      40,8
                HDR     m_l8b
                LDRAW      40,20
                HDR     m_l8c
                PW      RP_PTRN,$FFFF
                MV      30,21
                LDRAW      60,30
                HDR     m_l8d
                MV      30,3
                LDRAW      33,6
                HDR     m_l8e
                MODE    2
                MV      2,17
                LDRAW      12,17
                LDRAW      12,22
                HDR     m_l8g
                MV      15,10
                LDRAW      30,10
                LDRAW      30,13
                HDR     m_l8h
                MSG     m_l8before
                DUMP    0,31
                move.l  lyf-vars(a4),a1
                bsr     dellay
                MSG     m_l8after
                DUMP    0,31
                move.l  lyb-vars(a4),a1
                bsr     dellay
                bra     displi
.fail1:         move.l  lyb-vars(a4),a1
                bsr     dellay
.fail:          bra     displi
.r:             rts
; newli: NewLayerInfo -> li; Z = 1 (and a message) on failure
newli:          move.l  layb-vars(a4),a6
                jsr     LVO_NewLayerInfo(a6)
                move.l  gfxb-vars(a4),a6
                move.l  d0,li-vars(a4)
                bne.s   .r
                MSG     m_fail
                moveq   #0,d0
.r:             rts
; newly(d0-d3 = bounds, d4 = flags) -> d0 = layer on bm (message when 0), then the planes are cleared again
newly:          movem.l d2-d4,-(sp)
                move.l  layb-vars(a4),a6
                move.l  li-vars(a4),a0
                lea     bm-vars(a4),a1
                sub.l   a2,a2
                jsr     LVO_CreateUpfrontLayer(a6)
                move.l  gfxb-vars(a4),a6
                move.l  d0,-(sp)
                bne.s   .ok
                MSG     m_fail
.ok:            bsr     clrpl
                move.l  (sp)+,d0
                movem.l (sp)+,d2-d4
                rts
; lyrp: rpa := back layer's RastPort, FgPen 1, BgPen 0, JAM2
lyrp:           move.l  lyb-vars(a4),a0
                move.l  LR_RP(a0),rpa-vars(a4)
                PEN     1
                BPEN    0
                MODE    1
                rts
dellay:         move.l  layb-vars(a4),a6
                sub.l   a0,a0
                jsr     LVO_DeleteLayer(a6)
                move.l  gfxb-vars(a4),a6
                jmp     LVO_WaitBlit(a6)
displi:         move.l  layb-vars(a4),a6
                move.l  li-vars(a4),a0
                jsr     LVO_DisposeLayerInfo(a6)
                move.l  gfxb-vars(a4),a6
                lea     rp-vars(a4),a0
                move.l  a0,rpa-vars(a4)
                rts

; --- L9: AreaEnd fill vs Move/Draw outline, each polygon in both vertex orders
t_l9:           lea     polys(pc),a3
                moveq   #1,d6
.p:             tst.w   (a3)
                beq.s   .e
                moveq   #0,d5
                bsr.s   l9one
                moveq   #1,d5
                bsr.s   l9one
                move.w  (a3),d0
                lsl.w   #2,d0
                lea     2(a3,d0.w),a3
                addq.w  #1,d6
                bra.s   .p
.e:             rts
; l9one(a3 = polygon, d5 = 0 forward / 1 reverse, d6 = number)
l9one:          movem.l d6/a3,-(sp)
                bsr     fresh
                move.l  rpa-vars(a4),a1
                lea     ai-vars(a4),a0
                move.l  a0,RP_AREA(a1)
                lea     tr-vars(a4),a0
                move.l  a0,RP_TMPRAS(a1)
                lea     ai-vars(a4),a0
                lea     vbuf-vars(a4),a1
                moveq   #40,d0
                jsr     LVO_InitArea(a6)
                lea     tr-vars(a4),a0
                lea     O_TMP(a5),a1
                move.l  #2048,d0
                jsr     LVO_InitTmpRas(a6)
                moveq   #0,d2
                bsr     vtx
                move.l  rpa-vars(a4),a1
                jsr     LVO_AreaMove(a6)
                moveq   #1,d2
.a:             cmp.w   (a3),d2
                bge.s   .ae
                bsr     vtx
                move.l  rpa-vars(a4),a1
                jsr     LVO_AreaDraw(a6)
                addq.w  #1,d2
                bra.s   .a
.ae:            move.l  rpa-vars(a4),a1
                jsr     LVO_AreaEnd(a6)
                move.l  d0,d7
                bsr     l9lab
                MSG     m_fill
                move.w  d7,d0
                bsr     phex4
                bsr     nl
                DUMP    0,31
                bsr     fresh
                moveq   #0,d2
                bsr     vtx
                move.l  rpa-vars(a4),a1
                jsr     LVO_Move(a6)
                moveq   #1,d2
.d:             bsr     vtx
                move.l  rpa-vars(a4),a1
                jsr     LVO_Draw(a6)
                cmp.w   (a3),d2
                beq.s   .de
                addq.w  #1,d2
                bra.s   .d
.de:            bsr     l9lab
                MSG     m_outl
                bsr     nl
                DUMP    0,31
                movem.l (sp)+,d6/a3
                rts
; l9lab: "L9 p<d6> fwd|rev"
l9lab:          MSG     m_l9
                move.w  4+2(sp),d0          ; low word of the d6 saved by l9one, after our return address
                bsr     pdec
                lea     m_fwd(pc),a0
                tst.w   d5
                beq.s   .f
                lea     m_rev(pc),a0
.f:             bra     puts
; vtx(a3 = polygon, d2 = index (n means 0), d5 = reverse) -> d0/d1 = vertex (long)
vtx:            move.w  d2,d0
                cmp.w   (a3),d0
                bne.s   .m
                moveq   #0,d0
.m:             tst.w   d5
                beq.s   .f
                tst.w   d0
                beq.s   .f
                neg.w   d0
                add.w   (a3),d0
.f:             move.w  d0,d1
                lsl.w   #2,d1
                lea     2(a3),a0
                move.w  0(a0,d1.w),d0
                move.w  2(a0,d1.w),d1
                ext.l   d0
                ext.l   d1
                rts

; --- regt(d0.w = LVO): d0-d7/a0-a5 := mk (slot a1 = rpa), call, print " <reg>=<value>" for each changed one
regt:           movem.l d2-d7/a2-a6,-(sp)
                ext.l   d0
                add.l   a6,d0
                move.l  d0,jaddr-vars(a4)
                move.l  rpa-vars(a4),mk+36-vars(a4)
                movem.l mk(pc),d0-d7/a0-a5
                pea     .r(pc)
                move.l  jaddr(pc),-(sp)
                rts
.r:             movem.l d0-d7/a0-a5,-(sp)
                move.l  56+32(sp),a4        ; caller's a4 in the first save (d2-d7, a2, a3, a4)
                move.l  sp,a2
                lea     mk-vars(a4),a3
                moveq   #0,d7
.l:             move.l  (a2)+,d2
                cmp.l   (a3)+,d2
                beq.s   .n
                bsr     sp1
                lea     rnames(pc),a0
                move.w  d7,d0
                add.w   d0,d0
                move.b  0(a0,d0.w),d1
                bsr     putc
                move.b  1(a0,d0.w),d1
                bsr     putc
                moveq   #'=',d1
                bsr     putc
                move.l  d2,d0
                bsr     phex8
.n:             addq.w  #1,d7
                cmp.w   #14,d7
                blo.s   .l
                bsr     nl
                lea     56(sp),sp
                movem.l (sp)+,d2-d7/a2-a6
                rts

; --- fresh: planes and guards cleared, rpa = rp initialised (FgPen 1, BgPen 0) on bm
fresh:          bsr.s   clrall
rpinit:         bsr.s   rpinit0
                PEN     1
                BPEN    0
                rts
; fresh0: cleared, InitRastPort only
fresh0:         bsr.s   clrall
rpinit0:        lea     rp-vars(a4),a1
                move.l  a1,rpa-vars(a4)
                jsr     LVO_InitRastPort(a6)
                lea     rp-vars(a4),a1
                lea     bm-vars(a4),a0
                move.l  a0,RP_BM(a1)
                rts
clrall:         jsr     LVO_WaitBlit(a6)
                lea     O_G0(a5),a1
                move.l  #O_G1+512,d0
                moveq   #1,d1
                jmp     LVO_BltClear(a6)
clrpl:          jsr     LVO_WaitBlit(a6)
                lea     O_PL0(a5),a1
                move.l  #2*PLSZ,d0
                moveq   #1,d1
                jmp     LVO_BltClear(a6)

; --- hdr(a0 label): "label cp=<x>,<y> fl=<Flags> 1e=<+$1E> 1f=<+$1F>"
hdr:            move.l  a2,-(sp)
                bsr     puts
                move.l  rpa-vars(a4),a2
                MSG     m_cp
                move.w  RP_CPX(a2),d0
                bsr     phex4
                bsr     comma
                move.w  RP_CPY(a2),d0
                bsr     phex4
                MSG     m_fl
                move.w  RP_FLAGS(a2),d0
                bsr     phex4
                MSG     m_1e
                move.b  RP_LPC(a2),d0
                bsr     phex2
                MSG     m_1f
                move.b  RP_PC(a2),d0
                bsr     phex2
                move.l  (sp)+,a2
                bra     nl
; --- pmisc: "  pt=<LinePtrn> fg bg ao mask mode mt=<minterms[8]>"
pmisc:          move.l  rpa-vars(a4),a2
                MSG     m_pt
                move.w  RP_PTRN(a2),d0
                bsr     phex4
                MSG     m_pens
                lea     RP_MASK(a2),a3
                moveq   #4,d2
.p:             move.b  (a3)+,d0
                bsr     phex2
                bsr     sp1
                dbra    d2,.p
                MSG     m_mt
                lea     RP_MINT(a2),a3
                moveq   #7,d2
.m:             move.b  (a3)+,d0
                bsr     phex2
                dbra    d2,.m
                bra     nl

; --- dump(d6 first row, d7 last row): "<row> <plane0> <plane1>"
dump:           jsr     LVO_WaitBlit(a6)
.r:             move.w  d6,d0
                bsr     phex2
                bsr     sp1
                lea     O_PL0(a5),a2
                move.w  d6,d0
                lsl.w   #3,d0
                adda.w  d0,a2
                move.l  (a2),d0
                bsr     phex8
                move.l  4(a2),d0
                bsr     phex8
                bsr     sp1
                move.l  PLSZ(a2),d0
                bsr     phex8
                move.l  PLSZ+4(a2),d0
                bsr     phex8
                bsr     nl
                addq.w  #1,d6
                cmp.w   d7,d6
                ble.s   .r
                rts

; --- plist: " x,y[:c]" for every non-zero pixel, row by row
plist:          jsr     LVO_WaitBlit(a6)
                moveq   #0,d6
.y:             moveq   #0,d7
.x:             lea     O_PL0(a5),a2
                move.w  d6,d0
                lsl.w   #3,d0
                adda.w  d0,a2
                move.w  d7,d0
                lsr.w   #3,d0
                adda.w  d0,a2
                move.w  d7,d3
                not.w   d3
                moveq   #0,d2
                btst    d3,(a2)
                beq.s   .p1
                addq.w  #1,d2
.p1:            btst    d3,PLSZ(a2)
                beq.s   .p2
                addq.w  #2,d2
.p2:            tst.w   d2
                beq.s   .nx
                bsr     sp1
                move.w  d7,d0
                bsr     pdec
                bsr     comma
                move.w  d6,d0
                bsr     pdec
                cmp.w   #1,d2
                beq.s   .nx
                moveq   #':',d1
                bsr     putc
                move.w  d2,d0
                bsr     pdec
.nx:            addq.w  #1,d7
                cmp.w   #64,d7
                blo.s   .x
                addq.w  #1,d6
                cmp.w   #32,d6
                blo.s   .y
                bra     nl

; --- printing helpers
comma:          moveq   #',',d1
                bra.s   putc
nl:             moveq   #10,d1
                bra.s   putc
sp1:            moveq   #' ',d1
                bra.s   putc
; pdec: d0.w signed, in decimal
pdec:           ext.l   d0
                bpl.s   pdecu
                neg.l   d0
                moveq   #'-',d1
                bsr.s   putc
; pdecu: d0.l unsigned (< 655360), in decimal
pdecu:          divu    #10,d0
                move.l  d0,-(sp)
                and.l   #$FFFF,d0
                beq.s   .d
                bsr.s   pdecu
.d:             move.l  (sp)+,d0
                swap    d0
                add.b   #'0',d0
                move.b  d0,d1
putc:           move.w  d0,-(sp)
.w:             move.w  SERDATR,d0
                btst    #13,d0
                beq.s   .w
                and.w   #$FF,d1
                or.w    #$100,d1
                move.w  d1,SERDAT
                move.w  (sp)+,d0
                rts
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

; L2 lines of §10.1 (x0,y0,x1,y1), each also drawn reversed; -1 ends
l2tab:          dc.w    0,0,2,1, 0,0,6,4, 0,0,4,6, 0,0,5,2, 0,0,10,3, 0,10,9,0, 3,0,0,5
                dc.w    0,0,9,0, 0,0,0,9, 0,0,7,7, 7,0,0,7
                dc.w    10,10,20,13, 10,10,0,13, 10,10,20,7, 10,10,0,7
                dc.w    10,10,13,20, 10,10,7,20, 10,10,13,0, 10,10,7,0
                dc.w    10,10,16,13, 10,10,4,7, 5,5,5,5
                dc.w    -1
ptab0:          dc.w    20,14
ptab3:          dc.w    30,9, 30,20, 40,25
; L9 polygons of §10.6: vertex count, then (x,y) pairs; 0 ends
polys:          dc.w    3, 16,1, 28,14, 4,14
                dc.w    3, 2,2, 12,7, 2,12
                dc.w    4, 40,2, 60,5, 50,20, 35,12
                dc.w    3, 2,20, 30,23, 10,30
                dc.w    0
rnames:         dc.b    "d0d1d2d3d4d5d6d7a0a1a2a3a4a5"

gfxname:        dc.b    "graphics.library",0
layname:        dc.b    "layers.library",0
m_start:        dc.b    10,"GLP debut",10,0
m_end:          dc.b    "GLP fin",10,0
m_fail:         dc.b    "FAIL layers",10,0
m_none:         dc.b    0
m_cp:           dc.b    " cp=",0
m_fl:           dc.b    " fl=",0
m_1e:           dc.b    " 1e=",0
m_1f:           dc.b    " 1f=",0
m_pt:           dc.b    "  pt=",0
m_pens:         dc.b    " mask/fg/bg/aol/mode=",0
m_mt:           dc.b    "mt=",0
m_rows:         dc.b    " rows=",0
m_last:         dc.b    " last=",0
m_l0m:          dc.b    "L0 Move",0
m_l0d:          dc.b    "L0 Draw",0
m_l0p:          dc.b    "L0 PolyDraw",0
m_l0h:          dc.b    "L0 after",0
m_l1i:          dc.b    "L1 InitRastPort",0
m_l1a:          dc.b    "L1 SetAPen1",0
m_l1b:          dc.b    "L1 SetBPen2",0
m_l1m:          dc.b    "L1 SetDrMd0",0
m_l1v:          dc.b    "L1 Move3,4",0
m_l1d1:         dc.b    "L1 Draw10,4",0
m_l1d2:         dc.b    "L1 Draw20,9",0
m_l1p3:         dc.b    "L1 PolyDraw3",0
m_l1p0:         dc.b    "L1 PolyDraw0",0
m_l2:           dc.b    "L2 ",0
m_l3a:          dc.b    "L3 FF00 (0,1)>(40,1)",0
m_l3b:          dc.b    "L3 FF00 (40,3)>(0,3)",0
m_l3c:          dc.b    "L3 FF00 (0,5)>(40,6)",0
m_l3d1:         dc.b    "L3 FF00 (0,8)>(10,8)",0
m_l3d2:         dc.b    "L3 FF00 >(10,18)",0
m_l3d3:         dc.b    "L3 FF00 >(30,18)",0
m_l3e:          dc.b    "L3 FF00 (40,8)>(40,30)",0
m_l3f:          dc.b    "L3 FF00 (60,30)>(45,10)",0
m_l3dump:       dc.b    "L3 dump FF00",10,0
m_l3modes:      dc.b    "L3 dump modes FF00 fg1 bg2: rows 1/2 JAM1, 4/5 JAM2, 7/8 JAM1|INV, 10/11 JAM2|INV,"
                dc.b    " 13/14 COMPLEMENT, 16/17 COMPLEMENT|INV",10,0
m_l3g:          dc.b    "L3 8001 Move(0,1) Draw(40,1)",0
m_l3h0:         dc.b    "L3 8001 InitRastPort+SetAPen cp=(0,3), before",0
m_l3h:          dc.b    "L3 8001 InitRastPort+SetAPen Draw(40,3)",0
m_l3i:          dc.b    "L3 8001 Move(0,4) 1f:=3 1e:=9 Draw(40,4)",0
m_l3j0:         dc.b    "L3 8001 InitRastPort only cp=(0,6), before",0
m_l3j:          dc.b    "L3 8001 InitRastPort only Draw(40,6)",0
m_l38001:       dc.b    "L3 dump 8001",10,0
m_l4a:          dc.b    "L4 (2,2)>(12,2)>(12,12)",0
m_l4b:          dc.b    "L4 (20,2)>(30,2)>(20,2)",0
m_l4c:          dc.b    "L4 FFDF (34,2)>(44,2)>(44,12)",0
m_l4d:          dc.b    "L4 (20,6)>(30,6)>(30,6)",0
m_l4e:          dc.b    "L4 (2,20)>(12,20) Move(12,20)>(12,30)",0
m_l4f:          dc.b    "L4 mode 6 (14,26)>(40,26)",0
m_l4dump:       dc.b    "L4 dump COMPLEMENT",10,0
m_l5a:          dc.b    "L5 ONE_DOT lines",0
m_l5b:          dc.b    "L5 Mask1 FgPen3 row 28",0
m_l5c:          dc.b    "L5 Mask2 COMPLEMENT row 30",0
m_l5dump:       dc.b    "L5 dump",10,0
m_l6:           dc.b    "L6 out of bounds FgPen 3",0
m_l6dump:       dc.b    "L6 dump",10,0
m_l6g:          dc.b    "L6 guards (offset from plane 0 = value):",0
m_l7a:          dc.b    "L7 (3,0)>(3,1000) dmaconr=",0
m_l7b:          dc.b    " blitlock=",0
m_l7c:          dc.b    "L7 (0,0)>(1,1100)",0
m_l8smart:      dc.b    "L8 back layer SMART",10,0
m_l8simple:     dc.b    "L8 back layer SIMPLE",10,0
m_l8one:        dc.b    "L8 single SIMPLE layer FF00",10,0
m_l8a0:         dc.b    "L8 F0F0 Move(1,1)",0
m_l8a1:         dc.b    "L8 F0F0 Draw(10,1)",0
m_l8a2:         dc.b    "L8 F0F0 Draw(10,6)",0
m_l8b:          dc.b    "L8 F0F0 Move(2,8) Draw(40,8)",0
m_l8c:          dc.b    "L8 F0F0 Draw(40,20)",0
m_l8d:          dc.b    "L8 solid Move(30,21) Draw(60,30)",0
m_l8e:          dc.b    "L8 solid Move(30,3) Draw(33,6)",0
m_l8g:          dc.b    "L8 COMPLEMENT (2,17)>(12,17)>(12,22)",0
m_l8h:          dc.b    "L8 COMPLEMENT (15,10)>(30,10)>(30,13)",0
m_l8before:     dc.b    "L8 dump before DeleteLayer(front)",10,0
m_l8after:      dc.b    "L8 dump after DeleteLayer(front)",10,0
m_l8i1:         dc.b    "L8 Move(0,1) Draw(20,1)",0
m_l8i2:         dc.b    "L8 Draw(40,1)",0
m_l8j:          dc.b    "L8 Move(0,3) Draw(47,3)",0
m_l8k:          dc.b    "L8 Move(-8,5) Draw(40,5)",0
m_l8l:          dc.b    "L8 Move(40,7) Draw(-8,7)",0
m_l8m1:         dc.b    "L8 Move(-3,9) Draw(10,9)",0
m_l8m2:         dc.b    "L8 Draw(30,9)",0
m_l8n:          dc.b    "L8 1e:=4 Move(-8,11) Draw(40,11)",0
m_l8dump:       dc.b    "L8 dump single layer",10,0
m_l9:           dc.b    "L9 p",0
m_fwd:          dc.b    " fwd",0
m_rev:          dc.b    " rev",0
m_fill:         dc.b    " fill ret=",0
m_outl:         dc.b    " outline",0
                even

vars:
gfxb:           dc.l    0
layb:           dc.l    0
chip:           dc.l    0
li:             dc.l    0
lyb:            dc.l    0
lyf:            dc.l    0
rpa:            dc.l    0
jaddr:          dc.l    0
mk:             dc.l    $11110000,$22220000,$D2D2D2D2,$D3D3D3D3,$D4D4D4D4,$D5D5D5D5,$D6D6D6D6,$D7D7D7D7
                dc.l    $A0A0A0A0,0,$A2A2A2A2,$A3A3A3A3,$A4A4A4A4,$A5A5A5A5
bm:             ds.b    40
bm2:            ds.b    40
ai:             ds.b    24
tr:             ds.b    8
rp:             ds.b    100
vbuf:           ds.b    5*40
