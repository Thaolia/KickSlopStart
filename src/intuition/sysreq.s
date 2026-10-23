; src/intuition/sysreq.s — intuition.library : AutoRequest, le requester système à deux réponses (spec
; intuition-requesters-v34 §5). Une fenêtre s'ouvre en (0,0) sur l'écran de la fenêtre donnée (à défaut l'écran
; Workbench), avec son titre (« System Request » sans fenêtre) ; son intérieur porte le requester : fond au stylo 1,
; cadre, corps, gadgets positif (en bas à gauche, ID 1) et négatif (en bas à droite, ID 0).
; Écart assumé : le requester est dessiné directement dans la fenêtre (pas de couche Request) ; seule la structure
; interne diffère.
; Piste IMPLÉMENTATION (« clean ») : AutoDoc intuition AutoRequest + structures publiques + spec. AUCUNE lecture ROM.

                include "exec.i"
                include "graphics.i"
                include "intuition.i"

                xdef    intuition_AutoRequest
                xref    intuition_OpenWindow
                xref    intuition_CloseWindow
                xref    intuition_PrintIText
                xref    intuition_IntuiTextLength
                xref    intuition_DrawBorder
                xref    intuition_AddGadget
                xref    intuition_RefreshGadgets

SR_SIMPLE       EQU $0040            ; NewWindow : SIMPLE_REFRESH
SR_NOCARE       EQU $00020000        ; NOCAREREFRESH
SR_FLAGS        EQU SR_NOCARE|ACTIVATE|SR_SIMPLE|WINDOWDEPTH|WINDOWDRAG|WINDOWSIZING
SR_REQGAD       EQU $1000            ; GadgetType : gadget de requester
SR_LCOMMAND     EQU $40              ; qualifier : Amiga gauche
SR_KEYV         EQU $34              ; Amiga-V : positif
SR_KEYB         EQU $35              ; Amiga-B : négatif

; bloc alloué : 2 gadgets, 5 cadres (Border + 9 points), la NewWindow
SR_BDSZ         EQU 16+9*4
SR_GADP         EQU 0
SR_GADN         EQU SR_GADP+GG_SIZEOF
SR_BREQ         EQU SR_GADN+GG_SIZEOF ; cadre du requester
SR_BP           EQU SR_BREQ+SR_BDSZ  ; gadget positif : filet intérieur puis cadre extérieur
SR_BN           EQU SR_BP+2*SR_BDSZ
SR_NW           EQU SR_BN+2*SR_BDSZ
SR_NWSIZE       EQU 48               ; struct NewWindow
SR_SIZE         EQU SR_NW+SR_NWSIZE

; AutoRequest(fenêtre a0, corps a1, positif a2, négatif a3, drapeauxPos d0, drapeauxNég d1, largeur d2, hauteur d3)
; -> d0 = TRUE (gadget positif, Amiga-V ou événement IDCMP de drapeauxPos) / FALSE (négatif, Amiga-B, drapeauxNég, ou
; échec). Sans texte positif, seul le gadget négatif existe. Le port IDCMP signale l'appelant.
intuition_AutoRequest:
        movem.l d2-d7/a2-a5,-(sp)
        move.l  a6,a5                ; a5 = IntuitionBase
        move.l  a0,d7                ; d7 = fenêtre de référence | 0
        move.l  a1,d6                ; d6 = corps
        move.l  d0,d4                ; d4 = drapeaux positifs
        move.l  d1,d5                ; d5 = drapeaux négatifs
        movem.w d2-d3,-(sp)          ; (sp) = largeur, 2(sp) = hauteur
        move.l  ($4).w,a6
        move.l  #SR_SIZE,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .ar_nomem
        move.l  d0,a4                ; a4 = bloc
        move.l  a2,SR_GADP+GG_GADGETTEXT(a4)
        move.l  a3,SR_GADN+GG_GADGETTEXT(a4)
        move.l  a5,a6
        lea     SR_NW(a4),a0
        move.w  (sp),NW_WIDTH(a0)
        move.w  2(sp),NW_HEIGHT(a0)
        move.w  (sp),NW_MAXWIDTH(a0)
        move.w  2(sp),NW_MAXHEIGHT(a0)
        move.w  #88,NW_MINWIDTH(a0)
        move.w  #24,NW_MINHEIGHT(a0)
        move.w  #$FFFF,NW_DETAILPEN(a0) ; stylos de l'écran
        move.l  d4,d0
        or.l    d5,d0
        or.l    #GADGETUP|RAWKEY,d0
        move.l  d0,NW_IDCMPFLAGS(a0)
        move.l  #SR_FLAGS,NW_FLAGS(a0)
        lea     sr_title(pc),a1
        move.l  a1,NW_TITLE(a0)
        move.w  #WBENCHSCREEN,NW_TYPE(a0)
        tst.l   d7
        beq.s   .ar_open
        move.l  d7,a1
        move.b  WD_DETAILPEN(a1),NW_DETAILPEN(a0)
        move.b  WD_BLOCKPEN(a1),NW_BLOCKPEN(a0)
        tst.l   WD_TITLE(a1)
        beq.s   .ar_scr
        move.l  WD_TITLE(a1),NW_TITLE(a0)
.ar_scr:
        move.l  WD_WSCREEN(a1),a1
        move.l  a1,NW_SCREEN(a0)
        move.w  SC_FLAGS(a1),d0
        and.w   #$0F,d0
        move.w  d0,NW_TYPE(a0)
.ar_open:
        jsr     intuition_OpenWindow
        tst.l   d0
        beq     .ar_nowin
        move.l  d0,a3                ; a3 = fenêtre du requester
        bsr     sr_draw
        move.l  ($4).w,a6
.ar_wait:
        move.l  WD_USERPORT(a3),a0
        jsr     LVO_WAITPORT(a6)
.ar_get:
        move.l  WD_USERPORT(a3),a0
        jsr     LVO_GETMSG(a6)
        tst.l   d0
        beq.s   .ar_wait
        move.l  d0,a1
        move.l  IM_CLASS(a1),d0
        moveq   #-1,d2               ; d2 = réponse (-1 : pas encore)
        move.l  d0,d1
        and.l   d5,d1
        beq.s   .ar_pos
        moveq   #0,d2
        bra.s   .ar_reply
.ar_pos:
        move.l  d0,d1
        and.l   d4,d1
        beq.s   .ar_gad
        moveq   #1,d2
        bra.s   .ar_reply
.ar_gad:
        cmp.l   #GADGETUP,d0
        bne.s   .ar_key
        move.l  IM_IADDRESS(a1),a0
        moveq   #0,d2
        tst.w   GG_GADGETID(a0)
        beq.s   .ar_reply
        moveq   #1,d2
        bra.s   .ar_reply
.ar_key:
        cmp.l   #RAWKEY,d0
        bne.s   .ar_reply
        btst    #6,IM_QUALIFIER+1(a1) ; Amiga gauche
        beq.s   .ar_reply
        cmp.w   #SR_KEYB,IM_CODE(a1)
        bne.s   .ar_kv
        moveq   #0,d2
        bra.s   .ar_reply
.ar_kv:
        cmp.w   #SR_KEYV,IM_CODE(a1)
        bne.s   .ar_reply
        tst.l   SR_GADP+GG_GADGETTEXT(a4) ; seulement s'il y a un gadget positif
        beq.s   .ar_reply
        moveq   #1,d2
.ar_reply:
        jsr     LVO_REPLYMSG(a6)
        tst.l   d2
        bmi.s   .ar_get
        move.l  a3,a0
        move.l  a5,a6
        jsr     intuition_CloseWindow
        move.l  d2,d7
        bra.s   .ar_free
.ar_nowin:
        moveq   #0,d7
.ar_free:
        move.l  ($4).w,a6
        move.l  a4,a1
        move.l  #SR_SIZE,d0
        jsr     LVO_FREEMEM(a6)
        move.l  d7,d0
        bra.s   .ar_ret
.ar_nomem:
        moveq   #0,d0
.ar_ret:
        addq.l  #4,sp
        movem.l (sp)+,d2-d7/a2-a5
        rts

; sr_draw(a3 = fenêtre, a4 = bloc, d6 = corps, a5 = a6 = IntuitionBase) : requester sur tout l'intérieur de la
; fenêtre : fond au stylo 1 (JAM1), cadre en retrait d'un pixel au stylo 0, corps à son coin ; puis les gadgets,
; placés dans le domaine du requester (positif à 14 du bord gauche, négatif à 13 du bord droit, 4 au-dessus du bas),
; ajoutés à la fenêtre et dessinés. Clobbe d0-d5/a0-a2.
sr_draw:
        moveq   #0,d0
        move.b  WD_BORDERLEFT(a3),d0
        moveq   #0,d1
        move.b  WD_BORDERTOP(a3),d1
        move.w  WD_WIDTH(a3),d2
        sub.w   d0,d2
        moveq   #0,d3
        move.b  WD_BORDERRIGHT(a3),d3
        sub.w   d3,d2                ; d2 = largeur du requester
        move.w  WD_HEIGHT(a3),d3
        sub.w   d1,d3
        moveq   #0,d4
        move.b  WD_BORDERBOTTOM(a3),d4
        sub.w   d4,d3                ; d3 = hauteur du requester
        movem.w d0-d3,-(sp)          ; (sp) = x, 2 = y, 4 = largeur, 6 = hauteur
        move.l  IB_GFXBASE(a5),a6
        move.l  WD_RPORT(a3),a1
        moveq   #1,d0
        jsr     LVO_SETAPEN(a6)
        move.l  WD_RPORT(a3),a1
        moveq   #JAM1,d0
        jsr     LVO_SETDRMD(a6)
        movem.w (sp),d0-d3
        add.w   d0,d2
        subq.w  #1,d2
        add.w   d1,d3
        subq.w  #1,d3
        ext.l   d0
        ext.l   d1
        ext.l   d2
        ext.l   d3
        move.l  WD_RPORT(a3),a1
        jsr     LVO_RECTFILL(a6)
        move.l  a5,a6
        lea     SR_BREQ(a4),a0
        move.w  4(sp),d0
        move.w  6(sp),d1
        moveq   #1,d2
        moveq   #0,d3
        bsr     sr_frame
        move.l  WD_RPORT(a3),a0
        lea     SR_BREQ(a4),a1
        move.w  (sp),d0
        ext.l   d0
        move.w  2(sp),d1
        ext.l   d1
        jsr     intuition_DrawBorder
        move.l  d6,d0
        beq.s   .dr_gad
        move.l  WD_RPORT(a3),a0
        move.l  d0,a1
        move.w  (sp),d0
        ext.l   d0
        move.w  2(sp),d1
        ext.l   d1
        jsr     intuition_PrintIText
.dr_gad:
        moveq   #0,d0                ; positions dans la fenêtre : requester ramené à ses bordures
        move.b  WD_BORDERRIGHT(a3),d0
        move.w  d0,4(sp)             ; 4(sp) = bordure droite
        move.b  WD_BORDERBOTTOM(a3),d0
        move.w  d0,6(sp)             ; 6(sp) = bordure basse
        lea     SR_GADN(a4),a0       ; négatif
        lea     SR_BN(a4),a1
        bsr     sr_mkgad
        or.w    #GRELRIGHT,GG_FLAGS(a0)
        move.w  GG_WIDTH(a0),d0
        add.w   #13,d0
        add.w   4(sp),d0
        neg.w   d0
        move.w  d0,GG_LEFTEDGE(a0)
        move.w  6(sp),d0
        sub.w   d0,GG_TOPEDGE(a0)
        tst.l   SR_GADP+GG_GADGETTEXT(a4)
        beq.s   .dr_add
        lea     SR_GADP(a4),a0       ; positif
        lea     SR_BP(a4),a1
        bsr     sr_mkgad
        move.w  #14,d0
        add.w   (sp),d0
        move.w  d0,GG_LEFTEDGE(a0)
        move.w  #1,GG_GADGETID(a0)
        move.w  6(sp),d0
        sub.w   d0,GG_TOPEDGE(a0)
        move.l  a0,a1
        move.l  a3,a0
        moveq   #-1,d0
        jsr     intuition_AddGadget
.dr_add:
        move.l  a3,a0
        lea     SR_GADN(a4),a1
        moveq   #-1,d0
        jsr     intuition_AddGadget
        lea     SR_GADP(a4),a0       ; premier gadget du requester
        tst.l   SR_GADP+GG_GADGETTEXT(a4)
        bne.s   .dr_rg
        lea     SR_GADN(a4),a0
.dr_rg:
        move.l  a3,a1
        suba.l  a2,a2
        jsr     intuition_RefreshGadgets
        addq.l  #8,sp
        rts

; sr_mkgad(a0 = gadget (texte déjà posé), a1 = ses deux cadres, a3 = fenêtre, a6 = IntuitionBase) : bouton booléen de
; requester relâché-vérifié, largeur = texte (premier IntuiText) + 12, hauteur = police + 6, 4 pixels au-dessus du bas
; du domaine ; rendu = filet intérieur (stylo 0) puis cadre extérieur d'un pixel (stylo 3), surbrillance par
; complément. Préserve a0/a2-a6.
sr_mkgad:
        movem.l d2-d3/a0-a2,-(sp)
        move.l  a0,a2
        move.w  #SR_REQGAD|BOOLGADGET,GG_GADGETTYPE(a2)
        move.w  #$0100|RELVERIFY,GG_ACTIVATION(a2)
        move.w  #GRELBOTTOM,GG_FLAGS(a2)
        move.l  a1,GG_GADGETRENDER(a2)
        moveq   #12,d2               ; largeur
        move.l  WD_WSCREEN(a3),a0
        move.w  SC_RASTPORT+rp_TxHeight(a0),d3
        move.l  GG_GADGETTEXT(a2),d0
        beq.s   .mg_size
        move.l  d0,a0
        move.l  IT_ITEXTFONT(a0),d1
        beq.s   .mg_w
        move.l  d1,a1
        move.w  ta_YSize(a1),d3
.mg_w:
        jsr     intuition_IntuiTextLength
        add.w   d0,d2
.mg_size:
        addq.w  #6,d3                ; hauteur
        move.w  d2,GG_WIDTH(a2)
        move.w  d3,GG_HEIGHT(a2)
        move.w  d3,d0
        addq.w  #4,d0
        neg.w   d0
        move.w  d0,GG_TOPEDGE(a2)
        move.l  GG_GADGETRENDER(a2),a0
        move.w  d2,d0
        move.w  d3,d1
        moveq   #1,d2
        moveq   #0,d3
        bsr.s   sr_frame             ; filet intérieur, stylo 0 (dessiné en premier)
        lea     SR_BDSZ(a0),a1
        move.l  a1,BD_NEXTBORDER(a0)
        move.l  a1,a0
        move.w  GG_WIDTH(a2),d0
        move.w  GG_HEIGHT(a2),d1
        moveq   #-1,d2
        moveq   #3,d3
        bsr.s   sr_frame             ; cadre extérieur d'un pixel, stylo 3
        movem.l (sp)+,d2-d3/a0-a2
        rts

; sr_frame(a0 = Border suivie de 9 points, d0.w/d1.w = largeur/hauteur, d2.w = retrait, d3.b = stylo) : rectangle en
; retrait de d2 aux montants verticaux de deux pixels, JAM1, Count 9, sans Border suivante. Clobbe d0-d3 ;
; préserve a0/a1.
sr_frame:
        move.l  a1,-(sp)
        clr.l   BD_LEFTEDGE(a0)
        move.b  d3,BD_FRONTPEN(a0)
        clr.b   BD_FRONTPEN+1(a0)
        move.b  #JAM1,BD_DRAWMODE(a0)
        move.b  #9,BD_COUNT(a0)
        clr.l   BD_NEXTBORDER(a0)
        lea     16(a0),a1
        move.l  a1,BD_XY(a0)
        subq.w  #1,d0                ; d0 = largeur - 1 - retrait, d1 = hauteur - 1 - retrait
        sub.w   d2,d0
        subq.w  #1,d1
        sub.w   d2,d1
        move.w  d2,(a1)+             ; (r,r)
        move.w  d2,(a1)+
        move.w  d0,(a1)+             ; (W'-r,r)
        move.w  d2,(a1)+
        move.w  d0,(a1)+             ; (W'-r,H'-r)
        move.w  d1,(a1)+
        move.w  d2,(a1)+             ; (r,H'-r)
        move.w  d1,(a1)+
        move.w  d2,(a1)+             ; (r,r)
        move.w  d2,(a1)+
        move.w  d2,d3
        addq.w  #1,d3                ; d3 = s = r + 1
        move.w  d3,(a1)+             ; (s,r)
        move.w  d2,(a1)+
        move.w  d3,(a1)+             ; (s,H'-r)
        move.w  d1,(a1)+
        subq.w  #1,d0                ; d0 = W'-s
        move.w  d0,(a1)+             ; (W'-s,H'-r)
        move.w  d1,(a1)+
        move.w  d0,(a1)+             ; (W'-s,r)
        move.w  d2,(a1)+
        move.l  (sp)+,a1
        rts

sr_title:
        dc.b    "System Request",0
        even
