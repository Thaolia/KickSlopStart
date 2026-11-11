; SPDX-License-Identifier: MIT
; Adding a server must retain an established interrupt list and a RAM dispatcher wrapper.
; The wrapper is an authored JMP through the saved public iv_Code, without copying ROM instructions.
                include "exec.i"
                section code,code
_start:
        movem.l d2-d7/a2-a6,-(sp)
        move.w  #372,$dff032
        move.l  4.w,a6
        lea     EB_INTVECTS+INTB_VERTB*IV_SIZE(a6),a3
        moveq   #INTB_VERTB,d0
        lea     server_a(pc),a1
        jsr     LVO_ADDINTSERVER(a6)
        bsr     frames
        move.l  count_a(pc),d2
        beq     fail
        move.l  IV_DATA(a3),saved_data
        move.l  IV_CODE(a3),saved_code
        move.l  IV_CODE(a3),proxy+2
        jsr     LVO_DISABLE(a6)
        lea     proxy(pc),a0
        move.l  a0,IV_CODE(a3)
        moveq   #INTB_VERTB,d0
        lea     server_b(pc),a1
        jsr     LVO_ADDINTSERVER(a6)
        lea     proxy(pc),a0
        cmpa.l  IV_CODE(a3),a0
        beq.s   .data
        st      bad
.data:
        move.l  saved_data(pc),d0
        cmp.l   IV_DATA(a3),d0
        beq.s   .enabled
        st      bad
.enabled:
        jsr     LVO_ENABLE(a6)
        tst.b   bad
        bne     fail_restore
        move.l  count_a(pc),d2
        move.l  count_b(pc),d3
        bsr     frames
        cmp.l   count_a(pc),d2     ; the server installed before the wrapper must keep running
        beq     fail_restore
        cmp.l   count_b(pc),d3
        beq     fail_restore
        moveq   #INTB_VERTB,d0
        lea     server_b(pc),a1
        jsr     LVO_REMINTSERVER(a6)
        move.l  count_a(pc),d2
        move.l  count_b(pc),d3
        bsr     frames
        cmp.l   count_a(pc),d2
        beq     fail_restore
        cmp.l   count_b(pc),d3
        bne     fail_restore
        jsr     LVO_DISABLE(a6)
        move.l  saved_code(pc),IV_CODE(a3)
        jsr     LVO_ENABLE(a6)
        moveq   #INTB_VERTB,d0
        lea     server_a(pc),a1
        jsr     LVO_REMINTSERVER(a6)
        lea     ok(pc),a0
        bsr.s   puts
        movem.l (sp)+,d2-d7/a2-a6
        moveq   #0,d0
        rts
fail_restore:
        jsr     LVO_DISABLE(a6)
        move.l  saved_code(pc),IV_CODE(a3)
        jsr     LVO_ENABLE(a6)
fail:
        lea     error(pc),a0
        bsr.s   puts
.stop:  bra.s   .stop
; Use the hardware beam rather than timer/WaitTOF services that the bug removes from the chain.
frames:
        moveq   #3,d7
.frame:
.bottom:
        bsr.s   beam
        cmp.w   #100,d0
        blo.s   .bottom
.top:
        bsr.s   beam
        cmp.w   #20,d0
        bhs.s   .top
        dbra    d7,.frame
        rts
beam:
        move.l  $dff004,d0
        lsr.l   #8,d0
        and.w   #511,d0
        rts
callback:
        addq.l  #1,(a1)
        moveq   #0,d0
        rts
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
proxy:  dc.w    $4ef9
        dc.l    0
server_a:
        dc.l    0,0
        dc.b    NT_INTERRUPT,25
        dc.l    name_a,count_a,callback
server_b:
        dc.l    0,0
        dc.b    NT_INTERRUPT,24
        dc.l    name_b,count_b,callback
name_a: dc.b    "irqchain first",0
name_b: dc.b    "irqchain second",0
ok:     dc.b    "IRQCHAIN OK",10,"IRQCHAIN END",10,0
error:  dc.b    "IRQCHAIN FAIL",10,"IRQCHAIN END",10,0
bad:    dc.b    0
        even
saved_code: dc.l 0
saved_data: dc.l 0
count_a: dc.l   0
count_b: dc.l   0
