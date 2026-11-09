; SPDX-License-Identifier: MIT
; Native regression: a window uses its screen font, including when the global default is different.
; Authored text and sentinel lines verify the resulting text advance and drawing bounds.
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
        move.l  gfxbase(pc),a6
        move.l  gb_DefaultFont(a6),a0
        move.l  SC_RASTPORT+rp_Font(a4),d0
        cmp.l   a0,d0
        beq     close_screen       ; require a screen font distinct from the global default
        move.l  d0,screenfont
        move.l  4.w,a6
        jsr     LVO_FORBID(a6)
        lea     modes(pc),a2
next_case:
        move.l  (a2)+,d7
        bmi     done
        move.l  d7,new_window+NW_FLAGS
        move.l  intbase(pc),a6
        lea     new_window(pc),a0
        jsr     -204(a6)
        move.l  d0,a3
        tst.l   d0
        beq     done
        move.l  WD_IFONT(a3),d0
        cmp.l   screenfont(pc),d0
        beq.s   .body
        st      bad
.body:
        move.l  WD_RPORT(a3),a1
        btst    #10,d7
        bne.s   .gzz_body
        bsr     check_font
        bra.s   .border
.gzz_body:
        cmp.w   #10,rp_TxWidth(a1)  ; 1.3 leaves the newly-created GZZ inner port at the global default
        bne.s   .body_bad
        cmp.w   #9,rp_TxHeight(a1)
        bne.s   .body_bad
        cmp.w   #6,rp_TxBaseline(a1)
        beq.s   .border
.body_bad:
        st      bad
.border:
        move.l  WD_BORDERRPORT(a3),d0
        beq.s   .text
        move.l  d0,a1
        bsr     check_font
        bra     close_window       ; the eight-cell drawing checks apply to ordinary window ports
.text:
        move.l  gfxbase(pc),a6
        move.l  WD_RPORT(a3),a1
        lea     label(pc),a0
        moveq   #7,d0
        jsr     -54(a6)            ; TextLength("Protect") in an eight-pixel cell
        cmp.w   #56,d0
        beq.s   .lines
        st      bad
.lines:
        move.l  WD_RPORT(a3),a1
        moveq   #3,d0
        jsr     LVO_SETAPEN(a6)
        moveq   #64,d0
        moveq   #14,d1
        moveq   #64,d2
        moveq   #22,d3
        move.l  WD_RPORT(a3),a1
        jsr     LVO_RECTFILL(a6)
        moveq   #4,d0
        moveq   #22,d1
        moveq   #59,d2
        moveq   #22,d3
        move.l  WD_RPORT(a3),a1
        jsr     LVO_RECTFILL(a6)
        move.l  WD_RPORT(a3),a1
        moveq   #1,d0
        jsr     LVO_SETAPEN(a6)
        move.l  WD_RPORT(a3),a1
        moveq   #4,d0
        moveq   #20,d1
        jsr     LVO_MOVE(a6)
        move.l  WD_RPORT(a3),a1
        lea     label(pc),a0
        moveq   #7,d0
        jsr     -60(a6)            ; Text: wrong width/height overwrites the authored sentinel lines
        move.l  WD_RPORT(a3),a1
        cmp.w   #60,rp_cp_x(a1)
        beq.s   .guards
        st      bad
.guards:
        jsr     -228(a6)
        moveq   #14,d5
.vertical:
        moveq   #64,d0
        move.w  d5,d1
        bsr     check_pixel
        addq.w  #1,d5
        cmp.w   #22,d5
        ble.s   .vertical
        moveq   #4,d4
.horizontal:
        move.w  d4,d0
        moveq   #22,d1
        bsr     check_pixel
        addq.w  #1,d4
        cmp.w   #59,d4
        ble.s   .horizontal
close_window:
        move.l  intbase(pc),a6
        move.l  a3,a0
        jsr     -72(a6)
        bra     next_case
done:
        move.l  4.w,a6
        jsr     LVO_PERMIT(a6)
        tst.l   d7
        bpl.s   .incomplete
        st      complete
        bra.s   close_screen
.incomplete:
        st      bad
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
check_font:
        move.l  rp_Font(a1),d0
        cmp.l   screenfont(pc),d0
        bne.s   .bad
        cmp.w   #8,rp_TxWidth(a1)
        bne.s   .bad
        cmp.w   #8,rp_TxHeight(a1)
        bne.s   .bad
        cmp.w   #6,rp_TxBaseline(a1)
        beq.s   .ret
.bad:   st      bad
.ret:   rts
check_pixel:
        move.l  WD_RPORT(a3),a1
        jsr     -318(a6)
        cmp.l   #3,d0
        beq.s   .ret
        st      bad
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
        dc.w    0,0,640,200,2
        dc.b    0,1
        dc.w    $8000,CUSTOMSCREEN
        dc.l    attr,0,0,0
new_window:
        dc.w    40,30,128,64
        dc.b    0,1
        dc.l    0,0,0,0,0,0,0
        dc.w    0,0,0,0,CUSTOMSCREEN
modes:  dc.l    BORDERLESS,WINDOWCLOSE,WINDOWCLOSE|GIMMEZEROZERO,-1
attr:   dc.l    fontname
        dc.w    8
        dc.b    0,FPF_ROMFONT
fontname: dc.b  "topaz.font",0
gfxname: dc.b   "graphics.library",0
intname: dc.b   "intuition.library",0
label:  dc.b    "Protect",0
ok:     dc.b    "WINFONT OK",10,"WINFONT END",10,0
error:  dc.b    "WINFONT FAIL",10,"WINFONT END",10,0
        even
gfxbase: dc.l   0
intbase: dc.l   0
screenfont: dc.l 0
bad:    dc.b    0
complete: dc.b  0
