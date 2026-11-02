; src/exec/gameport.s — gameport.device: units 0 and 1 with the GPD_* commands (spec gameport-v34), plus the
; hardware mouse driver that injects RAWMOUSE InputEvents into input.device.
;
; Device: GPD_READEVENT queue, 8-slot event ring, trigger, controller types (mouse, relative and absolute joystick)
; per unit, sampled every VBlank by gp_unit_frame; pot bits through potgo.resource (§7.2).
;
; Role: read the mouse hardware every VBlank (JOY0DAT = X/Y quadrature counters; CIAA_PRA bit 6 = left
; button, active-low), turn the readings into RAWMOUSE InputEvents (signed deltas with 8-bit wraparound +
; button edge detection) and inject them into input.device via IND_WRITEEVENT. It is the mouse COUNTERPART of
; the keyboard feeder: like it, we use IND_WRITEEVENT (PUBLIC injection path) instead of an input.task
; (documented deviation, cf. input.s). Intuition (pointer.s) then accumulates these deltas into an absolute position.
;
; FACTORISATION (headless clean-room proof): the hardware mouse is NOT observable under headless FS-UAE
; (RELATIVE JOY0DAT deltas + no injectable movement + framebuffer not capturable). So we separate:
;   - gp_delta8 / gp_poll: PURE LOGIC (delta+wraparound, button edge, event construction, IND_WRITEEVENT),
;     drivable with SYNTHETIC register snapshots -> proven exhaustively ("GAMEPORT OK").
;   - gp_vblank_server: thin hardware SHIM (reads the real registers -> gp_poll). Only non-E2E part;
;     proven STRUCTURALLY: registered on the VERTB chain of the running system, its GP_POLLS counter
;     advances on the real VBlanks ("GP VBLANK LIVE OK"). On a static JOY0DAT (headless) it emits nothing.
; IMPLEMENTATION track ("clean"): HRM (JOYxDAT/CIAA PRA/POTGOR) + NDK devices/gameport.i + inputevent.i +
; docs/analysis/gameport-v34.md. NO ROM reading.

                include "exec.i"

                xdef    gp_delta8
                xdef    gp_poll
                xdef    gp_vblank_server
                xdef    gp_install
                xdef    gameport_dev_name
                xdef    gp_mousesrc

POTGO_W         EQU CUSTOM+$034
JOY1DAT_W       EQU CUSTOM+$00C
IO_ACTUAL2      EQU 32               ; IOStdReq fields — local (avoids including disk.i)
IO_LENGTH2      EQU 36
IO_DATA2        EQU 40
IOERR_BADLEN    EQU -4
LIBB_DELEXP     EQU 3
GPDERR_SETCTYPE EQU 1
GPCT_MOUSE      EQU 1
GPCT_ABSJOY     EQU 3
IEQUAL_RELMOUSE EQU $80              ; high byte of IEQUALIFIER_RELATIVEMOUSE

; Unit (gameport-v34 §1.1, own layout): GPD_READEVENT queue, 8-slot event ring (7 usable), trigger, known buttons
; (bit 15 left/fire, 14 right, 13 middle), frame counter, accumulators (relative types) or position (absolute).
GU_QUEUE        EQU 0                ; struct List of queued GPD_READEVENT requests
GU_STOP         EQU 14               ; byte: CMD_STOP flag
GU_FLAGS        EQU 15               ; byte: GUF_*
GU_TYPE         EQU 16               ; byte: signed GPCT_*
GU_RD           EQU 18               ; word: ring read slot (0-7)
GU_WR           EQU 20               ; word: ring write slot
GU_TRIG         EQU 22               ; struct GamePortTrigger: keys, timeout, xdelta, ydelta (words)
GU_BTN          EQU 30
GU_CNT          EQU 32               ; word: frames since the last event (saturating)
GU_X            EQU 34
GU_Y            EQU 36
GU_LX           EQU 38               ; byte: absolute type, last reported X / Y
GU_LY           EQU 39
GU_REF          EQU 40               ; word: mouse, previous JOYxDAT
GU_RING         EQU 42               ; 8 slots: code byte, qualifier high byte, X word, Y word, frames word
GU_SIZE         EQU GU_RING+8*8
GUF_REL         EQU 0
GUF_SKIP        EQU 1
GUF_UNIT1       EQU 2
GPMS_PORT1      EQU 0                ; GPB_MSRC: mouse on port 1 (connector 2)
GPMS_STOPPED    EQU 6                ; input.device stopped (CMD_STOP)
GPMS_NONE       EQU 7                ; no mouse (failed open, or type other than GPCT_MOUSE)

GPB_POTGO       EQU LIB_SIZE         ; potgo.resource base
GPB_REQ         EQU LIB_SIZE+4       ; pot bits requested for both units
GPB_ALLOC       EQU LIB_SIZE+6       ; pot bits granted by AllocPotBits
GPB_DATA        EQU LIB_SIZE+8       ; POTGO data word written every frame
GPB_MSRC        EQU LIB_SIZE+10      ; byte: system mouse source (gp_mousesrc), 0 = port 0 running
GPB_UNIT0       EQU LIB_SIZE+12
GPB_UNIT1       EQU GPB_UNIT0+GU_SIZE
GAMEPORT_SIZE   EQU GPB_UNIT1+GU_SIZE

; --- gameport.device ROMTag (scanned by build_reslist; pri 60 = gameport roadmap slot) ---
                EVEN
gameport_romtag:
        dc.w    RTC_MATCHWORD
        dc.l    gameport_romtag      ; RT_MATCHTAG = self
        dc.l    gameport_end         ; RT_ENDSKIP
        dc.b    RTF_AUTOINIT|RTF_COLDSTART,34,NT_DEVICE,60  ; RT_FLAGS, RT_VERSION, RT_TYPE, RT_PRI
        dc.l    gameport_dev_name    ; RT_NAME
        dc.l    gameport_dev_name    ; RT_IDSTRING
        dc.l    gameport_inittab     ; RT_INIT -> AUTOINIT table
gameport_dev_name:
        dc.b    "gameport.device",0
        EVEN
gameport_inittab:
        dc.l    GAMEPORT_SIZE        ; dataSize
        dc.l    gameport_vectors     ; funcTable
        dc.l    gameport_datatab     ; dataTable (InitStruct)
        dc.l    gameport_initfunc    ; initFunc
gameport_vectors:                    ; ABSOLUTE table, terminated by -1 (standard device order)
        dc.l    gameport_open        ; LVO -6
        dc.l    gameport_close       ; LVO -12
        dc.l    gameport_expunge     ; LVO -18
        dc.l    gameport_null        ; LVO -24 (reserved)
        dc.l    gameport_beginio     ; LVO -30
        dc.l    gameport_abortio     ; LVO -36
        dc.l    -1
gameport_datatab:
        dc.w    $E000,LN_TYPE,(NT_DEVICE<<8)   ; INITBYTE(LN_TYPE, NT_DEVICE)
        dc.w    $D000,LIB_VERSION,34           ; INITWORD(LIB_VERSION, 34)
        dc.b    0
        EVEN

; Open(ioreq a1, unit d0): units 0 and 1 only; io_Unit = the unit. Nothing is reset: type, trigger and buffered
; events belong to the unit and survive CloseDevice (gameport-v34 §1.2-1.3).
gameport_open:
        cmp.l   #1,d0
        bhi.s   .go_fail
        lea     GPB_UNIT0(a6),a0
        tst.l   d0
        beq.s   .go_unit
        lea     GPB_UNIT1(a6),a0
.go_unit:
        move.l  a0,IO_UNIT(a1)
        bclr    #LIBB_DELEXP,LIB_FLAGS(a6)
        addq.w  #1,LIB_OPENCNT(a6)
        rts
.go_fail:
        move.b  #IOERR_OPENFAIL,IO_ERROR(a1)
        rts
gameport_close:
        clr.l   IO_UNIT(a1)
        clr.l   IO_DEVICE(a1)
        subq.w  #1,LIB_OPENCNT(a6)
        moveq   #0,d0
        rts
gameport_expunge:
        moveq   #0,d0                ; resident base: no expunge
        rts
gameport_null:
        moveq   #0,d0
        rts

; gp_dis / gp_ena: inline Disable/Enable (exec/ables.i). The VERTB server shares this code, and the Enable LVO may
; reschedule, which an interrupt must not do. Preserve every register.
gp_dis:
        move.l  a0,-(sp)
        move.l  ($4).w,a0
        move.w  #INTF_INTEN,INTENA
        addq.b  #1,EB_IDNEST(a0)
        move.l  (sp)+,a0
        rts
gp_ena:
        move.l  a0,-(sp)
        move.l  ($4).w,a0
        subq.b  #1,EB_IDNEST(a0)
        bge.s   .ge_ret
        move.w  #INTF_SETCLR|INTF_INTEN,INTENA
.ge_ret:
        move.l  (sp)+,a0
        rts

; gp_reply(ioreq a1, error d0.b): a request already replied is left alone; otherwise io_Error, out of the unit queue
; if it was queued, ReplyMsg unless IOF_QUICK. Clobbers d0/d1/a0/a1, preserves d2-d7/a2-a6.
gp_reply:
        bsr.s   gp_dis
        cmp.b   #NT_REPLYMSG,LN_TYPE(a1)
        beq.s   .gr_ret
        move.b  d0,IO_ERROR(a1)
        move.l  IO_UNIT(a1),d1
        beq.s   .gr_out
        move.l  d1,a0                ; queued? (walk the unit's queue)
.gr_find:
        move.l  (a0),a0
        tst.l   (a0)
        beq.s   .gr_out
        cmp.l   a0,a1
        bne.s   .gr_find
        move.l  (a1),a0              ; Remove: a0 = successor, d1 = predecessor
        move.l  LN_PRED(a1),d1
        move.l  d1,LN_PRED(a0)
        exg     d1,a0
        move.l  d1,(a0)
.gr_out:
        btst    #0,IO_FLAGS(a1)      ; IOF_QUICK: completed in place, no ReplyMsg
        bne.s   .gr_ret
        move.l  a6,-(sp)
        move.l  ($4).w,a6
        jsr     LVO_REPLYMSG(a6)
        move.l  (sp)+,a6
.gr_ret:
        bra.s   gp_ena

; BeginIO(ioreq a1, device a6): commands 0-13 (gameport-v34 §2.2), a number >= 14 is command 0. GPD_READEVENT is
; queued, the others run at once.
gameport_beginio:
        movem.l d2-d3/a2-a3,-(sp)
        and.b   #$0F,IO_FLAGS(a1)
        clr.b   IO_ERROR(a1)
        move.l  IO_UNIT(a1),a3       ; a3 = unit
        moveq   #0,d0
        move.w  IO_COMMAND(a1),d0
        cmp.w   #14,d0
        blo.s   .gb_cmd
        moveq   #0,d0
.gb_cmd:
        add.w   d0,d0
        move.w  gp_cmdtab(pc,d0.w),d0
        jsr     gp_cmdtab(pc,d0.w)
        movem.l (sp)+,d2-d3/a2-a3
        rts
gp_cmdtab:
        dc.w    gp_nocmd-gp_cmdtab   ; 0 CMD_INVALID
        dc.w    gp_reset-gp_cmdtab   ; 1 CMD_RESET
        dc.w    gp_nocmd-gp_cmdtab   ; 2 CMD_READ
        dc.w    gp_nocmd-gp_cmdtab   ; 3 CMD_WRITE
        dc.w    gp_nocmd-gp_cmdtab   ; 4 CMD_UPDATE
        dc.w    gp_clear-gp_cmdtab   ; 5 CMD_CLEAR
        dc.w    gp_stop-gp_cmdtab    ; 6 CMD_STOP
        dc.w    gp_start-gp_cmdtab   ; 7 CMD_START
        dc.w    gp_flush-gp_cmdtab   ; 8 CMD_FLUSH
        dc.w    gp_readevent-gp_cmdtab ; 9 GPD_READEVENT
        dc.w    gp_askctype-gp_cmdtab  ; 10 GPD_ASKCTYPE
        dc.w    gp_setctype-gp_cmdtab  ; 11 GPD_SETCTYPE
        dc.w    gp_asktrigger-gp_cmdtab ; 12 GPD_ASKTRIGGER
        dc.w    gp_settrigger-gp_cmdtab ; 13 GPD_SETTRIGGER

gp_nocmd:
        moveq   #IOERR_NOCMD,d0
        bra     gp_reply
gp_ok:
        moveq   #0,d0
        bra     gp_reply
gp_badlen:
        moveq   #IOERR_BADLEN,d0
        bra     gp_reply

; CMD_CLEAR empties the ring and, as in 1.3, never replies.
gp_clear:
        bsr     gp_dis
        clr.l   GU_RD(a3)            ; GU_RD and GU_WR
        bra     gp_ena
gp_stop:
        st      GU_STOP(a3)
        bra.s   gp_ok
gp_start:
        clr.b   GU_STOP(a3)
        move.l  a1,-(sp)
        bsr     gp_runread
        move.l  (sp)+,a1
        bra.s   gp_ok
; CMD_FLUSH: every queued request is replied with IOERR_ABORTED, then the flush itself (-2 if it flushed something).
gp_flush:
        move.l  a1,a2
        moveq   #0,d2
.gf_lp:
        move.l  GU_QUEUE(a3),a1
        tst.l   (a1)
        beq.s   .gf_done
        moveq   #IOERR_ABORTED,d0
        bsr     gp_reply
        moveq   #IOERR_ABORTED,d2
        bra.s   .gf_lp
.gf_done:
        move.l  a2,a1
        move.l  d2,d0
        bra     gp_reply
; CMD_RESET = STOP, FLUSH, START: the unit runs with an empty queue; type, trigger and ring are kept.
gp_reset:
        bsr.s   gp_flush
        clr.b   GU_STOP(a3)
        rts

gp_readevent:
        cmp.l   #IE_SIZEOF,IO_LENGTH2(a1)
        blo.s   gp_badlen
        bsr     gp_dis
        move.b  #NT_MESSAGE,LN_TYPE(a1)
        move.l  a1,a2
        lea     LH_TAIL(a3),a0       ; AddTail(queue, request)
        move.l  LH_TAILPRED(a3),d0
        move.l  a1,LH_TAILPRED(a3)
        move.l  a0,(a1)
        move.l  d0,LN_PRED(a1)
        move.l  d0,a0
        move.l  a1,(a0)
        cmp.l   GU_QUEUE(a3),a1      ; head of the queue and unit running: serve it now
        bne.s   .gr_wait
        tst.b   GU_STOP(a3)
        bne.s   .gr_wait
        bsr     gp_runread
        bra     gp_ena
.gr_wait:
        bclr    #0,IO_FLAGS(a2)      ; IOF_QUICK: replied later
        bra     gp_ena

gp_askctype:
        tst.w   IO_LENGTH2+2(a1)
        beq     gp_badlen
        move.l  IO_DATA2(a1),a0
        move.b  GU_TYPE(a3),(a0)
        moveq   #1,d0
        move.l  d0,IO_ACTUAL2(a1)
        bra     gp_ok

; GPD_SETCTYPE: resets buttons, counter, accumulators and the mouse reference (not the ring nor the trigger), skips
; the next frame, then sets the pot bits of both units again (§3.2, §7.2). Values outside -1..3 are refused with
; GPDERR_SETCTYPE (the 1.3 crashes on them).
gp_setctype:
        tst.w   IO_LENGTH2+2(a1)
        beq     gp_badlen
        moveq   #1,d0
        move.l  d0,IO_ACTUAL2(a1)
        move.l  IO_DATA2(a1),a0
        move.b  (a0),d2
        ext.w   d2
        cmp.w   #-1,d2
        blt.s   .gs_bad
        cmp.w   #GPCT_ABSJOY,d2
        bgt.s   .gs_bad
        move.l  a1,-(sp)
        bsr     gp_dis
        clr.w   GU_BTN(a3)
        clr.l   GU_CNT(a3)           ; GU_CNT and GU_X
        clr.l   GU_Y(a3)             ; GU_Y, GU_LX, GU_LY
        move.b  d2,GU_TYPE(a3)
        bset    #GUF_REL,GU_FLAGS(a3)
        bset    #GUF_SKIP,GU_FLAGS(a3)
        cmp.w   #GPCT_ABSJOY,d2
        bne.s   .gs_ref
        bclr    #GUF_REL,GU_FLAGS(a3)
.gs_ref:
        bsr     gp_readjoy
        move.w  d0,GU_REF(a3)
        bsr     gp_potbits           ; d0 = 0 | GPDERR_SETCTYPE
        bsr     gp_ena
        move.l  (sp)+,a1
        bra     gp_reply
.gs_bad:
        moveq   #GPDERR_SETCTYPE,d0
        bra     gp_reply

gp_asktrigger:
        cmp.w   #8,IO_LENGTH2+2(a1)
        blo     gp_badlen
        lea     GU_TRIG(a3),a0
        move.l  IO_DATA2(a1),a2
        bra.s   gp_trigcopy
gp_settrigger:
        cmp.w   #8,IO_LENGTH2+2(a1)
        blo     gp_badlen
        move.l  IO_DATA2(a1),a0
        lea     GU_TRIG(a3),a2
gp_trigcopy:
        move.l  (a0)+,(a2)+
        move.l  (a0)+,(a2)+
        moveq   #8,d0
        move.l  d0,IO_ACTUAL2(a1)
        bra     gp_ok

; AbortIO(ioreq a1): IOERR_ABORTED if not replied yet.
gameport_abortio:
        moveq   #IOERR_ABORTED,d0
        bsr     gp_reply
        moveq   #0,d0
        rts

; gp_readjoy(unit a3) -> d0.w = JOYxDAT of the unit.
gp_readjoy:
        move.w  JOY0DAT,d0
        btst    #GUF_UNIT1,GU_FLAGS(a3)
        beq.s   .rj_ret
        move.w  JOY1DAT_W,d0
.rj_ret:
        rts

; gp_potbits(unit a3, device a6) -> d0 = 0 | GPDERR_SETCTYPE: frees the device's pot bits, takes the unit's four bits
; out of (or into, for types 1-3) the requested and data words, and allocates the union again (§7.2). Caller holds
; Disable. Preserves d2-d7/a1-a6.
gp_potbits:
        movem.l d2-d3/a1/a6,-(sp)
        move.w  #$0F00,d2
        btst    #GUF_UNIT1,GU_FLAGS(a3)
        beq.s   .pb_m
        move.w  #$F000,d2            ; d2 = the unit's pot bits
.pb_m:
        move.w  d2,d3
        not.w   d3
        and.w   d3,GPB_REQ(a6)
        and.w   d3,GPB_DATA(a6)
        tst.b   GU_TYPE(a3)
        ble.s   .pb_alloc
        or.w    d2,GPB_REQ(a6)
        or.w    d2,GPB_DATA(a6)
.pb_alloc:
        move.l  a6,a1                ; a1 = gameport base
        move.l  GPB_POTGO(a1),d0
        beq.s   .pb_none
        move.l  d0,a6
        moveq   #0,d0
        move.w  GPB_ALLOC(a1),d0
        jsr     -12(a6)              ; FreePotBits
        moveq   #0,d0
        move.w  GPB_REQ(a1),d0
        jsr     -6(a6)               ; AllocPotBits -> granted DATxx (and START)
        move.w  d0,d1
        and.w   #$5500,d1
        add.w   d1,d1
        or.w    d1,d0                ; + the OUTxx partner of each granted DATxx
        move.w  d0,GPB_ALLOC(a1)
        bra.s   .pb_chk
.pb_none:
        move.w  GPB_REQ(a1),d0       ; no potgo.resource: the server writes POTGO itself
        move.w  d0,GPB_ALLOC(a1)
.pb_chk:
        moveq   #0,d1
        tst.b   GU_TYPE(a3)
        ble.s   .pb_ret
        and.w   d2,d0
        cmp.w   d2,d0
        beq.s   .pb_ret
        moveq   #GPDERR_SETCTYPE,d1
.pb_ret:
        move.l  d1,d0
        movem.l (sp)+,d2-d3/a1/a6
        rts

; gp_runread(unit a3): serves the head GPD_READEVENT. Empty ring: it stays queued (IOF_QUICK cleared). Otherwise
; copies the buffered events, oldest first, up to io_Length / 22, chained through ie_NextEvent; io_Actual in bytes;
; replied; the next request is then served the same way. Under Disable (task) or in the VERTB server.
; Preserves d2-d7/a2-a6.
gp_runread:
        movem.l d2-d4/a2,-(sp)
        bsr     gp_dis
.rr_next:
        move.l  GU_QUEUE(a3),a1
        tst.l   (a1)
        beq     .rr_ret
        move.w  GU_RD(a3),d0
        cmp.w   GU_WR(a3),d0
        bne.s   .rr_copy
        bclr    #0,IO_FLAGS(a1)
        bra     .rr_ret
.rr_copy:
        move.l  IO_LENGTH2(a1),d2
        divu    #IE_SIZEOF,d2        ; d2.w = capacity (io_Length >= 22 checked by BeginIO)
        move.l  IO_DATA2(a1),a2
        moveq   #0,d3                ; d3 = bytes written
.rr_ev:
        move.w  GU_RD(a3),d0
        cmp.w   GU_WR(a3),d0
        beq.s   .rr_end
        tst.w   d2
        beq.s   .rr_end
        lsl.w   #3,d0
        lea     GU_RING(a3,d0.w),a0
        lea     IE_SIZEOF(a2),a1
        move.l  a1,IE_NEXTEVENT(a2)
        move.b  #IECLASS_RAWMOUSE,IE_CLASS(a2)
        moveq   #0,d0
        btst    #GUF_UNIT1,GU_FLAGS(a3)
        beq.s   .rr_sub
        moveq   #1,d0
.rr_sub:
        move.b  d0,IE_SUBCLASS(a2)   ; unit number
        moveq   #0,d0
        move.b  (a0)+,d0
        move.w  d0,IE_CODE(a2)
        move.b  (a0)+,d0
        lsl.w   #8,d0
        move.w  d0,IE_QUALIFIER(a2)
        move.w  (a0)+,IE_X(a2)
        move.w  (a0)+,IE_Y(a2)
        move.w  (a0)+,IE_TIMESTAMP(a2) ; tv_secs high word = frames since the previous event
        clr.w   IE_TIMESTAMP+2(a2)
        move.l  a2,d4                ; d4 = last event written
        move.l  a1,a2
        add.l   #IE_SIZEOF,d3
        subq.w  #1,d2
        move.w  GU_RD(a3),d0
        addq.w  #1,d0
        and.w   #7,d0
        move.w  d0,GU_RD(a3)
        bra.s   .rr_ev
.rr_end:
        move.l  d4,a0
        clr.l   IE_NEXTEVENT(a0)
        move.l  GU_QUEUE(a3),a1
        move.l  d3,IO_ACTUAL2(a1)
        moveq   #0,d0
        bsr     gp_reply
        bra     .rr_next
.rr_ret:
        bsr     gp_ena
        movem.l (sp)+,d2-d4/a2
        rts

; gp_unit_frame(unit a3): one frame of a unit (§7.1, §4.2): skip after SETCTYPE, counter, sampling, at most one
; event into the ring, then the head request. Server context. Preserves d2-d7/a2-a6.
gp_unit_frame:
        movem.l d2-d7/a2,-(sp)
        bclr    #GUF_SKIP,GU_FLAGS(a3)
        bne     .uf_ret
        addq.w  #1,GU_CNT(a3)
        bne.s   .uf_cnt
        subq.w  #1,GU_CNT(a3)        ; saturates at 65535
.uf_cnt:
        tst.b   GU_TYPE(a3)
        ble     .uf_ret
        moveq   #0,d7                ; d7 = pressed buttons (bit 15 left/fire, 14 right, 13 middle), active low
        move.w  POTINP,d1
        btst    #GUF_UNIT1,GU_FLAGS(a3)
        bne.s   .uf_b1
        btst    #6,CIAA_PRA
        bne.s   .uf_b0r
        bset    #15,d7
.uf_b0r:
        btst    #10,d1
        bne.s   .uf_b0m
        bset    #14,d7
.uf_b0m:
        btst    #8,d1
        bne.s   .uf_mot
        bset    #13,d7
        bra.s   .uf_mot
.uf_b1:
        btst    #7,CIAA_PRA
        bne.s   .uf_b1r
        bset    #15,d7
.uf_b1r:
        btst    #14,d1
        bne.s   .uf_b1m
        bset    #14,d7
.uf_b1m:
        btst    #12,d1
        bne.s   .uf_mot
        bset    #13,d7
.uf_mot:
        bsr     gp_readjoy           ; motion -> d4 = X, d5 = Y
        move.w  d0,d2
        cmp.b   #GPCT_MOUSE,GU_TYPE(a3)
        bne.s   .uf_joy
        move.w  GU_REF(a3),d3
        move.w  d2,GU_REF(a3)
        move.b  d2,d0
        move.b  d3,d1
        bsr     gp_delta8
        move.w  d0,d4
        move.w  d2,d0
        lsr.w   #8,d0
        move.w  d3,d1
        lsr.w   #8,d1
        bsr     gp_delta8
        move.w  d0,d5
        bra.s   .uf_axes
.uf_joy:
        bsr     gp_joydecode
.uf_axes:
        moveq   #0,d6                ; d6 = triggered
        btst    #GUF_REL,GU_FLAGS(a3)
        beq.s   .uf_abs
        add.w   d4,GU_X(a3)          ; relative: accumulate, an axis triggers at 0 < delta <= |sum|
        add.w   d5,GU_Y(a3)
        move.w  GU_X(a3),d0
        move.w  GU_TRIG+4(a3),d1
        bsr     gp_axis
        or.b    d0,d6
        move.w  GU_Y(a3),d0
        move.w  GU_TRIG+6(a3),d1
        bsr     gp_axis
        or.b    d0,d6
        bra.s   .uf_full
.uf_abs:
        move.w  d4,GU_X(a3)          ; absolute: position, an axis triggers on a change of at least delta
        move.w  d5,GU_Y(a3)
        move.b  GU_LX(a3),d0
        ext.w   d0
        neg.w   d0
        add.w   d4,d0
        move.w  GU_TRIG+4(a3),d1
        bsr     gp_axis
        tst.b   d0
        beq.s   .uf_ay
        move.b  d4,GU_LX(a3)
        st      d6
.uf_ay:
        move.b  GU_LY(a3),d0
        ext.w   d0
        neg.w   d0
        add.w   d5,d0
        move.w  GU_TRIG+6(a3),d1
        bsr     gp_axis
        tst.b   d0
        beq.s   .uf_full
        move.b  d5,GU_LY(a3)
        st      d6
.uf_full:
        move.w  GU_WR(a3),d0         ; ring full (7 events): nothing more this frame, nothing lost
        addq.w  #1,d0
        and.w   #7,d0
        cmp.w   GU_RD(a3),d0
        beq     .uf_ret
        moveq   #-1,d3               ; d3.b = code: IECODE_NOBUTTON unless a button transition is reported
        move.w  GU_BTN(a3),d0
        not.w   d0
        and.w   d7,d0                ; new presses (the highest one per event, the others on next frames)
        beq.s   .uf_rel
        btst    #0,GU_TRIG+1(a3)     ; GPTF_DOWNKEYS
        bne.s   .uf_down
        or.w    d0,GU_BTN(a3)
        bra.s   .uf_tmo
.uf_down:
        bsr     gp_highbtn           ; d0 = one bit, d1 = its code
        or.w    d0,GU_BTN(a3)
        move.b  d1,d3
        st      d6
        bra.s   .uf_tmo
.uf_rel:
        move.w  d7,d0
        not.w   d0
        and.w   GU_BTN(a3),d0        ; new releases
        beq.s   .uf_tmo
        btst    #1,GU_TRIG+1(a3)     ; GPTF_UPKEYS
        bne.s   .uf_up
        not.w   d0
        and.w   d0,GU_BTN(a3)
        bra.s   .uf_tmo
.uf_up:
        bsr     gp_highbtn
        not.w   d0
        and.w   d0,GU_BTN(a3)
        bset    #7,d1                ; IECODE_UP_PREFIX
        move.b  d1,d3
        st      d6
.uf_tmo:
        tst.b   d6
        bne.s   .uf_event
        move.w  GU_TRIG+2(a3),d0     ; timeout in frames, 0 = never
        beq.s   .uf_ret
        cmp.w   GU_CNT(a3),d0
        bhi.s   .uf_ret
.uf_event:
        move.w  GU_WR(a3),d0
        lsl.w   #3,d0
        lea     GU_RING(a3,d0.w),a0
        move.b  d3,(a0)+
        move.w  GU_BTN(a3),d0        ; qualifier: bits 15/14/13 -> $40/$20/$10, + RELATIVEMOUSE
        lsr.w   #8,d0
        lsr.b   #1,d0
        and.b   #$70,d0
        btst    #GUF_REL,GU_FLAGS(a3)
        beq.s   .uf_q
        or.b    #IEQUAL_RELMOUSE,d0
.uf_q:
        move.b  d0,(a0)+
        move.w  GU_X(a3),(a0)+
        move.w  GU_Y(a3),(a0)+
        move.w  GU_CNT(a3),(a0)+
        move.w  GU_WR(a3),d0
        addq.w  #1,d0
        and.w   #7,d0
        move.w  d0,GU_WR(a3)
        clr.l   GU_CNT(a3)           ; GU_CNT and GU_X
        clr.w   GU_Y(a3)
        bsr     gp_runread
.uf_ret:
        movem.l (sp)+,d2-d7/a2
        rts

; gp_axis(d0.w = value, d1.w = delta) -> d0.b = -1 if 0 < delta <= |value| (signed word compare), else 0.
gp_axis:
        tst.w   d1
        beq.s   .ax_no
        tst.w   d0
        bpl.s   .ax_abs
        neg.w   d0
.ax_abs:
        cmp.w   d0,d1
        bgt.s   .ax_no
        moveq   #-1,d0
        rts
.ax_no:
        moveq   #0,d0
        rts

; gp_highbtn(d0.w = button bits) -> d0.w = the highest bit, d1.b = its IECODE (left/fire > right > middle).
gp_highbtn:
        moveq   #IECODE_LBUTTON,d1
        btst    #15,d0
        bne.s   .hb_l
        moveq   #IECODE_RBUTTON,d1
        btst    #14,d0
        bne.s   .hb_r
        moveq   #IECODE_MBUTTON,d1
        move.w  #$2000,d0
        rts
.hb_l:
        move.w  #$8000,d0
        rts
.hb_r:
        move.w  #$4000,d0
        rts

; gp_joydecode(d2.w = JOYxDAT) -> d4.w = X, d5.w = Y in -1/0/+1 (HRM: right = bit 1, left = bit 9, down = bit 1
; XOR bit 0, up = bit 9 XOR bit 8; Y positive down). Clobbers d0.
gp_joydecode:
        moveq   #0,d4
        btst    #1,d2
        beq.s   .jd_l
        addq.w  #1,d4
.jd_l:
        btst    #9,d2
        beq.s   .jd_y
        subq.w  #1,d4
.jd_y:
        moveq   #0,d5
        move.w  d2,d0
        lsr.w   #1,d0
        eor.w   d2,d0                ; bit 0 = down, bit 8 = up
        btst    #0,d0
        beq.s   .jd_u
        addq.w  #1,d5
.jd_u:
        btst    #8,d0
        beq.s   .jd_ret
        subq.w  #1,d5
.jd_ret:
        rts

; initFunc (D0=base, A0=segList, A6=ExecBase) -> D0 = base. Sets the name (V34 quirk) and the two unit queues. The
; VBlank server is NOT armed here (resident init = early): gp_install (called at system bringup) does it.
gameport_initfunc:
        move.l  d0,a1
        lea     gameport_dev_name(pc),a0
        move.l  a0,LN_NAME(a1)
        lea     GPB_UNIT0(a1),a0
        bsr.s   .gi_list
        lea     GPB_UNIT1(a1),a0
        bset    #GUF_UNIT1,GU_FLAGS(a0)
.gi_list:                            ; NewList(unit queue)
        move.l  a0,LH_TAILPRED(a0)
        addq.l  #LH_TAIL,a0
        move.l  a0,-LH_TAIL(a0)
        rts

; gp_delta8(d0.b = cur, d1.b = prev) -> d0.w = signed delta. The JOY0DAT quadrature counters are bytes that
; WRAP: (cur - prev) mod 256 then byte->word sign-extend gives the correct delta for |delta| <= 127 (covers
; any realistic movement per frame). Only touches d0 (reads d1).
gp_delta8:
                ifne    GP_NO_WRAP
        and.w   #$00FF,d0            ; RED: WORD subtraction of the values 0..255 (NO byte modulo)
        and.w   #$00FF,d1
        sub.w   d1,d0               ; -> WRONG delta when crossing $FF/$00 (e.g. $FE->$01 = -253 instead of +3)
        rts
                endc
        sub.b   d1,d0               ; (cur - prev) mod 256
        ext.w   d0                  ; byte -> word sign-extend: correct signed delta despite the wraparound
        rts

; gp_poll(d0.w = current JOY0DAT, d1.w = current CIAA_PRA | $100 if right button pressed | $200 if middle button
; pressed): logical core. Computes dx/dy (vs GP_PREV_JOY, via gp_delta8), detects the left button edge (vs
; GP_PREV_BTN; PRA bit 6 active-low), otherwise the right button edge (vs GP_PREV_RBTN), otherwise the middle one (vs
; GP_PREV_MBTN); a simultaneous second edge waits for the next poll. If movement OR edge, builds a RAWMOUSE
; InputEvent (ie_Code = $68/$69/$6A down, | $80 up, $FF movement; ie_X=dx
; ie_Y=dy) and injects it into input.device (GP_INPUTBASE) via IND_WRITEEVENT. Updates GP_PREV_JOY/GP_PREV_BTN.
; a6 = SysBase on entry (reloaded via ($4).w), a6 = SysBase on exit. Preserves d2-d7/a2-a4 (VERTB server convention).
gp_poll:
        movem.l d2-d7/a2-a4,-(sp)
        moveq   #0,d6
        move.w  d1,d6               ; d6 = CIAA_PRA + right button (saved before the gp_delta8 calls clobber d1)
        move.w  d0,d2               ; d2 = current JOY0DAT
        move.w  GP_PREV_JOY,d3       ; d3 = previous JOY0DAT
        move.b  d2,d0               ; dx = delta8(curX = low byte, prevX = low byte)
        move.b  d3,d1
        bsr     gp_delta8
        move.w  d0,d4               ; d4 = dx
        move.w  d2,d0               ; dy = delta8(curY = high byte, prevY = high byte)
        lsr.w   #8,d0
        move.w  d3,d1
        lsr.w   #8,d1
        bsr     gp_delta8
        move.w  d0,d5               ; d5 = dy
        move.w  d2,GP_PREV_JOY       ; remember the current reading
        moveq   #0,d7               ; d7 = current button pressed (1/0)
        btst    #6,d6               ; CIAA_PRA bit 6: 0 = pressed (active-low)
        bne.s   .gp_notpressed
        moveq   #1,d7
.gp_notpressed:
        moveq   #0,d2               ; d2 = previous button (reuses d2, current JOY already stored)
        move.b  GP_PREV_BTN,d2
        move.b  d7,GP_PREV_BTN       ; remember the current state
        moveq   #0,d1               ; d1 = "emit" flag (0/1)
        moveq   #0,d3               ; d3 = ie_Code
                ifne    GP_NO_EDGE
        tst.l   d7                  ; RED: emits a down on EVERY pressed poll (ignores the edge)
        beq.s   .gp_motion
        move.w  #IECODE_LBUTTON,d3
        moveq   #1,d1
        bra.s   .gp_motion
                endc
                ifeq    GP_NO_EDGE
        cmp.l   d2,d7               ; button edge? (previous vs current)
        beq.s   .gp_right           ; no change -> right button
        tst.l   d7
        beq.s   .gp_release
        move.w  #IECODE_LBUTTON,d3  ; released -> pressed: down ($68)
        moveq   #1,d1
        bra.s   .gp_motion
.gp_release:
        move.w  #(IECODE_LBUTTON|IECODE_UP_PREFIX),d3 ; pressed -> released: up ($E8)
        moveq   #1,d1
                endc
        tst.b   d1
        bne.s   .gp_motion
.gp_right:
        moveq   #0,d7               ; right button: same edge detection
        btst    #8,d6
        beq.s   .gp_rup
        moveq   #1,d7
.gp_rup:
        move.b  GP_PREV_RBTN,d2
        move.b  d7,GP_PREV_RBTN
        cmp.b   d2,d7
        beq.s   .gp_middle
        move.w  #IECODE_RBUTTON,d3
        moveq   #1,d1
        tst.b   d7
        bne.s   .gp_motion
        move.w  #(IECODE_RBUTTON|IECODE_UP_PREFIX),d3
        bra.s   .gp_motion
.gp_middle:
        moveq   #0,d7               ; middle button (DATLX): same edge detection
        btst    #9,d6
        beq.s   .gp_mup
        moveq   #1,d7
.gp_mup:
        move.b  GP_PREV_MBTN,d2
        move.b  d7,GP_PREV_MBTN
        cmp.b   d2,d7
        beq.s   .gp_motion
        move.w  #IECODE_MBUTTON,d3
        moveq   #1,d1
        tst.b   d7
        bne.s   .gp_motion
        move.w  #(IECODE_MBUTTON|IECODE_UP_PREFIX),d3
.gp_motion:
        tst.b   d1
        bne.s   .gp_emit            ; button event already decided -> emit it (with current dx/dy)
        move.w  d4,d0               ; otherwise: is there any movement?
        or.w    d5,d0
        beq     .gp_noemit          ; neither button nor movement -> nothing (anti-flood)
        move.w  #IECODE_NOBUTTON,d3 ; pure movement
        moveq   #1,d1
.gp_emit:
        move.l  GP_INPUTBASE,d0
        beq.s   .gp_noemit          ; no injection target
        move.l  d0,a4               ; a4 = input.device base
        lea     -72(sp),sp          ; stack scratch: InputEvent(22) @ sp, IOStdReq(48) @ sp+24
        move.l  sp,a1               ; build the RAWMOUSE InputEvent
        clr.l   IE_NEXTEVENT(a1)
        move.b  #IECLASS_RAWMOUSE,IE_CLASS(a1)
        clr.b   IE_SUBCLASS(a1)
        move.w  d3,IE_CODE(a1)
        clr.w   IE_QUALIFIER(a1)
        move.w  d4,IE_X(a1)
        move.w  d5,IE_Y(a1)
        lea     24(sp),a3           ; build the IND_WRITEEVENT IOStdReq
        move.l  a4,IO_DEVICE(a3)
        move.w  #IND_WRITEEVENT,IO_COMMAND(a3)
        move.l  sp,IO_DATA2(a3)     ; io_Data = &event (stack base)
        move.l  a4,a6
        move.l  a3,a1
        move.b  #IOF_QUICK,IO_FLAGS(a1)
        jsr     -30(a6)             ; input.device BeginIO (IND_WRITEEVENT) — walks the handler chain
        move.l  ($4).w,a6           ; reload SysBase
        lea     72(sp),sp
.gp_noemit:
        movem.l (sp)+,d2-d7/a2-a4
        rts

; gp_vblank_server(a1 = is_Data = gameport.device base): hardware SHIM. Server on the VERTB chain (AddIntServer)
; -> runs every frame in the running system. Reads the mouse registers of the port input.device chose (GPB_MSRC) and
; calls gp_poll (mouse -> input.device), unless there is no mouse or input.device is stopped;
; runs one frame of unit 0 then unit 1 (gp_unit_frame: events for GPD_READEVENT), then rewrites POTGO through
; WritePotgo(data, allocated), as the 1.3 gameport does every frame (gameport-v34 §7): a program that drove the pins
; differently cannot leave the right/middle buttons dead. Server convention: a6=SysBase (provided), preserves
; d2-d7/a2-a4, returns Z-set (d0=0 -> "continue the chain"). Headless: static JOY0DAT -> gp_poll finds neither
; movement nor edge -> no IND_WRITEEVENT (inert, no effect on M7).
gp_vblank_server:
        movem.l a2-a3,-(sp)
        move.l  a1,a2               ; a2 = gameport.device base (gp_poll preserves a2)
        addq.l  #1,GP_POLLS         ; live proof: one more poll on a REAL VBlank
        move.b  GPB_MSRC(a2),d0
        and.b   #(1<<GPMS_NONE)|(1<<GPMS_STOPPED),d0
        bne.s   .vs_units           ; no mouse, or input.device stopped: the deltas wait in the counters
        bsr     gp_mread
        bsr     gp_poll
.vs_units:
        lea     GPB_UNIT0(a2),a3
        bsr     gp_unit_frame
        lea     GPB_UNIT1(a2),a3
        bsr     gp_unit_frame
        moveq   #0,d1
        move.w  GPB_ALLOC(a2),d1
        move.l  GPB_POTGO(a2),d0
        beq.s   .vs_rawpot
        move.l  a6,-(sp)
        move.l  d0,a6
        moveq   #0,d0
        move.w  GPB_DATA(a2),d0
        jsr     -18(a6)              ; WritePotgo(data, allocated)
        move.l  (sp)+,a6
        bra.s   .vs_ret
.vs_rawpot:
        and.w   GPB_DATA(a2),d1
        move.w  d1,POTGO_W
.vs_ret:
        movem.l (sp)+,a2-a3
        moveq   #0,d0               ; Z-set -> call-all server: continue the VERTB chain
        rts

; gp_install(a6 = SysBase): arms the mouse poller in the running system. (1) publishes the input.device base
; (GP_INPUTBASE) for injection; (2) PRIMES GP_PREV_JOY with the CURRENT JOY0DAT reading (not 0: otherwise a
; spurious delta at the 1st frame) and GP_PREV_BTN with the current button state; (3) sets unit 0 as the 1.3
; input.device leaves it (mouse, trigger {DOWNKEYS|UPKEYS, 0, 1, 1}, gameport-v34 §3.4) with its pot bits; (4)
; registers gp_vblank_server on the VERTB chain (AddIntServer, pri 5). Clobbers d0/d1/a0/a1 (+ whatever AddIntServer clobbers). Call with IRQs masked.
gp_install:
        clr.l   GP_POLLS
        clr.b   GP_LIVE_STAT
        lea     EB_DEVICELIST(a6),a0 ; publish the input.device base (0 if missing -> gp_poll does not inject)
        lea     gp_inputname(pc),a1
        jsr     LVO_FINDNAME(a6)
        move.l  d0,GP_INPUTBASE
        move.w  JOY0DAT,GP_PREV_JOY  ; prime the delta on the current reading (avoids the frame-1 spurious delta)
        moveq   #0,d0
        move.b  CIAA_PRA,d0          ; prime the current button state
        moveq   #0,d1
        btst    #6,d0
        bne.s   .gi_btndone
        moveq   #1,d1
.gi_btndone:
        move.b  d1,GP_PREV_BTN
        movem.l a2-a3,-(sp)
        lea     EB_DEVICELIST(a6),a0
        lea     gameport_dev_name(pc),a1
        jsr     LVO_FINDNAME(a6)
        move.l  d0,a2                ; a2 = gameport.device base
        move.l  d0,GP_VBL_INT+IS_DATA
        lea     EB_RESOURCELIST(a6),a0 ; right/middle buttons (pins 9/5 of port 0): driven high through potgo.resource,
        lea     gp_potgoname(pc),a1  ; pressing pulls the line to 0 -> DATLY/DATLX read as 0
        jsr     LVO_FINDNAME(a6)
        move.l  d0,GPB_POTGO(a2)
        lea     GPB_UNIT0(a2),a3
        move.b  #GPCT_MOUSE,GU_TYPE(a3)
        bset    #GUF_REL,GU_FLAGS(a3)
        move.w  JOY0DAT,GU_REF(a3)
        move.l  #$00030000,GU_TRIG(a3) ; keys = DOWNKEYS|UPKEYS, timeout = 0
        move.l  #$00010001,GU_TRIG+4(a3) ; xdelta = ydelta = 1
        move.l  a6,-(sp)
        move.l  a2,a6
        bsr     gp_potbits
        move.l  (sp)+,a6
        movem.l (sp)+,a2-a3
        moveq   #0,d1
        btst    #10-8,POTINP
        bne.s   .gi_rdone
        moveq   #1,d1
.gi_rdone:
        move.b  d1,GP_PREV_RBTN
        moveq   #0,d1
        btst    #8-8,POTINP
        bne.s   .gi_mdone
        moveq   #1,d1
.gi_mdone:
        move.b  d1,GP_PREV_MBTN
        clr.l   GP_VBL_INT+LN_SUCC   ; struct Interrupt in reserved low RAM (not guaranteed zero at power-on)
        move.b  #5,GP_VBL_INT+LN_PRI ; pri 5: between sched(20) and timer_vblank(0)/vbl_tail(-10) in the VERTB chain
        move.l  #gp_vblank_server,GP_VBL_INT+IS_CODE
        moveq   #INTB_VERTB,d0
        lea     GP_VBL_INT,a1
        jsr     LVO_ADDINTSERVER(a6)
        rts

; gp_mread(gameport base a2) -> d0.w = JOYxDAT of the mouse port, d1.w in the gp_poll format: bit 6 = left button
; released, | $100 right pressed, | $200 middle pressed. Port 1: CIAA PRA bit 7, POTINP DATRY / DATRX.
gp_mread:
        moveq   #0,d1
        move.b  CIAA_PRA,d1
        btst    #GPMS_PORT1,GPB_MSRC(a2)
        bne.s   .mr_p1
        move.w  JOY0DAT,d0
        btst    #10-8,POTINP        ; right button (DATLY, active-low)
        bne.s   .mr_r0
        bset    #8,d1
.mr_r0:
        btst    #8-8,POTINP         ; middle button (DATLX, active-low)
        bne.s   .mr_ret
        bset    #9,d1
.mr_ret:
        rts
.mr_p1:
        lsr.b   #1,d1               ; fire of port 1 (bit 7) onto bit 6
        move.w  JOY1DAT_W,d0
        btst    #14-8,POTINP        ; DATRY
        bne.s   .mr_r1
        bset    #8,d1
.mr_r1:
        btst    #12-8,POTINP        ; DATRX
        bne.s   .mr_ret
        bset    #9,d1
        rts

; gp_mousesrc(d0.b = source, a0 = gameport base): called by input.device (IND_SETMPORT/SETMTYPE/SETMTRIG, CMD_STOP/
; START/RESET). Bit 0 = port, bit 6 = input.device stopped, bit 7 = no mouse. When the port or the no-mouse bit
; changes, the delta and button references are taken again from the new port (no spurious first event); a stop
; alone keeps them, so the motion made meanwhile arrives at the restart. Task context. Preserves d2-d7/a2-a6.
gp_mousesrc:
        move.l  a2,-(sp)
        move.l  a0,a2
        bsr     gp_dis
        move.b  GPB_MSRC(a2),d1
        move.b  d0,GPB_MSRC(a2)
        eor.b   d0,d1
        and.b   #(1<<GPMS_NONE)|(1<<GPMS_PORT1),d1
        beq.s   .ms_ena
        bsr.s   gp_mread
        move.w  d0,GP_PREV_JOY
        moveq   #0,d0
        btst    #6,d1
        seq     d0
        neg.b   d0
        move.b  d0,GP_PREV_BTN
        moveq   #0,d0
        btst    #8,d1
        sne     d0
        neg.b   d0
        move.b  d0,GP_PREV_RBTN
        moveq   #0,d0
        btst    #9,d1
        sne     d0
        neg.b   d0
        move.b  d0,GP_PREV_MBTN
.ms_ena:
        bsr     gp_ena
        move.l  (sp)+,a2
        rts

gp_inputname:
        dc.b    "input.device",0
gp_potgoname:
        dc.b    "potgo.resource",0
        EVEN
gameport_end:
