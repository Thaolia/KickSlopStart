; tests/ghost_test.s - ghosting of a GADGDISABLED gadget (implementation-side test, intuition-gzz-v34 §6.4).
; Run from a startup-sequence (tests/garea_probe.sh <rom> <exe> <out>); results on the serial port.
; A borderless window at (21,21) on the Workbench screen (BlockPen 1) carries one disabled boolean gadget without
; rendering, box (8,6)-(31,9). ReadPixel over (6..33, 5..10) prints one line per row, '#' = pen 1, '.' = other.
; Expected: dots only inside the box, at x mod 4 = 1 on even rows and x mod 4 = 3 on odd rows (pattern $4444/$1111
; from the layer's top-left corner; the window's odd screen position would shift a screen-aligned pattern):
;   G05 ............................
;   G06 ...#...#...#...#...#...#....     (x = 9, 13, ... 29)
;   G07 .....#...#...#...#...#...#..     (x = 11, 15, ... 31)
;   G08 ...#...#...#...#...#...#....
;   G09 .....#...#...#...#...#...#..
;   G10 ............................
; then "ON" and the same six lines after OnGadget (no erase on 1.3: the dots stay), then "GHOST END".

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018
WD_RPORT EQU 50

start:  move.l  4.w,a6
        lea     gfxname(pc),a1
        moveq   #0,d0
        jsr     -552(a6)                ; OpenLibrary
        move.l  d0,gbase
        beq     .out
        lea     intname(pc),a1
        moveq   #0,d0
        jsr     -552(a6)
        move.l  d0,ibase
        beq     .out
        move.l  d0,a6
        lea     nw(pc),a0
        jsr     -204(a6)                ; OpenWindow
        move.l  d0,win
        beq     .out
        bsr     dump
        lea     m_on(pc),a0
        bsr     puts
        move.l  ibase,a6
        lea     gad(pc),a0
        move.l  win,a1
        sub.l   a2,a2
        jsr     -186(a6)                ; OnGadget
        bsr     dump
        move.l  ibase,a6
        move.l  win,a0
        jsr     -72(a6)                 ; CloseWindow
.out:   lea     m_end(pc),a0
        bsr     puts
        moveq   #0,d0
        rts

; dump: rows 5..10, columns 6..33 of the window's RastPort.
dump:   moveq   #5,d6
.row:   lea     m_g(pc),a0
        bsr     puts
        move.l  d6,d0
        divu    #10,d0
        add.b   #'0',d0
        bsr     putc
        swap    d0
        add.b   #'0',d0
        bsr     putc
        moveq   #' ',d0
        bsr     putc
        moveq   #6,d7
.col:   move.l  gbase,a6
        move.l  win,a0
        move.l  WD_RPORT(a0),a1
        move.l  d7,d0
        move.l  d6,d1
        jsr     -318(a6)                ; ReadPixel
        moveq   #'.',d1
        cmp.l   #1,d0
        bne.s   .pt
        moveq   #'#',d1
.pt:    move.l  d1,d0
        bsr     putc
        addq.l  #1,d7
        cmp.l   #33,d7
        ble.s   .col
        moveq   #13,d0
        bsr     putc
        moveq   #10,d0
        bsr     putc
        addq.l  #1,d6
        cmp.l   #10,d6
        ble.s   .row
        rts

puts:   move.b  (a0)+,d0
        beq.s   .e
        bsr.s   putc
        bra.s   puts
.e:     rts
putc:   btst    #5,SERDATR
        beq.s   putc
        and.w   #$FF,d0
        or.w    #$100,d0
        move.w  d0,SERDAT
        rts

nw:     dc.w    21,21,64,16             ; LeftEdge, TopEdge, Width, Height
        dc.b    0,1                     ; DetailPen, BlockPen
        dc.l    0,$0800                 ; IDCMP, Flags BORDERLESS
        dc.l    gad,0,0,0,0             ; FirstGadget, CheckMark, Title, Screen, BitMap
        dc.w    0,0,0,0,1               ; min/max size, WBENCHSCREEN
gad:    dc.l    0                       ; NextGadget
        dc.w    8,6,24,4                ; LeftEdge, TopEdge, Width, Height
        dc.w    $0103,0,1               ; Flags GADGDISABLED|GADGHNONE, Activation, BOOLGADGET
        dc.l    0,0,0,0,0               ; GadgetRender, SelectRender, GadgetText, MutualExclude, SpecialInfo
        dc.w    0                       ; GadgetID
        dc.l    0                       ; UserData
gfxname: dc.b   "graphics.library",0
intname: dc.b   "intuition.library",0
m_g:    dc.b    "G",0
m_on:   dc.b    "ON",13,10,0
m_end:  dc.b    "GHOST END",13,10,0
        even
gbase:  dc.l    0
ibase:  dc.l    0
win:    dc.l    0
