; SPDX-License-Identifier: MIT
; Native spacing-only Text regression: pen advance, visible pixels, style/mode fallbacks and bounded work.
; All font data is authored here. Zero-width glyph images have six-pixel character spacing.
                include "exec.i"
                include "graphics.i"
PLSIZE          EQU 256
BUFSIZE         EQU 16+5*PLSIZE+16
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
        move.l  #BUFSIZE,d0
        moveq   #MEMF_CHIP,d1
        move.l  4.w,a6
        jsr     LVO_ALLOCMEM(a6)
        move.l  d0,chip
        beq     fail
        moveq   #0,d7
.case:
        bsr     initialize
        move.l  gfxbase(pc),a6
        lea     rp(pc),a1
        moveq   #0,d0
        lea     modes(pc),a0
        move.b  0(a0,d7.w),d0
        jsr     LVO_SETDRMD(a6)
        cmp.w   #4,d7
        bne.s   .draw
        move.b  #FSF_UNDERLINED,rp+rp_AlgoStyle
.draw:
        bsr     draw
        bsr     check
        addq.w  #1,d7
        cmp.w   #5,d7
        blo.s   .case
        lea     pixels_ok(pc),a0
        bsr     puts
        move.l  4.w,a6
        lea     server(pc),a1
        lea     vbcode(pc),a0
        move.l  a0,18(a1)
        moveq   #5,d0
        jsr     LVO_ADDINTSERVER(a6)
        bsr     initialize
        lea     rp(pc),a1
        moveq   #JAM1,d0
        move.l  gfxbase(pc),a6
        jsr     LVO_SETDRMD(a6)
        bsr     now
        move.l  d0,d6
        moveq   #31,d7
.measure:
        bsr     draw
        dbra    d7,.measure
        bsr     now
        sub.l   d6,d0
        move.l  d0,elapsed
        move.l  4.w,a6
        lea     server(pc),a1
        moveq   #5,d0
        jsr     LVO_REMINTSERVER(a6)
        lea     timing(pc),a0
        bsr     puts
        move.l  elapsed(pc),d0
        bsr     hex
        lea     newline(pc),a0
        bsr     puts
        move.l  elapsed(pc),d0
        cmp.l   #4000,d0            ; 32 sixteen-character runs: below thirteen PAL fields (original ROM: about nine)
        bhs     fail
        move.l  chip(pc),a1
        move.l  #BUFSIZE,d0
        jsr     LVO_FREEMEM(a6)
        move.l  gfxbase(pc),a1
        jsr     LVO_CLOSELIBRARY(a6)
        lea     ok(pc),a0
        bsr     puts
        movem.l (sp)+,d2-d7/a2-a6
        moveq   #0,d0
        rts
fail:
        lea     error(pc),a0
        bsr     puts
.stop:  bra.s   .stop
initialize:
        move.l  chip(pc),a0
        move.w  #BUFSIZE/4-1,d0
.fill:  move.l  #$a5a5a5a5,(a0)+
        dbra    d0,.fill
        move.l  gfxbase(pc),a6
        lea     bm(pc),a0
        moveq   #5,d0
        move.l  #128,d1
        moveq   #16,d2
        jsr     -390(a6)
        move.l  chip(pc),a0
        lea     16(a0),a0
        lea     bm+bm_Planes(pc),a1
        moveq   #4,d0
.planes:
        move.l  a0,(a1)+
        lea     PLSIZE(a0),a0
        dbra    d0,.planes
        lea     rp(pc),a1
        jsr     LVO_INITRASTPORT(a6)
        lea     bm(pc),a0
        move.l  a0,rp+rp_BitMap
        lea     font(pc),a0
        jsr     LVO_SETFONT(a6)
        moveq   #1,d0
        jsr     LVO_SETAPEN(a6)
        moveq   #2,d0
        jsr     LVO_SETBPEN(a6)
        rts
draw:
        move.l  gfxbase(pc),a6
        lea     rp(pc),a1
        moveq   #3,d0
        moveq   #8,d1
        jsr     LVO_MOVE(a6)
        lea     text(pc),a0
        moveq   #16,d0
        jsr     LVO_TEXT(a6)
        jmp     -228(a6)
check:
        cmp.w   #99,rp+rp_cp_x
        bne     fail
        cmp.w   #8,rp+rp_cp_y
        bne     fail
        move.l  chip(pc),a0
        moveq   #3,d0
.guard:
        cmp.l   #$a5a5a5a5,(a0)+
        bne     fail
        dbra    d0,.guard
        moveq   #0,d1
        move.w  #5*PLSIZE/4-1,d0
.pixels:
        cmp.l   #$a5a5a5a5,(a0)+
        beq.s   .same
        addq.w  #1,d1
.same:  dbra    d0,.pixels
        moveq   #3,d0
.tail:  cmp.l   #$a5a5a5a5,(a0)+
        bne     fail
        dbra    d0,.tail
        cmp.w   #2,d7
        bhs.s   .changed
        tst.w   d1
        bne     fail
        rts
.changed:
        tst.w   d1
        beq     fail
        rts
vbcode:
        addq.l  #1,frames
        moveq   #0,d0
        rts
now:
        move.l  frames(pc),d0
        move.l  $dff004,d1
        lsr.l   #8,d1
        and.l   #511,d1
        cmp.l   frames(pc),d0
        bne.s   now
        mulu    #313,d0
        add.l   d1,d0
        rts
hex:
        movem.l d0-d3,-(sp)
        move.l  d0,d2
        moveq   #7,d1
        lea     digits(pc),a0
.loop:
        rol.l   #4,d2
        moveq   #15,d3
        and.l   d2,d3
        moveq   #0,d0
        move.b  0(a0,d3.w),d0
.wait:
        btst    #5,$dff018
        beq.s   .wait
        or.w    #256,d0
        move.w  d0,$dff030
        dbra    d1,.loop
        movem.l (sp)+,d0-d3
        rts
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
digits: dc.b "0123456789ABCDEF"
timing: dc.b "TEXTBLANK TIME ",0
newline: dc.b 10,0
modes:  dc.b JAM1,COMPLEMENT,JAM2,INVERSVID,JAM1
text:   dcb.b 16,'A'
gfxname: dc.b "graphics.library",0
pixels_ok: dc.b "TEXTBLANK PIXELS OK",10,0
ok:     dc.b "TEXTBLANK OK",10,"TEXTBLANK END",10,0
error:  dc.b "TEXTBLANK FAIL",10,"TEXTBLANK END",10,0
        even
font:
        dcb.b 20,0
        dc.w 8
        dc.b 0,FPF_DESIGNED
        dc.w 8,6,1,0
        dc.b 'A','A'
        dc.l glyph
        dc.w 2
        dc.l charloc,charspace,0
charloc: dc.l 0,0
charspace: dc.w 6,6
glyph:  dcb.w 8,0
chip:   dc.l 0
gfxbase: dc.l 0
frames: dc.l 0
elapsed: dc.l 0
server: dcb.b 22,0
bm:     dcb.b bm_SIZEOF,0
rp:     dcb.b rp_SIZEOF,0
