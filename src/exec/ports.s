; src/exec/ports.s — exec.library: message ports.
;   AddPort/RemPort/FindPort: public ports in ExecBase.PortList.
;   PutMsg   : AddTail of the message, then the port action (mp_Flags AND 3).
;   GetMsg   : RemHead of the 1st message (FIFO) or NULL.
;   ReplyMsg : PutMsg to mn_ReplyPort with type NT_REPLYMSG, or NT_FREEMSG when there is no reply port.
;   WaitPort : blocks until a message is present; returns the 1st one without removing it.
; Amiga convention: scratch = d0/d1/a0/a1; a6 = library base.
; IMPLEMENTATION track ("clean"): docs/analysis/exec-messages-io-v34.md §1, NDK exec/ports.i (public ABI).

                include "exec.i"

                xdef    exec_AddPort
                xdef    exec_RemPort
                xdef    exec_FindPort
                xdef    exec_PutMsg
                xdef    exec_GetMsg
                xdef    exec_ReplyMsg
                xdef    exec_WaitPort

                xref    raw_enable       ; library.s (interrupt-safe ports = BARE Disable + raw_enable)

; PutMsg/GetMsg/ReplyMsg work on MP_MSGLIST, which an interrupt (a device replying from its handler) also touches:
; they run under a BARE Disable (INTENA + raw_enable, no reschedule tail, so no scheduler re-entry when called
; from an interrupt). AddPort/RemPort only exclude other tasks (Forbid). FindPort leaves the exclusion to its
; caller (V34 contract).

; AddPort(port a1): under Forbid, mp_MsgList emptied (NewList) and the port Enqueued on PortList by priority.
; ln_Type is not set (1.3: the caller marks its port NT_MSGPORT itself).
exec_AddPort:
        jsr     LVO_FORBID(a6)
        lea     MP_MSGLIST(a1),a0
        move.l  a0,8(a0)             ; lh_TailPred = &lh_Head
        clr.l   4(a0)                ; lh_Tail = 0
        move.l  a0,(a0)
        addq.l  #4,(a0)              ; lh_Head = &lh_Tail
        lea     EB_PORTLIST(a6),a0
        jsr     LVO_ENQUEUE(a6)
        jmp     LVO_PERMIT(a6)

; RemPort(port a1): unlinked under Forbid. D0/D1 kept; A0 = old successor, A1 = old predecessor.
exec_RemPort:
        jsr     LVO_FORBID(a6)
        move.l  (a1),a0
        move.l  LN_PRED(a1),a1
        move.l  a0,(a1)
        move.l  a1,LN_PRED(a0)
        jmp     LVO_PERMIT(a6)

; FindPort(name a1) -> d0 = port | 0 (search in PortList).
exec_FindPort:
        lea     EB_PORTLIST(a6),a0
        jmp     LVO_FINDNAME(a6)

; PutMsg(port a0, message a1): under Disable, ln_Type := NT_MESSAGE, AddTail, then the action of mp_Flags AND 3
; when mp_SigTask is not NULL: 0 Signal(mp_SigTask, 1 << (mp_SigBit AND 31)), 1 Cause(mp_SigTask), 2 nothing,
; 3 JSR mp_SigTask (A0 = that address, A1 = port, D0 = mp_Flags; its D0/D1/A0/A1 are what PutMsg returns).
; D2-D7/A2-A6 preserved.
exec_PutMsg:
        moveq   #NT_MESSAGE,d0
; pm_queue(port a0, message a1, type d0.b): PutMsg with the given message type (ReplyMsg: NT_REPLYMSG). The type is
; set inside the Disable: no task sees a "replied" message before it is in the port.
pm_queue:
        addq.b  #1,EB_IDNEST(a6)     ; BARE Disable
        move.w  #INTF_INTEN,INTENA
        move.b  d0,LN_TYPE(a1)
        move.l  a0,-(sp)
        lea     MP_MSGLIST(a0),a0
        jsr     LVO_ADDTAIL(a6)
        move.l  (sp)+,a1             ; a1 = port
        move.l  MP_SIGTASK(a1),d0
        beq.s   .pm_done             ; no target: queue only, whatever the action
        moveq   #PF_ACTION,d1
        and.b   MP_FLAGS(a1),d1
        beq.s   .pm_signal
        subq.b  #PA_IGNORE,d1
        beq.s   .pm_done
        bmi.s   .pm_cause
        move.l  d0,a0                ; action 3: call the routine held in mp_SigTask
        moveq   #0,d0
        move.b  MP_FLAGS(a1),d0
        move.l  a6,-(sp)
        jsr     (a0)
        move.l  (sp)+,a6
        bra.s   .pm_done
.pm_cause:
        move.l  d0,a1                ; PA_SOFTINT: the softint runs when the Disable ends
        jsr     LVO_CAUSE(a6)
        bra.s   .pm_done
.pm_signal:
        move.b  MP_SIGBIT(a1),d1     ; bset on a register takes the bit number modulo 32
        move.l  d0,a1
        moveq   #0,d0
        bset    d1,d0
        jsr     LVO_SIGNAL(a6)
.pm_done:
        jmp     raw_enable           ; INTEN back on at the outermost level; registers kept

; GetMsg(port a0) -> d0 = message | 0 (RemHead of the queue, FIFO). A0 = &mp_MsgList, A1 = the new first node.
exec_GetMsg:
        addq.b  #1,EB_IDNEST(a6)     ; BARE Disable -> RemHead atomic vs an interrupt doing PutMsg
        move.w  #INTF_INTEN,INTENA
        lea     MP_MSGLIST(a0),a0
        jsr     LVO_REMHEAD(a6)
        jmp     raw_enable

; ReplyMsg(message a1): mn_ReplyPort set -> PutMsg to it with type NT_REPLYMSG; no reply port -> ln_Type :=
; NT_FREEMSG, d0 = 0, nothing else touched. The previous type is not checked.
exec_ReplyMsg:
        move.l  MN_REPLYPORT(a1),d0
        beq.s   .rm_free
        move.l  d0,a0
        moveq   #NT_REPLYMSG,d0
        bra     pm_queue
.rm_free:
        move.b  #NT_FREEMSG,LN_TYPE(a1)
        rts

; WaitPort(port a0) -> d0 = a1 = 1st message, not removed. A non-empty port returns at once (signal bit untouched,
; D1/A0 kept). Otherwise Wait(1 << mp_SigBit) until the list is not empty; D1 = that mask on return. No lost wakeup:
; PutMsg links the message before it signals.
exec_WaitPort:
        move.l  MP_MSGLIST(a0),a1
        tst.l   (a1)
        beq.s   .wp_wait
        move.l  a1,d0
        rts
.wp_wait:
        move.l  a0,-(sp)
.wp_loop:
        moveq   #0,d1
        move.b  MP_SIGBIT(a0),d1
        moveq   #0,d0
        bset    d1,d0
        move.l  d0,-(sp)
        jsr     LVO_WAIT(a6)
        move.l  (sp)+,d1
        move.l  (sp),a0
        move.l  MP_MSGLIST(a0),a1
        tst.l   (a1)
        beq.s   .wp_loop
        addq.l  #4,sp
        move.l  a1,d0
        rts
