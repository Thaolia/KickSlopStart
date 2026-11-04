; strg_probe.s - ActivateGadget and string gadget editing, black box (implementation track: our own test program;
; public ABI only: exec/dos/intuition .fd, intuition.h Window/Gadget/StringInfo/IntuiMessage layouts, AutoDocs).
; A CLI program (run from the startup-sequence by tests/strg_probe.sh, which types the keys). It opens a window
; (ACTIVATE) with string gadgets S1..S4, a boolean gadget B and a disabled string gadget D, then runs tests; for each
; test that needs keys it prints "ST WAIT <n>" and waits for the GADGETUP; the harness types the keys after the
; WAIT line. Serial output (polled, one line under Forbid), hex:
;   "ST A<n> <ActivateGadget D0 long> <Flags> <BufferPos> <DispPos> <NumChars>"   right after ActivateGadget
;   "ST M<n> <Class long> <Code>"                     any other IDCMP message while waiting
;   "ST U<n> <Code> <Qualifier> <IAddress = the gadget: 01>"   the GADGETUP
;   "ST B<n> <BufferPos> <DispPos> <NumChars> <LongInt long> <Flags> |<Buffer>| |<UndoBuffer>|"
;   "ST A8 ..." twice (boolean gadget, disabled gadget), "ST A9 <D0> <active window = ours: 01>" after a second
;   window took the activation, "ST END".
; Keys typed by the harness, per test:
;   1 S1 "Hello", BufferPos 2: "abc" Return
;   2 S2 LONGINT "12", BufferPos 0: "5-x9" Return
;   3 S1: Shift+Left, "Z", Right, Del, Shift+Right, Backspace, Enter
;   4 S1: right Amiga+X, "Q", Return
;   5 S1: "zz", right Amiga+Q, Return
;   6 S3 MaxChars 6 "abcd": "123" Return
;   7 S4 24 pixels wide, MaxChars 20, empty: "abcdefgh" Return
; Build: vasmm68k_mot -Fhunkexe -kick1hunks -o strg_probe tests/strg_probe.s

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018

_Forbid     EQU -132
_Permit     EQU -138
_Wait       EQU -318
_GetMsg     EQU -372
_ReplyMsg   EQU -378
_OpenLibrary EQU -552
_Delay      EQU -198
_OpenWindow EQU -204
_ActivateGadget EQU -462

WD_USERPORT EQU 86
IM_CLASS EQU 20
IM_CODE  EQU 24
IM_QUAL  EQU 26
IM_IADDR EQU 28
GG_FLAGS EQU 12
GG_SINFO EQU 34
SI_BUF   EQU 0
SI_UNDO  EQU 4
SI_POS   EQU 8
SI_DISP  EQU 12
SI_NUM   EQU 16
SI_LONG  EQU 28
GADGETUP EQU $40

        section code,code
start:
        move.l  ($4).w,a6
        lea     intname(pc),a1
        moveq   #0,d0
        jsr     _OpenLibrary(a6)
        move.l  d0,ibase
        beq     .out
        lea     dosname(pc),a1
        moveq   #0,d0
        jsr     _OpenLibrary(a6)
        move.l  d0,dbase
        beq     .out
        move.l  ibase(pc),a6
        lea     neww(pc),a0
        jsr     _OpenWindow(a6)
        move.l  d0,win
        beq     .out
        bsr     pause

        moveq   #1,d7
        lea     gS1(pc),a2
        bsr     test
        moveq   #2,d7
        lea     gS2(pc),a2
        bsr     test
        moveq   #3,d7
        lea     gS1(pc),a2
        bsr     test
        moveq   #4,d7
        lea     gS1(pc),a2
        bsr     test
        moveq   #5,d7
        lea     gS1(pc),a2
        bsr     test
        moveq   #6,d7
        lea     gS3(pc),a2
        bsr     test
        moveq   #7,d7
        lea     gS4(pc),a2
        bsr     test

        moveq   #8,d7                   ; boolean, then disabled string gadget: no keys
        lea     gB(pc),a2
        bsr     activate
        lea     gD(pc),a2
        bsr     activate

        move.l  ibase(pc),a6            ; 9: another window takes the activation
        lea     neww2(pc),a0
        jsr     _OpenWindow(a6)
        bsr     pause
        lea     gS1(pc),a0
        move.l  win(pc),a1
        sub.l   a2,a2
        move.l  ibase(pc),a6
        jsr     _ActivateGadget(a6)
        move.l  d0,d6
        bsr     lbeg
        lea     m_a9(pc),a0
        bsr     puts
        move.l  d6,d0
        bsr     slong
        move.l  ibase(pc),a0
        move.l  52(a0),d0               ; ib_ActiveWindow
        cmp.l   win(pc),d0
        seq     d0
        and.b   #1,d0
        bsr     shex
        bsr     lend
        bsr     lbeg
        lea     m_end(pc),a0
        bsr     puts
        bsr     lend
.out:   moveq   #0,d0
        rts

; pause: Delay(2 s) (activation is asynchronous on 1.3).
pause:
        move.l  dbase(pc),a6
        moveq   #100,d1
        jsr     _Delay(a6)
        rts

; test(d7 = n, a2 = gadget): ActivateGadget, "ST WAIT n", wait for the GADGETUP, report.
test:
        bsr     activate
        bsr     lbeg
        lea     m_wait(pc),a0
        bsr     puts
        move.l  d7,d0
        bsr     shex
        bsr     lend
.wt:    move.l  win(pc),a0
        move.l  WD_USERPORT(a0),a3
        move.l  ($4).w,a6
        moveq   #0,d0
        move.b  15(a3),d1               ; mp_SigBit
        bset    d1,d0
        jsr     _Wait(a6)
.get:   move.l  a3,a0
        move.l  ($4).w,a6
        jsr     _GetMsg(a6)
        tst.l   d0
        beq.s   .wt
        move.l  d0,a4
        bsr     lbeg
        cmp.l   #GADGETUP,IM_CLASS(a4)
        beq.s   .up
        moveq   #'M',d0
        bsr     tag
        move.l  IM_CLASS(a4),d0
        bsr     slong
        move.w  IM_CODE(a4),d0
        bsr     sword
        bsr     lend
        move.l  a4,a1
        jsr     _ReplyMsg(a6)
        bra.s   .get
.up:    moveq   #'U',d0
        bsr     tag
        move.w  IM_CODE(a4),d0
        bsr     sword
        move.w  IM_QUAL(a4),d0
        bsr     sword
        cmp.l   IM_IADDR(a4),a2
        seq     d0
        and.b   #1,d0
        bsr     shex
        bsr     lend
        move.l  a4,a1
        move.l  ($4).w,a6
        jsr     _ReplyMsg(a6)
        move.l  GG_SINFO(a2),a4         ; "ST B<n> ..."
        bsr     lbeg
        moveq   #'B',d0
        bsr     tag
        move.w  SI_POS(a4),d0
        bsr     sword
        move.w  SI_DISP(a4),d0
        bsr     sword
        move.w  SI_NUM(a4),d0
        bsr     sword
        move.l  SI_LONG(a4),d0
        bsr     slong
        move.w  GG_FLAGS(a2),d0
        bsr     sword
        move.l  SI_BUF(a4),a0
        bsr     qstr
        move.l  SI_UNDO(a4),a0
        bsr     qstr
        bra     lend

; activate(d7 = n, a2 = gadget): "ST A<n> <D0> <Flags> <BufferPos> <DispPos> <NumChars>".
activate:
        move.l  a2,a0
        move.l  win(pc),a1
        sub.l   a2,a2
        move.l  ibase(pc),a6
        move.l  a0,-(sp)
        jsr     _ActivateGadget(a6)
        move.l  (sp)+,a2
        move.l  d0,d6
        bsr     lbeg
        moveq   #'A',d0
        bsr     tag
        move.l  d6,d0
        bsr     slong
        move.w  GG_FLAGS(a2),d0
        bsr     sword
        move.l  GG_SINFO(a2),d0
        beq.s   .ac_end
        move.l  d0,a4
        move.w  SI_POS(a4),d0
        bsr     sword
        move.w  SI_DISP(a4),d0
        bsr     sword
        move.w  SI_NUM(a4),d0
        bsr     sword
.ac_end:
        bra     lend

; tag(d0 = letter, d7 = n): "ST <letter><n>".
tag:    move.l  d0,-(sp)
        lea     m_st(pc),a0
        bsr     puts
        move.l  (sp)+,d0
        bsr     putc
        move.l  d7,d0
        add.b   #'0',d0
        bra     putc

; lbeg / lend: one line under Forbid (other tasks of our ROM also print on the serial port).
lbeg:   move.l  a6,-(sp)
        move.l  ($4).w,a6
        jsr     _Forbid(a6)
        move.l  (sp)+,a6
        rts
lend:   moveq   #10,d0
        bsr     putc
        move.l  a6,-(sp)
        move.l  ($4).w,a6
        jsr     _Permit(a6)
        move.l  (sp)+,a6
        rts

; qstr(a0): " |text|" (bytes below $20 or above $7E as '.').
qstr:   move.l  a0,-(sp)
        moveq   #' ',d0
        bsr     putc
        moveq   #'|',d0
        bsr     putc
        move.l  (sp)+,a0
.q_lp:  move.b  (a0)+,d0
        beq.s   .q_end
        cmp.b   #$20,d0
        blo.s   .q_dot
        cmp.b   #$7E,d0
        bls.s   .q_put
.q_dot: moveq   #'.',d0
.q_put: bsr     putc
        bra.s   .q_lp
.q_end: moveq   #'|',d0
        bra     putc

slong:  move.l  d0,-(sp)
        swap    d0
        bsr.s   sword
        move.l  (sp)+,d0
        move.l  d0,-(sp)
        lsr.w   #8,d0
        bsr.s   hexb
        move.l  (sp)+,d0
        bra.s   hexb
sword:  move.l  d0,-(sp)
        lsr.w   #8,d0
        bsr.s   shex
        move.l  (sp)+,d0
        bra.s   hexb
shex:   move.l  d0,-(sp)
        moveq   #' ',d0
        bsr.s   putc
        move.l  (sp)+,d0
hexb:   move.l  d0,-(sp)
        lsr.b   #4,d0
        bsr.s   .dig
        move.l  (sp)+,d0
.dig:   and.w   #$F,d0
        move.b  digits(pc,d0.w),d0
        bra.s   putc
digits: dc.b    "0123456789ABCDEF"

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

ibase:  dc.l    0
dbase:  dc.l    0
win:    dc.l    0

intname: dc.b   "intuition.library",0
dosname: dc.b   "dos.library",0
title:   dc.b   "strg",0
m_st:    dc.b   "ST ",0
m_wait:  dc.b   "ST WAIT",0
m_a9:    dc.b   "ST A9",0
m_end:   dc.b   "ST END",0
        even

neww:   dc.w    20,20,400,120
        dc.b    0,1
        dc.l    $00000060               ; IDCMP: GADGETDOWN, GADGETUP
        dc.l    $00001006               ; ACTIVATE, WINDOWDRAG, WINDOWDEPTH
        dc.l    gS1,0,title,0,0
        dc.w    100,50,640,200
        dc.w    1                       ; WBENCHSCREEN
neww2:  dc.w    300,150,200,40
        dc.b    0,1
        dc.l    0
        dc.l    $00001006
        dc.l    0,0,title,0,0
        dc.w    100,30,640,200
        dc.w    1

; Gadgets (44 bytes): Next, Left, Top, Width, Height, Flags, Activation, Type, Render, Select, Text, MutualExclude,
; SpecialInfo, GadgetID, UserData. Activation RELVERIFY ($0001), LONGINT $0800. Type STRGADGET 4, BOOLGADGET 1.
gS1:    dc.l    gS2
        dc.w    20,20,200,10, 0, $0001, 4
        dc.l    0,0,0,0,si1
        dc.w    1
        dc.l    0
gS2:    dc.l    gS3
        dc.w    20,35,80,10, 0, $0801, 4
        dc.l    0,0,0,0,si2
        dc.w    2
        dc.l    0
gS3:    dc.l    gS4
        dc.w    20,50,80,10, 0, $0001, 4
        dc.l    0,0,0,0,si3
        dc.w    3
        dc.l    0
gS4:    dc.l    gB
        dc.w    20,65,24,10, 0, $0001, 4
        dc.l    0,0,0,0,si4
        dc.w    4
        dc.l    0
gB:     dc.l    gD
        dc.w    240,20,40,10, 0, $0001, 1
        dc.l    0,0,0,0,0
        dc.w    5
        dc.l    0
gD:     dc.l    0
        dc.w    240,35,80,10, $0100, $0001, 4
        dc.l    0,0,0,0,si5
        dc.w    6
        dc.l    0

; StringInfo (36 bytes): Buffer, UndoBuffer, BufferPos, MaxChars, DispPos, UndoPos, NumChars, DispCount, CLeft, CTop,
; LayerPtr, LongInt, AltKeyMap.
si1:    dc.l    b1,u1
        dc.w    2,32,0,0,5,0,0,0
        dc.l    0,0,0
si2:    dc.l    b2,u2
        dc.w    0,12,0,0,2,0,0,0
        dc.l    0,0,0
si3:    dc.l    b3,u3
        dc.w    4,6,0,0,4,0,0,0
        dc.l    0,0,0
si4:    dc.l    b4,u4
        dc.w    0,20,0,0,0,0,0,0
        dc.l    0,0,0
si5:    dc.l    b5,u5
        dc.w    0,8,0,0,0,0,0,0
        dc.l    0,0,0
b1:     dc.b    "Hello"
        dcb.b   32-5,0
u1:     dcb.b   32,0
b2:     dc.b    "12"
        dcb.b   12-2,0
u2:     dcb.b   12,0
b3:     dc.b    "abcd",0,0
u3:     dcb.b   6,0
b4:     dcb.b   20,0
u4:     dcb.b   20,0
b5:     dcb.b   8,0
u5:     dcb.b   8,0
