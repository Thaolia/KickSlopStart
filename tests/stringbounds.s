; SPDX-License-Identifier: MIT
; Native regression: refreshing a string gadget clears text cells, not its whole declared rectangle.
; Authored guard pixels cover extra rows, partial columns and cells beyond the buffer's padding limit.
                include "exec.i"
                include "graphics.i"
                include "intuition.i"
                section code,code
_start:
        movem.l d2-d7/a2-a6,-(sp)
        suba.l  a4,a4
        suba.l  a3,a3
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
        move.l  4.w,a6
        jsr     LVO_FORBID(a6)
        move.l  intbase(pc),a6
        move.l  a3,a0
        lea     gadget(pc),a1
        moveq   #-1,d0
        moveq   #1,d1
        suba.l  a2,a2
        jsr     -438(a6)           ; AddGList(window, gadget, -1, 1, NULL)
        moveq   #0,d7
next_case:
        clr.l   buffer
        clr.l   info+SI_BUFFERPOS
        clr.l   info+SI_DISPPOS
        move.w  #16,info+SI_MAXCHARS
        moveq   #40,d6             ; first untouched column after four complete eight-pixel cells
        btst    #0,d7
        beq.s   .content
        move.w  #3,info+SI_MAXCHARS
        moveq   #24,d6             ; only two cells fit before MaxChars - 1
.content:
        btst    #1,d7
        beq.s   .paint
        move.b  #'A',buffer
        move.b  #'B',buffer+1
.paint:
        move.l  gfxbase(pc),a6
        move.l  WD_RPORT(a3),a1
        moveq   #3,d0
        jsr     LVO_SETAPEN(a6)
        moveq   #8,d0
        moveq   #18,d1
        moveq   #44,d2
        moveq   #28,d3
        move.l  WD_RPORT(a3),a1
        jsr     LVO_RECTFILL(a6)
        jsr     -228(a6)
        bsr     refresh
        moveq   #18,d5
.rows:
        move.w  d6,d4
.cols:
        move.w  d4,d0
        move.w  d5,d1
        bsr     pixel
        cmp.l   #3,d0
        beq.s   .next_col
        st      bad
.next_col:
        addq.w  #1,d4
        cmp.w   #44,d4
        ble.s   .cols
        addq.w  #1,d5
        cmp.w   #25,d5
        ble.s   .rows
        moveq   #26,d5
.bottom:
        moveq   #8,d4
.bottom_row:
        move.w  d4,d0
        move.w  d5,d1
        bsr     pixel
        cmp.l   #3,d0
        beq.s   .bottom_next
        st      bad
.bottom_next:
        addq.w  #1,d4
        cmp.w   #44,d4
        ble.s   .bottom_row
        addq.w  #1,d5
        cmp.w   #28,d5
        ble.s   .bottom
        clr.b   buffer             ; a second refresh must remove the old text as well
        bsr     refresh
        moveq   #18,d5
.clear_row:
        moveq   #8,d4
.clear_col:
        move.w  d4,d0
        move.w  d5,d1
        bsr     pixel
        tst.l   d0
        beq.s   .clear_next
        st      bad
.clear_next:
        addq.w  #1,d4
        cmp.w   d6,d4
        blt.s   .clear_col
        addq.w  #1,d5
        cmp.w   #25,d5
        ble.s   .clear_row
        addq.w  #1,d7
        cmp.w   #4,d7
        blo     next_case
        move.l  4.w,a6
        jsr     LVO_PERMIT(a6)
        move.l  intbase(pc),a6
        move.l  a3,a0
        jsr     -72(a6)
        st      complete
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
refresh:
        move.l  intbase(pc),a6
        lea     gadget(pc),a0
        move.l  a3,a1
        suba.l  a2,a2
        moveq   #1,d0
        jsr     -432(a6)           ; RefreshGList
        move.l  gfxbase(pc),a6
        jmp     -228(a6)
pixel:
        move.l  WD_RPORT(a3),a1
        jmp     -318(a6)
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
        dc.w    0,0,640,200,2
        dc.b    0,1
        dc.w    $8000,CUSTOMSCREEN
        dc.l    attr,0,0,0
new_window:
        dc.w    40,30,128,64
        dc.b    0,1
        dc.l    0,BORDERLESS,0,0,0,0,0
        dc.w    0,0,0,0,CUSTOMSCREEN
gadget:
        dc.l    0
        dc.w    8,18,37,11,3,0,STRGADGET
        dc.l    border,0,0,0,info
        dc.w    1
        dc.l    0
border:
        dc.w    -1,-1
        dc.b    3,0,JAM1,5
        dc.l    points,0
points: dc.w    0,9,38,9,38,0,0,0,0,9
info:
        dc.l    buffer,0
        dc.w    0,16,0,0,0,0,0,0
        dc.l    0,0,0
attr:   dc.l    fontname
        dc.w    8
        dc.b    0,FPF_ROMFONT
fontname: dc.b "topaz.font",0
gfxname: dc.b  "graphics.library",0
intname: dc.b  "intuition.library",0
ok:     dc.b   "STRBOUNDS OK",10,"STRBOUNDS END",10,0
error:  dc.b   "STRBOUNDS FAIL",10,"STRBOUNDS END",10,0
        even
gfxbase: dc.l  0
intbase: dc.l  0
buffer: dcb.b 16,0
bad:    dc.b   0
complete: dc.b 0
