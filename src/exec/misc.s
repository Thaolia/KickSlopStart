; src/exec/misc.s — misc.resource: arbitration of the shared serial / parallel hardware bits (units 0 = serial
; data bits, 1 = serial control bits, 2 = parallel ports, 3 = parallel bits). serial.device (loaded from DEVS:)
; opens it in its init and allocates units 0 and 1: without this resource, its init fails.
; IMPLEMENTATION track ("clean"): AutoDocs misc.resource (AllocMiscResource / FreeMiscResource) +
; resources/misc.i. NO ROM reading.

                include "exec.i"

MR_UNITS        EQU 4
MR_OWNERS       EQU LIB_SIZE         ; owner name of each unit (0 = free)
MR_SIZE         EQU LIB_SIZE+MR_UNITS*4

        EVEN
misc_romtag:
        dc.w    RTC_MATCHWORD
        dc.l    misc_romtag          ; RT_MATCHTAG = self
        dc.l    misc_end             ; RT_ENDSKIP
        dc.b    RTF_COLDSTART,34,NT_RESOURCE,70  ; RT_FLAGS (COLDSTART, direct init), RT_VERSION, RT_TYPE, RT_PRI
        dc.l    misc_name            ; RT_NAME
        dc.l    misc_name            ; RT_IDSTRING
        dc.l    misc_init            ; RT_INIT
misc_name:
        dc.b    "misc.resource",0
        EVEN
misc_vectors:
        dc.l    misc_alloc           ; -6  AllocMiscResource(unit d0, name a1)
        dc.l    misc_free            ; -12 FreeMiscResource(unit d0)
        dc.l    -1

misc_init:
        lea     misc_vectors(pc),a0
        suba.l  a1,a1
        suba.l  a2,a2
        move.l  #MR_SIZE,d0
        moveq   #0,d1
        jsr     LVO_MAKELIBRARY(a6)
        tst.l   d0
        beq.s   .mi_ret
        move.l  d0,a1
        lea     misc_name(pc),a0
        move.l  a0,LN_NAME(a1)
        move.b  #NT_RESOURCE,LN_TYPE(a1)
        jsr     LVO_ADDRESOURCE(a6)
.mi_ret:
        moveq   #0,d0
        rts

; AllocMiscResource(unit d0, name a1, a6 = resource) -> d0 = 0 if the unit is granted to the caller, otherwise the
; name of the current owner. Atomic (Disable).
misc_alloc:
        movem.l d2/a2/a6,-(sp)
        lsl.l   #2,d0
        lea     MR_OWNERS(a6,d0.l),a2   ; a2 = slot of the unit
        move.l  a1,d2                   ; d2 = requester name
        move.l  ($4).w,a6
        jsr     LVO_DISABLE(a6)
        move.l  (a2),d0
        bne.s   .ma_busy
        move.l  d2,(a2)
.ma_busy:
        move.l  d0,d2
        jsr     LVO_ENABLE(a6)
        move.l  d2,d0
        movem.l (sp)+,d2/a2/a6
        rts

; FreeMiscResource(unit d0, a6 = resource): frees the unit.
misc_free:
        lsl.l   #2,d0
        clr.l   MR_OWNERS(a6,d0.l)
        rts
misc_end:
