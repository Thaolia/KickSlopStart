; src/graphics/regions.s — graphics.library Regions (graphics/regions.h) + rectangle list engine.
;
; A Region = bounds (struct Rectangle) + list of DISJOINT RegionRectangles. As on the Amiga, the bounds of a
; RegionRectangle are RELATIVE to region->bounds.MinX/MinY. Every public operation converts the list back to
; absolute coordinates (rg_toabs), does its work, then recomputes bounds = union of the rectangles and makes them
; relative again (rg_finish, which also rebuilds the Prev links). Inclusive rectangles (MinX..MaxX, MinY..MaxY).
; The rl_* engine (subtraction / intersection of a rectangle against a disjoint list) is shared with
; layers.library to compute the visible parts of the layers.
; The public functions follow docs/analysis/graphics-regions-v34.md (order of the nodes, bounds, return values).
; IMPLEMENTATION track ("clean"): docs/analysis/graphics-regions-v34.md + AutoDocs + graphics/regions.h.

                include "exec.i"
                include "graphics.i"

                xdef    gfx_NewRegion
                xdef    gfx_rpflush          ; exec AllocMem, after a failure
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

; Pool of 16-byte blocks (RegionRectangles; Region headers, 12 bytes, take 16 from exec too): a menu box or a layer
; move allocates and frees dozens of them, and each AllocMem / FreeMem walks the free list of a fragmented slow-RAM
; header. Freed blocks are kept (up to RP_MAX, 2 KB) and given back first; each is a genuine AllocMem(16) block, so
; code that hands one straight to FreeMem stays correct. Under Forbid; emptied by gfx_rpflush when AllocMem fails.
RP_MAX          EQU 128

; rp_alloc(d1 = requirements, a6 = SysBase) -> d0 = 16-byte block | 0, as AllocMem(16, d1) (MEMF_CLEAR honoured).
; Changes d0/a0/a1.
rp_alloc:
        addq.b  #1,EB_TDNEST(a6)     ; Forbid, inline
        move.l  GFX_RPOOL,d0
        beq.s   .pa_exec
        move.l  d0,a0
        move.l  (a0),GFX_RPOOL
        subq.w  #1,GFX_RPOOLN
        bsr.s   rp_permit
        btst    #16,d1               ; MEMF_CLEAR
        beq.s   .pa_ret
        clr.l   (a0)+
        clr.l   (a0)+
        clr.l   (a0)+
        clr.l   (a0)
.pa_ret:
        rts
.pa_exec:
        bsr.s   rp_permit
        moveq   #RR_SIZE,d0
        jmp     LVO_ALLOCMEM(a6)

; rp_free(a1 = 16-byte block, a6 = SysBase), as FreeMem(a1, 16). Changes d0/d1/a0; a1 preserved.
rp_free:
        addq.b  #1,EB_TDNEST(a6)     ; Forbid, inline
        cmp.w   #RP_MAX,GFX_RPOOLN
        bhs.s   .pf_exec
        move.l  GFX_RPOOL,(a1)
        move.l  a1,GFX_RPOOL
        addq.w  #1,GFX_RPOOLN
        bra.s   rp_permit
.pf_exec:
        bsr.s   rp_permit
        moveq   #RR_SIZE,d0
        jmp     LVO_FREEMEM(a6)

; rp_permit: Permit, inline unless it must reschedule (then through the vector, as exec_Permit would).
; Flags changed, registers preserved.
rp_permit:
        subq.b  #1,EB_TDNEST(a6)
        bge.s   .pp_r
        tst.b   EB_IDNEST(a6)
        bge.s   .pp_r
        btst    #SFB_SAR,EB_SYSFLAGS(a6)
        beq.s   .pp_r
        addq.b  #1,EB_TDNEST(a6)
        jmp     LVO_PERMIT(a6)
.pp_r:
        rts

; gfx_rpflush(a6 = SysBase, under Forbid): the pooled blocks go back to exec. Preserves d2-d7/a2-a6.
gfx_rpflush:
.pl_lp:
        move.l  GFX_RPOOL,d0
        beq.s   .pl_ret
        move.l  d0,a1
        move.l  (a1),GFX_RPOOL
        subq.w  #1,GFX_RPOOLN
        moveq   #RR_SIZE,d0
        jsr     LVO_FREEMEM(a6)
        bra.s   .pl_lp
.pl_ret:
        rts

; ============================ rl_* engine (absolute coordinates) ============================
; List designated by a2 = address of the cell pointing to the first node (RG_RECTS(region), or any
; long). Rectangle designated by a1 (MinX, MinY, MaxX, MaxY: 4 words). The rl_* preserve d2-d7/a2-a6.

; rl_add(a2 = list, a1 = rectangle): adds a node at the head (the caller guarantees disjointness). d0 = 0 ok,
; -1 memory.
rl_add:
        movem.l a1/a6,-(sp)
        move.l  ($4).w,a6
        move.l  #MEMF_PUBLIC,d1
        bsr     rp_alloc
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
        bsr     rp_free
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
        bsr     rp_free
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
        bsr     rp_free
        bra     .sb_lp
.sb_pieces:
        move.l  (a5),RR_MINX(a3)     ; 1st piece in the node
        move.l  4(a5),RR_MAXX(a3)
        lea     8(a5),a0
        subq.w  #2,d6
        bmi.s   .sb_adv
.sb_ins:
        movem.l d0-d1/a0,-(sp)
        move.l  #MEMF_PUBLIC,d1
        bsr     rp_alloc
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
; Spec graphics-regions-v34: nodes are never merged nor sorted; the order follows §4 (Or: the new rectangle cut
; against each node in list order through a pending list appended at the tail; Xor: the old nodes outside the
; rectangle, then the rectangle minus the old nodes; And: nodes kept, cut to one piece, or replaced by the
; rectangle). Nodes are AllocMem(16, MEMF_CLEAR), regions AllocMem(12, MEMF_CLEAR); first node's Prev = region + 8.
; During an operation the nodes hold absolute coordinates; rg_rel makes them relative to bounds.MinX/MinY again.
; A node allocation that 1.3 does not survive raises the dead-end alert AN_RegionMemory.
AN_REGIONMEMORY EQU $8201000B
RG_EMPTYSHIFT   EQU 15000            ; normalisation shift of a region left without rectangles (§5)

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

; rg_rel(a0 = region): rectangles relative to bounds.MinX/MinY, Prev links rebuilt (first: region + 8).
; Uses d0/d1/a1/a2.
rg_rel:
        move.w  RG_MINX(a0),d0
        move.w  RG_MINY(a0),d1
        lea     RG_RECTS(a0),a2
        move.l  (a2),a1
.re_lp:
        cmpa.w  #0,a1
        beq.s   .re_r
        sub.w   d0,RR_MINX(a1)
        sub.w   d0,RR_MAXX(a1)
        sub.w   d1,RR_MINY(a1)
        sub.w   d1,RR_MAXY(a1)
        move.l  a2,RR_PREV(a1)
        move.l  a1,a2
        move.l  RR_NEXT(a1),a1
        bra.s   .re_lp
.re_r:
        rts

; rg_norm(a0 = absolute region, d2-d5 = base bounds) -> d0 = Y shift (word, zero-extended): bounds = base moved by
; (smallest node MinX, smallest node MinY) - base Min on all four words, or by 15000 without nodes; then rg_rel.
; Uses d0/d1/a1/a2.
rg_norm:
        movem.l d2-d7,-(sp)
        move.l  RG_RECTS(a0),a1
        cmpa.w  #0,a1
        bne.s   .no_some
        move.w  #RG_EMPTYSHIFT,d6
        move.w  d6,d7
        bra.s   .no_set
.no_some:
        move.w  #$7FFF,d6
        move.w  d6,d7
.no_min:
        cmp.w   RR_MINX(a1),d6
        ble.s   .no_x
        move.w  RR_MINX(a1),d6
.no_x:
        cmp.w   RR_MINY(a1),d7
        ble.s   .no_y
        move.w  RR_MINY(a1),d7
.no_y:
        move.l  RR_NEXT(a1),a1
        cmpa.w  #0,a1
        bne.s   .no_min
        sub.w   d2,d6                ; shifts
        sub.w   d3,d7
.no_set:
        add.w   d6,d2
        add.w   d6,d4
        add.w   d7,d3
        add.w   d7,d5
        movem.w d2-d5,RG_MINX(a0)
        moveq   #0,d0
        move.w  d7,d0
        move.l  d0,-(sp)
        bsr     rg_rel
        move.l  (sp)+,d0
        movem.l (sp)+,d2-d7
        rts

; rg_overlap(a0 = rectangle A, a1 = rectangle B) -> Z = 0 if they share a pixel. Uses d0.
rg_overlap:
        move.w  (a0),d0
        cmp.w   4(a1),d0
        bgt.s   .ov_no
        move.w  4(a0),d0
        cmp.w   (a1),d0
        blt.s   .ov_no
        move.w  2(a0),d0
        cmp.w   6(a1),d0
        bgt.s   .ov_no
        move.w  6(a0),d0
        cmp.w   2(a1),d0
        blt.s   .ov_no
        moveq   #1,d0
        rts
.ov_no:
        moveq   #0,d0
        rts
; rg_inside(a0 = rectangle A, a1 = rectangle B) -> Z = 0 if A lies within B (edges included). Uses d0.
rg_inside:
        move.w  (a0),d0
        cmp.w   (a1),d0
        blt.s   .in_no
        move.w  2(a0),d0
        cmp.w   2(a1),d0
        blt.s   .in_no
        move.w  4(a0),d0
        cmp.w   4(a1),d0
        bgt.s   .in_no
        move.w  6(a0),d0
        cmp.w   6(a1),d0
        bgt.s   .in_no
        moveq   #1,d0
        rts
.in_no:
        moveq   #0,d0
        rts

; rg_alloc(a1 = rectangle) -> d0 = new node holding it (Next 0), or 0. Preserves d2-d7/a0-a6.
rg_alloc:
        movem.l a0-a1/a6,-(sp)
        move.l  ($4).w,a6
        move.l  #MEMF_CLEAR,d1
        bsr     rp_alloc
        movem.l (sp)+,a0-a1/a6
        tst.l   d0
        beq.s   .al_r
        move.l  a0,-(sp)
        move.l  d0,a0
        move.l  (a1),RR_MINX(a0)
        move.l  4(a1),RR_MAXX(a0)
        move.l  (sp)+,a0
.al_r:
        rts
; rg_new(a1 = rectangle, a2 = last link of a list) -> a2 = the new node, appended; dead-end alert without
; memory. Preserves d2-d7/a0/a1/a3-a6.
rg_new:
        bsr.s   rg_alloc
        tst.l   d0
        bne.s   .nw_ok
        move.l  #AN_REGIONMEMORY,d7
        move.l  ($4).w,a6
        jsr     LVO_ALERT(a6)
.nw_ok:
        move.l  d0,(a2)
        move.l  d0,a2
        rts
; rg_free(a1 = node). Preserves all registers except d0/d1.
rg_free:
        movem.l a0-a1/a6,-(sp)
        move.l  ($4).w,a6
        bsr     rp_free
        movem.l (sp)+,a0-a1/a6
        rts

; rg_bands(a0 = rectangle A, a1 = rectangle B overlapping it, a2 = last link) -> a2: the parts of A outside B
; appended (§4.4): left and right bands over A's rows, then top and bottom bands over the common columns.
; Preserves d2-d7/a0/a1/a3-a6.
rg_bands:
        movem.l d2-d5/a3,-(sp)
        subq.l  #8,sp
        move.l  sp,a3
        movem.w (a0),d2-d5           ; A
        cmp.w   (a1),d2              ; left
        bge.s   .bd_r
        move.w  d2,(a3)
        move.w  d3,2(a3)
        move.w  (a1),d0
        subq.w  #1,d0
        move.w  d0,4(a3)
        move.w  d5,6(a3)
        bsr.s   .bd_add
.bd_r:
        cmp.w   4(a1),d4             ; right
        ble.s   .bd_c
        move.w  4(a1),d0
        addq.w  #1,d0
        move.w  d0,(a3)
        move.w  d3,2(a3)
        move.w  d4,4(a3)
        move.w  d5,6(a3)
        bsr.s   .bd_add
.bd_c:
        cmp.w   (a1),d2              ; common columns
        bge.s   .bd_c0
        move.w  (a1),d2
.bd_c0:
        cmp.w   4(a1),d4
        ble.s   .bd_c1
        move.w  4(a1),d4
.bd_c1:
        cmp.w   2(a1),d3             ; top
        bge.s   .bd_b
        move.w  d2,(a3)
        move.w  d3,2(a3)
        move.w  d4,4(a3)
        move.w  2(a1),d0
        subq.w  #1,d0
        move.w  d0,6(a3)
        bsr.s   .bd_add
.bd_b:
        cmp.w   6(a1),d5             ; bottom
        ble.s   .bd_ret
        move.w  d2,(a3)
        move.w  6(a1),d0
        addq.w  #1,d0
        move.w  d0,2(a3)
        move.w  d4,4(a3)
        move.w  d5,6(a3)
        bsr.s   .bd_add
.bd_ret:
        addq.l  #8,sp
        movem.l (sp)+,d2-d5/a3
        rts
.bd_add:
        move.l  a1,-(sp)
        move.l  a3,a1
        bsr     rg_new
        move.l  (sp)+,a1
        rts

; rg_cut(a4 = cell of the pending list, a2 = its last link, a5 = first node of a list E) -> a2: each pending
; rectangle that overlaps an E (in E's order) is replaced by its bands outside E, appended at the end of the
; pending list (§4.5 step 3). Preserves d2-d7/a3-a6.
rg_cut:
        movem.l a3/a5,-(sp)
.ct_e:
        cmpa.w  #0,a5
        beq.s   .ct_ret
        move.l  a4,a3                ; a3 = link pointing to the pending rectangle
.ct_p:
        move.l  (a3),d0
        beq.s   .ct_en
        move.l  d0,a0
        lea     RR_MINX(a0),a0
        lea     RR_MINX(a5),a1
        bsr     rg_overlap
        beq.s   .ct_pn
        lea     -RR_MINX(a0),a0      ; a0 = pending node: unlinked first
        move.l  RR_NEXT(a0),(a3)
        cmpa.l  a0,a2
        bne.s   .ct_tl
        move.l  a3,a2
.ct_tl:
        move.l  a0,-(sp)
        lea     RR_MINX(a0),a0
        bsr     rg_inside
        bne.s   .ct_fr
        bsr     rg_bands
.ct_fr:
        move.l  (sp)+,a1
        bsr     rg_free
        bra.s   .ct_p
.ct_pn:
        move.l  (a3),a3
        bra.s   .ct_p
.ct_en:
        move.l  RR_NEXT(a5),a5
        bra.s   .ct_e
.ct_ret:
        movem.l (sp)+,a3/a5
        rts

; rg_last(a0 = region) -> a2 = last link of its list. Uses nothing else.
rg_last:
        lea     RG_RECTS(a0),a2
.la_lp:
        tst.l   (a2)
        beq.s   .la_r
        move.l  (a2),a2
        bra.s   .la_lp
.la_r:
        rts

; rg_freelist(a1 = first node): frees the chain. Uses d0/d1/a1.
rg_freelist:
        cmpa.w  #0,a1
        beq.s   .fl_r
        move.l  RR_NEXT(a1),-(sp)
        bsr     rg_free
        move.l  (sp)+,a1
        bra.s   rg_freelist
.fl_r:
        rts

; rg_union(a0 = region, a1 = rectangle): bounds := rectangle if the region is empty, else their union. Uses d0.
rg_union:
        tst.l   RG_RECTS(a0)
        bne.s   .un_both
        move.l  (a1),RG_MINX(a0)
        move.l  4(a1),RG_MAXX(a0)
        rts
.un_both:
        move.w  (a1),d0
        cmp.w   RG_MINX(a0),d0
        bge.s   .un_1
        move.w  d0,RG_MINX(a0)
.un_1:
        move.w  2(a1),d0
        cmp.w   RG_MINY(a0),d0
        bge.s   .un_2
        move.w  d0,RG_MINY(a0)
.un_2:
        move.w  4(a1),d0
        cmp.w   RG_MAXX(a0),d0
        ble.s   .un_3
        move.w  d0,RG_MAXX(a0)
.un_3:
        move.w  6(a1),d0
        cmp.w   RG_MAXY(a0),d0
        ble.s   .un_r
        move.w  d0,RG_MAXY(a0)
.un_r:
        rts

; NewRegion() -> d0 = empty region (bounds 0), or 0.
gfx_NewRegion:
        move.l  a6,-(sp)
        move.l  ($4).w,a6
        move.l  #MEMF_CLEAR,d1
        bsr     rp_alloc
        move.l  (sp)+,a6
        rts

; ClearRegion(region a0): bounds 0, every node freed, list empty.
gfx_ClearRegion:
        clr.l   RG_MINX(a0)
        clr.l   RG_MAXX(a0)
        move.l  RG_RECTS(a0),a1
        clr.l   RG_RECTS(a0)
        move.l  a0,-(sp)
        bsr.s   rg_freelist
        move.l  (sp)+,a0
        moveq   #0,d0
        rts

; DisposeRegion(region a0): ClearRegion, then the region itself (0 accepted).
gfx_DisposeRegion:
        move.l  a0,d0
        beq.s   .dr_r
        move.l  a0,-(sp)
        bsr.s   gfx_ClearRegion
        move.l  (sp)+,a1
        move.l  a6,-(sp)
        move.l  ($4).w,a6
        bsr     rp_free
        move.l  (sp)+,a6
.dr_r:
        rts

; OrRectRegion(region a0, rectangle a1) -> d0 = 1, or 0 if the rectangle's first node cannot be allocated (the
; bounds are already enlarged then). Bounds = union, never normalised (§4.5).
gfx_OrRectRegion:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  a0,a3                ; a3 = region
        move.l  a1,a6                ; a6 = rectangle
        bsr     rg_toabs
        move.l  a3,a0
        move.l  a6,a1
        bsr     rg_union
        bsr     rg_alloc
        tst.l   d0
        beq.s   .or_fail
        clr.l   -(sp)                ; pending list
        move.l  sp,a4
        move.l  d0,(a4)
        move.l  d0,a2
        move.l  RG_RECTS(a3),a5
        bsr     rg_cut
        move.l  a3,a0
        bsr     rg_last
        move.l  (sp)+,(a2)           ; pending list at the tail
        move.l  a3,a0
        bsr     rg_rel
        moveq   #1,d0
        bra.s   .or_ret
.or_fail:
        move.l  a3,a0
        bsr     rg_rel
        moveq   #0,d0
.or_ret:
        movem.l (sp)+,d2-d7/a2-a6
        rts

; XorRectRegion(region a0, rectangle a1) -> d0 = 1 always. Empty region: as OrRectRegion. Otherwise the old nodes
; outside the rectangle (copies or bands, in order), then the rectangle minus the old nodes; new nodes only;
; normalised from the union (§4.7).
gfx_XorRectRegion:
        tst.l   RG_RECTS(a0)
        bne.s   .xr_go
        bsr     gfx_OrRectRegion
        moveq   #1,d0
        rts
.xr_go:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  a0,a3
        move.l  a1,a6
        bsr     rg_toabs
        move.l  a3,a0
        move.l  a6,a1
        bsr     rg_union
        movem.w RG_MINX(a3),d2-d5    ; d2-d5 = base bounds (union)
        clr.l   -(sp)                ; 4(sp): pending list (the rectangle)
        clr.l   -(sp)                ; (sp): first part
        lea     4(sp),a2
        move.l  a6,a1
        bsr     rg_new
        move.l  sp,a2
        move.l  RG_RECTS(a3),a5      ; old nodes E outside the rectangle
.xr_e:
        cmpa.w  #0,a5
        beq.s   .xr_cut
        lea     RR_MINX(a5),a0
        move.l  a6,a1
        bsr     rg_overlap
        bne.s   .xr_ov
        move.l  a0,a1
        bsr     rg_new               ; untouched: a new copy
        bra.s   .xr_en
.xr_ov:
        bsr     rg_inside
        bne.s   .xr_en
        bsr     rg_bands
.xr_en:
        move.l  RR_NEXT(a5),a5
        bra.s   .xr_e
.xr_cut:
        move.l  a2,d6                ; d6 = last link of the first part
        lea     4(sp),a4
        move.l  (a4),a2
        move.l  RG_RECTS(a3),a5
        bsr     rg_cut
        move.l  RG_RECTS(a3),a1
        bsr     rg_freelist
        move.l  d6,a0                ; first part, then the pending list
        move.l  4(sp),(a0)
        move.l  (sp),RG_RECTS(a3)
        addq.l  #8,sp
        move.l  a3,a0
        bsr     rg_norm
        moveq   #1,d0
        movem.l (sp)+,d2-d7/a2-a6
        rts

; AndRectRegion(region a0, rectangle a1): empty region -> nothing at all (d0 untouched). Otherwise, per node in
; order: dropped if it misses the rectangle, kept as is if it lies inside, else one new node for the common part;
; a rectangle inside a node replaces the whole list. Normalised from bounds ∩ rectangle (1.3 intersects with its
; own pointer and return address there, §4.6). d0 = Y shift of the normalisation.
gfx_AndRectRegion:
        tst.l   RG_RECTS(a0)
        bne.s   .an_go
        rts
.an_go:
        movem.l d1-d7/a2-a6,-(sp)
        move.l  a0,a3
        move.l  a1,a6
        movem.w RG_MINX(a3),d2-d5    ; base = bounds ∩ rectangle
        cmp.w   (a6),d2
        bge.s   .an_1
        move.w  (a6),d2
.an_1:
        cmp.w   2(a6),d3
        bge.s   .an_2
        move.w  2(a6),d3
.an_2:
        cmp.w   4(a6),d4
        ble.s   .an_3
        move.w  4(a6),d4
.an_3:
        cmp.w   6(a6),d5
        ble.s   .an_4
        move.w  6(a6),d5
.an_4:
        bsr     rg_toabs
        move.l  RG_RECTS(a3),a5      ; a5 = old list
        clr.l   RG_RECTS(a3)
        lea     RG_RECTS(a3),a2
.an_e:
        cmpa.w  #0,a5
        beq     .an_done
        move.l  RR_NEXT(a5),a4       ; a4 = next old node
        lea     RR_MINX(a5),a0
        move.l  a6,a1
        bsr     rg_overlap
        beq.s   .an_drop
        exg     a0,a1
        bsr     rg_inside            ; the rectangle within this node: it alone is the result
        exg     a0,a1
        beq.s   .an_ein
        move.l  a6,a1
        bsr     rg_new
        move.l  a5,a1
        bsr     rg_free
        move.l  a4,a1
        bsr     rg_freelist
        bra.s   .an_done
.an_ein:
        bsr     rg_inside            ; node within the rectangle: kept
        beq.s   .an_cut
        clr.l   RR_NEXT(a5)
        move.l  a5,(a2)
        move.l  a5,a2
        bra.s   .an_n
.an_cut:
        subq.l  #8,sp                ; node ∩ rectangle
        movem.w (a0),d0-d1
        cmp.w   (a6),d0
        bge.s   .an_c1
        move.w  (a6),d0
.an_c1:
        cmp.w   2(a6),d1
        bge.s   .an_c2
        move.w  2(a6),d1
.an_c2:
        movem.w d0-d1,(sp)
        movem.w 4(a0),d0-d1
        cmp.w   4(a6),d0
        ble.s   .an_c3
        move.w  4(a6),d0
.an_c3:
        cmp.w   6(a6),d1
        ble.s   .an_c4
        move.w  6(a6),d1
.an_c4:
        movem.w d0-d1,4(sp)
        move.l  sp,a1
        bsr     rg_new
        addq.l  #8,sp
.an_drop:
        move.l  a5,a1
        bsr     rg_free
.an_n:
        move.l  a4,a5
        bra     .an_e
.an_done:
        clr.l   (a2)
        move.l  a3,a0
        bsr     rg_norm
        movem.l (sp)+,d1-d7/a2-a6
        rts

; rg_absrect(a0 = region, a1 = node, a2 = 8-byte buffer) -> a1 = a2 = the node's absolute rectangle. Uses d0/d1.
rg_absrect:
        move.w  RG_MINX(a0),d0
        move.w  RG_MINY(a0),d1
        move.w  RR_MINX(a1),(a2)
        add.w   d0,(a2)
        move.w  RR_MINY(a1),2(a2)
        add.w   d1,2(a2)
        move.w  RR_MAXX(a1),4(a2)
        add.w   d0,4(a2)
        move.w  RR_MAXY(a1),6(a2)
        add.w   d1,6(a2)
        move.l  a2,a1
        rts

; rg_each(R1 a0, R2 a1, a5 = operation (region a0, rectangle a1)): the operation on R2 with each rectangle of R1 in
; order; d0 = 1. Preserves d2-d7/a2-a6.
rg_each:
        movem.l d2/a2-a4,-(sp)
        subq.l  #8,sp
        move.l  a0,a3
        move.l  a1,a4
        move.l  RG_RECTS(a3),d2
.ea_lp:
        tst.l   d2
        beq.s   .ea_r
        move.l  d2,a1
        move.l  RR_NEXT(a1),d2
        move.l  a3,a0
        move.l  sp,a2
        bsr.s   rg_absrect
        move.l  a4,a0
        jsr     (a5)
        bra.s   .ea_lp
.ea_r:
        addq.l  #8,sp
        movem.l (sp)+,d2/a2-a4
        moveq   #1,d0
        rts

; OrRegionRegion(R1 a0, R2 a1) -> 1: OrRectRegion(R2, each rectangle of R1); failures ignored.
gfx_OrRegionRegion:
        move.l  a5,-(sp)
        lea     gfx_OrRectRegion(pc),a5
        bsr.s   rg_each
        move.l  (sp)+,a5
        rts

; XorRegionRegion(R1 a0, R2 a1) -> 1: XorRectRegion(R2, each rectangle of R1).
gfx_XorRegionRegion:
        move.l  a5,-(sp)
        lea     gfx_XorRectRegion(pc),a5
        bsr.s   rg_each
        move.l  (sp)+,a5
        rts

; ClearRectRegion(region a0, rectangle a1) -> 1, or 0 if the temporary region cannot be allocated (§4.8):
; T = copy of the region cut to the rectangle, then XOR-ed out of the region.
gfx_ClearRectRegion:
        movem.l a2-a4,-(sp)
        move.l  a0,a3
        move.l  a1,a4
        bsr     gfx_NewRegion
        tst.l   d0
        beq.s   .cr_ret
        move.l  d0,a2                ; a2 = T
        move.l  a3,a0
        move.l  a2,a1
        bsr.s   gfx_OrRegionRegion
        move.l  a2,a0
        move.l  a4,a1
        bsr     gfx_AndRectRegion
        move.l  a2,a0
        move.l  a3,a1
        bsr.s   gfx_XorRegionRegion
        move.l  a2,a0
        bsr     gfx_DisposeRegion
        moveq   #1,d0
.cr_ret:
        movem.l (sp)+,a2-a4
        rts

; AndRegionRegion(R1 a0, R2 a1) -> 1, or 0 if a temporary region cannot be allocated (R2 untouched then). For each
; rectangle r of R1 in order: a copy of R2 cut to r is OR-ed into the result; R2 takes the result, normalised.
gfx_AndRegionRegion:
        movem.l d2-d5/a2-a5,-(sp)
        move.l  a0,a3                ; a3 = R1
        move.l  a1,a4                ; a4 = R2
        bsr     gfx_NewRegion
        move.l  d0,a5                ; a5 = result
        tst.l   d0
        beq     .ag_ret
        bsr     gfx_NewRegion
        move.l  d0,a2                ; a2 = temporary
        tst.l   d0
        bne.s   .ag_go
        move.l  a5,a0
        bsr     gfx_DisposeRegion
        moveq   #0,d0
        bra.s   .ag_ret
.ag_go:
        subq.l  #8,sp
        move.l  RG_RECTS(a3),d2
.ag_lp:
        tst.l   d2
        beq.s   .ag_end
        move.l  a4,a0                ; temporary = copy of R2
        move.l  a2,a1
        bsr     gfx_OrRegionRegion
        move.l  d2,a1
        move.l  RR_NEXT(a1),d2
        move.l  a3,a0
        move.l  a2,-(sp)
        lea     4(sp),a2
        bsr     rg_absrect
        move.l  (sp)+,a2
        move.l  a2,a0
        bsr     gfx_AndRectRegion
        move.l  a2,a0
        move.l  a5,a1
        bsr     gfx_OrRegionRegion
        move.l  a2,a0
        bsr     gfx_ClearRegion
        bra.s   .ag_lp
.ag_end:
        addq.l  #8,sp
        move.l  a2,a0
        bsr     gfx_DisposeRegion
        move.l  RG_RECTS(a4),a1      ; R2 takes the result
        bsr     rg_freelist
        move.l  RG_RECTS(a5),RG_RECTS(a4)
        move.l  RG_MINX(a5),RG_MINX(a4)
        move.l  RG_MAXX(a5),RG_MAXX(a4)
        move.l  a4,a0
        bsr     rg_toabs
        movem.w RG_MINX(a4),d2-d5
        bsr     rg_norm
        move.l  a5,a1                ; the result's header only
        move.l  a6,-(sp)
        move.l  ($4).w,a6
        bsr     rp_free
        move.l  (sp)+,a6
        moveq   #1,d0
.ag_ret:
        movem.l (sp)+,d2-d5/a2-a5
        rts
