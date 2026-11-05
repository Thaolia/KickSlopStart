; Authored regression/benchmark for our ROM, using public NDK structures and LVOs.
; CHIP rendering must match the CPU fallback in non-DMA memory, including guards.
                include "exec.i"
                include "graphics.i"
BUFSIZE         EQU 65536
PLSIZE          EQU 21000
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
        bne     fail                 ; requires slow or fast RAM for the reference
        lea     vbint(pc),a1
        lea     vbcode(pc),a0
        move.l  a0,18(a1)
        moveq   #5,d0
        jsr     LVO_ADDINTSERVER(a6)
        lea     startmsg(pc),a0
        bsr     puts
        clr.w   variant
.variant:
        bsr     reset
        move.l  chip(pc),a0
        lea     bmchip(pc),a2
        lea     rpchip(pc),a3
        bsr     setup
        move.l  soft(pc),a0
        lea     bmsoft(pc),a2
        lea     rpsoft(pc),a3
        bsr     setup
        cmp.w   #5,variant
        bne.s   .depth_ready
        move.b  #2,bmchip+bm_Depth
        move.b  #2,bmsoft+bm_Depth
.depth_ready:
        moveq   #0,d7
.mode:
        cmp.w   #5,variant
        bne.s   .free
        bsr     busy
.free:
        lea     rpchip(pc),a2
        bsr     exercise
        cmp.w   #5,variant
        bne.s   .released
        bsr     unbusy
.released:
        lea     rpsoft(pc),a2
        bsr     exercise
        bsr     compare
        addq.w  #1,d7
        cmp.w   #8,d7
        bne.s   .mode
        addq.w  #1,variant
        cmp.w   #7,variant
        bne     .variant
        bsr     limits
        bsr     bitmap_checks
        bsr     clock_checks
        bsr     rectangle_modes
        clr.w   variant
        move.l  chip(pc),a0
        lea     bmchip(pc),a2
        lea     rpchip(pc),a3
        bsr     setup
        move.l  soft(pc),a0
        lea     bmsoft(pc),a2
        lea     rpsoft(pc),a3
        bsr     setup
        lea     okmsg(pc),a0
        bsr     puts
        moveq   #0,d7
.bench:
        lea     rpchip(pc),a2
        bsr     measure
        move.l  d0,d6
        lea     rpsoft(pc),a2
        bsr     measure
        move.l  d0,d5
        bsr     compare
        lea     linemsg(pc),a0
        tst.w   d7
        beq.s   .label
        lea     fillmsg(pc),a0
        cmp.w   #1,d7
        beq.s   .label
        lea     clearmsg(pc),a0
        cmp.w   #2,d7
        beq.s   .label
        lea     shortmsg(pc),a0
        cmp.w   #3,d7
        beq.s   .label
        lea     areamsg(pc),a0
.label:
        bsr     puts
        move.l  d6,d0
        bsr     hex
        moveq   #' ',d0
        bsr     putc
        move.l  d5,d0
        bsr     hex
        moveq   #10,d0
        bsr     putc
        addq.w  #1,d7
        cmp.w   #5,d7
        bne.s   .bench
        lea     endmsg(pc),a0
        bsr     puts
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
        movem.l (sp)+,d2-d7/a2-a6
        moveq   #0,d0
        rts
fail:
        lea     failmsg(pc),a0
        bsr     puts
        move.w  #$f00,$dff180
.stop:  bra.s   .stop

reset:
        move.l  chip(pc),a0
        move.l  soft(pc),a1
        move.w  #BUFSIZE/4-1,d0
.loop: move.l  #$a55aa55a,(a0)+
        move.l  #$a55aa55a,(a1)+
        dbra    d0,.loop
        rts

; Model ownership by another task while scheduling is forbidden. The drawing call must neither wait nor disown it.
busy:
        move.l  4.w,a6
        jsr     LVO_FORBID(a6)
        move.l  gfxbase(pc),a0
        lea     gb_BlitSem(a0),a0
        tst.l   40(a0)
        bne     fail
        move.l  #-1,40(a0)
        move.w  #1,14(a0)
        clr.w   44(a0)
        rts
unbusy:
        move.l  gfxbase(pc),a0
        lea     gb_BlitSem(a0),a0
        cmp.l   #-1,40(a0)
        bne     fail
        cmp.w   #1,14(a0)
        bne     fail
        tst.w   44(a0)
        bne     fail
        clr.l   40(a0)
        clr.w   14(a0)
        move.w  #-1,44(a0)
        move.l  4.w,a6
        jmp     LVO_PERMIT(a6)

; Also exercise a disabled non-CHIP plane and layer offsets/ClipRects.
setup:
        addq.l  #8,a0
        cmp.w   #1,variant
        bne.s   .even
        addq.l  #1,a0
.even:
        move.l  a0,bm_Planes(a2)
        lea     PLSIZE(a0),a0
        move.l  a0,bm_Planes+4(a2)
        lea     PLSIZE(a0),a0
        move.l  a0,bm_Planes+8(a2)
        move.w  #80,bm_BytesPerRow(a2)
        cmp.w   #2,variant
        bne.s   .stride
        addq.w  #1,bm_BytesPerRow(a2)
.stride:
        move.w  #256,bm_Rows(a2)
        move.b  #3,bm_Depth(a2)
        move.l  gfxbase(pc),a6
        move.l  a3,a1
        jsr     -198(a6)             ; InitRastPort
        move.l  a2,rp_BitMap(a3)
        cmp.w   #3,variant
        bne.s   .layer
        move.l  soft(pc),d0
        add.l   #8+PLSIZE,d0
        move.l  d0,bm_Planes+4(a2)  ; disabled plane must not disqualify DMA
.layer:
        cmp.w   #4,variant
        beq.s   .make_layer
        cmp.w   #6,variant
        bne     .done
.make_layer:
        lea     layerchip(pc),a0
        lea     clipschip(pc),a1
        lea     bmchip(pc),a4
        cmpa.l  a4,a2
        beq.s   .chosen
        lea     layersoft(pc),a0
        lea     clipssoft(pc),a1
.chosen:
        move.l  a0,rp_Layer(a3)
        move.l  a1,8(a0)
        move.w  #13,16(a0)
        move.w  #7,18(a0)
        move.w  #626,20(a0)
        move.w  #247,22(a0)
        lea     28(a1),a4
        move.l  a4,(a1)
        move.w  #13,16(a1)
        move.w  #7,18(a1)
        move.w  #319,20(a1)
        move.w  #247,22(a1)
        move.w  #340,16(a4)         ; gap exercises SIMPLE hidden clipping
        move.w  #7,18(a4)
        move.w  #626,20(a4)
        move.w  #247,22(a4)
        cmp.w   #6,variant
        bne.s   .lock
        move.w  #127,22(a0)
        move.w  #127,22(a1)         ; visible rows end before the backup storage
        move.w  #70,22(a4)
        move.l  #1,8(a4)           ; hidden SMART ClipRect, distinct from the layer
        move.w  #336,24(a4)        ; word-aligned backup origin
        move.w  #7,26(a4)
        move.l  a0,-(sp)
        lea     backupchip(pc),a0
        lea     bmchip(pc),a1
        cmpa.l  a1,a2
        beq.s   .backup
        lea     backupsoft(pc),a0
.backup:
        move.l  a0,12(a4)
        move.w  #40,bm_BytesPerRow(a0)
        move.w  #64,bm_Rows(a0)
        move.b  #3,bm_Depth(a0)
        moveq   #2,d0
        lea     bm_Planes(a2),a1
        lea     bm_Planes(a0),a4
.bp:
        move.l  (a1)+,d1
        add.l   #12800,d1
        move.l  d1,(a4)+
        dbra    d0,.bp
        move.l  (sp)+,a0
.lock:
        lea     72(a0),a0
        move.l  4.w,a6
        jsr     LVO_INITSEMAPHORE(a6)
.done:
        rts

exercise:
        move.l  gfxbase(pc),a6
        move.l  a2,a1
        move.w  d7,d0
        jsr     -354(a6)             ; SetDrMd: all modes including INVERSVID
        moveq   #5,d0
        jsr     -342(a6)
        moveq   #2,d0
        jsr     -348(a6)
        move.b  #5,rp_Mask(a2)
        cmp.w   #5,variant
        bne.s   .mask_ready
        move.b  #3,rp_Mask(a2)
.mask_ready:
        lea     endpoints(pc),a3
        moveq   #NEND-1,d4
.lines:
        move.l  a2,a1
        move.w  #320,d0
        moveq   #120,d1
        jsr     -240(a6)
        movem.w (a3)+,d0-d1
        jsr     -246(a6)
        move.w  #320,d0             ; continuation, shared vertex in COMPLEMENT
        moveq   #120,d1
        jsr     -246(a6)
        dbra    d4,.lines
        moveq   #16,d0
        moveq   #16,d1
        jsr     -240(a6)
        move.w  #280,d0
        moveq   #100,d1
        jsr     -246(a6)
        move.w  #340,d0
        moveq   #12,d1
        jsr     -240(a6)
        move.w  #590,d0
        moveq   #48,d1
        jsr     -246(a6)
        move.w  #$a35c,rp_LinePtrn(a2)
        or.w    #2,rp_Flags(a2)     ; ONE_DOT and patterned fallback
        moveq   #10,d0
        moveq   #10,d1
        jsr     -240(a6)
        move.w  #620,d0
        move.w  #200,d1
        jsr     -246(a6)
        move.w  #$ffff,rp_LinePtrn(a2)
        and.w   #$fffd,rp_Flags(a2)
        lea     rectangles(pc),a3
        moveq   #NRECT-1,d4
.rects:
        movem.w (a3)+,d0-d3
        jsr     -306(a6)
        dbra    d4,.rects
        lea     pattern(pc),a0      ; patterned rectangles retain their CPU semantics
        move.l  a0,rp_AreaPtrn(a2)
        move.b  #1,rp_AreaPtSz(a2)
        moveq   #17,d0
        moveq   #7,d1
        move.w  #607,d2
        move.w  #213,d3
        jsr     -306(a6)
        clr.l   rp_AreaPtrn(a2)
        clr.b   rp_AreaPtSz(a2)
        rts

; OCS encodings (64 words, 1024 rows), wider/taller CPU fallback and line length modulo 1024.
limits:
        clr.w   variant
        move.l  chip(pc),a0
        lea     bmchip(pc),a2
        lea     rpchip(pc),a3
        bsr     setup
        move.l  soft(pc),a0
        lea     bmsoft(pc),a2
        lea     rpsoft(pc),a3
        bsr     setup
        lea     geometries(pc),a3
        moveq   #NGEOM-1,d7
.geometry:
        move.w  (a3),bmchip+bm_BytesPerRow
        move.w  (a3)+,bmsoft+bm_BytesPerRow
        move.w  (a3),bmchip+bm_Rows
        move.w  (a3)+,bmsoft+bm_Rows
        move.b  #1,bmchip+bm_Depth
        move.b  #1,bmsoft+bm_Depth
        lea     rpchip(pc),a2
        bsr.s   .draw
        lea     rpsoft(pc),a2
        bsr.s   .draw
        bsr     compare
        dbra    d7,.geometry
        rts
.draw:
        move.l  gfxbase(pc),a6
        move.l  a2,a1
        moveq   #2,d0
        jsr     -354(a6)
        moveq   #0,d0
        moveq   #0,d1
        move.l  rp_BitMap(a2),a0
        move.w  bm_BytesPerRow(a0),d2
        lsl.w   #3,d2
        subq.w  #1,d2
        move.w  bm_Rows(a0),d3
        subq.w  #1,d3
        jsr     -306(a6)
        moveq   #0,d0
        moveq   #0,d1
        jsr     -240(a6)
        move.l  rp_BitMap(a2),a0
        move.w  bm_BytesPerRow(a0),d0
        lsl.w   #3,d0
        subq.w  #1,d0
        moveq   #3,d1
        jsr     -246(a6)
        rts

compare:
        move.l  gfxbase(pc),a6
        jsr     -228(a6)             ; WaitBlit, also tests back-to-back drawing
        move.l  chip(pc),a0
        move.l  soft(pc),a1
        move.w  #BUFSIZE-1,d0
.loop: cmpm.b  (a0)+,(a1)+
        bne     fail
        dbra    d0,.loop
        lea     rpchip(pc),a0
        lea     rpsoft(pc),a1
        moveq   #15,d0              ; pens, flags, phase and current point
.state: move.b  24(a0),d1
        cmp.b   24(a1),d1
        bne     fail
        addq.l  #1,a0
        addq.l  #1,a1
        dbra    d0,.state
        rts

; Expected whole-buffer fingerprints come from an independent pixel oracle: initialize every byte A5/5A,
; apply the Boolean operation to x=11..619, y=9..229 in planes 0 and 2, then ROL5/add each big-endian long.
bitmap_checks:
        clr.w   variant
        move.l  chip(pc),a0
        lea     bmchip(pc),a2
        lea     rpchip(pc),a3
        bsr     setup
        move.l  soft(pc),a0
        lea     bmsoft(pc),a2
        lea     rpsoft(pc),a3
        bsr     setup
        lea     bitmap_expected(pc),a3
        moveq   #3,d4
.operation:
        bsr     reset
        lea     bmchip(pc),a0
        bsr.s   .apply
        lea     bmsoft(pc),a0
        bsr.s   .apply
        bsr     compare
        move.l  chip(pc),a0
        moveq   #0,d0
        move.w  #BUFSIZE/4-1,d1
.hash:
        rol.l   #5,d0
        add.l   (a0)+,d0
        dbra    d1,.hash
        cmp.l   2(a3),d0
        bne     fail
        addq.l  #6,a3
        dbra    d4,.operation
        rts
.apply:
        movem.l d2-d7,-(sp)
        move.l  a0,a1
        moveq   #0,d0
        moveq   #0,d1
        moveq   #11,d2
        moveq   #9,d3
        move.w  #609,d4
        move.w  #221,d5
        move.w  (a3),d6
        moveq   #5,d7
        move.l  gfxbase(pc),a6
        jsr     -30(a6)
        cmp.w   #2,d0
        bne     fail
        movem.l (sp)+,d2-d7
        rts

measure:
        cmp.w   #3,d7
        bhs     clock_measure
        move.l  gfxbase(pc),a6
        move.l  a2,a1
        moveq   #0,d0
        jsr     -354(a6)
        moveq   #5,d0
        jsr     -342(a6)
        st      rp_Mask(a2)
        bsr     now
        move.l  d0,d4
        moveq   #31,d3
.loop:
        tst.w   d7
        bne.s   .fill
        moveq   #10,d0
        moveq   #10,d1
        jsr     -240(a6)
        move.w  #620,d0
        move.w  #230,d1
        jsr     -246(a6)
        bra.s   .next
.fill:
        cmp.w   #1,d7
        bne.s   .clear
        movem.l d3-d4,-(sp)
        moveq   #11,d0
        moveq   #11,d1
        move.w  #619,d2
        move.w  #229,d3
        jsr     -306(a6)
        movem.l (sp)+,d3-d4
        bra.s   .next
.clear:
        movem.l d2-d7,-(sp)
        move.l  rp_BitMap(a2),a0
        move.l  a0,a1
        moveq   #11,d0
        moveq   #11,d1
        moveq   #11,d2
        moveq   #11,d3
        move.w  #609,d4
        move.w  #219,d5
        moveq   #0,d6
        moveq   #-1,d7
        jsr     -30(a6)             ; the same source=destination clear used by layers' lr_clear
        cmp.w   #3,d0
        bne     fail
        movem.l (sp)+,d2-d7
.next: dbra    d3,.loop
        jsr     -228(a6)
        bsr     now
        sub.l   d4,d0
        rts

; Differential coverage for the small two-plane strokes and masks used by analog instruments.
; Upstream's solid-rectangle minterms include INVERSVID and both pens. Cover all four plane-bit pairs
; in every mode on a rectangle large enough for DMA, comparing full buffers and state with the CPU engine.
rectangle_modes:
        clr.w   variant
        move.l  chip(pc),a0
        lea     bmchip(pc),a2
        lea     rpchip(pc),a3
        bsr     setup
        move.l  soft(pc),a0
        lea     bmsoft(pc),a2
        lea     rpsoft(pc),a3
        bsr     setup
        moveq   #0,d7
.mode:
        moveq   #0,d6
.pens:
        bsr     reset
        lea     rpchip(pc),a2
        bsr.s   .draw
        lea     rpsoft(pc),a2
        bsr.s   .draw
        bsr     compare
        addq.w  #1,d6
        cmp.w   #4,d6
        bne.s   .pens
        addq.w  #1,d7
        cmp.w   #8,d7
        bne.s   .mode
        rts
.draw:
        move.l  gfxbase(pc),a6
        move.l  a2,a1
        move.b  #3,rp_Mask(a2)
        move.w  d7,d0
        jsr     -354(a6)
        move.w  d6,d0
        jsr     -342(a6)
        lea     .background(pc),a0
        moveq   #0,d0
        move.b  0(a0,d6.w),d0
        jsr     -348(a6)
        moveq   #11,d0
        moveq   #9,d1
        moveq   #74,d2
        moveq   #48,d3
        jsr     -306(a6)
        rts
.background: dc.b 0,2,1,3

clock_checks:
        clr.w   variant
        move.l  chip(pc),a0
        lea     bmchip(pc),a2
        lea     rpchip(pc),a3
        bsr     setup
        move.l  soft(pc),a0
        lea     bmsoft(pc),a2
        lea     rpsoft(pc),a3
        bsr     setup
        moveq   #0,d7
.mode:
        bsr     reset
        tst.w   d7
        bne.s   .no_own
        move.l  gfxbase(pc),a6
        jsr     -456(a6)           ; a caller-owned blitter lease must survive nested drawing
.no_own:
        move.l  4.w,a0
        move.b  EB_TDNEST(a0),clock_nest
        lea     rpchip(pc),a2
        bsr     clock_exercise
        move.l  4.w,a0
        move.b  EB_TDNEST(a0),d0
        cmp.b   clock_nest(pc),d0
        bne     fail
        tst.w   d7
        bne.s   .no_disown
        cmp.w   #1,gb_BlitSem+14(a6)
        bne     fail
        move.l  4.w,a0
        move.l  EB_THISTASK(a0),d0
        cmp.l   gb_BlitSem+40(a6),d0
        bne     fail
        jsr     -462(a6)
.no_disown:
        lea     rpsoft(pc),a2
        bsr     clock_exercise
        bsr     compare
        addq.w  #1,d7
        cmp.w   #8,d7
        bne.s   .mode
        bsr     clock_clipchecks
        rts
clock_port:
        move.l  rp_BitMap(a2),a0
        move.b  #2,bm_Depth(a0)
        lea     clock_trchip(pc),a0
        lea     clock_aichip(pc),a1
        lea     clock_vecchip(pc),a3
        move.l  chip(pc),d0
        lea     rpchip(pc),a6
        cmpa.l  a6,a2
        beq.s   .chip
        lea     clock_trsoft(pc),a0
        lea     clock_aisoft(pc),a1
        lea     clock_vecsoft(pc),a3
        move.l  soft(pc),d0
.chip:
        add.l   #42008,d0
        move.l  d0,(a0)
        move.l  #20000,4(a0)
        move.l  a0,rp_TmpRas(a2)
        move.l  a1,rp_AreaInfo(a2)
        move.l  gfxbase(pc),a6
        rts
clock_exercise:
        bsr     clock_port
        move.l  a2,a1
        move.w  d7,d0
        jsr     -354(a6)
        move.w  d7,d0
        and.w   #3,d0
        jsr     -342(a6)
        moveq   #3,d0
        jsr     -348(a6)
        move.b  #3,rp_Mask(a2)
        btst    #1,d7
        beq.s   .aligned
        move.l  rp_TmpRas(a2),a0
        addq.l  #1,(a0)            ; byte-addressable CPU mask fallback
.aligned:
        bsr     clock_strokes
        moveq   #0,d4
.triangle:
        bsr     clock_initarea
        moveq   #13,d0
        add.w   d4,d0
        moveq   #10,d1
        jsr     -252(a6)
        move.w  #140,d0
        add.w   d4,d0
        moveq   #23,d1
        jsr     -258(a6)
        moveq   #15,d0
        add.w   d4,d0
        moveq   #120,d1
        jsr     -258(a6)
        jsr     -264(a6)
        tst.l   d0
        bne     fail
        addq.w  #1,d4
        cmp.w   #16,d4
        bne.s   .triangle
        ; Legacy mixed ellipse/line lists can have odd crossing parity and must retain the CPU fill rule.
        bsr     clock_initarea
        moveq   #80,d0
        moveq   #40,d1
        moveq   #15,d2
        moveq   #15,d3
        jsr     -186(a6)
        moveq   #100,d0
        moveq   #80,d1
        jsr     -258(a6)
        moveq   #110,d0
        moveq   #110,d1
        jsr     -258(a6)
        move.w  #150,d0
        moveq   #100,d1
        moveq   #30,d2
        moveq   #20,d3
        jsr     -186(a6)
        jsr     -264(a6)
        tst.l   d0
        bne     fail
        moveq   #15,d4
.shift:
        move.l  rp_TmpRas(a2),a0
        move.l  (a0),a0
        moveq   #0,d0
        moveq   #18,d1
        moveq   #64,d2
        add.w   d4,d2
        move.w  #132,d3
        move.l  d4,-(sp)
        moveq   #127,d4
        moveq   #16,d5
        jsr     -36(a6)
        move.l  (sp)+,d4
        dbra    d4,.shift
        rts
clock_strokes:
        movem.l d2-d7/a3,-(sp)
        lea     clock_lengths(pc),a3
        moveq   #13,d4
.length:
        moveq   #0,d5
.octant:
        moveq   #0,d6
        move.b  (a3),d6
        move.w  d6,d2
        addq.w  #1,d2
        lsr.w   #1,d2
        move.w  d6,d3
        btst    #2,d5
        bne.s   .steep
        exg     d2,d3
.steep:
        btst    #0,d5
        beq.s   .right
        neg.w   d2
.right:
        btst    #1,d5
        beq.s   .down
        neg.w   d3
.down:
        add.w   clock_center(pc),d2
        add.w   #120,d3
        move.l  a2,a1
        move.w  clock_center(pc),d0
        moveq   #120,d1
        jsr     -240(a6)
        move.w  d2,d0
        move.w  d3,d1
        jsr     -246(a6)
        move.w  clock_center(pc),d0            ; reverse continuation tests shared points and pattern state
        moveq   #120,d1
        jsr     -246(a6)
        addq.w  #1,d5
        cmp.w   #8,d5
        bne.s   .octant
        addq.l  #1,a3
        dbra    d4,.length
        movem.l (sp)+,d2-d7/a3
        rts
clock_initarea:
        move.l  a3,-(sp)
        move.l  rp_AreaInfo(a2),a0
        lea     clock_vecchip(pc),a1
        lea     rpchip(pc),a3
        cmpa.l  a3,a2
        beq.s   .chip
        lea     clock_vecsoft(pc),a1
.chip:
        moveq   #40,d0
        jsr     -282(a6)
        move.l  a2,a1
        move.l  (sp)+,a3
        rts
clock_clipchecks:
        bsr     reset
        lea     rpchip(pc),a2
        bsr     .port
        lea     rpsoft(pc),a2
        bsr     .port
        bsr     compare
        move.w  #320,clock_center
        rts
.port:
        bsr     clock_port
        move.l  a2,a1
        moveq   #0,d0
        jsr     -354(a6)
        moveq   #1,d0
        jsr     -342(a6)
        move.b  #3,rp_Mask(a2)
        lea     layerchip(pc),a3
        lea     clipschip(pc),a4
        lea     backupchip(pc),a5
        lea     rpchip(pc),a0
        cmpa.l  a0,a2
        beq.s   .chosen
        lea     layersoft(pc),a3
        lea     clipssoft(pc),a4
        lea     backupsoft(pc),a5
.chosen:
        move.l  a3,rp_Layer(a2)
        move.l  a4,8(a3)
        clr.l   16(a3)
        move.w  #639,20(a3)
        move.w  #255,22(a3)
        move.w  #$10,30(a3)        ; a client-owned BeginUpdate surface
        clr.l   32(a3)
        clr.l   44(a3)
        clr.l   (a4)
        clr.l   8(a4)
        clr.l   12(a4)
        move.w  #400,16(a4)
        move.w  #100,18(a4)
        move.w  #500,20(a4)
        move.w  #140,22(a4)
        move.l  4.w,a6
        lea     72(a3),a0
        jsr     LVO_INITSEMAPHORE(a6)
        lea     72(a3),a0
        jsr     LVO_OBTAINSEMAPHORE(a6)
        move.l  gfxbase(pc),a6
        ; Wholly outside the damaged rectangle: raster and client lock must remain unchanged.
        bsr     clock_initarea
        moveq   #20,d0
        moveq   #20,d1
        jsr     -252(a6)
        moveq   #60,d0
        moveq   #20,d1
        jsr     -258(a6)
        moveq   #40,d0
        moveq   #60,d1
        jsr     -258(a6)
        jsr     -264(a6)
        tst.l   d0
        bne     fail
        move.l  rp_BitMap(a2),a0
        move.l  bm_Planes(a0),a0
        move.w  #80*256/4-1,d0
.unchanged:
        cmp.l   #$a55aa55a,(a0)+
        bne     fail
        dbra    d0,.unchanged
        ; Partly intersecting the update must still paint the visible part and clip its left edge.
        bsr     .rectangle
        move.l  a2,a1
        move.w  #410,d0
        moveq   #120,d1
        jsr     -318(a6)
        cmp.w   #1,d0
        bne     fail
        move.l  rp_BitMap(a2),a0
        move.l  bm_Planes(a0),a0
        cmp.w   #$a55a,9648(a0)    ; x384..399, outside the damaged rectangle
        bne     fail
        move.w  #450,clock_center
        bsr     clock_strokes
        moveq   #3,d4
.axis:
        move.l  a2,a1
        move.w  #450,d0
        moveq   #120,d1
        jsr     -240(a6)
        move.w  #450,d0
        moveq   #120,d1
        lea     clock_clip_axes(pc),a0
        move.w  d4,d2
        lsl.w   #2,d2
        add.w   0(a0,d2.w),d0
        add.w   2(a0,d2.w),d1
        jsr     -246(a6)
        dbra    d4,.axis
        cmp.w   #1,72+14(a3)
        bne     fail
        move.l  rp_AreaInfo(a2),a0
        tst.w   16(a0)
        bne     fail
        move.l  4.w,a6
        lea     72(a3),a0
        jsr     LVO_RELEASESEMAPHORE(a6)
        clr.l   rp_Layer(a2)
        move.l  gfxbase(pc),a6
        rts
.rectangle:
        bsr     clock_initarea
        move.w  #390,d0
        moveq   #110,d1
        jsr     -252(a6)
        move.w  #430,d0
        moveq   #110,d1
        jsr     -258(a6)
        move.w  #430,d0
        move.w  #130,d1
        jsr     -258(a6)
        move.w  #390,d0
        move.w  #130,d1
        jsr     -258(a6)
        jsr     -264(a6)
        tst.l   d0
        bne     fail
        rts
clock_polygon:
        movem.l d2-d7/a3,-(sp)
        bsr     clock_initarea
        lea     clock_polygon_points(pc),a3
        movem.w (a3)+,d0-d1
        jsr     -252(a6)
        moveq   #16,d4
.edge:
        movem.w (a3)+,d0-d1
        jsr     -258(a6)
        dbra    d4,.edge
        jsr     -264(a6)
        tst.l   d0
        bne     fail
        movem.l (sp)+,d2-d7/a3
        rts
clock_measure:
        movem.l d2-d7/a3,-(sp)
        bsr     clock_port
        move.l  a2,a1
        moveq   #0,d0
        jsr     -354(a6)
        moveq   #2,d0
        jsr     -342(a6)
        move.b  #3,rp_Mask(a2)
        bsr     now
        move.l  d0,d4
        cmp.w   #3,d7
        bne.s   .areas
        move.w  #227,d3
.stroke:
        moveq   #0,d5
        move.w  d3,d5
        divu    #26,d5
        swap    d5
        and.w   #$ffff,d5
        addq.w  #2,d5
        moveq   #0,d6
        move.w  d3,d6
        mulu    #7,d6
        divu    #26,d6
        swap    d6
        and.w   #$ffff,d6
        addq.w  #1,d6
        btst    #0,d3
        beq.s   .right
        neg.w   d5
.right:
        btst    #1,d3
        beq.s   .down
        neg.w   d6
.down:
        move.l  a2,a1
        move.w  #320,d0
        moveq   #120,d1
        jsr     -240(a6)
        move.w  #320,d0
        add.w   d5,d0
        moveq   #120,d1
        add.w   d6,d1
        jsr     -246(a6)
        dbra    d3,.stroke
        bra.s   .stop
.areas:
        moveq   #12,d3
.area:
        bsr     clock_polygon
        dbra    d3,.area
.stop:
        jsr     -228(a6)
        bsr     now
        sub.l   d4,d0
        movem.l (sp)+,d2-d7/a3
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
.loop: move.b  (a0)+,d0
        beq.s   .done
        bsr.s   putc
        bra.s   .loop
.done: move.l  (sp)+,d0
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
.loop: rol.l   #4,d2
        moveq   #15,d0
        and.b   d2,d0
        move.b  digits(pc,d0.w),d0
        bsr.s   putc
        dbra    d1,.loop
        movem.l (sp)+,d0-d2
        rts
digits: dc.b    "0123456789ABCDEF"
gfxname: dc.b   "graphics.library",0
startmsg: dc.b  "DRAWBLIT START",10,0
okmsg: dc.b     "DRAWBLIT PIXELS OK",10,0
linemsg: dc.b   "DRAWBLIT LINE ",0
fillmsg: dc.b   "DRAWBLIT FILL ",0
clearmsg: dc.b  "DRAWBLIT CLEAR ",0
shortmsg: dc.b  "DRAWBLIT SHORT ",0
areamsg: dc.b   "DRAWBLIT AREA ",0
endmsg: dc.b    "DRAWBLIT END",10,0
failmsg: dc.b   "DRAWBLIT FAIL",10,0
        even
endpoints:
        dc.w 610,200, 400,240, 240,240, 30,200
        dc.w 30,40, 240,0, 400,0, 610,40
        dc.w 610,120, 30,120, 320,240, 320,0
        dc.w 0,0, 640,256, -30,30, 400,300
        dc.w 324,122, 316,122, 324,118, 316,118
NEND EQU (*-endpoints)/4
rectangles:
        dc.w 11,11,619,229, 0,0,639,255, 7,20,7,220
        dc.w 15,3,16,240, 17,1,623,230, -20,-10,36,36
        dc.w 60,12,75,220, 1,15,14,250, 639,250,680,280
NRECT EQU (*-rectangles)/8
pattern: dc.w $aaaa,$5555
clock_center: dc.w 320
clock_nest: dc.b 0,0
clock_clip_axes: dc.w 1023,0,-1023,0,0,1023,0,-1023
clock_lengths: dc.b 2,3,4,7,8,15,16,27,28,31,32,33,56,63
        even
; Authored symmetric eighteen-vertex instrument face, independent of the Workbench Clock executable.
clock_polygon_points:
        dc.w 80,8, 105,10, 127,18, 145,32, 155,49, 155,67, 145,84, 127,98, 105,106
        dc.w 80,108, 55,106, 33,98, 15,84, 5,67, 5,49, 15,32, 33,18, 55,10
bitmap_expected:
        dc.w $000f
        dc.l $49097298
        dc.w $005f
        dc.l $f0ac93aa
        dc.w $00af
        dc.l $427a9576
        dc.w $00ff
        dc.l $0e4b71d0
geometries: dc.w 128,128, 130,128, 2,1024, 2,1025
NGEOM EQU (*-geometries)/4
chip:   dc.l 0
soft:   dc.l 0
gfxbase: dc.l 0
frames: dc.l 0
variant: dc.w 0
vbint:  ds.b 22
bmchip: ds.b bm_SIZEOF
bmsoft: ds.b bm_SIZEOF
rpchip: ds.b rp_SIZEOF
rpsoft: ds.b rp_SIZEOF
layerchip: ds.b 160
layersoft: ds.b 160
clipschip: ds.b 56
clipssoft: ds.b 56
backupchip: ds.b bm_SIZEOF
backupsoft: ds.b bm_SIZEOF
clock_trchip: ds.l 2
clock_trsoft: ds.l 2
clock_aichip: ds.b 24
clock_aisoft: ds.b 24
clock_vecchip: ds.b 200
clock_vecsoft: ds.b 200
