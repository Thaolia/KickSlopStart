; src/intuition/gadgets.s - intuition.library: application gadgets of windows (wd_FirstGadget list). Rendering
; (Border or Image, IntuiText, highlight), left-button selection with GADGETDOWN / GADGETUP (im_IAddress = the
; gadget), AddGadget/AddGList, RemoveGadget/RemoveGList, RefreshGadgets/RefreshGList, OnGadget/OffGadget, DrawBorder.
; Text gadgets (STRGADGET, StringInfo): activated by a click or ActivateGadget, they receive the keyboard (routed by
; the pointer handler, see it_keyin): insertion, Backspace, Del, arrows (Shift: start / end), right Amiga + X
; (clear) and + Q (undo); Return / Enter ends (LONGINT converted, GADGETUP if RELVERIFY), a click elsewhere
; deactivates without a message. Left-aligned text (STRINGCENTER / STRINGRIGHT ignored). The other types are handled
; as buttons; no "ghost" pattern for a disabled gadget (it simply no longer responds).
; IMPLEMENTATION track ("clean"): public structures intuition/intuition.h + AutoDocs intuition. NO ROM reading.

                include "exec.i"
                include "graphics.i"
                include "intuition.i"

                xdef    intuition_AddGadget
                xref    it_unclip            ; screens.s: drawing outside the application's ClipRegion
                xref    it_reclip
                xdef    intuition_AddGList
                xdef    intuition_RemoveGadget
                xdef    intuition_RemoveGList
                xdef    intuition_RefreshGadgets
                xdef    intuition_RefreshGList
                xdef    intuition_OnGadget
                xdef    intuition_OffGadget
                xdef    intuition_DrawBorder
                xdef    gad_drawall
                xdef    gad_rect
                xdef    gad_down
                xdef    gad_up
                xdef    gad_forget
                xdef    intuition_ActivateGadget
                xdef    str_key
                xdef    str_clickout
                xref    kbd_cook
                xref    intuition_DrawImage
                xref    intuition_PrintIText
                xref    wn_sendgad
                xref    wn_sysgads
                xref    it_scrxy
                xdef    gad_propinit
                xdef    gad_propinitl
                xdef    gad_drawrev
                xdef    rq_origin
                xref    rq_endgadget         ; request.s: end of the requester through an ENDGADGET
                xdef    prop_track
                xdef    intuition_ModifyProp
                xdef    intuition_NewModifyProp

; gad_rect(a3 = window, a0 = gadget, a1 = 4 words x0, y0, x1, y1): gadget rectangle in window coordinates,
; positions and sizes relative to the right / bottom edge resolved. Inner gadget of a GIMMEZEROZERO window: relative to
; the interior (GZZ size), then offset by the left and top borders. Requester gadget: relative to the requester
; (its size, offset by its corner, spec intuition-requesters-v34 §2.4). Clobbers d0/d1.
gad_rect:
        movem.l d2-d5,-(sp)
        moveq   #0,d4                ; d4/d5 = corner of the domain in the window
        moveq   #0,d5
        move.w  WD_WIDTH(a3),d2      ; d2/d3 = size of the domain
        move.w  WD_HEIGHT(a3),d3
        bsr     gad_reqof
        beq.s   .gr_win
        move.l  a0,-(sp)
        move.l  d0,a0
        move.w  RQ_WIDTH(a0),d2
        move.w  RQ_HEIGHT(a0),d3
        bsr     rq_origin
        move.w  d0,d4
        move.w  d1,d5
        move.l  (sp)+,a0
        bra.s   .gr_ref
.gr_win:
        bsr     gad_inner
        beq.s   .gr_ref
        move.w  WD_GZZWIDTH(a3),d2
        move.w  WD_GZZHEIGHT(a3),d3
        move.b  WD_BORDERLEFT(a3),d4
        move.b  WD_BORDERTOP(a3),d5
.gr_ref:
        move.w  GG_FLAGS(a0),d1
        move.w  GG_LEFTEDGE(a0),d0
        btst    #4,d1                ; GRELRIGHT: right edge of the domain (width - 1) + LeftEdge
        beq.s   .gr_x
        add.w   d2,d0
        subq.w  #1,d0
.gr_x:
        move.w  d0,(a1)
        move.w  GG_TOPEDGE(a0),d0
        btst    #3,d1                ; GRELBOTTOM: bottom edge of the domain (height - 1) + TopEdge
        beq.s   .gr_y
        add.w   d3,d0
        subq.w  #1,d0
.gr_y:
        move.w  d0,2(a1)
        move.w  GG_WIDTH(a0),d0
        btst    #5,d1                ; GRELWIDTH
        beq.s   .gr_w
        add.w   d2,d0
.gr_w:
        add.w   (a1),d0
        subq.w  #1,d0
        move.w  d0,4(a1)
        move.w  GG_HEIGHT(a0),d0
        btst    #6,d1                ; GRELHEIGHT
        beq.s   .gr_h
        add.w   d3,d0
.gr_h:
        add.w   2(a1),d0
        subq.w  #1,d0
        move.w  d0,6(a1)
        add.w   d4,(a1)
        add.w   d4,4(a1)
        add.w   d5,2(a1)
        add.w   d5,6(a1)
        movem.l (sp)+,d2-d5
        rts

gad_skip:
        rts

; gad_reqof(a3 = window, a0 = gadget) -> d0 = the window's requester that carries this gadget (REQGADGET), 0 otherwise;
; Z = 1 if none. Preserves everything else.
gad_reqof:
        moveq   #0,d0
        btst    #4,GG_GADGETTYPE(a0) ; REQGADGET ($1000)
        beq.s   .ro_none
        movem.l a1-a2,-(sp)
        move.l  WD_FIRSTREQUEST(a3),a1
.rq_lp:
        move.l  a1,d0
        beq.s   .rq_ret
        move.l  RQ_REQGADGET(a1),a2
.rq_gad:
        cmpa.w  #0,a2
        beq.s   .rq_next
        cmpa.l  a0,a2
        beq.s   .rq_ret              ; d0 = this requester
        move.l  GG_NEXTGADGET(a2),a2
        bra.s   .rq_gad
.rq_next:
        move.l  RQ_OLDERREQ(a1),a1
        bra.s   .rq_lp
.rq_ret:
        movem.l (sp)+,a1-a2
        tst.l   d0
.ro_none:
        rts

; rq_origin(a3 = window, a0 = requester) -> d0.w/d1.w = corner of the requester in the window: LeftEdge/TopEdge, plus
; the borders in a GIMMEZEROZERO window (relative to the interior). Preserves everything else.
rq_origin:
        move.w  RQ_LEFTEDGE(a0),d0
        move.w  RQ_TOPEDGE(a0),d1
        btst    #2,WD_FLAGS+2(a3)    ; GIMMEZEROZERO
        beq.s   .og_ret
        tst.l   WD_BORDERRPORT(a3)   ; (BACKDROP: a single layer)
        beq.s   .og_ret
        move.l  d2,-(sp)
        moveq   #0,d2
        move.b  WD_BORDERLEFT(a3),d2
        add.w   d2,d0
        move.b  WD_BORDERTOP(a3),d2
        add.w   d2,d1
        move.l  (sp)+,d2
.og_ret:
        rts

; gad_nolayer(a3 = window, a2 = gadget) -> Z = 0 if it is a requester gadget without a layer (requester clipped to
; nothing): nothing to draw. Preserves everything else.
gad_nolayer:
        movem.l d0/a0,-(sp)
        move.l  a2,a0
        bsr.s   gad_reqof
        beq.s   .nl_ret              ; Z = 1: not a requester gadget
        move.l  d0,a0
        tst.l   RQ_REQLAYER(a0)
        seq     d0                   ; d0 = $FF if no layer
        tst.b   d0
.nl_ret:
        movem.l (sp)+,d0/a0          ; (movem does not touch the flags)
        rts

; gad_inner(a3 = window, a0 = gadget) -> Z = 0 if it is an interior gadget of a GIMMEZEROZERO window (not
; GZZGADGET): drawn in the inner layer, at the origin of the interior. Preserves everything.
gad_inner:
        btst    #2,WD_FLAGS+2(a3)    ; GIMMEZEROZERO
        beq.s   .gn_ret
        tst.l   WD_BORDERRPORT(a3)   ; (BACKDROP: a single layer)
        beq.s   .gn_ret
        btst    #5,GG_GADGETTYPE(a0) ; GZZGADGET ($2000): in the border -> Z = 1; otherwise Z = 0
        eori.b  #4,ccr
.gn_ret:
        rts

; gad_rpof(a3 = window, a2 = gadget) -> a0 = RastPort to draw it in: that of the requester's layer for a requester
; gadget (caller: gad_nolayer checked), that of the border for a GZZGADGET gadget of a GIMMEZEROZERO window,
; otherwise that of the window (the interior). Preserves everything else.
gad_rpof:
        move.l  d0,-(sp)
        move.l  a2,a0
        bsr     gad_reqof
        beq.s   .ro_win
        move.l  d0,a0                ; requester gadget: the requester's layer
        move.l  RQ_REQLAYER(a0),a0
        move.l  IL_RP(a0),a0
        move.l  (sp)+,d0
        rts
.ro_win:
        move.l  (sp)+,d0
        move.l  WD_RPORT(a3),a0
        btst    #2,WD_FLAGS+2(a3)
        beq.s   .ro_ret
        tst.l   WD_BORDERRPORT(a3)
        beq.s   .ro_ret
        btst    #5,GG_GADGETTYPE(a2)
        beq.s   .ro_ret
        move.l  WD_BORDERRPORT(a3),a0
.ro_ret:
        rts

; gad_rp(a3 = window, a2 = gadget, a1 = rectangle from gad_rect) -> a1 unchanged, a0 = RastPort to draw in (gad_rpof);
; the rectangle is brought into this RastPort (inner gadget of a GIMMEZEROZERO window: minus the borders; requester
; gadget: minus the requester's corner). Clobbers d0.
gad_rp:
        bsr.s   gad_rpof
        move.l  a0,-(sp)
        move.l  a2,a0
        bsr     gad_reqof
        beq.s   .rp_win
        move.l  d1,-(sp)
        move.l  d0,a0                ; requester gadget: rectangle relative to the requester's corner
        bsr     rq_origin
        sub.w   d0,(a1)
        sub.w   d0,4(a1)
        sub.w   d1,2(a1)
        sub.w   d1,6(a1)
        move.l  (sp)+,d1
        move.l  (sp)+,a0
        rts
.rp_win:
        move.l  (sp)+,a0
        exg     a0,a2
        bsr     gad_inner
        exg     a0,a2
        beq.s   .rp_ret
        moveq   #0,d0
        move.b  WD_BORDERLEFT(a3),d0
        sub.w   d0,(a1)
        sub.w   d0,4(a1)
        move.b  WD_BORDERTOP(a3),d0
        sub.w   d0,2(a1)
        sub.w   d0,6(a1)
.rp_ret:
        rts

; gad_inside(a3 = window, a0 = gadget, d2/d3 = point in the window) -> Z = 0 if the point is in the gadget.
; Clobbers d0/d1/a1.
gad_inside:
        lea     -8(sp),sp
        move.l  sp,a1
        bsr     gad_rect
        moveq   #0,d0                ; Z = 1 by default (outside)
        cmp.w   (sp),d2
        blt.s   .gi_out
        cmp.w   4(sp),d2
        bgt.s   .gi_out
        cmp.w   2(sp),d3
        blt.s   .gi_out
        cmp.w   6(sp),d3
        bgt.s   .gi_out
        moveq   #1,d0
.gi_out:
        lea     8(sp),sp
        tst.l   d0
        rts

; gad_draw(a3 = window, a2 = gadget, a5 = IntuitionBase): image or border (SelectRender if selected in
; GADGHIMAGE), text, then highlight of a selected gadget in GADGHCOMP / GADGHBOX. gad_render: without this
; highlight. Preserves d2-d7/a2-a6.
gad_draw:
        moveq   #1,d0
        bra.s   gad_drw
gad_render:
        moveq   #0,d0
gad_drw:
        bsr     gad_nolayer
        bne     gad_skip
        bsr     it_unclip
        bsr     gad_drw_nc
        bra     it_reclip
gad_drw_nc:
        movem.l d2-d7/a2-a6,-(sp)
        move.w  d0,d7                ; d7 = wanted highlight
        lea     -8(sp),sp
        move.l  a2,a0
        move.l  sp,a1
        bsr     gad_rect
        bsr     gad_rp
        move.l  a0,a4                ; a4 = RastPort of the gadget, rectangle brought into it
        move.w  GG_GADGETTYPE(a2),d0
        and.w   #GTYP_MASK,d0
        cmp.w   #PROPGADGET,d0
        bne.s   .gd_nprop
        bsr     prop_render          ; proportional: box, border, knob; then its text
        move.l  a5,a6
        bra     .gd_txt
.gd_nprop:
        move.l  a5,a6
        move.l  GG_GADGETRENDER(a2),a1
        move.w  GG_FLAGS(a2),d0
        btst    #7,d0                ; SELECTED
        beq.s   .gd_img
        and.w   #GADGHIGHBITS,d0
        cmp.w   #GADGHIMAGE,d0
        bne.s   .gd_img
        tst.l   GG_SELECTRENDER(a2)
        beq.s   .gd_img
        move.l  GG_SELECTRENDER(a2),a1
.gd_img:
        move.l  a1,d0
        beq.s   .gd_txt
        move.l  a4,a0
        move.w  (sp),d0
        ext.l   d0
        move.w  2(sp),d1
        ext.l   d1
        btst    #2,GG_FLAGS+1(a2)    ; GADGIMAGE
        bne.s   .gd_image
        bsr     intuition_DrawBorder
        bra.s   .gd_txt
.gd_image:
        jsr     intuition_DrawImage
.gd_txt:
        move.l  GG_GADGETTEXT(a2),d0
        beq.s   .gd_hl
        move.l  d0,a1
        move.l  a4,a0
        move.w  (sp),d0
        ext.l   d0
        move.w  2(sp),d1
        ext.l   d1
        jsr     intuition_PrintIText
.gd_hl:
        move.w  GG_GADGETTYPE(a2),d0
        and.w   #GTYP_MASK,d0
        cmp.w   #STRGADGET,d0
        bne.s   .gd_sel
        bsr     str_text
        bra.s   .gd_ret
.gd_sel:
        tst.w   d7
        beq.s   .gd_ret
        cmp.w   #PROPGADGET,d0       ; (proportional: its knob already carries the held state)
        beq.s   .gd_ret
        btst    #7,GG_FLAGS+1(a2)    ; SELECTED
        beq.s   .gd_ret
        bsr.s   gad_comp
.gd_ret:
        lea     8(sp),sp
        movem.l (sp)+,d2-d7/a2-a6
        rts

; gad_comp(a3 = window, a2 = gadget, a5, rectangle at 4(sp)): highlight by inversion, of the whole gadget
; (GADGHCOMP) or of its outline (GADGHBOX); a second inversion erases it. Preserves d2-d7/a2-a5.
gad_comp:
        move.w  GG_FLAGS(a2),d0
        and.w   #GADGHIGHBITS,d0
        cmp.w   #GADGHBOX,d0
        bhi.s   .gc_ret              ; GADGHIMAGE / GADGHNONE: nothing to invert
        movem.l d2-d7/a2-a3/a6,-(sp)
        move.w  d0,d7                ; d7 = 0 whole / 1 outline
        bsr     gad_rpof             ; RastPort of the gadget (rectangle already brought into it by the caller)
        move.l  a0,a3                ; a3 = RastPort from now on
        movem.w 4+36(sp),d4-d6/a2    ; x0 y0 x1 y1 (a2 = y1, extended)
        move.l  a2,d3
        move.l  IB_GFXBASE(a5),a6
        move.l  a3,a1
        moveq   #0,d0
        move.b  rp_DrawMode(a1),d0
        move.l  d0,-(sp)
        moveq   #COMPLEMENT,d0
        jsr     LVO_SETDRMD(a6)
        tst.w   d7
        bne.s   .gc_box
        move.w  d4,d0
        move.w  d5,d1
        move.w  d6,d2
        bsr.s   .gc_fill             ; d3 = y1
        bra.s   .gc_end
.gc_box:
        move.w  d4,d0                ; top
        move.w  d5,d1
        move.w  d6,d2
        move.l  d3,-(sp)
        move.w  d5,d3
        bsr.s   .gc_fill
        move.l  (sp)+,d3
        move.w  d4,d0                ; bottom
        move.w  d3,d1
        move.w  d6,d2
        bsr.s   .gc_fill
        move.w  d4,d0                ; left (without the corners already inverted)
        move.w  d5,d1
        addq.w  #1,d1
        move.w  d4,d2
        subq.w  #1,d3
        bsr.s   .gc_fill
        move.w  d6,d0                ; right
        move.w  d5,d1
        addq.w  #1,d1
        move.w  d6,d2
        bsr.s   .gc_fill
.gc_end:
        move.l  a3,a1
        move.l  (sp)+,d0
        jsr     LVO_SETDRMD(a6)
        movem.l (sp)+,d2-d7/a2-a3/a6
.gc_ret:
        rts
.gc_fill:                            ; RectFill(rp, d0, d1, d2, d3) if the rectangle is not empty
        cmp.w   d0,d2
        blt.s   .gf_ret
        cmp.w   d1,d3
        blt.s   .gf_ret
        movem.l d0-d3,-(sp)
        move.l  a3,a1
        ext.l   d0
        ext.l   d1
        ext.l   d2
        ext.l   d3
        jsr     LVO_RECTFILL(a6)
        movem.l (sp)+,d0-d3
.gf_ret:
        rts

; gad_drawall(a3 = window, a5 = IntuitionBase): all the application gadgets of the window. Preserves everything.
gad_drawall:
        movem.l d0-d2/a0-a2,-(sp)
        move.l  WD_FIRSTGADGET(a3),a2
        moveq   #-1,d2
        bsr.s   gad_drawrev
        movem.l (sp)+,d0-d2/a0-a2
        rts

; gad_drawrev(a2 = first gadget, d2 = count (-1 = up to the end), a3 = window, a5): as in intuition 1.3, the
; range is rendered in reverse, from last to first, so that the first of the list ends up on top (info.library
; relies on it so that SAVE/QUIT, at the head, cover their filler); then, in forward order, the highlight of the
; selected gadgets. Quadratic walk without a stack (short lists). The system gadgets are drawn with the
; border. Clobbers d0-d2/a0-a2.
gad_drawrev:
        move.l  a2,a0                ; a0 = end of range (gadget following the last one, or NULL)
.dr_end:
        move.l  a0,d0
        beq.s   .dr_go
        tst.l   d2
        beq.s   .dr_go
        subq.l  #1,d2
        move.l  GG_NEXTGADGET(a0),a0
        bra.s   .dr_end
.dr_go:
        movem.l a0/a2,-(sp)          ; end of range, first gadget
.dr_lp:
        cmp.l   a2,a0
        beq.s   .dr_hl               ; range empty or fully rendered
        move.l  a2,a1                ; look for the predecessor of the end
.dr_pred:
        cmp.l   GG_NEXTGADGET(a1),a0
        beq.s   .dr_got
        move.l  GG_NEXTGADGET(a1),a1
        bra.s   .dr_pred
.dr_got:
        move.l  a1,-(sp)
        tst.w   GG_GADGETTYPE(a1)    ; SYSGADGET (bit 15)
        bmi.s   .dr_skip
        move.l  a1,a2
        bsr     gad_render
        move.l  4+4(sp),a2
.dr_skip:
        move.l  (sp)+,a0             ; this gadget becomes the new end
        bra.s   .dr_lp
.dr_hl:
        movem.l (sp)+,a0/a2
.dr_hlp:
        cmp.l   a2,a0
        beq.s   .dr_ret
        tst.w   GG_GADGETTYPE(a2)
        bmi.s   .dr_hnext
        btst    #7,GG_FLAGS+1(a2)    ; SELECTED
        beq.s   .dr_hnext
        move.w  GG_FLAGS(a2),d0
        and.w   #GADGHIGHBITS,d0
        cmp.w   #GADGHIMAGE,d0       ; SelectRender already rendered
        beq.s   .dr_hnext
        move.l  a0,-(sp)
        bsr     gad_hilite
        move.l  (sp)+,a0
.dr_hnext:
        move.l  GG_NEXTGADGET(a2),a2
        bra.s   .dr_hlp
.dr_ret:
        rts

; gad_hilite(a3, a2, a5): the SELECTED state just changed -> highlight updated (inversion, or image redrawn
; in GADGHIMAGE). Preserves d2-d7/a2-a5.
gad_hilite:
        bsr     gad_nolayer
        bne     gad_skip
        bsr     it_unclip
        bsr     gad_hilite_nc
        bra     it_reclip
gad_hilite_nc:
        move.w  GG_FLAGS(a2),d0
        and.w   #GADGHIGHBITS,d0
        cmp.w   #GADGHIMAGE,d0
        beq     gad_draw
        lea     -8(sp),sp
        move.l  a2,a0
        move.l  sp,a1
        bsr     gad_rect
        bsr     gad_rp
        bsr     gad_comp
        lea     8(sp),sp
        rts

; gad_down(a3 = window, a5, d2/d3 = click in the window) -> Z = 0 if an enabled application gadget took it:
; it is selected (or toggled in TOGGLESELECT), GADGETDOWN if it is GADGIMMEDIATE, and it stays pressed until the
; release (gad_up). With a requester, the window's gadgets are inert: only those of the most recent one
; count, if the click lands on its layer (spec intuition-requesters-v34 §3.1). Clobbers d0/d1/d6/a0/a1/a6.
gad_down:
        move.l  a2,-(sp)
        move.l  WD_FIRSTGADGET(a3),a2
        move.l  WD_FIRSTREQUEST(a3),d0
        beq.s   .gn_lp
        suba.l  a2,a2
        move.l  d0,a0
        move.l  RQ_REQLAYER(a0),d0
        beq.s   .gn_lp
        move.l  d0,a1
        move.w  d2,d0                ; click -> screen coordinates
        add.w   WD_LEFTEDGE(a3),d0
        cmp.w   IL_MINX(a1),d0
        blt.s   .gn_lp
        cmp.w   IL_MAXX(a1),d0
        bgt.s   .gn_lp
        move.w  d3,d0
        add.w   WD_TOPEDGE(a3),d0
        cmp.w   IL_MINY(a1),d0
        blt.s   .gn_lp
        cmp.w   IL_MAXY(a1),d0
        bgt.s   .gn_lp
        move.l  RQ_REQGADGET(a0),a2
.gn_lp:
        move.l  a2,d0
        beq.s   .gn_none
        tst.w   GG_GADGETTYPE(a2)
        bmi.s   .gn_next
        btst    #0,GG_FLAGS(a2)      ; GADGDISABLED (bit 8)
        bne.s   .gn_next
        move.l  a2,a0
        bsr     gad_inside
        bne.s   .gn_hit
.gn_next:
        move.l  GG_NEXTGADGET(a2),a2
        bra.s   .gn_lp
.gn_hit:
        move.w  GG_GADGETTYPE(a2),d0
        and.w   #GTYP_MASK,d0
        cmp.w   #PROPGADGET,d0
        beq.s   .gn_prop
        cmp.w   #STRGADGET,d0
        bne.s   .gn_bool
        bsr     str_activate         ; d2 = x of the click: places the cursor
        bra.s   .gn_taken
.gn_prop:
        bsr     prop_down
        bra.s   .gn_imm
.gn_bool:
        move.l  a2,IB_GADACT(a5)
        move.l  a3,IB_GADWIN(a5)
        btst    #0,GG_ACTIVATION(a2) ; TOGGLESELECT (bit 8)
        beq.s   .gn_sel
        bchg    #7,GG_FLAGS+1(a2)
        bra.s   .gn_hl
.gn_sel:
        bset    #7,GG_FLAGS+1(a2)
.gn_hl:
        bsr     gad_hilite
.gn_imm:
        btst    #1,GG_ACTIVATION+1(a2)   ; GADGIMMEDIATE
        beq.s   .gn_taken
        moveq   #GADGETDOWN,d0
        moveq   #0,d1
        move.l  a2,a0
        bsr.s   gad_send
.gn_taken:
        move.l  (sp)+,a2
        moveq   #1,d0                ; Z = 0
        rts
.gn_none:
        move.l  (sp)+,a2
        moveq   #0,d0                ; Z = 1
        rts

; gad_send(a3, a0 = gadget, d0 = class, d1 = code, d2/d3 = mouse): IDCMP message whose im_IAddress is the gadget.
gad_send:
        movem.l d2-d7/a2-a5,-(sp)
        jsr     wn_sendgad
        movem.l (sp)+,d2-d7/a2-a5
        rts

; gad_up(a5, d4/d5 = screen pointer): release of a pressed gadget. Except in TOGGLESELECT it is deselected;
; GADGETUP if it is RELVERIFY and the pointer is still over it. Clobbers d0-d3/d6/a0/a1/a3/a6.
gad_up:
        move.l  a2,-(sp)
        move.l  IB_GADACT(a5),a2
        move.l  IB_GADWIN(a5),a3
        clr.l   IB_GADACT(a5)
        move.w  d4,d2
        sub.w   WD_LEFTEDGE(a3),d2
        move.w  d5,d3
        sub.w   WD_TOPEDGE(a3),d3
        move.w  GG_GADGETTYPE(a2),d0
        and.w   #GTYP_MASK,d0
        cmp.w   #PROPGADGET,d0
        bne.s   .gu_nprop
        bsr     prop_up
        bra.s   .gu_ret
.gu_nprop:
        btst    #0,GG_ACTIVATION(a2) ; TOGGLESELECT: the state toggled on click stays
        bne.s   .gu_verify
        bclr    #7,GG_FLAGS+1(a2)
        bsr     gad_hilite
.gu_verify:
        btst    #0,GG_ACTIVATION+1(a2)   ; RELVERIFY
        beq.s   .gu_end
        move.l  a2,a0
        bsr     gad_inside
        beq.s   .gu_end
        moveq   #GADGETUP,d0
        moveq   #0,d1
        move.l  a2,a0
        bsr.s   gad_send
.gu_end:
        btst    #2,GG_ACTIVATION+1(a2)   ; ENDGADGET released over it: end of the most recent requester
        beq.s   .gu_ret
        move.l  a2,a0
        bsr     gad_inside
        beq.s   .gu_ret
        move.l  a2,a0
        bsr     gad_reqof
        beq.s   .gu_ret
        cmp.l   WD_FIRSTREQUEST(a3),d0
        bne.s   .gu_ret
        jsr     rq_endgadget
.gu_ret:
        move.l  (sp)+,a2
        rts

; gad_forget(a0 = window | gadget): forgets the pressed gadget if it belongs to this window or is this gadget
; (window closed, gadget removed). a6 = IntuitionBase. Clobbers d0.
gad_forget:
        cmp.l   IB_SYSWIN(a6),a0     ; system gadget pressed in this window: forgotten
        bne.s   .gf_sys
        clr.w   IB_SYSACT(a6)
.gf_sys:
        cmp.l   IB_STRWIN(a6),a0
        beq.s   .gf_str
        cmp.l   IB_STRGAD(a6),a0
        bne.s   .gf_act
.gf_str:
        clr.l   IB_STRGAD(a6)
.gf_act:
        cmp.l   IB_GADWIN(a6),a0
        beq.s   .gf_clr
        cmp.l   IB_GADACT(a6),a0
        bne.s   .gf_r
.gf_clr:
        clr.l   IB_GADACT(a6)
.gf_r:
        rts

; --- proportional gadgets (spec intuition-prop-v34) ----------------------------------------------------------
; work area: box and container in coordinates of the gadget's RastPort, knob relative to the container, window ->
; RastPort offset
PP_L            EQU 0
PP_T            EQU 2
PP_R            EQU 4
PP_B            EQU 6
PP_CL           EQU 8
PP_CT           EQU 10
PP_CW           EQU 12
PP_CH           EQU 14
PP_KX           EQU 16
PP_KY           EQU 18
PP_KW           EQU 20
PP_KH           EQU 22
PP_DX           EQU 24
PP_DY           EQU 26
PP_SIZE         EQU 28

; gad_propinit(a3 = window): PropInfo borders of each proportional gadget of the window, as when a gadget
; enters a window: WBorLeft / WBorTop of the screen, 0 / 0 if PROPBORDERLESS (spec §1). Preserves everything.
gad_propinit:
        move.l  a2,-(sp)
        move.l  WD_FIRSTGADGET(a3),a2
        bsr.s   gad_propinitl
        move.l  (sp)+,a2
        rts
; gad_propinitl(a3 = window, a2 = first gadget of a list): same for this list (gadgets of a requester).
gad_propinitl:
        movem.l d0-d1/a0-a2,-(sp)
        move.l  WD_WSCREEN(a3),a1
.pi_lp:
        move.l  a2,d0
        beq.s   .pi_ret
        move.w  GG_GADGETTYPE(a2),d0
        and.w   #GTYP_MASK,d0
        cmp.w   #PROPGADGET,d0
        bne.s   .pi_next
        move.l  GG_SPECIALINFO(a2),d0
        beq.s   .pi_next
        move.l  d0,a0
        moveq   #0,d0
        moveq   #0,d1
        btst    #3,PI_FLAGS+1(a0)    ; PROPBORDERLESS
        bne.s   .pi_set
        move.l  a1,d1
        beq.s   .pi_set
        move.b  SC_WBORLEFT(a1),d0
        moveq   #0,d1
        move.b  SC_WBORTOP(a1),d1
.pi_set:
        move.w  d0,PI_LBORDER(a0)
        move.w  d1,PI_TBORDER(a0)
.pi_next:
        move.l  GG_NEXTGADGET(a2),a2
        bra.s   .pi_lp
.pi_ret:
        movem.l (sp)+,d0-d1/a0-a2
        rts

; prop_prep(a3 = window, a2 = gadget, a1 = PP_SIZE area) -> a0 = RastPort of the gadget, area filled (spec §2). Writes
; CWidth/CHeight and the PotRes of the PropInfo, the knob size into the render Image (AUTOKNOB) and its position into
; the render and select Images. Preserves d2-d7/a2-a6.
prop_prep:
        movem.l d2-d7/a2-a4,-(sp)
        move.l  a1,a4
        move.l  a2,a0
        bsr     gad_rect
        move.l  (a4),d2              ; corner of the box in the window (x, y)
        move.l  a4,a1
        bsr     gad_rp
        move.l  a0,-(sp)
        swap    d2
        sub.w   PP_L(a4),d2
        move.w  d2,PP_DX(a4)
        swap    d2
        sub.w   PP_T(a4),d2
        move.w  d2,PP_DY(a4)
        move.l  GG_SPECIALINFO(a2),a1
        move.w  PI_LBORDER(a1),d4
        move.w  PI_TBORDER(a1),d5
        move.w  PP_L(a4),d0          ; container = box minus the PropInfo borders
        add.w   d4,d0
        move.w  d0,PP_CL(a4)
        move.w  PP_T(a4),d0
        add.w   d5,d0
        move.w  d0,PP_CT(a4)
        move.w  PP_R(a4),d0
        sub.w   PP_L(a4),d0
        addq.w  #1,d0
        sub.w   d4,d0
        sub.w   d4,d0
        move.w  d0,PP_CW(a4)
        move.w  d0,PI_CWIDTH(a1)
        move.w  PP_B(a4),d0
        sub.w   PP_T(a4),d0
        addq.w  #1,d0
        sub.w   d5,d0
        sub.w   d5,d0
        move.w  d0,PP_CH(a4)
        move.w  d0,PI_CHEIGHT(a1)
        move.w  PI_HBODY(a1),d0
        bsr     .pp_step
        move.w  d0,PI_HPOTRES(a1)
        move.w  PI_VBODY(a1),d0
        bsr     .pp_step
        move.w  d0,PI_VPOTRES(a1)
        move.l  GG_GADGETRENDER(a2),a0   ; a0 = knob Image
        btst    #0,PI_FLAGS+1(a1)    ; AUTOKNOB: size from Body
        beq.s   .pp_img
        move.w  PP_CW(a4),d4         ; width
        btst    #1,PI_FLAGS+1(a1)    ; FREEHORIZ
        beq.s   .pp_kw
        moveq   #0,d0
        move.w  PI_HBODY(a1),d0
        mulu    PP_CW(a4),d0
        swap    d0
        addq.w  #1,d0
        moveq   #6,d1
        move.w  PP_CW(a4),d2
        bsr     .pp_clamp
        move.w  d0,d4
.pp_kw:
        move.w  PP_CH(a4),d5         ; height
        btst    #2,PI_FLAGS+1(a1)    ; FREEVERT
        beq.s   .pp_kh
        moveq   #0,d0
        move.w  PI_VBODY(a1),d0
        mulu    PP_CH(a4),d0
        swap    d0
        addq.w  #1,d0
        moveq   #4,d1
        move.w  PP_CH(a4),d2
        bsr     .pp_clamp
        move.w  d0,d5
.pp_kh:
        move.w  d4,IG_WIDTH(a0)
        move.w  d5,IG_HEIGHT(a0)
        bra.s   .pp_pos
.pp_img:
        move.w  IG_WIDTH(a0),d4
        move.w  IG_HEIGHT(a0),d5
.pp_pos:
        move.w  d4,PP_KW(a4)
        move.w  d5,PP_KH(a4)
        moveq   #0,d6                ; knob x
        btst    #1,PI_FLAGS+1(a1)
        beq.s   .pp_kx
        move.w  PP_CW(a4),d0
        sub.w   d4,d0
        move.w  PI_HPOT(a1),d1
        bsr     .pp_place
        move.w  d0,d6
.pp_kx:
        moveq   #0,d7                ; knob y
        btst    #2,PI_FLAGS+1(a1)
        beq.s   .pp_ky
        move.w  PP_CH(a4),d0
        sub.w   d5,d0
        move.w  PI_VPOT(a1),d1
        bsr     .pp_place
        move.w  d0,d7
.pp_ky:
        move.w  d6,PP_KX(a4)
        move.w  d7,PP_KY(a4)
        move.w  d6,IG_LEFTEDGE(a0)
        move.w  d7,IG_TOPEDGE(a0)
        move.l  GG_SELECTRENDER(a2),d0
        beq.s   .pp_ret
        move.l  d0,a0
        move.w  d6,IG_LEFTEDGE(a0)
        move.w  d7,IG_TOPEDGE(a0)
.pp_ret:
        move.l  (sp)+,a0
        movem.l (sp)+,d2-d7/a2-a4
        rts
.pp_step:                            ; d0.w = Body -> d0.w = page step ($FFFF as soon as Body >= $8000). Clobbers d1.
        cmp.w   #$8000,d0
        bhs.s   .ps_max
        moveq   #0,d1
        move.w  d0,d1
        swap    d1                   ; Body << 16
        neg.w   d0
        subq.w  #1,d0                ; $FFFF - Body
        divu    d0,d1
        move.w  d1,d0
        rts
.ps_max:
        moveq   #-1,d0
        rts
.pp_clamp:                           ; d0.w brought into [d1, d2] then to at least 1
        cmp.w   d1,d0
        bge.s   .pc_lo
        move.w  d1,d0
.pc_lo:
        cmp.w   d2,d0
        ble.s   .pc_hi
        move.w  d2,d0
.pc_hi:
        cmp.w   #1,d0
        bge.s   .pc_r
        moveq   #1,d0
.pc_r:
        rts
.pp_place:                           ; d0.w = travel, d1.w = Pot -> d0.w = (travel x (Pot + 1)) >> 16 (travel < 0: 0)
        tst.w   d0
        bpl.s   .pl_ok
        moveq   #0,d0
        rts
.pl_ok:
        and.l   #$FFFF,d0
        and.l   #$FFFF,d1
        mulu    d0,d1
        add.l   d0,d1
        swap    d1
        move.w  d1,d0
        rts

; prop_render(a3 = window, a2 = gadget, a5): full drawing (spec §3.1): box in DetailPen, border in BlockPen
; (sides of WBorLeft/2, lines of WBorTop/2) except PROPBORDERLESS, then the knob. Preserves d2-d7/a2-a5; clobbers
; d0/d1/a0/a1/a6.
prop_render:
        lea     prop_rend(pc),a1
        bra.s   prop_keep

; prop_keep(a1 = drawing routine of a proportional gadget, a2/a3/a5, d4-d7 passed on): the routine is called,
; then the pens and mode of the gadget's RastPort are restored: it is often the window's, where
; the application draws without setting them again (OctaMED's file list, redrawn after RefreshGList of its
; scroller, became invisible). Clobbers d0/d1/a0/a1/a6.
prop_keep:
        move.l  a1,-(sp)
        bsr     gad_rpof
        move.l  (sp)+,a1
        move.l  a0,-(sp)
        move.b  rp_FgPen(a0),-(sp)
        move.b  rp_BgPen(a0),-(sp)
        move.b  rp_DrawMode(a0),-(sp)
        jsr     (a1)
        move.l  6(sp),a0
        move.b  (sp)+,rp_DrawMode(a0)
        move.b  (sp)+,rp_BgPen(a0)
        move.b  (sp)+,rp_FgPen(a0)
        addq.l  #4,sp
        rts

prop_rend:
        movem.l d2-d7/a4,-(sp)
        lea     -PP_SIZE(sp),sp
        move.l  sp,a1
        bsr     prop_prep
        move.l  a0,a4                ; a4 = RastPort
        move.l  IB_GFXBASE(a5),a6
        move.l  a4,a1
        moveq   #JAM2,d0
        jsr     LVO_SETDRMD(a6)
        moveq   #0,d0
        move.b  WD_DETAILPEN(a3),d0
        move.l  a4,a1
        jsr     LVO_SETAPEN(a6)
        movem.w (sp),d0-d3           ; box
        move.l  a4,a1
        jsr     LVO_RECTFILL(a6)
        move.l  GG_SPECIALINFO(a2),a0
        btst    #3,PI_FLAGS+1(a0)    ; PROPBORDERLESS
        bne.s   .pr_knob
        move.l  a4,a1
        moveq   #JAM1,d0
        jsr     LVO_SETDRMD(a6)
        moveq   #0,d0
        move.b  WD_BLOCKPEN(a3),d0
        move.l  a4,a1
        jsr     LVO_SETAPEN(a6)
        move.l  WD_WSCREEN(a3),a0
        moveq   #0,d6
        move.b  SC_WBORLEFT(a0),d6
        lsr.w   #1,d6                ; d6 = thickness of the sides
        moveq   #0,d7
        move.b  SC_WBORTOP(a0),d7
        lsr.w   #1,d7                ; d7 = thickness of the lines
        tst.w   d6
        beq.s   .pr_h
        movem.w (sp),d0-d3
        move.w  d0,d2
        add.w   d6,d2
        subq.w  #1,d2
        bsr.s   .pr_fill
        movem.w (sp),d0-d3
        move.w  d2,d0
        sub.w   d6,d0
        addq.w  #1,d0
        bsr.s   .pr_fill
.pr_h:
        tst.w   d7
        beq.s   .pr_knob
        movem.w (sp),d0-d3
        move.w  d1,d3
        add.w   d7,d3
        subq.w  #1,d3
        bsr.s   .pr_fill
        movem.w (sp),d0-d3
        move.w  d3,d1
        sub.w   d7,d1
        addq.w  #1,d1
        bsr.s   .pr_fill
.pr_knob:
        move.l  sp,a1
        bsr     prop_knob
        lea     PP_SIZE(sp),sp
        movem.l (sp)+,d2-d7/a4
        rts
.pr_fill:
        move.l  a4,a1
        jmp     LVO_RECTFILL(a6)

; prop_knob(a3 = window, a2 = gadget, a4 = RastPort, a1 = prepared area, a5, a6 = GfxBase): the knob (spec §3.1):
; AUTOKNOB = filled rectangle in BlockPen (complemented if held: SELECTED and KNOBHIT); otherwise the render Image
; (select Image in GADGHIMAGE), inverted in GADGHCOMP when held. Clobbers d0/d1/a0/a1; returns a6 = GfxBase.
prop_knob:
        movem.l d2-d5,-(sp)
        move.w  PP_CL(a1),d4
        move.w  PP_CT(a1),d5
        move.w  PP_KX(a1),d0
        add.w   d4,d0
        move.w  PP_KY(a1),d1
        add.w   d5,d1
        move.w  d0,d2
        add.w   PP_KW(a1),d2
        subq.w  #1,d2
        move.w  d1,d3
        add.w   PP_KH(a1),d3
        subq.w  #1,d3                ; d0-d3 = knob box
        moveq   #0,d5                ; d5 = knob held?
        btst    #7,GG_FLAGS+1(a2)    ; SELECTED
        beq.s   .pk_held
        move.l  GG_SPECIALINFO(a2),a0
        btst    #0,PI_FLAGS(a0)      ; KNOBHIT
        sne     d5
.pk_held:
        move.l  GG_SPECIALINFO(a2),a0
        btst    #0,PI_FLAGS+1(a0)    ; AUTOKNOB
        beq.s   .pk_img
        movem.w d0-d3,-(sp)
        move.l  a4,a1
        moveq   #JAM1,d0
        jsr     LVO_SETDRMD(a6)
        moveq   #0,d0
        move.b  WD_BLOCKPEN(a3),d0
        tst.b   d5
        beq.s   .pk_pen
        not.b   d0
.pk_pen:
        move.l  a4,a1
        jsr     LVO_SETAPEN(a6)
        movem.w (sp)+,d0-d3
        move.l  a4,a1
        jsr     LVO_RECTFILL(a6)
        bra.s   .pk_ret
.pk_img:
        movem.w d0-d3,-(sp)
        move.l  GG_GADGETRENDER(a2),a1
        tst.b   d5
        beq.s   .pk_draw
        move.w  GG_FLAGS(a2),d0
        and.w   #GADGHIGHBITS,d0
        cmp.w   #GADGHIMAGE,d0
        bne.s   .pk_draw
        tst.l   GG_SELECTRENDER(a2)
        beq.s   .pk_draw
        move.l  GG_SELECTRENDER(a2),a1
.pk_draw:
        move.l  a4,a0                ; container corner = knob box - knob position in the Image
        move.w  (sp),d0
        move.w  2(sp),d1
        sub.w   IG_LEFTEDGE(a1),d0
        sub.w   IG_TOPEDGE(a1),d1
        ext.l   d0
        ext.l   d1
        move.l  a5,a6
        jsr     intuition_DrawImage
        move.l  IB_GFXBASE(a5),a6
        movem.w (sp)+,d0-d3
        tst.b   d5
        beq.s   .pk_ret
        move.w  GG_FLAGS(a2),d4
        and.w   #GADGHIGHBITS,d4
        bne.s   .pk_ret              ; GADGHCOMP only
        movem.w d0-d3,-(sp)
        move.l  a4,a1
        moveq   #COMPLEMENT,d0
        jsr     LVO_SETDRMD(a6)
        movem.w (sp)+,d0-d3
        move.l  a4,a1
        jsr     LVO_RECTFILL(a6)
.pk_ret:
        movem.l (sp)+,d2-d5
        rts

; prop_update(a3 = window, a2 = gadget, a5, d4-d7 = old knob box x0, y0, x1, y1): the knob is redrawn
; at its new position, then the parts of the old one it no longer covers are restored in DetailPen (spec §3.2).
; Nothing if the position has not changed. Preserves d2-d7/a2-a5; clobbers d0/d1/a0/a1/a6.
PU_NEW          EQU PP_SIZE          ; new knob box (4 words)
prop_update:
        bsr     gad_nolayer
        bne     gad_skip
        bsr     it_unclip
        lea     prop_upd(pc),a1
        bsr     prop_keep
        bra     it_reclip
prop_upd:
        movem.l d2-d7/a4,-(sp)
        lea     -PP_SIZE-8(sp),sp
        move.l  sp,a1
        bsr     prop_prep
        move.l  a0,a4
        move.l  IB_GFXBASE(a5),a6
        move.w  PP_CL(sp),d0
        add.w   PP_KX(sp),d0
        move.w  d0,PU_NEW(sp)
        add.w   PP_KW(sp),d0
        subq.w  #1,d0
        move.w  d0,PU_NEW+4(sp)
        move.w  PP_CT(sp),d0
        add.w   PP_KY(sp),d0
        move.w  d0,PU_NEW+2(sp)
        add.w   PP_KH(sp),d0
        subq.w  #1,d0
        move.w  d0,PU_NEW+6(sp)
        cmp.w   PU_NEW(sp),d4
        bne.s   .pu_draw
        cmp.w   PU_NEW+2(sp),d5
        beq     .pu_ret
.pu_draw:
        move.l  sp,a1
        bsr     prop_knob
        move.l  a4,a1
        moveq   #JAM1,d0
        jsr     LVO_SETDRMD(a6)
        moveq   #0,d0
        move.b  WD_DETAILPEN(a3),d0
        move.l  a4,a1
        jsr     LVO_SETAPEN(a6)
        move.w  d4,d0                ; above the new box
        move.w  d5,d1
        move.w  d6,d2
        move.w  PU_NEW+2(sp),d3
        subq.w  #1,d3
        cmp.w   d7,d3
        ble.s   .pu_t
        move.w  d7,d3
.pu_t:
        bsr     .pu_fill
        move.w  d4,d0                ; below
        move.w  PU_NEW+6(sp),d1
        addq.w  #1,d1
        cmp.w   d5,d1
        bge.s   .pu_b
        move.w  d5,d1
.pu_b:
        move.w  d6,d2
        move.w  d7,d3
        bsr.s   .pu_fill
        move.w  PU_NEW+2(sp),d1      ; common band: left and right
        cmp.w   d5,d1
        bge.s   .pu_m0
        move.w  d5,d1
.pu_m0:
        move.w  PU_NEW+6(sp),d3
        cmp.w   d7,d3
        ble.s   .pu_m1
        move.w  d7,d3
.pu_m1:
        move.w  d4,d0
        move.w  PU_NEW(sp),d2
        subq.w  #1,d2
        cmp.w   d6,d2
        ble.s   .pu_l
        move.w  d6,d2
.pu_l:
        movem.w d1/d3,-(sp)
        bsr.s   .pu_fill
        movem.w (sp)+,d1/d3
        move.w  PU_NEW+4(sp),d0
        addq.w  #1,d0
        cmp.w   d4,d0
        bge.s   .pu_r
        move.w  d4,d0
.pu_r:
        move.w  d6,d2
        bsr.s   .pu_fill
.pu_ret:
        lea     PP_SIZE+8(sp),sp
        movem.l (sp)+,d2-d7/a4
        rts
.pu_fill:                            ; RectFill(d0..d3) if the rectangle is not empty. Clobbers d0/d1/a1.
        cmp.w   d0,d2
        blt.s   .pf_r
        cmp.w   d1,d3
        blt.s   .pf_r
        move.l  a4,a1
        jmp     LVO_RECTFILL(a6)
.pf_r:
        rts

; prop_down(a3 = window, a2 = gadget, a5, d2/d3 = click in the window, d4/d5 = screen pointer): the gadget is held
; (SELECTED). Click in the knob widened by the borders: KNOBHIT, drag tracked (IB_TRACK); elsewhere: jump of one
; page on each free axis, towards the click (spec §4). Preserves d2-d7/a2-a5; clobbers d0/d1/a0/a1/a6.
prop_down:
        movem.l d2-d7/a4,-(sp)
        move.l  a2,IB_GADACT(a5)
        move.l  a3,IB_GADWIN(a5)
        bset    #7,GG_FLAGS+1(a2)    ; SELECTED
        move.w  d4,IB_PMX(a5)
        move.w  d5,IB_PMY(a5)
        lea     -PP_SIZE(sp),sp
        move.l  sp,a1
        bsr     prop_prep
        move.l  a0,a4
        sub.w   PP_DX(sp),d2         ; d2/d3 = click in the RastPort
        sub.w   PP_DY(sp),d3
        move.w  PP_CL(sp),d4         ; d4-d7 = knob box
        add.w   PP_KX(sp),d4
        move.w  d4,d6
        add.w   PP_KW(sp),d6
        subq.w  #1,d6
        move.w  PP_CT(sp),d5
        add.w   PP_KY(sp),d5
        move.w  d5,d7
        add.w   PP_KH(sp),d7
        subq.w  #1,d7
        move.l  GG_SPECIALINFO(a2),a0
        move.w  d4,d0                ; knob widened by the PropInfo borders
        sub.w   PI_LBORDER(a0),d0
        cmp.w   d0,d2
        blt.s   .pd_page
        move.w  d6,d0
        add.w   PI_LBORDER(a0),d0
        cmp.w   d0,d2
        bgt.s   .pd_page
        move.w  d5,d0
        sub.w   PI_TBORDER(a0),d0
        cmp.w   d0,d3
        blt.s   .pd_page
        move.w  d7,d0
        add.w   PI_TBORDER(a0),d0
        cmp.w   d0,d3
        bgt.s   .pd_page
        bset    #0,PI_FLAGS(a0)      ; KNOBHIT
        move.w  PP_KX(sp),IB_PKX(a5)
        move.w  PP_KY(sp),IB_PKY(a5)
        st      IB_TRACK(a5)
        move.l  IB_GFXBASE(a5),a6
        move.l  sp,a1
        bsr     prop_knob            ; knob held
        bra.s   .pd_ret
.pd_page:
        bclr    #0,PI_FLAGS(a0)
        btst    #1,PI_FLAGS+1(a0)    ; FREEHORIZ
        beq.s   .pd_v
        move.w  PI_HPOT(a0),d0
        move.w  PI_HPOTRES(a0),d1
        cmp.w   d4,d2
        bge.s   .pd_hr
        sub.w   d1,d0
        bcc.s   .pd_hs
        moveq   #0,d0
        bra.s   .pd_hs
.pd_hr:
        cmp.w   d6,d2
        ble.s   .pd_v
        add.w   d1,d0
        bcc.s   .pd_hs
        moveq   #-1,d0
.pd_hs:
        move.w  d0,PI_HPOT(a0)
.pd_v:
        btst    #2,PI_FLAGS+1(a0)    ; FREEVERT
        beq.s   .pd_upd
        move.w  PI_VPOT(a0),d0
        move.w  PI_VPOTRES(a0),d1
        cmp.w   d5,d3
        bge.s   .pd_vr
        sub.w   d1,d0
        bcc.s   .pd_vs
        moveq   #0,d0
        bra.s   .pd_vs
.pd_vr:
        cmp.w   d7,d3
        ble.s   .pd_upd
        add.w   d1,d0
        bcc.s   .pd_vs
        moveq   #-1,d0
.pd_vs:
        move.w  d0,PI_VPOT(a0)
.pd_upd:
        bsr     prop_update
.pd_ret:
        lea     PP_SIZE(sp),sp
        movem.l (sp)+,d2-d7/a4
        rts

; prop_track(a5, d4/d5 = pointer) -> Z = 0 if a knob is held and this movement belongs to it: new position
; = previous + displacement, bounded to the container; Pots recomputed (spec §2.4); knob redrawn; MOUSEMOVE if
; FOLLOWMOUSE. Clobbers d0-d7/a0-a4/a6.
prop_track:
        move.l  IB_GADACT(a5),d0
        beq     .pt_no
        move.l  d0,a2
        move.w  GG_GADGETTYPE(a2),d0
        and.w   #GTYP_MASK,d0
        cmp.w   #PROPGADGET,d0
        bne     .pt_no
        move.l  GG_SPECIALINFO(a2),a0
        btst    #0,PI_FLAGS(a0)      ; KNOBHIT
        beq     .pt_no
        move.l  IB_GADWIN(a5),a3
        jsr     it_scrxy
        beq     .pt_yes
        move.w  d4,d2                ; d2/d3 = displacement
        sub.w   IB_PMX(a5),d2
        move.w  d5,d3
        sub.w   IB_PMY(a5),d3
        move.w  d4,IB_PMX(a5)
        move.w  d5,IB_PMY(a5)
        lea     -PP_SIZE(sp),sp
        move.l  sp,a1
        bsr     prop_prep
        move.w  PP_CL(sp),d4         ; d4-d7 = current knob box
        add.w   PP_KX(sp),d4
        move.w  d4,d6
        add.w   PP_KW(sp),d6
        subq.w  #1,d6
        move.w  PP_CT(sp),d5
        add.w   PP_KY(sp),d5
        move.w  d5,d7
        add.w   PP_KH(sp),d7
        subq.w  #1,d7
        move.l  GG_SPECIALINFO(a2),a0
        btst    #1,PI_FLAGS+1(a0)    ; FREEHORIZ
        beq.s   .pt_v
        move.w  PP_CW(sp),d1
        sub.w   PP_KW(sp),d1         ; travel
        move.w  IB_PKX(a5),d0
        add.w   d2,d0
        bsr.s   .pt_axis
        move.w  d0,IB_PKX(a5)
        move.w  d1,PI_HPOT(a0)
.pt_v:
        btst    #2,PI_FLAGS+1(a0)    ; FREEVERT
        beq.s   .pt_upd
        move.w  PP_CH(sp),d1
        sub.w   PP_KH(sp),d1
        move.w  IB_PKY(a5),d0
        add.w   d3,d0
        bsr.s   .pt_axis
        move.w  d0,IB_PKY(a5)
        move.w  d1,PI_VPOT(a0)
.pt_upd:
        lea     PP_SIZE(sp),sp
        bsr     prop_update
        btst    #3,GG_ACTIVATION+1(a2)   ; FOLLOWMOUSE
        beq.s   .pt_yes
        move.w  IB_PMX(a5),d2
        sub.w   WD_LEFTEDGE(a3),d2
        move.w  IB_PMY(a5),d3
        sub.w   WD_TOPEDGE(a3),d3
        moveq   #MOUSEMOVE,d0
        moveq   #0,d1
        move.l  a2,a0
        bsr     gad_send
.pt_yes:
        moveq   #1,d0                ; Z = 0
        rts
.pt_no:
        moveq   #0,d0                ; Z = 1
        rts
.pt_axis:                            ; d0.w = wanted position, d1.w = travel -> d0 = bounded position, d1 = Pot
        tst.w   d0
        bpl.s   .pa_lo
        moveq   #0,d0
.pa_lo:
        tst.w   d1
        bgt.s   .pa_hi
        moveq   #0,d0
        moveq   #-1,d1               ; full container: Pot = $FFFF
        rts
.pa_hi:
        cmp.w   d1,d0
        blt.s   .pa_div
        move.w  d1,d0
        moveq   #-1,d1
        rts
.pa_div:
        swap    d1
        clr.w   d1
        swap    d1                   ; d1 = travel (long)
        move.l  d0,-(sp)
        and.l   #$FFFF,d0
        swap    d0                   ; position << 16
        divu    d1,d0
        move.w  d0,d1
        move.l  (sp)+,d0
        rts

; prop_up(a3 = window, a2 = gadget, a5, d2/d3 = pointer in the window): release: the gadget is no longer held,
; tracking stops, knob redrawn; GADGETUP if it is RELVERIFY, wherever the pointer is.
prop_up:
        bclr    #7,GG_FLAGS+1(a2)
        move.l  GG_SPECIALINFO(a2),a0
        btst    #0,PI_FLAGS(a0)      ; KNOBHIT: drag tracked
        beq.s   .pu2_draw
        clr.b   IB_TRACK(a5)
.pu2_draw:
        bsr     prop_render
        btst    #0,GG_ACTIVATION+1(a2)   ; RELVERIFY
        beq.s   .pu2_ret
        moveq   #GADGETUP,d0
        moveq   #0,d1
        move.l  a2,a0
        bsr     gad_send
.pu2_ret:
        rts

; ModifyProp(gadget a0, window a1, requester a2, Flags d0, HorizPot d1, VertPot d2, HorizBody d3, VertBody d4):
; new PropInfo values, then redraw from this gadget up to the end of the list. NewModifyProp(..., count d5):
; only "count" gadgets starting from this one (spec §5).
intuition_NewModifyProp:
        movem.l d2-d7/a2-a3/a5,-(sp)
        move.l  d5,d7
        bra.s   mp_set
intuition_ModifyProp:
        movem.l d2-d7/a2-a3/a5,-(sp)
        moveq   #-1,d7
mp_set:
        move.l  a6,a5
        move.l  a1,a3
        move.l  a0,a2
        move.l  GG_SPECIALINFO(a2),a0
        move.w  d0,PI_FLAGS(a0)
        move.w  d1,PI_HPOT(a0)
        move.w  d2,PI_VPOT(a0)
        move.w  d3,PI_HBODY(a0)
        move.w  d4,PI_VBODY(a0)
        move.l  a3,d0
        beq.s   .mp_ret              ; without a window: nothing to redraw
        move.l  d7,d2
        bsr     gad_drawrev
.mp_ret:
        movem.l (sp)+,d2-d7/a2-a3/a5
        rts

; --- text gadgets ---------------------------------------------------------------------------------------------
; str_len(a0 = StringInfo) -> si_NumChars recomputed (text length, capped at MaxChars - 1), d0 = that number.
str_len:
        move.l  a1,-(sp)
        move.l  SI_BUFFER(a0),a1
        moveq   #0,d0
.sl_lp:
        tst.b   (a1)+
        beq.s   .sl_end
        addq.w  #1,d0
        bra.s   .sl_lp
.sl_end:
        move.w  SI_MAXCHARS(a0),d1
        subq.w  #1,d1
        bmi.s   .sl_set
        cmp.w   d1,d0
        bls.s   .sl_set
        move.w  d1,d0
.sl_set:
        move.w  d0,SI_NUMCHARS(a0)
        move.l  (sp)+,a1
        rts

; str_text(a3 = window, a2 = gadget, a5 = IntuitionBase): text area of the gadget (its rectangle) cleared then
; filled with the visible characters from si_DispPos, cursor inverted if it is active; the display position
; follows the cursor. RastPort pens and mode restored. Preserves d2-d7/a2-a6.
str_text:
        bsr     gad_nolayer
        bne     gad_skip
        bsr     it_unclip
        bsr     str_text_nc
        bra     it_reclip
str_text_nc:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  GG_SPECIALINFO(a2),d0
        beq     .st_ret
        move.l  d0,a4                ; a4 = StringInfo
        lea     -8(sp),sp
        move.l  a2,a0
        move.l  sp,a1
        bsr     gad_rect
        bsr     gad_rp               ; rectangle brought into the gadget's RastPort
        move.l  a4,a0
        bsr     str_len
        move.l  WD_RPORT(a3),a1
        moveq   #0,d6
        move.w  rp_TxWidth(a1),d6
        bne.s   .st_cw
        moveq   #8,d6
.st_cw:
        move.w  4(sp),d0             ; visible characters = width / character width
        sub.w   (sp),d0
        addq.w  #1,d0
        ext.l   d0
        divu    d6,d0
        move.w  d0,SI_DISPCOUNT(a4)
        cmp.l   IB_STRGAD(a5),a2
        bne.s   .st_disp
        move.w  SI_BUFFERPOS(a4),d1  ; active: cursor visible
        cmp.w   SI_DISPPOS(a4),d1
        bge.s   .st_d1
        move.w  d1,SI_DISPPOS(a4)
.st_d1:
        move.w  SI_DISPPOS(a4),d2
        add.w   d0,d2
        cmp.w   d2,d1
        blt.s   .st_disp
        sub.w   d0,d1
        addq.w  #1,d1
        move.w  d1,SI_DISPPOS(a4)
.st_disp:
        move.w  SI_DISPPOS(a4),d0
        cmp.w   SI_NUMCHARS(a4),d0
        ble.s   .st_dok
        clr.w   SI_DISPPOS(a4)
.st_dok:
        move.l  IB_GFXBASE(a5),a6
        bsr     gad_rpof
        move.l  a0,a3                ; a3 = RastPort of the gadget from now on
        move.b  rp_FgPen(a3),-(sp)
        move.b  rp_BgPen(a3),-(sp)
        move.b  rp_DrawMode(a3),-(sp)
        move.l  a3,a1
        moveq   #0,d0
        jsr     LVO_SETAPEN(a6)
        move.l  a3,a1
        moveq   #JAM1,d0
        jsr     LVO_SETDRMD(a6)
        movem.w 6(sp),d0-d3          ; x0 y0 x1 y1 (under the 3 saved values, 6 bytes)
        ext.l   d0
        ext.l   d1
        ext.l   d2
        ext.l   d3
        move.l  a3,a1
        jsr     LVO_RECTFILL(a6)
        move.l  a3,a1
        moveq   #1,d0
        jsr     LVO_SETAPEN(a6)
        move.l  a3,a1
        moveq   #0,d0
        jsr     LVO_SETBPEN(a6)
        move.l  a3,a1
        moveq   #JAM2,d0
        jsr     LVO_SETDRMD(a6)
        moveq   #0,d4
        move.w  SI_NUMCHARS(a4),d4
        sub.w   SI_DISPPOS(a4),d4    ; d4 = characters to write
        cmp.w   SI_DISPCOUNT(a4),d4
        ble.s   .st_n
        move.w  SI_DISPCOUNT(a4),d4
.st_n:
        tst.w   d4
        ble.s   .st_cur
        move.l  a3,a1
        move.w  6(sp),d0
        ext.l   d0
        move.w  8(sp),d1
        add.w   rp_TxBaseline(a3),d1
        ext.l   d1
        jsr     LVO_MOVE(a6)
        move.l  SI_BUFFER(a4),a0
        add.w   SI_DISPPOS(a4),a0
        move.l  d4,d0
        move.l  a3,a1
        jsr     LVO_TEXT(a6)
.st_cur:
        cmp.l   IB_STRGAD(a5),a2
        bne.s   .st_end
        move.l  a3,a1
        moveq   #COMPLEMENT,d0
        jsr     LVO_SETDRMD(a6)
        move.w  SI_BUFFERPOS(a4),d0
        sub.w   SI_DISPPOS(a4),d0
        mulu    d6,d0
        add.w   6(sp),d0
        move.w  d0,d2
        add.w   d6,d2
        subq.w  #1,d2
        move.w  8(sp),d1
        move.w  d1,d3
        add.w   rp_TxHeight(a3),d3
        subq.w  #1,d3
        cmp.w   12(sp),d3            ; bounded to the bottom of the gadget
        ble.s   .st_cy
        move.w  12(sp),d3
.st_cy:
        ext.l   d0
        ext.l   d1
        ext.l   d2
        ext.l   d3
        move.l  a3,a1
        jsr     LVO_RECTFILL(a6)
.st_end:
        move.l  a3,a1
        moveq   #0,d0
        move.b  (sp)+,d0
        jsr     LVO_SETDRMD(a6)
        move.l  a3,a1
        moveq   #0,d0
        move.b  (sp)+,d0
        jsr     LVO_SETBPEN(a6)
        move.l  a3,a1
        moveq   #0,d0
        move.b  (sp)+,d0
        jsr     LVO_SETAPEN(a6)
        lea     8(sp),sp
.st_ret:
        movem.l (sp)+,d2-d7/a2-a6
        rts

; str_activate(a3 = window, a2 = STRGADGET gadget, a5, d2.w = x of the click in the window | -1): the gadget becomes the
; active text gadget (the old one is deactivated), its text is copied into the undo buffer, the cursor is placed under
; the click (otherwise kept, bounded to the text); GADGETDOWN if it is GADGIMMEDIATE. Preserves d2-d7/a2-a6.
str_activate:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  GG_SPECIALINFO(a2),d0
        beq     .sa_ret
        move.l  d0,a4
        cmp.l   IB_STRGAD(a5),a2
        beq.s   .sa_same
        bsr     str_deact
        move.l  a4,a0
        bsr     str_len
        move.l  SI_UNDOBUFFER(a4),d0
        beq.s   .sa_noundo
        move.l  d0,a1
        move.l  SI_BUFFER(a4),a0
        move.w  SI_MAXCHARS(a4),d0
        bra.s   .sa_ux
.sa_ucp:
        move.b  (a0)+,(a1)+
.sa_ux:
        dbra    d0,.sa_ucp
.sa_noundo:
        move.w  SI_BUFFERPOS(a4),SI_UNDOPOS(a4)
.sa_same:
        tst.w   d2
        bmi.s   .sa_clamp
        lea     -8(sp),sp
        move.l  a2,a0
        move.l  sp,a1
        bsr     gad_rect
        move.w  d2,d0
        sub.w   (sp),d0
        lea     8(sp),sp
        ext.l   d0
        bpl.s   .sa_div
        moveq   #0,d0
.sa_div:
        move.l  WD_RPORT(a3),a0
        move.w  rp_TxWidth(a0),d1
        bne.s   .sa_cw
        moveq   #8,d1
.sa_cw:
        divu    d1,d0
        add.w   SI_DISPPOS(a4),d0
        move.w  d0,SI_BUFFERPOS(a4)
.sa_clamp:
        move.w  SI_BUFFERPOS(a4),d0
        bpl.s   .sa_c1
        clr.w   SI_BUFFERPOS(a4)
.sa_c1:
        cmp.w   SI_NUMCHARS(a4),d0
        ble.s   .sa_c2
        move.w  SI_NUMCHARS(a4),SI_BUFFERPOS(a4)
.sa_c2:
        move.l  a3,IB_STRWIN(a5)
        move.l  a2,IB_STRGAD(a5)
        bsr     str_text
        btst    #1,GG_ACTIVATION+1(a2)   ; GADGIMMEDIATE
        beq.s   .sa_ret
        moveq   #GADGETDOWN,d0
        moveq   #0,d1
        moveq   #0,d2
        moveq   #0,d3
        move.l  a2,a0
        bsr     gad_send
.sa_ret:
        movem.l (sp)+,d2-d7/a2-a6
        rts

; str_deact(a5): the active text gadget (if any) is no longer active; redrawn without the cursor. Preserves everything.
str_deact:
        movem.l d0-d1/a0-a3,-(sp)
        move.l  IB_STRGAD(a5),d0
        beq.s   .sd_ret
        move.l  d0,a2
        move.l  IB_STRWIN(a5),a3
        clr.l   IB_STRGAD(a5)
        bsr     str_text
.sd_ret:
        movem.l (sp)+,d0-d1/a0-a3
        rts

; str_clickout(a5, d4/d5 = click in the screen): a click outside the active text gadget deactivates it (no message).
; Preserves everything.
str_clickout:
        movem.l d0-d3/a0-a3,-(sp)
        move.l  IB_STRGAD(a5),d0
        beq.s   .co_ret
        move.l  d0,a0
        move.l  IB_STRWIN(a5),a3
        move.w  d4,d2
        sub.w   WD_LEFTEDGE(a3),d2
        move.w  d5,d3
        sub.w   WD_TOPEDGE(a3),d3
        bsr     gad_inside
        bne.s   .co_ret
        bsr     str_deact
.co_ret:
        movem.l (sp)+,d0-d3/a0-a3
        rts

; str_key(a5, d0.w = IT_KEYCODE + keycode, d4.w = qualifier): input task - a key for the active text
; gadget. Preserves a5.
str_key:
        move.l  IB_STRGAD(a5),d1
        beq     .sk_ret
        movem.l d2-d7/a2-a4,-(sp)
        move.l  d1,a2
        move.l  IB_STRWIN(a5),a3
        move.l  GG_SPECIALINFO(a2),a4
        and.w   #$007F,d0
        move.w  SI_BUFFERPOS(a4),d2  ; d2 = cursor, d3 = length
        move.w  SI_NUMCHARS(a4),d3
        move.l  SI_BUFFER(a4),a0
        cmp.w   #$4F,d0              ; left arrow
        bne.s   .sk_nl
        moveq   #0,d1
        move.w  d4,d1
        and.w   #KQ_SHIFT,d1
        bne.s   .sk_home
        tst.w   d2
        beq     .sk_done
        subq.w  #1,d2
        bra     .sk_pos
.sk_home:
        moveq   #0,d2
        bra     .sk_pos
.sk_nl:
        cmp.w   #$4E,d0              ; right arrow
        bne.s   .sk_nr
        move.w  d4,d1
        and.w   #KQ_SHIFT,d1
        bne.s   .sk_end
        cmp.w   d3,d2
        bge     .sk_done
        addq.w  #1,d2
        bra     .sk_pos
.sk_end:
        move.w  d3,d2
        bra     .sk_pos
.sk_nr:
        cmp.w   #$44,d0              ; Return
        beq     .sk_enter
        cmp.w   #$43,d0              ; Enter
        beq     .sk_enter
        cmp.w   #$41,d0              ; Backspace: deletes before the cursor
        bne.s   .sk_nbs
        tst.w   d2
        beq     .sk_done
        subq.w  #1,d2
        bra.s   .sk_del
.sk_nbs:
        cmp.w   #$46,d0              ; Del: deletes under the cursor
        bne.s   .sk_ndel
        cmp.w   d3,d2
        bge     .sk_done
.sk_del:
        lea     0(a0,d2.w),a1        ; text shifted one step to the left, NUL included
.sk_dl:
        move.b  1(a1),(a1)+
        bne.s   .sk_dl
        subq.w  #1,d3
        bra     .sk_pos
.sk_ndel:
        move.w  d4,d1
        jsr     kbd_cook             ; d0 = character (0: no character)
        and.w   #$00FF,d0
        beq     .sk_done
        btst    #KQB_RCOMMAND,d4
        beq.s   .sk_char
        or.b    #$20,d0              ; right Amiga: X clears, Q undoes
        cmp.b   #'x',d0
        bne.s   .sk_nx
        clr.b   (a0)
        moveq   #0,d2
        moveq   #0,d3
        clr.w   SI_DISPPOS(a4)
        bra.s   .sk_pos
.sk_nx:
        cmp.b   #'q',d0
        bne     .sk_done
        move.l  SI_UNDOBUFFER(a4),d0
        beq     .sk_done
        move.l  d0,a1
        move.w  SI_MAXCHARS(a4),d0
        bra.s   .sk_qx
.sk_qc:
        move.b  (a1)+,(a0)+
.sk_qx:
        dbra    d0,.sk_qc
        move.l  a4,a0
        bsr     str_len
        move.w  d0,d3
        move.w  SI_UNDOPOS(a4),d2
        cmp.w   d3,d2
        ble.s   .sk_pos
        move.w  d3,d2
        bra.s   .sk_pos
.sk_char:
        cmp.b   #$20,d0
        blo     .sk_done
        cmp.b   #$7F,d0
        beq     .sk_done
        btst    #3,GG_ACTIVATION(a2) ; LONGINT ($0800): digits and sign only
        beq.s   .sk_ins
        cmp.b   #'-',d0
        beq.s   .sk_ins
        cmp.b   #'0',d0
        blo     .sk_done
        cmp.b   #'9',d0
        bhi     .sk_done
.sk_ins:
        move.w  SI_MAXCHARS(a4),d1
        subq.w  #1,d1
        cmp.w   d1,d3
        bge     .sk_done             ; full
        lea     0(a0,d3.w),a1        ; shifts [cursor .. NUL] one step to the right
        move.w  d3,d1
        sub.w   d2,d1                ; bytes to shift, NUL included: d1 + 1
.sk_il:
        move.b  (a1),1(a1)
        subq.l  #1,a1
        dbra    d1,.sk_il
        move.b  d0,0(a0,d2.w)
        addq.w  #1,d2
        addq.w  #1,d3
.sk_pos:
        move.w  d2,SI_BUFFERPOS(a4)
        move.w  d3,SI_NUMCHARS(a4)
        bsr     str_text
.sk_done:
        movem.l (sp)+,d2-d7/a2-a4
.sk_ret:
        rts
.sk_enter:
        btst    #3,GG_ACTIVATION(a2) ; LONGINT: signed decimal value in si_LongInt
        beq.s   .sk_up
        moveq   #0,d1                ; d1 = value, d2 = negative
        moveq   #0,d2
        cmp.b   #'-',(a0)
        bne.s   .sk_dg
        moveq   #1,d2
        addq.l  #1,a0
.sk_dg:
        moveq   #0,d0
        move.b  (a0)+,d0
        sub.b   #'0',d0
        bcs.s   .sk_dend
        cmp.b   #9,d0
        bhi.s   .sk_dend
        add.l   d1,d1                ; x 10 = x 2 + x 8
        move.l  d1,d3
        lsl.l   #2,d3
        add.l   d3,d1
        add.l   d0,d1
        bra.s   .sk_dg
.sk_dend:
        tst.w   d2
        beq.s   .sk_pl
        neg.l   d1
.sk_pl:
        move.l  d1,SI_LONGINT(a4)
.sk_up:
        bsr     str_deact
        btst    #0,GG_ACTIVATION+1(a2)   ; RELVERIFY
        beq.s   .sk_done
        moveq   #GADGETUP,d0
        moveq   #0,d1
        moveq   #0,d2
        moveq   #0,d3
        move.l  a2,a0
        bsr     gad_send
        bra.s   .sk_done

; ActivateGadget(gadget a0, window a1, requester a2) -> d0 = TRUE if an enabled (not disabled) text gadget of this
; window became the active gadget (cursor kept), FALSE otherwise.
intuition_ActivateGadget:
        movem.l d2/a2-a3/a5,-(sp)
        move.l  a6,a5
        move.l  a0,a2
        move.l  a1,a3
        moveq   #0,d0
        move.l  a2,d1
        beq.s   .ag_ret
        move.l  a3,d1
        beq.s   .ag_ret
        move.w  GG_GADGETTYPE(a2),d1
        and.w   #GTYP_MASK,d1
        cmp.w   #STRGADGET,d1
        bne.s   .ag_ret
        btst    #0,GG_FLAGS(a2)      ; GADGDISABLED
        bne.s   .ag_ret
        moveq   #-1,d2
        bsr     str_activate
        moveq   #1,d0
.ag_ret:
        movem.l (sp)+,d2/a2-a3/a5
        rts

; ------------------------------------------------------------------------------------------------------------------
; AddGadget(window a0, gadget a1, position d0) -> d0 = effective position. AddGList(window a0, gadget a1, position
; d0, count d1 (-1 = the whole chain), requester a2): the gadget chain is inserted at the position (-1 = at the
; end) in wd_FirstGadget. Nothing is redrawn (RefreshGadgets / RefreshGList).
intuition_AddGadget:
        moveq   #1,d1
intuition_AddGList:
        movem.l d2/a2-a3/a6,-(sp)
        move.l  a0,a3                ; a3 = window
        move.l  a1,a2                ; a2 = last gadget of the chain to insert
.ag_last:
        subq.l  #1,d1
        beq.s   .ag_got
        tst.l   GG_NEXTGADGET(a2)
        beq.s   .ag_got
        move.l  GG_NEXTGADGET(a2),a2
        bra.s   .ag_last
.ag_got:
        move.l  ($4).w,a6
        movem.l d0/a0-a1,-(sp)
        jsr     LVO_FORBID(a6)
        movem.l (sp)+,d0/a0-a1
        lea     WD_FIRSTGADGET(a0),a0    ; previous link (the link is at the start of a gadget)
        moveq   #0,d2
.ag_pos:
        cmp.l   d0,d2
        bhs.s   .ag_ins              ; position reached (-1 = never: up to the end)
        tst.l   (a0)
        beq.s   .ag_ins
        move.l  (a0),a0
        addq.l  #1,d2
        bra.s   .ag_pos
.ag_ins:
        move.l  (a0),GG_NEXTGADGET(a2)
        move.l  a1,(a0)
        jsr     LVO_PERMIT(a6)
        bsr     gad_propinit         ; borders of the proportional gadgets that entered the window
        move.l  d2,d0
        movem.l (sp)+,d2/a2-a3/a6
        rts

; RemoveGadget(window a0, gadget a1) -> d0 = position it occupied | -1. RemoveGList(window a0, gadget a1, count
; d0 (-1 = up to the end)): the gadgets leave the list, the last one removed is terminated by NULL.
intuition_RemoveGadget:
        moveq   #1,d0
intuition_RemoveGList:
        movem.l d2/a2/a6,-(sp)
        move.l  a6,-(sp)
        move.l  d0,d1                ; d1 = count
        move.l  ($4).w,a6
        movem.l d1/a0-a1,-(sp)
        jsr     LVO_FORBID(a6)
        movem.l (sp)+,d1/a0-a1
        lea     WD_FIRSTGADGET(a0),a0
        moveq   #0,d2
.rg_find:
        move.l  (a0),d0
        beq.s   .rg_none
        cmp.l   a1,d0
        beq.s   .rg_found
        move.l  d0,a0
        addq.l  #1,d2
        bra.s   .rg_find
.rg_found:
        move.l  a1,a2                ; a2 = last removed
.rg_last:
        subq.l  #1,d1
        beq.s   .rg_cut
        tst.l   GG_NEXTGADGET(a2)
        beq.s   .rg_cut
        move.l  GG_NEXTGADGET(a2),a2
        bra.s   .rg_last
.rg_cut:
        move.l  GG_NEXTGADGET(a2),(a0)
        clr.l   GG_NEXTGADGET(a2)
        move.l  a1,a0
        move.l  (sp),a6              ; IntuitionBase
        bsr     gad_forget
        move.l  ($4).w,a6
        jsr     LVO_PERMIT(a6)
        move.l  d2,d0
        bra.s   .rg_ret
.rg_none:
        jsr     LVO_PERMIT(a6)
        moveq   #-1,d0
.rg_ret:
        addq.l  #4,sp
        movem.l (sp)+,d2/a2/a6
        rts

; RefreshGadgets(gadgets a0, window a1, requester a2): redraws from this gadget up to the end of the list.
; RefreshGList(gadgets a0, window a1, requester a2, count d0): at most count gadgets (-1 = all).
intuition_RefreshGadgets:
        moveq   #-1,d0
intuition_RefreshGList:
        movem.l d2/a2-a3/a5,-(sp)
        move.l  a6,a5
        move.l  a1,a3
        move.l  a0,a2
        move.l  d0,d2
        cmp.l   WD_FIRSTGADGET(a3),a2    ; from the head of the list: the system gadgets (at the head in intuition 1.3)
        seq     -(sp)                    ; are redrawn last, on top
        bsr     gad_drawrev
        tst.b   (sp)+
        beq.s   .rf_ret
        btst    #3,WD_FLAGS+2(a3)        ; (none on a BORDERLESS window)
        bne.s   .rf_ret
        jsr     wn_sysgads
.rf_ret:
        movem.l (sp)+,d2/a2-a3/a5
        rts

; OnGadget(gadget a0, window a1, requester a2) / OffGadget(...): the gadget becomes enabled again / is disabled, then it
; is redrawn.
intuition_OnGadget:
        bclr    #0,GG_FLAGS(a0)
        bra.s   gad_onoff
intuition_OffGadget:
        bset    #0,GG_FLAGS(a0)
        move.l  a0,-(sp)
        bsr     gad_forget
        move.l  (sp)+,a0
gad_onoff:
        moveq   #1,d0
        bra.s   intuition_RefreshGList

; DrawBorder(rp a0, border a1, x d0, y d1): each Border of the chain, polyline of Count points (XY pairs)
; offset by (x + LeftEdge, y + TopEdge), in pen FrontPen in mode DrawMode. RastPort pens and mode left
; intact, as in 1.3 (probed: tests/itextstate.s).
intuition_DrawBorder:
        movem.l d2-d7/a2-a6,-(sp)
        move.b  rp_FgPen(a0),-(sp)
        move.b  rp_BgPen(a0),-(sp)
        move.b  rp_DrawMode(a0),-(sp)
        move.l  IB_GFXBASE(a6),a6
        move.l  a0,a2
        move.l  a1,a3
        move.w  d0,d6
        move.w  d1,d7
.db_lp:
        move.l  a3,d0
        beq.s   .db_ret
        move.l  a2,a1
        moveq   #0,d0
        move.b  BD_FRONTPEN(a3),d0
        jsr     LVO_SETAPEN(a6)
        move.l  a2,a1
        moveq   #0,d0
        move.b  BD_DRAWMODE(a3),d0
        jsr     LVO_SETDRMD(a6)
        moveq   #0,d5
        move.b  BD_COUNT(a3),d5
        subq.w  #1,d5
        bmi.s   .db_next
        move.l  BD_XY(a3),a4
        move.w  d6,d4
        add.w   BD_LEFTEDGE(a3),d4   ; d4 = x origin
        move.w  d7,d3
        add.w   BD_TOPEDGE(a3),d3    ; d3 = y origin
        bsr.s   .db_pt
        jsr     LVO_MOVE(a6)
        bra.s   .db_nx
.db_seg:
        bsr.s   .db_pt
        jsr     LVO_DRAW(a6)
.db_nx:
        dbra    d5,.db_seg
.db_next:
        move.l  BD_NEXTBORDER(a3),a3
        bra.s   .db_lp
.db_ret:
        move.b  (sp)+,rp_DrawMode(a2)
        move.b  (sp)+,rp_BgPen(a2)
        move.b  (sp)+,rp_FgPen(a2)
        movem.l (sp)+,d2-d7/a2-a6
        rts
.db_pt:                              ; next point (a4)+ -> absolute d0/d1, a1 = rp
        move.w  (a4)+,d0
        add.w   d4,d0
        ext.l   d0
        move.w  (a4)+,d1
        add.w   d3,d1
        ext.l   d1
        move.l  a2,a1
        rts
