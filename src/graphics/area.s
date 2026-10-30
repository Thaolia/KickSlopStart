; src/graphics/area.s — graphics.library: polygon and ellipse fills, ellipses, Flood (spec
; docs/analysis/graphics-area-v34.md).
; InitArea / InitTmpRas / AreaMove / AreaDraw / AreaEllipse record the vertices like 1.3 (flags $00, $02,
; $03, $06/$07, ellipse $83 then $02; -1 when the table is full). AreaEnd builds a one-plane mask: crossing
; points per scan line (even/odd rule, lines [top, bottom[ of each non-horizontal edge, line bounds of the
; ellipses), each line filled from left to right, then complete edges added (or erased in
; JAM1 with AreaPtSz = 2, like 1.3): interior and edges included. The mask is rendered line by line by RectFill
; (RectFill's pens, mode, pattern and clipping by the layers), then the outline in AOlPen if AREAOUTLINE.
; DrawEllipse: Kennedy's algorithm in two sets (pixels identical to the spec's vectors), zero radii
; drawn as a segment, points plotted by the WritePixel LVO. Flood: 4-connected line-by-line fill (seeds
; on a stack, ReadPixel via LVO), mask then rendered by RectFill.
; Deviations: CPU rendering (no blitter or BltPattern), vertex table not translated, AreaEnd without TmpRas
; allocates its mask instead of writing to low memory, exactly Count entries read after an ellipse.
; IMPLEMENTATION track ("clean"): graphics AutoDocs + public structures + spec. NO ROM reading.

                include "exec.i"
                include "graphics.i"

                xdef    gfx_InitArea
                xdef    gfx_InitTmpRas
                xdef    gfx_AreaMove
                xdef    gfx_AreaDraw
                xdef    gfx_AreaEllipse
                xdef    gfx_AreaEnd
                xdef    gfx_DrawEllipse
                xdef    gfx_Flood

AREAOUTLINE     EQU $0008
ai_VctrTbl      EQU 0
ai_VctrPtr      EQU 4
ai_FlagTbl      EQU 8
ai_FlagPtr      EQU 12
ai_Count        EQU 16
ai_MaxCount     EQU 18
ai_FirstX       EQU 20
ai_FirstY       EQU 22
tr_RasPtr       EQU 0
tr_Size         EQU 4
LY_BOUNDS       EQU 16               ; Layer.bounds: MinX, MinY, MaxX, MaxY
LY_LOCK         EQU 72               ; Layer.Lock (SignalSemaphore)
LVO_READPIXEL   EQU -318
LVO_WRITEPIXEL  EQU -324
LVO_AREADRAW    EQU -258
AF_DRAWN        EQU 1                ; bits of the entry flags
AF_OUTLINE      EQU 2
AF_ELLIPSE      EQU 7

; InitArea(areaInfo a0, buffer a1, maxVectors d0): vertex tables (4 bytes per entry) then flag tables.
gfx_InitArea:
        move.l  a1,ai_VctrTbl(a0)
        move.l  a1,ai_VctrPtr(a0)
        move.w  d0,ai_MaxCount(a0)
        clr.w   ai_Count(a0)
        ext.l   d0
        lsl.l   #2,d0
        add.l   a1,d0
        move.l  d0,ai_FlagTbl(a0)
        move.l  d0,ai_FlagPtr(a0)
        rts

; InitTmpRas(tmpRas a0, buffer a1, size d0) -> d0 = tmpRas.
gfx_InitTmpRas:
        move.l  a1,tr_RasPtr(a0)
        move.l  d0,tr_Size(a0)
        move.l  a0,d0
        rts

; ar_close(a1 = RastPort, a0 = AreaInfo, a6) -> d0 = 0 | -1: before a new polygon or an ellipse, an isolated
; AreaMove just before is removed; otherwise an unclosed polygon is closed by AreaDraw(FirstX, FirstY) (LVO).
; Preserves d2-d7/a1-a6; a0 = AreaInfo on return.
ar_close:
        moveq   #0,d0
        tst.w   ai_Count(a0)
        beq.s   .cl_ret
        move.l  ai_FlagPtr(a0),a0
        move.b  -1(a0),d0
        move.l  rp_AreaInfo(a1),a0
        bne.s   .cl_drawn
        subq.w  #1,ai_Count(a0)      ; isolated AreaMove: replaced
        subq.l  #4,ai_VctrPtr(a0)
        subq.l  #1,ai_FlagPtr(a0)
        moveq   #0,d0
        bra.s   .cl_ret
.cl_drawn:
        cmp.w   #2,ai_Count(a0)      ; end of an ellipse: nothing to close
        blo.s   .cl_poly
        move.l  ai_FlagPtr(a0),a0
        btst    #AF_ELLIPSE,-2(a0)
        move.l  rp_AreaInfo(a1),a0
        bne.s   .cl_ok
.cl_poly:
        move.l  ai_VctrPtr(a0),a0
        move.l  -4(a0),d0            ; last vertex (x, y)
        move.l  rp_AreaInfo(a1),a0
        cmp.l   ai_FirstX(a0),d0
        beq.s   .cl_ok
        movem.l d1/a1,-(sp)
        move.w  ai_FirstX(a0),d0
        ext.l   d0
        move.w  ai_FirstY(a0),d1
        ext.l   d1
        jsr     LVO_AREADRAW(a6)
        movem.l (sp)+,d1/a1
        move.l  rp_AreaInfo(a1),a0
        rts
.cl_ok:
        moveq   #0,d0
.cl_ret:
        rts

; ar_add(a0 = AreaInfo, d0 = x, d1 = y, d2.b = flag) -> d0 = 0 | -1 (table full). Clobbers d3.
ar_add:
        move.w  ai_Count(a0),d3
        cmp.w   ai_MaxCount(a0),d3
        bhs.s   .ad_full
        move.l  a1,-(sp)
        move.l  ai_VctrPtr(a0),a1
        move.w  d0,(a1)+
        move.w  d1,(a1)+
        move.l  a1,ai_VctrPtr(a0)
        move.l  ai_FlagPtr(a0),a1
        move.b  d2,(a1)+
        move.l  a1,ai_FlagPtr(a0)
        move.l  (sp)+,a1
        addq.w  #1,ai_Count(a0)
        moveq   #0,d0
        rts
.ad_full:
        moveq   #-1,d0
        rts

; AreaMove(rp a1, x d0, y d1) -> d0 = 0 | -1: closes the current polygon, then new starting point.
gfx_AreaMove:
        movem.l d2-d4,-(sp)
        move.l  d0,d4
        move.l  rp_AreaInfo(a1),a0
        movem.l d0-d1,-(sp)
        bsr     ar_close
        movem.l (sp)+,d2-d3          ; d2/d3 = x, y (ar_close returned d0)
        tst.l   d0
        bmi.s   .am_ret
        move.l  d2,d0
        move.l  d3,d1
        moveq   #0,d2
        bsr.s   ar_add
        tst.l   d0
        bmi.s   .am_ret
        move.w  d4,ai_FirstX(a0)
        move.w  d1,ai_FirstY(a0)
.am_ret:
        movem.l (sp)+,d2-d4
        rts

; AreaDraw(rp a1, x d0, y d1) -> d0 = 0 | -1: edge to (x, y); flag $02, | $04 if AREAOUTLINE now,
; | $01 if the edge is not horizontal.
gfx_AreaDraw:
        movem.l d2-d3,-(sp)
        move.l  rp_AreaInfo(a1),a0
        moveq   #2,d2
        btst    #3,rp_Flags+1(a1)    ; AREAOUTLINE
        beq.s   .ad_o
        moveq   #6,d2
.ad_o:
        tst.w   ai_Count(a0)
        beq.s   .ad_nh
        move.l  ai_VctrPtr(a0),a0
        cmp.w   -2(a0),d1
        move.l  rp_AreaInfo(a1),a0
        beq.s   .ad_h
.ad_nh:
        or.b    #1,d2
.ad_h:
        bsr     ar_add
        movem.l (sp)+,d2-d3
        rts

; AreaEllipse(rp a1, cx d0, cy d1, a d2, b d3) -> d0 = 0 | -1: two entries, corners of the bounding box ($83, $02).
; FirstX/FirstY unchanged.
gfx_AreaEllipse:
        movem.l d2-d5,-(sp)
        movem.l d0-d3,-(sp)
        move.l  rp_AreaInfo(a1),a0
        bsr     ar_close
        move.l  d0,d5
        movem.l (sp)+,d0-d3
        tst.l   d5
        bmi.s   .ae_fail
        move.w  ai_MaxCount(a0),d5
        sub.w   ai_Count(a0),d5
        cmp.w   #2,d5
        blt.s   .ae_fail
        move.l  d2,d4                ; d4/d5 = a, b
        move.l  d3,d5
        movem.l d0-d1,-(sp)
        sub.w   d4,d0
        sub.w   d5,d1
        move.b  #$83,d2
        bsr     ar_add
        movem.l (sp)+,d0-d1
        add.w   d4,d0
        add.w   d5,d1
        moveq   #2,d2
        bsr     ar_add
        bra.s   .ae_ret
.ae_fail:
        moveq   #-1,d0
.ae_ret:
        movem.l (sp)+,d2-d5
        rts

; ---------------------------------------------------------------------------------------------------------------
; el_gen(d2 = a, d3 = b, a3 = callback): points of the first quadrant of an ellipse (Kennedy's algorithm in two
; sets, from (a, 0) then from (0, b)); the callback receives d0 = x, d1 = y relative (>= 0), once per
; point (the junction point is not repeated). Zero radii: the segment (x from 0 to a, or y from 0 to b). The
; callback may destroy d0/d1/a0/a1 and must preserve the rest. Preserves d2-d7/a2-a6.
EG_SIZE         EQU 32               ; local variables below a4 (link)
EG_A2           EQU -32              ; 2a²
EG_B2           EQU -28              ; 2b²
EG_XC           EQU -24
EG_YC           EQU -20
EG_ERR          EQU -16
EG_SX           EQU -12
EG_SY           EQU -8
EG_LAST         EQU -4               ; last point emitted (x, y)
el_gen:
        movem.l d2-d7,-(sp)
        link    a4,#-EG_SIZE
        move.l  #-1,EG_LAST(a4)
        and.l   #$FFFF,d2
        and.l   #$FFFF,d3
        moveq   #0,d6
        moveq   #0,d7
        tst.w   d3
        bne.s   .eg_b
.eg_hs:                              ; b = 0 : (0..a, 0)
        bsr     .eg_emit
        addq.w  #1,d6
        cmp.w   d2,d6
        bls.s   .eg_hs
        bra     .eg_ret
.eg_b:
        tst.w   d2
        bne.s   .eg_full
.eg_vs:                              ; a = 0 : (0, 0..b)
        bsr     .eg_emit
        addq.w  #1,d7
        cmp.w   d3,d7
        bls.s   .eg_vs
        bra     .eg_ret
.eg_full:
        move.w  d2,d0
        mulu    d2,d0                ; a²
        move.l  d0,d4
        add.l   d0,d0
        move.l  d0,EG_A2(a4)
        move.w  d3,d0
        mulu    d3,d0                ; b²
        move.l  d0,d5
        add.l   d0,d0
        move.l  d0,EG_B2(a4)
        ; set 1: from (a, 0), increasing y
        move.l  EG_B2(a4),d0
        move.w  d2,d1
        bsr     el_mul               ; 2b²·a
        move.l  d0,EG_SX(a4)
        move.l  d5,d1
        sub.l   d0,d1
        move.l  d1,EG_XC(a4)         ; b²(1 - 2a)
        move.l  d4,EG_YC(a4)         ; a²
        clr.l   EG_ERR(a4)
        clr.l   EG_SY(a4)
        move.w  d2,d6                ; d6 = x, d7 = y
        moveq   #0,d7
.eg_s1:
        move.l  EG_SX(a4),d0
        cmp.l   EG_SY(a4),d0
        blt.s   .eg_set2
        bsr     .eg_emit
        addq.w  #1,d7
        move.l  EG_A2(a4),d0
        add.l   d0,EG_SY(a4)
        move.l  EG_YC(a4),d1
        add.l   d1,EG_ERR(a4)
        add.l   d0,EG_YC(a4)
        move.l  EG_ERR(a4),d0
        add.l   d0,d0
        add.l   EG_XC(a4),d0
        ble.s   .eg_s1
        subq.w  #1,d6
        move.l  EG_B2(a4),d0
        sub.l   d0,EG_SX(a4)
        move.l  EG_XC(a4),d1
        add.l   d1,EG_ERR(a4)
        add.l   d0,EG_XC(a4)
        bra.s   .eg_s1
.eg_set2:                            ; set 2: from (0, b), increasing x
        move.l  EG_A2(a4),d0
        move.w  d3,d1
        bsr     el_mul               ; 2a²·b
        move.l  d0,EG_SY(a4)
        move.l  d4,d1
        sub.l   d0,d1
        move.l  d1,EG_YC(a4)         ; a²(1 - 2b)
        move.l  d5,EG_XC(a4)         ; b²
        clr.l   EG_ERR(a4)
        clr.l   EG_SX(a4)
        moveq   #0,d6
        move.w  d3,d7
.eg_s2:
        move.l  EG_SX(a4),d0
        cmp.l   EG_SY(a4),d0
        bgt.s   .eg_ret
        bsr.s   .eg_emit
        addq.w  #1,d6
        move.l  EG_B2(a4),d0
        add.l   d0,EG_SX(a4)
        move.l  EG_XC(a4),d1
        add.l   d1,EG_ERR(a4)
        add.l   d0,EG_XC(a4)
        move.l  EG_ERR(a4),d0
        add.l   d0,d0
        add.l   EG_YC(a4),d0
        ble.s   .eg_s2
        subq.w  #1,d7
        move.l  EG_A2(a4),d0
        sub.l   d0,EG_SY(a4)
        move.l  EG_YC(a4),d1
        add.l   d1,EG_ERR(a4)
        add.l   d0,EG_YC(a4)
        bra.s   .eg_s2
.eg_ret:
        unlk    a4
        movem.l (sp)+,d2-d7
        rts
.eg_emit:                            ; point (d6, d7) if it differs from the previous one
        move.w  d6,d0
        swap    d0
        move.w  d7,d0
        cmp.l   EG_LAST(a4),d0
        beq.s   .em_r
        move.l  d0,EG_LAST(a4)
        moveq   #0,d0
        move.w  d6,d0
        moveq   #0,d1
        move.w  d7,d1
        movem.l d2-d7/a2-a6,-(sp)
        jsr     (a3)
        movem.l (sp)+,d2-d7/a2-a6
.em_r:
        rts

; el_mul(d0.l >= 0, d1.w >= 0) -> d0.l = d0 × d1 (32 × 16 bits, unsigned). Clobbers d1.
el_mul:
        move.l  d2,-(sp)
        move.l  d0,d2
        swap    d2
        mulu    d1,d2
        swap    d2
        clr.w   d2
        mulu    d1,d0
        add.l   d2,d0
        move.l  (sp)+,d2
        rts

; ---------------------------------------------------------------------------------------------------------------
; DrawEllipse(rp a1, cx d0, cy d1, a d2, b d3): each point via WritePixel (LVO, hence clipped by the layer and
; subject to SetFunction), four-quadrant symmetry without duplicates on the axes.
DE_RP           EQU 0
DE_CX           EQU 4
DE_CY           EQU 6
DE_SIZE         EQU 8
gfx_DrawEllipse:
        movem.l a2-a3/a5,-(sp)
        lea     -DE_SIZE(sp),sp
        move.l  sp,a5
        move.l  a1,DE_RP(a5)
        move.w  d0,DE_CX(a5)
        move.w  d1,DE_CY(a5)
        lea     de_plot(pc),a3
        bsr     el_gen
        lea     DE_SIZE(sp),sp
        movem.l (sp)+,a2-a3/a5
        rts
de_plot:                             ; (d0 = x, d1 = y relative, a5 = frame, a6 = GfxBase)
        move.w  d0,d2
        move.w  d1,d3
        bsr.s   .dp_one              ; (+x, +y)
        tst.w   d2
        beq.s   .dp_y
        neg.w   d2
        bsr.s   .dp_one              ; (-x, +y)
        neg.w   d2
.dp_y:
        tst.w   d3
        beq.s   .dp_r
        neg.w   d3
        bsr.s   .dp_one              ; (+x, -y)
        tst.w   d2
        beq.s   .dp_r
        neg.w   d2                   ; (-x, -y)
.dp_one:
        move.w  DE_CX(a5),d0
        add.w   d2,d0
        ext.l   d0
        move.w  DE_CY(a5),d1
        add.w   d3,d1
        ext.l   d1
        move.l  DE_RP(a5),a1
        jmp     LVO_WRITEPIXEL(a6)
.dp_r:
        rts

; ---------------------------------------------------------------------------------------------------------------
; One-plane mask (AreaEnd, Flood): frame in a5.
MK_BUF          EQU 0                ; long: buffer
MK_ALLOC        EQU 4                ; long: allocated size (0 = caller's TmpRas)
MK_X0           EQU 8                ; word: absolute x of column 0
MK_Y0           EQU 10               ; word: absolute y of row 0
MK_L            EQU 12               ; word: bytes per row
MK_H            EQU 14               ; word: rows
MK_OP           EQU 16               ; word: 0 = set to 1, 1 = set to 0, 2 = invert
MK_RP           EQU 18               ; long: caller's RastPort
MK_CX           EQU 22               ; word: ellipse centre (callbacks)
MK_CY           EQU 24
MK_TBL          EQU 26               ; long: table of an ellipse's half-widths
MK_FLAGS        EQU 30               ; word: saved rp_Flags
MK_SIZE         EQU 32

; mk_bit(d0 = x, d1 = y absolute, a5): applies MK_OP to the point (outside the mask: nothing). Clobbers d0/d1/a0.
mk_bit:
        sub.w   MK_X0(a5),d0
        bmi.s   .mb_r
        sub.w   MK_Y0(a5),d1
        bmi.s   .mb_r
        cmp.w   MK_H(a5),d1
        bge.s   .mb_r
        move.l  d2,-(sp)
        move.w  MK_L(a5),d2
        lsl.w   #3,d2
        cmp.w   d2,d0
        bge.s   .mb_out
        mulu    MK_L(a5),d1
        move.l  MK_BUF(a5),a0
        add.l   d1,a0
        move.w  d0,d1
        lsr.w   #3,d1
        add.w   d1,a0
        not.w   d0
        and.w   #7,d0                ; bit 7 = leftmost pixel of the byte
        move.w  MK_OP(a5),d2
        beq.s   .mb_set
        subq.w  #1,d2
        beq.s   .mb_clr
        bchg    d0,(a0)
        bra.s   .mb_out
.mb_set:
        bset    d0,(a0)
        bra.s   .mb_out
.mb_clr:
        bclr    d0,(a0)
.mb_out:
        move.l  (sp)+,d2
.mb_r:
        rts

; mk_line(d0/d1 = start, d2/d3 = end, absolute, a5): segment into the mask, endpoints included, walked from the
; start to the end by Draw's unified Bresenham (same pixels as the 1.3 edges, direction included).
; Preserves d2-d7/a1-a6.
mk_line:
        movem.l d2-d7,-(sp)
        move.w  d2,d4
        sub.w   d0,d4                ; d4 = |dx|, d6 = x step
        moveq   #1,d6
        tst.w   d4
        bpl.s   .ml_1
        neg.w   d4
        moveq   #-1,d6
.ml_1:
        move.w  d3,d5
        sub.w   d1,d5                ; d5 = -|dy|, d7 = y step
        moveq   #-1,d7
        tst.w   d5
        bmi.s   .ml_2
        neg.w   d5
        moveq   #1,d7
.ml_2:
        move.w  d4,-(sp)
        add.w   d5,(sp)              ; error = dx + dy
        movem.w d0-d1,-(sp)          ; (sp) = x, 2(sp) = y, 4(sp) = error
.ml_lp:
        movem.w (sp),d0-d1
        bsr     mk_bit
        movem.w (sp),d0-d1
        cmp.w   d2,d0
        bne.s   .ml_st
        cmp.w   d3,d1
        beq.s   .ml_end
.ml_st:
        move.w  4(sp),d0
        add.w   d0,d0
        cmp.w   d5,d0
        blt.s   .ml_ny
        add.w   d5,4(sp)
        add.w   d6,(sp)
.ml_ny:
        cmp.w   d4,d0
        bgt.s   .ml_lp
        add.w   d4,4(sp)
        add.w   d7,2(sp)
        bra.s   .ml_lp
.ml_end:
        addq.l  #6,sp
        movem.l (sp)+,d2-d7
        rts

; mk_alloc(d0.w = width in pixels from MK_X0, d1.w = height, a1 = RastPort, a5) -> Z = 0 if a cleared mask
; is ready (caller's TmpRas if it exists and is large enough, otherwise allocated memory). Clobbers d0/d1/a0.
mk_alloc:
        add.w   #15,d0
        lsr.w   #4,d0
        add.w   d0,d0
        move.w  d0,MK_L(a5)
        move.w  d1,MK_H(a5)
        mulu    d0,d1
        clr.l   MK_ALLOC(a5)
        move.l  rp_TmpRas(a1),d0
        beq.s   .ma_new
        move.l  d0,a0
        cmp.l   tr_Size(a0),d1
        bhi.s   .ma_new
        move.l  tr_RasPtr(a0),d0
        beq.s   .ma_new
        move.l  d0,MK_BUF(a5)
        move.l  d0,a0
        move.l  d1,d0
        bra.s   .ma_clr
.ma_new:
        movem.l d1/a1/a6,-(sp)
        move.l  d1,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        move.l  ($4).w,a6
        jsr     LVO_ALLOCMEM(a6)
        movem.l (sp)+,d1/a1/a6
        move.l  d0,MK_BUF(a5)
        beq.s   .ma_r
        move.l  d1,MK_ALLOC(a5)
        moveq   #1,d0
        rts
.ma_clr:
        subq.l  #1,d0
        bmi.s   .ma_ok
.ma_cl:
        clr.b   (a0)+
        subq.l  #1,d0
        bpl.s   .ma_cl
.ma_ok:
        moveq   #1,d0
.ma_r:
        rts

; mk_free(a5): frees the mask if it was allocated. Preserves everything except d0/d1/a0/a1.
mk_free:
        move.l  MK_ALLOC(a5),d0
        beq.s   .mf_r
        move.l  MK_BUF(a5),a1
        move.l  a6,-(sp)
        move.l  ($4).w,a6
        jsr     LVO_FREEMEM(a6)
        move.l  (sp)+,a6
.mf_r:
        rts

; mk_render(a5, a6 = GfxBase): each run of 1 bits in a mask row becomes a RectFill on the caller's
; RastPort (AREAOUTLINE masked during rendering). Preserves d2-d7/a2-a6.
mk_render:
        movem.l d2-d7/a2,-(sp)
        move.l  MK_RP(a5),a1
        move.w  rp_Flags(a1),MK_FLAGS(a5)
        and.w   #~AREAOUTLINE,rp_Flags(a1)
        move.l  MK_BUF(a5),a2
        moveq   #0,d7                ; d7 = row
.mr_row:
        cmp.w   MK_H(a5),d7
        bge.s   .mr_end
        moveq   #-1,d5               ; d5 = start of the current run (-1: none)
        moveq   #0,d6                ; d6 = column
        move.w  MK_L(a5),d4
        lsl.w   #3,d4                ; d4 = columns
.mr_col:
        cmp.w   d4,d6
        bge.s   .mr_eol
        move.w  d6,d0
        lsr.w   #3,d0
        move.b  0(a2,d0.w),d1
        move.w  d6,d0
        not.w   d0
        and.w   #7,d0
        btst    d0,d1
        beq.s   .mr_zero
        tst.w   d5
        bpl.s   .mr_next
        move.w  d6,d5
        bra.s   .mr_next
.mr_zero:
        tst.w   d5
        bmi.s   .mr_next
        move.w  d6,d2
        subq.w  #1,d2
        bsr.s   .mr_fill
        moveq   #-1,d5
.mr_next:
        addq.w  #1,d6
        bra.s   .mr_col
.mr_eol:
        tst.w   d5
        bmi.s   .mr_nr
        move.w  d6,d2
        subq.w  #1,d2
        bsr.s   .mr_fill
.mr_nr:
        add.w   MK_L(a5),a2
        addq.w  #1,d7
        bra.s   .mr_row
.mr_end:
        move.l  MK_RP(a5),a1
        move.w  MK_FLAGS(a5),rp_Flags(a1)
        movem.l (sp)+,d2-d7/a2
        rts
.mr_fill:                            ; RectFill(x0 + d5, y0 + d7, x0 + d2, y0 + d7)
        movem.l d2-d7/a2,-(sp)
        move.w  MK_X0(a5),d0
        add.w   d5,d0
        ext.l   d0
        move.w  MK_Y0(a5),d1
        add.w   d7,d1
        ext.l   d1
        add.w   MK_X0(a5),d2
        ext.l   d2
        move.l  d1,d3
        move.l  MK_RP(a5),a1
        jsr     LVO_RECTFILL(a6)
        movem.l (sp)+,d2-d7/a2
        rts

; ---------------------------------------------------------------------------------------------------------------
; AreaEnd(rp a1) -> d0 = 0 | -1.
gfx_AreaEnd:
        movem.l d2-d7/a2-a5,-(sp)
        lea     -MK_SIZE(sp),sp
        move.l  sp,a5
        move.l  a1,MK_RP(a5)
        move.l  rp_AreaInfo(a1),a2   ; a2 = AreaInfo
        move.w  ai_Count(a2),d0
        beq     .ae_reset
        move.l  ai_FlagPtr(a2),a0
        tst.b   -1(a0)
        bne.s   .ae_last
        cmp.w   #1,d0                ; ends with an AreaMove
        bls     .ae_reset
        bra.s   .ae_go
.ae_last:
        cmp.w   #2,d0                ; end of ellipse: already closed
        blo.s   .ae_cl
        btst    #AF_ELLIPSE,-2(a0)
        bne.s   .ae_go
.ae_cl:
        move.l  ai_VctrPtr(a2),a0
        move.l  -4(a0),d0
        cmp.l   ai_FirstX(a2),d0
        beq.s   .ae_go
        move.w  ai_FirstX(a2),d0
        ext.l   d0
        move.w  ai_FirstY(a2),d1
        ext.l   d1
        jsr     LVO_AREADRAW(a6)
        move.l  MK_RP(a5),a1
        tst.l   d0
        bpl.s   .ae_go
        moveq   #-1,d7
        bra     .ae_reset2
.ae_go:
        ; bounding box of all entries
        move.l  ai_VctrTbl(a2),a0
        move.w  ai_Count(a2),d7
        subq.w  #1,d7
        move.w  #$7FFF,d2            ; d2/d3 = min x, y; d4/d5 = max x, y
        move.w  d2,d3
        move.w  #$8000,d4
        move.w  d4,d5
.ae_bb:
        move.w  (a0)+,d0
        move.w  (a0)+,d1
        cmp.w   d2,d0
        bge.s   .ae_b1
        move.w  d0,d2
.ae_b1:
        cmp.w   d4,d0
        ble.s   .ae_b2
        move.w  d0,d4
.ae_b2:
        cmp.w   d3,d1
        bge.s   .ae_b3
        move.w  d1,d3
.ae_b3:
        cmp.w   d5,d1
        ble.s   .ae_b4
        move.w  d1,d5
.ae_b4:
        dbra    d7,.ae_bb
        and.w   #$FFF0,d2
        move.w  d2,MK_X0(a5)
        move.w  d3,MK_Y0(a5)
        move.w  d4,d0
        sub.w   d2,d0
        addq.w  #1,d0
        move.w  d5,d1
        sub.w   d3,d1
        addq.w  #1,d1
        bsr     mk_alloc
        beq     .ae_nomem
        ; pass 1: crossing points (inversion), pass 2: line filling
        move.w  #2,MK_OP(a5)
        moveq   #1,d6                ; pass 1
        bsr     ae_walk
        bsr     ae_rows
        ; pass 3: complete edges (set to 1, or to 0 if DrawMode = JAM1 and AreaPtSz = 2)
        clr.w   MK_OP(a5)
        move.l  MK_RP(a5),a1
        move.b  rp_DrawMode(a1),d0
        lsl.w   #8,d0
        move.b  rp_AreaPtSz(a1),d0
        cmp.w   #$0002,d0
        bne.s   .ae_p3
        move.w  #1,MK_OP(a5)
.ae_p3:
        moveq   #3,d6
        bsr     ae_walk
        bsr     mk_render            ; pass 4: rendering
        bsr     ae_outline
        bsr     mk_free
        moveq   #0,d7
        bra.s   .ae_reset2
.ae_nomem:
        moveq   #-1,d7
        bra.s   .ae_reset2
.ae_reset:
        moveq   #0,d7
.ae_reset2:
        move.l  ai_VctrTbl(a2),ai_VctrPtr(a2)
        move.l  ai_FlagTbl(a2),ai_FlagPtr(a2)
        clr.w   ai_Count(a2)
        move.l  d7,d0
        lea     MK_SIZE(sp),sp
        movem.l (sp)+,d2-d7/a2-a5
        rts

; ae_rows(a5): each mask row is filled from left to right between the crossing points (one point
; opens the run, the next closes it without being filled; the pass 3 edges complete it). Preserves d2-d7/a2-a6.
ae_rows:
        movem.l d2-d5/a2,-(sp)
        move.l  MK_BUF(a5),a2
        move.w  MK_H(a5),d4
        subq.w  #1,d4
.ar_row:
        moveq   #0,d2                ; state (0 / $FF)
        move.w  MK_L(a5),d5
        subq.w  #1,d5
.ar_byte:
        move.b  (a2),d0
        moveq   #0,d1                ; result byte
        moveq   #7,d3
.ar_bit:
        btst    d3,d0
        beq.s   .ar_b0
        not.b   d2
.ar_b0:
        tst.b   d2
        beq.s   .ar_b1
        bset    d3,d1
.ar_b1:
        dbra    d3,.ar_bit
        move.b  d1,(a2)+
        dbra    d5,.ar_byte
        dbra    d4,.ar_row
        movem.l (sp)+,d2-d5/a2
        rts

; ae_walk(d6 = pass 1 | 3, a2 = AreaInfo, a5): walks the Count entries. Pass 1: non-horizontal edges ->
; one point per line [top, bottom[; ellipses -> bounds of each line. Pass 3: all edges in full,
; ellipses by their outline. Preserves d2-d7/a2-a6.
ae_walk:
        movem.l d2-d7/a2-a4,-(sp)
        move.l  ai_VctrTbl(a2),a3
        move.l  ai_FlagTbl(a2),a4
        move.w  ai_Count(a2),d7
        moveq   #0,d4                ; current point (d4 = x, d5 = y)
        moveq   #0,d5
.aw_lp:
        subq.w  #1,d7
        bmi     .aw_ret
        move.b  (a4)+,d0
        btst    #AF_ELLIPSE,d0
        bne.s   .aw_ell
        movem.w (a3)+,d2-d3          ; vertex
        btst    #AF_DRAWN,d0
        beq.s   .aw_move
        cmp.w   #1,d6
        bne.s   .aw_full
        cmp.w   d5,d3
        beq.s   .aw_move             ; horizontal: nothing in pass 1
        bsr     ae_cross
        bra.s   .aw_move
.aw_full:
        move.w  d4,d0
        move.w  d5,d1
        bsr     mk_line
.aw_move:
        move.w  d2,d4
        move.w  d3,d5
        bra.s   .aw_lp
.aw_ell:                             ; two entries: corners of the bounding box
        subq.w  #1,d7
        bmi     .aw_ret
        addq.l  #1,a4
        movem.w (a3)+,d0-d3          ; (x1, y1, x2, y2)
        add.w   d2,d0
        asr.w   #1,d0                ; centre
        add.w   d3,d1
        asr.w   #1,d1
        sub.w   d0,d2                ; radii
        sub.w   d1,d3
        move.w  d0,MK_CX(a5)
        move.w  d1,MK_CY(a5)
        cmp.w   #1,d6
        bne.s   .aw_e3
        bsr     ae_ellrows
        bra.s   .aw_lp
.aw_e3:
        movem.l a3,-(sp)
        lea     mk_ellplot(pc),a3
        bsr     el_gen
        movem.l (sp)+,a3
        bra     .aw_lp
.aw_ret:
        movem.l (sp)+,d2-d7/a2-a4
        rts

; ae_cross(d4/d5 = start, d2/d3 = end, a5): for each line y in [min y, max y[ of the edge, inversion of the point
; x = x(top) + round((y - y(top)) × dx / dy). Preserves d2-d7/a2-a6.
ae_cross:
        movem.l d2-d7,-(sp)
        cmp.w   d3,d5                ; (d4, d5) = top, (d2, d3) = bottom
        ble.s   .ac_o
        exg     d2,d4
        exg     d3,d5
.ac_o:
        move.w  d2,d6
        sub.w   d4,d6                ; dx
        move.w  d3,d7
        sub.w   d5,d7                ; dy > 0
        moveq   #0,d2                ; d2 = line index
.ac_lp:
        cmp.w   d7,d2
        bge.s   .ac_ret
        move.w  d2,d0
        muls    d6,d0
        add.l   d0,d0                ; 2·i·dx
        moveq   #0,d1
        move.w  d7,d1
        add.l   d1,d0                ; + dy
        add.w   d1,d1                ; divisor 2·dy
        tst.l   d0
        bmi.s   .ac_neg
        divu    d1,d0
        bra.s   .ac_q
.ac_neg:
        neg.l   d0
        add.l   d1,d0
        subq.l  #1,d0
        divu    d1,d0
        neg.w   d0
.ac_q:
        add.w   d4,d0                ; x
        move.w  d5,d1
        add.w   d2,d1                ; y
        bsr     mk_bit
        addq.w  #1,d2
        bra.s   .ac_lp
.ac_ret:
        movem.l (sp)+,d2-d7
        rts

; ae_ellrows(d2 = a, d3 = b, MK_CX/MK_CY, a5): table of half-widths per line (maximum x of each y of the
; outline), then inversion of the two bounds of each line. Preserves d2-d7/a2-a6.
ae_ellrows:
        movem.l d2-d7/a3,-(sp)
        moveq   #0,d0
        move.w  d3,d0
        addq.l  #1,d0
        add.l   d0,d0
        move.l  d0,d7                ; size of the table
        move.l  #MEMF_PUBLIC,d1
        move.l  a6,-(sp)
        move.l  ($4).w,a6
        jsr     LVO_ALLOCMEM(a6)
        move.l  (sp)+,a6
        move.l  d0,MK_TBL(a5)
        beq.s   .er_ret
        move.l  d0,a0
        move.w  d3,d1
.er_init:
        move.w  #-1,(a0)+
        dbra    d1,.er_init
        lea     er_max(pc),a3
        bsr     el_gen
        move.l  MK_TBL(a5),a3
        moveq   #0,d6                ; relative y
.er_row:
        cmp.w   d3,d6
        bgt.s   .er_free
        move.w  (a3)+,d5             ; half-width
        bmi.s   .er_next
        move.w  MK_CY(a5),d4
        add.w   d6,d4
        bsr.s   .er_pair
        tst.w   d6
        beq.s   .er_next
        move.w  MK_CY(a5),d4
        sub.w   d6,d4
        bsr.s   .er_pair
.er_next:
        addq.w  #1,d6
        bra.s   .er_row
.er_free:
        move.l  MK_TBL(a5),a1
        move.l  d7,d0
        move.l  a6,-(sp)
        move.l  ($4).w,a6
        jsr     LVO_FREEMEM(a6)
        move.l  (sp)+,a6
.er_ret:
        movem.l (sp)+,d2-d7/a3
        rts
.er_pair:                            ; line d4: inversion at cx - d5 and cx + d5
        move.w  MK_CX(a5),d0
        sub.w   d5,d0
        move.w  d4,d1
        bsr     mk_bit
        move.w  MK_CX(a5),d0
        add.w   d5,d0
        move.w  d4,d1
        bra     mk_bit
er_max:                              ; callback: table[y] = max(table[y], x)
        move.l  MK_TBL(a5),a0
        add.w   d1,d1
        cmp.w   0(a0,d1.w),d0
        ble.s   .em_r
        move.w  d0,0(a0,d1.w)
.em_r:
        rts

; mk_ellplot: el_gen callback, the four symmetric points around MK_CX/MK_CY into the mask (MK_OP).
mk_ellplot:
        move.w  d0,d2
        move.w  d1,d3
        bsr.s   .ep_one
        neg.w   d2
        bsr.s   .ep_one
        neg.w   d3
        bsr.s   .ep_one
        neg.w   d2
.ep_one:
        move.w  MK_CX(a5),d0
        add.w   d2,d0
        move.w  MK_CY(a5),d1
        add.w   d3,d1
        bra     mk_bit

; ae_outline(a2 = AreaInfo, a5, a6): if AREAOUTLINE, outline in AOlPen, JAM1, solid line, no pattern: Draw (LVO)
; to each entry whose outline flag is set, Move otherwise; ellipses never outlined. Preserves d2-d7/a2-a6.
ae_outline:
        move.l  MK_RP(a5),a1
        btst    #3,MK_FLAGS+1(a5)
        beq     .ao_r
        movem.l d2-d7/a2-a4,-(sp)
        move.l  a1,a3
        move.b  rp_FgPen(a3),-(sp)
        move.b  rp_DrawMode(a3),-(sp)
        move.w  rp_LinePtrn(a3),-(sp)
        move.l  rp_AreaPtrn(a3),-(sp)
        move.l  a3,a1
        moveq   #0,d0
        move.b  rp_AOlPen(a3),d0
        jsr     LVO_SETAPEN(a6)
        move.l  a3,a1
        moveq   #JAM1,d0
        jsr     LVO_SETDRMD(a6)
        move.w  #$FFFF,rp_LinePtrn(a3)
        clr.l   rp_AreaPtrn(a3)
        move.w  ai_Count(a2),d7
        move.l  ai_VctrTbl(a2),a4
        move.l  ai_FlagTbl(a2),a2
.ao_lp:
        subq.w  #1,d7
        bmi.s   .ao_end
        move.b  (a2)+,d2
        btst    #AF_ELLIPSE,d2
        beq.s   .ao_pt
        subq.w  #1,d7
        addq.l  #1,a2
        addq.l  #8,a4
        bra.s   .ao_lp
.ao_pt:
        move.w  (a4)+,d0
        ext.l   d0
        move.w  (a4)+,d1
        ext.l   d1
        move.l  a3,a1
        btst    #AF_DRAWN,d2
        beq.s   .ao_mv
        btst    #AF_OUTLINE,d2
        beq.s   .ao_mv
        jsr     LVO_DRAW(a6)
        bra.s   .ao_lp
.ao_mv:
        jsr     LVO_MOVE(a6)
        bra.s   .ao_lp
.ao_end:
        move.l  (sp)+,rp_AreaPtrn(a3)
        move.w  (sp)+,rp_LinePtrn(a3)
        move.b  (sp)+,d0
        move.l  a3,a1
        ext.w   d0
        jsr     LVO_SETDRMD(a6)
        moveq   #0,d0
        move.b  (sp)+,d0
        move.l  a3,a1
        jsr     LVO_SETAPEN(a6)
        movem.l (sp)+,d2-d7/a2-a4
.ao_r:
        rts

; ---------------------------------------------------------------------------------------------------------------
; Flood(rp a1, mode d2, x d0, y d1) -> d0 = 1 | 0. Mode 0: up to the AOlPen colour; mode 1: as long as the colour
; of the starting point. 4-connected. Without TmpRas, mode 1 fails (like 1.3).
FL_STK          EQU 2048             ; pending seeds (x, y)
FL_MODE         EQU MK_SIZE          ; word
FL_TARGET       EQU MK_SIZE+2        ; word: target colour
FL_W            EQU MK_SIZE+4        ; word: width of the area
FL_SP           EQU MK_SIZE+6        ; long: top of the seed stack
FL_STKB         EQU MK_SIZE+10       ; long: base of the stack
FL_OVF          EQU MK_SIZE+14       ; word: stack overflowed
FL_LAYER        EQU MK_SIZE+16       ; long: layer locked for the whole Flood (spec §7.1) | 0
FL_SIZE         EQU MK_SIZE+20
gfx_Flood:
        movem.l d2-d7/a2-a5,-(sp)
        lea     -FL_SIZE(sp),sp
        move.l  sp,a5
        move.l  a1,MK_RP(a5)
        clr.l   FL_LAYER(a5)
        move.w  d2,FL_MODE(a5)
        move.w  d0,d6                ; seed
        move.w  d1,d7
        tst.w   d2
        beq.s   .fl_m0
        tst.l   rp_TmpRas(a1)
        beq     .fl_fail
.fl_m0:
        clr.w   MK_X0(a5)            ; area: the layer (layer coordinates) or the BitMap
        clr.w   MK_Y0(a5)
        move.l  rp_Layer(a1),d0
        beq.s   .fl_bm
        move.l  d0,FL_LAYER(a5)      ; the layer stays locked until the end: its bounds and contents are stable
        movem.l d0/a1/a6,-(sp)
        move.l  d0,a0
        lea     LY_LOCK(a0),a0
        move.l  ($4).w,a6
        jsr     LVO_OBTAINSEMAPHORE(a6)
        movem.l (sp)+,d0/a1/a6
        move.l  d0,a0
        move.w  LY_BOUNDS+4(a0),d0
        sub.w   LY_BOUNDS(a0),d0
        addq.w  #1,d0
        move.w  LY_BOUNDS+6(a0),d1
        sub.w   LY_BOUNDS+2(a0),d1
        addq.w  #1,d1
        bra.s   .fl_sz
.fl_bm:
        move.l  rp_BitMap(a1),a0
        move.w  bm_BytesPerRow(a0),d0
        lsl.w   #3,d0
        move.w  bm_Rows(a0),d1
.fl_sz:
        move.w  d0,FL_W(a5)
        clr.l   MK_ALLOC(a5)         ; the mask is always allocated: the TmpRas is not necessarily large enough
        movem.l d0-d1,-(sp)
        add.w   #15,d0
        lsr.w   #4,d0
        add.w   d0,d0
        move.w  d0,MK_L(a5)
        move.w  d1,MK_H(a5)
        mulu    d1,d0
        move.l  d0,d3
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        move.l  a6,-(sp)
        move.l  ($4).w,a6
        jsr     LVO_ALLOCMEM(a6)
        move.l  (sp)+,a6
        movem.l (sp)+,d4-d5
        move.l  d0,MK_BUF(a5)
        beq     .fl_fail
        move.l  d3,MK_ALLOC(a5)
        move.l  #FL_STK*4,d0
        move.l  #MEMF_PUBLIC,d1
        move.l  a6,-(sp)
        move.l  ($4).w,a6
        jsr     LVO_ALLOCMEM(a6)
        move.l  (sp)+,a6
        move.l  d0,FL_STKB(a5)
        beq     .fl_free1
        move.l  d0,FL_SP(a5)
        clr.w   FL_OVF(a5)
        ; target colour
        move.w  d6,d0
        move.w  d7,d1
        bsr     fl_read
        move.w  d0,FL_TARGET(a5)
        tst.w   FL_MODE(a5)
        bne.s   .fl_t1
        move.l  MK_RP(a5),a1
        moveq   #0,d0
        move.b  rp_AOlPen(a1),d0
        move.w  d0,FL_TARGET(a5)
.fl_t1:
        move.w  d6,d0
        move.w  d7,d1
        bsr     fl_push
.fl_loop:
        bsr     fl_pop
        bmi.s   .fl_more
        bsr     fl_span
        bra.s   .fl_loop
.fl_more:
        tst.w   FL_OVF(a5)           ; stack overflowed: new seeds at the edge of the already filled areas
        beq.s   .fl_done
        clr.w   FL_OVF(a5)
        bsr     fl_rescan
        bra.s   .fl_loop
.fl_done:
        bsr     mk_render
        move.l  FL_STKB(a5),a1
        move.l  #FL_STK*4,d0
        move.l  a6,-(sp)
        move.l  ($4).w,a6
        jsr     LVO_FREEMEM(a6)
        move.l  (sp)+,a6
        bsr     mk_free
        moveq   #1,d0
        bra.s   .fl_ret
.fl_free1:
        bsr     mk_free
.fl_fail:
        moveq   #0,d0
.fl_ret:
        move.l  FL_LAYER(a5),d1
        beq.s   .fl_nolk
        movem.l d0/a6,-(sp)
        move.l  d1,a0
        lea     LY_LOCK(a0),a0
        move.l  ($4).w,a6
        jsr     LVO_RELEASESEMAPHORE(a6)
        movem.l (sp)+,d0/a6
.fl_nolk:
        lea     FL_SIZE(sp),sp
        movem.l (sp)+,d2-d7/a2-a5
        rts

; fl_read(d0 = x, d1 = y) -> d0 = colour (ReadPixel, LVO; -1 outside the layer). Preserves d1-d7/a1-a6.
fl_read:
        movem.l d1/a1,-(sp)
        ext.l   d0
        ext.l   d1
        move.l  MK_RP(a5),a1
        jsr     LVO_READPIXEL(a6)
        movem.l (sp)+,d1/a1
        rts

; fl_ok(d0 = x, d1 = y) -> Z = 0 if the point must be filled (in the area, not visited, right colour). Preserves
; d1-d7/a1-a6.
fl_ok:
        tst.w   d0
        bmi.s   .fo_no
        cmp.w   FL_W(a5),d0
        bge.s   .fo_no
        tst.w   d1
        bmi.s   .fo_no
        cmp.w   MK_H(a5),d1
        bge.s   .fo_no
        movem.l d0-d2/a0,-(sp)
        move.w  d1,d2
        mulu    MK_L(a5),d2
        move.l  MK_BUF(a5),a0
        add.l   d2,a0
        move.w  d0,d2
        lsr.w   #3,d2
        not.w   d0
        and.w   #7,d0
        btst    d0,0(a0,d2.w)
        movem.l (sp)+,d0-d2/a0
        bne.s   .fo_no
        movem.l d0-d1,-(sp)
        bsr.s   fl_read
        tst.w   FL_MODE(a5)
        bne.s   .fo_m1
        tst.l   d0                   ; mode 0: everything except the boundary and unreadable points (-1)
        bmi.s   .fo_n2
        cmp.w   FL_TARGET(a5),d0
        beq.s   .fo_n2
        bra.s   .fo_y2
.fo_m1:
        cmp.w   FL_TARGET(a5),d0     ; mode 1: the starting colour only
        bne.s   .fo_n2
.fo_y2:
        movem.l (sp)+,d0-d1
        moveq   #1,d0
        rts
.fo_n2:
        movem.l (sp)+,d0-d1
.fo_no:
        moveq   #0,d0
        rts

; fl_push(d0 = x, d1 = y): seed pushed (stack full: FL_OVF). fl_pop -> d0/d1, N = 1 if the stack is empty.
fl_push:
        move.l  a0,-(sp)
        move.l  FL_SP(a5),a0
        move.l  FL_STKB(a5),-(sp)
        add.l   #FL_STK*4,(sp)
        cmp.l   (sp)+,a0
        bhs.s   .fp_ovf
        move.w  d0,(a0)+
        move.w  d1,(a0)+
        move.l  a0,FL_SP(a5)
        move.l  (sp)+,a0
        rts
.fp_ovf:
        move.w  #1,FL_OVF(a5)
        move.l  (sp)+,a0
        rts
fl_pop:
        move.l  FL_SP(a5),a0
        cmp.l   FL_STKB(a5),a0
        bls.s   .fq_empty
        move.w  -(a0),d1
        move.w  -(a0),d0
        move.l  a0,FL_SP(a5)
        moveq   #0,d2
        rts
.fq_empty:
        moveq   #-1,d2
        rts

; fl_span(d0 = x, d1 = y): extends the seed left and right, marks the run in the mask, then pushes one seed
; per fillable run of the lines above and below. Preserves a5/a6.
fl_span:
        move.w  d0,d4
        move.w  d1,d5
        bsr     fl_ok
        beq.s   .fs_r
        move.w  d4,d6                ; d6 = left
.fs_l:
        move.w  d6,d0
        subq.w  #1,d0
        move.w  d5,d1
        bsr     fl_ok
        beq.s   .fs_rt
        subq.w  #1,d6
        bra.s   .fs_l
.fs_rt:
        move.w  d4,d7                ; d7 = right
.fs_r1:
        move.w  d7,d0
        addq.w  #1,d0
        move.w  d5,d1
        bsr     fl_ok
        beq.s   .fs_mark
        addq.w  #1,d7
        bra.s   .fs_r1
.fs_mark:
        clr.w   MK_OP(a5)
        move.w  d6,d3
.fs_mk:
        move.w  d3,d0
        move.w  d5,d1
        bsr     mk_bit
        addq.w  #1,d3
        cmp.w   d7,d3
        ble.s   .fs_mk
        move.w  d5,d1                ; seeds above then below
        subq.w  #1,d1
        bsr.s   fl_seeds
        move.w  d5,d1
        addq.w  #1,d1
        bra.s   fl_seeds
.fs_r:
        rts

; fl_seeds(d1 = line, d6..d7 = columns): one seed per fillable run of the line. Clobbers d0/d2/d3.
fl_seeds:
        move.w  d6,d3
        moveq   #0,d2                ; inside a run?
.fd_lp:
        cmp.w   d7,d3
        bgt.s   .fd_r
        move.w  d3,d0
        bsr     fl_ok
        beq.s   .fd_no
        tst.w   d2
        bne.s   .fd_nx
        moveq   #1,d2
        move.w  d3,d0
        bsr     fl_push
        bra.s   .fd_nx
.fd_no:
        moveq   #0,d2
.fd_nx:
        addq.w  #1,d3
        bra.s   .fd_lp
.fd_r:
        rts

; fl_rescan: after a stack overflow, each marked point with a neighbour (above or below) still to be filled
; becomes a seed again. Preserves a5/a6.
fl_rescan:
        moveq   #0,d5
.rs_row:
        cmp.w   MK_H(a5),d5
        bge.s   .rs_r
        moveq   #0,d4
.rs_col:
        cmp.w   FL_W(a5),d4
        bge.s   .rs_nr
        move.w  d5,d2
        mulu    MK_L(a5),d2
        move.l  MK_BUF(a5),a0
        add.l   d2,a0
        move.w  d4,d2
        lsr.w   #3,d2
        move.w  d4,d0
        not.w   d0
        and.w   #7,d0
        btst    d0,0(a0,d2.w)
        beq.s   .rs_nc
        move.w  d4,d0
        move.w  d5,d1
        subq.w  #1,d1
        bsr     fl_ok
        beq.s   .rs_dn
        move.w  d4,d0
        move.w  d5,d1
        subq.w  #1,d1
        bsr     fl_push
.rs_dn:
        move.w  d4,d0
        move.w  d5,d1
        addq.w  #1,d1
        bsr     fl_ok
        beq.s   .rs_nc
        move.w  d4,d0
        move.w  d5,d1
        addq.w  #1,d1
        bsr     fl_push
.rs_nc:
        addq.w  #1,d4
        bra.s   .rs_col
.rs_nr:
        addq.w  #1,d5
        bra.s   .rs_row
.rs_r:
        rts
