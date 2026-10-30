; src/exec/gameport.s — gameport.device (hardware mouse): driver + RAWMOUSE InputEvent injector.
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
; IMPLEMENTATION track ("clean"): HRM (JOY0DAT/CIAA PRA) + NDK devices/gameport.i + inputevent.i. NO ROM reading.

                include "exec.i"

                xdef    gp_delta8
                xdef    gp_poll
                xdef    gp_vblank_server
                xdef    gp_install
                xdef    gameport_dev_name

GP_POTBITS      EQU $0C00            ; OUTLY | DATLY (port 0, pin 9 = right button)
POTGO_W         EQU CUSTOM+$034
IO_DATA2        EQU 40               ; IOStdReq io_Data (APTR) — local (avoids including disk.i)
GAMEPORT_SIZE   EQU LIB_SIZE         ; gameport.device base: Library node only (no own device state)

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

gameport_open:
        addq.w  #1,LIB_OPENCNT(a6)
        rts
gameport_close:
        subq.w  #1,LIB_OPENCNT(a6)
        moveq   #0,d0
        rts
gameport_expunge:
        moveq   #0,d0                ; resident base: no expunge
        rts
gameport_null:
        moveq   #0,d0
        rts
gameport_abortio:
        moveq   #0,d0
        rts

; gameport_beginio(device a6, ioreq a1): our gameport does NOT expose gpd commands (GPD_READEVENT...). Its
; active role is the VBlank poller that injects via IND_WRITEEVENT (feeder pattern) — just as input.device has
; no input.task. Every io command therefore gets IOERR_NOCMD (the device node exists for the ROMTag/map parity).
gameport_beginio:
        move.b  #IOERR_NOCMD,IO_ERROR(a1)
        btst    #0,IO_FLAGS(a1)      ; IOF_QUICK: the caller does not wait for a reply
        bne.s   .gb_ret
        move.l  a6,-(sp)
        move.l  ($4).w,a6
        jsr     LVO_REPLYMSG(a6)     ; SendIO + WaitIO (GPD_READEVENT, RKM pattern) must not hang
        move.l  (sp)+,a6
.gb_ret:
        rts

; initFunc (D0=base, A0=segList, A6=ExecBase) -> D0 = base. Sets the name (V34 quirk). The VBlank poller is NOT
; armed here (resident init = early): gp_install (called at system bringup) primes the state + registers the server.
gameport_initfunc:
        move.l  d0,a1
        lea     gameport_dev_name(pc),a0
        move.l  a0,LN_NAME(a1)
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

; gp_poll(d0.w = current JOY0DAT, d1.w = current CIAA_PRA | $100 if right button pressed): logical core. Computes
; dx/dy (vs GP_PREV_JOY, via gp_delta8), detects the left button edge (vs GP_PREV_BTN; PRA bit 6 active-low),
; otherwise the right button edge (vs GP_PREV_RBTN; a simultaneous right edge waits for the next poll), and if
; movement OR edge, builds a RAWMOUSE InputEvent (ie_Code = $68/$69 down, $E8/$E9 up, $FF movement; ie_X=dx
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
        beq.s   .gp_motion
        move.w  #IECODE_RBUTTON,d3
        moveq   #1,d1
        tst.b   d7
        bne.s   .gp_motion
        move.w  #(IECODE_RBUTTON|IECODE_UP_PREFIX),d3
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

; gp_vblank_server: hardware SHIM. Server on the VERTB chain (AddIntServer) -> runs every frame in the
; running system. Reads the real mouse registers and calls gp_poll. Server convention: a6=SysBase (provided),
; preserves d2-d7/a2-a4 (gp_poll guarantees it), returns Z-set (d0=0 -> "continue the chain"). Headless: static
; JOY0DAT -> gp_poll finds neither movement nor edge -> no IND_WRITEEVENT (inert, no effect on M7).
gp_vblank_server:
        addq.l  #1,GP_POLLS         ; live proof: one more poll on a REAL VBlank
        move.w  JOY0DAT,d0          ; mouse quadrature counters (hardware shim)
        moveq   #0,d1
        move.b  CIAA_PRA,d1         ; left button (bit 6, active-low)
        btst    #10-8,POTINP        ; right button (DATLY, active-low)
        bne.s   .vs_noright
        bset    #8,d1
.vs_noright:
        bsr     gp_poll
        moveq   #0,d0               ; Z-set -> call-all server: continue the VERTB chain
        rts

; gp_install(a6 = SysBase): arms the mouse poller in the running system. (1) publishes the input.device base
; (GP_INPUTBASE) for injection; (2) PRIMES GP_PREV_JOY with the CURRENT JOY0DAT reading (not 0: otherwise a
; spurious delta at the 1st frame) and GP_PREV_BTN with the current button state; (3) registers gp_vblank_server on
; the VERTB chain (AddIntServer, pri 5). Clobbers d0/d1/a0/a1 (+ whatever AddIntServer clobbers). Call with IRQs masked.
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
        lea     EB_RESOURCELIST(a6),a0 ; right button (pin 9 of port 0): OUTLY|DATLY as output at 1 (potgo.resource),
        lea     gp_potgoname(pc),a1  ; pressing pulls the line to 0 -> DATLY read as 0
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        beq.s   .gi_rawpot
        move.l  a6,-(sp)
        move.l  d0,a6
        move.l  #GP_POTBITS,d0
        jsr     -6(a6)               ; AllocPotBits
        move.l  #GP_POTBITS,d0
        move.l  #GP_POTBITS,d1
        jsr     -18(a6)              ; WritePotgo
        move.l  (sp)+,a6
        bra.s   .gi_potok
.gi_rawpot:
        move.w  #GP_POTBITS,POTGO_W
.gi_potok:
        moveq   #0,d1
        btst    #10-8,POTINP
        bne.s   .gi_rdone
        moveq   #1,d1
.gi_rdone:
        move.b  d1,GP_PREV_RBTN
        clr.l   GP_VBL_INT+LN_SUCC   ; struct Interrupt in reserved low RAM (not guaranteed zero at power-on)
        clr.l   GP_VBL_INT+IS_DATA
        move.b  #5,GP_VBL_INT+LN_PRI ; pri 5: between sched(20) and timer_vblank(0)/vbl_tail(-10) in the VERTB chain
        move.l  #gp_vblank_server,GP_VBL_INT+IS_CODE
        moveq   #INTB_VERTB,d0
        lea     GP_VBL_INT,a1
        jsr     LVO_ADDINTSERVER(a6)
        rts

gp_inputname:
        dc.b    "input.device",0
gp_potgoname:
        dc.b    "potgo.resource",0
        EVEN
gameport_end:
