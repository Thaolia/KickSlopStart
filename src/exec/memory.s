; src/exec/memory.s — exec.library : allocateur mémoire (AllocMem first-fit +
; split + MEMF_CLEAR ; FreeMem avec coalescing bilatéral) + init_memory
; (MemHeader chip unique). Un seul MemHeader en V34 courant ; le parcours
; multi-MemHeader viendra. Convention Amiga : scratch = d0/d1/a0/a1 ; a6 = base.
; Piste IMPLÉMENTATION (« clean ») : docs/analysis/exec-spec.md + ABI publique.

                include "exec.i"

                xdef    exec_AllocMem
                xdef    exec_FreeMem
                xdef    init_memory

; AllocMem(size d0, flags d1) -> d0 = bloc | 0  (first-fit + split, MEMF_CLEAR)
; Un seul MemHeader (chip, MH_CHIP) ; parcours de MemList -> ultérieur.
exec_AllocMem:
        movem.l d2-d4/a2-a3,-(sp)
        move.l  d1,d4                ; flags
        addq.l  #7,d0
        and.l   #-8,d0               ; arrondi 8 octets
        move.l  d0,d2                ; size
        beq     .am_fail
        lea     MH_CHIP,a2
        lea     MH_FIRST(a2),a3      ; a3 = &mh_First (maillon précédent)
.am_scan:
        move.l  (a3),a0              ; chunk = *prev
        move.l  a0,d0
        beq     .am_fail             ; fin de liste -> pas de place
        move.l  MC_BYTES(a0),d3
        cmp.l   d2,d3
        bcs.s   .am_next             ; mc_Bytes < size
        beq.s   .am_whole
        move.l  a0,a1                ; split : nouveau chunk = chunk + size
        add.l   d2,a1
        move.l  (a0),(a1)            ; new->Next = chunk->Next
        sub.l   d2,d3
        move.l  d3,MC_BYTES(a1)      ; new->Bytes = reste
        move.l  a1,(a3)              ; *prev = new
        bra.s   .am_alloc
.am_whole:
        move.l  (a0),(a3)            ; retire le chunk entier
.am_alloc:
        sub.l   d2,MH_FREE(a2)
        move.l  d4,d0
        and.l   #MEMF_CLEAR,d0
        beq.s   .am_ok
        move.l  a0,a1                ; MEMF_CLEAR : met le bloc à zéro
        move.l  d2,d0
        lsr.l   #2,d0
.am_clr:
        clr.l   (a1)+
        subq.l  #1,d0
        bne.s   .am_clr
.am_ok:
        move.l  a0,d0                ; résultat
        movem.l (sp)+,d2-d4/a2-a3
        rts
.am_next:
        move.l  a0,a3                ; prev = &chunk->mc_Next
        bra     .am_scan
.am_fail:
        moveq   #0,d0
        movem.l (sp)+,d2-d4/a2-a3
        rts

; FreeMem(ptr a1, size d0) -- insertion en ordre d'adresse + coalescing bilatéral
exec_FreeMem:
        move.l  a1,d1
        beq.w   .fm_ret              ; ptr NULL
        tst.l   d0
        beq.w   .fm_ret              ; size 0
        movem.l d2-d3/a2-a3,-(sp)
        addq.l  #7,d0
        and.l   #-8,d0               ; d0 = taille arrondie
        lea     MH_CHIP,a2
        add.l   d0,MH_FREE(a2)       ; mh_Free += size
        lea     MH_FIRST(a2),a3      ; a3 = maillon précédent (&mh_First au départ)
.fm_find:
        move.l  (a3),a0              ; a0 = chunk courant
        move.l  a0,d2
        beq.s   .fm_ins              ; fin de liste
        cmp.l   a1,a0
        bhi.s   .fm_ins              ; chunk > ptr -> insérer avant
        move.l  a0,a3                ; prev = &chunk->mc_Next
        bra.s   .fm_find
.fm_ins:
        move.l  a0,(a1)              ; new->Next = chunk courant
        move.l  d0,MC_BYTES(a1)
        move.l  a1,(a3)              ; *prev = new
        ; coalescing avec le SUIVANT : (new + size) == courant ?
        move.l  a1,d2
        add.l   d0,d2
        cmp.l   a0,d2
        bne.s   .fm_noNext
        move.l  (a0),(a1)            ; new->Next = courant->Next
        move.l  MC_BYTES(a0),d3
        add.l   d3,MC_BYTES(a1)      ; new->Bytes += courant->Bytes
.fm_noNext:
        ; coalescing avec le PRÉCÉDENT (si a3 n'est pas la sentinelle mh_First)
        lea     MH_FIRST(a2),a0
        cmp.l   a0,a3
        beq.s   .fm_done
        move.l  a3,a0                ; a0 = prevchunk (a3 = &prevchunk->mc_Next)
        move.l  a0,d2
        add.l   MC_BYTES(a0),d2      ; d2 = fin du prevchunk
        cmp.l   a1,d2
        bne.s   .fm_done
        move.l  (a1),(a0)            ; prev->Next = new->Next
        move.l  MC_BYTES(a1),d3
        add.l   d3,MC_BYTES(a0)      ; prev->Bytes += new->Bytes
.fm_done:
        movem.l (sp)+,d2-d3/a2-a3
.fm_ret:
        rts

; init_memory : MemHeader chip @ MH_CHIP + chunk initial couvrant le tas
init_memory:                         ; a6 = SysBase (jump table déjà bâtie)
        lea     MH_CHIP,a0
        moveq   #7,d0                ; 32 octets à zéro
        move.l  a0,a1
.im_z:
        clr.l   (a1)+
        dbf     d0,.im_z
        move.b  #NT_MEMORY,LN_TYPE(a0)
        move.l  #mh_name,LN_NAME(a0)
        move.w  #(MEMF_CHIP|MEMF_PUBLIC),MH_ATTRIBUTES(a0)
        move.l  #HEAP_LOWER,MH_LOWER(a0)
        move.l  #HEAP_UPPER,MH_UPPER(a0)
        move.l  #(HEAP_UPPER-HEAP_LOWER),MH_FREE(a0)
        move.l  #HEAP_LOWER,a1       ; chunk initial = tout le tas
        clr.l   MC_NEXT(a1)
        move.l  #(HEAP_UPPER-HEAP_LOWER),MC_BYTES(a1)
        move.l  a1,MH_FIRST(a0)
        lea     EB_MEMLIST(a6),a0    ; AddTail(MemList, MemHeader)
        lea     MH_CHIP,a1
        jsr     LVO_ADDTAIL(a6)
        rts

mh_name:
        dc.b    "chip memory",0
        EVEN
