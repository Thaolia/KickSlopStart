; src/graphics/draw.s — graphics.library drawing primitives into a RastPort (planar BitMap, CPU rendering).
; SetAPen/SetBPen/SetDrMd/Move/Draw/WritePixel/RectFill/SetRast/ClearEOL/ClearScreen/ScrollRaster/Text/TextLength/SetFont/
; InitRastPort/InitBitMap/ReadPixel/BltBitMap. If rp_Layer is set, its bounds give the offset (coordinates
; relative to the layer) and drawing goes through its ClipRects (layers.library): visible ClipRect -> the
; RastPort's BitMap; hidden ClipRect with backup (cr_BitMap, origin in cr_p1) -> the backup; hidden without
; backup -> nothing. The layer lock is held during drawing (dr_ctx ... dr_end). Without a layer: a single
; pseudo-ClipRect = the whole BitMap. Text: the RastPort's font (any TextFont, topaz 8 by default),
; drawn in JAM1/JAM2/COMPLEMENT/INVERSVID, algorithmic bold and underline. ScrollRaster: vertical scrolling only.
; Memory accessed BYTE by byte (a BitMap row can start at an odd address).
; Beyond the convention (d2-d7/a2-a6), all these functions leave a1 (the RastPort) intact: intuition and
; console.device chain their calls on the same RastPort without reloading it.
; IMPLEMENTATION track ("clean"): graphics.library AutoDocs + public NDK includes. NO ROM reading.

                include "exec.i"
                include "graphics.i"

                xdef    gfx_BltTemplate
                xdef    gfx_SetAPen
                xdef    gfx_SetBPen
                xdef    gfx_SetDrMd
                xdef    gfx_Move
                xdef    gfx_Draw
                xdef    gfx_WritePixel
                xdef    gfx_RectFill
                xdef    gfx_SetRast
                xdef    gfx_ClearEOL
                xdef    gfx_ClearScreen
                xdef    gfx_ScrollRaster
                xdef    gfx_Text
                xdef    gfx_TextLength
                xdef    gfx_SetFont
                xdef    gfx_InitRastPort
                xdef    gfx_InitBitMap
                xdef    gfx_BltBitMapRastPort
                xdef    gfx_BltMaskBitMapRastPort
                xdef    gfx_ClipBlit
                xdef    gfx_BltBitMap
                xdef    gfx_ReadPixel
                xdef    gfx_LockLayerRom
                xdef    gfx_UnlockLayerRom
                xdef    gfx_AttemptLockLayerRom
                xdef    gfx_putrow
                xref    topaz8_font
                xref    gfx_OwnBlitter
                xref    gfx_DisownBlitter
                xref    gfx_OrRectRegion

; --- drawing context (on the stack, pointed to by a5) ---
DC_OX           EQU 0                ; X offset (Layer bounds); WORD
DC_OY           EQU 2
DC_MINX         EQU 4                ; absolute clipping rectangle (inclusive)
DC_MINY         EQU 6
DC_MAXX         EQU 8
DC_MAXY         EQU 10
DC_BM           EQU 12               ; BitMap
DC_RP           EQU 16               ; RastPort
DC_MINTERM      EQU 20               ; byte: minterm of the bit copies (dr_bits)
DC_LAYER        EQU 22               ; layer of the RastPort (0 = none)
DC_FIRST        EQU 26               ; first ClipRect to walk (those of the layer, or DC_PSEUDO)
DC_CMINX        EQU 30               ; current ClipRect: absolute clipping rectangle
DC_CMINY        EQU 32
DC_CMAXX        EQU 34
DC_CMAXY        EQU 36
DC_CBM          EQU 38               ; BitMap to draw into
DC_BX           EQU 42               ; origin of this BitMap in absolute coordinates (0 for the screen)
DC_BY           EQU 44
DC_PSEUDO       EQU 46               ; pseudo-ClipRect without a layer (Next, prev, lobs, BitMap, bounds)
DC_SIZE         EQU 70
; ClipRect fields read here (graphics/clip.h)
CR_NEXT         EQU 0
CR_LOBS         EQU 8
CR_BITMAP       EQU 12
CR_MINX         EQU 16
CR_ORGX         EQU 24               ; origin of the backup (layers private: cr_p1)
CR_ORGY         EQU 26
LY_CLIPRECT     EQU 8
LY_FLAGS        EQU 30
LY_LOCK         EQU 72
LY_DAMAGE       EQU 156
LAYERREFRESH    EQU $80

; dr_ctx(a1 = RastPort, a5 = context): fills the context and takes the layer lock. Clobbers d0/d1/a0.
dr_ctx:
        bsr     dr_ctx0
        move.l  rp_Layer(a1),d0
        move.l  d0,DC_LAYER(a5)
        beq.s   .cx_pseudo
        move.l  d0,a0
        move.l  LY_CLIPRECT(a0),DC_FIRST(a5)
        movem.l a1/a6,-(sp)
        lea     LY_LOCK(a0),a0
        move.l  ($4).w,a6
        jsr     LVO_OBTAINSEMAPHORE(a6)
        movem.l (sp)+,a1/a6
        rts
.cx_pseudo:
        lea     DC_PSEUDO(a5),a0     ; visible pseudo-ClipRect = the whole clipping area
        move.l  a0,DC_FIRST(a5)
        clr.l   CR_NEXT(a0)
        clr.l   CR_LOBS(a0)
        clr.l   CR_BITMAP(a0)
        move.l  DC_MINX(a5),CR_MINX(a0)
        move.l  DC_MAXX(a5),CR_MINX+4(a0)
        rts
; dr_end(a5): releases the layer lock. Preserves all registers.
dr_end:
        tst.l   DC_LAYER(a5)
        beq.s   .de_r
        movem.l d0-d1/a0-a1/a6,-(sp)
        move.l  DC_LAYER(a5),a0
        lea     LY_LOCK(a0),a0
        move.l  ($4).w,a6
        jsr     LVO_RELEASESEMAPHORE(a6)
        movem.l (sp)+,d0-d1/a0-a1/a6
.de_r:
        rts
; dr_crset(a0 = ClipRect, a5): current ClipRect -> DC_C*, DC_CBM, DC_BX/BY. Z = 1 if unusable (hidden without
; backup, or empty once clipped to the BitMap). Preserves everything except d0.
dr_crset:
        tst.l   CR_LOBS(a0)
        beq.s   .cs_vis
        move.l  CR_BITMAP(a0),d0
        beq     .cs_r                ; Z = 1
        move.l  d0,DC_CBM(a5)
        move.l  CR_ORGX(a0),DC_BX(a5)   ; BX, BY
        move.l  CR_MINX(a0),DC_CMINX(a5)
        move.l  CR_MINX+4(a0),DC_CMAXX(a5)
        bra.s   .cs_ok
.cs_vis:
        move.l  DC_BM(a5),DC_CBM(a5)
        clr.l   DC_BX(a5)
        move.l  CR_MINX(a0),DC_CMINX(a5)   ; ∩ clipping area (BitMap bounds)
        move.l  CR_MINX+4(a0),DC_CMAXX(a5)
        move.w  DC_MINX(a5),d0
        cmp.w   DC_CMINX(a5),d0
        ble.s   .cs_1
        move.w  d0,DC_CMINX(a5)
.cs_1:
        move.w  DC_MINY(a5),d0
        cmp.w   DC_CMINY(a5),d0
        ble.s   .cs_2
        move.w  d0,DC_CMINY(a5)
.cs_2:
        move.w  DC_MAXX(a5),d0
        cmp.w   DC_CMAXX(a5),d0
        bge.s   .cs_3
        move.w  d0,DC_CMAXX(a5)
.cs_3:
        move.w  DC_MAXY(a5),d0
        cmp.w   DC_CMAXY(a5),d0
        bge.s   .cs_ok
        move.w  d0,DC_CMAXY(a5)
.cs_ok:
        move.w  DC_CMINX(a5),d0      ; empty?
        cmp.w   DC_CMAXX(a5),d0
        bgt.s   .cs_empty
        move.w  DC_CMINY(a5),d0
        cmp.w   DC_CMAXY(a5),d0
        bgt.s   .cs_empty
        moveq   #1,d0                ; Z = 0: usable
        rts
.cs_empty:
        moveq   #0,d0
.cs_r:
        rts

; dr_ctx0(a1 = RastPort, a5): offset, clipping area (layer bounds ∩ BitMap), BitMap.
dr_ctx0:
        move.l  a1,DC_RP(a5)
        move.l  rp_BitMap(a1),a0
        move.l  a0,DC_BM(a5)
        clr.l   DC_OX(a5)            ; OX = OY = 0
        clr.l   DC_MINX(a5)          ; MINX = MINY = 0
        move.w  bm_BytesPerRow(a0),d0
        lsl.w   #3,d0
        subq.w  #1,d0
        move.w  d0,DC_MAXX(a5)
        move.w  bm_Rows(a0),d0
        subq.w  #1,d0
        move.w  d0,DC_MAXY(a5)
        move.l  rp_Layer(a1),d0
        beq.s   .dc_ret
        move.l  d0,a0
        move.w  lr_MinX(a0),DC_OX(a5)
        move.w  lr_MinY(a0),DC_OY(a5)
        move.w  lr_MinX(a0),d0       ; intersection of Layer bounds / BitMap
        cmp.w   DC_MINX(a5),d0
        ble.s   .dc_x0
        move.w  d0,DC_MINX(a5)
.dc_x0:
        move.w  lr_MinY(a0),d0
        cmp.w   DC_MINY(a5),d0
        ble.s   .dc_y0
        move.w  d0,DC_MINY(a5)
.dc_y0:
        move.w  lr_MaxX(a0),d0
        cmp.w   DC_MAXX(a5),d0
        bge.s   .dc_x1
        move.w  d0,DC_MAXX(a5)
.dc_x1:
        move.w  lr_MaxY(a0),d0
        cmp.w   DC_MAXY(a5),d0
        bge.s   .dc_ret
        move.w  d0,DC_MAXY(a5)
.dc_ret:
        rts

; dr_span(a5 = context, d0.w = x0, d1.w = y, d2.w = x1 (absolute, x0 <= x1), d3.b = pen): fills the pixels
; [x0..x1] of row y with the pen (rp_DrawMode COMPLEMENT: invert) in each usable ClipRect, planes
; filtered by rp_Mask. Preserves everything.
dr_span:
        movem.l d0/a0,-(sp)
        move.l  DC_FIRST(a5),a0
.ds_lp:
        cmpa.w  #0,a0
        beq.s   .ds_r
        cmp.w   CR_MINX+2(a0),d1     ; the row must cross the ClipRect
        blt.s   .ds_n
        cmp.w   CR_MINX+6(a0),d1
        bgt.s   .ds_n
        bsr     dr_crset
        beq.s   .ds_n
        move.l  (sp),d0
        bsr     dr_span1
.ds_n:
        move.l  CR_NEXT(a0),a0
        bra.s   .ds_lp
.ds_r:
        movem.l (sp)+,d0/a0
        rts
; dr_span1: like dr_span, within the current ClipRect (DC_C*, DC_CBM, origin DC_BX/BY). Preserves everything.
dr_span1:
        movem.l d0-d7/a0-a3,-(sp)
        cmp.w   DC_CMINY(a5),d1
        blt     .sp_ret
        cmp.w   DC_CMAXY(a5),d1
        bgt     .sp_ret
        cmp.w   DC_CMINX(a5),d0
        bge.s   .sp_c0
        move.w  DC_CMINX(a5),d0
.sp_c0:
        cmp.w   DC_CMAXX(a5),d2
        ble.s   .sp_c1
        move.w  DC_CMAXX(a5),d2
.sp_c1:
        cmp.w   d2,d0
        bgt     .sp_ret
        move.l  DC_CBM(a5),a3
        sub.w   DC_BX(a5),d0         ; coordinates within this BitMap (the X origin is a multiple of 16)
        sub.w   DC_BX(a5),d2
        sub.w   DC_BY(a5),d1
        moveq   #0,d4
        move.w  bm_BytesPerRow(a3),d4
        mulu    d1,d4
        move.l  d4,a1                ; a1 = offset of the row
        move.w  d0,d5
        lsr.w   #3,d5                ; d5 = start byte
        move.w  d2,d6
        lsr.w   #3,d6
        sub.w   d5,d6                ; d6 = bytes after the first one
        moveq   #-1,d7               ; d7.b = start mask: pixels >= x0
        move.w  d0,d4
        and.w   #7,d4
        lsr.b   d4,d7
        move.w  d2,d4                ; d2.b = end mask: pixels <= x1
        and.w   #7,d4
        moveq   #7,d1
        sub.w   d4,d1
        moveq   #-1,d2
        lsl.b   d1,d2
        tst.w   d6
        bne.s   .sp_masks
        and.b   d2,d7                ; a single byte
.sp_masks:
        move.l  DC_RP(a5),a0
        move.b  rp_Mask(a0),d1       ; d1.b = allowed planes
        moveq   #0,d0
        move.b  rp_DrawMode(a0),d0
        and.b   #COMPLEMENT,d0
        move.l  d0,a2                ; a2 != 0: inversion
        moveq   #0,d0
        move.b  bm_Depth(a3),d0
        subq.w  #1,d0                ; d0 = plane counter (dbra)
        lea     bm_Planes(a3),a3
.sp_plane:
        move.l  (a3)+,a0
        btst    #0,d1
        beq.s   .sp_pnext
        add.l   a1,a0
        add.w   d5,a0                ; a0 = first byte
        move.b  d7,d4
        bsr.s   .sp_ap
        tst.w   d6
        beq.s   .sp_pnext
        move.w  d6,d4
        subq.w  #2,d4                ; full bytes - 1 (d6 - 1 full bytes)
        bmi.s   .sp_last
        cmpa.w  #0,a2
        bne.s   .sp_minv
        btst    #0,d3
        beq.s   .sp_mclr
.sp_mset:
        st      (a0)+
        dbra    d4,.sp_mset
        bra.s   .sp_last
.sp_mclr:
        clr.b   (a0)+
        dbra    d4,.sp_mclr
        bra.s   .sp_last
.sp_minv:
        not.b   (a0)+
        dbra    d4,.sp_minv
.sp_last:
        move.b  d2,d4
        bsr.s   .sp_ap
.sp_pnext:
        lsr.b   #1,d1
        lsr.b   #1,d3                ; pen bit for the next plane
        dbra    d0,.sp_plane
.sp_ret:
        movem.l (sp)+,d0-d7/a0-a3
        rts
; .sp_ap: applies mask d4.b to byte (a0)+ according to bit 0 of d3 (pen) or the inversion (a2 != 0).
.sp_ap:
        cmpa.w  #0,a2
        beq.s   .ap_set
        eor.b   d4,(a0)+
        rts
.ap_set:
        btst    #0,d3
        beq.s   .ap_clr
        or.b    d4,(a0)+
        rts
.ap_clr:
        not.b   d4
        and.b   d4,(a0)+
        rts

; dr_rect(a5 = context, d0/d1 = top-left corner, d2/d3 = bottom-right corner (absolute, inclusive), d4.b = pen A,
; d5.b = pen B, a0 = pattern (0: solid), d6.w = pattern row mask): fills the rectangle in each
; usable ClipRect, planes filtered by rp_Mask, according to rp_DrawMode. Solid: pen A (COMPLEMENT: inversion). Pattern:
; 1 bits in pen A (COMPLEMENT: inversion), 0 bits in pen B in JAM2 only, left alone otherwise; word for row y =
; pattern[(y - OY) & mask], bit 15 = pixel x such that (x - OX) ≡ 0 (mod 16). Clipping, masks and address computed once
; per ClipRect and per plane: the per-pixel cost no longer depends on the number of ClipRects. Preserves everything.
RC_X0           EQU 0                ; requested rectangle (absolute): X0 Y0 X1 Y1
RC_Y0           EQU 2
RC_X1           EQU 4
RC_Y1           EQU 6
RC_FG           EQU 8                ; byte: pen A
RC_BG           EQU 9                ; byte: pen B
RC_PAT          EQU 10               ; pattern (0: solid)
RC_PMASK        EQU 14               ; pattern row mask
RC_NB           EQU 16               ; bytes of the row after the first one
RC_FM           EQU 18               ; byte: mask of the first byte
RC_LM           EQU 19               ; byte: mask of the last byte
RC_ROWS         EQU 20               ; rows - 1
RC_BPR          EQU 22               ; bytes per row of the BitMap
RC_ROFF         EQU 24               ; offset of the first byte within a plane
RC_SHIFT        EQU 28               ; rotation of the pattern word (first pixel of the first byte -> bit 15)
RC_PROW         EQU 30               ; pattern row of the first row
RC_COMP         EQU 32               ; byte: COMPLEMENT
RC_JAM2         EQU 33               ; byte: 0 bits of the pattern in pen B
RC_F            EQU 34               ; byte: bit 0 = pen A of the current plane
RC_G            EQU 35               ; byte: bit 0 = pen B of the current plane
RC_PR           EQU 36               ; current pattern row
RC_RCNT         EQU 38               ; remaining rows (pattern)
RC_PW           EQU 40               ; rotated pattern word of the current row
RC_PSTEP        EQU 42               ; bytes of the pattern for one plane (multicolour pattern), 0 otherwise
RC_SIZE         EQU 44
dr_rect:
        movem.l d0-d7/a0-a4/a6,-(sp)
        lea     -RC_SIZE(sp),sp
        move.l  sp,a4
        movem.w d0-d3,RC_X0(a4)
        move.b  d4,RC_FG(a4)
        move.b  d5,RC_BG(a4)
        move.l  a0,RC_PAT(a4)
        move.w  d6,RC_PMASK(a4)
        swap    d6
        move.w  d6,RC_PSTEP(a4)
        move.l  DC_RP(a5),a0
        move.b  rp_DrawMode(a0),d4
        moveq   #COMPLEMENT,d5
        and.b   d4,d5
        sne     RC_COMP(a4)
        and.b   #JAM2|COMPLEMENT,d4
        cmp.b   #JAM2,d4
        seq     RC_JAM2(a4)
        move.l  DC_FIRST(a5),a3
.rc_lp:
        cmpa.w  #0,a3
        beq.s   .rc_ret
        movem.w RC_X0(a4),d0-d3
        cmp.w   CR_MINX+2(a3),d3     ; the rectangle must cross the ClipRect
        blt.s   .rc_n
        cmp.w   CR_MINX+6(a3),d1
        bgt.s   .rc_n
        cmp.w   CR_MINX(a3),d2
        blt.s   .rc_n
        cmp.w   CR_MINX+4(a3),d0
        bgt.s   .rc_n
        move.l  a3,a0
        bsr     dr_crset
        beq.s   .rc_n
        bsr.s   rc_one
.rc_n:
        move.l  CR_NEXT(a3),a3
        bra.s   .rc_lp
.rc_ret:
        lea     RC_SIZE(sp),sp
        movem.l (sp)+,d0-d7/a0-a4/a6
        rts
; rc_one(a4 = dr_rect variables, a5): the rectangle within the current ClipRect. Preserves a3-a5.
rc_one:
        movem.w RC_X0(a4),d0-d3
        cmp.w   DC_CMINX(a5),d0
        bge.s   .o_1
        move.w  DC_CMINX(a5),d0
.o_1:
        cmp.w   DC_CMAXX(a5),d2
        ble.s   .o_2
        move.w  DC_CMAXX(a5),d2
.o_2:
        cmp.w   d2,d0
        bgt     .o_ret
        cmp.w   DC_CMINY(a5),d1
        bge.s   .o_3
        move.w  DC_CMINY(a5),d1
.o_3:
        cmp.w   DC_CMAXY(a5),d3
        ble.s   .o_4
        move.w  DC_CMAXY(a5),d3
.o_4:
        cmp.w   d3,d1
        bgt     .o_ret
        move.w  d1,d4
        sub.w   DC_OY(a5),d4
        move.w  d4,RC_PROW(a4)
        sub.w   d1,d3
        move.w  d3,RC_ROWS(a4)
        move.l  DC_CBM(a5),a0
        sub.w   DC_BX(a5),d0         ; coordinates within this BitMap
        sub.w   DC_BX(a5),d2
        sub.w   DC_BY(a5),d1
        moveq   #0,d4
        move.w  bm_BytesPerRow(a0),d4
        move.w  d4,RC_BPR(a4)
        mulu    d1,d4
        moveq   #0,d5
        move.w  d0,d5
        lsr.w   #3,d5                ; d5 = start byte
        add.l   d5,d4
        move.l  d4,RC_ROFF(a4)
        move.w  d2,d6
        lsr.w   #3,d6
        sub.w   d5,d6
        move.w  d6,RC_NB(a4)
        moveq   #-1,d7               ; start mask: pixels >= x0
        move.w  d0,d4
        and.w   #7,d4
        lsr.b   d4,d7
        move.w  d2,d4                ; end mask: pixels <= x1
        not.w   d4
        and.w   #7,d4
        moveq   #-1,d3
        lsl.b   d4,d3
        tst.w   d6
        bne.s   .o_5
        and.b   d3,d7                ; a single byte
.o_5:
        move.b  d7,RC_FM(a4)
        move.b  d3,RC_LM(a4)
        lsl.w   #3,d5                ; absolute x of the 1st pixel of the 1st byte (the X origin is a multiple of 16)
        add.w   DC_BX(a5),d5
        sub.w   DC_OX(a5),d5
        and.w   #15,d5
        move.w  d5,RC_SHIFT(a4)
        move.l  DC_RP(a5),a1
        move.b  rp_Mask(a1),d6       ; d6 = allowed planes
        move.b  RC_FG(a4),d5         ; d5/d4: bit 0 = pen A/B of the current plane
        move.b  RC_BG(a4),d4
        moveq   #0,d7
        move.b  bm_Depth(a0),d7
        lea     bm_Planes(a0),a2
        move.l  RC_PAT(a4),-(sp)
        bra.s   .o_pe
.o_pl:
        move.l  (a2)+,a1
        btst    #0,d6
        beq.s   .o_pn
        adda.l  RC_ROFF(a4),a1
        bsr.s   rc_plane
.o_pn:
        lsr.b   #1,d6
        lsr.b   #1,d5
        lsr.b   #1,d4
        move.w  RC_PSTEP(a4),d0      ; multicolour pattern: block of the next plane
        add.w   d0,RC_PAT+2(a4)
        bcc.s   .o_pe
        addq.w  #1,RC_PAT(a4)
.o_pe:
        dbra    d7,.o_pl
        move.l  (sp)+,RC_PAT(a4)
.o_ret:
        rts
; rc_plane(a1 = first byte of the first row, d5.b/d4.b bit 0 = pens A/B of this plane, a4): fills the
; rectangle in one plane. Clobbers d0-d3/a0/a1/a6.
rc_plane:
        movem.l d4-d7/a2,-(sp)
        move.w  RC_ROWS(a4),d7
        tst.l   RC_PAT(a4)
        bne     .pl_pat
        tst.b   RC_COMP(a4)
        bne.s   .pl_inv
        btst    #0,d5
        beq.s   .pl_clr
.pl_set:
        move.l  a1,a0
        move.b  RC_FM(a4),d0
        or.b    d0,(a0)+
        move.w  RC_NB(a4),d1
        beq.s   .ps_nx
        subq.w  #1,d1
        moveq   #-1,d0
        bsr     rc_fill
        move.b  RC_LM(a4),d0
        or.b    d0,(a0)+
.ps_nx:
        adda.w  RC_BPR(a4),a1
        dbra    d7,.pl_set
        bra     .pl_ret
.pl_clr:
        move.l  a1,a0
        move.b  RC_FM(a4),d0
        not.b   d0
        and.b   d0,(a0)+
        move.w  RC_NB(a4),d1
        beq.s   .pc_nx
        subq.w  #1,d1
        moveq   #0,d0
        bsr     rc_fill
        move.b  RC_LM(a4),d0
        not.b   d0
        and.b   d0,(a0)+
.pc_nx:
        adda.w  RC_BPR(a4),a1
        dbra    d7,.pl_clr
        bra     .pl_ret
.pl_inv:
        move.l  a1,a0
        move.b  RC_FM(a4),d0
        eor.b   d0,(a0)+
        move.w  RC_NB(a4),d1
        beq.s   .pi_nx
        subq.w  #1,d1
        moveq   #-1,d0
        bsr     rc_finv
        move.b  RC_LM(a4),d0
        eor.b   d0,(a0)+
.pi_nx:
        adda.w  RC_BPR(a4),a1
        dbra    d7,.pl_inv
        bra     .pl_ret
; pattern: each byte becomes ((byte & K) | S) ^ X, K/S/X derived from the mask and the pattern bits (rc_kpx); the
; full bytes alternate the two bytes of the rotated word (even: high byte, odd: low byte).
.pl_pat:
        move.b  d5,RC_F(a4)
        move.b  d4,RC_G(a4)
        move.w  RC_PROW(a4),RC_PR(a4)
        move.w  d7,RC_RCNT(a4)
.pp_row:
        move.w  RC_PR(a4),d0
        and.w   RC_PMASK(a4),d0
        add.w   d0,d0
        move.l  RC_PAT(a4),a0
        move.w  0(a0,d0.w),d0
        move.w  RC_SHIFT(a4),d1
        rol.w   d1,d0
        move.w  d0,RC_PW(a4)
        move.l  a1,a0
        move.b  RC_FM(a4),d0
        move.b  RC_PW(a4),d1
        bsr     rc_kpx
        bsr     rc_apply
        move.w  RC_NB(a4),d1
        beq     .pp_nx
        moveq   #-1,d0               ; even full bytes -> d5/d6/d7
        move.b  RC_PW(a4),d1
        bsr     rc_kpx
        move.b  d2,d5
        move.b  d3,d6
        move.b  d4,d7
        moveq   #-1,d0               ; odd full bytes -> d2/d3/d4
        move.b  RC_PW+1(a4),d1
        bsr     rc_kpx
        move.w  RC_NB(a4),d1
        subq.w  #1,d1                ; full bytes, the first one odd
        beq.s   .pp_last
        move.l  a0,d0
        btst    #0,d0
        beq.s   .pp_even
        move.b  (a0),d0              ; odd address: one odd byte, then words (even, odd)
        and.b   d2,d0
        or.b    d3,d0
        eor.b   d4,d0
        move.b  d0,(a0)+
        subq.w  #1,d1
        lsl.w   #8,d5
        move.b  d2,d5
        lsl.w   #8,d6
        move.b  d3,d6
        lsl.w   #8,d7
        move.b  d4,d7
        exg     d2,d5
        exg     d3,d6
        exg     d4,d7
        bra.s   .pp_w
.pp_even:
        lsl.w   #8,d2                ; even address: words (odd, even)
        move.b  d5,d2
        lsl.w   #8,d3
        move.b  d6,d3
        lsl.w   #8,d4
        move.b  d7,d4
.pp_w:
        move.w  d1,d5
        lsr.w   #1,d5
        bra.s   .pp_we
.pp_wl:
        move.w  (a0),d0
        and.w   d2,d0
        or.w    d3,d0
        eor.w   d4,d0
        move.w  d0,(a0)+
.pp_we:
        dbra    d5,.pp_wl
        btst    #0,d1
        beq.s   .pp_last
        lsr.w   #8,d2                ; remaining byte: that of the high byte of the words
        lsr.w   #8,d3
        lsr.w   #8,d4
        bsr     rc_apply
.pp_last:
        move.b  RC_PW(a4),d1
        btst    #0,RC_NB+1(a4)
        beq.s   .pp_l
        move.b  RC_PW+1(a4),d1
.pp_l:
        move.b  RC_LM(a4),d0
        bsr.s   rc_kpx
        bsr.s   rc_apply
.pp_nx:
        adda.w  RC_BPR(a4),a1
        addq.w  #1,RC_PR(a4)
        subq.w  #1,RC_RCNT(a4)
        bpl     .pp_row
.pl_ret:
        movem.l (sp)+,d4-d7/a2
        rts
; rc_kpx(d0.b = mask, d1.b = pattern bits, a4) -> d2.b = K, d3.b = S, d4.b = X for ((byte & K) | S) ^ X.
; Clobbers d0/d1.
rc_kpx:
        move.b  d1,d4
        and.b   d0,d4                ; d4 = 1 bits in the mask
        not.b   d1
        and.b   d0,d1                ; d1 = 0 bits in the mask
        tst.b   RC_COMP(a4)
        beq.s   .kx_n
        moveq   #-1,d2               ; COMPLEMENT: inversion of the 1 bits only
        moveq   #0,d3
        rts
.kx_n:
        tst.b   RC_JAM2(a4)
        bne.s   .kx_j
        moveq   #0,d1
.kx_j:
        move.b  d4,d2
        or.b    d1,d2
        not.b   d2
        moveq   #0,d3
        btst    #0,RC_F(a4)
        beq.s   .kx_g
        or.b    d4,d3
.kx_g:
        btst    #0,RC_G(a4)
        beq.s   .kx_x
        or.b    d1,d3
.kx_x:
        moveq   #0,d4
        rts
; rc_apply(a0, d2/d3/d4 = K/S/X): (a0)+ = (((a0) & K) | S) ^ X. Clobbers d0.
rc_apply:
        move.b  (a0),d0
        and.b   d2,d0
        or.b    d3,d0
        eor.b   d4,d0
        move.b  d0,(a0)+
        rts
; rc_fill(a0, d1.w = byte count, d0.l = repeated value): writes d0 over d1 bytes starting at a0 (advanced), as
; longs as soon as the address is even. rc_finv: same walk, inversion by d0. Clobber d1/d2.
rc_fill:
        tst.w   d1
        beq.s   .fl_r
        move.l  a0,d2
        btst    #0,d2
        beq.s   .fl_al
        move.b  d0,(a0)+
        subq.w  #1,d1
.fl_al:
        move.w  d1,d2
        lsr.w   #2,d2
        bra.s   .fl_le
.fl_l:
        move.l  d0,(a0)+
.fl_le:
        dbra    d2,.fl_l
        btst    #1,d1
        beq.s   .fl_b
        move.w  d0,(a0)+
.fl_b:
        btst    #0,d1
        beq.s   .fl_r
        move.b  d0,(a0)+
.fl_r:
        rts
rc_finv:
        tst.w   d1
        beq.s   .fi_r
        move.l  a0,d2
        btst    #0,d2
        beq.s   .fi_al
        eor.b   d0,(a0)+
        subq.w  #1,d1
.fi_al:
        move.w  d1,d2
        lsr.w   #2,d2
        bra.s   .fi_le
.fi_l:
        eor.l   d0,(a0)+
.fi_le:
        dbra    d2,.fi_l
        btst    #1,d1
        beq.s   .fi_b
        eor.w   d0,(a0)+
.fi_b:
        btst    #0,d1
        beq.s   .fi_r
        eor.b   d0,(a0)+
.fi_r:
        rts

; dr_line(a5 = context, d4/d5 = start, d6/d7 = end (absolute)): segment in pen A in each usable
; ClipRect, planes filtered by rp_Mask (COMPLEMENT: inversion). Bresenham: e = dx - |dy|; at each point, step in x
; if 2e >= -|dy|, step in y if 2e <= dx. Within a ClipRect, the address follows the point (row ± BytesPerRow) and each
; plane gets a bset/bclr/bchg: no more ClipRect lookup per pixel. Preserves everything.
LN_X0           EQU 0                ; absolute start and end: X0 Y0 X1 Y1
LN_Y0           EQU 2
LN_X1           EQU 4
LN_Y1           EQU 6
LN_DX           EQU 8                ; |dx|
LN_DY           EQU 10               ; -|dy|
LN_SX           EQU 12               ; x step (±1)
LN_SY           EQU 14               ; y step (±1)
LN_BX0          EQU 16               ; absolute bounding box: BX0 BY0 BX1 BY1
LN_BY0          EQU 18
LN_BX1          EQU 20
LN_BY1          EQU 22
LN_MINX         EQU 24               ; current ClipRect within its BitMap: MINX MINY MAXX MAXY
LN_MINY         EQU 26
LN_MAXX         EQU 28
LN_MAXY         EQU 30
LN_EX           EQU 32               ; end point within this BitMap
LN_EY           EQU 34
LN_AE           EQU 36               ; end of list A (planes set to 1, or inverted)
LN_BE           EQU 40               ; end of list B (planes set to 0)
LN_COMP         EQU 44               ; byte: COMPLEMENT
LN_A            EQU 46               ; 8 planes at most
LN_B            EQU 78
LN_SIZE         EQU 110
dr_line:
        movem.l d0-d7/a0-a4/a6,-(sp)
        lea     -LN_SIZE(sp),sp
        move.l  sp,a4
        movem.w d4-d7,LN_X0(a4)
        move.w  d6,d0
        sub.w   d4,d0
        moveq   #1,d1
        move.w  d4,d2
        move.w  d6,d3
        tst.w   d0
        bpl.s   .ln_1
        neg.w   d0
        moveq   #-1,d1
        exg     d2,d3
.ln_1:
        move.w  d0,LN_DX(a4)
        move.w  d1,LN_SX(a4)
        move.w  d2,LN_BX0(a4)
        move.w  d3,LN_BX1(a4)
        move.w  d7,d0
        sub.w   d5,d0
        moveq   #1,d1
        move.w  d5,d2
        move.w  d7,d3
        tst.w   d0
        bpl.s   .ln_2
        neg.w   d0
        moveq   #-1,d1
        exg     d2,d3
.ln_2:
        neg.w   d0
        move.w  d0,LN_DY(a4)
        move.w  d1,LN_SY(a4)
        move.w  d2,LN_BY0(a4)
        move.w  d3,LN_BY1(a4)
        move.l  DC_RP(a5),a0
        moveq   #COMPLEMENT,d0
        and.b   rp_DrawMode(a0),d0
        sne     LN_COMP(a4)
        move.l  DC_FIRST(a5),a3
.ln_lp:
        cmpa.w  #0,a3
        beq.s   .ln_ret
        move.w  LN_BY1(a4),d0        ; the segment's box must cross the ClipRect
        cmp.w   CR_MINX+2(a3),d0
        blt.s   .ln_n
        move.w  LN_BY0(a4),d0
        cmp.w   CR_MINX+6(a3),d0
        bgt.s   .ln_n
        move.w  LN_BX1(a4),d0
        cmp.w   CR_MINX(a3),d0
        blt.s   .ln_n
        move.w  LN_BX0(a4),d0
        cmp.w   CR_MINX+4(a3),d0
        bgt.s   .ln_n
        move.l  a3,a0
        bsr     dr_crset
        beq.s   .ln_n
        bsr.s   ln_one
.ln_n:
        move.l  CR_NEXT(a3),a3
        bra.s   .ln_lp
.ln_ret:
        lea     LN_SIZE(sp),sp
        movem.l (sp)+,d0-d7/a0-a4/a6
        rts
; ln_one(a4 = dr_line variables, a5): the whole segment walked, points plotted within the current ClipRect.
; Preserves a3-a5.
ln_one:
        move.l  a3,-(sp)
        move.w  DC_BX(a5),d2
        move.w  DC_BY(a5),d3
        move.w  DC_CMINX(a5),d0
        sub.w   d2,d0
        move.w  d0,LN_MINX(a4)
        move.w  DC_CMAXX(a5),d0
        sub.w   d2,d0
        move.w  d0,LN_MAXX(a4)
        move.w  DC_CMINY(a5),d0
        sub.w   d3,d0
        move.w  d0,LN_MINY(a4)
        move.w  DC_CMAXY(a5),d0
        sub.w   d3,d0
        move.w  d0,LN_MAXY(a4)
        move.w  LN_X1(a4),d0
        sub.w   d2,d0
        move.w  d0,LN_EX(a4)
        move.w  LN_Y1(a4),d0
        sub.w   d3,d0
        move.w  d0,LN_EY(a4)
        move.l  DC_CBM(a5),a2        ; plane lists: A = bset (bchg in COMPLEMENT), B = bclr
        move.l  DC_RP(a5),a0
        move.b  rp_Mask(a0),d6
        move.b  rp_FgPen(a0),d5
        lea     LN_A(a4),a0
        lea     LN_B(a4),a1
        moveq   #0,d7
        move.b  bm_Depth(a2),d7
        move.w  bm_BytesPerRow(a2),d4
        lea     bm_Planes(a2),a2
        bra.s   .lo_pe
.lo_pl:
        move.l  (a2)+,d0
        btst    #0,d6
        beq.s   .lo_pn
        tst.b   LN_COMP(a4)
        bne.s   .lo_pa
        btst    #0,d5
        bne.s   .lo_pa
        move.l  d0,(a1)+
        bra.s   .lo_pn
.lo_pa:
        move.l  d0,(a0)+
.lo_pn:
        lsr.b   #1,d6
        lsr.b   #1,d5
.lo_pe:
        dbra    d7,.lo_pl
        move.l  a0,LN_AE(a4)
        move.l  a1,LN_BE(a4)
        move.w  LN_X0(a4),d0         ; d0/d1 = current point within this BitMap
        sub.w   d2,d0
        move.w  LN_Y0(a4),d1
        sub.w   d3,d1
        move.w  d4,d3
        muls    d1,d3
        move.l  d3,a3                ; a3 = offset of the point's row (may be negative outside the BitMap)
        moveq   #0,d2
        move.w  d4,d2
        tst.w   LN_SY(a4)
        bpl.s   .lo_sy
        neg.l   d2
.lo_sy:
        move.l  d2,a6                ; a6 = row step
        move.w  LN_DX(a4),d4
        move.w  LN_DY(a4),d5
        move.w  d4,d2
        add.w   d5,d2                ; d2 = error
.lo_pt:
        cmp.w   LN_MINX(a4),d0
        blt.s   .lo_np
        cmp.w   LN_MAXX(a4),d0
        bgt.s   .lo_np
        cmp.w   LN_MINY(a4),d1
        blt.s   .lo_np
        cmp.w   LN_MAXY(a4),d1
        bgt.s   .lo_np
        move.w  d0,d3
        lsr.w   #3,d3                ; d3 = byte
        move.w  d0,d7
        not.w   d7                   ; d7 = bit (modulo 8: 7 for the leftmost pixel)
        lea     LN_A(a4),a2
        tst.b   LN_COMP(a4)
        bne.s   .lo_c
.lo_s:
        cmpa.l  LN_AE(a4),a2
        beq.s   .lo_b0
        move.l  (a2)+,a0
        adda.l  a3,a0
        bset    d7,0(a0,d3.w)
        bra.s   .lo_s
.lo_b0:
        lea     LN_B(a4),a2
.lo_b:
        cmpa.l  LN_BE(a4),a2
        beq.s   .lo_np
        move.l  (a2)+,a0
        adda.l  a3,a0
        bclr    d7,0(a0,d3.w)
        bra.s   .lo_b
.lo_c:
        cmpa.l  LN_AE(a4),a2
        beq.s   .lo_np
        move.l  (a2)+,a0
        adda.l  a3,a0
        bchg    d7,0(a0,d3.w)
        bra.s   .lo_c
.lo_np:
        cmp.w   LN_EX(a4),d0
        bne.s   .lo_st
        cmp.w   LN_EY(a4),d1
        beq.s   .lo_ret
.lo_st:
        move.w  d2,d6
        add.w   d6,d6                ; 2e
        cmp.w   d5,d6
        blt.s   .lo_nx
        add.w   d5,d2
        add.w   LN_SX(a4),d0
.lo_nx:
        cmp.w   d4,d6
        bgt.s   .lo_pt
        add.w   d4,d2
        add.w   LN_SY(a4),d1
        adda.l  a6,a3
        bra     .lo_pt
.lo_ret:
        move.l  (sp)+,a3
        rts

; --- simple LVOs ---
gfx_SetAPen:                         ; SetAPen(rp a1, pen d0)
        move.b  d0,rp_FgPen(a1)
        rts
gfx_SetBPen:                         ; SetBPen(rp a1, pen d0)
        move.b  d0,rp_BgPen(a1)
        rts
gfx_SetDrMd:                         ; SetDrMd(rp a1, mode d0)
        move.b  d0,rp_DrawMode(a1)
        rts
gfx_Move:                            ; Move(rp a1, x d0, y d1)
        move.w  d0,rp_cp_x(a1)
        move.w  d1,rp_cp_y(a1)
        rts
gfx_TextLength:                      ; TextLength(rp a1, string a0, count d0) -> width in pixels (like Text)
        movem.l d2-d3/a2-a3,-(sp)
        bsr     tx_font
        move.l  a0,a3
        move.w  d0,d3
        moveq   #0,d2
.tl_lp:
        subq.w  #1,d3
        bmi.s   .tl_r
        moveq   #0,d0
        move.b  (a3)+,d0
        bsr     tx_index
        bsr     tx_metrics
        add.w   d1,d0
        add.w   rp_TxSpacing(a1),d0
        add.w   d0,d2
        bra.s   .tl_lp
.tl_r:
        move.w  d2,d0
        ext.l   d0
        movem.l (sp)+,d2-d3/a2-a3
        rts
; SetFont(rp a1, font a0): font and metrics of the RastPort (0: ignored). D0 is not touched, as in 1.3:
; Preferences tests on return the D0 left by its OpenFont.
gfx_SetFont:
        cmpa.w  #0,a0
        beq.s   .sf_r
        move.l  a0,rp_Font(a1)
        move.w  tf_YSize(a0),rp_TxHeight(a1)
        move.w  tf_XSize(a0),rp_TxWidth(a1)
        move.w  tf_Baseline(a0),rp_TxBaseline(a1)
.sf_r:
        rts

; InitRastPort(rp a1, a6 = GfxBase): RastPort zeroed, Mask/FgPen/AOlPen/LinePtrn = -1, DrawMode = JAM2, default
; font (gb_DefaultFont).
gfx_InitRastPort:
        move.l  a1,a0
        moveq   #rp_SIZEOF/2-1,d0
.ir_clr:
        clr.w   (a0)+
        dbra    d0,.ir_clr
        st      rp_Mask(a1)
        st      rp_FgPen(a1)
        st      rp_AOlPen(a1)
        move.b  #JAM2,rp_DrawMode(a1)
        move.w  #-1,rp_LinePtrn(a1)
        move.l  gb_DefaultFont(a6),a0
        cmpa.w  #0,a0
        bne.s   gfx_SetFont
        lea     topaz8_font,a0
        bra.s   gfx_SetFont

; InitBitMap(bm a0, depth d0, width d1, height d2): BytesPerRow = width rounded to a word; planes not touched.
gfx_InitBitMap:
        add.w   #15,d1
        lsr.w   #4,d1
        add.w   d1,d1
        move.w  d1,bm_BytesPerRow(a0)
        move.w  d2,bm_Rows(a0)
        clr.b   4(a0)                ; bm_Flags
        move.b  d0,bm_Depth(a0)
        clr.w   6(a0)                ; bm_Pad
        rts

; WritePixel(rp a1, x d0, y d1) -> 0: one pixel in pen A.
gfx_WritePixel:
        movem.l d2-d3/a5,-(sp)
        lea     -DC_SIZE(sp),sp
        move.l  sp,a5
        movem.w d0-d1,-(sp)
        bsr     dr_ctx
        movem.w (sp)+,d0-d1
        add.w   DC_OX(a5),d0
        add.w   DC_OY(a5),d1
        move.w  d0,d2
        move.b  rp_FgPen(a1),d3
        bsr     dr_span
        bsr     dr_end
        lea     DC_SIZE(sp),sp
        movem.l (sp)+,d2-d3/a5
        moveq   #0,d0
        rts

; RectFill(rp a1, xmin d0, ymin d1, xmax d2, ymax d3): rectangle in pen A (relative to the Layer), SetAfPt pattern
; if there is one (dr_rect; AreaPtSz = -n: multicolour pattern, 2^n words per plane, consecutive planes). AREAOUTLINE:
; interior (shrunk by one pixel on each side in COMPLEMENT, so as not to invert the edge twice), then outline
; Move/Draw (LVO) in AOlPen and JAM1; cp stays at (xmin, ymin) (spec graphics-area-v34 §8).
gfx_RectFill:
        btst    #3,rp_Flags+1(a1)    ; AREAOUTLINE
        bne.s   rf_outline
rf_fill:
        movem.l d2-d7/a5,-(sp)
        lea     -DC_SIZE(sp),sp
        move.l  sp,a5
        movem.w d0-d3,-(sp)
        bsr     dr_ctx
        movem.w (sp)+,d0-d3
        add.w   DC_OX(a5),d0
        add.w   DC_OX(a5),d2
        add.w   DC_OY(a5),d1
        add.w   DC_OY(a5),d3
        move.b  rp_FgPen(a1),d4
        move.b  rp_BgPen(a1),d5
        move.l  rp_AreaPtrn(a1),a0
        moveq   #0,d6                ; d6 = step between planes (high word) | row mask
        move.b  rp_AreaPtSz(a1),d7
        bpl.s   .rf_mono
        neg.b   d7
        moveq   #2,d6
        lsl.w   d7,d6
        swap    d6
.rf_mono:
        move.w  #1,d6
        lsl.w   d7,d6
        subq.w  #1,d6
        bsr     dr_rect
        bsr     dr_end
        lea     DC_SIZE(sp),sp
        movem.l (sp)+,d2-d7/a5
        rts
rf_outline:
        movem.l d2-d5/a2,-(sp)
        move.l  a1,a2
        movem.w d0-d3,-(sp)
        btst    #1,rp_DrawMode(a2)   ; COMPLEMENT
        beq.s   .ro_fill
        addq.w  #1,d0
        addq.w  #1,d1
        subq.w  #1,d2
        subq.w  #1,d3
        cmp.w   d2,d0
        bgt.s   .ro_edge
        cmp.w   d3,d1
        bgt.s   .ro_edge
.ro_fill:
        bsr     rf_fill
.ro_edge:
        movem.w (sp)+,d2-d5          ; xmin ymin xmax ymax
        move.b  rp_FgPen(a2),-(sp)
        move.b  rp_DrawMode(a2),-(sp)
        move.l  a2,a1
        moveq   #0,d0
        move.b  rp_AOlPen(a2),d0
        jsr     LVO_SETAPEN(a6)
        move.l  a2,a1
        moveq   #JAM1,d0
        jsr     LVO_SETDRMD(a6)
        move.l  a2,a1
        move.l  d2,d0
        move.l  d3,d1
        jsr     LVO_MOVE(a6)
        move.l  a2,a1
        move.l  d2,d0
        move.l  d5,d1
        jsr     LVO_DRAW(a6)
        move.l  a2,a1
        move.l  d4,d0
        move.l  d5,d1
        jsr     LVO_DRAW(a6)
        move.l  a2,a1
        move.l  d4,d0
        move.l  d3,d1
        jsr     LVO_DRAW(a6)
        move.l  a2,a1
        move.l  d2,d0
        move.l  d3,d1
        jsr     LVO_DRAW(a6)
        moveq   #0,d0
        move.b  (sp)+,d0
        move.l  a2,a1
        jsr     LVO_SETDRMD(a6)
        moveq   #0,d0
        move.b  (sp)+,d0
        move.l  a2,a1
        jsr     LVO_SETAPEN(a6)
        movem.l (sp)+,d2-d5/a2
        rts

; SetRast(rp a1, pen d0): fills the whole RastPort area (Layer bounds, else the BitMap).
gfx_SetRast:
        movem.l d2-d7/a5,-(sp)
        lea     -DC_SIZE(sp),sp
        move.l  sp,a5
        move.b  d0,d3
        bsr     dr_ctx
        move.b  rp_DrawMode(a1),-(sp)
        clr.b   rp_DrawMode(a1)      ; solid fill, whatever the mode
        move.b  d3,d4
        movem.w DC_MINX(a5),d0-d3    ; MINX MINY MAXX MAXY
        suba.l  a0,a0
        bsr     dr_rect
        move.b  (sp)+,rp_DrawMode(a1)
        bsr     dr_end
        lea     DC_SIZE(sp),sp
        movem.l (sp)+,d2-d7/a5
        rts

; ClearEOL(rp a1): clears from the current position to the right edge, over the font height (cell sitting on the
; baseline, where Text would write). ClearScreen(rp a1): ClearEOL then the whole area below that line. Colour:
; pen B in JAM2, 0 otherwise; solid fill, cp unchanged.
gfx_ClearEOL:
        moveq   #0,d1
        bra.s   cl_go
gfx_ClearScreen:
        moveq   #1,d1
cl_go:
        movem.l d2-d7/a5,-(sp)
        lea     -DC_SIZE(sp),sp
        move.l  sp,a5
        move.w  d1,d6
        bsr     dr_ctx
        moveq   #0,d3
        btst    #0,rp_DrawMode(a1)   ; JAM2
        beq.s   .cl_pen
        move.b  rp_BgPen(a1),d3
.cl_pen:
        move.b  rp_DrawMode(a1),-(sp)
        clr.b   rp_DrawMode(a1)
        move.w  rp_cp_x(a1),d4
        add.w   DC_OX(a5),d4
        move.w  rp_cp_y(a1),d5
        sub.w   rp_TxBaseline(a1),d5
        add.w   DC_OY(a5),d5
        move.w  d5,d7
        add.w   rp_TxHeight(a1),d7
        subq.w  #1,d7
        bsr.s   cl_box
        tst.w   d6
        beq.s   .cl_ret
        move.w  DC_MINX(a5),d4
        move.w  d7,d5
        addq.w  #1,d5
        move.w  DC_MAXY(a5),d7
        bsr.s   cl_box
.cl_ret:
        move.b  (sp)+,rp_DrawMode(a1)
        bsr     dr_end
        lea     DC_SIZE(sp),sp
        movem.l (sp)+,d2-d7/a5
        rts
; cl_box(a5, d3.b = pen, d4 = x0, d5..d7 = absolute rows): rows [d5..d7] ∩ area, from x0 to the right edge.
; Clobbers d0-d2/d5; d7 is reduced only if it goes past the bottom of the area.
cl_box:
        cmp.w   DC_MINY(a5),d5
        bge.s   .cb_0
        move.w  DC_MINY(a5),d5
.cb_0:
        cmp.w   DC_MAXY(a5),d7
        ble.s   .cb_lp
        move.w  DC_MAXY(a5),d7
.cb_lp:
        movem.l d3-d6/a0,-(sp)
        move.w  d4,d0
        move.w  d5,d1
        move.w  DC_MAXX(a5),d2
        move.b  d3,d4
        move.w  d7,d3
        suba.l  a0,a0
        bsr     dr_rect
        movem.l (sp)+,d3-d6/a0
        rts

; Draw(rp a1, x d0, y d1): segment from (cp_x, cp_y) to (x, y) in pen A, then cp := (x, y). Horizontal and vertical
; ones via dr_rect (same pixels), the others via dr_line (Bresenham).
gfx_Draw:
        movem.l d2-d7/a5,-(sp)
        lea     -DC_SIZE(sp),sp
        move.l  sp,a5
        move.w  rp_cp_x(a1),d4       ; d4,d5 = current point; d6,d7 = end
        move.w  rp_cp_y(a1),d5
        move.w  d0,d6
        move.w  d1,d7
        move.w  d0,rp_cp_x(a1)
        move.w  d1,rp_cp_y(a1)
        bsr     dr_ctx
        move.w  DC_OX(a5),d0
        add.w   d0,d4
        add.w   d0,d6
        move.w  DC_OY(a5),d0
        add.w   d0,d5
        add.w   d0,d7
        cmp.w   d5,d7
        bne.s   .dw_nh
        move.w  d4,d0                ; horizontal: one dr_rect row
        move.w  d6,d2
        cmp.w   d2,d0
        ble.s   .dw_h
        exg     d0,d2
.dw_h:
        move.w  d5,d1
        move.w  d5,d3
        bra.s   .dw_rect
.dw_nh:
        cmp.w   d4,d6
        bne.s   .dw_line
        move.w  d4,d0                ; vertical: one dr_rect column
        move.w  d4,d2
        move.w  d5,d1
        move.w  d7,d3
        cmp.w   d3,d1
        ble.s   .dw_rect
        exg     d1,d3
.dw_rect:
        move.b  rp_FgPen(a1),d4
        suba.l  a0,a0
        bsr     dr_rect
        bra.s   .dw_done
.dw_line:
        bsr     dr_line
.dw_done:
        bsr     dr_end
        lea     DC_SIZE(sp),sp
        movem.l (sp)+,d2-d7/a5
        rts

; --- Text variables, after the drawing context (a5) ---
TX_FONT         EQU DC_SIZE          ; font
TX_W            EQU DC_SIZE+4        ; glyph width (bits, 32 at most)
TX_RW           EQU DC_SIZE+6        ; rendered width (glyph + bold smear)
TX_H            EQU DC_SIZE+8        ; height (tf_YSize)
TX_MOD          EQU DC_SIZE+10       ; tf_Modulo
TX_SH           EQU DC_SIZE+12       ; offset of the glyph within its first byte
TX_BASE         EQU DC_SIZE+14       ; tf_Baseline
TX_SMEAR        EQU DC_SIZE+16       ; tf_BoldSmear
TX_ADV          EQU DC_SIZE+18       ; advance of the current character
TX_STYLE        EQU DC_SIZE+20       ; byte: rendered algorithmic styles (bold, underline)
TX_SOK          EQU DC_SIZE+21       ; byte: "string" path allowed (fixed 8-pixel font, no style)
TX_GP           EQU DC_SIZE+22       ; TX_NMAX glyph pointers of the current slice
TX_NMAX         EQU 16
TX_FRAME        EQU DC_SIZE+22+4*TX_NMAX

; dr_cellcr(d4, d5 = corner of a TX_W x TX_H cell, absolute): looks for a usable ClipRect that contains
; the whole cell and makes it the current ClipRect. Z = 0 if found. Preserves everything except d0.
dr_cellcr:
        move.l  a0,-(sp)
        move.l  DC_FIRST(a5),a0
.cc_lp:
        cmpa.w  #0,a0
        beq.s   .cc_no
        bsr     dr_crset
        beq.s   .cc_n
        cmp.w   DC_CMINX(a5),d4
        blt.s   .cc_n
        cmp.w   DC_CMINY(a5),d5
        blt.s   .cc_n
        move.w  d4,d0
        add.w   TX_W(a5),d0
        subq.w  #1,d0
        cmp.w   DC_CMAXX(a5),d0
        bgt.s   .cc_n
        move.w  d5,d0
        add.w   TX_H(a5),d0
        subq.w  #1,d0
        cmp.w   DC_CMAXY(a5),d0
        bgt.s   .cc_n
        moveq   #1,d0
        bra.s   .cc_r
.cc_n:
        move.l  CR_NEXT(a0),a0
        bra.s   .cc_lp
.cc_no:
        moveq   #0,d0
.cc_r:
        move.l  (sp)+,a0
        rts

; tx_font(rp a1) -> a2 = the RastPort's font, the ROM topaz 8 if it has none. Preserves the rest.
tx_font:
        move.l  rp_Font(a1),a2
        cmpa.w  #0,a2
        bne.s   .tf_r
        lea     topaz8_font,a2
.tf_r:
        rts
; tx_index(a2 = font, d0.w = character) -> d0.w = index into tf_CharLoc; outside LoChar..HiChar: the default
; glyph that follows HiChar. Clobbers d1.
tx_index:
        moveq   #0,d1
        move.b  tf_HiChar(a2),d1
        cmp.w   d1,d0
        bhi.s   .ti_def
        move.b  tf_LoChar(a2),d1
        sub.w   d1,d0
        bcc.s   .ti_r
.ti_def:
        moveq   #0,d0
        move.b  tf_HiChar(a2),d0
        move.b  tf_LoChar(a2),d1
        sub.w   d1,d0
        addq.w  #1,d0
.ti_r:
        rts
; tx_metrics(a2 = font, d0.w = index) -> d0.w = spacing (tf_CharSpace or tf_XSize), d1.w = kerning
; (tf_CharKern or 0). Clobbers a0.
tx_metrics:
        add.w   d0,d0
        move.l  tf_CharKern(a2),d1
        beq.s   .tm_sp
        move.l  d1,a0
        move.w  0(a0,d0.w),d1
.tm_sp:
        tst.l   tf_CharSpace(a2)
        beq.s   .tm_fix
        move.l  tf_CharSpace(a2),a0
        move.w  0(a0,d0.w),d0
        rts
.tm_fix:
        move.w  tf_XSize(a2),d0
        rts

; BltTemplate(template a0, xSrc d0, srcMod d1, rp a1, xDest d2, yDest d3, xSize d4, ySize d5): one-plane template
; (1 bit = pattern pixel), row i at a0 + i × srcMod, first pixel at bit xSrc. 1 bits in pen A (inverted in
; COMPLEMENT); 0 bits in pen B in JAM2; INVERSVID swaps. Coordinates relative to the layer, clipping by
; its ClipRects, planes filtered by rp_Mask. Per ClipRect and per plane, a fixed operation on the template byte g
; (NOT g if inversion applies): OR (JAM1, pen 1), AND-NOT (JAM1, pen 0), exclusive OR (COMPLEMENT),
; set to 1 / to 0 (JAM2, pens A and B equal), replace (JAM2, different pens); edge bytes masked.
BT_SRC          EQU DC_SIZE          ; template
BT_MOD          EQU DC_SIZE+4        ; WORD: srcMod
BT_XS           EQU DC_SIZE+6        ; WORD: xSrc
BT_X            EQU DC_SIZE+8        ; WORD: absolute x of the first pixel
BT_Y            EQU DC_SIZE+10       ; WORD: absolute y of the first row
BT_W            EQU DC_SIZE+12       ; WORD: width
BT_H            EQU DC_SIZE+14       ; WORD: height
BT_NB           EQU DC_SIZE+16       ; WORD: bytes of the row after the first one
BT_FM           EQU DC_SIZE+18       ; byte: mask of the first byte
BT_LM           EQU DC_SIZE+19       ; byte: mask of the last byte
BT_ROWS         EQU DC_SIZE+20       ; WORD: rows - 1
BT_RC           EQU DC_SIZE+22       ; WORD: remaining rows
BT_ROFF         EQU DC_SIZE+24       ; offset of the first byte within a plane
BT_SROW         EQU DC_SIZE+28       ; first template byte read for the first row
BT_SH           EQU DC_SIZE+32       ; WORD: 8 - (start bit & 7)
BT_FGS          EQU DC_SIZE+34       ; byte: pen A, shifted by one bit per plane
BT_BGS          EQU DC_SIZE+35       ; byte: pen B
BT_MSK          EQU DC_SIZE+36       ; byte: rp_Mask
BT_INV          EQU DC_SIZE+37       ; byte: $FF in INVERSVID
BT_BPR          EQU DC_SIZE+38       ; WORD: bytes per row of the BitMap
BT_FRAME        EQU DC_SIZE+40
BTO_OR          EQU 0                ; operations (index x 4 in the tables)
BTO_ANDN        EQU 4
BTO_XOR         EQU 8
BTO_SET         EQU 12
BTO_CLR         EQU 16
BTO_REPL        EQU 20
gfx_BltTemplate:
        movem.l d2-d7/a2-a6,-(sp)
        lea     -BT_FRAME(sp),sp
        move.l  sp,a5
        move.l  a0,BT_SRC(a5)
        move.w  d1,BT_MOD(a5)
        move.w  d0,BT_XS(a5)
        move.w  d4,BT_W(a5)
        move.w  d5,BT_H(a5)
        movem.w d2-d3,-(sp)
        bsr     dr_ctx               ; clobbers d0/d1/a0
        movem.w (sp)+,d2-d3
        add.w   DC_OX(a5),d2
        move.w  d2,BT_X(a5)
        add.w   DC_OY(a5),d3
        move.w  d3,BT_Y(a5)
        tst.w   BT_W(a5)
        ble.s   .bt_end
        tst.w   BT_H(a5)
        ble.s   .bt_end
        move.l  DC_FIRST(a5),a3
.bt_lp:
        cmpa.w  #0,a3
        beq.s   .bt_end
        move.w  BT_Y(a5),d1          ; the template rectangle must cross the ClipRect
        cmp.w   CR_MINX+6(a3),d1
        bgt.s   .bt_n
        add.w   BT_H(a5),d1
        subq.w  #1,d1
        cmp.w   CR_MINX+2(a3),d1
        blt.s   .bt_n
        move.w  BT_X(a5),d0
        cmp.w   CR_MINX+4(a3),d0
        bgt.s   .bt_n
        add.w   BT_W(a5),d0
        subq.w  #1,d0
        cmp.w   CR_MINX(a3),d0
        blt.s   .bt_n
        move.l  a3,a0
        bsr     dr_crset
        beq.s   .bt_n
        bsr.s   bt_one
.bt_n:
        move.l  CR_NEXT(a3),a3
        bra.s   .bt_lp
.bt_end:
        bsr     dr_end
        lea     BT_FRAME(sp),sp
        movem.l (sp)+,d2-d7/a2-a6
        rts
; bt_one(a1 = rp, a5): the template within the current ClipRect. Preserves a1/a3/a5.
bt_one:
        move.w  BT_X(a5),d0          ; d0..d2 = columns, d1..d3 = rows kept (absolute)
        move.w  d0,d2
        add.w   BT_W(a5),d2
        subq.w  #1,d2
        cmp.w   DC_CMINX(a5),d0
        bge.s   .bo_1
        move.w  DC_CMINX(a5),d0
.bo_1:
        cmp.w   DC_CMAXX(a5),d2
        ble.s   .bo_2
        move.w  DC_CMAXX(a5),d2
.bo_2:
        cmp.w   d2,d0
        bgt     .bo_ret
        move.w  BT_Y(a5),d1
        move.w  d1,d3
        add.w   BT_H(a5),d3
        subq.w  #1,d3
        cmp.w   DC_CMINY(a5),d1
        bge.s   .bo_3
        move.w  DC_CMINY(a5),d1
.bo_3:
        cmp.w   DC_CMAXY(a5),d3
        ble.s   .bo_4
        move.w  DC_CMAXY(a5),d3
.bo_4:
        cmp.w   d3,d1
        bgt     .bo_ret
        sub.w   d1,d3
        move.w  d3,BT_ROWS(a5)
        move.w  d1,d4                ; first template row read: (kept y - BT_Y) × srcMod
        sub.w   BT_Y(a5),d4
        muls    BT_MOD(a5),d4
        move.l  BT_SRC(a5),a0
        add.l   d4,a0
        move.l  DC_CBM(a5),a2
        sub.w   DC_BX(a5),d0         ; coordinates within this BitMap
        sub.w   DC_BX(a5),d2
        sub.w   DC_BY(a5),d1
        moveq   #0,d4
        move.w  bm_BytesPerRow(a2),d4
        move.w  d4,BT_BPR(a5)
        mulu    d1,d4
        moveq   #0,d5
        move.w  d0,d5
        lsr.w   #3,d5                ; d5 = first byte
        add.l   d5,d4
        move.l  d4,BT_ROFF(a5)
        move.w  d2,d6
        lsr.w   #3,d6
        sub.w   d5,d6
        move.w  d6,BT_NB(a5)
        moveq   #-1,d7               ; edge masks
        move.w  d0,d4
        and.w   #7,d4
        lsr.b   d4,d7
        move.w  d2,d4
        not.w   d4
        and.w   #7,d4
        moveq   #-1,d3
        lsl.b   d4,d3
        tst.w   d6
        bne.s   .bo_5
        and.b   d3,d7
.bo_5:
        move.b  d7,BT_FM(a5)
        move.b  d3,BT_LM(a5)
        lsl.w   #3,d5                ; template bit under pixel 0 of the first byte (may be negative)
        add.w   DC_BX(a5),d5
        sub.w   BT_X(a5),d5
        add.w   BT_XS(a5),d5
        move.w  d5,d4
        asr.w   #3,d4
        ext.l   d4
        add.l   d4,a0
        move.l  a0,BT_SROW(a5)
        and.w   #7,d5
        moveq   #8,d4
        sub.w   d5,d4
        move.w  d4,BT_SH(a5)
        move.b  rp_FgPen(a1),BT_FGS(a5)
        move.b  rp_BgPen(a1),BT_BGS(a5)
        move.b  rp_Mask(a1),BT_MSK(a5)
        btst    #2,rp_DrawMode(a1)   ; INVERSVID
        sne     BT_INV(a5)
        moveq   #0,d7
        move.b  bm_Depth(a2),d7
        lea     bm_Planes(a2),a2
        bra.s   .bo_pe
.bo_pl:
        move.l  (a2)+,a0
        btst    #0,BT_MSK(a5)
        beq.s   .bo_pn
        adda.l  BT_ROFF(a5),a0
        movem.l d7/a1-a3,-(sp)
        bsr.s   bt_plane
        movem.l (sp)+,d7/a1-a3
.bo_pn:
        move.b  BT_FGS(a5),d0
        lsr.b   #1,d0
        move.b  d0,BT_FGS(a5)
        move.b  BT_BGS(a5),d0
        lsr.b   #1,d0
        move.b  d0,BT_BGS(a5)
        move.b  BT_MSK(a5),d0
        lsr.b   #1,d0
        move.b  d0,BT_MSK(a5)
.bo_pe:
        dbra    d7,.bo_pl
.bo_ret:
        rts
; bt_plane(a0 = first byte of the first row, a1 = rp, a5): the plane's operation, then row by row: first
; byte masked, full bytes, last byte masked. Template stream: d3.w = previous (high) and current byte,
; byte g = (d3 >> BT_SH) ^ d7. Clobbers d0-d7/a0-a3/a6.
bt_plane:
        move.b  BT_INV(a5),d7        ; d7 = template inversion
        moveq   #BTO_XOR,d6
        btst    #1,rp_DrawMode(a1)   ; COMPLEMENT
        bne.s   .bp_go
        btst    #0,rp_DrawMode(a1)   ; JAM2: according to both pens
        bne.s   .bp_j2
        moveq   #BTO_OR,d6
        btst    #0,BT_FGS(a5)
        bne.s   .bp_go
        moveq   #BTO_ANDN,d6
        bra.s   .bp_go
.bp_j2:
        move.b  BT_FGS(a5),d0
        move.b  BT_BGS(a5),d1
        eor.b   d0,d1
        btst    #0,d1
        bne.s   .bp_rp
        moveq   #BTO_SET,d6          ; equal pens: solid colour
        btst    #0,d0
        bne.s   .bp_go
        moveq   #BTO_CLR,d6
        bra.s   .bp_go
.bp_rp:
        moveq   #BTO_REPL,d6         ; different pens: the template, inverted if pen A is 0
        btst    #0,d0
        bne.s   .bp_go
        not.b   d7
.bp_go:
        lea     bt_mops(pc),a6
        move.l  0(a6,d6.w),a6        ; a6 = full-byte loop
        move.w  BT_SH(a5),d4
        move.l  BT_SROW(a5),a2
        move.w  BT_ROWS(a5),BT_RC(a5)
.bp_row:
        move.l  a0,-(sp)
        move.l  a2,-(sp)
        moveq   #0,d3
        move.b  (a2)+,d3
        lsl.w   #8,d3
        move.b  (a2)+,d3             ; first byte
        move.w  d3,d0
        lsr.w   d4,d0
        eor.b   d7,d0
        lsl.w   #8,d3
        move.b  BT_FM(a5),d2
        bsr.s   bt_mask
        move.w  BT_NB(a5),d1
        beq.s   .bp_nx
        subq.w  #1,d1
        beq.s   .bp_last
        subq.w  #1,d1                ; full bytes - 1 (dbra)
        jsr     (a6)
.bp_last:
        move.b  (a2)+,d3
        move.w  d3,d0
        lsr.w   d4,d0
        eor.b   d7,d0
        move.b  BT_LM(a5),d2
        bsr.s   bt_mask
.bp_nx:
        move.l  (sp)+,a2
        move.l  (sp)+,a0
        adda.w  BT_MOD(a5),a2
        adda.w  BT_BPR(a5),a0
        subq.w  #1,BT_RC(a5)
        bpl.s   .bp_row
        rts
; bt_mask(a0, d0.b = g, d2.b = mask, d6 = operation): one edge byte, (a0)+. Clobbers d0/d2.
bt_mask:
        jmp     .bm_t(pc,d6.w)
.bm_t:
        bra.w   .bm_or
        bra.w   .bm_andn
        bra.w   .bm_xor
        bra.w   .bm_set
        bra.w   .bm_clr
        and.b   d2,d0                ; BTO_REPL
        not.b   d2
        and.b   (a0),d2
        or.b    d2,d0
        move.b  d0,(a0)+
        rts
.bm_or:
        and.b   d2,d0
        or.b    d0,(a0)+
        rts
.bm_andn:
        and.b   d2,d0
        not.b   d0
        and.b   d0,(a0)+
        rts
.bm_xor:
        and.b   d2,d0
        eor.b   d0,(a0)+
        rts
.bm_set:
        or.b    d2,(a0)+
        rts
.bm_clr:
        not.b   d2
        and.b   d2,(a0)+
        rts
; full-byte loops: d1 = count - 1, a0 = destination, a2/d3/d4/d7 = template stream. Clobber d0.
bt_mops:
        dc.l    .mo_or,.mo_andn,.mo_xor,.mo_set,.mo_clr,.mo_repl
.mo_or:
        move.b  (a2)+,d3
        move.w  d3,d0
        lsr.w   d4,d0
        eor.b   d7,d0
        lsl.w   #8,d3
        or.b    d0,(a0)+
        dbra    d1,.mo_or
        rts
.mo_andn:
        move.b  (a2)+,d3
        move.w  d3,d0
        lsr.w   d4,d0
        eor.b   d7,d0
        lsl.w   #8,d3
        not.b   d0
        and.b   d0,(a0)+
        dbra    d1,.mo_andn
        rts
.mo_xor:
        move.b  (a2)+,d3
        move.w  d3,d0
        lsr.w   d4,d0
        eor.b   d7,d0
        lsl.w   #8,d3
        eor.b   d0,(a0)+
        dbra    d1,.mo_xor
        rts
.mo_repl:
        move.b  (a2)+,d3
        move.w  d3,d0
        lsr.w   d4,d0
        eor.b   d7,d0
        lsl.w   #8,d3
        move.b  d0,(a0)+
        dbra    d1,.mo_repl
        rts
.mo_set:                             ; SET and CLR do not read the template (neither here nor at the last byte)
        st      (a0)+
        dbra    d1,.mo_set
        rts
.mo_clr:
        clr.b   (a0)+
        dbra    d1,.mo_clr
        rts

; Text(rp a1, string a0, count d0): characters of the RastPort's font (topaz 8 by default), top of the glyph
; at cp_y - tf_Baseline, at cp_x + kerning; cp_x advances by kerning + spacing + rp_TxSpacing. JAM1: glyph
; pixels (pen A); JAM2: background in pen B; COMPLEMENT: glyph inverted; INVERSVID: glyph and background swapped.
; Algorithmic styles (rp_AlgoStyle): bold (glyph smeared by tf_BoldSmear) and underline (line below the baseline).
; Fast paths, fixed 8-pixel font without style: "string" (.tx_str, any mode, up to TX_NMAX aligned glyphs
; at once), otherwise glyph by glyph (.tx_fast, JAM1/JAM2); the whole cell must lie in one ClipRect. Otherwise
; rendering by pixel spans.
gfx_Text:
        movem.l d2-d7/a2-a5,-(sp)
        lea     -TX_FRAME(sp),sp
        move.l  sp,a5
        move.l  a0,a4                ; a4 = string
        move.w  d0,d7                ; d7 = remaining count
        bsr     dr_ctx
        bsr     tx_font
        move.l  a2,TX_FONT(a5)
        move.w  tf_YSize(a2),TX_H(a5)
        move.w  tf_Modulo(a2),TX_MOD(a5)
        move.w  tf_Baseline(a2),TX_BASE(a5)
        move.w  tf_BoldSmear(a2),TX_SMEAR(a5)
        move.b  rp_AlgoStyle(a1),d0
        and.b   #FSF_UNDERLINED|FSF_BOLD,d0
        move.b  d0,TX_STYLE(a5)
        clr.b   TX_SOK(a5)
        tst.b   d0
        bne.s   .tx_char
        tst.l   tf_CharSpace(a2)
        bne.s   .tx_char
        tst.l   tf_CharKern(a2)
        bne.s   .tx_char
        cmp.w   #8,tf_XSize(a2)
        bne.s   .tx_char
        tst.w   rp_TxSpacing(a1)
        bne.s   .tx_char
        st      TX_SOK(a5)
.tx_char:
        tst.b   TX_SOK(a5)
        beq.s   .tx_one
        cmp.w   #2,d7
        blt.s   .tx_one
        bsr     .tx_try
        bne.s   .tx_char
.tx_one:
        subq.w  #1,d7
        bmi     .tx_ret
        move.l  TX_FONT(a5),a2
        moveq   #0,d0
        move.b  (a4)+,d0
        bsr     tx_index
        move.w  d0,d3                ; d3 = index
        bsr     tx_metrics
        add.w   d1,d0
        add.w   rp_TxSpacing(a1),d0
        move.w  d0,TX_ADV(a5)
        move.w  rp_cp_x(a1),d4
        add.w   d1,d4
        add.w   DC_OX(a5),d4         ; d4 = absolute x
        move.w  rp_cp_y(a1),d5
        sub.w   TX_BASE(a5),d5
        add.w   DC_OY(a5),d5         ; d5 = absolute y of the first row
        move.l  tf_CharLoc(a2),a0
        lsl.w   #2,d3
        move.w  0(a0,d3.w),d1        ; bit offset of the glyph
        move.w  2(a0,d3.w),d0        ; width
        cmp.w   #32,d0
        bls.s   .tx_wok
        moveq   #32,d0
.tx_wok:
        move.w  d0,TX_W(a5)
        move.w  d0,TX_RW(a5)
        btst    #1,TX_STYLE(a5)      ; FSF_BOLD: the glyph widens by the smear
        beq.s   .tx_nb
        add.w   TX_SMEAR(a5),d0
        cmp.w   #32,d0
        bls.s   .tx_rw
        moveq   #32,d0
.tx_rw:
        move.w  d0,TX_RW(a5)
.tx_nb:
        move.l  tf_CharData(a2),a3
        move.w  d1,d0
        and.w   #7,d0
        move.w  d0,TX_SH(a5)
        lsr.w   #3,d1
        add.w   d1,a3                ; a3 = first byte of the glyph (row 0)
        tst.w   TX_RW(a5)
        beq.s   .tx_adv
        tst.b   TX_STYLE(a5)
        bne.s   .tx_slow
        tst.w   TX_SH(a5)
        bne.s   .tx_slow
        cmp.w   #8,TX_W(a5)
        bne.s   .tx_slow
        btst    #1,rp_DrawMode(a1)   ; COMPLEMENT: rendering by spans
        bne.s   .tx_slow
        bsr     dr_cellcr            ; whole cell within a single usable ClipRect?
        beq.s   .tx_slow
        bsr     .tx_fast
        bra.s   .tx_adv
.tx_slow:
        moveq   #0,d6                ; d6 = glyph row
.tx_row:
        cmp.w   TX_H(a5),d6
        bhs.s   .tx_adv
        bsr     .tx_bits             ; d2.l = row, left pixel in bit 31
        btst    #1,TX_STYLE(a5)
        beq.s   .tx_nbold
        move.l  d2,d0
        move.w  TX_SMEAR(a5),d1
        lsr.l   d1,d0
        or.l    d0,d2
.tx_nbold:
        btst    #0,TX_STYLE(a5)      ; FSF_UNDERLINED: solid line just below the baseline
        beq.s   .tx_nul
        move.w  TX_BASE(a5),d0
        addq.w  #1,d0
        cmp.w   d6,d0
        bne.s   .tx_nul
        moveq   #-1,d2
.tx_nul:
        btst    #2,rp_DrawMode(a1)   ; INVERSVID
        beq.s   .tx_nv
        not.l   d2
.tx_nv:
        bsr     .tx_runs
        addq.w  #1,d5
        addq.w  #1,d6
        bra.s   .tx_row
.tx_adv:
        move.w  TX_ADV(a5),d0
        add.w   d0,rp_cp_x(a1)
        bra     .tx_char
.tx_ret:
        bsr     dr_end
        lea     TX_FRAME(sp),sp
        movem.l (sp)+,d2-d7/a2-a5
        rts
; .tx_try: "string" path over at most the next TX_NMAX characters: 8-pixel glyphs aligned on the byte,
; whole span within one ClipRect. Z = 0 if characters were rendered (a4, d7 and cp_x advanced). If the span
; overflows every ClipRect, the path is abandoned for the rest of the call. Clobbers d0-d6/a0/a2/a3.
.tx_try:
        move.w  d7,d6
        cmp.w   #TX_NMAX,d6
        bls.s   .tt_n
        moveq   #TX_NMAX,d6
.tt_n:
        move.l  TX_FONT(a5),a2
        lea     TX_GP(a5),a3
        moveq   #0,d5                ; d5 = accepted glyphs
.tt_gl:
        cmp.w   d6,d5
        bge.s   .tt_pos
        moveq   #0,d0
        move.b  0(a4,d5.w),d0
        bsr     tx_index
        lsl.w   #2,d0
        move.l  tf_CharLoc(a2),a0
        cmp.w   #8,2(a0,d0.w)        ; width
        bne.s   .tt_pos
        move.w  0(a0,d0.w),d1        ; bit offset
        moveq   #7,d2
        and.w   d1,d2
        bne.s   .tt_pos
        lsr.w   #3,d1
        move.l  tf_CharData(a2),a0
        add.w   d1,a0
        move.l  a0,(a3)+
        addq.w  #1,d5
        bra.s   .tt_gl
.tt_pos:
        move.w  d5,d6                ; d6 = characters of the slice
        beq.s   .tt_none
        move.w  rp_cp_x(a1),d4
        add.w   DC_OX(a5),d4
        move.w  rp_cp_y(a1),d5
        sub.w   TX_BASE(a5),d5
        add.w   DC_OY(a5),d5
        move.w  d6,d0
        lsl.w   #3,d0
        move.w  d0,TX_W(a5)
        bsr     dr_cellcr
        beq.s   .tt_off
        bsr.s   .tx_str
        add.w   d6,a4
        sub.w   d6,d7
        lsl.w   #3,d6
        add.w   d6,rp_cp_x(a1)
        moveq   #1,d0                ; Z = 0
        rts
.tt_off:
        clr.b   TX_SOK(a5)
.tt_none:
        moveq   #0,d0                ; Z = 1
        rts
; .tx_str(d6.w = n characters, glyphs in TX_GP, d4/d5 = absolute corner, a1 = rp, current ClipRect): plane by plane
; and row by row, stream of glyph bytes shifted by x & 7. JAM2: byte g -> (g AND m1) exclusive-OR m2 (m1 =
; pens A and B differ, m2 = pen B; INVERSVID: m2 ^= m1), the bits outside the span of the two edge bytes
; are kept. Other modes (.to_*): g (INVERSVID: NOT g) touches only its 1 bits: dst = (dst AND K) exclusive-
; OR V with K = NOT g OR E and V = g AND F (JAM1 pen 1: E = 0, F = $FF; pen 0: E = F = 0;
; COMPLEMENT: E = F = $FF). Preserves everything except d0/d1.
TS_N            EQU 0                ; WORD: characters
TS_PLW          EQU 2                ; next plane (bm_Planes)
TS_PC           EQU 6                ; WORD: remaining planes
TS_FG           EQU 8                ; byte: pen A, shifted by one bit per plane
TS_BG           EQU 9
TS_MSK          EQU 10
TS_MODE         EQU 11               ; byte: rp_DrawMode
TS_RC           EQU 12               ; WORD: remaining rows
TS_DST          EQU 14               ; first byte of the current row
TS_O0           EQU 18               ; byte: original left byte
TS_F            EQU 19               ; byte: F of the modes other than JAM2
TS_SIZE         EQU 20
.tx_str:
        movem.l d2-d7/a1-a4/a6,-(sp)
        lea     -TS_SIZE(sp),sp
        move.l  sp,a3
        move.w  d6,TS_N(a3)
        move.b  rp_FgPen(a1),TS_FG(a3)
        move.b  rp_BgPen(a1),TS_BG(a3)
        move.b  rp_Mask(a1),TS_MSK(a3)
        move.b  rp_DrawMode(a1),TS_MODE(a3)
        move.l  DC_CBM(a5),a2
        sub.w   DC_BX(a5),d4         ; coordinates within the ClipRect's BitMap
        sub.w   DC_BY(a5),d5
        moveq   #0,d0
        move.w  bm_BytesPerRow(a2),d0
        move.l  d0,a6                ; a6 = row step
        mulu    d5,d0
        moveq   #0,d1
        move.w  d4,d1
        lsr.w   #3,d1
        add.l   d1,d0
        move.l  d0,a4                ; a4 = offset of the first byte
        and.w   #7,d4                ; d4 = offset within the byte
        moveq   #0,d0
        move.b  bm_Depth(a2),d0
        move.w  d0,TS_PC(a3)
        pea     bm_Planes(a2)
        move.l  (sp)+,TS_PLW(a3)
.ts_plane:
        subq.w  #1,TS_PC(a3)
        bmi     .ts_ret
        move.l  TS_PLW(a3),a2
        move.l  (a2)+,a0
        move.l  a2,TS_PLW(a3)
        move.b  TS_FG(a3),d0
        lsr.b   #1,d0
        scs     d6                   ; (scs before the move, which clears C)
        move.b  d0,TS_FG(a3)
        move.b  TS_BG(a3),d0
        lsr.b   #1,d0
        scs     d7                   ; d7 = m2 = pen B bit
        move.b  d0,TS_BG(a3)
        move.b  TS_MSK(a3),d0
        lsr.b   #1,d0
        scs     d1
        move.b  d0,TS_MSK(a3)
        tst.b   d1
        beq.s   .ts_plane            ; plane protected by rp_Mask
        move.b  TS_MODE(a3),d0
        and.b   #JAM2|COMPLEMENT,d0
        cmp.b   #JAM2,d0
        bne     .to_plane
        eor.b   d7,d6                ; d6 = m1
        btst    #2,TS_MODE(a3)       ; INVERSVID
        beq.s   .ts_ni
        eor.b   d6,d7
.ts_ni:
        add.l   a4,a0                ; a0 = first byte, row 0
        moveq   #0,d5                ; d5 = offset of the row within the glyph
        move.w  TX_H(a5),TS_RC(a3)
.ts_row:
        subq.w  #1,TS_RC(a3)
        bmi.s   .ts_plane
        move.l  a0,TS_DST(a3)
        move.b  (a0),TS_O0(a3)
        lea     TX_GP(a5),a2
        move.w  TS_N(a3),d2
        subq.w  #1,d2
        moveq   #0,d3                ; d3 = previous byte (high 8 bits) and current one
.ts_ch:
        move.l  (a2)+,a1
        move.b  0(a1,d5.l),d0
        and.b   d6,d0
        eor.b   d7,d0
        lsl.w   #8,d3
        move.b  d0,d3
        move.w  d3,d0
        lsr.w   d4,d0
        move.b  d0,(a0)+
        dbra    d2,.ts_ch
        tst.w   d4
        beq.s   .ts_nx
        lsl.w   #8,d3                ; right byte: end of the last glyph
        lsr.w   d4,d3
        moveq   #-1,d0
        lsr.b   d4,d0                ; d0 = right bits kept ($FF >> shift)
        move.b  (a0),d1
        and.b   d0,d1
        or.b    d3,d1
        move.b  d1,(a0)
        move.l  TS_DST(a3),a0        ; left byte: its bits outside the span are restored
        not.b   d0
        and.b   TS_O0(a3),d0
        or.b    d0,(a0)
.ts_nx:
        move.l  TS_DST(a3),a0
        add.l   a6,a0
        moveq   #0,d0
        move.w  TX_MOD(a5),d0
        add.l   d0,d5
        bra.s   .ts_row
.to_plane:                           ; d6 = pen A bit ($FF / 0)
        moveq   #0,d7                ; d7 = glyph inversion (INVERSVID)
        btst    #2,TS_MODE(a3)
        beq.s   .to_ni
        moveq   #-1,d7
.to_ni:
        btst    #1,TS_MODE(a3)       ; COMPLEMENT
        beq.s   .to_j1
        moveq   #-1,d6               ; d6 = E
        st      TS_F(a3)
        bra.s   .to_go
.to_j1:
        move.b  d6,TS_F(a3)
        moveq   #0,d6
.to_go:
        add.l   a4,a0
        moveq   #0,d5
        move.w  TX_H(a5),TS_RC(a3)
.to_row:
        subq.w  #1,TS_RC(a3)
        bmi     .ts_plane
        move.l  a0,TS_DST(a3)
        lea     TX_GP(a5),a2
        move.w  TS_N(a3),d2
        subq.w  #1,d2
        moveq   #0,d3
.to_ch:
        move.l  (a2)+,a1
        move.b  0(a1,d5.l),d0
        eor.b   d7,d0
        lsl.w   #8,d3
        move.b  d0,d3
        move.w  d3,d0
        lsr.w   d4,d0
        move.b  d0,d1
        not.b   d1
        or.b    d6,d1
        and.b   d1,(a0)
        and.b   TS_F(a3),d0
        eor.b   d0,(a0)+
        dbra    d2,.to_ch
        tst.w   d4
        beq.s   .to_nx
        lsl.w   #8,d3                ; right byte: end of the last glyph
        lsr.w   d4,d3
        move.b  d3,d0
        move.b  d0,d1
        not.b   d1
        or.b    d6,d1
        and.b   d1,(a0)
        and.b   TS_F(a3),d0
        eor.b   d0,(a0)
.to_nx:
        move.l  TS_DST(a3),a0
        add.l   a6,a0
        moveq   #0,d0
        move.w  TX_MOD(a5),d0
        add.l   d0,d5
        bra.s   .to_row
.ts_ret:
        lea     TS_SIZE(sp),sp
        movem.l (sp)+,d2-d7/a1-a4/a6
        rts
; .tx_bits(d6 = row, a3 = glyph) -> d2.l = TX_W bits of the row, left-aligned (bit 31 = left pixel), the
; rest 0. Read by bytes (the strike can start at an odd address). Clobbers d0/d1/a0.
.tx_bits:
        move.w  d6,d0
        mulu    TX_MOD(a5),d0
        lea     0(a3,d0.l),a0
        moveq   #3,d1
.tb_lp:
        lsl.l   #8,d2
        move.b  (a0)+,d2
        dbra    d1,.tb_lp
        move.w  TX_SH(a5),d0
        lsl.l   d0,d2
        moveq   #0,d1
        move.b  (a0),d1
        lsl.w   d0,d1
        lsr.w   #8,d1
        or.b    d1,d2
        move.w  TX_W(a5),d0
        cmp.w   #32,d0
        bhs.s   .tb_r
        moveq   #-1,d1
        lsr.l   d0,d1
        not.l   d1
        and.l   d1,d2
.tb_r:
        rts
; .tx_fast: glyph a3 (8 pixels, aligned) at (d4, d5) aligned on a byte, within the current ClipRect, JAM2 mode:
; each plane allowed by rp_Mask receives its bytes directly (1 bit -> pen A bit, 0 bit -> pen B
; bit). Preserves d4-d7.
.tx_fast:
        movem.l d4-d7/a4/a6,-(sp)
        move.l  DC_CBM(a5),a2
        sub.w   DC_BX(a5),d4         ; coordinates within the ClipRect's BitMap
        sub.w   DC_BY(a5),d5
        moveq   #0,d6
        move.w  bm_BytesPerRow(a2),d6
        move.l  d6,a4                ; a4 = row step
        move.w  d5,d0
        mulu    d6,d0
        moveq   #0,d1
        move.w  d4,d1
        lsr.w   #3,d1
        add.l   d1,d0                ; d0 = offset of the first byte touched
        move.l  d0,-(sp)
        moveq   #7,d6
        and.w   d4,d6                ; d6 = offset of the glyph within the byte (0..7)
        moveq   #0,d3
        move.b  bm_Depth(a2),d3
        subq.w  #1,d3                ; d3 = plane counter (dbra)
        lea     bm_Planes(a2),a2
        move.b  rp_FgPen(a1),d1
        move.b  rp_BgPen(a1),d2
        move.b  rp_Mask(a1),d7
.tf_plane:
        move.l  (a2)+,a0
        btst    #0,d7
        beq.s   .tf_next
        add.l   (sp),a0
        move.l  a3,a6                ; a6 = glyph row
        move.w  TX_H(a5),d4
        subq.w  #1,d4                ; d4 = row counter (dbra)
.tf_row:
        move.b  (a6),d0              ; d0 = glyph pixels
        btst    #2,rp_DrawMode(a1)   ; INVERSVID
        beq.s   .tf_ni
        not.b   d0
.tf_ni:
        moveq   #0,d5                ; d5 = value; d0 = pixels touched
        btst    #0,rp_DrawMode(a1)   ; JAM2: the whole cell
        bne.s   .tf_jam2
        btst    #0,d1                ; JAM1: the glyph only, in pen A
        beq.s   .tf_put
        move.b  d0,d5
        bra.s   .tf_put
.tf_jam2:
        btst    #0,d1
        beq.s   .tf_nf
        move.b  d0,d5
.tf_nf:
        btst    #0,d2
        beq.s   .tf_nb
        not.b   d0
        or.b    d0,d5
.tf_nb:
        moveq   #-1,d0
.tf_put:
        and.w   #$FF,d0              ; pixels touched and value, placed across two bytes according to the shift
        and.w   #$FF,d5
        lsl.w   #8,d0
        lsl.w   #8,d5
        lsr.w   d6,d0
        lsr.w   d6,d5
        ror.w   #8,d0                ; left byte
        ror.w   #8,d5
        not.b   d0
        and.b   d0,(a0)
        or.b    d5,(a0)
        not.b   d0
        tst.w   d6
        beq.s   .tf_adv
        ror.w   #8,d0                ; right byte
        ror.w   #8,d5
        not.b   d0
        and.b   d0,1(a0)
        or.b    d5,1(a0)
.tf_adv:
        add.l   a4,a0
        add.w   TX_MOD(a5),a6
        dbra    d4,.tf_row
.tf_next:
        lsr.b   #1,d1                ; pen and mask bits for the next plane
        lsr.b   #1,d2
        lsr.b   #1,d7
        dbra    d3,.tf_plane
        addq.l  #4,sp
        movem.l (sp)+,d4-d7/a4/a6
        rts
; .tx_runs: row d2.l (bit 31 = left pixel) of TX_RW pixels at (d4, d5): split into runs of equal bits;
; bit 1 -> pen A (or inversion in COMPLEMENT); bit 0 -> pen B in JAM2 only. Preserves d4-d7. For glyph
; rows (about ten pixels), a few dr_span calls are enough.
.tx_runs:
        movem.l d4-d7,-(sp)
        moveq   #0,d6                ; d6 = index of the current pixel
.tr_run:
        cmp.w   TX_RW(a5),d6
        bge.s   .tr_ret
        move.w  d6,d7                ; d7 = start of the run
        moveq   #31,d0
        sub.w   d6,d0
        btst    d0,d2
        sne     d3                   ; d3.b = value of the run ($FF / 0)
.tr_ext:
        addq.w  #1,d6
        cmp.w   TX_RW(a5),d6
        bge.s   .tr_emit
        moveq   #31,d0
        sub.w   d6,d0
        btst    d0,d2
        sne     d1
        cmp.b   d1,d3
        beq.s   .tr_ext
.tr_emit:                            ; run [d7 .. d6-1] of value d3
        movem.l d2-d3,-(sp)
        tst.b   d3
        bne.s   .tr_fgp
        move.b  rp_DrawMode(a1),d0   ; background: only in JAM2 (without COMPLEMENT)
        and.b   #JAM2|COMPLEMENT,d0
        cmp.b   #JAM2,d0
        bne.s   .tr_skip
        move.b  rp_BgPen(a1),d3
        bra.s   .tr_do
.tr_fgp:
        move.b  rp_FgPen(a1),d3
.tr_do:
        move.w  d4,d0
        add.w   d7,d0                ; x0
        move.w  d4,d2
        add.w   d6,d2
        subq.w  #1,d2                ; x1
        move.w  d5,d1
        bsr     dr_span
.tr_skip:
        movem.l (sp)+,d2-d3
        bra.s   .tr_run
.tr_ret:
        movem.l (sp)+,d4-d7
        rts

; ScrollRaster(rp a1, dx d0, dy d1, xmin d2, ymin d3, xmax d4, ymax d5): shifts the contents of the rectangle by dy rows
; UP (dy > 0) or down (dy < 0) and fills the freed band with pen B. dx ignored (vertical scrolling only,
; enough for console.device). Coordinates relative to the Layer. Each destination row is copied ClipRect by
; ClipRect from the ClipRects that contain the source row (screen or backups: same bit alignment
; modulo 16, copy by masked bytes). A part whose source is hidden without backup (simple layer) marks
; the whole rectangle "damaged" (DamageList + LAYERREFRESH).
SC_XMIN         EQU 0                ; variables on the stack (a4)
SC_XMAX         EQU 2
SC_DY           EQU 4
SC_Y            EQU 6                ; current destination row
SC_SY           EQU 8                ; source row
SC_DMINX        EQU 10               ; selected destination ClipRect: X bounds, BitMap, origin
SC_DMAXX        EQU 12
SC_DBM          EQU 14
SC_DBX          EQU 18
SC_DBY          EQU 20
SC_COVER        EQU 22               ; pixels of the destination row covered by a source
SC_LOST         EQU 24               ; byte: a source was missing
SC_YMIN         EQU 26
SC_YMAX         EQU 28
SC_SIZE         EQU 30
gfx_ScrollRaster:
        movem.l d2-d7/a2-a5,-(sp)
        lea     -DC_SIZE(sp),sp
        move.l  sp,a5
        lea     -SC_SIZE(sp),sp
        move.l  sp,a4
        movem.w d1-d5,-(sp)          ; (sp) dy, xmin, ymin, xmax, ymax
        bsr     dr_ctx
        movem.w (sp)+,d1-d5
        add.w   DC_OX(a5),d2
        add.w   DC_OX(a5),d4
        add.w   DC_OY(a5),d3
        add.w   DC_OY(a5),d5
        cmp.w   DC_MINX(a5),d2       ; clipping to the RastPort area
        bge.s   .sc_c0
        move.w  DC_MINX(a5),d2
.sc_c0:
        cmp.w   DC_MAXX(a5),d4
        ble.s   .sc_c1
        move.w  DC_MAXX(a5),d4
.sc_c1:
        cmp.w   DC_MINY(a5),d3
        bge.s   .sc_c2
        move.w  DC_MINY(a5),d3
.sc_c2:
        cmp.w   DC_MAXY(a5),d5
        ble.s   .sc_c3
        move.w  DC_MAXY(a5),d5
.sc_c3:
        cmp.w   d4,d2
        bgt     .sc_ret
        cmp.w   d5,d3
        bgt     .sc_ret
        tst.w   d1
        beq     .sc_ret
        move.w  d2,SC_XMIN(a4)
        move.w  d4,SC_XMAX(a4)
        move.w  d1,SC_DY(a4)
        move.w  d3,SC_YMIN(a4)
        move.w  d5,SC_YMAX(a4)
        clr.b   SC_LOST(a4)
        bsr     .sc_whole
        bne     .sc_fast
        move.w  SC_DY(a4),d1
        bmi.s   .sc_down
        move.w  SC_YMIN(a4),d6       ; upwards: row y <- y+dy, increasing y
.sc_up:
        move.w  d6,d0
        add.w   d1,d0
        cmp.w   d5,d0
        bgt.s   .sc_fillu
        move.w  d6,SC_Y(a4)
        move.w  d0,SC_SY(a4)
        bsr     .sc_line
        move.w  SC_DY(a4),d1
        addq.w  #1,d6
        bra.s   .sc_up
.sc_fillu:                           ; rows [d6 .. ymax] in pen B
        move.w  SC_YMAX(a4),d4
        bra.s   .sc_fill
.sc_down:
        move.w  SC_YMAX(a4),d6       ; downwards: y <- y+dy (dy < 0), decreasing y
.sc_dn:
        move.w  d6,d0
        add.w   d1,d0
        cmp.w   SC_YMIN(a4),d0
        blt.s   .sc_filld
        move.w  d6,SC_Y(a4)
        move.w  d0,SC_SY(a4)
        bsr     .sc_line
        move.w  SC_DY(a4),d1
        subq.w  #1,d6
        bra.s   .sc_dn
.sc_filld:                           ; rows [ymin .. d6]
        move.w  d6,d4
        move.w  SC_YMIN(a4),d6
.sc_fill:
        move.b  rp_DrawMode(a1),-(sp)
        clr.b   rp_DrawMode(a1)
        move.b  rp_BgPen(a1),d3
.sc_flp:
        cmp.w   d4,d6
        bgt.s   .sc_fdone
        move.w  SC_XMIN(a4),d0
        move.w  d6,d1
        move.w  SC_XMAX(a4),d2
        bsr     dr_span
        addq.w  #1,d6
        bra.s   .sc_flp
.sc_fdone:
        move.b  (sp)+,rp_DrawMode(a1)
        tst.b   SC_LOST(a4)
        beq.s   .sc_ret
        bsr     .sc_damage
.sc_ret:
        bsr     dr_end
        lea     SC_SIZE+DC_SIZE(sp),sp
        movem.l (sp)+,d2-d7/a2-a5
        rts

; Fast path: a single visible ClipRect contains the whole rectangle (uncovered window) -> rectangle copied with the
; blitter when the planes are in chip memory, otherwise rows copied directly without walking the ClipRects.
.sc_fast:
        bsr     .sc_blit
        tst.l   d0
        beq.s   .sf_cpu
        move.w  SC_DY(a4),d1         ; exposed rows, as at the end of the row-by-row loops
        bmi.s   .sf_bdn
        move.w  SC_YMAX(a4),d6
        sub.w   d1,d6
        addq.w  #1,d6
        bra     .sc_fillu
.sf_bdn:
        move.w  SC_YMIN(a4),d6
        sub.w   d1,d6
        subq.w  #1,d6
        bra     .sc_filld
.sf_cpu:
        tst.w   SC_DY(a4)
        bmi.s   .sf_down
        move.w  SC_YMIN(a4),d6
.sf_up:
        move.w  d6,d0
        add.w   SC_DY(a4),d0
        cmp.w   SC_YMAX(a4),d0
        bgt     .sc_fillu
        move.w  d6,SC_Y(a4)
        move.w  d0,SC_SY(a4)
        move.w  SC_XMIN(a4),d2
        move.w  SC_XMAX(a4),d4
        bsr     .sc_copy
        addq.w  #1,d6
        bra.s   .sf_up
.sf_down:
        move.w  SC_YMAX(a4),d6
.sf_dn:
        move.w  d6,d0
        add.w   SC_DY(a4),d0
        cmp.w   SC_YMIN(a4),d0
        blt     .sc_filld
        move.w  d6,SC_Y(a4)
        move.w  d0,SC_SY(a4)
        move.w  SC_XMIN(a4),d2
        move.w  SC_XMAX(a4),d4
        bsr     .sc_copy
        subq.w  #1,d6
        bra.s   .sf_dn

; .sc_blit(a6 = GfxBase) -> d0 = 1 if the moved rectangle ([SC_XMIN..SC_XMAX], height minus |dy| rows, at least
; one) was copied with the blitter in SC_DBM (source = destination), 0 otherwise (plane not in chip memory, rectangle
; too wide or too tall for a blit, or entirely exposed: nothing done). One blit per plane: A = constant $FFFF masked
; (first/last word), B = source, C = destination, D = AB + ~AC; downwards: descending mode (end addresses,
; masks swapped). Blitter taken by OwnBlitter. Preserves d2-d7/a1-a6.
BLT_CON0        EQU $040
BLT_CON1        EQU $042
BLT_AFWM        EQU $044
BLT_ALWM        EQU $046
BLT_CPT         EQU $048
BLT_BPT         EQU $04C
BLT_DPT         EQU $054
BLT_SIZE        EQU $058
BLT_CMOD        EQU $060
BLT_BMOD        EQU $062
BLT_DMOD        EQU $066
BLT_ADAT        EQU $074
BLT_DMACONR     EQU $002
.sc_blit:
        movem.l d2-d7/a1-a3/a6,-(sp)
        move.l  SC_DBM(a4),a2        ; a2 = BitMap
        move.w  SC_YMAX(a4),d4       ; d4 = rows copied
        sub.w   SC_YMIN(a4),d4
        addq.w  #1,d4
        move.w  SC_DY(a4),d0
        bpl.s   .bl_ady
        neg.w   d0
.bl_ady:
        sub.w   d0,d4
        ble     .bl_no               ; everything is exposed: only the fill remains
        cmp.w   #1024,d4
        bhi     .bl_no
        move.l  a6,a3                ; a3 = GfxBase
        move.l  ($4).w,a6
        moveq   #0,d6
.bl_chip:
        cmp.b   bm_Depth(a2),d6
        bge.s   .bl_go
        move.w  d6,d0
        lsl.w   #2,d0
        move.l  bm_Planes(a2,d0.w),a1
        jsr     LVO_TYPEOFMEM(a6)
        btst    #1,d0                ; MEMF_CHIP: the only memory the blitter can reach
        beq     .bl_no
        addq.w  #1,d6
        bra.s   .bl_chip
.bl_go:
        move.w  SC_XMIN(a4),d2       ; columns relative to the BitMap
        sub.w   SC_DBX(a4),d2
        move.w  SC_XMAX(a4),d3
        sub.w   SC_DBX(a4),d3
        move.w  d2,d6
        lsr.w   #4,d6                ; d6 = first word
        move.w  d3,d5
        lsr.w   #4,d5
        sub.w   d6,d5
        addq.w  #1,d5                ; d5 = words per row
        cmp.w   #64,d5
        bhi     .bl_no
        lsl.w   #6,d4
        or.w    d5,d4                ; d4 = BLTSIZE (height << 6 | words; 1024 rows = 0)
        and.w   #15,d2
        moveq   #-1,d0
        lsr.w   d2,d0
        move.w  d0,d2                ; d2 = left word mask
        and.w   #15,d3
        moveq   #15,d1
        sub.w   d3,d1
        moveq   #-1,d3
        lsl.w   d1,d3                ; d3 = right word mask
        move.w  SC_YMIN(a4),d0       ; upwards: destination ymin, source ymin + dy, first word
        tst.w   SC_DY(a4)
        bpl.s   .bl_rows
        move.w  SC_YMAX(a4),d0       ; downwards: last row and last word, descending
        add.w   d5,d6
        subq.w  #1,d6
        exg     d2,d3                ; when descending, the first word processed is the rightmost one
.bl_rows:
        move.w  d0,d1
        add.w   SC_DY(a4),d1
        sub.w   SC_DBY(a4),d0
        sub.w   SC_DBY(a4),d1
        moveq   #0,d7
        move.w  bm_BytesPerRow(a2),d7
        mulu    d7,d0                ; d0 = destination offset
        mulu    d7,d1                ; d1 = source offset
        add.w   d6,d6
        and.l   #$FFFF,d6
        add.l   d6,d0
        add.l   d6,d1
        add.w   d5,d5
        sub.w   d5,d7                ; d7 = modulo (bytes skipped per row)
        moveq   #0,d6                ; d6 = BLTCON1
        tst.w   SC_DY(a4)
        bpl.s   .bl_own
        moveq   #2,d6                ; DESC
.bl_own:
        move.l  a3,a6
        movem.l d0-d1,-(sp)
        jsr     gfx_OwnBlitter
        movem.l (sp)+,d0-d1
        move.w  #$8240,DMACON        ; master DMA + blitter
        lea     CUSTOM,a0
        moveq   #0,d5                ; d5 = plane
.bl_plane:
        cmp.b   bm_Depth(a2),d5
        bge.s   .bl_done
        move.w  d5,a1
        add.w   a1,a1
        add.w   a1,a1
        move.l  bm_Planes(a2,a1.w),a1
        btst    #6,BLT_DMACONR(a0)   ; dummy read (A1000 quirk), then wait for the previous blit
.bl_wait:
        btst    #6,BLT_DMACONR(a0)
        bne.s   .bl_wait
        move.w  #$07CA,BLT_CON0(a0)  ; B, C, D enabled; minterm AB + ~AC
        move.w  d6,BLT_CON1(a0)
        move.w  d2,BLT_AFWM(a0)
        move.w  d3,BLT_ALWM(a0)
        move.w  #$FFFF,BLT_ADAT(a0)
        move.w  d7,BLT_BMOD(a0)
        move.w  d7,BLT_CMOD(a0)
        move.w  d7,BLT_DMOD(a0)
        pea     0(a1,d1.l)
        move.l  (sp)+,BLT_BPT(a0)
        pea     0(a1,d0.l)
        move.l  (sp),BLT_CPT(a0)
        move.l  (sp)+,BLT_DPT(a0)
        move.w  d4,BLT_SIZE(a0)
        addq.w  #1,d5
        bra.s   .bl_plane
.bl_done:
        btst    #6,BLT_DMACONR(a0)
.bl_wend:
        btst    #6,BLT_DMACONR(a0)
        bne.s   .bl_wend
        jsr     gfx_DisownBlitter
        moveq   #1,d0
        bra.s   .bl_ret
.bl_no:
        moveq   #0,d0
.bl_ret:
        movem.l (sp)+,d2-d7/a1-a3/a6
        rts

; .sc_whole -> Z = 0 if a visible ClipRect contains the whole [SC_XMIN..SC_XMAX] x [SC_YMIN..SC_YMAX]: it becomes
; the current ClipRect (source) and the destination (SC_DBM/DBX/DBY). Clobbers d0/a0.
.sc_whole:
        move.l  DC_FIRST(a5),a0
.sw_lp:
        cmpa.w  #0,a0
        beq.s   .sw_no
        tst.l   CR_LOBS(a0)
        bne.s   .sw_next
        bsr     dr_crset
        beq.s   .sw_next
        move.w  SC_XMIN(a4),d0
        cmp.w   DC_CMINX(a5),d0
        blt.s   .sw_next
        move.w  SC_XMAX(a4),d0
        cmp.w   DC_CMAXX(a5),d0
        bgt.s   .sw_next
        move.w  SC_YMIN(a4),d0
        cmp.w   DC_CMINY(a5),d0
        blt.s   .sw_next
        move.w  SC_YMAX(a4),d0
        cmp.w   DC_CMAXY(a5),d0
        bgt.s   .sw_next
        move.l  DC_CBM(a5),SC_DBM(a4)
        move.l  DC_BX(a5),SC_DBX(a4)
        moveq   #1,d0
        rts
.sw_next:
        move.l  CR_NEXT(a0),a0
        bra.s   .sw_lp
.sw_no:
        moveq   #0,d0
        rts

; .sc_line: row SC_Y <- row SC_SY over [SC_XMIN..SC_XMAX], ClipRect by ClipRect. Preserves d4-d7/a1.
.sc_line:
        movem.l d4-d7/a1-a3,-(sp)
        move.l  DC_FIRST(a5),a2      ; a2 = destination ClipRect
.sl_dst:
        cmpa.w  #0,a2
        beq     .sl_r
        move.l  a2,a0
        bsr     dr_crset
        beq     .sl_dnext
        move.w  SC_Y(a4),d0
        cmp.w   DC_CMINY(a5),d0
        blt     .sl_dnext
        cmp.w   DC_CMAXY(a5),d0
        bgt     .sl_dnext
        move.w  SC_XMIN(a4),d0       ; destination segment
        cmp.w   DC_CMINX(a5),d0
        bge.s   .sl_1
        move.w  DC_CMINX(a5),d0
.sl_1:
        move.w  SC_XMAX(a4),d1
        cmp.w   DC_CMAXX(a5),d1
        ble.s   .sl_2
        move.w  DC_CMAXX(a5),d1
.sl_2:
        cmp.w   d1,d0
        bgt     .sl_dnext
        move.w  d0,SC_DMINX(a4)
        move.w  d1,SC_DMAXX(a4)
        move.l  DC_CBM(a5),SC_DBM(a4)
        move.l  DC_BX(a5),SC_DBX(a4)   ; BX, BY
        clr.w   SC_COVER(a4)
        move.l  DC_FIRST(a5),a3      ; a3 = source ClipRect
.sl_src:
        cmpa.w  #0,a3
        beq.s   .sl_check
        move.l  a3,a0
        bsr     dr_crset
        beq.s   .sl_snext
        move.w  SC_SY(a4),d0
        cmp.w   DC_CMINY(a5),d0
        blt.s   .sl_snext
        cmp.w   DC_CMAXY(a5),d0
        bgt.s   .sl_snext
        move.w  SC_DMINX(a4),d2      ; common segment
        cmp.w   DC_CMINX(a5),d2
        bge.s   .sl_3
        move.w  DC_CMINX(a5),d2
.sl_3:
        move.w  SC_DMAXX(a4),d4
        cmp.w   DC_CMAXX(a5),d4
        ble.s   .sl_4
        move.w  DC_CMAXX(a5),d4
.sl_4:
        cmp.w   d4,d2
        bgt.s   .sl_snext
        move.w  d4,d0
        sub.w   d2,d0
        addq.w  #1,d0
        add.w   d0,SC_COVER(a4)
        bsr     .sc_copy
.sl_snext:
        move.l  CR_NEXT(a3),a3
        bra.s   .sl_src
.sl_check:
        move.w  SC_DMAXX(a4),d0
        sub.w   SC_DMINX(a4),d0
        addq.w  #1,d0
        cmp.w   SC_COVER(a4),d0
        ble.s   .sl_dnext
        st      SC_LOST(a4)          ; a part had no source
.sl_dnext:
        move.l  CR_NEXT(a2),a2
        bra     .sl_dst
.sl_r:
        movem.l (sp)+,d4-d7/a1-a3
        rts

; .sc_copy(d2..d4 = absolute segment; source = current ClipRect (DC_CBM, DC_BX/BY, row SC_SY); destination =
; SC_DBM / SC_DBX / SC_DBY, row SC_Y): pixels copied plane by plane, edge bytes masked. Preserves d4-d7/a1-a3.
.sc_copy:
        movem.l d4-d7/a1-a3,-(sp)
        move.l  DC_CBM(a5),a2        ; a2 = source BitMap, a3 = destination BitMap
        move.l  SC_DBM(a4),a3
        move.w  SC_SY(a4),d0
        sub.w   DC_BY(a5),d0
        moveq   #0,d5
        move.w  bm_BytesPerRow(a2),d5
        mulu    d0,d5
        move.w  d2,d0
        sub.w   DC_BX(a5),d0
        lsr.w   #3,d0
        add.l   d0,d5                ; d5 = offset of the first source byte
        move.w  SC_Y(a4),d0
        sub.w   SC_DBY(a4),d0
        moveq   #0,d6
        move.w  bm_BytesPerRow(a3),d6
        mulu    d0,d6
        move.w  d2,d0
        sub.w   SC_DBX(a4),d0
        lsr.w   #3,d0
        add.l   d0,d6                ; d6 = offset of the first destination byte
        move.w  d4,d7                ; d7 = bytes after the first one
        lsr.w   #3,d7
        move.w  d2,d0
        lsr.w   #3,d0
        sub.w   d0,d7
        move.w  d2,d0                ; d2.b = left mask, d3.b = right mask
        and.w   #7,d0
        moveq   #-1,d2
        lsr.b   d0,d2
        move.w  d4,d0
        and.w   #7,d0
        moveq   #7,d1
        sub.w   d0,d1
        moveq   #-1,d3
        lsl.b   d1,d3
        tst.w   d7
        bne.s   .cp_m
        and.b   d3,d2                ; single byte: masks combined
.cp_m:
        moveq   #0,d4                ; d4 = plane
.cp_plane:
        cmp.b   bm_Depth(a2),d4
        bge.s   .cp_r
        cmp.b   bm_Depth(a3),d4
        bge.s   .cp_r
        move.w  d4,d0
        lsl.w   #2,d0
        move.l  bm_Planes(a2,d0.w),a0
        move.l  bm_Planes(a3,d0.w),a1
        add.l   d5,a0
        add.l   d6,a1
        move.b  d2,d0                ; first byte
        bsr.s   .cp_mask
        tst.w   d7
        beq.s   .cp_pdone
        move.w  d7,d1
        subq.w  #1,d1                ; full bytes
        beq.s   .cp_last
        bsr.s   .cp_run
.cp_last:
        move.b  d3,d0                ; last byte
        bsr.s   .cp_mask
.cp_pdone:
        addq.w  #1,d4
        bra.s   .cp_plane
.cp_r:
        movem.l (sp)+,d4-d7/a1-a3
        rts
; .cp_run(d1.w = bytes, > 0): copies (a0)+ -> (a1)+, as longs when both addresses have the same parity (the
; scrolling case: same abscissa). Clobbers d0/d1.
.cp_run:
        move.l  a0,d0
        sub.l   a1,d0
        btst    #0,d0
        bne.s   .cr_bx               ; different parities: byte by byte
        move.w  a0,d0
        btst    #0,d0
        beq.s   .cr_even
        move.b  (a0)+,(a1)+
        subq.w  #1,d1
.cr_even:
        move.w  d1,d0
        lsr.w   #2,d0
        bra.s   .cr_lx
.cr_l:
        move.l  (a0)+,(a1)+
.cr_lx:
        dbra    d0,.cr_l
        and.w   #3,d1
        bra.s   .cr_bx
.cr_b:
        move.b  (a0)+,(a1)+
.cr_bx:
        dbra    d1,.cr_b
        rts
; .cp_mask(d0.b = mask): dst = (dst & ~m) | (src & m) for the current byte; advances a0/a1. Clobbers d0/d1.
.cp_mask:
        move.b  (a0)+,d1
        and.b   d0,d1
        not.b   d0
        and.b   d0,(a1)
        or.b    d1,(a1)+
        rts

; .sc_damage: scroll rectangle (relative to the layer) added to the layer's DamageList + LAYERREFRESH.
.sc_damage:
        move.l  DC_LAYER(a5),d0
        beq.s   .sd_r
        move.l  d0,a0
        or.w    #LAYERREFRESH,LY_FLAGS(a0)
        move.l  LY_DAMAGE(a0),d0
        beq.s   .sd_r
        movem.l a1/a6,-(sp)
        move.w  SC_YMAX(a4),-(sp)
        move.w  SC_XMAX(a4),-(sp)
        move.w  SC_YMIN(a4),-(sp)
        move.w  SC_XMIN(a4),-(sp)
        move.w  16(a0),d1            ; layer bounds
        sub.w   d1,(sp)
        sub.w   d1,4(sp)
        move.w  18(a0),d1
        sub.w   d1,2(sp)
        sub.w   d1,6(sp)
        move.l  d0,a0
        move.l  sp,a1
        bsr     gfx_OrRectRegion
        addq.l  #8,sp
        movem.l (sp)+,a1/a6
.sd_r:
        rts

; BltMaskBitMapRastPort(BitMap a0, srcX d0, srcY d1, RastPort a1, destX d2, destY d3, width d4, height d5,
; minterm d6, mask a2) (spec graphics-blitter-v34 §5.4): three passes of BltBitMapRastPort, source with $90
; (D = not(B exclusive-or C)), then the mask (dummy BitMap: header of the source, all planes on the mask)
; with the caller's minterm, then the source again with $90. With $E0: the source where the mask is 1, the
; destination intact elsewhere. NULL mask: nothing. Preserves d2-d7/a1-a5.
BMB_ARGS        EQU bm_SIZEOF        ; arguments saved above the dummy BitMap: d0/d1/d6/a0
gfx_BltMaskBitMapRastPort:
        cmpa.w  #0,a2
        beq.s   .bm_ret
        movem.l d0-d1/d6/a0,-(sp)
        lea     -bm_SIZEOF(sp),sp
        move.l  (a0),(sp)            ; BytesPerRow, Rows
        move.l  4(a0),4(sp)          ; Flags, Depth, pad
        lea     bm_Planes(sp),a0
        moveq   #7,d0
.bm_pl:
        move.l  a2,(a0)+
        dbra    d0,.bm_pl
        movem.l BMB_ARGS(sp),d0-d1   ; pass 1: source, $90
        move.l  BMB_ARGS+12(sp),a0
        move.l  #$90,d6
        bsr     gfx_BltBitMapRastPort
        movem.l BMB_ARGS(sp),d0-d1   ; pass 2: mask, caller's minterm
        move.l  BMB_ARGS+8(sp),d6
        move.l  sp,a0
        bsr     gfx_BltBitMapRastPort
        movem.l BMB_ARGS(sp),d0-d1   ; pass 3: source, $90
        move.l  BMB_ARGS+12(sp),a0
        move.l  #$90,d6
        bsr     gfx_BltBitMapRastPort
        lea     bm_SIZEOF(sp),sp
        movem.l (sp)+,d0-d1/d6/a0
.bm_ret:
        rts

; ClipBlit(source RastPort a0, srcX d0, srcY d1, dest RastPort a1, destX d2, destY d3, width d4, height d5,
; minterm d6) -> d0 = 1 (spec graphics-blitter-v34 §5.3): the source rectangle is clipped by the ClipRects of its
; layer (visible part: the screen BitMap; hidden and backed up: the backup; hidden without backup: the
; destination stays intact); each piece goes through BltBitMapRastPort, which clips on the destination side. Deviations:
; no source SuperBitMap, no reordering of the ClipRects for an overlapping copy within the same RastPort.
CB_SX   EQU 0                        ; saved arguments (words): sx, sy, dx, dy, w, h; minterm (long); dest RastPort
CB_SY   EQU 2
CB_DX   EQU 4
CB_DY   EQU 6
CB_W    EQU 8
CB_H    EQU 10
CB_MT   EQU 12
CB_DRP  EQU 16
CB_SIZE EQU 20
gfx_ClipBlit:
        movem.l d2-d7/a1-a5,-(sp)
        lea     -DC_SIZE(sp),sp
        move.l  sp,a5
        lea     -CB_SIZE(sp),sp
        movem.w d0-d5,(sp)
        move.l  d6,CB_MT(sp)
        move.l  a1,CB_DRP(sp)
        move.l  a0,a1
        bsr     dr_ctx               ; context of the source RastPort (lock of its layer)
        move.w  DC_OX(a5),d0
        add.w   d0,CB_SX(sp)         ; source in absolute coordinates
        move.w  DC_OY(a5),d0
        add.w   d0,CB_SY(sp)
        move.l  DC_FIRST(a5),a4
.cb_lp:
        cmpa.w  #0,a4
        beq     .cb_done
        move.l  a4,a0
        bsr     dr_crset
        beq     .cb_next
        move.w  CB_SX(sp),d0         ; d0..d3 = intersection (x0, y0, x1, y1)
        cmp.w   DC_CMINX(a5),d0
        bge.s   .cb_x0
        move.w  DC_CMINX(a5),d0
.cb_x0:
        move.w  CB_SY(sp),d1
        cmp.w   DC_CMINY(a5),d1
        bge.s   .cb_y0
        move.w  DC_CMINY(a5),d1
.cb_y0:
        move.w  CB_SX(sp),d2
        add.w   CB_W(sp),d2
        subq.w  #1,d2
        cmp.w   DC_CMAXX(a5),d2
        ble.s   .cb_x1
        move.w  DC_CMAXX(a5),d2
.cb_x1:
        move.w  CB_SY(sp),d3
        add.w   CB_H(sp),d3
        subq.w  #1,d3
        cmp.w   DC_CMAXY(a5),d3
        ble.s   .cb_y1
        move.w  DC_CMAXY(a5),d3
.cb_y1:
        move.w  d2,d4
        sub.w   d0,d4
        addq.w  #1,d4                ; width of the piece
        ble.s   .cb_next
        move.w  d3,d5
        sub.w   d1,d5
        addq.w  #1,d5                ; height of the piece
        ble.s   .cb_next
        move.w  d0,d2                ; destination offset like the piece within the source
        sub.w   CB_SX(sp),d2
        add.w   CB_DX(sp),d2
        move.w  d1,d3
        sub.w   CB_SY(sp),d3
        add.w   CB_DY(sp),d3
        sub.w   DC_BX(a5),d0         ; position of this piece within the BitMap
        sub.w   DC_BY(a5),d1
        ext.l   d0
        ext.l   d1
        ext.l   d2
        ext.l   d3
        ext.l   d4
        ext.l   d5
        move.l  CB_MT(sp),d6
        move.l  DC_CBM(a5),a0
        move.l  CB_DRP(sp),a1
        move.l  a5,-(sp)
        bsr     gfx_BltBitMapRastPort
        move.l  (sp)+,a5
.cb_next:
        move.l  CR_NEXT(a4),a4
        bra     .cb_lp
.cb_done:
        bsr     dr_end
        lea     CB_SIZE+DC_SIZE(sp),sp
        movem.l (sp)+,d2-d7/a1-a5
        moveq   #1,d0
        rts

; BltBitMapRastPort(BitMap a0, srcX d0, srcY d1, RastPort a1, destX d2, destY d3, width d4, height d5, minterm d6):
; copies the source rectangle into the RastPort (relative to the Layer, clipped to the context), plane by plane per
; rp_Mask. Minterm applied (B = source, C = destination). NULL source plane = all 0,
; -1 = all 1 (planes beyond the source depth are 0). CPU rendering byte by byte, edges masked.
gfx_BltBitMapRastPort:
        movem.l d2-d7/a1-a5,-(sp)
        lea     -DC_SIZE(sp),sp
        move.l  sp,a5
        move.l  a0,a4                ; a4 = source BitMap
        move.b  d6,DC_MINTERM(a5)
        movem.w d0-d1,-(sp)
        bsr     dr_ctx
        movem.w (sp)+,d0-d1
        add.w   DC_OX(a5),d2
        add.w   DC_OY(a5),d3
        movem.w d0-d5,-(sp)          ; 4(sp): arguments (absolute destination)
        move.l  DC_FIRST(a5),-(sp)   ; (sp): current ClipRect
.bb_cr:
        move.l  (sp),a0
        cmpa.w  #0,a0
        beq.s   .bb_done
        bsr     dr_crset
        beq.s   .bb_crn
        movem.w 4(sp),d0-d5
        bsr.s   .bb_one
.bb_crn:
        move.l  (sp),a0
        move.l  CR_NEXT(a0),(sp)
        bra.s   .bb_cr
.bb_done:
        lea     16(sp),sp
        bsr     dr_end
        lea     DC_SIZE(sp),sp
        movem.l (sp)+,d2-d7/a1-a5
        moveq   #1,d0                ; always returns true (spec graphics-blitter-v34 §5.2)
        rts
; .bb_one(d0..d5 = absolute sx, sy, dx, dy, width, height): part within the current ClipRect. Clobbers d0-d7/a0-a3.
.bb_one:
        move.w  DC_CMINX(a5),d6      ; left/top clipping: also shifts the source
        sub.w   d2,d6
        ble.s   .bb_l
        add.w   d6,d0
        sub.w   d6,d4
        add.w   d6,d2
.bb_l:
        move.w  DC_CMINY(a5),d6
        sub.w   d3,d6
        ble.s   .bb_t
        add.w   d6,d1
        sub.w   d6,d5
        add.w   d6,d3
.bb_t:
        move.w  DC_CMAXX(a5),d6      ; right/bottom clipping
        sub.w   d2,d6
        addq.w  #1,d6
        cmp.w   d6,d4
        ble.s   .bb_r
        move.w  d6,d4
.bb_r:
        move.w  DC_CMAXY(a5),d6
        sub.w   d3,d6
        addq.w  #1,d6
        cmp.w   d6,d5
        ble.s   .bb_b
        move.w  d6,d5
.bb_b:
        tst.w   d4
        ble     .bb_oret
        tst.w   d5
        ble     .bb_oret
        sub.w   DC_BX(a5),d2         ; coordinates within the ClipRect's BitMap
        sub.w   DC_BY(a5),d3
        move.l  DC_CBM(a5),a3        ; a3 = destination BitMap
        moveq   #0,d7                ; d7 = plane
.bb_plane:
        moveq   #0,d6
        move.b  bm_Depth(a3),d6
        cmp.w   d6,d7
        bge     .bb_oret
        move.l  DC_RP(a5),a0
        move.b  rp_Mask(a0),d6
        btst    d7,d6
        beq     .bb_pnext
        moveq   #0,d6                ; a2 = source plane (0 / -1 / address)
        move.b  bm_Depth(a4),d6
        sub.l   a2,a2
        cmp.w   d6,d7
        bge.s   .bb_src
        move.w  d7,d6
        lsl.w   #2,d6
        move.l  bm_Planes(a4,d6.w),a2
.bb_src:
        movem.l d0-d5/d7/a2,-(sp)    ; rows: d1 = source row, d3 = destination row, d5 = counter
.bb_row:
        movem.l d0-d5/d7/a2,-(sp)
        move.l  a2,d6                ; address of the source row (except constant plane)
        beq.s   .bb_const
        cmp.l   #-1,d6
        beq.s   .bb_const
        moveq   #0,d6
        move.w  bm_BytesPerRow(a4),d6
        mulu    d1,d6
        add.l   d6,a2
.bb_const:
        move.w  d7,d6                ; a1 = destination row
        lsl.w   #2,d6
        move.l  bm_Planes(a3,d6.w),a1
        moveq   #0,d6
        move.w  bm_BytesPerRow(a3),d6
        mulu    d3,d6
        add.l   d6,a1
        bsr     dr_bits
        movem.l (sp)+,d0-d5/d7/a2
        addq.w  #1,d1
        addq.w  #1,d3
        subq.w  #1,d5
        bne.s   .bb_row
        movem.l (sp)+,d0-d5/d7/a2
.bb_pnext:
        addq.w  #1,d7
        bra     .bb_plane
.bb_oret:
        rts
; dr_bits(a2 = source row | 0 | -1, d0 = source bit, a1 = destination row, d2 = destination bit, d4 = width,
; a5 = context: DC_MINTERM): combines d4 bits. For each destination byte: 8 aligned source bits (two bytes
; read then shifted), edge masks computed once; result = minterm(B = source, C = destination), the blitter's A
; channel being 1 (only bits 7-4 of the minterm matter). Clobbers d0-d7/a0.
dr_bits:
        move.w  d2,d5
        lsr.w   #3,d5                ; d5 = current destination byte (the first one)
        move.w  d5,-(sp)             ; (sp) = first byte
        move.w  d2,d7
        add.w   d4,d7
        subq.w  #1,d7                ; d7 = last destination bit
        moveq   #-1,d1               ; d1.b = mask of the first byte: pixels >= destX
        move.w  d2,d3
        and.w   #7,d3
        lsr.b   d3,d1
        move.w  d7,d3                ; d2.b = mask of the last byte: pixels <= last bit
        and.w   #7,d3
        moveq   #7,d4
        sub.w   d3,d4
        sub.w   d2,d0                ; d0 = source bit - destination bit
        moveq   #-1,d2
        lsl.b   d4,d2
        lsr.w   #3,d7                ; d7 = last destination byte
        cmp.b   #$C0,DC_MINTERM(a5)  ; fast path: copy of a real plane, shift a multiple of 8 (layers
        bne.s   .bt_byte             ; backups: same bit position modulo 16) -> bytes copied as is
        move.l  a2,d4
        beq.s   .bt_byte
        addq.l  #1,d4
        beq.s   .bt_byte
        moveq   #7,d4
        and.w   d0,d4
        bne.s   .bt_byte
        move.l  a1,-(sp)
        asr.w   #3,d0
        lea     0(a2,d0.w),a0
        add.w   d5,a0                ; a0 = source of the first destination byte
        add.w   d5,a1
        cmp.w   d5,d7
        bne.s   .bf_multi
        and.b   d2,d1                ; a single byte: both masks
        move.b  (a0),d4
        and.b   d1,d4
        not.b   d1
        and.b   d1,(a1)
        or.b    d4,(a1)
        bra.s   .bf_done
.bf_multi:
        move.b  (a0)+,d4             ; first byte (masked)
        and.b   d1,d4
        not.b   d1
        and.b   d1,(a1)
        or.b    d4,(a1)+
        sub.w   d5,d7
        subq.w  #1,d7                ; d7 = full bytes
        beq.s   .bf_last
        move.w  a0,d3                ; same parity: align to a word then copy as longs
        move.w  a1,d4
        eor.w   d4,d3
        btst    #0,d3
        bne.s   .bf_bytes
        move.w  a0,d3
        btst    #0,d3
        beq.s   .bf_even
        move.b  (a0)+,(a1)+
        subq.w  #1,d7
.bf_even:
        move.w  d7,d4
        lsr.w   #2,d4
        and.w   #3,d7
        bra.s   .bf_lnx
.bf_long:
        move.l  (a0)+,(a1)+
.bf_lnx:
        dbra    d4,.bf_long
.bf_bytes:
        subq.w  #1,d7
        bmi.s   .bf_last
.bf_mid:
        move.b  (a0)+,(a1)+
        dbra    d7,.bf_mid
.bf_last:
        move.b  (a0),d4              ; last byte (masked)
        and.b   d2,d4
        not.b   d2
        and.b   d2,(a1)
        or.b    d4,(a1)
.bf_done:
        move.l  (sp)+,a1
        addq.l  #2,sp
        rts
.bt_byte:
        moveq   #-1,d6               ; d6.b = mask of the byte
        cmp.w   (sp),d5
        bne.s   .bt_nf
        and.b   d1,d6
.bt_nf:
        cmp.w   d7,d5
        bne.s   .bt_nl
        and.b   d2,d6
.bt_nl:
        move.l  a2,d4
        beq.s   .bt_put              ; null source plane: 0
        moveq   #-1,d4
        cmp.l   a2,d4
        beq.s   .bt_put              ; source plane -1: 1
        move.w  d5,d3                ; source bit of the leftmost pixel of the byte
        lsl.w   #3,d3
        add.w   d0,d3
        move.w  d3,d4
        asr.w   #3,d4                ; source byte (-1 possible at the left edge: bits masked)
        lea     0(a2,d4.w),a0
        move.b  (a0)+,d4
        lsl.w   #8,d4
        move.b  (a0),d4
        and.w   #7,d3
        lsl.w   d3,d4
        lsr.w   #8,d4
.bt_put:
        cmp.b   #$C0,DC_MINTERM(a5)
        beq.s   .bt_copy             ; copy: direct path
        movem.l d0-d2,-(sp)
        move.b  0(a1,d5.w),d3        ; C = destination
        moveq   #0,d1                ; d1 = result
        move.b  DC_MINTERM(a5),d0
        btst    #7,d0                ; B & C
        beq.s   .mt_6
        move.b  d4,d2
        and.b   d3,d2
        or.b    d2,d1
.mt_6:
        btst    #6,d0                ; B & ~C
        beq.s   .mt_5
        move.b  d3,d2
        not.b   d2
        and.b   d4,d2
        or.b    d2,d1
.mt_5:
        btst    #5,d0                ; ~B & C
        beq.s   .mt_4
        move.b  d4,d2
        not.b   d2
        and.b   d3,d2
        or.b    d2,d1
.mt_4:
        btst    #4,d0                ; ~B & ~C
        beq.s   .mt_r
        move.b  d4,d2
        or.b    d3,d2
        not.b   d2
        or.b    d2,d1
.mt_r:
        move.b  d1,d4
        movem.l (sp)+,d0-d2
.bt_copy:
        and.b   d6,d4
        not.b   d6
        and.b   d6,0(a1,d5.w)
        or.b    d4,0(a1,d5.w)
        addq.w  #1,d5
        cmp.w   d7,d5
        ble     .bt_byte
        addq.l  #2,sp
        rts

; BltBitMap(src a0, srcX d0, srcY d1, dest a1, destX d2, destY d3, width d4, height d5, minterm d6, mask d7,
; buffer a2 ignored) -> d0 = number of planes processed. Rectangle clipped to both BitMaps. Planes: those of the mask
; present in BOTH BitMaps (NULL or -1 destination plane ignored); a NULL or -1 source plane counts as 0 / 1. Same
; source and destination BitMap: each source row goes through a buffer (no overlap possible within the row) and the
; rows are walked from bottom to top if the destination is lower.
; Frame: DC context (DC_MINTERM for dr_bits) followed by the BB_* variables.
BB_SX           EQU DC_SIZE
BB_SY           EQU DC_SIZE+2
BB_DX           EQU DC_SIZE+4
BB_DY           EQU DC_SIZE+6
BB_W            EQU DC_SIZE+8
BB_H            EQU DC_SIZE+10
BB_PLANE        EQU DC_SIZE+12           ; current plane number
BB_COUNT        EQU DC_SIZE+14           ; planes processed
BB_STEP         EQU DC_SIZE+16           ; +1 / -1 between rows
BB_CSY          EQU DC_SIZE+18           ; current source row
BB_CDY          EQU DC_SIZE+20           ; current destination row
BB_N            EQU DC_SIZE+22           ; remaining rows
BB_MASK         EQU DC_SIZE+24           ; byte
BB_BUF          EQU DC_SIZE+26           ; long: row buffer (0 if distinct BitMaps)
BB_SPLANE       EQU DC_SIZE+30           ; long: current source plane (0 / -1 / address)
BB_SIZE         EQU DC_SIZE+34
gfx_BltBitMap:
        movem.l d2-d7/a2-a6,-(sp)
        lea     -BB_SIZE(sp),sp
        move.l  sp,a5
        move.b  d6,DC_MINTERM(a5)
        move.b  d7,BB_MASK(a5)
        move.l  a0,a4                ; a4 = source, a3 = destination
        move.l  a1,a3
        clr.w   BB_COUNT(a5)
        tst.w   d0                   ; clipping to both BitMaps: left / top edges
        bpl.s   .bm_1
        add.w   d0,d4
        sub.w   d0,d2
        moveq   #0,d0
.bm_1:
        tst.w   d2
        bpl.s   .bm_2
        add.w   d2,d4
        sub.w   d2,d0
        moveq   #0,d2
.bm_2:
        tst.w   d1
        bpl.s   .bm_3
        add.w   d1,d5
        sub.w   d1,d3
        moveq   #0,d1
.bm_3:
        tst.w   d3
        bpl.s   .bm_4
        add.w   d3,d5
        sub.w   d3,d1
        moveq   #0,d3
.bm_4:
        move.w  bm_BytesPerRow(a4),d6    ; right / bottom edges
        lsl.w   #3,d6
        sub.w   d0,d6
        cmp.w   d6,d4
        ble.s   .bm_5
        move.w  d6,d4
.bm_5:
        move.w  bm_BytesPerRow(a3),d6
        lsl.w   #3,d6
        sub.w   d2,d6
        cmp.w   d6,d4
        ble.s   .bm_6
        move.w  d6,d4
.bm_6:
        move.w  bm_Rows(a4),d6
        sub.w   d1,d6
        cmp.w   d6,d5
        ble.s   .bm_7
        move.w  d6,d5
.bm_7:
        move.w  bm_Rows(a3),d6
        sub.w   d3,d6
        cmp.w   d6,d5
        ble.s   .bm_8
        move.w  d6,d5
.bm_8:
        tst.w   d4
        ble     .bm_ret
        tst.w   d5
        ble     .bm_ret
        movem.w d0-d5,BB_SX(a5)
        clr.l   BB_BUF(a5)
        cmp.l   a3,a4
        bne.s   .bm_go
        moveq   #0,d0                ; same BitMap: row buffer (+1 byte of margin on each side)
        move.w  bm_BytesPerRow(a4),d0
        addq.l  #4,d0
        moveq   #MEMF_PUBLIC,d1
        move.l  ($4).w,a6
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .bm_ret              ; no buffer: refuse rather than corrupt
        addq.l  #1,d0
        move.l  d0,BB_BUF(a5)
.bm_go:
        clr.w   BB_PLANE(a5)
.bm_plane:
        move.w  BB_PLANE(a5),d6
        moveq   #0,d0
        move.b  bm_Depth(a3),d0
        cmp.w   d0,d6
        bge     .bm_free
        move.b  bm_Depth(a4),d0      ; only the planes common to both BitMaps (spec graphics-blitter-v34 §1.1:
        cmp.w   d0,d6                ; 2-plane source to 3 planes -> 2 copied, the 3rd plane stays intact)
        bge     .bm_free
        move.b  BB_MASK(a5),d0
        btst    d6,d0
        beq     .bm_pnext
        move.w  d6,d0
        lsl.w   #2,d0
        move.l  bm_Planes(a3,d0.w),d1
        beq     .bm_pnext
        cmp.l   #-1,d1
        beq     .bm_pnext
        addq.w  #1,BB_COUNT(a5)
        move.l  bm_Planes(a4,d0.w),BB_SPLANE(a5)
.bm_rows:
        move.w  BB_SY(a5),BB_CSY(a5)
        move.w  BB_DY(a5),BB_CDY(a5)
        move.w  BB_H(a5),BB_N(a5)
        move.w  #1,BB_STEP(a5)
        tst.l   BB_BUF(a5)
        beq.s   .bm_row
        move.w  BB_DY(a5),d0
        cmp.w   BB_SY(a5),d0
        ble.s   .bm_row
        move.w  BB_H(a5),d0          ; lower destination: from bottom to top
        subq.w  #1,d0
        add.w   d0,BB_CSY(a5)
        add.w   d0,BB_CDY(a5)
        move.w  #-1,BB_STEP(a5)
.bm_row:
        move.l  BB_SPLANE(a5),a2
        move.l  a2,d0
        beq.s   .bm_dst
        cmp.l   #-1,d0
        beq.s   .bm_dst
        moveq   #0,d0
        move.w  bm_BytesPerRow(a4),d0
        mulu    BB_CSY(a5),d0
        add.l   d0,a2                ; a2 = source row
        move.l  BB_BUF(a5),d0
        beq.s   .bm_dst
        move.l  d0,a0                ; same BitMap: row copied into the buffer first
        move.l  a2,a1
        move.w  bm_BytesPerRow(a4),d0
        subq.w  #1,d0
.bm_cp:
        move.b  (a1)+,(a0)+
        dbra    d0,.bm_cp
        move.l  BB_BUF(a5),a2
.bm_dst:
        move.w  BB_PLANE(a5),d0
        lsl.w   #2,d0
        move.l  bm_Planes(a3,d0.w),a1
        moveq   #0,d0
        move.w  bm_BytesPerRow(a3),d0
        mulu    BB_CDY(a5),d0
        add.l   d0,a1                ; a1 = destination row
        move.w  BB_SX(a5),d0
        move.w  BB_DX(a5),d2
        move.w  BB_W(a5),d4
        bsr     dr_bits
        move.w  BB_STEP(a5),d0
        add.w   d0,BB_CSY(a5)
        add.w   d0,BB_CDY(a5)
        subq.w  #1,BB_N(a5)
        bne.s   .bm_row
.bm_pnext:
        addq.w  #1,BB_PLANE(a5)
        bra     .bm_plane
.bm_free:
        move.l  BB_BUF(a5),d0
        beq.s   .bm_ret
        subq.l  #1,d0
        move.l  d0,a1
        moveq   #0,d0
        move.w  bm_BytesPerRow(a4),d0
        addq.l  #4,d0
        move.l  ($4).w,a6
        jsr     LVO_FREEMEM(a6)
.bm_ret:
        moveq   #0,d0
        move.w  BB_COUNT(a5),d0
        lea     BB_SIZE(sp),sp
        movem.l (sp)+,d2-d7/a2-a6
        rts

; ReadPixel(rp a1, x d0, y d1) -> d0 = colour number of the pixel (relative to the layer), -1 if it is in no
; readable ClipRect (outside the area, or hidden without backup).
gfx_ReadPixel:
        movem.l d2-d4/a5,-(sp)
        lea     -DC_SIZE(sp),sp
        move.l  sp,a5
        movem.w d0-d1,-(sp)
        bsr     dr_ctx
        movem.w (sp)+,d0-d1
        add.w   DC_OX(a5),d0
        add.w   DC_OY(a5),d1
        move.w  d0,d2
        move.w  d1,d3
        move.l  DC_FIRST(a5),a0
.rp_lp:
        cmpa.w  #0,a0
        beq.s   .rp_none
        bsr     dr_crset
        beq.s   .rp_n
        cmp.w   DC_CMINX(a5),d2
        blt.s   .rp_n
        cmp.w   DC_CMAXX(a5),d2
        bgt.s   .rp_n
        cmp.w   DC_CMINY(a5),d3
        blt.s   .rp_n
        cmp.w   DC_CMAXY(a5),d3
        ble.s   .rp_read
.rp_n:
        move.l  CR_NEXT(a0),a0
        bra.s   .rp_lp
.rp_none:
        moveq   #-1,d0
        bra.s   .rp_out
.rp_read:
        move.l  DC_CBM(a5),a0
        sub.w   DC_BX(a5),d2
        sub.w   DC_BY(a5),d3
        moveq   #0,d1
        move.w  bm_BytesPerRow(a0),d1
        mulu    d3,d1
        move.w  d2,d4
        lsr.w   #3,d4
        add.l   d4,d1                ; d1 = offset of the byte
        not.w   d2
        and.w   #7,d2                ; d2 = bit number (7 = leftmost pixel)
        moveq   #0,d0
        moveq   #0,d3
        move.b  bm_Depth(a0),d3
        subq.w  #1,d3                ; from the highest plane to plane 0
.rp_pl:
        add.w   d0,d0
        move.w  d3,d4
        lsl.w   #2,d4
        move.l  bm_Planes(a0,d4.w),a1
        btst    d2,0(a1,d1.l)
        beq.s   .rp_z
        addq.w  #1,d0
.rp_z:
        dbra    d3,.rp_pl
        move.l  DC_RP(a5),a1
.rp_out:
        bsr     dr_end
        lea     DC_SIZE(sp),sp
        movem.l (sp)+,d2-d4/a5
        rts

; gfx_putrow(rp a1, colours a0, x d0, y d1, count d2): draws a row of pixels (one colour byte per pixel,
; 255 = transparent) at (x, y) relative to the RastPort, by runs of the same colour, through its ClipRects, in JAM2
; whatever rp_DrawMode (rp_Mask respected). Used for drawing GELs. Preserves d2-d7/a1-a6.
gfx_putrow:
        movem.l d2-d7/a2-a5,-(sp)
        lea     -DC_SIZE(sp),sp
        move.l  sp,a5
        move.l  a0,a2                ; a2 = colours
        movem.w d0-d1,-(sp)
        bsr     dr_ctx
        movem.w (sp)+,d4-d5
        add.w   DC_OX(a5),d4         ; d4 = absolute x of the first pixel
        add.w   DC_OY(a5),d5         ; d5 = absolute y
        move.b  rp_DrawMode(a1),d6
        move.b  #JAM2,rp_DrawMode(a1)
        move.w  d2,d7                ; d7 = count
        moveq   #0,d0                ; d0 = current index
.pr_lp:
        cmp.w   d7,d0
        bge.s   .pr_end
        move.b  0(a2,d0.w),d3
        cmp.b   #$FF,d3
        bne.s   .pr_run
        addq.w  #1,d0
        bra.s   .pr_lp
.pr_run:
        move.w  d0,d2
.pr_ext:
        addq.w  #1,d2
        cmp.w   d7,d2
        bge.s   .pr_emit
        cmp.b   0(a2,d2.w),d3
        beq.s   .pr_ext
.pr_emit:                            ; run [d0 .. d2-1]
        move.w  d2,-(sp)
        subq.w  #1,d2
        add.w   d4,d0
        add.w   d4,d2
        move.w  d5,d1
        bsr     dr_span
        move.w  (sp)+,d0
        bra.s   .pr_lp
.pr_end:
        move.b  d6,rp_DrawMode(a1)
        bsr     dr_end
        lea     DC_SIZE(sp),sp
        movem.l (sp)+,d2-d7/a2-a5
        rts

; LockLayerRom(layer a5) / UnlockLayerRom(layer a5): the layer's semaphore. Preserve all registers, as
; the AutoDoc requires.
gfx_LockLayerRom:
        cmpa.w  #0,a5                ; RastPort without a layer: nothing to lock
        beq.s   .lock_r
        movem.l d0-d1/a0-a1/a6,-(sp)
        lea     LY_LOCK(a5),a0
        move.l  ($4).w,a6
        jsr     LVO_OBTAINSEMAPHORE(a6)
        movem.l (sp)+,d0-d1/a0-a1/a6
.lock_r:
        rts
gfx_UnlockLayerRom:
        cmpa.w  #0,a5                ; RastPort without a layer: nothing to lock
        beq.s   .unlo_r
        movem.l d0-d1/a0-a1/a6,-(sp)
        lea     LY_LOCK(a5),a0
        move.l  ($4).w,a6
        jsr     LVO_RELEASESEMAPHORE(a6)
        movem.l (sp)+,d0-d1/a0-a1/a6
.unlo_r:
        rts
; AttemptLockLayerRom(layer a5) -> d0 = true if the layer is locked (without waiting), false if it is held by
; another task. Preserves d1/a0/a1/a6.
gfx_AttemptLockLayerRom:
        moveq   #1,d0
        cmpa.w  #0,a5
        beq.s   .alo_r
        movem.l d1/a0-a1/a6,-(sp)
        lea     LY_LOCK(a5),a0
        move.l  ($4).w,a6
        jsr     LVO_ATTEMPTSEMAPHORE(a6)
        movem.l (sp)+,d1/a0-a1/a6
.alo_r:
        rts
