; tests/fsgap_test.s - DF0:/DF1: file system details (implementation-side test of docs/analysis/rom-filesystem-v34.md
; §2.2, §2.3, §4.1, §4.2, §6.2, §6.3, §7.1): names truncated to 30 characters, 212 for a path through a file or a
; directory opened as a file, DELETE of the root 205 and SET_PROTECT of the root 212, fib_DirEntryType 2 for the root,
; ExNext in creation order inside a hash slot, a directory renamed into itself 202, and on a write-protected disk in
; DF1: 214 before the name is looked at and id_DiskState 80. Run by tests/fsgap_probe.sh (DF0: scratch disk running
; this program, DF1: write-protected disk "WProt" holding a file "wf"). One line per check on the serial port,
; "FSGP nnnnnnnn OK" or "FSGP nnnnnnnn FAIL <got> <expected>", then "FSGP END <failures>".
; Build: vasmm68k_mot -Fhunkexe -kick1hunks -o build/fsgap_test tests/fsgap_test.s

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018
MODE_OLD EQU 1005
MODE_NEW EQU 1006
SHARED   EQU -2
PR_MSGPORT EQU $5C

_Open    EQU -30
_Close   EQU -36
_DeleteFile EQU -72
_Lock    EQU -84
_UnLock  EQU -90
_Examine EQU -102
_ExNext  EQU -108
_Info    EQU -114
_CreateDir EQU -120
_IoErr   EQU -132
_DeviceProc EQU -174
_SetProtection EQU -186

FIB_DIRENTRYTYPE EQU 4
FIB_FILENAME     EQU 8

start:  move.l  4.w,a6
        lea     dosname(pc),a1
        moveq   #0,d0
        jsr     -552(a6)
        tst.l   d0
        beq     quit
        move.l  d0,a6                   ; a6 = DosBase

; --- names longer than 30 characters ----------------------------------------------------------------------------
        move.l  #n_long36,d1
        move.l  #MODE_NEW,d2
        jsr     _Open(a6)
        move.l  d0,d1
        bsr     isset
        moveq   #-1,d1
        bsr     check                   ; 1: created
        move.l  d7,d1
        jsr     _Close(a6)
        move.l  #n_long30,d1
        bsr     lockok                  ; 2: its name is the first 30 characters
        move.l  #n_long36,d1
        bsr     lockok                  ; 3: the long name finds it too

; --- 212 ------------------------------------------------------------------------------------------------------
        move.l  #n_thru,d1
        moveq   #SHARED,d2
        jsr     _Lock(a6)
        bsr     fail212                 ; 4, 5: Lock through a file
        move.l  #n_thru,d1
        move.l  #MODE_OLD,d2
        jsr     _Open(a6)
        bsr     fail212                 ; 6, 7: FINDINPUT through a file
        move.l  #n_thru,d1
        move.l  #MODE_NEW,d2
        jsr     _Open(a6)
        bsr     fail212                 ; 8, 9: FINDOUTPUT through a file
        move.l  #n_thru,d1
        jsr     _DeleteFile(a6)
        bsr     fail212                 ; 10, 11: DELETE through a file
        move.l  #n_sdir,d1
        move.l  #MODE_OLD,d2
        jsr     _Open(a6)
        bsr     fail212                 ; 12, 13: a directory opened as a file

; --- the root -------------------------------------------------------------------------------------------------
        move.l  #n_df0,d1
        jsr     _DeleteFile(a6)
        moveq   #0,d1
        bsr     check                   ; 14
        jsr     _IoErr(a6)
        move.l  #205,d1
        bsr     check                   ; 15: DELETE of the root
        move.l  #n_df0,d1
        moveq   #0,d2
        jsr     _SetProtection(a6)
        bsr     fail212                 ; 16, 17: SET_PROTECT of the root
        move.l  #n_df0,d1
        bsr     examine
        move.l  fib+FIB_DIRENTRYTYPE,d0
        moveq   #2,d1
        bsr     check                   ; 18: the root reads as a directory, 2

; --- ExNext order inside a hash slot (fh, aa, eu: all slot 24) ----------------------------------------------------
        move.l  #n_ord,d1
        jsr     _CreateDir(a6)
        move.l  d0,d1
        jsr     _UnLock(a6)
        lea     n_ordfh,a0
        bsr     mkfile
        lea     n_ordaa,a0
        bsr     mkfile
        lea     n_ordeu,a0
        bsr     mkfile
        move.l  #n_ord,d1
        moveq   #SHARED,d2
        jsr     _Lock(a6)
        move.l  d0,d4
        move.l  d4,d1
        move.l  #fib,d2
        jsr     _Examine(a6)
        bsr     nextname
        move.l  #'fh'<<16,d1
        bsr     check                   ; 19: creation order
        bsr     nextname
        move.l  #'aa'<<16,d1
        bsr     check                   ; 20
        bsr     nextname
        move.l  #'eu'<<16,d1
        bsr     check                   ; 21
        move.l  d4,d1
        move.l  #fib,d2
        jsr     _ExNext(a6)
        moveq   #0,d1
        bsr     check                   ; 22
        jsr     _IoErr(a6)
        move.l  #232,d1
        bsr     check                   ; 23: end of the directory
        move.l  d4,d1
        jsr     _UnLock(a6)

; --- a directory renamed into itself -------------------------------------------------------------------------------
        move.l  #n_d3,d1
        jsr     _CreateDir(a6)
        move.l  d0,d4                   ; lock on d3
        bsr     handler0
        clr.l   arg1                    ; from: root, "d3"
        move.l  #b_d3,d0
        lsr.l   #2,d0
        move.l  d0,arg2
        move.l  d4,arg3                 ; to: d3 itself, "x"
        move.l  #b_x,d0
        lsr.l   #2,d0
        move.l  d0,arg4
        moveq   #17,d0                  ; ACTION_RENAME_OBJECT
        bsr     rawpkt
        moveq   #0,d1
        bsr     check                   ; 24
        move.l  pkt+20+16,d0
        move.l  #202,d1
        bsr     check                   ; 25
        move.l  d4,d1
        jsr     _UnLock(a6)
        move.l  #n_d3,d1
        bsr     lockok                  ; 26: d3 is back in the root

; --- write-protected disk in DF1: -------------------------------------------------------------------------------
        move.l  #n_wnew,d1
        jsr     _CreateDir(a6)
        bsr     fail214                 ; 27, 28: CREATE_DIR of a new name
        move.l  #n_wf,d1
        jsr     _DeleteFile(a6)
        bsr     fail214                 ; 29, 30: DELETE of an existing file
        move.l  #n_wnone,d1
        jsr     _DeleteFile(a6)
        bsr     fail214                 ; 31, 32: DELETE of a missing name (214 comes first)
        move.l  #n_wf,d1
        moveq   #0,d2
        jsr     _SetProtection(a6)
        bsr     fail214                 ; 33, 34
        move.l  #n_df1,d1
        moveq   #SHARED,d2
        jsr     _Lock(a6)
        move.l  d0,d4
        move.l  d4,d1
        move.l  #info,d2
        jsr     _Info(a6)
        move.l  info+8,d0
        moveq   #80,d1
        bsr     check                   ; 35: ID_WRITE_PROTECTED
        move.l  d4,d1
        jsr     _UnLock(a6)
        move.l  #n_wf,d1
        move.l  #MODE_OLD,d2
        jsr     _Open(a6)
        move.l  d0,d1
        bsr     isset
        moveq   #-1,d1
        bsr     check                   ; 36: reading still works
        move.l  d7,d1
        jsr     _Close(a6)

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

; isset(d1 = value) -> d7 = the value, d0 = -1 if it is not 0, else 0.
isset:  move.l  d1,d7
        sne     d0
        ext.w   d0
        ext.l   d0
        rts
; lockok(d1 = name): Lock must succeed (one check), then UnLock.
lockok: moveq   #SHARED,d2
        jsr     _Lock(a6)
        move.l  d0,d1
        bsr.s   isset
        moveq   #-1,d1
        bsr     check
        move.l  d7,d1
        jmp     _UnLock(a6)
; fail212 / fail214 (d0 = result of the call): two checks, result 0 then IoErr.
fail212:
        move.l  #212,-(sp)
        bra.s   failn
fail214:
        move.l  #214,-(sp)
failn:  moveq   #0,d1
        bsr     check
        jsr     _IoErr(a6)
        move.l  (sp)+,d1
        bra     check
; mkfile(a0 = name): empty file created.
mkfile: move.l  a0,d1
        move.l  #MODE_NEW,d2
        jsr     _Open(a6)
        move.l  d0,d1
        jmp     _Close(a6)
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
; nextname(d4 = lock): ExNext into fib -> d0 = first two characters of the C name in the high word.
nextname:
        move.l  d4,d1
        move.l  #fib,d2
        jsr     _ExNext(a6)
        move.w  fib+FIB_FILENAME,d0
        swap    d0
        clr.w   d0
        rts
; handler0: hport = DeviceProc("df0:").
handler0:
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
m_fslk: dc.b    "FSGP ",0
m_ok:   dc.b    "OK",13,10,0
m_fail: dc.b    "FAIL ",0
m_end:  dc.b    "FSGP END ",0
m_nl:   dc.b    13,10,0
m_sp:   dc.b    " ",0
        even

        section fsdata,data
n_long36: dc.b  "df0:abcdefghijklmnopqrstuvwxyz0123456789",0
n_long30: dc.b  "df0:abcdefghijklmnopqrstuvwxyz0123",0
n_thru: dc.b    "df0:fsgap_test/x",0
n_sdir: dc.b    "df0:s",0
n_df0:  dc.b    "df0:",0
n_df1:  dc.b    "df1:",0
n_ord:  dc.b    "df0:ord",0
n_ordfh: dc.b   "df0:ord/fh",0
n_ordaa: dc.b   "df0:ord/aa",0
n_ordeu: dc.b   "df0:ord/eu",0
n_d3:   dc.b    "df0:d3",0
n_wnew: dc.b    "df1:new",0
n_wf:   dc.b    "df1:wf",0
n_wnone: dc.b   "df1:nothere",0
        cnop    0,4
b_d3:   dc.b    2,"d3"
        cnop    0,4
b_x:    dc.b    1,"x"
        cnop    0,4
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
