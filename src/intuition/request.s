; src/intuition/request.s — intuition.library : requesters (spec docs/analysis/intuition-requesters-v34.md §1-§4).
; Request pose un requester dans une fenêtre : une couche LAYERSMART devant celle de la fenêtre (ou devant le requester
; précédent), au coin LeftEdge/TopEdge (intérieur d'une fenêtre GIMMEZEROZERO), rognée à la fenêtre ; fond au stylo
; BackFill, ReqBorder, ReqText, gadgets (ou ImageBMap recopié si PREDRAWN). Tant qu'un requester est là, seuls ses
; gadgets répondent (gadgets.s) et, sans NOISYREQ, la fenêtre ne reçoit plus touches, boutons, mouvements ni menus
; (screens.s). REQSET à la pose, REQCLEAR à la fin ; ENDGADGET ou EndRequest le retirent. Les couches des requesters
; suivent la fenêtre quand elle bouge ou change de profondeur.
; Piste IMPLÉMENTATION (« clean ») : AutoDocs intuition + structures publiques + spec. AUCUNE lecture ROM.

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

; Request(requester a0, fenêtre a1) -> d0 = TRUE ; FALSE si la couche n'a pu être créée (rien n'est chaîné).
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
        jsr     LVO_FORBID(a6)       ; la tâche d'entrée lit la chaîne
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

; rq_mklayer(a2 = requester, a3 = fenêtre, a5 = IntuitionBase) -> Z = 0 si réussi : couche créée (ou aucune si la
; taille rognée à la fenêtre est nulle : réussite aussi), placée devant le requester précédent, sinon devant la
; fenêtre ; RastPort à la police de l'écran. Clobbe d0-d7/a0/a1/a4/a6.
rq_mklayer:
        move.l  a2,a0
        jsr     rq_origin            ; d0/d1 = coin dans la fenêtre
        move.w  RQ_WIDTH(a2),d2      ; taille rognée à la place disponible
        move.w  RQ_HEIGHT(a2),d3
        btst    #2,WD_FLAGS+2(a3)    ; GIMMEZEROZERO : jusqu'à la taille intérieure
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
        move.w  WD_WIDTH(a3),d4      ; sinon jusqu'aux bordures droite et basse
        moveq   #0,d6
        move.b  WD_BORDERRIGHT(a3),d6
        sub.w   d6,d4
        move.w  WD_HEIGHT(a3),d5
        move.b  WD_BORDERBOTTOM(a3),d6
        sub.w   d6,d5
.ml_clip:
        sub.w   d0,d4                ; place à droite / en bas du coin
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
        add.w   WD_LEFTEDGE(a3),d0   ; bornes à l'écran
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
        move.l  WD_WLAYER(a3),a1     ; a1 = couche devant laquelle se placer : requester précédent, sinon fenêtre
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
        cmp.l   SC_LAYERINFO(a4),d5  ; (Layer_Info.top_layer : offset 0) déjà tout devant : une seule opération
        bne.s   .ml_behind
        jsr     LVO_CREATEUPFRONTLAYER(a6)
        addq.l  #4,sp
        bra.s   .ml_made
.ml_behind:
        jsr     LVO_CREATEBEHINDLAYER(a6)    ; créée derrière, puis placée devant (spec §2.2)
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
        beq.s   .ml_ret              ; Z = 1 : échec
        move.l  d0,RQ_REQLAYER(a2)
        move.l  d0,a0
        move.l  a3,IL_WINDOW(a0)
        move.l  RQ_REQLAYER(a2),a1   ; police de l'écran
        move.l  IL_RP(a1),a1
        move.l  SC_RASTPORT+rp_Font(a4),a0
        move.l  IB_GFXBASE(a5),a6
        jsr     LVO_SETFONT(a6)
.ml_none:
        moveq   #1,d0                ; Z = 0
.ml_ret:
        rts

; rq_render(a2 = requester, a3 = fenêtre, a5 = IntuitionBase) : REQACTIVE ; PropInfo de ses gadgets ; dans sa couche,
; ImageBMap recopié (PREDRAWN) ou fond BackFill + ReqBorder + ReqText ; puis ses gadgets (à rebours, comme une
; fenêtre). Sans couche : rien n'est dessiné. Clobbe d0-d7/a0/a1/a4/a6.
rq_render:
        or.w    #REQACTIVE,RQ_FLAGS(a2)
        move.l  RQ_REQLAYER(a2),d0
        beq     .rr_ret
        move.l  d0,a4
        move.l  IL_RP(a4),a4         ; a4 = RastPort de la couche
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

; rq_send(a3 = fenêtre, d0 = REQSET / REQCLEAR) : message IDCMP à la fenêtre (si elle l'a demandé), sous Forbid : la
; tâche d'entrée puise dans la même réserve de messages. Préserve d2-d7/a2-a5.
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

; rq_remove(a2 = requester, a3 = fenêtre, a5 = IntuitionBase) -> Z = 1 s'il n'était pas dans la chaîne de la fenêtre
; (rien n'est fait) ; sinon : plus REQACTIVE, retiré de la chaîne, ses gadgets oubliés s'ils étaient tenus, sa couche
; supprimée (layers répare la zone découverte). Clobbe d0/d1/a0/a1/a6.
rq_remove:
        and.w   #~REQACTIVE,RQ_FLAGS(a2)
        move.l  ($4).w,a6
        jsr     LVO_FORBID(a6)
        lea     WD_FIRSTREQUEST(a3),a0   ; RQ_OLDERREQ est à l'offset 0 : la tête se traite comme un maillon
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

; rq_count(a3 = fenêtre) : un requester de moins ; à zéro, INREQUEST effacé. Préserve tout sauf d0 ; Z = 1 si zéro.
rq_count:
        subq.w  #1,WD_REQCOUNT(a3)
        bgt.s   .rc_ret
        clr.w   WD_REQCOUNT(a3)
        and.l   #~INREQUEST,WD_FLAGS(a3)
        moveq   #0,d0                ; Z = 1
.rc_ret:
        rts

; EndRequest(requester a0, fenêtre a1) : retiré (rien s'il n'est pas dans la fenêtre) ; au dernier requester, REQCLEAR
; et INREQUEST effacé ; la fenêtre est réparée.
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

; rq_endgadget(a3 = fenêtre, a5 = IntuitionBase) : tâche d'entrée, relâchement d'un ENDGADGET du requester le plus
; récent : il est retiré, REQCLEAR (à chaque fois), un de moins, fenêtre réparée (spec §3.3). Préserve d2-d7/a2-a5.
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

; rq_closeall(a3 = fenêtre, a5 = IntuitionBase) : CloseWindow — les requesters encore posés sont retirés (leurs couches
; ne doivent pas survivre à la fenêtre). Préserve d2-d7/a2-a5.
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

; rq_move(a3 = fenêtre, d2.l/d3.l = déplacement, a5 = IntuitionBase) : MoveWindow — les couches des requesters suivent.
; Préserve d2-d7/a2-a5.
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

; rq_restack(a3 = fenêtre, a5 = IntuitionBase) : après un changement de profondeur de la fenêtre, ses requesters
; reviennent juste devant elle, du plus ancien au plus récent. Préserve d2-d7/a2-a5.
rq_restack:
        movem.l d2-d3/a2/a6,-(sp)
        move.l  IB_LAYERSBASE(a5),a6
        move.l  WD_WLAYER(a3),d2     ; d2 = couche devant laquelle placer le suivant
        suba.l  a2,a2                ; a2 = dernier requester placé (0 : aucun)
.rs_pass:
        move.l  WD_FIRSTREQUEST(a3),a0   ; cherche celui dont le plus ancien est a2 (le suivant vers la tête)
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

; InitRequester(requester a0) : les 112 octets mis à zéro.
intuition_InitRequester:
        moveq   #RQ_SIZEOF/4-1,d0
.ir_lp:
        clr.l   (a0)+
        dbra    d0,.ir_lp
        rts

; SetDMRequest(fenêtre a0, requester a1) -> d0 = TRUE ; FALSE (rien de changé) si le DMRequest actuel est affiché.
; ClearDMRequest(fenêtre a0) : la même chose avec NULL.
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
