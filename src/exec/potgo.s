; src/exec/potgo.s — potgo.resource: sharing of the POTGO register (analogue ports / pins 5 and 9 of the joysticks).
;
; AllocPotBits grants START / DATxx / OUTxx bits not yet taken (an input DATxx requires that nobody else holds
; START: a foreign START would restart its counters; START requires that no input DATxx is already taken).
; WritePotgo writes the bits of the mask; the high byte is kept for subsequent writes, START is never kept.
; IMPLEMENTATION track ("clean"): AutoDocs potgo.resource + hardware/custom.i + docs/analysis/resources-v34.md §3.
; NO ROM reading.

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
        move.b  #(1<<LIBB_SUMUSED)|(1<<LIBB_CHANGED),LIB_FLAGS(a1)
        lea     potgo_name(pc),a0
        move.l  a0,LN_NAME(a1)
        move.b  #NT_RESOURCE,LN_TYPE(a1)
        jsr     LVO_ADDRESOURCE(a6)
.pi_ret:
        moveq   #0,d0
        rts

; AllocPotBits(bits d0) -> d0 = granted bits (subset of the request). Atomic (Disable). Rules (resources-v34 §3.2):
; bits already taken are refused, and so is the OUTxx of a taken DATxx; START is refused while a DATxx is held as an
; input (without its OUTxx); while START is held by someone, only complete OUTxx+DATxx pairs are granted.
pg_alloc:
        movem.l d2-d3/a6,-(sp)
        move.w  d0,d2                ; d2 = request
        move.l  a6,a0
        move.l  ($4).w,a6
        jsr     LVO_DISABLE(a6)
        move.w  PG_ALLOC(a0),d3      ; d3 = already allocated
        move.w  d3,d1
        and.w   #PGM_DAT,d1
        add.w   d1,d1                ; OUTxx of the taken DATxx
        or.w    d3,d1
        not.w   d1
        and.w   d1,d2
        btst    #0,d2
        beq.s   .pa_pairs
        move.w  d3,d1
        lsr.w   #1,d1                ; OUTxx moved onto their DATxx
        not.w   d1
        and.w   d3,d1
        and.w   #PGM_DAT,d1          ; DATxx taken as inputs
        beq.s   .pa_pairs
        bclr    #0,d2
.pa_pairs:
        btst    #0,d3
        beq.s   .pa_done
        move.w  d2,d1                ; START held: complete pairs only
        lsr.w   #1,d1
        and.w   d2,d1
        and.w   #PGM_DAT,d1
        move.w  d1,d0
        add.w   d0,d0
        or.w    d0,d1
        and.w   #$00FF,d2
        or.w    d1,d2
.pa_done:
        and.w   #$FF01,d2
        or.w    d2,PG_ALLOC(a0)
        jsr     LVO_ENABLE(a6)
        moveq   #0,d0
        move.w  d2,d0
        movem.l (sp)+,d2-d3/a6
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

; WritePotgo(word d0, mask d1): POTGO = (shadow & ~mask) | (word & mask); only the high byte is kept afterwards
; (START and the low bits are one-shot). Called every frame by the gameport VBlank server: inline DISABLE/ENABLE
; (exec/ables.i) instead of the LVOs, whose Enable may reschedule — not allowed from an interrupt.
pg_write:
        move.l  a6,a0
        move.l  ($4).w,a1
        move.w  #INTF_INTEN,INTENA
        addq.b  #1,EB_IDNEST(a1)
        and.w   d1,d0
        not.w   d1
        and.w   PG_SHADOW(a0),d1
        or.w    d1,d0
        move.w  d0,POTGO_HW
        clr.b   d0
        move.w  d0,PG_SHADOW(a0)
        subq.b  #1,EB_IDNEST(a1)
        bge.s   .pw_ret
        move.w  #INTF_SETCLR|INTF_INTEN,INTENA
.pw_ret:
        rts
potgo_end:
