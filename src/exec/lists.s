; src/exec/lists.s — exec.library : primitives de listes doublement chaînées
; (newlist, AddHead, AddTail, Remove, FindName). Convention Amiga : scratch =
; d0/d1/a0/a1 ; a6 = library base.
; Piste IMPLÉMENTATION (« clean ») : docs/analysis/exec-spec.md + ABI publique.

                include "exec.i"

                xdef    newlist
                xdef    exec_AddHead
                xdef    exec_AddTail
                xdef    exec_Remove
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

; Remove(node a1)
exec_Remove:
        move.l  (a1),d0              ; Succ
        move.l  LN_PRED(a1),a0       ; Pred
        move.l  d0,(a0)              ; Pred.Succ = Succ
        move.l  d0,a0                ; a0 = Succ
        move.l  LN_PRED(a1),LN_PRED(a0) ; Succ.Pred = Pred
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
