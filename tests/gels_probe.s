; tests/gels_probe.s - HUNK test executable (TEST ASSET, NOT ROM code).
; Black-box probe "graphics.library GELs and animation" (docs/analysis/graphics-gels-v34.md §12, expected values
; §11). Run from the startup-sequence of a floppy without SetPatch (tests/gels_probe.sh). Calls the 15 GEL LVOs
; (InitGels, AddBob, AddVSprite, SortGList, RemVSprite, InitMasks, DrawGList, RemIBob, DoCollision, SetCollision,
; AddAnimOb, Animate, GetGBuffers, InitGMasks, FreeGBuffers) on layerless BitMaps in CHIP and writes the results
; to the direct serial port (SERDAT), between "GEL debut" and "GEL fin".
; Lines tagged DEFECT are the V34 defect vectors of the spec (PlaneOnOff shape of a non-OVERLAY Bob, the
; collision pair whose second GEL starts on the left); a ROM may deliberately differ there.
; SetCollision is only called with indexes 0..15.
; Assembly: vasmm68k_mot -Fhunkexe -kick1hunks -nosym -m68000 -o build/gels_probe tests/gels_probe.s
; Authored code; public structures (graphics/gels.h, rastport.h, gfx.h, view.h, copper.h).

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018
SERPER   EQU $DFF032
CHIPSZ   EQU 32768
HEAP0    EQU 2048        ; structures are carved from the chip block from here (planes and guards below)
BM2OFF   EQU 1024        ; second BitMap plane (G8), with 64-byte guards on each side

; LVOs checked against AROS rom/graphics/graphics.conf (bias 30, 6 bytes per slot)
LVO_AddBob       EQU -96
LVO_AddVSprite   EQU -102
LVO_DoCollision  EQU -108
LVO_DrawGList    EQU -114
LVO_InitGels     EQU -120
LVO_InitMasks    EQU -126
LVO_RemIBob      EQU -132
LVO_RemVSprite   EQU -138
LVO_SetCollision EQU -144
LVO_SortGList    EQU -150
LVO_AddAnimOb    EQU -156
LVO_Animate      EQU -162
LVO_GetGBuffers  EQU -168
LVO_InitGMasks   EQU -174
LVO_InitRastPort EQU -198
LVO_InitVPort    EQU -204
LVO_InitBitMap   EQU -390
LVO_FreeGBuffers EQU -600
; exec
LVO_Forbid       EQU -132
LVO_Permit       EQU -138
LVO_AllocMem     EQU -198
LVO_FreeMem      EQU -210
LVO_AvailMem     EQU -216
LVO_CloseLibrary EQU -414
LVO_OpenLibrary  EQU -552

; VSprite (gels.h)
VS_NEXT    EQU $00
VS_PREV    EQU $04
VS_DPATH   EQU $08
VS_CPATH   EQU $0C
VS_OLDY    EQU $10
VS_OLDX    EQU $12
VS_FLAGS   EQU $14
VS_Y       EQU $16
VS_X       EQU $18
VS_HEIGHT  EQU $1A
VS_WIDTH   EQU $1C
VS_DEPTH   EQU $1E
VS_MEMASK  EQU $20
VS_HITMASK EQU $22
VS_IMAGE   EQU $24
VS_BORDER  EQU $28
VS_COLL    EQU $2C
VS_SPRCOL  EQU $30
VS_BOB     EQU $34
VS_PICK    EQU $38
; Bob
BOB_FLAGS  EQU $00
BOB_SAVE   EQU $02
BOB_SHADOW EQU $06
BOB_BEFORE EQU $0A
BOB_AFTER  EQU $0E
BOB_VS     EQU $12
BOB_DBUF   EQU $1A
; AnimComp
AC_FLAGS   EQU $00
AC_TIMER   EQU $02
AC_TIMESET EQU $04
AC_NEXTC   EQU $06
AC_PREVC   EQU $0A
AC_NEXTS   EQU $0E
AC_PREVS   EQU $12
AC_ROUT    EQU $16
AC_YTRANS  EQU $1A
AC_XTRANS  EQU $1C
AC_HEADOB  EQU $1E
AC_BOB     EQU $22
; AnimOb
AO_CLOCK   EQU $08
AO_Y       EQU $10
AO_X       EQU $12
AO_YVEL    EQU $14
AO_XVEL    EQU $16
AO_YACC    EQU $18
AO_XACC    EQU $1A
AO_RINGY   EQU $1C
AO_RINGX   EQU $1E
AO_ROUT    EQU $20
AO_HEADC   EQU $24
; GelsInfo
GI_RSRVD   EQU $00
GI_HEAD    EQU $02
GI_TAIL    EQU $06
GI_NLINE   EQU $0A
GI_LCOL    EQU $0E
GI_COLL    EQU $12
GI_LEFT    EQU $16
GI_RIGHT   EQU $18
GI_TOP     EQU $1A
GI_BOTTOM  EQU $1C
; RastPort / ViewPort / View / GfxBase
RP_BM      EQU $04
RP_GI      EQU $14
RP_MASK    EQU $18
VP_SPRINS  EQU $0C
VP_CLRINS  EQU $10
VP_DWIDTH  EQU $18
VP_DHEIGHT EQU $1A
VP_MODES   EQU $20
GB_ACTIVIEW EQU $22
GB_VBLANK  EQU $A0
GB_SPRRES  EQU $A6

; --- PRS "text": prints an inline string, preserves every register
PRS             macro
                bsr     prsi
                dc.b    \1,0
                even
                endm
; --- DUMP bitmap,y0,y1,x0,x1: one line per row, colour digit per pixel ('.' = 0)
DUMP            macro
                lea     \1-vars(a4),a0
                movem.l d2-d5,-(sp)
                move.w  #\2,d2
                move.w  #\3,d3
                move.w  #\4,d4
                move.w  #\5,d5
                bsr     pdump
                movem.l (sp)+,d2-d5
                endm
; --- SETBM width,height,depth,fills
SETBM           macro
                move.w  #\1,d0
                move.w  #\2,d1
                move.w  #\3,d2
                lea     \4(pc),a0
                bsr     setbm
                endm
; --- BOB desc,y,x,vflags,pick<<8|onoff: builds and AddBob's a Bob (a2 = VSprite, a3 = Bob); clobbers d0-d3
BOB             macro
                lea     \1(pc),a0
                move.w  #\2,d0
                move.w  #\3,d1
                move.w  #\4,d2
                move.w  #\5,d3
                bsr     addbob
                endm
DRAW            macro
                lea     rp-vars(a4),a1
                lea     vp-vars(a4),a0
                jsr     LVO_DrawGList(a6)
                endm
SORT            macro
                lea     rp-vars(a4),a1
                jsr     LVO_SortGList(a6)
                endm
REMIBOB         macro
                move.l  a2,-(sp)
                move.l  a3,a0
                lea     rp-vars(a4),a1
                lea     vp-vars(a4),a2
                jsr     LVO_RemIBob(a6)
                move.l  (sp)+,a2
                endm
; --- CG x,y,h,w,me,hit,table,name: collision GEL (CollMask from table) added to the list; clobbers d0-d5
CG              macro
                move.w  #\2,d0
                move.w  #\1,d1
                move.w  #\3,d2
                move.w  #\4,d3
                move.w  #\5,d4
                move.w  #\6,d5
                lea     \7(pc),a0
                bsr     mkcg
                move.l  a2,a0
                move.w  #\8,d0
                bsr     regn
                endm
CASE            macro
                PRS     \1
                bsr     cnew
                endm

                section code,code
_start:
                movem.l d2-d7/a2-a6,-(sp)
                lea     vars(pc),a4
                move.w  #372,SERPER
                move.l  4.w,a6
                lea     gfxname(pc),a1
                moveq   #0,d0
                jsr     LVO_OpenLibrary(a6)
                move.l  d0,gfxb-vars(a4)
                beq     .out
                move.l  #CHIPSZ,d0
                move.l  #$10002,d1
                jsr     LVO_AllocMem(a6)
                tst.l   d0
                beq     .close
                move.l  d0,a5
                lea     m_start(pc),a0
                bsr     puts
                move.l  gfxb-vars(a4),a6
                lea     vp-vars(a4),a0
                jsr     LVO_InitVPort(a6)
                move.w  #320,vp+VP_DWIDTH-vars(a4)
                move.w  #200,vp+VP_DHEIGHT-vars(a4)
                lea     gi-vars(a4),a0
                move.b  #$FC,GI_RSRVD(a0)
                lea     nline-vars(a4),a1
                move.l  a1,GI_NLINE(a0)
                lea     lcol-vars(a4),a1
                move.l  a1,GI_LCOL(a0)
                lea     coll-vars(a4),a1
                move.l  a1,GI_COLL(a0)
                lea     collg-vars(a4),a1
                moveq   #15,d0
.cg:            move.b  #$A5,(a1)+
                dbra    d0,.cg

                bsr     g1
                bsr     g2
                bsr     g3
                bsr     g4
                bsr     g5
                bsr     g6
                bsr     g7
                bsr     g8
                bsr     g9
                bsr     g10
                bsr     g11
                bsr     g0

                lea     m_end(pc),a0
                bsr     puts
                move.l  4.w,a6
                move.l  a5,a1
                move.l  #CHIPSZ,d0
                jsr     LVO_FreeMem(a6)
.close:         move.l  4.w,a6
                move.l  gfxb-vars(a4),a1
                jsr     LVO_CloseLibrary(a6)
.out:           movem.l (sp)+,d2-d7/a2-a6
                moveq   #0,d0
                rts

; ===============================================================================================================
; G1 list: InitGels sentinels, AddVSprite order, SortGList, RemVSprite
g1:             movem.l d2-d7/a2-a3,-(sp)
                SETBM   32,8,1,zeros
                move.l  #$12345678,coll-vars(a4)
                bsr     newgels
                PRS     "G1 head"
                move.l  gi+GI_HEAD-vars(a4),a2
                bsr     psent
                PRS     "G1 tail"
                move.l  gi+GI_TAIL-vars(a4),a2
                bsr     psent
                PRS     "G1 coll0="
                move.l  coll-vars(a4),d0
                bsr     phex8
                bsr     nl
                lea     g1tab(pc),a3
                lea     g1v-vars(a4),a2
                moveq   #6,d7
.mk:            moveq   #60,d0
                bsr     newblk
                move.w  (a3)+,VS_Y(a0)
                move.w  (a3)+,VS_X(a0)
                move.w  (a3)+,d0
                bsr     regn
                move.l  a0,(a2)+
                dbra    d7,.mk
                move.l  g1v-vars(a4),a0
                move.w  #$FF02,VS_FLAGS(a0)
                lea     g1v-vars(a4),a2
                moveq   #6,d7
.add:           move.l  (a2)+,a0
                lea     rp-vars(a4),a1
                jsr     LVO_AddVSprite(a6)
                dbra    d7,.add
                PRS     "G1 add"
                bsr     plist
                move.l  g1v-vars(a4),a2
                PRS     " A:"
                bsr     pvs
                bsr     nl
                lea     g1v-vars(a4),a2
                move.l  #$0001000A,d0
                move.l  (a2),a0
                move.l  d0,VS_Y(a0)
                move.l  8(a2),a0
                move.l  d0,VS_Y(a0)
                move.l  24(a2),a0
                move.l  d0,VS_Y(a0)
                SORT
                PRS     "G1 sort"
                bsr     plist
                bsr     nl
                move.l  g1v+16-vars(a4),a2
                move.l  a2,a0
                jsr     LVO_RemVSprite(a6)
                PRS     "G1 remE"
                bsr     plist
                PRS     " E.nx="
                move.l  VS_NEXT(a2),d0
                bsr     pptr
                PRS     " E.pv="
                move.l  VS_PREV(a2),d0
                bsr     pptr
                bsr     nl
                movem.l (sp)+,d2-d7/a2-a3
                rts

; psent(a2): every field of a sentinel
psent:          PRS     " nx="
                move.l  VS_NEXT(a2),d0
                bsr     pptr
                PRS     " pv="
                move.l  VS_PREV(a2),d0
                bsr     pptr
                PRS     " dp="
                move.l  VS_DPATH(a2),d0
                bsr     pptr
                PRS     " cp="
                move.l  VS_CPATH(a2),d0
                bsr     pptr
                PRS     " oy="
                move.w  VS_OLDY(a2),d0
                bsr     phex4
                PRS     " ox="
                move.w  VS_OLDX(a2),d0
                bsr     phex4
                PRS     " fl="
                move.w  VS_FLAGS(a2),d0
                bsr     phex4
                PRS     " y="
                move.w  VS_Y(a2),d0
                bsr     phex4
                PRS     " x="
                move.w  VS_X(a2),d0
                bsr     phex4
                bra     nl

; ===============================================================================================================
; G2 InitMasks
g2:             movem.l d2-d7/a2-a3,-(sp)
                bsr     newgels
                lea     g2a(pc),a3
                bsr     g2one
                PRS     "G2 bob"
                bsr     g2pr
                lea     g2b(pc),a3
                bsr     g2one
                PRS     "G2 vsprite"
                bsr     g2pr
                movem.l (sp)+,d2-d7/a2-a3
                rts
; g2one(a3 = flags, h, w, depth, image words) -> a2 = VSprite after InitMasks
g2one:          moveq   #60,d0
                bsr     newblk
                move.l  a0,a2
                move.w  (a3)+,VS_FLAGS(a2)
                move.w  (a3)+,VS_HEIGHT(a2)
                move.w  (a3)+,VS_WIDTH(a2)
                move.w  (a3)+,VS_DEPTH(a2)
                move.w  VS_HEIGHT(a2),d4
                mulu    VS_WIDTH(a2),d4
                move.w  VS_DEPTH(a2),d5
                mulu    d4,d5
                move.l  d5,d0
                add.l   d0,d0
                bsr     newblk
                move.l  a0,VS_IMAGE(a2)
                subq.w  #1,d5
.cp:            move.w  (a3)+,(a0)+
                dbra    d5,.cp
                move.l  d4,d0
                add.l   d0,d0
                bsr     newblk
                move.l  a0,VS_COLL(a2)
                moveq   #0,d0
                move.w  VS_WIDTH(a2),d0
                add.l   d0,d0
                bsr     newblk
                move.l  a0,VS_BORDER(a2)
                move.l  a2,a0
                jmp     LVO_InitMasks(a6)
g2pr:           PRS     " bl="
                move.l  VS_BORDER(a2),a0
                move.w  VS_WIDTH(a2),d0
                bsr     pwords
                PRS     " cm="
                move.l  VS_COLL(a2),a0
                move.w  VS_HEIGHT(a2),d0
                mulu    VS_WIDTH(a2),d0
                bsr     pwords
                bra     nl

; ===============================================================================================================
; G3 Bob draw / move / OVERLAY off / RemIBob (64 x 32, 2 planes, background $33 / $0F)
g3:             movem.l d2-d7/a2-a3,-(sp)
                SETBM   64,32,2,f_33_0f
                bsr     newgels
                BOB     d_g3,3,5,6,$0300
                move.l  a2,a0
                moveq   #'B',d0
                bsr     regn
                DRAW
                PRS     "G3 draw"
                bsr     pvs
                bsr     pbf
                moveq   #8,d0
                bsr     psbuf
                bsr     nl
                DUMP    bm,0,15,0,39
                move.w  #10,VS_Y(a2)
                move.w  #20,VS_X(a2)
                SORT
                DRAW
                PRS     "G3 move"
                bsr     pvs
                bsr     pbf
                moveq   #8,d0
                bsr     psbuf
                bsr     nl
                DUMP    bm,0,15,0,39
                and.w   #$FFFB,VS_FLAGS(a2)
                DRAW
                PRS     "G3 nooverlay"
                bsr     pvs
                bsr     pbf
                bsr     nl
                DUMP    bm,0,15,0,39
                REMIBOB
                PRS     "G3 remibob"
                bsr     pvs
                bsr     pbf
                bsr     plist
                bsr     nl
                DUMP    bm,0,15,0,39
                bsr     pguard
                movem.l (sp)+,d2-d7/a2-a3
                rts

; ===============================================================================================================
; G4 PlanePick / PlaneOnOff / OVERLAY / rp->Mask
g4:             movem.l d2-d7/a2-a3,-(sp)
                SETBM   64,6,3,zeros
                bsr     newgels
                BOB     d_ring,1,0,4,$0100
                BOB     d_ring,1,8,4,$0200
                BOB     d_ring,1,16,4,$0406
                BOB     d_ring,1,24,4,$0007
                BOB     d_ring,1,48,2,$0007
                DRAW
                PRS     "G4a ov(1 0)x0 ov(2 0)x8 ov(4 6)x16 ov(0 7)x24 sb(0 7)x48"
                bsr     nl
                DUMP    bm,0,5,0,63
                bsr     pguard
                moveq   #3,d7
                PRS     "G4b nonov pick2 onoff5 x0"
                moveq   #0,d4
                moveq   #0,d5
                move.w  #$0205,d6
                bsr     g4one
                PRS     "G4b nonov pick1 onoff6 x16"
                moveq   #16,d4
                move.w  #$0106,d6
                bsr     g4one
                PRS     "G4b nonov pick4 onoff3 x32"
                moveq   #32,d4
                move.w  #$0403,d6
                bsr     g4one
                moveq   #2,d7
                move.w  #$0102,d6
                lea     g4xs(pc),a3
.dn:            move.w  (a3)+,d4
                bmi.s   .ov
                PRS     "G4c nonov pick1 onoff2 x="
                move.w  d4,d0
                bsr     pdec
                tst.w   d4
                beq.s   .ok0
                PRS     " DEFECT"
.ok0:           moveq   #0,d5
                bsr     g4one
                bra.s   .dn
.ov:            lea     g4xs(pc),a3
.dv:            move.w  (a3)+,d4
                bmi.s   .mask
                PRS     "G4c ov pick1 onoff2 x="
                move.w  d4,d0
                bsr     pdec
                moveq   #4,d5
                bsr     g4one
                bra.s   .dv
.mask:          SETBM   64,6,3,f_0ff0
                bsr     newgels
                move.b  #5,rp+RP_MASK-vars(a4)
                BOB     d_mask,1,2,2,$0700
                DRAW
                PRS     "G4d mask5"
                bsr     pvs
                moveq   #12,d0
                bsr     psbuf
                bsr     nl
                DUMP    bm,0,5,0,23
                bsr     pguard
                movem.l (sp)+,d2-d7/a2-a3
                rts
; g4one(d4 x, d5 vflags, d6 pick<<8|onoff, d7 depth): isolated ring Bob at (1, x) on a clear 64 x 6 BitMap.
; Preserves a2/a3.
g4one:          movem.l a2-a3,-(sp)
                bsr     nl
                move.w  #64,d0
                moveq   #6,d1
                move.w  d7,d2
                lea     zeros(pc),a0
                bsr     setbm
                bsr     newgels
                lea     d_ring(pc),a0
                moveq   #1,d0
                move.w  d4,d1
                move.w  d5,d2
                move.w  d6,d3
                bsr     addbob
                DRAW
                DUMP    bm,0,5,0,63
                bsr     pguard
                movem.l (sp)+,a2-a3
                rts

; ===============================================================================================================
; G5 SAVEBOB and no-SAVEBACK Bobs drawn at x 0, 10, 20 then RemIBob
g5:             movem.l d2-d7/a2-a3,-(sp)
                SETBM   48,6,1,zeros
                bsr     newgels
                BOB     d_rings,1,0,6,$0100
                PRS     "G5 savebob"
                bsr     g5run
                SETBM   48,6,1,zeros
                bsr     newgels
                BOB     d_ring,1,0,4,$0100
                PRS     "G5 nosaveback"
                bsr     g5run
                movem.l (sp)+,d2-d7/a2-a3
                rts
g5run:          DRAW
                move.w  #10,VS_X(a2)
                DRAW
                move.w  #20,VS_X(a2)
                DRAW
                PRS     " drawn"
                bsr     pvs
                bsr     pbf
                bsr     nl
                DUMP    bm,0,5,0,47
                REMIBOB
                PRS     " remibob"
                bsr     pvs
                bsr     pbf
                bsr     plist
                bsr     nl
                DUMP    bm,0,5,0,47
                bra     pguard

; ===============================================================================================================
; G6 Before/After
g6:             movem.l d2-d7/a2-a3,-(sp)
                bsr     g6mk
                DRAW
                PRS     "G6 unlinked"
                bsr     pchain
                bsr     g6ab
                bsr     nl
                DUMP    bm,0,5,0,31
                move.l  gab-vars(a4),a0
                move.l  gbb-vars(a4),a1
                move.l  a1,BOB_AFTER(a0)
                move.l  a0,BOB_BEFORE(a1)
                DRAW
                PRS     "G6 linked A.After=B"
                bsr     pchain
                bsr     g6ab
                bsr     nl
                DUMP    bm,0,5,0,31
                move.l  gbb-vars(a4),a3
                REMIBOB
                PRS     "G6 remibobB"
                bsr     g6ab
                bsr     plist
                bsr     nl
                DUMP    bm,0,5,0,31
                DRAW
                PRS     "G6 redraw"
                bsr     pchain
                bsr     g6ab
                bsr     plist
                bsr     nl
                DUMP    bm,0,5,0,31
                bsr     g6mk
                DRAW
                move.l  gab-vars(a4),a3
                REMIBOB
                PRS     "G6u remibobA"
                bsr     g6ab
                bsr     plist
                bsr     nl
                DUMP    bm,0,5,0,31
                DRAW
                PRS     "G6u redraw"
                bsr     g6ab
                bsr     plist
                bsr     nl
                DUMP    bm,0,5,0,31
                bsr     pguard
                movem.l (sp)+,d2-d7/a2-a3
                rts
; g6mk: clear 48 x 6 x 2 BitMap, list with A (colour 1 at (1,4)) and B (colour 2 at (2,12)), 16 x 3 each
g6mk:           SETBM   48,6,2,zeros
                bsr     newgels
                BOB     d_solid3,1,4,2,$0100
                move.l  a2,gav-vars(a4)
                move.l  a3,gab-vars(a4)
                move.l  a2,a0
                moveq   #'A',d0
                bsr     regn
                BOB     d_solid3,2,12,2,$0200
                move.l  a2,gbv-vars(a4)
                move.l  a3,gbb-vars(a4)
                move.l  a2,a0
                moveq   #'B',d0
                bsr     regn
                rts
g6ab:           PRS     " A:"
                move.l  gav-vars(a4),a2
                move.l  gab-vars(a4),a3
                bsr     pvs
                bsr     pbf
                PRS     " B:"
                move.l  gbv-vars(a4),a2
                move.l  gbb-vars(a4),a3
                bsr     pvs
                bra     pbf

; ===============================================================================================================
; G7 clipping against the BitMap (32 x 8, 1 plane)
g7:             movem.l d2-d7/a2-a3,-(sp)
                lea     g7tab(pc),a3
.lp:            move.w  (a3)+,d6
                cmp.w   #$7FFF,d6
                beq     .x
                move.w  (a3)+,d7
                PRS     "G7 y="
                move.w  d6,d0
                bsr     pdec
                PRS     " x="
                move.w  d7,d0
                bsr     pdec
                SETBM   32,8,1,zeros
                bsr     newgels
                move.l  a3,-(sp)
                lea     d_box(pc),a0
                move.w  d6,d0
                move.w  d7,d1
                moveq   #6,d2
                move.w  #$0100,d3
                bsr     addbob
                DRAW
                bsr     pvs
                bsr     pbf
                bsr     pchain
                bsr     nl
                DUMP    bm,0,7,0,31
                bsr     pguard
                move.l  (sp)+,a3
                bra     .lp
.x:             movem.l (sp)+,d2-d7/a2-a3
                rts

; ===============================================================================================================
; G8 double buffering (48 x 6, 1 plane, BM1 $AA, BM2 $55, Bob FF00 x 3, DBufPacket preset)
g8:             movem.l d2-d7/a2-a3,-(sp)
                SETBM   48,6,1,f_aa
                lea     bm-vars(a4),a0
                lea     bm2-vars(a4),a1
                moveq   #9,d0
.cb:            move.l  (a0)+,(a1)+
                dbra    d0,.cb
                lea     BM2OFF-64(a5),a0
                moveq   #63,d0
.g0:            move.b  #$A5,(a0)+
                dbra    d0,.g0
                move.l  a0,bm2+8-vars(a4)
                moveq   #35,d0
.p2:            move.b  #$55,(a0)+
                dbra    d0,.p2
                moveq   #63,d0
.g1:            move.b  #$A5,(a0)+
                dbra    d0,.g1
                bsr     newgels
                BOB     d_ff00,1,2,2,$0100
                move.l  a2,a0
                moveq   #'B',d0
                bsr     regn
                moveq   #12,d0
                bsr     newblk
                move.l  a0,BOB_DBUF(a3)
                move.l  #$11112222,(a0)
                move.l  #$33333333,4(a0)
                move.l  a0,a1
                moveq   #24,d0
                bsr     newblk
                move.l  a0,8(a1)
                lea     g8tab(pc),a0
                move.l  a0,dptr-vars(a4)
                moveq   #1,d7
.fr:            move.l  dptr-vars(a4),a0
                move.w  (a0)+,d6
                bmi.s   .rem
                move.w  (a0)+,VS_X(a2)
                move.l  a0,dptr-vars(a4)
                bsr     g8bm
                DRAW
                PRS     "G8 frame"
                move.w  d7,d0
                bsr     pdec
                bsr     g8pr
                addq.w  #1,d7
                bra.s   .fr
.rem:           or.w    #$0400,BOB_FLAGS(a3)
                moveq   #1,d6
                bsr     g8bm
                DRAW
                PRS     "G8 rembob1 BM2"
                bsr     g8pr
                moveq   #0,d6
                bsr     g8bm
                DRAW
                PRS     "G8 rembob2 BM1"
                bsr     g8pr
                movem.l (sp)+,d2-d7/a2-a3
                rts
; g8bm(d6 = 0 BM1 / 1 BM2): rp->BitMap
g8bm:           lea     bm-vars(a4),a0
                tst.w   d6
                beq.s   .s
                lea     bm2-vars(a4),a0
.s:             move.l  a0,rp+RP_BM-vars(a4)
                rts
g8pr:           bsr     pvs
                bsr     pbf
                bsr     plist
                bsr     nl
                PRS     " BM1"
                bsr     nl
                DUMP    bm,0,4,0,47
                PRS     " BM2"
                bsr     nl
                DUMP    bm2,0,4,0,47
                bsr     pguard
                PRS     " bm2guard="
                lea     BM2OFF-64(a5),a0
                bsr     chk64
                bne.s   .bad
                lea     BM2OFF+36(a5),a0
                bsr     chk64
                bne.s   .bad
                PRS     "ok"
                bra     nl
.bad:           PRS     "BAD"
                bra     nl

; ===============================================================================================================
; G9 VSprites: allocation, nextLine, lastColor, SprIns / ClrIns
g9:             movem.l d2-d7/a2-a3,-(sp)
                SETBM   320,24,1,zeros
                bsr     newgels
                bsr     g9pre
                move.b  #$FC,gi+GI_RSRVD-vars(a4)
                lea     g9tab(pc),a3
                lea     vsl-vars(a4),a1
                moveq   #0,d7
.mk:            moveq   #6,d0
                bsr     newblk
                move.w  6(a3),d0
                subq.w  #1,d0
                mulu    #6,d0
                lea     cset(pc),a1
                add.w   d0,a1
                move.l  (a1)+,(a0)
                move.w  (a1),4(a0)
                moveq   #'p',d0
                add.w   d7,d0
                bsr     regn
                move.w  (a3)+,d0
                move.w  (a3)+,d1
                move.w  (a3)+,d2
                addq.l  #2,a3
                bsr     mkvsp
                move.l  a2,a0
                moveq   #'a',d0
                add.w   d7,d0
                bsr     regn
                lea     vsl-vars(a4),a1
                move.w  d7,d0
                lsl.w   #2,d0
                move.l  a2,0(a1,d0.w)
                addq.w  #1,d7
                cmp.w   #7,d7
                blo.s   .mk
                DRAW
                PRS     "G9a sprRsrvd=FC"
                moveq   #6,d7
                bsr     g9pr
                bsr     newgels
                bsr     g9pre
                move.b  #$0C,gi+GI_RSRVD-vars(a4)
                lea     g9tab2(pc),a3
                moveq   #0,d7
.mk2:           move.w  (a3)+,d0
                move.w  (a3)+,d1
                move.w  (a3)+,d2
                sub.l   a0,a0
                bsr     mkvsp
                move.l  a2,a0
                moveq   #'a',d0
                add.w   d7,d0
                bsr     regn
                lea     vsl-vars(a4),a1
                move.w  d7,d0
                lsl.w   #2,d0
                move.l  a2,0(a1,d0.w)
                addq.w  #1,d7
                cmp.w   #4,d7
                blo.s   .mk2
                DRAW
                PRS     "G9b sprRsrvd=0C"
                moveq   #3,d7
                bsr     g9pr
                ; G9c: HIRES ViewPort, a VSprite partly above the BitMap (X 101, Y -2, H 6): the two rows above are
                ; clipped (graphics-gels §5.8: POS $2C59, CTL $3001, SPRxPT = ImageData + 8 bytes)
                bsr     newgels
                moveq   #24,d0
                bsr     newblk
                move.l  a0,vimg-vars(a4)
                lea     nline-vars(a4),a0
                moveq   #11,d0
.nl9c:          move.l  #$55555555,(a0)+
                dbra    d0,.nl9c
                move.b  #$FC,gi+GI_RSRVD-vars(a4)
                move.w  #$8000,vp+VP_MODES-vars(a4)
                moveq   #-2,d0
                moveq   #101,d1
                moveq   #6,d2
                sub.l   a0,a0
                bsr     mkvsp
                move.l  a2,a0
                moveq   #'a',d0
                bsr     regn
                move.l  a2,vsl-vars(a4)
                DRAW
                clr.w   vp+VP_MODES-vars(a4)
                PRS     "G9c hires y=-2"
                moveq   #0,d7
                bsr     g9pr
                movem.l (sp)+,d2-d7/a2-a3
                rts
; g9pre: shared VSprite image (5 lines x 2 words, chip), nextLine/lastColor preset to $5555 / $55555555
g9pre:          moveq   #20,d0
                bsr     newblk
                move.l  a0,vimg-vars(a4)
                moveq   #4,d0
.im:            move.l  #$F00F0FF0,(a0)+
                dbra    d0,.im
                lea     nline-vars(a4),a0
                moveq   #11,d0
.nl:            move.l  #$55555555,(a0)+
                dbra    d0,.nl
                rts
; g9pr(d7 = VSprites - 1): flags, nextLine, lastColor, offsets, SprIns, ClrIns
g9pr:           lea     vsl-vars(a4),a3
.f:             bsr     sp1
                move.l  (a3)+,a2
                move.l  a2,d0
                bsr     pptr
                moveq   #'=',d1
                bsr     putc
                move.w  VS_FLAGS(a2),d0
                bsr     phex4
                dbra    d7,.f
                bsr     nl
                PRS     " nextLine="
                lea     nline-vars(a4),a0
                moveq   #7,d7
.n:             move.w  (a0)+,d0
                bsr     pdec
                bsr     sp1
                dbra    d7,.n
                PRS     "lastColor="
                lea     lcol-vars(a4),a0
                moveq   #7,d7
.c:             move.l  (a0)+,d0
                bsr     pptr
                bsr     sp1
                dbra    d7,.c
                bsr     nl
                PRS     " img="
                move.l  vimg-vars(a4),d0
                bsr     phex8
                PRS     " actiview dx/dy="
                move.l  GB_ACTIVIEW(a6),d0
                beq.s   .nv
                move.l  d0,a0
                move.w  14(a0),d0
                bsr     pdec
                moveq   #'/',d1
                bsr     putc
                move.w  12(a0),d0
.nv:            bsr     pdec
                PRS     " sprres="
                move.b  GB_SPRRES(a6),d0
                bsr     phex2
                PRS     " vblank="
                move.b  GB_VBLANK(a6),d0
                bsr     phex2
                bsr     nl
                PRS     " SprIns"
                move.l  vp+VP_SPRINS-vars(a4),d0
                bsr     pcop
                bsr     nl
                PRS     " ClrIns"
                move.l  vp+VP_CLRINS-vars(a4),d0
                bsr     pcop
                bra     nl
; mkvsp(d0 y, d1 x, d2 h, a0 = SprColors or 0) -> a2 = VSPRITE VSprite (W 1, Depth 2, ImageData vimg) added
mkvsp:          movem.l d0-d2/a0,-(sp)
                moveq   #60,d0
                bsr     newblk
                move.l  a0,a2
                movem.l (sp)+,d0-d2/a0
                move.w  d0,VS_Y(a2)
                move.w  d1,VS_X(a2)
                move.w  d2,VS_HEIGHT(a2)
                move.w  #1,VS_WIDTH(a2)
                move.w  #2,VS_DEPTH(a2)
                move.w  #1,VS_FLAGS(a2)
                move.l  vimg-vars(a4),VS_IMAGE(a2)
                move.l  a0,VS_SPRCOL(a2)
                move.l  a2,a0
                lea     rp-vars(a4),a1
                jmp     LVO_AddVSprite(a6)
; pcop(d0 = CopList): " none" | " n=<Count>" + instructions (W v,h / M dest,data / > next block) | raw longs
pcop:           movem.l d0-d4/a0-a2,-(sp)
                tst.l   d0
                bne.s   .nz
                PRS     " none"
                bra     .x
.nz:            btst    #0,d0
                beq.s   .ev
                PRS     " odd"
                bra     .x
.ev:            move.l  d0,a2
                move.l  12(a2),d1
                move.w  28(a2),d2
                tst.l   d1
                beq     .raw
                btst    #0,d1
                bne     .raw
                cmp.w   #64,d2
                bhi     .raw
                PRS     " n="
                move.w  d2,d0
                bsr     pdec
                move.l  d1,a0
                moveq   #80,d3
                subq.w  #1,d2
                bmi     .x
.l:             subq.w  #1,d3
                bmi     .x
                move.w  (a0)+,d0
                move.w  d0,d4
                and.w   #3,d4
                cmp.w   #2,d4
                bne.s   .nb
                PRS     " >"
                move.l  (a0),d0
                beq     .x
                btst    #0,d0
                bne     .x
                move.l  d0,a1
                move.l  12(a1),d0
                beq     .x
                btst    #0,d0
                bne     .x
                move.l  d0,a0
                bra.s   .l
.nb:            cmp.w   #1,d4
                bne.s   .mv
                PRS     " W"
                move.w  (a0)+,d0
                bsr     pdec
                moveq   #',',d1
                bsr     putc
                move.w  (a0)+,d0
                bsr     pdec
                bra.s   .nx
.mv:            PRS     " M"
                move.w  (a0)+,d0
                bsr     phex4
                moveq   #',',d1
                bsr     putc
                move.w  (a0)+,d0
                bsr     phex4
.nx:            dbra    d2,.l
                bra.s   .x
.raw:           PRS     " raw"
                moveq   #15,d2
                move.l  a2,a0
.r:             bsr     sp1
                move.l  (a0)+,d0
                bsr     phex8
                dbra    d2,.r
.x:             movem.l (sp)+,d0-d4/a0-a2
                rts

; ===============================================================================================================
; G10 DoCollision / SetCollision
g10:            movem.l d2-d7/a2-a3,-(sp)
                SETBM   64,32,1,zeros
                moveq   #1,d6
.sc:            lea     lgtab(pc),a0
                move.w  d6,d0
                lsl.w   #2,d0
                move.l  0(a0,d0.w),a0
                move.l  d6,d0
                lea     gi-vars(a4),a1
                jsr     LVO_SetCollision(a6)
                addq.w  #1,d6
                cmp.w   #15,d6
                ble.s   .sc
                PRS     "G10 setcoll"
                lea     coll-vars(a4),a0
                lea     lgtab(pc),a1
                moveq   #1,d6
.ck:            addq.l  #4,a1
                move.l  (a1),d0
                cmp.l   4(a0),d0
                bne.s   .ckb
                addq.l  #4,a0
                addq.w  #1,d6
                cmp.w   #15,d6
                ble.s   .ck
                PRS     " table=ok"
                bra.s   .ckg
.ckb:           PRS     " table=BAD"
.ckg:           lea     collg-vars(a4),a0
                moveq   #15,d0
.g:             cmp.b   #$A5,(a0)+
                dbne    d0,.g
                bne.s   .gb
                PRS     " guard=ok"
                bra.s   .gx
.gb:            PRS     " guard=BAD"
.gx:            bsr     nl
; bounds: left 10, right 50, top 5, bottom 20
                move.w  #10,gi+GI_LEFT-vars(a4)
                move.w  #50,gi+GI_RIGHT-vars(a4)
                move.w  #5,gi+GI_TOP-vars(a4)
                move.w  #20,gi+GI_BOTTOM-vars(a4)
                CASE    "G10 b1 Y4 pixel y6 (exp [0](G 1)) TOPHIT-QUIRK"
                CG      20,4,4,1,0,1,t_r2,'G'
                bsr     crun
                CASE    "G10 b2 Y4 pixel y7 (exp none)"
                CG      20,4,4,1,0,1,t_r3,'G'
                bsr     crun
                CASE    "G10 b3 Y5 row0 (exp none)"
                CG      20,5,4,1,0,1,t_r0,'G'
                bsr     crun
                CASE    "G10 b4 Y18 pixel y20 (exp none)"
                CG      20,18,4,1,0,1,t_r2,'G'
                bsr     crun
                CASE    "G10 b5 Y18 pixel y21 (exp [0](G 2))"
                CG      20,18,4,1,0,1,t_r3,'G'
                bsr     crun
                CASE    "G10 b6 X8 col9 (exp [0](G 4))"
                CG      8,10,4,1,0,1,t_c1,'G'
                bsr     crun
                CASE    "G10 b7 X8 col10 (exp none)"
                CG      8,10,4,1,0,1,t_c2,'G'
                bsr     crun
                CASE    "G10 b8 X40 col51 (exp [0](G 8))"
                CG      40,10,4,1,0,1,t_c11,'G'
                bsr     crun
                CASE    "G10 b9 X40 col50 (exp none)"
                CG      40,10,4,1,0,1,t_c10,'G'
                bsr     crun
                CASE    "G10 b10 X4 Y2 all hit1 (exp [0](G 5))"
                CG      4,2,4,1,0,1,t_all,'G'
                bsr     crun
                CASE    "G10 b11 X4 Y2 all hit2 (exp [0](G 5))"
                CG      4,2,4,1,0,2,t_all,'G'
                bsr     crun
                CASE    "G10 b12 X4 Y2 all hit0 (exp none)"
                CG      4,2,4,1,0,0,t_all,'G'
                bsr     crun
                CASE    "G10 b13 X4 Y2 all hit1 coll0=NULL (exp none)"
                moveq   #0,d0
                sub.l   a0,a0
                lea     gi-vars(a4),a1
                jsr     LVO_SetCollision(a6)
                CG      4,2,4,1,0,1,t_all,'G'
                bsr     crun
; pairs: bounds 0..63 x 0..31
                clr.w   gi+GI_LEFT-vars(a4)
                move.w  #63,gi+GI_RIGHT-vars(a4)
                clr.w   gi+GI_TOP-vars(a4)
                move.w  #31,gi+GI_BOTTOM-vars(a4)
                CASE    "G10 p1 P(10 5)me2 Q(14 7)hit2 (exp [1](P Q))"
                CG      10,5,4,1,2,0,t_all,'P'
                CG      14,7,4,1,0,2,t_all,'Q'
                bsr     crun
                CASE    "G10 p2 P(10 5)hit2 Q(14 7)me2 (exp none)"
                CG      10,5,4,1,0,2,t_all,'P'
                CG      14,7,4,1,2,0,t_all,'Q'
                bsr     crun
                CASE    "G10 p3 P(10 5)FF00 Q(18 7)00FF (exp none)"
                CG      10,5,4,1,2,0,t_ff00,'P'
                CG      18,7,4,1,0,2,t_00ff,'Q'
                bsr     crun
                CASE    "G10 p4 me0C hit0E (exp [2](P Q))"
                CG      10,5,4,1,$0C,0,t_all,'P'
                CG      14,7,4,1,0,$0E,t_all,'Q'
                bsr     crun
                CASE    "G10 p5 Q(25 6) 1 column (exp [1](P Q))"
                CG      10,5,4,1,2,0,t_all,'P'
                CG      25,6,4,1,0,2,t_all,'Q'
                bsr     crun
                CASE    "G10 p7 P(26 5) Q(26 6) (exp [1](P Q))"
                CG      26,5,4,1,2,0,t_all,'P'
                CG      26,6,4,1,0,2,t_all,'Q'
                bsr     crun
                CASE    "G10 p8a Q(14 9) (exp none)"
                CG      10,5,4,1,2,0,t_all,'P'
                CG      14,9,4,1,0,2,t_all,'Q'
                bsr     crun
                CASE    "G10 p8b Q(26 6) adjacent (exp none)"
                CG      10,5,4,1,2,0,t_all,'P'
                CG      26,6,4,1,0,2,t_all,'Q'
                bsr     crun
                CASE    "G10 p11 me8001 hit8001 (exp [15](P Q))"
                CG      10,5,4,1,$8001,0,t_all,'P'
                CG      14,7,4,1,0,$8001,t_all,'Q'
                bsr     crun
                CASE    "G10 p12 P Q S (exp [1](P Q) [1](P S) [1](Q S))"
                CG      10,5,4,1,2,2,t_all,'P'
                CG      12,6,4,1,2,2,t_all,'Q'
                CG      14,7,4,1,2,2,t_all,'S'
                bsr     crun
; p6 DEFECT: P (26,5) all, Q (x,6) all, x = 11..25 (expected on 1.3: no call at all)
                PRS     "G10 p6 DEFECT P(26 5) Q(x 6) calls at x="
                moveq   #11,d6
.s6:            bsr     cnew
                CG      26,5,4,1,2,0,t_all,'P'
                moveq   #6,d0
                move.w  d6,d1
                moveq   #4,d2
                moveq   #1,d3
                moveq   #0,d4
                moveq   #2,d5
                lea     t_all(pc),a0
                bsr     mkcg
                bsr     cdo
                tst.w   nlog-vars(a4)
                beq.s   .n6
                move.w  d6,d0
                bsr     pdec
                bsr     sp1
.n6:            addq.w  #1,d6
                cmp.w   #25,d6
                ble.s   .s6
                bsr     nl
; p9 DEFECT: P (26,5) all 16 wide, Q 32 wide at (18,6) one pixel at column c = 18..49 (1.3: c = 18..25 only)
                PRS     "G10 p9 DEFECT P(26 5) Q32(18 6) pixel c: calls at c="
                moveq   #18,d6
.s9:            bsr     cnew
                CG      26,5,4,1,2,0,t_all,'P'
                moveq   #6,d0
                moveq   #18,d1
                moveq   #4,d2
                moveq   #2,d3
                moveq   #0,d4
                moveq   #2,d5
                sub.l   a0,a0
                bsr     mkcg
                move.w  d6,d0
                sub.w   #18,d0
                bsr     setpix
                bsr     cdo
                tst.w   nlog-vars(a4)
                beq.s   .n9
                move.w  d6,d0
                bsr     pdec
                bsr     sp1
.n9:            addq.w  #1,d6
                cmp.w   #49,d6
                ble.s   .s9
                bsr     nl
; p10: P (18,5) 32 wide all, Q (26,6) 16 wide one pixel at c = 26..41 (1.3: every c)
                PRS     "G10 p10 P32(18 5) Q(26 6) pixel c: calls at c="
                moveq   #26,d6
.s10:           bsr     cnew
                CG      18,5,4,2,2,0,t_all,'P'
                moveq   #6,d0
                moveq   #26,d1
                moveq   #4,d2
                moveq   #1,d3
                moveq   #0,d4
                moveq   #2,d5
                sub.l   a0,a0
                bsr     mkcg
                move.w  d6,d0
                sub.w   #26,d0
                bsr     setpix
                bsr     cdo
                tst.w   nlog-vars(a4)
                beq.s   .n10
                move.w  d6,d0
                bsr     pdec
                bsr     sp1
.n10:           addq.w  #1,d6
                cmp.w   #41,d6
                ble.s   .s10
                bsr     nl
; symmetric masks (both GELs MeMask = HitMask): same 1.3 result, independent of the mask direction
                CASE    "G10 p3s sym FF00/00FF (exp none)"
                CG      10,5,4,1,2,2,t_ff00,'P'
                CG      18,7,4,1,2,2,t_00ff,'Q'
                bsr     crun
                CASE    "G10 p4s sym P 0C/0C Q 0E/0E (exp [2](P Q))"
                CG      10,5,4,1,$0C,$0C,t_all,'P'
                CG      14,7,4,1,$0E,$0E,t_all,'Q'
                bsr     crun
                CASE    "G10 p5s sym Q(25 6) 1 column (exp [1](P Q))"
                CG      10,5,4,1,2,2,t_all,'P'
                CG      25,6,4,1,2,2,t_all,'Q'
                bsr     crun
                CASE    "G10 p7s sym P(26 5) Q(26 6) (exp [1](P Q))"
                CG      26,5,4,1,2,2,t_all,'P'
                CG      26,6,4,1,2,2,t_all,'Q'
                bsr     crun
                CASE    "G10 p8as sym Q(14 9) (exp none)"
                CG      10,5,4,1,2,2,t_all,'P'
                CG      14,9,4,1,2,2,t_all,'Q'
                bsr     crun
                CASE    "G10 p8bs sym Q(26 6) adjacent (exp none)"
                CG      10,5,4,1,2,2,t_all,'P'
                CG      26,6,4,1,2,2,t_all,'Q'
                bsr     crun
                CASE    "G10 p11s sym 8001 (exp [15](P Q))"
                CG      10,5,4,1,$8001,$8001,t_all,'P'
                CG      14,7,4,1,$8001,$8001,t_all,'Q'
                bsr     crun
                PRS     "G10 p6s DEFECT sym P(26 5) Q(x 6) calls at x="
                moveq   #11,d6
.t6:            bsr     cnew
                CG      26,5,4,1,2,2,t_all,'P'
                moveq   #6,d0
                move.w  d6,d1
                moveq   #4,d2
                moveq   #1,d3
                moveq   #2,d4
                moveq   #2,d5
                lea     t_all(pc),a0
                bsr     mkcg
                bsr     cdo
                tst.w   nlog-vars(a4)
                beq.s   .u6
                move.w  d6,d0
                bsr     pdec
                bsr     sp1
.u6:            addq.w  #1,d6
                cmp.w   #25,d6
                ble.s   .t6
                bsr     nl
                PRS     "G10 p9s DEFECT sym P(26 5) Q32(18 6) pixel c: calls at c="
                moveq   #18,d6
.t9:            bsr     cnew
                CG      26,5,4,1,2,2,t_all,'P'
                moveq   #6,d0
                moveq   #18,d1
                moveq   #4,d2
                moveq   #2,d3
                moveq   #2,d4
                moveq   #2,d5
                sub.l   a0,a0
                bsr     mkcg
                move.w  d6,d0
                sub.w   #18,d0
                bsr     setpix
                bsr     cdo
                tst.w   nlog-vars(a4)
                beq.s   .u9
                move.w  d6,d0
                bsr     pdec
                bsr     sp1
.u9:            addq.w  #1,d6
                cmp.w   #49,d6
                ble.s   .t9
                bsr     nl
                PRS     "G10 p10s sym P32(18 5) Q(26 6) pixel c: calls at c="
                moveq   #26,d6
.t10:           bsr     cnew
                CG      18,5,4,2,2,2,t_all,'P'
                moveq   #6,d0
                moveq   #26,d1
                moveq   #4,d2
                moveq   #1,d3
                moveq   #2,d4
                moveq   #2,d5
                sub.l   a0,a0
                bsr     mkcg
                move.w  d6,d0
                sub.w   #26,d0
                bsr     setpix
                bsr     cdo
                tst.w   nlog-vars(a4)
                beq.s   .u10
                move.w  d6,d0
                bsr     pdec
                bsr     sp1
.u10:           addq.w  #1,d6
                cmp.w   #41,d6
                ble.s   .t10
                bsr     nl
                movem.l (sp)+,d2-d7/a2-a3
                rts
; cnew: fresh list, collHandler[0] = logger 0
cnew:           bsr     newgels
                moveq   #0,d0
                lea     lg0(pc),a0
                lea     gi-vars(a4),a1
                jmp     LVO_SetCollision(a6)
cdo:            clr.w   nlog-vars(a4)
                lea     rp-vars(a4),a1
                jmp     LVO_DoCollision(a6)
crun:           bsr.s   cdo
                moveq   #2,d0
                bsr     plog
                bra     nl
; setpix(a2 = VSprite, d0 = column inside the GEL): sets that pixel on row 0 of CollMask, BorderLine rebuilt
setpix:         move.l  VS_COLL(a2),a0
                move.w  d0,d1
                lsr.w   #4,d1
                add.w   d1,d1
                add.w   d1,a0
                not.w   d0
                and.w   #15,d0
                move.w  (a0),d1
                bset    d0,d1
                move.w  d1,(a0)
                bra     cgfix
; mkcg(d0 y, d1 x, d2 h, d3 w, d4 MeMask, d5 HitMask, a0 = CollMask words or 0) -> a2 = GEL added to the list.
; Depth 1, ImageData = CollMask, BorderLine = OR of the rows. Preserves d2-d7.
mkcg:           movem.l d2-d7,-(sp)
                move.l  a0,dptr-vars(a4)
                move.w  d0,d6
                move.w  d1,d7
                moveq   #60,d0
                bsr     newblk
                move.l  a0,a2
                move.w  d6,VS_Y(a2)
                move.w  d7,VS_X(a2)
                move.w  d2,VS_HEIGHT(a2)
                move.w  d3,VS_WIDTH(a2)
                move.w  #1,VS_DEPTH(a2)
                move.w  d4,VS_MEMASK(a2)
                move.w  d5,VS_HITMASK(a2)
                mulu    d3,d2
                move.l  d2,d0
                add.l   d0,d0
                bsr     newblk
                move.l  a0,VS_COLL(a2)
                move.l  a0,VS_IMAGE(a2)
                move.l  dptr-vars(a4),d0
                beq.s   .z
                move.l  d0,a1
                subq.w  #1,d2
.c:             move.w  (a1)+,(a0)+
                dbra    d2,.c
.z:             moveq   #0,d0
                move.w  d3,d0
                add.l   d0,d0
                bsr     newblk
                move.l  a0,VS_BORDER(a2)
                bsr.s   cgfix
                move.l  a2,a0
                lea     rp-vars(a4),a1
                jsr     LVO_AddVSprite(a6)
                movem.l (sp)+,d2-d7
                rts
; cgfix(a2): BorderLine = OR of the CollMask rows, per word column. Clobbers d0/d1/a0.
cgfix:          movem.l d2-d4,-(sp)
                move.w  VS_WIDTH(a2),d2
                subq.w  #1,d2
                moveq   #0,d3
                moveq   #0,d4
                move.w  VS_WIDTH(a2),d4
                add.l   d4,d4
.c:             moveq   #0,d0
                move.l  VS_COLL(a2),a0
                add.l   d3,a0
                move.w  VS_HEIGHT(a2),d1
                subq.w  #1,d1
.r:             or.w    (a0),d0
                add.l   d4,a0
                dbra    d1,.r
                move.l  VS_BORDER(a2),a0
                move.w  d0,0(a0,d3.l)
                addq.l  #2,d3
                dbra    d2,.c
                movem.l (sp)+,d2-d4
                rts

; ===============================================================================================================
; G11 animation: GetGBuffers, InitGMasks, AddAnimOb, Animate x4, FreeGBuffers
g11:            movem.l d2-d7/a2-a3,-(sp)
                SETBM   64,32,2,zeros
                bsr     newgels
                moveq   #42,d0
                bsr     newblk
                move.l  a0,an_ob-vars(a4)
                moveq   #'O',d0
                bsr     regn
                move.l  a0,a3
                move.w  #640,AO_Y(a3)
                move.w  #320,AO_X(a3)
                move.w  #32,AO_YVEL(a3)
                move.w  #100,AO_XVEL(a3)
                clr.w   AO_YACC(a3)
                move.w  #-6,AO_XACC(a3)
                move.w  #192,AO_RINGY(a3)
                move.w  #1280,AO_RINGX(a3)
                lea     lg0(pc),a0
                move.l  a0,AO_ROUT(a3)
                moveq   #0,d0
                moveq   #0,d1
                moveq   #0,d2
                moveq   #0,d3
                moveq   #'1',d4
                moveq   #'x',d5
                bsr     mkcomp
                move.l  a0,an_c1-vars(a4)
                moveq   #2,d0
                move.w  #256,d1
                move.w  #512,d2
                moveq   #0,d3
                moveq   #'a',d4
                moveq   #'y',d5
                bsr     mkcomp
                move.l  a0,an_c2a-vars(a4)
                moveq   #3,d0
                move.w  #256,d1
                move.w  #544,d2
                moveq   #1,d3
                moveq   #'b',d4
                moveq   #'z',d5
                bsr     mkcomp
                move.l  a0,an_c2b-vars(a4)
                move.l  an_c1-vars(a4),a0
                move.l  an_c2a-vars(a4),a1
                move.l  an_c2b-vars(a4),a2
                move.l  a1,AC_NEXTC(a0)
                move.l  a0,AC_PREVC(a1)
                move.l  a0,AC_NEXTS(a0)
                move.l  a0,AC_PREVS(a0)
                move.l  a2,AC_NEXTS(a1)
                move.l  a2,AC_PREVS(a1)
                move.l  a1,AC_NEXTS(a2)
                move.l  a1,AC_PREVS(a2)
                move.l  a0,AO_HEADC(a3)
                bsr     forbid
                bsr     amem
                movem.l d0-d1,-(sp)
                move.l  a3,a0
                lea     rp-vars(a4),a1
                moveq   #1,d0
                jsr     LVO_GetGBuffers(a6)
                move.l  d0,d7
                bsr     amem
                movem.l (sp)+,d2-d3
                bsr     permit
                PRS     "G11 getgbuffers d0="
                exg     d0,d7
                bsr     phex8
                exg     d0,d7
                sub.l   d0,d2
                sub.l   d1,d3
                PRS     " chip="
                move.l  d2,d0
                bsr     pdec
                PRS     " other="
                move.l  d3,d0
                sub.l   d2,d0
                bsr     pdec
                bsr     nl
                move.l  a3,a0
                jsr     LVO_InitGMasks(a6)
                PRS     "G11 initgmasks d0="
                bsr     phex8
                bsr     nl
                clr.l   akey-vars(a4)
                move.l  a3,a0
                lea     akey-vars(a4),a1
                lea     rp-vars(a4),a2
                jsr     LVO_AddAnimOb(a6)
                PRS     "G11 addanimob d0="
                bsr     phex8
                bsr     pan
                move.l  an_c1-vars(a4),a0
                move.l  AC_BOB(a0),a0
                move.l  an_c2a-vars(a4),a1
                move.l  AC_BOB(a1),a1
                move.l  a1,BOB_BEFORE(a0)
                move.l  a0,BOB_AFTER(a1)
                moveq   #1,d6
.an:            clr.w   nlog-vars(a4)
                lea     akey-vars(a4),a0
                lea     rp-vars(a4),a1
                jsr     LVO_Animate(a6)
                PRS     "G11 animate"
                exg     d0,d6
                bsr     pdecs
                exg     d0,d6
                PRS     " d0="
                bsr     phex8
                bsr     pan
                addq.w  #1,d6
                cmp.w   #4,d6
                ble.s   .an
                bsr     forbid
                bsr     amem
                movem.l d0-d1,-(sp)
                move.l  a3,a0
                lea     rp-vars(a4),a1
                moveq   #1,d0
                jsr     LVO_FreeGBuffers(a6)
                bsr     amem
                movem.l (sp)+,d2-d3
                bsr     permit
                sub.l   d2,d0
                sub.l   d3,d1
                move.l  d0,d2
                move.l  d1,d3
                PRS     "G11 freegbuffers chip="
                bsr     pdec
                PRS     " other="
                move.l  d3,d0
                sub.l   d2,d0
                bsr     pdec
                bsr     nl
                movem.l (sp)+,d2-d7/a2-a3
                rts
; pdecs: d0.w in decimal, preserves d0/d1
pdecs:          movem.l d0-d1,-(sp)
                bsr     pdec
                movem.l (sp)+,d0-d1
                rts
; mkcomp(d0 TimeSet, d1 YTrans, d2 XTrans, d3 Flags, d4 comp name, d5 bob name) -> a0 = AnimComp with its Bob
; (16 x 3, depth 2). Names: comp d4, Bob d5, VSprite d5 - 32.
mkcomp:         movem.l d2-d6/a2-a3,-(sp)
                movem.l d0-d3,-(sp)
                lea     d_anim(pc),a0
                bsr     mkbob
                move.w  #6,VS_FLAGS(a2)
                move.w  #$0300,VS_PICK(a2)
                move.l  a2,a0
                move.w  d5,d0
                sub.w   #32,d0
                bsr     regn
                move.l  a3,a0
                move.w  d5,d0
                bsr     regn
                moveq   #38,d0
                bsr     newblk
                move.l  (sp)+,d0
                move.w  d0,AC_TIMESET(a0)
                move.l  (sp)+,d0
                move.w  d0,AC_YTRANS(a0)
                move.l  (sp)+,d0
                move.w  d0,AC_XTRANS(a0)
                move.l  (sp)+,d0
                move.w  d0,AC_FLAGS(a0)
                move.l  a3,AC_BOB(a0)
                move.l  an_ob-vars(a4),AC_HEADOB(a0)
                lea     lg1(pc),a1
                move.l  a1,AC_ROUT(a0)
                move.w  d4,d0
                bsr     regn
                movem.l (sp)+,d2-d6/a2-a3
                rts
; pan: animation state (2 lines)
pan:            movem.l d0-d1/a0-a3,-(sp)
                move.l  an_ob-vars(a4),a3
                PRS     " clk="
                move.l  AO_CLOCK(a3),d0
                bsr     pdec
                PRS     " an="
                move.w  AO_Y(a3),d0
                bsr     pdec
                moveq   #',',d1
                bsr     putc
                move.w  AO_X(a3),d0
                bsr     pdec
                PRS     " vel="
                move.w  AO_YVEL(a3),d0
                bsr     pdec
                moveq   #',',d1
                bsr     putc
                move.w  AO_XVEL(a3),d0
                bsr     pdec
                move.l  an_c1-vars(a4),a0
                PRS     " c1T="
                move.w  AC_TIMER(a0),d0
                bsr     pdec
                move.l  AC_BOB(a0),a1
                move.l  BOB_VS(a1),a1
                PRS     " c1="
                bsr     pyx
                PRS     " act="
                move.l  AC_NEXTC(a0),d0
                bsr     pptr
                tst.l   d0
                beq.s   .n
                move.l  d0,a0
                PRS     " T="
                move.w  AC_TIMER(a0),d0
                bsr     pdec
                move.l  AC_BOB(a0),a1
                move.l  BOB_VS(a1),a1
                PRS     " c2="
                bsr     pyx
.n:             bsr     nl
                PRS     "  c2a.bob bf="
                move.l  an_c2a-vars(a4),a0
                move.l  AC_BOB(a0),a1
                move.w  BOB_FLAGS(a1),d0
                bsr     phex4
                move.l  BOB_VS(a1),a1
                PRS     " yx="
                bsr     pyx
                PRS     " c1n="
                move.l  an_c1-vars(a4),a0
                move.l  AC_NEXTC(a0),d0
                bsr     pptr
                PRS     " c2b.pv="
                move.l  an_c2b-vars(a4),a0
                move.l  AC_PREVC(a0),d0
                bsr     pptr
                move.l  AC_BOB(a0),a1
                PRS     " z.After="
                move.l  BOB_AFTER(a1),d0
                bsr     pptr
                PRS     " x.Before="
                move.l  an_c1-vars(a4),a0
                move.l  AC_BOB(a0),a1
                move.l  BOB_BEFORE(a1),d0
                bsr     pptr
                PRS     " head="
                move.l  AO_HEADC(a3),d0
                bsr     pptr
                bsr     plist
                moveq   #1,d0
                bsr     plog
                bsr     nl
                movem.l (sp)+,d0-d1/a0-a3
                rts
; pyx(a1 = VSprite): "Y,X"
pyx:            move.w  VS_Y(a1),d0
                bsr     pdec
                moveq   #',',d1
                bsr     putc
                move.w  VS_X(a1),d0
                bra     pdec
forbid:         movem.l d0-d1/a0-a1/a6,-(sp)
                move.l  4.w,a6
                jsr     LVO_Forbid(a6)
                movem.l (sp)+,d0-d1/a0-a1/a6
                rts
permit:         movem.l d0-d1/a0-a1/a6,-(sp)
                move.l  4.w,a6
                jsr     LVO_Permit(a6)
                movem.l (sp)+,d0-d1/a0-a1/a6
                rts
; amem -> d0 = AvailMem(MEMF_CHIP), d1 = AvailMem(MEMF_ANY)
amem:           movem.l a0-a1/a6,-(sp)
                move.l  4.w,a6
                moveq   #0,d1
                jsr     LVO_AvailMem(a6)
                move.l  d0,-(sp)
                moveq   #2,d1
                jsr     LVO_AvailMem(a6)
                move.l  (sp)+,d1
                movem.l (sp)+,a0-a1/a6
                rts

; ===============================================================================================================
; G0 registers changed by each LVO (markers in D0-D7/A0-A5, arguments in their .fd registers)
g0:             movem.l d2-d7/a2-a3,-(sp)
                SETBM   32,8,1,zeros
                bsr     newgels
                move.l  gi+GI_HEAD-vars(a4),g0h-vars(a4)
                move.l  gi+GI_TAIL-vars(a4),g0t-vars(a4)
                lea     d_ring(pc),a0
                bsr     mkbob
                move.w  #1,VS_Y(a2)
                move.w  #1,VS_X(a2)
                move.w  #6,VS_FLAGS(a2)
                move.w  #$0100,VS_PICK(a2)
                move.l  a2,g0bvs-vars(a4)
                move.l  a3,g0bob-vars(a4)
                moveq   #60,d0
                bsr     newblk
                move.l  a0,a2
                move.l  #$00050005,VS_Y(a2)
                move.l  #$00010001,VS_HEIGHT(a2)
                move.w  #1,VS_DEPTH(a2)
                moveq   #8,d0
                bsr     newblk
                move.l  a0,VS_COLL(a2)
                move.l  a0,VS_IMAGE(a2)
                addq.l  #4,a0
                move.l  a0,VS_BORDER(a2)
                move.l  a2,g0vs-vars(a4)
                moveq   #42,d0
                bsr     newblk
                move.l  a0,g0ob-vars(a4)
                clr.l   akey-vars(a4)
                lea     g0tab(pc),a3
.lp:            tst.l   (a3)
                beq.s   .x
                bsr.s   g0one
                bra.s   .lp
.x:             movem.l (sp)+,d2-d7/a2-a3
                rts
; g0one(a3 = entry: name.l, lvo.w, nargs.w, nargs x (reg.w, kind.w, value.l)) -> a3 past the entry.
; kind 0 = value, 1 = vars + value, 2 = long stored at vars + value.
g0one:          lea     rin-vars(a4),a0
                moveq   #13,d0
                move.l  #$5A5A0000,d1
.f:             move.l  d1,(a0)+
                add.l   #$00010001,d1
                dbra    d0,.f
                PRS     "G0 "
                move.l  (a3)+,a0
                bsr     puts
                move.w  (a3)+,d0
                ext.l   d0
                add.l   a6,d0
                move.l  d0,tgt-vars(a4)
                move.w  (a3)+,d2
                subq.w  #1,d2
.a:             move.w  (a3)+,d0
                move.w  (a3)+,d1
                move.l  (a3)+,d3
                tst.w   d1
                beq.s   .set
                cmp.w   #1,d1
                bne.s   .k2
                add.l   a4,d3
                bra.s   .set
.k2:            move.l  0(a4,d3.l),d3
.set:           lsl.w   #2,d0
                lea     rin-vars(a4),a0
                move.l  d3,0(a0,d0.w)
                dbra    d2,.a
                movem.l d2-d7/a2-a5,-(sp)
                pea     .ret(pc)
                move.l  tgt(pc),-(sp)
                movem.l rin(pc),d0-d7/a0-a5
                rts
.ret:           movem.l d0-d7/a0-a5,rout
                movem.l (sp)+,d2-d7/a2-a5
                PRS     " changed:"
                lea     rin-vars(a4),a0
                lea     rout-vars(a4),a1
                lea     rnames(pc),a2
                moveq   #13,d2
.c:             cmpm.l  (a0)+,(a1)+
                beq.s   .s
                bsr     sp1
                move.b  (a2),d1
                bsr     putc
                move.b  1(a2),d1
                bsr     putc
.s:             addq.l  #2,a2
                dbra    d2,.c
                PRS     " d0="
                move.l  rout-vars(a4),d0
                bsr     phex8
                bra     nl

; ===============================================================================================================
; Common helpers
; newgels: heap reset, names reset, head 'H' + tail 'T' (60 bytes, cleared) and InitGels(head, tail, gi)
newgels:        movem.l d0-d1/a0-a2,-(sp)
                move.l  a5,d0
                add.l   #HEAP0,d0
                move.l  d0,heap-vars(a4)
                clr.w   nnames-vars(a4)
                moveq   #60,d0
                bsr     newblk
                move.l  a0,-(sp)
                moveq   #'H',d0
                bsr     regn
                moveq   #60,d0
                bsr     newblk
                move.l  a0,a1
                moveq   #'T',d0
                bsr     regn
                move.l  (sp)+,a0
                lea     gi-vars(a4),a2
                jsr     LVO_InitGels(a6)
                movem.l (sp)+,d0-d1/a0-a2
                rts
; newblk(d0.l = size) -> a0 = cleared block from the chip heap (long aligned). Clobbers d0/d1.
newblk:         move.l  heap-vars(a4),a0
                addq.l  #3,d0
                and.w   #$FFFC,d0
                move.l  a0,d1
                add.l   d0,d1
                move.l  d1,heap-vars(a4)
                lsr.l   #1,d0
                move.l  a0,d1
                bra.s   .s
.c:             clr.w   (a0)+
.s:             dbra    d0,.c
                move.l  d1,a0
                rts
; regn(a0 = address, d0 = character): names the address for pptr. Preserves everything.
regn:           movem.l d1/a1,-(sp)
                move.w  nnames-vars(a4),d1
                cmp.w   #40,d1
                bhs.s   .x
                mulu    #6,d1
                lea     names-vars(a4),a1
                add.l   d1,a1
                move.l  a0,(a1)+
                move.w  d0,(a1)
                addq.w  #1,nnames-vars(a4)
.x:             movem.l (sp)+,d1/a1
                rts
; pptr(d0): name, "0", hex4 (< $10000) or hex8. Preserves everything.
pptr:           movem.l d0-d2/a0,-(sp)
                tst.l   d0
                bne.s   .nz
                moveq   #'0',d1
                bsr     putc
                bra.s   .x
.nz:            lea     names-vars(a4),a0
                move.w  nnames-vars(a4),d2
                bra.s   .f
.l:             cmp.l   (a0)+,d0
                beq.s   .hit
                addq.l  #2,a0
.f:             dbra    d2,.l
                cmp.l   #$10000,d0
                bhs.s   .h8
                bsr     phex4
                bra.s   .x
.h8:            bsr     phex8
                bra.s   .x
.hit:           move.w  (a0),d1
                bsr     putc
.x:             movem.l (sp)+,d0-d2/a0
                rts
; setbm(d0.w width, d1.w height, d2.w depth, a0 = fill byte per plane): planes at chip+64 with 64-byte $A5
; guards before and after; rp = InitRastPort + BitMap + GelsInfo.
setbm:          movem.l d2-d4/a2-a3,-(sp)
                move.l  a0,a3
                move.w  d0,d3
                move.w  d1,d4
                lea     bm-vars(a4),a0
                moveq   #0,d0
                move.w  d2,d0
                moveq   #0,d1
                move.w  d3,d1
                move.w  d2,-(sp)
                moveq   #0,d2
                move.w  d4,d2
                jsr     LVO_InitBitMap(a6)
                move.w  (sp)+,d2
                move.w  bm-vars(a4),d3
                mulu    bm+2-vars(a4),d3
                move.l  a5,a0
                moveq   #63,d0
.g0:            move.b  #$A5,(a0)+
                dbra    d0,.g0
                lea     bm+8-vars(a4),a2
                subq.w  #1,d2
.pl:            move.l  a0,(a2)+
                move.b  (a3)+,d1
                move.w  d3,d0
                subq.w  #1,d0
.f:             move.b  d1,(a0)+
                dbra    d0,.f
                dbra    d2,.pl
                move.l  a0,gend-vars(a4)
                moveq   #63,d0
.g1:            move.b  #$A5,(a0)+
                dbra    d0,.g1
                lea     rp-vars(a4),a1
                jsr     LVO_InitRastPort(a6)
                lea     bm-vars(a4),a0
                move.l  a0,rp+RP_BM-vars(a4)
                lea     gi-vars(a4),a0
                move.l  a0,rp+RP_GI-vars(a4)
                movem.l (sp)+,d2-d4/a2-a3
                rts
; chk64(a0): Z = 1 if the 64 bytes are all $A5. Clobbers d0/a0.
chk64:          moveq   #63,d0
.l:             cmp.b   #$A5,(a0)+
                dbne    d0,.l
                rts
; pguard: " guard=ok|BAD" for the main BitMap planes, then a new line
pguard:         movem.l d0-d1/a0,-(sp)
                PRS     " guard="
                move.l  a5,a0
                bsr.s   chk64
                bne.s   .bad
                move.l  gend-vars(a4),a0
                bsr.s   chk64
                bne.s   .bad
                PRS     "ok"
                bra.s   .x
.bad:           PRS     "BAD"
.x:             bsr     nl
                movem.l (sp)+,d0-d1/a0
                rts
; addbob(a0 desc, d0 y, d1 x, d2 VSprite flags, d3 pick<<8|onoff) -> a2 VSprite, a3 Bob, AddBob done
addbob:         movem.l d0-d3,-(sp)
                bsr     mkbob
                movem.l (sp)+,d0-d3
                move.w  d0,VS_Y(a2)
                move.w  d1,VS_X(a2)
                move.w  d2,VS_FLAGS(a2)
                move.w  d3,VS_PICK(a2)
                move.l  a3,a0
                lea     rp-vars(a4),a1
                jmp     LVO_AddBob(a6)
; mkbob(a0 = desc: h, w, depth, bob flags, image words) -> a2 = VSprite, a3 = Bob, a0 past the desc.
; CollMask = ImageShadow = OR of the image planes; BorderLine = OR of the plane-0 rows; SaveBuffer sized for
; the current BitMap depth, followed by 16 guard bytes $A5. Preserves d2-d7.
mkbob:          movem.l d2-d7,-(sp)
                move.l  a0,dptr-vars(a4)
                moveq   #60,d0
                bsr     newblk
                move.l  a0,a2
                moveq   #32,d0
                bsr     newblk
                move.l  a0,a3
                move.l  a2,BOB_VS(a3)
                move.l  a3,VS_BOB(a2)
                move.l  dptr-vars(a4),a1
                move.w  (a1)+,VS_HEIGHT(a2)
                move.w  (a1)+,VS_WIDTH(a2)
                move.w  (a1)+,VS_DEPTH(a2)
                move.w  (a1)+,BOB_FLAGS(a3)
                move.l  a1,dptr-vars(a4)
                move.w  VS_HEIGHT(a2),d4
                mulu    VS_WIDTH(a2),d4
                move.w  VS_DEPTH(a2),d5
                mulu    d4,d5
                move.l  d5,d0
                add.l   d0,d0
                bsr     newblk
                move.l  a0,VS_IMAGE(a2)
                move.l  dptr-vars(a4),a1
                move.w  d5,d0
                subq.w  #1,d0
.cp:            move.w  (a1)+,(a0)+
                dbra    d0,.cp
                move.l  d4,d0
                add.l   d0,d0
                bsr     newblk
                move.l  a0,VS_COLL(a2)
                move.l  a0,BOB_SHADOW(a3)
                move.l  d4,d7
                add.l   d7,d7
                move.w  d4,d2
                subq.w  #1,d2
                moveq   #0,d6
.ci:            moveq   #0,d0
                move.l  VS_IMAGE(a2),a0
                add.l   d6,a0
                move.w  VS_DEPTH(a2),d3
                subq.w  #1,d3
.cq:            or.w    (a0),d0
                add.l   d7,a0
                dbra    d3,.cq
                move.l  VS_COLL(a2),a0
                move.w  d0,0(a0,d6.l)
                addq.l  #2,d6
                dbra    d2,.ci
                moveq   #0,d0
                move.w  VS_WIDTH(a2),d0
                add.l   d0,d0
                bsr     newblk
                move.l  a0,VS_BORDER(a2)
                move.w  VS_WIDTH(a2),d2
                subq.w  #1,d2
                moveq   #0,d6
                moveq   #0,d7
                move.w  VS_WIDTH(a2),d7
                add.l   d7,d7
.bc:            moveq   #0,d0
                move.l  VS_IMAGE(a2),a0
                add.l   d6,a0
                move.w  VS_HEIGHT(a2),d3
                subq.w  #1,d3
.br:            or.w    (a0),d0
                add.l   d7,a0
                dbra    d3,.br
                move.l  VS_BORDER(a2),a0
                move.w  d0,0(a0,d6.l)
                addq.l  #2,d6
                dbra    d2,.bc
                moveq   #0,d0
                move.b  bm+5-vars(a4),d0
                mulu    d4,d0
                add.l   d0,d0
                move.l  d0,d6
                add.l   #16,d0
                bsr     newblk
                move.l  a0,BOB_SAVE(a3)
                add.l   d6,a0
                moveq   #15,d0
.sg:            move.b  #$A5,(a0)+
                dbra    d0,.sg
                move.l  dptr-vars(a4),a0
                add.l   d5,a0
                add.l   d5,a0
                movem.l (sp)+,d2-d7
                rts
; pvs(a2): " vf= yx= old= dp= cp="
pvs:            movem.l d0-d1,-(sp)
                PRS     " vf="
                move.w  VS_FLAGS(a2),d0
                bsr     phex4
                PRS     " yx="
                move.w  VS_Y(a2),d0
                bsr     pdec
                moveq   #',',d1
                bsr     putc
                move.w  VS_X(a2),d0
                bsr     pdec
                PRS     " old="
                move.w  VS_OLDY(a2),d0
                bsr     pdec
                moveq   #',',d1
                bsr     putc
                move.w  VS_OLDX(a2),d0
                bsr     pdec
                PRS     " dp="
                move.l  VS_DPATH(a2),d0
                bsr     pptr
                PRS     " cp="
                move.l  VS_CPATH(a2),d0
                bsr     pptr
                movem.l (sp)+,d0-d1
                rts
; pbf(a3): " bf=<Bob flags>"
pbf:            move.l  d0,-(sp)
                PRS     " bf="
                move.w  BOB_FLAGS(a3),d0
                bsr     phex4
                move.l  (sp)+,d0
                rts
; psbuf(a3 = Bob, d0 = words): SaveBuffer words and its guard
psbuf:          movem.l d0-d2/a0,-(sp)
                PRS     " sb="
                move.l  BOB_SAVE(a3),a0
                move.w  d0,d2
                subq.w  #1,d2
.l:             move.w  (a0)+,d0
                bsr     phex4
                bsr     sp1
                dbra    d2,.l
                moveq   #15,d2
.g:             cmp.b   #$A5,(a0)+
                dbne    d2,.g
                bne.s   .bad
                PRS     "sg=ok"
                bra.s   .x
.bad:           PRS     "sg=BAD"
.x:             movem.l (sp)+,d0-d2/a0
                rts
; plist: " list=" names from head.Next to the tail
plist:          movem.l d0-d2/a0,-(sp)
                PRS     " list="
                move.l  gi+GI_HEAD-vars(a4),a0
                move.l  VS_NEXT(a0),a0
                moveq   #40,d2
.l:             tst.l   VS_NEXT(a0)
                beq.s   .x
                move.l  a0,d0
                bsr     pptr
                move.l  VS_NEXT(a0),a0
                subq.w  #1,d2
                bne.s   .l
                PRS     "..."
.x:             movem.l (sp)+,d0-d2/a0
                rts
; pchain: " chain=" DrawPath walk from the head
pchain:         movem.l d0-d2/a0,-(sp)
                PRS     " chain="
                move.l  gi+GI_HEAD-vars(a4),a0
                moveq   #12,d2
.l:             move.l  a0,d0
                bsr     pptr
                cmp.l   gi+GI_TAIL-vars(a4),a0
                beq.s   .x
                moveq   #'>',d1
                bsr     putc
                move.l  VS_DPATH(a0),d0
                beq.s   .z
                btst    #0,d0
                bne.s   .z
                move.l  d0,a0
                subq.w  #1,d2
                bne.s   .l
                PRS     "..."
                bra.s   .x
.z:             bsr     pptr
.x:             movem.l (sp)+,d0-d2/a0
                rts
; plog(d0 = arguments shown, 1 or 2): " log=" [i](a,b) entries of the routine log
plog:           movem.l d0-d3/a0,-(sp)
                move.w  d0,d3
                PRS     " log="
                move.w  nlog-vars(a4),d2
                bne.s   .some
                PRS     "-"
                bra.s   .x
.some:          lea     logb-vars(a4),a0
                subq.w  #1,d2
.l:             moveq   #'[',d1
                bsr     putc
                move.l  (a0)+,d0
                bsr     pdec
                PRS     "]("
                move.l  (a0)+,d0
                bsr     pptr
                cmp.w   #2,d3
                bne.s   .one
                moveq   #' ',d1
                bsr     putc
                move.l  (a0),d0
                bsr     pptr
.one:           addq.l  #4,a0
                moveq   #')',d1
                bsr     putc
                dbra    d2,.l
.x:             movem.l (sp)+,d0-d3/a0
                rts
; pwords(a0, d0.w count): " xxxx" each
pwords:         movem.l d0-d2/a0,-(sp)
                move.w  d0,d2
                subq.w  #1,d2
.l:             bsr     sp1
                move.w  (a0)+,d0
                bsr     phex4
                dbra    d2,.l
                movem.l (sp)+,d0-d2/a0
                rts
; pdump(a0 = BitMap, d2 y0, d3 y1, d4 x0, d5 x1): "y:" + one colour digit per pixel ('.' = 0)
pdump:          movem.l d2-d7/a2-a3,-(sp)
                move.l  a0,a2
.row:           move.w  d2,d0
                bsr     pdec
                moveq   #':',d1
                bsr     putc
                move.w  d4,d6
.col:           move.w  d2,d0
                mulu    (a2),d0
                moveq   #0,d1
                move.w  d6,d1
                lsr.w   #3,d1
                add.l   d1,d0
                move.l  d0,a1
                move.w  d6,d1
                not.w   d1
                and.w   #7,d1
                moveq   #0,d7
                moveq   #0,d0
                move.b  5(a2),d0
                lsl.w   #2,d0
                lea     8(a2,d0.w),a3
                lsr.w   #2,d0
                subq.w  #1,d0
.pl:            move.l  -(a3),a0
                add.w   d7,d7
                btst    d1,0(a0,a1.l)
                beq.s   .z
                addq.w  #1,d7
.z:             dbra    d0,.pl
                moveq   #'.',d1
                tst.w   d7
                beq.s   .pc
                moveq   #'0',d1
                add.w   d7,d1
.pc:            bsr     putc
                addq.w  #1,d6
                cmp.w   d5,d6
                ble.s   .col
                bsr     nl
                addq.w  #1,d2
                cmp.w   d3,d2
                ble.s   .row
                movem.l (sp)+,d2-d7/a2-a3
                rts

; --- logger routines: append (index, 4(sp), 8(sp)) to the log (C convention: scratch d0/d1/a0/a1)
lg0:            moveq   #0,d0
                bra.w   lgcom
lg1:            moveq   #1,d0
                bra.w   lgcom
lg2:            moveq   #2,d0
                bra.w   lgcom
lg3:            moveq   #3,d0
                bra.w   lgcom
lg4:            moveq   #4,d0
                bra.w   lgcom
lg5:            moveq   #5,d0
                bra.w   lgcom
lg6:            moveq   #6,d0
                bra.w   lgcom
lg7:            moveq   #7,d0
                bra.w   lgcom
lg8:            moveq   #8,d0
                bra.w   lgcom
lg9:            moveq   #9,d0
                bra.w   lgcom
lg10:           moveq   #10,d0
                bra.w   lgcom
lg11:           moveq   #11,d0
                bra.w   lgcom
lg12:           moveq   #12,d0
                bra.w   lgcom
lg13:           moveq   #13,d0
                bra.w   lgcom
lg14:           moveq   #14,d0
                bra.w   lgcom
lg15:           moveq   #15,d0
lgcom:          lea     nlog(pc),a0
                move.w  (a0),d1
                cmp.w   #40,d1
                bhs.s   .x
                addq.w  #1,(a0)
                mulu    #12,d1
                lea     logb(pc),a0
                add.l   d1,a0
                move.l  d0,(a0)+
                move.l  4(sp),(a0)+
                move.l  8(sp),(a0)
.x:             rts

; --- printing helpers
prsi:           movem.l d0-d1/a0,-(sp)
                move.l  12(sp),a0
                bsr     puts
                move.l  a0,d0
                addq.l  #1,d0
                and.b   #$FE,d0
                move.l  d0,12(sp)
                movem.l (sp)+,d0-d1/a0
                rts
nl:             move.l  d1,-(sp)
                moveq   #10,d1
                bsr.s   putc
                move.l  (sp)+,d1
                rts
sp1:            move.l  d1,-(sp)
                moveq   #' ',d1
                bsr.s   putc
                move.l  (sp)+,d1
                rts
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

; --- data
lgtab:          dc.l    lg0,lg1,lg2,lg3,lg4,lg5,lg6,lg7,lg8,lg9,lg10,lg11,lg12,lg13,lg14,lg15
; G1: (Y, X, name) in insertion order
g1tab:          dc.w    5,10,'A', 5,3,'B', 5,10,'C', 5,-2,'D', 4,0,'E', -3,10,'F', 5,32766,'G'
; G2: flags, h, w, depth, image
g2a:            dc.w    0,3,2,2
                dc.w    $8000,$0000, $0000,$0000, $0000,$0001
                dc.w    $0000,$00F0, $0000,$0F00, $0000,$0000
g2b:            dc.w    1,4,1,2
                dc.w    $8001,$4002, $2004,$1008, $0810,$0420, $0240,$0180
; Bob descriptors: h, w, depth, bob flags, image words
d_g3:           dc.w    4,1,2,0
                dc.w    $0180,$03C0,$07E0,$0FF0, $0000,$0180,$03C0,$0000
d_ring:         dc.w    4,1,1,0, $F000,$9000,$9000,$F000
d_rings:        dc.w    4,1,1,1, $F000,$9000,$9000,$F000
d_mask:         dc.w    4,1,3,0
                dc.w    $FF00,$FF00,$FF00,$FF00, 0,0,0,0, $FF00,$FF00,$FF00,$FF00
d_solid3:       dc.w    3,1,1,0, $FFFF,$FFFF,$FFFF
d_box:          dc.w    4,1,1,0, $FFFF,$8001,$8001,$FFFF
d_ff00:         dc.w    3,1,1,0, $FF00,$FF00,$FF00
d_anim:         dc.w    3,1,2,0, $F000,$F000,$F000, $0F00,$0F00,$0F00
g4xs:           dc.w    0,4,24,33,-1
g7tab:          dc.w    -2,-5, 6,25, 2,40, $7FFF
; G8 frames: BitMap (0 BM1 / 1 BM2), X
g8tab:          dc.w    0,2, 1,10, 0,20, 1,30, -1
; G9: y, x, h, colour set (1..3)
g9tab:          dc.w    10,50,5,1, 10,100,5,1, 10,150,5,2, 10,200,5,1, 10,250,5,3, 18,60,3,1, 17,300,3,2
g9tab2:         dc.w    10,50,5, 17,80,2, 18,110,2, 19,140,2
cset:           dc.w    $0F00,$00F0,$000F, $0FF0,$0F0F,$00FF, $0111,$0222,$0333
; G10 CollMasks (4 rows of 1 word unless stated)
t_r0:           dc.w    $8000,0,0,0
t_r2:           dc.w    0,0,$8000,0
t_r3:           dc.w    0,0,0,$8000
t_c1:           dc.w    0,$4000,0,0
t_c2:           dc.w    0,$2000,0,0
t_c11:          dc.w    0,$0010,0,0
t_c10:          dc.w    0,$0020,0,0
t_ff00:         dc.w    $FF00,$FF00,$FF00,$FF00
t_00ff:         dc.w    $00FF,$00FF,$00FF,$00FF
t_all:          dc.w    $FFFF,$FFFF,$FFFF,$FFFF,$FFFF,$FFFF,$FFFF,$FFFF
; G0 entries
g0tab:          dc.l    s_initgels
                dc.w    LVO_InitGels,3, 8,2
                dc.l    g0h-vars
                dc.w    9,2
                dc.l    g0t-vars
                dc.w    10,1
                dc.l    gi-vars
                dc.l    s_addbob
                dc.w    LVO_AddBob,2, 8,2
                dc.l    g0bob-vars
                dc.w    9,1
                dc.l    rp-vars
                dc.l    s_addvs
                dc.w    LVO_AddVSprite,2, 8,2
                dc.l    g0vs-vars
                dc.w    9,1
                dc.l    rp-vars
                dc.l    s_sort
                dc.w    LVO_SortGList,1, 9,1
                dc.l    rp-vars
                dc.l    s_initmasks
                dc.w    LVO_InitMasks,1, 8,2
                dc.l    g0bvs-vars
                dc.l    s_docoll
                dc.w    LVO_DoCollision,1, 9,1
                dc.l    rp-vars
                dc.l    s_draw
                dc.w    LVO_DrawGList,2, 9,1
                dc.l    rp-vars
                dc.w    8,1
                dc.l    vp-vars
                dc.l    s_remibob
                dc.w    LVO_RemIBob,3, 8,2
                dc.l    g0bob-vars
                dc.w    9,1
                dc.l    rp-vars
                dc.w    10,1
                dc.l    vp-vars
                dc.l    s_remvs
                dc.w    LVO_RemVSprite,1, 8,2
                dc.l    g0vs-vars
                dc.l    s_setcoll
                dc.w    LVO_SetCollision,3, 0,0
                dc.l    1
                dc.w    8,0
                dc.l    lg1
                dc.w    9,1
                dc.l    gi-vars
                dc.l    s_addanim
                dc.w    LVO_AddAnimOb,3, 8,2
                dc.l    g0ob-vars
                dc.w    9,1
                dc.l    akey-vars
                dc.w    10,1
                dc.l    rp-vars
                dc.l    s_animate
                dc.w    LVO_Animate,2, 8,1
                dc.l    akey-vars
                dc.w    9,1
                dc.l    rp-vars
                dc.l    s_getg
                dc.w    LVO_GetGBuffers,3, 8,2
                dc.l    g0ob-vars
                dc.w    9,1
                dc.l    rp-vars
                dc.w    0,0
                dc.l    1
                dc.l    s_initgm
                dc.w    LVO_InitGMasks,1, 8,2
                dc.l    g0ob-vars
                dc.l    s_freeg
                dc.w    LVO_FreeGBuffers,3, 8,2
                dc.l    g0ob-vars
                dc.w    9,1
                dc.l    rp-vars
                dc.w    0,0
                dc.l    1
                dc.l    0
rnames:         dc.b    "D0D1D2D3D4D5D6D7A0A1A2A3A4A5"
zeros:          dc.b    0,0,0,0
f_33_0f:        dc.b    $33,$0F
f_0ff0:         dc.b    0,$FF,0
f_aa:           dc.b    $AA
s_initgels:     dc.b    "InitGels",0
s_addbob:       dc.b    "AddBob",0
s_addvs:        dc.b    "AddVSprite",0
s_sort:         dc.b    "SortGList",0
s_initmasks:    dc.b    "InitMasks",0
s_docoll:       dc.b    "DoCollision",0
s_draw:         dc.b    "DrawGList",0
s_remibob:      dc.b    "RemIBob",0
s_remvs:        dc.b    "RemVSprite",0
s_setcoll:      dc.b    "SetCollision",0
s_addanim:      dc.b    "AddAnimOb",0
s_animate:      dc.b    "Animate",0
s_getg:         dc.b    "GetGBuffers",0
s_initgm:       dc.b    "InitGMasks",0
s_freeg:        dc.b    "FreeGBuffers",0
gfxname:        dc.b    "graphics.library",0
m_start:        dc.b    10,"GEL debut",10,0
m_end:          dc.b    "GEL fin",10,0
                even

vars:
gfxb:           dc.l    0
heap:           dc.l    0
gend:           dc.l    0
tgt:            dc.l    0
dptr:           dc.l    0
vimg:           dc.l    0
akey:           dc.l    0
g0h:            dc.l    0
g0t:            dc.l    0
g0bob:          dc.l    0
g0bvs:          dc.l    0
g0vs:           dc.l    0
g0ob:           dc.l    0
gav:            dc.l    0
gab:            dc.l    0
gbv:            dc.l    0
gbb:            dc.l    0
an_ob:          dc.l    0
an_c1:          dc.l    0
an_c2a:         dc.l    0
an_c2b:         dc.l    0
g1v:            ds.l    7
vsl:            ds.l    8
nnames:         dc.w    0
nlog:           dc.w    0
bm:             ds.b    40
bm2:            ds.b    40
rp:             ds.b    100
gi:             ds.b    40
vp:             ds.b    40
coll:           ds.b    64
collg:          ds.b    16
nline:          ds.b    16
lcol:           ds.b    32
names:          ds.b    240
logb:           ds.b    480
rin:            ds.l    14
rout:           ds.l    14
