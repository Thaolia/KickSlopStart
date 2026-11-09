; SPDX-License-Identifier: MIT
; Authored shifted bitmap-copy regression and native PAL scanline speed gate.
                include "exec.i"
                include "graphics.i"
BUFSIZE         EQU 49152
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
        jsr     LVO_ALLOCMEM(a6)
        move.l  d0,chip
        beq     fail
        move.l  #BUFSIZE,d0
        moveq   #0,d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  d0,soft
        beq     fail
        move.l  d0,a1
        jsr     LVO_TYPEOFMEM(a6)
        btst    #1,d0
        bne     fail
        lea     vbint(pc),a1
        lea     vbcode(pc),a0
        move.l  a0,18(a1)
        moveq   #5,d0
        jsr     LVO_ADDINTSERVER(a6)
        lea     copy_cases(pc),a4
        move.w  #COPY_CASES-1,d7
.case:
        move.l  chip(pc),a3
        bsr     initialize
        bsr     copy
        bsr     fingerprint
        cmp.l   28(a4),d0
        bne     fail
        move.l  soft(pc),a3
        bsr     initialize
        bsr     copy
        bsr     fingerprint
        cmp.l   28(a4),d0
        bne     fail
        lea     32(a4),a4
        dbra    d7,.case
        lea     pixels_ok(pc),a0
        bsr     puts
        lea     copy_cases(pc),a4
        move.l  chip(pc),a3
        bsr     initialize
        bsr     measure
        move.l  d0,d6
        move.l  soft(pc),a3
        bsr     initialize
        bsr     measure
        move.l  d0,d5
        lea     timing(pc),a0
        bsr     puts
        move.l  d6,d0
        bsr     hex
        moveq   #' ',d0
        bsr     putc
        move.l  d5,d0
        bsr     hex
        moveq   #10,d0
        bsr     putc
        cmp.l   #8192,d6           ; eight copies, each comfortably below an 80 ms playback interval
        bhs     fail
        cmp.l   #8192,d5
        bhs     fail
        move.l  4.w,a6
        lea     vbint(pc),a1
        moveq   #5,d0
        jsr     LVO_REMINTSERVER(a6)
        move.l  chip(pc),a1
        move.l  #BUFSIZE,d0
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
        move.l  #$13579bdf,d0
        move.w  #BUFSIZE/4-1,d1
.fill:
        move.l  d0,(a0)+
        add.l   #$0103070b,d0
        dbra    d1,.fill
        move.l  gfxbase(pc),a6
        lea     source_rp(pc),a1
        jsr     -198(a6)
        lea     destination_rp(pc),a1
        jsr     -198(a6)
        lea     source_bm(pc),a0
        move.l  a0,source_rp+rp_BitMap
        move.w  (a4),bm_BytesPerRow(a0)
        move.w  #128,bm_Rows(a0)
        move.b  9(a4),bm_Depth(a0)
        move.w  4(a4),d0
        ext.l   d0
        ble.s   .source
        add.l   a3,d0
.source:
        move.l  d0,bm_Planes(a0)
        lea     destination_bm(pc),a0
        move.l  a0,destination_rp+rp_BitMap
        move.w  2(a4),bm_BytesPerRow(a0)
        move.w  #160,bm_Rows(a0)
        move.b  11(a4),bm_Depth(a0)
        move.w  6(a4),d0
        ext.l   d0
        add.l   a3,d0
        move.l  d0,bm_Planes(a0)
        add.l   #12800,d0
        move.l  d0,bm_Planes+4(a0)
        move.b  13(a4),destination_rp+rp_Mask
        lea     destination_rp(pc),a0
        lea     saved_rp(pc),a1
        moveq   #rp_SIZEOF/4-1,d0
.save:
        move.l  (a0)+,(a1)+
        dbra    d0,.save
        rts
copy:
        movem.l d2-d7/a2-a4,-(sp)
        move.l  gfxbase(pc),a6
        move.w  14(a4),d0
        move.w  16(a4),d1
        move.w  18(a4),d2
        move.w  20(a4),d3
        move.w  22(a4),d4
        move.w  24(a4),d5
        move.w  26(a4),d6
        lea     source_rp(pc),a0
        lea     destination_rp(pc),a1
        jsr     -552(a6)          ; ClipBlit exercises BltBitMapRastPort's row-copy engine
        jsr     -228(a6)
        movem.l (sp)+,d2-d7/a2-a4
        rts
fingerprint:
        lea     destination_rp(pc),a0
        lea     saved_rp(pc),a1
        moveq   #rp_SIZEOF/4-1,d0
.state:
        cmpm.l  (a0)+,(a1)+
        bne     fail
        dbra    d0,.state
        move.l  a3,a0
        moveq   #0,d0
        move.w  #BUFSIZE/4-1,d1
.hash:
        rol.l   #5,d0
        add.l   (a0)+,d0
        dbra    d1,.hash
        rts
measure:
        bsr     now
        move.l  d0,d2
        moveq   #7,d7
.copy:
        bsr     copy
        dbra    d7,.copy
        bsr     now
        sub.l   d2,d0
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
        mulu    #312,d0
        add.l   d1,d0
        rts
puts:
        move.l  d0,-(sp)
.loop:
        move.b  (a0)+,d0
        beq.s   .done
        bsr.s   putc
        bra.s   .loop
.done:
        move.l  (sp)+,d0
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
.loop:
        rol.l   #4,d2
        moveq   #15,d0
        and.b   d2,d0
        move.b  digits(pc,d0.w),d0
        bsr.s   putc
        dbra    d1,.loop
        movem.l (sp)+,d0-d2
        rts
digits: dc.b "0123456789ABCDEF"
gfxname: dc.b "graphics.library",0
pixels_ok: dc.b "COPYSHIFT PIXELS OK",10,0
timing: dc.b "COPYSHIFT COPY ",0
ok: dc.b "COPYSHIFT OK",10,"COPYSHIFT END",10,0
error: dc.b "COPYSHIFT FAIL",10,"COPYSHIFT END",10,0
        even
        include "copyshift_cases.i"
chip: dc.l 0
soft: dc.l 0
gfxbase: dc.l 0
frames: dc.l 0
vbint: dcb.b 22,0
source_bm: dcb.b bm_SIZEOF,0
destination_bm: dcb.b bm_SIZEOF,0
source_rp: dcb.b rp_SIZEOF,0
destination_rp: dcb.b rp_SIZEOF,0
saved_rp: dcb.b rp_SIZEOF,0
