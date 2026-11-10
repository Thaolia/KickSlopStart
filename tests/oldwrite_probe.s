; tests/oldwrite_probe.s - writes through a FileHandle opened with MODE_OLDFILE (implementation track, authored).
; docs/analysis/rom-filesystem-v34.md §5.1: a FINDINPUT handle accepts writes on 1.3. DF0:t holds 37 bytes.
;   1. Open OLDFILE, Read 5, Write 200 bytes 'W' (position 5), Seek(0, BEGINNING), Read up to 300, Close:
;      "OW A <read1> <write> <seek> <read2> <sum of read2> <close>"
;   2. Open OLDFILE, Seek(0, END), Write "END",10, Close: "OW B <seek> <write> <close>"
;   3. Open OLDFILE, Write "abc" at once, Close: "OW C <write> <IoErr> <close>"
; Expected file: "abc" + bytes 3-4 of the original + 200 x 'W' + "END",10 (209 bytes); tests/oldwrite_probe.sh
; checks it on the host. "OW END" last. Run as a CLI command.

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018

LVO_OpenLibrary  EQU -552
LVO_CloseLibrary EQU -414
LVO_Open         EQU -30
LVO_Close        EQU -36
LVO_Read         EQU -42
LVO_Write        EQU -48
LVO_Seek         EQU -66
LVO_IoErr        EQU -132
MODE_OLDFILE     EQU 1005

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
        lea     wbuf,a0              ; 200 x 'W'
        move.w  #199,d0
.fill:  move.b  #'W',(a0)+
        dbra    d0,.fill
        lea     m_a(pc),a0
        bsr     puts
        bsr     open
        beq     .b
        moveq   #5,d3
        bsr     read
        bsr     phex8
        move.l  #wbuf,d2
        move.l  #200,d3
        bsr     write
        bsr     phex8
        moveq   #0,d2
        moveq   #-1,d3
        bsr     seek
        bsr     phex8
        move.l  #300,d3
        bsr     read
        bsr     phex8
        lea     rbuf,a0              ; sum of the bytes read
        moveq   #0,d1
        moveq   #0,d4
        bra.s   .sn
.sl:    move.b  (a0)+,d1
        add.l   d1,d4
.sn:    dbra    d0,.sl
        move.l  d4,d0
        bsr     phex8
        bsr     close
.b:
        bsr     nl
        lea     m_b(pc),a0
        bsr     puts
        bsr     open
        beq     .c
        moveq   #0,d2
        moveq   #1,d3
        bsr     seek
        bsr     phex8
        move.l  #s_end,d2
        moveq   #4,d3
        bsr     write
        bsr     phex8
        bsr     close
.c:
        bsr     nl
        lea     m_c(pc),a0
        bsr     puts
        bsr     open
        beq     .e
        move.l  #s_abc,d2
        moveq   #3,d3
        bsr     write
        bsr     phex8
        jsr     LVO_IoErr(a6)
        bsr     phex8
        bsr     close
.e:
        bsr     nl
        lea     m_end(pc),a0
        bsr     puts
        move.l  4.w,a6
        move.l  a5,a1
        jsr     LVO_CloseLibrary(a6)
.done:
        movem.l (sp)+,d2-d7/a2-a6
        moveq   #0,d0
        rts

; open -> d7 = file | 0 (Z), " FAIL <IoErr>" printed on failure
open:
        move.l  #fname,d1
        move.l  #MODE_OLDFILE,d2
        jsr     LVO_Open(a6)
        move.l  d0,d7
        bne.s   .r
        lea     m_fail(pc),a0
        bsr     puts
        jsr     LVO_IoErr(a6)
        bsr     phex8
        moveq   #0,d7
.r:     rts
read:   ; d3 = length -> d0 = result
        move.l  d7,d1
        move.l  #rbuf,d2
        jmp     LVO_Read(a6)
write:  ; d2 = data, d3 = length -> d0 = result
        move.l  d7,d1
        jmp     LVO_Write(a6)
seek:   ; d2 = position, d3 = mode -> d0 = old position
        move.l  d7,d1
        jmp     LVO_Seek(a6)
close:  ; prints the result of Close
        move.l  d7,d1
        jsr     LVO_Close(a6)
        bra.s   phex8

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

fname:    dc.b  "DF0:t",0
dosname:  dc.b  "dos.library",0
s_end:    dc.b  "END",10
s_abc:    dc.b  "abc"
m_a:      dc.b  "OW A",0
m_b:      dc.b  "OW B",0
m_c:      dc.b  "OW C",0
m_fail:   dc.b  " FAIL",0
m_end:    dc.b  "OW END",10,0

                section buffer,bss
wbuf:     ds.b  200
rbuf:     ds.b  300
