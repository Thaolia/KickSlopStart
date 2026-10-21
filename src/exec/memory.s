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
                xdef    exec_Allocate
                xdef    exec_Deallocate
                xdef    exec_AllocAbs
                xdef    exec_AddMemList
                xdef    init_memory
                xdef    add_slow_memory

; Allocate(memHeader a0, byteSize d0) -> d0 = bloc | 0 : first-fit + découpe dans les chunks d'UN MemHeader, taille
; arrondie à 8 octets (AutoDoc : l'appelant protège le header, Forbid ou sémaphore). Clobbe d1/a0/a1.
exec_Allocate:
        movem.l d2-d3/a2-a3,-(sp)
        addq.l  #7,d0
        and.l   #-8,d0
        move.l  d0,d2                ; d2 = taille
        beq.s   .al_fail
        cmp.l   MH_FREE(a0),d2
        bhi.s   .al_fail
        move.l  a0,a2                ; a2 = header
        lea     MH_FIRST(a2),a3      ; a3 = maillon précédent
.al_scan:
        move.l  (a3),a0              ; chunk = *prev
        move.l  a0,d0
        beq.s   .al_fail             ; header épuisé
        move.l  MC_BYTES(a0),d3
        cmp.l   d2,d3
        bcs.s   .al_next             ; mc_Bytes < taille
        beq.s   .al_whole
        move.l  a0,a1                ; découpe : nouveau chunk = chunk + taille
        add.l   d2,a1
        move.l  (a0),(a1)
        sub.l   d2,d3
        move.l  d3,MC_BYTES(a1)
        move.l  a1,(a3)
        bra.s   .al_got
.al_whole:
        move.l  (a0),(a3)            ; chunk entier retiré
.al_got:
        sub.l   d2,MH_FREE(a2)
        move.l  a0,d0
        bra.s   .al_ret
.al_next:
        move.l  a0,a3
        bra.s   .al_scan
.al_fail:
        moveq   #0,d0
.al_ret:
        movem.l (sp)+,d2-d3/a2-a3
        rts

; AllocMem(size d0, flags d1) -> d0 = bloc | 0 : premier MemHeader dont les attributs couvrent les bits de TYPE
; demandés et qui peut servir la taille (Allocate) ; MEMF_CLEAR met le bloc à zéro. Sous Forbid (MemList partagée),
; sortie unique pour un seul Permit.
exec_AllocMem:
        movem.l d2-d5/a2-a4,-(sp)
        jsr     LVO_FORBID(a6)
        move.l  d1,d4                ; flags (pour MEMF_CLEAR)
        move.l  d1,d5
        and.w   #MEMF_TYPEMASK,d5    ; reqType = bits de TYPE demandés (V34)
        move.l  d0,d2                ; taille demandée
        lea     EB_MEMLIST(a6),a4
        move.l  (a4),a4              ; a4 = premier header
.am_hdr:
        move.l  (a4),d0              ; Succ
        beq.s   .am_fail             ; sentinelle : aucun header satisfaisant
        move.w  MH_ATTRIBUTES(a4),d0
        and.w   d5,d0
        cmp.w   d5,d0
        bne.s   .am_nexth            ; (MH_ATTR & reqType) != reqType
        move.l  a4,a0
        move.l  d2,d0
        bsr     exec_Allocate
        tst.l   d0
        bne.s   .am_got
.am_nexth:
        move.l  (a4),a4
        bra.s   .am_hdr
.am_got:
        btst    #16,d4               ; MEMF_CLEAR ?
        beq.s   .am_exit
        move.l  d0,a1
        move.l  d2,d1
        addq.l  #7,d1
        lsr.l   #3,d1                ; taille arrondie / 8
.am_clr:
        clr.l   (a1)+
        clr.l   (a1)+
        subq.l  #1,d1
        bne.s   .am_clr
        bra.s   .am_exit
.am_fail:
        moveq   #0,d0
.am_exit:
        jsr     LVO_PERMIT(a6)       ; Permit ne touche pas d0
        movem.l (sp)+,d2-d5/a2-a4
        rts

; Deallocate(memHeader a0, memoryBlock a1, byteSize d0) : rend le bloc à la liste de chunks triée du header, avec
; fusion avec le chunk suivant et le précédent s'ils sont contigus. Taille arrondie à 8. Clobbe d0/d1/a0/a1.
exec_Deallocate:
        move.l  a1,d1
        beq.s   .de_ret
        addq.l  #7,d0
        and.l   #-8,d0
        beq.s   .de_ret
        movem.l d2-d3/a2-a3,-(sp)
        move.l  a0,a2                ; a2 = header
        add.l   d0,MH_FREE(a2)
        lea     MH_FIRST(a2),a3      ; a3 = maillon précédent
.de_find:
        move.l  (a3),a0              ; a0 = chunk courant
        move.l  a0,d2
        beq.s   .de_ins              ; fin de liste
        cmp.l   a1,a0
        bhi.s   .de_ins              ; chunk > bloc -> insérer avant
        move.l  a0,a3
        bra.s   .de_find
.de_ins:
        move.l  a0,(a1)              ; bloc->Next = chunk courant
        move.l  d0,MC_BYTES(a1)
        move.l  a1,(a3)
        move.l  a1,d2                ; fusion avec le SUIVANT : bloc + taille == courant ?
        add.l   d0,d2
        cmp.l   a0,d2
        bne.s   .de_nonext
        move.l  (a0),(a1)
        move.l  MC_BYTES(a0),d3
        add.l   d3,MC_BYTES(a1)
.de_nonext:
        lea     MH_FIRST(a2),a0      ; fusion avec le PRÉCÉDENT (s'il existe)
        cmp.l   a0,a3
        beq.s   .de_done
        move.l  a3,d2
        add.l   MC_BYTES(a3),d2
        cmp.l   a1,d2
        bne.s   .de_done
        move.l  (a1),(a3)
        move.l  MC_BYTES(a1),d3
        add.l   d3,MC_BYTES(a3)
.de_done:
        movem.l (sp)+,d2-d3/a2-a3
.de_ret:
        rts

; FreeMem(ptr a1, size d0) : header propriétaire (MH_LOWER <= ptr < MH_UPPER) puis Deallocate, sous Forbid. Les gardes
; NULL / taille 0 sortent avant le Forbid.
exec_FreeMem:
        move.l  a1,d1
        beq.s   .fm_ret
        tst.l   d0
        beq.s   .fm_ret
        jsr     LVO_FORBID(a6)
        bsr.s   mem_owner            ; a0 = header | 0
        beq.s   .fm_done             ; aucun header propriétaire -> ignoré
        bsr     exec_Deallocate
.fm_done:
        jsr     LVO_PERMIT(a6)
.fm_ret:
        rts

; mem_owner(a1 = adresse, a6) -> a0 = MemHeader qui la contient | 0 (Z = 1 si aucun). Préserve d0/a1.
mem_owner:
        lea     EB_MEMLIST(a6),a0
        move.l  (a0),a0
.mo_hdr:
        tst.l   (a0)                 ; Succ
        beq.s   .mo_none
        cmp.l   MH_LOWER(a0),a1
        bcs.s   .mo_next
        cmp.l   MH_UPPER(a0),a1
        bcs.s   .mo_found
.mo_next:
        move.l  (a0),a0
        bra.s   .mo_hdr
.mo_none:
        sub.l   a0,a0
.mo_found:
        cmp.w   #0,a0                ; Z selon a0 (cmpa.w étend le mot : a0 = 0 <=> Z)
        rts

; AllocAbs(byteSize d0, location a1) -> d0 = bloc (location arrondie à 8 vers le bas) | 0 si la zone n'est pas
; entièrement libre dans un même chunk. Sous Forbid.
exec_AllocAbs:
        movem.l d2-d4/a2-a3,-(sp)
        jsr     LVO_FORBID(a6)
        move.l  a1,d2
        and.l   #-8,d2               ; d2 = début
        add.l   a1,d0
        sub.l   d2,d0
        addq.l  #7,d0
        and.l   #-8,d0
        move.l  d0,d3                ; d3 = taille
        beq.s   .aa_fail
        move.l  d2,a1
        bsr.s   mem_owner
        beq.s   .aa_fail
        move.l  a0,a2                ; a2 = header
        lea     MH_FIRST(a2),a3      ; a3 = maillon précédent
.aa_scan:
        move.l  (a3),a0
        move.l  a0,d0
        beq.s   .aa_fail
        cmp.l   d2,d0
        bhi.s   .aa_fail             ; chunks triés : le début n'est dans aucun chunk libre
        add.l   MC_BYTES(a0),d0      ; d0 = fin du chunk
        move.l  d2,d4
        add.l   d3,d4                ; d4 = fin demandée
        cmp.l   d4,d0
        bcc.s   .aa_found
        move.l  a0,a3
        bra.s   .aa_scan
.aa_found:
        sub.l   d4,d0                ; d0 = reste après la zone
        beq.s   .aa_nosuf
        move.l  d4,a1                ; chunk de queue
        move.l  (a0),(a1)
        move.l  d0,MC_BYTES(a1)
        move.l  a1,(a0)              ; chaîné après le chunk courant
.aa_nosuf:
        move.l  d2,d0
        sub.l   a0,d0                ; d0 = partie avant la zone
        beq.s   .aa_noprefix
        move.l  d0,MC_BYTES(a0)
        bra.s   .aa_got
.aa_noprefix:
        move.l  (a0),(a3)            ; chunk courant retiré (sa queue éventuelle prend sa place)
.aa_got:
        sub.l   d3,MH_FREE(a2)
        move.l  d2,d0
        bra.s   .aa_exit
.aa_fail:
        moveq   #0,d0
.aa_exit:
        jsr     LVO_PERMIT(a6)
        movem.l (sp)+,d2-d4/a2-a3
        rts

; AddMemList(size d0, attributes d1, pri d2, base a0, name a1) : la zone devient un MemHeader (en tête de la zone)
; inséré dans la MemList par priorité ; un seul chunk libre la couvre après l'en-tête.
exec_AddMemList:
        movem.l d2-d3/a2,-(sp)
        move.l  a0,a2
        move.b  #NT_MEMORY,LN_TYPE(a2)
        move.b  d2,LN_PRI(a2)
        move.l  a1,LN_NAME(a2)
        move.w  d1,MH_ATTRIBUTES(a2)
        move.l  a2,d2
        add.l   d0,d2
        move.l  d2,MH_UPPER(a2)
        lea     MH_SIZE+7(a2),a1
        move.l  a1,d3
        and.l   #-8,d3
        move.l  d3,a1                ; a1 = premier chunk
        move.l  a1,MH_LOWER(a2)
        move.l  a1,MH_FIRST(a2)
        sub.l   d3,d2
        and.l   #-8,d2
        move.l  d2,MH_FREE(a2)
        clr.l   MC_NEXT(a1)
        move.l  d2,MC_BYTES(a1)
        jsr     LVO_FORBID(a6)
        lea     EB_MEMLIST(a6),a0
        move.l  a2,a1
        jsr     LVO_ENQUEUE(a6)
        jsr     LVO_PERMIT(a6)
        movem.l (sp)+,d2-d3/a2
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
