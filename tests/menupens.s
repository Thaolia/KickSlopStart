; SPDX-License-Identifier: MIT
; Native menu-pen/proportional-font regression: window pens differ from the screen pens.
; Authored glyphs advance six pixels despite an eight-pixel nominal width; titles must remain complete.
; Raw input opens the bar, item and submenu; disabled rows must keep their window-colored background.
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
        clr.w   new_screen+NS_VIEWMODES
        move.w  #320,new_screen+NS_WIDTH
        lea     new_screen(pc),a0
        jsr     -198(a6)
        tst.l   d0
        beq     remove_font
        move.l  d0,a0
        cmp.b   #2,SC_BARHBORDER(a0)
        bne.s   .margins_bad
        cmp.b   #4,SC_MENUVBORDER(a0)
        beq.s   .margins_ok
.margins_bad:
        st      bad
.margins_ok:
        jsr     -66(a6)
        move.w  #$8000,new_screen+NS_VIEWMODES
        move.w  #640,new_screen+NS_WIDTH
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
        move.l  4.w,a6
        moveq   #MEMF_CHIP,d1
        jsr     LVO_AVAILMEM(a6)
        move.l  d0,chip_before_menu
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
        moveq   #48,d6
        moveq   #10,d5
        moveq   #79,d7
        bsr     count_runs
        bsr     check_frame
        cmp.w   #51,menu+MU_BEATX
        bhs.s   .bounds_ok
        st      bad
.bounds_ok:
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
        moveq   #85,d0
        moveq   #5,d1
        bsr     position
        move.l  gfxbase(pc),a6
        moveq   #10,d0
        moveq   #0,d1
        move.b  SC_BARHEIGHT(a4),d1
        subq.w  #1,d1
        lea     SC_RASTPORT(a4),a1
        jsr     -318(a6)
        cmp.l   #27,d0              ; closing the first box must preserve the overlapping bar row
        beq.s   .bar_restored
        st      bad
.bar_restored:
        move.w  #30,hover_pen
        bsr     check_hover
        moveq   #1,d7             ; repeated HIGHIMAGE text selection and restoration, with no ITextFont
.hover_cycle:
        moveq   #90,d0
        moveq   #16,d1
        bsr     position
        move.w  #1,hover_pen
        bsr     check_hover
        moveq   #85,d0
        moveq   #5,d1
        bsr     position
        move.w  #30,hover_pen
        bsr     check_hover
        dbra    d7,.hover_cycle
        bsr     benchmark_menu
        moveq   #85,d0
        moveq   #5,d1
        bsr     position
        move.l  #14000,perf_budget
        bsr     benchmark_menu
        moveq   #85,d0
        moveq   #5,d1
        bsr     position
        move.b  #1,perf_text+IT_FRONTPEN
        move.l  #20000,perf_budget
        bsr     benchmark_menu
        move.b  #30,perf_text+IT_FRONTPEN
        move.w  #265,d0
        moveq   #5,d1
        bsr     position
        bsr     check_ghostitem
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
        lea     ghost_error(pc),a0
        bsr     puts
.ghost_ok:
        move.w  #IECODE_RBUTTON|$80,event+IE_CODE
        clr.l   event+IE_X
        bsr     inject
        move.l  4.w,a6
        moveq   #MEMF_CHIP,d1
        jsr     LVO_AVAILMEM(a6)
        add.l   #4096,d0             ; allow unrelated screen/pointer housekeeping, not retained menu surfaces
        cmp.l   chip_before_menu(pc),d0
        bhs.s   .released_storage
        st      bad
.released_storage:
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
 ; The authored item is a solid 24x8 block. Its whole footprint must change to the brighter pen and
; return exactly, repeatedly; using the default font gives a different glyph shape and advance.
check_ghostitem:
        move.l  gfxbase(pc),a6
        moveq   #0,d2
        move.b  SC_BARHBORDER(a4),d2
        add.w   ghost_menu+MU_LEFTEDGE,d2
        moveq   #0,d3
        move.b  SC_BARHEIGHT(a4),d3
        subq.w  #1,d3
        moveq   #0,d0
        move.b  SC_MENUVBORDER(a4),d0
        add.w   d0,d3
        moveq   #0,d5
.row:
        moveq   #0,d4
.pixel:
        move.w  d2,d0
        add.w   d4,d0
        move.w  d3,d1
        add.w   d5,d1
        lea     SC_RASTPORT(a4),a1
        jsr     -318(a6)
        move.w  d0,d6
        moveq   #0,d0
        move.b  SC_MENUVBORDER(a4),d0
        add.w   d5,d0
        and.w   #1,d0
        add.w   d0,d0
        addq.w  #1,d0              ; $4444/$1111 erase absolute columns 1/3 modulo four
        move.w  d2,d1
        add.w   d4,d1
        and.w   #3,d1
        cmp.w   d1,d0
        bne.s   .kept
        moveq   #27,d0
        bra.s   .check
.kept:  moveq   #30,d0
.check:
        cmp.w   d0,d6
        beq.s   .next
        st      bad
.next:
        addq.w  #1,d4
        cmp.w   #24,d4
        blo.s   .pixel
        addq.w  #1,d5
        cmp.w   #8,d5
        blo.s   .row
        rts

benchmark_menu:
        move.l  4.w,a6
        lea     perf_server(pc),a1
        lea     perf_vblank(pc),a0
        move.l  a0,18(a1)
        moveq   #5,d0
        jsr     LVO_ADDINTSERVER(a6)
        bsr     perf_now
        move.l  d0,perf_start
        move.w  #170,d0
        moveq   #5,d1
        bsr     position
        bsr     perf_now
        sub.l   perf_start(pc),d0
        move.l  d0,perf_elapsed
        move.l  4.w,a6
        lea     perf_server(pc),a1
        moveq   #5,d0
        jsr     LVO_REMINTSERVER(a6)
        lea     perf_marker(pc),a0
        bsr     puts
        move.l  perf_elapsed(pc),d0
        bsr     perf_hex
        lea     perf_nl(pc),a0
        bsr     puts
        move.l  perf_budget(pc),d0
        cmp.l   perf_elapsed(pc),d0   ; first render and cached return have separate visible-latency bounds
        bhi.s   .time_ok
        st      bad
.time_ok:
        move.l  gfxbase(pc),a6
        moveq   #0,d4
        move.b  SC_BARHBORDER(a4),d4
        add.w   perf_menu+MU_LEFTEDGE,d4
        moveq   #0,d5
        move.b  SC_BARHEIGHT(a4),d5
        subq.w  #1,d5
        moveq   #0,d0
        move.b  SC_MENUVBORDER(a4),d0
        add.w   d0,d5
        moveq   #19,d7
.row:
        move.w  d4,d0
        move.w  d5,d1
        lea     SC_RASTPORT(a4),a1
        jsr     -318(a6)
        moveq   #0,d1
        move.b  perf_text+IT_FRONTPEN,d1
        cmp.w   d1,d0
        bne.s   .bad
        move.w  d4,d0
        add.w   #143,d0
        move.w  d5,d1
        lea     SC_RASTPORT(a4),a1
        jsr     -318(a6)
        moveq   #0,d1
        move.b  perf_text+IT_FRONTPEN,d1
        cmp.w   d1,d0
        beq.s   .next
.bad:   st      bad
.next:  addq.w  #8,d5
        dbra    d7,.row
        rts
perf_vblank:
        addq.l  #1,perf_frames
        moveq   #0,d0
        rts
perf_now:
        move.l  perf_frames(pc),d0
        move.l  $dff004,d1
        lsr.l   #8,d1
        and.l   #511,d1
        cmp.l   perf_frames(pc),d0
        bne.s   perf_now
        mulu    #313,d0
        add.l   d1,d0
        rts
perf_hex:
        movem.l d0-d3,-(sp)
        move.l  d0,d2
        moveq   #7,d1
        lea     perf_digits(pc),a0
.loop:  rol.l   #4,d2
        moveq   #15,d3
        and.l   d2,d3
        moveq   #0,d0
        move.b  0(a0,d3.w),d0
.wait:  btst    #5,$dff018
        beq.s   .wait
        or.w    #256,d0
        move.w  d0,$dff030
        dbra    d1,.loop
        movem.l (sp)+,d0-d3
        rts

check_hover:
        move.l  gfxbase(pc),a6
        moveq   #0,d2
        move.b  SC_BARHBORDER(a4),d2
        add.w   second_menu+MU_LEFTEDGE,d2
        moveq   #0,d3
        move.b  SC_BARHEIGHT(a4),d3
        subq.w  #1,d3
        moveq   #0,d0
        move.b  SC_MENUVBORDER(a4),d0
        add.w   d0,d3
        moveq   #0,d5
        clr.w   hover_bad
.row:
        moveq   #0,d4
.pixel:
        move.w  d2,d0
        add.w   d4,d0
        move.w  d3,d1
        add.w   d5,d1
        lea     SC_RASTPORT(a4),a1
        jsr     -318(a6)
        cmp.w   hover_pen(pc),d0
        beq.s   .next
        st      hover_bad
.next:
        addq.w  #1,d4
        cmp.w   #23,d4
        ble.s   .pixel
        addq.w  #1,d5
        cmp.w   #7,d5
        ble.s   .row
        tst.b   hover_bad
        beq.s   .ret
        st      bad
        lea     hover_error(pc),a0
        bsr     puts
.ret:   rts
check_frame:
        move.l  gfxbase(pc),a6
        moveq   #0,d4
        move.b  SC_BARHBORDER(a4),d4
        add.w   menu+MU_LEFTEDGE,d4
        add.w   menu+MU_JAZZX,d4
        bpl.s   .x_ok
        moveq   #0,d4
.x_ok:
        addq.w  #1,d4             ; inner column of the two-pixel left frame
        moveq   #0,d5
        move.b  SC_BARHEIGHT(a4),d5
        addq.w  #3,d5
        move.w  d4,d0
        move.w  d5,d1
        lea     SC_RASTPORT(a4),a1
        jsr     -318(a6)
        cmp.l   #30,d0
        beq.s   .ret
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
        cmp.l   #30,d0
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
        cmp.l   #30,d0
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
        lea     glyph_error(pc),a0
        bsr     puts
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
        dc.w    0,0,640,200,5
        dc.b    26,31
        dc.w    $8000,CUSTOMSCREEN
        dc.l    attr,0,0,0
new_window:
        dc.w    40,30,200,80
        dc.b    30,27
        dc.l    MENUPICK,BORDERLESS|ACTIVATE,gadget,0,0,0,0
        dc.w    0,0,0,0,CUSTOMSCREEN
gadget:
        dc.l    0
        dc.w    20,20,16,8,3,0,BOOLGADGET
        dc.l    0,0,0,0,0
        dc.w    1
        dc.l    0
menu:
        dc.l    second_menu
        dc.w    0,0,36,10,MENUENABLED
        dc.l    six_a,parent
        dc.w    0,0,0,0
parent:
        dc.l    0
        dc.w    0,0,24,10,ITEMTEXT|ITEMENABLED|HIGHNONE
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
        dc.b    30,27,JAM1,0
        dc.w    0,0
        dc.l    0,eight_a,0
child_text:
        dc.b    30,27,JAM1,0
        dc.w    0,0
        dc.l    0,four_a,0
second_menu:
        dc.l    perf_menu
        dc.w    80,0,36,10,MENUENABLED
        dc.l    four_a,second_item
        dc.w    0,0,0,0
second_item:
        dc.l    0
        dc.w    0,0,40,10,ITEMTEXT|ITEMENABLED ; HIGHIMAGE = 0
        dc.l    0,hover_normal,hover_selected
        dc.b    0,0
        dc.l    0
        dc.w    $ffff
hover_normal:
        dc.b    30,27,JAM2,0
        dc.w    0,0
        dc.l    0,four_a,0
hover_selected:
        dc.b    1,27,JAM2,0
        dc.w    0,0
        dc.l    0,four_a,0
perf_menu:
        dc.l ghost_menu
        dc.w 160,0,40,10,MENUENABLED
        dc.l four_a,perf_item_0
        dc.w 0,0,0,0
perf_item_0:
        dc.l perf_item_1
        dc.w 0,0,160,8,ITEMTEXT|ITEMENABLED|HIGHNONE
        dc.l 0,perf_text,0
        dc.b 0,0
        dc.l 0
        dc.w $ffff
perf_item_1:
        dc.l perf_item_2
        dc.w 0,8,160,8,ITEMTEXT|ITEMENABLED|HIGHNONE
        dc.l 0,perf_text,0
        dc.b 0,0
        dc.l 0
        dc.w $ffff
perf_item_2:
        dc.l perf_item_3
        dc.w 0,16,160,8,ITEMTEXT|ITEMENABLED|HIGHNONE
        dc.l 0,perf_text,0
        dc.b 0,0
        dc.l 0
        dc.w $ffff
perf_item_3:
        dc.l perf_item_4
        dc.w 0,24,160,8,ITEMTEXT|ITEMENABLED|HIGHNONE
        dc.l 0,perf_text,0
        dc.b 0,0
        dc.l 0
        dc.w $ffff
perf_item_4:
        dc.l perf_item_5
        dc.w 0,32,160,8,ITEMTEXT|ITEMENABLED|HIGHNONE
        dc.l 0,perf_text,0
        dc.b 0,0
        dc.l 0
        dc.w $ffff
perf_item_5:
        dc.l perf_item_6
        dc.w 0,40,160,8,ITEMTEXT|ITEMENABLED|HIGHNONE
        dc.l 0,perf_text,0
        dc.b 0,0
        dc.l 0
        dc.w $ffff
perf_item_6:
        dc.l perf_item_7
        dc.w 0,48,160,8,ITEMTEXT|ITEMENABLED|HIGHNONE
        dc.l 0,perf_text,0
        dc.b 0,0
        dc.l 0
        dc.w $ffff
perf_item_7:
        dc.l perf_item_8
        dc.w 0,56,160,8,ITEMTEXT|ITEMENABLED|HIGHNONE
        dc.l 0,perf_text,0
        dc.b 0,0
        dc.l 0
        dc.w $ffff
perf_item_8:
        dc.l perf_item_9
        dc.w 0,64,160,8,ITEMTEXT|ITEMENABLED|HIGHNONE
        dc.l 0,perf_text,0
        dc.b 0,0
        dc.l 0
        dc.w $ffff
perf_item_9:
        dc.l perf_item_10
        dc.w 0,72,160,8,ITEMTEXT|ITEMENABLED|HIGHNONE
        dc.l 0,perf_text,0
        dc.b 0,0
        dc.l 0
        dc.w $ffff
perf_item_10:
        dc.l perf_item_11
        dc.w 0,80,160,8,ITEMTEXT|ITEMENABLED|HIGHNONE
        dc.l 0,perf_text,0
        dc.b 0,0
        dc.l 0
        dc.w $ffff
perf_item_11:
        dc.l perf_item_12
        dc.w 0,88,160,8,ITEMTEXT|ITEMENABLED|HIGHNONE
        dc.l 0,perf_text,0
        dc.b 0,0
        dc.l 0
        dc.w $ffff
perf_item_12:
        dc.l perf_item_13
        dc.w 0,96,160,8,ITEMTEXT|ITEMENABLED|HIGHNONE
        dc.l 0,perf_text,0
        dc.b 0,0
        dc.l 0
        dc.w $ffff
perf_item_13:
        dc.l perf_item_14
        dc.w 0,104,160,8,ITEMTEXT|ITEMENABLED|HIGHNONE
        dc.l 0,perf_text,0
        dc.b 0,0
        dc.l 0
        dc.w $ffff
perf_item_14:
        dc.l perf_item_15
        dc.w 0,112,160,8,ITEMTEXT|ITEMENABLED|HIGHNONE
        dc.l 0,perf_text,0
        dc.b 0,0
        dc.l 0
        dc.w $ffff
perf_item_15:
        dc.l perf_item_16
        dc.w 0,120,160,8,ITEMTEXT|ITEMENABLED|HIGHNONE
        dc.l 0,perf_text,0
        dc.b 0,0
        dc.l 0
        dc.w $ffff
perf_item_16:
        dc.l perf_item_17
        dc.w 0,128,160,8,ITEMTEXT|ITEMENABLED|HIGHNONE
        dc.l 0,perf_text,0
        dc.b 0,0
        dc.l 0
        dc.w $ffff
perf_item_17:
        dc.l perf_item_18
        dc.w 0,136,160,8,ITEMTEXT|ITEMENABLED|HIGHNONE
        dc.l 0,perf_text,0
        dc.b 0,0
        dc.l 0
        dc.w $ffff
perf_item_18:
        dc.l perf_item_19
        dc.w 0,144,160,8,ITEMTEXT|ITEMENABLED|HIGHNONE
        dc.l 0,perf_text,0
        dc.b 0,0
        dc.l 0
        dc.w $ffff
perf_item_19:
        dc.l 0
        dc.w 0,152,160,8,ITEMTEXT|ITEMENABLED|HIGHNONE
        dc.l 0,perf_text,0
        dc.b 0,0
        dc.l 0
        dc.w $ffff
perf_text:
        dc.b 30,27,JAM1,0
        dc.w 0,0
        dc.l 0,perf_label,0
ghost_menu:
        dc.l 0
        dc.w 257,0,36,10,MENUENABLED
        dc.l four_a,ghost_item
        dc.w 0,0,0,0
ghost_item:
        dc.l 0
        dc.w 0,0,40,10,ITEMTEXT|HIGHNONE
        dc.l 0,child_text,0
        dc.b 0,0
        dc.l 0
        dc.w $ffff

font:
        dc.l    0,0
        dc.b    NT_FONT,0
        dc.l    fontname,0
        dc.w    tf_SIZEOF,8
        dc.b    0,FPF_DESIGNED
        dc.w    8,6,1,0
        dc.b    'A','A'
        dc.l    glyph
        dc.w    2
        dc.l    charloc,charspace,0
charspace: dc.w 6,6
charloc: dc.l   6,6
glyph:  dcb.w   8,$fc00
attr:   dc.l    fontname
        dc.w    8
        dc.b    0,0
fontname: dc.b  "menupens.font",0
gfxname: dc.b   "graphics.library",0
intname: dc.b   "intuition.library",0
inputname: dc.b "input.device",0
perf_label: dc.b "AAAAAAAAAAAAAAAAAAAAAAAA",0
perf_marker: dc.b "MENUPENS OPEN ",0
perf_nl: dc.b 10,0
perf_digits: dc.b "0123456789ABCDEF"
eight_a: dc.b "AAAAAAAA",0
six_a: dc.b    "AAAAAA",0
four_a: dc.b   "AAAA",0
hover_error: dc.b "MENUPENS HOVER FAIL",10,0
glyph_error: dc.b "MENUPENS GLYPH FAIL",10,0
ghost_error: dc.b "MENUPENS GHOST FAIL",10,0
bar_marker: dc.b "MENUPENS BAR",10,0
item_marker: dc.b "MENUPENS ITEM",10,0
sub_marker: dc.b "MENUPENS SUB",10,0
ok:     dc.b   "MENUPENS OK",10,"MENUPENS END",10,0
error:  dc.b   "MENUPENS FAIL",10,"MENUPENS END",10,0
        even
chip_before_menu: dc.l 0
perf_frames: dc.l 0
perf_start: dc.l 0
perf_elapsed: dc.l 0
perf_budget: dc.l 20000
perf_server: dcb.b 22,0
gfxbase: dc.l   0
intbase: dc.l   0
mouse_x: dc.w  0
mouse_y: dc.w  0
scan_left: dc.w 0
enabled_pixels: dc.w 0
hover_pen: dc.w 0
hover_bad: dc.w 0
saved_mt: dc.l 0,0
io:     dcb.b  48,0
event:  dcb.b  IE_SIZEOF,0
prefs:  dcb.b  PF_SIZE,0
bad:    dc.b   0
complete: dc.b 0
