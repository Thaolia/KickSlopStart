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
IB_PTRSS         EQU IB_WBSCREEN+4     ; 88 : SimpleSprite du pointeur (canal 0)
IB_LAYERSBASE    EQU IB_PTRSS+12       ; 100 : LayersBase (trouvée à l'init)
; tâche d'entrée d'intuition : l'interruption souris dépose les boutons dans un anneau, la tâche les traite
IB_INTASK        EQU IB_LAYERSBASE+4   ; tâche d'entrée (0 tant qu'elle n'a pas son signal)
IB_INSIG         EQU IB_INTASK+4       ; masque du signal d'événement
IB_EVHEAD        EQU IB_INSIG+4        ; UWORD : prochaine case écrite (interruption)
IB_EVTAIL        EQU IB_EVHEAD+2       ; UWORD : prochaine case lue (tâche)
IB_EVRING        EQU IB_EVTAIL+2       ; IB_EVN cases de IB_EVSZ octets : code, x, y (écran)
IB_EVN           EQU 8
IB_EVSZ          EQU 6
IB_TRACK         EQU IB_EVRING+IB_EVN*IB_EVSZ ; BYTE : la tâche veut aussi les mouvements (glisser, menus)
IB_MOVED         EQU IB_TRACK+1        ; BYTE : mouvement à traiter
IB_DRAGWIN       EQU IB_MOVED+1        ; fenêtre en cours de déplacement / redimensionnement | 0
IB_DRAGMODE      EQU IB_DRAGWIN+4      ; UWORD : IT_DRAGMOVE / IT_DRAGSIZE
IB_DRAGSX        EQU IB_DRAGMODE+2     ; position du pointeur au début du geste (écran)
IB_DRAGSY        EQU IB_DRAGSX+2
IB_BOX           EQU IB_DRAGSY+2       ; cadre fantôme affiché : x0, y0, x1, y1
IB_BOXON         EQU IB_BOX+8          ; BYTE : cadre fantôme affiché
IB_MENUWIN       EQU IB_BOXON+2        ; fenêtre dont la barre de menus est affichée | 0
IB_MENUBAR       EQU IB_MENUWIN+4      ; couche de la barre de menus | 0
IB_MENUBOX       EQU IB_MENUBAR+4      ; couche du menu déroulé | 0
IB_MENUCUR       EQU IB_MENUBOX+4      ; Menu déroulé | 0
IB_ITEMCUR       EQU IB_MENUCUR+4      ; MenuItem en surbrillance | 0
IB_MENUNUM       EQU IB_ITEMCUR+4      ; UWORD : n° du menu déroulé
IB_ITEMNUM       EQU IB_MENUNUM+2      ; UWORD : n° de l'élément en surbrillance
IB_PICK          EQU IB_ITEMNUM+2      ; UWORD : code MENUPICK en construction
IB_GADACT        EQU IB_PICK+2         ; gadget d'application enfoncé (bouton gauche tenu) | 0
IB_GADWIN        EQU IB_GADACT+4       ; sa fenêtre
IB_STRGAD        EQU IB_GADWIN+4       ; gadget texte actif (reçoit le clavier) | 0
IB_STRWIN        EQU IB_STRGAD+4       ; sa fenêtre
IB_SYSACT        EQU IB_STRWIN+4       ; UWORD : gadget système enfoncé (IT_SYSCLOSE / BACK / FRONT) | 0
IB_SYSWIN        EQU IB_SYSACT+2       ; sa fenêtre
IB_PKX           EQU IB_SYSWIN+4       ; gadget proportionnel : knob (relatif au conteneur) pendant un glissement
IB_PKY           EQU IB_PKX+2
IB_PMX           EQU IB_PKY+2          ; dernière position du pointeur (écran) pendant le glissement
IB_PMY           EQU IB_PMX+2
IB_PREFS         EQU IB_PMY+2          ; Preferences courantes (PF_SIZE octets), lues par GetPrefs, posées par SetPrefs
IB_PREMX         EQU IB_PREFS+PF_SIZE  ; reste du mouvement souris par axe (division par PointerTicks)
IB_PREMY         EQU IB_PREMX+2
IB_PTRDATA       EQU IB_PREMY+2        ; données chip du sprite du pointeur par défaut | 0
IB_VINITX        EQU IB_PTRDATA+4      ; DxOffset / DyOffset de la vue à l'init (ViewInitX/Y des Preferences)
IB_VINITY        EQU IB_VINITX+2
IB_TATTR         EQU IB_VINITY+2       ; TextAttr de la police par défaut (topaz 8 ou 9 selon FontHeight)
INTUITIONBASE_SIZE EQU IB_TATTR+8
IT_SYSCLOSE      EQU 1
IT_SYSBACK       EQU 2
IT_SYSFRONT      EQU 3
IT_KEYCODE       EQU $0200             ; anneau d'entrée : code >= IT_KEYCODE = touche (keycode en bits 0-6), x = qualificatif
IT_TICKCODE      EQU $0400             ; anneau d'entrée : tic IECLASS_TIMER d'input.device (INTUITICKS)
IT_DISKINCODE    EQU $0401             ; anneau d'entrée : IECLASS_DISKINSERTED
IT_DISKOUTCODE   EQU $0402             ; anneau d'entrée : IECLASS_DISKREMOVED
IT_MENUKEYCODE   EQU $0403             ; anneau d'entrée : raccourci Amiga droite, x = code de menu, y = qualificatif
IT_DRAGMOVE      EQU 1
IT_DRAGSIZE      EQU 2

; --- layers.library (graphics/clip.h, layers.h ; LVO de l'AutoDoc) ---
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
IL_RP           EQU 12               ; struct Layer : RastPort
IL_MINX         EQU 16               ; bornes (coordonnées de l'écran)
IL_MINY         EQU 18
IL_MAXX         EQU 20
IL_MAXY         EQU 22
IL_FLAGS        EQU 30               ; Flags (UWORD)
IL_WINDOW       EQU 40               ; Window (réservé à l'interface utilisateur)
IL_LOCK         EQU 72               ; SignalSemaphore de la couche
IL_CLIPREGION   EQU 126              ; région de découpe de l'application (InstallClipRegion)
IL_DAMAGE       EQU 156              ; DamageList (struct Region *)
IL_SIMPLE       EQU 1                ; LAYERSIMPLE
IL_SMART        EQU 2                ; LAYERSMART
IL_SUPER        EQU 4                ; LAYERSUPER
IL_BACKDROP     EQU $40              ; LAYERBACKDROP
ILB_REFRESH     EQU 7                ; LAYERREFRESH (bit de l'octet bas de Flags)

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
WD_MENUSTRIP    EQU 28
WD_TITLE        EQU 32
WD_WSCREEN      EQU 46
WD_RPORT        EQU 50
WD_BORDERLEFT   EQU 54
WD_BORDERTOP    EQU 55
WD_BORDERRIGHT  EQU 56
WD_BORDERBOTTOM EQU 57
WD_BORDERRPORT  EQU 58              ; GIMMEZEROZERO : RastPort de la couche du cadre (0 sinon)
WD_FIRSTGADGET  EQU 62
WD_PARENT       EQU 66              ; fenêtre active à l'ouverture (activée à la fermeture de celle-ci)
WD_DESCENDANT   EQU 70
WD_IDCMPFLAGS   EQU 82
WD_USERPORT     EQU 86
WD_DETAILPEN    EQU 98
WD_BLOCKPEN     EQU 99
WD_CHECKMARK    EQU 100             ; Image de la coche des menus (NewWindow.CheckMark, sinon l'interne)
WD_SCREENTITLE  EQU 104             ; titre d'écran montré quand la fenêtre est active (0 : celui de l'écran)
WD_GZZWIDTH     EQU 112
WD_GZZHEIGHT    EQU 114
WD_USERDATA     EQU 120              ; UserData (le WB y garde les vrais dommages, spec wb-icon-clipping-v34 §1)
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
GIMMEZEROZERO   EQU $0400           ; NewWindow : intérieur dans sa propre couche, origine dans l'intérieur
ACTIVATE        EQU $1000           ; NewWindow : fenêtre activée à l'ouverture
WINDOWACTIVE    EQU $2000
RMBTRAP         EQU $00010000

; --- struct Preferences V34 (intuition/preferences.h, 232 octets) : champs utilisés ---
PF_FONTHEIGHT   EQU $00
PF_KEYRPTSPEED  EQU $04                ; timeval : période de répétition des touches
PF_KEYRPTDELAY  EQU $0C                ; timeval : délai avant la 1re répétition
PF_DBLCLICK     EQU $14                ; timeval : secondes, microsecondes
PF_PTRMATRIX    EQU $1C                ; 36 mots : POS, CTL, 16 lignes (2 plans), 0, 0
PF_XOFFSET      EQU $64                ; octets signés : décalage de l'image par rapport au point chaud
PF_YOFFSET      EQU $65
PF_COLOR17      EQU $66                ; couleurs 17..19 (pointeur)
PF_PTRTICKS     EQU $6C
PF_COLOR0       EQU $6E                ; couleurs 0..3 (Workbench)
PF_VIEWXOFF     EQU $76                ; octets signés
PF_VIEWYOFF     EQU $77
PF_VIEWINITX    EQU $78
PF_VIEWINITY    EQU $7A
PF_EXTSIZE      EQU $E7
PF_SIZE         EQU 232
PF_VIEWEND      EQU PF_VIEWINITY+2     ; taille minimale pour que ViewInitX/Y soient copiés
SC_BGCOLOR      EQU $7C3               ; couleur 0 : vert pomme (thème AmigaSlopDOS, défaut des Preferences)

; --- struct IntuiMessage (intuition/intuition.h) et classes IDCMP ---
IM_CLASS        EQU 20               ; après la struct Message
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
REPORTMOUSE     EQU $00000200       ; WD_FLAGS : la fenêtre reçoit les mouvements (MOUSEMOVE)
MENUPICK        EQU $00000100
CLOSEWINDOW     EQU $00000200
RAWKEY          EQU $00000400
NEWPREFS        EQU $00004000
DISKINSERTED    EQU $00008000           ; une disquette a été insérée (toutes les fenêtres qui le demandent)
DISKREMOVED     EQU $00010000
INTUITICKS      EQU $00400000           ; ~10 par seconde à la fenêtre active, un seul en circulation
MENUNULL        EQU $FFFF
SELECTDOWN      EQU $68                ; im_Code de MOUSEBUTTONS
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
GG_GADGETRENDER EQU 18         ; APTR Border ou Image (GADGIMAGE)
GG_SELECTRENDER EQU 22         ; APTR : rendu sélectionné (GADGHIMAGE)
GG_GADGETTEXT EQU 26           ; APTR IntuiText
GG_SPECIALINFO EQU 34          ; APTR : StringInfo d'un STRGADGET
GG_GADGETID   EQU 38           ; UWORD
GG_SIZEOF     EQU 44
; gg_Flags
GADGHIGHBITS  EQU $0003        ; GADGHCOMP 0 / GADGHBOX 1 / GADGHIMAGE 2 / GADGHNONE 3
GADGHBOX      EQU $0001
GADGHIMAGE    EQU $0002
GADGIMAGE     EQU $0004        ; GadgetRender est une Image (sinon une Border)
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
LONGINT       EQU $0800        ; STRGADGET : entier, converti dans si_LongInt
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
BOOLGADGET    EQU 1             ; gg_GadgetType : bouton booléen
STRGADGET     EQU 4             ; gg_GadgetType : texte éditable (SpecialInfo = StringInfo)
PROPGADGET    EQU 3             ; gg_GadgetType : proportionnel (SpecialInfo = PropInfo)
FOLLOWMOUSE   EQU $0008         ; gg_Activation : MOUSEMOVE pendant que le gadget est tenu
PI_FLAGS      EQU 0             ; struct PropInfo (V34, 22 octets)
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
GTYP_MASK     EQU $0007         ; type de base dans gg_GadgetType
GZZGADGET     EQU $2000         ; gg_GadgetType : gadget du cadre d'une fenêtre GIMMEZEROZERO
; struct StringInfo (intuition/intuition.h)
SI_BUFFER     EQU 0             ; APTR : texte, terminé par NUL
SI_UNDOBUFFER EQU 4             ; APTR : copie à l'activation (Amiga droite + Q) | 0
SI_BUFFERPOS  EQU 8             ; WORD : position du curseur
SI_MAXCHARS   EQU 10            ; WORD : taille du tampon, NUL compris
SI_DISPPOS    EQU 12            ; WORD : premier caractère affiché
SI_UNDOPOS    EQU 14
SI_NUMCHARS   EQU 16
SI_DISPCOUNT  EQU 18            ; WORD : caractères visibles
SI_LONGINT    EQU 28            ; LONG : valeur d'un gadget LONGINT
LVO_ACTIVATEGADGET EQU -462
RQ_OLDERREQ   EQU 0
RQ_LEFTEDGE   EQU 4             ; WORD
RQ_TOPEDGE    EQU 6             ; WORD
RQ_WIDTH      EQU 8             ; WORD
RQ_HEIGHT     EQU 10            ; WORD
RQ_RELLEFT    EQU 12            ; WORD (POINTREL : double-menu)
RQ_RELTOP     EQU 14            ; WORD
RQ_REQGADGET  EQU 16           ; APTR liste de gadgets
RQ_REQBORDER  EQU 20           ; APTR Border
RQ_REQTEXT    EQU 24           ; APTR texte
RQ_FLAGS      EQU 28           ; UWORD
RQ_BACKFILL   EQU 30           ; UBYTE : stylo du fond
RQ_REQLAYER   EQU 32           ; APTR couche du requester
RQ_IMAGEBMAP  EQU 68           ; APTR BitMap (PREDRAWN)
RQ_RWINDOW    EQU 72           ; APTR fenêtre
RQ_SIZEOF     EQU 112
PREDRAWN      EQU $0002         ; RQ_FLAGS : ImageBMap recopié au lieu du dessin
NOISYREQ      EQU $0004         ; RQ_FLAGS : les événements continuent d'aller à la fenêtre
REQACTIVE     EQU $2000         ; RQ_FLAGS : affiché
REQGADGET     EQU $1000         ; gg_GadgetType : gadget d'un requester
ENDGADGET     EQU $0004         ; gg_Activation : son relâchement termine le requester
WD_FIRSTREQUEST EQU 36          ; struct Window
WD_DMREQUEST  EQU 40
WD_REQCOUNT   EQU 44            ; WORD
INREQUEST     EQU $00004000     ; WD_FLAGS : au moins un requester
MENUSTATE     EQU $00008000     ; WD_FLAGS : menus en cours
REQSET        EQU $00000080     ; IDCMP
REQCLEAR      EQU $00001000
; REQ_NO_HITTEST=1 (RED requester) : req_input_handler ne fait PAS le hit-test -> un clic DANS le gadget ne pose pas
; REQ_HIT -> « REQUESTER CLICK OK » absent. Isole le hit-test du gadget. Défaut 0.
REQ_NO_HITTEST EQU 0

; M5 : intuition.library comme module résident (squelette + ViewAddress). M5I_BAD_VIEWADDR=1 (RED) : ViewAddress
; renvoie 0 au lieu de &ib_ViewLord -> la preuve « ViewAddress()==IntuitionBase+34 » échoue -> « M5I INTUI LIB OK »
; absent. Isole la primitive neuve (le routage NT_LIBRARY->LibList est déjà RED-prouvé par M4C1_WRONG_TYPE).
; Défaut 0 (inerte).
M5I_BAD_VIEWADDR EQU 0
