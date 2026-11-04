; vsprite_test.s - hardware VSprites through the GEL system (implementation track, our own test program).
; Opens a lores 320 x 200 screen of 2 planes, sets up a GelsInfo (sprRsrvd = $FC: sprites 2-7 for the VSprites) and
; adds six VSprites of 16 x 12: three side by side at Y = 30 (red, green, blue frames) and three more at Y = 60
; (yellow, cyan, magenta), which must reuse the same hardware sprites. Each frame: SortGList, DrawGList, MrgCop and
; LoadView of ViewAddress() (the RKM sequence), WaitTOF. The six move right by one pixel per frame for 120 frames,
; then "VSPRITE DONE" is written and the screen stays 10 minutes.
; Build: vasmm68k_mot -Fhunkexe -kick1hunks -o vsprite_test tests/vsprite_test.s

        section code,code

NVS     EQU 6
VS_SIZE EQU 60
start:
        move.l  ($4).w,a6
        lea     intname(pc),a1
        moveq   #0,d0
        jsr     -552(a6)             ; OpenLibrary
        move.l  d0,a5                ; a5 = IntuitionBase
        lea     gfxname(pc),a1
        moveq   #0,d0
        jsr     -552(a6)
        move.l  d0,a4                ; a4 = GfxBase
        lea     dosname(pc),a1
        moveq   #0,d0
        jsr     -552(a6)
        move.l  d0,a3                ; a3 = DOSBase
        move.l  a5,a6
        lea     newscr(pc),a0
        jsr     -198(a6)             ; OpenScreen
        tst.l   d0
        beq     fail
        lea     savescr(pc),a0
        move.l  d0,(a0)
        ; GelsInfo + nextLine/lastColor arrays + head/tail + six VSprites, public memory
        move.l  ($4).w,a6
        move.l  #MEMSIZE,d0
        move.l  #$10001,d1
        jsr     -198(a6)             ; AllocMem
        tst.l   d0
        beq     fail
        move.l  d0,d7                ; d7 = block, GelsInfo first
        move.l  d0,a2
        move.b  #$FC,(a2)            ; sprRsrvd: the sprites the VSprites may use
        lea     O_NEXTL(a2),a1
        move.l  a1,10(a2)            ; nextLine
        lea     O_LASTC(a2),a1
        move.l  a1,14(a2)            ; lastColor
        move.l  a4,a6
        lea     O_HEAD(a2),a0
        lea     O_TAIL(a2),a1
        jsr     -120(a6)             ; InitGels(head, tail, GelsInfo)
        move.l  savescr(pc),a0
        move.l  d7,84+20(a0)         ; Screen.RastPort.GelsInfo
        moveq   #0,d6                ; d6 = VSprite index
.add:
        move.l  d7,a0
        lea     O_VS(a0),a0
        move.w  d6,d0
        mulu    #VS_SIZE,d0
        add.l   d0,a0                ; a0 = VSprite
        move.w  #$0001,20(a0)        ; Flags = VSPRITE
        move.w  d6,d0
        cmp.w   #3,d0
        blo.s   .row1
        subq.w  #3,d0
        move.w  #60,22(a0)           ; Y
        bra.s   .xpos
.row1:
        move.w  #30,22(a0)
.xpos:
        mulu    #40,d0
        add.w   #20,d0
        move.w  d0,24(a0)            ; X
        move.w  #12,26(a0)           ; Height
        move.w  #1,28(a0)            ; Width (words)
        move.w  #2,30(a0)            ; Depth
        lea     image,a1
        move.l  a1,36(a0)            ; ImageData
        move.w  d6,d0
        mulu    #6,d0
        lea     colours(pc),a1
        add.l   d0,a1
        move.l  a1,48(a0)            ; SprColors
        move.l  savescr(pc),a1
        lea     84(a1),a1            ; RastPort
        move.l  a4,a6
        jsr     -102(a6)             ; AddVSprite(vs, rp)
        addq.w  #1,d6
        cmp.w   #NVS,d6
        blo.s   .add
        moveq   #120-1,d5            ; frames
.frame:
        bsr     show
        move.l  d7,a0                ; every VSprite one pixel right
        lea     O_VS(a0),a0
        moveq   #NVS-1,d6
.mv:
        addq.w  #1,24(a0)
        lea     VS_SIZE(a0),a0
        dbra    d6,.mv
        dbra    d5,.frame
        bsr     show
        move.l  a3,a6
        jsr     -60(a6)              ; Output
        move.l  d0,d1
        lea     msg(pc),a0
        move.l  a0,d2
        moveq   #msglen,d3
        jsr     -48(a6)              ; Write
        move.l  #50*600,d1
        jsr     -198(a6)             ; Delay
        moveq   #0,d0
        rts
fail:
        moveq   #20,d0
        rts

; show: SortGList, DrawGList, MrgCop + LoadView of the intuition View, WaitTOF.
show:
        move.l  savescr(pc),a2
        move.l  a4,a6
        lea     84(a2),a1
        jsr     -150(a6)             ; SortGList(rp)
        lea     84(a2),a1
        lea     44(a2),a0
        jsr     -114(a6)             ; DrawGList(rp, vp)
        move.l  a5,a6
        jsr     -294(a6)             ; ViewAddress
        move.l  d0,-(sp)
        move.l  a4,a6
        move.l  d0,a1
        jsr     -210(a6)             ; MrgCop
        move.l  (sp)+,a1
        jsr     -222(a6)             ; LoadView
        jsr     -270(a6)             ; WaitTOF
        rts

O_NEXTL EQU 38                       ; GelsInfo is 38 bytes
O_LASTC EQU O_NEXTL+16
O_HEAD  EQU O_LASTC+32
O_TAIL  EQU O_HEAD+VS_SIZE
O_VS    EQU O_TAIL+VS_SIZE
MEMSIZE EQU O_VS+NVS*VS_SIZE

savescr: dc.l    0
newscr:
        dc.w    0,0,320,200,2
        dc.b    0,1
        dc.w    0
        dc.w    $000F                ; CUSTOMSCREEN
        dc.l    0,title,0,0
colours:                             ; SprColors of the six: colours 1, 2, 3 of the pair
        dc.w    $F00,$800,$FFF
        dc.w    $0F0,$080,$FFF
        dc.w    $00F,$008,$FFF
        dc.w    $FF0,$880,$FFF
        dc.w    $0FF,$088,$FFF
        dc.w    $F0F,$808,$FFF
intname: dc.b    "intuition.library",0
gfxname: dc.b    "graphics.library",0
dosname: dc.b    "dos.library",0
title:   dc.b    "VSPRITES",0
msg:     dc.b    "VSPRITE DONE",10
msglen  EQU *-msg
        even

        section image,data_c
image:                               ; 16 x 12: colour 1 frame, colour 2 inside, colour 3 centre
        dc.w    $FFFF,$0000
        dc.w    $FFFF,$0000
        dc.w    $C003,$3FFC
        dc.w    $C003,$3FFC
        dc.w    $C003,$3FFC
        dc.w    $C3C3,$3FFC
        dc.w    $C3C3,$3FFC
        dc.w    $C003,$3FFC
        dc.w    $C003,$3FFC
        dc.w    $C003,$3FFC
        dc.w    $FFFF,$0000
        dc.w    $FFFF,$0000
