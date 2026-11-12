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
;   "EXP OLZ <$0000 | Z after a successful OpenLibrary (Seq) << 8 | Z after a failed one>"   programs branch on the
;            flags straight after the call (Paccer's CLS: movea.l d0,a6 then beq)
;   "EXP INT6 <servers in the EXTER chain after AddIntServer> <calls of ours after one INTREQ EXTER>"   INT6 is a
;            server chain holding ciab.resource (custom-chips-v34 §3.3), so a program's server joins it
;   "EXP MACT <Menu.Flags & MIDRAWN> <MenuItem.Flags & (MENUTOGGLED|HIGHITEM|ISDRAWN)>"   flags set by hand on window
;            A's menu strip, then window B activated and A again: the activation clears them (intuition-input-menus
;            §1.11 step 3, §3.8), so 0 and 0
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
LVO_AddIntServer EQU -168
LVO_OpenWindow   EQU -204
LVO_CloseWindow  EQU -72
LVO_SetMenuStrip EQU -264
LVO_ClearMenuStrip EQU -54
LVO_ActivateWindow EQU -450
LVO_WaitTOF      EQU -270
LVO_RemIntServer EQU -174
INTB_EXTER       EQU 13
EB_IntVects      EQU $54
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
        lea     gfxname(pc),a1
        moveq   #0,d0
        jsr     LVO_OpenLibrary(a6)
        seq     d3
        move.l  d0,a1
        jsr     LVO_CloseLibrary(a6)
        lea     gfxname(pc),a1
        move.l  #999,d0              ; present but too old: fails without a load
        jsr     LVO_OpenLibrary(a6)
        seq     d4
        lea     m_olz(pc),a0
        bsr     puts
        moveq   #0,d0
        move.b  d3,d0
        lsl.w   #8,d0
        move.b  d4,d0
        bsr     phex8
        bsr     nl
        moveq   #INTB_EXTER,d0       ; INT6: our server joins the chain, then one software request of EXTER
        lea     i6is(pc),a1
        jsr     LVO_AddIntServer(a6)
        move.l  EB_IntVects+INTB_EXTER*12(a6),a0  ; iv_Data = the chain's list header
        moveq   #0,d3
.i6c:   move.l  (a0),a0
        tst.l   (a0)
        beq.s   .i6d
        addq.l  #1,d3
        bra.s   .i6c
.i6d:   lea     i6cnt(pc),a2
        move.w  #$A000,$DFF09C       ; INTREQ SET | EXTER
        move.w  #20000,d0
.i6w:   tst.l   (a2)
        dbne    d0,.i6w
        moveq   #INTB_EXTER,d0
        lea     i6is(pc),a1
        jsr     LVO_RemIntServer(a6)
        lea     m_int6(pc),a0
        bsr     puts
        move.l  d3,d0
        bsr     phex8
        move.l  i6cnt(pc),d0
        bsr     phex8
        bsr     nl
        bsr     mact
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

; mact (a6 = ExecBase): the EXP MACT line. Preserves a6.
mact:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  a6,a4                ; a4 = ExecBase
        lea     n_int(pc),a1
        moveq   #0,d0
        jsr     LVO_OpenLibrary(a6)
        move.l  d0,a5                ; a5 = IntuitionBase
        lea     gfxname(pc),a1
        moveq   #0,d0
        jsr     LVO_OpenLibrary(a6)
        move.l  d0,a3                ; a3 = GfxBase
        move.l  a5,a6
        lea     nwa(pc),a0
        jsr     LVO_OpenWindow(a6)
        move.l  d0,d6                ; d6 = A
        beq     .mx
        lea     nwb(pc),a0
        jsr     LVO_OpenWindow(a6)
        move.l  d0,d7                ; d7 = B
        beq     .mxa
        move.l  d6,a0
        lea     mmenu(pc),a1
        jsr     LVO_SetMenuStrip(a6)
        lea     mmenu(pc),a0
        or.w    #$0100,12(a0)        ; MIDRAWN
        lea     mitem(pc),a0
        or.w    #$7000,12(a0)        ; MENUTOGGLED | HIGHITEM | ISDRAWN
        move.l  d7,a0
        jsr     LVO_ActivateWindow(a6)
        bsr     mwait
        move.l  d6,a0
        jsr     LVO_ActivateWindow(a6)
        bsr     mwait
        lea     m_mact(pc),a0
        bsr     puts
        moveq   #0,d0
        move.w  mmenu+12(pc),d0
        and.w   #$0100,d0
        bsr     phex8
        moveq   #0,d0
        move.w  mitem+12(pc),d0
        and.w   #$7000,d0
        bsr     phex8
        bsr     nl
        move.l  d6,a0
        jsr     LVO_ClearMenuStrip(a6)
        move.l  d7,a0
        jsr     LVO_CloseWindow(a6)
.mxa:   move.l  d6,a0
        jsr     LVO_CloseWindow(a6)
.mx:    move.l  a4,a6
        move.l  a3,a1
        jsr     LVO_CloseLibrary(a6)
        move.l  a5,a1
        jsr     LVO_CloseLibrary(a6)
        movem.l (sp)+,d2-d7/a2-a6
        rts
mwait:                               ; 10 frames: the activations are carried out by the input task
        movem.l d2/a6,-(sp)
        move.l  a3,a6
        moveq   #10-1,d2
.mw:    jsr     LVO_WaitTOF(a6)
        dbra    d2,.mw
        movem.l (sp)+,d2/a6
        rts
i6code:   addq.l  #1,(a1)            ; a1 = is_Data = the counter
          moveq   #0,d0              ; continue the chain
          rts
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
m_olz:    dc.b  "EXP OLZ",0
m_int6:   dc.b  "EXP INT6",0
m_mact:   dc.b  "EXP MACT",0
n_int:    dc.b  "intuition.library",0
t_a:      dc.b  "A",0
t_menu:   dc.b  "M",0
t_item:   dc.b  "I",0
                even
nwa:      dc.w  20,40,200,60
          dc.b  0,1
          dc.l  0,$1000|$0002,0,0,t_a,0,0     ; ACTIVATE | WINDOWDRAG
          dc.w  0,0,0,0,1                     ; WBENCHSCREEN
nwb:      dc.w  240,40,200,60
          dc.b  0,1
          dc.l  0,$0002,0,0,t_a,0,0
          dc.w  0,0,0,0,1
mmenu:    dc.l  0
          dc.w  0,0,60,10,1                   ; MENUENABLED
          dc.l  t_menu,mitem
          dc.w  0,0,0,0
mitem:    dc.l  0
          dc.w  0,0,80,10,$0052               ; ITEMTEXT | ITEMENABLED | HIGHCOMP
          dc.l  0,mitxt,0
          dc.b  0,0
          dc.l  0
          dc.w  0
mitxt:    dc.b  0,1,1,0
          dc.w  0,0
          dc.l  0,t_item,0
                even
i6cnt:    dc.l  0
i6is:     dc.l  0,0
          dc.b  2,10
          dc.l  0,i6cnt,i6code
m_fin:    dc.b  "EXP fin",10,0
                even
