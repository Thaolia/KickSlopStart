; defprefs_probe.s - GetDefPrefs black-box probe (our own test program, public API only: intuition AutoDocs
; GetDefPrefs/GetPrefs, preferences.h V34 layout of 232 bytes).
; Bootblock: opens intuition.library, calls GetDefPrefs and then GetPrefs into two 232-byte buffers prefilled
; with $EE, and sends both on the serial port (SERDAT, polled), in hex, 16 bytes per line:
;   "DP D <offset> <16 bytes>"   GetDefPrefs
;   "DP C <offset> <16 bytes>"   GetPrefs (current copy at bootblock time)
;   "DP R <d0 GetDefPrefs == buffer ? 1 : 0>"
;   "DP END"
; Then it stays in a loop (the boot does not go on).
; Build and run: tests/defprefs_probe.sh <out_dir> (it writes <out_dir>/defprefs.adf).

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018
PSIZE    EQU 232

boot:
        lea     intname(pc),a1
        moveq   #0,d0
        jsr     -552(a6)                ; OpenLibrary
        tst.l   d0
        beq     .hang
        move.l  d0,a5
        move.l  #2*PSIZE,d0
        move.l  #$10001,d1              ; MEMF_PUBLIC|MEMF_CLEAR
        jsr     -198(a6)                ; AllocMem
        tst.l   d0
        beq     .hang
        move.l  d0,a4
        move.l  a4,a0
        move.w  #2*PSIZE-1,d1
.fill:  move.b  #$EE,(a0)+
        dbra    d1,.fill
        move.l  a5,a6
        move.l  a4,a0
        move.l  #PSIZE,d0
        jsr     -126(a6)                ; GetDefPrefs
        moveq   #0,d7
        cmp.l   a4,d0
        bne.s   .nr
        moveq   #1,d7
.nr:
        lea     PSIZE(a4),a0
        move.l  #PSIZE,d0
        jsr     -132(a6)                ; GetPrefs
        moveq   #'D',d6
        move.l  a4,a3
        bsr.s   dump
        moveq   #'C',d6
        lea     PSIZE(a4),a3
        bsr.s   dump
        lea     m_r(pc),a0
        bsr     puts
        move.l  d7,d0
        bsr     hexb
        moveq   #10,d0
        bsr     putc
        lea     m_end(pc),a0
        bsr     puts
.hang:  bra.s   .hang

; dump(a3 = buffer, d6 = tag letter): PSIZE bytes, 16 per line.
dump:
        moveq   #0,d5                   ; offset
.line:  lea     m_dp(pc),a0
        bsr.s   puts
        move.l  d6,d0
        bsr.s   putc
        moveq   #' ',d0
        bsr.s   putc
        move.l  d5,d0
        bsr.s   hexb
        moveq   #15,d4
.byte:  cmp.w   #PSIZE,d5
        bge.s   .eol
        moveq   #' ',d0
        bsr.s   putc
        moveq   #0,d0
        move.b  (a3)+,d0
        bsr.s   hexb
        addq.w  #1,d5
        dbra    d4,.byte
.eol:   moveq   #10,d0
        bsr.s   putc
        cmp.w   #PSIZE,d5
        blt.s   .line
        rts

; hexb(d0.b): two hex digits.
hexb:   move.l  d0,-(sp)
        lsr.b   #4,d0
        bsr.s   .dig
        move.l  (sp)+,d0
.dig:   and.w   #$F,d0
        move.b  digits(pc,d0.w),d0
        bra.s   putc
digits: dc.b    "0123456789ABCDEF"

puts:   move.b  (a0)+,d0
        beq.s   .ret
        bsr.s   putc
        bra.s   puts
.ret:   rts

putc:   movem.l d0/d2,-(sp)
        move.w  #$4000,d2
.wt:    btst    #13-8,SERDATR
        bne.s   .tx
        dbra    d2,.wt
.tx:    and.w   #$FF,d0
        or.w    #$100,d0
        move.w  d0,SERDAT
        movem.l (sp)+,d0/d2
        rts

intname: dc.b   "intuition.library",0
m_dp:    dc.b   "DP ",0
m_r:     dc.b   "DP R ",0
m_end:   dc.b   "DP END",10,0
        even
