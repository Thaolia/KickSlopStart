; tests/fsrw_test.s - OFS write streams (implementation-side test of docs/analysis/rom-filesystem-v34.md §5 and
; dos-lvo-partial-v34.md §2.2/§2.6): Info keeps D2, Seek on NIL: returns 0, seek error 219, Seek and Read on a file
; open for writing, MODE_READWRITE in place (a missing file is not created), files with extension blocks.
; Run by tests/fsrw_probe.sh from the startup-sequence of a scratch OFS disk in DF0:. One line per check on the
; serial port, "FSRW nnnnnnnn OK" or "FSRW nnnnnnnn FAIL <got> <expected>", then "FSRW END <failures>".
; Build: vasmm68k_mot -Fhunkexe -kick1hunks -o build/fsrw_test tests/fsrw_test.s

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018
MODE_RW  EQU 1004
MODE_OLD EQU 1005
MODE_NEW EQU 1006
OFF_BEG  EQU -1
OFF_CUR  EQU 0
OFF_END  EQU 1
BIGN     EQU 40000

_Open    EQU -30
_Close   EQU -36
_Read    EQU -42
_Write   EQU -48
_Seek    EQU -66
_Lock    EQU -84
_UnLock  EQU -90
_Info    EQU -114
_IoErr   EQU -132

start:  move.l  4.w,a6
        lea     dosname(pc),a1
        moveq   #0,d0
        jsr     -552(a6)                ; OpenLibrary
        tst.l   d0
        beq     quit
        move.l  d0,a6                   ; a6 = DosBase from here on
        lea     bigbuf,a0
        move.l  #BIGN,d0
        bsr     fillA

; --- Info keeps the caller's D2 -------------------------------------------------------------------------------------
        move.l  #n_root,d1
        moveq   #-2,d2                  ; ACCESS_READ
        jsr     _Lock(a6)
        move.l  d0,d4
        move.l  d4,d1
        move.l  #infobuf,d2
        jsr     _Info(a6)
        move.l  d0,d5
        move.l  d2,d0
        move.l  #infobuf,d1
        bsr     check                   ; 1: D2 unchanged
        move.l  d5,d0
        moveq   #-1,d1
        bsr     check                   ; 2: Info -> DOSTRUE
        move.l  d4,d1
        jsr     _UnLock(a6)

; --- Seek on NIL: -> 0 ----------------------------------------------------------------------------------------------
        move.l  #n_nil,d1
        move.l  #MODE_NEW,d2
        jsr     _Open(a6)
        move.l  d0,d4
        moveq   #0,d2
        moveq   #OFF_CUR,d3
        bsr     fseek
        moveq   #0,d1
        bsr     check                   ; 3
        move.l  d4,d1
        jsr     _Close(a6)

; --- new file: Seek and Read while writing ---------------------------------------------------------------------------
        move.l  #n_t1,d1
        move.l  #MODE_NEW,d2
        jsr     _Open(a6)
        move.l  d0,d4
        lea     bigbuf,a0
        move.l  #1000,d3
        bsr     fwrite
        move.l  #1000,d1
        bsr     check                   ; 4: Write 1000
        moveq   #10,d2
        moveq   #OFF_BEG,d3
        bsr     fseek
        move.l  #1000,d1
        bsr     check                   ; 5: Seek -> old position
        lea     s_xyz(pc),a0
        moveq   #3,d3
        bsr     fwrite
        moveq   #3,d1
        bsr     check                   ; 6: overwrite inside the file
        moveq   #0,d2
        moveq   #OFF_END,d3
        bsr     fseek
        moveq   #13,d1
        bsr     check                   ; 7
        move.l  #-5000,d2
        moveq   #OFF_CUR,d3
        bsr     fseek
        moveq   #-1,d1
        bsr     check                   ; 8: out of range
        jsr     _IoErr(a6)
        move.l  #219,d1
        bsr     check                   ; 9: ERROR_SEEK_ERROR
        moveq   #0,d2
        moveq   #OFF_CUR,d3
        bsr     fseek
        move.l  #1000,d1
        bsr     check                   ; 10: position unchanged by the failed Seek (END kept the size 1000)
        lea     rdbuf,a0
        moveq   #4,d3
        bsr     fread
        moveq   #0,d1
        bsr     check                   ; 11: Read at the end -> 0
        moveq   #8,d2
        moveq   #OFF_BEG,d3
        bsr     fseek
        move.l  #1000,d1
        bsr     check                   ; 12
        lea     rdbuf,a0
        moveq   #4,d3
        bsr     fread
        moveq   #4,d1
        bsr     check                   ; 13: Read through a write handle
        move.l  rdbuf,d0
        move.l  #$08095859,d1
        bsr     check                   ; 14: bytes 8..11 = 8, 9, 'X', 'Y'
        move.l  d4,d1
        jsr     _Close(a6)
        lea     expbuf,a0
        move.l  #1000,d0
        bsr     fillA
        lea     expbuf+10,a0
        bsr     putxyz
        move.l  #n_t1,d0
        move.l  #1100,d2
        move.l  #1000,d1
        bsr     verify                  ; 15, 16

; --- MODE_READWRITE ---------------------------------------------------------------------------------------------------
        move.l  #n_none,d1
        move.l  #MODE_RW,d2
        jsr     _Open(a6)
        moveq   #0,d1
        bsr     check                   ; 17: a missing file is not created
        jsr     _IoErr(a6)
        move.l  #205,d1
        bsr     check                   ; 18
        move.l  #n_t1,d1
        move.l  #MODE_RW,d2
        jsr     _Open(a6)
        move.l  d0,d4
        lea     rdbuf,a0
        moveq   #5,d3
        bsr     fread
        moveq   #5,d1
        bsr     check                   ; 19
        move.l  #600,d2
        moveq   #OFF_BEG,d3
        bsr     fseek
        moveq   #5,d1
        bsr     check                   ; 20
        lea     s_q(pc),a0
        moveq   #1,d3
        bsr     fwrite
        moveq   #1,d1
        bsr     check                   ; 21
        lea     rdbuf,a0
        moveq   #4,d3
        bsr     fread
        moveq   #4,d1
        bsr     check                   ; 22
        move.l  rdbuf,d0
        move.l  #$595A5B5C,d1
        bsr     check                   ; 23: bytes 601..604
        moveq   #0,d2
        moveq   #OFF_END,d3
        bsr     fseek
        move.l  #605,d1
        bsr     check                   ; 24
        lea     bigbuf,a0
        move.l  #500,d3
        bsr     fwrite
        move.l  #500,d1
        bsr     check                   ; 25: appended at the end
        move.l  d4,d1
        jsr     _Close(a6)
        moveq   #-1,d1
        bsr     check                   ; 26
        lea     expbuf+1000,a0
        move.l  #500,d0
        bsr     fillA
        move.b  #'Q',expbuf+600
        move.l  #n_t1,d0
        move.l  #2000,d2
        move.l  #1500,d1
        bsr     verify                  ; 27, 28

; --- file with an extension block ------------------------------------------------------------------------------------
        move.l  #n_t2,d1
        move.l  #MODE_NEW,d2
        jsr     _Open(a6)
        move.l  d0,d4
        lea     bigbuf,a0
        move.l  #BIGN,d3
        bsr     fwrite
        move.l  #BIGN,d1
        bsr     check                   ; 29
        moveq   #100,d2
        moveq   #OFF_BEG,d3
        bsr     fseek
        move.l  #BIGN,d1
        bsr     check                   ; 30
        lea     s_xyz(pc),a0
        moveq   #3,d3
        bsr     fwrite
        moveq   #3,d1
        bsr     check                   ; 31: header's table
        move.l  #39000,d2
        moveq   #OFF_BEG,d3
        bsr     fseek
        moveq   #103,d1
        bsr     check                   ; 32
        lea     s_xyz(pc),a0
        moveq   #3,d3
        bsr     fwrite
        moveq   #3,d1
        bsr     check                   ; 33: extension's table
        moveq   #0,d2
        moveq   #OFF_END,d3
        bsr     fseek
        move.l  #39003,d1
        bsr     check                   ; 34
        lea     bigbuf,a0
        move.l  #2000,d3
        bsr     fwrite
        move.l  #2000,d1
        bsr     check                   ; 35
        move.l  d4,d1
        jsr     _Close(a6)
        move.l  #n_t2,d1
        move.l  #MODE_RW,d2
        jsr     _Open(a6)
        move.l  d0,d4
        move.l  #36000,d2
        moveq   #OFF_BEG,d3
        bsr     fseek
        moveq   #0,d1
        bsr     check                   ; 36
        lea     rdbuf,a0
        moveq   #4,d3
        bsr     fread
        moveq   #4,d1
        bsr     check                   ; 37
        move.l  rdbuf,d0
        move.l  #$A0A1A2A3,d1
        bsr     check                   ; 38: data block found through the extension read back from the disk
        move.l  #200,d2
        moveq   #OFF_BEG,d3
        bsr     fseek
        move.l  #36004,d1
        bsr     check                   ; 39
        lea     s_q(pc),a0
        moveq   #1,d3
        bsr     fwrite
        moveq   #1,d1
        bsr     check                   ; 40
        moveq   #0,d2
        moveq   #OFF_END,d3
        bsr     fseek
        move.l  #201,d1
        bsr     check                   ; 41
        lea     bigbuf,a0
        moveq   #100,d3
        bsr     fwrite
        moveq   #100,d1
        bsr     check                   ; 42
        move.l  d4,d1
        jsr     _Close(a6)
        lea     expbuf,a0
        move.l  #BIGN,d0
        bsr     fillA
        lea     expbuf+BIGN,a0
        move.l  #2000,d0
        bsr     fillA
        lea     expbuf+BIGN+2000,a0
        moveq   #100,d0
        bsr     fillA
        lea     expbuf+100,a0
        bsr     putxyz
        lea     expbuf+39000,a0
        bsr     putxyz
        move.b  #'Q',expbuf+200
        move.l  #n_t2,d0
        move.l  #BIGN+3000,d2
        move.l  #BIGN+2100,d1
        bsr     verify                  ; 43, 44

        lea     m_end(pc),a0
        bsr     puts
        move.l  nfail,d0
        bsr     hex8
        lea     m_nl(pc),a0
        bsr     puts
        move.l  a6,a1
        move.l  4.w,a6
        jsr     -414(a6)                ; CloseLibrary
quit:   moveq   #0,d0
        rts

; fwrite(a0 = data, d3 = length) / fread(a0 = buffer, d3 = length) / fseek(d2 = offset, d3 = mode) on the file d4
; -> d0 = result.
fwrite: move.l  d4,d1
        move.l  a0,d2
        jmp     _Write(a6)
fread:  move.l  d4,d1
        move.l  a0,d2
        jmp     _Read(a6)
fseek:  move.l  d4,d1
        jmp     _Seek(a6)

; verify(d0 = name, d2 = length asked, d1 = expected size): the file read back in one Read; two checks: the length
; returned, then the first byte that differs from expbuf (-1 = none).
verify: move.l  d1,-(sp)
        move.l  d2,d3
        move.l  d0,d1
        move.l  #MODE_OLD,d2
        jsr     _Open(a6)
        move.l  d0,d4
        lea     rdbuf,a0
        bsr     fread
        move.l  d0,d5
        move.l  d4,d1
        jsr     _Close(a6)
        move.l  d5,d0
        move.l  (sp),d1
        bsr     check
        move.l  (sp)+,d0
        lea     rdbuf,a0
        lea     expbuf,a1
        moveq   #0,d1
.vf_lp: cmp.l   d0,d1
        beq.s   .vf_same
        cmpm.b  (a0)+,(a1)+
        bne.s   .vf_diff
        addq.l  #1,d1
        bra.s   .vf_lp
.vf_same:
        moveq   #-1,d1
.vf_diff:
        move.l  d1,d0
        moveq   #-1,d1
        bra     check

; fillA(a0 = buffer, d0 = length): byte i = i & 255.
fillA:  moveq   #0,d1
        bra.s   .fa_n
.fa_lp: move.b  d1,(a0)+
        addq.b  #1,d1
.fa_n:  subq.l  #1,d0
        bpl.s   .fa_lp
        rts
putxyz: move.b  #'X',(a0)+
        move.b  #'Y',(a0)+
        move.b  #'Z',(a0)
        rts

; check(d0 = got, d1 = expected): one result line for the next test number. Clobbers d0/d1/a0.
check:  movem.l d0-d1,-(sp)
        addq.l  #1,tno
        lea     m_fsrw(pc),a0
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
        bra.s   puts

puts:   move.b  (a0)+,d1
        beq.s   .pe
.pw:    btst    #5,SERDATR
        beq.s   .pw
        and.w   #$FF,d1
        or.w    #$100,d1
        move.w  d1,SERDAT
        bra.s   puts
.pe:    rts
; hex8(d0): 8 hex digits and a space. Preserves d0.
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
m_fsrw: dc.b    "FSRW ",0
m_ok:   dc.b    "OK",13,10,0
m_fail: dc.b    "FAIL ",0
m_end:  dc.b    "FSRW END ",0
m_nl:   dc.b    13,10,0
m_sp:   dc.b    " ",0
s_xyz:  dc.b    "XYZ"
s_q:    dc.b    "Q"
        even

        section fsdata,data
n_root: dc.b    "df0:",0
n_nil:  dc.b    "NIL:",0
n_t1:   dc.b    "df0:t1",0
n_t2:   dc.b    "df0:t2",0
n_none: dc.b    "df0:none",0
        even
tno:    dc.l    0
nfail:  dc.l    0

        section fsbss,bss
infobuf: ds.l   9
bigbuf: ds.b    BIGN
expbuf: ds.b    BIGN+2200
rdbuf:  ds.b    BIGN+3100
