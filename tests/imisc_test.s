; tests/imisc_test.s - intuition LVOs of the lot 1 (implementation-side test, intuition-misc-v34 / intuition-screens-v34
; / intuition-frame-v34). Run from a startup-sequence (tests/garea_probe.sh <rom> <exe> <out>); results on the serial
; port, one "NAME value(s)" line per check. Expected:
;   LOCK 00000000 00000003          LockIBase(0) and LockIBase(3) return their argument
;   TIME 1                          CurrentTime: second reading later than the first
;   ACT 1 1                         OpenWindow ACTIVATE -> w2 active; ActivateWindow(w1) -> w1 active
;   SETPTR <data> 08 10 FF FE 1     window fields $4A..$51 set; sprite POS/CTL rewritten (shown at once)
;   CLRPTR 00000000 00 00 FF FE     Pointer/height/width cleared, offsets kept
;   INTU 00000000                   Intuition(NULL) through the LVO (list on the stack)
;   WBF 00000001                    WBenchToFront

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018
IB_ACTW  EQU $34

start:  move.l  4.w,a6
        lea     intname(pc),a1
        moveq   #0,d0
        jsr     -552(a6)                ; OpenLibrary
        move.l  d0,ibase
        beq     .out
        moveq   #20,d0                  ; sprite data: posctl, 8 lines, end
        add.l   #24,d0
        move.l  #$10002,d1              ; MEMF_CHIP|MEMF_CLEAR
        jsr     -198(a6)
        move.l  d0,sprdata
        beq     .out
        move.l  ibase,a6

        lea     m_lock(pc),a0           ; --- LockIBase / UnlockIBase
        bsr     puts
        moveq   #0,d0
        jsr     -414(a6)
        bsr     hex8
        sub.l   a0,a0
        jsr     -420(a6)
        moveq   #3,d0
        jsr     -414(a6)
        bsr     hex8
        move.l  #3,a0
        jsr     -420(a6)
        bsr     nl

        lea     t1,a0                   ; --- CurrentTime
        lea     t1+4,a1
        jsr     -84(a6)
        move.l  #300000,d0
.dl:    subq.l  #1,d0
        bne.s   .dl
        lea     t2,a0
        lea     t2+4,a1
        jsr     -84(a6)
        lea     m_time(pc),a0
        bsr     puts
        move.l  t2,d0
        cmp.l   t1,d0
        bhi.s   .tok
        bne.s   .tko
        move.l  t2+4,d0
        cmp.l   t1+4,d0
        bhi.s   .tok
.tko:   lea     m_0(pc),a0
        bra.s   .tpr
.tok:   lea     m_1(pc),a0
.tpr:   bsr     puts

        lea     nw1(pc),a0              ; --- OpenWindow / ActivateWindow
        jsr     -204(a6)
        move.l  d0,w1
        beq     .out
        lea     nw2(pc),a0
        jsr     -204(a6)
        move.l  d0,w2
        beq     .out
        lea     m_act(pc),a0
        bsr     puts
        moveq   #0,d0
        move.l  IB_ACTW(a6),d1
        cmp.l   w2,d1
        bne.s   .a1
        moveq   #1,d0
.a1:    bsr     dig
        move.l  w1,a0
        jsr     -450(a6)                ; ActivateWindow(w1)
        moveq   #0,d0
        move.l  IB_ACTW(a6),d1
        cmp.l   w1,d1
        bne.s   .a2
        moveq   #1,d0
.a2:    bsr     dig
        bsr     nl

        move.l  w1,a0                   ; --- SetPointer on the active window
        move.l  sprdata,a1
        moveq   #8,d0
        moveq   #16,d1
        moveq   #-1,d2
        moveq   #-2,d3
        jsr     -270(a6)
        lea     m_setp(pc),a0
        bsr     puts
        bsr     ptrfields
        moveq   #0,d0
        move.l  sprdata,a0
        tst.l   (a0)                    ; POS/CTL written by ChangeSprite/MoveSprite
        beq.s   .s1
        moveq   #1,d0
.s1:    bsr     dig
        bsr     nl
        move.l  w1,a0                   ; --- ClearPointer
        jsr     -60(a6)
        lea     m_clrp(pc),a0
        bsr     puts
        bsr     ptrfields
        bsr     nl
        move.l  w1,a0                   ; RefreshWindowFrame: must not crash
        jsr     -456(a6)

        clr.l   -(sp)                   ; --- Intuition(NULL), list on the stack
        jsr     -36(a6)
        addq.l  #4,sp
        move.l  d0,-(sp)
        lea     m_intu(pc),a0
        bsr     puts
        move.l  (sp)+,d0
        bsr     hex8
        bsr     nl

        jsr     -342(a6)                ; --- WBenchToFront
        move.l  d0,-(sp)
        lea     m_wbf(pc),a0
        bsr     puts
        move.l  (sp)+,d0
        bsr     hex8
        bsr     nl

        move.l  w2,a0
        jsr     -72(a6)                 ; CloseWindow
        move.l  w1,a0
        jsr     -72(a6)
        lea     m_end(pc),a0
        bsr     puts
.out:   moveq   #0,d0
        rts

; ptrfields: prints Pointer (long) then PtrHeight, PtrWidth, XOffset, YOffset (bytes) of w1.
ptrfields:
        move.l  w1,a1
        move.l  $4A(a1),d0
        bsr     hex8
        moveq   #3,d1
        lea     $4E(a1),a1
.pf:    move.b  (a1)+,d0
        movem.l d1/a1,-(sp)
        bsr     hex2
        movem.l (sp)+,d1/a1
        dbra    d1,.pf
        rts
; dig(d0 = 0/1): one digit and a space.
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
; hex8(d0.l) / hex2(d0.b): hex digits and a space.
hex8:   moveq   #7,d1
        bra.s   hexn
hex2:   ror.l   #8,d0
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
        bra.s   puts
hexd:   dc.b    "0123456789ABCDEF"

; NewWindow: Left, Top, W, H, Detail, Block, IDCMP, Flags, Gadget, CheckMark, Title, Screen, BitMap, min/max, Type
nw1:    dc.w    20,20,200,60
        dc.b    0,1
        dc.l    0,$000E,0,0,title1,0,0
        dc.w    40,20,640,256,1         ; WBENCHSCREEN
nw2:    dc.w    60,60,200,60
        dc.b    0,1
        dc.l    0,$100E,0,0,title2,0,0
        dc.w    40,20,640,256,1
title1: dc.b    "W1",0
title2: dc.b    "W2",0
intname: dc.b   "intuition.library",0
m_lock: dc.b    13,10,"LOCK ",0
m_time: dc.b    "TIME ",0
m_0:    dc.b    "0",13,10,0
m_1:    dc.b    "1",13,10,0
m_act:  dc.b    "ACT ",0
m_setp: dc.b    "SETPTR ",0
m_clrp: dc.b    "CLRPTR ",0
m_intu: dc.b    "INTU ",0
m_wbf:  dc.b    "WBF ",0
m_nl:   dc.b    13,10,0
m_end:  dc.b    "IMISC END",13,10,0
        even

        section bss,bss
ibase:  ds.l    1
sprdata: ds.l   1
w1:     ds.l    1
w2:     ds.l    1
t1:     ds.l    2
t2:     ds.l    2
hbuf:   ds.b    12
