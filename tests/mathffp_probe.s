; tests/mathffp_probe.s - HUNK test executable (TEST ASSET, NOT ROM code).
; Black-box probe "mathffp.library" (docs/analysis/mathffp-v34.md §8). Run from the startup-sequence of a floppy
; (tests/mathffp_probe.sh). Results go to a memory buffer whose bounds are printed on the direct serial port
; (SERDAT) before "MFP fin"; the harness reads it through gdb (the emulated serial link loses characters under load)
; and tests/mathffp_check.py compares it with the spec. The probe then waits forever so that the buffer stays valid.
; The case table comes from mathffp_check.py ("mathffp_cases.i"): kind.w, LVO.w, D0.l, D1.l.
; One line per case: "C<nnn> r=<D0> f=<N Z V C or .> d1=<D1> x=<registers changed among d2-d7/a0-a6, sp, or ->"
; (+ " s=<stack depth>" for the stack cases), or "C<nnn> TRAP" when the call took the zero-divide trap.
; Then the library lines PRE, B1..B8 (spec §7 V13). Nothing here uses mathffp to print.
; Assembly: vasmm68k_mot -Fhunkexe -kick1hunks -nosym -m68000 -I <dir of mathffp_cases.i> tests/mathffp_probe.s
; Authored code; public interfaces only (exec AutoDocs, exec.library and mathffp_lib .fd).

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018
SERPER   EQU $DFF032
LVO_Forbid      EQU -132     ; exec LVOs checked against AROS rom/exec/exec.conf
LVO_Permit      EQU -138
LVO_Disable     EQU -120
LVO_Enable      EQU -126
LVO_AllocMem    EQU -198
LVO_FindName    EQU -276
LVO_FindTask    EQU -294
LVO_Wait        EQU -318
LVO_CloseLibrary EQU -414
LVO_OpenLibrary EQU -552
LVO_Expunge     EQU -18      ; library vectors
LVO_Null        EQU -24
EB_LIBLIST      EQU 378      ; ExecBase.LibList (exec/execbase.i)
TC_TRAPCODE     EQU 50       ; struct Task tc_TrapCode (exec/tasks.i)
LIB_FLAGS       EQU 14
LIB_NEGSIZE     EQU 16
LIB_POSSIZE     EQU 18
LIB_VERSION     EQU 20
LIB_REVISION    EQU 22
LIB_IDSTRING    EQU 24
LIB_OPENCNT     EQU 32

K_PLAIN  EQU 0               ; case kinds, see mathffp_check.py
K_STACK  EQU 1
K_A6Z    EQU 2
K_CCR    EQU 3
K_TRAP   EQU 4
STKSZ    EQU 256
OBUFSZ   EQU 32768
NULLMARK EQU $5A5A1234

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
                move.l  #OBUFSZ,d0
                move.l  #$10001,d1
                jsr     LVO_AllocMem(a6)
                lea     optr(pc),a0
                move.l  d0,(a0)
                move.l  d0,obuf-optr(a0)
                beq     .out
                MSG     m_start
                bsr     t_pre
                bsr     t_open
                tst.l   base
                beq.s   .fin
                bsr     t_cases
                bsr     t_lib
.fin:           MSG     m_end
                moveq   #1,d3                ; "MFP buf=<start> end=<end>" twice, then "MFP fin", on the serial port
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
                move.l  ebase(pc),a6         ; the buffer must stay valid until the harness has read it
                moveq   #0,d0
                jsr     LVO_Wait(a6)
.out:           movem.l (sp)+,d2-d7/a2-a6
                moveq   #0,d0
                rts

; --- PRE: state at rest, before the probe opens the library (spec §1)
t_pre:          MSG     m_pre
                bsr     listed
                move.l  d0,a2
                MSG     m_listed
                moveq   #1,d0
                move.l  a2,d1
                bne.s   .l
                moveq   #0,d0
.l:             bsr     phex8
                move.l  a2,d0
                beq.s   .e
                bsr     cntflags
.e:             bra     nl

; --- B1 Open(0) with the base fields, B3 Open(35)
t_open:         move.l  ebase(pc),a6
                lea     libname(pc),a1
                moveq   #0,d0
                jsr     LVO_OpenLibrary(a6)
                lea     base(pc),a0
                move.l  d0,(a0)
                MSG     m_b1
                move.l  base(pc),d0
                sne     d0
                and.l   #1,d0
                bsr     phex8
                move.l  base(pc),d0
                beq     nl
                move.l  d0,a2
                bsr     cntflags
                MSG     m_ver
                move.w  LIB_VERSION(a2),d0
                bsr     phex4
                MSG     m_rev
                move.w  LIB_REVISION(a2),d0
                bsr     phex4
                MSG     m_neg
                move.w  LIB_NEGSIZE(a2),d0
                bsr     phex4
                MSG     m_pos
                move.w  LIB_POSSIZE(a2),d0
                bsr     phex4
                MSG     m_type
                move.b  8(a2),d0
                bsr     phex2
                MSG     m_pri
                move.b  9(a2),d0
                bsr     phex2
                MSG     m_id
                move.l  LIB_IDSTRING(a2),d0
                beq.s   .noid
                move.l  d0,a3
                moveq   #63,d2
.id:            move.b  (a3)+,d0
                beq.s   .noid
                bsr     phex2
                dbra    d2,.id
.noid:          bsr     nl
                move.l  ebase(pc),a6         ; B3: version 35 refused
                lea     libname(pc),a1
                moveq   #35,d0
                jsr     LVO_OpenLibrary(a6)
                move.l  d0,d2
                MSG     m_b3
                move.l  d2,d0
                bsr     phex8
                move.l  base(pc),a2
                bsr     cntflags
                bra     nl

; --- every case of the table: a3 = table cursor, d7 = case number
t_cases:        move.l  ebase(pc),a6         ; task trap handler for the zero-divide cases
                sub.l   a1,a1
                jsr     LVO_FindTask(a6)
                move.l  d0,a0
                lea     oldtrap(pc),a1
                move.l  TC_TRAPCODE(a0),(a1)
                lea     trap_h(pc),a1
                move.l  a1,TC_TRAPCODE(a0)
                lea     cases,a3
                moveq   #0,d7
.next:          move.w  (a3)+,d0
                bmi.s   .done
                lea     kind(pc),a0
                move.w  d0,(a0)
                move.w  (a3)+,d0
                ext.l   d0
                add.l   base(pc),d0
                move.l  d0,v_vec-kind(a0)
                lea     rin(pc),a1           ; D0/D1 from the table, markers elsewhere, A6 = base (0 for K_A6Z)
                move.l  (a3)+,(a1)+
                move.l  (a3)+,(a1)+
                lea     mk(pc),a2
                moveq   #11,d0
.mk:            move.l  (a2)+,(a1)+
                dbra    d0,.mk
                move.l  base(pc),(a1)
                move.w  kind(pc),d0
                cmp.w   #K_A6Z,d0
                bne.s   .a6
                clr.l   (a1)
.a6:            lea     v_ccr(pc),a0
                clr.w   (a0)
                move.w  kind(pc),d0
                cmp.w   #K_CCR,d0
                bne.s   .cc
                move.w  #$1F,(a0)
.cc:            bsr     docall
                bsr     report
                addq.w  #1,d7
                bra.s   .next
.done:          move.l  ebase(pc),a6
                sub.l   a1,a1
                jsr     LVO_FindTask(a6)
                move.l  d0,a0
                move.l  oldtrap(pc),TC_TRAPCODE(a0)
                rts

; docall: one call through v_vec with the registers of rin and the entry CCR v_ccr; exit registers into v_out,
; flags into f_n/f_z/f_v/f_c, SP after the return into v_rsp. K_STACK: the call runs on a $5A-filled area, with
; task switching off. Preserves d2-d7/a2-a6.
docall:         movem.l d2-d7/a2-a6,-(sp)
                lea     trapped(pc),a0
                clr.b   (a0)
                lea     v_osp(pc),a0
                move.l  sp,(a0)
                move.w  kind(pc),d0
                cmp.w   #K_STACK,d0
                bne.s   .s
                lea     stk(pc),a1
                move.w  #STKSZ/4-1,d0
.sf:            move.l  #$5A5A5A5A,(a1)+
                dbra    d0,.sf
                move.l  ebase(pc),a6
                jsr     LVO_Disable(a6)
                lea     stk+STKSZ(pc),sp
.s:             lea     v_csp(pc),a0
                move.l  sp,(a0)
                lea     .jsr+2(pc),a0        ; the call pushes only its return address (68000: no cache)
                move.l  v_vec(pc),(a0)
                movem.l rin(pc),d0-d7/a0-a6
                move.w  v_ccr(pc),ccr
.jsr:           dc.w    $4EB9                ; jsr <vector>.l
                dc.l    0
                smi     f_n
                seq     f_z
                svs     f_v
                scs     f_c
                movem.l d0-d7/a0-a6,v_out
                move.l  sp,v_rsp
dc_back:        move.l  v_osp(pc),sp
                move.w  kind(pc),d0
                cmp.w   #K_STACK,d0
                bne.s   .b
                move.l  ebase(pc),a6
                jsr     LVO_Enable(a6)
.b:             movem.l (sp)+,d2-d7/a2-a6
                rts

; trap_h: task trap handler (supervisor, stack = trap number.l then the exception frame). Zero divide (5): the
; frame's PC is replaced by trap_resume and the trap is recorded; any other trap goes to the previous handler.
trap_h:         cmp.l   #5,(sp)
                bne.s   .old
                addq.l  #4,sp
                move.l  #trap_resume,2(sp)
                st      trapped
                rte
.old:           move.l  oldtrap,-(sp)
                rts
trap_resume:    bra.s   dc_back              ; user mode again: SP back to the caller of docall

; report: one line for the case just run (d7 = case number). Preserves d2-d7/a2-a6.
report:         movem.l d2/a2-a3,-(sp)
                bsr.s   .line
                movem.l (sp)+,d2/a2-a3
                rts
.line:          moveq   #'C',d1
                bsr     putc
                move.w  d7,d0
                bsr     pdec3
                tst.b   trapped
                beq.s   .r
                MSG     m_trap
                bra     nl
.r:             MSG     m_r
                move.l  v_out(pc),d0
                bsr     phex8
                MSG     m_f
                lea     f_n(pc),a2
                lea     fnames(pc),a3
                moveq   #3,d2
.fl:            moveq   #'.',d1
                tst.b   (a2)+
                beq.s   .fn
                move.b  (a3),d1
.fn:            addq.l  #1,a3
                bsr     putc
                dbra    d2,.fl
                MSG     m_d1
                move.l  v_out+4(pc),d0
                bsr     phex8
                MSG     m_x
                bsr     regs
                move.w  kind(pc),d0
                cmp.w   #K_STACK,d0
                bne     nl
                MSG     m_s                  ; depth = top of the area - lowest byte written
                lea     stk(pc),a2
                moveq   #0,d0
.sl:            cmp.b   #$5A,(a2)+
                bne.s   .sd
                addq.w  #1,d0
                cmp.w   #STKSZ,d0
                blo.s   .sl
.sd:            neg.w   d0
                add.w   #STKSZ,d0
                bsr     phex4
                bra     nl

; regs: names of the registers among d1-d7/a0-a6 whose exit value differs from the entry value, "sp" if SP after
; the return is not the caller's, or "-"
regs:           movem.l d2-d4/a2-a3,-(sp)
                lea     v_out+4(pc),a2
                lea     rin+4(pc),a3
                moveq   #0,d3                ; changed count
                moveq   #1,d2
.l:             cmpm.l  (a2)+,(a3)+
                beq.s   .n
                tst.w   d3
                beq.s   .c
                bsr     comma
.c:             moveq   #'d',d1
                cmp.w   #8,d2
                blo.s   .dn
                moveq   #'a',d1
.dn:            bsr     putc
                moveq   #7,d1
                and.w   d2,d1
                add.b   #'0',d1
                bsr     putc
                addq.w  #1,d3
.n:             addq.w  #1,d2
                cmp.w   #15,d2
                blo.s   .l
                move.l  v_rsp(pc),d0
                cmp.l   v_csp(pc),d0
                beq.s   .sp
                tst.w   d3
                beq.s   .c2
                bsr     comma
.c2:            MSG     m_spn
                addq.w  #1,d3
.sp:            tst.w   d3
                bne.s   .r
                moveq   #'-',d1
                bsr     putc
.r:             movem.l (sp)+,d2-d4/a2-a3
                rts

; --- library vectors at the very end (spec §8.9): B2 Open(34), B4 Close, B5 Expunge (count 1), B6 Close,
; B7 Null, B8 Expunge (count 0) then FindName on the library list.
t_lib:          move.l  ebase(pc),a6
                lea     libname(pc),a1
                moveq   #34,d0
                jsr     LVO_OpenLibrary(a6)
                move.l  d0,d2
                MSG     m_b2
                cmp.l   base(pc),d2
                seq     d0
                and.l   #1,d0
                bsr     phex8
                bsr     cntl
                move.l  ebase(pc),a6         ; B4
                move.l  base(pc),a1
                jsr     LVO_CloseLibrary(a6)
                move.l  d0,d2
                MSG     m_b4
                bsr     d2cnt
                move.l  ebase(pc),a6         ; B5
                jsr     LVO_Forbid(a6)
                move.l  base(pc),a6
                jsr     LVO_Expunge(a6)
                move.l  d0,d2
                move.l  ebase(pc),a6
                jsr     LVO_Permit(a6)
                MSG     m_b5
                bsr     d2cnt
                move.l  ebase(pc),a6         ; B6
                move.l  base(pc),a1
                jsr     LVO_CloseLibrary(a6)
                move.l  d0,d2
                MSG     m_b6
                bsr     d2cnt
                move.l  base(pc),a6          ; B7
                move.l  #NULLMARK,d0
                jsr     LVO_Null(a6)
                move.l  d0,d2
                MSG     m_b7
                move.l  d2,d0
                bsr     phex8
                bsr     nl
                move.l  ebase(pc),a6         ; B8
                jsr     LVO_Forbid(a6)
                move.l  base(pc),a6
                jsr     LVO_Expunge(a6)
                move.l  d0,d2
                move.l  ebase(pc),a6
                bsr     listed
                move.l  d0,d3
                move.l  ebase(pc),a6
                jsr     LVO_Permit(a6)
                MSG     m_b8
                move.l  d2,d0
                bsr     phex8
                MSG     m_listed
                moveq   #0,d0
                tst.l   d3
                beq.s   .l
                moveq   #1,d0
.l:             bsr     phex8
                bra     nl
d2cnt:          MSG     m_d0                 ; " d0=<d2>" + count/flags/listed of the base, end of line
                move.l  d2,d0
                bsr     phex8
cntl:           move.l  base(pc),a2
                bsr     cntflags
                bsr     listed
                MSG     m_listed
                tst.l   d0
                sne     d0
                and.l   #1,d0
                bsr     phex8
                bra     nl

; listed: d0 = node of "mathffp.library" in the exec library list, or 0 (under Forbid)
listed:         move.l  a6,-(sp)
                move.l  ebase(pc),a6
                jsr     LVO_Forbid(a6)
                lea     EB_LIBLIST(a6),a0
                lea     libname(pc),a1
                jsr     LVO_FindName(a6)
                move.l  d0,-(sp)
                jsr     LVO_Permit(a6)
                move.l  (sp)+,d0
                move.l  (sp)+,a6
                rts
; cntflags(a2 = library): " cnt=<lib_OpenCnt> flags=<lib_Flags>"
cntflags:       MSG     m_cnt
                move.w  LIB_OPENCNT(a2),d0
                bsr     phex4
                MSG     m_flags
                move.b  LIB_FLAGS(a2),d0
                bra     phex2

; --- output helpers (memory buffer, read back by the harness through gdb)
nl:             moveq   #10,d1
                bra.s   putc
comma:          moveq   #',',d1
                bra.s   putc
pdec3:          and.l   #$FFFF,d0            ; three decimal digits
                divu    #100,d0
                add.b   #'0',d0
                move.b  d0,d1
                bsr.s   putc
                clr.w   d0
                swap    d0
                divu    #10,d0
                add.b   #'0',d0
                move.b  d0,d1
                bsr.s   putc
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

m_start:        dc.b    10,"MFP debut",10,0
m_end:          dc.b    "MFP fin",10,0
m_buf:          dc.b    "MFP buf=",0
m_bend:         dc.b    " end=",0
m_pre:          dc.b    "PRE",0
m_b1:           dc.b    "B1 ok=",0
m_b2:           dc.b    "B2 ok=",0
m_b3:           dc.b    "B3 d0=",0
m_b4:           dc.b    "B4",0
m_b5:           dc.b    "B5",0
m_b6:           dc.b    "B6",0
m_b7:           dc.b    "B7 d0=",0
m_b8:           dc.b    "B8 d0=",0
m_d0:           dc.b    " d0=",0
m_listed:       dc.b    " listed=",0
m_cnt:          dc.b    " cnt=",0
m_flags:        dc.b    " flags=",0
m_ver:          dc.b    " ver=",0
m_rev:          dc.b    " rev=",0
m_neg:          dc.b    " neg=",0
m_pos:          dc.b    " pos=",0
m_type:         dc.b    " type=",0
m_pri:          dc.b    " pri=",0
m_id:           dc.b    " id=",0
m_trap:         dc.b    " TRAP",0
m_r:            dc.b    " r=",0
m_f:            dc.b    " f=",0
m_d1:           dc.b    " d1=",0
m_x:            dc.b    " x=",0
m_s:            dc.b    " s=",0
m_spn:          dc.b    "sp",0
fnames:         dc.b    "NZVC"
libname:        dc.b    "mathffp.library",0
                even

ebase:          dc.l    0
base:           dc.l    0
oldtrap:        dc.l    0
optr:           dc.l    0
obuf:           dc.l    0
kind:           dc.w    0
v_vec:          dc.l    0
v_ccr:          dc.w    0
v_osp:          dc.l    0
v_csp:          dc.l    0
v_rsp:          dc.l    0
f_n:            dc.b    0
f_z:            dc.b    0
f_v:            dc.b    0
f_c:            dc.b    0
trapped:        dc.b    0
                even
mk:             dc.l    $11110002,$11110003,$11110004,$11110005,$11110006,$11110007
                dc.l    $11110008,$11110009,$1111000A,$1111000B,$1111000C,$1111000D
rin:            ds.l    15                   ; d0-d7/a0-a6 at entry
v_out:          ds.l    15                   ; d0-d7/a0-a6 after the return
stk:            ds.b    STKSZ

                include "mathffp_cases.i"
