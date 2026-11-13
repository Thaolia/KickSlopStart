; tests/layerbak_probe.s - contents of SMART layer backups after layer operations (implementation track, authored).
; Free memory is first filled with $A5 (allocate, fill, free), so a backup that a ROM leaves partly unwritten shows
; up. On a private 320 x 200, 2-plane BitMap with its own Layer_Info, two overlapping SMART layers A (drawn in three
; pens) and B; after each step, "LB <step> <hash of A> <hash of B> <plane 0 sum> <plane 1 sum>": the hashes run
; ReadPixel over every pixel of the layer (hidden parts are read from their backups). Steps:
;   1 setup   2 SizeLayer(A, +40, +30) (enlargement partly under B)   3 MoveLayer(A, +7, +3)
;   4 BehindLayer(A) + UpfrontLayer(A)   5 MoveLayer(B, -30, -10) with almost no free memory (backups fail)
;   6 MoveLayer(A, +2, +1) with memory back (old hidden parts without backup)   then "LB END".
; Run by tests/layerbak_probe.sh; two ROMs must agree.
; LVOs: AutoDocs offsets (exec AllocMem -198, FreeMem -210, AvailMem -216, OpenLibrary -552; layers
; CreateUpfrontLayer -36, UpfrontLayer -48, BehindLayer -54, MoveLayer -60, SizeLayer -66, DeleteLayer -90,
; NewLayerInfo -144, DisposeLayerInfo -150; graphics RectFill -306, ReadPixel -318, SetAPen -342, InitBitMap -390).

W       EQU 320
H       EQU 200
PLSZ    EQU W/8*H

        section code,code
start:
        move.l  ($4).w,a6
        move.w  #372,$DFF032         ; SERPER 9600 bauds
        lea     gfxname(pc),a1
        moveq   #0,d0
        jsr     -552(a6)
        move.l  d0,gfxb
        beq     .ret
        lea     laysname(pc),a1
        moveq   #0,d0
        jsr     -552(a6)
        move.l  d0,layb
        beq     .ret
        bsr     poison
        move.l  #2*PLSZ,d0
        move.l  #$10002,d1           ; MEMF_CHIP|MEMF_CLEAR
        jsr     -198(a6)
        move.l  d0,planes
        beq     .ret
        move.l  gfxb(pc),a6
        lea     bm(pc),a0
        moveq   #2,d0
        move.l  #W,d1
        move.l  #H,d2
        jsr     -390(a6)             ; InitBitMap
        lea     bm(pc),a0
        move.l  planes(pc),d0
        move.l  d0,8(a0)
        add.l   #PLSZ,d0
        move.l  d0,12(a0)
        move.l  layb(pc),a6
        jsr     -144(a6)             ; NewLayerInfo
        move.l  d0,li
        beq     .ret

        moveq   #20,d0
        moveq   #20,d1
        move.l  #149,d2
        moveq   #99,d3
        bsr     newlayer
        move.l  d0,la
        beq     .ret
        move.l  #100,d0
        moveq   #60,d1
        move.l  #229,d2
        move.l  #139,d3
        bsr     newlayer
        move.l  d0,lb
        beq     .ret
        move.l  la(pc),a0            ; A: pen 1 everywhere, pens 2 and 3 in bands crossing the hidden part
        moveq   #1,d4
        moveq   #0,d0
        moveq   #0,d1
        move.l  #129,d2
        moveq   #79,d3
        bsr     fill
        move.l  la(pc),a0
        moveq   #2,d4
        moveq   #10,d0
        moveq   #5,d1
        move.l  #125,d2
        moveq   #30,d3
        bsr     fill
        move.l  la(pc),a0
        moveq   #3,d4
        moveq   #60,d0
        moveq   #20,d1
        move.l  #120,d2
        moveq   #75,d3
        bsr     fill
        move.l  lb(pc),a0            ; B: pen 2 frame band
        moveq   #2,d4
        moveq   #4,d0
        moveq   #4,d1
        moveq   #60,d2
        moveq   #40,d3
        bsr     fill
        moveq   #1,d7
        bsr     report

        move.l  la(pc),a1
        moveq   #40,d0
        moveq   #30,d1
        moveq   #-66,d5              ; SizeLayer
        bsr     layop
        moveq   #2,d7
        bsr     report

        move.l  la(pc),a1
        moveq   #7,d0
        moveq   #3,d1
        moveq   #-60,d5              ; MoveLayer
        bsr     layop
        moveq   #3,d7
        bsr     report

        move.l  la(pc),a1
        moveq   #-54,d5              ; BehindLayer
        bsr     layop
        move.l  la(pc),a1
        moveq   #-48,d5              ; UpfrontLayer
        bsr     layop
        moveq   #4,d7
        bsr     report

        bsr     grab                 ; almost no free memory
        move.l  lb(pc),a1
        moveq   #-30,d0
        moveq   #-10,d1
        moveq   #-60,d5
        bsr     layop
        bsr     release
        moveq   #5,d7
        bsr     report

        move.l  la(pc),a1
        moveq   #2,d0
        moveq   #1,d1
        moveq   #-60,d5
        bsr     layop
        moveq   #6,d7
        bsr     report

        move.l  layb(pc),a6
        move.l  lb(pc),a1
        suba.l  a0,a0
        jsr     -90(a6)              ; DeleteLayer
        move.l  la(pc),a1
        suba.l  a0,a0
        jsr     -90(a6)
        move.l  li(pc),a0
        jsr     -150(a6)             ; DisposeLayerInfo
        move.l  ($4).w,a6
        move.l  planes(pc),a1
        move.l  #2*PLSZ,d0
        jsr     -210(a6)
        lea     m_end(pc),a0
        bsr     puts
.ret:
        moveq   #0,d0
        rts

; newlayer(d0-d3 = bounds) -> d0 = SMART layer, upfront.
newlayer:
        move.l  layb(pc),a6
        move.l  li(pc),a0
        lea     bm(pc),a1
        moveq   #2,d4                ; LAYERSMART
        suba.l  a2,a2
        jmp     -36(a6)

; layop(a1 = layer, d0/d1 = dx/dy, d5 = layers LVO).
layop:
        move.l  layb(pc),a6
        suba.l  a0,a0
        jmp     0(a6,d5.w)

; fill(a0 = layer, d4 = pen, d0-d3 = rectangle in layer coordinates). Changes d0-d1/a0-a1/a6.
fill:
        movem.l d0-d3,-(sp)
        move.l  12(a0),a1            ; lr_rp
        move.l  a1,-(sp)
        move.l  gfxb(pc),a6
        move.l  d4,d0
        jsr     -342(a6)             ; SetAPen
        move.l  (sp)+,a1
        movem.l (sp)+,d0-d3
        jmp     -306(a6)             ; RectFill

; report(d7 = step): "LB <step> <hash A> <hash B> <plane sums>".
report:
        lea     m_lb(pc),a0
        bsr     puts
        move.l  d7,d0
        bsr     phex8
        move.l  la(pc),a0
        bsr     hash
        bsr     phex8
        move.l  lb(pc),a0
        bsr     hash
        bsr     phex8
        move.l  planes(pc),a0
        bsr     psum
        bsr     phex8
        bsr     psum
        bsr     phex8
        moveq   #10,d1
        bra     putc

; hash(a0 = layer) -> d0 = hash of ReadPixel over the whole layer.
hash:
        movem.l d2-d7/a2,-(sp)
        move.l  a0,a2
        moveq   #0,d7
        moveq   #0,d5                ; y
.hy:
        move.w  22(a2),d3            ; MaxY
        sub.w   18(a2),d3            ; - MinY
        cmp.w   d3,d5
        bgt.s   .hr
        moveq   #0,d4                ; x
.hx:
        move.w  20(a2),d3            ; MaxX
        sub.w   16(a2),d3
        cmp.w   d3,d4
        bgt.s   .hn
        move.l  12(a2),a1
        move.l  d4,d0
        move.l  d5,d1
        move.l  gfxb(pc),a6
        jsr     -318(a6)             ; ReadPixel
        rol.l   #5,d7
        add.l   d0,d7
        addq.w  #1,d4
        bra.s   .hx
.hn:
        addq.w  #1,d5
        bra.s   .hy
.hr:
        move.l  d7,d0
        movem.l (sp)+,d2-d7/a2
        rts

; psum(a0 = plane) -> d0 = sum of its longs, a0 past it.
psum:
        moveq   #0,d0
        move.w  #PLSZ/4-1,d1
.ps:
        add.l   (a0)+,d0
        dbra    d1,.ps
        rts

; poison: every free block of 1 KB or more filled with $A5, then freed.
poison:
        bsr.s   grab
        move.l  blocks(pc),a0
.po_b:
        cmpa.w  #0,a0
        beq.s   release
        move.l  4(a0),d0
        lsr.l   #2,d0
        subq.l  #3,d0
        lea     8(a0),a1
.po_f:
        move.l  #$A5A5A5A5,(a1)+
        subq.l  #1,d0
        bne.s   .po_f
        move.l  (a0),a0
        bra.s   .po_b

; grab: allocates free memory in decreasing blocks down to 1 KB (list at blocks: next, size).
grab:
        move.l  ($4).w,a6
        move.l  #$40000,d2
.gr_lp:
        move.l  d2,d0
        moveq   #1,d1                ; MEMF_PUBLIC
        jsr     -198(a6)
        tst.l   d0
        beq.s   .gr_half
        move.l  d0,a0
        move.l  blocks(pc),(a0)
        move.l  d2,4(a0)
        move.l  a0,blocks
        bra.s   .gr_lp
.gr_half:
        lsr.l   #1,d2
        cmp.l   #1024,d2
        bhs.s   .gr_lp
        rts

; release: frees the list at blocks.
release:
        move.l  ($4).w,a6
.re_lp:
        move.l  blocks(pc),d0
        beq.s   .re_r
        move.l  d0,a1
        move.l  (a1),blocks
        move.l  4(a1),d0
        jsr     -210(a6)
        bra.s   .re_lp
.re_r:
        rts

puts:
        move.b  (a0)+,d1
        beq.s   .pr
        bsr.s   putc
        bra.s   puts
.pr:
        rts
phex8:
        movem.l d0-d2,-(sp)
        moveq   #' ',d1
        bsr.s   putc
        moveq   #7,d2
.h:     rol.l   #4,d0
        move.w  d0,d1
        and.w   #15,d1
        move.b  digits(pc,d1.w),d1
        bsr.s   putc
        dbra    d2,.h
        movem.l (sp)+,d0-d2
        rts
digits: dc.b    "0123456789ABCDEF"
putc:
        move.w  d0,-(sp)
.w:     move.w  $DFF018,d0           ; SERDATR: wait for TBE
        btst    #13,d0
        beq.s   .w
        and.w   #$FF,d1
        or.w    #$100,d1             ; stop bit
        move.w  d1,$DFF030           ; SERDAT
        move.w  (sp)+,d0
        rts

        cnop    0,4
gfxb:   dc.l    0
layb:   dc.l    0
planes: dc.l    0
li:     dc.l    0
la:     dc.l    0
lb:     dc.l    0
blocks: dc.l    0
bm:     ds.b    40
gfxname:  dc.b  "graphics.library",0
laysname: dc.b  "layers.library",0
m_lb:   dc.b    "LB",0
m_end:  dc.b    "LB END",10,0
