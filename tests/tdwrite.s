; tests/tdwrite.s - HUNK test executable (TEST ASSET, NOT ROM code).
; Black-box "trackdisk write" probe (analysis track, docs/analysis/trackdisk-write-v34.md).
; Started from the startup-sequence of a blank OFS floppy (tests/tdwrite_run.sh). Sends a series of
; requests to trackdisk.device unit 0 and writes each result to the direct serial port (SERDAT), one line per step:
;   "<step> E=<io_Error> A=<io_Actual> L=<first long read>" (hex).
; io_Actual is preloaded with $DEADBEEF before each request to see whether it gets modified.
; Blocks used: 1100 (track 100), 220 (track 20), track 158 (formatted). Buffers in CHIP (required by the blitter).
; Assembly: vasmm68k_mot -Fhunkexe -kick1hunks -nosym -o build/tdwrite tests/tdwrite.s
; Author's code; public structures (exec/io.h, devices/trackdisk.h).

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018
SERPER   EQU $DFF032
IO_CMD   EQU $1C
IO_ERR   EQU $1F
IO_ACT   EQU $20
IO_LEN   EQU $24
IO_DATA  EQU $28
IO_OFF   EQU $2C
TRKB     EQU 11*512

                section code,code
_start:
                movem.l d2-d7/a2-a6,-(sp)
                move.l  4.w,a6
                lea     vars(pc),a4
                move.w  #372,SERPER
                move.l  #TRKB,d0
                move.l  #$10003,d1              ; MEMF_CHIP|MEMF_CLEAR
                jsr     -198(a6)
                move.l  d0,buf-vars(a4)
                beq     .out
                sub.l   a1,a1
                jsr     -294(a6)                ; FindTask(0)
                lea     port(pc),a2
                move.l  d0,16(a2)
                moveq   #-1,d0
                jsr     -330(a6)                ; AllocSignal
                move.b  d0,15(a2)
                move.b  #4,8(a2)
                lea     20(a2),a0
                move.l  a0,8(a0)
                addq.l  #4,a0
                clr.l   (a0)
                move.l  a0,-(a0)
                lea     ioreq(pc),a1
                move.b  #5,8(a1)
                move.l  a2,14(a1)
                move.w  #$38,18(a1)
                lea     tdname(pc),a0
                moveq   #0,d0
                moveq   #0,d1
                jsr     -444(a6)                ; OpenDevice
                tst.l   d0
                bne     .out
                lea     msg0(pc),a0
                bsr     puts
; A: read block 1100 (track 100)
                moveq   #'A',d7
                moveq   #2,d2
                move.l  #1100*512,d3
                move.l  #512,d4
                bsr     doio
; B: write pattern 11111111 to 1100 (buffer only)
                move.l  #$11111111,d0
                bsr     fill
                moveq   #'B',d7
                moveq   #3,d2
                bsr     doio
; C: CMD_CLEAR
                moveq   #'C',d7
                moveq   #5,d2
                bsr     doio
; D: re-read 1100 (old contents expected if CLEAR discards the buffer)
                moveq   #'D',d7
                moveq   #2,d2
                bsr     doio
; E: rewrite 22222222 + F: CMD_UPDATE + G: CLEAR + re-read
                move.l  #$22222222,d0
                bsr     fill
                moveq   #'E',d7
                moveq   #3,d2
                bsr     doio
                moveq   #'F',d7
                moveq   #4,d2
                bsr     doio
                moveq   #'g',d7
                moveq   #5,d2
                bsr     doio
                moveq   #'G',d7
                moveq   #2,d2
                bsr     doio
; H: zero-length write (pattern 33333333), UPDATE, CLEAR, re-read
                move.l  #$33333333,d0
                bsr     fill
                moveq   #'H',d7
                moveq   #3,d2
                moveq   #0,d4
                bsr     doio
                move.l  #512,d4
                moveq   #'h',d7
                moveq   #4,d2
                bsr     doio
                moveq   #'i',d7
                moveq   #5,d2
                bsr     doio
                moveq   #'I',d7
                moveq   #2,d2
                bsr     doio
; J: write + UPDATE on track 20 (block 220), precomp comparison in the disk log
                move.l  #$44444444,d0
                bsr     fill
                moveq   #'J',d7
                moveq   #3,d2
                move.l  #220*512,d3
                bsr     doio
                moveq   #'j',d7
                moveq   #4,d2
                bsr     doio
; K: TD_FORMAT length 512 (not a multiple of a track)
                moveq   #'K',d7
                moveq   #11,d2
                move.l  #158*TRKB,d3
                bsr     doio
; L: TD_FORMAT whole track 158, pattern 55555555, then re-read
                move.l  #$55555555,d0
                bsr     fill
                moveq   #'L',d7
                moveq   #11,d2
                move.l  #TRKB,d4
                bsr     doio
                move.l  #512,d4
                moveq   #'l',d7
                moveq   #2,d2
                bsr     doio
; M: TD_PROTSTATUS; N: CMD_WRITE odd offset; O: TD_MOTOR 0 (previous state in io_Actual)
                moveq   #'M',d7
                moveq   #15,d2
                bsr     doio
                moveq   #'N',d7
                moveq   #3,d2
                move.l  #100,d3
                bsr     doio
                moveq   #'O',d7
                moveq   #9,d2
                moveq   #0,d4
                bsr     doio
                lea     msg1(pc),a0
                bsr     puts
                lea     ioreq(pc),a1
                jsr     -450(a6)                ; CloseDevice
.out:           movem.l (sp)+,d2-d7/a2-a6
                moveq   #0,d0
                rts

; fill(d0): fills the buffer (one track, 5632 bytes) with the long d0
fill:           move.l  buf(pc),a0
                move.w  #TRKB/4-1,d1
.f:             move.l  d0,(a0)+
                dbra    d1,.f
                rts

; doio: command d2, offset d3, length d4, label d7; prints the result
doio:           lea     ioreq(pc),a1
                move.w  d2,IO_CMD(a1)
                clr.b   30(a1)
                move.l  #$DEADBEEF,IO_ACT(a1)
                move.l  d4,IO_LEN(a1)
                move.l  buf(pc),IO_DATA(a1)
                move.l  d3,IO_OFF(a1)
                cmp.w   #2,d2
                bne.s   .nr
                move.l  buf(pc),a0
                clr.l   (a0)
.nr:            jsr     -456(a6)                ; DoIO
                move.b  d7,d1
                bsr     putc
                moveq   #' ',d1
                bsr     putc
                moveq   #'E',d1
                bsr     putc
                lea     ioreq(pc),a1
                move.b  IO_ERR(a1),d0
                moveq   #1,d5
                bsr     hex
                moveq   #'A',d1
                bsr     putc
                lea     ioreq(pc),a1
                move.l  IO_ACT(a1),d0
                moveq   #7,d5
                bsr     hex
                moveq   #'L',d1
                bsr     putc
                move.l  buf(pc),a0
                move.l  (a0),d0
                moveq   #7,d5
                bsr     hex
                moveq   #10,d1
                bra.s   putc

; hex: d0 on d5+1 digits, then a space
hex:            move.l  d0,d6
                move.w  d5,d1
                addq.w  #1,d1
                lsl.w   #2,d1
                ror.l   d1,d6
.h:             rol.l   #4,d6
                move.b  d6,d1
                and.b   #15,d1
                add.b   #'0',d1
                cmp.b   #'9',d1
                bls.s   .d
                addq.b  #7,d1
.d:             bsr.s   putc
                dbra    d5,.h
                moveq   #' ',d1
                bra.s   putc

puts:           move.b  (a0)+,d1
                beq.s   .e
                bsr.s   putc
                bra.s   puts
.e:             rts

putc:           move.w  SERDATR,d0
                btst    #13,d0
                beq.s   putc
                and.w   #$FF,d1
                or.w    #$100,d1
                move.w  d1,SERDAT
                rts

vars:
buf:            dc.l    0
port:           ds.b    34
                even
ioreq:          ds.b    $38
tdname:         dc.b    "trackdisk.device",0
msg0:           dc.b    10,"TDW debut",10,0
msg1:           dc.b    "TDW fin",10,0
                even
