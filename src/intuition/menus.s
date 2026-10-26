; src/intuition/menus.s — menus d'intuition : SetMenuStrip/ClearMenuStrip, ItemAddress, OnMenu/OffMenu, PrintIText,
; IntuiTextLength, et l'interaction au bouton droit (tâche d'entrée d'intuition).
; Bouton droit enfoncé sur la fenêtre active qui a une barre de menus (et pas RMBTRAP) : la barre de l'écran est
; recouverte par une couche simple portant les titres des menus ; le pointeur dans la barre déroule le menu visé
; (une seconde couche simple sous la barre, éléments ITEMTEXT ou images) ; l'élément sous le pointeur est mis en
; surbrillance (inversion) s'il est actif. Au relâchement : MENUPICK à la fenêtre avec le code du choix (MENUNULL
; sinon), couches supprimées ; layers rend la zone aux fenêtres (sauvegarde des fenêtres smart, REFRESHWINDOW des
; fenêtres simple via it_refresh). Les éléments ou menus inactifs sont grisés par des rayures horizontales au stylo
; du fond.
; Portée : pas de sous-menus, ni de coches dessinées, ni de raccourcis clavier, ni de multi-sélection.
; Piste IMPLÉMENTATION (« clean ») : AutoDocs intuition.library + intuition/intuition.h. AUCUNE lecture ROM.

                include "exec.i"
                include "intuition.i"
                include "graphics.i"

                xdef    intuition_SetMenuStrip
                xdef    intuition_ClearMenuStrip
                xdef    intuition_ItemAddress
                xdef    intuition_OnMenu
                xdef    intuition_OffMenu
                xdef    intuition_PrintIText
                xdef    intuition_IntuiTextLength
                xdef    it_menubutton
                xdef    it_menumove
                xref    it_refresh
                xref    it_title
                xref    it_box
                xref    it_scrxy
                xref    wn_sendmsg
                xref    intuition_DrawImage

MB_MARGIN       EQU 2                ; marge intérieure du menu déroulé (cadre compris)
SC_BARH_M       EQU 9                ; hauteur de la barre de l'écran (lignes 0..9), comme screens.s

; SetMenuStrip(fenêtre a0, menu a1) -> d0 = TRUE. ClearMenuStrip(fenêtre a0).
intuition_SetMenuStrip:
        move.l  a1,WD_MENUSTRIP(a0)
        moveq   #1,d0
        rts
intuition_ClearMenuStrip:
        clr.l   WD_MENUSTRIP(a0)
        rts

; ItemAddress(menustrip a0, code d0) -> d0 = MenuItem (ou sous-élément) désigné, 0 pour MENUNULL ou hors liste.
intuition_ItemAddress:
        bsr.s   mn_find
        move.l  a0,d0
        rts

; mn_find(a0 = premier menu, d0.w = code) -> a0 = élément | 0, a1 = menu | 0, d1.w = n° d'élément ($3F : aucun).
; Clobbe d0.
mn_find:
        move.l  d2,-(sp)
        move.w  d0,d2
        cmp.w   #MENUNULL,d2
        beq.s   .fd_none
        and.w   #$1F,d0              ; n° de menu
.fd_menu:
        move.l  a0,d1
        beq.s   .fd_none
        subq.w  #1,d0
        bmi.s   .fd_gotmenu
        move.l  MU_NEXTMENU(a0),a0
        bra.s   .fd_menu
.fd_gotmenu:
        move.l  a0,a1
        move.w  d2,d1
        lsr.w   #5,d1
        and.w   #$3F,d1              ; n° d'élément
        cmp.w   #$3F,d1
        beq.s   .fd_menuonly
        move.l  MU_FIRSTITEM(a1),a0
        move.w  d1,d0
        bsr.s   .fd_walk
        beq.s   .fd_out
        move.w  d2,d0
        lsr.w   #8,d0
        lsr.w   #3,d0                ; n° de sous-élément
        cmp.w   #$1F,d0
        beq.s   .fd_out
        move.l  MI_SUBITEM(a0),a0
        bsr.s   .fd_walk
        bra.s   .fd_out
.fd_menuonly:
        suba.l  a0,a0
        bra.s   .fd_out
.fd_none:
        suba.l  a0,a0
        suba.l  a1,a1
        moveq   #$3F,d1
.fd_out:
        move.l  (sp)+,d2
        rts
.fd_walk:                            ; a0 = d0-ième de la chaîne (MI_NEXTITEM) | 0 ; Z = 1 si absent
        cmpa.w  #0,a0
        beq.s   .fw_ret
        subq.w  #1,d0
        bmi.s   .fw_hit
        move.l  MI_NEXTITEM(a0),a0
        bra.s   .fd_walk
.fw_hit:
        cmpa.w  #0,a0                ; Z = 0
.fw_ret:
        rts

; OffMenu(fenêtre a0, code d0) / OnMenu(fenêtre a0, code d0) : désactive / active l'élément désigné (sous-élément
; compris), ou le menu entier si le n° d'élément vaut NOITEM.
intuition_OffMenu:
        moveq   #0,d1
        bra.s   mn_onoff
intuition_OnMenu:
        moveq   #1,d1
mn_onoff:
        move.l  d1,-(sp)
        move.l  WD_MENUSTRIP(a0),a0
        bsr.s   mn_find
        move.l  (sp)+,d0
        move.l  a0,d1
        bne.s   .oo_item
        move.l  a1,d1
        beq.s   .oo_ret
        bclr    #0,MU_FLAGS+1(a1)    ; MENUENABLED
        tst.w   d0
        beq.s   .oo_ret
        bset    #0,MU_FLAGS+1(a1)
.oo_ret:
        rts
.oo_item:
        bclr    #4,MI_FLAGS+1(a0)    ; ITEMENABLED
        tst.w   d0
        beq.s   .oo_ret
        bset    #4,MI_FLAGS+1(a0)
        rts

; PrintIText(rp a0, itext a1, x d0, y d1) : chaque IntuiText de la chaîne aux stylos et mode qu'elle porte, son
; coin haut-gauche en (x + LeftEdge, y + TopEdge). Police unique 8x8 (ITextFont ignorée).
intuition_PrintIText:
        movem.l d2-d3/a2-a3/a6,-(sp)
        move.b  rp_FgPen(a0),-(sp)   ; stylos et mode rendus intacts, comme en 1.3 (sondé : tests/itextstate.s)
        move.b  rp_BgPen(a0),-(sp)
        move.b  rp_DrawMode(a0),-(sp)
        move.l  a0,a2
        move.l  a1,a3
        move.w  d0,d2
        move.w  d1,d3
        move.l  IB_GFXBASE(a6),a6
.pt_lp:
        move.l  a3,d0
        beq.s   .pt_ret
        move.l  a2,a1
        moveq   #0,d0
        move.b  IT_FRONTPEN(a3),d0
        jsr     LVO_SETAPEN(a6)
        move.l  a2,a1
        moveq   #0,d0
        move.b  IT_BACKPEN(a3),d0
        jsr     LVO_SETBPEN(a6)
        move.l  a2,a1
        moveq   #0,d0
        move.b  IT_DRAWMODE(a3),d0
        jsr     LVO_SETDRMD(a6)
        move.l  a2,a1
        move.w  d2,d0
        add.w   IT_LEFTEDGE(a3),d0
        move.w  d3,d1
        add.w   IT_TOPEDGE(a3),d1
        addq.w  #GFX_FONTBASE,d1
        jsr     LVO_MOVE(a6)
        move.l  IT_ITEXT(a3),a0
        bsr.s   mn_strlen
        move.l  a2,a1
        jsr     LVO_TEXT(a6)
        move.l  IT_NEXTTEXT(a3),a3
        bra.s   .pt_lp
.pt_ret:
        move.b  (sp)+,rp_DrawMode(a2)
        move.b  (sp)+,rp_BgPen(a2)
        move.b  (sp)+,rp_FgPen(a2)
        movem.l (sp)+,d2-d3/a2-a3/a6
        rts

; IntuiTextLength(itext a0) -> d0 = largeur en pixels de son texte (police 8x8).
intuition_IntuiTextLength:
        move.l  IT_ITEXT(a0),a0
        bsr.s   mn_strlen
        lsl.l   #3,d0
        rts

; mn_strlen(a0 = chaîne C) -> d0 = longueur. Préserve a0.
mn_strlen:
        move.l  a0,-(sp)
        moveq   #-1,d0
.sl_lp:
        addq.l  #1,d0
        tst.b   (a0)+
        bne.s   .sl_lp
        move.l  (sp)+,a0
        rts

; it_menubutton(a4 = écran de tête, a5 = IntuitionBase, d7.w = code, d4/d5 = pointeur dans l'écran) : contexte
; tâche d'entrée. Enfoncé : affiche la barre de menus de la fenêtre active ; relâché : fin du choix.
it_menubutton:
        cmp.w   #IECODE_RBUTTON,d7
        bne     mn_end
        tst.l   IB_MENUWIN(a5)
        bne.s   .mb_ret
        move.l  IB_ACTIVEWINDOW(a5),d0
        beq.s   .mb_ret
        move.l  d0,a3
        cmp.l   WD_WSCREEN(a3),a4
        bne.s   .mb_ret
        tst.l   WD_MENUSTRIP(a3)
        beq.s   .mb_ret
        btst    #0,WD_FLAGS+1(a3)    ; RMBTRAP : le bouton droit appartient à l'application
        bne.s   .mb_ret
        move.l  WD_FIRSTREQUEST(a3),d0   ; requester sans NOISYREQ : pas de menus (spec intuition-requesters-v34 §3.2)
        beq.s   .mb_menus
        move.l  d0,a0
        btst    #2,RQ_FLAGS+1(a0)    ; NOISYREQ
        beq.s   .mb_ret
.mb_menus:
        clr.l   IB_MENUBOX(a5)
        clr.l   IB_MENUCUR(a5)
        clr.l   IB_ITEMCUR(a5)
        lea     SC_LAYERINFO(a4),a0
        lea     SC_BITMAP(a4),a1
        moveq   #0,d0
        moveq   #0,d1
        move.w  SC_WIDTH(a4),d2
        subq.w  #1,d2
        moveq   #SC_BARH_M,d3
        moveq   #IL_SIMPLE,d4
        suba.l  a2,a2
        move.l  IB_LAYERSBASE(a5),a6
        jsr     LVO_CREATEUPFRONTLAYER(a6)
        move.l  d0,IB_MENUBAR(a5)
        beq.s   .mb_ret
        move.l  a3,IB_MENUWIN(a5)
        bsr     mn_drawbar
        st      IB_TRACK(a5)
        move.w  PTR_X,d4
        move.w  PTR_Y,d5
        bra     it_menumove
.mb_ret:
        rts

; mn_drawbar(a3 = fenêtre, a4 = écran, a5) : fond au stylo BlockPen, titres des menus au stylo DetailPen à leur
; LeftEdge ; un menu inactif est grisé.
mn_drawbar:
        movem.l d2-d7/a2,-(sp)
        move.l  IB_MENUBAR(a5),a2
        move.l  IL_RP(a2),a2         ; a2 = RastPort de la barre
        move.l  IB_GFXBASE(a5),a6
        move.l  a2,a1
        moveq   #0,d0
        move.b  SC_BLOCKPEN(a4),d0
        jsr     LVO_SETAPEN(a6)
        move.l  a2,a1
        moveq   #0,d0
        moveq   #0,d1
        move.w  SC_WIDTH(a4),d2
        subq.w  #1,d2
        moveq   #SC_BARH_M,d3
        jsr     LVO_RECTFILL(a6)
        move.l  WD_MENUSTRIP(a3),d7
.db_lp:
        tst.l   d7
        beq.s   .db_ret
        move.l  d7,a0
        moveq   #0,d0
        move.b  SC_DETAILPEN(a4),d0
        moveq   #0,d1
        move.b  SC_BLOCKPEN(a4),d1
        move.w  MU_WIDTH(a0),d2
        move.w  MU_LEFTEDGE(a0),d3
        addq.w  #4,d3
        move.l  MU_MENUNAME(a0),a0
        move.l  a2,a1
        jsr     it_title
        move.l  d7,a0
        btst    #0,MU_FLAGS+1(a0)    ; MENUENABLED
        bne.s   .db_nx
        move.w  MU_LEFTEDGE(a0),d0
        moveq   #0,d1
        move.w  d0,d2
        add.w   MU_WIDTH(a0),d2
        subq.w  #1,d2
        moveq   #SC_BARH_M,d3
        move.l  a2,a1
        bsr     mn_ghost
.db_nx:
        move.l  d7,a0
        move.l  MU_NEXTMENU(a0),d7
        bra.s   .db_lp
.db_ret:
        movem.l (sp)+,d2-d7/a2
        rts

; mn_ghost(a1 = RastPort, d0..d3 = x0,y0,x1,y1, a4 = écran, a5) : rayures horizontales (une ligne sur deux) au stylo
; BlockPen sur le rectangle (une ligne par RectFill : peu d'appels). Clobbe d0-d3/a0/a1/a6.
mn_ghost:
        movem.l d4-d7/a2,-(sp)
        move.l  a1,a2
        movem.w d0-d3,-(sp)
        movem.w (sp)+,d4-d7
        move.l  IB_GFXBASE(a5),a6
        move.l  a2,a1
        moveq   #JAM1,d0
        jsr     LVO_SETDRMD(a6)
        move.l  a2,a1
        moveq   #0,d0
        move.b  SC_BLOCKPEN(a4),d0
        jsr     LVO_SETAPEN(a6)
        addq.w  #1,d5                ; lignes impaires du rectangle
.gh_lp:
        cmp.w   d7,d5
        bgt.s   .gh_ret
        move.l  a2,a1
        move.w  d4,d0
        move.w  d5,d1
        move.w  d6,d2
        move.w  d5,d3
        jsr     LVO_RECTFILL(a6)
        addq.w  #2,d5
        bra.s   .gh_lp
.gh_ret:
        movem.l (sp)+,d4-d7/a2
        rts

; it_menumove(a5, d4/d5 = pointeur) : pointeur dans la barre -> le menu visé est déroulé (aucun élément choisi) ;
; dans le menu déroulé -> l'élément visé est mis en surbrillance ; ailleurs -> aucun élément.
it_menumove:
        tst.l   IB_MENUWIN(a5)
        beq     .mm_ret
        bsr     it_scrxy
        beq     .mm_ret
        move.l  IB_MENUWIN(a5),a3
        cmp.w   #SC_BARH_M,d5
        bgt.s   .mm_items
        move.l  WD_MENUSTRIP(a3),a2  ; menu sous le pointeur
        moveq   #0,d6
.mm_find:
        move.l  a2,d0
        beq.s   .mm_none
        move.w  d4,d0
        sub.w   MU_LEFTEDGE(a2),d0
        bmi.s   .mm_fnx
        cmp.w   MU_WIDTH(a2),d0
        blt.s   .mm_found
.mm_fnx:
        move.l  MU_NEXTMENU(a2),a2
        addq.w  #1,d6
        bra.s   .mm_find
.mm_found:
        cmp.l   IB_MENUCUR(a5),a2
        beq.s   .mm_none
        bsr     mn_closebox
        move.l  a2,IB_MENUCUR(a5)
        move.w  d6,IB_MENUNUM(a5)
        bsr     mn_openbox
.mm_none:
        suba.l  a2,a2
        bra     mn_setitem
.mm_items:
        tst.l   IB_MENUBOX(a5)
        beq.s   .mm_none
        move.l  IB_MENUCUR(a5),a0
        move.l  MU_FIRSTITEM(a0),a2
        moveq   #0,d6
        move.w  d4,d2                ; position relative au premier élément
        sub.w   IB_BOX(a5),d2
        subq.w  #MB_MARGIN,d2
        move.w  d5,d3
        sub.w   IB_BOX+2(a5),d3
        subq.w  #MB_MARGIN,d3
.mm_it:
        move.l  a2,d0
        beq.s   mn_setitem
        move.w  d2,d0
        sub.w   MI_LEFTEDGE(a2),d0
        bmi.s   .mm_inx
        cmp.w   MI_WIDTH(a2),d0
        bge.s   .mm_inx
        move.w  d3,d0
        sub.w   MI_TOPEDGE(a2),d0
        bmi.s   .mm_inx
        cmp.w   MI_HEIGHT(a2),d0
        blt.s   mn_setitem
.mm_inx:
        move.l  MI_NEXTITEM(a2),a2
        addq.w  #1,d6
        bra.s   .mm_it
.mm_ret:
        rts

; mn_setitem(a2 = élément visé | 0, d6.w = son n°, a4, a5) : la surbrillance passe de l'élément courant au visé, si
; celui-ci est actif (et son menu aussi).
mn_setitem:
        cmp.l   IB_ITEMCUR(a5),a2
        beq.s   .si_ret
        tst.l   IB_ITEMCUR(a5)
        beq.s   .si_new
        bsr.s   mn_hilite            ; rétablit l'ancien
        clr.l   IB_ITEMCUR(a5)
.si_new:
        move.l  a2,d0
        beq.s   .si_ret
        btst    #4,MI_FLAGS+1(a2)    ; ITEMENABLED
        beq.s   .si_ret
        move.l  IB_MENUCUR(a5),a0
        btst    #0,MU_FLAGS+1(a0)    ; MENUENABLED
        beq.s   .si_ret
        move.l  a2,IB_ITEMCUR(a5)
        move.w  d6,IB_ITEMNUM(a5)
        bra.s   mn_hilite
.si_ret:
        rts

; mn_hilite(a5) : inverse le rectangle de l'élément courant (HIGHNONE : rien) dans la couche du menu déroulé.
; Clobbe d0-d3/a0/a1/a6.
mn_hilite:
        move.l  IB_ITEMCUR(a5),a0
        move.w  MI_FLAGS(a0),d0
        and.w   #HIGHFLAGS,d0
        cmp.w   #HIGHNONE,d0
        beq.s   .hl_ret
        move.l  a2,-(sp)
        move.l  a0,a2
        move.l  IB_GFXBASE(a5),a6
        move.l  IB_MENUBOX(a5),a1
        move.l  IL_RP(a1),a1
        move.l  a1,-(sp)
        moveq   #COMPLEMENT,d0
        jsr     LVO_SETDRMD(a6)
        move.l  (sp)+,a1
        moveq   #MB_MARGIN,d0
        add.w   MI_LEFTEDGE(a2),d0
        moveq   #MB_MARGIN,d1
        add.w   MI_TOPEDGE(a2),d1
        move.w  d0,d2
        add.w   MI_WIDTH(a2),d2
        subq.w  #1,d2
        move.w  d1,d3
        add.w   MI_HEIGHT(a2),d3
        subq.w  #1,d3
        jsr     LVO_RECTFILL(a6)
        move.l  (sp)+,a2
.hl_ret:
        rts

; mn_openbox(a2 = menu, a4 = écran, a5) : couche simple sous la barre, à la LeftEdge du menu (décalée pour rester
; dans l'écran), juste assez grande pour ses éléments ; fond BlockPen, cadre DetailPen, éléments (texte ou image),
; éléments inactifs grisés. Origine de la couche dans IB_BOX. Préserve d2-d7/a2-a4.
mn_openbox:
        movem.l d2-d7/a2-a4,-(sp)
        move.l  MU_FIRSTITEM(a2),d0
        beq     .ob_ret
        move.l  d0,a3
        moveq   #0,d6                ; d6/d7 = étendue des éléments (droite, bas)
        moveq   #0,d7
.ob_ext:
        move.w  MI_LEFTEDGE(a3),d0
        add.w   MI_WIDTH(a3),d0
        cmp.w   d6,d0
        ble.s   .ob_e1
        move.w  d0,d6
.ob_e1:
        move.w  MI_TOPEDGE(a3),d0
        add.w   MI_HEIGHT(a3),d0
        cmp.w   d7,d0
        ble.s   .ob_e2
        move.w  d0,d7
.ob_e2:
        move.l  MI_NEXTITEM(a3),d0
        move.l  d0,a3
        bne.s   .ob_ext
        add.w   #2*MB_MARGIN-1,d6    ; d6/d7 = largeur / hauteur - 1
        add.w   #2*MB_MARGIN-1,d7
        move.w  MU_LEFTEDGE(a2),d0
        move.w  SC_WIDTH(a4),d1
        subq.w  #1,d1
        sub.w   d6,d1                ; x0 maximal
        cmp.w   d1,d0
        ble.s   .ob_x
        move.w  d1,d0
.ob_x:
        tst.w   d0
        bpl.s   .ob_x0
        moveq   #0,d0
.ob_x0:
        moveq   #SC_BARH_M+1,d1
        move.w  d0,d2
        add.w   d6,d2
        move.w  d1,d3
        add.w   d7,d3
        move.w  SC_HEIGHT(a4),d4
        subq.w  #1,d4
        cmp.w   d4,d3
        ble.s   .ob_y
        move.w  d4,d3
.ob_y:
        movem.w d0-d1,IB_BOX(a5)
        moveq   #IL_SIMPLE,d4
        lea     SC_LAYERINFO(a4),a0
        lea     SC_BITMAP(a4),a1
        move.l  a2,-(sp)
        suba.l  a2,a2
        move.l  IB_LAYERSBASE(a5),a6
        jsr     LVO_CREATEUPFRONTLAYER(a6)
        move.l  (sp)+,a2
        move.l  d0,IB_MENUBOX(a5)
        beq     .ob_ret
        move.l  d0,a3
        move.l  IL_RP(a3),a3         ; a3 = RastPort du menu
        move.l  IB_GFXBASE(a5),a6
        move.l  a3,a1
        moveq   #JAM2,d0
        jsr     LVO_SETDRMD(a6)
        move.l  a3,a1
        moveq   #0,d0
        move.b  SC_BLOCKPEN(a4),d0
        jsr     LVO_SETAPEN(a6)
        move.l  a3,a1
        moveq   #0,d0
        moveq   #0,d1
        move.w  d6,d2
        move.w  d7,d3
        jsr     LVO_RECTFILL(a6)
        move.l  a3,a1
        moveq   #0,d0
        move.b  SC_DETAILPEN(a4),d0
        jsr     LVO_SETAPEN(a6)
        move.l  a3,a1
        moveq   #0,d0
        moveq   #0,d1
        move.w  d6,d2
        move.w  d7,d3
        jsr     it_box
        move.l  MU_FIRSTITEM(a2),a2  ; éléments
.ob_it:
        move.l  a2,d0
        beq.s   .ob_ret
        move.l  MI_ITEMFILL(a2),d0
        beq.s   .ob_ghost
        move.l  d0,a1
        moveq   #MB_MARGIN,d0
        add.w   MI_LEFTEDGE(a2),d0
        moveq   #MB_MARGIN,d1
        add.w   MI_TOPEDGE(a2),d1
        move.l  a3,a0
        move.l  a5,a6
        btst    #1,MI_FLAGS+1(a2)    ; ITEMTEXT
        beq.s   .ob_img
        bsr     intuition_PrintIText
        bra.s   .ob_ghost
.ob_img:
        jsr     intuition_DrawImage
.ob_ghost:
        btst    #4,MI_FLAGS+1(a2)    ; inactif (ou menu inactif) : grisé
        beq.s   .ob_g
        move.l  IB_MENUCUR(a5),a0
        btst    #0,MU_FLAGS+1(a0)
        bne.s   .ob_nx
.ob_g:
        moveq   #MB_MARGIN,d0
        add.w   MI_LEFTEDGE(a2),d0
        moveq   #MB_MARGIN,d1
        add.w   MI_TOPEDGE(a2),d1
        move.w  d0,d2
        add.w   MI_WIDTH(a2),d2
        subq.w  #1,d2
        move.w  d1,d3
        add.w   MI_HEIGHT(a2),d3
        subq.w  #1,d3
        move.l  a3,a1
        bsr     mn_ghost
.ob_nx:
        move.l  MI_NEXTITEM(a2),a2
        bra.s   .ob_it
.ob_ret:
        movem.l (sp)+,d2-d7/a2-a4
        rts

; mn_closebox(a4, a5) : supprime le menu déroulé (s'il existe) et répare l'écran. Préserve d2-d7/a2-a4.
mn_closebox:
        move.l  IB_MENUBOX(a5),d0
        beq.s   .cb_ret
        clr.l   IB_MENUBOX(a5)
        clr.l   IB_ITEMCUR(a5)
        move.l  a2,-(sp)
        move.l  d0,a1
        suba.l  a0,a0
        move.l  IB_LAYERSBASE(a5),a6
        jsr     LVO_DELETELAYER(a6)
        bsr     it_refresh
        move.l  (sp)+,a2
.cb_ret:
        rts

; mn_end(a4, a5) : bouton droit relâché. Code du choix (élément actif en surbrillance, sinon MENUNULL) ; un élément
; CHECKIT est coché (MENUTOGGLE : basculé). Couches supprimées, écran réparé, puis MENUPICK à la fenêtre.
mn_end:
        move.l  IB_MENUWIN(a5),d0
        beq.s   .me_ret
        move.l  d0,a3
        move.w  #MENUNULL,d7
        move.l  IB_ITEMCUR(a5),d0
        beq.s   .me_close
        move.l  d0,a0
        move.w  #MENUNULL,MI_NEXTSELECT(a0)
        btst    #0,MI_FLAGS+1(a0)    ; CHECKIT
        beq.s   .me_code
        btst    #3,MI_FLAGS+1(a0)    ; MENUTOGGLE
        beq.s   .me_set
        bchg    #0,MI_FLAGS(a0)      ; CHECKED ($100)
        bra.s   .me_code
.me_set:
        bset    #0,MI_FLAGS(a0)
.me_code:
        move.w  IB_ITEMNUM(a5),d7
        lsl.w   #5,d7
        or.w    IB_MENUNUM(a5),d7
        or.w    #$1F<<11,d7          ; NOSUB
.me_close:
        bsr     mn_closebox
        clr.l   IB_MENUCUR(a5)
        clr.l   IB_MENUWIN(a5)
        clr.b   IB_TRACK(a5)
        move.l  IB_MENUBAR(a5),a1
        clr.l   IB_MENUBAR(a5)
        suba.l  a0,a0
        move.l  IB_LAYERSBASE(a5),a6
        jsr     LVO_DELETELAYER(a6)
        bsr     it_refresh
        move.w  d4,d2
        sub.w   WD_LEFTEDGE(a3),d2
        move.w  d5,d3
        sub.w   WD_TOPEDGE(a3),d3
        move.l  #MENUPICK,d0
        move.w  d7,d1
        bra     wn_sendmsg
.me_ret:
        rts
