; tests/sched_probe.s - exec scheduling details probe for OUR ROM (implementation track, authored).
; Prints on the serial line (docs/analysis/exec-scheduling-v34.md §2.3, §2.7, §8; timer-v34.md §3):
;   "SP Q <Quantum> E <Elapsed> ..."  ExecBase Quantum, then Elapsed read on 8 successive frames by a busy loop that
;                                       never waits (timer.device sets the quantum to 16 and counts Elapsed down in its
;                                       VERTB server; a dispatch reloads it)
;   "SP SIG <d0> <d0>"                 D0 returned by Signal(self, $00100000) twice: the task's tc_SigRecvd before
;                                       each call (the second one has the bit)
;   "SP SOFT <sr> <intena>"            SR and INTENAR read inside a software interrupt (Cause): SR $2000, SOFTINT
;                                       (bit 2) off in INTENA meanwhile
;   "SP ORD <letters>"                 order in which six software interrupts Caused under Disable run once Enable
;                                       lets SOFTINT in: A pri -32, B 0, C +32, D 0, E +16, F 5 (§8: highest queue
;                                       first, FIFO inside a queue, 1..15 share the 0 queue) -> CEBDFA
; then "SP END". Run by tests/sched_probe.sh as a CLI command from a startup-sequence.

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018
INTENAR  EQU $DFF01C

LVO_FindTask    EQU -294
LVO_SetSignal   EQU -306
LVO_Signal      EQU -324
LVO_Cause       EQU -180
LVO_Disable     EQU -120
LVO_Enable      EQU -126
LVO_OpenLibrary EQU -552
LVO_CloseLibrary EQU -414
LVO_WaitTOF     EQU -270
EB_Quantum      EQU $120
EB_Elapsed      EQU $122
SIGBIT          EQU $00100000

                section code,code
start:
        move.l  4.w,a6
        lea     gfxname(pc),a1
        moveq   #0,d0
        jsr     LVO_OpenLibrary(a6)
        move.l  d0,a5                ; a5 = GfxBase
        tst.l   d0
        beq     .done
        lea     m_begin(pc),a0
        bsr     puts
        lea     m_q(pc),a0
        bsr     puts
        move.w  EB_Quantum(a6),d0
        bsr     phex4
        lea     m_e(pc),a0
        bsr     puts
        moveq   #8-1,d7
        lea     elap(pc),a2
.fr:
        bsr     frame                ; busy-waits for the next frame (no Wait: no dispatch of this task)
        move.w  EB_Elapsed(a6),(a2)+
        dbra    d7,.fr
        moveq   #8-1,d7
        lea     elap(pc),a2
.pe:
        move.w  (a2)+,d0
        bsr     phex4
        dbra    d7,.pe
        bsr     nl
        moveq   #0,d0                ; Signal(self, SIGBIT) twice
        move.l  #SIGBIT,d1
        jsr     LVO_SetSignal(a6)
        sub.l   a1,a1
        jsr     LVO_FindTask(a6)
        move.l  d0,a2
        move.l  a2,a1
        move.l  #SIGBIT,d0
        jsr     LVO_Signal(a6)
        move.l  d0,d6
        move.l  a2,a1
        move.l  #SIGBIT,d0
        jsr     LVO_Signal(a6)
        move.l  d0,d5
        moveq   #0,d0
        move.l  #SIGBIT,d1
        jsr     LVO_SetSignal(a6)
        lea     m_sig(pc),a0
        bsr     puts
        move.l  d6,d0
        bsr     phex8
        move.l  d5,d0
        bsr     phex8
        bsr     nl
        lea     softis(pc),a1        ; a software interrupt notes SR and INTENAR
        jsr     LVO_Cause(a6)
        move.l  a6,-(sp)
        move.l  a5,a6
        jsr     LVO_WaitTOF(a6)
        move.l  (sp)+,a6
        lea     m_soft(pc),a0
        bsr     puts
        move.w  softsr(pc),d0
        bsr     phex4
        move.w  softena(pc),d0
        bsr     phex4
        bsr     nl
        jsr     LVO_Disable(a6)      ; six software interrupts queued while SOFTINT cannot be taken
        lea     ordis(pc),a2
        moveq   #6-1,d7
.cq:    move.l  a2,a1
        jsr     LVO_Cause(a6)
        lea     IS_SZ(a2),a2
        dbra    d7,.cq
        jsr     LVO_Enable(a6)
        move.l  a6,-(sp)
        move.l  a5,a6
        jsr     LVO_WaitTOF(a6)
        move.l  (sp)+,a6
        lea     m_ord(pc),a0
        bsr     puts
        moveq   #' ',d1
        bsr     putc
        lea     ordbuf(pc),a0
        bsr     puts
        bsr     nl
        lea     m_end(pc),a0
        bsr     puts
        move.l  a5,a1
        jsr     LVO_CloseLibrary(a6)
.done:
        moveq   #0,d0
        rts

; frame: returns once the beam has passed line 20 of the next frame (VPOSR/VHPOSR polled). Clobbers d0/d1.
frame:
.f1:    bsr.s   line
        cmp.w   #100,d0
        blo.s   .f1                  ; first somewhere below line 100
.f2:    bsr.s   line
        cmp.w   #20,d0
        bhs.s   .f2                  ; then back to the top of a frame
        rts
line:
        move.l  $DFF004,d0
        lsr.l   #8,d0
        and.w   #$1FF,d0
        rts

softcode:
        lea     softsr(pc),a0
        move.w  sr,(a0)
        move.w  INTENAR,softena-softsr(a0)
        rts

ordcode:                             ; a1 = is_Data = the interrupt's letter
        lea     ordbuf(pc),a0
.oc:    tst.b   (a0)+
        bne.s   .oc
        move.l  a1,d0
        move.b  d0,-1(a0)            ; ordbuf ends with spare NULs
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
softis:   dc.l  0,0                  ; struct Interrupt: ln_Succ, ln_Pred
          dc.b  2,0                  ; NT_INTERRUPT, pri 0
          dc.l  0                    ; ln_Name
          dc.l  0                    ; is_Data
          dc.l  softcode             ; is_Code
IS_SZ     EQU   22
ordis:    dc.l  0,0
          dc.b  2,-32
          dc.l  0,'A',ordcode
          dc.l  0,0
          dc.b  2,0
          dc.l  0,'B',ordcode
          dc.l  0,0
          dc.b  2,32
          dc.l  0,'C',ordcode
          dc.l  0,0
          dc.b  2,0
          dc.l  0,'D',ordcode
          dc.l  0,0
          dc.b  2,16
          dc.l  0,'E',ordcode
          dc.l  0,0
          dc.b  2,5
          dc.l  0,'F',ordcode
ordbuf:   dcb.b 8,0
elap:     ds.w  8
softsr:   dc.w  $FFFF
softena:  dc.w  $FFFF

gfxname:  dc.b  "graphics.library",0
m_begin:  dc.b  "SP BEGIN",10,0
m_q:      dc.b  "SP Q",0
m_e:      dc.b  " E",0
m_sig:    dc.b  "SP SIG",0
m_soft:   dc.b  "SP SOFT",0
m_ord:    dc.b  "SP ORD",0
m_end:    dc.b  "SP END",10,0
                even
