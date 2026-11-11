; SPDX-License-Identifier: MIT
; Borderless windows retain explicitly requested titles/system gadgets and deliver close clicks.
; Authored input and pixel readback; no application or original-ROM artwork.
                include "exec.i"
                include "graphics.i"
                include "intuition.i"
                section code,code
_start:
        movem.l d2-d7/a2-a6,-(sp)
        move.w  #372,$dff032
        move.l  4.w,a6
        lea     gfxname(pc),a1
        moveq   #0,d0
        jsr     LVO_OPENLIBRARY(a6)
        move.l  d0,gfxbase
        beq     fail
        lea     intname(pc),a1
        moveq   #0,d0
        jsr     LVO_OPENLIBRARY(a6)
        move.l  d0,intbase
        beq     fail
open_screen:
        move.l  intbase(pc),a6
        lea     new_screen(pc),a0
        jsr     -198(a6)
        move.l  d0,a4
        tst.l   d0
        beq     fail
        move.l  a4,new_window+NW_SCREEN
        lea     modes(pc),a2
next_case:
        move.l  (a2)+,d7
        bmi     success
        move.l  d7,new_window+NW_FLAGS
        clr.l   new_window+NW_TITLE
        tst.l   d7
        beq.s   .open
        lea     title(pc),a0
        move.l  a0,new_window+NW_TITLE
.open:
        or.l    #BORDERLESS|ACTIVATE,new_window+NW_FLAGS
        move.l  intbase(pc),a6
        lea     new_window(pc),a0
        jsr     -204(a6)
        move.l  d0,a3
        tst.l   d0
        beq     fail
        move.w  #1,stage
        tst.b   WD_BORDERLEFT(a3)
        bne     fail
        tst.w   WD_BORDERRIGHT(a3) ; right and bottom remain zero
        bne     fail
        moveq   #0,d0
        tst.l   d7
        beq.s   .top
        move.l  SC_FONT(a4),a0
        move.w  ta_YSize(a0),d0
        addq.w  #1,d0
.top:
        cmp.b   WD_BORDERTOP(a3),d0
        bne     fail
        tst.l   d7
        beq     .close
        move.w  #2,stage
        ; The bar reaches the right edge, while pixels immediately below it stay background.
        move.l  gfxbase(pc),a6
        move.l  WD_RPORT(a3),a1
        moveq   #100,d0
        moveq   #2,d1
        jsr     -318(a6)
        cmp.l   #1,d0
        bne     fail
        moveq   #100,d0
        moveq   #15,d1
        move.l  WD_RPORT(a3),a1
        jsr     -318(a6)
        tst.l   d0
        bne     fail
        ; Both title and gadget contain foreground and background pixels, not an empty filled strip.
        clr.l   colours
        move.w  #3,stage
        moveq   #0,d4
        moveq   #13,d6
        bsr     pixels
        btst    #1,colours+3       ; system images use fixed pens, including pen 2
        beq     fail
        cmp.l   #2,colours
        beq     fail
        clr.l   colours
        move.w  #4,stage
        moveq   #16,d4
        moveq   #79,d6
        bsr     pixels
        cmp.l   #3,colours
        bne     fail
        move.l  intbase(pc),a6
        move.w  #5,stage
        move.l  a3,a0
        jsr     -456(a6)           ; RefreshWindowFrame must draw the same explicit decorations
        move.l  gfxbase(pc),a6
        clr.l   colours
        moveq   #16,d4
        moveq   #79,d6
        bsr     pixels
        cmp.l   #3,colours
        bne     fail
        btst    #8,d7
        beq.s   .close
        move.w  #4,click_y
        bsr     click_close
        move.w  #9,click_y         ; last gadget row is clickable even when BorderTop is only nine
        bsr     click_close
.close:
        move.l  intbase(pc),a6
        move.l  a3,a0
        jsr     -72(a6)
        bra     next_case
pixels:
        moveq   #1,d5
.row:
        move.w  d4,d2
.pixel:
        move.l  WD_RPORT(a3),a1
        move.w  d2,d0
        move.w  d5,d1
        jsr     -318(a6)
        cmp.l   #3,d0
        bhi     fail
        move.l  colours(pc),d1
        bset    d0,d1
        move.l  d1,colours
        addq.w  #1,d2
        cmp.w   d6,d2
        ble.s   .pixel
        addq.w  #1,d5
        cmp.w   #7,d5
        ble.s   .row
        rts
click_close:
        move.w  #6,stage
        move.l  intbase(pc),a6
        lea     prefs(pc),a0
        move.l  #PF_SIZE,d0
        jsr     -132(a6)
        move.l  WD_USERPORT(a3),io+MN_REPLYPORT
        move.b  #NT_MESSAGE,io+LN_TYPE
        move.w  #48,io+MN_LENGTH
        move.l  4.w,a6
        lea     inputname(pc),a0
        moveq   #0,d0
        moveq   #0,d1
        lea     io(pc),a1
        jsr     LVO_OPENDEVICE(a6)
        tst.l   d0
        bne     fail
        move.b  #IECLASS_RAWMOUSE,event+IE_CLASS
        move.w  #IECODE_NOBUTTON,event+IE_CODE
        move.w  #$8000,event+IE_QUALIFIER
        move.w  #-32000,event+IE_X
        move.w  #-32000,event+IE_Y
        bsr     inject
        moveq   #10,d0             ; close gadget at screen X=5, twice the mouse delta per pixel
        muls    prefs+PF_PTRTICKS,d0
        move.w  d0,event+IE_X
        moveq   #0,d0
        move.w  WD_TOPEDGE(a3),d0
        add.w   click_y(pc),d0
        add.w   d0,d0
        muls    prefs+PF_PTRTICKS,d0
        move.w  d0,event+IE_Y
        bsr     inject
        move.w  #7,stage
        cmp.w   #5,WD_MOUSEX(a3)
        bne     fail
        move.w  click_y(pc),d0
        cmp.w   WD_MOUSEY(a3),d0
        bne     fail
        move.w  #8,stage
        clr.l   event+IE_X
        move.w  #IECODE_LBUTTON,event+IE_CODE
        move.w  #$c000,event+IE_QUALIFIER
        bsr     inject
        clr.l   event+IE_X
        move.w  #IECODE_LBUTTON|$80,event+IE_CODE
        move.w  #$8000,event+IE_QUALIFIER
        bsr     inject
        move.l  4.w,a6
        lea     io(pc),a1
        jsr     LVO_CLOSEDEVICE(a6)
        clr.w   closes
.drain:
        move.l  WD_USERPORT(a3),a0
        jsr     LVO_GETMSG(a6)
        tst.l   d0
        beq.s   .done
        move.l  d0,a1
        cmp.l   #CLOSEWINDOW,IM_CLASS(a1)
        bne.s   .reply
        addq.w  #1,closes
.reply:
        jsr     LVO_REPLYMSG(a6)
        bra.s   .drain
.done:
        cmp.w   #1,closes
        bne     fail
        rts
inject:
        move.w  #IND_WRITEEVENT,io+IO_COMMAND
        move.l  #IE_SIZEOF,io+36
        lea     event(pc),a0
        move.l  a0,io+40
        lea     io(pc),a1
        move.l  4.w,a6
        jsr     LVO_DOIO(a6)
        move.l  gfxbase(pc),a6
        jsr     LVO_WAITTOF(a6)
        jsr     LVO_WAITTOF(a6)
        jmp     LVO_WAITTOF(a6)
success:
        move.l  intbase(pc),a6
        move.l  a4,a0
        jsr     -66(a6)
        tst.w   screen_case
        bne.s   .complete
        addq.w  #1,screen_case
        lea     attr8(pc),a0
        move.l  a0,new_screen+NS_FONT
        bra     open_screen       ; repeat with a font smaller than the ten-line system gadgets
.complete:
        move.l  4.w,a6
        move.l  intbase(pc),a1
        jsr     LVO_CLOSELIBRARY(a6)
        move.l  gfxbase(pc),a1
        jsr     LVO_CLOSELIBRARY(a6)
        lea     ok(pc),a0
        bsr.s   puts
        movem.l (sp)+,d2-d7/a2-a6
        moveq   #0,d0
        rts
fail:
        moveq   #'0',d0
        add.w   stage(pc),d0
        move.b  d0,error_stage
        lea     error(pc),a0
        bsr.s   puts
.stop:  bra.s   .stop
puts:
        moveq   #0,d0
        move.b  (a0)+,d0
        beq.s   .ret
.wait:  btst    #5,$dff018
        beq.s   .wait
        or.w    #256,d0
        move.w  d0,$dff030
        bra.s   puts
.ret:   rts
new_screen:
        dc.w    0,0,320,200,2
        dc.b    0,1
        dc.w    0,CUSTOMSCREEN
        dc.l    0,0,0,0
new_window:
        dc.w    0,30,120,120
        dc.b    0,1
        dc.l    CLOSEWINDOW,0,0,0,0,0,0
        dc.w    0,0,0,0,CUSTOMSCREEN
modes:  dc.l    0,WINDOWCLOSE,WINDOWCLOSE|BACKDROP,$80000000
title:  dc.b    "Test bar",0
fontname: dc.b  "topaz.font",0
        even
attr8:  dc.l    fontname
        dc.w    8
        dc.b    0,0
gfxname: dc.b   "graphics.library",0
intname: dc.b   "intuition.library",0
inputname: dc.b "input.device",0
ok:     dc.b    "BORDERLESS OK",10,"BORDERLESS END",10,0
error:  dc.b    "BORDERLESS FAIL stage "
error_stage: dc.b "0",10,"BORDERLESS END",10,0
        even
gfxbase: dc.l   0
intbase: dc.l   0
colours: dc.l   0
closes: dc.w    0
stage:  dc.w    0
click_y: dc.w   0
screen_case: dc.w 0
io:     dcb.b   48,0
event:  dcb.b   IE_SIZEOF,0
prefs:  dcb.b   PF_SIZE,0
