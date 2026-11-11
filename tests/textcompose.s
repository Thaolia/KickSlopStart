; SPDX-License-Identifier: MIT
; Native proportional Text: authored narrow/wide glyphs, source/destination phases, masks and modes.
; Independent whole-allocation fingerprints include bitmap guards; a bounded repeated-line workload catches lag.
                include "exec.i"
                include "graphics.i"
BUFSIZE         EQU 544
SCRATCH         EQU 256
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
        move.l  4.w,a6
        move.l  #BUFSIZE+SCRATCH,d0
        moveq   #MEMF_CHIP,d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  d0,chip
        beq     fail
        move.l  #BUFSIZE,d0
        moveq   #MEMF_PUBLIC,d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  d0,soft
        beq     fail
        move.l  d0,a1
        jsr     LVO_TYPEOFMEM(a6)
        btst    #1,d0
        bne     fail
        move.l  chip(pc),d0
        add.l   #BUFSIZE,d0
        move.l  d0,tmpras+tr_RasPtr
        move.l  #SCRATCH,tmpras+tr_Size
        lea     compose_cases(pc),a4
        move.w  #TEXTCOMPOSE_CASES-1,d7
.case:
        move.l  chip(pc),a3
        bsr     initialize
        bsr     draw
        bsr     check
        move.l  soft(pc),a3
        bsr     initialize
        bsr     draw
        bsr     check
        lea     24(a4),a4
        dbra    d7,.case
        lea     pixels_ok(pc),a0
        bsr     puts
        move.l  4.w,a6
        lea     server(pc),a1
        lea     vbcode(pc),a0
        move.l  a0,18(a1)
        moveq   #5,d0
        jsr     LVO_ADDINTSERVER(a6)
        lea     benchmark_case(pc),a4
        move.l  chip(pc),a3
        bsr     initialize
        move.w  #6,charspace
        move.w  #6,charspace+2
        bsr     now
        move.l  d0,start
        moveq   #63,d7
.repeat:
        moveq   #24,d0
        bsr     draw_count
        dbra    d7,.repeat
        bsr     now
        sub.l   start(pc),d0
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
        cmp.l   #16000,elapsed        ; 64 composed 24-character lines, under fifty-two PAL fields
        bhs     fail
        move.l  chip(pc),a1
        move.l  #BUFSIZE+SCRATCH,d0
        jsr     LVO_FREEMEM(a6)
        move.l  soft(pc),a1
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
        move.l  a3,a0
        moveq   #0,d0
        move.w  #BUFSIZE-1,d1
.fill:
        move.b  d0,d2
        eor.b   #$a5,d2
        move.b  d2,(a0)+
        add.b   #29,d0
        dbra    d1,.fill
        move.l  gfxbase(pc),a6
        lea     bm(pc),a0
        moveq   #2,d0
        move.l  #128,d1
        moveq   #16,d2
        jsr     -390(a6)
        lea     16(a3),a0
        move.l  a0,bm+bm_Planes
        lea     256(a0),a0
        move.l  a0,bm+bm_Planes+4
        move.l  (a4),charloc
        move.l  (a4),charloc+4
        moveq   #1,d0
        and.w   (a4),d0
        lea     compose_strike(pc),a0
        adda.w  d0,a0
        move.l  a0,font+tf_CharData
        move.w  10(a4),charkern
        move.w  10(a4),charkern+2
        move.w  #10,charspace
        move.w  #10,charspace+2
        lea     rp(pc),a1
        jsr     LVO_INITRASTPORT(a6)
        lea     bm(pc),a0
        move.l  a0,rp+rp_BitMap
        lea     tmpras(pc),a0
        move.l  a0,rp+rp_TmpRas
        lea     font(pc),a0
        jsr     LVO_SETFONT(a6)
        moveq   #0,d0
        move.w  16(a4),d0
        jsr     LVO_SETAPEN(a6)
        moveq   #0,d0
        move.w  18(a4),d0
        jsr     LVO_SETBPEN(a6)
        moveq   #0,d0
        move.w  6(a4),d0
        jsr     LVO_SETDRMD(a6)
        move.b  9(a4),rp+rp_Mask
        move.w  12(a4),rp+rp_TxSpacing
        rts
draw:
        moveq   #12,d0
draw_count:
        move.l  d0,-(sp)
        move.l  gfxbase(pc),a6
        lea     rp(pc),a1
        moveq   #0,d0
        move.w  4(a4),d0
        moveq   #8,d1
        jsr     LVO_MOVE(a6)
        lea     text(pc),a0
        move.l  (sp)+,d0
        jsr     LVO_TEXT(a6)
        jmp     -228(a6)
check:
        move.w  rp+rp_cp_x,d0
        cmp.w   14(a4),d0
        bne     fail
        cmp.w   #8,rp+rp_cp_y
        bne     fail
        move.l  a3,a0
        moveq   #0,d0
        move.w  #BUFSIZE/4-1,d1
.hash:
        rol.l   #5,d0
        add.l   (a0)+,d0
        dbra    d1,.hash
        cmp.l   20(a4),d0
        bne     fail
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
puts:
        move.l  d0,-(sp)
.loop:  move.b  (a0)+,d0
        beq.s   .done
        bsr.s   putc
        bra.s   .loop
.done:  move.l  (sp)+,d0
        rts
putc:
        btst    #5,$dff018
        beq.s   putc
        and.w   #255,d0
        or.w    #256,d0
        move.w  d0,$dff030
        rts
hex:
        movem.l d0-d2,-(sp)
        move.l  d0,d2
        moveq   #7,d1
.loop:  rol.l   #4,d2
        moveq   #15,d0
        and.b   d2,d0
        move.b  digits(pc,d0.w),d0
        bsr.s   putc
        dbra    d1,.loop
        movem.l (sp)+,d0-d2
        rts
digits: dc.b "0123456789ABCDEF"
text:   dcb.b 24,'A'
gfxname: dc.b "graphics.library",0
pixels_ok: dc.b "TEXTCOMPOSE PIXELS OK",10,0
timing: dc.b "TEXTCOMPOSE TIME ",0
newline: dc.b 10,0
ok:     dc.b "TEXTCOMPOSE OK",10,"TEXTCOMPOSE END",10,0
error:  dc.b "TEXTCOMPOSE FAIL",10,"TEXTCOMPOSE END",10,0
        even
benchmark_case: dc.w 3,7,0,0,3,0,0,0,1,2
        dc.l 0
font:
        dcb.b 20,0
        dc.w 8
        dc.b 0,FPF_DESIGNED
        dc.w 8,6,1,0
        dc.b 'A','A'
        dc.l 0
        dc.w 5
        dc.l charloc,charspace,charkern
charloc: dc.l 0,0
charspace: dc.w 10,10
charkern: dc.w 0,0
gfxbase: dc.l 0
chip:   dc.l 0
soft:   dc.l 0
frames: dc.l 0
start:  dc.l 0
elapsed: dc.l 0
server: dcb.b 22,0
tmpras: dcb.b 8,0
bm:     dcb.b bm_SIZEOF,0
rp:     dcb.b rp_SIZEOF,0
        include "textcompose_cases.i"
