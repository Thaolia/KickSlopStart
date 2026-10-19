; src/intuition/intuition.i — layout IntuitionBase V34 + constantes M5.
; Piste IMPLÉMENTATION (« clean ») : NDK intuition.i/intuitionbase.i + intuition_lib.fd (public). AUCUNE lecture ROM.
; LIB_SIZE est défini dans exec.i (inclus AVANT ce fichier).

; --- IntuitionBase : champs publics 1re génération (stables V34 ; intuitionbase.i) ---
; ib_LibNode = base Library ; ib_ViewLord = View embarqué d'intuition (le « ViewLord », renvoyé par ViewAddress).
IB_VIEWLORD      EQU LIB_SIZE          ; 34 : struct View embarquée (v_SIZEOF = 18)
IB_ACTIVEWINDOW  EQU IB_VIEWLORD+18    ; 52
IB_ACTIVESCREEN  EQU IB_ACTIVEWINDOW+4 ; 56
IB_FIRSTSCREEN   EQU IB_ACTIVESCREEN+4 ; 60 : Screen frontal (liste front->back)
IB_FLAGS         EQU IB_FIRSTSCREEN+4  ; 64
IB_MOUSEY        EQU IB_FLAGS+4        ; 68
IB_MOUSEX        EQU IB_MOUSEY+2       ; 70
IB_SECONDS       EQU IB_MOUSEX+2       ; 72
IB_MICROS        EQU IB_SECONDS+4      ; 76
; champs privés (au-delà de la partie publique) :
IB_GFXBASE       EQU IB_MICROS+4       ; 80 : GfxBase (trouvée à l'init)
IB_WBSCREEN      EQU IB_GFXBASE+4      ; 84 : écran Workbench ouvert (0 sinon)
INTUITIONBASE_SIZE EQU IB_WBSCREEN+4   ; 88 : dataSize pour MakeLibrary

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
; types / drapeaux d'écran
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
WD_TITLE        EQU 32
WD_WSCREEN      EQU 46
WD_RPORT        EQU 50
WD_BORDERLEFT   EQU 54
WD_BORDERTOP    EQU 55
WD_BORDERRIGHT  EQU 56
WD_BORDERBOTTOM EQU 57
WD_IDCMPFLAGS   EQU 82
WD_DETAILPEN    EQU 98
WD_BLOCKPEN     EQU 99
WD_GZZWIDTH     EQU 112
WD_GZZHEIGHT    EQU 114
WD_WLAYER       EQU 124
WD_SIZE         EQU 132
; drapeaux de fenêtre (wd_Flags)
WINDOWSIZING    EQU $0001
WINDOWDRAG      EQU $0002
WINDOWDEPTH     EQU $0004
WINDOWCLOSE     EQU $0008
SIZEBRIGHT      EQU $0010
SIZEBBOTTOM     EQU $0020
BACKDROP        EQU $0100
BORDERLESS      EQU $0800
WINDOWACTIVE    EQU $2000

; --- LVO intuition.library (lvo/intuition_lib.i, autoritatif) ---
LVO_VIEWADDRESS  EQU -294              ; ViewAddress() -> View courant (vecteur 49)
LVO_OPENWORKBENCH EQU -210             ; OpenWorkBench() -> Screen Workbench

; --- struct Gadget / struct Requester (NDK intuition/intuition.i) — requester insert-disk cliquable ---
GG_NEXTGADGET EQU 0
GG_LEFTEDGE   EQU 4             ; WORD (relatif au requester)
GG_TOPEDGE    EQU 6             ; WORD
GG_WIDTH      EQU 8             ; WORD
GG_HEIGHT     EQU 10            ; WORD
GG_FLAGS      EQU 12            ; UWORD
GG_ACTIVATION EQU 14           ; UWORD
GG_GADGETTYPE EQU 16           ; UWORD
GG_SIZEOF     EQU 44
BOOLGADGET    EQU 1             ; gg_GadgetType : bouton booléen
RQ_OLDERREQ   EQU 0
RQ_LEFTEDGE   EQU 4             ; WORD
RQ_TOPEDGE    EQU 6             ; WORD
RQ_WIDTH      EQU 8             ; WORD
RQ_HEIGHT     EQU 10            ; WORD
RQ_REQGADGET  EQU 16           ; APTR liste de gadgets
RQ_REQTEXT    EQU 24           ; APTR texte
RQ_SIZEOF     EQU 112
; REQ_NO_HITTEST=1 (RED requester) : req_input_handler ne fait PAS le hit-test -> un clic DANS le gadget ne pose pas
; REQ_HIT -> « REQUESTER CLICK OK » absent. Isole le hit-test du gadget. Défaut 0.
REQ_NO_HITTEST EQU 0

; M5 : intuition.library comme module résident (squelette + ViewAddress). M5I_BAD_VIEWADDR=1 (RED) : ViewAddress
; renvoie 0 au lieu de &ib_ViewLord -> la preuve « ViewAddress()==IntuitionBase+34 » échoue -> « M5I INTUI LIB OK »
; absent. Isole la primitive neuve (le routage NT_LIBRARY->LibList est déjà RED-prouvé par M4C1_WRONG_TYPE).
; Défaut 0 (inerte).
M5I_BAD_VIEWADDR EQU 0
