; src/exec/io.s — exec: device input/output (OpenDevice, CloseDevice, DoIO, SendIO, CheckIO, WaitIO, AbortIO)
; and memory copies (CopyMem, CopyMemQuick: L:Ram-Handler copies all its data with CopyMem).
; Required by the BCPL disk handlers (L:Newcon-Handler, L:Aux-Handler, L:Port-Handler: globals opendevice,
; doio, sendio) and by any program that opens a device.
; IMPLEMENTATION track ("clean"): AutoDocs exec (OpenDevice/DoIO/SendIO/CheckIO/WaitIO/AbortIO) + exec/io.i.
; NO ROM reading.

                include "exec.i"

                xdef    exec_OpenDevice
                xdef    exec_CloseDevice
                xdef    exec_DoIO
                xdef    exec_SendIO
                xdef    exec_CheckIO
                xdef    exec_WaitIO
                xdef    exec_AbortIO
                xdef    exec_CopyMem
                xdef    exec_CopyMemQuick
                xdef    exec_AddLibrary
                xdef    exec_RemLibrary
                xdef    exec_AddDevice
                xdef    exec_RemDevice
                xref    ram_loadmodule   ; ramlib.s

DEV_OPEN        EQU -6
DEV_CLOSE       EQU -12
DEV_BEGINIO     EQU -30
DEV_ABORTIO     EQU -36

; OpenDevice(name a0, unit d0, iorequest a1, flags d1) -> d0 = io_Error (0 = success). Under Forbid: FindName in the
; DeviceList, io_Device := device, io_Error := 0, then the device's Open vector (a6 = device, a1/d0/d1 passed on).
; Device missing: loaded from DEVS: (ram_loadmodule, process caller); otherwise io_Error = IOERR_OPENFAIL.
exec_OpenDevice:
        movem.l d2-d3/a2-a3/a6,-(sp)
        move.l  a1,a2                ; a2 = iorequest
        move.l  d0,d2                ; d2 = unit
        move.l  d1,d3                ; d3 = flags
        move.l  a0,a3                ; a3 = name
        jsr     LVO_FORBID(a6)
        lea     EB_DEVICELIST(a6),a0
        move.l  a3,a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        bne.s   .od_found
        jsr     LVO_PERMIT(a6)       ; missing: load from DEVS: (ramlib), outside Forbid
        lea     od_devsdir(pc),a0
        move.l  a3,a1
        jsr     ram_loadmodule
        jsr     LVO_FORBID(a6)
        tst.l   d0
        beq.s   .od_nodev
        lea     EB_DEVICELIST(a6),a0
        move.l  a3,a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        bne.s   .od_found
.od_nodev:
        move.b  #IOERR_OPENFAIL,IO_ERROR(a2)
        bra.s   .od_done
.od_found:
        move.l  d0,IO_DEVICE(a2)
        clr.b   IO_ERROR(a2)
        move.l  a6,-(sp)
        move.l  d0,a6
        move.l  a2,a1
        move.l  d2,d0
        move.l  d3,d1
        jsr     DEV_OPEN(a6)
        move.l  (sp)+,a6
.od_done:
        jsr     LVO_PERMIT(a6)
        move.b  IO_ERROR(a2),d0
        ext.w   d0
        ext.l   d0
        movem.l (sp)+,d2-d3/a2-a3/a6
        rts

od_devsdir:
        dc.b    "DEVS:",0
        even

; CloseDevice(iorequest a1): Close vector of the request's device.
exec_CloseDevice:
        move.l  a6,-(sp)
        jsr     LVO_FORBID(a6)
        move.l  a6,-(sp)
        move.l  IO_DEVICE(a1),a6
        jsr     DEV_CLOSE(a6)
        move.l  (sp)+,a6
        jsr     LVO_PERMIT(a6)
        move.l  (sp)+,a6
        rts

; DoIO(iorequest a1) -> d0 = io_Error: BeginIO in quick mode (IOF_QUICK), then WaitIO if the device has queued
; the request.
exec_DoIO:
        move.l  a1,-(sp)
        move.b  #IOF_QUICK,IO_FLAGS(a1)
        bsr.s   io_beginio
        move.l  (sp)+,a1
        bra     exec_WaitIO

; SendIO(iorequest a1): asynchronous BeginIO (the reply will arrive on mn_ReplyPort).
exec_SendIO:
        clr.b   IO_FLAGS(a1)
io_beginio:
        move.b  #NT_MESSAGE,LN_TYPE(a1)
        move.l  a6,-(sp)
        move.l  IO_DEVICE(a1),a6
        jsr     DEV_BEGINIO(a6)
        move.l  (sp)+,a6
        rts

; CheckIO(iorequest a1) -> d0 = a1 if the request is complete (quick or replied), otherwise 0.
exec_CheckIO:
        moveq   #0,d0
        btst    #0,IO_FLAGS(a1)      ; IOF_QUICK
        bne.s   .ci_done
        cmp.b   #NT_REPLYMSG,LN_TYPE(a1)
        bne.s   .ci_ret
.ci_done:
        move.l  a1,d0
.ci_ret:
        rts

; WaitIO(iorequest a1) -> d0 = io_Error: waits for the reply (Wait on the reply port's bit) then removes the request
; from the port (under Disable: the reply may come from an interrupt).
exec_WaitIO:
        move.l  a2,-(sp)
        move.l  a1,a2
        btst    #0,IO_FLAGS(a2)
        bne.s   .wi_err
.wi_wait:
        cmp.b   #NT_REPLYMSG,LN_TYPE(a2)
        beq.s   .wi_got
        move.l  MN_REPLYPORT(a2),a0
        moveq   #0,d1
        move.b  MP_SIGBIT(a0),d1
        moveq   #0,d0
        bset    d1,d0
        jsr     LVO_WAIT(a6)
        bra.s   .wi_wait
.wi_got:
        jsr     LVO_DISABLE(a6)
        move.l  a2,a1
        jsr     LVO_REMOVE(a6)
        jsr     LVO_ENABLE(a6)
.wi_err:
        move.b  IO_ERROR(a2),d0
        ext.w   d0
        ext.l   d0
        move.l  (sp)+,a2
        rts

; AbortIO(iorequest a1): AbortIO vector of the device.
exec_AbortIO:
        move.l  a6,-(sp)
        move.l  IO_DEVICE(a1),a6
        jsr     DEV_ABORTIO(a6)
        move.l  (sp)+,a6
        rts

; CopyMem(source a0, destination a1, size d0): byte copy with no alignment required (AutoDoc: disjoint areas).
; By longs when source and destination have the same parity, otherwise byte by byte. Only touches d0/d1/a0/a1.
exec_CopyMem:
        move.l  a0,d1
        add.l   a1,d1                ; bit 0 of the sum = different parities
        btst    #0,d1
        bne.s   cm_bytes            ; different parities: bytes
        move.l  a0,d1
        btst    #0,d1
        beq.s   exec_CopyMemQuick
        tst.l   d0
        beq.s   cm_ret
        move.b  (a0)+,(a1)+          ; align on an even word
        subq.l  #1,d0
; CopyMemQuick(source a0, destination a1, size d0): source/destination aligned; longs then remainder in bytes.
exec_CopyMemQuick:
        move.l  d0,d1
        lsr.l   #2,d1                ; number of longs
        bra.s   .cq_lnext
.cq_long:
        move.l  (a0)+,(a1)+
.cq_lnext:
        subq.l  #1,d1
        bcc.s   .cq_long
        and.l   #3,d0
cm_bytes:
        bra.s   cm_bnext
cm_byte:
        move.b  (a0)+,(a1)+
cm_bnext:
        subq.l  #1,d0
        bcc.s   cm_byte
cm_ret:
        rts

; AddLibrary(library a1) / AddDevice(device a1): Enqueue into LibList / DeviceList under Forbid (a module loaded
; from disk that does its own MakeLibrary registers itself this way). RemLibrary / RemDevice(a1): call of the
; module's Expunge vector (a6 = module) -> d0 = seglist returned by Expunge (0 if the module refuses).
exec_AddLibrary:
        lea     EB_LIBLIST(a6),a0
        bra.s   io_addnode
exec_AddDevice:
        lea     EB_DEVICELIST(a6),a0
io_addnode:
        movem.l a0-a1,-(sp)
        jsr     LVO_FORBID(a6)
        movem.l (sp)+,a0-a1
        jsr     LVO_ENQUEUE(a6)
        jmp     LVO_PERMIT(a6)
exec_RemLibrary:
exec_RemDevice:
        move.l  a6,-(sp)
        jsr     LVO_FORBID(a6)
        move.l  a6,-(sp)
        move.l  a1,a6
        jsr     -18(a6)              ; Expunge
        move.l  (sp)+,a6
        move.l  d0,-(sp)
        jsr     LVO_PERMIT(a6)
        move.l  (sp)+,d0
        move.l  (sp)+,a6
        rts
