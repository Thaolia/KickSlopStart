; SPDX-License-Identifier: MIT
; The Initial CLI runs at priority zero and yields to an awakened ordinary priority-zero worker.
                include "exec.i"
                section code,code
_start:
        movem.l d2-d7/a2-a6,-(sp)
        move.w  #372,$dff032
        move.l  4.w,a6
        suba.l  a1,a1
        jsr     LVO_FINDTASK(a6)
        move.l  d0,a0
        tst.b   LN_PRI(a0)
        bne.s   fail
        lea     task(pc),a1
        move.b  #NT_TASK,LN_TYPE(a1)
        lea     child_name(pc),a0
        move.l  a0,LN_NAME(a1)
        lea     stack(pc),a0
        move.l  a0,TC_SPLOWER(a1)
        lea     stack+512(pc),a0
        move.l  a0,TC_SPUPPER(a1)
        move.l  a0,TC_SPREG(a1)
        lea     TC_MEMENTRY(a1),a0
        move.l  a0,8(a0)
        addq.l  #4,a0
        move.l  a0,-4(a0)
        clr.l   (a0)
        jsr     LVO_FORBID(a6)
        lea     worker(pc),a2
        suba.l  a3,a3
        jsr     LVO_ADDTASK(a6)
        jsr     LVO_PERMIT(a6)
        tst.b   worker_ran
        beq.s   fail
        lea     ok(pc),a0
        bsr.s   puts
        movem.l (sp)+,d2-d7/a2-a6
        moveq   #0,d0
        rts
worker:
        st      worker_ran
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
child_name: dc.b "clipri worker",0
ok:     dc.b    "CLIPRI OK",10,"CLIPRI END",10,0
error:  dc.b    "CLIPRI FAIL",10,"CLIPRI END",10,0
worker_ran: dc.b 0
        even
task:   dcb.b   TC_SIZE,0
stack:  dcb.b   512,0
