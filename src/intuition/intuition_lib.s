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
        dc.b    RTF_AUTOINIT,34,NT_LIBRARY,10  ; RT_FLAGS, RT_VERSION, RT_TYPE, RT_PRI (10 : place roadmap intuition)
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
        dcb.l   44,intuition_null        ; 5..48 : LVO -30..-288 (non impl. : DisplayAlert -90, OpenScreen -198 inclus)
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
