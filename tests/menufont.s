; SPDX-License-Identifier: MIT
; Native menu-font regression: authored six-pixel solid glyphs distinguish screen and global fonts.
; Raw input opens the menu bar, item box and submenu; each must render at the screen font's width.
; Disabled gadget/menu stipples must use their BlockPen and preserve client drawing state.
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
        move.l  gfxbase(pc),a6
        lea     font(pc),a1
        jsr     -480(a6)           ; AddFont of the entirely authored test font
        move.l  intbase(pc),a6
        lea     new_screen(pc),a0
        jsr     -198(a6)
        move.l  d0,a4
        tst.l   d0
        beq     remove_font
        move.l  a4,new_window+NW_SCREEN
        lea     new_window(pc),a0
        jsr     -204(a6)
        move.l  d0,a3
        tst.l   d0
        beq     close_screen
        bsr     check_gadget
        move.l  intbase(pc),a6
        move.l  a3,a0
        lea     menu(pc),a1
        jsr     -264(a6)           ; SetMenuStrip
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
        moveq   #70,d0
        moveq   #60,d1
        bsr     position
        move.w  #IECODE_RBUTTON,event+IE_CODE
        clr.l   event+IE_X
        bsr     inject
        moveq   #36,d6             ; six authored glyphs, six pixels wide, eight rows high
        moveq   #0,d5
        moveq   #9,d7
        bsr     count_runs
        bsr     bar_pixels
        move.w  d3,enabled_pixels
        lea     bar_marker(pc),a0
        bsr     puts
        moveq   #10,d0
        moveq   #5,d1
        bsr     position
        moveq   #36,d6
        moveq   #10,d5
        moveq   #79,d7
        bsr     count_runs
        lea     item_marker(pc),a0
        bsr     puts
        moveq   #10,d0
        moveq   #16,d1
        bsr     position
        moveq   #24,d6             ; four authored glyphs in the submenu
        move.w  #40,scan_left      ; exclude the parent text while checking the child glyph block
        moveq   #10,d5
        moveq   #79,d7
        bsr     count_runs
        lea     sub_marker(pc),a0
        bsr     puts
        move.w  #IECODE_RBUTTON|$80,event+IE_CODE
        clr.l   event+IE_X
        bsr     inject
        move.l  intbase(pc),a6
        move.l  a3,a0
        move.l  #$ffe0,d0         ; menu 0, NOITEM, NOSUB
        jsr     -180(a6)          ; OffMenu
        moveq   #70,d0
        moveq   #60,d1
        bsr     position
        move.w  #IECODE_RBUTTON,event+IE_CODE
        clr.l   event+IE_X
        bsr     inject
        bsr     bar_pixels
        add.w   #72,d3            ; one quarter of the 36 x 8 solid title is cleared by ghosting
        cmp.w   enabled_pixels(pc),d3
        beq.s   .ghost_ok
        st      bad
.ghost_ok:
        move.w  #IECODE_RBUTTON|$80,event+IE_CODE
        clr.l   event+IE_X
        bsr     inject
        lea     io(pc),a1
        move.l  4.w,a6
        jsr     LVO_CLOSEDEVICE(a6)
        st      complete
close_window:
        move.l  intbase(pc),a6
        move.l  a3,a0
        jsr     -54(a6)            ; ClearMenuStrip
        move.l  a3,a0
        jsr     -72(a6)
close_screen:
        move.l  intbase(pc),a6
        move.l  a4,a0
        jsr     -66(a6)
remove_font:
        move.l  gfxbase(pc),a6
        lea     font(pc),a1
        jsr     -486(a6)
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
check_gadget:
        move.l  gfxbase(pc),a6
        move.l  WD_RPORT(a3),a1
        moveq   #2,d0
        jsr     LVO_SETAPEN(a6)
        moveq   #19,d0
        moveq   #19,d1
        moveq   #36,d2
        moveq   #28,d3
        jsr     LVO_RECTFILL(a6)
        move.l  WD_RPORT(a3),a0
        move.l  rp_minterms(a0),saved_mt
        move.l  rp_minterms+4(a0),saved_mt+4
        move.l  intbase(pc),a6
        lea     gadget(pc),a0
        move.l  a3,a1
        suba.l  a2,a2
        jsr     -174(a6)          ; OffGadget
        move.l  gfxbase(pc),a6
        jsr     -228(a6)
        moveq   #0,d6
        moveq   #19,d5
.row:
        moveq   #19,d4
.pixel:
        move.w  d4,d0
        move.w  d5,d1
        move.l  WD_RPORT(a3),a1
        jsr     -318(a6)
        cmp.l   #2,d0
        beq.s   .kept
        tst.l   d0
        bne.s   .bad
        cmp.w   #20,d4
        blo.s   .bad
        cmp.w   #35,d4
        bhi.s   .bad
        cmp.w   #20,d5
        blo.s   .bad
        cmp.w   #27,d5
        bls.s   .next
.bad:
        st      bad
        bra.s   .next
.kept:
        addq.w  #1,d6
.next:
        addq.w  #1,d4
        cmp.w   #36,d4
        ble.s   .pixel
        addq.w  #1,d5
        cmp.w   #28,d5
        ble.s   .row
        cmp.w   #148,d6
        bne.s   .state_bad
        move.l  WD_RPORT(a3),a0
        cmp.b   #2,rp_FgPen(a0)
        bne.s   .state_bad
        tst.b   rp_BgPen(a0)
        bne.s   .state_bad
        cmp.b   #JAM2,rp_DrawMode(a0)
        bne.s   .state_bad
        move.l  saved_mt(pc),d0
        cmp.l   rp_minterms(a0),d0
        bne.s   .state_bad
        move.l  saved_mt+4(pc),d0
        cmp.l   rp_minterms+4(a0),d0
        beq.s   .ret
.state_bad:
        st      bad
.ret:   rts
bar_pixels:
        move.l  gfxbase(pc),a6
        jsr     -228(a6)
        moveq   #0,d3
        moveq   #0,d5
.row:
        moveq   #0,d4
.pixel:
        move.w  d4,d0
        move.w  d5,d1
        lea     SC_RASTPORT(a4),a1
        jsr     -318(a6)
        cmp.l   #1,d0
        bne.s   .next
        addq.w  #1,d3
.next:
        addq.w  #1,d4
        cmp.w   #100,d4
        blo.s   .pixel
        addq.w  #1,d5
        cmp.w   #10,d5
        blo.s   .row
        rts
; Count solid runs from the authored glyphs, independent of the menu box's precise frame position.
count_runs:
        move.l  gfxbase(pc),a6
        jsr     -228(a6)
        moveq   #0,d3
.row:
        moveq   #0,d2
        move.w  scan_left(pc),d4
.pixel:
        move.w  d4,d0
        move.w  d5,d1
        lea     SC_RASTPORT(a4),a1
        jsr     -318(a6)
        cmp.l   #1,d0
        bne.s   .end_run
        addq.w  #1,d2
        bra.s   .next
.end_run:
        cmp.w   d6,d2
        blo.s   .reset
        addq.w  #1,d3
.reset: moveq   #0,d2
.next:
        addq.w  #1,d4
        cmp.w   #160,d4
        blo.s   .pixel
        addq.w  #1,d5
        cmp.w   d7,d5
        ble.s   .row
        cmp.w   #8,d3
        bhs.s   .ret
        st      bad
.ret:   rts
; Position in hires pixels/non-interlaced lines, using public raw mouse counts and Preferences.
position:
        move.w  d0,d2
        sub.w   mouse_x(pc),d0
        move.w  d2,mouse_x
        muls    prefs+PF_PTRTICKS,d0
        move.w  d0,event+IE_X
        move.w  d1,d2
        sub.w   mouse_y(pc),d1
        move.w  d2,mouse_y
        add.w   d1,d1
        muls    prefs+PF_PTRTICKS,d1
        move.w  d1,event+IE_Y
        move.w  #IECODE_NOBUTTON,event+IE_CODE
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
puts:
        moveq   #0,d0
        move.b  (a0)+,d0
        beq.s   .ret
.wait: btst    #5,$dff018
        beq.s   .wait
        or.w    #256,d0
        move.w  d0,$dff030
        bra.s   puts
.ret:  rts
new_screen:
        dc.w    0,0,640,200,2
        dc.b    1,0
        dc.w    $8000,CUSTOMSCREEN
        dc.l    attr,0,0,0
new_window:
        dc.w    40,30,200,80
        dc.b    1,0
        dc.l    MENUPICK,BORDERLESS|ACTIVATE,gadget,0,0,0,0
        dc.w    0,0,0,0,CUSTOMSCREEN
gadget:
        dc.l    0
        dc.w    20,20,16,8,3,0,BOOLGADGET
        dc.l    0,0,0,0,0
        dc.w    1
        dc.l    0
menu:
        dc.l    0
        dc.w    0,0,64,10,MENUENABLED
        dc.l    six_a,parent
        dc.w    0,0,0,0
parent:
        dc.l    0
        dc.w    0,0,48,10,ITEMTEXT|ITEMENABLED|HIGHNONE
        dc.l    0,parent_text,0
        dc.b    0,0
        dc.l    child
        dc.w    $ffff
child:
        dc.l    0
        dc.w    40,0,40,10,ITEMTEXT|ITEMENABLED|HIGHNONE
        dc.l    0,child_text,0
        dc.b    0,0
        dc.l    0
        dc.w    $ffff
parent_text:
        dc.b    1,0,JAM2,0
        dc.w    0,0
        dc.l    0,six_a,0
child_text:
        dc.b    1,0,JAM2,0
        dc.w    0,0
        dc.l    0,four_a,0
font:
        dc.l    0,0
        dc.b    NT_FONT,0
        dc.l    fontname,0
        dc.w    tf_SIZEOF,8
        dc.b    0,FPF_DESIGNED
        dc.w    6,6,1,0
        dc.b    'A','A'
        dc.l    glyph
        dc.w    2
        dc.l    charloc,0,0
charloc: dc.l   6,6
glyph:  dcb.w   8,$fc00
attr:   dc.l    fontname
        dc.w    8
        dc.b    0,0
fontname: dc.b  "menutest.font",0
gfxname: dc.b   "graphics.library",0
intname: dc.b   "intuition.library",0
inputname: dc.b "input.device",0
six_a: dc.b    "AAAAAA",0
four_a: dc.b   "AAAA",0
bar_marker: dc.b "MENUFONT BAR",10,0
item_marker: dc.b "MENUFONT ITEM",10,0
sub_marker: dc.b "MENUFONT SUB",10,0
ok:     dc.b   "MENUFONT OK",10,"MENUFONT END",10,0
error:  dc.b   "MENUFONT FAIL",10,"MENUFONT END",10,0
        even
gfxbase: dc.l   0
intbase: dc.l   0
mouse_x: dc.w  0
mouse_y: dc.w  0
scan_left: dc.w 0
enabled_pixels: dc.w 0
saved_mt: dc.l 0,0
io:     dcb.b  48,0
event:  dcb.b  IE_SIZEOF,0
prefs:  dcb.b  PF_SIZE,0
bad:    dc.b   0
complete: dc.b 0
