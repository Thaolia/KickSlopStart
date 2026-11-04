; src/graphics/gels.s — graphics.library GELs (spec docs/analysis/graphics-gels-v34.md): VSprite list sorted by the
; long at VSprite.Y (InitGels, AddVSprite, RemVSprite, SortGList), Bobs (AddBob, RemIBob, DrawGList: Before/After
; ordering, DrawPath/ClearPath chains, background saved/restored, SAVEBOB, double buffering, PlanePick/PlaneOnOff
; through ImageShadow), masks (InitMasks), collisions (DoCollision, SetCollision) and animation (AddAnimOb,
; Animate, GetGBuffers, FreeGBuffers, InitGMasks).
; Drawing by pixel rows (gfx_putrow / gfx_ReadPixel): goes through the layers and their ClipRects. Hardware VSprites
; (VSPRITE flag) are shown through the ViewPort's copper stream (gel_vsprites).
; Deliberate differences from 1.3 (V34 defects not reproduced): the PlaneOnOff shape of a non-OVERLAY Bob is placed
; at its real X, a Mask hole does not shift the saved planes, the collision pixel test is right whichever GEL is
; on the left, a one-member animation sequence is not added twice.
; IMPLEMENTATION track ("clean"): the spec above, public graphics.library AutoDocs, graphics/gels.h. NO ROM reading.

                include "exec.i"
                include "graphics.i"

                xdef    gfx_AddBob
                xdef    gfx_AddVSprite
                xdef    gfx_DoCollision
                xdef    gfx_DrawGList
                xdef    gfx_InitGels
                xdef    gfx_InitMasks
                xdef    gfx_RemIBob
                xdef    gfx_RemVSprite
                xdef    gfx_SetCollision
                xdef    gfx_SortGList
                xdef    gfx_AddAnimOb
                xdef    gfx_Animate
                xdef    gfx_GetGBuffers
                xdef    gfx_InitGMasks
                xdef    gfx_FreeGBuffers
                xref    gfx_putrow
                xref    gfx_ReadPixel

; struct VSprite (graphics/gels.h, V34)
VS_NEXT         EQU 0
VS_PREV         EQU 4
VS_DRAWPATH     EQU 8
VS_CLEARPATH    EQU 12
VS_OLDY         EQU 16
VS_OLDX         EQU 18
VS_FLAGS        EQU 20
VS_Y            EQU 22
VS_X            EQU 24
VS_HEIGHT       EQU 26
VS_WIDTH        EQU 28               ; in words
VS_DEPTH        EQU 30
VS_MEMASK       EQU 32
VS_HITMASK      EQU 34
VS_IMAGE        EQU 36
VS_BORDER       EQU 40
VS_COLLMASK     EQU 44
VS_SPRCOLORS    EQU 48
VS_BOB          EQU 52
VS_PICK         EQU 56
VS_ONOFF        EQU 57
VSB_VSPRITE     EQU 0
VSB_SAVEBACK    EQU 1
VSB_OVERLAY     EQU 2
VSB_BACKSAVED   EQU 8
VSB_BOBUPDATE   EQU 9
VSB_GELGONE     EQU 10
VSB_VSOVERFLOW  EQU 11
; struct Bob
BOB_FLAGS       EQU 0
BOB_SAVE        EQU 2
BOB_SHADOW      EQU 6
BOB_BEFORE      EQU 10
BOB_AFTER       EQU 14
BOB_VS          EQU 18
BOB_DBUF        EQU 26
BB_SAVEBOB      EQU 0
BB_BWAITING     EQU 8
BB_BDRAWN       EQU 9
BB_BOBSAWAY     EQU 10
BB_BOBNIX       EQU 11
BB_SAVEPRESERVE EQU 12
BB_OUTSTEP      EQU 13
; struct GelsInfo
GI_RSRVD        EQU 0                ; BYTE: hardware sprites the VSprites may use
GI_HEAD         EQU 2
GI_TAIL         EQU 6
GI_NEXTLINE     EQU 10
GI_LASTCOLOR    EQU 14
GI_COLL         EQU 18
GI_LEFT         EQU 22
GI_RIGHT        EQU 24
GI_TOP          EQU 26
GI_BOTTOM       EQU 28
rp_GelsInfo     EQU 20
; struct AnimComp
AC_FLAGS        EQU 0
AC_TIMER        EQU 2
AC_TIMESET      EQU 4
AC_NEXTCOMP     EQU 6
AC_PREVCOMP     EQU 10
AC_NEXTSEQ      EQU 14
AC_ROUTINE      EQU 22
AC_YTRANS       EQU 26
AC_XTRANS       EQU 28
AC_BOB          EQU 34
RINGTRIGGER     EQU 0                ; bit of AnimComp.Flags
; struct AnimOb
AO_NEXT         EQU 0
AO_PREV         EQU 4
AO_CLOCK        EQU 8
AO_OLDY         EQU 12
AO_Y            EQU 16
AO_X            EQU 18
AO_YVEL         EQU 20
AO_XVEL         EQU 22
AO_YACC         EQU 24
AO_XACC         EQU 26
AO_RINGY        EQU 28
AO_RINGX        EQU 30
AO_ROUTINE      EQU 32
AO_HEADCOMP     EQU 36
ANFRACSIZE      EQU 6
; struct DBufPacket
DB_BUFY         EQU 0                ; BufY, BufX
DB_BUFPATH      EQU 4
DB_BUFFER       EQU 8
DB_SIZE         EQU 12
; DoCollision flags for routine 0 (boundaries)
TOPHIT          EQU 1
BOTTOMHIT       EQU 2
LEFTHIT         EQU 4
RIGHTHIT        EQU 8

GEL_CHUNK       EQU 64               ; pixels processed per gfx_putrow call
GEL_PLAN        EQU 36               ; gel_draw's per-plane sources: 8 longs + "background needed" byte (+ pad)
GEL_MAXPATH     EQU 1024             ; ClearPath steps walked at most: a double-buffered chain mixes two frames

; ---------------------------------------------------------------------------------------------------------------
; InitGels(head a0, tail a1, gelsInfo a2): empty list between two sentinels (head at (-32767, -32767), its ClearPath
; = tail; tail at (32767, 32767)); boundary routine (collHandler[0]) cleared.
gfx_InitGels:
        move.l  a1,VS_NEXT(a0)
        clr.l   VS_PREV(a0)
        move.l  a1,VS_CLEARPATH(a0)
        move.l  a0,VS_PREV(a1)
        clr.l   VS_NEXT(a1)
        move.l  #$80018001,d0
        move.l  d0,VS_Y(a0)
        move.l  d0,VS_OLDY(a0)
        move.l  #$7FFF7FFF,d0
        move.l  d0,VS_Y(a1)
        move.l  d0,VS_OLDY(a1)
        move.l  a0,GI_HEAD(a2)
        move.l  a1,GI_TAIL(a2)
        move.l  GI_COLL(a2),d0
        beq.s   .ig_r
        exg     d0,a0
        clr.l   (a0)
        exg     d0,a0
.ig_r:
        rts

; gel_gt(a0, a1 = VSprites) -> d0 = 1 if the long at Y of a0 (Y high word, X low word) is greater than a1's,
; signed compare, else 0. Preserves the rest.
gel_gt:
        move.l  VS_Y(a0),d0
        cmp.l   VS_Y(a1),d0
        bgt.s   .gt_yes
        moveq   #0,d0
        rts
.gt_yes:
        moveq   #1,d0
        rts

; gel_insert(vs a0, before a1): links vs just before a1. Preserves everything except a1.
gel_insert:
        move.l  a1,VS_NEXT(a0)
        move.l  VS_PREV(a1),VS_PREV(a0)
        move.l  a0,VS_PREV(a1)
        move.l  VS_PREV(a0),a1
        move.l  a0,VS_NEXT(a1)
        rts

; AddVSprite(vs a0, rp a1): system flags cleared, old position = position, inserted before the first GEL whose key
; is not below its own.
gfx_AddVSprite:
        movem.l a1-a2,-(sp)
        and.w   #$00FF,VS_FLAGS(a0)
        move.l  VS_Y(a0),VS_OLDY(a0)
        move.l  rp_GelsInfo(a1),a2
        move.l  GI_HEAD(a2),a1
        move.l  VS_NEXT(a1),a1
.av_lp:
        tst.l   VS_NEXT(a1)          ; tail: insert before it
        beq.s   .av_ins
        bsr.s   gel_gt               ; vs > element: further
        tst.w   d0
        beq.s   .av_ins
        move.l  VS_NEXT(a1),a1
        bra.s   .av_lp
.av_ins:
        bsr.s   gel_insert
        movem.l (sp)+,a1-a2
        rts

; RemVSprite(vs a0): unlinks the VSprite; its own links are left as they were.
gfx_RemVSprite:
        move.l  a1,-(sp)
        move.l  VS_PREV(a0),a1
        move.l  VS_NEXT(a0),VS_NEXT(a1)
        move.l  VS_NEXT(a0),a1
        move.l  VS_PREV(a0),VS_PREV(a1)
        move.l  (sp)+,a1
        rts

; AddBob(bob a0, rp a1): the Bob's system flags cleared, its VSprite (which points to the Bob) added to the list.
gfx_AddBob:
        and.w   #$00FF,BOB_FLAGS(a0)
        move.l  a0,d0
        move.l  BOB_VS(a0),a0
        move.l  d0,VS_BOB(a0)
        bra.s   gfx_AddVSprite

; RemIBob(bob a0, rp a1, vp a2): background restored at once (first every overlapping Bob drawn after it, which
; disappears until the next DrawGList), VSprite unlinked, BOBNIX.
gfx_RemIBob:
        movem.l d2-d7/a2-a4,-(sp)
        move.l  a0,a3
        move.l  BOB_VS(a3),a0
        bsr     gel_restore
        move.l  BOB_VS(a3),a0
        bsr.s   gfx_RemVSprite
        bset    #BB_BOBNIX-8,BOB_FLAGS(a3)
        movem.l (sp)+,d2-d7/a2-a4
        rts

; SortGList(rp a1): stable insertion sort of the list by its key.
gfx_SortGList:
        movem.l a2-a4,-(sp)
        move.l  rp_GelsInfo(a1),a4
        move.l  GI_HEAD(a4),a4       ; a4 = head
        move.l  VS_NEXT(a4),a2       ; a2 = current element
.sg_lp:
        tst.l   VS_NEXT(a2)
        beq.s   .sg_ret              ; tail
        move.l  VS_NEXT(a2),a3       ; a3 = next (saved before moving)
        move.l  VS_PREV(a2),a0
        cmpa.l  a4,a0
        beq.s   .sg_nx
        move.l  a2,a1
        bsr     gel_gt               ; previous > current?
        tst.w   d0
        beq.s   .sg_nx
        move.l  a2,a0                ; unlinks the current one
        bsr.s   gfx_RemVSprite
        move.l  VS_PREV(a2),a1       ; moves back while the predecessor is greater
.sg_back:
        move.l  VS_PREV(a1),a0
        cmpa.l  a4,a0
        beq.s   .sg_put
        move.l  a0,-(sp)
        move.l  a2,a1
        bsr     gel_gt
        move.l  (sp)+,a1
        tst.w   d0
        beq.s   .sg_put0
        bra.s   .sg_back
.sg_put0:
        move.l  VS_NEXT(a1),a1       ; a1 = first element not greater -> insert before its successor
.sg_put:
        move.l  a2,a0
        bsr     gel_insert
.sg_nx:
        move.l  a3,a2
        bra.s   .sg_lp
.sg_ret:
        movem.l (sp)+,a2-a4
        rts

; ---------------------------------------------------------------------------------------------------------------
; DrawGList(rp a1, vp a0), under Forbid (spec §5.1): GfxBase->VBlank := 1; pass 1 in list order: a BOBSAWAY Bob is
; restored and removed (with a DBuffer: kept one more call, OUTSTEP), another Bob goes through gel_drawbob; the
; drawn Bobs are chained through DrawPath from the head to the tail. Pass 2: a Bob left waiting is restored,
; BOBUPDATE becomes BACKSAVED, BWAITING/BDRAWN cleared, old position and ClearPath taken (or swapped with the
; DBufPacket). Then the VSprites get hardware sprites (gel_vsprites).
gfx_DrawGList:
        movem.l d2-d7/a2-a5,-(sp)
        move.l  a0,d6                ; d6 = vp
        move.l  rp_GelsInfo(a1),d0
        beq     .dg_ret
        move.l  d0,a5
        move.l  a6,-(sp)
        move.l  ($4).w,a6
        jsr     LVO_FORBID(a6)
        move.l  (sp)+,a6
        move.b  #1,gb_VBlank(a6)
        move.l  GI_HEAD(a5),a4       ; a4 = last Bob drawn (DrawPath chain from the head)
        move.l  VS_NEXT(a4),a2
.dg_lp:
        move.l  VS_NEXT(a2),d7       ; d7 = next (the current Bob may leave the list)
        beq.s   .dg_p2
        btst    #VSB_VSPRITE,VS_FLAGS+1(a2)
        bne.s   .dg_nx
        move.l  VS_BOB(a2),d0
        beq.s   .dg_nx
        move.l  d0,a3
        btst    #BB_BOBSAWAY-8,BOB_FLAGS(a3)
        bne.s   .dg_away
        bsr     gel_drawbob
        bra.s   .dg_nx
.dg_away:
        move.l  a2,a0
        bsr     gel_restore
        tst.l   BOB_DBUF(a3)
        beq.s   .dg_gone
        bset    #BB_OUTSTEP-8,BOB_FLAGS(a3)
        beq.s   .dg_nx               ; first call: erased in this BitMap, the other one at the next call
.dg_gone:
        move.l  a2,a0
        bsr     gfx_RemVSprite
        bset    #BB_BOBNIX-8,BOB_FLAGS(a3)
.dg_nx:
        move.l  d7,a2
        bra.s   .dg_lp
.dg_p2:
        move.l  GI_TAIL(a5),VS_DRAWPATH(a4)
        move.l  GI_HEAD(a5),a2
.dg_p2l:
        move.l  VS_NEXT(a2),a2
        tst.l   VS_NEXT(a2)
        beq.s   .dg_vs
        move.l  a2,a0
        bsr     gel_restore          ; a Bob left waiting
        bclr    #VSB_BOBUPDATE-8,VS_FLAGS(a2)
        beq.s   .dg_p2b
        bset    #VSB_BACKSAVED-8,VS_FLAGS(a2)
.dg_p2b:
        move.l  VS_BOB(a2),d0
        beq.s   .dg_p2l
        move.l  d0,a3
        and.w   #~((1<<BB_BWAITING)|(1<<BB_BDRAWN)),BOB_FLAGS(a3)
        move.l  BOB_DBUF(a3),d0
        bne.s   .dg_swap
        move.l  VS_Y(a2),VS_OLDY(a2) ; OldY, OldX
        move.l  VS_DRAWPATH(a2),VS_CLEARPATH(a2)
        bra.s   .dg_p2l
.dg_swap:
        move.l  d0,a0
        move.l  DB_BUFY(a0),d0
        move.l  VS_Y(a2),DB_BUFY(a0)
        move.l  d0,VS_OLDY(a2)
        move.l  DB_BUFPATH(a0),d0
        move.l  VS_DRAWPATH(a2),DB_BUFPATH(a0)
        move.l  d0,VS_CLEARPATH(a2)
        move.l  DB_BUFFER(a0),d0
        move.l  BOB_SAVE(a3),DB_BUFFER(a0)
        move.l  d0,BOB_SAVE(a3)
        bclr    #VSB_BACKSAVED-8,VS_FLAGS(a2) ; BACKSAVED <-> SAVEPRESERVE
        sne     d0
        bclr    #BB_SAVEPRESERVE-8,BOB_FLAGS(a3)
        beq.s   .dg_sp
        bset    #VSB_BACKSAVED-8,VS_FLAGS(a2)
.dg_sp:
        tst.b   d0
        beq.s   .dg_p2l
        bset    #BB_SAVEPRESERVE-8,BOB_FLAGS(a3)
        bra.s   .dg_p2l
.dg_vs:
        move.l  d6,a0
        bsr     gel_vsprites
        move.l  a6,-(sp)
        move.l  ($4).w,a6
        jsr     LVO_PERMIT(a6)
        move.l  (sp)+,a6
.dg_ret:
        movem.l (sp)+,d2-d7/a2-a5
        rts

; gel_drawbob(a2 = vs of a Bob, a1 = rp, a4 = last Bob drawn (updated), a5 = GelsInfo): spec §5.2. Waits
; (BWAITING) while its After Bob is not drawn; GELGONE when outside the BitMap; SAVEBACK: own and overlapping old
; backgrounds restored, new background saved (BOBUPDATE); drawn and chained; BDRAWN; then its waiting Before Bob.
; Preserves d2-d7/a2-a3/a5/a6.
gel_drawbob:
        movem.l d2-d7/a2-a3,-(sp)
        move.l  VS_BOB(a2),a3
        move.l  BOB_AFTER(a3),d0
        beq.s   .db_go
        move.l  d0,a0
        btst    #BB_BDRAWN-8,BOB_FLAGS(a0)
        bne.s   .db_go
        bset    #BB_BWAITING-8,BOB_FLAGS(a3)
        bra     .db_ret
.db_go:
        bsr     gel_clip
        move.w  d0,d7                ; d7 = visible
        bclr    #VSB_GELGONE-8,VS_FLAGS(a2)
        tst.w   d7
        bne.s   .db_vis
        bset    #VSB_GELGONE-8,VS_FLAGS(a2)
.db_vis:
        btst    #VSB_SAVEBACK,VS_FLAGS+1(a2)
        beq.s   .db_draw
        move.l  a2,a0
        bsr     gel_restore
        move.l  GI_HEAD(a5),d6       ; every saved GEL whose old rectangle meets the new one
.db_ov:
        move.l  d6,a0
        move.l  VS_NEXT(a0),d6
        move.l  d6,a0
        tst.l   VS_NEXT(a0)
        beq.s   .db_sv
        btst    #VSB_BACKSAVED-8,VS_FLAGS(a0)
        beq.s   .db_ov
        move.l  a2,a3
        move.w  VS_OLDX(a0),d0
        move.w  VS_OLDY(a0),d1
        move.w  VS_X(a2),d2
        move.w  VS_Y(a2),d3
        bsr     gel_isect
        beq.s   .db_ov
        move.l  d6,a0
        bsr     gel_restore
        bra.s   .db_ov
.db_sv:
        move.l  VS_BOB(a2),a3
        tst.w   d7
        beq.s   .db_flag
        bsr     gel_save
.db_draw:
        tst.w   d7
        beq.s   .db_flag
        move.l  a2,VS_DRAWPATH(a4)
        move.l  a2,a4
        bsr     gel_draw
.db_flag:
        bclr    #BB_BWAITING-8,BOB_FLAGS(a3)
        bset    #BB_BDRAWN-8,BOB_FLAGS(a3)
        move.l  BOB_BEFORE(a3),d0
        beq.s   .db_ret
        move.l  d0,a0
        btst    #BB_BWAITING-8,BOB_FLAGS(a0)
        beq.s   .db_ret
        move.l  BOB_VS(a0),a2
        bsr     gel_drawbob
.db_ret:
        movem.l (sp)+,d2-d7/a2-a3
        rts

; gel_clip(a2 = vs, a1 = rp) -> d0.w = 1 if its rectangle (X .. X+16*Width-1, Y .. Y+Height-1) meets the
; RastPort's BitMap, else 0. Clobbers d1/a0.
gel_clip:
        move.l  rp_BitMap(a1),a0
        move.w  VS_X(a2),d0
        ext.l   d0
        moveq   #0,d1
        move.w  bm_BytesPerRow(a0),d1
        lsl.l   #3,d1
        cmp.l   d1,d0
        bge.s   .cl_out
        moveq   #0,d1
        move.w  VS_WIDTH(a2),d1
        lsl.l   #4,d1
        add.l   d0,d1
        ble.s   .cl_out
        move.w  VS_Y(a2),d0
        ext.l   d0
        moveq   #0,d1
        move.w  bm_Rows(a0),d1
        cmp.l   d1,d0
        bge.s   .cl_out
        moveq   #0,d1
        move.w  VS_HEIGHT(a2),d1
        add.l   d0,d1
        ble.s   .cl_out
        moveq   #1,d0
        rts
.cl_out:
        moveq   #0,d0
        rts

; gel_isect(a0 = GEL 1 at (d0.w x, d1.w y), a3 = GEL 2 at (d2.w x, d3.w y)) -> d0 = 1 (Z clear) if their
; rectangles overlap, else 0. Clobbers d1-d3.
gel_isect:
        move.l  d4,-(sp)
        ext.l   d0
        ext.l   d1
        ext.l   d2
        ext.l   d3
        moveq   #0,d4
        move.w  VS_WIDTH(a3),d4
        lsl.l   #4,d4
        add.l   d2,d4
        cmp.l   d4,d0
        bge.s   .is_no
        moveq   #0,d4
        move.w  VS_WIDTH(a0),d4
        lsl.l   #4,d4
        add.l   d0,d4
        cmp.l   d4,d2
        bge.s   .is_no
        moveq   #0,d4
        move.w  VS_HEIGHT(a3),d4
        add.l   d3,d4
        cmp.l   d4,d1
        bge.s   .is_no
        moveq   #0,d4
        move.w  VS_HEIGHT(a0),d4
        add.l   d1,d4
        cmp.l   d4,d3
        bge.s   .is_no
        moveq   #1,d0
        bra.s   .is_ret
.is_no:
        moveq   #0,d0
.is_ret:
        move.l  (sp)+,d4
        rts

; gel_restore(a0 = vs, a1 = rp): spec §5.3. If BACKSAVED: first every BACKSAVED GEL of its ClearPath chain whose
; old rectangle meets its own (recursively), then BACKSAVED cleared and, unless the Bob has SAVEBOB, its SaveBuffer
; copied back at (OldY, OldX). Preserves everything except d0/d1/a0.
gel_restore:
        btst    #VSB_BACKSAVED-8,VS_FLAGS(a0)
        beq.s   .gr_r
        movem.l d2-d4/a2-a3,-(sp)
        move.l  a0,a2
        move.l  VS_CLEARPATH(a2),a3
        move.w  #GEL_MAXPATH-1,d4
.gr_lp:
        cmpa.w  #0,a3
        beq.s   .gr_me
        tst.l   VS_NEXT(a3)          ; tail
        beq.s   .gr_me
        btst    #VSB_BACKSAVED-8,VS_FLAGS(a3)
        beq.s   .gr_nx
        move.l  a2,a0
        move.w  VS_OLDX(a2),d0
        move.w  VS_OLDY(a2),d1
        move.w  VS_OLDX(a3),d2
        move.w  VS_OLDY(a3),d3
        bsr     gel_isect
        beq.s   .gr_nx
        move.l  a3,a0
        bsr.s   gel_restore
.gr_nx:
        move.l  VS_CLEARPATH(a3),a3
        dbra    d4,.gr_lp
.gr_me:
        bclr    #VSB_BACKSAVED-8,VS_FLAGS(a2)
        move.l  VS_BOB(a2),d0
        beq.s   .gr_out
        move.l  d0,a3
        btst    #BB_SAVEBOB,BOB_FLAGS+1(a3)
        bne.s   .gr_out
        bsr     gel_unsave
.gr_out:
        movem.l (sp)+,d2-d4/a2-a3
.gr_r:
        rts

; gel_geom(a2 = vs, a1 = rp) -> d4.w = height, d5.w = width in pixels, d6.w = depth of the RastPort's BitMap,
; d3.l = bytes of one image plane (height * width in words * 2). Clobbers d0/a0.
gel_geom:
        move.w  VS_HEIGHT(a2),d4
        move.w  VS_WIDTH(a2),d5
        move.w  d4,d3
        mulu    d5,d3
        add.l   d3,d3
        lsl.w   #4,d5
        move.l  rp_BitMap(a1),a0
        moveq   #0,d6
        move.b  bm_Depth(a0),d6
        rts

; gel_save(a2 = vs, a3 = bob, a1 = rp): background of the (Y, X) rectangle read pixel by pixel into bob->SaveBuffer
; (planes of the RastPort's BitMap, each height x width in words); BOBUPDATE set. Without a buffer: nothing.
gel_save:
        movem.l d2-d7/a2-a4,-(sp)
        move.l  BOB_SAVE(a3),d0
        beq     .gs_ret
        move.l  d0,a4                ; a4 = buffer
        bsr.s   gel_geom
        move.l  d3,d0                ; buffer cleared (depth x plane)
        mulu    d6,d0
        lsr.l   #1,d0
        move.l  a4,a0
        bra.s   .gs_cz
.gs_clr:
        clr.w   (a0)+
.gs_cz:
        subq.l  #1,d0
        bpl.s   .gs_clr
        moveq   #0,d7                ; d7 = row
.gs_row:
        cmp.w   d4,d7
        bge.s   .gs_done
        moveq   #0,d2                ; d2 = column
.gs_px:
        cmp.w   d5,d2
        bge.s   .gs_nr
        move.w  VS_X(a2),d0
        add.w   d2,d0
        move.w  VS_Y(a2),d1
        add.w   d7,d1
        jsr     gfx_ReadPixel
        tst.l   d0
        bmi.s   .gs_nxp              ; outside any visible area: 0
        bsr     gel_putbits
.gs_nxp:
        addq.w  #1,d2
        bra.s   .gs_px
.gs_nr:
        addq.w  #1,d7
        bra.s   .gs_row
.gs_done:
        bset    #VSB_BOBUPDATE-8,VS_FLAGS(a2)
.gs_ret:
        movem.l (sp)+,d2-d7/a2-a4
        rts
; gel_putbits(d0 = colour, d2 = column, d7 = row, a4 = planar buffer, d3 = bytes of one plane, d6 = planes,
; VS_WIDTH(a2)): sets the colour bits in each plane of the buffer. Clobbers d0/d1/a0.
gel_putbits:
        movem.l d4-d5,-(sp)
        move.w  d7,d1
        mulu    VS_WIDTH(a2),d1
        add.l   d1,d1                ; start byte of the row within a plane
        move.w  d2,d4
        lsr.w   #3,d4
        add.l   d4,d1                ; byte of the pixel
        move.w  d2,d4
        not.w   d4
        and.w   #7,d4                ; bit of the pixel
        lea     0(a4,d1.l),a0
        move.w  d6,d5
        bra.s   .pb_nx
.pb_pl:
        lsr.w   #1,d0
        bcc.s   .pb_z
        bset    d4,(a0)
.pb_z:
        add.l   d3,a0
.pb_nx:
        dbra    d5,.pb_pl
        movem.l (sp)+,d4-d5
        rts

; gel_unsave(a2 = vs, a3 = bob, a1 = rp): saved background written back at (OldY, OldX).
gel_unsave:
        movem.l d2-d7/a2-a4,-(sp)
        move.l  BOB_SAVE(a3),d0
        beq.s   .gu_ret
        move.l  d0,a4
        bsr     gel_geom
        lea     -GEL_CHUNK(sp),sp
        moveq   #0,d7                ; row
.gu_row:
        cmp.w   d4,d7
        bge.s   .gu_done
        moveq   #0,d2                ; start of the chunk
.gu_ch:
        cmp.w   d5,d2
        bge.s   .gu_nr
        moveq   #0,d0                ; d0 = pixels in this chunk
        move.w  d5,d0
        sub.w   d2,d0
        cmp.w   #GEL_CHUNK,d0
        ble.s   .gu_n
        moveq   #GEL_CHUNK,d0
.gu_n:
        move.w  d0,-(sp)
        lea     2(sp),a0
        bsr     gel_getbits          ; buffer colours -> chunk
        move.w  (sp)+,d0
        move.w  d2,-(sp)
        move.w  d0,-(sp)
        lea     4(sp),a0
        move.w  VS_OLDX(a2),d0
        add.w   d2,d0
        move.w  VS_OLDY(a2),d1
        add.w   d7,d1
        move.w  (sp),d2
        jsr     gfx_putrow
        move.w  (sp)+,d0
        move.w  (sp)+,d2
        add.w   d0,d2
        bra.s   .gu_ch
.gu_nr:
        addq.w  #1,d7
        bra.s   .gu_row
.gu_done:
        lea     GEL_CHUNK(sp),sp
.gu_ret:
        movem.l (sp)+,d2-d7/a2-a4
        rts
; gel_getbits(a0 = chunk, d0.w = count, d2 = first column, d7 = row, a4 = buffer, d3, d6, a2): colour
; of each pixel of the chunk rebuilt from the buffer planes. Preserves d2-d7.
gel_getbits:
        movem.l d2-d7/a1,-(sp)
        move.l  a0,a1
        move.w  d0,d5                ; d5 = counter
        bra.s   .gb_nx
.gb_px:
        move.w  d7,d1
        mulu    VS_WIDTH(a2),d1
        add.l   d1,d1
        move.w  d2,d4
        lsr.w   #3,d4
        add.l   d4,d1
        move.w  d2,d4
        not.w   d4
        and.w   #7,d4
        lea     0(a4,d1.l),a0
        move.l  d3,d1
        mulu    d6,d1                ; (d3 fits in 16 bits for a reasonable Bob)
        add.l   d1,a0                ; after the last plane, go back up
        moveq   #0,d0
        move.w  d6,d1
        bra.s   .gb_pn
.gb_pl:
        sub.l   d3,a0
        add.b   d0,d0
        btst    d4,(a0)
        beq.s   .gb_pn
        addq.b  #1,d0
.gb_pn:
        dbra    d1,.gb_pl
        move.b  d0,(a1)+
        addq.w  #1,d2
.gb_nx:
        dbra    d5,.gb_px
        movem.l (sp)+,d2-d7/a1
        rts

; gel_draw(a2 = vs, a3 = bob, a1 = rp): image drawn at (Y, X) (spec §5.4). Per BitMap plane: rp->Mask bit clear
; -> untouched (gfx_putrow); in PlanePick -> the next image plane (counted over the planes actually written), over
; the whole rectangle, or only inside ImageShadow with OVERLAY; not in PlanePick -> its PlaneOnOff bit inside
; ImageShadow, the background elsewhere. OVERLAY: transparent outside ImageShadow. Without an ImageShadow the OR
; of the image planes stands for it.
gel_draw:
        movem.l d2-d7/a2-a4,-(sp)
        bsr     gel_geom
        cmp.w   #8,d6
        bls.s   .gd_d8
        moveq   #8,d6
.gd_d8:
        lea     -(GEL_CHUNK+GEL_PLAN)(sp),sp
        lea     GEL_CHUNK(sp),a0     ; per-plane source: image plane offset, -1 unpicked, -2 zero
        clr.b   32(a0)
        moveq   #0,d0                ; next image plane offset
        moveq   #0,d1                ; BitMap plane
        moveq   #0,d2                ; image planes used
.gd_pp:
        cmp.w   d6,d1
        bge.s   .gd_pd
        btst    d1,VS_PICK(a2)
        beq.s   .gd_unp
        btst    d1,rp_Mask(a1)
        beq.s   .gd_zero             ; plane not written: no image plane consumed
        cmp.w   VS_DEPTH(a2),d2
        bge.s   .gd_zero
        move.l  d0,(a0)+
        add.l   d3,d0
        addq.w  #1,d2
        bra.s   .gd_pn
.gd_unp:
        move.l  #-1,(a0)+
        st      GEL_CHUNK+32(sp)
        bra.s   .gd_pn
.gd_zero:
        move.l  #-2,(a0)+
.gd_pn:
        addq.w  #1,d1
        bra.s   .gd_pp
.gd_pd:
        moveq   #0,d7                ; row
.gd_row:
        cmp.w   d4,d7
        bge.s   .gd_done
        moveq   #0,d2
.gd_ch:
        cmp.w   d5,d2
        bge.s   .gd_nr
        moveq   #0,d0
        move.w  d5,d0
        sub.w   d2,d0
        cmp.w   #GEL_CHUNK,d0
        ble.s   .gd_n
        moveq   #GEL_CHUNK,d0
.gd_n:
        move.l  sp,a0
        bsr.s   gel_imgbits
        move.w  d2,-(sp)
        move.w  d0,-(sp)
        lea     4(sp),a0
        move.w  VS_X(a2),d0
        add.w   d2,d0
        move.w  VS_Y(a2),d1
        add.w   d7,d1
        move.w  (sp),d2
        jsr     gfx_putrow
        move.w  (sp)+,d0
        move.w  (sp)+,d2
        add.w   d0,d2
        bra.s   .gd_ch
.gd_nr:
        addq.w  #1,d7
        bra.s   .gd_row
.gd_done:
        lea     GEL_CHUNK+GEL_PLAN(sp),sp
        movem.l (sp)+,d2-d7/a2-a4
        rts
; gel_imgbits(a0 = chunk (the plane sources follow it), d0.w = count, d2 = first column, d7 = row, a1 = rp,
; a2 = vs, a3 = bob, d3 = bytes of one image plane, d6 = BitMap planes): colour (or 255) of each pixel. Bit 16 of
; d5 = the pixel is inside ImageShadow. Preserves everything.
gel_imgbits:
        movem.l d0-d7/a0-a5,-(sp)
        pea     GEL_CHUNK(a0)        ; (sp) = plane sources
        move.l  a0,a5
        move.l  VS_IMAGE(a2),a4
        move.w  d0,d5
        bra     .ib_nx
.ib_px:
        move.w  d7,d1                ; d1 = byte of the pixel within a plane, d4 = its bit
        mulu    VS_WIDTH(a2),d1
        add.l   d1,d1
        move.w  d2,d4
        lsr.w   #3,d4
        add.l   d4,d1
        move.w  d2,d4
        not.w   d4
        and.w   #7,d4
        bclr    #16,d5
        move.l  BOB_SHADOW(a3),d0
        beq.s   .ib_or
        move.l  d0,a0
        btst    d4,0(a0,d1.l)
        bne.s   .ib_ins
        bra.s   .ib_sh
.ib_or:
        lea     0(a4,d1.l),a0
        move.w  VS_DEPTH(a2),d0
        bra.s   .ib_on
.ib_ol:
        btst    d4,(a0)
        bne.s   .ib_ins
        add.l   d3,a0
.ib_on:
        dbra    d0,.ib_ol
        bra.s   .ib_sh
.ib_ins:
        bset    #16,d5
.ib_sh:
        movem.l d2/d7,-(sp)
        btst    #16,d5
        bne.s   .ib_col
        btst    #VSB_OVERLAY,VS_FLAGS+1(a2)
        bne.s   .ib_tr
        move.l  8(sp),a0
        tst.b   32(a0)
        beq.s   .ib_col              ; every plane comes from the image: no background needed
        move.l  d1,-(sp)
        move.l  a1,-(sp)
        move.w  VS_X(a2),d0
        add.w   d2,d0
        move.w  VS_Y(a2),d1
        add.w   d7,d1
        jsr     gfx_ReadPixel
        move.l  d0,d7                ; d7 = background colour
        move.l  (sp)+,a1
        move.l  (sp)+,d1
        tst.l   d7
        bmi.s   .ib_tr               ; not visible there
.ib_col:
        move.l  a1,-(sp)
        move.l  12(sp),a0            ; plane sources
        moveq   #0,d0                ; colour
        moveq   #0,d2                ; BitMap plane
.ib_pl:
        cmp.w   d6,d2
        bge.s   .ib_put
        move.l  (a0)+,a1
        cmpa.w  #-1,a1
        beq.s   .ib_unp
        cmpa.w  #-2,a1
        beq.s   .ib_np
        add.l   a4,a1
        add.l   d1,a1
        btst    d4,(a1)
        beq.s   .ib_np
        bset    d2,d0
        bra.s   .ib_np
.ib_unp:
        btst    #16,d5
        beq.s   .ib_bg
        btst    d2,VS_ONOFF(a2)
        beq.s   .ib_np
        bset    d2,d0
        bra.s   .ib_np
.ib_bg:
        btst    d2,d7
        beq.s   .ib_np
        bset    d2,d0
.ib_np:
        addq.w  #1,d2
        bra.s   .ib_pl
.ib_put:
        move.l  (sp)+,a1
        move.b  d0,(a5)+
        bra.s   .ib_nxp
.ib_tr:
        st      (a5)+
.ib_nxp:
        movem.l (sp)+,d2/d7
        addq.w  #1,d2
.ib_nx:
        dbra    d5,.ib_px
        addq.l  #4,sp
        movem.l (sp)+,d0-d7/a0-a5
        rts

; ---------------------------------------------------------------------------------------------------------------
; InitMasks(vs a0): CollMask = OR of the Depth image planes row by row (VSPRITE: the two words of each line);
; BorderLine[c] = OR over Height rows of word column c of the first image plane (for a VSprite: the first
; Height x Width words of ImageData, as on 1.3). A missing array is skipped.
gfx_InitMasks:
        movem.l d2-d7/a2-a4,-(sp)
        move.l  a0,a2
        move.w  VS_WIDTH(a2),d5      ; d5 = words per row
        move.w  VS_HEIGHT(a2),d4
        move.l  VS_IMAGE(a2),a3
        move.l  VS_COLLMASK(a2),d0
        beq.s   .im_bl
        move.l  d0,a4
        moveq   #0,d7                ; row
.im_row:
        cmp.w   d4,d7
        bge.s   .im_bl
        moveq   #0,d6                ; word
.im_w:
        cmp.w   d5,d6
        bge.s   .im_nr
        moveq   #0,d2                ; d2 = OR
        btst    #VSB_VSPRITE,VS_FLAGS+1(a2)
        beq.s   .im_bob
        move.w  d7,d0                ; VSprite: row = 2 x width words (plane 0 then plane 1)
        mulu    d5,d0
        add.w   d0,d0
        add.w   d6,d0
        add.w   d0,d0
        or.w    0(a3,d0.w),d2
        move.w  d5,d1
        add.w   d1,d1
        add.w   d1,d0
        or.w    0(a3,d0.w),d2
        bra.s   .im_put
.im_bob:
        move.w  d4,d3                ; d3 = bytes of one plane
        mulu    d5,d3
        add.l   d3,d3
        move.w  d7,d0
        mulu    d5,d0
        add.w   d6,d0
        add.l   d0,d0
        lea     0(a3,d0.l),a0
        move.w  VS_DEPTH(a2),d1
        bra.s   .im_pn
.im_pl:
        or.w    (a0),d2
        add.l   d3,a0
.im_pn:
        dbra    d1,.im_pl
.im_put:
        move.w  d7,d0
        mulu    d5,d0
        add.w   d6,d0
        add.l   d0,d0
        move.w  d2,0(a4,d0.l)
        addq.w  #1,d6
        bra.s   .im_w
.im_nr:
        addq.w  #1,d7
        bra.s   .im_row
.im_bl:
        move.l  VS_BORDER(a2),d0
        beq.s   .im_ret
        move.l  d0,a0
        moveq   #0,d6                ; word column
.im_bw:
        cmp.w   d5,d6
        bge.s   .im_ret
        moveq   #0,d2
        move.w  d6,d0
        add.w   d0,d0
        lea     0(a3,d0.w),a4
        move.w  d4,d7
        bra.s   .im_bn
.im_br:
        or.w    (a4),d2
        add.w   d5,a4
        add.w   d5,a4
.im_bn:
        dbra    d7,.im_br
        move.w  d2,(a0)+
        addq.w  #1,d6
        bra.s   .im_bw
.im_ret:
        movem.l (sp)+,d2-d7/a2-a4
        rts

; SetCollision(number d0, routine a0, gelsInfo a1): collHandler[number] := routine (number used as a long).
gfx_SetCollision:
        move.l  GI_COLL(a1),d1
        beq.s   .sc_r
        move.l  d1,a1
        lsl.l   #2,d0
        move.l  a0,0(a1,d0.l)
.sc_r:
        rts

; gel_call(a0 = routine, d0 = 1st argument, d1 = 2nd): call using the C convention (arguments pushed right to
; left, removed on return). Preserves d2-d7/a2-a6.
gel_call:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  d1,-(sp)
        move.l  d0,-(sp)
        jsr     (a0)
        addq.l  #8,sp
        movem.l (sp)+,d2-d7/a2-a6
        rts

; DoCollision(rp a1), spec §7: for each GEL G in list order: with a boundary routine and HitMask != 0, the
; boundary flags (gel_bounds) -> collHandler[0](G, flags); then each following GEL H while H.Y < G.Y + G.Height:
; m = G.MeMask & H.HitMask without bit 0; if m and a common CollMask pixel -> collHandler[lowest bit of m](G, H).
gfx_DoCollision:
        movem.l d2-d7/a2-a5,-(sp)
        move.l  rp_GelsInfo(a1),d0
        beq     .dc_ret
        move.l  d0,a5
        move.l  GI_COLL(a5),d0
        beq     .dc_ret
        move.l  d0,a4                ; a4 = collHandler
        move.l  GI_HEAD(a5),a2
.dc_lp:
        move.l  VS_NEXT(a2),a2
        tst.l   VS_NEXT(a2)
        beq     .dc_ret
        tst.l   (a4)
        beq.s   .dc_pairs
        tst.w   VS_HITMASK(a2)
        beq.s   .dc_pairs
        bsr     gel_bounds
        tst.l   d0
        beq.s   .dc_pairs
        move.l  d0,d1
        move.l  a2,d0
        move.l  (a4),a0
        bsr.s   gel_call
.dc_pairs:
        move.l  a2,a3
.dc_p2:
        move.l  VS_NEXT(a3),a3
        tst.l   VS_NEXT(a3)
        beq.s   .dc_lp
        move.w  VS_Y(a2),d0
        add.w   VS_HEIGHT(a2),d0
        cmp.w   VS_Y(a3),d0
        ble.s   .dc_lp
        move.w  VS_MEMASK(a2),d6
        and.w   VS_HITMASK(a3),d6
        and.w   #$FFFE,d6
        beq.s   .dc_p2
        bsr     gel_overlap
        beq.s   .dc_p2
        moveq   #1,d0                ; lowest bit
.dc_bit:
        btst    d0,d6
        bne.s   .dc_got
        addq.w  #1,d0
        bra.s   .dc_bit
.dc_got:
        lsl.w   #2,d0
        move.l  0(a4,d0.w),d0
        beq.s   .dc_p2
        move.l  d0,a0
        move.l  a2,d0
        move.l  a3,d1
        bsr     gel_call
        bra.s   .dc_p2
.dc_ret:
        movem.l (sp)+,d2-d7/a2-a5
        rts

; gel_bounds(a2 = vs, a5 = GelsInfo) -> d0.l = boundary flags (spec §7.2): TOPHIT when Y < topmost and a CollMask
; pixel lies in rows Y .. topmost+1 (two rows past the bound, as 1.3); BOTTOMHIT for a CollMask pixel below
; bottommost; LEFTHIT / RIGHTHIT for a BorderLine pixel left of leftmost / right of rightmost.
gel_bounds:
        movem.l d1-d2,-(sp)
        moveq   #0,d2
        move.w  GI_TOP(a5),d1
        sub.w   VS_Y(a2),d1
        ble.s   .bd_b
        addq.w  #1,d1                ; last row = topmost + 1 - Y
        moveq   #0,d0
        bsr.s   gel_rowsany
        beq.s   .bd_b
        or.w    #TOPHIT,d2
.bd_b:
        move.w  GI_BOTTOM(a5),d0
        sub.w   VS_Y(a2),d0
        addq.w  #1,d0                ; first row below bottommost
        move.w  VS_HEIGHT(a2),d1
        subq.w  #1,d1
        bsr.s   gel_rowsany
        beq.s   .bd_l
        or.w    #BOTTOMHIT,d2
.bd_l:
        moveq   #0,d0
        move.w  GI_LEFT(a5),d1
        sub.w   VS_X(a2),d1
        subq.w  #1,d1                ; last column left of leftmost
        bsr     gel_colsany
        beq.s   .bd_r
        or.w    #LEFTHIT,d2
.bd_r:
        move.w  GI_RIGHT(a5),d0
        sub.w   VS_X(a2),d0
        addq.w  #1,d0                ; first column right of rightmost
        move.w  VS_WIDTH(a2),d1
        lsl.w   #4,d1
        subq.w  #1,d1
        bsr     gel_colsany
        beq.s   .bd_ret
        or.w    #RIGHTHIT,d2
.bd_ret:
        move.l  d2,d0
        movem.l (sp)+,d1-d2
        rts

; gel_rowsany(a2 = vs, d0.w = first row, d1.w = last row, both clamped to the GEL) -> Z clear if CollMask has a
; pixel in those rows (no CollMask: any row counts). Clobbers d0.
gel_rowsany:
        movem.l d1-d3/a0,-(sp)
        tst.w   d0
        bpl.s   .ra_1
        moveq   #0,d0
.ra_1:
        move.w  VS_HEIGHT(a2),d2
        subq.w  #1,d2
        cmp.w   d2,d1
        ble.s   .ra_2
        move.w  d2,d1
.ra_2:
        cmp.w   d1,d0
        bgt.s   .ra_no
        move.l  VS_COLLMASK(a2),d2
        beq.s   .ra_yes
        move.l  d2,a0
        move.w  VS_WIDTH(a2),d2      ; words per row
        beq.s   .ra_no
        move.w  d0,d3
        mulu    d2,d3
        add.l   d3,d3
        add.l   d3,a0
        sub.w   d0,d1
        addq.w  #1,d1
        mulu    d2,d1                ; words to test
        subq.w  #1,d1
.ra_lp:
        tst.w   (a0)+
        bne.s   .ra_yes
        dbra    d1,.ra_lp
.ra_no:
        moveq   #0,d0
        bra.s   .ra_ret
.ra_yes:
        moveq   #1,d0
.ra_ret:
        movem.l (sp)+,d1-d3/a0
        rts

; gel_colsany(a2 = vs, d0.w = first column, d1.w = last column, both clamped to the GEL) -> Z clear if BorderLine
; has a pixel in those columns (no BorderLine: any column counts). Clobbers d0.
gel_colsany:
        movem.l d1-d3/a0,-(sp)
        tst.w   d0
        bpl.s   .ca_1
        moveq   #0,d0
.ca_1:
        move.w  VS_WIDTH(a2),d2
        lsl.w   #4,d2
        subq.w  #1,d2
        cmp.w   d2,d1
        ble.s   .ca_2
        move.w  d2,d1
.ca_2:
        cmp.w   d1,d0
        bgt.s   .ca_no
        move.l  VS_BORDER(a2),d2
        beq.s   .ca_yes
        move.l  d2,a0
.ca_lp:
        move.w  d0,d2
        lsr.w   #4,d2
        add.w   d2,d2
        move.w  0(a0,d2.w),d3
        move.w  d0,d2
        not.w   d2
        and.w   #15,d2
        btst    d2,d3
        bne.s   .ca_yes
        addq.w  #1,d0
        cmp.w   d1,d0
        ble.s   .ca_lp
.ca_no:
        moveq   #0,d0
        bra.s   .ca_ret
.ca_yes:
        moveq   #1,d0
.ca_ret:
        movem.l (sp)+,d1-d3/a0
        rts

; gel_overlap(a2, a3 = VSprites): Z = 0 if their rectangles overlap and (CollMasks present) a pixel
; is common to both masks. Preserves d6/a2-a5.
gel_overlap:
        movem.l d2-d7,-(sp)
        move.w  VS_X(a2),d2          ; common x [d2 .. d3], common y [d4 .. d5]
        move.w  VS_X(a3),d0
        cmp.w   d0,d2
        bge.s   .ov_1
        move.w  d0,d2
.ov_1:
        move.w  VS_WIDTH(a2),d3
        lsl.w   #4,d3
        add.w   VS_X(a2),d3
        move.w  VS_WIDTH(a3),d0
        lsl.w   #4,d0
        add.w   VS_X(a3),d0
        cmp.w   d0,d3
        ble.s   .ov_2
        move.w  d0,d3
.ov_2:
        subq.w  #1,d3
        move.w  VS_Y(a2),d4
        move.w  VS_Y(a3),d0
        cmp.w   d0,d4
        bge.s   .ov_3
        move.w  d0,d4
.ov_3:
        move.w  VS_Y(a2),d5
        add.w   VS_HEIGHT(a2),d5
        move.w  VS_Y(a3),d0
        add.w   VS_HEIGHT(a3),d0
        cmp.w   d0,d5
        ble.s   .ov_4
        move.w  d0,d5
.ov_4:
        subq.w  #1,d5
        cmp.w   d3,d2
        bgt.s   .ov_no
        cmp.w   d5,d4
        bgt.s   .ov_no
        tst.l   VS_COLLMASK(a2)
        beq.s   .ov_yes
        tst.l   VS_COLLMASK(a3)
        beq.s   .ov_yes
.ov_y:
        move.w  d2,d7                ; pixel by pixel
.ov_x:
        move.l  a2,a0
        bsr.s   .ov_bit
        beq.s   .ov_nx
        move.l  a3,a0
        bsr.s   .ov_bit
        bne.s   .ov_yes
.ov_nx:
        addq.w  #1,d7
        cmp.w   d3,d7
        ble.s   .ov_x
        addq.w  #1,d4
        cmp.w   d5,d4
        ble.s   .ov_y
.ov_no:
        moveq   #0,d0
        bra.s   .ov_ret
.ov_yes:
        moveq   #1,d0
.ov_ret:
        movem.l (sp)+,d2-d7
        rts
; .ov_bit(a0 = vs, d7 = x, d4 = y absolute): Z = 0 if the CollMask bit is set. Clobbers d0/d1/a0.
.ov_bit:
        move.w  d4,d0
        sub.w   VS_Y(a0),d0
        mulu    VS_WIDTH(a0),d0
        add.l   d0,d0
        moveq   #0,d1
        move.w  d7,d1
        sub.w   VS_X(a0),d1
        move.l  d1,-(sp)
        lsr.w   #3,d1
        add.l   d1,d0
        move.l  VS_COLLMASK(a0),a0
        add.l   d0,a0
        move.l  (sp)+,d1
        not.w   d1
        and.w   #7,d1
        btst    d1,(a0)
        rts

; ---------------------------------------------------------------------------------------------------------------
; AddAnimOb(anOb a0, anKey a1, rp a2) -> d0 = 0: the object is put at the head of the *anKey list; for each
; component of the NextComp chain: Timer := TimeSet and its Bob added (positions left as they are).
gfx_AddAnimOb:
        movem.l a2-a4,-(sp)
        move.l  a0,a3
        move.l  (a1),d0
        move.l  d0,AO_NEXT(a3)
        clr.l   AO_PREV(a3)
        tst.l   d0
        beq.s   .aa_first
        move.l  d0,a0
        move.l  a3,AO_PREV(a0)
.aa_first:
        move.l  a3,(a1)
        move.l  AO_HEADCOMP(a3),a4
.aa_lp:
        cmpa.w  #0,a4
        beq.s   .aa_ret
        move.w  AC_TIMESET(a4),AC_TIMER(a4)
        move.l  AC_BOB(a4),a0
        move.l  a2,a1
        bsr     gfx_AddBob
        move.l  AC_NEXTCOMP(a4),a4
        bra.s   .aa_lp
.aa_ret:
        moveq   #0,d0
        movem.l (sp)+,a2-a4
        rts

; anim_place(a3 = anOb, a4 = comp): the component's VSprite at ((An + Trans + 32) >> 6) in both axes (6 fraction
; bits, rounded). Clobbers d0/d1/a0.
anim_place:
        move.l  AC_BOB(a4),a0
        move.l  BOB_VS(a0),a0
        move.w  AO_Y(a3),d0
        ext.l   d0
        move.w  AC_YTRANS(a4),d1
        ext.l   d1
        add.l   d1,d0
        moveq   #1<<(ANFRACSIZE-1),d1
        add.l   d1,d0
        asr.l   #ANFRACSIZE,d0
        move.w  d0,VS_Y(a0)
        move.w  AO_X(a3),d0
        ext.l   d0
        move.w  AC_XTRANS(a4),d1
        ext.l   d1
        add.l   d1,d0
        moveq   #1<<(ANFRACSIZE-1),d1
        add.l   d1,d0
        asr.l   #ANFRACSIZE,d0
        move.w  d0,VS_X(a0)
        rts

; Animate(anKey a0, rp a1), spec §8.2: per object: Clock + 1, old = position, position += velocity, velocity +=
; acceleration, AnimORoutine(ob); per component: a running timer that reaches 0 switches to NextSeq (links, flags,
; position and paths carried over to the new Bob, old Bob BOBSAWAY and parked at -32767, new Bob added, timer
; re-armed, RINGTRIGGER translation), then AnimCRoutine(comp) and the VSprite position. Returns d0 = 0.
gfx_Animate:
        movem.l d2-d7/a2-a5,-(sp)
        move.l  a1,a5                ; a5 = rp
        move.l  (a0),a3
.an_ob:
        cmpa.w  #0,a3
        beq     .an_ret
        addq.l  #1,AO_CLOCK(a3)
        move.l  AO_Y(a3),AO_OLDY(a3)
        move.w  AO_YVEL(a3),d0
        add.w   d0,AO_Y(a3)
        move.w  AO_XVEL(a3),d0
        add.w   d0,AO_X(a3)
        move.w  AO_YACC(a3),d0
        add.w   d0,AO_YVEL(a3)
        move.w  AO_XACC(a3),d0
        add.w   d0,AO_XVEL(a3)
        move.l  AO_ROUTINE(a3),d0
        beq.s   .an_comps
        move.l  d0,a0
        move.l  a3,d0
        moveq   #0,d1
        bsr     gel_call
.an_comps:
        move.l  AO_HEADCOMP(a3),a4
.an_c:
        cmpa.w  #0,a4
        beq     .an_nob
        tst.w   AC_TIMER(a4)
        beq     .an_rt
        subq.w  #1,AC_TIMER(a4)
        bne     .an_rt
        move.l  AC_NEXTSEQ(a4),d2    ; d2 = N
        beq     .an_rt
        cmp.l   a4,d2
        bne.s   .an_sw
        move.w  AC_TIMESET(a4),AC_TIMER(a4) ; one-member sequence: its Bob is already in the list
        bra     .an_rt
.an_sw:
        move.l  AC_BOB(a4),a0        ; a0 = C's Bob
        move.l  d2,a1
        move.l  AC_BOB(a1),a1        ; a1 = N's Bob
        cmpa.l  a0,a1
        beq.s   .an_link             ; shared Bob: only the component changes
        move.l  BOB_BEFORE(a0),d0
        move.l  d0,BOB_BEFORE(a1)
        beq.s   .an_nb
        move.l  d0,a2
        move.l  a1,BOB_AFTER(a2)
.an_nb:
        move.l  BOB_AFTER(a0),d0
        move.l  d0,BOB_AFTER(a1)
        beq.s   .an_na
        move.l  d0,a2
        move.l  a1,BOB_BEFORE(a2)
.an_na:
        move.w  BOB_FLAGS(a0),BOB_FLAGS(a1)
        move.l  BOB_VS(a0),a2        ; a2 = C's VSprite
        move.l  BOB_VS(a1),d3        ; d3 = N's VSprite
        move.l  d3,a1
        move.l  VS_Y(a2),VS_Y(a1)
        bset    #BB_BOBSAWAY-8,BOB_FLAGS(a0)
        move.l  d2,a0
        move.l  AC_BOB(a0),a0
        move.l  a5,a1
        bsr     gfx_AddBob
        move.l  #$80018001,VS_Y(a2)
        move.l  d3,a1
        move.l  VS_DRAWPATH(a2),VS_DRAWPATH(a1)
        move.l  VS_CLEARPATH(a2),VS_CLEARPATH(a1)
.an_link:
        move.l  d2,a2                ; N replaces C in the component chain
        move.l  AC_PREVCOMP(a4),d0
        move.l  d0,AC_PREVCOMP(a2)
        beq.s   .an_head
        move.l  d0,a0
        move.l  a2,AC_NEXTCOMP(a0)
        bra.s   .an_lnk
.an_head:
        move.l  a2,AO_HEADCOMP(a3)
.an_lnk:
        move.l  AC_NEXTCOMP(a4),d0
        move.l  d0,AC_NEXTCOMP(a2)
        beq.s   .an_lnk2
        move.l  d0,a0
        move.l  a2,AC_PREVCOMP(a0)
.an_lnk2:
        move.w  AC_TIMESET(a2),AC_TIMER(a2)
        btst    #RINGTRIGGER,AC_FLAGS+1(a2)
        beq.s   .an_cur
        move.w  AO_RINGY(a3),d0
        add.w   d0,AO_Y(a3)
        move.w  AO_RINGX(a3),d0
        add.w   d0,AO_X(a3)
.an_cur:
        move.l  a2,a4
.an_rt:
        move.l  AC_ROUTINE(a4),d0
        beq.s   .an_pos
        move.l  d0,a0
        move.l  a4,d0
        moveq   #0,d1
        bsr     gel_call
.an_pos:
        bsr     anim_place
        move.l  AC_NEXTCOMP(a4),a4
        bra     .an_c
.an_nob:
        move.l  AO_NEXT(a3),a3
        bra     .an_ob
.an_ret:
        moveq   #0,d0
        movem.l (sp)+,d2-d7/a2-a5
        rts

; anim_forall(a0 = anOb, a3 = action): calls the action (a4 = component) for each component of each sequence
; (NextSeq ring walked until it loops back or reaches 0). The action returns Z = 0 to stop (failure). d0 = 1 if
; everything succeeded. Preserves d2-d7/a2-a6.
anim_forall:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  AO_HEADCOMP(a0),a2
.fa_c:
        cmpa.w  #0,a2
        beq.s   .fa_ok
        move.l  a2,a4
.fa_s:
        move.l  a2,-(sp)             ; the action may use a2
        jsr     (a3)
        movem.l (sp)+,a2             ; movem leaves the action's condition codes
        bne.s   .fa_ko
        move.l  AC_NEXTSEQ(a4),a4
        cmpa.w  #0,a4
        beq.s   .fa_nc
        cmpa.l  a2,a4
        bne.s   .fa_s
.fa_nc:
        move.l  AC_NEXTCOMP(a2),a2
        bra.s   .fa_c
.fa_ok:
        moveq   #1,d0
        bra.s   .fa_ret
.fa_ko:
        moveq   #0,d0
.fa_ret:
        movem.l (sp)+,d2-d7/a2-a6
        rts

; InitGMasks(anOb a0) -> d0 = 0: InitMasks of each member of each sequence.
gfx_InitGMasks:
        move.l  a3,-(sp)
        lea     gm_one(pc),a3
        bsr.s   anim_forall
        move.l  (sp)+,a3
        moveq   #0,d0
        rts
gm_one:
        move.l  AC_BOB(a4),a0
        move.l  BOB_VS(a0),a0
        bsr     gfx_InitMasks
        moveq   #0,d0                ; Z = 1: continue
        rts

; GetGBuffers(anOb a0, rp a1, db d0) -> d0 = 1 if every member received its buffers, 0 at the first failure
; (nothing given back, as 1.3): SaveBuffer (BitMap depth planes), with db a DBufPacket and its BufBuffer, BorderLine
; and CollMask, all chip but the packet; ImageShadow = CollMask.
gfx_GetGBuffers:
        movem.l d2-d3/a3/a5,-(sp)
        move.w  d0,d3                ; d3 = double buffering
        move.l  rp_BitMap(a1),a5
        moveq   #0,d2
        move.b  bm_Depth(a5),d2      ; d2 = depth
        lea     gb_one(pc),a3
        bsr.s   anim_forall
        movem.l (sp)+,d2-d3/a3/a5
        rts
; gb_one(a4 = component, d2 = depth, d3 = double buffering): Z = 0 if an allocation fails.
gb_one:
        move.l  AC_BOB(a4),a2
        move.l  BOB_VS(a2),a5
        bsr     gb_sizes             ; d4 = plane, d5 = width in bytes
        move.l  d4,d0
        mulu    d2,d0
        move.l  #MEMF_CHIP|MEMF_PUBLIC|MEMF_CLEAR,d1
        bsr.s   gb_alloc
        move.l  d0,BOB_SAVE(a2)
        beq.s   .go_ko
        tst.w   d3
        beq.s   .go_bl
        moveq   #DB_SIZE,d0
        move.l  #MEMF_PUBLIC|MEMF_CLEAR,d1
        bsr.s   gb_alloc
        move.l  d0,BOB_DBUF(a2)
        beq.s   .go_ko
        move.l  d0,-(sp)
        move.l  d4,d0
        mulu    d2,d0
        move.l  #MEMF_CHIP|MEMF_PUBLIC|MEMF_CLEAR,d1
        bsr.s   gb_alloc
        move.l  (sp)+,a0
        move.l  d0,DB_BUFFER(a0)
        beq.s   .go_ko
.go_bl:
        move.l  d5,d0
        move.l  #MEMF_CHIP|MEMF_PUBLIC|MEMF_CLEAR,d1
        bsr.s   gb_alloc
        move.l  d0,VS_BORDER(a5)
        beq.s   .go_ko
        move.l  d4,d0
        move.l  #MEMF_CHIP|MEMF_PUBLIC|MEMF_CLEAR,d1
        bsr.s   gb_alloc
        move.l  d0,VS_COLLMASK(a5)
        beq.s   .go_ko
        move.l  d0,BOB_SHADOW(a2)
        moveq   #0,d0
        rts
.go_ko:
        moveq   #1,d0
        rts
; gb_sizes(a5 = vs) -> d4 = bytes of one plane (height x width in words x 2), d5 = bytes of one row.
gb_sizes:
        move.w  VS_WIDTH(a5),d5
        add.w   d5,d5
        move.w  VS_HEIGHT(a5),d4
        mulu    d5,d4
        ext.l   d5
        rts
; gb_alloc(d0 = size, d1 = requirements) -> d0 = block | 0 (Z accordingly).
gb_alloc:
        move.l  a6,-(sp)
        move.l  ($4).w,a6
        jsr     LVO_ALLOCMEM(a6)
        move.l  (sp)+,a6
        tst.l   d0
        rts

; FreeGBuffers(anOb a0, rp a1, db d0): returns the buffers obtained by GetGBuffers (pointers reset to 0; an
; ImageShadow equal to the CollMask too).
gfx_FreeGBuffers:
        movem.l d2-d3/a3/a5,-(sp)
        move.w  d0,d3
        move.l  rp_BitMap(a1),a5
        moveq   #0,d2
        move.b  bm_Depth(a5),d2
        lea     fb_one(pc),a3
        bsr     anim_forall
        movem.l (sp)+,d2-d3/a3/a5
        rts
fb_one:
        move.l  AC_BOB(a4),a2
        move.l  BOB_VS(a2),a5
        bsr.s   gb_sizes
        move.l  VS_COLLMASK(a5),d0
        cmp.l   BOB_SHADOW(a2),d0
        bne.s   .fo_cm
        clr.l   BOB_SHADOW(a2)
.fo_cm:
        lea     VS_COLLMASK(a5),a0
        move.l  d4,d0
        bsr.s   fb_free
        lea     VS_BORDER(a5),a0
        move.l  d5,d0
        bsr.s   fb_free
        lea     BOB_SAVE(a2),a0
        move.l  d4,d0
        mulu    d2,d0
        bsr.s   fb_free
        tst.w   d3
        beq.s   .fo_r
        move.l  BOB_DBUF(a2),d0
        beq.s   .fo_r
        move.l  d0,a0
        pea     BOB_DBUF(a2)
        lea     DB_BUFFER(a0),a0
        move.l  d4,d0
        mulu    d2,d0
        bsr.s   fb_free
        move.l  (sp)+,a0
        moveq   #DB_SIZE,d0
        bsr.s   fb_free
.fo_r:
        moveq   #0,d0
        rts
; fb_free(a0 = address of the pointer, d0 = size): FreeMem if non-zero, pointer reset to 0.
fb_free:
        move.l  (a0),d1
        beq.s   .ff_r
        clr.l   (a0)
        move.l  a6,-(sp)
        move.l  d1,a1
        move.l  ($4).w,a6
        jsr     LVO_FREEMEM(a6)
        move.l  (sp)+,a6
.ff_r:
        rts

; ---------------------------------------------------------------------------------------------------------------
; gel_vsprites(vp a0, rp a1, GelsInfo a5, a6 = GfxBase): spec §5.8. Rebuilds vp->SprIns (our copper stream, layout
; in graphics.i; 1.3 builds SprIns/ClrIns CopLists instead). nextLine[] := -1 and lastColor[] := NULL (local tables
; when the GelsInfo has none). Usable sprites = sprRsrvd minus GfxBase->SpriteReserved; sprite n is free for a
; VSprite whose top (clipped to the RastPort's BitMap) is > nextLine[n]. Per VSprite, in list order: a pair with
; exactly one free sprite whose partner shows no colours, or the same SprColors pointer, or the VSprite has none;
; otherwise the even sprite of the first fully free pair; otherwise VSOVERFLOW (left set). On success
; nextLine[n] := top + clipped height + 2, lastColor[n] := SprColors. Outside the BitMap: GELGONE, nothing.
; One segment on the line before the top loads SPRxPOS/SPRxCTL (VSTART, VSTOP, HSTART as MoveSprite computes
; them), SPRxPT (ImageData past the clipped rows) and the pair's colours when they differ from the last loaded; one
; on the VSTOP line zeroes POS/CTL, so that the words after the image never re-arm the sprite. No vp or no memory:
; nothing. Preserves d2-d7/a2-a6.
VL_FREE  EQU -16                     ; 8 words: line from which a sprite's segments are done (stream hazard)
VL_CLEAN EQU -32                     ; 8 words: line of its pending clean-up, $7FFF = none
VL_COL   EQU -48                     ; 4 longs: SprColors last loaded for each pair
VL_AVAIL EQU -50                     ; word: usable hardware sprites (low byte)
VL_ROWS  EQU -52                     ; word: rows of the RastPort's BitMap
VL_CL    EQU -54                     ; word: clean-up line of the VSprite being placed
VL_PNL   EQU -58                     ; long: nextLine table in use
VL_PLC   EQU -62                     ; long: lastColor table in use
VL_NL    EQU -78                     ; 8 words: nextLine when the GelsInfo has none
VL_LC    EQU -110                    ; 8 longs: lastColor when the GelsInfo has none
VL_LOC   EQU 110
VL_HPOS  EQU $40                     ; copper position of the segments' WAITs
gel_vsprites:
        movem.l d2-d7/a2-a4,-(sp)
        cmpa.w  #0,a0
        beq     .vs_ret
        move.l  a0,a3                ; a3 = vp
        move.l  rp_BitMap(a1),a0
        move.w  bm_Rows(a0),d1
        link    a4,#-VL_LOC
        move.w  d1,VL_ROWS(a4)
        moveq   #0,d0                ; size: 60 bytes per VSprite at most
        move.l  GI_HEAD(a5),a2
        move.l  VS_NEXT(a2),a2
.vs_cnt:
        tst.l   VS_NEXT(a2)
        beq.s   .vs_counted
        btst    #VSB_VSPRITE,VS_FLAGS+1(a2)
        beq.s   .vs_cn
        add.l   #60,d0
.vs_cn:
        move.l  VS_NEXT(a2),a2
        bra.s   .vs_cnt
.vs_counted:
        add.l   #GFX_SPRI_HDR+4,d0
        move.l  d0,d7                ; d7 = size needed
        move.l  a6,-(sp)
        move.l  ($4).w,a6
        move.l  vp_SprIns(a3),d0
        beq.s   .vs_alloc
        move.l  d0,a1
        cmp.l   (a1),d7
        bls.s   .vs_have
        clr.l   vp_SprIns(a3)
        move.l  (a1),d0
        jsr     LVO_FREEMEM(a6)
.vs_alloc:
        move.l  d7,d0
        move.l  #MEMF_PUBLIC|MEMF_CLEAR,d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .vs_nomem
        move.l  d0,a1
        move.l  d7,(a1)
        move.l  a1,vp_SprIns(a3)
        move.l  a1,d0
.vs_have:
        move.l  (sp)+,a6
        move.l  d0,a1
        addq.l  #GFX_SPRI_HDR,a1     ; a1 = write pointer
        lea     VL_NL(a4),a0
        move.l  GI_NEXTLINE(a5),d0
        beq.s   .vs_nl0
        move.l  d0,a0
.vs_nl0:
        move.l  a0,VL_PNL(a4)
        lea     VL_LC(a4),a0
        move.l  GI_LASTCOLOR(a5),d0
        beq.s   .vs_lc0
        move.l  d0,a0
.vs_lc0:
        move.l  a0,VL_PLC(a4)
        moveq   #8-1,d0
        move.l  VL_PNL(a4),a0
        lea     VL_FREE(a4),a2
.vs_init:
        move.w  #-1,(a0)+            ; nextLine
        move.w  #$8000,(a2)+         ; VL_FREE: free from the start
        dbra    d0,.vs_init
        moveq   #8-1,d0
        move.l  VL_PLC(a4),a0
        lea     VL_CLEAN(a4),a2
.vs_ini2:
        clr.l   (a0)+                ; lastColor
        move.w  #$7FFF,(a2)+
        dbra    d0,.vs_ini2
        clr.l   VL_COL(a4)
        clr.l   VL_COL+4(a4)
        clr.l   VL_COL+8(a4)
        clr.l   VL_COL+12(a4)
        move.b  gb_SpriteReserved(a6),d0
        not.b   d0
        and.b   GI_RSRVD(a5),d0
        move.w  d0,VL_AVAIL(a4)
        move.l  GI_HEAD(a5),a2
        move.l  VS_NEXT(a2),a2
.vs_lp:
        tst.l   VS_NEXT(a2)
        beq     .vs_end
        btst    #VSB_VSPRITE,VS_FLAGS+1(a2)
        beq     .vs_nx
        move.w  VS_Y(a2),d4          ; d4 = top, d6 = clipped height, d7 = rows clipped at the top
        move.w  VS_HEIGHT(a2),d6
        add.w   d4,d6
        cmp.w   VL_ROWS(a4),d6
        ble.s   .vs_cb
        move.w  VL_ROWS(a4),d6
.vs_cb:
        moveq   #0,d7
        tst.w   d4
        bpl.s   .vs_ct
        move.w  d4,d7
        neg.w   d7
        moveq   #0,d4
.vs_ct:
        cmp.w   d4,d6
        bgt.s   .vs_vis
        bset    #VSB_GELGONE-8,VS_FLAGS(a2)
        bra     .vs_nx
.vs_vis:
        bclr    #VSB_GELGONE-8,VS_FLAGS(a2)
        sub.w   d4,d6
        move.w  d4,d5
        subq.w  #1,d5                ; d5 = line of the set-up segment (vp lines)
        btst    #2,vp_Modes+1(a3)
        beq.s   .vs_p1s
        subq.w  #1,d5                ; LACE ViewPort: interlaced lines
.vs_p1s:
        moveq   #0,d3                ; pass 1: a pair with exactly one free sprite
.vs_p1:
        move.w  d3,d0
        bsr     .vs_isfree
        move.w  d1,d2
        addq.w  #1,d0
        bsr     .vs_isfree
        cmp.w   d1,d2
        beq.s   .vs_p1n
        move.w  d3,d0
        tst.w   d2
        bne.s   .vs_p1o
        addq.w  #1,d0                ; d0 = the free one
.vs_p1o:
        tst.l   VS_SPRCOLORS(a2)
        beq.s   .vs_take
        move.w  d0,d1
        eor.w   #1,d1
        lsl.w   #2,d1
        move.l  VL_PLC(a4),a0
        move.l  0(a0,d1.w),d1        ; the partner's colours
        beq.s   .vs_take
        cmp.l   VS_SPRCOLORS(a2),d1
        beq.s   .vs_take
.vs_p1n:
        addq.w  #2,d3
        cmp.w   #8,d3
        blo.s   .vs_p1
        moveq   #0,d3                ; pass 2: the even sprite of a fully free pair
.vs_p2:
        move.w  d3,d0
        bsr     .vs_isfree
        tst.w   d1
        beq.s   .vs_p2n
        addq.w  #1,d0
        bsr     .vs_isfree
        tst.w   d1
        beq.s   .vs_p2n
        move.w  d3,d0
        bra.s   .vs_take
.vs_p2n:
        addq.w  #2,d3
        cmp.w   #8,d3
        blo.s   .vs_p2
        bset    #VSB_VSOVERFLOW-8,VS_FLAGS(a2)
        bra     .vs_nx
.vs_take:
        move.w  d0,d3                ; d3 = hardware sprite
        add.w   d0,d0
        move.l  VL_PNL(a4),a0
        move.w  d4,d1
        add.w   d6,d1
        addq.w  #2,d1
        move.w  d1,0(a0,d0.w)        ; nextLine
        move.l  VS_SPRCOLORS(a2),d1
        beq.s   .vs_nlc
        add.w   d0,d0
        move.l  VL_PLC(a4),a0
        move.l  d1,0(a0,d0.w)        ; lastColor
.vs_nlc:
        move.w  d7,d0                ; SPRxPT = ImageData + clipped rows x Depth words
        mulu    VS_DEPTH(a2),d0
        add.l   d0,d0
        add.l   VS_IMAGE(a2),d0
        move.l  d0,-(sp)
        move.w  d5,d0
        bsr     .vs_flush            ; clean-ups up to this line first
        move.w  d6,d0                ; clean-up line: VSTOP in vp lines
        btst    #2,vp_Modes+1(a3)
        beq.s   .vs_cl
        add.w   d0,d0
.vs_cl:
        add.w   d4,d0
        move.w  d0,VL_CL(a4)
        move.w  VS_X(a2),d0          ; d0 = HSTART, d1 = VSTART (as MoveSprite)
        tst.w   vp_Modes(a3)
        bpl.s   .vs_lx
        asr.w   #1,d0
.vs_lx:
        move.w  d4,d1
        add.w   vp_DyOffset(a3),d1
        btst    #2,vp_Modes+1(a3)
        beq.s   .vs_ly
        asr.w   #1,d1
.vs_ly:
        move.l  gb_ActiView(a6),d7
        beq.s   .vs_pos
        move.l  d7,a0
        add.w   v_DxOffset(a0),d0
        add.w   v_DyOffset(a0),d1
.vs_pos:
        move.w  d1,d7
        add.w   d6,d7                ; d7 = VSTOP
        move.w  d1,d2                ; POS = VSTART[7:0] << 8 | HSTART[8:1]
        lsl.w   #8,d2
        ror.w   #1,d0                ; (HSTART0 -> bit 15)
        move.b  d0,d2
        lsr.w   #8,d1                ; CTL = VSTOP[7:0] << 8 | VSTART8 << 2 | VSTOP8 << 1 | HSTART0
        and.w   #1,d1
        lsl.w   #2,d1
        tst.w   d0
        bpl.s   .vs_h0
        bset    #0,d1
.vs_h0:
        btst    #8,d7
        beq.s   .vs_e8
        bset    #1,d1
.vs_e8:
        lsl.w   #8,d7
        or.b    d1,d7
        move.w  d5,d0
        bsr     .vs_wait
        move.w  d3,d0
        lsl.w   #3,d0
        add.w   #$140,d0             ; SPRxPOS
        move.w  d0,(a1)+
        move.w  d2,(a1)+
        addq.w  #2,d0                ; SPRxCTL
        move.w  d0,(a1)+
        move.w  d7,(a1)+
        move.w  d3,d0
        lsl.w   #2,d0
        add.w   #SPR0PTH-CUSTOM,d0
        move.l  (sp)+,d1             ; SPRxPT
        swap    d1
        move.w  d0,(a1)+
        move.w  d1,(a1)+
        addq.w  #2,d0
        swap    d1
        move.w  d0,(a1)+
        move.w  d1,(a1)+
        move.l  VS_SPRCOLORS(a2),d1
        beq.s   .vs_nocol
        move.w  d3,d0
        lsr.w   #1,d0
        lsl.w   #2,d0                ; pair * 4
        cmp.l   VL_COL(a4,d0.w),d1
        beq.s   .vs_nocol
        move.l  d1,VL_COL(a4,d0.w)
        move.l  d1,a0
        add.w   d0,d0
        add.w   #COLOR00-CUSTOM+17*2,d0 ; COLOR17 + 4 * pair
        moveq   #3-1,d1
.vs_col:
        move.w  d0,(a1)+
        move.w  (a0)+,(a1)+
        addq.w  #2,d0
        dbra    d1,.vs_col
.vs_nocol:
        move.w  d3,d0
        add.w   d0,d0
        move.w  VL_CL(a4),d1
        move.w  d1,VL_CLEAN(a4,d0.w)
        move.w  d1,VL_FREE(a4,d0.w)
.vs_nx:
        move.l  VS_NEXT(a2),a2
        bra     .vs_lp
.vs_end:
        move.w  #$7FFF,d0
        bsr.s   .vs_flush
        move.w  #GFX_PSEUDO,(a1)+
        move.w  #GFX_PEND,(a1)+
        move.l  vp_SprIns(a3),a0
        move.l  a1,d0
        sub.l   a0,d0
        sub.l   #GFX_SPRI_HDR+4,d0
        move.l  d0,4(a0)             ; bytes in a hardware list (12 per WAIT, 4 per MOVE, as in the stream)
        bra.s   .vs_out
.vs_nomem:
        move.l  (sp)+,a6
.vs_out:
        unlk    a4
.vs_ret:
        movem.l (sp)+,d2-d7/a2-a4
        rts
; .vs_isfree(d0.w = sprite, d4 = top, d5 = set-up line) -> d1.w = 1 if usable, nextLine < top and its previous
; segments are over by the set-up line, else 0. Preserves d0.
.vs_isfree:
        moveq   #0,d1
        btst    d0,VL_AVAIL+1(a4)
        beq.s   .if_r
        move.l  a0,-(sp)
        move.l  VL_PNL(a4),a0
        add.w   d0,d0
        cmp.w   0(a0,d0.w),d4
        ble.s   .if_no
        cmp.w   VL_FREE(a4,d0.w),d5
        blt.s   .if_no
        moveq   #1,d1
.if_no:
        lsr.w   #1,d0
        move.l  (sp)+,a0
.if_r:
        rts
; .vs_wait(d0.w = line, a1 = write pointer): pseudo-WAIT at VL_HPOS.
.vs_wait:
        move.w  #GFX_PSEUDO,(a1)+
        move.w  d0,(a1)+
        move.w  #VL_HPOS,(a1)+
        clr.w   (a1)+
        move.w  #GFX_NOP,(a1)+
        clr.w   (a1)+
        rts
; .vs_flush(d0.w = line): the pending clean-ups on that line or above, in line order. Preserves d2-d7.
.vs_flush:
        movem.l d2-d4,-(sp)
        move.w  d0,d4
.vf_lp:
        moveq   #-1,d3               ; d3 = sprite of the earliest clean-up, d2 = its line
        move.w  #$7FFF,d2
        moveq   #0,d1
.vf_sc:
        move.w  d1,d0
        add.w   d0,d0
        move.w  VL_CLEAN(a4,d0.w),d0
        cmp.w   d2,d0
        bge.s   .vf_n
        move.w  d0,d2
        move.w  d1,d3
.vf_n:
        addq.w  #1,d1
        cmp.w   #8,d1
        blo.s   .vf_sc
        tst.w   d3
        bmi.s   .vf_ret
        cmp.w   d4,d2
        bgt.s   .vf_ret
        move.w  d2,d0
        bsr.s   .vs_wait
        move.w  d3,d0
        lsl.w   #3,d0
        add.w   #$140,d0
        move.w  d0,(a1)+             ; SPRxPOS = 0
        clr.w   (a1)+
        addq.w  #2,d0
        move.w  d0,(a1)+             ; SPRxCTL = 0
        clr.w   (a1)+
        move.w  d3,d0
        add.w   d0,d0
        move.w  #$7FFF,VL_CLEAN(a4,d0.w)
        bra.s   .vf_lp
.vf_ret:
        movem.l (sp)+,d2-d4
        rts
