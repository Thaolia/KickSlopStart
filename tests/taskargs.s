; SPDX-License-Identifier: MIT
; AddTask must preserve caller-supplied stack arguments and enter below the requested tc_SPReg.
; Authored tasks exercise word-aligned stack positions, ordinary RTS and a custom finalPC.
                include "exec.i"
                section code,code
STACK_BYTES     EQU 1024
_start:
        movem.l d2-d7/a2-a6,-(sp)
        move.w  #372,$dff032
        move.l  4.w,a6
        suba.l  a1,a1
        jsr     LVO_FINDTASK(a6)
        move.l  d0,parent
        moveq   #-1,d0
        jsr     LVO_ALLOCSIGNAL(a6)
        tst.b   d0
        bmi     fail
        move.w  d0,sigbit
        moveq   #0,d1
        bset    d0,d1
        move.l  d1,signal_mask
        lea     cases(pc),a4
next_case:
        move.w  (a4)+,d7
        beq     success
        lea     task(pc),a0
        moveq   #TC_SIZE/4-1,d0
.clear_task:
        clr.l   (a0)+
        dbra    d0,.clear_task
        lea     task(pc),a1
        move.b  #NT_TASK,LN_TYPE(a1)
        move.l  parent(pc),a0
        move.b  LN_PRI(a0),d0
        addq.b  #1,d0
        move.b  d0,LN_PRI(a1)      ; child finishes before the signalled parent resumes
        lea     child_name(pc),a0
        move.l  a0,LN_NAME(a1)
        lea     TC_MEMENTRY(a1),a0
        move.l  a0,8(a0)
        addq.l  #4,a0
        move.l  a0,-4(a0)
        clr.l   (a0)
        lea     stack(pc),a0
        move.l  a0,TC_SPLOWER(a1)
        move.w  #STACK_BYTES/4-1,d0
.fill:
        move.l  #$a5a5a5a5,(a0)+
        dbra    d0,.fill
        move.l  a0,TC_SPUPPER(a1)
        suba.w  d7,a0
        move.l  a0,TC_SPREG(a1)
        move.l  a0,requested_sp
        lea     payload(pc),a2
        move.l  a2,(a0)
        move.l  #$13579bdf,4(a0)
        move.l  #$2468ace0,8(a0)
        clr.l   entry_sp
        clr.l   final_sp
        lea     child(pc),a2
        suba.l  a3,a3
        btst    #1,d7
        beq.s   .add
        lea     custom_final(pc),a3
.add:
        jsr     LVO_ADDTASK(a6)
        move.l  signal_mask(pc),d0
        jsr     LVO_WAIT(a6)
        move.l  requested_sp(pc),d0
        subq.l  #4,d0             ; initialPC sees finalPC as its normal return address
        cmp.l   entry_sp(pc),d0
        bne     fail
        lea     payload(pc),a0
        cmpa.l  seen_args(pc),a0
        bne     fail
        cmp.l   #$13579bdf,seen_args+4
        bne     fail
        cmp.l   #$2468ace0,seen_args+8
        bne     fail
        move.l  requested_sp(pc),a0
        lea     payload(pc),a1
        cmp.l   (a0)+,a1
        bne     fail
        cmp.l   #$13579bdf,(a0)+
        bne     fail
        cmp.l   #$2468ace0,(a0)+
        bne     fail
.guards:
        lea     stack+STACK_BYTES(pc),a1
        cmpa.l  a1,a0
        bhs.s   .final
        cmp.w   #$a5a5,(a0)+
        bne     fail
        bra.s   .guards
.final:
        btst    #1,d7
        beq.s   .default
        move.l  requested_sp(pc),d0
        cmp.l   final_sp(pc),d0
        bne     fail
        bra     next_case
.default:
        tst.l   final_sp
        bne     fail
        bra     next_case
child:
        move.l  sp,entry_sp
        move.l  4(sp),seen_args
        move.l  8(sp),seen_args+4
        move.l  12(sp),seen_args+8
        move.l  4.w,a6
        move.l  parent(pc),a1
        move.l  signal_mask(pc),d0
        jsr     LVO_SIGNAL(a6)
        rts
custom_final:
        move.l  sp,final_sp
        move.l  4.w,a6
        suba.l  a1,a1
        jsr     LVO_REMTASK(a6)
.stop:  bra.s   .stop
success:
        moveq   #0,d0
        move.w  sigbit(pc),d0
        jsr     LVO_FREESIGNAL(a6)
        lea     ok(pc),a0
        bsr.s   puts
        movem.l (sp)+,d2-d7/a2-a6
        moveq   #0,d0
        rts
fail:
        lea     error(pc),a0
        bsr.s   puts
.stop:  bra.s   .stop
puts:
        moveq   #0,d0
        move.b  (a0)+,d0
        beq.s   .ret
.wait:  btst    #5,$dff018
        beq.s   .wait
        or.w    #256,d0
        move.w  d0,$dff030
        bra.s   puts
.ret:   rts
cases:  dc.w    12,14,20,46,0
payload: dc.l   $11223344,$55667788
child_name: dc.b "taskargs child",0
ok:     dc.b    "TASKARGS OK",10,"TASKARGS END",10,0
error:  dc.b    "TASKARGS FAIL",10,"TASKARGS END",10,0
        even
parent: dc.l    0
signal_mask: dc.l 0
requested_sp: dc.l 0
entry_sp: dc.l  0
final_sp: dc.l  0
seen_args: dcb.l 3,0
sigbit: dc.w    0
task:   dcb.b   TC_SIZE,0
stack:  dcb.b   STACK_BYTES,0
        dc.l    $a5a5a5a5,$a5a5a5a5,$a5a5a5a5 ; readable guards if a broken AddTask starts at SPUpper
