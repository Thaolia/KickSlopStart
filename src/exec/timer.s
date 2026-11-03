; src/exec/timer.s — timer.device — M5c (AUTOINIT creation) + M6a (functional VBLANK unit).
; 2nd real resident module, 1st DEVICE. RTF_AUTOINIT ROMTag (pri 50) -> AUTOINIT path of
; InitResident (MakeLibrary + Enqueue DeviceList). V34 quirk: the data table sets LN_TYPE +
; LIB_VERSION and the init func sets LN_NAME="timer.device" + initialises the VBLANK unit + registers
; the VBlank service (M7f: timer_vblank_service is a SERVER of the VERTB chain via AddIntServer,
; dispatched by int3_dispatch — no longer the old VBL_SVC hook).
;
; M6a — FUNCTIONAL VBLANK UNIT (without CIA):
;   BeginIO(TR_ADDREQUEST): converts the timeval to TICKS (secs*50 + micro/20000), stores the
;     countdown in TR_TIME, enqueues the request on the VBLANK unit's queue. Disable around
;     the manipulation (the queue is shared with the VBlank handler = interrupt, not just tasks).
;   timer_vblank_service: called from the VBlank handler (IPL 3) every tick. Decrements each
;     request; at 0 -> removes it and replies via ReplyMsg (M7i). HISTORY: until M7h the reply
;     used a bespoke routine (timer_reply) because PutMsg/ReplyMsg called Permit (SYNCHRONOUS
;     reschedule forbidden in an interrupt). M7d made PutMsg/ReplyMsg interrupt-safe (Disable INTENA +
;     raw_enable, WITHOUT Permit/yield tail) -> M7i removed timer_reply and calls ReplyMsg directly.
;     Signal (via PutMsg) sets SAR without rescheduling -> the switch happens on handler exit.
; MICROHZ UNIT (CIA-A timer B, level 2, like 1.3 — spec docs/analysis/timer-v34.md):
;   the init takes bit 1 (timer B) of ciaa.resource through AddICRVector; timer_micro_service is called by
;   cia_dispatch (PORTS server) at each end of one-shot. The one-shot is armed on the nearest deadline; the
;   elapsed time is read back from the counter. No CIA-B timer: a game that hijacks vector $78 (level 6) without
;   chaining no longer breaks the system delays. Conversion into real us (PAL E-clock 709379 Hz).
; IMPLEMENTATION track ("clean"): AutoDocs timer.device + exec + spec docs/analysis/timer-v34.md. NO ROM reading.

                include "exec.i"

                xdef    timer_now         ; system time (dos DateStamp)
                xdef    timer_setnow      ; setting of the system time (BCPL global setdatstamp)

                xref    newlist           ; lists.s (NEWLIST of the unit queue)
                xref    ciaa_server       ; cia.s (distribution of the CIA-A ICR vectors)

; --- timer.device ROMTag (scanned by build_reslist) ---
        EVEN
timer_romtag:
        dc.w    RTC_MATCHWORD
        dc.l    timer_romtag         ; RT_MATCHTAG = self
        dc.l    timer_end            ; RT_ENDSKIP
        dc.b    RTF_AUTOINIT|RTF_COLDSTART,34,NT_DEVICE,50  ; RT_FLAGS, RT_VERSION, RT_TYPE, RT_PRI
        dc.l    timer_name           ; RT_NAME
        dc.l    timer_name           ; RT_IDSTRING
        dc.l    timer_inittab        ; RT_INIT -> AUTOINIT table
timer_name:
        dc.b    "timer.device",0
timer_cianame:
        dc.b    "ciaa.resource",0
        EVEN
timer_inittab:
        dc.l    TD_SIZE              ; dataSize (Library + VBLANK unit queue)
        dc.l    timer_vectors        ; funcTable
        dc.l    timer_datatab        ; dataTable (InitStruct)
        dc.l    timer_initfunc       ; initFunc
timer_vectors:                       ; ABSOLUTE table, terminated by -1 (standard device order)
        dc.l    timer_open           ; LVO -6
        dc.l    timer_close          ; LVO -12
        dc.l    timer_expunge        ; LVO -18
        dc.l    timer_null           ; LVO -24 (reserved / ExtFunc)
        dc.l    timer_beginio        ; LVO -30
        dc.l    timer_abortio        ; LVO -36
        dc.l    timer_addtime        ; LVO -42 AddTime(dest a0, src a1)
        dc.l    timer_subtime        ; LVO -48 SubTime(dest a0, src a1)
        dc.l    timer_cmptime        ; LVO -54 CmpTime(dest a0, src a1) -> d0
        dc.l    -1
timer_datatab:
        dc.w    $E000,LN_TYPE,(NT_DEVICE<<8)  ; INITBYTE(LN_TYPE, NT_DEVICE)
        dc.w    $D000,LIB_VERSION,34          ; INITWORD(LIB_VERSION, 34)
        dc.b    0
        EVEN

; Open(device a6, iorequest a1, unit d0, flags d1): unit 0 (MICROHZ) or 1 (VBLANK) -> io_Unit = unit, open
; count + 1; unit >= 2 -> io_Error = IOERR_OPENFAIL, nothing counted (like 1.3).
timer_open:
        cmp.l   #UNIT_VBLANK,d0
        bhi.s   .to_fail
        move.l  d0,IO_UNIT(a1)
        addq.w  #1,LIB_OPENCNT(a6)
        rts
.to_fail:
        move.b  #IOERR_OPENFAIL,IO_ERROR(a1)
        rts
; Close(device a6, iorequest a1): io_Device = io_Unit = -1, open count - 1.
timer_close:
        moveq   #-1,d0
        move.l  d0,IO_DEVICE(a1)
        move.l  d0,IO_UNIT(a1)
        subq.w  #1,LIB_OPENCNT(a6)
        moveq   #0,d0
        rts
timer_expunge:
        moveq   #0,d0
        rts
timer_null:
        moveq   #0,d0
        rts

; AddTime(dest a0, src a1): dest += src, then while micro >= 1 000 000: one second carried (a negative micro
; is not corrected, as in 1.3). SubTime(dest a0, src a1): dest -= src, then while micro < 0: one second
; borrowed (a micro >= 1 000 000 is not corrected). Do not read a6; destroy d0/d1.
timer_addtime:
        move.l  TV_SECS-IO_SIZE(a1),d0
        add.l   d0,TV_SECS-IO_SIZE(a0)
        move.l  TV_MICRO-IO_SIZE(a1),d0
        add.l   TV_MICRO-IO_SIZE(a0),d0
        move.l  #1000000,d1
.at_lp:
        cmp.l   d1,d0
        blt.s   .at_set
        sub.l   d1,d0
        addq.l  #1,TV_SECS-IO_SIZE(a0)
        bra.s   .at_lp
.at_set:
        move.l  d0,TV_MICRO-IO_SIZE(a0)
        rts
timer_subtime:
        move.l  TV_SECS-IO_SIZE(a1),d0
        sub.l   d0,TV_SECS-IO_SIZE(a0)
        move.l  TV_MICRO-IO_SIZE(a0),d0
        sub.l   TV_MICRO-IO_SIZE(a1),d0
.st_lp:
        tst.l   d0
        bpl.s   .st_set
        add.l   #1000000,d0
        subq.l  #1,TV_SECS-IO_SIZE(a0)
        bra.s   .st_lp
.st_set:
        move.l  d0,TV_MICRO-IO_SIZE(a0)
        rts
; CmpTime(dest a0, src a1) -> d0 = 0 if equal, +1 if src > dest, -1 if src < dest (seconds then us, unsigned).
timer_cmptime:
        move.l  TV_SECS-IO_SIZE(a1),d0
        cmp.l   TV_SECS-IO_SIZE(a0),d0
        bne.s   .ct_diff
        move.l  TV_MICRO-IO_SIZE(a1),d0
        cmp.l   TV_MICRO-IO_SIZE(a0),d0
        bne.s   .ct_diff
        moveq   #0,d0
        rts
.ct_diff:
        bhi.s   .ct_gt
        moveq   #-1,d0
        rts
.ct_gt:
        moveq   #1,d0
        rts

; timer_vbconv(a3 = VBLANK request, a6 = SysBase) -> d0 = frames to its deadline: the k-th VBlank, k = max(1,
; ceil(T / P)), P = round(1000000 / VBlankFrequency), 0 counting as 60 (timer-v34 §3): 20000 us in PAL, 16667 in
; NTSC. Whole seconds count VBlankFrequency frames each. Clobbers d1/d2.
timer_vbconv:
        moveq   #0,d0
        move.b  EB_VBLANKFREQ(a6),d0
        bne.s   .vc_f
        moveq   #60,d0
.vc_f:
        move.l  d0,d1
        lsr.w   #1,d1
        add.l   #1000000,d1
        divu    d0,d1                ; d1.w = P
        mulu    TV_SECS+2(a3),d0     ; frames of the whole seconds
        move.l  TV_MICRO(a3),d2
        beq.s   .vc_min
        subq.l  #1,d2
        divu    d1,d2                ; ceil(us / P) = (us - 1) / P + 1
        and.l   #$0000FFFF,d2
        addq.l  #1,d2
        add.l   d2,d0
.vc_min:
        tst.l   d0
        bne.s   .vc_ret
        moveq   #1,d0
.vc_ret:
        rts

; timer_systime(a2 = timer.device base, a6 = SysBase) -> d0 = seconds, d1 = us of the system time (timer-v34 §4):
; base + CIA-A TOD converted at the mains rate + the uniqueness counter, which then grows by 1 us, so two reads never
; return the same time. Preserves d2-d7/a0-a6.
timer_systime:
        movem.l d2-d3/a0,-(sp)
        lea     CIAA_HW,a0
        jsr     LVO_DISABLE(a6)
        moveq   #0,d0
        move.b  CIA_TODHI(a0),d0     ; high byte first: the 8520 latches the reading until the low byte
        swap    d0
        move.b  CIA_TODMID(a0),d0
        lsl.w   #8,d0
        move.b  CIA_TODLO(a0),d0
        move.l  TIMER_UNIQ(a2),d3
        addq.l  #1,TIMER_UNIQ(a2)
        jsr     LVO_ENABLE(a6)
        divu    TIMER_TODHZ(a2),d0   ; the fold-over keeps the TOD below 65536 ticks: the quotient fits a word
        moveq   #0,d2
        move.w  d0,d2                ; d2 = seconds of TOD
        clr.w   d0
        swap    d0                   ; d0 = remaining ticks
        mulu    TIMER_TODUS(a2),d0
        move.l  d0,d1
        add.l   d3,d1
        add.l   TIMER_SYSMICRO(a2),d1
        add.l   TIMER_SYSSECS(a2),d2
.sy_norm:
        cmp.l   #1000000,d1
        blo.s   .sy_ret
        sub.l   #1000000,d1
        addq.l  #1,d2
        bra.s   .sy_norm
.sy_ret:
        move.l  d2,d0
        movem.l (sp)+,d2-d3/a0
        rts

; timer_setsys(a2 = base, d0 = seconds, d1 = us): new base, CIA-A TOD and uniqueness counter back to 0, so the next
; read returns exactly this time. Clobbers d0/d1/a0.
timer_setsys:
        move.l  d0,TIMER_SYSSECS(a2)
        move.l  d1,TIMER_SYSMICRO(a2)
        jsr     LVO_DISABLE(a6)
        clr.l   TIMER_UNIQ(a2)
        bsr.s   timer_todzero
        jmp     LVO_ENABLE(a6)

; timer_todzero: CIA-A TOD := 0 (CRB ALARM cleared, the time is written high byte first, the low byte restarts it).
; MOVE, not CLR: a CLR reads first, and reading the high byte latches the TOD. Clobbers d0/a0.
timer_todzero:
        lea     CIAA_HW,a0
        bclr    #7,CIA_CRB(a0)
        moveq   #0,d0
        move.b  d0,CIA_TODHI(a0)
        move.b  d0,CIA_TODMID(a0)
        move.b  d0,CIA_TODLO(a0)
        rts

; timer_setnow(a6 = SysBase, d0 = seconds, d1 = us): sets the system time (TR_SETSYSTIME without IORequest).
; Preserves d2-d7/a2-a6.
timer_setnow:
        movem.l d0-d1/a2,-(sp)
        lea     EB_DEVICELIST(a6),a0
        lea     timer_name(pc),a1
        jsr     LVO_FINDNAME(a6)
        move.l  d0,a2
        movem.l (sp)+,d0-d1
        cmpa.w  #0,a2
        beq.s   .ts_ret
        bsr.s   timer_setsys
.ts_ret:
        move.l  (sp)+,a2
        rts

; timer_now(a6 = SysBase) -> d0 = seconds, d1 = us of the system time (0 / 0 without timer.device). For DateStamp.
; Preserves d2-d7/a2-a6.
timer_now:
        move.l  a2,-(sp)
        lea     EB_DEVICELIST(a6),a0
        lea     timer_name(pc),a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        beq.s   .tn_none
        move.l  d0,a2
        bsr     timer_systime
        move.l  (sp)+,a2
        rts
.tn_none:
        moveq   #0,d1
        move.l  (sp)+,a2
        rts

; BeginIO(device a6, iorequest a1): TR_ADDREQUEST is queued on its unit (VBLANK: countdown in frames; MICROHZ: CIA-A
; timer B), TR_GETSYSTIME / TR_SETSYSTIME act on the system clock at once. Disable around the queues (shared with
; the interrupts).
timer_beginio:
        movem.l d2/a2-a4,-(sp)
        move.l  a6,a2                ; a2 = device base
        move.l  a1,a3                ; a3 = iorequest
        move.l  ($4).w,a6            ; a6 = SysBase (for the exec calls)
        clr.b   IO_ERROR(a3)
        move.w  IO_COMMAND(a3),d0
        cmp.w   #TR_ADDREQUEST,d0
        beq.s   .bio_add
        cmp.w   #TR_GETSYSTIME,d0
        beq.s   .bio_get
        cmp.w   #TR_SETSYSTIME,d0
        beq.s   .bio_set
        move.b  #IOERR_NOCMD,IO_ERROR(a3)
        bra.s   .bio_done
.bio_set:
        move.l  TV_SECS(a3),d0
        move.l  TV_MICRO(a3),d1
        bsr     timer_setsys
        bra.s   .bio_done
.bio_get:
        bsr     timer_systime
        move.l  d0,TV_SECS(a3)
        move.l  d1,TV_MICRO(a3)
.bio_done:
        btst    #0,IO_FLAGS(a3)      ; IOF_QUICK: completed in place; otherwise reply to the reply port
        bne.s   .bio_ret
        move.l  a3,a1
        jsr     LVO_REPLYMSG(a6)
.bio_ret:
        move.l  a2,a6
        movem.l (sp)+,d2/a2-a4
        rts
.bio_add:
        jsr     LVO_DISABLE(a6)      ; queues shared with the VBlank server and the CIA-A interrupt
        move.b  #NT_MESSAGE,LN_TYPE(a3)
        bclr    #0,IO_FLAGS(a3)      ; request queued: never quick (DoIO will wait for the reply)
        cmp.l   #UNIT_VBLANK,IO_UNIT(a3)
        beq.s   .bio_vbl
        bsr     tm_conv              ; MICROHZ: remainder in (seconds, E ticks)
        move.l  a3,-(sp)
        bsr     tm_account           ; elapsed time charged to the requests already queued BEFORE adding this one
        move.l  (sp)+,a1
        lea     TIMER_MICROQ(a2),a0
        jsr     LVO_ADDTAIL(a6)
        bsr     tm_rearm
        bra.s   .bio_queued
.bio_vbl:
        bsr     timer_vbconv         ; VBLANK: countdown in frames
.bio_store:
        move.l  d0,TV_SECS(a3)       ; countdown (TV_SECS reused)
        clr.l   TV_MICRO(a3)
        lea     TIMER_VBLQ(a2),a0
        move.l  a3,a1
        jsr     LVO_ADDTAIL(a6)
.bio_queued:
        jsr     LVO_ENABLE(a6)
        move.l  a2,a6                ; restore a6 = device base
        movem.l (sp)+,d2/a2-a4
        rts

; tm_div1000(d0 = dividend) -> d0 = quotient, d1 = remainder of the division by 1000. Preserves d2-d7/a0-a6.
tm_div1000:
        move.l  d2,-(sp)
        moveq   #0,d1
        swap    d0
        move.w  d0,d1
        divu    #1000,d1             ; d1 = remainder: quotient of the high word
        move.w  d1,d2
        swap    d0
        move.w  d0,d1                ; remainder: low word
        divu    #1000,d1
        swap    d2
        move.w  d1,d2                ; d2 = complete quotient
        clr.w   d1
        swap    d1                   ; d1 = remainder
        move.l  d2,d0
        move.l  (sp)+,d2
        rts

; tm_conv(a3 = MICROHZ request): timeval -> remainder (TV_SECS seconds, TV_MICRO E ticks within the second), at least
; 1 tick. us normalised (>= 1 s carried into the seconds). Clobbers d0/d1.
tm_conv:
                ifne    M7L_OLD_CONV
        move.l  TV_SECS(a3),d0       ; RED: old VBLANK conversion (/20000) applied to steps of 255 ticks
        mulu    #50,d0
        move.l  TV_MICRO(a3),d1
        divu    #20000,d1
        and.l   #$0000FFFF,d1
        add.l   d1,d0
        mulu    #255,d0
        clr.l   TV_SECS(a3)
                else
        move.l  TV_MICRO(a3),d0
        bsr.s   tm_div1000           ; d0 = ms, d1 = us (0-999)
        move.l  d1,-(sp)
        bsr.s   tm_div1000           ; d0 = extra seconds, d1 = ms (0-999)
        add.l   d0,TV_SECS(a3)
        move.l  d1,d0
        mulu    #E_PER_SEC/1000,d0   ; ms -> ticks: ms x 709.379
        mulu    #E_PER_SEC//1000,d1
        divu    #1000,d1
        and.l   #$0000FFFF,d1
        add.l   d1,d0
        move.l  (sp)+,d1
        mulu    #E_PER_SEC/1000,d1   ; us -> ticks: us x 0.709
        divu    #1000,d1
        and.l   #$0000FFFF,d1
        add.l   d1,d0
                endc
        tst.l   TV_SECS(a3)
        bne.s   .tc_set
        tst.l   d0
        bne.s   .tc_set
        moveq   #1,d0
.tc_set:
        move.l  d0,TV_MICRO(a3)
        rts

; tm_account(a2 = base, a6 = SysBase; under Disable or in the interrupt): stops CIA-A timer B, charges the time
; elapsed since it was armed to each MICROHZ request, replies to those that are due. Clobbers d0-d2/a0/a1/a3/a4.
tm_account:
        move.l  TIMER_ARMED(a2),d2
        beq.s   .ta_ret
        clr.l   TIMER_ARMED(a2)
        lea     CIAA_HW,a0
        btst    #0,CIA_CRB(a0)
        beq.s   .ta_spent            ; START dropped: the one-shot ran to the end
        bclr    #0,CIA_CRB(a0)       ; stop (counter frozen): START only, like 1.3
        moveq   #0,d0
        move.b  CIA_TBHI(a0),d0
        lsl.w   #8,d0
        move.b  CIA_TBLO(a0),d0
        cmp.l   d2,d0
        bhs.s   .ta_spent            ; counter reloaded: reached the end just before the stop
        sub.l   d0,d2                ; elapsed = armed - remaining
.ta_spent:
        lea     TIMER_MICROQ(a2),a3
        move.l  (a3),a3
.ta_loop:
        move.l  (a3),a4              ; a4 = next (0: end sentinel)
        cmpa.w  #0,a4
        beq.s   .ta_ret
        move.l  TV_MICRO(a3),d0
        sub.l   d2,d0
        bpl.s   .ta_nb
        add.l   #E_PER_SEC,d0        ; borrow of one second (elapsed < 1 s)
        subq.l  #1,TV_SECS(a3)
.ta_nb:
        move.l  d0,TV_MICRO(a3)
        tst.l   TV_SECS(a3)
        bmi.s   .ta_exp
        bne.s   .ta_next
        tst.l   d0
        bne.s   .ta_next
.ta_exp:
        move.l  a3,a1
        jsr     LVO_REMOVE(a6)
        move.l  a3,a1
        jsr     LVO_REPLYMSG(a6)     ; interrupt-safe (Disable/raw_enable, no yield)
.ta_next:
        move.l  a4,a3
        bra.s   .ta_loop
.ta_ret:
        rts

; tm_rearm(a2 = base; timer stopped by tm_account): arms the one-shot on the nearest deadline, at most
; TIMER_CAP ticks; empty queue: timer left stopped. Clobbers d0/d2/a0.
tm_rearm:
        lea     TIMER_MICROQ(a2),a0
        move.l  (a0),a0
        tst.l   (a0)
        beq.s   .tr_ret
        move.l  #TIMER_CAP,d2
.tr_loop:
        tst.l   (a0)
        beq.s   .tr_arm
        tst.l   TV_SECS(a0)
        bne.s   .tr_next             ; at least 1 s: cap
        move.l  TV_MICRO(a0),d0
        cmp.l   d2,d0
        bhs.s   .tr_next
        move.l  d0,d2
.tr_next:
        move.l  (a0),a0
        bra.s   .tr_loop
.tr_arm:
        lea     CIAA_HW,a0
        move.b  d2,CIA_TBLO(a0)
        move.w  d2,d0
        lsr.w   #8,d0
        move.b  d0,CIA_TBHI(a0)      ; one-shot: writing the high byte loads the counter
        move.b  #$19,CIA_CRB(a0)     ; START + one-shot + LOAD, E clock, ALARM = 0 (TOD in time mode)
        move.l  d2,TIMER_ARMED(a2)
.tr_ret:
        rts

; AbortIO(device a6, iorequest a1) -> d0: a request still queued (ln_Type = NT_MESSAGE and IOF_QUICK at 0) is
; removed and returned with io_Error = IOERR_ABORTED, d0 = 0; a request that is not queued is left as
; is, d0 = -1 (as in 1.3).
; (Without this removal, a request abandoned by a terminating program expired later and replied on its
; freed port, into reused memory.)
timer_abortio:
        movem.l a2/a6,-(sp)
        move.l  a1,a2
        move.l  ($4).w,a6
        jsr     LVO_DISABLE(a6)
        moveq   #-1,d0
        cmp.b   #NT_MESSAGE,LN_TYPE(a2)
        bne.s   .ab_done
        btst    #0,IO_FLAGS(a2)      ; IOF_QUICK: completed in place (DoIO), never queued -> nothing to remove
        bne.s   .ab_done
        move.l  a2,a1
        jsr     LVO_REMOVE(a6)
        move.b  #IOERR_ABORTED,IO_ERROR(a2)
        move.l  a2,a1
        jsr     LVO_REPLYMSG(a6)
        moveq   #0,d0
.ab_done:
        move.l  d0,-(sp)
        jsr     LVO_ENABLE(a6)
        move.l  (sp)+,d0
        movem.l (sp)+,a2/a6
        rts

; timer_calibrate(a2 = base, a6 = SysBase): mains frequency (timer-v34 §1.3), under Disable. TOD := 0, CIA-A timer B
; counts down from $FFFF; at a TOD tick it restarts from $FFFF and stops at the next one: 13090 E ticks or more
; (value <= $CCDD) is 50 Hz, fewer 60 Hz (PAL 14188, NTSC 11932). No tick for 32768 E ticks (TBHI below $80):
; recoverable alert, 60 Hz. Sets TIMER_TODHZ, TIMER_TODUS and ExecBase PowerSupplyFrequency. Clobbers d0/d1/a0/a1.
timer_calibrate:
        movem.l d2/d7,-(sp)
        jsr     LVO_DISABLE(a6)
        bsr     timer_todzero
        lea     CIAA_HW,a0
        move.b  #$08,CIA_CRB(a0)
        st      CIA_TBLO(a0)
        st      CIA_TBHI(a0)         ; one-shot: writing the high byte starts the countdown
        bsr.s   .cal_tick
        bne.s   .cal_60
        move.b  #$19,CIA_CRB(a0)     ; START | one-shot | LOAD: from $FFFF again
        bsr.s   .cal_tick
        bne.s   .cal_60
        move.b  #$08,CIA_CRB(a0)
        move.b  CIA_TBHI(a0),d0
        lsl.w   #8,d0
        move.b  CIA_TBLO(a0),d0
        cmp.w   #$CCDD,d0
        bhi.s   .cal_60h
        moveq   #50,d0
        move.w  #20000,d1
        bra.s   .cal_set
.cal_60:
        move.b  #$08,CIA_CRB(a0)
        move.l  #AN_TIMERNOTOD,d7
        jsr     LVO_ALERT(a6)
.cal_60h:
        moveq   #60,d0
        move.w  #16667,d1
.cal_set:
        move.w  d0,TIMER_TODHZ(a2)
        move.w  d1,TIMER_TODUS(a2)
        move.b  d0,EB_POWERFREQ(a6)
        bsr     timer_todzero
        jsr     LVO_ENABLE(a6)
        movem.l (sp)+,d2/d7
        rts
; .cal_tick(a0 = CIA-A): waits for the TOD low byte to change -> Z = 1, or Z = 0 if TBHI fell below $80 first.
.cal_tick:
        move.b  CIA_TODLO(a0),d2
.ct_lp:
        cmp.b   CIA_TODLO(a0),d2
        bne.s   .ct_ok
        cmp.b   #$80,CIA_TBHI(a0)
        bhs.s   .ct_lp
        moveq   #1,d0
        rts
.ct_ok:
        moveq   #0,d0
        rts

; initFunc (D0=base, A0=segList, A6=ExecBase) -> D0 = base. Sets the name (V34 quirk),
; NEWLISTs the VBLANK unit, registers the VBlank service.
timer_initfunc:
        move.l  d0,a1                ; a1 = base
        lea     timer_name(pc),a0
        move.l  a0,LN_NAME(a1)
        move.l  d0,-(sp)             ; save the base
        lea     TIMER_VBLQ(a1),a1    ; NEWLIST VBLANK unit queue
        jsr     newlist              ; (clobbers a0; a6 preserved)
        move.l  (sp),a1              ; reread the base (without popping)
        lea     TIMER_MICROQ(a1),a1  ; NEWLIST MICROHZ unit queue (CIA-A timer B)
        jsr     newlist
        move.l  (sp)+,d0             ; base
        move.l  d0,VBL_SVCDATA       ; data = device base (also read by timer_micro_service)
        ; M7f: timer_vblank becomes a SERVER of the VERTB chain (replaces the old VBL_SVC hook).
        ; struct Interrupt in reserved low RAM (AddIntServer Enqueues it). pri 0: after sched_server(20).
        move.b  #0,TIMER_VBL_INT+LN_PRI
        move.l  d0,TIMER_VBL_INT+IS_DATA        ; IS_DATA = device base -> passed in a1 to the service
        move.l  #timer_vblank_service,TIMER_VBL_INT+IS_CODE
        move.l  d0,-(sp)             ; save the base (AddIntServer clobbers d0/d1/a0/a1)
        moveq   #INTB_VERTB,d0       ; AddIntServer(VERTB, &TIMER_VBL_INT)
        lea     TIMER_VBL_INT,a1
        jsr     LVO_ADDINTSERVER(a6)
        move.b  #$08,CIAA_HW+CIA_CRB ; CIA-A timer B: one-shot, E clock, stopped
        move.l  a2,-(sp)
        move.l  4(sp),a2
        bsr     timer_calibrate
        move.l  (sp)+,a2
        lea     timer_cianame(pc),a1 ; MICROHZ: bit 1 (timer B) of ciaa.resource -> level 2
        jsr     LVO_OPENRESOURCE(a6)
        tst.l   d0
        beq.s   .ti_nocia
        move.l  a6,-(sp)
        move.l  d0,a6
        moveq   #1,d0
        lea     timer_micro_int(pc),a1
        jsr     CIA_ADDICRVECTOR(a6)
        move.l  (sp)+,a6
        move.l  (sp)+,d0             ; d0 = base (return value unchanged)
        rts
.ti_nocia:
        move.l  d7,-(sp)
        move.l  #AN_TIMERCIARSRC,d7  ; ciaa.resource missing: like 1.3, alert and no timer.device
        jsr     LVO_ALERT(a6)
        move.l  (sp)+,d7
        addq.l  #4,sp
        moveq   #0,d0
        rts

; timer_vblank_service(a1 = IS_DATA = device base, a6 = SysBase): M7f — SERVER of the VERTB chain
; (no longer a hook). Decrements each request of the VBLANK queue; at 0 -> Remove + ReplyMsg (M7i:
; interrupt-safe, without Permit). Server convention: preserves d2-d7/a2-a4 (movem d0-d2/a0-a4 covers
; d2/a2-a4; does NOT touch d3-d7/a5) and returns Z-SET (d0=0) = "continue the chain" (call-all).
timer_vblank_service:
        movem.l d0-d2/a0-a5,-(sp)
        move.l  a1,a2                ; a2 = device base
        tst.b   INT2_BUSY            ; recovery of a lost CIA-A interrupt: MICROHZ one-shot armed, ran to
        bne.s   .svc_vbl             ; the end (START dropped), and no level-2 interrupt in progress to serve it
        tst.l   TIMER_ARMED(a2)      ; (lost ICR event: 8520 read race, or event queue full
        beq.s   .svc_vbl             ; under FS-UAE). Otherwise CIA-A would keep its IR bit set and never request
        btst    #0,CIAA_HW+CIA_CRB   ; an interrupt again (keyboard included): we read the ICR and dispatch here.
        bne.s   .svc_vbl
        jsr     ciaa_server
.svc_vbl:
        lea     CIAA_HW,a0           ; clock fold-over (timer-v34 §4): once the TOD reaches 65536 ticks, the base takes
        tst.b   CIA_TODHI(a0)        ; the current time and TOD and counter restart from 0 (reading the high byte
        bne.s   .svc_fold            ; latches the TOD: the low byte is read to release it)
        tst.b   CIA_TODLO(a0)
        bra.s   .svc_q
.svc_fold:
        tst.b   CIA_TODLO(a0)
        bsr     timer_systime
        bsr     timer_setsys
.svc_q:
        lea     TIMER_VBLQ(a2),a4
        move.l  (a4),a3              ; a3 = lh_Head (1st request or sentinel)
.svc_loop:
        move.l  (a3),d2              ; d2 = a3->Succ; 0 => tail sentinel -> end
        beq.s   .svc_done
        subq.l  #1,TV_SECS(a3)       ; count down this tick
        bgt.s   .svc_cont            ; > 0 -> not expired yet
        move.l  a3,a1                ; expired: Remove(a3)
        jsr     LVO_REMOVE(a6)
        move.l  a3,a1                ; M7i: ReplyMsg(a3) — interrupt-safe since M7d (Disable/raw_enable,
        jsr     LVO_REPLYMSG(a6)     ; NO Permit/yield); preserves d2/a2/a4 (loop invariants)
.svc_cont:
        move.l  d2,a3                ; a3 = saved Succ (valid even after Remove)
        bra.s   .svc_loop
.svc_done:
        movem.l (sp)+,d0-d2/a0-a5
        moveq   #0,d0               ; M7f: Z-SET -> "continue the chain" (VERTB call-all server)
        rts

; M7i: timer_reply (bespoke M7c routine) REMOVED — replaced by ReplyMsg. M7d made PutMsg/GetMsg/
; ReplyMsg interrupt-safe (Disable INTENA + raw_enable, WITHOUT Permit/yield tail), so the low-level hack
; that avoided Permit's synchronous reschedule no longer has a reason to exist: the VBLANK/MICROHZ services
; call LVO_REPLYMSG directly (AddTail + Signal + NT_REPLYMSG mark, atomic, no yield in IRQ).

; timer_micro_service(a6 = SysBase; a1 = IS_DATA, unused): ICR bit 1 vector of ciaa.resource, called by
; cia_dispatch (PORTS server, level 2) at each end of one-shot of CIA-A timer B. Base read from VBL_SVCDATA.
; ICR vector convention: preserves d2/d3/a2 (loop variables of cia_dispatch).
timer_micro_service:
        movem.l d0-d2/a0-a4,-(sp)
        move.l  VBL_SVCDATA,a2
        move.l  a2,d0
        beq.s   .mic_ret             ; timer not initialised -> nothing
        bsr     tm_account
        bsr     tm_rearm
.mic_ret:
        movem.l (sp)+,d0-d2/a0-a4
        rts

; struct Interrupt of the MICROHZ unit: registered on ciaa.resource (ICR bit 1 = timer B) via AddICRVector.
; IS_CODE -> timer_micro_service. IS_DATA unused (the service reads VBL_SVCDATA).
        EVEN
timer_micro_int:
        dcb.b   14,0                ; struct Node (not linked; AddICRVector only stores the ptr)
        dc.l    0                   ; IS_DATA
        dc.l    timer_micro_service ; IS_CODE
        EVEN
timer_end:
