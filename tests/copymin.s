; SPDX-License-Identifier: MIT
; Native Boolean-minterm equivalence, rectangle-copy correctness and restore/animation speed gates.
                include "exec.i"
                include "graphics.i"
BUFSIZE         EQU 110592
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
        lea     copymin_cases(pc),a4
        move.w  #COPYMIN_CASES-1,d7
.case:
        clr.w   api
.api:
        move.l  chip(pc),a3
        bsr     initialize
        bsr     copy
        bsr     check
        move.l  soft(pc),a3
        bsr     initialize
        bsr     copy
        bsr     check
        addq.w  #1,api
        cmp.w   #3,api
        blo.s   .api
        move.w  4(a4),d0
        cmp.w   6(a4),d0
        bne.s   .next
        cmp.w   #3,api
        beq.s   .api               ; same underlying planes also tested through one actual RastPort/BitMap
.next:
        lea     36(a4),a4
        dbra    d7,.case
        lea     pixels_ok(pc),a0
        bsr     puts
        move.w  #2,api
        lea     copymin_large(pc),a4
        move.l  chip(pc),a3
        bsr     benchmark
        move.l  soft(pc),a3
        bsr     benchmark
        lea     copymin_motion(pc),a4
        move.w  #2,api
        bsr     motion
        lea     36(a4),a4
        move.w  #3,api
        bsr     motion
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
        move.w  30(a4),d1
        subq.w  #1,d1
.fill:
        move.l  d0,(a0)+
        add.l   #$0103070b,d0
        dbra    d1,.fill
        move.l  gfxbase(pc),a6
        lea     srp(pc),a1
        jsr     -198(a6)
        lea     drp(pc),a1
        jsr     -198(a6)
        lea     sbm(pc),a0
        move.l  a0,srp+rp_BitMap
        move.w  (a4),bm_BytesPerRow(a0)
        move.w  28(a4),bm_Rows(a0)
        move.b  9(a4),bm_Depth(a0)
        move.w  (a4),d2
        mulu    28(a4),d2
        moveq   #0,d0
        move.w  4(a4),d0
        cmp.w   #-1,d0
        bne.s   .source
        moveq   #-1,d0
.source:
        moveq   #0,d3
        move.b  bm_Depth(a0),d3
        subq.w  #1,d3
        lea     bm_Planes(a0),a0
.source_plane:
        move.l  d0,d1
        beq.s   .source_store
        cmp.l   #-1,d1
        beq.s   .source_store
        add.l   a3,d1
.source_store:
        move.l  d1,(a0)+
        tst.l   d0
        beq.s   .source_next
        cmp.l   #-1,d0
        beq.s   .source_next
        add.l   d2,d0
.source_next:
        dbra    d3,.source_plane
        lea     dbm(pc),a0
        move.l  a0,drp+rp_BitMap
        move.w  2(a4),bm_BytesPerRow(a0)
        move.w  28(a4),bm_Rows(a0)
        move.b  11(a4),bm_Depth(a0)
        move.w  2(a4),d2
        mulu    28(a4),d2
        moveq   #0,d0
        move.w  6(a4),d0
        add.l   a3,d0
        moveq   #0,d3
        move.b  bm_Depth(a0),d3
        subq.w  #1,d3
        lea     bm_Planes(a0),a0
.dest_plane:
        move.l  d0,(a0)+
        add.l   d2,d0
        dbra    d3,.dest_plane
        move.b  13(a4),drp+rp_Mask
        lea     drp(pc),a0
        lea     saved(pc),a1
        moveq   #rp_SIZEOF/4-1,d0
.save:
        move.l  (a0)+,(a1)+
        dbra    d0,.save
        rts
copy:
        movem.l d2-d7/a2-a4,-(sp)
        move.l  gfxbase(pc),a6
        movem.w 14(a4),d0-d5
        moveq   #0,d6
        move.w  26(a4),d6
        or.l    #$12340000,d6
        cmp.w   #1,api
        beq.s   .bitmap
        tst.w   api
        bne.s   .clip
        lea     sbm(pc),a0
        lea     drp(pc),a1
        jsr     -606(a6)
        bra.s   .returned
.clip:
        lea     srp(pc),a0
        lea     drp(pc),a1
        cmp.w   #3,api
        bne.s   .clip_call
        move.l  a1,a0
.clip_call:
        jsr     -552(a6)
        bra.s   .returned
.bitmap:
        lea     sbm(pc),a0
        lea     dbm(pc),a1
        moveq   #0,d7
        move.w  12(a4),d7
        suba.l  a2,a2
        jsr     -30(a6)
        moveq   #0,d1
        moveq   #0,d2
.count:
        btst    d2,d7
        beq.s   .next_bit
        addq.w  #1,d1
.next_bit:
        addq.w  #1,d2
        cmp.w   10(a4),d2
        blo.s   .count
        cmp.w   d0,d1
        bne     fail
.returned:
        moveq   #0,d0
        move.w  26(a4),d0
        or.l    #$12340000,d0
        cmp.l   d6,d0
        bne     fail
        jsr     -228(a6)
        movem.l (sp)+,d2-d7/a2-a4
        rts
check:
        lea     drp(pc),a0
        lea     saved(pc),a1
        moveq   #rp_SIZEOF/4-1,d0
.state:
        cmpm.l  (a0)+,(a1)+
        bne     fail
        dbra    d0,.state
        move.l  a3,a0
        moveq   #0,d0
        move.w  30(a4),d1
        subq.w  #1,d1
.hash:
        rol.l   #5,d0
        add.l   (a0)+,d0
        dbra    d1,.hash
        cmp.l   32(a4),d0
        bne     fail
        rts
benchmark:
        move.w  #$c0,26(a4)
        bsr     initialize
        bsr     measure
        move.l  d0,d6
        bsr     check
        move.w  #$cc,26(a4)
        bsr     measure
        move.l  d0,d5
        bsr     check
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
        cmp.l   #4800,d6           ; four complete restores, average below1200PAL lines each
        bhs     fail
        cmp.l   #4800,d5
        bhs     fail
        move.l  d6,d0
        lsr.l   #2,d0
        add.l   d6,d0
        cmp.l   d0,d5              ; equivalent minterms must stay within25% under interrupt/bus variation
        bhi     fail
        rts
motion:
        move.l  chip(pc),a3
        bsr     initialize
        bsr     measure
        move.l  d0,d6
        bsr     check
        lea     motion_timing(pc),a0
        bsr     puts
        moveq   #0,d0
        move.w  26(a4),d0
        bsr     hex
        moveq   #' ',d0
        bsr     putc
        move.l  d6,d0
        bsr     hex
        moveq   #10,d0
        bsr     putc
        cmp.l   #1000,d6           ; four 40x40, five-plane updates: average below one PAL frame
        bhs     fail
        rts
measure:
        bsr     now
        move.l  d0,d2
        moveq   #3,d7
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
.loop: move.b (a0)+,d0
        beq.s .done
        bsr.s putc
        bra.s .loop
.done: move.l (sp)+,d0
        rts
putc:
        btst #5,$dff018
        beq.s putc
        and.w #255,d0
        or.w #256,d0
        move.w d0,$dff030
        rts
hex:
        movem.l d0-d2,-(sp)
        move.l d0,d2
        moveq #7,d1
.loop: rol.l #4,d2
        moveq #15,d0
        and.b d2,d0
        move.b digits(pc,d0.w),d0
        bsr.s putc
        dbra d1,.loop
        movem.l (sp)+,d0-d2
        rts
digits: dc.b "0123456789ABCDEF"
gfxname: dc.b "graphics.library",0
pixels_ok: dc.b "COPYMIN PIXELS OK",10,0
timing: dc.b "COPYMIN RESTORE ",0
motion_timing: dc.b "COPYMIN MOTION ",0
ok: dc.b "COPYMIN OK",10,"COPYMIN END",10,0
error: dc.b "COPYMIN FAIL",10,"COPYMIN END",10,0
        even
        include "copymin_cases.i"
chip: dc.l 0
soft: dc.l 0
gfxbase: dc.l 0
frames: dc.l 0
api: dc.w 0
vbint: dcb.b 22,0
sbm: dcb.b bm_SIZEOF,0
dbm: dcb.b bm_SIZEOF,0
srp: dcb.b rp_SIZEOF,0
drp: dcb.b rp_SIZEOF,0
saved: dcb.b rp_SIZEOF,0
