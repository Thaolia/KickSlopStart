; src/exec/keyboard.s — F2a/F2b: reception, decoding and LIVE driver of the keyboard via CIA-A.
;
; The Amiga keyboard transmits each scancode serially on the SP line of CIA-A (CNT clock). When 8 bits are
; received, CIA-A sets ICR bit 3 (SP). The raw byte in SDR is the INVERTED keycode rotated by 1 bit ->
; keycode = NOT(ROR.b #1, raw). bit 7 = up/down, bits 6-0 = key. Special power-up codes: $FD (initiate
; power-up key stream), $FE (terminate). After reading, HANDSHAKE mandatory (pulse SP as output ~75us via CRA
; bit 6) otherwise the keyboard stalls before the next byte.
;
; kbd_selftest: called VERY EARLY at boot (interrupts masked, cf. the spike that worked so) -> direct BOUNDED
; poll of CIA-A, decodes+handshakes the emulated keyboard's power-up stream, returns d0 = flags seen ($FD/$FE).
; Proves the reception+decoding+handshake path WITHOUT injector (the emulated keyboard sends its power-up sequence
; at reset). Standalone (no SysBase). Clobbers d0-d4/a0-a1. IMPLEMENTATION track: HRM (CIA/keyboard). NO ROM reading.
;
; F2b = LIVE interrupt-driven driver: kbd_install registers kbd_interrupt on ICR bit 3 (SP) via
; AddICRVector (cia.resource) + re-enables PORTS/INT2; on each received scancode, cia_dispatch (via ciaa_server,
; PORTS chain) calls kbd_interrupt which decodes, handshakes, ignores key-ups, maps keycode -> ASCII (minimal US
; keymap) and pushes into an SPSC ring (producer). con_handler (READ) drains this ring (consumer) IN ADDITION
; to the serial RBF -> the CLI can be driven from the real keyboard. Keycodes measured under FS-UAE: v=$34 e=$12
; r=$13 Return=$44 space=$40 a=$20 (bit 7 = up). Lock-free (producer advances TAIL last, consumer advances HEAD).

                include "exec.i"

                xdef    kbd_selftest
                xref    kbd_devevent     ; kbddev.s: matrix + KBD_READEVENT

CIAA_SDR     EQU $BFEC01          ; CIA-A reg $C: serial data (received scancode)
CIAA_ICR     EQU $BFED01          ; CIA-A reg $D: interrupt control (read = pending + ACK; bit 3 = SP)
CIAA_CRA     EQU $BFEE01          ; CIA-A reg $E: control A (bit 6 = SPMODE: 0 = input, 1 = output)

KBD_MAXBYTES EQU 32               ; bound: max number of bytes read (the power-up stream is short; bounds the resends)
KBD_BUDGET   EQU $00100000        ; TOTAL bound of poll iterations (~1.5 s of CIA reads): bounds the wall time
                                  ; even if the keyboard is slow/absent/stalled (no pathological boot delay)
KBD_HSDELAY  EQU $0100            ; handshake: iterations of the SPMODE pulse (~> 75 us at 7 MHz)

KBF_FD       EQU 0                ; flag: $FD (initiate power-up) seen
KBF_FE       EQU 1                ; flag: $FE (terminate power-up) seen

; kbd_selftest() -> d0 = flags (bit KBF_FD, bit KBF_FE). d0==3 (both) = power-up stream received+decoded.
kbd_selftest:
                moveq   #0,d0                ; d0 = result flags
                move.b  CIAA_CRA,d1           ; SP as INPUT (CRA bit 6 = 0)
                and.b   #$BF,d1
                move.b  d1,CIAA_CRA
                moveq   #KBD_MAXBYTES-1,d4    ; d4 = max byte counter (bound on the resends)
                move.l  #KBD_BUDGET,d2        ; TOTAL poll iteration budget (bounds the wall time, slow/absent keyboard)
.poll:
                move.b  CIAA_ICR,d1           ; read ICR (ACK); bit 3 = SP
                btst    #3,d1
                bne.s   .got
                subq.l  #1,d2
                bne.s   .poll
                bra.s   .done                 ; budget exhausted -> end (no byte / keyboard absent)
.got:
                move.b  CIAA_SDR,d3           ; raw byte received
                ror.b   #1,d3
                not.b   d3                    ; d3 = decoded keycode
                ifeq    F2A_NO_HANDSHAKE
                move.b  CIAA_CRA,d1           ; handshake: pulse SPMODE output ~75us then input
                or.b    #$40,d1
                move.b  d1,CIAA_CRA
                move.w  #KBD_HSDELAY,d1
.hs:
                dbra    d1,.hs
                move.b  CIAA_CRA,d1
                and.b   #$BF,d1
                move.b  d1,CIAA_CRA
                endc                          ; RED F2A_NO_HANDSHAKE: no handshake -> the keyboard stalls after
                                              ; 1 byte -> $FE never reached -> "F2 KBD OK" absent (isolates handshake)
                cmp.b   #$FD,d3
                bne.s   .notfd
                bset    #KBF_FD,d0
.notfd:
                cmp.b   #$FE,d3
                bne.s   .notfe
                bset    #KBF_FE,d0
                bra.s   .done                 ; $FE = terminate -> end of the power-up stream
.notfe:
                dbra    d4,.poll              ; bound resends: resume polling with the remaining budget
.done:
                rts

; ============================ F2b: LIVE keyboard driver (interrupt-driven) ============================
                xdef    kbd_install
                xdef    kbd_pushcooked
                xref    kbd_cook         ; #5: exec/keymap.s — cook keycode(+qualifiers)->ASCII (US/AZERTY)

; kbd_install() [a6=SysBase] -> d0 = 0 (ok) | !=0 (OpenResource failure). Installs the LIVE driver:
; empties the ring, SP as INPUT, AddICRVector(bit 3 = SP) -> kbd_interrupt, re-enables PORTS/INT2 (turned off after
; the M7B demo). ciaa_server (left on the PORTS chain) acknowledges the ICR and routes bit 3 to kbd_interrupt.
; Clobbers d0/d1/a0/a1 (a2/a6 preserved).
kbd_install:
                movem.l a2/a6,-(sp)
                clr.w   KBD_HEAD             ; low RAM not guaranteed zero at power-on
                clr.w   KBD_TAIL
                clr.w   KBD_FHEAD            ; feeder buffer: an odd index left by the power-on RAM caused
                clr.w   KBD_FTAIL            ; an address error on the 1st keypress (WinUAE fills RAM, FS-UAE clears it)
                clr.w   KBD_QUAL             ; #5: qualifier state
                lea     kbd_ciaa_name(pc),a1
                jsr     LVO_OPENRESOURCE(a6) ; OpenResource("ciaa.resource")
                tst.l   d0
                beq.s   .ki_fail
                move.l  d0,a2                ; a2 = ciaa.resource base
                move.b  CIAA_CRA,d0          ; SP as INPUT (b6=0) to receive
                and.b   #$BF,d0
                move.b  d0,CIAA_CRA
                move.l  a2,a6                ; a6 = resource base for AddICRVector
                moveq   #3,d0                ; CIA-A SP = ICR bit 3 (keyboard)
                lea     kbd_int(pc),a1
                jsr     CIA_ADDICRVECTOR(a6) ; -> d0 = 0 (ok) | struct occupying the bit
                move.w  #(INTF_SETCLR|INTF_PORTS),INTENA ; re-enables Paula PORTS/INT2 (turned off after M7B)
                bra.s   .ki_ret              ; d0 = AddICRVector result (0 = ok)
.ki_fail:
                moveq   #-1,d0
.ki_ret:
                movem.l (sp)+,a2/a6
                rts

; kbd_interrupt: ICR bit 3 handler (keyboard SP). Called by cia_dispatch via jsr (a5): d2/d3 (bit index +
; ICR) and a2 (resource base) are LIVE across the call -> we save/restore d0-d3/a0-a1 and touch NEITHER
; a2 NOR a6. Decodes (F2a); HANDSHAKE mandatory. #5: QUALIFIER TRACKING (shift/caps/ctrl/alt/Amiga, $60-$67)
; in KBD_QUAL, then cooking keycode(+KBD_QUAL)->ASCII via kbd_cook (US/AZERTY keymap); push into the SPSC ring
; (producer: writes the data then advances TAIL last -> consumer never ahead).
kbd_interrupt:
                movem.l d0-d3/a0-a1,-(sp)
                move.b  CIAA_SDR,d0          ; raw byte received
                ror.b   #1,d0
                not.b   d0                   ; d0.b = keycode (bit 7 = up/down)
                move.b  CIAA_CRA,d1          ; handshake: pulse SPMODE output ~75us then input
                or.b    #$40,d1
                move.b  d1,CIAA_CRA
                move.w  #KBD_HSDELAY,d1
.ki_hs:
                dbra    d1,.ki_hs
                move.b  CIAA_CRA,d1
                and.b   #$BF,d1
                move.b  d1,CIAA_CRA
                jsr     kbd_devevent         ; keyboard.device: matrix + raw event (preserves everything)
                move.b  d0,d2                ; d2 = raw (bit7=up/down)
                and.b   #$7F,d2              ; d2 = keycode
                cmp.b   #$60,d2
                blo   .ki_key              ; < $60 -> normal key
                cmp.b   #$68,d2
                bhs   .ki_out              ; >= $68: special codes, ignored
                cmp.b   #$62,d2
                beq   .ki_caps             ; $62 = CAPSLOCK (toggle)
                moveq   #0,d1                ; $60/$61 = shift L/R; $63 = ctrl
                cmp.b   #$60,d2
                bne.s   .kq1
                moveq   #$01,d1
                bra.s   .ki_qmod
.kq1:
                cmp.b   #$61,d2
                bne.s   .kq2
                moveq   #$02,d1
                bra.s   .ki_qmod
.kq2:
                moveq   #$08,d1              ; $63 = ctrl
                cmp.b   #$63,d2
                beq.s   .ki_qmod
                moveq   #$10,d1              ; $64-$67 = alt L/R, Amiga L/R: bits $10 << (code - $64)
                move.b  d2,d3                ; (IEQUALIFIER_LALT, RALT, LCOMMAND, RCOMMAND)
                sub.b   #$64,d3
                lsl.w   d3,d1
.ki_qmod:
                btst    #7,d0                ; down -> set the bit, up -> clear
                bne.s   .ki_qclr
                or.w    d1,KBD_QUAL
                bra.s   .ki_feedout
.ki_qclr:
                not.w   d1
                and.w   d1,KBD_QUAL
                bra.s   .ki_feedout
.ki_caps:
                btst    #7,d0                ; CAPS: toggle on key-down only
                bne.s   .ki_feedout
                move.w  KBD_QUAL,d1
                eori.w  #$04,d1
                move.w  d1,KBD_QUAL
                bra.s   .ki_feedout
.ki_key:
                btst    #7,d0
                bne.s   .ki_feedout          ; normal key released: for input.device only
                bsr.s   .ki_feed
                ifne    F2B_NO_FEED
                bra.s   .ki_out              ; RED F2B_NO_FEED: decodes, does NOT feed the cooked ring (isolates wiring)
                endc
                move.b  d2,d0                ; keycode
                move.w  KBD_QUAL,d1          ; current qualifiers
                bsr.s   kbd_pushcooked
                bra.s   .ki_out
.ki_feedout:
                bsr.s   .ki_feed
                bra.s   .ki_out
                ; --- every event (press, release, qualifiers) -> feeder ring: (KBD_QUAL << 8) | raw
                ; code (bit 7 = release), qualifier already up to date -> input.device gets everything, as in 1.3 ---
.ki_feed:
                move.w  KBD_FTAIL,d1
                move.w  d1,d3
                addq.w  #2,d3
                and.w   #KBD_FRMASK,d3
                cmp.w   KBD_FHEAD,d3
                beq.s   .kf_ret              ; ring full: event lost (bounded)
                move.w  d3,-(sp)
                move.w  KBD_QUAL,d3
                lsl.w   #8,d3
                move.b  d0,d3                ; d3 = (qualifiers << 8) | raw code
                lea     KBD_FEEDRING,a0
                move.w  d3,0(a0,d1.w)        ; write the entry BEFORE publishing TAIL
                move.w  (sp)+,KBD_FTAIL
.kf_ret:
                rts
.ki_out:
                movem.l (sp)+,d0-d3/a0-a1
                rts

; kbd_pushcooked(d0.b = keycode, d1.w = qualifiers): cooked character (kbd_cook) put into the ring read by the CLI
; (con_ring_get); unmapped or ring full: nothing. Two producers (keyboard interrupt, feeder repeat):
; a caller outside interrupt calls under Disable. Preserves d2-d7/a2-a6.
kbd_pushcooked:
                move.l  d2,-(sp)
                jsr     kbd_cook             ; -> d0.b = ASCII (preserves d2/a0/a1)
                tst.b   d0
                beq.s   .pc_ret              ; unmapped
                move.b  d0,d1
                move.w  KBD_TAIL,d0
                move.w  d0,d2
                addq.w  #1,d2
                and.w   #KBD_RMASK,d2
                cmp.w   KBD_HEAD,d2
                beq.s   .pc_ret              ; ring full: lost (bounded)
                lea     KBD_RING,a0
                move.b  d1,0(a0,d0.w)        ; write the data BEFORE publishing TAIL
                move.w  d2,KBD_TAIL
.pc_ret:
                move.l  (sp)+,d2
                rts

                EVEN
kbd_int:                                     ; struct Interrupt in ROM (AddICRVector only stores a pointer)
                dc.l    0                    ; LN_SUCC
                dc.l    0                    ; LN_PRED
                dc.b    2                    ; LN_TYPE = NT_INTERRUPT
                dc.b    0                    ; LN_PRI
                dc.l    0                    ; LN_NAME
                dc.l    0                    ; IS_DATA (unused: the handler reads globals + fixed addresses)
                dc.l    kbd_interrupt        ; IS_CODE
kbd_ciaa_name:
                dc.b    "ciaa.resource",0
                EVEN

