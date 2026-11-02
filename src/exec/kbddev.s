; src/exec/kbddev.s — keyboard.device: exec interface of the keyboard (raw events, matrix, reset handlers).
;
; Serial decoding stays in keyboard.s (kbd_interrupt); it hands each raw keycode (bit 7 = released) over here
; via kbd_devevent: the matrix of pressed keys is kept up to date, the event is stored in a 32-entry ring (31
; usable; when full, the newest entry becomes the overflow code $7D) and the pending KBD_READEVENT requests are
; served from the ring unless the unit is stopped.
; Commands 0-13 per docs/analysis/keyboard-input-devices-v34.md §2: CMD_RESET (handshake pulse + flush, ring kept),
; CMD_CLEAR, CMD_STOP/START/FLUSH, KBD_READEVENT (as many events as io_Length holds, chained), KBD_READMATRIX
; (exactly 13 bytes), KBD_ADD/REMRESETHANDLER, KBD_RESETHANDLERDONE. CMD_READ/WRITE/UPDATE are refused. The
; keyboard reset sequence (Ctrl-Amiga-Amiga) is not relayed to the handlers: the list is maintained, not called.
; io_Error of STOP/START/FLUSH/RESET is 0 (undefined on 1.3).
; IMPLEMENTATION track ("clean"): AutoDocs keyboard.device + devices/keyboard.i + devices/inputevent.i +
; docs/analysis/keyboard-input-devices-v34.md. NO ROM reading.

                include "exec.i"

                xdef    kbd_devevent

KD_MATRIX       EQU LIB_SIZE         ; 13 bytes used (keys $00-$67), 16 reserved
KD_READQ        EQU LIB_SIZE+16      ; struct List of the queued KBD_READEVENTs (io_Unit)
KD_RESETQ       EQU KD_READQ+14      ; struct List of the reset handlers
KD_RD           EQU KD_RESETQ+14     ; word: ring read index (byte offset)
KD_WR           EQU KD_RD+2          ; word: ring write index
KD_STOP         EQU KD_WR+2          ; byte: CMD_STOP flag
KD_RHCNT        EQU KD_STOP+2        ; word: reset handlers still running
KD_BUF          EQU KD_RHCNT+2       ; 32 entries of 4 bytes: keycode.w, qualifiers.w
KD_BMASK        EQU $7F
KD_SIZE         EQU KD_BUF+128

KD_NCMDS        EQU 14
KD_MATRIXSIZE   EQU 13
KD_QUALBYTE     EQU 12               ; matrix byte of keys $60-$67 = qualifier low byte
KD_LASTKEY      EQU $67
KD_OVERFLOW     EQU $7D
IEQUAL_NUMPAD   EQU $0100
IO_ACTUAL3      EQU 32
IO_LENGTH3      EQU 36
IO_DATA3        EQU 40
IOERR_BADLEN3   EQU -4
CIAA_CRA_K      EQU $BFEE01

        EVEN
kbddev_romtag:
        dc.w    RTC_MATCHWORD
        dc.l    kbddev_romtag
        dc.l    kbddev_end
        dc.b    RTF_AUTOINIT|RTF_COLDSTART,34,NT_DEVICE,60
        dc.l    kbddev_name
        dc.l    kbddev_name
        dc.l    kbddev_inittab
kbddev_name:
        dc.b    "keyboard.device",0
        EVEN
kbddev_inittab:
        dc.l    KD_SIZE
        dc.l    kbddev_vectors
        dc.l    kbddev_datatab
        dc.l    kbddev_initfunc
kbddev_vectors:
        dc.l    kd_open              ; -6
        dc.l    kd_close             ; -12
        dc.l    kd_null              ; -18 Expunge
        dc.l    kd_null              ; -24
        dc.l    kd_beginio           ; -30
        dc.l    kd_abortio           ; -36
        dc.l    -1
kbddev_datatab:
        dc.w    $E000,LN_TYPE,(NT_DEVICE<<8)
        dc.w    $D000,LIB_VERSION,34
        dc.b    0
        EVEN

; Keypad keys carrying IEQUALIFIER_NUMERICPAD (public raw codes $0F, $1D-$1F, $2D-$2F, $3C-$3F, $43, $4A):
; bit (code & 7) of byte (code >> 3).
kd_numpad:
        dc.b    $00,$80,$00,$E0,$00,$E0,$00,$F0,$08,$04,$00,$00,$00,$00,$00,$00

; initFunc (d0 = base): name, lists (base zeroed by MakeLibrary); publishes the base for kbd_devevent.
kbddev_initfunc:
        move.l  d0,a1
        lea     kbddev_name(pc),a0
        move.l  a0,LN_NAME(a1)
        lea     KD_READQ(a1),a0
        bsr.s   kd_newlist
        lea     KD_RESETQ(a1),a0
        bsr.s   kd_newlist
        move.l  a1,KBD_DEVBASE
        rts

kd_newlist:
        move.l  a0,8(a0)             ; lh_TailPred
        clr.l   4(a0)                ; lh_Tail
        addq.l  #4,a0
        move.l  a0,-4(a0)            ; lh_Head = &lh_Tail
        rts

; Open: single unit, unit number and flags ignored, always succeeds.
kd_open:
        lea     KD_READQ(a6),a0
        move.l  a0,IO_UNIT(a1)
        addq.w  #1,LIB_OPENCNT(a6)
        clr.b   IO_ERROR(a1)
        rts
kd_close:
        clr.l   IO_UNIT(a1)
        clr.l   IO_DEVICE(a1)
        subq.w  #1,LIB_OPENCNT(a6)
kd_null:
        moveq   #0,d0
        rts

; kd_dis / kd_ena: inline Disable/Enable (exec/ables.i), usable from the keyboard interrupt. Preserve everything.
kd_dis:
        move.l  a0,-(sp)
        move.l  ($4).w,a0
        move.w  #INTF_INTEN,INTENA
        addq.b  #1,EB_IDNEST(a0)
        move.l  (sp)+,a0
        rts
kd_ena:
        move.l  a0,-(sp)
        move.l  ($4).w,a0
        subq.b  #1,EB_IDNEST(a0)
        bge.s   .ke_ret
        move.w  #INTF_SETCLR|INTF_INTEN,INTENA
.ke_ret:
        move.l  (sp)+,a0
        rts

; kd_term(ioreq a1, error d0.b): io_Error, ReplyMsg unless IOF_QUICK. The request is no longer queued.
; Clobbers d0/d1/a0/a1.
kd_term:
        move.b  d0,IO_ERROR(a1)
        btst    #0,IO_FLAGS(a1)
        bne.s   .kt_ret
        move.l  a6,-(sp)
        move.l  ($4).w,a6
        jsr     LVO_REPLYMSG(a6)
        move.l  (sp)+,a6
.kt_ret:
        rts

; kd_unlink(ioreq a1): Remove from the queue. Clobbers a0, preserves a1.
kd_unlink:
        move.l  (a1),a0
        move.l  a1,-(sp)
        move.l  LN_PRED(a1),a1
        move.l  a0,(a1)
        move.l  a1,LN_PRED(a0)
        move.l  (sp)+,a1
        rts

; BeginIO(ioreq a1, device a6): io_Command >= 14 is CMD_INVALID. KBD_READEVENT is queued, the others are
; completed at once. Preserves d2-d7/a2-a6.
kd_beginio:
        movem.l d2-d3/a2-a3,-(sp)
        move.l  a6,a2
        and.b   #$0F,IO_FLAGS(a1)
        clr.b   IO_ERROR(a1)
        move.b  #NT_MESSAGE,LN_TYPE(a1)
        moveq   #0,d0
        move.w  IO_COMMAND(a1),d0
        cmp.w   #KD_NCMDS,d0
        blo.s   .kb_cmd
        moveq   #0,d0
.kb_cmd:
        add.w   d0,d0
        move.w  kd_cmdtab(pc,d0.w),d0
        jsr     kd_cmdtab(pc,d0.w)
        movem.l (sp)+,d2-d3/a2-a3
        rts
kd_cmdtab:
        dc.w    kd_nocmd-kd_cmdtab   ; 0 CMD_INVALID
        dc.w    kd_reset-kd_cmdtab   ; 1 CMD_RESET
        dc.w    kd_nocmd-kd_cmdtab   ; 2 CMD_READ (no CMD_READ: KBD_READEVENT only)
        dc.w    kd_nocmd-kd_cmdtab   ; 3 CMD_WRITE
        dc.w    kd_nocmd-kd_cmdtab   ; 4 CMD_UPDATE
        dc.w    kd_clear-kd_cmdtab   ; 5 CMD_CLEAR
        dc.w    kd_stop-kd_cmdtab    ; 6 CMD_STOP
        dc.w    kd_start-kd_cmdtab   ; 7 CMD_START
        dc.w    kd_flushcmd-kd_cmdtab ; 8 CMD_FLUSH
        dc.w    kd_readevent-kd_cmdtab ; 9 KBD_READEVENT
        dc.w    kd_matrix-kd_cmdtab  ; 10 KBD_READMATRIX
        dc.w    kd_addrh-kd_cmdtab   ; 11 KBD_ADDRESETHANDLER
        dc.w    kd_remrh-kd_cmdtab   ; 12 KBD_REMRESETHANDLER
        dc.w    kd_rhdone-kd_cmdtab  ; 13 KBD_RESETHANDLERDONE

kd_nocmd:
        moveq   #IOERR_NOCMD,d0
        bra    kd_term
kd_badlen:
        moveq   #IOERR_BADLEN3,d0
        bra    kd_term
kd_ok:
        moveq   #0,d0
        bra    kd_term

kd_clear:
        bsr    kd_dis
        clr.l   KD_RD(a2)            ; KD_RD + KD_WR
        bsr    kd_ena
        bra    kd_ok
kd_stop:
        st      KD_STOP(a2)
        bra    kd_ok
kd_start:
        bsr    kd_dostart
        bra    kd_ok
kd_dostart:                          ; clears the stop flag and serves the head request. Preserves a1.
        move.l  a1,-(sp)
        bsr    kd_dis
        clr.b   KD_STOP(a2)
        bsr     kd_serve
        bsr    kd_ena
        move.l  (sp)+,a1
        rts
kd_flushcmd:
        bsr    kd_flush
        bra    kd_ok
; kd_flush: every queued KBD_READEVENT terminated with IOERR_ABORTED. Preserves a1.
kd_flush:
        move.l  a1,a3
        bsr    kd_dis
.kf_lp:
        move.l  KD_READQ(a2),a1
        tst.l   (a1)
        beq.s   .kf_done
        bsr    kd_unlink
        moveq   #IOERR_ABORTED,d0
        bsr     kd_term
        bra.s   .kf_lp
.kf_done:
        bsr    kd_ena
        move.l  a3,a1
        rts
; CMD_RESET: stop, handshake pulse on KDAT (CIA-A CRA SPMODE output) while the queue is flushed, then start. The
; ring, the matrix and the qualifiers are kept.
kd_reset:
        st      KD_STOP(a2)
        moveq   #0,d0
        move.b  d0,CIAA_CRA_K
        move.b  d0,CIAA_CRA_K
        move.b  #$40,CIAA_CRA_K
        bsr    kd_flush
        moveq   #0,d0
        move.b  d0,CIAA_CRA_K
        bsr    kd_dostart
        bra    kd_ok

kd_readevent:
        cmp.l   #IE_SIZEOF,IO_LENGTH3(a1)
        blo   kd_badlen
        bsr    kd_dis
        lea     KD_READQ(a2),a0      ; AddTail(queue, request)
        move.l  LH_TAILPRED(a0),d0
        move.l  a1,LH_TAILPRED(a0)
        addq.l  #LH_TAIL,a0
        move.l  a0,(a1)
        move.l  d0,LN_PRED(a1)
        move.l  d0,a0
        move.l  a1,(a0)
        cmp.l   KD_READQ(a2),a1      ; head of the queue and unit running: serve it now
        bne.s   .kr_wait
        tst.b   KD_STOP(a2)
        bne.s   .kr_wait
        bsr     kd_serve
        bra     kd_ena
.kr_wait:
        bclr    #0,IO_FLAGS(a1)      ; IOF_QUICK: replied later
        bra     kd_ena

kd_matrix:
        cmp.l   #KD_MATRIXSIZE,IO_LENGTH3(a1)
        bne   kd_badlen
        lea     KD_MATRIX(a2),a0
        move.l  IO_DATA3(a1),a3
        moveq   #KD_MATRIXSIZE-1,d0
.km_cp:
        move.b  (a0)+,(a3)+
        dbra    d0,.km_cp
        moveq   #KD_MATRIXSIZE,d0
        move.l  d0,IO_ACTUAL3(a1)
        bra     kd_ok

kd_addrh:
        move.l  a1,a3
        move.l  a6,-(sp)
        move.l  ($4).w,a6
        lea     KD_RESETQ(a2),a0
        move.l  IO_DATA3(a3),a1
        jsr     LVO_ENQUEUE(a6)
        move.l  (sp)+,a6
        move.l  a3,a1
        bra     kd_ok
kd_remrh:
        move.l  a1,a3
        move.l  a6,-(sp)
        move.l  ($4).w,a6
        move.l  IO_DATA3(a3),a1
        jsr     LVO_REMOVE(a6)
        move.l  (sp)+,a6
        move.l  a3,a1
        bra     kd_ok
; KBD_RESETHANDLERDONE: one handler fewer, unconditionally; the last one ends the reset handshake (KDAT released).
kd_rhdone:
        subq.w  #1,KD_RHCNT(a2)
        bne     kd_ok
        move.b  CIAA_CRA_K,d0
        and.b   #$BF,d0
        move.b  d0,CIAA_CRA_K
        bra     kd_ok

; AbortIO(ioreq a1, device a6): a KBD_READEVENT still queued is removed and terminated with IOERR_ABORTED.
kd_abortio:
        bsr     kd_dis
        move.l  KD_READQ(a6),a0
.ka_lp:
        tst.l   (a0)
        beq.s   .ka_out              ; end of list: already terminated
        cmp.l   a0,a1
        beq.s   .ka_hit
        move.l  (a0),a0
        bra.s   .ka_lp
.ka_hit:
        bsr     kd_unlink
        moveq   #IOERR_ABORTED,d0
        bsr     kd_term
.ka_out:
        bsr     kd_ena
        moveq   #0,d0
        rts

; kd_serve(device a2): caller holds Disable. While a request is queued: empty ring -> it stays queued (IOF_QUICK
; cleared); otherwise as many events as io_Length holds (oldest first, chained by ie_NextEvent), io_Actual in
; bytes, replied, and the next request is served the same way. Preserves d2-d7/a2-a6.
kd_serve:
        movem.l d2-d4/a3,-(sp)
.ks_next:
        move.l  KD_READQ(a2),a1
        tst.l   (a1)
        beq   .ks_ret
        move.w  KD_RD(a2),d0
        cmp.w   KD_WR(a2),d0
        bne.s   .ks_copy
        bclr    #0,IO_FLAGS(a1)
        bra   .ks_ret
.ks_copy:
        move.l  IO_LENGTH3(a1),d2
        cmp.l   #IE_SIZEOF*32,d2     ; the ring never holds more (keeps divu in range)
        bls.s   .ks_div
        move.l  #IE_SIZEOF*32,d2
.ks_div:
        divu    #IE_SIZEOF,d2        ; d2.w = capacity (>= 1: io_Length >= 22 checked by BeginIO)
        move.l  IO_DATA3(a1),a3
        moveq   #0,d3                ; d3 = bytes written
.ks_ev:
        move.w  KD_RD(a2),d0
        cmp.w   KD_WR(a2),d0
        beq.s   .ks_end
        tst.w   d2
        beq.s   .ks_end
        lea     KD_BUF(a2,d0.w),a0
        lea     IE_SIZEOF(a3),a1
        move.l  a1,IE_NEXTEVENT(a3)
        move.b  #IECLASS_RAWKEY,IE_CLASS(a3)
        clr.b   IE_SUBCLASS(a3)
        move.w  (a0)+,IE_CODE(a3)
        move.w  (a0),IE_QUALIFIER(a3)
        clr.l   IE_X(a3)             ; ie_X / ie_Y
        clr.l   IE_TIMESTAMP(a3)
        clr.l   IE_TIMESTAMP+4(a3)
        addq.w  #4,d0
        and.w   #KD_BMASK,d0
        move.w  d0,KD_RD(a2)
        move.l  a3,d4                ; d4 = last event written
        move.l  a1,a3
        add.l   #IE_SIZEOF,d3
        subq.w  #1,d2
        bra.s   .ks_ev
.ks_end:
        move.l  d4,a0
        clr.l   IE_NEXTEVENT(a0)
        move.l  KD_READQ(a2),a1
        move.l  d3,IO_ACTUAL3(a1)
        bsr     kd_unlink
        moveq   #0,d0
        bsr     kd_term
        bra   .ks_next
.ks_ret:
        movem.l (sp)+,d2-d4/a3
        rts

; kbd_devevent(d0.b = raw keycode, bit 7 = released): called by kbd_interrupt (CIA-A interrupt). Matrix (keys
; $00-$67 only), then the ring entry (code, qualifiers = matrix row $60-$67 + NUMERICPAD for keypad keys); a full
; ring turns its newest entry into the overflow code. Then the queue is served unless stopped.
; Preserves all registers.
kbd_devevent:
        movem.l d0-d2/a0-a2,-(sp)
        move.l  KBD_DEVBASE,d1
        beq   .ke_out
        move.l  d1,a2
        bsr     kd_dis
        moveq   #0,d2
        move.b  d0,d2                ; d2 = raw code word
        moveq   #$7F,d1
        and.w   d2,d1                ; d1 = key number
        cmp.w   #KD_LASTKEY,d1
        bhi.s   .ke_qual
        move.w  d1,d0
        lsr.w   #3,d0                ; matrix byte
        btst    #7,d2
        bne.s   .ke_up
        bset    d1,KD_MATRIX(a2,d0.w)  ; bset on memory: bit number modulo 8
        bra.s   .ke_qual
.ke_up:
        bclr    d1,KD_MATRIX(a2,d0.w)
.ke_qual:
        swap    d2
        moveq   #0,d0
        move.b  KD_MATRIX+KD_QUALBYTE(a2),d0
        move.w  d0,d2                ; d2 = (code << 16) | qualifiers
        move.w  d1,d0
        lsr.w   #3,d0
        lea     kd_numpad(pc),a0
        btst    d1,0(a0,d0.w)
        beq.s   .ke_store
        or.w    #IEQUAL_NUMPAD,d2
.ke_store:
        move.w  KD_WR(a2),d0
        move.w  d0,d1
        addq.w  #4,d1
        and.w   #KD_BMASK,d1
        cmp.w   KD_RD(a2),d1
        beq.s   .ke_full
        move.l  d2,KD_BUF(a2,d0.w)
        move.w  d1,KD_WR(a2)
        bra.s   .ke_serve
.ke_full:
        subq.w  #4,d0
        and.w   #KD_BMASK,d0
        move.w  #KD_OVERFLOW,KD_BUF(a2,d0.w)
        clr.w   d1
        move.b  KD_MATRIX+KD_QUALBYTE(a2),d1
        move.w  d1,KD_BUF+2(a2,d0.w)
.ke_serve:
        tst.b   KD_STOP(a2)
        bne.s   .ke_ena
        bsr     kd_serve
.ke_ena:
        bsr     kd_ena
.ke_out:
        movem.l (sp)+,d0-d2/a0-a2
        rts
kbddev_end:
