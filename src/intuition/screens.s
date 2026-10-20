; src/intuition/screens.s — écrans et fenêtres d'intuition.library : OpenScreen/CloseScreen, OpenWorkBench,
; GetScreenData, OpenWindow/CloseWindow, WindowToFront/WindowToBack, MoveWindow, SizeWindow, WindowLimits,
; BeginRefresh/EndRefresh, menus (SetMenuStrip/ClearMenuStrip/ItemAddress/OnMenu/OffMenu).
; Un écran = struct Screen (V34) + BitMap en chip RAM + ColorMap + son Layer_Info (sc_LayerInfo) ; l'écran de tête
; est affiché via le View d'IntuitionBase (ib_ViewLord : MakeVPort/MrgCop/LoadView). La barre de titre de l'écran est
; une couche simple « backdrop » (sc_BarLayer). Chaque fenêtre est une couche de layers.library (simple, smart ou
; super selon ses drapeaux ; backdrop pour BACKDROP) : son RPort est celui de la couche, le recouvrement et la
; sauvegarde des fenêtres smart sont gérés par layers. Après une opération sur les couches, it_refresh redessine les
; bordures abîmées et envoie REFRESHWINDOW aux fenêtres qui l'ont demandé (sinon les dommages sont effacés).
; La liste des fenêtres de l'écran suit l'ordre des couches (it_relist). Les boutons de la souris sont traités par
; une tâche d'entrée (it_intask) : gadgets système (fermeture, profondeur, déplacement, taille) et menus.
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
                xdef    intuition_DrawImage
                xdef    intuition_AllocRemember
                xdef    intuition_FreeRemember
                xdef    intuition_DoubleClick
                xdef    it_event
                xdef    it_refresh           ; menus.s
                xdef    it_title
                xdef    it_box
                xdef    it_scrxy
                xdef    wn_sendmsg
                xref    it_menubutton        ; menus.s : bouton droit
                xref    it_menumove
                xdef    it_startinput
                xdef    intuition_SizeWindow
                xdef    intuition_WindowLimits
                xdef    intuition_WindowToFront
                xdef    intuition_WindowToBack
                xdef    intuition_MoveWindow
                xdef    intuition_BeginRefresh
                xdef    intuition_EndRefresh

; extension privée derrière la struct Screen (même allocation)
SCX_RASINFO     EQU SC_SIZEOF        ; struct RasInfo (12)
SCX_COLORMAP    EQU SCX_RASINFO+ri_SIZEOF   ; struct ColorMap (8)
SCX_COLORTAB    EQU SCX_COLORMAP+GCM_SIZEOF ; 32 couleurs
SCX_PLANESIZE   EQU SCX_COLORTAB+64  ; taille d'un plan alloué ici (0 : BitMap fournie par l'appelant)
SCX_SIZE        EQU SCX_PLANESIZE+4
SC_MAXCOLORS    EQU 32
SC_BARH         EQU 9                ; BarHeight : la barre de titre couvre les lignes 0..9
SC_GADW         EQU 23               ; largeur d'un gadget de profondeur
SC_BGCOLOR      EQU $7C3             ; couleur 0 : vert pomme (thème AmigaSlopDOS)
; fenêtre : struct Window + messages IDCMP (même allocation) ; RastPort et couche viennent de layers.library
WDX_IMSG        EQU WD_SIZE          ; IntuiMessage REFRESHWINDOW (réutilisé une fois répondu)
WDX_EMSG        EQU WDX_IMSG+IM_SIZEOF  ; IntuiMessages des événements (boutons, fermeture), réutilisés une fois répondus
WDX_NEMSG       EQU 4
WDX_SIZE        EQU WDX_EMSG+WDX_NEMSG*IM_SIZEOF
WD_TBARH        EQU 10               ; hauteur de la barre de titre d'une fenêtre (BorderTop)
WD_CLOSEW       EQU 20               ; largeur du gadget de fermeture

; OpenScreen(newscreen a0) -> d0 = Screen | 0. Alloue la struct, la BitMap (plans chip effacés, sauf CUSTOMBITMAP),
; la palette par défaut (32 couleurs, dont celles du pointeur), dessine la barre de titre (sauf SCREENQUIET), place
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
        ; palette : 32 couleurs quelle que soit la profondeur (les couleurs 17-19 sont celles du pointeur)
        move.w  #SC_MAXCOLORS,SCX_COLORMAP+cm_Count(a3)
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
        move.l  IB_LAYERSBASE(a5),a6
        lea     SC_LAYERINFO(a3),a0
        jsr     LVO_INITLAYERS(a6)
        move.w  SC_FLAGS(a3),d0
        and.w   #SCREENQUIET,d0
        bne.s   .os_quiet
        move.l  a2,-(sp)             ; barre de titre : couche simple backdrop, derrière les fenêtres
        lea     SC_LAYERINFO(a3),a0
        lea     SC_BITMAP(a3),a1
        moveq   #0,d0
        moveq   #0,d1
        move.w  SC_WIDTH(a3),d2
        subq.w  #1,d2
        moveq   #SC_BARH,d3
        moveq   #IL_SIMPLE|IL_BACKDROP,d4
        suba.l  a2,a2
        jsr     LVO_CREATEBEHINDLAYER(a6)
        move.l  (sp)+,a2
        move.l  d0,SC_BARLAYER(a3)
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
        move.l  SC_BARLAYER(a3),d0   ; dans la couche de barre quand elle existe (recouvrement par les fenêtres)
        beq.s   .db_rp
        move.l  d0,a1
        move.l  IL_RP(a1),a1
.db_rp:
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
        move.l  SC_BARLAYER(a3),d0
        beq.s   .cs_nobar
        move.l  d0,a1
        suba.l  a0,a0
        move.l  IB_LAYERSBASE(a5),a6
        jsr     LVO_DELETELAYER(a6)
.cs_nobar:
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
        bsr     wn_gzz
        lea     WD_MINWIDTH(a3),a0   ; limites nulles : taille courante (AutoDoc OpenWindow)
        moveq   #3,d1
.ow_lim:
        tst.w   (a0)
        bne.s   .ow_limok
        move.w  d6,(a0)
        btst    #0,d1
        bne.s   .ow_limok
        move.w  d7,(a0)
.ow_limok:
        addq.l  #2,a0
        dbra    d1,.ow_lim
        move.l  ($4).w,a6
        tst.l   WD_IDCMPFLAGS(a3)
        beq.s   .ow_noport
        bsr     wn_mkport            ; port IDCMP (signal de la tâche appelante)
        tst.l   WD_USERPORT(a3)
        beq     .ow_nolayer          ; pas de port : échec
.ow_noport:
        ; couche : simple / smart / super selon les drapeaux, backdrop pour BACKDROP (derrière les autres)
        movem.l d4-d7/a2,-(sp)
        move.w  d4,d0
        move.w  d5,d1
        move.w  d4,d2
        add.w   d6,d2
        subq.w  #1,d2
        move.w  d5,d3
        add.w   d7,d3
        subq.w  #1,d3
        move.l  WD_FLAGS(a3),d5
        suba.l  a1,a1                ; a1 = SuperBitMap éventuelle
        moveq   #IL_SMART,d4
        moveq   #$C0,d6              ; type de rafraîchissement
        and.l   d5,d6
        cmp.b   #$40,d6              ; SIMPLE_REFRESH
        bne.s   .ow_nsimple
        moveq   #IL_SIMPLE,d4
.ow_nsimple:
        cmp.b   #$80,d6              ; SUPER_BITMAP
        bne.s   .ow_nsuper
        moveq   #IL_SMART|IL_SUPER,d4
        move.l  NW_BITMAP(a2),a1
.ow_nsuper:
        move.l  a1,a2
        lea     SC_LAYERINFO(a4),a0
        lea     SC_BITMAP(a4),a1
        move.l  IB_LAYERSBASE(a5),a6
        btst    #8,d5                ; BACKDROP ($100)
        bne.s   .ow_behind
        jsr     LVO_CREATEUPFRONTLAYER(a6)
        bra.s   .ow_lay
.ow_behind:
        or.w    #IL_BACKDROP,d4
        jsr     LVO_CREATEBEHINDLAYER(a6)
.ow_lay:
        movem.l (sp)+,d4-d7/a2
        move.l  ($4).w,a6
        tst.l   d0
        bne.s   .ow_haslayer
        bsr     wn_freeport
.ow_nolayer:
        move.l  a3,a1
        move.l  #WDX_SIZE,d0
        jsr     LVO_FREEMEM(a6)
        bra     .ow_fail
.ow_haslayer:
        move.l  d0,a0
        move.l  a0,WD_WLAYER(a3)
        move.l  a3,IL_WINDOW(a0)
        move.l  IL_RP(a0),WD_RPORT(a3)
        bsr     it_relist
        btst    #0,WD_FLAGS+2(a3)    ; une fenêtre BACKDROP ne devient pas active
        bne.s   .ow_linked
        jsr     LVO_FORBID(a6)
        move.l  IB_ACTIVEWINDOW(a5),d0
        beq.s   .ow_noact
        move.l  d0,a0
        and.l   #~WINDOWACTIVE,WD_FLAGS(a0)
.ow_noact:
        move.l  a3,IB_ACTIVEWINDOW(a5)
        jsr     LVO_PERMIT(a6)
.ow_linked:
        bsr     wn_border
        move.l  a3,d0
        bra.s   .ow_ret
.ow_fail:
        moveq   #0,d0
.ow_ret:
        move.l  a5,a6
        movem.l (sp)+,d2-d7/a2-a5
        rts

; wn_border(a3 = Window, a5 = IntuitionBase) : sauf BORDERLESS, cadre au stylo BlockPen, barre de titre pleine au
; stylo BlockPen avec le titre au stylo DetailPen, gadget de fermeture, gadgets de profondeur, gadget de
; redimensionnement ; puis état de dessin JAM2, stylos 1/0. Clobbe d0-d7/a0/a1/a6.
wn_border:
        move.l  IB_GFXBASE(a5),a6
        move.l  WD_RPORT(a3),a1
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

; CloseWindow(fenêtre a0) : supprime sa couche (layers rend la zone aux couches de derrière et au fond), la retire de
; son écran, redessine ce qui a été abîmé (it_refresh), puis libère son port IDCMP et la fenêtre.
intuition_CloseWindow:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  a6,a5
        move.l  a0,a3
        move.l  a0,d0
        beq.s   .cw_ret
        move.l  WD_WSCREEN(a3),a4    ; a4 = écran
        move.l  IB_LAYERSBASE(a5),a6
        suba.l  a0,a0
        move.l  WD_WLAYER(a3),a1
        jsr     LVO_DELETELAYER(a6)
        move.l  ($4).w,a6
        bsr     it_relist
        cmp.l   IB_ACTIVEWINDOW(a5),a3
        bne.s   .cw_act
        clr.l   IB_ACTIVEWINDOW(a5)
.cw_act:
        bsr     it_refresh
        move.l  ($4).w,a6
        bsr     wn_freeport
        move.l  a3,a1
        move.l  #WDX_SIZE,d0
        jsr     LVO_FREEMEM(a6)
.cw_ret:
        movem.l (sp)+,d2-d7/a2-a6
        rts

; it_relist(a4 = écran) : la liste des fenêtres (sc_FirstWindow / wd_NextWindow) reprend l'ordre des couches, de
; l'avant vers l'arrière (couches sans fenêtre, comme la barre, ignorées). Préserve tout sauf d0/a0/a1.
it_relist:
        move.l  a6,-(sp)
        move.l  ($4).w,a6
        jsr     LVO_FORBID(a6)
        lea     SC_FIRSTWINDOW(a4),a1    ; maillon à remplir (wd_NextWindow est à l'offset 0)
        move.l  SC_LAYERINFO(a4),a0      ; top_layer
.rl_lp:
        cmpa.w  #0,a0
        beq.s   .rl_end
        move.l  IL_WINDOW(a0),d0
        beq.s   .rl_n
        move.l  d0,(a1)
        move.l  d0,a1
.rl_n:
        move.l  4(a0),a0                 ; couche suivante (back)
        bra.s   .rl_lp
.rl_end:
        clr.l   (a1)
        jsr     LVO_PERMIT(a6)
        move.l  (sp)+,a6
        rts

; it_refresh(a4 = écran, a5 = IntuitionBase) : barre et fenêtres dont la couche est abîmée (LAYERREFRESH). La barre
; est redessinée dans sa zone abîmée. Une fenêtre voit sa bordure redessinée dans sa zone abîmée ; si elle a demandé
; REFRESHWINDOW, ses dommages restent pour son propriétaire (BeginRefresh/EndRefresh) et le message lui est envoyé,
; sinon ils sont effacés. Préserve d2-d7/a2-a6.
it_refresh:
        movem.l d2-d7/a2-a3/a6,-(sp)
        move.l  SC_BARLAYER(a4),d0
        beq.s   .ir_wins
        move.l  d0,a2
        btst    #ILB_REFRESH,IL_FLAGS+1(a2)
        beq.s   .ir_wins
        move.l  IB_LAYERSBASE(a5),a6
        move.l  a2,a0
        jsr     LVO_BEGINUPDATE(a6)
        move.l  a4,a3
        bsr     sc_drawbar
        move.l  IB_LAYERSBASE(a5),a6
        move.l  a2,a0
        moveq   #1,d0
        jsr     LVO_ENDUPDATE(a6)
.ir_wins:
        move.l  SC_FIRSTWINDOW(a4),a3
.ir_lp:
        cmpa.w  #0,a3
        beq.s   .ir_r
        move.l  WD_WLAYER(a3),a2
        btst    #ILB_REFRESH,IL_FLAGS+1(a2)
        beq.s   .ir_n
        move.l  IB_LAYERSBASE(a5),a6
        move.l  a2,a0
        jsr     LVO_BEGINUPDATE(a6)
        bsr     wn_border
        moveq   #1,d2                ; d2 = dommages à effacer ?
        tst.l   WD_USERPORT(a3)
        beq.s   .ir_end
        moveq   #REFRESHWINDOW,d0
        and.l   WD_IDCMPFLAGS(a3),d0
        beq.s   .ir_end
        moveq   #0,d2                ; gardés : le propriétaire redessine
.ir_end:
        move.l  IB_LAYERSBASE(a5),a6
        move.l  a2,a0
        move.l  d2,d0
        jsr     LVO_ENDUPDATE(a6)
        tst.l   d2
        bne.s   .ir_n
        bsr     wn_refreshmsg
.ir_n:
        move.l  WD_NEXTWINDOW(a3),a3
        bra.s   .ir_lp
.ir_r:
        movem.l (sp)+,d2-d7/a2-a3/a6
        rts

; WindowToFront(fenêtre a0) / WindowToBack(fenêtre a0) : couche devant / derrière (une fenêtre BACKDROP reste
; derrière les autres), liste des fenêtres remise dans l'ordre, zones abîmées redessinées.
intuition_WindowToFront:
        moveq   #LVO_UPFRONTLAYER,d1
        bra.s   wn_depth
intuition_WindowToBack:
        moveq   #LVO_BEHINDLAYER,d1
wn_depth:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  a6,a5
        move.l  a0,a3
        move.l  WD_WSCREEN(a3),a4
        move.l  IB_LAYERSBASE(a5),a6
        suba.l  a0,a0
        move.l  WD_WLAYER(a3),a1
        jsr     0(a6,d1.w)
        bsr     it_relist
        bsr     it_refresh
        movem.l (sp)+,d2-d7/a2-a6
        rts

; MoveWindow(fenêtre a0, dx d0, dy d1) : déplacement borné à l'écran, puis zones abîmées redessinées.
intuition_MoveWindow:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  a6,a5
        move.l  a0,a3
        move.l  WD_WSCREEN(a3),a4
        move.w  WD_LEFTEDGE(a3),d2   ; nouvelle position bornée : 0 .. taille de l'écran - taille de la fenêtre
        add.w   d0,d2
        bpl.s   .mw_x0
        moveq   #0,d2
.mw_x0:
        move.w  SC_WIDTH(a4),d3
        sub.w   WD_WIDTH(a3),d3
        cmp.w   d3,d2
        ble.s   .mw_x1
        move.w  d3,d2
.mw_x1:
        move.w  WD_TOPEDGE(a3),d3
        add.w   d1,d3
        bpl.s   .mw_y0
        moveq   #0,d3
.mw_y0:
        move.w  SC_HEIGHT(a4),d4
        sub.w   WD_HEIGHT(a3),d4
        cmp.w   d4,d3
        ble.s   .mw_y1
        move.w  d4,d3
.mw_y1:
        move.w  d2,d0
        sub.w   WD_LEFTEDGE(a3),d0
        move.w  d3,d1
        sub.w   WD_TOPEDGE(a3),d1
        move.w  d2,WD_LEFTEDGE(a3)
        move.w  d3,WD_TOPEDGE(a3)
        ext.l   d0
        ext.l   d1
        move.l  IB_LAYERSBASE(a5),a6
        suba.l  a0,a0
        move.l  WD_WLAYER(a3),a1
        jsr     LVO_MOVELAYER(a6)
        bsr     it_refresh
        movem.l (sp)+,d2-d7/a2-a6
        rts

; BeginRefresh(fenêtre a0) / EndRefresh(fenêtre a0, complet d0) : BeginUpdate / EndUpdate de sa couche.
intuition_BeginRefresh:
        move.l  a6,-(sp)
        move.l  WD_WLAYER(a0),a0
        move.l  IB_LAYERSBASE(a6),a6
        jsr     LVO_BEGINUPDATE(a6)
        move.l  (sp)+,a6
        rts
intuition_EndRefresh:
        move.l  a6,-(sp)
        move.l  WD_WLAYER(a0),a0
        move.l  IB_LAYERSBASE(a6),a6
        jsr     LVO_ENDUPDATE(a6)
        move.l  (sp)+,a6
        rts

; wn_refreshmsg(a3 = fenêtre) : si elle a demandé REFRESHWINDOW et que son message n'est pas en attente, le lui
; envoie (sans port de réponse : ReplyMsg le marque répondu, il est réutilisé). Préserve d2-d7/a2-a6.
wn_refreshmsg:
        move.l  WD_USERPORT(a3),d0
        beq.s   .rf_ret
        moveq   #REFRESHWINDOW,d1
        and.l   WD_IDCMPFLAGS(a3),d1
        beq.s   .rf_ret
        lea     WDX_IMSG(a3),a1
        cmp.b   #NT_MESSAGE,LN_TYPE(a1)
        beq.s   .rf_ret              ; le précédent n'a pas été lu : il suffit
        move.l  a6,-(sp)
        move.l  d0,-(sp)
        move.b  #NT_MESSAGE,LN_TYPE(a1)
        clr.l   MN_REPLYPORT(a1)
        move.w  #IM_SIZEOF,MN_LENGTH(a1)
        move.l  #REFRESHWINDOW,IM_CLASS(a1)
        clr.l   IM_CODE(a1)
        move.l  a3,IM_IADDRESS(a1)
        move.l  a3,IM_IDCMPWINDOW(a1)
        move.l  (sp)+,a0
        move.l  ($4).w,a6
        jsr     LVO_PUTMSG(a6)
        move.l  (sp)+,a6
.rf_ret:
        rts

; wn_mkport(a3 = fenêtre, a6 = SysBase) : port IDCMP (WD_USERPORT) signalant la tâche appelante ; laissé à 0 si
; plus de signal ou de mémoire. Préserve d2-d7/a2-a6.
wn_mkport:
        move.l  a2,-(sp)
        moveq   #-1,d0
        jsr     LVO_ALLOCSIGNAL(a6)
        tst.b   d0
        bmi.s   .mp_ret
        move.l  d0,-(sp)
        moveq   #MP_SIZE,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  (sp)+,d1
        tst.l   d0
        bne.s   .mp_ok
        move.l  d1,d0
        jsr     LVO_FREESIGNAL(a6)
        bra.s   .mp_ret
.mp_ok:
        move.l  d0,a2
        move.b  #NT_MSGPORT,LN_TYPE(a2)
        move.b  #PA_SIGNAL,MP_FLAGS(a2)
        move.b  d1,MP_SIGBIT(a2)
        move.l  EB_THISTASK(a6),MP_SIGTASK(a2)
        lea     MP_MSGLIST(a2),a0    ; NEWLIST
        move.l  a0,8(a0)
        addq.l  #4,a0
        move.l  a0,-4(a0)
        move.l  a2,WD_USERPORT(a3)
.mp_ret:
        move.l  (sp)+,a2
        rts

; wn_freeport(a3 = fenêtre, a6 = SysBase) : retire du port le message en attente éventuel, libère le signal et le port.
; Préserve d2-d7/a2-a6.
wn_freeport:
        move.l  WD_USERPORT(a3),d0
        beq.s   .fp_ret
        move.l  a2,-(sp)
        move.l  d0,a2
        jsr     LVO_DISABLE(a6)
        move.l  d2,-(sp)
        lea     WDX_IMSG(a3),a1      ; messages encore en file : retirés avant de libérer la fenêtre
        moveq   #WDX_NEMSG,d2
.fp_lp:
        cmp.b   #NT_MESSAGE,LN_TYPE(a1)
        bne.s   .fp_nomsg
        move.l  a1,-(sp)
        jsr     LVO_REMOVE(a6)
        move.l  (sp)+,a1
.fp_nomsg:
        lea     IM_SIZEOF(a1),a1
        dbra    d2,.fp_lp
        move.l  (sp)+,d2
        jsr     LVO_ENABLE(a6)
        moveq   #0,d0
        move.b  MP_SIGBIT(a2),d0
        jsr     LVO_FREESIGNAL(a6)
        move.l  a2,a1
        moveq   #MP_SIZE,d0
        jsr     LVO_FREEMEM(a6)
        move.l  (sp)+,a2
.fp_ret:
        rts

; DrawImage(rp a0, image a1, x d0, y d1) : dessine la chaîne d'Images (struct Image) à (x + LeftEdge, y + TopEdge).
; Chaque Image devient une BitMap temporaire de 8 plans : plan d'image i -> i-ème plan désigné par PlanePick, les autres
; plans valent 0 ou 1 selon PlaneOnOff (pointeurs NULL / -1) ; un seul BltBitMapRastPort la copie dans le RastPort.
intuition_DrawImage:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  IB_GFXBASE(a6),a6
        move.l  a0,a2                ; a2 = RastPort
        move.l  a1,a3                ; a3 = Image courante
        movem.w d0-d1,-(sp)          ; (sp) = x, 2(sp) = y de base
        lea     -bm_SIZEOF(sp),sp
        move.l  sp,a4                ; a4 = BitMap temporaire
.di_img:
        move.l  a3,d0
        beq     .di_done
        move.w  IG_WIDTH(a3),d0      ; octets par ligne = mots entiers
        add.w   #15,d0
        lsr.w   #4,d0
        add.w   d0,d0
        move.w  d0,bm_BytesPerRow(a4)
        move.w  IG_HEIGHT(a3),bm_Rows(a4)
        move.b  #8,bm_Depth(a4)
        mulu    IG_HEIGHT(a3),d0     ; d0 = taille d'un plan d'image
        move.l  IG_IMAGEDATA(a3),a0
        moveq   #0,d1                ; d1 = plan de la BitMap
        moveq   #0,d2                ; d2 = plans d'image consommés
        lea     bm_Planes(a4),a1
.di_plane:
        btst    d1,IG_PLANEPICK(a3)
        beq.s   .di_onoff
        cmp.w   IG_DEPTH(a3),d2
        bge.s   .di_zero             ; plan choisi sans données : 0
        move.l  a0,(a1)+
        add.l   d0,a0
        addq.w  #1,d2
        bra.s   .di_pnext
.di_onoff:
        btst    d1,IG_PLANEONOFF(a3)
        beq.s   .di_zero
        move.l  #-1,(a1)+
        bra.s   .di_pnext
.di_zero:
        clr.l   (a1)+
.di_pnext:
        addq.w  #1,d1
        cmp.w   #8,d1
        blo.s   .di_plane
        move.l  a4,a0                ; BltBitMapRastPort(bm, 0, 0, rp, x, y, l, h, copie)
        moveq   #0,d0
        moveq   #0,d1
        move.l  a2,a1
        move.w  bm_SIZEOF(sp),d2
        add.w   IG_LEFTEDGE(a3),d2
        move.w  bm_SIZEOF+2(sp),d3
        add.w   IG_TOPEDGE(a3),d3
        move.w  IG_WIDTH(a3),d4
        move.w  IG_HEIGHT(a3),d5
        move.l  #$C0,d6
        jsr     LVO_BLTBITMAPRASTPORT(a6)
        move.l  IG_NEXTIMAGE(a3),a3
        bra     .di_img
.di_done:
        lea     bm_SIZEOF+4(sp),sp
        movem.l (sp)+,d2-d7/a2-a6
        rts

; AllocRemember(clé a0, taille d0, drapeaux d1) -> d0 = mémoire | 0 : alloue et chaîne un nœud Remember en tête de
; *clé. FreeRemember(clé a0, oublier d0) : libère les nœuds (et leur mémoire si oublier != 0), *clé := 0.
intuition_AllocRemember:
        movem.l d2-d3/a2/a6,-(sp)
        move.l  a0,a2
        move.l  d0,d2
        move.l  d1,d3
        move.l  ($4).w,a6
        moveq   #RM_SIZEOF,d0
        moveq   #MEMF_PUBLIC,d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.s   .ar_ret
        move.l  d0,-(sp)
        move.l  d2,d0
        move.l  d3,d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  (sp)+,a1
        tst.l   d0
        bne.s   .ar_ok
        moveq   #RM_SIZEOF,d0        ; mémoire refusée : rend le nœud
        jsr     LVO_FREEMEM(a6)
        moveq   #0,d0
        bra.s   .ar_ret
.ar_ok:
        move.l  (a2),RM_NEXTREMEMBER(a1)
        move.l  d2,RM_REMEMBERSIZE(a1)
        move.l  d0,RM_MEMORY(a1)
        move.l  a1,(a2)
.ar_ret:
        movem.l (sp)+,d2-d3/a2/a6
        rts
intuition_FreeRemember:
        movem.l d2/a2-a3/a6,-(sp)
        move.l  a0,a2
        move.l  d0,d2
        move.l  ($4).w,a6
        move.l  (a2),a3
.fr_lp:
        move.l  a3,d0
        beq.s   .fr_done
        tst.l   d2
        beq.s   .fr_node
        move.l  RM_MEMORY(a3),a1
        move.l  RM_REMEMBERSIZE(a3),d0
        jsr     LVO_FREEMEM(a6)
.fr_node:
        move.l  a3,a1
        move.l  RM_NEXTREMEMBER(a3),a3
        moveq   #RM_SIZEOF,d0
        jsr     LVO_FREEMEM(a6)
        bra.s   .fr_lp
.fr_done:
        clr.l   (a2)
        movem.l (sp)+,d2/a2-a3/a6
        rts

; it_event(d0.w = ie_Code) : appelé par le handler de pointeur (interruption VBlank) pour chaque RAWMOUSE, après la
; mise à jour de PTR_X/PTR_Y. Un bouton est déposé dans l'anneau avec la position du pointeur (anneau plein : perdu) ;
; un mouvement n'est signalé que si la tâche d'entrée suit le pointeur (geste ou menu en cours). Tout le traitement
; (fenêtres, couches, menus) se fait dans la tâche : rien ici ne peut attendre. Préserve tout.
it_event:
        movem.l d0-d1/a0-a1/a6,-(sp)
        move.l  INT_IBASE,d1
        beq.s   .ev_ret
        move.l  d1,a1
        tst.l   IB_INSIG(a1)
        beq.s   .ev_ret              ; tâche pas encore prête
        cmp.w   #IECODE_NOBUTTON,d0
        bne.s   .ev_btn
        tst.b   IB_TRACK(a1)
        beq.s   .ev_ret
        st      IB_MOVED(a1)
        bra.s   .ev_sig
.ev_btn:
        move.w  IB_EVHEAD(a1),d1
        lea     IB_EVRING(a1),a0
        add.w   d1,a0
        addq.w  #IB_EVSZ,d1
        cmp.w   #IB_EVN*IB_EVSZ,d1
        blo.s   .ev_wrap
        moveq   #0,d1
.ev_wrap:
        cmp.w   IB_EVTAIL(a1),d1
        beq.s   .ev_ret
        move.w  d0,(a0)+
        move.w  PTR_X,(a0)+
        move.w  PTR_Y,(a0)
        move.w  d1,IB_EVHEAD(a1)     ; publiée après les données
.ev_sig:
        move.l  IB_INSIG(a1),d0
        move.l  IB_INTASK(a1),a1
        move.l  ($4).w,a6
        jsr     LVO_SIGNAL(a6)
.ev_ret:
        movem.l (sp)+,d0-d1/a0-a1/a6
        rts

; it_startinput(a2 = IntuitionBase, a6 = SysBase) : crée la tâche d'entrée (pri 20, comme celle d'input.device).
; Sans mémoire : pas de tâche, les boutons sont ignorés. Préserve d2-d7/a2-a6.
IT_STACK        EQU 4096
it_startinput:
        movem.l a2-a4,-(sp)
        move.l  #TC_SIZE,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.s   .si_ret
        move.l  d0,a4
        move.l  #IT_STACK,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        bne.s   .si_stk
        move.l  a4,a1
        move.l  #TC_SIZE,d0
        jsr     LVO_FREEMEM(a6)
        bra.s   .si_ret
.si_stk:
        move.l  d0,TC_SPLOWER(a4)
        add.l   #IT_STACK,d0
        move.l  d0,TC_SPUPPER(a4)
        lea     it_inname(pc),a0
        move.l  a0,LN_NAME(a4)
        move.b  #20,LN_PRI(a4)
        move.l  #SYS_SIGALLOC,TC_SIGALLOC(a4)
        move.l  a4,a1
        lea     it_intask(pc),a2
        move.l  a2,a3                ; ne revient jamais
        jsr     LVO_ADDTASK(a6)
.si_ret:
        movem.l (sp)+,a2-a4
        rts
it_inname:
        dc.b    "intuition input",0
        even

; it_intask : corps de la tâche d'entrée. Alloue son signal et se publie, puis traite dans l'ordre les boutons de
; l'anneau et, quand elle suit le pointeur, son dernier mouvement.
it_intask:
        move.l  ($4).w,a6
        move.l  INT_IBASE,a5
        moveq   #-1,d0
        jsr     LVO_ALLOCSIGNAL(a6)
        moveq   #0,d1
        bset    d0,d1
        move.l  EB_THISTASK(a6),IB_INTASK(a5)
        move.l  d1,IB_INSIG(a5)
.in_wait:
        move.l  IB_INSIG(a5),d0
        move.l  ($4).w,a6
        jsr     LVO_WAIT(a6)
.in_next:
        move.w  IB_EVTAIL(a5),d1
        cmp.w   IB_EVHEAD(a5),d1
        beq.s   .in_move
        lea     IB_EVRING(a5),a0
        add.w   d1,a0
        move.w  (a0)+,d0             ; code
        move.w  (a0)+,d4             ; x, y (pointeur)
        move.w  (a0),d5
        addq.w  #IB_EVSZ,d1
        cmp.w   #IB_EVN*IB_EVSZ,d1
        blo.s   .in_wrap
        moveq   #0,d1
.in_wrap:
        move.w  d1,IB_EVTAIL(a5)
        bsr     it_dobutton
        bra.s   .in_next
.in_move:
        tst.b   IB_MOVED(a5)
        beq.s   .in_wait
        clr.b   IB_MOVED(a5)
        move.w  PTR_X,d4
        move.w  PTR_Y,d5
        bsr     it_domove
        bra.s   .in_next

; it_scrxy(a5, d4.w/d5.w = pointeur) -> a4 = écran de tête, d4/d5 = position dans cet écran (HIRES : x doublé) ;
; Z = 1 s'il n'y a pas d'écran. Clobbe d0.
it_scrxy:
        move.l  IB_FIRSTSCREEN(a5),d0
        beq.s   .sx_ret
        move.l  d0,a4
        tst.w   SC_VIEWPORT+vp_Modes(a4)
        bpl.s   .sx_lo
        add.w   d4,d4
.sx_lo:
        moveq   #1,d0                ; Z = 0
.sx_ret:
        rts

; it_winat(a4 = écran, d4/d5 = position) -> a3 = fenêtre la plus en avant sous le point, d2/d3 = position relative ;
; Z = 1 si aucune. Clobbe d0.
it_winat:
        move.l  SC_FIRSTWINDOW(a4),a3
.wa_lp:
        move.l  a3,d0
        beq.s   .wa_ret
        move.w  d4,d2
        sub.w   WD_LEFTEDGE(a3),d2
        bmi.s   .wa_nxt
        cmp.w   WD_WIDTH(a3),d2
        bge.s   .wa_nxt
        move.w  d5,d3
        sub.w   WD_TOPEDGE(a3),d3
        bmi.s   .wa_nxt
        cmp.w   WD_HEIGHT(a3),d3
        blt.s   .wa_hit
.wa_nxt:
        move.l  WD_NEXTWINDOW(a3),a3
        bra.s   .wa_lp
.wa_hit:
        moveq   #1,d0                ; Z = 0
.wa_ret:
        rts

; it_dobutton(a5 = IntuitionBase, d0.w = code, d4/d5 = pointeur) : contexte tâche d'entrée. Bouton gauche enfoncé
; sur une fenêtre : elle devient active (y compris une fenêtre BACKDROP, pour ses menus) ; gadget de fermeture -> CLOSEWINDOW, gadgets de profondeur -> derrière /
; devant, barre de titre (WINDOWDRAG) ou gadget de taille -> geste avec cadre fantôme ; sinon MOUSEBUTTONS. Le
; relâchement termine un geste en cours. Bouton droit : menus. Préserve a5.
it_dobutton:
        move.w  d0,d7                ; d7 = code
        bsr     it_scrxy
        beq     .db_ret
        tst.l   IB_DRAGWIN(a5)
        beq.s   .db_free
        cmp.w   #IECODE_LBUTTON|IECODE_UP_PREFIX,d7
        bne     .db_ret
        bra     it_dragend
.db_free:
        move.w  d7,d0
        and.w   #~IECODE_UP_PREFIX,d0
        cmp.w   #IECODE_RBUTTON,d0
        beq     it_menubutton
        tst.l   IB_MENUWIN(a5)
        bne     .db_ret              ; menus affichés : le bouton gauche est ignoré
        bsr     it_winat
        beq     .db_ret
        cmp.w   #IECODE_LBUTTON,d7
        bne     .db_mb
        move.l  IB_ACTIVEWINDOW(a5),d0   ; la fenêtre cliquée devient active (BACKDROP compris : ses menus)
        beq.s   .db_set
        move.l  d0,a0
        and.l   #~WINDOWACTIVE,WD_FLAGS(a0)
.db_set:
        or.l    #WINDOWACTIVE,WD_FLAGS(a3)
        move.l  a3,IB_ACTIVEWINDOW(a5)
        btst    #3,WD_FLAGS+2(a3)    ; BORDERLESS : aucun gadget système
        bne     .db_mb
        cmp.b   #WD_TBARH,WD_BORDERTOP(a3)
        bne.s   .db_size
        cmp.w   #WD_TBARH,d3
        bge.s   .db_size
        btst    #3,WD_FLAGS+3(a3)    ; WINDOWCLOSE
        beq.s   .db_nclose
        cmp.w   #WD_CLOSEW+3,d2
        bgt.s   .db_nclose
        move.l  #CLOSEWINDOW,d0
        moveq   #0,d1
        bra     wn_sendmsg
.db_nclose:
        btst    #2,WD_FLAGS+3(a3)    ; WINDOWDEPTH : [W-2G, W-G-1] derrière, [W-G, W-1] devant
        beq.s   .db_ndepth
        move.w  WD_WIDTH(a3),d0
        sub.w   #2*SC_GADW,d0
        cmp.w   d0,d2
        blt.s   .db_ndepth
        add.w   #SC_GADW,d0
        move.l  a3,a0
        move.l  a5,a6
        cmp.w   d0,d2
        bge     intuition_WindowToFront
        bra     intuition_WindowToBack
.db_ndepth:
        btst    #1,WD_FLAGS+3(a3)    ; WINDOWDRAG
        beq.s   .db_mb
        moveq   #IT_DRAGMOVE,d0
        bra     it_dragstart
.db_size:
        btst    #0,WD_FLAGS+3(a3)    ; WINDOWSIZING : gadget dans le coin bas-droit (18 x 9)
        beq.s   .db_mb
        move.w  WD_WIDTH(a3),d0
        sub.w   #18,d0
        cmp.w   d0,d2
        blt.s   .db_mb
        move.w  WD_HEIGHT(a3),d0
        sub.w   #9,d0
        cmp.w   d0,d3
        blt.s   .db_mb
        moveq   #IT_DRAGSIZE,d0
        bra     it_dragstart
.db_mb:
        move.l  #MOUSEBUTTONS,d0
        moveq   #SELECTDOWN,d1
        cmp.w   #IECODE_LBUTTON,d7
        beq     wn_sendmsg
        move.w  #SELECTUP,d1
        cmp.w   #IECODE_LBUTTON|IECODE_UP_PREFIX,d7
        beq     wn_sendmsg
.db_ret:
        rts

; it_dragstart(a3 = fenêtre, a4 = écran, d0 = IT_DRAGMOVE | IT_DRAGSIZE, d4/d5 = pointeur) : début d'un geste. Les
; couches de l'écran sont verrouillées jusqu'au relâchement (personne ne dessine sous le cadre fantôme, tracé en
; mode COMPLEMENT dans le RastPort de l'écran). Préserve a5.
it_dragstart:
        move.l  a3,IB_DRAGWIN(a5)
        move.w  d0,IB_DRAGMODE(a5)
        move.w  d4,IB_DRAGSX(a5)
        move.w  d5,IB_DRAGSY(a5)
        st      IB_TRACK(a5)
        lea     SC_LAYERINFO(a4),a0
        move.l  IB_LAYERSBASE(a5),a6
        jsr     LVO_LOCKLAYERS(a6)
        bsr     it_dragrect
        st      IB_BOXON(a5)
        bra     it_boxxor

; it_domove(a5, d4/d5 = pointeur) : geste en cours -> le cadre fantôme suit le pointeur ; menus -> surbrillance.
it_domove:
        tst.l   IB_MENUWIN(a5)
        bne     it_menumove
        move.l  IB_DRAGWIN(a5),d0
        beq.s   .dm_ret
        move.l  d0,a3
        bsr     it_scrxy
        beq.s   .dm_ret
        bsr     it_boxxor            ; efface l'ancien
        bsr     it_dragrect
        bra     it_boxxor
.dm_ret:
        rts

; it_dragend(a5, a4 = écran, d4/d5 = pointeur au relâchement) : efface le cadre, applique le déplacement ou la
; nouvelle taille, puis rend les couches.
it_dragend:
        move.l  IB_DRAGWIN(a5),a3
        bsr     it_boxxor
        clr.b   IB_BOXON(a5)
        bsr     it_dragrect
        move.l  a3,a0
        move.l  a5,a6
        cmp.w   #IT_DRAGSIZE,IB_DRAGMODE(a5)
        beq.s   .de_size
        movem.w IB_BOX(a5),d0-d1
        sub.w   WD_LEFTEDGE(a3),d0
        sub.w   WD_TOPEDGE(a3),d1
        ext.l   d0
        ext.l   d1
        bsr     intuition_MoveWindow
        bra.s   .de_done
.de_size:
        movem.w IB_BOX(a5),d0-d3
        sub.w   d0,d2
        addq.w  #1,d2
        sub.w   d1,d3
        addq.w  #1,d3
        move.w  d2,d0
        sub.w   WD_WIDTH(a3),d0
        move.w  d3,d1
        sub.w   WD_HEIGHT(a3),d1
        ext.l   d0
        ext.l   d1
        bsr     intuition_SizeWindow
.de_done:
        clr.l   IB_DRAGWIN(a5)
        clr.b   IB_TRACK(a5)
        move.l  WD_WSCREEN(a3),a0
        lea     SC_LAYERINFO(a0),a0
        move.l  IB_LAYERSBASE(a5),a6
        jmp     LVO_UNLOCKLAYERS(a6)

; it_dragrect(a3 = fenêtre, a4 = écran, a5, d4/d5 = pointeur) : rectangle visé par le geste -> IB_BOX (x0,y0,x1,y1).
; Déplacement : la fenêtre reste dans l'écran ; taille : bornée par les limites de la fenêtre et l'écran.
it_dragrect:
        movem.l d2-d7,-(sp)
        move.w  d4,d6
        sub.w   IB_DRAGSX(a5),d6     ; d6/d7 = déplacement du pointeur
        move.w  d5,d7
        sub.w   IB_DRAGSY(a5),d7
        move.w  WD_LEFTEDGE(a3),d0
        move.w  WD_TOPEDGE(a3),d1
        move.w  WD_WIDTH(a3),d2
        move.w  WD_HEIGHT(a3),d3
        cmp.w   #IT_DRAGSIZE,IB_DRAGMODE(a5)
        beq.s   .dr_size
        add.w   d6,d0
        move.w  SC_WIDTH(a4),d4
        sub.w   d2,d4
        bsr.s   .dr_clamp0
        add.w   d7,d1
        exg     d0,d1
        move.w  SC_HEIGHT(a4),d4
        sub.w   d3,d4
        bsr.s   .dr_clamp0
        exg     d0,d1
        bra.s   .dr_out
.dr_size:
        add.w   d6,d2                ; largeur : [MinWidth, min(MaxWidth, écran - LeftEdge)]
        move.w  SC_WIDTH(a4),d4
        sub.w   d0,d4
        cmp.w   WD_MAXWIDTH(a3),d4
        bls.s   .dr_wmax
        move.w  WD_MAXWIDTH(a3),d4
.dr_wmax:
        move.w  WD_MINWIDTH(a3),d5
        exg     d0,d2
        bsr.s   it_clamp
        exg     d0,d2
        add.w   d7,d3
        move.w  SC_HEIGHT(a4),d4
        sub.w   d1,d4
        cmp.w   WD_MAXHEIGHT(a3),d4
        bls.s   .dr_hmax
        move.w  WD_MAXHEIGHT(a3),d4
.dr_hmax:
        move.w  WD_MINHEIGHT(a3),d5
        exg     d0,d3
        bsr.s   it_clamp
        exg     d0,d3
.dr_out:
        add.w   d0,d2                ; x1 = x0 + largeur - 1
        subq.w  #1,d2
        add.w   d1,d3
        subq.w  #1,d3
        movem.w d0-d3,IB_BOX(a5)
        movem.l (sp)+,d2-d7
        rts
.dr_clamp0:                          ; d0 := clamp(d0, 0, d4)
        moveq   #0,d5
; it_clamp : d0.w := clamp(d0, d5, d4) (d4 prime si d5 > d4).
it_clamp:
        cmp.w   d5,d0
        bge.s   .cl_1
        move.w  d5,d0
.cl_1:
        cmp.w   d4,d0
        ble.s   .cl_2
        move.w  d4,d0
.cl_2:
        rts

; it_boxxor(a3 = fenêtre du geste, a5) : inverse le cadre IB_BOX (1 pixel) dans le RastPort de son écran ; quatre
; segments disjoints, pour qu'un second appel l'efface exactement. Préserve d2-d7/a2-a5.
it_boxxor:
        movem.l d2-d7/a2,-(sp)
        move.l  WD_WSCREEN(a3),a2
        lea     SC_RASTPORT(a2),a2
        move.l  IB_GFXBASE(a5),a6
        move.l  a2,a1
        moveq   #COMPLEMENT,d0
        jsr     LVO_SETDRMD(a6)
        movem.w IB_BOX(a5),d4-d7     ; x0, y0, x1, y1
        move.l  a2,a1                ; haut
        move.w  d4,d0
        move.w  d5,d1
        move.w  d6,d2
        move.w  d5,d3
        jsr     LVO_RECTFILL(a6)
        cmp.w   d5,d7
        ble.s   .bx_done
        move.l  a2,a1                ; bas
        move.w  d4,d0
        move.w  d7,d1
        move.w  d6,d2
        move.w  d7,d3
        jsr     LVO_RECTFILL(a6)
        move.w  d7,d3
        subq.w  #1,d3
        cmp.w   d5,d3
        ble.s   .bx_done
        move.l  a2,a1                ; gauche
        move.w  d4,d0
        move.w  d5,d1
        addq.w  #1,d1
        move.w  d4,d2
        jsr     LVO_RECTFILL(a6)
        cmp.w   d4,d6
        ble.s   .bx_done
        move.l  a2,a1                ; droite
        move.w  d6,d0
        move.w  d5,d1
        addq.w  #1,d1
        move.w  d6,d2
        move.w  d7,d3
        subq.w  #1,d3
        jsr     LVO_RECTFILL(a6)
.bx_done:
        move.l  a2,a1
        moveq   #JAM2,d0
        jsr     LVO_SETDRMD(a6)
        movem.l (sp)+,d2-d7/a2
        rts

; SizeWindow(fenêtre a0, dx d0, dy d1) : nouvelle taille bornée (16 pixels au moins, sans sortir de l'écran). La
; couche suit (SizeLayer) ; les anciennes bordures devenues intérieures et l'ancien gadget de taille sont effacés,
; le cadre redessiné, NEWSIZE envoyé, puis les zones abîmées réparées (REFRESHWINDOW pour la fenêtre elle-même).
intuition_SizeWindow:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  a6,a5
        move.l  a0,a3
        move.l  WD_WSCREEN(a3),a4
        move.w  WD_WIDTH(a3),d6      ; d6/d7 = ancienne taille
        move.w  WD_HEIGHT(a3),d7
        move.w  d6,d2
        add.w   d0,d2
        move.w  SC_WIDTH(a4),d4
        sub.w   WD_LEFTEDGE(a3),d4
        moveq   #16,d5
        exg     d0,d2
        bsr     it_clamp
        exg     d0,d2
        move.w  d7,d3
        add.w   d1,d3
        move.w  SC_HEIGHT(a4),d4
        sub.w   WD_TOPEDGE(a3),d4
        exg     d0,d3
        bsr     it_clamp
        exg     d0,d3
        move.w  d2,d0
        sub.w   d6,d0                ; d0/d1 = variation effective
        move.w  d3,d1
        sub.w   d7,d1
        move.w  d0,d4
        or.w    d1,d4
        beq     .sw_ret
        move.w  d2,WD_WIDTH(a3)
        move.w  d3,WD_HEIGHT(a3)
        ext.l   d0
        ext.l   d1
        move.l  IB_LAYERSBASE(a5),a6
        suba.l  a0,a0
        move.l  WD_WLAYER(a3),a1
        jsr     LVO_SIZELAYER(a6)
        bsr     wn_gzz
        bsr     wn_unborder
        bsr     wn_border
        move.l  #NEWSIZE,d0
        moveq   #0,d1
        moveq   #0,d2
        moveq   #0,d3
        bsr     wn_sendmsg
        bsr     it_refresh
.sw_ret:
        movem.l (sp)+,d2-d7/a2-a6
        rts

; WindowLimits(fenêtre a0, minW d0, minH d1, maxW d2, maxH d3) -> d0 = TRUE : limites du gadget de taille ; une
; valeur nulle laisse la limite inchangée.
intuition_WindowLimits:
        lea     WD_MINWIDTH(a0),a0
        tst.w   d0
        beq.s   .wl_1
        move.w  d0,(a0)
.wl_1:
        tst.w   d1
        beq.s   .wl_2
        move.w  d1,2(a0)
.wl_2:
        tst.w   d2
        beq.s   .wl_3
        move.w  d2,4(a0)
.wl_3:
        tst.w   d3
        beq.s   .wl_4
        move.w  d3,6(a0)
.wl_4:
        moveq   #1,d0
        rts

; wn_gzz(a3 = fenêtre) : GZZWidth / GZZHeight = taille moins les bordures. Clobbe d0/d1.
wn_gzz:
        moveq   #0,d0
        move.b  WD_BORDERLEFT(a3),d0
        moveq   #0,d1
        move.b  WD_BORDERRIGHT(a3),d1
        add.w   d0,d1
        move.w  WD_WIDTH(a3),d0
        sub.w   d1,d0
        move.w  d0,WD_GZZWIDTH(a3)
        moveq   #0,d0
        move.b  WD_BORDERTOP(a3),d0
        moveq   #0,d1
        move.b  WD_BORDERBOTTOM(a3),d1
        add.w   d0,d1
        move.w  WD_HEIGHT(a3),d0
        sub.w   d1,d0
        move.w  d0,WD_GZZHEIGHT(a3)
        rts

; wn_unborder(a3 = fenêtre, a5, d6/d7 = ancienne taille) : efface (stylo 0) les bandes de bordure droite / basse
; touchées par le changement de taille, de min(ancienne, nouvelle) jusqu'aux nouveaux bords (ancienne bordure devenue
; intérieure, ou intérieur passé sous la nouvelle bordure), et l'ancien gadget de taille ; wn_border redessine ensuite
; le cadre. Clobbe d0-d5/a0/a1/a6.
wn_unborder:
        btst    #3,WD_FLAGS+2(a3)    ; BORDERLESS : rien à effacer
        bne     .ub_ret
        move.l  IB_GFXBASE(a5),a6
        move.l  WD_RPORT(a3),a1
        moveq   #0,d0
        jsr     LVO_SETAPEN(a6)
        move.w  WD_WIDTH(a3),d0      ; bande droite : [min(oldW, W) - BR, W - 1] x [BT, H - 1]
        cmp.w   d6,d0
        ble.s   .ub_wmin
        move.w  d6,d0
.ub_wmin:
        moveq   #0,d4
        move.b  WD_BORDERRIGHT(a3),d4
        sub.w   d4,d0
        move.w  WD_WIDTH(a3),d2
        subq.w  #1,d2
        moveq   #0,d1
        move.b  WD_BORDERTOP(a3),d1
        move.w  WD_HEIGHT(a3),d3
        subq.w  #1,d3
        bsr.s   .ub_fill
        move.w  WD_HEIGHT(a3),d1     ; bande basse : [0, W - 1] x [min(oldH, H) - BB, H - 1]
        cmp.w   d7,d1
        ble.s   .ub_hmin
        move.w  d7,d1
.ub_hmin:
        moveq   #0,d5
        move.b  WD_BORDERBOTTOM(a3),d5
        sub.w   d5,d1
        moveq   #0,d0
        move.w  WD_WIDTH(a3),d2
        subq.w  #1,d2
        move.w  WD_HEIGHT(a3),d3
        subq.w  #1,d3
        bsr.s   .ub_fill
.ub_gad:
        btst    #0,WD_FLAGS+3(a3)    ; ancien gadget de taille
        beq.s   .ub_ret
        move.w  d6,d0
        sub.w   #18,d0
        move.w  d7,d1
        sub.w   #9,d1
        move.w  d6,d2
        subq.w  #1,d2
        move.w  d7,d3
        subq.w  #1,d3
.ub_fill:                            ; RectFill si le rectangle n'est pas vide
        cmp.w   d0,d2
        blt.s   .ub_ret
        cmp.w   d1,d3
        blt.s   .ub_ret
        move.l  WD_RPORT(a3),a1
        jmp     LVO_RECTFILL(a6)
.ub_ret:
        rts

; wn_sendmsg(a3 = fenêtre, d0 = classe IDCMP, d1.w = code, d2.w/d3.w = souris relative) : si la fenêtre a demandé
; cette classe, prend un IntuiMessage libre de sa réserve, l'horodate (compteur VBlank : 50 Hz) et l'envoie sur son
; UserPort ; réserve épuisée : événement perdu. Clobbe d0/d1/d6/a0/a1/a6.
wn_sendmsg:
        move.l  WD_USERPORT(a3),d6
        beq     .sm_ret
        and.l   WD_IDCMPFLAGS(a3),d0
        beq.s   .sm_ret
        lea     WDX_EMSG(a3),a1
        moveq   #WDX_NEMSG-1,d6
.sm_find:
        cmp.b   #NT_MESSAGE,LN_TYPE(a1)
        bne.s   .sm_free
        lea     IM_SIZEOF(a1),a1
        dbra    d6,.sm_find
        bra.s   .sm_ret
.sm_free:
        move.b  #NT_MESSAGE,LN_TYPE(a1)
        clr.l   MN_REPLYPORT(a1)
        move.w  #IM_SIZEOF,MN_LENGTH(a1)
        move.l  d0,IM_CLASS(a1)
        move.w  d1,IM_CODE(a1)
        clr.w   IM_QUALIFIER(a1)
        move.l  a3,IM_IADDRESS(a1)
        move.w  d2,IM_MOUSEX(a1)
        move.w  d3,IM_MOUSEY(a1)
        move.l  GP_POLLS,d0          ; secondes / microsecondes depuis le démarrage (VBlanks)
        moveq   #0,d1
        swap    d0
        move.w  d0,d1
        divu    #50,d1               ; division longue en deux temps (le quotient peut dépasser 16 bits)
        move.w  d1,d6
        swap    d6
        swap    d0
        move.w  d0,d1
        divu    #50,d1
        move.w  d1,d6                ; d6 = secondes
        swap    d1
        mulu    #20000,d1            ; reste (1/50 s) -> microsecondes
        move.l  d6,IM_SECONDS(a1)
        move.l  d1,IM_MICROS(a1)
        move.l  a3,IM_IDCMPWINDOW(a1)
        move.l  WD_USERPORT(a3),a0
        move.l  ($4).w,a6
        jsr     LVO_PUTMSG(a6)
.sm_ret:
        rts

; DoubleClick(secondes d0, micros d1, secondes d2, micros d3) -> d0 = TRUE si le second clic suit le premier de moins
; que le délai de double-clic des préférences.
intuition_DoubleClick:
        sub.l   d0,d2                ; d2 = écart en secondes
        bmi.s   .dc_no
        cmp.l   #2,d2
        bhs.s   .dc_no
        mulu    #15625,d2            ; secondes -> microsecondes (15625 * 64)
        lsl.l   #6,d2
        add.l   d3,d2
        sub.l   d1,d2                ; d2 = écart en microsecondes
        bmi.s   .dc_no
        cmp.l   #IT_DBLCLICK,d2
        bhs.s   .dc_no
        moveq   #-1,d0
        rts
.dc_no:
        moveq   #0,d0
        rts
IT_DBLCLICK     EQU 1000000          ; délai de double-clic (Preferences par défaut : 1 s)

; NewScreen du Workbench
sc_wbnewscreen:
        dc.w    0,0,640,256,2        ; LeftEdge, TopEdge, Width, Height, Depth
        dc.b    2,1                  ; DetailPen (titres et gadgets : noir), BlockPen (barres : blanc)
        dc.w    V_HIRES              ; ViewModes
        dc.w    WBENCHSCREEN         ; Type
        dc.l    0                    ; Font
        dc.l    sc_wbtitle           ; DefaultTitle
        dc.l    0,0                  ; Gadgets, CustomBitMap
; palette par défaut : thème du projet (fond vert pomme au lieu du bleu des préférences 1.3, blanc, noir, orange), puis
; couleurs de remplissage (16..19 : pointeur)
sc_palette:
        dc.w    SC_BGCOLOR,$FFF,$000,$F80,$00F,$F0F,$0FF,$FFF
        dc.w    $620,$E50,$9F1,$EB0,$55F,$92F,$0F8,$CCC
        dc.w    $000,$E44,$000,$EEC,$444,$555,$666,$777
        dc.w    $888,$999,$AAA,$BBB,$CCC,$DDD,$EEE,$FFF
sc_wbtitle:
        dc.b    "Workbench Screen",0
        even
