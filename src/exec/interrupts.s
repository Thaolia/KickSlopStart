; src/exec/interrupts.s — exec.library: interrupt plumbing + preemptive scheduler (M3a..M7b)
; + M7c: USER-MODE tasks on a shared SSP + DEFERRED switch + M7e: per-level IPL + M7f: VERTB as a chain.
;
; M7c/M7e/M7f MODEL (derived from AROS's public spec "The Exec Microkernel" + 68000 mechanics):
; - Tasks run in USER mode (SR bit S = 0), each on ITS user stack (USP). Interrupts and
;   the kernel run on ONE SHARED supervisor stack (SSP = STACKTOP region).
; - A task's context lives on ITS user stack; TC_SPREG points to it.
; - M7f: the 3 autovectors used are UNIFORM — int2_dispatch(PORTS)/int3_dispatch(VERTB)/
;   int6_dispatch(EXTER) all go through intr_dispatch_number(n) -> server chain IntVects[n].
;   The scheduling decision (round-robin quantum) is sched_server, a server of the VERTB chain.
; - Common PROLOGUE: movem.l d0-d7/a0-a6,-(sp) -> contiguous frame [GPR 60][SR 2][PC 4] = 66 bytes on the SSP.
;   M7e: the handlers run at their NATIVE IPL (int2=2, int3/vbl=3, int6=6, set by the CPU; no more
;   raising to IPL7) -> INT6 can preempt the body of vbl/int2. Common EPILOGUE (intr_exit): if a switch is
;   requested AND the SAVED SR has S=0 (we interrupted a user task = outer boundary, not a nested IRQ),
;   -> dispatch; otherwise movem+rte (resumes the interrupted code). S=1 => nested/kernel => never a switch
;   (the user context is not available): this is the NEST-COUNT, read directly from the S bit.
; - dispatch: RELOCATES the outgoing task's frame SSP -> its user stack (move usp,a0; copy 66 bytes;
;   TC_SPREG<-), then loads the incoming one (copies its frame user stack -> SSP; usp<-end; movem+rte ->
;   restarts in USER mode). Saves/restores the PER-TASK nesting (TC_IDNESTCNT/TC_TDNESTCNT <-> EB_*)
;   and synchronises INTENA. => SSP never shared between task contexts (hazard neutralised).
; - VOLUNTARY switch (user-mode): EXEC_SVC trap0_handler (Wait: outgoing already filed) / trap1_handler (yield:
;   requeue outgoing->Ready). The trap enters supervisor (user frame on SSP) and joins the common epilogue.
; - PREEMPTION: round-robin per VBlank tick (SCHED_ON && !Forbid && !Disable && TaskReady not empty).
;   DEFERRED DISPATCH FLAG (M7c): int2/int6, if a server woke up a HIGHER-PRIORITY task (Signal
;   set EB_ATTNRESCHED), request a switch at interrupt EXIT (d7<-AttnResched) instead of
;   waiting for a Permit or the next VBlank -> deterministic wake-up (without it: phase resonance).
;   Signal never RESCHEDULES from the IRQ (no re-entry): it SETS the flag, the epilogue consumes it.
; - M7a/M7e GATE: the list surgery of the switch (dispatch) is made atomic by IPL7 ("move
;   #imm,sr" = CPU internal, INSTANTANEOUS) around the Enqueue/RemHead. NOT by INTENA-off: the INTENA
;   write has a propagation delay (Amiga quirk modelled by FS-UAE) -> an already asserted INT6 overlaps
;   the window (proven, RED1). VBL_INSURG/VBL_CLASH = OVERLAP detector (INT6 overlaps the window),
;   NOT a corruption detector; the overlap is the PRECONDITION of corruption (INT6->ReplyMsg->
;   Signal Enqueues the same TaskReady the surgery is walking). M7e: VBL_INBODY/VBL_PREEMPT_COUNT prove
;   that INT6 DOES preempt the body of vbl (native IPL3) without ever overlapping the surgery (IPL7). The
;   frame relocation (SSP->user stack) runs at the native IPL without a mask: INT6 nests below sp,
;   the outgoing frame is intact.
; - HONESTY (M7d consistency): the write-delay window affects EVERY INTENA-masked section callable
;   in USER mode — Signal, PutMsg/GetMsg/ReplyMsg (M7d ports), Wait — because a user task cannot
;   raise the IPL ("move to SR" privileged, 68000 manual). They therefore keep this caveat, tolerated by the
;   re-check (Wait re-tests on wake-up) and empirically benign for the M7d ports even at max contention.
;   ONLY the supervisor-side switch was promoted to IPL7 (it can: it runs in supervisor).
; COMING (M7f): VERTB as a server chain, multi-source INTREQR decoding, quantum, RemTask.
; IMPLEMENTATION track ("clean"): hardware/intbits.i (public ABI) + HRM + public AROS spec.

                include "exec.i"
                include "dospkt.i"       ; pr_CLI / cli_CommandName (command name in SOFTWARE FAILURE)

                xdef    trap2_handler        ; tasks.s (RemTask(self), via EXEC_SVC)
                xdef    trap3_handler        ; library.s (Supervisor, via EXEC_SVC)
                xdef    init_ints
                xdef    exec_Wait
                xdef    reschedule
                xdef    dispatch_in        ; M7c: half-restore of the switch (launch of the 1st task = boot.s)
                xdef    exec_SetIntVector  ; M7b: by-number dispatcher (exclusive vector)
                xdef    exec_AddIntServer  ; M7b: by-number dispatcher (server chain)

                xref    task_freemem      ; tasks.s
                xref    alert_show        ; execmisc.s (Guru of a task's exception)
                xref    alert_deadend
                xref    alert_reboot
                xref    newlist          ; lists.s (NEWLIST of a server chain)
                xref    exec_Enqueue     ; lists.s (AddIntServer: insertion by priority)
                xref    exec_AllocMem    ; memory.s (alloc of the IntVects block at init_ints)
                xref    raw_enable       ; library.s (BARE Enable: Wait re-enables without the reschedule tail)

; init_ints: arms the VBlank interrupt + registers sched_server on the VERTB chain (M7f).
; a6 = SysBase. Clobbers d0/d1/a0/a1 (via AllocMem + AddIntServer).
init_ints:
        lea     VBL_COUNT,a0
        clr.l   (a0)                              ; counter to zero
        clr.b   SCHED_ON                          ; scheduler disarmed (count-only)
        clr.l   CIAA_PTR                          ; M6b: CIA handlers no-op as long as cia not created
        clr.l   CIAB_PTR
        clr.l   CIA_FIRED
        clr.b   VBL_INSURG                        ; M7a: no surgery in progress at start
        clr.l   VBL_CLASH                         ; M7a: re-entry clash counter
        clr.b   VBL_INBODY                        ; M7e: vbl body not yet entered
        clr.b   VBL_IPL                           ; M7e: observed IPL (filled in by vbl)
        clr.l   VBL_PREEMPT_COUNT                 ; M7e: preemptions of the vbl body by INT6
        clr.l   IDLE_ENTERED                      ; M7e: idle episodes of the dispatcher
        clr.l   VERTB_CHAIN_N                     ; M7f: complete walks of the VERTB chain
        clr.b   M7F_STAT                          ; M7f: "M7F VERTB OK" marker not yet emitted
        lea     EB_INTVECTS(a6),a0                ; public IntVects[]: no handler at start
        moveq   #INTVECTS_NVEC*IV_SIZE/4-1,d0
.ii_clr:
        clr.l   (a0)+
        dbra    d0,.ii_clr
        move.l  #INTSVL_TOTAL,d0                  ; M7b: server lists (AddIntServer)
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)                  ; (preserves a6)
        move.l  d0,EB_INTSVL(a6)
        move.l  #int3_dispatch,AUTOVEC_L3         ; M7f: VERTB (INT3) -> generic by-number dispatcher
        move.l  #int2_dispatch,AUTOVEC_L2         ; M7b: INT2/PORTS -> generic by-number dispatcher
        move.l  #int6_dispatch,AUTOVEC_L6         ; M7b: INT6/EXTER -> generic by-number dispatcher
        move.l  #int1_dispatch,AUTOVEC_L1         ; TBE / DSKBLK / SOFTINT (serial.device loaded from DEVS:)
        move.l  #int4_dispatch,AUTOVEC_L4         ; AUD0..AUD3
        move.l  #int5_dispatch,AUTOVEC_L5         ; RBF / DSKSYNC
        bsr     init_traps                        ; CPU exceptions + TRAP #4-15 -> the task's tc_TrapCode
        ; M7f: registers the SCHEDULER server (round-robin quantum) on the VERTB chain. Faithful:
        ; the real exec has a VBlank server that sets the AttnResched flag. pri 20 -> head of chain.
        clr.l   SCHED_INT+LN_SUCC                 ; (reserved low RAM, not guaranteed zero at power-on)
        clr.l   SCHED_INT+IS_DATA                 ; scheduler server: IS_DATA unused (reads the globals)
        move.b  #20,SCHED_INT+LN_PRI              ; pri 20: runs before timer_vblank(0)/vbl_tail(-10)
        move.l  #sched_server,SCHED_INT+IS_CODE
        moveq   #INTB_VERTB,d0                    ; AddIntServer(VERTB, &SCHED_INT)
        lea     SCHED_INT,a1
        bsr     exec_AddIntServer
        move.w  #INTF_VERTB,INTREQ                ; clears a pending VERTB
        ; enables VERTB + PORTS (INT2) + master. EXTER(INT6, level 6 > VBlank 3) is enabled
        ; LATER, at the bringup of the MICROHZ unit (boot.s M7a): it now preempts the BODY of
        ; int3_dispatch (VERTB chain, native IPL 3), but the switch's list surgery stays atomic
        ; because the switch's critical section (dispatch) briefly raises IPL7. It is left off as long as no
        ; CIA-B source exists -> M4..M6 remain unchanged.
        move.w  #(INTF_SETCLR|INTF_INTEN|INTF_VERTB|INTF_PORTS),INTENA
        move.w  #$2000,sr                         ; supervisor, IPL=0 -> interrupts get through
        rts

; int3_dispatch (AUTOVEC_L3, level 3): M7f — VERTB (only level 3 source used, single-source
; like int2/int6) goes through the BY-NUMBER dispatcher + server chain, instead of a dedicated handler.
; Body = M7g MULTI-SOURCE DECODING: reads INTREQR & INTENAR, dispatches+acks EACH pending level 3
; source (COPER bit4, VERTB bit5, BLIT bit6) via IntVects[n], instead of assuming VERTB only.
; VERTB -> M3a counter + chain (sched/timer/tail). Epilogue = intr_isr_defer (consumes AttnResched).
; VBL_INBODY (M7e gate) covers the whole body (preemptible by INT6). Bonus: on a SPURIOUS INT3 (ack
; propagation delay, cf. M7e) the 3 btst fail -> we dispatch NOTHING (more correct than M7f which
; dispatched VERTB unconditionally). d2 = mask of the pending sources, PRESERVED by the server
; convention (walker: movem d2/a2-a4; coper_test: only touches COPER_FIRED) across the dispatches.
int3_dispatch:
                ifne    M7E_PROLOGUE_IPL7
        move.w  #$2700,sr           ; RED2 M7e: M7a model (whole handler at IPL7) -> INT6 does NOT preempt
                                    ; the body -> VBL_PREEMPT_COUNT==0 -> "M7E IPL OK" never emitted.
                endc
        movem.l d0-d7/a0-a6,-(sp)   ; M7e PROLOGUE: NATIVE IPL (level 3) — INT6 (6) can preempt THIS body
        move.l  ($4).w,a6           ; a6 = SysBase
        st      VBL_INBODY          ; M7e: preemptible window = level 3 decoding+dispatch (INT6 detector)
        move.w  sr,d0               ; M7e value-check: native IPL observed (must == 3, not 7; "move from
        lsr.w   #8,d0               ; SR" not privileged on 68000, supervisor here)
        and.w   #7,d0
        move.b  d0,VBL_IPL
        move.w  INTREQR,d2          ; M7g: pending sources ...
        and.w   INTENAR,d2          ; ... AND enabled (d2 preserved across the dispatches)
        btst    #INTB_VERTB,d2      ; --- VERTB (bit 5) ---
        beq.s   .i3_coper
        move.w  #INTF_VERTB,INTREQ  ; ack VERTB (SETCLR=0 -> clears this bit only)
        addq.l  #1,VBL_COUNT        ; M3a counter (ONLY if VERTB really pending)
        moveq   #INTB_VERTB,d0
        bsr     intr_dispatch_number ; VERTB chain (sched + timer_vblank + vbl_tail)
        move.l  ($4).w,a6           ; reload a6 (the walker does not restore it)
.i3_coper:
        btst    #INTB_COPER,d2      ; --- COPER (bit 4) ---
        beq.s   .i3_blit
        move.w  #INTF_COPER,INTREQ  ; ack COPER (always, even in RED -> no storm)
                ifeq    M7G_MONO_SOURCE
        moveq   #INTB_COPER,d0
        bsr     intr_dispatch_number ; dispatch IntVects[COPER] (= coper_test in demo)
        move.l  ($4).w,a6
                endc                ; RED M7G_MONO_SOURCE=1: acked but NOT dispatched -> COPER_FIRED frozen
.i3_blit:
        btst    #INTB_BLIT,d2       ; --- BLIT (bit 6; not used in demo -> dormant) ---
        beq.s   .i3_done
        move.w  #INTF_BLIT,INTREQ   ; ack BLIT
                ifeq    M7G_MONO_SOURCE
        moveq   #INTB_BLIT,d0
        bsr     intr_dispatch_number ; dispatch IntVects[BLIT]
        move.l  ($4).w,a6
                endc
.i3_done:
        clr.b   VBL_INBODY          ; M7e: end of the window before dispatch (disjoint from VBL_INSURG)
        bra     intr_isr_defer      ; common tail: reloads a6 + deferred dispatch if AttnResched (S=0)

; sched_server: VERTB server of the SCHEDULER (round-robin quantum). Sets EB_ATTNRESCHED when a
; preemption is due — SCHED_ON && !Forbid && !Disable && TaskReady not empty (same guards as the old
; vbl_handler: round-robin RESPECTS Forbid/Disable). Faithful: the real exec has a VBlank server that
; sets the AttnResched flag; intr_isr_defer consumes it at IRQ exit (like an INT6 wake-up).
; Server convention: a6=SysBase (re-supplied by the walker), a1=IS_DATA (free), preserves d2-d7/a2-a4;
; returns Z-SET (d0=0) = "continue the chain" (call-all server).
sched_server:
        tst.b   SCHED_ON
        beq.s   .sched_cont         ; scheduler not armed -> request nothing (M3a/count-only)
        tst.b   EB_TDNEST(a6)       ; Forbid() active? (INVOLUNTARY preemption respected)
        bge.s   .sched_cont
        tst.b   EB_IDNEST(a6)       ; Disable() active?
        bge.s   .sched_cont
        move.l  EB_TASKREADY(a6),a1 ; TaskReady not empty? (a1 = IS_DATA, free) M7e: torn read possible
        tst.l   (a1)                ; vs an AddTail from INT6 -> benign (spurious/missed request; RemHead protected)
        beq.s   .sched_cont
        ; M7h: QUANTUM — only preempts after M7H_QUANTUM ticks of time slice (not every tick).
        addq.b  #1,QUANTUM_ELAPSED  ; +1 tick for the current task
        cmp.b   #M7H_QUANTUM,QUANTUM_ELAPSED
        bcs.s   .sched_cont         ; ELAPSED < QUANTUM -> the time slice continues (no reschedule)
        clr.b   QUANTUM_ELAPSED     ; quantum elapsed -> reset + request a deferred reschedule (round-robin)
        addq.l  #1,QUANTUM_EXPIRE_N ; throughput proof (~= VBL_COUNT/QUANTUM in isolation; ~=0 in the default demo)
        move.w  #1,EB_ATTNRESCHED(a6) ; consumed by intr_isr_defer (at IRQ exit)
.sched_cont:
                ifne    M7F_SCHED_STOPS_CHAIN
        moveq   #1,d0               ; RED2 M7f: Z-CLEAR -> the walker STOPS the chain after sched
                else
        moveq   #0,d0               ; Z-SET -> continue the chain (call-all: timer_vblank + vbl_tail after)
                endc
        rts

; intr_exit: common EPILOGUE (vbl/int2/int6/trap). d7 = switch requested. We switch ONLY at the
; USER BOUNDARY: S bit of the SAVED SR (FRAME_SR) == 0. S=1 (nested IRQ / kernel) => user context
; unavailable => simple resume. This is the nest-count, read directly from the S bit. a6=SysBase.
intr_exit:
        tst.b   d7
        beq.s   .ie_noswitch
        move.w  FRAME_SR(sp),d0     ; SR saved on the SSP
        and.w   #$2000,d0           ; S bit (supervisor)?
        bne.s   .ie_noswitch        ; S=1 -> nested -> no switch (resume the interrupted code)
        bra     dispatch            ; user boundary -> relocate + switch (does not return here)
.ie_noswitch:
        movem.l (sp)+,d0-d7/a0-a6
        rte

; dispatch: RELOCATES the outgoing task's frame (SSP -> its user stack) then loads the incoming one. Entry:
; sp = 66-byte frame on the SSP; a6=SysBase; d6=1 -> requeue the outgoing task into TaskReady (round-robin),
; d6=0 -> outgoing already filed (Wait on TaskWait). M7e: relocation at the caller's native IPL,
; then surgery masked by a brief IPL7. Does not return (rte to the incoming one, at the IPL/S of the restored SR).
dispatch:
        move.l  EB_THISTASK(a6),a1  ; outgoing
        move.b  EB_IDNEST(a6),TC_IDNESTCNT(a1)  ; PER-TASK nesting: save the state of the outgoing task
        move.b  EB_TDNEST(a6),TC_TDNESTCNT(a1)
        move.l  usp,a0              ; a0 = outgoing USP (privileged, OK in supervisor)
        lea     -FRAME_SIZE(a0),a3  ; dest = outgoing user stack - 66
        move.l  a3,TC_SPREG(a1)     ; outgoing TC_SPREG = base of the relocated frame
        move.l  sp,a2               ; src = frame on the SSP (disjoint stacks -> ascending copy safe)
        moveq   #(FRAME_SIZE/2)-1,d0
.d_save:
        move.w  (a2)+,(a3)+         ; relocate 66 bytes SSP -> user stack (33 words, no long straddling SR)
        dbf     d0,.d_save          ; (relocation SAFE at native IPL: INT6 nests BELOW sp, frame intact)
        ; M7e: mask the surgery with IPL7 (SR write = CPU internal, INSTANTANEOUS). NOT INTENA-off:
        ; the INTENA write has a PROPAGATION DELAY (Amiga quirk modelled by FS-UAE) -> an INT6 already
        ; asserted on the IPL lines overlaps the VBL_INSURG window = clash (proven empirically, RED1).
        ; WHY the IPL here but INTENA elsewhere (Signal/ports/Wait): the surgery runs in SUPERVISOR
        ; (reached via intr_exit/trap) -> "move #imm,sr" LEGAL. Signal/PutMsg/GetMsg/Wait are callable
        ; from a USER-MODE task where "move to SR" is PRIVILEGED (68000 manual) -> impossible to raise
        ; the IPL -> they must use INTENA-Disable, which therefore carries the write-delay caveat (cf. header).
                ifne    M7E_SURGERY_INTENA
        move.w  #INTF_INTEN,INTENA  ; RED1: mask by INTENA-off (propagation delay) -> clash observed
                else
        move.w  #$2700,sr           ; GREEN: mask by IPL7 (instantaneous)
                endc
        move.b  #1,VBL_INSURG       ; list surgery (Enqueue/RemHead) = contended section (M7a detector)
        tst.b   d6
        beq.s   .d_pick             ; outgoing already filed (Wait) -> no requeue
        move.b  #TS_READY,TC_STATE(a1)
        lea     EB_TASKREADY(a6),a0
        jsr     LVO_ENQUEUE(a6)     ; round-robin: requeue the outgoing task (a1 preserved)
        clr.w   EB_ATTNRESCHED(a6)  ; a switch satisfies any reschedule request
.d_pick:
        lea     EB_TASKREADY(a6),a0
        jsr     LVO_REMHEAD(a6)     ; d0 = incoming | 0
        tst.l   d0
        bne.s   .d_have
        addq.l  #1,IDLE_ENTERED     ; M7e: instrumentation (idle episode; must be > 0 in a normal run)
.d_idle:                            ; nobody ready (Wait with no other ready task): wait for a Signal
        clr.b   VBL_INSURG          ; idle wait -> no surgery in progress (no false clash)
        move.w  #(INTF_SETCLR|INTF_INTEN),INTENA ; M7e: re-enable INTEN to receive the waking Signal
                                    ; (the Wait->idle path arrives INTEN-off from exec_Wait -> necessary)
        move.w  #$2000,sr           ; supervisor IPL0 -> every IRQ gets through (nested frame, S=1 -> no dispatch)
        nop
        move.w  #$2700,sr           ; IPL7: masks the RemHead surgery (instantaneous, cf. non-idle)
        move.b  #1,VBL_INSURG
        lea     EB_TASKREADY(a6),a0
        jsr     LVO_REMHEAD(a6)
        tst.l   d0
        beq.s   .d_idle
.d_have:
        move.l  d0,a1               ; incoming
        clr.b   VBL_INSURG          ; surgery finished (RemHead done)
        ; falls through into dispatch_in

; dispatch_in: half-restore — loads the incoming task (a1) and rte's in USER mode. Also used by the
; LAUNCH of the 1st task (boot.s), which performs the supervisor->user transition. sp = 66-byte SSP slot.
dispatch_in:
        cmp.l   EB_THISTASK(a6),a1  ; M7h: REAL task change (incoming != outgoing)?
        beq.s   .di_samequantum
        clr.b   QUANTUM_ELAPSED     ; yes -> new time slice (no reset on dispatch-to-self)
.di_samequantum:
        move.l  a1,EB_THISTASK(a6)
        move.b  #TS_RUN,TC_STATE(a1)
        move.b  TC_IDNESTCNT(a1),EB_IDNEST(a6)  ; restore the incoming task's nesting
        move.b  TC_TDNESTCNT(a1),EB_TDNEST(a6)
        tst.b   EB_IDNEST(a6)
        bge.s   .di_dis             ; incoming Disabled -> INTEN off
        move.w  #(INTF_SETCLR|INTF_INTEN),INTENA  ; incoming permitted -> INTEN on (touches ONLY bit14)
        bra.s   .di_copy
.di_dis:
        move.w  #INTF_INTEN,INTENA  ; clear INTEN (bit14; without SETCLR = clears)
.di_copy:
        move.l  TC_SPREG(a1),a2     ; src = frame of the incoming task (its user stack)
        move.l  sp,a3               ; dest = SSP slot (overwrites the location of the outgoing frame)
        moveq   #(FRAME_SIZE/2)-1,d0
.di_loop:
        move.w  (a2)+,(a3)+
        dbf     d0,.di_loop
        move.l  TC_SPREG(a1),a2
        lea     FRAME_SIZE(a2),a2   ; incoming USP = after its restored frame
        move.l  a2,usp
        movem.l (sp)+,d0-d7/a0-a6   ; pop the incoming task's GPRs
        rte                         ; pops {SR,PC} -> restarts in USER mode (saved SR S=0) on its USP

; exec_Wait(signalSet d0.l) -> d0 = received signals. Blocks ThisTask (USER mode) until reception.
; Critical section via BARE Disable (INTENA, user-safe); blocking via EXEC_SVC (enters supervisor ->
; dispatch relocates). On wake-up (re-dispatched after the trap), re-tests (robust to spurious wake-ups).
; BARE exit (raw_enable): the woken task is already running -> no yield (preserves the M3d semantics).
exec_Wait:
        addq.b  #1,EB_IDNEST(a6)    ; BARE Disable: critical section vs scheduler
        move.w  #INTF_INTEN,INTENA  ; INTEN off (bit14)
        move.l  EB_THISTASK(a6),a1
        move.l  d0,TC_SIGWAIT(a1)
.wa_check:
        move.l  TC_SIGRECVD(a1),d0
        and.l   TC_SIGWAIT(a1),d0
        bne.s   .wa_got             ; an awaited signal is present -> no blocking
        move.b  #TS_WAIT,TC_STATE(a1)
        lea     EB_TASKWAIT(a6),a0
        jsr     LVO_ADDTAIL(a6)     ; ThisTask (a1) -> TaskWait (a1 preserved)
        EXEC_SVC trap0_handler      ; -> supervisor -> dispatch (outgoing already on TaskWait, d6=0)
        move.l  EB_THISTASK(a6),a1  ; re-dispatched: a6/a1 restored by the switch (defensive reload)
        bra.s   .wa_check           ; re-test (spurious -> block again)
.wa_got:
        eor.l   d0,TC_SIGRECVD(a1)  ; clear the waking bits (d0 subset of SIGRECVD)
        clr.l   TC_SIGWAIT(a1)
        bsr     raw_enable          ; INTEN on if IDNest<0 (BARE exit, no reschedule tail)
        rts

; reschedule: voluntary synchronous YIELD (yield-on-Permit, M3e). Called by Permit/Enable (USER mode,
; permitted & enabled, AttnResched set). EXEC_SVC trap1_handler -> dispatch requeues the current task (d6=1) +
; switches to the higher-priority woken task. On return (re-dispatched), rts to Permit/Enable.
reschedule:
        tst.w   EB_ATTNRESCHED(a6)  ; still requested? (a tick may have consumed it)
        beq.s   .rs_none
        move.l  EB_TASKREADY(a6),a0
        tst.l   (a0)                ; a ready task available? (defensive)
        beq.s   .rs_none
        EXEC_SVC trap1_handler      ; yield: dispatch requeues self->Ready + RemHead
        rts                         ; re-dispatched -> return to Permit/Enable
.rs_none:
        clr.w   EB_ATTNRESCHED(a6)
        rts

; trap0_handler (EXEC_SVC): voluntary Wait-style switch — the outgoing task is ALREADY filed (TaskWait).
; trap1_handler (EXEC_SVC): yield — dispatch requeues the outgoing task into TaskReady (round-robin).
; From a task, the {user SR, PC} frame comes from the privilege violation -> the saved SR has S=0 -> epilogue
; dispatch guaranteed.
; M7e: no more raising to IPL7 — the trap enters at the task's IPL (0); the atomicity of the switch relies
; ENTIRELY on dispatch's Disable. trap0 (Wait) arrives already Disabled (exec_Wait did INTEN-off
; before EXEC_SVC) -> idempotent Disable. trap1 (yield) arrives INTEN-on -> fresh but correct Disable.
trap0_handler:
        movem.l d0-d7/a0-a6,-(sp)
        move.l  ($4).w,a6
        moveq   #1,d7
        moveq   #0,d6               ; do NOT requeue (outgoing on TaskWait)
        bra     intr_exit
trap1_handler:
        movem.l d0-d7/a0-a6,-(sp)
        move.l  ($4).w,a6
        moveq   #1,d7
        moveq   #1,d6               ; requeue outgoing -> TaskReady
        bra     intr_exit

; trap3_handler (EXEC_SVC): exec Supervisor — NOT a task switch. The {SR, PC} frame is on the SSP and we
; are in supervisor. We jump directly to the user routine (a5), which runs in supervisor
; and ends with RTE: the RTE pops {SR,PC} -> resumes in exec_Supervisor in user mode. We touch
; no context (the called code is responsible for preserving the trap's SSP frame, Supervisor contract).
trap3_handler:
        jmp     (a5)

; priv_handler (vector $20): privilege violation. An EXEC_SVC site of the ROM ("ori.w #0,sr", SVC_MAGIC, service
; address) goes on to its service, with the pushed PC advanced past the site; any other violation follows the
; exception path (tc_TrapCode).
priv_handler:
        move.l  a0,-(sp)
        move.l  6(sp),a0             ; faulting PC
        cmp.l   #ROM_BASE,a0
        blo.s   .pv_exc
        cmp.w   #$007C,(a0)          ; ori.w #imm,sr
        bne.s   .pv_exc
        tst.w   2(a0)
        bne.s   .pv_exc
        cmp.w   #SVC_MAGIC,4(a0)
        bne.s   .pv_exc
        move.l  6(a0),-(sp)          ; service
        lea     10(a0),a0
        move.l  a0,10(sp)            ; resume after the site
        move.l  4(sp),a0
        move.l  (sp)+,(sp)           ; [service][SR][PC]
        rts
.pv_exc:
        move.l  (sp)+,a0
        bra     exc_table+2*(8-TRAPVEC_FIRST)

; trap2_handler (EXEC_SVC): M7j — RemTask(self). The outgoing task REMOVES itself: we do NOT save its context
; (it is discarded). In supervisor, on the SSP -> the outgoing task's user stack is no longer used = freeable.
; External Forbid (FreeMem's internal Permit does not yield) + IPL7 (masks IRQs during the teardown).
; Clear EB_THISTASK BEFORE freeing tc_MemEntry (dispatch_in reads EB_THISTASK). Then switch like the launch of
; the 1st task (RemHead + dispatch_in). DOES NOT RETURN.
trap2_handler:
        move.w  #$2700,sr           ; IPL7 (supervisor -> legal): masks IRQs during the teardown
        move.l  ($4).w,a6           ; SysBase
        jsr     LVO_FORBID(a6)      ; external Forbid -> FreeMem.Permit sees TDNEST>=0 -> no yield
        move.l  EB_THISTASK(a6),a1  ; outgoing task to free
        clr.l   EB_THISTASK(a6)     ; BEFORE the freeing: dispatch_in compares EB_THISTASK (QUANTUM_ELAPSED)
                ifeq    M7J_NOFREE
        jsr     task_freemem        ; tc_MemEntry (TCB and stack included if they are in it) — safe: we run on the SSP
                endc
        move.l  #STACKTOP,sp        ; final switch: clean SSP + 66-byte slot (like boot.s)
        lea     -FRAME_SIZE(sp),sp
.t2_pick:
        lea     EB_TASKREADY(a6),a0
        jsr     LVO_REMHEAD(a6)
        tst.l   d0
        bne.s   .t2_have
        move.w  #(INTF_SETCLR|INTF_INTEN),INTENA ; no ready task -> idle (IRQ Signal; not reached
        move.w  #$2000,sr           ; in demo: other tasks are ready). IPL0 -> IRQ gets through (S=1 -> no
        nop                         ; nested dispatch), IPL7, re-RemHead.
        move.w  #$2700,sr
        bra.s   .t2_pick
.t2_have:
        move.l  d0,a1
        bra     dispatch_in         ; load the incoming task + rte (per-task IPL/INTEN/nesting restored)

; ============================ by-number dispatcher (M7b) ==========
; SetIntVector/AddIntServer + generic INT2(PORTS)/INT6(EXTER) autovectors + chain walker.
; M7e: BY-NUMBER dispatch (IntVects[n] lookup + server chain) AT THE NATIVE IPL — int2 runs at
; IPL2, int6 at IPL6 (no more raising to IPL7). INT6 can therefore preempt int2 and the body of vbl. The
; scheduler's atomicity no longer comes from the IPL but from the Disable (INTEN off) around the surgery in dispatch.
; M7c: int2/int6 share the prologue (movem) and the epilogue (intr_exit). DEFERRED DISPATCH
; FLAG (AROS spec "The Exec Microkernel"): if a server woke up a HIGHER-PRIORITY task (Signal
; set EB_ATTNRESCHED), the epilogue dispatches IMMEDIATELY at interrupt exit (at the user
; boundary S=0) instead of waiting for a Permit/Enable or the next VBlank. Without it, a task woken by an
; IRQ depends on the phase lottery (which task is running + calls Permit) -> erratic wake-up (resonance).
; Signal never RESCHEDULES itself from the interrupt (no re-entry): it SETS the flag,
; the epilogue consumes it. M7f: VERTB ALSO goes through this dispatcher (int3_dispatch -> VERTB chain:
; sched_server + timer_vblank + vbl_tail) -> UNIFORM model PORTS(int2)/VERTB(int3)/EXTER(int6).

; int2_dispatch ($68, level 2): only level 2 source = PORTS -> dispatches IntVects[INTB_PORTS].
int2_dispatch:
        movem.l d0-d7/a0-a6,-(sp)   ; M7e PROLOGUE: NATIVE IPL (level 2) — preemptible by vbl(3)/int6(6)
        move.l  ($4).w,a6
        move.w  #INTF_PORTS,INTREQ  ; ack Paula INT2 BEFORE the chain: a CIA event occurring during the service
        moveq   #INTB_PORTS,d0      ; (MICROHZ one-shot re-armed short, keyboard) re-sets PORTS instead of being cleared
        st      INT2_BUSY
        bsr     intr_dispatch_number
        clr.b   INT2_BUSY
        bra.s   intr_isr_defer
; int1/int4/int5_dispatch (autovectors $64/$70/$74): multiple sources with an EXCLUSIVE vector (SetIntVector). For each
; pending AND enabled source of the level: handler present -> call (it acknowledges INTREQ itself, RKRM "Exec:
; Interrupts"); no handler -> acknowledged here (no storm). Level 1 = TBE(0)/DSKBLK(1)/SOFTINT(2), level 4 =
; AUD0..3(7-10), level 5 = RBF(11)/DSKSYNC(12). trackdisk and the serial console poll DSKBLK/RBF with INTENA off:
; these sources do not come through here.
int1_dispatch:
        movem.l d0-d7/a0-a6,-(sp)
        move.w  #INTM_L1,d3
        bra.s   intr_multi
int4_dispatch:
        movem.l d0-d7/a0-a6,-(sp)
        move.w  #INTM_L4,d3
        bra.s   intr_multi
int5_dispatch:
        movem.l d0-d7/a0-a6,-(sp)
        move.w  #INTM_L5,d3
intr_multi:
        move.l  ($4).w,a6
        move.w  INTREQR,d2
        and.w   INTENAR,d2
        and.w   d3,d2                ; d2 = sources of the level to serve
        moveq   #0,d4                ; d4 = source number
.im_lp:
        btst    d4,d2
        beq.s   .im_next
        lea     EB_INTVECTS(a6),a0
        move.w  d4,d0
        mulu    #IV_SIZE,d0
        tst.l   IV_CODE(a0,d0.l)
        bne.s   .im_call
        moveq   #0,d0                ; no handler: acknowledge
        bset    d4,d0
        move.w  d0,INTREQ
        bra.s   .im_next
.im_call:
        move.l  d4,d0
        bsr     intr_dispatch_number
        move.l  ($4).w,a6
.im_next:
        addq.w  #1,d4
        cmp.w   #13,d4
        bcs.s   .im_lp
        bra     intr_isr_defer

; int6_dispatch ($78, level 6): only level 6 source = EXTER -> dispatches IntVects[INTB_EXTER].
int6_dispatch:
        movem.l d0-d7/a0-a6,-(sp)   ; M7e PROLOGUE: NATIVE IPL (level 6) — highest level used, never preempted
        move.l  ($4).w,a6
        move.w  #INTF_EXTER,INTREQ  ; ack Paula INT6 BEFORE the chain (same reason as PORTS)
        moveq   #INTB_EXTER,d0
        bsr     intr_dispatch_number
; intr_isr_defer: common int2/int3/int6 tail — deferred dispatch flag (EB_ATTNRESCHED).
intr_isr_defer:
        move.l  ($4).w,a6           ; M7f: RELOADS a6=SysBase — the walker does NOT restore a6 after the
                                    ; last server, which may have clobbered it (convention preserves d2-d7/a2-a4
                                    ; only). Without this, the EB_* reads below would read garbage.
        moveq   #1,d6               ; round-robin: requeue the interrupted task if we dispatch
        moveq   #0,d7
                ifeq    SCHED_NO_FORBID_GATE
        tst.b   EB_TDNEST(a6)       ; Forbid() active? -> deferred dispatch SUPPRESSED at the CONSUMPTION point:
        bge.s   intr_isr_exit       ;   AttnResched may have been set BEFORE the Forbid (stale quantum) or by
        tst.b   EB_IDNEST(a6)       ;   Signal() of a higher-priority task DURING the Forbid -> do NOT switch here.
        bge.s   intr_isr_exit       ; Disable() active? -> same (critical section vs scheduler). AttnResched stays
                                    ;   pending -> consumed at the next non-forbidden IRQ exit, or by the voluntary
                                    ;   yield of Permit/Enable (EXEC_SVC, not guarded). Same guards as sched_server.
                endc                ; RED SCHED_NO_FORBID_GATE: guards removed -> switch even under Forbid (orig. bug:
                                    ;   a serial printer under Forbid got preempted -> interleaved markers).
        tst.w   EB_ATTNRESCHED(a6)  ; did a server wake up a higher-priority task?
        beq.s   intr_isr_exit
        moveq   #1,d7               ; deferred dispatch flag -> switch on exit (if S=0)
intr_isr_exit:
        bra     intr_exit

; intr_dispatch_number(d0.l = number; a6 = SysBase): calls the handler of IntVects[n]. Exclusive
; vector (SetIntVector) -> direct call; chain (AddIntServer) -> IV_CODE = intr_chain_walker.
; Convention (AutoDoc): a0=$DFF000, a1=IS_DATA (or &svlist), a5=IS_CODE (or walker), a6=SysBase.
intr_dispatch_number:
        lea     EB_INTVECTS(a6),a1
        mulu    #IV_SIZE,d0         ; n * IV_SIZE(12)
        add.l   d0,a1               ; a1 = &IntVects[n]
        move.l  IV_CODE(a1),a5
        move.l  a5,d1
        beq.s   .idn_ret            ; no handler for this number
        move.l  IV_DATA(a1),a1      ; a1 = IS_DATA (or &svlist)
        lea     CUSTOM,a0           ; a0 = $DFF000 (server convention)
        jsr     (a5)
.idn_ret:
        rts

; intr_chain_walker(a1 = &svlist, a0=$DFF000, a6=SysBase): walks the chain by priority (head = highest
; pri, set by Enqueue). Calls each server until Z clear (!=0 = "handled, stop"); Z set
; (==0) = continue (AutoDoc AddIntServer; "call-all" servers like VERTB return Z set).
; a2/a3 = walk, a4 = stashed SysBase — preserved by the servers (convention d2-d7/a2-a4).
intr_chain_walker:
        movem.l d2/a2-a4,-(sp)
        move.l  a6,a4               ; stash SysBase (a4 preserved by the servers)
        move.l  (a1),a2             ; a2 = lh_Head (1st node)
.cw_loop:
        move.l  (a2),d2             ; d2 = node->Succ (DATA register -> sets the flags;
        beq.s   .cw_done            ; MOVEA to Ax would NOT affect the CCs -> wrong beq). 0 => tail.
        movea.l d2,a3               ; a3 = Succ (preserved by the servers: d2-d7/a2-a4)
        move.l  IS_DATA(a2),a1      ; a1 = IS_DATA of the server
        move.l  IS_CODE(a2),a5
        lea     CUSTOM,a0           ; re-supply a0=$DFF000 (a server may have clobbered it)
        move.l  a4,a6               ; re-supply a6=SysBase
        jsr     (a5)
        bne.s   .cw_done            ; Z clear -> server "handled" it -> stop the chain
        movea.l a3,a2               ; next node
        bra.s   .cw_loop
.cw_done:
        movem.l (sp)+,d2/a2-a4
        rts

; SetIntVector(intNum d0, interrupt a1) -> d0 = old Interrupt | 0. EXCLUSIVE vector: copies IS_DATA/IS_CODE
; into IntVects[n], iv_Node = the Interrupt (a1=NULL -> clears). Masked: an interrupt must not see a
; half-written entry. a6=SysBase.
exec_SetIntVector:
        lea     EB_INTVECTS(a6),a0
        mulu    #IV_SIZE,d0
        add.l   d0,a0               ; a0 = &IntVects[n]
        move.w  #INTF_INTEN,INTENA
        move.l  IV_NODE(a0),d0      ; old Interrupt
        move.l  a1,IV_NODE(a0)
        move.l  a1,d1
        beq.s   .siv_null
        move.l  IS_DATA(a1),IV_DATA(a0)
        move.l  IS_CODE(a1),IV_CODE(a0)
        bra.s   .siv_ret
.siv_null:
        clr.l   IV_DATA(a0)
        clr.l   IV_CODE(a0)
.siv_ret:
        tst.b   EB_IDNEST(a6)       ; under Disable: do not restore INTEN
        bge.s   .siv_x
        move.w  #INTF_SETCLR|INTF_INTEN,INTENA
.siv_x:
        rts

; AddIntServer(intNum d0, interrupt a1) -> void. Adds the server to the chain of the number, sorted by
; LN_PRI. 1st server: NEWLISTs the svlist, sets IV_DATA=&svlist / IV_CODE=intr_chain_walker. a6=SysBase.
exec_AddIntServer:
        movem.l d2/a2/a3,-(sp)
        move.l  a1,a2               ; a2 = interrupt (preserved by newlist/Enqueue)
        move.l  EB_INTSVL(a6),a3    ; a3 = block of the server lists
        move.l  a3,d1
        beq.s   .ais_ret            ; block missing (defensive)
        move.l  d0,d2               ; d2 = number
        move.w  d2,d1               ; &IntVects[n] = ExecBase + EB_INTVECTS + n*12
        mulu    #IV_SIZE,d1
        lea     EB_INTVECTS(a6,d1.l),a0
        cmp.l   #intr_chain_walker,IV_CODE(a0)
        beq.s   .ais_enq            ; already a chain
        move.w  d2,d1               ; 1st server: &svlist[n] = block + n*14
        mulu    #IV_LIST_SIZE,d1
        lea     0(a3,d1.l),a1       ; a1 = &svlist[n]
        move.l  a0,-(sp)            ; save &IntVects[n]
        move.l  a1,-(sp)            ; save &svlist[n]
        jsr     newlist             ; NEWLIST(a1) (clobbers a0)
        move.l  (sp)+,a1
        move.l  (sp)+,a0
        move.l  a1,IV_DATA(a0)
        move.l  #intr_chain_walker,IV_CODE(a0)
        clr.l   IV_NODE(a0)
.ais_enq:
        move.w  d2,d1               ; &svlist[n] (robust to both paths)
        mulu    #IV_LIST_SIZE,d1
        lea     0(a3,d1.l),a0       ; a0 = &svlist[n]
        move.l  a2,a1               ; a1 = interrupt
        jsr     LVO_ENQUEUE(a6)     ; inserts by LN_PRI (head = highest pri)
.ais_ret:
        movem.l (sp)+,d2/a2/a3
        rts

; --- CPU exceptions (exec model, RKRM "Traps") ---------------------------------------------------------------
; Each vector (bus/address error, illegal, divide by zero, CHK, TRAPV, privilege, trace, line-A, line-F,
; TRAP #4-#15) pushes the trap number (LONG) above the exception frame then jumps, in supervisor and with registers
; intact, to ThisTask's tc_TrapCode (0 -> ExecBase.TaskTrapCode). Without a handler, an exception made
; the CPU jump to an arbitrary address and froze the whole machine.
TRAPVEC_FIRST   EQU 2                ; bus error
TRAPVEC_CPULAST EQU 11               ; line-F
TRAPVEC_T0      EQU 32               ; TRAP #0
TRAPVEC_T15     EQU 47               ; TRAP #15
init_traps:
        move.l  #exc_default,EB_TASKTRAPCODE(a6)
        moveq   #TRAPVEC_FIRST,d0
.it_cpu:
        bsr.s   .it_set
        cmp.w   #TRAPVEC_CPULAST,d0
        bls.s   .it_cpu
        moveq   #TRAPVEC_T0,d0
.it_trap:
        bsr.s   .it_set
        cmp.w   #TRAPVEC_T15,d0
        bls.s   .it_trap
        move.l  #priv_handler,PRIV_VEC   ; after the loop (which sets vector 8): EXEC_SVC entries
        rts
.it_set:                             ; vector d0 -> exc_table + 2*(d0-2); advance d0
        moveq   #0,d1
        move.w  d0,d1
        lsl.w   #2,d1
        move.l  d1,a1                ; a1 = address of the vector
        move.w  d0,d1
        subq.w  #TRAPVEC_FIRST,d1
        add.w   d1,d1
        lea     exc_table(pc),a0
        add.w   d1,a0
        move.l  a0,(a1)
        addq.w  #1,d0
        rts

; Form IMPOSED by the clients (SetPatch 1.3x): vector n points to a "bsr.s exc_entry" of exc_table
; (2 bytes per vector, vectors 2..47). exc_entry brings the return address back to 2*n by a 6-byte
; subtraction, then "lsr.w 2(sp)" gives n. SetPatch reads vector $14, derives exc_entry+6 from it, checks the
; word $E2EF (lsr.w d16(a7)) there — otherwise it crashes on purpose — and makes its own FPU stubs (vectors 48-63)
; jump there with 2*n on the stack. Do not change the sizes: subi.l = 6 bytes, lsr.w 2(sp) = $E2EF $0002.
exc_table:
                rept    TRAPVEC_T15-TRAPVEC_FIRST+1
        bsr.s   exc_entry
                endr
        dc.w    0                    ; separator: a bsr.s with a zero displacement would encode a bsr.w (never executed)
exc_entry:
        subi.l  #exc_table-2,(sp)    ; return address of entry n -> 2*n
        lsr.w   2(sp)                ; -> n = trap number (LONG at (sp))

; exc_common: (sp) = trap number. Jumps to the task's handler without touching a single register.
exc_common:
        subq.l  #4,sp                ; slot for the target address
        move.l  a0,-(sp)
        move.l  ($4).w,a0
        move.l  EB_THISTASK(a0),a0
        move.l  TC_TRAPCODE(a0),a0
        move.l  a0,4(sp)
        bne.s   .ec_go
        move.l  ($4).w,a0
        move.l  EB_TASKTRAPCODE(a0),4(sp)
.ec_go:
        move.l  (sp)+,a0
        rts                          ; -> handler, stack = [trap number][frame]

; exc_default: default handler. Emits "SOFTWARE FAILURE trap=XXXX pc=XXXXXXXX task=<name>" on the serial port
; (equivalent of the real OS's Software Failure requester) then PUTS THE TASK ON HOLD: the frame is rewritten so
; that the RTE resumes in user mode in exc_hold (Wait(0) forever); the other tasks continue. An
; exception occurring in supervisor mode (interrupt, Supervisor) is unrecoverable: message then halt.
exc_default:
        movem.l d0-d2/a0-a1,-(sp)
        move.w  #SERPER_9600_PAL,SERPER  ; a program may have changed the port speed: readable message
        lea     exc_msg1(pc),a0
        bsr     exc_puts
        move.l  20(sp),d1            ; trap number
        move.l  d1,d0
        bsr     exc_puthex
        lea     24(sp),a1            ; a1 = frame
        cmp.l   #3,d1
        bhi.s   .ed_short
        addq.l  #8,a1                ; bus/address error: 8 more bytes before SR/PC (68000)
.ed_short:
        lea     exc_msg2(pc),a0
        bsr     exc_puts
        move.l  2(a1),d0             ; pushed PC
        swap    d0
        bsr     exc_puthex
        swap    d0
        bsr     exc_puthex
        cmp.l   #3,d1
        bhi.s   .ed_nofault
        lea     exc_msg4(pc),a0      ; bus/address error: faulting access address
        bsr     exc_puts
        move.l  24+2(sp),d0
        swap    d0
        bsr     exc_puthex
        swap    d0
        bsr     exc_puthex
.ed_nofault:
        lea     exc_msg5(pc),a0      ; code words around the PC (to locate the instruction)
        bsr     exc_puts
        move.l  2(a1),d0
        and.l   #$FFFFFE,d0          ; even PC, 24 bits
        move.l  d0,a0
        subq.l  #8,a0
        moveq   #7,d2
.ed_code:
        move.w  (a0)+,d0
        bsr     exc_puthex
        dbra    d2,.ed_code
        lea     exc_msg3(pc),a0
        bsr     exc_puts
        move.l  ($4).w,a0
        move.l  EB_THISTASK(a0),a0
        move.l  LN_NAME(a0),d0
        beq.s   .ed_noname
        move.l  d0,a0
        bsr     exc_puts
.ed_noname:
        move.l  ($4).w,a0            ; CLI process: name of the current command (cli_CommandName)
        move.l  EB_THISTASK(a0),a0
        cmp.b   #NT_PROCESS,LN_TYPE(a0)
        bne.s   .ed_nocmd
        move.l  PR_CLI(a0),d0
        lsl.l   #2,d0
        beq.s   .ed_nocmd
        move.l  d0,a0
        move.l  CLI_COMMANDNAME(a0),d0
        lsl.l   #2,d0
        beq.s   .ed_nocmd
        move.l  d0,a0
        moveq   #0,d2
        move.b  (a0)+,d2             ; BSTR length
        beq.s   .ed_nocmd
        move.l  a0,-(sp)
        lea     exc_msg6(pc),a0
        bsr     exc_puts
        move.l  (sp)+,a0
        subq.w  #1,d2
.ed_cmd:
        move.b  (a0)+,d0
        bsr     exc_putc
        dbra    d2,.ed_cmd
.ed_nocmd:
        lea     exc_msg7(pc),a0      ; a6 (probable library base) and (usp) (return of the last jsr)
        bsr     exc_puts
        move.l  a6,d0
        swap    d0
        bsr     exc_puthex
        swap    d0
        bsr     exc_puthex
        lea     exc_msg8(pc),a0
        bsr     exc_puts
        move.l  usp,a0
        move.l  a0,d0
        bsr     .ed_hex32            ; usp
        move.l  (a0),d0
        swap    d0
        bsr     exc_puthex
        swap    d0
        bsr     exc_puthex
        lea     exc_msg9(pc),a0      ; BCPL registers: a1 = frame, a2 = GV, a4 = current routine
        bsr     exc_puts
        move.l  16(sp),d0            ; a1 saved by the entry movem
        bsr.s   .ed_hex32
        move.l  a2,d0
        bsr.s   .ed_hex32
        move.l  a4,d0
        bsr.s   .ed_hex32
        lea     exc_crlf(pc),a0
        bsr     exc_puts
        btst    #5,(a1)              ; S bit of the pushed SR (high byte of the SR word)
        bne     .ed_fatal
        move.l  20(sp),d0            ; "Software Failure" Guru: #<vector number>.<task> (spec alert-v34 §3)
        move.l  ($4).w,a0
        move.l  EB_THISTASK(a0),d1
        move.l  a1,-(sp)
        jsr     alert_show
        move.l  (sp)+,a1
        cmp.l   #1,d0                ; left button: reboot (like 1.3); right: the task is suspended
        bne.s   .ed_hold
        jmp     alert_reboot
.ed_hold:
        clr.w   (a1)                 ; resume in user mode, IPL 0
        move.l  #exc_hold,2(a1)
        movem.l (sp)+,d0-d2/a0-a1
        cmp.l   #3,(sp)
        bhi.s   .ed_pop
        addq.l  #8,sp                ; bus/address error: also removes the 8 extra bytes of the frame
.ed_pop:
        addq.l  #4,sp                ; remove the trap number -> stack = [SR][PC]
        rte
.ed_hex32:
        swap    d0
        bsr     exc_puthex
        swap    d0
        bsr     exc_puthex
        moveq   #' ',d0
        bra     exc_putc
.ed_fatal:                           ; exception in supervisor: dead-end alert (reset, Guru at the next boot)
        move.l  20(sp),d0
        move.l  ($4).w,a0
        move.l  EB_THISTASK(a0),d1
        jmp     alert_deadend

; exc_hold: resume point (user mode) of a faulting task: sleeps forever.
exc_hold:
        move.l  ($4).w,a6
.eh_lp:
        moveq   #0,d0
        jsr     LVO_WAIT(a6)
        bra.s   .eh_lp

; exc_puts(a0) / exc_puthex(d0.w): RAW serial output (TBE polling), without Forbid/Permit — usable from
; an exception context. Clobber d0 (puthex preserves d0), a0.
exc_puts:
        move.b  (a0)+,d0
        beq.s   .xp_ret
        bsr.s   exc_putc
        bra.s   exc_puts
.xp_ret:
        rts
exc_puthex:
        movem.l d0-d2,-(sp)
        move.w  d0,d2
        moveq   #3,d1
.xh_lp:
        rol.w   #4,d2
        move.w  d2,d0
        and.w   #$000F,d0
        add.b   #'0',d0
        cmp.b   #'9',d0
        bls.s   .xh_out
        addq.b  #7,d0
.xh_out:
        bsr.s   exc_putc
        dbra    d1,.xh_lp
        movem.l (sp)+,d0-d2
        rts
exc_putc:
        move.l  d1,-(sp)
        move.w  #$2000,d1
.xc_wt:
        btst    #5,SERDATR           ; TBE = bit 13 of the word = bit 5 of the high byte
        bne.s   .xc_tx
        dbra    d1,.xc_wt
.xc_tx:
        and.w   #$00FF,d0
        or.w    #$0100,d0
        move.w  d0,SERDAT
        move.l  (sp)+,d1
        rts
exc_msg1:
        dc.b    13,10,"SOFTWARE FAILURE trap=",0
exc_msg2:
        dc.b    " pc=",0
exc_msg3:
        dc.b    " task=",0
exc_msg4:
        dc.b    " addr=",0
exc_msg5:
        dc.b    " code(pc-8)=",0
exc_msg6:
        dc.b    " cmd=",0
exc_msg7:
        dc.b    " a6=",0
exc_msg8:
        dc.b    " usp/(usp)=",0
exc_msg9:
        dc.b    " a1/a2/a4=",0
exc_crlf:
        dc.b    13,10,0
        even
