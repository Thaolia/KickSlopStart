; src/exec/memory.s — exec.library : allocateur mémoire multi-MemHeader.
;   AllocMem : parcourt la MemList, sélectionne le 1er header satisfaisant les
;              bits de TYPE demandés, puis first-fit + split sur ce header.
;   FreeMem  : retrouve le header propriétaire (par plage d'adresse) puis
;              coalescing bilatéral (corps IDENTIQUE à M2.2, vérifié).
;   AvailMem : somme le libre des headers compatibles (ou plus grand bloc).
;   TypeOfMem: attributs du header contenant une adresse (0 si aucun).
;   init_memory : MemHeader chip unique @ MH_CHIP.
; Convention Amiga : scratch = d0/d1/a0/a1 ; a6 = library base.
; Piste IMPLÉMENTATION (« clean ») : docs/analysis/exec-spec.md + ABI publique.

                include "exec.i"

                xdef    exec_AllocMem
                xdef    exec_FreeMem
                xdef    exec_AvailMem
                xdef    exec_TypeOfMem
                xdef    init_memory
                xdef    add_slow_memory

; AllocMem(size d0, flags d1) -> d0 = bloc | 0  (multi-header, first-fit + split)
; M3c : enveloppé en Forbid/Permit — la MemList + les listes de chunks sont
; partagées entre tâches ; une préemption mid-split corromprait le tas. Section à
; SORTIE UNIQUE (.am_exit) : chaque chemin (succès, échec taille, header épuisé)
; passe par le même Permit, sinon EB_TDNEST dériverait et figerait le scheduler.
exec_AllocMem:
        movem.l d2-d5/a2-a4,-(sp)
        jsr     LVO_FORBID(a6)
        move.l  d1,d4                ; flags (pour MEMF_CLEAR)
        move.l  d1,d5
        and.w   #MEMF_TYPEMASK,d5    ; reqType = bits de TYPE demandés (V34)
        addq.l  #7,d0
        and.l   #-8,d0               ; arrondi 8 octets
        move.l  d0,d2                ; size
        beq     .am_fail
        lea     EB_MEMLIST(a6),a4
        move.l  (a4),a4              ; a4 = premier noeud (lh_Head)
.am_hdr:
        move.l  (a4),d0              ; a4->Succ
        beq     .am_fail             ; sentinelle tail -> aucun header satisfaisant
        move.w  MH_ATTRIBUTES(a4),d0
        and.w   d5,d0
        cmp.w   d5,d0
        bne     .am_nexth            ; (MH_ATTR & reqType) != reqType
        move.l  a4,a2                ; a2 = header candidat
        lea     MH_FIRST(a2),a3      ; a3 = &mh_First (maillon précédent)
.am_scan:
        move.l  (a3),a0              ; chunk = *prev
        move.l  a0,d0
        beq     .am_nexth            ; header épuisé -> header suivant
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
        bra.s   .am_exit
.am_next:
        move.l  a0,a3                ; prev = &chunk->mc_Next
        bra     .am_scan
.am_nexth:
        move.l  (a4),a4              ; header = header->Succ
        bra     .am_hdr
.am_fail:
        moveq   #0,d0
.am_exit:
        jsr     LVO_PERMIT(a6)       ; sortie unique ; Permit ne touche pas d0
        movem.l (sp)+,d2-d5/a2-a4
        rts

; FreeMem(ptr a1, size d0) -- header propriétaire + coalescing bilatéral (M2.2)
; M3c : FreeMem enveloppé en Forbid/Permit (coalescing mute la liste de chunks
; partagée). Les gardes NULL/size-0 sortent AVANT le Forbid (aucune section
; critique) ; le corps a une sortie unique (.fm_done) -> un seul Permit.
exec_FreeMem:
        move.l  a1,d1
        beq.w   .fm_ret              ; ptr NULL
        tst.l   d0
        beq.w   .fm_ret              ; size 0
        movem.l d2-d3/a2-a3,-(sp)
        jsr     LVO_FORBID(a6)
        addq.l  #7,d0
        and.l   #-8,d0               ; d0 = taille arrondie
        ; recherche du header propriétaire : MH_LOWER <= ptr < MH_UPPER
        lea     EB_MEMLIST(a6),a2
        move.l  (a2),a2              ; premier noeud
.fm_hdr:
        move.l  (a2),d2              ; Succ
        beq     .fm_done             ; aucun header propriétaire -> ignore
        cmp.l   MH_LOWER(a2),a1
        bcs.s   .fm_nexth            ; ptr < MH_LOWER
        cmp.l   MH_UPPER(a2),a1
        bcc.s   .fm_nexth            ; ptr >= MH_UPPER
        bra.s   .fm_found
.fm_nexth:
        move.l  (a2),a2
        bra.s   .fm_hdr
.fm_found:
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
        jsr     LVO_PERMIT(a6)
        movem.l (sp)+,d2-d3/a2-a3
.fm_ret:
        rts

; AvailMem(requirements d1) -> d0 = octets libres compatibles (ou plus grand bloc)
exec_AvailMem:
        movem.l d2-d4,-(sp)
        jsr     LVO_FORBID(a6)       ; M3c : lecture cohérente des chunks partagés
        move.l  d1,d2                ; requirements
        move.l  d1,d3
        and.w   #MEMF_TYPEMASK,d3    ; reqType
        moveq   #0,d4                ; accumulateur
        lea     EB_MEMLIST(a6),a0
        move.l  (a0),a0              ; premier noeud
.av_hdr:
        move.l  (a0),d0              ; Succ
        beq.s   .av_done
        move.w  MH_ATTRIBUTES(a0),d0
        and.w   d3,d0
        cmp.w   d3,d0
        bne.s   .av_nexth            ; header non compatible
        btst    #17,d2               ; MEMF_LARGEST ($20000) ?
        bne.s   .av_largest
        add.l   MH_FREE(a0),d4       ; somme du libre
        bra.s   .av_nexth
.av_largest:
        move.l  MH_FIRST(a0),a1      ; parcourt les chunks -> max MC_BYTES
.av_lchunk:
        move.l  a1,d0
        beq.s   .av_nexth
        move.l  MC_BYTES(a1),d0
        cmp.l   d4,d0
        bls.s   .av_lnext
        move.l  d0,d4
.av_lnext:
        move.l  (a1),a1
        bra.s   .av_lchunk
.av_nexth:
        move.l  (a0),a0
        bra.s   .av_hdr
.av_done:
        jsr     LVO_PERMIT(a6)       ; sortie unique ; Permit ne touche pas d4
        move.l  d4,d0
        movem.l (sp)+,d2-d4
        rts

; TypeOfMem(address a1) -> d0 = attributs du header contenant l'adresse | 0
; M3c : Forbid/Permit (parcourt la MemList partagée). Sortie unique .tom_done.
exec_TypeOfMem:
        jsr     LVO_FORBID(a6)
        lea     EB_MEMLIST(a6),a0
        move.l  (a0),a0              ; premier noeud
.tom_hdr:
        move.l  (a0),d0              ; Succ
        beq.s   .tom_none
        cmp.l   MH_LOWER(a0),a1
        bcs.s   .tom_nexth           ; a1 < MH_LOWER
        cmp.l   MH_UPPER(a0),a1
        bcc.s   .tom_nexth           ; a1 >= MH_UPPER
        moveq   #0,d0
        move.w  MH_ATTRIBUTES(a0),d0 ; trouvé -> attributs
        bra.s   .tom_done
.tom_nexth:
        move.l  (a0),a0
        bra.s   .tom_hdr
.tom_none:
        moveq   #0,d0
.tom_done:
        jsr     LVO_PERMIT(a6)       ; préserve d0
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

; add_slow_memory : détecte la RAM « slow » A500 (trapdoor, $C00000..) et l'ajoute EN TÊTE de la MemList
; (MEMF_FAST|MEMF_PUBLIC) -> les allocations sans MEMF_CHIP y vont d'abord ; la chip reste au DMA. Un jeu qui
; demande ~400 Ko de CHIP (Lemmings) ne tient qu'à cette condition sur une config 512K chip + 512K slow.
; Sans slow RAM, la zone peut refléter les registres custom ($DFF000, décodage partiel) : chaque sonde est à
; l'offset $1FE/$3FE d'un bloc (= registre NO-OP si miroir -> écriture inoffensive). Deux motifs croisés écrits
; sur DEUX adresses avant relecture : un bus flottant qui retient la dernière valeur écrite ne passe pas.
; Blocs suivants : refus si alias du bloc 0 (décodage incomplet). a6 = SysBase. Appelé après le selftest
; mémoire (qui suppose la chip en tête de liste). Renvoie d0 = octets de slow RAM détectés (0 = aucune).
SLOW_BASE       EQU $00C00000
SLOW_STEP       EQU $00080000        ; granularité 512 Ko
SLOW_MAXBLK     EQU 3                ; jusqu'à 1,5 Mo ($C00000-$D7FFFF)
add_slow_memory:
        movem.l d2-d4/a2-a3,-(sp)
        moveq   #0,d2                ; d2 = taille détectée
.as_blk:
        cmp.l   #(SLOW_MAXBLK*SLOW_STEP),d2
        beq.s   .as_add
        lea     SLOW_BASE,a2
        add.l   d2,a2                ; a2 = bloc candidat
        move.w  #$5A3C,$1FE(a2)
        move.w  #$A5C3,$3FE(a2)
        cmp.w   #$5A3C,$1FE(a2)
        bne.s   .as_add
        move.w  #$A5C3,$1FE(a2)
        move.w  #$5A3C,$3FE(a2)
        cmp.w   #$A5C3,$1FE(a2)
        bne.s   .as_add
        tst.l   d2                   ; bloc 0 : pas d'alias possible
        beq.s   .as_ok
        lea     SLOW_BASE,a3
        move.w  #$1234,$1FE(a3)      ; marque le bloc 0...
        move.w  #$4321,$1FE(a2)      ; ...écrit le bloc courant...
        cmp.w   #$1234,$1FE(a3)      ; ...le bloc 0 a-t-il changé ? -> alias
        bne.s   .as_add
.as_ok:
        add.l   #SLOW_STEP,d2
        bra.s   .as_blk
.as_add:
        move.l  d2,d4                ; d4 = taille détectée (valeur de retour)
        beq.s   .as_ret              ; pas de slow RAM : rien à faire
        lea     SLOW_BASE,a0         ; MemHeader au début de la zone, 1er chunk juste après
        moveq   #(MH_SIZE/4)-1,d0
        move.l  a0,a1
.as_z:
        clr.l   (a1)+
        dbf     d0,.as_z
        move.b  #NT_MEMORY,LN_TYPE(a0)
        move.l  #slow_name,LN_NAME(a0)
        move.w  #(MEMF_FAST|MEMF_PUBLIC),MH_ATTRIBUTES(a0)
        lea     MH_SIZE(a0),a1       ; a1 = 1er chunk
        move.l  a1,MH_LOWER(a0)
        move.l  a1,MH_FIRST(a0)
        move.l  d2,d3
        add.l   a0,d3
        move.l  d3,MH_UPPER(a0)
        sub.l   #MH_SIZE,d2          ; d2 = octets libres
        move.l  d2,MH_FREE(a0)
        clr.l   MC_NEXT(a1)
        move.l  d2,MC_BYTES(a1)
        move.l  a0,a1                ; AddHead(MemList, header)
        lea     EB_MEMLIST(a6),a0
        jsr     LVO_ADDHEAD(a6)
.as_ret:
        move.l  d4,d0
        movem.l (sp)+,d2-d4/a2-a3
        rts

slow_name:
        dc.b    "slow memory",0
        EVEN

mh_name:
        dc.b    "chip memory",0
        EVEN
