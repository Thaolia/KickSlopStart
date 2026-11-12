; tdcode_probe.s - trackdisk.device error codes and ETD commands (implementation track, our own test program; expected
; values from trackdisk-write-v34 §5.2 and trackdisk-raw-changeint-v34 §1).
; On DF0:, with a 512-byte buffer, writes "TC <name> <io_Error> <io_Actual>" in hex for:
;   TD_CHANGENUM (the unit's change counter, kept as C);
;   CMD_READ at offset 901120 (beyond the disk)          -> io_Error $FC (-4);
;   ETD_READ of block 0 with iotd_Count = C - 1          -> 29 (counter newer than the request);
;   ETD_READ of block 0 with iotd_Count = C              -> 0, io_Actual 512;
; then writes "TC EJECT", waits 10 s for the harness to eject the floppy, and does a CMD_READ of block 0
;   -> 29 (no floppy), then a TD_FORMAT of track 0 -> 29, io_Actual 0 (the disk test comes first, trackdisk-write
;   §7). Ends with "TC END".
; Build: vasmm68k_mot -Fhunkexe -kick1hunks -o tdcode_probe tests/tdcode_probe.s

        section code,code

IOTD_SIZE EQU 56
start:
        move.l  ($4).w,a6
        lea     dosname(pc),a1
        moveq   #0,d0
        jsr     -552(a6)             ; OpenLibrary
        lea     dosbase(pc),a0
        move.l  d0,(a0)
        moveq   #-1,d0
        jsr     -330(a6)             ; AllocSignal(-1)
        lea     port(pc),a2
        move.b  d0,15(a2)            ; mp_SigBit
        move.b  #4,8(a2)             ; ln_Type = NT_MSGPORT
        sub.l   a1,a1
        jsr     -294(a6)             ; FindTask(0)
        move.l  d0,16(a2)            ; mp_SigTask
        lea     20(a2),a0            ; mp_MsgList: NewList
        move.l  a0,8(a0)
        addq.l  #4,a0
        move.l  a0,-4(a0)
        clr.l   (a0)
        lea     ioreq(pc),a1
        move.b  #5,8(a1)             ; NT_MESSAGE
        move.l  a2,14(a1)            ; mn_ReplyPort
        move.w  #IOTD_SIZE,18(a1)    ; mn_Length
        lea     tdname(pc),a0
        moveq   #0,d0                ; unit 0
        moveq   #0,d1
        jsr     -444(a6)             ; OpenDevice
        tst.l   d0
        bne     bail
        moveq   #13,d0               ; TD_CHANGENUM
        moveq   #0,d1
        moveq   #0,d2
        bsr     doio
        lea     n_chg(pc),a0
        bsr     report
        lea     ioreq(pc),a1
        move.l  32(a1),d7            ; d7 = C
        moveq   #2,d0                ; CMD_READ beyond the disk
        move.l  #901120,d1
        move.l  #512,d2
        bsr     doio
        lea     n_range(pc),a0
        bsr     report
        lea     ioreq(pc),a1
        move.l  d7,d0
        subq.l  #1,d0
        move.l  d0,48(a1)            ; iotd_Count = C - 1
        move.l  #$8002,d0            ; ETD_READ
        moveq   #0,d1
        move.l  #512,d2
        bsr     doio
        lea     n_etdold(pc),a0
        bsr     report
        lea     ioreq(pc),a1
        move.l  d7,48(a1)            ; iotd_Count = C
        move.l  #$8002,d0
        moveq   #0,d1
        move.l  #512,d2
        bsr     doio
        lea     n_etdok(pc),a0
        bsr     report
        moveq   #9,d0                ; TD_MOTOR off
        moveq   #0,d1
        moveq   #0,d2
        bsr     doio
        lea     n_eject(pc),a0
        bsr     say
        move.l  dosbase(pc),a6
        move.l  #50*10,d1
        jsr     -198(a6)             ; Delay(10 s)
        moveq   #2,d0                ; CMD_READ without a floppy
        moveq   #0,d1
        move.l  #512,d2
        bsr     doio
        lea     n_absent(pc),a0
        bsr     report
        moveq   #11,d0               ; TD_FORMAT of track 0 without a floppy
        moveq   #0,d1
        move.l  #11*512,d2
        bsr     doio
        lea     n_fmt(pc),a0
        bsr     report
        lea     n_end(pc),a0
        bsr     say
        moveq   #0,d0
        rts
bail:
        lea     n_fail(pc),a0
        bsr     say
        moveq   #20,d0
        rts

; doio(d0 = command, d1 = offset, d2 = length): DoIO on ioreq with buf as io_Data.
doio:
        move.l  a6,-(sp)
        lea     ioreq(pc),a1
        move.w  d0,28(a1)            ; io_Command
        clr.b   30(a1)               ; io_Flags
        move.l  d1,44(a1)            ; io_Offset
        move.l  d2,36(a1)            ; io_Length
        lea     buf,a0
        move.l  a0,40(a1)            ; io_Data
        move.l  ($4).w,a6
        jsr     -456(a6)             ; DoIO
        move.l  (sp)+,a6
        rts

; report(a0 = name): "TC <name> <io_Error byte> <io_Actual>".
report:
        movem.l d2-d3,-(sp)
        lea     line(pc),a1
        move.b  #'T',(a1)+
        move.b  #'C',(a1)+
        move.b  #' ',(a1)+
.rp_name:
        move.b  (a0)+,(a1)+
        bne.s   .rp_name
        move.b  #' ',-1(a1)
        lea     ioreq(pc),a0
        move.b  31(a0),d0            ; io_Error
        ror.l   #8,d0
        moveq   #2-1,d1
        bsr.s   hex
        move.b  #' ',(a1)+
        lea     ioreq(pc),a0
        move.l  32(a0),d0            ; io_Actual
        moveq   #8-1,d1
        bsr.s   hex
        move.b  #10,(a1)+
        clr.b   (a1)
        lea     line(pc),a0
        bsr.s   say
        movem.l (sp)+,d2-d3
        rts
hex:
        rol.l   #4,d0
        move.w  d0,d2
        and.w   #$F,d2
        move.b  digits(pc,d2.w),(a1)+
        dbra    d1,hex
        rts
digits: dc.b    "0123456789ABCDEF"

; say(a0 = text ended by 0): on the serial line, polled (the production ROM does not mirror the console there).
say:
        movem.l d0-d1,-(sp)
.sy_ch:
        move.b  (a0)+,d0
        beq.s   .sy_ret
.sy_w:
        move.w  $DFF018,d1           ; SERDATR: wait for TBE
        btst    #13,d1
        beq.s   .sy_w
        and.w   #$FF,d0
        or.w    #$100,d0             ; stop bit
        move.w  d0,$DFF030           ; SERDAT
        bra.s   .sy_ch
.sy_ret:
        movem.l (sp)+,d0-d1
        rts

dosbase: dc.l    0
port:    dcb.b   34,0
ioreq:   dcb.b   IOTD_SIZE,0
line:    dcb.b   48,0
dosname: dc.b    "dos.library",0
tdname:  dc.b    "trackdisk.device",0
n_chg:    dc.b   "CHANGENUM",0
n_range:  dc.b   "READ-BEYOND",0
n_etdold: dc.b   "ETD-OLDCOUNT",0
n_etdok:  dc.b   "ETD-COUNT",0
n_absent: dc.b   "READ-NODISK",0
n_fmt:    dc.b   "FORMAT-NODISK",0
n_eject:  dc.b   "TC EJECT",10,0
n_end:    dc.b   "TC END",10,0
n_fail:   dc.b   "TC FAIL",10,0
        even

        section buffer,bss_c
buf:    ds.b    11*512
