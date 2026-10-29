; src/exec/ports.s — exec.library: message ports, NON-BLOCKING PART (M2.4c).
;   AddPort/RemPort/FindPort: public ports in ExecBase.PortList.
;   PutMsg   : AddTail of the message + Signal of the target task (if PA_SIGNAL).
;   GetMsg   : RemHead of the 1st message (FIFO) or NULL.
;   ReplyMsg: sends the message back to its MN_REPLYPORT, type NT_REPLYMSG.
;   WaitPort: M3d — BLOCKS until a message is present; returns the 1st one (without
;              removing it: GetMsg is what removes it).
; Amiga convention: scratch = d0/d1/a0/a1; a6 = library base.
; IMPLEMENTATION track ("clean"): NDK includes exec/ports.i (public ABI).
; The caller initialises MP_MSGLIST (NEWLIST) and MP_FLAGS/MP_SIGBIT/MP_SIGTASK
; before AddPort (V34 contract; CreateMsgPort only exists in V36+).

                include "exec.i"

                xdef    exec_AddPort
                xdef    exec_RemPort
                xdef    exec_FindPort
                xdef    exec_PutMsg
                xdef    exec_GetMsg
                xdef    exec_ReplyMsg
                xdef    exec_WaitPort

                xref    raw_enable       ; library.s (M7d: interrupt-safe ports = BARE Disable + raw_enable)

; M3c: AddPort/RemPort wrapped in Forbid/Permit (PortList = task-vs-task exclusion;
; no interrupt touches it). M7d: PutMsg/GetMsg/ReplyMsg manipulate MP_MSGLIST, which CAN
; be touched from an INTERRUPT (an IRQ-driven device that does PutMsg/ReplyMsg) -> they are
; now INTERRUPT-SAFE: BARE critical section (Disable INTENA + raw_enable, without reschedule
; tail -> no scheduler re-entry from the IRQ), instead of Forbid (which does NOT mask
; interrupts). Forbid protected task-vs-task; Disable ALSO protects vs interrupts.
; FindPort/FindName remain arbitrated by the CALLER (exec V34 contract).

; AddPort(port a1): type NT_MSGPORT then Enqueue into PortList (priority order).
exec_AddPort:
        move.b  #NT_MSGPORT,LN_TYPE(a1)
        lea     MP_MSGLIST(a1),a0    ; AutoDoc: AddPort also initialises the message list (NEWLIST)
        move.l  a0,8(a0)             ; lh_TailPred = &lh_Head
        clr.l   4(a0)                ; lh_Tail = 0
        move.l  a0,(a0)
        addq.l  #4,(a0)              ; lh_Head = &lh_Tail
        jsr     LVO_FORBID(a6)
        lea     EB_PORTLIST(a6),a0
        jsr     LVO_ENQUEUE(a6)
        jsr     LVO_PERMIT(a6)
        rts

; RemPort(port a1): removes from PortList.
exec_RemPort:
        jsr     LVO_FORBID(a6)
        jsr     LVO_REMOVE(a6)
        jsr     LVO_PERMIT(a6)
        rts

; FindPort(name a1) -> d0 = port | 0 (search in PortList).
exec_FindPort:
        lea     EB_PORTLIST(a6),a0
        jsr     LVO_FINDNAME(a6)
        rts

; PutMsg(port a0, message a1): links the message then signals the task (PA_SIGNAL).
exec_PutMsg:
        move.l  a2,-(sp)
        move.l  a0,a2                ; a2 = port
        addq.b  #1,EB_IDNEST(a6)     ; M7d: BARE Disable -> {linking + signal} atomic vs task AND interrupt
        move.w  #INTF_INTEN,INTENA   ; INTEN off (bit14)
        move.b  #NT_MESSAGE,LN_TYPE(a1)
        lea     MP_MSGLIST(a2),a0    ; AddTail(&port->MsgList, msg)
        jsr     LVO_ADDTAIL(a6)
        moveq   #0,d0
        move.b  MP_FLAGS(a2),d0
        and.b   #PF_ACTION,d0
        bne.s   .pm_done             ; action != PA_SIGNAL -> no signal
        move.l  MP_SIGTASK(a2),d0
        beq.s   .pm_done             ; no target task
        move.l  d0,a1                ; a1 = task to signal
        moveq   #0,d0
        move.b  MP_SIGBIT(a2),d0
        moveq   #1,d1
        lsl.l   d0,d1                ; 1 << MP_SIGBIT
        move.l  d1,d0
        jsr     LVO_SIGNAL(a6)       ; Signal(task a1, sigmask d0)
.pm_done:
        bsr     raw_enable           ; BARE exit (INTEN on if IDNest<0; no reschedule tail)
        move.l  (sp)+,a2
        rts

; GetMsg(port a0) -> d0 = message | 0 (RemHead of the queue, FIFO).
exec_GetMsg:
        addq.b  #1,EB_IDNEST(a6)     ; M7d: BARE Disable -> RemHead atomic vs an interrupt doing PutMsg
        move.w  #INTF_INTEN,INTENA
        lea     MP_MSGLIST(a0),a0
        jsr     LVO_REMHEAD(a6)      ; d0 = message | 0
        bsr     raw_enable           ; preserves d0 (raw_enable only touches EB_IDNEST/INTENA)
        rts

; ReplyMsg(message a1): sends back to MN_REPLYPORT (if present), type NT_REPLYMSG.
exec_ReplyMsg:
        move.l  a2,-(sp)
        move.l  a1,a2                ; a2 = message (PutMsg clobbers scratch a1)
        addq.b  #1,EB_IDNEST(a6)     ; M7d: BARE Disable -> {send back + marking} atomic vs task AND interrupt
        move.w  #INTF_INTEN,INTENA   ; (the owner must not GetMsg before the NT_REPLYMSG type)
        move.l  MN_REPLYPORT(a1),d0
        beq.s   .rm_mark             ; no reply port -> just mark
        move.l  d0,a0                ; a0 = reply port
        jsr     LVO_PUTMSG(a6)       ; AddTail + signal (PutMsg nests its own Disable -> nesting OK)
.rm_mark:
        move.b  #NT_REPLYMSG,LN_TYPE(a2)   ; overwrite -> "replied" type
        bsr     raw_enable           ; only the outermost raw_enable turns INTEN back on
        move.l  (sp)+,a2
        rts

; WaitPort(port a0) -> d0 = 1st message (lh_Head), WITHOUT removing it. Blocks while the
; queue is empty, via Wait(1<<MP_SIGBIT). No lost wakeup: PutMsg does AddTail BEFORE
; Signal, and Wait's SIGRECVD recheck is atomic (IPL 7) -> a message arriving just
; before/during the Wait is seen either by the queue test or by the already-set bit (Wait
; returns immediately), then the loop rereads the queue. a2 preserved across Wait (saved/
; restored in the blocking frame, untouched on the fast path).
exec_WaitPort:
        move.l  a2,-(sp)
        move.l  a0,a2                ; a2 = port (survives Wait)
.wp_loop:
        move.l  MP_MSGLIST(a2),a0    ; lh_Head of the port's queue
        tst.l   (a0)                 ; (lh_Head)==0 <=> empty queue
        bne.s   .wp_has              ; not empty -> at least one message
        moveq   #0,d0                ; empty queue -> Wait on the port's bit
        move.b  MP_SIGBIT(a2),d0
        moveq   #1,d1
        lsl.l   d0,d1                ; 1 << MP_SIGBIT
        move.l  d1,d0
        jsr     LVO_WAIT(a6)
        bra.s   .wp_loop
.wp_has:
        move.l  MP_MSGLIST(a2),d0    ; d0 = lh_Head = 1st message (not removed)
        move.l  (sp)+,a2
        rts
