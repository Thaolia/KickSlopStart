; src/dos/feeder.s - keyboard feeder -> input.device (integration F, item 1).
;
; Process (proc_create) that DRAINS the RAW keyboard ring (KBD_FEEDRING, filled by kbd_interrupt at the same point
; as the cooked push) and injects each keystroke as a RAWKEY InputEvent into input.device via IND_WRITEEVENT ->
; input.device becomes the SINGLE keyboard SOURCE; its handlers (console.device) do the cooking. The task wakes on a
; keystroke (the keyboard interrupt signals it) or a deadline (timer.device VBLANK: the next IECLASS_TIMER or key
; repeat), never on every frame: a frame-rate wake-up delayed every WaitTOF caller of lower priority. Role of the 1.3
; input.device task (spec docs/analysis/intuiticks-repeat-v34.md): an IECLASS_TIMER event every 5 frames (10 per second) and the
; auto-repeat of the last key pressed (input.device delay and period, IND_SETTHRESH/SETPERIOD).
;
; SELF-TEST (ifeq SHELL_ON_SCREEN, item 1): after injecting the 1st keystroke, reads console.device CMD_READ (which
; its handler has cooked) and emits "FEEDER OK=<char>" on serial (proves keyboard -> feeder -> input.device -> console).
; When SHELL_ON_SCREEN=1 (item 2), no self-test: the shell (via the screen handler) consumes console.device.
; IMPLEMENTATION track ("clean"): input.device/timer.device + exec AutoDocs. NO ROM reading.

                include "exec.i"
                include "dospkt.i"

                xdef    feeder_main
                xref    ser_lock             ; exec/boot.s (atomic serial output)
                xref    ser_unlock
                xref    kbd_pushcooked       ; exec/keyboard.s (cooked character to the CLI ring)
                xref    kd_numpad            ; exec/kbddev.s (keypad raw codes)

IO_DATA2     EQU 40               ; IOStdReq io_Data (local: feeder.s does not include disk.i)
IO_LENGTH    EQU 36               ; IOStdReq io_Length
IO_ACTUAL    EQU 32               ; IOStdReq io_Actual
CMD_READ     EQU 2                ; console.device CMD_READ
FD_NOREPEAT  EQU $FFFF            ; FD_RPTCODE: no repeat
TICK_FRAMES  EQU 5                ; IECLASS_TIMER every 5 frames (100 ms in PAL)
KEY_NOREPEAT EQU $60              ; codes >= $60 (qualifiers): never repeated, they stop the repeat

; state block (AllocMem)
FD_INPUT   EQU 0                  ; APTR base input.device
FD_CON     EQU 4                  ; APTR console.device base (self-test)
FD_TBASE   EQU 8                  ; APTR base timer.device
FD_RPORT   EQU 12                 ; APTR reply MsgPort
FD_TREQ    EQU 16                 ; APTR timerequest
FD_SIGMASK EQU 20                 ; LONG signal mask of the reply port
FD_DONE    EQU 24                 ; BYTE self-test emitted
FD_TPEND   EQU 25                 ; BYTE timer request in flight
FD_IOREQ   EQU 28                 ; IOStdReq (48) for input BeginIO
FD_EVENT   EQU 76                 ; InputEvent (22)
FD_RDBUF   EQU 100                ; 4 bytes: console read buffer (self-test)
FD_REVENT  EQU 104                ; InputEvent (22): repeating key (qualifier | IEQUALIFIER_REPEAT)
FD_RPTCODE EQU 126                ; WORD: code of the repeating key ($FFFF: none)
FD_RPTDUE  EQU 128                ; LONG: frame (VBL_COUNT) of the next repeat
FD_TICKDUE EQU 132                ; LONG: frame of the next IECLASS_TIMER
FD_GSTREQ  EQU 136                ; timerequest (40): TR_GETSYSTIME for the timestamp
FD_PREV    EQU 176                ; 4 bytes: Prev1DownCode/Qual, Prev2DownCode/Qual (dead keys)
FD_SIZE    EQU 180

feeder_main:
                move.l  ($4).w,a6
                move.l  #FD_SIZE,d0
                move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
                jsr     LVO_ALLOCMEM(a6)
                tst.l   d0
                beq     .fm_idle             ; no RAM -> idle
                move.l  d0,a5                ; a5 = state (persistent)
                lea     EB_DEVICELIST(a6),a0 ; input.device
                lea     fd_inputname(pc),a1
                jsr     LVO_FINDNAME(a6)
                move.l  d0,FD_INPUT(a5)
                beq     .fm_idle
                lea     EB_DEVICELIST(a6),a0 ; console.device
                lea     fd_conname(pc),a1
                jsr     LVO_FINDNAME(a6)
                move.l  d0,FD_CON(a5)
                ; --- set up timer.device MICROHZ (COOP poll) ---
                lea     EB_DEVICELIST(a6),a0
                lea     fd_timername(pc),a1
                jsr     LVO_FINDNAME(a6)
                tst.l   d0
                beq     .fm_idle
                move.l  d0,FD_TBASE(a5)
                moveq   #-1,d0               ; AllocSignal
                jsr     LVO_ALLOCSIGNAL(a6)
                moveq   #1,d1
                lsl.l   d0,d1
                move.l  d1,FD_SIGMASK(a5)
                move.l  d0,d3                ; d3 = bit number
                move.l  #MP_SIZE,d0          ; reply port
                move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
                jsr     LVO_ALLOCMEM(a6)
                tst.l   d0
                beq     .fm_idle
                move.l  d0,FD_RPORT(a5)
                move.l  d0,a3
                move.b  #NT_MSGPORT,LN_TYPE(a3)
                move.b  #PA_SIGNAL,MP_FLAGS(a3)
                move.b  d3,MP_SIGBIT(a3)
                move.l  EB_THISTASK(a6),MP_SIGTASK(a3)
                lea     MP_MSGLIST(a3),a1    ; NEWLIST inline
                move.l  a1,d0
                addq.l  #4,d0
                move.l  d0,(a1)
                clr.l   4(a1)
                move.l  a1,8(a1)
                move.l  #TR_SIZE,d0          ; timerequest
                move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
                jsr     LVO_ALLOCMEM(a6)
                tst.l   d0
                beq     .fm_idle
                move.l  d0,FD_TREQ(a5)
                move.l  d0,a1
                move.l  FD_RPORT(a5),MN_REPLYPORT(a1)
                move.l  FD_TBASE(a5),IO_DEVICE(a1)
                move.l  #UNIT_VBLANK,IO_UNIT(a1)
                lea     FD_GSTREQ(a5),a1
                move.l  FD_TBASE(a5),IO_DEVICE(a1)
                move.w  #FD_NOREPEAT,FD_RPTCODE(a5)
                moveq   #-1,d0               ; keyboard signal, published for the keyboard interrupt (mask first)
                jsr     LVO_ALLOCSIGNAL(a6)
                moveq   #1,d1
                lsl.l   d0,d1
                move.l  d1,FEED_KMASK
                move.l  EB_THISTASK(a6),FEED_KTASK
.fm_loop:
                bsr     fd_poll_wait         ; keystroke or deadline
                bsr     fd_timed             ; IECLASS_TIMER tick and due repeat
.fm_drain:
                move.w  KBD_FHEAD,d2
                cmp.w   KBD_FTAIL,d2
                beq.s   .fm_loop             ; ring empty -> next frame
                lea     KBD_FEEDRING,a0
                move.w  0(a0,d2.w),d4        ; d4 = (qual<<8)|keycode
                addq.w  #2,d2
                and.w   #KBD_FRMASK,d2
                move.w  d2,KBD_FHEAD         ; advance HEAD (consumed)
                ; build the RAWKEY InputEvent
                lea     FD_EVENT(a5),a1
                clr.l   IE_NEXTEVENT(a1)
                move.b  #IECLASS_RAWKEY,IE_CLASS(a1)
                move.b  d4,IE_CODE+1(a1)     ; keycode (low byte of the ie_Code word)
                clr.b   IE_CODE(a1)
                moveq   #0,d0
                move.w  d4,d0
                lsr.w   #8,d0                ; qualifiers
                move.w  d0,IE_QUALIFIER(a1)
                moveq   #$7F,d1              ; keypad key: IEQUALIFIER_NUMERICPAD, as keyboard.device gives it
                and.b   d4,d1
                move.w  d1,d0
                lsr.w   #3,d0
                lea     kd_numpad,a0
                btst    d1,0(a0,d0.w)
                beq.s   .fm_nopad
                or.w    #$0100,IE_QUALIFIER(a1)
.fm_nopad:
                bsr     fd_stamp
                bsr     fd_history
                bsr     fd_repeat_key        ; arm / stop the repeat according to this keystroke
                lea     FD_EVENT(a5),a0
                bsr     fd_write
                ifeq    SHELL_ON_SCREEN|PROD     ; the self-test steals a byte of the first key typed: dev ROM only
                bsr     fd_selftest          ; item 1: emit "FEEDER OK=<char>" once (reads console.device)
                endc
                bra.s   .fm_drain
.fm_idle:
                move.l  ($4).w,a6            ; setup failed: sleep on a signal that never arrives (COOP, does not spin)
.fm_idle_lp:
                moveq   #0,d0
                jsr     LVO_WAIT(a6)
                bra.s   .fm_idle_lp

; fd_write(a0 = InputEvent): IND_WRITEEVENT to input.device. a5 = state, a6 = SysBase. Preserves a5/a6.
fd_write:
                ifeq    FEEDER_NO_WRITEEVENT
                movem.l a2-a3,-(sp)
                lea     FD_IOREQ(a5),a3
                move.l  FD_INPUT(a5),IO_DEVICE(a3)
                move.w  #IND_WRITEEVENT,IO_COMMAND(a3)
                move.l  a0,IO_DATA2(a3)
                move.l  FD_INPUT(a5),a6
                move.l  a3,a1
                move.b  #IOF_QUICK,IO_FLAGS(a1)
                jsr     -30(a6)              ; input BeginIO (IND_WRITEEVENT)
                move.l  ($4).w,a6
                movem.l (sp)+,a2-a3
                endc                         ; RED FEEDER_NO_WRITEEVENT: injects nothing into input.device
                rts

; fd_stamp(a1 = InputEvent): ie_TimeStamp = system time (timer.device TR_GETSYSTIME, synchronous). Preserves a1/a5/a6.
fd_stamp:
                movem.l a1-a2/a6,-(sp)
                move.l  a1,a2
                lea     FD_GSTREQ(a5),a1
                move.w  #TR_GETSYSTIME,IO_COMMAND(a1)
                move.b  #IOF_QUICK,IO_FLAGS(a1)
                move.l  FD_TBASE(a5),a6
                jsr     TD_BEGINIO(a6)
                lea     FD_GSTREQ(a5),a1
                move.l  TV_SECS(a1),IE_TIMESTAMP(a2)
                move.l  TV_MICRO(a1),IE_TIMESTAMP+4(a2)
                movem.l (sp)+,a1-a2/a6
                rts

; fd_rate(a6 = SysBase) -> d0 = frames per second (VBlankFrequency, 0 counting as 60), d1 = frame period in us,
; rounded, as UNIT_VBLANK uses them (timer-v34 §3).
fd_rate:
                moveq   #0,d0
                move.b  EB_VBLANKFREQ(a6),d0
                bne.s   .ra_f
                moveq   #60,d0
.ra_f:
                move.l  d0,d1
                lsr.w   #1,d1
                add.l   #1000000,d1
                divu    d0,d1
                and.l   #$FFFF,d1
                rts

; fd_frames(a0 = timeval, a6 = SysBase) -> d0 = number of frames: max(1, seconds x rate + ceil(us / period)), like
; UNIT_VBLANK. Clobbers d1.
fd_frames:
                move.l  d2,-(sp)
                bsr.s   fd_rate
                mulu    2(a0),d0
                move.l  4(a0),d2
                beq.s   .fr_min
                subq.l  #1,d2
                divu    d1,d2
                and.l   #$FFFF,d2
                addq.l  #1,d2
                add.l   d2,d0
.fr_min:
                tst.l   d0
                bne.s   .fr_r
                moveq   #1,d0
.fr_r:
                move.l  (sp)+,d2
                rts

; fd_repeat_key(a1 = RAWKEY event of the keystroke): press of a key < $60 -> it becomes the repeating
; key (copy with IEQUALIFIER_REPEAT, 1st repeat after the delay); press of a qualifier (>= $60) ->
; stop; release of the repeating key, or different qualifier (masks $05FF / $07FF) -> stop.
; a5 = state. Preserves a1/a5/a6.
; fd_history(a1 = RAWKEY event, a5): dead-key history (intuiticks-repeat §2.1): a press of a code below $60 carries
; in ie_X/ie_Y the two previous such presses (code, low byte of the qualifier) and becomes the newest of them; other
; events carry 0. Clobbers d0/d1.
fd_history:
                clr.l   IE_X(a1)
                move.w  IE_CODE(a1),d0
                cmp.w   #KEY_NOREPEAT,d0     ; (a release has bit 7 set: above $60 too)
                bhs.s   .hi_ret
                move.l  FD_PREV(a5),IE_X(a1)
                lsl.w   #8,d0
                move.b  IE_QUALIFIER+1(a1),d0
                move.w  FD_PREV(a5),d1
                move.w  d1,FD_PREV+2(a5)
                move.w  d0,FD_PREV(a5)
.hi_ret:
                rts

fd_repeat_key:
                move.w  IE_CODE(a1),d0
                bclr    #7,d0
                bne.s   .rk_up
                cmp.w   #KEY_NOREPEAT,d0
                bhs.s   .rk_stop
                move.w  d0,FD_RPTCODE(a5)
                lea     FD_REVENT(a5),a0
                moveq   #IE_SIZEOF/2-1,d1
                move.l  a1,-(sp)
.rk_cp:
                move.w  (a1)+,(a0)+
                dbra    d1,.rk_cp
                move.l  (sp)+,a1
                or.w    #IEQUALIFIER_REPEAT,FD_REVENT+IE_QUALIFIER(a5)
                move.l  FD_INPUT(a5),a0
                lea     ID_THRESH(a0),a0
                bsr.s   fd_frames
                add.l   VBL_COUNT,d0
                move.l  d0,FD_RPTDUE(a5)
                rts
.rk_up:
                cmp.w   FD_RPTCODE(a5),d0
                beq.s   .rk_stop
                move.w  FD_REVENT+IE_QUALIFIER(a5),d0
                and.w   #$05FF,d0
                move.w  IE_QUALIFIER(a1),d1
                and.w   #$07FF,d1
                cmp.w   d1,d0
                beq.s   .rk_ret
.rk_stop:
                move.w  #FD_NOREPEAT,FD_RPTCODE(a5)
.rk_ret:
                rts

; fd_timed: on every frame, IECLASS_TIMER if its deadline is reached (every TICK_FRAMES frames), then
; repeat of the held key if its deadline is reached (re-armed with the period). a5 = state, a6 = SysBase.
fd_timed:
                move.l  VBL_COUNT,d0
                sub.l   FD_TICKDUE(a5),d0
                bmi.s   .td_rpt
                move.l  VBL_COUNT,d0
                addq.l  #TICK_FRAMES,d0
                move.l  d0,FD_TICKDUE(a5)
                lea     FD_EVENT(a5),a1
                clr.l   IE_NEXTEVENT(a1)
                move.w  #IECLASS_TIMER<<8,IE_CLASS(a1)
                clr.l   IE_CODE(a1)          ; code and qualifier
                clr.l   IE_X(a1)
                bsr     fd_stamp
                move.l  a1,a0
                bsr     fd_write
.td_rpt:
                cmp.w   #FD_NOREPEAT,FD_RPTCODE(a5)
                beq.s   .td_ret
                move.l  VBL_COUNT,d0
                sub.l   FD_RPTDUE(a5),d0
                bmi.s   .td_ret
                move.l  FD_INPUT(a5),a0
                lea     ID_PERIOD(a0),a0
                bsr     fd_frames
                add.l   VBL_COUNT,d0
                move.l  d0,FD_RPTDUE(a5)
                lea     FD_REVENT(a5),a0     ; the template stays intact (a handler may neutralise the event
                lea     FD_EVENT(a5),a1      ; passed on, e.g. intuition to a RAWKEY window)
                moveq   #IE_SIZEOF/2-1,d0
.td_cp:
                move.w  (a0)+,(a1)+
                dbra    d0,.td_cp
                lea     FD_EVENT(a5),a1
                clr.l   IE_NEXTEVENT(a1)
                bsr     fd_stamp
                move.l  a1,a0
                bsr     fd_write
                move.w  FD_REVENT+IE_CODE(a5),d0  ; the screen CLI reads the cooked ring, not input.device: the
                move.w  FD_REVENT+IE_QUALIFIER(a5),d1 ; repeat also deposits its character there
                jsr     LVO_DISABLE(a6)      ; (two producers: the keyboard interrupt and us)
                jsr     kbd_pushcooked
                jsr     LVO_ENABLE(a6)
.td_ret:
                rts

; fd_poll_wait: sleeps until a keystroke (FEED_KMASK) or the timer request (UNIT_VBLANK) ends. Without one in flight,
; a request is sent for the frames left to the next deadline: IECLASS_TIMER, or the key repeat if it comes first.
; A keystroke leaves the request running. a5 = state, a6 = SysBase. Preserves a5.
fd_poll_wait:
                movem.l d2-d4/a0-a4,-(sp)
                tst.b   FD_TPEND(a5)
                bne.s   .pw_wait
                move.l  FD_TICKDUE(a5),d0
                cmp.w   #FD_NOREPEAT,FD_RPTCODE(a5)
                beq.s   .pw_due
                move.l  FD_RPTDUE(a5),d1
                cmp.l   d0,d1
                bge.s   .pw_due
                move.l  d1,d0
.pw_due:
                sub.l   VBL_COUNT,d0         ; d0 = frames left (at least one)
                bgt.s   .pw_n
                moveq   #1,d0
.pw_n:
                move.l  d0,d2
                bsr     fd_rate              ; frames -> seconds and microseconds at the VBlank rate
                move.l  FD_TREQ(a5),a1
                divu    d0,d2
                moveq   #0,d0
                move.w  d2,d0
                move.l  d0,TV_SECS(a1)
                swap    d2
                mulu    d1,d2
                move.l  d2,TV_MICRO(a1)
                move.w  #TR_ADDREQUEST,IO_COMMAND(a1)
                move.l  FD_TBASE(a5),a6
                jsr     TD_BEGINIO(a6)
                move.l  ($4).w,a6
                st      FD_TPEND(a5)
.pw_wait:
                move.l  FD_SIGMASK(a5),d0
                or.l    FEED_KMASK,d0
                jsr     LVO_WAIT(a6)
                move.l  FD_RPORT(a5),a0
                jsr     LVO_GETMSG(a6)
                tst.l   d0
                beq.s   .pw_ret
                sf      FD_TPEND(a5)
.pw_ret:
                movem.l (sp)+,d2-d4/a0-a4
                rts

                ifeq    SHELL_ON_SCREEN|PROD
; fd_selftest: item 1 - reads console.device CMD_READ ONCE (cooked by its handler) and emits "FEEDER OK=<char>"
; on serial. Done flag in FD_DONE. a5 = state, a6 = SysBase. Preserves a5.
fd_selftest:
                tst.b   FD_DONE(a5)
                bne.s   .st_ret
                move.l  FD_CON(a5),d0
                beq.s   .st_ret
                lea     FD_IOREQ(a5),a3      ; console CMD_READ 1 byte -> FD_RDBUF
                move.l  FD_CON(a5),IO_DEVICE(a3)
                move.w  #CMD_READ,IO_COMMAND(a3)
                lea     FD_RDBUF(a5),a0
                move.l  a0,IO_DATA2(a3)
                move.l  #1,IO_LENGTH(a3)
                clr.l   IO_ACTUAL(a3)
                clr.b   FD_RDBUF(a5)
                move.l  FD_CON(a5),a6
                move.l  a3,a1
                jsr     -30(a6)              ; console BeginIO (CMD_READ)
                move.l  ($4).w,a6
                tst.l   IO_ACTUAL(a3)
                beq.s   .st_ret              ; nothing read this tick -> retry on the next one
                st      FD_DONE(a5)          ; self-test emitted only once
                jsr     ser_lock             ; whole marker atomic (no interleaving)
                lea     fd_msg_ok(pc),a0     ; "FEEDER OK="
                bsr     fd_puts
                move.b  FD_RDBUF(a5),d0      ; the cooked char
                bsr     fd_putc
                moveq   #13,d0
                bsr     fd_putc
                moveq   #10,d0
                bsr     fd_putc
                jsr     ser_unlock
.st_ret:
                rts

; fd_puts(a0 = NUL-terminated string) / fd_putc(d0.b): bounded serial output (TBE). Clobbers d0/d1.
fd_puts:
                move.b  (a0)+,d0
                beq.s   .ps_ret
                bsr.s   fd_putc
                bra.s   fd_puts
.ps_ret:
                rts
fd_putc:                                     ; emits d0.b on serial (bounded TBE poll). Clobbers d0/d1/d2; preserves a0.
                and.w   #$00FF,d0
                or.w    #$0100,d0            ; bit stop
                move.w  #$3000,d1            ; timeout
.pc_wt:
                move.w  SERDATR,d2
                btst    #13,d2               ; TBE (transmit buffer empty) ?
                bne.s   .pc_tx
                dbra    d1,.pc_wt
                rts                          ; timeout -> give up on this character
.pc_tx:
                move.w  d0,SERDAT
                rts
fd_msg_ok:
                dc.b    "FEEDER OK=",0
                even
                endc

fd_inputname:
                dc.b    "input.device",0
fd_conname:
                dc.b    "console.device",0
fd_timername:
                dc.b    "timer.device",0
                even
