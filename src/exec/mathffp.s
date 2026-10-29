; src/exec/mathffp.s — mathffp.library (Motorola FFP fast floating point), resident pri 0, V34.
;
; FFP format (32 bits): 24-bit mantissa normalised in bits 31-8 (bit 31 = 1 except for zero), sign in
; bit 7, excess-64 exponent in bits 6-0. Value = (mantissa / 2^24) * 2^(exponent - 64); zero = 0.
; Internally a mantissa lives on 32 bits (bits 7-0 = guard) and rounding is to nearest on the guard.
; Exit: Z/N condition codes according to the result; overflow -> largest signed value + V.
; Registers: d0/d1/a0/a1 destroyed, d2-d7 preserved (library convention).
; IMPLEMENTATION track ("clean"): AutoDocs mathffp.library + mathffp_lib.fd. NO ROM reading.

                include "exec.i"

FFP_M1          EQU $800000C1        ; -1.0

; --- mathffp.library ROMTag (scanned by build_reslist) ---
                EVEN
mathffp_romtag:
        dc.w    RTC_MATCHWORD
        dc.l    mathffp_romtag
        dc.l    mathffp_end
        dc.b    RTF_AUTOINIT|RTF_COLDSTART,34,NT_LIBRARY,0
        dc.l    mathffp_name
        dc.l    mathffp_name
        dc.l    mathffp_inittab
mathffp_name:
        dc.b    "mathffp.library",0
        EVEN
mathffp_inittab:
        dc.l    LIB_SIZE
        dc.l    mathffp_vectors
        dc.l    mathffp_datatab
        dc.l    mathffp_initfunc
; Vector N -> LVO -6*N; ##bias 30: SPFix = slot 5.
mathffp_vectors:
        dc.l    mf_open              ; -6
        dc.l    mf_close             ; -12
        dc.l    mf_expunge           ; -18
        dc.l    mf_expunge           ; -24 (reserved)
        dc.l    mf_fix               ; -30 SPFix(d0)
        dc.l    mf_flt               ; -36 SPFlt(d0)
        dc.l    mf_cmp               ; -42 SPCmp(d0,d1)
        dc.l    mf_tst               ; -48 SPTst(d1)
        dc.l    mf_abs               ; -54 SPAbs(d0)
        dc.l    ffp_neg              ; -60 SPNeg(d0)
        dc.l    mf_add               ; -66 SPAdd(d1,d0)
        dc.l    mf_sub               ; -72 SPSub(d1,d0) = d0 - d1
        dc.l    mf_mul               ; -78 SPMul(d1,d0)
        dc.l    mf_div               ; -84 SPDiv(d1,d0) = d0 / d1
        dc.l    mf_floor             ; -90 SPFloor(d0)
        dc.l    mf_ceil              ; -96 SPCeil(d0)
        dc.l    -1
mathffp_datatab:
        dc.w    $E000,LN_TYPE,(NT_LIBRARY<<8)
        dc.w    $D000,LIB_VERSION,34
        dc.b    0
        EVEN

; initFunc (d0 = base): V34 InitResident does not name the node, the module does it.
mathffp_initfunc:
        move.l  d0,a1
        lea     mathffp_name(pc),a0
        move.l  a0,LN_NAME(a1)
        rts

mf_open:
        addq.w  #1,LIB_OPENCNT(a6)
        move.l  a6,d0
        rts
mf_close:
        subq.w  #1,LIB_OPENCNT(a6)
mf_expunge:
        moveq   #0,d0
        rts

; ffp_cc: condition codes of float d0 (Z if zero, N from the sign bit, V/C at 0).
ffp_cc:
        tst.l   d0
        beq.s   .z
        tst.b   d0
        bmi.s   .n
        move.w  #0,ccr
.z:
        rts
.n:
        move.w  #8,ccr
        rts

; ffp_pack: d2 = normalised 32-bit mantissa (bit 31 = 1), d3.w = signed exponent, d4.b = sign ($80/0)
; -> d0 = rounded float + condition codes. Exponent <= 0 -> 0; > 127 -> largest value + V.
ffp_pack:
        add.l   #$80,d2
        bcc.s   .nc
        move.l  #$80000000,d2        ; the rounded mantissa reaches 2^32: renormalise
        addq.w  #1,d3
.nc:
        clr.b   d2
        tst.w   d3
        ble.s   .uf
        cmp.w   #127,d3
        bgt.s   .ov
        move.l  d2,d0
        or.b    d3,d0
        or.b    d4,d0
        bra.s   ffp_cc
.uf:
        moveq   #0,d0
        rts
.ov:
        moveq   #-1,d0
        move.b  #$7F,d0
        or.b    d4,d0
        bsr.s   ffp_cc
        ori.b   #2,ccr
        rts

; SPAbs / SPNeg (d0 only).
mf_abs:
        and.b   #$7F,d0
        bra.s   ffp_cc
ffp_neg:
        tst.l   d0
        beq.s   .r
        eor.b   #$80,d0
        bra.s   ffp_cc
.r:
        rts

; SPTst(d1) -> d0 = +1 / -1 / 0.
mf_tst:
        moveq   #0,d0
        tst.l   d1
        beq.s   .r
        tst.b   d1
        bmi.s   .n
        moveq   #1,d0
        rts
.n:
        moveq   #-1,d0
.r:
        rts

; SPCmp(fnum1 d0, fnum2 d1) -> d0 = +1 if fnum1 > fnum2, -1 if fnum1 < fnum2, 0 otherwise; the condition
; codes describe fnum2 against fnum1 (GT <=> fnum2 > fnum1), as the AutoDoc specifies.
; Signed integer key ordered like the float: (exponent << 24 | 24-bit mantissa), negated if negative.
mf_cmp:
        movem.l d2-d3,-(sp)
        move.l  d0,d2
        ror.l   #8,d2
        bclr    #31,d2
        beq.s   .k1
        neg.l   d2
.k1:
        move.l  d1,d3
        ror.l   #8,d3
        bclr    #31,d3
        beq.s   .k2
        neg.l   d3
.k2:
        moveq   #0,d0
        cmp.l   d3,d2
        beq.s   .cc
        bgt.s   .gt
        moveq   #-1,d0
        bra.s   .cc
.gt:
        moveq   #1,d0
.cc:
        cmp.l   d2,d3
        movem.l (sp)+,d2-d3          ; movem to registers: CCR intact
        rts

; SPFix(d0) -> integer truncated towards zero, saturated at $7FFFFFFF / $80000000.
mf_fix:
        move.l  d2,-(sp)
        moveq   #$7F,d1
        and.l   d0,d1
        sub.w   #64,d1               ; d1 = number of integer bits
        ble.s   .zero
        cmp.w   #32,d1
        bge.s   .sat
        move.l  d0,d2
        clr.b   d2
        neg.w   d1
        add.w   #32,d1
        lsr.l   d1,d2
        tst.b   d0
        bpl.s   .p
        neg.l   d2
.p:
        move.l  d2,d0
        move.l  (sp)+,d2
        tst.l   d0
        rts
.zero:
        moveq   #0,d0
        move.l  (sp)+,d2
        tst.l   d0
        rts
.sat:
        tst.b   d0
        bmi.s   .sn
        move.l  #$7FFFFFFF,d0
        bra.s   .sr
.sn:
        move.l  #$80000000,d0
.sr:
        move.l  (sp)+,d2
        tst.l   d0
        rts

; SPFlt(d0 signed integer) -> float.
mf_flt:
        movem.l d2-d4,-(sp)
        tst.l   d0
        beq.s   .ret
        moveq   #0,d4
        move.l  d0,d2
        bpl.s   .p
        neg.l   d2                   ; $80000000 stays $80000000 = unsigned 2^31
        move.b  #$80,d4
.p:
        moveq   #96,d3               ; mantissa = 32-bit integer: 2^32 * 2^(96-64-32)
        cmp.l   #$10000,d2
        bcc.s   .nt
        swap    d2
        sub.w   #16,d3
.nt:
        tst.l   d2
        bmi.s   .pk
.nl:
        subq.w  #1,d3
        add.l   d2,d2
        bpl.s   .nl
.pk:
        bsr     ffp_pack
.ret:
        movem.l (sp)+,d2-d4
        rts

; SPSub(d1,d0) = d0 - d1; SPAdd(d1,d0) = d0 + d1.
mf_sub:
        tst.l   d1
        beq     ffp_cc
        eor.b   #$80,d1
mf_add:
        movem.l d2-d7,-(sp)
        bsr.s   ffp_add
        movem.l (sp)+,d2-d7
        rts

; ffp_add: d0 + d1 -> d0 + condition codes (uses d1-d7).
ffp_add:
        tst.l   d0
        bne.s   .a1
        move.l  d1,d0
        bra     ffp_cc
.a1:
        tst.l   d1
        beq     ffp_cc
        move.l  d0,d2                ; d2/d3/d4 = mantissa/exponent/sign of d0
        clr.b   d2
        moveq   #$7F,d3
        and.l   d0,d3
        move.b  d0,d4
        and.b   #$80,d4
        move.l  d1,d5                ; d5/d6/d7 = same for d1
        clr.b   d5
        moveq   #$7F,d6
        and.l   d1,d6
        move.b  d1,d7
        and.b   #$80,d7
        cmp.w   d6,d3
        bcc.s   .ord
        exg     d2,d5                ; operand with the larger exponent in d2/d3/d4
        exg     d3,d6
        exg     d4,d7
.ord:
        move.w  d3,d1
        sub.w   d6,d1
        cmp.w   #32,d1
        bcc     ffp_pack             ; gap >= 32: the small operand is absorbed
        lsr.l   d1,d5
        cmp.b   d4,d7
        bne.s   .diff
        add.l   d5,d2
        bcc     ffp_pack
        roxr.l  #1,d2                ; carry fed back into bit 31
        addq.w  #1,d3
        bra     ffp_pack
.diff:
        sub.l   d5,d2
        beq.s   .zero
        bcc.s   .norm
        neg.l   d2                   ; |d1| > |d0|: the sign of the result is that of d1
        move.b  d7,d4
.norm:
        tst.l   d2
        bmi     ffp_pack
.nl:
        subq.w  #1,d3
        add.l   d2,d2
        bpl.s   .nl
        bra     ffp_pack
.zero:
        moveq   #0,d0
        rts

; SPMul(d1,d0) -> d0 * d1. 24x24-bit product by four 16x16 mulu; we keep the 32 most significant bits.
mf_mul:
        movem.l d2-d7,-(sp)
        tst.l   d0
        beq.s   .zero
        tst.l   d1
        beq.s   .zero
        move.b  d0,d4
        eor.b   d1,d4
        and.b   #$80,d4
        moveq   #$7F,d3
        and.l   d0,d3
        moveq   #$7F,d2
        and.l   d1,d2
        add.w   d2,d3
        sub.w   #64,d3
        lsr.l   #8,d0                ; 24-bit mantissas: d0 = a1:a0, d1 = b1:b0
        lsr.l   #8,d1
        move.l  d0,d2
        swap    d2                   ; d2.w = a1
        move.l  d1,d5
        swap    d5                   ; d5.w = b1
        move.w  d0,d6
        mulu.w  d1,d6                ; d6 = a0*b0
        move.w  d2,d7
        mulu.w  d1,d7                ; d7 = a1*b0
        move.w  d5,d1
        mulu.w  d0,d1                ; d1 = a0*b1
        mulu.w  d5,d2                ; d2 = a1*b1
        swap    d2
        clr.w   d2
        add.l   d7,d2
        add.l   d1,d2
        move.l  d6,d1
        clr.w   d1
        swap    d1
        add.l   d1,d2                ; d2 = 48-bit product >> 16
        bmi.s   .pk
        add.w   d6,d6                ; next bit (bit 15 of the product) -> X
        addx.l  d2,d2
        subq.w  #1,d3
.pk:
        bsr     ffp_pack
        movem.l (sp)+,d2-d7
        rts
.zero:
        moveq   #0,d0
        movem.l (sp)+,d2-d7
        rts

; SPDiv(d1,d0) -> d0 / d1. Restoring division over 32 quotient bits; zero divisor -> overflow.
mf_div:
        movem.l d2-d7,-(sp)
        move.b  d0,d4
        eor.b   d1,d4
        and.b   #$80,d4
        tst.l   d1
        beq.s   .dz
        tst.l   d0
        beq.s   .zero
        moveq   #$7F,d3
        and.l   d0,d3
        moveq   #$7F,d2
        and.l   d1,d2
        sub.w   d2,d3
        add.w   #65,d3
        lsr.l   #8,d0                ; d0 = remainder (mantissa of the dividend), d1 = divisor
        lsr.l   #8,d1
        cmp.l   d1,d0
        bcc.s   .go
        add.l   d0,d0                ; dividend < divisor: the first quotient bit will be 1
        subq.w  #1,d3
.go:
        moveq   #0,d2
        moveq   #31,d5
.lp:
        add.l   d2,d2
        cmp.l   d1,d0
        bcs.s   .nb
        sub.l   d1,d0
        addq.l  #1,d2
.nb:
        add.l   d0,d0
        dbra    d5,.lp
        bra.s   .pk
.dz:
        move.w  #200,d3              ; forces the overflow branch of ffp_pack
.pk:
        bsr     ffp_pack
        movem.l (sp)+,d2-d7
        rts
.zero:
        moveq   #0,d0
        movem.l (sp)+,d2-d7
        rts

; SPFloor(d0) / SPCeil(d0) = -Floor(-d0).
mf_floor:
        movem.l d2-d7,-(sp)
        bsr.s   ffp_floor
        movem.l (sp)+,d2-d7
        rts
mf_ceil:
        movem.l d2-d7,-(sp)
        bsr     ffp_neg
        bsr.s   ffp_floor
        bsr     ffp_neg
        movem.l (sp)+,d2-d7
        rts

; ffp_floor: largest integer <= d0 -> d0 + condition codes (uses d1-d7).
ffp_floor:
        tst.l   d0
        beq     ffp_cc
        moveq   #$7F,d1
        and.l   d0,d1
        sub.w   #64,d1               ; d1 = number of integer bits
        bgt.s   .big
        tst.b   d0                   ; |x| < 1: 0 if positive, -1 if negative
        bmi.s   .m1
        moveq   #0,d0
        rts
.m1:
        move.l  #FFP_M1,d0
        bra     ffp_cc
.big:
        cmp.w   #24,d1
        bge     ffp_cc               ; no fractional bit
        moveq   #-1,d2
        lsr.l   d1,d2
        clr.b   d2                   ; d2 = mask of the fractional bits of the mantissa
        move.l  d0,d3
        and.l   d2,d3
        beq     ffp_cc
        not.l   d2
        and.l   d2,d0                ; truncation towards zero
        tst.b   d0
        bpl     ffp_cc
        move.l  #FFP_M1,d1           ; non-integer negative: truncated - 1
        bra     ffp_add

mathffp_end:
