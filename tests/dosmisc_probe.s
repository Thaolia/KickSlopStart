; tests/dosmisc_probe.s - dos behaviours still open after the probes of 2026-11-10 (implementation track, authored
; from the descriptions of docs/analysis/dos-lvo-partial-v34.md §4 items 2, 3, 7 and dos-memory-v34.md §8 P1, P3).
; Run as a CLI command; the argument picks the part. Prints on the serial line, one line per result, values in hex,
; each line printed under Forbid so that concurrent instances (started with Run) do not mix their characters:
;   argument "1".."4": Delay(50), Delay(-50), Delay(-49), Delay(-1)
;     "DM DLn start" then "DM DLn <ticks elapsed by DateStamp>" when Delay returns
;   argument "S":
;     "DM SKO <d0> <IoErr>"         Seek(Output(), 0, OFFSET_CURRENT) (the CLI's console)
;     "DM SKR <d0> <IoErr>"         Seek on a RAW: window handle (0, OFFSET_BEGINNING)
;     "DM SKN <d0> <IoErr>"         Seek on a NEWCON: window handle (0, OFFSET_BEGINNING)
;     "DM SKF <Read d0> <Seek d0> <second Seek d0> <IoErr>"   s/startup-sequence: Read 10 bytes, then
;                                   Seek(0, OFFSET_CURRENT) twice (the old position each time)
;     "DM INF <Info d0> <12 longs from the aligned buffer start>"   Info(lock on DF0:, buffer + 2) on a 48-byte
;                                   buffer filled with $5A
;     "DM UL0 <long 0 before> <long 4 before == ExecBase> <UnLoadSeg(0) d0> <long 0 after> <long 4 after == ExecBase>"
;     "DM LSM <LoadSeg d0> <IoErr> <AvailMem drop>"   LoadSeg("df0:nonexistent")
;     "DM ATT <LoadSeg d0> <IoErr> <TypeOfMem of the hunk or 0>"   LoadSeg("df0:attr"): a header whose hunk size has
;                                   bits 31-30 = 11 followed by an attribute long MEMF_CHIP (2.0 hunk format)
;     "DM END"
; Run by tests/dosmisc_probe.sh.

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018

LVO_Forbid       EQU -132           ; exec LVOs checked against AROS rom/exec/exec.conf
LVO_Permit       EQU -138
LVO_AvailMem     EQU -216
LVO_TypeOfMem    EQU -534
LVO_CloseLibrary EQU -414
LVO_OpenLibrary  EQU -552
LVO_Open         EQU -30            ; dos LVOs checked against AROS rom/dos/dos.conf
LVO_Close        EQU -36
LVO_Read         EQU -42
LVO_Output       EQU -60
LVO_Seek         EQU -66
LVO_Lock         EQU -84
LVO_UnLock       EQU -90
LVO_Info         EQU -114
LVO_IoErr        EQU -132
LVO_LoadSeg      EQU -150
LVO_UnLoadSeg    EQU -156
LVO_DateStamp    EQU -192
LVO_Delay        EQU -198
MODE_OLDFILE     EQU 1005
MODE_NEWFILE     EQU 1006
ACCESS_READ      EQU -2

                section code,code
start:
        movem.l d2-d7/a2-a6,-(sp)
        move.b  (a0),d7              ; d7 = argument letter
        move.l  4.w,a6
        lea     dosname(pc),a1
        moveq   #0,d0
        jsr     LVO_OpenLibrary(a6)
        tst.l   d0
        beq     p_ret
        move.l  d0,a5                ; a5 = DOSBase
        cmp.b   #'S',d7
        beq     seekpart
        move.b  d7,d0
        sub.b   #'1',d0
        cmp.b   #3,d0
        bhi     p_close
        ext.w   d0
        add.w   d0,d0
        add.w   d0,d0
        lea     dlvals(pc),a0
        move.l  (a0,d0.w),d6         ; d6 = Delay argument
        lea     dltag+5(pc),a0
        move.b  d7,(a0)
        bsr     lnbeg
        lea     dltag(pc),a0
        bsr     puts
        lea     m_start(pc),a0
        bsr     puts
        bsr     lnend
        bsr     ticks
        move.l  d0,d5
        move.l  d6,d1
        exg     a5,a6
        jsr     LVO_Delay(a6)
        exg     a5,a6
        bsr     ticks
        sub.l   d5,d0
        move.l  d0,d5
        bsr     lnbeg
        lea     dltag(pc),a0
        bsr     puts
        move.l  d5,d0
        bsr     phex8
        bsr     lnend
        bra     p_close
dlvals: dc.l    50,-50,-49,-1

seekpart:
        exg     a5,a6                ; a6 = DOSBase, a5 = ExecBase from here on
        jsr     LVO_Output(a6)
        move.l  d0,d1
        moveq   #0,d2
        moveq   #0,d3                ; OFFSET_CURRENT
        jsr     LVO_Seek(a6)
        lea     m_sko(pc),a0
        bsr     pres
        lea     n_raw(pc),a0
        lea     m_skr(pc),a1
        bsr     seekwin
        lea     n_newcon(pc),a0
        lea     m_skn(pc),a1
        bsr     seekwin
        lea     n_ss(pc),a0          ; disk file: one buffered read, then Seek(0, CURRENT) twice
        move.l  a0,d1
        move.l  #MODE_OLDFILE,d2
        jsr     LVO_Open(a6)
        move.l  d0,d4
        beq     .nofile
        move.l  d4,d1
        lea     buf(pc),a0
        move.l  a0,d2
        moveq   #10,d3
        jsr     LVO_Read(a6)
        move.l  d0,d5
        move.l  d4,d1
        moveq   #0,d2
        moveq   #0,d3
        jsr     LVO_Seek(a6)
        move.l  d0,d6
        move.l  d4,d1
        moveq   #0,d2
        moveq   #0,d3
        jsr     LVO_Seek(a6)
        move.l  d0,d7
        jsr     LVO_IoErr(a6)
        move.l  d0,-(sp)
        move.l  d4,d1
        jsr     LVO_Close(a6)
        bsr     lnbeg
        lea     m_skf(pc),a0
        bsr     puts
        move.l  d5,d0
        bsr     phex8
        move.l  d6,d0
        bsr     phex8
        move.l  d7,d0
        bsr     phex8
        move.l  (sp)+,d0
        bsr     phex8
        bsr     lnend
.nofile:
        lea     n_df0(pc),a0         ; Info(lock, buffer + 2)
        move.l  a0,d1
        moveq   #ACCESS_READ,d2
        jsr     LVO_Lock(a6)
        move.l  d0,d4
        lea     ibuf(pc),a2
        moveq   #12-1,d0
.fill:  move.l  #$5A5A5A5A,(a2)+
        dbra    d0,.fill
        move.l  d4,d1
        lea     ibuf+2(pc),a0
        move.l  a0,d2
        jsr     LVO_Info(a6)
        move.l  d0,d5
        move.l  d4,d1
        jsr     LVO_UnLock(a6)
        bsr     lnbeg
        lea     m_inf(pc),a0
        bsr     puts
        move.l  d5,d0
        bsr     phex8
        lea     ibuf(pc),a2
        moveq   #12-1,d4
.dump:  move.l  (a2)+,d0
        bsr     phex8
        dbra    d4,.dump
        bsr     lnend
        move.l  0.w,d4               ; P1: UnLoadSeg(0) and the longs at 0 and 4
        move.l  4.w,d5
        moveq   #0,d1
        jsr     LVO_UnLoadSeg(a6)
        move.l  d0,d6
        bsr     lnbeg
        lea     m_ul0(pc),a0
        bsr     puts
        move.l  d4,d0
        bsr     phex8
        moveq   #0,d0
        cmp.l   a5,d5
        seq     d0
        bsr     phex8
        move.l  d6,d0
        bsr     phex8
        move.l  0.w,d0
        bsr     phex8
        moveq   #0,d0
        cmp.l   4.w,a5
        seq     d0
        bsr     phex8
        bsr     lnend
        lea     n_none(pc),a0
        bsr     loadone
        move.l  d0,d4
        lea     m_lsm(pc),a0
        bsr     plsr
        tst.l   d4
        beq.s   .att
        move.l  d4,d1
        jsr     LVO_UnLoadSeg(a6)
.att:
        lea     n_attr(pc),a0
        bsr     loadone
        move.l  d0,d4
        moveq   #0,d5                ; TypeOfMem of the hunk, 0 when nothing was loaded
        tst.l   d4
        beq.s   .attp
        exg     a5,a6
        move.l  d4,d0
        lsl.l   #2,d0
        move.l  d0,a1
        addq.l  #4,a1
        jsr     LVO_TypeOfMem(a6)
        exg     a5,a6
        move.l  d0,d5
        move.l  d4,d1
        jsr     LVO_UnLoadSeg(a6)
.attp:
        lea     m_att(pc),a0
        bsr     plsr3
        bsr     lnbeg
        lea     m_end(pc),a0
        bsr     puts
        bsr     lnend
        exg     a5,a6
p_close:
        move.l  a5,a1
        jsr     LVO_CloseLibrary(a6)
p_ret:
        movem.l (sp)+,d2-d7/a2-a6
        moveq   #0,d0
        rts

; seekwin(a0 = window name, a1 = tag): Open MODE_NEWFILE, Seek(0, OFFSET_BEGINNING), close; prints "<tag> d0 IoErr"
seekwin:
        move.l  a1,-(sp)
        move.l  a0,d1
        move.l  #MODE_NEWFILE,d2
        jsr     LVO_Open(a6)
        move.l  d0,d4
        beq.s   .sw_no
        move.l  d4,d1
        moveq   #0,d2
        moveq   #-1,d3               ; OFFSET_BEGINNING
        jsr     LVO_Seek(a6)
        move.l  d0,d5
        jsr     LVO_IoErr(a6)
        move.l  d0,d6
        move.l  d4,d1
        jsr     LVO_Close(a6)
        move.l  d5,d0
        move.l  d6,d1
        move.l  (sp)+,a0
        bra.s   pres2
.sw_no:
        move.l  (sp)+,a0
        moveq   #-2,d0               ; Open failed
        moveq   #0,d1
        bra.s   pres2
; pres(a0 = tag, d0 = result): prints "<tag> d0 IoErr"
pres:
        move.l  d0,-(sp)
        move.l  a0,-(sp)
        jsr     LVO_IoErr(a6)
        move.l  d0,d1
        move.l  (sp)+,a0
        move.l  (sp)+,d0
pres2:
        movem.l d0/d1,-(sp)
        bsr     lnbeg
        bsr     puts
        move.l  (sp)+,d0
        bsr     phex8
        move.l  (sp)+,d0
        bsr     phex8
        bra     lnend

; loadone(a0 = name) -> d0 = LoadSeg result; d6 = IoErr, d7 = AvailMem drop
loadone:
        move.l  a0,-(sp)
        exg     a5,a6
        moveq   #0,d1
        jsr     LVO_AvailMem(a6)
        exg     a5,a6
        move.l  d0,d7
        move.l  (sp)+,d1
        jsr     LVO_LoadSeg(a6)
        move.l  d0,-(sp)
        jsr     LVO_IoErr(a6)
        move.l  d0,d6
        exg     a5,a6
        moveq   #0,d1
        jsr     LVO_AvailMem(a6)
        exg     a5,a6
        sub.l   d0,d7
        move.l  (sp)+,d0
        rts
; plsr(a0 = tag, d4 = LoadSeg d0, d6 = IoErr, d7 = drop): "<tag> d0 IoErr drop"
plsr:
        move.l  d7,d5
; plsr3(a0 = tag, d4, d6 = IoErr, d5 = third value)
plsr3:
        bsr     lnbeg
        bsr     puts
        move.l  d4,d0
        bsr     phex8
        move.l  d6,d0
        bsr     phex8
        move.l  d5,d0
        bsr     phex8
        bra     lnend

; ticks -> d0 = DateStamp as ticks since day 0 (minutes * 3000 + ticks, days ignored: runs are short)
ticks:
        movem.l d1-d3/a0-a1/a6,-(sp)
        move.l  a5,a6
        lea     dstamp(pc),a0
        move.l  a0,d1
        jsr     LVO_DateStamp(a6)
        move.l  dstamp+4(pc),d0
        mulu    #3000,d0
        add.l   dstamp+8(pc),d0
        movem.l (sp)+,d1-d3/a0-a1/a6
        rts

; lnbeg / lnend: a line under Forbid (ExecBase from 4)
lnbeg:
        movem.l d0-d1/a0-a1/a6,-(sp)
        move.l  4.w,a6
        jsr     LVO_Forbid(a6)
        movem.l (sp)+,d0-d1/a0-a1/a6
        rts
lnend:
        movem.l d0-d1/a0-a1/a6,-(sp)
        moveq   #10,d1
        bsr.s   putc
        move.l  4.w,a6
        jsr     LVO_Permit(a6)
        movem.l (sp)+,d0-d1/a0-a1/a6
        rts

puts:
        move.l  d1,-(sp)
.p:     move.b  (a0)+,d1
        beq.s   .r
        bsr.s   putc
        bra.s   .p
.r:     move.l  (sp)+,d1
        rts
; phex8(d0.l): " XXXXXXXX"
phex8:
        movem.l d0-d2,-(sp)
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
        movem.l (sp)+,d0-d2
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

                cnop    0,4
dstamp:   ds.l  3
ibuf:     ds.l  12
buf:      ds.l  4
dosname:  dc.b  "dos.library",0
n_raw:    dc.b  "RAW:0/0/320/50/dmraw",0
n_newcon: dc.b  "NEWCON:0/60/320/50/dmnewcon",0
n_ss:     dc.b  "df0:s/startup-sequence",0
n_df0:    dc.b  "df0:",0
n_none:   dc.b  "df0:nonexistent",0
n_attr:   dc.b  "df0:attr",0
dltag:    dc.b  "DM DLx",0
m_start:  dc.b  " start",0
m_sko:    dc.b  "DM SKO",0
m_skr:    dc.b  "DM SKR",0
m_skn:    dc.b  "DM SKN",0
m_skf:    dc.b  "DM SKF",0
m_inf:    dc.b  "DM INF",0
m_ul0:    dc.b  "DM UL0",0
m_lsm:    dc.b  "DM LSM",0
m_att:    dc.b  "DM ATT",0
m_end:    dc.b  "DM END",0
                even
