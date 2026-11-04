; glist_probe.s - intuition gadget list functions, black box (implementation track: our own test program; public
; ABI only: intuition/graphics .fd, intuition.h Gadget/Border/Window layouts, AutoDocs of AddGadget, AddGList,
; RemoveGadget, RemoveGList, RefreshGadgets, RefreshGList, OnGadget, OffGadget).
; Two stages like concmd_probe.s: the bootblock reloads the first LOADSZ bytes and jumps to stage 2, which opens the
; Workbench screen and a window with drag, depth and close gadgets. Our gadgets have GadgetID 'A'..'H'.
; Serial output:
;   "GP <step> <d0 word> | <list>"   list = Window.FirstGadget chain: our gadgets by letter, system gadgets as
;                                    "s" + GadgetType low byte (hex); "!" = more than 20 entries
;   "GP N <gadget> <next>"           NextGadget of one of our gadgets: letter, "0" or "?" (elsewhere)
;   "GP F <gadget> <Flags word>"
;   "GP P <step> <pen A> <pen B> <pen C> <pen D>"   pen at the middle of each gadget's top border line after the
;                                    step (area cleared to pen 0 before it)
;   "GP M <step> <byte>"             8 pixels inside gadget B (bit 7 = leftmost), 1 = pen not 0
;   "GP I <step> <pen>"              one pixel inside gadget A (GADGHCOMP + SELECTED)
;   "GP END"
; Build and run: tests/glist_probe.sh <out_dir> [rom]

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018
LOADSZ   EQU 8192

_AllocMem   EQU -198
_DoIO       EQU -456
_OpenLibrary EQU -552
; intuition
_AddGadget  EQU -42
_OffGadget  EQU -174
_OnGadget   EQU -186
_OpenWindow EQU -204
_OpenWorkBench EQU -210
_RefreshGadgets EQU -222
_RemoveGadget EQU -228
_RefreshGList EQU -432
_AddGList   EQU -438
_RemoveGList EQU -444
; graphics
_SetAPen    EQU -342
_RectFill   EQU -306
_ReadPixel  EQU -318

WD_RPORT EQU 50
WD_FIRSTGADGET EQU 62
GG_NEXT  EQU 0
GG_FLAGS EQU 12
GG_TYPE  EQU 16
GG_ID    EQU 38

; stage 1 (bootblock, a1 = trackdisk IOStdReq, a6 = ExecBase)
boot:
        movea.l a1,a5
        move.l  #LOADSZ,d0
        move.l  #$10003,d1              ; MEMF_PUBLIC|MEMF_CHIP|MEMF_CLEAR
        jsr     _AllocMem(a6)
        tst.l   d0
        beq.s   .ko
        movea.l d0,a4
        move.w  #2,28(a5)               ; CMD_READ
        move.l  #LOADSZ,36(a5)
        move.l  a4,40(a5)
        clr.l   44(a5)
        movea.l a5,a1
        jsr     _DoIO(a6)
        lea     12+stage2-boot(a4),a0
        jmp     (a0)
.ko:    moveq   #-1,d0
        rts

; stage 2. d7 = IntuitionBase, d6 = window, d5 = GfxBase, a5 = window RastPort.
stage2:
        lea     neww+26(pc),a0          ; the binary runs where stage 1 loaded it: pointers are set here
        lea     title(pc),a1
        move.l  a1,(a0)
        lea     bord+8(pc),a0
        lea     bxy(pc),a1
        move.l  a1,(a0)
        lea     gA(pc),a0
        lea     bord(pc),a1
        moveq   #4-1,d0
.rel:   lea     GSIZE(a0),a2
        move.l  a2,(a0)                 ; A->B->C->D (D.Next cleared below)
        move.l  a1,18(a0)               ; GadgetRender
        move.l  a2,a0
        dbra    d0,.rel
        clr.l   -GSIZE(a0)
        lea     gA(pc),a1
        move.l  a1,(a0)                 ; E.Next = A
        lea     intname(pc),a1
        moveq   #0,d0
        jsr     _OpenLibrary(a6)
        move.l  d0,d7
        beq     hang
        lea     gfxname(pc),a1
        moveq   #0,d0
        jsr     _OpenLibrary(a6)
        move.l  d0,d5
        beq     hang
        move.l  d7,a6
        jsr     _OpenWorkBench(a6)
        lea     neww(pc),a0
        jsr     _OpenWindow(a6)
        move.l  d0,d6
        beq     hang
        move.l  d6,a0
        move.l  WD_RPORT(a0),a5

        moveq   #'0',d0                 ; the fresh window
        moveq   #0,d1
        bsr     line

        move.l  d6,a0                   ; 1: AddGadget at the end (-1); E.NextGadget preset to A
        lea     gE(pc),a1
        moveq   #-1,d0
        jsr     _AddGadget(a6)
        move.l  d0,d1
        moveq   #'1',d0
        bsr     line
        moveq   #'E',d0
        bsr     pnext

        move.l  d6,a0                   ; 2: AddGadget at 0
        lea     gF(pc),a1
        moveq   #0,d0
        jsr     _AddGadget(a6)
        move.l  d0,d1
        moveq   #'2',d0
        bsr     line

        move.l  d6,a0                   ; 3: AddGadget at 2
        lea     gG(pc),a1
        moveq   #2,d0
        jsr     _AddGadget(a6)
        move.l  d0,d1
        moveq   #'3',d0
        bsr     line

        move.l  d6,a0                   ; 4: AddGadget at 100 (past the end)
        lea     gH(pc),a1
        moveq   #100,d0
        jsr     _AddGadget(a6)
        move.l  d0,d1
        moveq   #'4',d0
        bsr     line

        move.l  d6,a0                   ; 5: RemoveGadget G
        lea     gG(pc),a1
        jsr     _RemoveGadget(a6)
        move.l  d0,d1
        moveq   #'5',d0
        bsr     line
        moveq   #'G',d0
        bsr     pnext

        move.l  d6,a0                   ; 6: RemoveGadget G again (not in the list)
        lea     gG(pc),a1
        jsr     _RemoveGadget(a6)
        move.l  d0,d1
        moveq   #'6',d0
        bsr     line

        move.l  d6,a0                   ; 7: AddGList A->B->C->D at 1, 2 gadgets
        lea     gA(pc),a1
        moveq   #1,d0
        moveq   #2,d1
        sub.l   a2,a2
        jsr     _AddGList(a6)
        move.l  d0,d1
        moveq   #'7',d0
        bsr     line
        moveq   #'B',d0
        bsr     pnext
        moveq   #'C',d0
        bsr     pnext

        move.l  d6,a0                   ; 8: RemoveGList A, 2 gadgets
        lea     gA(pc),a1
        moveq   #2,d0
        jsr     _RemoveGList(a6)
        move.l  d0,d1
        moveq   #'8',d0
        bsr     line
        moveq   #'B',d0
        bsr     pnext

        lea     gB(pc),a0               ; the chain A->B->C->D again
        lea     gC(pc),a1
        move.l  a1,(a0)
        move.l  d6,a0                   ; 9: AddGList A at -1, all (-1)
        lea     gA(pc),a1
        moveq   #-1,d0
        moveq   #-1,d1
        sub.l   a2,a2
        jsr     _AddGList(a6)
        move.l  d0,d1
        moveq   #'9',d0
        bsr     line

        move.l  d6,a0                   ; R: RemoveGList A, all (-1)
        lea     gA(pc),a1
        moveq   #-1,d0
        jsr     _RemoveGList(a6)
        move.l  d0,d1
        moveq   #'R',d0
        bsr     line
        moveq   #'D',d0
        bsr     pnext

        lea     gC(pc),a0               ; chain A->B->C->D, then add the four at the head
        lea     gD(pc),a1
        move.l  a1,(a0)
        clr.l   (a1)
        lea     gB(pc),a0
        lea     gC(pc),a1
        move.l  a1,(a0)
        lea     gA(pc),a0
        lea     gB(pc),a1
        move.l  a1,(a0)
        move.l  d6,a0                   ; S: AddGList A at 0, 4 gadgets
        lea     gA(pc),a1
        moveq   #0,d0
        moveq   #4,d1
        sub.l   a2,a2
        jsr     _AddGList(a6)
        move.l  d0,d1
        moveq   #'S',d0
        bsr     line
        lea     gD(pc),a0
        moveq   #'D',d0
        bsr     pnext

; --- rendering
        moveq   #'a',d0                 ; a: no call (does AddGList draw?)
        bsr     pens
        bsr     clear
        lea     gA(pc),a0               ; b: RefreshGList A, 2
        move.l  d6,a1
        sub.l   a2,a2
        moveq   #2,d0
        move.l  d7,a6
        jsr     _RefreshGList(a6)
        moveq   #'b',d0
        bsr     pens
        bsr     clear
        lea     gB(pc),a0               ; c: RefreshGadgets B (B and everything after it)
        move.l  d6,a1
        sub.l   a2,a2
        move.l  d7,a6
        jsr     _RefreshGadgets(a6)
        moveq   #'c',d0
        bsr     pens
        bsr     clear
        lea     gA(pc),a0               ; d: RefreshGList A, 0
        move.l  d6,a1
        sub.l   a2,a2
        moveq   #0,d0
        move.l  d7,a6
        jsr     _RefreshGList(a6)
        moveq   #'d',d0
        bsr     pens
        bsr     clear
        lea     gB(pc),a0               ; e: OffGadget B
        move.l  d6,a1
        sub.l   a2,a2
        move.l  d7,a6
        jsr     _OffGadget(a6)
        moveq   #'e',d0
        bsr     pens
        moveq   #'e',d0
        bsr     ghost
        moveq   #'B',d0
        bsr     pflags
        bsr     clear
        lea     gB(pc),a0               ; f: OnGadget B
        move.l  d6,a1
        sub.l   a2,a2
        move.l  d7,a6
        jsr     _OnGadget(a6)
        moveq   #'f',d0
        bsr     pens
        moveq   #'f',d0
        bsr     ghost
        moveq   #'B',d0
        bsr     pflags
        bsr     clear
        lea     gA(pc),a0               ; g: A SELECTED (GADGHCOMP), RefreshGList A, 1
        or.w    #$0080,GG_FLAGS(a0)
        move.l  d6,a1
        sub.l   a2,a2
        moveq   #1,d0
        move.l  d7,a6
        jsr     _RefreshGList(a6)
        moveq   #'g',d0
        bsr     pens
        lea     m_i(pc),a0
        bsr     puts
        move.l  a5,a1
        moveq   #35,d0
        moveq   #45,d1
        move.l  d5,a6
        jsr     _ReadPixel(a6)
        bsr     shex
        bsr     nl
        lea     m_end(pc),a0
        bsr     puts
hang:   bra.s   hang

; line(d0 = step char, d1 = value): "GP <step> <word> | <list>".
line:
        move.l  d1,-(sp)
        move.l  d0,-(sp)
        lea     m_gp(pc),a0
        bsr     puts
        move.l  (sp)+,d0
        bsr     putc
        move.l  (sp)+,d0
        bsr     sword
        lea     m_bar(pc),a0
        bsr     puts
        move.l  d6,a0
        move.l  WD_FIRSTGADGET(a0),d2
        moveq   #20-1,d3
.l_lp:  tst.l   d2
        beq.s   .l_end
        move.l  d2,a0
        moveq   #' ',d0
        bsr     putc
        move.w  GG_TYPE(a0),d0
        bmi.s   .l_sys
        move.w  GG_ID(a0),d0
        bsr     putc
        bra.s   .l_nx
.l_sys: moveq   #'s',d0
        bsr     putc
        move.w  GG_TYPE(a0),d0
        bsr     hexb
.l_nx:  move.l  (a0),d2
        dbra    d3,.l_lp
        moveq   #'!',d0
        bsr     putc
.l_end: move.l  d7,a6
        bra     nl

; gad(d0 = letter) -> a0 = our gadget.
gad:    sub.w   #'A',d0
        mulu    #GSIZE,d0
        lea     gA(pc),a0
        add.l   d0,a0
        rts

; pnext(d0 = letter): "GP N <letter> <next>".
pnext:
        move.l  d0,-(sp)
        lea     m_n(pc),a0
        bsr     puts
        move.l  (sp),d0
        bsr     putc
        moveq   #' ',d0
        bsr     putc
        move.l  (sp)+,d0
        bsr.s   gad
        move.l  (a0),d1
        moveq   #'0',d0
        tst.l   d1
        beq.s   .pn_out
        moveq   #'?',d0
        lea     gA(pc),a0
        sub.l   a0,d1
        bmi.s   .pn_out
        divu    #GSIZE,d1
        cmp.w   #8,d1
        bhs.s   .pn_out
        swap    d1
        tst.w   d1
        bne.s   .pn_out
        swap    d1
        moveq   #'A',d0
        add.w   d1,d0
.pn_out:
        bsr     putc
        move.l  d7,a6
        bra     nl

; pflags(d0 = letter): "GP F <letter> <Flags>".
pflags:
        move.l  d0,-(sp)
        lea     m_f(pc),a0
        bsr     puts
        move.l  (sp),d0
        bsr     putc
        move.l  (sp)+,d0
        bsr.s   gad
        move.w  GG_FLAGS(a0),d0
        bsr     sword
        move.l  d7,a6
        bra     nl

; clear: pen 0 over the gadget row.
clear:
        move.l  d5,a6
        move.l  a5,a1
        moveq   #0,d0
        jsr     _SetAPen(a6)
        move.l  a5,a1
        moveq   #10,d0
        moveq   #35,d1
        move.l  #220,d2
        moveq   #60,d3
        jsr     _RectFill(a6)
        move.l  d7,a6
        rts

; pens(d0 = step char): "GP P <step> <pen A..D>", top border middle of each gadget (x + 15, y = 40).
pens:
        move.l  d0,-(sp)
        lea     m_p(pc),a0
        bsr     puts
        move.l  (sp)+,d0
        bsr     putc
        moveq   #35,d2
.p_lp:  move.l  a5,a1
        move.l  d2,d0
        moveq   #40,d1
        move.l  d5,a6
        jsr     _ReadPixel(a6)
        bsr     shex
        add.w   #50,d2
        cmp.w   #35+4*50,d2
        blo.s   .p_lp
        move.l  d7,a6
        bra     nl

; ghost(d0 = step char): "GP M <step> <byte>", pixels x = 78..85, y = 45 (inside B).
ghost:
        move.l  d0,-(sp)
        lea     m_m(pc),a0
        bsr     puts
        move.l  (sp)+,d0
        bsr     putc
        moveq   #0,d3
        moveq   #78,d2
.g_lp:  move.l  a5,a1
        move.l  d2,d0
        moveq   #45,d1
        move.l  d5,a6
        jsr     _ReadPixel(a6)
        add.b   d3,d3
        tst.l   d0
        beq.s   .g_z
        addq.b  #1,d3
.g_z:   addq.w  #1,d2
        cmp.w   #86,d2
        blo.s   .g_lp
        move.l  d3,d0
        bsr     shex
        move.l  d7,a6
        bra     nl

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

nl:     moveq   #10,d0
        bra.s   putc
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

neww:   dc.w    20,20,400,100
        dc.b    0,1
        dc.l    0                       ; IDCMP
        dc.l    $100E                   ; ACTIVATE, WINDOWDRAG, WINDOWDEPTH, WINDOWCLOSE
        dc.l    0,0,0,0,0               ; Title set at run time
        dc.w    100,50,640,200
        dc.w    1                       ; WBENCHSCREEN
intname: dc.b   "intuition.library",0
gfxname: dc.b   "graphics.library",0
title:   dc.b   "glist",0
m_gp:    dc.b   "GP ",0
m_bar:   dc.b   " |",0
m_n:     dc.b   "GP N ",0
m_f:     dc.b   "GP F ",0
m_p:     dc.b   "GP P ",0
m_m:     dc.b   "GP M ",0
m_i:     dc.b   "GP I g",0
m_end:   dc.b   "GP END",10,0
        even

; Border: 30 x 10 rectangle, pen 1, JAM1.
bord:   dc.w    0,0
        dc.b    1,0,0,5
        dc.l    0,0                     ; XY set at run time
bxy:    dc.w    0,0, 29,0, 29,9, 0,9, 0,0

; Gadgets (44 bytes): A-D on the row y = 40 (x = 20, 70, 120, 170) with the border, E-H at y = 70 without render.
; Links and GadgetRender are set at run time: A.Next = B, B.Next = C, C.Next = D, E.Next = A.
GSIZE   EQU 44
gA:     dc.l    0
        dc.w    20,40,30,10, 0, 1, 1
        dc.l    0,0,0,0,0
        dc.w    'A'
        dc.l    0
gB:     dc.l    0
        dc.w    70,40,30,10, 0, 1, 1
        dc.l    0,0,0,0,0
        dc.w    'B'
        dc.l    0
gC:     dc.l    0
        dc.w    120,40,30,10, 0, 1, 1
        dc.l    0,0,0,0,0
        dc.w    'C'
        dc.l    0
gD:     dc.l    0
        dc.w    170,40,30,10, 0, 1, 1
        dc.l    0,0,0,0,0
        dc.w    'D'
        dc.l    0
gE:     dc.l    0
        dc.w    20,70,30,10, 0, 1, 1
        dc.l    0,0,0,0,0
        dc.w    'E'
        dc.l    0
gF:     dc.l    0
        dc.w    70,70,30,10, 0, 1, 1
        dc.l    0,0,0,0,0
        dc.w    'F'
        dc.l    0
gG:     dc.l    0
        dc.w    120,70,30,10, 0, 1, 1
        dc.l    0,0,0,0,0
        dc.w    'G'
        dc.l    0
gH:     dc.l    0
        dc.w    170,70,30,10, 0, 1, 1
        dc.l    0,0,0,0,0
        dc.w    'H'
        dc.l    0
