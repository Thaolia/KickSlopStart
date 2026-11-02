; src/exec/tasks.s — exec.library: tasks + signals, NON-BLOCKING PART (M2.4b).
;   init_task   : creates the "boot task" TCB (ThisTask) from the heap.
;   FindTask    : NULL -> current task; otherwise search in TaskReady/TaskWait.
;   AllocSignal/FreeSignal/SetSignal: management of ThisTask's signal bits.
;   Signal      : sets the bits in TC_SIGRECVD + WAKES the task if TS_WAIT (M3d) +
;                 requests a reschedule if the woken task has priority (M3e, SAR).
;   SetTaskPri  : changes LN_PRI (re-Enqueue + Reschedule), returns the old one.
; M3b: AddTask (initial context + TaskReady). M3d: wake-on-Signal (here) + Wait/
;   WaitPort (interrupts.s / ports.s), RemTask. Switch/Dispatch and the other scheduling LVOs: interrupts.s.
; Amiga convention: scratch = d0/d1/a0/a1; a6 = library base.
; IMPLEMENTATION track ("clean"): NDK includes exec/tasks.i (public ABI).

                include "exec.i"

                xdef    init_task
                xdef    exec_AddTask
                xdef    exec_RemTask
                xdef    task_alloc        ; task + stack described in tc_MemEntry (dos proc_create, demos)
                xdef    task_freemem      ; freeing of tc_MemEntry (trap2_handler)
                xdef    task_excpending   ; execmisc.s (SetExcept)
                xref    trap2_handler     ; interrupts.s (RemTask(self) via EXEC_SVC)
                xdef    exec_FindTask
                xdef    exec_AllocSignal
                xdef    exec_FreeSignal
                xdef    exec_SetSignal
                xdef    exec_Signal
                xdef    exec_SetTaskPri

                xref    raw_enable       ; library.s (M7c: Signal = BARE critical section)

; init_task: allocates the TCB of the boot task and publishes it in ThisTask.
; Called by coldstart AFTER init_memory (AllocMem available) and BEFORE selftest
; (otherwise AllocSignal would dereference a NULL ThisTask -> write into the
; exception vectors $0-$3FF). a6 = SysBase.
init_task:
        move.l  #TC_SIZE,d0
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  d0,a0                ; TCB (assumed non-NULL at boot)
        move.b  #NT_TASK,LN_TYPE(a0)
        move.b  #0,LN_PRI(a0)
        move.l  #task_name,LN_NAME(a0)
        move.b  #TS_RUN,TC_STATE(a0)
        move.b  #-1,TC_IDNESTCNT(a0) ; per-task copies (save/restore at the M3 switch)
        move.b  #-1,TC_TDNESTCNT(a0)
        move.l  #SYS_SIGALLOC,TC_SIGALLOC(a0)
        move.l  #SSP_LOWER,TC_SPLOWER(a0)  ; supervisor stack bounds (informative)
        move.l  #STACKTOP,TC_SPUPPER(a0)
        move.l  a0,EB_THISTASK(a6)
        rts

; AddTask(task a1, initialPC a2, finalPC a3): prepares the initial context and puts the task into
; TaskReady. M7c: USER-MODE tasks (initial SR $0000, S bit = 0) on their user stack. Fields as in
; exec-scheduling-v34 §4.2: tc_Flags 0, nest counts -1/-1 (permitted & enabled), SigWait/SigRecvd/SigExcept 0,
; tc_TrapCode / tc_ExceptCode defaulted from ExecBase when 0, finalPC 0 -> ExecBase TaskExitCode. Context in the
; §4.1 layout, all registers 0: [PC=initialPC][SR=$0000][d0-d7/a0-a6 = 0][finalPC]; TC_SPREG -> the PC; USP at 1st entry = TC_SPREG+FRAME_SIZE
; -> points to finalPC (return if the task does RTS). Built from TC_SPUPPER (our callers set SPLOWER/UPPER only).
exec_AddTask:
        tst.b   LN_TYPE(a1)          ; ln_Type is set by the caller (CreateProc -> NT_PROCESS): do NOT overwrite it
        bne.s   .at_typed            ; (programs test NT_PROCESS to know whether they may call dos)
        move.b  #NT_TASK,LN_TYPE(a1)
.at_typed:
        clr.b   TC_FLAGS(a1)         ; no stale TB_SWITCH/TB_LAUNCH/TB_EXCEPT from uncleared memory
        move.b  #TS_READY,TC_STATE(a1)
        move.b  #-1,TC_IDNESTCNT(a1) ; per-task nesting: enabled
        move.b  #-1,TC_TDNESTCNT(a1) ; permitted
        clr.l   TC_SIGWAIT(a1)
        clr.l   TC_SIGRECVD(a1)
        clr.l   TC_SIGEXCEPT(a1)
        tst.l   TC_TRAPCODE(a1)
        bne.s   .at_trap
        move.l  EB_TASKTRAPCODE(a6),TC_TRAPCODE(a1)
.at_trap:
        tst.l   TC_EXCEPTCODE(a1)
        bne.s   .at_exc
        move.l  EB_TASKEXCEPTCODE(a6),TC_EXCEPTCODE(a1)
.at_exc:
        move.l  a3,d0
        bne.s   .at_fin
        move.l  EB_TASKEXITCODE(a6),d0
.at_fin:
        move.l  TC_SPUPPER(a1),a0    ; top of the task's user stack
        move.l  d0,-(a0)             ; finalPC (A3, or TaskExitCode when 0): return if the task does RTS
        moveq   #14,d0
.at_zero:
        clr.l   -(a0)                ; 15 register longs = 0
        dbf     d0,.at_zero
        move.w  #$0000,-(a0)         ; initial SR = USER mode, IPL0 (S bit = 0)
        move.l  a2,-(a0)             ; initial PC
        move.l  a0,TC_SPREG(a1)
        addq.b  #1,EB_IDNEST(a6)     ; BARE Disable: Enqueue atomic vs an interrupt's Signal
        move.w  #INTF_INTEN,INTENA
        lea     EB_TASKREADY(a6),a0
        jsr     LVO_ENQUEUE(a6)      ; Enqueue(TaskReady, task)
        bra     raw_enable

; RemTask(task a1): removes a task and frees the MemLists of its tc_MemEntry (FreeEntry), and NOTHING else: the
; memory of the structure and of the stack belongs to whoever created the task, who describes it in tc_MemEntry
; (task_alloc, CreateProc, amiga.lib CreateTask) — freeing TCB and stack automatically returned the memory of
; tasks created by programs twice. a1 = 0 or ThisTask -> SELF: switches to supervisor via EXEC_SVC (frees on the
; SSP then switches to the next task, DOES NOT RETURN). Otherwise NON-SELF (ready/waiting task): Remove from its
; list + freeing, in task context, under an EXTERNAL Forbid (FreeMem's internal Permit does not yield) + Disable
; (atomic vs an IRQ touching the lists).
exec_RemTask:
        move.l  a1,d0
        bne.s   .rt_chk
        move.l  EB_THISTASK(a6),a1   ; NULL -> self
.rt_chk:
        cmp.l   EB_THISTASK(a6),a1
        beq.s   .rt_self
        ; --- NON-SELF: the target is not current (on TaskReady or TaskWait) ---
        move.l  d6,-(sp)
        move.l  a1,d6                ; d6 = TCB
        jsr     LVO_FORBID(a6)       ; external Forbid -> suppresses the yield of FreeMem's internal Permit
        addq.b  #1,EB_IDNEST(a6)     ; Disable -> Remove atomic vs an IRQ (Signal) touching the lists
        move.w  #INTF_INTEN,INTENA
        move.l  d6,a1                ; Remove(a1) from its list (SUCC/PRED of the node -> any list)
        jsr     LVO_REMOVE(a6)
        move.l  d6,a1
        move.b  #TS_REMOVED,TC_STATE(a1)
                ifeq    M7J_NOFREE
        move.l  d6,a1
        bsr     task_freemem
                endc
        bsr     raw_enable           ; INTEN on (bare exit, no reschedule tail)
        jsr     LVO_PERMIT(a6)       ; end of the external Forbid (yield OK here: task context, after RemTask)
        move.l  (sp)+,d6
        rts
.rt_self:
        move.b  #TS_REMOVED,TC_STATE(a1)
        EXEC_SVC trap2_handler       ; -> supervisor: frees + switches, DOES NOT RETURN
        rts                          ; safety net (never reached)

; task_freemem(a1 = task, a6): each MemList of tc_MemEntry is returned by FreeEntry. The list header is IN the
; task, which the last MemList may free: the end of list is the address of lh_Tail, computed beforehand, and each
; next node is read before it is freed. List never initialised (null head): nothing. Preserves d2-d7/a2-a6.
task_freemem:
        movem.l a2-a3,-(sp)
        lea     TC_MEMENTRY+4(a1),a3 ; a3 = &lh_Tail (end of list)
        move.l  TC_MEMENTRY(a1),a2
.tf_lp:
        cmpa.w  #0,a2
        beq.s   .tf_ret
        cmpa.l  a3,a2
        beq.s   .tf_ret
        move.l  a2,a0
        move.l  (a2),a2              ; next
        jsr     LVO_FREEENTRY(a6)
        bra.s   .tf_lp
.tf_ret:
        movem.l (sp)+,a2-a3
        rts

; task_alloc(d0 = structure size, d1 = stack size, a6) -> d0 = task | 0: structure and stack (public,
; zeroed) obtained through AllocEntry and described in tc_MemEntry (RemTask will return them); TC_SPLOWER /
; TC_SPUPPER set. Preserves d2-d7/a2-a6.
task_alloc:
        movem.l a2-a3,-(sp)
        lea     -(ML_ME+16)(sp),sp   ; two-entry MemList template
        move.w  #2,ML_NUMENTRIES(sp)
        move.l  #MEMF_PUBLIC|MEMF_CLEAR,ML_ME(sp)
        move.l  d0,ML_ME+4(sp)
        move.l  #MEMF_PUBLIC|MEMF_CLEAR,ML_ME+8(sp)
        move.l  d1,ML_ME+12(sp)
        move.l  sp,a0
        jsr     LVO_ALLOCENTRY(a6)
        lea     ML_ME+16(sp),sp
        tst.l   d0
        bmi.s   .ta_fail             ; bit 31: failure (nothing remains allocated)
        move.l  d0,a2                ; a2 = MemList
        move.l  ML_ME(a2),a3         ; a3 = structure
        move.l  ML_ME+8(a2),d0       ; stack
        move.l  d0,TC_SPLOWER(a3)
        add.l   ML_ME+12(a2),d0
        move.l  d0,TC_SPUPPER(a3)
        lea     TC_MEMENTRY(a3),a0   ; NEWLIST(tc_MemEntry) then AddHead(MemList)
        move.l  a0,8(a0)             ; lh_TailPred = &lh_Head
        clr.l   4(a0)                ; lh_Tail = 0
        lea     4(a0),a1
        move.l  a1,(a0)              ; lh_Head = &lh_Tail
        move.l  a2,a1
        jsr     LVO_ADDHEAD(a6)
        move.l  a3,d0
        bra.s   .ta_ret
.ta_fail:
        moveq   #0,d0
.ta_ret:
        movem.l (sp)+,a2-a3
        rts

; FindTask(name a1) -> d0 = task | 0; a1 == NULL -> current task
exec_FindTask:
        move.l  a1,d0
        bne.s   .ft_named
        move.l  EB_THISTASK(a6),d0
        rts
.ft_named:
        move.l  a2,-(sp)
        move.l  a1,a2                ; keep the name (FindName clobbers a1)
        lea     EB_TASKREADY(a6),a0
        move.l  a2,a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        bne.s   .ft_done
        lea     EB_TASKWAIT(a6),a0
        move.l  a2,a1
        jsr     LVO_FINDNAME(a6)
.ft_done:
        move.l  (sp)+,a2
        rts

; AllocSignal(signum d0.l) -> d0 = allocated bit number | -1
; signum == -1: allocates the lowest free bit; otherwise allocates that precise bit.
; The allocated bit is cleared in SIGWAIT/SIGRECVD/SIGEXCEPT (clean start).
exec_AllocSignal:
        move.l  d2,-(sp)
        move.l  EB_THISTASK(a6),a0
        move.l  TC_SIGALLOC(a0),d1   ; mask of the allocated bits
        tst.l   d0
        bpl.s   .as_spec             ; precise bit requested
        moveq   #0,d0                ; search for the lowest free bit
.as_scan:
        btst    d0,d1
        beq.s   .as_got
        addq.l  #1,d0
        cmp.l   #32,d0
        bne.s   .as_scan
        moveq   #-1,d0               ; none free
        move.l  (sp)+,d2
        rts
.as_spec:
        btst    d0,d1
        bne.s   .as_fail             ; already allocated
.as_got:
        bset    d0,d1
        move.l  d1,TC_SIGALLOC(a0)
        moveq   #1,d2
        lsl.l   d0,d2                ; mask = 1<<bit
        not.l   d2
        and.l   d2,TC_SIGWAIT(a0)
        and.l   d2,TC_SIGRECVD(a0)
        and.l   d2,TC_SIGEXCEPT(a0)
        move.l  (sp)+,d2
        rts
.as_fail:
        moveq   #-1,d0
        move.l  (sp)+,d2
        rts

; FreeSignal(signum d0)
exec_FreeSignal:
        move.l  EB_THISTASK(a6),a0
        move.l  TC_SIGALLOC(a0),d1
        bclr    d0,d1
        move.l  d1,TC_SIGALLOC(a0)
        rts

; SetSignal(newSignals d0, signalSet d1) -> d0 = old TC_SIGRECVD. Under a bare Disable (an interrupt's Signal
; also updates the mask). Then, as Signal: an exception signal now received -> TB_EXCEPT + Reschedule.
exec_SetSignal:
        move.l  d2,-(sp)
        addq.b  #1,EB_IDNEST(a6)
        move.w  #INTF_INTEN,INTENA
        move.l  EB_THISTASK(a6),a0
        move.l  TC_SIGRECVD(a0),d2   ; old ones
        and.l   d1,d0                ; newSignals & mask
        not.l   d1                   ; ~mask
        and.l   d2,d1                ; old & ~mask
        or.l    d1,d0                ; new = (old&~mask) | (newSignals&mask)
        move.l  d0,TC_SIGRECVD(a0)
        bsr     task_excpending
        move.l  d2,d0                ; return the old ones
        move.l  (sp)+,d2
        rts

; task_excpending(a0 = ThisTask, inside a bare Disable): ends the Disable; if tc_SigRecvd & tc_SigExcept != 0,
; sets TB_EXCEPT and calls Reschedule through its vector (the exception is delivered at the next dispatch).
; Clobbers d0/d1/a0/a1.
task_excpending:
        move.l  TC_SIGRECVD(a0),d0
        and.l   TC_SIGEXCEPT(a0),d0
        beq     raw_enable
        bset    #TB_EXCEPT,TC_FLAGS(a0)
        bsr     raw_enable
        jmp     LVO_RESCHEDULE(a6)

; Signal(task a1, signalSet d0): sets the bits in the task's TC_SIGRECVD; if it is blocked
; (TS_WAIT) on one of these bits, wakes it up (TaskWait -> TaskReady).
; M7c: called from a USER-MODE task OR from an interrupt (timer service). Atomicity
; vs the scheduler goes through a BARE CRITICAL SECTION: bare Disable on entry (INTENA, user-safe),
; raw_enable on exit — NOT exec_Enable, whose tail would trigger reschedule->trap in IRQ
; context (scheduler re-entry, cf. ledger M7c). Signal does not switch itself: it SETS SAR (if
; the woken task has priority), consumed by the next Permit/Enable (yield) or VBlank tick.
; Remove/Enqueue preserve a1. The woken task goes into TaskReady ("defer" model).
; Exception signal (d0 & tc_SigExcept, exec-scheduling-v34 §2.7): TB_EXCEPT set, a waiting task is woken whatever
; its wait mask, then Reschedule (which only sets SAR when called from an interrupt).
exec_Signal:
        addq.b  #1,EB_IDNEST(a6)     ; BARE Disable (critical section vs scheduler)
        move.w  #INTF_INTEN,INTENA   ; INTEN off (bit14)
        or.l    d0,TC_SIGRECVD(a1)
        and.l   TC_SIGEXCEPT(a1),d0
        bne.s   .sig_exc
        cmp.b   #TS_WAIT,TC_STATE(a1)
        bne.s   .sig_done            ; not waiting -> just set the bits
        move.l  TC_SIGRECVD(a1),d0
        and.l   TC_SIGWAIT(a1),d0
        beq.s   .sig_done            ; waiting, but not on these bits
        move.b  #TS_READY,TC_STATE(a1)
        jsr     LVO_REMOVE(a6)       ; remove the target (a1) from TaskWait
        lea     EB_TASKREADY(a6),a0
        jsr     LVO_ENQUEUE(a6)      ; insert the target (a1) into TaskReady (by priority)
        ; M3e: if the woken task has HIGHER priority than the current one, request a deferred reschedule.
        move.l  EB_THISTASK(a6),a0
        move.b  LN_PRI(a1),d0        ; priority of the woken task (signed byte)
        cmp.b   LN_PRI(a0),d0        ; woken - current
        ble.s   .sig_done            ; woken <= current -> no preemption
        bset    #SFB_SAR,EB_SYSFLAGS(a6)
.sig_done:
        bra     raw_enable           ; BARE exit (INTEN on if IDNest<0; no reschedule tail)
.sig_exc:
        bset    #TB_EXCEPT,TC_FLAGS(a1)
        cmp.b   #TS_WAIT,TC_STATE(a1)
        bne.s   .sig_resched
        move.b  #TS_READY,TC_STATE(a1)
        jsr     LVO_REMOVE(a6)
        lea     EB_TASKREADY(a6),a0
        jsr     LVO_ENQUEUE(a6)
.sig_resched:
        bsr     raw_enable
        jmp     LVO_RESCHEDULE(a6)

; SetTaskPri(task a1, pri d0.b) -> d0 = old priority, ZERO-extended as in 1.3 (-1 -> $000000FF). A READY task
; is re-enqueued; Reschedule when the task is the running one or became the head of TaskReady
; (exec-scheduling-v34 §2.7: SetTaskPri(self, same) yields to the ready tasks of equal priority).
exec_SetTaskPri:
        move.l  d2,-(sp)
        addq.b  #1,EB_IDNEST(a6)     ; BARE Disable
        move.w  #INTF_INTEN,INTENA
        moveq   #0,d2
        move.b  LN_PRI(a1),d2        ; old pri
        move.b  d0,LN_PRI(a1)        ; new one
        cmp.l   EB_THISTASK(a6),a1
        beq.s   .stp_resched
        cmp.b   #TS_READY,TC_STATE(a1)
        bne.s   .stp_done
        jsr     LVO_REMOVE(a6)
        lea     EB_TASKREADY(a6),a0
        jsr     LVO_ENQUEUE(a6)
        cmp.l   EB_TASKREADY(a6),a1
        bne.s   .stp_done
.stp_resched:
        bsr     raw_enable
        jsr     LVO_RESCHEDULE(a6)
        bra.s   .stp_ret
.stp_done:
        bsr     raw_enable
.stp_ret:
        move.l  d2,d0
        move.l  (sp)+,d2
        rts

task_name:
        dc.b    "exec.task",0
        EVEN
