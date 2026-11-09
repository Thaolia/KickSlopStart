; SPDX-License-Identifier: MIT
; Native regression: a short close-only window must not expand over the pixels below it.
; Public Intuition/graphics structures and LVOs; no ROM-derived code or artwork.
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
        jsr     -198(a6)           ; OpenScreen
        move.l  d0,a4
        tst.l   d0
        beq     close_int
        move.l  a4,new_window+NW_SCREEN
        move.l  4.w,a6
        jsr     LVO_FORBID(a6)
        move.l  gfxbase(pc),a6
        lea     read_port(pc),a1
        jsr     LVO_INITRASTPORT(a6)
        lea     SC_BITMAP(a4),a0
        move.l  a0,read_port+rp_BitMap
        lea     heights(pc),a2
next_case:
        moveq   #0,d7
        move.w  (a2)+,d7
        beq     done
        move.w  d7,new_window+NW_HEIGHT
        lea     read_port(pc),a1
        moveq   #3,d0
        jsr     LVO_SETAPEN(a6)
        moveq   #40,d0
        moveq   #30,d1
        moveq   #66,d2
        moveq   #51,d3
        lea     read_port(pc),a1
        jsr     LVO_RECTFILL(a6)
        jsr     -228(a6)           ; finish the guard fill before Intuition draws the window
        move.l  intbase(pc),a6
        lea     new_window(pc),a0
        jsr     -204(a6)           ; OpenWindow
        move.l  d0,a3
        tst.l   d0
        beq     done
        cmp.w   WD_HEIGHT(a3),d7
        bne.s   geometry_bad
        move.l  WD_WLAYER(a3),a0
        cmp.w   #30,IL_MINY(a0)
        bne.s   geometry_bad
        move.w  d7,d0
        add.w   #29,d0
        cmp.w   IL_MAXY(a0),d0
        beq.s   guard
geometry_bad:
        st      bad
guard:
        move.l  gfxbase(pc),a6
        jsr     -228(a6)
        move.w  d7,d5
        add.w   #30,d5
.row:
        moveq   #40,d4
.pixel:
        move.w  d4,d0
        move.w  d5,d1
        lea     read_port(pc),a1
        jsr     -318(a6)           ; ReadPixel on the screen bitmap, outside the requested window bounds
        cmp.l   #3,d0
        beq.s   .next
        st      bad
.next:
        addq.w  #1,d4
        cmp.w   #66,d4
        ble.s   .pixel
        addq.w  #1,d5
        cmp.w   #51,d5
        ble.s   .row
        move.l  intbase(pc),a6
        move.l  a3,a0
        jsr     -72(a6)            ; CloseWindow
        move.l  gfxbase(pc),a6
        bra     next_case
done:
        move.l  4.w,a6
        jsr     LVO_PERMIT(a6)
        move.l  intbase(pc),a6
        move.l  a4,a0
        jsr     -66(a6)            ; CloseScreen
        tst.w   d7
        beq.s   close_int          ; only the zero terminator denotes completion of every case
        st      bad
close_int:
        move.l  4.w,a6
        move.l  intbase(pc),a1
        jsr     LVO_CLOSELIBRARY(a6)
close_gfx:
        move.l  4.w,a6
        move.l  gfxbase(pc),a1
        jsr     LVO_CLOSELIBRARY(a6)
        cmpa.w  #0,a4
        beq.s   fail
        tst.b   bad
        bne.s   fail
        lea     ok(pc),a0
        bsr.s   puts
        movem.l (sp)+,d2-d7/a2-a6
        moveq   #0,d0
        rts
fail:
        lea     error(pc),a0
        bsr.s   puts
        movem.l (sp)+,d2-d7/a2-a6
        moveq   #20,d0
        rts
puts:
        moveq   #0,d0
        move.b  (a0)+,d0
        beq.s   .done
.wait:
        btst    #5,$dff018
        beq.s   .wait
        or.w    #256,d0
        move.w  d0,$dff030
        bra.s   puts
.done:  rts
new_screen:
        dc.w    0,0,640,200,2
        dc.b    0,1
        dc.w    $8000,CUSTOMSCREEN
        dc.l    0,0,0,0
new_window:
        dc.w    40,30,27,10
        dc.b    0,1
        dc.l    0,WINDOWCLOSE,0,0,0,0,0
        dc.w    0,0,0,0,CUSTOMSCREEN
heights: dc.w  10,1,8,15,16,0
gfxname: dc.b  "graphics.library",0
intname: dc.b  "intuition.library",0
ok:      dc.b  "SMALLWIN OK",10,"SMALLWIN END",10,0
error:   dc.b  "SMALLWIN FAIL",10,"SMALLWIN END",10,0
        even
gfxbase: dc.l  0
intbase: dc.l  0
bad:     dc.b  0,0
read_port: dcb.b 100,0
