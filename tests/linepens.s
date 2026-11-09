; SPDX-License-Identifier: MIT
; Stored Draw minterms must drive CPU, rectangle and line-mode paths, including XOR cursor erasure.
                include "exec.i"
                include "graphics.i"
BUFSIZE         EQU 8192
PLSIZE          EQU 1536
MINT            EQU 40              ; public RastPort.minterms[8]
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
        lea     line_cases(pc),a4
        move.w  #LINE_CASES-1,d7
.case:
        move.l  chip(pc),a3
        bsr     exercise
        move.l  soft(pc),a3
        bsr     exercise
        lea     28(a4),a4
        dbra    d7,.case
        move.l  4.w,a6
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
exercise:
        move.l  a3,a0
        move.l  #$2468ace1,d0
        move.w  #BUFSIZE/4-1,d1
.fill:
        move.l  d0,(a0)+
        add.l   #$01030507,d0
        dbra    d1,.fill
        move.l  gfxbase(pc),a6
        lea     rport(pc),a1
        jsr     -198(a6)
        lea     bitmap(pc),a0
        move.l  a0,rport+rp_BitMap
        move.w  #16,bm_BytesPerRow(a0)
        move.w  #96,bm_Rows(a0)
        move.b  3(a4),bm_Depth(a0)
        lea     bm_Planes(a0),a0
        lea     16(a3),a1
        adda.w  4(a4),a1
        moveq   #4,d0
.planes:
        move.l  a1,(a0)+
        lea     PLSIZE(a1),a1
        dbra    d0,.planes
        tst.w   6(a4)
        beq.s   .pens
        lea     layer(pc),a0
        move.l  a0,rport+rp_Layer
        lea     clip(pc),a1
        move.l  a1,8(a0)
        move.w  #5,16(a0)
        move.w  #3,18(a0)
        move.w  #124,20(a0)
        move.w  #94,22(a0)
        lea     72(a0),a0
        move.l  4.w,a6
        jsr     LVO_INITSEMAPHORE(a6)
.pens:
        move.l  gfxbase(pc),a6
        lea     rport(pc),a1
        moveq   #31,d0
        jsr     LVO_SETAPEN(a6)
        moveq   #0,d0
        jsr     LVO_SETBPEN(a6)
        move.w  (a4),d0
        jsr     LVO_SETDRMD(a6)
        move.b  11(a4),rp_Mask(a1)
        move.w  8(a4),rp_LinePtrn(a1)
        move.l  16(a4),MINT(a1)
        move.l  20(a4),MINT+4(a1)
        lea     saved_rp(pc),a0
        moveq   #rp_SIZEOF/4-1,d0
.save:
        move.l  (a1)+,(a0)+
        dbra    d0,.save
        move.w  #55,saved_rp+rp_cp_x
        move.w  #42,saved_rp+rp_cp_y
        and.w   #$fffe,saved_rp+rp_Flags
        move.b  #15,saved_rp+31
        move.w  12(a4),d6
        subq.w  #1,d6
.repeat:
        lea     line_points(pc),a2
        move.w  #LINE_COUNT-1,d5
.line:
        lea     rport(pc),a1
        movem.w (a2)+,d0-d1
        jsr     LVO_MOVE(a6)
        movem.w (a2)+,d0-d1
        jsr     LVO_DRAW(a6)
        dbra    d5,.line
        dbra    d6,.repeat
        jsr     -228(a6)
        lea     rport(pc),a0
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
        cmp.l   24(a4),d0
        bne     fail
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
gfxname: dc.b "graphics.library",0
ok: dc.b "LINEPENS OK",10,"LINEPENS END",10,0
error: dc.b "LINEPENS FAIL",10,"LINEPENS END",10,0
        even
        include "linepens_cases.i"
chip: dc.l 0
soft: dc.l 0
gfxbase: dc.l 0
bitmap: dcb.b bm_SIZEOF,0
rport: dcb.b rp_SIZEOF,0
saved_rp: dcb.b rp_SIZEOF,0
layer: dcb.b lr_SIZEOF,0
clip:
        dc.l 0,0,0,0
        dc.w 5,3,124,94
        dc.l 0
