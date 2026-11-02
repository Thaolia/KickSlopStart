; tests/allocsnoop.s - AllocMem spy for the serial port (implementation-side debugging tool).
; Run it from a startup-sequence before the program to watch. It patches exec AllocMem (-198) with SetFunction
; and stays in memory (a small AllocMem'd copy of the wrapper). On the serial port:
;   AM <size> <flags> <address>           every request of 8 KB or more
;   AMFAIL <size> <flags> <largest any> <largest chip>   every failed request
; plus, at start, "SNOOP <free any> <free chip> <largest chip>".

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018

start:  move.l  4.w,a6
        moveq   #0,d1
        jsr     -216(a6)                ; AvailMem(0)
        move.l  d0,d4
        moveq   #2,d1
        jsr     -216(a6)                ; AvailMem(CHIP)
        move.l  d0,d5
        move.l  #$20002,d1
        jsr     -216(a6)                ; AvailMem(CHIP|LARGEST)
        move.l  d0,d6
        lea     m_snoop(pc),a0
        bsr     puts
        move.l  d4,d0
        bsr     hex8
        move.l  d5,d0
        bsr     hex8
        move.l  d6,d0
        bsr     hex8
        bsr     nl
        move.l  #wend-wrap,d0
        moveq   #1,d1                   ; MEMF_PUBLIC
        jsr     -198(a6)
        tst.l   d0
        beq.s   .out
        move.l  d0,a2
        lea     wrap(pc),a0
        move.l  a2,a1
        move.w  #(wend-wrap)/2-1,d0
.cp:    move.w  (a0)+,(a1)+
        dbra    d0,.cp
        jsr     -132(a6)                ; Forbid
        move.l  a6,a1
        move.w  #-198,a0
        move.l  a2,d0
        jsr     -420(a6)                ; SetFunction -> old vector
        move.l  d0,origp-wrap(a2)
        jsr     -138(a6)                ; Permit
.out:   moveq   #0,d0
        rts

; ---- copied into AllocMem'd memory; position-independent ----
wrap:   movem.l d0-d1,-(sp)
        move.l  origp(pc),a1
        jsr     (a1)
        movem.l d2-d3/a0-a1,-(sp)
        move.l  d0,d3
        move.l  16(sp),d2               ; requested size
        tst.l   d3
        beq.s   .fail
        cmp.l   #8192,d2
        blo.s   .ret
        lea     w_am(pc),a0
        bsr.s   wputs
        move.l  d2,d0
        bsr.s   whex
        move.l  20(sp),d0
        bsr.s   whex
        move.l  d3,d0
        bsr.s   whex
        bra.s   .nl
.fail:  lea     w_fail(pc),a0
        bsr.s   wputs
        move.l  d2,d0
        bsr.s   whex
        move.l  20(sp),d0
        bsr.s   whex
        move.l  #$20000,d1
        jsr     -216(a6)                ; AvailMem(LARGEST)
        bsr.s   whex
        move.l  #$20002,d1
        jsr     -216(a6)                ; AvailMem(CHIP|LARGEST)
        bsr.s   whex
.nl:    moveq   #13,d0
        bsr.s   wputc
        moveq   #10,d0
        bsr.s   wputc
.ret:   move.l  d3,d0
        movem.l (sp)+,d2-d3/a0-a1
        addq.l  #8,sp
        rts
wputs:  move.b  (a0)+,d0
        beq.s   .e
        bsr.s   wputc
        bra.s   wputs
.e:     rts
whex:   movem.l d1-d2,-(sp)
        moveq   #7,d2
        move.l  d0,d1
.d:     rol.l   #4,d1
        move.b  d1,d0
        and.b   #15,d0
        add.b   #'0',d0
        cmp.b   #'9',d0
        bls.s   .p
        addq.b  #7,d0
.p:     bsr.s   wputc
        dbra    d2,.d
        moveq   #' ',d0
        bsr.s   wputc
        movem.l (sp)+,d1-d2
        rts
wputc:  btst    #5,SERDATR
        beq.s   wputc
        and.w   #$FF,d0
        or.w    #$100,d0
        move.w  d0,SERDAT
        rts
origp:  dc.l    0
w_am:   dc.b    "AM ",0
w_fail: dc.b    "AMFAIL ",0
        even
wend:
; ---- end of the copied part ----

puts:   move.b  (a0)+,d0
        beq.s   .e
        bsr.s   putc
        bra.s   puts
.e:     rts
nl:     moveq   #13,d0
        bsr.s   putc
        moveq   #10,d0
putc:   btst    #5,SERDATR
        beq.s   putc
        and.w   #$FF,d0
        or.w    #$100,d0
        move.w  d0,SERDAT
        rts
hex8:   moveq   #7,d2
        move.l  d0,d1
.d:     rol.l   #4,d1
        move.b  d1,d0
        and.b   #15,d0
        add.b   #'0',d0
        cmp.b   #'9',d0
        bls.s   .p
        addq.b  #7,d0
.p:     bsr.s   putc
        dbra    d2,.d
        moveq   #' ',d0
        bra.s   putc
m_snoop: dc.b   "SNOOP ",0
        even
