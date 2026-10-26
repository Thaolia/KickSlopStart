; src/graphics/layers.s — layers.library V34 : couches rectangulaires empilées sur un BitMap commun.
;
; Chaque couche porte une liste de ClipRects qui pave ses bornes : visibles (cr_lobs = 0, dessinées directement
; dans le BitMap commun) ou cachées (cr_lobs = la couche la plus en avant qui les recouvre). Pour une couche
; LAYERSMART, une ClipRect cachée possède un BitMap de sauvegarde (cr_BitMap) qui garde son contenu ; pour une
; couche LAYERSIMPLE elle n'a rien : la zone redécouverte est remplie au stylo 0, ajoutée à la DamageList
; (coordonnées relatives à la couche) et LAYERREFRESH est posé.
; Origine d'un BitMap de sauvegarde : (MinX & ~15, MinY) de la ClipRect qui l'a créé, rangée dans cr_p1 (deux
; mots) : la position des bits modulo 16 est la même qu'à l'écran. Les sauvegardes sont en RAM quelconque
; (MEMF_PUBLIC) : graphics les remplit au processeur.
;
; RECONSTRUCTION (lr_rebuild), après tout changement d'ordre, de bornes, de création ou de suppression :
;   1. nouvelles ClipRects de chaque couche (liste ly_crnew), calculées par soustractions de rectangles ;
;   2. phase A, écran encore intact : chaque ClipRect d'une couche smart qui doit recevoir du contenu (cachée,
;      ou visible mais déplacée / jamais visible à cet endroit) reçoit un BitMap rempli depuis les anciennes
;      ClipRects (écran à l'ancienne position, ou anciennes sauvegardes) ;
;   3. fond découvert (anciennement visible, plus couvert par aucune couche) : effacé au stylo 0 ;
;   4. phase B : écriture de l'écran — sauvegardes provisoires recopiées puis rendues, zones des couches simple
;      redécouvertes effacées et ajoutées aux dommages ;
;   5. anciennes ClipRects (et leurs sauvegardes) libérées, nouvelles listes installées.
; Les zones écrites à l'écran par la phase B et l'étape 3 sont disjointes : l'ordre n'a pas d'importance.
; Couches LAYERSUPER : traitées comme LAYERSMART (pas de SuperBitMap séparé, ScrollLayer sans effet).
; Verrous : chaque opération tient le sémaphore du Layer_Info et celui de chaque couche (LockLayers) ; graphics
; tient celui de la couche pendant un dessin.
; Piste IMPLÉMENTATION (« clean ») : AutoDocs layers.library + graphics/clip.h, layers.h, regions.h. LVO :
; ordre de l'AutoDoc, recoupé avec une unité Pascal publique (layers.pas). AUCUNE lecture ROM.

                include "exec.i"
                include "graphics.i"

                xref    rl_add
                xref    rl_sub
                xref    rl_and
                xref    rl_free

; --- struct Layer (graphics/clip.h) ---
LY_FRONT        EQU 0
LY_BACK         EQU 4
LY_CLIPRECT     EQU 8
LY_RP           EQU 12
LY_MINX         EQU 16
LY_MINY         EQU 18
LY_MAXX         EQU 20
LY_MAXY         EQU 22
LY_FLAGS        EQU 30
LY_SUPERBM      EQU 32
LY_CRNEW        EQU 56               ; liste en construction (champ privé « crnew »)
LY_SAVECR       EQU 64               ; « _cliprects » : liste normale pendant BeginUpdate
LY_LAYERINFO    EQU 68
LY_LOCK         EQU 72               ; struct SignalSemaphore
LY_OLDX         EQU 138              ; reserved2 : position avant l'opération en cours
LY_OLDY         EQU 140
LY_NEW          EQU 142              ; byte : couche créée par l'opération en cours
LY_CLIPREGION   EQU 126              ; struct Region * : région de découpe de l'application (InstallClipRegion)
LY_DAMAGE       EQU 156              ; struct Region *
LY_SIZE         EQU 160
LAYERSIMPLE     EQU 1
LAYERSMART      EQU 2
LAYERSUPER      EQU 4
LAYERUPDATING   EQU $10
LAYERBACKDROP   EQU $40
LAYERREFRESH    EQU $80
LAYER_CLIPRECTS_LOST EQU $0100       ; liste réduite incomplète (mémoire insuffisante)
; --- struct ClipRect ---
CR_NEXT         EQU 0
CR_PREV         EQU 4
CR_LOBS         EQU 8
CR_BITMAP       EQU 12
CR_MINX         EQU 16
CR_MINY         EQU 18
CR_MAXX         EQU 20
CR_MAXY         EQU 22
CR_ORGX         EQU 24               ; _p1 : origine (X, Y) du BitMap de sauvegarde
CR_ORGY         EQU 26
CR_FLAGS        EQU 36               ; privé : CRF_TEMP / CRF_BORROWED
CR_SIZE         EQU 40
CRF_TEMP        EQU 1                ; sauvegarde provisoire (phase A -> B)
CRF_BORROWED    EQU 2                ; BitMap appartenant à une autre ClipRect (liste de BeginUpdate)
CRF_EXPOSE      EQU 4                ; visible, en place, en partie découverte : recopie directe en phase B
; --- struct Layer_Info ---
LI_TOP          EQU 0
LI_LOCK         EQU 24
LI_GSHEAD       EQU 70
LI_FLAGS        EQU 88
LI_LOCKCNT      EQU 91               ; byte : niveau d'imbrication de LockLayers
LI_SIZE         EQU 102
NEWLAYERINFO_CALLED EQU 1
; --- nœud de liste de rectangles (RegionRectangle) ---
RR_NEXT         EQU 0
RR_MINX         EQU 8
RR_SIZE         EQU 16
; --- base de la bibliothèque ---
LB_GFX          EQU LIB_SIZE
LB_SIZE         EQU LIB_SIZE+4

LVO_BLTBITMAP_G EQU -30
LVO_INITRASTPORT_G EQU -198
LVO_ORRECTREGION_G EQU -510
LVO_NEWREGION_G EQU -516
LVO_CLEARREGION_G EQU -528
LVO_DISPOSEREGION_G EQU -534

        EVEN
layers_romtag:
        dc.w    RTC_MATCHWORD
        dc.l    layers_romtag
        dc.l    layers_end
        dc.b    RTF_AUTOINIT|RTF_COLDSTART,34,NT_LIBRARY,31
        dc.l    layers_name
        dc.l    layers_name
        dc.l    layers_inittab
layers_name:
        dc.b    "layers.library",0
lb_gfxname:
        dc.b    "graphics.library",0
        EVEN
layers_inittab:
        dc.l    LB_SIZE
        dc.l    layers_vectors
        dc.l    layers_datatab
        dc.l    layers_initfunc
layers_vectors:
        dc.l    ly_open              ; -6
        dc.l    ly_close             ; -12
        dc.l    ly_null              ; -18
        dc.l    ly_null              ; -24
        dc.l    ly_InitLayers        ; -30
        dc.l    ly_CreateUpfrontLayer ; -36
        dc.l    ly_CreateBehindLayer ; -42
        dc.l    ly_UpfrontLayer      ; -48
        dc.l    ly_BehindLayer       ; -54
        dc.l    ly_MoveLayer         ; -60
        dc.l    ly_SizeLayer         ; -66
        dc.l    ly_ScrollLayer       ; -72
        dc.l    ly_BeginUpdate       ; -78
        dc.l    ly_EndUpdate         ; -84
        dc.l    ly_DeleteLayer       ; -90
        dc.l    ly_LockLayer         ; -96
        dc.l    ly_UnlockLayer       ; -102
        dc.l    ly_LockLayers        ; -108
        dc.l    ly_UnlockLayers      ; -114
        dc.l    ly_LockLayerInfo     ; -120
        dc.l    ly_SwapBitsRastPortClipRect ; -126
        dc.l    ly_WhichLayer        ; -132
        dc.l    ly_UnlockLayerInfo   ; -138
        dc.l    ly_NewLayerInfo      ; -144
        dc.l    ly_DisposeLayerInfo  ; -150
        dc.l    ly_FattenLayerInfo   ; -156
        dc.l    ly_ThinLayerInfo     ; -162
        dc.l    ly_MoveLayerInFrontOf ; -168
        dc.l    ly_InstallClipRegion ; -174
        dc.l    -1
layers_datatab:
        dc.w    $E000,LN_TYPE,(NT_LIBRARY<<8)
        dc.w    $D000,LIB_VERSION,34
        dc.b    0
        EVEN

; initFunc (d0 = base, a6 = SysBase) : nom, GfxBase (graphics, pri 65, est déjà là).
layers_initfunc:
        move.l  a2,-(sp)
        move.l  d0,a2
        lea     layers_name(pc),a0
        move.l  a0,LN_NAME(a2)
        lea     lb_gfxname(pc),a1
        moveq   #0,d0
        jsr     LVO_OPENLIBRARY(a6)
        move.l  d0,LB_GFX(a2)
        move.l  a2,d0
        move.l  (sp)+,a2
        rts

ly_open:
        addq.w  #1,LIB_OPENCNT(a6)
        move.l  a6,d0
        rts
ly_close:
        subq.w  #1,LIB_OPENCNT(a6)
ly_null:
        moveq   #0,d0
        rts

; ============================ Layer_Info et verrous ============================

; InitLayers(li a0) : Layer_Info vide, sémaphore initialisé.
ly_InitLayers:
        move.l  a6,-(sp)
        move.l  a0,a1
        moveq   #LI_SIZE/2-1,d0
.il_clr:
        clr.w   (a1)+
        dbra    d0,.il_clr
        move.l  a0,-(sp)
        lea     LI_LOCK(a0),a0
        move.l  ($4).w,a6
        jsr     LVO_INITSEMAPHORE(a6)
        move.l  (sp)+,a0
        lea     LI_GSHEAD+4(a0),a1   ; MinList vide
        move.l  a1,LI_GSHEAD(a0)
        clr.l   LI_GSHEAD+4(a0)
        lea     LI_GSHEAD(a0),a1
        move.l  a1,LI_GSHEAD+8(a0)
        move.l  (sp)+,a6
        rts

; NewLayerInfo() -> d0 = Layer_Info prêt, ou 0.
ly_NewLayerInfo:
        movem.l a2/a6,-(sp)
        move.l  a6,a2
        move.l  ($4).w,a6
        moveq   #LI_SIZE,d0
        move.l  #MEMF_PUBLIC|MEMF_CLEAR,d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.s   .nl_r
        move.l  d0,-(sp)
        move.l  d0,a0
        move.l  a2,a6
        bsr     ly_InitLayers
        move.l  (sp)+,d0
        move.l  d0,a0
        or.w    #NEWLAYERINFO_CALLED,LI_FLAGS(a0)
.nl_r:
        movem.l (sp)+,a2/a6
        rts

; DisposeLayerInfo(li a0).
ly_DisposeLayerInfo:
        move.l  a6,-(sp)
        move.l  a0,a1
        moveq   #LI_SIZE,d0
        move.l  ($4).w,a6
        jsr     LVO_FREEMEM(a6)
        move.l  (sp)+,a6
        rts

; FattenLayerInfo(li a0) -> TRUE ; ThinLayerInfo(li a0) : rien à ajouter ni retirer ici.
ly_FattenLayerInfo:
        moveq   #-1,d0
        rts
ly_ThinLayerInfo:
        rts

; LockLayerInfo(li a0) / UnlockLayerInfo(li a0).
ly_LockLayerInfo:
        lea     LI_LOCK(a0),a0
        bra     ly_obtain
ly_UnlockLayerInfo:
        lea     LI_LOCK(a0),a0
        bra     ly_release
; LockLayer(dummy a0, l a1) / UnlockLayer(l a0).
ly_LockLayer:
        lea     LY_LOCK(a1),a0
ly_obtain:
        move.l  a6,-(sp)
        move.l  ($4).w,a6
        jsr     LVO_OBTAINSEMAPHORE(a6)
        move.l  (sp)+,a6
        rts
ly_UnlockLayer:
        lea     LY_LOCK(a0),a0
ly_release:
        move.l  a6,-(sp)
        move.l  ($4).w,a6
        jsr     LVO_RELEASESEMAPHORE(a6)
        move.l  (sp)+,a6
        rts

; LockLayers(li a0) : Layer_Info puis chaque couche, de l'avant vers l'arrière. Au premier niveau, la liste réduite
; de chaque couche qui a une ClipRegion est défaite : les opérations de couches travaillent sur les listes normales.
ly_LockLayers:
        movem.l a2-a4,-(sp)
        move.l  a0,a3
        bsr     ly_LockLayerInfo
        move.l  LI_TOP(a3),a2
.ll_lp:
        cmpa.w  #0,a2
        beq.s   .ll_cnt
        lea     LY_LOCK(a2),a0
        bsr     ly_obtain
        move.l  LY_BACK(a2),a2
        bra.s   .ll_lp
.ll_cnt:
        addq.b  #1,LI_LOCKCNT(a3)
        cmp.b   #1,LI_LOCKCNT(a3)
        bne.s   .ll_r
        move.l  LI_TOP(a3),a4
.ll_reg:
        cmpa.w  #0,a4
        beq.s   .ll_r
        tst.l   LY_CLIPREGION(a4)
        beq.s   .ll_rn
        bsr     lr_unclip
.ll_rn:
        move.l  LY_BACK(a4),a4
        bra.s   .ll_reg
.ll_r:
        movem.l (sp)+,a2-a4
        rts
; UnlockLayers(li a0). Au dernier niveau, la liste réduite de chaque couche qui a une ClipRegion est reconstruite
; sur le nouvel arrangement.
ly_UnlockLayers:
        movem.l a2/a4,-(sp)
        move.l  a0,-(sp)
        subq.b  #1,LI_LOCKCNT(a0)
        bne.s   .ul_go
        move.l  LI_TOP(a0),a4
.ul_reg:
        cmpa.w  #0,a4
        beq.s   .ul_go
        tst.l   LY_CLIPREGION(a4)
        beq.s   .ul_rn
        bsr     lr_unclip            ; (région installée pendant le verrou par la même tâche)
        bsr     lr_clip
.ul_rn:
        move.l  LY_BACK(a4),a4
        bra.s   .ul_reg
.ul_go:
        move.l  (sp),a0
        move.l  LI_TOP(a0),a2
.ul_lp:
        cmpa.w  #0,a2
        beq.s   .ul_li
        lea     LY_LOCK(a2),a0
        bsr     ly_release
        move.l  LY_BACK(a2),a2
        bra.s   .ul_lp
.ul_li:
        move.l  (sp)+,a0
        bsr     ly_UnlockLayerInfo
        movem.l (sp)+,a2/a4
        rts

; WhichLayer(li a0, x d0, y d1) -> d0 = couche la plus en avant contenant le point, ou 0.
ly_WhichLayer:
        move.l  LI_TOP(a0),a0
.wl_lp:
        cmpa.w  #0,a0
        beq.s   .wl_no
        cmp.w   LY_MINX(a0),d0
        blt.s   .wl_next
        cmp.w   LY_MAXX(a0),d0
        bgt.s   .wl_next
        cmp.w   LY_MINY(a0),d1
        blt.s   .wl_next
        cmp.w   LY_MAXY(a0),d1
        bgt.s   .wl_next
        move.l  a0,d0
        rts
.wl_next:
        move.l  LY_BACK(a0),a0
        bra.s   .wl_lp
.wl_no:
        moveq   #0,d0
        rts

; ============================ ordre des couches ============================
; Une couche LAYERBACKDROP reste toujours derrière les autres.

; lr_unlink(a4 = couche) : la retire de la pile de son Layer_Info.
lr_unlink:
        move.l  LY_LAYERINFO(a4),a0
        move.l  LY_FRONT(a4),d0
        move.l  LY_BACK(a4),d1
        tst.l   d0
        bne.s   .un_f
        move.l  d1,LI_TOP(a0)
        bra.s   .un_b
.un_f:
        move.l  d0,a1
        move.l  d1,LY_BACK(a1)
.un_b:
        tst.l   d1
        beq.s   .un_r
        move.l  d1,a1
        move.l  d0,LY_FRONT(a1)
.un_r:
        clr.l   LY_FRONT(a4)
        clr.l   LY_BACK(a4)
        rts

; lr_insert(a4 = couche, a0 = couche devant laquelle l'insérer, 0 = tout à l'arrière).
lr_insert:
        move.l  LY_LAYERINFO(a4),a1
        cmpa.w  #0,a0
        bne.s   .in_before
        move.l  LI_TOP(a1),d0        ; à l'arrière : après la dernière
        bne.s   .in_last
        move.l  a4,LI_TOP(a1)
        rts
.in_last:
        move.l  d0,a0
.in_lp:
        tst.l   LY_BACK(a0)
        beq.s   .in_tail
        move.l  LY_BACK(a0),a0
        bra.s   .in_lp
.in_tail:
        move.l  a4,LY_BACK(a0)
        move.l  a0,LY_FRONT(a4)
        rts
.in_before:
        move.l  LY_FRONT(a0),d0
        move.l  d0,LY_FRONT(a4)
        move.l  a0,LY_BACK(a4)
        move.l  a4,LY_FRONT(a0)
        tst.l   d0
        bne.s   .in_mid
        move.l  a4,LI_TOP(a1)
        rts
.in_mid:
        move.l  d0,a0
        move.l  a4,LY_BACK(a0)
        rts

; lr_frontpos(a4 = couche hors pile) -> a0 = couche devant laquelle la placer « tout devant » : la première pour une
; couche normale, la première couche backdrop pour une backdrop (0 = à l'arrière).
lr_frontpos:
        move.l  LY_LAYERINFO(a4),a0
        move.l  LI_TOP(a0),a0
        btst    #6,LY_FLAGS+1(a4)    ; LAYERBACKDROP
        beq.s   .fp_r
        bra     lr_firstbackdrop
.fp_r:
        rts
; lr_backpos(a4) -> a0 = position « tout derrière » : première backdrop pour une couche normale, 0 pour une backdrop.
lr_backpos:
        suba.l  a0,a0
        btst    #6,LY_FLAGS+1(a4)
        bne.s   .bp_r
        move.l  LY_LAYERINFO(a4),a0
        move.l  LI_TOP(a0),a0
        bra     lr_firstbackdrop
.bp_r:
        rts
; lr_firstbackdrop(a0 = départ) -> a0 = première couche backdrop à partir de a0, ou 0.
lr_firstbackdrop:
        cmpa.w  #0,a0
        beq.s   .fb_r
        btst    #6,LY_FLAGS+1(a0)
        bne.s   .fb_r
        move.l  LY_BACK(a0),a0
        bra     lr_firstbackdrop
.fb_r:
        rts

; ============================ création / suppression ============================

; CreateUpfrontLayer(li a0, bm a1, x0 d0, y0 d1, x1 d2, y1 d3, flags d4, bm2 a2) -> d0 = couche ou 0.
ly_CreateUpfrontLayer:
        movem.l d2-d7/a2-a6,-(sp)
        moveq   #0,d7
        bra     lr_create
; CreateBehindLayer(...) : même chose, placée derrière.
ly_CreateBehindLayer:
        movem.l d2-d7/a2-a6,-(sp)
        moveq   #1,d7
; lr_create : d7 = 0 devant / 1 derrière ; registres de l'appelant déjà empilés.
lr_create:
        move.l  d7,-(sp)             ; position demandée
        move.l  a6,a5                ; a5 = LayersBase
        move.l  a0,a3                ; a3 = Layer_Info
        movem.w d0-d3,-(sp)          ; bornes
        move.l  a1,-(sp)             ; BitMap commun
        move.l  ($4).w,a6
        move.l  #LY_SIZE+rp_SIZEOF,d0
        move.l  #MEMF_PUBLIC|MEMF_CLEAR,d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .cr_fail
        move.l  d0,a4                ; a4 = couche, RastPort juste après
        move.l  (sp)+,d5             ; d5 = BitMap
        movem.w (sp)+,d0-d3
        movem.w d0-d3,LY_MINX(a4)
        move.w  d0,LY_OLDX(a4)
        move.w  d1,LY_OLDY(a4)
        move.b  #1,LY_NEW(a4)
        move.w  d4,LY_FLAGS(a4)
        move.l  a2,LY_SUPERBM(a4)
        move.l  a3,LY_LAYERINFO(a4)
        lea     LY_LOCK(a4),a0
        jsr     LVO_INITSEMAPHORE(a6)
        move.l  LB_GFX(a5),a6
        jsr     LVO_NEWREGION_G(a6)
        move.l  d0,LY_DAMAGE(a4)
        lea     LY_SIZE(a4),a1
        move.l  a1,LY_RP(a4)
        jsr     LVO_INITRASTPORT_G(a6)
        move.l  LY_RP(a4),a1
        move.l  a4,rp_Layer(a1)
        move.l  d5,rp_BitMap(a1)
        move.l  a3,a0
        bsr     ly_LockLayers
        move.l  (sp)+,d7
        tst.l   d7
        bne.s   .cr_back
        bsr     lr_frontpos
        bra.s   .cr_ins
.cr_back:
        bsr     lr_backpos
.cr_ins:
        bsr     lr_insert
        lea     LY_LOCK(a4),a0       ; la nouvelle couche est verrouillée comme les autres pendant l'opération
        bsr     ly_obtain
        move.l  a3,a0
        suba.l  a1,a1
        bsr     lr_rebuild
        move.l  a3,a0
        bsr     ly_UnlockLayers
        move.l  a4,d0
        bra.s   .cr_out
.cr_fail:
        lea     16(sp),sp            ; BitMap + bornes + position
        moveq   #0,d0
.cr_out:
        movem.l (sp)+,d2-d7/a2-a6
        rts

; DeleteLayer(dummy a0, l a1) -> TRUE. Les couches de derrière et le fond récupèrent la zone. Trois étapes appelées
; avec leur argument sur la pile (convention C) : verrou de tout le Layer_Info, retrait de la couche, déverrou.
; Le mot d'entrée est suivi d'un branchement vers le corps, dont les trois BSR sont les seuls de la séquence :
; SetPatch 1.38 retrouve ainsi ces trois étapes pour son propre DeleteLayer (docs/analysis/setpatch-138.md §1.8).
ly_DeleteLayer:
        nop
        bra.s   ly_dl_body
; ly_dl_lock(Layer_Info) -> d0 = 1 : couches et Layer_Info verrouillés. Convention C (préserve d2-d7/a2-a6).
ly_dl_lock:
        move.l  4(sp),a0
        bsr     ly_LockLayers
        moveq   #1,d0
        rts
; ly_dl_unlock(Layer_Info).
ly_dl_unlock:
        move.l  4(sp),a0
        bra     ly_UnlockLayers
ly_dl_body:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  a1,a4
        move.l  LY_LAYERINFO(a4),a3
        move.l  a3,-(sp)
        bsr.s   ly_dl_lock
        move.l  a4,(sp)
        bsr.s   ly_dl_remove
        move.l  a3,(sp)
        bsr.s   ly_dl_unlock
        addq.l  #4,sp
        moveq   #-1,d0
        movem.l (sp)+,d2-d7/a2-a6
        rts
; ly_dl_remove(couche, a6 = LayersBase) : la couche quitte la pile, la zone est rendue aux couches de derrière et au fond,
; puis ses ClipRects, sa région de dommages et sa mémoire sont libérées. Le Layer_Info reste verrouillé.
ly_dl_remove:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  44+4(sp),a4          ; couche (au-dessus des 11 registres sauvés et du retour)
        move.l  a6,a5
        move.l  LY_LAYERINFO(a4),a3
        bsr     lr_unlink
        move.l  a3,a0
        move.l  a4,a1                ; anciennes ClipRects de la couche supprimée : fond à découvrir
        bsr     lr_rebuild
        lea     LY_LOCK(a4),a0       ; son verrou n'est plus rendu par UnlockLayers (elle a quitté la pile)
        bsr     ly_release
        lea     LY_CLIPRECT(a4),a2
        bsr     lr_freecrs
        move.l  LB_GFX(a5),a6
        move.l  LY_DAMAGE(a4),a0
        jsr     LVO_DISPOSEREGION_G(a6)
        move.l  ($4).w,a6
        move.l  a4,a1
        move.l  #LY_SIZE+rp_SIZEOF,d0
        jsr     LVO_FREEMEM(a6)
        movem.l (sp)+,d2-d7/a2-a6
        rts

; ============================ ordre, position, taille ============================
; lr_op_enter(a1 = couche) : a5 = LayersBase, a4 = couche, a3 = Layer_Info, tout verrouillé.
; lr_op_leave : reconstruit, déverrouille, d0 = TRUE. (Cadre : d2-d7/a2-a6 empilés par l'appelant.)
lr_op_enter:
        move.l  a6,a5
        move.l  a1,a4
        move.l  LY_LAYERINFO(a4),a3
        move.l  a3,a0
        bra     ly_LockLayers
lr_op_leave:
        move.l  a3,a0
        suba.l  a1,a1
        bsr     lr_rebuild
        move.l  a3,a0
        bsr     ly_UnlockLayers
        moveq   #-1,d0
        rts

; UpfrontLayer(dummy a0, l a1) -> TRUE.
ly_UpfrontLayer:
        movem.l d2-d7/a2-a6,-(sp)
        bsr     lr_op_enter
        bsr     lr_unlink
        bsr     lr_frontpos
        bra     lr_reorder
; BehindLayer(dummy a0, l a1) -> TRUE.
ly_BehindLayer:
        movem.l d2-d7/a2-a6,-(sp)
        bsr     lr_op_enter
        bsr     lr_unlink
        bsr     lr_backpos
lr_reorder:
        bsr     lr_insert
        bsr     lr_op_leave
        movem.l (sp)+,d2-d7/a2-a6
        rts
; MoveLayerInFrontOf(l a0, other a1) -> TRUE : l juste devant other.
ly_MoveLayerInFrontOf:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  a1,-(sp)
        move.l  a0,a1
        bsr     lr_op_enter
        bsr     lr_unlink
        move.l  (sp)+,a0
        bra     lr_reorder

; MoveLayer(dummy a0, l a1, dx d0, dy d1) -> TRUE.
ly_MoveLayer:
        movem.l d2-d7/a2-a6,-(sp)
        movem.w d0-d1,-(sp)
        bsr     lr_op_enter
        movem.w (sp)+,d0-d1
        add.w   d0,LY_MINX(a4)
        add.w   d0,LY_MAXX(a4)
        add.w   d1,LY_MINY(a4)
        add.w   d1,LY_MAXY(a4)
        bsr     lr_op_leave
        movem.l (sp)+,d2-d7/a2-a6
        rts

; SizeLayer(dummy a0, l a1, dx d0, dy d1) -> TRUE : coin bas-droit déplacé, contenu gardé dans la partie commune.
ly_SizeLayer:
        movem.l d2-d7/a2-a6,-(sp)
        movem.w d0-d1,-(sp)
        bsr     lr_op_enter
        movem.w (sp)+,d0-d1
        add.w   d0,LY_MAXX(a4)
        add.w   d1,LY_MAXY(a4)
        bsr     lr_op_leave
        movem.l (sp)+,d2-d7/a2-a6
        rts

; ScrollLayer(dummy a0, l a1, dx d0, dy d1) : réservé aux SuperBitMaps, non gérés ici.
ly_ScrollLayer:
        rts

; ============================ BeginUpdate / EndUpdate ============================

; BeginUpdate(l a0) -> TRUE : la liste de ClipRects devient sa partie dans la DamageList (∩ ClipRegion s'il y en a
; une), pour ne redessiner que les zones abîmées. La couche reste verrouillée jusqu'à EndUpdate.
ly_BeginUpdate:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  a0,a4
        lea     LY_LOCK(a4),a0
        bsr     ly_obtain
        bsr     lr_unclip
        or.w    #LAYERUPDATING,LY_FLAGS(a4)
        bsr     lr_clip
        moveq   #-1,d0
        movem.l (sp)+,d2-d7/a2-a6
        rts

; InstallClipRegion(l a0, region a1) -> d0 = ancienne région. La liste de ClipRects devient sa partie dans la région
; (coordonnées de la couche) : un instantané, une région modifiée doit être réinstallée. NULL : liste normale.
ly_InstallClipRegion:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  a0,a4
        move.l  a1,a2
        lea     LY_LOCK(a4),a0
        bsr     ly_obtain
        move.l  LY_CLIPREGION(a4),d5
        bsr     lr_unclip
        move.l  a2,LY_CLIPREGION(a4)
        bsr     lr_clip
        lea     LY_LOCK(a4),a0
        bsr     ly_release
        move.l  d5,d0
        movem.l (sp)+,d2-d7/a2-a6
        rts

; lr_unclip(a4 = couche) : liste réduite (BeginUpdate ou ClipRegion) libérée, liste normale rétablie. Préserve
; d2-d7/a2-a6.
lr_unclip:
        tst.l   LY_SAVECR(a4)
        beq.s   .uc_r
        move.l  a2,-(sp)
        lea     LY_CLIPRECT(a4),a2
        bsr     lr_freecrs           ; ClipRects empruntées : BitMaps non libérés
        move.l  LY_SAVECR(a4),LY_CLIPRECT(a4)
        clr.l   LY_SAVECR(a4)
        move.l  (sp)+,a2
.uc_r:
        rts

; lr_clip(a4 = couche, liste normale en place) : C = DamageList (∩ ClipRegion) pendant BeginUpdate, sinon ClipRegion ;
; sans C, rien. Sinon la liste normale est gardée dans ly__cliprects et remplacée par ses ClipRects ∩ C : visibles,
; et cachées avec sauvegarde (BitMap emprunté : dessiner dedans écrit la sauvegarde). Région sans rectangle : aucun
; ClipRect. Mémoire insuffisante : liste partielle et LAYER_CLIPRECTS_LOST. Préserve d2-d7/a2-a6.
lr_clip:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  LY_CLIPREGION(a4),d6 ; d6 = 1re région, d7 = 2e (0 : aucune)
        moveq   #0,d7
        btst    #4,LY_FLAGS+1(a4)    ; LAYERUPDATING
        beq.s   .cl_reg
        move.l  d6,d7
        move.l  LY_DAMAGE(a4),d6
        bra.s   .cl_build
.cl_reg:
        tst.l   d6
        beq     .cl_ret
.cl_build:
        clr.l   -(sp)                ; cellule de la nouvelle liste
        move.l  sp,a5
        move.l  LY_CLIPRECT(a4),a3
.cb_cr:
        cmpa.w  #0,a3
        beq     .cb_done
        tst.l   CR_LOBS(a3)
        beq.s   .cb_use
        tst.l   CR_BITMAP(a3)
        beq.s   .cb_next             ; caché sans sauvegarde : rien à dessiner
.cb_use:
        tst.l   d6
        beq.s   .cb_next
        move.l  d6,a0
        move.l  8(a0),a2
.cb_r1:
        cmpa.w  #0,a2
        beq.s   .cb_next
        move.l  d6,a0
        bsr     lr_dmgrect
        lea     CR_MINX(a3),a0
        bsr     lr_isect
        bgt.s   .cb_n1
        tst.l   d7
        bne.s   .cb_two
        bsr.s   .cb_add
        bra.s   .cb_n1
.cb_two:
        movem.w d0-d3,-(sp)          ; ClipRect ∩ rectangle de la 1re région
        move.l  d7,a0
        move.l  8(a0),a6
.cb_r2:
        cmpa.w  #0,a6
        beq.s   .cb_e2
        exg     a2,a6
        move.l  d7,a0
        bsr     lr_dmgrect
        exg     a2,a6
        move.l  sp,a0
        bsr     lr_isect
        bgt.s   .cb_n2
        bsr.s   .cb_add
.cb_n2:
        move.l  RR_NEXT(a6),a6
        bra.s   .cb_r2
.cb_e2:
        addq.l  #8,sp
.cb_n1:
        move.l  RR_NEXT(a2),a2
        bra.s   .cb_r1
.cb_next:
        move.l  CR_NEXT(a3),a3
        bra.s   .cb_cr
.cb_add:                             ; ClipRect d0..d3 en tête de la liste (a5), mêmes lobs/sauvegarde que a3
        move.l  a5,a1
        bsr     lr_newcr
        cmpa.w  #0,a0
        beq.s   .ca_lost
        move.l  CR_LOBS(a3),CR_LOBS(a0)
        move.l  CR_BITMAP(a3),CR_BITMAP(a0)
        move.l  CR_ORGX(a3),CR_ORGX(a0)
        move.b  #CRF_BORROWED,CR_FLAGS+3(a0)
        rts
.ca_lost:
        or.w    #LAYER_CLIPRECTS_LOST,LY_FLAGS(a4)
        rts
.cb_done:
        move.l  LY_CLIPRECT(a4),LY_SAVECR(a4)
        move.l  (sp)+,LY_CLIPRECT(a4)
.cl_ret:
        movem.l (sp)+,d2-d7/a2-a6
        rts

; lr_isect(d0..d3 = rectangle, a0 = bornes (4 mots)) -> d0..d3 ∩ bornes ; condition GT si l'intersection est vide.
lr_isect:
        cmp.w   (a0),d0
        bge.s   .is_1
        move.w  (a0),d0
.is_1:
        cmp.w   2(a0),d1
        bge.s   .is_2
        move.w  2(a0),d1
.is_2:
        cmp.w   4(a0),d2
        ble.s   .is_3
        move.w  4(a0),d2
.is_3:
        cmp.w   6(a0),d3
        ble.s   .is_4
        move.w  6(a0),d3
.is_4:
        cmp.w   d2,d0
        bgt.s   .is_r
        cmp.w   d3,d1
.is_r:
        rts

; lr_dmgrect(a4 = couche, a0 = région relative à la couche, a2 = son rectangle) -> d0..d3 = rectangle absolu.
; Clobbe d4.
lr_dmgrect:
        movem.w RR_MINX(a2),d0-d3
        move.w  (a0),d4              ; région : bornes relatives à la couche
        add.w   LY_MINX(a4),d4
        add.w   d4,d0
        add.w   d4,d2
        move.w  2(a0),d4
        add.w   LY_MINY(a4),d4
        add.w   d4,d1
        add.w   d4,d3
        rts

; EndUpdate(l a0, flag d0) : liste normale rétablie (ou réduite à la ClipRegion) ; flag != 0 -> dommages effacés et LAYERREFRESH retiré.
ly_EndUpdate:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  a0,a4
        move.l  d0,d7
        move.l  a6,a5
        btst    #4,LY_FLAGS+1(a4)    ; LAYERUPDATING
        beq.s   .eu_flag
        bsr     lr_unclip
        and.w   #~LAYERUPDATING,LY_FLAGS(a4)
        bsr     lr_clip              ; ClipRegion seule, s'il y en a une
.eu_flag:
        tst.l   d7
        beq.s   .eu_unlock
        move.l  LB_GFX(a5),a6
        move.l  LY_DAMAGE(a4),a0
        jsr     LVO_CLEARREGION_G(a6)
        and.w   #~LAYERREFRESH,LY_FLAGS(a4)
.eu_unlock:
        lea     LY_LOCK(a4),a0
        bsr     ly_release
        movem.l (sp)+,d2-d7/a2-a6
        rts

; ============================ SwapBitsRastPortClipRect ============================

; SwapBitsRastPortClipRect(rp a0, cr a1) : échange le contenu de la zone de la ClipRect dans le BitMap du RastPort
; avec celui du BitMap de la ClipRect (même alignement des bits : échange octet par octet, bords masqués).
ly_SwapBitsRastPortClipRect:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  CR_BITMAP(a1),d0
        beq     .sw_r
        move.l  d0,a3                ; a3 = BitMap de la ClipRect
        move.l  rp_BitMap(a0),a2     ; a2 = BitMap du RastPort
        move.w  CR_MINX(a1),d4
        move.w  CR_MAXX(a1),d5
        move.w  d4,d0                ; masques de bord
        and.w   #7,d0
        moveq   #-1,d6
        lsr.b   d0,d6                ; d6.b = masque gauche
        move.w  d5,d0
        and.w   #7,d0
        moveq   #7,d1
        sub.w   d0,d1
        moveq   #-1,d7
        lsl.b   d1,d7                ; d7.b = masque droit
        lsr.w   #3,d4                ; octets de début / fin (écran)
        lsr.w   #3,d5
        cmp.w   d4,d5
        bne.s   .sw_m
        and.b   d7,d6
.sw_m:
        move.w  CR_MINY(a1),d3       ; d3 = ligne écran
        moveq   #0,d2                ; d2 = ligne sauvegarde
        move.w  CR_ORGX(a1),d0
        lsr.w   #3,d0
        move.w  d0,a6                ; a6 = décalage en octets de l'origine de la sauvegarde
.sw_row:
        cmp.w   CR_MAXY(a1),d3
        bgt     .sw_r
        moveq   #0,d1                ; plan
.sw_plane:
        cmp.b   bm_Depth(a2),d1
        bge.s   .sw_rnext
        cmp.b   bm_Depth(a3),d1
        bge.s   .sw_rnext
        move.w  d1,d0
        lsl.w   #2,d0
        move.l  bm_Planes(a2,d0.w),a4
        move.l  bm_Planes(a3,d0.w),a5
        moveq   #0,d0
        move.w  bm_BytesPerRow(a2),d0
        mulu    d3,d0
        add.l   d0,a4
        add.w   d4,a4                ; a4 = premier octet écran
        moveq   #0,d0
        move.w  bm_BytesPerRow(a3),d0
        mulu    d2,d0
        add.l   d0,a5
        move.w  d4,d0
        sub.w   a6,d0
        add.w   d0,a5                ; a5 = premier octet sauvegarde
        movem.l d1-d3,-(sp)
        move.w  d4,d3                ; d3 = octet courant
.sw_byte:
        moveq   #-1,d0               ; d0.b = masque de l'octet
        cmp.w   d4,d3
        bne.s   .sw_nf
        and.b   d6,d0
.sw_nf:
        cmp.w   d5,d3
        bne.s   .sw_nl
        and.b   d7,d0
.sw_nl:
        move.b  (a4),d1              ; échange sous masque
        move.b  (a5),d2
        eor.b   d2,d1
        and.b   d0,d1                ; d1 = bits à basculer
        eor.b   d1,(a4)+
        eor.b   d1,(a5)+
        addq.w  #1,d3
        cmp.w   d5,d3
        ble.s   .sw_byte
        movem.l (sp)+,d1-d3
        addq.w  #1,d1
        bra.s   .sw_plane
.sw_rnext:
        addq.w  #1,d3
        addq.w  #1,d2
        bra     .sw_row
.sw_r:
        movem.l (sp)+,d2-d7/a2-a6
        rts

; ============================ outils de ClipRects ============================

; lr_newcr(d0..d3 = bornes, a1 = cellule de liste) -> a0 = ClipRect mise à zéro, en tête de la liste, ou 0.
; Préserve d0-d7/a1-a6.
lr_newcr:
        movem.l d0-d3/a1/a6,-(sp)
        move.l  ($4).w,a6
        moveq   #CR_SIZE,d0
        move.l  #MEMF_PUBLIC|MEMF_CLEAR,d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  d0,a0
        movem.l (sp)+,d0-d3/a1/a6
        cmpa.w  #0,a0
        beq.s   .nc_r
        movem.w d0-d3,CR_MINX(a0)
        move.l  (a1),CR_NEXT(a0)
        move.l  a0,(a1)
.nc_r:
        rts

; lr_freecrs(a2 = cellule de liste) : libère les ClipRects et les BitMaps qu'elles possèdent (pas les empruntés).
lr_freecrs:
        movem.l a3/a6,-(sp)
        move.l  ($4).w,a6
.fc_lp:
        move.l  (a2),d0
        beq.s   .fc_r
        move.l  d0,a3
        move.l  CR_NEXT(a3),(a2)
        btst    #1,CR_FLAGS+3(a3)    ; CRF_BORROWED
        bne.s   .fc_cr
        move.l  CR_BITMAP(a3),d0
        beq.s   .fc_cr
        move.l  d0,a0
        bsr     lr_freebm
.fc_cr:
        move.l  a3,a1
        moveq   #CR_SIZE,d0
        jsr     LVO_FREEMEM(a6)
        bra.s   .fc_lp
.fc_r:
        movem.l (sp)+,a3/a6
        rts

; lr_bmsize(a0 = BitMap de sauvegarde) -> d0 = taille de l'allocation (struct + plans contigus).
lr_bmsize:
        moveq   #0,d0
        move.w  bm_BytesPerRow(a0),d0
        mulu    bm_Rows(a0),d0
        moveq   #0,d1
        move.b  bm_Depth(a0),d1
        mulu    d1,d0
        add.l   #bm_SIZEOF,d0
        rts
; lr_freebm(a0 = BitMap de sauvegarde, a6 = SysBase).
lr_freebm:
        bsr     lr_bmsize
        move.l  a0,a1
        jmp     LVO_FREEMEM(a6)

; lr_allocbm(a3 = ClipRect, d7.b = profondeur) -> cr_BitMap + origine posés (0 si mémoire insuffisante).
; Plans contigus après la structure, mis à zéro. Préserve d2-d7/a2-a6.
lr_allocbm:
        movem.l d2-d4/a6,-(sp)
        move.w  CR_MINX(a3),d2
        and.w   #~15,d2              ; origine X alignée sur 16
        move.w  d2,CR_ORGX(a3)
        move.w  CR_MINY(a3),CR_ORGY(a3)
        move.w  CR_MAXX(a3),d3
        sub.w   d2,d3
        lsr.w   #4,d3
        addq.w  #1,d3
        add.w   d3,d3                ; d3 = octets par ligne
        move.w  CR_MAXY(a3),d4
        sub.w   CR_MINY(a3),d4
        addq.w  #1,d4                ; d4 = lignes
        moveq   #0,d0
        move.w  d3,d0
        mulu    d4,d0
        moveq   #0,d1
        move.b  d7,d1
        mulu    d1,d0                ; plans x profondeur
        add.l   #bm_SIZEOF,d0
        move.l  #MEMF_PUBLIC|MEMF_CLEAR,d1
        move.l  ($4).w,a6
        jsr     LVO_ALLOCMEM(a6)
        move.l  d0,CR_BITMAP(a3)
        beq.s   .ab_r
        move.l  d0,a0
        move.w  d3,bm_BytesPerRow(a0)
        move.w  d4,bm_Rows(a0)
        move.b  d7,bm_Depth(a0)
        moveq   #0,d1                ; plans
        move.w  d3,d1
        mulu    d4,d1                ; d1 = taille d'un plan
        lea     bm_SIZEOF(a0),a1
        moveq   #0,d0
.ab_pl:
        cmp.b   d7,d0
        bge.s   .ab_r
        move.w  d0,d2
        lsl.w   #2,d2
        move.l  a1,bm_Planes(a0,d2.w)
        add.l   d1,a1
        addq.w  #1,d0
        bra.s   .ab_pl
.ab_r:
        movem.l (sp)+,d2-d4/a6
        rts

; lr_blt : BltBitMap(src a0, sx d0, sy d1, dst a1, dx d2, dy d3, w d4, h d5, minterm d6) via graphics (a5 =
; LayersBase). Préserve d2-d7/a2-a6.
lr_blt:
        movem.l d7/a6,-(sp)
        moveq   #-1,d7
        move.l  LB_GFX(a5),a6
        jsr     LVO_BLTBITMAP_G(a6)
        movem.l (sp)+,d7/a6
        rts

; lr_clear(a0 = BitMap, d0..d3 = rectangle absolu) : zone au stylo 0 (tous les plans à 0). Préserve d0-d7/a2-a6.
lr_clear:
        movem.l d0-d6,-(sp)
        move.w  d2,d4
        sub.w   d0,d4
        addq.w  #1,d4
        move.w  d3,d5
        sub.w   d1,d5
        addq.w  #1,d5
        move.w  d0,d2
        move.w  d1,d3
        move.l  a0,a1
        moveq   #0,d6                ; minterm 0 : résultat nul
        bsr     lr_blt
        movem.l (sp)+,d0-d6
        rts

; lr_damage(a4 = couche, d0..d3 = rectangle absolu) : ajouté à la DamageList (relatif à la couche), LAYERREFRESH.
; Préserve d0-d7/a2-a6 (pas a0/a1).
lr_damage:
        movem.l d0-d3/a6,-(sp)
        sub.w   LY_MINX(a4),d0
        sub.w   LY_MINX(a4),d2
        sub.w   LY_MINY(a4),d1
        sub.w   LY_MINY(a4),d3
        movem.w d0-d3,-(sp)
        move.l  sp,a1
        move.l  LY_DAMAGE(a4),d0
        beq.s   .dm_none
        move.l  d0,a0
        move.l  LB_GFX(a5),a6
        jsr     LVO_ORRECTREGION_G(a6)
.dm_none:
        addq.l  #8,sp
        or.w    #LAYERREFRESH,LY_FLAGS(a4)
        movem.l (sp)+,d0-d3/a6
        rts

; lr_screenbm(a4 = couche) -> a0 = BitMap commun (celui de son RastPort).
lr_screenbm:
        move.l  LY_RP(a4),a0
        move.l  rp_BitMap(a0),a0
        rts

; lr_moved(a4) -> Z = 0 si la couche a changé de position pendant l'opération.
lr_moved:
        move.w  LY_MINX(a4),d0
        cmp.w   LY_OLDX(a4),d0
        bne.s   .mv_r
        move.w  LY_MINY(a4),d0
        cmp.w   LY_OLDY(a4),d0
.mv_r:
        rts

; ============================ reconstruction ============================

; lr_rebuild(a3 = Layer_Info, a1 = couche supprimée ou 0, a5 = LayersBase). Couches verrouillées par l'appelant.
lr_rebuild:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  a1,-(sp)             ; (sp) = couche supprimée
        move.l  LI_TOP(a3),a4        ; 1. nouvelles ClipRects
.rb_1:
        cmpa.w  #0,a4
        beq.s   .rb_2
        bsr     lr_newcrs
        move.l  LY_BACK(a4),a4
        bra.s   .rb_1
.rb_2:
        move.l  LI_TOP(a3),a4        ; 2. phase A (couches smart)
.rb_2l:
        cmpa.w  #0,a4
        beq.s   .rb_3
        move.w  LY_FLAGS(a4),d0
        and.w   #LAYERSMART|LAYERSUPER,d0
        beq.s   .rb_2n
        bsr     lr_phasea
.rb_2n:
        move.l  LY_BACK(a4),a4
        bra.s   .rb_2l
.rb_3:
        move.l  (sp),a1
        bsr     lr_background        ; 3. fond découvert
        move.l  LI_TOP(a3),a4        ; 4. phase B
.rb_4l:
        cmpa.w  #0,a4
        beq.s   .rb_5
        bsr     lr_phaseb
        move.l  LY_BACK(a4),a4
        bra.s   .rb_4l
.rb_5:
        move.l  LI_TOP(a3),a4        ; 5. installation
.rb_5l:
        cmpa.w  #0,a4
        beq.s   .rb_out
        lea     LY_CLIPRECT(a4),a2
        bsr     lr_freecrs
        move.l  LY_CRNEW(a4),a0
        move.l  a0,LY_CLIPRECT(a4)
        clr.l   LY_CRNEW(a4)
        suba.l  a1,a1                ; liens arrière
.rb_prev:
        cmpa.w  #0,a0
        beq.s   .rb_pd
        move.l  a1,CR_PREV(a0)
        move.l  a0,a1
        move.l  CR_NEXT(a0),a0
        bra.s   .rb_prev
.rb_pd:
        move.w  LY_MINX(a4),LY_OLDX(a4)
        move.w  LY_MINY(a4),LY_OLDY(a4)
        clr.b   LY_NEW(a4)
        move.l  LY_BACK(a4),a4
        bra.s   .rb_5l
.rb_out:
        addq.l  #4,sp
        movem.l (sp)+,d2-d7/a2-a6
        rts

; lr_newcrs(a4 = couche, a3 = Layer_Info) : ly_crnew = ClipRects de ses bornes face aux couches de devant.
; reste = {bornes} ; pour chaque couche A devant (de l'avant vers l'arrière) : (reste ∩ A) -> ClipRects cachées
; par A, reste -= A ; ce qui reste est visible.
lr_newcrs:
        movem.l d2-d7/a2-a6,-(sp)
        clr.l   LY_CRNEW(a4)
        clr.l   -(sp)                ; 4(sp) = reste, (sp) = temporaire
        clr.l   -(sp)
        lea     4(sp),a2
        lea     LY_MINX(a4),a1
        bsr     rl_add
        move.l  LI_TOP(a3),a6        ; a6 = couche de devant courante
.nc_front:
        cmp.l   a4,a6
        beq.s   .nc_vis
        move.l  sp,a2                ; temporaire = copie du reste ∩ A
        move.l  4(sp),a0
.nc_copy:
        cmpa.w  #0,a0
        beq.s   .nc_and
        move.l  a0,-(sp)
        lea     RR_MINX(a0),a1
        lea     4(sp),a2
        bsr     rl_add
        move.l  (sp)+,a0
        move.l  RR_NEXT(a0),a0
        bra.s   .nc_copy
.nc_and:
        move.l  sp,a2
        lea     LY_MINX(a6),a1
        bsr     rl_and
        move.l  (sp),a0              ; pièces cachées par A
        move.l  a6,d4
        bsr     lr_rr2cr
        move.l  sp,a2
        bsr     rl_free
        lea     4(sp),a2
        lea     LY_MINX(a6),a1
        bsr     rl_sub
        move.l  LY_BACK(a6),a6
        bra.s   .nc_front
.nc_vis:
        move.l  4(sp),a0             ; pièces visibles
        moveq   #0,d4
        bsr     lr_rr2cr
        lea     4(sp),a2
        bsr     rl_free
        addq.l  #8,sp
        movem.l (sp)+,d2-d7/a2-a6
        rts
; lr_rr2cr(a0 = premier nœud rectangle, d4 = lobs, a4 = couche) : une ClipRect par rectangle, dans ly_crnew.
lr_rr2cr:
        cmpa.w  #0,a0
        beq.s   .rc_r
        move.l  a0,-(sp)
        movem.w RR_MINX(a0),d0-d3
        lea     LY_CRNEW(a4),a1
        bsr     lr_newcr
        cmpa.w  #0,a0
        beq.s   .rc_n
        move.l  d4,CR_LOBS(a0)
.rc_n:
        move.l  (sp)+,a0
        move.l  RR_NEXT(a0),a0
        bra     lr_rr2cr
.rc_r:
        rts

; lr_phasea(a4 = couche smart) : sauvegardes des nouvelles ClipRects qui doivent recevoir du contenu.
lr_phasea:
        movem.l d2-d7/a2-a6,-(sp)
        bsr     lr_screenbm
        move.b  bm_Depth(a0),d7      ; profondeur des sauvegardes
        move.l  LY_CRNEW(a4),a3
.pa_lp:
        cmpa.w  #0,a3
        beq.s   .pa_r
        tst.l   CR_LOBS(a3)
        bne.s   .pa_save             ; cachée : sauvegarde permanente
        tst.b   LY_NEW(a4)
        bne.s   .pa_temp
        bsr     lr_moved
        bne.s   .pa_temp
        bsr     lr_oldviscovers      ; déjà visible ici et non déplacée : l'écran est juste
        beq.s   .pa_next
        move.b  #CRF_EXPOSE,CR_FLAGS+3(a3)   ; en place : seules les parties découvertes iront à l'écran (phase B)
        bra.s   .pa_next
.pa_temp:
        move.b  #CRF_TEMP,CR_FLAGS+3(a3)
.pa_save:
        bsr     lr_allocbm
        tst.l   CR_BITMAP(a3)
        beq.s   .pa_next
        bsr     lr_fill
.pa_next:
        move.l  CR_NEXT(a3),a3
        bra.s   .pa_lp
.pa_r:
        movem.l (sp)+,d2-d7/a2-a6
        rts

; lr_oldviscovers(a3 = ClipRect, a4 = couche) -> Z = 1 si ses bornes sont couvertes par les anciennes ClipRects
; visibles de la couche (à la même position).
lr_oldviscovers:
        movem.l d2-d7/a2-a6,-(sp)
        clr.l   -(sp)
        move.l  sp,a2
        lea     CR_MINX(a3),a1
        bsr     rl_add
        move.l  LY_CLIPRECT(a4),a3
.oc_lp:
        cmpa.w  #0,a3
        beq.s   .oc_end
        tst.l   CR_LOBS(a3)
        bne.s   .oc_n
        lea     CR_MINX(a3),a1
        bsr     rl_sub
.oc_n:
        move.l  CR_NEXT(a3),a3
        bra.s   .oc_lp
.oc_end:
        move.l  (sp),d2              ; reste ?
        bsr     rl_free
        addq.l  #4,sp
        tst.l   d2
        movem.l (sp)+,d2-d7/a2-a6    ; movem vers registres : Z intact
        rts

; lr_fill(a3 = nouvelle ClipRect avec sauvegarde, a4 = couche) : contenu depuis les anciennes ClipRects (décalées du
; déplacement), puis la partie sans ancien contenu (agrandissement) en dommages, sauf couche neuve.
lr_fill:
        movem.l d2-d7/a2-a6,-(sp)
        move.w  LY_MINX(a4),d6
        sub.w   LY_OLDX(a4),d6       ; d6 = décalage X (nouveau - ancien)
        move.w  LY_MINY(a4),d7
        sub.w   LY_OLDY(a4),d7       ; d7 = décalage Y
        clr.l   -(sp)                ; zone sans ancien contenu
        move.l  sp,a2
        lea     CR_MINX(a3),a1
        bsr     rl_add
        move.l  LY_CLIPRECT(a4),a6   ; a6 = ancienne ClipRect
.fi_lp:
        cmpa.w  #0,a6
        beq     .fi_new
        movem.w CR_MINX(a6),d0-d3    ; ancienne zone, en nouvelles coordonnées
        add.w   d6,d0
        add.w   d6,d2
        add.w   d7,d1
        add.w   d7,d3
        movem.w d0-d3,-(sp)
        move.l  sp,a1
        lea     8(sp),a2
        bsr     rl_sub               ; retirée de la zone sans contenu
        movem.w (sp)+,d0-d3
        cmp.w   CR_MINX(a3),d0       ; ∩ nouvelle ClipRect
        bge.s   .fi_1
        move.w  CR_MINX(a3),d0
.fi_1:
        cmp.w   CR_MINY(a3),d1
        bge.s   .fi_2
        move.w  CR_MINY(a3),d1
.fi_2:
        cmp.w   CR_MAXX(a3),d2
        ble.s   .fi_3
        move.w  CR_MAXX(a3),d2
.fi_3:
        cmp.w   CR_MAXY(a3),d3
        ble.s   .fi_4
        move.w  CR_MAXY(a3),d3
.fi_4:
        cmp.w   d2,d0
        bgt.s   .fi_next
        cmp.w   d3,d1
        bgt.s   .fi_next
        sub.w   d0,d2
        addq.w  #1,d2
        move.w  d2,d4                ; d4 = largeur
        sub.w   d1,d3
        addq.w  #1,d3
        move.w  d3,d5                ; d5 = hauteur
        move.w  d0,d2                ; destination : coordonnées dans la sauvegarde de a3
        sub.w   CR_ORGX(a3),d2
        move.w  d1,d3
        sub.w   CR_ORGY(a3),d3
        sub.w   d6,d0                ; source : ancienne position absolue
        sub.w   d7,d1
        tst.l   CR_LOBS(a6)
        bne.s   .fi_bk
        bsr     lr_screenbm          ; ancienne zone visible : l'écran
        bra.s   .fi_do
.fi_bk:
        move.l  CR_BITMAP(a6),a0
        cmpa.w  #0,a0
        beq.s   .fi_next             ; ancienne zone cachée sans sauvegarde
        sub.w   CR_ORGX(a6),d0
        sub.w   CR_ORGY(a6),d1
.fi_do:
        move.l  CR_BITMAP(a3),a1
        movem.l d6-d7,-(sp)
        moveq   #-$40,d6             ; minterm $C0 (copie)
        bsr     lr_blt
        movem.l (sp)+,d6-d7
.fi_next:
        move.l  CR_NEXT(a6),a6
        bra     .fi_lp
.fi_new:
        tst.b   LY_NEW(a4)
        bne.s   .fi_free
        move.l  (sp),a0
.fi_dmg:
        cmpa.w  #0,a0
        beq.s   .fi_free
        movem.w RR_MINX(a0),d0-d3
        move.l  a0,-(sp)             ; lr_damage écrase a0/a1
        bsr     lr_damage
        move.l  (sp)+,a0
        move.l  RR_NEXT(a0),a0
        bra.s   .fi_dmg
.fi_free:
        move.l  sp,a2
        bsr     rl_free
        addq.l  #4,sp
        movem.l (sp)+,d2-d7/a2-a6
        rts

; lr_expose(a3 = nouvelle ClipRect visible, a4 = couche smart restée en place) : ses parties anciennement cachées
; et sauvegardées sont recopiées de leur sauvegarde vers l'écran ; les parties sans ancien contenu (agrandissement)
; sont effacées et abîmées. Les parties déjà visibles ne sont pas touchées.
lr_expose:
        movem.l d2-d7/a2-a6,-(sp)
        clr.l   -(sp)                ; zone sans ancien contenu
        move.l  sp,a2
        lea     CR_MINX(a3),a1
        bsr     rl_add
        move.l  LY_CLIPRECT(a4),a6   ; a6 = ancienne ClipRect
.ex_lp:
        cmpa.w  #0,a6
        beq     .ex_new
        movem.w CR_MINX(a6),d0-d3
        movem.w d0-d3,-(sp)
        move.l  sp,a1
        lea     8(sp),a2
        bsr     rl_sub
        movem.w (sp)+,d0-d3
        tst.l   CR_LOBS(a6)
        beq.s   .ex_next             ; anciennement visible : déjà à l'écran
        move.l  CR_BITMAP(a6),d4
        beq.s   .ex_next             ; cachée sans sauvegarde
        cmp.w   CR_MINX(a3),d0       ; ∩ nouvelle ClipRect
        bge.s   .ex_1
        move.w  CR_MINX(a3),d0
.ex_1:
        cmp.w   CR_MINY(a3),d1
        bge.s   .ex_2
        move.w  CR_MINY(a3),d1
.ex_2:
        cmp.w   CR_MAXX(a3),d2
        ble.s   .ex_3
        move.w  CR_MAXX(a3),d2
.ex_3:
        cmp.w   CR_MAXY(a3),d3
        ble.s   .ex_4
        move.w  CR_MAXY(a3),d3
.ex_4:
        cmp.w   d2,d0
        bgt.s   .ex_next
        cmp.w   d3,d1
        bgt.s   .ex_next
        bsr     lr_screenbm
        move.l  a0,a1                ; destination : l'écran, à la même place
        move.l  d4,a0                ; source : la sauvegarde
        sub.w   d0,d2
        addq.w  #1,d2
        move.w  d2,d4                ; largeur
        sub.w   d1,d3
        addq.w  #1,d3
        move.w  d3,d5                ; hauteur
        move.w  d0,d2
        move.w  d1,d3
        sub.w   CR_ORGX(a6),d0
        sub.w   CR_ORGY(a6),d1
        moveq   #-$40,d6             ; minterm $C0 (copie)
        bsr     lr_blt
.ex_next:
        move.l  CR_NEXT(a6),a6
        bra     .ex_lp
.ex_new:
        move.l  (sp),a0
.ex_dmg:
        cmpa.w  #0,a0
        beq.s   .ex_free
        movem.w RR_MINX(a0),d0-d3
        move.l  a0,-(sp)             ; lr_damage écrase a0/a1
        bsr     lr_screenbm
        bsr     lr_clear
        bsr     lr_damage
        move.l  (sp)+,a0
        move.l  RR_NEXT(a0),a0
        bra.s   .ex_dmg
.ex_free:
        move.l  sp,a2
        bsr     rl_free
        addq.l  #4,sp
        movem.l (sp)+,d2-d7/a2-a6
        rts

; lr_phaseb(a4 = couche) : écriture de l'écran pour ses ClipRects visibles.
lr_phaseb:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  LY_CRNEW(a4),a3
.pb_lp:
        cmpa.w  #0,a3
        beq     .pb_r
        tst.l   CR_LOBS(a3)
        bne     .pb_next
        move.w  LY_FLAGS(a4),d0
        and.w   #LAYERSMART|LAYERSUPER,d0
        beq.s   .pb_simple
        btst    #0,CR_FLAGS+3(a3)    ; CRF_TEMP : sauvegarde provisoire -> écran, puis rendue
        bne.s   .pb_temp
        btst    #2,CR_FLAGS+3(a3)    ; CRF_EXPOSE
        beq     .pb_next
        bsr     lr_expose
        clr.b   CR_FLAGS+3(a3)
        bra     .pb_next
.pb_temp:
        move.l  CR_BITMAP(a3),a0
        movem.w CR_MINX(a3),d0-d3
        sub.w   d0,d2
        addq.w  #1,d2
        move.w  d2,d4
        sub.w   d1,d3
        addq.w  #1,d3
        move.w  d3,d5
        move.w  d0,d2                ; destination écran
        move.w  d1,d3
        sub.w   CR_ORGX(a3),d0       ; source : sauvegarde
        sub.w   CR_ORGY(a3),d1
        move.l  a0,-(sp)
        bsr     lr_screenbm
        move.l  a0,a1
        move.l  (sp)+,a0
        moveq   #-$40,d6
        bsr     lr_blt
        move.l  ($4).w,a6
        move.l  CR_BITMAP(a3),a0
        bsr     lr_freebm
        clr.l   CR_BITMAP(a3)
        clr.b   CR_FLAGS+3(a3)
        bra.s   .pb_next
.pb_simple:
        movem.w CR_MINX(a3),d0-d3
        tst.b   LY_NEW(a4)
        bne.s   .pb_clr              ; couche neuve : fond seulement
        bsr     lr_moved
        bne.s   .pb_dmg              ; déplacée : tout est à redessiner
        clr.l   -(sp)                ; non déplacée : seule la partie anciennement cachée
        move.l  sp,a2
        lea     CR_MINX(a3),a1
        bsr     rl_add
        move.l  LY_CLIPRECT(a4),a6
.pb_old:
        cmpa.w  #0,a6
        beq.s   .pb_exp
        tst.l   CR_LOBS(a6)
        bne.s   .pb_on
        lea     CR_MINX(a6),a1
        bsr     rl_sub
.pb_on:
        move.l  CR_NEXT(a6),a6
        bra.s   .pb_old
.pb_exp:
        move.l  (sp),a0
.pb_e:
        cmpa.w  #0,a0
        beq.s   .pb_efree
        movem.w RR_MINX(a0),d0-d3
        move.l  a0,-(sp)
        bsr     lr_screenbm
        bsr     lr_clear
        bsr     lr_damage
        move.l  (sp)+,a0
        move.l  RR_NEXT(a0),a0
        bra.s   .pb_e
.pb_efree:
        move.l  sp,a2
        bsr     rl_free
        addq.l  #4,sp
        bra.s   .pb_next
.pb_dmg:
        bsr     lr_damage
.pb_clr:
        bsr     lr_screenbm
        bsr     lr_clear
.pb_next:
        move.l  CR_NEXT(a3),a3
        bra     .pb_lp
.pb_r:
        movem.l (sp)+,d2-d7/a2-a6
        rts

; lr_background(a3 = Layer_Info, a1 = couche supprimée ou 0, a5 = LayersBase) : zones anciennement visibles
; qu'aucune couche ne couvre plus -> stylo 0. Liste = anciennes ClipRects visibles de toutes les couches (et de la
; supprimée), moins les bornes actuelles de chaque couche. d6 = BitMap commun, d7 = couche supprimée.
lr_background:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  a1,d7
        moveq   #0,d6
        clr.l   -(sp)                ; (sp) = liste
        move.l  LI_TOP(a3),a4
.bg_all:
        cmpa.w  #0,a4
        beq.s   .bg_del
        bsr     .bg_add1
        move.l  LY_BACK(a4),a4
        bra.s   .bg_all
.bg_del:
        move.l  d7,a4
        cmpa.w  #0,a4
        beq.s   .bg_sub
        bsr     .bg_add1
.bg_sub:
        move.l  LI_TOP(a3),a4
.bg_s:
        cmpa.w  #0,a4
        beq.s   .bg_clear
        move.l  sp,a2
        lea     LY_MINX(a4),a1
        bsr     rl_sub
        move.l  LY_BACK(a4),a4
        bra.s   .bg_s
.bg_clear:
        tst.l   d6
        beq.s   .bg_free
        move.l  (sp),a2
.bg_c:
        cmpa.w  #0,a2
        beq.s   .bg_free
        movem.w RR_MINX(a2),d0-d3
        move.l  d6,a0
        bsr     lr_clear
        move.l  RR_NEXT(a2),a2
        bra.s   .bg_c
.bg_free:
        move.l  sp,a2
        bsr     rl_free
        addq.l  #4,sp
        movem.l (sp)+,d2-d7/a2-a6
        rts
; .bg_add1(a4 = couche) : ses anciennes ClipRects visibles ajoutées à la liste (cellule à 4(sp) depuis ici).
.bg_add1:
        move.l  LY_RP(a4),a0
        move.l  rp_BitMap(a0),d6
        move.l  LY_CLIPRECT(a4),a6
.ba_lp:
        cmpa.w  #0,a6
        beq.s   .ba_r
        tst.l   CR_LOBS(a6)
        bne.s   .ba_n
        lea     CR_MINX(a6),a1
        lea     4(sp),a2
        bsr     rl_add
.ba_n:
        move.l  CR_NEXT(a6),a6
        bra.s   .ba_lp
.ba_r:
        rts
layers_end:
