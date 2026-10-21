; src/intuition/gadgets.s — intuition.library : gadgets d'application des fenêtres (liste wd_FirstGadget). Rendu
; (Border ou Image, IntuiText, surbrillance), sélection au bouton gauche avec GADGETDOWN / GADGETUP (im_IAddress = le
; gadget), AddGadget/AddGList, RemoveGadget/RemoveGList, RefreshGadgets/RefreshGList, OnGadget/OffGadget, DrawBorder.
; Les gadgets sont traités comme des boutons (BOOLGADGET) quel que soit leur type ; pas de motif « fantôme » pour un
; gadget désactivé (il ne répond simplement plus).
; Piste IMPLÉMENTATION (« clean ») : structures publiques intuition/intuition.h + AutoDocs intuition. AUCUNE lecture ROM.

                include "exec.i"
                include "graphics.i"
                include "intuition.i"

                xdef    intuition_AddGadget
                xdef    intuition_AddGList
                xdef    intuition_RemoveGadget
                xdef    intuition_RemoveGList
                xdef    intuition_RefreshGadgets
                xdef    intuition_RefreshGList
                xdef    intuition_OnGadget
                xdef    intuition_OffGadget
                xdef    intuition_DrawBorder
                xdef    gad_drawall
                xdef    gad_down
                xdef    gad_up
                xdef    gad_forget
                xref    intuition_DrawImage
                xref    intuition_PrintIText
                xref    wn_sendgad

; gad_rect(a3 = fenêtre, a0 = gadget, a1 = 4 mots x0, y0, x1, y1) : rectangle du gadget en coordonnées de la fenêtre,
; positions et tailles relatives au bord droit / bas résolues. Clobbe d0/d1.
gad_rect:
        move.w  GG_FLAGS(a0),d1
        move.w  GG_LEFTEDGE(a0),d0
        btst    #4,d1                ; GRELRIGHT
        beq.s   .gr_x
        add.w   WD_WIDTH(a3),d0
.gr_x:
        move.w  d0,(a1)
        move.w  GG_TOPEDGE(a0),d0
        btst    #3,d1                ; GRELBOTTOM
        beq.s   .gr_y
        add.w   WD_HEIGHT(a3),d0
.gr_y:
        move.w  d0,2(a1)
        move.w  GG_WIDTH(a0),d0
        btst    #5,d1                ; GRELWIDTH
        beq.s   .gr_w
        add.w   WD_WIDTH(a3),d0
.gr_w:
        add.w   (a1),d0
        subq.w  #1,d0
        move.w  d0,4(a1)
        move.w  GG_HEIGHT(a0),d0
        btst    #6,d1                ; GRELHEIGHT
        beq.s   .gr_h
        add.w   WD_HEIGHT(a3),d0
.gr_h:
        add.w   2(a1),d0
        subq.w  #1,d0
        move.w  d0,6(a1)
        rts

; gad_inside(a3 = fenêtre, a0 = gadget, d2/d3 = point dans la fenêtre) -> Z = 0 si le point est dans le gadget.
; Clobbe d0/d1/a1.
gad_inside:
        lea     -8(sp),sp
        move.l  sp,a1
        bsr.s   gad_rect
        moveq   #0,d0                ; Z = 1 par défaut (dehors)
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

; gad_draw(a3 = fenêtre, a2 = gadget, a5 = IntuitionBase) : image ou bordure (SelectRender si sélectionné en
; GADGHIMAGE), texte, puis surbrillance d'un gadget sélectionné en GADGHCOMP / GADGHBOX. Préserve d2-d7/a2-a6.
gad_draw:
        movem.l d2-d7/a2-a6,-(sp)
        lea     -8(sp),sp
        move.l  a2,a0
        move.l  sp,a1
        bsr     gad_rect
        move.l  WD_RPORT(a3),a4
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
        btst    #7,GG_FLAGS+1(a2)    ; SELECTED
        beq.s   .gd_ret
        bsr.s   gad_comp
.gd_ret:
        lea     8(sp),sp
        movem.l (sp)+,d2-d7/a2-a6
        rts

; gad_comp(a3 = fenêtre, a2 = gadget, a5, rectangle en 4(sp)) : surbrillance par inversion, de tout le gadget
; (GADGHCOMP) ou de son contour (GADGHBOX) ; une seconde inversion l'efface. Préserve d2-d7/a2-a5.
gad_comp:
        move.w  GG_FLAGS(a2),d0
        and.w   #GADGHIGHBITS,d0
        cmp.w   #GADGHBOX,d0
        bhi.s   .gc_ret              ; GADGHIMAGE / GADGHNONE : rien à inverser
        movem.l d2-d7/a2/a6,-(sp)
        move.w  d0,d7                ; d7 = 0 tout / 1 contour
        movem.w 4+32(sp),d4-d6/a2    ; x0 y0 x1 y1 (a2 = y1, étendu)
        move.l  a2,d3
        move.l  IB_GFXBASE(a5),a6
        move.l  WD_RPORT(a3),a1
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
        move.w  d4,d0                ; haut
        move.w  d5,d1
        move.w  d6,d2
        move.l  d3,-(sp)
        move.w  d5,d3
        bsr.s   .gc_fill
        move.l  (sp)+,d3
        move.w  d4,d0                ; bas
        move.w  d3,d1
        move.w  d6,d2
        bsr.s   .gc_fill
        move.w  d4,d0                ; gauche (sans les coins déjà inversés)
        move.w  d5,d1
        addq.w  #1,d1
        move.w  d4,d2
        subq.w  #1,d3
        bsr.s   .gc_fill
        move.w  d6,d0                ; droite
        move.w  d5,d1
        addq.w  #1,d1
        move.w  d6,d2
        bsr.s   .gc_fill
.gc_end:
        move.l  WD_RPORT(a3),a1
        move.l  (sp)+,d0
        jsr     LVO_SETDRMD(a6)
        movem.l (sp)+,d2-d7/a2/a6
.gc_ret:
        rts
.gc_fill:                            ; RectFill(rp, d0, d1, d2, d3) si le rectangle n'est pas vide
        cmp.w   d0,d2
        blt.s   .gf_ret
        cmp.w   d1,d3
        blt.s   .gf_ret
        movem.l d0-d3,-(sp)
        move.l  WD_RPORT(a3),a1
        ext.l   d0
        ext.l   d1
        ext.l   d2
        ext.l   d3
        jsr     LVO_RECTFILL(a6)
        movem.l (sp)+,d0-d3
.gf_ret:
        rts

; gad_drawall(a3 = fenêtre, a5 = IntuitionBase) : tous les gadgets d'application de la fenêtre. Préserve tout.
gad_drawall:
        movem.l d0-d1/a0-a2,-(sp)
        move.l  WD_FIRSTGADGET(a3),a2
.da_lp:
        move.l  a2,d0
        beq.s   .da_ret
        tst.w   GG_GADGETTYPE(a2)    ; SYSGADGET (bit 15) : dessiné avec le cadre
        bmi.s   .da_next
        bsr     gad_draw
.da_next:
        move.l  GG_NEXTGADGET(a2),a2
        bra.s   .da_lp
.da_ret:
        movem.l (sp)+,d0-d1/a0-a2
        rts

; gad_hilite(a3, a2, a5) : l'état SELECTED vient de changer -> surbrillance mise à jour (inversion, ou image redessinée
; en GADGHIMAGE). Préserve d2-d7/a2-a5.
gad_hilite:
        move.w  GG_FLAGS(a2),d0
        and.w   #GADGHIGHBITS,d0
        cmp.w   #GADGHIMAGE,d0
        beq     gad_draw
        lea     -8(sp),sp
        move.l  a2,a0
        move.l  sp,a1
        bsr     gad_rect
        bsr     gad_comp
        lea     8(sp),sp
        rts

; gad_down(a3 = fenêtre, a5, d2/d3 = clic dans la fenêtre) -> Z = 0 si un gadget d'application actif l'a pris :
; il est sélectionné (ou basculé en TOGGLESELECT), GADGETDOWN s'il est GADGIMMEDIATE, et il reste enfoncé jusqu'au
; relâchement (gad_up). Clobbe d0/d1/d6/a0/a1/a6 (comme wn_sendmsg).
gad_down:
        move.l  a2,-(sp)
        move.l  WD_FIRSTGADGET(a3),a2
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

; gad_send(a3, a0 = gadget, d0 = classe, d1 = code, d2/d3 = souris) : message IDCMP dont im_IAddress est le gadget.
gad_send:
        movem.l d2-d7/a2-a5,-(sp)
        jsr     wn_sendgad
        movem.l (sp)+,d2-d7/a2-a5
        rts

; gad_up(a5, d4/d5 = pointeur écran) : relâchement d'un gadget enfoncé. Hors TOGGLESELECT il est désélectionné ;
; GADGETUP s'il est RELVERIFY et que le pointeur est encore dessus. Clobbe d0-d3/d6/a0/a1/a3/a6.
gad_up:
        move.l  a2,-(sp)
        move.l  IB_GADACT(a5),a2
        move.l  IB_GADWIN(a5),a3
        clr.l   IB_GADACT(a5)
        move.w  d4,d2
        sub.w   WD_LEFTEDGE(a3),d2
        move.w  d5,d3
        sub.w   WD_TOPEDGE(a3),d3
        btst    #0,GG_ACTIVATION(a2) ; TOGGLESELECT : l'état basculé au clic reste
        bne.s   .gu_verify
        bclr    #7,GG_FLAGS+1(a2)
        bsr     gad_hilite
.gu_verify:
        btst    #0,GG_ACTIVATION+1(a2)   ; RELVERIFY
        beq.s   .gu_ret
        move.l  a2,a0
        bsr     gad_inside
        beq.s   .gu_ret
        moveq   #GADGETUP,d0
        moveq   #0,d1
        move.l  a2,a0
        bsr.s   gad_send
.gu_ret:
        move.l  (sp)+,a2
        rts

; gad_forget(a0 = fenêtre | gadget) : oublie le gadget enfoncé s'il appartient à cette fenêtre ou est ce gadget
; (fenêtre fermée, gadget retiré). a6 = IntuitionBase. Clobbe d0.
gad_forget:
        cmp.l   IB_GADWIN(a6),a0
        beq.s   .gf_clr
        cmp.l   IB_GADACT(a6),a0
        bne.s   .gf_r
.gf_clr:
        clr.l   IB_GADACT(a6)
.gf_r:
        rts

; ------------------------------------------------------------------------------------------------------------------
; AddGadget(fenêtre a0, gadget a1, position d0) -> d0 = position effective. AddGList(fenêtre a0, gadget a1, position
; d0, nombre d1 (-1 = toute la chaîne), requester a2) : la chaîne de gadgets est insérée à la position (-1 = à la
; fin) dans wd_FirstGadget. Rien n'est redessiné (RefreshGadgets / RefreshGList).
intuition_AddGadget:
        moveq   #1,d1
intuition_AddGList:
        movem.l d2/a2/a6,-(sp)
        move.l  a1,a2                ; a2 = dernier gadget de la chaîne à insérer
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
        lea     WD_FIRSTGADGET(a0),a0    ; maillon précédent (le lien est au début d'un gadget)
        moveq   #0,d2
.ag_pos:
        cmp.l   d0,d2
        bhs.s   .ag_ins              ; position atteinte (-1 = jamais : jusqu'à la fin)
        tst.l   (a0)
        beq.s   .ag_ins
        move.l  (a0),a0
        addq.l  #1,d2
        bra.s   .ag_pos
.ag_ins:
        move.l  (a0),GG_NEXTGADGET(a2)
        move.l  a1,(a0)
        jsr     LVO_PERMIT(a6)
        move.l  d2,d0
        movem.l (sp)+,d2/a2/a6
        rts

; RemoveGadget(fenêtre a0, gadget a1) -> d0 = position qu'il occupait | -1. RemoveGList(fenêtre a0, gadget a1, nombre
; d0 (-1 = jusqu'à la fin)) : les gadgets quittent la liste, le dernier retiré est terminé par NULL.
intuition_RemoveGadget:
        moveq   #1,d0
intuition_RemoveGList:
        movem.l d2/a2/a6,-(sp)
        move.l  a6,-(sp)
        move.l  d0,d1                ; d1 = nombre
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
        move.l  a1,a2                ; a2 = dernier retiré
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

; RefreshGadgets(gadgets a0, fenêtre a1, requester a2) : redessine depuis ce gadget jusqu'à la fin de la liste.
; RefreshGList(gadgets a0, fenêtre a1, requester a2, nombre d0) : au plus nombre gadgets (-1 = tous).
intuition_RefreshGadgets:
        moveq   #-1,d0
intuition_RefreshGList:
        movem.l d2/a2-a3/a5,-(sp)
        move.l  a6,a5
        move.l  a1,a3
        move.l  a0,a2
        move.l  d0,d2
.rf_lp:
        move.l  a2,d0
        beq.s   .rf_ret
        tst.l   d2
        beq.s   .rf_ret
        tst.w   GG_GADGETTYPE(a2)
        bmi.s   .rf_next
        bsr     gad_draw
.rf_next:
        subq.l  #1,d2
        move.l  GG_NEXTGADGET(a2),a2
        bra.s   .rf_lp
.rf_ret:
        movem.l (sp)+,d2/a2-a3/a5
        rts

; OnGadget(gadget a0, fenêtre a1, requester a2) / OffGadget(...) : le gadget redevient actif / est désactivé, puis il
; est redessiné.
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

; DrawBorder(rp a0, border a1, x d0, y d1) : chaque Border de la chaîne, ligne brisée de Count points (paires XY)
; décalés de (x + LeftEdge, y + TopEdge), au stylo FrontPen dans le mode DrawMode.
intuition_DrawBorder:
        movem.l d2-d7/a2-a6,-(sp)
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
        add.w   BD_LEFTEDGE(a3),d4   ; d4 = origine x
        move.w  d7,d3
        add.w   BD_TOPEDGE(a3),d3    ; d3 = origine y
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
        movem.l (sp)+,d2-d7/a2-a6
        rts
.db_pt:                              ; point suivant (a4)+ -> d0/d1 absolus, a1 = rp
        move.w  (a4)+,d0
        add.w   d4,d0
        ext.l   d0
        move.w  (a4)+,d1
        add.w   d3,d1
        ext.l   d1
        move.l  a2,a1
        rts
