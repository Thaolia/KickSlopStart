; src/exec/cia.s — cia.resource (ciaa.resource + ciab.resource) — M5b.
; FIRST real resident module (direct-init, pri 80). Its ROMTag is scanned by
; build_reslist; InitResident calls cia_init which creates BOTH CIA resources via
; MakeLibrary (library-like base + AddICRVector/RemICRVector/AbleICR/SetICR jump table),
; names them (ciaa/ciab), sets the hardware base, AddResource. The functions manage the
; ICR vector slots (5 per CIA) + the shadow of the ICR mask + the chip's ICR register.
; INTERRUPT DISPATCH: cia_dispatch reads the chip's ICR once (ACK + clears all pending) and
; calls the vector of each set bit. In M7b, cia_server (wraps cia_dispatch) is registered as
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
        jsr     LVO_ADDRESOURCE(a6)  ; AddResource(a1=base) (preserves a1 and d2)
        cmp.l   #CIAA_HW,d2          ; publish the base pointer for the interrupt handler
        bne.s   .cm_notA
        move.l  a1,CIAA_PTR
        bra.s   .cm_ret
.cm_notA:
        move.l  a1,CIAB_PTR
.cm_ret:
        rts

; --- cia.resource functions (a6 = resource base) ---

; AddICRVector(iCRBit d0, interrupt a1) -> d0 = NULL (ok) | interrupt occupying the bit.
; Stores the vector in the slot + enables the ICR bit (shadow + chip register).
cia_AddICRVector:
        move.l  d0,d1
        lsl.l   #2,d1                ; d1 = slot offset = bit*4 (index, preserved)
        lea     CIAR_VECTORS(a6),a0
        tst.l   0(a0,d1.l)           ; slot occupied? (without clobbering index d1)
        bne.s   .aiv_owned
        move.l  a1,0(a0,d1.l)        ; store the vector
        moveq   #1,d1
        lsl.l   d0,d1                ; d1 = 1<<bit
        or.b    d1,CIAR_ICRMASK(a6)  ; shadow |= bit
        or.b    #$80,d1              ; chip: set-bits
        move.l  CIAR_HWBASE(a6),a0
        move.b  d1,CIA_ICR_OFF(a0)
        moveq   #0,d0                ; success
        rts
.aiv_owned:
        move.l  0(a0,d1.l),d0        ; return the occupant of the bit
        rts

; RemICRVector(iCRBit d0, interrupt a1) -> void. Frees the slot + disables the ICR bit.
cia_RemICRVector:
        move.l  d0,d1
        lsl.l   #2,d1
        lea     CIAR_VECTORS(a6),a0
        clr.l   0(a0,d1.l)           ; slot freed
        moveq   #1,d1
        lsl.l   d0,d1                ; d1 = 1<<bit (chip: clear-bits, no $80)
        move.b  d1,d0
        not.b   d0
        and.b   d0,CIAR_ICRMASK(a6)  ; shadow &= ~bit
        move.l  CIAR_HWBASE(a6),a0
        move.b  d1,CIA_ICR_OFF(a0)
        rts

; AbleICR(mask d0) -> d0 = old mask. bit7=1: enable (mask&$7F); bit7=0: disable;
; d0=0: read-only of the current mask (shadow).
cia_AbleICR:
        move.l  d2,-(sp)
        moveq   #0,d2
        move.b  CIAR_ICRMASK(a6),d2  ; old mask (to return)
        move.l  d0,d1
        btst    #7,d1
        beq.s   .ai_clear
        and.b   #$7F,d1              ; enable these bits
        or.b    d1,CIAR_ICRMASK(a6)
        or.b    #$80,d1              ; chip: set-bits
        bra.s   .ai_hw
.ai_clear:
        and.b   #$7F,d1
        beq.s   .ai_done             ; mask == 0 -> read-only
        move.b  d1,d0
        not.b   d0
        and.b   d0,CIAR_ICRMASK(a6)  ; shadow &= ~bits (chip: clear-bits, d1 without $80)
.ai_hw:
        move.l  CIAR_HWBASE(a6),a0
        move.b  d1,CIA_ICR_OFF(a0)
.ai_done:
        move.l  d2,d0                ; old mask
        move.l  (sp)+,d2
        rts

; SetICR(mask d0) -> d0. Minimal STUB this milestone (handling of the interrupt status deferred
; with the INT2/INT6 dispatch): returns 0, does not touch the chip (an ICR read would clear
; the status). To be completed with the dispatch.
cia_SetICR:
        moveq   #0,d0
        rts

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
        move.b  CIA_ICR_OFF(a0),d3   ; ICR READ: pending (b7=IR, b0-4 sources) + chip ACK
        and.b   CIAR_ICRMASK(a2),d3  ; only enabled sources: the ICR read also reports masked sources
        beq.s   .cd_ret
        moveq   #0,d2                ; bit 0..4
.cd_loop:
        btst    d2,d3
        beq.s   .cd_next
        move.l  d2,d0
        lsl.l   #2,d0
        lea     CIAR_VECTORS(a2),a0
        move.l  0(a0,d0.l),d0        ; struct Interrupt* of the slot
        beq.s   .cd_next
        move.l  d0,a0
        move.l  IS_DATA(a0),a1
        move.l  IS_CODE(a0),a5
        jsr     (a5)                 ; server (a1=data, a5=code, a6=SysBase)
.cd_next:
        addq.l  #1,d2
        cmp.l   #5,d2
        bne.s   .cd_loop
.cd_ret:
        rts
        EVEN
cia_end:
