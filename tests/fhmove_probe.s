; tests/fhmove_probe.s - open FileHandles whose floppy moves to another drive (implementation track, authored).
; docs/analysis/disk-change-v34.md §2.4.1: a FileHandle stays bound to the file system of the drive it was opened on;
; while its volume is out of that drive (even in another one) every access waits behind "Please replace volume /
; <name> / in unit  n", and the access completes once the disk is back in that drive.
; Reads DF1:longfile by 2048-byte blocks with a 0.5 s pause after each, printing "FM RD <n>" per block, then
; "FM RDLAST <result> <IoErr>" for the last Read (0 at the end of the file), "FM RDEND <bytes> <sum>" (sum of
; all bytes). Then creates DF1:w, writes "line one" + LF, prints "FM WR1", waits
; 20 s, writes "line two" + LF, closes, prints "FM WREND <result of the second Write>". "FM END" last.
; tests/fhmove_probe.sh moves the disk DF1 -> DF2 -> DF1 during each part. Run as a CLI command.

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018

LVO_OpenLibrary  EQU -552
LVO_CloseLibrary EQU -414
LVO_Open         EQU -30
LVO_Close        EQU -36
LVO_Read         EQU -42
LVO_Write        EQU -48
LVO_Delay        EQU -198
LVO_IoErr        EQU -132
MODE_OLDFILE     EQU 1005
MODE_NEWFILE     EQU 1006
BLK              EQU 2048

                section code,code
start:
        movem.l d2-d7/a2-a6,-(sp)
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
        move.l  #rname,d1
        move.l  #MODE_OLDFILE,d2
        jsr     LVO_Open(a6)
        move.l  d0,d7                ; d7 = file
        beq     .write
        moveq   #0,d4                ; d4 = bytes, d5 = sum, d6 = block number
        moveq   #0,d5
        moveq   #0,d6
.rd:
        move.l  d7,d1
        move.l  #buf,d2
        move.l  #BLK,d3
        jsr     LVO_Read(a6)
        tst.l   d0
        ble.s   .rdlast
        add.l   d0,d4
        lea     buf,a0
        subq.w  #1,d0
        moveq   #0,d1
.sum:
        move.b  (a0)+,d1
        add.l   d1,d5
        dbra    d0,.sum
        addq.l  #1,d6
        lea     m_rd(pc),a0
        bsr     puts
        move.l  d6,d0
        bsr     phex8
        bsr     nl
        moveq   #25,d1
        jsr     LVO_Delay(a6)
        bra.s   .rd
.rdlast:
        move.l  d0,d3
        lea     m_rdlast(pc),a0
        bsr     puts
        move.l  d3,d0
        bsr     phex8
        jsr     LVO_IoErr(a6)
        bsr     phex8
        bsr     nl
        lea     m_rdend(pc),a0
        bsr     puts
        move.l  d4,d0
        bsr     phex8
        move.l  d5,d0
        bsr     phex8
        bsr     nl
        move.l  d7,d1
        jsr     LVO_Close(a6)
.write:
        move.l  #wname,d1
        move.l  #MODE_NEWFILE,d2
        jsr     LVO_Open(a6)
        move.l  d0,d7
        beq.s   .end
        move.l  d7,d1
        move.l  #line1,d2
        moveq   #9,d3
        jsr     LVO_Write(a6)
        lea     m_wr1(pc),a0
        bsr     puts
        move.l  #1000,d1
        jsr     LVO_Delay(a6)
        move.l  d7,d1
        move.l  #line2,d2
        moveq   #9,d3
        jsr     LVO_Write(a6)
        move.l  d0,d6
        move.l  d7,d1
        jsr     LVO_Close(a6)
        lea     m_wrend(pc),a0
        bsr     puts
        move.l  d6,d0
        bsr     phex8
        bsr     nl
.end:
        lea     m_end(pc),a0
        bsr     puts
        move.l  4.w,a6
        move.l  a5,a1
        jsr     LVO_CloseLibrary(a6)
.done:
        movem.l (sp)+,d2-d7/a2-a6
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

rname:    dc.b  "DF1:longfile",0
wname:    dc.b  "DF1:w",0
dosname:  dc.b  "dos.library",0
line1:    dc.b  "line one",10
line2:    dc.b  "line two",10
m_begin:  dc.b  "FM BEGIN",10,0
m_rd:     dc.b  "FM RD",0
m_rdlast: dc.b  "FM RDLAST",0
m_rdend:  dc.b  "FM RDEND",0
m_wr1:    dc.b  "FM WR1",10,0
m_wrend:  dc.b  "FM WREND",0
m_end:    dc.b  "FM END",10,0

                section buffer,bss
buf:      ds.b  BLK
