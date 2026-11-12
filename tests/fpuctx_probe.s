; tests/fpuctx_probe.s - CPU/FPU probe for OUR ROM (implementation track, authored; docs/analysis/cpu-fpu-v34.md).
; Prints on the serial line:
;   "FC ATTN <AttnFlags> CACR <cacr>"   ExecBase AttnFlags; CACR read in supervisor mode (0 on a 68000/68010)
;   "FC NOFPU"                          AttnFlags has no AFB_68881: nothing else to check
;   "FC CTX <itA> <itB> <errA> <errB> <disp>"
;                                       two tasks of the same priority (this CLI process and a subtask) each load
;                                       their own FP0-FP7 and FPCR rounding mode, busy-wait so the VBlank quantum
;                                       preempts them, then compare every register; itA/itB = rounds done, errA/errB
;                                       = rounds where a register changed, disp = ExecBase DispCount delta (§3.3)
; then "FC END". Run by tests/fpuctx_probe.sh as a CLI command from a startup-sequence. Assembled for 68020+68881;
; the main path only executes 68000 instructions until AttnFlags says otherwise.

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018

LVO_Supervisor  EQU -30
LVO_Forbid      EQU -132
LVO_Permit      EQU -138
LVO_AddTask     EQU -282
LVO_RemTask     EQU -288
EB_AttnFlags    EQU $128
EB_DispCount    EQU $11C
TC_SPLOWER      EQU 58
TC_SPUPPER      EQU 62
TC_SPREG        EQU 54
TC_SIZE         EQU 92
ROUNDS          EQU 150
SPIN            EQU 12000
MINDISP         EQU 60

                section code,code
start:
        move.l  4.w,a6
        lea     m_attn(pc),a0
        bsr     puts
        move.w  EB_AttnFlags(a6),d0
        bsr     phex4
        lea     m_cacr(pc),a0
        bsr     puts
        moveq   #0,d0
        btst    #1,EB_AttnFlags+1(a6)
        beq.s   .nocacr
        lea     rdcacr(pc),a5
        jsr     LVO_Supervisor(a6)
.nocacr:
        bsr     phex8
        bsr     nl
        btst    #4,EB_AttnFlags+1(a6)
        bne.s   .fpu
        lea     m_nofpu(pc),a0
        bsr     puts
        bra     .end
.fpu:
        move.l  EB_DispCount(a6),dispst
        lea     task(pc),a1
        move.b  #1,8(a1)             ; NT_TASK, priority 0 (as this CLI process)
        clr.b   9(a1)
        lea     tname(pc),a0
        move.l  a0,10(a1)
        lea     stack(pc),a0
        move.l  a0,TC_SPLOWER(a1)
        lea     stack_end(pc),a0
        move.l  a0,TC_SPUPPER(a1)
        move.l  a0,TC_SPREG(a1)
        lea     subtask(pc),a2
        sub.l   a3,a3
        jsr     LVO_AddTask(a6)
        moveq   #0,d7                ; worker A
        bsr     worker
        jsr     LVO_Forbid(a6)
        lea     task(pc),a1
        jsr     LVO_RemTask(a6)
        jsr     LVO_Permit(a6)
        move.l  EB_DispCount(a6),d6
        sub.l   dispst(pc),d6
        lea     m_ctx(pc),a0
        bsr     puts
        move.l  rounds(pc),d0
        bsr     phex8
        move.l  rounds+4(pc),d0
        bsr     phex8
        move.l  errs(pc),d0
        bsr     phex8
        move.l  errs+4(pc),d0
        bsr     phex8
        move.l  d6,d0
        bsr     phex8
        bsr     nl
.end:
        lea     m_end(pc),a0
        bsr     puts
        moveq   #0,d0
        rts

rdcacr:
        movec   cacr,d0
        rte

subtask:
        moveq   #1,d7                ; worker B, runs until RemTask
.again:
        bsr.s   worker
        bra.s   .again

; worker(d7 = 0 for A, 1 for B, a6 = ExecBase for A): A stops after ROUNDS rounds and MINDISP dispatches; B is
; removed by A. Each round loads FP0-FP7
; with 100*id+n+1 and FPCR with a rounding mode of its own, spins, then checks them all.
worker:
        lea     rounds(pc),a2
        lea     errs(pc),a3
        move.l  d7,d0
        lsl.l   #2,d0
        add.l   d0,a2
        add.l   d0,a3
        moveq   #$10,d5              ; FPCR: RZ for A, RM for B
        tst.l   d7
        beq.s   .rm
        moveq   #$20,d5
.rm:
        move.l  d7,d4
        mulu    #100,d4              ; d4 = 100*id
.round:
        fmove.l d5,fpcr
        move.l  d4,d0
        addq.l  #1,d0
        fmove.l d0,fp0
        addq.l  #1,d0
        fmove.l d0,fp1
        addq.l  #1,d0
        fmove.l d0,fp2
        addq.l  #1,d0
        fmove.l d0,fp3
        addq.l  #1,d0
        fmove.l d0,fp4
        addq.l  #1,d0
        fmove.l d0,fp5
        addq.l  #1,d0
        fmove.l d0,fp6
        addq.l  #1,d0
        fmove.l d0,fp7
        move.w  #SPIN-1,d0
.spin:
        dbra    d0,.spin
        moveq   #0,d3                ; d3 = 1 if anything changed
        fmove.l fpcr,d0
        cmp.l   d5,d0
        sne     d3
        move.l  d4,d1
        addq.l  #1,d1
        fmove.l fp0,d0
        bsr.s   .cmp
        fmove.l fp1,d0
        bsr.s   .cmp
        fmove.l fp2,d0
        bsr.s   .cmp
        fmove.l fp3,d0
        bsr.s   .cmp
        fmove.l fp4,d0
        bsr.s   .cmp
        fmove.l fp5,d0
        bsr.s   .cmp
        fmove.l fp6,d0
        bsr.s   .cmp
        fmove.l fp7,d0
        bsr.s   .cmp
        tst.b   d3
        beq.s   .ok
        addq.l  #1,(a3)
.ok:
        addq.l  #1,(a2)
        tst.l   d7
        bne     .round
        cmp.l   #ROUNDS,(a2)
        blo     .round
        move.l  EB_DispCount(a6),d0  ; and until the quantum switched tasks often enough (a 68040 is fast)
        sub.l   dispst(pc),d0
        cmp.l   #MINDISP,d0
        blo     .round
        rts
.cmp:
        cmp.l   d1,d0
        beq.s   .same
        st      d3
.same:
        addq.l  #1,d1
        rts

puts:
        move.b  (a0)+,d1
        beq.s   .r
        bsr.s   putc
        bra.s   puts
.r:     rts
nl:     moveq   #10,d1
        bra.s   putc
; phex8(d0.l): " XXXXXXXX"
phex8:
        move.l  d0,-(sp)
        swap    d0
        bsr.s   phex4
        move.l  (sp)+,d0
        bra.s   phex4c
; phex4(d0.w): " XXXX"
phex4:
        moveq   #' ',d1
        bsr.s   putc
phex4c:
        movem.l d0/d2,-(sp)
        moveq   #3,d2
.h:     rol.w   #4,d0
        move.w  d0,d1
        and.w   #15,d1
        add.b   #'0',d1
        cmp.b   #'9',d1
        bls.s   .o
        addq.b  #7,d1
.o:     bsr.s   putc
        dbra    d2,.h
        movem.l (sp)+,d0/d2
        rts
putc:
        move.w  d0,-(sp)
.w:     move.w  SERDATR,d0
        btst    #13,d0
        beq.s   .w
        and.w   #$FF,d1
        or.w    #$100,d1
        move.w  d1,SERDAT
        move.w  (sp)+,d0
        rts

                cnop    0,4
task:     dcb.b TC_SIZE,0
rounds:   dc.l  0,0
errs:     dc.l  0,0
dispst:   dc.l  0
stack:    dcb.b 2048,0
stack_end:
tname:    dc.b  "fpuctx B",0
m_attn:   dc.b  "FC ATTN",0
m_cacr:   dc.b  " CACR",0
m_nofpu:  dc.b  "FC NOFPU",10,0
m_ctx:    dc.b  "FC CTX",0
m_end:    dc.b  "FC END",10,0
                even
