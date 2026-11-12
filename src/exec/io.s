; src/exec/io.s — exec: device input/output (OpenDevice, CloseDevice, DoIO, SendIO, CheckIO, WaitIO, AbortIO)
; and memory copies (CopyMem, CopyMemQuick: L:Ram-Handler copies all its data with CopyMem).
; Required by the BCPL disk handlers (L:Newcon-Handler, L:Aux-Handler, L:Port-Handler: globals opendevice,
; doio, sendio) and by any program that opens a device.
; IMPLEMENTATION track ("clean"): AutoDocs exec (OpenDevice/DoIO/SendIO/CheckIO/WaitIO/AbortIO) + exec/io.i +
; docs/analysis/exec-messages-io-v34.md §2-§4. NO ROM reading.

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
                xref    ram_basename
                xref    ram_freeseg
                xref    exec_SumLibrary  ; execmisc.s

DEV_OPEN        EQU -6
DEV_CLOSE       EQU -12
DEV_BEGINIO     EQU -30
DEV_ABORTIO     EQU -36

; OpenDevice(name a0, unit d0, iorequest a1, flags d1) -> d0 = io_Error sign-extended (0 = success), a0 = device |
; 0. Under Forbid: FindName in the DeviceList (first node of that name only), io_Device := device, io_Unit := 0,
; io_Error := 0, then the device's Open vector (a6 = a0 = device, a1 = request, d0 = unit, d1 = flags); the
; device's own d0 is ignored and io_Device stays set when its Open fails. Device missing: loaded from DEVS:
; (ram_loadmodule, process caller); otherwise io_Device := 0, io_Error := IOERR_OPENFAIL.
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
        move.l  a3,a1                ; the base name of a path
        jsr     ram_basename
        cmpa.l  a3,a0
        beq.s   .od_load
        move.l  a0,a1
        lea     EB_DEVICELIST(a6),a0
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        bne.s   .od_found
.od_load:
        jsr     LVO_PERMIT(a6)       ; missing: ramlib (ROM resident or DEVS:), outside Forbid
        lea     od_devsdir(pc),a0
        move.l  a3,a1
        move.l  a2,-(sp)
        lea     EB_DEVICELIST(a6),a2
        jsr     ram_loadmodule       ; d0 = node of the base name | 0
        move.l  (sp)+,a2
        jsr     LVO_FORBID(a6)
        tst.l   d0
        bne.s   .od_found
.od_nodev:
        clr.l   IO_DEVICE(a2)        ; failure: io_Device 0, io_Error -1 (ramlib-v34 §3)
        move.b  #IOERR_OPENFAIL,IO_ERROR(a2)
        sub.l   a3,a3                ; a3 = device for the caller's a0
        bra.s   .od_done
.od_found:
        move.l  d0,a3                ; a3 = device
        move.l  d0,IO_DEVICE(a2)
        clr.l   IO_UNIT(a2)
        clr.b   IO_ERROR(a2)
        movem.l a2-a3/a6,-(sp)       ; kept even for a device that does not preserve them
        move.l  a3,a6
        move.l  a3,a0
        move.l  a2,a1
        move.l  d2,d0
        move.l  d3,d1
        jsr     DEV_OPEN(a6)
        movem.l (sp)+,a2-a3/a6
.od_done:
        jsr     LVO_PERMIT(a6)
        move.l  a3,a0
        move.b  IO_ERROR(a2),d0
        ext.w   d0
        ext.l   d0
        movem.l (sp)+,d2-d3/a2-a3/a6
        rts

od_devsdir:
        dc.b    "DEVS:",0
        even

; CloseDevice(iorequest a1) -> d0 = what the Close vector returned (a seglist is freed, ramlib-v34 §2.2).
; Under Forbid; io_Device/io_Unit are not cleared.
exec_CloseDevice:
        move.l  a6,-(sp)
        jsr     LVO_FORBID(a6)
        move.l  a6,-(sp)
        move.l  IO_DEVICE(a1),a6
        move.l  DEV_CLOSE+2(a6),-(sp) ; where the Close vector jumps (the base may be gone after the call)
        jsr     DEV_CLOSE(a6)
        move.l  (sp)+,a0
        move.l  (sp)+,a6
        jsr     ram_freeseg
        move.l  d0,-(sp)
        jsr     LVO_PERMIT(a6)
        move.l  (sp)+,d0
        move.l  (sp)+,a6
        rts

; DoIO(iorequest a1) -> d0 = io_Error: io_Flags := IOF_QUICK (whole byte), BeginIO, then WaitIO if the device
; cleared IOF_QUICK. ln_Type is left alone (a device that queues a request marks it NT_MESSAGE itself). A1 and A6
; restored; the other registers are what BeginIO left.
exec_DoIO:
        move.l  a1,-(sp)
        move.b  #IOF_QUICK,IO_FLAGS(a1)
        bsr.s   io_beginio
        move.l  (sp)+,a1
        bra     exec_WaitIO

; SendIO(iorequest a1): io_Flags := 0 (whole byte), BeginIO (the reply will arrive on mn_ReplyPort). No result.
; BeginIO runs in the caller's context with no Forbid/Disable (a6 = io_Device, a1 = request).
exec_SendIO:
        clr.b   IO_FLAGS(a1)
io_beginio:
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

; WaitIO(iorequest a1) -> d0 = io_Error sign-extended. IOF_QUICK set: nothing else is done. Otherwise waits until
; ln_Type = NT_REPLYMSG (Wait on the reply port's bit; no Wait when already replied, the bit is then left as it
; is), then removes the request with its own links under Disable (the reply may come from an interrupt).
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
        move.l  MN_REPLYPORT(a2),a0  ; D1 = the reply port's signal bit, as 1.3 leaves it (exec-messages-io WI2)
        moveq   #0,d1
        move.b  MP_SIGBIT(a0),d1
.wi_err:
        move.b  IO_ERROR(a2),d0
        ext.w   d0
        ext.l   d0
        move.l  (sp)+,a2
        rts

; AbortIO(iorequest a1) -> d0 = what the device's AbortIO vector returned (a6 = io_Device, a1 = request).
exec_AbortIO:
        move.l  a6,-(sp)
        move.l  IO_DEVICE(a1),a6
        jsr     DEV_ABORTIO(a6)
        move.l  (sp)+,a6
        rts

; CopyMem(source a0, destination a1, size d0): any size and alignment, ascending copy (exec-memory-semaphores-v34
; §3: overlap works only with the destination below the source). By longs when source and destination have the
; same parity, otherwise byte by byte. Only touches d0/d1/a0/a1; a0/a1 come back just past the copied bytes (the
; file system and LoadSeg call it directly for that).
exec_CopyMem:
        move.l  a0,d1
        add.l   a1,d1                ; bit 0 of the sum = different parities
        btst    #0,d1
        bne.s   cm_bytes            ; different parities: bytes
        move.l  a0,d1
        btst    #0,d1
        beq.s   cm_even
        tst.l   d0
        beq.s   cm_ret
        move.b  (a0)+,(a1)+          ; align on an even word
        subq.l  #1,d0
; cm_even: a0/a1 even, d0 bytes. 32-byte blocks, then the tail taken from the low five bits of the size, so no
; register beyond d0/d1 is needed.
cm_even:
        move.l  d0,d1
        lsr.l   #5,d1                ; number of 32-byte blocks
        subq.l  #1,d1
        bcs.s   .cm_tail
.cm_blk:
        move.l  (a0)+,(a1)+
        move.l  (a0)+,(a1)+
        move.l  (a0)+,(a1)+
        move.l  (a0)+,(a1)+
        move.l  (a0)+,(a1)+
        move.l  (a0)+,(a1)+
        move.l  (a0)+,(a1)+
        move.l  (a0)+,(a1)+
        dbra    d1,.cm_blk
        sub.l   #$10000,d1           ; dbra counts 16 bits: 65536 more blocks while the high word is not spent
        bcc.s   .cm_blk
.cm_tail:
        btst    #4,d0
        beq.s   .cm_t8
        move.l  (a0)+,(a1)+
        move.l  (a0)+,(a1)+
        move.l  (a0)+,(a1)+
        move.l  (a0)+,(a1)+
.cm_t8:
        btst    #3,d0
        beq.s   .cm_t4
        move.l  (a0)+,(a1)+
        move.l  (a0)+,(a1)+
.cm_t4:
        btst    #2,d0
        beq.s   .cm_t2
        move.l  (a0)+,(a1)+
.cm_t2:
        btst    #1,d0
        beq.s   .cm_t1
        move.w  (a0)+,(a1)+
.cm_t1:
        btst    #0,d0
        beq.s   cm_ret
        move.b  (a0)+,(a1)+
        rts
cm_bytes:
        bra.s   cm_bnext
cm_byte:
        move.b  (a0)+,(a1)+
cm_bnext:
        subq.l  #1,d0
        bcc.s   cm_byte
cm_ret:
        rts
; CopyMemQuick(source a0, destination a1, size d0): even pointers; copies size & ~3 bytes (the low two bits of the
; size are ignored, as in 1.3).
exec_CopyMemQuick:
        and.w   #$FFFC,d0
        bra.s   cm_even

; AddLibrary(library a1) / AddDevice(device a1): under Forbid, the SumLibrary step when LIBF_SUMUSED is set (sum
; recomputed with LIBF_CHANGED, otherwise verified: a wrong sum is the dead-end alert), then Enqueue into LibList /
; DeviceList. ln_Type is not set. RemLibrary / RemDevice(a1): the module's Expunge vector (a6 = a1 = d0 = module)
; -> d0 = what Expunge returned (a seglist is freed); exec does not unlink the node, Expunge does.
exec_AddLibrary:
        lea     EB_LIBLIST(a6),a0
        bra.s   io_addnode
exec_AddDevice:
        lea     EB_DEVICELIST(a6),a0
io_addnode:
        jsr     LVO_FORBID(a6)
        btst    #LIBB_SUMUSED,LIB_FLAGS(a1)
        beq.s   .an_add
        move.l  a0,-(sp)
        jsr     exec_SumLibrary
        move.l  (sp)+,a0
.an_add:
        jsr     LVO_ENQUEUE(a6)
        jmp     LVO_PERMIT(a6)
exec_RemLibrary:
exec_RemDevice:
        move.l  a6,-(sp)
        jsr     LVO_FORBID(a6)
        move.l  a6,-(sp)
        move.l  a1,a6
        move.l  a1,d0
        move.l  -16(a6),-(sp)        ; where the Expunge vector jumps
        jsr     -18(a6)              ; Expunge
        move.l  (sp)+,a0
        move.l  (sp)+,a6
        jsr     ram_freeseg
        move.l  d0,-(sp)
        jsr     LVO_PERMIT(a6)
        move.l  (sp)+,d0
        move.l  (sp)+,a6
        rts
