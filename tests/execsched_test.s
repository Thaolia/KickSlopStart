; tests/execsched_test.s - exec scheduling LVOs (implementation-side test of docs/analysis/exec-scheduling-v34.md):
; Reschedule, Schedule, ExitIntr, Switch hooks, Dispatch (RemTask of self through TaskExitCode), task exceptions,
; the saved context layout, SetTaskPri, Procure/Vacate, SumKickData, Debug. Run from a startup-sequence
; (tests/garea_probe.sh <rom> <exe> <out>); results on the serial port. Debug waits for serial input: send "r"
; then "g" once "rom-wack" appears. Expected:
;   TDN n                        Forbid nesting the command started with (dev ROM shell: 1), undone meanwhile
;   RSC 0000000x 00000001 S06    a pri-0 task added under Disable; Reschedule() from pri 0 runs it at once
;                                (>= rule); its code returned -> RemTask(self) -> Dispatch: state 6. The first
;                                value is 1 when an interrupt pending during the Disable ran a schedule check at
;                                Enable (same >= rule; seen on the dev ROM, whose demo tasks keep it busy)
;   STP 00000000 00000001        SetTaskPri(self, same) returns the old pri (0) and yields to the equal ready task
;   EXI 00000000 R1 00000001 R1   ExitIntr with SAR clear: resumes, registers kept (R1); with
;                                SAR set and an equal ready task: switches to it, then resumes (R1)
;   SCH 00000001                 Schedule from a Supervisor routine switches to the equal ready task
;   HKS 00000004 00000004 00000003 00000000 000000C0   tc_Launch / tc_Switch calls, wake-ups, A3 mismatches,
;                                D0 (tc_Flags) seen by tc_Launch
;   CTX <pc> <sr> A6 <ret>       context of a waiting task: PC in ROM, SR user mode (S clear), A6 slot = ExecBase, long at
;                                +$42 = the return address of its Wait call
;   EXC 00010000 12345678 0000 FFFFFFF8 00000001 00010000 04 00000000 00000002   handler D0, A1, SR,
;                                USP - tc_SPReg, calls after one signal, re-armed SigExcept, state WAIT, exception
;                                bits left in SigRecvd, calls after a 2nd signal
;   PRI 000000FF                 SetTaskPri returns the old priority zero-extended
;   SEM 00000001 0000 00000000 0001 07 0000 0000 FFFF   Procure/Vacate vectors (§6)
;   SKD FFFFFFFF <P-1> <P+Q-1> <ml> 00 expect ...  SumKickData vectors (§7), KickMemPtr restored (00), then
;                                the expected values computed by the test
;   DSP <dispcount delta> <idlecount>  DispCount increased; IdleCount counts idle wake-ups
;   DBG <intenar before> <after>  around Debug(): TBE/RBF ($0801) left disabled

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018
INTENA   EQU $DFF09A
INTENAR  EQU $DFF01C
TC_SIZE  EQU 92
STK      EQU 1024
SIGW     EQU $00020000              ; signal a test task waits on
SIGE     EQU $00010000              ; exception signal

start:  move.l  4.w,a6
        move.l  a6,execb
        move.l  $114(a6),me             ; ThisTask
        move.l  me,a1
        moveq   #0,d0
        jsr     -300(a6)                ; SetTaskPri(self, 0)
        move.l  d0,oldpri
        move.l  $11C(a6),disp0
        moveq   #0,d7                   ; the dev ROM shell runs commands under Forbid (ser_lock): undo it here,
.unf:   tst.b   $127(a6)                ; redo it at the end (scheduling needs TDNestCnt -1)
        bmi.s   .unf2
        jsr     -138(a6)                ; Permit
        addq.l  #1,d7
        bra.s   .unf
.unf2:  move.l  d7,nforbid
        lea     m_tdn(pc),a0
        bsr     puts
        move.l  d7,d0
        bsr     hex8

        ; --- RSC: Reschedule (-48)
        clr.l   flag
        jsr     -120(a6)                ; Disable: no interrupt wakes a higher task meanwhile
        lea     tcbA,a1
        lea     bodyflag(pc),a2
        moveq   #0,d0
        lea     stkA,a0
        bsr     mktask
        jsr     -126(a6)                ; Enable
        move.l  flag,d4
        jsr     -48(a6)                 ; Reschedule
        lea     m_rsc(pc),a0
        bsr     puts
        move.l  d4,d0
        bsr     hex8
        move.l  flag,d0
        bsr     hex8
        lea     m_s(pc),a0
        bsr     puts
        lea     tcbA,a0
        move.b  15(a0),d0
        bsr     hex2
        bsr     nl

        bsr     cleanA
        ; --- STP: SetTaskPri(self, same) yields
        clr.l   flag
        jsr     -132(a6)
        lea     tcbA,a1
        lea     bodyflag(pc),a2
        moveq   #0,d0
        lea     stkA,a0
        bsr     mktask
        jsr     -138(a6)
        move.l  me,a1
        moveq   #0,d0
        jsr     -300(a6)
        move.l  d0,d4
        lea     m_stp(pc),a0
        bsr     puts
        move.l  d4,d0
        bsr     hex8
        move.l  flag,d0
        bsr     hex8
        bsr     nl

        bsr     cleanA
        ; --- EXI: ExitIntr (-36) with SAR clear, then with SAR set and an equal ready task
        lea     m_exi(pc),a0
        bsr     puts
        clr.l   flag
        lea     exi_clr(pc),a5
        bsr     supreg
        moveq   #0,d5
        jsr     -132(a6)
        lea     tcbA,a1
        lea     bodyflag(pc),a2
        moveq   #0,d0
        lea     stkA,a0
        bsr     mktask
        jsr     -138(a6)
        lea     exi_set(pc),a5
        bsr     supreg
        bsr     nl

        bsr     cleanA
        ; --- SCH: Schedule (-42) from a Supervisor routine
        clr.l   flag
        jsr     -132(a6)
        lea     tcbA,a1
        lea     bodyflag(pc),a2
        moveq   #0,d0
        lea     stkA,a0
        bsr     mktask
        jsr     -138(a6)
        lea     sch_sup(pc),a5
        jsr     -30(a6)                 ; Supervisor
        lea     m_sch(pc),a0
        bsr     puts
        move.l  flag,d0
        bsr     hex8
        bsr     nl

        bsr     cleanA
        ; --- HKS: tc_Launch / tc_Switch hooks on a pri-1 task that waits
        clr.l   nlaunch
        clr.l   nswitch
        clr.l   nwake
        clr.l   badA3
        jsr     -132(a6)
        lea     tcbC,a1
        lea     bodywait(pc),a2
        moveq   #1,d0
        lea     stkC,a0
        bsr     mktask
        lea     tcbC,a1
        move.l  #hook_switch,66(a1)     ; tc_Switch
        move.l  #hook_launch,70(a1)     ; tc_Launch
        or.b    #$C0,14(a1)             ; TF_LAUNCH|TF_SWITCH
        jsr     -138(a6)
        jsr     -48(a6)                 ; Reschedule: it runs and waits
        moveq   #2,d7
.hk:    jsr     -132(a6)
        lea     tcbC,a1
        move.l  #SIGW,d0
        jsr     -324(a6)                ; Signal
        jsr     -138(a6)                ; Permit: the woken pri-1 task runs now
        dbra    d7,.hk
        lea     m_hks(pc),a0
        bsr     puts
        move.l  nlaunch,d0
        bsr     hex8
        move.l  nswitch,d0
        bsr     hex8
        move.l  nwake,d0
        bsr     hex8
        move.l  badA3,d0
        bsr     hex8
        move.l  lflags,d0
        bsr     hex8
        bsr     nl

        ; --- CTX: saved context of the waiting task
        lea     m_ctx(pc),a0
        bsr     puts
        lea     tcbC,a2
        move.l  54(a2),a2               ; tc_SPReg
        move.l  (a2),d0                 ; PC
        bsr     hex8
        move.w  4(a2),d0                ; SR
        bsr     hex4
        lea     m_a6n(pc),a0
        cmp.l   $3E(a2),a6              ; A6 slot
        bne.s   .c1
        lea     m_a6y(pc),a0
.c1:    bsr     puts
        move.l  $42(a2),d0              ; long above the context
        bsr     hex8
        lea     m_wret(pc),a0
        bsr     puts
        lea     wait_ret(pc),a0
        move.l  a0,d0
        bsr     hex8
        bsr     nl
        lea     tcbC,a1
        jsr     -288(a6)                ; RemTask (another task)

        ; --- EXC: exception of a waiting task
        clr.l   ncalls
        lea     tcbD,a1
        move.l  #$12345678,38(a1)       ; tc_ExceptData (set before mktask: kept, tcb not cleared there)
        move.l  #handlerD,42(a1)        ; tc_ExceptCode
        jsr     -132(a6)
        lea     tcbD,a1
        lea     bodyexc(pc),a2
        moveq   #1,d0
        lea     stkD,a0
        bsr     mktask2
        jsr     -138(a6)
        jsr     -48(a6)                 ; it runs, SetExcept, Wait
        lea     tcbD,a1
        move.l  #SIGE,d0
        jsr     -324(a6)                ; Signal with the exception signal: handler runs at once
        move.l  ncalls,d6
        lea     tcbD,a1
        move.l  #SIGE,d0
        jsr     -324(a6)                ; 2nd time: re-armed by the handler's return value
        lea     m_exc(pc),a0
        bsr     puts
        move.l  hd0,d0
        bsr     hex8
        move.l  ha1,d0
        bsr     hex8
        move.w  hsr,d0
        bsr     hex4
        move.l  hsp,d0
        sub.l   hspreg,d0
        bsr     hex8
        move.l  d6,d0
        bsr     hex8
        lea     tcbD,a1
        move.l  30(a1),d0               ; tc_SigExcept
        bsr     hex8
        lea     tcbD,a1
        move.b  15(a1),d0
        bsr     hex2
        lea     tcbD,a1
        move.l  26(a1),d0
        and.l   #SIGE,d0
        bsr     hex8
        move.l  ncalls,d0
        bsr     hex8
        bsr     nl
        lea     tcbD,a1
        jsr     -288(a6)

        ; --- PRI: SetTaskPri on a task outside the lists
        lea     tcbE,a1
        move.b  #-1,9(a1)
        moveq   #3,d0
        jsr     -300(a6)
        move.l  d0,d4
        lea     m_pri(pc),a0
        bsr     puts
        move.l  d4,d0
        bsr     hex8
        bsr     nl

        ; --- SEM: Procure / Vacate on a V34 message semaphore (reply port = rport, PA_IGNORE)
        lea     sem,a0
        bsr     initport
        move.w  #-1,34(a0)              ; sm_Bids
        lea     rport,a0
        bsr     initport
        lea     m1,a0
        move.l  #rport,14(a0)           ; mn_ReplyPort
        lea     m2,a0
        move.l  #rport,14(a0)
        lea     m_sem(pc),a0
        bsr     puts
        lea     sem,a0
        lea     m1,a1
        jsr     -540(a6)                ; Procure(m1) -> 1
        bsr     hex8
        move.w  sem+34,d0
        bsr     hex4
        lea     sem,a0
        lea     m2,a1
        jsr     -540(a6)                ; Procure(m2) -> 0
        bsr     hex8
        move.w  sem+34,d0
        bsr     hex4
        lea     sem,a0
        jsr     -546(a6)                ; Vacate -> m2 replied, sm_LockMsg = m2
        lea     m2,a0
        move.b  8(a0),d0                ; LN_TYPE (NT_REPLYMSG = 7)
        bsr     hex2
        move.w  sem+34,d0
        bsr     hex4
        moveq   #0,d0
        move.l  sem+16,d1
        cmp.l   #m2,d1
        beq.s   .s1
        moveq   #-1,d0
.s1:    bsr     hex4                    ; 0000: sm_LockMsg = m2
        lea     sem,a0
        jsr     -546(a6)                ; Vacate -> free
        move.w  sem+34,d0
        bsr     hex4
        tst.l   sem+16
        beq.s   .s2
        lea     m_bad(pc),a0
        bsr     puts
.s2:    bsr     nl

        ; --- SKD: SumKickData (-612)
        lea     m_skd(pc),a0
        bsr     puts
        jsr     -132(a6)
        jsr     -612(a6)                ; both pointers 0
        move.l  d0,r1
        move.l  #tag1,$226(a6)          ; {P, 0}
        jsr     -612(a6)
        move.l  d0,r2
        move.l  #tag2,$226(a6)          ; {P, $80000000|tag3}, tag3 = {Q, 0}
        jsr     -612(a6)
        move.l  d0,r3
        clr.l   $226(a6)
        move.l  #kml,$222(a6)           ; one MemList, 1 entry
        jsr     -612(a6)
        move.l  d0,r4
        move.l  $222(a6),d5
        clr.l   $222(a6)
        jsr     -138(a6)
        move.l  r1,d0
        bsr     hex8
        move.l  r2,d0
        bsr     hex8
        move.l  r3,d0
        bsr     hex8
        move.l  r4,d0
        bsr     hex8
        moveq   #0,d0                   ; 0 = KickMemPtr written back unchanged
        cmp.l   #kml,d5
        beq.s   .k1
        moveq   #1,d0
.k1:    bsr     hex2
        lea     m_skx(pc),a0            ; expected values, computed here
        bsr     puts
        moveq   #-1,d0
        add.l   #$00FC1234,d0
        bsr     hex8
        moveq   #-1,d0
        add.l   #$00FC1234,d0
        add.l   #$00FC5678,d0
        bsr     hex8
        moveq   #-1,d0
        lea     kml,a0
        moveq   #5,d1
.k2:    add.l   (a0)+,d0
        dbra    d1,.k2
        bsr     hex8
        bsr     nl

        ; --- DSP: counters
        lea     m_dsp(pc),a0
        bsr     puts
        move.l  $11C(a6),d0
        sub.l   disp0,d0
        bsr     hex8
        move.l  $118(a6),d0
        bsr     hex8
        bsr     nl

        ; --- DBG: Debug() then INTENA (TBE/RBF left off)
        move.w  #$8801,INTENA           ; TBE+RBF on, to see Debug clear them
        lea     m_dbg(pc),a0
        bsr     puts
        move.w  INTENAR,d0
        bsr     hex4
        bsr     nl
        jsr     -114(a6)                ; Debug
        lea     m_dbg2(pc),a0
        bsr     puts
        move.w  INTENAR,d0
        bsr     hex4
        bsr     nl

        move.l  me,a1
        move.l  oldpri,d0
        jsr     -300(a6)
        move.l  nforbid,d7
        bra.s   .ref2
.ref:   jsr     -132(a6)                ; Forbid: back to the shell's nesting
.ref2:  dbra    d7,.ref
        lea     m_end(pc),a0
        bsr     puts
        moveq   #0,d0
        rts

; cleanA: a test task A that did not run is still listed: RemTask it before tcbA is reused.
cleanA: lea     tcbA,a1
        cmp.b   #6,15(a1)               ; TS_REMOVED
        beq.s   .ca
        lea     m_nrun(pc),a0
        bsr     puts
        lea     tcbA,a1
        jsr     -288(a6)
.ca:    rts

; supreg: runs the Supervisor routine a5 with sentinel registers; prints the flag and R1 when d0/d1/a0/a1 are back.
supreg: move.l  #$D0D0D0D0,d0
        move.l  #$D1D1D1D1,d1
        move.l  #$A0A0A0A0,a0
        move.l  #$A1A1A1A1,a1
        jsr     -30(a6)                 ; Supervisor
        moveq   #0,d2
        cmp.l   #$D0D0D0D0,d0
        bne.s   .sr1
        cmp.l   #$D1D1D1D1,d1
        bne.s   .sr1
        cmp.l   #$A0A0A0A0,a0
        bne.s   .sr1
        cmp.l   #$A1A1A1A1,a1
        bne.s   .sr1
        moveq   #1,d2
.sr1:   move.l  flag,d0
        bsr     hex8
        lea     m_r(pc),a0
        bsr     puts
        move.l  d2,d0
        add.b   #'0',d0
        lea     hbuf,a0
        move.b  d0,(a0)+
        move.b  #' ',(a0)+
        clr.b   (a0)
        lea     hbuf,a0
        bra     puts

; Supervisor routines (supervisor mode, the {SR, PC} frame of Supervisor on the SSP, a6 = ExecBase).
exi_clr:
        move.w  #$2700,sr
        bclr    #7,$124(a6)             ; SAR clear
        movem.l d0/d1/a0/a1/a5/a6,-(sp) ; the 1.3 autovector frame
        jmp     -36(a6)                 ; ExitIntr
exi_set:
        move.w  #$2700,sr
        bset    #7,$124(a6)             ; SAR set
        movem.l d0/d1/a0/a1/a5/a6,-(sp)
        jmp     -36(a6)
sch_sup:
        jmp     -42(a6)                 ; Schedule

; mktask(a1 = tcb, a2 = initial PC, d0 = pri, a0 = stack of STK bytes): cleared TCB, AddTask(a1, a2, 0).
; mktask2: same without clearing the TCB (tc_ExceptCode/Data already set).
mktask: movem.l d0/a0-a1,-(sp)
        moveq   #TC_SIZE/4-1,d1
.mc:    clr.l   (a1)+
        dbra    d1,.mc
        movem.l (sp)+,d0/a0-a1
mktask2:
        move.b  #1,8(a1)                ; NT_TASK
        move.b  d0,9(a1)
        move.l  #tname,10(a1)
        move.l  a0,58(a1)               ; tc_SPLower
        lea     STK(a0),a0
        move.l  a0,62(a1)               ; tc_SPUpper
        move.l  #$FFFF,18(a1)           ; tc_SigAlloc
        lea     74(a1),a0               ; NEWLIST tc_MemEntry
        move.l  a0,8(a0)
        clr.l   4(a0)
        lea     4(a0),a3
        move.l  a3,(a0)
        sub.l   a3,a3                   ; finalPC 0 -> TaskExitCode
        jmp     -282(a6)                ; AddTask

; initport(a0): NT_MSGPORT, PA_IGNORE, empty message list, mp_SigTask 0.
initport:
        move.b  #4,8(a0)
        move.b  #2,14(a0)
        clr.l   16(a0)
        lea     20(a0),a1
        move.l  a1,8(a1)
        clr.l   4(a1)
        lea     4(a1),a3
        move.l  a3,(a1)
        rts

; Task bodies (user mode, registers 0 at entry).
bodyflag:
        move.l  #1,flag
        rts                             ; -> TaskExitCode -> RemTask(self)
bodywait:
        move.l  4.w,a6
bw_loop: move.l #SIGW,d0
        jsr     -318(a6)                ; Wait
wait_ret:
        addq.l  #1,nwake
        bra.s   bw_loop
bodyexc:
        move.l  4.w,a6
        move.l  #SIGE,d0
        move.l  d0,d1
        jsr     -312(a6)                ; SetExcept(SIGE, SIGE)
.be:    move.l  #SIGW,d0
        jsr     -318(a6)
        bra.s   .be

; Hooks (supervisor, A3 = task, A6 = ExecBase; tc_Launch also D0 = tc_Flags).
hook_launch:
        addq.l  #1,nlaunch
        move.l  d0,lflags
        cmp.l   #tcbC,a3
        beq.s   .hl
        addq.l  #1,badA3
.hl:    rts
hook_switch:
        addq.l  #1,nswitch
        cmp.l   #tcbC,a3
        beq.s   .hs
        addq.l  #1,badA3
.hs:    rts

; Exception handler (user mode): records D0, A1, SR, USP and tc_SPReg; returns D0 = signals to re-arm.
handlerD:
        move.w  sr,hsr
        move.l  sp,hsp
        move.l  d0,hd0
        move.l  a1,ha1
        move.l  a6,a0
        move.l  $114(a0),a0
        move.l  54(a0),hspreg
        addq.l  #1,ncalls
        rts                             ; d0 = SIGE: re-armed

nl:     lea     m_nl(pc),a0
; puts(a0): NUL-terminated string on the serial port. Clobbers d1/a0.
puts:   move.b  (a0)+,d1
        beq.s   .e
.w:     btst    #5,SERDATR              ; TBE (bit 13)
        beq.s   .w
        and.w   #$FF,d1
        or.w    #$100,d1
        move.w  d1,SERDAT
        bra.s   puts
.e:     rts
; hex8(d0.l) / hex4(d0.w) / hex2(d0.b): hex digits and a space. Clobbers d0/d1/a0.
hex8:   moveq   #7,d1
        bra.s   hexn
hex4:   swap    d0
        moveq   #3,d1
        bra.s   hexn
hex2:   ror.l   #8,d0
        moveq   #1,d1
hexn:   lea     hbuf,a0
.dg:    rol.l   #4,d0
        move.l  d0,-(sp)
        and.w   #15,d0
        move.b  hexd(pc,d0.w),(a0)+
        move.l  (sp)+,d0
        dbra    d1,.dg
        move.b  #' ',(a0)+
        clr.b   (a0)
        lea     hbuf,a0
        bra.s   puts
hexd:   dc.b    "0123456789ABCDEF"
tname:  dc.b    "execsched.task",0
m_tdn:  dc.b    13,10,"TDN ",0
m_nrun: dc.b    "(task A not run, removed)",13,10,0
m_rsc:  dc.b    13,10,"RSC ",0
m_s:    dc.b    "S",0
m_stp:  dc.b    "STP ",0
m_exi:  dc.b    "EXI ",0
m_r:    dc.b    "R",0
m_sch:  dc.b    "SCH ",0
m_hks:  dc.b    "HKS ",0
m_ctx:  dc.b    "CTX ",0
m_a6y:  dc.b    "A6 ",0
m_a6n:  dc.b    "a6? ",0
m_wret: dc.b    "wait_ret=",0
m_exc:  dc.b    "EXC ",0
m_pri:  dc.b    "PRI ",0
m_sem:  dc.b    "SEM ",0
m_bad:  dc.b    "LOCKMSG? ",0
m_skd:  dc.b    "SKD ",0
m_skx:  dc.b    "expect FFFFFFFF ",0
m_dsp:  dc.b    "DSP ",0
m_dbg:  dc.b    "DBG ",0
m_dbg2: dc.b    "DBG after ",0
m_nl:   dc.b    13,10,0
m_end:  dc.b    "EXECSCHED END GAP fin",13,10,0
        even

        section data,data
tag1:   dc.l    $00FC1234,0
tag2:   dc.l    $00FC1234,$80000000+tag3
tag3:   dc.l    $00FC5678,0
kml:    dc.l    0,0                     ; LN_SUCC 0 (end), LN_PRED
        dc.w    $0A00,0                 ; LN_TYPE/LN_PRI, LN_NAME high word
        dc.w    0,1                     ; LN_NAME low word, ml_NumEntries 1
        dc.l    $00012345,$00000100     ; me_Addr, me_Length

        section bss,bss
execb:  ds.l    1
me:     ds.l    1
oldpri: ds.l    1
nforbid: ds.l   1
disp0:  ds.l    1
flag:   ds.l    1
nlaunch: ds.l   1
nswitch: ds.l   1
nwake:  ds.l    1
badA3:  ds.l    1
lflags: ds.l    1
ncalls: ds.l    1
hd0:    ds.l    1
ha1:    ds.l    1
hsp:    ds.l    1
hspreg: ds.l    1
hsr:    ds.w    1
        ds.w    1
r1:     ds.l    1
r2:     ds.l    1
r3:     ds.l    1
r4:     ds.l    1
tcbA:   ds.b    TC_SIZE
tcbC:   ds.b    TC_SIZE
tcbD:   ds.b    TC_SIZE
tcbE:   ds.b    TC_SIZE
sem:    ds.b    36
rport:  ds.b    34
        ds.w    1
m1:     ds.b    20
m2:     ds.b    20
stkA:   ds.b    STK
stkC:   ds.b    STK
stkD:   ds.b    STK
hbuf:   ds.b    12
