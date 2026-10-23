; src/graphics/draw.s — primitives de dessin de graphics.library dans un RastPort (BitMap planaire, rendu CPU).
; SetAPen/SetBPen/SetDrMd/Move/Draw/WritePixel/RectFill/SetRast/ScrollRaster/Text/TextLength/SetFont/
; InitRastPort/InitBitMap/ReadPixel/BltBitMap. Si rp_Layer est posé, ses bornes donnent le décalage (coordonnées
; relatives à la couche) et le dessin passe par ses ClipRects (layers.library) : ClipRect visible -> BitMap du
; RastPort ; ClipRect cachée avec sauvegarde (cr_BitMap, origine dans cr_p1) -> la sauvegarde ; cachée sans
; sauvegarde -> rien. Le verrou de la couche est tenu pendant le dessin (dr_ctx ... dr_end). Sans couche : une seule
; pseudo-ClipRect = le BitMap entier. Texte : police du RastPort (TextFont quelconque, topaz 8 par défaut),
; dessinée en JAM1/JAM2/COMPLEMENT/INVERSVID, gras et souligné algorithmiques. ScrollRaster : défilement vertical seul.
; Accès mémoire OCTET par octet (une ligne de BitMap peut commencer à une adresse impaire).
; Au-delà de la convention (d2-d7/a2-a6), toutes ces fonctions laissent a1 (le RastPort) intact : intuition et
; console.device enchaînent leurs appels sur le même RastPort sans le recharger.
; Piste IMPLÉMENTATION (« clean ») : AutoDocs graphics.library + includes NDK publics. AUCUNE lecture ROM.

                include "exec.i"
                include "graphics.i"

                xdef    gfx_BltTemplate
                xdef    gfx_SetAPen
                xdef    gfx_SetBPen
                xdef    gfx_SetDrMd
                xdef    gfx_Move
                xdef    gfx_Draw
                xdef    gfx_WritePixel
                xdef    gfx_RectFill
                xdef    gfx_SetRast
                xdef    gfx_ScrollRaster
                xdef    gfx_Text
                xdef    gfx_TextLength
                xdef    gfx_SetFont
                xdef    gfx_InitRastPort
                xdef    gfx_InitBitMap
                xdef    gfx_BltBitMapRastPort
                xdef    gfx_BltBitMap
                xdef    gfx_ReadPixel
                xdef    gfx_LockLayerRom
                xdef    gfx_UnlockLayerRom
                xdef    gfx_putrow
                xref    topaz8_font
                xref    gfx_OwnBlitter
                xref    gfx_DisownBlitter
                xref    gfx_OrRectRegion

; --- contexte de dessin (sur la pile, pointé par a5) ---
DC_OX           EQU 0                ; décalage X (bornes du Layer) ; WORD
DC_OY           EQU 2
DC_MINX         EQU 4                ; rectangle de découpage absolu (inclusif)
DC_MINY         EQU 6
DC_MAXX         EQU 8
DC_MAXY         EQU 10
DC_BM           EQU 12               ; BitMap
DC_RP           EQU 16               ; RastPort
DC_MINTERM      EQU 20               ; byte : minterm des copies de bits (dr_bits)
DC_LAYER        EQU 22               ; couche du RastPort (0 = aucune)
DC_FIRST        EQU 26               ; première ClipRect à parcourir (celles de la couche, ou DC_PSEUDO)
DC_CMINX        EQU 30               ; ClipRect courante : rectangle de découpage absolu
DC_CMINY        EQU 32
DC_CMAXX        EQU 34
DC_CMAXY        EQU 36
DC_CBM          EQU 38               ; BitMap où dessiner
DC_BX           EQU 42               ; origine de ce BitMap en coordonnées absolues (0 pour l'écran)
DC_BY           EQU 44
DC_PSEUDO       EQU 46               ; pseudo-ClipRect sans couche (Next, prev, lobs, BitMap, bornes)
DC_SIZE         EQU 70
; champs de ClipRect lus ici (graphics/clip.h)
CR_NEXT         EQU 0
CR_LOBS         EQU 8
CR_BITMAP       EQU 12
CR_MINX         EQU 16
CR_ORGX         EQU 24               ; origine de la sauvegarde (privé layers : cr_p1)
CR_ORGY         EQU 26
LY_CLIPRECT     EQU 8
LY_FLAGS        EQU 30
LY_LOCK         EQU 72
LY_DAMAGE       EQU 156
LAYERREFRESH    EQU $80

; dr_ctx(a1 = RastPort, a5 = contexte) : remplit le contexte et prend le verrou de la couche. Clobbe d0/d1/a0.
dr_ctx:
        bsr     dr_ctx0
        move.l  rp_Layer(a1),d0
        move.l  d0,DC_LAYER(a5)
        beq.s   .cx_pseudo
        move.l  d0,a0
        move.l  LY_CLIPRECT(a0),DC_FIRST(a5)
        movem.l a1/a6,-(sp)
        lea     LY_LOCK(a0),a0
        move.l  ($4).w,a6
        jsr     LVO_OBTAINSEMAPHORE(a6)
        movem.l (sp)+,a1/a6
        rts
.cx_pseudo:
        lea     DC_PSEUDO(a5),a0     ; pseudo-ClipRect visible = zone de découpage entière
        move.l  a0,DC_FIRST(a5)
        clr.l   CR_NEXT(a0)
        clr.l   CR_LOBS(a0)
        clr.l   CR_BITMAP(a0)
        move.l  DC_MINX(a5),CR_MINX(a0)
        move.l  DC_MAXX(a5),CR_MINX+4(a0)
        rts
; dr_end(a5) : rend le verrou de la couche. Préserve tous les registres.
dr_end:
        tst.l   DC_LAYER(a5)
        beq.s   .de_r
        movem.l d0-d1/a0-a1/a6,-(sp)
        move.l  DC_LAYER(a5),a0
        lea     LY_LOCK(a0),a0
        move.l  ($4).w,a6
        jsr     LVO_RELEASESEMAPHORE(a6)
        movem.l (sp)+,d0-d1/a0-a1/a6
.de_r:
        rts
; dr_crset(a0 = ClipRect, a5) : ClipRect courante -> DC_C*, DC_CBM, DC_BX/BY. Z = 1 si inutilisable (cachée sans
; sauvegarde, ou vide une fois découpée au BitMap). Préserve tout sauf d0.
dr_crset:
        tst.l   CR_LOBS(a0)
        beq.s   .cs_vis
        move.l  CR_BITMAP(a0),d0
        beq     .cs_r                ; Z = 1
        move.l  d0,DC_CBM(a5)
        move.l  CR_ORGX(a0),DC_BX(a5)   ; BX, BY
        move.l  CR_MINX(a0),DC_CMINX(a5)
        move.l  CR_MINX+4(a0),DC_CMAXX(a5)
        bra.s   .cs_ok
.cs_vis:
        move.l  DC_BM(a5),DC_CBM(a5)
        clr.l   DC_BX(a5)
        move.l  CR_MINX(a0),DC_CMINX(a5)   ; ∩ zone de découpage (bornes du BitMap)
        move.l  CR_MINX+4(a0),DC_CMAXX(a5)
        move.w  DC_MINX(a5),d0
        cmp.w   DC_CMINX(a5),d0
        ble.s   .cs_1
        move.w  d0,DC_CMINX(a5)
.cs_1:
        move.w  DC_MINY(a5),d0
        cmp.w   DC_CMINY(a5),d0
        ble.s   .cs_2
        move.w  d0,DC_CMINY(a5)
.cs_2:
        move.w  DC_MAXX(a5),d0
        cmp.w   DC_CMAXX(a5),d0
        bge.s   .cs_3
        move.w  d0,DC_CMAXX(a5)
.cs_3:
        move.w  DC_MAXY(a5),d0
        cmp.w   DC_CMAXY(a5),d0
        bge.s   .cs_ok
        move.w  d0,DC_CMAXY(a5)
.cs_ok:
        move.w  DC_CMINX(a5),d0      ; vide ?
        cmp.w   DC_CMAXX(a5),d0
        bgt.s   .cs_empty
        move.w  DC_CMINY(a5),d0
        cmp.w   DC_CMAXY(a5),d0
        bgt.s   .cs_empty
        moveq   #1,d0                ; Z = 0 : utilisable
        rts
.cs_empty:
        moveq   #0,d0
.cs_r:
        rts

; dr_ctx0(a1 = RastPort, a5) : décalage, zone de découpage (bornes de la couche ∩ BitMap), BitMap.
dr_ctx0:
        move.l  a1,DC_RP(a5)
        move.l  rp_BitMap(a1),a0
        move.l  a0,DC_BM(a5)
        clr.l   DC_OX(a5)            ; OX = OY = 0
        clr.l   DC_MINX(a5)          ; MINX = MINY = 0
        move.w  bm_BytesPerRow(a0),d0
        lsl.w   #3,d0
        subq.w  #1,d0
        move.w  d0,DC_MAXX(a5)
        move.w  bm_Rows(a0),d0
        subq.w  #1,d0
        move.w  d0,DC_MAXY(a5)
        move.l  rp_Layer(a1),d0
        beq.s   .dc_ret
        move.l  d0,a0
        move.w  lr_MinX(a0),DC_OX(a5)
        move.w  lr_MinY(a0),DC_OY(a5)
        move.w  lr_MinX(a0),d0       ; intersection bornes du Layer / BitMap
        cmp.w   DC_MINX(a5),d0
        ble.s   .dc_x0
        move.w  d0,DC_MINX(a5)
.dc_x0:
        move.w  lr_MinY(a0),d0
        cmp.w   DC_MINY(a5),d0
        ble.s   .dc_y0
        move.w  d0,DC_MINY(a5)
.dc_y0:
        move.w  lr_MaxX(a0),d0
        cmp.w   DC_MAXX(a5),d0
        bge.s   .dc_x1
        move.w  d0,DC_MAXX(a5)
.dc_x1:
        move.w  lr_MaxY(a0),d0
        cmp.w   DC_MAXY(a5),d0
        bge.s   .dc_ret
        move.w  d0,DC_MAXY(a5)
.dc_ret:
        rts

; dr_span(a5 = contexte, d0.w = x0, d1.w = y, d2.w = x1 (absolus, x0 <= x1), d3.b = stylo) : remplit les pixels
; [x0..x1] de la ligne y avec le stylo (rp_DrawMode COMPLEMENT : inverse) dans chaque ClipRect utilisable, plans
; filtrés par rp_Mask. Préserve tout.
dr_span:
        movem.l d0/a0,-(sp)
        move.l  DC_FIRST(a5),a0
.ds_lp:
        cmpa.w  #0,a0
        beq.s   .ds_r
        cmp.w   CR_MINX+2(a0),d1     ; la ligne doit croiser la ClipRect
        blt.s   .ds_n
        cmp.w   CR_MINX+6(a0),d1
        bgt.s   .ds_n
        bsr     dr_crset
        beq.s   .ds_n
        move.l  (sp),d0
        bsr     dr_span1
.ds_n:
        move.l  CR_NEXT(a0),a0
        bra.s   .ds_lp
.ds_r:
        movem.l (sp)+,d0/a0
        rts
; dr_span1 : comme dr_span, dans la ClipRect courante (DC_C*, DC_CBM, origine DC_BX/BY). Préserve tout.
dr_span1:
        movem.l d0-d7/a0-a3,-(sp)
        cmp.w   DC_CMINY(a5),d1
        blt     .sp_ret
        cmp.w   DC_CMAXY(a5),d1
        bgt     .sp_ret
        cmp.w   DC_CMINX(a5),d0
        bge.s   .sp_c0
        move.w  DC_CMINX(a5),d0
.sp_c0:
        cmp.w   DC_CMAXX(a5),d2
        ble.s   .sp_c1
        move.w  DC_CMAXX(a5),d2
.sp_c1:
        cmp.w   d2,d0
        bgt     .sp_ret
        move.l  DC_CBM(a5),a3
        sub.w   DC_BX(a5),d0         ; coordonnées dans ce BitMap (l'origine X est multiple de 16)
        sub.w   DC_BX(a5),d2
        sub.w   DC_BY(a5),d1
        moveq   #0,d4
        move.w  bm_BytesPerRow(a3),d4
        mulu    d1,d4
        move.l  d4,a1                ; a1 = décalage de la ligne
        move.w  d0,d5
        lsr.w   #3,d5                ; d5 = octet de début
        move.w  d2,d6
        lsr.w   #3,d6
        sub.w   d5,d6                ; d6 = octets après le premier
        moveq   #-1,d7               ; d7.b = masque de début : pixels >= x0
        move.w  d0,d4
        and.w   #7,d4
        lsr.b   d4,d7
        move.w  d2,d4                ; d2.b = masque de fin : pixels <= x1
        and.w   #7,d4
        moveq   #7,d1
        sub.w   d4,d1
        moveq   #-1,d2
        lsl.b   d1,d2
        tst.w   d6
        bne.s   .sp_masks
        and.b   d2,d7                ; un seul octet
.sp_masks:
        move.l  DC_RP(a5),a0
        move.b  rp_Mask(a0),d1       ; d1.b = plans autorisés
        moveq   #0,d0
        move.b  rp_DrawMode(a0),d0
        and.b   #COMPLEMENT,d0
        move.l  d0,a2                ; a2 != 0 : inversion
        moveq   #0,d0
        move.b  bm_Depth(a3),d0
        subq.w  #1,d0                ; d0 = compteur de plans (dbra)
        lea     bm_Planes(a3),a3
.sp_plane:
        move.l  (a3)+,a0
        btst    #0,d1
        beq.s   .sp_pnext
        add.l   a1,a0
        add.w   d5,a0                ; a0 = premier octet
        move.b  d7,d4
        bsr.s   .sp_ap
        tst.w   d6
        beq.s   .sp_pnext
        move.w  d6,d4
        subq.w  #2,d4                ; octets pleins - 1 (d6 - 1 octets pleins)
        bmi.s   .sp_last
        cmpa.w  #0,a2
        bne.s   .sp_minv
        btst    #0,d3
        beq.s   .sp_mclr
.sp_mset:
        st      (a0)+
        dbra    d4,.sp_mset
        bra.s   .sp_last
.sp_mclr:
        clr.b   (a0)+
        dbra    d4,.sp_mclr
        bra.s   .sp_last
.sp_minv:
        not.b   (a0)+
        dbra    d4,.sp_minv
.sp_last:
        move.b  d2,d4
        bsr.s   .sp_ap
.sp_pnext:
        lsr.b   #1,d1
        lsr.b   #1,d3                ; bit du stylo pour le plan suivant
        dbra    d0,.sp_plane
.sp_ret:
        movem.l (sp)+,d0-d7/a0-a3
        rts
; .sp_ap : applique le masque d4.b à l'octet (a0)+ selon le bit 0 de d3 (stylo) ou l'inversion (a2 != 0).
.sp_ap:
        cmpa.w  #0,a2
        beq.s   .ap_set
        eor.b   d4,(a0)+
        rts
.ap_set:
        btst    #0,d3
        beq.s   .ap_clr
        or.b    d4,(a0)+
        rts
.ap_clr:
        not.b   d4
        and.b   d4,(a0)+
        rts

; --- LVO simples ---
gfx_SetAPen:                         ; SetAPen(rp a1, stylo d0)
        move.b  d0,rp_FgPen(a1)
        rts
gfx_SetBPen:                         ; SetBPen(rp a1, stylo d0)
        move.b  d0,rp_BgPen(a1)
        rts
gfx_SetDrMd:                         ; SetDrMd(rp a1, mode d0)
        move.b  d0,rp_DrawMode(a1)
        rts
gfx_Move:                            ; Move(rp a1, x d0, y d1)
        move.w  d0,rp_cp_x(a1)
        move.w  d1,rp_cp_y(a1)
        rts
gfx_TextLength:                      ; TextLength(rp a1, chaîne a0, nombre d0) -> largeur en pixels (comme Text)
        movem.l d2-d3/a2-a3,-(sp)
        bsr     tx_font
        move.l  a0,a3
        move.w  d0,d3
        moveq   #0,d2
.tl_lp:
        subq.w  #1,d3
        bmi.s   .tl_r
        moveq   #0,d0
        move.b  (a3)+,d0
        bsr     tx_index
        bsr     tx_metrics
        add.w   d1,d0
        add.w   rp_TxSpacing(a1),d0
        add.w   d0,d2
        bra.s   .tl_lp
.tl_r:
        move.w  d2,d0
        ext.l   d0
        movem.l (sp)+,d2-d3/a2-a3
        rts
gfx_SetFont:                         ; SetFont(rp a1, police a0) : police et métriques du RastPort (0 : ignoré)
        move.l  a0,d0
        beq.s   .sf_r
        move.l  a0,rp_Font(a1)
        move.w  tf_YSize(a0),rp_TxHeight(a1)
        move.w  tf_XSize(a0),rp_TxWidth(a1)
        move.w  tf_Baseline(a0),rp_TxBaseline(a1)
.sf_r:
        moveq   #0,d0
        rts

; InitRastPort(rp a1, a6 = GfxBase) : RastPort à zéro, Mask/FgPen/AOlPen/LinePtrn = -1, DrawMode = JAM2, police
; par défaut (gb_DefaultFont).
gfx_InitRastPort:
        move.l  a1,a0
        moveq   #rp_SIZEOF/2-1,d0
.ir_clr:
        clr.w   (a0)+
        dbra    d0,.ir_clr
        st      rp_Mask(a1)
        st      rp_FgPen(a1)
        st      rp_AOlPen(a1)
        move.b  #JAM2,rp_DrawMode(a1)
        move.w  #-1,rp_LinePtrn(a1)
        move.l  gb_DefaultFont(a6),a0
        cmpa.w  #0,a0
        bne.s   gfx_SetFont
        lea     topaz8_font,a0
        bra.s   gfx_SetFont

; InitBitMap(bm a0, profondeur d0, largeur d1, hauteur d2) : BytesPerRow = largeur arrondie au mot ; plans non touchés.
gfx_InitBitMap:
        add.w   #15,d1
        lsr.w   #4,d1
        add.w   d1,d1
        move.w  d1,bm_BytesPerRow(a0)
        move.w  d2,bm_Rows(a0)
        clr.b   4(a0)                ; bm_Flags
        move.b  d0,bm_Depth(a0)
        clr.w   6(a0)                ; bm_Pad
        rts

; WritePixel(rp a1, x d0, y d1) -> 0 : un pixel au stylo A.
gfx_WritePixel:
        movem.l d2-d3/a5,-(sp)
        lea     -DC_SIZE(sp),sp
        move.l  sp,a5
        movem.w d0-d1,-(sp)
        bsr     dr_ctx
        movem.w (sp)+,d0-d1
        add.w   DC_OX(a5),d0
        add.w   DC_OY(a5),d1
        move.w  d0,d2
        move.b  rp_FgPen(a1),d3
        bsr     dr_span
        bsr     dr_end
        lea     DC_SIZE(sp),sp
        movem.l (sp)+,d2-d3/a5
        moveq   #0,d0
        rts

; RectFill(rp a1, xmin d0, ymin d1, xmax d2, ymax d3) : rectangle plein au stylo A (relatif au Layer).
gfx_RectFill:
        movem.l d2-d7/a5,-(sp)
        lea     -DC_SIZE(sp),sp
        move.l  sp,a5
        move.w  d0,d4
        move.w  d1,d5
        move.w  d2,d6
        move.w  d3,d7
        bsr     dr_ctx
        add.w   DC_OX(a5),d4
        add.w   DC_OX(a5),d6
        add.w   DC_OY(a5),d5
        add.w   DC_OY(a5),d7
        move.b  rp_FgPen(a1),d3
        tst.l   rp_AreaPtrn(a1)
        bne.s   .rf_pat
.rf_lp:
        cmp.w   d7,d5
        bgt.s   .rf_ret
        move.w  d4,d0
        move.w  d5,d1
        move.w  d6,d2
        bsr     dr_span
        addq.w  #1,d5
        bra.s   .rf_lp
.rf_ret:
        bsr     dr_end
        lea     DC_SIZE(sp),sp
        movem.l (sp)+,d2-d7/a5
        rts
; motif (SetAfPt) : ligne y -> mot AreaPtrn[(y - origine) & (2^AreaPtSz - 1)], bit 15 = pixel x ≡ 0 (mod 16) de la
; couche ; plages de 1 au stylo A, plages de 0 au stylo B en JAM2 (laissées telles quelles sinon).
RP_WORD         EQU 0                ; mot du motif de la ligne
RP_VAL          EQU 2                ; byte : valeur de la plage (FF = bits à 1)
RP_X0           EQU 4                ; début de la plage
RP_X1           EQU 6                ; fin exclusive de la plage
RP_MASK         EQU 8                ; masque des lignes du motif
RP_SIZE         EQU 10
.rf_pat:
        move.l  a2,-(sp)
        lea     -RP_SIZE(sp),sp
        move.l  rp_AreaPtrn(a1),a2
        moveq   #1,d0
        move.b  rp_AreaPtSz(a1),d1
        lsl.w   d1,d0
        subq.w  #1,d0
        move.w  d0,RP_MASK(sp)
.rp_row:
        cmp.w   d7,d5
        bgt.s   .rp_ret
        move.w  d5,d0
        sub.w   DC_OY(a5),d0
        and.w   RP_MASK(sp),d0
        add.w   d0,d0
        move.w  0(a2,d0.w),RP_WORD(sp)
        move.w  d4,RP_X0(sp)
.rp_run:
        move.w  RP_X0(sp),d0
        cmp.w   d6,d0
        bgt.s   .rp_next
        bsr.s   .rp_bit
        sne     RP_VAL(sp)
.rp_ext:
        addq.w  #1,d0
        cmp.w   d6,d0
        bgt.s   .rp_emit
        bsr.s   .rp_bit
        sne     d1
        cmp.b   RP_VAL(sp),d1
        beq.s   .rp_ext
.rp_emit:
        move.w  d0,RP_X1(sp)
        tst.b   RP_VAL(sp)
        bne.s   .rp_fg
        move.b  rp_DrawMode(a1),d1
        and.b   #JAM2|COMPLEMENT,d1
        cmp.b   #JAM2,d1
        bne.s   .rp_skip
        move.b  rp_BgPen(a1),d3
        bra.s   .rp_span
.rp_fg:
        move.b  rp_FgPen(a1),d3
.rp_span:
        move.w  RP_X0(sp),d0
        move.w  d5,d1
        move.w  RP_X1(sp),d2
        subq.w  #1,d2
        bsr     dr_span
.rp_skip:
        move.w  RP_X1(sp),RP_X0(sp)
        bra.s   .rp_run
.rp_next:
        addq.w  #1,d5
        bra.s   .rp_row
.rp_ret:
        lea     RP_SIZE(sp),sp
        move.l  (sp)+,a2
        bra     .rf_ret
.rp_bit:                             ; (d0 = x) -> Z = 1 si le bit du motif vaut 0. Clobbe d1/d2.
        move.w  d0,d1
        sub.w   DC_OX(a5),d1
        not.w   d1
        and.w   #15,d1
        move.w  4+RP_WORD(sp),d2
        btst    d1,d2
        rts

; SetRast(rp a1, stylo d0) : remplit toute la zone du RastPort (bornes du Layer, sinon le BitMap).
gfx_SetRast:
        movem.l d2-d7/a5,-(sp)
        lea     -DC_SIZE(sp),sp
        move.l  sp,a5
        move.b  d0,d3
        bsr     dr_ctx
        move.b  rp_DrawMode(a1),-(sp)
        clr.b   rp_DrawMode(a1)      ; remplissage plein, quel que soit le mode
        move.w  DC_MINY(a5),d5
.sr_lp:
        cmp.w   DC_MAXY(a5),d5
        bgt.s   .sr_ret
        move.w  DC_MINX(a5),d0
        move.w  d5,d1
        move.w  DC_MAXX(a5),d2
        bsr     dr_span
        addq.w  #1,d5
        bra.s   .sr_lp
.sr_ret:
        move.b  (sp)+,rp_DrawMode(a1)
        bsr     dr_end
        lea     DC_SIZE(sp),sp
        movem.l (sp)+,d2-d7/a5
        rts

; Draw(rp a1, x d0, y d1) : segment de (cp_x, cp_y) à (x, y) au stylo A (Bresenham), puis cp := (x, y).
gfx_Draw:
        movem.l d2-d7/a2-a5,-(sp)
        lea     -DC_SIZE(sp),sp
        move.l  sp,a5
        move.w  rp_cp_x(a1),d4       ; d4,d5 = point courant ; d6,d7 = arrivée
        move.w  rp_cp_y(a1),d5
        move.w  d0,d6
        move.w  d1,d7
        move.w  d0,rp_cp_x(a1)
        move.w  d1,rp_cp_y(a1)
        bsr     dr_ctx
        move.w  DC_OX(a5),d0
        add.w   d0,d4
        add.w   d0,d6
        move.w  DC_OY(a5),d0
        add.w   d0,d5
        add.w   d0,d7
        move.w  d6,d0                ; a2 = dx = |x1-x0|, a3 = sx
        sub.w   d4,d0
        moveq   #1,d1
        tst.w   d0
        bpl.s   .dw_sx
        neg.w   d0
        moveq   #-1,d1
.dw_sx:
        move.w  d0,a2
        move.w  d1,a3
        move.w  d7,d0                ; d2 = -|y1-y0| (dy négatif), a4 = sy
        sub.w   d5,d0
        moveq   #1,d1
        tst.w   d0
        bpl.s   .dw_sy
        neg.w   d0
        moveq   #-1,d1
.dw_sy:
        neg.w   d0
        move.w  d0,-(sp)             ; (sp) = dy (négatif)
        move.w  d1,a4
        move.w  a2,d0
        add.w   (sp),d0
        move.w  d0,-(sp)             ; (sp) = err = dx + dy ; 2(sp) = dy
.dw_lp:
        movem.w d4-d5,-(sp)
        move.w  d4,d0
        move.w  d5,d1
        move.w  d4,d2
        move.b  rp_FgPen(a1),d3
        bsr     dr_span
        movem.w (sp)+,d4-d5
        cmp.w   d6,d4
        bne.s   .dw_step
        cmp.w   d7,d5
        beq.s   .dw_done
.dw_step:
        move.w  (sp),d0
        add.w   d0,d0                ; e2 = 2*err
        cmp.w   2(sp),d0
        blt.s   .dw_noy
        move.w  2(sp),d1             ; err += dy ; x += sx
        add.w   d1,(sp)
        add.w   a3,d4
.dw_noy:
        move.w  a2,d1
        cmp.w   d1,d0
        bgt.s   .dw_lp
        add.w   d1,(sp)              ; err += dx ; y += sy
        add.w   a4,d5
        bra.s   .dw_lp
.dw_done:
        addq.l  #4,sp
        bsr     dr_end
        lea     DC_SIZE(sp),sp
        movem.l (sp)+,d2-d7/a2-a5
        rts

; --- variables de Text, après le contexte de dessin (a5) ---
TX_FONT         EQU DC_SIZE          ; police
TX_W            EQU DC_SIZE+4        ; largeur du glyphe (bits, 32 au plus)
TX_RW           EQU DC_SIZE+6        ; largeur rendue (glyphe + étalement du gras)
TX_H            EQU DC_SIZE+8        ; hauteur (tf_YSize)
TX_MOD          EQU DC_SIZE+10       ; tf_Modulo
TX_SH           EQU DC_SIZE+12       ; décalage du glyphe dans son premier octet
TX_BASE         EQU DC_SIZE+14       ; tf_Baseline
TX_SMEAR        EQU DC_SIZE+16       ; tf_BoldSmear
TX_ADV          EQU DC_SIZE+18       ; avance du caractère courant
TX_STYLE        EQU DC_SIZE+20       ; byte : styles algorithmiques rendus (gras, souligné)
TX_SOK          EQU DC_SIZE+21       ; byte : voie « chaîne » permise (JAM2, police fixe de 8 pixels, sans style)
TX_GP           EQU DC_SIZE+22       ; TX_NMAX pointeurs de glyphes de la tranche courante
TX_NMAX         EQU 16
TX_FRAME        EQU DC_SIZE+22+4*TX_NMAX

; dr_cellcr(d4, d5 = coin d'une cellule de TX_W x TX_H, absolu) : cherche une ClipRect utilisable qui contient
; toute la cellule et en fait la ClipRect courante. Z = 0 si trouvée. Préserve tout sauf d0.
dr_cellcr:
        move.l  a0,-(sp)
        move.l  DC_FIRST(a5),a0
.cc_lp:
        cmpa.w  #0,a0
        beq.s   .cc_no
        bsr     dr_crset
        beq.s   .cc_n
        cmp.w   DC_CMINX(a5),d4
        blt.s   .cc_n
        cmp.w   DC_CMINY(a5),d5
        blt.s   .cc_n
        move.w  d4,d0
        add.w   TX_W(a5),d0
        subq.w  #1,d0
        cmp.w   DC_CMAXX(a5),d0
        bgt.s   .cc_n
        move.w  d5,d0
        add.w   TX_H(a5),d0
        subq.w  #1,d0
        cmp.w   DC_CMAXY(a5),d0
        bgt.s   .cc_n
        moveq   #1,d0
        bra.s   .cc_r
.cc_n:
        move.l  CR_NEXT(a0),a0
        bra.s   .cc_lp
.cc_no:
        moveq   #0,d0
.cc_r:
        move.l  (sp)+,a0
        rts

; tx_font(rp a1) -> a2 = police du RastPort, topaz 8 de la ROM s'il n'en a pas. Préserve le reste.
tx_font:
        move.l  rp_Font(a1),a2
        cmpa.w  #0,a2
        bne.s   .tf_r
        lea     topaz8_font,a2
.tf_r:
        rts
; tx_index(a2 = police, d0.w = caractère) -> d0.w = indice dans tf_CharLoc ; hors LoChar..HiChar : le glyphe par
; défaut qui suit HiChar. Clobbe d1.
tx_index:
        moveq   #0,d1
        move.b  tf_HiChar(a2),d1
        cmp.w   d1,d0
        bhi.s   .ti_def
        move.b  tf_LoChar(a2),d1
        sub.w   d1,d0
        bcc.s   .ti_r
.ti_def:
        moveq   #0,d0
        move.b  tf_HiChar(a2),d0
        move.b  tf_LoChar(a2),d1
        sub.w   d1,d0
        addq.w  #1,d0
.ti_r:
        rts
; tx_metrics(a2 = police, d0.w = indice) -> d0.w = espacement (tf_CharSpace ou tf_XSize), d1.w = crénage
; (tf_CharKern ou 0). Clobbe a0.
tx_metrics:
        add.w   d0,d0
        move.l  tf_CharKern(a2),d1
        beq.s   .tm_sp
        move.l  d1,a0
        move.w  0(a0,d0.w),d1
.tm_sp:
        tst.l   tf_CharSpace(a2)
        beq.s   .tm_fix
        move.l  tf_CharSpace(a2),a0
        move.w  0(a0,d0.w),d0
        rts
.tm_fix:
        move.w  tf_XSize(a2),d0
        rts

; BltTemplate(gabarit a0, xSrc d0, srcMod d1, rp a1, xDest d2, yDest d3, xSize d4, ySize d5) : gabarit d'un plan
; (bit à 1 = pixel du motif), ligne i à a0 + i × srcMod, premier pixel au bit xSrc. Bits à 1 au stylo A (inversés en
; COMPLEMENT) ; bits à 0 au stylo B en JAM2 ; INVERSVID permute. Coordonnées relatives à la couche, découpage par
; ses ClipRects, plans filtrés par rp_Mask (dr_span). Lu par tranches de 32 pixels.
BT_SRC          EQU DC_SIZE          ; ligne courante du gabarit
BT_MOD          EQU DC_SIZE+4        ; WORD : srcMod
BT_XS           EQU DC_SIZE+6        ; WORD : xSrc
BT_X            EQU DC_SIZE+8        ; WORD : x absolu du premier pixel
BT_Y            EQU DC_SIZE+10       ; WORD : y absolu de la ligne courante
BT_W            EQU DC_SIZE+12       ; WORD : largeur
BT_H            EQU DC_SIZE+14       ; WORD : lignes restantes
BT_FRAME        EQU DC_SIZE+16
gfx_BltTemplate:
        movem.l d2-d7/a2-a5,-(sp)
        lea     -BT_FRAME(sp),sp
        move.l  sp,a5
        move.l  a0,BT_SRC(a5)
        move.w  d1,BT_MOD(a5)
        move.w  d0,BT_XS(a5)
        move.w  d4,BT_W(a5)
        move.w  d5,BT_H(a5)
        movem.w d2-d3,-(sp)
        bsr     dr_ctx               ; clobbe d0/d1/a0
        movem.w (sp)+,d2-d3
        add.w   DC_OX(a5),d2
        move.w  d2,BT_X(a5)
        add.w   DC_OY(a5),d3
        move.w  d3,BT_Y(a5)
        tst.w   BT_W(a5)
        ble.s   .bt_end
.bt_row:
        subq.w  #1,BT_H(a5)
        bmi.s   .bt_end
        moveq   #0,d7                ; d7 = pixel de la tranche dans la ligne
.bt_chunk:
        move.w  BT_W(a5),d6
        sub.w   d7,d6                ; pixels restants
        ble.s   .bt_next
        cmp.w   #32,d6
        bls.s   .bt_n
        moveq   #32,d6
.bt_n:
        move.w  BT_XS(a5),d0         ; bit de départ = xSrc + d7
        add.w   d7,d0
        move.w  d0,d1
        lsr.w   #3,d1
        move.l  BT_SRC(a5),a0
        add.w   d1,a0
        and.w   #7,d0
        moveq   #3,d1                ; 32 bits + l'octet suivant pour le décalage (lecture par octets)
.bt_rd:
        lsl.l   #8,d2
        move.b  (a0)+,d2
        dbra    d1,.bt_rd
        lsl.l   d0,d2
        moveq   #0,d1
        move.b  (a0),d1
        lsl.w   d0,d1
        lsr.w   #8,d1
        or.b    d1,d2                ; d2 = 32 pixels, le premier en bit 31
        btst    #2,rp_DrawMode(a1)   ; INVERSVID
        beq.s   .bt_nv
        not.l   d2
.bt_nv:
        move.w  BT_X(a5),d4
        add.w   d7,d4                ; d4 = x absolu de la tranche
        move.w  BT_Y(a5),d5
        bsr.s   bt_runs
        add.w   #32,d7
        bra.s   .bt_chunk
.bt_next:
        moveq   #0,d0
        move.w  BT_MOD(a5),d0
        ext.l   d0
        add.l   d0,BT_SRC(a5)
        addq.w  #1,BT_Y(a5)
        bra.s   .bt_row
.bt_end:
        bsr     dr_end
        lea     BT_FRAME(sp),sp
        movem.l (sp)+,d2-d7/a2-a5
        rts
; bt_runs(d2 = pixels (bit 31 d'abord), d6.w = nombre, d4.w = x absolu, d5.w = y, a1 = rp, a5) : plages de même
; valeur ; 1 -> stylo A, 0 -> stylo B en JAM2 seulement. Préserve d4-d7.
bt_runs:
        movem.l d4-d7,-(sp)
        move.w  d6,d0
        move.w  d0,-(sp)             ; (sp) = nombre de pixels
        moveq   #0,d6                ; d6 = pixel courant
.br_run:
        cmp.w   (sp),d6
        bge.s   .br_ret
        move.w  d6,d7                ; début de la plage
        moveq   #31,d0
        sub.w   d6,d0
        btst    d0,d2
        sne     d3                   ; valeur de la plage
.br_ext:
        addq.w  #1,d6
        cmp.w   (sp),d6
        bge.s   .br_emit
        moveq   #31,d0
        sub.w   d6,d0
        btst    d0,d2
        sne     d1
        cmp.b   d1,d3
        beq.s   .br_ext
.br_emit:
        movem.l d2-d3,-(sp)
        tst.b   d3
        bne.s   .br_fg
        move.b  rp_DrawMode(a1),d0   ; fond : seulement en JAM2 (sans COMPLEMENT)
        and.b   #JAM2|COMPLEMENT,d0
        cmp.b   #JAM2,d0
        bne.s   .br_skip
        move.b  rp_BgPen(a1),d3
        bra.s   .br_do
.br_fg:
        move.b  rp_FgPen(a1),d3
.br_do:
        move.w  d4,d0
        add.w   d7,d0                ; x0
        move.w  d4,d2
        add.w   d6,d2
        subq.w  #1,d2                ; x1
        move.w  d5,d1
        bsr     dr_span
.br_skip:
        movem.l (sp)+,d2-d3
        bra.s   .br_run
.br_ret:
        addq.l  #2,sp
        movem.l (sp)+,d4-d7
        rts

; Text(rp a1, chaîne a0, nombre d0) : caractères de la police du RastPort (topaz 8 par défaut), coin haut du glyphe
; à cp_y - tf_Baseline, à cp_x + crénage ; cp_x avance du crénage + espacement + rp_TxSpacing. JAM1 : pixels du
; glyphe (stylo A) ; JAM2 : fond au stylo B ; COMPLEMENT : glyphe inversé ; INVERSVID : glyphe et fond permutés.
; Styles algorithmiques (rp_AlgoStyle) : gras (glyphe étalé de tf_BoldSmear) et souligné (ligne sous la base).
; Voie rapide : glyphe de 8 pixels (début d'octet dans la police), JAM1 ou JAM2, à n'importe quelle abscisse, cellule
; entière dans une ClipRect, sans style ; sinon rendu par plages de pixels.
gfx_Text:
        movem.l d2-d7/a2-a5,-(sp)
        lea     -TX_FRAME(sp),sp
        move.l  sp,a5
        move.l  a0,a4                ; a4 = chaîne
        move.w  d0,d7                ; d7 = nombre restant
        bsr     dr_ctx
        bsr     tx_font
        move.l  a2,TX_FONT(a5)
        move.w  tf_YSize(a2),TX_H(a5)
        move.w  tf_Modulo(a2),TX_MOD(a5)
        move.w  tf_Baseline(a2),TX_BASE(a5)
        move.w  tf_BoldSmear(a2),TX_SMEAR(a5)
        move.b  rp_AlgoStyle(a1),d0
        and.b   #FSF_UNDERLINED|FSF_BOLD,d0
        move.b  d0,TX_STYLE(a5)
        clr.b   TX_SOK(a5)
        tst.b   d0
        bne.s   .tx_char
        move.b  rp_DrawMode(a1),d0
        and.b   #JAM2|COMPLEMENT,d0
        cmp.b   #JAM2,d0
        bne.s   .tx_char
        tst.l   tf_CharSpace(a2)
        bne.s   .tx_char
        tst.l   tf_CharKern(a2)
        bne.s   .tx_char
        cmp.w   #8,tf_XSize(a2)
        bne.s   .tx_char
        tst.w   rp_TxSpacing(a1)
        bne.s   .tx_char
        st      TX_SOK(a5)
.tx_char:
        tst.b   TX_SOK(a5)
        beq.s   .tx_one
        cmp.w   #2,d7
        blt.s   .tx_one
        bsr     .tx_try
        bne.s   .tx_char
.tx_one:
        subq.w  #1,d7
        bmi     .tx_ret
        move.l  TX_FONT(a5),a2
        moveq   #0,d0
        move.b  (a4)+,d0
        bsr     tx_index
        move.w  d0,d3                ; d3 = indice
        bsr     tx_metrics
        add.w   d1,d0
        add.w   rp_TxSpacing(a1),d0
        move.w  d0,TX_ADV(a5)
        move.w  rp_cp_x(a1),d4
        add.w   d1,d4
        add.w   DC_OX(a5),d4         ; d4 = x absolu
        move.w  rp_cp_y(a1),d5
        sub.w   TX_BASE(a5),d5
        add.w   DC_OY(a5),d5         ; d5 = y absolu de la première ligne
        move.l  tf_CharLoc(a2),a0
        lsl.w   #2,d3
        move.w  0(a0,d3.w),d1        ; décalage en bits du glyphe
        move.w  2(a0,d3.w),d0        ; largeur
        cmp.w   #32,d0
        bls.s   .tx_wok
        moveq   #32,d0
.tx_wok:
        move.w  d0,TX_W(a5)
        move.w  d0,TX_RW(a5)
        btst    #1,TX_STYLE(a5)      ; FSF_BOLD : le glyphe s'élargit de l'étalement
        beq.s   .tx_nb
        add.w   TX_SMEAR(a5),d0
        cmp.w   #32,d0
        bls.s   .tx_rw
        moveq   #32,d0
.tx_rw:
        move.w  d0,TX_RW(a5)
.tx_nb:
        move.l  tf_CharData(a2),a3
        move.w  d1,d0
        and.w   #7,d0
        move.w  d0,TX_SH(a5)
        lsr.w   #3,d1
        add.w   d1,a3                ; a3 = premier octet du glyphe (ligne 0)
        tst.w   TX_RW(a5)
        beq.s   .tx_adv
        tst.b   TX_STYLE(a5)
        bne.s   .tx_slow
        tst.w   TX_SH(a5)
        bne.s   .tx_slow
        cmp.w   #8,TX_W(a5)
        bne.s   .tx_slow
        btst    #1,rp_DrawMode(a1)   ; COMPLEMENT : rendu par plages
        bne.s   .tx_slow
        bsr     dr_cellcr            ; cellule entière dans une seule ClipRect utilisable ?
        beq.s   .tx_slow
        bsr     .tx_fast
        bra.s   .tx_adv
.tx_slow:
        moveq   #0,d6                ; d6 = ligne du glyphe
.tx_row:
        cmp.w   TX_H(a5),d6
        bhs.s   .tx_adv
        bsr     .tx_bits             ; d2.l = ligne, pixel gauche en bit 31
        btst    #1,TX_STYLE(a5)
        beq.s   .tx_nbold
        move.l  d2,d0
        move.w  TX_SMEAR(a5),d1
        lsr.l   d1,d0
        or.l    d0,d2
.tx_nbold:
        btst    #0,TX_STYLE(a5)      ; FSF_UNDERLINED : ligne pleine juste sous la base
        beq.s   .tx_nul
        move.w  TX_BASE(a5),d0
        addq.w  #1,d0
        cmp.w   d6,d0
        bne.s   .tx_nul
        moveq   #-1,d2
.tx_nul:
        btst    #2,rp_DrawMode(a1)   ; INVERSVID
        beq.s   .tx_nv
        not.l   d2
.tx_nv:
        bsr     .tx_runs
        addq.w  #1,d5
        addq.w  #1,d6
        bra.s   .tx_row
.tx_adv:
        move.w  TX_ADV(a5),d0
        add.w   d0,rp_cp_x(a1)
        bra     .tx_char
.tx_ret:
        bsr     dr_end
        lea     TX_FRAME(sp),sp
        movem.l (sp)+,d2-d7/a2-a5
        rts
; .tx_try : voie « chaîne » sur les TX_NMAX prochains caractères au plus : glyphes de 8 pixels alignés sur l'octet,
; plage entière dans une ClipRect. Z = 0 si des caractères ont été rendus (a4, d7 et cp_x avancés). Si la plage
; déborde de toute ClipRect, la voie est abandonnée pour le reste de l'appel. Clobbe d0-d6/a0/a2/a3.
.tx_try:
        move.w  d7,d6
        cmp.w   #TX_NMAX,d6
        bls.s   .tt_n
        moveq   #TX_NMAX,d6
.tt_n:
        move.l  TX_FONT(a5),a2
        lea     TX_GP(a5),a3
        moveq   #0,d5                ; d5 = glyphes acceptés
.tt_gl:
        cmp.w   d6,d5
        bge.s   .tt_pos
        moveq   #0,d0
        move.b  0(a4,d5.w),d0
        bsr     tx_index
        lsl.w   #2,d0
        move.l  tf_CharLoc(a2),a0
        cmp.w   #8,2(a0,d0.w)        ; largeur
        bne.s   .tt_pos
        move.w  0(a0,d0.w),d1        ; décalage en bits
        moveq   #7,d2
        and.w   d1,d2
        bne.s   .tt_pos
        lsr.w   #3,d1
        move.l  tf_CharData(a2),a0
        add.w   d1,a0
        move.l  a0,(a3)+
        addq.w  #1,d5
        bra.s   .tt_gl
.tt_pos:
        move.w  d5,d6                ; d6 = caractères de la tranche
        beq.s   .tt_none
        move.w  rp_cp_x(a1),d4
        add.w   DC_OX(a5),d4
        move.w  rp_cp_y(a1),d5
        sub.w   TX_BASE(a5),d5
        add.w   DC_OY(a5),d5
        move.w  d6,d0
        lsl.w   #3,d0
        move.w  d0,TX_W(a5)
        bsr     dr_cellcr
        beq.s   .tt_off
        bsr.s   .tx_str
        add.w   d6,a4
        sub.w   d6,d7
        lsl.w   #3,d6
        add.w   d6,rp_cp_x(a1)
        moveq   #1,d0                ; Z = 0
        rts
.tt_off:
        clr.b   TX_SOK(a5)
.tt_none:
        moveq   #0,d0                ; Z = 1
        rts
; .tx_str(d6.w = n caractères, glyphes en TX_GP, d4/d5 = coin absolu, a1 = rp, ClipRect courante) : JAM2, plan par
; plan et ligne par ligne, octet de glyphe g -> (g ET m1) OU-exclusif m2 (m1 = stylos A et B différents, m2 =
; stylo B ; INVERSVID : m2 ^= m1), flux décalé de x & 7 ; les bits hors de la plage des deux octets de bord sont
; conservés. Préserve tout sauf d0/d1.
TS_N            EQU 0                ; WORD : caractères
TS_PLW          EQU 2                ; plan suivant (bm_Planes)
TS_PC           EQU 6                ; WORD : plans restants
TS_FG           EQU 8                ; byte : stylo A, décalé d'un bit par plan
TS_BG           EQU 9
TS_MSK          EQU 10
TS_MODE         EQU 11               ; byte : rp_DrawMode
TS_RC           EQU 12               ; WORD : lignes restantes
TS_DST          EQU 14               ; premier octet de la ligne courante
TS_O0           EQU 18               ; byte : octet de gauche d'origine
TS_SIZE         EQU 20
.tx_str:
        movem.l d2-d7/a1-a4/a6,-(sp)
        lea     -TS_SIZE(sp),sp
        move.l  sp,a3
        move.w  d6,TS_N(a3)
        move.b  rp_FgPen(a1),TS_FG(a3)
        move.b  rp_BgPen(a1),TS_BG(a3)
        move.b  rp_Mask(a1),TS_MSK(a3)
        move.b  rp_DrawMode(a1),TS_MODE(a3)
        move.l  DC_CBM(a5),a2
        sub.w   DC_BX(a5),d4         ; coordonnées dans le BitMap de la ClipRect
        sub.w   DC_BY(a5),d5
        moveq   #0,d0
        move.w  bm_BytesPerRow(a2),d0
        move.l  d0,a6                ; a6 = pas d'une ligne
        mulu    d5,d0
        moveq   #0,d1
        move.w  d4,d1
        lsr.w   #3,d1
        add.l   d1,d0
        move.l  d0,a4                ; a4 = décalage du premier octet
        and.w   #7,d4                ; d4 = décalage dans l'octet
        moveq   #0,d0
        move.b  bm_Depth(a2),d0
        move.w  d0,TS_PC(a3)
        pea     bm_Planes(a2)
        move.l  (sp)+,TS_PLW(a3)
.ts_plane:
        subq.w  #1,TS_PC(a3)
        bmi     .ts_ret
        move.l  TS_PLW(a3),a2
        move.l  (a2)+,a0
        move.l  a2,TS_PLW(a3)
        move.b  TS_FG(a3),d0
        lsr.b   #1,d0
        scs     d6                   ; (scs avant le move, qui efface C)
        move.b  d0,TS_FG(a3)
        move.b  TS_BG(a3),d0
        lsr.b   #1,d0
        scs     d7                   ; d7 = m2 = bit du stylo B
        move.b  d0,TS_BG(a3)
        move.b  TS_MSK(a3),d0
        lsr.b   #1,d0
        scs     d1
        move.b  d0,TS_MSK(a3)
        tst.b   d1
        beq.s   .ts_plane            ; plan protégé par rp_Mask
        eor.b   d7,d6                ; d6 = m1
        btst    #2,TS_MODE(a3)       ; INVERSVID
        beq.s   .ts_ni
        eor.b   d6,d7
.ts_ni:
        add.l   a4,a0                ; a0 = premier octet, ligne 0
        moveq   #0,d5                ; d5 = décalage de la ligne dans le glyphe
        move.w  TX_H(a5),TS_RC(a3)
.ts_row:
        subq.w  #1,TS_RC(a3)
        bmi.s   .ts_plane
        move.l  a0,TS_DST(a3)
        move.b  (a0),TS_O0(a3)
        lea     TX_GP(a5),a2
        move.w  TS_N(a3),d2
        subq.w  #1,d2
        moveq   #0,d3                ; d3 = octet précédent (8 bits hauts) et courant
.ts_ch:
        move.l  (a2)+,a1
        move.b  0(a1,d5.l),d0
        and.b   d6,d0
        eor.b   d7,d0
        lsl.w   #8,d3
        move.b  d0,d3
        move.w  d3,d0
        lsr.w   d4,d0
        move.b  d0,(a0)+
        dbra    d2,.ts_ch
        tst.w   d4
        beq.s   .ts_nx
        lsl.w   #8,d3                ; octet de droite : fin du dernier glyphe
        lsr.w   d4,d3
        moveq   #-1,d0
        lsr.b   d4,d0                ; d0 = bits de droite conservés ($FF >> décalage)
        move.b  (a0),d1
        and.b   d0,d1
        or.b    d3,d1
        move.b  d1,(a0)
        move.l  TS_DST(a3),a0        ; octet de gauche : ses bits hors plage sont restitués
        not.b   d0
        and.b   TS_O0(a3),d0
        or.b    d0,(a0)
.ts_nx:
        move.l  TS_DST(a3),a0
        add.l   a6,a0
        moveq   #0,d0
        move.w  TX_MOD(a5),d0
        add.l   d0,d5
        bra.s   .ts_row
.ts_ret:
        lea     TS_SIZE(sp),sp
        movem.l (sp)+,d2-d7/a1-a4/a6
        rts
; .tx_bits(d6 = ligne, a3 = glyphe) -> d2.l = TX_W bits de la ligne, cadrés à gauche (bit 31 = pixel gauche), le
; reste à 0. Lecture par octets (le strike peut commencer à une adresse impaire). Clobbe d0/d1/a0.
.tx_bits:
        move.w  d6,d0
        mulu    TX_MOD(a5),d0
        lea     0(a3,d0.l),a0
        moveq   #3,d1
.tb_lp:
        lsl.l   #8,d2
        move.b  (a0)+,d2
        dbra    d1,.tb_lp
        move.w  TX_SH(a5),d0
        lsl.l   d0,d2
        moveq   #0,d1
        move.b  (a0),d1
        lsl.w   d0,d1
        lsr.w   #8,d1
        or.b    d1,d2
        move.w  TX_W(a5),d0
        cmp.w   #32,d0
        bhs.s   .tb_r
        moveq   #-1,d1
        lsr.l   d0,d1
        not.l   d1
        and.l   d1,d2
.tb_r:
        rts
; .tx_fast : glyphe a3 (8 pixels, aligné) à (d4, d5) aligné sur un octet, dans la ClipRect courante, mode JAM2 :
; chaque plan autorisé par rp_Mask reçoit directement ses octets (bit à 1 -> bit du stylo A, bit à 0 -> bit du
; stylo B). Préserve d4-d7.
.tx_fast:
        movem.l d4-d7/a4/a6,-(sp)
        move.l  DC_CBM(a5),a2
        sub.w   DC_BX(a5),d4         ; coordonnées dans le BitMap de la ClipRect
        sub.w   DC_BY(a5),d5
        moveq   #0,d6
        move.w  bm_BytesPerRow(a2),d6
        move.l  d6,a4                ; a4 = pas d'une ligne
        move.w  d5,d0
        mulu    d6,d0
        moveq   #0,d1
        move.w  d4,d1
        lsr.w   #3,d1
        add.l   d1,d0                ; d0 = décalage du premier octet touché
        move.l  d0,-(sp)
        moveq   #7,d6
        and.w   d4,d6                ; d6 = décalage du glyphe dans l'octet (0..7)
        moveq   #0,d3
        move.b  bm_Depth(a2),d3
        subq.w  #1,d3                ; d3 = compteur de plans (dbra)
        lea     bm_Planes(a2),a2
        move.b  rp_FgPen(a1),d1
        move.b  rp_BgPen(a1),d2
        move.b  rp_Mask(a1),d7
.tf_plane:
        move.l  (a2)+,a0
        btst    #0,d7
        beq.s   .tf_next
        add.l   (sp),a0
        move.l  a3,a6                ; a6 = ligne du glyphe
        move.w  TX_H(a5),d4
        subq.w  #1,d4                ; d4 = compteur de lignes (dbra)
.tf_row:
        move.b  (a6),d0              ; d0 = pixels du glyphe
        btst    #2,rp_DrawMode(a1)   ; INVERSVID
        beq.s   .tf_ni
        not.b   d0
.tf_ni:
        moveq   #0,d5                ; d5 = valeur ; d0 = pixels touchés
        btst    #0,rp_DrawMode(a1)   ; JAM2 : toute la cellule
        bne.s   .tf_jam2
        btst    #0,d1                ; JAM1 : le glyphe seul, au stylo A
        beq.s   .tf_put
        move.b  d0,d5
        bra.s   .tf_put
.tf_jam2:
        btst    #0,d1
        beq.s   .tf_nf
        move.b  d0,d5
.tf_nf:
        btst    #0,d2
        beq.s   .tf_nb
        not.b   d0
        or.b    d0,d5
.tf_nb:
        moveq   #-1,d0
.tf_put:
        and.w   #$FF,d0              ; pixels touchés et valeur, placés sur deux octets selon le décalage
        and.w   #$FF,d5
        lsl.w   #8,d0
        lsl.w   #8,d5
        lsr.w   d6,d0
        lsr.w   d6,d5
        ror.w   #8,d0                ; octet de gauche
        ror.w   #8,d5
        not.b   d0
        and.b   d0,(a0)
        or.b    d5,(a0)
        not.b   d0
        tst.w   d6
        beq.s   .tf_adv
        ror.w   #8,d0                ; octet de droite
        ror.w   #8,d5
        not.b   d0
        and.b   d0,1(a0)
        or.b    d5,1(a0)
.tf_adv:
        add.l   a4,a0
        add.w   TX_MOD(a5),a6
        dbra    d4,.tf_row
.tf_next:
        lsr.b   #1,d1                ; bits des stylos et du masque pour le plan suivant
        lsr.b   #1,d2
        lsr.b   #1,d7
        dbra    d3,.tf_plane
        addq.l  #4,sp
        movem.l (sp)+,d4-d7/a4/a6
        rts
; .tx_runs : ligne d2.l (bit 31 = pixel gauche) de TX_RW pixels à (d4, d5) : découpe en plages de bits égaux ;
; bit 1 -> stylo A (ou inversion en COMPLEMENT) ; bit 0 -> stylo B en JAM2 seulement. Préserve d4-d7.
.tx_runs:
        movem.l d4-d7,-(sp)
        moveq   #0,d6                ; d6 = index du pixel courant
.tr_run:
        cmp.w   TX_RW(a5),d6
        bge.s   .tr_ret
        move.w  d6,d7                ; d7 = début de la plage
        moveq   #31,d0
        sub.w   d6,d0
        btst    d0,d2
        sne     d3                   ; d3.b = valeur de la plage ($FF / 0)
.tr_ext:
        addq.w  #1,d6
        cmp.w   TX_RW(a5),d6
        bge.s   .tr_emit
        moveq   #31,d0
        sub.w   d6,d0
        btst    d0,d2
        sne     d1
        cmp.b   d1,d3
        beq.s   .tr_ext
.tr_emit:                            ; plage [d7 .. d6-1] de valeur d3
        movem.l d2-d3,-(sp)
        tst.b   d3
        bne.s   .tr_fgp
        move.b  rp_DrawMode(a1),d0   ; fond : seulement en JAM2 (sans COMPLEMENT)
        and.b   #JAM2|COMPLEMENT,d0
        cmp.b   #JAM2,d0
        bne.s   .tr_skip
        move.b  rp_BgPen(a1),d3
        bra.s   .tr_do
.tr_fgp:
        move.b  rp_FgPen(a1),d3
.tr_do:
        move.w  d4,d0
        add.w   d7,d0                ; x0
        move.w  d4,d2
        add.w   d6,d2
        subq.w  #1,d2                ; x1
        move.w  d5,d1
        bsr     dr_span
.tr_skip:
        movem.l (sp)+,d2-d3
        bra.s   .tr_run
.tr_ret:
        movem.l (sp)+,d4-d7
        rts

; ScrollRaster(rp a1, dx d0, dy d1, xmin d2, ymin d3, xmax d4, ymax d5) : décale le contenu du rectangle de dy lignes
; vers le HAUT (dy > 0) ou le bas (dy < 0) et remplit la bande libérée au stylo B. dx ignoré (défilement vertical seul,
; suffisant pour console.device). Coordonnées relatives au Layer. Chaque ligne destination est recopiée ClipRect par
; ClipRect depuis les ClipRects qui contiennent la ligne source (écran ou sauvegardes : même alignement des bits
; modulo 16, copie par octets masqués). Une partie dont la source est cachée sans sauvegarde (couche simple) rend
; le rectangle entier « abîmé » (DamageList + LAYERREFRESH).
SC_XMIN         EQU 0                ; variables sur la pile (a4)
SC_XMAX         EQU 2
SC_DY           EQU 4
SC_Y            EQU 6                ; ligne destination courante
SC_SY           EQU 8                ; ligne source
SC_DMINX        EQU 10               ; ClipRect destination retenue : bornes en X, BitMap, origine
SC_DMAXX        EQU 12
SC_DBM          EQU 14
SC_DBX          EQU 18
SC_DBY          EQU 20
SC_COVER        EQU 22               ; pixels de la ligne destination couverts par une source
SC_LOST         EQU 24               ; byte : une source manquait
SC_YMIN         EQU 26
SC_YMAX         EQU 28
SC_SIZE         EQU 30
gfx_ScrollRaster:
        movem.l d2-d7/a2-a5,-(sp)
        lea     -DC_SIZE(sp),sp
        move.l  sp,a5
        lea     -SC_SIZE(sp),sp
        move.l  sp,a4
        movem.w d1-d5,-(sp)          ; (sp) dy, xmin, ymin, xmax, ymax
        bsr     dr_ctx
        movem.w (sp)+,d1-d5
        add.w   DC_OX(a5),d2
        add.w   DC_OX(a5),d4
        add.w   DC_OY(a5),d3
        add.w   DC_OY(a5),d5
        cmp.w   DC_MINX(a5),d2       ; découpage à la zone du RastPort
        bge.s   .sc_c0
        move.w  DC_MINX(a5),d2
.sc_c0:
        cmp.w   DC_MAXX(a5),d4
        ble.s   .sc_c1
        move.w  DC_MAXX(a5),d4
.sc_c1:
        cmp.w   DC_MINY(a5),d3
        bge.s   .sc_c2
        move.w  DC_MINY(a5),d3
.sc_c2:
        cmp.w   DC_MAXY(a5),d5
        ble.s   .sc_c3
        move.w  DC_MAXY(a5),d5
.sc_c3:
        cmp.w   d4,d2
        bgt     .sc_ret
        cmp.w   d5,d3
        bgt     .sc_ret
        tst.w   d1
        beq     .sc_ret
        move.w  d2,SC_XMIN(a4)
        move.w  d4,SC_XMAX(a4)
        move.w  d1,SC_DY(a4)
        move.w  d3,SC_YMIN(a4)
        move.w  d5,SC_YMAX(a4)
        clr.b   SC_LOST(a4)
        bsr     .sc_whole
        bne     .sc_fast
        move.w  SC_DY(a4),d1
        bmi.s   .sc_down
        move.w  SC_YMIN(a4),d6       ; vers le haut : ligne y <- y+dy, y croissant
.sc_up:
        move.w  d6,d0
        add.w   d1,d0
        cmp.w   d5,d0
        bgt.s   .sc_fillu
        move.w  d6,SC_Y(a4)
        move.w  d0,SC_SY(a4)
        bsr     .sc_line
        move.w  SC_DY(a4),d1
        addq.w  #1,d6
        bra.s   .sc_up
.sc_fillu:                           ; lignes [d6 .. ymax] au stylo B
        move.w  SC_YMAX(a4),d4
        bra.s   .sc_fill
.sc_down:
        move.w  SC_YMAX(a4),d6       ; vers le bas : y <- y+dy (dy < 0), y décroissant
.sc_dn:
        move.w  d6,d0
        add.w   d1,d0
        cmp.w   SC_YMIN(a4),d0
        blt.s   .sc_filld
        move.w  d6,SC_Y(a4)
        move.w  d0,SC_SY(a4)
        bsr     .sc_line
        move.w  SC_DY(a4),d1
        subq.w  #1,d6
        bra.s   .sc_dn
.sc_filld:                           ; lignes [ymin .. d6]
        move.w  d6,d4
        move.w  SC_YMIN(a4),d6
.sc_fill:
        move.b  rp_DrawMode(a1),-(sp)
        clr.b   rp_DrawMode(a1)
        move.b  rp_BgPen(a1),d3
.sc_flp:
        cmp.w   d4,d6
        bgt.s   .sc_fdone
        move.w  SC_XMIN(a4),d0
        move.w  d6,d1
        move.w  SC_XMAX(a4),d2
        bsr     dr_span
        addq.w  #1,d6
        bra.s   .sc_flp
.sc_fdone:
        move.b  (sp)+,rp_DrawMode(a1)
        tst.b   SC_LOST(a4)
        beq.s   .sc_ret
        bsr     .sc_damage
.sc_ret:
        bsr     dr_end
        lea     SC_SIZE+DC_SIZE(sp),sp
        movem.l (sp)+,d2-d7/a2-a5
        rts

; Voie rapide : une seule ClipRect visible contient tout le rectangle (fenêtre non recouverte) -> rectangle copié au
; blitter quand les plans sont en mémoire chip, sinon lignes copiées directement sans parcourir les ClipRects.
.sc_fast:
        bsr     .sc_blit
        tst.l   d0
        beq.s   .sf_cpu
        move.w  SC_DY(a4),d1         ; lignes découvertes, comme à la fin des boucles ligne à ligne
        bmi.s   .sf_bdn
        move.w  SC_YMAX(a4),d6
        sub.w   d1,d6
        addq.w  #1,d6
        bra     .sc_fillu
.sf_bdn:
        move.w  SC_YMIN(a4),d6
        sub.w   d1,d6
        subq.w  #1,d6
        bra     .sc_filld
.sf_cpu:
        tst.w   SC_DY(a4)
        bmi.s   .sf_down
        move.w  SC_YMIN(a4),d6
.sf_up:
        move.w  d6,d0
        add.w   SC_DY(a4),d0
        cmp.w   SC_YMAX(a4),d0
        bgt     .sc_fillu
        move.w  d6,SC_Y(a4)
        move.w  d0,SC_SY(a4)
        move.w  SC_XMIN(a4),d2
        move.w  SC_XMAX(a4),d4
        bsr     .sc_copy
        addq.w  #1,d6
        bra.s   .sf_up
.sf_down:
        move.w  SC_YMAX(a4),d6
.sf_dn:
        move.w  d6,d0
        add.w   SC_DY(a4),d0
        cmp.w   SC_YMIN(a4),d0
        blt     .sc_filld
        move.w  d6,SC_Y(a4)
        move.w  d0,SC_SY(a4)
        move.w  SC_XMIN(a4),d2
        move.w  SC_XMAX(a4),d4
        bsr     .sc_copy
        subq.w  #1,d6
        bra.s   .sf_dn

; .sc_blit(a6 = GfxBase) -> d0 = 1 si le rectangle déplacé ([SC_XMIN..SC_XMAX], hauteur moins |dy| lignes, au moins
; une) a été copié au blitter dans SC_DBM (source = destination), 0 sinon (plan hors mémoire chip, rectangle trop large
; ou trop haut pour un blit, ou entièrement découvert : rien de fait). Un blit par plan : A = $FFFF constant masqué
; (premier/dernier mot), B = source, C = destination, D = AB + ~AC ; vers le bas : mode descendant (adresses de fin,
; masques échangés). Blitter pris par OwnBlitter. Préserve d2-d7/a1-a6.
BLT_CON0        EQU $040
BLT_CON1        EQU $042
BLT_AFWM        EQU $044
BLT_ALWM        EQU $046
BLT_CPT         EQU $048
BLT_BPT         EQU $04C
BLT_DPT         EQU $054
BLT_SIZE        EQU $058
BLT_CMOD        EQU $060
BLT_BMOD        EQU $062
BLT_DMOD        EQU $066
BLT_ADAT        EQU $074
BLT_DMACONR     EQU $002
.sc_blit:
        movem.l d2-d7/a1-a3/a6,-(sp)
        move.l  SC_DBM(a4),a2        ; a2 = BitMap
        move.w  SC_YMAX(a4),d4       ; d4 = lignes copiées
        sub.w   SC_YMIN(a4),d4
        addq.w  #1,d4
        move.w  SC_DY(a4),d0
        bpl.s   .bl_ady
        neg.w   d0
.bl_ady:
        sub.w   d0,d4
        ble     .bl_no               ; tout est découvert : seul le remplissage reste
        cmp.w   #1024,d4
        bhi     .bl_no
        move.l  a6,a3                ; a3 = GfxBase
        move.l  ($4).w,a6
        moveq   #0,d6
.bl_chip:
        cmp.b   bm_Depth(a2),d6
        bge.s   .bl_go
        move.w  d6,d0
        lsl.w   #2,d0
        move.l  bm_Planes(a2,d0.w),a1
        jsr     LVO_TYPEOFMEM(a6)
        btst    #1,d0                ; MEMF_CHIP : seule mémoire que le blitter atteint
        beq     .bl_no
        addq.w  #1,d6
        bra.s   .bl_chip
.bl_go:
        move.w  SC_XMIN(a4),d2       ; colonnes relatives au BitMap
        sub.w   SC_DBX(a4),d2
        move.w  SC_XMAX(a4),d3
        sub.w   SC_DBX(a4),d3
        move.w  d2,d6
        lsr.w   #4,d6                ; d6 = premier mot
        move.w  d3,d5
        lsr.w   #4,d5
        sub.w   d6,d5
        addq.w  #1,d5                ; d5 = mots par ligne
        cmp.w   #64,d5
        bhi     .bl_no
        lsl.w   #6,d4
        or.w    d5,d4                ; d4 = BLTSIZE (hauteur << 6 | mots ; 1024 lignes = 0)
        and.w   #15,d2
        moveq   #-1,d0
        lsr.w   d2,d0
        move.w  d0,d2                ; d2 = masque du mot de gauche
        and.w   #15,d3
        moveq   #15,d1
        sub.w   d3,d1
        moveq   #-1,d3
        lsl.w   d1,d3                ; d3 = masque du mot de droite
        move.w  SC_YMIN(a4),d0       ; vers le haut : destination ymin, source ymin + dy, premier mot
        tst.w   SC_DY(a4)
        bpl.s   .bl_rows
        move.w  SC_YMAX(a4),d0       ; vers le bas : dernière ligne et dernier mot, en descendant
        add.w   d5,d6
        subq.w  #1,d6
        exg     d2,d3                ; en descendant, le premier mot traité est celui de droite
.bl_rows:
        move.w  d0,d1
        add.w   SC_DY(a4),d1
        sub.w   SC_DBY(a4),d0
        sub.w   SC_DBY(a4),d1
        moveq   #0,d7
        move.w  bm_BytesPerRow(a2),d7
        mulu    d7,d0                ; d0 = décalage destination
        mulu    d7,d1                ; d1 = décalage source
        add.w   d6,d6
        and.l   #$FFFF,d6
        add.l   d6,d0
        add.l   d6,d1
        add.w   d5,d5
        sub.w   d5,d7                ; d7 = modulo (octets sautés par ligne)
        moveq   #0,d6                ; d6 = BLTCON1
        tst.w   SC_DY(a4)
        bpl.s   .bl_own
        moveq   #2,d6                ; DESC
.bl_own:
        move.l  a3,a6
        movem.l d0-d1,-(sp)
        jsr     gfx_OwnBlitter
        movem.l (sp)+,d0-d1
        move.w  #$8240,DMACON        ; DMA maître + blitter
        lea     CUSTOM,a0
        moveq   #0,d5                ; d5 = plan
.bl_plane:
        cmp.b   bm_Depth(a2),d5
        bge.s   .bl_done
        move.w  d5,a1
        add.w   a1,a1
        add.w   a1,a1
        move.l  bm_Planes(a2,a1.w),a1
        btst    #6,BLT_DMACONR(a0)   ; lecture bidon (quirk A1000), puis attente du blit précédent
.bl_wait:
        btst    #6,BLT_DMACONR(a0)
        bne.s   .bl_wait
        move.w  #$07CA,BLT_CON0(a0)  ; B, C, D actifs ; minterme AB + ~AC
        move.w  d6,BLT_CON1(a0)
        move.w  d2,BLT_AFWM(a0)
        move.w  d3,BLT_ALWM(a0)
        move.w  #$FFFF,BLT_ADAT(a0)
        move.w  d7,BLT_BMOD(a0)
        move.w  d7,BLT_CMOD(a0)
        move.w  d7,BLT_DMOD(a0)
        pea     0(a1,d1.l)
        move.l  (sp)+,BLT_BPT(a0)
        pea     0(a1,d0.l)
        move.l  (sp),BLT_CPT(a0)
        move.l  (sp)+,BLT_DPT(a0)
        move.w  d4,BLT_SIZE(a0)
        addq.w  #1,d5
        bra.s   .bl_plane
.bl_done:
        btst    #6,BLT_DMACONR(a0)
.bl_wend:
        btst    #6,BLT_DMACONR(a0)
        bne.s   .bl_wend
        jsr     gfx_DisownBlitter
        moveq   #1,d0
        bra.s   .bl_ret
.bl_no:
        moveq   #0,d0
.bl_ret:
        movem.l (sp)+,d2-d7/a1-a3/a6
        rts

; .sc_whole -> Z = 0 si une ClipRect visible contient tout [SC_XMIN..SC_XMAX] x [SC_YMIN..SC_YMAX] : elle devient
; la ClipRect courante (source) et la destination (SC_DBM/DBX/DBY). Clobbe d0/a0.
.sc_whole:
        move.l  DC_FIRST(a5),a0
.sw_lp:
        cmpa.w  #0,a0
        beq.s   .sw_no
        tst.l   CR_LOBS(a0)
        bne.s   .sw_next
        bsr     dr_crset
        beq.s   .sw_next
        move.w  SC_XMIN(a4),d0
        cmp.w   DC_CMINX(a5),d0
        blt.s   .sw_next
        move.w  SC_XMAX(a4),d0
        cmp.w   DC_CMAXX(a5),d0
        bgt.s   .sw_next
        move.w  SC_YMIN(a4),d0
        cmp.w   DC_CMINY(a5),d0
        blt.s   .sw_next
        move.w  SC_YMAX(a4),d0
        cmp.w   DC_CMAXY(a5),d0
        bgt.s   .sw_next
        move.l  DC_CBM(a5),SC_DBM(a4)
        move.l  DC_BX(a5),SC_DBX(a4)
        moveq   #1,d0
        rts
.sw_next:
        move.l  CR_NEXT(a0),a0
        bra.s   .sw_lp
.sw_no:
        moveq   #0,d0
        rts

; .sc_line : ligne SC_Y <- ligne SC_SY sur [SC_XMIN..SC_XMAX], ClipRect par ClipRect. Préserve d4-d7/a1.
.sc_line:
        movem.l d4-d7/a1-a3,-(sp)
        move.l  DC_FIRST(a5),a2      ; a2 = ClipRect destination
.sl_dst:
        cmpa.w  #0,a2
        beq     .sl_r
        move.l  a2,a0
        bsr     dr_crset
        beq     .sl_dnext
        move.w  SC_Y(a4),d0
        cmp.w   DC_CMINY(a5),d0
        blt     .sl_dnext
        cmp.w   DC_CMAXY(a5),d0
        bgt     .sl_dnext
        move.w  SC_XMIN(a4),d0       ; segment destination
        cmp.w   DC_CMINX(a5),d0
        bge.s   .sl_1
        move.w  DC_CMINX(a5),d0
.sl_1:
        move.w  SC_XMAX(a4),d1
        cmp.w   DC_CMAXX(a5),d1
        ble.s   .sl_2
        move.w  DC_CMAXX(a5),d1
.sl_2:
        cmp.w   d1,d0
        bgt     .sl_dnext
        move.w  d0,SC_DMINX(a4)
        move.w  d1,SC_DMAXX(a4)
        move.l  DC_CBM(a5),SC_DBM(a4)
        move.l  DC_BX(a5),SC_DBX(a4)   ; BX, BY
        clr.w   SC_COVER(a4)
        move.l  DC_FIRST(a5),a3      ; a3 = ClipRect source
.sl_src:
        cmpa.w  #0,a3
        beq.s   .sl_check
        move.l  a3,a0
        bsr     dr_crset
        beq.s   .sl_snext
        move.w  SC_SY(a4),d0
        cmp.w   DC_CMINY(a5),d0
        blt.s   .sl_snext
        cmp.w   DC_CMAXY(a5),d0
        bgt.s   .sl_snext
        move.w  SC_DMINX(a4),d2      ; segment commun
        cmp.w   DC_CMINX(a5),d2
        bge.s   .sl_3
        move.w  DC_CMINX(a5),d2
.sl_3:
        move.w  SC_DMAXX(a4),d4
        cmp.w   DC_CMAXX(a5),d4
        ble.s   .sl_4
        move.w  DC_CMAXX(a5),d4
.sl_4:
        cmp.w   d4,d2
        bgt.s   .sl_snext
        move.w  d4,d0
        sub.w   d2,d0
        addq.w  #1,d0
        add.w   d0,SC_COVER(a4)
        bsr     .sc_copy
.sl_snext:
        move.l  CR_NEXT(a3),a3
        bra.s   .sl_src
.sl_check:
        move.w  SC_DMAXX(a4),d0
        sub.w   SC_DMINX(a4),d0
        addq.w  #1,d0
        cmp.w   SC_COVER(a4),d0
        ble.s   .sl_dnext
        st      SC_LOST(a4)          ; une partie n'avait pas de source
.sl_dnext:
        move.l  CR_NEXT(a2),a2
        bra     .sl_dst
.sl_r:
        movem.l (sp)+,d4-d7/a1-a3
        rts

; .sc_copy(d2..d4 = segment absolu ; source = ClipRect courante (DC_CBM, DC_BX/BY, ligne SC_SY) ; destination =
; SC_DBM / SC_DBX / SC_DBY, ligne SC_Y) : pixels copiés plan par plan, octets de bord masqués. Préserve d4-d7/a1-a3.
.sc_copy:
        movem.l d4-d7/a1-a3,-(sp)
        move.l  DC_CBM(a5),a2        ; a2 = BitMap source, a3 = BitMap destination
        move.l  SC_DBM(a4),a3
        move.w  SC_SY(a4),d0
        sub.w   DC_BY(a5),d0
        moveq   #0,d5
        move.w  bm_BytesPerRow(a2),d5
        mulu    d0,d5
        move.w  d2,d0
        sub.w   DC_BX(a5),d0
        lsr.w   #3,d0
        add.l   d0,d5                ; d5 = décalage du premier octet source
        move.w  SC_Y(a4),d0
        sub.w   SC_DBY(a4),d0
        moveq   #0,d6
        move.w  bm_BytesPerRow(a3),d6
        mulu    d0,d6
        move.w  d2,d0
        sub.w   SC_DBX(a4),d0
        lsr.w   #3,d0
        add.l   d0,d6                ; d6 = décalage du premier octet destination
        move.w  d4,d7                ; d7 = octets après le premier
        lsr.w   #3,d7
        move.w  d2,d0
        lsr.w   #3,d0
        sub.w   d0,d7
        move.w  d2,d0                ; d2.b = masque gauche, d3.b = masque droit
        and.w   #7,d0
        moveq   #-1,d2
        lsr.b   d0,d2
        move.w  d4,d0
        and.w   #7,d0
        moveq   #7,d1
        sub.w   d0,d1
        moveq   #-1,d3
        lsl.b   d1,d3
        tst.w   d7
        bne.s   .cp_m
        and.b   d3,d2                ; octet unique : masques combinés
.cp_m:
        moveq   #0,d4                ; d4 = plan
.cp_plane:
        cmp.b   bm_Depth(a2),d4
        bge.s   .cp_r
        cmp.b   bm_Depth(a3),d4
        bge.s   .cp_r
        move.w  d4,d0
        lsl.w   #2,d0
        move.l  bm_Planes(a2,d0.w),a0
        move.l  bm_Planes(a3,d0.w),a1
        add.l   d5,a0
        add.l   d6,a1
        move.b  d2,d0                ; premier octet
        bsr.s   .cp_mask
        tst.w   d7
        beq.s   .cp_pdone
        move.w  d7,d1
        subq.w  #1,d1                ; octets pleins
        beq.s   .cp_last
        bsr.s   .cp_run
.cp_last:
        move.b  d3,d0                ; dernier octet
        bsr.s   .cp_mask
.cp_pdone:
        addq.w  #1,d4
        bra.s   .cp_plane
.cp_r:
        movem.l (sp)+,d4-d7/a1-a3
        rts
; .cp_run(d1.w = octets, > 0) : copie (a0)+ -> (a1)+, par longs quand les deux adresses ont la même parité (cas du
; défilement : même abscisse). Clobbe d0/d1.
.cp_run:
        move.l  a0,d0
        sub.l   a1,d0
        btst    #0,d0
        bne.s   .cr_bx               ; parités différentes : octet par octet
        move.w  a0,d0
        btst    #0,d0
        beq.s   .cr_even
        move.b  (a0)+,(a1)+
        subq.w  #1,d1
.cr_even:
        move.w  d1,d0
        lsr.w   #2,d0
        bra.s   .cr_lx
.cr_l:
        move.l  (a0)+,(a1)+
.cr_lx:
        dbra    d0,.cr_l
        and.w   #3,d1
        bra.s   .cr_bx
.cr_b:
        move.b  (a0)+,(a1)+
.cr_bx:
        dbra    d1,.cr_b
        rts
; .cp_mask(d0.b = masque) : dst = (dst & ~m) | (src & m) pour l'octet courant ; avance a0/a1. Clobbe d0/d1.
.cp_mask:
        move.b  (a0)+,d1
        and.b   d0,d1
        not.b   d0
        and.b   d0,(a1)
        or.b    d1,(a1)+
        rts

; .sc_damage : rectangle de défilement (relatif à la couche) ajouté à la DamageList de la couche + LAYERREFRESH.
.sc_damage:
        move.l  DC_LAYER(a5),d0
        beq.s   .sd_r
        move.l  d0,a0
        or.w    #LAYERREFRESH,LY_FLAGS(a0)
        move.l  LY_DAMAGE(a0),d0
        beq.s   .sd_r
        movem.l a1/a6,-(sp)
        move.w  SC_YMAX(a4),-(sp)
        move.w  SC_XMAX(a4),-(sp)
        move.w  SC_YMIN(a4),-(sp)
        move.w  SC_XMIN(a4),-(sp)
        move.w  16(a0),d1            ; bornes de la couche
        sub.w   d1,(sp)
        sub.w   d1,4(sp)
        move.w  18(a0),d1
        sub.w   d1,2(sp)
        sub.w   d1,6(sp)
        move.l  d0,a0
        move.l  sp,a1
        bsr     gfx_OrRectRegion
        addq.l  #8,sp
        movem.l (sp)+,a1/a6
.sd_r:
        rts

; BltBitMapRastPort(BitMap a0, srcX d0, srcY d1, RastPort a1, destX d2, destY d3, largeur d4, hauteur d5, minterm d6) :
; copie le rectangle source dans le RastPort (relatif au Layer, découpé au contexte), plan par plan selon rp_Mask.
; Minterm appliqué (B = source, C = destination). Plan source NULL = tout à 0,
; -1 = tout à 1 (les plans au-delà de la profondeur source valent 0). Rendu CPU octet par octet, bords masqués.
gfx_BltBitMapRastPort:
        movem.l d2-d7/a1-a5,-(sp)
        lea     -DC_SIZE(sp),sp
        move.l  sp,a5
        move.l  a0,a4                ; a4 = BitMap source
        move.b  d6,DC_MINTERM(a5)
        movem.w d0-d1,-(sp)
        bsr     dr_ctx
        movem.w (sp)+,d0-d1
        add.w   DC_OX(a5),d2
        add.w   DC_OY(a5),d3
        movem.w d0-d5,-(sp)          ; 4(sp) : arguments (destination absolue)
        move.l  DC_FIRST(a5),-(sp)   ; (sp) : ClipRect courante
.bb_cr:
        move.l  (sp),a0
        cmpa.w  #0,a0
        beq.s   .bb_done
        bsr     dr_crset
        beq.s   .bb_crn
        movem.w 4(sp),d0-d5
        bsr.s   .bb_one
.bb_crn:
        move.l  (sp),a0
        move.l  CR_NEXT(a0),(sp)
        bra.s   .bb_cr
.bb_done:
        lea     16(sp),sp
        bsr     dr_end
        lea     DC_SIZE(sp),sp
        movem.l (sp)+,d2-d7/a1-a5
        rts
; .bb_one(d0..d5 = sx, sy, dx, dy absolus, largeur, hauteur) : partie dans la ClipRect courante. Clobbe d0-d7/a0-a3.
.bb_one:
        move.w  DC_CMINX(a5),d6      ; découpage gauche/haut : décale aussi la source
        sub.w   d2,d6
        ble.s   .bb_l
        add.w   d6,d0
        sub.w   d6,d4
        add.w   d6,d2
.bb_l:
        move.w  DC_CMINY(a5),d6
        sub.w   d3,d6
        ble.s   .bb_t
        add.w   d6,d1
        sub.w   d6,d5
        add.w   d6,d3
.bb_t:
        move.w  DC_CMAXX(a5),d6      ; découpage droit/bas
        sub.w   d2,d6
        addq.w  #1,d6
        cmp.w   d6,d4
        ble.s   .bb_r
        move.w  d6,d4
.bb_r:
        move.w  DC_CMAXY(a5),d6
        sub.w   d3,d6
        addq.w  #1,d6
        cmp.w   d6,d5
        ble.s   .bb_b
        move.w  d6,d5
.bb_b:
        tst.w   d4
        ble     .bb_oret
        tst.w   d5
        ble     .bb_oret
        sub.w   DC_BX(a5),d2         ; coordonnées dans le BitMap de la ClipRect
        sub.w   DC_BY(a5),d3
        move.l  DC_CBM(a5),a3        ; a3 = BitMap destination
        moveq   #0,d7                ; d7 = plan
.bb_plane:
        moveq   #0,d6
        move.b  bm_Depth(a3),d6
        cmp.w   d6,d7
        bge     .bb_oret
        move.l  DC_RP(a5),a0
        move.b  rp_Mask(a0),d6
        btst    d7,d6
        beq     .bb_pnext
        moveq   #0,d6                ; a2 = plan source (0 / -1 / adresse)
        move.b  bm_Depth(a4),d6
        sub.l   a2,a2
        cmp.w   d6,d7
        bge.s   .bb_src
        move.w  d7,d6
        lsl.w   #2,d6
        move.l  bm_Planes(a4,d6.w),a2
.bb_src:
        movem.l d0-d5/d7/a2,-(sp)    ; lignes : d1 = ligne source, d3 = ligne destination, d5 = compteur
.bb_row:
        movem.l d0-d5/d7/a2,-(sp)
        move.l  a2,d6                ; adresse de la ligne source (sauf plan constant)
        beq.s   .bb_const
        cmp.l   #-1,d6
        beq.s   .bb_const
        moveq   #0,d6
        move.w  bm_BytesPerRow(a4),d6
        mulu    d1,d6
        add.l   d6,a2
.bb_const:
        move.w  d7,d6                ; a1 = ligne destination
        lsl.w   #2,d6
        move.l  bm_Planes(a3,d6.w),a1
        moveq   #0,d6
        move.w  bm_BytesPerRow(a3),d6
        mulu    d3,d6
        add.l   d6,a1
        bsr     dr_bits
        movem.l (sp)+,d0-d5/d7/a2
        addq.w  #1,d1
        addq.w  #1,d3
        subq.w  #1,d5
        bne.s   .bb_row
        movem.l (sp)+,d0-d5/d7/a2
.bb_pnext:
        addq.w  #1,d7
        bra     .bb_plane
.bb_oret:
        rts
; dr_bits(a2 = ligne source | 0 | -1, d0 = bit source, a1 = ligne destination, d2 = bit destination, d4 = largeur,
; a5 = contexte : DC_MINTERM) : combine d4 bits. Pour chaque octet destination : 8 bits source alignés (deux octets
; lus puis décalés), masques de bord calculés une fois ; résultat = minterm(B = source, C = destination), le canal A
; du blitter valant 1 (seuls les bits 7-4 du minterm comptent). Clobbe d0-d7/a0.
dr_bits:
        move.w  d2,d5
        lsr.w   #3,d5                ; d5 = octet destination courant (le premier)
        move.w  d5,-(sp)             ; (sp) = premier octet
        move.w  d2,d7
        add.w   d4,d7
        subq.w  #1,d7                ; d7 = dernier bit destination
        moveq   #-1,d1               ; d1.b = masque du premier octet : pixels >= destX
        move.w  d2,d3
        and.w   #7,d3
        lsr.b   d3,d1
        move.w  d7,d3                ; d2.b = masque du dernier octet : pixels <= dernier bit
        and.w   #7,d3
        moveq   #7,d4
        sub.w   d3,d4
        sub.w   d2,d0                ; d0 = bit source - bit destination
        moveq   #-1,d2
        lsl.b   d4,d2
        lsr.w   #3,d7                ; d7 = dernier octet destination
        cmp.b   #$C0,DC_MINTERM(a5)  ; voie rapide : copie d'un plan réel, décalage multiple de 8 (sauvegardes de
        bne.s   .bt_byte             ; layers : même position des bits modulo 16) -> octets recopiés tels quels
        move.l  a2,d4
        beq.s   .bt_byte
        addq.l  #1,d4
        beq.s   .bt_byte
        moveq   #7,d4
        and.w   d0,d4
        bne.s   .bt_byte
        move.l  a1,-(sp)
        asr.w   #3,d0
        lea     0(a2,d0.w),a0
        add.w   d5,a0                ; a0 = source du premier octet destination
        add.w   d5,a1
        cmp.w   d5,d7
        bne.s   .bf_multi
        and.b   d2,d1                ; un seul octet : les deux masques
        move.b  (a0),d4
        and.b   d1,d4
        not.b   d1
        and.b   d1,(a1)
        or.b    d4,(a1)
        bra.s   .bf_done
.bf_multi:
        move.b  (a0)+,d4             ; premier octet (masqué)
        and.b   d1,d4
        not.b   d1
        and.b   d1,(a1)
        or.b    d4,(a1)+
        sub.w   d5,d7
        subq.w  #1,d7                ; d7 = octets pleins
        beq.s   .bf_last
        move.w  a0,d3                ; même parité : alignement sur un mot puis copie par longs
        move.w  a1,d4
        eor.w   d4,d3
        btst    #0,d3
        bne.s   .bf_bytes
        move.w  a0,d3
        btst    #0,d3
        beq.s   .bf_even
        move.b  (a0)+,(a1)+
        subq.w  #1,d7
.bf_even:
        move.w  d7,d4
        lsr.w   #2,d4
        and.w   #3,d7
        bra.s   .bf_lnx
.bf_long:
        move.l  (a0)+,(a1)+
.bf_lnx:
        dbra    d4,.bf_long
.bf_bytes:
        subq.w  #1,d7
        bmi.s   .bf_last
.bf_mid:
        move.b  (a0)+,(a1)+
        dbra    d7,.bf_mid
.bf_last:
        move.b  (a0),d4              ; dernier octet (masqué)
        and.b   d2,d4
        not.b   d2
        and.b   d2,(a1)
        or.b    d4,(a1)
.bf_done:
        move.l  (sp)+,a1
        addq.l  #2,sp
        rts
.bt_byte:
        moveq   #-1,d6               ; d6.b = masque de l'octet
        cmp.w   (sp),d5
        bne.s   .bt_nf
        and.b   d1,d6
.bt_nf:
        cmp.w   d7,d5
        bne.s   .bt_nl
        and.b   d2,d6
.bt_nl:
        move.l  a2,d4
        beq.s   .bt_put              ; plan source nul : 0
        moveq   #-1,d4
        cmp.l   a2,d4
        beq.s   .bt_put              ; plan source -1 : 1
        move.w  d5,d3                ; bit source du pixel de gauche de l'octet
        lsl.w   #3,d3
        add.w   d0,d3
        move.w  d3,d4
        asr.w   #3,d4                ; octet source (-1 possible au bord gauche : bits masqués)
        lea     0(a2,d4.w),a0
        move.b  (a0)+,d4
        lsl.w   #8,d4
        move.b  (a0),d4
        and.w   #7,d3
        lsl.w   d3,d4
        lsr.w   #8,d4
.bt_put:
        cmp.b   #$C0,DC_MINTERM(a5)
        beq.s   .bt_copy             ; copie : voie directe
        movem.l d0-d2,-(sp)
        move.b  0(a1,d5.w),d3        ; C = destination
        moveq   #0,d1                ; d1 = résultat
        move.b  DC_MINTERM(a5),d0
        btst    #7,d0                ; B & C
        beq.s   .mt_6
        move.b  d4,d2
        and.b   d3,d2
        or.b    d2,d1
.mt_6:
        btst    #6,d0                ; B & ~C
        beq.s   .mt_5
        move.b  d3,d2
        not.b   d2
        and.b   d4,d2
        or.b    d2,d1
.mt_5:
        btst    #5,d0                ; ~B & C
        beq.s   .mt_4
        move.b  d4,d2
        not.b   d2
        and.b   d3,d2
        or.b    d2,d1
.mt_4:
        btst    #4,d0                ; ~B & ~C
        beq.s   .mt_r
        move.b  d4,d2
        or.b    d3,d2
        not.b   d2
        or.b    d2,d1
.mt_r:
        move.b  d1,d4
        movem.l (sp)+,d0-d2
.bt_copy:
        and.b   d6,d4
        not.b   d6
        and.b   d6,0(a1,d5.w)
        or.b    d4,0(a1,d5.w)
        addq.w  #1,d5
        cmp.w   d7,d5
        ble     .bt_byte
        addq.l  #2,sp
        rts

; BltBitMap(src a0, srcX d0, srcY d1, dest a1, destX d2, destY d3, largeur d4, hauteur d5, minterm d6, masque d7,
; tampon a2 ignoré) -> d0 = nombre de plans traités. Rectangle découpé aux deux BitMaps. Plans : ceux du masque
; présents dans la destination (plan destination NULL ou -1 ignoré) ; un plan source absent, NULL ou -1 vaut
; 0 / 0 / 1. Même BitMap source et destination : chaque ligne source passe par un tampon (aucun recouvrement
; possible dans la ligne) et les lignes sont parcourues du bas vers le haut si la destination est plus basse.
; Cadre : contexte DC (DC_MINTERM pour dr_bits) suivi des variables BB_*.
BB_SX           EQU DC_SIZE
BB_SY           EQU DC_SIZE+2
BB_DX           EQU DC_SIZE+4
BB_DY           EQU DC_SIZE+6
BB_W            EQU DC_SIZE+8
BB_H            EQU DC_SIZE+10
BB_PLANE        EQU DC_SIZE+12           ; n° du plan courant
BB_COUNT        EQU DC_SIZE+14           ; plans traités
BB_STEP         EQU DC_SIZE+16           ; +1 / -1 entre lignes
BB_CSY          EQU DC_SIZE+18           ; ligne source courante
BB_CDY          EQU DC_SIZE+20           ; ligne destination courante
BB_N            EQU DC_SIZE+22           ; lignes restantes
BB_MASK         EQU DC_SIZE+24           ; byte
BB_BUF          EQU DC_SIZE+26           ; long : tampon de ligne (0 si BitMaps distincts)
BB_SPLANE       EQU DC_SIZE+30           ; long : plan source courant (0 / -1 / adresse)
BB_SIZE         EQU DC_SIZE+34
gfx_BltBitMap:
        movem.l d2-d7/a2-a6,-(sp)
        lea     -BB_SIZE(sp),sp
        move.l  sp,a5
        move.b  d6,DC_MINTERM(a5)
        move.b  d7,BB_MASK(a5)
        move.l  a0,a4                ; a4 = source, a3 = destination
        move.l  a1,a3
        clr.w   BB_COUNT(a5)
        tst.w   d0                   ; découpage aux deux BitMaps : bords gauche / haut
        bpl.s   .bm_1
        add.w   d0,d4
        sub.w   d0,d2
        moveq   #0,d0
.bm_1:
        tst.w   d2
        bpl.s   .bm_2
        add.w   d2,d4
        sub.w   d2,d0
        moveq   #0,d2
.bm_2:
        tst.w   d1
        bpl.s   .bm_3
        add.w   d1,d5
        sub.w   d1,d3
        moveq   #0,d1
.bm_3:
        tst.w   d3
        bpl.s   .bm_4
        add.w   d3,d5
        sub.w   d3,d1
        moveq   #0,d3
.bm_4:
        move.w  bm_BytesPerRow(a4),d6    ; bords droit / bas
        lsl.w   #3,d6
        sub.w   d0,d6
        cmp.w   d6,d4
        ble.s   .bm_5
        move.w  d6,d4
.bm_5:
        move.w  bm_BytesPerRow(a3),d6
        lsl.w   #3,d6
        sub.w   d2,d6
        cmp.w   d6,d4
        ble.s   .bm_6
        move.w  d6,d4
.bm_6:
        move.w  bm_Rows(a4),d6
        sub.w   d1,d6
        cmp.w   d6,d5
        ble.s   .bm_7
        move.w  d6,d5
.bm_7:
        move.w  bm_Rows(a3),d6
        sub.w   d3,d6
        cmp.w   d6,d5
        ble.s   .bm_8
        move.w  d6,d5
.bm_8:
        tst.w   d4
        ble     .bm_ret
        tst.w   d5
        ble     .bm_ret
        movem.w d0-d5,BB_SX(a5)
        clr.l   BB_BUF(a5)
        cmp.l   a3,a4
        bne.s   .bm_go
        moveq   #0,d0                ; même BitMap : tampon de ligne (+1 octet de marge de chaque côté)
        move.w  bm_BytesPerRow(a4),d0
        addq.l  #4,d0
        moveq   #MEMF_PUBLIC,d1
        move.l  ($4).w,a6
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .bm_ret              ; pas de tampon : on refuse plutôt que de corrompre
        addq.l  #1,d0
        move.l  d0,BB_BUF(a5)
.bm_go:
        clr.w   BB_PLANE(a5)
.bm_plane:
        move.w  BB_PLANE(a5),d6
        moveq   #0,d0
        move.b  bm_Depth(a3),d0
        cmp.w   d0,d6
        bge     .bm_free
        move.b  BB_MASK(a5),d0
        btst    d6,d0
        beq     .bm_pnext
        move.w  d6,d0
        lsl.w   #2,d0
        move.l  bm_Planes(a3,d0.w),d1
        beq     .bm_pnext
        cmp.l   #-1,d1
        beq     .bm_pnext
        addq.w  #1,BB_COUNT(a5)
        clr.l   BB_SPLANE(a5)
        moveq   #0,d1
        move.b  bm_Depth(a4),d1
        cmp.w   d1,d6
        bge.s   .bm_rows
        move.l  bm_Planes(a4,d0.w),BB_SPLANE(a5)
.bm_rows:
        move.w  BB_SY(a5),BB_CSY(a5)
        move.w  BB_DY(a5),BB_CDY(a5)
        move.w  BB_H(a5),BB_N(a5)
        move.w  #1,BB_STEP(a5)
        tst.l   BB_BUF(a5)
        beq.s   .bm_row
        move.w  BB_DY(a5),d0
        cmp.w   BB_SY(a5),d0
        ble.s   .bm_row
        move.w  BB_H(a5),d0          ; destination plus basse : du bas vers le haut
        subq.w  #1,d0
        add.w   d0,BB_CSY(a5)
        add.w   d0,BB_CDY(a5)
        move.w  #-1,BB_STEP(a5)
.bm_row:
        move.l  BB_SPLANE(a5),a2
        move.l  a2,d0
        beq.s   .bm_dst
        cmp.l   #-1,d0
        beq.s   .bm_dst
        moveq   #0,d0
        move.w  bm_BytesPerRow(a4),d0
        mulu    BB_CSY(a5),d0
        add.l   d0,a2                ; a2 = ligne source
        move.l  BB_BUF(a5),d0
        beq.s   .bm_dst
        move.l  d0,a0                ; même BitMap : ligne recopiée dans le tampon d'abord
        move.l  a2,a1
        move.w  bm_BytesPerRow(a4),d0
        subq.w  #1,d0
.bm_cp:
        move.b  (a1)+,(a0)+
        dbra    d0,.bm_cp
        move.l  BB_BUF(a5),a2
.bm_dst:
        move.w  BB_PLANE(a5),d0
        lsl.w   #2,d0
        move.l  bm_Planes(a3,d0.w),a1
        moveq   #0,d0
        move.w  bm_BytesPerRow(a3),d0
        mulu    BB_CDY(a5),d0
        add.l   d0,a1                ; a1 = ligne destination
        move.w  BB_SX(a5),d0
        move.w  BB_DX(a5),d2
        move.w  BB_W(a5),d4
        bsr     dr_bits
        move.w  BB_STEP(a5),d0
        add.w   d0,BB_CSY(a5)
        add.w   d0,BB_CDY(a5)
        subq.w  #1,BB_N(a5)
        bne.s   .bm_row
.bm_pnext:
        addq.w  #1,BB_PLANE(a5)
        bra     .bm_plane
.bm_free:
        move.l  BB_BUF(a5),d0
        beq.s   .bm_ret
        subq.l  #1,d0
        move.l  d0,a1
        moveq   #0,d0
        move.w  bm_BytesPerRow(a4),d0
        addq.l  #4,d0
        move.l  ($4).w,a6
        jsr     LVO_FREEMEM(a6)
.bm_ret:
        moveq   #0,d0
        move.w  BB_COUNT(a5),d0
        lea     BB_SIZE(sp),sp
        movem.l (sp)+,d2-d7/a2-a6
        rts

; ReadPixel(rp a1, x d0, y d1) -> d0 = n° de couleur du pixel (relatif à la couche), -1 s'il n'est dans aucune
; ClipRect lisible (hors zone, ou caché sans sauvegarde).
gfx_ReadPixel:
        movem.l d2-d4/a5,-(sp)
        lea     -DC_SIZE(sp),sp
        move.l  sp,a5
        movem.w d0-d1,-(sp)
        bsr     dr_ctx
        movem.w (sp)+,d0-d1
        add.w   DC_OX(a5),d0
        add.w   DC_OY(a5),d1
        move.w  d0,d2
        move.w  d1,d3
        move.l  DC_FIRST(a5),a0
.rp_lp:
        cmpa.w  #0,a0
        beq.s   .rp_none
        bsr     dr_crset
        beq.s   .rp_n
        cmp.w   DC_CMINX(a5),d2
        blt.s   .rp_n
        cmp.w   DC_CMAXX(a5),d2
        bgt.s   .rp_n
        cmp.w   DC_CMINY(a5),d3
        blt.s   .rp_n
        cmp.w   DC_CMAXY(a5),d3
        ble.s   .rp_read
.rp_n:
        move.l  CR_NEXT(a0),a0
        bra.s   .rp_lp
.rp_none:
        moveq   #-1,d0
        bra.s   .rp_out
.rp_read:
        move.l  DC_CBM(a5),a0
        sub.w   DC_BX(a5),d2
        sub.w   DC_BY(a5),d3
        moveq   #0,d1
        move.w  bm_BytesPerRow(a0),d1
        mulu    d3,d1
        move.w  d2,d4
        lsr.w   #3,d4
        add.l   d4,d1                ; d1 = décalage de l'octet
        not.w   d2
        and.w   #7,d2                ; d2 = n° du bit (7 = pixel de gauche)
        moveq   #0,d0
        moveq   #0,d3
        move.b  bm_Depth(a0),d3
        subq.w  #1,d3                ; du plan le plus haut au plan 0
.rp_pl:
        add.w   d0,d0
        move.w  d3,d4
        lsl.w   #2,d4
        move.l  bm_Planes(a0,d4.w),a1
        btst    d2,0(a1,d1.l)
        beq.s   .rp_z
        addq.w  #1,d0
.rp_z:
        dbra    d3,.rp_pl
        move.l  DC_RP(a5),a1
.rp_out:
        bsr     dr_end
        lea     DC_SIZE(sp),sp
        movem.l (sp)+,d2-d4/a5
        rts

; gfx_putrow(rp a1, couleurs a0, x d0, y d1, nombre d2) : pose une ligne de pixels (un octet de couleur par pixel,
; 255 = transparent) à (x, y) relatifs au RastPort, par plages de même couleur, à travers ses ClipRects, en JAM2
; quel que soit rp_DrawMode (rp_Mask respecté). Sert au dessin des GELs. Préserve d2-d7/a1-a6.
gfx_putrow:
        movem.l d2-d7/a2-a5,-(sp)
        lea     -DC_SIZE(sp),sp
        move.l  sp,a5
        move.l  a0,a2                ; a2 = couleurs
        movem.w d0-d1,-(sp)
        bsr     dr_ctx
        movem.w (sp)+,d4-d5
        add.w   DC_OX(a5),d4         ; d4 = x absolu du premier pixel
        add.w   DC_OY(a5),d5         ; d5 = y absolu
        move.b  rp_DrawMode(a1),d6
        move.b  #JAM2,rp_DrawMode(a1)
        move.w  d2,d7                ; d7 = nombre
        moveq   #0,d0                ; d0 = index courant
.pr_lp:
        cmp.w   d7,d0
        bge.s   .pr_end
        move.b  0(a2,d0.w),d3
        cmp.b   #$FF,d3
        bne.s   .pr_run
        addq.w  #1,d0
        bra.s   .pr_lp
.pr_run:
        move.w  d0,d2
.pr_ext:
        addq.w  #1,d2
        cmp.w   d7,d2
        bge.s   .pr_emit
        cmp.b   0(a2,d2.w),d3
        beq.s   .pr_ext
.pr_emit:                            ; plage [d0 .. d2-1]
        move.w  d2,-(sp)
        subq.w  #1,d2
        add.w   d4,d0
        add.w   d4,d2
        move.w  d5,d1
        bsr     dr_span
        move.w  (sp)+,d0
        bra.s   .pr_lp
.pr_end:
        move.b  d6,rp_DrawMode(a1)
        bsr     dr_end
        lea     DC_SIZE(sp),sp
        movem.l (sp)+,d2-d7/a2-a5
        rts

; LockLayerRom(layer a5) / UnlockLayerRom(layer a5) : sémaphore de la couche. Préservent tous les registres, comme
; l'exige l'AutoDoc.
gfx_LockLayerRom:
        cmpa.w  #0,a5                ; RastPort sans couche : rien à verrouiller
        beq.s   .lock_r
        movem.l d0-d1/a0-a1/a6,-(sp)
        lea     LY_LOCK(a5),a0
        move.l  ($4).w,a6
        jsr     LVO_OBTAINSEMAPHORE(a6)
        movem.l (sp)+,d0-d1/a0-a1/a6
.lock_r:
        rts
gfx_UnlockLayerRom:
        cmpa.w  #0,a5                ; RastPort sans couche : rien à verrouiller
        beq.s   .unlo_r
        movem.l d0-d1/a0-a1/a6,-(sp)
        lea     LY_LOCK(a5),a0
        move.l  ($4).w,a6
        jsr     LVO_RELEASESEMAPHORE(a6)
        movem.l (sp)+,d0-d1/a0-a1/a6
.unlo_r:
        rts
