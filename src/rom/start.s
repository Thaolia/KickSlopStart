; src/rom/start.s — hello-ROM M0
;
; Goal: prove the chain vasm -> 256K image -> romtool -> emulator.
; 100% generic low-level Amiga code (publicly documented hardware
; registers, HRM) + ROM container format (amitools, open source). NO
; derivation from the analysed Kickstart ROM: this file belongs to the
; IMPLEMENTATION track ("clean").
;
; Behaviour: freezes the hardware (IRQ/DMA off), sets the background to green
; ("alive" visual signal), emits a marker on the serial port (primary
; assertion channel), then loops. Uses NEITHER stack NOR RAM: runnable as is
; at reset, before any memory/overlay configuration.
;
; Container layout, modelled on a genuine 256K Kickstart:
;   $FC0000 reset header (ROM-ID + PC vector)
;   $FC00D0 RESET instruction (magic_reset field expected by romtool)
;   $FC00D2 coldstart (reset entry point)

; --- Custom chip registers (Amiga Hardware Reference Manual) ---
CUSTOM   EQU $DFF000
DMACON   EQU CUSTOM+$096         ; write: SET/CLR + DMA channels
INTENA   EQU CUSTOM+$09A         ; write: SET/CLR + IRQ mask
INTREQ   EQU CUSTOM+$09C         ; write: SET/CLR + IRQ requests
SERDAT   EQU CUSTOM+$030         ; write: serial data + stop bit
SERPER   EQU CUSTOM+$032         ; write: serial period (baud)
SERDATR  EQU CUSTOM+$018         ; read:  bit 13 = TBE (TX buffer empty)
COLOR00  EQU CUSTOM+$180         ; write: background colour

ROMBASE  EQU $FC0000             ; base of a 256K ROM (A500 Kickstart 1.x)
COLDSTART_OFF EQU $D2            ; coldstart offset (as in a real Kickstart)
GREEN    EQU $00F0               ; 4-bit RGB: green
SERPER_9600_PAL EQU 368          ; 3546895/9600 - 1

        ORG     ROMBASE

; --- Reset header (container format, see Cloanto ROM FAQ / amitools) ---
; longword $0 (= initial reset SSP) = 0x11114EF9: harmless, we never push.
; longword $4 (= initial reset PC)  = coldstart address.
rom_header:
        dc.w    $1111            ; 256K ROM-ID word
        dc.w    $4EF9            ; JMP abs.l opcode (makes $FC0000 executable on warm reset)
        dc.l    coldstart        ; reset / JMP target (= $FC00D2)

        dcb.b   COLDSTART_OFF-2-(*-rom_header),0  ; padding up to offset $D0
        dc.w    $4E70            ; $FC00D0: RESET instruction (magic_reset)

coldstart:                        ; $FC00D2
        move.w  #$7FFF,DMACON    ; turn off all DMA
        move.w  #$7FFF,INTENA    ; mask all IRQs
        move.w  #$7FFF,INTREQ    ; acknowledge pending IRQs

        move.w  #GREEN,COLOR00   ; green background BEFORE serial: guaranteed visual signal

        move.w  #SERPER_9600_PAL,SERPER
        lea     msg(pc),a0
.emit:
        move.b  (a0)+,d0
        beq.s   freeze
.wait:
        move.w  SERDATR,d1
        btst    #13,d1           ; wait for TBE (TX buffer empty)
        beq.s   .wait
        and.w   #$00FF,d0
        or.w    #$0100,d0         ; add the stop bit
        move.w  d0,SERDAT
        bra.s   .emit

freeze:
        bra.s   freeze           ; frozen green background

msg:
        dc.b    "M0 HELLO kickstart13-reimpl alive",13,10,0
        EVEN
