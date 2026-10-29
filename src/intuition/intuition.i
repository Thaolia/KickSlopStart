; src/intuition/intuition.i - IntuitionBase V34 layout + M5 constants.
; IMPLEMENTATION track ("clean"): NDK intuition.i/intuitionbase.i + intuition_lib.fd (public). NO ROM reading.
; LIB_SIZE is defined in exec.i (included BEFORE this file).

; --- IntuitionBase: 1st-generation public fields (stable in V34; intuitionbase.i) ---
; ib_LibNode = Library base; ib_ViewLord = intuition's embedded View (the "ViewLord", returned by ViewAddress).
IB_VIEWLORD      EQU LIB_SIZE          ; 34: embedded struct View (v_SIZEOF = 18)
IB_ACTIVEWINDOW  EQU IB_VIEWLORD+18    ; 52
IB_ACTIVESCREEN  EQU IB_ACTIVEWINDOW+4 ; 56
IB_FIRSTSCREEN   EQU IB_ACTIVESCREEN+4 ; 60: front Screen (front->back list)
IB_FLAGS         EQU IB_FIRSTSCREEN+4  ; 64
IB_MOUSEY        EQU IB_FLAGS+4        ; 68
IB_MOUSEX        EQU IB_MOUSEY+2       ; 70
IB_SECONDS       EQU IB_MOUSEX+2       ; 72
IB_MICROS        EQU IB_SECONDS+4      ; 76
; private fields (beyond the public part):
IB_GFXBASE       EQU IB_MICROS+4       ; 80: GfxBase (found at init)
IB_WBSCREEN      EQU IB_GFXBASE+4      ; 84: open Workbench screen (0 otherwise)
IB_PTRSS         EQU IB_WBSCREEN+4     ; 88: pointer SimpleSprite (channel 0)
IB_LAYERSBASE    EQU IB_PTRSS+12       ; 100: LayersBase (found at init)
; intuition input task: the mouse interrupt drops the buttons into a ring, the task processes them
IB_INTASK        EQU IB_LAYERSBASE+4   ; input task (0 until it has its signal)
IB_INSIG         EQU IB_INTASK+4       ; event signal mask
IB_EVHEAD        EQU IB_INSIG+4        ; UWORD: next slot written (interrupt)
IB_EVTAIL        EQU IB_EVHEAD+2       ; UWORD: next slot read (task)
IB_EVRING        EQU IB_EVTAIL+2       ; IB_EVN slots of IB_EVSZ bytes: code, x, y (screen)
IB_EVN           EQU 8
IB_EVSZ          EQU 6
IB_TRACK         EQU IB_EVRING+IB_EVN*IB_EVSZ ; BYTE: the task also wants the movements (drag, menus)
IB_MOVED         EQU IB_TRACK+1        ; BYTE: movement to process
IB_DRAGWIN       EQU IB_MOVED+1        ; window being moved / resized | 0
IB_DRAGMODE      EQU IB_DRAGWIN+4      ; UWORD: IT_DRAGMOVE / IT_DRAGSIZE
IB_DRAGSX        EQU IB_DRAGMODE+2     ; pointer position at the start of the gesture (screen)
IB_DRAGSY        EQU IB_DRAGSX+2
IB_BOX           EQU IB_DRAGSY+2       ; ghost frame displayed: x0, y0, x1, y1
IB_BOXON         EQU IB_BOX+8          ; BYTE: ghost frame displayed
IB_MENUWIN       EQU IB_BOXON+2        ; window whose menu bar is displayed | 0
IB_MENUBAR       EQU IB_MENUWIN+4      ; layer of the menu bar | 0
IB_MENUBOX       EQU IB_MENUBAR+4      ; layer of the pulled-down menu | 0
IB_MENUCUR       EQU IB_MENUBOX+4      ; pulled-down Menu | 0
IB_ITEMCUR       EQU IB_MENUCUR+4      ; highlighted MenuItem | 0
IB_MENUNUM       EQU IB_ITEMCUR+4      ; UWORD: number of the pulled-down menu
IB_ITEMNUM       EQU IB_MENUNUM+2      ; UWORD: number of the highlighted item
IB_PICK          EQU IB_ITEMNUM+2      ; UWORD: MENUPICK code being built
IB_GADACT        EQU IB_PICK+2         ; pressed application gadget (left button held) | 0
IB_GADWIN        EQU IB_GADACT+4       ; its window
IB_STRGAD        EQU IB_GADWIN+4       ; active text gadget (receives the keyboard) | 0
IB_STRWIN        EQU IB_STRGAD+4       ; its window
IB_SYSACT        EQU IB_STRWIN+4       ; UWORD: pressed system gadget (IT_SYSCLOSE / BACK / FRONT) | 0
IB_SYSWIN        EQU IB_SYSACT+2       ; its window
IB_PKX           EQU IB_SYSWIN+4       ; proportional gadget: knob (relative to the container) during a drag
IB_PKY           EQU IB_PKX+2
IB_PMX           EQU IB_PKY+2          ; last pointer position (screen) during the drag
IB_PMY           EQU IB_PMX+2
IB_PREFS         EQU IB_PMY+2          ; current Preferences (PF_SIZE bytes), read by GetPrefs, set by SetPrefs
IB_PREMX         EQU IB_PREFS+PF_SIZE  ; remainder of the mouse movement per axis (division by PointerTicks)
IB_PREMY         EQU IB_PREMX+2
IB_PTRDATA       EQU IB_PREMY+2        ; chip data of the default pointer sprite | 0
IB_VINITX        EQU IB_PTRDATA+4      ; DxOffset / DyOffset of the view at init (ViewInitX/Y of the Preferences)
IB_VINITY        EQU IB_VINITX+2
IB_TATTR         EQU IB_VINITY+2       ; TextAttr of the default font (topaz 8 or 9 depending on FontHeight)
IB_SUBBOX        EQU IB_TATTR+8        ; layer of the sub-item box | 0
IB_SUBITEM       EQU IB_SUBBOX+4       ; item whose sub-items are displayed | 0
IB_SUBCUR        EQU IB_SUBITEM+4      ; highlighted sub-item | 0
IB_ITEMHIT       EQU IB_SUBCUR+4       ; item under the pointer, enabled or not | 0
IB_SUBNUM        EQU IB_ITEMHIT+4      ; UWORD: number of the highlighted sub-item
IB_SUBPNUM       EQU IB_SUBNUM+2       ; UWORD: number of the IB_SUBITEM item
IB_SUBLX         EQU IB_SUBPNUM+2      ; screen position of the sub-item box
IB_SUBLY         EQU IB_SUBLX+2
IB_SUBOX         EQU IB_SUBLY+2        ; origin of the sub-items in this box
IB_SUBOY         EQU IB_SUBOX+2
IB_DOX           EQU IB_SUBOY+2        ; origin of the items in the box being drawn (mn_drawitems)
IB_DOY           EQU IB_DOX+2
IB_DGHOST        EQU IB_DOY+2          ; BYTE: box being drawn entirely ghosted (menu or parent item disabled)
INTUITIONBASE_SIZE EQU IB_DGHOST+2
IT_SYSCLOSE      EQU 1
IT_SYSBACK       EQU 2
IT_SYSFRONT      EQU 3
IT_KEYCODE       EQU $0200             ; input ring: code >= IT_KEYCODE = key (keycode in bits 0-6), x = qualifier
IT_TICKCODE      EQU $0400             ; input ring: IECLASS_TIMER tick from input.device (INTUITICKS)
IT_DISKINCODE    EQU $0401             ; input ring: IECLASS_DISKINSERTED
IT_DISKOUTCODE   EQU $0402             ; input ring: IECLASS_DISKREMOVED
IT_MENUKEYCODE   EQU $0403             ; input ring: right Amiga shortcut, x = menu code, y = qualifier
IT_DRAGMOVE      EQU 1
IT_DRAGSIZE      EQU 2

; --- layers.library (graphics/clip.h, layers.h; LVOs from the AutoDoc) ---
LVO_INITLAYERS          EQU -30
LVO_CREATEUPFRONTLAYER  EQU -36
LVO_CREATEBEHINDLAYER   EQU -42
LVO_UPFRONTLAYER        EQU -48
LVO_BEHINDLAYER         EQU -54
LVO_MOVELAYER           EQU -60
LVO_SIZELAYER           EQU -66
LVO_MOVELAYERINFRONTOF  EQU -168
LVO_BEGINUPDATE         EQU -78
LVO_ENDUPDATE           EQU -84
LVO_INSTALLCLIPREGION   EQU -174
LVO_DELETELAYER         EQU -90
LVO_LOCKLAYERS          EQU -108
LVO_UNLOCKLAYERS        EQU -114
IL_RP           EQU 12               ; struct Layer: RastPort
IL_MINX         EQU 16               ; bounds (screen coordinates)
IL_MINY         EQU 18
IL_MAXX         EQU 20
IL_MAXY         EQU 22
IL_FLAGS        EQU 30               ; Flags (UWORD)
IL_WINDOW       EQU 40               ; Window (reserved for the user interface)
IL_LOCK         EQU 72               ; SignalSemaphore of the layer
IL_CLIPREGION   EQU 126              ; application clip region (InstallClipRegion)
IL_DAMAGE       EQU 156              ; DamageList (struct Region *)
IL_SIMPLE       EQU 1                ; LAYERSIMPLE
IL_SMART        EQU 2                ; LAYERSMART
IL_SUPER        EQU 4                ; LAYERSUPER
IL_BACKDROP     EQU $40              ; LAYERBACKDROP
ILB_REFRESH     EQU 7                ; LAYERREFRESH (bit of the low byte of Flags)

; --- struct NewScreen / struct Screen (intuition/screens.h V34) ---
NS_LEFTEDGE     EQU 0
NS_TOPEDGE      EQU 2
NS_WIDTH        EQU 4
NS_HEIGHT       EQU 6
NS_DEPTH        EQU 8
NS_DETAILPEN    EQU 10
NS_BLOCKPEN     EQU 11
NS_VIEWMODES    EQU 12
NS_TYPE         EQU 14
NS_FONT         EQU 16
NS_DEFAULTTITLE EQU 20
NS_GADGETS      EQU 24
NS_CUSTOMBITMAP EQU 28
SC_NEXTSCREEN   EQU 0
SC_FIRSTWINDOW  EQU 4
SC_LEFTEDGE     EQU 8
SC_TOPEDGE      EQU 10
SC_WIDTH        EQU 12
SC_HEIGHT       EQU 14
SC_MOUSEY       EQU 16
SC_MOUSEX       EQU 18
SC_FLAGS        EQU 20
SC_TITLE        EQU 22
SC_DEFAULTTITLE EQU 26
SC_BARHEIGHT    EQU 30
SC_BARVBORDER   EQU 31
SC_BARHBORDER   EQU 32
SC_MENUVBORDER  EQU 33
SC_MENUHBORDER  EQU 34
SC_WBORTOP      EQU 35
SC_WBORLEFT     EQU 36
SC_WBORRIGHT    EQU 37
SC_WBORBOTTOM   EQU 38
SC_FONT         EQU 40
SC_VIEWPORT     EQU 44
SC_RASTPORT     EQU 84
SC_BITMAP       EQU 184
SC_LAYERINFO    EQU 224
SC_FIRSTGADGET  EQU 326
SC_DETAILPEN    EQU 330
SC_BLOCKPEN     EQU 331
SC_SAVECOLOR0   EQU 332
SC_BARLAYER     EQU 334
SC_EXTDATA      EQU 338
SC_USERDATA     EQU 342
SC_SIZEOF       EQU 346
; screen types / flags
WBENCHSCREEN    EQU $0001
CUSTOMSCREEN    EQU $000F
SCREENTYPE      EQU $000F
SHOWTITLE       EQU $0010
SCREENQUIET     EQU $0100
CUSTOMBITMAP    EQU $0040

; --- struct NewWindow / struct Window (intuition/intuition.h V34) ---
NW_LEFTEDGE     EQU 0
NW_TOPEDGE      EQU 2
NW_WIDTH        EQU 4
NW_HEIGHT       EQU 6
NW_DETAILPEN    EQU 8
NW_BLOCKPEN     EQU 9
NW_IDCMPFLAGS   EQU 10
NW_FLAGS        EQU 14
NW_FIRSTGADGET  EQU 18
NW_CHECKMARK    EQU 22
NW_TITLE        EQU 26
NW_SCREEN       EQU 30
NW_BITMAP       EQU 34
NW_MINWIDTH     EQU 38
NW_MINHEIGHT    EQU 40
NW_MAXWIDTH     EQU 42
NW_MAXHEIGHT    EQU 44
NW_TYPE         EQU 46
WD_NEXTWINDOW   EQU 0
WD_LEFTEDGE     EQU 4
WD_TOPEDGE      EQU 6
WD_WIDTH        EQU 8
WD_HEIGHT       EQU 10
WD_MINWIDTH     EQU 16
WD_MINHEIGHT    EQU 18
WD_MAXWIDTH     EQU 20
WD_MAXHEIGHT    EQU 22
WD_FLAGS        EQU 24
WD_MENUSTRIP    EQU 28
WD_TITLE        EQU 32
WD_WSCREEN      EQU 46
WD_RPORT        EQU 50
WD_BORDERLEFT   EQU 54
WD_BORDERTOP    EQU 55
WD_BORDERRIGHT  EQU 56
WD_BORDERBOTTOM EQU 57
WD_BORDERRPORT  EQU 58              ; GIMMEZEROZERO: RastPort of the border layer (0 otherwise)
WD_FIRSTGADGET  EQU 62
WD_PARENT       EQU 66              ; window active at open time (activated when this one closes)
WD_DESCENDANT   EQU 70
WD_IDCMPFLAGS   EQU 82
WD_USERPORT     EQU 86
WD_DETAILPEN    EQU 98
WD_BLOCKPEN     EQU 99
WD_CHECKMARK    EQU 100             ; menu check mark Image (NewWindow.CheckMark, otherwise the internal one)
WD_SCREENTITLE  EQU 104             ; screen title shown when the window is active (0: the screen's own)
WD_GZZWIDTH     EQU 112
WD_GZZHEIGHT    EQU 114
WD_USERDATA     EQU 120              ; UserData (the WB keeps the real damage there, spec wb-icon-clipping-v34 §1)
WD_WLAYER       EQU 124
WD_SIZE         EQU 132
; window flags (wd_Flags)
WINDOWSIZING    EQU $0001
WINDOWDRAG      EQU $0002
WINDOWDEPTH     EQU $0004
WINDOWCLOSE     EQU $0008
SIZEBRIGHT      EQU $0010
SIZEBBOTTOM     EQU $0020
BACKDROP        EQU $0100
BORDERLESS      EQU $0800
GIMMEZEROZERO   EQU $0400           ; NewWindow: interior in its own layer, origin in the interior
ACTIVATE        EQU $1000           ; NewWindow: window activated at open time
WINDOWACTIVE    EQU $2000
RMBTRAP         EQU $00010000

; --- struct Preferences V34 (intuition/preferences.h, 232 bytes): fields used ---
PF_FONTHEIGHT   EQU $00
PF_KEYRPTSPEED  EQU $04                ; timeval: key repeat period
PF_KEYRPTDELAY  EQU $0C                ; timeval: delay before the 1st repeat
PF_DBLCLICK     EQU $14                ; timeval: seconds, microseconds
PF_PTRMATRIX    EQU $1C                ; 36 words: POS, CTL, 16 lines (2 planes), 0, 0
PF_XOFFSET      EQU $64                ; signed bytes: image offset relative to the hot spot
PF_YOFFSET      EQU $65
PF_COLOR17      EQU $66                ; colors 17..19 (pointer)
PF_PTRTICKS     EQU $6C
PF_COLOR0       EQU $6E                ; colors 0..3 (Workbench)
PF_VIEWXOFF     EQU $76                ; signed bytes
PF_VIEWYOFF     EQU $77
PF_VIEWINITX    EQU $78
PF_VIEWINITY    EQU $7A
PF_EXTSIZE      EQU $E7
PF_SIZE         EQU 232
PF_VIEWEND      EQU PF_VIEWINITY+2     ; minimum size for ViewInitX/Y to be copied
SC_BGCOLOR      EQU $7C3               ; color 0: apple green (AmigaSlopDOS theme, Preferences default)

; --- struct IntuiMessage (intuition/intuition.h) and IDCMP classes ---
IM_CLASS        EQU 20               ; after the struct Message
IM_CODE         EQU 24
IM_QUALIFIER    EQU 26
IM_IADDRESS     EQU 28
IM_MOUSEX       EQU 32
IM_MOUSEY       EQU 34
IM_SECONDS      EQU 36
IM_MICROS       EQU 40
IM_IDCMPWINDOW  EQU 44
IM_SIZEOF       EQU 52
NEWSIZE         EQU $00000002
REFRESHWINDOW   EQU $00000004
MOUSEBUTTONS    EQU $00000008
MOUSEMOVE       EQU $00000010
GADGETDOWN      EQU $00000020
GADGETUP        EQU $00000040
REPORTMOUSE     EQU $00000200       ; WD_FLAGS: the window receives the movements (MOUSEMOVE)
MENUPICK        EQU $00000100
CLOSEWINDOW     EQU $00000200
RAWKEY          EQU $00000400
NEWPREFS        EQU $00004000
DISKINSERTED    EQU $00008000           ; a floppy disk was inserted (all windows that ask for it)
DISKREMOVED     EQU $00010000
INTUITICKS      EQU $00400000           ; ~10 per second to the active window, only one in circulation
MENUNULL        EQU $FFFF
SELECTDOWN      EQU $68                ; im_Code of MOUSEBUTTONS
SELECTUP        EQU $E8

; --- struct Menu / struct MenuItem / struct IntuiText (intuition/intuition.h) ---
MU_NEXTMENU     EQU 0
MU_LEFTEDGE     EQU 4
MU_TOPEDGE      EQU 6
MU_WIDTH        EQU 8
MU_HEIGHT       EQU 10
MU_FLAGS        EQU 12
MU_MENUNAME     EQU 14
MU_FIRSTITEM    EQU 18
MENUENABLED     EQU $0001
MI_NEXTITEM     EQU 0
MI_LEFTEDGE     EQU 4
MI_TOPEDGE      EQU 6
MI_WIDTH        EQU 8
MI_HEIGHT       EQU 10
MI_FLAGS        EQU 12
MI_ITEMFILL     EQU 18
MI_SELECTFILL   EQU 22
MI_SUBITEM      EQU 28
MI_NEXTSELECT   EQU 32
CHECKIT         EQU $0001
ITEMTEXT        EQU $0002
MENUTOGGLE      EQU $0008
ITEMENABLED     EQU $0010
HIGHFLAGS       EQU $00C0
HIGHNONE        EQU $00C0
CHECKED         EQU $0100
IT_FRONTPEN     EQU 0
IT_BACKPEN      EQU 1
IT_DRAWMODE     EQU 2
IT_LEFTEDGE     EQU 4
IT_TOPEDGE      EQU 6
IT_ITEXTFONT    EQU 8
IT_ITEXT        EQU 12
IT_NEXTTEXT     EQU 16
IT_SIZEOF       EQU 20
LVO_AUTOREQUEST EQU -348

; --- struct Image et struct Remember (intuition/intuition.h) ---
IG_LEFTEDGE     EQU 0
IG_TOPEDGE      EQU 2
IG_WIDTH        EQU 4
IG_HEIGHT       EQU 6
IG_DEPTH        EQU 8
IG_IMAGEDATA    EQU 10
IG_PLANEPICK    EQU 14
IG_PLANEONOFF   EQU 15
IG_NEXTIMAGE    EQU 16
RM_NEXTREMEMBER EQU 0
RM_REMEMBERSIZE EQU 4
RM_MEMORY       EQU 8
RM_SIZEOF       EQU 12

; --- intuition.library LVOs (lvo/intuition_lib.i, authoritative) ---
LVO_VIEWADDRESS  EQU -294              ; ViewAddress() -> current View (vector 49)
LVO_OPENWORKBENCH EQU -210             ; OpenWorkBench() -> Workbench Screen

; --- struct Gadget / struct Requester (NDK intuition/intuition.i) - clickable insert-disk requester ---
GG_NEXTGADGET EQU 0
GG_LEFTEDGE   EQU 4             ; WORD (relative to the requester)
GG_TOPEDGE    EQU 6             ; WORD
GG_WIDTH      EQU 8             ; WORD
GG_HEIGHT     EQU 10            ; WORD
GG_FLAGS      EQU 12            ; UWORD
GG_ACTIVATION EQU 14           ; UWORD
GG_GADGETTYPE EQU 16           ; UWORD
GG_GADGETRENDER EQU 18         ; APTR Border or Image (GADGIMAGE)
GG_SELECTRENDER EQU 22         ; APTR: selected rendering (GADGHIMAGE)
GG_GADGETTEXT EQU 26           ; APTR IntuiText
GG_SPECIALINFO EQU 34          ; APTR: StringInfo of a STRGADGET
GG_GADGETID   EQU 38           ; UWORD
GG_SIZEOF     EQU 44
; gg_Flags
GADGHIGHBITS  EQU $0003        ; GADGHCOMP 0 / GADGHBOX 1 / GADGHIMAGE 2 / GADGHNONE 3
GADGHBOX      EQU $0001
GADGHIMAGE    EQU $0002
GADGIMAGE     EQU $0004        ; GadgetRender is an Image (otherwise a Border)
GRELBOTTOM    EQU $0008
GRELRIGHT     EQU $0010
GRELWIDTH     EQU $0020
GRELHEIGHT    EQU $0040
SELECTED      EQU $0080
GADGDISABLED  EQU $0100
; gg_Activation
RELVERIFY     EQU $0001
GADGIMMEDIATE EQU $0002
TOGGLESELECT  EQU $0100
LONGINT       EQU $0800        ; STRGADGET: integer, converted into si_LongInt
; gg_GadgetType
SYSGADGET     EQU $8000
; struct Border (intuition/intuition.h)
BD_LEFTEDGE   EQU 0
BD_TOPEDGE    EQU 2
BD_FRONTPEN   EQU 4
BD_DRAWMODE   EQU 6
BD_COUNT      EQU 7
BD_XY         EQU 8
BD_NEXTBORDER EQU 12
BOOLGADGET    EQU 1             ; gg_GadgetType: boolean button
STRGADGET     EQU 4             ; gg_GadgetType: editable text (SpecialInfo = StringInfo)
PROPGADGET    EQU 3             ; gg_GadgetType: proportional (SpecialInfo = PropInfo)
FOLLOWMOUSE   EQU $0008         ; gg_Activation: MOUSEMOVE while the gadget is held
PI_FLAGS      EQU 0             ; struct PropInfo (V34, 22 bytes)
PI_HPOT       EQU 2
PI_VPOT       EQU 4
PI_HBODY      EQU 6
PI_VBODY      EQU 8
PI_CWIDTH     EQU 10
PI_CHEIGHT    EQU 12
PI_HPOTRES    EQU 14
PI_VPOTRES    EQU 16
PI_LBORDER    EQU 18
PI_TBORDER    EQU 20
AUTOKNOB      EQU $0001         ; pi_Flags
FREEHORIZ     EQU $0002
FREEVERT      EQU $0004
PROPBORDERLESS EQU $0008
KNOBHIT       EQU $0100
GTYP_MASK     EQU $0007         ; base type in gg_GadgetType
GZZGADGET     EQU $2000         ; gg_GadgetType: border gadget of a GIMMEZEROZERO window
; struct StringInfo (intuition/intuition.h)
SI_BUFFER     EQU 0             ; APTR: text, NUL-terminated
SI_UNDOBUFFER EQU 4             ; APTR: copy at activation (right Amiga + Q) | 0
SI_BUFFERPOS  EQU 8             ; WORD: cursor position
SI_MAXCHARS   EQU 10            ; WORD: buffer size, NUL included
SI_DISPPOS    EQU 12            ; WORD: first displayed character
SI_UNDOPOS    EQU 14
SI_NUMCHARS   EQU 16
SI_DISPCOUNT  EQU 18            ; WORD: visible characters
SI_LONGINT    EQU 28            ; LONG: value of a LONGINT gadget
LVO_ACTIVATEGADGET EQU -462
RQ_OLDERREQ   EQU 0
RQ_LEFTEDGE   EQU 4             ; WORD
RQ_TOPEDGE    EQU 6             ; WORD
RQ_WIDTH      EQU 8             ; WORD
RQ_HEIGHT     EQU 10            ; WORD
RQ_RELLEFT    EQU 12            ; WORD (POINTREL: double-menu)
RQ_RELTOP     EQU 14            ; WORD
RQ_REQGADGET  EQU 16           ; APTR gadget list
RQ_REQBORDER  EQU 20           ; APTR Border
RQ_REQTEXT    EQU 24           ; APTR text
RQ_FLAGS      EQU 28           ; UWORD
RQ_BACKFILL   EQU 30           ; UBYTE: background pen
RQ_REQLAYER   EQU 32           ; APTR requester layer
RQ_IMAGEBMAP  EQU 68           ; APTR BitMap (PREDRAWN)
RQ_RWINDOW    EQU 72           ; APTR window
RQ_SIZEOF     EQU 112
PREDRAWN      EQU $0002         ; RQ_FLAGS: ImageBMap copied instead of drawing
NOISYREQ      EQU $0004         ; RQ_FLAGS: events keep going to the window
REQACTIVE     EQU $2000         ; RQ_FLAGS: displayed
REQGADGET     EQU $1000         ; gg_GadgetType: gadget of a requester
ENDGADGET     EQU $0004         ; gg_Activation: its release ends the requester
WD_FIRSTREQUEST EQU 36          ; struct Window
WD_DMREQUEST  EQU 40
WD_REQCOUNT   EQU 44            ; WORD
INREQUEST     EQU $00004000     ; WD_FLAGS: at least one requester
MENUSTATE     EQU $00008000     ; WD_FLAGS: menus in progress
REQSET        EQU $00000080     ; IDCMP
REQCLEAR      EQU $00001000
; REQ_NO_HITTEST=1 (RED requester): req_input_handler does NOT do the hit-test -> a click INSIDE the gadget does not set
; REQ_HIT -> "REQUESTER CLICK OK" absent. Isolates the gadget hit-test. Default 0.
REQ_NO_HITTEST EQU 0

; M5: intuition.library as a resident module (skeleton + ViewAddress). M5I_BAD_VIEWADDR=1 (RED): ViewAddress
; returns 0 instead of &ib_ViewLord -> the "ViewAddress()==IntuitionBase+34" proof fails -> "M5I INTUI LIB OK"
; absent. Isolates the new primitive (the NT_LIBRARY->LibList routing is already RED-proven by M4C1_WRONG_TYPE).
; Default 0 (inert).
M5I_BAD_VIEWADDR EQU 0
