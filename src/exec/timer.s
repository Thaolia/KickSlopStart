; src/exec/timer.s — timer.device — M5c.
; 2e vrai module résident, et 1er DEVICE, créé par le chemin AUTOINIT de InitResident :
; ROMTag RTF_AUTOINIT (pri 50) -> InitResident appelle MakeLibrary avec la table de 4 longs,
; puis Enqueue la base dans DeviceList (RT_TYPE = NT_DEVICE). Quirk V34 : InitResident ne
; remplit PAS les champs du nœud -> la data table (InitStruct) pose LN_TYPE + LIB_VERSION et
; l'init func pose LN_NAME="timer.device" (sinon OpenDevice/FindName ne le trouverait pas).
; PÉRIMÈTRE M5c : device CRÉÉ + NOMMÉ + AJOUTÉ + jump table fonctionnelle (Open incrémente
; LIB_OPENCNT). DIFFÉRÉ (ledgeré) : unités (VBLANK/MICROHZ/ECLOCK), file de requêtes, BeginIO
; fonctionnel (nécessitent la dispatch CIA INT2/INT6, elle-même différée). BeginIO/AbortIO = stubs.
; Table de vecteurs ABSOLUE. Piste CLEAN : AutoDocs timer.device + exec. AUCUNE lecture ROM.

                include "exec.i"

; --- ROMTag timer.device (scanné par build_reslist) ---
        EVEN
timer_romtag:
        dc.w    RTC_MATCHWORD
        dc.l    timer_romtag         ; RT_MATCHTAG = self
        dc.l    timer_end            ; RT_ENDSKIP
        dc.b    RTF_AUTOINIT,34,NT_DEVICE,50  ; RT_FLAGS, RT_VERSION, RT_TYPE, RT_PRI
        dc.l    timer_name           ; RT_NAME
        dc.l    timer_name           ; RT_IDSTRING
        dc.l    timer_inittab        ; RT_INIT -> table AUTOINIT
timer_name:
        dc.b    "timer.device",0
        EVEN
timer_inittab:
        dc.l    LIB_SIZE             ; dataSize (base device mini)
        dc.l    timer_vectors        ; funcTable
        dc.l    timer_datatab        ; dataTable (InitStruct)
        dc.l    timer_initfunc       ; initFunc
timer_vectors:                       ; table ABSOLUE, terminée par -1 (ordre device standard)
        dc.l    timer_open           ; LVO -6
        dc.l    timer_close          ; LVO -12
        dc.l    timer_expunge        ; LVO -18
        dc.l    timer_null           ; LVO -24 (réservé / ExtFunc)
        dc.l    timer_beginio        ; LVO -30
        dc.l    timer_abortio        ; LVO -36
        dc.l    -1
timer_datatab:
        dc.w    $E000,LN_TYPE,(NT_DEVICE<<8)  ; INITBYTE(LN_TYPE, NT_DEVICE)
        dc.w    $D000,LIB_VERSION,34          ; INITWORD(LIB_VERSION, 34)
        dc.b    0
        EVEN

; Open(device a6, iorequest a1, unit d0, flags d1) : stub M5c -> incrémente le compte d'ouverture.
timer_open:
        addq.w  #1,LIB_OPENCNT(a6)
        rts
; Close(device a6, iorequest a1) -> d0
timer_close:
        subq.w  #1,LIB_OPENCNT(a6)
        moveq   #0,d0
        rts
timer_expunge:
        moveq   #0,d0                ; ne s'expulse pas
        rts
timer_null:
        moveq   #0,d0
        rts
; BeginIO(iorequest a1) a6=device : STUB (gestion d'unité/requête différée).
timer_beginio:
        rts
timer_abortio:
        moveq   #0,d0
        rts
; initFunc (D0=base, A0=segList, A6=ExecBase) -> D0 = base. Pose le nom (quirk V34).
timer_initfunc:
        move.l  d0,a1
        lea     timer_name(pc),a0
        move.l  a0,LN_NAME(a1)
        rts
        EVEN
timer_end:
