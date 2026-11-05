; tests/exec_memsem_probe.s - HUNK test executable (TEST ASSET, NOT ROM code).
; Black-box probe "exec memory and signal semaphores" (docs/analysis/exec-memory-semaphores-v34.md §9, §10). Run
; from the startup-sequence of a floppy (tests/exec_memsem_probe.sh). Results go to a memory buffer whose bounds are
; printed on the direct serial port (SERDAT) before "MSP fin"; the harness reads it through gdb (the emulated serial
; link loses characters) and tests/exec_memsem_check.py compares it with the expected values. The probe then waits
; for ever so that the buffer stays valid.
; One line per vector: "<id> key=value ...", values in hexadecimal without leading zeros. Addresses are printed
; relative to the probe's own regions: R (private MemHeader, not linked), F and C (private MemHeaders linked at the
; head of the MemList with attributes $0805 and $0803, so that the results do not depend on the system lists), K
; (AddMemList block); "-" is 0 and "S" any other address. x= lists the registers among d0-d7/a0-a5 that differ
; after the call from the markers loaded before it (a6 = ExecBase).
; Dead-end alert vectors (G1 G3 G4 G5 G6 V1 V4 V5 S9 H4) run only when the first character of the command line
; selects one: the probe clears $100.l, prints "MSP alert <c>" on the serial port and makes the faulty call; the
; harness then reads the alert number from $100.l (where this ROM's dead-end alert leaves it).
; Assembly: vasmm68k_mot -Fhunkexe -kick1hunks -nosym -m68000 tests/exec_memsem_probe.s
; Authored code; public interfaces only (exec AutoDocs, exec_lib.fd, exec/*.i structure offsets).

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018
SERPER   EQU $DFF032

LVO_Alert           EQU -108     ; exec LVOs checked against docs/exec-lvo-table.md (exec_lib.fd)
LVO_Forbid          EQU -132
LVO_Permit          EQU -138
LVO_Allocate        EQU -186
LVO_Deallocate      EQU -192
LVO_AllocMem        EQU -198
LVO_AllocAbs        EQU -204
LVO_FreeMem         EQU -210
LVO_AvailMem        EQU -216
LVO_AllocEntry      EQU -222
LVO_FreeEntry       EQU -228
LVO_AddTail         EQU -246
LVO_Remove          EQU -252
LVO_Enqueue         EQU -270
LVO_AddTask         EQU -282
LVO_FindTask        EQU -294
LVO_SetTaskPri      EQU -300
LVO_SetSignal       EQU -306
LVO_Wait            EQU -318
LVO_Signal          EQU -324
LVO_AllocSignal     EQU -330
LVO_SetFunction     EQU -420
LVO_TypeOfMem       EQU -534
LVO_Procure         EQU -540
LVO_Vacate          EQU -546
LVO_InitSemaphore   EQU -558
LVO_ObtainSemaphore EQU -564
LVO_ReleaseSemaphore EQU -570
LVO_AttemptSemaphore EQU -576
LVO_ObtainSemaphoreList EQU -582
LVO_ReleaseSemaphoreList EQU -588
LVO_FindSemaphore   EQU -594
LVO_AddSemaphore    EQU -600
LVO_RemSemaphore    EQU -606
LVO_AddMemList      EQU -618
LVO_CopyMem         EQU -624
LVO_CopyMemQuick    EQU -630

EB_MEMLIST  EQU 322              ; ExecBase->MemList (exec/execbase.i)
EB_SEMLIST  EQU 532              ; ExecBase->SemaphoreList
LN_TYPE     EQU 8
LN_PRI      EQU 9
LN_NAME     EQU 10
MH_ATTR     EQU 14
MH_FIRST    EQU 16
MH_LOWER    EQU 20
MH_UPPER    EQU 24
MH_FREE     EQU 28
ML_NUM      EQU 14
ML_ME       EQU 16
SS_NEST     EQU 14
SS_WQ       EQU 16
SS_ML       EQU 28
SS_OWNER    EQU 40
SS_QC       EQU 44
TC_SIGALLOC EQU 18
TC_SIGRECVD EQU 26
TC_SPREG    EQU 54
TC_SPLOWER  EQU 58
TC_SPUPPER  EQU 62
TC_MEMENTRY EQU 74
TC_USERDATA EQU 88
MP_FLAGS    EQU 14
MP_SIGTASK  EQU 16
MP_MSGLIST  EQU 20
MN_REPLY    EQU 14
MN_LENGTH   EQU 18

CMDSIG      EQU $00100000        ; command signal of the helper tasks (bit 20)
PRI_ME      EQU 20               ; probe priority; helper T = PRI_ME+2, U = PRI_ME+1, or PRI_LOW when it must run only
PRI_LOW     EQU 15               ; while the probe waits (still above tasks that are always ready, e.g. dev demo tasks)
OBUFSZ      EQU 32768
STKSZ       EQU 1536

W_RH     EQU 0                   ; private MemHeader of the A/D/V vectors (not in the MemList)
W_R      EQU 64                  ; its region R (1024 bytes + slack)
W_PFH    EQU 1152                ; PF header (attributes $0805, pri 100)
W_PFR    EQU 1184                ; PF region (1024)
W_PCH    EQU 2208                ; PC header (attributes $0803, pri 99)
W_PCR    EQU 2240                ; PC region (1024)
W_TPL    EQU 3264                ; AllocEntry template (64)
W_TCP    EQU 3328                ; its copy (64)
W_CPS    EQU 3392                ; copy source (1280)
W_CPD    EQU 4672                ; copy destination (1280)
W_SEM    EQU 5952                ; S, S2, S3 (48 each)
W_SL     EQU 6096                ; List of S, S2, S3
W_DL     EQU 6112                ; dummy List + node X (N7)
W_DX     EQU 6128
W_OS     EQU 6144                ; old Semaphore (36)
W_RP     EQU 6184                ; reply port (34)
W_M1     EQU 6224                ; messages (20 each)
W_M2     EQU 6248
W_T1     EQU 6272                ; helper tasks (92 each)
W_T2     EQU 6368
W_ST1    EQU 6464                ; their stacks
W_ST2    EQU 8000
WORKSZ   EQU 9600

OP_END   EQU 0                   ; helper task operations: word code, word argument, long pointer
OP_OBT   EQU 1                   ; ObtainSemaphore(sem[arg])
OP_REL   EQU 2                   ; ReleaseSemaphore(sem[arg])
OP_SNAP  EQU 3                   ; one output line: label (pointer), fields of sem[arg], probe's SIGF_SEMAPHORE
OP_SIGME EQU 4                   ; Signal(probe, $10)
OP_CMD   EQU 5                   ; Signal(task[arg], CMDSIG)

; PS "text": prints a literal string (inline, skipped over; local labels keep the enclosing scope).
PS              macro
                move.l  a0,-(sp)
                lea     .s\@(pc),a0
                bsr     puts
                move.l  (sp)+,a0
                bra     .e\@
.s\@:           dc.b    \1,0
                even
.e\@:
                endm
; SC "id",lvo: scallw with the line's id in a2 (printed after the call: helper tasks may print meanwhile)
SC              macro
                lea     .s\@(pc),a2
                move.w  #\2,d0
                bsr     scallw
                bra     .e\@
.s\@:           dc.b    \1,0
                even
.e\@:
                endm
; CALL lvo: one call through docall (registers from rin, results in rout).
CALL            macro
                move.w  #\1,d0
                bsr     docall
                endm

                section code,code
_start:
                movem.l d2-d7/a2-a6,-(sp)
                moveq   #0,d1
                tst.l   d0
                beq     .noarg
                move.b  (a0),d1
.noarg:         move.b  d1,argc
                move.w  #372,SERPER
                move.l  4.w,a6
                move.l  a6,ebase
                sub.l   a1,a1
                jsr     LVO_FindTask(a6)
                move.l  d0,me
                move.l  d0,a1                ; priority 20, above busy tasks of the system; the helper tasks (22, 21)
                moveq   #PRI_ME,d0           ; preempt the probe
                jsr     LVO_SetTaskPri(a6)
.unf:           tst.b   295(a6)              ; TDNestCnt: this ROM's dev shell runs commands under Forbid (the probe
                bmi.s   .unf0                ; never returns, so the level is not given back)
                jsr     LVO_Permit(a6)
                bra.s   .unf
.unf0:
                move.l  #OBUFSZ,d0
                move.l  #$10001,d1
                jsr     LVO_AllocMem(a6)
                move.l  d0,obuf
                move.l  d0,optr
                beq     .out
                move.l  #WORKSZ,d0
                move.l  #$10001,d1
                jsr     LVO_AllocMem(a6)
                move.l  d0,work
                beq     .out
                move.b  argc,d0
                cmp.b   #'0',d0
                blo     .normal
                bsr     alertmode
                bra     .hang
.normal:        PS      <10,"MSP debut",10>
                bsr     ptd
                bsr     t_ad
                bsr     ptd
                bsr     t_sys
                bsr     ptd
                bsr     t_type
                bsr     ptd
                bsr     t_addml
                bsr     ptd
                bsr     t_copy
                bsr     ptd
                bsr     t_sem
                bsr     ptd
                PS      <"MSP fin",10>
                moveq   #1,d3                ; "MSP buf=<start> end=<end>" twice, then "MSP fin", on the serial port
.sb:            lea     m_buf,a0
                bsr     sputs
                move.l  obuf,d0
                bsr     shex8
                lea     m_bend,a0
                bsr     sputs
                move.l  optr,d0
                bsr     shex8
                moveq   #10,d1
                bsr     sputc
                dbra    d3,.sb
                lea     m_fin,a0
                bsr     sputs
.hang:          move.l  ebase,a6             ; the buffer (and the helper tasks' code) must stay valid
                moveq   #0,d0
                jsr     LVO_Wait(a6)
.out:           movem.l (sp)+,d2-d7/a2-a6
                moveq   #0,d0
                rts

; ptd: line "Z<n> td=<ExecBase TDNestCnt> id=<IDNestCnt>" (FF FF expected between sections: no Forbid/Disable left)
ptd:            movem.l d0-d1/a0,-(sp)
                moveq   #'Z',d1
                bsr     putc
                move.b  zcount,d1
                add.b   #'0',d1
                bsr     putc
                addq.b  #1,zcount
                PS      " td="
                move.l  ebase,a0
                moveq   #0,d0
                move.b  295(a0),d0
                bsr     phex
                PS      " id="
                move.b  294(a0),d0
                bsr     phex
                bsr     nl
                movem.l (sp)+,d0-d1/a0
                rts

; ---------------------------------------------------------------------------------------------------------------
; docall(d0.w = LVO): d0-d7/a0-a5 loaded from rin, a6 = ExecBase, the function called through its vector; all
; registers stored into rout afterwards. The caller's d2-d7/a2-a5 are restored; d0/d1/a0/a1/a6 are the callee's.
docall:         ext.l   d0
                movem.l d2-d7/a2-a5,-(sp)
                move.l  ebase,a6
                add.l   a6,d0
                pea     .back(pc)
                move.l  d0,-(sp)
                movem.l rin,d0-d7/a0-a5
                rts
.back:          movem.l d0-d7/a0-a5,rout
                movem.l (sp)+,d2-d7/a2-a5
                rts
; mark: rin = $11110000 + register number. Preserves everything.
mark:           movem.l d0/a0,-(sp)
                lea     rin,a0
                move.l  #$11110000,d0
.l:             move.l  d0,(a0)+
                addq.w  #1,d0
                cmp.w   #14,d0
                bne     .l
                movem.l (sp)+,d0/a0
                rts
; pxreg: " x=" names of the registers changed by the last docall ("-" if none). Preserves everything.
pxreg:          movem.l d0-d2/a0-a2,-(sp)
                PS      " x="
                lea     rin,a0
                lea     rout,a1
                lea     regnames,a2
                moveq   #13,d0
                moveq   #0,d2
.l:             move.l  (a0)+,d1
                cmp.l   (a1)+,d1
                beq     .n
                move.b  (a2),d1
                bsr     putc
                move.b  1(a2),d1
                bsr     putc
                moveq   #1,d2
.n:             addq.l  #2,a2
                dbra    d0,.l
                tst.w   d2
                bne     .r
                moveq   #'-',d1
                bsr     putc
.r:             movem.l (sp)+,d0-d2/a0-a2
                rts

; ---------------------------------------------------------------------------------------------------------------
; output into the buffer (no allocation, no RawDoFmt)
putc:           move.l  a0,-(sp)
                move.l  optr,a0
                move.b  d1,(a0)+
                move.l  a0,optr
                move.l  (sp)+,a0
                rts
puts:           movem.l d1/a0,-(sp)
.l:             move.b  (a0)+,d1
                beq     .e
                bsr     putc
                bra     .l
.e:             movem.l (sp)+,d1/a0
                rts
nl:             move.l  d1,-(sp)
                moveq   #10,d1
                bsr     putc
                move.l  (sp)+,d1
                rts
comma:          move.l  d1,-(sp)
                moveq   #',',d1
                bsr     putc
                move.l  (sp)+,d1
                rts
; phex(d0): hexadecimal without leading zeros. Preserves everything.
phex:           movem.l d0-d3,-(sp)
                moveq   #7,d2
                moveq   #0,d3                ; a digit already printed
.l:             rol.l   #4,d0
                moveq   #15,d1
                and.w   d0,d1
                bne     .p
                tst.w   d3
                bne     .p
                tst.w   d2
                bne     .n
.p:             move.b  hexd(pc,d1.w),d1
                bsr     putc
                moveq   #1,d3
.n:             dbra    d2,.l
                movem.l (sp)+,d0-d3
                rts
hexd:           dc.b    "0123456789ABCDEF"
; phex8(d0): 8 digits. Preserves everything.
phex8:          movem.l d0-d2,-(sp)
                moveq   #7,d2
.l:             rol.l   #4,d0
                moveq   #15,d1
                and.w   d0,d1
                move.b  hexd(pc,d1.w),d1
                bsr     putc
                dbra    d2,.l
                movem.l (sp)+,d0-d2
                rts
; psig(d0.b): signed byte as "-n" or "n" (hex). Preserves everything.
psig:           movem.l d0-d1,-(sp)
                ext.w   d0
                ext.l   d0
                bpl     .p
                moveq   #'-',d1
                bsr     putc
                neg.l   d0
.p:             bsr     phex
                movem.l (sp)+,d0-d1
                rts
; prel(d0): "-" (0), region letter + offset (inside a region, end included), "S" otherwise. Preserves everything.
prel:           movem.l d0-d2/a0,-(sp)
                tst.l   d0
                bne     .t
                moveq   #'-',d1
                bsr     putc
                bra     .r
.t:             lea     rtab,a0
.l:             move.l  (a0)+,d1             ; base
                beq     .s
                move.l  (a0)+,d2             ; size
                cmp.l   d1,d0
                blo     .nx
                sub.l   d1,d0
                cmp.l   d2,d0
                bls     .in
                add.l   d1,d0
.nx:            addq.l  #2,a0
                bra     .l
.in:            move.l  d0,d2
                move.w  (a0),d1
                bsr     putc
                move.l  d2,d0
                bsr     phex
                bra     .r
.s:             moveq   #'S',d1
                bsr     putc
.r:             movem.l (sp)+,d0-d2/a0
                rts
; setreg(a0 = rtab slot, d0 = base, d1 = size, d2 = letter)
setreg:         move.l  d0,(a0)+
                move.l  d1,(a0)+
                move.w  d2,(a0)
                rts
; pch(a0 = MemHeader): " c=" chunk list (address via prel : size) and " f=" mh_Free. Preserves everything.
pch:            movem.l d0-d2/a0-a1,-(sp)
                PS      " c="
                move.l  MH_FIRST(a0),a1
                moveq   #0,d2
                move.l  a1,d0
                bne     .l
                moveq   #'-',d1
                bsr     putc
.l:             move.l  a1,d0
                beq     .e
                cmp.w   #12,d2
                beq     .e                   ; looping list: stop
                tst.w   d2
                beq     .f
                bsr     comma
.f:             bsr     prel
                moveq   #':',d1
                bsr     putc
                move.l  4(a1),d0
                bsr     phex
                addq.w  #1,d2
                move.l  (a1),a1
                bra     .l
.e:             PS      " f="
                move.l  MH_FREE(a0),d0
                bsr     phex
                movem.l (sp)+,d0-d2/a0-a1
                rts
; pid(a0 = 4-byte id field, NUL-padded unless 4 characters long). Preserves everything.
pid:            movem.l d0-d1/a0,-(sp)
                moveq   #3,d0
.l:             move.b  (a0)+,d1
                beq     .e
                bsr     putc
                dbra    d0,.l
.e:             movem.l (sp)+,d0-d1/a0
                rts

; ---------------------------------------------------------------------------------------------------------------
; mkhdr(a0 = header, a1 = region, d0 = size, d1.w = attributes, d2.b = pri): MemHeader with one chunk.
mkhdr:          move.b  #10,LN_TYPE(a0)
                move.b  d2,LN_PRI(a0)
                move.l  #n_priv,LN_NAME(a0)
                move.w  d1,MH_ATTR(a0)
                move.l  a1,MH_FIRST(a0)
                move.l  a1,MH_LOWER(a0)
                move.l  a1,MH_UPPER(a0)
                add.l   d0,MH_UPPER(a0)
                move.l  d0,MH_FREE(a0)
                clr.l   (a1)
                move.l  d0,4(a1)
                rts

; ---------------------------------------------------------------------------------------------------------------
; A / D vectors: Allocate / Deallocate on the private header (R region). Table: id (4 bytes), op.w (0 Allocate,
; 1 Deallocate), offset.l, size.l, n.w (-1 = keep the state of the previous vector), n x (offset.w, size.w).
t_ad:           move.l  work,a5
                lea     rtab,a0
                lea     W_R(a5),a1
                move.l  a1,d0
                move.l  #1024,d1
                moveq   #'R',d2
                bsr     setreg
                lea     adtab,a4
.v:             tst.l   (a4)
                beq     .done
                move.l  a4,a0
                bsr     pid
                addq.l  #4,a4
                move.w  (a4)+,d6             ; op
                move.l  (a4)+,d4             ; offset
                move.l  (a4)+,d5             ; size
                move.w  (a4)+,d3             ; chunks
                bmi     .keep
                lea     W_RH(a5),a0          ; fresh header: Lower R, Upper R+1024, chunks from the table
                lea     W_R(a5),a1
                clr.l   MH_FIRST(a0)
                clr.l   MH_FREE(a0)
                move.l  a1,MH_LOWER(a0)
                move.l  a1,MH_UPPER(a0)
                add.l   #1024,MH_UPPER(a0)
                lea     MH_FIRST(a0),a2      ; a2 = link to fill
                bra     .ce
.c:             moveq   #0,d0
                move.w  (a4)+,d0
                lea     0(a1,d0.l),a3
                move.l  a3,(a2)
                moveq   #0,d0
                move.w  (a4)+,d0
                move.l  d0,4(a3)
                add.l   d0,MH_FREE(a0)
                move.l  a3,a2
.ce:            dbra    d3,.c
                clr.l   (a2)
.keep:          bsr     mark
                lea     W_RH(a5),a0
                move.l  a0,rin+32            ; a0 = header
                move.l  d5,rin               ; d0 = size
                tst.w   d6
                bne     .dea
                CALL    LVO_Allocate
                PS      " r="
                move.l  rout,d0
                bsr     prel
                bra     .pr
.dea:           lea     W_R(a5),a1
                add.l   d4,a1
                move.l  a1,rin+36
                CALL    LVO_Deallocate
.pr:            move.l  work,a5
                lea     W_RH(a5),a0
                bsr     pch
                bsr     pxreg
                bsr     nl
                bra     .v
.done:          rts

; ---------------------------------------------------------------------------------------------------------------
; System-list vectors M F C G T L E H, under Forbid, with PF and PC linked at the head of the MemList.
t_sys:          move.l  ebase,a6
                jsr     LVO_Forbid(a6)
                bsr     pfpc_add
                bsr     t_m
                bsr     t_f
                bsr     t_c
                bsr     t_g
                bsr     t_t
                bsr     t_l
                bsr     t_e
                bsr     pfpc_rem
                move.l  ebase,a6
                jmp     LVO_Permit(a6)

pfpc_add:       move.l  work,a5
                lea     rtab+10,a0
                lea     W_PFR(a5),a1
                move.l  a1,d0
                move.l  #1024,d1
                moveq   #'F',d2
                bsr     setreg
                lea     rtab+20,a0
                lea     W_PCR(a5),a1
                move.l  a1,d0
                moveq   #'C',d2
                bsr     setreg
                bsr     pfpc_init
                move.l  ebase,a6
                lea     EB_MEMLIST(a6),a0
                lea     W_PFH(a5),a1
                jsr     LVO_Enqueue(a6)
                lea     EB_MEMLIST(a6),a0
                lea     W_PCH(a5),a1
                jmp     LVO_Enqueue(a6)
; pfpc_init: PF and PC header fields and single chunks (links untouched)
pfpc_init:      move.l  work,a5
                lea     W_PFH(a5),a0
                lea     W_PFR(a5),a1
                move.l  #1024,d0
                move.w  #$0805,d1
                moveq   #100,d2
                bsr     mkhdr
                lea     W_PCH(a5),a0
                lea     W_PCR(a5),a1
                move.w  #$0803,d1
                moveq   #99,d2
                bra     mkhdr
pfpc_rem:       move.l  work,a5
                move.l  ebase,a6
                lea     W_PFH(a5),a1
                jsr     LVO_Remove(a6)
                lea     W_PCH(a5),a1
                jmp     LVO_Remove(a6)
pffree:         move.l  work,a0              ; d0 = mh_Free of PF + PC (d1 = of PF)
                move.l  W_PFH+MH_FREE(a0),d1
                move.l  W_PCH+MH_FREE(a0),d0
                add.l   d1,d0
                rts
; am(d0 = size, d1 = requirements) -> d0 = block (AllocMem through docall)
am:             bsr     mark
                move.l  d0,rin
                move.l  d1,rin+4
                CALL    LVO_AllocMem
                move.l  rout,d0
                rts
; fm(a1 = block, d0 = size): FreeMem, direct
fm:             move.l  ebase,a6
                jmp     LVO_FreeMem(a6)

; M1-M14: sizes, rounding, wrap-around; " r= d=<PF free taken> rs=<free restored by FreeMem>"
t_m:            lea     mtab,a4
.v:             tst.l   (a4)
                beq     .done
                move.l  a4,a0
                bsr     pid
                bsr     pffree
                move.l  d1,d7
                move.l  4(a4),d0
                move.l  8(a4),d1
                bsr     am
                move.l  d0,d6
                PS      " r="
                bsr     prel
                PS      " d="
                bsr     pffree
                move.l  d7,d0
                sub.l   d1,d0
                bsr     phex
                bsr     pxreg
                tst.l   d6
                beq     .nf
                move.l  d6,a1
                move.l  4(a4),d0
                bsr     fm
.nf:            PS      " rs="
                bsr     pffree
                moveq   #'1',d0
                cmp.l   d1,d7
                beq     .ok
                moveq   #'0',d0
.ok:            move.b  d0,d1
                bsr     putc
                bsr     nl
                lea     12(a4),a4
                bra     .v
.done:          rts

; F1-F19: header choice, AllocMem(16, req)
t_f:            lea     ftab,a4
.v:             tst.l   (a4)
                beq     .done
                move.l  a4,a0
                bsr     pid
                moveq   #16,d0
                move.l  4(a4),d1
                bsr     am
                PS      " r="
                bsr     prel
                tst.l   d0
                beq     .nf
                move.l  d0,a1
                moveq   #16,d0
                bsr     fm
.nf:            bsr     nl
                addq.l  #8,a4
                bra     .v
.done:          rts

; C1-C3: block contents with and without MEMF_CLEAR (PF chunk body pre-filled with $A5)
t_c:            PS      "MC1"
                bsr     fillpf
                moveq   #32,d0
                moveq   #0,d1
                moveq   #3,d2
                bsr     cblk
                PS      "MC2"
                bsr     fillpf
                moveq   #13,d0
                move.l  #$10000,d1
                moveq   #6,d2
                bsr     cblk
                PS      "MC3"
                bsr     fillpf
                moveq   #8,d0
                move.l  #$10000,d1
                moveq   #4,d2
                bsr     cblk
                rts
fillpf:         move.l  work,a0
                lea     W_PFR+8(a0),a0
                moveq   #55,d0
.l:             move.b  #$A5,(a0)+
                dbra    d0,.l
                rts
; cblk(d0 size, d1 req, d2 = longs to print): " r= h=<longs>", then FreeMem
cblk:           move.l  d0,d7
                move.l  d2,d5
                bsr     am
                move.l  d0,d6
                PS      " r="
                bsr     prel
                PS      " h="
                tst.l   d6
                beq     .e
                move.l  d6,a2
                subq.w  #1,d5
.l:             move.l  (a2)+,d0
                bsr     phex8
                tst.w   d5
                beq     .n
                bsr     comma
.n:             dbra    d5,.l
                move.l  d6,a1
                move.l  d7,d0
                bsr     fm
.e:             bra     nl

; G2, G7: FreeMem with size 0
t_g:            PS      "G2"
                bsr     pffree
                move.l  d0,d7
                bsr     mark
                clr.l   rin
                clr.l   rin+36
                CALL    LVO_FreeMem
                PS      " d="
                bsr     pffree
                sub.l   d7,d0
                bsr     phex
                bsr     pxreg
                bsr     nl
                PS      "G7"
                bsr     pffree
                move.l  d0,d7
                moveq   #16,d0
                moveq   #0,d1
                bsr     am
                move.l  d0,d6
                bsr     mark
                clr.l   rin
                move.l  d6,rin+36
                CALL    LVO_FreeMem
                PS      " d="
                bsr     pffree
                move.l  d7,d1
                sub.l   d0,d1
                move.l  d1,d0
                bsr     phex
                bsr     pxreg
                move.l  d6,a1
                moveq   #16,d0
                bsr     fm
                bra     nl

; T: AvailMem. Tp* on the private headers only (literal), T1-T17 on everything (value and the spec's model).
t_t:            lea     ttab,a4
.v:             tst.l   (a4)
                beq     .done
                move.l  a4,a0
                bsr     pid
                move.l  4(a4),d1
                bsr     availref
                move.l  d0,d7
                bsr     mark
                move.l  4(a4),rin+4
                CALL    LVO_AvailMem
                PS      " v="
                move.l  rout,d0
                bsr     phex
                PS      " ref="
                move.l  d7,d0
                bsr     phex
                bsr     pxreg
                bsr     nl
                addq.l  #8,a4
                bra     .v
.done:          rts
; availref(d1 = requirements) -> d0: the spec's model (§2.6): headers whose attributes hold every low-word bit;
; sum of mh_Free, or the largest chunk with MEMF_LARGEST.
availref:       movem.l d2-d3/a0-a1,-(sp)
                moveq   #0,d0
                move.l  ebase,a0
                move.l  EB_MEMLIST(a0),a0
.h:             tst.l   (a0)
                beq     .e
                move.w  MH_ATTR(a0),d2
                and.w   d1,d2
                cmp.w   d1,d2
                bne     .nh
                btst    #17,d1
                bne     .lg
                add.l   MH_FREE(a0),d0
                bra     .nh
.lg:            move.l  MH_FIRST(a0),a1
.c:             move.l  a1,d3
                beq     .nh
                move.l  4(a1),d3
                cmp.l   d0,d3
                bls     .cn
                move.l  d3,d0
.cn:            move.l  (a1),a1
                bra     .c
.nh:            move.l  (a0),a0
                bra     .h
.e:             movem.l (sp)+,d2-d3/a0-a1
                rts

; L: AllocAbs on PF (single chunk F:400 at the start)
t_l:            lea     ltab,a4
.v:             tst.l   (a4)
                beq     .done
                move.l  a4,a0
                bsr     pid
                move.w  4(a4),d0             ; kind: 0 AllocAbs, 1 FreeMem (offset, size)
                move.l  6(a4),d2             ; offset (from F, or absolute when bit 0 of the kind byte 2 set)
                move.l  10(a4),d3            ; size
                move.l  work,a5
                lea     W_PFR(a5),a1
                btst    #1,d0
                beq     .rel
                lea     W_PCR(a5),a1
.rel:           btst    #2,d0
                beq     .rel2
                sub.l   a1,a1
.rel2:          add.l   d2,a1
                btst    #0,d0
                bne     .free
                bsr     mark
                move.l  d3,rin
                move.l  a1,rin+36
                CALL    LVO_AllocAbs
                PS      " r="
                move.l  rout,d0
                bsr     prel
                bra     .p
.free:          move.l  d3,d0
                bsr     fm
.p:             move.l  work,a5
                lea     W_PFH(a5),a0
                bsr     pch
                move.w  4(a4),d0
                btst    #0,d0
                bne     .np
                bsr     pxreg
.np:            bsr     nl
                lea     14(a4),a4
                bra     .v
.done:          rts

; E / H: AllocEntry / FreeEntry with AllocMem and FreeMem patched by logging stubs
t_e:            move.l  ebase,a6
                move.l  a6,a1
                move.w  #LVO_AllocMem,a0
                move.l  #st_am,d0
                jsr     LVO_SetFunction(a6)
                move.l  d0,oldam
                move.l  a6,a1
                move.w  #LVO_FreeMem,a0
                move.l  #st_fm,d0
                jsr     LVO_SetFunction(a6)
                move.l  d0,oldfm
                lea     etab,a4
.v:             tst.l   (a4)
                beq     .done
                move.l  a4,a0
                bsr     pid
                move.w  4(a4),d7             ; kind: 0 AllocEntry (+FreeEntry if it worked), 1 E7, 2 H3
                move.l  work,a5
                lea     W_TPL(a5),a0         ; template: node bytes $CD, count, entries from the table
                moveq   #13,d0
.nd:            move.b  #$CD,(a0)+
                dbra    d0,.nd
                move.w  6(a4),(a0)+          ; ml_NumEntries
                move.w  8(a4),d0             ; entries in the table
                lea     10(a4),a1
                bra     .ee
.e:             move.l  (a1)+,(a0)+
                move.l  (a1)+,(a0)+
.ee:            dbra    d0,.e
                move.w  8(a4),d0
                lsl.w   #3,d0
                lea     10(a4,d0.w),a3       ; a3 = next table entry
                lea     W_TPL(a5),a0         ; copy for E3
                lea     W_TCP(a5),a1
                moveq   #15,d0
.cp:            move.l  (a0)+,(a1)+
                dbra    d0,.cp
                cmp.w   #1,d7
                bne     .ne7
                bsr     eat
.ne7:           cmp.w   #2,d7
                beq     .h3
                bsr     pffree
                move.l  d0,d6                ; PF+PC free before
                clr.l   logn
                st      logon
                bsr     mark
                lea     W_TPL(a5),a0
                move.l  a0,rin+32
                CALL    LVO_AllocEntry
                sf      logon
                move.l  rout,d5
                PS      " r="
                move.l  d5,d0
                bmi     .rneg
                bsr     prel
                bra     .rok
.rneg:          moveq   #'!',d1
                bsr     putc
                bsr     phex8
.rok:           tst.l   d5
                bmi     .fail
                move.l  d5,a2
                PS      " n="
                moveq   #0,d0
                move.w  ML_NUM(a2),d0
                bsr     phex
                PS      " nd="                ; node bytes of the new list all zero
                moveq   #'1',d1
                moveq   #13,d0
                move.l  a2,a0
.z:             tst.b   (a0)+
                beq     .zn
                moveq   #'0',d1
.zn:            dbra    d0,.z
                bsr     putc
                PS      " e="
                move.w  ML_NUM(a2),d2
                lea     ML_ME(a2),a0
                moveq   #0,d4                ; entries printed
                bra     .pe
.pl:            tst.w   d4
                beq     .pf
                bsr     comma
.pf:            move.l  (a0)+,d0
                bsr     prel
                moveq   #':',d1
                bsr     putc
                move.l  (a0)+,d0
                bsr     phex
                addq.w  #1,d4
.pe:            dbra    d2,.pl
                bsr     zchk
                PS      " l="
                bsr     plog
                bsr     pxreg
                PS      " same="
                bsr     tplsame
                bsr     nl
                move.l  a4,a0                ; "<id>h": FreeEntry of the new list
                bsr     pid
                moveq   #'h',d1
                bsr     putc
                clr.l   logn
                st      logon
                bsr     mark
                move.l  d5,rin+32
                CALL    LVO_FreeEntry
                sf      logon
                PS      " l="
                bsr     plog
                bsr     pxreg
                PS      " rs="
                bsr     pffree
                moveq   #'1',d1
                cmp.l   d0,d6
                beq     .rs
                moveq   #'0',d1
.rs:            bsr     putc
                bra     .end
.fail:          PS      " l="
                bsr     plog
                PS      " same="
                bsr     tplsame
                PS      " lk="                ; PF+PC bytes no longer free (the list leaked)
                bsr     pffree
                move.l  d6,d1
                sub.l   d0,d1
                move.l  d1,d0
                bsr     phex
                bsr     pfpc_init            ; leaked blocks given back by resetting the private headers
.end:           cmp.w   #1,d7
                bne     .nu
                bsr     uneat
.nu:            bsr     nl
                move.l  a3,a4
                bra     .v
.h3:            moveq   #32,d0               ; H3: n=1 list {addr, length 0} in a 32-byte block, FreeEntry
                moveq   #0,d1
                bsr     am
                move.l  d0,d5
                move.l  d0,a0
                move.w  #1,ML_NUM(a0)
                lea     W_PFR+$200(a5),a1
                move.l  a1,ML_ME(a0)
                clr.l   ML_ME+4(a0)
                bsr     pffree
                add.l   #32,d0
                move.l  d0,d6
                clr.l   logn
                st      logon
                bsr     mark
                move.l  d5,rin+32
                CALL    LVO_FreeEntry
                sf      logon
                PS      " l="
                bsr     plog
                PS      " lk="
                bsr     pffree
                move.l  d6,d1
                sub.l   d0,d1
                move.l  d1,d0
                bsr     phex
                bsr     pfpc_init
                bsr     nl
                move.l  a3,a4
                bra     .v
.done:          move.l  ebase,a6
                move.l  a6,a1
                move.w  #LVO_AllocMem,a0
                move.l  oldam,d0
                jsr     LVO_SetFunction(a6)
                move.l  a6,a1
                move.w  #LVO_FreeMem,a0
                move.l  oldfm,d0
                jmp     LVO_SetFunction(a6)
; zchk: " z=" 1 when every entry of the new list (a2) whose template requirements hold MEMF_CLEAR is zeroed
zchk:           movem.l d0-d2/a0-a1,-(sp)
                PS      " z="
                move.l  work,a1
                lea     W_TPL+ML_ME(a1),a1
                lea     ML_ME(a2),a0
                move.w  ML_NUM(a2),d2
                moveq   #'1',d1
                bra     .ne
.e:             btst    #0,1(a1)
                beq     .nx
                movem.l a0/d2,-(sp)
                move.l  4(a0),d2
                move.l  (a0),a0
                bra     .ze
.zl:            tst.b   (a0)+
                beq     .ze
                moveq   #'0',d1
.ze:            subq.l  #1,d2
                bcc     .zl
                movem.l (sp)+,a0/d2
.nx:            addq.l  #8,a0
                addq.l  #8,a1
.ne:            dbra    d2,.e
                bsr     putc
                movem.l (sp)+,d0-d2/a0-a1
                rts
; tplsame: '1' when the template is byte-identical to its copy (E3)
tplsame:        movem.l d0-d1/a0-a1,-(sp)
                move.l  work,a0
                lea     W_TCP(a0),a1
                lea     W_TPL(a0),a0
                moveq   #'1',d1
                moveq   #63,d0
.l:             cmp.b   (a0)+,(a1)+
                beq     .n
                moveq   #'0',d1
.n:             dbra    d0,.l
                bsr     putc
                movem.l (sp)+,d0-d1/a0-a1
                rts
; eat / uneat (E7): allocate the largest chunks until none is >= $30000, free them afterwards
eat:            movem.l d2/a2,-(sp)
                lea     eatt,a2
                clr.l   (a2)
                moveq   #15,d2
.l:             move.l  ebase,a6
                move.l  #$20000,d1
                jsr     LVO_AvailMem(a6)
                cmp.l   #$30000,d0
                blo     .e
                move.l  d0,4(a2)
                moveq   #0,d1
                jsr     LVO_AllocMem(a6)
                move.l  d0,(a2)
                beq     .e
                addq.l  #8,a2
                clr.l   (a2)
                dbra    d2,.l
.e:             movem.l (sp)+,d2/a2
                rts
uneat:          move.l  a2,-(sp)
                lea     eatt,a2
.l:             move.l  (a2)+,d0
                beq     .e
                move.l  d0,a1
                move.l  (a2)+,d0
                bsr     fm
                bra     .l
.e:             move.l  (sp)+,a2
                rts
; logging stubs: AllocMem (every call) and FreeMem (blocks inside F or C), while logon is set
st_am:          tst.b   logon
                beq     .go
                movem.l d2/a0,-(sp)
                moveq   #'a',d2
                bsr     logit
                movem.l (sp)+,d2/a0
.go:            move.l  oldam,-(sp)
                rts
st_fm:          tst.b   logon
                beq     .go
                movem.l d1-d2/a0,-(sp)
                move.l  work,a0
                lea     W_PFR(a0),a0
                cmp.l   a0,a1
                blo     .no
                lea     2048+32(a0),a0
                cmp.l   a0,a1
                bhs     .no
                moveq   #'f',d2
                move.l  d0,d1
                move.l  a1,d0
                bsr     logit
                move.l  d1,d0
.no:            movem.l (sp)+,d1-d2/a0
.go:            move.l  oldfm,-(sp)
                rts
; logit(d2 = kind, d0, d1): appends an entry. Preserves everything but a0.
logit:          move.l  logn,a0
                cmp.w   #16,a0
                beq     .r
                addq.l  #1,logn
                add.l   a0,a0
                add.l   a0,a0
                move.l  a0,-(sp)
                add.l   a0,a0
                add.l   (sp)+,a0             ; 12 bytes per entry
                add.l   #logbuf,a0
                move.l  d2,(a0)+
                move.l  d0,(a0)+
                move.l  d1,(a0)
.r:             rts
; plog: entries "a<size>/<req>" and "f<block>/<size>", comma-separated ("-" if none)
plog:           movem.l d0-d2/a0,-(sp)
                lea     logbuf,a0
                move.l  logn,d2
                bne     .s
                moveq   #'-',d1
                bsr     putc
                bra     .e
.s:             subq.w  #1,d2
.l:             move.l  (a0)+,d1
                bsr     putc
                cmp.b   #'a',d1
                bne     .f
                move.l  (a0)+,d0
                bsr     phex
                moveq   #'/',d1
                bsr     putc
                move.l  (a0)+,d0
                bsr     phex
                bra     .n
.f:             move.l  (a0)+,d0
                bsr     prel
                moveq   #'/',d1
                bsr     putc
                move.l  (a0)+,d0
                bsr     phex
.n:             tst.w   d2
                beq     .e
                bsr     comma
                dbra    d2,.l
.e:             movem.l (sp)+,d0-d2/a0
                rts

; ---------------------------------------------------------------------------------------------------------------
; Y: TypeOfMem. For each system header: a=<attributes>, v=<header, Lower-1, Lower, Upper-1, Upper>; then fixed
; addresses. Under Forbid.
t_type:         move.l  ebase,a6
                jsr     LVO_Forbid(a6)
                move.l  EB_MEMLIST(a6),a4
                moveq   #'0',d7
.h:             tst.l   (a4)
                beq     .f
                moveq   #'Y',d1
                bsr     putc
                move.b  d7,d1
                bsr     putc
                PS      " a="
                moveq   #0,d0
                move.w  MH_ATTR(a4),d0
                bsr     phex
                PS      " v="
                move.l  a4,d0
                bsr     ty
                bsr     comma
                move.l  MH_LOWER(a4),d0
                subq.l  #1,d0
                bsr     ty
                bsr     comma
                addq.l  #1,d0
                bsr     ty
                bsr     comma
                move.l  MH_UPPER(a4),d0
                subq.l  #1,d0
                bsr     ty
                bsr     comma
                addq.l  #1,d0
                bsr     ty
                bsr     pxreg
                bsr     nl
                addq.b  #1,d7
                move.l  (a4),a4
                bra     .h
.f:             PS      "Yf v="
                moveq   #0,d0
                bsr     ty
                bsr     comma
                move.l  #$FC0000,d0
                bsr     ty
                bsr     comma
                move.l  #$DFF000,d0
                bsr     ty
                bsr     comma
                move.l  #$BFE001,d0
                bsr     ty
                bsr     nl
                move.l  ebase,a6
                jmp     LVO_Permit(a6)
; ty(d0 = address): prints TypeOfMem(address). Preserves d0.
ty:             move.l  d0,-(sp)
                bsr     mark
                move.l  d0,rin+36
                CALL    LVO_TypeOfMem
                move.l  rout,d0
                bsr     phex
                move.l  (sp)+,d0
                rts

; ---------------------------------------------------------------------------------------------------------------
; K: AddMemList on a 4 KB chip block B (rtab K), attributes $41. Under Forbid; the header is removed after each.
t_addml:        move.l  ebase,a6
                jsr     LVO_Forbid(a6)
                move.l  #4096,d0
                move.l  #$10003,d1
                jsr     LVO_AllocMem(a6)
                move.l  d0,kblk
                beq     .out
                lea     rtab+30,a0
                move.l  #4096,d1
                moveq   #'K',d2
                bsr     setreg
                PS      "K1"
                move.l  #$1000,d0
                moveq   #5,d2
                moveq   #0,d3
                bsr     kadd
                PS      "K6 r="              ; AllocMem and TypeOfMem with K1's header linked
                moveq   #16,d0
                moveq   #$40,d1
                bsr     am
                bsr     prel
                move.l  d0,a1
                moveq   #16,d0
                bsr     kfm
                bsr     comma
                moveq   #16,d0
                moveq   #1,d1
                bsr     am
                bsr     prel
                move.l  d0,a1
                moveq   #16,d0
                bsr     kfm
                PS      " t="
                move.l  kblk,d0
                add.l   #31,d0
                bsr     ty
                bsr     comma
                addq.l  #1,d0
                bsr     ty
                bsr     comma
                add.l   #4095-32,d0
                bsr     ty
                bsr     comma
                addq.l  #1,d0
                bsr     ty
                bsr     nl
                bsr     krem
                PS      "K2"                 ; priority equal to the first system header's
                move.l  ebase,a0
                move.l  EB_MEMLIST(a0),a0
                move.b  LN_PRI(a0),d2
                ext.w   d2
                ext.l   d2
                move.l  #$1000,d0
                moveq   #0,d3
                bsr     kadd
                bsr     krem
                PS      "K3"
                move.l  #$1000,d0
                moveq   #-20,d2
                moveq   #0,d3
                bsr     kadd
                bsr     krem
                PS      "K4"
                move.l  #$FFC,d0
                moveq   #5,d2
                moveq   #4,d3
                bsr     kadd
                bsr     krem
                PS      "K5"
                move.l  #$FF9,d0
                moveq   #5,d2
                moveq   #8,d3
                bsr     kadd
                bsr     krem
                move.l  kblk,a1
                move.l  #4096,d0
                bsr     fm
.out:           move.l  ebase,a6
                jmp     LVO_Permit(a6)
kfm:            move.l  a1,d1
                beq     .r
                bra     fm
.r:             rts
; kadd(d0 size, d2 pri, d3 = offset of the base in B): AddMemList(size, $41, pri, B+offset, name) and its line
kadd:           bsr     mark
                move.l  d0,rin
                move.l  #$41,rin+4
                move.l  d2,rin+8
                move.l  kblk,a0
                add.l   d3,a0
                move.l  a0,khdr
                move.l  a0,rin+32
                move.l  #n_test,rin+36
                CALL    LVO_AddMemList
                move.l  khdr,a2
                PS      " t="
                moveq   #0,d0
                move.b  LN_TYPE(a2),d0
                bsr     phex
                PS      " p="
                move.b  LN_PRI(a2),d0
                bsr     psig
                PS      " nm="
                moveq   #'1',d1
                cmp.l   #n_test,LN_NAME(a2)
                beq     .nm
                moveq   #'0',d1
.nm:            bsr     putc
                PS      " a="
                moveq   #0,d0
                move.w  MH_ATTR(a2),d0
                bsr     phex
                PS      " lo="
                move.l  MH_LOWER(a2),d0
                bsr     prel
                PS      " hi="
                move.l  MH_UPPER(a2),d0
                bsr     prel
                PS      " fi="
                move.l  MH_FIRST(a2),d0
                bsr     prel
                move.l  a2,a0
                bsr     pch
                PS      " o="
                move.l  ebase,a0
                move.l  EB_MEMLIST(a0),a0
                moveq   #0,d2
.o:             tst.l   (a0)
                beq     .oe
                tst.w   d2
                beq     .o1
                bsr     comma
.o1:            moveq   #'S',d1
                cmp.l   a0,a2
                bne     .os
                moveq   #'N',d1
.os:            bsr     putc
                move.b  LN_PRI(a0),d0
                bsr     psig
                moveq   #1,d2
                move.l  (a0),a0
                bra     .o
.oe:            bsr     pxreg
                bra     nl
krem:           move.l  ebase,a6
                move.l  khdr,a1
                jmp     LVO_Remove(a6)

; ---------------------------------------------------------------------------------------------------------------
; B: CopyMem / CopyMemQuick. Source pattern p(i) = 7i+1, destination $EE with 16 guard bytes each side.
t_copy:         PS      "B0"                 ; registers
                move.l  work,a5
                bsr     mark
                lea     W_CPS+16(a5),a0
                move.l  a0,rin+32
                lea     W_CPD+16(a5),a0
                move.l  a0,rin+36
                moveq   #100,d0
                move.l  d0,rin
                CALL    LVO_CopyMem
                bsr     pxreg
                PS      " q"
                bsr     mark
                move.l  work,a5
                lea     W_CPS+16(a5),a0
                move.l  a0,rin+32
                lea     W_CPD+16(a5),a0
                move.l  a0,rin+36
                moveq   #100,d0
                move.l  d0,rin
                CALL    LVO_CopyMemQuick
                bsr     pxreg
                bsr     nl
                PS      "B1"
                move.w  #LVO_CopyMem,d4
                lea     b1off,a3
                lea     b1siz,a4
                moveq   #-1,d5               ; mask of the size actually copied
                bsr     cploop
                PS      "B2"
                move.w  #LVO_CopyMemQuick,d4
                lea     b2off,a3
                lea     b2siz,a4
                moveq   #-4,d5
                bsr     cploop
                PS      "B3"
                lea     b2off,a3
                lea     b3siz,a4
                bsr     cploop
                PS      "B4"
                lea     b2off,a3
                lea     b4siz,a4
                bsr     cploop
                PS      "B5"
                move.w  #LVO_CopyMem,d4
                lea     b5k,a3
                lea     b5siz,a4
                bsr     ovloop
                PS      "B5q"
                move.w  #LVO_CopyMemQuick,d4
                lea     b5kq,a3
                lea     b5sizq,a4
                bsr     ovloop
                rts
; pat(d0 = index) -> d0.b = 7*index + 1
pat:            mulu    #7,d0
                addq.w  #1,d0
                rts
; fillsrc: W_CPS[i] = pat(i), i = 0..1279
fillsrc:        move.l  work,a0
                lea     W_CPS(a0),a0
                moveq   #0,d1
.l:             move.l  d1,d0
                bsr     pat
                move.b  d0,(a0)+
                addq.w  #1,d1
                cmp.w   #1280,d1
                bne     .l
                rts
; cploop(d4 = LVO, a3 = offset pairs (source, destination bytes, $FF end), a4 = sizes (words, -1 end), d5 = mask of
; the length expected to be copied): " n=<cases> bad=<failures>", first failure " first=<so>,<do>,<size>"
cploop:         moveq   #0,d6
                moveq   #0,d7
.po:            cmp.b   #$FF,(a3)
                beq     .done
                move.l  a4,a2
.sz:            move.w  (a2)+,d3
                bmi     .np
                bsr     fillsrc
                move.l  work,a5
                lea     W_CPD(a5),a0
                move.w  #1279,d0
.fd:            move.b  #$EE,(a0)+
                dbra    d0,.fd
                moveq   #0,d0
                move.b  (a3),d0
                lea     W_CPS+16(a5),a0
                add.w   d0,a0
                move.b  1(a3),d0
                lea     W_CPD+16(a5),a1
                add.w   d0,a1
                moveq   #0,d0
                move.w  d3,d0
                move.l  ebase,a6
                jsr     0(a6,d4.w)
                move.l  work,a5
                moveq   #0,d0
                move.w  d3,d0
                and.l   d5,d0
                move.l  d0,d2                ; d2 = expected length
                moveq   #0,d0
                move.b  (a3),d0
                moveq   #0,d1
                move.b  1(a3),d1
                sub.w   d1,d0
                move.w  d0,a1                ; a1 = source index - destination index
                add.w   #16,d1               ; d1 = first destination index
                lea     W_CPD(a5),a0
                moveq   #0,d0
.ck:            move.w  d0,-(sp)
                sub.w   d1,d0
                bcs     .g
                cmp.w   d2,d0
                bhs     .g
                move.w  (sp),d0
                add.w   a1,d0
                bsr     pat
                bra     .c
.g:             moveq   #-$12,d0             ; $EE
.c:             cmp.b   (a0)+,d0
                bne     .bad
                move.w  (sp)+,d0
                addq.w  #1,d0
                cmp.w   #1280,d0
                bne     .ck
                bra     .nx
.bad:           addq.l  #2,sp
                tst.l   d7
                bne     .b2
                move.b  (a3),fbso
                move.b  1(a3),fbdo
                move.w  d3,fbsz
.b2:            addq.l  #1,d7
.nx:            addq.l  #1,d6
                bra     .sz
.np:            addq.l  #2,a3
                bra     .po
.done:          PS      " n="
                move.l  d6,d0
                bsr     phex
                PS      " bad="
                move.l  d7,d0
                bsr     phex
                tst.l   d7
                beq     .e
                PS      " first="
                moveq   #0,d0
                move.b  fbso,d0
                bsr     phex
                bsr     comma
                move.b  fbdo,d0
                bsr     phex
                bsr     comma
                move.w  fbsz,d0
                bsr     phex
.e:             bra     nl
; ovloop(d4 = LVO, a3 = distances k (words, -1 end), a4 = sizes (words, -1 end)): copy from index 80 to index 80-k
; of the pattern-filled W_CPS; expected: the memmove result. " n= bad= first=<k>,<size>"
ovloop:         moveq   #0,d6
                moveq   #0,d7
.ko:            move.w  (a3)+,d2
                bmi     .done
                move.l  a4,a2
.sz:            move.w  (a2)+,d3
                bmi     .ko
                bsr     fillsrc
                move.l  work,a5
                lea     W_CPS+80(a5),a0
                move.l  a0,a1
                sub.w   d2,a1
                moveq   #0,d0
                move.w  d3,d0
                move.l  ebase,a6
                jsr     0(a6,d4.w)
                move.l  work,a5
                lea     W_CPS(a5),a0
                move.w  #80,d1
                sub.w   d2,d1                ; d1 = destination index
                moveq   #0,d0
.ck:            move.w  d0,-(sp)
                sub.w   d1,d0
                bcs     .o
                cmp.w   d3,d0
                bhs     .o
                move.w  (sp),d0
                add.w   d2,d0                ; copied from index i + k
                bra     .p
.o:             move.w  (sp),d0
.p:             bsr     pat
                cmp.b   (a0)+,d0
                bne     .bad
                move.w  (sp)+,d0
                addq.w  #1,d0
                cmp.w   #1280,d0
                bne     .ck
                bra     .nx
.bad:           addq.l  #2,sp
                tst.l   d7
                bne     .b2
                move.w  d2,fbk
                move.w  d3,fbsz
.b2:            addq.l  #1,d7
.nx:            addq.l  #1,d6
                bra     .sz
.done:          PS      " n="
                move.l  d6,d0
                bsr     phex
                PS      " bad="
                move.l  d7,d0
                bsr     phex
                tst.l   d7
                beq     .e
                PS      " first="
                moveq   #0,d0
                move.w  fbk,d0
                bsr     phex
                bsr     comma
                move.w  fbsz,d0
                bsr     phex
.e:             bra     nl

; ---------------------------------------------------------------------------------------------------------------
; Semaphores. Helper tasks T (ftask 0) and U (ftask 1), priority 22 and 21 (above the probe): a Signal(CMDSIG) makes one
; run its operation list at once, up to its next Wait or until it blocks.
semaddr:        move.l  work,a0              ; semaddr(d1.w = index) -> a0
                lea     W_SEM(a0),a0
                mulu    #48,d1
                add.l   d1,a0
                rts
; ownid(d0): '-' 0, 'M' probe, 'T' task 0, 'U' task 1, '?' other. Preserves everything.
ownid:          move.l  d1,-(sp)
                moveq   #'-',d1
                tst.l   d0
                beq     .p
                moveq   #'M',d1
                cmp.l   me,d0
                beq     .p
                moveq   #'T',d1
                cmp.l   ftask,d0
                beq     .p
                moveq   #'U',d1
                cmp.l   ftask+4,d0
                beq     .p
                moveq   #'?',d1
.p:             bsr     putc
                move.l  (sp)+,d1
                rts
; psem(a0 = semaphore): " n= q= o= w=" (waiters by id, '*' = the semaphore's own ss_MultipleLink)
psem:           movem.l d0-d2/a0-a2,-(sp)
                PS      " n="
                moveq   #0,d0
                move.w  SS_NEST(a0),d0
                bsr     phex
                PS      " q="
                move.w  SS_QC(a0),d0
                bsr     phex
                PS      " o="
                move.l  SS_OWNER(a0),d0
                bsr     ownid
                PS      " w="
                move.l  SS_WQ(a0),a1
                moveq   #0,d2
                tst.l   (a1)
                bne     .l
                moveq   #'-',d1
                bsr     putc
.l:             tst.l   (a1)
                beq     .e
                cmp.w   #8,d2
                beq     .e
                tst.w   d2
                beq     .f
                bsr     comma
.f:             lea     SS_ML(a0),a2
                cmp.l   a2,a1
                bne     .nm
                moveq   #'*',d1
                bsr     putc
.nm:            move.l  8(a1),d0
                bsr     ownid
                addq.w  #1,d2
                move.l  (a1),a1
                bra     .l
.e:             movem.l (sp)+,d0-d2/a0-a2
                rts
; psemi(d1.w = index): psem of semaphore d1
psemi:          move.l  a0,-(sp)
                bsr     semaddr
                bsr     psem
                move.l  (sp)+,a0
                rts
; initsem(d1.w = index): InitSemaphore, direct
initsem:        bsr     semaddr
                move.l  ebase,a6
                jmp     LVO_InitSemaphore(a6)
; run(d0.w = task index, a0 = operation list): Signal(task, CMDSIG), then Forbid/Permit so that a ROM whose Signal
; only requests the switch (this ROM: at the next Permit or interrupt) also runs the helper at once (outside Forbid)
run:            move.l  ebase,a6
                lsl.w   #2,d0
                lea     ftops,a1
                move.l  a0,0(a1,d0.w)
                lea     ftask,a1
                move.l  0(a1,d0.w),a1
                move.l  #CMDSIG,d0
                jsr     LVO_Signal(a6)
                jsr     LVO_Forbid(a6)
                jmp     LVO_Permit(a6)
; helper task body
ftbody:         move.l  4.w,a6
                sub.l   a1,a1
                jsr     LVO_FindTask(a6)
                move.l  d0,a4
                move.l  me,a1                ; parked: tell the probe
                move.l  readysig,d0
                jsr     LVO_Signal(a6)
.lp:            move.l  #CMDSIG,d0
                jsr     LVO_Wait(a6)
                move.l  TC_USERDATA(a4),d0
                lsl.w   #2,d0
                lea     ftops,a0
                move.l  0(a0,d0.w),a3
                bsr     runops
                bra     .lp
runops:         move.w  (a3)+,d0
                move.w  (a3)+,d1
                move.l  (a3)+,a2
                move.l  4.w,a6
                cmp.w   #OP_OBT,d0
                bne     .r
                bsr     semaddr
                jsr     LVO_ObtainSemaphore(a6)
                bra     runops
.r:             cmp.w   #OP_REL,d0
                bne     .s
                bsr     semaddr
                jsr     LVO_ReleaseSemaphore(a6)
                bra     runops
.s:             cmp.w   #OP_SNAP,d0
                bne     .g
                move.l  a2,a0
                bsr     puts
                bsr     psemi
                PS      " sg="
                move.l  me,a0
                moveq   #'0',d1
                btst    #4,TC_SIGRECVD+3(a0)
                beq     .s0
                moveq   #'1',d1
.s0:            bsr     putc
                bsr     nl
                bra     runops
.g:             cmp.w   #OP_SIGME,d0
                bne     .c
                move.l  me,a1
                moveq   #$10,d0
                jsr     LVO_Signal(a6)
                bra     runops
.c:             cmp.w   #OP_CMD,d0
                bne     .e
                lsl.w   #2,d1
                lea     ftask,a1
                move.l  0(a1,d1.w),a1
                move.l  #CMDSIG,d0
                jsr     LVO_Signal(a6)
                bra     runops
.e:             rts
; mktask(d0.w = index, a0 = Task, a1 = stack): AddTask at priority PRI_ME+2 - index (T is never preempted by U,
; and both preempt the probe)
mktask:         move.l  a0,a2
                move.b  #1,LN_TYPE(a2)
                moveq   #PRI_ME+2,d1
                sub.b   d0,d1
                move.b  d1,LN_PRI(a2)
                move.l  #n_task,LN_NAME(a2)
                ext.l   d0
                move.l  d0,TC_USERDATA(a2)
                lsl.w   #2,d0
                lea     ftask,a3
                move.l  a2,0(a3,d0.w)
                move.l  #$FFFF,TC_SIGALLOC(a2)
                move.l  a1,TC_SPLOWER(a2)
                add.l   #STKSZ,a1
                move.l  a1,TC_SPUPPER(a2)
                move.l  a1,TC_SPREG(a2)
                lea     TC_MEMENTRY(a2),a0
                move.l  a0,8(a0)
                clr.l   4(a0)
                lea     4(a0),a1
                move.l  a1,(a0)
                move.l  a2,a1
                lea     ftbody,a2
                sub.l   a3,a3
                move.l  ebase,a6
                jmp     LVO_AddTask(a6)

t_sem:          move.l  ebase,a6
                moveq   #-1,d0
                jsr     LVO_AllocSignal(a6)
                moveq   #0,d1
                bset    d0,d1
                move.l  d1,readysig
                moveq   #0,d7
.mk:            moveq   #0,d0                ; the bit may already be set: cleared before each helper starts
                move.l  readysig,d1
                jsr     LVO_SetSignal(a6)
                move.w  d7,d0
                move.l  work,a5
                lea     W_T1(a5),a0
                lea     W_ST1(a5),a1
                tst.w   d7
                beq     .mk0
                lea     W_T2(a5),a0
                lea     W_ST2(a5),a1
.mk0:           bsr     mktask
                move.l  readysig,d0          ; each helper reaches its Wait before the tests
                jsr     LVO_Wait(a6)
                addq.w  #1,d7
                cmp.w   #2,d7
                bne     .mk
                ; S1: InitSemaphore on 46 bytes of $AB
                move.l  work,a5
                lea     W_SEM(a5),a0
                moveq   #47,d0
.ab:            move.b  #$AB,(a0)+
                dbra    d0,.ab
                PS      "S1"
                bsr     mark
                lea     W_SEM(a5),a0
                move.l  a0,rin+32
                CALL    LVO_InitSemaphore
                moveq   #0,d1
                bsr     psemi
                PS      " nd="               ; node and MultipleLink bytes untouched
                move.l  work,a5
                lea     W_SEM(a5),a0
                moveq   #'1',d1
                moveq   #13,d0
.n1:            cmp.b   #$AB,(a0)+
                beq     .n2
                moveq   #'0',d1
.n2:            dbra    d0,.n1
                bsr     putc
                PS      " ml="
                lea     W_SEM+SS_ML(a5),a0
                moveq   #'1',d1
                moveq   #11,d0
.m1:            cmp.b   #$AB,(a0)+
                beq     .m2
                moveq   #'0',d1
.m2:            dbra    d0,.m1
                bsr     putc
                PS      " a1="
                move.l  rout+36,d0
                sub.l   rin+32,d0
                bsr     phex
                bsr     pxreg
                bsr     nl
                ; S2-S8 on S, the probe alone
                SC      "S2",LVO_ObtainSemaphore
                SC      "S3",LVO_ObtainSemaphore
                SC      "S4",LVO_AttemptSemaphore
                moveq   #0,d1
                bsr     initsem
                SC      "S5",LVO_AttemptSemaphore
                moveq   #0,d1                ; S7: from 3,2,M
                bsr     semaddr
                move.l  ebase,a6
                jsr     LVO_ObtainSemaphore(a6)
                moveq   #0,d1
                bsr     semaddr
                jsr     LVO_ObtainSemaphore(a6)
                SC      "S7",LVO_ReleaseSemaphore
                SC      "S7b",LVO_ReleaseSemaphore
                SC      "S8",LVO_ReleaseSemaphore
                ; S6 / C7: Attempt while T owns (and U waits)
                moveq   #0,d1
                bsr     initsem
                moveq   #0,d0
                lea     ops_obt0,a0
                bsr     run
                SC      "S6",LVO_AttemptSemaphore
                moveq   #1,d0
                lea     ops_obt0_rel0,a0     ; U blocks (queued)
                bsr     run
                SC      "C7",LVO_AttemptSemaphore
                moveq   #0,d0
                lea     ops_rel0,a0          ; T releases: hand-off to U, which runs and releases too
                bsr     run
                PS      "C7e"
                moveq   #0,d1
                bsr     psemi
                bsr     nl
                ; C1 C3 C4 C4b: T owns S, U queued, the probe queues behind U
                moveq   #0,d1
                bsr     initsem
                moveq   #0,d0
                lea     ops_obt0,a0
                bsr     run
                PS      "C0"
                moveq   #0,d1
                bsr     psemi
                bsr     nl
                moveq   #1,d0
                lea     ops_u_c4,a0
                bsr     run
                PS      "C3a"
                moveq   #0,d1
                bsr     psemi
                bsr     nl
                move.l  ebase,a6
                jsr     LVO_Forbid(a6)
                moveq   #$10,d0              ; a SIGF_SEMAPHORE received before the call must not end the wait
                moveq   #$10,d1
                jsr     LVO_SetSignal(a6)
                moveq   #0,d0
                lea     ops_t_c3,a0
                bsr     run
                moveq   #0,d1
                bsr     semaddr
                bsr     mark
                move.l  a0,rin+32
                CALL    LVO_ObtainSemaphore  ; blocks: T, then U run; U hands over to the probe
                PS      "C1"
                moveq   #0,d1
                bsr     psemi
                bsr     pxreg
                bsr     nl
                move.l  ebase,a6
                jsr     LVO_Permit(a6)
                moveq   #0,d1
                bsr     semaddr
                jsr     LVO_ReleaseSemaphore(a6)
                PS      "C8x"
                moveq   #0,d1
                bsr     psemi
                bsr     nl
                ; C5: nested release while T waits, then the last release hands over to T
                moveq   #0,d1
                bsr     initsem
                moveq   #0,d1
                bsr     semaddr
                jsr     LVO_ObtainSemaphore(a6)
                moveq   #0,d1
                bsr     semaddr
                jsr     LVO_ObtainSemaphore(a6)
                moveq   #0,d0
                lea     ops_t_c5,a0
                bsr     run
                SC      "C5",LVO_ReleaseSemaphore
                SC      "C5e",LVO_ReleaseSemaphore
                ; C6: release by a task that does not own it
                moveq   #0,d1
                bsr     initsem
                moveq   #0,d0
                lea     ops_obt0,a0
                bsr     run
                SC      "C6",LVO_ReleaseSemaphore
                ; C2: a SIGF_SEMAPHORE from elsewhere while waiting in ObtainSemaphore (U below the probe releases)
                moveq   #0,d1
                bsr     initsem
                moveq   #0,d0
                lea     ops_obt0,a0
                bsr     run
                moveq   #PRI_LOW,d0
                bsr     setupri
                lea     ftops+4,a0
                move.l  #ops_rel0,(a0)
                move.l  ebase,a6
                jsr     LVO_Forbid(a6)
                moveq   #0,d0
                lea     ops_spur,a0
                bsr     run
                PS      "C2"
                moveq   #0,d1
                bsr     semaddr
                move.l  ebase,a6
                jsr     LVO_ObtainSemaphore(a6)
                moveq   #0,d1
                bsr     psemi
                bsr     nl
                move.l  ebase,a6
                jsr     LVO_Permit(a6)
                moveq   #PRI_ME+1,d0
                bsr     setupri
                moveq   #0,d1
                bsr     semaddr
                move.l  ebase,a6
                jsr     LVO_ReleaseSemaphore(a6)
                ; Q: ObtainSemaphoreList / ReleaseSemaphoreList on [S, S2, S3]
                bsr     mklist
                PS      "Q1"
                move.w  #LVO_ObtainSemaphoreList,d0
                bsr     qcall
                PS      "Q2"
                move.w  #LVO_ObtainSemaphoreList,d0
                bsr     qcall
                PS      "Q7"
                move.w  #LVO_ReleaseSemaphoreList,d0
                bsr     qcall
                PS      "Q8"
                move.w  #LVO_ReleaseSemaphoreList,d0
                bsr     qcall
                ; Q3 (+ C8): S2 owned by T
                bsr     mklist
                moveq   #0,d0
                lea     ops_obt1,a0
                bsr     run
                move.l  ebase,a6
                jsr     LVO_Forbid(a6)
                moveq   #0,d0
                lea     ops_t_q3,a0
                bsr     run
                bsr     obl
                PS      "Q3e"
                bsr     pall
                move.l  ebase,a6
                jsr     LVO_Permit(a6)
                bsr     rsl
                ; Q5: spurious SIGF_SEMAPHORE, then U (below the probe) releases S2
                bsr     mklist
                moveq   #0,d0
                lea     ops_obt1,a0
                bsr     run
                moveq   #PRI_LOW,d0
                bsr     setupri
                lea     ftops+4,a0
                move.l  #ops_rel1,(a0)
                move.l  ebase,a6
                jsr     LVO_Forbid(a6)
                moveq   #0,d0
                lea     ops_spur,a0
                bsr     run
                bsr     obl
                PS      "Q5"
                bsr     pall
                move.l  ebase,a6
                jsr     LVO_Permit(a6)
                moveq   #PRI_ME+1,d0
                bsr     setupri
                bsr     rsl
                ; Q4: S2 and S3 owned by T; S3 handed over first, S2 later by U (below the probe)
                bsr     mklist
                moveq   #0,d0
                lea     ops_obt12,a0
                bsr     run
                moveq   #PRI_LOW,d0
                bsr     setupri
                lea     ftops+4,a0
                move.l  #ops_u_q4,(a0)
                move.l  ebase,a6
                jsr     LVO_Forbid(a6)
                moveq   #0,d0
                lea     ops_t_q4,a0
                bsr     run
                bsr     obl
                PS      "Q4c"
                bsr     pall
                move.l  ebase,a6
                jsr     LVO_Permit(a6)
                moveq   #PRI_ME+1,d0
                bsr     setupri
                bsr     rsl
                ; Q6: both handed over before the first wake-up
                bsr     mklist
                moveq   #0,d0
                lea     ops_obt12,a0
                bsr     run
                move.l  ebase,a6
                jsr     LVO_Forbid(a6)
                moveq   #0,d0
                lea     ops_rel12,a0
                bsr     run
                bsr     obl
                PS      "Q6"
                bsr     pall
                move.l  ebase,a6
                jsr     LVO_Permit(a6)
                bsr     rsl
                bsr     t_n
                bra     t_p
; setupri(d0 = priority of U)
setupri:        move.l  ftask+4,a1
                move.l  ebase,a6
                jmp     LVO_SetTaskPri(a6)
; scallw(d0.w = LVO, a2 = id): one-argument call on S through docall, then the line: id, fields, D0 and A1 for
; AttemptSemaphore, registers
scallw:         move.w  d0,-(sp)
                bsr     mark
                moveq   #0,d1
                bsr     semaddr
                move.l  a0,rin+32
                move.w  (sp),d0
                bsr     docall
                move.l  a2,a0
                bsr     puts
                moveq   #0,d1
                bsr     psemi
                move.w  (sp)+,d0
                cmp.w   #LVO_AttemptSemaphore,d0
                bne     .x
                PS      " d="
                move.l  rout,d0
                bsr     phex
                PS      " a1="
                move.l  rout+36,d0
                bsr     ownid
.x:             bsr     pxreg
                bra     nl
; mklist: S, S2, S3 initialised and linked in that order in the List W_SL
mklist:         moveq   #0,d1
                bsr     initsem
                moveq   #1,d1
                bsr     initsem
                moveq   #2,d1
                bsr     initsem
                move.l  work,a5
                lea     W_SL(a5),a0
                move.l  a0,8(a0)
                clr.l   4(a0)
                lea     4(a0),a1
                move.l  a1,(a0)
                moveq   #0,d7
.l:             move.w  d7,d1
                bsr     semaddr
                move.l  a0,a1
                lea     W_SL(a5),a0
                move.l  ebase,a6
                jsr     LVO_AddTail(a6)
                addq.w  #1,d7
                cmp.w   #3,d7
                bne     .l
                rts
; qcall(d0.w = LVO): list call with the registers, then one line per semaphore (<id>a/b/c)
qcall:          bsr     mark
                move.l  work,a5
                lea     W_SL(a5),a0
                move.l  a0,rin+32
                bsr     docall
                bsr     pxreg
; pall: " a: <S> b: <S2> c: <S3>" then newline
pall:           moveq   #0,d7
.l:             PS      " |"
                move.w  d7,d1
                bsr     psemi
                addq.w  #1,d7
                cmp.w   #3,d7
                bne     .l
                bra     nl
obl:            move.l  work,a5
                lea     W_SL(a5),a0
                move.l  ebase,a6
                jmp     LVO_ObtainSemaphoreList(a6)
rsl:            move.l  work,a5
                lea     W_SL(a5),a0
                move.l  ebase,a6
                jmp     LVO_ReleaseSemaphoreList(a6)

; N: AddSemaphore (working form: semaphore in A1), FindSemaphore, RemSemaphore
t_n:            moveq   #0,d1
                bsr     semaddr
                move.l  a0,a2
                move.l  #n_sem,LN_NAME(a2)
                move.b  #7,LN_PRI(a2)
                PS      "N2"
                bsr     mark
                move.l  a2,rin+36
                CALL    LVO_AddSemaphore
                moveq   #0,d1
                bsr     psemi
                PS      " in="
                bsr     insl
                bsr     pxreg
                bsr     nl
                PS      "N3"
                lea     n_sem,a0
                bsr     fs
                PS      "N4"
                lea     n_nosuch,a0
                bsr     fs
                PS      "N5"
                lea     n_semuc,a0
                bsr     fs
                PS      "N7"                 ; RemSemaphore(A0 = S, A1 = X): X removed from its own list
                move.l  work,a5
                lea     W_DL(a5),a0
                move.l  a0,8(a0)
                clr.l   4(a0)
                lea     4(a0),a1
                move.l  a1,(a0)
                lea     W_DX(a5),a1
                move.l  ebase,a6
                jsr     LVO_AddTail(a6)
                bsr     mark
                move.l  work,a5
                lea     W_SEM(a5),a0
                move.l  a0,rin+32
                lea     W_DX(a5),a0
                move.l  a0,rin+36
                CALL    LVO_RemSemaphore
                PS      " in="
                bsr     insl
                PS      " dl="
                move.l  work,a5
                lea     W_DL+4(a5),a0
                moveq   #'0',d1
                cmp.l   W_DL(a5),a0
                bne     .d
                moveq   #'1',d1              ; dummy list empty
.d:             bsr     putc
                bsr     pxreg
                bsr     nl
                PS      "N6"
                bsr     mark
                move.l  work,a5
                lea     W_SEM(a5),a0
                move.l  a0,rin+36
                CALL    LVO_RemSemaphore
                PS      " in="
                bsr     insl
                bsr     pxreg
                bra     nl
; insl: '1' when S is in ExecBase->SemaphoreList
insl:           movem.l d0-d1/a0-a1,-(sp)
                move.l  work,a1
                lea     W_SEM(a1),a1
                move.l  ebase,a0
                move.l  EB_SEMLIST(a0),a0
                moveq   #'0',d1
                moveq   #31,d0
.l:             tst.l   (a0)
                beq     .e
                cmp.l   a0,a1
                bne     .n
                moveq   #'1',d1
.n:             move.l  (a0),a0
                dbra    d0,.l
.e:             bsr     putc
                movem.l (sp)+,d0-d1/a0-a1
                rts
; fs(a0 = name): FindSemaphore line " r= x="
fs:             bsr     mark
                move.l  a0,rin+36
                move.l  ebase,a6
                jsr     LVO_Forbid(a6)
                CALL    LVO_FindSemaphore
                move.l  ebase,a6
                jsr     LVO_Permit(a6)
                PS      " r="
                move.l  rout,d0
                move.l  work,a0
                lea     W_SEM(a0),a0
                cmp.l   a0,d0
                bne     .o
                moveq   #'S',d1
                bsr     putc
                bra     .x
.o:             bsr     phex
.x:             bsr     pxreg
                bra     nl

; P: Procure / Vacate on an old Semaphore (port PA_IGNORE, sm_Bids -1); messages m1, m2 reply to port RP
t_p:            move.l  work,a5
                lea     W_OS(a5),a0
                bsr     mkport
                move.w  #-1,34(a0)
                lea     W_RP(a5),a0
                bsr     mkport
                lea     W_M1(a5),a0
                lea     W_RP(a5),a1
                move.l  a1,MN_REPLY(a0)
                move.w  #20,MN_LENGTH(a0)
                move.b  #5,LN_TYPE(a0)
                lea     W_M2(a5),a0
                move.l  a1,MN_REPLY(a0)
                move.w  #20,MN_LENGTH(a0)
                move.b  #5,LN_TYPE(a0)
                PS      "P1"
                lea     W_M1(a5),a0
                bsr     proc
                PS      "P2"
                lea     W_M2(a5),a0
                bsr     proc
                PS      "P3"
                bsr     vac
                PS      "P4"
                bsr     vac
                rts
mkport:         move.b  #4,LN_TYPE(a0)
                move.b  #2,MP_FLAGS(a0)      ; PA_IGNORE
                clr.l   MP_SIGTASK(a0)
                lea     MP_MSGLIST(a0),a1
                move.l  a1,8(a1)
                clr.l   4(a1)
                pea     4(a1)
                move.l  (sp)+,(a1)
                rts
proc:           bsr     mark
                move.l  work,a5
                move.l  a0,rin+36
                lea     W_OS(a5),a0
                move.l  a0,rin+32
                CALL    LVO_Procure
                PS      " d="
                move.l  rout,d0
                bsr     phex
                bra     posem
vac:            bsr     mark
                move.l  work,a5
                lea     W_OS(a5),a0
                move.l  a0,rin+32
                CALL    LVO_Vacate
; posem: " lk=<m1|m2|-> b=<sm_Bids> q=<first message of the port> rq=<first message of RP> t2=<type of m2>"
posem:          move.l  work,a5
                PS      " lk="
                move.l  W_OS+MP_SIGTASK(a5),d0
                bsr     pmsg
                PS      " b="
                moveq   #0,d0
                move.w  W_OS+34(a5),d0
                bsr     phex
                PS      " q="
                move.l  W_OS+MP_MSGLIST(a5),d0
                bsr     pmsg
                PS      " rq="
                move.l  W_RP+MP_MSGLIST(a5),d0
                bsr     pmsg
                PS      " t2="
                moveq   #0,d0
                move.b  W_M2+LN_TYPE(a5),d0
                bsr     phex
                bsr     pxreg
                bra     nl
; pmsg(d0): "1" m1, "2" m2, "-" 0 or the list's own tail (empty), "?" other
pmsg:           movem.l d1/a0,-(sp)
                moveq   #'1',d1
                lea     W_M1(a5),a0
                cmp.l   a0,d0
                beq     .p
                moveq   #'2',d1
                lea     W_M2(a5),a0
                cmp.l   a0,d0
                beq     .p
                moveq   #'-',d1
                tst.l   d0
                beq     .p
                move.l  d0,a0
                tst.l   (a0)
                beq     .p
                moveq   #'?',d1
.p:             bsr     putc
                movem.l (sp)+,d1/a0
                rts

; ---------------------------------------------------------------------------------------------------------------
; alertmode(argc): one dead-end alert vector. "MSP alert <c>" on the serial port, $100.l cleared, then the call.
alertmode:      move.l  ebase,a6
                lea     m_alert,a0
                bsr     sputs
                move.b  argc,d1
                bsr     sputc
                moveq   #10,d1
                bsr     sputc
                clr.l   $100.w
                move.b  argc,d0
                cmp.b   #'1',d0              ; G1: FreeMem(0, 8)
                bne     .g3
                sub.l   a1,a1
                moveq   #8,d0
                jmp     LVO_FreeMem(a6)
.g3:            cmp.b   #'3',d0              ; G3: FreeMem(ROM, 8)
                bne     .g4
                move.l  #$FC1000,a1
                moveq   #8,d0
                jmp     LVO_FreeMem(a6)
.g4:            cmp.b   #'4',d0              ; G4: FreeMem(unmapped, 8)
                bne     .g5
                move.l  #$F00000,a1
                moveq   #8,d0
                jmp     LVO_FreeMem(a6)
.g5:            cmp.b   #'5',d0              ; G5: double free
                bne     .g6
                moveq   #64,d0
                moveq   #0,d1
                jsr     LVO_AllocMem(a6)
                move.l  d0,-(sp)
                move.l  d0,a1
                moveq   #64,d0
                jsr     LVO_FreeMem(a6)
                move.l  (sp)+,a1
                moveq   #8,d0
                jmp     LVO_FreeMem(a6)
.g6:            cmp.b   #'6',d0              ; G6: free inside a free chunk
                bne     .v1
                moveq   #64,d0
                moveq   #0,d1
                jsr     LVO_AllocMem(a6)
                move.l  d0,-(sp)
                move.l  d0,a1
                moveq   #64,d0
                jsr     LVO_FreeMem(a6)
                move.l  (sp)+,a1
                add.w   #16,a1
                moveq   #8,d0
                jmp     LVO_FreeMem(a6)
.v1:            lea     valt,a0              ; V1 V4 V5: Deallocate on R [64:64, 256:64]
                moveq   #2,d1
.vl:            cmp.b   (a0),d0
                beq     .vgo
                addq.l  #6,a0
                dbra    d1,.vl
                bra     .s9
.vgo:           move.w  (a0)+,d2             ; skip the selector word
                moveq   #0,d2
                move.w  (a0)+,d2             ; offset
                moveq   #0,d3
                move.w  (a0),d3              ; size
                move.l  work,a5
                lea     W_RH(a5),a0
                lea     W_R(a5),a1
                move.l  a1,MH_LOWER(a0)
                move.l  a1,MH_UPPER(a0)
                add.l   #1024,MH_UPPER(a0)
                move.l  #128,MH_FREE(a0)
                lea     64(a1),a2
                move.l  a2,MH_FIRST(a0)
                lea     256(a1),a3
                move.l  a3,(a2)
                move.l  #64,4(a2)
                clr.l   (a3)
                move.l  #64,4(a3)
                add.l   d2,a1
                move.l  d3,d0
                jmp     LVO_Deallocate(a6)
.s9:            cmp.b   #'s',d0              ; S9: release of a free semaphore
                bne     .h4
                moveq   #0,d1
                bsr     initsem
                moveq   #0,d1
                bsr     semaddr
                jmp     LVO_ReleaseSemaphore(a6)
.h4:            cmp.b   #'h',d0              ; H4: FreeEntry of {0, 8}
                bne     .none
                move.l  work,a5
                lea     W_TPL(a5),a0
                move.w  #1,ML_NUM(a0)
                clr.l   ML_ME(a0)
                move.l  #8,ML_ME+4(a0)
                jmp     LVO_FreeEntry(a6)
.none:          rts

; ---------------------------------------------------------------------------------------------------------------
; direct serial output (only the buffer bounds and the alert marker)
sputc:          move.w  d0,-(sp)
.w:             move.w  SERDATR,d0
                btst    #13,d0
                beq     .w
                and.w   #$FF,d1
                or.w    #$100,d1
                move.w  d1,SERDAT
                move.w  (sp)+,d0
                rts
sputs:          move.b  (a0)+,d1
                beq     .e
                bsr     sputc
                bra     sputs
.e:             rts
shex8:          moveq   #7,d2
.l:             rol.l   #4,d0
                move.w  d0,d1
                and.w   #$F,d1
                move.b  hexd2(pc,d1.w),d1
                bsr     sputc
                dbra    d2,.l
                rts
hexd2:          dc.b    "0123456789ABCDEF"

; ---------------------------------------------------------------------------------------------------------------
                section data,data
m_buf:          dc.b    "MSP buf=",0
m_bend:         dc.b    " end=",0
m_fin:          dc.b    "MSP fin",10,0
m_alert:        dc.b    10,"MSP alert ",0
n_priv:         dc.b    "msp private",0
n_test:         dc.b    "testmem",0
n_task:         dc.b    "msp helper",0
n_sem:          dc.b    "r13sem",0
n_semuc:        dc.b    "R13SEM",0
n_nosuch:       dc.b    "nosuch",0
regnames:       dc.b    "d0d1d2d3d4d5d6d7a0a1a2a3a4a5"
                even
; alert vectors V1 V4 V5: selector char (word), offset, size
valt:           dc.w    'v'<<8,64,8
                dc.w    'w'<<8,32,64
                dc.w    'x'<<8,0,512

; A/D table (id, op, offset, size, n, chunks)
adtab:          dc.b    "A1",0,0
                dc.w    0
                dc.l    0,1
                dc.w    1,0,1024
                dc.b    "A2",0,0
                dc.w    0
                dc.l    0,8
                dc.w    -1
                dc.b    "A3",0,0
                dc.w    0
                dc.l    0,9
                dc.w    -1
                dc.b    "A4",0,0
                dc.w    0
                dc.l    0,0
                dc.w    -1
                dc.b    "A5",0,0
                dc.w    0
                dc.l    0,1024
                dc.w    -1
                dc.b    "A6",0,0
                dc.w    0
                dc.l    0,100
                dc.w    3,0,64,128,64,256,64
                dc.b    "A7a",0
                dc.w    0
                dc.l    0,64
                dc.w    3,0,64,128,64,256,64
                dc.b    "A7b",0
                dc.w    0
                dc.l    0,32
                dc.w    -1
                dc.b    "A7c",0
                dc.w    0
                dc.l    0,40
                dc.w    -1
                dc.b    "A8",0,0
                dc.w    0
                dc.l    0,992
                dc.w    1,32,992
                dc.b    "A9",0,0
                dc.w    0
                dc.l    0,1024
                dc.w    1,0,1024
                dc.b    "A10",0
                dc.w    0
                dc.l    0,$FFFFFFF8
                dc.w    1,0,1024
                dc.b    "A10b"
                dc.w    0
                dc.l    0,$80000000
                dc.w    -1
                dc.b    "A11",0
                dc.w    0
                dc.l    0,$FFFFFFFF
                dc.w    1,0,1024
                dc.b    "D1",0,0
                dc.w    1
                dc.l    0,64
                dc.w    2,64,64,256,64
                dc.b    "D2",0,0
                dc.w    1
                dc.l    128,64
                dc.w    2,64,64,256,64
                dc.b    "D3",0,0
                dc.w    1
                dc.l    192,64
                dc.w    2,64,64,256,64
                dc.b    "D4",0,0
                dc.w    1
                dc.l    128,128
                dc.w    2,64,64,256,64
                dc.b    "D5",0,0
                dc.w    1
                dc.l    160,32
                dc.w    2,64,64,256,64
                dc.b    "D6",0,0
                dc.w    1
                dc.l    512,64
                dc.w    2,64,64,256,64
                dc.b    "D7",0,0
                dc.w    1
                dc.l    0,0
                dc.w    1,256,64
                dc.b    "D8",0,0
                dc.w    1
                dc.l    0,8
                dc.w    0
                dc.b    "D9a",0
                dc.w    1
                dc.l    0,1
                dc.w    1,256,64
                dc.b    "D9b",0
                dc.w    1
                dc.l    0,9
                dc.w    1,256,64
                dc.b    "D9c",0
                dc.w    1
                dc.l    4,8
                dc.w    1,256,64
                dc.b    "D9d",0
                dc.w    1
                dc.l    4,4
                dc.w    1,256,64
                dc.b    "D9e",0
                dc.w    1
                dc.l    2,16
                dc.w    1,256,64
                dc.b    "D9f",0
                dc.w    1
                dc.l    5,3
                dc.w    1,256,64
                dc.l    0

; M: id, size, requirements (the private headers carry $0800)
mtab:           dc.b    "M1",0,0
                dc.l    1,0
                dc.b    "M2",0,0
                dc.l    4,0
                dc.b    "M3",0,0
                dc.l    7,0
                dc.b    "M4",0,0
                dc.l    8,0
                dc.b    "M5",0,0
                dc.l    9,0
                dc.b    "M6",0,0
                dc.l    15,0
                dc.b    "M7",0,0
                dc.l    16,0
                dc.b    "M8",0,0
                dc.l    17,0
                dc.b    "M9",0,0
                dc.l    0,0
                dc.b    "M10",0
                dc.l    $FFFFFFFF,4
                dc.b    "M10b"
                dc.l    $FFFFFFF9,4
                dc.b    "M11",0
                dc.l    $FFFFFFF8,4
                dc.b    "M12",0
                dc.l    $80000000,4
                dc.b    "M13",0
                dc.l    $7FFFFFFF,4
                dc.b    "M14",0
                dc.l    1025,$804
                dc.b    "M14b"
                dc.l    1024,$804
                dc.l    0
; F: id, requirements
ftab:           dc.b    "F1",0,0
                dc.l    0
                dc.b    "F2",0,0
                dc.l    1
                dc.b    "F3",0,0
                dc.l    2
                dc.b    "F4",0,0
                dc.l    3
                dc.b    "F5",0,0
                dc.l    4
                dc.b    "F6",0,0
                dc.l    5
                dc.b    "F7",0,0
                dc.l    6
                dc.b    "F8",0,0
                dc.l    7
                dc.b    "F9",0,0
                dc.l    8
                dc.b    "F10",0
                dc.l    $100
                dc.b    "F11",0
                dc.l    $200
                dc.b    "F12",0
                dc.l    $400
                dc.b    "F13",0
                dc.l    $10000
                dc.b    "F14",0
                dc.l    $20000
                dc.b    "F15",0
                dc.l    $40000
                dc.b    "F16",0
                dc.l    $80000
                dc.b    "F17",0
                dc.l    $80000000
                dc.b    "F18",0
                dc.l    $10002
                dc.b    "F19",0
                dc.l    $20002
                dc.l    0
; T: id, requirements
ttab:           dc.b    "Tp1",0
                dc.l    $800
                dc.b    "Tp2",0
                dc.l    $20800
                dc.b    "Tp3",0
                dc.l    $80800
                dc.b    "Tp4",0
                dc.l    $10800
                dc.b    "Tp5",0
                dc.l    $802
                dc.b    "Tp6",0
                dc.l    $804
                dc.b    "Tp7",0
                dc.l    $806
                dc.b    "T1",0,0
                dc.l    0
                dc.b    "T2",0,0
                dc.l    1
                dc.b    "T3",0,0
                dc.l    2
                dc.b    "T4",0,0
                dc.l    3
                dc.b    "T5",0,0
                dc.l    4
                dc.b    "T6",0,0
                dc.l    5
                dc.b    "T7",0,0
                dc.l    6
                dc.b    "T8",0,0
                dc.l    8
                dc.b    "T9",0,0
                dc.l    $100
                dc.b    "T10",0
                dc.l    $10000
                dc.b    "T11",0
                dc.l    $20000
                dc.b    "T12",0
                dc.l    $20002
                dc.b    "T13",0
                dc.l    $20004
                dc.b    "T14",0
                dc.l    $80000
                dc.b    "T15",0
                dc.l    $80002
                dc.b    "T16",0
                dc.l    $80004
                dc.b    "T17",0
                dc.l    $A0000
                dc.l    0
; L: id, kind.w (bit 0 FreeMem, bit 1 offset from C, bit 2 absolute), offset.l, size.l
ltab:           dc.b    "L1",0,0
                dc.w    0
                dc.l    $100,64
                dc.b    "L1f",0
                dc.w    1
                dc.l    $100,64
                dc.b    "L2",0,0
                dc.w    0
                dc.l    $104,64
                dc.b    "L2f",0
                dc.w    1
                dc.l    $100,72
                dc.b    "L3",0,0
                dc.w    0
                dc.l    $103,60
                dc.b    "L4",0,0
                dc.w    1
                dc.l    $100,64
                dc.b    "L5",0,0
                dc.w    0
                dc.l    0,64
                dc.b    "L6",0,0
                dc.w    0
                dc.l    64,968
                dc.b    "L7",0,0
                dc.w    0
                dc.l    32,64
                dc.b    "L8",0,0
                dc.w    0
                dc.l    8,16
                dc.b    "L9",0,0
                dc.w    4
                dc.l    $FC1000,64
                dc.b    "L9f",0
                dc.w    1
                dc.l    0,64
                dc.b    "L10",0
                dc.w    0
                dc.l    $200,0
                dc.b    "L10m"
                dc.w    0
                dc.l    $1F8,8
                dc.b    "L10f"
                dc.w    1
                dc.l    $1F8,8
                dc.b    "L11",0
                dc.w    0
                dc.l    0,1024
                dc.b    "L11f"
                dc.w    1
                dc.l    0,1024
                dc.b    "L11b"
                dc.w    0
                dc.l    $3C0,64
                dc.b    "L11g"
                dc.w    1
                dc.l    $3C0,64
                dc.b    "L11c"
                dc.w    2
                dc.l    $100,8
                dc.b    "L11h"
                dc.w    3
                dc.l    $100,8
                dc.b    "L12",0
                dc.w    0
                dc.l    $3E0,64
                dc.l    0
; E: id, kind.w (0 normal, 1 E7 with memory eaten, 2 H3), ml_NumEntries.w, entries in the table.w, entries
etab:           dc.b    "E1",0,0
                dc.w    0,2,2
                dc.l    1,100,$10002,50
                dc.b    "E2",0,0
                dc.w    0,2,2
                dc.l    1,0,2,8
                dc.b    "E4",0,0
                dc.w    0,3,3
                dc.l    1,64,$10004,$7FFFFFF0,2,64
                dc.b    "E5",0,0
                dc.w    0,1,1
                dc.l    8,64
                dc.b    "E6",0,0
                dc.w    0,2,2
                dc.l    2,64,6,64
                dc.b    "E7",0,0
                dc.w    1,$6000,1
                dc.l    1,64
                dc.b    "E8",0,0
                dc.w    0,0,1
                dc.l    1,24
                dc.b    "H3",0,0
                dc.w    2,0,0
                dc.l    0

; offsets (source, destination) and sizes of the copy loops
b1off:          dc.b    0,0,1,0,0,1,1,1,2,0,0,2,2,2,$FF
                even
b1siz:          dc.w    0,1,2,3,4,5,7,8,9,15,16,17,31,32,33,100,1000,-1
b2off:          dc.b    0,0,4,0,0,4,2,2,2,0,$FF
                even
b2siz:          dc.w    0,4,8,12,16,20,100,1000,-1
b3siz:          dc.w    1,2,3,-1
b4siz:          dc.w    5,6,7,-1
b5k:            dc.w    1,4,8,16,64,-1
b5siz:          dc.w    16,17,63,64,100,256,-1
b5kq:           dc.w    4,8,16,64,-1
b5sizq:         dc.w    16,64,96,256,-1

; helper task operation lists (code, argument, pointer)
ops_obt0:       dc.w    OP_OBT,0
                dc.l    0
                dc.w    OP_END,0
                dc.l    0
ops_rel0:       dc.w    OP_REL,0
                dc.l    0
                dc.w    OP_END,0
                dc.l    0
ops_obt1:       dc.w    OP_OBT,1
                dc.l    0
                dc.w    OP_END,0
                dc.l    0
ops_rel1:       dc.w    OP_REL,1
                dc.l    0
                dc.w    OP_END,0
                dc.l    0
ops_obt12:      dc.w    OP_OBT,1
                dc.l    0
                dc.w    OP_OBT,2
                dc.l    0
                dc.w    OP_END,0
                dc.l    0
ops_rel12:      dc.w    OP_REL,1
                dc.l    0
                dc.w    OP_REL,2
                dc.l    0
                dc.w    OP_END,0
                dc.l    0
ops_obt0_rel0:  dc.w    OP_OBT,0
                dc.l    0
                dc.w    OP_REL,0
                dc.l    0
                dc.w    OP_END,0
                dc.l    0
ops_u_c4:       dc.w    OP_OBT,0             ; U: queued behind T; once woken, snapshot and release
                dc.l    0
                dc.w    OP_SNAP,0
                dc.l    l_c4u
                dc.w    OP_REL,0
                dc.l    0
                dc.w    OP_END,0
                dc.l    0
ops_t_c3:       dc.w    OP_SNAP,0            ; T, while the probe waits behind U
                dc.l    l_c3
                dc.w    OP_REL,0
                dc.l    0
                dc.w    OP_SNAP,0
                dc.l    l_c4b
                dc.w    OP_END,0
                dc.l    0
ops_t_c5:       dc.w    OP_OBT,0
                dc.l    0
                dc.w    OP_SNAP,0
                dc.l    l_c5t
                dc.w    OP_REL,0
                dc.l    0
                dc.w    OP_END,0
                dc.l    0
ops_spur:       dc.w    OP_SIGME,0           ; T: spurious SIGF_SEMAPHORE to the probe, then wakes U
                dc.l    0
                dc.w    OP_CMD,1
                dc.l    0
                dc.w    OP_END,0
                dc.l    0
ops_t_q3:       dc.w    OP_SNAP,0
                dc.l    l_q3a
                dc.w    OP_SNAP,1
                dc.l    l_q3b
                dc.w    OP_SNAP,2
                dc.l    l_q3c
                dc.w    OP_REL,1
                dc.l    0
                dc.w    OP_SNAP,1
                dc.l    l_q3d
                dc.w    OP_END,0
                dc.l    0
ops_t_q4:       dc.w    OP_REL,2
                dc.l    0
                dc.w    OP_SNAP,2
                dc.l    l_q4a
                dc.w    OP_CMD,1
                dc.l    0
                dc.w    OP_END,0
                dc.l    0
ops_u_q4:       dc.w    OP_SNAP,2
                dc.l    l_q4b
                dc.w    OP_REL,1
                dc.l    0
                dc.w    OP_END,0
                dc.l    0
l_c3:           dc.b    "C3",0
l_c4b:          dc.b    "C4b",0
l_c4u:          dc.b    "C4u",0
l_c5t:          dc.b    "C5t",0
l_q3a:          dc.b    "Q3a",0
l_q3b:          dc.b    "Q3b",0
l_q3c:          dc.b    "Q3c",0
l_q3d:          dc.b    "Q3d",0
l_q4a:          dc.b    "Q4a",0
l_q4b:          dc.b    "Q4b",0
                even

                section bss,bss
ebase:          ds.l    1
me:             ds.l    1
obuf:           ds.l    1
optr:           ds.l    1
work:           ds.l    1
kblk:           ds.l    1
khdr:           ds.l    1
oldam:          ds.l    1
oldfm:          ds.l    1
logn:           ds.l    1
fbsz:           ds.w    1
fbk:            ds.w    1
fbso:           ds.b    1
fbdo:           ds.b    1
argc:           ds.b    1
logon:          ds.b    1
zcount:         ds.b    1
                even
rin:            ds.l    14
rout:           ds.l    14
rtab:           ds.b    10*4+4               ; 4 regions (base.l, size.l, letter.w), then a 0 base
logbuf:         ds.l    3*16
eatt:           ds.l    2*17
ftask:          ds.l    2
ftops:          ds.l    2
readysig:       ds.l    1
