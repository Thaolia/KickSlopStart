; src/intuition/pointer.s - Intuition pointer accumulator (live M6R wiring of the requester).
;
; THE missing link of the clickable requester. gameport.device produces RAWMOUSE InputEvents with RELATIVE
; deltas (movement per frame); req_input_handler hit-tests ABSOLUTE coordinates. pointer_input_handler
; bridges them: an input.device handler of HIGH pri (50 > 0 of the requester -> Enqueue places it BEFORE in the chain)
; which, for each RAWMOUSE, integrates ie_X/ie_Y (signed relative deltas) into the absolute position PTR_X/PTR_Y
; (clamped to the screen bounds), then REWRITES ie_X/ie_Y as absolute. The following handlers (req_input_handler,
; UNCHANGED) therefore see an absolute position. This is exactly what Intuition's input handler does (pointer
; tracking); the faithful home of PTR_X/PTR_Y is IB_MOUSEX/IB_MOUSEY of IntuitionBase (here we use the low-RAM proof
; globals, like REQ_HIT). IMPLEMENTATION track ("clean"): NDK inputevent.i + intuition. NO ROM reading.

                include "exec.i"
                include "intuition.i"
                include "graphics.i"

                xdef    pointer_input_handler
                xdef    it_ptrinit
                xdef    it_ptrmoved
                xdef    ptr_image
                xref    it_event             ; screens.s: buttons and movements -> input task
                xref    it_keyin
                xref    it_tickin
                xref    it_diskin

; pointer_input_handler(a0 = InputEvent list, a1 = is_Data): input.device handler (pri 50). For each
; RAWMOUSE: PTR += signed relative (ie_X, ie_Y), clamp [0, PTR_?MAX-1], rewrites ie_X/ie_Y as absolute. Returns d0 =
; list (pass-through). Preserves d2-d7/a2-a6 (saves d2/d3/d4/a3).
pointer_input_handler:
                movem.l d2/d3/d4/a3,-(sp)
                move.l  a0,d2                ; return list (pass-through)
                move.l  a0,a3                ; walk
.pih_loop:
                move.l  a3,d0
                beq     .pih_done
                cmp.b   #IECLASS_RAWKEY,IE_CLASS(a3)
                bne.s   .pih_tick
                jsr     it_keyin             ; keyboard of an active text gadget
                bra.s   .pih_next
.pih_tick:
                cmp.b   #IECLASS_TIMER,IE_CLASS(a3)
                bne.s   .pih_disk
                jsr     it_tickin            ; INTUITICKS (input task)
                bra.s   .pih_next
.pih_disk:
                cmp.b   #IECLASS_DISKREMOVED,IE_CLASS(a3)
                beq.s   .pih_dk
                cmp.b   #IECLASS_DISKINSERTED,IE_CLASS(a3)
                bne.s   .pih_mouse
.pih_dk:
                jsr     it_diskin            ; DISKINSERTED / DISKREMOVED (input task)
                bra.s   .pih_next
.pih_mouse:
                cmp.b   #IECLASS_RAWMOUSE,IE_CLASS(a3)
                bne.s   .pih_next
                bsr     ptr_ticks            ; deltas scaled to the Preferences speed
                move.w  PTR_X,d3             ; X: absolute position += relative delta
                add.w   IE_X(a3),d3
                ifeq    PTR_NO_CLAMP
                bpl.s   .pih_xlo
                moveq   #0,d3                ; low clamp (< 0 -> 0)
.pih_xlo:
                cmp.w   #PTR_XMAX,d3
                blt.s   .pih_xhi
                move.w  #PTR_XMAX-1,d3       ; high clamp (>= XMAX -> XMAX-1)
.pih_xhi:
                endc                         ; RED PTR_NO_CLAMP: no clipping -> off-screen position possible
                move.w  d3,PTR_X
                move.w  d3,IE_X(a3)          ; rewritten as absolute for the following handlers
                move.w  PTR_Y,d4             ; Y: same
                add.w   IE_Y(a3),d4
                ifeq    PTR_NO_CLAMP
                bpl.s   .pih_ylo
                moveq   #0,d4
.pih_ylo:
                cmp.w   #PTR_YMAX,d4
                blt.s   .pih_yhi
                move.w  #PTR_YMAX-1,d4
.pih_yhi:
                endc
                move.w  d4,PTR_Y
                move.w  d4,IE_Y(a3)
                bsr     it_ptrmoved          ; pointer sprite + IB_MOUSEX/Y
                move.w  IE_CODE(a3),d0       ; buttons and movements -> intuition input task
                jsr     it_event
.pih_next:
                move.l  IE_NEXTEVENT(a3),a3
                bra     .pih_loop
.pih_done:
                move.l  d2,d0                ; list (pass-through)
                movem.l (sp)+,d2/d3/d4/a3
                rts

; ptr_ticks(a3 = RAWMOUSE event): as in intuition 1.3, one mouse count is worth one hires pixel (half a line
; in Y) divided by the Preferences PointerTicks; since our positions are in lores pixels and lines, each delta is
; divided by 2 x PointerTicks, the remainder being carried over to the following events (IB_PREMX/Y). Nothing before
; intuition init. Clobbers d0/d1/a0/a1.
ptr_ticks:
                move.l  INT_IBASE,d0
                beq.s   .pt_ret
                move.l  d0,a1
                move.w  IB_PREFS+PF_PTRTICKS(a1),d1
                ble.s   .pt_ret
                add.w   d1,d1                ; d1 = divisor
                lea     IE_X(a3),a0
                lea     IB_PREMX(a1),a1
                bsr.s   .pt_axis
                lea     IE_Y(a3),a0
                addq.l  #IB_PREMY-IB_PREMX,a1
.pt_axis:                            ; (a0) = delta, (a1) = remainder: (delta + remainder) = q x d1 + r, 0 <= r < d1
                move.w  (a0),d0
                add.w   (a1),d0
                ext.l   d0
                divs    d1,d0
                swap    d0                   ; d0.w = remainder (sign of the dividend)
                tst.w   d0
                bpl.s   .pa_pos
                add.w   d1,d0                ; negative remainder: quotient - 1, remainder + divisor
                move.w  d0,(a1)
                swap    d0
                subq.w  #1,d0
                move.w  d0,(a0)
                rts
.pa_pos:
                move.w  d0,(a1)
                swap    d0
                move.w  d0,(a0)
.pt_ret:
                rts

; it_ptrmoved(): places the pointer sprite at (PTR_X, PTR_Y) shifted by the Preferences XOffset/YOffset, and
; updates ib_MouseX/Y (HIRES screen coordinates: x doubled). Nothing before intuition init. Preserves everything.
it_ptrmoved:
                movem.l d0-d1/a0-a1/a6,-(sp)
                move.l  INT_IBASE,d0
                beq.s   .pm_ret
                move.l  d0,a1
                move.w  PTR_X,d0
                add.w   d0,d0
                move.w  d0,IB_MOUSEX(a1)
                move.w  PTR_Y,IB_MOUSEY(a1)
                move.l  IB_GFXBASE(a1),d0
                beq.s   .pm_ret
                move.l  d0,a6
                move.b  IB_PREFS+PF_XOFFSET(a1),d0
                ext.w   d0
                add.w   PTR_X,d0
                move.b  IB_PREFS+PF_YOFFSET(a1),d1
                ext.w   d1
                add.w   PTR_Y,d1
                lea     IB_PTRSS(a1),a1
                sub.l   a0,a0                ; ViewPort of the active View
                jsr     LVO_MOVESPRITE(a6)
.pm_ret:
                movem.l (sp)+,d0-d1/a0-a1/a6
                rts

; it_ptrinit(a2 = IntuitionBase, a6 = SysBase): copies the Preferences pointer image into chip (IB_PTRDATA),
; reserves channel 0 and displays it at the current position; publishes IntuitionBase in INT_IBASE. Without GfxBase or
; without memory: no pointer.
; Preserves d2-d7/a2-a6.
it_ptrinit:
                movem.l a3/a6,-(sp)
                move.l  a2,INT_IBASE
                tst.l   IB_GFXBASE(a2)
                beq.s   .pi_ret
                move.l  #PTR_DATASIZE,d0
                move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
                jsr     LVO_ALLOCMEM(a6)
                tst.l   d0
                beq.s   .pi_ret
                move.l  d0,a3                ; a3 = data (POS, CTL, image, 0, 0)
                move.l  d0,IB_PTRDATA(a2)
                lea     4(a3),a1
                lea     IB_PREFS+PF_PTRMATRIX+4(a2),a0
                moveq   #PTR_HEIGHT*2-1,d0
.pi_cpy:
                move.w  (a0)+,(a1)+
                dbra    d0,.pi_cpy
                lea     IB_PTRSS(a2),a1
                move.w  #PTR_HEIGHT,ss_height(a1)
                move.w  PTR_X,ss_x(a1)
                move.w  PTR_Y,ss_y(a1)
                move.l  IB_GFXBASE(a2),a6
                move.l  a1,a0
                moveq   #0,d0
                jsr     LVO_GETSPRITE(a6)
                tst.l   d0
                bmi.s   .pi_ret
                sub.l   a0,a0
                lea     IB_PTRSS(a2),a1
                move.l  a2,-(sp)
                move.l  a3,a2
                jsr     LVO_CHANGESPRITE(a6)
                move.l  (sp)+,a2
.pi_ret:
                movem.l (sp)+,a3/a6
                rts

; pointer image (drawn for this project): arrow, pixel = plane1*2 + plane0 -> colors 17 (red), 18 (black)
PTR_HEIGHT      EQU 16
PTR_DATASIZE    EQU 4+PTR_HEIGHT*4+4
ptr_image:
        dc.w    $0000,$C000            ; KK..............
        dc.w    $4000,$A000            ; KRK.............
        dc.w    $6000,$9000            ; KRRK............
        dc.w    $7000,$8800            ; KRRRK...........
        dc.w    $7800,$8400            ; KRRRRK..........
        dc.w    $7C00,$8200            ; KRRRRRK.........
        dc.w    $7E00,$8100            ; KRRRRRRK........
        dc.w    $7F00,$8080            ; KRRRRRRRK.......
        dc.w    $7C00,$83C0            ; KRRRRRKKKK......
        dc.w    $6C00,$9200            ; KRRKRRK.........
        dc.w    $4600,$A900            ; KRK.KRRK........
        dc.w    $0600,$C900            ; KK..KRRK........
        dc.w    $0300,$0480            ; .....KRRK.......
        dc.w    $0300,$0480            ; .....KRRK.......
        dc.w    $0000,$0300            ; ......KK........
        dc.w    $0000,$0000            ; ................
