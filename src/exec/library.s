; src/exec/library.s — exec.library: construction of the LVO jump table and
; "library/forbid/disable" functions (Open, Close, Expunge, Forbid, Permit,
; Disable, Enable). Amiga convention: scratch = d0/d1/a0/a1; a6 = library base.
; IMPLEMENTATION track ("clean"): docs/analysis/exec-spec.md +
; docs/exec-lvo-table.md + public ABI. NO reading of the ROM.
;
; M2.1a covers: the dispatch MECHANISM (jump table) and the BEHAVIOUR of the
; functions. It does NOT prove offset compatibility with the real AmigaOS 1.3
; (we call what we patched ourselves) — validated by cross-check against exec_lib.fd V34.

                include "exec.i"

                xdef    build_jumptable
                xdef    exec_Open
                xdef    exec_Close
                xdef    exec_Expunge
                xdef    exec_Forbid
                xdef    exec_Permit
                xdef    exec_Disable
                xdef    exec_Enable
                xdef    raw_enable       ; M7c: BARE Enable (Signal re-enables without the reschedule tail)

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
                xref    exec_Wait        ; interrupts.s (scheduler: synchronous switch)
                xref    reschedule       ; interrupts.s (yield-on-Permit: synchronous switch)
                xref    exec_SetIntVector ; interrupts.s (by-number dispatcher: exclusive vector)
                xref    exec_AddIntServer ; interrupts.s (by-number dispatcher: server chain)
                xref    exec_InitCode    ; resident.s (scan + init of the resident modules)
                xref    exec_FindResident
                xref    exec_InitResident
                xref    exec_MakeLibrary ; libinit.s (lib/device creation, AUTOINIT path)
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
                xref    ram_loadmodule   ; ramlib.s (loading from LIBS:/DEVS:)
                xref    exec_CopyMemQuick
                xref    exec_AddLibrary
                xref    exec_RemLibrary
                xref    exec_AddDevice
                xref    exec_RemDevice
                xref    exec_InitSemaphore
                xref    exec_ObtainSemaphore
                xref    exec_ReleaseSemaphore
                xref    exec_AttemptSemaphore
                xref    exec_AddSemaphore
                xref    exec_RemSemaphore
                xref    exec_FindSemaphore
                xref    exec_SetFunction
                xref    exec_SumLibrary
                xref    exec_Cause
                xref    exec_Alert
                xref    exec_SetSR
                xref    exec_SuperState
                xref    exec_UserState
                xref    exec_GetCC
                xref    exec_RemIntServer
                xref    exec_AllocEntry
                xref    exec_FreeEntry
                xref    exec_SetExcept
                xref    exec_AllocTrap
                xref    trap3_handler        ; interrupts.s (Supervisor via EXEC_SVC)
                xref    exec_FreeTrap
                xref    exec_RemResource
                xref    exec_RawIOInit
                xref    exec_RawMayGetChar
                xref    exec_RawPutChar
                xref    exec_ObtainSemaphoreList
                xref    exec_ReleaseSemaphoreList
                xref    exec_Allocate
                xref    exec_Deallocate
                xref    exec_AllocAbs
                xref    exec_AddMemList

; ============================ jump table ============================
; Fills the 105 entries (V34) with _unimpl then patches the implemented LVOs.
build_jumptable:                     ; a6 = SysBase; clobbers d0/d1/a0
        lea     EXEC_BLOCK,a0
        move.w  #(EXEC_NEGSIZE/6)-1,d0
        move.l  #_unimpl,d1
.fill:
        move.w  #$4EF9,(a0)+
        move.l  d1,(a0)+
        dbf     d0,.fill
        move.w  #$4EF9,LVO_SUPERVISOR(a6)      ; -30: exec Supervisor (required by the flt-intro cracktro)
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
        move.l  #exec_InitSemaphore,LVO_INITSEMAPHORE+2(a6)
        move.l  #exec_ObtainSemaphore,LVO_OBTAINSEMAPHORE+2(a6)
        move.l  #exec_ReleaseSemaphore,LVO_RELEASESEMAPHORE+2(a6)
        move.l  #exec_AttemptSemaphore,LVO_ATTEMPTSEMAPHORE+2(a6)
        move.l  #exec_FindSemaphore,LVO_FINDSEMAPHORE+2(a6)
        move.l  #exec_AddSemaphore,LVO_ADDSEMAPHORE+2(a6)
        move.l  #exec_RemSemaphore,LVO_REMSEMAPHORE+2(a6)
        move.w  #$4EF9,-420(a6)
        move.l  #exec_SetFunction,-420+2(a6)       ; SetFunction
        move.w  #$4EF9,-426(a6)
        move.l  #exec_SumLibrary,-426+2(a6)       ; SumLibrary
        move.w  #$4EF9,-180(a6)
        move.l  #exec_Cause,-180+2(a6)       ; Cause
        move.w  #$4EF9,EXEC_ALERTSTUB       ; Alert goes through a relay in RAM: SetPatch 1.3 only replaces Alert
        move.l  #exec_Alert,EXEC_ALERTSTUB+2 ; if the old vector is in ROM, then jumps into the 1.3 ROM code
        move.w  #$4EF9,-108(a6)
        move.l  #EXEC_ALERTSTUB,-108+2(a6)   ; Alert
        move.w  #$4EF9,-144(a6)
        move.l  #exec_SetSR,-144+2(a6)       ; SetSR
        move.w  #$4EF9,-150(a6)
        move.l  #exec_SuperState,-150+2(a6)       ; SuperState
        move.w  #$4EF9,-156(a6)
        move.l  #exec_UserState,-156+2(a6)       ; UserState
        move.w  #$4EF9,-528(a6)
        move.l  #exec_GetCC,-528+2(a6)       ; GetCC
        move.w  #$4EF9,-174(a6)
        move.l  #exec_RemIntServer,-174+2(a6)       ; RemIntServer
        move.w  #$4EF9,-222(a6)
        move.l  #exec_AllocEntry,-222+2(a6)       ; AllocEntry
        move.w  #$4EF9,-228(a6)
        move.l  #exec_FreeEntry,-228+2(a6)       ; FreeEntry
        move.w  #$4EF9,-312(a6)
        move.l  #exec_SetExcept,-312+2(a6)       ; SetExcept
        move.w  #$4EF9,-342(a6)
        move.l  #exec_AllocTrap,-342+2(a6)       ; AllocTrap
        move.w  #$4EF9,-348(a6)
        move.l  #exec_FreeTrap,-348+2(a6)       ; FreeTrap
        move.w  #$4EF9,-492(a6)
        move.l  #exec_RemResource,-492+2(a6)       ; RemResource
        move.w  #$4EF9,-504(a6)
        move.l  #exec_RawIOInit,-504+2(a6)       ; RawIOInit
        move.w  #$4EF9,-510(a6)
        move.l  #exec_RawMayGetChar,-510+2(a6)       ; RawMayGetChar
        move.w  #$4EF9,-516(a6)
        move.l  #exec_RawPutChar,-516+2(a6)       ; RawPutChar
        move.w  #$4EF9,-582(a6)
        move.l  #exec_ObtainSemaphoreList,-582+2(a6)       ; ObtainSemaphoreList
        move.w  #$4EF9,-588(a6)
        move.l  #exec_ReleaseSemaphoreList,-588+2(a6)       ; ReleaseSemaphoreList
        move.w  #$4EF9,-186(a6)
        move.l  #exec_Allocate,-186+2(a6)       ; Allocate
        move.w  #$4EF9,-192(a6)
        move.l  #exec_Deallocate,-192+2(a6)       ; Deallocate
        move.w  #$4EF9,-204(a6)
        move.l  #exec_AllocAbs,-204+2(a6)       ; AllocAbs
        move.w  #$4EF9,-618(a6)
        move.l  #exec_AddMemList,-618+2(a6)       ; AddMemList
        rts

_unimpl:
        moveq   #0,d0                ; unimplemented LVO: neutral return
        rts

; exec_Supervisor(a5 = routine): executes a5 in SUPERVISOR mode, then returns to the caller. Called in
; USER mode by loaded code (e.g. the flt-intro cracktro which drives the hardware/copper in supervisor). EXEC_SVC ->
; supervisor -> trap3_handler does jmp (a5); a5 (by Supervisor convention) ends with RTE, which pops the
; {user SR, PC} frame of EXEC_SVC -> resumes HERE in user mode -> rts to the caller. a5 must preserve the
; SSP frame (AutoDoc Supervisor contract).
exec_Supervisor:
        EXEC_SVC trap3_handler
        rts

; ============================ exec functions ========================
exec_Open:                           ; -> d0 = SysBase
        addq.w  #1,LIB_OPENCNT(a6)
        move.l  a6,d0
        rts
exec_Close:
        subq.w  #1,LIB_OPENCNT(a6)
        moveq   #0,d0
        rts
exec_Expunge:
        moveq   #0,d0                ; exec never expunges itself
        rts

; OpenLibrary(libName a1, version d0) -> d0 = base (or 0). Forbid-guarded: FindName(LibList) + version
; gate (lib_Version >= requested version, otherwise 0) + call of the lib's Open vector (-6) (OpenCnt++).
; Disk loading via ramlib if not resident = deferred (M6): not found -> 0. Preserves d2/a2.
exec_OpenLibrary:
        movem.l d2/a2,-(sp)
        move.w  d0,d2                ; d2 = requested version (UWORD)
        move.l  a1,a2                ; a2 = name (preserved across Forbid/FindName)
        jsr     LVO_FORBID(a6)
        lea     EB_LIBLIST(a6),a0
        move.l  a2,a1
        jsr     LVO_FINDNAME(a6)     ; d0 = lib node (or 0)
        tst.l   d0
        bne.s   .ol_found
        jsr     LVO_PERMIT(a6)       ; missing: load from LIBS: (ramlib), outside Forbid
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
        move.l  d0,a2                ; a2 = lib base
                ifeq    OPENLIB_NO_VERCHECK
        cmp.w   LIB_VERSION(a2),d2   ; requested (d2) > available (lib_Version)?
        bhi.s   .ol_fail             ; too recent a version requested -> failure
                endc
        move.l  a6,-(sp)             ; call of the lib's Open vector (a6 = lib)
        move.l  a2,a6
        jsr     LVO_OPEN(a6)         ; -6: OpenCnt++, d0 = base
        move.l  (sp)+,a6
        bra.s   .ol_done
.ol_fail:
        moveq   #0,d0
.ol_done:
        move.l  d0,-(sp)             ; preserve the result across Permit (which may yield)
        jsr     LVO_PERMIT(a6)
        move.l  (sp)+,d0
        movem.l (sp)+,d2/a2
        rts

ol_libsdir:
        dc.b    "LIBS:",0
        even

; OldOpenLibrary(libName a1) -> d0 = base (or 0): OpenLibrary without version gate (pre-V33 form).
exec_OldOpenLibrary:
        moveq   #0,d0                ; version 0 -> the gate always passes
        bra     exec_OpenLibrary

; CloseLibrary(library a1): Forbid-guarded, call of the lib's Close vector (-12) (OpenCnt--). d0 = 0.
exec_CloseLibrary:
        movem.l a2,-(sp)
        move.l  a1,a2                ; a2 = lib
        jsr     LVO_FORBID(a6)
        move.l  a6,-(sp)
        move.l  a2,a6
        jsr     LVO_CLOSE(a6)        ; -12: OpenCnt--
        move.l  (sp)+,a6
        jsr     LVO_PERMIT(a6)
        moveq   #0,d0
        movem.l (sp)+,a2
        rts

exec_Forbid:
        addq.b  #1,EB_TDNEST(a6)
        rts
; Permit: unlocks the Forbid; on return to the permitted state (TDNest < 0) AND not Disabled,
; if a reschedule is pending (AttnResched, set by Signal for a woken task with
; priority) -> immediate SYNCHRONOUS yield (M3e). Otherwise the woken task would wait for a tick.
exec_Permit:
        subq.b  #1,EB_TDNEST(a6)
        bge.s   .pm_ret             ; nesting: still forbidden -> nothing
        tst.b   EB_IDNEST(a6)
        bge.s   .pm_ret             ; still Disabled -> Enable will do the yield
        tst.w   EB_ATTNRESCHED(a6)
        beq.s   .pm_ret
        jsr     reschedule          ; returns here when the current task is re-dispatched
.pm_ret:
        rts
exec_Disable:
        addq.b  #1,EB_IDNEST(a6)
        move.w  #$4000,INTENA        ; clear INTEN (bit14)
        rts
; raw_enable: BARE Enable — decrements the nesting and re-enables INTEN if we go back to permitted, WITHOUT the
; reschedule tail. Shared by exec_Enable and exec_Signal: Signal is ALSO called from an
; interrupt, where triggering reschedule->trap would be a scheduler re-entry (cf. ledger M7c).
raw_enable:
        subq.b  #1,EB_IDNEST(a6)
        bge.s   .re_ret             ; still Disabled (nesting) -> do not touch INTENA
        move.w  #$C000,INTENA        ; SETCLR + INTEN (re-enables the master)
.re_ret:
        rts
; Enable: symmetric of Permit on the Disable side. raw_enable then, if we just re-enabled AND not
; Forbidden AND reschedule pending -> yield.
exec_Enable:
        bsr     raw_enable
        tst.b   EB_IDNEST(a6)
        bge.s   .en_ret             ; still Disabled (nesting) -> no yield
        tst.b   EB_TDNEST(a6)
        bge.s   .en_ret             ; still Forbidden -> Permit will do the yield
        tst.w   EB_ATTNRESCHED(a6)
        beq.s   .en_ret
        jsr     reschedule
.en_ret:
        rts
