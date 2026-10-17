; src/intuition/pointer.s — accumulateur de pointeur Intuition (câblage M6R live du requester).
;
; LE chaînon manquant du requester cliquable. gameport.device produit des InputEvents RAWMOUSE à deltas
; RELATIFS (mouvement par frame) ; le req_input_handler hit-teste des coordonnées ABSOLUES. pointer_input_handler
; fait le pont : handler input.device de pri HAUTE (50 > 0 du requester -> Enqueue le place AVANT dans la chaîne)
; qui, pour chaque RAWMOUSE, intègre ie_X/ie_Y (deltas relatifs signés) dans la position absolue PTR_X/PTR_Y
; (clampée aux bornes écran), puis RÉÉCRIT ie_X/ie_Y en absolu. Les handlers suivants (req_input_handler, INCHANGÉ)
; voient donc une position absolue. C'est exactement ce que fait l'input handler d'Intuition (suivi du pointeur) ;
; la place fidèle de PTR_X/PTR_Y est IB_MOUSEX/IB_MOUSEY d'IntuitionBase (on utilise ici les globals RAM basse de
; preuve, comme REQ_HIT). Piste IMPLÉMENTATION (« clean ») : NDK inputevent.i + intuition. AUCUNE lecture ROM.

                include "exec.i"

                xdef    pointer_input_handler

; pointer_input_handler(a0 = liste d'InputEvents, a1 = is_Data) : handler input.device (pri 50). Pour chaque
; RAWMOUSE : PTR += (ie_X, ie_Y) relatifs signés, clamp [0, PTR_?MAX-1], réécrit ie_X/ie_Y en absolu. Rend d0 =
; liste (pass-through). Préserve d2-d7/a2-a6 (sauve d2/d3/d4/a3).
pointer_input_handler:
                movem.l d2/d3/d4/a3,-(sp)
                move.l  a0,d2                ; liste de retour (pass-through)
                move.l  a0,a3                ; parcours
.pih_loop:
                move.l  a3,d0
                beq.s   .pih_done
                cmp.b   #IECLASS_RAWMOUSE,IE_CLASS(a3)
                bne.s   .pih_next
                move.w  PTR_X,d3             ; X : position absolue += delta relatif
                add.w   IE_X(a3),d3
                ifeq    PTR_NO_CLAMP
                bpl.s   .pih_xlo
                moveq   #0,d3                ; clamp bas (< 0 -> 0)
.pih_xlo:
                cmp.w   #PTR_XMAX,d3
                blt.s   .pih_xhi
                move.w  #PTR_XMAX-1,d3       ; clamp haut (>= XMAX -> XMAX-1)
.pih_xhi:
                endc                         ; RED PTR_NO_CLAMP : aucun écrêtage -> position hors écran possible
                move.w  d3,PTR_X
                move.w  d3,IE_X(a3)          ; réécrit en absolu pour les handlers suivants
                move.w  PTR_Y,d4             ; Y : idem
                add.w   IE_Y(a3),d4
                ifeq    PTR_NO_CLAMP
                bpl.s   .pih_ylo
                moveq   #0,d4
.pih_ylo:
                cmp.w   #PTR_YMAX,d4
                blt.s   .pih_yhi
                move.w  #PTR_YMAX-1,d4
.pih_yhi:
                endc
                move.w  d4,PTR_Y
                move.w  d4,IE_Y(a3)
.pih_next:
                move.l  IE_NEXTEVENT(a3),a3
                bra.s   .pih_loop
.pih_done:
                move.l  d2,d0                ; liste (pass-through)
                movem.l (sp)+,d2/d3/d4/a3
                rts
