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
; Accepted deviations: no scrolling (clamped at the bottom), no CSI/ANSI sequences, no visible cursor.
; HAND-AUTHORED 8x8 font (public domain, tests/mk_font8x8.py) — NEVER the ROM's topaz (clean-room).
; IMPLEMENTATION track ("clean"): AutoDocs console.device + public NDK includes. NO ROM reading.

                include "exec.i"
                include "graphics.i"
                include "intuition.i"

                xref    font8x8          ; graphics/font8x8.s (8x8 glyphs, ASCII 0x20..0x7F)
                xref    km_conv          ; exec/keymap.s: one RAWKEY event -> bytes through a struct KeyMap

CMD_READ     EQU 2                ; standard io_Command (io.i: READ=2, WRITE=3)
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
        dc.l    console_null         ; LVO -42 CDInputHandler (not impl.)
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
        move.l  4(sp),a0             ; a0 = console base: unit removed from CONB_UNITS
        lea     CONB_UNITS(a0),a0
        move.l  (sp),d0
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
.bi_read:                            ; #3b: drains the read buffer (ASCII cooked via input.device) into io_Data
        move.l  IO_DATA2(a3),a4      ; dest
        move.l  IO_LEN2(a3),d4       ; max
        moveq   #0,d0                ; count read
.bi_rl:
        tst.l   d4
        beq.s   .bi_rdone
        move.w  CONB_RHEAD(a2),d1
        cmp.w   CONB_RTAIL(a2),d1
        beq.s   .bi_rdone            ; read buffer empty
        lea     CONB_RBUF(a2),a0
        move.b  0(a0,d1.w),(a4)+
        addq.w  #1,d1
        and.w   #CON_RBMASK,d1
        move.w  d1,CONB_RHEAD(a2)
        addq.l  #1,d0
        subq.l  #1,d4
        bra.s   .bi_rl
.bi_rdone:
        move.l  d0,IO_ACTUAL2(a3)    ; io_Actual = bytes read
.bi_done:
        move.l  a2,a6                ; a6 = device base (BeginIO convention)
        movem.l (sp)+,d4/a2-a4
        rts
; --- open unit (request from OpenDevice): direct synchronous callers = null IO_UNIT (path above) ---
.bi_unit:
        move.w  IO_COMMAND(a3),d0
        cmp.w   #CMD_WRITE,d0
        beq.s   .bu_write
        cmp.w   #CMD_READ,d0
        beq     .bu_read
        cmp.w   #CD_ASKKEYMAP,d0     ; CD_ASKKEYMAP, CD_SETKEYMAP, CD_ASKDEFAULTKEYMAP, CD_SETDEFAULTKEYMAP
        blo.s   .bu_nocmd
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
        bsr     cu_write
        bra     .bu_reply
.bu_wl:
        tst.l   d4
        beq.s   .bu_reply
        move.b  (a4)+,d0
        bsr     con_putglyph
        subq.l  #1,d4
        bra.s   .bu_wl
.bu_read:
        move.l  ($4).w,a6
        jsr     LVO_DISABLE(a6)
        bsr     con_target           ; a console has the active window: only its reads take the keys
        beq.s   .bu_rany
        cmp.l   IO_UNIT(a3),d0
        bne.s   .bu_queue
.bu_rany:
        move.l  a3,a1
        bsr     con_fillread         ; d0 = bytes copied
        tst.l   d0
        bne.s   .bu_rgot
.bu_queue:
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
.bu_reply:
        btst    #0,IO_FLAGS(a3)      ; IOF_QUICK: completed in place
        bne     .bi_done
        move.l  ($4).w,a6
        move.l  a3,a1
        jsr     LVO_REPLYMSG(a6)
        bra     .bi_done

; con_fillread(a1 = CMD_READ, a2 = base): copies the read buffer into io_Data (max io_Length) -> d0 = bytes copied
; = io_Actual. Called under Disable. Clobbers d1/a0.
con_fillread:
        movem.l d2/a3,-(sp)
        move.l  IO_DATA2(a1),a3
        move.l  IO_LEN2(a1),d2
        moveq   #0,d0
.cf_lp:
        tst.l   d2
        beq.s   .cf_done
        move.w  CONB_RHEAD(a2),d1
        cmp.w   CONB_RTAIL(a2),d1
        beq.s   .cf_done
        lea     CONB_RBUF(a2),a0
        move.b  0(a0,d1.w),(a3)+
        addq.w  #1,d1
        and.w   #CON_RBMASK,d1
        move.w  d1,CONB_RHEAD(a2)
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

; console_input_handler(a0 = InputEvent list, a1 = is_Data = console base): handler registered on input.device via
; IND_ADDHANDLER. Each RAWKEY is converted through the keymap of the unit whose window is active (the default keymap
; otherwise); the bytes go into the read buffer only if they all fit, then a waiting CMD_READ is served. Returns
; d0 = unchanged list (pass-through). Preserves d2-d7/a2-a6.
console_input_handler:
        movem.l d2-d4/a2-a3,-(sp)
        lea     -16(sp),sp           ; conversion buffer
        move.l  a0,d3                ; d3 = original list (pass-through return)
        move.l  a1,a2                ; a2 = console base
        move.l  a0,a3                ; a3 = current event
.cih_loop:
        move.l  a3,d0
        beq     .cih_done
        cmp.b   #IECLASS_RAWKEY,IE_CLASS(a3)
        bne.s   .cih_next
        bsr     con_target           ; keymap of the active console unit, else the default one
        lea     CONB_DEFKM(a2),a1
        beq.s   .cih_km
        move.l  d0,a1
        lea     CU_KEYMAP(a1),a1
.cih_km:
        move.l  a2,-(sp)
        move.l  a1,a2
        move.l  a3,a0
        lea     4(sp),a1
        moveq   #16,d1
        jsr     km_conv
        move.l  (sp)+,a2
        move.l  d0,d2                ; d2 = bytes
        ble.s   .cih_next
                ifeq    CON_NO_READBUF
        move.w  CONB_RHEAD(a2),d0    ; free room in the ring
        sub.w   CONB_RTAIL(a2),d0
        subq.w  #1,d0
        and.w   #CON_RBMASK,d0
        cmp.w   d2,d0
        blo.s   .cih_next            ; does not fit: dropped
        lea     (sp),a0
        lea     CONB_RBUF(a2),a1
        move.w  CONB_RTAIL(a2),d0
        subq.w  #1,d2
.cih_push:
        move.b  (a0)+,0(a1,d0.w)
        addq.w  #1,d0
        and.w   #CON_RBMASK,d0
        dbra    d2,.cih_push
        move.w  d0,CONB_RTAIL(a2)
        bsr     con_servereads       ; a CMD_READ of an open unit was waiting: served and replied
                endc                 ; RED CON_NO_READBUF: converts but does not buffer -> empty CMD_READ
.cih_next:
        move.l  IE_NEXTEVENT(a3),a3
        bra     .cih_loop
.cih_done:
        move.l  d3,d0                ; return the original list (pass-through)
        lea     16(sp),sp
        movem.l (sp)+,d2-d4/a2-a3
        rts

; con_servereads(a2 = base): if a CMD_READ is waiting and the read buffer has bytes, fills it, unhooks it
; and replies to it. If the active window is that of a console, only a read from that unit is served (otherwise the
; keys wait in the buffer); otherwise the head of the queue. Preserves d2-d7/a2-a6.
con_servereads:
        movem.l a3-a4/a6,-(sp)
        move.l  ($4).w,a6
        jsr     LVO_DISABLE(a6)
        bsr     con_target
        move.l  d0,d1                ; d1 = targeted unit | 0
        lea     CONB_RQ(a2),a4       ; a4 = previous link
.sr_find:
        move.l  (a4),d0
        beq.s   .sr_none
        move.l  d0,a3
        tst.l   d1
        beq.s   .sr_take
        cmp.l   IO_UNIT(a3),d1
        beq.s   .sr_take
        move.l  a3,a4
        bra.s   .sr_find
.sr_take:
        move.l  a3,a1
        bsr     con_fillread
        tst.l   d0
        beq.s   .sr_none
        move.l  (a3),(a4)            ; unhook the served request
        jsr     LVO_ENABLE(a6)
        move.l  a3,a1
        jsr     LVO_REPLYMSG(a6)
        bra.s   .sr_ret
.sr_none:
        jsr     LVO_ENABLE(a6)
.sr_ret:
        movem.l (sp)+,a3-a4/a6
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
        clr.w   CONB_RHEAD(a2)
        clr.w   CONB_RTAIL(a2)
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
; Text area = inside of the window (borders excluded), 8x8 cells. Controls: BEL ignored, BS, TAB (every
; 8), LF (with return to column 0), VT, FF (clears), CR, ESC c (resets), $84 IND, $85 NEL, $8D RI. CSI
; (ESC [ or $9B): A B C D E F (movements), H f (position), J K (erasures), L M (line insertion / deletion),
; m (pens 30-37/40-47, inverse 7, 0 = default: text pen 2, background 0), SPACE p (cursor visible or
; not). CSI P (character deletion) erases up to the end of the line (no horizontal shift); @, t, u,
; x, y, q ignored. Automatic line wrap when writing beyond the last column, one-line scroll at the bottom of the
; area. Cursor: inverted cell (COMPLEMENT mode), removed before each write and redrawn afterwards.
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
CU_FGPEN        EQU 259
CU_BGPEN        EQU 260
CU_ESC          EQU 296              ; private: 0 normal, 1 after ESC, 2 inside a CSI
CU_NPAR         EQU 297              ; private: index of the current CSI parameter (0..1)
CU_PSEEN        EQU 298              ; private: a digit has been read for parameter 0
CU_INTER        EQU 299              ; private: CSI intermediate byte ($20..$2F)
CU_PAR0         EQU 300              ; private: CSI parameters
CU_PAR1         EQU 302
CU_CUROFF       EQU 304              ; private: cursor hidden (CSI 0 SPACE p)
CU_CURVIS       EQU 305              ; private: cursor currently drawn
CU_INV          EQU 306              ; private: inverse video (CSI 7 m)
CU_NEXT         EQU 308              ; private: next unit (CONB_UNITS list)
CU_KEYMAP       EQU 66               ; cu_KeyMapStruct (devices/conunit.h): the unit's struct KeyMap
CU_SIZE         EQU 312
CU_DEFFG        EQU 2                ; default text pen: black on the green background (project theme; 1.3: 1)

; cu_init(a0 = cleared ConUnit, a1 = Window): bounds of the text area from the window geometry.
; Preserves everything except d0/d1.
cu_init:
        move.l  a1,CU_WINDOW(a0)
        move.w  #GFX_FONTW,CU_XRSIZE(a0)
        move.w  #GFX_FONTH,CU_YRSIZE(a0)
        moveq   #0,d0
        move.b  WD_BORDERLEFT(a1),d0
        move.w  d0,CU_XRORIGIN(a0)
        move.b  WD_BORDERTOP(a1),d0
        move.w  d0,CU_YRORIGIN(a0)
        move.w  WD_WIDTH(a1),d0
        moveq   #0,d1
        move.b  WD_BORDERLEFT(a1),d1
        sub.w   d1,d0
        move.b  WD_BORDERRIGHT(a1),d1
        sub.w   d1,d0
        asr.w   #3,d0
        subq.w  #1,d0
        bpl.s   .ci_x
        moveq   #0,d0
.ci_x:
        move.w  d0,CU_XMAX(a0)
        addq.w  #1,d0
        lsl.w   #3,d0
        add.w   CU_XRORIGIN(a0),d0
        subq.w  #1,d0
        move.w  d0,CU_XREXTANT(a0)
        move.w  WD_HEIGHT(a1),d0
        moveq   #0,d1
        move.b  WD_BORDERTOP(a1),d1
        sub.w   d1,d0
        move.b  WD_BORDERBOTTOM(a1),d1
        sub.w   d1,d0
        asr.w   #3,d0
        subq.w  #1,d0
        bpl.s   .ci_y
        moveq   #0,d0
.ci_y:
        move.w  d0,CU_YMAX(a0)
        addq.w  #1,d0
        lsl.w   #3,d0
        add.w   CU_YRORIGIN(a0),d0
        subq.w  #1,d0
        move.w  d0,CU_YREXTANT(a0)
        move.b  #CU_DEFFG,CU_FGPEN(a0)
        clr.b   CU_BGPEN(a0)
        rts

; cu_write(a0 = ConUnit, a4 = data, d4 = length, a2 = console base): interprets the stream in the window.
; Preserves d2-d7/a2-a6 (a4/d4 consumed: saved).
cu_write:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  a0,a5                ; a5 = ConUnit
        move.l  CONB_GFXBASE(a2),a6  ; a6 = GfxBase
        move.l  CU_WINDOW(a5),a0
        move.l  WD_RPORT(a0),a3      ; a3 = RastPort
        move.l  a3,a1
        moveq   #JAM2,d0
        jsr     LVO_SETDRMD(a6)
        bsr     cu_setpens
        bsr     cu_curoff
.cw_lp:
        tst.l   d4
        beq.s   .cw_end
        tst.b   CU_ESC(a5)
        bne.s   .cw_ctl
        move.b  (a4),d0
        bsr     cu_isprint
        beq.s   .cw_print
.cw_ctl:
        move.b  (a4)+,d0
        subq.l  #1,d4
        bsr     cu_ctl
        bra.s   .cw_lp
.cw_print:
        move.w  CU_XCP(a5),d0        ; column beyond the last one: line wrap before writing
        cmp.w   CU_XMAX(a5),d0
        ble.s   .cw_fit
        clr.w   CU_XCP(a5)
        bsr     cu_lf
.cw_fit:
        move.w  CU_XMAX(a5),d3
        sub.w   CU_XCP(a5),d3
        addq.w  #1,d3                ; d3 = cells left on the line
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
        addq.w  #GFX_FONTBASE,d1
        move.l  a3,a1
        jsr     LVO_MOVE(a6)
        move.l  a2,a0
        move.w  d2,d0
        move.l  a3,a1
        jsr     LVO_TEXT(a6)
        add.w   d2,CU_XCP(a5)
        bra.s   .cw_lp
.cw_end:
        bsr     cu_curon
        movem.l (sp)+,d2-d7/a2-a6
        rts

; cu_isprint(d0.b) -> Z = 1 if printable character ($20..$7E, $A0..$FF). Only touches the condition codes.
cu_isprint:
        cmp.b   #$20,d0
        blo.s   .ip_no
        cmp.b   #$7F,d0
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
        lsl.w   #3,d0
        add.w   CU_XRORIGIN(a5),d0
        move.w  CU_YCP(a5),d1
        lsl.w   #3,d1
        add.w   CU_YRORIGIN(a5),d1
        rts

; cu_setpens(a5, a3 = RastPort, a6 = GfxBase): effective A/B pens (swapped in inverse video). Clobbers d0/d1/a0/a1.
cu_setpens:
        moveq   #0,d0
        move.b  CU_FGPEN(a5),d0
        moveq   #0,d1
        move.b  CU_BGPEN(a5),d1
        tst.b   CU_INV(a5)
        beq.s   .sp_n
        exg     d0,d1
.sp_n:
        move.l  d2,-(sp)             ; text and background merged by the BitMap's planes (screen reduced to 1 plane by a
        move.l  rp_BitMap(a3),a0     ; program: theme black = background) -> text uses the colour next to the background
        moveq   #0,d2
        move.b  bm_Depth(a0),d2
        moveq   #1,d0
        lsl.l   d2,d0
        subq.l  #1,d0
        move.l  d0,d2                ; d2 = mask of the displayable pens
        moveq   #0,d0
        move.b  CU_FGPEN(a5),d0
        tst.b   CU_INV(a5)
        beq.s   .sp_m
        move.b  CU_BGPEN(a5),d0
.sp_m:
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

; cu_curoff / cu_curon(a5, a3, a6): removes / draws the cursor (inverted cell). Clobbers d0-d3/a0/a1.
cu_curoff:
        tst.b   CU_CURVIS(a5)
        beq.s   cu_ret
        clr.b   CU_CURVIS(a5)
        bra.s   cu_cplcell
cu_curon:
        tst.b   CU_CUROFF(a5)
        bne.s   cu_ret
        move.w  CU_XCP(a5),d0
        cmp.w   CU_XMAX(a5),d0
        bgt.s   cu_ret               ; waiting for a line wrap: no cell
        st      CU_CURVIS(a5)
cu_cplcell:
        move.l  a3,a1
        moveq   #COMPLEMENT,d0
        jsr     LVO_SETDRMD(a6)
        bsr     cu_cellxy
        move.w  d0,d2
        addq.w  #GFX_FONTW-1,d2
        move.w  d1,d3
        addq.w  #GFX_FONTH-1,d3
        move.l  a3,a1
        jsr     LVO_RECTFILL(a6)
        move.l  a3,a1
        moveq   #JAM2,d0
        jmp     LVO_SETDRMD(a6)
cu_ret:
        rts

; cu_fill(d0..d3 = rectangle, a3, a6): fills with the effective background pen. Clobbers d0-d3/a0/a1.
cu_fill:
        movem.w d0-d3,-(sp)
        move.l  a3,a1
        moveq   #0,d0
        move.b  CU_BGPEN(a5),d0
        tst.b   CU_INV(a5)
        beq.s   .fl_n
        move.b  CU_FGPEN(a5),d0
.fl_n:
        jsr     LVO_SETAPEN(a6)
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

; cu_lf(a5, a3, a6): next line; at the bottom of the area, one-line scroll. Clobbers d0-d3/a0/a1.
cu_lf:
        move.w  CU_YCP(a5),d0
        cmp.w   CU_YMAX(a5),d0
        bge.s   .lf_scroll
        addq.w  #1,CU_YCP(a5)
        rts
.lf_scroll:
        move.w  CU_YMAX(a5),CU_YCP(a5)
        moveq   #GFX_FONTH,d1
        move.w  CU_YRORIGIN(a5),d3
        bra.s   cu_scroll

; cu_eol(a5, a3, a6): erases from the cursor cell to the end of the line. Clobbers d0-d3/a0/a1.
cu_eol:
        move.w  CU_XCP(a5),d0
        cmp.w   CU_XMAX(a5),d0
        bgt.s   cu_ret
        bsr     cu_cellxy
        move.w  CU_XREXTANT(a5),d2
        move.w  d1,d3
        addq.w  #GFX_FONTH-1,d3
        bra.s   cu_fill

; cu_ctl(d0.b = control or sequence byte, a5, a3, a6): controls and ESC / CSI sequences.
; Clobbers d0-d3/d5-d7/a0/a1.
cu_ctl:
        move.b  CU_ESC(a5),d1
        beq.s   .ct_plain
        subq.b  #1,d1
        beq     .ct_esc
        bra     .ct_csi
.ct_plain:
        cmp.b   #$1B,d0
        bne.s   .ct_n1b
        move.b  #1,CU_ESC(a5)
        rts
.ct_n1b:
        cmp.b   #$9B,d0
        beq     .ct_csistart
        cmp.b   #8,d0
        bne.s   .ct_nbs
        tst.w   CU_XCP(a5)
        beq.s   .ct_ret
        move.w  CU_XCP(a5),d0        ; after a full line, BS goes back to the last column
        cmp.w   CU_XMAX(a5),d0
        ble.s   .ct_bs
        move.w  CU_XMAX(a5),CU_XCP(a5)
        rts
.ct_bs:
        subq.w  #1,CU_XCP(a5)
.ct_ret:
        rts
.ct_nbs:
        cmp.b   #9,d0
        bne.s   .ct_ntab
        move.w  CU_XCP(a5),d0
        or.w    #7,d0
        addq.w  #1,d0
        cmp.w   CU_XMAX(a5),d0
        ble.s   .ct_tab
        move.w  CU_XMAX(a5),d0
.ct_tab:
        move.w  d0,CU_XCP(a5)
        rts
.ct_ntab:
        cmp.b   #10,d0
        bne.s   .ct_nlf
        clr.w   CU_XCP(a5)
        bra     cu_lf
.ct_nlf:
        cmp.b   #11,d0
        bne.s   .ct_nvt
        tst.w   CU_YCP(a5)
        beq.s   .ct_ret
        subq.w  #1,CU_YCP(a5)
        rts
.ct_nvt:
        cmp.b   #12,d0
        beq     .ct_ff
        cmp.b   #13,d0
        bne.s   .ct_ncr
        clr.w   CU_XCP(a5)
        rts
.ct_ncr:
        cmp.b   #$84,d0              ; IND
        beq     cu_lf
        cmp.b   #$85,d0              ; NEL
        bne.s   .ct_nnel
        clr.w   CU_XCP(a5)
        bra     cu_lf
.ct_nnel:
        cmp.b   #$8D,d0              ; RI: previous line, scroll down at the top of the area
        bne.s   .ct_ret
        tst.w   CU_YCP(a5)
        beq.s   .ct_ri
        subq.w  #1,CU_YCP(a5)
        rts
.ct_ri:
        moveq   #-GFX_FONTH,d1
        move.w  CU_YRORIGIN(a5),d3
        bra     cu_scroll
.ct_esc:                             ; after ESC
        clr.b   CU_ESC(a5)
        cmp.b   #'[',d0
        beq.s   .ct_csistart
        cmp.b   #'c',d0              ; RIS: reset (pens, cursor, erasure)
        bne     .ct_ret
        move.b  #CU_DEFFG,CU_FGPEN(a5)
        clr.b   CU_BGPEN(a5)
        clr.b   CU_INV(a5)
        clr.b   CU_CUROFF(a5)
        bsr     cu_setpens
.ct_ff:
        clr.l   CU_XCP(a5)           ; XCP = YCP = 0
        move.w  CU_XRORIGIN(a5),d0
        move.w  CU_YRORIGIN(a5),d1
        move.w  CU_XREXTANT(a5),d2
        move.w  CU_YREXTANT(a5),d3
        bra     cu_fill
.ct_csistart:
        move.b  #2,CU_ESC(a5)
        clr.l   CU_PAR0(a5)          ; PAR0 = PAR1 = 0
        clr.b   CU_NPAR(a5)
        clr.b   CU_PSEEN(a5)
        clr.b   CU_INTER(a5)
        rts
.ct_csi:                             ; inside a CSI: parameters, intermediates, final byte
        cmp.b   #'0',d0
        blo.s   .ct_nd
        cmp.b   #'9',d0
        bhi.s   .ct_nd
        and.w   #$000F,d0
        lea     CU_PAR0(a5),a0
        tst.b   CU_NPAR(a5)
        beq.s   .ct_p0
        lea     CU_PAR1(a5),a0
        bra.s   .ct_pacc
.ct_p0:
        st      CU_PSEEN(a5)
.ct_pacc:
        move.w  (a0),d1
        mulu    #10,d1
        add.w   d0,d1
        cmp.w   #999,d1
        bls.s   .ct_pst
        move.w  #999,d1
.ct_pst:
        move.w  d1,(a0)
        rts
.ct_nd:
        cmp.b   #';',d0
        bne.s   .ct_nsc
        move.b  #1,CU_NPAR(a5)
        rts
.ct_nsc:
        cmp.b   #$40,d0
        bhs.s   .ct_final
        cmp.b   #$20,d0
        blo.s   .ct_abort
        move.b  d0,CU_INTER(a5)      ; intermediate ($20..$3F except digits and ';')
        rts
.ct_abort:
        clr.b   CU_ESC(a5)           ; control byte inside a CSI: sequence abandoned
        rts
.ct_final:
        clr.b   CU_ESC(a5)
        move.w  CU_PAR0(a5),d6       ; d6 = n (parameter 0, at least 1 for movements)
        bne.s   .ct_n1
        moveq   #1,d6
.ct_n1:
        cmp.b   #'A',d0
        bne.s   .ct_nA
        move.w  CU_YCP(a5),d1
        sub.w   d6,d1
        bra     .ct_sety
.ct_nA:
        cmp.b   #'B',d0
        bne.s   .ct_nB
        move.w  CU_YCP(a5),d1
        add.w   d6,d1
        bra     .ct_sety
.ct_nB:
        cmp.b   #'C',d0
        bne.s   .ct_nC
        move.w  CU_XCP(a5),d1
        add.w   d6,d1
        bra     .ct_setx
.ct_nC:
        cmp.b   #'D',d0
        bne.s   .ct_nD
        move.w  CU_XCP(a5),d1
        sub.w   d6,d1
        bra     .ct_setx
.ct_nD:
        cmp.b   #'E',d0
        bne.s   .ct_nE
        clr.w   CU_XCP(a5)
        move.w  CU_YCP(a5),d1
        add.w   d6,d1
        bra     .ct_sety
.ct_nE:
        cmp.b   #'F',d0
        bne.s   .ct_nF
        clr.w   CU_XCP(a5)
        move.w  CU_YCP(a5),d1
        sub.w   d6,d1
        bra     .ct_sety
.ct_nF:
        cmp.b   #'H',d0
        beq.s   .ct_pos
        cmp.b   #'f',d0
        bne.s   .ct_nH
.ct_pos:
        move.w  CU_PAR1(a5),d1       ; column (1 by default)
        bne.s   .ct_pc
        moveq   #1,d1
.ct_pc:
        subq.w  #1,d1
        bsr     .ct_setx
        move.w  d6,d1
        subq.w  #1,d1
        bra     .ct_sety
.ct_nH:
        cmp.b   #'J',d0
        bne.s   .ct_nJ
        bsr     cu_eol
        move.w  CU_YCP(a5),d1        ; then the following lines
        cmp.w   CU_YMAX(a5),d1
        bge     .ct_ret2
        addq.w  #1,d1
        lsl.w   #3,d1
        add.w   CU_YRORIGIN(a5),d1
        move.w  CU_XRORIGIN(a5),d0
        move.w  CU_XREXTANT(a5),d2
        move.w  CU_YREXTANT(a5),d3
        bra     cu_fill
.ct_nJ:
        cmp.b   #'K',d0
        beq     cu_eol
        cmp.b   #'P',d0
        beq     cu_eol
        cmp.b   #'L',d0
        beq.s   .ct_lines
        cmp.b   #'M',d0
        bne.s   .ct_nM
.ct_lines:                           ; L: inserts n lines (downwards); M: deletes n of them (upwards)
        move.w  d6,d1
        lsl.w   #3,d1
        cmp.b   #'L',d0
        bne.s   .ct_lm
        neg.w   d1
.ct_lm:
        move.w  CU_YCP(a5),d3
        lsl.w   #3,d3
        add.w   CU_YRORIGIN(a5),d3
        bra     cu_scroll
.ct_nM:
        cmp.b   #'m',d0
        bne.s   .ct_nm
        move.w  CU_PAR0(a5),d0
        bsr.s   .ct_sgr
        tst.b   CU_NPAR(a5)
        beq.s   .ct_sgrdone
        move.w  CU_PAR1(a5),d0
        bsr.s   .ct_sgr
.ct_sgrdone:
        bra     cu_setpens
.ct_nm:
        cmp.b   #'p',d0
        bne.s   .ct_ret2
        cmp.b   #' ',CU_INTER(a5)
        bne.s   .ct_ret2
        clr.b   CU_CUROFF(a5)        ; CSI SPACE p: visible; CSI 0 SPACE p: hidden
        tst.b   CU_PSEEN(a5)
        beq.s   .ct_ret2
        tst.w   CU_PAR0(a5)
        bne.s   .ct_ret2
        st      CU_CUROFF(a5)
.ct_ret2:
        rts
; .ct_sgr(d0.w = SGR parameter): 0 default, 7 inverse, 30..37 / 39 foreground, 40..47 / 49 background.
.ct_sgr:
        tst.w   d0
        bne.s   .sg_n0
        move.b  #CU_DEFFG,CU_FGPEN(a5)
        clr.b   CU_BGPEN(a5)
        clr.b   CU_INV(a5)
        rts
.sg_n0:
        cmp.w   #7,d0
        bne.s   .sg_n7
        st      CU_INV(a5)
        rts
.sg_n7:
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
; .ct_setx / .ct_sety(d1.w = desired position): clamped to the text area.
.ct_setx:
        tst.w   d1
        bpl.s   .sx_lo
        moveq   #0,d1
.sx_lo:
        cmp.w   CU_XMAX(a5),d1
        ble.s   .sx_hi
        move.w  CU_XMAX(a5),d1
.sx_hi:
        move.w  d1,CU_XCP(a5)
        rts
.ct_sety:
        tst.w   d1
        bpl.s   .sy_lo
        moveq   #0,d1
.sy_lo:
        cmp.w   CU_YMAX(a5),d1
        ble.s   .sy_hi
        move.w  CU_YMAX(a5),d1
.sy_hi:
        move.w  d1,CU_YCP(a5)
        rts
console_end:
