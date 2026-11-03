; waittof_probe.s - WaitTOF and the graphics VBlank server (implementation track, our own test program; expected
; behaviour from graphics-display-v34 §7.2/§7.4).
; Calls WaitTOF 50 times and keeps the beam line seen right after each return, then writes:
;   "WT LINES <min> <max>"           lines just after WaitTOF (1.3 returns just after the VBlank, line ~$0C);
;   "WT TICKS <n>"                   timer.device-free measure: DateStamp ticks over the 50 WaitTOFs (~50);
;   "WT TOD <cia-b tod> <line>"      CIA-B TOD (restarted from the line at each VBlank) and the line, read together;
;   "WT CHAIN <first> <last>"        highest line seen by two VERTB servers of the probe, pri 127 and -128, during
;                                     the 50 WaitTOFs: the cost of the VERTB chain, as opposed to the task wake-up.
; Ends with "WT END".
; Build: vasmm68k_mot -Fhunkexe -kick1hunks -o waittof_probe tests/waittof_probe.s

        section code,code

start:
        move.l  ($4).w,a6
        lea     gfxname(pc),a1
        moveq   #0,d0
        jsr     -552(a6)             ; OpenLibrary
        move.l  d0,a5                ; a5 = GfxBase
        lea     dosname(pc),a1
        moveq   #0,d0
        jsr     -552(a6)
        move.l  d0,a4                ; a4 = DOSBase
        move.l  a4,a6
        lea     ds0(pc),a0
        move.l  a0,d1
        jsr     -192(a6)             ; DateStamp
        move.l  ($4).w,a6
        moveq   #5,d0                ; INTB_VERTB
        lea     srv_first(pc),a1
        jsr     -168(a6)             ; AddIntServer
        moveq   #5,d0
        lea     srv_last(pc),a1
        jsr     -168(a6)
        move.l  a5,a6
        moveq   #-1,d6               ; d6 = min line
        moveq   #0,d5                ; d5 = max line
        moveq   #50-1,d7
.lp:
        jsr     -270(a6)             ; WaitTOF
        move.l  $DFF004,d0
        lsr.l   #8,d0
        and.w   #$1FF,d0
        cmp.w   d6,d0
        bhs.s   .nmin
        move.w  d0,d6
.nmin:
        cmp.w   d5,d0
        bls.s   .nmax
        move.w  d0,d5
.nmax:
        dbra    d7,.lp
        move.l  ($4).w,a6
        moveq   #5,d0
        lea     srv_first(pc),a1
        jsr     -174(a6)             ; RemIntServer
        moveq   #5,d0
        lea     srv_last(pc),a1
        jsr     -174(a6)
        move.l  a4,a6
        lea     ds1(pc),a0
        move.l  a0,d1
        jsr     -192(a6)             ; DateStamp
        lea     m_lines(pc),a0
        moveq   #0,d0
        move.w  d6,d0
        moveq   #0,d1
        move.w  d5,d1
        bsr     say2
        move.l  ds1+4(pc),d0         ; minutes then ticks: elapsed = (min1-min0)*3000 + tick1 - tick0
        sub.l   ds0+4(pc),d0
        mulu    #3000,d0
        add.l   ds1+8(pc),d0
        sub.l   ds0+8(pc),d0
        lea     m_ticks(pc),a0
        moveq   #0,d1
        bsr     say2
        move.l  a5,a6
        jsr     -270(a6)             ; WaitTOF, then let the beam run to about line 100
.beam:
        move.l  $DFF004,d0
        lsr.l   #8,d0
        and.w   #$1FF,d0
        cmp.w   #100,d0
        blo.s   .beam
        moveq   #0,d0
        move.b  $BFDA00,d0           ; TODHI first: latches the reading until TODLO
        swap    d0
        move.b  $BFD900,d0
        lsl.w   #8,d0
        move.b  $BFD800,d0
        move.l  $DFF004,d1
        lsr.l   #8,d1
        and.w   #$1FF,d1
        lea     m_tod(pc),a0
        bsr     say2
        lea     m_chain(pc),a0
        move.l  hi_first(pc),d0
        move.l  hi_last(pc),d1
        bsr     say2
        lea     m_end(pc),a0
        bsr     say
        moveq   #0,d0
        rts

; VERTB servers (a1 = is_Data = the variable): keep the highest line seen at entry. Z = 1: the chain goes on.
spy:
        move.l  $DFF004,d0
        lsr.l   #8,d0
        and.l   #$1FF,d0
        cmp.l   (a1),d0
        bls.s   .sp_ret
        move.l  d0,(a1)
.sp_ret:
        moveq   #0,d0
        rts

; say2(a0 = prefix, d0 = first value, d1 = second value, both in hex): "prefix v0 v1".
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

; say(a0 = text ended by 0): Write(Output(), text).
say:
        movem.l d2-d3/a6,-(sp)
        move.l  a0,d2
        moveq   #-1,d3
.sy_len:
        addq.l  #1,d3
        tst.b   (a0)+
        bne.s   .sy_len
        move.l  a4,a6
        jsr     -60(a6)              ; Output
        move.l  d0,d1
        jsr     -48(a6)              ; Write
        movem.l (sp)+,d2-d3/a6
        rts

srv_first:
        dc.l    0,0
        dc.b    2,127                ; NT_INTERRUPT, pri 127
        dc.l    0,hi_first,spy
srv_last:
        dc.l    0,0
        dc.b    2,-128
        dc.l    0,hi_last,spy
hi_first: dc.l   0
hi_last:  dc.l   0
ds0:     dcb.l   3,0
ds1:     dcb.l   3,0
line:    dcb.b   48,0
gfxname: dc.b    "graphics.library",0
dosname: dc.b    "dos.library",0
m_lines: dc.b    "WT LINES",0
m_ticks: dc.b    "WT TICKS",0
m_tod:   dc.b    "WT TOD",0
m_chain: dc.b    "WT CHAIN",0
m_end:   dc.b    "WT END",10,0
        even
