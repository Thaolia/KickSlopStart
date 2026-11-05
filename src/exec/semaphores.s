; src/exec/semaphores.s — exec signal semaphores (struct SignalSemaphore, exec/semaphores.h).
;
; Behaviour and register contracts: docs/analysis/exec-memory-semaphores-v34.md §4-§5.
; ss_QueueCount counts holds plus waiters minus one (-1 = free): each Obtain increments it, each Release
; decrements it. ss_NestCount counts the owner's nested holds. A blocked ObtainSemaphore puts a SemaphoreRequest
; on its stack at the tail of ss_WaitQueue and waits for SIGF_SEMAPHORE; the Release that frees the semaphore hands
; it over itself: owner := the head request's task, ss_NestCount left at 0, Signal(task, SIGF_SEMAPHORE); the woken
; task increments ss_NestCount. ObtainSemaphoreList queues each semaphore's own ss_MultipleLink instead.
; Procure / Vacate work on the OLD V34 message semaphore (struct Semaphore), see below.
; IMPLEMENTATION track ("clean"): AutoDocs exec.library + exec/semaphores.h + the spec above. NO ROM reading.

                include "exec.i"

                xdef    exec_InitSemaphore
                xdef    exec_ObtainSemaphore
                xdef    exec_ReleaseSemaphore
                xdef    exec_AttemptSemaphore
                xdef    exec_ObtainSemaphoreList
                xdef    exec_ReleaseSemaphoreList
                xdef    exec_AddSemaphore
                xdef    exec_RemSemaphore
                xdef    exec_FindSemaphore
                xdef    exec_Procure
                xdef    exec_Vacate

SS_NESTCOUNT    EQU 14
SS_WAITQUEUE    EQU 16               ; struct MinList (12)
SS_MULTIPLELINK EQU 28               ; struct SemaphoreRequest (12)
SS_OWNER        EQU 40
SS_QUEUECOUNT   EQU 44
SR_WAITER       EQU 8                ; struct SemaphoreRequest: MinNode + sr_Waiter
SR_SIZE         EQU 12
NT_SIGNALSEM    EQU 15
SIGF_SEMAPHORE  EQU $10

; InitSemaphore(sigSem a0): ss_NestCount 0, empty wait queue, no owner, ss_QueueCount -1; nothing else is written
; (node, ss_MultipleLink). Changes a1 only (= the wait queue).
exec_InitSemaphore:
        clr.w   SS_NESTCOUNT(a0)
        clr.l   SS_OWNER(a0)
        move.w  #-1,SS_QUEUECOUNT(a0)
        lea     SS_WAITQUEUE+4(a0),a1
        move.l  a1,SS_WAITQUEUE(a0)  ; mlh_Head = &mlh_Tail
        clr.l   (a1)                 ; mlh_Tail
        lea     SS_WAITQUEUE(a0),a1
        move.l  a1,SS_WAITQUEUE+8(a0) ; mlh_TailPred = &mlh_Head
        rts

; ObtainSemaphore(sigSem a0): exclusive hold, nestable by its owner; blocks otherwise (Forbid kept across the
; Wait). Unlike 1.3, which returns after its single Wait, the owner is checked after each wake-up: a SIGF_SEMAPHORE
; from elsewhere does not break in. Preserves every register.
exec_ObtainSemaphore:
        movem.l d0-d1/a0-a3,-(sp)
        move.l  a0,a2
        jsr     LVO_FORBID(a6)
        move.l  EB_THISTASK(a6),a3
        addq.w  #1,SS_QUEUECOUNT(a2)
        beq.s   .ob_take             ; was free
        cmp.l   SS_OWNER(a2),a3
        beq.s   .ob_nest
        lea     -SR_SIZE(sp),sp      ; request on the stack, handed over by the Release that frees the semaphore
        move.l  a3,SR_WAITER(sp)
        moveq   #0,d0
        moveq   #SIGF_SEMAPHORE,d1
        jsr     LVO_SETSIGNAL(a6)    ; a SIGF_SEMAPHORE received earlier must not end the wait
        lea     SS_WAITQUEUE(a2),a0
        move.l  sp,a1
        jsr     LVO_ADDTAIL(a6)
.ob_wait:
        moveq   #SIGF_SEMAPHORE,d0
        jsr     LVO_WAIT(a6)
        cmp.l   SS_OWNER(a2),a3
        bne.s   .ob_wait
        lea     SR_SIZE(sp),sp
        bra.s   .ob_nest
.ob_take:
        move.l  a3,SS_OWNER(a2)
.ob_nest:
        addq.w  #1,SS_NESTCOUNT(a2)
        jsr     LVO_PERMIT(a6)
        movem.l (sp)+,d0-d1/a0-a3
        rts

; ReleaseSemaphore(sigSem a0): no owner check. Nested level: counts only (no Forbid). Last level, under Forbid: no
; waiter -> free; otherwise hand-off to the head request (see the header). A free semaphore is the dead-end
; Alert(AN_SemCorrupt). Preserves every register.
exec_ReleaseSemaphore:
        movem.l d0-d1/a0-a2,-(sp)
        move.l  a0,a2
        tst.w   SS_QUEUECOUNT(a2)
        bmi.s   .rl_free
        subq.w  #1,SS_QUEUECOUNT(a2)
        subq.w  #1,SS_NESTCOUNT(a2)
        bgt.s   .rl_out              ; still held (nesting)
        jsr     LVO_FORBID(a6)
        tst.w   SS_QUEUECOUNT(a2)
        bmi.s   .rl_noone
        lea     SS_WAITQUEUE(a2),a0
        jsr     LVO_REMHEAD(a6)
        tst.l   d0
        beq.s   .rl_noone
        move.l  d0,a0
        move.l  SR_WAITER(a0),a1
        move.l  a1,SS_OWNER(a2)
        moveq   #SIGF_SEMAPHORE,d0
        jsr     LVO_SIGNAL(a6)
        bra.s   .rl_permit
.rl_noone:
        clr.l   SS_OWNER(a2)
.rl_permit:
        jsr     LVO_PERMIT(a6)
.rl_out:
        movem.l (sp)+,d0-d1/a0-a2
        rts
.rl_free:
        move.l  d7,-(sp)
        move.l  #AN_SEMCORRUPT,d7
        jsr     LVO_ALERT(a6)        ; dead end
        move.l  (sp)+,d7
        bra.s   .rl_out

; AttemptSemaphore(sigSem a0) -> d0 = 1 if obtained (free or already ours), 0 otherwise (nothing changed); never
; blocks. Changes d0 and a1 (= ThisTask).
exec_AttemptSemaphore:
        jsr     LVO_FORBID(a6)
        move.l  EB_THISTASK(a6),a1
        cmp.w   #-1,SS_QUEUECOUNT(a0)
        beq.s   .at_take
        cmp.l   SS_OWNER(a0),a1
        bne.s   .at_no
.at_take:
        addq.w  #1,SS_QUEUECOUNT(a0)
        addq.w  #1,SS_NESTCOUNT(a0)
        move.l  a1,SS_OWNER(a0)
        jsr     LVO_PERMIT(a6)
        moveq   #1,d0
        rts
.at_no:
        jsr     LVO_PERMIT(a6)
        moveq   #0,d0
        rts

; ObtainSemaphoreList(list a0): every semaphore of the List (linked by their nodes), under Forbid. Pass 1 in list
; order: free or own ones are taken at once; for one held by another task, ss_QueueCount + 1 and its own
; ss_MultipleLink {ThisTask} goes to the tail of its wait queue. Pass 2 in list order: Wait(SIGF_SEMAPHORE) until
; the owner is ThisTask, then a handed-over semaphore (ss_NestCount 0) gets its first level. Changes d0, d1, a0, a1.
exec_ObtainSemaphoreList:
        movem.l d2/a2-a3,-(sp)
        move.l  a0,a2
        jsr     LVO_FORBID(a6)
        move.l  EB_THISTASK(a6),a3
        moveq   #0,d2                ; d2 = a request was queued
        move.l  (a2),a0
.ol_p1:
        tst.l   (a0)
        beq.s   .ol_pass2
        addq.w  #1,SS_QUEUECOUNT(a0)
        beq.s   .ol_take
        cmp.l   SS_OWNER(a0),a3
        beq.s   .ol_nest
        lea     SS_MULTIPLELINK(a0),a1
        move.l  a3,SR_WAITER(a1)
        move.l  a0,-(sp)
        lea     SS_WAITQUEUE(a0),a0
        jsr     LVO_ADDTAIL(a6)
        move.l  (sp)+,a0
        moveq   #1,d2
        bra.s   .ol_next
.ol_take:
        move.l  a3,SS_OWNER(a0)
.ol_nest:
        addq.w  #1,SS_NESTCOUNT(a0)
.ol_next:
        move.l  (a0),a0
        bra.s   .ol_p1
.ol_pass2:
        tst.w   d2
        beq.s   .ol_done
        move.l  (a2),a0
.ol_p2:
        tst.l   (a0)
        beq.s   .ol_done
.ol_own:
        cmp.l   SS_OWNER(a0),a3
        beq.s   .ol_got
        move.l  a0,-(sp)
        moveq   #SIGF_SEMAPHORE,d0
        jsr     LVO_WAIT(a6)
        move.l  (sp)+,a0
        bra.s   .ol_own
.ol_got:
        tst.w   SS_NESTCOUNT(a0)
        bne.s   .ol_n2
        addq.w  #1,SS_NESTCOUNT(a0)  ; handed over while this task waited
.ol_n2:
        move.l  (a0),a0
        bra.s   .ol_p2
.ol_done:
        jsr     LVO_PERMIT(a6)
        movem.l (sp)+,d2/a2-a3
        rts

; ReleaseSemaphoreList(list a0): ReleaseSemaphore (vector) on every node, in list order. Changes a0 only.
exec_ReleaseSemaphoreList:
        move.l  a2,-(sp)
        move.l  (a0),a2
.rs_lp:
        tst.l   (a2)
        beq.s   .rs_ret
        move.l  a2,a0
        jsr     LVO_RELEASESEMAPHORE(a6)
        move.l  (a2),a2
        bra.s   .rs_lp
.rs_ret:
        move.l  (sp)+,a2
        rts

; AddSemaphore(sigSem a1): InitSemaphore then Enqueue into ExecBase->SemaphoreList (by priority). 1.3 initialises
; a0 and links a0+16 instead, which no working program can rely on: the documented form is implemented.
exec_AddSemaphore:
        move.l  a1,a0
        bsr     exec_InitSemaphore
        move.b  #NT_SIGNALSEM,LN_TYPE(a0)
        move.l  a0,a1
        jsr     LVO_FORBID(a6)
        lea     EB_SEMLIST(a6),a0
        jsr     LVO_ENQUEUE(a6)
        jmp     LVO_PERMIT(a6)

; RemSemaphore(sigSem a1): removes from the public list, under Forbid. Changes a0 and a1 only.
exec_RemSemaphore:
        move.l  d0,-(sp)
        jsr     LVO_FORBID(a6)
        jsr     LVO_REMOVE(a6)
        jsr     LVO_PERMIT(a6)
        move.l  (sp)+,d0
        rts

; FindSemaphore(name a1) -> d0 = public semaphore with that name, or 0. No Forbid (the caller's).
exec_FindSemaphore:
        lea     EB_SEMLIST(a6),a0
        jmp     LVO_FINDNAME(a6)

; V34 message semaphore (exec/semaphores.i, old form; exec-scheduling-v34 §6): a MsgPort followed by sm_Bids
; (WORD, -1 = free); sm_LockMsg is the port's mp_SigTask field. Set up by the user (sm_Bids -1, message list
; initialised, PA_IGNORE). No Forbid/Disable: the caller provides the atomicity it needs.
SM_BIDS         EQU 34
SM_LOCKMSG      EQU MP_SIGTASK

; Procure(semaphore a0, bidMessage a1) -> d0 = 1 owned at once (sm_LockMsg = the bid, not queued) | 0 bid queued
; on the port (PutMsg); the owner learns it holds the semaphore when its bid is replied.
exec_Procure:
        addq.w  #1,SM_BIDS(a0)
        bne.s   .pr_queue
        move.l  a1,SM_LOCKMSG(a0)
        moveq   #1,d0
        rts
.pr_queue:
        movem.l d1/a0-a1,-(sp)       ; Procure changes d0 only (exec-memory-semaphores-v34 §4.8)
        jsr     LVO_PUTMSG(a6)
        movem.l (sp)+,d1/a0-a1
        moveq   #0,d0
        rts

; Vacate(semaphore a0): sm_LockMsg 0, sm_Bids - 1; still bidders -> the next bid becomes sm_LockMsg and is
; replied (it now owns the semaphore).
exec_Vacate:
        clr.l   SM_LOCKMSG(a0)
        subq.w  #1,SM_BIDS(a0)
        bmi.s   .va_ret
        move.l  a0,-(sp)
        jsr     LVO_GETMSG(a6)
        move.l  (sp)+,a0
        move.l  d0,SM_LOCKMSG(a0)
        beq.s   .va_ret
        move.l  d0,a1
        jsr     LVO_REPLYMSG(a6)
.va_ret:
        rts
