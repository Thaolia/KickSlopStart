; tests/fsnodisk_test.s - dos's unit requesters (implementation-side test of docs/analysis/dos-lvo-partial-v34.md
; §1.4): CreateDir on DF1:, either empty ("No disk present / in unit  1", 226) or holding a non-DOS disk (argument
; "d": "Not a DOS disk / in unit  1", 225) or a DOS disk that fails validation (argument "v": "Volume / <name> /
; is not validated", 213). With pr_WindowPtr = -1 the call fails at once; with pr_WindowPtr = 0 the
; requester opens ("FSND REQ" is sent first) and the harness (tests/fsnodisk_probe.sh) answers Cancel with left
; Amiga + B. Lines "FSND nnnnnnnn OK|FAIL", then "FSND END <failures>".
; Build: vasmm68k_mot -Fhunkexe -kick1hunks -o build/fsnodisk_test tests/fsnodisk_test.s

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018
PR_WINDOWPTR EQU $B8
_CreateDir EQU -120
_IoErr   EQU -132

start:  move.l  #226,ecode
        subq.l  #1,d0
        bmi.s   .arg
        cmp.b   #'d',(a0)
        bne.s   .argv
        move.l  #225,ecode
.argv:  cmp.b   #'v',(a0)
        bne.s   .arg
        move.l  #213,ecode
.arg:   move.l  4.w,a6
        lea     dosname(pc),a1
        moveq   #0,d0
        jsr     -552(a6)
        tst.l   d0
        beq     quit
        move.l  d0,a6
        bsr     getwin
        moveq   #-1,d0
        move.l  d0,PR_WINDOWPTR(a0)
        move.l  #n_x,d1
        jsr     _CreateDir(a6)
        moveq   #0,d1
        bsr     check                   ; 1: no requester
        jsr     _IoErr(a6)
        move.l  ecode,d1
        bsr     check                   ; 2
        bsr     getwin
        clr.l   PR_WINDOWPTR(a0)
        lea     m_req(pc),a0
        bsr     puts
        move.l  #n_x,d1
        jsr     _CreateDir(a6)
        moveq   #0,d1
        bsr     check                   ; 3: Cancel
        jsr     _IoErr(a6)
        move.l  ecode,d1
        bsr     check                   ; 4
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
getwin: move.l  4.w,a0
        move.l  276(a0),a0
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
m_fslk: dc.b    "FSND ",0
m_ok:   dc.b    "OK",13,10,0
m_fail: dc.b    "FAIL ",0
m_end:  dc.b    "FSND END ",0
m_req:  dc.b    "FSND REQ",13,10,0
m_nl:   dc.b    13,10,0
m_sp:   dc.b    " ",0
n_x:    dc.b    "df1:x",0
        even
tno:    dc.l    0
ecode:  dc.l    0
nfail:  dc.l    0
