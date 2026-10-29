; src/intuition/screens.s - intuition.library screens and windows: OpenScreen/CloseScreen, OpenWorkBench,
; GetScreenData, OpenWindow/CloseWindow, WindowToFront/WindowToBack, MoveWindow, SizeWindow, WindowLimits,
; BeginRefresh/EndRefresh, menus (SetMenuStrip/ClearMenuStrip/ItemAddress/OnMenu/OffMenu).
; A screen = struct Screen (V34) + BitMap in chip RAM + ColorMap + its Layer_Info (sc_LayerInfo); the front screen
; is displayed through the IntuitionBase View (ib_ViewLord: MakeVPort/MrgCop/LoadView). The screen's title bar is
; a simple "backdrop" layer (sc_BarLayer). Each window is a layers.library layer (simple, smart or
; super depending on its flags; backdrop for BACKDROP): its RPort is the layer's, the overlapping and the
; backup of smart windows are handled by layers. After an operation on the layers, it_refresh redraws the
; damaged borders and sends REFRESHWINDOW to the windows that asked for it (otherwise the damage is cleared).
; The screen's window list follows the order of the layers (it_relist). The mouse buttons are handled by
; an input task (it_intask): system gadgets (close, depth, drag, size) and menus.
; Decoration (title bars, drawn gadgets): rendering specific to this project, in the colors of the 1.3 preferences.
; IMPLEMENTATION track ("clean"): AutoDocs intuition.library + public NDK includes (screens.h, intuition.h).
; NO ROM reading.

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
                xdef    intuition_RemakeDisplay
                xdef    intuition_ScreenToFront
                xdef    intuition_ScreenToBack
                xdef    it_event
                xdef    it_refresh           ; menus.s
                xdef    it_title
                xdef    it_box
                xdef    it_scrxy
                xdef    wn_sendmsg
                xdef    wn_sendkey
                xdef    wn_sendgad
                xdef    wn_sysgads
                xref    gad_drawall          ; gadgets.s
                xref    gad_propinit
                xref    prop_track
                xref    gad_rect
                xref    gad_down
                xref    gad_up
                xref    str_key
                xref    str_clickout
                xdef    it_keyin
                xdef    it_tickin
                xdef    it_diskin
                xdef    it_unclip
                xref    rq_closeall          ; request.s
                xref    rq_move
                xref    rq_restack
                xdef    it_reclip
                xdef    intuition_ModifyIDCMP
                xdef    intuition_ShowTitle
                xdef    intuition_ViewPortAddress
                xref    gad_forget
                xref    it_menubutton        ; menus.s: right button
                xref    it_menumove
                xref    mn_keyshort          ; menus.s: right Amiga shortcut (handler)
                xref    mn_keypick           ; menus.s: right Amiga shortcut (input task)
                xref    mn_defcheck          ; menus.s: internal menu check mark
                xdef    it_startinput
                xdef    intuition_ReportMouse
                xdef    intuition_SizeWindow
                xdef    intuition_SetWindowTitles
                xdef    intuition_DisplayBeep
                xdef    intuition_WindowLimits
                xdef    intuition_WindowToFront
                xdef    intuition_WindowToBack
                xdef    intuition_MoveWindow
                xdef    intuition_BeginRefresh
                xdef    intuition_EndRefresh

; private extension behind the struct Screen (same allocation)
SCX_RASINFO     EQU SC_SIZEOF        ; struct RasInfo (12)
SCX_COLORMAP    EQU SCX_RASINFO+ri_SIZEOF   ; struct ColorMap (8)
SCX_COLORTAB    EQU SCX_COLORMAP+GCM_SIZEOF ; 32 colors
SCX_PLANESIZE   EQU SCX_COLORTAB+64  ; size of a plane allocated here (0: BitMap supplied by the caller)
SCX_SIZE        EQU SCX_PLANESIZE+4
SC_MAXCOLORS    EQU 32
SC_BARH         EQU 9                ; BarHeight: the title bar covers lines 0..9
; window: struct Window + IDCMP messages (same allocation); RastPort and layer come from layers.library
WDX_IMSG        EQU WD_SIZE          ; REFRESHWINDOW IntuiMessage (reused once replied)
WDX_EMSG        EQU WDX_IMSG+IM_SIZEOF  ; event IntuiMessages (buttons, close), reused once replied
WDX_NEMSG       EQU 4
WDX_BLAYER      EQU WDX_EMSG+WDX_NEMSG*IM_SIZEOF ; GIMMEZEROZERO: border layer (WD_WLAYER = the interior) | 0
WDX_CLIPSAVE    EQU WDX_BLAYER+4     ; application ClipRegion removed during an intuition drawing
WDX_CLIPNEST    EQU WDX_CLIPSAVE+4   ; WORD: nesting of it_unclip
WDX_SIZE        EQU WDX_CLIPNEST+2
WD_TBARH        EQU 10               ; height of a window's title bar (BorderTop)

; OpenScreen(newscreen a0) -> d0 = Screen | 0. Allocates the struct, the BitMap (cleared chip planes, except
; CUSTOMBITMAP), the default palette (32 colors, including those of the pointer), draws the title bar (except
; SCREENQUIET), places the screen at the head of the list and displays it.
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
        move.w  NS_WIDTH(a2),d4      ; d4 = width (<= 0: 320 or 640 depending on the mode)
        bgt.s   .os_wok
        move.w  #320,d4
        tst.w   NS_VIEWMODES(a2)
        bpl.s   .os_wok
        move.w  #640,d4
.os_wok:
        move.w  NS_HEIGHT(a2),d5     ; d5 = height (<= 0: 256, PAL)
        bgt.s   .os_hok
        move.w  #256,d5
.os_hok:
        move.w  d4,SC_WIDTH(a3)
        move.w  d5,SC_HEIGHT(a3)
        move.w  NS_DEPTH(a2),d6      ; d6 = depth, brought into 1..6
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
        mulu    d5,d7                ; d7 = size of a plane
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
        ; palette: 32 colors whatever the depth (colors 17-19 are those of the pointer)
        move.w  #SC_MAXCOLORS,SCX_COLORMAP+cm_Count(a3)
        lea     SCX_COLORTAB(a3),a0
        move.l  a0,SCX_COLORMAP+cm_ColorTable(a3)
        lea     sc_palette(pc),a1
        moveq   #SC_MAXCOLORS-1,d0
.os_pal:
        move.w  (a1)+,(a0)+
        dbra    d0,.os_pal
        moveq   #SCREENTYPE,d0       ; Workbench screen: colors 0-3 and 17-19 from the Preferences
        and.w   NS_TYPE(a2),d0
        cmp.w   #WBENCHSCREEN,d0
        bne.s   .os_ras
        lea     SCX_COLORTAB(a3),a0
        lea     IB_PREFS+PF_COLOR0(a5),a1
        move.l  (a1)+,(a0)+
        move.l  (a1)+,(a0)+
        lea     SCX_COLORTAB+17*2(a3),a0
        lea     IB_PREFS+PF_COLOR17(a5),a1
        move.l  (a1)+,(a0)+
        move.w  (a1)+,(a0)+
.os_ras:
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
        move.l  a2,-(sp)             ; title bar: simple backdrop layer, behind the windows
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

; sc_free(a3 = Screen, a5 = IntuitionBase): frees the copper fragment, the planes allocated by OpenScreen and the
; struct. a6 on exit = SysBase. Clobbers d0/d1/a0/a1/a4/d3.
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
        beq.s   .sf_planes           ; contiguous planes in the array: the first empty one terminates
        move.l  d1,a1
        move.l  SCX_PLANESIZE(a3),d0
        jsr     LVO_FREEMEM(a6)
        dbra    d3,.sf_lp
.sf_planes:
        move.l  a3,a1
        move.l  #SCX_SIZE,d0
        jmp     LVO_FREEMEM(a6)

; wn_scrtitle(a3 = window that became active, a5 = IntuitionBase): its screen's bar shows wd_ScreenTitle, or the
; screen's default title if it is null; always redrawn (the same buffer may have changed contents). Preserves
; everything.
wn_scrtitle:
        movem.l d0-d3/a0-a1/a3/a6,-(sp)
        move.l  WD_SCREENTITLE(a3),d1
        move.l  WD_WSCREEN(a3),d0
        beq.s   .st_ret
        move.l  d0,a3
        tst.l   d1
        bne.s   .st_set
        move.l  SC_DEFAULTTITLE(a3),d1
.st_set:
        move.l  d1,SC_TITLE(a3)
        bsr     sc_drawbar
.st_ret:
        movem.l (sp)+,d0-d3/a0-a1/a3/a6
        rts

; intuition_SetWindowTitles(window a0, title a1, screen title a2, a6 = IntuitionBase): -1 leaves the title
; unchanged. New window title: border redrawn. New screen title: shown immediately if the window
; is active, or if none is.
intuition_SetWindowTitles:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  a6,a5
        move.l  a0,a3
        cmp.l   #-1,a1
        beq.s   .swt_scr
        move.l  a1,WD_TITLE(a3)
        move.l  a2,-(sp)
        bsr     wn_border
        move.l  (sp)+,a2
.swt_scr:
        cmp.l   #-1,a2
        beq.s   .swt_ret
        move.l  a2,WD_SCREENTITLE(a3)
        move.l  IB_ACTIVEWINDOW(a5),d0
        beq.s   .swt_show
        cmp.l   d0,a3
        bne.s   .swt_ret
.swt_show:
        bsr     wn_scrtitle
.swt_ret:
        movem.l (sp)+,d2-d7/a2-a6
        rts

; intuition_DisplayBeep(screen a0 | 0 = front screen, a6 = IntuitionBase): 1.x visual signal, color 0 of the
; screen complemented for BEEP_FRAMES frames then restored (busy wait on the beam position).
BEEP_FRAMES     EQU 6
intuition_DisplayBeep:
        movem.l d3/a2/a5,-(sp)
        move.l  a6,a5
        move.l  a0,d0
        bne.s   .bp_scr
        move.l  IB_FIRSTSCREEN(a5),d0
        beq.s   .bp_ret
.bp_scr:
        move.l  d0,a2
        move.l  SCX_COLORMAP+cm_ColorTable(a2),a0
        eor.w   #$0FFF,(a0)
        bsr     it_remake
        moveq   #BEEP_FRAMES-1,d3
.bp_frame:
        move.l  $DFF004,d0           ; VPOSR/VHPOSR: line = bits 16..8
        lsr.l   #8,d0
        and.w   #$1FF,d0
        cmp.w   #200,d0
        blo.s   .bp_frame
.bp_top:
        move.l  $DFF004,d0
        lsr.l   #8,d0
        and.w   #$1FF,d0
        cmp.w   #200,d0
        bhs.s   .bp_top
        dbra    d3,.bp_frame
        move.l  SCX_COLORMAP+cm_ColorTable(a2),a0
        eor.w   #$0FFF,(a0)          ; second complement = original color (it_remake does not keep d2/d3)
        bsr     it_remake
.bp_ret:
        movem.l (sp)+,d3/a2/a5
        rts

; sc_drawbar(a3 = Screen, a5 = IntuitionBase): title bar (lines 0..BarHeight) in pen BlockPen, title in
; pen DetailPen, screen depth gadgets on the right (window pictograms, spec intuition-frame-v34 §6).
; SCREENQUIET screen (no bar layer): nothing, never a bar. Clobbers d0-d3/a0/a1/a6.
sc_drawbar:
        tst.l   SC_BARLAYER(a3)
        beq.s   .db_quiet
        move.l  IB_GFXBASE(a5),a6
        bsr.s   sc_barrp
        moveq   #0,d0
        move.b  SC_BLOCKPEN(a3),d0
        jsr     LVO_SETAPEN(a6)
        bsr.s   sc_barrp
        moveq   #0,d0
        moveq   #0,d1
        move.w  SC_WIDTH(a3),d2
        subq.w  #1,d2
        moveq   #SC_BARH,d3
        jsr     LVO_RECTFILL(a6)
        move.l  a3,a0
        bsr     sc_geo
        move.w  SC_WIDTH(a3),d2      ; width available for the title: up to the depth gadgets
        sub.w   GEO_TX1(a0),d2
        subq.w  #5,d2
        bsr.s   sc_barrp
        moveq   #0,d0
        move.b  SC_DETAILPEN(a3),d0
        moveq   #0,d1
        move.b  SC_BLOCKPEN(a3),d1
        move.l  SC_TITLE(a3),a0
        moveq   #5,d3                ; x = BarHBorder
        bsr     it_title
        movem.l a2/a4,-(sp)
        bsr.s   sc_barrp
        move.l  a1,a4
        move.l  a3,a0
        bsr     sc_geo
        move.l  a0,a2
        move.w  SC_WIDTH(a3),d0
        bsr     wn_depthpics
        movem.l (sp)+,a2/a4
.db_quiet:
        rts

; sc_barrp(a3 = Screen with a bar layer) -> a1 = RastPort of this layer (overlapping by the windows).
; Preserves everything else.
sc_barrp:
        move.l  SC_BARLAYER(a3),a1
        move.l  IL_RP(a1),a1
        rts

; it_title(a1 = RastPort, a0 = C title | 0, d0 = text pen, d1 = background pen, d2.w = max width in pixels,
; d3.w = x, a6 = GfxBase): writes the title in JAM2 on baseline 7 (10-line bar). Clobbers d0-d3/a0.
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
        moveq   #0,d0                ; d0 = length, bounded to the available width
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

; it_box(a1 = RastPort, d0..d3 = x0,y0,x1,y1, a6 = GfxBase): 1-pixel frame in pen A. Clobbers d0-d3/a0.
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

; RemakeDisplay() / RethinkDisplay() (a6 = IntuitionBase): copper list rebuilt from the structures of the front
; screen (a program that changed BitMap.Depth or the colors by hand is thus displayed as is).
intuition_RemakeDisplay:
        move.l  a5,-(sp)
        move.l  a6,a5
        bsr.s   it_remake
        move.l  (sp)+,a5
        rts

; it_remake(a5 = IntuitionBase): displays the front screen (its ViewPort alone in ib_ViewLord), or turns off
; the display if there is no screen left. Preserves everything but d0/d1/a0/a1.
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

; ScreenToFront(screen a0) / ScreenToBack(screen a0): the screen moves to the head / tail of the screen list; only
; the front screen is displayed (it_remake). Nothing if the screen is not in the list.
intuition_ScreenToFront:
        moveq   #0,d1
        bra.s   sc_depth
intuition_ScreenToBack:
        moveq   #1,d1
sc_depth:
        movem.l a2/a5-a6,-(sp)
        move.l  a6,a5
        move.l  a0,a2
        move.l  ($4).w,a6
        jsr     LVO_FORBID(a6)
        lea     IB_FIRSTSCREEN(a5),a0 ; previous link (SC_NEXTSCREEN at offset 0)
.sd_find:
        move.l  (a0),d0
        beq.s   .sd_none
        cmp.l   d0,a2
        beq.s   .sd_hit
        move.l  d0,a0
        bra.s   .sd_find
.sd_hit:
        move.l  SC_NEXTSCREEN(a2),(a0)
        tst.w   d1
        bne.s   .sd_back
        move.l  IB_FIRSTSCREEN(a5),SC_NEXTSCREEN(a2)
        move.l  a2,IB_FIRSTSCREEN(a5)
        bra.s   .sd_done
.sd_back:
        clr.l   SC_NEXTSCREEN(a2)
        lea     IB_FIRSTSCREEN(a5),a0
.sd_tail:
        move.l  (a0),d0
        beq.s   .sd_put
        move.l  d0,a0
        bra.s   .sd_tail
.sd_put:
        move.l  a2,(a0)
.sd_done:
        jsr     LVO_PERMIT(a6)
        bsr     it_remake
        bra.s   .sd_ret
.sd_none:
        jsr     LVO_PERMIT(a6)
.sd_ret:
        movem.l (sp)+,a2/a5-a6
        rts

; CloseScreen(screen a0) -> d0 = TRUE. Removes the screen from the list, frees its resources and redisplays the next
; screen. The windows still open on it are not closed (AutoDoc contract: the caller closes them beforehand).
intuition_CloseScreen:
        movem.l d3/a3-a5,-(sp)
        move.l  a6,a5
        move.l  a0,a3
        move.l  a0,d0
        beq.s   .cs_ret
        move.l  ($4).w,a6
        jsr     LVO_FORBID(a6)
        lea     IB_FIRSTSCREEN(a5),a0 ; a0 = previous link (SC_NEXTSCREEN at offset 0)
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
        bsr     it_remake            ; redisplay first: this screen's fragment is no longer used
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

; OpenWorkBench() -> d0 = Workbench Screen: opens it if it is not open (640x256, 2 planes, HIRES).
intuition_OpenWorkBench:
        move.l  IB_WBSCREEN(a6),d0
        bne.s   .ow_ret
        lea     sc_wbnewscreen(pc),a0
        bsr     intuition_OpenScreen
        move.l  d0,IB_WBSCREEN(a6)
.ow_ret:
        rts

; GetScreenData(buffer a0, size d0, type d1, screen a1) -> d0 = TRUE | FALSE: copies min(size, sizeof Screen)
; bytes of the screen (type WBENCHSCREEN: the Workbench screen, opened if needed).
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

; OpenWindow(newwindow a0) -> d0 = Window | 0. Screen: nw_Screen if nw_Type = CUSTOMSCREEN, otherwise the Workbench
; (opened if needed). Position/size brought into the screen; borders according to the flags (BORDERLESS: none;
; title/system gadgets: 10-line bar; WINDOWSIZING: right border of 18, or bottom of 9 if SIZEBBOTTOM).
; RPort = own RastPort (screen BitMap, layer at the window bounds). The border is drawn, the interior
; cleared in pen 0, and the window becomes the active window.
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
        ; geometry brought into the screen
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
        sub.w   d4,d0                ; maximum width
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
        and.l   #~WINDOWACTIVE,d0    ; set only if the window is activated (ACTIVATE)
        move.l  d0,WD_FLAGS(a3)
        move.l  NW_TITLE(a2),WD_TITLE(a3)
        move.l  NW_IDCMPFLAGS(a2),WD_IDCMPFLAGS(a3)
        move.l  NW_FIRSTGADGET(a2),WD_FIRSTGADGET(a3)
        move.l  a4,WD_WSCREEN(a3)
        move.l  NW_CHECKMARK(a2),d0  ; menu check mark: the application's, else the internal one (according to HIRES)
        bne.s   .ow_ck
        jsr     mn_defcheck
.ow_ck:
        move.l  d0,WD_CHECKMARK(a3)
        move.b  NW_DETAILPEN(a2),d0  ; pens: -1 = those of the screen
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
        ; borders
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
        btst    #4,d1                ; SIZEBRIGHT as well
        beq.s   .ow_bord
.ow_szr:
        move.b  #18,WD_BORDERRIGHT(a3)
.ow_bord:
        jsr     gad_propinit         ; borders of the NewWindow's proportional gadgets
        bsr     wn_gadborders
        bsr     wn_gzz
        lea     WD_MINWIDTH(a3),a0   ; zero limits: current size (AutoDoc OpenWindow)
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
        bsr     wn_mkport            ; IDCMP port (signal of the calling task)
        tst.l   WD_USERPORT(a3)
        beq     .ow_nolayer          ; no port: failure
.ow_noport:
        ; layer: simple / smart / super according to the flags, backdrop for BACKDROP (behind the others)
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
        suba.l  a1,a1                ; a1 = optional SuperBitMap
        moveq   #IL_SMART,d4
        moveq   #$C0,d6              ; refresh type
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
        btst    #10,d5               ; GIMMEZEROZERO (except BACKDROP): the border layer is always simple,
        beq.s   .ow_type             ; the interior takes the requested refresh mode (wn_gzzlayer)
        btst    #8,d5
        bne.s   .ow_type
        moveq   #IL_SIMPLE,d4
        suba.l  a1,a1
.ow_type:
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
        btst    #2,WD_FLAGS+2(a3)    ; GIMMEZEROZERO (except BACKDROP): interior in a second layer, in front
        beq.s   .ow_one
        btst    #0,WD_FLAGS+2(a3)
        bne.s   .ow_one
        bsr     wn_gzzlayer
        bne.s   .ow_one
        move.l  IB_LAYERSBASE(a5),a6 ; failure: the border layer is given back
        suba.l  a0,a0
        move.l  WD_WLAYER(a3),a1
        jsr     LVO_DELETELAYER(a6)
        move.l  ($4).w,a6
        bsr     wn_freeport
        bra     .ow_nolayer
.ow_one:
        bsr     it_relist
        jsr     LVO_FORBID(a6)
        move.l  IB_ACTIVEWINDOW(a5),d0   ; Parent/Descendant chain: right after the active window (intuition 34.3)
        move.l  d0,WD_PARENT(a3)
        beq.s   .ow_nopar
        move.l  d0,a0
        move.l  WD_DESCENDANT(a0),d1
        move.l  d1,WD_DESCENDANT(a3)
        move.l  a3,WD_DESCENDANT(a0)
        tst.l   d1
        beq.s   .ow_nopar
        move.l  d1,a0
        move.l  a3,WD_PARENT(a0)
.ow_nopar:
        btst    #4,WD_FLAGS+2(a3)    ; ACTIVATE: only a window that asks for it becomes active
        beq.s   .ow_noact
        jsr     LVO_PERMIT(a6)
        bsr     it_setactive         ; (the new bar is redrawn with the border right after)
        bsr     wn_scrtitle
        bra.s   .ow_linked
.ow_noact:
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

; wn_gadborders(a3 = window): the application gadgets marked LEFTBORDER / RIGHTBORDER / TOPBORDER / BOTTOMBORDER
; (Activation) enlarge the corresponding border to fit in it, never shrink it (spec intuition-gzz-v34 §1):
; left >= right of the gadget, right >= width - left of the gadget, top >= bottom of the gadget, bottom >= height - top
; of the gadget. Preserves d2-d7/a2-a6.
wn_gadborders:
        movem.l d2-d3/a2,-(sp)
        move.l  WD_FIRSTGADGET(a3),a2
        lea     -8(sp),sp
.gb_lp:
        move.l  a2,d0
        beq.s   .gb_ret
        moveq   #$F0,d2
        and.b   GG_ACTIVATION+1(a2),d2
        beq.s   .gb_nx
        move.l  a2,a0
        move.l  sp,a1
        jsr     gad_rect             ; (sp) = x0, y0, x1, y1 in the window
        btst    #5,d2                ; LEFTBORDER
        beq.s   .gb_r
        move.w  4(sp),d3
        lea     WD_BORDERLEFT(a3),a0
        bsr.s   .gb_max
.gb_r:
        btst    #4,d2                ; RIGHTBORDER
        beq.s   .gb_t
        move.w  WD_WIDTH(a3),d3
        sub.w   (sp),d3
        lea     WD_BORDERRIGHT(a3),a0
        bsr.s   .gb_max
.gb_t:
        btst    #6,d2                ; TOPBORDER
        beq.s   .gb_b
        move.w  6(sp),d3
        lea     WD_BORDERTOP(a3),a0
        bsr.s   .gb_max
.gb_b:
        btst    #7,d2                ; BOTTOMBORDER
        beq.s   .gb_nx
        move.w  WD_HEIGHT(a3),d3
        sub.w   2(sp),d3
        lea     WD_BORDERBOTTOM(a3),a0
        bsr.s   .gb_max
.gb_nx:
        move.l  (a2),a2              ; gg_NextGadget
        bra.s   .gb_lp
.gb_ret:
        lea     8(sp),sp
        movem.l (sp)+,d2-d3/a2
        rts
.gb_max:                             ; byte (a0) := max((a0), d3) (d3 bounded to 0..255)
        tst.w   d3
        bmi.s   .gm_ret
        cmp.w   #255,d3
        bls.s   .gm_cmp
        move.w  #255,d3
.gm_cmp:
        moveq   #0,d0
        move.b  (a0),d0
        cmp.w   d0,d3
        bls.s   .gm_ret
        move.b  d3,(a0)
.gm_ret:
        rts

; wn_gzzlayer(a3 = window whose WD_WLAYER is the whole layer, a5) -> Z = 0 if successful: the whole layer becomes
; the border layer (WDX_BLAYER, WD_BORDERRPORT) and a layer covering the interior (window minus borders), with the
; same refresh mode, is created in front: it becomes WD_WLAYER / WD_RPORT (origin in the interior). a6 = SysBase
; on return. Preserves d2-d7/a2-a5.
wn_gzzlayer:
        movem.l d2-d5/a2,-(sp)
        move.l  WD_WLAYER(a3),a0
        move.l  a0,WDX_BLAYER(a3)
        move.l  IL_RP(a0),WD_BORDERRPORT(a3)
        moveq   #0,d5
        move.w  WD_LEFTEDGE(a3),d0
        move.b  WD_BORDERLEFT(a3),d5
        add.w   d5,d0
        move.w  WD_TOPEDGE(a3),d1
        move.b  WD_BORDERTOP(a3),d5
        add.w   d5,d1
        move.w  WD_LEFTEDGE(a3),d2
        add.w   WD_WIDTH(a3),d2
        move.b  WD_BORDERRIGHT(a3),d5
        sub.w   d5,d2
        subq.w  #1,d2
        move.w  WD_TOPEDGE(a3),d3
        add.w   WD_HEIGHT(a3),d3
        move.b  WD_BORDERBOTTOM(a3),d5
        sub.w   d5,d3
        subq.w  #1,d3
        moveq   #IL_SMART,d4
        moveq   #$C0,d5
        and.b   WD_FLAGS+3(a3),d5
        cmp.b   #$40,d5              ; SIMPLE_REFRESH
        bne.s   .gl_type
        moveq   #IL_SIMPLE,d4
.gl_type:
        suba.l  a2,a2
        move.l  WD_WSCREEN(a3),a0
        lea     SC_BITMAP(a0),a1
        lea     SC_LAYERINFO(a0),a0
        move.l  IB_LAYERSBASE(a5),a6
        jsr     LVO_CREATEUPFRONTLAYER(a6)
        move.l  ($4).w,a6
        tst.l   d0
        beq.s   .gl_fail
        move.l  d0,a0
        move.l  a0,WD_WLAYER(a3)
        move.l  a3,IL_WINDOW(a0)
        move.l  IL_RP(a0),WD_RPORT(a3)
        moveq   #1,d0
        bra.s   .gl_ret
.gl_fail:
        move.l  WDX_BLAYER(a3),WD_WLAYER(a3)   ; Z = 1
        clr.l   WDX_BLAYER(a3)
        clr.l   WD_BORDERRPORT(a3)
        moveq   #0,d0
.gl_ret:
        movem.l (sp)+,d2-d5/a2
        rts

; wn_brp(a3 = window) -> a1 = border RastPort (that of the border layer of a GIMMEZEROZERO window, otherwise the
; window's RastPort). Preserves everything else.
wn_brp:
        move.l  WD_BORDERRPORT(a3),a1
        cmpa.w  #0,a1
        bne.s   .bp_ret
        move.l  WD_RPORT(a3),a1
.bp_ret:
        rts

; wn_border(a3 = Window, a5 = IntuitionBase): full border (spec intuition-frame-v34 §2). Except BORDERLESS: left,
; right and bottom borders cleared in pen 0, outline in BlockPen (sides of BorderLeft/2 pixels at both edges,
; top and bottom lines), title bar background down to BorderTop-2, title and pattern (wn_titlebar). Then the
; application gadgets, the system gadgets on top (wn_sysgads), and the veil if the window is not active. Drawing state
; given back to the clients: JAM2, pens 1/0. Clobbers d0-d7/a0/a1/a6.
wn_border:
        bsr     it_unclip
        bsr     wn_border_nc
        bra     it_reclip
wn_border_nc:
        move.l  IB_GFXBASE(a5),a6
        btst    #3,WD_FLAGS+2(a3)    ; BORDERLESS
        bne     .df_gad
        bsr     wn_brp
        moveq   #JAM1,d0
        jsr     LVO_SETDRMD(a6)
        move.w  WD_WIDTH(a3),d4
        subq.w  #1,d4                ; d4 = W - 1
        move.w  WD_HEIGHT(a3),d5
        subq.w  #1,d5                ; d5 = H - 1
        moveq   #0,d0
        bsr     .df_pen
        moveq   #0,d6
        move.b  WD_BORDERLEFT(a3),d6 ; d6 = BorderLeft
        beq.s   .df_er
        moveq   #0,d0
        moveq   #0,d1
        move.w  d6,d2
        subq.w  #1,d2
        move.w  d5,d3
        bsr     .df_fill
.df_er:
        moveq   #0,d0
        move.b  WD_BORDERRIGHT(a3),d0
        beq.s   .df_eb
        neg.w   d0
        add.w   d4,d0
        addq.w  #1,d0
        moveq   #0,d1
        move.w  d4,d2
        move.w  d5,d3
        bsr     .df_fill
.df_eb:
        moveq   #0,d1
        move.b  WD_BORDERBOTTOM(a3),d1
        beq.s   .df_ct
        neg.w   d1
        add.w   d5,d1
        addq.w  #1,d1
        moveq   #0,d0
        move.w  d4,d2
        move.w  d5,d3
        bsr     .df_fill
.df_ct:
        moveq   #0,d0
        move.b  WD_BLOCKPEN(a3),d0
        bsr     .df_pen
        lsr.w   #1,d6                ; d6 = BorderLeft / 2
        beq.s   .df_tb
        moveq   #0,d0
        moveq   #0,d1
        move.w  d6,d2
        subq.w  #1,d2
        move.w  d5,d3
        bsr     .df_fill
        move.w  d4,d0
        sub.w   d6,d0
        addq.w  #1,d0
        moveq   #0,d1
        move.w  d4,d2
        move.w  d5,d3
        bsr     .df_fill
        move.w  d6,d0
        moveq   #0,d1
        move.w  d4,d2
        sub.w   d6,d2
        moveq   #0,d3
        bsr     .df_fill
        move.w  d6,d0
        move.w  d5,d1
        move.w  d4,d2
        sub.w   d6,d2
        move.w  d5,d3
        bsr     .df_fill
.df_tb:
        moveq   #0,d3
        move.b  WD_BORDERTOP(a3),d3
        subq.w  #2,d3                ; background down to BorderTop - 2 (the next line stays in pen 0)
        bmi.s   .df_gad
        moveq   #0,d0
        moveq   #0,d1
        move.w  d4,d2
        bsr     .df_fill
        bsr     wn_titlebar
.df_gad:
        bsr     gad_drawall          ; application gadgets, redrawn with the border
        btst    #3,WD_FLAGS+2(a3)    ; system gadgets (except BORDERLESS) at the head of the list: drawn last
        bne.s   .df_veil
        bsr     wn_sysgads
.df_veil:
        btst    #5,WD_FLAGS+2(a3)    ; WINDOWACTIVE
        bne.s   .df_rp
        bsr     wn_veil
.df_rp:
        move.l  WD_RPORT(a3),a1      ; drawing state given back to the clients: JAM2, pens 1/0
        moveq   #1,d0
        jsr     LVO_SETAPEN(a6)
        move.l  WD_RPORT(a3),a1
        moveq   #0,d0
        jsr     LVO_SETBPEN(a6)
        move.l  WD_RPORT(a3),a1
        moveq   #JAM2,d0
        jsr     LVO_SETDRMD(a6)
        rts
.df_pen:
        bsr     wn_brp
        jmp     LVO_SETAPEN(a6)
.df_fill:
        bsr     wn_brp
        jmp     LVO_RECTFILL(a6)

; --- border geometry per resolution (spec intuition-frame-v34 §3.1, §5.2): offsets in pixels; positions
; relative to the right / bottom edge read as W - value / H - value.
GEO_CX0         EQU 0                ; close gadget: x0..x1 (click)
GEO_CX1         EQU 2
GEO_BACK        EQU 4                ; back depth: W - BACK .. W - FRONT - 1
GEO_FRONT       EQU 6                ; front depth: W - FRONT .. W - FEND
GEO_FEND        EQU 8
GEO_SW          EQU 10               ; size gadget: (W - SW, H - SH) up to the corner
GEO_SH          EQU 12
GEO_TX0         EQU 14               ; start of the title with close gadget
GEO_TX1         EQU 16               ; end of the title with depth gadgets: W - TX1
GEO_PCLOSE      EQU 18               ; pictograms
GEO_PSIZE       EQU 22
GEO_PBACK       EQU 26
GEO_PFRONT      EQU 30
wn_geo_hi:
        dc.w    4,27,53,29,4,16,9,30,54
        dc.l    pic_close_h,pic_size_h,pic_back_h,pic_front_h
wn_geo_lo:
        dc.w    0,13,34,17,1,11,10,16,35
        dc.l    pic_close_l,pic_size_l,pic_back_l,pic_front_l

; wn_geo(a3 = window) -> a0 = geometry for its screen's resolution; sc_geo(a0 = screen) -> a0 same. Preserves
; everything else.
wn_geo:
        move.l  WD_WSCREEN(a3),a0
        cmpa.w  #0,a0
        beq.s   wn_geolo
sc_geo:
        tst.w   SC_VIEWPORT+vp_Modes(a0)
        bpl.s   wn_geolo
        lea     wn_geo_hi(pc),a0
        rts
wn_geolo:
        lea     wn_geo_lo(pc),a0
        rts


; wn_titlex(a3 = window) -> d2 = start, d3 = end of the title area (spec §3.1): after the close gadget if it
; exists (otherwise the screen's WBorLeft), up to before the depth gadgets (otherwise W - 1). Clobbers d0/a0.
wn_titlex:
        bsr     wn_geo
        moveq   #0,d2
        btst    #3,WD_FLAGS+3(a3)    ; WINDOWCLOSE
        beq.s   .tx_bl
        move.w  GEO_TX0(a0),d2
        bra.s   .tx_x1
.tx_bl:
        move.l  WD_WSCREEN(a3),d0
        beq.s   .tx_x1
        move.l  d0,a0
        move.b  SC_WBORLEFT(a0),d2
        bsr     wn_geo
.tx_x1:
        move.w  WD_WIDTH(a3),d3
        btst    #2,WD_FLAGS+3(a3)    ; WINDOWDEPTH
        bne.s   .tx_dp
        subq.w  #1,d3
        rts
.tx_dp:
        sub.w   GEO_TX1(a0),d3
        rts

; wn_titlebar(a3 = window, a5): title area in BlockPen, title (DetailPen on BlockPen, JAM2) at the start of the
; area, then, with WINDOWDRAG, the drag pattern (lines 2, 3, 6, 7 of each group of 8 in DetailPen) from the end
; of the title + 3 up to the end of the area - 3 (spec §3.2). Preserves d2-d7/a2-a5; clobbers d0/d1/a0/a1/a6.
wn_titlebar:
        bsr     it_unclip
        bsr     wn_titlebar_nc
        bra     it_reclip
wn_titlebar_nc:
        movem.l d2-d7/a2,-(sp)
        move.l  IB_GFXBASE(a5),a6
        moveq   #0,d7
        move.b  WD_BORDERTOP(a3),d7
        subq.w  #2,d7                ; d7 = last line of the bar
        bmi     .tb_ret
        bsr     wn_titlex
        cmp.w   d3,d2
        bge     .tb_ret
        move.w  d2,d4                ; d4 = start, d5 = end
        move.w  d3,d5
        bsr     wn_brp
        moveq   #JAM1,d0
        jsr     LVO_SETDRMD(a6)
        bsr     wn_brp
        moveq   #0,d0
        move.b  WD_BLOCKPEN(a3),d0
        jsr     LVO_SETAPEN(a6)
        bsr     wn_brp
        move.w  d4,d0
        moveq   #0,d1
        move.w  d5,d2
        move.w  d7,d3
        jsr     LVO_RECTFILL(a6)
        move.w  d4,d6
        addq.w  #3,d6                ; d6 = start of the pattern
        move.l  WD_TITLE(a3),d0
        beq.s   .tb_drag
        move.l  d0,a0
        bsr     wn_brp
        moveq   #0,d0
        move.b  WD_DETAILPEN(a3),d0
        moveq   #0,d1
        move.b  WD_BLOCKPEN(a3),d1
        move.w  d5,d2
        sub.w   d4,d2
        addq.w  #1,d2
        move.w  d4,d3
        bsr     it_title
        bsr     wn_brp
        move.w  rp_cp_x(a1),d6
        addq.w  #3,d6
.tb_drag:
        btst    #1,WD_FLAGS+3(a3)    ; WINDOWDRAG
        beq.s   .tb_ret
        move.w  d6,d0
        moveq   #1,d1
        move.w  d5,d2
        subq.w  #3,d2
        move.w  d7,d3
        subq.w  #1,d3                ; down to BorderTop - 3
        lea     wn_dragpat(pc),a2
        moveq   #3,d6
        move.b  WD_DETAILPEN(a3),d7
        bsr.s   wn_patfill
.tb_ret:
        movem.l (sp)+,d2-d7/a2
        rts

; wn_veil(a3 = window, a5): veil of an inactive window (spec §4.2): one pixel out of four in BlockPen over the title
; area, lines 1 to BorderTop - 3. Preserves d2-d7/a2-a5; clobbers d0/d1/a0/a1/a6.
wn_veil:
        movem.l d2-d7/a2,-(sp)
        move.l  IB_GFXBASE(a5),a6
        moveq   #0,d7
        move.b  WD_BORDERTOP(a3),d7
        subq.w  #3,d7
        ble.s   .vl_ret
        bsr     wn_titlex
        move.w  d2,d0
        moveq   #1,d1
        move.w  d3,d2
        move.w  d7,d3
        lea     wn_veilpat(pc),a2
        moveq   #2,d6
        move.b  WD_BLOCKPEN(a3),d7
        bsr.s   wn_patfill
.vl_ret:
        movem.l (sp)+,d2-d7/a2
        rts

; wn_patfill(a3 = window, a6 = GfxBase, a2 = pattern, d6 = log2 of its lines, d7.b = pen, d0-d3 = rectangle):
; patterned RectFill in JAM1 in the border RastPort, its original pattern restored afterwards. Empty rectangle: nothing.
; Clobbers d0-d3/a0/a1.
wn_patfill:
        cmp.w   d0,d2
        blt.s   .pf_ret
        cmp.w   d1,d3
        blt.s   .pf_ret
        movem.w d0-d3,-(sp)
        bsr     wn_brp
        move.l  rp_AreaPtrn(a1),-(sp)
        move.b  rp_AreaPtSz(a1),-(sp)
        move.l  a2,rp_AreaPtrn(a1)
        move.b  d6,rp_AreaPtSz(a1)
        moveq   #JAM1,d0
        jsr     LVO_SETDRMD(a6)
        bsr     wn_brp
        moveq   #0,d0
        move.b  d7,d0
        jsr     LVO_SETAPEN(a6)
        bsr     wn_brp
        movem.w 6(sp),d0-d3
        jsr     LVO_RECTFILL(a6)
        bsr     wn_brp
        move.b  (sp)+,rp_AreaPtSz(a1)
        move.l  (sp)+,rp_AreaPtrn(a1)
        addq.l  #8,sp
.pf_ret:
        rts

; wn_sysgads(a3 = window, a5): system gadget pictograms (spec §5): close at (0,0), size in the bottom-right
; corner, back then front depth on the right of the bar. Preserves d2-d7/a2-a5; clobbers d0/d1/a0/a1/a6.
wn_sysgads:
        bsr     it_unclip
        bsr     wn_sysgads_nc
        bra     it_reclip
wn_sysgads_nc:
        movem.l d2/a2/a4,-(sp)
        move.l  IB_GFXBASE(a5),a6
        bsr     wn_brp
        move.l  a1,a4                ; a4 = border RastPort
        bsr     wn_geo
        move.l  a0,a2                ; a2 = geometry
        move.l  WD_FLAGS(a3),d2
        btst    #3,d2                ; WINDOWCLOSE
        beq.s   .sg_size
        move.l  GEO_PCLOSE(a2),a0
        moveq   #0,d0
        moveq   #0,d1
        bsr.s   wn_picto
.sg_size:
        btst    #0,d2                ; WINDOWSIZING
        beq.s   .sg_depth
        move.l  GEO_PSIZE(a2),a0
        move.w  WD_WIDTH(a3),d0
        sub.w   GEO_SW(a2),d0
        move.w  WD_HEIGHT(a3),d1
        sub.w   GEO_SH(a2),d1
        bsr.s   wn_picto
.sg_depth:
        btst    #2,d2                ; WINDOWDEPTH
        beq.s   .sg_ret
        move.w  WD_WIDTH(a3),d0
        bsr.s   wn_depthpics
.sg_ret:
        movem.l (sp)+,d2/a2/a4
        rts

; wn_depthpics(a2 = geometry, a4 = RastPort, d0.w = width of the window or screen, a6): back and front depth
; pictograms, anchored to the right edge, line 0. Clobbers d0/d1/a0/a1.
wn_depthpics:
        move.w  d0,-(sp)
        move.l  GEO_PBACK(a2),a0
        sub.w   GEO_BACK(a2),d0
        moveq   #0,d1
        bsr.s   wn_picto
        move.w  (sp)+,d0
        move.l  GEO_PFRONT(a2),a0
        sub.w   GEO_FRONT(a2),d0
        moveq   #0,d1
;       (continued in wn_picto)

; wn_picto(a0 = pictogram, a4 = RastPort, d0.w/d1.w = top-left corner, a6): sequence of filled rectangles (pen,
; x0, y0, x1, y1 in bytes, terminated by $FF) drawn in JAM1. Clobbers d0/d1/a0/a1.
wn_picto:
        movem.l d2-d5/a2,-(sp)
        move.l  a0,a2
        move.w  d0,d4
        move.w  d1,d5
        move.l  a4,a1
        moveq   #JAM1,d0
        jsr     LVO_SETDRMD(a6)
.pc_lp:
        moveq   #0,d0
        move.b  (a2)+,d0
        cmp.b   #$FF,d0
        beq.s   .pc_ret
        move.l  a4,a1
        jsr     LVO_SETAPEN(a6)
        moveq   #0,d0
        move.b  (a2)+,d0
        add.w   d4,d0
        moveq   #0,d1
        move.b  (a2)+,d1
        add.w   d5,d1
        moveq   #0,d2
        move.b  (a2)+,d2
        add.w   d4,d2
        moveq   #0,d3
        move.b  (a2)+,d3
        add.w   d5,d3
        move.l  a4,a1
        jsr     LVO_RECTFILL(a6)
        bra.s   .pc_lp
.pc_ret:
        movem.l (sp)+,d2-d5/a2
        rts

; wn_sysat(a3 = window, d2/d3 = point in the window, in the title bar) -> d0.w = IT_SYSCLOSE / IT_SYSBACK /
; IT_SYSFRONT if the point is in that gadget's box (spec intuition-frame-v34 §5.2), Z = 1 otherwise. Clobbers d1/a0.
wn_sysat:
        bsr     wn_geo
        btst    #3,WD_FLAGS+3(a3)    ; WINDOWCLOSE
        beq.s   .sa_depth
        moveq   #IT_SYSCLOSE,d0
        cmp.w   GEO_CX0(a0),d2
        blt.s   .sa_depth
        cmp.w   GEO_CX1(a0),d2
        ble.s   .sa_hit
.sa_depth:
        btst    #2,WD_FLAGS+3(a3)    ; WINDOWDEPTH: back then front, anchored to the right edge
        beq.s   .sa_none
        move.w  WD_WIDTH(a3),d1
        sub.w   GEO_FEND(a0),d1
        cmp.w   d1,d2
        bgt.s   .sa_none             ; beyond the front gadget: drag
        move.w  WD_WIDTH(a3),d1
        sub.w   GEO_BACK(a0),d1
        cmp.w   d1,d2
        blt.s   .sa_none
        moveq   #IT_SYSBACK,d0
        move.w  WD_WIDTH(a3),d1
        sub.w   GEO_FRONT(a0),d1
        cmp.w   d1,d2
        blt.s   .sa_hit
        moveq   #IT_SYSFRONT,d0
.sa_hit:
        tst.w   d0                   ; Z = 0
        rts
.sa_none:
        moveq   #0,d0
        rts

; wn_sysinv(a3 = window, d0.w = system gadget, a5): inverts its box (GADGHCOMP highlight) in the border
; RastPort, drawing mode restored afterwards. Clobbers d0-d3/a0/a1/a6.
wn_sysinv:
        bsr     it_unclip
        bsr     wn_sysinv_nc
        bra     it_reclip
wn_sysinv_nc:
        move.w  d0,d3
        bsr     wn_geo
        moveq   #0,d1                ; box: y 0..9, x according to the gadget
        cmp.w   #IT_SYSCLOSE,d3
        bne.s   .si_depth
        move.w  GEO_CX0(a0),d0
        move.w  GEO_CX1(a0),d2
        bra.s   .si_fill
.si_depth:
        move.w  WD_WIDTH(a3),d0
        move.w  d0,d2
        cmp.w   #IT_SYSBACK,d3
        bne.s   .si_front
        sub.w   GEO_BACK(a0),d0
        sub.w   GEO_FRONT(a0),d2
        subq.w  #1,d2
        bra.s   .si_fill
.si_front:
        sub.w   GEO_FRONT(a0),d0
        sub.w   GEO_FEND(a0),d2
.si_fill:
        moveq   #9,d3
        move.l  IB_GFXBASE(a5),a6
        movem.w d0-d3,-(sp)
        bsr     wn_brp
        moveq   #0,d0
        move.b  rp_DrawMode(a1),d0
        move.w  d0,-(sp)
        moveq   #COMPLEMENT,d0
        jsr     LVO_SETDRMD(a6)
        bsr     wn_brp
        movem.w 2(sp),d0-d3
        jsr     LVO_RECTFILL(a6)
        bsr     wn_brp
        move.w  (sp)+,d0
        jsr     LVO_SETDRMD(a6)
        addq.l  #8,sp
        rts

; it_sysup(a5, d4/d5 = screen pointer): release of a system gadget: its box gets its look back, then, if the
; pointer is still over it, the action: CLOSEWINDOW, WindowToBack or WindowToFront.
it_sysup:
        move.l  IB_SYSWIN(a5),a3
        move.w  IB_SYSACT(a5),d0
        clr.w   IB_SYSACT(a5)
        move.w  d0,-(sp)
        bsr     wn_sysinv
        move.w  d4,d2
        sub.w   WD_LEFTEDGE(a3),d2
        move.w  d5,d3
        sub.w   WD_TOPEDGE(a3),d3
        tst.w   d3
        bmi.s   .su_out
        moveq   #0,d0
        move.b  WD_BORDERTOP(a3),d0
        cmp.w   d0,d3
        bge.s   .su_out              ; outside the title bar
        bsr     wn_sysat
        beq.s   .su_out
        move.w  (sp)+,d1             ; pressed gadget
        cmp.w   d0,d1
        bne.s   .su_ret              ; released over another gadget: nothing
        move.l  a3,a0
        move.l  a5,a6
        cmp.w   #IT_SYSBACK,d1
        beq     intuition_WindowToBack
        cmp.w   #IT_SYSFRONT,d1
        beq     intuition_WindowToFront
        move.l  #CLOSEWINDOW,d0
        moveq   #0,d1
        bra     wn_sendmsg
.su_out:
        addq.l  #2,sp
.su_ret:
        rts

; it_setactive(a3 = new active window | 0, a5): the old active window loses WINDOWACTIVE and receives the
; veil; the new one takes WINDOWACTIVE and its title bar is redrawn (veil cleared) (spec §4). Preserves everything.
it_setactive:
        movem.l d0-d1/a0-a1/a3/a6,-(sp)
        move.l  IB_ACTIVEWINDOW(a5),d0
        cmp.l   a3,d0
        beq.s   .sa_ret
        move.l  a3,IB_ACTIVEWINDOW(a5)
        tst.l   d0
        beq.s   .sa_new
        move.l  d0,a3
        and.l   #~WINDOWACTIVE,WD_FLAGS(a3)
        bsr     wn_veil
        move.l  16(sp),a3
.sa_new:
        move.l  a3,d0
        beq.s   .sa_ret
        or.l    #WINDOWACTIVE,WD_FLAGS(a3)
        bsr     wn_titlebar
.sa_ret:
        movem.l (sp)+,d0-d1/a0-a1/a3/a6
        rts

; fill patterns (SetAfPt): drag (8 lines: 2, 3, 6, 7 filled) and veil (4 lines, one pixel out of
; four, shifted from one line to the next)
wn_dragpat:
        dc.w    0,0,$FFFF,$FFFF,0,0,$FFFF,$FFFF
wn_veilpat:
        dc.w    $8888,$2222,$8888,$2222

; system gadget pictograms, drawn freely from their geometric description (spec §5.3): filled
; rectangles (pen, x0, y0, x1, y1). Pens: 0 screen background, 1 white, 2 black.
pic_front_h:                         ; 29 x 10: black square behind a hollow square in front
        dc.b    1,0,0,28,9, 0,0,0,1,9, 2,4,1,7,6, 2,4,1,17,1, 0,8,2,21,8, 1,10,3,19,7, 0,24,0,25,9, $FF
pic_back_h:                          ; 24 x 10: hollow square behind a black rectangle in front
        dc.b    1,0,0,23,9, 0,0,0,1,9, 0,4,1,17,6, 1,6,2,15,5, 2,8,3,21,8, $FF
pic_close_h:                         ; 28 x 10: hollow frame and small black square in the center
        dc.b    1,0,0,27,9, 0,4,0,5,9, 0,8,1,23,8, 1,10,2,21,7, 2,14,4,17,5, 0,26,0,27,9, $FF
pic_size_h:                          ; 16 x 9: two overlapping hollow rectangles
        dc.b    1,0,0,15,8, 0,2,1,7,3, 1,4,2,5,2, 0,6,3,13,7, 1,8,4,11,6, $FF
pic_front_l:                         ; 17 x 10
        dc.b    1,0,0,16,9, 0,0,0,1,9, 2,4,1,7,6, 2,4,1,10,1, 0,8,2,14,8, 1,9,3,13,7, $FF
pic_back_l:                          ; 17 x 10
        dc.b    1,0,0,16,9, 0,0,0,1,9, 0,4,1,10,6, 1,5,2,9,5, 2,8,3,14,8, $FF
pic_close_l:                         ; 14 x 10
        dc.b    1,0,0,13,9, 0,2,1,11,8, 1,3,2,10,7, 2,6,4,7,5, $FF
pic_size_l:                          ; 11 x 10: two black squares touching at a corner
        dc.b    1,0,0,10,9, 2,2,1,4,3, 2,5,4,8,8, $FF
        even

; CloseWindow(window a0): deletes its layer (layers gives the area back to the layers behind and to the background),
; removes it from its screen, redraws what was damaged (it_refresh), then frees its IDCMP port and the window.
intuition_CloseWindow:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  a6,a5
        move.l  a0,a3
        move.l  a0,d0
        beq     .cw_ret
        bsr     gad_forget           ; a gadget of this window was still pressed
        jsr     rq_closeall          ; its requesters (and their layers) first
        move.l  WD_WSCREEN(a3),a4    ; a4 = screen
        move.l  IB_LAYERSBASE(a5),a6
        suba.l  a0,a0
        move.l  WD_WLAYER(a3),a1
        jsr     LVO_DELETELAYER(a6)
        move.l  WDX_BLAYER(a3),d0    ; GIMMEZEROZERO: then the border layer
        beq.s   .cw_onel
        move.l  d0,a1
        suba.l  a0,a0
        jsr     LVO_DELETELAYER(a6)
.cw_onel:
        move.l  ($4).w,a6
        bsr     it_relist
        jsr     LVO_FORBID(a6)
        move.l  WD_PARENT(a3),d2     ; removed from the Parent/Descendant chain
        move.l  WD_DESCENDANT(a3),d0
        tst.l   d2
        beq.s   .cw_np
        move.l  d2,a0
        move.l  d0,WD_DESCENDANT(a0)
.cw_np:
        tst.l   d0
        beq.s   .cw_nd
        move.l  d0,a0
        move.l  d2,WD_PARENT(a0)
.cw_nd:
        jsr     LVO_PERMIT(a6)
        cmp.l   IB_ACTIVEWINDOW(a5),a3
        bne.s   .cw_act
        clr.l   IB_ACTIVEWINDOW(a5)  ; was active: its Parent, otherwise the first window of the screen, otherwise none
        tst.l   d2
        bne.s   .cw_new
        move.l  SC_FIRSTWINDOW(a4),d2
        bne.s   .cw_new
        movem.l a3/a6,-(sp)          ; no more windows: the bar gets the screen's title back
        move.l  a4,a3
        move.l  SC_DEFAULTTITLE(a3),SC_TITLE(a3)
        bsr     sc_drawbar
        movem.l (sp)+,a3/a6
        bra.s   .cw_act
.cw_new:
        move.l  a3,-(sp)
        move.l  d2,a3
        bsr     it_setactive
        bsr     wn_scrtitle
        move.l  (sp)+,a3
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

; it_relist(a4 = screen): the window list (sc_FirstWindow / wd_NextWindow) takes the order of the layers back, from
; front to back (layers without a window, like the bar, ignored). Preserves everything but d0/a0/a1.
it_relist:
        move.l  a6,-(sp)
        move.l  ($4).w,a6
        jsr     LVO_FORBID(a6)
        lea     SC_FIRSTWINDOW(a4),a1    ; link to fill (wd_NextWindow is at offset 0)
        move.l  SC_LAYERINFO(a4),a0      ; top_layer
.rl_lp:
        cmpa.w  #0,a0
        beq.s   .rl_end
        move.l  IL_WINDOW(a0),d0
        beq.s   .rl_n
        exg     d0,a1
        cmpa.l  WD_WLAYER(a1),a0     ; border layer of a GIMMEZEROZERO window: already counted
        exg     d0,a1
        bne.s   .rl_n
        move.l  d0,(a1)
        move.l  d0,a1
.rl_n:
        move.l  4(a0),a0                 ; next layer (back)
        bra.s   .rl_lp
.rl_end:
        clr.l   (a1)
        jsr     LVO_PERMIT(a6)
        move.l  (sp)+,a6
        rts

; it_refresh(a4 = screen, a5 = IntuitionBase): bar and windows whose layer is damaged (LAYERREFRESH). The bar
; is redrawn in its damaged area. A window gets its border redrawn in its damaged area; if it asked for
; REFRESHWINDOW, its damage stays for its owner (BeginRefresh/EndRefresh) and the message is sent to it,
; otherwise it is cleared. Preserves d2-d7/a2-a6.
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
        beq     .ir_r
        move.l  WDX_BLAYER(a3),d0    ; GIMMEZEROZERO: the border, in its own layer
        beq.s   .ir_inner
        move.l  d0,a2
        btst    #ILB_REFRESH,IL_FLAGS+1(a2)
        beq.s   .ir_inner
        move.l  IB_LAYERSBASE(a5),a6
        move.l  a2,a0
        jsr     LVO_BEGINUPDATE(a6)
        bsr     wn_border
        move.l  IB_LAYERSBASE(a5),a6
        move.l  a2,a0
        moveq   #1,d0
        jsr     LVO_ENDUPDATE(a6)
.ir_inner:
        move.l  WD_WLAYER(a3),a2
        btst    #ILB_REFRESH,IL_FLAGS+1(a2)
        beq     .ir_n
        move.l  IB_LAYERSBASE(a5),a6
        move.l  a2,a0
        jsr     LVO_BEGINUPDATE(a6)
        tst.l   WDX_BLAYER(a3)       ; interior of a GIMMEZEROZERO window: its gadgets only; those of the border
        beq.s   .ir_bord             ; (GZZGADGET) are drawn too, the system gadgets stay on top
        bsr     gad_drawall
        bsr     wn_sysgads
        bra.s   .ir_dmg
.ir_bord:
        bsr     wn_border
.ir_dmg:
        moveq   #1,d2                ; d2 = damage to clear?
        tst.l   WD_USERPORT(a3)
        beq.s   .ir_end
        moveq   #REFRESHWINDOW,d0
        and.l   WD_IDCMPFLAGS(a3),d0
        beq.s   .ir_end
        moveq   #0,d2                ; kept: the owner redraws
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
        bra     .ir_lp
.ir_r:
        movem.l (sp)+,d2-d7/a2-a3/a6
        rts

; WindowToFront(window a0) / WindowToBack(window a0): layer to the front / back (a BACKDROP window stays
; behind the others), window list put back in order, damaged areas redrawn.
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
        move.w  d1,d2
        move.l  WD_WLAYER(a3),a2     ; a2 = first layer handled, d3 = second | 0 (GIMMEZEROZERO: the interior
        move.l  WDX_BLAYER(a3),d3    ; must stay in front of its border -> to front: border then interior; to back:
        beq.s   .wd_go               ; interior then border)
        cmp.w   #LVO_BEHINDLAYER,d2
        beq.s   .wd_go
        exg     d3,a2
.wd_go:
        suba.l  a0,a0
        move.l  a2,a1
        jsr     0(a6,d2.w)
        tst.l   d3
        beq.s   .wd_one
        suba.l  a0,a0
        move.l  d3,a1
        jsr     0(a6,d2.w)
.wd_one:
        jsr     rq_restack           ; the requesters stay just in front of the window
        bsr     it_relist
        bsr     it_refresh
        movem.l (sp)+,d2-d7/a2-a6
        rts

; ShowTitle(screen a0, show d0): the screen's title bar moves in front of (d0 != 0) or behind (d0 = 0) the
; BACKDROP windows (its layer is a backdrop: it always stays behind the other windows); damaged areas
; redrawn. Screen without a bar (SCREENQUIET): nothing.
intuition_ShowTitle:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  a6,a5
        move.l  a0,a4
        move.l  SC_BARLAYER(a4),d1
        beq.s   .st_ret
        moveq   #LVO_UPFRONTLAYER,d2
        tst.l   d0
        bne.s   .st_go
        moveq   #LVO_BEHINDLAYER,d2
.st_go:
        move.l  IB_LAYERSBASE(a5),a6
        suba.l  a0,a0
        move.l  d1,a1
        jsr     0(a6,d2.w)
        bsr     it_refresh
.st_ret:
        movem.l (sp)+,d2-d7/a2-a6
        rts

; ViewPortAddress(window a0) -> d0 = ViewPort of the window's screen.
intuition_ViewPortAddress:
        move.l  WD_WSCREEN(a0),d0
        add.l   #SC_VIEWPORT,d0
        rts

; MoveWindow(window a0, dx d0, dy d1): displacement bounded to the screen, then damaged areas redrawn.
intuition_MoveWindow:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  a6,a5
        move.l  a0,a3
        move.l  WD_WSCREEN(a3),a4
        move.w  WD_LEFTEDGE(a3),d2   ; new bounded position: 0 .. screen size - window size
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
        move.l  d0,d2
        move.l  d1,d3
        move.l  WDX_BLAYER(a3),d4    ; GIMMEZEROZERO: the border first
        beq.s   .mw_in
        move.l  d4,a1
        suba.l  a0,a0
        jsr     LVO_MOVELAYER(a6)
        move.l  d2,d0
        move.l  d3,d1
.mw_in:
        suba.l  a0,a0
        move.l  WD_WLAYER(a3),a1
        jsr     LVO_MOVELAYER(a6)
        jsr     rq_move              ; the requesters follow
        bsr     it_refresh
        movem.l (sp)+,d2-d7/a2-a6
        rts

; BeginRefresh(window a0) / EndRefresh(window a0, complete d0): BeginUpdate / EndUpdate of its layer.
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

; wn_refreshmsg(a3 = window): if it asked for REFRESHWINDOW and its message is not pending, sends it
; (without a reply port: ReplyMsg marks it replied, it is reused). Preserves d2-d7/a2-a6.
wn_refreshmsg:
        move.l  WD_USERPORT(a3),d0
        beq.s   .rf_ret
        moveq   #REFRESHWINDOW,d1
        and.l   WD_IDCMPFLAGS(a3),d1
        beq.s   .rf_ret
        lea     WDX_IMSG(a3),a1
        cmp.b   #NT_MESSAGE,LN_TYPE(a1)
        beq.s   .rf_ret              ; the previous one has not been read: it is enough
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

; intuition_ModifyIDCMP(window a0, classes d0): new IDCMP classes. 0: the UserPort is closed (its pending messages
; removed); non-zero without a UserPort: a port signaling the calling task is created. Under Forbid: the input
; task does not post during the change.
intuition_ModifyIDCMP:
        movem.l a3/a6,-(sp)
        move.l  a0,a3
        move.l  ($4).w,a6
        jsr     LVO_FORBID(a6)
        move.l  d0,WD_IDCMPFLAGS(a3)
        bne.s   .mi_open
        bsr     wn_freeport
        clr.l   WD_USERPORT(a3)
        bra.s   .mi_ret
.mi_open:
        tst.l   WD_USERPORT(a3)
        bne.s   .mi_ret
        bsr     wn_mkport
.mi_ret:
        jsr     LVO_PERMIT(a6)
        movem.l (sp)+,a3/a6
        rts

; wn_mkport(a3 = window, a6 = SysBase): IDCMP port (WD_USERPORT) signaling the calling task; left at 0 if
; out of signals or memory. Preserves d2-d7/a2-a6.
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

; wn_freeport(a3 = window, a6 = SysBase): removes any pending message from the port, frees the signal and the port.
; Preserves d2-d7/a2-a6.
wn_freeport:
        move.l  WD_USERPORT(a3),d0
        beq.s   .fp_ret
        move.l  a2,-(sp)
        move.l  d0,a2
        jsr     LVO_DISABLE(a6)
        move.l  d2,-(sp)
        lea     WDX_IMSG(a3),a1      ; messages still queued: removed before freeing the window
        moveq   #WDX_NEMSG,d2
.fp_lp:
        cmp.b   #NT_MESSAGE,LN_TYPE(a1)
        bne.s   .fp_nomsg
        move.l  a1,-(sp)
        jsr     LVO_REMOVE(a6)
        move.l  (sp)+,a1
        move.b  #NT_REPLYMSG,LN_TYPE(a1) ; free again in the pool (ModifyIDCMP can reopen a port)
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

; DrawImage(rp a0, image a1, x d0, y d1): draws the chain of Images (struct Image) at (x + LeftEdge, y + TopEdge). Each
; Image becomes a temporary 8-plane BitMap: image plane i -> i-th plane designated by PlanePick, the other planes are 0
; or 1 according to PlaneOnOff (NULL / -1 pointers); a single BltBitMapRastPort copies it into the RastPort.
intuition_DrawImage:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  IB_GFXBASE(a6),a6
        move.l  a0,a2                ; a2 = RastPort
        move.l  a1,a3                ; a3 = current Image
        movem.w d0-d1,-(sp)          ; (sp) = base x, 2(sp) = base y
        lea     -bm_SIZEOF(sp),sp
        move.l  sp,a4                ; a4 = temporary BitMap
.di_img:
        move.l  a3,d0
        beq     .di_done
        move.w  IG_WIDTH(a3),d0      ; bytes per line = whole words
        add.w   #15,d0
        lsr.w   #4,d0
        add.w   d0,d0
        move.w  d0,bm_BytesPerRow(a4)
        move.w  IG_HEIGHT(a3),bm_Rows(a4)
        move.b  #8,bm_Depth(a4)
        mulu    IG_HEIGHT(a3),d0     ; d0 = size of an image plane
        move.l  IG_IMAGEDATA(a3),a0
        moveq   #0,d1                ; d1 = BitMap plane
        moveq   #0,d2                ; d2 = image planes consumed
        lea     bm_Planes(a4),a1
.di_plane:
        btst    d1,IG_PLANEPICK(a3)
        beq.s   .di_onoff
        cmp.w   IG_DEPTH(a3),d2
        bge.s   .di_zero             ; chosen plane without data: 0
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
        move.l  a4,a0                ; BltBitMapRastPort(bm, 0, 0, rp, x, y, w, h, copy)
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

; AllocRemember(key a0, size d0, flags d1) -> d0 = memory | 0: allocates and links a Remember node at the head of
; *key. FreeRemember(key a0, forget d0): frees the nodes (and their memory if forget != 0), *key := 0.
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
        moveq   #RM_SIZEOF,d0        ; memory refused: gives the node back
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

; it_event(d0.w = ie_Code): called by the pointer handler (VBlank interrupt) for each RAWMOUSE, after the
; update of PTR_X/PTR_Y. A button is dropped into the ring with the pointer position (ring full: lost);
; a movement is signaled only if the input task is tracking the pointer (gesture or menu in progress) or if the active
; window asks for movements (REPORTMOUSE and IDCMP MOUSEMOVE). All the processing
; (windows, layers, menus) is done in the task: nothing here may wait. Preserves everything.
it_event:
        movem.l d0-d1/a0-a1/a6,-(sp)
        move.l  INT_IBASE,d1
        beq.s   .ev_ret
        move.l  d1,a1
        tst.l   IB_INSIG(a1)
        beq.s   .ev_ret              ; task not ready yet
        cmp.w   #IECODE_NOBUTTON,d0
        bne.s   .ev_btn
        tst.b   IB_TRACK(a1)
        bne.s   .ev_mv
        move.l  IB_ACTIVEWINDOW(a1),d1   ; active window that asks for movements (REPORTMOUSE + MOUSEMOVE)
        beq.s   .ev_ret
        move.l  d1,a0
        btst    #1,WD_FLAGS+2(a0)    ; REPORTMOUSE
        beq.s   .ev_ret
        btst    #4,WD_IDCMPFLAGS+3(a0)   ; MOUSEMOVE
        beq.s   .ev_ret
.ev_mv:
        st      IB_MOVED(a1)
        bra.s   .ev_sig
.ev_btn:
        move.w  PTR_X,d1
        swap    d1
        move.w  PTR_Y,d1
        bsr.s   it_push
        bra.s   .ev_ret
.ev_sig:
        bsr.s   it_signal
.ev_ret:
        movem.l (sp)+,d0-d1/a0-a1/a6
        rts

; it_push(a1 = IntuitionBase, d0.w = code, d1 = x (high word) : y (low word)): slot dropped into the input task's
; ring, then signal (ring full: lost). Clobbers d0/d1/a0/a6.
it_push:
        move.l  d2,-(sp)
        move.w  IB_EVHEAD(a1),d2
        lea     IB_EVRING(a1),a0
        add.w   d2,a0
        addq.w  #IB_EVSZ,d2
        cmp.w   #IB_EVN*IB_EVSZ,d2
        blo.s   .pu_wrap
        moveq   #0,d2
.pu_wrap:
        cmp.w   IB_EVTAIL(a1),d2
        beq.s   .pu_full
        move.w  d0,(a0)+
        swap    d1
        move.w  d1,(a0)+
        swap    d1
        move.w  d1,(a0)
        move.w  d2,IB_EVHEAD(a1)     ; published after the data
        move.l  (sp)+,d2
        bra.s   it_signal
.pu_full:
        move.l  (sp)+,d2
        rts
; it_signal(a1 = IntuitionBase): wakes up the input task. Clobbers d0/d1/a0/a6.
it_signal:
        move.l  a1,-(sp)
        move.l  IB_INSIG(a1),d0
        move.l  IB_INTASK(a1),a1
        move.l  ($4).w,a6
        jsr     LVO_SIGNAL(a6)
        move.l  (sp)+,a1
        rts

; it_keyin(a3 = RAWKEY InputEvent): pointer handler (input.device). The keyboard goes to an active text gadget;
; otherwise a right Amiga key that designates an item of the active window's menu strip (mn_keyshort) is swallowed and
; dropped into the ring (IT_MENUKEYCODE); otherwise the key goes to the active window if it asked for RAWKEY: the event
; is then neutralized (IECLASS_NULL, the console does not see it) and dropped into the ring (code IT_KEYCODE + raw code,
; release included; x = qualifier). A text gadget only receives pressed keys. Preserves everything.
it_keyin:
        movem.l d0-d1/a0-a1/a6,-(sp)
        move.l  INT_IBASE,d1
        beq.s   .ki_ret
        move.l  d1,a1
        tst.l   IB_INSIG(a1)
        beq.s   .ki_ret
        move.w  IE_CODE(a3),d0
        tst.l   IB_STRGAD(a1)
        bne.s   .ki_str
        move.l  IB_ACTIVEWINDOW(a1),d1
        beq.s   .ki_ret
        move.l  d1,a0
        btst    #7,d0
        bne.s   .ki_raw
        btst    #KQB_RCOMMAND,IE_QUALIFIER+1(a3)
        beq.s   .ki_raw
        jsr     mn_keyshort          ; d0 = menu code | -1
        tst.l   d0
        bmi.s   .ki_nmk
        clr.b   IE_CLASS(a3)         ; swallowed: the release will arrive normally
        move.w  d0,d1
        swap    d1
        move.w  IE_QUALIFIER(a3),d1
        move.w  #IT_MENUKEYCODE,d0
        bsr     it_push
        bra.s   .ki_ret
.ki_nmk:
        move.w  IE_CODE(a3),d0
.ki_raw:
        move.l  WD_IDCMPFLAGS(a0),d1
        and.l   #RAWKEY,d1
        beq.s   .ki_ret
        clr.b   IE_CLASS(a3)         ; IECLASS_NULL
        bra.s   .ki_push
.ki_str:
        clr.b   IE_CLASS(a3)
        btst    #7,d0
        bne.s   .ki_ret              ; release: swallowed
.ki_push:
        and.w   #$00FF,d0
        or.w    #IT_KEYCODE,d0
        move.w  IE_QUALIFIER(a3),d1
        swap    d1
        clr.w   d1
        bsr     it_push
.ki_ret:
        movem.l (sp)+,d0-d1/a0-a1/a6
        rts

; it_unclip(a3 = window): before an intuition drawing in the window, the layer is locked and, at the first
; level, the application's ClipRegion is removed (spec installclipregion-v34 §5): border and gadgets are not
; clipped by it. it_reclip puts it back and unlocks. Both preserve everything.
it_unclip:
        movem.l d0-d1/a0-a1/a6,-(sp)
        move.l  WD_WLAYER(a3),d0
        beq.s   .uc_r
        move.l  d0,a0
        lea     IL_LOCK(a0),a0
        move.l  ($4).w,a6
        jsr     LVO_OBTAINSEMAPHORE(a6)
        addq.w  #1,WDX_CLIPNEST(a3)
        cmp.w   #1,WDX_CLIPNEST(a3)
        bne.s   .uc_r
        move.l  WD_WLAYER(a3),a0
        move.l  IL_CLIPREGION(a0),WDX_CLIPSAVE(a3)
        beq.s   .uc_r
        suba.l  a1,a1
        move.l  INT_IBASE,a6
        move.l  IB_LAYERSBASE(a6),a6
        jsr     LVO_INSTALLCLIPREGION(a6)
.uc_r:
        movem.l (sp)+,d0-d1/a0-a1/a6
        rts
it_reclip:
        movem.l d0-d1/a0-a1/a6,-(sp)
        move.l  WD_WLAYER(a3),d0
        beq.s   .rc_r
        subq.w  #1,WDX_CLIPNEST(a3)
        bne.s   .rc_rel
        move.l  WDX_CLIPSAVE(a3),d0
        beq.s   .rc_rel
        move.l  WD_WLAYER(a3),a0
        move.l  d0,a1
        move.l  INT_IBASE,a6
        move.l  IB_LAYERSBASE(a6),a6
        jsr     LVO_INSTALLCLIPREGION(a6)
.rc_rel:
        move.l  WD_WLAYER(a3),a0
        lea     IL_LOCK(a0),a0
        move.l  ($4).w,a6
        jsr     LVO_RELEASESEMAPHORE(a6)
.rc_r:
        movem.l (sp)+,d0-d1/a0-a1/a6
        rts

; it_tickin(a3 = IECLASS_TIMER InputEvent): pointer handler (input.device). The tick goes to the input task, which
; sends INTUITICKS (it_tick). Preserves everything.
it_tickin:
        movem.l d0-d1/a0-a1/a6,-(sp)
        move.l  INT_IBASE,d1
        beq.s   .ti_ret
        move.l  d1,a1
        tst.l   IB_INSIG(a1)
        beq.s   .ti_ret
        move.w  #IT_TICKCODE,d0
        moveq   #0,d1
        bsr     it_push
.ti_ret:
        movem.l (sp)+,d0-d1/a0-a1/a6
        rts

; it_diskin(a3 = IECLASS_DISKINSERTED | IECLASS_DISKREMOVED InputEvent): pointer handler (input.device). Passes it to
; the input task (it_diskbc). Preserves everything.
it_diskin:
        movem.l d0-d1/a0-a1/a6,-(sp)
        move.l  INT_IBASE,d1
        beq.s   .di_ret
        move.l  d1,a1
        tst.l   IB_INSIG(a1)
        beq.s   .di_ret
        move.w  #IT_DISKINCODE,d0
        cmp.b   #IECLASS_DISKINSERTED,IE_CLASS(a3)
        beq.s   .di_push
        move.w  #IT_DISKOUTCODE,d0
.di_push:
        moveq   #0,d1
        bsr     it_push
.di_ret:
        movem.l (sp)+,d0-d1/a0-a1/a6
        rts

; it_diskbc(a5, d0.w = IT_DISKINCODE | IT_DISKOUTCODE): DISKINSERTED / DISKREMOVED to all the windows of all the
; screens that asked for it, active or not (spec disk-change-v34 §3); mouse relative to each window.
; Preserves d2-d7/a2-a5.
it_diskbc:
        movem.l d2-d7/a3-a4,-(sp)
        move.l  #DISKINSERTED,d7
        cmp.w   #IT_DISKINCODE,d0
        beq.s   .db_cls
        move.l  #DISKREMOVED,d7
.db_cls:
        move.l  IB_FIRSTSCREEN(a5),a4
.db_scr:
        cmpa.w  #0,a4
        beq.s   .db_ret
        move.l  SC_FIRSTWINDOW(a4),a3
.db_win:
        cmpa.w  #0,a3
        beq.s   .db_nscr
        move.w  PTR_X,d2
        sub.w   WD_LEFTEDGE(a3),d2
        move.w  PTR_Y,d3
        sub.w   WD_TOPEDGE(a3),d3
        move.l  d7,d0
        moveq   #0,d1
        bsr     wn_sendmsg           ; only if the window asked for the class
        move.l  WD_NEXTWINDOW(a3),a3
        bra.s   .db_win
.db_nscr:
        move.l  SC_NEXTSCREEN(a4),a4
        bra.s   .db_scr
.db_ret:
        movem.l (sp)+,d2-d7/a3-a4
        rts

; it_tick(a5): INTUITICKS to the active window if it asked for it and if its previous INTUITICKS was returned (at most
; one in circulation, like WINDOWTICKED in 1.3); mouse relative to the window (spec intuiticks-repeat-v34 §3).
; Preserves d2-d7/a2-a5.
it_tick:
        move.l  IB_ACTIVEWINDOW(a5),d1
        beq.s   .tk_ret
        movem.l d2-d6/a3-a4,-(sp)
        move.l  d1,a3
        move.l  WD_IDCMPFLAGS(a3),d0
        and.l   #INTUITICKS,d0
        beq.s   .tk_done
        lea     WDX_EMSG(a3),a1
        moveq   #WDX_NEMSG-1,d0
.tk_scan:
        cmp.b   #NT_MESSAGE,LN_TYPE(a1)
        bne.s   .tk_nx
        cmp.l   #INTUITICKS,IM_CLASS(a1)
        beq.s   .tk_done             ; the previous one has not been returned yet
.tk_nx:
        lea     IM_SIZEOF(a1),a1
        dbra    d0,.tk_scan
        move.w  PTR_X,d4
        move.w  PTR_Y,d5
        bsr     it_scrxy
        beq.s   .tk_done
        move.w  d4,d2
        sub.w   WD_LEFTEDGE(a3),d2
        move.w  d5,d3
        sub.w   WD_TOPEDGE(a3),d3
        move.l  #INTUITICKS,d0
        moveq   #0,d1
        bsr     wn_sendmsg
.tk_done:
        movem.l (sp)+,d2-d6/a3-a4
.tk_ret:
        rts

; it_startinput(a2 = IntuitionBase, a6 = SysBase): creates the input task (pri 20, like that of input.device).
; Without memory: no task, the buttons are ignored. Preserves d2-d7/a2-a6.
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
        move.l  a2,a3                ; never returns
        jsr     LVO_ADDTASK(a6)
.si_ret:
        movem.l (sp)+,a2-a4
        rts
it_inname:
        dc.b    "intuition input",0
        even

; it_intask: body of the input task. Allocates its signal and publishes itself, then processes in order the buttons of
; the ring and, when it is tracking the pointer, its last movement.
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
        move.w  (a0)+,d4             ; x, y (pointer)
        move.w  (a0),d5
        addq.w  #IB_EVSZ,d1
        cmp.w   #IB_EVN*IB_EVSZ,d1
        blo.s   .in_wrap
        moveq   #0,d1
.in_wrap:
        move.w  d1,IB_EVTAIL(a5)
        cmp.w   #IT_TICKCODE,d0
        beq.s   .in_tick
        cmp.w   #IT_DISKINCODE,d0
        beq.s   .in_disk
        cmp.w   #IT_DISKOUTCODE,d0
        beq.s   .in_disk
        cmp.w   #IT_MENUKEYCODE,d0
        beq.s   .in_mkey
        cmp.w   #IT_KEYCODE,d0
        bhs.s   .in_key
        bsr     it_dobutton
        bra.s   .in_next
.in_key:
        tst.l   IB_STRGAD(a5)
        beq.s   .in_raw
        btst    #7,d0                ; text gadget: pressed keys only
        bne.s   .in_next
        bsr     str_key              ; d0 = key, d4 = qualifier
        bra.s   .in_next
.in_raw:
        bsr     it_rawkey
        bra.s   .in_next
.in_tick:
        bsr     it_tick
        bra.s   .in_next
.in_disk:
        bsr     it_diskbc
        bra.s   .in_next
.in_mkey:
        jsr     mn_keypick           ; d4 = menu code, d5 = qualifier
        bra     .in_next
.in_move:
        tst.b   IB_MOVED(a5)
        beq     .in_wait
        clr.b   IB_MOVED(a5)
        move.w  PTR_X,d4
        move.w  PTR_Y,d5
        bsr     it_domove
        bra     .in_next

; it_rawkey(a5, d0.w = IT_KEYCODE + raw code, d4.w = qualifier): RAWKEY message to the active window, if it
; asked for it. Preserves d2-d7/a2-a5.
it_rawkey:
        move.l  IB_ACTIVEWINDOW(a5),d1
        beq.s   .rk_ret
        movem.l d2-d3/a3,-(sp)
        move.l  d1,a3
        move.w  d0,d1
        and.w   #$00FF,d1
        moveq   #0,d2
        moveq   #0,d3
        move.l  #RAWKEY,d0
        bsr     wn_sendkey
        movem.l (sp)+,d2-d3/a3
.rk_ret:
        rts

; it_scrxy(a5, d4.w/d5.w = pointer) -> a4 = front screen, d4/d5 = position in this screen (HIRES: x doubled);
; Z = 1 if there is no screen. Clobbers d0.
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

; it_winat(a4 = screen, d4/d5 = position) -> a3 = frontmost window under the point, d2/d3 = relative position;
; Z = 1 if none. Clobbers d0.
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

; it_dobutton(a5 = IntuitionBase, d0.w = code, d4/d5 = pointer): input task context. Left button pressed over a window:
; it becomes active (including a BACKDROP window, for its menus); close gadget -> CLOSEWINDOW, depth gadgets -> back /
; front, title bar (WINDOWDRAG) or size gadget -> gesture with ghost frame; otherwise MOUSEBUTTONS. The release ends a
; gesture in progress, otherwise it goes to the active window (SELECTUP). Right button: menus. Preserves a5.
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
        bne     .db_ret              ; menus displayed: the left button is ignored
        cmp.w   #IECODE_LBUTTON|IECODE_UP_PREFIX,d7
        bne.s   .db_down
        tst.w   IB_SYSACT(a5)
        bne     it_sysup             ; a system gadget was pressed
        tst.l   IB_GADACT(a5)
        bne     gad_up               ; an application gadget was pressed
        move.l  IB_ACTIVEWINDOW(a5),d0   ; release: to the active window (the clicked one), wherever it happens
        beq     .db_ret
        move.l  d0,a3
        cmp.l   WD_WSCREEN(a3),a4
        bne     .db_ret
        move.w  d4,d2
        sub.w   WD_LEFTEDGE(a3),d2
        move.w  d5,d3
        sub.w   WD_TOPEDGE(a3),d3
        move.l  #MOUSEBUTTONS,d0
        move.w  #SELECTUP,d1
        bra     wn_sendmsg
.db_down:
        cmp.w   #IECODE_LBUTTON,d7
        bne.s   .db_nstr
        bsr     str_clickout         ; a click outside the active text gadget deactivates it
.db_nstr:
        bsr     it_winat
        beq     .db_ret
        cmp.w   #IECODE_LBUTTON,d7
        bne     .db_mb
        bsr     it_setactive         ; the clicked window becomes active (BACKDROP included: its menus)
        bsr     wn_scrtitle
        btst    #3,WD_FLAGS+2(a3)    ; BORDERLESS: no system gadget
        bne     .db_mb
        cmp.b   #WD_TBARH,WD_BORDERTOP(a3)
        bne.s   .db_size
        cmp.w   #WD_TBARH,d3
        bge.s   .db_size
        bsr     wn_sysat             ; close / depth: box inverted, action on release
        beq.s   .db_ndepth
        cmp.w   #IT_SYSCLOSE,d0      ; close refused while a requester is up
        bne.s   .db_sys
        tst.l   WD_FIRSTREQUEST(a3)
        bne     .db_ret
.db_sys:
        move.w  d0,IB_SYSACT(a5)
        move.l  a3,IB_SYSWIN(a5)
        bra     wn_sysinv
.db_ndepth:
        btst    #1,WD_FLAGS+3(a3)    ; WINDOWDRAG
        beq.s   .db_mb
        moveq   #IT_DRAGMOVE,d0
        bra     it_dragstart
.db_size:
        btst    #0,WD_FLAGS+3(a3)    ; WINDOWSIZING: gadget in the bottom-right corner
        beq.s   .db_mb
        bsr     wn_geo
        move.w  WD_WIDTH(a3),d0
        sub.w   GEO_SW(a0),d0
        cmp.w   d0,d2
        blt.s   .db_mb
        move.w  WD_HEIGHT(a3),d0
        sub.w   GEO_SH(a0),d0
        cmp.w   d0,d3
        blt.s   .db_mb
        moveq   #IT_DRAGSIZE,d0
        bra     it_dragstart
.db_mb:
        cmp.w   #IECODE_LBUTTON,d7
        bne.s   .db_ret
        bsr     gad_down             ; does an application gadget take the click?
        bne.s   .db_ret
        move.l  #MOUSEBUTTONS,d0
        moveq   #SELECTDOWN,d1
        bra     wn_sendmsg
.db_ret:
        rts

; it_dragstart(a3 = window, a4 = screen, d0 = IT_DRAGMOVE | IT_DRAGSIZE, d4/d5 = pointer): start of a gesture. The
; screen's layers are locked until the release (nobody draws under the ghost frame, drawn in
; COMPLEMENT mode in the screen's RastPort). Preserves a5.
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

; it_domove(a5, d4/d5 = pointer): gesture in progress -> the ghost frame follows the pointer; menus -> highlight.
it_domove:
        tst.l   IB_MENUWIN(a5)
        bne     it_menumove
        jsr     prop_track           ; knob of a held proportional gadget; the active window also receives the
        beq.s   .dm_np               ; movement if it has REPORTMOUSE
        move.w  PTR_X,d4
        move.w  PTR_Y,d5
        bra     it_reportmove
.dm_np:
        move.l  IB_DRAGWIN(a5),d0
        beq.s   it_reportmove
        move.l  d0,a3
        bsr     it_scrxy
        beq.s   .dm_ret
        bsr     it_boxxor            ; erase the old one
        bsr     it_dragrect
        bra     it_boxxor
.dm_ret:
        rts

; it_reportmove(a5, d4/d5 = pointer): the active window that asks for movements receives MOUSEMOVE (relative
; position). A MOUSEMOVE not yet replied is updated rather than duplicated: the port does not overflow.
it_reportmove:
        move.l  IB_ACTIVEWINDOW(a5),d0
        beq.s   .rm_ret
        move.l  d0,a3
        btst    #1,WD_FLAGS+2(a3)    ; REPORTMOUSE
        beq.s   .rm_ret
        tst.l   WD_USERPORT(a3)
        beq.s   .rm_ret
        btst    #4,WD_IDCMPFLAGS+3(a3)   ; MOUSEMOVE
        beq.s   .rm_ret
        bsr     it_scrxy
        beq.s   .rm_ret
        cmp.l   WD_WSCREEN(a3),a4
        bne.s   .rm_ret
        move.w  d4,d2
        sub.w   WD_LEFTEDGE(a3),d2
        move.w  d5,d3
        sub.w   WD_TOPEDGE(a3),d3
        lea     WDX_EMSG(a3),a1
        moveq   #WDX_NEMSG-1,d6
.rm_find:
        cmp.b   #NT_MESSAGE,LN_TYPE(a1)
        bne.s   .rm_nx
        cmp.l   #MOUSEMOVE,IM_CLASS(a1)
        bne.s   .rm_nx
        move.w  d2,IM_MOUSEX(a1)
        move.w  d3,IM_MOUSEY(a1)
        rts
.rm_nx:
        lea     IM_SIZEOF(a1),a1
        dbra    d6,.rm_find
        move.l  #MOUSEMOVE,d0
        move.w  #IECODE_NOBUTTON,d1
        bra     wn_sendmsg
.rm_ret:
        rts

; ReportMouse(flag d0, window a0): the window receives (or no longer receives) the mouse movements (REPORTMOUSE).
intuition_ReportMouse:
        tst.w   d0
        beq.s   .rp_off
        or.l    #REPORTMOUSE,WD_FLAGS(a0)
        rts
.rp_off:
        and.l   #~REPORTMOUSE,WD_FLAGS(a0)
        rts

; it_dragend(a5, a4 = screen, d4/d5 = pointer at release): erases the frame, applies the move or the
; new size, then releases the layers.
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

; it_dragrect(a3 = window, a4 = screen, a5, d4/d5 = pointer): rectangle targeted by the gesture -> IB_BOX (x0,y0,x1,y1).
; Move: the window stays within the screen; size: bounded by the window limits and the screen.
it_dragrect:
        movem.l d2-d7,-(sp)
        move.w  d4,d6
        sub.w   IB_DRAGSX(a5),d6     ; d6/d7 = pointer displacement
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
        add.w   d6,d2                ; width: [MinWidth, min(MaxWidth, screen - LeftEdge)]
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
        add.w   d0,d2                ; x1 = x0 + width - 1
        subq.w  #1,d2
        add.w   d1,d3
        subq.w  #1,d3
        movem.w d0-d3,IB_BOX(a5)
        movem.l (sp)+,d2-d7
        rts
.dr_clamp0:                          ; d0 := clamp(d0, 0, d4)
        moveq   #0,d5
; it_clamp: d0.w := clamp(d0, d5, d4) (d4 wins if d5 > d4).
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

; it_boxxor(a3 = window of the gesture, a5): inverts the IB_BOX frame (1 pixel) in its screen's RastPort; four
; disjoint segments, so that a second call erases it exactly. Preserves d2-d7/a2-a5.
it_boxxor:
        movem.l d2-d7/a2,-(sp)
        move.l  WD_WSCREEN(a3),a2
        lea     SC_RASTPORT(a2),a2
        move.l  IB_GFXBASE(a5),a6
        move.l  a2,a1
        moveq   #COMPLEMENT,d0
        jsr     LVO_SETDRMD(a6)
        movem.w IB_BOX(a5),d4-d7     ; x0, y0, x1, y1
        move.l  a2,a1                ; top
        move.w  d4,d0
        move.w  d5,d1
        move.w  d6,d2
        move.w  d5,d3
        jsr     LVO_RECTFILL(a6)
        cmp.w   d5,d7
        ble.s   .bx_done
        move.l  a2,a1                ; bottom
        move.w  d4,d0
        move.w  d7,d1
        move.w  d6,d2
        move.w  d7,d3
        jsr     LVO_RECTFILL(a6)
        move.w  d7,d3
        subq.w  #1,d3
        cmp.w   d5,d3
        ble.s   .bx_done
        move.l  a2,a1                ; left
        move.w  d4,d0
        move.w  d5,d1
        addq.w  #1,d1
        move.w  d4,d2
        jsr     LVO_RECTFILL(a6)
        cmp.w   d4,d6
        ble.s   .bx_done
        move.l  a2,a1                ; right
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

; SizeWindow(window a0, dx d0, dy d1): new bounded size (at least 16 pixels, without leaving the screen). The
; layer follows (SizeLayer); the old borders that became interior and the old size gadget are erased,
; the border redrawn, NEWSIZE sent, then the damaged areas repaired (REFRESHWINDOW for the window itself).
intuition_SizeWindow:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  a6,a5
        move.l  a0,a3
        move.l  WD_WSCREEN(a3),a4
        move.w  WD_WIDTH(a3),d6      ; d6/d7 = old size
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
        sub.w   d6,d0                ; d0/d1 = effective change
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
        move.l  WDX_BLAYER(a3),d4    ; GIMMEZEROZERO: the border, then the interior by the same change (d6/d7 =
        beq.s   .sw_in               ; old size, kept for wn_unborder)
        movem.l d0-d1,-(sp)
        move.l  d4,a1
        suba.l  a0,a0
        jsr     LVO_SIZELAYER(a6)
        movem.l (sp)+,d0-d1
.sw_in:
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

; WindowLimits(window a0, minW d0, minH d1, maxW d2, maxH d3) -> d0 = TRUE: limits of the size gadget; a
; zero value leaves the limit unchanged.
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

; wn_gzz(a3 = window): GZZWidth / GZZHeight = size minus the borders. Clobbers d0/d1.
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

; wn_unborder(a3 = window, a5, d6/d7 = old size): erases (pen 0) the right / bottom border bands
; touched by the size change, from min(old, new) up to the new edges (old border that became
; interior, or interior that went under the new border), and the old size gadget; wn_border then redraws
; the border. Clobbers d0-d5/a0/a1/a6.
wn_unborder:
        btst    #3,WD_FLAGS+2(a3)    ; BORDERLESS: nothing to erase
        bne     .ub_ret
        move.l  IB_GFXBASE(a5),a6
        bsr     wn_brp
        moveq   #0,d0
        jsr     LVO_SETAPEN(a6)
        move.w  WD_WIDTH(a3),d0      ; right band: [min(oldW, W) - BR, W - 1] x [BT, H - 1]
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
        move.w  WD_HEIGHT(a3),d1     ; bottom band: [0, W - 1] x [min(oldH, H) - BB, H - 1]
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
        btst    #0,WD_FLAGS+3(a3)    ; old size gadget
        beq.s   .ub_ret
        move.w  d6,d0
        sub.w   #18,d0
        move.w  d7,d1
        sub.w   #9,d1
        move.w  d6,d2
        subq.w  #1,d2
        move.w  d7,d3
        subq.w  #1,d3
.ub_fill:                            ; RectFill if the rectangle is not empty
        cmp.w   d0,d2
        blt.s   .ub_ret
        cmp.w   d1,d3
        blt.s   .ub_ret
        bsr     wn_brp
        jmp     LVO_RECTFILL(a6)
.ub_ret:
        rts

; wn_sendmsg(a3 = window, d0 = IDCMP class, d1.w = code, d2.w/d3.w = relative mouse): if the window asked for
; this class, takes a free IntuiMessage from its pool, timestamps it (VBlank counter: 50 Hz) and sends it on its
; UserPort; pool exhausted: event lost. im_IAddress = the window; wn_sendgad: im_IAddress = a0 (the gadget
; of GADGETDOWN / GADGETUP); wn_sendkey: im_Qualifier = d4.w (RAWKEY). Clobbers d0/d1/d6/a0/a1/a6.
wn_sendmsg:
        move.l  a3,a0
wn_sendgad:
        clr.w   -(sp)                ; qualifier
        bra.s   wn_post
wn_sendkey:
        move.l  a3,a0
        move.w  d4,-(sp)
wn_post:
        move.l  WD_USERPORT(a3),d6
        beq     .sm_ret
        and.l   WD_IDCMPFLAGS(a3),d0
        beq     .sm_ret
        move.l  WD_FIRSTREQUEST(a3),d6   ; requester without NOISYREQ: keys, buttons, movements, ticks and menus
        beq.s   .sm_take                 ; are swallowed (spec intuition-requesters-v34 §3.2)
        move.l  d6,a1
        btst    #2,RQ_FLAGS+1(a1)    ; NOISYREQ
        bne.s   .sm_take
        move.l  d0,d6
        and.l   #RAWKEY|MOUSEBUTTONS|MOUSEMOVE|INTUITICKS|MENUPICK,d6
        bne     .sm_ret
.sm_take:
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
        move.w  (sp),IM_QUALIFIER(a1)
        move.l  a0,IM_IADDRESS(a1)
        move.w  d2,IM_MOUSEX(a1)
        move.w  d3,IM_MOUSEY(a1)
        move.l  GP_POLLS,d0          ; seconds / microseconds since startup (VBlanks)
        moveq   #0,d1
        swap    d0
        move.w  d0,d1
        divu    #50,d1               ; long division in two steps (the quotient may exceed 16 bits)
        move.w  d1,d6
        swap    d6
        swap    d0
        move.w  d0,d1
        divu    #50,d1
        move.w  d1,d6                ; d6 = seconds
        swap    d1
        mulu    #20000,d1            ; remainder (1/50 s) -> microseconds
        move.l  d6,IM_SECONDS(a1)
        move.l  d1,IM_MICROS(a1)
        move.l  a3,IM_IDCMPWINDOW(a1)
        move.l  WD_USERPORT(a3),a0
        move.l  ($4).w,a6
        jsr     LVO_PUTMSG(a6)
.sm_ret:
        addq.l  #2,sp
        rts

; DoubleClick(seconds d0, micros d1, seconds d2, micros d3) -> d0 = TRUE if the second click follows the first by less
; than the double-click delay of the Preferences (a6 = IntuitionBase).
intuition_DoubleClick:
        sub.l   d0,d2                ; (d2, d3) = gap (seconds, microseconds)
        bmi.s   .dc_no
        sub.l   d1,d3
        bpl.s   .dc_cmp
        add.l   #1000000,d3
        subq.l  #1,d2
        bmi.s   .dc_no
.dc_cmp:
        cmp.l   IB_PREFS+PF_DBLCLICK(a6),d2
        bhi.s   .dc_no
        blo.s   .dc_yes
        cmp.l   IB_PREFS+PF_DBLCLICK+4(a6),d3
        bhs.s   .dc_no
.dc_yes:
        moveq   #-1,d0
        rts
.dc_no:
        moveq   #0,d0
        rts

; Workbench NewScreen
sc_wbnewscreen:
        dc.w    0,0,640,256,2        ; LeftEdge, TopEdge, Width, Height, Depth
        dc.b    2,1                  ; DetailPen (titles and gadgets: black), BlockPen (bars: white)
        dc.w    V_HIRES              ; ViewModes
        dc.w    WBENCHSCREEN         ; Type
        dc.l    0                    ; Font
        dc.l    sc_wbtitle           ; DefaultTitle
        dc.l    0,0                  ; Gadgets, CustomBitMap
; default palette: project theme (apple-green background instead of the blue of the 1.3 preferences, white, black,
; orange), then fill colors (16..19: pointer)
sc_palette:
        dc.w    SC_BGCOLOR,$FFF,$000,$F80,$00F,$F0F,$0FF,$FFF
        dc.w    $620,$E50,$9F1,$EB0,$55F,$92F,$0F8,$CCC
        dc.w    $000,$E44,$000,$EEC,$444,$555,$666,$777
        dc.w    $888,$999,$AAA,$BBB,$CCC,$DDD,$EEE,$FFF
sc_wbtitle:
        dc.b    "Workbench Screen",0
        even
