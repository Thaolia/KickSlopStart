; SPDX-License-Identifier: MIT
; Native PAL regression: a display takeover must be able to wait for scanline 312.
; Uses the public graphics FD and documented Agnus registers, no ROM-derived code or data.
                include "exec.i"
                include "graphics.i"
                section code,code
_start:
        movem.l d2-d7/a2-a6,-(sp)
        move.w  #372,$dff032
        move.l  4.w,a6
        lea     gfxname(pc),a1
        moveq   #0,d0
        jsr     LVO_OPENLIBRARY(a6)
        tst.l   d0
        beq     fail
        move.l  d0,a3
        jsr     LVO_FORBID(a6)
        move.l  a3,a6
        move.l  gb_ActiView(a6),a2
        moveq   #0,d6
        btst    #7,$dff004          ; graphics initialization must already select a long frame
        beq.s   failed
        suba.l  a1,a1
        jsr     -222(a6)           ; LoadView(NULL) removes any interlaced system display
        bsr.s   short_frame
        btst    #7,$dff004
        bne.s   failed             ; require a genuine short-frame starting condition
        suba.l  a1,a1
        jsr     -222(a6)
        btst    #7,$dff004
        beq.s   failed
        move.w  #$ffff,d7          ; bound the observation even when line 312 never arrives
.beam:
        move.l  $dff004,d0
        lsr.l   #8,d0
        and.w   #$01ff,d0
        cmp.w   #312,d0
        beq.s   restore
        dbra    d7,.beam
failed:
        moveq   #1,d6
restore:
        move.l  a2,a1
        jsr     -222(a6)
        move.l  4.w,a6
        jsr     LVO_PERMIT(a6)
        move.l  a3,a1
        jsr     LVO_CLOSELIBRARY(a6)
        tst.w   d6
        bne.s   fail
        lea     ok(pc),a0
        bsr.s   puts
        movem.l (sp)+,d2-d7/a2-a6
        moveq   #0,d0
        rts
fail:
        lea     bad(pc),a0
        bsr.s   puts
        movem.l (sp)+,d2-d7/a2-a6
        moveq   #20,d0
        rts

; Preserve the current ninth beam bit while selecting a short non-interlaced frame.
short_frame:
        move.w  #2000,d0
.safe:
        cmp.b   #$ff,$dff006
        dbne    d0,.safe
        move.w  $dff004,d0
        and.w   #1,d0
        move.w  d0,$dff02a
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
gfxname: dc.b "graphics.library",0
ok:     dc.b "LONGFRAME OK",10,"LONGFRAME END",10,0
bad:    dc.b "LONGFRAME FAIL",10,"LONGFRAME END",10,0
