; src/graphics/text.s — graphics.library fonts: topaz 8 (the ROM font, hand-authored glyphs from
; font8x8 in strike format), gb_TextFonts list, OpenFont/CloseFont/AskFont/AddFont/RemFont, software styles
; (AskSoftStyle/SetSoftStyle) and AllocRaster/FreeRaster. Rendering (Text/TextLength) lives in draw.s.
; IMPLEMENTATION track ("clean"): public graphics.library AutoDocs + graphics/text.h. NO ROM reading.

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

TOPAZ8_NCHARS   EQU $7F-$20+2        ; LoChar..HiChar plus the default glyph
SOFTSTYLES      EQU FSF_UNDERLINED|FSF_BOLD   ; styles that Text can produce

; topaz 8 in ROM: template of the TextFont linked into gb_TextFonts (RAM copy) and fallback font for a RastPort
; with no font.
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

; gfx_fontinit(a2 = GfxBase, a6 = SysBase): empty font list, then topaz 8 (RAM copy of the template) at the head and
; as default font. Without memory, the ROM template serves as the default font outside the list. Preserves a2/a6.
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

; OpenFont(textAttr a0) -> d0 = font with the same name (case ignored) whose height is closest to ta_YSize
; (exact preferred), its access count incremented; 0 if no font has that name.
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
        suba.l  a1,a1                ; best font
        move.l  #$10000,d3           ; best difference
        move.l  gb_TextFonts(a6),a2
.of_lp:
        tst.l   (a2)                 ; ln_Succ = 0: end of list
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

; tx_namecmp(a0, a4 = C strings): Z = 1 if equal, ASCII case ignored. Clobbers d0/d1/a0.
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
        movem.l (sp)+,a1             ; movem does not touch the condition codes
        rts

; CloseFont(textFont a1): one access fewer (never negative).
gfx_CloseFont:
        move.l  a1,d0
        beq.s   .cf_r
        tst.w   tf_Accessors(a1)
        beq.s   .cf_r
        subq.w  #1,tf_Accessors(a1)
.cf_r:
        rts

; AskFont(rp a1, textAttr a0): name, height, style and flags of the RastPort's font.
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

; AddFont(textFont a1): the font is added at the head of gb_TextFonts.
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

; RemFont(textFont a1): removes the font from the list (only once).
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

; AskSoftStyle(rp a1) -> d0 = styles SetSoftStyle can add (those the font does not already have).
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

; SetSoftStyle(rp a1, style d0, enable d1) -> d0 = resulting style (font + algorithmic). Only the bits of enable
; that AskSoftStyle allows are changed.
gfx_SetSoftStyle:
        move.l  d2,-(sp)
        move.l  d0,d2
        bsr.s   gfx_AskSoftStyle
        and.b   d0,d1                ; d1 = modifiable bits
        and.b   d1,d2
        not.b   d1
        and.b   rp_AlgoStyle(a1),d1
        or.b    d2,d1
        move.b  d1,rp_AlgoStyle(a1)
        moveq   #0,d0
        move.b  tf_Style(a0),d0      ; a0 = font (left by AskSoftStyle)
        or.b    d1,d0
        move.l  (sp)+,d2
        rts

; AllocRaster(width d0, height d1) -> d0 = plane in chip memory (width rounded to a word), 0 if exhausted.
gfx_AllocRaster:
        bsr.s   tx_rassize
        move.l  #MEMF_CHIP,d1
        move.l  a6,-(sp)
        move.l  ($4).w,a6
        jsr     LVO_ALLOCMEM(a6)
        move.l  (sp)+,a6
        rts
; FreeRaster(plane a0, width d0, height d1): returns a plane from AllocRaster.
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
; tx_rassize(width d0, height d1) -> d0 = height * bytes per row (width rounded to a word). Clobbers d1.
tx_rassize:
        add.w   #15,d0
        lsr.w   #4,d0
        add.w   d0,d0
        mulu    d1,d0
        rts
