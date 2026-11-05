; tests/exec_msgio_probe.s - HUNK test executable (TEST ASSET, NOT ROM code).
; Black-box probe "exec messages, ports, I/O, opening libraries and devices" (docs/analysis/exec-messages-io-v34.md
; §8 test vectors, §9 probe description). Run from the startup-sequence of a floppy (tests/exec_msgio_probe.sh).
; Every exec call goes through a wrapper that loads markers into D2-D7/A2-A4, calls the vector, then records
; D0-D7/A0-A6, the nest counters and which marked registers changed. A fake device ("msgio.device"), fake
; libraries ("msgio.library", two nodes) and a fake resource are built here; their vectors record their entry
; registers, IDNestCnt/TDNestCnt and the request bytes 20-31, and behave as the byte "beh" says (set D0, io_Error,
; clear IOF_QUICK, ReplyMsg, clobber registers). Timer cases use timer.device UNIT_VBLANK.
; Output: one line per vector, "<id> key=hex ...", into a memory buffer whose bounds are printed on the serial port
; (SERDAT) before "MLP fin"; the harness reads it through gdb and tests/exec_msgio_check.py compares it with the
; expected values. A first line "MAP" gives the addresses of the test structures. The probe then waits forever.
; Arguments: N = also run N1 (CloseLibrary(NULL), crashes on 1.3); A = only run AL4 (AddLibrary with a wrong sum:
; dead-end alert $81000003 expected, reported on the serial port by the alert).
; Assembly: vasmm68k_mot -Fhunkexe -kick1hunks -nosym -m68000 tests/exec_msgio_probe.s
; Authored code; public structures only (exec/nodes.i, ports.i, io.i, libraries.i, interrupts.i, execbase.i).

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018
SERPER   EQU $DFF032
OBUFSZ   EQU 65536

; exec LVOs (exec_lib.fd V34)
L_Disable        EQU -120
L_Enable         EQU -126
L_Forbid         EQU -132
L_Permit         EQU -138
L_AllocMem       EQU -198
L_FreeMem        EQU -210
L_Remove         EQU -252
L_FindName       EQU -276
L_FindTask       EQU -294
L_SetSignal      EQU -306
L_Wait           EQU -318
L_AllocSignal    EQU -330
L_AddPort        EQU -354
L_RemPort        EQU -360
L_PutMsg         EQU -366
L_GetMsg         EQU -372
L_ReplyMsg       EQU -378
L_WaitPort       EQU -384
L_FindPort       EQU -390
L_AddLibrary     EQU -396
L_RemLibrary     EQU -402
L_OldOpenLibrary EQU -408
L_CloseLibrary   EQU -414
L_SumLibrary     EQU -426
L_AddDevice      EQU -432
L_RemDevice      EQU -438
L_OpenDevice     EQU -444
L_CloseDevice    EQU -450
L_DoIO           EQU -456
L_SendIO         EQU -462
L_CheckIO        EQU -468
L_WaitIO         EQU -474
L_AbortIO        EQU -480
L_AddResource    EQU -486
L_RemResource    EQU -492
L_OpenResource   EQU -498
L_OpenLibrary    EQU -552

LN_TYPE      EQU 8
LN_PRI       EQU 9
LN_NAME      EQU 10
MP_FLAGS     EQU 14
MP_SIGBIT    EQU 15
MP_SIGTASK   EQU 16
MP_MSGLIST   EQU 20
MN_REPLYPORT EQU 14
MN_LENGTH    EQU 18
IO_DEVICE    EQU 20
IO_UNIT      EQU 24
IO_COMMAND   EQU 28
IO_FLAGS     EQU 30
IO_ERROR     EQU 31
TV_SECS      EQU 32
TV_MICRO     EQU 36
LIB_FLAGS    EQU 14
LIB_NEGSIZE  EQU 16
LIB_VERSION  EQU 20
LIB_SUM      EQU 28
LIB_OPENCNT  EQU 32
IS_DATA      EQU 14
IS_CODE      EQU 18
EB_IDNEST    EQU $126
EB_TDNEST    EQU $127
EB_RESLIST   EQU $150
EB_DEVLIST   EQU $15E
EB_LIBLIST   EQU $17A
EB_PORTLIST  EQU $188
PR_RESULT2   EQU 148

; markers of the arguments that a call does not use
M0V      EQU $11110000
M1V      EQU $11110001
M8V      EQU $11110008
M9V      EQU $11110009

; stub record (one per fake vector)
R_D0     EQU 0
R_D1     EQU 4
R_A0     EQU 8
R_A1     EQU 12
R_A6     EQU 16
R_ID     EQU 20           ; IDNestCnt, then TDNestCnt (word at 20)
R_TD     EQU 21
R_B      EQU 22           ; bytes 20-31 of the structure in A1
R_TY     EQU 34           ; LN_TYPE of the structure in A1
R_CNT    EQU 36           ; calls
R_KIND   EQU 38           ; default D0: 0 = unchanged, 1 = 0, 2 = A6 (library Open)

; beh flags (byte at beh, io_Error at beh+1, D0 at beh+2)
BB_D0    EQU 0
BB_ERR   EQU 1
BB_NOQ   EQU 2
BB_REPLY EQU 3
BB_A6    EQU 4
BB_JUNK  EQU 5

CALL            macro                ; CALL lvo,d0,d1,a0,a1
                move.w  #\1,c_lvo-vars(a5)
                move.l  \2,c_d0-vars(a5)
                move.l  \3,c_d1-vars(a5)
                move.l  \4,c_a0-vars(a5)
                move.l  \5,c_a1-vars(a5)
                bsr     xcall
                endm
LINE            macro
                bsr     pid
                dc.b    "\1",0
                even
                endm
PV              macro
                move.l  \2,d0
                bsr     pkv
                dc.b    "\1",0
                even
                endm
PW              macro
                moveq   #0,d0
                move.w  \2,d0
                bsr     pkv
                dc.b    "\1",0
                even
                endm
PB              macro
                moveq   #0,d0
                move.b  \2,d0
                bsr     pkv
                dc.b    "\1",0
                even
                endm
BEH             macro                ; BEH flags,error,d0
                move.b  #\1,beh-vars(a5)
                move.b  #\2,beh+1-vars(a5)
                move.l  #\3,beh+2-vars(a5)
                endm
CLRREC          macro
                lea     \1(pc),a0
                bsr     clrrec
                endm
STUB            macro
\1:             move.l  a5,-(sp)
                lea     \2(pc),a5
                bra     stub
                endm
REC             macro
\1:             dcb.b   38,0
                dc.b    \2,0
                endm
JV              macro
                dc.w    $4EF9
                dc.l    \1
                endm

                section code,code
_start:
                movem.l d2-d7/a2-a6,-(sp)
                lea     vars(pc),a5
.arg:           subq.l  #1,d0
                bmi.s   .argd
                move.b  (a0)+,d1
                cmp.b   #'N',d1
                bne.s   .a1
                st      argN-vars(a5)
.a1:            cmp.b   #'A',d1
                bne.s   .arg
                st      argA-vars(a5)
                bra.s   .arg
.argd:          move.w  #372,SERPER
                move.l  ($4).w,a6
                move.l  a6,exb-vars(a5)
                tst.b   argA-vars(a5)
                bne     t_al4
                move.l  #OBUFSZ,d0
                move.l  #$10001,d1
                jsr     L_AllocMem(a6)
                move.l  d0,obuf-vars(a5)
                move.l  d0,optr-vars(a5)
                beq     .out
                sub.l   a1,a1
                jsr     L_FindTask(a6)
                move.l  d0,me-vars(a5)
                moveq   #-1,d0
                jsr     L_AllocSignal(a6)
                move.b  d0,sigP-vars(a5)
                moveq   #-1,d0
                jsr     L_AllocSignal(a6)
                move.b  d0,sigQ-vars(a5)
                lea     portQ(pc),a0         ; Q: reply port of the TR_GETSYSTIME request
                moveq   #0,d0
                move.b  sigQ-vars(a5),d1
                move.l  me-vars(a5),a1
                bsr     initport
                lea     n_timer(pc),a0
                moveq   #1,d0                ; UNIT_VBLANK
                lea     treq(pc),a1
                moveq   #0,d1
                jsr     L_OpenDevice(a6)
                lea     treq(pc),a0
                lea     treqs(pc),a1
                move.l  IO_DEVICE(a0),IO_DEVICE(a1)
                move.l  IO_UNIT(a0),IO_UNIT(a1)
                move.l  #portQ,MN_REPLYPORT(a1)
                lea     m_start(pc),a0
                bsr     puts
                bsr     pmap
                bsr     t_put
                bsr     t_get
                bsr     t_reply
                bsr     t_waitport
                bsr     t_ports
                bsr     t_dev
                bsr     t_lib
                bsr     t_res
                tst.b   argN-vars(a5)
                beq.s   .non1
                bsr     t_n1
.non1:          lea     treq(pc),a1
                jsr     L_CloseDevice(a6)
                lea     m_end(pc),a0
                bsr     puts
                moveq   #1,d3                ; "MLP buf=<start> end=<end>" twice, then "MLP fin", on the serial port
.sb:            lea     m_buf(pc),a0
                bsr     sputs
                move.l  obuf-vars(a5),d0
                bsr     shex8
                lea     m_bend(pc),a0
                bsr     sputs
                move.l  optr-vars(a5),d0
                bsr     shex8
                moveq   #10,d1
                bsr     sputc
                dbra    d3,.sb
                lea     m_end(pc),a0
                bsr     sputs
                moveq   #0,d0                ; the buffer must stay valid until the harness has read it
                jsr     L_Wait(a6)
.out:           movem.l (sp)+,d2-d7/a2-a6
                moveq   #0,d0
                rts

; ---------------------------------------------------------------- V1 PutMsg / GetMsg
t_put:          bsr     rstP                 ; P1
                lea     msg1(pc),a0
                move.b  #$55,LN_TYPE(a0)
                CALL    L_PutMsg,#M0V,#M1V,#portP,#msg1
                LINE    P1
                PB      ty,msg1+LN_TYPE(pc)
                bsr     psig
                bsr     plistP
                bsr     pstd
                CALL    L_PutMsg,#M0V,#M1V,#portP,#msg2    ; P2
                LINE    P2
                bsr     plistP
                bsr     pstd
                bsr     rstP                 ; P3: PA_IGNORE
                lea     portP(pc),a0
                move.b  #2,MP_FLAGS(a0)
                lea     msg3(pc),a0
                move.b  #$55,LN_TYPE(a0)
                CALL    L_PutMsg,#M0V,#M1V,#portP,#msg3
                LINE    P3
                PB      ty,msg3+LN_TYPE(pc)
                bsr     psig
                bsr     plistP
                bsr     pstd
                bsr     rstP                 ; P4: PA_SOFTINT
                lea     portP(pc),a0
                move.b  #1,MP_FLAGS(a0)
                move.l  #intr,MP_SIGTASK(a0)
                bsr     clrcnt
                lea     intr(pc),a0
                move.b  #2,LN_TYPE(a0)
                move.l  #$DA7A0000,IS_DATA(a0)
                move.l  #softcode,IS_CODE(a0)
                CALL    L_PutMsg,#M0V,#M1V,#portP,#msg1
                LINE    P4
                PW      sc,sir(pc)
                PV      sa1,sir+2(pc)
                PV      sa6,sir+6(pc)
                PW      ssr,sir+10(pc)
                PB      it,intr+LN_TYPE(pc)
                PB      ty,msg1+LN_TYPE(pc)
                bsr     plistP
                bsr     pstd
                bsr     rstP                 ; P5: mp_SigBit 33 -> bit 1
                lea     portP(pc),a0
                move.b  #33,MP_SIGBIT(a0)
                moveq   #0,d0
                moveq   #2,d1
                jsr     L_SetSignal(a6)
                CALL    L_PutMsg,#M0V,#M1V,#portP,#msg1
                LINE    P5
                moveq   #0,d0
                moveq   #0,d1
                jsr     L_SetSignal(a6)
                lsr.l   #1,d0
                and.l   #1,d0
                bsr     pkv
                dc.b    "b1",0
                even
                bsr     pstd
                moveq   #0,d0
                moveq   #2,d1
                jsr     L_SetSignal(a6)
                bsr     rstP                 ; P6: mp_SigBit 96 + b
                lea     portP(pc),a0
                add.b   #96,MP_SIGBIT(a0)
                CALL    L_PutMsg,#M0V,#M1V,#portP,#msg1
                LINE    P6
                bsr     psig
                bsr     pstd
                bsr     rstP                 ; P8: action 3
                lea     portP(pc),a0
                move.b  #3,MP_FLAGS(a0)
                move.l  #act3,MP_SIGTASK(a0)
                bsr     clrcnt
                CALL    L_PutMsg,#M0V,#M1V,#portP,#msg1
                LINE    P8
                PW      ac,a3r(pc)
                PV      ra0,a3r+2(pc)
                PV      ra1,a3r+6(pc)
                PV      rd0,a3r+10(pc)
                PV      rhd,a3r+14(pc)
                PB      rid,a3r+18(pc)
                PV      d0,rout(pc)
                PV      d1,rout+4(pc)
                PV      a0,rout+32(pc)
                PV      a1,rout+36(pc)
                bsr     pstd
                LINE    P9                   ; P9-P12: mp_SigTask = 0
                moveq   #0,d4
                bsr     p9x
                LINE    P10
                moveq   #1,d4
                bsr     p9x
                LINE    P11
                moveq   #2,d4
                bsr     p9x
                LINE    P12
                moveq   #3,d4
                bsr     p9x
                LINE    P13_04               ; P13: bits 2-7 of mp_Flags ignored
                moveq   #$04,d4
                move.l  me-vars(a5),a2
                bsr     p13x
                LINE    P13_40
                moveq   #$40,d4
                move.l  me-vars(a5),a2
                bsr     p13x
                LINE    P13_80
                move.l  #$80,d4
                move.l  me-vars(a5),a2
                bsr     p13x
                LINE    P13_81
                move.l  #$81,d4
                lea     intr(pc),a2
                bsr     p13x
                LINE    P13_82
                move.l  #$82,d4
                move.l  me-vars(a5),a2
                bsr     p13x
                LINE    P13_07
                moveq   #$07,d4
                lea     act3(pc),a2
                bsr     p13x
                LINE    P13_83
                move.l  #$83,d4
                lea     act3(pc),a2
                bsr     p13x
                rts
p9x:            bsr     rstP
                lea     portP(pc),a0
                move.b  d4,MP_FLAGS(a0)
                clr.l   MP_SIGTASK(a0)
                bsr     clrcnt
                lea     msg1(pc),a0
                move.b  #$55,LN_TYPE(a0)
                CALL    L_PutMsg,#M0V,#M1V,#portP,#msg1
                PB      ty,msg1+LN_TYPE(pc)
                bsr     psig
                PW      sc,sir(pc)
                PW      ac,a3r(pc)
                bsr     plistP
                PV      d0,rout(pc)
                PV      d1,rout+4(pc)
                PV      a0,rout+32(pc)
                PV      a1,rout+36(pc)
                bra     pstd
p13x:           bsr     rstP
                lea     portP(pc),a0
                move.b  d4,MP_FLAGS(a0)
                move.l  a2,MP_SIGTASK(a0)
                bsr     clrcnt
                CALL    L_PutMsg,#M0V,#M1V,#portP,#msg1
                PB      ty,msg1+LN_TYPE(pc)
                bsr     psig
                PW      sc,sir(pc)
                PW      ac,a3r(pc)
                PB      fl,portP+MP_FLAGS(pc)
                bra     pstd

t_get:          bsr     rstP                 ; G1-G3: three messages, signal set
                lea     portP(pc),a0
                move.b  #2,MP_FLAGS(a0)
                lea     portP(pc),a0
                lea     msg1(pc),a1
                jsr     L_PutMsg(a6)
                lea     portP(pc),a0
                lea     msg2(pc),a1
                jsr     L_PutMsg(a6)
                lea     portP(pc),a0
                lea     msg3(pc),a1
                jsr     L_PutMsg(a6)
                bsr     setsig
                LINE    G1
                bsr     getx
                LINE    G2
                bsr     getx
                LINE    G3
                bsr     getx
                CALL    L_GetMsg,#M0V,#M1V,#portP,#M9V     ; G4: empty
                LINE    G4
                PV      d0,rout(pc)
                PV      d1,rout+4(pc)
                PV      a0,rout+32(pc)
                PV      a1,rout+36(pc)
                bra     pstd
getx:           CALL    L_GetMsg,#M0V,#M1V,#portP,#M9V
                PV      d0,rout(pc)
                move.l  rout(pc),d0
                beq.s   .n
                move.l  d0,a2
                PB      ty,LN_TYPE(a2)
                PV      su,(a2)
.n:             PV      d1,rout+4(pc)
                bsr     psig
                bra     pstd

; ---------------------------------------------------------------- V2 ReplyMsg
t_reply:        bsr     rstP                 ; R1
                lea     msg1(pc),a0
                move.l  #portP,MN_REPLYPORT(a0)
                move.b  #$55,LN_TYPE(a0)
                CALL    L_ReplyMsg,#M0V,#M1V,#M8V,#msg1
                LINE    R1
                PB      ty,msg1+LN_TYPE(pc)
                bsr     psig
                bsr     plistP
                bsr     pstd
                lea     msg2(pc),a0          ; R2: no reply port
                clr.l   (a0)
                clr.l   4(a0)
                clr.l   MN_REPLYPORT(a0)
                move.b  #$55,LN_TYPE(a0)
                CALL    L_ReplyMsg,#M0V,#M1V,#M8V,#msg2
                LINE    R2
                PB      ty,msg2+LN_TYPE(pc)
                PV      ls,msg2(pc)
                PV      lp,msg2+4(pc)
                PV      d0,rout(pc)
                PV      d1,rout+4(pc)
                PV      a0,rout+32(pc)
                PV      a1,rout+36(pc)
                bsr     pstd
                bsr     rstP                 ; R3: PA_SOFTINT
                lea     portP(pc),a0
                move.b  #1,MP_FLAGS(a0)
                move.l  #intr,MP_SIGTASK(a0)
                bsr     clrcnt
                CALL    L_ReplyMsg,#M0V,#M1V,#M8V,#msg1
                LINE    R3
                PB      ty,msg1+LN_TYPE(pc)
                PW      sc,sir(pc)
                bsr     plistP
                bsr     pstd
                bsr     rstP                 ; R4: PA_IGNORE
                lea     portP(pc),a0
                move.b  #2,MP_FLAGS(a0)
                CALL    L_ReplyMsg,#M0V,#M1V,#M8V,#msg1
                LINE    R4
                PB      ty,msg1+LN_TYPE(pc)
                bsr     psig
                bsr     plistP
                bsr     pstd
                bsr     rstP                 ; R5: replied (7) then freed (6) messages replied again
                lea     portP(pc),a0
                move.b  #2,MP_FLAGS(a0)
                lea     msg1(pc),a0
                move.b  #7,LN_TYPE(a0)
                lea     msg2(pc),a0
                move.l  #portP,MN_REPLYPORT(a0)
                move.b  #6,LN_TYPE(a0)
                CALL    L_ReplyMsg,#M0V,#M1V,#M8V,#msg1
                CALL    L_ReplyMsg,#M0V,#M1V,#M8V,#msg2
                LINE    R5
                PB      t1,msg1+LN_TYPE(pc)
                PB      t2,msg2+LN_TYPE(pc)
                bsr     plistP
                bsr     pstd
                bsr     rstP                 ; R6: PA_SIGNAL with mp_SigTask = 0
                lea     portP(pc),a0
                clr.l   MP_SIGTASK(a0)
                CALL    L_ReplyMsg,#M0V,#M1V,#M8V,#msg1
                LINE    R6
                PB      ty,msg1+LN_TYPE(pc)
                bsr     psig
                bsr     plistP
                bra     pstd

; ---------------------------------------------------------------- V3 WaitPort
t_waitport:     LINE    WP1
                bsr     setsig
                bsr     wpq
                LINE    WP2
                bsr     clrsig
                bsr     wpq
                LINE    WP3
                moveq   #0,d4
                bsr     wpt
                LINE    WP4
                moveq   #1,d4
                bra     wpt
wpq:            bsr     rstP0
                lea     portP(pc),a0
                move.b  #2,MP_FLAGS(a0)
                lea     portP(pc),a0
                lea     msg1(pc),a1
                jsr     L_PutMsg(a6)
                CALL    L_WaitPort,#M0V,#M1V,#portP,#M9V
                PV      d0,rout(pc)
                PV      a1,rout+36(pc)
                PV      d1,rout+4(pc)
                PV      a0,rout+32(pc)
                bsr     psig
                bsr     plistP
                bra     pstd
wpt:            bsr     rstP                 ; d4 = 1: signal set beforehand (spurious)
                moveq   #0,d1
                move.l  #100000,d0
                bsr     tadd
                bsr     tstart
                lea     treq(pc),a1
                jsr     L_SendIO(a6)
                tst.b   d4
                beq.s   .w
                bsr     setsig
.w:             CALL    L_WaitPort,#M0V,#M1V,#portP,#M9V
                bsr     telapsed
                move.l  d0,d5
                PV      d0,rout(pc)
                PV      a1,rout+36(pc)
                PB      ty,treq+LN_TYPE(pc)
                PV      d1,rout+4(pc)
                bsr     sigmask
                bsr     pkv
                dc.b    "mk",0
                even
                bsr     psig
                bsr     plistP
                move.l  d5,d0
                bsr     pkv
                dc.b    "el",0
                even
                bsr     pstd
                lea     portP(pc),a0
                jmp     L_GetMsg(a6)

; ---------------------------------------------------------------- V4 AddPort / RemPort / FindPort
t_ports:        lea     portR(pc),a0         ; AP1
                move.l  #n_port,LN_NAME(a0)
                move.b  #5,LN_PRI(a0)
                move.b  #$33,LN_TYPE(a0)
                move.l  #$11111111,MP_MSGLIST(a0)
                move.l  #$22222222,MP_MSGLIST+4(a0)
                move.l  #$33333333,MP_MSGLIST+8(a0)
                CALL    L_AddPort,#M0V,#M1V,#M8V,#portR
                LINE    AP1
                PB      ty,portR+LN_TYPE(pc)
                PV      lh,portR+MP_MSGLIST(pc)
                PV      lt,portR+MP_MSGLIST+4(pc)
                PV      lp,portR+MP_MSGLIST+8(pc)
                lea     EB_PORTLIST(a6),a0
                lea     portR(pc),a1
                bsr     inlist
                bsr     pkv
                dc.b    "in",0
                even
                PB      d1b,rout+7(pc)
                PV      a1,rout+36(pc)
                bsr     pstd
                lea     portS0(pc),a2        ; AP2: priorities 0, 10, -10, 10
                moveq   #0,d0
                bsr     addsp
                lea     portS1(pc),a2
                moveq   #10,d0
                bsr     addsp
                lea     portS2(pc),a2
                moveq   #-10,d0
                bsr     addsp
                lea     portS3(pc),a2
                moveq   #10,d0
                bsr     addsp
                LINE    AP2
                lea     m_o(pc),a0
                bsr     puts
                lea     EB_PORTLIST(a6),a2
                move.l  (a2),a2
.o:             tst.l   (a2)
                beq.s   .oe
                lea     portR(pc),a0
                lea     portS3+40(pc),a1
                cmp.l   a0,a2
                bcs.s   .on
                cmp.l   a1,a2
                bcc.s   .on
                move.l  a2,d0
                bsr     phex8
                moveq   #',',d1
                bsr     putc
.on:            move.l  (a2),a2
                bra.s   .o
.oe:            moveq   #10,d1
                bsr     putc
                CALL    L_FindPort,#M0V,#M1V,#M8V,#n_port  ; AP3
                LINE    AP3a
                PV      d0,rout(pc)
                PV      a1,rout+36(pc)
                bsr     pstd
                CALL    L_FindPort,#M0V,#M1V,#M8V,#n_pnone
                LINE    AP3b
                PV      d0,rout(pc)
                bsr     pstd
                CALL    L_RemPort,#M0V,#M1V,#M8V,#portR    ; AP4
                LINE    AP4
                PV      d0,rout(pc)
                PV      d1,rout+4(pc)
                PV      a0,rout+32(pc)
                PV      a1,rout+36(pc)
                lea     n_port(pc),a1
                jsr     L_FindPort(a6)
                bsr     pkv
                dc.b    "f",0
                even
                bsr     pstd
                lea     portS0(pc),a1
                jsr     L_RemPort(a6)
                lea     portS1(pc),a1
                jsr     L_RemPort(a6)
                lea     portS2(pc),a1
                jsr     L_RemPort(a6)
                lea     portS3(pc),a1
                jmp     L_RemPort(a6)
addsp:          move.l  #n_s,LN_NAME(a2)
                move.b  d0,LN_PRI(a2)
                move.b  #4,LN_TYPE(a2)
                move.l  a2,a1
                jmp     L_AddPort(a6)

; ---------------------------------------------------------------- V5/V6 devices and I/O
t_dev:          lea     fd(pc),a0            ; ADV1
                lea     n_dev(pc),a1
                moveq   #3,d0
                moveq   #$77,d1
                moveq   #36,d2
                bsr     initlib
                CALL    L_AddDevice,#M0V,#M1V,#M8V,#fd
                LINE    ADV1
                PB      ty,fd+LN_TYPE(pc)
                PB      fl,fd+LIB_FLAGS(pc)
                PV      sm,fd+LIB_SUM(pc)
                PV      hd,EB_DEVLIST(a6)
                PB      d1b,rout+7(pc)
                bsr     pstd

                LINE    IO1                  ; IO1-IO3: quick BeginIO setting io_Error
                bsr     rstIO
                lea     ior(pc),a0
                move.b  #$F0,IO_FLAGS(a0)
                move.b  #$55,LN_TYPE(a0)
                CLRREC  rec_dbio
                BEH     1<<BB_ERR,0,0
                CALL    L_DoIO,#M0V,#M1V,#M8V,#ior
                lea     rec_dbio(pc),a2
                bsr     prec
                PV      d0,rout(pc)
                PB      ty,ior+LN_TYPE(pc)
                PB      fl,ior+IO_FLAGS(pc)
                bsr     plistP
                bsr     pstd
                LINE    IO2
                bsr     rstIO
                BEH     1<<BB_ERR,5,0
                CALL    L_DoIO,#M0V,#M1V,#M8V,#ior
                PV      d0,rout(pc)
                bsr     pstd
                LINE    IO3
                bsr     rstIO
                BEH     1<<BB_ERR,$FE,0
                CALL    L_DoIO,#M0V,#M1V,#M8V,#ior
                PV      d0,rout(pc)
                bsr     pstd

                LINE    IO4                  ; IO4: timer 100 ms through DoIO
                bsr     rstP
                moveq   #0,d1
                move.l  #100000,d0
                bsr     tadd
                bsr     tstart
                CALL    L_DoIO,#M0V,#M1V,#M8V,#treq
                bsr     telapsed
                move.l  d0,d5
                PB      ty,treq+LN_TYPE(pc)
                bsr     plistP
                bsr     psig
                PV      d0,rout(pc)
                move.l  d5,d0
                bsr     pkv
                dc.b    "el",0
                even
                bsr     pstd
                LINE    IO5                  ; IO5: TR_GETSYSTIME (quick)
                lea     treq(pc),a0
                move.w  #10,IO_COMMAND(a0)
                move.b  #$55,LN_TYPE(a0)
                CALL    L_DoIO,#M0V,#M1V,#M8V,#treq
                PB      ty,treq+LN_TYPE(pc)
                PB      fl,treq+IO_FLAGS(pc)
                PV      d0,rout(pc)
                bsr     pstd

                LINE    IO6                  ; IO6: BeginIO clears IOF_QUICK and replies
                bsr     rstP
                bsr     rstIO
                BEH     (1<<BB_ERR)|(1<<BB_NOQ)|(1<<BB_REPLY),4,0
                CALL    L_DoIO,#M0V,#M1V,#M8V,#ior
                PB      ty,ior+LN_TYPE(pc)
                bsr     plistP
                bsr     psig
                PV      d0,rout(pc)
                bsr     pstd
                LINE    IO7                  ; IO7: BeginIO replies but keeps IOF_QUICK
                bsr     rstP
                bsr     rstIO
                BEH     1<<BB_REPLY,0,0
                CALL    L_DoIO,#M0V,#M1V,#M8V,#ior
                PB      ty,ior+LN_TYPE(pc)
                bsr     plistP
                PB      fl,ior+IO_FLAGS(pc)
                PV      d0,rout(pc)
                bsr     pstd
                bsr     rstP
                LINE    IO8                  ; IO8/IO9: BeginIO clobbers D1, D2, A0, A1, A2
                bsr     rstIO
                BEH     1<<BB_JUNK,0,0
                CALL    L_DoIO,#M0V,#M1V,#M8V,#ior
                bsr     pjunk
                LINE    IO9
                bsr     rstIO
                BEH     1<<BB_JUNK,0,0
                CALL    L_SendIO,#M0V,#M1V,#M8V,#ior
                PV      d0,rout(pc)
                bsr     pjunk
                LINE    IO10a                ; IO10: BeginIO changes A6
                bsr     rstIO
                BEH     1<<BB_A6,0,0
                CALL    L_DoIO,#M0V,#M1V,#M8V,#ior
                bsr     pstd
                LINE    IO10b
                bsr     rstIO
                BEH     1<<BB_A6,0,0
                CALL    L_SendIO,#M0V,#M1V,#M8V,#ior
                bsr     pstd
                LINE    IO11a                ; IO11: SendIO writes io_Flags = 0
                move.l  #$F1,d4
                bsr     io11
                LINE    IO11b
                moveq   #0,d4
                bsr     io11
                LINE    IO11c
                moveq   #1,d4
                bsr     io11

                LINE    WI1                  ; WI1: quick request also queued in its port
                bsr     rstP
                lea     portP(pc),a0
                move.b  #2,MP_FLAGS(a0)
                bsr     rstIO
                lea     portP(pc),a0
                lea     ior(pc),a1
                jsr     L_PutMsg(a6)
                lea     ior(pc),a0
                move.b  #1,IO_FLAGS(a0)
                move.b  #$F9,IO_ERROR(a0)
                bsr     setsig
                CALL    L_WaitIO,#M0V,#M1V,#M8V,#ior
                PV      d0,rout(pc)
                bsr     plistP
                bsr     psig
                PV      d1,rout+4(pc)
                PV      a0,rout+32(pc)
                PV      a1,rout+36(pc)
                bsr     pstd
                LINE    WI2s                 ; WI2: already replied, signal set / clear
                moveq   #1,d4
                bsr     wi2
                LINE    WI2c
                moveq   #0,d4
                bsr     wi2
                LINE    WI3                  ; WI3: Remove with the request's own links
                bsr     rstIO
                lea     ior(pc),a0
                move.b  #7,LN_TYPE(a0)
                move.l  #nodeX,(a0)
                move.l  #nodeY,4(a0)
                lea     nodeX(pc),a0
                clr.l   (a0)
                clr.l   4(a0)
                clr.l   8(a0)
                clr.l   12(a0)
                CALL    L_WaitIO,#M0V,#M1V,#M8V,#ior
                PV      xp,nodeX+4(pc)
                PV      ys,nodeY(pc)
                PV      d0,rout(pc)
                bsr     pstd
                moveq   #0,d4                ; CK10, WI4, CK11
                bsr     wi4
                moveq   #1,d4                ; WI5: signal set beforehand
                bsr     wi4

                LINE    CK1                  ; CK1-CK9: (io_Flags, ln_Type)
                moveq   #1,d4
                moveq   #5,d5
                bsr     ckx
                LINE    CK2
                moveq   #1,d4
                moveq   #7,d5
                bsr     ckx
                LINE    CK3
                moveq   #0,d4
                moveq   #5,d5
                bsr     ckx
                LINE    CK4
                moveq   #0,d4
                moveq   #7,d5
                bsr     ckx
                LINE    CK5
                moveq   #0,d4
                moveq   #6,d5
                bsr     ckx
                LINE    CK6
                moveq   #0,d4
                moveq   #0,d5
                bsr     ckx
                LINE    CK7
                move.l  #$FE,d4
                moveq   #7,d5
                bsr     ckx
                LINE    CK8
                move.l  #$FF,d4
                moveq   #0,d5
                bsr     ckx
                LINE    CK9
                move.l  #$80,d4
                moveq   #5,d5
                bsr     ckx

                LINE    AB1a                 ; AB1: AbortIO passes the device's D0 through
                bsr     rstIO
                moveq   #0,d4
                moveq   #5,d5
                bsr     ab1
                LINE    AB1b
                bsr     rstIO
                moveq   #1,d4
                moveq   #7,d5
                bsr     ab1
                LINE    AB2a                 ; AB2: timer 5 s aborted, then WaitIO
                bsr     rstP
                moveq   #5,d1
                moveq   #0,d0
                bsr     tadd
                lea     treq(pc),a1
                jsr     L_SendIO(a6)
                CALL    L_AbortIO,#M0V,#M1V,#M8V,#treq
                PV      d0,rout(pc)
                PB      ty,treq+LN_TYPE(pc)
                PB      er,treq+IO_ERROR(pc)
                bsr     psig
                bsr     pstd
                LINE    AB2b
                bsr     tstart
                CALL    L_WaitIO,#M0V,#M1V,#M8V,#treq
                bsr     telapsed
                move.l  d0,d5
                PV      d0,rout(pc)
                bsr     plistP
                move.l  d5,d0
                bsr     pkv
                dc.b    "el",0
                even
                bsr     pstd
                LINE    AB3                  ; AB3: the device's AbortIO changes A6, A1, D1, returns 7
                bsr     rstIO
                BEH     (1<<BB_D0)|(1<<BB_A6)|(1<<BB_JUNK),0,7
                CALL    L_AbortIO,#M0V,#M1V,#M8V,#ior
                PV      d0,rout(pc)
                PV      d1,rout+4(pc)
                PV      a1,rout+36(pc)
                bsr     pstd

                LINE    OD1                  ; OD1: entry of the device's Open
                bsr     fillio
                CLRREC  rec_dopen
                CALL    L_OpenDevice,#2,#3,#n_dev,#ior
                lea     rec_dopen(pc),a2
                bsr     prec
                PV      d0,rout(pc)
                PV      a0,rout+32(pc)
                bsr     pstd
                LINE    OD2
                bsr     fillio
                BEH     (1<<BB_D0)|(1<<BB_ERR),$FD,$0BADBAD0
                CALL    L_OpenDevice,#0,#0,#n_dev,#ior
                PV      d0,rout(pc)
                PV      dv,ior+IO_DEVICE(pc)
                bsr     pstd
                LINE    OD3
                bsr     fillio
                BEH     1<<BB_ERR,5,0
                CALL    L_OpenDevice,#0,#0,#n_dev,#ior
                PV      d0,rout(pc)
                PV      dv,ior+IO_DEVICE(pc)
                bsr     pstd
                LINE    OD4
                bsr     fillio
                BEH     (1<<BB_D0)|(1<<BB_ERR),0,$12345678
                CALL    L_OpenDevice,#0,#0,#n_dev,#ior
                PV      d0,rout(pc)
                bsr     pstd
                LINE    OD5                  ; OD5: name not found
                bsr     fillio
                CALL    L_OpenDevice,#0,#0,#n_none,#ior
                PV      d0,rout(pc)
                PV      b0,ior+20(pc)
                PV      b1,ior+24(pc)
                PV      b2,ior+28(pc)
                PV      a0,rout+32(pc)
                PV      a1,rout+36(pc)
                move.l  me-vars(a5),a0
                PV      ie,PR_RESULT2(a0)
                bsr     pstd
                LINE    OD6                  ; OD6: io_Error cleared before the Open
                bsr     fillio
                lea     ior(pc),a0
                move.b  #$77,IO_ERROR(a0)
                CALL    L_OpenDevice,#0,#0,#n_dev,#ior
                PV      d0,rout(pc)
                bsr     pstd
                lea     fd3(pc),a0           ; OD7: second device of the same name
                lea     n_dev(pc),a1
                moveq   #-5,d0
                moveq   #3,d1
                moveq   #36,d2
                bsr     initlib
                lea     fd3(pc),a1
                jsr     L_AddDevice(a6)
                LINE    OD7
                bsr     fillio
                CLRREC  rec_dopen
                CLRREC  rec_d3open
                BEH     1<<BB_ERR,$FF,0
                CALL    L_OpenDevice,#0,#0,#n_dev,#ior
                PV      d0,rout(pc)
                PW      c1,rec_dopen+R_CNT(pc)
                PW      c3,rec_d3open+R_CNT(pc)
                PV      dv,ior+IO_DEVICE(pc)
                bsr     pstd
                lea     fd3(pc),a1
                bsr     unlink
                LINE    OD8                  ; OD8: the Open changes A6, A1, D1
                bsr     fillio
                BEH     (1<<BB_A6)|(1<<BB_JUNK),0,0
                CALL    L_OpenDevice,#0,#0,#n_dev,#ior
                PV      d0,rout(pc)
                PV      d1,rout+4(pc)
                PV      a1,rout+36(pc)
                bsr     pstd
                LINE    CD1                  ; CD1: CloseDevice passes Close's D0 through
                bsr     rstIO
                lea     ior(pc),a0
                move.l  #$12345678,IO_UNIT(a0)
                CLRREC  rec_dclose
                bsr     mkseg
                CALL    L_CloseDevice,#M0V,#M1V,#M8V,#ior
                PV      d0,rout(pc)
                PV      es,es-vars(a5)
                lea     rec_dclose(pc),a2
                bsr     prec
                PV      dv,ior+IO_DEVICE(pc)
                PV      un,ior+IO_UNIT(pc)
                bsr     pstd
                LINE    RD1                  ; RD1: RemDevice calls Expunge, does not unlink
                CLRREC  rec_dexp
                bsr     mkseg
                CALL    L_RemDevice,#M0V,#M1V,#M8V,#fd
                PV      d0,rout(pc)
                PV      es,es-vars(a5)
                lea     rec_dexp(pc),a2
                bsr     prec
                lea     EB_DEVLIST(a6),a0
                lea     fd(pc),a1
                bsr     inlist
                bsr     pkv
                dc.b    "in",0
                even
                bsr     pstd
                lea     fd(pc),a1
                bsr     unlink
                lea     fd2(pc),a0           ; ADV2: SUMUSED|CHANGED device
                lea     n_sumdev(pc),a1
                moveq   #-100,d0
                moveq   #3,d1
                moveq   #36,d2
                bsr     initlib
                lea     fd2(pc),a0
                move.b  #6,LIB_FLAGS(a0)
                CALL    L_AddDevice,#M0V,#M1V,#M8V,#fd2
                LINE    ADV2
                PB      fl,fd2+LIB_FLAGS(pc)
                PV      sm,fd2+LIB_SUM(pc)
                lea     fd2(pc),a0
                bsr     wsum
                swap    d0
                move.w  #$5A5A,d0
                bsr     pkv
                dc.b    "es",0
                even
                bsr     pstd
                lea     fd2(pc),a1
                bra     unlink
io11:           bsr     rstIO
                lea     ior(pc),a0
                move.b  d4,IO_FLAGS(a0)
                CLRREC  rec_dbio
                CALL    L_SendIO,#M0V,#M1V,#M8V,#ior
                PB      bf,rec_dbio+R_B+10(pc)
                PV      d0,rout(pc)
                bra     pstd
pjunk:          PV      d1,rout+4(pc)
                PV      d2,rout+8(pc)
                PV      a0,rout+32(pc)
                PV      a1,rout+36(pc)
                PV      a2,rout+40(pc)
                bra     pstd
wi2:            bsr     rstP
                lea     portP(pc),a0
                move.b  #2,MP_FLAGS(a0)
                bsr     rstIO
                lea     ior(pc),a0
                move.b  #3,IO_ERROR(a0)
                lea     ior(pc),a1
                jsr     L_ReplyMsg(a6)
                bsr     clrsig
                tst.b   d4
                beq.s   .c
                bsr     setsig
.c:             CALL    L_WaitIO,#M0V,#M1V,#M8V,#ior
                PV      d0,rout(pc)
                PB      ty,ior+LN_TYPE(pc)
                bsr     plistP
                bsr     psig
                PV      d1,rout+4(pc)
                bra     pstd
wi4:            bsr     rstP
                moveq   #0,d1
                move.l  #100000,d0
                bsr     tadd
                bsr     tstart
                lea     treq(pc),a1
                jsr     L_SendIO(a6)
                tst.b   d4
                beq.s   .ck
                bsr     setsig
                LINE    WI5
                bra.s   .w
.ck:            CALL    L_CheckIO,#M0V,#M1V,#M8V,#treq
                LINE    CK10
                PV      d0,rout(pc)
                bsr     pstd
                LINE    WI4
.w:             CALL    L_WaitIO,#M0V,#M1V,#M8V,#treq
                bsr     telapsed
                move.l  d0,d5
                PB      ty,treq+LN_TYPE(pc)
                bsr     plistP
                bsr     psig
                PV      d0,rout(pc)
                move.l  d5,d0
                bsr     pkv
                dc.b    "el",0
                even
                bsr     pstd
                tst.b   d4
                bne.s   .r
                CALL    L_CheckIO,#M0V,#M1V,#M8V,#treq
                LINE    CK11
                PV      d0,rout(pc)
                bsr     pstd
.r:             rts
ckx:            bsr     rstIO
                lea     ior(pc),a0
                move.b  d4,IO_FLAGS(a0)
                move.b  d5,LN_TYPE(a0)
                CALL    L_CheckIO,#M0V,#M1V,#M8V,#ior
                PV      d0,rout(pc)
                PV      d1,rout+4(pc)
                PV      a0,rout+32(pc)
                PV      a1,rout+36(pc)
                bra     pstd
ab1:            lea     ior(pc),a0
                move.b  d4,IO_FLAGS(a0)
                move.b  d5,LN_TYPE(a0)
                CLRREC  rec_dabort
                BEH     1<<BB_D0,0,$AB0127ED
                CALL    L_AbortIO,#M0V,#M1V,#M8V,#ior
                PV      d0,rout(pc)
                PB      fl,ior+IO_FLAGS(pc)
                PB      ty,ior+LN_TYPE(pc)
                PB      er,ior+IO_ERROR(pc)
                lea     rec_dabort(pc),a2
                bsr     prec
                bra     pstd

; ---------------------------------------------------------------- V7 libraries, checksum, resources
t_lib:          lea     fl1(pc),a0           ; AL1
                lea     n_lib(pc),a1
                moveq   #0,d0
                moveq   #$66,d1
                moveq   #30,d2
                bsr     initlib
                CALL    L_AddLibrary,#M0V,#M1V,#M8V,#fl1
                LINE    AL1
                PB      ty,fl1+LN_TYPE(pc)
                PB      fl,fl1+LIB_FLAGS(pc)
                PV      sm,fl1+LIB_SUM(pc)
                PV      nx,fl1(pc)
                bsr     pstd
                lea     oltab(pc),a3         ; OL1-OL10, then the OL11 pairs as OLP1-OLP8: (lib_Version, D0)
                lea     m_ol(pc),a4
                moveq   #9,d6
.ol:            move.w  (a3)+,d4
                move.l  (a3)+,d5
                bsr     pid0
                lea     fl1(pc),a0
                move.w  d4,LIB_VERSION(a0)
                CLRREC  rec_l1open
                CALL    L_OpenLibrary,d5,#M1V,#M8V,#n_lib
                PV      d0,rout(pc)
                PW      oc,rec_l1open+R_CNT(pc)
                bsr     pstd
                dbra    d6,.ol
                cmp.l   #m_ol,a4
                bne.s   .old
                lea     m_olp(pc),a4
                clr.w   olno-vars(a5)
                moveq   #7,d6
                bra.s   .ol
.old:           lea     fl1(pc),a0           ; OL18: entry of the Open vector
                move.w  #40,LIB_VERSION(a0)
                CLRREC  rec_l1open
                CALL    L_OpenLibrary,#40,#M1V,#M8V,#n_lib
                LINE    OLE
                lea     rec_l1open(pc),a2
                bsr     prec
                PV      d0,rout(pc)
                PV      d1,rout+4(pc)
                PV      a0,rout+32(pc)
                bsr     pstd
                CLRREC  rec_l1open           ; OL12: OldOpenLibrary ignores D0
                CALL    L_OldOpenLibrary,#99,#M1V,#M8V,#n_lib
                LINE    OL12
                PV      d0,rout(pc)
                bsr     pstd
                lea     fl2(pc),a0           ; OL13: v40 pri 0, then v50 pri -5
                lea     n_lib(pc),a1
                moveq   #-5,d0
                moveq   #9,d1
                moveq   #30,d2
                bsr     initlib
                lea     fl2(pc),a0
                move.w  #50,LIB_VERSION(a0)
                lea     fl2(pc),a1
                jsr     L_AddLibrary(a6)
                CLRREC  rec_l1open
                CLRREC  rec_l2open
                CALL    L_OpenLibrary,#45,#M1V,#M8V,#n_lib
                LINE    OL13a
                PV      d0,rout(pc)
                PW      c1,rec_l1open+R_CNT(pc)
                PW      c2,rec_l2open+R_CNT(pc)
                bsr     pstd
                CLRREC  rec_l1open
                CLRREC  rec_l2open
                CALL    L_OpenLibrary,#40,#M1V,#M8V,#n_lib
                LINE    OL13b
                PV      d0,rout(pc)
                PW      c1,rec_l1open+R_CNT(pc)
                PW      c2,rec_l2open+R_CNT(pc)
                bsr     pstd
                LINE    OL15                 ; OL15: first Open returns 0, the second node is not tried
                CLRREC  rec_l2open
                BEH     1<<BB_D0,0,0
                CALL    L_OpenLibrary,#0,#M1V,#M8V,#n_lib
                PV      d0,rout(pc)
                PW      c2,rec_l2open+R_CNT(pc)
                bsr     pstd
                lea     fl2(pc),a1
                bsr     unlink
                LINE    OL14a                ; OL14: the Open's D0 as is
                BEH     1<<BB_D0,0,0
                CALL    L_OpenLibrary,#0,#M1V,#M8V,#n_lib
                PV      d0,rout(pc)
                bsr     pstd
                LINE    OL14b
                BEH     1<<BB_D0,0,$1234
                CALL    L_OpenLibrary,#0,#M1V,#M8V,#n_lib
                PV      d0,rout(pc)
                bsr     pstd
                LINE    OL16                 ; OL16: the Open changes A6, A1, A0, D1
                BEH     (1<<BB_D0)|(1<<BB_A6)|(1<<BB_JUNK),0,$1234
                CALL    L_OpenLibrary,#0,#M1V,#M8V,#n_lib
                PV      d0,rout(pc)
                PV      d1,rout+4(pc)
                PV      a0,rout+32(pc)
                PV      a1,rout+36(pc)
                bsr     pstd
                LINE    OL17                 ; OL17: graphics.library open count (property of graphics)
                lea     EB_LIBLIST(a6),a0
                lea     n_gfx(pc),a1
                jsr     L_FindName(a6)
                move.l  d0,gfxb-vars(a5)
                beq     .nog
                move.l  d0,a2
                PW      gv,LIB_VERSION(a2)
                PW      g0,LIB_OPENCNT(a2)
                CALL    L_OpenLibrary,#34,#M1V,#M8V,#n_gfx
                PV      d0,rout(pc)
                PW      g1,LIB_OPENCNT(a2)
                CALL    L_OpenLibrary,#35,#M1V,#M8V,#n_gfx
                PV      o35,rout(pc)
                PW      g2,LIB_OPENCNT(a2)
                CALL    L_CloseLibrary,#M0V,#M1V,#M8V,gfxb-vars(a5)
                PW      g3,LIB_OPENCNT(a2)
.nog:           PV      gb,gfxb-vars(a5)
                bsr     pstd
                LINE    OL19                 ; OL19: name absent
                CALL    L_OpenLibrary,#0,#M1V,#M8V,#n_nolib
                PV      d0,rout(pc)
                bsr     pstd
                LINE    CL1                  ; CL1: CloseLibrary passes Close's D0 through
                CLRREC  rec_l1close
                bsr     mkseg
                CALL    L_CloseLibrary,#M0V,#M1V,#M8V,#fl1
                PV      d0,rout(pc)
                PV      es,es-vars(a5)
                lea     rec_l1close(pc),a2
                bsr     prec
                bsr     pstd
                LINE    RL1                  ; RL1: RemLibrary calls Expunge, does not unlink
                CLRREC  rec_l1exp
                bsr     mkseg
                CALL    L_RemLibrary,#M0V,#M1V,#M8V,#fl1
                PV      d0,rout(pc)
                PV      es,es-vars(a5)
                lea     rec_l1exp(pc),a2
                bsr     prec
                lea     EB_LIBLIST(a6),a0
                lea     fl1(pc),a1
                bsr     inlist
                bsr     pkv
                dc.b    "in",0
                even
                bsr     pstd
                lea     fl1(pc),a1
                bsr     unlink

                LINE    AL2a                 ; AL2: SUMUSED|CHANGED, CHANGED only, other flags
                moveq   #6,d4
                bsr     al2
                LINE    AL2b
                moveq   #2,d4
                bsr     al2
                LINE    AL2c
                moveq   #1,d4
                bsr     al2
                LINE    AL2d
                move.l  #$FB,d4
                bsr     al2
                LINE    AL3                  ; AL3: SUMUSED with the right sum
                bsr     inittl
                lea     tl(pc),a0
                bsr     wsum
                swap    d0
                move.w  #$5A5A,d0
                lea     tl(pc),a0
                move.l  d0,LIB_SUM(a0)
                move.b  #4,LIB_FLAGS(a0)
                CALL    L_AddLibrary,#M0V,#M1V,#M8V,#tl
                bsr     ptl
                lea     tl(pc),a1
                bsr     unlink
                LINE    SL1                  ; SL1-SL4: SumLibrary
                moveq   #0,d4
                bsr     slx
                LINE    SL2
                moveq   #2,d4
                bsr     slx
                LINE    SL3
                moveq   #4,d4
                bsr     slx
                LINE    SL4
                moveq   #6,d4
                bsr     slx
                LINE    SL5                  ; SL5: 6 vectors, lib_NegSize 30
                bsr     inittl
                lea     tl(pc),a0
                move.w  #30,LIB_NEGSIZE(a0)
                move.b  #6,LIB_FLAGS(a0)
                CALL    L_AddLibrary,#M0V,#M1V,#M8V,#tl
                bsr     ptl
                lea     tl(pc),a1
                bra     unlink
al2:            bsr     inittl
                lea     tl(pc),a0
                move.b  d4,LIB_FLAGS(a0)
                CALL    L_AddLibrary,#M0V,#M1V,#M8V,#tl
                bsr     ptl
                lea     tl(pc),a1
                bra     unlink
slx:            bsr     inittl
                lea     tl(pc),a0
                move.b  d4,LIB_FLAGS(a0)
                cmp.b   #4,d4
                bne.s   .s
                bsr     wsum
                swap    d0
                move.w  #$5A5A,d0
                lea     tl(pc),a0
                move.l  d0,LIB_SUM(a0)
.s:             CALL    L_SumLibrary,#M0V,#M1V,#M8V,#tl
                PV      d0,rout(pc)
                PV      d1,rout+4(pc)
; ptl: flags, lib_Sum and the expected sum word (upper half) of the throw-away library
ptl:            PB      fl,tl+LIB_FLAGS(pc)
                PV      sm,tl+LIB_SUM(pc)
                lea     tl(pc),a0
                bsr     wsum
                swap    d0
                move.w  #$5A5A,d0
                bsr     pkv
                dc.b    "es",0
                even
                bra     pstd
inittl:         lea     tl(pc),a0
                lea     n_sum(pc),a1
                moveq   #-100,d0
                moveq   #9,d1
                moveq   #36,d2
                bra     initlib

t_res:          lea     resn(pc),a0            ; AR1
                lea     n_res(pc),a1
                moveq   #7,d0
                moveq   #$44,d1
                moveq   #0,d2
                bsr     initlib
                lea     resn(pc),a0
                move.w  #5,LIB_VERSION(a0)
                CALL    L_AddResource,#M0V,#M1V,#M8V,#resn
                LINE    AR1
                PB      ty,resn+LN_TYPE(pc)
                PV      hd,EB_RESLIST(a6)
                PB      d1b,rout+7(pc)
                bsr     pstd
                CALL    L_OpenResource,#99,#M1V,#M8V,#n_res     ; OR1
                LINE    OR1a
                PV      d0,rout(pc)
                PW      ver,resn+LIB_VERSION(pc)
                PB      ty,resn+LN_TYPE(pc)
                PW      oc,resn+LIB_OPENCNT(pc)
                PV      a1,rout+36(pc)
                bsr     pstd
                CALL    L_OpenResource,#99,#M1V,#M8V,#n_nores
                LINE    OR1b
                PV      d0,rout(pc)
                bsr     pstd
                CALL    L_RemResource,#M0V,#M1V,#M8V,#resn      ; RR1
                LINE    RR1
                PV      d0,rout(pc)
                PV      d1,rout+4(pc)
                lea     EB_RESLIST(a6),a0
                lea     resn(pc),a1
                bsr     inlist
                bsr     pkv
                dc.b    "in",0
                even
                bra     pstd

t_n1:           CALL    L_CloseLibrary,#M0V,#M1V,#M8V,#0        ; N1: CloseLibrary(NULL)
                LINE    N1
                PV      d0,rout(pc)
                bra     pstd

; AL4 (argument A): AddLibrary of a SUMUSED library whose sum is wrong -> dead-end alert $81000003
t_al4:          lea     m_al4(pc),a0
                bsr     sputs
                bsr     inittl
                lea     tl(pc),a0
                move.b  #4,LIB_FLAGS(a0)
                lea     tl(pc),a1
                jsr     L_AddLibrary(a6)
                lea     m_al4r(pc),a0
                bsr     sputs
                moveq   #0,d0
                jsr     L_Wait(a6)

; ---------------------------------------------------------------- call wrapper
; xcall: c_lvo/c_d0/c_d1/c_a0/c_a1 -> calls ExecBase+c_lvo with markers in D2-D7/A2-A4; rout = D0-D7/A0-A6 on
; return, r_nest = IDNestCnt:TDNestCnt after the call, r_rm = marked registers changed (bits 0-5 D2-D7, 6-8 A2-A4).
; beh is cleared afterwards.
xcall:          movem.l d2-d7/a2-a4/a6,-(sp)
                pea     .ret(pc)
                move.l  ($4).w,a6
                move.w  c_lvo-vars(a5),d0
                ext.l   d0
                add.l   a6,d0
                move.l  d0,-(sp)
                movem.l marks(pc),d2-d7/a2-a4
                movem.l c_d0-vars(a5),d0-d1/a0-a1
                rts
.ret:           movem.l d0-d7/a0-a6,rout
                lea     vars(pc),a5
                move.l  ($4).w,a6
                move.b  EB_IDNEST(a6),r_nest-vars(a5)
                move.b  EB_TDNEST(a6),r_nest+1-vars(a5)
                lea     rout+8(pc),a0
                lea     marks(pc),a1
                moveq   #0,d1
                moveq   #0,d2
                moveq   #5,d0
.m1:            cmpm.l  (a0)+,(a1)+
                beq.s   .m2
                bset    d2,d1
.m2:            addq.w  #1,d2
                dbra    d0,.m1
                lea     rout+40(pc),a0
                moveq   #2,d0
.m3:            cmpm.l  (a0)+,(a1)+
                beq.s   .m4
                bset    d2,d1
.m4:            addq.w  #1,d2
                dbra    d0,.m3
                move.w  d1,r_rm-vars(a5)
                clr.b   beh-vars(a5)
                movem.l (sp)+,d2-d7/a2-a4/a6
                rts

; ---------------------------------------------------------------- fake vectors
; stub (a5 = record, caller's A5 on the stack): records D0/D1/A0/A1/A6, the nest counters, bytes 20-31 and
; LN_TYPE of the structure in A1, counts the call, then does what beh says.
stub:           movem.l d0-d1/a0-a1/a6,(a5)
                move.l  a4,-(sp)
                move.l  ($4).w,a4
                move.b  EB_IDNEST(a4),R_ID(a5)
                move.b  EB_TDNEST(a4),R_TD(a5)
                move.l  d0,-(sp)
                moveq   #11,d0
.cp:            move.b  20(a1,d0.w),R_B(a5,d0.w)
                dbra    d0,.cp
                move.l  (sp)+,d0
                move.b  LN_TYPE(a1),R_TY(a5)
                addq.w  #1,R_CNT(a5)
                lea     beh(pc),a4
                btst    #BB_ERR,(a4)
                beq.s   .s1
                move.b  1(a4),IO_ERROR(a1)
.s1:            btst    #BB_NOQ,(a4)
                beq.s   .s2
                bclr    #0,IO_FLAGS(a1)
.s2:            btst    #BB_REPLY,(a4)
                beq.s   .s3
                movem.l d0-d1/a0-a1/a6,-(sp)
                move.l  ($4).w,a6
                jsr     L_ReplyMsg(a6)
                movem.l (sp)+,d0-d1/a0-a1/a6
.s3:            btst    #BB_D0,(a4)
                beq.s   .k
                move.l  2(a4),d0
                bra.s   .s4
.k:             tst.b   R_KIND(a5)
                beq.s   .s4
                moveq   #0,d0
                cmp.b   #2,R_KIND(a5)
                bne.s   .s4
                move.l  R_A6(a5),d0
.s4:            btst    #BB_A6,(a4)
                beq.s   .s5
                move.l  #$A6A6A6A6,a6
.s5:            btst    #BB_JUNK,(a4)
                beq.s   .s6
                move.l  #$D1D1D1D1,d1
                move.l  #$D2D2D2D2,d2
                move.l  #$A0A0A0A0,a0
                move.l  #$A1A1A1A1,a1
                move.l  #$A2A2A2A2,a2
.s6:            move.l  (sp)+,a4
                move.l  (sp)+,a5
                rts
                STUB    v_dopen,rec_dopen
                STUB    v_dclose,rec_dclose
                STUB    v_dexp,rec_dexp
                STUB    v_dbio,rec_dbio
                STUB    v_dabort,rec_dabort
                STUB    v_d3open,rec_d3open
                STUB    v_d3x,rec_d3x
                STUB    v_l1open,rec_l1open
                STUB    v_l1close,rec_l1close
                STUB    v_l1exp,rec_l1exp
                STUB    v_l2open,rec_l2open
                STUB    v_l2x,rec_l2x
v_null:         moveq   #0,d0
                rts

; software interrupt of P4/R3: counts, records A1, A6, SR
softcode:       movem.l d0/a0,-(sp)
                lea     sir(pc),a0
                addq.w  #1,(a0)
                move.l  a1,2(a0)
                move.l  a6,6(a0)
                move.w  sr,d0
                move.w  d0,10(a0)
                movem.l (sp)+,d0/a0
                rts
; routine of PutMsg action 3: records A0, A1, D0, the port's first message and IDNestCnt, returns known values
act3:           move.l  a2,-(sp)
                lea     a3r(pc),a2
                addq.w  #1,(a2)
                move.l  a0,2(a2)
                move.l  a1,6(a2)
                move.l  d0,10(a2)
                move.l  MP_MSGLIST(a1),14(a2)
                move.l  ($4).w,a0
                move.b  EB_IDNEST(a0),18(a2)
                move.l  (sp)+,a2
                move.l  #$13579BDF,d0
                move.l  #$2468ACE0,d1
                move.l  #$0A0A0A0A,a0
                move.l  #$0B0B0B0B,a1
                rts

; ---------------------------------------------------------------- helpers (a5 = vars, a6 = ExecBase)
; initport(a0 = port, d0 = flags, d1 = signal bit, a1 = task): NT_MSGPORT, empty list
initport:       move.b  #4,LN_TYPE(a0)
                move.b  d0,MP_FLAGS(a0)
                move.b  d1,MP_SIGBIT(a0)
                move.l  a1,MP_SIGTASK(a0)
                lea     MP_MSGLIST(a0),a0
newlist:        move.l  a0,8(a0)
                clr.l   4(a0)
                move.l  a0,(a0)
                addq.l  #4,(a0)
                rts
; rstP: P = PA_SIGNAL to this task on sigP, empty; signal cleared. rstP0: same without clearing the signal.
rstP:           bsr.s   rstP0
                bra.s   clrsig
rstP0:          lea     portP(pc),a0
                moveq   #0,d0
                move.b  sigP-vars(a5),d1
                move.l  me-vars(a5),a1
                bra.s   initport
sigmask:        moveq   #0,d1
                move.b  sigP-vars(a5),d1
                moveq   #0,d0
                bset    d1,d0
                rts
clrsig:         bsr.s   sigmask
                move.l  d0,d1
                moveq   #0,d0
                jmp     L_SetSignal(a6)
setsig:         bsr.s   sigmask
                move.l  d0,d1
                jmp     L_SetSignal(a6)
psig:           moveq   #0,d0
                moveq   #0,d1
                jsr     L_SetSignal(a6)
                moveq   #0,d1
                move.b  sigP-vars(a5),d1
                lsr.l   d1,d0
                and.l   #1,d0
                bsr     pkv
                dc.b    "sg",0
                even
                rts
clrcnt:         lea     sir(pc),a0
                clr.w   (a0)
                clr.l   2(a0)
                clr.l   6(a0)
                clr.w   10(a0)
                lea     a3r(pc),a0
                moveq   #9,d0
.c:             clr.w   (a0)+
                dbra    d0,.c
                rts
; clrrec(a0): record cleared, its default-D0 kind kept
clrrec:         moveq   #R_KIND/2-1,d0
.c:             clr.w   (a0)+
                dbra    d0,.c
                rts
; rstIO: fake-device request cleared, reply port P, io_Device = the fake device, ln_Type 5
rstIO:          lea     ior(pc),a0
                moveq   #11,d0
.c:             clr.l   (a0)+
                dbra    d0,.c
                lea     ior(pc),a0
                move.l  #portP,MN_REPLYPORT(a0)
                move.w  #48,MN_LENGTH(a0)
                move.l  #fd,IO_DEVICE(a0)
                move.b  #5,LN_TYPE(a0)
                rts
; fillio: byte i of the request = $80 + i
fillio:         lea     ior(pc),a0
                moveq   #0,d0
.l:             move.b  d0,d1
                add.b   #$80,d1
                move.b  d1,(a0)+
                addq.w  #1,d0
                cmp.w   #48,d0
                bne.s   .l
                rts
; tadd(d0 = micro, d1 = secs): TR_ADDREQUEST request, reply port P, io_Flags 0
tadd:           lea     treq(pc),a1
                move.l  #portP,MN_REPLYPORT(a1)
                move.w  #9,IO_COMMAND(a1)
                clr.b   IO_FLAGS(a1)
                clr.b   IO_ERROR(a1)
                move.l  d1,TV_SECS(a1)
                move.l  d0,TV_MICRO(a1)
                rts
; tnow -> d0 = secs, d1 = micro (TR_GETSYSTIME)
tnow:           lea     treqs(pc),a1
                move.w  #10,IO_COMMAND(a1)
                jsr     L_DoIO(a6)
                lea     treqs(pc),a1
                move.l  TV_SECS(a1),d0
                move.l  TV_MICRO(a1),d1
                rts
tstart:         bsr.s   tnow
                movem.l d0-d1,tsave-vars(a5)
                rts
; telapsed -> d0 = microseconds since tstart
telapsed:       bsr.s   tnow
                sub.l   tsave+4-vars(a5),d1
                sub.l   tsave-vars(a5),d0
                mulu    #15625,d0
                lsl.l   #6,d0
                add.l   d1,d0
                rts
; initlib(a0 = node, a1 = name, d0 = pri, d1 = type, d2 = lib_NegSize): flags 0, version 1, lib_Sum $5A5A5A5A
initlib:        clr.l   (a0)
                clr.l   4(a0)
                move.b  d1,LN_TYPE(a0)
                move.b  d0,LN_PRI(a0)
                move.l  a1,LN_NAME(a0)
                clr.b   LIB_FLAGS(a0)
                move.w  d2,LIB_NEGSIZE(a0)
                move.w  #1,LIB_VERSION(a0)
                move.l  #$5A5A5A5A,LIB_SUM(a0)
                clr.w   LIB_OPENCNT(a0)
                rts
; wsum(a0 = library) -> d0 = 16-bit sum of the words of the lib_NegSize bytes below it (upper word 0)
wsum:           moveq   #0,d0
                moveq   #0,d1
                move.w  LIB_NEGSIZE(a0),d1
                move.l  a0,a1
                sub.l   d1,a1
                lsr.w   #1,d1
                bra.s   .n
.l:             add.w   (a1)+,d0
.n:             dbra    d1,.l
                rts
; inlist(a0 = list, a1 = node) -> d0 = 1 if the node is linked in the list
inlist:         move.l  (a0),a0
.l:             tst.l   (a0)
                beq.s   .no
                cmp.l   a0,a1
                beq.s   .yes
                move.l  (a0),a0
                bra.s   .l
.no:            moveq   #0,d0
                rts
.yes:           moveq   #1,d0
                rts
; unlink(a1 = node): Remove under Forbid
unlink:         jsr     L_Forbid(a6)
                jsr     L_Remove(a6)
                jmp     L_Permit(a6)
; mkseg: a 16-byte block shaped as a one-hunk seglist (size, null link); its BPTR goes to es and to beh's D0 (the
; Close/Expunge result is freed as a seglist by ramlib on 1.3, as by our exec)
mkseg:          moveq   #16,d0
                move.l  #$10001,d1
                jsr     L_AllocMem(a6)
                tst.l   d0
                beq.s   .r
                move.l  d0,a0
                move.l  #16,(a0)
                addq.l  #4,d0
                lsr.l   #2,d0
.r:             move.l  d0,es-vars(a5)
                move.l  d0,beh+2-vars(a5)
                move.b  #1<<BB_D0,beh-vars(a5)
                rts

; ---------------------------------------------------------------- output
; pmap: addresses of the test structures
pmap:           LINE    MAP
                PV      P,#portP
                PV      Q,#portQ
                PV      R,#portR
                PV      S0,#portS0
                PV      S1,#portS1
                PV      S2,#portS2
                PV      S3,#portS3
                PV      M1,#msg1
                PV      M2,#msg2
                PV      M3,#msg3
                PV      IOR,#ior
                PV      TR,#treq
                PV      INT,#intr
                PV      ACT3,#act3
                PV      FD,#fd
                PV      FD2,#fd2
                PV      FD3,#fd3
                PV      FL1,#fl1
                PV      FL2,#fl2
                PV      TL,#tl
                PV      RS,#resn
                PV      X,#nodeX
                PV      Y,#nodeY
                PV      EX,exb-vars(a5)
                PV      ME,me-vars(a5)
                PV      NDEV,#n_dev
                PV      NLIB,#n_lib
                PV      NPORT,#n_port
                PV      NNONE,#n_none
                PV      NGFX,#n_gfx
                PV      NRES,#n_res
                moveq   #0,d0
                move.b  sigP-vars(a5),d0
                bsr     pkv
                dc.b    "SIGP",0
                even
                moveq   #10,d1
                bra     putc
; pstd: " rm= ne= e6=" then end of line
pstd:           PW      rm,r_rm-vars(a5)
                PW      ne,r_nest-vars(a5)
                moveq   #0,d0
                move.l  rout+56(pc),d1
                cmp.l   exb-vars(a5),d1
                bne.s   .n
                moveq   #1,d0
.n:             bsr     pkv
                dc.b    "e6",0
                even
                moveq   #10,d1
                bra     putc
; prec(a2 = record)
prec:           PV      bd0,R_D0(a2)
                PV      bd1,R_D1(a2)
                PV      ba0,R_A0(a2)
                PV      ba1,R_A1(a2)
                PV      ba6,R_A6(a2)
                PW      bn,R_ID(a2)
                PV      b0,R_B(a2)
                PV      b1,R_B+4(a2)
                PV      b2,R_B+8(a2)
                PB      bt,R_TY(a2)
                PW      bc,R_CNT(a2)
                rts
; plistP: " L=<node>,<node>," for port P (16 nodes at most)
plistP:         movem.l d2/a2,-(sp)
                lea     m_l(pc),a0
                bsr     puts
                lea     portP+MP_MSGLIST(pc),a2
                move.l  (a2),a2
                moveq   #15,d2
.l:             tst.l   (a2)
                beq.s   .e
                move.l  a2,d0
                bsr     phex8
                moveq   #',',d1
                bsr     putc
                move.l  (a2),a2
                dbra    d2,.l
.e:             movem.l (sp)+,d2/a2
                rts
; pid: inline name at the start of a line; pid0: prefix a4, then the OL table counter
pid:            move.l  (sp),a0
                bsr     puts
                move.l  a0,d1
                addq.l  #1,d1
                and.b   #$FE,d1
                move.l  d1,(sp)
                rts
pid0:           move.l  a4,a0
                bsr     puts
                addq.w  #1,olno-vars(a5)
                moveq   #0,d0
                move.w  olno-vars(a5),d0
                divu    #10,d0
                tst.w   d0
                beq.s   .u
                move.b  d0,d1
                add.b   #'0',d1
                bsr     putc
.u:             swap    d0
                move.b  d0,d1
                add.b   #'0',d1
                bra     putc
; pkv(d0): " <inline name>=<8 hex digits>"
pkv:            move.l  (sp),a0
                move.l  d0,-(sp)
                moveq   #' ',d1
                bsr     putc
                bsr     puts
                moveq   #'=',d1
                bsr     putc
                move.l  (sp)+,d0
                bsr     phex8
                move.l  a0,d1
                addq.l  #1,d1
                and.b   #$FE,d1
                move.l  d1,(sp)
                rts
; putc(d1.b): appended to the output buffer. Preserves everything.
putc:           movem.l a0-a1,-(sp)
                lea     optr(pc),a1
                move.l  (a1),a0
                move.b  d1,(a0)+
                move.l  a0,(a1)
                movem.l (sp)+,a0-a1
                rts
; puts(a0): string to the buffer, a0 just past its NUL
puts:           move.b  (a0)+,d1
                beq.s   .e
                bsr.s   putc
                bra.s   puts
.e:             rts
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

; OL1-OL10 then the eight OL11 pairs: lib_Version (word), requested D0 (long)
oltab:          dc.w    40
                dc.l    0
                dc.w    40
                dc.l    39
                dc.w    40
                dc.l    40
                dc.w    40
                dc.l    41
                dc.w    40
                dc.l    $10028
                dc.w    40
                dc.l    $10029
                dc.w    40
                dc.l    $8000
                dc.w    40
                dc.l    $FFFF
                dc.w    40
                dc.l    $FFFFFFFF
                dc.w    40
                dc.l    $10000
                dc.w    $8001                ; OL11 pairs
                dc.l    40
                dc.w    $FFFF
                dc.l    1
                dc.w    40
                dc.l    $7FFF
                dc.w    $7FFF
                dc.l    $8000
                dc.w    $8000
                dc.l    $8001
                dc.w    $8001
                dc.l    $8000
                dc.w    0
                dc.l    0
                dc.w    0
                dc.l    1

m_start:        dc.b    10,"MLP debut",10,0
m_end:          dc.b    "MLP fin",10,0
m_buf:          dc.b    "MLP buf=",0
m_bend:         dc.b    " end=",0
m_al4:          dc.b    "MLP AL4 go",10,0
m_al4r:         dc.b    "MLP AL4 returned",10,0
m_l:            dc.b    " L=",0
m_o:            dc.b    " O=",0
m_ol:           dc.b    "OL",0
m_olp:          dc.b    "OLP",0
                even
n_timer:        dc.b    "timer.device",0
                even
n_gfx:          dc.b    "graphics.library",0
                even
n_dev:          dc.b    "msgio.device",0
                even
n_none:         dc.b    "msgio.none",0
                even
n_sumdev:       dc.b    "msgio.sumdev",0
                even
n_lib:          dc.b    "msgio.library",0
                even
n_nolib:        dc.b    "msgio.nolib",0
                even
n_sum:          dc.b    "msgio.sum",0
                even
n_res:          dc.b    "msgio.resource",0
                even
n_nores:        dc.b    "msgio.nores",0
                even
n_port:         dc.b    "r12.port",0
                even
n_pnone:        dc.b    "r12.none",0
                even
n_s:            dc.b    "r12.s",0
                even

; ---------------------------------------------------------------- data
                cnop    0,4
vars:
c_lvo:          dc.w    0
c_d0:           dc.l    0
c_d1:           dc.l    0
c_a0:           dc.l    0
c_a1:           dc.l    0
r_nest:         dc.w    0
r_rm:           dc.w    0
beh:            dc.b    0,0
                dc.l    0
me:             dc.l    0
exb:            dc.l    0
obuf:           dc.l    0
optr:           dc.l    0
tsave:          dc.l    0,0
es:             dc.l    0
gfxb:           dc.l    0
olno:           dc.w    0
sigP:           dc.b    0
sigQ:           dc.b    0
argN:           dc.b    0
argA:           dc.b    0
sir:            dc.w    0                    ; softint: count, A1, A6, SR
                dc.l    0,0
                dc.w    0
a3r:            dc.w    0                    ; action 3: count, A0, A1, D0, list head, IDNestCnt
                dc.l    0,0,0,0
                dc.w    0
marks:          dc.l    $11110002,$11110003,$11110004,$11110005,$11110006,$11110007
                dc.l    $1111000A,$1111000B,$1111000C
rout:           dcb.l   15,0
                REC     rec_dopen,0
                REC     rec_dclose,1
                REC     rec_dexp,1
                REC     rec_dbio,0
                REC     rec_dabort,0
                REC     rec_d3open,0
                REC     rec_d3x,1
                REC     rec_l1open,2
                REC     rec_l1close,1
                REC     rec_l1exp,1
                REC     rec_l2open,2
                REC     rec_l2x,1
                cnop    0,4
portP:          dcb.b   36,0
portQ:          dcb.b   36,0
portR:          dcb.b   36,0
portS0:         dcb.b   36,0
portS1:         dcb.b   36,0
portS2:         dcb.b   36,0
portS3:         dcb.b   36,0
msg1:           dcb.b   24,0
msg2:           dcb.b   24,0
msg3:           dcb.b   24,0
ior:            dcb.b   48,0
treq:           dcb.b   40,0
treqs:          dcb.b   40,0
intr:           dcb.b   24,0
nodeX:          dcb.b   8,0
nodeY:          dcb.b   8,0
                cnop    0,4
                JV      v_dabort             ; fake device: -36 AbortIO ... -6 Open
                JV      v_dbio
                JV      v_null
                JV      v_dexp
                JV      v_dclose
                JV      v_dopen
fd:             dcb.b   36,0
                JV      v_null
                JV      v_null
                JV      v_null
                JV      v_null
                JV      v_null
                JV      v_null
fd2:            dcb.b   36,0
                JV      v_null
                JV      v_null
                JV      v_null
                JV      v_d3x
                JV      v_d3x
                JV      v_d3open
fd3:            dcb.b   36,0
                JV      v_null               ; fake library: -30 ... -6 Open
                JV      v_null
                JV      v_l1exp
                JV      v_l1close
                JV      v_l1open
fl1:            dcb.b   36,0
                JV      v_null
                JV      v_null
                JV      v_l2x
                JV      v_l2x
                JV      v_l2open
fl2:            dcb.b   36,0
                JV      v_null               ; throw-away library of the checksum tests (6 vectors)
                JV      v_null
                JV      v_null
                JV      v_null
                JV      v_null
                JV      v_null
tl:             dcb.b   36,0
resn:           dcb.b   36,0
