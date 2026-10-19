; src/intuition/screens.s — écrans et fenêtres d'intuition.library : OpenScreen/CloseScreen, OpenWorkBench,
; GetScreenData, OpenWindow/CloseWindow.
; Un écran = struct Screen (V34) + BitMap en chip RAM + ColorMap ; l'écran de tête est affiché via le View
; d'IntuitionBase (ib_ViewLord : MakeVPort/MrgCop/LoadView). Une fenêtre = struct Window + son RastPort + une
; pseudo-couche (struct Layer dont seules les bornes servent : décalage et découpage du dessin, cf. graphics/draw.s).
; Sans layers.library : pas de recouvrement géré (une fenêtre dessine par-dessus les autres, la fermer efface sa
; zone au stylo 0), pas de rafraîchissement, pas de déplacement ni de redimensionnement, pas de port IDCMP.
; Décor (barres de titre, gadgets dessinés) : rendu propre à ce projet, aux couleurs des préférences 1.3.
; Piste IMPLÉMENTATION (« clean ») : AutoDocs intuition.library + includes NDK publics (screens.h, intuition.h).
; AUCUNE lecture ROM.

                include "exec.i"
                include "intuition.i"
                include "graphics.i"

                xdef    intuition_OpenScreen
                xdef    intuition_CloseScreen
                xdef    intuition_OpenWorkBench
                xdef    intuition_GetScreenData
                xdef    intuition_OpenWindow
                xdef    intuition_CloseWindow

; extension privée derrière la struct Screen (même allocation)
SCX_RASINFO     EQU SC_SIZEOF        ; struct RasInfo (12)
SCX_COLORMAP    EQU SCX_RASINFO+ri_SIZEOF   ; struct ColorMap (8)
SCX_COLORTAB    EQU SCX_COLORMAP+GCM_SIZEOF ; 32 couleurs
SCX_PLANESIZE   EQU SCX_COLORTAB+64  ; taille d'un plan alloué ici (0 : BitMap fournie par l'appelant)
SCX_SIZE        EQU SCX_PLANESIZE+4
SC_MAXCOLORS    EQU 32
SC_BARH         EQU 9                ; BarHeight : la barre de titre couvre les lignes 0..9
SC_GADW         EQU 23               ; largeur d'un gadget de profondeur
; fenêtre : struct Window + RastPort + Layer (même allocation)
WDX_RPORT       EQU WD_SIZE
WDX_LAYER       EQU WDX_RPORT+rp_SIZEOF
WDX_SIZE        EQU WDX_LAYER+lr_SIZEOF
WD_TBARH        EQU 10               ; hauteur de la barre de titre d'une fenêtre (BorderTop)
WD_CLOSEW       EQU 20               ; largeur du gadget de fermeture

; OpenScreen(newscreen a0) -> d0 = Screen | 0. Alloue la struct, la BitMap (plans chip effacés, sauf CUSTOMBITMAP),
; la palette par défaut (2^profondeur couleurs, 32 au plus), dessine la barre de titre (sauf SCREENQUIET), place
; l'écran en tête de liste et l'affiche.
intuition_OpenScreen:
        movem.l d2-d7/a2-a5,-(sp)
        move.l  a6,a5                ; a5 = IntuitionBase
        move.l  a0,a2                ; a2 = NewScreen
        move.l  ($4).w,a6
        move.l  #SCX_SIZE,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .os_fail
        move.l  d0,a3                ; a3 = Screen
        move.w  NS_LEFTEDGE(a2),SC_LEFTEDGE(a3)
        move.w  NS_TOPEDGE(a2),SC_TOPEDGE(a3)
        move.w  NS_WIDTH(a2),d4      ; d4 = largeur (<= 0 : 320 ou 640 selon le mode)
        bgt.s   .os_wok
        move.w  #320,d4
        tst.w   NS_VIEWMODES(a2)
        bpl.s   .os_wok
        move.w  #640,d4
.os_wok:
        move.w  NS_HEIGHT(a2),d5     ; d5 = hauteur (<= 0 : 256, PAL)
        bgt.s   .os_hok
        move.w  #256,d5
.os_hok:
        move.w  d4,SC_WIDTH(a3)
        move.w  d5,SC_HEIGHT(a3)
        move.w  NS_DEPTH(a2),d6      ; d6 = profondeur, ramenée à 1..6
        bgt.s   .os_d1
        moveq   #1,d6
.os_d1:
        cmp.w   #6,d6
        bls.s   .os_d6
        moveq   #6,d6
.os_d6:
        move.b  NS_DETAILPEN(a2),SC_DETAILPEN(a3)
        move.b  NS_BLOCKPEN(a2),SC_BLOCKPEN(a3)
        move.w  NS_TYPE(a2),SC_FLAGS(a3)
        move.l  NS_DEFAULTTITLE(a2),SC_TITLE(a3)
        move.l  NS_DEFAULTTITLE(a2),SC_DEFAULTTITLE(a3)
        move.l  NS_FONT(a2),SC_FONT(a3)
        move.b  #SC_BARH,SC_BARHEIGHT(a3)
        move.b  #1,SC_BARVBORDER(a3)
        move.b  #5,SC_BARHBORDER(a3)
        move.b  #2,SC_MENUVBORDER(a3)
        move.b  #4,SC_MENUHBORDER(a3)
        move.b  #2,SC_WBORTOP(a3)
        move.b  #4,SC_WBORLEFT(a3)
        move.b  #4,SC_WBORRIGHT(a3)
        move.b  #2,SC_WBORBOTTOM(a3)
        ; BitMap
        move.w  NS_TYPE(a2),d0
        and.w   #CUSTOMBITMAP,d0
        beq.s   .os_ownbm
        move.l  NS_CUSTOMBITMAP(a2),a0
        lea     SC_BITMAP(a3),a1
        moveq   #bm_SIZEOF/2-1,d0
.os_cbm:
        move.w  (a0)+,(a1)+
        dbra    d0,.os_cbm
        bra.s   .os_bmok
.os_ownbm:
        lea     SC_BITMAP(a3),a0
        move.w  d6,d0
        move.w  d4,d1
        move.w  d5,d2
        move.l  IB_GFXBASE(a5),a6
        jsr     LVO_INITBITMAP(a6)
        move.l  ($4).w,a6
        move.w  SC_BITMAP+bm_BytesPerRow(a3),d7
        mulu    d5,d7                ; d7 = taille d'un plan
        move.l  d7,SCX_PLANESIZE(a3)
        lea     SC_BITMAP+bm_Planes(a3),a4
        move.w  d6,d3
        subq.w  #1,d3
.os_plane:
        move.l  d7,d0
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  d0,(a4)+
        beq     .os_nomem
        dbra    d3,.os_plane
.os_bmok:
        ; palette : 2^profondeur couleurs (32 au plus) depuis la table par défaut
        moveq   #1,d0
        move.b  SC_BITMAP+bm_Depth(a3),d1
        lsl.w   d1,d0
        cmp.w   #SC_MAXCOLORS,d0
        bls.s   .os_ncol
        moveq   #SC_MAXCOLORS,d0
.os_ncol:
        move.w  d0,SCX_COLORMAP+cm_Count(a3)
        lea     SCX_COLORTAB(a3),a0
        move.l  a0,SCX_COLORMAP+cm_ColorTable(a3)
        lea     sc_palette(pc),a1
        moveq   #SC_MAXCOLORS-1,d0
.os_pal:
        move.w  (a1)+,(a0)+
        dbra    d0,.os_pal
        ; RasInfo, ViewPort, RastPort
        lea     SC_BITMAP(a3),a0
        move.l  a0,SCX_RASINFO+ri_BitMap(a3)
        lea     SC_VIEWPORT(a3),a0
        move.w  d4,vp_DWidth(a0)
        move.w  d5,vp_DHeight(a0)
        move.w  NS_VIEWMODES(a2),vp_Modes(a0)
        lea     SCX_RASINFO(a3),a1
        move.l  a1,vp_RasInfo(a0)
        lea     SCX_COLORMAP(a3),a1
        move.l  a1,vp_ColorMap(a0)
        move.l  IB_GFXBASE(a5),a6
        lea     SC_RASTPORT(a3),a1
        jsr     LVO_INITRASTPORT(a6)
        lea     SC_BITMAP(a3),a0
        move.l  a0,SC_RASTPORT+rp_BitMap(a3)
        move.w  SC_FLAGS(a3),d0
        and.w   #SCREENQUIET,d0
        bne.s   .os_quiet
        bsr     sc_drawbar
.os_quiet:
        move.l  ($4).w,a6
        jsr     LVO_FORBID(a6)
        move.l  IB_FIRSTSCREEN(a5),SC_NEXTSCREEN(a3)
        move.l  a3,IB_FIRSTSCREEN(a5)
        move.l  a3,IB_ACTIVESCREEN(a5)
        jsr     LVO_PERMIT(a6)
        bsr     it_remake
        move.l  a3,d0
        bra.s   .os_ret
.os_nomem:
        bsr     sc_free
.os_fail:
        moveq   #0,d0
.os_ret:
        move.l  a5,a6
        movem.l (sp)+,d2-d7/a2-a5
        rts

; sc_free(a3 = Screen, a5 = IntuitionBase) : libère le fragment copper, les plans alloués par OpenScreen et la
; struct. a6 ressort = SysBase. Clobbe d0/d1/a0/a1/a4/d3.
sc_free:
        lea     SC_VIEWPORT(a3),a0
        move.l  IB_GFXBASE(a5),a6
        jsr     LVO_FREEVPORTCOPLISTS(a6)
        move.l  ($4).w,a6
        move.l  SCX_PLANESIZE(a3),d0
        beq.s   .sf_planes
        lea     SC_BITMAP+bm_Planes(a3),a4
        moveq   #7,d3
.sf_lp:
        move.l  (a4)+,d1
        beq.s   .sf_planes           ; plans contigus dans le tableau : le premier vide termine
        move.l  d1,a1
        move.l  SCX_PLANESIZE(a3),d0
        jsr     LVO_FREEMEM(a6)
        dbra    d3,.sf_lp
.sf_planes:
        move.l  a3,a1
        move.l  #SCX_SIZE,d0
        jmp     LVO_FREEMEM(a6)

; sc_drawbar(a3 = Screen, a5 = IntuitionBase) : barre de titre (lignes 0..BarHeight) au stylo BlockPen, titre au
; stylo DetailPen, deux gadgets de profondeur à droite. Clobbe d0-d3/a0/a1/a6.
sc_drawbar:
        move.l  IB_GFXBASE(a5),a6
        lea     SC_RASTPORT(a3),a1
        moveq   #0,d0
        move.b  SC_BLOCKPEN(a3),d0
        jsr     LVO_SETAPEN(a6)
        moveq   #0,d0
        moveq   #0,d1
        move.w  SC_WIDTH(a3),d2
        subq.w  #1,d2
        moveq   #SC_BARH,d3
        jsr     LVO_RECTFILL(a6)
        moveq   #0,d0
        move.b  SC_DETAILPEN(a3),d0
        moveq   #0,d1
        move.b  SC_BLOCKPEN(a3),d1
        move.w  SC_WIDTH(a3),d2
        sub.w   #2*SC_GADW+8,d2      ; largeur disponible pour le titre
        move.l  SC_TITLE(a3),a0
        moveq   #5,d3                ; x = BarHBorder
        bsr     it_title
        move.w  SC_WIDTH(a3),d2      ; gadgets de profondeur : [W-2G-1 .. W-G-2] et [W-G .. W-1]
        sub.w   #2*SC_GADW+1,d2
        moveq   #0,d3
        move.b  SC_DETAILPEN(a3),d3
        bsr     it_depthgads
        rts

; it_title(a1 = RastPort, a0 = titre C | 0, d0 = stylo texte, d1 = stylo fond, d2.w = largeur max en pixels,
; d3.w = x, a6 = GfxBase) : écrit le titre en JAM2 sur la ligne de base 7 (barre de 10 lignes). Clobbe d0-d3/a0.
it_title:
        move.l  d4,-(sp)
        move.l  a0,d4
        beq.s   .tt_ret
        move.l  d4,-(sp)
        move.l  d1,-(sp)
        jsr     LVO_SETAPEN(a6)
        move.l  (sp)+,d0
        jsr     LVO_SETBPEN(a6)
        moveq   #JAM2,d0
        jsr     LVO_SETDRMD(a6)
        move.w  d3,d0
        moveq   #1+GFX_FONTBASE,d1
        jsr     LVO_MOVE(a6)
        move.l  (sp)+,a0
        move.l  a0,d4
        moveq   #0,d0                ; d0 = longueur, bornée à la largeur disponible
        asr.w   #3,d2
.tt_len:
        tst.b   (a0)+
        beq.s   .tt_out
        cmp.w   d2,d0
        bge.s   .tt_out
        addq.w  #1,d0
        bra.s   .tt_len
.tt_out:
        move.l  d4,a0
        jsr     LVO_TEXT(a6)
.tt_ret:
        move.l  (sp)+,d4
        rts

; it_depthgads(a1 = RastPort, d2.w = x du premier gadget, d3.b = stylo, a6 = GfxBase) : deux gadgets de profondeur
; (arrière : cadre vide ; avant : cadre + carré plein) sur les lignes 1..8. Clobbe d0-d3/a0.
it_depthgads:
        movem.l d4/d5,-(sp)
        move.w  d2,d4                ; d4 = x
        move.b  d3,d5
        moveq   #0,d0
        move.b  d5,d0
        jsr     LVO_SETAPEN(a6)
        move.w  d4,d0                ; gadget arrière
        addq.w  #4,d0
        moveq   #2,d1
        move.w  d0,d2
        add.w   #13,d2
        moveq   #7,d3
        bsr     it_box
        add.w   #SC_GADW,d4          ; gadget avant
        move.w  d4,d0
        addq.w  #4,d0
        moveq   #2,d1
        move.w  d0,d2
        add.w   #13,d2
        moveq   #7,d3
        bsr     it_box
        move.w  d4,d0
        addq.w  #7,d0
        moveq   #4,d1
        move.w  d0,d2
        addq.w  #7,d2
        moveq   #6,d3
        jsr     LVO_RECTFILL(a6)
        movem.l (sp)+,d4/d5
        rts

; it_box(a1 = RastPort, d0..d3 = x0,y0,x1,y1, a6 = GfxBase) : cadre de 1 pixel au stylo A. Clobbe d0-d3/a0.
it_box:
        movem.l d4-d7,-(sp)
        movem.w d0-d3,-(sp)
        movem.w (sp)+,d4-d7          ; d4..d7 = x0,y0,x1,y1
        move.w  d4,d0
        move.w  d5,d1
        jsr     LVO_MOVE(a6)
        move.w  d6,d0
        move.w  d5,d1
        jsr     LVO_DRAW(a6)
        move.w  d6,d0
        move.w  d7,d1
        jsr     LVO_DRAW(a6)
        move.w  d4,d0
        move.w  d7,d1
        jsr     LVO_DRAW(a6)
        move.w  d4,d0
        move.w  d5,d1
        jsr     LVO_DRAW(a6)
        movem.l (sp)+,d4-d7
        rts

; it_remake(a5 = IntuitionBase) : affiche l'écran de tête (sa ViewPort seule dans ib_ViewLord), ou coupe
; l'affichage s'il n'y a plus d'écran. Préserve tout sauf d0/d1/a0/a1.
it_remake:
        movem.l a2/a6,-(sp)
        lea     IB_VIEWLORD(a5),a2
        move.l  IB_GFXBASE(a5),a6
        move.l  IB_FIRSTSCREEN(a5),d0
        beq.s   .rm_none
        add.l   #SC_VIEWPORT,d0
        move.l  d0,a1
        clr.l   vp_Next(a1)
        move.l  a1,v_ViewPort(a2)
        move.l  a2,a0
        jsr     LVO_MAKEVPORT(a6)
        move.l  a2,a1
        jsr     LVO_MRGCOP(a6)
        move.l  a2,a1
        jsr     LVO_LOADVIEW(a6)
        bra.s   .rm_ret
.rm_none:
        clr.l   v_ViewPort(a2)
        sub.l   a1,a1
        jsr     LVO_LOADVIEW(a6)
.rm_ret:
        movem.l (sp)+,a2/a6
        rts

; CloseScreen(screen a0) -> d0 = TRUE. Retire l'écran de la liste, libère ses ressources et réaffiche l'écran
; suivant. Les fenêtres encore ouvertes dessus ne sont pas fermées (contrat AutoDoc : l'appelant les ferme avant).
intuition_CloseScreen:
        movem.l d3/a3-a5,-(sp)
        move.l  a6,a5
        move.l  a0,a3
        move.l  a0,d0
        beq.s   .cs_ret
        move.l  ($4).w,a6
        jsr     LVO_FORBID(a6)
        lea     IB_FIRSTSCREEN(a5),a0 ; a0 = maillon précédent (SC_NEXTSCREEN à l'offset 0)
.cs_find:
        move.l  (a0),d0
        beq.s   .cs_unl
        cmp.l   d0,a3
        beq.s   .cs_hit
        move.l  d0,a0
        bra.s   .cs_find
.cs_hit:
        move.l  SC_NEXTSCREEN(a3),(a0)
.cs_unl:
        cmp.l   IB_ACTIVESCREEN(a5),a3
        bne.s   .cs_act
        move.l  IB_FIRSTSCREEN(a5),IB_ACTIVESCREEN(a5)
.cs_act:
        cmp.l   IB_WBSCREEN(a5),a3
        bne.s   .cs_wb
        clr.l   IB_WBSCREEN(a5)
.cs_wb:
        jsr     LVO_PERMIT(a6)
        bsr     it_remake            ; d'abord réafficher : le fragment de cet écran n'est plus utilisé
        bsr     sc_free
.cs_ret:
        moveq   #-1,d0
        move.l  a5,a6
        movem.l (sp)+,d3/a3-a5
        rts

; OpenWorkBench() -> d0 = Screen Workbench : l'ouvre s'il ne l'est pas (640x256, 2 plans, HIRES).
intuition_OpenWorkBench:
        move.l  IB_WBSCREEN(a6),d0
        bne.s   .ow_ret
        lea     sc_wbnewscreen(pc),a0
        bsr     intuition_OpenScreen
        move.l  d0,IB_WBSCREEN(a6)
.ow_ret:
        rts

; GetScreenData(buffer a0, taille d0, type d1, écran a1) -> d0 = TRUE | FALSE : copie min(taille, sizeof Screen)
; octets de l'écran (type WBENCHSCREEN : l'écran Workbench, ouvert au besoin).
intuition_GetScreenData:
        movem.l d2/a2,-(sp)
        move.l  a0,a2
        move.l  d0,d2
        cmp.w   #WBENCHSCREEN,d1
        bne.s   .gs_have
        bsr     intuition_OpenWorkBench
        move.l  d0,a1
.gs_have:
        move.l  a1,d0
        beq.s   .gs_ret
        cmp.l   #SC_SIZEOF,d2
        bls.s   .gs_cnt
        move.l  #SC_SIZEOF,d2
.gs_cnt:
        subq.l  #1,d2
        bmi.s   .gs_ok
.gs_cpy:
        move.b  (a1)+,(a2)+
        dbra    d2,.gs_cpy
.gs_ok:
        moveq   #-1,d0
.gs_ret:
        movem.l (sp)+,d2/a2
        rts

; OpenWindow(newwindow a0) -> d0 = Window | 0. Écran : nw_Screen si nw_Type = CUSTOMSCREEN, sinon le Workbench
; (ouvert au besoin). Position/taille ramenées dans l'écran ; bordures selon les drapeaux (BORDERLESS : aucune ;
; titre/gadgets système : barre de 10 lignes ; WINDOWSIZING : bordure droite de 18, ou basse de 9 si SIZEBBOTTOM).
; RPort = RastPort propre (BitMap de l'écran, couche aux bornes de la fenêtre). Le cadre est dessiné, l'intérieur
; effacé au stylo 0, et la fenêtre devient la fenêtre active.
intuition_OpenWindow:
        movem.l d2-d7/a2-a5,-(sp)
        move.l  a6,a5                ; a5 = IntuitionBase
        move.l  a0,a2                ; a2 = NewWindow
        move.w  NW_TYPE(a2),d0
        and.w   #SCREENTYPE,d0
        cmp.w   #CUSTOMSCREEN,d0
        bne.s   .ow_wb
        move.l  NW_SCREEN(a2),d0
        bne.s   .ow_scr
.ow_wb:
        bsr     intuition_OpenWorkBench
        tst.l   d0
        beq     .ow_fail
.ow_scr:
        move.l  d0,a4                ; a4 = Screen
        move.l  ($4).w,a6
        move.l  #WDX_SIZE,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .ow_fail
        move.l  d0,a3                ; a3 = Window
        ; géométrie ramenée dans l'écran
        move.w  NW_LEFTEDGE(a2),d4
        bpl.s   .ow_x0
        moveq   #0,d4
.ow_x0:
        move.w  NW_TOPEDGE(a2),d5
        bpl.s   .ow_y0
        moveq   #0,d5
.ow_y0:
        move.w  SC_WIDTH(a4),d0
        sub.w   #16,d0
        cmp.w   d0,d4
        ble.s   .ow_x1
        move.w  d0,d4
.ow_x1:
        move.w  SC_HEIGHT(a4),d0
        sub.w   #16,d0
        cmp.w   d0,d5
        ble.s   .ow_y1
        move.w  d0,d5
.ow_y1:
        move.w  NW_WIDTH(a2),d6
        move.w  SC_WIDTH(a4),d0
        sub.w   d4,d0                ; largeur maximale
        cmp.w   d0,d6
        ble.s   .ow_w1
        move.w  d0,d6
.ow_w1:
        cmp.w   #16,d6
        bge.s   .ow_w2
        moveq   #16,d6
.ow_w2:
        move.w  NW_HEIGHT(a2),d7
        move.w  SC_HEIGHT(a4),d0
        sub.w   d5,d0
        cmp.w   d0,d7
        ble.s   .ow_h1
        move.w  d0,d7
.ow_h1:
        cmp.w   #16,d7
        bge.s   .ow_h2
        moveq   #16,d7
.ow_h2:
        move.w  d4,WD_LEFTEDGE(a3)
        move.w  d5,WD_TOPEDGE(a3)
        move.w  d6,WD_WIDTH(a3)
        move.w  d7,WD_HEIGHT(a3)
        move.w  NW_MINWIDTH(a2),WD_MINWIDTH(a3)
        move.w  NW_MINHEIGHT(a2),WD_MINHEIGHT(a3)
        move.w  NW_MAXWIDTH(a2),WD_MAXWIDTH(a3)
        move.w  NW_MAXHEIGHT(a2),WD_MAXHEIGHT(a3)
        move.l  NW_FLAGS(a2),d0
        or.l    #WINDOWACTIVE,d0
        move.l  d0,WD_FLAGS(a3)
        move.l  NW_TITLE(a2),WD_TITLE(a3)
        move.l  NW_IDCMPFLAGS(a2),WD_IDCMPFLAGS(a3)
        move.l  a4,WD_WSCREEN(a3)
        move.b  NW_DETAILPEN(a2),d0  ; stylos : -1 = ceux de l'écran
        cmp.b   #-1,d0
        bne.s   .ow_dp
        move.b  SC_DETAILPEN(a4),d0
.ow_dp:
        move.b  d0,WD_DETAILPEN(a3)
        move.b  NW_BLOCKPEN(a2),d0
        cmp.b   #-1,d0
        bne.s   .ow_bp
        move.b  SC_BLOCKPEN(a4),d0
.ow_bp:
        move.b  d0,WD_BLOCKPEN(a3)
        ; bordures
        move.l  WD_FLAGS(a3),d1
        btst    #11,d1               ; BORDERLESS
        bne.s   .ow_bord
        move.b  SC_WBORLEFT(a4),WD_BORDERLEFT(a3)
        move.b  SC_WBORRIGHT(a4),WD_BORDERRIGHT(a3)
        move.b  SC_WBORTOP(a4),WD_BORDERTOP(a3)
        move.b  SC_WBORBOTTOM(a4),WD_BORDERBOTTOM(a3)
        tst.l   WD_TITLE(a3)
        bne.s   .ow_tbar
        move.l  d1,d0
        and.l   #WINDOWDRAG|WINDOWDEPTH|WINDOWCLOSE,d0
        beq.s   .ow_notbar
.ow_tbar:
        move.b  #WD_TBARH,WD_BORDERTOP(a3)
.ow_notbar:
        btst    #0,d1                ; WINDOWSIZING
        beq.s   .ow_bord
        btst    #5,d1                ; SIZEBBOTTOM
        beq.s   .ow_szr
        move.b  #9,WD_BORDERBOTTOM(a3)
        btst    #4,d1                ; SIZEBRIGHT en plus
        beq.s   .ow_bord
.ow_szr:
        move.b  #18,WD_BORDERRIGHT(a3)
.ow_bord:
        moveq   #0,d0                ; GZZWidth / GZZHeight = intérieur
        move.b  WD_BORDERLEFT(a3),d0
        moveq   #0,d1
        move.b  WD_BORDERRIGHT(a3),d1
        add.w   d0,d1
        move.w  d6,d0
        sub.w   d1,d0
        move.w  d0,WD_GZZWIDTH(a3)
        moveq   #0,d0
        move.b  WD_BORDERTOP(a3),d0
        moveq   #0,d1
        move.b  WD_BORDERBOTTOM(a3),d1
        add.w   d0,d1
        move.w  d7,d0
        sub.w   d1,d0
        move.w  d0,WD_GZZHEIGHT(a3)
        ; RastPort + couche
        move.l  IB_GFXBASE(a5),a6
        lea     WDX_RPORT(a3),a1
        jsr     LVO_INITRASTPORT(a6)
        lea     WDX_RPORT(a3),a1
        lea     SC_BITMAP(a4),a0
        move.l  a0,rp_BitMap(a1)
        lea     WDX_LAYER(a3),a0
        move.l  a0,rp_Layer(a1)
        move.l  a1,lr_rp(a0)
        move.l  a0,WD_WLAYER(a3)
        move.l  a1,WD_RPORT(a3)
        move.w  d4,lr_MinX(a0)
        move.w  d5,lr_MinY(a0)
        add.w   d6,d4
        subq.w  #1,d4
        move.w  d4,lr_MaxX(a0)
        add.w   d7,d5
        subq.w  #1,d5
        move.w  d5,lr_MaxY(a0)
        bsr     wn_drawframe
        move.l  ($4).w,a6
        jsr     LVO_FORBID(a6)
        move.l  SC_FIRSTWINDOW(a4),WD_NEXTWINDOW(a3)
        move.l  a3,SC_FIRSTWINDOW(a4)
        move.l  IB_ACTIVEWINDOW(a5),d0
        beq.s   .ow_noact
        move.l  d0,a0
        and.l   #~WINDOWACTIVE,WD_FLAGS(a0)
.ow_noact:
        move.l  a3,IB_ACTIVEWINDOW(a5)
        jsr     LVO_PERMIT(a6)
        move.l  a3,d0
        bra.s   .ow_ret
.ow_fail:
        moveq   #0,d0
.ow_ret:
        move.l  a5,a6
        movem.l (sp)+,d2-d7/a2-a5
        rts

; wn_drawframe(a3 = Window, a5 = IntuitionBase) : efface la fenêtre au stylo 0, puis (sauf BORDERLESS) cadre au
; stylo BlockPen, barre de titre pleine au stylo BlockPen avec le titre au stylo DetailPen, gadget de fermeture,
; gadgets de profondeur, gadget de redimensionnement. Clobbe d0-d7/a0/a1/a6.
wn_drawframe:
        move.l  IB_GFXBASE(a5),a6
        move.l  WD_RPORT(a3),a1
        moveq   #0,d0
        jsr     LVO_SETRAST(a6)
        move.l  WD_FLAGS(a3),d7      ; d7 = drapeaux
        btst    #11,d7
        bne     .df_ret
        move.w  WD_WIDTH(a3),d4
        subq.w  #1,d4                ; d4 = x max
        move.w  WD_HEIGHT(a3),d5
        subq.w  #1,d5                ; d5 = y max
        moveq   #0,d6
        move.b  WD_BLOCKPEN(a3),d6   ; d6 = stylo du cadre
        move.l  d6,d0
        jsr     LVO_SETAPEN(a6)
        moveq   #0,d0                ; bordures gauche/droite (2 pixels) et basse/haute (1 ligne)
        moveq   #0,d1
        move.w  d4,d2
        move.w  d5,d3
        bsr     it_box
        moveq   #1,d0
        moveq   #1,d1
        moveq   #1,d2
        move.w  d5,d3
        jsr     LVO_RECTFILL(a6)
        move.w  d4,d0
        subq.w  #1,d0
        moveq   #1,d1
        move.w  d0,d2
        move.w  d5,d3
        jsr     LVO_RECTFILL(a6)
        cmp.b   #WD_TBARH,WD_BORDERTOP(a3)
        bne     .df_size
        moveq   #0,d0                ; barre de titre
        moveq   #0,d1
        move.w  d4,d2
        moveq   #WD_TBARH-1,d3
        jsr     LVO_RECTFILL(a6)
        moveq   #4,d3                ; x du titre (après le gadget de fermeture s'il existe)
        btst    #3,d7                ; WINDOWCLOSE
        beq.s   .df_noclose
        moveq   #0,d0
        move.b  WD_DETAILPEN(a3),d0
        jsr     LVO_SETAPEN(a6)
        moveq   #4,d0
        moveq   #2,d1
        moveq   #15,d2
        moveq   #7,d3
        bsr     it_box
        moveq   #8,d0
        moveq   #4,d1
        moveq   #11,d2
        moveq   #5,d3
        jsr     LVO_RECTFILL(a6)
        moveq   #WD_CLOSEW+4,d3
.df_noclose:
        moveq   #0,d0
        move.b  WD_DETAILPEN(a3),d0
        move.l  d6,d1
        move.w  d4,d2
        sub.w   d3,d2
        btst    #2,d7                ; WINDOWDEPTH : place réservée aux gadgets
        beq.s   .df_tw
        sub.w   #2*SC_GADW,d2
.df_tw:
        move.l  WD_TITLE(a3),a0
        move.l  WD_RPORT(a3),a1
        bsr     it_title
        btst    #2,d7
        beq.s   .df_size
        move.w  d4,d2
        sub.w   #2*SC_GADW-1,d2
        moveq   #0,d3
        move.b  WD_DETAILPEN(a3),d3
        move.l  WD_RPORT(a3),a1
        bsr     it_depthgads
.df_size:
        btst    #0,d7                ; WINDOWSIZING : cadre dans le coin bas-droit
        beq.s   .df_ret
        move.l  WD_RPORT(a3),a1
        move.l  d6,d0
        jsr     LVO_SETAPEN(a6)
        move.w  d4,d0
        sub.w   #17,d0
        move.w  d5,d1
        subq.w  #8,d1
        move.w  d4,d2
        move.w  d5,d3
        jsr     LVO_RECTFILL(a6)
        moveq   #0,d0
        move.b  WD_DETAILPEN(a3),d0
        jsr     LVO_SETAPEN(a6)
        move.w  d4,d0
        sub.w   #13,d0
        move.w  d5,d1
        subq.w  #6,d1
        move.w  d4,d2
        subq.w  #4,d2
        move.w  d5,d3
        subq.w  #2,d3
        bsr     it_box
.df_ret:
        move.l  WD_RPORT(a3),a1      ; état de dessin rendu aux clients : JAM2, stylos 1/0
        moveq   #1,d0
        jsr     LVO_SETAPEN(a6)
        moveq   #0,d0
        jsr     LVO_SETBPEN(a6)
        moveq   #JAM2,d0
        jsr     LVO_SETDRMD(a6)
        rts

; CloseWindow(fenêtre a0) : retire la fenêtre de son écran, efface sa zone au stylo 0 et la libère.
intuition_CloseWindow:
        movem.l a3-a6,-(sp)
        move.l  a6,a5
        move.l  a0,a3
        move.l  a0,d0
        beq.s   .cw_ret
        move.l  ($4).w,a6
        jsr     LVO_FORBID(a6)
        move.l  WD_WSCREEN(a3),d0
        beq.s   .cw_unl
        move.l  d0,a0
        lea     SC_FIRSTWINDOW(a0),a0 ; maillon précédent (WD_NEXTWINDOW à l'offset 0)
.cw_find:
        move.l  (a0),d0
        beq.s   .cw_unl
        cmp.l   d0,a3
        beq.s   .cw_hit
        move.l  d0,a0
        bra.s   .cw_find
.cw_hit:
        move.l  WD_NEXTWINDOW(a3),(a0)
.cw_unl:
        cmp.l   IB_ACTIVEWINDOW(a5),a3
        bne.s   .cw_act
        clr.l   IB_ACTIVEWINDOW(a5)
.cw_act:
        jsr     LVO_PERMIT(a6)
        move.l  WD_RPORT(a3),d0
        beq.s   .cw_free
        move.l  d0,a1
        move.l  IB_GFXBASE(a5),a6
        moveq   #0,d0
        jsr     LVO_SETRAST(a6)
        move.l  ($4).w,a6
.cw_free:
        move.l  a3,a1
        move.l  #WDX_SIZE,d0
        jsr     LVO_FREEMEM(a6)
.cw_ret:
        movem.l (sp)+,a3-a6
        rts

; NewScreen du Workbench
sc_wbnewscreen:
        dc.w    0,0,640,256,2        ; LeftEdge, TopEdge, Width, Height, Depth
        dc.b    0,1                  ; DetailPen, BlockPen
        dc.w    V_HIRES              ; ViewModes
        dc.w    WBENCHSCREEN         ; Type
        dc.l    0                    ; Font
        dc.l    sc_wbtitle           ; DefaultTitle
        dc.l    0,0                  ; Gadgets, CustomBitMap
; palette par défaut : 4 couleurs des préférences 1.3 (bleu, blanc, noir, orange), puis couleurs de remplissage
; (16..19 : pointeur)
sc_palette:
        dc.w    $05A,$FFF,$002,$F80,$00F,$F0F,$0FF,$FFF
        dc.w    $620,$E50,$9F1,$EB0,$55F,$92F,$0F8,$CCC
        dc.w    $000,$E44,$000,$EEC,$444,$555,$666,$777
        dc.w    $888,$999,$AAA,$BBB,$CCC,$DDD,$EEE,$FFF
sc_wbtitle:
        dc.b    "Workbench Screen",0
        even
