; tests/fsperf_probe.s - speed and correctness of the data paths (implementation track, authored). DF0:big holds a
; pattern written on the host by tests/fsperf_probe.sh: the long at byte offset 4n is n. Times are DateStamp ticks
; (1/50 s). Prints on the serial line:
;   "FP RD <ticks> <bytes> <bad>"    DF0:big read whole in 4,888-byte Reads; bad = longs differing from the pattern
;   "FP SMALL <ticks> <bad>"         the first 9,002 bytes of DF0:big in 7-byte Reads to an odd address
;   "FP WR <ticks> <bytes>"          DF0:out written from the pattern in 3,001-byte Writes (120,000 bytes), Close
;   "FP WRCHK <bytes> <bad>"         DF0:out read back and compared with the pattern
;   "FP CPY <ticks>"                 100 CopyMem of 50,000 bytes
;   "FP CLR <ticks> <bad>"           200 AllocMem(20,000, MEMF_CLEAR) + FreeMem, each block dirtied before its
;                                    FreeMem; bad = non-zero longs in one more cleared block
;   "FP END"
; Run by tests/fsperf_probe.sh as a CLI command from a startup-sequence.

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018

LVO_AllocMem     EQU -198
LVO_FreeMem      EQU -210
LVO_OpenLibrary  EQU -552
LVO_CloseLibrary EQU -414
LVO_CopyMem      EQU -624
LVO_Open         EQU -30
LVO_Close        EQU -36
LVO_Read         EQU -42
LVO_Write        EQU -48
LVO_DateStamp    EQU -192
MODE_OLDFILE     EQU 1005
MODE_NEWFILE     EQU 1006
MEMF_CLEAR       EQU $10000
BIGSIZE          EQU 200000
OUTSIZE          EQU 120000
BUFSIZE          EQU BIGSIZE+16

                section code,code
start:
        move.l  4.w,a6
        lea     dosname(pc),a1
        moveq   #0,d0
        jsr     LVO_OpenLibrary(a6)
        move.l  d0,a5                ; a5 = DOSBase
        tst.l   d0
        beq     .done
        lea     m_begin(pc),a0
        bsr     puts
        move.l  #BUFSIZE,d0
        moveq   #1,d1                ; MEMF_PUBLIC
        jsr     LVO_AllocMem(a6)
        move.l  d0,a4                ; a4 = buffer 1
        tst.l   d0
        beq     .end
        move.l  #BUFSIZE,d0
        moveq   #1,d1
        jsr     LVO_AllocMem(a6)
        move.l  d0,a3                ; a3 = buffer 2
        tst.l   d0
        beq     .free1

; --- whole file in 4,888-byte Reads ---
        bsr     stamp
        move.l  d0,d6
        lea     bigname(pc),a0
        move.l  a4,a1
        move.l  #4888,d0
        bsr     readall              ; d0 = bytes read
        move.l  d0,d5
        bsr     stamp
        sub.l   d6,d0
        lea     m_rd(pc),a0
        bsr     puts
        bsr     phex8
        move.l  d5,d0
        bsr     phex8
        move.l  a4,a0
        move.l  d5,d0
        bsr     pattern_bad
        bsr     phex8
        bsr     nl

; --- 7-byte Reads to an odd address ---
        bsr     stamp
        move.l  d0,d6
        move.l  #bigname,d1
        move.l  #MODE_OLDFILE,d2
        bsr     dos_open
        move.l  d0,d7
        beq.s   .small_done
        moveq   #0,d4                ; d4 = bytes so far
.small_lp:
        move.l  d7,d1
        lea     1(a3,d4.l),a0
        move.l  a0,d2
        moveq   #7,d3
        bsr     dos_read
        tst.l   d0
        ble.s   .small_close
        add.l   d0,d4
        cmp.l   #9002,d4
        blo.s   .small_lp
.small_close:
        move.l  d7,d1
        bsr     dos_close
.small_done:
        bsr     stamp
        sub.l   d6,d0
        lea     m_small(pc),a0
        bsr     puts
        bsr     phex8
        moveq   #0,d0                ; bad = bytes differing from buffer 1 (checked above against the pattern)
        moveq   #0,d1
.small_cmp:
        cmp.l   #9002,d1
        bhs.s   .small_end
        move.b  1(a3,d1.l),d2
        cmp.b   0(a4,d1.l),d2
        beq.s   .small_ok
        addq.l  #1,d0
.small_ok:
        addq.l  #1,d1
        bra.s   .small_cmp
.small_end:
        bsr     phex8
        bsr     nl

; --- 3,001-byte Writes ---
        bsr     stamp
        move.l  d0,d6
        moveq   #0,d4                ; d4 = bytes written
        move.l  #outname,d1
        move.l  #MODE_NEWFILE,d2
        bsr     dos_open
        move.l  d0,d7
        beq.s   .wr_done
.wr_lp:
        move.l  #OUTSIZE,d3
        sub.l   d4,d3
        beq.s   .wr_close
        cmp.l   #3001,d3
        bls.s   .wr_n
        move.l  #3001,d3
.wr_n:
        move.l  d7,d1
        lea     0(a4,d4.l),a0
        move.l  a0,d2
        bsr     dos_write
        tst.l   d0
        ble.s   .wr_close
        add.l   d0,d4
        bra.s   .wr_lp
.wr_close:
        move.l  d7,d1
        bsr     dos_close
.wr_done:
        bsr     stamp
        sub.l   d6,d0
        lea     m_wr(pc),a0
        bsr     puts
        bsr     phex8
        move.l  d4,d0
        bsr     phex8
        bsr     nl
        lea     outname(pc),a0
        move.l  a3,a1
        move.l  #5000,d0
        bsr     readall
        move.l  d0,d5
        lea     m_wrchk(pc),a0
        bsr     puts
        bsr     phex8
        move.l  a3,a0
        move.l  d5,d0
        bsr     pattern_bad
        bsr     phex8
        bsr     nl

; --- CopyMem ---
        bsr     stamp
        move.l  d0,d6
        moveq   #100-1,d4
.cpy_lp:
        move.l  a4,a0
        move.l  a3,a1
        move.l  #50000,d0
        jsr     LVO_CopyMem(a6)
        dbra    d4,.cpy_lp
        bsr     stamp
        sub.l   d6,d0
        lea     m_cpy(pc),a0
        bsr     puts
        bsr     phex8
        bsr     nl

; --- AllocMem(MEMF_CLEAR) ---
        bsr     stamp
        move.l  d0,d6
        move.w  #200-1,d4
.clr_lp:
        move.l  #20000,d0
        move.l  #MEMF_CLEAR|1,d1
        jsr     LVO_AllocMem(a6)
        tst.l   d0
        beq.s   .clr_next
        move.l  d0,a1
        st      (a1)                 ; dirty the first and last bytes for the next one
        st      19999(a1)
        move.l  #20000,d0
        jsr     LVO_FreeMem(a6)
.clr_next:
        dbra    d4,.clr_lp
        bsr     stamp
        sub.l   d6,d0
        lea     m_clr(pc),a0
        bsr     puts
        bsr     phex8
        move.l  #20000,d0
        move.l  #MEMF_CLEAR|1,d1
        jsr     LVO_AllocMem(a6)
        moveq   #-1,d2
        tst.l   d0
        beq.s   .clr_pr
        move.l  d0,a0
        moveq   #0,d2
        move.w  #20000/4-1,d1
.clr_chk:
        tst.l   (a0)+
        beq.s   .clr_z
        addq.l  #1,d2
.clr_z:
        dbra    d1,.clr_chk
        move.l  d0,a1
        move.l  #20000,d0
        jsr     LVO_FreeMem(a6)
.clr_pr:
        move.l  d2,d0
        bsr     phex8
        bsr     nl

        move.l  a3,a1
        move.l  #BUFSIZE,d0
        jsr     LVO_FreeMem(a6)
.free1:
        move.l  a4,a1
        move.l  #BUFSIZE,d0
        jsr     LVO_FreeMem(a6)
.end:
        lea     m_end(pc),a0
        bsr     puts
        move.l  a5,a1
        jsr     LVO_CloseLibrary(a6)
.done:
        moveq   #0,d0
        rts

; readall(a0 = name, a1 = destination, d0 = Read size) -> d0 = bytes read until end of file. a6 = SysBase.
readall:
        movem.l d2-d7/a2,-(sp)
        move.l  a1,a2
        move.l  d0,d5
        moveq   #0,d4
        move.l  a0,d1
        move.l  #MODE_OLDFILE,d2
        bsr.s   dos_open
        move.l  d0,d7
        beq.s   .ra_ret
.ra_lp:
        move.l  d7,d1
        lea     0(a2,d4.l),a0
        move.l  a0,d2
        move.l  d5,d3
        bsr.s   dos_read
        tst.l   d0
        ble.s   .ra_close
        add.l   d0,d4
        cmp.l   #BIGSIZE,d4
        blo.s   .ra_lp
.ra_close:
        move.l  d7,d1
        bsr.s   dos_close
.ra_ret:
        move.l  d4,d0
        movem.l (sp)+,d2-d7/a2
        rts

dos_open:
        move.l  a6,-(sp)
        move.l  a5,a6
        jsr     LVO_Open(a6)
        move.l  (sp)+,a6
        rts
dos_close:
        move.l  a6,-(sp)
        move.l  a5,a6
        jsr     LVO_Close(a6)
        move.l  (sp)+,a6
        rts
dos_read:
        move.l  a6,-(sp)
        move.l  a5,a6
        jsr     LVO_Read(a6)
        move.l  (sp)+,a6
        rts
dos_write:
        move.l  a6,-(sp)
        move.l  a5,a6
        jsr     LVO_Write(a6)
        move.l  (sp)+,a6
        rts

; stamp -> d0 = minutes * 3000 + ticks (DateStamp). a6 = SysBase.
stamp:
        movem.l d1-d3/a0-a1/a6,-(sp)
        move.l  a5,a6
        move.l  #dstamp,d1
        jsr     LVO_DateStamp(a6)
        move.l  dstamp+4(pc),d0
        mulu.w  #3000,d0
        add.l   dstamp+8(pc),d0
        movem.l (sp)+,d1-d3/a0-a1/a6
        rts

; pattern_bad(a0 = data, d0 = bytes) -> d0 = longs n (n < bytes/4) whose value is not n.
pattern_bad:
        move.l  d2,-(sp)
        lsr.l   #2,d0
        move.l  d0,d1
        moveq   #0,d0
        moveq   #0,d2
.pb_lp:
        cmp.l   d1,d2
        bhs.s   .pb_ret
        cmp.l   (a0)+,d2
        beq.s   .pb_ok
        addq.l  #1,d0
.pb_ok:
        addq.l  #1,d2
        bra.s   .pb_lp
.pb_ret:
        move.l  (sp)+,d2
        rts

puts:
        move.b  (a0)+,d1
        beq.s   .r
        bsr.s   putc
        bra.s   puts
.r:     rts
nl:     moveq   #10,d1
        bra.s   putc
; phex8(d0.l): " XXXXXXXX"
phex8:
        movem.l d0/d2,-(sp)
        moveq   #' ',d1
        bsr.s   putc
        moveq   #7,d2
.h:     rol.l   #4,d0
        move.w  d0,d1
        and.w   #15,d1
        add.b   #'0',d1
        cmp.b   #'9',d1
        bls.s   .o
        addq.b  #7,d1
.o:     bsr.s   putc
        dbra    d2,.h
        movem.l (sp)+,d0/d2
        rts
putc:
        move.w  d0,-(sp)
.w:     move.w  SERDATR,d0
        btst    #13,d0
        beq.s   .w
        and.w   #$FF,d1
        or.w    #$100,d1
        move.w  d1,SERDAT
        move.w  (sp)+,d0
        rts

bigname:  dc.b  "DF0:big",0
outname:  dc.b  "DF0:out",0
dosname:  dc.b  "dos.library",0
m_begin:  dc.b  "FP BEGIN",10,0
m_rd:     dc.b  "FP RD",0
m_small:  dc.b  "FP SMALL",0
m_wr:     dc.b  "FP WR",0
m_wrchk:  dc.b  "FP WRCHK",0
m_cpy:    dc.b  "FP CPY",0
m_clr:    dc.b  "FP CLR",0
m_end:    dc.b  "FP END",10,0
                cnop    0,4
dstamp:   ds.l  3
