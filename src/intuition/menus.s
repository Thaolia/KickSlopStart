; src/intuition/menus.s - intuition menus: SetMenuStrip/ClearMenuStrip, ItemAddress, OnMenu/OffMenu, PrintIText,
; IntuiTextLength, and the right-button interaction (intuition input task).
; Right button pressed over the active window that has a menu strip (and no RMBTRAP): the screen's title bar is
; covered by a smart layer carrying the menu titles; the pointer in the bar pulls down the targeted menu
; (a smart layer under the bar, ITEMTEXT or image items); the item under the pointer is
; highlighted (inversion) if it is enabled. On release: MENUPICK to the window with the selection code (MENUNULL
; otherwise), layers deleted; layers gives the area back to the windows (backup of smart windows, REFRESHWINDOW for
; simple windows via it_refresh). Disabled items or menus are ghosted by the 1.3 dot pattern in
; BlockPen.
; COMMSEQ shortcuts (spec intuition-input-menus-v34 §3.5): the Command character to the right of the item, preceded by
; the Amiga key symbol - here a small cat drawn for KickSlopStart (not the ROM glyph), in the same format.
; Keyboard shortcuts (§3.11): right Amiga + key converted to a character; the handler searches the menu strip of the
; active window (menus, items, sub-items; Command & $5F, COMMSEQ not tested), swallows the key, and the input
; task sends MENUPICK (MENUNULL if the menu, the item or the sub-item is disabled).
; Check marks (§3.5): a CHECKIT and CHECKED item receives the Window->CheckMark image at (x of the item, y of the item +
; TopEdge of its ItemFill); internal check mark = cat paw print (own design), same format as the cat.
; Sub-menus (§3.5, §3.7): pointer on an item with sub-items -> sub-item box (simple layer on top,
; the item box is a smart layer that restores itself when it closes), placed over the item according to the extent of
; its sub-items; a hit sub-item is highlighted (the parent item lit again); outside the sub-items,
; the box stays; a title removes it. MENUPICK code with the sub-item number; item with sub-items without a
; chosen sub-item -> MENUNULL.
; Selection (§3.8): each chosen code is appended to the NextSelect chain of the menu session (head in IB_PICK, sent
; with MENUPICK); MENUTOGGLED stops a CHECKIT item toggling twice before the next click; MutualExclude unchecks the
; CHECKIT siblings named by its bits; a changed check mark redraws the box. Left button held during a menu:
; drag-selection of each item passed over (§3.9). Highlighting (§3.6): HIGHCOMP, HIGHBOX (complemented frame around
; the item), HIGHIMAGE (SelectFill / ItemFill), HIGHNONE; HIGHITEM follows the state.
; IMPLEMENTATION track ("clean"): AutoDocs intuition.library + intuition/intuition.h. NO ROM reading.

                include "exec.i"
                include "intuition.i"
                include "graphics.i"

                xdef    intuition_SetMenuStrip
                xdef    mn_actclr
                xdef    it_rpsave
                xdef    it_rprest
                xdef    intuition_ClearMenuStrip
                xdef    intuition_ItemAddress
                xdef    intuition_OnMenu
                xdef    intuition_OffMenu
                xdef    intuition_PrintIText
                xref    gfx_minterms
                xdef    intuition_IntuiTextLength
                xdef    it_menubutton
                xdef    it_menumove
                xdef    mn_boxfree
                xref    mn_cache_lookup,mn_cache_store,mn_cache_dispose,mn_cache_clear
                xdef    mn_lbutton
                xdef    mn_keyshort
                xdef    mn_keypick
                xdef    mn_defcheck
                xref    it_refresh
                xref    it_box
                xref    it_scrxy
                xref    wn_sendgad
                xref    it_alive
                xref    wn_sendkey
                xref    it_verify
                xref    it_dmreq
                xref    it_dmrnear
                xref    kbd_cook
                xref    intuition_DrawImage

MB_MARGIN       EQU 2                ; inner margin of the pulled-down menu (border included)
MI_COMMAND      EQU 26               ; MenuItem: shortcut character (COMMSEQ)
MI_MUTUALEXCLUDE EQU 14              ; MenuItem: siblings unchecked when it is chosen (bit n = n-th of its list)
HIGHCOMP        EQU $0040
HIGHBOX         EQU $0080
MIDRAWN         EQU $0100            ; Menu flag
ISDRAWN         EQU $1000            ; MenuItem working flags
HIGHITEM        EQU $2000
MENUTOGGLED     EQU $4000
COMMSEQ         EQU $0004

; SetMenuStrip(window a0, menu a1, a6 = IntuitionBase) -> d0 = TRUE. Each menu gets JazzX/JazzY/BeatX/BeatY
; (intuition-input-menus §3.2, §3.5): the union of its items' rectangles and of the extents of their ItemFill and
; SelectFill, widened by the active screen's MenuHBorder/MenuVBorder, left at most 0, right at least Width - 1. A
; menu without items keeps its values. 1.3 raises a dead-end Alert for a box above the items' origin; not here.
; ClearMenuStrip(window a0).
intuition_SetMenuStrip:
        movem.l d2-d7/a2-a4,-(sp)
        move.l  a1,WD_MENUSTRIP(a0)
        move.l  IB_ACTIVESCREEN(a6),d0
        bne.s   .sm_scr
        move.l  WD_WSCREEN(a0),d0
.sm_scr:
        move.l  d0,a4                ; a4 = screen of the borders
        move.l  a1,a2
.sm_menu:
        move.l  a2,d0
        beq.s   .sm_ret
        bsr     mn_measuremenu
        move.l  MU_NEXTMENU(a2),a2
        bra.s   .sm_menu
.sm_ret:
        movem.l (sp)+,d2-d7/a2-a4
        moveq   #1,d0
        rts

; Measure current item contents with the screen font. Applications may fill strings after SetMenuStrip;
; the first draw in each menu session refreshes the public box cache before MIDRAWN is set.
mn_measuremenu:
        movem.l d2-d7/a2-a4,-(sp)
        move.l  MU_FIRSTITEM(a2),d0
        beq     .sm_done
        move.l  d0,a3
        move.w  #$7FFF,d4            ; d4..d7 = left, top, right, bottom
        move.w  d4,d5
        move.w  #$8000,d6
        move.w  d6,d7
.sm_item:
        move.w  MI_LEFTEDGE(a3),d0
        move.w  MI_TOPEDGE(a3),d1
        move.w  d0,d2
        add.w   MI_WIDTH(a3),d2
        subq.w  #1,d2
        move.w  d1,d3
        add.w   MI_HEIGHT(a3),d3
        subq.w  #1,d3
        bsr.s   .sm_union
        move.l  MI_ITEMFILL(a3),d0
        bsr.s   .sm_fill
        move.l  MI_SELECTFILL(a3),d0
        bsr.s   .sm_fill
        move.l  MI_NEXTITEM(a3),d0
        move.l  d0,a3
        bne.s   .sm_item
        moveq   #0,d0
        move.b  SC_MENUHBORDER(a4),d0
        sub.w   d0,d4
        add.w   d0,d6
        move.b  SC_MENUVBORDER(a4),d0
        sub.w   d0,d5
        add.w   d0,d7
        tst.w   d4
        ble.s   .sm_left
        moveq   #0,d4
.sm_left:
        move.w  MU_WIDTH(a2),d0
        subq.w  #1,d0
        cmp.w   d0,d6
        bge.s   .sm_right
        move.w  d0,d6
.sm_right:
        movem.w d4-d7,MU_JAZZX(a2)
.sm_done:
        movem.l (sp)+,d2-d7/a2-a4
        rts
.sm_union:                           ; d0..d3 = rectangle into d4..d7
        cmp.w   d4,d0
        bge.s   .su_1
        move.w  d0,d4
.su_1:
        cmp.w   d5,d1
        bge.s   .su_2
        move.w  d1,d5
.su_2:
        cmp.w   d6,d2
        ble.s   .su_3
        move.w  d2,d6
.su_3:
        cmp.w   d7,d3
        ble.s   .su_4
        move.w  d3,d7
.su_4:
        rts
.sm_fill:                            ; d0 = ItemFill | SelectFill of item a3: its extent, offset by the item
        tst.l   d0
        beq     .sf_ret
        move.l  d0,a0
        btst    #1,MI_FLAGS+1(a3)    ; ITEMTEXT
        bne.s   .sf_text
        move.w  MI_LEFTEDGE(a3),d0
        add.w   IG_LEFTEDGE(a0),d0
        move.w  MI_TOPEDGE(a3),d1
        add.w   IG_TOPEDGE(a0),d1
        move.w  d0,d2
        add.w   IG_WIDTH(a0),d2
        move.w  d1,d3
        add.w   IG_HEIGHT(a0),d3
        bra.s   .sf_go
.sf_text:                            ; Missing ITextFont inherits the menu's screen font, not the global default.
        tst.l   IT_ITEXTFONT(a0)
        bne.s   .sf_explicit
        movem.l a0/a6,-(sp)
        lea     -rp_SIZEOF(sp),sp
        move.l  IB_GFXBASE(a6),a6
        move.l  sp,a1
        jsr     LVO_INITRASTPORT(a6)
        move.l  SC_RASTPORT+rp_Font(a4),a0
        jsr     LVO_SETFONT(a6)
        move.l  rp_SIZEOF(sp),a0
        move.l  IT_ITEXT(a0),a0
        bsr     mn_strlen
        jsr     LVO_TEXTLENGTH(a6)
        lea     rp_SIZEOF(sp),sp
        movem.l (sp)+,a0/a6
        bra.s   .sf_length
.sf_explicit:
        move.l  a0,-(sp)
        bsr     intuition_IntuiTextLength
        move.l  (sp)+,a0
.sf_length:
        move.w  d0,d2
        move.w  MI_LEFTEDGE(a3),d0
        add.w   IT_LEFTEDGE(a0),d0
        add.w   d0,d2
        move.w  MI_TOPEDGE(a3),d1
        add.w   IT_TOPEDGE(a0),d1
        move.l  IT_ITEXTFONT(a0),d3  ; height of its font, the default one without
        bne.s   .sf_ta
        move.l  SC_RASTPORT+rp_Font(a4),a1
        move.w  tf_YSize(a1),d3
        bra.s   .sf_h
.sf_ta:
        move.l  d3,a1
        move.w  ta_YSize(a1),d3
.sf_h:
        add.w   MI_TOPEDGE(a3),d3
.sf_go:
        subq.w  #1,d2
        subq.w  #1,d3
        bra     .sm_union
.sf_ret:
        rts
intuition_ClearMenuStrip:
        clr.l   WD_MENUSTRIP(a0)
        rts

; ItemAddress(menustrip a0, code d0) -> d0 = designated MenuItem (or sub-item), 0 for MENUNULL or outside the list.
intuition_ItemAddress:
        bsr.s   mn_find
        move.l  a0,d0
        rts

; mn_find(a0 = first menu, d0.w = code) -> a0 = item | 0, a1 = menu | 0, d1.w = item number ($3F: none).
; Clobbers d0.
mn_find:
        move.l  d2,-(sp)
        move.w  d0,d2
        cmp.w   #MENUNULL,d2
        beq.s   .fd_none
        and.w   #$1F,d0              ; menu number
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
        and.w   #$3F,d1              ; item number
        cmp.w   #$3F,d1
        beq.s   .fd_menuonly
        move.l  MU_FIRSTITEM(a1),a0
        move.w  d1,d0
        bsr.s   .fd_walk
        beq.s   .fd_out
        move.w  d2,d0
        lsr.w   #8,d0
        lsr.w   #3,d0                ; sub-item number
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
.fd_walk:                            ; a0 = d0-th of the chain (MI_NEXTITEM) | 0; Z = 1 if absent
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

; OffMenu(window a0, code d0) / OnMenu(window a0, code d0): disables / enables the designated item (sub-item
; included), or the whole menu if the item number is NOITEM.
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

; it_rpsave(a2 = rp, a0 = 20-byte buffer): the RastPort state DrawBorder and PrintIText restore (intuition-render
; §1): font fields (Font, AlgoStyle, TxFlags, TxHeight, TxWidth, TxBaseline), pens, DrawMode, Mask, Layer.
it_rpsave:
        move.l  rp_Font(a2),(a0)
        move.l  rp_Font+4(a2),4(a0)
        move.l  rp_Font+8(a2),8(a0)
        move.b  rp_FgPen(a2),12(a0)
        move.b  rp_BgPen(a2),13(a0)
        move.b  rp_DrawMode(a2),14(a0)
        move.b  rp_Mask(a2),15(a0)
        move.l  rp_Layer(a2),16(a0)
        rts
; it_rprest(a2 = rp, a0 = buffer of it_rpsave, a6 = GfxBase): font fields written back, pens and mode through
; SetAPen/SetBPen/SetDrMd (so FRST_DOT is set and the line pattern restarts, as on 1.3), then Mask and Layer.
; Clobbers d0/d1/a0/a1.
it_rprest:
        move.l  a0,-(sp)
        move.l  (a0),rp_Font(a2)
        move.l  4(a0),rp_Font+4(a2)
        move.l  8(a0),rp_Font+8(a2)
        move.l  a2,a1
        moveq   #0,d0
        move.b  12(a0),d0
        jsr     LVO_SETAPEN(a6)
        move.l  (sp),a0
        move.l  a2,a1
        moveq   #0,d0
        move.b  13(a0),d0
        jsr     LVO_SETBPEN(a6)
        move.l  (sp),a0
        move.l  a2,a1
        moveq   #0,d0
        move.b  14(a0),d0
        jsr     LVO_SETDRMD(a6)
        move.l  (sp)+,a0
        move.b  15(a0),rp_Mask(a2)
        move.l  16(a0),rp_Layer(a2)
        rts

; PrintIText(rp a0, itext a1, x d0, y d1) (intuition-render §5): each IntuiText of the chain with its pens and mode,
; its ITextFont when it opens (SetFont + SetSoftStyle of its style), from (x + LeftEdge, y + TopEdge + TxBaseline),
; Mask $FF; the RastPort state is restored after each font change and at the end; cp is left after the text.
intuition_PrintIText:
        movem.l d2-d3/a2-a4/a6,-(sp)
        lea     -20(sp),sp
        move.l  a0,a2
        move.l  a1,a3
        move.w  d0,d2
        move.w  d1,d3
        move.l  IB_GFXBASE(a6),a6
        move.l  sp,a0
        bsr     it_rpsave
        st      rp_Mask(a2)
.pt_lp:
        move.l  a3,d0
        beq     .pt_ret
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
        sub.l   a4,a4                ; a4 = font opened for this IntuiText | 0
        move.l  IT_ITEXTFONT(a3),d0
        beq.s   .pt_move
        move.l  d0,a0
        jsr     LVO_OPENFONT(a6)
        tst.l   d0
        beq.s   .pt_move
        move.l  d0,a4
        move.l  d0,a0
        move.l  a2,a1
        jsr     LVO_SETFONT(a6)
        move.l  IT_ITEXTFONT(a3),a0
        moveq   #0,d0
        move.b  ta_Style(a0),d0
        move.l  #$FF,d1
        move.l  a2,a1
        jsr     LVO_SETSOFTSTYLE(a6)
.pt_move:
        move.l  a2,a1
        move.w  d2,d0
        add.w   IT_LEFTEDGE(a3),d0
        move.w  d3,d1
        add.w   IT_TOPEDGE(a3),d1
        add.w   rp_TxBaseline(a2),d1
        jsr     LVO_MOVE(a6)
        move.l  IT_ITEXT(a3),d0
        beq.s   .pt_font
        move.l  d0,a0
        bsr     mn_strlen
        move.l  a2,a1
        jsr     LVO_TEXT(a6)
.pt_font:
        move.l  a4,d0
        beq.s   .pt_next
        move.l  a4,a1
        jsr     LVO_CLOSEFONT(a6)
        move.l  sp,a0
        bsr     it_rprest
        st      rp_Mask(a2)
.pt_next:
        move.l  IT_NEXTTEXT(a3),a3
        bra     .pt_lp
.pt_ret:
        move.l  sp,a0
        bsr     it_rprest
        lea     20(sp),sp
        movem.l (sp)+,d2-d3/a2-a4/a6
        rts

; IntuiTextLength(itext a0, a6 = IntuitionBase) -> d0 = width in pixels of its text in its own font: ITextFont opened
; from graphics.library, or GfxBase's default font when it has none or it cannot be opened (TextLength in a RastPort
; on the stack). Preserves d2-d7/a2-a6.
intuition_IntuiTextLength:
        movem.l d2/a2-a3/a6,-(sp)
        lea     -rp_SIZEOF(sp),sp
        move.l  a0,a2                ; a2 = IntuiText
        move.l  IB_GFXBASE(a6),a6
        move.l  sp,a1
        jsr     LVO_INITRASTPORT(a6)
        sub.l   a3,a3                ; a3 = font opened here | 0
        move.l  IT_ITEXTFONT(a2),d0
        beq.s   .tl_len
        move.l  d0,a0
        jsr     LVO_OPENFONT(a6)
        move.l  d0,a3
        tst.l   d0
        beq.s   .tl_len
        move.l  d0,a0
        move.l  sp,a1
        jsr     LVO_SETFONT(a6)
.tl_len:
        move.l  IT_ITEXT(a2),a0
        bsr.s   mn_strlen
        move.l  sp,a1
        jsr     LVO_TEXTLENGTH(a6)
        move.l  d0,d2
        move.l  a3,d0
        beq.s   .tl_ret
        move.l  a3,a1
        jsr     LVO_CLOSEFONT(a6)
.tl_ret:
        moveq   #0,d0
        move.w  d2,d0
        lea     rp_SIZEOF(sp),sp
        movem.l (sp)+,d2/a2-a3/a6
        rts

; mn_strlen(a0 = C string) -> d0 = length. Preserves a0.
mn_strlen:
        move.l  a0,-(sp)
        moveq   #-1,d0
.sl_lp:
        addq.l  #1,d0
        tst.b   (a0)+
        bne.s   .sl_lp
        move.l  (sp)+,a0
        rts

; it_menubutton(a4 = front screen, a5 = IntuitionBase, d7.w = code, d4/d5 = pointer in the screen): input task
; context. Pressed: displays the menu bar of the active window; released: end of the selection.
it_menubutton:
        cmp.w   #IECODE_RBUTTON,d7
        bne     mn_end
        tst.l   IB_MENUWIN(a5)
        bne     .mb_ret
        move.l  IB_ACTIVEWINDOW(a5),d0
        beq     .mb_ret
        move.l  d0,a3
        cmp.l   WD_WSCREEN(a3),a4
        bne     .mb_ret
        btst    #0,WD_FLAGS+1(a3)    ; RMBTRAP: the right button belongs to the application (a window without menus
                                     ; gets the empty bar and the verifies: intuition-input-menus §5 step F)
        bne     .mb_ret
        move.l  WD_FIRSTREQUEST(a3),d0   ; requester without NOISYREQ: no menus (spec intuition-requesters-v34 §3.2)
        beq.s   .mb_menus
        move.l  d0,a0
        btst    #2,RQ_FLAGS+1(a0)    ; NOISYREQ
        beq     .mb_ret
.mb_menus:
        move.l  #MENUVERIFY,d0       ; MENUHOT: the application may cancel (intuition-input-menus §3.3, §3.10)
        moveq   #MENUHOT,d1
        jsr     it_verify
        cmp.l   #MENUCANCEL,d0
        beq     mn_mcancel
        cmp.l   #4,d0
        beq     .mb_ret
        cmp.l   IB_ACTIVEWINDOW(a5),a3
        bne     .mb_ret
        jsr     it_dmreq             ; right double click: the DMRequest instead
        cmp.l   #1,d0
        beq     .mb_ret
        tst.l   d0
        bne.s   .mb_bar              ; DMRequest first press: the bar only, for now
        bsr     mn_waiting
        cmp.l   IB_ACTIVEWINDOW(a5),a3
        bne     .mb_ret
.mb_bar:
        move.l  WD_MENUSTRIP(a3),a0  ; working flags of the whole bar reset, chain empty (§3.8)
        move.w  #MENUTOGGLED|HIGHITEM|ISDRAWN,d0
        move.w  #MENUTOGGLED|HIGHITEM,d1
        move.w  #MIDRAWN,d2
        bsr     mn_clrflags
        move.w  #MENUNULL,IB_PICK(a5)
        clr.b   IB_MNDRAG(a5)
        clr.l   IB_MENUBOX(a5)
        clr.l   IB_MENUCUR(a5)
        clr.l   IB_ITEMCUR(a5)
        clr.l   IB_ITEMHIT(a5)
        clr.l   IB_SUBBOX(a5)
        clr.l   IB_SUBITEM(a5)
        clr.l   IB_SUBCUR(a5)
        clr.l   IB_MENUSAVE(a5)
        clr.l   IB_SUBSAVE(a5)
        lea     SC_LAYERINFO(a4),a0
        lea     SC_BITMAP(a4),a1
        moveq   #0,d0
        moveq   #0,d1
        move.w  SC_WIDTH(a4),d2
        subq.w  #1,d2
        moveq   #0,d3                ; lines 0..BarHeight-1
        move.b  SC_BARHEIGHT(a4),d3
        subq.w  #1,d3
        moveq   #IL_SMART,d4
        suba.l  a2,a2
        move.l  IB_LAYERSBASE(a5),a6
        jsr     LVO_CREATEUPFRONTLAYER(a6)
        move.l  d0,IB_MENUBAR(a5)
        beq     .mb_ret
        jsr     it_alive             ; the layer creation may wait: the window may have been closed meanwhile
        bne.s   .mb_on
        move.l  d0,a1
        clr.l   IB_MENUBAR(a5)
        suba.l  a0,a0
        jsr     LVO_DELETELAYER(a6)
        jmp     it_refresh
.mb_on:
        move.l  a3,IB_MENUWIN(a5)
        bsr     mn_drawbar
        st      IB_TRACK(a5)
        tst.w   IB_DMRSTATE(a5)
        bne.s   .mb_ret              ; DMRequest: no tracking while the second click may come
        move.w  PTR_X,d4
        move.w  PTR_Y,d5
        bra     it_menumove
.mb_ret:
        rts

; mn_rmbar(a5): closes the boxes and removes the bar layer, then repairs.
mn_rmbar:
        bsr     mn_closebox
        bsr     mn_cache_clear
        clr.l   IB_MENUCUR(a5)
        clr.b   IB_TRACK(a5)
        move.l  IB_MENUBAR(a5),a1
        clr.l   IB_MENUBAR(a5)
        suba.l  a0,a0
        move.l  IB_LAYERSBASE(a5),a6
        jsr     LVO_DELETELAYER(a6)
        bra     it_refresh

; mn_mcancel(a3, a5): MENUCANCEL: no menu; the release comes to the window as MOUSEBUTTONS MENUUP (it_rbutton).
mn_mcancel:
        move.l  a3,IB_RMBWIN(a5)
        rts

; mn_waiting(a3 = active window, a4 = its screen, a5): MENUWAITING to each other window of the screen that has
; MENUVERIFY, one by one, each waiting for its reply (ignored). Preserves d2-d7/a2-a5.
mn_waiting:
        move.l  a3,-(sp)
        move.l  SC_FIRSTWINDOW(a4),d0
.mw_lp:
        beq.s   .mw_ret
        move.l  d0,a3
        cmp.l   (sp),a3
        beq.s   .mw_nx
        move.l  #MENUVERIFY,d0
        moveq   #MENUWAITING,d1
        jsr     it_verify
.mw_nx:
        move.l  WD_NEXTWINDOW(a3),d0
        bra.s   .mw_lp
.mw_ret:
        move.l  (sp)+,a3
        rts

; mn_menuup(a3 = menu window, a5): at the close of a menu, MOUSEBUTTONS MENUUP to every window of its screen that has
; MENUVERIFY (the menu window included; wn_sendgad checks MOUSEBUTTONS). Preserves d2-d7/a2-a5.
mn_menuup:
        movem.l d2-d3/d6/a3-a4,-(sp)
        move.l  WD_WSCREEN(a3),a4
        move.l  SC_FIRSTWINDOW(a4),d0
.mu_lp:
        beq.s   .mu_ret
        move.l  d0,a3
        btst    #5,WD_IDCMPFLAGS+2(a3) ; MENUVERIFY ($2000)
        beq.s   .mu_nx
        move.w  WD_MOUSEX(a3),d2
        move.w  WD_MOUSEY(a3),d3
        move.l  #MOUSEBUTTONS,d0
        move.w  #MENUUP,d1
        suba.l  a0,a0                ; IAddress = the event's raw ie_X/ie_Y, 0 for a click (§2.3)
        jsr     wn_sendgad
.mu_nx:
        move.l  WD_NEXTWINDOW(a3),d0
        bra.s   .mu_lp
.mu_ret:
        movem.l (sp)+,d2-d3/d6/a3-a4
        rts

; mn_drawbar(a3 = window, a4 = screen, a5): window BlockPen/DetailPen, screen font and bar borders.
; Menu names are complete strings: the nominal font width does not bound proportional-font text.
mn_drawbar:
        movem.l d2-d7/a2,-(sp)
        move.l  IB_MENUBAR(a5),a2
        move.l  IL_RP(a2),a2         ; a2 = RastPort of the bar
        move.l  IB_GFXBASE(a5),a6
        move.l  a2,a1
        bsr     mn_screenfont
        move.l  a2,a1
        bsr     mn_windowpens
        move.l  d1,d0
        jsr     LVO_SETAPEN(a6)
        move.l  a2,a1
        moveq   #0,d0
        moveq   #0,d1
        move.w  SC_WIDTH(a4),d2
        subq.w  #1,d2
        moveq   #0,d3
        move.b  SC_BARHEIGHT(a4),d3
        subq.w  #1,d3
        jsr     LVO_RECTFILL(a6)
        move.l  WD_MENUSTRIP(a3),d7
.db_lp:
        tst.l   d7
        beq.s   .db_ret
        bsr     mn_windowpens
        move.l  a2,a1
        jsr     LVO_SETAPEN(a6)
        move.l  d1,d0
        jsr     LVO_SETBPEN(a6)
        moveq   #JAM2,d0
        jsr     LVO_SETDRMD(a6)
        move.l  d7,a0
        moveq   #0,d0
        move.b  SC_BARHBORDER(a4),d0
        add.w   MU_LEFTEDGE(a0),d0
        moveq   #0,d1
        move.b  SC_BARVBORDER(a4),d1
        add.w   rp_TxBaseline(a2),d1
        jsr     LVO_MOVE(a6)
        move.l  d7,a0
        move.l  MU_MENUNAME(a0),d0
        beq.s   .db_flags
        move.l  d0,a0
        bsr     mn_strlen
        jsr     LVO_TEXT(a6)
.db_flags:
        move.l  d7,a0
        btst    #0,MU_FLAGS+1(a0)    ; MENUENABLED
        bne.s   .db_nx
        move.w  MU_LEFTEDGE(a0),d0
        moveq   #0,d1
        move.b  SC_BARHBORDER(a4),d1
        add.w   d1,d0
        moveq   #0,d1
        move.w  d0,d2
        add.w   MU_WIDTH(a0),d2
        subq.w  #1,d2
        moveq   #0,d3
        move.b  SC_BARHEIGHT(a4),d3
        subq.w  #1,d3
        move.l  a2,a1
        bsr     mn_ghost
.db_nx:
        move.l  d7,a0
        move.l  MU_NEXTMENU(a0),d7
        bra.s   .db_lp
.db_ret:
        movem.l (sp)+,d2-d7/a2
        rts

; mn_windowpens(a4 = screen, a5): d0 = DetailPen, d1 = BlockPen of the menu's window.
; A screen without a menu window uses its own pens. Clobbers a0.
mn_windowpens:
        moveq   #0,d0
        moveq   #0,d1
        move.l  IB_MENUWIN(a5),a0
        cmpa.w  #0,a0
        beq.s   .wp_screen
        move.b  WD_DETAILPEN(a0),d0
        move.b  WD_BLOCKPEN(a0),d1
        rts
.wp_screen:
        move.b  SC_DETAILPEN(a4),d0
        move.b  SC_BLOCKPEN(a4),d1
        rts

; Fresh menu layers otherwise retain the graphics global default instead of this screen's font and style.
mn_screenfont:
        move.l  a1,-(sp)
        move.l  SC_RASTPORT+rp_Font(a4),a0
        jsr     LVO_SETFONT(a6)
        move.l  (sp)+,a1
        move.b  SC_RASTPORT+rp_AlgoStyle(a4),rp_AlgoStyle(a1)
        rts

; mn_ghost(a1 = RastPort, d0..d3 = x0,y0,x1,y1, a4 = screen, a5): ghosting (spec intuition-input-menus-v34 §3.5):
; pattern $4444/$1111 in the BlockPen of the menu's window (the screen's without one), BPen 0, JAM1, RectFill over the
; rectangle. Rows follow the RastPort (line 0 = top of the box layer), the x phase is the screen's: the pattern is
; rotated by the layer's MinX. RastPort state restored. Clobbers d0-d3/a0/a1/a6.
mn_ghost:
        movem.l d4-d7/a2,-(sp)
        move.l  a1,a2
        move.l  rp_minterms+4(a2),-(sp)
        move.l  rp_minterms(a2),-(sp)
        move.l  rp_AreaPtrn(a2),-(sp)
        move.b  rp_AreaPtSz(a2),-(sp)
        move.b  rp_FgPen(a2),-(sp)
        move.b  rp_BgPen(a2),-(sp)
        move.b  rp_DrawMode(a2),-(sp)
        move.w  rp_Flags(a2),-(sp)
        move.l  #$44441111,d4        ; pattern rows 0 / 1
        move.l  rp_Layer(a2),d5
        beq.s   .gh_buffer
        move.l  d5,a0
        move.w  lr_MinX(a0),d5
        bra.s   .gh_phase
.gh_buffer:
        move.w  MB_X(a2),d5
.gh_phase:
        and.w   #3,d5
        rol.w   d5,d4                ; screen x phase: bit 15 of a row = x of the layer's left edge
        swap    d4
        rol.w   d5,d4
        swap    d4
.gh_rot:
        move.l  d4,-(sp)
        move.l  sp,rp_AreaPtrn(a2)
        move.b  #1,rp_AreaPtSz(a2)
        move.b  SC_BLOCKPEN(a4),rp_FgPen(a2)
        move.l  IB_MENUWIN(a5),d4
        beq.s   .gh_pen
        move.l  d4,a0
        move.b  WD_BLOCKPEN(a0),rp_FgPen(a2)
.gh_pen:
        clr.b   rp_BgPen(a2)
        move.b  #JAM1,rp_DrawMode(a2)
        bclr    #3,rp_Flags+1(a2)    ; no AREAOUTLINE
        move.l  IB_GFXBASE(a5),a6
        move.l  a2,a1
        jsr     gfx_minterms
        jsr     LVO_RECTFILL(a6)
        addq.l  #4,sp
        move.w  (sp)+,rp_Flags(a2)
        move.b  (sp)+,rp_DrawMode(a2)
        move.b  (sp)+,rp_BgPen(a2)
        move.b  (sp)+,rp_FgPen(a2)
        move.b  (sp)+,rp_AreaPtSz(a2)
        move.l  (sp)+,rp_AreaPtrn(a2)
        move.l  (sp)+,rp_minterms(a2)
        move.l  (sp)+,rp_minterms+4(a2)
        movem.l (sp)+,d4-d7/a2
        rts

; it_menumove(a5, d4/d5 = pointer): pointer in the bar -> the targeted menu is pulled down (no item selected);
; in the pulled-down menu -> the targeted item is highlighted; elsewhere -> no item.
it_menumove:
        bsr.s   mn_track
        tst.b   IB_MNDRAG(a5)        ; left button held: the code under the pointer is chosen too
        beq.s   .mv_ret
        bra     mn_pickcur
.mv_ret:
        rts
mn_track:
        tst.l   IB_MENUWIN(a5)
        beq     .mm_ret
        cmp.w   #1,IB_DMRSTATE(a5)   ; DMRequest bar: still near the press and in time -> no menu yet
        bne.s   .mm_go
        jsr     it_dmrnear
        beq     .mm_ret
        clr.w   IB_DMRSTATE(a5)
        movem.l a3-a4,-(sp)          ; the bar becomes a menu: MENUWAITING first (§3.3)
        move.l  IB_MENUWIN(a5),a3
        move.l  WD_WSCREEN(a3),a4
        bsr     mn_waiting
        movem.l (sp)+,a3-a4
.mm_go:
        bsr     it_scrxy
        beq     .mm_ret
        move.l  IB_MENUWIN(a5),a3
        tst.l   IB_SUBBOX(a5)        ; rule 1: a sub-item under the pointer
        beq.s   .mm_bar
        bsr     mn_subhit
        bsr     mn_setsub
        move.l  a2,d0
        bne     .mm_ret
.mm_bar:
        move.l  WD_WSCREEN(a3),a0
        moveq   #0,d0
        move.b  SC_BARHEIGHT(a0),d0
        cmp.w   d0,d5
        bge.s   .mm_items
        move.l  WD_MENUSTRIP(a3),a2  ; menu under the pointer
        moveq   #0,d6
.mm_find:
        move.l  a2,d0
        beq.s   .mm_none
        move.w  d4,d0
        moveq   #0,d1
        move.b  SC_BARVBORDER(a4),d1
        sub.w   d1,d0
        sub.w   MU_LEFTEDGE(a2),d0
        bmi.s   .mm_fnx
        cmp.w   MU_WIDTH(a2),d0
        blt.s   .mm_found
.mm_fnx:
        move.l  MU_NEXTMENU(a2),a2
        addq.w  #1,d6
        bra.s   .mm_find
.mm_found:
        bsr     mn_closesub
        cmp.l   IB_MENUCUR(a5),a2
        beq.s   .mm_none
        bsr     mn_closebox
        move.l  a2,-(sp)
        move.l  IB_MENUCUR(a5),a2
        bsr     mn_hltitle
        move.l  (sp)+,a2
        move.l  a2,IB_MENUCUR(a5)
        move.w  d6,IB_MENUNUM(a5)
        bsr     mn_hltitle
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
        move.w  d4,d2                ; position relative to the first item
        sub.w   IB_BOX(a5),d2
        sub.w   IB_BOX+4(a5),d2
        move.w  d5,d3
        sub.w   IB_BOX+2(a5),d3
        sub.w   IB_BOX+6(a5),d3
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

; Toggle the enabled menu title in the bar's own layer. The window's menu pens are complemented through
; the screen depth; the public BarVBorder positions both the hit rectangle and its highlight.
mn_hltitle:
        move.l  a2,d0
        beq.s   .ht_ret
        btst    #0,MU_FLAGS+1(a2)
        beq.s   .ht_ret
        movem.l d0-d3/a0-a1/a6,-(sp)
        move.l  IB_MENUBAR(a5),a0
        move.l  IL_RP(a0),a1
        move.l  IB_GFXBASE(a5),a6
        moveq   #COMPLEMENT,d0
        jsr     LVO_SETDRMD(a6)
        moveq   #0,d0
        move.b  SC_BARVBORDER(a4),d0
        add.w   MU_LEFTEDGE(a2),d0
        moveq   #0,d1
        move.w  d0,d2
        add.w   MU_WIDTH(a2),d2
        subq.w  #1,d2
        moveq   #0,d3
        move.b  SC_BARHEIGHT(a4),d3
        subq.w  #1,d3
        jsr     LVO_RECTFILL(a6)
        movem.l (sp)+,d0-d3/a0-a1/a6
.ht_ret:
        rts

; mn_setitem(a2 = targeted item | 0, d6.w = its number, a4, a5): the hit item changes -> sub-item box of another
; item removed, highlight moved (if the targeted item and its menu are enabled), box of its sub-items
; displayed. Outside the items: highlight off, the sub-item box stays.
mn_setitem:
        cmp.l   IB_ITEMHIT(a5),a2
        beq.s   .si_ret
        move.l  a2,IB_ITEMHIT(a5)
        move.l  a2,d0
        beq.s   .si_off
        cmp.l   IB_SUBITEM(a5),a2
        beq.s   .si_off
        bsr     mn_closesub
.si_off:
        bsr.s   mn_unlight
        move.l  a2,d0
        beq.s   .si_ret
        bsr.s   mn_light
        tst.l   MI_SUBITEM(a2)
        beq.s   .si_ret
        cmp.l   IB_SUBITEM(a5),a2
        bne     mn_opensub
.si_ret:
        rts

; mn_unlight(a5): turns off the highlighted item. mn_light(a2 = item, d6.w = number, a5): lights it if it is enabled
; and its menu too. Both clobber d0-d3/a0/a1/a6.
mn_unlight:
        tst.l   IB_ITEMCUR(a5)
        beq.s   .ul_ret
        moveq   #0,d3
        bsr.s   mn_hilite
        clr.l   IB_ITEMCUR(a5)
.ul_ret:
        rts
mn_light:
        btst    #4,MI_FLAGS+1(a2)    ; ITEMENABLED
        beq.s   .li_ret
        move.l  IB_MENUCUR(a5),a0
        btst    #0,MU_FLAGS+1(a0)    ; MENUENABLED
        beq.s   .li_ret
        move.l  a2,IB_ITEMCUR(a5)
        move.w  d6,IB_ITEMNUM(a5)
        moveq   #1,d3
        bra.s   mn_hilite
.li_ret:
        rts

; mn_hilite(d3.b = 1 on | 0 off, a5): highlight of the current item in the item box; mn_hlsub(d3, a5): of the
; current sub-item in the sub-item box. mn_hlrect(a0 = item, a1 = layer, d0/d1 = origin of the items in the layer,
; d3) (§3.6): HIGHCOMP = complemented rectangle; HIGHBOX = complemented frame outside the item (4 pixels left and
; right, 2 lines above and below); HIGHIMAGE = SelectFill drawn (ItemFill to turn off); HIGHNONE = nothing. HIGHITEM
; follows the state. All clobber d0-d3/a0/a1/a6.
mn_hilite:
        move.l  IB_ITEMCUR(a5),a0
        move.l  IB_MENUBOX(a5),a1
        move.w  IB_BOX+4(a5),d0
        move.w  IB_BOX+6(a5),d1
        bra.s   mn_hlrect
mn_hlsub:
        move.l  IB_SUBCUR(a5),a0
        move.l  IB_SUBBOX(a5),a1
        move.w  IB_SUBOX(a5),d0
        move.w  IB_SUBOY(a5),d1
mn_hlrect:
        bclr    #5,MI_FLAGS(a0)      ; HIGHITEM ($2000)
        tst.b   d3
        beq.s   .hl_st
        bset    #5,MI_FLAGS(a0)
.hl_st:
        move.w  MI_FLAGS(a0),d2
        and.w   #HIGHFLAGS,d2
        cmp.w   #HIGHNONE,d2
        beq     .hl_ret
        movem.l d4-d7/a2-a3,-(sp)
        move.l  a0,a2
        move.l  IL_RP(a1),a3
        move.w  d0,d4                ; d4/d5 = top-left corner of the item in the layer
        add.w   MI_LEFTEDGE(a2),d4
        move.w  d1,d5
        add.w   MI_TOPEDGE(a2),d5
        tst.w   d2
        beq.s   .hl_image
        move.w  d2,-(sp)
        move.l  IB_GFXBASE(a5),a6
        move.l  a3,a1
        moveq   #COMPLEMENT,d0
        jsr     LVO_SETDRMD(a6)
        move.w  d4,d6                ; d6/d7 = bottom-right corner
        add.w   MI_WIDTH(a2),d6
        subq.w  #1,d6
        move.w  d5,d7
        add.w   MI_HEIGHT(a2),d7
        subq.w  #1,d7
        cmp.w   #HIGHBOX,(sp)+
        beq.s   .hl_box
        move.w  d4,d0                ; HIGHCOMP: the item rectangle
        move.w  d5,d1
        move.w  d6,d2
        move.w  d7,d3
        bsr.s   .hl_fill
        bra.s   .hl_done
.hl_box:
        move.w  d4,d0                ; above: 2 lines
        subq.w  #4,d0
        move.w  d5,d1
        subq.w  #2,d1
        move.w  d6,d2
        addq.w  #4,d2
        move.w  d5,d3
        subq.w  #1,d3
        bsr.s   .hl_fill
        move.w  d4,d0                ; below
        subq.w  #4,d0
        move.w  d7,d1
        addq.w  #1,d1
        move.w  d6,d2
        addq.w  #4,d2
        move.w  d7,d3
        addq.w  #2,d3
        bsr.s   .hl_fill
        move.w  d4,d0                ; left: 4 pixels
        subq.w  #4,d0
        move.w  d5,d1
        move.w  d4,d2
        subq.w  #1,d2
        move.w  d7,d3
        bsr.s   .hl_fill
        move.w  d6,d0                ; right
        addq.w  #1,d0
        move.w  d5,d1
        move.w  d6,d2
        addq.w  #4,d2
        move.w  d7,d3
        bsr.s   .hl_fill
        bra.s   .hl_done
.hl_image:
        move.l  MI_ITEMFILL(a2),d0
        tst.b   d3
        beq.s   .hl_draw
        move.l  MI_SELECTFILL(a2),d0
.hl_draw:
        tst.l   d0
        beq.s   .hl_done
        move.l  d0,a1
        move.w  d4,d0
        move.w  d5,d1
        move.l  a3,a0
        move.l  a5,a6
        btst    #1,MI_FLAGS+1(a2)    ; ITEMTEXT
        beq.s   .hl_img
        bsr     intuition_PrintIText
        bra.s   .hl_done
.hl_img:
        jsr     intuition_DrawImage
.hl_done:
        movem.l (sp)+,d4-d7/a2-a3
.hl_ret:
        rts
.hl_fill:                            ; RectFill (d0..d3) in a3, the part left of or above the layer cut off
        ext.l   d0
        bpl.s   .hf_x
        moveq   #0,d0
.hf_x:
        ext.l   d1
        bpl.s   .hf_y
        moveq   #0,d1
.hf_y:
        cmp.w   d0,d2
        blt.s   .hf_ret
        cmp.w   d1,d3
        blt.s   .hf_ret
        ext.l   d2
        ext.l   d3
        move.l  a3,a1
        jmp     LVO_RECTFILL(a6)
.hf_ret:
        rts

; mn_subhit(d4/d5 = pointer, a5) -> a2 = first sub-item of IB_SUBITEM that contains the point | 0, d6.w = its
; number. Clobbers d0-d3.
mn_subhit:
        move.l  IB_SUBITEM(a5),a2
        move.l  MI_SUBITEM(a2),a2
        moveq   #0,d6
        move.w  d4,d2
        sub.w   IB_SUBLX(a5),d2
        sub.w   IB_SUBOX(a5),d2
        move.w  d5,d3
        sub.w   IB_SUBLY(a5),d3
        sub.w   IB_SUBOY(a5),d3
.sh_lp:
        move.l  a2,d0
        beq.s   .sh_ret
        move.w  d2,d0
        sub.w   MI_LEFTEDGE(a2),d0
        bmi.s   .sh_nx
        cmp.w   MI_WIDTH(a2),d0
        bge.s   .sh_nx
        move.w  d3,d0
        sub.w   MI_TOPEDGE(a2),d0
        bmi.s   .sh_nx
        cmp.w   MI_HEIGHT(a2),d0
        blt.s   .sh_ret
.sh_nx:
        move.l  MI_NEXTITEM(a2),a2
        addq.w  #1,d6
        bra.s   .sh_lp
.sh_ret:
        rts

; mn_setsub(a2 = targeted sub-item | 0, d6.w = its number, a4, a5): the highlight moves from the old sub-item to the
; targeted one; a hit sub-item lights its parent item again; it is lit only if it, its item and its menu
; are enabled. Preserves a2.
mn_setsub:
        cmp.l   IB_SUBCUR(a5),a2
        beq.s   .ss_ret
        tst.l   IB_SUBCUR(a5)
        beq.s   .ss_new
        moveq   #0,d3
        bsr     mn_hlsub
        clr.l   IB_SUBCUR(a5)
.ss_new:
        move.l  a2,d0
        beq.s   .ss_ret
        movem.l d6/a2,-(sp)
        move.l  IB_SUBITEM(a5),a2    ; parent item: hit and lit again
        move.l  a2,IB_ITEMHIT(a5)
        cmp.l   IB_ITEMCUR(a5),a2
        beq.s   .ss_lit
        bsr     mn_unlight
        move.w  IB_SUBPNUM(a5),d6
        bsr     mn_light
.ss_lit:
        movem.l (sp)+,d6/a2
        move.l  IB_ITEMCUR(a5),d0    ; parent off (disabled) -> nothing
        beq.s   .ss_ret
        btst    #4,MI_FLAGS+1(a2)    ; ITEMENABLED of the sub-item
        beq.s   .ss_ret
        move.l  a2,IB_SUBCUR(a5)
        move.w  d6,IB_SUBNUM(a5)
        moveq   #1,d3
        bra     mn_hlsub
.ss_ret:
        rts

; mn_openbox(a2 = menu, a4 = screen, a5): smart layer under the bar, at the menu's LeftEdge (shifted to stay
; within the screen), just big enough for its items; background BlockPen, border DetailPen, items (text or image),
; disabled items ghosted. Origin of the layer in IB_BOX. Preserves d2-d7/a2-a4.
mn_openbox:
        movem.l d2-d7/a2-a4,-(sp)
        move.l  MU_FIRSTITEM(a2),d0
        beq     .ob_ret
        btst    #0,MU_FLAGS(a2)      ; MIDRAWN: lazily refresh bounds after client item changes
        bne.s   .ob_measured
        move.l  a5,a6
        bsr     mn_measuremenu
.ob_measured:
        move.w  MU_BEATX(a2),d6
        sub.w   MU_JAZZX(a2),d6      ; box width - 1, including the screen's menu borders
        move.w  MU_BEATY(a2),d7
        moveq   #0,d0
        move.b  SC_MENUVBORDER(a4),d0
        add.w   d0,d7                ; box height - 1
        move.w  d0,IB_BOX+6(a5)      ; item origin inside the box (Y)
        move.w  MU_JAZZX(a2),d0
        neg.w   d0
        move.w  d0,IB_BOX+4(a5)      ; item origin inside the box (X)
        move.w  MU_LEFTEDGE(a2),d0
        moveq   #0,d1
        move.b  SC_BARHBORDER(a4),d1
        add.w   d1,d0
        add.w   MU_JAZZX(a2),d0
        move.w  SC_WIDTH(a4),d1
        subq.w  #1,d1
        sub.w   d6,d1                ; maximum x0
        cmp.w   d1,d0
        ble.s   .ob_x
        move.w  d1,d0
.ob_x:
        tst.w   d0
        bpl.s   .ob_x0
        moveq   #0,d0
.ob_x0:
        moveq   #0,d1
        move.b  SC_BARHEIGHT(a4),d1
        subq.w  #1,d1
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
        movem.w d6-d7,IB_BOXW(a5)
        ; Compose the complete box before exposing it. Its smart layer still keeps the underlying
        ; screen for normal item highlighting, submenus and removal.
        movem.w d0-d3,-(sp)
        bsr     mn_cache_lookup
        tst.l   d0
        beq.s   .ob_compose
        move.l  d0,a3
        bra.s   .ob_ready
.ob_compose:
        move.w  (sp),d0             ; lookup returns zero on a miss; allocation still needs the screen X phase
        bsr     mn_boxalloc
        tst.l   d0
        bne.s   .ob_allocated
        tst.l   IB_MENUCACHE(a5)
        beq.s   .ob_allocated
        bsr     mn_cache_clear       ; optional cached surfaces must not prevent a larger menu allocation
        move.w  (sp),d0
        bsr     mn_boxalloc
.ob_allocated:
        move.l  d0,a3
        tst.l   d0
        beq.w   .ob_nobuf
        bsr     mn_paintbox
        move.w  IB_BOX+4(a5),IB_DOX(a5)
        move.w  IB_BOX+6(a5),IB_DOY(a5)
        btst    #0,MU_FLAGS+1(a2)
        seq     IB_DGHOST(a5)
        move.l  a2,-(sp)
        move.l  MU_FIRSTITEM(a2),a2
        bsr     mn_drawitems
        move.l  (sp)+,a2
.ob_ready:
        movem.w (sp)+,d0-d3
        bsr     mn_save
        move.l  a0,IB_MENUSAVE(a5)
        move.l  a2,-(sp)
        lea     SC_LAYERINFO(a4),a0
        lea     SC_BITMAP(a4),a1
        moveq   #IL_SMART,d4
        suba.l  a2,a2
        move.l  IB_LAYERSBASE(a5),a6
        jsr     LVO_CREATEUPFRONTLAYER(a6)
        move.l  (sp)+,a2
        move.l  d0,IB_MENUBOX(a5)
        beq.s   .ob_layerfail
        bset    #0,MU_FLAGS(a2)
        move.l  d0,a0
        move.l  IL_RP(a0),a1
        bsr     mn_boxshow
        bsr     mn_cache_store
.ob_free:
        bsr     mn_cache_dispose
        bra.s   .ob_ret
.ob_layerfail:
        move.l  IB_MENUSAVE(a5),a0
        clr.l   IB_MENUSAVE(a5)
        moveq   #0,d0
        bsr     mn_restore
        bsr     mn_cache_dispose
        tst.l   IB_MENUCACHE(a5)
        beq.s   .ob_ret
        bsr     mn_cache_clear
        movem.l (sp)+,d2-d7/a2-a4
        bra     mn_openbox          ; one retry after eviction; an empty cache cannot cause another retry
.ob_nobuf:
        addq.l  #8,sp
.ob_ret:
        movem.l (sp)+,d2-d7/a2-a4
        rts

; mn_drawitems(a2 = first item, a3 = RastPort of the box, a4 = screen, a5): each item at (IB_DOX +
; LeftEdge, IB_DOY + TopEdge): ItemFill (text or image), check mark, shortcut; disabled (or IB_DGHOST box): ghosted.
; Preserves d2-d7/a3-a5.
mn_drawitems:
.ob_it:
        move.l  a2,d0
        beq     .ob_ret
        move.l  MI_ITEMFILL(a2),d0
        beq.s   .ob_ghost
        move.l  d0,a1
        move.w  IB_DOX(a5),d0
        add.w   MI_LEFTEDGE(a2),d0
        move.w  IB_DOY(a5),d1
        add.w   MI_TOPEDGE(a2),d1
        move.l  a3,a0
        move.l  a5,a6
        btst    #1,MI_FLAGS+1(a2)    ; ITEMTEXT
        beq.s   .ob_img
        tst.l   rp_Layer(a3)
        bne.s   .ob_itext
        tst.l   IT_ITEXTFONT(a1)
        bne.s   .ob_itext
        tst.l   IT_NEXTTEXT(a1)
        bne.s   .ob_itext
        bsr     mn_stagetext
        bra.s   .ob_ghost
.ob_itext:
        bsr     intuition_PrintIText
        bra.s   .ob_ghost
.ob_img:
        jsr     intuition_DrawImage
.ob_ghost:
        move.w  MI_FLAGS(a2),d0
        and.w   #CHECKIT|CHECKED,d0
        cmp.w   #CHECKIT|CHECKED,d0
        bne.s   .ob_nck
        bsr     mn_drawcheck
.ob_nck:
        btst    #2,MI_FLAGS+1(a2)    ; COMMSEQ: symbol + shortcut character
        beq.s   .ob_gh
        bsr     mn_commseq
.ob_gh:
        btst    #4,MI_FLAGS+1(a2)    ; disabled (or the whole box ghosted): ghosted
        beq.s   .ob_g
        tst.b   IB_DGHOST(a5)
        beq.s   .ob_nx
.ob_g:
        move.w  IB_DOX(a5),d0
        add.w   MI_LEFTEDGE(a2),d0
        move.w  IB_DOY(a5),d1
        add.w   MI_TOPEDGE(a2),d1
        move.w  d0,d2
        add.w   MI_WIDTH(a2),d2
        subq.w  #1,d2
        move.w  d1,d3
        add.w   MI_HEIGHT(a2),d3
        subq.w  #1,d3
        move.l  a3,a1
        movem.l d2-d3,-(sp)
        bsr     mn_ghost
        movem.l (sp)+,d2-d3
.ob_nx:
        move.l  MI_NEXTITEM(a2),a2
        bra     .ob_it
.ob_ret:
        rts

; A single inherited-font IntuiText in our private staging RastPort needs no public save/restore or line-state
; resets. Text reads pens/mode directly; ghosting and any later RectFill synchronize their own minterms.
mn_stagetext:
        movem.l a2/a6,-(sp)
        move.l  a0,a2
        move.l  a1,a0
        move.b  IT_FRONTPEN(a0),rp_FgPen(a2)
        move.b  IT_BACKPEN(a0),rp_BgPen(a2)
        move.b  IT_DRAWMODE(a0),rp_DrawMode(a2)
        st      rp_Mask(a2)
        add.w   IT_LEFTEDGE(a0),d0
        move.w  d0,rp_cp_x(a2)
        add.w   IT_TOPEDGE(a0),d1
        add.w   rp_TxBaseline(a2),d1
        move.w  d1,rp_cp_y(a2)
        move.l  IT_ITEXT(a0),d0
        beq.s   .st_ret
        move.l  d0,a0
        bsr     mn_strlen
        move.l  a2,a1
        move.l  IB_GFXBASE(a5),a6
        jsr     LVO_TEXT(a6)
.st_ret:
        movem.l (sp)+,a2/a6
        rts

; mn_opensub(a2 = item with sub-items, d6.w = its number, a4, a5): sub-item box. Extent of the
; sub-items (relative to the item) widened by MB_MARGIN, bounded to touch the item (left <= Width - 1,
; right >= 0, top <= Height - 1, bottom >= 0), placed over the item then brought back into the screen; simple layer,
; background BlockPen, border DetailPen, sub-items drawn (also ghosted if the menu or the item is disabled).
; Preserves d2-d7/a2-a4.
mn_opensub:
        movem.l d2-d7/a2-a4,-(sp)
        move.l  MI_SUBITEM(a2),a0
        move.w  #$7FFF,d0            ; d0..d3 = left, top, right, bottom (relative to the item)
        move.w  d0,d1
        move.w  #$8000,d2
        move.w  d2,d3
.os_ext:
        move.w  MI_LEFTEDGE(a0),d4
        cmp.w   d0,d4
        bge.s   .os_e1
        move.w  d4,d0
.os_e1:
        add.w   MI_WIDTH(a0),d4
        subq.w  #1,d4
        cmp.w   d2,d4
        ble.s   .os_e2
        move.w  d4,d2
.os_e2:
        move.w  MI_TOPEDGE(a0),d4
        cmp.w   d1,d4
        bge.s   .os_e3
        move.w  d4,d1
.os_e3:
        add.w   MI_HEIGHT(a0),d4
        subq.w  #1,d4
        cmp.w   d3,d4
        ble.s   .os_e4
        move.w  d4,d3
.os_e4:
        move.l  MI_NEXTITEM(a0),d4
        move.l  d4,a0
        bne.s   .os_ext
        subq.w  #MB_MARGIN,d0
        subq.w  #MB_MARGIN,d1
        addq.w  #MB_MARGIN,d2
        addq.w  #MB_MARGIN,d3
        move.w  MI_WIDTH(a2),d4
        subq.w  #1,d4
        cmp.w   d4,d0
        ble.s   .os_c1
        move.w  d4,d0
.os_c1:
        tst.w   d2
        bpl.s   .os_c2
        moveq   #0,d2
.os_c2:
        move.w  MI_HEIGHT(a2),d4
        subq.w  #1,d4
        cmp.w   d4,d1
        ble.s   .os_c3
        move.w  d4,d1
.os_c3:
        tst.w   d3
        bpl.s   .os_c4
        moveq   #0,d3
.os_c4:
        move.w  IB_BOX(a5),d4        ; d4/d5 = screen position of the item
        add.w   IB_BOX+4(a5),d4
        add.w   MI_LEFTEDGE(a2),d4
        move.w  IB_BOX+2(a5),d5
        add.w   IB_BOX+6(a5),d5
        add.w   MI_TOPEDGE(a2),d5
        add.w   d4,d0
        add.w   d4,d2
        add.w   d5,d1
        add.w   d5,d3
        move.w  SC_WIDTH(a4),d7      ; within the screen: shifted left, then right if needed
        subq.w  #1,d7
        sub.w   d2,d7
        bpl.s   .os_x1
        add.w   d7,d0
        add.w   d7,d2
.os_x1:
        move.w  d0,d7
        bpl.s   .os_x2
        sub.w   d7,d0
        sub.w   d7,d2
.os_x2:
        move.w  SC_HEIGHT(a4),d7     ; upwards, without going back up into the bar
        subq.w  #1,d7
        sub.w   d3,d7
        bpl.s   .os_y1
        add.w   d7,d1
        add.w   d7,d3
.os_y1:
        moveq   #0,d7
        move.b  SC_BARHEIGHT(a4),d7
        sub.w   d1,d7
        ble.s   .os_y2
        add.w   d7,d1
        add.w   d7,d3
.os_y2:
        move.w  d0,IB_SUBLX(a5)
        move.w  d1,IB_SUBLY(a5)
        sub.w   d0,d4
        move.w  d4,IB_SUBOX(a5)
        sub.w   d1,d5
        move.w  d5,IB_SUBOY(a5)
        move.w  d2,d6                ; d6/d7 = width / height - 1
        sub.w   d0,d6
        move.w  d3,d7
        sub.w   d1,d7
        ext.l   d0
        ext.l   d1
        ext.l   d2
        ext.l   d3
        bsr     mn_save
        move.l  a0,IB_SUBSAVE(a5)
        moveq   #IL_SIMPLE,d4
        lea     SC_LAYERINFO(a4),a0
        lea     SC_BITMAP(a4),a1
        move.l  a2,-(sp)
        suba.l  a2,a2
        move.l  IB_LAYERSBASE(a5),a6
        jsr     LVO_CREATEUPFRONTLAYER(a6)
        move.l  (sp)+,a2
        move.l  d0,IB_SUBBOX(a5)
        beq     .os_fail
        move.l  a2,IB_SUBITEM(a5)
        move.w  4*4+2(sp),IB_SUBPNUM(a5)   ; input d6 (low word of the 5th long of the movem)
        clr.l   IB_SUBCUR(a5)
        move.l  d0,a3
        move.l  IL_RP(a3),a3         ; a3 = RastPort of the box
        movem.w d6-d7,IB_SUBW(a5)
        bsr     mn_paintbox
        move.w  IB_SUBOX(a5),IB_DOX(a5)
        move.w  IB_SUBOY(a5),IB_DOY(a5)
        move.l  IB_MENUCUR(a5),a0
        btst    #0,MU_FLAGS+1(a0)
        seq     IB_DGHOST(a5)
        btst    #4,MI_FLAGS+1(a2)    ; parent item disabled: sub-items ghosted
        bne.s   .os_draw
        st      IB_DGHOST(a5)
.os_draw:
        move.l  MI_SUBITEM(a2),a2
        bsr     mn_drawitems
.os_ret:
        movem.l (sp)+,d2-d7/a2-a4
        rts
.os_fail:
        move.l  IB_SUBSAVE(a5),a0
        clr.l   IB_SUBSAVE(a5)
        moveq   #0,d0
        bsr     mn_restore
        bra.s   .os_ret

; mn_closesub(a5): removes the sub-item box (if there is one) and repairs what it covered. Preserves
; d2-d7/a2-a4.
mn_closesub:
        move.l  IB_SUBBOX(a5),d0
        beq.s   .cs_ret
        clr.l   IB_SUBBOX(a5)
        clr.l   IB_SUBITEM(a5)
        clr.l   IB_SUBCUR(a5)
        move.l  a2,-(sp)
        move.l  d0,a1
        suba.l  a0,a0
        move.l  IB_LAYERSBASE(a5),a6
        jsr     LVO_DELETELAYER(a6)
        move.l  IB_SUBSAVE(a5),a0
        clr.l   IB_SUBSAVE(a5)
        moveq   #1,d0
        bsr     mn_restore
        bsr     it_refresh
        move.l  (sp)+,a2
.cs_ret:
        rts

; mn_commseq(a2 = item, a3 = RastPort of the box, a4 = screen, a5 = IntuitionBase): the Command character at
; x = item + Width - character width - 2 (pen DetailPen, JAM1), at the height of the item's text, and the
; cat just to its left (2 pixels apart). Preserves d2-d7/a2-a5.
mn_commseq:
        movem.l d2-d4/a6,-(sp)
        move.w  IB_DOX(a5),d2
        add.w   MI_LEFTEDGE(a2),d2
        add.w   MI_WIDTH(a2),d2
        sub.w   rp_TxWidth(a3),d2
        subq.w  #2,d2                ; d2 = x of the character
        move.w  IB_DOY(a5),d3
        add.w   MI_TOPEDGE(a2),d3    ; d3 = y (top of the item's text)
        btst    #1,MI_FLAGS+1(a2)
        beq.s   .cq_y
        move.l  MI_ITEMFILL(a2),d0
        beq.s   .cq_y
        move.l  d0,a0
        add.w   IT_TOPEDGE(a0),d3
.cq_y:
        move.l  IB_GFXBASE(a5),a6
        move.l  a3,a1
        bsr     mn_windowpens
        jsr     LVO_SETAPEN(a6)
        move.l  a3,a1
        moveq   #JAM1,d0
        jsr     LVO_SETDRMD(a6)
        move.l  a3,a1
        move.w  d2,d0
        ext.l   d0
        move.w  d3,d1
        add.w   rp_TxBaseline(a3),d1
        ext.l   d1
        jsr     LVO_MOVE(a6)
        move.l  a3,a1
        lea     MI_COMMAND(a2),a0
        moveq   #1,d0
        jsr     LVO_TEXT(a6)
        lea     mn_cat_lo(pc),a1     ; cat: hires version if the screen is hires
        tst.w   SC_VIEWPORT+vp_Modes(a4)
        bpl.s   .cq_lo
        lea     mn_cat_hi(pc),a1
.cq_lo:
        move.w  d2,d0
        sub.w   4(a1),d0             ; Image.Width
        subq.w  #2,d0
        ext.l   d0
        move.w  d3,d1
        ext.l   d1
        move.l  a3,a0
        move.l  a5,a6
        jsr     intuition_DrawImage
        movem.l (sp)+,d2-d4/a6
        rts

; mn_drawcheck(a2 = item, a3 = RastPort of the box, a4 = screen, a5 = IntuitionBase): check mark of the menu's window
; (Window->CheckMark, otherwise the internal one) at (x of the item, y of the item + TopEdge of its ItemFill). Preserves
; d2-d7/a2-a5.
mn_drawcheck:
        move.l  a6,-(sp)
        moveq   #0,d0
        move.l  IB_MENUWIN(a5),d1
        beq.s   .dc_def
        move.l  d1,a0
        move.l  WD_CHECKMARK(a0),d0
.dc_def:
        tst.l   d0
        bne.s   .dc_img
        bsr.s   mn_defcheck
.dc_img:
        move.l  d0,a1
        move.w  IB_DOY(a5),d1
        add.w   MI_TOPEDGE(a2),d1
        move.l  MI_ITEMFILL(a2),d0
        beq.s   .dc_y
        move.l  d0,a0
        btst    #1,MI_FLAGS+1(a2)    ; ITEMTEXT: IntuiText.TopEdge, otherwise Image.TopEdge
        beq.s   .dc_iy
        add.w   IT_TOPEDGE(a0),d1
        bra.s   .dc_y
.dc_iy:
        add.w   2(a0),d1
.dc_y:
        ext.l   d1
        move.w  IB_DOX(a5),d0
        add.w   MI_LEFTEDGE(a2),d0
        ext.l   d0
        move.l  a3,a0
        move.l  a5,a6
        jsr     intuition_DrawImage
        move.l  (sp)+,a6
        rts

; mn_defcheck(a4 = screen) -> d0 = internal check mark (hires if the screen's ViewPort is). Preserves the rest.
mn_defcheck:
        lea     mn_chk_lo(pc),a0
        move.l  a0,d0
        tst.w   SC_VIEWPORT+vp_Modes(a4)
        bpl.s   .df_r
        lea     mn_chk_hi(pc),a0
        move.l  a0,d0
.df_r:
        rts

; Internal menu check mark: a cat paw print (KickSlopStart's own design, unrelated to the 1.3 image;
; LeftEdge 2, bits at 1 = background, drawing at 0).
mn_chk_hi:
        dc.w    2,0,15,8,1
        dc.l    mn_chk_hi_data
        dc.b    1,0
        dc.l    0
mn_chk_lo:
        dc.w    2,0,9,8,1
        dc.l    mn_chk_lo_data
        dc.b    1,0
        dc.l    0
mn_chk_hi_data:                      ; cat paw print: four toes and the pad (15 x 8)
        dc.w    $F39F,$E38F,$9FF3,$9833,$F01F,$E00F,$E00F,$F11F
mn_chk_lo_data:                      ; the same in low resolution (9 x 8)
        dc.w    $DDFF,$9CFF,$7F7F,$637F,$C1FF,$80FF,$80FF,$C9FF

; The Amiga-key cat (struct Image: Left, Top, Width, Height, Depth, ImageData, PlanePick, PlaneOnOff, Next).
; 1.3 format: PlanePick 1, PlaneOnOff 0, bits at 1 = background (color 1), drawing at 0 (color 0).
mn_cat_hi:
        dc.w    0,0,23,8,1
        dc.l    mn_cat_hi_data
        dc.b    1,0
        dc.l    0
mn_cat_lo:
        dc.w    0,0,14,8,1
        dc.l    mn_cat_lo_data
        dc.b    1,0
        dc.l    0
mn_cat_hi_data:                      ; ears, eyes, whiskers, nose, chin (23 x 8)
        dc.w    $FDFF,$7FFF
        dc.w    $FCFE,$7FFF
        dc.w    $FC00,$7FFF
        dc.w    $FC82,$7FFF
        dc.w    $E000,$0FFF
        dc.w    $FC10,$7FFF
        dc.w    $E101,$0FFF
        dc.w    $FF01,$FFFF
mn_cat_lo_data:                      ; the same in low resolution (14 x 8)
        dc.w    $EFDF
        dc.w    $E79F
        dc.w    $E01F
        dc.w    $E85F
        dc.w    $8007
        dc.w    $E31F
        dc.w    $9027
        dc.w    $F87F

 ; A temporary CHIP RastPort/BitMap plus its planes. The completed image is copied into the new
; menu layer once, keeping intermediate fills, glyphs and ghosting off the displayed BitMap.
MB_BM           EQU rp_SIZEOF
MB_SIZE         EQU MB_BM+bm_SIZEOF
MB_X            EQU MB_SIZE+4
MB_TR           EQU MB_X+4          ; optional shared text-line TmpRas (CHIP)
MB_HEADER       EQU MB_TR+8
; mn_boxalloc(d0.w = screen x, d6/d7 = width/height - 1, a4 = screen) -> d0 = buffer RastPort | 0.
mn_boxalloc:
        movem.l d1-d7/a0-a2/a6,-(sp)
        move.w  d0,d4
        move.w  d6,d5
        add.w   #16,d5
        lsr.w   #4,d5
        add.w   d5,d5                ; word-aligned row stride
        move.w  d7,d2
        addq.w  #1,d2
        mulu    d5,d2                ; bytes per plane
        moveq   #0,d3
        move.b  SC_BITMAP+bm_Depth(a4),d3
        move.l  d2,d0
        mulu    d3,d0
        add.l   #MB_HEADER,d0
        move.l  d0,d6
        move.l  #MEMF_CHIP|MEMF_CLEAR,d1
        move.l  4.w,a6
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.s   .ba_ret
        move.l  d0,a2
        move.l  d6,MB_SIZE(a2)
        move.w  d4,MB_X(a2)
        move.l  IB_GFXBASE(a5),a6
        move.l  a2,a1
        jsr     LVO_INITRASTPORT(a6)
        lea     MB_BM(a2),a0
        move.l  a0,rp_BitMap(a2)
        move.w  d5,bm_BytesPerRow(a0)
        addq.w  #1,d7
        move.w  d7,bm_Rows(a0)
        move.b  d3,bm_Depth(a0)
        lea     MB_HEADER(a2),a1
        lea     bm_Planes(a0),a0
        subq.w  #1,d3
.ba_plane:
        move.l  a1,(a0)+
        adda.l  d2,a1
        dbra    d3,.ba_plane
        ; Reuse a line buffer while composing this box instead of allocating one per item. A larger
        ; explicit font or a failed scratch allocation still takes Text's ordinary allocation path.
        moveq   #0,d0
        move.w  d5,d0
        addq.l  #8,d0
        move.l  SC_RASTPORT+rp_Font(a4),a0
        mulu    tf_YSize(a0),d0
        move.l  d0,MB_TR+tr_Size(a2)
        moveq   #MEMF_CHIP,d1
        move.l  4.w,a6
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.s   .ba_ready
        move.l  d0,MB_TR+tr_RasPtr(a2)
        lea     MB_TR(a2),a0
        move.l  a0,rp_TmpRas(a2)
.ba_ready:
        move.l  a2,d0
.ba_ret:
        movem.l (sp)+,d1-d7/a0-a2/a6
        rts
; mn_boxshow(a3 = buffer RastPort, a1 = destination RastPort, d6/d7 = width/height - 1).
mn_boxshow:
        movem.l d2-d7/a0-a2/a6,-(sp)
        ; Initial pixels come from the staging bitmap, but HIGHIMAGE hover/unhover later draws through
        ; this visible RastPort. IntuiText without ITextFont must inherit the same screen font and style.
        move.l  IB_GFXBASE(a5),a6
        bsr     mn_screenfont
        move.l  rp_BitMap(a3),a0
        moveq   #0,d0
        moveq   #0,d1
        moveq   #0,d2
        moveq   #0,d3
        move.w  d6,d4
        addq.w  #1,d4
        move.w  d7,d5
        addq.w  #1,d5
        moveq   #-$40,d6
        move.l  IB_GFXBASE(a5),a6
        jsr     LVO_BLTBITMAPRASTPORT(a6)
        movem.l (sp)+,d2-d7/a0-a2/a6
        rts
; mn_boxfree(a3 = temporary RastPort). Wait for any image DMA before returning the CHIP allocation.
mn_boxfree:
        movem.l d0-d1/a0-a1/a6,-(sp)
        move.l  IB_GFXBASE(a5),a6
        jsr     -228(a6)             ; WaitBlit
        move.l  4.w,a6
        move.l  MB_TR+tr_RasPtr(a3),d0
        beq.s   .bf_bitmap
        move.l  d0,a1
        move.l  MB_TR+tr_Size(a3),d0
        jsr     LVO_FREEMEM(a6)
.bf_bitmap:
        move.l  MB_SIZE(a3),d0
        move.l  a3,a1
        jsr     LVO_FREEMEM(a6)
        movem.l (sp)+,d0-d1/a0-a1/a6
        rts

; mn_paintbox(a3 = RastPort of a box, d6/d7 = width - 1 / height - 1, a4 = screen, a5): window background
; BlockPen and border DetailPen. Clobbers d0-d3/a0/a1/a6.
mn_paintbox:
        move.l  IB_GFXBASE(a5),a6
        move.l  a3,a1
        bsr     mn_screenfont
        move.l  a3,a1
        moveq   #JAM2,d0
        jsr     LVO_SETDRMD(a6)
        move.l  a3,a1
        bsr     mn_windowpens
        move.l  d1,d0
        jsr     LVO_SETAPEN(a6)
        move.l  a3,a1
        moveq   #0,d0
        moveq   #0,d1
        move.w  d6,d2
        move.w  d7,d3
        jsr     LVO_RECTFILL(a6)
        move.l  a3,a1
        bsr     mn_windowpens
        jsr     LVO_SETAPEN(a6)
        move.l  a3,a1
        moveq   #0,d0
        moveq   #0,d1
        move.w  d6,d2
        move.w  d7,d3
        bsr     it_box
        moveq   #1,d0               ; menu frames have two-pixel vertical sides
        moveq   #0,d1
        moveq   #1,d2
        move.w  d7,d3
        jsr     LVO_RECTFILL(a6)
        move.w  d6,d0
        subq.w  #1,d0
        moveq   #0,d1
        move.w  d0,d2
        move.w  d7,d3
        jmp     LVO_RECTFILL(a6)

; mn_actclr(a3 = window being activated): the working flags of its whole menu strip cleared as when a menu opens
; (intuition-input-menus §1.11 step 3, §3.8). Preserves all registers.
mn_actclr:
        movem.l d0-d2/a0,-(sp)
        move.l  WD_MENUSTRIP(a3),d0
        beq.s   .ac_ret
        move.l  d0,a0
        move.w  #MENUTOGGLED|HIGHITEM|ISDRAWN,d0
        move.w  #MENUTOGGLED|HIGHITEM,d1
        move.w  #MIDRAWN,d2
        bsr.s   mn_clrflags
.ac_ret:
        movem.l (sp)+,d0-d2/a0
        rts

; mn_clrflags(a0 = first Menu, d0.w = flags cleared in the items, d1.w = in the sub-items, d2.w = in the menus).
; Preserves all registers.
mn_clrflags:
        movem.l d0-d3/a0-a2,-(sp)
        not.w   d0
        not.w   d1
        not.w   d2
.cf_menu:
        move.l  a0,d3
        beq.s   .cf_ret
        and.w   d2,MU_FLAGS(a0)
        move.l  MU_FIRSTITEM(a0),a1
.cf_item:
        move.l  a1,d3
        beq.s   .cf_nmenu
        and.w   d0,MI_FLAGS(a1)
        move.l  MI_SUBITEM(a1),a2
.cf_sub:
        move.l  a2,d3
        beq.s   .cf_nitem
        and.w   d1,MI_FLAGS(a2)
        move.l  MI_NEXTITEM(a2),a2
        bra.s   .cf_sub
.cf_nitem:
        move.l  MI_NEXTITEM(a1),a1
        bra.s   .cf_item
.cf_nmenu:
        move.l  MU_NEXTMENU(a0),a0
        bra.s   .cf_menu
.cf_ret:
        movem.l (sp)+,d0-d3/a0-a2
        rts

; mn_walk(a0 = first link, d1.w = rank) -> a0 = that link | 0, Z = 1 if none (NextMenu / NextItem at offset 0).
; Preserves d0-d7/a1-a6.
mn_walk:
        movem.l d0-d1,-(sp)
.wk_lp:
        move.l  a0,d0
        beq.s   .wk_ret
        subq.w  #1,d1
        bmi.s   .wk_ret
        move.l  (a0),a0
        bra.s   .wk_lp
.wk_ret:
        movem.l (sp)+,d0-d1
        rts

; mn_pick(d0.w = menu code, a3 = window, a5) -> d0.l = 0 refused, bit 0 = chosen, bit 1 = a check mark changed.
; "Select the current code" of spec intuition-input-menus §3.8: refused if the code is MENUNULL, names no item, or its
; menu, item or sub-item is disabled, or it is an item with sub-items and no sub-item; CHECKIT: stop if MENUTOGGLED
; is already set, else CHECKED set (toggled with MENUTOGGLE) and MENUTOGGLED set; NextSelect := MENUNULL and the
; code appended to the chain headed by IB_PICK (a link to this code is cut first; a code that is the head leaves
; the head alone); MutualExclude: the CHECKIT and CHECKED siblings it names lose CHECKED. Preserves d1-d7/a0-a6.
mn_pick:
        movem.l d1-d7/a0-a2,-(sp)
        move.w  d0,d7                ; d7 = code
        moveq   #0,d6                ; d6 = result
        cmp.w   #MENUNULL,d7
        beq     .pk_ret
        move.l  WD_MENUSTRIP(a3),a0
        move.w  d7,d1
        and.w   #$1F,d1
        bsr     mn_walk
        beq     .pk_ret
        btst    #0,MU_FLAGS+1(a0)    ; MENUENABLED
        beq     .pk_ret
        move.l  MU_FIRSTITEM(a0),a0
        move.l  a0,a2                ; a2 = first of the chosen item's list
        move.w  d7,d1
        lsr.w   #5,d1
        and.w   #$3F,d1
        cmp.w   #$3F,d1              ; NOITEM
        beq     .pk_ret
        bsr     mn_walk
        beq     .pk_ret
        btst    #4,MI_FLAGS+1(a0)    ; ITEMENABLED
        beq     .pk_ret
        move.w  d7,d1
        moveq   #11,d0
        lsr.w   d0,d1
        cmp.w   #$1F,d1              ; NOSUB
        bne.s   .pk_sub
        tst.l   MI_SUBITEM(a0)       ; item with sub-items, none chosen
        bne     .pk_ret
        bra.s   .pk_chk
.pk_sub:
        move.l  MI_SUBITEM(a0),a0
        move.l  a0,a2
        bsr     mn_walk
        beq     .pk_ret
        btst    #4,MI_FLAGS+1(a0)
        beq     .pk_ret
.pk_chk:
        btst    #0,MI_FLAGS+1(a0)    ; CHECKIT
        beq.s   .pk_chain
        btst    #6,MI_FLAGS(a0)      ; MENUTOGGLED ($4000): already toggled since the last click
        bne     .pk_ret
        bset    #6,MI_FLAGS(a0)
        moveq   #2,d6
        bset    #0,MI_FLAGS(a0)      ; CHECKED ($100)
        beq.s   .pk_chain
        btst    #3,MI_FLAGS+1(a0)    ; MENUTOGGLE: a checked item is unchecked
        bne.s   .pk_uncheck
        moveq   #0,d6                ; already checked: no change
        bra.s   .pk_chain
.pk_uncheck:
        bclr    #0,MI_FLAGS(a0)
.pk_chain:
        btst    #1,d6
        beq.s   .pk_hi
        bclr    #5,MI_FLAGS(a0)      ; its check mark changed: redrawn, the item loses HIGHITEM (§5 step 5: 415B)
.pk_hi:
        addq.l  #1,d6
        move.w  #MENUNULL,MI_NEXTSELECT(a0)
        move.w  IB_PICK(a5),d3
        cmp.w   #MENUNULL,d3
        bne.s   .pk_walk
        move.w  d7,IB_PICK(a5)
        bra.s   .pk_mx
.pk_walk:
        cmp.w   d7,d3
        beq.s   .pk_mx               ; the head itself: the chain is reduced to it
        move.l  a0,-(sp)
        move.w  #1023,d4             ; bound on a looping chain
.pk_wl:
        move.l  WD_MENUSTRIP(a3),a0
        move.w  d3,d0
        bsr     mn_find
        move.l  a0,d0
        beq.s   .pk_wend
        move.w  MI_NEXTSELECT(a0),d3
        cmp.w   d7,d3
        bne.s   .pk_wn
        move.w  #MENUNULL,d3         ; link to the chosen code: cut here
        move.w  d3,MI_NEXTSELECT(a0)
.pk_wn:
        cmp.w   #MENUNULL,d3
        beq.s   .pk_tail
        dbra    d4,.pk_wl
        bra.s   .pk_wend
.pk_tail:
        move.w  d7,MI_NEXTSELECT(a0) ; appended at the tail
.pk_wend:
        move.l  (sp)+,a0
.pk_mx:
        move.l  MI_MUTUALEXCLUDE(a0),d2
        beq.s   .pk_ret
        moveq   #0,d1                ; d1 = rank of the sibling
.pk_ml:
        move.l  a2,d0
        beq.s   .pk_ret
        btst    d1,d2
        beq.s   .pk_mn
        cmp.l   a0,a2                ; its own bit does not uncheck it
        beq.s   .pk_mn
        move.w  MI_FLAGS(a2),d0
        and.w   #CHECKIT|CHECKED,d0
        cmp.w   #CHECKIT|CHECKED,d0
        bne.s   .pk_mn
        bclr    #0,MI_FLAGS(a2)
        or.w    #2,d6
.pk_mn:
        move.l  MI_NEXTITEM(a2),a2
        addq.w  #1,d1
        cmp.w   #32,d1
        blo.s   .pk_ml
.pk_ret:
        move.l  d6,d0
        movem.l (sp)+,d1-d7/a0-a2
        rts

; mn_curcode(a5) -> d0.w = code of the highlighted sub-item, else of the highlighted item (NOSUB), else MENUNULL.
mn_curcode:
        tst.l   IB_SUBCUR(a5)
        beq.s   .cc_item
        move.w  IB_SUBNUM(a5),d0     ; sub-item << 11 | item << 5 | menu
        lsl.w   #6,d0
        or.w    IB_SUBPNUM(a5),d0
        lsl.w   #5,d0
        or.w    IB_MENUNUM(a5),d0
        rts
.cc_item:
        tst.l   IB_ITEMCUR(a5)
        beq.s   .cc_null
        move.w  IB_ITEMNUM(a5),d0
        lsl.w   #5,d0
        or.w    IB_MENUNUM(a5),d0
        or.w    #$1F<<11,d0          ; NOSUB
        rts
.cc_null:
        move.w  #MENUNULL,d0
        rts

; mn_pickcur(a5): menus displayed, left button held: the current code is chosen; a changed check mark redraws its
; box. Preserves all registers.
mn_pickcur:
        movem.l d0-d7/a0-a4/a6,-(sp)
        move.l  IB_MENUWIN(a5),d0
        beq.s   .pc_ret
        move.l  d0,a3
        move.l  WD_WSCREEN(a3),a4
        bsr.s   mn_curcode
        bsr     mn_pick
        btst    #1,d0
        beq.s   .pc_ret
        bsr.s   mn_repaint
.pc_ret:
        movem.l (sp)+,d0-d7/a0-a4/a6
        rts

; mn_repaint(a4 = screen, a5): the box of the current code is drawn again (check marks changed), then its
; highlight put back (§3.8 point 5). The redrawn item does not get HIGHITEM back: 1.3's NextSelect chain shows a
; CHECKIT item toggled at MENUUP without it (§5 step 5: 415B / 405B). The code was accepted, so its menu and item
; are enabled.
mn_repaint:
        tst.l   IB_SUBCUR(a5)
        bne.s   .rp_sub
        move.l  IB_MENUBOX(a5),d0
        beq.s   .rp_ret
        move.l  d0,a0
        move.l  IL_RP(a0),a3
        movem.w IB_BOXW(a5),d6-d7
        bsr     mn_paintbox
        move.w  #MB_MARGIN,IB_DOX(a5)
        move.w  #MB_MARGIN,IB_DOY(a5)
        sf      IB_DGHOST(a5)
        move.l  IB_MENUCUR(a5),a2
        move.l  MU_FIRSTITEM(a2),a2
        bsr     mn_drawitems
        moveq   #1,d3
        bsr     mn_hilite
        move.l  IB_ITEMCUR(a5),a0
        bclr    #5,MI_FLAGS(a0)      ; HIGHITEM
        rts
.rp_sub:
        move.l  IB_SUBBOX(a5),a0
        move.l  IL_RP(a0),a3
        movem.w IB_SUBW(a5),d6-d7
        bsr     mn_paintbox
        move.w  IB_SUBOX(a5),IB_DOX(a5)
        move.w  IB_SUBOY(a5),IB_DOY(a5)
        sf      IB_DGHOST(a5)
        move.l  IB_SUBITEM(a5),a2
        move.l  MI_SUBITEM(a2),a2
        bsr     mn_drawitems
        moveq   #1,d3
        bsr     mn_hlsub
        move.l  IB_SUBCUR(a5),a0
        bclr    #5,MI_FLAGS(a0)
.rp_ret:
        rts

; mn_lbutton(d7.w = button code, a5): left button while menus are displayed (§3.9): press = MENUTOGGLED cleared in
; the whole bar, the current code chosen, then each pointer move chooses the code under it until the release. No
; message to the window.
mn_lbutton:
        cmp.w   #IECODE_LBUTTON,d7
        beq.s   .lb_down
        cmp.w   #IECODE_LBUTTON|IECODE_UP_PREFIX,d7
        bne.s   .lb_ret
        clr.b   IB_MNDRAG(a5)
.lb_ret:
        rts
.lb_down:
        st      IB_MNDRAG(a5)
        move.l  IB_MENUWIN(a5),a0
        move.l  WD_MENUSTRIP(a0),a0
        move.w  #MENUTOGGLED,d0
        move.w  d0,d1
        moveq   #0,d2
        bsr     mn_clrflags
        bra     mn_pickcur

; mn_closebox(a4, a5): deletes the pulled-down menu (if it exists) and repairs the screen. Preserves d2-d7/a2-a4.
mn_closebox:
        bsr     mn_closesub
        clr.l   IB_ITEMHIT(a5)
        move.l  IB_MENUBOX(a5),d0
        beq.s   .cb_ret
        clr.l   IB_MENUBOX(a5)
        clr.l   IB_ITEMCUR(a5)
        move.l  a2,-(sp)
        move.l  d0,a1
        suba.l  a0,a0
        move.l  IB_LAYERSBASE(a5),a6
        jsr     LVO_DELETELAYER(a6)
        move.l  IB_MENUSAVE(a5),a0
        clr.l   IB_MENUSAVE(a5)
        moveq   #1,d0
        bsr     mn_restore
        bsr     it_refresh
        move.l  (sp)+,a2
.cb_ret:
        rts

; 1.3 swaps a menu box with the screen (intuition-input-menus §0 point 5): what was under it comes back when it
; closes, and no window gets damage or REFRESHWINDOW from it. Our boxes are layers, whose removal clears and damages
; the SIMPLE_REFRESH layers they covered (a Deluxe Paint III picture lost its pixels under every menu). So the screen
; pixels under a box are saved before its layer is made and put back after the layer is deleted, all layers of the
; screen being locked for the whole menu, and the damage the deletion gave the layers that had none is dropped.
SV_X            EQU bm_SIZEOF        ; WORDs: rectangle on the screen
SV_Y            EQU SV_X+2
SV_W            EQU SV_X+4
SV_H            EQU SV_X+6
SV_SIZE         EQU SV_X+8           ; LONG: size of the block
SV_N            EQU SV_X+12          ; WORD: layers without damage when the box opened
SV_LAYERS       EQU SV_X+16          ; their addresses, then the planes
MN_BLTBITMAP    EQU -30              ; graphics.library BltBitMap
MN_WAITBLIT     EQU -228             ; graphics.library WaitBlit

; mn_save(d0-d3.w = x0, y0, x1, y1 of the box on the screen, a4 = screen, a5) -> a0 = block | 0 (no CHIP memory: the
; box then behaves as before). Preserves the other registers.
mn_save:
        movem.l d0-d7/a1-a6,-(sp)
        move.w  d2,d4
        sub.w   d0,d4
        addq.w  #1,d4                ; d4 = width
        move.w  d3,d5
        sub.w   d1,d5
        addq.w  #1,d5                ; d5 = height
        moveq   #0,d6                ; d6 = layers of the screen
        move.l  SC_LAYERINFO(a4),a0
.sv_cnt:
        move.l  a0,d7
        beq.s   .sv_cnted
        addq.w  #1,d6
        move.l  IL_BACK(a0),a0
        bra.s   .sv_cnt
.sv_cnted:
        move.w  d0,d7
        and.w   #15,d7
        add.w   d4,d7
        add.w   #15,d7
        lsr.w   #4,d7
        add.w   d7,d7                ; d7 = bytes per row of the saved planes (even)
        movem.w d0-d1/d4-d7,-(sp)    ; x0, y0, width, height, layers, bytes per row
        mulu    d5,d7                ; bytes per plane
        moveq   #0,d0
        move.b  SC_BITMAP+bm_Depth(a4),d0
        mulu    d0,d7
        moveq   #0,d0
        move.w  d6,d0
        lsl.l   #2,d0
        add.l   d0,d7
        add.l   #SV_LAYERS,d7        ; d7 = size of the block
        move.l  d7,d0
        move.l  #MEMF_CHIP|MEMF_PUBLIC,d1
        move.l  ($4).w,a6
        jsr     LVO_ALLOCMEM(a6)
        move.l  d0,a3                ; a3 = block
        tst.l   d0
        bne.s   .sv_have
        lea     12(sp),sp
        bra     .sv_none
.sv_have:
        move.l  d7,SV_SIZE(a3)
        movem.w (sp)+,d0-d1/d4-d7
        movem.w d0-d1/d4-d5,SV_X(a3)
        move.l  IB_GFXBASE(a5),a6
        move.l  a3,a0
        moveq   #0,d0
        move.b  SC_BITMAP+bm_Depth(a4),d0
        move.w  d7,d1
        lsl.w   #3,d1
        move.w  d5,d2
        jsr     LVO_INITBITMAP(a6)
        lea     SV_LAYERS(a3),a1     ; layers without damage
        moveq   #0,d0
        move.l  SC_LAYERINFO(a4),a0
.sv_lay:
        cmpa.w  #0,a0
        beq.s   .sv_layed
        btst    #ILB_REFRESH,IL_FLAGS+1(a0)
        bne.s   .sv_lnext
        move.l  a0,(a1)+
        addq.w  #1,d0
.sv_lnext:
        move.l  IL_BACK(a0),a0
        bra.s   .sv_lay
.sv_layed:
        move.w  d0,SV_N(a3)
        lsl.w   #2,d6                ; planes after the room for every layer
        lea     SV_LAYERS(a3,d6.w),a1
        mulu    d5,d7
        moveq   #0,d0
        lea     bm_Planes(a3),a0
.sv_pl:
        cmp.b   SC_BITMAP+bm_Depth(a4),d0
        bhs.s   .sv_copy
        move.l  a1,(a0)+
        add.l   d7,a1
        addq.w  #1,d0
        bra.s   .sv_pl
.sv_copy:
        lea     SC_BITMAP(a4),a0     ; screen -> block, same phase in the word
        move.l  a3,a1
        movem.w SV_X(a3),d0-d1/d4-d5
        move.w  d0,d2
        and.w   #15,d2
        moveq   #0,d3
        move.l  #$C0,d6
        moveq   #-1,d7
        suba.l  a2,a2
        jsr     MN_BLTBITMAP(a6)
        move.l  a3,a0
        bra.s   .sv_ret
.sv_none:
        suba.l  a0,a0
.sv_ret:
        movem.l (sp)+,d0-d7/a1-a6
        rts

; mn_restore(a0 = block of mn_save | 0, d0.b = 0: only freed, else its pixels put back and the damage of its clean
; layers dropped first; a4 = screen, a5). Preserves d2-d7/a2-a6.
mn_restore:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  a0,d1
        beq.s   .sr_ret
        move.l  a0,a3
        move.l  IB_GFXBASE(a5),a6
        tst.b   d0
        beq.s   .sr_free
        move.l  a3,a0                ; block -> screen
        lea     SC_BITMAP(a4),a1
        movem.w SV_X(a3),d2-d5
        move.w  d2,d0
        and.w   #15,d0
        moveq   #0,d1
        move.l  #$C0,d6
        moveq   #-1,d7
        suba.l  a2,a2
        jsr     MN_BLTBITMAP(a6)
        move.l  SC_LAYERINFO(a4),a2
.sr_lay:
        cmpa.w  #0,a2
        beq.s   .sr_free
        btst    #ILB_REFRESH,IL_FLAGS+1(a2)
        beq.s   .sr_lnext
        lea     SV_LAYERS(a3),a0
        move.w  SV_N(a3),d2
        bra.s   .sr_find
.sr_fl:
        cmpa.l  (a0)+,a2
        beq.s   .sr_clean
.sr_find:
        dbra    d2,.sr_fl
        bra.s   .sr_lnext
.sr_clean:
        move.l  IL_DAMAGE(a2),d0
        beq.s   .sr_nodmg
        move.l  d0,a0
        jsr     LVO_CLEARREGION(a6)
.sr_nodmg:
        bclr    #ILB_REFRESH,IL_FLAGS+1(a2)
.sr_lnext:
        move.l  IL_BACK(a2),a2
        bra.s   .sr_lay
.sr_free:
        jsr     MN_WAITBLIT(a6)
        move.l  a3,a1
        move.l  SV_SIZE(a3),d0
        move.l  ($4).w,a6
        jsr     LVO_FREEMEM(a6)
.sr_ret:
        movem.l (sp)+,d2-d7/a2-a6
        rts

; mn_keyshort(a0 = active window, a1 = IntuitionBase, a3 = InputEvent, d0.w = raw code of a key pressed with
; right Amiga): input.device handler. Window with no requester, no menus in progress, no RMBTRAP, with a menu strip;
; key converted by the keymap (kbd_cook) -> d0.l = menu code (mn_keyfind) or -1. Clobbers d1; preserves a0/a1.
mn_keyshort:
        move.l  WD_FLAGS(a0),d1
        and.l   #INREQUEST|MENUSTATE|RMBTRAP,d1
        bne.s   .ks_no
        tst.l   IB_MENUWIN(a1)
        bne.s   .ks_no
        tst.l   WD_MENUSTRIP(a0)
        beq.s   .ks_no
        cmp.w   #$60,d0
        bhs.s   .ks_no
        move.w  IE_QUALIFIER(a3),d1
        jsr     kbd_cook
        bra.s   mn_keyfind
.ks_no:
        moveq   #-1,d0
        rts

; mn_keyfind(a0 = window, d0.b = character) -> d0.l = code of the first item (without sub-items) or sub-item
; whose Command & $5F = character & $5F, in the order menus -> items -> sub-items; -1 if none or if
; character & $5F = 0. Preserves everything but d0.
mn_keyfind:
        movem.l d1-d4/a0-a2,-(sp)
        and.b   #$5F,d0
        beq.s   .kf_no
        move.l  WD_MENUSTRIP(a0),a1
        moveq   #0,d2                ; menu number
.kf_menu:
        move.l  a1,d1
        beq.s   .kf_no
        move.l  MU_FIRSTITEM(a1),a2
        moveq   #0,d3                ; item number
.kf_item:
        move.l  a2,d1
        beq.s   .kf_nm
        move.l  MI_SUBITEM(a2),a0
        move.l  a0,d1
        bne.s   .kf_sub
        moveq   #$1F,d4              ; NOSUB
        move.b  MI_COMMAND(a2),d1
        and.b   #$5F,d1
        cmp.b   d1,d0
        beq.s   .kf_hit
        bra.s   .kf_ni
.kf_sub:
        moveq   #0,d4                ; sub-item number
.kf_sl:
        move.b  MI_COMMAND(a0),d1
        and.b   #$5F,d1
        cmp.b   d1,d0
        beq.s   .kf_hit
        addq.w  #1,d4
        move.l  MI_NEXTITEM(a0),a0
        move.l  a0,d1
        bne.s   .kf_sl
.kf_ni:
        addq.w  #1,d3
        move.l  MI_NEXTITEM(a2),a2
        bra.s   .kf_item
.kf_nm:
        addq.w  #1,d2
        move.l  MU_NEXTMENU(a1),a1
        bra.s   .kf_menu
.kf_hit:
        moveq   #0,d0
        move.w  d4,d0                ; sub-item << 11 | item << 5 | menu
        lsl.w   #6,d0
        or.w    d3,d0
        lsl.w   #5,d0
        or.w    d2,d0
        bra.s   .kf_ret
.kf_no:
        moveq   #-1,d0
.kf_ret:
        movem.l (sp)+,d1-d4/a0-a2
        rts

; mn_keypick(a5, d4.w = menu code, d5.w = qualifier): input task - right Amiga shortcut. Menu, item
; and sub-item enabled: mn_pick, then MENUPICK with the code to the active window; otherwise MENUPICK MENUNULL.
; Nothing if the window has lost its menu strip or if a menu is open. Preserves d2-d7/a2-a5.
mn_keypick:
        move.l  IB_ACTIVEWINDOW(a5),d0
        beq     .kp_ret
        tst.l   IB_MENUWIN(a5)
        bne     .kp_ret
        movem.l d2-d4/a3,-(sp)
        move.l  d0,a3
        move.w  d5,IB_QUAL(a5)       ; the messages of the shortcut carry the key's qualifier (§5 step 7)
        move.l  #MENUVERIFY,d0       ; MENUHOT: MENUCANCEL means no selection (intuition-input-menus §3.11)
        moveq   #MENUHOT,d1
        jsr     it_verify
        cmp.l   #MENUCANCEL,d0
        beq     .kp_null
        move.l  WD_MENUSTRIP(a3),d0
        beq.s   .kp_out
        move.l  d0,a0                ; working flags reset as for an opening, then the code chosen (§3.11)
        move.w  #MENUTOGGLED|HIGHITEM|ISDRAWN,d0
        move.w  #MENUTOGGLED|HIGHITEM,d1
        move.w  #MIDRAWN,d2
        bsr     mn_clrflags
        move.w  #MENUNULL,IB_PICK(a5)
        move.w  d4,d0
        bsr     mn_pick
        move.w  IB_PICK(a5),d1       ; the code, or MENUNULL if it was refused
        bra.s   .kp_send
.kp_null:
        move.w  #MENUNULL,d1
.kp_send:
        move.l  #MENUPICK,d0
        move.w  WD_MOUSEX(a3),d2
        move.w  WD_MOUSEY(a3),d3
        move.w  d5,d4                ; im_Qualifier
        bsr     wn_sendkey
.kp_out:
        movem.l (sp)+,d2-d4/a3
.kp_ret:
        rts

; mn_end(a4, a5): right button released. The current code is chosen (mn_pick); layers deleted, screen repaired,
; MOUSEBUTTONS MENUUP, then MENUPICK to the window with the head of the NextSelect chain (MENUNULL if empty).
mn_end:
        move.l  IB_MENUWIN(a5),d0
        beq     .me_ret
        move.l  d0,a3
        move.w  #MENUNULL,d7
        cmp.w   #1,IB_DMRSTATE(a5)   ; DMRequest bar released in time: removed, the second click may come
        bne.s   .me_sel
        move.w  #2,IB_DMRSTATE(a5)
        bsr     mn_rmbar
        clr.l   IB_MENUWIN(a5)
        rts
.me_sel:
        bsr     mn_curcode           ; current code chosen, then MENUPICK with the head of the chain (§3.9)
        bsr     mn_pick
        move.w  IB_PICK(a5),d7
        clr.b   IB_MNDRAG(a5)
.me_close:
        bsr     mn_rmbar
        bsr     mn_menuup
        move.w  d4,d2
        sub.w   WD_LEFTEDGE(a3),d2
        move.w  d5,d3
        sub.w   WD_TOPEDGE(a3),d3
        move.l  #MENUPICK,d0
        move.w  d7,d1
        suba.l  a0,a0                ; IAddress = the button event's ie_X/ie_Y, 0 for a click without movement (§5)
        jsr     wn_sendgad
        clr.l   IB_MENUWIN(a5)       ; only now: CloseWindow waits for it, and the deletion above may have blocked
.me_ret:
        rts
