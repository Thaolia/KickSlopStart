; src/graphics/regions.s — graphics.library Regions (graphics/regions.h) + rectangle list engine.
;
; A Region = bounds (struct Rectangle) + list of DISJOINT RegionRectangles. As on the Amiga, the bounds of a
; RegionRectangle are RELATIVE to region->bounds.MinX/MinY. Every public operation converts the list back to
; absolute coordinates (rg_toabs), does its work, then recomputes bounds = union of the rectangles and makes them
; relative again (rg_finish, which also rebuilds the Prev links). Inclusive rectangles (MinX..MaxX, MinY..MaxY).
; The rl_* engine (subtraction / intersection of a rectangle against a disjoint list) is shared with
; layers.library to compute the visible parts of the layers.
; Operations: return d0 = TRUE (-1), or FALSE (0) if memory runs out (the region stays consistent but
; incomplete, as the AutoDoc allows).
; IMPLEMENTATION track ("clean"): graphics.library AutoDocs (Regions) + graphics/regions.h. NO ROM reading.

                include "exec.i"
                include "graphics.i"

                xdef    gfx_NewRegion
                xdef    gfx_DisposeRegion
                xdef    gfx_ClearRegion
                xdef    gfx_OrRectRegion
                xdef    gfx_AndRectRegion
                xdef    gfx_ClearRectRegion
                xdef    gfx_XorRectRegion
                xdef    gfx_OrRegionRegion
                xdef    gfx_AndRegionRegion
                xdef    gfx_XorRegionRegion
                xdef    rl_sub
                xdef    rl_and
                xdef    rl_add
                xdef    rl_free

; --- list node = RegionRectangle (Next, Prev, bounds) ---
RR_NEXT         EQU 0
RR_PREV         EQU 4
RR_MINX         EQU 8
RR_MINY         EQU 10
RR_MAXX         EQU 12
RR_MAXY         EQU 14
RR_SIZE         EQU 16
RG_MINX         EQU 0                ; struct Region
RG_MINY         EQU 2
RG_MAXX         EQU 4
RG_MAXY         EQU 6
RG_RECTS        EQU 8                ; head cell of the list
RG_SIZE         EQU 12

; ============================ rl_* engine (absolute coordinates) ============================
; List designated by a2 = address of the cell pointing to the first node (RG_RECTS(region), or any
; long). Rectangle designated by a1 (MinX, MinY, MaxX, MaxY: 4 words). The rl_* preserve d2-d7/a2-a6.

; rl_add(a2 = list, a1 = rectangle): adds a node at the head (the caller guarantees disjointness). d0 = 0 ok,
; -1 memory.
rl_add:
        movem.l a1/a6,-(sp)
        move.l  ($4).w,a6
        moveq   #RR_SIZE,d0
        move.l  #MEMF_PUBLIC,d1
        jsr     LVO_ALLOCMEM(a6)
        movem.l (sp)+,a1/a6
        tst.l   d0
        beq.s   .ad_nomem
        move.l  d0,a0
        move.l  (a1),RR_MINX(a0)
        move.l  4(a1),RR_MAXX(a0)
        move.l  (a2),RR_NEXT(a0)
        move.l  a0,(a2)
        moveq   #0,d0
        rts
.ad_nomem:
        moveq   #-1,d0
        rts

; rl_free(a2 = list): frees all nodes; cell reset to 0.
rl_free:
        movem.l a3/a6,-(sp)
        move.l  ($4).w,a6
.fr_lp:
        move.l  (a2),d0
        beq.s   .fr_out
        move.l  d0,a1
        move.l  RR_NEXT(a1),(a2)
        moveq   #RR_SIZE,d0
        jsr     LVO_FREEMEM(a6)
        bra.s   .fr_lp
.fr_out:
        movem.l (sp)+,a3/a6
        rts

; rl_and(a2 = list, a1 = rectangle): each node becomes its intersection with the rectangle; empty ones are
; freed.
rl_and:
        movem.l d2-d5/a3-a4/a6,-(sp)
        move.l  ($4).w,a6
        movem.w (a1),d2-d5           ; d2..d5 = MinX, MinY, MaxX, MaxY of the rectangle (extended to longs)
        move.l  a2,a4                ; a4 = previous cell
.an_lp:
        move.l  (a4),d0
        beq.s   .an_out
        move.l  d0,a3
        cmp.w   RR_MINX(a3),d2
        ble.s   .an_x0
        move.w  d2,RR_MINX(a3)
.an_x0:
        cmp.w   RR_MINY(a3),d3
        ble.s   .an_y0
        move.w  d3,RR_MINY(a3)
.an_y0:
        cmp.w   RR_MAXX(a3),d4
        bge.s   .an_x1
        move.w  d4,RR_MAXX(a3)
.an_x1:
        cmp.w   RR_MAXY(a3),d5
        bge.s   .an_y1
        move.w  d5,RR_MAXY(a3)
.an_y1:
        move.w  RR_MINX(a3),d0
        cmp.w   RR_MAXX(a3),d0
        bgt.s   .an_drop
        move.w  RR_MINY(a3),d0
        cmp.w   RR_MAXY(a3),d0
        bgt.s   .an_drop
        move.l  a3,a4                ; node kept: advance
        bra.s   .an_lp
.an_drop:
        move.l  RR_NEXT(a3),(a4)
        move.l  a3,a1
        moveq   #RR_SIZE,d0
        jsr     LVO_FREEMEM(a6)
        bra.s   .an_lp
.an_out:
        movem.l (sp)+,d2-d5/a3-a4/a6
        rts

; rl_sub(a2 = list, a1 = rectangle): removes the rectangle from each node. An overlapped node splits into at
; most 4 pieces (top band, bottom band, left and right of the common band): the 1st reuses the node,
; the others are inserted right after it. d0 = 0 ok, -1 memory.
rl_sub:
        movem.l d2-d7/a3-a6,-(sp)
        move.l  ($4).w,a6
        movem.w (a1),d2-d5           ; rectangle B
        moveq   #0,d7                ; d7 = result
        move.l  a2,a4                ; a4 = previous cell
        lea     -32(sp),sp           ; 4 pieces x 8 bytes
        move.l  sp,a5
.sb_lp:
        move.l  (a4),d0
        beq     .sb_out
        move.l  d0,a3
        cmp.w   RR_MAXX(a3),d2       ; no overlap -> node intact
        bgt     .sb_keep
        cmp.w   RR_MINX(a3),d4
        blt     .sb_keep
        cmp.w   RR_MAXY(a3),d3
        bgt     .sb_keep
        cmp.w   RR_MINY(a3),d5
        blt     .sb_keep
        move.l  a5,a0                ; pieces
        moveq   #0,d6                ; d6 = number of pieces
        move.w  RR_MINY(a3),d0       ; top band: A.MinY .. B.MinY-1
        cmp.w   d3,d0
        bge.s   .sb_nt
        move.w  RR_MINX(a3),(a0)+
        move.w  d0,(a0)+
        move.w  RR_MAXX(a3),(a0)+
        move.w  d3,d1
        subq.w  #1,d1
        move.w  d1,(a0)+
        addq.w  #1,d6
.sb_nt:
        move.w  RR_MAXY(a3),d0       ; bottom band: B.MaxY+1 .. A.MaxY
        cmp.w   d5,d0
        ble.s   .sb_nb
        move.w  RR_MINX(a3),(a0)+
        move.w  d5,d1
        addq.w  #1,d1
        move.w  d1,(a0)+
        move.w  RR_MAXX(a3),(a0)+
        move.w  d0,(a0)+
        addq.w  #1,d6
.sb_nb:
        move.w  RR_MINY(a3),d0       ; common band: max(MinY) .. min(MaxY) -> d0..d1
        cmp.w   d3,d0
        bge.s   .sb_m0
        move.w  d3,d0
.sb_m0:
        move.w  RR_MAXY(a3),d1
        cmp.w   d5,d1
        ble.s   .sb_m1
        move.w  d5,d1
.sb_m1:
        cmp.w   RR_MINX(a3),d2       ; left: A.MinX .. B.MinX-1
        ble.s   .sb_nl
        move.w  RR_MINX(a3),(a0)+
        move.w  d0,(a0)+
        move.w  d2,(a0)
        subq.w  #1,(a0)+
        move.w  d1,(a0)+
        addq.w  #1,d6
.sb_nl:
        cmp.w   RR_MAXX(a3),d4       ; right: B.MaxX+1 .. A.MaxX
        bge.s   .sb_nr
        move.w  d4,(a0)
        addq.w  #1,(a0)+
        move.w  d0,(a0)+
        move.w  RR_MAXX(a3),(a0)+
        move.w  d1,(a0)+
        addq.w  #1,d6
.sb_nr:
        tst.w   d6
        bne.s   .sb_pieces
        move.l  RR_NEXT(a3),(a4)     ; fully overlapped: node removed
        move.l  a3,a1
        moveq   #RR_SIZE,d0
        jsr     LVO_FREEMEM(a6)
        bra     .sb_lp
.sb_pieces:
        move.l  (a5),RR_MINX(a3)     ; 1st piece in the node
        move.l  4(a5),RR_MAXX(a3)
        lea     8(a5),a0
        subq.w  #2,d6
        bmi.s   .sb_adv
.sb_ins:
        movem.l d0-d1/a0,-(sp)
        moveq   #RR_SIZE,d0
        move.l  #MEMF_PUBLIC,d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  d0,a1
        movem.l (sp)+,d0-d1/a0
        move.l  a1,d1
        bne.s   .sb_got
        moveq   #-1,d7               ; memory: remaining pieces lost
        bra.s   .sb_adv
.sb_got:
        move.l  (a0)+,RR_MINX(a1)
        move.l  (a0)+,RR_MAXX(a1)
        move.l  RR_NEXT(a3),RR_NEXT(a1)
        move.l  a1,RR_NEXT(a3)
        move.l  a1,a3                ; the pieces are outside B: advance past them
        dbra    d6,.sb_ins
.sb_adv:
        move.l  a3,a4
        bra     .sb_lp
.sb_keep:
        move.l  a3,a4
        bra     .sb_lp
.sb_out:
        lea     32(sp),sp
        move.l  d7,d0
        movem.l (sp)+,d2-d7/a3-a6
        rts

; ============================ public Regions ============================
; Each public function saves d2-d7/a2-a6; a3 = region being processed, a2 = cell of its list (absolute during
; the operation), d7 = accumulated memory failure, common exit rg_exit.

; rg_toabs(a0 = region): rectangles in absolute coordinates. Uses d0/d1/a1.
rg_toabs:
        move.w  RG_MINX(a0),d0
        move.w  RG_MINY(a0),d1
        move.l  RG_RECTS(a0),a1
.ta_lp:
        cmpa.w  #0,a1
        beq.s   .ta_r
        add.w   d0,RR_MINX(a1)
        add.w   d0,RR_MAXX(a1)
        add.w   d1,RR_MINY(a1)
        add.w   d1,RR_MAXY(a1)
        move.l  RR_NEXT(a1),a1
        bra.s   .ta_lp
.ta_r:
        rts

; rg_finish(a0 = region): bounds = union of the rectangles (0 if empty), rectangles made relative, Prev links rebuilt.
; Uses d0-d5/a1/a2.
rg_finish:
        move.l  RG_RECTS(a0),d0
        bne.s   .fi_some
        clr.l   RG_MINX(a0)
        clr.l   RG_MAXX(a0)
        rts
.fi_some:
        move.w  #$7FFF,d2
        move.w  d2,d3
        move.w  #$8000,d4
        move.w  d4,d5
        move.l  d0,a1
.fi_b:
        cmp.w   RR_MINX(a1),d2
        ble.s   .fi_b0
        move.w  RR_MINX(a1),d2
.fi_b0:
        cmp.w   RR_MINY(a1),d3
        ble.s   .fi_b1
        move.w  RR_MINY(a1),d3
.fi_b1:
        cmp.w   RR_MAXX(a1),d4
        bge.s   .fi_b2
        move.w  RR_MAXX(a1),d4
.fi_b2:
        cmp.w   RR_MAXY(a1),d5
        bge.s   .fi_b3
        move.w  RR_MAXY(a1),d5
.fi_b3:
        move.l  RR_NEXT(a1),a1
        cmpa.w  #0,a1
        bne.s   .fi_b
        movem.w d2-d5,RG_MINX(a0)
        move.l  d0,a1
        suba.l  a2,a2
.fi_rel:
        sub.w   d2,RR_MINX(a1)
        sub.w   d2,RR_MAXX(a1)
        sub.w   d3,RR_MINY(a1)
        sub.w   d3,RR_MAXY(a1)
        move.l  a2,RR_PREV(a1)
        move.l  a1,a2
        move.l  RR_NEXT(a1),a1
        cmpa.w  #0,a1
        bne.s   .fi_rel
        rts

; rg_open(a0 = region): a3 = region, absolute list, a2 = its cell, d7 = 0.
rg_open:
        move.l  a0,a3
        bsr     rg_toabs
        lea     RG_RECTS(a3),a2
        moveq   #0,d7
        rts
; rg_exit: finishes region a3, d0 = TRUE / FALSE, restores and returns (branch to it, do not call it).
rg_exit:
        move.l  a3,a0
        bsr     rg_finish
        moveq   #-1,d0
        tst.l   d7
        beq.s   .ex_r
        moveq   #0,d0
.ex_r:
        movem.l (sp)+,d2-d7/a2-a6
        rts

; NewRegion() -> d0 = empty region, or 0.
gfx_NewRegion:
        move.l  a6,-(sp)
        move.l  ($4).w,a6
        moveq   #RG_SIZE,d0
        move.l  #MEMF_PUBLIC|MEMF_CLEAR,d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  (sp)+,a6
        rts

; ClearRegion(region a0): empties the region.
gfx_ClearRegion:
        move.l  a2,-(sp)
        move.l  a0,-(sp)
        lea     RG_RECTS(a0),a2
        bsr     rl_free
        move.l  (sp)+,a0
        clr.l   RG_MINX(a0)
        clr.l   RG_MAXX(a0)
        move.l  (sp)+,a2
        rts

; DisposeRegion(region a0): empties then frees the region (0 accepted).
gfx_DisposeRegion:
        move.l  a0,d0
        beq.s   .dr_r
        move.l  a0,-(sp)
        bsr     gfx_ClearRegion
        move.l  (sp)+,a1
        move.l  a6,-(sp)
        move.l  ($4).w,a6
        moveq   #RG_SIZE,d0
        jsr     LVO_FREEMEM(a6)
        move.l  (sp)+,a6
.dr_r:
        rts

; OrRectRegion(region a0, rectangle a1): region ∪= rectangle.
gfx_OrRectRegion:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  a1,a4
        bsr     rg_open
        move.l  a4,a1
        bsr     rl_sub
        move.l  d0,d7
        move.l  a4,a1
        bsr     rl_add
        or.l    d0,d7
        bra     rg_exit

; AndRectRegion(region a0, rectangle a1): region ∩= rectangle.
gfx_AndRectRegion:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  a1,a4
        bsr     rg_open
        move.l  a4,a1
        bsr     rl_and
        bra     rg_exit

; ClearRectRegion(region a0, rectangle a1): region -= rectangle.
gfx_ClearRectRegion:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  a1,a4
        bsr     rg_open
        move.l  a4,a1
        bsr     rl_sub
        move.l  d0,d7
        bra     rg_exit

; XorRectRegion(region a0, rectangle a1): region = (region - rectangle) ∪ (rectangle - region).
gfx_XorRectRegion:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  a1,a4
        bsr     rg_open
        move.l  a4,a1
        bsr     rg_xorabs
        move.l  d0,d7
        bra     rg_exit

; rg_xorabs(a2 = absolute list, a1 = rectangle) -> d0 = 0 / -1. The pieces of the rectangle outside the list are
; computed in a temporary list (cell on the stack), the list loses the rectangle, then the two are merged.
; Preserves d2-d7/a2-a6.
rg_xorabs:
        movem.l d7/a2-a5,-(sp)
        move.l  a1,a4
        move.l  a2,a5                ; a5 = cell of the list
        clr.l   -(sp)                ; temporary cell
        move.l  sp,a2
        bsr     rl_add               ; temp = { rectangle }
        move.l  d0,d7
        move.l  (a5),a3
.xo_lp:
        cmpa.w  #0,a3
        beq.s   .xo_cut
        lea     RR_MINX(a3),a1
        bsr     rl_sub               ; temp -= each rectangle of the list
        or.l    d0,d7
        move.l  RR_NEXT(a3),a3
        bra.s   .xo_lp
.xo_cut:
        move.l  a5,a2
        move.l  a4,a1
        bsr     rl_sub               ; list -= rectangle
        or.l    d0,d7
        move.l  (sp)+,d0
        beq.s   .xo_r
        move.l  d0,a1
.xo_tail:
        tst.l   RR_NEXT(a1)
        beq.s   .xo_link
        move.l  RR_NEXT(a1),a1
        bra.s   .xo_tail
.xo_link:
        move.l  (a5),RR_NEXT(a1)     ; temp at the head of the list
        move.l  d0,(a5)
.xo_r:
        move.l  d7,d0
        movem.l (sp)+,d7/a2-a5
        rts

; rg_srcrect(a0 = source region, a4 = its node, a5 = 8-byte buffer) -> a1 = a5 = absolute rectangle of the node.
rg_srcrect:
        move.l  a5,a1
        move.w  RG_MINX(a0),d0
        move.w  RG_MINY(a0),d1
        move.w  RR_MINX(a4),(a1)
        add.w   d0,(a1)
        move.w  RR_MINY(a4),2(a1)
        add.w   d1,2(a1)
        move.w  RR_MAXX(a4),4(a1)
        add.w   d0,4(a1)
        move.w  RR_MAXY(a4),6(a1)
        add.w   d1,6(a1)
        rts

; rg_open2(src a0, dest a1): d6 = source, destination region opened (a3/a2/d7), a5 = 16-byte buffer on
; the stack (freed by rg_exit2), a4 = first node of the source.
rg_open2:
        move.l  (sp)+,d0             ; return
        lea     -16(sp),sp
        move.l  sp,a5
        move.l  d0,-(sp)
        move.l  a0,d6
        move.l  a1,a0
        bsr     rg_open
        move.l  d6,a0
        move.l  RG_RECTS(a0),a4
        rts
rg_exit2:
        lea     16(sp),sp
        bra     rg_exit

; OrRegionRegion(src a0, dest a1): dest ∪= src.
gfx_OrRegionRegion:
        movem.l d2-d7/a2-a6,-(sp)
        bsr     rg_open2
.or_lp:
        cmpa.w  #0,a4
        beq.s   .or_out
        move.l  d6,a0
        bsr     rg_srcrect
        bsr     rl_sub
        or.l    d0,d7
        move.l  a5,a1
        bsr     rl_add
        or.l    d0,d7
        move.l  RR_NEXT(a4),a4
        bra.s   .or_lp
.or_out:
        bra     rg_exit2

; XorRegionRegion(src a0, dest a1): dest = dest xor src (src rectangles disjoint: successive xors).
gfx_XorRegionRegion:
        movem.l d2-d7/a2-a6,-(sp)
        bsr     rg_open2
.xr_lp:
        cmpa.w  #0,a4
        beq.s   .xr_out
        move.l  d6,a0
        bsr     rg_srcrect
        bsr     rg_xorabs
        or.l    d0,d7
        move.l  RR_NEXT(a4),a4
        bra.s   .xr_lp
.xr_out:
        bra     rg_exit2

; AndRegionRegion(src a0, dest a1): dest = ∪ (d ∩ s) over the rectangles d of dest and s of src (pairwise
; disjoint, hence so are the intersections). The old dest list is detached then freed.
gfx_AndRegionRegion:
        movem.l d2-d7/a2-a6,-(sp)
        bsr     rg_open2
        move.l  (a2),d5              ; d5 = old dest list
        clr.l   (a2)
.ar_src:
        cmpa.w  #0,a4
        beq.s   .ar_out
        move.l  d6,a0
        bsr     rg_srcrect
        move.l  d5,a0
.ar_dst:
        cmpa.w  #0,a0
        beq.s   .ar_nexts
        move.w  RR_MINX(a0),d0       ; intersection -> 8(a5)
        cmp.w   (a5),d0
        bge.s   .ar_1
        move.w  (a5),d0
.ar_1:
        move.w  d0,8(a5)
        move.w  RR_MINY(a0),d0
        cmp.w   2(a5),d0
        bge.s   .ar_2
        move.w  2(a5),d0
.ar_2:
        move.w  d0,10(a5)
        move.w  RR_MAXX(a0),d0
        cmp.w   4(a5),d0
        ble.s   .ar_3
        move.w  4(a5),d0
.ar_3:
        move.w  d0,12(a5)
        cmp.w   8(a5),d0
        blt.s   .ar_nextd
        move.w  RR_MAXY(a0),d0
        cmp.w   6(a5),d0
        ble.s   .ar_4
        move.w  6(a5),d0
.ar_4:
        move.w  d0,14(a5)
        cmp.w   10(a5),d0
        blt.s   .ar_nextd
        move.l  a0,-(sp)
        lea     8(a5),a1
        bsr     rl_add
        or.l    d0,d7
        move.l  (sp)+,a0
.ar_nextd:
        move.l  RR_NEXT(a0),a0
        bra.s   .ar_dst
.ar_nexts:
        move.l  RR_NEXT(a4),a4
        bra.s   .ar_src
.ar_out:
        move.l  d5,-(sp)             ; frees the old list (cell on the stack)
        move.l  a2,-(sp)
        lea     4(sp),a2
        bsr     rl_free
        move.l  (sp)+,a2
        addq.l  #4,sp
        bra     rg_exit2
