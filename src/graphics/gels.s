; src/graphics/gels.s — GELs de graphics.library : liste de VSprites triée par (Y, X) (InitGels, AddVSprite,
; RemVSprite, SortGList), Bobs (AddBob, RemIBob, DrawGList : fond sauvé/restauré, image posée avec son masque
; selon PlanePick/PlaneOnOff), masques (InitMasks), collisions (DoCollision, SetCollision) et animation
; (AddAnimOb, Animate, GetGBuffers, FreeGBuffers, InitGMasks).
; Dessin par lignes de pixels (gfx_putrow / gfx_ReadPixel) : passe par les couches et leurs ClipRects.
; Portée : les VSprites matériels (drapeau VSPRITE) restent dans la liste et participent aux collisions mais ne
; sont pas affichés ; l'ordre Before/After des Bobs et le double tampon (DBuffer) ne sont pas exploités ; les Bobs
; recouverts ne sont pas redessinés par RemIBob.
; Piste IMPLÉMENTATION (« clean ») : AutoDocs graphics.library, graphics/gels.h et RKM publics. AUCUNE lecture ROM.

                include "exec.i"
                include "graphics.i"

                xdef    gfx_AddBob
                xdef    gfx_AddVSprite
                xdef    gfx_DoCollision
                xdef    gfx_DrawGList
                xdef    gfx_InitGels
                xdef    gfx_InitMasks
                xdef    gfx_RemIBob
                xdef    gfx_RemVSprite
                xdef    gfx_SetCollision
                xdef    gfx_SortGList
                xdef    gfx_AddAnimOb
                xdef    gfx_Animate
                xdef    gfx_GetGBuffers
                xdef    gfx_InitGMasks
                xdef    gfx_FreeGBuffers
                xref    gfx_putrow
                xref    gfx_ReadPixel

; struct VSprite (graphics/gels.h, V34)
VS_NEXT         EQU 0
VS_PREV         EQU 4
VS_OLDY         EQU 16
VS_OLDX         EQU 18
VS_FLAGS        EQU 20
VS_Y            EQU 22
VS_X            EQU 24
VS_HEIGHT       EQU 26
VS_WIDTH        EQU 28               ; en mots
VS_DEPTH        EQU 30
VS_MEMASK       EQU 32
VS_HITMASK      EQU 34
VS_IMAGE        EQU 36
VS_BORDER       EQU 40
VS_COLLMASK     EQU 44
VS_BOB          EQU 52
VS_PICK         EQU 56
VS_ONOFF        EQU 57
VSB_VSPRITE     EQU 0
VSB_SAVEBACK    EQU 1
VSB_OVERLAY     EQU 2
VSB_BACKSAVED   EQU 8
; struct Bob
BOB_FLAGS       EQU 0
BOB_SAVE        EQU 2
BOB_SHADOW      EQU 6
BOB_VS          EQU 18
BOB_DBUF        EQU 26
BB_BDRAWN       EQU 9
BB_BOBSAWAY     EQU 10
BB_BOBNIX       EQU 11
; struct GelsInfo
GI_HEAD         EQU 2
GI_TAIL         EQU 6
GI_COLL         EQU 18
GI_LEFT         EQU 22
GI_RIGHT        EQU 24
GI_TOP          EQU 26
GI_BOTTOM       EQU 28
rp_GelsInfo     EQU 20
; struct AnimComp
AC_FLAGS        EQU 0
AC_TIMER        EQU 2
AC_TIMESET      EQU 4
AC_NEXTCOMP     EQU 6
AC_PREVCOMP     EQU 10
AC_NEXTSEQ      EQU 14
AC_ROUTINE      EQU 22
AC_YTRANS       EQU 26
AC_XTRANS       EQU 28
AC_HEADOB       EQU 30
AC_BOB          EQU 34
RINGTRIGGER     EQU $0001
; struct AnimOb
AO_NEXT         EQU 0
AO_PREV         EQU 4
AO_CLOCK        EQU 8
AO_OLDY         EQU 12
AO_OLDX         EQU 14
AO_Y            EQU 16
AO_X            EQU 18
AO_YVEL         EQU 20
AO_XVEL         EQU 22
AO_YACC         EQU 24
AO_XACC         EQU 26
AO_RINGY        EQU 28
AO_RINGX        EQU 30
AO_ROUTINE      EQU 32
AO_HEADCOMP     EQU 36
ANFRACSIZE      EQU 6
; struct DBufPacket
DB_BUFFER       EQU 8
DB_SIZE         EQU 12
; bits de DoCollision pour la routine 0 (bords)
TOPHIT          EQU 1
BOTTOMHIT       EQU 2
LEFTHIT         EQU 4
RIGHTHIT        EQU 8

GEL_CHUNK       EQU 64               ; pixels traités par appel de gfx_putrow

; ---------------------------------------------------------------------------------------------------------------
; InitGels(head a0, tail a1, gelsInfo a2) : liste vide encadrée par deux VSprites sentinelles (head au plus petit
; (Y, X), tail au plus grand), rattachée à la GelsInfo.
gfx_InitGels:
        move.l  a1,VS_NEXT(a0)
        clr.l   VS_PREV(a0)
        move.l  a0,VS_PREV(a1)
        clr.l   VS_NEXT(a1)
        move.l  #$80008000,d0
        move.l  d0,VS_Y(a0)
        move.l  d0,VS_OLDY(a0)
        move.l  #$7FFF7FFF,d0
        move.l  d0,VS_Y(a1)
        move.l  d0,VS_OLDY(a1)
        move.l  a0,GI_HEAD(a2)
        move.l  a1,GI_TAIL(a2)
        rts

; gel_gt(a0, a1 = VSprites) -> d0 = 1 si (Y, X) de a0 > (Y, X) de a1 (Y d'abord, comparaisons signées), sinon 0.
; Préserve le reste.
gel_gt:
        move.w  VS_Y(a0),d0
        cmp.w   VS_Y(a1),d0
        bgt.s   .gt_yes
        blt.s   .gt_no
        move.w  VS_X(a0),d0
        cmp.w   VS_X(a1),d0
        bgt.s   .gt_yes
.gt_no:
        moveq   #0,d0
        rts
.gt_yes:
        moveq   #1,d0
        rts

; gel_insert(vs a0, avant a1) : chaîne vs juste avant a1. Préserve tout sauf a1.
gel_insert:
        move.l  a1,VS_NEXT(a0)
        move.l  VS_PREV(a1),VS_PREV(a0)
        move.l  a0,VS_PREV(a1)
        move.l  VS_PREV(a0),a1
        move.l  a0,VS_NEXT(a1)
        rts

; AddVSprite(vs a0, rp a1) : drapeaux système effacés, ancienne position = position, insertion triée par (Y, X)
; dans la liste de rp->GelsInfo.
gfx_AddVSprite:
        movem.l a1-a2,-(sp)
        and.w   #$00FF,VS_FLAGS(a0)
        move.l  VS_Y(a0),VS_OLDY(a0)
        move.l  rp_GelsInfo(a1),a2
        move.l  GI_HEAD(a2),a1
        move.l  VS_NEXT(a1),a1
.av_lp:
        tst.l   VS_NEXT(a1)          ; sentinelle de fin : on insère avant
        beq.s   .av_ins
        exg     a0,a1
        bsr.s   gel_gt               ; élément > vs ?
        exg     a0,a1
        tst.w   d0
        bne.s   .av_ins
        move.l  VS_NEXT(a1),a1
        bra.s   .av_lp
.av_ins:
        bsr.s   gel_insert
        movem.l (sp)+,a1-a2
        rts

; RemVSprite(vs a0) : retire le VSprite de sa liste.
gfx_RemVSprite:
        move.l  a1,-(sp)
        move.l  VS_PREV(a0),a1
        move.l  VS_NEXT(a0),VS_NEXT(a1)
        move.l  VS_NEXT(a0),a1
        move.l  VS_PREV(a0),VS_PREV(a1)
        move.l  (sp)+,a1
        rts

; AddBob(bob a0, rp a1) : drapeaux système du Bob effacés, son VSprite (qui pointe sur le Bob) ajouté à la liste.
gfx_AddBob:
        and.w   #$00FF,BOB_FLAGS(a0)
        move.l  a0,d0
        move.l  BOB_VS(a0),a0
        move.l  d0,VS_BOB(a0)
        bra     gfx_AddVSprite

; RemIBob(bob a0, rp a1, vp a2) : retrait immédiat : fond restauré s'il avait été sauvé, VSprite retiré, Bob marqué
; BOBNIX.
gfx_RemIBob:
        movem.l d2-d7/a2-a4,-(sp)
        move.l  a0,a3
        move.l  BOB_VS(a3),a2
        bsr     gel_unsave
        move.l  a2,a0
        bsr.s   gfx_RemVSprite
        bclr    #BB_BDRAWN-8,BOB_FLAGS(a3)
        bset    #BB_BOBNIX-8,BOB_FLAGS(a3)
        movem.l (sp)+,d2-d7/a2-a4
        rts

; SortGList(rp a1) : tri par insertion de la liste par (Y, X) croissants (positions modifiées depuis l'ajout).
gfx_SortGList:
        movem.l a2-a4,-(sp)
        move.l  rp_GelsInfo(a1),a4
        move.l  GI_HEAD(a4),a4       ; a4 = tête
        move.l  VS_NEXT(a4),a2       ; a2 = élément courant
.sg_lp:
        tst.l   VS_NEXT(a2)
        beq.s   .sg_ret              ; sentinelle de fin
        move.l  VS_NEXT(a2),a3       ; a3 = suivant (sauvé avant déplacement)
        move.l  VS_PREV(a2),a0
        cmpa.l  a4,a0
        beq.s   .sg_nx
        move.l  a2,a1
        bsr     gel_gt               ; précédent > courant ?
        tst.w   d0
        beq.s   .sg_nx
        move.l  a2,a0                ; décroche le courant
        bsr     gfx_RemVSprite
        move.l  VS_PREV(a2),a1       ; remonte tant que le prédécesseur est plus grand
.sg_back:
        move.l  VS_PREV(a1),a0
        cmpa.l  a4,a0
        beq.s   .sg_put
        move.l  a0,-(sp)
        move.l  a2,a1
        bsr     gel_gt
        move.l  (sp)+,a1
        tst.w   d0
        beq.s   .sg_put0
        bra.s   .sg_back
.sg_put0:
        move.l  VS_NEXT(a1),a1       ; a1 = premier élément non plus grand -> insérer avant son suivant
.sg_put:
        move.l  a2,a0
        bsr     gel_insert
.sg_nx:
        move.l  a3,a2
        bra.s   .sg_lp
.sg_ret:
        movem.l (sp)+,a2-a4
        rts

; ---------------------------------------------------------------------------------------------------------------
; DrawGList(rp a1, vp a0) : 1) fonds sauvés restaurés, du dernier Bob dessiné au premier ; 2) dans l'ordre de la
; liste : Bob BOBSAWAY retiré (BOBNIX), sinon fond sauvé (SAVEBACK) puis image posée, ancienne position = position.
gfx_DrawGList:
        movem.l d2-d7/a2-a5,-(sp)
        move.l  rp_GelsInfo(a1),d0
        beq     .dg_ret
        move.l  d0,a5
        move.l  GI_TAIL(a5),a2
.dg_rest:
        move.l  VS_PREV(a2),a2
        tst.l   VS_PREV(a2)          ; tête atteinte
        beq.s   .dg_draw
        btst    #VSB_VSPRITE,VS_FLAGS+1(a2)
        bne.s   .dg_rest
        move.l  VS_BOB(a2),d0
        beq.s   .dg_rest
        move.l  d0,a3
        bsr     gel_unsave
        bra.s   .dg_rest
.dg_draw:
        move.l  GI_HEAD(a5),a2
        move.l  VS_NEXT(a2),a2
.dg_lp:
        move.l  VS_NEXT(a2),d7       ; d7 = suivant (le Bob courant peut quitter la liste)
        beq.s   .dg_ret
        btst    #VSB_VSPRITE,VS_FLAGS+1(a2)
        bne.s   .dg_nx
        move.l  VS_BOB(a2),d0
        beq.s   .dg_nx
        move.l  d0,a3
        btst    #BB_BOBSAWAY-8,BOB_FLAGS(a3)
        beq.s   .dg_show
        move.l  a2,a0
        bsr     gfx_RemVSprite
        bclr    #BB_BDRAWN-8,BOB_FLAGS(a3)
        bset    #BB_BOBNIX-8,BOB_FLAGS(a3)
        bra.s   .dg_nx
.dg_show:
        btst    #VSB_SAVEBACK,VS_FLAGS+1(a2)
        beq.s   .dg_img
        bsr     gel_save
.dg_img:
        bsr     gel_draw
        move.l  VS_Y(a2),VS_OLDY(a2)
        bset    #BB_BDRAWN-8,BOB_FLAGS(a3)
.dg_nx:
        move.l  d7,a2
        bra.s   .dg_lp
.dg_ret:
        movem.l (sp)+,d2-d7/a2-a5
        rts

; gel_geom(a2 = vs, a1 = rp) -> d4.w = hauteur, d5.w = largeur en pixels, d6.w = profondeur du BitMap du RastPort,
; d3.l = octets d'un plan de l'image (hauteur * largeur en mots * 2). Clobbe d0/a0.
gel_geom:
        move.w  VS_HEIGHT(a2),d4
        move.w  VS_WIDTH(a2),d5
        move.w  d4,d3
        mulu    d5,d3
        add.l   d3,d3
        lsl.w   #4,d5
        move.l  rp_BitMap(a1),a0
        moveq   #0,d6
        move.b  bm_Depth(a0),d6
        rts

; gel_save(a2 = vs, a3 = bob, a1 = rp) : fond du rectangle (Y, X) lu pixel par pixel dans bob->SaveBuffer (plans
; du BitMap du RastPort, chacun hauteur x largeur en mots) ; BACKSAVED posé. Sans tampon : rien.
gel_save:
        movem.l d2-d7/a2-a4,-(sp)
        move.l  BOB_SAVE(a3),d0
        beq     .gs_ret
        move.l  d0,a4                ; a4 = tampon
        bsr.s   gel_geom
        move.l  d3,d0                ; tampon à zéro (profondeur x plan)
        mulu    d6,d0
        lsr.l   #1,d0
        move.l  a4,a0
        bra.s   .gs_cz
.gs_clr:
        clr.w   (a0)+
.gs_cz:
        subq.l  #1,d0
        bpl.s   .gs_clr
        moveq   #0,d7                ; d7 = ligne
.gs_row:
        cmp.w   d4,d7
        bge.s   .gs_done
        moveq   #0,d2                ; d2 = colonne
.gs_px:
        cmp.w   d5,d2
        bge.s   .gs_nr
        move.w  VS_X(a2),d0
        add.w   d2,d0
        move.w  VS_Y(a2),d1
        add.w   d7,d1
        jsr     gfx_ReadPixel
        tst.l   d0
        bmi.s   .gs_nxp              ; hors de toute zone visible : 0
        bsr     gel_putbits
.gs_nxp:
        addq.w  #1,d2
        bra.s   .gs_px
.gs_nr:
        addq.w  #1,d7
        bra.s   .gs_row
.gs_done:
        bset    #VSB_BACKSAVED-8,VS_FLAGS(a2)
.gs_ret:
        movem.l (sp)+,d2-d7/a2-a4
        rts
; gel_putbits(d0 = couleur, d2 = colonne, d7 = ligne, a4 = tampon planaire, d3 = octets d'un plan, d6 = plans,
; VS_WIDTH(a2)) : pose les bits de la couleur dans chaque plan du tampon. Clobbe d0/d1/a0.
gel_putbits:
        movem.l d4-d5,-(sp)
        move.w  d7,d1
        mulu    VS_WIDTH(a2),d1
        add.l   d1,d1                ; octet de début de la ligne dans un plan
        move.w  d2,d4
        lsr.w   #3,d4
        add.l   d4,d1                ; octet du pixel
        move.w  d2,d4
        not.w   d4
        and.w   #7,d4                ; bit du pixel
        lea     0(a4,d1.l),a0
        move.w  d6,d5
        bra.s   .pb_nx
.pb_pl:
        lsr.w   #1,d0
        bcc.s   .pb_z
        bset    d4,(a0)
.pb_z:
        add.l   d3,a0
.pb_nx:
        dbra    d5,.pb_pl
        movem.l (sp)+,d4-d5
        rts

; gel_unsave(a2 = vs, a3 = bob, a1 = rp) : si BACKSAVED, le fond sauvé est reposé à (OldY, OldX) ; BACKSAVED effacé.
gel_unsave:
        bclr    #VSB_BACKSAVED-8,VS_FLAGS(a2)
        beq.s   .gu_r
        movem.l d2-d7/a2-a4,-(sp)
        move.l  BOB_SAVE(a3),d0
        beq.s   .gu_ret
        move.l  d0,a4
        bsr     gel_geom
        lea     -GEL_CHUNK(sp),sp
        moveq   #0,d7                ; ligne
.gu_row:
        cmp.w   d4,d7
        bge.s   .gu_done
        moveq   #0,d2                ; début du morceau
.gu_ch:
        cmp.w   d5,d2
        bge.s   .gu_nr
        moveq   #0,d0                ; d0 = pixels de ce morceau
        move.w  d5,d0
        sub.w   d2,d0
        cmp.w   #GEL_CHUNK,d0
        ble.s   .gu_n
        moveq   #GEL_CHUNK,d0
.gu_n:
        move.w  d0,-(sp)
        lea     2(sp),a0
        bsr     gel_getbits          ; couleurs du tampon -> morceau
        move.w  (sp)+,d0
        move.w  d2,-(sp)
        move.w  d0,-(sp)
        lea     4(sp),a0
        move.w  VS_OLDX(a2),d0
        add.w   d2,d0
        move.w  VS_OLDY(a2),d1
        add.w   d7,d1
        move.w  (sp),d2
        jsr     gfx_putrow
        move.w  (sp)+,d0
        move.w  (sp)+,d2
        add.w   d0,d2
        bra.s   .gu_ch
.gu_nr:
        addq.w  #1,d7
        bra.s   .gu_row
.gu_done:
        lea     GEL_CHUNK(sp),sp
.gu_ret:
        movem.l (sp)+,d2-d7/a2-a4
.gu_r:
        rts
; gel_getbits(a0 = morceau, d0.w = nombre, d2 = première colonne, d7 = ligne, a4 = tampon, d3, d6, a2) : couleur
; de chaque pixel du morceau reconstituée depuis les plans du tampon. Préserve d2-d7.
gel_getbits:
        movem.l d2-d7/a1,-(sp)
        move.l  a0,a1
        move.w  d0,d5                ; d5 = compteur
        bra.s   .gb_nx
.gb_px:
        move.w  d7,d1
        mulu    VS_WIDTH(a2),d1
        add.l   d1,d1
        move.w  d2,d4
        lsr.w   #3,d4
        add.l   d4,d1
        move.w  d2,d4
        not.w   d4
        and.w   #7,d4
        lea     0(a4,d1.l),a0
        move.l  d3,d1
        mulu    d6,d1                ; (d3 tient sur 16 bits pour un Bob raisonnable)
        add.l   d1,a0                ; après le dernier plan, on remonte
        moveq   #0,d0
        move.w  d6,d1
        bra.s   .gb_pn
.gb_pl:
        sub.l   d3,a0
        add.b   d0,d0
        btst    d4,(a0)
        beq.s   .gb_pn
        addq.b  #1,d0
.gb_pn:
        dbra    d1,.gb_pl
        move.b  d0,(a1)+
        addq.w  #1,d2
.gb_nx:
        dbra    d5,.gb_px
        movem.l (sp)+,d2-d7/a1
        rts

; gel_draw(a2 = vs, a3 = bob, a1 = rp) : image posée à (Y, X). Pixel du masque (OVERLAY : bob->ImageShadow, à
; défaut OU des plans de l'image ; sinon tout le rectangle) : pour chaque plan du BitMap, bit du plan d'image
; suivant si PlanePick le choisit, sinon bit de PlaneOnOff. Hors masque : transparent.
gel_draw:
        movem.l d2-d7/a2-a4,-(sp)
        bsr     gel_geom
        lea     -GEL_CHUNK(sp),sp
        moveq   #0,d7                ; ligne
.gd_row:
        cmp.w   d4,d7
        bge.s   .gd_done
        moveq   #0,d2
.gd_ch:
        cmp.w   d5,d2
        bge.s   .gd_nr
        moveq   #0,d0
        move.w  d5,d0
        sub.w   d2,d0
        cmp.w   #GEL_CHUNK,d0
        ble.s   .gd_n
        moveq   #GEL_CHUNK,d0
.gd_n:
        move.l  sp,a0
        bsr.s   gel_imgbits
        move.w  d2,-(sp)
        move.w  d0,-(sp)
        lea     4(sp),a0
        move.w  VS_X(a2),d0
        add.w   d2,d0
        move.w  VS_Y(a2),d1
        add.w   d7,d1
        move.w  (sp),d2
        jsr     gfx_putrow
        move.w  (sp)+,d0
        move.w  (sp)+,d2
        add.w   d0,d2
        bra.s   .gd_ch
.gd_nr:
        addq.w  #1,d7
        bra.s   .gd_row
.gd_done:
        lea     GEL_CHUNK(sp),sp
        movem.l (sp)+,d2-d7/a2-a4
        rts
; gel_imgbits(a0 = morceau, d0.w = nombre, d2 = première colonne, d7 = ligne, a2 = vs, a3 = bob, d3 = octets d'un
; plan, d6 = plans du BitMap) : couleur (ou 255) de chaque pixel. Préserve d0/d2-d7.
gel_imgbits:
        movem.l d0/d2-d7/a1/a4,-(sp)
        move.l  a0,a1
        move.w  d0,d5
        bra     .ib_nx
.ib_px:
        move.w  d7,d1                ; d1 = octet du pixel dans un plan
        mulu    VS_WIDTH(a2),d1
        add.l   d1,d1
        move.w  d2,d4
        lsr.w   #3,d4
        add.l   d4,d1
        move.w  d2,d4
        not.w   d4
        and.w   #7,d4                ; d4 = bit
        move.l  VS_IMAGE(a2),a4
        btst    #VSB_OVERLAY,VS_FLAGS+1(a2)
        beq.s   .ib_in
        move.l  BOB_SHADOW(a3),d0
        beq.s   .ib_or
        move.l  d0,a0
        btst    d4,0(a0,d1.l)
        beq.s   .ib_out
        bra.s   .ib_in
.ib_or:
        lea     0(a4,d1.l),a0        ; pas d'ombre : OU des plans de l'image
        move.w  VS_DEPTH(a2),d0
        bra.s   .ib_on
.ib_ol:
        btst    d4,(a0)
        bne.s   .ib_in
        add.l   d3,a0
.ib_on:
        dbra    d0,.ib_ol
.ib_out:
        st      (a1)+
        bra.s   .ib_np
.ib_in:
        lea     0(a4,d1.l),a0        ; a0 = plan d'image courant
        moveq   #0,d0                ; couleur
        moveq   #0,d1                ; n° de plan du BitMap
        swap    d5
        move.w  VS_DEPTH(a2),d5      ; plans d'image restants (mot haut de d5 = compteur de pixels)
.ib_pl:
        cmp.w   d6,d1
        bge.s   .ib_put
        btst    d1,VS_PICK(a2)
        beq.s   .ib_onoff
        subq.w  #1,d5
        bmi.s   .ib_npl              ; plus de plan d'image : bit 0
        btst    d4,(a0)
        beq.s   .ib_np0
        bset    d1,d0
.ib_np0:
        add.l   d3,a0
        bra.s   .ib_npl
.ib_onoff:
        btst    d1,VS_ONOFF(a2)
        beq.s   .ib_npl
        bset    d1,d0
.ib_npl:
        addq.w  #1,d1
        bra.s   .ib_pl
.ib_put:
        swap    d5
        move.b  d0,(a1)+
.ib_np:
        addq.w  #1,d2
.ib_nx:
        dbra    d5,.ib_px
        movem.l (sp)+,d0/d2-d7/a1/a4
        rts

; ---------------------------------------------------------------------------------------------------------------
; InitMasks(vs a0) : CollMask = OU des plans de l'image ligne par ligne (VSprite matériel : les deux mots
; entrelacés de chaque ligne) ; BorderLine = OU de toutes les lignes du CollMask. Tableau absent : ignoré.
gfx_InitMasks:
        movem.l d2-d7/a2-a4,-(sp)
        move.l  a0,a2
        move.w  VS_WIDTH(a2),d5      ; d5 = mots par ligne
        move.w  VS_HEIGHT(a2),d4
        move.l  VS_IMAGE(a2),a3
        move.l  VS_COLLMASK(a2),d0
        beq.s   .im_bl
        move.l  d0,a4
        moveq   #0,d7                ; ligne
.im_row:
        cmp.w   d4,d7
        bge.s   .im_bl
        moveq   #0,d6                ; mot
.im_w:
        cmp.w   d5,d6
        bge.s   .im_nr
        moveq   #0,d2                ; d2 = OU
        btst    #VSB_VSPRITE,VS_FLAGS+1(a2)
        beq.s   .im_bob
        move.w  d7,d0                ; VSprite : ligne = 2 x largeur mots (plan 0 puis plan 1)
        mulu    d5,d0
        add.w   d0,d0
        add.w   d6,d0
        add.w   d0,d0
        or.w    0(a3,d0.w),d2
        move.w  d5,d1
        add.w   d1,d1
        add.w   d1,d0
        or.w    0(a3,d0.w),d2
        bra.s   .im_put
.im_bob:
        move.w  d4,d3                ; d3 = mots d'un plan
        mulu    d5,d3
        add.l   d3,d3                ; octets d'un plan
        move.w  d7,d0
        mulu    d5,d0
        add.w   d6,d0
        add.l   d0,d0
        lea     0(a3,d0.l),a0
        move.w  VS_DEPTH(a2),d1
        bra.s   .im_pn
.im_pl:
        or.w    (a0),d2
        add.l   d3,a0
.im_pn:
        dbra    d1,.im_pl
.im_put:
        move.w  d7,d0
        mulu    d5,d0
        add.w   d6,d0
        add.l   d0,d0
        move.w  d2,0(a4,d0.l)
        addq.w  #1,d6
        bra.s   .im_w
.im_nr:
        addq.w  #1,d7
        bra.s   .im_row
.im_bl:
        move.l  VS_BORDER(a2),d0
        beq.s   .im_ret
        move.l  VS_COLLMASK(a2),d1
        beq.s   .im_ret
        move.l  d0,a0
        moveq   #0,d6
.im_bw:
        cmp.w   d5,d6
        bge.s   .im_ret
        moveq   #0,d2
        move.l  d1,a4
        move.w  d6,d0
        add.w   d0,d0
        add.w   d0,a4
        move.w  d4,d7
        bra.s   .im_bn
.im_br:
        or.w    (a4),d2
        add.w   d5,a4
        add.w   d5,a4
.im_bn:
        dbra    d7,.im_br
        move.w  d2,(a0)+
        addq.w  #1,d6
        bra.s   .im_bw
.im_ret:
        movem.l (sp)+,d2-d7/a2-a4
        rts

; SetCollision(n° d0, routine a0, gelsInfo a1) : routine n de la collTable de la GelsInfo.
gfx_SetCollision:
        move.l  GI_COLL(a1),d1
        beq.s   .sc_r
        move.l  d1,a1
        lsl.w   #2,d0
        move.l  a0,0(a1,d0.w)
.sc_r:
        rts

; gel_call(a0 = routine, d0 = 1er argument, d1 = 2e) : appel à la convention C (arguments empilés de droite à
; gauche, retirés au retour). Préserve d2-d7/a2-a6.
gel_call:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  d1,-(sp)
        move.l  d0,-(sp)
        jsr     (a0)
        addq.l  #8,sp
        movem.l (sp)+,d2-d7/a2-a6
        rts

; DoCollision(rp a1) : pour chaque gel (ordre de la liste) : HitMask bit 0 et sortie des bornes de la GelsInfo ->
; routine 0 (gel, TOPHIT|BOTTOMHIT|LEFTHIT|RIGHTHIT) ; puis chaque gel suivant dont le rectangle chevauche et dont
; un pixel du CollMask recouvre (à défaut de CollMask : le rectangle) avec HitMask(premier) & MeMask(second) non nul
; -> routine du plus petit bit commun (premier, second).
gfx_DoCollision:
        movem.l d2-d7/a2-a5,-(sp)
        move.l  rp_GelsInfo(a1),d0
        beq     .dc_ret
        move.l  d0,a5
        move.l  GI_COLL(a5),d0
        beq     .dc_ret
        move.l  d0,a4                ; a4 = collTable
        move.l  GI_HEAD(a5),a2
.dc_lp:
        move.l  VS_NEXT(a2),a2
        tst.l   VS_NEXT(a2)
        beq     .dc_ret
        btst    #0,VS_HITMASK+1(a2)
        beq.s   .dc_pairs
        moveq   #0,d1
        move.w  VS_Y(a2),d0
        cmp.w   GI_TOP(a5),d0
        bge.s   .dc_b1
        or.w    #TOPHIT,d1
.dc_b1:
        add.w   VS_HEIGHT(a2),d0
        subq.w  #1,d0
        cmp.w   GI_BOTTOM(a5),d0
        ble.s   .dc_b2
        or.w    #BOTTOMHIT,d1
.dc_b2:
        move.w  VS_X(a2),d0
        cmp.w   GI_LEFT(a5),d0
        bge.s   .dc_b3
        or.w    #LEFTHIT,d1
.dc_b3:
        move.w  VS_WIDTH(a2),d2
        lsl.w   #4,d2
        add.w   d2,d0
        subq.w  #1,d0
        cmp.w   GI_RIGHT(a5),d0
        ble.s   .dc_b4
        or.w    #RIGHTHIT,d1
.dc_b4:
        tst.w   d1
        beq.s   .dc_pairs
        move.l  (a4),d0
        beq.s   .dc_pairs
        move.l  d0,a0
        move.l  a2,d0
        bsr     gel_call
.dc_pairs:
        move.l  a2,a3
.dc_p2:
        move.l  VS_NEXT(a3),a3
        tst.l   VS_NEXT(a3)
        beq     .dc_lp
        move.w  VS_Y(a2),d0          ; liste triée : au-delà du bas du premier, plus de chevauchement
        add.w   VS_HEIGHT(a2),d0
        cmp.w   VS_Y(a3),d0
        ble     .dc_lp
        move.w  VS_HITMASK(a2),d6
        and.w   VS_MEMASK(a3),d6
        beq.s   .dc_p2
        bsr.s   gel_overlap
        beq.s   .dc_p2
        moveq   #0,d0                ; plus petit bit commun
.dc_bit:
        btst    d0,d6
        bne.s   .dc_got
        addq.w  #1,d0
        bra.s   .dc_bit
.dc_got:
        lsl.w   #2,d0
        move.l  0(a4,d0.w),d0
        beq.s   .dc_p2
        move.l  d0,a0
        move.l  a2,d0
        move.l  a3,d1
        bsr     gel_call
        bra.s   .dc_p2
.dc_ret:
        movem.l (sp)+,d2-d7/a2-a5
        rts

; gel_overlap(a2, a3 = VSprites) : Z = 0 si leurs rectangles se chevauchent et (CollMasks présents) qu'un pixel
; est commun aux deux masques. Préserve d6/a2-a5.
gel_overlap:
        movem.l d2-d7,-(sp)
        move.w  VS_X(a2),d2          ; x commun [d2 .. d3], y commun [d4 .. d5]
        move.w  VS_X(a3),d0
        cmp.w   d0,d2
        bge.s   .ov_1
        move.w  d0,d2
.ov_1:
        move.w  VS_WIDTH(a2),d3
        lsl.w   #4,d3
        add.w   VS_X(a2),d3
        move.w  VS_WIDTH(a3),d0
        lsl.w   #4,d0
        add.w   VS_X(a3),d0
        cmp.w   d0,d3
        ble.s   .ov_2
        move.w  d0,d3
.ov_2:
        subq.w  #1,d3
        move.w  VS_Y(a2),d4
        move.w  VS_Y(a3),d0
        cmp.w   d0,d4
        bge.s   .ov_3
        move.w  d0,d4
.ov_3:
        move.w  VS_Y(a2),d5
        add.w   VS_HEIGHT(a2),d5
        move.w  VS_Y(a3),d0
        add.w   VS_HEIGHT(a3),d0
        cmp.w   d0,d5
        ble.s   .ov_4
        move.w  d0,d5
.ov_4:
        subq.w  #1,d5
        cmp.w   d3,d2
        bgt.s   .ov_no
        cmp.w   d5,d4
        bgt.s   .ov_no
        tst.l   VS_COLLMASK(a2)
        beq.s   .ov_yes
        tst.l   VS_COLLMASK(a3)
        beq.s   .ov_yes
.ov_y:
        move.w  d2,d7                ; pixel par pixel
.ov_x:
        move.l  a2,a0
        bsr.s   .ov_bit
        beq.s   .ov_nx
        move.l  a3,a0
        bsr.s   .ov_bit
        bne.s   .ov_yes
.ov_nx:
        addq.w  #1,d7
        cmp.w   d3,d7
        ble.s   .ov_x
        addq.w  #1,d4
        cmp.w   d5,d4
        ble.s   .ov_y
.ov_no:
        moveq   #0,d0
        bra.s   .ov_ret
.ov_yes:
        moveq   #1,d0
.ov_ret:
        movem.l (sp)+,d2-d7
        rts
; .ov_bit(a0 = vs, d7 = x, d4 = y absolus) : Z = 0 si le bit du CollMask est posé. Clobbe d0/d1/a0.
.ov_bit:
        move.w  d4,d0
        sub.w   VS_Y(a0),d0
        mulu    VS_WIDTH(a0),d0
        add.l   d0,d0
        moveq   #0,d1
        move.w  d7,d1
        sub.w   VS_X(a0),d1
        move.l  d1,-(sp)
        lsr.w   #3,d1
        add.l   d1,d0
        move.l  VS_COLLMASK(a0),a0
        add.l   d0,a0
        move.l  (sp)+,d1
        not.w   d1
        and.w   #7,d1
        btst    d1,(a0)
        rts

; ---------------------------------------------------------------------------------------------------------------
; AddAnimOb(anOb a0, anKey a1, rp a2) : l'objet entre en tête de la liste *anKey ; horloge à 0 ; le Bob de chaque
; composant actif (chaîne NextComp) est ajouté, positionné, minuteur armé (TimeSet).
gfx_AddAnimOb:
        movem.l a2-a4,-(sp)
        move.l  a0,a3
        move.l  (a1),d0
        move.l  d0,AO_NEXT(a3)
        clr.l   AO_PREV(a3)
        tst.l   d0
        beq.s   .aa_first
        move.l  d0,a0
        move.l  a3,AO_PREV(a0)
.aa_first:
        move.l  a3,(a1)
        clr.l   AO_CLOCK(a3)
        move.l  AO_Y(a3),AO_OLDY(a3)
        move.l  AO_HEADCOMP(a3),a4
.aa_lp:
        cmpa.w  #0,a4
        beq.s   .aa_ret
        move.l  a3,AC_HEADOB(a4)
        move.w  AC_TIMESET(a4),AC_TIMER(a4)
        bsr     anim_place
        move.l  AC_BOB(a4),a0
        move.l  a2,a1
        bsr     gfx_AddBob
        move.l  AC_NEXTCOMP(a4),a4
        bra.s   .aa_lp
.aa_ret:
        movem.l (sp)+,a2-a4
        rts

; anim_place(a3 = anOb, a4 = comp) : position du VSprite du composant = position de l'objet (partie entière) +
; translation du composant. Clobbe d0/a0.
anim_place:
        move.l  AC_BOB(a4),a0
        move.l  BOB_VS(a0),a0
        move.w  AO_Y(a3),d0
        asr.w   #ANFRACSIZE,d0
        add.w   AC_YTRANS(a4),d0
        move.w  d0,VS_Y(a0)
        move.w  AO_X(a3),d0
        asr.w   #ANFRACSIZE,d0
        add.w   AC_XTRANS(a4),d0
        move.w  d0,VS_X(a0)
        rts

; Animate(anKey a0, rp a1) : pour chaque objet : horloge + 1, vitesse += accélération, position += vitesse,
; routine de l'objet ; pour chaque composant actif : minuteur décompté (TimeSet non nul) ; à zéro, le composant
; NextSeq le remplace dans la chaîne (ancien Bob marqué BOBSAWAY, nouveau Bob ajouté, minuteur réarmé ;
; RINGTRIGGER : translation d'anneau ajoutée à l'objet) ; puis position du Bob et routine du composant.
gfx_Animate:
        movem.l d2-d7/a2-a5,-(sp)
        move.l  a1,a5                ; a5 = rp
        move.l  (a0),a3
.an_ob:
        cmpa.w  #0,a3
        beq     .an_ret
        addq.l  #1,AO_CLOCK(a3)
        move.l  AO_Y(a3),AO_OLDY(a3)
        move.w  AO_YACC(a3),d0
        add.w   d0,AO_YVEL(a3)
        move.w  AO_XACC(a3),d0
        add.w   d0,AO_XVEL(a3)
        move.w  AO_YVEL(a3),d0
        add.w   d0,AO_Y(a3)
        move.w  AO_XVEL(a3),d0
        add.w   d0,AO_X(a3)
        move.l  AO_ROUTINE(a3),d0
        beq.s   .an_comps
        move.l  d0,a0
        move.l  a3,d0
        moveq   #0,d1
        bsr     gel_call
.an_comps:
        move.l  AO_HEADCOMP(a3),a4
.an_c:
        cmpa.w  #0,a4
        beq     .an_nob
        move.l  AC_NEXTCOMP(a4),d7   ; d7 = composant suivant de la chaîne
        tst.w   AC_TIMESET(a4)
        beq.s   .an_pos
        subq.w  #1,AC_TIMER(a4)
        bgt.s   .an_pos
        move.l  AC_NEXTSEQ(a4),d0
        beq.s   .an_pos
        cmp.l   a4,d0
        beq.s   .an_rearm
        move.l  d0,a2                ; a2 = nouveau composant
        move.l  AC_BOB(a4),a0        ; RemBob de l'ancien
        bset    #BB_BOBSAWAY-8,BOB_FLAGS(a0)
        move.l  AC_PREVCOMP(a4),d0
        move.l  d0,AC_PREVCOMP(a2)
        beq.s   .an_head
        move.l  d0,a0
        move.l  a2,AC_NEXTCOMP(a0)
        bra.s   .an_lnk
.an_head:
        move.l  a2,AO_HEADCOMP(a3)
.an_lnk:
        move.l  d7,AC_NEXTCOMP(a2)
        beq.s   .an_lnk2
        move.l  d7,a0
        move.l  a2,AC_PREVCOMP(a0)
.an_lnk2:
        move.l  a3,AC_HEADOB(a2)
        move.w  AC_TIMESET(a2),AC_TIMER(a2)
        move.w  AC_FLAGS(a2),d0
        and.w   #RINGTRIGGER,d0
        beq.s   .an_add
        move.w  AO_RINGY(a3),d0
        add.w   d0,AO_Y(a3)
        move.w  AO_RINGX(a3),d0
        add.w   d0,AO_X(a3)
.an_add:
        move.l  a2,a4
        bsr     anim_place
        move.l  AC_BOB(a4),a0
        move.l  a5,a1
        bsr     gfx_AddBob
        bra.s   .an_pos
.an_rearm:
        move.w  AC_TIMESET(a4),AC_TIMER(a4)
.an_pos:
        bsr     anim_place
        move.l  AC_ROUTINE(a4),d0
        beq.s   .an_cn
        move.l  d0,a0
        move.l  a4,d0
        moveq   #0,d1
        bsr     gel_call
.an_cn:
        move.l  d7,a4
        bra     .an_c
.an_nob:
        move.l  AO_NEXT(a3),a3
        bra     .an_ob
.an_ret:
        movem.l (sp)+,d2-d7/a2-a5
        rts

; anim_forall(a0 = anOb, a3 = action) : appelle l'action (a4 = composant) pour chaque composant de chaque séquence
; (anneau NextSeq parcouru jusqu'au retour ou jusqu'à 0). L'action rend Z = 0 pour arrêter (échec). d0 = 1 si tout
; a réussi. Préserve d2-d7/a2-a6.
anim_forall:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  AO_HEADCOMP(a0),a2
.fa_c:
        cmpa.w  #0,a2
        beq.s   .fa_ok
        move.l  a2,a4
.fa_s:
        move.l  a2,-(sp)             ; l'action peut utiliser a2
        jsr     (a3)
        movem.l (sp)+,a2             ; movem laisse les codes conditions de l'action
        bne.s   .fa_ko
        move.l  AC_NEXTSEQ(a4),a4
        cmpa.w  #0,a4
        beq.s   .fa_nc
        cmpa.l  a2,a4
        bne.s   .fa_s
.fa_nc:
        move.l  AC_NEXTCOMP(a2),a2
        bra.s   .fa_c
.fa_ok:
        moveq   #1,d0
        bra.s   .fa_ret
.fa_ko:
        moveq   #0,d0
.fa_ret:
        movem.l (sp)+,d2-d7/a2-a6
        rts

; InitGMasks(anOb a0) : InitMasks de chaque composant de chaque séquence.
gfx_InitGMasks:
        move.l  a3,-(sp)
        lea     gm_one(pc),a3
        bsr.s   anim_forall
        move.l  (sp)+,a3
        rts
gm_one:
        move.l  AC_BOB(a4),a0
        move.l  BOB_VS(a0),a0
        bsr     gfx_InitMasks
        moveq   #0,d0                ; Z = 1 : continuer
        rts

; GetGBuffers(anOb a0, rp a1, db d0) -> d0 = TRUE si chaque composant a reçu ses tampons : ImageShadow et
; SaveBuffer (chip), CollMask et BorderLine, et en double tampon un DBufPacket avec son BufBuffer (chip). En cas
; d'échec, FreeGBuffers rend ce qui a été obtenu.
gfx_GetGBuffers:
        movem.l d2-d3/a3/a5,-(sp)
        move.w  d0,d3                ; d3 = double tampon
        move.l  rp_BitMap(a1),a5
        moveq   #0,d2
        move.b  bm_Depth(a5),d2      ; d2 = profondeur
        lea     gb_one(pc),a3
        bsr.s   anim_forall
        movem.l (sp)+,d2-d3/a3/a5
        rts
; gb_one(a4 = composant, d2 = profondeur, d3 = double tampon) : Z = 0 si une allocation échoue.
gb_one:
        move.l  AC_BOB(a4),a2
        move.l  BOB_VS(a2),a5
        bsr     gb_sizes             ; d4 = plan, d5 = largeur en octets
        move.l  d4,d0
        move.l  #MEMF_CHIP|MEMF_CLEAR,d1
        bsr     gb_alloc
        move.l  d0,BOB_SHADOW(a2)
        beq.s   .go_ko
        move.l  d4,d0
        move.l  #MEMF_PUBLIC|MEMF_CLEAR,d1
        bsr.s   gb_alloc
        move.l  d0,VS_COLLMASK(a5)
        beq.s   .go_ko
        move.l  d5,d0
        move.l  #MEMF_PUBLIC|MEMF_CLEAR,d1
        bsr.s   gb_alloc
        move.l  d0,VS_BORDER(a5)
        beq.s   .go_ko
        move.l  d4,d0
        mulu    d2,d0
        move.l  #MEMF_CHIP|MEMF_CLEAR,d1
        bsr.s   gb_alloc
        move.l  d0,BOB_SAVE(a2)
        beq.s   .go_ko
        tst.w   d3
        beq.s   .go_ok
        moveq   #DB_SIZE,d0
        move.l  #MEMF_PUBLIC|MEMF_CLEAR,d1
        bsr.s   gb_alloc
        move.l  d0,BOB_DBUF(a2)
        beq.s   .go_ko
        move.l  d0,a0
        move.l  a0,-(sp)
        move.l  d4,d0
        mulu    d2,d0
        move.l  #MEMF_CHIP|MEMF_CLEAR,d1
        bsr.s   gb_alloc
        move.l  (sp)+,a0
        move.l  d0,DB_BUFFER(a0)
        beq.s   .go_ko
.go_ok:
        moveq   #0,d0
        rts
.go_ko:
        moveq   #1,d0
        rts
; gb_sizes(a5 = vs) -> d4 = octets d'un plan (hauteur x largeur en mots x 2), d5 = octets d'une ligne.
gb_sizes:
        move.w  VS_WIDTH(a5),d5
        add.w   d5,d5
        move.w  VS_HEIGHT(a5),d4
        mulu    d5,d4
        ext.l   d5
        rts
; gb_alloc(d0 = taille, d1 = exigences) -> d0 = bloc | 0 (Z en conséquence).
gb_alloc:
        move.l  a6,-(sp)
        move.l  ($4).w,a6
        jsr     LVO_ALLOCMEM(a6)
        move.l  (sp)+,a6
        tst.l   d0
        rts

; FreeGBuffers(anOb a0, rp a1, db d0) : rend les tampons obtenus par GetGBuffers (pointeurs remis à 0).
gfx_FreeGBuffers:
        movem.l d2-d3/a3/a5,-(sp)
        move.w  d0,d3
        move.l  rp_BitMap(a1),a5
        moveq   #0,d2
        move.b  bm_Depth(a5),d2
        lea     fb_one(pc),a3
        bsr     anim_forall
        movem.l (sp)+,d2-d3/a3/a5
        rts
fb_one:
        move.l  AC_BOB(a4),a2
        move.l  BOB_VS(a2),a5
        bsr.s   gb_sizes
        lea     BOB_SHADOW(a2),a0
        move.l  d4,d0
        bsr.s   fb_free
        lea     VS_COLLMASK(a5),a0
        move.l  d4,d0
        bsr.s   fb_free
        lea     VS_BORDER(a5),a0
        move.l  d5,d0
        bsr.s   fb_free
        lea     BOB_SAVE(a2),a0
        move.l  d4,d0
        mulu    d2,d0
        bsr.s   fb_free
        tst.w   d3
        beq.s   .fo_r
        move.l  BOB_DBUF(a2),d0
        beq.s   .fo_r
        move.l  d0,a0
        pea     BOB_DBUF(a2)
        lea     DB_BUFFER(a0),a0
        move.l  d4,d0
        mulu    d2,d0
        bsr.s   fb_free
        move.l  (sp)+,a0
        moveq   #DB_SIZE,d0
        bsr.s   fb_free
.fo_r:
        moveq   #0,d0
        rts
; fb_free(a0 = adresse du pointeur, d0 = taille) : FreeMem si non nul, pointeur remis à 0.
fb_free:
        move.l  (a0),d1
        beq.s   .ff_r
        clr.l   (a0)
        move.l  a6,-(sp)
        move.l  d1,a1
        move.l  ($4).w,a6
        jsr     LVO_FREEMEM(a6)
        move.l  (sp)+,a6
.ff_r:
        rts
