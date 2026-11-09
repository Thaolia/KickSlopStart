; SPDX-License-Identifier: MIT
; Native regression: an actual proportional-knob press/drag/release must preserve the client's drawing state.
; Public input.device injection drives Intuition; a reused template verifies replacement of old pixels.
                include "exec.i"
                include "graphics.i"
                include "intuition.i"
                section code,code
_start:
        movem.l d2-d7/a2-a6,-(sp)
        suba.l  a4,a4
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
        move.l  a4,new_window+NW_SCREEN
        lea     new_window(pc),a0
        jsr     -204(a6)
        move.l  d0,a3
        tst.l   d0
        beq     close_screen
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
        moveq   #64,d0
        move.l  #MEMF_CHIP,d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  d0,template
        beq     close_input
        move.l  gfxbase(pc),a6
        move.l  WD_RPORT(a3),a1
        moveq   #3,d0
        jsr     LVO_SETAPEN(a6)
        moveq   #4,d0
        jsr     LVO_SETBPEN(a6)
        moveq   #JAM2,d0
        jsr     LVO_SETDRMD(a6)
        move.l  40(a1),saved_mt
        move.l  44(a1),saved_mt+4
        move.b  #$f0,d0
        bsr     draw_template
        move.l  intbase(pc),a6
        lea     prefs(pc),a0
        move.l  #PF_SIZE,d0
        jsr     -132(a6)           ; GetPrefs: raw mouse counts follow PointerTicks
        move.b  #IECLASS_RAWMOUSE,event+IE_CLASS
        move.w  #IECODE_NOBUTTON,event+IE_CODE
        move.w  #$8000,event+IE_QUALIFIER
        move.w  #-32000,event+IE_X
        move.w  #-32000,event+IE_Y
        bsr     inject             ; clamp the pointer to the top-left before positioning it
        moveq   #70,d0
        muls    prefs+PF_PTRTICKS,d0
        move.w  d0,event+IE_X
        moveq   #110,d0
        muls    prefs+PF_PTRTICKS,d0
        move.w  d0,event+IE_Y       ; hires x70, non-interlaced y55
        bsr     inject
        move.b  #IECLASS_RAWMOUSE,event+IE_CLASS
        move.w  #IECODE_LBUTTON,event+IE_CODE
        move.w  #$8000,event+IE_QUALIFIER
        clr.l   event+IE_X
        bsr     inject
        move.l  #GADGETDOWN,d0
        bsr     wait_event
        tst.l   d0
        beq     free_template
        lea     down_marker(pc),a0
        bsr     puts
        bsr     check_state
        move.w  #IECODE_NOBUTTON,event+IE_CODE
        moveq   #40,d0
        muls    prefs+PF_PTRTICKS,d0
        move.w  d0,event+IE_X
        clr.w   event+IE_Y
        bsr     inject
        move.b  #IECLASS_RAWMOUSE,event+IE_CLASS
        move.w  #IECODE_LBUTTON|$80,event+IE_CODE
        move.w  #$8000,event+IE_QUALIFIER
        clr.l   event+IE_X
        bsr     inject
        move.l  #GADGETUP,d0
        bsr     wait_event
        tst.l   d0
        beq     free_template
        lea     up_marker(pc),a0
        bsr     puts
        bsr     check_state
        move.l  gfxbase(pc),a6
        move.l  WD_RPORT(a3),a1
        moveq   #3,d0
        jsr     LVO_SETAPEN(a6)
        moveq   #4,d0
        jsr     LVO_SETBPEN(a6)     ; like a caller that resets its pens but relies on the existing drawing mode
        move.b  #$0f,d0
        bsr     draw_template
        moveq   #0,d5
.row:
        moveq   #0,d4
.pixel:
        moveq   #4,d7
        move.w  d4,d0
        and.w   #7,d0
        cmp.w   #4,d0
        blo.s   .pen
        moveq   #3,d7
.pen:
        move.w  d4,d0
        add.w   #20,d0
        move.w  d5,d1
        add.w   #50,d1
        move.l  WD_RPORT(a3),a1
        jsr     -318(a6)
        cmp.l   d7,d0
        beq.s   .next
        st      bad
.next:
        addq.w  #1,d4
        cmp.w   #64,d4
        blo.s   .pixel
        addq.w  #1,d5
        cmp.w   #8,d5
        blo.s   .row
        st      complete
free_template:
        move.l  4.w,a6
        move.l  template(pc),a1
        moveq   #64,d0
        jsr     LVO_FREEMEM(a6)
close_input:
        move.l  4.w,a6
        lea     io(pc),a1
        jsr     LVO_CLOSEDEVICE(a6)
close_window:
        move.l  intbase(pc),a6
        move.l  a3,a0
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
check_state:
        move.l  WD_RPORT(a3),a0
        cmp.b   #3,rp_FgPen(a0)
        bne.s   .bad
        cmp.b   #4,rp_BgPen(a0)
        bne.s   .bad
        cmp.b   #JAM2,rp_DrawMode(a0)
        bne.s   .bad
        move.l  40(a0),d0
        cmp.l   saved_mt(pc),d0
        bne.s   .bad
        move.l  44(a0),d0
        cmp.l   saved_mt+4(pc),d0
        beq.s   .ret
.bad:   st      bad
.ret:   rts
draw_template:
        move.l  gfxbase(pc),a6
        jsr     -228(a6)           ; the source is reused only after pending DMA finishes
        move.l  template(pc),a0
        moveq   #63,d1
.fill:  move.b  d0,(a0)+
        dbra    d1,.fill
        move.l  template(pc),a0
        moveq   #0,d0
        moveq   #8,d1
        moveq   #20,d2
        moveq   #50,d3
        moveq   #64,d4
        moveq   #8,d5
        move.l  WD_RPORT(a3),a1
        jsr     -36(a6)
        jmp     -228(a6)
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
wait_event:
        movem.l d2-d4/a6,-(sp)
        move.l  d0,d2
        moveq   #100,d3
.poll:
        move.l  4.w,a6
        move.l  WD_USERPORT(a3),a0
        jsr     LVO_GETMSG(a6)
        tst.l   d0
        beq.s   .tick
        move.l  d0,a1
        move.l  IM_CLASS(a1),d4
        jsr     LVO_REPLYMSG(a6)
        cmp.l   d2,d4
        beq.s   .yes
        bra.s   .poll
.tick:
        move.l  gfxbase(pc),a6
        jsr     LVO_WAITTOF(a6)
        dbra    d3,.poll
        moveq   #0,d0
        bra.s   .ret
.yes:   moveq   #1,d0
.ret:   movem.l (sp)+,d2-d4/a6
        rts
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
        dc.w    0,0,640,200,3
        dc.b    0,1
        dc.w    $8000,CUSTOMSCREEN
        dc.l    0,0,0,0
new_window:
        dc.w    40,30,200,80
        dc.b    0,1
        dc.l    GADGETDOWN|GADGETUP,BORDERLESS|ACTIVATE,gadget,0,0,0,0
        dc.w    0,0,0,0,CUSTOMSCREEN
gadget:
        dc.l    0
        dc.w    20,20,128,12,4,GADGIMMEDIATE|RELVERIFY,PROPGADGET
        dc.l    image,0,0,0,propinfo
        dc.w    1
        dc.l    0
propinfo:
        dc.w    AUTOKNOB|FREEHORIZ,0,0,$8000,$ffff,0,0,0,0,0,0
image:  dcb.b 20,0
gfxname: dc.b "graphics.library",0
intname: dc.b "intuition.library",0
inputname: dc.b "input.device",0
down_marker: dc.b "PROPSTATE DOWN",10,0
up_marker: dc.b "PROPSTATE UP",10,0
ok:     dc.b "PROPSTATE OK",10,"PROPSTATE END",10,0
error:  dc.b "PROPSTATE FAIL",10,"PROPSTATE END",10,0
        even
gfxbase: dc.l 0
intbase: dc.l 0
template: dc.l 0
saved_mt: dc.l 0,0
io:     dcb.b 48,0
event:  dcb.b IE_SIZEOF,0
prefs:  dcb.b PF_SIZE,0
bad:    dc.b 0
complete: dc.b 0
