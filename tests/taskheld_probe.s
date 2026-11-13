; tests/taskheld_probe.s - CLI command that takes a CPU exception, for the "Software error - task held" requester
; (implementation track, authored from the probe described in docs/analysis/task-held-v34.md §5; expected results
; in its §4). First letter of the argument:
;   (none) illegal instruction              z  divide by zero            f  line-F opcode       0  TRAP #0
;   w      pr_WindowPtr = -1, then illegal  t  tc_TrapCode = ExecBase TaskTrapCode, then illegal
;   a      a plain exec task (AddTask, no dos) executes the illegal instruction; the command returns
; Prints "TH <letter>" on its output before the fault. Run by tests/taskheld_probe.sh.
; Offsets: exec AllocMem -198, AddTask -282, Wait -318; ExecBase ThisTask 276, TaskTrapCode 304; Task
; tc_TrapCode 50, tc_SPLower 58, tc_SPUpper 62, tc_SPReg 54; Process pr_WindowPtr 184; dos Output -60, Write -48.

TASKSZ  EQU 1024

        section code,code
start:
        move.l  a0,a2
        move.l  d0,d2
        moveq   #' ',d3              ; letter (space = no argument)
        tst.l   d2
        beq.s   .noarg
        move.b  (a2),d3
        cmp.b   #10,d3
        bne.s   .noarg
        moveq   #' ',d3
.noarg:
        move.l  ($4).w,a6
        lea     dosname(pc),a1
        moveq   #0,d0
        jsr     -552(a6)             ; OpenLibrary
        move.l  d0,a5
        move.b  d3,msg_l
        move.l  a5,a6
        jsr     -60(a6)              ; Output
        move.l  d0,d1
        beq.s   .nomsg
        lea     msg(pc),a0
        move.l  a0,d2
        moveq   #msg_end-msg,d3
        jsr     -48(a6)              ; Write
.nomsg:
        move.l  ($4).w,a6
        move.l  276(a6),a3           ; ThisTask
        move.b  msg_l(pc),d3
        cmp.b   #'w',d3
        bne.s   .not_w
        moveq   #-1,d0
        move.l  d0,184(a3)           ; pr_WindowPtr = -1
        bra.s   .illegal
.not_w:
        cmp.b   #'t',d3
        bne.s   .not_t
        move.l  304(a6),50(a3)       ; tc_TrapCode = TaskTrapCode
        bra.s   .illegal
.not_t:
        cmp.b   #'z',d3
        bne.s   .not_z
        moveq   #0,d1
        divu    d1,d0
.not_z:
        cmp.b   #'f',d3
        bne.s   .not_f
        dc.w    $F000
.not_f:
        cmp.b   #'0',d3
        bne.s   .not_0
        trap    #0
.not_0:
        cmp.b   #'a',d3
        beq.s   .task
.illegal:
        illegal
        moveq   #0,d0
        rts
.task:
        move.l  #TASKSZ,d0
        move.l  #$10001,d1           ; MEMF_PUBLIC|MEMF_CLEAR
        jsr     -198(a6)
        tst.l   d0
        beq.s   .ret
        move.l  d0,a1
        move.b  #1,8(a1)             ; NT_TASK
        lea     tname(pc),a0
        move.l  a0,10(a1)
        lea     92(a1),a0
        move.l  a0,58(a1)            ; tc_SPLower
        lea     TASKSZ(a1),a0
        move.l  a0,62(a1)            ; tc_SPUpper
        move.l  a0,54(a1)            ; tc_SPReg
        lea     taskbody(pc),a2
        suba.l  a3,a3
        jsr     -282(a6)             ; AddTask
.ret:
        moveq   #0,d0
        rts
taskbody:
        illegal
.hang:
        moveq   #0,d0
        move.l  ($4).w,a6
        jsr     -318(a6)
        bra.s   .hang

dosname: dc.b   "dos.library",0
tname:   dc.b   "taskheld.plain",0
msg:     dc.b   "TH "
msg_l:   dc.b   " ",10
msg_end:
        even
