; tests/fslock_test.s - DF0: file system locks and the packets SET_DATE, RENAME_DISK, FLUSH (implementation-side test
; of docs/analysis/rom-filesystem-v34.md §3, §5.1, §6.1, §6.4, §6.5, §7.4). Run by tests/fslock_probe.sh from the
; startup-sequence of a scratch OFS disk named "Probe" in DF0:. One line per check on the serial port,
; "FSLK nnnnnnnn OK" or "FSLK nnnnnnnn FAIL <got> <expected>", then "FSLK END <failures>". The disk is left
; relabelled "Renamed", with f1 (comment of 80 characters, date 1000/600/50) and d2 (a file that replaced an empty
; directory).
; Build: vasmm68k_mot -Fhunkexe -kick1hunks -o build/fslock_test tests/fslock_test.s

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018
MODE_RW  EQU 1004
MODE_OLD EQU 1005
MODE_NEW EQU 1006
SHARED   EQU -2
EXCL     EQU -1
PR_MSGPORT EQU $5C

_Open    EQU -30
_Close   EQU -36
_DeleteFile EQU -72
_Lock    EQU -84
_UnLock  EQU -90
_DupLock EQU -96
_Examine EQU -102
_Info    EQU -114
_CreateDir EQU -120
_IoErr   EQU -132
_DeviceProc EQU -174
_SetComment EQU -180
_SetProtection EQU -186

FIB_DIRENTRYTYPE EQU 4
FIB_COMMENT      EQU 144
FIB_DATE         EQU 132
ID_VOLUMENODE    EQU 28
DN_NAME          EQU 40

start:  move.l  4.w,a6
        lea     dosname(pc),a1
        moveq   #0,d0
        jsr     -552(a6)
        tst.l   d0
        beq     quit
        move.l  d0,a6                   ; a6 = DosBase

; --- a file open for writing holds an exclusive lock ----------------------------------------------------------------
        move.l  #n_f1,d1
        move.l  #MODE_NEW,d2
        jsr     _Open(a6)
        move.l  d0,d7                   ; d7 = file open for writing
        move.l  #n_f1,d1
        moveq   #SHARED,d2
        jsr     _Lock(a6)
        moveq   #0,d1
        bsr     check                   ; 1: Lock while open for output
        bsr     ioerr202                ; 2
        move.l  #n_f1,d1
        move.l  #MODE_OLD,d2
        jsr     _Open(a6)
        moveq   #0,d1
        bsr     check                   ; 3: Type >x x
        bsr     ioerr202                ; 4
        move.l  #n_f1,d1
        jsr     _DeleteFile(a6)
        moveq   #0,d1
        bsr     check                   ; 5: Delete >x x
        bsr     ioerr202                ; 6
        move.l  d7,d1
        jsr     _Close(a6)

; --- shared and exclusive locks -------------------------------------------------------------------------------------
        moveq   #SHARED,d2
        bsr     lockf1
        move.l  d0,d4                   ; d4 = shared lock 1
        sne     d0
        ext.w   d0
        ext.l   d0
        moveq   #-1,d1
        bsr     check                   ; 7: granted
        moveq   #SHARED,d2
        bsr     lockf1
        move.l  d0,d5                   ; d5 = shared lock 2
        sne     d0
        ext.w   d0
        ext.l   d0
        moveq   #-1,d1
        bsr     check                   ; 8: two shared locks
        moveq   #EXCL,d2
        bsr     lockf1
        moveq   #0,d1
        bsr     check                   ; 9: exclusive refused
        bsr     ioerr202                ; 10
        move.l  #n_f1,d1
        move.l  #MODE_RW,d2
        jsr     _Open(a6)
        moveq   #0,d1
        bsr     check                   ; 11: MODE_READWRITE needs exclusive access
        bsr     ioerr202                ; 12
        move.l  #n_f1,d1
        move.l  #MODE_NEW,d2
        jsr     _Open(a6)
        moveq   #0,d1
        bsr     check                   ; 13: replacing a locked file
        bsr     ioerr202                ; 14
        move.l  #n_f1,d1
        moveq   #0,d2
        jsr     _SetProtection(a6)
        moveq   #0,d1
        bsr     check                   ; 15
        bsr     ioerr202                ; 16
        move.l  #n_f1,d1
        move.l  #MODE_OLD,d2
        jsr     _Open(a6)
        move.l  d0,d7
        sne     d0
        ext.w   d0
        ext.l   d0
        moveq   #-1,d1
        bsr     check                   ; 17: reading beside shared locks
        move.l  d7,d1
        jsr     _Close(a6)
        move.l  d4,d1
        jsr     _UnLock(a6)
        move.l  d5,d1
        jsr     _UnLock(a6)
        moveq   #EXCL,d2
        bsr     lockf1
        move.l  d0,d4                   ; d4 = exclusive lock
        sne     d0
        ext.w   d0
        ext.l   d0
        moveq   #-1,d1
        bsr     check                   ; 18: exclusive once the others are gone
        moveq   #SHARED,d2
        bsr     lockf1
        moveq   #0,d1
        bsr     check                   ; 19: shared under an exclusive one
        bsr     ioerr202                ; 20
        move.l  d4,d1
        jsr     _DupLock(a6)
        moveq   #0,d1
        bsr     check                   ; 21: the copy of an exclusive lock conflicts
        bsr     ioerr202                ; 22
        move.l  d4,d1
        jsr     _UnLock(a6)

; --- delete bit, directories ----------------------------------------------------------------------------------------
        move.l  #n_f1,d1
        moveq   #1,d2                   ; d set: protected from deletion
        jsr     _SetProtection(a6)
        moveq   #-1,d1
        bsr     check                   ; 23
        move.l  #n_f1,d1
        jsr     _DeleteFile(a6)
        moveq   #0,d1
        bsr     check                   ; 24
        jsr     _IoErr(a6)
        move.l  #222,d1
        bsr     check                   ; 25
        move.l  #n_f1,d1
        move.l  #MODE_NEW,d2
        jsr     _Open(a6)
        moveq   #0,d1
        bsr     check                   ; 26: FINDOUTPUT applies the delete rules
        jsr     _IoErr(a6)
        move.l  #222,d1
        bsr     check                   ; 27
        move.l  #n_f1,d1
        moveq   #0,d2
        jsr     _SetProtection(a6)
        moveq   #-1,d1
        bsr     check                   ; 28
        move.l  #n_d1,d1
        jsr     _CreateDir(a6)
        move.l  d0,d4                   ; lock on the new directory
        sne     d0
        ext.w   d0
        ext.l   d0
        moveq   #-1,d1
        bsr     check                   ; 29
        move.l  #n_d1,d1
        jsr     _DeleteFile(a6)
        moveq   #0,d1
        bsr     check                   ; 30: directory locked (CD e, Delete e)
        bsr     ioerr202                ; 31
        move.l  d4,d1
        jsr     _UnLock(a6)
        move.l  #n_d1x,d1
        move.l  #MODE_NEW,d2
        jsr     _Open(a6)
        move.l  d0,d1
        jsr     _Close(a6)
        move.l  #n_d1,d1
        jsr     _DeleteFile(a6)
        moveq   #0,d1
        bsr     check                   ; 32
        jsr     _IoErr(a6)
        move.l  #216,d1
        bsr     check                   ; 33: not empty
        move.l  #n_d1x,d1
        jsr     _DeleteFile(a6)
        move.l  #n_d1,d1
        jsr     _DeleteFile(a6)
        moveq   #-1,d1
        bsr     check                   ; 34
        move.l  #n_d2,d1
        jsr     _CreateDir(a6)
        move.l  d0,d1
        jsr     _UnLock(a6)
        move.l  #n_d2,d1
        move.l  #MODE_NEW,d2
        jsr     _Open(a6)
        move.l  d0,d7
        sne     d0
        ext.w   d0
        ext.l   d0
        moveq   #-1,d1
        bsr     check                   ; 35: an empty directory replaced by a file
        move.l  d7,d1
        jsr     _Close(a6)
        move.l  #n_d2,d1
        bsr     examine
        move.l  fib+FIB_DIRENTRYTYPE,d0
        smi     d0
        ext.w   d0
        ext.l   d0
        moveq   #-1,d1
        bsr     check                   ; 36: d2 is a file now

; --- comment, SET_DATE --------------------------------------------------------------------------------------------
        move.l  #n_f1,d1
        move.l  #c80,d2
        jsr     _SetComment(a6)
        moveq   #-1,d1
        bsr     check                   ; 37: 80 characters
        move.l  #n_f1,d1
        move.l  #c81,d2
        jsr     _SetComment(a6)
        moveq   #0,d1
        bsr     check                   ; 38: 81 characters
        jsr     _IoErr(a6)
        move.l  #220,d1
        bsr     check                   ; 39
        bsr     handler
        move.l  #b_f1,d0
        lsr.l   #2,d0
        move.l  d0,arg3
        move.l  #stamp,arg4
        clr.l   arg2                    ; lock 0: the root
        moveq   #34,d0                  ; ACTION_SET_DATE
        bsr     rawpkt
        moveq   #-1,d1
        bsr     check                   ; 40
        move.l  #n_f1,d1
        bsr     examine
        lea     fib+FIB_COMMENT,a0      ; dos gives a C string; ofs_fib_fill bounds it to 79 characters so that it
        moveq   #-1,d0                  ; fits the 80-byte field (the header keeps 80: checked on the disk image)
.cl:    addq.l  #1,d0
        tst.b   (a0)+
        bne.s   .cl
        moveq   #79,d1
        bsr     check                   ; 41
        move.l  fib+FIB_DATE,d0
        move.l  #1000,d1
        bsr     check                   ; 42
        move.l  fib+FIB_DATE+4,d0
        move.l  #600,d1
        bsr     check                   ; 43
        move.l  fib+FIB_DATE+8,d0
        moveq   #50,d1
        bsr     check                   ; 44

; --- FLUSH, FREE_LOCK of a foreign lock, RENAME_DISK ------------------------------------------------------------
        moveq   #27,d0                  ; ACTION_FLUSH: Res1/Res2 left as sent
        bsr     rawpkt
        move.l  #$11111111,d1
        bsr     check                   ; 45
        move.l  pkt+20+16,d0
        move.l  #$22222222,d1
        bsr     check                   ; 46
        move.l  #fakelock,d0
        lsr.l   #2,d0
        move.l  d0,arg1
        moveq   #15,d0                  ; ACTION_FREE_LOCK of a lock that is not the file system's
        bsr     rawpkt
        moveq   #0,d1
        bsr     check                   ; 47
        move.l  pkt+20+16,d0
        move.l  #211,d1
        bsr     check                   ; 48
        move.l  #b_new,d0
        lsr.l   #2,d0
        move.l  d0,arg1
        moveq   #9,d0                   ; ACTION_RENAME_DISK
        bsr     rawpkt
        moveq   #-1,d1
        bsr     check                   ; 49
        move.l  #n_newvol,d1
        moveq   #SHARED,d2
        jsr     _Lock(a6)
        move.l  d0,d4
        sne     d0
        ext.w   d0
        ext.l   d0
        moveq   #-1,d1
        bsr     check                   ; 50: the volume node answers to its new name
        move.l  d4,d1
        move.l  #info,d2
        jsr     _Info(a6)
        move.l  info+ID_VOLUMENODE,d0
        lsl.l   #2,d0
        move.l  d0,a0
        move.l  DN_NAME(a0),d0
        lsl.l   #2,d0
        move.l  d0,a0
        move.l  (a0),d0                 ; length + "Ren"
        move.l  #$0752656E,d1
        bsr     check                   ; 51
        move.l  d4,d1
        jsr     _UnLock(a6)

        lea     m_end(pc),a0
        bsr     puts
        move.l  nfail,d0
        bsr     hex8
        lea     m_nl(pc),a0
        bsr     puts
        move.l  a6,a1
        move.l  4.w,a6
        jsr     -414(a6)
quit:   moveq   #0,d0
        rts

lockf1: move.l  #n_f1,d1
        jmp     _Lock(a6)
ioerr202:
        jsr     _IoErr(a6)
        move.l  #202,d1
        bra     check
; examine(d1 = name): Lock + Examine into fib + UnLock.
examine:
        moveq   #SHARED,d2
        jsr     _Lock(a6)
        move.l  d0,-(sp)
        move.l  d0,d1
        move.l  #fib,d2
        jsr     _Examine(a6)
        move.l  (sp)+,d1
        jmp     _UnLock(a6)
; handler: hport = DeviceProc("df0:").
handler:
        move.l  #n_df0,d1
        jsr     _DeviceProc(a6)
        move.l  d0,hport
        rts
; rawpkt(d0 = type; arg1..arg4 in memory) -> d0 = Res1. Res1/Res2 preset to $11111111/$22222222.
rawpkt: movem.l d2/a2-a3/a6,-(sp)
        lea     pkt,a0
        lea     20(a0),a1
        move.l  a1,10(a0)               ; ln_Name = DosPacket
        move.l  a0,(a1)                 ; dp_Link = Message
        move.l  4.w,a6
        move.l  276(a6),a2              ; ThisTask
        lea     PR_MSGPORT(a2),a3
        move.l  a3,4(a1)                ; dp_Port
        move.l  d0,8(a1)
        move.l  #$11111111,12(a1)
        move.l  #$22222222,16(a1)
        move.l  arg1,20(a1)
        move.l  arg2,24(a1)
        move.l  arg3,28(a1)
        move.l  arg4,32(a1)
        move.l  hport,a0
        lea     pkt,a1
        jsr     -366(a6)                ; PutMsg
        move.l  a3,a0
        jsr     -384(a6)                ; WaitPort
        move.l  a3,a0
        jsr     -372(a6)                ; GetMsg
        move.l  pkt+20+12,d0
        movem.l (sp)+,d2/a2-a3/a6
        rts

; check(d0 = got, d1 = expected): one result line for the next test number. Clobbers d0/d1/a0.
check:  movem.l d0-d1,-(sp)
        addq.l  #1,tno
        lea     m_fslk(pc),a0
        bsr.s   puts
        move.l  tno,d0
        bsr.s   hex8
        movem.l (sp)+,d0-d1
        cmp.l   d0,d1
        bne.s   .ck_bad
        lea     m_ok(pc),a0
        bra.s   puts
.ck_bad:
        addq.l  #1,nfail
        move.l  d1,-(sp)
        lea     m_fail(pc),a0
        bsr.s   puts
        bsr.s   hex8
        move.l  (sp)+,d0
        bsr.s   hex8
        lea     m_nl(pc),a0
puts:   move.b  (a0)+,d1
        beq.s   .pe
.pw:    btst    #5,SERDATR
        beq.s   .pw
        and.w   #$FF,d1
        or.w    #$100,d1
        move.w  d1,SERDAT
        bra.s   puts
.pe:    rts
hex8:   movem.l d0/d2/a0,-(sp)
        moveq   #7,d2
.hx:    rol.l   #4,d0
        move.l  d0,-(sp)
        and.w   #15,d0
        lea     hbuf(pc),a0
        move.b  hexd(pc,d0.w),(a0)
        bsr.s   puts
        move.l  (sp)+,d0
        dbra    d2,.hx
        lea     m_sp(pc),a0
        bsr.s   puts
        movem.l (sp)+,d0/d2/a0
        rts
hexd:   dc.b    "0123456789ABCDEF"
hbuf:   dc.b    0,0

dosname: dc.b   "dos.library",0
m_fslk: dc.b    "FSLK ",0
m_ok:   dc.b    "OK",13,10,0
m_fail: dc.b    "FAIL ",0
m_end:  dc.b    "FSLK END ",0
m_nl:   dc.b    13,10,0
m_sp:   dc.b    " ",0
        even

        section fsdata,data
n_f1:   dc.b    "df0:f1",0
n_d1:   dc.b    "df0:d1",0
n_d1x:  dc.b    "df0:d1/x",0
n_d2:   dc.b    "df0:d2",0
n_df0:  dc.b    "df0:",0
n_newvol: dc.b  "Renamed:",0
c80:    dcb.b   80,'c'
        dc.b    0
c81:    dcb.b   81,'c'
        dc.b    0
        cnop    0,4
b_f1:   dc.b    2,"f1"
        cnop    0,4
b_new:  dc.b    7,"Renamed"
        cnop    0,4
stamp:  dc.l    1000,600,50
tno:    dc.l    0
nfail:  dc.l    0
arg1:   dc.l    0
arg2:   dc.l    0
arg3:   dc.l    0
arg4:   dc.l    0
hport:  dc.l    0

        section fsbss,bss
pkt:    ds.l    17
fib:    ds.l    65
info:   ds.l    9
fakelock: ds.l  7
