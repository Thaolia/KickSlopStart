; src/exec/cia.s — cia.resource (ciaa.resource + ciab.resource) — M5b.
; FIRST real resident module (direct-init, pri 80). Its ROMTag is scanned by
; build_reslist; InitResident calls cia_init which creates BOTH CIA resources via
; MakeLibrary (library-like base + AddICRVector/RemICRVector/AbleICR/SetICR jump table),
; names them (ciaa/ciab), sets the hardware base, AddResource. The functions manage the
; ICR vector slots (5 per CIA, base layout of docs/analysis/resources-v34.md §1.1), a software copy of
; the enabled ICR mask and a software PENDING mask: flags read from the chip on a disabled bit stay latched
; until that bit is enabled (AbleICR then re-requests the CIA's level) or cleared by SetICR.
; INTERRUPT DISPATCH: cia_dispatch reads the chip's ICR once (ACK), merges it into the pending mask and
; calls the vector of each pending and enabled bit. In M7b, cia_server (wraps cia_dispatch) is registered as
; PORTS/EXTER SERVER via exec's by-number dispatcher (AddIntServer/SetIntVector) instead of a
; hardcoded autovector -> cia.resource IS the PORTS/EXTER handler, as in the real exec.
; Convention: functions called with a6 = resource base; scratch = d0/d1/a0/a1.
; IMPLEMENTATION track ("clean"): AutoDocs cia.resource + exec. NO reading of the ROM.
; ABSOLUTE vector table here (the M5a AUTOINIT demo is relative -> both branches of
; MakeFunctions remain exercised).

                include "exec.i"

                xdef    cia_init
                xdef    ciaa_server       ; M7b: PORTS server (ciaa) — IS_CODE of a registered server
                xdef    ciab_server       ; M7b: EXTER server (ciab)

; --- cia.resource ROMTag (scanned by build_reslist) ---
        EVEN
cia_romtag:
        dc.w    RTC_MATCHWORD
        dc.l    cia_romtag           ; RT_MATCHTAG = self
        dc.l    cia_end              ; RT_ENDSKIP
        dc.b    RTF_COLDSTART,34,NT_RESOURCE,80  ; RT_FLAGS (COLDSTART, direct init), RT_VERSION, RT_TYPE, RT_PRI
        dc.l    cia_resname          ; RT_NAME
        dc.l    cia_resname          ; RT_IDSTRING
        dc.l    cia_init             ; RT_INIT (direct-init)
cia_resname:
        dc.b    "cia.resource",0
ciaa_name:
        dc.b    "ciaa.resource",0
ciab_name:
        dc.b    "ciab.resource",0
        EVEN
cia_vectors:                         ; ABSOLUTE table, terminated by -1
        dc.l    cia_AddICRVector     ; LVO -6
        dc.l    cia_RemICRVector     ; LVO -12
        dc.l    cia_AbleICR          ; LVO -18
        dc.l    cia_SetICR           ; LVO -24
        dc.l    -1

; cia_init: direct-init (D0=0, A0=segList, A6=ExecBase) -> D0=0. Creates ciaa then ciab.
cia_init:
        movem.l d2/a2,-(sp)
        move.l  #CIAA_HW,d2
        lea     ciaa_name(pc),a2
        bsr.s   cia_make
        move.l  #CIAA_HW,a0
        bsr.s   cia_todstart
        move.l  #CIAB_HW,d2
        lea     ciab_name(pc),a2
        bsr.s   cia_make
        move.l  #CIAB_HW,a0
        bsr.s   cia_todstart
        moveq   #0,d0
        movem.l (sp)+,d2/a2
        rts

; cia_todstart(a0 = CIA base): the TOD counter (frames on CIA-A, lines on CIA-B) stays stopped as long as TODLO
; has not been written. CRB ALARM = 0 (the writes target the time, not the alarm), then TODHI, TODMID, TODLO last,
; which restarts counting. Some programs measure time through the TOD (SysInfo: docs/analysis/sysinfo-44.md).
; Writes by MOVE: CLR reads the address first on 68000, and reading TODHI freezes the TOD read until TODLO is read.
cia_todstart:
        and.b   #$7F,$F00(a0)        ; CRB
        moveq   #0,d0
        move.b  d0,$A00(a0)          ; TODHI
        move.b  d0,$900(a0)          ; TODMID
        move.b  d0,$800(a0)          ; TODLO: start
        rts

; cia_make: creates a CIA resource. d2 = hardware base, a2 = name. a6 = SysBase.
cia_make:
        move.l  a2,-(sp)             ; save the name (MakeLibrary clobbers a2)
        lea     cia_vectors(pc),a0
        suba.l  a1,a1                ; structure = NULL
        suba.l  a2,a2                ; init = NULL
        move.l  #CIAR_SIZE,d0
        moveq   #0,d1                ; segList = 0
        jsr     LVO_MAKELIBRARY(a6)  ; -> d0 = base (jump table built)
        move.l  (sp)+,a2
        tst.l   d0
        beq.s   .cm_ret              ; alloc failed
        move.l  d0,a1                ; a1 = resource base
        move.l  a2,LN_NAME(a1)
        move.b  #NT_RESOURCE,LN_TYPE(a1)
        move.l  d2,CIAR_HWBASE(a1)
        move.w  #INTF_PORTS,CIAR_INTBIT(a1)
        cmp.l   #CIAA_HW,d2
        beq.s   .cm_add
        move.w  #INTF_EXTER,CIAR_INTBIT(a1)
        or.b    #$C0,CIAB_HW         ; CIA-B /DTR and /RTS high (inactive),
        or.b    #$C0,CIAB_HW+$200    ; then outputs (DDRA)
.cm_add:
        jsr     LVO_ADDRESOURCE(a6)  ; AddResource(a1=base) (preserves a1 and d2)
        cmp.l   #CIAA_HW,d2          ; publish the base pointer for the interrupt handler
        bne.s   .cm_notA
        move.l  a1,CIAA_PTR
        bra.s   .cm_ret
.cm_notA:
        move.l  a1,CIAB_PTR
.cm_ret:
        rts

; --- cia.resource functions (a6 = resource base, spec resources-v34 §1.4-1.7) ---
; All run under an inline Disable (INTENA + IDNestCnt): they are called from interrupt handlers too (trackdisk index,
; timer), where the Enable LVO must not reschedule.

cia_dis:
        move.l  a0,-(sp)
        move.l  ($4).w,a0
        move.w  #INTF_INTEN,INTENA
        addq.b  #1,EB_IDNEST(a0)
        move.l  (sp)+,a0
        rts
cia_ena:
        move.l  a0,-(sp)
        move.l  ($4).w,a0
        subq.b  #1,EB_IDNEST(a0)
        bge.s   .ce_ret
        move.w  #INTF_SETCLR|INTF_INTEN,INTENA
.ce_ret:
        move.l  (sp)+,a0
        rts

; cia_vec(d0 = ICR bit) -> a0 = its IntVector. Clobbers d1.
cia_vec:
        move.w  d0,d1
        mulu    #IV_SIZE,d1
        lea     CIAR_VECTORS(a6,d1.l),a0
        rts

; AddICRVector(iCRBit d0, interrupt a1) -> d0 = 0, or the Interrupt that already owns the bit (nothing changed).
; is_Data/is_Code are copied into the vector now; the bit is then enabled (a latched flag fires at once).
cia_AddICRVector:
        bsr.s   cia_dis
        bsr.s   cia_vec
        move.l  IV_NODE(a0),d1
        bne.s   .aiv_out
        move.l  a1,IV_NODE(a0)
        move.l  IS_DATA(a1),IV_DATA(a0)
        move.l  IS_CODE(a1),IV_CODE(a0)
        moveq   #0,d1
        bset    d0,d1
        bset    #7,d1
        move.l  d1,d0
        bsr.s   cia_ablecore
        moveq   #0,d1
.aiv_out:
        move.l  d1,d0
        bra.s   cia_ena

; RemICRVector(iCRBit d0, interrupt a1) -> d0 = 0. The owner is not checked; the bit is disabled.
cia_RemICRVector:
        bsr.s   cia_dis
        bsr.s   cia_vec
        clr.l   IV_NODE(a0)
        moveq   #0,d1
        bset    d0,d1
        move.l  d1,d0
        bsr.s   cia_ablecore
        moveq   #0,d0
        bra.s   cia_ena

; AbleICR(mask d0) -> d0 = enabled mask before the change. Bit 7 set enables the listed bits, clear disables them;
; AbleICR(0) only reads the mask.
cia_AbleICR:
        bsr.s   cia_dis
        bsr.s   cia_ablecore
        bra.s   cia_ena

; cia_ablecore(d0.b = mask): AbleICR body, caller holds Disable. -> d0 = old enabled mask. Clobbers d1/a0.
cia_ablecore:
        move.l  CIAR_HWBASE(a6),a0
        move.b  d0,CIA_ICR_OFF(a0)
        moveq   #0,d1
        move.b  CIAR_ICRMASK(a6),d1
        exg     d0,d1
        bclr    #7,d1
        beq.s   .ac_off
        or.b    d1,CIAR_ICRMASK(a6)
        bra.s   cia_retrig
.ac_off:
        not.b   d1
        and.b   d1,CIAR_ICRMASK(a6)
; cia_retrig: flags pending on enabled bits -> request the CIA's interrupt level by software so the server runs.
; Preserves d0, clobbers d1.
cia_retrig:
        move.b  CIAR_ICRMASK(a6),d1
        and.b   CIAR_PENDING(a6),d1
        beq.s   .rt_ret
        move.w  CIAR_INTBIT(a6),d1
        or.w    #INTF_SETCLR,d1
        move.w  d1,INTREQ
.rt_ret:
        rts

; SetICR(mask d0) -> d0 = pending mask after merging the hardware flags, before the change. The hardware ICR is read
; (and so acknowledged) into the pending mask first; bit 7 set adds the listed flags (software CIA interrupt), clear
; removes them. SetICR(0) samples the flags.
cia_SetICR:
        bsr     cia_dis
        move.l  CIAR_HWBASE(a6),a0
        move.b  CIA_ICR_OFF(a0),d1
        and.b   #$7F,d1
        or.b    d1,CIAR_PENDING(a6)
        moveq   #0,d1
        move.b  CIAR_PENDING(a6),d1
        exg     d0,d1
        bclr    #7,d1
        beq.s   .si_off
        or.b    d1,CIAR_PENDING(a6)
        bra.s   .si_trig
.si_off:
        not.b   d1
        and.b   d1,CIAR_PENDING(a6)
.si_trig:
        bsr.s   cia_retrig
        bra     cia_ena

; --- CIA interrupt server (M6b -> M7b) ---
; ciaa_server / ciab_server: PORTS / EXTER servers called by the generic by-number dispatcher
; (interrupts.s). The resource base is NOT taken from IS_DATA (a chained struct Interrupt lives in RAM,
; but the exclusive EXTER vector lives in ROM -> impossible to freeze a runtime pointer there): each
; wrapper reads CIAA_PTR / CIAB_PTR (published by cia_make). Reads+acknowledges the chip's ICR via cia_dispatch.
; Server convention: preserves d2-d7/a2-a4; cia_dispatch clobbers d2/d3/a2 -> we save them. Returns
; Z SET (d0=0) = "continue the chain" (VERTB server type: lets the other servers run too).
ciaa_server:
        move.l  CIAA_PTR,a1          ; ciaa base (0 if not created -> cia_dispatch no-op)
        bra.s   cia_server_common
ciab_server:
        move.l  CIAB_PTR,a1          ; ciab base
cia_server_common:
        movem.l d2/d3/a2,-(sp)
        move.l  a1,a2                ; a2 = resource base
        bsr.s   cia_dispatch
        movem.l (sp)+,d2/d3/a2
        moveq   #0,d0                ; Z set -> continue the chain
        rts
cia_dispatch:                        ; a2 = resource base (0 ok), a6 = SysBase
        move.l  a2,d0
        beq.s   .cd_ret
        move.l  CIAR_HWBASE(a2),a0
        move.b  CIA_ICR_OFF(a0),d3   ; ICR read once: acknowledges the chip
        and.b   #$7F,d3
        or.b    CIAR_PENDING(a2),d3  ; d3 = all pending flags
        move.b  d3,d0
        and.b   CIAR_ICRMASK(a2),d3  ; d3 = active (pending and enabled)
        eor.b   d3,d0                ; disabled flags stay latched in software
        move.b  d0,CIAR_PENDING(a2)
        tst.b   d3
        beq.s   .cd_ret
        moveq   #0,d2                ; bits 0..4 in order
.cd_loop:
        btst    d2,d3
        beq.s   .cd_next
        move.w  d2,d0
        mulu    #IV_SIZE,d0
        movem.l CIAR_VECTORS(a2,d0.l),a1/a5   ; a1 = iv_Data, a5 = iv_Code
        move.l  a5,d0
        beq.s   .cd_next
        jsr     (a5)
.cd_next:
        addq.l  #1,d2
        cmp.l   #5,d2
        bne.s   .cd_loop
.cd_ret:
        rts
        EVEN
cia_end:
