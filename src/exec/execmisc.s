; src/exec/execmisc.s — exec.library: documented V34 functions that were missing from the vector table (SetFunction,
; SumLibrary, Cause and the software interrupt queue, Alert, SetSR, SuperState/UserState, GetCC,
; RemIntServer, AllocEntry/FreeEntry, SetExcept, AllocTrap/FreeTrap, RemResource, Raw*, Obtain/ReleaseSemaphoreList).
; IMPLEMENTATION track ("clean"): AutoDocs exec + public includes (exec/libraries.i, exec/tasks.i, exec/memory.i).
; NO ROM reading.

                include "exec.i"

                xdef    exec_SetFunction
                xdef    exec_SumLibrary
                xdef    exec_Cause
                xdef    exec_softint_init
                xdef    exec_Alert
                xdef    alert_show           ; interrupts.s (exception of a task), boot.s (alert.hook)
                xdef    alert_boothook
                xdef    alert_deadend
                xdef    alert_reboot         ; interrupts.s: reboot from supervisor mode
                xdef    exec_SetSR
                xdef    exec_SuperState
                xdef    exec_UserState
                xdef    exec_GetCC
                xdef    exec_RemIntServer
                xdef    exec_AllocEntry
                xdef    exec_FreeEntry
                xdef    exec_SetExcept
                xdef    exec_AllocTrap
                xdef    exec_FreeTrap
                xdef    exec_RemResource
                xdef    exec_RawIOInit
                xdef    exec_RawMayGetChar
                xdef    exec_RawPutChar
                xdef    exec_ObtainSemaphoreList
                xdef    exec_ReleaseSemaphoreList
                xdef    exec_Debug
                xdef    debug_entry          ; library.s: ExecBase DebugEntry
                xdef    exec_SumKickData
                xdef    exec_ExitIntr        ; scheduling entries (exec-scheduling-v34 §2), with interrupts.s
                xdef    exec_Reschedule
                xdef    exec_Exception
                xdef    svc_schedule
                xdef    svc_switch
                xdef    except_default       ; library.s: ExecBase TaskExceptCode / TaskExitCode
                xdef    task_exit_default
                xref    exec_Schedule        ; interrupts.s
                xref    intr_chain_walker    ; interrupts.s (RemIntServer: is IntVects[n] a server chain?)
                xref    task_excpending      ; tasks.s (SetExcept: exception pending -> TB_EXCEPT + Reschedule)

LVO_SUPERVISOR_X EQU -30
ME_SIZE         EQU 8                ; struct MemEntry: me_Reqs|me_Addr, me_Length
INTENA_INTEN    EQU 14               ; master bit of INTENA

; SetFunction(library a1, funcOffset a0.w, newFunction d0) -> d0 = old function. The vector becomes
; JMP newFunction; the library is marked changed and its sum recomputed. Under Forbid.
exec_SetFunction:
        move.l  d0,d1
        move.w  a0,d0
        ext.l   d0
        lea     0(a1,d0.l),a0        ; a0 = vector
        jsr     LVO_FORBID(a6)
        move.l  2(a0),-(sp)          ; old function
        move.w  #$4EF9,(a0)
        move.l  d1,2(a0)
        bset    #LIBB_CHANGED,LIB_FLAGS(a1)
        bsr.s   exec_SumLibrary
        jsr     LVO_PERMIT(a6)
        move.l  (sp)+,d0
        rts

; SumLibrary(library a1): sum of the words of the vector table. Table changed (LIBF_CHANGED) or sum not
; verified: the sum is stored and LIBF_CHANGED cleared. (No alert on mismatch: no table is
; protected here.) Clobbers d0/d1/a0.
exec_SumLibrary:
        moveq   #0,d0
        moveq   #0,d1
        move.w  LIB_NEGSIZE(a1),d1
        lsr.w   #1,d1
        move.l  a1,a0
        sub.l   d1,a0
        sub.l   d1,a0                ; a0 = start of the table
        bra.s   .sl_nx
.sl_lp:
        add.w   (a0)+,d0
.sl_nx:
        dbra    d1,.sl_lp
        move.l  d0,LIB_SUM(a1)
        bclr    #LIBB_CHANGED,LIB_FLAGS(a1)
        rts

; Cause(interrupt a1): the software interrupt is queued (only once while it is pending) then
; SOFTINT is requested; the level 1 server executes it (a1 = is_Data, a5 = is_Code, a6 = SysBase). Callable
; from an interrupt: masking through INTENA (master state restored), never Disable/Enable (which may yield).
exec_Cause:
        move.w  INTENAR,d1
        move.w  #INTF_INTEN,INTENA
        cmp.b   #NT_SOFTINT,LN_TYPE(a1)
        beq.s   .ca_done             ; already pending
        move.b  #NT_SOFTINT,LN_TYPE(a1)
        move.l  d1,-(sp)
        lea     EXEC_SOFTLIST,a0
        jsr     LVO_ADDTAIL(a6)
        move.l  (sp)+,d1
        move.w  #(INTF_SETCLR|INTF_SOFTINT),INTREQ
.ca_done:
        btst    #INTENA_INTEN,d1
        beq.s   .ca_ret
        move.w  #(INTF_SETCLR|INTF_INTEN),INTENA
.ca_ret:
        rts

; exec_softint_init(a6): empty queue, SOFTINT server installed (exclusive level 1 vector) and source enabled.
; After init_ints (IntVects table allocated).
exec_softint_init:
        lea     EXEC_SOFTLIST,a0
        move.l  a0,8(a0)             ; lh_TailPred = &lh_Head
        addq.l  #LH_TAIL,a0
        move.l  a0,-LH_TAIL(a0)      ; lh_Head = &lh_Tail
        clr.l   (a0)                 ; lh_Tail = 0
        moveq   #INTB_SOFTINT,d0
        lea     softint_is(pc),a1
        jsr     LVO_SETINTVECTOR(a6)
        move.w  #INTF_SOFTINT,INTREQ
        move.w  #(INTF_SETCLR|INTF_SOFTINT),INTENA
        rts

; softint_server (level 1, a6 = SysBase): acknowledges SOFTINT then executes the pending interrupts in order.
softint_server:
        move.w  #INTF_SOFTINT,INTREQ
.ss_lp:
        move.w  #INTF_INTEN,INTENA
        lea     EXEC_SOFTLIST,a0
        jsr     LVO_REMHEAD(a6)
        move.w  #(INTF_SETCLR|INTF_INTEN),INTENA
        tst.l   d0
        beq.s   .ss_ret
        move.l  d0,a1
        move.b  #NT_INTERRUPT,LN_TYPE(a1)
        move.l  IS_CODE(a1),a5
        move.l  IS_DATA(a1),a1
        jsr     (a5)
        move.l  ($4).w,a6
        bra.s   .ss_lp
.ss_ret:
        rts

; Alert(alertNum d7, a5) (spec alert-v34 §1, coldstart-hardware-v34 §8): serial message, then
; - recoverable (bit 31 at 0): LastAlert = (number, long pointed to by a5), Guru displayed by DisplayAlert, LastAlert[0]
;   reset to -1; d0 = 1 (left button) | 0 (right button or intuition missing). A null high word (CPU exception
;   number) is treated as a recoverable alert;
; - dead end (bit 31): 'HELP' at $0, number at $100, second number at $104, blinking LED, reboot; the Guru
;   is displayed at the next boot (alert_boothook).
; Preserves d1-d7/a0-a6.
exec_Alert:
        movem.l d1-d2/a0-a1/a6,-(sp)
        lea     al_dead(pc),a0
        tst.l   d7
        bmi.s   .al_msg
        lea     al_rec(pc),a0
.al_msg:
        bsr     raw_puts
        move.l  d7,d2
        moveq   #7,d1
        lea     al_digits(pc),a1
.al_hex:
        rol.l   #4,d2
        moveq   #15,d0
        and.w   d2,d0
        move.b  0(a1,d0.w),d0
        bsr     exec_RawPutChar
        dbra    d1,.al_hex
        moveq   #10,d0
        bsr     exec_RawPutChar
        moveq   #0,d1                ; second number: the long pointed to by a5 (if it is readable in RAM)
        move.l  a5,d0
        btst    #0,d0
        bne.s   .al_2nd
        cmp.l   #$00200000,d0
        bhs.s   .al_2nd
        move.l  (a5),d1
.al_2nd:
        move.l  d7,d0
        tst.l   d7
        bmi     alert_deadend
        move.l  ($4).w,a6
        movem.l d0-d1,EB_LASTALERT(a6)
        bsr     alert_show
        move.l  ($4).w,a6
        move.l  #-1,EB_LASTALERT(a6)
        movem.l (sp)+,d1-d2/a0-a1/a6
        rts

; alert_deadend(d0 = number, d1 = second number): remembers the alert for the next boot ('HELP' at $0, $100, $104),
; blinks the LED six times then reboots. Does not return; usable in user or supervisor mode.
alert_deadend:
        move.l  #$48454C50,$0.w      ; 'HELP'
        move.l  d0,$100.w
        move.l  d1,$104.w
        moveq   #5,d1
.ad_blink:
        bset    #1,CIAA_PRA          ; LED dimmed
        bsr.s   .ad_wait
        bclr    #1,CIAA_PRA
        bsr.s   .ad_wait
        dbra    d1,.ad_blink
        move.l  ($4).w,a6
        lea     al_reset(pc),a5
        jsr     LVO_SUPERVISOR(a6)
.ad_wait:
        move.l  #50000,d0            ; ~0.15 s
.ad_w:
        subq.l  #1,d0
        bne.s   .ad_w
        rts
; al_reset (supervisor): RESET restores the overlay (ROM at $0); the JMP, read in the same long as the RESET
; (prefetched), goes to word 2 of the ROM: JMP to the coldstart entry point.
        cnop    0,4
alert_reboot:
al_reset:
        lea     2.w,a0
        reset
        jmp     (a0)

; alert_boothook: role of the alert.hook resident (spec alert-v34 §4), called once intuition is initialised. If a
; dead-end alert has been remembered ('HELP' at $0), displays its Guru, then clears the mark. Preserves everything.
alert_boothook:
        cmp.l   #$48454C50,$0.w
        bne.s   .ab_ret
        movem.l d0-d1/a6,-(sp)
        clr.l   $0.w
        move.l  $100.w,d0
        move.l  $104.w,d1
        move.l  ($4).w,a6
        movem.l d0-d1,EB_LASTALERT(a6)
        bsr.s   alert_show
        move.l  ($4).w,a6
        move.l  #-1,EB_LASTALERT(a6)
        movem.l (sp)+,d0-d1/a6
.ab_ret:
        rts

; alert_show(d0 = number, d1 = second number) -> d0 = result of DisplayAlert (0 without intuition): Guru text
; (spec alert-v34 §3), DisplayAlert(0, text, 40). Header: "Not enough memory." (subsystem $01), "Recoverable
; Alert." (bit 31 at 0, non-null high word), otherwise "Software Failure.". Preserves d1-d7/a0-a6.
AS_BUF          EQU 132
alert_show:
        movem.l d1-d3/a0-a3/a6,-(sp)
        lea     -AS_BUF(sp),sp
        move.l  d0,d2
        move.l  d1,d3
        move.l  ($4).w,a6
        lea     al_intname(pc),a1
        moveq   #0,d0
        jsr     LVO_OPENLIBRARY(a6)
        move.l  d0,a3
        tst.l   d0
        beq.s   .as_ret
        move.l  sp,a2
        move.l  #$00260F00,d0        ; x = 38, y = 15 (3 bytes)
        bsr     .as_pos
        lea     al_h3(pc),a0         ; header
        move.l  d2,d0
        swap    d0
        cmp.b   #$01,d0              ; subsystem AG_NoMemory
        bne.s   .as_h2
        lea     al_h1(pc),a0
        bra.s   .as_hd
.as_h2:
        tst.l   d2
        bmi.s   .as_hd
        tst.w   d0
        beq.s   .as_hd
        lea     al_h2(pc),a0
.as_hd:
        bsr.s   .as_str
        move.b  #$FF,(a2)+
        move.l  #$00EA0F00,d0        ; x = 234, y = 15
        bsr.s   .as_pos
        lea     al_press(pc),a0
        bsr.s   .as_str
        move.b  #$FF,(a2)+
        move.l  #$008E1E00,d0        ; x = 142, y = 30
        bsr.s   .as_pos
        lea     al_guru(pc),a0
        bsr.s   .as_strnz
        move.l  d2,d0
        bsr.s   .as_hex8
        move.b  #'.',(a2)+
        move.l  d3,d0
        bsr.s   .as_hex8
        clr.b   (a2)+
        clr.b   (a2)+                ; end of the string
        move.l  a3,a6
        moveq   #0,d0
        move.l  sp,a0
        moveq   #40,d1
        jsr     -90(a6)              ; DisplayAlert
        move.l  d0,d2
        move.l  a3,a1
        move.l  ($4).w,a6
        jsr     LVO_CLOSELIBRARY(a6)
        move.l  d2,d0
.as_ret:
        lea     AS_BUF(sp),sp
        movem.l (sp)+,d1-d3/a0-a3/a6
        rts
.as_pos:                             ; d0 = x (high word) and y (byte 3) -> 3 bytes
        rol.l   #8,d0
        move.b  d0,(a2)+
        rol.l   #8,d0
        move.b  d0,(a2)+
        rol.l   #8,d0
        move.b  d0,(a2)+
        rts
.as_str:                             ; string a0 with its 0
        move.b  (a0)+,(a2)+
        bne.s   .as_str
        rts
.as_strnz:                           ; string a0 without its 0
        move.b  (a0)+,(a2)+
        bne.s   .as_strnz
        subq.l  #1,a2
        rts
.as_hex8:                            ; d0 -> 8 upper-case hexadecimal digits
        moveq   #7,d1
.as_hx:
        rol.l   #4,d0
        moveq   #15,d2
        and.w   d0,d2
        move.b  al_digits(pc,d2.w),(a2)+
        dbra    d1,.as_hx
        rts
al_digits:
        dc.b    "0123456789ABCDEF"

; raw_puts(a0 = C string): serial output through RawPutChar. Clobbers d0/a0.
raw_puts:
        move.b  (a0)+,d0
        beq.s   .rp_ret
        bsr.s   exec_RawPutChar
        bra.s   raw_puts
.rp_ret:
        rts

; Polled serial I/O of exec, as in 1.3 (custom-chips-v34 §4.3). RawIOInit(): SERPER only (8 bits, no interrupt).
; RawMayGetChar() -> d0 = received character (7 bits, RBF acknowledged) | -1. RawPutChar(char d0): waits for TBE,
; sends the byte with one stop bit, then looks at the receiver: Ctrl-S holds the output until any other byte
; arrives, DEL calls Debug. Preserves d1-d2/a0/a1/a6.
exec_RawIOInit:
        move.w  #SERPER_RAW,SERPER
        rts
exec_RawMayGetChar:
        move.w  SERDATR,d0
        btst    #14,d0               ; RBF
        beq.s   .rg_none
        and.l   #$7F,d0
        move.w  #INTF_RBF,INTREQ
        rts
.rg_none:
        moveq   #-1,d0
        rts
exec_RawPutChar:
        movem.l d1-d2/a0-a1/a6,-(sp)
.rpc_wt:
        btst    #13-8,SERDATR        ; TBE
        beq.s   .rpc_wt
        and.w   #$FF,d0
        or.w    #$100,d0
        move.w  d0,SERDAT
        bsr.s   exec_RawMayGetChar
        cmp.b   #$13,d0              ; Ctrl-S (XOFF): hold until any other byte
        bne.s   .rpc_del
.rpc_xoff:
        bsr.s   exec_RawMayGetChar
        tst.l   d0
        bmi.s   .rpc_xoff
        bra.s   .rpc_ret
.rpc_del:
        cmp.b   #$7F,d0
        bne.s   .rpc_ret
        move.l  ($4).w,a6
        jsr     -114(a6)             ; Debug
.rpc_ret:
        movem.l (sp)+,d1-d2/a0-a1/a6
        rts

; ============================ scheduling entries (exec-scheduling-v34 §2) ============================
; The scheduler core (Schedule, Switch, Dispatch, the dispatcher) is in interrupts.s. These entries reach it only
; through vectors or absolute jumps, so they live here, linked after trackdisk: boot.s reaches trackdisk with
; 16-bit branches and the modules linked between them must stay small.

; ExitIntr (-36): entry = the 1.3 autovector frame: D0, D1, A0, A1, A5, A6 (24 bytes) above {SR, PC}. Resumes the
; interrupted code unless it was a task in user mode, switching is allowed and a reschedule is pending (SAR).
; Our own autovector handlers use the 60-byte frame and intr_exit; this entry serves code built for the 1.3 frame.
exec_ExitIntr:
        btst    #5,24(sp)           ; S bit of the stacked SR
        bne.s   .ei_resume
        move.l  ($4).w,a6
        tst.b   EB_TDNEST(a6)
        bge.s   .ei_resume
        btst    #SFB_SAR,EB_SYSFLAGS(a6)
        beq.s   .ei_resume
        move.w  #$2000,sr
        movem.l (sp)+,d0/d1/a0/a1/a5/a6
        jmp     exec_Schedule       ; the body of Schedule, not its vector (§1)
.ei_resume:
        movem.l (sp)+,d0/d1/a0/a1/a5/a6
        rte

; Reschedule (-48): a6 = ExecBase, d0 destroyed. Sets SAR. Under Forbid: nothing more (Permit or the next
; interrupt exit switches). Interrupts enabled: from user mode, Schedule through its vector; from supervisor mode
; (interrupt code), return at once (the interrupt exit schedules). Disabled: if SAR was clear, post a software
; interrupt so that the switch happens when Enable lets level 1 in.
exec_Reschedule:
        bset    #SFB_SAR,EB_SYSFLAGS(a6)
        sne     d0                  ; d0 = $FF: SAR was already set
        tst.b   EB_TDNEST(a6)
        bge.s   .rs_ret
        tst.b   EB_IDNEST(a6)
        bge.s   .rs_dis
        EXEC_SVC svc_schedule
.rs_ret:
        rts
.rs_dis:
        tst.b   d0
        bne.s   .rs_ret
        move.w  #(INTF_SETCLR|INTF_SOFTINT),INTREQ
        rts

; Exception (-66): in 1.3 an internal step of the dispatcher that nobody calls through the vector (§1, §5); the
; dispatcher here runs it directly too (dispatch_in). A direct call gets a safe meaning: when the running task has
; an exception pending, ask for the reschedule that delivers it.
exec_Exception:
        move.l  EB_THISTASK(a6),a0
        btst    #TB_EXCEPT,TC_FLAGS(a0)
        beq.s   .ex_ret
        jmp     LVO_RESCHEDULE(a6)
.ex_ret:
        rts

; svc_schedule / svc_switch (EXEC_SVC services): from a task (user frame), go to Schedule / Switch through the
; vector; from supervisor mode, return at once (no user context to switch, as the 1.3 Supervisor path).
svc_schedule:
        btst    #5,(sp)
        bne.s   svc_rte
        move.l  ($4).w,-(sp)         ; jump through the vector, frame and registers untouched
        add.l   #LVO_SCHEDULE,(sp)
        rts
svc_switch:
        btst    #5,(sp)
        bne.s   svc_rte
        move.l  ($4).w,-(sp)
        add.l   #LVO_SWITCH,(sp)
        rts
svc_rte:
        rte

; except_default: default tc_ExceptCode (ExecBase TaskExceptCode): re-arms nothing.
except_default:
        moveq   #0,d0
        rts

; task_exit_default: ExecBase TaskExitCode, the final PC of a task added with finalPC 0 (its code returned, user
; mode): RemTask(self).
task_exit_default:
        move.l  ($4).w,a6
        sub.l   a1,a1
        jmp     LVO_REMTASK(a6)

; Debug() (exec-scheduling-v34 §9): a polled serial monitor in supervisor mode, entered through Supervisor (EXEC_SVC).
; Saves every register, INTENAR, then INTENA $0801 (TBE and RBF off), RawIOInit, banner "rom-wack". Commands
; (echoed): 'r' shows the registers of the caller, 'g' resumes it (RTE, registers preserved). On exit INTENA gets
; the saved TBE/RBF bits WITHOUT the SET bit, as in 1.3: the write can only clear, TBE and RBF stay disabled.
; Output does not go through RawPutChar, which would swallow the next command byte while looking for ^S / DEL.
; Only this command subset of ROM-Wack is provided.
exec_Debug:
        EXEC_SVC debug_entry
        rts

; Frame built on the SSP by debug_entry (offsets from sp after the last push):
DBG_INTENA      EQU 0                ; word: INTENAR at entry
DBG_USP         EQU 2
DBG_REGS        EQU 6                ; D0-D7/A0-A6, then the "reason" long 0 (+66)
DBG_SR          EQU 70               ; the {SR, PC} frame of the entry
DBG_PC          EQU 72
debug_entry:
        clr.l   -(sp)                ; reason 0
        movem.l d0-d7/a0-a6,-(sp)
        move.l  usp,a0
        move.l  a0,-(sp)
        move.w  INTENAR,-(sp)
        move.w  #$0801,INTENA        ; TBE and RBF off for the session
        bsr     exec_RawIOInit
        lea     dbg_banner(pc),a0
        bsr     dbg_puts
.db_cmd:
        lea     dbg_prompt(pc),a0
        bsr     dbg_puts
.db_get:
        bsr     exec_RawMayGetChar
        tst.l   d0
        bmi.s   .db_get
        bsr     dbg_putc             ; echo
        cmp.b   #'g',d0
        beq.s   .db_go
        cmp.b   #'r',d0
        bne.s   .db_cmd
        lea     dbg_dregs(pc),a0
        bsr     dbg_puts
        lea     DBG_REGS(sp),a1
        moveq   #7,d2
.db_d:
        move.l  (a1)+,d0
        bsr     dbg_hex8
        dbra    d2,.db_d
        lea     dbg_aregs(pc),a0
        bsr     dbg_puts
        moveq   #6,d2
.db_a:
        move.l  (a1)+,d0
        bsr     dbg_hex8
        dbra    d2,.db_a
        lea     dbg_misc(pc),a0      ; USP, PC, SR of the caller
        bsr     dbg_puts
        move.l  DBG_USP(sp),d0
        bsr     dbg_hex8
        move.l  DBG_PC(sp),d0
        bsr     dbg_hex8
        moveq   #0,d0
        move.w  DBG_SR(sp),d0
        bsr     dbg_hex8
        bra.s   .db_cmd
.db_go:
        lea     dbg_crlf(pc),a0
        bsr     dbg_puts
        move.w  (sp)+,d0
        and.w   #$0801,d0            ; no SET bit: can only clear TBE/RBF
        move.w  d0,INTENA
        move.l  (sp)+,a0
        move.l  a0,usp
        movem.l (sp)+,d0-d7/a0-a6
        addq.l  #4,sp                ; reason
        rte

; dbg_puts(a0) / dbg_putc(d0.b) / dbg_hex8(d0.l + space): polled transmitter only. dbg_putc preserves d0.
; Clobbers d1/a0 (dbg_hex8: d0/d1/d3/a0).
dbg_puts:
        move.b  (a0)+,d0
        beq.s   .dp_ret
        bsr.s   dbg_putc
        bra.s   dbg_puts
.dp_ret:
        rts
dbg_putc:
        btst    #13-8,SERDATR        ; TBE
        beq.s   dbg_putc
        moveq   #0,d1
        move.b  d0,d1
        or.w    #$100,d1
        move.w  d1,SERDAT
        rts
dbg_hex8:
        move.l  d0,d3
        moveq   #7,d1
.dh_lp:
        rol.l   #4,d3
        moveq   #15,d0
        and.w   d3,d0
        lea     al_digits(pc),a0
        move.b  0(a0,d0.w),d0
        move.w  d1,-(sp)
        bsr.s   dbg_putc
        move.w  (sp)+,d1
        dbra    d1,.dh_lp
        moveq   #' ',d0
        bra.s   dbg_putc

; SumKickData() -> d0 (exec-scheduling-v34 §7): $FFFFFFFF plus, 32-bit wrapping, every long of each KickMemPtr
; MemList (node header, ml_NumEntries word pair and the MemEntries: 2*NumEntries+4 longs) and every ROMTag
; POINTER of the KickTagPtr table (0 = end, bit 31 = link to the next table, not summed). Both pointers read
; 0 during the computation and are written back. Clobbers d1/a0.
exec_SumKickData:
        movem.l d2/a1-a2,-(sp)
        move.l  EB_KICKMEMPTR(a6),a1
        move.l  EB_KICKTAGPTR(a6),a2
        clr.l   EB_KICKMEMPTR(a6)
        clr.l   EB_KICKTAGPTR(a6)
        moveq   #-1,d0
        move.l  a1,d1
.sk_ml:
        beq.s   .sk_tags
        move.l  d1,a0
        move.w  ML_NUMENTRIES(a0),d2
        add.w   d2,d2
        addq.w  #3,d2                ; 2*n+4 longs, dbra count
.sk_mll:
        add.l   (a0)+,d0
        dbra    d2,.sk_mll
        move.l  d1,a0
        move.l  (a0),d1              ; LN_SUCC
        bra.s   .sk_ml
.sk_tags:
        move.l  a2,d1
        beq.s   .sk_end
        move.l  d1,a0
.sk_tl:
        move.l  (a0)+,d1
        beq.s   .sk_end
        bpl.s   .sk_tag
        bclr    #31,d1
        move.l  d1,a0
        bra.s   .sk_tl
.sk_tag:
        add.l   d1,d0
        bra.s   .sk_tl
.sk_end:
        move.l  a1,EB_KICKMEMPTR(a6)
        move.l  a2,EB_KICKTAGPTR(a6)
        movem.l (sp)+,d2/a1-a2
        rts

; SetSR(newSR d0, mask d1) -> d0 = old SR: the bits of mask take the value of newSR (via Supervisor; the SR
; pushed by the trap is modified then restored by RTE).
exec_SetSR:
        move.l  a5,-(sp)
        lea     .sr_super(pc),a5
        jsr     LVO_SUPERVISOR_X(a6)
        move.l  (sp)+,a5
        rts
.sr_super:
        move.w  (sp),a1              ; old SR
        and.w   d1,d0
        not.w   d1
        and.w   d1,(sp)
        or.w    d0,(sp)
        move.w  a1,d0
        and.l   #$FFFF,d0
        rte

; SuperState() -> d0 = supervisor stack to give back to UserState (0 if already in supervisor): what follows runs in
; supervisor on the user stack.
exec_SuperState:
        move.w  sr,d0
        btst    #13,d0
        bne.s   .su_already
        move.l  a5,a1
        lea     .su_super(pc),a5
        jsr     LVO_SUPERVISOR_X(a6) ; comes back in supervisor through .su_super
        rts
.su_already:
        moveq   #0,d0
        rts
.su_super:
        move.l  a1,a5
        move.l  2(sp),a0             ; resume: after the Supervisor trap
        addq.l  #6,sp                ; trap frame removed
        move.l  sp,d0                ; supervisor stack
        move.l  usp,a1
        move.l  a1,sp                ; we continue on the user stack
        jmp     (a0)

; UserState(sysStack d0): return to user mode on the current stack, the supervisor stack becomes sysStack again.
; d0 = 0 (SuperState called in supervisor): nothing to do.
exec_UserState:
        tst.l   d0
        beq.s   .us_ret
        move.l  (sp)+,a0
        move.l  sp,a1
        move.l  a1,usp
        move.l  d0,sp
        and.w   #$DFFF,sr
        jmp     (a0)
.us_ret:
        rts

; GetCC() -> d0 = condition codes (68000: MOVE from SR allowed in user mode).
exec_GetCC:
        move.w  sr,d0
        and.l   #$FF,d0
        rts

; RemIntServer(intNum d0, interrupt a1): the server leaves its chain, interrupts masked during the removal. When the
; chain becomes empty its source is disabled (AutoDocs). The 1.3 exec clears a wrong bit there (custom-chips-v34
; §3.1); the documented behaviour is kept instead.
exec_RemIntServer:
        move.w  INTENAR,d1
        move.w  #INTF_INTEN,INTENA
        movem.l d0-d1,-(sp)
        jsr     LVO_REMOVE(a6)
        move.l  (sp),d0              ; d0 = number (d1 = saved INTENAR stays on the stack)
        move.w  d0,d1
        mulu    #IV_SIZE,d1
        lea     EB_INTVECTS(a6,d1.l),a0
        cmp.l   #intr_chain_walker,IV_CODE(a0)
        bne.s   .ri_on
        move.l  IV_DATA(a0),a0       ; &svlist[n]
        cmp.l   LH_TAILPRED(a0),a0   ; empty list: lh_TailPred == &lh_Head
        bne.s   .ri_on
        moveq   #0,d1
        bset    d0,d1
        move.w  d1,INTENA            ; CLR the chain's source
.ri_on:
        movem.l (sp)+,d0-d1
        btst    #INTENA_INTEN,d1
        beq.s   .ri_ret
        move.w  #(INTF_SETCLR|INTF_INTEN),INTENA
.ri_ret:
        rts

; AllocEntry(memList a0) -> d0 = new MemList (addresses filled in) | requirements of the failing entry with bit 31
; set (nothing remains allocated). FreeEntry(memList a0) frees the entries then the MemList (a0 like AllocEntry:
; exec_lib.fd; icon.library chains RemHead -> FreeEntry with the MemList in a0 and the list still in a1).
exec_AllocEntry:
        movem.l d2-d3/a2-a3,-(sp)
        move.l  a0,a2                ; a2 = template
        moveq   #0,d2
        move.w  ML_NUMENTRIES(a2),d2
        move.l  d2,d0
        lsl.l   #3,d0
        add.l   #ML_ME,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.s   .ae_nolist
        move.l  d0,a3                ; a3 = copy
        move.w  d2,ML_NUMENTRIES(a3)
        moveq   #0,d3                ; d3 = allocated entries
.ae_lp:
        cmp.w   d2,d3
        beq.s   .ae_ok
        move.l  d3,d0
        lsl.l   #3,d0
        lea     ML_ME(a2,d0.l),a0
        lea     ML_ME(a3,d0.l),a1
        move.l  4(a0),4(a1)          ; me_Length
        move.l  (a0),-(sp)           ; me_Reqs
        move.l  4(a0),d0
        move.l  (sp),d1
        move.l  a1,-(sp)
        jsr     LVO_ALLOCMEM(a6)
        move.l  (sp)+,a1
        move.l  (sp)+,d1
        tst.l   d0
        beq.s   .ae_fail
        move.l  d0,(a1)              ; me_Addr
        addq.w  #1,d3
        bra.s   .ae_lp
.ae_ok:
        move.l  a3,d0
        bra.s   .ae_ret
.ae_fail:
        move.l  d1,-(sp)             ; failing requirements
        move.w  d3,ML_NUMENTRIES(a3) ; only the obtained entries are returned
        move.l  a3,a0
        bsr.s   exec_FreeEntry
        move.l  (sp)+,d0
        bset    #31,d0
        bra.s   .ae_ret
.ae_nolist:
        moveq   #-1,d0               ; the MemList itself could not be allocated
.ae_ret:
        movem.l (sp)+,d2-d3/a2-a3
        rts
exec_FreeEntry:
        movem.l d2/a2,-(sp)
        move.l  a0,a2
        moveq   #0,d2
        move.w  ML_NUMENTRIES(a2),d2
        lea     ML_ME(a2),a0
        bra.s   .fe_nx
.fe_lp:
        move.l  (a0)+,a1
        move.l  (a0)+,d0
        move.l  a0,-(sp)
        jsr     LVO_FREEMEM(a6)
        move.l  (sp)+,a0
.fe_nx:
        dbra    d2,.fe_lp
        moveq   #0,d0
        move.w  ML_NUMENTRIES(a2),d0
        lsl.l   #3,d0
        add.l   #ML_ME,d0
        move.l  a2,a1
        jsr     LVO_FREEMEM(a6)
        movem.l (sp)+,d2/a2
        rts

; SetExcept(newSignals d0, signalMask d1) -> d0 = old tc_SigExcept (bits of mask replaced), under a bare Disable.
; A signal already received that is now an exception signal: TB_EXCEPT + Reschedule (exec-scheduling-v34 §2.7).
exec_SetExcept:
        move.l  d2,-(sp)
        addq.b  #1,EB_IDNEST(a6)
        move.w  #INTF_INTEN,INTENA
        move.l  EB_THISTASK(a6),a0
        move.l  TC_SIGEXCEPT(a0),d2
        and.l   d1,d0
        not.l   d1
        and.l   d2,d1
        or.l    d1,d0
        move.l  d0,TC_SIGEXCEPT(a0)
        bsr     task_excpending
        move.l  d2,d0
        move.l  (sp)+,d2
        rts

; AllocTrap(trapNum d0 | -1 = any) -> d0 = trap number granted to the task | -1. FreeTrap(trapNum d0).
exec_AllocTrap:
        move.l  EB_THISTASK(a6),a0
        move.w  TC_TRAPALLOC(a0),d1
        cmp.l   #-1,d0
        bne.s   .at_one
        moveq   #15,d0
.at_lp:
        btst    d0,d1
        beq.s   .at_got
        dbra    d0,.at_lp
        bra.s   .at_fail
.at_one:
        cmp.l   #15,d0
        bhi.s   .at_fail
        btst    d0,d1
        bne.s   .at_fail
.at_got:
        bset    d0,d1
        move.w  d1,TC_TRAPALLOC(a0)
        ext.l   d0
        rts
.at_fail:
        moveq   #-1,d0
        rts
exec_FreeTrap:
        move.l  EB_THISTASK(a6),a0
        move.w  TC_TRAPALLOC(a0),d1
        bclr    d0,d1
        move.w  d1,TC_TRAPALLOC(a0)
        rts

; RemResource(resource a1): removal from the resource list, under Forbid.
exec_RemResource:
        jsr     LVO_FORBID(a6)
        jsr     LVO_REMOVE(a6)
        jmp     LVO_PERMIT(a6)

; ObtainSemaphoreList(list a0) / ReleaseSemaphoreList(list a0): each SignalSemaphore of the list, in order.
exec_ObtainSemaphoreList:
        move.l  #LVO_OBTAINSEMAPHORE,d0
        bra.s   sem_walk
exec_ReleaseSemaphoreList:
        move.l  #LVO_RELEASESEMAPHORE,d0
sem_walk:
        movem.l d2/a2,-(sp)
        move.l  d0,d2
        move.l  (a0),a2
.sw_lp:
        tst.l   (a2)
        beq.s   .sw_ret
        move.l  a2,a0
        jsr     0(a6,d2.l)
        move.l  (a2),a2
        bra.s   .sw_lp
.sw_ret:
        movem.l (sp)+,d2/a2
        rts

softint_is:
        dcb.b   IS_DATA,0
        dc.l    0                    ; IS_DATA
        dc.l    softint_server       ; IS_CODE
al_dead:
        dc.b    10,"Software Failure ALERT ",0
al_rec:
        dc.b    10,"Recoverable Alert ",0
al_intname:
        dc.b    "intuition.library",0
al_h1:
        dc.b    "Not enough memory. ",0
al_h2:
        dc.b    "Recoverable Alert. ",0
al_h3:
        dc.b    "Software Failure. ",0
al_press:
        dc.b    "Press left mouse button to continue.",0
al_guru:
        dc.b    "Guru Meditation #",0
dbg_banner:
        dc.b    10,"rom-wack",13,10,0
dbg_prompt:
        dc.b    13,10,"> ",0
dbg_dregs:
        dc.b    13,10,"D ",0
dbg_aregs:
        dc.b    13,10,"A ",0
dbg_misc:
        dc.b    13,10,"USP/PC/SR ",0
dbg_crlf:
        dc.b    13,10,0
        even
