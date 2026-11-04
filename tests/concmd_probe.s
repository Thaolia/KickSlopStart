; concmd_probe.s - console.device CMD_RESET/CLEAR/STOP/START/FLUSH on a window unit (implementation track: our own
; test program; public ABI only: exec/intuition .fd, exec/io.h, devices/console.h; expected behaviour from
; docs/analysis/console-keymap-v34.md §2.4).
; Two stages: the bootblock re-reads the first LOADSZ bytes of the disk and jumps to stage 2, which opens the
; Workbench screen, a window, and console.device on it. Replies go to a PA_IGNORE port: the probe never Waits
; (the bootblock may run before the scheduler) and tests ln_Type = NT_REPLYMSG (7) instead.
; Pending reads get their bytes from a cursor position report (CSI 6n written to the unit).
; Serial output, hex bytes:
;   "CC STOP <err> <read type after 6n> START <err> <read type> <read err> <actual>"   expected 00 05 00 07 00 nn>0
;   "CC CLEAR <err> <read type> ABORT <read err>"                                      expected 00 05 FE
;   "CC FLUSH <err> <read type> <read err> AFTER <read type>"                          expected 00 07 FE 07
;   "CC RESET <err> <read type> <read err> AFTER <read type>"                          expected 00 07 FE 07
;   "CC UPDATE <err>"                                                                  expected FD
;   "CC END"
; Build and run: tests/concmd_probe.sh <out_dir> [rom]

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018
LOADSZ   EQU 4096

_AllocMem   EQU -198
_GetMsg     EQU -372
_OpenDevice EQU -444
_DoIO       EQU -456
_SendIO     EQU -462
_AbortIO    EQU -480
_OpenLibrary EQU -552
_OpenWindow EQU -204
_OpenWorkBench EQU -210

LN_TYPE  EQU 8
MN_REPLY EQU 14
IO_DEV   EQU 20
IO_UNIT  EQU 24
IO_CMD   EQU 28
IO_FLAGS EQU 30
IO_ERR   EQU 31
IO_ACT   EQU 32
IO_LEN   EQU 36
IO_DATA  EQU 40
IOSIZE   EQU 48

; stage 1 (bootblock, a1 = trackdisk IOStdReq, a6 = ExecBase)
boot:
        movea.l a1,a5
        move.l  #LOADSZ,d0
        move.l  #$10003,d1              ; MEMF_PUBLIC|MEMF_CHIP|MEMF_CLEAR
        jsr     _AllocMem(a6)
        tst.l   d0
        beq.s   .ko
        movea.l d0,a4
        move.w  #2,IO_CMD(a5)           ; CMD_READ
        move.l  #LOADSZ,IO_LEN(a5)
        move.l  a4,IO_DATA(a5)
        clr.l   44(a5)                  ; io_Offset = 0
        movea.l a5,a1
        jsr     _DoIO(a6)
        lea     12+stage2-boot(a4),a0
        jmp     (a0)
.ko:    moveq   #-1,d0
        rts

; stage 2: a6 = ExecBase.
stage2:
        lea     neww+26(pc),a0          ; NewWindow.Title: the binary runs where stage 1 loaded it
        lea     title(pc),a1
        move.l  a1,(a0)
        lea     intname(pc),a1
        moveq   #0,d0
        jsr     _OpenLibrary(a6)
        move.l  d0,d7
        beq     hang
        move.l  d7,a6
        jsr     _OpenWorkBench(a6)
        lea     neww(pc),a0
        jsr     _OpenWindow(a6)
        tst.l   d0
        beq     hang
        move.l  d0,d6                   ; d6 = window
        move.l  ($4).w,a6
        lea     port(pc),a0             ; reply port: PA_IGNORE, empty list
        move.b  #4,LN_TYPE(a0)
        move.b  #2,14(a0)
        lea     24(a0),a1
        move.l  a1,20(a0)
        clr.l   24(a0)
        lea     20(a0),a1
        move.l  a1,28(a0)
        lea     ioc(pc),a1
        bsr     ioprep
        move.l  d6,IO_DATA(a1)
        move.l  #124,IO_LEN(a1)
        lea     conname(pc),a0
        moveq   #0,d0
        moveq   #0,d1
        jsr     _OpenDevice(a6)
        tst.l   d0
        bne     hang
        lea     ioc(pc),a0              ; the read and write requests share the opened unit
        lea     ior(pc),a1
        bsr     iocopy
        lea     iow(pc),a1
        bsr     iocopy

; --- STOP: a read stays queued although a report arrives; START serves it
        lea     m_stop(pc),a0
        bsr     puts
        moveq   #6,d0
        bsr     ctl                     ; prints io_Error
        bsr     readsend
        bsr     cpr
        bsr     rtype
        lea     m_start(pc),a0
        bsr     puts
        moveq   #7,d0
        bsr     ctl
        bsr     rtype
        bsr     rerr
        lea     ior(pc),a1
        move.l  IO_ACT(a1),d0
        bsr     shex
        bsr     reap
        bsr     nl

; --- CLEAR: a report written with no read pending is dropped; the next read waits
        lea     m_clear(pc),a0
        bsr     puts
        bsr     cpr
        moveq   #5,d0
        bsr     ctl
        bsr     readsend
        bsr     rtype
        lea     m_abort(pc),a0
        bsr     puts
        lea     ior(pc),a1
        jsr     _AbortIO(a6)
        bsr     rerr
        bsr     reap
        bsr     nl

; --- FLUSH: the pending read comes back with IOERR_ABORTED; the unit keeps running
        lea     m_flush(pc),a0
        bsr     puts
        bsr     readsend
        moveq   #8,d0
        bsr     ctl
        bsr     rtype
        bsr     rerr
        bsr     reap
        bsr     after

; --- RESET on a stopped unit: the read is aborted and the unit runs again
        lea     m_reset(pc),a0
        bsr     puts
        bsr     readsend
        lea     ioc(pc),a1
        move.w  #6,IO_CMD(a1)
        jsr     _DoIO(a6)
        moveq   #1,d0
        bsr     ctl
        bsr     rtype
        bsr     rerr
        bsr     reap
        bsr     after

        lea     m_update(pc),a0
        bsr     puts
        moveq   #4,d0
        bsr     ctl
        bsr     nl
        lea     m_end(pc),a0
        bsr     puts
hang:   bra.s   hang

; after: " AFTER <read type>" for a read sent before a report, then newline.
after:
        lea     m_after(pc),a0
        bsr     puts
        bsr     readsend
        bsr     cpr
        bsr     rtype
        bsr     reap
        bra     nl

; ctl(d0 = command): DoIO on ioc, prints " <io_Error>".
ctl:
        lea     ioc(pc),a1
        move.w  d0,IO_CMD(a1)
        jsr     _DoIO(a6)
        lea     ioc(pc),a1
        move.b  IO_ERR(a1),d0
        bra     shex

; readsend: SendIO of a 16-byte CMD_READ on ior.
readsend:
        lea     ior(pc),a1
        move.b  #5,LN_TYPE(a1)          ; NT_MESSAGE again: a reply sets NT_REPLYMSG
        move.w  #2,IO_CMD(a1)
        move.l  #16,IO_LEN(a1)
        lea     rbuf(pc),a0
        move.l  a0,IO_DATA(a1)
        clr.l   IO_ACT(a1)
        jmp     _SendIO(a6)

; cpr: writes CSI 6n (cursor position report into the read stream).
cpr:
        lea     iow(pc),a1
        move.w  #3,IO_CMD(a1)
        move.l  #3,IO_LEN(a1)
        lea     csi6n(pc),a0
        move.l  a0,IO_DATA(a1)
        jmp     _DoIO(a6)

rtype:  lea     ior(pc),a1
        move.b  LN_TYPE(a1),d0
        bra.s   shex
rerr:   lea     ior(pc),a1
        move.b  IO_ERR(a1),d0
        bra.s   shex

; reap: removes every replied message from the port.
reap:   lea     port(pc),a0
        jsr     _GetMsg(a6)
        tst.l   d0
        bne.s   reap
        rts

ioprep: move.b  #5,LN_TYPE(a1)          ; NT_MESSAGE
        lea     port(pc),a2
        move.l  a2,MN_REPLY(a1)
        move.w  #IOSIZE,18(a1)
        rts
; iocopy(a0 = opened request, a1 = new one): same port, device and unit.
iocopy: bsr.s   ioprep
        move.l  IO_DEV(a0),IO_DEV(a1)
        move.l  IO_UNIT(a0),IO_UNIT(a1)
        rts

shex:   move.l  d0,-(sp)
        moveq   #' ',d0
        bsr.s   putc
        move.l  (sp),d0
        lsr.b   #4,d0
        bsr.s   .dig
        move.l  (sp)+,d0
.dig:   and.w   #$F,d0
        move.b  digits(pc,d0.w),d0
        bra.s   putc
digits: dc.b    "0123456789ABCDEF"

nl:     moveq   #10,d0
        bra.s   putc
puts:   move.b  (a0)+,d0
        beq.s   .ret
        bsr.s   putc
        bra.s   puts
.ret:   rts

putc:   movem.l d0/d2,-(sp)
        move.w  #$4000,d2
.wt:    btst    #13-8,SERDATR
        bne.s   .tx
        dbra    d2,.wt
.tx:    and.w   #$FF,d0
        or.w    #$100,d0
        move.w  d0,SERDAT
        movem.l (sp)+,d0/d2
        rts

neww:   dc.w    20,20,400,100
        dc.b    0,1
        dc.l    0                       ; IDCMP
        dc.l    $100F                   ; ACTIVATE, WINDOWSIZING/DRAG/DEPTH
        dc.l    0,0,0,0,0               ; Title set at run time
        dc.w    100,50,640,200
        dc.w    1                       ; WBENCHSCREEN
intname: dc.b   "intuition.library",0
conname: dc.b   "console.device",0
title:   dc.b   "concmd",0
csi6n:   dc.b   $9B,"6n"
m_stop:  dc.b   "CC STOP",0
m_start: dc.b   " START",0
m_clear: dc.b   "CC CLEAR",0
m_abort: dc.b   " ABORT",0
m_flush: dc.b   "CC FLUSH",0
m_reset: dc.b   "CC RESET",0
m_after: dc.b   " AFTER",0
m_update: dc.b  "CC UPDATE",0
m_end:   dc.b   "CC END",10,0
        even
port:   dcb.b   34,0
ioc:    dcb.b   IOSIZE,0
ior:    dcb.b   IOSIZE,0
iow:    dcb.b   IOSIZE,0
rbuf:   dcb.b   16,0
