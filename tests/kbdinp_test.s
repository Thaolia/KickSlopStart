; tests/kbdinp_test.s - keyboard.device and input.device commands (implementation-side test of
; docs/analysis/keyboard-input-devices-v34.md). Run from a startup-sequence (tests/garea_probe.sh <rom> <exe> <out>);
; results on the serial port, one "NAME value(s)" line per check (io_Error as 2 hex digits). Expected:
;   KOPEN 00
;   KINV FD FD FD FD               CMD_READ, CMD_WRITE, CMD_UPDATE, command 14 refused (-3)
;   KMAT FC 00 0000000D            READMATRIX io_Length 16 -> -4; 13 -> 0, io_Actual 13
;   KGEN 00 00 00 00               CMD_CLEAR, CMD_STOP, CMD_START, CMD_FLUSH
;   KREAD2 0000002C 0020 00A0 1    3 events buffered, io_Length 44: two events chained (1 = links right)
;   KREAD1 00000016 0045           the third one stays for the next read
;   KBADLEN FC                     READEVENT io_Length 10
;   KSTOP 0 00 0033                stopped: the read stays pending (0), served by CMD_START
;   KFLUSH FE 00                   pending read aborted by CMD_FLUSH
;   KRESET FE 00 0044              CMD_RESET aborts the pending read, keeps the ring
;   KABORT FE                      AbortIO of a pending read
;   KRHD 00                        KBD_RESETHANDLERDONE
;   IOPEN 00
;   IINV FD FD FD FD FD            commands 0, 2, 3, 4, 17 refused
;   IGEN 00 00 00 00 00            CMD_CLEAR, CMD_STOP, CMD_START, CMD_RESET, CMD_FLUSH
;   ISTOP 40 00                    gameport mouse source after CMD_STOP, after CMD_START
;   ICLEAR 00                      CMD_CLEAR through SendIO + WaitIO returns
;   ITRIG FC 00 00000008           IND_SETMTRIG io_Length 4 -> -4; 8 -> 0, io_Actual 8
;   IPORT FC 00 00000001 01 01 01  IND_SETMPORT io_Length 0 -> -4; port 1 -> 0, io_Actual 1, mouse source 1,
;                                  gameport unit 0 still GPCT_MOUSE, unit 1 now GPCT_MOUSE
;   IPORT0 00                      port 0 again: source 0
;   ITYPE 80 00                    IND_SETMTYPE 0 -> no mouse; 1 -> port 0 again
;   IBADPORT 00 80 00              IND_SETMPORT 5: error 0 but no mouse; port 0 again
;   IWRITE 00000000                IND_WRITEEVENT forces ie_NextEvent to NULL
; The ring is filled by writing the private layout of src/exec/kbddev.s (no key can be typed headless).

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018
KD_RD    EQU 78                         ; keyboard.device base: ring read / write index, ring entries
KD_WR    EQU 80
KD_BUF   EQU 86
GPB_MSRC EQU 44                         ; gameport.device base: system mouse source

start:  move.l  4.w,a6
        moveq   #-1,d0
        jsr     -330(a6)                ; AllocSignal
        lea     port,a0
        move.b  d0,15(a0)
        move.b  #4,8(a0)                ; NT_MSGPORT, PA_SIGNAL
        sub.l   a1,a1
        jsr     -294(a6)                ; FindTask(NULL)
        lea     port,a0
        move.l  d0,16(a0)
        lea     20(a0),a0
        move.l  a0,8(a0)
        addq.l  #4,a0
        clr.l   (a0)
        move.l  a0,-4(a0)
        lea     io,a0
        bsr     ioinit
        lea     io2,a0
        bsr     ioinit

        lea     m_kopen(pc),a0          ; --- keyboard.device
        bsr     puts
        lea     kbdname(pc),a0
        moveq   #0,d0
        lea     io,a1
        moveq   #0,d1
        jsr     -444(a6)
        bsr     hex2
        bsr     nl
        tst.b   d0
        bne     .inp
        move.l  io+20,kbase
        move.l  io+20,io2+20
        move.l  io+24,io2+24

        lea     m_kinv(pc),a0
        bsr     puts
        moveq   #2,d0
        bsr     kio0
        moveq   #3,d0
        bsr     kio0
        moveq   #4,d0
        bsr     kio0
        moveq   #14,d0
        bsr     kio0
        bsr     nl

        lea     m_kmat(pc),a0
        bsr     puts
        moveq   #10,d0
        moveq   #16,d1
        lea     buf,a0
        bsr     kio
        bsr     hex2
        moveq   #10,d0
        moveq   #13,d1
        lea     buf,a0
        bsr     kio
        bsr     hex2
        move.l  io+32,d0
        bsr     hex8
        bsr     nl

        lea     m_kgen(pc),a0
        bsr     puts
        moveq   #5,d0
        bsr     kio0
        moveq   #6,d0
        bsr     kio0
        moveq   #7,d0
        bsr     kio0
        moveq   #8,d0
        bsr     kio0
        bsr     nl

        jsr     -120(a6)                ; Disable: three entries in the ring
        move.l  kbase,a0
        move.l  #$00200000,KD_BUF(a0)
        move.l  #$00A00000,KD_BUF+4(a0)
        move.l  #$00450000,KD_BUF+8(a0)
        clr.w   KD_RD(a0)
        move.w  #12,KD_WR(a0)
        jsr     -126(a6)
        lea     m_kread2(pc),a0
        bsr     puts
        moveq   #9,d0
        moveq   #44,d1
        lea     buf,a0
        bsr     kio
        move.l  io+32,d0
        bsr     hex8
        move.w  buf+6,d0
        bsr     hex4
        move.w  buf+22+6,d0
        bsr     hex4
        moveq   #0,d0
        lea     buf+22,a0
        cmp.l   buf,a0
        bne.s   .k1
        tst.l   buf+22
        bne.s   .k1
        moveq   #1,d0
.k1:    bsr     dig
        bsr     nl
        lea     m_kread1(pc),a0
        bsr     puts
        moveq   #9,d0
        moveq   #22,d1
        lea     buf,a0
        bsr     kio
        move.l  io+32,d0
        bsr     hex8
        move.w  buf+6,d0
        bsr     hex4
        bsr     nl

        lea     m_kbad(pc),a0
        bsr     puts
        moveq   #9,d0
        moveq   #10,d1
        lea     buf,a0
        bsr     kio
        bsr     hex2
        bsr     nl

        lea     m_kstop(pc),a0          ; stopped unit: the read waits for CMD_START
        bsr     puts
        moveq   #6,d0
        bsr     kio2
        moveq   #$33,d0
        bsr     poke1
        bsr     sendread
        moveq   #0,d0
        cmp.b   #7,io+8                 ; NT_REPLYMSG?
        bne.s   .k2
        moveq   #1,d0
.k2:    bsr     dig
        moveq   #7,d0
        bsr     kio2
        bsr     waitio
        bsr     hex2
        move.w  buf+6,d0
        bsr     hex4
        bsr     nl

        lea     m_kflush(pc),a0
        bsr     puts
        bsr     sendread
        moveq   #8,d0
        bsr     kio2
        move.l  d0,-(sp)
        bsr     waitio
        bsr     hex2
        move.l  (sp)+,d0
        bsr     hex2
        bsr     nl

        lea     m_kreset(pc),a0
        bsr     puts
        bsr     sendread
        moveq   #$44,d0
        bsr     poke1
        moveq   #1,d0
        bsr     kio2
        move.l  d0,-(sp)
        bsr     waitio
        bsr     hex2
        move.l  (sp)+,d0
        bsr     hex2
        moveq   #9,d0
        moveq   #22,d1
        lea     buf,a0
        bsr     kio
        move.w  buf+6,d0
        bsr     hex4
        bsr     nl

        lea     m_kabort(pc),a0
        bsr     puts
        bsr     sendread
        lea     io,a1
        jsr     -480(a6)                ; AbortIO
        bsr     waitio
        bsr     hex2
        bsr     nl

        lea     m_krhd(pc),a0
        bsr     puts
        moveq   #13,d0
        bsr     kio0
        bsr     nl
        lea     io,a1
        jsr     -450(a6)                ; CloseDevice

.inp:   lea     m_iopen(pc),a0          ; --- input.device
        bsr     puts
        lea     inpname(pc),a0
        moveq   #0,d0
        lea     io,a1
        moveq   #0,d1
        jsr     -444(a6)
        bsr     hex2
        bsr     nl
        tst.b   d0
        bne     .end
        move.l  io+20,io2+20
        lea     $15E(a6),a0             ; DeviceList
        lea     gpname(pc),a1
        jsr     -276(a6)                ; FindName
        move.l  d0,gbase
        beq     .end

        lea     m_iinv(pc),a0
        bsr     puts
        moveq   #0,d0
        bsr     kio0
        moveq   #2,d0
        bsr     kio0
        moveq   #3,d0
        bsr     kio0
        moveq   #4,d0
        bsr     kio0
        moveq   #17,d0
        bsr     kio0
        bsr     nl

        lea     m_igen(pc),a0
        bsr     puts
        moveq   #5,d0
        bsr     kio0
        moveq   #6,d0
        bsr     kio0
        move.l  gbase,a0
        move.b  GPB_MSRC(a0),msrc1
        moveq   #7,d0
        bsr     kio0
        move.l  gbase,a0
        move.b  GPB_MSRC(a0),msrc2
        moveq   #1,d0
        bsr     kio0
        moveq   #8,d0
        bsr     kio0
        bsr     nl
        lea     m_istop(pc),a0
        bsr     puts
        move.b  msrc1,d0
        bsr     hex2
        move.b  msrc2,d0
        bsr     hex2
        bsr     nl

        lea     m_iclear(pc),a0
        bsr     puts
        lea     io,a1
        move.w  #5,28(a1)
        clr.b   30(a1)
        jsr     -462(a6)                ; SendIO
        bsr     waitio
        bsr     hex2
        bsr     nl

        lea     m_itrig(pc),a0
        bsr     puts
        moveq   #16,d0
        moveq   #4,d1
        lea     trig(pc),a0
        bsr     kio
        bsr     hex2
        moveq   #16,d0
        moveq   #8,d1
        lea     trig(pc),a0
        bsr     kio
        bsr     hex2
        move.l  io+32,d0
        bsr     hex8
        bsr     nl

        lea     m_iport(pc),a0
        bsr     puts
        moveq   #14,d0
        moveq   #0,d1
        lea     one(pc),a0
        bsr     kio
        bsr     hex2
        moveq   #14,d0
        moveq   #1,d1
        lea     one(pc),a0
        bsr     kio
        bsr     hex2
        move.l  io+32,d0
        bsr     hex8
        bsr     msrc
        moveq   #0,d0
        bsr     askctype
        moveq   #1,d0
        bsr     askctype
        bsr     nl
        lea     m_iport0(pc),a0
        bsr     puts
        moveq   #14,d0
        lea     zero(pc),a0
        bsr     kio1
        bsr     msrc
        bsr     nl

        lea     m_itype(pc),a0
        bsr     puts
        moveq   #15,d0
        lea     zero(pc),a0
        bsr     kio1
        bsr     msrc
        moveq   #15,d0
        lea     one(pc),a0
        bsr     kio1
        bsr     msrc
        bsr     nl

        lea     m_ibad(pc),a0
        bsr     puts
        moveq   #14,d0
        lea     five(pc),a0
        bsr     kio1
        bsr     hex2
        bsr     msrc
        moveq   #14,d0
        lea     zero(pc),a0
        bsr     kio1
        bsr     msrc
        bsr     nl

        lea     m_iwrite(pc),a0         ; IND_WRITEEVENT of a 2-event list (IECLASS_NULL)
        bsr     puts
        lea     buf,a0
        moveq   #43/4,d0
.cl:    clr.l   (a0)+
        dbra    d0,.cl
        lea     buf+22,a0
        move.l  a0,buf
        moveq   #11,d0
        moveq   #22,d1
        lea     buf,a0
        bsr     kio
        move.l  buf,d0
        bsr     hex8
        bsr     nl
        lea     io,a1
        jsr     -450(a6)
.end:   lea     m_end(pc),a0
        bsr     puts
        moveq   #0,d0
        rts

; ioinit(a0 = IOStdReq): reply port, length.
ioinit: move.b  #5,8(a0)                ; NT_MESSAGE
        move.l  #port,14(a0)
        move.w  #48,18(a0)
        rts
; kio(d0 = command, d1 = io_Length, a0 = io_Data): DoIO(io) -> d0 = io_Error (byte). kio0: no data, prints the
; error. kio1: io_Length 1. kio2: DoIO on io2 (no data) -> d0 = io_Error.
kio0:   moveq   #0,d1
        sub.l   a0,a0
        bsr.s   kio
        bra     hex2
kio1:   moveq   #1,d1
kio:    lea     io,a1
kiox:   move.w  d0,28(a1)
        move.l  d1,36(a1)
        move.l  a0,40(a1)
        clr.l   32(a1)
        clr.b   30(a1)
        move.l  a1,-(sp)
        jsr     -456(a6)                ; DoIO
        move.l  (sp)+,a1
        moveq   #0,d0
        move.b  31(a1),d0
        rts
kio2:   moveq   #0,d1
        sub.l   a0,a0
        lea     io2,a1
        bra.s   kiox
; sendread: SendIO(io) of a KBD_READEVENT of one event into buf.
sendread:
        lea     io,a1
        move.w  #9,28(a1)
        move.l  #22,36(a1)
        move.l  #buf,40(a1)
        clr.w   buf+6
        jsr     -462(a6)
        rts
; waitio: WaitIO(io) -> d0 = io_Error (byte).
waitio: lea     io,a1
        jsr     -474(a6)
        moveq   #0,d0
        move.b  io+31,d0
        rts
; poke1(d0 = code): the ring holds that single entry (qualifier 0).
poke1:  move.l  d0,-(sp)
        jsr     -120(a6)
        move.l  kbase,a0
        move.l  (sp)+,d0
        swap    d0
        clr.w   d0
        move.l  d0,KD_BUF(a0)
        clr.w   KD_RD(a0)
        move.w  #4,KD_WR(a0)
        jsr     -126(a6)
        rts
; msrc: prints the gameport mouse source byte.
msrc:   move.l  gbase,a0
        move.b  GPB_MSRC(a0),d0
        bra     hex2
; askctype(d0 = unit): GPD_ASKCTYPE on that gameport unit, prints the type.
askctype:
        lea     io3,a1
        move.l  a1,a0
        moveq   #11,d1
.c:     clr.l   (a0)+
        dbra    d1,.c
        lea     gpname(pc),a0
        moveq   #0,d1
        jsr     -444(a6)
        tst.b   d0
        bne.s   .f
        lea     io3,a1
        move.w  #10,28(a1)
        move.l  #1,36(a1)
        move.l  #ctype,40(a1)
        move.b  #1,30(a1)               ; IOF_QUICK
        move.l  20(a1),a6
        jsr     -30(a6)                 ; BeginIO
        move.l  4.w,a6
        lea     io3,a1
        jsr     -450(a6)
        move.b  ctype,d0
        bra     hex2
.f:     moveq   #-1,d0
        bra     hex2

dig:    add.b   #'0',d0
        lea     hbuf,a0
        move.b  d0,(a0)+
        move.b  #' ',(a0)+
        clr.b   (a0)
        lea     hbuf,a0
        bra.s   puts
nl:     lea     m_nl(pc),a0
; puts(a0): NUL-terminated string on the serial port. Clobbers d1/a0.
puts:   move.b  (a0)+,d1
        beq.s   .e
.w:     btst    #5,SERDATR              ; TBE (bit 13)
        beq.s   .w
        and.w   #$FF,d1
        or.w    #$100,d1
        move.w  d1,SERDAT
        bra.s   puts
.e:     rts
; hex8(d0.l) / hex4(d0.w) / hex2(d0.b): hex digits and a space. d0 preserved.
hex8:   moveq   #7,d1
        bra.s   hexn
hex4:   swap    d0
        moveq   #3,d1
        bsr.s   hexn
        swap    d0
        rts
hex2:   ror.l   #8,d0
        moveq   #1,d1
        bsr.s   hexn
        rol.l   #8,d0
        rts
hexn:   lea     hbuf,a0
.dg:    rol.l   #4,d0
        move.l  d0,-(sp)
        and.w   #15,d0
        move.b  hexd(pc,d0.w),(a0)+
        move.l  (sp)+,d0
        dbra    d1,.dg
        move.b  #' ',(a0)+
        clr.b   (a0)
        move.l  d0,-(sp)
        lea     hbuf,a0
        bsr.s   puts
        move.l  (sp)+,d0
        rts
hexd:   dc.b    "0123456789ABCDEF"

trig:   dc.w    3,0,1,1                 ; DOWNKEYS|UPKEYS, timeout 0, xdelta 1, ydelta 1
zero:   dc.b    0
one:    dc.b    1
five:   dc.b    5
kbdname: dc.b   "keyboard.device",0
inpname: dc.b   "input.device",0
gpname: dc.b    "gameport.device",0
m_kopen: dc.b   13,10,"KOPEN ",0
m_kinv: dc.b    "KINV ",0
m_kmat: dc.b    "KMAT ",0
m_kgen: dc.b    "KGEN ",0
m_kread2: dc.b  "KREAD2 ",0
m_kread1: dc.b  "KREAD1 ",0
m_kbad: dc.b    "KBADLEN ",0
m_kstop: dc.b   "KSTOP ",0
m_kflush: dc.b  "KFLUSH ",0
m_kreset: dc.b  "KRESET ",0
m_kabort: dc.b  "KABORT ",0
m_krhd: dc.b    "KRHD ",0
m_iopen: dc.b   "IOPEN ",0
m_iinv: dc.b    "IINV ",0
m_igen: dc.b    "IGEN ",0
m_istop: dc.b   "ISTOP ",0
m_iclear: dc.b  "ICLEAR ",0
m_itrig: dc.b   "ITRIG ",0
m_iport: dc.b   "IPORT ",0
m_iport0: dc.b  "IPORT0 ",0
m_itype: dc.b   "ITYPE ",0
m_ibad: dc.b    "IBADPORT ",0
m_iwrite: dc.b  "IWRITE ",0
m_nl:   dc.b    13,10,0
m_end:  dc.b    "KBDINP END",13,10,"GAP fin",13,10,0
        even

        section bss,bss
kbase:  ds.l    1
gbase:  ds.l    1
port:   ds.b    34
io:     ds.b    48
io2:    ds.b    48
io3:    ds.b    48
buf:    ds.b    48
hbuf:   ds.b    12
msrc1:  ds.b    1
msrc2:  ds.b    1
ctype:  ds.b    1
        even
