; src/exec/input.s — input.device: resident device managing the HANDLER CHAIN of InputEvents.
;
; Public ABI (devices/input.i + devices/inputevent.i). ROMTag RTF_AUTOINIT NT_DEVICE pri 40 -> MakeLibrary
; (AUTOINIT path) creates the base, Enqueue into EB_DEVICELIST. BeginIO dispatches commands 0-16
; (docs/analysis/keyboard-input-devices-v34.md §3.3):
;   IND_ADDHANDLER / IND_REMHANDLER: Enqueue / Remove the handler's struct Interrupt (io_Data) in the chain,
;     sorted by descending LN_PRI (head = highest priority) — same mechanism as AddIntServer.
;   IND_SETTHRESH / IND_SETPERIOD: key repeat delay and period (read by the keyboard feeder).
;   IND_WRITEEVENT: walks the chain; each handler receives a0 = InputEvent list, a1 = is_Data,
;     a5 = is_Code, and RETURNS in d0 the (possibly modified) list passed to the next handler.
;   IND_SETMPORT / SETMTYPE / SETMTRIG: mouse port, controller type and trigger, applied to gameport.device.
;   CMD_STOP / START / RESET: the mouse stops / resumes feeding the chain. CMD_CLEAR / FLUSH: nothing to do.
; Deviation: no input.device task. The keyboard feeder (dos/feeder.s) and the gameport VBlank server inject their
; events through IND_WRITEEVENT, the chain runs in the context of the caller, so every command completes at once
; (replied unless IOF_QUICK) and CMD_STOP does not hold back the keyboard feeder nor its timer ticks.
; IMPLEMENTATION track ("clean"): AutoDocs input.device + public NDK includes + docs/analysis. NO ROM reading.

                include "exec.i"

                xref    newlist          ; lists.s (NEWLIST of the handler chain)
                xref    gp_mousesrc      ; gameport.s (system mouse source)

IO_ACTUAL2      EQU 32               ; IOStdReq fields — defined locally (avoids including disk.i)
IO_LENGTH2      EQU 36
IO_DATA2        EQU 40
IOSTD_SIZE_I    EQU 48
IOERR_BADLEN_I  EQU -4
LIBB_DELEXP_I   EQU 3
GPD_SETCTYPE_I  EQU 11
GPD_SETTRIGGER_I EQU 13
GPCT_MOUSE_I    EQU 1
ID_NCMDS        EQU 17

; private fields after the public part of the base (exec.i: ID_HANDLERS, ID_THRESH, ID_PERIOD)
ID_FLAGS        EQU INPUT_SIZE       ; byte: IDB_STOPPED
ID_MSRC         EQU INPUT_SIZE+1     ; byte: mouse source handed to gameport (port 0/1, or ID_NOMOUSE)
ID_MPORT        EQU INPUT_SIZE+2     ; byte: IND_SETMPORT
ID_MTYPE        EQU INPUT_SIZE+3     ; byte: IND_SETMTYPE
ID_MTRIG        EQU INPUT_SIZE+4     ; struct GamePortTrigger: IND_SETMTRIG
ID_SIZE         EQU INPUT_SIZE+12
IDB_STOPPED     EQU 0
ID_NOMOUSE      EQU $80              ; gp_mousesrc: bit 7 = no mouse
GPMS_STOPPED    EQU 6                ; gp_mousesrc: bit 6 = input.device stopped

; --- input.device ROMTag (scanned by build_reslist) ---
                EVEN
input_romtag:
        dc.w    RTC_MATCHWORD
        dc.l    input_romtag         ; RT_MATCHTAG = self
        dc.l    input_end            ; RT_ENDSKIP
        dc.b    RTF_AUTOINIT|RTF_COLDSTART,34,NT_DEVICE,40  ; RT_FLAGS, RT_VERSION, RT_TYPE, RT_PRI (40: input roadmap slot)
        dc.l    input_name           ; RT_NAME
        dc.l    input_name           ; RT_IDSTRING
        dc.l    input_inittab        ; RT_INIT -> AUTOINIT table
input_name:
        dc.b    "input.device",0
        EVEN
input_inittab:
        dc.l    ID_SIZE              ; dataSize
        dc.l    input_vectors        ; funcTable
        dc.l    input_datatab        ; dataTable (InitStruct)
        dc.l    input_initfunc       ; initFunc
input_vectors:                       ; ABSOLUTE table, terminated by -1 (standard device order)
        dc.l    input_open           ; LVO -6
        dc.l    input_close          ; LVO -12
        dc.l    input_expunge        ; LVO -18
        dc.l    input_null           ; LVO -24 (reserved)
        dc.l    input_beginio        ; LVO -30
        dc.l    input_abortio        ; LVO -36
        dc.l    -1
input_datatab:
        dc.w    $E000,LN_TYPE,(NT_DEVICE<<8)   ; INITBYTE(LN_TYPE, NT_DEVICE)
        dc.w    $D000,LIB_VERSION,34           ; INITWORD(LIB_VERSION, 34)
        dc.b    0
        EVEN

; Open(device a6, ioreq a1, unit d0, flags d1): unit and flags ignored, always succeeds.
input_open:
        addq.w  #1,LIB_OPENCNT(a6)
        rts
input_close:
        subq.w  #1,LIB_OPENCNT(a6)
        moveq   #0,d0
        rts
input_expunge:                       ; never expunges: delayed-expunge flag only
        bset    #LIBB_DELEXP_I,LIB_FLAGS(a6)
input_null:
input_abortio:                       ; nothing ever stays pending (synchronous device)
        moveq   #0,d0
        rts

; input_beginio(device a6, ioreq a1): commands 0-16, a number >= 17 is CMD_INVALID. Replied unless IOF_QUICK.
; a6 on exit = device base (BeginIO conv.: the caller reloads SysBase if it needs it). Preserves a2-a5;
; clobbers d0/d1/a0/a1.
input_beginio:
        movem.l a2-a5,-(sp)
        move.l  a6,a2                ; a2 = device base
        move.l  a1,a3                ; a3 = ioreq
        move.l  ($4).w,a6            ; a6 = SysBase
        and.b   #$0F,IO_FLAGS(a3)
        clr.b   IO_ERROR(a3)
        moveq   #0,d0
        move.w  IO_COMMAND(a3),d0
        cmp.w   #ID_NCMDS,d0
        blo.s   .bi_cmd
        moveq   #0,d0
.bi_cmd:
        add.w   d0,d0
        move.w  input_cmdtab(pc,d0.w),d0
        jsr     input_cmdtab(pc,d0.w)    ; -> d0.b = io_Error
        move.b  d0,IO_ERROR(a3)
        btst    #0,IO_FLAGS(a3)      ; IOF_QUICK
        bne.s   .bi_quick
        move.l  ($4).w,a6            ; (a handler of the chain may have changed it)
        move.l  a3,a1
        jsr     LVO_REPLYMSG(a6)
.bi_quick:
        move.l  a2,a6                ; a6 = device base (BeginIO convention)
        movem.l (sp)+,a2-a5
        rts
input_cmdtab:
        dc.w    in_nocmd-input_cmdtab    ; 0 CMD_INVALID
        dc.w    in_start-input_cmdtab    ; 1 CMD_RESET = STOP + FLUSH + START
        dc.w    in_nocmd-input_cmdtab    ; 2 CMD_READ
        dc.w    in_nocmd-input_cmdtab    ; 3 CMD_WRITE (events go through IND_WRITEEVENT)
        dc.w    in_nocmd-input_cmdtab    ; 4 CMD_UPDATE
        dc.w    in_ok-input_cmdtab       ; 5 CMD_CLEAR (never replied on 1.3)
        dc.w    in_stop-input_cmdtab     ; 6 CMD_STOP
        dc.w    in_start-input_cmdtab    ; 7 CMD_START
        dc.w    in_ok-input_cmdtab       ; 8 CMD_FLUSH (nothing is ever queued)
        dc.w    in_add-input_cmdtab      ; 9 IND_ADDHANDLER
        dc.w    in_rem-input_cmdtab      ; 10 IND_REMHANDLER
        dc.w    in_write-input_cmdtab    ; 11 IND_WRITEEVENT
        dc.w    in_thresh-input_cmdtab   ; 12 IND_SETTHRESH
        dc.w    in_period-input_cmdtab   ; 13 IND_SETPERIOD
        dc.w    in_mport-input_cmdtab    ; 14 IND_SETMPORT
        dc.w    in_mtype-input_cmdtab    ; 15 IND_SETMTYPE
        dc.w    in_mtrig-input_cmdtab    ; 16 IND_SETMTRIG

in_nocmd:
        moveq   #IOERR_NOCMD,d0
        rts
in_badlen:
        moveq   #IOERR_BADLEN_I,d0
        rts
; CMD_STOP: the mouse stops feeding the handler chain (gameport keeps buffering); the commands the 1.3 task takes
; from its port (IND_ADDHANDLER/REMHANDLER/WRITEEVENT) still run.
in_stop:
        bset    #IDB_STOPPED,ID_FLAGS(a2)
        bra.s   in_msrc
in_start:
        bclr    #IDB_STOPPED,ID_FLAGS(a2)
in_msrc:
        moveq   #0,d0
        move.b  ID_MSRC(a2),d0
        bsr     in_setsrc
in_ok:
        moveq   #0,d0
        rts
in_thresh:
        lea     ID_THRESH(a2),a0
        bra.s   in_tv
in_period:
        lea     ID_PERIOD(a2),a0
in_tv:                               ; timeval of the request (like a timerequest), taken into account at the next
        move.l  TV_SECS(a3),(a0)+    ; arming of the repeat (keyboard feeder)
        move.l  TV_MICRO(a3),(a0)
        bra.s   in_ok
in_add:
        lea     ID_HANDLERS(a2),a0   ; handler chain
        move.l  IO_DATA2(a3),a1      ; a1 = &struct Interrupt of the handler
        jsr     LVO_ENQUEUE(a6)      ; inserts sorted by LN_PRI (head = highest pri)
        bra.s   in_ok
in_rem:
        move.l  IO_DATA2(a3),a1
        jsr     LVO_REMOVE(a6)       ; Remove(node a1)
        bra.s   in_ok
; IND_WRITEEVENT: the single InputEvent at io_Data (ie_NextEvent forced to NULL) goes down the chain.
in_write:
                ifne    INPUT_NO_PROPAGATE
        bra.s   in_ok                ; RED INPUT_NO_PROPAGATE: does NOT walk the chain -> no handler called
                endc
        move.l  IO_DATA2(a3),a0      ; a0 = InputEvent (passed to the 1st handler)
        clr.l   IE_NEXTEVENT(a0)
        lea     ID_HANDLERS(a2),a1
        move.l  (a1),a4              ; a4 = lh_Head (1st handler or tail sentinel)
.iw_loop:
        move.l  (a4),d0              ; d0 = a4->Succ; 0 => a4 = tail sentinel -> end
        beq.s   in_ok
        move.l  d0,-(sp)             ; save Succ (robust if a handler modifies the chain)
        move.l  IS_DATA(a4),a1       ; a1 = is_Data
        move.l  IS_CODE(a4),a5       ; a5 = is_Code
        jsr     (a5)                 ; handler(a0 = events, a1 = data) -> d0 = list for the next one
        move.l  d0,a0                ; result = input of the next handler
        move.l  (sp)+,a4             ; a4 = Succ (advance)
        bra.s   .iw_loop

; IND_SETMPORT / IND_SETMTYPE: io_Data[0] stored (io_Length low word >= 1), io_Actual = 1. IND_SETMTRIG: 8 bytes of
; GamePortTrigger (io_Length low word >= 8), io_Actual = 8. Each one re-opens the mouse unit (in_mouse). Values are
; not checked: a port other than 0/1, or a type that is not GPCT_MOUSE, leaves the system without mouse.
in_mport:
        lea     ID_MPORT(a2),a0
        bra.s   in_mbyte
in_mtype:
        lea     ID_MTYPE(a2),a0
in_mbyte:
        tst.w   IO_LENGTH2+2(a3)
        beq.s   in_badlen
        move.l  IO_DATA2(a3),a1
        move.b  (a1),(a0)
        moveq   #1,d0
        bra.s   in_mset
in_mtrig:
        cmp.w   #8,IO_LENGTH2+2(a3)
        blo   in_badlen
        move.l  IO_DATA2(a3),a1
        lea     ID_MTRIG(a2),a0
        move.l  (a1)+,(a0)+
        move.l  (a1),(a0)
        moveq   #8,d0
in_mset:
        move.l  d0,IO_ACTUAL2(a3)
        bsr.s   in_mouse
        bra   in_ok

; in_mouse(device a2, a6 = SysBase): the 1.3 re-open sequence (§3.4), done at once in the caller's context:
; OpenDevice("gameport.device", port), GPD_SETCTYPE(type), GPD_SETTRIGGER(trigger), CloseDevice (the unit keeps its
; settings). The system mouse (gp_vblank_server) then reads that port; none if the open failed or the type is not
; GPCT_MOUSE. Preserves a2-a5.
in_mouse:
        movem.l a3-a4,-(sp)
        lea     -IOSTD_SIZE_I(sp),sp
        move.l  sp,a3
        move.l  a3,a0
        moveq   #IOSTD_SIZE_I/4-1,d0
.im_clr:
        clr.l   (a0)+
        dbra    d0,.im_clr
        lea     in_gpname(pc),a0
        moveq   #0,d0
        move.b  ID_MPORT(a2),d0
        move.l  a3,a1
        moveq   #0,d1
        jsr     LVO_OPENDEVICE(a6)
        moveq   #0,d1
        move.b  #ID_NOMOUSE,d1
        tst.b   d0
        bne.s   .im_src
        move.l  IO_DEVICE(a3),a4
        move.w  #GPD_SETCTYPE_I,IO_COMMAND(a3)
        moveq   #1,d0
        lea     ID_MTYPE(a2),a0
        bsr.s   .im_gpio
        move.w  #GPD_SETTRIGGER_I,IO_COMMAND(a3)
        moveq   #8,d0
        lea     ID_MTRIG(a2),a0
        bsr.s   .im_gpio
        move.l  a3,a1
        jsr     LVO_CLOSEDEVICE(a6)
        moveq   #0,d1
        move.b  #ID_NOMOUSE,d1
        cmp.b   #GPCT_MOUSE_I,ID_MTYPE(a2)
        bne.s   .im_src
        moveq   #1,d1
        and.b   ID_MPORT(a2),d1
.im_src:
        move.b  d1,ID_MSRC(a2)
        move.l  d1,d0
        bsr.s   in_setsrc
        lea     IOSTD_SIZE_I(sp),sp
        movem.l (sp)+,a3-a4
        rts
.im_gpio:                            ; BeginIO(IOF_QUICK) of a gameport command completed at once (errors ignored)
        move.l  d0,IO_LENGTH2(a3)
        move.l  a0,IO_DATA2(a3)
        move.b  #IOF_QUICK,IO_FLAGS(a3)
        move.l  a3,a1
        move.l  a6,-(sp)
        move.l  a4,a6
        jsr     -30(a6)
        move.l  (sp)+,a6
        rts

; in_setsrc(d0.l = ID_MSRC value, device a2, a6 = SysBase): hands the mouse source, plus the stopped state, to
; gameport.device. Preserves a2-a6.
in_setsrc:
        btst    #IDB_STOPPED,ID_FLAGS(a2)
        beq.s   .ss_run
        bset    #GPMS_STOPPED,d0
.ss_run:
        move.l  d0,-(sp)
        lea     EB_DEVICELIST(a6),a0
        lea     in_gpname(pc),a1
        jsr     LVO_FINDNAME(a6)
        move.l  d0,a0
        move.l  (sp)+,d0
        move.l  a0,d1
        beq.s   .ss_ret
        jsr     gp_mousesrc
.ss_ret:
        rts

; initFunc (D0=base, A0=segList, A6=ExecBase) -> D0 = base. Sets the name (V34 quirk), NEWLISTs the handler chain,
; default repeat timing and mouse settings (port 0, GPCT_MOUSE, trigger {DOWNKEYS|UPKEYS, 0, 1, 1}).
input_initfunc:
        move.l  d0,a1
        lea     input_name(pc),a0
        move.l  a0,LN_NAME(a1)       ; set the name
        move.l  d0,-(sp)             ; save the base (newlist clobbers a0)
        move.l  #800000,ID_THRESH+4(a1) ; default repeat: 0.8 s then 0.1 s (base zeroed by MakeLibrary)
        move.l  #100000,ID_PERIOD+4(a1)
        move.b  #GPCT_MOUSE_I,ID_MTYPE(a1)
        move.l  #$00030000,ID_MTRIG(a1)
        move.l  #$00010001,ID_MTRIG+4(a1)
        lea     ID_HANDLERS(a1),a1   ; NEWLIST(handler chain)
        jsr     newlist
        move.l  (sp)+,d0             ; d0 = base (return value)
        rts

in_gpname:
        dc.b    "gameport.device",0
        EVEN
input_end:
