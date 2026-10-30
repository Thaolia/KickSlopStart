; src/exec/input.s — input.device (#2): resident device managing the HANDLER CHAIN of InputEvents.
;
; Public ABI (devices/input.i + devices/inputevent.i). ROMTag RTF_AUTOINIT NT_DEVICE pri 40 -> MakeLibrary
; (AUTOINIT path) creates the base, Enqueue into EB_DEVICELIST. BeginIO dispatches on io_Command:
;   IND_ADDHANDLER / IND_REMHANDLER: Enqueue / Remove the handler's struct Interrupt (io_Data) in the chain,
;     sorted by descending LN_PRI (head = highest priority) — same mechanism as AddIntServer.
;   IND_SETTHRESH / IND_SETPERIOD: key repeat delay and period (read by the keyboard feeder).
;   IND_WRITEEVENT: walks the chain; each handler receives a0 = InputEvent list, a1 = is_Data,
;     a5 = is_Code, and RETURNS in d0 the (possibly modified) list passed to the next handler.
; IND_WRITEEVENT is the first-class PUBLIC injection point (Intuition uses it to inject
; events). The LIVE keyboard -> input.device -> console wiring will be done in #3 (real console.device), where
; console.device is the natural consumer of IND_ADDHANDLER. Synchronous (no ReplyMsg: the caller reads
; io_Error directly, like trackdisk). Deviation #2: no input.task nor keyboard/gameport opening
; (the chain runs in the context of the IND_WRITEEVENT caller) — faithful on the handler-chain ABI side.
; IMPLEMENTATION track ("clean"): AutoDocs input.device + public NDK includes. NO ROM reading.

                include "exec.i"

                xref    newlist          ; lists.s (NEWLIST of the handler chain)

IO_DATA2        EQU 40               ; IOStdReq: io_Data (APTR) — defined locally (avoids including disk.i)

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
        dc.l    INPUT_SIZE           ; dataSize
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

; Open(device a6, ioreq a1, unit d0, flags d1): increments the open count.
input_open:
        addq.w  #1,LIB_OPENCNT(a6)
        rts
input_close:
        subq.w  #1,LIB_OPENCNT(a6)
        moveq   #0,d0
        rts
input_expunge:
        moveq   #0,d0                ; resident base: no expunge
        rts
input_null:
        moveq   #0,d0
        rts
input_abortio:
        moveq   #0,d0
        rts

; input_beginio(device a6, ioreq a1): dispatch on io_Command. Synchronous: replied unless IOF_QUICK (every caller
; inside the ROM sets it). a6 on exit = device base (BeginIO conv.: the caller reloads SysBase if it needs it).
; Preserves a2-a5; clobbers d0/d1/a0/a1.
input_beginio:
        movem.l a2-a5,-(sp)
        move.l  a6,a2                ; a2 = device base
        move.l  a1,a3                ; a3 = ioreq
        move.l  ($4).w,a6            ; a6 = SysBase (for Enqueue/Remove)
        clr.b   IO_ERROR(a3)
        move.w  IO_COMMAND(a3),d0
        cmp.w   #IND_ADDHANDLER,d0
        beq.s   .bi_add
        cmp.w   #IND_REMHANDLER,d0
        beq.s   .bi_rem
        cmp.w   #IND_WRITEEVENT,d0
        beq.s   .bi_write
        lea     ID_THRESH(a2),a0
        cmp.w   #IND_SETTHRESH,d0
        beq.s   .bi_tv
        lea     ID_PERIOD(a2),a0
        cmp.w   #IND_SETPERIOD,d0
        beq.s   .bi_tv
        move.b  #IOERR_NOCMD,IO_ERROR(a3)   ; unrecognised command
        bra.s   .bi_done
.bi_tv:                              ; SETTHRESH / SETPERIOD: timeval of the request (like a timerequest), taken
        move.l  TV_SECS(a3),(a0)+    ; into account at the next arming of the repeat (keyboard feeder)
        move.l  TV_MICRO(a3),(a0)
        bra.s   .bi_done
.bi_add:
        lea     ID_HANDLERS(a2),a0   ; handler chain
        move.l  IO_DATA2(a3),a1      ; a1 = &struct Interrupt of the handler
        jsr     LVO_ENQUEUE(a6)      ; inserts sorted by LN_PRI (head = highest pri)
        bra.s   .bi_done
.bi_rem:
        move.l  IO_DATA2(a3),a1
        jsr     LVO_REMOVE(a6)       ; Remove(node a1)
        bra.s   .bi_done
.bi_write:
                ifne    INPUT_NO_PROPAGATE
        bra.s   .bi_done             ; RED INPUT_NO_PROPAGATE: does NOT walk the chain -> no handler called
                endc
        move.l  IO_DATA2(a3),a0      ; a0 = InputEvent list (passed to the 1st handler)
        lea     ID_HANDLERS(a2),a1
        move.l  (a1),a4              ; a4 = lh_Head (1st handler or tail sentinel)
.bi_wloop:
        move.l  (a4),d0              ; d0 = a4->Succ; 0 => a4 = tail sentinel -> end
        beq.s   .bi_done
        move.l  d0,-(sp)             ; save Succ (robust if a handler modifies the chain)
        move.l  IS_DATA(a4),a1       ; a1 = is_Data
        move.l  IS_CODE(a4),a5       ; a5 = is_Code
        jsr     (a5)                 ; handler(a0 = events, a1 = data) -> d0 = list for the next one
        move.l  d0,a0                ; result = input of the next handler
        move.l  (sp)+,a4             ; a4 = Succ (advance)
        bra.s   .bi_wloop
.bi_done:
        btst    #0,IO_FLAGS(a3)      ; IOF_QUICK
        bne.s   .bi_quick
        move.l  ($4).w,a6            ; (a handler of the chain may have changed it)
        move.l  a3,a1
        jsr     LVO_REPLYMSG(a6)
.bi_quick:
        move.l  a2,a6                ; a6 = device base (BeginIO convention)
        movem.l (sp)+,a2-a5
        rts

; initFunc (D0=base, A0=segList, A6=ExecBase) -> D0 = base. Sets the name (V34 quirk), NEWLISTs the handler chain.
input_initfunc:
        move.l  d0,a1
        lea     input_name(pc),a0
        move.l  a0,LN_NAME(a1)       ; set the name
        move.l  d0,-(sp)             ; save the base (newlist clobbers a0)
        move.l  #800000,ID_THRESH+4(a1) ; default repeat: 0.8 s then 0.1 s (base zeroed by MakeLibrary)
        move.l  #100000,ID_PERIOD+4(a1)
        lea     ID_HANDLERS(a1),a1   ; NEWLIST(handler chain)
        jsr     newlist
        move.l  (sp)+,d0             ; d0 = base (return value)
        rts

        EVEN
input_end:
