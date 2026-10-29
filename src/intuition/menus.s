; src/intuition/menus.s - intuition menus: SetMenuStrip/ClearMenuStrip, ItemAddress, OnMenu/OffMenu, PrintIText,
; IntuiTextLength, and the right-button interaction (intuition input task).
; Right button pressed over the active window that has a menu strip (and no RMBTRAP): the screen's title bar is
; covered by a simple layer carrying the menu titles; the pointer in the bar pulls down the targeted menu
; (a second simple layer under the bar, ITEMTEXT or image items); the item under the pointer is
; highlighted (inversion) if it is enabled. On release: MENUPICK to the window with the selection code (MENUNULL
; otherwise), layers deleted; layers gives the area back to the windows (backup of smart windows, REFRESHWINDOW for
; simple windows via it_refresh). Disabled items or menus are ghosted by horizontal stripes in the
; background pen.
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
; Scope: no multi-selection, no MENUVERIFY, no MutualExclude, no separate HIGHBOX/HIGHIMAGE.
; IMPLEMENTATION track ("clean"): AutoDocs intuition.library + intuition/intuition.h. NO ROM reading.

                include "exec.i"
                include "intuition.i"
                include "graphics.i"

                xdef    intuition_SetMenuStrip
                xdef    intuition_ClearMenuStrip
                xdef    intuition_ItemAddress
                xdef    intuition_OnMenu
                xdef    intuition_OffMenu
                xdef    intuition_PrintIText
                xdef    intuition_IntuiTextLength
                xdef    it_menubutton
                xdef    it_menumove
                xdef    mn_keyshort
                xdef    mn_keypick
                xdef    mn_defcheck
                xref    it_refresh
                xref    it_title
                xref    it_box
                xref    it_scrxy
                xref    wn_sendmsg
                xref    wn_sendkey
                xref    kbd_cook
                xref    intuition_DrawImage

MB_MARGIN       EQU 2                ; inner margin of the pulled-down menu (border included)
MI_COMMAND      EQU 26               ; MenuItem: shortcut character (COMMSEQ)
COMMSEQ         EQU $0004
SC_BARH_M       EQU 9                ; height of the screen's title bar (lines 0..9), as in screens.s

; SetMenuStrip(window a0, menu a1) -> d0 = TRUE. ClearMenuStrip(window a0).
intuition_SetMenuStrip:
        move.l  a1,WD_MENUSTRIP(a0)
        moveq   #1,d0
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

; PrintIText(rp a0, itext a1, x d0, y d1): each IntuiText of the chain with the pens and mode it carries, its
; top-left corner at (x + LeftEdge, y + TopEdge). Single 8x8 font (ITextFont ignored).
intuition_PrintIText:
        movem.l d2-d3/a2-a3/a6,-(sp)
        move.b  rp_FgPen(a0),-(sp)   ; pens and mode left intact, as in 1.3 (probed: tests/itextstate.s)
        move.b  rp_BgPen(a0),-(sp)
        move.b  rp_DrawMode(a0),-(sp)
        move.l  a0,a2
        move.l  a1,a3
        move.w  d0,d2
        move.w  d1,d3
        move.l  IB_GFXBASE(a6),a6
.pt_lp:
        move.l  a3,d0
        beq.s   .pt_ret
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
        move.l  a2,a1
        move.w  d2,d0
        add.w   IT_LEFTEDGE(a3),d0
        move.w  d3,d1
        add.w   IT_TOPEDGE(a3),d1
        addq.w  #GFX_FONTBASE,d1
        jsr     LVO_MOVE(a6)
        move.l  IT_ITEXT(a3),a0
        bsr.s   mn_strlen
        move.l  a2,a1
        jsr     LVO_TEXT(a6)
        move.l  IT_NEXTTEXT(a3),a3
        bra.s   .pt_lp
.pt_ret:
        move.b  (sp)+,rp_DrawMode(a2)
        move.b  (sp)+,rp_BgPen(a2)
        move.b  (sp)+,rp_FgPen(a2)
        movem.l (sp)+,d2-d3/a2-a3/a6
        rts

; IntuiTextLength(itext a0) -> d0 = width in pixels of its text (8x8 font).
intuition_IntuiTextLength:
        move.l  IT_ITEXT(a0),a0
        bsr.s   mn_strlen
        lsl.l   #3,d0
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
        beq.s   .mb_ret
        move.l  d0,a3
        cmp.l   WD_WSCREEN(a3),a4
        bne.s   .mb_ret
        tst.l   WD_MENUSTRIP(a3)
        beq.s   .mb_ret
        btst    #0,WD_FLAGS+1(a3)    ; RMBTRAP: the right button belongs to the application
        bne.s   .mb_ret
        move.l  WD_FIRSTREQUEST(a3),d0   ; requester without NOISYREQ: no menus (spec intuition-requesters-v34 §3.2)
        beq.s   .mb_menus
        move.l  d0,a0
        btst    #2,RQ_FLAGS+1(a0)    ; NOISYREQ
        beq.s   .mb_ret
.mb_menus:
        clr.l   IB_MENUBOX(a5)
        clr.l   IB_MENUCUR(a5)
        clr.l   IB_ITEMCUR(a5)
        clr.l   IB_ITEMHIT(a5)
        clr.l   IB_SUBBOX(a5)
        clr.l   IB_SUBITEM(a5)
        clr.l   IB_SUBCUR(a5)
        lea     SC_LAYERINFO(a4),a0
        lea     SC_BITMAP(a4),a1
        moveq   #0,d0
        moveq   #0,d1
        move.w  SC_WIDTH(a4),d2
        subq.w  #1,d2
        moveq   #SC_BARH_M,d3
        moveq   #IL_SIMPLE,d4
        suba.l  a2,a2
        move.l  IB_LAYERSBASE(a5),a6
        jsr     LVO_CREATEUPFRONTLAYER(a6)
        move.l  d0,IB_MENUBAR(a5)
        beq.s   .mb_ret
        move.l  a3,IB_MENUWIN(a5)
        bsr     mn_drawbar
        st      IB_TRACK(a5)
        move.w  PTR_X,d4
        move.w  PTR_Y,d5
        bra     it_menumove
.mb_ret:
        rts

; mn_drawbar(a3 = window, a4 = screen, a5): background in pen BlockPen, menu titles in pen DetailPen at their
; LeftEdge; a disabled menu is ghosted.
mn_drawbar:
        movem.l d2-d7/a2,-(sp)
        move.l  IB_MENUBAR(a5),a2
        move.l  IL_RP(a2),a2         ; a2 = RastPort of the bar
        move.l  IB_GFXBASE(a5),a6
        move.l  a2,a1
        moveq   #0,d0
        move.b  SC_BLOCKPEN(a4),d0
        jsr     LVO_SETAPEN(a6)
        move.l  a2,a1
        moveq   #0,d0
        moveq   #0,d1
        move.w  SC_WIDTH(a4),d2
        subq.w  #1,d2
        moveq   #SC_BARH_M,d3
        jsr     LVO_RECTFILL(a6)
        move.l  WD_MENUSTRIP(a3),d7
.db_lp:
        tst.l   d7
        beq.s   .db_ret
        move.l  d7,a0
        moveq   #0,d0
        move.b  SC_DETAILPEN(a4),d0
        moveq   #0,d1
        move.b  SC_BLOCKPEN(a4),d1
        move.w  MU_WIDTH(a0),d2
        move.w  MU_LEFTEDGE(a0),d3
        addq.w  #4,d3
        move.l  MU_MENUNAME(a0),a0
        move.l  a2,a1
        jsr     it_title
        move.l  d7,a0
        btst    #0,MU_FLAGS+1(a0)    ; MENUENABLED
        bne.s   .db_nx
        move.w  MU_LEFTEDGE(a0),d0
        moveq   #0,d1
        move.w  d0,d2
        add.w   MU_WIDTH(a0),d2
        subq.w  #1,d2
        moveq   #SC_BARH_M,d3
        move.l  a2,a1
        bsr     mn_ghost
.db_nx:
        move.l  d7,a0
        move.l  MU_NEXTMENU(a0),d7
        bra.s   .db_lp
.db_ret:
        movem.l (sp)+,d2-d7/a2
        rts

; mn_ghost(a1 = RastPort, d0..d3 = x0,y0,x1,y1, a4 = screen, a5): horizontal stripes (every other line) in pen
; BlockPen over the rectangle (one line per RectFill: few calls). Clobbers d0-d3/a0/a1/a6.
mn_ghost:
        movem.l d4-d7/a2,-(sp)
        move.l  a1,a2
        movem.w d0-d3,-(sp)
        movem.w (sp)+,d4-d7
        move.l  IB_GFXBASE(a5),a6
        move.l  a2,a1
        moveq   #JAM1,d0
        jsr     LVO_SETDRMD(a6)
        move.l  a2,a1
        moveq   #0,d0
        move.b  SC_BLOCKPEN(a4),d0
        jsr     LVO_SETAPEN(a6)
        addq.w  #1,d5                ; odd lines of the rectangle
.gh_lp:
        cmp.w   d7,d5
        bgt.s   .gh_ret
        move.l  a2,a1
        move.w  d4,d0
        move.w  d5,d1
        move.w  d6,d2
        move.w  d5,d3
        jsr     LVO_RECTFILL(a6)
        addq.w  #2,d5
        bra.s   .gh_lp
.gh_ret:
        movem.l (sp)+,d4-d7/a2
        rts

; it_menumove(a5, d4/d5 = pointer): pointer in the bar -> the targeted menu is pulled down (no item selected);
; in the pulled-down menu -> the targeted item is highlighted; elsewhere -> no item.
it_menumove:
        tst.l   IB_MENUWIN(a5)
        beq     .mm_ret
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
        cmp.w   #SC_BARH_M,d5
        bgt.s   .mm_items
        move.l  WD_MENUSTRIP(a3),a2  ; menu under the pointer
        moveq   #0,d6
.mm_find:
        move.l  a2,d0
        beq.s   .mm_none
        move.w  d4,d0
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
        move.l  a2,IB_MENUCUR(a5)
        move.w  d6,IB_MENUNUM(a5)
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
        subq.w  #MB_MARGIN,d2
        move.w  d5,d3
        sub.w   IB_BOX+2(a5),d3
        subq.w  #MB_MARGIN,d3
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
        bra.s   mn_hilite
.li_ret:
        rts

; mn_hilite(a5): inverts the rectangle of the current item in the item box; mn_hlsub(a5): that of the
; current sub-item in the sub-item box. mn_hlrect(a0 = item, a1 = layer, d0/d1 = origin of the
; items in the layer): HIGHNONE -> nothing. All clobber d0-d3/a0/a1/a6.
mn_hilite:
        move.l  IB_ITEMCUR(a5),a0
        move.l  IB_MENUBOX(a5),a1
        moveq   #MB_MARGIN,d0
        moveq   #MB_MARGIN,d1
        bra.s   mn_hlrect
mn_hlsub:
        move.l  IB_SUBCUR(a5),a0
        move.l  IB_SUBBOX(a5),a1
        move.w  IB_SUBOX(a5),d0
        move.w  IB_SUBOY(a5),d1
mn_hlrect:
        move.w  MI_FLAGS(a0),d2
        and.w   #HIGHFLAGS,d2
        cmp.w   #HIGHNONE,d2
        beq.s   .hl_ret
        movem.l d4-d5/a2,-(sp)
        move.l  a0,a2
        move.w  d0,d4
        move.w  d1,d5
        move.l  IB_GFXBASE(a5),a6
        move.l  IL_RP(a1),a1
        move.l  a1,-(sp)
        moveq   #COMPLEMENT,d0
        jsr     LVO_SETDRMD(a6)
        move.l  (sp)+,a1
        move.w  d4,d0
        add.w   MI_LEFTEDGE(a2),d0
        move.w  d5,d1
        add.w   MI_TOPEDGE(a2),d1
        move.w  d0,d2
        add.w   MI_WIDTH(a2),d2
        subq.w  #1,d2
        move.w  d1,d3
        add.w   MI_HEIGHT(a2),d3
        subq.w  #1,d3
        jsr     LVO_RECTFILL(a6)
        movem.l (sp)+,d4-d5/a2
.hl_ret:
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
        move.l  d0,a3
        moveq   #0,d6                ; d6/d7 = extent of the items (right, bottom)
        moveq   #0,d7
.ob_ext:
        move.w  MI_LEFTEDGE(a3),d0
        add.w   MI_WIDTH(a3),d0
        cmp.w   d6,d0
        ble.s   .ob_e1
        move.w  d0,d6
.ob_e1:
        move.w  MI_TOPEDGE(a3),d0
        add.w   MI_HEIGHT(a3),d0
        cmp.w   d7,d0
        ble.s   .ob_e2
        move.w  d0,d7
.ob_e2:
        move.l  MI_NEXTITEM(a3),d0
        move.l  d0,a3
        bne.s   .ob_ext
        add.w   #2*MB_MARGIN-1,d6    ; d6/d7 = width / height - 1
        add.w   #2*MB_MARGIN-1,d7
        move.w  MU_LEFTEDGE(a2),d0
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
        moveq   #SC_BARH_M+1,d1
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
        moveq   #IL_SMART,d4         ; smart: the sub-item box placed on top of it leaves it intact
        lea     SC_LAYERINFO(a4),a0
        lea     SC_BITMAP(a4),a1
        move.l  a2,-(sp)
        suba.l  a2,a2
        move.l  IB_LAYERSBASE(a5),a6
        jsr     LVO_CREATEUPFRONTLAYER(a6)
        move.l  (sp)+,a2
        move.l  d0,IB_MENUBOX(a5)
        beq     .ob_ret
        move.l  d0,a3
        move.l  IL_RP(a3),a3         ; a3 = RastPort of the menu
        move.l  IB_GFXBASE(a5),a6
        move.l  a3,a1
        moveq   #JAM2,d0
        jsr     LVO_SETDRMD(a6)
        move.l  a3,a1
        moveq   #0,d0
        move.b  SC_BLOCKPEN(a4),d0
        jsr     LVO_SETAPEN(a6)
        move.l  a3,a1
        moveq   #0,d0
        moveq   #0,d1
        move.w  d6,d2
        move.w  d7,d3
        jsr     LVO_RECTFILL(a6)
        move.l  a3,a1
        moveq   #0,d0
        move.b  SC_DETAILPEN(a4),d0
        jsr     LVO_SETAPEN(a6)
        move.l  a3,a1
        moveq   #0,d0
        moveq   #0,d1
        move.w  d6,d2
        move.w  d7,d3
        jsr     it_box
        move.w  #MB_MARGIN,IB_DOX(a5)
        move.w  #MB_MARGIN,IB_DOY(a5)
        btst    #0,MU_FLAGS+1(a2)    ; disabled menu: all its items ghosted
        seq     IB_DGHOST(a5)
        move.l  MU_FIRSTITEM(a2),a2
        bsr     mn_drawitems
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
        add.w   #MB_MARGIN,d4
        add.w   MI_LEFTEDGE(a2),d4
        move.w  IB_BOX+2(a5),d5
        add.w   #MB_MARGIN,d5
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
        moveq   #SC_BARH_M+1,d7
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
        moveq   #IL_SIMPLE,d4
        lea     SC_LAYERINFO(a4),a0
        lea     SC_BITMAP(a4),a1
        move.l  a2,-(sp)
        suba.l  a2,a2
        move.l  IB_LAYERSBASE(a5),a6
        jsr     LVO_CREATEUPFRONTLAYER(a6)
        move.l  (sp)+,a2
        move.l  d0,IB_SUBBOX(a5)
        beq     .os_ret
        move.l  a2,IB_SUBITEM(a5)
        move.w  4*4+2(sp),IB_SUBPNUM(a5)   ; input d6 (low word of the 5th long of the movem)
        clr.l   IB_SUBCUR(a5)
        move.l  d0,a3
        move.l  IL_RP(a3),a3         ; a3 = RastPort of the box
        move.l  IB_GFXBASE(a5),a6
        move.l  a3,a1
        moveq   #JAM2,d0
        jsr     LVO_SETDRMD(a6)
        move.l  a3,a1
        moveq   #0,d0
        move.b  SC_BLOCKPEN(a4),d0
        jsr     LVO_SETAPEN(a6)
        move.l  a3,a1
        moveq   #0,d0
        moveq   #0,d1
        move.w  d6,d2
        move.w  d7,d3
        jsr     LVO_RECTFILL(a6)
        move.l  a3,a1
        moveq   #0,d0
        move.b  SC_DETAILPEN(a4),d0
        jsr     LVO_SETAPEN(a6)
        move.l  a3,a1
        moveq   #0,d0
        moveq   #0,d1
        move.w  d6,d2
        move.w  d7,d3
        jsr     it_box
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
        moveq   #0,d0
        move.b  SC_DETAILPEN(a4),d0
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
        bsr     it_refresh
        move.l  (sp)+,a2
.cb_ret:
        rts

; mn_select(a0 = chosen item or sub-item): NextSelect := MENUNULL; CHECKIT: CHECKED set, or toggled with
; MENUTOGGLE. Preserves everything.
mn_select:
        move.w  #MENUNULL,MI_NEXTSELECT(a0)
        btst    #0,MI_FLAGS+1(a0)    ; CHECKIT
        beq.s   .sl_ret
        btst    #3,MI_FLAGS+1(a0)    ; MENUTOGGLE
        beq.s   .sl_set
        bchg    #0,MI_FLAGS(a0)      ; CHECKED ($100)
        rts
.sl_set:
        bset    #0,MI_FLAGS(a0)
.sl_ret:
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
; and sub-item enabled: mn_select, then MENUPICK with the code to the active window; otherwise MENUPICK MENUNULL.
; Nothing if the window has lost its menu strip or if a menu is open. Preserves d2-d7/a2-a5.
mn_keypick:
        move.l  IB_ACTIVEWINDOW(a5),d0
        beq     .kp_ret
        tst.l   IB_MENUWIN(a5)
        bne     .kp_ret
        movem.l d2-d4/a3,-(sp)
        move.l  d0,a3
        move.l  WD_MENUSTRIP(a3),d0
        beq.s   .kp_out
        move.l  d0,a0
        move.w  d4,d1                ; menu
        and.w   #$1F,d1
        bsr.s   .kp_walk
        beq.s   .kp_null
        btst    #0,MU_FLAGS+1(a0)    ; MENUENABLED
        beq.s   .kp_null
        move.l  MU_FIRSTITEM(a0),d0
        beq.s   .kp_null
        move.l  d0,a0
        move.w  d4,d1                ; item
        lsr.w   #5,d1
        and.w   #$3F,d1
        bsr.s   .kp_walk
        beq.s   .kp_null
        btst    #4,MI_FLAGS+1(a0)    ; ITEMENABLED
        beq.s   .kp_null
        move.w  d4,d1                ; sub-item
        moveq   #11,d0
        lsr.w   d0,d1
        cmp.w   #$1F,d1
        beq.s   .kp_ok
        move.l  MI_SUBITEM(a0),d0
        beq.s   .kp_null
        move.l  d0,a0
        bsr.s   .kp_walk
        beq.s   .kp_null
        btst    #4,MI_FLAGS+1(a0)
        beq.s   .kp_null
.kp_ok:
        bsr     mn_select
        move.w  d4,d1
        bra.s   .kp_send
.kp_null:
        move.w  #MENUNULL,d1
.kp_send:
        move.l  #MENUPICK,d0
        moveq   #0,d2
        moveq   #0,d3
        move.w  d5,d4                ; im_Qualifier
        bsr     wn_sendkey
.kp_out:
        movem.l (sp)+,d2-d4/a3
.kp_ret:
        rts
.kp_walk:                            ; a0 = first link, d1 = rank -> a0 = link (Z = 1: list too short)
        bra.s   .kw_e
.kw_l:
        move.l  (a0),d0              ; NextMenu / NextItem (offset 0)
        beq.s   .kw_r
        move.l  d0,a0
.kw_e:
        dbra    d1,.kw_l
        moveq   #1,d0                ; Z = 0
.kw_r:
        rts

; mn_end(a4, a5): right button released. Selection code (enabled highlighted item, otherwise MENUNULL); a
; CHECKIT item is checked (MENUTOGGLE: toggled). Layers deleted, screen repaired, then MENUPICK to the window.
mn_end:
        move.l  IB_MENUWIN(a5),d0
        beq     .me_ret
        move.l  d0,a3
        move.w  #MENUNULL,d7
        move.l  IB_SUBCUR(a5),d0
        beq.s   .me_item
        move.l  d0,a0
        bsr     mn_select
        move.w  IB_SUBNUM(a5),d7     ; sub-item << 11 | item << 5 | menu
        lsl.w   #6,d7
        or.w    IB_SUBPNUM(a5),d7
        lsl.w   #5,d7
        or.w    IB_MENUNUM(a5),d7
        bra.s   .me_close
.me_item:
        move.l  IB_ITEMCUR(a5),d0
        beq.s   .me_close
        move.l  d0,a0
        tst.l   MI_SUBITEM(a0)       ; item with sub-items, none chosen: MENUNULL
        bne.s   .me_close
        bsr     mn_select
        move.w  IB_ITEMNUM(a5),d7
        lsl.w   #5,d7
        or.w    IB_MENUNUM(a5),d7
        or.w    #$1F<<11,d7          ; NOSUB
.me_close:
        bsr     mn_closebox
        clr.l   IB_MENUCUR(a5)
        clr.l   IB_MENUWIN(a5)
        clr.b   IB_TRACK(a5)
        move.l  IB_MENUBAR(a5),a1
        clr.l   IB_MENUBAR(a5)
        suba.l  a0,a0
        move.l  IB_LAYERSBASE(a5),a6
        jsr     LVO_DELETELAYER(a6)
        bsr     it_refresh
        move.w  d4,d2
        sub.w   WD_LEFTEDGE(a3),d2
        move.w  d5,d3
        sub.w   WD_TOPEDGE(a3),d3
        move.l  #MENUPICK,d0
        move.w  d7,d1
        bra     wn_sendmsg
.me_ret:
        rts
