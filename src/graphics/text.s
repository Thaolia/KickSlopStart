; src/graphics/text.s — graphics.library fonts: topaz 8 and topaz 9 (the ROM fonts, hand-authored glyphs from
; tests/mk_font8x8.py in strike format), gb_TextFonts list, OpenFont/CloseFont/AskFont/AddFont/RemFont, software
; styles (AskSoftStyle/SetSoftStyle) and AllocRaster/FreeRaster. Rendering (Text/TextLength) lives in draw.s.
; IMPLEMENTATION track ("clean"): docs/analysis/graphics-text-v34.md + public AutoDocs + graphics/text.h.

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
                xref    gfx_waitidle
                xdef    gfx_FreeRaster
                xref    topaz8_strike
                xref    topaz8_loc
                xref    TOPAZ8_MOD
                xref    topaz9_strike
                xref    topaz9_loc
                xref    TOPAZ9_MOD

; The two ROM fonts (spec graphics-text-v34 §2): templates of the TextFonts linked into gb_TextFonts (RAM copies);
; topaz 8 is also the fallback font of a RastPort with no font. Codes $20..$FF plus the default glyph.
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
        dc.b    $20,$FF              ; tf_LoChar, tf_HiChar
        dc.l    topaz8_strike
        dc.w    TOPAZ8_MOD
        dc.l    topaz8_loc
        dc.l    0,0                  ; tf_CharSpace, tf_CharKern
topaz9_font:
        dc.l    0,0
        dc.b    NT_FONT,0
        dc.l    topaz_name
        dc.l    0
        dc.w    tf_SIZEOF
        dc.w    9
        dc.b    FSF_EXTENDED,FPF_ROMFONT|FPF_TALLDOT|FPF_DESIGNED
        dc.w    10,6,1,0
        dc.b    $20,$FF
        dc.l    topaz9_strike
        dc.w    TOPAZ9_MOD
        dc.l    topaz9_loc
        dc.l    0,0
topaz_name:
        dc.b    "topaz.font",0
        EVEN

; gfx_fontinit(a2 = GfxBase, a6 = SysBase): font list holding RAM copies of topaz 9 then topaz 8; topaz 8 is the
; default font until intuition applies the Preferences. Without memory, the ROM topaz 8 template serves as the
; default font outside the list. Preserves a2/a6.
gfx_fontinit:
        lea     gb_TextFonts(a2),a0
        lea     LH_TAIL(a0),a1
        move.l  a1,(a0)
        clr.l   LH_TAIL(a0)
        move.l  a0,8(a0)             ; lh_TailPred
        move.b  #NT_FONT,12(a0)      ; lh_Type
        moveq   #tf_SIZEOF*2,d0
        move.l  #MEMF_PUBLIC,d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        bne.s   .fi_copy
        lea     topaz8_font(pc),a0
        move.l  a0,gb_DefaultFont(a2)
        rts
.fi_copy:
        move.l  d0,a1                ; topaz 9 at d0, topaz 8 right after
        lea     topaz9_font(pc),a0
        moveq   #tf_SIZEOF/2-1,d1
.fi_cp9:
        move.w  (a0)+,(a1)+
        dbra    d1,.fi_cp9
        lea     topaz8_font(pc),a0
        moveq   #tf_SIZEOF/2-1,d1
.fi_cp8:
        move.w  (a0)+,(a1)+
        dbra    d1,.fi_cp8
        move.l  d0,-(sp)
        move.l  d0,a1
        lea     gb_TextFonts(a2),a0
        jsr     LVO_ADDTAIL(a6)
        move.l  (sp)+,a1
        lea     tf_SIZEOF(a1),a1
        move.l  a1,gb_DefaultFont(a2)
        lea     gb_TextFonts(a2),a0
        jmp     LVO_ADDTAIL(a6)

; OpenFont(textAttr a0) -> d0 = the best-scoring font of exactly that name (case counts), its tf_Accessors + 1;
; 0 if none scores above 0 (spec §3). Score: 32767, minus 256 per line too high or 64 per line too low, minus the
; weight of each style/flag bit that differs (of_wreq when the request has it, of_wfont when only the font has it).
; Ties go to the first font of the list.
gfx_OpenFont:
        movem.l d2-d7/a2-a4/a6,-(sp)
        move.l  a0,a3                ; a3 = TextAttr
        move.l  a6,a4                ; a4 = GfxBase
        move.l  ($4).w,a6
        jsr     LVO_FORBID(a6)
        moveq   #0,d6                ; d6 = best font
        moveq   #0,d7                ; d7 = best score (a font needs more)
        move.l  gb_TextFonts(a4),a2
.of_lp:
        tst.l   (a2)                 ; ln_Succ = 0: end of list
        beq.s   .of_end
        move.l  LN_NAME(a2),d0
        beq.s   .of_nx
        move.l  d0,a0
        move.l  ta_Name(a3),a1
.of_cmp:
        cmpm.b  (a0)+,(a1)+
        bne.s   .of_nx
        tst.b   -1(a0)
        bne.s   .of_cmp
        move.w  tf_YSize(a2),d0
        beq.s   .of_nx
        move.l  #$7FFF,d5            ; d5 = score
        sub.w   ta_YSize(a3),d0
        ext.l   d0
        bmi.s   .of_small
        lsl.l   #8,d0
        bra.s   .of_size
.of_small:
        neg.l   d0
        lsl.l   #6,d0
.of_size:
        sub.l   d0,d5
        move.w  tf_Style(a2),d2      ; tf_Style:tf_Flags
        move.w  ta_Style(a3),d3      ; ta_Style:ta_Flags
        move.w  d2,d4
        eor.w   d3,d4                ; d4 = bits that differ
        moveq   #0,d1                ; d1 = bit
        lea     of_wreq(pc),a0
        lea     of_wfont(pc),a1
.of_bit:
        btst    d1,d4
        beq.s   .of_bnx
        moveq   #0,d0
        btst    d1,d3
        beq.s   .of_bfont
        move.w  (a0),d0
        bra.s   .of_bsub
.of_bfont:
        move.w  (a1),d0
.of_bsub:
        sub.l   d0,d5
.of_bnx:
        addq.l  #2,a0
        addq.l  #2,a1
        addq.w  #1,d1
        cmp.w   #16,d1
        blo.s   .of_bit
        cmp.l   d7,d5
        ble.s   .of_nx
        move.l  d5,d7
        move.l  a2,d6
.of_nx:
        move.l  (a2),a2
        bra.s   .of_lp
.of_end:
        tst.l   d6
        beq.s   .of_perm
        move.l  d6,a0
        addq.w  #1,tf_Accessors(a0)
.of_perm:
        jsr     LVO_PERMIT(a6)
        move.l  d6,d0
        movem.l (sp)+,d2-d7/a2-a4/a6
        rts
; Weights by bit of (Style:Flags): bits 0-7 = tf_Flags (ROMFONT, DISKFONT, REVPATH, TALLDOT, WIDEDOT, PROPORTIONAL,
; DESIGNED, REMOVED), bits 8-15 = tf_Style (UNDERLINED, BOLD, ITALIC, EXTENDED, 4 unused).
of_wreq:
        dc.w    1,1,32768,32,32,32,2,0, 4,8,16,0,0,0,0,0
of_wfont:
        dc.w    1,1,32768,32,32,128,2,0, 128,128,128,0,0,0,0,0

; CloseFont(textFont a1): one access fewer (the count may go negative); a removed font with no access left is
; replied to its owner (spec §4).
gfx_CloseFont:
        move.l  a1,d0
        beq.s   .cf_r
        subq.w  #1,tf_Accessors(a1)
        bne.s   .cf_r                ; only the close that brings it to 0 replies (graphics-text §10.5: -1, -2 nothing)
        btst    #FPB_REMOVED,tf_Flags(a1)
        beq.s   .cf_r
        move.l  a6,-(sp)
        move.l  ($4).w,a6
        jsr     LVO_REPLYMSG(a6)
        move.l  (sp)+,a6
.cf_r:
        rts

; AskFont(rp a1, textAttr a0): name pointer, height, style and flags of the RastPort's font.
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

; AddFont(textFont a1): no access, type NT_FONT, Enqueue by priority into gb_TextFonts (after the fonts of the same
; priority). FPF_REMOVED is left as it is.
gfx_AddFont:
        move.l  a6,-(sp)
        clr.w   tf_Accessors(a1)
        move.b  #NT_FONT,LN_TYPE(a1)
        lea     gb_TextFonts(a6),a0
        move.l  ($4).w,a6
        jsr     LVO_FORBID(a6)
        jsr     LVO_ENQUEUE(a6)
        jsr     LVO_PERMIT(a6)
        move.l  (sp)+,a6
        rts

; RemFont(textFont a1): off the list, type NT_MESSAGE, FPF_REMOVED; replied at once if nobody uses it, otherwise by
; the last CloseFont.
gfx_RemFont:
        move.l  a6,-(sp)
        move.l  ($4).w,a6
        move.l  a1,-(sp)
        jsr     LVO_FORBID(a6)
        jsr     LVO_REMOVE(a6)
        jsr     LVO_PERMIT(a6)
        move.l  (sp)+,a1
        move.b  #NT_MESSAGE,LN_TYPE(a1)
        bset    #FPB_REMOVED,tf_Flags(a1)
        tst.w   tf_Accessors(a1)
        bgt.s   .rf_r
        jsr     LVO_REPLYMSG(a6)
.rf_r:
        move.l  (sp)+,a6
        rts

; AskSoftStyle(rp a1) -> d0 = NOT tf_Style (32 bits): the styles Text can add; underline only if the font has a row
; below the baseline for it (Baseline + 2 <= YSize). Leaves a0 = font.
gfx_AskSoftStyle:
        move.l  rp_Font(a1),d0
        bne.s   .as_have
        lea     topaz8_font(pc),a0
        move.l  a0,d0
.as_have:
        move.l  d0,a0
        move.l  d1,-(sp)
        move.w  tf_Baseline(a0),d1
        addq.w  #2,d1
        moveq   #0,d0
        move.b  tf_Style(a0),d0
        not.l   d0
        cmp.w   tf_YSize(a0),d1
        ble.s   .as_r
        bclr    #0,d0
.as_r:
        move.l  (sp)+,d1
        rts

; SetSoftStyle(rp a1, style d0, enable d1) -> d0 = AlgoStyle | tf_Style. Only the bits of enable that AskSoftStyle
; allows are changed (the value SetPatch 1.38 returns; the 1.3 ROM returns a byte read through the caller's a2).
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
        jsr     gfx_waitidle        ; Draw may still be writing the plane returned to the allocator
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
