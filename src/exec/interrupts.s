; src/exec/interrupts.s — exec.library: interrupt plumbing + preemptive scheduler (M3a..M7b)
; + M7c: USER-MODE tasks on a shared SSP + DEFERRED switch + M7e: per-level IPL + M7f: VERTB as a chain.
;
; M7c/M7e/M7f MODEL (derived from AROS's public spec "The Exec Microkernel" + 68000 mechanics):
; - Tasks run in USER mode (SR bit S = 0), each on ITS user stack (USP). Interrupts and
;   the kernel run on ONE SHARED supervisor stack (SSP = STACKTOP region).
; - A task's context lives on ITS user stack; TC_SPREG points to it, in the V34 layout PC, SR, D0-D7, A0-A6
;   (exec-scheduling-v34 §4.1: task monitors read it).
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
; - Scheduling LVOs (exec-scheduling-v34 §2): Wait switches through the Switch vector (-54); Permit/Enable/
;   Reschedule go to Schedule (-42) through its vector; the interrupt exit joins the body of Schedule, which
;   decides (>= priority rule, TQE, pending exception) and continues through the Switch vector; RemTask(self)
;   goes through Dispatch (-60). SAR/TQE are the SysFlags bits.
; - PREEMPTION: round-robin per VBlank tick (SCHED_ON && !Forbid && !Disable && TaskReady not empty).
;   DEFERRED DISPATCH FLAG (M7c): int2/int6, if a server woke up a HIGHER-PRIORITY task (Signal
;   set SAR), request a schedule check at interrupt EXIT (d7<-SAR) instead of
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
                xdef    exec_Schedule      ; scheduling LVOs (library.s jump table; the others: execmisc.s)
                xdef    exec_Switch
                xdef    exec_Dispatch
                xref    svc_schedule       ; execmisc.s (EXEC_SVC services of the scheduling entries)
                xref    svc_switch
                xdef    exec_SetIntVector  ; M7b: by-number dispatcher (exclusive vector)
                xdef    exec_AddIntServer  ; M7b: by-number dispatcher (server chain)
                xdef    intr_chain_walker  ; execmisc.s (RemIntServer)

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
        ; the real exec has a VBlank server that requests a reschedule. pri 20 -> head of chain.
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
; VERTB -> M3a counter + chain (sched/timer/tail). Epilogue = intr_isr_defer (consumes SAR).
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
        bra     intr_isr_defer      ; common tail: reloads a6 + deferred schedule check if SAR (S=0)

; sched_server: VERTB server of the SCHEDULER (round-robin quantum). Sets TQE and SAR when a
; preemption is due — SCHED_ON && !Forbid && !Disable && TaskReady not empty (same guards as the old
; vbl_handler: round-robin RESPECTS Forbid/Disable). Faithful: the real exec has a VBlank server that
; requests a reschedule; intr_isr_defer consumes SAR at IRQ exit (like an INT6 wake-up).
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
        bset    #SFB_TQE,EB_SYSFLAGS(a6) ; quantum elapsed ...
        bset    #SFB_SAR,EB_SYSFLAGS(a6) ; ... and a schedule check at IRQ exit (intr_isr_defer -> Schedule)
.sched_cont:
                ifne    M7F_SCHED_STOPS_CHAIN
        moveq   #1,d0               ; RED2 M7f: Z-CLEAR -> the walker STOPS the chain after sched
                else
        moveq   #0,d0               ; Z-SET -> continue the chain (call-all: timer_vblank + vbl_tail after)
                endc
        rts

; intr_exit: common EPILOGUE (int1-6). d7 = schedule check requested. We schedule ONLY at the USER BOUNDARY: S bit
; of the SAVED SR (FRAME_SR) == 0. S=1 (nested IRQ / kernel) => simple resume. This plays the part of ExitIntr
; (exec-scheduling-v34 §2.6) on our 60-byte frame: it joins the body of Schedule with the registers already saved.
intr_exit:
        tst.b   d7
        beq.s   .ie_noswitch
        move.w  FRAME_SR(sp),d0     ; SR saved on the SSP
        and.w   #$2000,d0           ; S bit (supervisor)?
        bne.s   .ie_noswitch        ; S=1 -> nested -> resume the interrupted code
        move.w  #$2000,sr           ; IPL 0, as ExitIntr before Schedule
        bra     schedule_body
.ie_noswitch:
        movem.l (sp)+,d0-d7/a0-a6
        rte

; ============================ scheduling LVOs (exec-scheduling-v34 §2) ============================
; Every switch-out goes through the Switch vector (-54): Wait (svc_switch), and preemption (Schedule, reached
; from Reschedule/Permit/Enable through its vector and from the interrupt exit directly). RemTask(self) goes
; through the Dispatch vector (-60). A SetFunction on these vectors therefore sees what the 1.3 one sees.

; Schedule (-42): supervisor, {SR, PC} of the code to resume on the SSP, registers = that code's. Clears SAR; the
; running task loses the CPU when it has an exception pending, or the head of TaskReady has a priority >= its
; own, or (head lower) the quantum has elapsed (TQE). Then it is enqueued READY and the switch goes through the
; Switch vector with only the exception frame left on the SSP. Otherwise the code resumes.
exec_Schedule:
        movem.l d0-d7/a0-a6,-(sp)
schedule_body:                      ; entry with the 60-byte frame already pushed (intr_exit)
        move.l  ($4).w,a6
        move.w  #$2700,sr
        bclr    #SFB_SAR,EB_SYSFLAGS(a6)
        move.l  EB_THISTASK(a6),a1
        btst    #TB_EXCEPT,TC_FLAGS(a1)
        bne.s   .sc_switch
        move.l  EB_TASKREADY(a6),a0
        tst.l   (a0)
        beq.s   .sc_stay            ; nobody ready
        move.b  LN_PRI(a0),d0
        cmp.b   LN_PRI(a1),d0
        bge.s   .sc_switch          ; head >= running: equal priority preempts too
        btst    #SFB_TQE,EB_SYSFLAGS(a6)
        bne.s   .sc_switch
.sc_stay:
        movem.l (sp)+,d0-d7/a0-a6
        rte
.sc_switch:
        move.b  #TS_READY,TC_STATE(a1)
        lea     EB_TASKREADY(a6),a0
        jsr     LVO_ENQUEUE(a6)     ; behind the ready tasks of its own priority (round-robin)
        move.w  #$2000,sr
        movem.l (sp)+,d0-d7/a0-a6
        move.l  ($4).w,-(sp)        ; jump through the vector, frame and registers untouched
        add.l   #LVO_SWITCH,(sp)
        rts

; Switch (-54): supervisor; {SR, PC} of the outgoing task on the SSP, D0-D7/A0-A6 = its registers, USP = its stack;
; ThisTask already filed (TaskReady or TaskWait) with its state set. Never returns.
exec_Switch:
        movem.l d0-d7/a0-a6,-(sp)
        move.l  ($4).w,a6
; dispatch: saves the outgoing context (66-byte frame on the SSP -> its user stack in the §4.1 layout), its nest
; counts, calls tc_Switch, then dispatches the head of TaskReady (idle STOP while nobody is ready). M7e: the
; context copy runs at the caller's IPL (a nested interrupt lands below sp, the frame stays intact); the list
; surgery is masked by IPL7 (instantaneous, unlike INTENA whose write has a propagation delay). Does not return.
dispatch:
        move.l  EB_THISTASK(a6),a1  ; outgoing
        move.w  EB_IDNEST(a6),TC_IDNESTCNT(a1) ; IDNestCnt/TDNestCnt pair -> the task
        move.l  usp,a0
        lea     -FRAME_SIZE(a0),a3
        move.l  a3,TC_SPREG(a1)
        move.l  FRAME_SR+2(sp),(a3)+ ; PC
        move.w  FRAME_SR(sp),(a3)+  ; SR
        move.l  sp,a2
        moveq   #14,d0
.d_save:
        move.l  (a2)+,(a3)+         ; D0-D7/A0-A6 (word-aligned longs: legal on 68000)
        dbf     d0,.d_save
        move.w  #-1,EB_IDNEST(a6)   ; both counts -1 between tasks, INTEN on
        move.w  #(INTF_SETCLR|INTF_INTEN),INTENA
        btst    #TB_SWITCH,TC_FLAGS(a1)
        beq.s   .d_surg
        move.l  a1,a3               ; tc_Switch: A3 = task, A6 = ExecBase, supervisor IPL 0, JSR
        move.l  TC_SWITCH(a3),a0
        move.w  #$2000,sr
        jsr     (a0)
        move.l  ($4).w,a6
.d_surg:
                ifne    M7E_SURGERY_INTENA
        move.w  #INTF_INTEN,INTENA  ; RED1: mask by INTENA-off (propagation delay) -> clash observed
                else
        move.w  #$2700,sr           ; GREEN: mask by IPL7 (instantaneous)
                endc
        move.b  #1,VBL_INSURG       ; list surgery (RemHead) = contended section (M7a detector)
dispatch_pick:                      ; IPL7, a6 = ExecBase, sp = 66-byte slot
        lea     EB_TASKREADY(a6),a0
        jsr     LVO_REMHEAD(a6)     ; d0 = incoming | 0
        tst.l   d0
        bne.s   .d_have
        addq.l  #1,IDLE_ENTERED     ; M7e: instrumentation (idle episode; must be > 0 in a normal run)
.d_idle:                            ; nobody ready: sleep until an interrupt readies a task
        clr.b   VBL_INSURG
        addq.l  #1,EB_IDLECOUNT(a6)
        bset    #SFB_SAR,EB_SYSFLAGS(a6)
        move.w  #(INTF_SETCLR|INTF_INTEN),INTENA
        stop    #$2000              ; supervisor IPL 0 (nested frame, S=1 -> no dispatch from the interrupt)
        move.w  #$2700,sr
        move.b  #1,VBL_INSURG
        lea     EB_TASKREADY(a6),a0
        jsr     LVO_REMHEAD(a6)
        tst.l   d0
        beq.s   .d_idle
.d_have:
        move.l  d0,a1               ; incoming
        clr.b   VBL_INSURG          ; surgery finished (RemHead done)
        ; falls through into dispatch_in

; dispatch_in: loads the incoming task (a1) and rte's to it. Also used by the launch of the 1st task (boot.s).
; sp = 66-byte SSP slot. Order (§2.5): ThisTask, DispCount, TQE cleared, RUN, nest counts, tc_Launch, exception.
dispatch_in:
        cmp.l   EB_THISTASK(a6),a1  ; M7h: REAL task change (incoming != outgoing)?
        beq.s   .di_samequantum
        clr.b   QUANTUM_ELAPSED     ; yes -> new time slice (no reset on dispatch-to-self)
.di_samequantum:
        move.l  a1,EB_THISTASK(a6)
        addq.l  #1,EB_DISPCOUNT(a6)
        bclr    #SFB_TQE,EB_SYSFLAGS(a6)
        move.b  #TS_RUN,TC_STATE(a1)
        bsr.s   di_nest
        move.b  TC_FLAGS(a1),d0
        and.b   #(1<<TB_LAUNCH)|(1<<TB_EXCEPT),d0
        bne.s   di_hooks
; di_restore: context at tc_SPReg (a1) -> SSP slot (movem layout) then rte. USP = tc_SPReg + 66.
di_restore:
        move.l  TC_SPREG(a1),a2
        move.l  (a2)+,d1            ; PC
        move.w  (a2)+,d2            ; SR
        move.l  sp,a3
        moveq   #14,d0
.dr_lp:
        move.l  (a2)+,(a3)+
        dbf     d0,.dr_lp
        move.w  d2,(a3)+
        move.l  d1,(a3)
        move.l  a2,usp
        movem.l (sp)+,d0-d7/a0-a6
        rte

; di_nest: ExecBase nest counts := the task's (a1); INTEN follows IDNestCnt.
di_nest:
        move.w  TC_IDNESTCNT(a1),EB_IDNEST(a6)
        tst.b   EB_IDNEST(a6)
        bge.s   .dn_dis
        move.w  #(INTF_SETCLR|INTF_INTEN),INTENA
        rts
.dn_dis:
        move.w  #INTF_INTEN,INTENA
        rts

; di_hooks: supervisor IPL 0. tc_Launch (A3 = task, A6 = ExecBase, D0 = tc_Flags), then the exception step (§5):
; TB_EXCEPT cleared; sigs = SigRecvd & SigExcept removed from both; tc_Flags..tc_TDNestCnt (one long) and the
; return address exc_return pushed below the saved context; ExecBase IDNestCnt exactly 0 -> -1 + INTEN on;
; tc_ExceptCode entered in USER mode (SR 0) with D0 = sigs, A1 = tc_ExceptData, A6 = ExecBase.
di_hooks:
        move.w  #$2000,sr
        btst    #TB_LAUNCH,TC_FLAGS(a1)
        beq.s   .dh_exc
        move.l  a1,-(sp)
        move.l  a1,a3
        moveq   #0,d0
        move.b  TC_FLAGS(a3),d0
        move.l  TC_LAUNCH(a3),a0
        jsr     (a0)
        move.l  (sp)+,a1
        move.l  ($4).w,a6
.dh_exc:
        bclr    #TB_EXCEPT,TC_FLAGS(a1)
        beq.s   di_restore
        move.w  #$2700,sr           ; Signal from an interrupt also updates these masks
        move.l  TC_SIGRECVD(a1),d0
        and.l   TC_SIGEXCEPT(a1),d0
        move.l  d0,d1
        not.l   d1
        and.l   d1,TC_SIGRECVD(a1)
        and.l   d1,TC_SIGEXCEPT(a1)
        move.w  #$2000,sr
        move.l  TC_SPREG(a1),a2
        move.l  TC_FLAGS(a1),-(a2)
        move.l  #exc_return,-(a2)
        move.l  a2,usp
        tst.b   EB_IDNEST(a6)
        bne.s   .dh_go
        st      EB_IDNEST(a6)
        move.w  #(INTF_SETCLR|INTF_INTEN),INTENA
.dh_go:
        lea     FRAME_SIZE(sp),sp   ; drop the slot: the SSP is back at its base
        move.l  TC_EXCEPTCODE(a1),-(sp)
        clr.w   -(sp)
        move.l  TC_EXCEPTDATA(a1),a1
        rte

; exc_return: where tc_ExceptCode returns (user mode), D0 = signals to re-arm in tc_SigExcept. USP points at the
; saved tc_Flags long, right below the context.
exc_return:
        EXEC_SVC exc_resume
; exc_resume (supervisor, the 6-byte frame of exc_return on the SSP): re-arms, restores tc_Flags..tc_TDNestCnt,
; tc_SPReg back to the context, ExecBase nest counts from the task, resumes the context.
exc_resume:
        addq.l  #6,sp
        move.w  #$2700,sr
        move.l  ($4).w,a6
        move.l  EB_THISTASK(a6),a1
        or.l    d0,TC_SIGEXCEPT(a1)
        move.l  usp,a2
        move.l  (a2)+,TC_FLAGS(a1)
        move.l  a2,TC_SPREG(a1)
        lea     -FRAME_SIZE(sp),sp
        bsr     di_nest
        bra     di_restore

; Dispatch (-60): supervisor, nothing to save (RemTask of the running task). Nest counts -1/-1, INTEN on, then the
; dispatcher loop. sp = where the dispatched context's frame slot goes.
exec_Dispatch:
        move.w  #$2700,sr
        move.l  ($4).w,a6
        move.w  #-1,EB_IDNEST(a6)
        move.w  #(INTF_SETCLR|INTF_INTEN),INTENA
        lea     -FRAME_SIZE(sp),sp
        move.b  #1,VBL_INSURG
        bra     dispatch_pick

; exec_Wait(signalSet d0.l) -> d0 = received signals. Blocks ThisTask (USER mode) until reception.
; Critical section via BARE Disable (INTENA, user-safe); blocking via EXEC_SVC svc_switch (Switch vector, outgoing
; already on TaskWait). Forbid is not tested: the nest counts are saved per task. On wake-up, re-tests (an
; exception signal alone wakes it without satisfying the mask). BARE exit (raw_enable).
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
        EXEC_SVC svc_switch
        move.l  EB_THISTASK(a6),a1  ; re-dispatched: a6/a1 restored by the switch (defensive reload)
        bra.s   .wa_check           ; re-test (spurious -> block again)
.wa_got:
        eor.l   d0,TC_SIGRECVD(a1)  ; clear the waking bits (d0 subset of SIGRECVD)
        clr.l   TC_SIGWAIT(a1)
        bsr     raw_enable          ; INTEN on if IDNest<0 (BARE exit, no reschedule tail)
        rts

; reschedule: yield of Permit/Enable (permitted & enabled, SAR set): Schedule through its vector when a task is
; ready (from supervisor mode svc_schedule returns at once). Clobbers a0.
reschedule:
        btst    #SFB_SAR,EB_SYSFLAGS(a6)
        beq.s   .rs_none
        move.l  EB_TASKREADY(a6),a0
        tst.l   (a0)                ; a ready task available?
        beq.s   .rs_clr
        EXEC_SVC svc_schedule
.rs_none:
        rts
.rs_clr:
        bclr    #SFB_SAR,EB_SYSFLAGS(a6)
        rts

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

; trap2_handler (EXEC_SVC): RemTask(self). The outgoing task REMOVES itself: its context is not saved (it is
; discarded). In supervisor, on the SSP -> the outgoing task's user stack is no longer used = freeable.
; External Forbid (FreeMem's internal Permit does not yield) + IPL7 (masks IRQs during the teardown).
; Clear EB_THISTASK BEFORE freeing tc_MemEntry (dispatch_in reads EB_THISTASK). Then a clean SSP and the Dispatch
; vector (tc_Switch is not called). DOES NOT RETURN.
trap2_handler:
        move.w  #$2700,sr           ; IPL7 (supervisor -> legal): masks IRQs during the teardown
        move.l  ($4).w,a6           ; SysBase
        jsr     LVO_FORBID(a6)      ; external Forbid -> FreeMem.Permit sees TDNEST>=0 -> no yield
        move.l  EB_THISTASK(a6),a1  ; outgoing task to free
        clr.l   EB_THISTASK(a6)     ; BEFORE the freeing: dispatch_in compares EB_THISTASK (QUANTUM_ELAPSED)
                ifeq    M7J_NOFREE
        jsr     task_freemem        ; tc_MemEntry (TCB and stack included if they are in it) — safe: we run on the SSP
                endc
        move.l  #STACKTOP,sp        ; clean SSP (like boot.s)
        jmp     LVO_DISPATCH(a6)

; ============================ by-number dispatcher (M7b) ==========
; SetIntVector/AddIntServer + generic INT2(PORTS)/INT6(EXTER) autovectors + chain walker.
; M7e: BY-NUMBER dispatch (IntVects[n] lookup + server chain) AT THE NATIVE IPL — int2 runs at
; IPL2, int6 at IPL6 (no more raising to IPL7). INT6 can therefore preempt int2 and the body of vbl. The
; scheduler's atomicity no longer comes from the IPL but from the Disable (INTEN off) around the surgery in dispatch.
; M7c: int2/int6 share the prologue (movem) and the epilogue (intr_exit). DEFERRED DISPATCH
; FLAG (AROS spec "The Exec Microkernel"): if a server woke up a HIGHER-PRIORITY task (Signal
; set SAR), the epilogue schedules IMMEDIATELY at interrupt exit (at the user
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
; intr_isr_defer: common interrupt tail — deferred schedule check (SAR).
intr_isr_defer:
        move.l  ($4).w,a6           ; M7f: RELOADS a6=SysBase — the walker does NOT restore a6 after the
                                    ; last server, which may have clobbered it (convention preserves d2-d7/a2-a4
                                    ; only). Without this, the EB_* reads below would read garbage.
        moveq   #0,d7
                ifeq    SCHED_NO_FORBID_GATE
        tst.b   EB_TDNEST(a6)       ; Forbid() active? -> deferred dispatch SUPPRESSED at the CONSUMPTION point:
        bge.s   intr_isr_exit       ;   SAR may have been set BEFORE the Forbid (stale quantum) or by
        tst.b   EB_IDNEST(a6)       ;   Signal() of a higher-priority task DURING the Forbid -> do NOT switch here.
        bge.s   intr_isr_exit       ; Disable() active? -> same (critical section vs scheduler). SAR stays
                                    ;   pending -> consumed at the next non-forbidden IRQ exit, or by the voluntary
                                    ;   yield of Permit/Enable (EXEC_SVC, not guarded). Same guards as sched_server.
                endc                ; RED SCHED_NO_FORBID_GATE: guards removed -> switch even under Forbid (orig. bug:
                                    ;   a serial printer under Forbid got preempted -> interleaved markers).
        btst    #SFB_SAR,EB_SYSFLAGS(a6) ; reschedule pending (Signal of a higher-priority task, quantum, idle)?
        beq.s   intr_isr_exit
        moveq   #1,d7               ; deferred dispatch flag -> Schedule on exit (if S=0)
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
; Then enables the chain's source in INTENA, as the 1.3 exec does at every add (custom-chips-v34 §3.1): software
; that adds a COPER server counts on it. Masked: the chain may be walked by its interrupt meanwhile.
exec_AddIntServer:
        movem.l d2/a2/a3,-(sp)
        move.l  a1,a2               ; a2 = interrupt (preserved by newlist/Enqueue)
        move.l  EB_INTSVL(a6),a3    ; a3 = block of the server lists
        move.l  a3,d1
        beq.s   .ais_ret            ; block missing (defensive)
        move.w  #INTF_INTEN,INTENA
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
        move.w  #INTF_SETCLR,d1
        bset    d2,d1
        move.w  d1,INTENA
        tst.b   EB_IDNEST(a6)       ; under Disable: do not restore INTEN
        bge.s   .ais_ret
        move.w  #INTF_SETCLR|INTF_INTEN,INTENA
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
        move.w  #SERPER_RAW,SERPER   ; a program may have changed the port speed: readable message
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
