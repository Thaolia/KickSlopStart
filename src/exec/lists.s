; src/exec/lists.s — exec.library : primitives de listes doublement chaînées
; (newlist, AddHead, AddTail, Remove, FindName). Convention Amiga : scratch =
; d0/d1/a0/a1 ; a6 = library base.
; Piste IMPLÉMENTATION (« clean ») : docs/analysis/exec-spec.md + ABI publique.

                include "exec.i"

                xdef    newlist
                xdef    exec_AddHead
                xdef    exec_AddTail
                xdef    exec_Insert
                xdef    exec_Remove
                xdef    exec_RemHead
                xdef    exec_RemTail
                xdef    exec_Enqueue
                xdef    exec_FindName

; newlist : struct List vide (a1 = &List ; conserve a6 ; clobbers a0)
newlist:
        move.l  a1,a0
        addq.l  #LH_TAIL,a0
        move.l  a0,(a1)
        clr.l   LH_TAIL(a1)
        move.l  a1,8(a1)
        rts

; AddHead(list a0, node a1)
exec_AddHead:
        move.l  (a0),d0              ; old lh_Head
        move.l  d0,(a1)              ; node.Succ = old head
        move.l  a0,LN_PRED(a1)       ; node.Pred = &lh_Head (= list)
        move.l  a1,(a0)              ; lh_Head = node
        move.l  d0,a0                ; a0 = old head
        move.l  a1,LN_PRED(a0)       ; old_head.Pred = node
        rts

; AddTail(list a0, node a1)
exec_AddTail:
        move.l  8(a0),d1             ; old lh_TailPred
        move.l  a0,d0
        addq.l  #LH_TAIL,d0          ; d0 = &lh_Tail
        move.l  d0,(a1)              ; node.Succ = &lh_Tail
        move.l  d1,LN_PRED(a1)       ; node.Pred = old TailPred
        move.l  a1,8(a0)             ; lh_TailPred = node
        move.l  d1,a0                ; a0 = old TailPred
        move.l  a1,(a0)              ; old_TailPred.Succ = node
        rts

; Insert(list a0, node a1, pred a2) : insère node APRÈS pred ; pred NULL -> AddHead
exec_Insert:
        move.l  a2,d0
        beq.s   exec_AddHead         ; pred NULL -> tête
        move.l  (a2),d0              ; succ = pred->Succ
        move.l  d0,(a1)              ; node->Succ = succ
        move.l  a2,LN_PRED(a1)       ; node->Pred = pred
        move.l  a1,(a2)              ; pred->Succ = node
        move.l  d0,a0                ; a0 = succ
        move.l  a1,LN_PRED(a0)       ; succ->Pred = node
        rts

; Remove(node a1)
exec_Remove:
        move.l  (a1),d0              ; Succ
        move.l  LN_PRED(a1),a0       ; Pred
        move.l  d0,(a0)              ; Pred.Succ = Succ
        move.l  d0,a0                ; a0 = Succ
        move.l  LN_PRED(a1),LN_PRED(a0) ; Succ.Pred = Pred
        rts

; RemHead(list a0) -> d0 = node retiré | 0 (liste vide)
exec_RemHead:
        move.l  (a0),a1              ; node = lh_Head
        move.l  (a1),d0              ; succ = node->Succ
        beq.s   .rh_none             ; Succ==0 -> node est la sentinelle = vide
        move.l  d0,(a0)              ; lh_Head = succ
        exg     d0,a1                ; a1 = succ, d0 = node (à retourner)
        move.l  a0,LN_PRED(a1)       ; succ->Pred = &lh_Head (= list)
        rts
.rh_none:
        moveq   #0,d0
        rts

; RemTail(list a0) -> d0 = node retiré | 0 (liste vide)
exec_RemTail:
        move.l  8(a0),a1             ; node = lh_TailPred
        move.l  LN_PRED(a1),d0       ; pred = node->Pred
        beq.s   .rt_none             ; Pred==0 -> node est la sentinelle = vide
        move.l  d0,8(a0)             ; lh_TailPred = pred
        exg     d0,a1                ; a1 = pred, d0 = node (à retourner)
        lea     LH_TAIL(a0),a0       ; a0 = &lh_Tail (= list+4)
        move.l  a0,(a1)              ; pred->Succ = &lh_Tail
        rts
.rt_none:
        moveq   #0,d0
        rts

; Enqueue(list a0, node a1) : insertion triée par LN_PRI décroissant (FIFO à pri égale)
exec_Enqueue:
        move.b  LN_PRI(a1),d1        ; d1.b = priorité du nouveau noeud (signée)
        move.l  (a0),a0              ; a0 = cur = lh_Head (1er noeud ou sentinelle)
.eq_loop:
        move.l  (a0),d0              ; cur->Succ
        beq.s   .eq_insert           ; cur = sentinelle tail -> insérer avant
        move.b  LN_PRI(a0),d0        ; priorité de cur
        cmp.b   d1,d0                ; cur - new (signé)
        blt.s   .eq_insert           ; cur->pri < new->pri -> insérer avant cur
        move.l  (a0),a0              ; cur = cur->Succ
        bra.s   .eq_loop
.eq_insert:
        move.l  LN_PRED(a0),d0       ; P = cur->Pred
        move.l  d0,LN_PRED(a1)       ; new->Pred = P
        move.l  a0,(a1)              ; new->Succ = cur
        move.l  a1,LN_PRED(a0)       ; cur->Pred = new
        move.l  d0,a0                ; a0 = P
        move.l  a1,(a0)              ; P->Succ = new
        rts

; FindName(list a0, name a1) -> d0 = node | 0
exec_FindName:
        move.l  (a0),a0              ; node = lh_Head
.fn_loop:
        move.l  (a0),d0              ; node->Succ
        beq.s   .fn_none             ; atteint le sentinel (Succ==0)
        move.l  LN_NAME(a0),d1
        beq.s   .fn_next             ; pas de nom
        movem.l d2/a0/a1,-(sp)
        move.l  d1,a0                ; nom du nœud
.fn_cmp:
        move.b  (a0)+,d0
        move.b  (a1)+,d2
        cmp.b   d0,d2
        bne.s   .fn_nomatch
        tst.b   d0
        bne.s   .fn_cmp
        movem.l (sp)+,d2/a0/a1
        move.l  a0,d0                ; match -> retourne le nœud
        rts
.fn_nomatch:
        movem.l (sp)+,d2/a0/a1
.fn_next:
        move.l  (a0),a0              ; node = node->Succ
        bra.s   .fn_loop
.fn_none:
        moveq   #0,d0
        rts
