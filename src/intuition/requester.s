; src/intuition/requester.s - CLICKABLE Intuition "insert disk" requester (component).
;
; Scope (advisor): the gadget/requester MECHANISM, provable clean-room headless. (1) struct Requester +
; struct Gadget (NDK layout); (2) gadget hit-test (the heart of "clickable"); (3) req_input_handler registered
; on input.device -> handles IECLASS_RAWMOUSE (left button click) and hit-tests the position -> sets REQ_HIT;
; (4) readback-provable rendering (border + text via the 8x8 font) into a bitplane. The HARDWARE mouse (gameport/
; JOY0DAT RELATIVE deltas) and the LIVE M6R WIRING (real click on an invisible headless screen) are DEFERRED: not
; observable in this harness (relative deltas + framebuffer not capturable). Proof of the click = IND_WRITEEVENT of a
; synthetic RAWMOUSE (absolute position) = the PUBLIC injection path, like console.device on the same chain.
; IMPLEMENTATION track ("clean"): NDK intuition.i (Gadget/Requester) + inputevent.i. NO ROM reading. Hand-authored font.

                include "exec.i"
                include "intuition.i"

                xdef    req_hittest
                xdef    req_input_handler
                xdef    req_draw
                xref    font8x8

; --- static struct Requester + struct Gadget (the insert-disk requester) ---
; Requester @ (80,64) 160x64; "Retry" gadget @ (40,40) rel 80x16 -> abs (120,104) 80x16 (x[120,200) y[104,120)).
                EVEN
req_struct:
                dc.l    0                    ; RQ_OLDERREQ
                dc.w    80                   ; RQ_LEFTEDGE
                dc.w    64                   ; RQ_TOPEDGE
                dc.w    160                  ; RQ_WIDTH
                dc.w    64                   ; RQ_HEIGHT
                dc.w    0,0                  ; RelLeft/RelTop
                dc.l    req_gadget           ; RQ_REQGADGET (offset 16)
                dc.l    0                    ; ReqBorder (20)
                dc.l    req_body             ; RQ_REQTEXT (24)
                dcb.b   RQ_SIZEOF-28,0       ; rest of the struct
                EVEN
req_gadget:
                dc.l    0                    ; GG_NEXTGADGET
                dc.w    40                   ; GG_LEFTEDGE (rel to requester)
                dc.w    40                   ; GG_TOPEDGE
                dc.w    80                   ; GG_WIDTH
                dc.w    16                   ; GG_HEIGHT
                dc.w    0                    ; GG_FLAGS
                dc.w    0                    ; GG_ACTIVATION
                dc.w    BOOLGADGET           ; GG_GADGETTYPE
                dcb.b   GG_SIZEOF-18,0
                EVEN
req_body:
                dc.b    "INSERT DISK",0
req_gtext:
                dc.b    "RETRY",0
                EVEN

; req_hittest(d0.w = x, d1.w = y) -> d0 = 1 if (x,y) is in the gadget's ABSOLUTE box, otherwise 0. Preserves d2/d3/a0.
req_hittest:
                movem.l d2/d3/a0,-(sp)
                lea     req_struct(pc),a0
                move.w  RQ_LEFTEDGE(a0),d2
                lea     req_gadget(pc),a0
                add.w   GG_LEFTEDGE(a0),d2   ; d2 = gx (absolute left)
                cmp.w   d2,d0
                blt.s   .ht_miss             ; x < gx
                move.w  GG_WIDTH(a0),d3
                add.w   d2,d3                ; gx + Width
                cmp.w   d3,d0
                bge.s   .ht_miss             ; x >= right
                lea     req_struct(pc),a0
                move.w  RQ_TOPEDGE(a0),d2
                lea     req_gadget(pc),a0
                add.w   GG_TOPEDGE(a0),d2    ; d2 = gy (absolute top)
                cmp.w   d2,d1
                blt.s   .ht_miss             ; y < gy
                move.w  GG_HEIGHT(a0),d3
                add.w   d2,d3
                cmp.w   d3,d1
                bge.s   .ht_miss             ; y >= bottom
                moveq   #1,d0
                bra.s   .ht_ret
.ht_miss:
                moveq   #0,d0
.ht_ret:
                movem.l (sp)+,d2/d3/a0
                rts

; req_input_handler(a0 = InputEvent list, a1 = is_Data): input.device handler. On a LEFT BUTTON click
; (IECLASS_RAWMOUSE, ie_Code == IECODE_LBUTTON) hit-tests ie_X/ie_Y -> sets REQ_HIT if the gadget is hit.
; Returns d0 = list (pass-through). Preserves d2-d7/a2-a6 (saves d2/d3/a3).
req_input_handler:
                movem.l d2/d3/a3,-(sp)
                move.l  a0,d3                ; original list (return)
                move.l  a0,a3                ; walk
.rih_loop:
                move.l  a3,d0
                beq.s   .rih_done
                cmp.b   #IECLASS_RAWMOUSE,IE_CLASS(a3)
                bne.s   .rih_next
                cmp.w   #IECODE_LBUTTON,IE_CODE(a3)   ; left button DOWN
                bne.s   .rih_next
                ifeq    REQ_NO_HITTEST
                move.w  IE_X(a3),d0
                move.w  IE_Y(a3),d1
                bsr     req_hittest          ; -> d0 = 1/0 (preserves d2/d3)
                tst.l   d0
                beq.s   .rih_next
                move.w  #1,REQ_HIT           ; gadget hit -> GADGETUP
                endc                         ; RED REQ_NO_HITTEST: no hit-test -> REQ_HIT never set
.rih_next:
                move.l  IE_NEXTEVENT(a3),a3
                bra.s   .rih_loop
.rih_done:
                move.l  d3,d0                ; list (pass-through)
                movem.l (sp)+,d2/d3/a3
                rts

; req_draw(a0 = bitplane, d0.w = bytewidth): draws the requester (top/bottom border + "INSERT DISK" text + "RETRY"
; label) via the 8x8 font. Rendered into the bitplane (proven by readback). Clobbers scratch + d2-d7/a2-a4 (saved).
req_draw:
                movem.l d2-d7/a2-a4,-(sp)
                move.l  a0,a2                ; a2 = bitplane
                moveq   #0,d7
                move.w  d0,d7                ; d7 = bytewidth
                lea     req_struct(pc),a3
                ; TOP border: row = RQ_TOPEDGE, bytes [LeftEdge/8 .. +Width/8] = $FF
                moveq   #0,d2
                move.w  RQ_TOPEDGE(a3),d2
                mulu    d7,d2                ; offset of the top line
                lea     0(a2,d2.l),a0
                bsr     .rd_hline
                ; BOTTOM border: row = RQ_TOPEDGE + RQ_HEIGHT - 1
                moveq   #0,d2
                move.w  RQ_TOPEDGE(a3),d2
                add.w   RQ_HEIGHT(a3),d2
                subq.w  #1,d2
                mulu    d7,d2
                lea     0(a2,d2.l),a0
                bsr     .rd_hline
                ; "INSERT DISK" text: col = LeftEdge/8 + 2, row = TopEdge + 8
                lea     req_body(pc),a4
                move.w  RQ_LEFTEDGE(a3),d5
                lsr.w   #3,d5
                addq.w  #2,d5
                moveq   #0,d6
                move.w  RQ_TOPEDGE(a3),d6
                addq.w  #8,d6
                bsr     .rd_str
                ; "RETRY" label in the gadget: col = (LeftEdge+gg_LeftEdge)/8 + 1, row = TopEdge+gg_TopEdge+4
                lea     req_gadget(pc),a0
                move.w  RQ_LEFTEDGE(a3),d5
                add.w   GG_LEFTEDGE(a0),d5
                lsr.w   #3,d5
                addq.w  #1,d5
                moveq   #0,d6
                move.w  RQ_TOPEDGE(a3),d6
                add.w   GG_TOPEDGE(a0),d6
                addq.w  #4,d6
                lea     req_gtext(pc),a4
                bsr     .rd_str
                movem.l (sp)+,d2-d7/a2-a4
                rts
; .rd_hline(a0 = &row, a3 = req_struct): draws a $FF horizontal line across the requester width. Clobbers d0/d1/a1.
.rd_hline:
                move.w  RQ_LEFTEDGE(a3),d0
                lsr.w   #3,d0                ; start byte
                move.w  RQ_WIDTH(a3),d1
                lsr.w   #3,d1                ; number of bytes
                lea     0(a0,d0.w),a1
                subq.w  #1,d1
.hl_lp:
                move.b  #$FF,(a1)+
                dbra    d1,.hl_lp
                rts
; .rd_str(a4 = NUL-terminated string, d5.w = byte col, d6.l = row px, a2 = bitplane, d7 = bytewidth): blits 8x8 glyphs.
.rd_str:
                moveq   #0,d0
                move.b  (a4)+,d0
                beq.s   .rs_ret
                sub.w   #$20,d0
                blt.s   .rs_adv              ; < space -> skip (but advance the column)
                lsl.w   #3,d0
                move.l  #font8x8,a0
                add.l   d0,a0                ; a0 = glyph (8 bytes)
                move.l  d6,d1
                mulu    d7,d1                ; row * bytewidth
                lea     0(a2,d1.l),a1
                add.w   d5,a1                ; + col
                moveq   #7,d2
.rs_row:
                move.b  (a0)+,(a1)
                add.w   d7,a1
                dbra    d2,.rs_row
.rs_adv:
                addq.w  #1,d5
                bra.s   .rd_str
.rs_ret:
                rts
