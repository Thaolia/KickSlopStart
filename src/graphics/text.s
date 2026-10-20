; src/graphics/text.s — polices de graphics.library : topaz 8 (police de la ROM, glyphes hand-authored de
; font8x8 au format strike), liste gb_TextFonts, OpenFont/CloseFont/AskFont/AddFont/RemFont, styles logiciels
; (AskSoftStyle/SetSoftStyle) et AllocRaster/FreeRaster. Le rendu (Text/TextLength) est dans draw.s.
; Piste IMPLÉMENTATION (« clean ») : AutoDocs graphics.library + graphics/text.h publics. AUCUNE lecture ROM.

                include "exec.i"
                include "graphics.i"

                xdef    topaz8_font
                xdef    gfx_fontinit
                xdef    gfx_OpenFont
                xdef    gfx_CloseFont
                xdef    gfx_AskFont
                xdef    gfx_AddFont
                xdef    gfx_RemFont
                xdef    gfx_AskSoftStyle
                xdef    gfx_SetSoftStyle
                xdef    gfx_AllocRaster
                xdef    gfx_FreeRaster
                xref    topaz8_strike
                xref    TOPAZ8_MOD

TOPAZ8_NCHARS   EQU $7F-$20+2        ; LoChar..HiChar plus le glyphe par défaut
SOFTSTYLES      EQU FSF_UNDERLINED|FSF_BOLD   ; styles que Text sait produire

; topaz 8 en ROM : modèle de la TextFont chaînée dans gb_TextFonts (copie RAM) et police de secours d'un RastPort
; sans police.
                EVEN
topaz8_font:
        dc.l    0,0                  ; ln_Succ, ln_Pred
        dc.b    NT_FONT,0
        dc.l    topaz_name
        dc.l    0                    ; mn_ReplyPort
        dc.w    tf_SIZEOF            ; mn_Length
        dc.w    8                    ; tf_YSize
        dc.b    0,FPF_ROMFONT|FPF_DESIGNED
        dc.w    8,6,1,0              ; tf_XSize, tf_Baseline, tf_BoldSmear, tf_Accessors
        dc.b    $20,$7F              ; tf_LoChar, tf_HiChar
        dc.l    topaz8_strike
        dc.w    TOPAZ8_MOD
        dc.l    topaz8_loc
        dc.l    0,0                  ; tf_CharSpace, tf_CharKern
topaz8_loc:
tz_n            SET 0
                REPT TOPAZ8_NCHARS
        dc.w    tz_n*8,8
tz_n            SET tz_n+1
                ENDR
topaz_name:
        dc.b    "topaz.font",0
        EVEN

; gfx_fontinit(a2 = GfxBase, a6 = SysBase) : liste des polices vide, puis topaz 8 (copie RAM du modèle) en tête et
; police par défaut. Sans mémoire, le modèle ROM sert de police par défaut hors liste. Préserve a2/a6.
gfx_fontinit:
        lea     gb_TextFonts(a2),a0
        lea     LH_TAIL(a0),a1
        move.l  a1,(a0)
        clr.l   LH_TAIL(a0)
        move.l  a0,8(a0)             ; lh_TailPred
        move.b  #NT_FONT,12(a0)      ; lh_Type
        moveq   #tf_SIZEOF,d0
        move.l  #MEMF_PUBLIC,d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        bne.s   .fi_copy
        lea     topaz8_font(pc),a0
        move.l  a0,gb_DefaultFont(a2)
        rts
.fi_copy:
        move.l  d0,a1
        lea     topaz8_font(pc),a0
        moveq   #tf_SIZEOF/2-1,d1
.fi_cp:
        move.w  (a0)+,(a1)+
        dbra    d1,.fi_cp
        move.l  d0,a1
        move.l  d0,gb_DefaultFont(a2)
        lea     gb_TextFonts(a2),a0
        jmp     LVO_ADDHEAD(a6)

; OpenFont(textAttr a0) -> d0 = police de même nom (casse ignorée) dont la hauteur est la plus proche de ta_YSize
; (exacte de préférence), son compte d'accès incrémenté ; 0 si aucune police de ce nom.
gfx_OpenFont:
        movem.l d2-d4/a2-a4/a6,-(sp)
        move.l  a0,a3
        move.l  ta_Name(a3),d0
        beq.s   .of_none
        move.l  d0,a4
        move.l  a6,-(sp)
        move.l  ($4).w,a6
        jsr     LVO_FORBID(a6)
        move.l  (sp)+,a6
        suba.l  a1,a1                ; meilleure police
        move.l  #$10000,d3           ; meilleur écart
        move.l  gb_TextFonts(a6),a2
.of_lp:
        tst.l   (a2)                 ; ln_Succ = 0 : fin de liste
        beq.s   .of_end
        move.l  LN_NAME(a2),d0
        beq.s   .of_nx
        move.l  d0,a0
        bsr.s   tx_namecmp
        bne.s   .of_nx
        moveq   #0,d0
        move.w  tf_YSize(a2),d0
        sub.w   ta_YSize(a3),d0
        bpl.s   .of_abs
        neg.w   d0
.of_abs:
        cmp.l   d3,d0
        bhs.s   .of_nx
        move.l  d0,d3
        move.l  a2,a1
        tst.l   d3
        beq.s   .of_end
.of_nx:
        move.l  (a2),a2
        bra.s   .of_lp
.of_end:
        move.l  a1,d2
        beq.s   .of_perm
        addq.w  #1,tf_Accessors(a1)
.of_perm:
        move.l  ($4).w,a6
        jsr     LVO_PERMIT(a6)
        move.l  d2,d0
        bra.s   .of_ret
.of_none:
        moveq   #0,d0
.of_ret:
        movem.l (sp)+,d2-d4/a2-a4/a6
        rts

; tx_namecmp(a0, a4 = chaînes C) : Z = 1 si égales, casse ASCII ignorée. Clobbe d0/d1/a0.
tx_namecmp:
        move.l  a1,-(sp)
        move.l  a4,a1
.nc_lp:
        move.b  (a0)+,d0
        move.b  (a1)+,d1
        cmp.b   #'A',d0
        blo.s   .nc_1
        cmp.b   #'Z',d0
        bhi.s   .nc_1
        add.b   #$20,d0
.nc_1:
        cmp.b   #'A',d1
        blo.s   .nc_2
        cmp.b   #'Z',d1
        bhi.s   .nc_2
        add.b   #$20,d1
.nc_2:
        cmp.b   d0,d1
        bne.s   .nc_r
        tst.b   d0
        bne.s   .nc_lp
.nc_r:
        movem.l (sp)+,a1             ; movem ne touche pas aux codes conditions
        rts

; CloseFont(textFont a1) : un accès de moins (jamais négatif).
gfx_CloseFont:
        move.l  a1,d0
        beq.s   .cf_r
        tst.w   tf_Accessors(a1)
        beq.s   .cf_r
        subq.w  #1,tf_Accessors(a1)
.cf_r:
        rts

; AskFont(rp a1, textAttr a0) : nom, hauteur, style et drapeaux de la police du RastPort.
gfx_AskFont:
        move.l  a2,-(sp)
        move.l  rp_Font(a1),a2
        cmpa.w  #0,a2
        bne.s   .af_have
        lea     topaz8_font(pc),a2
.af_have:
        move.l  LN_NAME(a2),ta_Name(a0)
        move.w  tf_YSize(a2),ta_YSize(a0)
        move.b  tf_Style(a2),ta_Style(a0)
        move.b  tf_Flags(a2),ta_Flags(a0)
        move.l  (sp)+,a2
        rts

; AddFont(textFont a1) : la police entre en tête de gb_TextFonts.
gfx_AddFont:
        move.l  a6,-(sp)
        move.l  a6,a0
        move.l  ($4).w,a6
        jsr     LVO_FORBID(a6)
        move.b  #NT_FONT,LN_TYPE(a1)
        bclr    #FPB_REMOVED,tf_Flags(a1)
        lea     gb_TextFonts(a0),a0
        jsr     LVO_ADDHEAD(a6)
        jsr     LVO_PERMIT(a6)
        move.l  (sp)+,a6
        rts

; RemFont(textFont a1) : retire la police de la liste (une seule fois).
gfx_RemFont:
        move.l  a6,-(sp)
        move.l  ($4).w,a6
        jsr     LVO_FORBID(a6)
        bset    #FPB_REMOVED,tf_Flags(a1)
        bne.s   .rf_p
        jsr     LVO_REMOVE(a6)
.rf_p:
        jsr     LVO_PERMIT(a6)
        move.l  (sp)+,a6
        rts

; AskSoftStyle(rp a1) -> d0 = styles que SetSoftStyle peut ajouter (ceux que la police n'a pas déjà).
gfx_AskSoftStyle:
        move.l  rp_Font(a1),d0
        bne.s   .as_have
        lea     topaz8_font(pc),a0
        move.l  a0,d0
.as_have:
        move.l  d0,a0
        moveq   #0,d0
        move.b  tf_Style(a0),d0
        not.b   d0
        and.b   #SOFTSTYLES,d0
        rts

; SetSoftStyle(rp a1, style d0, enable d1) -> d0 = style résultant (police + algorithmique). Seuls les bits de enable
; que AskSoftStyle autorise changent.
gfx_SetSoftStyle:
        move.l  d2,-(sp)
        move.l  d0,d2
        bsr.s   gfx_AskSoftStyle
        and.b   d0,d1                ; d1 = bits modifiables
        and.b   d1,d2
        not.b   d1
        and.b   rp_AlgoStyle(a1),d1
        or.b    d2,d1
        move.b  d1,rp_AlgoStyle(a1)
        moveq   #0,d0
        move.b  tf_Style(a0),d0      ; a0 = police (laissée par AskSoftStyle)
        or.b    d1,d0
        move.l  (sp)+,d2
        rts

; AllocRaster(largeur d0, hauteur d1) -> d0 = plan en mémoire chip (largeur arrondie au mot), 0 si épuisée.
gfx_AllocRaster:
        bsr.s   tx_rassize
        move.l  #MEMF_CHIP,d1
        move.l  a6,-(sp)
        move.l  ($4).w,a6
        jsr     LVO_ALLOCMEM(a6)
        move.l  (sp)+,a6
        rts
; FreeRaster(plan a0, largeur d0, hauteur d1) : rend un plan d'AllocRaster.
gfx_FreeRaster:
        move.l  a0,a1
        cmpa.w  #0,a1
        beq.s   .fr_r
        bsr.s   tx_rassize
        move.l  a6,-(sp)
        move.l  ($4).w,a6
        jsr     LVO_FREEMEM(a6)
        move.l  (sp)+,a6
.fr_r:
        rts
; tx_rassize(largeur d0, hauteur d1) -> d0 = hauteur * octets par ligne (largeur arrondie au mot). Clobbe d1.
tx_rassize:
        add.w   #15,d0
        lsr.w   #4,d0
        add.w   d0,d0
        mulu    d1,d0
        rts
