; tests/bigfile_probe.s - a file of more than 65535 data blocks on a hard disk partition (implementation track,
; authored). DH0:huge holds a pattern written on the host by tests/bigfile_probe.sh: the long at byte offset 4n is n.
; Prints on the serial line:
;   "BF EX <size> <numblocks>"      Examine of DH0:huge
;   "BF RD <offset> <long> <long>"  Seek(offset, OFFSET_BEGINNING) then Read of 8 bytes, for four offsets past
;                                   65535 * 488 bytes and one before
;   "BF WR <result> <ioerr>"        Seek(32000000) then Write of the 8 bytes "KSSWRITE" (bytes written, IoErr)
;   "BF END"
; The file is opened with MODE_READWRITE (FINDUPDATE).
; Run by tests/bigfile_probe.sh as a CLI command from a startup-sequence.

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018

LVO_OpenLibrary  EQU -552
LVO_CloseLibrary EQU -414
LVO_Open         EQU -30
LVO_Close        EQU -36
LVO_Read         EQU -42
LVO_Write        EQU -48
LVO_Seek         EQU -66
LVO_Lock         EQU -84
LVO_UnLock       EQU -90
LVO_Examine      EQU -102
LVO_IoErr        EQU -132
MODE_READWRITE   EQU 1004
OFFSET_BEGINNING EQU -1

                section code,code
start:
        move.l  4.w,a6
        lea     dosname(pc),a1
        moveq   #0,d0
        jsr     LVO_OpenLibrary(a6)
        move.l  d0,a5                ; a5 = DOSBase
        tst.l   d0
        beq     .done
        move.l  a5,a6
        lea     m_begin(pc),a0
        bsr     puts
        move.l  #fname,d1            ; Examine
        moveq   #-2,d2               ; ACCESS_READ
        jsr     LVO_Lock(a6)
        move.l  d0,d7
        beq.s   .nolock
        move.l  d7,d1
        move.l  #fib,d2
        jsr     LVO_Examine(a6)
        lea     m_ex(pc),a0
        bsr     puts
        move.l  fib+124(pc),d0       ; fib_Size
        bsr     phex8
        move.l  fib+128(pc),d0       ; fib_NumBlocks
        bsr     phex8
        bsr     nl
        move.l  d7,d1
        jsr     LVO_UnLock(a6)
.nolock:
        move.l  #fname,d1
        move.l  #MODE_READWRITE,d2
        jsr     LVO_Open(a6)
        move.l  d0,d7                ; d7 = file
        beq     .end
        lea     offsets(pc),a3
.rd:
        move.l  (a3)+,d6
        bmi.s   .wr
        move.l  d7,d1
        move.l  d6,d2
        moveq   #OFFSET_BEGINNING,d3
        jsr     LVO_Seek(a6)
        move.l  d7,d1
        move.l  #buf,d2
        moveq   #8,d3
        jsr     LVO_Read(a6)
        lea     m_rd(pc),a0
        bsr     puts
        move.l  d6,d0
        bsr     phex8
        move.l  buf(pc),d0
        bsr     phex8
        move.l  buf+4(pc),d0
        bsr     phex8
        bsr     nl
        bra.s   .rd
.wr:
        move.l  d7,d1
        move.l  #32000000,d2
        moveq   #OFFSET_BEGINNING,d3
        jsr     LVO_Seek(a6)
        move.l  d7,d1
        move.l  #wtext,d2
        moveq   #8,d3
        jsr     LVO_Write(a6)
        move.l  d0,d6
        lea     m_wr(pc),a0
        bsr     puts
        move.l  d6,d0
        bsr     phex8
        jsr     LVO_IoErr(a6)
        bsr     phex8
        bsr     nl
        move.l  d7,d1
        jsr     LVO_Close(a6)
.end:
        lea     m_end(pc),a0
        bsr     puts
        move.l  4.w,a6
        move.l  a5,a1
        jsr     LVO_CloseLibrary(a6)
.done:
        moveq   #0,d0
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

offsets:  dc.l  31000000,31980000,32000004,33000000,33599992,-1   ; 65535 * 488 = 31981080
fname:    dc.b  "DH0:huge",0
dosname:  dc.b  "dos.library",0
wtext:    dc.b  "KSSWRITE"
m_begin:  dc.b  "BF BEGIN",10,0
m_ex:     dc.b  "BF EX",0
m_rd:     dc.b  "BF RD",0
m_wr:     dc.b  "BF WR",0
m_end:    dc.b  "BF END",10,0
                cnop    0,4
buf:      ds.l  2
fib:      ds.b  260
