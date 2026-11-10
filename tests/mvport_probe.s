; tests/mvport_probe.s - MakeVPort display window probe for OUR ROM (implementation track, authored).
; For each configuration of the table in docs/analysis/graphics-display-v34.md §4.4 (probed vectors), fills a View, a
; ViewPort, RasInfo and BitMap structures (fake plane addresses $2i000), calls MakeVPort, then prints the words of the
; copper fragment it built (vp_DspIns, our own layout in src/graphics/graphics.i) up to its end marker:
;   "MV <n> <word> <word> ..." then "MV END". tests/mvport_check.py decodes the lines and compares them with §4.4.
; Run by tests/mvport_probe.sh as a CLI command from a startup-sequence.

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018

LVO_OpenLibrary     EQU -552
LVO_CloseLibrary    EQU -414
LVO_MakeVPort       EQU -216
LVO_FreeVPortCopLists EQU -540

; structure offsets (graphics/view.h, gfx.h, 1.3)
v_ViewPort  EQU 0
v_DyOffset  EQU 12
v_DxOffset  EQU 14
v_Modes     EQU 16
vp_DspIns   EQU 8
vp_DWidth   EQU 24
vp_DHeight  EQU 26
vp_DxOffset EQU 28
vp_DyOffset EQU 30
vp_Modes    EQU 32
vp_RasInfo  EQU 36
ri_Next     EQU 0
ri_BitMap   EQU 4
ri_RxOffset EQU 8
ri_RyOffset EQU 10
bm_BytesPerRow EQU 0
bm_Rows     EQU 2
bm_Depth    EQU 5
bm_Planes   EQU 8

; configuration: vp Modes, View Modes, View DxOffset, DWidth, DHeight, vp DxOffset, BytesPerRow, depth 1, rx 1, ry 1,
; depth 2 (0: one playfield), rx 2 - 12 words
CFG_SIZE    EQU 24

                section code,code
start:
        move.l  4.w,a6
        lea     gfxname(pc),a1
        moveq   #0,d0
        jsr     LVO_OpenLibrary(a6)
        move.l  d0,a5                ; a5 = GfxBase
        tst.l   d0
        beq     .done
        lea     m_begin(pc),a0
        bsr     puts
        lea     cfgs(pc),a3
        moveq   #1,d7                ; d7 = configuration number
.cfg:
        cmp.w   #-1,(a3)             ; end of the table ($8000 is a HIRES row)
        beq     .end
        lea     view(pc),a0          ; View
        clr.l   v_ViewPort(a0)
        move.w  #$2C,v_DyOffset(a0)
        move.w  4(a3),v_DxOffset(a0)
        move.w  2(a3),v_Modes(a0)
        lea     vport(pc),a1         ; ViewPort (its fragment kept from one configuration to the next)
        move.w  6(a3),vp_DWidth(a1)
        move.w  8(a3),vp_DHeight(a1)
        move.w  10(a3),vp_DxOffset(a1)
        clr.w   vp_DyOffset(a1)
        move.w  (a3),vp_Modes(a1)
        lea     ri1(pc),a2
        move.l  a2,vp_RasInfo(a1)
        clr.l   ri_Next(a2)
        lea     bm1(pc),a4
        move.l  a4,ri_BitMap(a2)
        move.w  16(a3),ri_RxOffset(a2)
        move.w  18(a3),ri_RyOffset(a2)
        move.w  12(a3),bm_BytesPerRow(a4)
        move.w  8(a3),bm_Rows(a4)
        move.b  15(a3),bm_Depth(a4)
        move.l  #$20000,d0
        bsr     planes
        tst.w   20(a3)               ; second playfield
        beq.s   .pf1
        lea     ri2(pc),a4
        move.l  a4,ri_Next(a2)
        lea     bm2(pc),a2
        move.l  a2,ri_BitMap(a4)
        move.w  22(a3),ri_RxOffset(a4)
        clr.w   ri_RyOffset(a4)
        move.l  a2,a4
        move.w  12(a3),bm_BytesPerRow(a4)
        move.w  8(a3),bm_Rows(a4)
        move.b  21(a3),bm_Depth(a4)
        move.l  #$28000,d0
        bsr     planes
.pf1:
        move.l  a6,-(sp)
        move.l  a5,a6
        lea     view(pc),a0
        lea     vport(pc),a1
        jsr     LVO_MakeVPort(a6)
        move.l  (sp)+,a6
        lea     m_mv(pc),a0
        bsr     puts
        move.w  d7,d0
        bsr     phex4
        lea     vport(pc),a1
        move.l  vp_DspIns(a1),d0
        beq.s   .nl
        move.l  d0,a2
        addq.l  #4,a2                ; past the header long
        move.w  #400,d6              ; at most 400 entries
.ent:
        move.w  (a2)+,d0
        move.w  (a2)+,d1
        movem.w d0-d1,-(sp)
        bsr     phex4
        move.w  2(sp),d0
        bsr     phex4
        movem.w (sp)+,d0-d1
        cmp.w   #$FFFF,d0
        bne.s   .nx
        cmp.w   #$8000,d1
        beq.s   .nl
.nx:
        subq.w  #1,d6
        bne.s   .ent
.nl:
        bsr     nl
        lea     CFG_SIZE(a3),a3
        addq.w  #1,d7
        bra     .cfg
.end:
        move.l  a6,-(sp)
        move.l  a5,a6
        lea     vport(pc),a0
        jsr     LVO_FreeVPortCopLists(a6)
        move.l  (sp)+,a6
        lea     m_end(pc),a0
        bsr     puts
        move.l  a5,a1
        jsr     LVO_CloseLibrary(a6)
.done:
        moveq   #0,d0
        rts

; planes(a4 = BitMap, d0 = address of plane 0): bm_Planes[i] = d0 + i * $1000 for the 8 planes.
planes:
        lea     bm_Planes(a4),a0
        moveq   #7,d1
.pl:
        move.l  d0,(a0)+
        add.l   #$1000,d0
        dbra    d1,.pl
        rts

puts:
        move.b  (a0)+,d1
        beq.s   .r
        bsr.s   putc
        bra.s   puts
.r:     rts
nl:     moveq   #10,d1
        bra.s   putc
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

; the 13 rows of §4.4 (vp Modes, View Modes, View Dx, DWidth, DHeight, vp Dx, bpr, depth, rx, ry, depth 2, rx 2)
cfgs:
        dc.w    $0000,0,$81,320,200,0,40,2,0,0,0,0              ; 1 LORES 320x200, 2 planes
        dc.w    $8000,0,$81,640,200,0,80,4,0,0,0,0              ; 2 HIRES 640x200, 4 planes
        dc.w    $0000,0,$81,320,200,0,80,2,5,3,0,0              ; 3 LORES rx=5 ry=3, bpr 80
        dc.w    $8000,0,$81,640,200,0,80,2,3,0,0,0              ; 4 HIRES rx=3
        dc.w    $0000,0,$81,320,200,-10,40,1,0,0,0,0            ; 5 LORES Dx=-10
        dc.w    $0000,0,$81,400,200,0,50,1,0,0,0,0              ; 6 LORES DW=400, bpr 50
        dc.w    $0000,0,$81,200,200,20,40,1,0,0,0,0             ; 7 LORES Dx=20 DW=200
        dc.w    $0000,0,$85,320,200,0,40,1,0,0,0,0              ; 8 View Dx=$85
        dc.w    $0400,0,$81,320,200,0,40,2,0,0,2,3              ; 9 DUALPF 2+2, PF2 rx=3
        dc.w    $0800,0,$81,320,200,0,40,6,0,0,0,0              ; 10 HAM 6 planes
        dc.w    $0080,0,$81,320,200,0,40,6,0,0,0,0              ; 11 EHB 6 planes
        dc.w    $0400,0,$81,320,200,0,40,3,0,0,3,0              ; 12 DUALPF 3+3
        dc.w    $0004,4,$81,320,400,0,40,1,0,0,0,0              ; 13 LACE View + vp, 320x400
        dc.w    -1

gfxname:  dc.b  "graphics.library",0
m_begin:  dc.b  "MV BEGIN",10,0
m_mv:     dc.b  "MV",0
m_end:    dc.b  "MV END",10,0
                even

                cnop    0,4
view:     ds.b  18
                even
vport:    ds.b  40
ri1:      ds.b  12
ri2:      ds.b  12
bm1:      ds.b  40
bm2:      ds.b  40
