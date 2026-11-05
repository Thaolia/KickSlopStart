; Native regression: drawable memory must reach FreeMem only after pending blitter DMA completes.
; Public graphics/Intuition LVOs and a temporary Exec SetFunction observer; no ROM-derived code/data.
                include "exec.i"
                include "graphics.i"
                include "intuition.i"
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
        lea     intname(pc),a1
        moveq   #0,d0
        jsr     LVO_OPENLIBRARY(a6)
        move.l  d0,intbase
        beq     fail
        jsr     LVO_FORBID(a6)
        lea     free_hook(pc),a0
        move.l  a0,d0
        move.l  #LVO_FREEMEM,a0
        move.l  a6,a1
        jsr     -420(a6)           ; SetFunction(library a1, offset a0, function d0)
        move.l  d0,oldfree

        move.l  gfxbase(pc),a6
        move.w  #512,d0
        move.w  #1024,d1
        jsr     -492(a6)           ; AllocRaster
        move.l  d0,watched
        beq     restore_fail
        moveq   #32,d2             ; 32 words x 1024 rows, OCS zero height encoding
        bsr     start_dma
        move.l  watched(pc),a0
        move.w  #512,d0
        move.w  #1024,d1
        jsr     -498(a6)           ; FreeRaster
        cmp.w   #1,observed
        bne     restore_fail

        clr.w   observed
        move.l  intbase(pc),a6
        lea     new_screen(pc),a0
        jsr     -198(a6)           ; OpenScreen
        move.l  d0,a3
        tst.l   d0
        beq     restore_fail
        move.l  SC_BITMAP+bm_Planes(a3),watched
        move.l  gfxbase(pc),a6
        move.w  #(200*64+40),d2    ; pending write into the actual 640x200 screen plane
        bsr     start_dma
        move.l  intbase(pc),a6
        move.l  a3,a0
        jsr     -66(a6)            ; CloseScreen
        cmp.w   #1,observed
        bne     restore_fail
        bra.s   restore
restore_fail:
        st      bad
restore:
        move.l  gfxbase(pc),a6
        jsr     -228(a6)           ; drain even a failing run before restoring the allocator vector
        move.l  4.w,a6
        move.l  oldfree(pc),d0
        move.l  #LVO_FREEMEM,a0
        move.l  a6,a1
        jsr     -420(a6)
        jsr     LVO_PERMIT(a6)
        tst.b   bad
        bne.s   fail
        lea     ok(pc),a0
        bsr     puts
        movem.l (sp)+,d2-d7/a2-a6
        moveq   #0,d0
        rts
fail:
        lea     error(pc),a0
        bsr     puts
.stop:  bra.s   .stop

; A long hardware clear ensures the release call encounters actual outstanding DMA.
start_dma:
        jsr     -456(a6)           ; OwnBlitter
        lea     CUSTOM,a0
        move.w  #$0100,BLT_CON0(a0)
        clr.w   BLT_CON1(a0)
        clr.w   BLT_DMOD(a0)
        move.l  watched(pc),BLT_DPT(a0)
        move.w  d2,BLT_SIZE(a0)
        jmp     -462(a6)           ; DisownBlitter leaves the operation pending

; Observe allocator handoff, then drain on a failing ROM to prevent corrupting its free-list metadata.
free_hook:
        movem.l d0-d1/a0,-(sp)
        move.l  a1,d1
        cmp.l   watched(pc),d1
        bne.s   .delegate
        addq.w  #1,observed
        lea     CUSTOM,a0
        btst    #6,BLT_DMACONR(a0)
        btst    #6,BLT_DMACONR(a0)
        beq.s   .delegate
        st      bad
.wait:  btst    #6,BLT_DMACONR(a0)
        bne.s   .wait
.delegate:
        movem.l (sp)+,d0-d1/a0
        move.l  oldfree(pc),-(sp)
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
new_screen:
        dc.w    0,0,640,200,2
        dc.b    0,1
        dc.w    $8000,$000f        ; HIRES, CUSTOMSCREEN
        dc.l    0,0,0,0
gfxname: dc.b   "graphics.library",0
intname: dc.b   "intuition.library",0
ok:     dc.b    "RASTERFREE OK",10,"RASTERFREE END",10,0
error:  dc.b    "RASTERFREE FAIL",10,"RASTERFREE END",10,0
        even
gfxbase: dc.l   0
intbase: dc.l   0
oldfree: dc.l   0
watched: dc.l   0
observed: dc.w  0
bad:    dc.b    0,0
