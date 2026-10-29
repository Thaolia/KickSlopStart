; src/exec/semaphores.s — exec signal semaphores (struct SignalSemaphore, exec/semaphores.h).
;
; ss_QueueCount counts the current holds minus one (-1 = free): each Obtain increments it, each Release
; decrements it. ss_NestCount counts the owner's nested holds. A blocked requester puts a SemaphoreRequest
; on its stack into ss_WaitQueue and waits for SIGF_SINGLE; the Release that frees the semaphore hands it over
; directly (owner and nesting set up for it) before signalling it.
; Everything is done under Forbid: the wake-up of a requester only happens at Permit.
; ObtainSemaphoreList / ReleaseSemaphoreList / Procure / Vacate are not provided (remain neutral).
; IMPLEMENTATION track ("clean"): AutoDocs exec.library + exec/semaphores.h. NO ROM reading.

                include "exec.i"

                xdef    exec_InitSemaphore
                xdef    exec_ObtainSemaphore
                xdef    exec_ReleaseSemaphore
                xdef    exec_AttemptSemaphore
                xdef    exec_AddSemaphore
                xdef    exec_RemSemaphore
                xdef    exec_FindSemaphore

SS_NESTCOUNT    EQU 14
SS_WAITQUEUE    EQU 16               ; struct MinList (12)
SS_OWNER        EQU 40
SS_QUEUECOUNT   EQU 44
SS_SIZE         EQU 46
SR_WAITER       EQU 8                ; struct SemaphoreRequest: MinNode + sr_Waiter
SR_SIZE         EQU 12
NT_SIGNALSEM    EQU 15
SIGF_SINGLE     EQU $10

; InitSemaphore(sigSem a0): node and counters reset to zero, empty wait queue, free. The name (ln_Name) and
; priority are kept (AddSemaphore uses them).
exec_InitSemaphore:
        move.b  #NT_SIGNALSEM,LN_TYPE(a0)
        clr.w   SS_NESTCOUNT(a0)
        lea     SS_WAITQUEUE+4(a0),a1
        move.l  a1,SS_WAITQUEUE(a0)  ; mlh_Head = &mlh_Tail
        clr.l   (a1)+                ; mlh_Tail
        move.l  a0,(a1)
        add.l   #SS_WAITQUEUE,(a1)   ; mlh_TailPred = &mlh_Head
        lea     SS_WAITQUEUE+12(a0),a1
        clr.l   (a1)+                ; ss_MultipleLink (SemaphoreRequest, unused)
        clr.l   (a1)+
        clr.l   (a1)+
        clr.l   SS_OWNER(a0)
        move.w  #-1,SS_QUEUECOUNT(a0)
        rts

; ObtainSemaphore(sigSem a0): exclusive hold, nestable by its owner; blocks otherwise.
exec_ObtainSemaphore:
        movem.l a2-a3,-(sp)
        move.l  a0,a2
        jsr     LVO_FORBID(a6)
        move.l  EB_THISTASK(a6),a3
        addq.w  #1,SS_QUEUECOUNT(a2)
        beq.s   .ob_take             ; was free
        cmp.l   SS_OWNER(a2),a3
        beq.s   .ob_nest
        lea     -SR_SIZE(sp),sp      ; request queued, handed over by the Release that frees it
        move.l  a3,SR_WAITER(sp)
        lea     SS_WAITQUEUE(a2),a0
        move.l  sp,a1
        jsr     LVO_ADDTAIL(a6)
        moveq   #0,d0
        moveq   #SIGF_SINGLE,d1
        jsr     LVO_SETSIGNAL(a6)    ; a leftover SIGF_SINGLE must not wake the wait
.ob_wait:
        moveq   #SIGF_SINGLE,d0
        jsr     LVO_WAIT(a6)
        cmp.l   SS_OWNER(a2),a3
        bne.s   .ob_wait             ; signal from another source: still not owner
        lea     SR_SIZE(sp),sp
        bra.s   .ob_out
.ob_take:
        move.l  a3,SS_OWNER(a2)
.ob_nest:
        addq.w  #1,SS_NESTCOUNT(a2)
.ob_out:
        jsr     LVO_PERMIT(a6)
        movem.l (sp)+,a2-a3
        rts

; ReleaseSemaphore(sigSem a0): undoes a hold; at the last one, the first queued requester becomes owner.
exec_ReleaseSemaphore:
        move.l  a2,-(sp)
        move.l  a0,a2
        jsr     LVO_FORBID(a6)
        subq.w  #1,SS_QUEUECOUNT(a2)
        subq.w  #1,SS_NESTCOUNT(a2)
        bne.s   .rl_out              ; still held (nesting)
        clr.l   SS_OWNER(a2)
        tst.w   SS_QUEUECOUNT(a2)
        bmi.s   .rl_out              ; nobody waiting
        lea     SS_WAITQUEUE(a2),a0
        jsr     LVO_REMHEAD(a6)
        tst.l   d0
        beq.s   .rl_out
        move.l  d0,a0
        move.l  SR_WAITER(a0),a1
        move.l  a1,SS_OWNER(a2)
        move.w  #1,SS_NESTCOUNT(a2)
        moveq   #SIGF_SINGLE,d0
        jsr     LVO_SIGNAL(a6)
.rl_out:
        jsr     LVO_PERMIT(a6)
        move.l  (sp)+,a2
        rts

; AttemptSemaphore(sigSem a0) -> d0 = 1 if obtained (free or already ours), 0 otherwise; never blocks.
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

; AddSemaphore(sigSem a1): initialises then publishes in ExecBase->SemaphoreList (sorted by priority).
exec_AddSemaphore:
        move.l  a1,-(sp)
        move.l  a1,a0
        bsr     exec_InitSemaphore
        jsr     LVO_FORBID(a6)
        move.l  (sp)+,a1
        lea     EB_SEMLIST(a6),a0
        jsr     LVO_ENQUEUE(a6)
        jmp     LVO_PERMIT(a6)

; RemSemaphore(sigSem a1): removes from the public list.
exec_RemSemaphore:
        jsr     LVO_FORBID(a6)
        jsr     LVO_REMOVE(a6)
        jmp     LVO_PERMIT(a6)

; FindSemaphore(name a1) -> d0 = public semaphore with that name, or 0.
exec_FindSemaphore:
        lea     EB_SEMLIST(a6),a0
        jmp     LVO_FINDNAME(a6)
