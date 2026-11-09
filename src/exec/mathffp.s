; src/exec/mathffp.s — mathffp.library 34.1 (Motorola fast floating point), ROM resident pri 0.
;
; FFP format (32 bits): 24-bit mantissa in bits 31-8 (normalised: bit 31 set), sign in bit 7, excess-64 exponent
; in bits 6-0. Value = (mantissa / 2^24) * 2^(exponent - 64); zero = $00000000.
; Behaviour, rounding and condition codes: docs/analysis/mathffp-v34.md (black-box spec of 1.3), checked by
; tests/mathffp_probe.sh. The points every caller can see:
; - a value whose low byte is 0 is zero for SPTst/SPFix/SPAbs/SPNeg/SPAdd/SPSub/SPMul and SPDiv's divisor;
;   $00000080 ("-0") is a number, not zero;
; - SPAdd/SPSub align with 8 guard bits, round half up before normalising and truncate a carry-out; SPFlt/SPMul
;   round to nearest, ties away from zero; SPDiv rounds to nearest; SPFix truncates toward zero;
; - overflow: +-$FFFFFF7F with V (SPMul as soon as the exponent sum reaches 192); underflow: 0; a zero divisor
;   takes the 68000 zero-divide exception (the task's trap handler);
; - registers: D0 = result; SPFix/SPFlt/SPCmp/SPTst/SPFloor/SPCeil may change D1; everything else (D1 included for
;   the others) is preserved; A6 is not used; at most 32 bytes of stack, return address included.
; IMPLEMENTATION track ("clean"): AutoDocs, mathffp_lib.fd and the analysis spec. NO ROM reading.

                include "exec.i"

LIBB_DELEXP     EQU 3                ; exec/libraries.i: LIBF_DELEXP
FFP_M1          EQU $800000C1        ; -1.0
FFP_MAX         EQU $FFFFFF7F        ; largest positive value

; --- mathffp.library ROMTag (scanned by build_reslist) ---
                EVEN
mathffp_romtag:
        dc.w    RTC_MATCHWORD
        dc.l    mathffp_romtag
        dc.l    mathffp_end
        dc.b    RTF_AUTOINIT|RTF_COLDSTART,34,NT_LIBRARY,0
        dc.l    mathffp_name
        dc.l    mathffp_id
        dc.l    mathffp_inittab
mathffp_name:
        dc.b    "mathffp.library",0
mathffp_id:
        dc.b    "mathffp 34.1 (18 Aug 1987)",13,10,0
        EVEN
mathffp_inittab:
        dc.l    LIB_SIZE
        dc.l    mathffp_vectors
        dc.l    0
        dc.l    mathffp_initfunc
; Vector N -> LVO -6*N; ##bias 30: SPFix = slot 5.
mathffp_vectors:
        dc.l    mf_open              ; -6
        dc.l    mf_close             ; -12
        dc.l    mf_expunge           ; -18
        dc.l    mf_null              ; -24 (reserved)
        dc.l    mf_fix               ; -30 SPFix(d0)
        dc.l    mf_flt               ; -36 SPFlt(d0)
        dc.l    mf_cmp               ; -42 SPCmp(d1,d0)
        dc.l    mf_tst               ; -48 SPTst(d1)
        dc.l    mf_abs               ; -54 SPAbs(d0)
        dc.l    mf_neg               ; -60 SPNeg(d0)
        dc.l    mf_add               ; -66 SPAdd(d1,d0)
        dc.l    mf_sub               ; -72 SPSub(d1,d0) = d0 - d1
        dc.l    mf_mul               ; -78 SPMul(d1,d0)
        dc.l    mf_div               ; -84 SPDiv(d1,d0) = d0 / d1
        dc.l    mf_floor             ; -90 SPFloor(d0)
        dc.l    mf_ceil              ; -96 SPCeil(d0)
        dc.l    -1

; initFunc (d0 = base): V34 InitResident does not name the node, the module does it.
mathffp_initfunc:
        move.l  d0,a1
        lea     mathffp_name(pc),a0
        move.l  a0,LN_NAME(a1)
        move.b  #NT_LIBRARY,LN_TYPE(a1)
        move.b  #(1<<LIBB_SUMUSED)|(1<<LIBB_CHANGED),LIB_FLAGS(a1) ; AddLibrary sums it, flags become $04 (1.3 at rest)
        move.l  #(34<<16)|1,LIB_VERSION(a1)
        lea     mathffp_id(pc),a0
        move.l  a0,LIB_IDSTRING(a1)
        rts

; Close never expunges, even with LIBF_DELEXP set (1.3 behaviour).
mf_open:
        addq.w  #1,LIB_OPENCNT(a6)
        move.l  a6,d0
        rts
mf_close:
        subq.w  #1,LIB_OPENCNT(a6)
        moveq   #0,d0
        rts
; Expunge: still open -> LIBF_DELEXP only; otherwise the base leaves the library list and its block is freed.
; No segment list -> D0 = 0 either way.
mf_expunge:
        tst.w   LIB_OPENCNT(a6)
        beq.s   .ex_rm
        bset    #LIBB_DELEXP,LIB_FLAGS(a6)
        moveq   #0,d0
        rts
.ex_rm:
        move.l  a6,-(sp)
        move.l  a6,a1
        move.l  ($4).w,a6
        jsr     LVO_REMOVE(a6)
        move.l  (sp),a0
        moveq   #0,d0
        move.w  LIB_NEGSIZE(a0),d0
        move.l  a0,a1
        sub.l   d0,a1
        add.w   LIB_POSSIZE(a0),d0
        jsr     LVO_FREEMEM(a6)
        move.l  (sp)+,a6
        moveq   #0,d0
mf_null:
        rts

; SPFix(d0) -> d0 = integer truncated toward zero. Low byte 0: returned unchanged with Z. Out of range:
; $7FFFFFFF with V, or $80000000 with Z and V. Changes d1.
mf_fix:
        tst.b   d0
        bne.s   .fx_nz
        move.w  #4,ccr
        rts
.fx_nz:
        moveq   #$7F,d1
        and.b   d0,d1
        sub.w   #64,d1               ; d1 = number of integer bits
        ble.s   .fx_zero
        tst.b   d0
        bmi.s   .fx_neg
        sub.w   #32,d1
        bge.s   .fx_psat
        neg.w   d1
        clr.b   d0
        lsr.l   d1,d0
        rts
.fx_zero:
        moveq   #0,d0
        rts
.fx_psat:
        move.l  #$7FFFFFFF,d0
        move.w  #2,ccr
        rts
.fx_neg:
        sub.w   #32,d1
        bgt.s   .fx_nsat
        clr.b   d0
        neg.w   d1
        lsr.l   d1,d0                ; magnitude
        tst.w   d1
        bne.s   .fx_n
        tst.l   d0                   ; 32 integer bits: only 1..2^31 fit
        beq.s   .fx_nsat
        cmp.l   #$80000000,d0
        bhi.s   .fx_nsat
.fx_n:
        neg.l   d0
        tst.l   d0                   ; -2^31: N only
        rts
.fx_nsat:
        move.l  #$80000000,d0
        move.w  #6,ccr
        rts

; SPFlt(d0 signed integer) -> FFP, rounded to nearest, ties away from zero. Changes d1.
mf_flt:
        tst.l   d0
        beq.s   .fl_r
        moveq   #$60,d1              ; low byte = sign + exponent of the 32-bit magnitude
        tst.l   d0
        bpl.s   .fl_p
        neg.l   d0                   ; $80000000 stays: unsigned 2^31
        moveq   #-$20,d1             ; $E0
.fl_p:
        cmp.l   #$10000,d0
        bcc.s   .fl_n
        swap    d0
        sub.b   #16,d1
.fl_n:
        tst.l   d0
        bmi.s   .fl_rnd
.fl_l:
        subq.b  #1,d1
        add.l   d0,d0
        bpl.s   .fl_l
.fl_rnd:
        add.l   #$80,d0
        bcc.s   .fl_pk
        roxr.l  #1,d0                ; rounded up to 2^32: mantissa $800000, exponent + 1
        addq.b  #1,d1
.fl_pk:
        clr.b   d0
        or.b    d1,d0
.fl_r:
        rts

; SPCmp(fnum1 d1, fnum2 d0) -> d0 = +1 if d1 > d0, -1 if d1 < d0, 0 if equal; the codes are those of "d0
; compared with d1" (signed branches). Order: sign, then the exponent, then the mantissa as a signed 24-bit
; number; reversed for two negative values. Key = exponent:mantissa with the mantissa's top bit inverted,
; complemented when negative. Changes d1.
mf_cmp:
        move.l  d2,-(sp)
        move.l  d0,d2
        ror.l   #8,d2
        bchg    #23,d2
        bclr    #31,d2
        beq.s   .cm_k0
        not.l   d2
.cm_k0:
        ror.l   #8,d1
        bchg    #23,d1
        bclr    #31,d1
        beq.s   .cm_k1
        not.l   d1
.cm_k1:
        moveq   #0,d0
        cmp.l   d1,d2
        beq.s   .cm_cc
        blt.s   .cm_gt
        moveq   #-1,d0
        bra.s   .cm_cc
.cm_gt:
        moveq   #1,d0
.cm_cc:
        cmp.l   d1,d2
        movem.l (sp)+,d2             ; movem to a register: CCR intact
        rts

; SPTst(d1) -> d0 = -1 (bit 7 set), 0 (low byte 0), +1 otherwise.
mf_tst:
        moveq   #1,d0
        tst.b   d1
        bgt.s   .ts_r
        beq.s   .ts_z
        moveq   #-1,d0
.ts_r:
        rts
.ts_z:
        moveq   #0,d0
        rts

; SPAbs(d0): bit 7 cleared. SPNeg(d0): bit 7 inverted unless the low byte is 0.
mf_abs:
        bclr    #7,d0
        tst.b   d0
        rts
mf_neg:
        tst.b   d0
        beq.s   .ng_r
        eori.b  #$80,d0
.ng_r:
        rts

; ffp_pack: d2 = mantissa in bits 31-8 (low byte 0), d3.w = exponent, d4.b = sign ($80/0) -> d0 + codes.
; Exponent < 0: 0. Exponent 0: kept when negative, 0 when positive. Exponent > 127: saturation.
ffp_pack:
        tst.w   d3
        bgt.s   .pk_e
        bmi.s   .pk_z
        tst.b   d4
        beq.s   .pk_z
.pk_e:
        cmp.w   #127,d3
        bgt.s   ffp_sat
        move.l  d2,d0
        or.b    d3,d0
        or.b    d4,d0
        rts
.pk_z:
        moveq   #0,d0
        rts
; ffp_sat: d4.b = sign -> d0 = +-largest value, V set.
ffp_sat:
        move.l  #FFP_MAX,d0
        or.b    d4,d0
        ori.b   #2,ccr
        rts

; SPSub(d1,d0) = d0 - d1 = SPAdd(d1 with its sign inverted, d0); a zero d1 gives d0 unchanged.
mf_sub:
        tst.b   d1
        bne.s   .sb_go
        tst.b   d0
        rts
.sb_go:
        movem.l d2-d6,-(sp)
        move.l  d1,d3
        eori.b  #$80,d3
        bra.s   ffp_add
; SPAdd(d1,d0) = d0 + d1.
mf_add:
        movem.l d2-d6,-(sp)
        move.l  d1,d3
; ffp_add: d0 + d3 -> d0 + codes; d2-d6 saved by the caller (popped here).
ffp_add:
        tst.b   d3
        beq     .ad_d0               ; second operand zero: d0 unchanged
        tst.b   d0
        bne.s   .ad_both
        move.l  d3,d0                ; d0 zero: the other operand
        bra.s   .ad_d0
.ad_both:
        move.l  d0,d2                ; keys exponent:mantissa, sign removed
        ror.l   #8,d2
        bclr    #31,d2
        move.l  d3,d4
        ror.l   #8,d4
        bclr    #31,d4
        cmp.l   d4,d2
        bcc.s   .ad_ord
        exg     d0,d3                ; d0 = A (larger exponent, then larger mantissa), d3 = B
.ad_ord:
        moveq   #$7F,d5
        and.b   d0,d5                ; d5 = exponent of A
        moveq   #$7F,d6
        and.b   d3,d6
        sub.w   d5,d6
        neg.w   d6                   ; d6 = exponent difference
        cmp.w   #24,d6
        bge.s   .ad_d0               ; B is ignored: A bit for bit
        move.l  d3,d4
        clr.b   d4
        lsr.l   d6,d4                ; B aligned, 8 bits below A's last mantissa bit
        eor.b   d0,d3                ; bit 7: signs differ
        move.l  d0,d2
        clr.b   d2                   ; A's mantissa
        moveq   #0,d6
        tst.b   d3
        bmi.s   .ad_dif
        add.l   d4,d2
        addx.l  d6,d6                ; d6 = carry out of the sum
        add.l   #$80,d2              ; half up, on A's last mantissa bit
        moveq   #0,d4
        addx.l  d4,d6
        lsr.l   #1,d6
        bcc.s   .ad_nm
        roxr.l  #1,d2                ; carry-out: halved, the bit shifted out is dropped
        addq.w  #1,d5
        bra.s   .ad_nm
.ad_dif:
        sub.l   d4,d2
        beq.s   .ad_z
        add.l   #$80,d2
.ad_nm:
        clr.b   d2
        tst.l   d2
        bmi.s   .ad_pk
.ad_nl:
        subq.w  #1,d5
        bmi.s   .ad_z
        add.l   d2,d2
        bpl.s   .ad_nl
.ad_pk:
        move.w  d5,d3
        move.b  d0,d4
        and.b   #$80,d4              ; sign of A
        bsr     ffp_pack
        bra.s   .ad_out
.ad_z:
        moveq   #0,d0
        bra.s   .ad_out
.ad_d0:
        tst.b   d0
.ad_out:
        movem.l (sp)+,d2-d6
        rts

; SPMul(d1,d0) -> d0 * d1. Low byte of d0 0: d0 unchanged; low byte of d1 0: 0. Exponent sum >= 192: saturation,
; whatever the mantissas. 24x24-bit product by four mulu; rounded to nearest, ties away from zero.
mf_mul:
        tst.b   d0
        beq.s   .mu_r
        tst.b   d1
        bne.s   .mu_go
        moveq   #0,d0
.mu_r:
        rts
.mu_go:
        movem.l d2-d6,-(sp)
        moveq   #$7F,d3
        and.b   d0,d3
        moveq   #$7F,d2
        and.b   d1,d2
        add.w   d2,d3                ; d3 = exponent sum
        cmp.w   #192,d3
        bge.s   .mu_sat
        move.l  d0,d2
        clr.b   d2                   ; a = ah:al
        move.l  d1,d4
        clr.b   d4                   ; b = bh:bl
        move.w  d2,d5
        mulu    d4,d5                ; al*bl
        clr.w   d5
        swap    d5
        move.l  d2,d6
        swap    d6
        mulu    d4,d6                ; ah*bl
        add.l   d6,d5
        swap    d4
        move.w  d4,d6
        mulu    d2,d6                ; al*bh
        add.l   d6,d5
        moveq   #0,d6
        addx.w  d6,d6                ; carry of the middle sum
        swap    d2
        mulu    d4,d2                ; ah*bh
        swap    d6
        clr.w   d5
        swap    d5
        add.l   d6,d5
        add.l   d5,d2                ; d2 = high 32 bits of a*b
        tst.l   d2
        bmi.s   .mu_hi
        add.l   #$40,d2
        bmi.s   .mu_up               ; rounded up to the next power of 2
        add.l   d2,d2
        subq.w  #1,d3
        bra.s   .mu_up
.mu_hi:
        add.l   #$80,d2
.mu_up:
        sub.w   #64,d3
        clr.b   d2
        bsr.s   .mu_sgn
        bsr     ffp_pack
        bra.s   .mu_out
.mu_sat:
        bsr.s   .mu_sgn
        bsr     ffp_sat
.mu_out:
        movem.l (sp)+,d2-d6
        rts
.mu_sgn:
        move.b  d0,d4
        eor.b   d1,d4
        and.b   #$80,d4
        rts

; SPDiv(d1,d0) -> d0 / d1. Divisor with low byte 0, or a zero divisor mantissa reached by the division: 68000
; zero-divide exception. Dividend $00000000: 0. Q = exponent difference + 64: >= 128 saturation with the
; quotient's sign, < 0 zero. Dividend mantissa >= divisor mantissa (compared as signed longs): exponent Q + 1 and
; 24 quotient bits, else Q and 25; one more bit for rounding to nearest. Exponent 128 reached through the mantissa
; step: saturation with the divisor's sign.
mf_div:
        tst.b   d1
        bne.s   .dv_nz
.dv_trap:
        divu    ffp_zero(pc),d0
        rts
.dv_nz:
        tst.l   d0
        beq     .dv_r
        movem.l d2-d6,-(sp)
        moveq   #$7F,d3
        and.b   d0,d3
        moveq   #$7F,d2
        and.b   d1,d2
        sub.w   d2,d3
        add.w   #64,d3               ; d3 = Q
        bmi     .dv_z
        cmp.w   #128,d3
        bge.s   .dv_sat
        move.l  d1,d2
        lsr.l   #8,d2                ; d2 = divisor mantissa
        bne.s   .dv_go
        divu    ffp_zero(pc),d0
        bra.s   .dv_out
.dv_go:
        move.l  d0,d5
        clr.b   d5                   ; dividend mantissa << 8
        move.l  d1,d4
        clr.b   d4
        moveq   #25,d6               ; quotient bits after the integer part (rounding bit included)
        cmp.l   d4,d5
        blt.s   .dv_b
        addq.w  #1,d3
        subq.w  #1,d6
.dv_b:
        swap    d6
        move.w  d3,d6
        swap    d6                   ; d6 = exponent : bit count
        moveq   #0,d4                ; quotient
        tst.l   d1
        bpl.s   .dv_slow
        lsr.l   #8,d5                ; normalised divisor: integer part 0 or 1
        move.l  d5,d3
        moveq   #0,d5
        cmp.l   d2,d3
        bcs.s   .dv_lp0
        sub.l   d2,d3
        moveq   #1,d4
        bra.s   .dv_lp0
.dv_slow:
        moveq   #0,d3                ; unnormalised divisor: the dividend's 24 bits go through the loop too
        add.w   #24,d6
.dv_lp0:
        subq.w  #1,d6
.dv_lp:
        add.l   d5,d5
        addx.l  d3,d3                ; remainder * 2 + next dividend bit
        add.l   d4,d4
        cmp.l   d2,d3
        bcs.s   .dv_nb
        sub.l   d2,d3
        addq.l  #1,d4
.dv_nb:
        dbra    d6,.dv_lp
        addq.l  #1,d4
        lsr.l   #1,d4                ; rounded
        lsl.l   #8,d4
        move.l  d4,d2
        swap    d6
        move.w  d6,d3
        move.b  d0,d4
        eor.b   d1,d4
        cmp.w   #128,d3
        bne.s   .dv_pk
        move.b  d1,d4
.dv_pk:
        and.b   #$80,d4
        bsr     ffp_pack
        bra.s   .dv_out
.dv_sat:
        move.b  d0,d4
        eor.b   d1,d4
        and.b   #$80,d4
        bsr     ffp_sat
        bra.s   .dv_out
.dv_z:
        moveq   #0,d0
.dv_out:
        movem.l (sp)+,d2-d6
.dv_r:
        rts

; SPCeil(d0) = SPNeg(SPFloor(SPNeg(d0))). Changes d1.
mf_ceil:
        tst.b   d0
        beq.s   .ce_f
        eori.b  #$80,d0
.ce_f:
        bsr.s   mf_floor
        tst.b   d0
        beq.s   .ce_r
        eori.b  #$80,d0
.ce_r:
        rts

; SPFloor(d0) -> largest integer <= d0. Exponent 0: the sign is cleared. |d0| < 1: 0 or -1. Positive: fraction
; bits cleared (exponent kept); negative with a fraction: one unit added at the integer position. Changes d1.
mf_floor:
        moveq   #$7F,d1
        and.b   d0,d1
        bne.s   .fo_e
        bclr    #7,d0
        tst.b   d0
        rts
.fo_e:
        sub.w   #64,d1               ; d1 = number of integer bits
        bgt.s   .fo_big
        tst.b   d0
        bmi.s   .fo_m1
        moveq   #0,d0
        rts
.fo_m1:
        move.l  #FFP_M1,d0
        rts
.fo_big:
        cmp.w   #24,d1
        bge.s   .fo_tst
        move.l  d2,-(sp)
        moveq   #-1,d2
        lsr.l   d1,d2
        clr.b   d2                   ; d2 = fraction bits of the mantissa
        move.l  d2,d1
        and.l   d0,d1
        beq.s   .fo_end
        not.l   d2
        and.l   d2,d0                ; truncated toward zero
        tst.b   d0
        bpl.s   .fo_end
        not.l   d2
        add.l   #$100,d2             ; one unit at the integer position
        add.l   d2,d0
        bcc.s   .fo_end
        move.b  d0,d1                ; mantissa overflow: $800000, exponent + 1
        addq.b  #1,d1
        move.l  #$80000000,d0
        move.b  d1,d0
.fo_end:
        tst.b   d0
        movem.l (sp)+,d2             ; movem to a register: CCR intact
        rts
.fo_tst:
        tst.b   d0
        rts

ffp_zero:
        dc.w    0                    ; divisor of the deliberate zero-divide exception

mathffp_end:
