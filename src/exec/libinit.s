; src/exec/libinit.s — exec.library : création de bibliothèques/devices (M5a, AUTOINIT).
;   MakeFunctions : construit une jump table (JMP absolus) sous une base, depuis un tableau
;                   de vecteurs (absolus longword, ou relatifs word si 1er mot = -1).
;   MakeLibrary   : alloue (negSize jump table + dataSize data), bâtit la jump table,
;                   InitStruct la data table, appelle l'init function ; rend la base.
;   InitStruct    : interprète un flux de commandes « ddssnnnn » (format exec/InitStruct).
; Utilisés par le chemin AUTOINIT de InitResident (resident.s) pour créer les devices/libs
; résidents (RTF_AUTOINIT) à partir de leur table de 4 longs {dataSize, funcTab, dataTab, init}.
; Convention Amiga : scratch = d0/d1/a0/a1 ; a6 = library base.
; Piste IMPLÉMENTATION (« clean ») : AutoDocs exec MakeLibrary/MakeFunctions/InitStruct
; + exec/initializers.i (ABI publique). AUCUNE lecture de la ROM.

                include "exec.i"

                xdef    exec_MakeLibrary
                xdef    exec_MakeFunctions
                xdef    exec_InitStruct

; MakeFunctions(target a0, funcArray a1, funcDispBase a2) -> d0 = taille (octets).
; Pose les entrées [JMP $4EF9][adresse long] (6 o) sous `target`, vers le bas (LVO -6, -12…).
; funcArray : 1er mot = -1 -> déplacements WORD relatifs à funcDispBase, terminés par word -1 ;
; sinon pointeurs LONG absolus, terminés par long -1.
exec_MakeFunctions:
                movem.l d2/a3-a4,-(sp)
                move.l  a0,d2               ; d2 = target d'origine (pour la taille)
                move.l  a0,a3               ; a3 = curseur de table (décroît)
                move.l  a1,a4               ; a4 = curseur funcArray
                cmp.w   #-1,(a4)
                bne.s   .mf_abs
                addq.l  #2,a4               ; relatif : saute le marqueur -1
.mf_rel:
                move.w  (a4)+,d0
                cmp.w   #-1,d0
                beq.s   .mf_end
                ext.l   d0
                move.l  a2,a0
                add.l   d0,a0               ; adresse = funcDispBase + offset(word)
                subq.l  #6,a3
                move.w  #$4EF9,(a3)
                move.l  a0,2(a3)
                bra.s   .mf_rel
.mf_abs:
                move.l  (a4)+,d0
                cmp.l   #-1,d0
                beq.s   .mf_end
                move.l  d0,a0               ; adresse absolue
                subq.l  #6,a3
                move.w  #$4EF9,(a3)
                move.l  a0,2(a3)
                bra.s   .mf_abs
.mf_end:
                move.l  d2,d0
                sub.l   a3,d0               ; taille = target - curseur
                movem.l (sp)+,d2/a3-a4
                rts

; MakeLibrary(vectors a0, structure a1, init a2, dataSize d0, segList d1) -> d0 = base | 0.
; Alloue negSize (jump table) + dataSize (MEMF_CLEAR), la base = alloc + negSize. Bâtit la
; jump table, pose LIB_NEGSIZE/LIB_POSSIZE, InitStruct la data table (si != NULL), appelle
; l'init (si != NULL) avec D0=base, A0=segList, A6=ExecBase (sa valeur de retour devient la
; base). Ne remplit PAS name/type/version depuis le ROMTag (quirk V34 : le module le fait).
exec_MakeLibrary:
                movem.l d2-d5/a3-a5,-(sp)
                move.l  a0,a3               ; a3 = vectors
                move.l  a1,a4               ; a4 = structure (data table InitStruct)
                move.l  a2,a5               ; a5 = init function
                move.l  d0,d2               ; d2 = dataSize
                move.l  d1,d3               ; d3 = segList
                move.l  a3,a0               ; compter les vecteurs -> negSize
                bsr.s   count_vectors       ; -> d0 = nombre de vecteurs
                mulu    #6,d0               ; negSize = nombre * 6
                move.l  d0,d4               ; d4 = negSize
                add.l   d2,d0               ; total = negSize + dataSize
                move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
                jsr     LVO_ALLOCMEM(a6)
                tst.l   d0
                beq.s   .ml_fail
                add.l   d4,d0               ; d0 = base = alloc + negSize
                move.l  d0,d5               ; d5 = base (conservée)
                move.l  d0,a0               ; MakeFunctions(target=base, vectors, dispBase=vectors)
                move.l  a3,a1
                move.l  a3,a2
                jsr     LVO_MAKEFUNCTIONS(a6)
                move.l  d5,a2               ; a2 = base
                move.w  d4,LIB_NEGSIZE(a2)
                move.w  d2,LIB_POSSIZE(a2)
                move.l  a4,d0               ; data table présente ?
                beq.s   .ml_noinitstruct
                move.l  a4,a1               ; InitStruct(initTable=structure, memory=base, size=dataSize)
                move.l  d5,a2
                move.l  d2,d0
                jsr     LVO_INITSTRUCT(a6)
.ml_noinitstruct:
                move.l  a5,d0               ; init function présente ?
                beq.s   .ml_done
                move.l  d5,d0               ; D0 = base
                move.l  d3,a0               ; A0 = segList
                move.l  a5,a1
                jsr     (a1)                ; init(D0=base, A0=segList, A6=ExecBase) -> D0 = base'
                move.l  d0,d5               ; la valeur de retour devient la base
.ml_done:
                move.l  d5,d0               ; -> base
                movem.l (sp)+,d2-d5/a3-a5
                rts
.ml_fail:
                moveq   #0,d0
                movem.l (sp)+,d2-d5/a3-a5
                rts

; count_vectors(a0 = funcArray) -> d0 = nombre de vecteurs (hors marqueur/terminateur).
count_vectors:
                move.l  a0,a1
                moveq   #0,d0
                cmp.w   #-1,(a1)
                bne.s   .cv_abs
                addq.l  #2,a1               ; relatif : saute le marqueur -1
.cv_rel:
                cmp.w   #-1,(a1)
                beq.s   .cv_done
                addq.l  #2,a1
                addq.l  #1,d0
                bra.s   .cv_rel
.cv_abs:
                cmp.l   #-1,(a1)
                beq.s   .cv_done
                addq.l  #4,a1
                addq.l  #1,d0
                bra.s   .cv_abs
.cv_done:
                rts

; InitStruct(initTable a1, memory a2, size d0) : initialise les champs de `memory` depuis un
; flux de commandes « ddssnnnn ». Implémente le chemin des macros INITBYTE/INITWORD/INITLONG
; (dd=11 : offset 24 bits ; ss = taille long/word/byte ; nnnn=0 : item unique) + terminateur
; 00 + ré-alignement word après un byte. Les variantes count/repeat (dd=00/01) et offset court
; (dd=10) ne sont PAS gérées ce milestone (nos tables n'utilisent que INITBYTE/WORD/LONG).
exec_InitStruct:
                move.l  d2,-(sp)
.is_loop:
                moveq   #0,d0
                move.b  (a1)+,d0            ; command byte ddssnnnn
                beq.s   .is_done            ; 00 -> fin du flux
                move.b  d0,d1
                and.b   #$C0,d1
                cmp.b   #$C0,d1
                bne.s   .is_done            ; dd != 11 (variante non gérée) -> arrêt défensif
                moveq   #0,d2               ; offset 24 bits (3 octets)
                move.b  (a1)+,d2
                lsl.l   #8,d2
                move.b  (a1)+,d2
                lsl.l   #8,d2
                move.b  (a1)+,d2
                move.l  a2,a0
                add.l   d2,a0               ; dest = memory + offset
                move.b  d0,d1
                and.b   #$30,d1             ; ss (bits 5-4)
                beq.s   .is_long            ; 00 = long
                cmp.b   #$10,d1
                beq.s   .is_word            ; 01 = word
                move.b  (a1)+,(a0)          ; 10 = byte
                move.l  a1,d1               ; ré-aligne le flux sur un mot après un byte
                btst    #0,d1
                beq.s   .is_loop
                addq.l  #1,a1
                bra.s   .is_loop
.is_word:
                move.w  (a1)+,(a0)
                bra.s   .is_loop
.is_long:
                move.l  (a1)+,(a0)
                bra.s   .is_loop
.is_done:
                move.l  (sp)+,d2
                rts
