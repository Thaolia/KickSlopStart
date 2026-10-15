; src/graphics/graphics_lib.s — graphics.library (M4c1 : squelette résident).
; 1er vrai module LIBRARY du projet (cia.resource/timer.device étaient resource/device). ROMTag RTF_AUTOINIT
; (pri 65, entre cia 80 et timer 50) -> chemin AUTOINIT de InitResident : MakeLibrary crée GfxBase, puis
; Enqueue dans EB_LIBLIST selon RT_TYPE=NT_LIBRARY (1re fois que la branche NT_LIBRARY->LibList est exercée ;
; jusqu'ici seul NT_DEVICE->DeviceList l'était avec timer.device). Quirk V34 : la data table pose LN_TYPE +
; LIB_VERSION, l'init func pose LN_NAME="graphics.library". Les fonctions d'affichage (MakeVPort/MrgCop/
; LoadView...) sont DIFFÉRÉES en M4c2 : ce milestone ne livre que Open/Close/Expunge/Reserved (le squelette
; que M4c2 ET intuition/M5 ouvriront). GfxBase = base Library minimale (étendue en M4c2).
;
; Piste IMPLÉMENTATION (« clean ») : AutoDocs graphics.library + exec (RKRM/NDK). AUCUNE lecture ROM.

                include "exec.i"
                include "graphics.i"

; --- ROMTag graphics.library (scanné par build_reslist) ---
        EVEN
graphics_romtag:
        dc.w    RTC_MATCHWORD
        dc.l    graphics_romtag          ; RT_MATCHTAG = self
        dc.l    graphics_end             ; RT_ENDSKIP
                ifne    M4C1_WRONG_TYPE
        dc.b    RTF_AUTOINIT,34,NT_DEVICE,65   ; RED : RT_TYPE device -> routé DeviceList -> absent de LibList
                else
        dc.b    RTF_AUTOINIT,34,NT_LIBRARY,65  ; RT_FLAGS, RT_VERSION, RT_TYPE, RT_PRI (65 : entre cia 80 / timer 50)
                endc
        dc.l    graphics_name            ; RT_NAME
        dc.l    graphics_name            ; RT_IDSTRING
        dc.l    graphics_inittab         ; RT_INIT -> table AUTOINIT
graphics_name:
        dc.b    "graphics.library",0
        EVEN
graphics_inittab:
        dc.l    LIB_SIZE                 ; dataSize : base Library minimale (étendue en M4c2)
        dc.l    graphics_vectors         ; funcTable
        dc.l    graphics_datatab         ; dataTable (InitStruct)
        dc.l    graphics_initfunc        ; initFunc
graphics_vectors:                        ; table ABSOLUE terminée par -1 (ordre LVO standard)
        dc.l    graphics_open            ; LVO -6
        dc.l    graphics_close           ; LVO -12
        dc.l    graphics_expunge         ; LVO -18
        dc.l    graphics_null            ; LVO -24 (réservé)
        dc.l    -1
graphics_datatab:
        dc.w    $E000,LN_TYPE,(NT_LIBRARY<<8)   ; INITBYTE(LN_TYPE, NT_LIBRARY)
        dc.w    $D000,LIB_VERSION,34            ; INITWORD(LIB_VERSION, 34)
        dc.b    0
        EVEN

; Open(lib a6) : incrémente le compte d'ouverture, retourne la base (convention OpenLibrary).
graphics_open:
        addq.w  #1,LIB_OPENCNT(a6)
        move.l  a6,d0
        rts
graphics_close:
        subq.w  #1,LIB_OPENCNT(a6)
        moveq   #0,d0
        rts
graphics_expunge:
        moveq   #0,d0               ; pas d'expunge ce milestone (base résidente)
        rts
graphics_null:
        moveq   #0,d0
        rts

; initFunc (D0=base, A0=segList, A6=ExecBase) -> D0=base. Pose le nom (quirk V34).
graphics_initfunc:
        move.l  d0,a1
        lea     graphics_name(pc),a0
        move.l  a0,LN_NAME(a1)
        rts
graphics_end:
