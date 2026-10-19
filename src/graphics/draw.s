; src/graphics/draw.s — primitives de dessin de graphics.library dans un RastPort (BitMap planaire, rendu CPU).
; SetAPen/SetBPen/SetDrMd/Move/Draw/WritePixel/RectFill/SetRast/ScrollRaster/Text/TextLength/SetFont/
; InitRastPort/InitBitMap. Sans layers.library : si rp_Layer est posé, ses bornes (struct Rectangle à lr_MinX)
; servent de décalage (coordonnées relatives à la fenêtre) ET de rectangle de découpage ; sinon coordonnées absolues
; découpées au BitMap. Pas de recouvrement de fenêtres géré (une seule couche). Police unique : font8x8 de la ROM
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
                xref    font8x8

; --- contexte de dessin (sur la pile, pointé par a5) ---
DC_OX           EQU 0                ; décalage X (bornes du Layer) ; WORD
DC_OY           EQU 2
DC_MINX         EQU 4                ; rectangle de découpage absolu (inclusif)
DC_MINY         EQU 6
DC_MAXX         EQU 8
DC_MAXY         EQU 10
DC_BM           EQU 12               ; BitMap
DC_RP           EQU 16               ; RastPort
DC_SIZE         EQU 20

; dr_ctx(a1 = RastPort, a5 = contexte) : remplit le contexte. Clobbe d0/d1/a0.
dr_ctx:
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
; [x0..x1] de la ligne y avec le stylo (rp_DrawMode COMPLEMENT : inverse), découpés au contexte, plans filtrés par
; rp_Mask. Préserve tout.
dr_span:
        movem.l d0-d7/a0-a3,-(sp)
        cmp.w   DC_MINY(a5),d1
        blt     .sp_ret
        cmp.w   DC_MAXY(a5),d1
        bgt     .sp_ret
        cmp.w   DC_MINX(a5),d0
        bge.s   .sp_c0
        move.w  DC_MINX(a5),d0
.sp_c0:
        cmp.w   DC_MAXX(a5),d2
        ble.s   .sp_c1
        move.w  DC_MAXX(a5),d2
.sp_c1:
        cmp.w   d2,d0
        bgt     .sp_ret
        move.l  DC_BM(a5),a3
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
        lea     DC_SIZE(sp),sp
        movem.l (sp)+,d2-d7/a2-a5
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
        cmp.w   DC_MINX(a5),d4
        blt.s   .tx_slow
        cmp.w   DC_MINY(a5),d5
        blt.s   .tx_slow
        move.w  d4,d0
        addq.w  #GFX_FONTW-1,d0
        cmp.w   DC_MAXX(a5),d0
        bgt.s   .tx_slow
        move.w  d5,d0
        addq.w  #GFX_FONTH-1,d0
        cmp.w   DC_MAXY(a5),d0
        bgt.s   .tx_slow
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
        lea     DC_SIZE(sp),sp
        movem.l (sp)+,d2-d7/a2-a5
        rts
; .tx_fast : glyphe a3 à (d4, d5) aligné sur un octet, entièrement visible, mode JAM2 : chaque plan autorisé par
; rp_Mask reçoit directement ses 8 octets (bit à 1 -> bit du stylo A, bit à 0 -> bit du stylo B). Préserve d4-d7.
.tx_fast:
        movem.l d4-d7,-(sp)
        move.l  DC_BM(a5),a2
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
; suffisant pour console.device). Coordonnées relatives au Layer ; copie octet par octet avec masques de bord.
gfx_ScrollRaster:
        movem.l d2-d7/a2-a5,-(sp)
        lea     -DC_SIZE(sp),sp
        move.l  sp,a5
        movem.w d1-d5,-(sp)          ; (sp) dy, xmin, ymin, xmax, ymax
        bsr     dr_ctx
        movem.w (sp)+,d1-d5
        add.w   DC_OX(a5),d2
        add.w   DC_OX(a5),d4
        add.w   DC_OY(a5),d3
        add.w   DC_OY(a5),d5
        cmp.w   DC_MINX(a5),d2       ; découpage
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
        move.w  d2,a2                ; a2 = xmin, a3 = xmax
        move.w  d4,a3
        move.w  d1,d7                ; d7 = dy
        bmi.s   .sc_down
        move.w  d3,d6                ; vers le haut : ligne y <- y+dy, y croissant
.sc_up:
        move.w  d6,d0
        add.w   d7,d0
        cmp.w   d5,d0
        bgt.s   .sc_fillu
        move.w  d6,d1
        bsr.s   .sc_copy             ; d0 = source, d1 = destination
        addq.w  #1,d6
        bra.s   .sc_up
.sc_fillu:                           ; lignes [d6 .. ymax] au stylo B
        move.w  d5,d4
        bra.s   .sc_fill
.sc_down:
        neg.w   d7
        move.w  d5,d6                ; vers le bas : y <- y-dy, y décroissant
.sc_dn:
        move.w  d6,d0
        sub.w   d7,d0
        cmp.w   d3,d0
        blt.s   .sc_filld
        move.w  d6,d1
        bsr.s   .sc_copy
        subq.w  #1,d6
        bra.s   .sc_dn
.sc_filld:                           ; lignes [ymin .. d6]
        move.w  d6,d4
        move.w  d3,d6
.sc_fill:
        move.b  rp_DrawMode(a1),-(sp)
        clr.b   rp_DrawMode(a1)
        move.b  rp_BgPen(a1),d3
.sc_flp:
        cmp.w   d4,d6
        bgt.s   .sc_fdone
        move.w  a2,d0
        move.w  d6,d1
        move.w  a3,d2
        bsr     dr_span
        addq.w  #1,d6
        bra.s   .sc_flp
.sc_fdone:
        move.b  (sp)+,rp_DrawMode(a1)
.sc_ret:
        lea     DC_SIZE(sp),sp
        movem.l (sp)+,d2-d7/a2-a5
        rts
; .sc_copy(d0.w = ligne source, d1.w = ligne destination, a2/a3 = xmin/xmax) : copie les pixels [xmin..xmax] dans
; chaque plan (octets de bord masqués : dst = (dst & ~m) | (src & m)). Préserve d2-d7/a2-a3.
.sc_copy:
        movem.l d2-d7/a2-a4,-(sp)
        move.l  DC_BM(a5),a4
        moveq   #0,d4
        move.w  bm_BytesPerRow(a4),d4
        moveq   #0,d5
        move.w  d4,d5
        mulu    d0,d4                ; d4 = décalage source
        mulu    d1,d5                ; d5 = décalage destination
        move.w  a2,d6
        lsr.w   #3,d6                ; d6 = premier octet
        move.w  a3,d7
        lsr.w   #3,d7                ; d7 = dernier octet
        move.w  a2,d0                ; d2.b = masque gauche, d3.b = masque droit
        and.w   #7,d0
        moveq   #-1,d2
        lsr.b   d0,d2
        move.w  a3,d0
        and.w   #7,d0
        moveq   #7,d1
        sub.w   d0,d1
        moveq   #-1,d3
        lsl.b   d1,d3
        cmp.w   d6,d7
        bne.s   .cp_m
        and.b   d3,d2                ; octet unique : masques combinés
.cp_m:
        moveq   #0,d0
        move.b  bm_Depth(a4),d0
        subq.w  #1,d0
        lea     bm_Planes(a4),a4
.cp_plane:
        move.w  d0,-(sp)             ; compteur de plans
        move.l  (a4)+,a2
        move.l  a2,a3
        add.l   d4,a2                ; a2 = source
        add.l   d5,a3                ; a3 = destination
        add.w   d6,a2
        add.w   d6,a3
        move.b  d2,d0                ; premier octet (masque gauche, ou combiné si octet unique)
        bsr.s   .cp_mask
        cmp.w   d6,d7
        beq.s   .cp_pdone
        move.w  d7,d1
        sub.w   d6,d1
        subq.w  #2,d1                ; octets pleins - 1
        bmi.s   .cp_last
.cp_mid:
        move.b  (a2)+,(a3)+
        dbra    d1,.cp_mid
.cp_last:
        move.b  d3,d0                ; dernier octet (masque droit)
        bsr.s   .cp_mask
.cp_pdone:
        move.w  (sp)+,d0
        dbra    d0,.cp_plane
        movem.l (sp)+,d2-d7/a2-a4
        rts
; .cp_mask(d0.b = masque) : dst = (dst & ~m) | (src & m) pour l'octet courant ; avance a2/a3. Clobbe d0/d1.
.cp_mask:
        move.b  (a2)+,d1
        and.b   d0,d1
        not.b   d0
        and.b   d0,(a3)
        or.b    d1,(a3)+
        rts
