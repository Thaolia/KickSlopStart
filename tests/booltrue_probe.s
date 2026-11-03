; booltrue_probe.s - black-box probe: the full 32-bit D0 returned by the BOOL functions of layers.library and of
; the graphics.library regions (implementation track, our own test program; run on any Kickstart 1.3).
; Every call is followed by one serial-free line on the CLI output:
;   "BT <name> <d0 in hex, 8 digits>"
; Regions: OrRectRegion, XorRectRegion, ClearRectRegion, AndRectRegion (void in the AutoDocs, printed anyway),
; OrRegionRegion, AndRegionRegion, XorRegionRegion. Layers, on a 320 x 200 one-plane BitMap with two simple
; layers L1 (10,10)-(100,80) and L2 (50,40)-(200,150): BehindLayer(L2), UpfrontLayer(L2), UpfrontLayer(L2) again
; (already in front), MoveLayer(L1,5,5), SizeLayer(L1,10,10), MoveLayerInFrontOf(L1,L2), the same again (already
; just in front), BeginUpdate(L1) (then EndUpdate), AttemptLockLayerRom(L1) (then UnlockLayerRom), DeleteLayer(L2),
; DeleteLayer(L1). Ends with "BT END".
; Build: vasmm68k_mot -Fhunkexe -kick1hunks -o booltrue_probe tests/booltrue_probe.s

        section code,code

start:
        move.l  ($4).w,a6
        lea     gfxname(pc),a1
        moveq   #0,d0
        jsr     -552(a6)             ; OpenLibrary
        lea     gfxbase(pc),a0
        move.l  d0,(a0)
        lea     layname(pc),a1
        moveq   #0,d0
        jsr     -552(a6)
        lea     laybase(pc),a0
        move.l  d0,(a0)
        lea     dosname(pc),a1
        moveq   #0,d0
        jsr     -552(a6)
        lea     dosbase(pc),a0
        move.l  d0,(a0)
        tst.l   gfxbase
        beq     bail
        tst.l   laybase
        beq     bail

        ; ---------------- regions ----------------
        move.l  gfxbase(pc),a6
        jsr     -516(a6)             ; NewRegion
        move.l  d0,d7                ; d7 = R1
        beq     bail
        jsr     -516(a6)
        move.l  d0,d6                ; d6 = R2
        beq     bail
        move.l  d7,a0
        lea     rect_a(pc),a1
        jsr     -510(a6)             ; OrRectRegion(R1, A)
        lea     n_orrect(pc),a0
        bsr     report
        move.l  d7,a0
        lea     rect_b(pc),a1
        jsr     -558(a6)             ; XorRectRegion(R1, B)
        lea     n_xorrect(pc),a0
        bsr     report
        move.l  d7,a0
        lea     rect_c(pc),a1
        jsr     -522(a6)             ; ClearRectRegion(R1, C)
        lea     n_clrrect(pc),a0
        bsr     report
        move.l  d7,a0
        lea     rect_a(pc),a1
        jsr     -504(a6)             ; AndRectRegion(R1, A)
        lea     n_andrect(pc),a0
        bsr     report
        move.l  d6,a0
        lea     rect_b(pc),a1
        jsr     -510(a6)             ; R2 = B
        move.l  d7,a0
        move.l  d6,a1
        jsr     -612(a6)             ; OrRegionRegion(R1, R2)
        lea     n_orreg(pc),a0
        bsr     report
        move.l  d7,a0
        move.l  d6,a1
        jsr     -624(a6)             ; AndRegionRegion(R1, R2)
        lea     n_andreg(pc),a0
        bsr     report
        move.l  d7,a0
        move.l  d6,a1
        jsr     -618(a6)             ; XorRegionRegion(R1, R2)
        lea     n_xorreg(pc),a0
        bsr     report
        move.l  d7,a0
        jsr     -534(a6)             ; DisposeRegion
        move.l  d6,a0
        jsr     -534(a6)

        ; ---------------- layers ----------------
        lea     bitmap(pc),a0
        moveq   #1,d0
        move.l  #320,d1
        move.l  #200,d2
        jsr     -390(a6)             ; InitBitMap(bm, 1, 320, 200)
        move.l  #320,d0
        move.l  #200,d1
        jsr     -492(a6)             ; AllocRaster
        tst.l   d0
        beq     bail
        lea     bitmap+8(pc),a0
        move.l  d0,(a0)              ; bm_Planes[0]
        move.l  laybase(pc),a6
        jsr     -144(a6)             ; NewLayerInfo
        move.l  d0,d5                ; d5 = Layer_Info
        beq     bail
        moveq   #10,d0
        moveq   #10,d1
        moveq   #100,d2
        moveq   #80,d3
        bsr     newlayer
        move.l  d0,d7                ; d7 = L1
        beq     bail
        moveq   #50,d0
        moveq   #40,d1
        move.l  #200,d2
        move.l  #150,d3
        bsr     newlayer
        move.l  d0,d6                ; d6 = L2
        beq     bail
        sub.l   a0,a0
        move.l  d6,a1
        jsr     -54(a6)              ; BehindLayer(L2)
        lea     n_behind(pc),a0
        bsr     report
        sub.l   a0,a0
        move.l  d6,a1
        jsr     -48(a6)              ; UpfrontLayer(L2)
        lea     n_upfront(pc),a0
        bsr     report
        sub.l   a0,a0
        move.l  d6,a1
        jsr     -48(a6)              ; UpfrontLayer(L2), already in front
        lea     n_upfront2(pc),a0
        bsr     report
        sub.l   a0,a0
        move.l  d7,a1
        moveq   #5,d0
        moveq   #5,d1
        jsr     -60(a6)              ; MoveLayer(L1, 5, 5)
        lea     n_move(pc),a0
        bsr     report
        sub.l   a0,a0
        move.l  d7,a1
        moveq   #10,d0
        moveq   #10,d1
        jsr     -66(a6)              ; SizeLayer(L1, 10, 10)
        lea     n_size(pc),a0
        bsr     report
        move.l  d7,a0
        move.l  d6,a1
        jsr     -168(a6)             ; MoveLayerInFrontOf(L1, L2)
        lea     n_infront(pc),a0
        bsr     report
        move.l  d7,a0
        move.l  d6,a1
        jsr     -168(a6)             ; again: L1 is already just in front of L2
        lea     n_infront2(pc),a0
        bsr     report
        move.l  d7,a0
        jsr     -78(a6)              ; BeginUpdate(L1)
        lea     n_begin(pc),a0
        bsr     report
        move.l  d7,a0
        moveq   #1,d0
        jsr     -84(a6)              ; EndUpdate(L1, TRUE)
        move.l  gfxbase(pc),a6
        move.l  a5,-(sp)
        move.l  d7,a5
        jsr     -654(a6)             ; AttemptLockLayerRom(L1)
        move.l  (sp)+,a5
        lea     n_attempt(pc),a0
        bsr     report
        tst.l   d0
        beq.s   .nolock
        move.l  a5,-(sp)
        move.l  d7,a5
        jsr     -438(a6)             ; UnlockLayerRom(L1)
        move.l  (sp)+,a5
.nolock:
        move.l  laybase(pc),a6
        sub.l   a0,a0
        move.l  d6,a1
        jsr     -90(a6)              ; DeleteLayer(L2)
        lea     n_del2(pc),a0
        bsr     report
        sub.l   a0,a0
        move.l  d7,a1
        jsr     -90(a6)              ; DeleteLayer(L1)
        lea     n_del1(pc),a0
        bsr     report
        move.l  d5,a0
        jsr     -150(a6)             ; DisposeLayerInfo
        move.l  gfxbase(pc),a6
        move.l  bitmap+8(pc),a0
        move.l  #320,d0
        move.l  #200,d1
        jsr     -498(a6)             ; FreeRaster
        lea     n_end(pc),a0
        bsr     say
        moveq   #0,d0
        rts
bail:
        lea     n_fail(pc),a0
        bsr     say
        moveq   #20,d0
        rts

; newlayer(d0-d3 = box, d5 = Layer_Info, a6 = LayersBase) -> d0 = simple layer in front.
newlayer:
        movem.l d4/a2,-(sp)
        move.l  d5,a0
        lea     bitmap(pc),a1
        moveq   #1,d4                ; LAYERSIMPLE
        sub.l   a2,a2
        jsr     -36(a6)              ; CreateUpfrontLayer
        movem.l (sp)+,d4/a2
        rts

; report(a0 = name ended by 0, d0 = value): writes "BT <name> <d0>". Keeps d0 and every register but a0/a1/d1.
report:
        movem.l d0/d2-d3/a2/a6,-(sp)
        lea     line(pc),a1
        move.b  #'B',(a1)+
        move.b  #'T',(a1)+
        move.b  #' ',(a1)+
.rp_name:
        move.b  (a0)+,(a1)+
        bne.s   .rp_name
        move.b  #' ',-1(a1)
        moveq   #8-1,d1
.rp_hex:
        rol.l   #4,d0
        move.w  d0,d2
        and.w   #$F,d2
        move.b  digits(pc,d2.w),(a1)+
        dbra    d1,.rp_hex
        move.b  #10,(a1)+
        clr.b   (a1)
        lea     line(pc),a0
        bsr.s   say
        movem.l (sp)+,d0/d2-d3/a2/a6
        rts
digits: dc.b    "0123456789ABCDEF"

; say(a0 = text ended by 0): Write(Output(), text). Keeps every register but a0/a1/d0/d1.
say:
        movem.l d2-d3/a6,-(sp)
        move.l  a0,d2
        moveq   #-1,d3
.sy_len:
        addq.l  #1,d3
        tst.b   (a0)+
        bne.s   .sy_len
        move.l  dosbase(pc),a6
        jsr     -60(a6)              ; Output
        move.l  d0,d1
        jsr     -48(a6)              ; Write
        movem.l (sp)+,d2-d3/a6
        rts

gfxbase: dc.l    0
laybase: dc.l    0
dosbase: dc.l    0
bitmap:  dcb.b   40,0
rect_a:  dc.w    0,0,99,49
rect_b:  dc.w    50,20,149,79
rect_c:  dc.w    10,10,29,29
line:    dcb.b   48,0
gfxname: dc.b    "graphics.library",0
layname: dc.b    "layers.library",0
dosname: dc.b    "dos.library",0
n_orrect:   dc.b "OrRectRegion",0
n_xorrect:  dc.b "XorRectRegion",0
n_clrrect:  dc.b "ClearRectRegion",0
n_andrect:  dc.b "AndRectRegion",0
n_orreg:    dc.b "OrRegionRegion",0
n_andreg:   dc.b "AndRegionRegion",0
n_xorreg:   dc.b "XorRegionRegion",0
n_behind:   dc.b "BehindLayer",0
n_upfront:  dc.b "UpfrontLayer",0
n_upfront2: dc.b "UpfrontLayer-again",0
n_move:     dc.b "MoveLayer",0
n_size:     dc.b "SizeLayer",0
n_infront:  dc.b "MoveLayerInFrontOf",0
n_infront2: dc.b "MoveLayerInFrontOf-again",0
n_begin:    dc.b "BeginUpdate",0
n_attempt:  dc.b "AttemptLockLayerRom",0
n_del2:     dc.b "DeleteLayer-L2",0
n_del1:     dc.b "DeleteLayer-L1",0
n_end:      dc.b "BT END",10,0
n_fail:     dc.b "BT FAIL",10,0
        even
