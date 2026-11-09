; SPDX-License-Identifier: MIT
; Authored native regression: RectFill must use client-supplied per-plane minterms.
; DPaint-style selective XOR and independent Boolean results, in CHIP and non-DMA RAM.
                include "exec.i"
                include "graphics.i"
MINT            EQU rp_minterms
PLSIZE          EQU 256
GUARD           EQU 16
BUFSIZE         EQU GUARD+4*PLSIZE+GUARD
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
        beq     close_gfx
        move.l  #BUFSIZE,d0
        moveq   #0,d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  d0,soft
        beq     free_chip
        move.l  d0,a1
        jsr     LVO_TYPEOFMEM(a6)
        btst    #1,d0
        bne     free_soft
        moveq   #0,d7
next_case:
        move.l  chip(pc),a4
        bsr     exercise
        tst.l   d0
        bne     free_soft
        move.l  soft(pc),a4
        bsr     exercise
        tst.l   d0
        bne     free_soft
        addq.w  #1,d7
        cmp.w   #16,d7
        blo.s   next_case
        moveq   #0,d7
.clear_case:
        move.l  chip(pc),a4
        bsr     check_clear
        tst.l   d0
        bne     free_soft
        move.l  soft(pc),a4
        bsr     check_clear
        tst.l   d0
        bne     free_soft
        addq.w  #1,d7
        cmp.w   #2,d7
        blo.s   .clear_case
        st      complete
free_soft:
        move.l  4.w,a6
        move.l  soft(pc),a1
        move.l  #BUFSIZE,d0
        jsr     LVO_FREEMEM(a6)
free_chip:
        move.l  4.w,a6
        move.l  chip(pc),a1
        move.l  #BUFSIZE,d0
        jsr     LVO_FREEMEM(a6)
close_gfx:
        move.l  4.w,a6
        move.l  gfxbase(pc),a1
        jsr     LVO_CLOSELIBRARY(a6)
        tst.b   complete
        beq.s   fail
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

; d7 selects small/large, solid/patterned operations, and full/partial plane masks.
exercise:
        move.l  a4,a0
        move.w  #BUFSIZE/4-1,d0
.fill:
        move.l  #$0f0f0f0f,(a0)+
        dbra    d0,.fill
        move.l  gfxbase(pc),a6
        lea     bitmap(pc),a0
        moveq   #4,d0
        move.l  #128,d1
        moveq   #16,d2
        jsr     -390(a6)           ; InitBitMap
        lea     bitmap+bm_Planes(pc),a0
        lea     GUARD(a4),a1
        moveq   #3,d0
.planes:
        move.l  a1,(a0)+
        lea     PLSIZE(a1),a1
        dbra    d0,.planes
        lea     rport(pc),a1
        jsr     -198(a6)           ; InitRastPort
        lea     bitmap(pc),a0
        move.l  a0,rport+rp_BitMap
        moveq   #1,d0
        jsr     LVO_SETAPEN(a6)
        moveq   #0,d0
        jsr     LVO_SETBPEN(a6)
        moveq   #JAM1,d0
        jsr     LVO_SETDRMD(a6)
        btst    #3,d7
        beq.s   .mask
        move.b  #5,rport+rp_Mask
.mask:
        move.w  d7,d0
        lsr.w   #1,d0
        and.w   #3,d0
        move.w  d0,operation
        lsl.w   #2,d0
        lea     minterms(pc),a0
        move.l  0(a0,d0.w),rport+MINT
        clr.l   rport+rp_AreaPtrn
        cmp.w   #2,operation
        blo.s   .bounds
        lea     patterns(pc),a0
        move.l  a0,rport+rp_AreaPtrn
        move.b  #1,rport+rp_AreaPtSz
        cmp.w   #3,operation
        bne.s   .bounds
        move.b  #-1,rport+rp_AreaPtSz
.bounds:
        move.w  #20,xmax
        move.w  #3,ymax
        btst    #0,d7
        beq.s   .draw
        move.w  #120,xmax
        move.w  #13,ymax
.draw:
        lea     rport(pc),a0
        lea     saved_rport(pc),a1
        moveq   #rp_SIZEOF/4-1,d0
.save:
        move.l  (a0)+,(a1)+
        dbra    d0,.save
        lea     rport(pc),a1
        moveq   #3,d0
        moveq   #2,d1
        move.w  xmax(pc),d2
        move.w  ymax(pc),d3
        jsr     LVO_RECTFILL(a6)
        jsr     -228(a6)           ; WaitBlit
        lea     rport(pc),a0
        lea     saved_rport(pc),a1
        moveq   #rp_SIZEOF/4-1,d0
.state:
        cmpm.l  (a0)+,(a1)+
        bne     .bad
        dbra    d0,.state
        move.l  a4,a0
        lea     GUARD+4*PLSIZE(a4),a1
        moveq   #GUARD/4-1,d0
.guards:
        cmp.l   #$0f0f0f0f,(a0)+
        bne     .bad
        cmp.l   #$0f0f0f0f,(a1)+
        bne     .bad
        dbra    d0,.guards
        lea     GUARD(a4),a2
        moveq   #0,d3             ; plane
.plane:
        moveq   #0,d5             ; row
.row:
        moveq   #0,d4             ; column
.pixel:
        moveq   #0,d6
        btst    #2,d4             ; initial authored stripes: four clear pixels, four set pixels
        sne     d6
        cmp.w   #3,d4
        blo     .check
        cmp.w   xmax(pc),d4
        bhi     .check
        cmp.w   #2,d5
        blo     .check
        cmp.w   ymax(pc),d5
        bhi     .check
        btst    #3,d7
        beq.s   .operation
        btst    #0,d3             ; mask 5 leaves planes 1 and 3 untouched
        bne     .check
.operation:
        move.w  operation(pc),d0
        beq.s   .selective_xor
        cmp.w   #1,d0
        bne.s   .pattern
        tst.w   d3
        beq.s   .clear
        cmp.w   #1,d3
        beq.s   .invert
        cmp.w   #2,d3
        beq.s   .check
        st      d6
        bra.s   .check
.clear:
        moveq   #0,d6
        bra.s   .check
.selective_xor:
        tst.w   d3
        bne.s   .check
.invert:
        not.b   d6
        bra.s   .check
.pattern:
        lea     patterns(pc),a0
        cmp.w   #3,d0
        bne.s   .pattern_row
        move.w  d3,d0
        lsl.w   #2,d0
        adda.w  d0,a0
.pattern_row:
        moveq   #1,d0
        and.w   d5,d0
        add.w   d0,d0
        move.w  0(a0,d0.w),d0
        moveq   #15,d1
        move.w  d4,d2
        and.w   #15,d2
        sub.w   d2,d1
        btst    d1,d0
        sne     d0
        tst.w   d3
        beq.s   .copy
        cmp.w   #1,d3
        bne.s   .pattern_modify
        not.b   d0
.copy:
        move.b  d0,d6
        bra.s   .check
.pattern_modify:
        cmp.w   #2,d3
        bne.s   .pattern_set
        not.b   d0
        and.b   d0,d6
        bra.s   .check
.pattern_set:
        or.b    d0,d6
.check:
        move.w  d5,d0
        lsl.w   #4,d0
        move.w  d4,d1
        lsr.w   #3,d1
        add.w   d1,d0
        move.w  d4,d1
        not.w   d1
        and.w   #7,d1
        move.b  0(a2,d0.w),d0
        btst    d1,d0
        sne     d0
        cmp.b   d0,d6
        bne.s   .bad
        addq.w  #1,d4
        cmp.w   #128,d4
        blo     .pixel
        addq.w  #1,d5
        cmp.w   #16,d5
        blo     .row
        lea     PLSIZE(a2),a2
        addq.w  #1,d3
        cmp.w   #4,d3
        blo     .plane
        moveq   #0,d0
        rts
.bad:
        moveq   #1,d0
        rts
; SetRast ignores cached minterms; the text clear calls select BgPen and rebuild pen state.
check_clear:
        lea     bitmap+bm_Planes(pc),a0
        lea     GUARD(a4),a1
        moveq   #3,d0
.planes:
        move.l  a1,(a0)+
        lea     PLSIZE(a1),a1
        dbra    d0,.planes
        move.l  gfxbase(pc),a6
        lea     rport(pc),a1
        st      rp_Mask(a1)
        clr.l   rp_AreaPtrn(a1)
        moveq   #1,d0
        jsr     LVO_SETAPEN(a6)
        moveq   #2,d0
        jsr     LVO_SETBPEN(a6)
        moveq   #JAM2,d0
        jsr     LVO_SETDRMD(a6)
        move.l  #$aaaaaaaa,MINT(a1)
        move.l  #$aaaaaaaa,MINT+4(a1)
        moveq   #3,d0
        jsr     -234(a6)           ; SetRast
        moveq   #12,d0
        move.w  rp_TxBaseline(a1),d1
        addq.w  #1,d1
        jsr     LVO_MOVE(a6)
        tst.w   d7
        bne.s   .screen
        jsr     -42(a6)            ; ClearEOL
        bra.s   .state
.screen:
        jsr     -48(a6)            ; ClearScreen
.state:
        cmp.b   #1,rp_FgPen(a1)
        bne     .bad
        cmp.b   #2,rp_BgPen(a1)
        bne     .bad
        cmp.b   #JAM2,rp_DrawMode(a1)
        bne     .bad
        cmp.l   #$ca3a0a0a,MINT(a1)
        bne     .bad
        cmp.l   #$0a0a0a0a,MINT+4(a1)
        bne     .bad
        cmp.w   #12,rp_cp_x(a1)
        bne     .bad
        move.w  rp_TxBaseline(a1),d0
        addq.w  #1,d0
        cmp.w   rp_cp_y(a1),d0
        bne     .bad
        moveq   #0,d5
.row:
        moveq   #0,d4
.pixel:
        moveq   #3,d6
        tst.w   d5
        beq.s   .read
        cmp.w   rport+rp_TxHeight(pc),d5
        bls.s   .line
        tst.w   d7
        beq.s   .read
        bra.s   .background
.line:
        cmp.w   #12,d4
        blo.s   .read
.background:
        moveq   #2,d6
.read:
        move.w  d4,d0
        move.w  d5,d1
        lea     rport(pc),a1
        jsr     -318(a6)
        cmp.l   d6,d0
        bne.s   .bad
        addq.w  #1,d4
        cmp.w   #128,d4
        blo.s   .pixel
        addq.w  #1,d5
        cmp.w   #16,d5
        blo.s   .row
        moveq   #0,d0
        rts
.bad:
        moveq   #1,d0
        rts
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
minterms:
        dc.b    $6a,$aa,$aa,$aa
        dc.b    $0a,$6a,$aa,$fa
        dc.b    $ca,$3a,$2a,$ea
        dc.b    $ca,$3a,$2a,$ea
        even
patterns:
        dc.w    $f0f0,$0f0f,$cccc,$3333,$aaaa,$5555,$ff00,$00ff
gfxname: dc.b "graphics.library",0
ok:     dc.b "RECTPENS OK",10,"RECTPENS END",10,0
error:  dc.b "RECTPENS FAIL",10,"RECTPENS END",10,0
        even
gfxbase: dc.l 0
chip:   dc.l 0
soft:   dc.l 0
operation: dc.w 0
xmax:   dc.w 0
ymax:   dc.w 0
complete: dc.w 0
bitmap: dcb.b bm_SIZEOF,0
rport:  dcb.b rp_SIZEOF,0
saved_rport: dcb.b rp_SIZEOF,0
