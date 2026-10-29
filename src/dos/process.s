; src/dos/process.s - Process + CreateProc (D3a). INTERNAL dos machinery: a Process = exec struct Task +
; embedded pr_MsgPort (@PR_MSGPORT) + V34 fields up to pr_WindowPtr. proc_create builds the Process, initialises
; its pr_MsgPort ENTIRELY in the parent (reserved sigbit DOS_PORTSIG pre-allocated via TC_SIGALLOC -> no race:
; signals are level-latched + WaitPort checks the list first), then AddTask. Returns the APTR of the port (NOT a BPTR).
;
; IMPLEMENTATION track ("clean"): docs/analysis/dos-v34-spec.md §4 (CreateProc behaviour) + exec AutoDocs
; (AddTask/MsgPort) + AROS rom/dos (read-only). NO ROM reading.
; D3a scope: creation + port; no pr_GlobVec/pr_CLI/pr_CurrentDir wired up (CLI = later). Process bodies
; start with GPRs at zero (AddTask frame) -> they reload SysBase from ($4).w themselves.

                include "exec.i"
                include "dospkt.i"

                xdef    proc_create
                xdef    dos_sendpkt
                xref    dos_pktretry         ; dos/dos_lib.s
                xref    task_alloc           ; exec/tasks.s

; proc_create(a6=SysBase, a0=name, a1=entryPC, d0=priority.b, d1=stack size) -> d0 = APTR &pr_MsgPort | 0.
proc_create:
                movem.l d2-d4/a2-a4,-(sp)
                move.l  a0,a2                ; a2 = name
                move.l  a1,a3                ; a3 = entryPC (process body)
                move.b  d0,d3                ; d3 = priority
                move.l  d1,d4                ; d4 = stack size
                addq.l  #7,d4
                and.w   #-8,d4
                move.l  #PR_SIZEOF,d0        ; Process + stack described in tc_MemEntry (RemTask will free them)
                move.l  d4,d1
                jsr     task_alloc
                tst.l   d0
                beq     .fail
                move.l  d0,a4                ; a4 = Process (= base Task)
                move.l  a2,LN_NAME(a4)
                move.b  d3,LN_PRI(a4)
                move.b  #NT_PROCESS,LN_TYPE(a4)
                move.l  #SYS_SIGALLOC,TC_SIGALLOC(a4)   ; bits 0-15 reserved (including DOS_PORTSIG=8)
                move.l  TC_SPUPPER(a4),d0
                subq.l  #4,d0                ; last long = stack size: at startup (sp) = return address,
                move.l  d0,a0                ; 4(sp) = size, pr_ReturnAddr -> this long (exit code of C programs)
                move.l  d4,(a0)
                move.l  d0,TC_SPUPPER(a4)
                move.l  d0,PR_RETURNADDR(a4)
                ; --- initialise pr_MsgPort ENTIRELY in the parent (no handshake) ---
                lea     PR_MSGPORT(a4),a0    ; a0 = &pr_MsgPort
                move.b  #NT_MSGPORT,LN_TYPE(a0)
                move.b  #PA_SIGNAL,MP_FLAGS(a0)
                move.b  #DOS_PORTSIG,MP_SIGBIT(a0)
                move.l  a4,MP_SIGTASK(a0)    ; PutMsg will signal THIS process on its own port
                lea     MP_MSGLIST(a0),a1    ; NEWLIST(mp_MsgList) inline
                move.l  a1,d0
                addq.l  #4,d0
                move.l  d0,(a1)              ; lh_Head = &lh_Tail
                clr.l   4(a1)                ; lh_Tail = 0
                move.l  a1,8(a1)             ; lh_TailPred = &lh_Head
                ; --- AddTask(a1=task, a2=initPC, a3=finalPC) ---
                move.l  a4,a1
                move.l  a3,a2                ; initPC = entryPC
                lea     proc_exit(pc),a3     ; finalPC (safety net: a body that returns blocks)
                jsr     LVO_ADDTASK(a6)
                lea     PR_MSGPORT(a4),a0    ; return the APTR of the port
                move.l  a0,d0
                bra.s   .ret
.fail:
                moveq   #0,d0
.ret:
                movem.l (sp)+,d2-d4/a2-a4
                rts

; Safety net: if a process body RETURNS (should not happen - they loop), block forever
; (Wait(0) never wakes up) rather than letting AddTask jump into the void.
proc_exit:
                move.l  ($4).w,a6
.pe:
                moveq   #0,d0
                jsr     LVO_WAIT(a6)
                bra.s   .pe

; dos_sendpkt(a6=SysBase, a0=StandardPacket, a1=handler port, d0=dp_Type, d1=arg1, d2=arg2, d3=arg3, d4=arg4)
;   -> d0 = dp_Res1, d1 = dp_Res2. No public DoPkt in V34 -> this internal equivalent sets up the packet, PutMsg to
;   the handler, then WaitPort/GetMsg on the CALLER's pr_MsgPort (which MUST be a Process). dos convention:
;   dp_Port/mn_ReplyPort = &caller.pr_MsgPort. Reused by the proof driver (D3b) and by dos Open/Read (D3c).
;   The packet travels as a BPTR (taskwait of a BCPL handler returns it via ln_Name >> 2): it must be long-aligned.
;   A StandardPacket supplied on a stack that is only word-aligned (C programs) is replaced by a long-aligned
;   reserve in the dos_sendpkt frame.
dos_sendpkt:
                movem.l d5/a2-a5,-(sp)
                lea     -(SP_SIZEOF+2)(sp),sp
                move.l  a0,d5
                btst    #1,d5
                beq.s   .sp_aligned
                move.l  sp,d5                ; reserve: sp or sp+2 is long-aligned
                btst    #1,d5
                beq.s   .sp_aligned
                addq.l  #2,d5
.sp_aligned:
                move.l  d5,a2                ; a2 = StandardPacket (&sp_Msg)
                move.l  a1,a3                ; a3 = handler port
                lea     SP_PKT(a2),a4        ; a4 = &sp_Pkt (DosPacket)
                move.l  EB_THISTASK(a6),a0
                lea     PR_MSGPORT(a0),a0    ; a0 = reply port = ThisTask->pr_MsgPort
                move.l  a0,a5                ; a5 = reply port (saved for WaitPort)
                move.l  d4,DP_ARG4(a4)
                move.b  #NT_MESSAGE,LN_TYPE(a2)
                move.l  a0,MN_REPLYPORT(a2)
                move.w  #DP_SIZEOF,MN_LENGTH(a2)
                move.l  a4,LN_NAME(a2)       ; sp_Msg.ln_Name -> sp_Pkt (the handler reads the packet there)
                move.l  a2,DP_LINK(a4)
                move.l  a0,DP_PORT(a4)
                move.l  d0,DP_TYPE(a4)
                move.l  d1,DP_ARG1(a4)
                move.l  d2,DP_ARG2(a4)
                move.l  d3,DP_ARG3(a4)
                clr.l   DP_RES1(a4)
                clr.l   DP_RES2(a4)
.sp_send:
                move.l  a3,a0                ; PutMsg(handlerPort, &sp_Msg)
                move.l  a2,a1
                jsr     LVO_PUTMSG(a6)
                move.l  a5,a0                ; WaitPort(reply) -> synchronous switch to the handler
                jsr     LVO_WAITPORT(a6)
                move.l  a5,a0
                jsr     LVO_GETMSG(a6)       ; fetch our packet (replied by the handler)
                move.l  DP_RES1(a4),d0
                move.l  DP_RES2(a4),d1
                jsr     dos_pktretry         ; volume ejected: "Please replace volume", Retry -> resend
                tst.l   d0
                beq.s   .sp_done
                clr.l   DP_RES1(a4)
                clr.l   DP_RES2(a4)
                move.l  a5,DP_PORT(a4)
                move.l  a5,MN_REPLYPORT(a2)
                bra.s   .sp_send
.sp_done:
                move.l  DP_RES1(a4),d0
                move.l  DP_RES2(a4),d1
                ifeq    DOS_NO_IOERR
                move.l  EB_THISTASK(a6),a0   ; IoErr: pr_Result2 = dp_Res2 of the packet (faithful; a6 = SysBase)
                move.l  d1,PR_RESULT2(a0)
                endc                         ; RED DOS_NO_IOERR: do not propagate -> IoErr returns 0 even on failure
                lea     SP_SIZEOF+2(sp),sp
                movem.l (sp)+,d5/a2-a5
                rts
