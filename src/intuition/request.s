; src/intuition/request.s - intuition.library: requesters (spec docs/analysis/intuition-requesters-v34.md §1-§4).
; Request puts up a requester in a window: a LAYERSMART layer in front of the window's layer (or in front of the
; previous requester), at corner LeftEdge/TopEdge (inside a GIMMEZEROZERO window), clipped to the window; background in
; pen BackFill, ReqBorder, ReqText, gadgets (or ImageBMap copied if PREDRAWN). While a requester is up, only its
; gadgets respond (gadgets.s) and, without NOISYREQ, the window no longer receives keys, buttons, movements or menus
; (screens.s). REQSET when put up, REQCLEAR at the end; ENDGADGET or EndRequest remove it. The requester layers
; follow the window when it moves or changes depth.
; IMPLEMENTATION track ("clean"): AutoDocs intuition + public structures + spec. NO ROM reading.

                include "exec.i"
                include "graphics.i"
                include "intuition.i"

                xdef    intuition_Request
                xdef    intuition_EndRequest
                xdef    intuition_InitRequester
                xdef    intuition_SetDMRequest
                xdef    intuition_ClearDMRequest
                xdef    rq_endgadget
                xdef    rq_move
                xdef    rq_restack
                xdef    rq_closeall
                xref    rq_origin            ; gadgets.s
                xref    gad_propinitl
                xref    gad_drawrev
                xref    gad_forget
                xref    intuition_DrawBorder
                xref    intuition_PrintIText
                xref    wn_sendmsg           ; screens.s
                xref    it_refresh

; Request(requester a0, window a1) -> d0 = TRUE; FALSE if the layer could not be created (nothing is linked).
intuition_Request:
        movem.l d2-d7/a2-a5,-(sp)
        move.l  a6,a5
        move.l  a0,a2
        move.l  a1,a3
        move.l  a3,RQ_RWINDOW(a2)
        clr.l   RQ_REQLAYER(a2)
        move.l  WD_FIRSTREQUEST(a3),RQ_OLDERREQ(a2)
        bsr     rq_mklayer
        beq     .rq_fail
        move.l  RQ_REQGADGET(a2),d0
.rq_mark:
        tst.l   d0
        beq.s   .rq_chain
        move.l  d0,a0
        or.w    #REQGADGET,GG_GADGETTYPE(a0)
        move.l  GG_NEXTGADGET(a0),d0
        bra.s   .rq_mark
.rq_chain:
        move.l  ($4).w,a6
        jsr     LVO_FORBID(a6)       ; the input task reads the chain
        move.l  a2,WD_FIRSTREQUEST(a3)
        addq.w  #1,WD_REQCOUNT(a3)
        or.l    #INREQUEST,WD_FLAGS(a3)
        jsr     LVO_PERMIT(a6)
        bsr     rq_render
        move.l  #REQSET,d0
        bsr     rq_send
        moveq   #-1,d0
        bra.s   .rq_ret
.rq_fail:
        moveq   #0,d0
.rq_ret:
        move.l  a5,a6
        movem.l (sp)+,d2-d7/a2-a5
        rts

; rq_mklayer(a2 = requester, a3 = window, a5 = IntuitionBase) -> Z = 0 if successful: layer created (or none if the
; size clipped to the window is zero: also a success), placed in front of the previous requester, otherwise in front of
; the window; RastPort set to the screen font. Clobbers d0-d7/a0/a1/a4/a6.
rq_mklayer:
        move.l  a2,a0
        jsr     rq_origin            ; d0/d1 = corner in the window
        move.w  RQ_WIDTH(a2),d2      ; size clipped to the available room
        move.w  RQ_HEIGHT(a2),d3
        btst    #2,WD_FLAGS+2(a3)    ; GIMMEZEROZERO: up to the inner size
        beq.s   .ml_win
        tst.l   WD_BORDERRPORT(a3)
        beq.s   .ml_win
        move.w  WD_GZZWIDTH(a3),d4
        move.w  WD_GZZHEIGHT(a3),d5
        moveq   #0,d6
        move.b  WD_BORDERLEFT(a3),d6
        add.w   d6,d4
        move.b  WD_BORDERTOP(a3),d6
        add.w   d6,d5
        bra.s   .ml_clip
.ml_win:
        move.w  WD_WIDTH(a3),d4      ; otherwise up to the right and bottom borders
        moveq   #0,d6
        move.b  WD_BORDERRIGHT(a3),d6
        sub.w   d6,d4
        move.w  WD_HEIGHT(a3),d5
        move.b  WD_BORDERBOTTOM(a3),d6
        sub.w   d6,d5
.ml_clip:
        sub.w   d0,d4                ; room to the right / below the corner
        sub.w   d1,d5
        cmp.w   d4,d2
        ble.s   .ml_w
        move.w  d4,d2
.ml_w:
        cmp.w   d5,d3
        ble.s   .ml_h
        move.w  d5,d3
.ml_h:
        tst.w   d2
        ble     .ml_none
        tst.w   d3
        ble     .ml_none
        add.w   WD_LEFTEDGE(a3),d0   ; bounds at the screen
        add.w   WD_TOPEDGE(a3),d1
        add.w   d0,d2
        subq.w  #1,d2
        add.w   d1,d3
        subq.w  #1,d3
        ext.l   d0
        ext.l   d1
        ext.l   d2
        ext.l   d3
        move.l  WD_WSCREEN(a3),a4
        move.l  WD_WLAYER(a3),a1     ; a1 = layer to be placed in front of: previous requester, otherwise window
        move.l  RQ_OLDERREQ(a2),d4
        beq.s   .ml_other
        move.l  d4,a0
        move.l  RQ_REQLAYER(a0),d4
        beq.s   .ml_other
        move.l  d4,a1
.ml_other:
        move.l  a2,-(sp)
        move.l  a1,-(sp)
        lea     SC_LAYERINFO(a4),a0
        lea     SC_BITMAP(a4),a1
        moveq   #IL_SMART,d4
        suba.l  a2,a2
        move.l  IB_LAYERSBASE(a5),a6
        move.l  (sp),d5
        cmp.l   SC_LAYERINFO(a4),d5  ; (Layer_Info.top_layer: offset 0) already frontmost: a single operation
        bne.s   .ml_behind
        jsr     LVO_CREATEUPFRONTLAYER(a6)
        addq.l  #4,sp
        bra.s   .ml_made
.ml_behind:
        jsr     LVO_CREATEBEHINDLAYER(a6)    ; created behind, then placed in front (spec §2.2)
        move.l  (sp)+,a1
        tst.l   d0
        beq.s   .ml_made
        move.l  d0,-(sp)
        move.l  d0,a0
        jsr     LVO_MOVELAYERINFRONTOF(a6)
        move.l  (sp)+,d0
.ml_made:
        move.l  (sp)+,a2
        tst.l   d0
        beq.s   .ml_ret              ; Z = 1: failure
        move.l  d0,RQ_REQLAYER(a2)
        move.l  d0,a0
        move.l  a3,IL_WINDOW(a0)
        move.l  RQ_REQLAYER(a2),a1   ; screen font
        move.l  IL_RP(a1),a1
        move.l  SC_RASTPORT+rp_Font(a4),a0
        move.l  IB_GFXBASE(a5),a6
        jsr     LVO_SETFONT(a6)
.ml_none:
        moveq   #1,d0                ; Z = 0
.ml_ret:
        rts

; rq_render(a2 = requester, a3 = window, a5 = IntuitionBase): REQACTIVE; PropInfo of its gadgets; in its layer,
; ImageBMap copied (PREDRAWN) or BackFill background + ReqBorder + ReqText; then its gadgets (in reverse order, like a
; window). Without a layer: nothing is drawn. Clobbers d0-d7/a0/a1/a4/a6.
rq_render:
        or.w    #REQACTIVE,RQ_FLAGS(a2)
        move.l  RQ_REQLAYER(a2),d0
        beq     .rr_ret
        move.l  d0,a4
        move.l  IL_RP(a4),a4         ; a4 = RastPort of the layer
        move.l  a2,-(sp)
        move.l  RQ_REQGADGET(a2),a2
        jsr     gad_propinitl
        move.l  (sp)+,a2
        move.l  IB_GFXBASE(a5),a6
        btst    #1,RQ_FLAGS+1(a2)    ; PREDRAWN
        beq.s   .rr_draw
        move.l  RQ_IMAGEBMAP(a2),d0
        beq.s   .rr_gads
        move.l  d0,a0
        moveq   #0,d0
        moveq   #0,d1
        move.l  a4,a1
        moveq   #0,d2
        moveq   #0,d3
        moveq   #0,d4
        move.w  RQ_WIDTH(a2),d4
        moveq   #0,d5
        move.w  RQ_HEIGHT(a2),d5
        move.l  #$C0,d6
        jsr     LVO_BLTBITMAPRASTPORT(a6)
        bra.s   .rr_gads
.rr_draw:
        move.l  a4,a1
        moveq   #0,d0
        move.b  RQ_BACKFILL(a2),d0
        jsr     LVO_SETAPEN(a6)
        move.l  a4,a1
        moveq   #JAM1,d0
        jsr     LVO_SETDRMD(a6)
        move.l  a4,a1
        moveq   #0,d0
        moveq   #0,d1
        moveq   #0,d2
        move.w  RQ_WIDTH(a2),d2
        subq.l  #1,d2
        moveq   #0,d3
        move.w  RQ_HEIGHT(a2),d3
        subq.l  #1,d3
        jsr     LVO_RECTFILL(a6)
        move.l  a5,a6
        move.l  RQ_REQBORDER(a2),d0
        beq.s   .rr_text
        move.l  a4,a0
        move.l  d0,a1
        moveq   #0,d0
        moveq   #0,d1
        jsr     intuition_DrawBorder
.rr_text:
        move.l  RQ_REQTEXT(a2),d0
        beq.s   .rr_gads
        move.l  a5,a6
        move.l  a4,a0
        move.l  d0,a1
        moveq   #0,d0
        moveq   #0,d1
        jsr     intuition_PrintIText
.rr_gads:
        move.l  a2,-(sp)
        move.l  RQ_REQGADGET(a2),a2
        moveq   #-1,d2
        jsr     gad_drawrev
        move.l  (sp)+,a2
.rr_ret:
        rts

; rq_send(a3 = window, d0 = REQSET / REQCLEAR): IDCMP message to the window (if it asked for it), under Forbid: the
; input task draws from the same message pool. Preserves d2-d7/a2-a5.
rq_send:
        movem.l d2-d3/d6,-(sp)
        move.l  d0,d2
        move.l  ($4).w,a6
        jsr     LVO_FORBID(a6)
        move.l  d2,d0
        moveq   #0,d1
        moveq   #0,d2
        moveq   #0,d3
        jsr     wn_sendmsg
        move.l  ($4).w,a6
        jsr     LVO_PERMIT(a6)
        movem.l (sp)+,d2-d3/d6
        rts

; rq_remove(a2 = requester, a3 = window, a5 = IntuitionBase) -> Z = 1 if it was not in the window's chain
; (nothing is done); otherwise: no longer REQACTIVE, removed from the chain, its gadgets forgotten if they were held,
; its layer deleted (layers repairs the uncovered area). Clobbers d0/d1/a0/a1/a6.
rq_remove:
        and.w   #~REQACTIVE,RQ_FLAGS(a2)
        move.l  ($4).w,a6
        jsr     LVO_FORBID(a6)
        lea     WD_FIRSTREQUEST(a3),a0   ; RQ_OLDERREQ is at offset 0: the head is handled like a link
.rm_find:
        move.l  (a0),d0
        beq.s   .rm_absent
        cmp.l   a2,d0
        beq.s   .rm_found
        move.l  d0,a0
        bra.s   .rm_find
.rm_absent:
        jsr     LVO_PERMIT(a6)
        moveq   #0,d0                ; Z = 1
        rts
.rm_found:
        move.l  RQ_OLDERREQ(a2),(a0)
        jsr     LVO_PERMIT(a6)
        move.l  RQ_REQGADGET(a2),d1
        move.l  a5,a6
.rm_forget:
        tst.l   d1
        beq.s   .rm_layer
        move.l  d1,a0
        jsr     gad_forget
        move.l  GG_NEXTGADGET(a0),d1
        bra.s   .rm_forget
.rm_layer:
        move.l  RQ_REQLAYER(a2),d0
        beq.s   .rm_ok
        clr.l   RQ_REQLAYER(a2)
        move.l  d0,a1
        suba.l  a0,a0
        move.l  IB_LAYERSBASE(a5),a6
        jsr     LVO_DELETELAYER(a6)
.rm_ok:
        moveq   #1,d0                ; Z = 0
        rts

; rq_count(a3 = window): one requester less; at zero, INREQUEST cleared. Preserves everything but d0; Z = 1 if zero.
rq_count:
        subq.w  #1,WD_REQCOUNT(a3)
        bgt.s   .rc_ret
        clr.w   WD_REQCOUNT(a3)
        and.l   #~INREQUEST,WD_FLAGS(a3)
        moveq   #0,d0                ; Z = 1
.rc_ret:
        rts

; EndRequest(requester a0, window a1): removed (nothing if it is not in the window); at the last requester, REQCLEAR
; and INREQUEST cleared; the window is repaired.
intuition_EndRequest:
        movem.l d2-d7/a2-a5,-(sp)
        move.l  a6,a5
        move.l  a0,a2
        move.l  a1,a3
        bsr     rq_remove
        beq.s   .er_ret
        bsr     rq_count
        bne.s   .er_fix
        move.l  #REQCLEAR,d0
        bsr     rq_send
.er_fix:
        move.l  WD_WSCREEN(a3),a4
        jsr     it_refresh
.er_ret:
        move.l  a5,a6
        movem.l (sp)+,d2-d7/a2-a5
        rts

; rq_endgadget(a3 = window, a5 = IntuitionBase): input task, release of an ENDGADGET of the most recent
; requester: it is removed, REQCLEAR (every time), one less, window repaired (spec §3.3). Preserves d2-d7/a2-a5.
rq_endgadget:
        movem.l d2-d7/a2-a5,-(sp)
        move.l  WD_FIRSTREQUEST(a3),d0
        beq.s   .eg_ret
        move.l  d0,a2
        bsr     rq_remove
        beq.s   .eg_ret
        move.l  #REQCLEAR,d0
        bsr     rq_send
        bsr     rq_count
        move.l  WD_WSCREEN(a3),a4
        jsr     it_refresh
.eg_ret:
        movem.l (sp)+,d2-d7/a2-a5
        rts

; rq_closeall(a3 = window, a5 = IntuitionBase): CloseWindow - the requesters still up are removed (their layers
; must not outlive the window). Preserves d2-d7/a2-a5.
rq_closeall:
        movem.l d2-d7/a2-a5,-(sp)
.ca_lp:
        move.l  WD_FIRSTREQUEST(a3),d0
        beq.s   .ca_ret
        move.l  d0,a2
        bsr     rq_remove
        bsr     rq_count
        bra.s   .ca_lp
.ca_ret:
        movem.l (sp)+,d2-d7/a2-a5
        rts

; rq_move(a3 = window, d2.l/d3.l = displacement, a5 = IntuitionBase): MoveWindow - the requester layers follow.
; Preserves d2-d7/a2-a5.
rq_move:
        movem.l a2/a6,-(sp)
        move.l  IB_LAYERSBASE(a5),a6
        move.l  WD_FIRSTREQUEST(a3),a2
.mv_lp:
        cmpa.w  #0,a2
        beq.s   .mv_ret
        move.l  RQ_REQLAYER(a2),d0
        beq.s   .mv_next
        move.l  d0,a1
        suba.l  a0,a0
        move.l  d2,d0
        move.l  d3,d1
        jsr     LVO_MOVELAYER(a6)
.mv_next:
        move.l  RQ_OLDERREQ(a2),a2
        bra.s   .mv_lp
.mv_ret:
        movem.l (sp)+,a2/a6
        rts

; rq_restack(a3 = window, a5 = IntuitionBase): after a depth change of the window, its requesters
; come back just in front of it, from oldest to most recent. Preserves d2-d7/a2-a5.
rq_restack:
        movem.l d2-d3/a2/a6,-(sp)
        move.l  IB_LAYERSBASE(a5),a6
        move.l  WD_WLAYER(a3),d2     ; d2 = layer in front of which to place the next one
        suba.l  a2,a2                ; a2 = last placed requester (0: none)
.rs_pass:
        move.l  WD_FIRSTREQUEST(a3),a0   ; look for the one whose older requester is a2 (the next one towards the head)
        moveq   #0,d3
.rs_find:
        cmpa.w  #0,a0
        beq.s   .rs_got
        cmp.l   RQ_OLDERREQ(a0),a2
        bne.s   .rs_nx
        move.l  a0,d3
.rs_nx:
        move.l  RQ_OLDERREQ(a0),a0
        bra.s   .rs_find
.rs_got:
        tst.l   d3
        beq.s   .rs_ret
        move.l  d3,a2
        move.l  RQ_REQLAYER(a2),d0
        beq.s   .rs_pass
        move.l  d0,a0
        move.l  d2,a1
        move.l  d0,d2
        jsr     LVO_MOVELAYERINFRONTOF(a6)
        bra.s   .rs_pass
.rs_ret:
        movem.l (sp)+,d2-d3/a2/a6
        rts

; InitRequester(requester a0): the 112 bytes set to zero.
intuition_InitRequester:
        moveq   #RQ_SIZEOF/4-1,d0
.ir_lp:
        clr.l   (a0)+
        dbra    d0,.ir_lp
        rts

; SetDMRequest(window a0, requester a1) -> d0 = TRUE; FALSE (nothing changed) if the current DMRequest is displayed.
; ClearDMRequest(window a0): the same with NULL.
intuition_ClearDMRequest:
        suba.l  a1,a1
intuition_SetDMRequest:
        move.l  a2,-(sp)
        move.l  WD_DMREQUEST(a0),d0
        beq.s   .dm_set
        move.l  d0,a2
        btst    #5,RQ_FLAGS(a2)      ; REQACTIVE ($2000)
        bne.s   .dm_no
.dm_set:
        move.l  a1,WD_DMREQUEST(a0)
        moveq   #-1,d0
        bra.s   .dm_ret
.dm_no:
        moveq   #0,d0
.dm_ret:
        move.l  (sp)+,a2
        rts
