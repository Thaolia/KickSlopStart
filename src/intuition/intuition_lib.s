; src/intuition/intuition_lib.s — intuition.library (M5 : squelette résident + ViewAddress).
; Calqué sur graphics_lib.s (M4c1) : ROMTag RTF_AUTOINIT NT_LIBRARY, pri 10 (place roadmap, init en dernier),
; auto-scanné par build_reslist -> MakeLibrary crée IntuitionBase, Enqueue dans EB_LIBLIST (branche NT_LIBRARY).
; Livre Open/Close/Expunge, ViewAddress (-> &ib_ViewLord, le View embarqué), GetPrefs/GetDefPrefs ; écrans et
; fenêtres dans screens.s (OpenScreen/CloseScreen/OpenWorkBench/GetScreenData/OpenWindow/CloseWindow).
;
; Piste IMPLÉMENTATION (« clean ») : AutoDocs intuition.library + NDK includes/.fd (public). AUCUNE lecture ROM.

                include "exec.i"
                include "intuition.i"

                xref    intuition_OpenScreen     ; screens.s : écrans et fenêtres
                xref    intuition_CloseScreen
                xref    intuition_OpenWorkBench
                xref    intuition_GetScreenData
                xref    intuition_OpenWindow
                xref    intuition_CloseWindow

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
; table ABSOLUE terminée par -1. Vecteur N -> LVO -6*N ; les vecteurs non implémentés pointent sur intuition_null
; (dcb évite tout miscount manuel).
intuition_vectors:
        dc.l    intuition_open           ; 1 : LVO -6
        dc.l    intuition_close          ; 2 : LVO -12
        dc.l    intuition_expunge        ; 3 : LVO -18
        dc.l    intuition_null           ; 4 : LVO -24 (réservé)
        dcb.l   6,intuition_null         ; 5..10 : LVO -30..-60 (non impl.)
        dc.l    intuition_CloseScreen    ; 11 : LVO -66 CloseScreen(écran a0)
        dc.l    intuition_CloseWindow    ; 12 : LVO -72 CloseWindow(fenêtre a0)
        dcb.l   8,intuition_null         ; 13..20 : LVO -78..-120 (non impl. : DisplayAlert -90 inclus)
        dc.l    intuition_GetPrefs       ; 21 : LVO -126 GetDefPrefs(buffer a0, taille d0)
        dc.l    intuition_GetPrefs       ; 22 : LVO -132 GetPrefs(buffer a0, taille d0)
        dcb.l   10,intuition_null        ; 23..32 : LVO -138..-192 (non impl.)
        dc.l    intuition_OpenScreen     ; 33 : LVO -198 OpenScreen(newscreen a0)
        dc.l    intuition_OpenWindow     ; 34 : LVO -204 OpenWindow(newwindow a0)
        dc.l    intuition_OpenWorkBench  ; 35 : LVO -210 OpenWorkBench()
        dcb.l   13,intuition_null        ; 36..48 : LVO -216..-288 (non impl.)
        dc.l    intuition_ViewAddress    ; 49 : LVO -294
        dcb.l   21,intuition_null        ; 50..70 : LVO -300..-420 (non impl.)
        dc.l    intuition_GetScreenData  ; 71 : LVO -426 GetScreenData(buffer a0, taille d0, type d1, écran a1)
        dcb.l   7,intuition_null         ; 72..78 : LVO -432..-468 (non impl. : jeu V34 complet, jusqu'à NewModifyProp)
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

; initFunc (D0=base, A0=segList, A6=ExecBase) -> D0=base. Pose le nom (quirk V34) et retient GfxBase
; (graphics.library, pri 65, est initialisée avant intuition, pri 10).
intuition_initfunc:
        move.l  a2,-(sp)
        move.l  d0,a2
        lea     intuition_name(pc),a0
        move.l  a0,LN_NAME(a2)
        lea     EB_LIBLIST(a6),a0
        lea     intuition_gfxname(pc),a1
        jsr     LVO_FINDNAME(a6)
        move.l  d0,IB_GFXBASE(a2)
        move.l  a2,d0
        move.l  (sp)+,a2
        rts
intuition_gfxname:
        dc.b    "graphics.library",0
        EVEN
intuition_end:
