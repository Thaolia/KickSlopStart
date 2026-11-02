; tests/bootblock_c.s - CUSTOM boot code for milestone C "it boots!" (TEST ASSET, NOT ROM code).
; Assembled as a raw binary (vasm -Fbin -m68000) and placed at offset +12 of a test ADF's bootblock
; (see tests/mk_boot_adf.sh). Proves that the strap READ + VALIDATED + EXECUTED the bootblock: emits a serial
; marker "CBOOT ..." then returns like the standard bootblock: D0=0 (success) and A0 = rt_Init of the
; dos.library resident, where the strap jumps.
;
; Entry (AmigaDOS bootblock convention, public - RKRM Devices / devices/bootblock.i): A6 = SysBase,
; A1 = reusable IORequest, supervisor mode. Everything PC-relative: the block runs at an arbitrary
; AllocMem'd address. A1 is not used (direct serial output via SERDAT). Clean-room:
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
        lea     dos_name(pc),a1
        jsr     -96(a6)             ; FindResident
        tst.l   d0
        beq.s   .nodos
        move.l  d0,a0
        move.l  22(a0),a0           ; A0 = RT_INIT
        moveq   #0,d0               ; D0 = 0: boot succeeded (bootblock convention)
        rts
.nodos:
        moveq   #-1,d0
        rts
dos_name:
        dc.b    "dos.library",0
bb_msg:
        dc.b    "CBOOT bootblock execute (kickslop) D0=0",13,10,0
        even
