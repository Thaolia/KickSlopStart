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
                xdef    it_ptrmoved
                xdef    ptr_image
                xref    it_event             ; screens.s : boutons et mouvements -> tâche d'entrée
                xref    it_keyin
                xref    it_tickin
                xref    it_diskin

; pointer_input_handler(a0 = liste d'InputEvents, a1 = is_Data) : handler input.device (pri 50). Pour chaque
; RAWMOUSE : PTR += (ie_X, ie_Y) relatifs signés, clamp [0, PTR_?MAX-1], réécrit ie_X/ie_Y en absolu. Rend d0 =
; liste (pass-through). Préserve d2-d7/a2-a6 (sauve d2/d3/d4/a3).
pointer_input_handler:
                movem.l d2/d3/d4/a3,-(sp)
                move.l  a0,d2                ; liste de retour (pass-through)
                move.l  a0,a3                ; parcours
.pih_loop:
                move.l  a3,d0
                beq     .pih_done
                cmp.b   #IECLASS_RAWKEY,IE_CLASS(a3)
                bne.s   .pih_tick
                jsr     it_keyin             ; clavier d'un gadget texte actif
                bra.s   .pih_next
.pih_tick:
                cmp.b   #IECLASS_TIMER,IE_CLASS(a3)
                bne.s   .pih_disk
                jsr     it_tickin            ; INTUITICKS (tâche d'entrée)
                bra.s   .pih_next
.pih_disk:
                cmp.b   #IECLASS_DISKREMOVED,IE_CLASS(a3)
                beq.s   .pih_dk
                cmp.b   #IECLASS_DISKINSERTED,IE_CLASS(a3)
                bne.s   .pih_mouse
.pih_dk:
                jsr     it_diskin            ; DISKINSERTED / DISKREMOVED (tâche d'entrée)
                bra.s   .pih_next
.pih_mouse:
                cmp.b   #IECLASS_RAWMOUSE,IE_CLASS(a3)
                bne.s   .pih_next
                bsr     ptr_ticks            ; deltas ramenés à la vitesse des Preferences
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
                bra     .pih_loop
.pih_done:
                move.l  d2,d0                ; liste (pass-through)
                movem.l (sp)+,d2/d3/d4/a3
                rts

; ptr_ticks(a3 = événement RAWMOUSE) : comme intuition 1.3, un compte de la souris vaut un pixel hires (une demi-ligne
; en Y) divisé par PointerTicks des Preferences ; nos positions étant en pixels lores et en lignes, chaque delta est
; divisé par 2 × PointerTicks, le reste étant reporté sur les événements suivants (IB_PREMX/Y). Rien avant l'init
; d'intuition. Clobbe d0/d1/a0/a1.
ptr_ticks:
                move.l  INT_IBASE,d0
                beq.s   .pt_ret
                move.l  d0,a1
                move.w  IB_PREFS+PF_PTRTICKS(a1),d1
                ble.s   .pt_ret
                add.w   d1,d1                ; d1 = diviseur
                lea     IE_X(a3),a0
                lea     IB_PREMX(a1),a1
                bsr.s   .pt_axis
                lea     IE_Y(a3),a0
                addq.l  #IB_PREMY-IB_PREMX,a1
.pt_axis:                            ; (a0) = delta, (a1) = reste : (delta + reste) = q × d1 + r, 0 <= r < d1
                move.w  (a0),d0
                add.w   (a1),d0
                ext.l   d0
                divs    d1,d0
                swap    d0                   ; d0.w = reste (signe du dividende)
                tst.w   d0
                bpl.s   .pa_pos
                add.w   d1,d0                ; reste négatif : quotient - 1, reste + diviseur
                move.w  d0,(a1)
                swap    d0
                subq.w  #1,d0
                move.w  d0,(a0)
                rts
.pa_pos:
                move.w  d0,(a1)
                swap    d0
                move.w  d0,(a0)
.pt_ret:
                rts

; it_ptrmoved() : place le sprite du pointeur en (PTR_X, PTR_Y) décalé de XOffset/YOffset des Preferences, et met
; à jour ib_MouseX/Y (coordonnées de l'écran HIRES : x doublé). Rien avant l'init d'intuition. Préserve tout.
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
                move.b  IB_PREFS+PF_XOFFSET(a1),d0
                ext.w   d0
                add.w   PTR_X,d0
                move.b  IB_PREFS+PF_YOFFSET(a1),d1
                ext.w   d1
                add.w   PTR_Y,d1
                lea     IB_PTRSS(a1),a1
                sub.l   a0,a0                ; ViewPort de la View active
                jsr     LVO_MOVESPRITE(a6)
.pm_ret:
                movem.l (sp)+,d0-d1/a0-a1/a6
                rts

; it_ptrinit(a2 = IntuitionBase, a6 = SysBase) : copie l'image du pointeur des Preferences en chip (IB_PTRDATA),
; réserve le canal 0 et l'affiche à la position courante ; publie IntuitionBase dans INT_IBASE. Sans GfxBase ou sans
; mémoire : pas de pointeur.
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
                move.l  d0,IB_PTRDATA(a2)
                lea     4(a3),a1
                lea     IB_PREFS+PF_PTRMATRIX+4(a2),a0
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
