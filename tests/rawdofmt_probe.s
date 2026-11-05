; tests/rawdofmt_probe.s - HUNK test executable (TEST ASSET, NOT ROM code).
; Black-box probe "exec RawDoFmt (LVO -522)" (docs/analysis/exec-rawdofmt-v34.md §8). Run from the
; startup-sequence of a floppy (tests/rawdofmt_probe.sh). Results go to a memory buffer whose bounds are printed on
; the direct serial port (SERDAT) before "RDP fin"; the harness reads it through gdb (the emulated serial link loses
; characters under load) and tests/rawdofmt_check.py compares it with the expected values. The probe then waits
; forever so that the buffer stays valid. The case table comes from rawdofmt_check.py ("rawdofmt_cases.i").
; One line per case: "V<n> o=<output bytes up to the first $AA> r=<A1 after - A1 before> q=<D0 after - A1 before>
; x=<registers changed among d2-d7/a2-a6, or ->" (hex), plus n= (count), rec= (records), eb=, s= (stack depth).
; Nothing here uses RawDoFmt to print.
; Assembly: vasmm68k_mot -Fhunkexe -kick1hunks -nosym -m68000 -I <dir of rawdofmt_cases.i> tests/rawdofmt_probe.s
; Authored code; public interfaces only (exec AutoDocs, exec.library .fd).

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018
SERPER   EQU $DFF032
LVO_RawDoFmt EQU -522    ; exec LVOs checked against AROS rom/exec/exec.conf
LVO_Disable  EQU -120
LVO_Enable   EQU -126
LVO_Wait     EQU -318
LVO_AllocMem EQU -198

W_STR    EQU 0           ; strings of the case table (64 bytes)
W_FMT    EQU 64          ; format string, zeroed before each case (64 bytes)
W_DATA   EQU 128         ; data stream (64 bytes)
W_OUT    EQU 192         ; output buffer, $AA-filled (1024 bytes)
OUTSZ    EQU 1024
W_STK    EQU 1216        ; stack area for the depth test (256 bytes)
STKSZ    EQU 256
W_ZERO   EQU 1472        ; zeroed area for the tolerance PutChProcs (64 bytes)
W_REC    EQU 1536        ; PutChProc records (512 bytes)
WORKSZ   EQU 2048
OBUFSZ   EQU 32768

K_STORE  EQU 0           ; case kinds, see rawdofmt_check.py
K_COUNT  EQU 1
K_A6ODD  EQU 2
K_REC    EQU 3
K_BUMP   EQU 4
K_TOLD0  EQU 5
K_TOLA1  EQU 10
K_STACK  EQU 11
K_ZERO0  EQU 12
K_NULLF  EQU 13

MSG             macro
                lea     \1(pc),a0
                bsr     puts
                endm

                section code,code
_start:
                movem.l d2-d7/a2-a6,-(sp)
                move.w  #372,SERPER
                move.l  4.w,a6
                lea     ebase(pc),a0
                move.l  a6,(a0)
                move.l  a6,d0
                add.l   #LVO_RawDoFmt,d0
                move.l  d0,v_vec-ebase(a0)
                move.l  #WORKSZ,d0
                move.l  #$10001,d1
                jsr     LVO_AllocMem(a6)
                lea     work(pc),a0
                move.l  d0,(a0)
                beq     .out
                move.l  d0,a5
                move.l  #OBUFSZ,d0
                move.l  #$10001,d1
                jsr     LVO_AllocMem(a6)
                lea     optr(pc),a0
                move.l  d0,(a0)
                move.l  d0,obuf-optr(a0)
                beq     .out
                lea     strs(pc),a0
                move.l  a5,a1
                moveq   #STRSZ-1,d0
.cs:            move.b  (a0)+,(a1)+
                dbra    d0,.cs
                MSG     m_start
                bsr     t_cases
                MSG     m_end
                moveq   #1,d3                ; "RDP buf=<start> end=<end>" twice, then "RDP fin", on the serial port
.sb:            lea     m_buf(pc),a0
                bsr     sputs
                move.l  obuf(pc),d0
                bsr     shex8
                lea     m_bend(pc),a0
                bsr     sputs
                move.l  optr(pc),d0
                bsr     shex8
                moveq   #10,d1
                bsr     sputc
                dbra    d3,.sb
                lea     m_end(pc),a0
                bsr     sputs
                move.l  4.w,a6               ; the buffer must stay valid until the harness has read it
                moveq   #0,d0
                jsr     LVO_Wait(a6)
.out:           movem.l (sp)+,d2-d7/a2-a6
                moveq   #0,d0
                rts

; --- every case of the table: a3 = table cursor, a5 = work block, d7 = case number
t_cases:        lea     cases(pc),a3
                move.l  work(pc),a5
                moveq   #0,d7
.next:          move.w  (a3)+,d0
                bmi     .done
                lea     kind(pc),a0
                move.w  d0,(a0)
                lea     W_FMT(a5),a0         ; format area and data stream zeroed
                moveq   #31,d0
.z:             clr.l   (a0)+
                dbra    d0,.z
                move.w  (a3)+,d0             ; format bytes
                move.w  (a3)+,d6             ; data items
                lea     W_FMT(a5),a0
                bra.s   .fe
.f:             move.b  (a3)+,(a0)+
.fe:            dbra    d0,.f
                move.l  a3,d0
                addq.l  #1,d0
                and.b   #$FE,d0
                move.l  d0,a3
                lea     W_DATA(a5),a0
                bra.s   .de
.d:             move.w  (a3)+,d0             ; 0 word, 1 long, 2 string pointer, 3 BPTR to a string
                move.l  (a3)+,d1
                tst.w   d0
                bne.s   .d1
                move.w  d1,(a0)+
                bra.s   .de
.d1:            cmp.w   #2,d0
                blo.s   .dl
                add.l   a5,d1
                cmp.w   #3,d0
                bne.s   .dl
                lsr.l   #2,d1
.dl:            move.l  d1,(a0)+
.de:            dbra    d6,.d
                lea     W_OUT(a5),a0         ; output buffer to $AA
                move.w  #OUTSZ/4-1,d0
.o:             move.l  #$AAAAAAAA,(a0)+
                dbra    d0,.o
                lea     W_ZERO(a5),a0
                moveq   #15,d0
.zz:            clr.l   (a0)+
                dbra    d0,.zz
                bsr     setup
                move.w  kind(pc),d0
                cmp.w   #K_ZERO0,d0
                beq.s   .zero0
                cmp.w   #K_STACK,d0
                beq.s   .stack
                bsr     docall
                bra.s   .print
.zero0:         move.l  ebase(pc),a6         ; "Z\0" at address 0 for the call only
                jsr     LVO_Disable(a6)
                move.w  0.w,d6
                move.w  #$5A00,0.w
                bsr     docall
                move.w  d6,0.w
                move.l  ebase(pc),a6
                jsr     LVO_Enable(a6)
                bra.s   .print
.stack:         lea     W_STK(a5),a0
                move.w  #STKSZ/4-1,d0
.sf:            move.l  #$5A5A5A5A,(a0)+
                dbra    d0,.sf
                move.l  ebase(pc),a6
                jsr     LVO_Disable(a6)
                bsr     docall
                move.l  ebase(pc),a6
                jsr     LVO_Enable(a6)
.print:         bsr     report
                addq.w  #1,d7
                bra     .next
.done:          rts

; setup: arguments of the call from the case kind (a5 = work block)
setup:          lea     v_fmt(pc),a0
                lea     W_FMT(a5),a1
                move.l  a1,(a0)+             ; v_fmt
                lea     W_DATA(a5),a1
                move.l  a1,(a0)+             ; v_data
                lea     put_store(pc),a1
                move.l  a1,(a0)+             ; v_put
                lea     W_OUT(a5),a1
                move.l  a1,(a0)+             ; v_a3
                move.l  ebase(pc),(a0)+      ; v_a6
                lea     W_REC(a5),a1
                move.l  a1,(a0)+             ; v_rec
                lea     W_OUT(a5),a1
                move.l  a1,(a0)+             ; v_rout
                lea     W_STK+STKSZ(a5),a1
                move.l  a1,(a0)+             ; v_stop
                lea     W_OUT+OUTSZ-1(a5),a1
                move.l  a1,(a0)+             ; v_oend
                lea     v_fmt(pc),a0
                move.w  kind(pc),d0
                cmp.w   #K_COUNT,d0
                bne.s   .1
                clr.l   W_OUT(a5)
                lea     put_count(pc),a1
                move.l  a1,v_put-v_fmt(a0)
.1:             cmp.w   #K_A6ODD,d0
                bne.s   .2
                move.l  #$12345678,v_a6-v_fmt(a0)
.2:             cmp.w   #K_REC,d0
                bne.s   .3
                lea     put_rec(pc),a1
                move.l  a1,v_put-v_fmt(a0)
.3:             cmp.w   #K_BUMP,d0
                bne.s   .4
                lea     put_bump(pc),a1
                move.l  a1,v_put-v_fmt(a0)
.4:             cmp.w   #K_TOLD0,d0
                blo.s   .5
                cmp.w   #K_TOLA1,d0
                bhi.s   .5
                sub.w   #K_TOLD0,d0
                add.w   d0,d0
                lea     tolt(pc),a1
                add.w   0(a1,d0.w),a1
                move.l  a1,v_put-v_fmt(a0)
.5:             cmp.w   #K_NULLF,kind-v_fmt(a0)
                bne.s   .6
                clr.l   v_fmt-v_fmt(a0)
.6:             rts

; docall: RawDoFmt through the library vector with markers in d0-d7/a4/a5; exit registers into v_out
; (d0-d7, a0-a6). For K_STACK the call runs on the $5A-filled area. Preserves d2-d7/a2-a6.
docall:         movem.l d2-d7/a2-a6,-(sp)
                lea     v_osp(pc),a0
                move.l  sp,(a0)
                cmp.w   #K_STACK,kind-v_osp(a0)
                bne.s   .s
                move.l  v_stop(pc),sp
.s:             move.l  sp,v_csp-v_osp(a0)
                pea     .ret(pc)
                move.l  v_vec(pc),-(sp)
                movem.l mk(pc),d0-d7/a4-a5
                move.l  v_fmt(pc),a0
                move.l  v_data(pc),a1
                move.l  v_put(pc),a2
                move.l  v_a3(pc),a3
                move.l  v_a6(pc),a6
                rts                          ; into the vector; RawDoFmt returns to .ret
.ret:           move.l  a4,-(sp)
                lea     v_out(pc),a4
                movem.l d0-d7/a0-a3,(a4)
                move.l  (sp)+,48(a4)
                move.l  a5,52(a4)
                move.l  a6,56(a4)
                move.l  v_osp(pc),sp
                movem.l (sp)+,d2-d7/a2-a6
                rts

; report: one line for the case just run (d7 = case number, a5 = work block)
report:         moveq   #'V',d1
                bsr     putc
                move.l  d7,d0
                bsr     pdecu0
                move.w  kind(pc),d0
                cmp.w   #K_COUNT,d0
                beq.s   .cnt
                cmp.w   #K_BUMP,d0
                beq     .bump
                MSG     m_o
                lea     W_OUT(a5),a2
                move.w  #OUTSZ-1,d2
.ol:            move.b  (a2)+,d0
                cmp.b   #$AA,d0
                beq.s   .oe
                bsr     phex2
                dbra    d2,.ol
.oe:            bra.s   .com
.cnt:           MSG     m_n
                move.l  W_OUT(a5),d0
                bsr     phex8
.com:           MSG     m_r
                lea     v_out(pc),a2
                move.l  36(a2),d0            ; a1 after - data start
                sub.l   v_data(pc),d0
                bsr     phex8
                MSG     m_q
                move.l  (a2),d0
                sub.l   v_data(pc),d0
                bsr     phex8
                MSG     m_x
                bsr     regs
                move.w  kind(pc),d0
                cmp.w   #K_REC,d0
                beq.s   .rec
                cmp.w   #K_STACK,d0
                beq.s   .stk
.eol:           moveq   #10,d1
                bra     putc
.rec:           MSG     m_eb                 ; per call: d0, a3 - entry, a6, caller's SP - SP, a1 - data start
                move.l  ebase(pc),d0
                bsr     phex8
                MSG     m_rec
                lea     W_REC(a5),a2
.rl:            cmp.l   v_rec(pc),a2
                bhs.s   .eol
                move.l  (a2)+,d0
                bsr     phex8
                bsr     comma
                move.l  (a2)+,d0
                sub.l   v_a3(pc),d0
                bsr     phex8
                bsr     comma
                move.l  (a2)+,d0
                bsr     phex8
                bsr     comma
                move.l  v_csp(pc),d0
                sub.l   (a2)+,d0
                bsr     phex8
                bsr     comma
                move.l  (a2)+,d0
                sub.l   v_data(pc),d0
                bsr     phex8
                moveq   #';',d1
                bsr     putc
                bra.s   .rl
.stk:           MSG     m_s                  ; depth = top of the area - lowest byte written
                lea     W_STK(a5),a2
                moveq   #0,d0
.sl:            cmp.b   #$5A,(a2)+
                bne.s   .sd
                addq.w  #1,d0
                cmp.w   #STKSZ,d0
                blo.s   .sl
.sd:            neg.w   d0
                add.w   #STKSZ,d0
                bsr     phex8
                bra     .eol
.bump:          MSG     m_n                  ; number of calls, then each A3 seen - entry A3
                move.l  v_rec(pc),d0
                lea     W_REC(a5),a2
                sub.l   a2,d0
                lsr.l   #2,d0
                bsr     phex8
                MSG     m_rec
.bl:            cmp.l   v_rec(pc),a2
                bhs     .com
                move.l  (a2)+,d0
                sub.l   v_a3(pc),d0
                bsr     phex8
                bsr     comma
                bra.s   .bl

; regs: names of the registers among d2-d7/a2-a6 whose exit value differs from the entry value, or "-"
regs:           movem.l d2-d4/a2-a3,-(sp)
                lea     v_out+8(pc),a2       ; d2 after
                lea     mk+8(pc),a3          ; d2 marker
                moveq   #0,d3                ; changed count
                moveq   #2,d2
.dl:            cmpm.l  (a2)+,(a3)+
                beq.s   .dn
                moveq   #'d',d4
                bsr.s   .name
.dn:            addq.w  #1,d2
                cmp.w   #8,d2
                blo.s   .dl
                lea     v_out+40(pc),a2      ; a2 after
                moveq   #2,d2
                move.l  v_put(pc),d0
                bsr.s   .acmp
                move.l  v_a3(pc),d0
                bsr.s   .acmp
                move.l  mk+32(pc),d0
                bsr.s   .acmp
                move.l  mk+36(pc),d0
                bsr.s   .acmp
                move.l  v_a6(pc),d0
                bsr.s   .acmp
                tst.w   d3
                bne.s   .r
                moveq   #'-',d1
                bsr     putc
.r:             movem.l (sp)+,d2-d4/a2-a3
                rts
.acmp:          cmp.l   (a2)+,d0
                beq.s   .an
                moveq   #'a',d4
                bsr.s   .name
.an:            addq.w  #1,d2
                rts
.name:          tst.w   d3
                beq.s   .nf
                bsr     comma
.nf:            move.b  d4,d1
                bsr     putc
                moveq   #'0',d1
                add.b   d2,d1
                bsr     putc
                addq.w  #1,d3
                rts

; --- PutChProcs
put_store:      cmp.l   v_oend(pc),a3        ; bounded: a runaway padding must not overwrite the probe
                bhs.s   .x
                move.b  d0,(a3)+
.x:             rts
put_count:      addq.l  #1,(a3)
                rts
put_rec:        move.l  a1,d1                ; records d0, a3, a6, sp, a1; the byte goes to v_rout, A3 untouched
                lea     v_rec(pc),a0
                move.l  (a0),a1
                move.l  d0,(a1)+
                move.l  a3,(a1)+
                move.l  a6,(a1)+
                move.l  sp,(a1)+
                move.l  d1,(a1)+
                move.l  a1,(a0)
                move.l  v_rout(pc),a1
                move.b  d0,(a1)+
                move.l  a1,v_rout-v_rec(a0)
                rts
put_bump:       lea     v_rec(pc),a0
                move.l  (a0),a1
                move.l  a3,(a1)+
                move.l  a1,(a0)
                addq.l  #1,a3
                rts
tolt:           dc.w    put_td0-tolt,put_td1-tolt,put_td4-tolt,put_td7-tolt,put_ta0-tolt,put_ta1-tolt
put_td0:        move.b  d0,(a3)+
                move.l  #$DEAD0000,d0
                rts
put_td1:        move.b  d0,(a3)+
                move.l  #$DEAD0000,d1
                rts
put_td4:        move.b  d0,(a3)+
                move.l  #$DEAD0000,d4
                rts
put_td7:        move.b  d0,(a3)+
                move.l  #$DEAD0000,d7
                rts
put_ta0:        move.b  d0,(a3)+
                move.l  work(pc),a0
                lea     W_ZERO(a0),a0
                rts
put_ta1:        move.b  d0,(a3)+
                move.l  work(pc),a1
                lea     W_ZERO(a1),a1
                rts

; --- output helpers (memory buffer, read back by the harness through gdb)
comma:          moveq   #',',d1
                bra.s   putc
pdecu0:         and.l   #$FFFF,d0
pdecu:          divu    #10,d0               ; d0.l unsigned (< 655360), in decimal
                move.l  d0,-(sp)
                and.l   #$FFFF,d0
                beq.s   .d
                bsr.s   pdecu
.d:             move.l  (sp)+,d0
                swap    d0
                add.b   #'0',d0
                move.b  d0,d1
; putc(d1.b): appended to the output buffer. Preserves everything.
putc:           movem.l a0-a1,-(sp)
                lea     optr(pc),a1
                move.l  (a1),a0
                move.b  d1,(a0)+
                move.l  a0,(a1)
                movem.l (sp)+,a0-a1
                rts
; sputc(d1.b): to the serial port. Preserves everything.
sputc:          move.w  d0,-(sp)
.w:             move.w  SERDATR,d0
                btst    #13,d0
                beq.s   .w
                and.w   #$FF,d1
                or.w    #$100,d1
                move.w  d1,SERDAT
                move.w  (sp)+,d0
                rts
sputs:          move.b  (a0)+,d1
                beq.s   .e
                bsr.s   sputc
                bra.s   sputs
.e:             rts
shex8:          moveq   #7,d2
.l:             rol.l   #4,d0
                move.w  d0,d1
                and.w   #$F,d1
                move.b  hexd(pc,d1.w),d1
                bsr.s   sputc
                dbra    d2,.l
                rts
phex8:          swap    d0
                bsr.s   phex4
                swap    d0
phex4:          move.w  d0,-(sp)
                lsr.w   #8,d0
                bsr.s   phex2
                move.w  (sp)+,d0
phex2:          move.w  d0,-(sp)
                lsr.b   #4,d0
                bsr.s   .n
                move.w  (sp)+,d0
.n:             move.w  d0,-(sp)
                and.w   #$F,d0
                move.b  hexd(pc,d0.w),d1
                bsr     putc
                move.w  (sp)+,d0
                rts
hexd:           dc.b    "0123456789ABCDEF"
puts:           move.b  (a0)+,d1
                beq.s   .e
                bsr     putc
                bra.s   puts
.e:             rts

                include "rawdofmt_cases.i"

m_start:        dc.b    10,"RDP debut",10,0
m_end:          dc.b    "RDP fin",10,0
m_buf:          dc.b    "RDP buf=",0
m_bend:         dc.b    " end=",0
m_o:            dc.b    " o=",0
m_n:            dc.b    " n=",0
m_r:            dc.b    " r=",0
m_q:            dc.b    " q=",0
m_x:            dc.b    " x=",0
m_eb:           dc.b    " eb=",0
m_rec:          dc.b    " rec=",0
m_s:            dc.b    " s=",0
                even

ebase:          dc.l    0
v_vec:          dc.l    0
work:           dc.l    0
optr:           dc.l    0
obuf:           dc.l    0
kind:           dc.w    0
v_fmt:          dc.l    0
v_data:         dc.l    0
v_put:          dc.l    0
v_a3:           dc.l    0
v_a6:           dc.l    0
v_rec:          dc.l    0
v_rout:         dc.l    0
v_stop:         dc.l    0
v_oend:         dc.l    0
v_osp:          dc.l    0
v_csp:          dc.l    0
mk:             dc.l    $11110000,$11110001,$11110002,$11110003,$11110004,$11110005,$11110006,$11110007
                dc.l    $11110024,$11110025
v_out:          ds.l    15
