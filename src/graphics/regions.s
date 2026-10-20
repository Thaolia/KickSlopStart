; src/graphics/regions.s — Regions de graphics.library (graphics/regions.h) + moteur de listes de rectangles.
;
; Une Region = bounds (struct Rectangle) + liste de RegionRectangle DISJOINTS. Comme sur Amiga, les bornes d'un
; RegionRectangle sont RELATIVES à region->bounds.MinX/MinY. Chaque opération publique repasse la liste en
; coordonnées absolues (rg_toabs), travaille, puis recalcule bounds = union des rectangles et relativise
; (rg_finish, qui refait aussi les liens Prev). Rectangles inclusifs (MinX..MaxX, MinY..MaxY).
; Le moteur rl_* (soustraction / intersection d'un rectangle sur une liste disjointe) est partagé avec
; layers.library pour calculer les parties visibles des couches.
; Opérations : renvoient d0 = TRUE (-1), ou FALSE (0) si la mémoire manque (la région reste cohérente mais
; incomplète, comme le permet l'AutoDoc).
; Piste IMPLÉMENTATION (« clean ») : AutoDocs graphics.library (Regions) + graphics/regions.h. AUCUNE lecture ROM.

                include "exec.i"
                include "graphics.i"

                xdef    gfx_NewRegion
                xdef    gfx_DisposeRegion
                xdef    gfx_ClearRegion
                xdef    gfx_OrRectRegion
                xdef    gfx_AndRectRegion
                xdef    gfx_ClearRectRegion
                xdef    gfx_XorRectRegion
                xdef    gfx_OrRegionRegion
                xdef    gfx_AndRegionRegion
                xdef    gfx_XorRegionRegion
                xdef    rl_sub
                xdef    rl_and
                xdef    rl_add
                xdef    rl_free

; --- nœud de liste = RegionRectangle (Next, Prev, bounds) ---
RR_NEXT         EQU 0
RR_PREV         EQU 4
RR_MINX         EQU 8
RR_MINY         EQU 10
RR_MAXX         EQU 12
RR_MAXY         EQU 14
RR_SIZE         EQU 16
RG_MINX         EQU 0                ; struct Region
RG_MINY         EQU 2
RG_MAXX         EQU 4
RG_MAXY         EQU 6
RG_RECTS        EQU 8                ; cellule de tête de la liste
RG_SIZE         EQU 12

; ============================ moteur rl_* (coordonnées absolues) ============================
; Liste désignée par a2 = adresse de la cellule qui pointe sur le premier nœud (RG_RECTS(region), ou un long
; quelconque). Rectangle désigné par a1 (MinX, MinY, MaxX, MaxY : 4 mots). Les rl_* préservent d2-d7/a2-a6.

; rl_add(a2 = liste, a1 = rectangle) : ajoute un nœud en tête (l'appelant garantit la disjonction). d0 = 0 ok,
; -1 mémoire.
rl_add:
        movem.l a1/a6,-(sp)
        move.l  ($4).w,a6
        moveq   #RR_SIZE,d0
        move.l  #MEMF_PUBLIC,d1
        jsr     LVO_ALLOCMEM(a6)
        movem.l (sp)+,a1/a6
        tst.l   d0
        beq.s   .ad_nomem
        move.l  d0,a0
        move.l  (a1),RR_MINX(a0)
        move.l  4(a1),RR_MAXX(a0)
        move.l  (a2),RR_NEXT(a0)
        move.l  a0,(a2)
        moveq   #0,d0
        rts
.ad_nomem:
        moveq   #-1,d0
        rts

; rl_free(a2 = liste) : libère tous les nœuds ; cellule remise à 0.
rl_free:
        movem.l a3/a6,-(sp)
        move.l  ($4).w,a6
.fr_lp:
        move.l  (a2),d0
        beq.s   .fr_out
        move.l  d0,a1
        move.l  RR_NEXT(a1),(a2)
        moveq   #RR_SIZE,d0
        jsr     LVO_FREEMEM(a6)
        bra.s   .fr_lp
.fr_out:
        movem.l (sp)+,a3/a6
        rts

; rl_and(a2 = liste, a1 = rectangle) : chaque nœud devient son intersection avec le rectangle ; les vides sont
; libérés.
rl_and:
        movem.l d2-d5/a3-a4/a6,-(sp)
        move.l  ($4).w,a6
        movem.w (a1),d2-d5           ; d2..d5 = MinX, MinY, MaxX, MaxY du rectangle (étendus en longs)
        move.l  a2,a4                ; a4 = cellule précédente
.an_lp:
        move.l  (a4),d0
        beq.s   .an_out
        move.l  d0,a3
        cmp.w   RR_MINX(a3),d2
        ble.s   .an_x0
        move.w  d2,RR_MINX(a3)
.an_x0:
        cmp.w   RR_MINY(a3),d3
        ble.s   .an_y0
        move.w  d3,RR_MINY(a3)
.an_y0:
        cmp.w   RR_MAXX(a3),d4
        bge.s   .an_x1
        move.w  d4,RR_MAXX(a3)
.an_x1:
        cmp.w   RR_MAXY(a3),d5
        bge.s   .an_y1
        move.w  d5,RR_MAXY(a3)
.an_y1:
        move.w  RR_MINX(a3),d0
        cmp.w   RR_MAXX(a3),d0
        bgt.s   .an_drop
        move.w  RR_MINY(a3),d0
        cmp.w   RR_MAXY(a3),d0
        bgt.s   .an_drop
        move.l  a3,a4                ; nœud gardé : avance
        bra.s   .an_lp
.an_drop:
        move.l  RR_NEXT(a3),(a4)
        move.l  a3,a1
        moveq   #RR_SIZE,d0
        jsr     LVO_FREEMEM(a6)
        bra.s   .an_lp
.an_out:
        movem.l (sp)+,d2-d5/a3-a4/a6
        rts

; rl_sub(a2 = liste, a1 = rectangle) : retire le rectangle de chaque nœud. Un nœud recouvert se découpe en au
; plus 4 morceaux (bande haute, bande basse, gauche et droite de la bande commune) : le 1er réutilise le nœud,
; les autres sont insérés juste après lui. d0 = 0 ok, -1 mémoire.
rl_sub:
        movem.l d2-d7/a3-a6,-(sp)
        move.l  ($4).w,a6
        movem.w (a1),d2-d5           ; rectangle B
        moveq   #0,d7                ; d7 = résultat
        move.l  a2,a4                ; a4 = cellule précédente
        lea     -32(sp),sp           ; 4 morceaux x 8 octets
        move.l  sp,a5
.sb_lp:
        move.l  (a4),d0
        beq     .sb_out
        move.l  d0,a3
        cmp.w   RR_MAXX(a3),d2       ; pas de recouvrement -> nœud intact
        bgt     .sb_keep
        cmp.w   RR_MINX(a3),d4
        blt     .sb_keep
        cmp.w   RR_MAXY(a3),d3
        bgt     .sb_keep
        cmp.w   RR_MINY(a3),d5
        blt     .sb_keep
        move.l  a5,a0                ; morceaux
        moveq   #0,d6                ; d6 = nombre de morceaux
        move.w  RR_MINY(a3),d0       ; bande haute : A.MinY .. B.MinY-1
        cmp.w   d3,d0
        bge.s   .sb_nt
        move.w  RR_MINX(a3),(a0)+
        move.w  d0,(a0)+
        move.w  RR_MAXX(a3),(a0)+
        move.w  d3,d1
        subq.w  #1,d1
        move.w  d1,(a0)+
        addq.w  #1,d6
.sb_nt:
        move.w  RR_MAXY(a3),d0       ; bande basse : B.MaxY+1 .. A.MaxY
        cmp.w   d5,d0
        ble.s   .sb_nb
        move.w  RR_MINX(a3),(a0)+
        move.w  d5,d1
        addq.w  #1,d1
        move.w  d1,(a0)+
        move.w  RR_MAXX(a3),(a0)+
        move.w  d0,(a0)+
        addq.w  #1,d6
.sb_nb:
        move.w  RR_MINY(a3),d0       ; bande commune : max(MinY) .. min(MaxY) -> d0..d1
        cmp.w   d3,d0
        bge.s   .sb_m0
        move.w  d3,d0
.sb_m0:
        move.w  RR_MAXY(a3),d1
        cmp.w   d5,d1
        ble.s   .sb_m1
        move.w  d5,d1
.sb_m1:
        cmp.w   RR_MINX(a3),d2       ; gauche : A.MinX .. B.MinX-1
        ble.s   .sb_nl
        move.w  RR_MINX(a3),(a0)+
        move.w  d0,(a0)+
        move.w  d2,(a0)
        subq.w  #1,(a0)+
        move.w  d1,(a0)+
        addq.w  #1,d6
.sb_nl:
        cmp.w   RR_MAXX(a3),d4       ; droite : B.MaxX+1 .. A.MaxX
        bge.s   .sb_nr
        move.w  d4,(a0)
        addq.w  #1,(a0)+
        move.w  d0,(a0)+
        move.w  RR_MAXX(a3),(a0)+
        move.w  d1,(a0)+
        addq.w  #1,d6
.sb_nr:
        tst.w   d6
        bne.s   .sb_pieces
        move.l  RR_NEXT(a3),(a4)     ; entièrement recouvert : nœud retiré
        move.l  a3,a1
        moveq   #RR_SIZE,d0
        jsr     LVO_FREEMEM(a6)
        bra     .sb_lp
.sb_pieces:
        move.l  (a5),RR_MINX(a3)     ; 1er morceau dans le nœud
        move.l  4(a5),RR_MAXX(a3)
        lea     8(a5),a0
        subq.w  #2,d6
        bmi.s   .sb_adv
.sb_ins:
        movem.l d0-d1/a0,-(sp)
        moveq   #RR_SIZE,d0
        move.l  #MEMF_PUBLIC,d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  d0,a1
        movem.l (sp)+,d0-d1/a0
        move.l  a1,d1
        bne.s   .sb_got
        moveq   #-1,d7               ; mémoire : morceaux restants perdus
        bra.s   .sb_adv
.sb_got:
        move.l  (a0)+,RR_MINX(a1)
        move.l  (a0)+,RR_MAXX(a1)
        move.l  RR_NEXT(a3),RR_NEXT(a1)
        move.l  a1,RR_NEXT(a3)
        move.l  a1,a3                ; les morceaux sont hors de B : on avance au-delà
        dbra    d6,.sb_ins
.sb_adv:
        move.l  a3,a4
        bra     .sb_lp
.sb_keep:
        move.l  a3,a4
        bra     .sb_lp
.sb_out:
        lea     32(sp),sp
        move.l  d7,d0
        movem.l (sp)+,d2-d7/a3-a6
        rts

; ============================ Regions publiques ============================
; Chaque fonction publique sauve d2-d7/a2-a6 ; a3 = région traitée, a2 = cellule de sa liste (absolue pendant
; l'opération), d7 = cumul d'échec mémoire, sortie commune rg_exit.

; rg_toabs(a0 = region) : rectangles en coordonnées absolues. Utilise d0/d1/a1.
rg_toabs:
        move.w  RG_MINX(a0),d0
        move.w  RG_MINY(a0),d1
        move.l  RG_RECTS(a0),a1
.ta_lp:
        cmpa.w  #0,a1
        beq.s   .ta_r
        add.w   d0,RR_MINX(a1)
        add.w   d0,RR_MAXX(a1)
        add.w   d1,RR_MINY(a1)
        add.w   d1,RR_MAXY(a1)
        move.l  RR_NEXT(a1),a1
        bra.s   .ta_lp
.ta_r:
        rts

; rg_finish(a0 = region) : bornes = union des rectangles (0 si vide), rectangles relativisés, liens Prev refaits.
; Utilise d0-d5/a1/a2.
rg_finish:
        move.l  RG_RECTS(a0),d0
        bne.s   .fi_some
        clr.l   RG_MINX(a0)
        clr.l   RG_MAXX(a0)
        rts
.fi_some:
        move.w  #$7FFF,d2
        move.w  d2,d3
        move.w  #$8000,d4
        move.w  d4,d5
        move.l  d0,a1
.fi_b:
        cmp.w   RR_MINX(a1),d2
        ble.s   .fi_b0
        move.w  RR_MINX(a1),d2
.fi_b0:
        cmp.w   RR_MINY(a1),d3
        ble.s   .fi_b1
        move.w  RR_MINY(a1),d3
.fi_b1:
        cmp.w   RR_MAXX(a1),d4
        bge.s   .fi_b2
        move.w  RR_MAXX(a1),d4
.fi_b2:
        cmp.w   RR_MAXY(a1),d5
        bge.s   .fi_b3
        move.w  RR_MAXY(a1),d5
.fi_b3:
        move.l  RR_NEXT(a1),a1
        cmpa.w  #0,a1
        bne.s   .fi_b
        movem.w d2-d5,RG_MINX(a0)
        move.l  d0,a1
        suba.l  a2,a2
.fi_rel:
        sub.w   d2,RR_MINX(a1)
        sub.w   d2,RR_MAXX(a1)
        sub.w   d3,RR_MINY(a1)
        sub.w   d3,RR_MAXY(a1)
        move.l  a2,RR_PREV(a1)
        move.l  a1,a2
        move.l  RR_NEXT(a1),a1
        cmpa.w  #0,a1
        bne.s   .fi_rel
        rts

; rg_open(a0 = region) : a3 = région, liste absolue, a2 = sa cellule, d7 = 0.
rg_open:
        move.l  a0,a3
        bsr     rg_toabs
        lea     RG_RECTS(a3),a2
        moveq   #0,d7
        rts
; rg_exit : termine la région a3, d0 = TRUE / FALSE, restaure et revient (à brancher, pas à appeler).
rg_exit:
        move.l  a3,a0
        bsr     rg_finish
        moveq   #-1,d0
        tst.l   d7
        beq.s   .ex_r
        moveq   #0,d0
.ex_r:
        movem.l (sp)+,d2-d7/a2-a6
        rts

; NewRegion() -> d0 = région vide, ou 0.
gfx_NewRegion:
        move.l  a6,-(sp)
        move.l  ($4).w,a6
        moveq   #RG_SIZE,d0
        move.l  #MEMF_PUBLIC|MEMF_CLEAR,d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  (sp)+,a6
        rts

; ClearRegion(region a0) : vide la région.
gfx_ClearRegion:
        move.l  a2,-(sp)
        move.l  a0,-(sp)
        lea     RG_RECTS(a0),a2
        bsr     rl_free
        move.l  (sp)+,a0
        clr.l   RG_MINX(a0)
        clr.l   RG_MAXX(a0)
        move.l  (sp)+,a2
        rts

; DisposeRegion(region a0) : vide puis rend la région (0 accepté).
gfx_DisposeRegion:
        move.l  a0,d0
        beq.s   .dr_r
        move.l  a0,-(sp)
        bsr     gfx_ClearRegion
        move.l  (sp)+,a1
        move.l  a6,-(sp)
        move.l  ($4).w,a6
        moveq   #RG_SIZE,d0
        jsr     LVO_FREEMEM(a6)
        move.l  (sp)+,a6
.dr_r:
        rts

; OrRectRegion(region a0, rectangle a1) : région ∪= rectangle.
gfx_OrRectRegion:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  a1,a4
        bsr     rg_open
        move.l  a4,a1
        bsr     rl_sub
        move.l  d0,d7
        move.l  a4,a1
        bsr     rl_add
        or.l    d0,d7
        bra     rg_exit

; AndRectRegion(region a0, rectangle a1) : région ∩= rectangle.
gfx_AndRectRegion:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  a1,a4
        bsr     rg_open
        move.l  a4,a1
        bsr     rl_and
        bra     rg_exit

; ClearRectRegion(region a0, rectangle a1) : région -= rectangle.
gfx_ClearRectRegion:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  a1,a4
        bsr     rg_open
        move.l  a4,a1
        bsr     rl_sub
        move.l  d0,d7
        bra     rg_exit

; XorRectRegion(region a0, rectangle a1) : région = (région - rectangle) ∪ (rectangle - région).
gfx_XorRectRegion:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  a1,a4
        bsr     rg_open
        move.l  a4,a1
        bsr     rg_xorabs
        move.l  d0,d7
        bra     rg_exit

; rg_xorabs(a2 = liste absolue, a1 = rectangle) -> d0 = 0 / -1. Les morceaux du rectangle hors de la liste sont
; calculés dans une liste temporaire (cellule sur la pile), la liste perd le rectangle, puis les deux s'unissent.
; Préserve d2-d7/a2-a6.
rg_xorabs:
        movem.l d7/a2-a5,-(sp)
        move.l  a1,a4
        move.l  a2,a5                ; a5 = cellule de la liste
        clr.l   -(sp)                ; cellule temporaire
        move.l  sp,a2
        bsr     rl_add               ; temp = { rectangle }
        move.l  d0,d7
        move.l  (a5),a3
.xo_lp:
        cmpa.w  #0,a3
        beq.s   .xo_cut
        lea     RR_MINX(a3),a1
        bsr     rl_sub               ; temp -= chaque rectangle de la liste
        or.l    d0,d7
        move.l  RR_NEXT(a3),a3
        bra.s   .xo_lp
.xo_cut:
        move.l  a5,a2
        move.l  a4,a1
        bsr     rl_sub               ; liste -= rectangle
        or.l    d0,d7
        move.l  (sp)+,d0
        beq.s   .xo_r
        move.l  d0,a1
.xo_tail:
        tst.l   RR_NEXT(a1)
        beq.s   .xo_link
        move.l  RR_NEXT(a1),a1
        bra.s   .xo_tail
.xo_link:
        move.l  (a5),RR_NEXT(a1)     ; temp en tête de la liste
        move.l  d0,(a5)
.xo_r:
        move.l  d7,d0
        movem.l (sp)+,d7/a2-a5
        rts

; rg_srcrect(a0 = région source, a4 = son nœud, a5 = tampon 8 o) -> a1 = a5 = rectangle absolu du nœud.
rg_srcrect:
        move.l  a5,a1
        move.w  RG_MINX(a0),d0
        move.w  RG_MINY(a0),d1
        move.w  RR_MINX(a4),(a1)
        add.w   d0,(a1)
        move.w  RR_MINY(a4),2(a1)
        add.w   d1,2(a1)
        move.w  RR_MAXX(a4),4(a1)
        add.w   d0,4(a1)
        move.w  RR_MAXY(a4),6(a1)
        add.w   d1,6(a1)
        rts

; rg_open2(src a0, dest a1) : d6 = source, région destination ouverte (a3/a2/d7), a5 = tampon de 16 octets sur
; la pile (libéré par rg_exit2), a4 = premier nœud de la source.
rg_open2:
        move.l  (sp)+,d0             ; retour
        lea     -16(sp),sp
        move.l  sp,a5
        move.l  d0,-(sp)
        move.l  a0,d6
        move.l  a1,a0
        bsr     rg_open
        move.l  d6,a0
        move.l  RG_RECTS(a0),a4
        rts
rg_exit2:
        lea     16(sp),sp
        bra     rg_exit

; OrRegionRegion(src a0, dest a1) : dest ∪= src.
gfx_OrRegionRegion:
        movem.l d2-d7/a2-a6,-(sp)
        bsr     rg_open2
.or_lp:
        cmpa.w  #0,a4
        beq.s   .or_out
        move.l  d6,a0
        bsr     rg_srcrect
        bsr     rl_sub
        or.l    d0,d7
        move.l  a5,a1
        bsr     rl_add
        or.l    d0,d7
        move.l  RR_NEXT(a4),a4
        bra.s   .or_lp
.or_out:
        bra     rg_exit2

; XorRegionRegion(src a0, dest a1) : dest = dest xor src (rectangles de src disjoints : xor successifs).
gfx_XorRegionRegion:
        movem.l d2-d7/a2-a6,-(sp)
        bsr     rg_open2
.xr_lp:
        cmpa.w  #0,a4
        beq.s   .xr_out
        move.l  d6,a0
        bsr     rg_srcrect
        bsr     rg_xorabs
        or.l    d0,d7
        move.l  RR_NEXT(a4),a4
        bra.s   .xr_lp
.xr_out:
        bra     rg_exit2

; AndRegionRegion(src a0, dest a1) : dest = ∪ (d ∩ s) sur les rectangles d de dest et s de src (disjoints deux à
; deux, donc les intersections aussi). L'ancienne liste de dest est détachée puis libérée.
gfx_AndRegionRegion:
        movem.l d2-d7/a2-a6,-(sp)
        bsr     rg_open2
        move.l  (a2),d5              ; d5 = ancienne liste de dest
        clr.l   (a2)
.ar_src:
        cmpa.w  #0,a4
        beq.s   .ar_out
        move.l  d6,a0
        bsr     rg_srcrect
        move.l  d5,a0
.ar_dst:
        cmpa.w  #0,a0
        beq.s   .ar_nexts
        move.w  RR_MINX(a0),d0       ; intersection -> 8(a5)
        cmp.w   (a5),d0
        bge.s   .ar_1
        move.w  (a5),d0
.ar_1:
        move.w  d0,8(a5)
        move.w  RR_MINY(a0),d0
        cmp.w   2(a5),d0
        bge.s   .ar_2
        move.w  2(a5),d0
.ar_2:
        move.w  d0,10(a5)
        move.w  RR_MAXX(a0),d0
        cmp.w   4(a5),d0
        ble.s   .ar_3
        move.w  4(a5),d0
.ar_3:
        move.w  d0,12(a5)
        cmp.w   8(a5),d0
        blt.s   .ar_nextd
        move.w  RR_MAXY(a0),d0
        cmp.w   6(a5),d0
        ble.s   .ar_4
        move.w  6(a5),d0
.ar_4:
        move.w  d0,14(a5)
        cmp.w   10(a5),d0
        blt.s   .ar_nextd
        move.l  a0,-(sp)
        lea     8(a5),a1
        bsr     rl_add
        or.l    d0,d7
        move.l  (sp)+,a0
.ar_nextd:
        move.l  RR_NEXT(a0),a0
        bra.s   .ar_dst
.ar_nexts:
        move.l  RR_NEXT(a4),a4
        bra.s   .ar_src
.ar_out:
        move.l  d5,-(sp)             ; libère l'ancienne liste (cellule sur la pile)
        move.l  a2,-(sp)
        lea     4(sp),a2
        bsr     rl_free
        move.l  (sp)+,a2
        addq.l  #4,sp
        bra     rg_exit2
