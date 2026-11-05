; Native A500 regression: public allocations prefer real Zorro II fast RAM over the slow expansion.
; The test machine supplies 512K CHIP, 512K slow and 1M Zorro II fast RAM.
                include "exec.i"
                section code,code
_start:
        movem.l d2-d7/a2-a6,-(sp)
        move.w  #372,$dff032
        move.l  4.w,a6
        moveq   #64,d0
        moveq   #MEMF_PUBLIC,d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  d0,a2
        cmp.l   #$200000,d0
        blo.s   fail
        cmp.l   #$a00000,d0
        bhs.s   fail
        move.l  a2,a1
        jsr     LVO_TYPEOFMEM(a6)
        btst    #2,d0
        beq.s   fail
        moveq   #64,d0
        moveq   #MEMF_CHIP,d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.s   fail
        cmp.l   EB_MAXLOCMEM(a6),d0
        bhs.s   fail
        move.l  d0,a1
        moveq   #64,d0
        jsr     LVO_FREEMEM(a6)
        move.l  a2,a1
        moveq   #64,d0
        jsr     LVO_FREEMEM(a6)
        lea     ok(pc),a0
        bsr.s   puts
        movem.l (sp)+,d2-d7/a2-a6
        moveq   #0,d0
        rts
fail:
        lea     bad(pc),a0
        bsr.s   puts
.stop:  bra.s   .stop
puts:
        moveq   #0,d0
        move.b  (a0)+,d0
        beq.s   .done
.wait:
        btst    #5,$dff018
        beq.s   .wait
        or.w    #256,d0
        move.w  d0,$dff030
        bra.s   puts
.done:  rts
ok:     dc.b "MEMPRIO OK",10,"MEMPRIO END",10,0
bad:    dc.b "MEMPRIO FAIL",10,0
