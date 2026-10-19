; src/intuition/intuition_lib.s — intuition.library (M5 : squelette résident + ViewAddress).
; Calqué sur graphics_lib.s (M4c1) : ROMTag RTF_AUTOINIT NT_LIBRARY, pri 10 (place roadmap, init en dernier),
; auto-scanné par build_reslist -> MakeLibrary crée IntuitionBase, Enqueue dans EB_LIBLIST (branche NT_LIBRARY).
; Livre Open/Close/Expunge + ViewAddress (vecteur 49 = LVO -294) -> renvoie &ib_ViewLord (le View embarqué).
; Hors M5 (différé) : OpenScreen/OpenWindow/DisplayAlert, rendu, écran insert-disk (-> M6, vrai déclencheur).
;
; Piste IMPLÉMENTATION (« clean ») : AutoDocs intuition.library + NDK includes/.fd (public). AUCUNE lecture ROM.

                include "exec.i"
                include "intuition.i"

; --- ROMTag intuition.library (scanné par build_reslist) ---
        EVEN
intuition_romtag:
        dc.w    RTC_MATCHWORD
        dc.l    intuition_romtag         ; RT_MATCHTAG = self
        dc.l    intuition_end            ; RT_ENDSKIP
        dc.b    RTF_AUTOINIT|RTF_COLDSTART,34,NT_LIBRARY,10  ; RT_FLAGS, RT_VERSION, RT_TYPE, RT_PRI (10 : place roadmap intuition)
        dc.l    intuition_name           ; RT_NAME
        dc.l    intuition_name           ; RT_IDSTRING
        dc.l    intuition_inittab        ; RT_INIT -> table AUTOINIT
intuition_name:
        dc.b    "intuition.library",0
        EVEN
intuition_inittab:
        dc.l    INTUITIONBASE_SIZE       ; dataSize : base Library + champs IntuitionBase (ViewLord embarqué...)
        dc.l    intuition_vectors        ; funcTable
        dc.l    intuition_datatab        ; dataTable (InitStruct)
        dc.l    intuition_initfunc       ; initFunc
; table ABSOLUE terminée par -1. Vecteur N -> LVO -6*N. On remplit jusqu'à ViewAddress (-294 = vecteur 49) ; les
; vecteurs 5..48 (-30..-288) non implémentés pointent sur intuition_null (dcb évite tout miscount manuel).
intuition_vectors:
        dc.l    intuition_open           ; 1 : LVO -6
        dc.l    intuition_close          ; 2 : LVO -12
        dc.l    intuition_expunge        ; 3 : LVO -18
        dc.l    intuition_null           ; 4 : LVO -24 (réservé)
        dcb.l   7,intuition_null         ; 5..11 : LVO -30..-66 (non impl.)
        dc.l    intuition_CloseWindow    ; 12 : LVO -72 CloseWindow(fenêtre a0)
        dcb.l   8,intuition_null         ; 13..20 : LVO -78..-120 (non impl. : DisplayAlert -90 inclus)
        dc.l    intuition_GetPrefs       ; 21 : LVO -126 GetDefPrefs(buffer a0, taille d0)
        dc.l    intuition_GetPrefs       ; 22 : LVO -132 GetPrefs(buffer a0, taille d0)
        dcb.l   11,intuition_null        ; 23..33 : LVO -138..-198 (non impl. : OpenScreen -198 inclus)
        dc.l    intuition_OpenWindow     ; 34 : LVO -204 OpenWindow(newwindow a0)
        dcb.l   14,intuition_null        ; 35..48 : LVO -210..-288 (non impl.)
        dc.l    intuition_ViewAddress    ; 49 : LVO -294
        dc.l    -1
intuition_datatab:
        dc.w    $E000,LN_TYPE,(NT_LIBRARY<<8)   ; INITBYTE(LN_TYPE, NT_LIBRARY)
        dc.w    $D000,LIB_VERSION,34            ; INITWORD(LIB_VERSION, 34)
        dc.b    0
        EVEN

; Open(lib a6) : incrémente le compte d'ouverture, retourne la base (convention OpenLibrary).
intuition_open:
        addq.w  #1,LIB_OPENCNT(a6)
        move.l  a6,d0
        rts
intuition_close:
        subq.w  #1,LIB_OPENCNT(a6)
        moveq   #0,d0
        rts
intuition_expunge:
        moveq   #0,d0               ; pas d'expunge ce milestone (base résidente)
        rts
intuition_null:
        moveq   #0,d0
        rts

; OpenWindow(newwindow a0) -> d0 = Window | 0. Fenêtre MINIMALE : structure Window (mise en page intuition.h V34)
; allouée et remplie depuis la NewWindow (position, taille, limites, titre, drapeaux, IDCMP, pinceaux), bordures
; nulles ; ni layer, ni rastport, ni port IDCMP, ni rendu à l'écran (pas de layers.library). Suffit aux clients
; qui passent la fenêtre à console.device (NEWCON:). CloseWindow(fenêtre a0) la libère.
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
WD_IDCMPFLAGS   EQU 82
WD_DETAILPEN    EQU 98
WD_BLOCKPEN     EQU 99
WD_GZZWIDTH     EQU 112
WD_GZZHEIGHT    EQU 114
WD_SIZE         EQU 132
NW_LEFTEDGE     EQU 0
NW_TOPEDGE      EQU 2
NW_WIDTH        EQU 4
NW_HEIGHT       EQU 6
NW_DETAILPEN    EQU 8
NW_BLOCKPEN     EQU 9
NW_IDCMPFLAGS   EQU 10
NW_FLAGS        EQU 14
NW_TITLE        EQU 26
NW_MINWIDTH     EQU 38
NW_MINHEIGHT    EQU 40
NW_MAXWIDTH     EQU 42
NW_MAXHEIGHT    EQU 44
intuition_OpenWindow:
        movem.l a2/a6,-(sp)
        move.l  a0,a2
        move.l  ($4).w,a6
        move.l  #WD_SIZE,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.s   .ow_ret
        move.l  d0,a0
        move.l  NW_LEFTEDGE(a2),WD_LEFTEDGE(a0)   ; LeftEdge + TopEdge
        move.l  NW_WIDTH(a2),WD_WIDTH(a0)         ; Width + Height
        move.w  NW_WIDTH(a2),WD_GZZWIDTH(a0)
        move.w  NW_HEIGHT(a2),WD_GZZHEIGHT(a0)
        move.w  NW_MINWIDTH(a2),WD_MINWIDTH(a0)
        move.w  NW_MINHEIGHT(a2),WD_MINHEIGHT(a0)
        move.w  NW_MAXWIDTH(a2),WD_MAXWIDTH(a0)
        move.w  NW_MAXHEIGHT(a2),WD_MAXHEIGHT(a0)
        move.l  NW_FLAGS(a2),WD_FLAGS(a0)
        move.l  NW_TITLE(a2),WD_TITLE(a0)
        move.l  NW_IDCMPFLAGS(a2),WD_IDCMPFLAGS(a0)
        move.b  NW_DETAILPEN(a2),WD_DETAILPEN(a0)
        move.b  NW_BLOCKPEN(a2),WD_BLOCKPEN(a0)
.ow_ret:
        movem.l (sp)+,a2/a6
        rts
intuition_CloseWindow:
        move.l  a6,-(sp)
        move.l  a0,d0
        beq.s   .cw_ret
        move.l  a0,a1
        move.l  #WD_SIZE,d0
        move.l  ($4).w,a6
        jsr     LVO_FREEMEM(a6)
.cw_ret:
        move.l  (sp)+,a6
        rts

; GetPrefs / GetDefPrefs(buffer a0, taille d0) -> d0 = buffer : copie min(taille, 232) octets des Preferences
; (pas de devs:system-configuration lu : les préférences courantes sont celles par défaut). serial.device y prend
; son débit (BaudRate) et ses bits série à l'ouverture.
INT_PREFSIZE    EQU 232
intuition_GetPrefs:
        move.l  a0,-(sp)
        lea     intuition_defprefs(pc),a1
        cmp.l   #INT_PREFSIZE,d0
        bls.s   .gp_cnt
        move.l  #INT_PREFSIZE,d0
.gp_cnt:
        subq.l  #1,d0
        bmi.s   .gp_ret
.gp_cpy:
        move.b  (a1)+,(a0)+
        dbra    d0,.gp_cpy
.gp_ret:
        move.l  (sp)+,d0
        rts

; Preferences par défaut (mise en page intuition/preferences.h V34, 232 octets).
intuition_defprefs:
        dc.b    8,0                      ; FontHeight = TOPAZ_EIGHTY, PrinterPort = PARALLEL_PRINTER
        dc.w    5                        ; BaudRate = BAUD_9600
        dc.l    0,100000                 ; KeyRptSpeed
        dc.l    0,600000                 ; KeyRptDelay
        dc.l    1,0                      ; DoubleClick
        dcb.w   36,0                     ; PointerMatrix
        dc.b    0,0                      ; XOffset, YOffset
        dc.w    $0E44,$0000,$0EEC        ; color17..19 (pointeur)
        dc.w    2                        ; PointerTicks
        dc.w    $005A,$0FFF,$0002,$0F80  ; color0..3 (Workbench)
        dc.b    0,0                      ; ViewXOffset, ViewYOffset
        dc.w    0,0                      ; ViewInitX, ViewInitY
        dc.w    0                        ; EnableCLI
        dc.w    0                        ; PrinterType
        dcb.b   30,0                     ; PrinterFilename
        dc.w    0,0,0,5,75,0,0,0,0,0,0,0 ; PrintPitch .. PaperType
        dc.b    0,0,0,0                  ; SerRWBits (8/8), SerStopBuf (1 stop, tampon 512), SerParShk, LaceWB
        dcb.b   30,0                     ; WorkName
        dc.b    0,0                      ; RowSizeChange, ColumnSizeChange
        dc.w    0,0,0                    ; PrintFlags, PrintMaxWidth, PrintMaxHeight
        dc.b    0,0                      ; PrintDensity, PrintXOffset
        dc.w    0,0                      ; wb_Width, wb_Height
        dc.b    0,0                      ; wb_Depth, ext_size
intuition_defprefs_end:
        EVEN
        ifne    intuition_defprefs_end-intuition_defprefs-INT_PREFSIZE
        fail    "Preferences : taille différente de 232 octets"
        endc

; ViewAddress() (a6 = IntuitionBase) -> d0 = &ib_ViewLord (le View courant d'intuition). AutoDoc : « View =
; ViewAddress() ». Pas d'argument. Le ViewLord est embarqué dans la base (offset IB_VIEWLORD) -> adresse stable.
intuition_ViewAddress:
        ifeq    M5I_BAD_VIEWADDR
        lea     IB_VIEWLORD(a6),a0
        move.l  a0,d0
        else
        moveq   #0,d0              ; RED M5I_BAD_VIEWADDR : ViewAddress cassé -> preuve M5I absente
        endc
        rts

; initFunc (D0=base, A0=segList, A6=ExecBase) -> D0=base. Pose le nom (quirk V34).
intuition_initfunc:
        move.l  d0,a1
        lea     intuition_name(pc),a0
        move.l  a0,LN_NAME(a1)
        rts
intuition_end:
