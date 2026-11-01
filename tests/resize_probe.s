; tests/resize_probe.s - HUNK test executable (TEST ASSET, NOT ROM code).
; Black-box probe of resizing/moving in layers.library and intuition (analysis track,
; docs/analysis/layers-v34.md §4/§5.6/§5.7/§6 and docs/analysis/intuition-gzz-v34.md).
; Run from a floppy's startup-sequence (tests/resize_probe.sh). Output on the direct serial port.
; Assembly: vasmm68k_mot -Fhunkexe -kick1hunks -nosym -o build/resize_probe tests/resize_probe.s
; Original author code; public structures (graphics/clip.h, layers.h, gfx.h, intuition.h from 1.3).
;
; Test pattern: pen(x,y) = 1 + (((x>>3) ^ (y>>3)) & 1), (x,y) relative to the origin of the drawn
; layer/window (8x8 checker of pens 1 and 2). Background of the private screen = pen 3.
; Grid dump "G x0 y0 x1 y1 nx ny ox oy same" then lines "R ya-yb <runs>" (decimal, screen coordinates,
; consecutive identical rows merged). A run is a class letter followed by its length in pixels:
;   #  pixel equals the pattern relative to the CURRENT origin (nx,ny)
;   o  pixel equals the pattern relative to the OLD origin (ox,oy) only (MoveLayer)
;   b  both (only when the origins differ)
;   .  pixel is 0
;   x y z  pen 1, 2, 3 not matching the pattern

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018
SERPER   EQU $DFF032
SCRW     EQU 320
SCRH     EQU 200
PLSZ     EQU SCRW/8*SCRH            ; 8000 bytes per plane
O_P0     EQU 0
O_P1     EQU PLSZ
O_SB0    EQU 2*PLSZ
O_SB1    EQU 3*PLSZ
CHIPSZ   EQU 4*PLSZ

; layers.library
L_CreateUpfront EQU -36
L_Move          EQU -60
L_Size          EQU -66
L_Delete        EQU -90
L_NewLayerInfo  EQU -144
L_DisposeLayerInfo EQU -150
; graphics.library
G_InitRastPort  EQU -198
G_RectFill      EQU -306
G_ReadPixel     EQU -318
G_SetAPen       EQU -342
G_InitBitMap    EQU -390
; intuition.library
I_CloseWindow   EQU -72
I_OpenWindow    EQU -204
I_SizeWindow    EQU -288
I_BeginRefresh  EQU -354
I_EndRefresh    EQU -366

LAY     macro
        move.l  layb-vars(a4),a6
        jsr     \1(a6)
        endm
GFX     macro
        move.l  gfxb-vars(a4),a6
        jsr     \1(a6)
        endm
INT     macro
        move.l  intb-vars(a4),a6
        jsr     \1(a6)
        endm
MSG     macro
        lea     \1(pc),a0
        bsr     puts
        endm
; GRIDL x0,y0,x1,y1,nx,ny,ox,oy : grid of the private screen
GRIDL   macro
        lea     scrrp-vars(a4),a0
        move.l  a0,grp-vars(a4)
        move.w  #\1,gx0-vars(a4)
        move.w  #\2,gy0-vars(a4)
        move.w  #\3,gx1-vars(a4)
        move.w  #\4,gy1-vars(a4)
        move.w  #\5,gnx-vars(a4)
        move.w  #\6,gny-vars(a4)
        move.w  #\7,gox-vars(a4)
        move.w  #\8,goy-vars(a4)
        bsr     grid
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
                beq     .out
                lea     intname(pc),a1
                moveq   #0,d0
                jsr     -552(a6)
                move.l  d0,intb-vars(a4)
                beq     .out
                lea     dosname(pc),a1
                moveq   #0,d0
                jsr     -552(a6)
                move.l  d0,dosb-vars(a4)
                beq     .out
                move.l  #CHIPSZ,d0
                move.l  #$10002,d1
                jsr     -198(a6)
                move.l  d0,chip-vars(a4)
                beq     .out
                move.l  d0,a5
                MSG     m_start
                lea     scrbm-vars(a4),a0
                moveq   #2,d0
                move.l  #SCRW,d1
                move.l  #SCRH,d2
                GFX     G_InitBitMap
                lea     scrbm-vars(a4),a0
                lea     O_P0(a5),a1
                move.l  a1,8(a0)
                lea     O_P1(a5),a1
                move.l  a1,12(a0)
                lea     scrrp-vars(a4),a1
                GFX     G_InitRastPort
                lea     scrrp-vars(a4),a1
                lea     scrbm-vars(a4),a0
                move.l  a0,4(a1)
                lea     sbm-vars(a4),a0
                lea     nw2+34(pc),a1
                move.l  a0,(a1)
                lea     nw3+34(pc),a1
                move.l  a0,(a1)
                LAY     L_NewLayerInfo
                move.l  d0,li-vars(a4)
                beq     .out

; ---------- T1a : B SIMPLE (60,30)-(159,89) alone, SizeLayer(+20,+10) ----------
                MSG     m_t1a
                bsr     newB
                GRIDL   56,26,183,103,60,30,60,30
                move.l  lB-vars(a4),a1
                moveq   #20,d0
                moveq   #10,d1
                bsr     dosize
                GRIDL   56,26,183,103,60,30,60,30
                bsr     delB
; ---------- T1b : same, SizeLayer(-30,-15) ----------
                MSG     m_t1b
                bsr     newB
                move.l  lB-vars(a4),a1
                moveq   #-30,d0
                moveq   #-15,d1
                bsr     dosize
                GRIDL   56,26,183,103,60,30,60,30
                bsr     delB
; ---------- T2a : B SIMPLE + C SMART (130,60)-(199,109) in front, SizeLayer(B,+20,+10) ----------
                MSG     m_t2a
                bsr     newB
                bsr     newC
                bsr     dumpB
                GRIDL   56,26,203,113,60,30,60,30
                move.l  lB-vars(a4),a1
                moveq   #20,d0
                moveq   #10,d1
                bsr     dosize
                bsr     dumpC
                GRIDL   56,26,203,113,60,30,60,30
                bsr     delC
                bsr     delB
; ---------- T2b : same, SizeLayer(B,-30,-15) ----------
                MSG     m_t2b
                bsr     newB
                bsr     newC
                move.l  lB-vars(a4),a1
                moveq   #-30,d0
                moveq   #-15,d1
                bsr     dosize
                bsr     dumpC
                GRIDL   56,26,203,113,60,30,60,30
                bsr     delC
                bsr     delB
; ---------- T3 : B SIMPLE alone, MoveLayer(+8,+4) ----------
                MSG     m_t3
                bsr     newB
                move.l  li-vars(a4),a0
                move.l  lB-vars(a4),a1
                moveq   #8,d0
                moveq   #4,d1
                LAY     L_Move
                bsr     okline
                bsr     dumpB
                GRIDL   56,26,175,97,68,34,60,30
                bsr     delB
                move.l  li-vars(a4),a0
                LAY     L_DisposeLayerInfo

; ---------- T4 : intuition, SIMPLE_REFRESH non-GZZ window ----------
                MSG     m_t4
                lea     nw1(pc),a0
                bsr     openw
                beq     .t5
                bsr     winfo
                bsr     wfill
                move.l  #40,d0
                moveq   #20,d1
                bsr     wsize
                move.l  win-vars(a4),a0
                INT     I_BeginRefresh
                move.l  win-vars(a4),a0
                moveq   #1,d0
                INT     I_EndRefresh
                MSG     m_after
                bsr     dumpWL
                bsr     wfill
                moveq   #-60,d0
                moveq   #-30,d1
                bsr     wsize
                bsr     closew
; ---------- T5 : GIMMEZEROZERO | SUPER_BITMAP, BitMap 320x200x2 ----------
.t5:            MSG     m_t5
                bsr     sbinit
                lea     nw2(pc),a0
                bsr     openw
                beq     .t6
                bsr     winfo
                bsr     wgrid
                move.l  #40,d0
                moveq   #20,d1
                bsr     wsize
                bsr     sgrid
                bsr     closew
; ---------- T6 : SUPER_BITMAP without GIMMEZEROZERO ----------
.t6:            MSG     m_t6
                bsr     sbinit
                lea     nw3(pc),a0
                bsr     openw
                beq     .t7
                bsr     winfo
                bsr     wgrid
                bsr     sgrid
                move.l  #40,d0
                moveq   #20,d1
                bsr     wsize
                bsr     sgrid
                move.l  win-vars(a4),a0
                INT     I_BeginRefresh
                move.l  win-vars(a4),a0
                moveq   #1,d0
                INT     I_EndRefresh
                MSG     m_after
                bsr     collect
                bsr     dumpWL
                bsr     wgrid
                bsr     sgrid
                bsr     closew
; ---------- T7 : control, SMART_REFRESH window, IDCMP NEWSIZE|REFRESHWINDOW then NEWSIZE alone ----------
.t7:            MSG     m_t7
                lea     nw4(pc),a0
                bsr     wctl
                lea     nw5(pc),a0
                bsr     wctl
.end:           MSG     m_end
                move.l  4.w,a6
                move.l  chip-vars(a4),a1
                move.l  #CHIPSZ,d0
                jsr     -210(a6)
.out:           movem.l (sp)+,d2-d7/a2-a6
                moveq   #0,d0
                rts

; ======================= layers part =======================
; --- clears the private screen to pen 3, creates B SIMPLE (60,30)-(159,89), draws the pattern, dumps B
newB:           lea     O_P0(a5),a0
                move.w  #2*PLSZ/4-1,d0
.ff:            move.l  #-1,(a0)+
                dbra    d0,.ff
                move.l  li-vars(a4),a0
                lea     scrbm-vars(a4),a1
                moveq   #60,d0
                moveq   #30,d1
                move.l  #159,d2
                moveq   #89,d3
                moveq   #1,d4
                sub.l   a2,a2
                LAY     L_CreateUpfront
                move.l  d0,lB-vars(a4)
                bsr     okline
                move.l  d0,a0
                bsr     lfill
                bra     dumpB

; --- C SMART (130,60)-(199,109) in front, filled with pen 3
newC:           move.l  li-vars(a4),a0
                lea     scrbm-vars(a4),a1
                move.l  #130,d0
                moveq   #60,d1
                move.l  #199,d2
                moveq   #109,d3
                moveq   #2,d4
                sub.l   a2,a2
                LAY     L_CreateUpfront
                move.l  d0,lC-vars(a4)
                bsr     okline
                move.l  d0,a0
                move.l  12(a0),a1
                moveq   #3,d0
                GFX     G_SetAPen
                move.l  lC-vars(a4),a0
                move.l  12(a0),a1
                moveq   #0,d0
                moveq   #0,d1
                moveq   #69,d2
                moveq   #49,d3
                GFX     G_RectFill
                rts

; --- SizeLayer(li, a1, d0, d1), result line, dump of B
dosize:         move.l  li-vars(a4),a0
                LAY     L_Size
                bsr     okline
                bra     dumpB

delB:           move.l  li-vars(a4),a0
                move.l  lB-vars(a4),a1
                LAY     L_Delete
                clr.l   lB-vars(a4)
                rts
delC:           move.l  li-vars(a4),a0
                move.l  lC-vars(a4),a1
                LAY     L_Delete
                clr.l   lC-vars(a4)
                rts

dumpB:          move.l  lB-vars(a4),a2
                moveq   #'B',d6
                bra     dumpL
dumpC:          move.l  lC-vars(a4),a2
                moveq   #'C',d6
                bra     dumpL

; --- pattern over the whole layer a0 (layer coordinates)
lfill:          move.l  12(a0),fr-vars(a4)
                clr.w   fx0-vars(a4)
                clr.w   fy0-vars(a4)
                move.w  $14(a0),d0
                sub.w   $10(a0),d0
                move.w  d0,fx1-vars(a4)
                move.w  $16(a0),d0
                sub.w   $12(a0),d0
                move.w  d0,fy1-vars(a4)
                bra     pfill

; ======================= intuition part =======================
; --- OpenWindow(a0); Z set on failure; prepares wrp on the screen BitMap; drains the opening messages
openw:          INT     I_OpenWindow
                move.l  d0,win-vars(a4)
                bsr     okline
                tst.l   d0
                beq.s   .r
                move.l  d0,a0
                move.l  8(a0),wold-vars(a4)
                move.l  $7C(a0),lW-vars(a4)
                clr.l   lO-vars(a4)
                move.l  $3A(a0),d0
                beq.s   .nb
                move.l  d0,a1
                move.l  (a1),lO-vars(a4)
.nb:            lea     wrp-vars(a4),a1
                GFX     G_InitRastPort
                move.l  win-vars(a4),a0
                move.l  $2E(a0),a0
                lea     $B8(a0),a0
                lea     wrp-vars(a4),a1
                move.l  a0,4(a1)
                MSG     m_open
                bsr     collect
                moveq   #1,d0
.r:             rts

closew:         bsr     collect
                move.l  win-vars(a4),a0
                INT     I_CloseWindow
                clr.l   lW-vars(a4)
                clr.l   lO-vars(a4)
                rts

; --- window: "W L T Wd Ht BL BT BR BB IDCMPFlags", then RPort->Layer, its Flags and SuperBitMap, supplied BitMap,
;     WLayer, BorderRPort, BorderRPort->Layer and its Flags; then dumps of the layers
winfo:          move.l  win-vars(a4),a3
                moveq   #'W',d1
                bsr     putc
                bsr     sp1
                move.l  4(a3),d0
                bsr     phex8
                bsr     sp1
                move.l  8(a3),d0
                bsr     phex8
                bsr     sp1
                move.l  $36(a3),d0
                bsr     phex8
                bsr     sp1
                move.l  $52(a3),d0
                bsr     phex8
                bsr     nl
                MSG     m_rp
                move.l  $32(a3),a0
                move.l  (a0),a2
                move.l  a2,d0
                bsr     phex8
                bsr     sp1
                move.w  $1E(a2),d0
                bsr     phex4
                bsr     sp1
                move.l  $20(a2),d0
                bsr     phex8
                bsr     sp1
                lea     sbm-vars(a4),a0
                move.l  a0,d0
                bsr     phex8
                bsr     nl
                MSG     m_wl
                move.l  $7C(a3),d0
                bsr     phex8
                bsr     sp1
                move.l  $3A(a3),d0
                bsr     phex8
                move.l  $3A(a3),d0
                beq.s   .nb
                bsr     sp1
                move.l  d0,a0
                move.l  (a0),a2
                move.l  a2,d0
                bsr     phex8
                bsr     sp1
                move.w  $1E(a2),d0
                bsr     phex4
.nb:            bsr     nl
dumpWL:         move.l  lW-vars(a4),a2
                moveq   #'W',d6
                bsr     dumpL
                move.l  lO-vars(a4),d0
                beq.s   .r
                move.l  d0,a2
                moveq   #'O',d6
                bsr     dumpL
.r:             rts

; --- pattern over the interior of the window (RPort coordinates)
wfill:          move.l  win-vars(a4),a3
                move.l  $32(a3),fr-vars(a4)
                moveq   #0,d0
                move.b  $36(a3),d0
                move.w  d0,fx0-vars(a4)
                move.b  $37(a3),d0
                move.w  d0,fy0-vars(a4)
                move.w  8(a3),d0
                move.b  $38(a3),d1
                ext.w   d1
                sub.w   d1,d0
                subq.w  #1,d0
                move.w  d0,fx1-vars(a4)
                move.w  $A(a3),d0
                move.b  $39(a3),d1
                ext.w   d1
                sub.w   d1,d0
                subq.w  #1,d0
                move.w  d0,fy1-vars(a4)
                bra     pfill

; --- SizeWindow(d0,d1): remembers the old size, collects IDCMP for ~2 s, dumps window + layers + grid
wsize:          move.l  win-vars(a4),a0
                move.l  8(a0),wold-vars(a4)
                INT     I_SizeWindow
                MSG     m_size
                bsr     collect
                bsr     winfo
                bra     wgrid

; --- grid over the window's old and new rectangles, margin 2; origin = RPort->Layer bounds
wgrid:          move.l  win-vars(a4),a3
                lea     wrp-vars(a4),a0
                move.l  a0,grp-vars(a4)
                move.w  4(a3),d0
                subq.w  #2,d0
                move.w  d0,gx0-vars(a4)
                move.w  6(a3),d0
                subq.w  #2,d0
                move.w  d0,gy0-vars(a4)
                move.w  8(a3),d0
                cmp.w   wold-vars(a4),d0
                bge.s   .w
                move.w  wold-vars(a4),d0
.w:             add.w   4(a3),d0
                addq.w  #1,d0
                move.w  d0,gx1-vars(a4)
                move.w  $A(a3),d0
                cmp.w   wold+2-vars(a4),d0
                bge.s   .h
                move.w  wold+2-vars(a4),d0
.h:             add.w   6(a3),d0
                addq.w  #1,d0
                move.w  d0,gy1-vars(a4)
                move.l  $32(a3),a0
                move.l  (a0),a0
                move.w  $10(a0),gnx-vars(a4)
                move.w  $12(a0),gny-vars(a4)
                move.w  $10(a0),gox-vars(a4)
                move.w  $12(a0),goy-vars(a4)
                bra     grid

; --- control: OpenWindow(a0), SizeWindow(+16,+8), messages, window line, CloseWindow
wctl:           bsr     openw
                beq.s   .r
                move.l  win-vars(a4),a0
                moveq   #16,d0
                moveq   #8,d1
                INT     I_SizeWindow
                MSG     m_size
                bsr     collect
                bsr     collect
                move.l  win-vars(a4),a3
                moveq   #'W',d1
                bsr     putc
                bsr     sp1
                move.l  8(a3),d0
                bsr     phex8
                bsr     sp1
                move.l  $52(a3),d0
                bsr     phex8
                bsr     nl
                bra     closew
.r:             rts

; --- grid of the SuperBitMap itself, (0,0)-(241,101), origin (0,0)
sgrid:          MSG     m_super
                lea     sbrp-vars(a4),a1
                GFX     G_InitRastPort
                lea     sbrp-vars(a4),a1
                lea     sbm-vars(a4),a0
                move.l  a0,4(a1)
                move.l  a1,grp-vars(a4)
                clr.l   gx0-vars(a4)
                move.l  #(241<<16)|101,gx1-vars(a4)
                clr.l   gnx-vars(a4)
                clr.l   gox-vars(a4)
                bra     grid

; --- 50 x (Delay 2 ticks, drains UserPort): one line "M class code" per message
collect:        movem.l d2/d7/a2,-(sp)
                moveq   #49,d7
.l:             moveq   #2,d1
                move.l  dosb-vars(a4),a6
                jsr     -198(a6)
.g:             move.l  win-vars(a4),a0
                move.l  $56(a0),a0
                move.l  4.w,a6
                jsr     -372(a6)
                tst.l   d0
                beq.s   .n
                move.l  d0,a2
                moveq   #'M',d1
                bsr     putc
                bsr     sp1
                move.l  20(a2),d0
                bsr     phex8
                bsr     sp1
                move.w  24(a2),d0
                bsr     phex4
                bsr     nl
                move.l  a2,a1
                move.l  4.w,a6
                jsr     -378(a6)
                bra.s   .g
.n:             dbra    d7,.l
                movem.l (sp)+,d2/d7/a2
                rts

; --- SuperBitMap 320x200x2 (planes O_SB0/O_SB1) filled with the pattern by the CPU
sbinit:         lea     sbm-vars(a4),a0
                moveq   #2,d0
                move.l  #SCRW,d1
                move.l  #SCRH,d2
                GFX     G_InitBitMap
                lea     sbm-vars(a4),a0
                lea     O_SB0(a5),a1
                move.l  a1,8(a0)
                lea     O_SB1(a5),a2
                move.l  a2,12(a0)
                moveq   #0,d1                   ; y
.y:             moveq   #0,d2                   ; byte column
.x:             move.w  d1,d0
                lsr.w   #3,d0
                eor.w   d2,d0
                btst    #0,d0
                bne.s   .p2
                move.b  #$FF,(a1)+
                clr.b   (a2)+
                bra.s   .nx
.p2:            clr.b   (a1)+
                move.b  #$FF,(a2)+
.nx:            addq.w  #1,d2
                cmp.w   #SCRW/8,d2
                blo.s   .x
                addq.w  #1,d1
                cmp.w   #SCRH,d1
                blo.s   .y
                rts

; ======================= common =======================
; --- checker pattern over [fx0..fx1]x[fy0..fy1] in the RastPort fr
pfill:          movem.l d2-d7,-(sp)
                move.w  fy0-vars(a4),d5
                lsr.w   #3,d5
.r:             move.w  fx0-vars(a4),d4
                lsr.w   #3,d4
.c:             move.w  d4,d0
                eor.w   d5,d0
                and.l   #1,d0
                addq.l  #1,d0
                move.l  fr-vars(a4),a1
                GFX     G_SetAPen
                move.w  d4,d0
                lsl.w   #3,d0
                cmp.w   fx0-vars(a4),d0
                bge.s   .xa
                move.w  fx0-vars(a4),d0
.xa:            move.w  d5,d1
                lsl.w   #3,d1
                cmp.w   fy0-vars(a4),d1
                bge.s   .ya
                move.w  fy0-vars(a4),d1
.ya:            move.w  d4,d2
                lsl.w   #3,d2
                addq.w  #7,d2
                cmp.w   fx1-vars(a4),d2
                ble.s   .xb
                move.w  fx1-vars(a4),d2
.xb:            move.w  d5,d3
                lsl.w   #3,d3
                addq.w  #7,d3
                cmp.w   fy1-vars(a4),d3
                ble.s   .yb
                move.w  fy1-vars(a4),d3
.yb:            ext.l   d0
                ext.l   d1
                ext.l   d2
                ext.l   d3
                move.l  fr-vars(a4),a1
                GFX     G_RectFill
                addq.w  #1,d4
                move.w  fx1-vars(a4),d0
                lsr.w   #3,d0
                cmp.w   d0,d4
                ble.s   .c
                addq.w  #1,d5
                move.w  fy1-vars(a4),d0
                lsr.w   #3,d0
                cmp.w   d0,d5
                ble     .r
                movem.l (sp)+,d2-d7
                rts

; --- classified grid (see header)
grid:           movem.l d2-d7/a2-a3,-(sp)
                moveq   #'G',d1
                bsr     putc
                lea     gx0-vars(a4),a3
                moveq   #7,d2
.hd:            bsr     sp1
                move.w  (a3)+,d0
                bsr     pdec
                dbra    d2,.hd
                bsr     nl
                clr.w   ghave-vars(a4)
                move.w  gy0-vars(a4),d5
.row:           lea     rowbuf-vars(a4),a2
                moveq   #0,d6
                moveq   #0,d7
                move.w  gx0-vars(a4),d4
.px:            bsr     classify
                cmp.b   d6,d0
                bne.s   .new
                addq.w  #1,d7
                bra.s   .nx
.new:           tst.b   d6
                beq.s   .st
                move.b  d0,-(sp)
                bsr     emit
                move.b  (sp)+,d0
.st:            move.b  d0,d6
                moveq   #1,d7
.nx:            addq.w  #1,d4
                cmp.w   gx1-vars(a4),d4
                ble.s   .px
                bsr     emit
                clr.b   (a2)
                tst.w   ghave-vars(a4)
                beq.s   .ng
                lea     rowbuf-vars(a4),a0
                lea     prevbuf-vars(a4),a1
                bsr     streq
                beq.s   .same
                move.w  d5,d0
                subq.w  #1,d0
                bsr     prgrp
.ng:            lea     rowbuf-vars(a4),a0
                lea     prevbuf-vars(a4),a1
.cp:            move.b  (a0)+,(a1)+
                bne.s   .cp
                move.w  d5,gya-vars(a4)
                move.w  #1,ghave-vars(a4)
.same:          addq.w  #1,d5
                cmp.w   gy1-vars(a4),d5
                ble     .row
                move.w  gy1-vars(a4),d0
                bsr     prgrp
                movem.l (sp)+,d2-d7/a2-a3
                rts

; --- pixel (d4,d5) of grp -> class letter in d0
classify:       move.l  grp-vars(a4),a1
                move.w  d4,d0
                ext.l   d0
                move.w  d5,d1
                ext.l   d1
                GFX     G_ReadPixel
                move.l  d0,d2
                bmi.s   .q
                bne.s   .nz
                moveq   #'.',d0
                rts
.q:             moveq   #'?',d0
                rts
.nz:            moveq   #0,d3
                move.w  d4,d0
                sub.w   gnx-vars(a4),d0
                move.w  d5,d1
                sub.w   gny-vars(a4),d1
                bsr.s   pat
                cmp.w   d0,d2
                bne.s   .n1
                bset    #0,d3
.n1:            move.w  gnx-vars(a4),d0
                cmp.w   gox-vars(a4),d0
                bne.s   .old
                move.w  gny-vars(a4),d0
                cmp.w   goy-vars(a4),d0
                beq.s   .m
.old:           move.w  d4,d0
                sub.w   gox-vars(a4),d0
                move.w  d5,d1
                sub.w   goy-vars(a4),d1
                bsr.s   pat
                cmp.w   d0,d2
                bne.s   .m
                bset    #1,d3
.m:             tst.w   d3
                beq.s   .v
                move.b  ctab(pc,d3.w),d0
                rts
.v:             move.b  vtab(pc,d2.w),d0
                rts
ctab:           dc.b    0,'#','o','b'
vtab:           dc.b    '.','x','y','z'

; --- pattern value at (d0,d1) relative, -1 if negative
pat:            tst.w   d0
                bmi.s   .no
                tst.w   d1
                bmi.s   .no
                lsr.w   #3,d0
                lsr.w   #3,d1
                eor.w   d1,d0
                and.w   #1,d0
                addq.w  #1,d0
                rts
.no:            moveq   #-1,d0
                rts

; --- run (d6 letter, d7 length) appended at a2, truncated with '~'
emit:           lea     rowend-vars(a4),a0
                cmp.l   a0,a2
                bhs.s   .full
                move.b  d6,(a2)+
                move.w  d7,d0
                bra     decbuf
.full:          move.l  a0,a2
                move.b  #'~',(a2)+
                rts

; --- "R ya-yb runs" from prevbuf, d0 = yb
prgrp:          move.w  d0,-(sp)
                moveq   #'R',d1
                bsr     putc
                bsr     sp1
                move.w  gya-vars(a4),d0
                bsr     pdec
                moveq   #'-',d1
                bsr     putc
                move.w  (sp)+,d0
                bsr     pdec
                bsr     sp1
                lea     prevbuf-vars(a4),a0
                bsr     puts
                bra     nl

streq:          cmpm.b  (a0)+,(a1)+
                bne.s   .r
                tst.b   -1(a0)
                bne.s   streq
.r:             rts

; --- unsigned decimal of d0.w into (a2)+
decbuf:         movem.l d0-d1,-(sp)
                moveq   #0,d1
                and.l   #$FFFF,d0
.l:             divu    #10,d0
                swap    d0
                add.b   #'0',d0
                move.w  d0,-(sp)
                addq.w  #1,d1
                clr.w   d0
                swap    d0
                tst.w   d0
                bne.s   .l
.o:             move.w  (sp)+,d0
                move.b  d0,(a2)+
                subq.w  #1,d1
                bne.s   .o
                movem.l (sp)+,d0-d1
                rts

; --- signed decimal of d0.w on the serial port
pdec:           movem.l d0-d1/a0/a2,-(sp)
                lea     dtmp-vars(a4),a2
                tst.w   d0
                bpl.s   .p
                move.b  #'-',(a2)+
                neg.w   d0
.p:             bsr     decbuf
                clr.b   (a2)
                lea     dtmp-vars(a4),a0
                bsr     puts
                movem.l (sp)+,d0-d1/a0/a2
                rts

; --- line "= d0"; preserves d0
okline:         move.l  d0,-(sp)
                moveq   #'=',d1
                bsr     putc
                bsr     phex8
                bsr     nl
                move.l  (sp)+,d0
                rts

; --- layer a2, tag d6: "L<tag> Flags priority bounds Scroll front back _cliprects", C/S lists, D
dumpL:          move.l  a2,d0
                beq     .nd
                moveq   #'L',d1
                bsr     putc
                move.b  d6,d1
                bsr     putc
                bsr     sp1
                move.w  $1E(a2),d0
                bsr     phex4
                bsr     sp1
                move.w  $1C(a2),d0
                bsr     phex4
                bsr     sp1
                move.l  $10(a2),d0
                bsr     phex8
                move.l  $14(a2),d0
                bsr     phex8
                bsr     sp1
                move.w  $2C(a2),d0
                bsr     phex4
                move.w  $2E(a2),d0
                bsr     phex4
                bsr     sp1
                move.l  (a2),d0
                bsr     tagof
                bsr     putc
                move.l  4(a2),d0
                bsr     tagof
                bsr     putc
                bsr     sp1
                move.l  $40(a2),d0
                bsr     phex8
                bsr     nl
                move.l  8(a2),a3
                moveq   #'C',d5
                bsr     dumpcr
                move.l  $24(a2),a3
                moveq   #'S',d5
                bsr     dumpcr
                move.l  $9C(a2),d0
                beq.s   .nd
                move.l  d0,a3
                moveq   #' ',d1
                bsr     putc
                bsr     sp1
                moveq   #'D',d1
                bsr     putc
                bsr     sp1
                move.l  (a3),d0
                bsr     phex8
                move.l  4(a3),d0
                bsr     phex8
                move.l  8(a3),a3
.dl:            move.l  a3,d0
                beq.s   .de
                bsr     sp1
                move.l  8(a3),d0
                bsr     phex8
                move.l  12(a3),d0
                bsr     phex8
                move.l  (a3),a3
                bra.s   .dl
.de:            bsr     nl
.nd:            rts

; --- ClipRect list a3, letter d5: bounds lobs (BytesPerRow Rows Depth | -)
dumpcr:         move.l  a3,d0
                beq.s   .e
                bsr     sp1
                bsr     sp1
                move.b  d5,d1
                bsr     putc
                bsr     sp1
                move.l  $10(a3),d0
                bsr     phex8
                move.l  $14(a3),d0
                bsr     phex8
                bsr     sp1
                move.l  8(a3),d0
                bsr     tagof
                bsr     putc
                bsr     sp1
                move.l  12(a3),d0
                beq.s   .nb
                move.l  d0,a0
                move.w  (a0),d0
                bsr     phex4
                move.w  2(a0),d0
                bsr     phex4
                move.b  5(a0),d0
                bsr     phex2
                bra.s   .f
.nb:            moveq   #'-',d1
                bsr     putc
.f:             bsr     nl
                move.l  (a3),a3
                bra.s   dumpcr
.e:             rts

; --- d0 = pointer -> d1 = letter (B C W O, 0, otherwise ?)
tagof:          moveq   #'0',d1
                tst.l   d0
                beq.s   .r
                moveq   #'B',d1
                cmp.l   lB-vars(a4),d0
                beq.s   .r
                moveq   #'C',d1
                cmp.l   lC-vars(a4),d0
                beq.s   .r
                moveq   #'W',d1
                cmp.l   lW-vars(a4),d0
                beq.s   .r
                moveq   #'O',d1
                cmp.l   lO-vars(a4),d0
                beq.s   .r
                moveq   #'?',d1
.r:             rts

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

; NewWindow: Left Top W H, pens, IDCMP (NEWSIZE|REFRESHWINDOW), Flags, gadget, check, title, screen,
; BitMap, MinW MinH MaxW MaxH, Type WBENCHSCREEN
nw1:            dc.w    100,30,200,80
                dc.b    0,1
                dc.l    $6,$41,0,0,0,0,0
                dc.w    40,20,640,200,1
nw2:            dc.w    100,30,200,80
                dc.b    0,1
                dc.l    $6,$481,0,0,0,0
                dc.l    0                       ; BitMap, patched with &sbm at start
                dc.w    40,20,320,200,1
nw3:            dc.w    100,30,200,80
                dc.b    0,1
                dc.l    $6,$81,0,0,0,0
                dc.l    0
                dc.w    40,20,320,200,1

nw4:            dc.w    100,30,200,80
                dc.b    0,1
                dc.l    $6,$1,0,0,0,0,0
                dc.w    40,20,640,200,1
nw5:            dc.w    100,30,200,80
                dc.b    0,1
                dc.l    $2,$1,0,0,0,0,0
                dc.w    40,20,640,200,1

gfxname:        dc.b    "graphics.library",0
layname:        dc.b    "layers.library",0
intname:        dc.b    "intuition.library",0
dosname:        dc.b    "dos.library",0
m_start:        dc.b    10,"RSP debut",10,0
m_t1a:          dc.b    "T1a",10,0
m_t1b:          dc.b    "T1b",10,0
m_t2a:          dc.b    "T2a",10,0
m_t2b:          dc.b    "T2b",10,0
m_t3:           dc.b    "T3",10,0
m_t4:           dc.b    "T4",10,0
m_t5:           dc.b    "T5",10,0
m_t6:           dc.b    "T6",10,0
m_t7:           dc.b    "T7",10,0
m_open:         dc.b    "open msgs",10,0
m_size:         dc.b    "size msgs",10,0
m_after:        dc.b    "after Begin/EndRefresh",10,0
m_rp:           dc.b    "RP layer flags super sbm ",0
m_wl:           dc.b    "WLayer BorderRPort layer flags ",0
m_super:        dc.b    "SuperBitMap content",10,0
m_end:          dc.b    "RSP fin",10,0
                even

vars:
gfxb:           dc.l    0
layb:           dc.l    0
intb:           dc.l    0
dosb:           dc.l    0
chip:           dc.l    0
li:             dc.l    0
lB:             dc.l    0
lC:             dc.l    0
lW:             dc.l    0
lO:             dc.l    0
win:            dc.l    0
wold:           dc.l    0
fr:             dc.l    0
fx0:            dc.w    0
fy0:            dc.w    0
fx1:            dc.w    0
fy1:            dc.w    0
grp:            dc.l    0
gx0:            dc.w    0
gy0:            dc.w    0
gx1:            dc.w    0
gy1:            dc.w    0
gnx:            dc.w    0
gny:            dc.w    0
gox:            dc.w    0
goy:            dc.w    0
gya:            dc.w    0
ghave:          dc.w    0
scrbm:          ds.b    40
sbm:            ds.b    40
scrrp:          ds.b    100
wrp:            ds.b    100
sbrp:           ds.b    100
dtmp:           ds.b    16
rowbuf:         ds.b    500
rowend:         ds.b    12
prevbuf:        ds.b    512
