; tests/explvo_probe.s - the LVOs specified last (implementation track, authored from
; docs/analysis/exec-partial-lvos-v34.md §2.4, §3, §4.6, §5, §6, graphics-raster-v34.md §10 and intuition-misc-v34.md
; §6c). Prints on the serial line, one line per group, values in hex:
;   "EXP SIG <init SigAlloc> <init TrapAlloc> <AllocSignal -1> <-1> <$FF> <4> <20> <SigRecvd bit 20> <20 again>
;            <SigAlloc> <AllocTrap -1> <-1> <15> <20, d1 0> <20, d1 $00100000> <TrapAlloc> <SigAlloc after
;            FreeSignal(-1)>"   (a fresh task made by AddTask, its tc_SigAlloc/tc_TrapAlloc preset to garbage)
;   "EXP CC <GetCC with d0 = $C0000000 and CCR $15>"
;   "EXP LIST <1 if Insert(bogus, X, &lh_Tail) gives N1 N2 X and lh_TailPred = X>"
;   "EXP TASK <1 if FindTask(own name) = own task>"
;   "EXP LIB <base mod 4> <NegSize> <PosSize>"     MakeLibrary, 5 long vectors, dataSize 34
;   "EXP IS <16 bytes after InitStruct size 16> <the last byte with size 15>"
;   "EXP BM <BytesPerRow> <Rows> <Depth> <Flags,pad> <Planes[0]> <d1>"   InitBitMap on a $AA-filled BitMap
;   "EXP REM <key after FreeRemember(FALSE)> <AvailMem drop>"   two AllocRemember (100, 50) then FALSE
;   "EXP PRIV <1 if graphicsPrivate1 returns a6>"
;   "EXP fin"
; Run as a CLI command; tests/explvo_probe.sh checks every line.

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018

LVO_InitStruct   EQU -78
LVO_MakeLibrary  EQU -84
LVO_Forbid       EQU -132
LVO_Permit       EQU -138
LVO_AllocMem     EQU -198
LVO_FreeMem      EQU -210
LVO_AvailMem     EQU -216
LVO_Insert       EQU -234
LVO_AddTask      EQU -282
LVO_FindTask     EQU -294
LVO_SetSignal    EQU -306
LVO_Wait         EQU -318
LVO_Signal       EQU -324
LVO_AllocSignal  EQU -330
LVO_FreeSignal   EQU -336
LVO_AllocTrap    EQU -342
LVO_CloseLibrary EQU -414
LVO_OpenLibrary  EQU -552
LVO_GetCC        EQU -528
LVO_InitBitMap   EQU -390
LVO_GfxPrivate1  EQU -642
LVO_AllocRemember EQU -396
LVO_FreeRemember EQU -408
MEMF_PUBLIC      EQU 1
MEMF_CLEAR       EQU $10000
TC_SIGALLOC      EQU 18
TC_SIGRECVD      EQU 26
TC_TRAPALLOC     EQU 34
TC_SPREG         EQU 54
TC_SPLOWER       EQU 58
TC_SPUPPER       EQU 62
TC_SIZE          EQU 92
LN_NAME          EQU 10
STK              EQU 1024
SIGF_DONE        EQU $8000

                section code,code
start:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  4.w,a6
        move.l  276(a6),a0           ; ThisTask
        lea     parent(pc),a1
        move.l  a0,(a1)
        ; --- SIG: a fresh task, masks preset to garbage before AddTask
        move.l  #TC_SIZE+STK,d0
        move.l  #MEMF_PUBLIC|MEMF_CLEAR,d1
        jsr     LVO_AllocMem(a6)
        tst.l   d0
        beq     .nosig
        move.l  d0,a1
        move.b  #1,8(a1)             ; NT_TASK
        lea     cname(pc),a0
        move.l  a0,LN_NAME(a1)
        lea     TC_SIZE(a1),a0
        move.l  a0,TC_SPLOWER(a1)
        lea     TC_SIZE+STK(a1),a0
        move.l  a0,TC_SPUPPER(a1)
        move.l  a0,TC_SPREG(a1)
        move.l  #$12345678,TC_SIGALLOC(a1)
        move.w  #$1234,TC_TRAPALLOC(a1)
        lea     child(pc),a2
        sub.l   a3,a3
        jsr     LVO_AddTask(a6)
        move.l  #SIGF_DONE,d0
        jsr     LVO_Wait(a6)
        lea     m_sig(pc),a0
        bsr     puts
        lea     sigbuf(pc),a2
        moveq   #17-1,d2
.sp:    move.l  (a2)+,d0
        bsr     phex8
        dbra    d2,.sp
        bsr     nl
.nosig:
        ; --- CC
        lea     m_cc(pc),a0
        bsr     puts
        move.l  #$C0000000,d0
        move    #$15,ccr
        jsr     LVO_GetCC(a6)
        bsr     phex8
        bsr     nl
        ; --- LIST: L = N1, N2; Insert(bogus, X, &L.lh_Tail)
        lea     lst(pc),a0
        lea     4(a0),a1
        move.l  a1,(a0)              ; lh_Head = &lh_Tail
        clr.l   4(a0)
        move.l  a0,8(a0)             ; lh_TailPred = &lh_Head
        lea     n1(pc),a1
        bsr     addtail
        lea     n2(pc),a1
        bsr     addtail
        move.l  #$00000400,a0        ; bogus list argument
        lea     nx(pc),a1
        lea     lst+4(pc),a2
        jsr     LVO_Insert(a6)
        moveq   #0,d0
        lea     lst(pc),a0
        lea     n1(pc),a1
        cmp.l   (a0),a1
        bne.s   .lsto
        lea     n2(pc),a2
        cmp.l   (a1),a2
        bne.s   .lsto
        lea     nx(pc),a1
        cmp.l   (a2),a1
        bne.s   .lsto
        cmp.l   8(a0),a1
        bne.s   .lsto
        lea     4(a0),a2
        cmp.l   (a1),a2
        bne.s   .lsto
        moveq   #1,d0
.lsto:  move.l  d0,d2
        lea     m_list(pc),a0
        bsr     puts
        move.l  d2,d0
        bsr     phex8
        bsr     nl
        ; --- TASK
        move.l  parent(pc),a0
        move.l  LN_NAME(a0),a1
        jsr     LVO_FindTask(a6)
        moveq   #0,d2
        cmp.l   parent(pc),d0
        bne.s   .tko
        moveq   #1,d2
.tko:   lea     m_task(pc),a0
        bsr     puts
        move.l  d2,d0
        bsr     phex8
        bsr     nl
        ; --- LIB
        lea     vecs(pc),a0
        sub.l   a1,a1
        sub.l   a2,a2
        moveq   #34,d0
        moveq   #0,d1
        jsr     LVO_MakeLibrary(a6)
        move.l  d0,d3
        lea     m_lib(pc),a0
        bsr     puts
        move.l  d3,d0
        and.l   #3,d0
        bsr     phex8
        move.l  d3,a0
        moveq   #0,d0
        move.w  16(a0),d0
        bsr     phex8
        moveq   #0,d0
        move.w  18(a0),d0
        bsr     phex8
        bsr     nl
        ; --- IS: size 16, then size 15
        lea     m_is(pc),a0
        bsr     puts
        moveq   #16,d0
        bsr     isrun
        lea     isbuf(pc),a2
        moveq   #3,d2
.isp:   move.l  (a2)+,d0
        bsr     phex8
        dbra    d2,.isp
        moveq   #15,d0
        bsr     isrun
        moveq   #0,d0
        move.b  isbuf+15(pc),d0
        bsr     phex8
        bsr     nl
        ; --- BM / PRIV (graphics)
        lea     gfxname(pc),a1
        moveq   #0,d0
        jsr     LVO_OpenLibrary(a6)
        move.l  d0,a5
        lea     bmbuf(pc),a0
        moveq   #40/4-1,d0
.bf:    move.l  #$AAAAAAAA,(a0)+
        dbra    d0,.bf
        move.l  a5,a6
        lea     bmbuf(pc),a0
        moveq   #3,d0
        moveq   #100,d1
        move.l  #$55550032,d2
        jsr     LVO_InitBitMap(a6)
        move.l  d1,d4
        move.l  4.w,a6
        lea     m_bm(pc),a0
        bsr     puts
        lea     bmbuf(pc),a2
        moveq   #0,d0
        move.w  (a2),d0
        bsr     phex8
        move.w  2(a2),d0
        bsr     phex8
        moveq   #0,d0
        move.b  5(a2),d0
        bsr     phex8
        move.b  4(a2),d0
        lsl.w   #8,d0
        move.b  6(a2),d0
        bsr     phex8
        move.l  8(a2),d0
        bsr     phex8
        move.l  d4,d0
        bsr     phex8
        bsr     nl
        move.l  a5,a6
        jsr     LVO_GfxPrivate1(a6)
        moveq   #0,d2
        cmp.l   a5,d0
        bne.s   .pv
        moveq   #1,d2
.pv:    move.l  4.w,a6
        move.l  a5,a1
        jsr     LVO_CloseLibrary(a6)
        ; --- REM
        lea     intname(pc),a1
        moveq   #0,d0
        jsr     LVO_OpenLibrary(a6)
        move.l  d0,a5
        moveq   #0,d1
        jsr     LVO_AvailMem(a6)
        move.l  d0,d5
        lea     rkey(pc),a0
        clr.l   (a0)
        move.l  a5,a6
        moveq   #100,d0
        moveq   #0,d1
        jsr     LVO_AllocRemember(a6)
        lea     rkey(pc),a0
        moveq   #50,d0
        moveq   #0,d1
        jsr     LVO_AllocRemember(a6)
        lea     rkey(pc),a0
        moveq   #0,d0
        jsr     LVO_FreeRemember(a6)
        move.l  4.w,a6
        moveq   #0,d1
        jsr     LVO_AvailMem(a6)
        sub.l   d0,d5
        lea     m_rem(pc),a0
        bsr     puts
        move.l  rkey(pc),d0
        bsr     phex8
        move.l  d5,d0
        bsr     phex8
        bsr     nl
        move.l  a5,a1
        jsr     LVO_CloseLibrary(a6)
        lea     m_priv(pc),a0
        bsr     puts
        move.l  d2,d0
        bsr     phex8
        bsr     nl
        lea     m_fin(pc),a0
        bsr     puts
        movem.l (sp)+,d2-d7/a2-a6
        moveq   #0,d0
        rts

; isrun(d0 = size): isbuf := 16 x $FF, then InitStruct(istab, isbuf, size)
isrun:
        lea     isbuf(pc),a0
        moveq   #3,d1
.f:     move.l  #-1,(a0)+
        dbra    d1,.f
        lea     istab(pc),a1
        lea     isbuf(pc),a2
        jmp     LVO_InitStruct(a6)

; addtail(list lst, node a1)
addtail:
        lea     lst(pc),a0
        move.l  8(a0),a2             ; old TailPred
        lea     4(a0),a3
        move.l  a3,(a1)
        move.l  a2,4(a1)
        move.l  a1,(a2)
        move.l  a1,8(a0)
        rts

; child task: the §4.6 rows on itself, results in sigbuf, then Signal(parent, SIGF_DONE)
child:
        move.l  4.w,a6
        move.l  276(a6),a4
        lea     sigbuf(pc),a5
        move.l  TC_SIGALLOC(a4),(a5)+
        moveq   #0,d0
        move.w  TC_TRAPALLOC(a4),d0
        move.l  d0,(a5)+
        moveq   #-1,d0
        jsr     LVO_AllocSignal(a6)
        move.l  d0,(a5)+
        moveq   #-1,d0
        jsr     LVO_AllocSignal(a6)
        move.l  d0,(a5)+
        move.l  #$FF,d0
        jsr     LVO_AllocSignal(a6)
        move.l  d0,(a5)+
        moveq   #4,d0
        jsr     LVO_AllocSignal(a6)
        move.l  d0,(a5)+
        move.l  #$00100000,d0
        move.l  d0,d1
        jsr     LVO_SetSignal(a6)
        moveq   #20,d0
        jsr     LVO_AllocSignal(a6)
        move.l  d0,(a5)+
        move.l  TC_SIGRECVD(a4),d0
        and.l   #$00100000,d0
        move.l  d0,(a5)+
        moveq   #20,d0
        jsr     LVO_AllocSignal(a6)
        move.l  d0,(a5)+
        move.l  TC_SIGALLOC(a4),(a5)+
        moveq   #-1,d0
        jsr     LVO_AllocTrap(a6)
        move.l  d0,(a5)+
        moveq   #-1,d0
        jsr     LVO_AllocTrap(a6)
        move.l  d0,(a5)+
        moveq   #15,d0
        jsr     LVO_AllocTrap(a6)
        move.l  d0,(a5)+
        moveq   #20,d0
        moveq   #0,d1
        jsr     LVO_AllocTrap(a6)
        move.l  d0,(a5)+
        moveq   #20,d0
        move.l  #$00100000,d1
        jsr     LVO_AllocTrap(a6)
        move.l  d0,(a5)+
        moveq   #0,d0
        move.w  TC_TRAPALLOC(a4),d0
        move.l  d0,(a5)+
        moveq   #-1,d0
        jsr     LVO_FreeSignal(a6)
        move.l  TC_SIGALLOC(a4),(a5)+
        move.l  parent(pc),a1
        move.l  #SIGF_DONE,d0
        jmp     LVO_Signal(a6)       ; then returns to the task's final PC

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
        movem.l d0/d2,-(sp)
        moveq   #' ',d1
        bsr.s   putc
        moveq   #7,d2
.h:     rol.l   #4,d0
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
parent:   dc.l  0
rkey:     dc.l  0
sigbuf:   ds.l  17
lst:      ds.l  3
n1:       ds.l  4
n2:       ds.l  4
nx:       ds.l  4
isbuf:    ds.l  4
bmbuf:    ds.l  10
vecs:     dc.l  dummy,dummy,dummy,dummy,dummy,-1
; InitStruct table (exec-partial-lvos §6.1): offset 4 long $12345678, offset 10 two bytes $AB $CD, repeat $77 x3, end
istab:    dc.b  $C0,$00,$00,$04,$12,$34,$56,$78,$A1,$0A,$AB,$CD,$62,$77,$00
          even
dummy:    rts
cname:    dc.b  "explvo child",0
gfxname:  dc.b  "graphics.library",0
intname:  dc.b  "intuition.library",0
m_sig:    dc.b  "EXP SIG",0
m_cc:     dc.b  "EXP CC",0
m_list:   dc.b  "EXP LIST",0
m_task:   dc.b  "EXP TASK",0
m_lib:    dc.b  "EXP LIB",0
m_is:     dc.b  "EXP IS",0
m_bm:     dc.b  "EXP BM",0
m_rem:    dc.b  "EXP REM",0
m_priv:   dc.b  "EXP PRIV",0
m_fin:    dc.b  "EXP fin",10,0
                even
