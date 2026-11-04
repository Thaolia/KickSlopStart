; tests/gregion_probe.s - HUNK test executable (TEST ASSET, NOT ROM code).
; Black-box probe "graphics.library regions" (docs/analysis/graphics-regions-v34.md §12, expected values §11, §6-§7).
; Run from the startup-sequence of a floppy (tests/gregion_probe.sh). Calls NewRegion, DisposeRegion, ClearRegion,
; OrRectRegion, AndRectRegion, XorRectRegion, ClearRectRegion, OrRegionRegion, XorRegionRegion and AndRegionRegion
; through their public LVOs and writes, after every call, to the direct serial port (SERDAT):
;   <id> D0=<hex8> C=<changed registers> [P=<rect ptr> Q=<return address>] B=minx,miny,maxx,maxy N=<count> L=<ok|bad>
;     minx,miny,maxx,maxy =k|+|+k    (one line per node, relative)
; Node marks: "=k" the node is node k of the region before the call and was not allocated during it (kept);
; "+" allocated during the call; "+k" allocated during the call at an address node k had before (recycled).
; AllocMem and FreeMem are wrapped with SetFunction for the whole run (restored before "GRG fin"); during each
; region call the wrappers record "A<size>/<flags>", "F<size>" (this task only) with the addresses, and in R8 a
; countdown makes the N-th AllocMem of the call return 0 ("X<size>/<flags>"). The log is printed for R7/R8 only.
; The alert cases F3, F4b, F7a, F7b are NOT run (dead-end alert = reset).
; Assembly: vasmm68k_mot -Fhunkexe -kick1hunks -nosym -m68000 -o build/gregion_probe tests/gregion_probe.s
; Authored code; public structures (graphics/regions.h, exec/execbase.h).

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018
SERPER   EQU $DFF032
NSNAP    EQU 32          ; nodes remembered for the identity marks
NMAX     EQU 64          ; walk limit of a dump (more = L=bad)
LOGMAX   EQU 64          ; entries of the allocation log (12 bytes each)
EB_THISTASK EQU 276      ; ExecBase.ThisTask

; exec LVOs checked against AROS rom/exec/exec.conf (open/close/2 skipped slots first)
LVO_Forbid       EQU -132
LVO_Permit       EQU -138
LVO_AllocMem     EQU -198
LVO_FreeMem      EQU -210
LVO_CloseLibrary EQU -414
LVO_SetFunction  EQU -420
LVO_OpenLibrary  EQU -552
; graphics LVOs checked against AROS rom/graphics/graphics.conf and src/graphics/graphics_lib.s
LVO_AndRectRegion   EQU -504
LVO_OrRectRegion    EQU -510
LVO_NewRegion       EQU -516
LVO_ClearRectRegion EQU -522
LVO_ClearRegion     EQU -528
LVO_DisposeRegion   EQU -534
LVO_XorRectRegion   EQU -558
LVO_OrRegionRegion  EQU -612
LVO_XorRegionRegion EQU -618
LVO_AndRegionRegion EQU -624

; logv block (wrappers, PC-relative)
LV_TASK  EQU 0
LV_OLDA  EQU 4
LV_OLDF  EQU 8
LV_ON    EQU 12
LV_CNT   EQU 14
LV_N     EQU 16          ; bytes used in LV_BUF (12 per entry: type, size, flags, address)
LV_TYPE  EQU 18
LV_BUF   EQU 20

; --- IDS "text": a2 = id string
IDS             macro
                lea     .i\@(pc),a2
                bra.w   .j\@
.i\@:           dc.b    \1,0
                even
.j\@:
                endm
; --- RCT "id",lvo,slot,x0,y0,x1,y1: region-rectangle call on slot, dump of the slot
RCT             macro
                move.w  #\4,rect-vars(a4)
                move.w  #\5,rect+2-vars(a4)
                move.w  #\6,rect+4-vars(a4)
                move.w  #\7,rect+6-vars(a4)
                move.l  rgs+4*\3-vars(a4),arga0-vars(a4)
                lea     rect-vars(a4),a0
                move.l  a0,arga1-vars(a4)
                move.w  #\3,dslot-vars(a4)
                move.w  #-1,dslot2-vars(a4)
                move.w  #-1,newslot-vars(a4)
                IDS     \1
                move.w  #\2,d0
                bsr     op
                endm
ORR             macro
                RCT     \1,LVO_OrRectRegion,\2,\3,\4,\5,\6
                endm
ANDR            macro
                RCT     \1,LVO_AndRectRegion,\2,\3,\4,\5,\6
                endm
XORR            macro
                RCT     \1,LVO_XorRectRegion,\2,\3,\4,\5,\6
                endm
CLRR            macro
                RCT     \1,LVO_ClearRectRegion,\2,\3,\4,\5,\6
                endm
; --- RRG "id",lvo,s1,s2: region-region call (R1 = slot s1 in A0, R2 = slot s2 in A1), dumps R2 then R1
RRG             macro
                move.l  rgs+4*\3-vars(a4),arga0-vars(a4)
                move.l  rgs+4*\4-vars(a4),arga1-vars(a4)
                move.w  #\4,dslot-vars(a4)
                move.w  #\3,dslot2-vars(a4)
                move.w  #-1,newslot-vars(a4)
                IDS     \1
                move.w  #\2,d0
                bsr     op
                endm
ORRG            macro
                RRG     \1,LVO_OrRegionRegion,\2,\3
                endm
XORRG           macro
                RRG     \1,LVO_XorRegionRegion,\2,\3
                endm
ANDRG           macro
                RRG     \1,LVO_AndRegionRegion,\2,\3
                endm
; --- NEWR "id",slot: NewRegion, result stored in the slot
NEWR            macro
                move.l  #$11110008,arga0-vars(a4)
                move.l  #$11110009,arga1-vars(a4)
                move.w  #\2,dslot-vars(a4)
                move.w  #-1,dslot2-vars(a4)
                move.w  #\2,newslot-vars(a4)
                IDS     \1
                move.w  #LVO_NewRegion,d0
                bsr     op
                endm
; --- CLRG "id",slot: ClearRegion
CLRG            macro
                move.l  rgs+4*\2-vars(a4),arga0-vars(a4)
                move.l  #$11110009,arga1-vars(a4)
                move.w  #\2,dslot-vars(a4)
                move.w  #-1,dslot2-vars(a4)
                move.w  #-1,newslot-vars(a4)
                IDS     \1
                move.w  #LVO_ClearRegion,d0
                bsr     op
                endm
; --- DISP "id",slot: DisposeRegion, slot cleared
DISP            macro
                move.l  rgs+4*\2-vars(a4),arga0-vars(a4)
                move.l  #$11110009,arga1-vars(a4)
                move.w  #-1,dslot-vars(a4)
                move.w  #-1,dslot2-vars(a4)
                move.w  #-1,newslot-vars(a4)
                IDS     \1
                move.w  #LVO_DisposeRegion,d0
                bsr     op
                clr.l   rgs+4*\2-vars(a4)
                endm
; --- LOG: print the allocation log of the next call; FAILN n: same, and its n-th AllocMem returns 0
LOG             macro
                move.b  #1,wantlog-vars(a4)
                clr.w   wantcnt-vars(a4)
                endm
FAILN           macro
                move.b  #1,wantlog-vars(a4)
                move.w  #\1,wantcnt-vars(a4)
                endm

                section code,code
_start:
                movem.l d2-d7/a2-a6,-(sp)
                lea     vars(pc),a4
                move.w  #372,SERPER
                move.l  4.w,a6
                lea     logv(pc),a0
                move.l  EB_THISTASK(a6),LV_TASK(a0)
                lea     gfxname(pc),a1
                moveq   #0,d0
                jsr     LVO_OpenLibrary(a6)
                move.l  d0,gfxb-vars(a4)
                beq     .out
                lea     m_start(pc),a0
                bsr     puts
; --- AllocMem/FreeMem wrappers (whole run)
                move.l  4.w,a6
                jsr     LVO_Forbid(a6)
                move.l  a6,a1
                move.w  #LVO_AllocMem,a0
                lea     allocw(pc),a2
                move.l  a2,d0
                jsr     LVO_SetFunction(a6)
                lea     logv(pc),a0
                move.l  d0,LV_OLDA(a0)
                move.l  a6,a1
                move.w  #LVO_FreeMem,a0
                lea     freew(pc),a2
                move.l  a2,d0
                jsr     LVO_SetFunction(a6)
                lea     logv(pc),a0
                move.l  d0,LV_OLDF(a0)
                jsr     LVO_Permit(a6)

; --- R1 V1: OrRectRegion
                NEWR    "V1.0 New",0
                ORR     "V1.1 Or",0,0,0,9,9
                ORR     "V1.2 Or",0,5,5,14,14
                ORR     "V1.3 Or",0,20,3,25,4
                ORR     "V1.4 Or",0,-4,2,30,6
                DISP    "V1.5 Dispose",0
; --- V2
                NEWR    "V2.0 New",0
                ORR     "V2.1 Or",0,10,10,19,19
                ORR     "V2.2 Or",0,12,12,15,15
                ORR     "V2.3 Or",0,10,10,19,19
                ORR     "V2.4 Or",0,20,10,29,19
                ORR     "V2.5 Or",0,5,20,8,22
                CLRG    "V2.6 Clear",0
                DISP    "V2.7 Dispose",0
; --- R2 V3: AndRectRegion, V10 (P/Q printed)
                NEWR    "V3.0 New",0
                ANDR    "V3.1 And",0,0,0,5,5
                ORR     "V3.2a Or",0,0,0,9,9
                ORR     "V3.2b Or",0,10,0,19,9
                ORR     "V3.2c Or",0,0,10,19,19
                ANDR    "V3.2 And",0,5,5,14,14
                CLRG    "V3.3a Clear",0
                ORR     "V3.3b Or",0,0,0,9,9
                ANDR    "V3.3 And",0,2,3,4,5
                CLRG    "V3.4a Clear",0
                ORR     "V3.4b Or",0,0,0,9,9
                ORR     "V3.4c Or",0,20,20,29,29
                ANDR    "V3.4 And",0,0,0,25,25
                CLRG    "V3.5a Clear",0
                ORR     "V3.5b Or",0,0,0,9,9
                ANDR    "V3.5 And",0,50,50,60,60
                ORR     "V3.5c Or",0,3,3,4,4
                CLRG    "V3.6a Clear",0
                ORR     "V3.6b Or",0,10,10,29,29
                ANDR    "V3.6 And",0,0,0,99,99
                ANDR    "V3.6c And",0,15,5,40,25
                CLRG    "V10a Clear",0
                ORR     "V10b Or",0,0,0,19,19
                ANDR    "V10 And",0,5,5,14,14
                DISP    "V3.7 Dispose",0
; --- R3 V4: XorRectRegion
                NEWR    "V4.0 New",0
                XORR    "V4.1 Xor",0,0,0,9,9
                XORR    "V4.2 Xor",0,5,5,14,14
                XORR    "V4.3 Xor",0,0,0,9,9
                XORR    "V4.4 Xor",0,5,5,14,14
                XORR    "V4.5 Xor",0,0,0,9,9
                XORR    "V4.6 Xor",0,0,0,4,9
                XORR    "V4.7 Xor",0,5,0,9,9
                DISP    "V4.8 Dispose",0
; --- R4 V5: ClearRectRegion
                NEWR    "V5.0 New",0
                ORR     "V5.0b Or",0,0,0,19,19
                CLRR    "V5.1 ClearRect",0,5,5,9,9
                CLRR    "V5.2 ClearRect",0,0,0,19,4
                CLRR    "V5.3 ClearRect",0,100,100,110,110
                CLRR    "V5.4 ClearRect",0,-5,-5,30,30
                DISP    "V5.5 Dispose",0
; --- R5 V6-V8c: region-region (R1 = slot 1, R2 = slot 2)
                NEWR    "V6a New R1",1
                ORR     "V6b Or R1",1,0,0,9,9
                ORR     "V6c Or R1",1,20,0,29,9
                NEWR    "V6d New R2",2
                ORR     "V6e Or R2",2,5,5,24,14
                ORRG    "V6 OrRR",1,2
                CLRG    "V7a Clear R2",2
                ORR     "V7b Or R2",2,5,5,24,14
                XORRG   "V7 XorRR",1,2
                CLRG    "V8a Clear R2",2
                ORR     "V8b Or R2",2,5,5,24,14
                ANDRG   "V8 AndRR",1,2
                CLRG    "V8b.a Clear R1",1
                ORR     "V8b.b Or R1",1,0,0,9,9
                CLRG    "V8b.c Clear R2",2
                ORR     "V8b.d Or R2",2,50,50,59,59
                ANDRG   "V8b AndRR",1,2
                CLRG    "V8b2.a Clear R1",1
                CLRG    "V8b2.b Clear R2",2
                ORR     "V8b2.c Or R2",2,50,50,59,59
                ANDRG   "V8b2 AndRR",1,2
                ORR     "V8c.a Or R1",1,0,0,9,9
                CLRG    "V8c.b Clear R2",2
                ORRG    "V8c1 OrRR",1,2
                CLRG    "V8c.c Clear R1",1
                XORRG   "V8c2 XorRR",1,2
                DISP    "V8d Dispose R1",1
                DISP    "V8e Dispose R2",2
; --- R6 V9: inverted rectangles
                NEWR    "V9.0 New",0
                ORR     "V9.1 Or",0,10,10,5,5
                ORR     "V9.2 Or",0,0,0,19,19
                CLRG    "V9.3a Clear",0
                ORR     "V9.3b Or",0,0,0,19,19
                ORR     "V9.3 Or",0,10,10,5,5
                XORR    "V9.4 Xor",0,10,10,5,5
                DISP    "V9.5 Dispose",0

; --- R7 allocation logs (§6)
                NEWR    "S1.a New",0
                ORR     "S1.b Or",0,0,0,9,9
                LOG
                ORR     "S1 Or",0,5,5,14,14
                CLRG    "S2.a Clear",0
                XORR    "S2.b Xor",0,0,0,9,9
                XORR    "S2.c Xor",0,5,5,14,14
                LOG
                XORR    "S2 Xor",0,20,20,21,21
                CLRG    "S3.a Clear",0
                XORR    "S3.b Xor",0,0,0,9,9
                XORR    "S3.c Xor",0,5,5,14,14
                LOG
                CLRR    "S3 ClearRect",0,100,100,110,110
                CLRG    "S4.a Clear",0
                XORR    "S4.b Xor",0,0,0,9,9
                XORR    "S4.c Xor",0,5,5,14,14
                LOG
                ANDR    "S4 And",0,2,2,12,12
                CLRG    "S5.a Clear R2",0
                XORR    "S5.b Xor R2",0,0,0,9,9
                XORR    "S5.c Xor R2",0,5,5,14,14
                NEWR    "S5.d New R1",1
                ORR     "S5.e Or R1",1,2,2,12,12
                LOG
                ANDRG   "S5 AndRR",1,0
                LOG
                DISP    "S6 Dispose",0
                DISP    "S6.b Dispose R1",1

; --- R8 failures (non-alert cases only)
                FAILN   1
                NEWR    "F1 New",3
                NEWR    "F2a.a New",0
                FAILN   1
                ORR     "F2a Or",0,5,5,14,14
                CLRG    "F2b.a Clear",0
                ORR     "F2b.b Or",0,0,0,9,9
                FAILN   1
                ORR     "F2b Or",0,5,5,14,14
                CLRG    "F4a.a Clear",0
                FAILN   1
                XORR    "F4a Xor",0,5,5,14,14
                CLRG    "F5.a Clear",0
                ORR     "F5.b Or",0,0,0,9,9
                FAILN   1
                CLRR    "F5 ClearRect",0,0,0,4,4
                NEWR    "F6a.a New R1",1
                ORR     "F6a.b Or R1",1,0,0,9,9
                CLRG    "F6a.c Clear R2",0
                ORR     "F6a.d Or R2",0,5,5,20,20
                FAILN   1
                ANDRG   "F6a AndRR",1,0
                CLRG    "F6b.a Clear R2",0
                ORR     "F6b.b Or R2",0,5,5,20,20
                FAILN   2
                ANDRG   "F6b AndRR",1,0
                CLRG    "F8.a Clear R1",1
                ORR     "F8.b Or R1",1,0,0,9,9
                ORR     "F8.c Or R1",1,20,0,29,9
                CLRG    "F8.d Clear R2",0
                FAILN   2
                ORRG    "F8 OrRR",1,0
                DISP    "F9a Dispose",0
                DISP    "F9b Dispose",1

; --- restore the exec vectors
                move.l  4.w,a6
                jsr     LVO_Forbid(a6)
                move.l  a6,a1
                move.w  #LVO_AllocMem,a0
                lea     logv(pc),a2
                move.l  LV_OLDA(a2),d0
                jsr     LVO_SetFunction(a6)
                move.l  a6,a1
                move.w  #LVO_FreeMem,a0
                lea     logv(pc),a2
                move.l  LV_OLDF(a2),d0
                jsr     LVO_SetFunction(a6)
                jsr     LVO_Permit(a6)

                lea     m_end(pc),a0
                bsr     puts
                move.l  4.w,a6
                move.l  gfxb-vars(a4),a1
                jsr     LVO_CloseLibrary(a6)
.out:           movem.l (sp)+,d2-d7/a2-a6
                moveq   #0,d0
                rts

; --- op(d0.w LVO, a2 id; arga0, arga1, dslot, dslot2, newslot, wantlog, wantcnt): one call and its dump
op:             move.w  d0,lvo-vars(a4)
                move.l  a2,curid-vars(a4)
                move.w  dslot-vars(a4),d0
                bsr     getslot
                bsr     snap
                lea     regsin-vars(a4),a0
                move.l  #$11110000,d1
                moveq   #13,d2
.m:             move.l  d1,(a0)+
                addq.l  #1,d1
                dbra    d2,.m
                move.l  arga0-vars(a4),regsin+32-vars(a4)
                move.l  arga1-vars(a4),regsin+36-vars(a4)
                move.l  gfxb-vars(a4),a6
                move.w  lvo-vars(a4),d0
                lea     0(a6,d0.w),a0
                move.l  a0,tgt-vars(a4)
                lea     logv(pc),a0
                clr.w   LV_N(a0)
                move.w  wantcnt-vars(a4),LV_CNT(a0)
                move.b  #1,LV_ON(a0)
                bsr     tramp
                lea     vars(pc),a4
                lea     logv(pc),a0
                clr.b   LV_ON(a0)
                clr.w   LV_CNT(a0)
; result into a slot (NewRegion)
                move.w  newslot-vars(a4),d0
                bmi.s   .nn
                add.w   d0,d0
                add.w   d0,d0
                lea     rgs-vars(a4),a0
                move.l  regsout-vars(a4),0(a0,d0.w)
.nn:            move.l  curid-vars(a4),a0
                bsr     puts
                lea     m_d0(pc),a0
                bsr     puts
                move.l  regsout-vars(a4),d0
                bsr     phex8
                lea     m_c(pc),a0
                bsr     puts
                bsr     pmask
                cmp.w   #LVO_AndRectRegion,lvo-vars(a4)
                bne.s   .np
                lea     m_p(pc),a0
                bsr     puts
                move.l  arga1-vars(a4),d0
                bsr     phex8
                lea     m_q(pc),a0
                bsr     puts
                lea     tret(pc),a0
                move.l  a0,d0
                bsr     phex8
.np:            move.w  dslot-vars(a4),d0
                bmi.s   .nd
                bsr     getslot
                moveq   #1,d7
                bsr     dump
                bra.s   .d2
.nd:            bsr     nl
.d2:            move.w  dslot2-vars(a4),d0
                bmi.s   .lg
                lea     m_r1(pc),a0
                bsr     puts
                bsr     getslot
                moveq   #0,d7
                bsr     dump
.lg:            tst.b   wantlog-vars(a4)
                beq.s   .x
                bsr     plog
.x:             clr.b   wantlog-vars(a4)
                clr.w   wantcnt-vars(a4)
                rts

; --- tramp: calls tgt with D0-D7/A0-A5 = regsin, A6 = GfxBase; saves D0-D7/A0-A6 in regsout
tramp:          movem.l d2-d7/a2-a6,-(sp)
                pea     tret(pc)
                move.l  tgt(pc),-(sp)
                movem.l regsin(pc),d0-d7/a0-a5
                rts
tret:           movem.l d0-d7/a0-a6,regsout
                movem.l (sp)+,d2-d7/a2-a6
                rts

; --- getslot(d0.w slot or <0) -> a3 region (0 if none)
getslot:        sub.l   a3,a3
                tst.w   d0
                bmi.s   .e
                add.w   d0,d0
                add.w   d0,d0
                lea     rgs-vars(a4),a0
                move.l  0(a0,d0.w),a3
.e:             rts

; --- snap(a3 region): node addresses before the call
snap:           lea     snapa-vars(a4),a0
                moveq   #0,d1
                move.l  a3,d0
                beq.s   .e
                move.l  8(a3),d0
.l:             tst.l   d0
                beq.s   .e
                cmp.w   #NSNAP,d1
                bhs.s   .e
                move.l  d0,(a0)+
                addq.w  #1,d1
                move.l  d0,a1
                move.l  (a1),d0
                bra.s   .l
.e:             move.w  d1,snapn-vars(a4)
                rts

; --- pmask: names of the registers whose value changed (A6 against GfxBase), "-" if none
pmask:          moveq   #0,d4
                moveq   #0,d5
                lea     regsin-vars(a4),a2
                lea     regsout-vars(a4),a3
.l:             move.l  (a3)+,d0
                cmp.w   #14,d5
                bne.s   .r
                cmp.l   gfxb-vars(a4),d0
                bra.s   .t
.r:             cmp.l   (a2)+,d0
.t:             beq.s   .n
                moveq   #1,d4
                lea     rnames(pc),a0
                move.w  d5,d0
                add.w   d0,d0
                move.b  0(a0,d0.w),d1
                bsr     putc
                move.b  1(a0,d0.w),d1
                bsr     putc
.n:             addq.w  #1,d5
                cmp.w   #15,d5
                blo.s   .l
                tst.w   d4
                bne.s   .e
                moveq   #'-',d1
                bsr     putc
.e:             rts

; --- dump(a3 region or 0, d7 = 1 for identity marks): " B=... N=n L=ok|bad" then the nodes
dump:           move.l  a3,d0
                bne.s   .h
                lea     m_none(pc),a0
                bsr     puts
                bra     nl
.h:             lea     m_b(pc),a0
                bsr     puts
                move.w  (a3),d0
                bsr     pdec
                bsr     comma
                move.w  2(a3),d0
                bsr     pdec
                bsr     comma
                move.w  4(a3),d0
                bsr     pdec
                bsr     comma
                move.w  6(a3),d0
                bsr     pdec
                moveq   #0,d5
                moveq   #1,d6
                lea     8(a3),a1
                move.l  8(a3),d0
.c:             beq.s   .cd
                move.l  d0,a0
                cmp.l   4(a0),a1
                beq.s   .ok
                moveq   #0,d6
.ok:            move.l  a0,a1
                addq.w  #1,d5
                cmp.w   #NMAX,d5
                bhs.s   .ov
                move.l  (a0),d0
                bra.s   .c
.ov:            moveq   #0,d6
.cd:            lea     m_n(pc),a0
                bsr     puts
                move.w  d5,d0
                bsr     pdec
                lea     m_lok(pc),a0
                tst.w   d6
                bne.s   .pl
                lea     m_lbad(pc),a0
.pl:            bsr     puts
                bsr     nl
                move.l  8(a3),a2
.nd:            tst.w   d5
                beq.s   .e
                lea     m_ind(pc),a0
                bsr     puts
                move.w  8(a2),d0
                bsr     pdec
                bsr     comma
                move.w  10(a2),d0
                bsr     pdec
                bsr     comma
                move.w  12(a2),d0
                bsr     pdec
                bsr     comma
                move.w  14(a2),d0
                bsr     pdec
                tst.w   d7
                beq.s   .nx
                bsr     sp1
                bsr     isalloc
                tst.b   d3
                beq.s   .ka
                moveq   #'+',d1
                bsr     putc
.ka:            lea     snapa-vars(a4),a0
                moveq   #0,d4
.s:             cmp.w   snapn-vars(a4),d4
                bhs.s   .nx
                addq.w  #1,d4
                cmp.l   (a0)+,a2
                bne.s   .s
                tst.b   d3
                bne.s   .k
                moveq   #'=',d1
                bsr     putc
.k:             move.w  d4,d0
                bsr     pdec
.nx:            bsr     nl
                move.l  (a2),a2
                subq.w  #1,d5
                bra.s   .nd
.e:             rts

; --- isalloc(a2 node): d3.b = $FF if an AllocMem of the last call returned a2
isalloc:        lea     logv(pc),a0
                moveq   #0,d4
.l:             cmp.w   LV_N(a0),d4
                bhs.s   .no
                cmp.w   #'A',LV_BUF(a0,d4.w)
                bne.s   .n
                cmp.l   LV_BUF+8(a0,d4.w),a2
                beq.s   .y
.n:             add.w   #12,d4
                bra.s   .l
.y:             st      d3
                rts
.no:            sf      d3
                rts

; --- plog: "  log: A16/00010000 F16 ..." of the last call
plog:           lea     m_log(pc),a0
                bsr     puts
                lea     logv(pc),a2
                moveq   #0,d4
.l:             cmp.w   LV_N(a2),d4
                bhs.s   .e
                lea     LV_BUF(a2,d4.w),a3
                bsr     sp1
                move.w  (a3),d1
                bsr     putc
                move.w  2(a3),d0
                bsr     pdec
                cmp.w   #'F',(a3)
                beq.s   .n
                moveq   #'/',d1
                bsr     putc
                move.l  4(a3),d0
                bsr     phex8
.n:             add.w   #12,d4
                bra.s   .l
.e:             cmp.w   #LOGMAX*12,LV_N(a2)
                blo.s   .x
                lea     m_full(pc),a0
                bsr     puts
.x:             bra     nl

; --- AllocMem wrapper (D0 size, D1 flags; A6 ExecBase): logs the call and the address returned
allocw:         lea     logv(pc),a0
                move.l  EB_THISTASK(a6),a1
                cmp.l   LV_TASK(a0),a1
                bne.s   .p
                tst.b   LV_ON(a0)
                beq.s   .p
                move.w  #'A',LV_TYPE(a0)
                tst.w   LV_CNT(a0)
                beq.s   .lg
                subq.w  #1,LV_CNT(a0)
                bne.s   .lg
                move.w  #'X',LV_TYPE(a0)
.lg:            move.w  LV_N(a0),a1
                cmp.w   #LOGMAX*12,a1
                bhs.s   .nl
                add.w   #12,LV_N(a0)
                move.w  LV_TYPE(a0),LV_BUF(a0,a1.w)
                move.w  d0,LV_BUF+2(a0,a1.w)
                move.l  d1,LV_BUF+4(a0,a1.w)
                clr.l   LV_BUF+8(a0,a1.w)
                cmp.w   #'X',LV_TYPE(a0)
                beq.s   .z
                move.l  a1,-(sp)
                move.l  LV_OLDA(a0),a0
                jsr     (a0)
                move.l  (sp)+,a1
                lea     logv(pc),a0
                move.l  d0,LV_BUF+8(a0,a1.w)
                rts
.nl:            cmp.w   #'X',LV_TYPE(a0)
                bne.s   .p
.z:             moveq   #0,d0
                rts
.p:             move.l  LV_OLDA(a0),a0
                jmp     (a0)

; --- FreeMem wrapper (A1 block, D0 size; A6 ExecBase)
freew:          lea     logv(pc),a0
                move.l  EB_THISTASK(a6),d1
                cmp.l   LV_TASK(a0),d1
                bne.s   .p
                tst.b   LV_ON(a0)
                beq.s   .p
                move.w  LV_N(a0),d1
                cmp.w   #LOGMAX*12,d1
                bhs.s   .p
                add.w   #12,LV_N(a0)
                move.w  #'F',LV_BUF(a0,d1.w)
                move.w  d0,LV_BUF+2(a0,d1.w)
                clr.l   LV_BUF+4(a0,d1.w)
                move.l  a1,LV_BUF+8(a0,d1.w)
.p:             move.l  LV_OLDF(a0),a0
                jmp     (a0)

; --- printing helpers
comma:          moveq   #',',d1
                bra.s   putc
nl:             moveq   #10,d1
                bra.s   putc
sp1:            moveq   #' ',d1
                bra.s   putc
; pdec: d0.w signed, in decimal
pdec:           ext.l   d0
                bpl.s   pdecu
                neg.l   d0
                moveq   #'-',d1
                bsr.s   putc
; pdecu: d0.l unsigned (< 655360), in decimal
pdecu:          divu    #10,d0
                move.l  d0,-(sp)
                and.l   #$FFFF,d0
                beq.s   .d
                bsr.s   pdecu
.d:             move.l  (sp)+,d0
                swap    d0
                add.b   #'0',d0
                move.b  d0,d1
putc:           move.w  d0,-(sp)
.w:             move.w  SERDATR,d0
                btst    #13,d0
                beq.s   .w
                and.w   #$FF,d1
                or.w    #$100,d1
                move.w  d1,SERDAT
                move.w  (sp)+,d0
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
                bsr.s   putc
                move.w  (sp)+,d0
                rts
hexd:           dc.b    "0123456789ABCDEF"
puts:           move.b  (a0)+,d1
                beq.s   .e
                bsr.s   putc
                bra.s   puts
.e:             rts

rnames:         dc.b    "D0D1D2D3D4D5D6D7A0A1A2A3A4A5A6"
gfxname:        dc.b    "graphics.library",0
m_start:        dc.b    10,"GRG debut",10,0
m_end:          dc.b    "GRG fin",10,0
m_d0:           dc.b    " D0=",0
m_c:            dc.b    " C=",0
m_p:            dc.b    " P=",0
m_q:            dc.b    " Q=",0
m_b:            dc.b    " B=",0
m_n:            dc.b    " N=",0
m_lok:          dc.b    " L=ok",0
m_lbad:         dc.b    " L=bad",0
m_none:         dc.b    " B=none",0
m_ind:          dc.b    "  ",0
m_r1:           dc.b    "  R1",0
m_log:          dc.b    "  log:",0
m_full:         dc.b    " (log full)",0
                even

vars:
rgs:            dc.l    0,0,0,0
gfxb:           dc.l    0
tgt:            dc.l    0
arga0:          dc.l    0
arga1:          dc.l    0
curid:          dc.l    0
lvo:            dc.w    0
dslot:          dc.w    0
dslot2:         dc.w    0
newslot:        dc.w    0
snapn:          dc.w    0
wantcnt:        dc.w    0
wantlog:        dc.b    0
                even
rect:           ds.w    4
regsin:         ds.l    14
regsout:        ds.l    15
snapa:          ds.l    NSNAP
logv:           ds.b    LV_BUF+LOGMAX*12
