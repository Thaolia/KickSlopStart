; src/dos/dos_lib.s - dos.library (M6: resident skeleton + BPTR convention + DateStamp).
; Modelled on intuition_lib.s (M5): RTF_AUTOINIT NT_LIBRARY ROMTag, auto-scanned by build_reslist -> MakeLibrary
; creates DosBase, Enqueue into EB_LIBLIST. Pri 0 (dos roadmap position: init last, after all the other residents).
;
; Accepted clean-room deviation: the real 1.3 dos.library is a BCPL port (init via BCPL glue, global vector).
; We reproduce the OBSERVABLE ABI (DosBase + RootNode + DosInfo linked by BPTR, DateStamp), not the BCPL mechanism -
; same approach as AROS rom/dos (C rewrite keeping BPTRs). Outside M6 (deferred): packets, LoadSeg, handlers,
; Open/Read/Lock..., strap/trackdisk, insert-disk screen (-> later M6 increments).
;
; BPTR convention (dos's signature quirk): a BPTR is an address divided by 4 (addr>>2). Reversibility of
; <<2/>>2 REQUIRES long-aligned structures -> RootNode and DosInfo are allocated SEPARATELY via AllocMem (exec aligns
; >= 8), never embedded in DosBase (whose end, offset 70, is not a multiple of 4).
;
; IMPLEMENTATION track ("clean"): dos.library AutoDocs + NDK includes/.fd (public). NO ROM reading.

                include "exec.i"
                include "dos.i"
                include "dospkt.i"       ; D3c : FileHandle / DosPacket / ACTION_* / DeviceNode / PR_MSGPORT
                include "expansion.i"    ; eb_MountList / BootNode (boot device)

                xref    conwin_seg
                xref    rcli_seg
                xref    dos_sendpkt      ; dos/process.s (D3: sending a DOS packet)
                xref    ls_load_stream   ; dos/loadseg.s (parses hunks as they are read -> BPTR seglist)
                xref    dos_unloadseg    ; dos/loadseg.s (frees a segment chain)
                xref    timer_now        ; exec/timer.s (system time for DateStamp)
                xref    timer_setnow
                xdef    dos_now
                xdef    dos_setnow
                xref    newlist          ; exec/lists.s (NEWLIST of the Delay port)
                xref    bcpl_starthandler ; dos/bcpl.s (startup of a DeviceNode's handler)
                xref    bcpl_execute     ; dos/bcpl.s (Execute LVO: C:Run + runcommand)
                xdef    dos_bufwrite     ; deferred writing of the BCPL runtime (bcpl.s)
                xdef    dos_flushout     ; flush of the current output before a read (bcpl.s)
                xdef    dos_pktretry     ; "Please replace volume" requester after a 218 refusal (process.s, bcpl.s)
                xref    proc_create      ; dos/process.s (Process + pile + pr_MsgPort + AddTask)
                xdef    dos_boot_assigns ; called by the initial CLI (shell.s) once the boot disk is readable
                xdef    dos_resolve      ; BCPL runtime (deviceproc)
                xdef    dos_mountlist    ; exec/boot.s: mount list, boot device
                xdef    dos_df0bootnode  ; exec/boot.s: DF0: BootNode after a bootblock
                xref    boot_dos_start   ; exec/boot.s: rest of the startup (Initial CLI), does not return


; --- dos.library ROMTag (scanned by build_reslist) ---
        EVEN
dos_romtag:
        dc.w    RTC_MATCHWORD
        dc.l    dos_romtag               ; RT_MATCHTAG = self
        dc.l    dos_end                  ; RT_ENDSKIP
        dc.b    RTF_COLDSTART,34,NT_LIBRARY,0   ; RT_FLAGS, RT_VERSION, RT_TYPE, RT_PRI (0: dos roadmap position)
        dc.l    dos_name                 ; RT_NAME
        dc.l    dos_name                 ; RT_IDSTRING
        dc.l    dos_rtinit               ; RT_INIT -> code (a bootblock gets it in A0, a BootPoint calls it)
dos_name:
        dc.b    "dos.library",0
exp_libname:
        dc.b    "expansion.library",0
        EVEN

; rt_Init of dos.library (a6 = ExecBase), code as in 1.3 and not an AUTOINIT table: the BootPoint of a board
; (spec uae-hd-boot-v34 §2.2, §6) does FindResident("dos.library") then calls rt_Init. First call (InitCode,
; COLDSTART): the library is built (MakeLibrary + Enqueue into LibList) -> d0 = DosBase. Subsequent call
; (dos already exists): dos starts on the expansion mount list (boot_dos_start, does not return).
dos_rtinit:
        move.l  ($4).w,a6
        lea     EB_LIBLIST(a6),a0
        lea     dos_name(pc),a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        beq.s   .ri_make
        jmp     boot_dos_start
.ri_make:
        move.l  a2,-(sp)
        lea     dos_vectors(pc),a0
        lea     dos_datatab(pc),a1
        lea     dos_initfunc(pc),a2
        move.l  #DOSBASE_DATASIZE,d0
        moveq   #0,d1
        jsr     LVO_MAKELIBRARY(a6)
        move.l  (sp)+,a2
        tst.l   d0
        beq.s   .ri_ret
        move.l  d0,a1
        lea     EB_LIBLIST(a6),a0
        jsr     LVO_ENQUEUE(a6)
        move.l  a1,d0
.ri_ret:
        rts
; ABSOLUTE table terminated by -1. Vector N -> LVO -6*N. D3c: Open(-30,v5)/Close(-36,v6)/Read(-42,v7) implemented
; (via packets to the file-handler). LoadSeg(-150,v25)/UnLoadSeg(-156,v26) combine Open/Read + ls_load_stream.
; The other vectors point to dos_null (not implemented).
dos_vectors:
        dc.l    dos_open                 ; 1: LVO -6  (LIBRARY Open: OpenCnt++)
        dc.l    dos_close                ; 2: LVO -12 (LIBRARY Close)
        dc.l    dos_expunge              ; 3: LVO -18
        dc.l    dos_null                 ; 4: LVO -24 (reserved)
                ifd     DOSTRACE
        dc.l    dtr_open                 ; 5: LVO -30 Open(name d1, mode d2) -> BPTR FileHandle
                else
        dc.l    dos_fn_open              ; 5: LVO -30 Open(name d1, mode d2) -> BPTR FileHandle
                endc
                ifd     DOSTRACE
        dc.l    dtr_close               ; 6: LVO -36 Close(fh d1)
                else
        dc.l    dos_fn_close             ; 6: LVO -36 Close(fh d1)
                endc
                ifd     DOSTRACE
        dc.l    dtr_read                 ; 7: LVO -42 Read(fh d1, buf d2, len d3) -> bytes
                else
        dc.l    dos_fn_read              ; 7: LVO -42 Read(fh d1, buf d2, len d3) -> bytes
                endc
                ifd     DOSTRACE
        dc.l    dtr_write               ; 8 : LVO -48 Write(fh d1, buf d2, len d3) -> bytes written
                else
        dc.l    dos_fn_write             ; 8 : LVO -48 Write(fh d1, buf d2, len d3) -> bytes written
                endc
        dc.l    dos_fn_input             ; 9 : LVO -54 Input() -> BPTR pr_CIS
        dc.l    dos_fn_output            ; 10: LVO -60 Output() -> BPTR pr_COS
                ifd     DOSTRACE
        dc.l    dtr_seek                 ; 11: LVO -66 Seek(fh d1, position d2, mode d3)
                else
        dc.l    dos_fn_seek              ; 11: LVO -66 Seek(fh d1, position d2, mode d3)
                endc
        dc.l    dos_fn_deletefile        ; 12: LVO -72  DeleteFile(name d1)
        dc.l    dos_fn_rename            ; 13: LVO -78  Rename(old d1, new d2)
                ifd     DOSTRACE
        dc.l    dtr_lock                 ; 14: LVO -84  Lock(name d1, mode d2) -> BPTR FileLock
                else
        dc.l    dos_fn_lock              ; 14: LVO -84  Lock(name d1, mode d2) -> BPTR FileLock
                endc
        dc.l    dos_fn_unlock            ; 15: LVO -90  UnLock(lock d1)
        dc.l    dos_fn_duplock           ; 16: LVO -96  DupLock(lock d1) -> new lock
        dc.l    dos_fn_examine           ; 17: LVO -102 Examine(lock d1, fib d2)
        dc.l    dos_fn_exnext            ; 18: LVO -108 ExNext(lock d1, fib d2)
        dc.l    dos_fn_info              ; 19: LVO -114 Info(lock d1, infodata d2)
        dc.l    dos_fn_createdir         ; 20: LVO -120 CreateDir(name d1) -> BPTR lock
        dc.l    dos_fn_currentdir        ; 21: LVO -126 CurrentDir(lock d1) -> old lock
        dc.l    dos_fn_ioerr             ; 22: LVO -132 IoErr() -> pr_Result2
        dc.l    dos_fn_createproc        ; 23: LVO -138 CreateProc(name d1, pri d2, seglist d3, stack d4)
        dc.l    dos_null                 ; 24: LVO -144 (Exit not implemented)
                ifeq    LOADSEG_LVO_UNWIRED
        dc.l    dos_fn_loadseg           ; 25: LVO -150 LoadSeg(name d1) -> BPTR seglist
                endc
                ifne    LOADSEG_LVO_UNWIRED
        dc.l    dos_null                 ; RED LOADSEG_LVO_UNWIRED: LoadSeg not wired -> jsr -150 returns 0
                endc
        dc.l    dos_fn_unloadseg         ; 26: LVO -156 UnLoadSeg(seglist d1)
        dcb.l   2,dos_null               ; 27..28: LVO -162/-168 (GetPacket/QueuePacket, private)
        dc.l    dos_fn_deviceproc        ; 29: LVO -174 DeviceProc(name d1) -> handler port
        dc.l    dos_fn_setcomment        ; 30: LVO -180 SetComment(name d1, comment d2)
        dc.l    dos_fn_setprotection     ; 31: LVO -186 SetProtection(name d1, mask d2)
        dc.l    dos_DateStamp            ; 32: LVO -192
        dc.l    dos_fn_delay             ; 33: LVO -198 Delay(ticks d1)
        dc.l    dos_fn_waitforchar       ; 34: LVO -204 WaitForChar(fh d1, us d2)
        dc.l    dos_fn_parentdir         ; 35: LVO -210 ParentDir(lock d1)
        dc.l    dos_fn_isinteractive     ; 36: LVO -216 IsInteractive(fh d1)
        dc.l    bcpl_execute             ; 37: LVO -222 Execute(cmd d1, in d2, out d3) - last V34 LVO (bcpl.s)
        dc.l    -1
dos_datatab:
        dc.w    $E000,LN_TYPE,(NT_LIBRARY<<8)   ; INITBYTE(LN_TYPE, NT_LIBRARY)
        dc.w    $D000,LIB_VERSION,34            ; INITWORD(LIB_VERSION, 34)
        dc.b    0
        EVEN

; Open(lib a6): increments the open count, returns the base (OpenLibrary convention).
dos_open:
        addq.w  #1,LIB_OPENCNT(a6)
        move.l  a6,d0
        rts
dos_close:
        subq.w  #1,LIB_OPENCNT(a6)
        moveq   #0,d0
        rts
dos_expunge:
        moveq   #0,d0               ; no expunge in this milestone (resident base)
        rts
dos_null:
        moveq   #0,d0
        rts

; DateStamp(date d1) (a6 = DosBase) -> d0 = date; clock never set: the three fields are 0.
; Our clock is NOT set (neither battclock nor dl_TimeReq wired up in this milestone) -> (0,0,0) is the FAITHFUL
; V34 behaviour, not a stub. Returns the pointer passed in (pre-V36 compat). Arg in d1 (BCPL-derived dos: args in D1..).
dos_DateStamp:
        move.l  d1,a0
        bsr.s   dos_now
        move.l  d1,d0               ; return &date
        rts

; dos_now(a0 = DateStamp: days, minutes, ticks): system time from timer.device (seconds since 1 January 1978)
; converted into days, minutes of the day and 50ths of a second within the minute. Preserves d1-d7/a0-a6.
dos_now:
        movem.l d1-d3/a0-a1/a6,-(sp)
        move.l  ($4).w,a6
        jsr     timer_now           ; d0 = seconds, d1 = us
        move.l  12(sp),a0           ; incoming a0 (timer_now does not preserve it)
        move.l  d1,d3               ; d3 = us
        move.l  d0,d1
        lsr.l   #1,d1               ; seconds / 2: the quotient by 43200 fits in 16 bits (divu)
        divu    #43200,d1
        moveq   #0,d2
        move.w  d1,d2
        move.l  d2,(a0)             ; ds_Days
        clr.w   d1
        swap    d1                  ; remainder of (seconds / 2) / 43200
        add.l   d1,d1
        and.l   #1,d0
        add.l   d0,d1               ; d1 = seconds of the day
        divu    #60,d1
        moveq   #0,d2
        move.w  d1,d2
        move.l  d2,4(a0)            ; ds_Minute
        swap    d1                  ; seconds within the minute
        mulu    #50,d1
        divu    #20000,d3           ; us -> 50ths
        and.l   #$FFFF,d3
        add.l   d3,d1
        and.l   #$FFFF,d1
        move.l  d1,8(a0)            ; ds_Tick
        move.l  DOS_DOSBASE,a1      ; copy into rn_Time of the RootNode (public time cache)
        move.l  DL_ROOT(a1),a1
        move.l  (a0),RN_TIME(a1)
        move.l  4(a0),RN_TIME+4(a1)
        move.l  8(a0),RN_TIME+8(a1)
        movem.l (sp)+,d1-d3/a0-a1/a6
        rts

; dos_setnow(a0 = DateStamp): sets the system time to these days / minutes / ticks (no range check), then
; refreshes rn_Time. Preserves d2-d7/a2-a6.
dos_setnow:
        movem.l d2/a0/a6,-(sp)
        move.l  (a0),d0             ; days x 86400 = days x 43200 x 2 (16-bit mulu)
        mulu    #43200,d0
        add.l   d0,d0
        move.l  4(a0),d1            ; + minutes x 60
        mulu    #60,d1
        add.l   d1,d0
        move.l  8(a0),d1            ; + ticks / 50; us = (ticks mod 50) x 20000
        divu    #50,d1
        moveq   #0,d2
        move.w  d1,d2
        add.l   d2,d0
        clr.w   d1
        swap    d1
        mulu    #20000,d1
        move.l  ($4).w,a6
        jsr     timer_setnow
        lea     -12(sp),sp
        move.l  sp,a0
        bsr     dos_now
        lea     12(sp),sp
        movem.l (sp)+,d2/a0/a6
        rts

; --- D3c: user-facing Open / Read / Close (via DOS packets to the DF0: file-handler) ---
; Called from a PROCESS (dos_sendpkt uses ThisTask->pr_MsgPort as the reply port). a6 = DosBase on
; entry (library convention); we switch a6 = SysBase for exec calls (AllocMem/FreeMem/dos_sendpkt).
; No public DoPkt in V34: dos_sendpkt is the internal equivalent. BCPL-derived argument convention (D1, D2, D3...).
; Name resolution by dos_resolve (device/assign/volume prefix, otherwise current directory). StandardPacket local to
; the caller's (process) stack.

; Open(name d1 [C string], accessMode d2 [= ACTION_FIND* code]) -> d0 = BPTR FileHandle | 0. The name "*" denotes the
; process's console: the packet goes to pr_ConsoleTask (lock 0, name "*" passed on), as under AmigaDOS. Any
; non-zero value of dp_Res1 means success.
dos_fn_open:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  d1,a4                   ; a4 = name (C string)
        move.l  d2,d7                   ; d7 = mode (= dp_Type ACTION_FINDINPUT)
        cmp.b   #'*',(a4)
        bne.s   .op_resolve
        tst.b   1(a4)
        bne.s   .op_resolve
        move.l  ($4).w,a0
        move.l  EB_THISTASK(a0),a0
        move.l  PR_CONSOLETASK(a0),a3
        moveq   #0,d6
        move.l  a3,d0
        bne.s   .op_port
        move.l  #ERROR_OBJECT_NOT_FOUND,PR_RESULT2(a0)
        bra     .op_fail_early          ; no console
.op_resolve:
        move.b  (a4),d0                 ; "NIL:" (case ignored; any name at an odd address: bytes):
        lsl.w   #8,d0                   ; FileHandle without a handler (fh_Type = 0) -> Read returns 0 (end of file),
        move.b  1(a4),d0                ; Write returns the length, Close frees
        swap    d0
        move.b  2(a4),d0
        lsl.w   #8,d0
        move.b  3(a4),d0
        and.l   #$DFDFDFFF,d0
        cmp.l   #$4E494C3A,d0           ; "NIL:"
        bne.s   .op_named
        suba.l  a3,a3
        bra.s   .op_port
.op_named:
        bsr     dos_resolve             ; a3 = handler port, d6 = starting lock, a4 = name to pass on
        move.l  a3,d0
        beq     .op_fail_early          ; unknown device / handler not started
.op_port:
        move.l  ($4).w,a6               ; -> SysBase for exec calls
        move.l  #DOS_FH_ALLOC+4,d0      ; FileHandle in getvec format: [size][FileHandle + name]
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.s   .op_fail_early
        move.l  d0,a2
        move.l  #DOS_FH_ALLOC+4,(a2)+   ; a2 = FileHandle (long-aligned: BPTR)
        lea     FH_SIZEOF(a2),a5        ; a5 = BSTR buffer of the name (long-aligned)
        lea     1(a5),a1                ; a1 -> characters
        moveq   #0,d3                   ; d3 = length
.op_ncpy:
        move.b  (a4)+,d0
        beq.s   .op_ndone
        move.b  d0,(a1)+
        addq.l  #1,d3
        cmp.l   #DOS_NAMEMAX,d3         ; bound of the buffer (BSTR)
        bcs.s   .op_ncpy
.op_ndone:
        move.b  d3,(a5)                 ; BCPL length byte
        move.l  a3,d0
        beq.s   .op_ok                  ; NIL: no handler
                ifeq    D3C_NO_FHTYPE
        move.l  a3,FH_TYPE(a2)          ; fh_Type = handler port (route of subsequent Read/Close)
                endc                    ; RED D3C_NO_FHTYPE: fh_Type stays 0 -> Read does not route
        lea     -SP_SIZEOF(sp),sp       ; StandardPacket on the process stack
        move.l  sp,a0
        move.l  a3,a1                   ; handler port
        move.l  d7,d0                   ; dp_Type = mode (ACTION_FINDINPUT)
        move.l  a2,d1
        lsr.l   #2,d1                   ; ARG1 = BPTR(FileHandle) (the handler sets fh_Arg1 in it)
        move.l  d6,d2                   ; ARG2 = lock of the starting directory
        move.l  a5,d3
        lsr.l   #2,d3                   ; ARG3 = BPTR(BSTR name)
        jsr     dos_sendpkt             ; d0 = dp_Res1
        lea     SP_SIZEOF(sp),sp
        tst.l   d0
        beq.s   .op_fail_free
.op_ok:
        moveq   #-1,d0
        move.l  d0,FH_POS(a2)           ; fh_Pos = fh_End = -1: BCPL buffer empty (rdch will fill it through Read)
        move.l  d0,FH_END(a2)
        move.l  a2,d0                   ; success -> BPTR(FileHandle)
        lsr.l   #2,d0
        bra.s   .op_ret
.op_fail_free:
        lea     -4(a2),a1
        move.l  #DOS_FH_ALLOC+4,d0
        jsr     LVO_FREEMEM(a6)
.op_fail_early:
        moveq   #0,d0
.op_ret:
        movem.l (sp)+,d2-d7/a2-a6
        rts

; Read(fh d1 [BPTR FileHandle], buf d2, len d3) -> d0 = bytes read (0 = EOF, -1 = error).
dos_fn_read:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  d2,d5                   ; buf
        move.l  d3,d6                   ; len
        move.l  d1,d4
        lsl.l   #2,d4
        beq.s   .rd_err                 ; null fh -> error (no read of address $8)
        move.l  d4,a2                   ; a2 = BADDR(fh)
        move.l  FH_TYPE(a2),a3          ; handler port
        move.l  a3,d0
        beq.s   .rd_zero                ; fh_Type==0 (not routed) -> 0 (RED D3C_NO_FHTYPE safeguard)
        bsr     dos_flushfh
        move.l  FH_ARG1(a2),d4          ; key of the file
        move.l  ($4).w,a6               ; SysBase
        lea     -SP_SIZEOF(sp),sp
        move.l  sp,a0
        move.l  a3,a1
        move.l  #ACTION_READ,d0
        move.l  d4,d1                   ; ARG1 = key
        move.l  d5,d2                   ; ARG2 = buffer
        move.l  d6,d3                   ; ARG3 = length
        jsr     dos_sendpkt             ; d0 = bytes read
        lea     SP_SIZEOF(sp),sp
        bra.s   .rd_ret
.rd_err:
        moveq   #-1,d0
        bra.s   .rd_ret
.rd_zero:
        moveq   #0,d0
.rd_ret:
        movem.l (sp)+,d2-d7/a2-a6
        rts

                ifd     DOSTRACE
; Diagnostic traces (ROM -DDOSTRACE=1 only): each call emits "X args -> result" on serial.
                xref    ser_puts
                xref    ser_puthex
dtr_open:
        movem.l d1-d2,-(sp)
        bsr     dos_fn_open
        movem.l d0/a0,-(sp)
        lea     dtr_to(pc),a0
        bsr     dtr_puts
        move.l  8(sp),a0             ; name
        bsr     dtr_puts
        move.l  12(sp),d0            ; mode
        bra.s   dtr_end2
dtr_lock:
        movem.l d1-d2,-(sp)
        bsr     dos_fn_lock
        movem.l d0/a0,-(sp)
        lea     dtr_tl(pc),a0
        bsr     dtr_puts
        move.l  8(sp),a0
        bsr     dtr_puts
        move.l  12(sp),d0
dtr_end2:
        bsr     dtr_hex
        move.l  (sp),d0              ; result
        bsr     dtr_hex
        movem.l (sp)+,d0/a0
        addq.l  #8,sp
        rts
dtr_close:
        move.l  d1,-(sp)
        bsr     dos_fn_close
        movem.l d0/a0,-(sp)
        lea     dtr_tc(pc),a0
        bsr     dtr_puts
        move.l  8(sp),d0
        bsr     dtr_hex
        movem.l (sp)+,d0/a0
        addq.l  #4,sp
        rts
dtr_read:
        lea     dtr_tr(pc),a0
        pea     dos_fn_read(pc)
        bra.s   dtr_3
dtr_write:
        lea     dtr_tw(pc),a0
        pea     dos_fn_write(pc)
        bra.s   dtr_3
dtr_seek:
        lea     dtr_ts(pc),a0
        pea     dos_fn_seek(pc)
dtr_3:                               ; (fh d1, arg d2, arg d3): function at (sp), label a0
        move.l  (sp)+,a1
        movem.l d1-d3/a0,-(sp)
        jsr     (a1)
        movem.l d0/a0,-(sp)
        move.l  8+12(sp),a0
        bsr     dtr_puts
        move.l  8(sp),d0             ; fh
        bsr     dtr_hex
        move.l  8+4(sp),d0           ; position / buffer
        bsr     dtr_hex
        move.l  8+8(sp),d0           ; mode / length
        bsr     dtr_hex
        move.l  (sp),d0
        bsr     dtr_hex
        movem.l (sp)+,d0/a0
        lea     16(sp),sp
        rts
dtr_hex:                             ; d0.l as 8 digits + space
        swap    d0
        jsr     ser_puthex
        swap    d0
        jsr     ser_puthex
        move.l  a0,-(sp)
        lea     dtr_sp(pc),a0
        bsr.s   dtr_puts
        move.l  (sp)+,a0
        rts
dtr_puts:
        movem.l d0-d1/a0-a1,-(sp)
        jsr     ser_puts
        movem.l (sp)+,d0-d1/a0-a1
        rts
dtr_to:         dc.b    10,"O ",0
dtr_tl:         dc.b    10,"L ",0
dtr_tc:         dc.b    10,"C ",0
dtr_tr:         dc.b    10,"R ",0
dtr_tw:         dc.b    10,"W ",0
dtr_ts:         dc.b    10,"S ",0
dtr_sp:         dc.b    " ",0
                even
                endc

; Close(fh d1 [BPTR FileHandle]) -> d0 = DOSTRUE.
dos_fn_close:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  d1,d4
        lsl.l   #2,d4
        beq     .cl_null                ; null fh -> nothing to close
        move.l  d4,a2                   ; a2 = BADDR(fh)
        bsr     dos_flushfh             ; deferred bytes written, then buffer freed
        cmp.l   #DOS_FH_ALLOC+4,-4(a2)
        bne.s   .cl_nowbuf
        move.l  FH_WBUF(a2),d0
        beq.s   .cl_nowbuf
        clr.l   FH_WBUF(a2)
        move.l  d0,a1
        move.l  #DOS_WBUF,d0
        move.l  ($4).w,a6
        jsr     LVO_FREEMEM(a6)
.cl_nowbuf:
        move.l  FH_TYPE(a2),a3
        move.l  a3,d0
        beq.s   .cl_free                ; not routed -> just free
        move.l  FH_ARG1(a2),d4          ; key
        move.l  ($4).w,a6
        lea     -SP_SIZEOF(sp),sp
        move.l  sp,a0
        move.l  a3,a1
        move.l  #ACTION_END,d0
        move.l  d4,d1                   ; ARG1 = key
        moveq   #0,d2
        moveq   #0,d3
        jsr     dos_sendpkt
        lea     SP_SIZEOF(sp),sp
        bra.s   .cl_free2
.cl_free:
        move.l  ($4).w,a6
.cl_free2:
        ; FileHandle = getvec block (size at -4, BCPL spec §5.1): those built by BCPL programs (e.g. the
        ; memory FileHandle of c:Run) arrive here too -> freed using the header size, never a fixed size.
        ; fh_Buf is only freed if it belongs to the runtime (rdch getvec buffer, OUTSIDE the FileHandle block).
        move.l  -4(a2),d5               ; d5 = size of the FileHandle block (header included)
        move.l  FH_BUF(a2),d0
        lsl.l   #2,d0
        beq.s   .cl_nobuf
        move.l  d0,a1
        move.l  a2,d1
        subq.l  #4,d1                   ; start of the FileHandle block
        cmp.l   d1,a1
        bcs.s   .cl_bufown
        add.l   d5,d1
        cmp.l   d1,a1
        bcs.s   .cl_nobuf               ; buffer inside the block (memory FileHandle): nothing to free
.cl_bufown:
        cmp.l   #(RT_FHBUFLONGS+2)*4,-4(a1)
        bne.s   .cl_nobuf               ; not a runtime buffer: do not touch it
        subq.l  #4,a1
        move.l  (a1),d0
        jsr     LVO_FREEMEM(a6)
.cl_nobuf:
        lea     -4(a2),a1               ; free the FileHandle (getvec block)
        move.l  d5,d0
        jsr     LVO_FREEMEM(a6)
.cl_null:
        moveq   #-1,d0                  ; DOSTRUE
        movem.l (sp)+,d2-d7/a2-a6
        rts

; Seek(fh d1 [BPTR FileHandle], position d2, mode d3 [OFFSET_BEGINNING/-CURRENT/-END]) -> d0 = old position | -1.
; Sends ACTION_SEEK to the handler (ARG1=key, ARG2=position, ARG3=mode). The handler buffers the whole file -> the
; repositioning is a simple adjustment of HS_POS. a6 = DosBase on entry. From a PROCESS (like Read).
dos_fn_seek:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  d2,d5                   ; position
        move.l  d3,d6                   ; mode
        move.l  d1,d4
        lsl.l   #2,d4
        beq.s   .sk_err                 ; null fh
        move.l  d4,a2                   ; a2 = BADDR(fh)
        move.l  FH_TYPE(a2),a3          ; handler port
        move.l  a3,d0
        beq.s   .sk_err                 ; not routed
        bsr     dos_flushfh
        move.l  FH_ARG1(a2),d4          ; key of the file
        move.l  ($4).w,a6               ; SysBase
        lea     -SP_SIZEOF(sp),sp
        move.l  sp,a0
        move.l  a3,a1
        move.l  #ACTION_SEEK,d0
        move.l  d4,d1                   ; ARG1 = key
        move.l  d5,d2                   ; ARG2 = position
        move.l  d6,d3                   ; ARG3 = mode
        jsr     dos_sendpkt             ; d0 = dp_Res1 (old pos | -1); pr_Result2 set by dos_sendpkt
        lea     SP_SIZEOF(sp),sp
        bra.s   .sk_ret
.sk_err:
        moveq   #-1,d0
.sk_ret:
        movem.l (sp)+,d2-d7/a2-a6
        rts

; IoErr() -> d0 = pr_Result2 of ThisTask (error code of the last dos packet). a6 = DosBase (unused).
dos_fn_ioerr:
        move.l  ($4).w,a0              ; SysBase
        move.l  EB_THISTASK(a0),a0
        move.l  PR_RESULT2(a0),d0
        rts

; Write(fh d1 [BPTR FileHandle], buf d2, len d3) -> d0 = bytes written | -1. Sends ACTION_WRITE to the handler
; (ARG1=key, ARG2=buf, ARG3=len). To con_handler -> serial output; to the DF0: OFS (read-only) -> error.
; a6 = DosBase on entry. From a PROCESS (like Read). Mirror of dos_fn_read.
dos_fn_write:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  d2,d5                   ; buf
        move.l  d3,d6                   ; len
        move.l  d1,d4
        lsl.l   #2,d4
        beq.s   .wr_err                 ; null fh
        move.l  d4,a2                   ; a2 = BADDR(fh)
        move.l  FH_TYPE(a2),a3          ; handler port
        move.l  a3,d0
        beq.s   .wr_nil                 ; fh_Type = 0 (NIL:): everything is "written"
                ifne    DOS_NO_WRITE
        moveq   #0,d0                   ; RED DOS_NO_WRITE: does not send -> nothing emitted
        bra.s   .wr_ret
                endc
        bsr     dos_flushfh             ; deferred bytes of the BCPL runtime first (order of writes)
        bsr     dos_rawwrite
        bra.s   .wr_ret
.wr_err:
        moveq   #-1,d0
        bra.s   .wr_ret
.wr_nil:
        move.l  d6,d0
.wr_ret:
        movem.l (sp)+,d2-d7/a2-a6
        rts

; dos_rawwrite(a2 = routed FileHandle, d5 = buffer, d6 = length) -> d0 = bytes written | -1: ACTION_WRITE to the
; handler. Preserves d1-d7/a2-a6.
dos_rawwrite:
        movem.l d1-d3/a0-a1/a6,-(sp)
.rw_send:
        move.l  ($4).w,a6
        lea     -SP_SIZEOF(sp),sp
        move.l  sp,a0
        move.l  FH_TYPE(a2),a1
        move.l  #ACTION_WRITE,d0
        move.l  FH_ARG1(a2),d1          ; ARG1 = key
        move.l  d5,d2                   ; ARG2 = buffer
        move.l  d6,d3                   ; ARG3 = length
        jsr     dos_sendpkt             ; d0 = bytes written; pr_Result2 set by dos_sendpkt
        lea     SP_SIZEOF(sp),sp
        cmp.l   #-1,d0                  ; volume full: "Volume <name> is full" requester (spec disk-full-write-v34),
        bne.s   .rw_ret                 ; Retry resends the write, Cancel returns the failure (IoErr 221)
        move.l  ($4).w,a0
        move.l  EB_THISTASK(a0),a0
        cmp.l   #ERROR_DISK_FULL,PR_RESULT2(a0)
        bne.s   .rw_ret
        bsr     dos_fullreq
        tst.l   d0
        bne.s   .rw_send
        moveq   #-1,d0
.rw_ret:
        movem.l (sp)+,d1-d3/a0-a1/a6
        rts

; dos_fullreq(a2 = FileHandle) -> d0 = true if Retry: "Volume / <volume name> / is full" requester. The volume is
; the DLT_VOLUME node served by the same handler as the FileHandle ("?" otherwise). Preserves d1-d7/a0-a6;
; Result2 intact.
dos_fullreq:
        movem.l d1-d7/a0-a6,-(sp)
        move.l  ($4).w,a0
        move.l  EB_THISTASK(a0),a0
        move.l  PR_RESULT2(a0),-(sp)
        lea     -32(sp),sp              ; volume name in C
        lea     vr_unknown(pc),a4
        moveq   #1,d3
        move.l  DOS_DOSBASE,a0
        move.l  DL_ROOT(a0),a0
        move.l  RN_INFO(a0),d0
        lsl.l   #2,d0
        move.l  d0,a0
        move.l  DI_DEVINFO(a0),d0
.fr_node:
        lsl.l   #2,d0
        beq.s   .fr_ask
        move.l  d0,a0
        cmp.l   #DLT_VOLUME,DN_TYPE(a0)
        bne.s   .fr_next
        move.l  DN_TASK(a0),d1
        cmp.l   FH_TYPE(a2),d1
        bne.s   .fr_next
        move.l  DN_NAME(a0),d0
        lsl.l   #2,d0
        beq.s   .fr_ask
        move.l  d0,a0
        moveq   #0,d3
        move.b  (a0)+,d3
        cmp.w   #30,d3
        bls.s   .fr_len
        moveq   #30,d3
.fr_len:
        move.l  sp,a4
        move.l  sp,a1
        move.w  d3,d0
        bra.s   .fr_cpn
.fr_cp:
        move.b  (a0)+,(a1)+
.fr_cpn:
        dbra    d0,.fr_cp
        clr.b   (a1)
        bra.s   .fr_ask
.fr_next:
        move.l  DN_NEXT(a0),d0
        bra.s   .fr_node
.fr_ask:
        lea     vr_v1(pc),a0
        lea     vr_v3(pc),a1
        moveq   #0,d0                   ; no event counts as Retry
        bsr     vr_req
        lea     32(sp),sp
        move.l  ($4).w,a0
        move.l  EB_THISTASK(a0),a0
        move.l  (sp)+,PR_RESULT2(a0)
        movem.l (sp)+,d1-d7/a0-a6
        rts

; Deferred writing of the BCPL runtime: wrch & co write byte by byte; to a file (routed, non-interactive
; FileHandle) each byte would be a packet. They accumulate in a buffer (FH_WBUF, fill level FH_WCNT), flushed when
; it is full and before any Write / Read / Seek / Close of the same FileHandle. A console (interactive) is
; additionally flushed on every LF/CR/FF/NUL (V34 wrch rule), and the current output is flushed before rdch
; re-reads the input (prompt without newline). Only the FileHandles opened by this dos (getvec block of
; DOS_FH_ALLOC bytes) have these private fields.
DOS_WBUF        EQU 512
; dos_bufwrite(d1 = fh BPTR, d2 = buffer, d3 = length) -> d0 = length | -1. Preserves d1-d7/a0-a6.
dos_bufwrite:
        movem.l d1-d7/a0-a6,-(sp)
        move.l  d2,d5
        move.l  d3,d6
        move.l  d1,d4
        lsl.l   #2,d4
        beq     .bw_direct
        move.l  d4,a2
        tst.l   FH_TYPE(a2)
        beq     .bw_direct
        cmp.l   #DOS_FH_ALLOC+4,-4(a2)
        bne     .bw_direct              ; not a FileHandle of this dos
        cmp.l   #DOS_WBUF,d6
        bhs     .bw_direct
        tst.l   FH_WBUF(a2)
        bne.s   .bw_have
        move.l  ($4).w,a6
        move.l  #DOS_WBUF,d0
        moveq   #MEMF_PUBLIC,d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  d0,FH_WBUF(a2)
        beq     .bw_direct
        clr.l   FH_WCNT(a2)
.bw_have:
        move.l  FH_WCNT(a2),d0
        add.l   d6,d0
        cmp.l   #DOS_WBUF,d0
        bls.s   .bw_copy
        bsr.s   dos_flushfh
        beq.s   .bw_fail                ; full buffer not written (volume full...): the caller will find out
.bw_copy:
        move.l  FH_WBUF(a2),a1
        add.l   FH_WCNT(a2),a1
        move.l  d5,a0
        move.w  d6,d0
        bra.s   .bw_cnx
.bw_cpy:
        move.b  (a0)+,(a1)+
.bw_cnx:
        dbra    d0,.bw_cpy
        add.l   d6,FH_WCNT(a2)
        tst.l   FH_INTERACTIVE(a2)
        beq.s   .bw_done
        move.l  d5,a0                   ; console: flushed as soon as an LF, CR, FF or NUL is written
        move.w  d6,d0
        bra.s   .bw_scnx
.bw_scan:
        move.b  (a0)+,d1
        beq.s   .bw_flush
        cmp.b   #10,d1
        beq.s   .bw_flush
        cmp.b   #12,d1
        beq.s   .bw_flush
        cmp.b   #13,d1
        beq.s   .bw_flush
.bw_scnx:
        dbra    d0,.bw_scan
        bra.s   .bw_done
.bw_flush:
        bsr     dos_flushfh
        beq.s   .bw_fail
.bw_done:
        move.l  d6,d0
        bra.s   .bw_ret
.bw_fail:
        moveq   #-1,d0
        bra.s   .bw_ret
.bw_direct:
        movem.l (sp),d1-d3
        move.l  DOS_DOSBASE,a6
        jsr     DOS_LVO_WRITE(a6)
.bw_ret:
        movem.l (sp)+,d1-d7/a0-a6
        rts

; dos_flushout(d1 = fh BPTR | 0): flushes the deferred bytes of this FileHandle. Preserves everything.
dos_flushout:
        movem.l d1/a2,-(sp)
        lsl.l   #2,d1
        beq.s   .fo_ret
        move.l  d1,a2
        bsr.s   dos_flushfh
.fo_ret:
        movem.l (sp)+,d1/a2
        rts

; dos_flushfh(a2 = FileHandle) -> Z = 1 if writing the deferred bytes failed (Result2 set, bytes lost),
; Z = 0 otherwise (or nothing to write). Preserves everything else.
dos_flushfh:
        cmp.l   #DOS_FH_ALLOC+4,-4(a2)
        bne.s   .fl_ok
        tst.l   FH_WCNT(a2)
        beq.s   .fl_ok
        movem.l d0/d5-d6,-(sp)
        move.l  FH_WBUF(a2),d5
        move.l  FH_WCNT(a2),d6
        clr.l   FH_WCNT(a2)
        bsr     dos_rawwrite
        cmp.l   #-1,d0
        movem.l (sp)+,d0/d5-d6       ; (movem does not touch the CCR)
        rts
.fl_ok:
        andi.b  #$FB,ccr             ; Z = 0
        rts

; Input() -> d0 = BPTR pr_CIS of ThisTask (standard input FileHandle). a6 = DosBase (unused).
dos_fn_input:
        move.l  ($4).w,a0
        move.l  EB_THISTASK(a0),a0
        move.l  PR_CIS(a0),d0
        rts

; Output() -> d0 = BPTR pr_COS of ThisTask (standard output FileHandle). a6 = DosBase (unused).
dos_fn_output:
        move.l  ($4).w,a0
        move.l  EB_THISTASK(a0),a0
        move.l  PR_COS(a0),d0
        rts

; CurrentDir(lock d1 [BPTR]) -> d0 = OLD pr_CurrentDir. Sets the new lock of the current directory. a6 = DosBase.
dos_fn_currentdir:
        move.l  ($4).w,a0
        move.l  EB_THISTASK(a0),a0
        move.l  PR_CURRENTDIR(a0),d0    ; old (return value)
        move.l  d1,PR_CURRENTDIR(a0)    ; new
        rts

; --- LoadSeg / UnLoadSeg (LVO vectors -150 / -156): loading of a hunk executable VIA THE REAL Open/Read ---
; Called from a PROCESS (like Open/Read: dos_sendpkt uses ThisTask->pr_MsgPort as the reply port).

; LoadSeg(name d1 [C string]) -> d0 = BPTR seglist | 0. Opens the file via dos Open (-30, MODE_OLDFILE) and
; loads it as it is read (ls_load_stream: buffer of LS_BUFSZ bytes refilled by Read, large hunks read
; directly into place; CODE/DATA/BSS hunks + RELOC32 relocations -> BPTR seglist), then closes it (-36). Failure:
; IoErr = 103 (memory) or 121 (not an executable). No buffer for the whole file: a large packed executable
; (Caesar, 126 KB for 657 KB of hunks) fits in 1 MB.
dos_fn_loadseg:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  a6,a4                  ; a4 = DosBase (survives all calls)
        move.l  #MODE_OLDFILE,d2       ; Open(name d1 [already set], mode d2 = ACTION_FINDINPUT)
        bsr     dos_fn_open            ; d0 = BPTR fh | 0; a6 restored = DosBase
        move.l  d0,d7                  ; d7 = BPTR fh
        beq.s   .ls_fail0
        move.l  ($4).w,a6
        move.l  #LS_BUFSZ,d0
        move.l  #MEMF_PUBLIC,d1
        jsr     LVO_ALLOCMEM(a6)
        moveq   #ERROR_NO_FREE_STORE,d6
        moveq   #0,d5                  ; d5 = seglist
        move.l  d0,a2                  ; a2 = read buffer
        tst.l   d0
        beq.s   .ls_close
        lea     -LR_SIZE(sp),sp        ; reader: the file is read as a stream
        move.l  a2,LR_BUF(sp)
        clr.l   LR_POS(sp)
        clr.l   LR_LEN(sp)
        move.l  d7,LR_FH(sp)
        move.l  a4,LR_DOS(sp)
        move.l  #LS_BUFSZ,LR_CAP(sp)
        move.l  sp,a0
        jsr     ls_load_stream         ; d0 = seglist | 0, d1 = error code (loadseg.o far away -> jsr)
        lea     LR_SIZE(sp),sp
        move.l  d0,d5
        move.l  d1,d6
        move.l  a2,a1
        move.l  #LS_BUFSZ,d0
        jsr     LVO_FREEMEM(a6)
.ls_close:
        move.l  a4,a6
        move.l  d7,d1
        bsr     dos_fn_close
        move.l  d5,d0
        bne.s   .ls_ret
        move.l  ($4).w,a0              ; IoErr set AFTER the Close (whose reply resets pr_Result2 to 0)
        move.l  EB_THISTASK(a0),a0
        move.l  d6,PR_RESULT2(a0)
.ls_fail0:
        moveq   #0,d0
.ls_ret:
        movem.l (sp)+,d2-d7/a2-a6
        rts

; UnLoadSeg(seglist d1 [BPTR]) -> d0 = 0. Frees the segment chain (dos_unloadseg: d0 = BPTR, a6 = SysBase).
dos_fn_unloadseg:
        move.l  a6,-(sp)
        move.l  d1,d0                  ; d0 = BPTR seglist
        move.l  ($4).w,a6             ; SysBase (FreeMem)
        jsr     dos_unloadseg          ; (loadseg.o far away -> jsr); d0=0 -> no-op
        moveq   #0,d0
        move.l  (sp)+,a6
        rts

; --- Lock / UnLock / Examine / ExNext (LVO vectors -84 / -90 / -102 / -108): locks + OFS directory reading ---
; Called from a PROCESS (dos_sendpkt = reply port = ThisTask->pr_MsgPort). The DF0: handler (handler.s) allocates
; the FileLock, fills the FileInfoBlock and enumerates via the OFS machinery
; (ofs_name_to_block/ofs_fill_fib/ofs_dir_next).

; Lock(name d1 [C string], mode d2 [SHARED_LOCK/EXCLUSIVE_LOCK]) -> d0 = BPTR FileLock | 0. dos_resolve gives the
; handler port and the parent lock, the name is converted into a LONG-ALIGNED BSTR (a BPTR requires alignment), then
; ACTION_LOCATE_OBJECT (ARG1 = parent lock, ARG2 = name, ARG3 = mode). a6 = DosBase.
dos_fn_lock:
        move.l  #ACTION_LOCATE_OBJECT,d0 ; ARG3 = mode (d2)
        bra.s   dos_namepkt

; CreateDir(name d1) -> BPTR lock of the created directory | 0 (ACTION_CREATE_DIR). DeleteFile(name d1) ->
; DOSTRUE/DOSFALSE (ACTION_DELETE_OBJECT). a6 = DosBase.
dos_fn_createdir:
        move.l  #ACTION_CREATE_DIR,d0
        bra.s   dos_namepkt
dos_fn_deletefile:
        move.l  #ACTION_DELETE_OBJECT,d0

; dos_namepkt(d0 = action, d1 = C name, d2 = ARG3, a6 = DosBase) -> d0 = dp_Res1 (0 if the name does not resolve; IoErr
; set). Resolves the name (dos_resolve: starts the handler if needed), then sends ARG1 = starting lock, ARG2 =
; BPTR of the remaining name as a BSTR, ARG3 to the handler. Modifies no caller register except d0/d1/a0/a1 (LVO
; convention: d2-d7/a2-a6 preserved).
dos_namepkt:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  d0,d5                   ; d5 = action
        move.l  d1,a4                   ; a4 = name (C string)
        move.l  d2,d7                   ; d7 = ARG3
        bsr     dos_resolve             ; a3 = handler port, d6 = parent lock, a4 = name to pass on
        move.l  a3,d0
        beq     .np_fail                ; unknown device / handler cannot be started
        move.l  ($4).w,a6               ; SysBase
        lea     -(DOS_NAMEMAX+5)(sp),sp ; BSTR area on the stack (even size: SP stays even)
        move.l  sp,d0
        addq.l  #3,d0
        and.l   #-4,d0                  ; rounded up to the next long -> long-aligned BSTR (reversible BPTR)
        move.l  d0,a5                   ; a5 = BSTR
        lea     1(a5),a1               ; a1 -> characters
        moveq   #0,d3                   ; d3 = length
.np_ncpy:
        move.b  (a4)+,d0
        beq.s   .np_ndone
        move.b  d0,(a1)+
        addq.l  #1,d3
        cmp.l   #DOS_NAMEMAX,d3         ; bound of the buffer (BSTR)
        bcs.s   .np_ncpy
.np_ndone:
        move.b  d3,(a5)                 ; BCPL length byte
        lea     -SP_SIZEOF(sp),sp       ; StandardPacket
        move.l  sp,a0
        move.l  a3,a1                   ; handler port
        move.l  d5,d0
        move.l  d6,d1                   ; ARG1 = parent lock
        move.l  a5,d2
        lsr.l   #2,d2                   ; ARG2 = BPTR(BSTR name)
        move.l  d7,d3                   ; ARG3
        jsr     dos_sendpkt             ; d0 = dp_Res1
        lea     SP_SIZEOF(sp),sp
        lea     DOS_NAMEMAX+5(sp),sp    ; free the BSTR area
        bra.s   .np_ret
.np_fail:
        moveq   #0,d0
.np_ret:
        movem.l (sp)+,d2-d7/a2-a6
        rts

; Rename(old d1, new d2) -> DOSTRUE/DOSFALSE: ACTION_RENAME_OBJECT (ARG1 lock, ARG2 BSTR old name, ARG3
; lock, ARG4 BSTR new name) to the common handler; different handlers -> IoErr = ERROR_RENAME_ACROSS_DEVICES.
DOS_RNFRAME     EQU 2*(DOS_NAMEMAX+1)+4    ; two 256-byte BSTRs + alignment margin
dos_fn_rename:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  d2,d7                   ; d7 = new name
        move.l  d1,a4
        bsr     dos_resolve
        move.l  a3,d0
        beq     .rn_fail
        move.l  a3,a5                   ; a5 = port, d5 = lock, a2 = name (old)
        move.l  d6,d5
        move.l  a4,a2
        move.l  d7,a4
        bsr     dos_resolve
        move.l  a3,d0
        beq     .rn_fail
        cmp.l   a3,a5
        beq.s   .rn_same
        move.l  ($4).w,a0
        move.l  EB_THISTASK(a0),a0
        move.l  #ERROR_RENAME_ACROSS_DEVICES,PR_RESULT2(a0)
        bra     .rn_fail
.rn_same:
        lea     -DOS_RNFRAME(sp),sp
        move.l  sp,d0
        addq.l  #3,d0
        and.l   #-4,d0
        move.l  d0,a0                   ; BSTR old name (long-aligned)
        move.l  a2,a1
        bsr     dos_c2bstr
        move.l  a0,d2
        lsr.l   #2,d2                   ; ARG2
        lea     DOS_NAMEMAX+1(a0),a0    ; BSTR new name (+256: stays long-aligned)
        move.l  a4,a1
        bsr     dos_c2bstr
        move.l  a0,d4
        lsr.l   #2,d4                   ; ARG4
        move.l  d5,d1                   ; ARG1
        move.l  d6,d3                   ; ARG3
        move.l  ($4).w,a6
        lea     -SP_SIZEOF(sp),sp
        move.l  sp,a0
        move.l  a5,a1
        move.l  #ACTION_RENAME_OBJECT,d0
        jsr     dos_sendpkt
        lea     SP_SIZEOF+DOS_RNFRAME(sp),sp
        bra.s   .rn_ret
.rn_fail:
        moveq   #0,d0
.rn_ret:
        movem.l (sp)+,d2-d7/a2-a6
        rts

; dos_c2bstr(a0 = long-aligned destination, a1 = C string): BSTR (DOS_NAMEMAX characters max). Preserves a0; a1
; advanced.
dos_c2bstr:
        movem.l d0-d1/a2,-(sp)
        lea     1(a0),a2
        moveq   #0,d1
.cb_lp:
        move.b  (a1)+,d0
        beq.s   .cb_end
        move.b  d0,(a2)+
        addq.l  #1,d1
        cmp.l   #DOS_NAMEMAX,d1
        bcs.s   .cb_lp
.cb_end:
        move.b  d1,(a0)
        movem.l (sp)+,d0-d1/a2
        rts

; UnLock(lock d1 [BPTR]) -> d0 = 0. Gets the handler port via the lock's fl_Task, sends ACTION_FREE_LOCK.
dos_fn_unlock:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  d1,d4                   ; BPTR lock
        move.l  d4,d0
        lsl.l   #2,d0
        beq.s   .ul_ret                 ; lock 0 -> no-op
        move.l  d0,a2                   ; BADDR(lock)
        move.l  FL_TASK(a2),a3          ; handler port
        move.l  a3,d0
        beq.s   .ul_ret
        move.l  ($4).w,a6               ; SysBase
        lea     -SP_SIZEOF(sp),sp
        move.l  sp,a0
        move.l  a3,a1
        move.l  #ACTION_FREE_LOCK,d0
        move.l  d4,d1                   ; ARG1 = BPTR lock
        moveq   #0,d2
        moveq   #0,d3
        jsr     dos_sendpkt
        lea     SP_SIZEOF(sp),sp
.ul_ret:
        moveq   #0,d0
        movem.l (sp)+,d2-d7/a2-a6
        rts

; Examine(lock d1 [BPTR], fib d2 [long-aligned APTR]) -> d0 = DOSTRUE/DOSFALSE. ExNext same signature (next entry).
; Port via the lock's fl_Task. ARG2 = BPTR(fib) (the FIB must be long-aligned -> AllocMem by the caller). a6 = DosBase.
dos_fn_examine:
        move.l  #ACTION_EXAMINE_OBJECT,d0
        bra.s   dos_examine_pkt
dos_fn_exnext:
        move.l  #ACTION_EXAMINE_NEXT,d0
dos_examine_pkt:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  d0,d6                   ; d6 = action code
        move.l  d1,d4                   ; BPTR lock
        move.l  d2,d5                   ; APTR fib
        move.l  d4,d0
        lsl.l   #2,d0
        beq.s   .exc_fail
        move.l  d0,a2                   ; BADDR(lock)
        move.l  FL_TASK(a2),a3          ; handler port
        move.l  a3,d0
        beq.s   .exc_fail
        move.l  ($4).w,a6               ; SysBase
        lea     -SP_SIZEOF(sp),sp
        move.l  sp,a0
        move.l  a3,a1
        move.l  d6,d0                   ; action (EXAMINE_OBJECT / EXAMINE_NEXT)
        move.l  d4,d1                   ; ARG1 = BPTR lock
        move.l  d5,d2
        lsr.l   #2,d2                   ; ARG2 = BPTR(fib)
        moveq   #0,d3
        jsr     dos_sendpkt             ; d0 = dp_Res1 (DOSTRUE/DOSFALSE)
        lea     SP_SIZEOF(sp),sp
        tst.l   d0
        beq.s   .exc_ret
        move.l  d5,a0                   ; the handler returns BSTRs: the C API wants NUL-terminated strings
        lea     FIB_FILENAME(a0),a0
        bsr.s   dos_bstr2c
        move.l  d5,a0
        lea     FIB_COMMENT(a0),a0
        bsr.s   dos_bstr2c
        bra.s   .exc_ret
.exc_fail:
        moveq   #0,d0                   ; DOSFALSE
.exc_ret:
        movem.l (sp)+,d2-d7/a2-a6
        rts

; dos_bstr2c(a0 = BSTR): converts in place into a C string (shifts the characters by one byte, final NUL).
; Preserves d0. Clobbers d1/a0/a1.
dos_bstr2c:
        moveq   #0,d1
        move.b  (a0),d1
        lea     1(a0),a1
        bra.s   .b2c_next
.b2c_cpy:
        move.b  (a1)+,(a0)+
.b2c_next:
        dbra    d1,.b2c_cpy
        clr.b   (a0)
        rts

; --- LVO -198..-222: the table used to stop at DateStamp; a call beyond it (SetClock: Delay, Execute) landed in the
; memory below the jump table. ---

; Delay(ticks d1): waits d1 fiftieths of a second by BLOCKING the task on a timer.device request (unit
; VBLANK, port and request on the stack): a busy wait would starve processes of the same priority (Wait of the
; startup-sequence while Run's background CLI executes StartupII). Falls back to a busy wait only if
; no signal is free or if timer.device is absent. a6 = DosBase.
DL_MAXTICKS     EQU 65535*50         ; TV_SECS is converted by mulu (16 bits)
DL_FRAME        EQU MP_SIZE+TR_SIZE
dos_fn_delay:
        movem.l d2-d3/a2-a4/a6,-(sp)
        move.l  d1,d2
        ble     .dl_done
        cmp.l   #DL_MAXTICKS,d2
        bls.s   .dl_ticks
        move.l  #DL_MAXTICKS,d2
.dl_ticks:
        move.l  ($4).w,a6
        lea     EB_DEVICELIST(a6),a0
        lea     dl_timername(pc),a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        beq     .dl_busy
        move.l  d0,a4                ; a4 = timer.device
        moveq   #-1,d0
        jsr     LVO_ALLOCSIGNAL(a6)
        move.l  d0,d3
        bmi     .dl_busy
        lea     -DL_FRAME(sp),sp
        move.l  sp,a0
        moveq   #DL_FRAME/2-1,d0
.dl_clr:
        clr.w   (a0)+
        dbra    d0,.dl_clr
        move.l  sp,a3                ; a3 = reply port
        lea     MP_SIZE(sp),a2       ; a2 = timerequest
        move.b  #NT_MSGPORT,LN_TYPE(a3)
        move.b  #PA_SIGNAL,MP_FLAGS(a3)
        move.b  d3,MP_SIGBIT(a3)
        move.l  EB_THISTASK(a6),MP_SIGTASK(a3)
        lea     MP_MSGLIST(a3),a1
        jsr     newlist
        move.l  a3,MN_REPLYPORT(a2)
        move.l  a4,IO_DEVICE(a2)
        move.l  #UNIT_VBLANK,IO_UNIT(a2)
        move.w  #TR_ADDREQUEST,IO_COMMAND(a2)
        divu    #50,d2
        moveq   #0,d0
        move.w  d2,d0
        move.l  d0,TV_SECS(a2)
        swap    d2
        mulu    #20000,d2
        move.l  d2,TV_MICRO(a2)
        move.l  a6,-(sp)
        move.l  a4,a6
        move.l  a2,a1
        jsr     TD_BEGINIO(a6)
        move.l  (sp)+,a6
.dl_wait:
        moveq   #0,d0
        bset    d3,d0
        jsr     LVO_WAIT(a6)
        move.l  a3,a0
        jsr     LVO_GETMSG(a6)
        cmp.l   a2,d0
        bne.s   .dl_wait
        lea     DL_FRAME(sp),sp
        move.l  d3,d0
        jsr     LVO_FREESIGNAL(a6)
        bra.s   .dl_done
.dl_busy:
        move.l  VBL_COUNT,d0
        add.l   d2,d0
.dl_spin:
        cmp.l   VBL_COUNT,d0
        bgt.s   .dl_spin
.dl_done:
        moveq   #0,d0
        movem.l (sp)+,d2-d3/a2-a4/a6
        rts
dl_timername:
        dc.b    "timer.device",0
        even

; CreateProc(name d1 [C], pri d2, seglist d3 [BPTR], stack d4 [bytes]) -> d0 = MsgPort of the process | 0 (dos AutoDoc).
; The process starts directly on the code of the first segment; name copied (the caller may free its own),
; segarray [3, creator's V!1, V!2, seglist] (BCPL spec §8.3, global -18), ConsoleTask/FileSystemTask/WindowPtr
; and GV inherited from the creator, null current directory. When the code returns (rts), cpr_exit ends the process.
; Fields set under Forbid before the process first runs.
CP_NAMEMAX      EQU 32
dos_fn_createproc:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  d1,a2                   ; a2 = name
        move.l  d2,d5                   ; d5 = pri
        move.l  d3,d6                   ; d6 = seglist
        move.l  d4,d7                   ; d7 = stack
        move.l  ($4).w,a6
        moveq   #CP_NAMEMAX+20,d0       ; name (32) + segarray with getvec header (5 longs)
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .cpr_fail
        move.l  d0,a3                   ; a3 = copied name
        move.l  a3,a0
        moveq   #CP_NAMEMAX-2,d1
.cpr_ncpy:
        move.b  (a2)+,(a0)+
        dbeq    d1,.cpr_ncpy
        lea     CP_NAMEMAX(a3),a4       ; a4 = getvec header of the segarray
        move.l  #20,(a4)                ; size (for a possible freevec)
        move.l  #3,4(a4)
        move.l  d6,16(a4)
        move.l  EB_THISTASK(a6),a0
        cmp.b   #NT_PROCESS,LN_TYPE(a0)
        bne.s   .cpr_noparent
        move.l  PR_SEGLIST(a0),d0
        lsl.l   #2,d0
        beq.s   .cpr_noparent
        move.l  d0,a1
        cmp.l   #2,(a1)
        blt.s   .cpr_noparent
        move.l  4(a1),8(a4)             ; creator's V!1, V!2
        move.l  8(a1),12(a4)
.cpr_noparent:
        jsr     LVO_FORBID(a6)
        move.l  a3,a0
        move.l  d6,d0
        lsl.l   #2,d0
        move.l  d0,a1
        addq.l  #4,a1                   ; entry = first segment
        move.l  d5,d0
        move.l  d7,d1
        jsr     proc_create             ; d0 = &pr_MsgPort | 0
        move.l  d0,d4
        beq.s   .cpr_failp
        move.l  d0,a0
        lea     -PR_MSGPORT(a0),a0      ; a0 = new process
        lea     4(a4),a1
        move.l  a1,d0
        lsr.l   #2,d0
        move.l  d0,PR_SEGLIST(a0)
        move.l  EB_THISTASK(a6),a1
        cmp.b   #NT_PROCESS,LN_TYPE(a1)
        bne.s   .cpr_started
        move.l  PR_CONSOLETASK(a1),PR_CONSOLETASK(a0)
        move.l  PR_FILESYSTEMTASK(a1),PR_FILESYSTEMTASK(a0)
        move.l  PR_WINDOWPTR(a1),PR_WINDOWPTR(a0)
        move.l  PR_GLOBVEC(a1),PR_GLOBVEC(a0)   ; creator's GV (createproc, spec §8.3): Execute needs it
.cpr_started:
        move.l  TC_SPUPPER(a0),a1               ; return address of the code (set by AddTask below the size)
        move.l  #cpr_exit,-4(a1)
        jsr     LVO_PERMIT(a6)
        move.l  d4,d0
        bra.s   .cpr_ret
.cpr_failp:
        jsr     LVO_PERMIT(a6)
        move.l  a3,a1
        moveq   #CP_NAMEMAX+20,d0
        jsr     LVO_FREEMEM(a6)
.cpr_fail:
        moveq   #0,d0
.cpr_ret:
        movem.l (sp)+,d2-d7/a2-a6
        rts

; cpr_exit: a process launched by CreateProc whose code returns (rts): name + segarray block freed, then RemTask
; (does not return). Under Forbid: the freed name is no longer visible before the process ends.
cpr_exit:
        move.l  ($4).w,a6
        jsr     LVO_FORBID(a6)
        move.l  EB_THISTASK(a6),a0
        move.l  LN_NAME(a0),a1
        moveq   #CP_NAMEMAX+20,d0
        jsr     LVO_FREEMEM(a6)
        sub.l   a1,a1
        jsr     LVO_REMTASK(a6)
.ce_hang:
        bra.s   .ce_hang

; WaitForChar(fh d1, us d2) -> DOSFALSE: no character available (the console does not handle this packet yet).
dos_fn_waitforchar:
        moveq   #0,d0
        rts

; ParentDir(lock d1) -> lock of the parent | 0 (root): ACTION_PARENT to the lock's handler. a6 = DosBase.
dos_fn_parentdir:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  d1,d0
        lsl.l   #2,d0
        beq.s   .pd_zero
        move.l  d0,a0
        move.l  FL_TASK(a0),a1
        move.l  ($4).w,a6
        lea     -SP_SIZEOF(sp),sp
        move.l  sp,a0
        moveq   #ACTION_PARENT,d0
        moveq   #0,d2
        moveq   #0,d3
        jsr     dos_sendpkt
        lea     SP_SIZEOF(sp),sp
        bra.s   .pd_ret
.pd_zero:
        moveq   #0,d0
.pd_ret:
        movem.l (sp)+,d2-d7/a2-a6
        rts

; DeviceProc(name d1) -> port of the handler process of the designated device, volume or assign | 0; IoErr = lock of
; an assign's directory, 0 otherwise (AutoDoc). Unknown name: 0, IoErr set by dos_resolve. a6 = DosBase.
dos_fn_deviceproc:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  d1,a4
        bsr     dos_resolve             ; a3 = port | 0, d6 = starting lock
        move.l  a3,d0
        beq.s   .dv_ret
        move.l  ($4).w,a0
        move.l  EB_THISTASK(a0),a0
        move.l  d6,PR_RESULT2(a0)
.dv_ret:
        movem.l (sp)+,d2-d7/a2-a6
        rts

; DupLock(lock d1) -> new shared lock on the same object | 0 (lock 0 -> 0): ACTION_COPY_DIR. Info(lock d1,
; infodata d2 [long-aligned]) -> DOSTRUE/DOSFALSE: ACTION_INFO (ARG1 lock, ARG2 BPTR InfoData), lock 0 -> DF0:.
dos_fn_duplock:
        tst.l   d1
        beq.s   .dl_zero
        moveq   #ACTION_COPY_DIR,d0
        bra.s   dos_lockpkt
.dl_zero:
        moveq   #0,d0
        rts
dos_fn_info:
        lsr.l   #2,d2
        moveq   #ACTION_INFO,d0
; dos_lockpkt(d0 = action, d1 = lock (ARG1), d2 = ARG2) -> d0 = dp_Res1: packet to the lock's handler.
dos_lockpkt:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  DOS_FSPORT,a1
        move.l  d1,d3
        lsl.l   #2,d3
        beq.s   .lp_port
        move.l  d3,a0
        move.l  FL_TASK(a0),a1
.lp_port:
        move.l  ($4).w,a6
        lea     -SP_SIZEOF(sp),sp
        move.l  sp,a0
        moveq   #0,d3
        jsr     dos_sendpkt
        lea     SP_SIZEOF(sp),sp
        movem.l (sp)+,d2-d7/a2-a6
        rts

; SetComment(name d1, comment d2 [C string]) / SetProtection(name d1, mask d2) -> DOSTRUE/DOSFALSE:
; ACTION_SET_COMMENT / ACTION_SET_PROTECT (ARG2 lock, ARG3 BSTR name, ARG4 BSTR comment | mask). a6 = DosBase.
dos_fn_setcomment:
        moveq   #ACTION_SET_COMMENT,d0
        bra.s   dos_setpkt
dos_fn_setprotection:
        moveq   #ACTION_SET_PROTECT,d0
dos_setpkt:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  d0,d5
        move.l  d2,d7
        move.l  d1,a4
        bsr     dos_resolve             ; a3 = port, d6 = lock, a4 = name to pass on
        move.l  a3,d0
        beq.s   .sp_fail
        lea     -DOS_RNFRAME(sp),sp
        move.l  sp,d0
        addq.l  #3,d0
        and.l   #-4,d0
        move.l  d0,a0
        move.l  a4,a1
        bsr     dos_c2bstr
        move.l  a0,d3
        lsr.l   #2,d3                   ; ARG3 = name
        move.l  d7,d4                   ; ARG4 = mask
        cmp.l   #ACTION_SET_COMMENT,d5
        bne.s   .sp_send
        lea     DOS_NAMEMAX+1(a0),a0
        move.l  d7,a1
        bsr     dos_c2bstr
        move.l  a0,d4
        lsr.l   #2,d4                   ; ARG4 = comment
.sp_send:
        moveq   #0,d1
        move.l  d6,d2                   ; ARG2 = lock
        move.l  ($4).w,a6
        lea     -SP_SIZEOF(sp),sp
        move.l  sp,a0
        move.l  a3,a1
        move.l  d5,d0
        jsr     dos_sendpkt
        lea     SP_SIZEOF+DOS_RNFRAME(sp),sp
        bra.s   .sp_ret
.sp_fail:
        moveq   #0,d0
.sp_ret:
        movem.l (sp)+,d2-d7/a2-a6
        rts

; IsInteractive(fh d1) -> fh_Interactive (raw, as in V34: not normalised to -1).
dos_fn_isinteractive:
        move.l  d1,d0
        lsl.l   #2,d0
        beq.s   .ii_ret
        move.l  d0,a0
        move.l  FH_INTERACTIVE(a0),d0
.ii_ret:
        rts

; dos_resolve(a4 = C string name, a6 = DosBase) -> a3 = handler port | 0, d6 = BPTR starting lock, a4 = name to
; pass on to the handler. AmigaDOS semantics: "xxx:rest" -> DosList node "xxx" (case-insensitive):
; assign (DLT_DIRECTORY) -> its lock + its handler, "rest" is passed on; device/volume -> its handler, lock 0, full
; name (the handler ignores the prefix and starts from the root). ":rest" -> volume of the current directory, root.
; Without ':' -> relative to pr_CurrentDir (lock 0 = root of the default handler pr_FileSystemTask, otherwise DF0:).
; Unknown prefix -> a3 = 0 and IoErr = ERROR_DEVICE_NOT_MOUNTED. Clobbers d0-d2/a0-a1.
dos_resolve:
        movem.l d3-d4/a2,-(sp)
.rs_top:
        move.l  a4,a0
.rs_scan:
        move.b  (a0)+,d0
        beq     .rs_rel                 ; no ':' -> relative to the current directory
        cmp.b   #':',d0
        bne.s   .rs_scan
        move.l  a0,d3
        sub.l   a4,d3
        subq.l  #1,d3                   ; d3 = length of the prefix
        beq     .rs_volroot             ; ":rest"
        move.l  DL_ROOT(a6),a2
        move.l  RN_INFO(a2),d0
        lsl.l   #2,d0
        move.l  d0,a2
        move.l  DI_DEVINFO(a2),d0
.rs_node:
        lsl.l   #2,d0
        beq     .rs_unknown
        move.l  d0,a2                   ; a2 = current node
        move.l  DN_NAME(a2),d0
        lsl.l   #2,d0
        beq     .rs_next
        move.l  d0,a0
        moveq   #0,d4
        move.b  (a0)+,d4                ; length of the node's name
        cmp.l   d3,d4
        bne.s   .rs_next
        move.l  a4,a1
.rs_cmp:
        move.b  (a0)+,d0
        bsr     dos_upper
        move.b  d0,d1
        move.b  (a1)+,d0
        bsr     dos_upper
        cmp.b   d0,d1
        bne.s   .rs_next
        subq.l  #1,d4
        bne.s   .rs_cmp
        cmp.l   #DLT_DIRECTORY,DN_TYPE(a2)
        bne.s   .rs_devvol
        move.l  DN_LOCK(a2),d6          ; assign: lock of the assigned directory
        move.l  d6,d0
        lsl.l   #2,d0
        beq.s   .rs_unknown
        move.l  d0,a0
        move.l  FL_TASK(a0),a3
        lea     1(a4,d3.l),a4           ; pass on what follows the ':'
        bra     .rs_ret
.rs_devvol:
        moveq   #0,d6
        move.l  DN_TASK(a2),a3
        move.l  a3,d0
        bne     .rs_ret
        tst.l   DN_TYPE(a2)             ; device without a task: start its handler (BCPL spec §13.3)
        bne.s   .rs_absent              ; volume known but not in a drive
        ; one startup at a time: the handler only sets dn_Task on receiving its startup packet, and
        ; loading its segment takes long; two processes opening the same device ("run copy x to pipe:a"
        ; then "type pipe:a") each launched an instance, and reader and writer could not see each other
        move.l  a6,-(sp)
        move.l  ($4).w,a6
        lea     DOS_HSEM,a0
        jsr     LVO_OBTAINSEMAPHORE(a6)
        move.l  DN_TASK(a2),a3          ; re-read: started in the meantime by another process?
        move.l  a3,d0
        bne.s   .rs_hrel
        move.l  a4,a0                   ; full name (the handler may read parameters from it: NEWCON:x/y/w/h/title)
        jsr     bcpl_starthandler       ; d0 = port | 0 (Result2 set)
        move.l  d0,a3
        move.l  DN_LOCK(a2),d6
.rs_hrel:
        lea     DOS_HSEM,a0
        jsr     LVO_RELEASESEMAPHORE(a6)
        move.l  (sp)+,a6
        bra.s   .rs_ret
.rs_next:
        move.l  DN_NEXT(a2),d0
        bra     .rs_node
.rs_unknown:
        tst.l   d3
        beq.s   .rs_fail                ; no prefix: no volume name to ask for
        cmp.l   #3,d3                   ; "NIL:": never a requester (deviceproc spec)
        bne.s   .rs_absent
        move.b  (a4),d0
        and.b   #$DF,d0
        cmp.b   #'N',d0
        bne.s   .rs_absent
        move.b  1(a4),d0
        and.b   #$DF,d0
        cmp.b   #'I',d0
        bne.s   .rs_absent
        move.b  2(a4),d0
        and.b   #$DF,d0
        cmp.b   #'L',d0
        beq.s   .rs_fail
.rs_absent:
        bsr     dos_volreq              ; "Please insert volume <prefix> in any drive"
        tst.l   d0
        bne     .rs_top                 ; Retry: resolve again
.rs_fail:
        move.l  ($4).w,a0
        move.l  EB_THISTASK(a0),a0
        move.l  #ERROR_DEVICE_NOT_MOUNTED,PR_RESULT2(a0)
        sub.l   a3,a3
        bra.s   .rs_ret
.rs_volroot:
        bsr     dos_cdport
        moveq   #0,d6                   ; the handler starts again from the root (it ignores the ':')
        bra.s   .rs_ret
.rs_rel:
        bsr     dos_cdport
.rs_ret:
        movem.l (sp)+,d3-d4/a2
        rts

; dos_volreq(a4 = name, d3 = length of the prefix before ':') -> d0 = true if the user chose Retry (or inserted a
; disk). Intuition requester "Please insert volume / <prefix> / in any drive" on the screen of pr_WindowPtr (or
; failing that the Workbench one); none for a plain task or if pr_WindowPtr = -1 (returns false). The preliminary
; FLUSH of 1.3 is not sent: our file-handler has no pending writes. Preserves d1-d7/a0-a6.
VR_ITEXT        EQU 12               ; struct IntuiText (intuition/intuition.h)
VR_NEXTTEXT     EQU 16
VR_ITSIZE       EQU 20
VR_NAME         EQU 0                ; frame: prefix (C string), 5 IntuiTexts
VR_IT           EQU 32
VR_SIZE         EQU VR_IT+5*VR_ITSIZE
LVO_AUTOREQ     EQU -348             ; intuition AutoRequest
VR_DISKINSERTED EQU $00008000        ; IDCMP class: an inserted disk counts as Retry
dos_volreq:
        movem.l a0-a1,-(sp)
        lea     vr_l1(pc),a0
        lea     vr_l3(pc),a1
        move.l  #VR_DISKINSERTED,d0
        bsr.s   vr_req
        movem.l (sp)+,a0-a1
        rts
; dos_pktretry(d0 = dp_Res1, d1 = dp_Res2 of a replied packet) -> d0 = true if it must be resent: 218 refusal from the
; DF0: handler for a lock or file of an ejected volume (HND_REFVOL) -> "Please replace volume / <name> /
; in any drive" requester (spec disk-change-v34 §2.4); Retry or the insertion of a disk (DISKINSERTED) retry. Preserves
; d1-d7/a0-a6.
dos_pktretry:
        tst.l   d0
        bne.s   .pr_no
        cmp.l   #ERROR_DEVICE_NOT_MOUNTED,d1
        bne.s   .pr_no
        move.l  HND_REFVOL,d0
        clr.l   HND_REFVOL
        lsl.l   #2,d0
        beq.s   .pr_ret
        movem.l d3/a0-a1/a4,-(sp)
        move.l  d0,a4
        moveq   #0,d0
        tst.l   DN_TASK(a4)          ; volume mounted again in the meantime: no requester
        bne.s   .pr_pop
        move.l  DN_NAME(a4),d0
        lsl.l   #2,d0
        move.l  d0,a4
        moveq   #0,d3
        move.b  (a4)+,d3             ; BSTR: length then characters
        lea     vr_r1(pc),a0
        lea     vr_l3(pc),a1
        move.l  #VR_DISKINSERTED,d0
        bsr.s   vr_req
.pr_pop:
        movem.l (sp)+,d3/a0-a1/a4
        rts
.pr_no:
        moveq   #0,d0
.pr_ret:
        rts
; vr_req(a4 = name, d3 = its length, a0 = 1st line, a1 = 3rd line, d0 = IDCMP classes counting as Retry) -> d0 = true if
; Retry: three-line system requester, Retry / Cancel. Preserves d1-d7/a0-a6.
vr_req:
        movem.l d1-d7/a0-a6,-(sp)
        move.l  a0,d4                ; d4/d5 = 1st / 3rd line, d2 = classes
        move.l  a1,d5
        move.l  d0,d2
        moveq   #0,d7                ; d7 = answer
        move.l  ($4).w,a6
        move.l  EB_THISTASK(a6),a5
        cmp.b   #NT_PROCESS,LN_TYPE(a5)
        bne     .vr_ret
        move.l  PR_WINDOWPTR(a5),d6  ; d6 = reference window | 0
        cmp.l   #-1,d6
        beq     .vr_ret
        lea     vr_intname(pc),a1
        moveq   #0,d0
        jsr     LVO_OPENLIBRARY(a6)
        tst.l   d0
        beq     .vr_ret
        move.l  d0,a3                ; a3 = IntuitionBase
        lea     -VR_SIZE(sp),sp
        move.l  sp,a0                ; all zero
        moveq   #VR_SIZE/2-1,d0
.vr_clr:
        clr.w   (a0)+
        dbra    d0,.vr_clr
        move.l  a4,a0                ; prefix, bounded to 30 characters
        lea     VR_NAME(sp),a1
        move.l  d3,d0
        cmp.l   #30,d0
        bls.s   .vr_ncp
        moveq   #30,d0
        bra.s   .vr_ncp
.vr_ncl:
        move.b  (a0)+,(a1)+
.vr_ncp:
        dbra    d0,.vr_ncl
        lea     VR_IT(sp),a0         ; body: three chained lines
        move.l  d4,a1
        moveq   #4,d1
        bsr     vr_itext
        lea     VR_NAME(sp),a1
        moveq   #14,d1
        bsr     vr_itext
        move.l  d5,a1
        moveq   #24,d1
        bsr     vr_itext
        clr.l   VR_NEXTTEXT-VR_ITSIZE(a0)
        lea     vr_retry(pc),a1
        moveq   #3,d1
        bsr     vr_itext
        clr.l   VR_NEXTTEXT-VR_ITSIZE(a0)
        lea     vr_cancel(pc),a1
        moveq   #3,d1
        bsr     vr_itext
        clr.l   VR_NEXTTEXT-VR_ITSIZE(a0)
        move.l  d6,a0                ; AutoRequest(window, body, Retry, Cancel, DISKINSERTED, 0, 320, 72)
        lea     VR_IT(sp),a1
        lea     VR_IT+3*VR_ITSIZE(sp),a2
        lea     VR_IT+4*VR_ITSIZE(sp),a4
        exg     a3,a4                ; a3 = Cancel, a4 = IntuitionBase
        move.l  d2,d0
        moveq   #0,d1
        move.l  #320,d2
        moveq   #72,d3
        move.l  a4,a6
        jsr     LVO_AUTOREQ(a6)
        move.l  d0,d7
        lea     VR_SIZE(sp),sp
        move.l  a6,a1
        move.l  ($4).w,a6
        jsr     LVO_CLOSELIBRARY(a6)
.vr_ret:
        move.l  d7,d0
        movem.l (sp)+,d1-d7/a0-a6
        rts
; vr_itext(a0 = IntuiText, a1 = text, d1.w = top) -> a0 = next IntuiText (chained): pen 2 on 1, JAM1.
vr_itext:
        move.b  #2,(a0)
        move.b  #1,1(a0)
        clr.b   2(a0)
        move.w  #6,4(a0)
        move.w  d1,6(a0)
        clr.l   8(a0)
        move.l  a1,VR_ITEXT(a0)
        lea     VR_ITSIZE(a0),a0
        move.l  a0,VR_NEXTTEXT-VR_ITSIZE(a0)
        rts
vr_intname:     dc.b    "intuition.library",0
vr_l1:          dc.b    "Please insert volume",0
vr_r1:          dc.b    "Please replace volume",0
vr_l3:          dc.b    "in any drive",0
vr_v1:          dc.b    "Volume",0
vr_v3:          dc.b    "is full",0
vr_unknown:     dc.b    "?",0
vr_retry:       dc.b    "Retry",0
vr_cancel:      dc.b    "Cancel",0
                even

; dos_cdport() -> d6 = pr_CurrentDir of ThisTask, a3 = port of the handler that owns this lock (lock 0 ->
; pr_FileSystemTask, or the DF0: file-handler if not set). Clobbers d0/a0.
dos_cdport:
        move.l  ($4).w,a0
        move.l  EB_THISTASK(a0),a0
        move.l  PR_CURRENTDIR(a0),d6
        move.l  d6,d0
        lsl.l   #2,d0
        beq.s   .cd_default
        move.l  d0,a0
        move.l  FL_TASK(a0),a3
        rts
.cd_default:
        move.l  PR_FILESYSTEMTASK(a0),a3
        move.l  a3,d0
        bne.s   .cd_ret
        move.l  DOS_FSPORT,a3
.cd_ret:
        rts

; dos_upper(d0.b) -> d0.b in upper case (ASCII a-z only).
dos_upper:
        cmp.b   #'a',d0
        blo.s   .up_ret
        cmp.b   #'z',d0
        bhi.s   .up_ret
        sub.b   #'a'-'A',d0
.up_ret:
        rts

; dos_boot_assigns(a6 = DosBase): called by the initial CLI (process) once the boot disk is mounted. Creates the
; VOLUME node (name read by Examine of the root), the SYS: assign (root) and the C: S: L: DEVS: LIBS: FONTS: assigns for
; each directory present on DF0:, then sets pr_CurrentDir = root. No readable disk -> nothing. Preserves everything.
BA_PATHMAX      EQU 48
dos_boot_assigns:
        movem.l d0-d7/a0-a6,-(sp)
        move.l  a6,a5                   ; a5 = DosBase
        lea     -BA_PATHMAX(sp),sp      ; (sp) = "<boot device>:", then the assign paths
        bsr     ba_ramnode
        bsr     ba_devnodes
        bsr     ba_bootname             ; d5 = length of "NAME:"
        move.l  sp,d1
        moveq   #SHARED_LOCK,d2
        bsr     dos_fn_lock
        move.l  d0,d7                   ; d7 = root lock (kept by SYS:)
        beq     .ba_ret
        lsl.l   #2,d0
        move.l  d0,a0
        move.l  FL_TASK(a0),a4          ; a4 = handler port of the boot device
        moveq   #DLT_DIRECTORY,d0
        move.l  d7,d1
        lea     ba_sysname(pc),a0
        move.l  a4,a1
        bsr     ba_addnode
        lea     ba_tab(pc),a2           ; pairs (assign name, disk directory) terminated by an empty name
.ba_loop:
        tst.b   (a2)
        beq.s   .ba_cd
        move.l  a2,a3                   ; a3 = assign name
.ba_skip1:
        tst.b   (a2)+
        bne.s   .ba_skip1               ; a2 = directory
        lea     0(sp,d5.l),a0           ; "NAME:directory"
.ba_cat:
        move.b  (a2)+,(a0)+
        bne.s   .ba_cat                 ; a2 = next pair
        move.l  a5,a6
        move.l  sp,d1
        moveq   #SHARED_LOCK,d2
        bsr     dos_fn_lock
        clr.b   0(sp,d5.l)              ; "NAME:" again
        tst.l   d0
        beq.s   .ba_loop                ; directory missing -> no assign
        move.l  d0,d1
        moveq   #DLT_DIRECTORY,d0
        move.l  a3,a0
        move.l  a4,a1
        bsr     ba_addnode
        bra.s   .ba_loop
.ba_cd:
        move.l  a5,a6                   ; initial current directory = root of the boot disk
        move.l  sp,d1
        moveq   #SHARED_LOCK,d2
        bsr     dos_fn_lock
        move.l  d0,d1
        beq.s   .ba_ret
        bsr     dos_fn_currentdir
.ba_ret:
        lea     BA_PATHMAX(sp),sp
        movem.l (sp)+,d0-d7/a0-a6
        rts

; ba_bootname(a5 = DosBase, 4(sp) = buffer of BA_PATHMAX bytes) -> d5 = length of "NAME:" written into the buffer
; (name of the boot DeviceNode DL_BOOTDEV, "DF0" by default), final NUL. Clobbers d0/a0/a1.
ba_bootname:
        lea     4(sp),a1
        lea     ba_df0(pc),a0
        move.l  DL_BOOTDEV(a5),d0
        beq.s   .bn_c
        move.l  d0,a0
        move.l  DN_NAME(a0),d0
        lsl.l   #2,d0
        beq.s   .bn_df0
        move.l  d0,a0
        moveq   #0,d5
        move.b  (a0)+,d5                ; BSTR
        cmp.w   #BA_PATHMAX-16,d5       ; room for ":directory"
        bhi.s   .bn_df0
        move.w  d5,d0
        bra.s   .bn_bnext
.bn_bcpy:
        move.b  (a0)+,(a1)+
.bn_bnext:
        dbra    d0,.bn_bcpy
        bra.s   .bn_colon
.bn_df0:
        lea     4(sp),a1
        lea     ba_df0(pc),a0
.bn_c:
        moveq   #0,d5
.bn_ccpy:
        move.b  (a0)+,d0
        beq.s   .bn_colon
        move.b  d0,(a1)+
        addq.l  #1,d5
        bra.s   .bn_ccpy
.bn_colon:
        move.b  #':',(a1)+
        clr.b   (a1)
        addq.l  #1,d5
        rts

; dos_df0bootnode(a6 = ExecBase): after a successful DF0: bootblock, priority 5 BootNode (ln_Type 0, ln_Name "DF0")
; enqueued into eb_MountList for the DF0: DeviceNode (spec uae-hd-boot-v34 §3 point 2): a board of priority >= 5,
; enqueued earlier, stays at the head and becomes the boot device. Preserves everything.
dos_df0bootnode:
        movem.l d0-d1/a0-a3,-(sp)
        lea     EB_LIBLIST(a6),a0
        lea     exp_libname(pc),a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        beq.s   .bn_ret
        move.l  d0,a3                   ; a3 = ExpansionBase
        lea     EB_LIBLIST(a6),a0
        lea     dos_name(pc),a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        beq.s   .bn_ret
        move.l  d0,a0
        move.l  DL_ROOT(a0),a0
        move.l  RN_INFO(a0),d0
        lsl.l   #2,d0
        move.l  d0,a0
        move.l  DI_DEVINFO(a0),d0       ; DeviceNode served by our DF0: handler
.bn_find:
        lsl.l   #2,d0
        beq.s   .bn_ret
        move.l  d0,a2
        move.l  DN_TASK(a2),d0
        cmp.l   DOS_FSPORT,d0
        beq.s   .bn_got
        move.l  DN_NEXT(a2),d0
        bra.s   .bn_find
.bn_got:
        moveq   #BN_SIZEOF,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.s   .bn_ret
        move.l  d0,a1
        move.b  #5,LN_PRI(a1)
        lea     ba_df0(pc),a0
        move.l  a0,LN_NAME(a1)
        move.l  a2,BN_DEVICENODE(a1)
        lea     EB_MOUNTLIST(a3),a0
        jsr     LVO_ENQUEUE(a6)
.bn_ret:
        movem.l (sp)+,d0-d1/a0-a3
        rts

; dos_mountlist(a6 = ExecBase): expansion mount list (spec uae-hd-boot-v34 §4.1), at dos startup. Its head
; is removed (not freed): its DeviceNode is the boot device (DL_BOOTDEV; empty list: DF0). The
; DeviceNode of each BootNode (head included), if not already in di_DevInfo, is appended at the end, in the order
; of the list; the other BootNodes stay in the list. Startup context only (before multitasking:
; no Forbid, whose Permit could reschedule from this context). Preserves everything.
dos_mountlist:
        movem.l d0-d2/a0-a5,-(sp)
        lea     EB_LIBLIST(a6),a0
        lea     dos_name(pc),a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        beq.s   .ml_ret
        move.l  d0,a5                   ; a5 = DosBase
        clr.l   DL_BOOTDEV(a5)
        lea     EB_LIBLIST(a6),a0
        lea     exp_libname(pc),a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        beq.s   .ml_ret
        move.l  d0,a4                   ; a4 = ExpansionBase
        lea     EB_MOUNTLIST(a4),a0
        jsr     LVO_REMHEAD(a6)
        tst.l   d0
        beq.s   .ml_list
        move.l  d0,a0
        move.l  BN_DEVICENODE(a0),DL_BOOTDEV(a5)
        bsr.s   .ml_add
.ml_list:
        move.l  EB_MOUNTLIST(a4),a3
.ml_lp:
        tst.l   (a3)
        beq.s   .ml_ret
        move.l  a3,a0
        bsr.s   .ml_add
        move.l  (a3),a3
        bra.s   .ml_lp
.ml_ret:
        movem.l (sp)+,d0-d2/a0-a5
        rts
.ml_add:                                ; a0 = BootNode: its DeviceNode at the end of di_DevInfo if it is not there
        move.l  BN_DEVICENODE(a0),d0
        beq.s   .ad_ret
        move.l  d0,a1
        move.l  DL_ROOT(a5),a2
        move.l  RN_INFO(a2),d0
        lsl.l   #2,d0
        move.l  d0,a2
        lea     DI_DEVINFO(a2),a2       ; a2 = link (BPTR)
.ad_lp:
        move.l  (a2),d0
        lsl.l   #2,d0
        beq.s   .ad_put
        cmp.l   a1,d0
        beq.s   .ad_ret                 ; already in the list
        move.l  d0,a2                   ; dn_Next at offset 0: the node serves as a link
        bra.s   .ad_lp
.ad_put:
        clr.l   DN_NEXT(a1)
        move.l  a1,d0
        lsr.l   #2,d0
        move.l  d0,(a2)
.ad_ret:
        rts

; ba_ramnode(a5 = DosBase): "RAM" device node (BCPL handler L:RAM-HANDLER loaded on first access, stack 300 longs,
; pri 0, new GV: handlers spec §1) inserted at the head of di_DevInfo. The handler itself writes dn_Task and creates the
; "RAM DISK" volume. Clobbers d0-d1/a0-a1.
ba_ramnode:
        move.l  a6,-(sp)
        move.l  ($4).w,a6
        move.l  #DN_SIZEOF,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.s   .rn_ret
        move.l  d0,a0
        lea     ba_ramhandler(pc),a1
        move.l  a1,d0
        lsr.l   #2,d0
        move.l  d0,DN_HANDLER(a0)
        move.l  #300,DN_STACKSIZE(a0)
        lea     ba_ramname(pc),a1
        move.l  a1,d0
        lsr.l   #2,d0
        move.l  d0,DN_NAME(a0)
        jsr     LVO_FORBID(a6)
        move.l  DL_ROOT(a5),a1
        move.l  RN_INFO(a1),d0
        lsl.l   #2,d0
        move.l  d0,a1
        move.l  DI_DEVINFO(a1),DN_NEXT(a0)
        move.l  a0,d0
        lsr.l   #2,d0
        move.l  d0,DI_DEVINFO(a1)
        jsr     LVO_PERMIT(a6)
.rn_ret:
        move.l  (sp)+,a6
        rts
        cnop    0,4
ba_ramhandler:
        dc.b    13,"L:RAM-HANDLER",0
        cnop    0,4
ba_ramname:
        dc.b    3,"RAM",0
        EVEN

; ba_devnodes(a5 = DosBase): device nodes CON, RAW (ROM console handler conwin_seg as dn_SegList, stack 700 longs,
; pri 5, Startup 0 / 1) then SER, PAR, PRT (L:PORT-HANDLER loaded on first access, stacks 800 / 800 / 1000, Startup
; 0 / 1 / 2), all sharing the GV of the initial CLI (current process); inserted at the head of di_DevInfo in this order
; (handlers spec §1.2). Clobbers d0-d1/a0-a1.
ba_devnodes:
        movem.l d2-d3/a2-a3,-(sp)
        lea     ba_devtab(pc),a2
.dv_lp:
        tst.l   (a2)
        beq.s   .dv_ret
        bsr.s   .dv_one
        lea     20(a2),a2
        bra.s   .dv_lp
.dv_ret:
        movem.l (sp)+,d2-d3/a2-a3
        rts
; one entry: name (BSTR), handler (BSTR | 0), ROM segment (| 0), stack, (pri << 16) | startup
.dv_one:
        move.l  a6,-(sp)
        move.l  ($4).w,a6
        move.l  #DN_SIZEOF,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.s   .do_ret
        move.l  d0,a0
        move.l  (a2),d0
        lsr.l   #2,d0
        move.l  d0,DN_NAME(a0)
        move.l  4(a2),d0
        lsr.l   #2,d0
        move.l  d0,DN_HANDLER(a0)
        move.l  8(a2),d0
        lsr.l   #2,d0
        move.l  d0,DN_SEGLIST(a0)
        move.l  12(a2),DN_STACKSIZE(a0)
        move.w  16(a2),DN_PRIORITY+2(a0)
        move.w  18(a2),DN_STARTUP+2(a0)
        move.l  EB_THISTASK(a6),a1
        move.l  PR_GLOBVEC(a1),d0
        lsr.l   #2,d0
        move.l  d0,DN_GLOBALVEC(a0)
        jsr     LVO_FORBID(a6)
        move.l  DL_ROOT(a5),a1
        move.l  RN_INFO(a1),d0
        lsl.l   #2,d0
        move.l  d0,a1
        move.l  DI_DEVINFO(a1),DN_NEXT(a0)
        move.l  a0,d0
        lsr.l   #2,d0
        move.l  d0,DI_DEVINFO(a1)
        jsr     LVO_PERMIT(a6)
.do_ret:
        move.l  (sp)+,a6
        rts
        cnop    0,4
ba_devtab:
        dc.l    ba_n_con,0,conwin_seg,700,(5<<16)|0
        dc.l    ba_n_raw,0,conwin_seg,700,(5<<16)|1
        dc.l    ba_n_ser,ba_porth,0,800,0
        dc.l    ba_n_par,ba_porth,0,800,1
        dc.l    ba_n_prt,ba_porth,0,1000,2
        dc.l    0
        cnop    0,4
ba_n_con:
        dc.b    3,"CON"
ba_n_raw:
        dc.b    3,"RAW"
ba_n_ser:
        dc.b    3,"SER"
ba_n_par:
        dc.b    3,"PAR"
ba_n_prt:
        dc.b    3,"PRT"
ba_porth:
        dc.b    14,"L:PORT-HANDLER",0
        cnop    0,4

; ba_addnode(d0 = type, d1 = BPTR lock, a0 = C string name, a1 = handler port): allocates a DosList node (+ BSTR of the
; name right after it, long-aligned) and inserts it at the head of di_DevInfo under Forbid. Clobbers d0-d2/a0-a1.
BA_NAMEMAX      EQU 31
ba_addnode:
        movem.l d3-d4/a2/a6,-(sp)
        move.l  d0,d3
        move.l  d1,d4
        move.l  a0,a2
        move.l  a1,-(sp)
        move.l  ($4).w,a6
        move.l  #DN_SIZEOF+BA_NAMEMAX+1,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  (sp)+,a1
        tst.l   d0
        beq.s   .an_ret
        move.l  d0,a0                   ; a0 = node
        move.l  d3,DN_TYPE(a0)
        move.l  a1,DN_TASK(a0)
        move.l  d4,DN_LOCK(a0)
        lea     DN_SIZEOF(a0),a1        ; BSTR of the name
        move.l  a1,d0
        lsr.l   #2,d0
        move.l  d0,DN_NAME(a0)
        moveq   #0,d1
.an_cpy:
        move.b  (a2)+,d0
        beq.s   .an_len
        move.b  d0,1(a1,d1.l)
        addq.l  #1,d1
        cmp.l   #BA_NAMEMAX-1,d1
        bcs.s   .an_cpy
.an_len:
        move.b  d1,(a1)
        jsr     LVO_FORBID(a6)
        move.l  DL_ROOT(a5),a1
        move.l  RN_INFO(a1),d0
        lsl.l   #2,d0
        move.l  d0,a1                   ; DosInfo
        move.l  DI_DEVINFO(a1),DN_NEXT(a0)
        move.l  a0,d0
        lsr.l   #2,d0
        move.l  d0,DI_DEVINFO(a1)
        jsr     LVO_PERMIT(a6)
.an_ret:
        movem.l (sp)+,d3-d4/a2/a6
        rts

ba_df0:
        dc.b    "DF0",0
ba_sysname:
        dc.b    "SYS",0
ba_tab:
        dc.b    "C",0,"c",0
        dc.b    "S",0,"s",0
        dc.b    "L",0,"l",0
        dc.b    "DEVS",0,"devs",0
        dc.b    "LIBS",0,"libs",0
        dc.b    "FONTS",0,"fonts",0
        dc.b    0
        EVEN

; initFunc (D0=base, A0=segList, A6=ExecBase) -> D0=base. Sets the name, allocates RootNode + DosInfo separately
; (AllocMem -> long-aligned), wires dl_Root (APTR) and rn_Info (BPTR = &DosInfo>>2), stores the DL_DISHADOW scaffold.
dos_initfunc:
        movem.l d3/a2,-(sp)         ; a2/d3 non-scratch: preserved for MakeLibrary (AllocMem preserves them too)
        move.l  d0,a2               ; a2 = DosBase
        move.l  d0,DOS_DOSBASE      ; published for the BCPL runtime (no a6 = DosBase in BCPL code)
        clr.l   DOS_OWCTX           ; low memory not cleared on reset
        lea     DOS_HSEM,a0
        jsr     LVO_INITSEMAPHORE(a6)
        lea     dos_name(pc),a0
        move.l  a0,LN_NAME(a2)      ; set the name (V34 quirk)
        moveq   #RN_SIZEOF,d0       ; allocate RootNode
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .out                ; alloc fails -> dl_Root stays 0 (M6D proof will fail cleanly)
        move.l  d0,DL_ROOT(a2)      ; dl_Root = RootNode (APTR, NOT BPTR)
        move.l  d0,d3               ; d3 = RootNode (APTR)
        move.l  #(RN_TASKSLOTS+1)*4,d0  ; rn_TaskArray: [size, slots] (Run takes a free slot there)
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .out
        move.l  d0,a0
        move.l  #RN_TASKSLOTS,(a0)
        lsr.l   #2,d0
        move.l  d3,a0
        move.l  d0,RN_TASKARRAY(a0)
        move.l  #rcli_seg,d0        ; rn_ConsoleSegment = ROM CLI (BCPL segment: Run / Execute without a "CLI" resident)
        lsr.l   #2,d0
        move.l  d0,RN_CONSOLESEG(a0)
        moveq   #DOSINFO_SIZE,d0    ; allocate DosInfo (pointer fields; locks deferred)
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .out                ; DosInfo missing -> rn_Info stays 0
        move.l  d0,DL_DISHADOW(a2)  ; scaffold: &DosInfo (raw APTR, known to the proof)
        move.l  d3,a0               ; a0 = RootNode
        ifeq    M6D_BAD_BPTR
        lsr.l   #2,d0               ; APTR DosInfo -> BPTR (dos convention: BPTR = addr>>2)
        endc                        ; RED M6D_BAD_BPTR: stores the raw APTR -> <<2 round-trip wrong (mismatch, no crash)
        move.l  d0,RN_INFO(a0)      ; rn_Info = BPTR(DosInfo)
        moveq   #RS_SIZEOF,d0       ; Resident list: system "CLI" (use count -1) = ROM CLI, like the real 1.3
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)    ; (EndCLI decrements the use count of the "CLI" node it looks for: without it, it
        tst.l   d0                  ; decremented address 4 = the ExecBase pointer)
        beq     .out
        move.l  d0,a0
        moveq   #-1,d1
        move.l  d1,RS_USAGE(a0)
        move.l  #rcli_seg,d1
        lsr.l   #2,d1
        move.l  d1,RS_SEGLIST(a0)
        move.l  #$03434C49,RS_NAME(a0) ; BSTR "CLI"
        lsr.l   #2,d0
        move.l  DL_DISHADOW(a2),a0
        move.l  d0,DI_RESLIST(a0)
.out:
        move.l  a2,d0               ; return DosBase
        movem.l (sp)+,d3/a2
        rts
dos_end:
