; tests/contype_probe.s - time stamp for console speed runs (implementation track, authored). Prints on the serial
; line "CT <minutes * 3000 + ticks>" in hex from DateStamp (1/50 s), then returns. Run by tests/contype_probe.sh
; before and after a C:Type of a 400-line file to the boot console.
; Build: vasmm68k_mot -Fhunkexe -kick1hunks -o contype_probe tests/contype_probe.s

        section code,code

start:
        move.l  ($4).w,a6
        lea     dosname(pc),a1
        moveq   #0,d0
        jsr     -552(a6)             ; OpenLibrary
        tst.l   d0
        beq.s   .ret
        move.l  d0,a5
        move.l  a5,a6
        move.l  #stamp,d1
        jsr     -192(a6)             ; DateStamp
        lea     msg(pc),a0
        bsr.s   puts
        move.l  stamp+4(pc),d0
        mulu.w  #3000,d0
        add.l   stamp+8(pc),d0
        moveq   #7,d2
.hx:
        rol.l   #4,d0
        move.w  d0,d1
        and.w   #$F,d1
        move.b  digits(pc,d1.w),d1
        bsr.s   putc
        dbra    d2,.hx
        moveq   #10,d1
        bsr.s   putc
        move.l  ($4).w,a6
        move.l  a5,a1
        jsr     -414(a6)             ; CloseLibrary
.ret:
        moveq   #0,d0
        rts
digits: dc.b    "0123456789ABCDEF"

puts:
        move.b  (a0)+,d1
        beq.s   .r
        bsr.s   putc
        bra.s   puts
.r:     rts
; putc(d1.b): polled serial output.
putc:
        move.w  d0,-(sp)
.w:     move.w  $DFF018,d0           ; SERDATR: wait for TBE
        btst    #13,d0
        beq.s   .w
        and.w   #$FF,d1
        or.w    #$100,d1             ; stop bit
        move.w  d1,$DFF030           ; SERDAT
        move.w  (sp)+,d0
        rts

dosname: dc.b   "dos.library",0
msg:     dc.b   "CT ",0
        cnop    0,4
stamp:   dcb.l  3,0
