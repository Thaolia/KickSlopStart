; src/exec/kbddev.s — keyboard.device: exec interface of the keyboard (raw events, matrix, reset handlers).
;
; Serial decoding stays in keyboard.s (kbd_interrupt); it hands each raw keycode (bit 7 = released) over here
; via kbd_devevent: the matrix of pressed keys is kept up to date, then the event satisfies the first
; pending KBD_READEVENT request, or is buffered (16 events) for the next one.
; Commands: CMD_CLEAR (empties the buffer), KBD_READEVENT (one IECLASS_RAWKEY InputEvent per request),
; KBD_READMATRIX (16 bytes, bit n = key n pressed), KBD_ADDRESETHANDLER / KBD_REMRESETHANDLER (list sorted
; by priority), KBD_RESETHANDLERDONE. The keyboard reset sequence (Ctrl-Amiga-Amiga) is not yet relayed
; to the handlers: the list is maintained, it is not called.
; IMPLEMENTATION track ("clean"): AutoDocs keyboard.device + devices/keyboard.i + devices/inputevent.i.
; NO ROM reading.

                include "exec.i"

                xdef    kbd_devevent

KD_MATRIX       EQU LIB_SIZE         ; 16 bytes
KD_READQ        EQU LIB_SIZE+16      ; struct List of the pending KBD_READEVENTs
KD_RESETQ       EQU KD_READQ+14      ; struct List of the reset handlers
KD_BHEAD        EQU KD_RESETQ+14     ; word: buffer head (byte offset)
KD_BTAIL        EQU KD_BHEAD+2       ; word: buffer tail
KD_BUF          EQU KD_BTAIL+2       ; 16 entries of 4 bytes: keycode.w, qualifiers.w
KD_BMASK        EQU 63
KD_SIZE         EQU KD_BUF+64

CMD_CLEAR       EQU 5
KBD_READEVENT   EQU 9
KBD_READMATRIX  EQU 10
KBD_ADDRESETHANDLER EQU 11
KBD_REMRESETHANDLER EQU 12
KBD_RESETHANDLERDONE EQU 13
KD_MATRIXSIZE   EQU 16
IO_ACTUAL3      EQU 32
IO_LENGTH3      EQU 36
IO_DATA3        EQU 40

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

; initFunc (d0 = base): name, lists, empty buffer, zeroed matrix; publishes the base for kbd_devevent.
kbddev_initfunc:
        move.l  d0,a1
        lea     kbddev_name(pc),a0
        move.l  a0,LN_NAME(a1)
        lea     KD_MATRIX(a1),a0
        moveq   #KD_MATRIXSIZE/4-1,d1
.ki_clr:
        clr.l   (a0)+
        dbra    d1,.ki_clr
        clr.l   KD_BHEAD(a1)         ; KD_BHEAD + KD_BTAIL
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

kd_open:
        addq.w  #1,LIB_OPENCNT(a6)
        clr.b   IO_ERROR(a1)
        rts
kd_close:
        subq.w  #1,LIB_OPENCNT(a6)
kd_null:
        moveq   #0,d0
        rts

; kd_fill: a1 = KBD_READEVENT, d0.l = (keycode << 16) | qualifiers -> RAWKEY InputEvent in io_Data.
kd_fill:
        move.l  IO_DATA3(a1),a0
        clr.l   (a0)                 ; ie_NextEvent
        move.b  #IECLASS_RAWKEY,IE_CLASS(a0)
        clr.b   IE_SUBCLASS(a0)
        move.w  d0,IE_QUALIFIER(a0)
        swap    d0
        move.w  d0,IE_CODE(a0)
        clr.l   IE_X(a0)             ; ie_X / ie_Y
        clr.l   IE_X+4(a0)           ; ie_TimeStamp
        clr.l   IE_X+8(a0)
        moveq   #IE_SIZEOF,d0
        move.l  d0,IO_ACTUAL3(a1)
        rts

; BeginIO(ioreq a1, device a6).
kd_beginio:
        movem.l a2/a6,-(sp)
        move.l  a6,a2
        move.l  ($4).w,a6
        clr.b   IO_ERROR(a1)
        move.w  IO_COMMAND(a1),d0
        cmp.w   #KBD_READEVENT,d0
        beq   .kb_read
        cmp.w   #KBD_READMATRIX,d0
        beq   .kb_matrix
        cmp.w   #KBD_ADDRESETHANDLER,d0
        beq   .kb_addrh
        cmp.w   #KBD_REMRESETHANDLER,d0
        beq   .kb_remrh
        cmp.w   #KBD_RESETHANDLERDONE,d0
        beq   .kb_done
        cmp.w   #CMD_CLEAR,d0
        beq   .kb_clear
        move.b  #IOERR_NOCMD,IO_ERROR(a1)
        bra   .kb_done
.kb_read:
        jsr     LVO_DISABLE(a6)
        move.w  KD_BHEAD(a2),d1
        cmp.w   KD_BTAIL(a2),d1
        beq   .kb_wait
        move.l  KD_BUF(a2,d1.w),d0
        addq.w  #4,d1
        and.w   #KD_BMASK,d1
        move.w  d1,KD_BHEAD(a2)
        move.l  a1,-(sp)
        jsr     LVO_ENABLE(a6)
        move.l  (sp)+,a1
        bsr     kd_fill
        bra   .kb_done
.kb_wait:
        bclr    #0,IO_FLAGS(a1)      ; IOF_QUICK: the request will be returned by ReplyMsg
        lea     KD_READQ(a2),a0
        jsr     LVO_ADDTAIL(a6)
        jsr     LVO_ENABLE(a6)
        bra   .kb_ret
.kb_matrix:
        move.l  IO_LENGTH3(a1),d0
        moveq   #KD_MATRIXSIZE,d1
        cmp.l   d1,d0
        bls.s   .kb_mlen
        move.l  d1,d0
.kb_mlen:
        move.l  d0,IO_ACTUAL3(a1)
        lea     KD_MATRIX(a2),a0
        move.l  a1,-(sp)
        move.l  IO_DATA3(a1),a1
        bra   .kb_mnext
.kb_mcp:
        move.b  (a0)+,(a1)+
.kb_mnext:
        dbra    d0,.kb_mcp
        move.l  (sp)+,a1
        bra   .kb_done
.kb_addrh:
        move.l  a1,-(sp)
        lea     KD_RESETQ(a2),a0
        move.l  IO_DATA3(a1),a1
        jsr     LVO_ENQUEUE(a6)
        move.l  (sp)+,a1
        bra   .kb_done
.kb_remrh:
        move.l  a1,-(sp)
        move.l  IO_DATA3(a1),a1
        jsr     LVO_REMOVE(a6)
        move.l  (sp)+,a1
        bra   .kb_done
.kb_clear:
        move.w  KD_BTAIL(a2),KD_BHEAD(a2)
.kb_done:
        btst    #0,IO_FLAGS(a1)
        bne   .kb_ret
        jsr     LVO_REPLYMSG(a6)
.kb_ret:
        movem.l (sp)+,a2/a6
        rts

; AbortIO(ioreq a1, device a6): a KBD_READEVENT still pending is removed and returned with IOERR_ABORTED.
kd_abortio:
        movem.l a2/a6,-(sp)
        move.l  a6,a2
        move.l  ($4).w,a6
        jsr     LVO_DISABLE(a6)
        move.l  KD_READQ(a2),a0
.ka_lp:
        tst.l   (a0)
        beq.s   .ka_out              ; end of list: already served
        cmp.l   a0,a1
        beq.s   .ka_hit
        move.l  (a0),a0
        bra.s   .ka_lp
.ka_hit:
        move.l  a1,-(sp)
        jsr     LVO_REMOVE(a6)
        move.l  (sp)+,a1
        move.b  #IOERR_ABORTED,IO_ERROR(a1)
        jsr     LVO_REPLYMSG(a6)
.ka_out:
        jsr     LVO_ENABLE(a6)
        moveq   #0,d0
        movem.l (sp)+,a2/a6
        rts

; kbd_devevent(d0.b = raw keycode, bit 7 = released): called by kbd_interrupt (CIA-A interrupt).
; Preserves all registers.
kbd_devevent:
        movem.l d0-d2/a0-a2/a6,-(sp)
        move.l  KBD_DEVBASE,d1
        beq.s   .ke_out
        move.l  d1,a2
        moveq   #0,d2
        move.b  d0,d2
        moveq   #$7F,d1
        and.w   d2,d1                ; d1 = key number
        move.w  d1,d0
        lsr.w   #3,d0                ; matrix byte
        btst    #7,d2
        bne.s   .ke_up
        bset    d1,KD_MATRIX(a2,d0.w)  ; bset on memory: bit number modulo 8
        bra.s   .ke_ev
.ke_up:
        bclr    d1,KD_MATRIX(a2,d0.w)
.ke_ev:
        swap    d2
        move.w  KBD_QUAL,d2          ; d2 = (keycode << 16) | qualifiers
        move.l  ($4).w,a6
        lea     KD_READQ(a2),a0
        jsr     LVO_REMHEAD(a6)
        tst.l   d0
        beq.s   .ke_buf
        move.l  d0,a1
        move.l  d2,d0
        bsr     kd_fill
        jsr     LVO_REPLYMSG(a6)
        bra.s   .ke_out
.ke_buf:
        move.w  KD_BTAIL(a2),d0
        move.w  d0,d1
        addq.w  #4,d1
        and.w   #KD_BMASK,d1
        cmp.w   KD_BHEAD(a2),d1
        beq.s   .ke_out              ; buffer full: the event is lost
        move.l  d2,KD_BUF(a2,d0.w)
        move.w  d1,KD_BTAIL(a2)
.ke_out:
        movem.l (sp)+,d0-d2/a0-a2/a6
        rts
kbddev_end:
