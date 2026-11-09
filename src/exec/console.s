; src/exec/console.s — console.device (#3a: on-screen text rendering by blitting 8x8 glyphs).
;
; ROMTag RTF_AUTOINIT NT_DEVICE pri 20 -> MakeLibrary (AUTOINIT path) creates the base, Enqueue into EB_DEVICELIST.
; initfunc allocates a 1-plane BITPLANE (CON_BMSIZE bytes, chip RAM) and the text state (cursor). BeginIO dispatches:
;   CMD_WRITE (io_Data=buf, io_Length=len): interprets the stream byte by byte (con_putglyph) — printable
;     character -> BLIT of the 8x8 glyph (CPU copy of 8 bytes from font8x8 into the bitplane at (curx,cury)) +
;     advances the column; CR -> column 0; LF / column overflow -> next line (+8 px, clamped).
; Blitter = synchronous CPU COPY (not the hardware Blitter): simple AND immediate (the proof readback sees the
; bytes at once, no blitter-done wait). graphics.library has no Text() -> rendering done here.
;
; Scope #3a: WRITE rendering proven by READBACK of the bitplane (headless, serial marker "CONSOLE WRITE OK"); the
; ON-SCREEN rendering (pointing the Copper at this bitplane) and keyboard reading (#3b, via input.device) are separate.
; That shared-bitplane path (no window) keeps those limits: no scrolling, no CSI, no cursor. Window units (OpenDevice
; with a Window) follow docs/analysis/console-keymap-v34.md: see "window units" below.
; HAND-AUTHORED 8x8 font (public domain, tests/mk_font8x8.py) — NEVER the ROM's topaz (clean-room).
; IMPLEMENTATION track ("clean"): AutoDocs console.device + public NDK includes. NO ROM reading.

                include "exec.i"
                include "graphics.i"
                include "intuition.i"

                xref    font8x8          ; graphics/font8x8.s (8x8 glyphs, ASCII 0x20..0x7F)
                xref    km_conv          ; exec/keymap.s: one RAWKEY event -> bytes through a struct KeyMap

CMD_RESET    EQU 1                ; standard io_Command (exec/io.i)
CMD_READ     EQU 2
CMD_CLEAR    EQU 5
CMD_STOP     EQU 6
CMD_START    EQU 7
CMD_FLUSH    EQU 8
CD_ASKKEYMAP        EQU 9        ; devices/console.h
CD_SETKEYMAP        EQU 10
CD_ASKDEFAULTKEYMAP EQU 11
CD_SETDEFAULTKEYMAP EQU 12
IOERR_BADLENGTH     EQU -4
CMD_WRITE    EQU 3
IO_DATA2     EQU 40               ; IOStdReq io_Data (local: console.s does not include disk.i)
IO_LEN2      EQU 36               ; IOStdReq io_Length
IO_ACTUAL2   EQU 32               ; IOStdReq io_Actual

; --- console.device ROMTag (scanned by build_reslist) ---
                EVEN
console_romtag:
        dc.w    RTC_MATCHWORD
        dc.l    console_romtag       ; RT_MATCHTAG = self
        dc.l    console_end          ; RT_ENDSKIP
        dc.b    RTF_AUTOINIT|RTF_COLDSTART,34,NT_DEVICE,20  ; RT_FLAGS, RT_VERSION, RT_TYPE, RT_PRI (20: console roadmap slot)
        dc.l    console_name         ; RT_NAME
        dc.l    console_name         ; RT_IDSTRING
        dc.l    console_inittab      ; RT_INIT -> AUTOINIT table
console_name:
        dc.b    "console.device",0
        EVEN
console_inittab:
        dc.l    CONDEV_SIZE          ; dataSize
        dc.l    console_vectors      ; funcTable
        dc.l    console_datatab      ; dataTable (InitStruct)
        dc.l    console_initfunc     ; initFunc
console_vectors:                     ; ABSOLUTE table, terminated by -1 (standard device order)
        dc.l    console_open         ; LVO -6
        dc.l    console_close        ; LVO -12
        dc.l    console_expunge      ; LVO -18
        dc.l    console_null         ; LVO -24 (reserved)
        dc.l    console_beginio      ; LVO -30
        dc.l    console_abortio      ; LVO -36
        dc.l    console_CDInputHandler ; LVO -42 CDInputHandler(events a0, console a1) -> 0
        dc.l    console_rawkeyconvert ; LVO -48 RawKeyConvert(events a0, buffer a1, length d1, keymap a2)
        dc.l    -1
console_datatab:
        dc.w    $E000,LN_TYPE,(NT_DEVICE<<8)   ; INITBYTE(LN_TYPE, NT_DEVICE)
        dc.w    $D000,LIB_VERSION,34           ; INITWORD(LIB_VERSION, 34)
        dc.b    0
        EVEN

; Open(iorequest a1, unit d0, flags d1): io_Data = window (NEWCON:, CON:) -> io_Unit = ConUnit allocated for
; that window (devices/conunit.h: cu_Window, cursor, bounds of the text area); io_Data = 0 -> io_Unit = the
; base (shared bitplane, without window). The requests of an open unit follow the standard exec semantics
; (ReplyMsg reply unless IOF_QUICK, CMD_READ put on hold as long as no character has arrived).
console_open:
        movem.l a2/a6,-(sp)
        move.l  a1,a2
        clr.b   IO_ERROR(a2)
        addq.l  #1,d0                ; unit -1 (CONU_LIBRARY): no window, base only (RawKeyConvert)
        beq.s   .co_lib
        move.l  IO_DATA2(a2),d0
        bne.s   .co_win
.co_lib:
        move.l  a6,IO_UNIT(a2)
        bra.s   .co_ok
.co_win:
        move.l  ($4).w,a6
        move.l  #CU_SIZE,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  4(sp),a6             ; a6 = console base
        tst.l   d0
        bne.s   .co_unit
        move.b  #-1,IO_ERROR(a2)     ; IOERR_OPENFAIL
        bra.s   .co_ret
.co_unit:
        move.l  d0,a0
        move.l  IO_DATA2(a2),a1
        bsr     cu_init
        move.l  a0,IO_UNIT(a2)
        lea     CONB_DEFKM(a6),a1    ; the unit's keymap: copy of the current default keymap
        lea     CU_KEYMAP(a0),a0
        moveq   #KM_SIZEOF/4-1,d0
.co_km:
        move.l  (a1)+,(a0)+
        dbra    d0,.co_km
        move.l  IO_UNIT(a2),a0
        move.l  a0,-(sp)             ; unit linked into CONB_UNITS (routing of keys to the active window)
        move.l  ($4).w,a6
        jsr     LVO_DISABLE(a6)
        move.l  4+4(sp),a1           ; a1 = console base
        move.l  (sp),a0
        move.l  a1,CU_BASE(a0)
        move.l  CONB_UNITS(a1),CU_NEXT(a0)
        move.l  a0,CONB_UNITS(a1)
        jsr     LVO_ENABLE(a6)
        addq.l  #4,sp
        move.l  4(sp),a6
.co_ok:
        addq.w  #1,LIB_OPENCNT(a6)
.co_ret:
        movem.l (sp)+,a2/a6
        rts
; RawKeyConvert(events a0, buffer a1, length d1, keymap a2 | 0 = the default keymap) -> d0 = bytes written for the
; whole chain (RAWKEY events only), -1 as soon as one result does not fit (spec console-keymap-v34 §5.3).
console_rawkeyconvert:
        movem.l d2-d3/a2-a4,-(sp)
        move.l  a2,d0
        bne.s   .rk_km
        lea     CONB_DEFKM(a6),a2
.rk_km:
        move.l  a0,a3                ; a3 = event
        move.l  a1,a4                ; a4 = output
        move.l  d1,d3                ; d3 = room
        moveq   #0,d2                ; d2 = total
.rk_lp:
        move.l  a3,d0
        beq.s   .rk_done
        cmp.b   #IECLASS_RAWKEY,IE_CLASS(a3)
        bne.s   .rk_nx
        move.l  a3,a0
        move.l  a4,a1
        move.l  d3,d1
        jsr     km_conv
        tst.l   d0
        bmi.s   .rk_ret
        add.l   d0,a4
        add.l   d0,d2
        sub.l   d0,d3
.rk_nx:
        move.l  IE_NEXTEVENT(a3),a3
        bra.s   .rk_lp
.rk_done:
        move.l  d2,d0
.rk_ret:
        movem.l (sp)+,d2-d3/a2-a4
        rts
        even

; Close(iorequest a1): frees the ConUnit of a window unit.
console_close:
        subq.w  #1,LIB_OPENCNT(a6)
        move.l  IO_UNIT(a1),d0
        beq.s   .cc_ret
        cmp.l   a6,d0
        beq.s   .cc_ret
        cmp.l   #-1,d0               ; unit -1 (SetMap restores it before CloseDevice): no ConUnit
        beq.s   .cc_ret
        clr.l   IO_UNIT(a1)
        move.l  a6,-(sp)
        move.l  d0,-(sp)
        move.l  ($4).w,a6
        jsr     LVO_DISABLE(a6)
        move.l  4(sp),a0             ; reads still pending on this unit are unhooked without a reply: a handler
        lea     CONB_RQ(a0),a0       ; that closes without AbortIO (Newcon-Handler) leaves one, on its stack
        move.l  (sp),d0
.cc_rq:
        move.l  (a0),d1
        beq.s   .cc_rqd
        move.l  d1,a1
        cmp.l   IO_UNIT(a1),d0
        bne.s   .cc_rqn
        move.l  (a1),(a0)
        bra.s   .cc_rq
.cc_rqn:
        move.l  a1,a0
        bra.s   .cc_rq
.cc_rqd:
        move.l  4(sp),a0             ; a0 = console base: unit removed from CONB_UNITS
        lea     CONB_UNITS(a0),a0
.cc_find:
        move.l  (a0),d1
        beq.s   .cc_gone
        cmp.l   d1,d0
        beq.s   .cc_unl
        move.l  d1,a0
        lea     CU_NEXT(a0),a0
        bra.s   .cc_find
.cc_unl:
        move.l  d0,a1
        move.l  CU_NEXT(a1),(a0)
.cc_gone:
        jsr     LVO_ENABLE(a6)
        move.l  (sp)+,a1
        move.l  #CU_SIZE,d0
        jsr     LVO_FREEMEM(a6)
        move.l  (sp)+,a6
.cc_ret:
        moveq   #0,d0
        rts
console_expunge:
        moveq   #0,d0
        rts
console_null:
        moveq   #0,d0
        rts
; AbortIO(iorequest a1): removes a pending CMD_READ (io_Error = IOERR_ABORTED) and replies to it. -> d0 = 0.
console_abortio:
        movem.l a2/a6,-(sp)
        move.l  a6,a2
        move.l  ($4).w,a6
        jsr     LVO_DISABLE(a6)
        lea     CONB_RQ(a2),a0       ; a0 = previous link (LN_SUCC at offset 0)
.ca_lp:
        move.l  (a0),d0
        beq.s   .ca_none
        cmp.l   d0,a1
        beq.s   .ca_found
        move.l  d0,a0
        bra.s   .ca_lp
.ca_found:
        move.l  (a1),(a0)            ; unhook
        move.b  #IOERR_ABORTED,IO_ERROR(a1)
        jsr     LVO_ENABLE(a6)
        jsr     LVO_REPLYMSG(a6)
        bra.s   .ca_ret
.ca_none:
        jsr     LVO_ENABLE(a6)
.ca_ret:
        moveq   #0,d0
        movem.l (sp)+,a2/a6
        rts

; console_beginio(device a6, ioreq a1): CMD_WRITE -> renders the stream. Synchronous. a6 on exit = device base.
console_beginio:
        movem.l d4/a2-a4,-(sp)
        move.l  a6,a2                ; a2 = device base (= console state)
        move.l  a1,a3                ; a3 = ioreq
        clr.b   IO_ERROR(a3)
        tst.l   IO_UNIT(a3)
        bne     .bi_unit             ; open unit: asynchronous semantics
        move.w  IO_COMMAND(a3),d0
        cmp.w   #CMD_WRITE,d0
        beq.s   .bi_write
        cmp.w   #CMD_READ,d0
        beq.s   .bi_read
        move.b  #IOERR_NOCMD,IO_ERROR(a3)
        bra.s   .bi_done
.bi_write:
        move.l  IO_DATA2(a3),a4      ; a4 = buffer
        move.l  IO_LEN2(a3),d4       ; d4 = length
.bi_wl:
        tst.l   d4
        beq.s   .bi_done
        move.b  (a4)+,d0
        bsr     con_putglyph         ; renders one byte (a2 = base; clobbers d0/d1/a0/a1)
        subq.l  #1,d4
        bra.s   .bi_wl
.bi_read:                            ; #3b: drains the window-less ring (ASCII cooked via input.device) into io_Data
        move.l  a3,a1
        bsr     con_fillread
.bi_done:
        move.l  a2,a6                ; a6 = device base (BeginIO convention)
        movem.l (sp)+,d4/a2-a4
        rts
; --- open unit (request from OpenDevice): direct synchronous callers = null IO_UNIT (path above) ---
.bi_unit:
        move.w  IO_COMMAND(a3),d0
        cmp.w   #CMD_WRITE,d0
        beq     .bu_write
        cmp.w   #CMD_READ,d0
        beq     .bu_read
        cmp.w   #CMD_RESET,d0
        beq     .bu_ctl
        cmp.w   #CMD_CLEAR,d0
        blo.s   .bu_nocmd            ; CMD_INVALID, CMD_UPDATE
        cmp.w   #CMD_FLUSH,d0
        bls     .bu_ctl
        cmp.w   #CD_ASKKEYMAP,d0     ; CD_ASKKEYMAP, CD_SETKEYMAP, CD_ASKDEFAULTKEYMAP, CD_SETDEFAULTKEYMAP
        cmp.w   #CD_SETDEFAULTKEYMAP,d0
        bhi.s   .bu_nocmd
        cmp.l   #KM_SIZEOF,IO_LEN2(a3)
        beq.s   .bu_kmlen
        move.b  #IOERR_BADLENGTH,IO_ERROR(a3)
        bra     .bu_reply
.bu_kmlen:
        lea     CONB_DEFKM(a2),a0    ; device default keymap, or the unit's own (CD_ASK/SETKEYMAP on a window unit)
        cmp.w   #CD_ASKDEFAULTKEYMAP,d0
        bhs.s   .bu_kmsel
        move.l  IO_UNIT(a3),a1
        cmp.l   a2,a1
        beq.s   .bu_kmsel
        lea     CU_KEYMAP(a1),a0
.bu_kmsel:
        move.l  IO_DATA2(a3),a1
        btst    #0,d0                ; odd = ASK (copy out), even = SET (copy in)
        bne.s   .bu_kmcp
        exg     a0,a1
.bu_kmcp:
        move.l  a6,-(sp)
        move.l  ($4).w,a6
        jsr     LVO_FORBID(a6)
        moveq   #KM_SIZEOF/4-1,d1
.bu_kml:
        move.l  (a0)+,(a1)+
        dbra    d1,.bu_kml
        jsr     LVO_PERMIT(a6)
        move.l  (sp)+,a6
        move.l  #KM_SIZEOF,IO_ACTUAL2(a3)
        bra     .bu_reply
.bu_nocmd:
        move.b  #IOERR_NOCMD,IO_ERROR(a3)
        bra     .bu_reply
.bu_write:
        move.l  IO_DATA2(a3),a4
        move.l  IO_LEN2(a3),d4
        cmp.l   #-1,d4               ; io_Length = -1: 0-terminated string
        bne.s   .bu_len
        moveq   #0,d4
        move.l  a4,a0
.bu_strlen:
        tst.b   (a0)+
        beq.s   .bu_len
        addq.l  #1,d4
        bra.s   .bu_strlen
.bu_len:
        move.l  d4,IO_ACTUAL2(a3)
        move.l  IO_UNIT(a3),a0
        cmp.l   a2,a0
        beq.s   .bu_wl               ; unit without window: shared bitplane
        move.l  CU_WINDOW(a0),a1
        tst.l   WD_RPORT(a1)
        beq.s   .bu_wl               ; window without RastPort: shared bitplane
        tst.l   CONB_GFXBASE(a2)
        beq.s   .bu_wl
        bsr     cu_rpwrite
        bra     .bu_reply
.bu_wl:
        tst.l   d4
        beq     .bu_reply
        move.b  (a4)+,d0
        bsr     con_putglyph
        subq.l  #1,d4
        bra.s   .bu_wl
.bu_read:
        tst.l   IO_LEN2(a3)
        bne.s   .bu_rlen
        move.b  #IOERR_BADLENGTH,IO_ERROR(a3) ; 1.3 replies -4 then misbehaves (console-keymap-v34 §6.3)
        bra     .bu_reply
.bu_rlen:
        move.l  ($4).w,a6
        jsr     LVO_DISABLE(a6)
        move.l  a3,a1
        bsr     con_stopped
        bne.s   .bu_queue            ; CMD_STOP: reads wait for CMD_START
        move.l  a3,a1
        bsr     con_fillread         ; d0 = bytes copied
        tst.l   d0
        bne.s   .bu_rgot
.bu_queue:
        move.b  #NT_MESSAGE,LN_TYPE(a3)  ; pending: exec's DoIO/SendIO leave ln_Type to the device
        bclr    #0,IO_FLAGS(a3)      ; nothing to read: on hold (reply by the input handler)
        clr.l   (a3)                 ; LN_SUCC = end of queue
        lea     CONB_RQ(a2),a0
.bu_tail:
        tst.l   (a0)
        beq.s   .bu_link
        move.l  (a0),a0
        bra.s   .bu_tail
.bu_link:
        move.l  a3,(a0)
        jsr     LVO_ENABLE(a6)
        bra     .bi_done
.bu_rgot:
        jsr     LVO_ENABLE(a6)
        bra     .bu_reply
; CMD_CLEAR empties the input buffer, CMD_STOP holds the unit's reads (writes go on), CMD_START releases them,
; CMD_FLUSH returns the unit's queued reads with IOERR_ABORTED, CMD_RESET = STOP + FLUSH + START. io_Error = 0
; (1.3 leaves the caller's D0 there), and CMD_CLEAR replies like the others (1.3 never returns it).
.bu_ctl:
        move.w  d0,d4
        move.l  IO_UNIT(a3),a4
        cmp.l   #-1,a4               ; SetMap's unit -1: no ConUnit
        beq     .bu_reply
        lea     CU_STOP(a4),a4
        cmp.l   IO_UNIT(a3),a2
        bne.s   .bc_flag
        lea     CONB_STOP(a2),a4     ; unit without window
.bc_flag:
        move.l  ($4).w,a6
        jsr     LVO_DISABLE(a6)
        cmp.w   #CMD_CLEAR,d4
        bne.s   .bc_nclr
        move.l  IO_UNIT(a3),a0
        bsr     con_ring
        move.w  CRG_TAIL(a0),CRG_HEAD(a0)
.bc_nclr:
        cmp.w   #CMD_STOP,d4
        bne.s   .bc_nstop
        st      (a4)
.bc_nstop:
        cmp.w   #CMD_FLUSH,d4
        beq.s   .bc_flush
        cmp.w   #CMD_RESET,d4
        bne.s   .bc_nflush
.bc_flush:
        lea     CONB_RQ(a2),a0       ; a0 = previous link
.bc_fl:
        move.l  (a0),d1
        beq.s   .bc_nflush
        move.l  d1,a1
        move.l  IO_UNIT(a1),d1
        cmp.l   IO_UNIT(a3),d1
        beq.s   .bc_abort
        move.l  a1,a0
        bra.s   .bc_fl
.bc_abort:
        move.l  (a1),(a0)            ; unhook
        move.b  #IOERR_ABORTED,IO_ERROR(a1)
        move.l  a0,-(sp)
        jsr     LVO_REPLYMSG(a6)
        move.l  (sp)+,a0
        bra.s   .bc_fl
.bc_nflush:
        cmp.w   #CMD_START,d4
        beq.s   .bc_run
        cmp.w   #CMD_RESET,d4
        bne.s   .bc_end
.bc_run:
        sf      (a4)
.bc_end:
        jsr     LVO_ENABLE(a6)
        cmp.w   #CMD_START,d4
        bne.s   .bu_reply
        bsr     con_servereads
.bu_reply:
        btst    #0,IO_FLAGS(a3)      ; IOF_QUICK: completed in place
        bne     .bi_done
        move.l  ($4).w,a6
        move.l  a3,a1
        jsr     LVO_REPLYMSG(a6)
        bra     .bi_done

; con_push(a0 = bytes, a1 = ring, d2.w = count > 0) -> Z = 1 if they do not all fit (nothing pushed). Two producers
; (the input handler, the reports of a write), the input chain also runs in the VBlank interrupt: bare Disable.
; Clobbers d0-d2/a0.
con_push:
        move.l  a3,-(sp)
        move.l  ($4).w,a3
        addq.b  #1,EB_IDNEST(a3)
        move.w  #INTF_INTEN,INTENA
        move.w  CRG_HEAD(a1),d0       ; free room in the ring
        sub.w   CRG_TAIL(a1),d0
        subq.w  #1,d0
        and.w   #CRG_MASK,d0
        cmp.w   d2,d0
        blo.s   .ps_full
        move.w  CRG_TAIL(a1),d0
        subq.w  #1,d2
.ps_lp:
        move.b  (a0)+,CRG_BUF(a1,d0.w)
        addq.w  #1,d0
        and.w   #CRG_MASK,d0
        dbra    d2,.ps_lp
        move.w  d0,CRG_TAIL(a1)
        moveq   #1,d2                ; Z = 0
        bra.s   .ps_on
.ps_full:
        moveq   #0,d2                ; Z = 1
.ps_on:
        subq.b  #1,EB_IDNEST(a3)
        bge.s   .ps_ret
        move.w  #$C000,INTENA        ; SETCLR + INTEN
.ps_ret:
        move.l  (sp)+,a3
        tst.l   d2
        rts

; con_ring(a0 = io_Unit, a2 = base) -> a0 = read ring of that unit: the ConUnit's, or the base's for the units
; without a window (the base, -1, none). Preserves everything else.
con_ring:
        cmp.l   a2,a0
        beq.s   .rg_base
        cmpa.w  #-1,a0
        beq.s   .rg_base
        cmpa.w  #0,a0
        beq.s   .rg_base
        lea     CU_RING(a0),a0
        rts
.rg_base:
        lea     CONB_RING(a2),a0
        rts

; con_fillread(a1 = CMD_READ, a2 = base): copies its unit's ring into io_Data (at most io_Length bytes, one for a
; negative length) -> d0 = bytes copied = io_Actual. Clobbers d1/a0.
con_fillread:
        movem.l d2/a3,-(sp)
        move.l  IO_UNIT(a1),a0
        bsr.s   con_ring
        move.l  IO_DATA2(a1),a3
        move.l  IO_LEN2(a1),d2
        bpl.s   .cf_go
        moveq   #1,d2                ; -1: one byte at most (§6.3)
.cf_go:
        moveq   #0,d0
.cf_lp:
        tst.l   d2
        beq.s   .cf_done
        move.w  CRG_HEAD(a0),d1
        cmp.w   CRG_TAIL(a0),d1
        beq.s   .cf_done
        move.b  CRG_BUF(a0,d1.w),(a3)+
        addq.w  #1,d1
        and.w   #CRG_MASK,d1
        move.w  d1,CRG_HEAD(a0)
        addq.l  #1,d0
        subq.l  #1,d2
        bra.s   .cf_lp
.cf_done:
        move.l  d0,IO_ACTUAL2(a1)
        movem.l (sp)+,d2/a3
        rts

; con_putglyph(d0.b = character, a2 = console base): renders one byte. Clobbers d0/d1/a0/a1; preserves the rest
; (saves d2/d3 for the blit). CR -> column 0; LF / wrap -> next line (+8, clamped); printable -> blit.
con_putglyph:
        tst.b   CONB_ESC(a2)         ; ESC / CSI sequence in progress: ignored (no ANSI interpretation)
        beq.s   .cpg_plain
        cmp.b   #1,CONB_ESC(a2)
        bne.s   .cpg_csi
        move.b  #2,CONB_ESC(a2)      ; ESC followed by '[' = CSI; other character = end of sequence
        cmp.b   #'[',d0
        beq     .cpg_ret
        clr.b   CONB_ESC(a2)
        rts
.cpg_csi:
        cmp.b   #$40,d0              ; final byte of a CSI: $40..$7E
        blo     .cpg_ret
        cmp.b   #$7E,d0
        bhi     .cpg_ret
        clr.b   CONB_ESC(a2)
        rts
.cpg_plain:
        cmp.b   #$1B,d0
        bne.s   .cpg_n9b
        move.b  #1,CONB_ESC(a2)
        rts
.cpg_n9b:
        cmp.b   #$9B,d0
        bne.s   .cpg_chr
        move.b  #2,CONB_ESC(a2)
        rts
.cpg_chr:
        cmp.b   #13,d0
        beq     .cpg_cr
        cmp.b   #10,d0
        beq     .cpg_nl
        cmp.b   #$20,d0
        blo     .cpg_ret             ; control (<space) not handled -> ignore
        cmp.b   #$7F,d0
        bhi     .cpg_ret
                ifeq    CON_NO_BLIT
        move.l  CONB_BITMAP(a2),d1
        bne.s   .cpg_have
        movem.l d0/a6,-(sp)          ; bitplane of the windowless unit: allocated at the first write (10 KB of
        move.l  ($4).w,a6            ; chip that windowed systems never use)
        move.l  #CON_BMSIZE,d0
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  d0,CONB_BITMAP(a2)
        move.l  d0,d1
        movem.l (sp)+,d0/a6
        tst.l   d1
        beq.s   .cpg_advance         ; no bitplane (alloc failed) -> does not write, advances anyway
.cpg_have:
        movem.l d2/d3,-(sp)
        moveq   #0,d1
        move.b  d0,d1
        subi.w  #$20,d1
        lsl.w   #3,d1                ; (char-0x20)*8 = glyph offset
        move.l  #font8x8,a0
        add.l   d1,a0                ; a0 = glyph (8 bytes)
        move.l  CONB_BITMAP(a2),a1
        moveq   #0,d2
        move.w  CONB_BWIDTH(a2),d2   ; d2 = stride (bytes/line)
        moveq   #0,d1
        move.w  CONB_CURY(a2),d1
        mulu    d2,d1                ; cury * stride (cury<256, stride=40 -> <10240)
        add.l   d1,a1
        moveq   #0,d1
        move.w  CONB_CURX(a2),d1
        add.l   d1,a1                ; a1 = dest = bitplane + cury*stride + curx
        moveq   #7,d3                ; 8 lines
.cpg_row:
        move.b  (a0)+,(a1)           ; glyph byte -> bitplane
        add.w   d2,a1                ; next line (+stride)
        dbra    d3,.cpg_row
        movem.l (sp)+,d2/d3
                endc                 ; RED CON_NO_BLIT: blit skipped -> non-space cells stay at 0
.cpg_advance:
        addq.w  #1,CONB_CURX(a2)     ; advance the column
        cmp.w   #CON_COLS,CONB_CURX(a2)
        blo.s   .cpg_ret
        clr.w   CONB_CURX(a2)        ; overflow -> column 0 + next line
        bra.s   .cpg_nl
.cpg_cr:
        clr.w   CONB_CURX(a2)        ; carriage return
        bra.s   .cpg_ret
.cpg_nl:
        move.w  CONB_CURY(a2),d0     ; next line (+8 px)
        add.w   #8,d0
        cmp.w   #CON_PXH,d0
        blo.s   .cpg_sety
        move.w  #CON_PXH-8,d0        ; clamp at the bottom (no scroll this milestone)
.cpg_sety:
        move.w  d0,CONB_CURY(a2)
.cpg_ret:
        rts

; CDInputHandler(events a0, console device a1) -> d0 = 0: the console's input processing for a chain handed over by
; the caller, which it consumes (spec console-keymap-v34 §6.1).
console_CDInputHandler:
        bsr.s   console_input_handler
        moveq   #0,d0
        rts

; console_input_handler(a0 = InputEvent list, a1 = is_Data = console base): handler registered on input.device via
; IND_ADDHANDLER (spec console-keymap-v34 §6.1). Each event goes to the unit whose window is active, or to every unit
; when its qualifier carries IEQUALIFIER_MULTIBROADCAST; with no window active at all, a key goes to the window-less
; ring. For a unit that asked for its class with CSI n {, a raw report CSI class;subclass;code;qualifier;x;y;seconds;
; microseconds | goes into its ring, truncated if it does not fit; any other RAWKEY is converted through the unit's
; keymap and its bytes go in only if they all fit. Then the waiting CMD_READs are served. Returns d0 = unchanged
; list (pass-through). Preserves d2-d7/a2-a6.
CIH_CONV        EQU 0                    ; frame: conversion buffer (128 bytes), raw report (96 bytes)
CIH_RAW         EQU CIH_CONV+128
CIH_SIZE        EQU CIH_RAW+96
IEQUALIFIERB_MULTIBROADCAST EQU 11
console_input_handler:
        movem.l d2-d5/a2-a6,-(sp)
        lea     -CIH_SIZE(sp),sp
        move.l  sp,a5                ; a5 = frame
        move.l  a0,d3                ; d3 = original list (pass-through return)
        move.l  a1,a2                ; a2 = console base
        move.l  a0,a3                ; a3 = current event
        move.l  ($4).w,a6
        moveq   #0,d5                ; d5 != 0: bytes went into a ring
.cih_loop:
        move.l  a3,d0
        beq.s   .cih_done
        ; A CON: handler that preempts this task can CloseDevice and free a unit: the units are walked with
        ; interrupts off (bare Disable: the input chain also runs from the VBlank interrupt).
        addq.b  #1,EB_IDNEST(a6)
        move.w  #INTF_INTEN,INTENA
        move.w  IE_QUALIFIER(a3),d0
        btst    #IEQUALIFIERB_MULTIBROADCAST,d0
        bne.s   .cih_all
        bsr     con_target
        bne.s   .cih_one
        move.l  CONB_IBASE(a2),d0    ; a key whose active window is not a console belongs to that window only: 1.3
        beq.s   .cih_free            ; never keeps it for a console opened later (§6.4)
        move.l  d0,a0
        tst.l   52(a0)               ; ib_ActiveWindow
        bne.s   .cih_en
.cih_free:
        suba.l  a4,a4
        bsr.s   cih_unit
        bra.s   .cih_en
.cih_one:
        move.l  d0,a4
        bsr.s   cih_unit
        bra.s   .cih_en
.cih_all:
        move.l  CONB_UNITS(a2),d0
.cih_al:
        beq.s   .cih_en
        move.l  d0,a4
        bsr.s   cih_unit
        move.l  CU_NEXT(a4),d0
        bra.s   .cih_al
.cih_en:
        subq.b  #1,EB_IDNEST(a6)
        bge.s   .cih_next
        move.w  #$C000,INTENA        ; SETCLR + INTEN
.cih_next:
        move.l  IE_NEXTEVENT(a3),a3
        bra.s   .cih_loop
.cih_done:
                ifeq    CON_NO_READBUF
        tst.l   d5
        beq.s   .cih_ret
        bsr     con_servereads       ; waiting CMD_READs served and replied
                endc                 ; RED CON_NO_READBUF: converts but never serves -> CMD_READ stays empty
.cih_ret:
        move.l  d3,d0                ; return the original list (pass-through)
        lea     CIH_SIZE(sp),sp
        movem.l (sp)+,d2-d5/a2-a6
        rts

; cih_unit(a3 = event, a4 = ConUnit | 0 = the window-less ring, a5 = frame, a2 = base), under Disable: the event for
; this unit (raw report or cooked key). Sets d5 when bytes went in. Clobbers d0-d2/d4/a0/a1.
cih_unit:
        move.l  a4,d0
        beq.s   .cu_cook             ; no raw report without a unit
        moveq   #0,d1
        move.b  IE_CLASS(a3),d1
        cmp.w   #18,d1
        bhi.s   .cu_cook
        move.w  d1,d0
        lsr.w   #3,d0
        and.w   #7,d1
        lea     CU_RAWEV(a4),a0
        btst    d1,0(a0,d0.w)
        beq.s   .cu_cook
        lea     CIH_RAW(a5),a0
        bsr     con_rawreport        ; a0 = end of the report
        move.l  a0,d4
        lea     CIH_RAW(a5),a0
        sub.l   a0,d4                ; d4 = its length
        lea     CU_RING(a4),a1
.cu_rawpush:                         ; byte by byte: what does not fit is lost (truncated report)
        moveq   #1,d2
        bsr     con_push
        beq.s   .cu_ret
        st      d5
        subq.l  #1,d4
        bne.s   .cu_rawpush
        rts
.cu_cook:
        cmp.b   #IECLASS_RAWKEY,IE_CLASS(a3)
        bne.s   .cu_ret
        move.l  a2,-(sp)
        lea     CONB_DEFKM(a2),a2
        move.l  a4,d0
        beq.s   .cu_km
        lea     CU_KEYMAP(a4),a2
.cu_km:
        move.l  a3,a0
        lea     CIH_CONV(a5),a1
        moveq   #127,d1              ; 1.3 converts into a 127-byte buffer (§6.1)
        jsr     km_conv
        move.l  (sp)+,a2
        move.l  d0,d2                ; d2 = bytes
        ble.s   .cu_ret
        lea     CIH_CONV(a5),a0
        lea     CONB_RING(a2),a1
        move.l  a4,d0
        beq.s   .cu_push
        lea     CU_RING(a4),a1
.cu_push:
        bsr     con_push             ; all or nothing
        beq.s   .cu_ret
        st      d5
.cu_ret:
        rts

; con_rawreport(a3 = event, a0 = buffer) -> a0 = end of CSI class;subclass;code;qualifier;x;y;seconds;microseconds |
; (decimal, x and y unsigned, bit 31 of the time cleared). Clobbers d0/d1.
con_rawreport:
        move.b  #$9B,(a0)+
        moveq   #0,d0
        move.b  IE_CLASS(a3),d0
        bsr.s   .rr_num
        moveq   #0,d0
        move.b  IE_SUBCLASS(a3),d0
        bsr.s   .rr_num
        moveq   #0,d0
        move.w  IE_CODE(a3),d0
        bsr.s   .rr_num
        moveq   #0,d0
        move.w  IE_QUALIFIER(a3),d0
        bsr.s   .rr_num
        moveq   #0,d0
        move.w  IE_X(a3),d0
        bsr.s   .rr_num
        moveq   #0,d0
        move.w  IE_Y(a3),d0
        bsr.s   .rr_num
        move.l  IE_TIMESTAMP(a3),d0
        bclr    #31,d0
        bsr.s   .rr_num
        move.l  IE_TIMESTAMP+4(a3),d0
        bclr    #31,d0
        bsr     cu_dec
        move.b  #'|',(a0)+
        rts
.rr_num:
        bsr     cu_dec
        move.b  #';',(a0)+
        rts

; con_servereads(a2 = base): every waiting CMD_READ whose unit is not stopped and whose ring has bytes is filled,
; unhooked and replied, in queue order. Preserves d2-d7/a2-a6.
con_servereads:
        movem.l a3-a4/a6,-(sp)
        move.l  ($4).w,a6
.sr_again:
        jsr     LVO_DISABLE(a6)
        lea     CONB_RQ(a2),a4       ; a4 = previous link
.sr_find:
        move.l  (a4),d0
        beq.s   .sr_none
        move.l  d0,a3
        move.l  a3,a1
        bsr     con_stopped
        bne.s   .sr_next
        move.l  a3,a1
        bsr     con_fillread
        tst.l   d0
        bne.s   .sr_take
.sr_next:
        move.l  a3,a4
        bra.s   .sr_find
.sr_take:
        move.l  (a3),(a4)            ; unhook the served request
        jsr     LVO_ENABLE(a6)
        move.l  a3,a1
        jsr     LVO_REPLYMSG(a6)
        bra.s   .sr_again
.sr_none:
        jsr     LVO_ENABLE(a6)
        movem.l (sp)+,a3-a4/a6
        rts

; con_stopped(a1 = ioreq, a2 = base) -> Z = 0 when the request's unit is stopped by CMD_STOP. Preserves all but d0.
con_stopped:
        move.l  a0,-(sp)
        move.l  IO_UNIT(a1),a0
        moveq   #0,d0
        cmp.l   #-1,a0
        beq.s   .st_ret
        cmp.l   a2,a0
        bne.s   .st_cu
        lea     CONB_STOP-CU_STOP(a2),a0
.st_cu:
        move.b  CU_STOP(a0),d0
.st_ret:
        movem.l (sp)+,a0
        tst.b   d0
        rts

; con_target(a2 = base) -> d0 = ConUnit whose window is intuition's active window, 0 otherwise (Z
; accordingly). IntuitionBase is looked up in the library list on first need. Called under Disable.
; Preserves everything except d0.
con_target:
        movem.l d1/a0-a1/a6,-(sp)
        move.l  CONB_IBASE(a2),d0
        bne.s   .tg_have
        move.l  ($4).w,a6
        lea     EB_LIBLIST(a6),a0
        lea     console_intname(pc),a1
        jsr     LVO_FINDNAME(a6)
        move.l  d0,CONB_IBASE(a2)
        beq.s   .tg_ret
.tg_have:
        move.l  d0,a0
        move.l  52(a0),d1            ; ib_ActiveWindow (public offset)
        beq.s   .tg_no
        move.l  CONB_UNITS(a2),d0
.tg_lp:
        beq.s   .tg_ret
        move.l  d0,a0
        cmp.l   CU_WINDOW(a0),d1
        beq.s   .tg_ret
        move.l  CU_NEXT(a0),d0
        bra.s   .tg_lp
.tg_no:
        moveq   #0,d0
.tg_ret:
        movem.l (sp)+,d1/a0-a1/a6
        tst.l   d0
        rts
console_intname:
        dc.b    "intuition.library",0
        even

; initFunc (D0=base, A0=segList, A6=ExecBase) -> D0 = base. Sets the name, allocates the bitplane, inits the state,
; and REGISTERS the input handler on input.device (IND_ADDHANDLER) -> the keyboard (via input.device) will feed
; the read buffer. input.device (pri 40) is initialised BEFORE console (pri 20) -> present at this point.
console_initfunc:
        movem.l d2/a2/a3,-(sp)
        move.l  d0,a2                ; a2 = device base
        lea     console_name(pc),a0
        move.l  a0,LN_NAME(a2)
        move.w  #CON_BYTEW,CONB_BWIDTH(a2)
        move.w  #CON_PXH,CONB_PXROWS(a2)
        clr.w   CONB_CURX(a2)
        clr.w   CONB_CURY(a2)
        clr.l   CONB_RING+CRG_HEAD(a2) ; head and tail
        move.l  KM_DEFKM,d0          ; default keymap = the KeyMap of keymap.resource's first node
        beq.s   .ci_nokm
        move.l  d0,a0
        lea     CONB_DEFKM(a2),a1
        move.l  a1,KM_DEFKM          ; from now on the default keymap is this copy (CD_SETDEFAULTKEYMAP)
        moveq   #KM_SIZEOF/4-1,d0
.ci_km:
        move.l  (a0)+,(a1)+
        dbra    d0,.ci_km
.ci_nokm:
        lea     EB_LIBLIST(a6),a0    ; GfxBase (graphics.library, pri 65, initialised before console, pri 20)
        lea     console_gfxname(pc),a1
        jsr     LVO_FINDNAME(a6)
        move.l  d0,CONB_GFXBASE(a2)
        ; prepares the handler's struct Interrupt (in the base) + registers it on input.device
        move.b  #0,CONB_INT+LN_PRI(a2)
        move.l  #console_input_handler,CONB_INT+IS_CODE(a2)
        move.l  a2,CONB_INT+IS_DATA(a2)     ; is_Data = console base (received in a1 by the handler)
        lea     EB_DEVICELIST(a6),a0
        lea     console_inputdev(pc),a1     ; FindName("input.device")
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        beq.s   .ci_done
        move.l  d0,a3                        ; a3 = input.device base
        move.l  a3,-(sp)                     ; (AllocMem clobbers a0/a1/d0/d1; a2/a3 preserved)
        move.l  #64,d0                        ; temporary ioreq
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  (sp)+,a3
        tst.l   d0
        beq.s   .ci_done
        move.l  d0,a1                        ; a1 = ioreq
        move.l  a3,IO_DEVICE(a1)
        move.w  #IND_ADDHANDLER,IO_COMMAND(a1)
        lea     CONB_INT(a2),a0
        move.l  a0,IO_DATA2(a1)
        move.l  a1,-(sp)                     ; save ioreq (for the free)
        move.l  a3,a6                        ; a6 = input.device base for BeginIO
        move.b  #IOF_QUICK,IO_FLAGS(a1)
        jsr     -30(a6)                      ; input BeginIO IND_ADDHANDLER (Enqueue CONB_INT into the chain)
        move.l  ($4).w,a6                    ; restore a6 = SysBase
        move.l  (sp)+,a1                     ; ioreq
        move.l  #64,d0
        jsr     LVO_FREEMEM(a6)
.ci_done:
        move.l  a2,d0                ; return the base
        movem.l (sp)+,d2/a2/a3
        rts

console_inputdev:
        dc.b    "input.device",0
console_gfxname:
        dc.b    "graphics.library",0
        EVEN

; === window units (ConUnit): rendering into the window's RastPort via graphics.library ===
; Behaviour of docs/analysis/console-keymap-v34.md §3: cells of the window font (TxWidth + TxSpacing x TxHeight), the
; byte automaton of §3.2 (ESC, ESC intermediates, CSI with up to 24 parameters, defaults, < = > ? markers,
; intermediates, sequences abandoned and the byte read again), the controls of §3.3, tab stops (§3.4), the CSI
; sequences of §3.5, ESC c (§3.6), SGR (§3.7), modes LNM/ASM/AWM, reports into the read stream (§4: CSI 6n, window
; bounds, raw events). Automatic wrap is lazy: the cursor waits beyond XMax until the next character. Cursor: cell
; complemented (COMPLEMENT RectFill), removed before each write and redrawn afterwards.
CU_WINDOW       EQU 34               ; struct ConUnit (devices/conunit.h)
CU_XCP          EQU 38
CU_YCP          EQU 40
CU_XMAX         EQU 42
CU_YMAX         EQU 44
CU_XRSIZE       EQU 46
CU_YRSIZE       EQU 48
CU_XRORIGIN     EQU 50
CU_YRORIGIN     EQU 52
CU_XREXTANT     EQU 54
CU_YREXTANT     EQU 56
CU_XCCP         EQU 62
CU_YCCP         EQU 64
CU_KEYMAP       EQU 66               ; cu_KeyMapStruct: the unit's struct KeyMap
CU_TABS         EQU 98               ; cu_TabStops[80]: increasing, $FFFF ends the list when it is not full
CU_FGPEN        EQU 259
CU_BGPEN        EQU 260
CU_MODES        EQU 290              ; cu_Modes[3]: bit n in byte n/8; byte 2: LNM $10, ASM $20, AWM $40
CU_RAWEV        EQU 293              ; cu_RawEvents[3]: bit n = IECLASS n reported raw
CU_ESC          EQU 296              ; private: 0 normal, 1 after ESC, 2 inside a CSI, 3 ESC intermediates
CU_NPAR         EQU 297              ; private: index of the current CSI parameter (0..23, 24 = the rest is lost)
CU_NINT         EQU 298              ; private: number of CSI intermediates
CU_INTER        EQU 299              ; private: first CSI intermediate byte ($20..$2F)
CU_STYLE        EQU 300              ; private: SGR soft style (FSF_BOLD 2, FSF_ITALIC 4, FSF_UNDERLINED 1)
CU_SO           EQU 301              ; private: shifted set (SO): $20-$7F shown as byte | $80
CU_CONCEAL      EQU 302              ; private: SGR 8, RastPort Mask 0
CU_AGAIN        EQU 303              ; private: the byte just given to cu_ctl must be read again
CU_CUROFF       EQU 304              ; private: cursor hidden (CSI 0 SPACE p)
CU_CURVIS       EQU 305              ; private: cursor currently drawn
CU_INV          EQU 306              ; private: inverse video (SGR 7)
CU_STOP         EQU 307              ; private: reads held by CMD_STOP
CU_NEXT         EQU 308              ; private: next unit (CONB_UNITS list)
CU_BASE         EQU 312              ; private: console base (cu_write reuses a2)
CU_PARS         EQU 316              ; private: 24 CSI parameters (words, CU_PDEF = absent)
CU_FIXCOL       EQU 364              ; private: line length fixed by CSI u (0 = from the window)
CU_FIXROW       EQU 366              ; private: page length fixed by CSI t (0 = from the window)
CU_FIXXO        EQU 368              ; private: XROrigin fixed by CSI x (-1 = from the window)
CU_FIXYO        EQU 370              ; private: YROrigin fixed by CSI y (-1 = from the window)
CU_WINW         EQU 372              ; private: window Width and Height (long) when the geometry was last computed
CU_RING         EQU 376              ; private: read ring of the unit (CRG_*)
CU_SIZE         EQU CU_RING+CRG_SIZE
CU_RPMASK       EQU 258              ; cu_Mask, cu_FgPen, cu_BgPen, cu_AOLPen, cu_DrawMode, cu_AreaPtSz: the copy of the
CU_AREAPTRN     EQU 264              ; window RastPort's state that the unit draws with (console-keymap-v34 §2.2)
CU_MINTERMS     EQU 268
CU_FONT         EQU 276
CU_ALGO         EQU 280              ; cu_AlgoStyle, cu_TxFlags, cu_TxHeight, cu_TxWidth, cu_TxBaseline, cu_TxSpacing
CU_NTABS        EQU 80
CU_NPARS        EQU 24
CU_PDEF         EQU -5               ; absent parameter
CU_DEFFG        EQU 2                ; default text pen: black on the purple background (project theme; 1.3: 1)
CUM_LNM         EQU 4                ; bits of byte 2 of cu_Modes
CUM_ASM         EQU 5
CUM_AWM         EQU 6
LVO_DISPLAYBEEP EQU -96             ; intuition

; cu_init(a0 = cleared ConUnit, a1 = Window): modes LNM/ASM/AWM, default tab stops and pens, automatic geometry.
; Preserves everything except d0/d1.
cu_init:
        move.l  a5,-(sp)
        move.l  a0,a5
        move.l  a1,CU_WINDOW(a5)
        move.l  WD_RPORT(a1),d0
        beq.s   .ci_norp
        movem.l d0/a3,-(sp)
        move.l  d0,a3
        lea     rps_unit(pc),a0
        move.l  a5,a1
        moveq   #0,d0
        bsr     rps_copy             ; the unit starts with the window's RastPort state
        movem.l (sp)+,d0/a3
.ci_norp:
        move.b  #$70,CU_MODES+2(a5)
        move.w  #-1,CU_FIXXO(a5)
        move.w  #-1,CU_FIXYO(a5)
        move.b  #CU_DEFFG,CU_FGPEN(a5)
        bsr.s   cu_deftabs
        bsr.s   cu_geom
        move.l  a5,a0
        move.l  (sp)+,a5
        rts

; cu_deftabs(a5): tab stops 0, 8, ..., 632. Clobbers d0/d1/a0.
cu_deftabs:
        lea     CU_TABS(a5),a0
        moveq   #0,d0
        moveq   #CU_NTABS-1,d1
.dt_lp:
        move.w  d0,(a0)+
        addq.w  #8,d0
        dbra    d1,.dt_lp
        rts

; cu_geom(a5): text area from the window and its RastPort font (§3.9): XRSize = TxWidth + TxSpacing, YRSize = TxHeight,
; origins at the borders (0 in a GIMMEZEROZERO window) unless CSI x / y, XMax / YMax from the useful size unless CSI u / t.
; Preserves everything except d0/d1.
cu_geom:
        movem.l d2/a0-a1,-(sp)
        move.l  CU_WINDOW(a5),a1
        moveq   #GFX_FONTW,d0        ; no RastPort yet: the 8 x 8 ROM font
        moveq   #GFX_FONTH,d1
        move.l  WD_RPORT(a1),d2
        beq.s   .gm_sz
        move.l  d2,a0
        move.w  rp_TxWidth(a0),d0
        add.w   rp_TxSpacing(a0),d0
        move.w  rp_TxHeight(a0),d1
.gm_sz:
        tst.w   d0
        bgt.s   .gm_w
        moveq   #1,d0
.gm_w:
        move.w  d0,CU_XRSIZE(a5)
        tst.w   d1
        bgt.s   .gm_h
        moveq   #1,d1
.gm_h:
        move.w  d1,CU_YRSIZE(a5)
        moveq   #0,d0                ; automatic origins
        moveq   #0,d1
        btst    #2,WD_FLAGS+2(a1)    ; GIMMEZEROZERO ($0400)
        bne.s   .gm_gzz
        move.b  WD_BORDERLEFT(a1),d0
        move.b  WD_BORDERTOP(a1),d1
.gm_gzz:
        tst.w   CU_FIXXO(a5)
        bmi.s   .gm_xo
        move.w  CU_FIXXO(a5),d0
.gm_xo:
        tst.w   CU_FIXYO(a5)
        bmi.s   .gm_yo
        move.w  CU_FIXYO(a5),d1
.gm_yo:
        move.w  d0,CU_XRORIGIN(a5)
        move.w  d1,CU_YRORIGIN(a5)
        move.w  WD_WIDTH(a1),d0      ; useful width
        moveq   #0,d2
        move.b  WD_BORDERRIGHT(a1),d2
        sub.w   d2,d0
        sub.w   CU_XRORIGIN(a5),d0
        btst    #2,WD_FLAGS+2(a1)
        beq.s   .gm_uw
        move.b  WD_BORDERLEFT(a1),d2
        sub.w   d2,d0
.gm_uw:
        tst.w   CU_FIXCOL(a5)
        beq.s   .gm_ac
        move.w  CU_FIXCOL(a5),d0
        bra.s   .gm_xm
.gm_ac:
        ext.l   d0
        bpl.s   .gm_dx
        moveq   #0,d0
.gm_dx:
        divu    CU_XRSIZE(a5),d0
.gm_xm:
        subq.w  #1,d0
        bpl.s   .gm_x0
        moveq   #0,d0
.gm_x0:
        move.w  d0,CU_XMAX(a5)
        addq.w  #1,d0
        mulu    CU_XRSIZE(a5),d0
        add.w   CU_XRORIGIN(a5),d0
        subq.w  #1,d0
        move.w  d0,CU_XREXTANT(a5)
        move.w  WD_HEIGHT(a1),d0     ; useful height
        moveq   #0,d2
        move.b  WD_BORDERBOTTOM(a1),d2
        sub.w   d2,d0
        btst    #2,WD_FLAGS+2(a1)
        beq.s   .gm_nh
        move.b  WD_BORDERTOP(a1),d2
        sub.w   d2,d0
        sub.w   CU_XRORIGIN(a5),d0   ; V34 subtracts the horizontal origin here (§3.9)
        bra.s   .gm_uh
.gm_nh:
        sub.w   CU_YRORIGIN(a5),d0
.gm_uh:
        tst.w   CU_FIXROW(a5)
        beq.s   .gm_ar
        move.w  CU_FIXROW(a5),d0
        bra.s   .gm_ym
.gm_ar:
        ext.l   d0
        bpl.s   .gm_dy
        moveq   #0,d0
.gm_dy:
        divu    CU_YRSIZE(a5),d0
.gm_ym:
        subq.w  #1,d0
        bpl.s   .gm_y0
        moveq   #0,d0
.gm_y0:
        move.w  d0,CU_YMAX(a5)
        addq.w  #1,d0
        mulu    CU_YRSIZE(a5),d0
        add.w   CU_YRORIGIN(a5),d0
        subq.w  #1,d0
        move.w  d0,CU_YREXTANT(a5)
        move.l  WD_WIDTH(a1),CU_WINW(a5)
        movem.l (sp)+,d2/a0-a1
        rts

; cu_resize(a5, a3, a6): the window size changed since the last geometry (§3.9). 1.3 learns it from
; IECLASS_SIZEWINDOW for the active unit and applies it at the start of its next write; here every unit checks its
; own window at the start of each write. New geometry; in a SMART_REFRESH window that grew, the band right of the
; old whole columns and the band below the old whole lines are cleared (half characters brought back); the cursor
; is erased only if its cell is still in the text area; then (except SUPER_BITMAP) XCP > XMax -> column 0 of the
; next line, YCP > YMax -> last line, column 0 and a one-line scroll. Clobbers d0-d3/a0/a1.
cu_resize:
        movem.l d4-d5,-(sp)
        move.w  CU_XMAX(a5),d4
        move.w  CU_YMAX(a5),d5
        bsr     cu_geom
        move.l  CU_WINDOW(a5),a0
        moveq   #$C0-256,d0
        and.b   WD_FLAGS+3(a0),d0    ; SIMPLE_REFRESH $40 | SUPER_BITMAP $80: 0 = SMART_REFRESH
        bne.s   .rs_cur
        cmp.w   CU_XMAX(a5),d4
        bge.s   .rs_y
        move.w  d4,d0                ; columns d4+1.. up to the right edge of the text area
        addq.w  #1,d0
        mulu    CU_XRSIZE(a5),d0
        add.w   CU_XRORIGIN(a5),d0
        move.w  CU_YRORIGIN(a5),d1
        bsr     cu_edges
        bsr     cu_fill
.rs_y:
        cmp.w   CU_YMAX(a5),d5
        bge.s   .rs_cur
        move.w  d5,d1                ; lines d5+1.. down to the bottom edge
        addq.w  #1,d1
        mulu    CU_YRSIZE(a5),d1
        add.w   CU_YRORIGIN(a5),d1
        move.w  CU_XRORIGIN(a5),d0
        bsr     cu_edges
        bsr     cu_fill
.rs_cur:
        tst.b   CU_CURVIS(a5)
        beq.s   .rs_pos
        move.w  CU_XCCP(a5),d0
        cmp.w   CU_XMAX(a5),d0
        bgt.s   .rs_gone
        move.w  CU_YCCP(a5),d0
        cmp.w   CU_YMAX(a5),d0
        bgt.s   .rs_gone
        bsr     cu_curoff
        bra.s   .rs_pos
.rs_gone:
        clr.b   CU_CURVIS(a5)
.rs_pos:
        move.l  CU_WINDOW(a5),a0
        btst    #7,WD_FLAGS+3(a0)    ; SUPER_BITMAP: the cursor stays where it is
        bne.s   .rs_ret
        move.w  CU_XCP(a5),d0
        cmp.w   CU_XMAX(a5),d0
        ble.s   .rs_ycp
        clr.w   CU_XCP(a5)
        addq.w  #1,CU_YCP(a5)
.rs_ycp:
        move.w  CU_YCP(a5),d0
        cmp.w   CU_YMAX(a5),d0
        ble.s   .rs_ret
        move.w  CU_YMAX(a5),CU_YCP(a5)
        clr.w   CU_XCP(a5)
        moveq   #1,d1
        bsr     cu_vscroll
.rs_ret:
        movem.l (sp)+,d4-d5
        rts

; cu_edges(a5; d0/d1 = top-left corner) -> d2/d3 = right and bottom edges of the window's useful area (inside the
; borders, in RastPort coordinates). Clobbers a0/a1.
cu_edges:
        move.l  CU_WINDOW(a5),a0
        moveq   #0,d2
        move.b  WD_BORDERRIGHT(a0),d2
        neg.w   d2
        add.w   WD_WIDTH(a0),d2
        moveq   #0,d3
        move.b  WD_BORDERBOTTOM(a0),d3
        neg.w   d3
        add.w   WD_HEIGHT(a0),d3
        btst    #2,WD_FLAGS+2(a0)    ; GIMMEZEROZERO: the RastPort starts inside the left and top borders
        beq.s   .ed_1
        move.l  d4,-(sp)
        moveq   #0,d4
        move.b  WD_BORDERLEFT(a0),d4
        sub.w   d4,d2
        move.b  WD_BORDERTOP(a0),d4
        sub.w   d4,d3
        move.l  (sp)+,d4
.ed_1:
        subq.w  #1,d2
        subq.w  #1,d3
        rts

; cu_write(a0 = ConUnit, a4 = data, d4 = length, a2 = console base): interprets the stream in the window.
; Preserves d2-d7/a2-a6 (a4/d4 consumed: saved).
cu_write:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  a0,a5                ; a5 = ConUnit
        move.l  CONB_GFXBASE(a2),a6  ; a6 = GfxBase
        move.l  CU_WINDOW(a5),a0
        move.l  WD_RPORT(a0),a3      ; a3 = RastPort
        bsr     cu_setpens
        move.l  CU_WINDOW(a5),a0
        move.l  WD_WIDTH(a0),d0
        cmp.l   CU_WINW(a5),d0
        beq.s   .cw_same
        bsr     cu_resize
.cw_same:
        bsr     cu_curoff
.cw_lp:
        tst.l   d4
        beq     .cw_end
        tst.b   CU_ESC(a5)
        bne.s   .cw_ctl
        move.b  (a4),d0
        bsr     cu_isprint
        beq.s   .cw_print
.cw_ctl:
        move.b  (a4),d0
        bsr     cu_ctl
        tst.b   CU_AGAIN(a5)
        beq.s   .cw_next
        clr.b   CU_AGAIN(a5)         ; sequence abandoned: the byte is read again in the normal state
        bra.s   .cw_lp
.cw_next:
        addq.l  #1,a4
        subq.l  #1,d4
        bra.s   .cw_lp
.cw_print:
        move.w  CU_XCP(a5),d0        ; column beyond the last one: line wrap before writing (AWM), or the
        cmp.w   CU_XMAX(a5),d0       ; last column is written again (no AWM)
        ble.s   .cw_fit
        btst    #CUM_AWM,CU_MODES+2(a5)
        beq.s   .cw_noawm
        clr.w   CU_XCP(a5)
        bsr     cu_lf
        bra.s   .cw_fit
.cw_noawm:
        move.w  CU_XMAX(a5),CU_XCP(a5)
.cw_fit:
        move.w  CU_XMAX(a5),d3
        sub.w   CU_XCP(a5),d3
        addq.w  #1,d3                ; d3 = cells left on the line
        tst.b   CU_SO(a5)
        beq.s   .cw_run
        moveq   #1,d3                ; shifted set: one character at a time
.cw_run:
        move.l  a4,a2                ; a2 = start of the run
        moveq   #0,d2                ; d2 = length of the run
.cw_cnt:
        cmp.w   d3,d2
        bge.s   .cw_out
        tst.l   d4
        beq.s   .cw_out
        move.b  (a4),d0
        bsr     cu_isprint
        bne.s   .cw_out
        addq.l  #1,a4
        subq.l  #1,d4
        addq.w  #1,d2
        bra.s   .cw_cnt
.cw_out:
        bsr     cu_cellxy
        add.w   rp_TxBaseline(a3),d1
        move.l  a3,a1
        jsr     LVO_MOVE(a6)
        tst.b   CU_SO(a5)
        bne.s   .cw_so
        move.l  a2,a0
        move.w  d2,d0
        move.l  a3,a1
        jsr     LVO_TEXT(a6)
        bra.s   .cw_adv
.cw_so:
        moveq   #0,d0                ; shifted set: $20-$7F shown as byte | $80
        move.b  (a2),d0
        or.b    #$80,d0
        move.w  d0,-(sp)
        lea     1(sp),a0
        moveq   #1,d0
        move.l  a3,a1
        jsr     LVO_TEXT(a6)
        addq.l  #2,sp
.cw_adv:
        add.w   d2,CU_XCP(a5)
        bra     .cw_lp
.cw_end:
        btst    #CUM_AWM,CU_MODES+2(a5)
        bne.s   .cw_cur
        move.w  CU_XCP(a5),d0
        cmp.w   CU_XMAX(a5),d0
        ble.s   .cw_cur
        move.w  CU_XMAX(a5),CU_XCP(a5)
.cw_cur:
        bsr     cu_curon
        movem.l (sp)+,d2-d7/a2-a6
        rts

; cu_rpwrite(a0 = ConUnit, a2 = base, a4 = data, d4 = length): CMD_WRITE into a window as 1.3 does it (console-
; keymap-v34 §2.2): the window RastPort's state is saved, the unit's copy installed, the write done, the RastPort's
; state copied back into the unit, the RastPort restored, so the program sharing the window finds its pens, mode,
; font and pen position intact. Clobbers d0/d1/a0/a1.
RPS_SIZE        EQU 36
cu_rpwrite:
        movem.l a3/a5,-(sp)
        move.l  a0,a5
        move.l  CU_WINDOW(a5),a1
        move.l  WD_RPORT(a1),a3
        lea     -RPS_SIZE(sp),sp
        lea     rps_save(pc),a0
        move.l  sp,a1
        moveq   #0,d0
        bsr.s   rps_copy             ; RastPort -> saved block
        lea     rps_unit(pc),a0
        move.l  a5,a1
        moveq   #1,d0
        bsr.s   rps_copy             ; unit -> RastPort
        move.l  a5,a0
        bsr     cu_write
        lea     rps_unit(pc),a0
        move.l  a5,a1
        moveq   #0,d0
        bsr.s   rps_copy             ; RastPort -> unit
        lea     rps_save(pc),a0
        move.l  sp,a1
        moveq   #1,d0
        bsr.s   rps_copy             ; saved block -> RastPort
        lea     RPS_SIZE(sp),sp
        movem.l (sp)+,a3/a5
        rts
; rps_copy(a0 = table, a1 = block, a3 = RastPort, d0 = 0: RastPort to block, otherwise block to RastPort): copies the
; fields of the table (RastPort offset, block offset, length - 1; -1 ends it). Preserves everything.
rps_copy:
        movem.l d1-d3/a0/a2/a4,-(sp)
.rc_lp:
        move.w  (a0)+,d1
        bmi.s   .rc_ret
        move.w  (a0)+,d2
        move.w  (a0)+,d3
        lea     0(a3,d1.w),a2
        lea     0(a1,d2.w),a4
        tst.l   d0
        beq.s   .rc_cp
        exg     a2,a4
.rc_cp:
        move.b  (a2)+,(a4)+
        dbra    d3,.rc_cp
        bra.s   .rc_lp
.rc_ret:
        movem.l (sp)+,d1-d3/a0/a2/a4
        rts
; rp_Mask..rp_AreaPtSz, rp_AreaPtrn, rp_minterms, rp_Font, rp_AlgoStyle..rp_TxSpacing, then rp_cp_x/y (saved only)
rps_save:
        dc.w    24,0,6-1, 8,6,4-1, 40,10,8-1, 52,18,4-1, 56,22,10-1, 36,32,4-1, -1
; the same into the ConUnit, without cu_FgPen / cu_BgPen: they hold the pens the escape sequences chose
rps_unit:
        dc.w    24,CU_RPMASK,1-1, 27,CU_RPMASK+3,3-1, 8,CU_AREAPTRN,4-1, 40,CU_MINTERMS,8-1, 52,CU_FONT,4-1
        dc.w    56,CU_ALGO,10-1, -1

; cu_isprint(d0.b) -> Z = 1 if printable character ($20..$7F, $A0..$FF). Only touches the condition codes.
cu_isprint:
        cmp.b   #$20,d0
        blo.s   .ip_no
        cmp.b   #$80,d0
        blo.s   .ip_yes
        cmp.b   #$A0,d0
        blo.s   .ip_no
.ip_yes:
        move.w  #4,ccr               ; Z = 1
        rts
.ip_no:
        move.w  #0,ccr               ; Z = 0
        rts

; cu_cellxy(a5) -> d0.w/d1.w = top-left corner of the cursor cell (window coordinates).
cu_cellxy:
        move.w  CU_XCP(a5),d0
        mulu    CU_XRSIZE(a5),d0
        add.w   CU_XRORIGIN(a5),d0
        move.w  CU_YCP(a5),d1
        mulu    CU_YRSIZE(a5),d1
        add.w   CU_YRORIGIN(a5),d1
        rts

; cu_setpens(a5, a3 = RastPort, a6 = GfxBase): JAM2 (with INVERSVID for SGR 7), A/B pens, soft style and write mask
; of the unit. Clobbers d0/d1/a0/a1.
cu_setpens:
        move.l  a3,a1
        moveq   #JAM2,d0
        tst.b   CU_INV(a5)
        beq.s   .sp_dm
        moveq   #JAM2|INVERSVID,d0
.sp_dm:
        jsr     LVO_SETDRMD(a6)
        move.l  a3,a1
        moveq   #0,d0
        move.b  CU_STYLE(a5),d0
        moveq   #7,d1
        jsr     LVO_SETSOFTSTYLE(a6)
        st      rp_Mask(a3)
        tst.b   CU_CONCEAL(a5)
        beq.s   .sp_pen
        clr.b   rp_Mask(a3)
.sp_pen:
        moveq   #0,d1
        move.b  CU_BGPEN(a5),d1
        move.l  d2,-(sp)             ; text and background merged by the BitMap's planes (screen reduced to 1 plane by a
        move.l  rp_BitMap(a3),a0     ; program: theme text pen = background) -> text uses the colour next to the background
        moveq   #0,d2
        move.b  bm_Depth(a0),d2
        moveq   #1,d0
        lsl.l   d2,d0
        subq.l  #1,d0
        move.l  d0,d2                ; d2 = mask of the displayable pens
        moveq   #0,d0
        move.b  CU_FGPEN(a5),d0
        eor.l   d1,d0
        and.l   d2,d0
        bne.s   .sp_vis
        move.l  d1,d0                ; merged: background ^ 1
        eor.b   #1,d0
        bra.s   .sp_ok
.sp_vis:
        eor.l   d1,d0                ; d0 = original pen
.sp_ok:
        move.l  (sp)+,d2
        move.l  d1,-(sp)
        move.l  a3,a1
        jsr     LVO_SETAPEN(a6)
        move.l  (sp)+,d0
        move.l  a3,a1
        jmp     LVO_SETBPEN(a6)

; cu_curoff / cu_curon(a5, a3, a6): removes / draws the cursor (complemented cell); cu_XCCP/YCCP follow it.
; Clobbers d0-d3/a0/a1.
cu_curoff:
        tst.b   CU_CURVIS(a5)
        beq.s   cu_ret
        clr.b   CU_CURVIS(a5)
        move.w  CU_XCCP(a5),d0
        mulu    CU_XRSIZE(a5),d0
        add.w   CU_XRORIGIN(a5),d0
        move.w  CU_YCCP(a5),d1
        mulu    CU_YRSIZE(a5),d1
        add.w   CU_YRORIGIN(a5),d1
        bra.s   cu_cplcell
cu_curon:
        move.l  CU_XCP(a5),CU_XCCP(a5)
        tst.b   CU_CUROFF(a5)
        bne.s   cu_ret
        move.w  CU_XCP(a5),d0
        cmp.w   CU_XMAX(a5),d0
        bgt.s   cu_ret               ; waiting for a line wrap: no cell
        st      CU_CURVIS(a5)
        bsr     cu_cellxy
cu_cplcell:
        movem.w d0-d1,-(sp)
        move.l  a3,a1
        moveq   #COMPLEMENT,d0
        jsr     LVO_SETDRMD(a6)
        movem.w (sp)+,d0-d1
        move.w  d0,d2
        add.w   CU_XRSIZE(a5),d2
        subq.w  #1,d2
        move.w  d1,d3
        add.w   CU_YRSIZE(a5),d3
        subq.w  #1,d3
        move.l  a3,a1
        jsr     LVO_RECTFILL(a6)
        bra     cu_setpens
cu_ret:
        rts

; cu_fill(d0..d3 = rectangle, a3, a6): clears it in the clearing colour of §3.7: BPen in plain JAM2, colour 0 in
; inverse video. Clobbers d0-d3/a0/a1.
cu_fill:
        movem.w d0-d3,-(sp)
        move.l  a3,a1
        moveq   #0,d0
        tst.b   CU_INV(a5)
        bne.s   .fl_n
        move.b  CU_BGPEN(a5),d0
.fl_n:
        jsr     LVO_SETAPEN(a6)
        move.l  a3,a1
        moveq   #JAM2,d0
        jsr     LVO_SETDRMD(a6)
        movem.w (sp)+,d0-d3
        move.l  a3,a1
        jsr     LVO_RECTFILL(a6)
        bra     cu_setpens

; cu_scroll(d1.w = dy in pixels, d3.w = first line in pixels, a3, a6): shifts [d3 .. YRExtant] of the text
; area (upwards if dy > 0), freed band in pen B. Clobbers d0-d3/a0/a1.
cu_scroll:
        movem.l d4/d5,-(sp)
        moveq   #0,d0
        move.w  CU_XRORIGIN(a5),d2
        move.w  CU_XREXTANT(a5),d4
        move.w  CU_YREXTANT(a5),d5
        move.l  a3,a1
        jsr     LVO_SCROLLRASTER(a6)
        movem.l (sp)+,d4/d5
        rts

; cu_vscroll(d1.w = lines, > 0 up / < 0 down): the whole text area. Clobbers d0-d3/a0/a1.
cu_vscroll:
        muls    CU_YRSIZE(a5),d1
        move.w  CU_YRORIGIN(a5),d3
        bra.s   cu_scroll

; cu_lf(a5, a3, a6): IND, next line; at the bottom, one-line scroll with ASM, otherwise the last line stays.
; Clobbers d0-d3/a0/a1.
cu_lf:
        move.w  CU_YCP(a5),d0
        cmp.w   CU_YMAX(a5),d0
        bge.s   .lf_bot
        addq.w  #1,CU_YCP(a5)
        rts
.lf_bot:
        move.w  CU_YMAX(a5),CU_YCP(a5)
        btst    #CUM_ASM,CU_MODES+2(a5)
        beq     cu_ret
        moveq   #1,d1
        bra.s   cu_vscroll

; cu_ri(a5, a3, a6): RI, previous line; at the top, one-line reverse scroll with ASM. Clobbers d0-d3/a0/a1.
cu_ri:
        tst.w   CU_YCP(a5)
        beq.s   .ri_top
        subq.w  #1,CU_YCP(a5)
        rts
.ri_top:
        btst    #CUM_ASM,CU_MODES+2(a5)
        beq     cu_ret
        moveq   #-1,d1
        bra.s   cu_vscroll

; cu_hshift(d1.w = dx in pixels, a5, a3, a6): shifts the line from the cursor cell to the right edge of the area by
; dx (> 0: to the left) with ScrollRaster, which clears the uncovered cells. Clobbers d0-d3/a0/a1.
cu_hshift:
        move.w  CU_XCP(a5),d0
        cmp.w   CU_XMAX(a5),d0
        bgt     cu_ret
        movem.l d4/d5,-(sp)
        move.w  d1,d4
        bsr     cu_cellxy            ; d0 = x, d1 = y of the cursor cell
        move.w  d0,d2
        move.w  d1,d3
        move.w  d4,d0
        ext.l   d0
        moveq   #0,d1
        move.w  CU_XREXTANT(a5),d4
        move.w  d3,d5
        add.w   CU_YRSIZE(a5),d5
        subq.w  #1,d5
        move.l  a3,a1
        jsr     LVO_SCROLLRASTER(a6)
        movem.l (sp)+,d4/d5
        rts

; cu_eol(a5, a3, a6): erases from the cursor cell to the end of the line. Clobbers d0-d3/a0/a1.
cu_eol:
        move.w  CU_XCP(a5),d0
        cmp.w   CU_XMAX(a5),d0
        bgt     cu_ret
        bsr     cu_cellxy
        move.w  CU_XREXTANT(a5),d2
        move.w  d1,d3
        add.w   CU_YRSIZE(a5),d3
        subq.w  #1,d3
        bra     cu_fill

; cu_ht(a5, a3, a6): next tab stop strictly beyond XCP; past XMax (or none): column 0 of the next line with AWM,
; XMax otherwise (§3.4). Clobbers d0-d3/a0/a1.
cu_ht:
        lea     CU_TABS(a5),a0
        moveq   #CU_NTABS-1,d1
.ht_lp:
        move.w  (a0)+,d0
        cmp.w   #$FFFF,d0
        beq.s   .ht_none
        cmp.w   CU_XCP(a5),d0
        bgt.s   .ht_got
        dbra    d1,.ht_lp
        bra.s   .ht_none
.ht_got:
        cmp.w   CU_XMAX(a5),d0
        bgt.s   .ht_none
        move.w  d0,CU_XCP(a5)
        rts
.ht_none:
        btst    #CUM_AWM,CU_MODES+2(a5)
        beq.s   .ht_end
        clr.w   CU_XCP(a5)
        bra     cu_lf
.ht_end:
        move.w  CU_XMAX(a5),CU_XCP(a5)
        rts

; cu_cbt(a5, a3, a6): previous tab stop strictly below XCP; in column 0 with AWM, the line above (reverse scroll at
; the top with ASM) is searched from its end; without AWM nothing. Clobbers d0-d3/a0/a1.
cu_cbt:
        move.w  CU_XCP(a5),d2
        bne.s   .cb_find
        btst    #CUM_AWM,CU_MODES+2(a5)
        beq     cu_ret
        bsr     cu_ri
        move.w  CU_XMAX(a5),d2
        addq.w  #1,d2
.cb_find:
        moveq   #0,d3                ; tab stop 0 always exists
        lea     CU_TABS(a5),a0
        moveq   #CU_NTABS-1,d1
.cb_lp:
        move.w  (a0)+,d0
        cmp.w   #$FFFF,d0
        beq.s   .cb_set
        cmp.w   d2,d0
        bge.s   .cb_set
        move.w  d0,d3
        dbra    d1,.cb_lp
.cb_set:
        move.w  d3,CU_XCP(a5)
        rts

; cu_hts(a5): tab stop at XCP, kept sorted, no duplicate; a full list loses its last one. Clobbers d0-d2/a0.
cu_hts:
        move.w  CU_XCP(a5),d2
        lea     CU_TABS(a5),a0
        moveq   #CU_NTABS-1,d1
.hs_lp:
        move.w  (a0),d0
        cmp.w   d2,d0
        beq     cu_ret
        bhi.s   .hs_ins              ; also $FFFF: end of the list
        addq.l  #2,a0
        dbra    d1,.hs_lp
        rts                          ; beyond the 80 entries: nothing
.hs_ins:
        move.w  (a0),d0              ; insertion: each following entry moves up one place
        move.w  d2,(a0)+
        move.w  d0,d2
        dbra    d1,.hs_ins
        rts

; cu_tbc(a5): clears the tab stop at XCP, except in column 0. Clobbers d0/d1/a0/a1.
cu_tbc:
        move.w  CU_XCP(a5),d0
        beq     cu_ret
        lea     CU_TABS(a5),a0
        moveq   #CU_NTABS-1,d1
.tb_lp:
        cmp.w   (a0)+,d0
        dbeq    d1,.tb_lp
        bne     cu_ret
        lea     -2(a0),a1            ; found: the following ones move down one place
        subq.w  #1,d1
        bmi.s   .tb_end
.tb_mv:
        move.w  (a0)+,(a1)+
        dbra    d1,.tb_mv
.tb_end:
        move.w  #$FFFF,(a1)
        rts

; cu_tclr(a5): only tab stop 0 remains. Clobbers a0.
cu_tclr:
        lea     CU_TABS(a5),a0
        clr.w   (a0)+
        move.w  #$FFFF,(a0)
        rts

; cu_dec(d0.l unsigned, a0 = output) -> a0 advanced past the decimal digits. Clobbers d0/d1.
cu_dec:
        movem.l d2-d3,-(sp)
        moveq   #0,d3                ; digits pushed
.dc_div:
        moveq   #0,d1                ; d0 / 10 in two 16-bit steps
        swap    d0
        move.w  d0,d1
        divu    #10,d1
        move.w  d1,d2
        swap    d2
        swap    d0
        move.w  d0,d1
        divu    #10,d1
        move.w  d1,d2
        swap    d1                   ; d1.w = remainder
        move.w  d1,-(sp)
        addq.w  #1,d3
        move.l  d2,d0
        bne.s   .dc_div
        subq.w  #1,d3
.dc_out:
        move.w  (sp)+,d1
        add.b   #'0',d1
        move.b  d1,(a0)+
        dbra    d3,.dc_out
        movem.l (sp)+,d2-d3
        rts

; cu_reply(a0 = end of the report built at 4(sp)..., d2 = its start): pushes the bytes into the read stream (whole or
; nothing) and serves a waiting read. Clobbers d0-d3/a0/a1.
cu_reply:
        move.l  a2,-(sp)
        move.l  CU_BASE(a5),a2
        exg     a0,d2
        sub.l   a0,d2
        lea     CU_RING(a5),a1
        bsr     con_push
        beq.s   .ry_out
        bsr     con_servereads
.ry_out:
        move.l  (sp)+,a2
        rts

; cu_report(a5): window bounds report CSI 1;1;<lines>;<columns> SPACE r into the read stream (§4). Ed waits for it to
; size its display. Clobbers d0-d3/a0/a1.
cu_report:
        lea     -24(sp),sp
        move.l  sp,a0
        move.b  #$9B,(a0)+
        move.b  #'1',(a0)+
        move.b  #';',(a0)+
        move.b  #'1',(a0)+
        move.b  #';',(a0)+
        moveq   #0,d0
        move.w  CU_YMAX(a5),d0
        addq.w  #1,d0
        bsr     cu_dec
        move.b  #';',(a0)+
        moveq   #0,d0
        move.w  CU_XMAX(a5),d0
        addq.w  #1,d0
        bsr     cu_dec
        move.b  #' ',(a0)+
        move.b  #'r',(a0)+
        move.l  sp,d2
        bsr     cu_reply
        lea     24(sp),sp
        rts

; cu_dsr(a5): cursor position report CSI <line>;<column> R (base 1). Clobbers d0-d3/a0/a1.
cu_dsr:
        lea     -16(sp),sp
        move.l  sp,a0
        move.b  #$9B,(a0)+
        moveq   #0,d0
        move.w  CU_YCP(a5),d0
        addq.w  #1,d0
        bsr     cu_dec
        move.b  #';',(a0)+
        moveq   #0,d0
        move.w  CU_XCP(a5),d0
        cmp.w   CU_XMAX(a5),d0
        ble.s   .ds_x
        move.w  CU_XMAX(a5),d0
.ds_x:
        addq.w  #1,d0
        bsr     cu_dec
        move.b  #'R',(a0)+
        move.l  sp,d2
        bsr     cu_reply
        lea     16(sp),sp
        rts

; cu_beep(a5): BEL = DisplayBeep of the window's screen. Clobbers d0/d1/a0/a1.
cu_beep:
        movem.l a2/a6,-(sp)
        move.l  CU_BASE(a5),a2
        bsr     con_target           ; (finds IntuitionBase on first need)
        move.l  CONB_IBASE(a2),d0
        beq.s   .bp_ret
        move.l  d0,a6
        move.l  CU_WINDOW(a5),a0
        move.l  WD_WSCREEN(a0),a0
        jsr     LVO_DISPLAYBEEP(a6)
.bp_ret:
        movem.l (sp)+,a2/a6
        rts

; cu_ris(a5, a3, a6): ESC c (§3.6): default tab stops, normal set, cursor visible, LNM/ASM/AWM, automatic geometry,
; SGR 0, cursor at (0,0), area cleared. cu_RawEvents is kept. Clobbers d0-d3/a0/a1.
cu_ris:
        bsr     cu_deftabs
        clr.b   CU_SO(a5)
        clr.b   CU_CUROFF(a5)
        move.b  #$70,CU_MODES+2(a5)
        clr.w   CU_FIXCOL(a5)
        clr.w   CU_FIXROW(a5)
        move.w  #-1,CU_FIXXO(a5)
        move.w  #-1,CU_FIXYO(a5)
        bsr     cu_geom
        moveq   #0,d0
        bsr     cu_sgr1
        bsr     cu_setpens
        ; falls through: FF
; cu_ff(a5, a3, a6): FF, cursor at (0,0) and the whole text area cleared. Clobbers d0-d3/a0/a1.
cu_ff:
        clr.l   CU_XCP(a5)           ; XCP = YCP = 0
        move.w  CU_XRORIGIN(a5),d0
        move.w  CU_YRORIGIN(a5),d1
        move.w  CU_XREXTANT(a5),d2
        move.w  CU_YREXTANT(a5),d3
        bra     cu_fill

; cu_sgr1(d0.w = SGR parameter, a5): one SGR value (§3.7); default/negative = 0, above 49 ignored. Clobbers d0.
cu_sgr1:
        tst.w   d0
        bgt.s   .sg_n0
        move.b  #CU_DEFFG,CU_FGPEN(a5)
        clr.b   CU_BGPEN(a5)
        clr.b   CU_INV(a5)
        clr.b   CU_STYLE(a5)
        clr.b   CU_CONCEAL(a5)
        rts
.sg_n0:
        cmp.w   #1,d0
        bne.s   .sg_n1
        or.b    #FSF_BOLD,CU_STYLE(a5)
        rts
.sg_n1:
        cmp.w   #2,d0
        bne.s   .sg_n2
        move.b  #2,CU_FGPEN(a5)      ; "faint" = colour 2
        rts
.sg_n2:
        cmp.w   #3,d0
        bne.s   .sg_n3
        or.b    #FSF_ITALIC,CU_STYLE(a5)
        rts
.sg_n3:
        cmp.w   #4,d0
        bne.s   .sg_n4
        or.b    #FSF_UNDERLINED,CU_STYLE(a5)
        rts
.sg_n4:
        cmp.w   #7,d0
        bne.s   .sg_n7
        st      CU_INV(a5)
        rts
.sg_n7:
        cmp.w   #8,d0
        bne.s   .sg_n8
        st      CU_CONCEAL(a5)
        rts
.sg_n8:
        cmp.w   #39,d0
        bne.s   .sg_n39
        move.b  #CU_DEFFG,CU_FGPEN(a5)
        rts
.sg_n39:
        cmp.w   #49,d0
        bne.s   .sg_n49
        clr.b   CU_BGPEN(a5)
        rts
.sg_n49:
        sub.w   #30,d0
        bcs.s   .sg_ret
        cmp.w   #7,d0
        bhi.s   .sg_bg
        move.b  d0,CU_FGPEN(a5)
        rts
.sg_bg:
        sub.w   #10,d0
        bcs.s   .sg_ret
        cmp.w   #7,d0
        bhi.s   .sg_ret
        move.b  d0,CU_BGPEN(a5)
.sg_ret:
        rts

; cu_ctl(d0.b = byte, a5, a3, a6): controls and the ESC / CSI automaton (§3.2). Sets CU_AGAIN when the byte must be
; read again in the normal state. Clobbers d0-d3/d5-d7/a0/a1.
cu_ctl:
        move.b  CU_ESC(a5),d1
        beq.s   cu_plain
        subq.b  #1,d1
        beq     .ct_esc
        subq.b  #1,d1
        beq     cu_csi
        ; ESC intermediates: more of them, or the end of an ignored sequence
        cmp.b   #$20,d0
        blo     .ct_again
        cmp.b   #$30,d0
        blo     cu_ret
        cmp.b   #$7F,d0
        bhs     .ct_again
        clr.b   CU_ESC(a5)
        rts
.ct_again:
        clr.b   CU_ESC(a5)
        st      CU_AGAIN(a5)
        rts
.ct_esc:                             ; after ESC
        cmp.b   #$20,d0
        blo.s   .ct_again
        cmp.b   #$80,d0
        bhs.s   .ct_again
        cmp.b   #$30,d0
        bhs.s   .ct_e30
        move.b  #3,CU_ESC(a5)        ; intermediate
        rts
.ct_e30:
        cmp.b   #$40,d0
        blo     cu_ret               ; $30-$3F: ignored, still after ESC
        clr.b   CU_ESC(a5)
        cmp.b   #$60,d0
        bhs.s   .ct_e60
        add.b   #$40,d0              ; ESC Fe = the C1 control byte + $40
        bra.s   cu_plain
.ct_e60:
        cmp.b   #'c',d0
        beq     cu_ris
        rts
cu_plain:
        cmp.b   #$1B,d0
        bne.s   .ct_n1b
        move.b  #1,CU_ESC(a5)
        rts
.ct_n1b:
        cmp.b   #$9B,d0
        beq     .ct_csistart
        cmp.b   #7,d0
        beq     cu_beep
        cmp.b   #8,d0
        beq     .ct_bs
        cmp.b   #9,d0
        beq     cu_ht
        cmp.b   #10,d0
        bne.s   .ct_nlf
        btst    #CUM_LNM,CU_MODES+2(a5)
        beq     .ct_ind
        clr.w   CU_XCP(a5)
.ct_ind:
        move.w  CU_XCP(a5),d0        ; just wrapped (lazy wrap pending): the line feed is that wrap
        cmp.w   CU_XMAX(a5),d0
        ble     cu_lf
        clr.w   CU_XCP(a5)
        bra     cu_lf
.ct_nlf:
        cmp.b   #11,d0
        beq     cu_ri
        cmp.b   #12,d0
        beq     cu_ff
        cmp.b   #13,d0
        bne.s   .ct_ncr
        clr.w   CU_XCP(a5)
        rts
.ct_ncr:
        cmp.b   #14,d0
        bne.s   .ct_nso
        st      CU_SO(a5)
        rts
.ct_nso:
        cmp.b   #15,d0
        bne.s   .ct_nsi
        clr.b   CU_SO(a5)
        rts
.ct_nsi:
        cmp.b   #$84,d0              ; IND
        beq.s   .ct_ind
        cmp.b   #$85,d0              ; NEL
        bne.s   .ct_nnel
        clr.w   CU_XCP(a5)
        bra     .ct_ind
.ct_nnel:
        cmp.b   #$88,d0              ; HTS
        beq     cu_hts
        cmp.b   #$8D,d0              ; RI
        beq     cu_ri
        rts
.ct_bs:                              ; non-destructive; column 0 with AWM: last column of the previous line
        move.w  CU_XCP(a5),d0
        cmp.w   CU_XMAX(a5),d0
        ble.s   .ct_bs1
        move.w  CU_XMAX(a5),CU_XCP(a5) ; after a full line: back to the last column
        rts
.ct_bs1:
        tst.w   d0
        beq.s   .ct_bs0
        subq.w  #1,CU_XCP(a5)
        rts
.ct_bs0:
        btst    #CUM_AWM,CU_MODES+2(a5)
        beq     cu_ret
        move.w  CU_XMAX(a5),CU_XCP(a5)
        bra     cu_ri
.ct_csistart:
        move.b  #2,CU_ESC(a5)
        clr.b   CU_NPAR(a5)
        clr.b   CU_NINT(a5)
        clr.b   CU_INTER(a5)
        lea     CU_PARS(a5),a0
        moveq   #CU_NPARS-1,d1
.ct_pclr:
        move.w  #CU_PDEF,(a0)+
        dbra    d1,.ct_pclr
        rts
cu_csi:                              ; inside a CSI
        cmp.b   #$20,d0              ; C0 / C1 control: sequence abandoned, the byte is read again
        blo     .ct_again2
        cmp.b   #$80,d0
        blo.s   .ct_c7
        cmp.b   #$A0,d0
        blo.s   .ct_again2
        rts                          ; $A0-$FF: ignored
.ct_c7:
        tst.b   CU_NINT(a5)
        bne     .ct_interm
        cmp.b   #$30,d0
        blo     .ct_toint
        cmp.b   #$40,d0
        bhs     .ct_final
        lea     CU_PARS(a5),a0       ; parameter bytes
        moveq   #0,d1
        move.b  CU_NPAR(a5),d1
        cmp.w   #CU_NPARS,d1
        bhs     cu_ret               ; beyond 24: lost
        add.w   d1,d1
        add.w   d1,a0
        cmp.b   #';',d0
        bne.s   .ct_nsc
        addq.b  #1,CU_NPAR(a5)
        rts
.ct_nsc:
        cmp.b   #':',d0
        beq     cu_ret
        cmp.b   #'<',d0
        blo.s   .ct_dig
        sub.b   #'<'-1,d0            ; < = > ? -> -1 -2 -3 -4
        ext.w   d0
        neg.w   d0
        move.w  d0,(a0)
        rts
.ct_dig:
        and.w   #$000F,d0
        move.w  (a0),d1
        cmp.w   #CU_PDEF,d1
        bne.s   .ct_dacc
        moveq   #0,d1
.ct_dacc:
        muls    #10,d1
        tst.w   d1
        bmi.s   .ct_dneg
        add.w   d0,d1
        move.w  d1,(a0)
        rts
.ct_dneg:
        sub.w   d0,d1                ; after < = > ?: the digits count negatively (>1 = -31)
        move.w  d1,(a0)
        rts
.ct_again2:
        clr.b   CU_ESC(a5)
        st      CU_AGAIN(a5)
        rts
.ct_toint:
        move.b  d0,CU_INTER(a5)
.ct_addint:
        addq.b  #1,CU_NINT(a5)
        rts
.ct_interm:                          ; after an intermediate
        cmp.b   #$30,d0
        blo.s   .ct_addint
        cmp.b   #$40,d0
        blo.s   .ct_again2           ; $30-$3F: abandoned, read again (displayed)
        clr.b   CU_ESC(a5)
        cmp.b   #$70,d0
        blo     cu_ret               ; $40-$6F: ignored
        cmp.b   #1,CU_NINT(a5)       ; $70-$7E: only with a single SPACE
        bne     cu_ret
        cmp.b   #' ',CU_INTER(a5)
        bne     cu_ret
        cmp.b   #'p',d0
        bne.s   .ct_nsp
        clr.b   CU_CUROFF(a5)        ; CSI SPACE p: visible; CSI 0 SPACE p: hidden
        tst.w   CU_PARS(a5)
        bne     cu_ret
        st      CU_CUROFF(a5)
        rts
.ct_nsp:
        cmp.b   #'q',d0
        beq     cu_report
        rts
.ct_final:
        clr.b   CU_ESC(a5)
        move.w  CU_PARS(a5),d6       ; d6 = n for movements: default, 0 or negative -> 1
        bgt.s   .ct_n1
        moveq   #1,d6
.ct_n1:
        lea     ct_finals(pc),a0
.ct_ftab:
        move.w  (a0)+,d1
        beq     cu_ret               ; final not in the table: ignored
        move.w  (a0)+,d2
        cmp.b   d1,d0
        bne.s   .ct_ftab
        lea     ct_finals(pc),a0
        jmp     0(a0,d2.w)

FIN             MACRO
        dc.w    \1,\2-ct_finals
                ENDM
ct_finals:
        FIN     'A',ct_cuu
        FIN     'B',ct_cud
        FIN     'C',ct_cuf
        FIN     'D',ct_cub
        FIN     'E',ct_cnl
        FIN     'F',ct_cpl
        FIN     'H',ct_cup
        FIN     'f',ct_cup
        FIN     'I',ct_cht
        FIN     'J',ct_ed
        FIN     'K',cu_eol
        FIN     'L',ct_il
        FIN     'M',ct_dl
        FIN     'P',ct_dch
        FIN     '@',ct_ich
        FIN     'S',ct_su
        FIN     'T',ct_sd
        FIN     'W',ct_ctc
        FIN     'Z',ct_cbt
        FIN     'g',ct_tbc
        FIN     'h',ct_sm
        FIN     'l',ct_rm
        FIN     'm',ct_sgr
        FIN     'n',ct_dsr
        FIN     'q',cu_report        ; (also without the SPACE: Ed and other programs send CSI q)
        FIN     't',ct_page
        FIN     'u',ct_line
        FIN     'x',ct_xorg
        FIN     'y',ct_yorg
        FIN     '{',ct_rawon
        FIN     '}',ct_rawoff
        dc.w    0

ct_cuu:                              ; up; beyond the top with ASM: the deficit scrolls down
        move.w  CU_YCP(a5),d1
        sub.w   d6,d1
        bpl.s   .uu_set
        neg.w   d1
        clr.w   CU_YCP(a5)
        btst    #CUM_ASM,CU_MODES+2(a5)
        beq     cu_ret
        neg.w   d1
        bra     cu_vscroll
.uu_set:
        move.w  d1,CU_YCP(a5)
        rts
ct_cud:                              ; down; beyond the bottom with ASM: the excess scrolls up
        move.w  CU_YCP(a5),d1
        add.w   d6,d1
        sub.w   CU_YMAX(a5),d1
        ble.s   .ud_set
        move.w  CU_YMAX(a5),CU_YCP(a5)
        btst    #CUM_ASM,CU_MODES+2(a5)
        beq     cu_ret
        bra     cu_vscroll
.ud_set:
        add.w   CU_YMAX(a5),d1
        move.w  d1,CU_YCP(a5)
        rts
ct_cnl:
        clr.w   CU_XCP(a5)
        bra.s   ct_cud
ct_cpl:
        clr.w   CU_XCP(a5)
        bra.s   ct_cuu
ct_cuf:                              ; right; past XMax: next lines with AWM, XMax otherwise
        move.w  CU_XCP(a5),d0
        cmp.w   CU_XMAX(a5),d0
        ble.s   .uf_in
        move.w  CU_XMAX(a5),d0
.uf_in:
        add.w   d6,d0
        cmp.w   CU_XMAX(a5),d0
        ble.s   .uf_set
        btst    #CUM_AWM,CU_MODES+2(a5)
        bne.s   .uf_wrap
        move.w  CU_XMAX(a5),d0
.uf_set:
        move.w  d0,CU_XCP(a5)
        rts
.uf_wrap:
        move.w  CU_XMAX(a5),d1
        addq.w  #1,d1
        ext.l   d0
        divu    d1,d0
        swap    d0
        move.w  d0,CU_XCP(a5)        ; column in the last line reached
        swap    d0
        move.w  d0,d7                ; lines to go down
        subq.w  #1,d7
.uf_lf:
        bsr     cu_lf
        dbra    d7,.uf_lf
        rts
ct_cub:                              ; left; before column 0: previous lines with AWM, 0 otherwise
        move.w  CU_XCP(a5),d0
        cmp.w   CU_XMAX(a5),d0
        ble.s   .ub_in
        move.w  CU_XMAX(a5),d0
.ub_in:
        sub.w   d6,d0
        bpl.s   .ub_set
        btst    #CUM_AWM,CU_MODES+2(a5)
        bne.s   .ub_wrap
        moveq   #0,d0
.ub_set:
        move.w  d0,CU_XCP(a5)
        rts
.ub_wrap:
        move.w  d0,d7
.ub_lp:
        add.w   CU_XMAX(a5),d7
        addq.w  #1,d7
        bsr     cu_ri
        tst.w   d7
        bmi.s   .ub_lp
        move.w  d7,CU_XCP(a5)
        rts
ct_cup:                              ; line;column, base 1, bounded, no scrolling
        move.w  CU_PARS+2(a5),d1
        bgt.s   .up_c
        moveq   #1,d1
.up_c:
        subq.w  #1,d1
        cmp.w   CU_XMAX(a5),d1
        ble.s   .up_cx
        move.w  CU_XMAX(a5),d1
.up_cx:
        move.w  d1,CU_XCP(a5)
        move.w  d6,d1
        subq.w  #1,d1
        cmp.w   CU_YMAX(a5),d1
        ble.s   .up_cy
        move.w  CU_YMAX(a5),d1
.up_cy:
        move.w  d1,CU_YCP(a5)
        rts
ct_cht:
        move.w  d6,d7
        subq.w  #1,d7
.ch_lp:
        bsr     cu_ht
        dbra    d7,.ch_lp
        rts
ct_cbt:
        move.w  d6,d7
        subq.w  #1,d7
.cb_lp:
        bsr     cu_cbt
        dbra    d7,.cb_lp
        rts
ct_ed:                               ; to the end of the line, then all the following lines (parameter ignored)
        bsr     cu_eol
        move.w  CU_YCP(a5),d1
        cmp.w   CU_YMAX(a5),d1
        bge     cu_ret
        addq.w  #1,d1
        mulu    CU_YRSIZE(a5),d1
        add.w   CU_YRORIGIN(a5),d1
        move.w  CU_XRORIGIN(a5),d0
        move.w  CU_XREXTANT(a5),d2
        move.w  CU_YREXTANT(a5),d3
        bra     cu_fill
ct_il:                               ; inserts n lines at the cursor line (downwards)
        move.w  d6,d1
        neg.w   d1
        bra.s   ct_lines
ct_dl:                               ; deletes n lines (upwards)
        move.w  d6,d1
ct_lines:
        muls    CU_YRSIZE(a5),d1
        move.w  CU_YCP(a5),d3
        mulu    CU_YRSIZE(a5),d3
        add.w   CU_YRORIGIN(a5),d3
        bra     cu_scroll
ct_dch:                              ; deletes n characters (the rest of the line moves left)
        move.w  d6,d1
        mulu    CU_XRSIZE(a5),d1
        bra     cu_hshift
ct_ich:                              ; inserts n blanks (the rest of the line moves right)
        move.w  d6,d1
        mulu    CU_XRSIZE(a5),d1
        neg.w   d1
        bra     cu_hshift
ct_su:
        move.w  d6,d1
        bra     cu_vscroll
ct_sd:
        move.w  d6,d1
        neg.w   d1
        bra     cu_vscroll
ct_dsr:                              ; only the first parameter is looked at: 6 = cursor position report
        cmp.w   #6,CU_PARS(a5)
        beq     cu_dsr
        rts
ct_page:                             ; CSI n t: fixed page length (n > 0), automatic otherwise
        move.w  CU_PARS(a5),d0
        bgt.s   .pg_set
        moveq   #0,d0
.pg_set:
        move.w  d0,CU_FIXROW(a5)
        bra.s   ct_regeom
ct_line:                             ; CSI n u: fixed line length
        move.w  CU_PARS(a5),d0
        bgt.s   .ln_set
        moveq   #0,d0
.ln_set:
        move.w  d0,CU_FIXCOL(a5)
        bra.s   ct_regeom
ct_xorg:                             ; CSI n x: XROrigin in pixels (n >= 0), automatic by default
        move.w  CU_PARS(a5),d0
        cmp.w   #CU_PDEF,d0
        bne.s   .xo_set
        moveq   #-1,d0
.xo_set:
        move.w  d0,CU_FIXXO(a5)
        bra.s   ct_regeom
ct_yorg:
        move.w  CU_PARS(a5),d0
        cmp.w   #CU_PDEF,d0
        bne.s   .yo_set
        moveq   #-1,d0
.yo_set:
        move.w  d0,CU_FIXYO(a5)
ct_regeom:                           ; geometry recomputed at once; the cursor stays within it
        bsr     cu_geom
        move.w  CU_YCP(a5),d0
        cmp.w   CU_YMAX(a5),d0
        ble.s   .rg_x
        move.w  CU_YMAX(a5),CU_YCP(a5)
.rg_x:
        move.w  CU_XCP(a5),d0
        cmp.w   CU_XMAX(a5),d0
        ble     cu_ret
        clr.w   CU_XCP(a5)
        rts

; CSI lists: each parameter of CU_PARS up to CU_NPAR goes through the routine in a1 (d0.w = parameter).
ct_each:
        movem.l d6-d7/a2,-(sp)
        move.l  a1,a2
        lea     CU_PARS(a5),a0
        moveq   #0,d7
        move.b  CU_NPAR(a5),d7
        cmp.w   #CU_NPARS-1,d7
        bls.s   .ea_lp
        moveq   #CU_NPARS-1,d7
.ea_lp:
        move.w  (a0)+,d0
        movem.l d7/a0,-(sp)
        jsr     (a2)
        movem.l (sp)+,d7/a0
        dbra    d7,.ea_lp
        movem.l (sp)+,d6-d7/a2
        rts
ct_ctc:
        lea     .tc_one(pc),a1
        bra.s   ct_each
.tc_one:                             ; 0/default: set; 2: clear the current one; 4, 5: clear all
        tst.w   d0
        ble     cu_hts
        cmp.w   #2,d0
        beq     cu_tbc
        cmp.w   #4,d0
        beq     cu_tclr
        cmp.w   #5,d0
        beq     cu_tclr
        rts
ct_tbc:
        lea     .tg_one(pc),a1
        bra.s   ct_each
.tg_one:                             ; 0/default: clear the current one; 3: clear all
        tst.w   d0
        ble     cu_tbc
        cmp.w   #3,d0
        beq     cu_tclr
        rts
ct_sgr:
        lea     cu_sgr1(pc),a1
        bsr.s   ct_each
        bra     cu_setpens
ct_sm:
        lea     .sm_one(pc),a1
        bra.s   ct_each
.sm_one:
        bsr.s   ct_modebit
        bmi     cu_ret
        bset    d0,0(a0,d1.w)
        rts
ct_rm:
        lea     .rm_one(pc),a1
        bra     ct_each
.rm_one:
        bsr.s   ct_modebit
        bmi     cu_ret
        bclr    d0,0(a0,d1.w)
        rts
; ct_modebit(d0.w = SM/RM parameter) -> d1.w = byte of cu_Modes, d0 = bit, a0 = cu_Modes; N = 1 when ignored.
; 0..20 as they are, >1 (-31) = 21 ASM, ?7 (-47) = 22 AWM.
ct_modebit:
        cmp.w   #-31,d0
        bne.s   .mb_n31
        moveq   #21,d0
.mb_n31:
        cmp.w   #-47,d0
        bne.s   .mb_n47
        moveq   #22,d0
.mb_n47:
        tst.w   d0
        bmi.s   .mb_ret
        cmp.w   #22,d0
        bhi.s   .mb_no
        lea     CU_MODES(a5),a0
        moveq   #0,d1
        move.w  d0,d1
        lsr.w   #3,d1
        and.w   #7,d0                ; N = 0
        rts
.mb_no:
        moveq   #-1,d0
.mb_ret:
        rts
ct_rawon:
        lea     .ro_one(pc),a1
        bra     ct_each
.ro_one:
        bsr.s   ct_rawbit
        bmi     cu_ret
        bset    d0,0(a0,d1.w)
        rts
ct_rawoff:
        lea     .rf_one(pc),a1
        bra     ct_each
.rf_one:
        bsr.s   ct_rawbit
        bmi     cu_ret
        bclr    d0,0(a0,d1.w)
        rts
; ct_rawbit(d0.w = class 0..18) -> d1.w = byte of cu_RawEvents, d0 = bit, a0 = cu_RawEvents; N = 1 when ignored.
ct_rawbit:
        tst.w   d0
        bmi.s   .rb_ret
        cmp.w   #18,d0
        bhi.s   .rb_no
        lea     CU_RAWEV(a5),a0
        move.w  d0,d1
        lsr.w   #3,d1
        and.w   #7,d0
        rts
.rb_no:
        moveq   #-1,d0
.rb_ret:
        rts
console_end:
