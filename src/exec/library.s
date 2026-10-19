; src/exec/library.s — exec.library : construction de la jump table LVO et
; fonctions « library/forbid/disable » (Open, Close, Expunge, Forbid, Permit,
; Disable, Enable). Convention Amiga : scratch = d0/d1/a0/a1 ; a6 = library base.
; Piste IMPLÉMENTATION (« clean ») : docs/analysis/exec-spec.md +
; docs/exec-lvo-table.md + ABI publique. AUCUNE lecture de la ROM.
;
; M2.1a couvre : le MÉCANISME de dispatch (jump table) et le COMPORTEMENT des
; fonctions. Il ne prouve PAS la compatibilité d'offsets avec l'AmigaOS 1.3 réel
; (on appelle ce qu'on a soi-même patché) — validé par cross-check exec_lib.fd V34.

                include "exec.i"

                xdef    build_jumptable
                xdef    exec_Open
                xdef    exec_Close
                xdef    exec_Expunge
                xdef    exec_Forbid
                xdef    exec_Permit
                xdef    exec_Disable
                xdef    exec_Enable
                xdef    raw_enable       ; M7c : Enable NU (Signal réactive sans la queue reschedule)

                xref    exec_AddHead     ; lists.s
                xref    exec_AddTail
                xref    exec_Insert
                xref    exec_Remove
                xref    exec_RemHead
                xref    exec_RemTail
                xref    exec_Enqueue
                xref    exec_FindName
                xref    exec_AllocMem    ; memory.s
                xref    exec_FreeMem
                xref    exec_AvailMem
                xref    exec_TypeOfMem
                xref    exec_AddTask     ; tasks.s
                xref    exec_RemTask     ; tasks.s (M7j)
                xref    exec_FindTask
                xref    exec_SetTaskPri
                xref    exec_SetSignal
                xref    exec_Signal
                xref    exec_AllocSignal
                xref    exec_FreeSignal
                xref    exec_Wait        ; interrupts.s (scheduler : switch synchrone)
                xref    reschedule       ; interrupts.s (yield-sur-Permit : switch synchrone)
                xref    exec_SetIntVector ; interrupts.s (dispatcher par numéro : vecteur exclusif)
                xref    exec_AddIntServer ; interrupts.s (dispatcher par numéro : chaîne de serveurs)
                xref    exec_InitCode    ; resident.s (scan + init des modules résidents)
                xref    exec_FindResident
                xref    exec_InitResident
                xref    exec_MakeLibrary ; libinit.s (création lib/device, chemin AUTOINIT)
                xref    exec_MakeFunctions
                xref    exec_InitStruct
                xref    exec_AddResource ; resident.s (resources)
                xref    exec_OpenResource
                xref    exec_AddPort     ; ports.s
                xref    exec_RemPort
                xref    exec_PutMsg
                xref    exec_GetMsg
                xref    exec_ReplyMsg
                xref    exec_WaitPort
                xref    exec_FindPort
                xref    exec_RawDoFmt    ; rawdofmt.s
                xref    exec_OpenDevice  ; io.s
                xref    exec_CloseDevice
                xref    exec_DoIO
                xref    exec_SendIO
                xref    exec_CheckIO
                xref    exec_WaitIO
                xref    exec_AbortIO
                xref    exec_CopyMem
                xref    ram_loadmodule   ; ramlib.s (chargement depuis LIBS:/DEVS:)
                xref    exec_CopyMemQuick
                xref    exec_AddLibrary
                xref    exec_RemLibrary
                xref    exec_AddDevice
                xref    exec_RemDevice

; ============================ jump table ============================
; Remplit les 105 entrées (V34) avec _unimpl puis patche les LVO implémentés.
build_jumptable:                     ; a6 = SysBase ; clobbers d0/d1/a0
        lea     EXEC_BLOCK,a0
        move.w  #(EXEC_NEGSIZE/6)-1,d0
        move.l  #_unimpl,d1
.fill:
        move.w  #$4EF9,(a0)+
        move.l  d1,(a0)+
        dbf     d0,.fill
        move.w  #$4EF9,LVO_SUPERVISOR(a6)      ; -30 : exec Supervisor (requis par le cracktro flt-intro)
        move.l  #exec_Supervisor,LVO_SUPERVISOR+2(a6)
        move.w  #$4EF9,LVO_OPEN(a6)
        move.l  #exec_Open,LVO_OPEN+2(a6)
        move.w  #$4EF9,LVO_CLOSE(a6)
        move.l  #exec_Close,LVO_CLOSE+2(a6)
        move.w  #$4EF9,LVO_EXPUNGE(a6)
        move.l  #exec_Expunge,LVO_EXPUNGE+2(a6)
        move.w  #$4EF9,LVO_INITCODE(a6)
        move.l  #exec_InitCode,LVO_INITCODE+2(a6)
        move.w  #$4EF9,LVO_INITSTRUCT(a6)
        move.l  #exec_InitStruct,LVO_INITSTRUCT+2(a6)
        move.w  #$4EF9,LVO_MAKELIBRARY(a6)
        move.l  #exec_MakeLibrary,LVO_MAKELIBRARY+2(a6)
        move.w  #$4EF9,LVO_MAKEFUNCTIONS(a6)
        move.l  #exec_MakeFunctions,LVO_MAKEFUNCTIONS+2(a6)
        move.w  #$4EF9,LVO_ADDRESOURCE(a6)
        move.l  #exec_AddResource,LVO_ADDRESOURCE+2(a6)
        move.w  #$4EF9,LVO_OPENRESOURCE(a6)
        move.l  #exec_OpenResource,LVO_OPENRESOURCE+2(a6)
        move.w  #$4EF9,LVO_FINDRESIDENT(a6)
        move.l  #exec_FindResident,LVO_FINDRESIDENT+2(a6)
        move.w  #$4EF9,LVO_INITRESIDENT(a6)
        move.l  #exec_InitResident,LVO_INITRESIDENT+2(a6)
        move.w  #$4EF9,LVO_DISABLE(a6)
        move.l  #exec_Disable,LVO_DISABLE+2(a6)
        move.w  #$4EF9,LVO_ENABLE(a6)
        move.l  #exec_Enable,LVO_ENABLE+2(a6)
        move.w  #$4EF9,LVO_FORBID(a6)
        move.l  #exec_Forbid,LVO_FORBID+2(a6)
        move.w  #$4EF9,LVO_PERMIT(a6)
        move.l  #exec_Permit,LVO_PERMIT+2(a6)
        move.w  #$4EF9,LVO_ADDHEAD(a6)
        move.l  #exec_AddHead,LVO_ADDHEAD+2(a6)
        move.w  #$4EF9,LVO_ADDTAIL(a6)
        move.l  #exec_AddTail,LVO_ADDTAIL+2(a6)
        move.w  #$4EF9,LVO_INSERT(a6)
        move.l  #exec_Insert,LVO_INSERT+2(a6)
        move.w  #$4EF9,LVO_REMOVE(a6)
        move.l  #exec_Remove,LVO_REMOVE+2(a6)
        move.w  #$4EF9,LVO_REMHEAD(a6)
        move.l  #exec_RemHead,LVO_REMHEAD+2(a6)
        move.w  #$4EF9,LVO_REMTAIL(a6)
        move.l  #exec_RemTail,LVO_REMTAIL+2(a6)
        move.w  #$4EF9,LVO_ENQUEUE(a6)
        move.l  #exec_Enqueue,LVO_ENQUEUE+2(a6)
        move.w  #$4EF9,LVO_FINDNAME(a6)
        move.l  #exec_FindName,LVO_FINDNAME+2(a6)
        move.w  #$4EF9,LVO_ALLOCMEM(a6)
        move.l  #exec_AllocMem,LVO_ALLOCMEM+2(a6)
        move.w  #$4EF9,LVO_FREEMEM(a6)
        move.l  #exec_FreeMem,LVO_FREEMEM+2(a6)
        move.w  #$4EF9,LVO_AVAILMEM(a6)
        move.l  #exec_AvailMem,LVO_AVAILMEM+2(a6)
        move.w  #$4EF9,LVO_TYPEOFMEM(a6)
        move.l  #exec_TypeOfMem,LVO_TYPEOFMEM+2(a6)
        move.w  #$4EF9,LVO_ADDTASK(a6)
        move.l  #exec_AddTask,LVO_ADDTASK+2(a6)
        move.w  #$4EF9,LVO_REMTASK(a6)
        move.l  #exec_RemTask,LVO_REMTASK+2(a6)
        move.w  #$4EF9,LVO_FINDTASK(a6)
        move.l  #exec_FindTask,LVO_FINDTASK+2(a6)
        move.w  #$4EF9,LVO_SETTASKPRI(a6)
        move.l  #exec_SetTaskPri,LVO_SETTASKPRI+2(a6)
        move.w  #$4EF9,LVO_SETSIGNAL(a6)
        move.l  #exec_SetSignal,LVO_SETSIGNAL+2(a6)
        move.w  #$4EF9,LVO_WAIT(a6)
        move.l  #exec_Wait,LVO_WAIT+2(a6)
        move.w  #$4EF9,LVO_SIGNAL(a6)
        move.l  #exec_Signal,LVO_SIGNAL+2(a6)
        move.w  #$4EF9,LVO_ALLOCSIGNAL(a6)
        move.l  #exec_AllocSignal,LVO_ALLOCSIGNAL+2(a6)
        move.w  #$4EF9,LVO_FREESIGNAL(a6)
        move.l  #exec_FreeSignal,LVO_FREESIGNAL+2(a6)
        move.w  #$4EF9,LVO_ADDPORT(a6)
        move.l  #exec_AddPort,LVO_ADDPORT+2(a6)
        move.w  #$4EF9,LVO_REMPORT(a6)
        move.l  #exec_RemPort,LVO_REMPORT+2(a6)
        move.w  #$4EF9,LVO_PUTMSG(a6)
        move.l  #exec_PutMsg,LVO_PUTMSG+2(a6)
        move.w  #$4EF9,LVO_GETMSG(a6)
        move.l  #exec_GetMsg,LVO_GETMSG+2(a6)
        move.w  #$4EF9,LVO_REPLYMSG(a6)
        move.l  #exec_ReplyMsg,LVO_REPLYMSG+2(a6)
        move.w  #$4EF9,LVO_WAITPORT(a6)
        move.l  #exec_WaitPort,LVO_WAITPORT+2(a6)
        move.w  #$4EF9,LVO_FINDPORT(a6)
        move.l  #exec_FindPort,LVO_FINDPORT+2(a6)
        move.w  #$4EF9,LVO_SETINTVECTOR(a6)
        move.l  #exec_SetIntVector,LVO_SETINTVECTOR+2(a6)
        move.w  #$4EF9,LVO_ADDINTSERVER(a6)
        move.l  #exec_AddIntServer,LVO_ADDINTSERVER+2(a6)
        move.w  #$4EF9,LVO_OPENLIBRARY(a6)
        move.l  #exec_OpenLibrary,LVO_OPENLIBRARY+2(a6)
        move.w  #$4EF9,LVO_OLDOPENLIBRARY(a6)
        move.l  #exec_OldOpenLibrary,LVO_OLDOPENLIBRARY+2(a6)
        move.w  #$4EF9,LVO_CLOSELIBRARY(a6)
        move.l  #exec_CloseLibrary,LVO_CLOSELIBRARY+2(a6)
        move.w  #$4EF9,LVO_RAWDOFMT(a6)
        move.l  #exec_RawDoFmt,LVO_RAWDOFMT+2(a6)
        move.w  #$4EF9,LVO_OPENDEVICE(a6)
        move.l  #exec_OpenDevice,LVO_OPENDEVICE+2(a6)
        move.w  #$4EF9,LVO_CLOSEDEVICE(a6)
        move.l  #exec_CloseDevice,LVO_CLOSEDEVICE+2(a6)
        move.w  #$4EF9,LVO_DOIO(a6)
        move.l  #exec_DoIO,LVO_DOIO+2(a6)
        move.w  #$4EF9,LVO_SENDIO(a6)
        move.l  #exec_SendIO,LVO_SENDIO+2(a6)
        move.w  #$4EF9,LVO_CHECKIO(a6)
        move.l  #exec_CheckIO,LVO_CHECKIO+2(a6)
        move.w  #$4EF9,LVO_WAITIO(a6)
        move.l  #exec_WaitIO,LVO_WAITIO+2(a6)
        move.w  #$4EF9,LVO_ABORTIO(a6)
        move.l  #exec_AbortIO,LVO_ABORTIO+2(a6)
        move.w  #$4EF9,LVO_COPYMEM(a6)
        move.l  #exec_CopyMem,LVO_COPYMEM+2(a6)
        move.w  #$4EF9,LVO_COPYMEMQUICK(a6)
        move.l  #exec_CopyMemQuick,LVO_COPYMEMQUICK+2(a6)
        move.w  #$4EF9,LVO_ADDLIBRARY(a6)
        move.l  #exec_AddLibrary,LVO_ADDLIBRARY+2(a6)
        move.w  #$4EF9,LVO_REMLIBRARY(a6)
        move.l  #exec_RemLibrary,LVO_REMLIBRARY+2(a6)
        move.w  #$4EF9,LVO_ADDDEVICE(a6)
        move.l  #exec_AddDevice,LVO_ADDDEVICE+2(a6)
        move.w  #$4EF9,LVO_REMDEVICE(a6)
        move.l  #exec_RemDevice,LVO_REMDEVICE+2(a6)
        rts

_unimpl:
        moveq   #0,d0                ; LVO non implémenté : retour neutre
        rts

; exec_Supervisor(a5 = routine) : exécute a5 en mode SUPERVISEUR, puis revient à l'appelant. Appelée en mode
; USER par le code chargé (ex. le cracktro flt-intro qui pilote le hardware/copper en superviseur). trap #3 ->
; superviseur -> trap3_handler fait jmp (a5) ; a5 (par convention Supervisor) se termine par RTE, qui dépile le
; frame {SR user, PC} poussé par le trap -> reprend ICI en mode user -> rts à l'appelant. a5 doit préserver le
; frame SSP du trap (contrat AutoDoc Supervisor).
exec_Supervisor:
        trap    #3
        rts

; ============================ fonctions exec ========================
exec_Open:                           ; -> d0 = SysBase
        addq.w  #1,LIB_OPENCNT(a6)
        move.l  a6,d0
        rts
exec_Close:
        subq.w  #1,LIB_OPENCNT(a6)
        moveq   #0,d0
        rts
exec_Expunge:
        moveq   #0,d0                ; exec ne s'expulse jamais
        rts

; OpenLibrary(libName a1, version d0) -> d0 = base (ou 0). Forbid-gardé : FindName(LibList) + gate de
; version (lib_Version >= version demandée, sinon 0) + appel du vecteur Open (-6) de la lib (OpenCnt++).
; Chargement disque via ramlib si non-résidente = différé (M6) : non trouvée -> 0. Préserve d2/a2.
exec_OpenLibrary:
        movem.l d2/a2,-(sp)
        move.w  d0,d2                ; d2 = version demandée (UWORD)
        move.l  a1,a2                ; a2 = nom (préservé sur Forbid/FindName)
        jsr     LVO_FORBID(a6)
        lea     EB_LIBLIST(a6),a0
        move.l  a2,a1
        jsr     LVO_FINDNAME(a6)     ; d0 = nœud lib (ou 0)
        tst.l   d0
        bne.s   .ol_found
        jsr     LVO_PERMIT(a6)       ; absente : chargement depuis LIBS: (ramlib), hors Forbid
        lea     ol_libsdir(pc),a0
        move.l  a2,a1
        jsr     ram_loadmodule
        jsr     LVO_FORBID(a6)
        tst.l   d0
        beq.s   .ol_fail
        lea     EB_LIBLIST(a6),a0
        move.l  a2,a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        beq.s   .ol_fail
.ol_found:
        move.l  d0,a2                ; a2 = base lib
                ifeq    OPENLIB_NO_VERCHECK
        cmp.w   LIB_VERSION(a2),d2   ; demandée (d2) > disponible (lib_Version) ?
        bhi.s   .ol_fail             ; version trop récente demandée -> échec
                endc
        move.l  a6,-(sp)             ; appel du vecteur Open de la lib (a6 = lib)
        move.l  a2,a6
        jsr     LVO_OPEN(a6)         ; -6 : OpenCnt++, d0 = base
        move.l  (sp)+,a6
        bra.s   .ol_done
.ol_fail:
        moveq   #0,d0
.ol_done:
        move.l  d0,-(sp)             ; préserve le résultat à travers Permit (qui peut yield)
        jsr     LVO_PERMIT(a6)
        move.l  (sp)+,d0
        movem.l (sp)+,d2/a2
        rts

ol_libsdir:
        dc.b    "LIBS:",0
        even

; OldOpenLibrary(libName a1) -> d0 = base (ou 0) : OpenLibrary sans gate de version (forme pré-V33).
exec_OldOpenLibrary:
        moveq   #0,d0                ; version 0 -> la gate passe toujours
        bra     exec_OpenLibrary

; CloseLibrary(library a1) : Forbid-gardé, appel du vecteur Close (-12) de la lib (OpenCnt--). d0 = 0.
exec_CloseLibrary:
        movem.l a2,-(sp)
        move.l  a1,a2                ; a2 = lib
        jsr     LVO_FORBID(a6)
        move.l  a6,-(sp)
        move.l  a2,a6
        jsr     LVO_CLOSE(a6)        ; -12 : OpenCnt--
        move.l  (sp)+,a6
        jsr     LVO_PERMIT(a6)
        moveq   #0,d0
        movem.l (sp)+,a2
        rts

exec_Forbid:
        addq.b  #1,EB_TDNEST(a6)
        rts
; Permit : déverrouille le Forbid ; au retour à l'état permis (TDNest < 0) ET non Disabled,
; si un reschedule est en attente (AttnResched, posé par Signal pour une réveillée
; prioritaire) -> yield SYNCHRONE immédiat (M3e). Sinon la réveillée attendrait un tick.
exec_Permit:
        subq.b  #1,EB_TDNEST(a6)
        bge.s   .pm_ret             ; nesting : encore interdit -> rien
        tst.b   EB_IDNEST(a6)
        bge.s   .pm_ret             ; encore Disabled -> Enable fera le yield
        tst.w   EB_ATTNRESCHED(a6)
        beq.s   .pm_ret
        jsr     reschedule          ; revient ici quand la courante est re-dispatchée
.pm_ret:
        rts
exec_Disable:
        addq.b  #1,EB_IDNEST(a6)
        move.w  #$4000,INTENA        ; clear INTEN (bit14)
        rts
; raw_enable : Enable NU — décrémente le nesting et réactive INTEN si on repasse permis, SANS la
; queue reschedule. Partagé par exec_Enable et exec_Signal : Signal est appelé AUSSI depuis une
; interruption, où déclencher reschedule->trap serait une ré-entrance du scheduler (cf. ledger M7c).
raw_enable:
        subq.b  #1,EB_IDNEST(a6)
        bge.s   .re_ret             ; encore Disabled (nesting) -> ne pas toucher INTENA
        move.w  #$C000,INTENA        ; SETCLR + INTEN (réactive le maître)
.re_ret:
        rts
; Enable : symétrique de Permit côté Disable. raw_enable puis, si on vient de ré-habiliter ET non
; Forbidden ET reschedule en attente -> yield.
exec_Enable:
        bsr     raw_enable
        tst.b   EB_IDNEST(a6)
        bge.s   .en_ret             ; encore Disabled (nesting) -> pas de yield
        tst.b   EB_TDNEST(a6)
        bge.s   .en_ret             ; encore Forbidden -> Permit fera le yield
        tst.w   EB_ATTNRESCHED(a6)
        beq.s   .en_ret
        jsr     reschedule
.en_ret:
        rts
