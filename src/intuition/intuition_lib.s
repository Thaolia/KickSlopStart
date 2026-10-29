; src/intuition/intuition_lib.s - intuition.library (M5: resident skeleton + ViewAddress).
; Modeled on graphics_lib.s (M4c1): ROMTag RTF_AUTOINIT NT_LIBRARY, pri 10 (roadmap slot, initialized last),
; auto-scanned by build_reslist -> MakeLibrary creates IntuitionBase, Enqueue into EB_LIBLIST (NT_LIBRARY branch).
; Provides Open/Close/Expunge, ViewAddress (-> &ib_ViewLord, the embedded View); Preferences in prefs.s; screens and
; windows in screens.s (OpenScreen/CloseScreen/OpenWorkBench/GetScreenData/OpenWindow/CloseWindow).
;
; IMPLEMENTATION track ("clean"): AutoDocs intuition.library + NDK includes/.fd (public). NO ROM reading.

                include "exec.i"
                include "intuition.i"

                xref    intuition_DisplayAlert ; alert.s
                xref    intuition_AutoRequest
                xref    intuition_AddGadget
                xref    intuition_AddGList
                xref    intuition_RemoveGadget
                xref    intuition_RemoveGList
                xref    intuition_RefreshGadgets
                xref    intuition_RefreshGList
                xref    intuition_OnGadget
                xref    intuition_OffGadget
                xref    intuition_DrawBorder
                xref    intuition_OpenScreen     ; screens.s: screens and windows
                xref    intuition_CloseScreen
                xref    intuition_OpenWorkBench
                xref    intuition_GetScreenData
                xref    intuition_OpenWindow
                xref    intuition_CloseWindow
                xref    it_ptrinit               ; pointer.s: pointer sprite
                xref    intuition_DrawImage      ; screens.s
                xref    intuition_ModifyProp     ; gadgets.s
                xref    intuition_NewModifyProp
                xref    intuition_AllocRemember
                xref    intuition_Request        ; request.s
                xref    intuition_ScreenToBack   ; screens.s
                xref    intuition_ScreenToFront
                xref    intuition_EndRequest
                xref    intuition_InitRequester
                xref    intuition_SetDMRequest
                xref    intuition_ClearDMRequest
                xref    intuition_BuildSysRequest ; sysreq.s
                xref    intuition_FreeSysRequest
                xref    intuition_FreeRemember
                xref    intuition_DoubleClick
                xref    intuition_GetPrefs
                xref    intuition_GetDefPrefs
                xref    intuition_SetPrefs
                xref    it_prefsinit
                xref    intuition_RemakeDisplay
                xref    intuition_WindowToBack
                xref    intuition_WindowToFront
                xref    intuition_BeginRefresh
                xref    intuition_EndRefresh
                xref    intuition_MoveWindow
                xref    intuition_ReportMouse
                xref    intuition_SizeWindow
                xref    intuition_SetWindowTitles
                xref    intuition_DisplayBeep
                xref    intuition_WindowLimits
                xref    intuition_SetMenuStrip   ; menus.s
                xref    intuition_ClearMenuStrip
                xref    intuition_ItemAddress
                xref    intuition_OnMenu
                xref    intuition_OffMenu
                xref    intuition_ModifyIDCMP
                xref    intuition_ShowTitle
                xref    intuition_ViewPortAddress
                xref    intuition_PrintIText
                xref    intuition_IntuiTextLength
                xref    it_startinput            ; screens.s: input task (buttons, gadgets, menus)

; --- intuition.library ROMTag (scanned by build_reslist) ---
        EVEN
intuition_romtag:
        dc.w    RTC_MATCHWORD
        dc.l    intuition_romtag         ; RT_MATCHTAG = self
        dc.l    intuition_end            ; RT_ENDSKIP
        dc.b    RTF_AUTOINIT|RTF_COLDSTART,34,NT_LIBRARY,10  ; RT_FLAGS, RT_VERSION, RT_TYPE, RT_PRI (10: intuition roadmap slot)
        dc.l    intuition_name           ; RT_NAME
        dc.l    intuition_name           ; RT_IDSTRING
        dc.l    intuition_inittab        ; RT_INIT -> AUTOINIT table
intuition_name:
        dc.b    "intuition.library",0
        EVEN
intuition_inittab:
        dc.l    INTUITIONBASE_SIZE       ; dataSize: Library base + IntuitionBase fields (embedded ViewLord...)
        dc.l    intuition_vectors        ; funcTable
        dc.l    intuition_datatab        ; dataTable (InitStruct)
        dc.l    intuition_initfunc       ; initFunc
; ABSOLUTE table terminated by -1. Vector N -> LVO -6*N; unimplemented vectors point to intuition_null
; (dcb avoids any manual miscount).
intuition_vectors:
        dc.l    intuition_open           ; 1: LVO -6
        dc.l    intuition_close          ; 2: LVO -12
        dc.l    intuition_expunge        ; 3: LVO -18
        dc.l    intuition_null           ; 4: LVO -24 (reserved)
        dcb.l   2,intuition_null         ; 5..6: LVO -30..-36 (not impl.)
        dc.l    intuition_AddGadget      ; 7: LVO -42 AddGadget(window a0, gadget a1, position d0)
        dc.l    intuition_ClearDMRequest ; 8: LVO -48 ClearDMRequest(window a0)
        dc.l    intuition_ClearMenuStrip ; 9: LVO -54 ClearMenuStrip(window a0)
        dc.l    intuition_null           ; 10: LVO -60 ClearPointer (not impl.)
        dc.l    intuition_CloseScreen    ; 11: LVO -66 CloseScreen(screen a0)
        dc.l    intuition_CloseWindow    ; 12: LVO -72 CloseWindow(window a0)
        dcb.l   2,intuition_null         ; 13..14: LVO -78..-84 (CloseWorkBench, CurrentTime: not impl.)
        dc.l    intuition_DisplayAlert   ; 15: LVO -90 DisplayAlert(number d0, string a0, height d1) -> d0
        dc.l    intuition_DisplayBeep    ; 16: LVO -96 DisplayBeep(screen a0 | 0)
        dc.l    intuition_DoubleClick    ; 17: LVO -102 DoubleClick(s1 d0, us1 d1, s2 d2, us2 d3)
        dc.l    intuition_DrawBorder     ; 18: LVO -108 DrawBorder(rp a0, border a1, x d0, y d1)
        dc.l    intuition_DrawImage      ; 19: LVO -114 DrawImage(rp a0, image a1, x d0, y d1)
        dc.l    intuition_EndRequest     ; 20: LVO -120 EndRequest(requester a0, window a1)
        dc.l    intuition_GetDefPrefs    ; 21: LVO -126 GetDefPrefs(buffer a0, size d0)
        dc.l    intuition_GetPrefs       ; 22: LVO -132 GetPrefs(buffer a0, size d0)
        dc.l    intuition_InitRequester  ; 23: LVO -138 InitRequester(requester a0)
        dc.l    intuition_ItemAddress    ; 24: LVO -144 ItemAddress(menustrip a0, code d0)
        dc.l    intuition_ModifyIDCMP    ; 25: LVO -150 ModifyIDCMP(window a0, classes d0)
        dc.l    intuition_ModifyProp     ; 26: LVO -156 ModifyProp(gadget a0, window a1, requester a2, Flags d0, Pots d1/d2, Bodies d3/d4)
        dc.l    intuition_null           ; 27: LVO -162 MoveScreen (not impl.)
        dc.l    intuition_MoveWindow     ; 28: LVO -168 MoveWindow(window a0, dx d0, dy d1)
        dc.l    intuition_OffGadget      ; 29: LVO -174 OffGadget(gadget a0, window a1, requester a2)
        dc.l    intuition_OffMenu        ; 30: LVO -180 OffMenu(window a0, code d0)
        dc.l    intuition_OnGadget       ; 31: LVO -186 OnGadget(gadget a0, window a1, requester a2)
        dc.l    intuition_OnMenu         ; 32: LVO -192 OnMenu(window a0, code d0)
        dc.l    intuition_OpenScreen     ; 33: LVO -198 OpenScreen(newscreen a0)
        dc.l    intuition_OpenWindow     ; 34: LVO -204 OpenWindow(newwindow a0)
        dc.l    intuition_OpenWorkBench  ; 35: LVO -210 OpenWorkBench()
        dc.l    intuition_PrintIText     ; 36: LVO -216 PrintIText(rp a0, itext a1, x d0, y d1)
        dc.l    intuition_RefreshGadgets ; 37: LVO -222 RefreshGadgets(gadgets a0, window a1, requester a2)
        dc.l    intuition_RemoveGadget   ; 38: LVO -228 RemoveGadget(window a0, gadget a1)
        dc.l    intuition_ReportMouse    ; 39: LVO -234 ReportMouse(flag d0, window a0)
        dc.l    intuition_Request        ; 40: LVO -240 Request(requester a0, window a1)
        dc.l    intuition_ScreenToBack   ; 41: LVO -246 ScreenToBack(screen a0)
        dc.l    intuition_ScreenToFront  ; 42: LVO -252 ScreenToFront(screen a0)
        dc.l    intuition_SetDMRequest   ; 43: LVO -258 SetDMRequest(window a0, requester a1)
        dc.l    intuition_SetMenuStrip   ; 44: LVO -264 SetMenuStrip(window a0, menu a1)
        dc.l    intuition_null           ; 45: LVO -270 SetPointer (not impl.)
        dc.l    intuition_SetWindowTitles ; 46: LVO -276 SetWindowTitles(window a0, title a1, screen title a2)
        dc.l    intuition_ShowTitle      ; 47: LVO -282 ShowTitle(screen a0, show d0)
        dc.l    intuition_SizeWindow     ; 48: LVO -288 SizeWindow(window a0, dx d0, dy d1)
        dc.l    intuition_ViewAddress    ; 49: LVO -294
        dc.l    intuition_ViewPortAddress ; 50: LVO -300 ViewPortAddress(window a0)
        dc.l    intuition_WindowToBack   ; 51: LVO -306 WindowToBack(window a0)
        dc.l    intuition_WindowToFront  ; 52: LVO -312 WindowToFront(window a0)
        dc.l    intuition_WindowLimits   ; 53: LVO -318 WindowLimits(window a0, minW d0, minH d1, maxW d2, maxH d3)
        dc.l    intuition_SetPrefs       ; 54: LVO -324 SetPrefs(prefs a0, size d0, inform d1)
        dc.l    intuition_IntuiTextLength ; 55: LVO -330 IntuiTextLength(itext a0)
        dcb.l   2,intuition_null         ; 56..57: LVO -336..-342 (not impl.)
        dc.l    intuition_AutoRequest    ; 58: LVO -348 AutoRequest(window a0, body a1, yes a2, no a3, ...)
        dc.l    intuition_BeginRefresh   ; 59: LVO -354 BeginRefresh(window a0)
        dc.l    intuition_BuildSysRequest ; 60: LVO -360 BuildSysRequest(window a0, body a1, pos a2, neg a3, IDCMP d0, w d2, h d3)
        dc.l    intuition_EndRefresh     ; 61: LVO -366 EndRefresh(window a0, complete d0)
        dc.l    intuition_FreeSysRequest ; 62: LVO -372 FreeSysRequest(window a0)
        dc.l    intuition_null           ; 63: LVO -378 (not impl.)
        dc.l    intuition_RemakeDisplay  ; 64: LVO -384 RemakeDisplay()
        dc.l    intuition_RemakeDisplay  ; 65: LVO -390 RethinkDisplay()
        dc.l    intuition_AllocRemember  ; 66: LVO -396 AllocRemember(key a0, size d0, flags d1)
        dc.l    intuition_null           ; 67: LVO -402 AlohaWorkbench (not impl.)
        dc.l    intuition_FreeRemember   ; 68: LVO -408 FreeRemember(key a0, forget d0)
        dcb.l   2,intuition_null         ; 69..70: LVO -414..-420 (not impl.)
        dc.l    intuition_GetScreenData  ; 71: LVO -426 GetScreenData(buffer a0, size d0, type d1, screen a1)
        dc.l    intuition_RefreshGList   ; 72: LVO -432 RefreshGList(gadgets a0, window a1, requester a2, count d0)
        dc.l    intuition_AddGList       ; 73: LVO -438 AddGList(window a0, gadget a1, position d0, count d1, req a2)
        dc.l    intuition_RemoveGList    ; 74: LVO -444 RemoveGList(window a0, gadget a1, count d0)
        dcb.l   2,intuition_null         ; 75..76: LVO -450..-456 (not impl.)
        dc.l    intuition_ActivateGadget ; 77: LVO -462 ActivateGadget(gadget a0, window a1, requester a2)
        dc.l    intuition_NewModifyProp  ; 78: LVO -468 NewModifyProp(..., number of gadgets d5)
        dc.l    -1
intuition_datatab:
        dc.w    $E000,LN_TYPE,(NT_LIBRARY<<8)   ; INITBYTE(LN_TYPE, NT_LIBRARY)
        dc.w    $D000,LIB_VERSION,34            ; INITWORD(LIB_VERSION, 34)
        dc.b    0
        EVEN

; Open(lib a6): increments the open count, returns the base (OpenLibrary convention).
intuition_open:
        addq.w  #1,LIB_OPENCNT(a6)
        move.l  a6,d0
        rts
intuition_close:
        subq.w  #1,LIB_OPENCNT(a6)
        moveq   #0,d0
        rts
intuition_expunge:
        moveq   #0,d0               ; no expunge in this milestone (resident base)
        rts
intuition_null:
        moveq   #0,d0
        rts

; ViewAddress() (a6 = IntuitionBase) -> d0 = &ib_ViewLord (intuition's current View). AutoDoc: "View =
; ViewAddress()". No argument. The ViewLord is embedded in the base (offset IB_VIEWLORD) -> stable address.
intuition_ViewAddress:
        ifeq    M5I_BAD_VIEWADDR
        lea     IB_VIEWLORD(a6),a0
        move.l  a0,d0
        else
        moveq   #0,d0              ; RED M5I_BAD_VIEWADDR: ViewAddress broken -> M5I proof absent
        endc
        rts

; initFunc (D0=base, A0=segList, A6=ExecBase) -> D0=base. Sets the name (V34 quirk), keeps GfxBase
; (graphics.library, pri 65, is initialized before intuition, pri 10) and installs the pointer.
intuition_initfunc:
        move.l  a2,-(sp)
        move.l  d0,a2
        lea     intuition_name(pc),a0
        move.l  a0,LN_NAME(a2)
        lea     EB_LIBLIST(a6),a0
        lea     intuition_gfxname(pc),a1
        jsr     LVO_FINDNAME(a6)
        move.l  d0,IB_GFXBASE(a2)
        lea     EB_LIBLIST(a6),a0
        lea     intuition_layersname(pc),a1
        jsr     LVO_FINDNAME(a6)     ; layers.library (pri 31) is already initialized
        move.l  d0,IB_LAYERSBASE(a2)
        jsr     it_prefsinit         ; prefs.s: default Preferences (before the pointer, which takes its image from it)
        jsr     it_ptrinit           ; pointer.s: pointer sprite
        jsr     it_startinput
        move.l  a2,d0
        move.l  (sp)+,a2
        rts
intuition_gfxname:
        dc.b    "graphics.library",0
intuition_layersname:
        dc.b    "layers.library",0
        EVEN
intuition_end:
