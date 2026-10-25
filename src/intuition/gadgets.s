; src/intuition/gadgets.s — intuition.library : gadgets d'application des fenêtres (liste wd_FirstGadget). Rendu
; (Border ou Image, IntuiText, surbrillance), sélection au bouton gauche avec GADGETDOWN / GADGETUP (im_IAddress = le
; gadget), AddGadget/AddGList, RemoveGadget/RemoveGList, RefreshGadgets/RefreshGList, OnGadget/OffGadget, DrawBorder.
; Gadgets texte (STRGADGET, StringInfo) : activés par un clic ou ActivateGadget, ils reçoivent le clavier (routé par
; le handler de pointeur, cf. it_keyin) : insertion, Backspace, Del, flèches (Shift : début / fin), Amiga droite + X
; (effacer) et + Q (annuler) ; Return / Enter termine (LONGINT converti, GADGETUP si RELVERIFY), un clic ailleurs
; désactive sans message. Texte aligné à gauche (STRINGCENTER / STRINGRIGHT ignorés). Les autres types sont traités
; comme des boutons ; pas de motif « fantôme » pour un gadget désactivé (il ne répond simplement plus).
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
                xdef    prop_track
                xdef    intuition_ModifyProp
                xdef    intuition_NewModifyProp

; gad_rect(a3 = fenêtre, a0 = gadget, a1 = 4 mots x0, y0, x1, y1) : rectangle du gadget en coordonnées de la fenêtre,
; positions et tailles relatives au bord droit / bas résolues. Gadget intérieur d'une fenêtre GIMMEZEROZERO : relatif à
; l'intérieur (taille GZZ), puis décalé des bordures gauche et haute. Clobbe d0/d1.
gad_rect:
        movem.l d2-d3,-(sp)
        move.w  WD_WIDTH(a3),d2      ; d2/d3 = taille de référence
        move.w  WD_HEIGHT(a3),d3
        bsr.s   gad_inner
        beq.s   .gr_ref
        move.w  WD_GZZWIDTH(a3),d2
        move.w  WD_GZZHEIGHT(a3),d3
.gr_ref:
        move.w  GG_FLAGS(a0),d1
        move.w  GG_LEFTEDGE(a0),d0
        btst    #4,d1                ; GRELRIGHT : bord droit du domaine (largeur - 1) + LeftEdge
        beq.s   .gr_x
        add.w   d2,d0
        subq.w  #1,d0
.gr_x:
        move.w  d0,(a1)
        move.w  GG_TOPEDGE(a0),d0
        btst    #3,d1                ; GRELBOTTOM : bord bas du domaine (hauteur - 1) + TopEdge
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
        bsr.s   gad_inner
        beq.s   .gr_ret
        moveq   #0,d0
        move.b  WD_BORDERLEFT(a3),d0
        add.w   d0,(a1)
        add.w   d0,4(a1)
        move.b  WD_BORDERTOP(a3),d0
        add.w   d0,2(a1)
        add.w   d0,6(a1)
.gr_ret:
        movem.l (sp)+,d2-d3
        rts

; gad_inner(a3 = fenêtre, a0 = gadget) -> Z = 0 si c'est un gadget de l'intérieur d'une fenêtre GIMMEZEROZERO (pas
; GZZGADGET) : dessiné dans la couche intérieure, à l'origine de l'intérieur. Préserve tout.
gad_inner:
        btst    #2,WD_FLAGS+2(a3)    ; GIMMEZEROZERO
        beq.s   .gn_ret
        tst.l   WD_BORDERRPORT(a3)   ; (BACKDROP : une seule couche)
        beq.s   .gn_ret
        btst    #5,GG_GADGETTYPE(a0) ; GZZGADGET ($2000) : dans le cadre -> Z = 1 ; sinon Z = 0
        eori.b  #4,ccr
.gn_ret:
        rts

; gad_rpof(a3 = fenêtre, a2 = gadget) -> a0 = RastPort où le dessiner : celui du cadre pour un gadget GZZGADGET d'une
; fenêtre GIMMEZEROZERO, sinon celui de la fenêtre (l'intérieur). Préserve tout le reste.
gad_rpof:
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

; gad_rp(a3 = fenêtre, a2 = gadget, a1 = rectangle de gad_rect) -> a1 inchangé, a0 = RastPort où le dessiner (gad_rpof) ;
; le rectangle est ramené dans ce RastPort (gadget intérieur d'une fenêtre GIMMEZEROZERO : moins les bordures).
; Clobbe d0.
gad_rp:
        bsr.s   gad_rpof
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

; gad_inside(a3 = fenêtre, a0 = gadget, d2/d3 = point dans la fenêtre) -> Z = 0 si le point est dans le gadget.
; Clobbe d0/d1/a1.
gad_inside:
        lea     -8(sp),sp
        move.l  sp,a1
        bsr     gad_rect
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
; GADGHIMAGE), texte, puis surbrillance d'un gadget sélectionné en GADGHCOMP / GADGHBOX. gad_render : sans cette
; surbrillance. Préserve d2-d7/a2-a6.
gad_draw:
        moveq   #1,d0
        bra.s   gad_drw
gad_render:
        moveq   #0,d0
gad_drw:
        movem.l d2-d7/a2-a6,-(sp)
        move.w  d0,d7                ; d7 = surbrillance voulue
        lea     -8(sp),sp
        move.l  a2,a0
        move.l  sp,a1
        bsr     gad_rect
        bsr     gad_rp
        move.l  a0,a4                ; a4 = RastPort du gadget, rectangle ramené dedans
        move.w  GG_GADGETTYPE(a2),d0
        and.w   #GTYP_MASK,d0
        cmp.w   #PROPGADGET,d0
        bne.s   .gd_nprop
        bsr     prop_render          ; proportionnel : boîte, cadre, knob ; puis son texte
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
        cmp.w   #PROPGADGET,d0       ; (proportionnel : son knob porte déjà l'état tenu)
        beq.s   .gd_ret
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
        movem.l d2-d7/a2-a3/a6,-(sp)
        move.w  d0,d7                ; d7 = 0 tout / 1 contour
        bsr     gad_rpof             ; RastPort du gadget (rectangle déjà ramené dedans par l'appelant)
        move.l  a0,a3                ; a3 = RastPort désormais
        movem.w 4+36(sp),d4-d6/a2    ; x0 y0 x1 y1 (a2 = y1, étendu)
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
        move.l  a3,a1
        move.l  (sp)+,d0
        jsr     LVO_SETDRMD(a6)
        movem.l (sp)+,d2-d7/a2-a3/a6
.gc_ret:
        rts
.gc_fill:                            ; RectFill(rp, d0, d1, d2, d3) si le rectangle n'est pas vide
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

; gad_drawall(a3 = fenêtre, a5 = IntuitionBase) : tous les gadgets d'application de la fenêtre. Préserve tout.
gad_drawall:
        movem.l d0-d2/a0-a2,-(sp)
        move.l  WD_FIRSTGADGET(a3),a2
        moveq   #-1,d2
        bsr.s   gad_drawrev
        movem.l (sp)+,d0-d2/a0-a2
        rts

; gad_drawrev(a2 = premier gadget, d2 = nombre (-1 = jusqu'à la fin), a3 = fenêtre, a5) : comme intuition 1.3, la
; plage est rendue à rebours, du dernier au premier, si bien que le premier de la liste finit par-dessus (info.library
; compte dessus pour que SAVE/QUIT, en tête, recouvrent leur remplisseur) ; puis, à l'endroit, la surbrillance des
; gadgets sélectionnés. Parcours quadratique sans pile (listes courtes). Les gadgets système sont dessinés avec le
; cadre. Clobbe d0-d2/a0-a2.
gad_drawrev:
        move.l  a2,a0                ; a0 = fin de plage (gadget qui suit le dernier, ou NULL)
.dr_end:
        move.l  a0,d0
        beq.s   .dr_go
        tst.l   d2
        beq.s   .dr_go
        subq.l  #1,d2
        move.l  GG_NEXTGADGET(a0),a0
        bra.s   .dr_end
.dr_go:
        movem.l a0/a2,-(sp)          ; fin de plage, premier gadget
.dr_lp:
        cmp.l   a2,a0
        beq.s   .dr_hl               ; plage vide ou entièrement rendue
        move.l  a2,a1                ; cherche le prédécesseur de la fin
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
        move.l  (sp)+,a0             ; ce gadget devient la nouvelle fin
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
        cmp.w   #GADGHIMAGE,d0       ; SelectRender déjà rendu
        beq.s   .dr_hnext
        move.l  a0,-(sp)
        bsr     gad_hilite
        move.l  (sp)+,a0
.dr_hnext:
        move.l  GG_NEXTGADGET(a2),a2
        bra.s   .dr_hlp
.dr_ret:
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
        bsr     gad_rp
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
        move.w  GG_GADGETTYPE(a2),d0
        and.w   #GTYP_MASK,d0
        cmp.w   #PROPGADGET,d0
        beq.s   .gn_prop
        cmp.w   #STRGADGET,d0
        bne.s   .gn_bool
        bsr     str_activate         ; d2 = abscisse du clic : place le curseur
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
        move.w  GG_GADGETTYPE(a2),d0
        and.w   #GTYP_MASK,d0
        cmp.w   #PROPGADGET,d0
        bne.s   .gu_nprop
        bsr     prop_up
        bra.s   .gu_ret
.gu_nprop:
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
        cmp.l   IB_SYSWIN(a6),a0     ; gadget système enfoncé dans cette fenêtre : oublié
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

; --- gadgets proportionnels (spec intuition-prop-v34) ----------------------------------------------------------
; zone de travail : boîte et conteneur en coordonnées du RastPort du gadget, knob relatif au conteneur, décalage
; fenêtre -> RastPort
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

; gad_propinit(a3 = fenêtre) : bordures du PropInfo de chaque gadget proportionnel de la fenêtre, comme à l'entrée
; d'un gadget dans une fenêtre : WBorLeft / WBorTop de l'écran, 0 / 0 si PROPBORDERLESS (spec §1). Préserve tout.
gad_propinit:
        movem.l d0-d1/a0-a2,-(sp)
        move.l  WD_WSCREEN(a3),a1
        move.l  WD_FIRSTGADGET(a3),a2
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

; prop_prep(a3 = fenêtre, a2 = gadget, a1 = zone PP_SIZE) -> a0 = RastPort du gadget, zone remplie (spec §2). Écrit
; CWidth/CHeight et les PotRes du PropInfo, la taille du knob dans l'Image de rendu (AUTOKNOB) et sa position dans
; les Images de rendu et de sélection. Préserve d2-d7/a2-a6.
prop_prep:
        movem.l d2-d7/a2-a4,-(sp)
        move.l  a1,a4
        move.l  a2,a0
        bsr     gad_rect
        move.l  (a4),d2              ; coin de la boîte dans la fenêtre (x, y)
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
        move.w  PP_L(a4),d0          ; conteneur = boîte moins les bordures du PropInfo
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
        move.l  GG_GADGETRENDER(a2),a0   ; a0 = Image du knob
        btst    #0,PI_FLAGS+1(a1)    ; AUTOKNOB : taille d'après Body
        beq.s   .pp_img
        move.w  PP_CW(a4),d4         ; largeur
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
        move.w  PP_CH(a4),d5         ; hauteur
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
        moveq   #0,d6                ; x du knob
        btst    #1,PI_FLAGS+1(a1)
        beq.s   .pp_kx
        move.w  PP_CW(a4),d0
        sub.w   d4,d0
        move.w  PI_HPOT(a1),d1
        bsr     .pp_place
        move.w  d0,d6
.pp_kx:
        moveq   #0,d7                ; y du knob
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
.pp_step:                            ; d0.w = Body -> d0.w = pas de page ($FFFF dès Body >= $8000). Clobbe d1.
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
.pp_clamp:                           ; d0.w ramené à [d1, d2] puis à au moins 1
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
.pp_place:                           ; d0.w = course, d1.w = Pot -> d0.w = (course × (Pot + 1)) >> 16 (course < 0 : 0)
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

; prop_render(a3 = fenêtre, a2 = gadget, a5) : dessin complet (spec §3.1) : boîte au DetailPen, cadre au BlockPen
; (montants de WBorLeft/2, traits de WBorTop/2) sauf PROPBORDERLESS, puis le knob. Préserve d2-d7/a2-a5 ; clobbe
; d0/d1/a0/a1/a6.
prop_render:
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
        movem.w (sp),d0-d3           ; boîte
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
        lsr.w   #1,d6                ; d6 = épaisseur des montants
        moveq   #0,d7
        move.b  SC_WBORTOP(a0),d7
        lsr.w   #1,d7                ; d7 = épaisseur des traits
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

; prop_knob(a3 = fenêtre, a2 = gadget, a4 = RastPort, a1 = zone préparée, a5, a6 = GfxBase) : le knob (spec §3.1) :
; AUTOKNOB = rectangle plein au BlockPen (complémenté s'il est tenu : SELECTED et KNOBHIT) ; sinon l'Image de rendu
; (de sélection en GADGHIMAGE), inversée en GADGHCOMP quand il est tenu. Clobbe d0/d1/a0/a1 ; rend a6 = GfxBase.
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
        subq.w  #1,d3                ; d0-d3 = boîte du knob
        moveq   #0,d5                ; d5 = knob tenu ?
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
        move.l  a4,a0                ; coin du conteneur = boîte du knob - position du knob dans l'Image
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
        bne.s   .pk_ret              ; GADGHCOMP seulement
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

; prop_update(a3 = fenêtre, a2 = gadget, a5, d4-d7 = ancienne boîte du knob x0, y0, x1, y1) : le knob est redessiné
; à sa nouvelle position, puis les parties de l'ancien qu'il ne recouvre plus sont rendues au DetailPen (spec §3.2).
; Rien si la position n'a pas changé. Préserve d2-d7/a2-a5 ; clobbe d0/d1/a0/a1/a6.
PU_NEW          EQU PP_SIZE          ; nouvelle boîte du knob (4 mots)
prop_update:
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
        move.w  d4,d0                ; au-dessus de la nouvelle boîte
        move.w  d5,d1
        move.w  d6,d2
        move.w  PU_NEW+2(sp),d3
        subq.w  #1,d3
        cmp.w   d7,d3
        ble.s   .pu_t
        move.w  d7,d3
.pu_t:
        bsr     .pu_fill
        move.w  d4,d0                ; au-dessous
        move.w  PU_NEW+6(sp),d1
        addq.w  #1,d1
        cmp.w   d5,d1
        bge.s   .pu_b
        move.w  d5,d1
.pu_b:
        move.w  d6,d2
        move.w  d7,d3
        bsr.s   .pu_fill
        move.w  PU_NEW+2(sp),d1      ; bande commune : à gauche et à droite
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
.pu_fill:                            ; RectFill(d0..d3) si le rectangle n'est pas vide. Clobbe d0/d1/a1.
        cmp.w   d0,d2
        blt.s   .pf_r
        cmp.w   d1,d3
        blt.s   .pf_r
        move.l  a4,a1
        jmp     LVO_RECTFILL(a6)
.pf_r:
        rts

; prop_down(a3 = fenêtre, a2 = gadget, a5, d2/d3 = clic dans la fenêtre, d4/d5 = pointeur écran) : le gadget est tenu
; (SELECTED). Clic dans le knob élargi des bordures : KNOBHIT, glissement suivi (IB_TRACK) ; ailleurs : saut d'une
; page sur chaque axe libre, vers le clic (spec §4). Préserve d2-d7/a2-a5 ; clobbe d0/d1/a0/a1/a6.
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
        sub.w   PP_DX(sp),d2         ; d2/d3 = clic dans le RastPort
        sub.w   PP_DY(sp),d3
        move.w  PP_CL(sp),d4         ; d4-d7 = boîte du knob
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
        move.w  d4,d0                ; knob élargi des bordures du PropInfo
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
        bsr     prop_knob            ; knob tenu
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

; prop_track(a5, d4/d5 = pointeur) -> Z = 0 si un knob est tenu et que ce mouvement lui revient : nouvelle position
; = précédente + déplacement, bornée au conteneur ; Pot recalculés (spec §2.4) ; knob redessiné ; MOUSEMOVE si
; FOLLOWMOUSE. Clobbe d0-d7/a0-a4/a6.
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
        move.w  d4,d2                ; d2/d3 = déplacement
        sub.w   IB_PMX(a5),d2
        move.w  d5,d3
        sub.w   IB_PMY(a5),d3
        move.w  d4,IB_PMX(a5)
        move.w  d5,IB_PMY(a5)
        lea     -PP_SIZE(sp),sp
        move.l  sp,a1
        bsr     prop_prep
        move.w  PP_CL(sp),d4         ; d4-d7 = boîte actuelle du knob
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
        sub.w   PP_KW(sp),d1         ; course
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
.pt_axis:                            ; d0.w = position voulue, d1.w = course -> d0 = position bornée, d1 = Pot
        tst.w   d0
        bpl.s   .pa_lo
        moveq   #0,d0
.pa_lo:
        tst.w   d1
        bgt.s   .pa_hi
        moveq   #0,d0
        moveq   #-1,d1               ; conteneur plein : Pot = $FFFF
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
        swap    d1                   ; d1 = course (long)
        move.l  d0,-(sp)
        and.l   #$FFFF,d0
        swap    d0                   ; position << 16
        divu    d1,d0
        move.w  d0,d1
        move.l  (sp)+,d0
        rts

; prop_up(a3 = fenêtre, a2 = gadget, a5, d2/d3 = pointeur dans la fenêtre) : relâchement : le gadget n'est plus tenu,
; le suivi s'arrête, knob redessiné ; GADGETUP s'il est RELVERIFY, où que soit le pointeur.
prop_up:
        bclr    #7,GG_FLAGS+1(a2)
        move.l  GG_SPECIALINFO(a2),a0
        btst    #0,PI_FLAGS(a0)      ; KNOBHIT : glissement suivi
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

; ModifyProp(gadget a0, fenêtre a1, requester a2, Flags d0, HorizPot d1, VertPot d2, HorizBody d3, VertBody d4) :
; nouvelles valeurs du PropInfo, puis redessin de ce gadget jusqu'à la fin de la liste. NewModifyProp(…, nombre d5) :
; seulement « nombre » gadgets à partir de celui-ci (spec §5).
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
        beq.s   .mp_ret              ; sans fenêtre : rien à redessiner
        move.l  d7,d2
        bsr     gad_drawrev
.mp_ret:
        movem.l (sp)+,d2-d7/a2-a3/a5
        rts

; --- gadgets texte ---------------------------------------------------------------------------------------------
; str_len(a0 = StringInfo) -> si_NumChars recalculé (longueur du texte, bornée à MaxChars - 1), d0 = ce nombre.
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

; str_text(a3 = fenêtre, a2 = gadget, a5 = IntuitionBase) : zone de texte du gadget (son rectangle) effacée puis
; remplie avec les caractères visibles depuis si_DispPos, curseur inversé s'il est actif ; la position d'affichage
; suit le curseur. Stylos et mode du RastPort restaurés. Préserve d2-d7/a2-a6.
str_text:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  GG_SPECIALINFO(a2),d0
        beq     .st_ret
        move.l  d0,a4                ; a4 = StringInfo
        lea     -8(sp),sp
        move.l  a2,a0
        move.l  sp,a1
        bsr     gad_rect
        bsr     gad_rp               ; rectangle ramené dans le RastPort du gadget
        move.l  a4,a0
        bsr     str_len
        move.l  WD_RPORT(a3),a1
        moveq   #0,d6
        move.w  rp_TxWidth(a1),d6
        bne.s   .st_cw
        moveq   #8,d6
.st_cw:
        move.w  4(sp),d0             ; caractères visibles = largeur / largeur de caractère
        sub.w   (sp),d0
        addq.w  #1,d0
        ext.l   d0
        divu    d6,d0
        move.w  d0,SI_DISPCOUNT(a4)
        cmp.l   IB_STRGAD(a5),a2
        bne.s   .st_disp
        move.w  SI_BUFFERPOS(a4),d1  ; actif : curseur visible
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
        move.l  a0,a3                ; a3 = RastPort du gadget désormais
        move.b  rp_FgPen(a3),-(sp)
        move.b  rp_BgPen(a3),-(sp)
        move.b  rp_DrawMode(a3),-(sp)
        move.l  a3,a1
        moveq   #0,d0
        jsr     LVO_SETAPEN(a6)
        move.l  a3,a1
        moveq   #JAM1,d0
        jsr     LVO_SETDRMD(a6)
        movem.w 6(sp),d0-d3          ; x0 y0 x1 y1 (sous les 3 sauvegardes, 6 octets)
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
        sub.w   SI_DISPPOS(a4),d4    ; d4 = caractères à écrire
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
        cmp.w   12(sp),d3            ; borné au bas du gadget
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

; str_activate(a3 = fenêtre, a2 = gadget STRGADGET, a5, d2.w = abscisse du clic dans la fenêtre | -1) : le gadget
; devient le gadget texte actif (l'ancien est désactivé), son texte est copié dans le tampon d'annulation, le curseur
; est placé sous le clic (sinon gardé, borné au texte) ; GADGETDOWN s'il est GADGIMMEDIATE. Préserve d2-d7/a2-a6.
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

; str_deact(a5) : le gadget texte actif (s'il y en a un) ne l'est plus ; redessiné sans curseur. Préserve tout.
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

; str_clickout(a5, d4/d5 = clic dans l'écran) : un clic hors du gadget texte actif le désactive (sans message).
; Préserve tout.
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

; str_key(a5, d0.w = IT_KEYCODE + keycode, d4.w = qualificatif) : tâche d'entrée — une touche pour le gadget texte
; actif. Préserve a5.
str_key:
        move.l  IB_STRGAD(a5),d1
        beq     .sk_ret
        movem.l d2-d7/a2-a4,-(sp)
        move.l  d1,a2
        move.l  IB_STRWIN(a5),a3
        move.l  GG_SPECIALINFO(a2),a4
        and.w   #$007F,d0
        move.w  SI_BUFFERPOS(a4),d2  ; d2 = curseur, d3 = longueur
        move.w  SI_NUMCHARS(a4),d3
        move.l  SI_BUFFER(a4),a0
        cmp.w   #$4F,d0              ; flèche gauche
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
        cmp.w   #$4E,d0              ; flèche droite
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
        cmp.w   #$41,d0              ; Backspace : supprime avant le curseur
        bne.s   .sk_nbs
        tst.w   d2
        beq     .sk_done
        subq.w  #1,d2
        bra.s   .sk_del
.sk_nbs:
        cmp.w   #$46,d0              ; Del : supprime sous le curseur
        bne.s   .sk_ndel
        cmp.w   d3,d2
        bge     .sk_done
.sk_del:
        lea     0(a0,d2.w),a1        ; texte décalé d'un cran vers la gauche, NUL compris
.sk_dl:
        move.b  1(a1),(a1)+
        bne.s   .sk_dl
        subq.w  #1,d3
        bra     .sk_pos
.sk_ndel:
        move.w  d4,d1
        jsr     kbd_cook             ; d0 = caractère (0 : pas de caractère)
        and.w   #$00FF,d0
        beq     .sk_done
        btst    #KQB_RCOMMAND,d4
        beq.s   .sk_char
        or.b    #$20,d0              ; Amiga droite : X efface, Q annule
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
        btst    #3,GG_ACTIVATION(a2) ; LONGINT ($0800) : chiffres et signe seulement
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
        bge     .sk_done             ; plein
        lea     0(a0,d3.w),a1        ; décale [curseur .. NUL] d'un cran vers la droite
        move.w  d3,d1
        sub.w   d2,d1                ; octets à décaler, NUL compris : d1 + 1
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
        btst    #3,GG_ACTIVATION(a2) ; LONGINT : valeur décimale signée dans si_LongInt
        beq.s   .sk_up
        moveq   #0,d1                ; d1 = valeur, d2 = négatif
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
        add.l   d1,d1                ; × 10 = × 2 + × 8
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

; ActivateGadget(gadget a0, fenêtre a1, requester a2) -> d0 = TRUE si un gadget texte actif (non désactivé) de cette
; fenêtre est devenu le gadget actif (curseur gardé), FALSE sinon.
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
; AddGadget(fenêtre a0, gadget a1, position d0) -> d0 = position effective. AddGList(fenêtre a0, gadget a1, position
; d0, nombre d1 (-1 = toute la chaîne), requester a2) : la chaîne de gadgets est insérée à la position (-1 = à la
; fin) dans wd_FirstGadget. Rien n'est redessiné (RefreshGadgets / RefreshGList).
intuition_AddGadget:
        moveq   #1,d1
intuition_AddGList:
        movem.l d2/a2-a3/a6,-(sp)
        move.l  a0,a3                ; a3 = fenêtre
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
        bsr     gad_propinit         ; bordures des gadgets proportionnels entrés dans la fenêtre
        move.l  d2,d0
        movem.l (sp)+,d2/a2-a3/a6
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
        cmp.l   WD_FIRSTGADGET(a3),a2    ; depuis la tête de liste : les gadgets système (en tête chez intuition 1.3)
        seq     -(sp)                    ; sont redessinés en dernier, par-dessus
        bsr     gad_drawrev
        tst.b   (sp)+
        beq.s   .rf_ret
        btst    #3,WD_FLAGS+2(a3)        ; (aucun sur une fenêtre BORDERLESS)
        bne.s   .rf_ret
        jsr     wn_sysgads
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
; décalés de (x + LeftEdge, y + TopEdge), au stylo FrontPen dans le mode DrawMode. Stylos et mode du RastPort rendus
; intacts, comme en 1.3 (sondé : tests/itextstate.s).
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
        move.b  (sp)+,rp_DrawMode(a2)
        move.b  (sp)+,rp_BgPen(a2)
        move.b  (sp)+,rp_FgPen(a2)
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
