; src/exec/rawdofmt.s — exec RawDoFmt (LVO -522): "printf-like" formatting used by programs (printf of the C
; startups, SetPatch messages, the Workbench memory title, the Guru text...).
; IMPLEMENTATION track ("clean"): AutoDoc exec.library/RawDoFmt (public) and the behavioural spec
; docs/analysis/exec-rawdofmt-v34.md. NO ROM reading.
;
; RawDoFmt(FormatString a0, DataStream a1, PutChProc a2, PutChData a3)
; Conversion: %[-][0][width][.limit][l]type, in this order and nothing else. Types d (signed), x (hex, upper case),
; s (C string), c (character); any other type character is sent as is, without padding and without reading data
; (%% is this rule, and so is %b, whose BPTR stays unread). d/x/c read a word (sign-extended for d only) or, with l,
; a long; s always reads a long pointer. Items are packed, no alignment. The limit (0 = none) keeps the first n
; characters of every type, sign included; width and limit are 16-bit, the padding count (width - length) is a
; signed 16-bit value and only a positive one pads. The pad character ('0' with the 0 flag, else a space) goes on the
; padding side only: before the text, or after it with '-' (so zeros never move the sign). %c of a zero byte is an
; empty text. Every character, final NUL included, goes to PutChProc (jsr (a2), d0.b = character, a3 = PutChData
; as left by the previous call).
; Exit: a1 = d0 = just past the last data item read, a3 restored, d2-d7/a2/a4-a6 preserved.
; Deliberate differences from 1.3 (docs/PLAN.md, rank 11): a format that ends inside a conversion ("abc%", "abc%5")
; ends the call at its terminator (1.3 sends that NUL as a character and keeps scanning past the end); d0 returns
; the next data pointer; PutChProc gets d0 with its upper 24 bits clear and the caller's a6; a1 on exit is the data
; cursor even if PutChProc changed a1.
;
; Registers kept across PutChProc calls (the ones a 1.3 PutChProc must preserve): a4 = format, d2 = data cursor,
; a5 = field text, d3 = characters of text left, d5 = pad character (bit 31 = left-justify), d6 = pad count.
; d0/d1/d4/d7/a0/a1 are scratch: PutChProc may change them.

                include "exec.i"

                xdef    exec_RawDoFmt

RDF_BUF         EQU 12               ; digit buffer: "-2147483648" is 11 characters

exec_RawDoFmt:
        movem.l d2-d7/a2-a6,-(sp)
        lea     -RDF_BUF(sp),sp
        move.l  a0,a4
        move.l  a1,d2
.rf_next:
        moveq   #0,d0
        move.b  (a4)+,d0
        beq.s   .rf_end
        cmp.b   #'%',d0
        beq.s   .rf_spec
.rf_echo:
        move.l  d2,a1
        jsr     (a2)
        bra.s   .rf_next
.rf_end:
        moveq   #0,d0                ; the terminating NUL, then exit
        move.l  d2,a1
        jsr     (a2)
        move.l  d2,d0
        move.l  d2,a1
        lea     RDF_BUF(sp),sp
        movem.l (sp)+,d2-d7/a2-a6
        rts

.rf_spec:
        moveq   #' ',d5
        moveq   #0,d6                ; width (low word)
        moveq   #0,d7                ; limit (low word)
        moveq   #0,d4                ; long flag
        move.b  (a4)+,d0
        cmp.b   #'-',d0
        bne.s   .rf_zero
        bset    #31,d5
        move.b  (a4)+,d0
.rf_zero:
        cmp.b   #'0',d0
        bne.s   .rf_width
        move.b  #'0',d5
        move.b  (a4)+,d0
.rf_width:
        moveq   #0,d1
        move.b  d0,d1
        sub.w   #'0',d1
        cmp.w   #9,d1
        bhi.s   .rf_dot
        mulu.w  #10,d6               ; modulo 65536: only the low word counts
        add.w   d1,d6
        move.b  (a4)+,d0
        bra.s   .rf_width
.rf_dot:
        cmp.b   #'.',d0
        bne.s   .rf_long
        move.b  (a4)+,d0
.rf_limit:
        moveq   #0,d1
        move.b  d0,d1
        sub.w   #'0',d1
        cmp.w   #9,d1
        bhi.s   .rf_long
        mulu.w  #10,d7
        add.w   d1,d7
        move.b  (a4)+,d0
        bra.s   .rf_limit
.rf_long:
        cmp.b   #'l',d0
        bne.s   .rf_type
        moveq   #1,d4
        move.b  (a4)+,d0
.rf_type:
        tst.b   d0
        beq.s   .rf_end              ; format ends inside a conversion: stop at its terminator
        and.l   #$FFFF,d7            ; d7 = maximum text length, $FFFFFFFF when there is no limit
        bne.s   .rf_lim
        moveq   #-1,d7
.rf_lim:
        cmp.b   #'d',d0
        beq.s   .rf_dec
        cmp.b   #'x',d0
        beq.s   .rf_hex
        cmp.b   #'s',d0
        beq     .rf_str
        cmp.b   #'c',d0
        beq     .rf_char
        bra     .rf_echo             ; unknown type, "%%" included: the character itself, nothing else

.rf_dec:
        bsr     .rf_fetch
        tst.w   d4
        bne.s   .rf_dsign
        ext.l   d0
.rf_dsign:
        moveq   #0,d4                ; d4 = 1 if negative
        tst.l   d0
        bpl.s   .rf_dabs
        neg.l   d0                   ; $80000000 stays itself, read as unsigned below
        moveq   #1,d4
.rf_dabs:
        lea     RDF_BUF(sp),a0       ; digits written right to left
        move.l  d0,d1
.rf_dloop:                           ; d1 /= 10 in two 16-bit divu, the remainder is the digit
        moveq   #0,d0
        swap    d1
        move.w  d1,d0
        divu.w  #10,d0               ; [remainder:high quotient]
        move.w  d0,d1
        swap    d1                   ; [high quotient:low word]
        move.w  d1,d0                ; [remainder:low word]
        divu.w  #10,d0               ; [digit:low quotient]
        move.w  d0,d1
        swap    d0
        add.b   #'0',d0
        move.b  d0,-(a0)
        tst.l   d1
        bne.s   .rf_dloop
        tst.w   d4
        beq.s   .rf_numtext
        move.b  #'-',-(a0)
.rf_numtext:
        move.l  a0,a5
        lea     RDF_BUF(sp),a0
        move.l  a0,d3
        sub.l   a5,d3
        bra.s   .rf_emit

.rf_hex:
        bsr     .rf_fetch
        lea     RDF_BUF(sp),a0
        move.l  d0,d1
.rf_xloop:
        moveq   #$0F,d0
        and.b   d1,d0
        add.b   #'0',d0
        cmp.b   #'9',d0
        bls.s   .rf_xdig
        addq.b  #7,d0                ; 'A'..'F'
.rf_xdig:
        move.b  d0,-(a0)
        lsr.l   #4,d1
        bne.s   .rf_xloop
        bra.s   .rf_numtext

.rf_char:
        bsr.s   .rf_fetch
        lea     RDF_BUF(sp),a5
        moveq   #0,d3
        tst.b   d0                   ; a zero byte is an empty text
        beq.s   .rf_emit
        move.b  d0,-(a5)
        moveq   #1,d3
        bra.s   .rf_emit

.rf_str:
        move.l  d2,a0
        move.l  (a0)+,a5
        move.l  a0,d2
        move.l  a5,a0                ; length, counted no further than the limit
        moveq   #0,d3
.rf_slen:
        cmp.l   d7,d3
        beq.s   .rf_emit
        tst.b   (a0)+
        beq.s   .rf_emit
        addq.l  #1,d3
        bra.s   .rf_slen

; .rf_emit: a5 = text, d3 = length; limit (d7), padding (d6 = width), justification and pad character (d5)
.rf_emit:
        cmp.l   d7,d3
        bls.s   .rf_trunc
        move.l  d7,d3
.rf_trunc:
        sub.w   d3,d6                ; pad count, signed 16-bit: only a positive value pads
        tst.w   d6                   ; (the sign of the result, not of the true difference)
        bgt.s   .rf_padn
        moveq   #0,d6
.rf_padn:
        tst.l   d5
        bmi.s   .rf_text
        bsr.s   .rf_pad
.rf_text:
        tst.l   d3
        beq.s   .rf_tdone
.rf_tloop:
        moveq   #0,d0
        move.b  (a5)+,d0
        move.l  d2,a1
        jsr     (a2)
        subq.l  #1,d3
        bne.s   .rf_tloop
.rf_tdone:
        bsr.s   .rf_pad              ; right-justified: d6 is already spent
        bra     .rf_next

; .rf_pad: sends the pad character d6.w times; d6.w = -1 on exit
.rf_pad:
        subq.w  #1,d6
        bmi.s   .rf_padx
        moveq   #0,d0
        move.b  d5,d0
        move.l  d2,a1
        jsr     (a2)
        bra.s   .rf_pad
.rf_padx:
        rts

; .rf_fetch: d0 = next word (zero-extended) or, with d4 set, next long of the data stream at d2
.rf_fetch:
        move.l  d2,a0
        tst.w   d4
        bne.s   .rf_flong
        moveq   #0,d0
        move.w  (a0)+,d0
        move.l  a0,d2
        rts
.rf_flong:
        move.l  (a0)+,d0
        move.l  a0,d2
        rts
