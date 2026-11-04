; scrfont_probe.s - screen font and title bar height (implementation track, our own test program; expected values
; from intuition-screens-v34 §1.2 and §2.5). Opens three hires screens (one at a time) with NewScreen.Font =
; topaz 8, topaz 9 and "nonexist.font" 8, and writes for each, in hex:
;   "SF <name> <BarHeight> <Screen.Font == our TextAttr ? 1 : 0> <RastPort.TxHeight>"
; (expected: topaz 8 -> 0A 1 8; topaz 9 -> 0B 1 9; nonexist -> intuition's default TextAttr, so 0 and its height).
; Then IntuiTextLength of "Hello" with ITextFont = topaz 8 and with ITextFont = NULL:
;   "SF ITL <width topaz 8> <width default>"     (topaz 8: 5 x 8 = $28).
; Each screen stays 3 s on display. Ends with "SF END".
; Build: vasmm68k_mot -Fhunkexe -kick1hunks -o scrfont_probe tests/scrfont_probe.s

        section code,code

start:
        move.l  ($4).w,a6
        lea     intname(pc),a1
        moveq   #0,d0
        jsr     -552(a6)             ; OpenLibrary
        move.l  d0,a5                ; a5 = IntuitionBase
        lea     dosname(pc),a1
        moveq   #0,d0
        jsr     -552(a6)
        move.l  d0,a4                ; a4 = DOSBase
        lea     ta8(pc),a2
        lea     n_t8(pc),a3
        bsr     tryscreen
        lea     ta9(pc),a2
        lea     n_t9(pc),a3
        bsr     tryscreen
        lea     tanone(pc),a2
        lea     n_none(pc),a3
        bsr     tryscreen
        move.l  a5,a6
        lea     itext(pc),a0
        lea     ta8(pc),a1
        move.l  a1,8(a0)             ; ITextFont = topaz 8
        jsr     -330(a6)             ; IntuiTextLength
        move.l  d0,d7
        lea     itext(pc),a0
        clr.l   8(a0)
        jsr     -330(a6)
        move.l  d0,d2
        move.l  d7,d0
        move.l  d2,d1
        moveq   #0,d2
        lea     n_itl(pc),a0
        bsr     say3
        lea     m_end(pc),a0
        bsr     say
        moveq   #0,d0
        rts

; tryscreen(a2 = TextAttr, a3 = name): opens the screen, reports, waits 3 s, closes it.
tryscreen:
        lea     newscr(pc),a0
        move.l  a2,16(a0)            ; NewScreen.Font
        move.l  a3,20(a0)            ; DefaultTitle = the name
        move.l  a5,a6
        jsr     -198(a6)             ; OpenScreen
        tst.l   d0
        beq.s   .ts_ret
        move.l  d0,a1
        moveq   #0,d0
        move.b  30(a1),d0            ; BarHeight
        moveq   #0,d1
        cmp.l   40(a1),a2            ; Screen.Font
        bne.s   .ts_f
        moveq   #1,d1
.ts_f:
        moveq   #0,d2
        move.w  84+58(a1),d2         ; RastPort.TxHeight
        move.l  a1,-(sp)
        move.l  a3,a0
        bsr     say3
        move.l  a4,a6
        move.l  #150,d1
        jsr     -198(a6)             ; Delay(3 s)
        move.l  (sp)+,a0
        move.l  a5,a6
        jsr     -66(a6)              ; CloseScreen
.ts_ret:
        rts

; say3(a0 = name, d0/d1/d2 = values): "SF <name> <d0> <d1> <d2>".
say3:
        movem.l d2-d4,-(sp)
        lea     line(pc),a1
        move.b  #'S',(a1)+
        move.b  #'F',(a1)+
        move.b  #' ',(a1)+
.s3_n:
        move.b  (a0)+,(a1)+
        bne.s   .s3_n
        subq.l  #1,a1
        movem.l d1-d2,-(sp)
        bsr.s   hex4
        move.l  (sp)+,d0
        bsr.s   hex4
        move.l  (sp)+,d0
        bsr.s   hex4
        move.b  #10,(a1)+
        clr.b   (a1)
        lea     line(pc),a0
        bsr.s   say
        movem.l (sp)+,d2-d4
        rts
hex4:
        move.b  #' ',(a1)+
        moveq   #4-1,d3
        swap    d0
.hx:
        rol.l   #4,d0
        move.w  d0,d4
        and.w   #$F,d4
        move.b  digits(pc,d4.w),(a1)+
        dbra    d3,.hx
        rts
digits: dc.b    "0123456789ABCDEF"

say:
        movem.l d2-d3/a6,-(sp)
        move.l  a0,d2
        moveq   #-1,d3
.sy_len:
        addq.l  #1,d3
        tst.b   (a0)+
        bne.s   .sy_len
        move.l  a4,a6
        jsr     -60(a6)              ; Output
        move.l  d0,d1
        jsr     -48(a6)              ; Write
        movem.l (sp)+,d2-d3/a6
        rts

newscr:
        dc.w    0,0,640,200,2        ; LeftEdge, TopEdge, Width, Height, Depth
        dc.b    0,1
        dc.w    $8000                ; HIRES
        dc.w    $000F                ; CUSTOMSCREEN
        dc.l    0,0,0,0              ; Font, DefaultTitle, Gadgets, CustomBitMap
ta8:    dc.l    topaz
        dc.w    8
        dc.b    0,0
ta9:    dc.l    topaz
        dc.w    9
        dc.b    0,0
tanone: dc.l    nofont
        dc.w    8
        dc.b    0,0
itext:  dc.b    1,0,1,0
        dc.w    0,0
        dc.l    0,hello,0
line:   dcb.b   64,0
intname: dc.b   "intuition.library",0
dosname: dc.b   "dos.library",0
topaz:   dc.b   "topaz.font",0
nofont:  dc.b   "nonexist.font",0
hello:   dc.b   "Hello",0
n_t8:    dc.b   "topaz8",0
n_t9:    dc.b   "topaz9",0
n_none:  dc.b   "nonexist",0
n_itl:   dc.b   "ITL",0
m_end:   dc.b   "SF END",10,0
        even
