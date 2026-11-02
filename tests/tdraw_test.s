; tests/tdraw_test.s - trackdisk raw I/O, seek, drive type and change interrupts (implementation-side test,
; docs/analysis/trackdisk-raw-changeint-v34.md). Run from a startup-sequence:
;   tests/garea_probe.sh <rom> <exe> <out>          (no argument: short change wait)
;   argument "W": waits up to 150 s for two change interrupts (eject + insert driven by tests/dskchg_run.sh)
; Results on the serial port, one "NAME value(s)" line per check. Expected:
;   OPEN 00                         OpenDevice unit 0
;   CHGNUM 00000001                 change counter after a boot with a disk
;   DTYPE 00 00000001               TD_GETDRIVETYPE: DRIVE3_5
;   NTRK 00 000000A0                TD_GETNUMTRACKS: 160
;   NOCMD FD FD FD FD               CMD_RESET/STOP/START/FLUSH: IOERR_NOCMD
;   SEEK 00 FC 00 00                offsets 5632*10, 100, 901120 (bound included), 0
;   RAWBAD FC FC                    RAWREAD track 160; length 32768
;   RAW10 00 CAFEF00D <bit> FF0Ass.. 1   track 10: io_Actual untouched, first sync bit position, header of the first
;                                   sector (format FF, track 0A), header checksum good
;   IDX 00 <bit> 00 <bit> NOIDX ... two INDEXSYNC reads of track 0 start at the same place (+- a few bits);
;                                   three plain reads start anywhere
;   RAWW 00 00 00000000             RAWWRITE of a self-encoded track 150 (after a CMD_READ that cached the old one),
;                                   then CMD_READ of track 150: error, mismatching longs
;   REMOVE 00  ADDCI 00000000       TD_REMOVE set; TD_ADDCHANGEINT pending (CheckIO = 0)
;   CHG n int rem                   one line per change seen during the wait (counter, change and remove interrupts)
;   REMCI 00 <req>                  TD_REMCHANGEINT: done (CheckIO != 0)
;   CHGINT int rem                  totals (W run with eject + insert: 2 2)
; Assembly: vasmm68k_mot -Fhunkexe -kick1hunks. Authored code; public structures (exec/io.h, devices/trackdisk.h).

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018
IO_COMMAND EQU 28
IO_FLAGS EQU 30
IO_ERROR EQU 31
IO_ACTUAL EQU 32
IO_LENGTH EQU 36
IO_DATA  EQU 40
IO_OFFSET EQU 44
TDSIZE   EQU 56
RAWLEN   EQU 12800
RAWWORDS EQU RAWLEN/2
WTRK     EQU 150
GAPL     EQU 415                ; guard of the written track: 1660 bytes
SECL     EQU 272                ; one sector: 1088 bytes
TRKL     EQU GAPL+11*SECL       ; 3407 longs, then the tail word
WRLEN    EQU TRKL*4+2
MASK     EQU $55555555

        section code,code
start:  move.l  d0,argl
        move.l  a0,argp
        move.l  4.w,a6
        lea     dosname(pc),a1
        moveq   #0,d0
        jsr     -552(a6)                ; OpenLibrary
        move.l  d0,dosbase
        beq     out
        move.l  #16384,d0
        move.l  #$10002,d1              ; MEMF_CHIP|MEMF_CLEAR
        jsr     -198(a6)
        move.l  d0,rawbuf
        beq     out
        move.l  #5632,d0
        move.l  #$10001,d1
        jsr     -198(a6)
        move.l  d0,secbuf
        beq     out
        moveq   #-1,d0
        jsr     -330(a6)                ; AllocSignal
        lea     port,a2
        move.b  #4,8(a2)                ; NT_MSGPORT
        clr.b   14(a2)                  ; PA_SIGNAL
        move.b  d0,15(a2)
        sub.l   a1,a1
        jsr     -294(a6)                ; FindTask(0)
        move.l  d0,16(a2)
        lea     20(a2),a0
        move.l  a0,8(a0)
        addq.l  #4,a0
        clr.l   (a0)
        move.l  a0,-4(a0)
        lea     req1,a1
        move.l  a2,14(a1)
        move.w  #TDSIZE,18(a1)
        lea     tdname(pc),a0
        moveq   #0,d0
        moveq   #0,d1
        jsr     -444(a6)                ; OpenDevice
        move.l  d0,-(sp)
        lea     m_open(pc),a0
        bsr     puts
        move.l  (sp)+,d0
        bsr     hex2
        bsr     nl
        tst.b   d0
        bne     out
        lea     req1,a0
        lea     req2,a1
        moveq   #TDSIZE/4-1,d0
.cp:    move.l  (a0)+,(a1)+
        dbra    d0,.cp

        lea     m_chgnum(pc),a0         ; --- change counter after the boot
        bsr     puts
        moveq   #13,d0                  ; TD_CHANGENUM
        bsr     doio
        bsr     pact
        bsr     nl

        lea     m_dtype(pc),a0          ; --- TD_GETDRIVETYPE / TD_GETNUMTRACKS
        bsr     puts
        moveq   #18,d0
        bsr     doio
        bsr     perr
        bsr     pact
        bsr     nl
        lea     m_ntrk(pc),a0
        bsr     puts
        moveq   #19,d0
        bsr     doio
        bsr     perr
        bsr     pact
        bsr     nl

        lea     m_nocmd(pc),a0          ; --- CMD_RESET / STOP / START / FLUSH
        bsr     puts
        lea     nocmds(pc),a2
.nc:    moveq   #0,d0
        move.b  (a2)+,d0
        beq.s   .ncd
        bsr     doio
        bsr     perr
        bra.s   .nc
.ncd:   bsr     nl

        lea     m_seek(pc),a0           ; --- TD_SEEK
        bsr     puts
        lea     seekoffs(pc),a2
        moveq   #3,d2
.sk:    lea     req1,a1
        move.l  (a2)+,IO_OFFSET(a1)
        moveq   #10,d0
        bsr     doio
        bsr     perr
        dbra    d2,.sk
        bsr     nl

        lea     m_rawbad(pc),a0         ; --- raw bounds
        bsr     puts
        lea     req1,a1
        move.l  rawbuf,IO_DATA(a1)
        move.l  #RAWLEN,IO_LENGTH(a1)
        move.l  #160,IO_OFFSET(a1)
        clr.b   IO_FLAGS(a1)
        moveq   #16,d0
        bsr     doio
        bsr     perr
        lea     req1,a1
        move.l  #32768,IO_LENGTH(a1)
        clr.l   IO_OFFSET(a1)
        moveq   #16,d0
        bsr     doio
        bsr     perr
        bsr     nl

        lea     m_raw10(pc),a0          ; --- TD_RAWREAD track 10
        bsr     puts
        moveq   #10,d0
        moveq   #0,d1
        bsr     rawread
        bsr     perr
        bsr     pact
        moveq   #0,d0
        bsr     findsync
        move.l  d0,d6                   ; d6 = bit position of the first sync | -1
        bsr     hex8
        tst.l   d6
        bmi     .r10e
.r10s:  move.l  d6,d0                   ; skip the sync words
        bsr     get32
        swap    d0
        cmp.w   #$4489,d0
        bne.s   .r10h
        add.l   #16,d6
        bra.s   .r10s
.r10h:  move.l  d6,d0                   ; info = odd/even combine
        bsr     get32
        move.l  d0,d4
        move.l  d6,d0
        add.l   #32,d0
        bsr     get32
        and.l   #MASK,d4
        add.l   d4,d4
        and.l   #MASK,d0
        or.l    d0,d4
        move.l  d4,d0
        bsr     hex8
        moveq   #0,d5                   ; header checksum: XOR of the 10 longs (info + label) & MASK
        moveq   #9,d3
        move.l  d6,d7
.r10c:  move.l  d7,d0
        bsr     get32
        eor.l   d0,d5
        add.l   #32,d7
        dbra    d3,.r10c
        and.l   #MASK,d5
        move.l  d7,d0                   ; stored checksum (odd, even)
        bsr     get32
        move.l  d0,d4
        move.l  d7,d0
        add.l   #32,d0
        bsr     get32
        and.l   #MASK,d4
        add.l   d4,d4
        and.l   #MASK,d0
        or.l    d4,d0
        moveq   #0,d1
        cmp.l   d5,d0
        bne.s   .r10k
        moveq   #1,d1
.r10k:  move.l  d1,d0
        bsr     dig
.r10e:  bsr     nl

        lea     m_idx(pc),a0            ; --- INDEXSYNC
        bsr     puts
        moveq   #1,d2
.ix:    moveq   #0,d0
        moveq   #$10,d1                 ; IOTDF_INDEXSYNC
        bsr     rawread
        bsr     perr
        moveq   #0,d0
        bsr     findsync
        bsr     hex8
        dbra    d2,.ix
        lea     m_noidx(pc),a0
        bsr     puts
        moveq   #2,d2
.nx:    moveq   #0,d0
        moveq   #0,d1
        bsr     rawread
        bsr     perr
        moveq   #0,d0
        bsr     findsync
        bsr     hex8
        dbra    d2,.nx
        bsr     nl

        lea     m_raww(pc),a0           ; --- TD_RAWWRITE of track 150, checked by CMD_READ
        bsr     puts
        bsr     readw                   ; old contents enter the track cache
        move.l  rawbuf,a0
        moveq   #0,d0
        move.b  #WTRK,d0
        bsr     encode
        lea     req1,a1
        move.l  rawbuf,IO_DATA(a1)
        move.l  #WRLEN,IO_LENGTH(a1)
        move.l  #WTRK,IO_OFFSET(a1)
        clr.b   IO_FLAGS(a1)
        moveq   #17,d0
        bsr     doio
        bsr     perr
        bsr     readw
        bsr     perr
        move.l  secbuf,a0               ; long k of sector n = $5A000000 | n << 16 | k
        moveq   #0,d4                   ; d4 = mismatches
        moveq   #0,d1
.vs:    moveq   #0,d2
.vl:    move.l  d1,d0
        swap    d0
        or.l    #$5A000000,d0
        or.w    d2,d0
        cmp.l   (a0)+,d0
        beq.s   .vok
        addq.l  #1,d4
.vok:   addq.w  #1,d2
        cmp.w   #128,d2
        bne.s   .vl
        addq.w  #1,d1
        cmp.w   #11,d1
        bne.s   .vs
        move.l  d4,d0
        bsr     hex8
        bsr     nl

        lea     m_remove(pc),a0         ; --- TD_REMOVE, TD_ADDCHANGEINT
        bsr     puts
        lea     remint,a0
        lea     remcnt,a1
        bsr     mkint
        lea     req1,a1
        move.l  #remint,IO_DATA(a1)
        moveq   #12,d0
        bsr     doio
        bsr     perr
        lea     chgint,a0
        lea     chgcnt,a1
        bsr     mkint
        lea     req2,a1
        move.w  #20,IO_COMMAND(a1)
        move.l  #chgint,IO_DATA(a1)
        move.l  4.w,a6
        jsr     -462(a6)                ; SendIO
        lea     req2,a1
        jsr     -468(a6)                ; CheckIO
        move.l  d0,-(sp)
        lea     m_addci(pc),a0
        bsr     puts
        move.l  (sp)+,d0
        bsr     hex8
        bsr     nl

        moveq   #6,d7                   ; --- change wait: 3 s, or 150 s with "W" (until two change interrupts)
        bsr     hasw
        beq.s   .wt
        move.w  #300,d7
.wt:    moveq   #-1,d6                  ; d6 = last counter printed
        moveq   #-1,d5                  ; d5 = last interrupt count printed
.wl:    moveq   #14,d0                  ; TD_CHANGESTATE: drives the probe step that sees an insertion
        bsr     doio
        moveq   #13,d0
        bsr     doio
        lea     req1,a1
        move.l  IO_ACTUAL(a1),d4
        move.l  chgcnt,d0
        add.l   remcnt,d0
        cmp.l   d4,d6
        bne.s   .wp
        cmp.l   d0,d5
        beq.s   .wn
.wp:    move.l  d4,d6
        move.l  d0,d5
        lea     m_chg(pc),a0
        bsr     puts
        move.l  d4,d0
        bsr     hex8
        move.l  chgcnt,d0
        bsr     hex8
        move.l  remcnt,d0
        bsr     hex8
        bsr     nl
.wn:    bsr     hasw
        beq.s   .wd
        cmp.l   #2,chgcnt
        bhs.s   .we
.wd:    move.l  dosbase,a6
        moveq   #25,d1
        jsr     -198(a6)                ; Delay(25)
        subq.w  #1,d7
        bne.s   .wl
.we:
        lea     req2,a1                 ; --- TD_REMCHANGEINT on the same request
        move.w  #21,IO_COMMAND(a1)
        move.l  4.w,a6
        jsr     -456(a6)                ; DoIO
        lea     m_remci(pc),a0
        bsr     puts
        lea     req2,a1
        move.b  IO_ERROR(a1),d0
        bsr     hex2
        lea     req2,a1
        jsr     -468(a6)                ; CheckIO
        bsr     hex8
        bsr     nl
        lea     req1,a1                 ; TD_REMOVE NULL
        clr.l   IO_DATA(a1)
        moveq   #12,d0
        bsr     doio
        lea     m_chgint(pc),a0
        bsr     puts
        move.l  chgcnt,d0
        bsr     hex8
        move.l  remcnt,d0
        bsr     hex8
        bsr     nl
        lea     req1,a1
        move.l  4.w,a6
        jsr     -450(a6)                ; CloseDevice
out:    lea     m_end(pc),a0
        bsr     puts
        moveq   #0,d0
        rts

; doio(d0.w = command) on req1 -> d0 = io_Error. Clobbers d0/d1/a0/a1, a6 = SysBase.
doio:   lea     req1,a1
        move.w  d0,IO_COMMAND(a1)
        move.l  4.w,a6
        jsr     -456(a6)
        lea     req1,a1
        move.b  IO_ERROR(a1),d0
        rts
; rawread(d0 = track, d1 = io_Flags): TD_RAWREAD of RAWLEN bytes into rawbuf, io_Actual preset to $CAFEF00D.
; BeginIO + WaitIO, as DoIO would overwrite io_Flags (IOTDF_INDEXSYNC).
rawread:
        lea     req1,a1
        move.l  d0,IO_OFFSET(a1)
        or.b    #1,d1                   ; IOF_QUICK
        move.b  d1,IO_FLAGS(a1)
        move.l  rawbuf,IO_DATA(a1)
        move.l  #RAWLEN,IO_LENGTH(a1)
        move.l  #$CAFEF00D,IO_ACTUAL(a1)
        move.w  #16,IO_COMMAND(a1)
        move.b  #5,8(a1)                ; NT_MESSAGE
        move.l  20(a1),a6               ; io_Device
        jsr     -30(a6)                 ; BeginIO
        lea     req1,a1
        move.l  4.w,a6
        jmp     -474(a6)                ; WaitIO (returns at once if IOF_QUICK stayed set)
; readw: CMD_READ of track WTRK into secbuf.
readw:  lea     req1,a1
        move.l  secbuf,IO_DATA(a1)
        move.l  #5632,IO_LENGTH(a1)
        move.l  #WTRK*5632,IO_OFFSET(a1)
        moveq   #2,d0
        bra     doio
; mkint(a0 = struct Interrupt, a1 = counter): software interrupt that increments the counter.
mkint:  move.b  #2,8(a0)                ; NT_INTERRUPT
        clr.b   9(a0)
        clr.l   10(a0)
        move.l  a1,14(a0)
        move.l  #intcode,18(a0)
        clr.l   (a1)
        rts
intcode:
        addq.l  #1,(a1)
        moveq   #0,d0
        rts
; hasw -> Z = 0 if the argument line contains "W".
hasw:   movem.l d0/a0,-(sp)
        move.l  argp,a0
        move.l  argl,d0
        bra.s   .hl
.hc:    cmp.b   #'W',(a0)+
        beq.s   .hy
.hl:    dbra    d0,.hc
        moveq   #0,d0
        bra.s   .hr
.hy:    moveq   #1,d0
.hr:    movem.l (sp)+,d0/a0             ; (movem does not touch the CCR)
        rts

; get32(d0 = bit position in rawbuf) -> d0 = the 32 bits from there. Clobbers d1.
get32:  movem.l d2-d3/a0,-(sp)
        move.l  rawbuf,a0
        move.l  d0,d1
        lsr.l   #4,d1
        add.l   d1,d1
        add.l   d1,a0                   ; word holding the first bit
        and.w   #15,d0
        move.l  (a0),d2
        moveq   #0,d3
        move.w  4(a0),d3
        lsl.l   d0,d2
        moveq   #16,d1
        sub.w   d0,d1
        lsr.l   d1,d3
        or.l    d3,d2
        move.l  d2,d0
        movem.l (sp)+,d2-d3/a0
        rts
; findsync(d0 = first bit position) -> d0 = bit position of the first $4489 at any bit phase, -1 if none.
findsync:
        movem.l d2/d6,-(sp)
        move.l  d0,d6
        move.l  #(RAWWORDS-3)*16,d2
.fs:    cmp.l   d2,d6
        bhs.s   .fn
        move.l  d6,d0
        bsr.s   get32
        swap    d0
        cmp.w   #$4489,d0
        beq.s   .ff
        addq.l  #1,d6
        bra.s   .fs
.fn:    moveq   #-1,d6
.ff:    move.l  d6,d0
        movem.l (sp)+,d2/d6
        rts

; encode(a0 = buffer, d0 = track): AmigaDOS MFM track (guard, 11 sectors, tail word); data long k of sector n =
; $5A000000 | n << 16 | k. Data bits first, then one pass sets the clock bits everywhere but in the sync words.
encode: movem.l d2-d7/a2-a4,-(sp)
        move.l  a0,a3                   ; a3 = start
        move.l  a0,a2
        move.l  d0,d7                   ; d7 = track
        move.l  #MASK,d6
        move.w  #GAPL-1,d1
.eg:    clr.l   (a2)+
        dbra    d1,.eg
        moveq   #0,d5                   ; d5 = sector
.es:    move.l  a2,a4                   ; a4 = sector start
        clr.l   (a2)+                   ; preamble (encoded zeros)
        move.l  #$44894489,(a2)+
        moveq   #0,d0                   ; info = $FF, track, sector, sectors to the gap
        move.b  #$FF,d0
        lsl.w   #8,d0
        move.b  d7,d0
        lsl.l   #8,d0
        move.b  d5,d0
        lsl.l   #8,d0
        moveq   #11,d1
        sub.b   d5,d1
        move.b  d1,d0
        bsr     .oe
        moveq   #7,d1                   ; label
.el:    clr.l   (a2)+
        dbra    d1,.el
        lea     8(a4),a0                ; header checksum over info + label
        moveq   #0,d0
        moveq   #9,d1
.eh:    move.l  (a0)+,d2
        eor.l   d2,d0
        dbra    d1,.eh
        and.l   d6,d0
        bsr     .oe
        lea     64(a4),a0               ; data: odd half, even half
        lea     576(a4),a1
        moveq   #0,d4
        moveq   #0,d3                   ; d3 = k
.ed:    move.l  d5,d0
        swap    d0
        or.l    #$5A000000,d0
        or.w    d3,d0
        move.l  d0,d2
        lsr.l   #1,d2
        and.l   d6,d2
        move.l  d2,(a0)+
        eor.l   d2,d4
        and.l   d6,d0
        move.l  d0,(a1)+
        eor.l   d0,d4
        addq.w  #1,d3
        cmp.w   #128,d3
        bne.s   .ed
        move.l  d4,d0                   ; data checksum
        bsr     .oe
        lea     SECL*4(a4),a2
        addq.w  #1,d5
        cmp.w   #11,d5
        bne     .es
        move.l  a3,a0                   ; clock pass
        moveq   #0,d3                   ; d3 = previous long
        move.w  #GAPL+1,d4              ; longs before the next sync long
        move.w  #TRKL-1,d5
.ec:    tst.w   d4
        bne.s   .ecl
        move.l  (a0)+,d3                ; sync long kept as is
        move.w  #SECL-1,d4
        bra.s   .ecn
.ecl:   move.l  (a0),d0
        and.l   d6,d0
        move.l  d0,d1
        add.l   d1,d1                   ; next data bit into the clock position
        move.l  d0,d2
        lsr.l   #1,d2                   ; previous data bit into the clock position
        or.l    d2,d1
        and.l   #1,d3
        ror.l   #1,d3                   ; bit 0 of the previous long before bit 31
        or.l    d3,d1
        not.l   d1
        and.l   #$AAAAAAAA,d1
        or.l    d1,d0
        move.l  d0,(a0)+
        move.l  d0,d3
        subq.w  #1,d4
.ecn:   dbra    d5,.ec
        move.w  #$AAA8,(a0)             ; tail word
        movem.l (sp)+,d2-d7/a2-a4
        rts
.oe:    move.l  d0,d2                   ; d0 -> (a2)+: odd bits, then even bits
        lsr.l   #1,d2
        and.l   d6,d2
        move.l  d2,(a2)+
        and.l   d6,d0
        move.l  d0,(a2)+
        rts

; output: perr = io_Error of req1 (2 digits), pact = io_Actual of req1, dig(d0 = 0/1), hex8, hex2, puts, nl
perr:   lea     req1,a1
        move.b  IO_ERROR(a1),d0
        bra.s   hex2
pact:   lea     req1,a1
        move.l  IO_ACTUAL(a1),d0
        bra.s   hex8
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
; hex8(d0.l) / hex2(d0.b): hex digits and a space. Preserve d0.
hex8:   movem.l d0-d1/a0,-(sp)
        moveq   #7,d1
        bra.s   hexn
hex2:   movem.l d0-d1/a0,-(sp)
        ror.l   #8,d0
        moveq   #1,d1
hexn:   lea     hbuf,a0
.dg:    rol.l   #4,d0
        move.l  d0,-(sp)
        and.w   #15,d0
        move.b  hexd(pc,d0.w),(a0)+
        move.l  (sp)+,d0
        dbra    d1,.dg
        move.b  #' ',(a0)+
        clr.b   (a0)
        lea     hbuf,a0
        bsr.s   puts
        movem.l (sp)+,d0-d1/a0
        rts
hexd:   dc.b    "0123456789ABCDEF"

nocmds: dc.b    1,6,7,8,0
        even
seekoffs: dc.l  5632*10,100,901120,0
dosname: dc.b   "dos.library",0
tdname: dc.b    "trackdisk.device",0
m_open: dc.b    13,10,"OPEN ",0
m_chgnum: dc.b  "CHGNUM ",0
m_dtype: dc.b   "DTYPE ",0
m_ntrk: dc.b    "NTRK ",0
m_nocmd: dc.b   "NOCMD ",0
m_seek: dc.b    "SEEK ",0
m_rawbad: dc.b  "RAWBAD ",0
m_raw10: dc.b   "RAW10 ",0
m_idx:  dc.b    "IDX ",0
m_noidx: dc.b   "NOIDX ",0
m_raww: dc.b    "RAWW ",0
m_remove: dc.b  "REMOVE ",0
m_addci: dc.b   " ADDCI ",0
m_chg:  dc.b    "CHG ",0
m_remci: dc.b   "REMCI ",0
m_chgint: dc.b  "CHGINT ",0
m_nl:   dc.b    13,10,0
m_end:  dc.b    "TDRAW END GAP fin",13,10,0
        even

        section bss,bss
argl:   ds.l    1
argp:   ds.l    1
dosbase: ds.l   1
rawbuf: ds.l    1
secbuf: ds.l    1
remcnt: ds.l    1
chgcnt: ds.l    1
port:   ds.b    34
        ds.w    0
req1:   ds.b    TDSIZE
req2:   ds.b    TDSIZE
remint: ds.b    22
chgint: ds.b    22
hbuf:   ds.b    12
