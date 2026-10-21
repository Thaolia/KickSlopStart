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
                include "intuition.i"
                include "graphics.i"

                xdef    pointer_input_handler
                xdef    it_ptrinit
                xref    it_event             ; screens.s : boutons et mouvements -> tâche d'entrée
                xref    it_keyin

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
                cmp.b   #IECLASS_RAWKEY,IE_CLASS(a3)
                bne.s   .pih_mouse
                jsr     it_keyin             ; clavier d'un gadget texte actif
                bra.s   .pih_next
.pih_mouse:
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
                bsr     it_ptrmoved          ; sprite du pointeur + IB_MOUSEX/Y
                move.w  IE_CODE(a3),d0       ; boutons et mouvements -> tâche d'entrée d'intuition
                jsr     it_event
.pih_next:
                move.l  IE_NEXTEVENT(a3),a3
                bra.s   .pih_loop
.pih_done:
                move.l  d2,d0                ; liste (pass-through)
                movem.l (sp)+,d2/d3/d4/a3
                rts

; it_ptrmoved() : place le sprite du pointeur en (PTR_X, PTR_Y) et met à jour ib_MouseX/Y (coordonnées de l'écran
; HIRES : x doublé). Rien avant l'init d'intuition. Préserve tout.
it_ptrmoved:
                movem.l d0-d1/a0-a1/a6,-(sp)
                move.l  INT_IBASE,d0
                beq.s   .pm_ret
                move.l  d0,a1
                move.w  PTR_X,d0
                add.w   d0,d0
                move.w  d0,IB_MOUSEX(a1)
                move.w  PTR_Y,IB_MOUSEY(a1)
                move.l  IB_GFXBASE(a1),d0
                beq.s   .pm_ret
                move.l  d0,a6
                lea     IB_PTRSS(a1),a1
                sub.l   a0,a0                ; ViewPort de la View active
                move.w  PTR_X,d0
                move.w  PTR_Y,d1
                jsr     LVO_MOVESPRITE(a6)
.pm_ret:
                movem.l (sp)+,d0-d1/a0-a1/a6
                rts

; it_ptrinit(a2 = IntuitionBase, a6 = SysBase) : copie l'image du pointeur en chip, réserve le canal 0 et l'affiche à
; la position courante ; publie IntuitionBase dans INT_IBASE. Sans GfxBase ou sans mémoire : pas de pointeur.
; Préserve d2-d7/a2-a6.
it_ptrinit:
                movem.l a3/a6,-(sp)
                move.l  a2,INT_IBASE
                tst.l   IB_GFXBASE(a2)
                beq.s   .pi_ret
                move.l  #PTR_DATASIZE,d0
                move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
                jsr     LVO_ALLOCMEM(a6)
                tst.l   d0
                beq.s   .pi_ret
                move.l  d0,a3                ; a3 = données (POS, CTL, image, 0, 0)
                lea     4(a3),a1
                lea     ptr_image(pc),a0
                moveq   #PTR_HEIGHT*2-1,d0
.pi_cpy:
                move.w  (a0)+,(a1)+
                dbra    d0,.pi_cpy
                lea     IB_PTRSS(a2),a1
                move.w  #PTR_HEIGHT,ss_height(a1)
                move.w  PTR_X,ss_x(a1)
                move.w  PTR_Y,ss_y(a1)
                move.l  IB_GFXBASE(a2),a6
                move.l  a1,a0
                moveq   #0,d0
                jsr     LVO_GETSPRITE(a6)
                tst.l   d0
                bmi.s   .pi_ret
                sub.l   a0,a0
                lea     IB_PTRSS(a2),a1
                move.l  a2,-(sp)
                move.l  a3,a2
                jsr     LVO_CHANGESPRITE(a6)
                move.l  (sp)+,a2
.pi_ret:
                movem.l (sp)+,a3/a6
                rts

; image du pointeur (dessinée pour ce projet) : flèche, pixel = plan1*2 + plan0 -> couleurs 17 (rouge), 18 (noir)
PTR_HEIGHT      EQU 16
PTR_DATASIZE    EQU 4+PTR_HEIGHT*4+4
ptr_image:
        dc.w    $0000,$C000            ; KK..............
        dc.w    $4000,$A000            ; KRK.............
        dc.w    $6000,$9000            ; KRRK............
        dc.w    $7000,$8800            ; KRRRK...........
        dc.w    $7800,$8400            ; KRRRRK..........
        dc.w    $7C00,$8200            ; KRRRRRK.........
        dc.w    $7E00,$8100            ; KRRRRRRK........
        dc.w    $7F00,$8080            ; KRRRRRRRK.......
        dc.w    $7C00,$83C0            ; KRRRRRKKKK......
        dc.w    $6C00,$9200            ; KRRKRRK.........
        dc.w    $4600,$A900            ; KRK.KRRK........
        dc.w    $0600,$C900            ; KK..KRRK........
        dc.w    $0300,$0480            ; .....KRRK.......
        dc.w    $0300,$0480            ; .....KRRK.......
        dc.w    $0000,$0300            ; ......KK........
        dc.w    $0000,$0000            ; ................
