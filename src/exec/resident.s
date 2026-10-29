; src/exec/resident.s — exec.library: discovery of resident modules (M4).
;   build_reslist   : scans the ROM for ROMTags (struct Resident), builds the
;                     NUL-terminated array ExecBase->ResModules sorted by descending RT_PRI.
;   FindResident    : looks up a resident by name in ResModules.
;   InitResident    : initialises ONE resident (matchword checked; direct-init path;
;                     AUTOINIT/MakeLibrary DEFERRED -> no-op this milestone).
;   InitCode        : walks ResModules and InitResidents each one (version filter).
; This is the backbone of the Amiga boot: the OS builds itself by scanning ROMTags
; and initialising them by descending priority (instead of a hard-coded dispatch).
; Amiga convention: scratch = d0/d1/a0/a1; a6 = library base.
; IMPLEMENTATION track ("clean"): NDK exec/resident.i + AutoDocs (public ABI).
; NO reading of the proprietary ROM; priorities of the demo residents = arbitrary.

                include "exec.i"

                xdef    build_reslist
                xdef    exec_FindResident
                xdef    exec_InitResident
                xdef    exec_InitCode
                xdef    exec_AddResource
                xdef    exec_OpenResource

; build_reslist: a6 = SysBase. Allocates the array, scans [RESSCAN_LO,RESSCAN_HI), sorts,
; publishes ExecBase->ResModules. A ROMTag = word $4AFC at an EVEN address whose RT_MATCHTAG
; points to itself (rejects stray $4AFC). The scan resumes at RT_ENDSKIP.
build_reslist:
        movem.l d2-d6/a2-a4,-(sp)
        move.l  #(RESMAX+1)*4,d0     ; RESMAX pointers + 1 NUL terminator
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  d0,a3                ; a3 = array base
        move.l  d0,EB_RESMODULES(a6)
        move.l  d0,a4                ; a4 = write cursor
        moveq   #0,d2                ; d2 = resident count
        move.l  #RESSCAN_LO,a2       ; a2 = p (scan pointer, always even)
.scan:
        cmp.l   #RESSCAN_HI,a2
        bcc.s   .sort                ; p >= end -> scan finished
        cmp.w   #RTC_MATCHWORD,(a2)
        bne.s   .scan_next
        move.l  RT_MATCHTAG(a2),d0
        cmp.l   a2,d0
        bne.s   .scan_next           ; RT_MATCHTAG != self -> stray $4AFC
        cmp.w   #RESMAX,d2
        bcc.s   .scan_skip           ; array full (defensive) -> do not record
        move.l  a2,(a4)+             ; array[count++] = p
        addq.l  #1,d2
.scan_skip:
        move.l  RT_ENDSKIP(a2),d0    ; resume after the module body
        cmp.l   a2,d0
        bls.s   .scan_next           ; ENDSKIP <= p (non-advancing) -> advance by 2 (defensive)
        move.l  d0,a2
        bra.s   .scan
.scan_next:
        addq.l  #2,a2
        bra.s   .scan
.sort:
        ; descending bubble sort by RT_PRI (small N; no swap at equal pri -> stable
        ; = FIFO in scan order = address order). array = a3, count = d2.
        cmp.l   #2,d2
        bcs.s   .done                ; 0 or 1 resident -> already sorted
.sort_pass:
        moveq   #0,d4                ; swap flag
        move.l  a3,a0                ; a0 = &array[0]
        moveq   #1,d3                ; j = 1
.sort_j:
        cmp.l   d2,d3
        bcc.s   .sort_passend        ; j >= count -> end of pass
        move.l  (a0),a1              ; array[j-1]
        move.l  4(a0),a2             ; array[j]
        move.b  RT_PRI(a1),d5
        move.b  RT_PRI(a2),d6
        cmp.b   d6,d5                ; pri[j-1] - pri[j] (signed)
        bge.s   .sort_noswap         ; pri[j-1] >= pri[j] -> descending order respected
        move.l  a2,(a0)              ; swap array[j-1] <-> array[j]
        move.l  a1,4(a0)
        moveq   #1,d4
.sort_noswap:
        addq.l  #4,a0
        addq.l  #1,d3
        bra.s   .sort_j
.sort_passend:
        tst.l   d4
        bne.s   .sort_pass           ; a swap took place -> another pass
.done:
        movem.l (sp)+,d2-d6/a2-a4
        rts

; FindResident(name a1) -> d0 = struct Resident* | 0. Looks up in ResModules.
exec_FindResident:
        movem.l d2/a2/a3,-(sp)
        move.l  a1,a2                ; a2 = name searched for
        move.l  EB_RESMODULES(a6),a3
        move.l  a3,d0
        beq.s   .fr_none             ; no array
.fr_loop:
        move.l  (a3)+,d0             ; next Resident* (d0 kept = return value)
        beq.s   .fr_none             ; NUL terminator -> not found
        move.l  d0,a0
        move.l  RT_NAME(a0),a0       ; name of the resident
        move.l  a2,a1                ; name searched for
.fr_cmp:
        move.b  (a0)+,d1
        move.b  (a1)+,d2
        cmp.b   d1,d2
        bne.s   .fr_loop             ; mismatch -> next resident
        tst.b   d1
        bne.s   .fr_cmp              ; not the end -> continue
        bra.s   .fr_done             ; complete match -> d0 = this Resident*
.fr_none:
        moveq   #0,d0
.fr_done:
        movem.l (sp)+,d2/a2/a3
        rts

; InitResident(resident a1, segList d1) -> d0. Validates the matchword then calls the init.
; Direct-init path (RTF_AUTOINIT clear): RT_INIT is a routine called with, by ABI
; convention (AutoDoc exec InitResident): D0 = 0, A0 = segList, A6 = ExecBase;
; the resident pointer is NOT passed (the init routine knows itself statically). Its
; return value (d0) is returned. For a ROM module, segList = NULL.
; AUTOINIT (RTF_AUTOINIT): RT_INIT -> 4 longs {dataSize, funcTable, dataTable, initFunc}
; passed to MakeLibrary; the returned base is Enqueue'd into the system list according to RT_TYPE
; (NT_LIBRARY->LibList, NT_DEVICE->DeviceList, NT_RESOURCE->ResourceList). V34: the
; name/type/version fields of the node are NOT filled from the ROMTag (the module does it).
exec_InitResident:
        cmp.w   #RTC_MATCHWORD,(a1)
        bne.s   .ir_fail             ; not a ROMTag -> 0
        btst    #7,RT_FLAGS(a1)      ; RTF_AUTOINIT?
        bne.s   .ir_autoinit
        move.l  a2,-(sp)
        move.l  RT_INIT(a1),a2       ; init routine
        move.l  d1,a0                ; a0 = segList (convention)
        moveq   #0,d0                ; d0 = 0 (convention)
        jsr     (a2)                 ; init(d0=0, a0=segList, a6=SysBase) -> d0
        move.l  (sp)+,a2
        rts
.ir_autoinit:
        ; RT_INIT -> 4 longs {dataSize, funcTable, dataTable, initFunc} passed to MakeLibrary.
        movem.l d2-d3/a2-a3,-(sp)
        move.l  d1,d3                ; d3 = segList (preserved)
        move.l  a1,a3                ; a3 = resident (for the per-type add)
        move.l  RT_INIT(a1),a2       ; a2 = AUTOINIT table
        move.l  (a2),d0              ; dataSize
        move.l  4(a2),a0             ; funcTable (vectors)
        move.l  8(a2),a1             ; dataTable (InitStruct structure)
        move.l  12(a2),a2           ; initFunc
        move.l  d3,d1                ; segList
        jsr     LVO_MAKELIBRARY(a6)  ; -> d0 = base | 0
        tst.l   d0
        beq.s   .ira_fail
        ; V34: do NOT fill name/type/version of the node from the ROMTag (the module did it).
        ; Add to the system list according to RT_TYPE.
        move.l  d0,a1                ; a1 = base (node)
        move.b  RT_TYPE(a3),d1
        cmp.b   #NT_DEVICE,d1
        beq.s   .ira_dev
        cmp.b   #NT_RESOURCE,d1
        beq.s   .ira_res
        lea     EB_LIBLIST(a6),a0    ; NT_LIBRARY (default)
        bra.s   .ira_add
.ira_dev:
        lea     EB_DEVICELIST(a6),a0
        bra.s   .ira_add
.ira_res:
        lea     EB_RESOURCELIST(a6),a0
.ira_add:
        jsr     LVO_ENQUEUE(a6)      ; Enqueue(list a0, node a1=base); a1 preserved
        move.l  a1,d0                ; d0 = base (return value)
.ira_done:
        movem.l (sp)+,d2-d3/a2-a3
        rts
.ira_fail:
        moveq   #0,d0
        bra.s   .ira_done
.ir_fail:
        moveq   #0,d0
        rts

; InitCode(startClass d0, version d1): walks ResModules (already pri-sorted) and calls
; InitResident on each resident whose RT_FLAGS has a bit in common with startClass (RTF_COLDSTART...)
; and with RT_VERSION >= version. A resident without a class flag (workbench.task) stays in
; ResModules without being initialised. segList = 0 (our ROMTags have no seglist).
exec_InitCode:
        movem.l d2-d4/a2,-(sp)
        move.b  d0,d4                ; d4 = startup class (RTF_COLDSTART...)
        move.l  d1,d3                ; minimum version
        move.l  EB_RESMODULES(a6),a2
        move.l  a2,d0
        beq.s   .ic_done             ; no array
.ic_loop:
        move.l  (a2)+,d0             ; Resident*
        beq.s   .ic_done             ; NUL terminator
        move.l  d0,a1                ; a1 = resident (for InitResident)
        move.b  RT_FLAGS(a1),d2
        and.b   d4,d2
        beq.s   .ic_loop             ; not of this class (e.g. workbench.task, started by LoadWB) -> skip
        moveq   #0,d2
        move.b  RT_VERSION(a1),d2
        cmp.l   d3,d2
        bcs.s   .ic_loop             ; RT_VERSION < version -> skip
        moveq   #0,d1                ; segList = 0
        jsr     LVO_INITRESIDENT(a6)
        bra.s   .ic_loop
.ic_done:
        movem.l (sp)+,d2-d4/a2
        rts

; AddResource(resource a1): type NT_RESOURCE then Enqueue into ResourceList (Forbid-wrapped,
; like AddPort: shared list). OpenResource uses it to find the resource by name.
exec_AddResource:
        move.b  #NT_RESOURCE,LN_TYPE(a1)
        jsr     LVO_FORBID(a6)
        lea     EB_RESOURCELIST(a6),a0
        jsr     LVO_ENQUEUE(a6)
        jsr     LVO_PERMIT(a6)
        rts

; OpenResource(name a1) -> d0 = resource | 0 (search in ResourceList; no CloseResource).
exec_OpenResource:
        lea     EB_RESOURCELIST(a6),a0
        jsr     LVO_FINDNAME(a6)
        rts
