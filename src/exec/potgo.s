; src/exec/potgo.s — potgo.resource: sharing of the POTGO register (analogue ports / pins 5 and 9 of the joysticks).
;
; AllocPotBits grants START / DATxx bits not yet taken (an input DATxx requires that nobody else holds START:
; a foreign START would restart its counters; START requires that no input DATxx is already taken). The OUTxx
; requested together with a granted DATxx are remembered. WritePotgo writes the bits of the mask; the high byte
; is kept for subsequent writes, START is never kept (written only when explicitly requested).
; IMPLEMENTATION track ("clean"): AutoDocs potgo.resource + hardware/custom.i. NO ROM reading.

                include "exec.i"

POTGO_HW        EQU CUSTOM+$034
PG_ALLOC        EQU LIB_SIZE         ; UWORD allocated bits (START, DATxx and their OUTxx)
PG_SHADOW       EQU LIB_SIZE+2       ; UWORD kept high byte of POTGO
PG_SIZE         EQU LIB_SIZE+4
PGF_START       EQU $0001
PGM_DAT         EQU $5500            ; DATLX/DATLY/DATRX/DATRY (bits 8/10/12/14), OUTxx = next bit

        EVEN
potgo_romtag:
        dc.w    RTC_MATCHWORD
        dc.l    potgo_romtag
        dc.l    potgo_end
        dc.b    RTF_COLDSTART,34,NT_RESOURCE,100
        dc.l    potgo_name
        dc.l    potgo_name
        dc.l    potgo_init
potgo_name:
        dc.b    "potgo.resource",0
        EVEN
potgo_vectors:
        dc.l    pg_alloc             ; -6  AllocPotBits(bits d0)
        dc.l    pg_free              ; -12 FreePotBits(bits d0)
        dc.l    pg_write             ; -18 WritePotgo(word d0, mask d1)
        dc.l    -1

potgo_init:
        lea     potgo_vectors(pc),a0
        suba.l  a1,a1
        suba.l  a2,a2
        move.l  #PG_SIZE,d0
        moveq   #0,d1
        jsr     LVO_MAKELIBRARY(a6)
        tst.l   d0
        beq.s   .pi_ret
        move.l  d0,a1
        clr.l   PG_ALLOC(a1)         ; PG_ALLOC + PG_SHADOW
        lea     potgo_name(pc),a0
        move.l  a0,LN_NAME(a1)
        move.b  #NT_RESOURCE,LN_TYPE(a1)
        jsr     LVO_ADDRESOURCE(a6)
.pi_ret:
        moveq   #0,d0
        rts

; pg_inputs: d1 = allocated bits -> d1 = DATxx allocated as inputs (matching OUTxx at 0), Z if none. Uses d0.
pg_inputs:
        move.w  d1,d0
        lsr.w   #1,d0                ; OUTxx shifted down onto the position of their DATxx
        not.w   d0
        and.w   #PGM_DAT,d0
        and.w   d0,d1
        rts

; AllocPotBits(bits d0) -> d0 = granted START/DATxx bits. Atomic (Disable).
pg_alloc:
        movem.l d2-d4/a6,-(sp)
        move.w  d0,d2                ; d2 = request
        move.l  a6,a0
        move.l  ($4).w,a6
        jsr     LVO_DISABLE(a6)
        move.w  PG_ALLOC(a0),d3      ; d3 = already allocated
        moveq   #0,d4                ; d4 = granted (DATxx + OUTxx + START)
        moveq   #3,d1
        move.w  #$0100,d0            ; d0 = current DATxx
.pa_dat:
        move.w  d0,-(sp)
        and.w   d2,d0
        beq.s   .pa_next             ; not requested
        and.w   d3,d0
        bne.s   .pa_next             ; already taken
        move.w  (sp),d0
        add.w   d0,d0                ; OUTxx
        and.w   d2,d0
        bne.s   .pa_grant            ; output: foreign START has no effect
        btst    #0,d3
        bne.s   .pa_next             ; input while someone else holds START
.pa_grant:
        or.w    (sp),d4
        or.w    d0,d4                ; OUTxx requested with the DATxx
.pa_next:
        move.w  (sp)+,d0
        lsl.w   #2,d0
        dbra    d1,.pa_dat
        btst    #0,d2
        beq.s   .pa_done
        btst    #0,d3
        bne.s   .pa_done             ; START already taken
        move.w  d3,d1
        bsr.s   pg_inputs
        bne.s   .pa_done             ; input DATxx are already taken
        or.w    #PGF_START,d4
.pa_done:
        or.w    d4,PG_ALLOC(a0)
        jsr     LVO_ENABLE(a6)
        move.w  d4,d0
        and.l   #PGM_DAT|PGF_START,d0
        movem.l (sp)+,d2-d4/a6
        rts

; FreePotBits(bits d0): frees the given START/DATxx and the associated OUTxx.
pg_free:
        and.w   #PGM_DAT|PGF_START,d0
        move.w  d0,d1
        and.w   #PGM_DAT,d1
        add.w   d1,d1
        or.w    d1,d0                ; + OUTxx of the freed DATxx
        not.w   d0
        and.w   d0,PG_ALLOC(a6)      ; memory and.w: indivisible on 68000
        rts

; WritePotgo(word d0, mask d1).
pg_write:
        movem.l d2/a6,-(sp)
        move.l  a6,a0
        move.l  ($4).w,a6
        jsr     LVO_DISABLE(a6)
        move.w  d1,d2
        and.w   #$FF00,d2
        not.w   d2
        and.w   PG_SHADOW(a0),d2     ; high byte kept outside the mask
        and.w   d0,d1                ; requested bits
        move.w  d1,d0
        and.w   #$FF00,d0
        or.w    d0,d2
        move.w  d2,PG_SHADOW(a0)
        and.w   #PGF_START,d1
        or.w    d1,d2                ; START only if it is written now
        move.w  d2,POTGO_HW
        jsr     LVO_ENABLE(a6)
        movem.l (sp)+,d2/a6
        rts
potgo_end:
