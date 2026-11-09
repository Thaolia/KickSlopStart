; SPDX-License-Identifier: MIT
; Polling Screen/Window mouse coordinates must work without requesting MOUSEMOVE messages.
; Public input.device events trace a held-button rectangle across active and inactive windows.
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
        beq     close_gfx
        move.l  d0,a6
        lea     new_screen(pc),a0
        jsr     -198(a6)
        move.l  d0,a4
        tst.l   d0
        beq     close_int
        move.l  a4,background+NW_SCREEN
        lea     background(pc),a0
        jsr     -204(a6)
        move.l  d0,other
        beq     close_screen
        move.l  a4,foreground+NW_SCREEN
        lea     foreground(pc),a0
        jsr     -204(a6)
        move.l  d0,a3
        tst.l   d0
        beq     close_other
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
        bne     close_window
        move.b  #IECLASS_RAWMOUSE,event+IE_CLASS
        move.w  #IECODE_NOBUTTON,event+IE_CODE
        move.w  #$8000,event+IE_QUALIFIER
        move.w  #-32000,event+IE_X
        move.w  #-32000,event+IE_Y
        bsr     inject
        clr.l   mouse_x
        moveq   #0,d7
next_case:
        move.l  intbase(pc),a6
        move.l  a3,a0
        moveq   #0,d0
        btst    #0,d7
        beq.s   .report
        moveq   #1,d0
.report:
        jsr     -234(a6)          ; ReportMouse
        move.l  a3,a0
        moveq   #MOUSEBUTTONS,d0
        btst    #1,d7
        beq.s   .idcmp
        or.l    #MOUSEMOVE,d0
.idcmp:
        jsr     -150(a6)          ; ModifyIDCMP
        moveq   #72,d4
        moveq   #60,d5
        bsr     position
        bsr     drain
        clr.w   moves
        clr.w   downs
        clr.w   ups
        move.w  #IECODE_LBUTTON,event+IE_CODE
        move.w  #$c000,event+IE_QUALIFIER
        clr.l   event+IE_X
        bsr     inject
        bsr     drain
        lea     points(pc),a2
        moveq   #3,d6
.point:
        move.w  (a2)+,d4
        move.w  (a2)+,d5
        bsr     position
        bsr     check_position
        bsr     drain
        dbra    d6,.point
        move.w  #IECODE_LBUTTON|$80,event+IE_CODE
        move.w  #$8000,event+IE_QUALIFIER
        clr.l   event+IE_X
        bsr     inject
        bsr     drain
        cmp.w   #1,downs
        bne.s   .bad
        cmp.w   #1,ups
        bne.s   .bad
        cmp.w   #3,d7
        beq.s   .wanted
        tst.w   moves
        beq.s   .next
        bra.s   .bad
.wanted:
        tst.w   moves
        bne.s   .next
.bad:
        st      bad
.next:
        addq.w  #1,d7
        cmp.w   #4,d7
        blo     next_case
        move.l  4.w,a6
        lea     io(pc),a1
        jsr     LVO_CLOSEDEVICE(a6)
        st      complete
close_window:
        move.l  intbase(pc),a6
        move.l  a3,a0
        jsr     -72(a6)
close_other:
        move.l  intbase(pc),a6
        move.l  other(pc),a0
        jsr     -72(a6)
close_screen:
        move.l  intbase(pc),a6
        move.l  a4,a0
        jsr     -66(a6)
close_int:
        move.l  4.w,a6
        move.l  intbase(pc),a1
        jsr     LVO_CLOSELIBRARY(a6)
close_gfx:
        move.l  4.w,a6
        move.l  gfxbase(pc),a1
        jsr     LVO_CLOSELIBRARY(a6)
        tst.b   complete
        beq.s   fail
        tst.b   bad
        bne.s   fail
        lea     ok(pc),a0
        bsr     puts
        movem.l (sp)+,d2-d7/a2-a6
        moveq   #0,d0
        rts
fail:
        lea     error(pc),a0
        bsr     puts
        movem.l (sp)+,d2-d7/a2-a6
        moveq   #20,d0
        rts
position:
        move.w  #IECODE_NOBUTTON,event+IE_CODE
        move.w  d4,d0
        sub.w   mouse_x(pc),d0
        move.w  d4,mouse_x
        add.w   d0,d0
        muls    prefs+PF_PTRTICKS,d0
        move.w  d0,event+IE_X
        move.w  d5,d0
        sub.w   mouse_y(pc),d0
        move.w  d5,mouse_y
        add.w   d0,d0
        muls    prefs+PF_PTRTICKS,d0
        move.w  d0,event+IE_Y
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
check_position:
        cmp.w   SC_MOUSEX(a4),d4
        bne.s   .bad
        cmp.w   SC_MOUSEY(a4),d5
        bne.s   .bad
        move.w  d4,d0
        sub.w   WD_LEFTEDGE(a3),d0
        cmp.w   WD_MOUSEX(a3),d0
        bne.s   .bad
        cmp.w   WD_GZZMOUSEX(a3),d0
        bne.s   .bad
        move.w  d5,d0
        sub.w   WD_TOPEDGE(a3),d0
        cmp.w   WD_MOUSEY(a3),d0
        bne.s   .bad
        cmp.w   WD_GZZMOUSEY(a3),d0
        bne.s   .bad
        move.l  other(pc),a0
        move.w  d4,d0
        sub.w   WD_LEFTEDGE(a0),d0
        cmp.w   WD_MOUSEX(a0),d0
        bne.s   .bad
        move.w  d5,d0
        sub.w   WD_TOPEDGE(a0),d0
        cmp.w   WD_MOUSEY(a0),d0
        beq.s   .ret
.bad:
        st      bad
.ret:   rts
drain:
        move.l  4.w,a6
.next:
        move.l  WD_USERPORT(a3),a0
        jsr     LVO_GETMSG(a6)
        tst.l   d0
        beq.s   .ret
        move.l  d0,a1
        cmp.l   #MOUSEMOVE,IM_CLASS(a1)
        bne.s   .button
        addq.w  #1,moves
.button:
        cmp.l   #MOUSEBUTTONS,IM_CLASS(a1)
        bne.s   .reply
        cmp.w   #IECODE_LBUTTON,IM_CODE(a1)
        bne.s   .up
        addq.w  #1,downs
.up:
        cmp.w   #IECODE_LBUTTON|$80,IM_CODE(a1)
        bne.s   .reply
        addq.w  #1,ups
.reply:
        jsr     LVO_REPLYMSG(a6)
        bra.s   .next
.ret:   rts
puts:
        moveq   #0,d0
        move.b  (a0)+,d0
        beq.s   .ret
.wait:
        btst    #5,$dff018
        beq.s   .wait
        or.w    #256,d0
        move.w  d0,$dff030
        bra.s   puts
.ret:   rts
new_screen:
        dc.w    0,0,320,200,1
        dc.b    0,1
        dc.w    0,CUSTOMSCREEN
        dc.l    0,0,0,0
background:
        dc.w    260,160,40,24
        dc.b    0,1
        dc.l    0,BORDERLESS,0,0,0,0,0
        dc.w    0,0,0,0,CUSTOMSCREEN
foreground:
        dc.w    32,24,224,144
        dc.b    0,1
        dc.l    MOUSEBUTTONS,BORDERLESS|ACTIVATE,0,0,0,0,0
        dc.w    0,0,0,0,CUSTOMSCREEN
points: dc.w 112,60,112,92,72,92,72,60
gfxname: dc.b "graphics.library",0
intname: dc.b "intuition.library",0
inputname: dc.b "input.device",0
ok: dc.b "MOUSEPOLL OK",10,"MOUSEPOLL END",10,0
error: dc.b "MOUSEPOLL FAIL",10,"MOUSEPOLL END",10,0
        even
gfxbase: dc.l 0
intbase: dc.l 0
other: dc.l 0
mouse_x: dc.w 0
mouse_y: dc.w 0
moves: dc.w 0
downs: dc.w 0
ups: dc.w 0
io: dcb.b 48,0
event: dcb.b IE_SIZEOF,0
prefs: dcb.b PF_SIZE,0
bad: dc.b 0
complete: dc.b 0
