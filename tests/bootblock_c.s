; tests/bootblock_c.s - CUSTOM boot code for milestone C "it boots!" (TEST ASSET, NOT ROM code).
; Assembled as a raw binary (vasm -Fbin -m68000) and placed at offset +12 of a test ADF's bootblock
; (see tests/mk_boot_adf.sh). Proves that the strap READ + VALIDATED + EXECUTED the bootblock: emits a serial
; marker "CBOOT ..." then returns with D0=0 (success). A REAL bootblock would load dos here and would not
; return - our stub returns (milestone without dos).
;
; Entry (AmigaDOS bootblock convention, public - RKRM Devices / devices/bootblock.i): A6 = SysBase,
; A1 = reusable IORequest, supervisor mode. Everything PC-relative: the block runs at an arbitrary
; AllocMem'd address. Neither A6 nor A1 is used (direct serial output via SERDAT, self-contained). Clean-room:
; AUTHORED code, public hardware registers, no ROM reading.

SERDAT   EQU $DFF030                ; serial register (write)
SERDATR  EQU $DFF018                ; serial register (read; TBE = bit 13)

        lea     bb_msg(pc),a0
.lp:
        move.b  (a0)+,d1
        beq.s   .done
        move.w  #$2000,d2            ; TBE timeout (bounded, never hangs)
.wt:
        move.w  SERDATR,d3
        btst    #13,d3              ; TBE (transmit buffer empty) ?
        bne.s   .tx
        dbra    d2,.wt
        bra.s   .lp                 ; timeout -> next character
.tx:
        and.w   #$00FF,d1
        or.w    #$0100,d1           ; stop bit
        move.w  d1,SERDAT
        bra.s   .lp
.done:
        moveq   #0,d0               ; D0 = 0: boot succeeded (bootblock convention)
        rts
bb_msg:
        dc.b    "CBOOT bootblock execute (kickslop) D0=0",13,10,0
        even
