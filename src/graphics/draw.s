; src/graphics/draw.s — primitives de dessin de graphics.library dans un RastPort (BitMap planaire, rendu CPU).
; SetAPen/SetBPen/SetDrMd/Move/Draw/WritePixel/RectFill/SetRast/ScrollRaster/Text/TextLength/SetFont/
; InitRastPort/InitBitMap/ReadPixel/BltBitMap. Si rp_Layer est posé, ses bornes donnent le décalage (coordonnées
; relatives à la couche) et le dessin passe par ses ClipRects (layers.library) : ClipRect visible -> BitMap du
; RastPort ; ClipRect cachée avec sauvegarde (cr_BitMap, origine dans cr_p1) -> la sauvegarde ; cachée sans
; sauvegarde -> rien. Le verrou de la couche est tenu pendant le dessin (dr_ctx ... dr_end). Sans couche : une seule
; pseudo-ClipRect = le BitMap entier. Police unique : font8x8 de la ROM
; (8x8, ligne de base 6), dessinée en JAM1/JAM2/COMPLEMENT/INVERSVID. ScrollRaster : défilement vertical seul.
; Accès mémoire OCTET par octet (une ligne de BitMap peut commencer à une adresse impaire).
; Au-delà de la convention (d2-d7/a2-a6), toutes ces fonctions laissent a1 (le RastPort) intact : intuition et
; console.device enchaînent leurs appels sur le même RastPort sans le recharger.
; Piste IMPLÉMENTATION (« clean ») : AutoDocs graphics.library + includes NDK publics. AUCUNE lecture ROM.

                include "exec.i"
                include "graphics.i"

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
                xref    font8x8
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
gfx_TextLength:                      ; TextLength(rp a1, chaîne a0, nombre d0) -> largeur en pixels
        ext.l   d0
        lsl.l   #3,d0
        rts
gfx_SetFont:                         ; SetFont(rp a1, police a0) : police unique 8x8 (métriques fixes)
        move.l  a0,rp_Font(a1)
        move.w  #GFX_FONTH,rp_TxHeight(a1)
        move.w  #GFX_FONTW,rp_TxWidth(a1)
        move.w  #GFX_FONTBASE,rp_TxBaseline(a1)
        moveq   #0,d0
        rts

; InitRastPort(rp a1) : RastPort à zéro, Mask/FgPen/AOlPen/LinePtrn = -1, DrawMode = JAM2, police 8x8.
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
        move.w  #GFX_FONTH,rp_TxHeight(a1)
        move.w  #GFX_FONTW,rp_TxWidth(a1)
        move.w  #GFX_FONTBASE,rp_TxBaseline(a1)
        rts

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

; dr_cellcr(d4, d5 = coin d'une cellule de police, absolu) : cherche une ClipRect utilisable qui contient toute la
; cellule et en fait la ClipRect courante. Z = 0 si trouvée. Préserve tout sauf d0.
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
        addq.w  #GFX_FONTW-1,d0
        cmp.w   DC_CMAXX(a5),d0
        bgt.s   .cc_n
        move.w  d5,d0
        addq.w  #GFX_FONTH-1,d0
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

; Text(rp a1, chaîne a0, nombre d0) : caractères de la police 8x8 à (cp_x, cp_y - ligne de base), cp_x avance de 8
; par caractère. JAM1 : seuls les pixels du glyphe (stylo A) ; JAM2 : fond au stylo B ; COMPLEMENT : glyphe inversé ;
; INVERSVID : glyphe et fond permutés. Caractère hors 0x20..0x7F -> '?'. Rendu par plages de pixels identiques.
gfx_Text:
        movem.l d2-d7/a2-a5,-(sp)
        lea     -DC_SIZE(sp),sp
        move.l  sp,a5
        move.l  a0,a4                ; a4 = chaîne
        move.w  d0,d7                ; d7 = nombre restant
        bsr     dr_ctx
.tx_char:
        subq.w  #1,d7
        bmi     .tx_ret
        moveq   #0,d0
        move.b  (a4)+,d0
        cmp.b   #$20,d0
        blo.s   .tx_bad
        cmp.b   #$7F,d0
        bls.s   .tx_ok
.tx_bad:
        moveq   #'?',d0
.tx_ok:
        sub.w   #$20,d0
        lsl.w   #3,d0
        move.l  #font8x8,a3
        add.w   d0,a3                ; a3 = glyphe (8 octets)
        move.w  rp_cp_x(a1),d4
        add.w   DC_OX(a5),d4         ; d4 = x absolu
        move.w  rp_cp_y(a1),d5
        sub.w   #GFX_FONTBASE,d5
        add.w   DC_OY(a5),d5         ; d5 = y absolu de la première ligne
        move.b  rp_DrawMode(a1),d0   ; voie rapide : JAM2 (± INVERSVID), x multiple de 8, cellule non découpée
        and.b   #~INVERSVID,d0
        cmp.b   #JAM2,d0
        bne.s   .tx_slow
        move.w  d4,d0
        and.w   #7,d0
        bne.s   .tx_slow
        bsr     dr_cellcr            ; cellule entière dans une seule ClipRect utilisable ?
        beq.s   .tx_slow
        bsr     .tx_fast
        bra.s   .tx_adv
.tx_slow:
        moveq   #GFX_FONTH-1,d6
.tx_row:
        move.b  (a3)+,d2             ; d2.b = ligne du glyphe (bit 7 = pixel gauche)
        btst    #2,rp_DrawMode(a1)   ; INVERSVID
        beq.s   .tx_nv
        not.b   d2
.tx_nv:
        bsr     .tx_runs
        addq.w  #1,d5
        dbra    d6,.tx_row
.tx_adv:
        addq.w  #GFX_FONTW,rp_cp_x(a1)
        bra     .tx_char
.tx_ret:
        bsr     dr_end
        lea     DC_SIZE(sp),sp
        movem.l (sp)+,d2-d7/a2-a5
        rts
; .tx_fast : glyphe a3 à (d4, d5) aligné sur un octet, dans la ClipRect courante, mode JAM2 : chaque plan autorisé par
; rp_Mask reçoit directement ses 8 octets (bit à 1 -> bit du stylo A, bit à 0 -> bit du stylo B). Préserve d4-d7.
.tx_fast:
        movem.l d4-d7,-(sp)
        move.l  DC_CBM(a5),a2
        sub.w   DC_BX(a5),d4         ; coordonnées dans le BitMap de la ClipRect
        sub.w   DC_BY(a5),d5
        moveq   #0,d6
        move.w  bm_BytesPerRow(a2),d6 ; d6 = pas d'une ligne
        move.w  d5,d0
        mulu    d6,d0
        moveq   #0,d1
        move.w  d4,d1
        lsr.w   #3,d1
        add.l   d1,d0                ; d0 = décalage de l'octet de la première ligne
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
        add.l   d0,a0
        moveq   #0,d4                ; d4 = ligne du glyphe
.tf_row:
        move.b  0(a3,d4.w),d5
        btst    #2,rp_DrawMode(a1)   ; INVERSVID
        beq.s   .tf_ni
        not.b   d5
.tf_ni:
        btst    #0,d1
        beq.s   .tf_nofg
        btst    #0,d2
        beq.s   .tf_put              ; stylo A seul : le glyphe
        moveq   #-1,d5               ; A et B : plein
        bra.s   .tf_put
.tf_nofg:
        btst    #0,d2
        beq.s   .tf_zero
        not.b   d5                   ; stylo B seul : le fond
        bra.s   .tf_put
.tf_zero:
        moveq   #0,d5
.tf_put:
        move.b  d5,(a0)
        add.l   d6,a0
        addq.w  #1,d4
        cmp.w   #GFX_FONTH,d4
        blo.s   .tf_row
.tf_next:
        lsr.b   #1,d1                ; bits des stylos et du masque pour le plan suivant
        lsr.b   #1,d2
        lsr.b   #1,d7
        dbra    d3,.tf_plane
        movem.l (sp)+,d4-d7
        rts
; .tx_runs : ligne d2.b à (d4, d5) : découpe en plages de bits égaux ; bit 1 -> stylo A (ou inversion en
; COMPLEMENT) ; bit 0 -> stylo B en JAM2 seulement. Préserve d4-d7.
.tx_runs:
        movem.l d4-d7,-(sp)
        moveq   #0,d6                ; d6 = index du pixel courant (0..7)
.tr_run:
        cmp.w   #8,d6
        bge.s   .tr_ret
        move.w  d6,d7                ; d7 = début de la plage
        moveq   #7,d0
        sub.w   d6,d0
        btst    d0,d2
        sne     d3                   ; d3.b = valeur de la plage ($FF / 0)
.tr_ext:
        addq.w  #1,d6
        cmp.w   #8,d6
        bge.s   .tr_emit
        moveq   #7,d0
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
        tst.w   d1
        bmi.s   .sc_down
        move.w  d3,d6                ; vers le haut : ligne y <- y+dy, y croissant
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
        move.w  d5,d6                ; vers le bas : y <- y+dy (dy < 0), y décroissant
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
        subq.w  #2,d1                ; octets pleins - 1
        bmi.s   .cp_last
.cp_mid:
        move.b  (a0)+,(a1)+
        dbra    d1,.cp_mid
.cp_last:
        move.b  d3,d0                ; dernier octet
        bsr.s   .cp_mask
.cp_pdone:
        addq.w  #1,d4
        bra.s   .cp_plane
.cp_r:
        movem.l (sp)+,d4-d7/a1-a3
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

; LockLayerRom(layer a5) / UnlockLayerRom(layer a5) : sémaphore de la couche. Préservent tous les registres, comme
; l'exige l'AutoDoc.
gfx_LockLayerRom:
        movem.l d0-d1/a0-a1/a6,-(sp)
        lea     LY_LOCK(a5),a0
        move.l  ($4).w,a6
        jsr     LVO_OBTAINSEMAPHORE(a6)
        movem.l (sp)+,d0-d1/a0-a1/a6
        rts
gfx_UnlockLayerRom:
        movem.l d0-d1/a0-a1/a6,-(sp)
        lea     LY_LOCK(a5),a0
        move.l  ($4).w,a6
        jsr     LVO_RELEASESEMAPHORE(a6)
        movem.l (sp)+,d0-d1/a0-a1/a6
        rts
