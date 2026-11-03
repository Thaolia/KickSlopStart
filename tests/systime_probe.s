; systime_probe.s - timer.device system clock and UNIT_VBLANK (implementation track, our own test program; expected
; behaviour from timer-v34 §1.3, §3, §4). Writes, in hex:
;   "ST FREQ <VBlankFrequency> <PowerSupplyFrequency>"   50 50 in PAL (60 60 in NTSC);
;   "ST GET1 <secs> <us>" and "ST GET2 <secs> <us>"     two reads in a row: GET2 = GET1 + 1 us between TOD ticks;
;   "ST SET <secs> <us>"                                 read right after TR_SETSYSTIME {1000, 500000}: exactly it;
;   "ST VBL2S <secs> <us>"                               system time spent in a UNIT_VBLANK request of {2, 0}: ~2 s;
; then "ST END".
; Build: vasmm68k_mot -Fhunkexe -kick1hunks -o systime_probe tests/systime_probe.s

        section code,code

TR_SIZE EQU 40
start:
        move.l  ($4).w,a6
        lea     dosname(pc),a1
        moveq   #0,d0
        jsr     -552(a6)             ; OpenLibrary
        lea     dosbase(pc),a0
        move.l  d0,(a0)
        moveq   #-1,d0
        jsr     -330(a6)             ; AllocSignal
        lea     port(pc),a2
        move.b  d0,15(a2)
        move.b  #4,8(a2)             ; NT_MSGPORT
        sub.l   a1,a1
        jsr     -294(a6)             ; FindTask
        move.l  d0,16(a2)
        lea     20(a2),a0
        move.l  a0,8(a0)
        addq.l  #4,a0
        move.l  a0,-4(a0)
        clr.l   (a0)
        lea     treq(pc),a1
        move.b  #5,8(a1)             ; NT_MESSAGE
        move.l  a2,14(a1)
        move.w  #TR_SIZE,18(a1)
        lea     tname(pc),a0
        moveq   #1,d0                ; UNIT_VBLANK
        moveq   #0,d1
        jsr     -444(a6)             ; OpenDevice
        tst.l   d0
        bne     bail
        moveq   #0,d0
        move.b  $212(a6),d0          ; VBlankFrequency
        moveq   #0,d1
        move.b  $213(a6),d1          ; PowerSupplyFrequency
        lea     m_freq(pc),a0
        bsr     say2
        bsr     get
        movem.l d0-d1,-(sp)
        bsr     get
        move.l  d0,d2
        move.l  d1,d3
        movem.l (sp)+,d0-d1
        lea     m_get1(pc),a0
        bsr     say2
        move.l  d2,d0
        move.l  d3,d1
        lea     m_get2(pc),a0
        bsr     say2
        lea     treq(pc),a1
        move.w  #11,28(a1)           ; TR_SETSYSTIME
        move.l  #1000,32(a1)
        move.l  #500000,36(a1)
        bsr     doio
        bsr     get
        lea     m_set(pc),a0
        bsr     say2
        bsr     get
        move.l  d0,d4
        move.l  d1,d5
        lea     treq(pc),a1
        move.w  #9,28(a1)            ; TR_ADDREQUEST {2, 0}
        move.l  #2,32(a1)
        clr.l   36(a1)
        bsr     doio
        bsr     get
        sub.l   d4,d0
        sub.l   d5,d1
        bpl.s   .pos
        add.l   #1000000,d1
        subq.l  #1,d0
.pos:
        lea     m_vbl(pc),a0
        bsr     say2
        lea     m_end(pc),a0
        bsr     say
        moveq   #0,d0
        rts
bail:
        lea     m_fail(pc),a0
        bsr     say
        moveq   #20,d0
        rts

; get -> d0 = secs, d1 = us (TR_GETSYSTIME).
get:
        lea     treq(pc),a1
        move.w  #10,28(a1)
        bsr.s   doio
        lea     treq(pc),a1
        move.l  32(a1),d0
        move.l  36(a1),d1
        rts
doio:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  ($4).w,a6
        clr.b   30(a1)
        jsr     -456(a6)             ; DoIO
        movem.l (sp)+,d2-d7/a2-a6
        rts

; say2(a0 = prefix, d0, d1): "prefix d0 d1" in hex. Keeps d2-d7.
say2:
        movem.l d2-d3,-(sp)
        lea     line(pc),a1
.s2_pre:
        move.b  (a0)+,(a1)+
        bne.s   .s2_pre
        subq.l  #1,a1
        move.l  d1,-(sp)
        bsr.s   hex8
        move.l  (sp)+,d0
        bsr.s   hex8
        move.b  #10,(a1)+
        clr.b   (a1)
        lea     line(pc),a0
        bsr.s   say
        movem.l (sp)+,d2-d3
        rts
hex8:
        move.b  #' ',(a1)+
        moveq   #8-1,d2
.hx:
        rol.l   #4,d0
        move.w  d0,d3
        and.w   #$F,d3
        move.b  digits(pc,d3.w),(a1)+
        dbra    d2,.hx
        rts
digits: dc.b    "0123456789ABCDEF"

say:
        movem.l d2-d3/a6,-(sp)
        move.l  a0,d2
        moveq   #-1,d3
.sy_len:
        addq.l  #1,d3
        tst.b   (a0)+
        bne.s   .sy_len
        move.l  dosbase(pc),a6
        jsr     -60(a6)              ; Output
        move.l  d0,d1
        jsr     -48(a6)              ; Write
        movem.l (sp)+,d2-d3/a6
        rts

dosbase: dc.l    0
port:    dcb.b   34,0
treq:    dcb.b   TR_SIZE,0
line:    dcb.b   48,0
dosname: dc.b    "dos.library",0
tname:   dc.b    "timer.device",0
m_freq:  dc.b    "ST FREQ",0
m_get1:  dc.b    "ST GET1",0
m_get2:  dc.b    "ST GET2",0
m_set:   dc.b    "ST SET",0
m_vbl:   dc.b    "ST VBL2S",0
m_end:   dc.b    "ST END",10,0
m_fail:  dc.b    "ST FAIL",10,0
        even
