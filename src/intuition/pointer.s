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
                xdef    it_ptrapply
                xdef    intuition_SetPointer
                xdef    intuition_ClearPointer
                xref    it_event             ; screens.s: buttons and movements -> input task
                xref    it_keyin
                xref    it_tickin
                xref    it_diskin

; pointer_input_handler(a0 = InputEvent list, a1 = is_Data): input.device handler (pri 50). For each
; RAWMOUSE: PTR += signed relative (ie_X, ie_Y), in high-resolution pixels and interlaced lines like ib_MouseX/Y
; (intuition-input-menus §1.4), clamp [0, PTR_XMAX-1] x [0, 2 x PTR_YLIM-1], rewrites ie_X/ie_Y as absolute. Returns d0 =
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
                bsr     ptr_keymouse         ; Amiga + arrows / Alt: the key may become a mouse event
                cmp.b   #IECLASS_RAWKEY,IE_CLASS(a3)
                bne     .pih_mouse
                jsr     it_keyin             ; keyboard of an active text gadget
                bra     .pih_next
.pih_tick:
                cmp.b   #IECLASS_TIMER,IE_CLASS(a3)
                bne.s   .pih_disk
                jsr     it_tickin            ; INTUITICKS (input task)
                bra     .pih_next
.pih_disk:
                cmp.b   #IECLASS_DISKREMOVED,IE_CLASS(a3)
                beq.s   .pih_dk
                cmp.b   #IECLASS_DISKINSERTED,IE_CLASS(a3)
                bne.s   .pih_mouse
.pih_dk:
                jsr     it_diskin            ; DISKINSERTED / DISKREMOVED (input task)
                bra     .pih_next
.pih_mouse:
                cmp.b   #IECLASS_POINTERPOS,IE_CLASS(a3)
                bne.s   .pih_raw
                bsr     ptr_abs              ; absolute position -> relative RAWMOUSE
                bra.s   .pih_move
.pih_raw:
                cmp.b   #IECLASS_RAWMOUSE,IE_CLASS(a3)
                bne     .pih_next
.pih_move:
                bsr     ptr_ticks            ; deltas scaled to the Preferences speed
                move.l  INT_IBASE,d0         ; a verification blocks intuition (input-menus §2.5): the pointer stays,
                beq.s   .pih_vok             ; its movement is held back and applied afterwards
                move.l  d0,a0
                tst.l   IB_VWIN(a0)
                beq.s   .pih_vfree
                move.w  IE_X(a3),d0
                add.w   d0,IB_VPX(a0)
                move.w  IE_Y(a3),d0
                add.w   d0,IB_VPY(a0)
                clr.l   IE_X(a3)
                bra.s   .pih_vok
.pih_vfree:
                move.w  IB_VPX(a0),d0
                add.w   d0,IE_X(a3)
                move.w  IB_VPY(a0),d0
                add.w   d0,IE_Y(a3)
                clr.l   IB_VPX(a0)
.pih_vok:
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
                move.l  INT_IBASE,d0
                beq.s   .pih_xset
                move.l  d0,a0
                tst.l   IB_SDRAG(a0)
                beq.s   .pih_xset
                move.w  IB_SDRAGX(a0),d3     ; screen drag: X frozen (intuition-screens §8.3)
.pih_xset:
                move.w  d3,PTR_X
                move.w  d3,IE_X(a3)          ; rewritten as absolute for the following handlers
                move.w  PTR_Y,d4             ; Y: same
                add.w   IE_Y(a3),d4
                ifeq    PTR_NO_CLAMP
                bpl.s   .pih_ylo
                moveq   #0,d4
.pih_ylo:
                move.w  PTR_YLIM,d0
                add.w   d0,d0
                cmp.w   d0,d4
                blt.s   .pih_yhi
                move.w  d0,d4
                subq.w  #1,d4
.pih_yhi:
                endc
                move.l  INT_IBASE,d0
                beq.s   .pih_yset
                move.l  d0,a0
                cmp.w   IB_YMIN(a0),d4
                bge.s   .pih_yset
                move.w  IB_YMIN(a0),d4       ; not above the highest visible screen (§5.3)
.pih_yset:
                move.w  d4,PTR_Y
                move.w  d4,IE_Y(a3)
                bsr     it_ptrmoved          ; pointer sprite + IB_MOUSEX/Y
                move.w  IE_CODE(a3),d0       ; buttons and movements -> intuition input task
                move.l  d2,-(sp)
                moveq   #0,d2
                move.w  IE_QUALIFIER(a3),d2  ; (Shift-click: the Workbench extends its selection)
                jsr     it_event
                move.l  (sp)+,d2
.pih_next:
                move.l  IE_NEXTEVENT(a3),a3
                bra     .pih_loop
.pih_done:
                move.l  d2,d0                ; list (pass-through)
                movem.l (sp)+,d2/d3/d4/a3
                rts

; ptr_keymouse(a3 = RAWKEY event), intuition-input-menus §1.7: a button emulated by Amiga + Alt is released (its
; SELECTUP / MENUUP goes to intuition first) at the first key event whose qualifier no longer holds that Alt. A press
; with an Amiga qualifier then becomes, in place: an arrow, a RAWMOUSE movement (code $FF; speed 1 on a press, +6 in X
; or +4 in Y per repeat, 100 in X or 75 in Y with Shift; the other axis's speed back to 0); left / right Alt, a
; SELECTDOWN / MENUDOWN RAWMOUSE if that button is not already emulated. Clobbers d0/d1/a0.
IEQUALIFIER_SHIFTS EQU $0003
IEQUALIFIERB_LALT  EQU 4
IEQUALIFIERB_RALT  EQU 5
IEQUALIFIER_AMIGAS EQU $00C0
IEQUALIFIERB_REPEAT EQU 9
ptr_keymouse:
                move.l  INT_IBASE,d0
                beq     .km_ret
                move.l  d0,a0
                move.w  IE_QUALIFIER(a3),d1
                btst    #0,IB_KMBTN(a0)
                beq.s   .km_r2
                btst    #IEQUALIFIERB_LALT,d1
                bne.s   .km_r2
                bclr    #0,IB_KMBTN(a0)
                move.w  #IECODE_LBUTTON|IECODE_UP_PREFIX,d0
                bsr     .km_btn
.km_r2:
                btst    #1,IB_KMBTN(a0)
                beq.s   .km_press
                btst    #IEQUALIFIERB_RALT,d1
                bne.s   .km_press
                bclr    #1,IB_KMBTN(a0)
                move.w  #IECODE_RBUTTON|IECODE_UP_PREFIX,d0
                bsr     .km_btn
.km_press:
                move.w  IE_CODE(a3),d0
                btst    #7,d0                ; a release: stays a key
                bne     .km_ret
                move.w  d1,-(sp)
                and.w   #IEQUALIFIER_AMIGAS,(sp)+
                beq     .km_ret
                cmp.w   #$4E,d0              ; ->
                beq.s   .km_x
                cmp.w   #$4F,d0              ; <-
                beq.s   .km_x
                cmp.w   #$4C,d0              ; up
                beq.s   .km_y
                cmp.w   #$4D,d0              ; down
                beq.s   .km_y
                btst    #IEQUALIFIERB_LALT,d1
                beq.s   .km_ralt
                bset    #0,IB_KMBTN(a0)
                bne.s   .km_ralt
                move.w  #IECODE_LBUTTON,d0
                bra.s   .km_toms
.km_ralt:
                btst    #IEQUALIFIERB_RALT,d1
                beq.s   .km_ret
                bset    #1,IB_KMBTN(a0)
                bne.s   .km_ret
                move.w  #IECODE_RBUTTON,d0
.km_toms:
                clr.l   IE_X(a3)
                bra.s   .km_mouse
.km_x:
                clr.w   IB_KMY(a0)
                lea     IB_KMX(a0),a0
                moveq   #6,d0
                swap    d0
                move.w  #100,d0              ; d0 = repeat step : Shift speed
                bsr.s   .km_speed
                cmp.w   #$4F,IE_CODE(a3)
                bne.s   .km_xp
                neg.w   d0
.km_xp:
                move.w  d0,IE_X(a3)
                clr.w   IE_Y(a3)
                bra.s   .km_move
.km_y:
                clr.w   IB_KMX(a0)
                lea     IB_KMY(a0),a0
                moveq   #4,d0
                swap    d0
                move.w  #75,d0
                bsr.s   .km_speed
                cmp.w   #$4C,IE_CODE(a3)
                bne.s   .km_yp
                neg.w   d0
.km_yp:
                move.w  d0,IE_Y(a3)
                clr.w   IE_X(a3)
.km_move:
                move.w  #IECODE_NOBUTTON,d0
.km_mouse:
                move.b  #IECLASS_RAWMOUSE,IE_CLASS(a3)
                move.w  d0,IE_CODE(a3)
.km_ret:
                rts
.km_speed:                           ; (a0) = axis speed, d0 = step : Shift speed, d1 = qualifier -> d0.w = speed
                btst    #0,d1
                bne.s   .ks_shift
                btst    #1,d1
                bne.s   .ks_shift
                btst    #IEQUALIFIERB_REPEAT,d1
                bne.s   .ks_rep
                moveq   #1,d0
                bra.s   .ks_set
.ks_shift:
                and.l   #$FFFF,d0
                bra.s   .ks_set
.ks_rep:
                swap    d0
                add.w   (a0),d0
.ks_set:
                move.w  d0,(a0)
                rts
.km_btn:                             ; release of an emulated button: to intuition before the key
                movem.l d1-d2/a0,-(sp)
                move.w  d1,d2
                jsr     it_event
                movem.l (sp)+,d1-d2/a0
                rts

; ptr_abs(a3 = IECLASS_POINTERPOS event), intuition-prefs-v34 §6: without IEQUALIFIER_RELATIVEMOUSE, ie_X/ie_Y (an
; absolute position, hires pixels and interlaced lines like ib_MouseX/Y) become (position - ib_MouseX/Y) x
; PointerTicks and RELATIVEMOUSE is set; the class becomes RAWMOUSE. IND_WRITEEVENT callers (tests/imenu_probe.s)
; move the pointer this way. Clobbers d0/d1/a0.
IEQUALIFIERB_RELATIVEMOUSE EQU 15
ptr_abs:
                move.b  #IECLASS_RAWMOUSE,IE_CLASS(a3)
                btst    #IEQUALIFIERB_RELATIVEMOUSE-8,IE_QUALIFIER(a3)
                bne.s   .pa_ret
                bset    #IEQUALIFIERB_RELATIVEMOUSE-8,IE_QUALIFIER(a3)
                moveq   #1,d1                ; PointerTicks (1 before intuition init)
                move.l  INT_IBASE,d0
                beq.s   .pa_t
                move.l  d0,a0
                move.w  IB_PREFS+PF_PTRTICKS(a0),d0
                ble.s   .pa_t
                move.w  d0,d1
.pa_t:
                move.w  PTR_X,d0             ; = ib_MouseX / ib_MouseY
                neg.w   d0
                add.w   IE_X(a3),d0
                muls    d1,d0
                move.w  d0,IE_X(a3)
                move.w  PTR_Y,d0
                neg.w   d0
                add.w   IE_Y(a3),d0
                muls    d1,d0
                move.w  d0,IE_Y(a3)
.pa_ret:
                rts

; ptr_ticks(a3 = RAWMOUSE event): as in intuition 1.3, one mouse count is worth one hires pixel (one interlaced line
; in Y) divided by the Preferences PointerTicks, the remainder being carried over to the following events
; (IB_PREMX/Y). Nothing before intuition init. Clobbers d0/d1/a0/a1.
ptr_ticks:
                move.l  INT_IBASE,d0
                beq.s   .pt_ret
                move.l  d0,a1
                move.w  IB_PREFS+PF_PTRTICKS(a1),d1
                ble.s   .pt_ret              ; d1 = divisor (intuition-prefs-v34 §6: for 1, 2, 4 the 1.3 shift-and-
                lea     IE_X(a3),a0          ; carry rule is this division with its remainder kept)
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

; it_ptrmoved(): places the pointer sprite at (PTR_X / 2, PTR_Y / 2) shifted by the XOffset/YOffset of the displayed
; pointer (the window's own, otherwise the Preferences'), and sets ib_MouseX/Y = PTR_X/Y. Nothing before intuition
; init. Preserves everything.
it_ptrmoved:
                movem.l d0-d1/a0-a1/a6,-(sp)
                move.l  INT_IBASE,d0
                beq.s   .pm_ret
                move.l  d0,a1
                move.w  PTR_X,IB_MOUSEX(a1)
                move.w  PTR_Y,IB_MOUSEY(a1)
                move.l  IB_GFXBASE(a1),d0
                beq.s   .pm_ret
                move.l  d0,a6
                lea     IB_PREFS+PF_XOFFSET(a1),a0  ; (XOffset, YOffset) byte pair
                move.l  IB_PTRWIN(a1),d0
                beq.s   .pm_off
                move.l  d0,a0
                lea     WD_XOFFSET(a0),a0
.pm_off:
                move.w  PTR_X,d0             ; the sprite moves in lores pixels and non-interlaced lines
                asr.w   #1,d0
                move.b  (a0)+,d1
                ext.w   d1
                add.w   d1,d0
                move.w  PTR_Y,d1
                asr.w   #1,d1
                move.l  d2,-(sp)
                move.b  (a0),d2
                ext.w   d2
                add.w   d2,d1
                move.l  (sp)+,d2
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

; SetPointer(window a0, data a1, height d0, width d1, xOffset d2, yOffset d3) / ClearPointer(window a0): the
; window's own pointer (spec intuition-misc-v34 §3), shown at once if the window is the active one, otherwise when it
; becomes active. The data (CHIP RAM) is used in place. ClearPointer leaves the offsets alone.
intuition_SetPointer:
                move.l  a1,WD_POINTER(a0)
                move.b  d0,WD_PTRHEIGHT(a0)
                move.b  d1,WD_PTRWIDTH(a0)
                move.b  d2,WD_XOFFSET(a0)
                move.b  d3,WD_YOFFSET(a0)
                bra.s   sp_show
intuition_ClearPointer:
                clr.l   WD_POINTER(a0)
                clr.b   WD_PTRHEIGHT(a0)
                clr.b   WD_PTRWIDTH(a0)
sp_show:
                move.l  a6,-(sp)
                move.l  a0,-(sp)
                move.l  ($4).w,a6
                jsr     LVO_FORBID(a6)
                move.l  (sp)+,a0
                move.l  (sp),a1              ; IntuitionBase
                cmp.l   IB_ACTIVEWINDOW(a1),a0
                bne.s   .ss_nact
                bsr.s   it_ptrapply
.ss_nact:
                jsr     LVO_PERMIT(a6)
                move.l  (sp)+,a6
                rts

; it_ptrapply(a0 = window | 0): displays the window's own pointer if it has one (Pointer non-zero), otherwise the
; default pointer: sprite 0 gets the image (ChangeSprite, height = signed byte) and is placed with its offsets.
; Called by SetPointer/ClearPointer, on activation and when the active window closes. Preserves everything.
it_ptrapply:
                movem.l d0-d1/a0-a2/a6,-(sp)
                move.l  INT_IBASE,d0
                beq.s   .pa_ret
                move.l  d0,a2
                tst.l   IB_GFXBASE(a2)
                beq.s   .pa_ret
                clr.l   IB_PTRWIN(a2)
                move.l  IB_PTRDATA(a2),d1
                moveq   #PTR_HEIGHT,d0
                cmpa.w  #0,a0
                beq.s   .pa_def
                tst.l   WD_POINTER(a0)
                beq.s   .pa_def
                move.l  WD_POINTER(a0),d1
                move.b  WD_PTRHEIGHT(a0),d0
                ext.w   d0
                move.l  a0,IB_PTRWIN(a2)
.pa_def:
                tst.l   d1
                beq.s   .pa_ret              ; no default image (no chip memory at init)
                lea     IB_PTRSS(a2),a1
                move.w  d0,ss_height(a1)
                move.l  IB_GFXBASE(a2),a6
                sub.l   a0,a0
                move.l  d1,a2
                jsr     LVO_CHANGESPRITE(a6)
                jsr     it_ptrmoved
.pa_ret:
                movem.l (sp)+,d0-d1/a0-a2/a6
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
