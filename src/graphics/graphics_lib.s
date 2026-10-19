; src/graphics/graphics_lib.s — graphics.library (M4c1 : squelette résident).
; 1er vrai module LIBRARY du projet (cia.resource/timer.device étaient resource/device). ROMTag RTF_AUTOINIT
; (pri 65, entre cia 80 et timer 50) -> chemin AUTOINIT de InitResident : MakeLibrary crée GfxBase, puis
; Enqueue dans EB_LIBLIST selon RT_TYPE=NT_LIBRARY (1re fois que la branche NT_LIBRARY->LibList est exercée ;
; jusqu'ici seul NT_DEVICE->DeviceList l'était avec timer.device). Quirk V34 : la data table pose LN_TYPE +
; LIB_VERSION, l'init func pose LN_NAME="graphics.library". Les fonctions d'affichage (MakeVPort/MrgCop/
; LoadView...) sont DIFFÉRÉES en M4c2 : ce milestone ne livre que Open/Close/Expunge/Reserved (le squelette
; que M4c2 ET intuition/M5 ouvriront). GfxBase = base Library minimale (étendue en M4c2).
;
; Piste IMPLÉMENTATION (« clean ») : AutoDocs graphics.library + exec (RKRM/NDK). AUCUNE lecture ROM.

                include "exec.i"
                include "graphics.i"

; --- ROMTag graphics.library (scanné par build_reslist) ---
        EVEN
; primitives de dessin : src/graphics/draw.s
                xref    gfx_Text
                xref    gfx_TextLength
                xref    gfx_SetFont
                xref    gfx_InitRastPort
                xref    gfx_SetRast
                xref    gfx_Move
                xref    gfx_Draw
                xref    gfx_RectFill
                xref    gfx_WritePixel
                xref    gfx_SetAPen
                xref    gfx_SetBPen
                xref    gfx_SetDrMd
                xref    gfx_InitBitMap
                xref    gfx_ScrollRaster
                xref    gfx_BltBitMapRastPort
graphics_romtag:
        dc.w    RTC_MATCHWORD
        dc.l    graphics_romtag          ; RT_MATCHTAG = self
        dc.l    graphics_end             ; RT_ENDSKIP
                ifne    M4C1_WRONG_TYPE
        dc.b    RTF_AUTOINIT|RTF_COLDSTART,34,NT_DEVICE,65   ; RED : RT_TYPE device -> routé DeviceList -> absent de LibList
                else
        dc.b    RTF_AUTOINIT|RTF_COLDSTART,34,NT_LIBRARY,65  ; RT_FLAGS, RT_VERSION, RT_TYPE, RT_PRI (65 : entre cia 80 / timer 50)
                endc
        dc.l    graphics_name            ; RT_NAME
        dc.l    graphics_name            ; RT_IDSTRING
        dc.l    graphics_inittab         ; RT_INIT -> table AUTOINIT
graphics_name:
        dc.b    "graphics.library",0
        EVEN
graphics_inittab:
        dc.l    GFXBASE_SIZE             ; dataSize : base Library + champs GfxBase minimaux (gb_ActiView/LOFlist)
        dc.l    graphics_vectors         ; funcTable
        dc.l    graphics_datatab         ; dataTable (InitStruct)
        dc.l    graphics_initfunc        ; initFunc
; table ABSOLUE terminée par -1. Vecteur N -> LVO -6*N. On remplit jusqu'à LoadView (-222 = vecteur 37) ; les
; vecteurs 5..34 (-30..-204) non implémentés pointent sur graphics_null (dcb évite tout miscount manuel).
graphics_vectors:                    ; table ABSOLUE, vecteur N -> LVO -6*N, jeu V34 complet (106 vecteurs)
        dc.l    graphics_open            ; 1 : LVO -6
        dc.l    graphics_close           ; 2 : LVO -12
        dc.l    graphics_expunge         ; 3 : LVO -18
        dc.l    graphics_null            ; 4 : LVO -24 (réservé)
        dcb.l   4,graphics_null         ; 5..8 : LVO -30..-48 (non implémentés)
        dc.l    gfx_TextLength           ; 9 : LVO -54
        dc.l    gfx_Text                 ; 10 : LVO -60
        dc.l    gfx_SetFont              ; 11 : LVO -66
        dcb.l   21,graphics_null         ; 12..32 : LVO -72..-192 (non implémentés)
        dc.l    gfx_InitRastPort         ; 33 : LVO -198
        dc.l    graphics_null            ; 34 : LVO -204 (non implémenté)
        dc.l    gfx_MrgCop               ; 35 : LVO -210
        dc.l    gfx_MakeVPort            ; 36 : LVO -216
        dc.l    gfx_LoadView             ; 37 : LVO -222
        dc.l    gfx_WaitBlit             ; 38 : LVO -228
        dc.l    gfx_SetRast              ; 39 : LVO -234
        dc.l    gfx_Move                 ; 40 : LVO -240
        dc.l    gfx_Draw                 ; 41 : LVO -246
        dcb.l   9,graphics_null         ; 42..50 : LVO -252..-300 (non implémentés)
        dc.l    gfx_RectFill             ; 51 : LVO -306
        dcb.l   2,graphics_null         ; 52..53 : LVO -312..-318 (non implémentés)
        dc.l    gfx_WritePixel           ; 54 : LVO -324
        dcb.l   2,graphics_null         ; 55..56 : LVO -330..-336 (non implémentés)
        dc.l    gfx_SetAPen              ; 57 : LVO -342
        dc.l    gfx_SetBPen              ; 58 : LVO -348
        dc.l    gfx_SetDrMd              ; 59 : LVO -354
        dcb.l   5,graphics_null         ; 60..64 : LVO -360..-384 (non implémentés)
        dc.l    gfx_InitBitMap           ; 65 : LVO -390
        dc.l    gfx_ScrollRaster         ; 66 : LVO -396
        dc.l    graphics_null            ; 67 : LVO -402 WaitBOVP (non implémenté)
        dc.l    gfx_GetSprite            ; 68 : LVO -408
        dc.l    graphics_null            ; 69 : LVO -414 FreeSprite (non implémenté)
        dc.l    gfx_ChangeSprite         ; 70 : LVO -420
        dc.l    gfx_MoveSprite           ; 71 : LVO -426
        dcb.l   4,graphics_null         ; 72..75 : LVO -432..-450 (non implémentés)
        dc.l    gfx_OwnBlitter           ; 76 : LVO -456
        dc.l    gfx_DisownBlitter        ; 77 : LVO -462
        dcb.l   11,graphics_null         ; 78..88 : LVO -468..-528 (non implémentés)
        dc.l    graphics_null            ; 89 : LVO -534 DisposeRegion (non implémenté)
        dc.l    gfx_FreeVPortCopLists    ; 90 : LVO -540
        dcb.l   10,graphics_null         ; 91..100 : LVO -546..-600 (non implémentés)
        dc.l    gfx_BltBitMapRastPort    ; 101 : LVO -606
        dcb.l   5,graphics_null          ; 102..106 : LVO -612..-636 (non implémentés)
        dc.l    -1
graphics_datatab:
        dc.w    $E000,LN_TYPE,(NT_LIBRARY<<8)   ; INITBYTE(LN_TYPE, NT_LIBRARY)
        dc.w    $D000,LIB_VERSION,34            ; INITWORD(LIB_VERSION, 34)
        dc.b    0
        EVEN

; Open(lib a6) : incrémente le compte d'ouverture, retourne la base (convention OpenLibrary).
graphics_open:
        addq.w  #1,LIB_OPENCNT(a6)
        move.l  a6,d0
        rts
graphics_close:
        subq.w  #1,LIB_OPENCNT(a6)
        moveq   #0,d0
        rts
graphics_expunge:
        moveq   #0,d0               ; pas d'expunge ce milestone (base résidente)
        rts
graphics_null:
        moveq   #0,d0
        rts

; initFunc (D0=base, A0=segList, A6=ExecBase) -> D0=base. Pose le nom (quirk V34) et alloue le sprite vide.
graphics_initfunc:
        move.l  a2,-(sp)
        move.l  d0,a2
        lea     graphics_name(pc),a0
        move.l  a0,LN_NAME(a2)
        moveq   #8,d0                ; sprite vide (POS/CTL = 0 : canal éteint), lu par le DMA -> chip
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  d0,gb_SprNull(a2)
        move.l  a2,d0
        move.l  (sp)+,a2
        rts

; === M4c2 : moteur d'affichage (copper list GÉNÉRÉE depuis les structures) ===
; Convention Amiga pour les 3 fonctions : a6 = GfxBase, préservent d2-d7/a2-a6, scratch d0/d1/a0/a1.
; AllocMem demande a6 = SysBase -> on sauve/restaure a6 et on prend SysBase via ($4).w.

; gfx_MakeVPort(view a0, vp a1) : génère le fragment copper de la ViewPort dans vp_DspIns (chip RAM).
; GÉNÉRIQUE (comme la vraie graphics.library) : fenêtre d'affichage selon le mode (HIRES 640 px ; basse résolution
; 320 px, ou overscan 352x272 si DWidth > 320), hauteur = DHeight (fenêtres standard), modulo = BytesPerRow - octets
; lus par ligne ; BPLCON0 depuis BitMap.Depth ; UN pointeur BPLxPT par plan (BitMap.Planes[0..depth-1]) ; cm_Count
; couleurs COLOR00..COLOR(Count-1) depuis ColorTable. Un fragment déjà présent est réutilisé (effacé puis réécrit).
; view inutilisé (1 seule ViewPort). Pas de WAIT final (ajouté par MrgCop).
gfx_MakeVPort:
        movem.l d2/d3/d4/d5/a2/a3/a4/a6,-(sp)
        move.l  a1,a2                ; a2 = ViewPort
        move.l  vp_DspIns(a2),d0
        bne.s   .mv_have
        move.l  ($4).w,a6            ; a6 = SysBase
        move.l  #GFX_FRAG_SIZE,d0
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .mv_ret              ; alloc KO -> vp_DspIns reste 0
.mv_have:
        move.l  d0,a3                ; a3 = fragment (chip)
        move.l  a3,a1
        move.w  #(GFX_FRAG_SIZE/2)-1,d1
.mv_clr:
        clr.w   (a1)+                ; reliquat = MOVEs inertes (cf. GFX_FRAG_WORDS)
        dbra    d1,.mv_clr
        move.l  a3,a1                ; a1 = ptr d'écriture
        move.l  vp_RasInfo(a2),a0
        move.l  ri_BitMap(a0),a4     ; a4 = BitMap
        lea     gfx_win_over(pc),a0  ; a0 = DIWSTRT, DDFSTRT, DDFSTOP, octets lus par ligne
        move.w  #GFX_DIWSTOP,d1
        tst.w   vp_Modes(a2)
        bpl.s   .mv_lo
        lea     gfx_win_hires(pc),a0
        bra.s   .mv_std
.mv_lo:
        cmp.w   #320,vp_DWidth(a2)
        bhi.s   .mv_emit             ; > 320 px en basse résolution : overscan
        lea     gfx_win_lores(pc),a0
.mv_std:
        move.w  vp_DHeight(a2),d1    ; DIWSTOP : vstop = $2C + DHeight (V8 déduit de V7 par le hardware)
        add.w   #$2C,d1
        lsl.w   #8,d1
        move.b  #$C1,d1
.mv_emit:
        move.w  #DIWSTRT-CUSTOM,(a1)+
        move.w  (a0)+,(a1)+
        move.w  #DIWSTOP-CUSTOM,(a1)+
        move.w  d1,(a1)+
        move.w  #DDFSTRT-CUSTOM,(a1)+
        move.w  (a0)+,(a1)+
        move.w  #DDFSTOP-CUSTOM,(a1)+
        move.w  (a0)+,(a1)+
        move.w  bm_BytesPerRow(a4),d5
        sub.w   (a0)+,d5             ; d5 = modulo
        moveq   #0,d4
        move.b  bm_Depth(a4),d4      ; d4 = depth (compteur de plans)
        move.w  d4,d2
        lsl.w   #8,d2
        lsl.w   #4,d2                ; depth << 12
        or.w    #GFX_COLOR_BIT,d2    ; | COLOR
        tst.w   vp_Modes(a2)
        bpl.s   .mv_lores
        or.w    #GFX_HIRES_BIT,d2    ; | HIRES (vp_Modes bit 15)
.mv_lores:
        move.w  #BPLCON0-CUSTOM,(a1)+
        move.w  d2,(a1)+
        move.w  #BPLCON1-CUSTOM,(a1)+
        move.w  #0,(a1)+
        move.w  #BPLCON2-CUSTOM,(a1)+
        move.w  #GFX_BPLCON2,(a1)+   ; sprites devant les deux playfields (pointeur visible partout)
        move.w  #BPL1MOD-CUSTOM,(a1)+
        move.w  d5,(a1)+
        move.w  #BPL2MOD-CUSTOM,(a1)+
        move.w  d5,(a1)+
        ; pointeurs de bitplane : un BPLxPTH/L par plan (Planes[i])
        lea     bm_Planes(a4),a0     ; a0 = &Planes[0]
        move.w  #BPL1PTH-CUSTOM,d3   ; d3 = offset du registre BPLxPTH courant
.mv_plane:
        move.l  (a0)+,d5             ; d5 = adresse du plan i
        move.w  d3,(a1)+             ; BPLxPTH
        move.l  d5,d2
        swap    d2
        move.w  d2,(a1)+             ; mot HAUT
        addq.w  #2,d3                ; -> BPLxPTL
        move.w  d3,(a1)+
        move.w  d5,(a1)+             ; mot BAS
        addq.w  #2,d3                ; -> BPL(x+1)PTH
        subq.w  #1,d4
        bne.s   .mv_plane
        ; couleurs : cm_Count MOVEs COLOR00..COLOR(Count-1)
        move.l  vp_ColorMap(a2),a0
        move.w  cm_Count(a0),d4      ; d4 = nombre de couleurs
        move.l  cm_ColorTable(a0),a0 ; a0 = ColorTable
        move.w  #COLOR00-CUSTOM,d3   ; d3 = offset du registre COLORxx courant
.mv_color:
        move.w  d3,(a1)+
        move.w  (a0)+,(a1)+          ; COLORxx = ColorTable[xx]
        addq.w  #2,d3
        subq.w  #1,d4
        bne.s   .mv_color
        move.l  a3,vp_DspIns(a2)     ; publie le fragment
.mv_ret:
        movem.l (sp)+,d2/d3/d4/d5/a2/a3/a4/a6
        rts

; fenêtres d'affichage PAL : DIWSTRT, DDFSTRT, DDFSTOP, octets lus par ligne (DIWSTOP : fixe en overscan, sinon
; calculé depuis DHeight)
gfx_win_over:
        dc.w    GFX_DIWSTRT,GFX_DDFSTRT,GFX_DDFSTOP,GFX_BOOT_BYTES
gfx_win_lores:
        dc.w    $2C81,$0038,$00D0,40
gfx_win_hires:
        dc.w    $2C81,$003C,$00D4,80

; gfx_FreeVPortCopLists(vp a0) : libère le fragment copper de la ViewPort (vp_DspIns := 0).
gfx_FreeVPortCopLists:
        move.l  a6,-(sp)
        move.l  vp_DspIns(a0),d0
        beq.s   .fv_ret
        clr.l   vp_DspIns(a0)
        move.l  d0,a1
        move.l  #GFX_FRAG_SIZE,d0
        move.l  ($4).w,a6
        jsr     LVO_FREEMEM(a6)
.fv_ret:
        move.l  (sp)+,a6
        rts

; gfx_MrgCop(view a1) : fusionne le fragment vp_DspIns de chaque ViewPort dans v_LOFCprList (master, chip RAM)
; + WAIT final. Une liste déjà présente est réutilisée. 1 ViewPort ici. Gaté M4C2_NO_MRGCOP (RED) : saute la fusion -> master = WAIT seul -> écran blanc.
gfx_MrgCop:
        movem.l d2/a2/a3/a4/a5/a6,-(sp)
        move.l  a6,a5                ; a5 = GfxBase
        move.l  a1,a2                ; a2 = View
        move.l  v_LOFCprList(a2),d0  ; liste déjà allouée : réécrite sur place (taille fixe)
        bne.s   .mc_have
        move.l  ($4).w,a6            ; SysBase
        move.l  #GFX_MASTER_SIZE,d0
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.s   .mc_ret
.mc_have:
        move.l  d0,a3                ; a3 = master
        move.l  a3,a4                ; a4 = ptr d'écriture
        bsr     gfx_sprmoves         ; en tête : SPR0PT..SPR7PT (position fixe, réécrite par LoadView/ChangeSprite)
                ifeq    M4C2_NO_MRGCOP
        move.l  v_ViewPort(a2),a0    ; 1re ViewPort
.mc_vp:
        move.l  a0,d2
        beq.s   .mc_end
        move.l  vp_DspIns(a0),a1     ; fragment de cette ViewPort
        move.l  a1,d2
        beq.s   .mc_next             ; pas de fragment
        move.w  #(GFX_FRAG_SIZE/2)-1,d2
.mc_copy:
        move.w  (a1)+,(a4)+
        dbf     d2,.mc_copy
.mc_next:
        move.l  vp_Next(a0),a0       ; ViewPort suivante
        bra.s   .mc_vp
.mc_end:
                endc
        move.w  #$FFFF,(a4)+         ; WAIT $FFFF,$FFFE = fin de liste
        move.w  #$FFFE,(a4)+
        move.l  a3,v_LOFCprList(a2) ; publie le master
.mc_ret:
        movem.l (sp)+,d2/a2/a3/a4/a5/a6
        rts

; gfx_sprmoves(a4 = écriture, a5 = GfxBase) : 8 paires de MOVEs SPRxPTH/SPRxPTL (gb_SprData[x], sinon le sprite vide) ;
; a4 avance de GFX_SPRCOP_SIZE. Clobbe d0-d2/a0.
gfx_sprmoves:
        lea     gb_SprData(a5),a0
        move.w  #SPR0PTH-CUSTOM,d1
        moveq   #7,d2
.sm_lp:
        move.l  (a0)+,d0
        bne.s   .sm_have
        move.l  gb_SprNull(a5),d0
.sm_have:
        move.w  d1,(a4)+             ; SPRxPTH
        swap    d0
        move.w  d0,(a4)+
        addq.w  #2,d1
        move.w  d1,(a4)+             ; SPRxPTL
        swap    d0
        move.w  d0,(a4)+
        addq.w  #2,d1
        dbra    d2,.sm_lp
        rts

; gfx_LoadView(view a1) : a1 != 0 -> réécrit les pointeurs de sprite de v_LOFCprList, l'installe (COP1LC) + active
; Copper/bitplane/sprite DMA + pose
; gb_ActiView. a1 == 0 (vue NULLE) -> BLANCHIT l'affichage : coupe le DMA bitplane (RASTER) ET copper du
; système, pour que l'appelant (ex. flt-intro) pose SON propre COP1LC + bitplanes sans que notre copper de
; boot les écrase. REQUIS par flt-intro, qui fait LoadView(NULL) avant de prendre la main sur le hardware.
gfx_LoadView:
        move.l  a1,gb_ActiView(a6)   ; GfxBase.ActiView = view (0 si NULL)
        move.l  a1,d0
        beq.s   .lv_null             ; vue NULLE -> stopper l'affichage système
        move.l  v_LOFCprList(a1),d0
        beq.s   .lv_ret              ; pas de copper list -> rien
        move.l  d0,gb_LOFlist(a6)
        movem.l a4/a5,-(sp)          ; pointeurs de sprite courants (une liste construite plus tôt est à jour)
        move.l  d0,a4
        move.l  a6,a5
        bsr     gfx_sprmoves
        movem.l (sp)+,a4/a5
        move.l  gb_LOFlist(a6),d0
        addq.l  #2,d0
        move.l  d0,gb_SprCop(a6)     ; mot de valeur de SPR0PTH
        subq.l  #2,d0
        move.l  d0,COP1LC            ; COP1LC = master (longword)
        move.w  #GFX_DMA_ON,DMACON   ; DMA maître + Copper + bitplane
        move.w  #0,COPJMP1           ; strobe COP1
.lv_ret:
        rts
.lv_null:
        clr.l   gb_SprCop(a6)
        move.w  #(DMAF_RASTER|DMAF_COPPER|DMAF_SPRITE),DMACON  ; clear (SETCLR=0) DMA bitplane + copper + sprites -> affichage système
        rts                                        ; stoppé (flt-intro installera son propre COP1LC/bitplanes)

; gfx_WaitBlit() : attend que le blitter soit idle (poll DMACONR, bit 14 = BBUSY). Double-lecture (quirk A1000).
gfx_WaitBlit:
        btst    #6,CUSTOM+$002       ; DMACONR octet haut, bit 6 = bit 14 (BBUSY) — lecture bidon (quirk)
.wb_loop:
        btst    #6,CUSTOM+$002
        bne.s   .wb_loop
        rts

; gfx_OwnBlitter() : prend le blitter. Mono-tâche (l'appelant possède la machine) -> on garantit juste l'idle.
gfx_OwnBlitter:
        bra.s   gfx_WaitBlit

; gfx_DisownBlitter() : relâche le blitter. Pas d'arbitrage multi-tâche ici -> no-op.
gfx_DisownBlitter:
        rts
; GetSprite(sprite a0, n° d0) -> d0 = canal réservé | -1. d0 = -1 : premier canal libre (0 réservé au pointeur).
gfx_GetSprite:
        move.w  gb_SprUsed(a6),d1
        tst.w   d0
        bpl.s   .gs_one
        moveq   #1,d0
.gs_find:
        btst    d0,d1
        beq.s   .gs_take
        addq.w  #1,d0
        cmp.w   #8,d0
        blo.s   .gs_find
        bra.s   .gs_fail
.gs_one:
        cmp.w   #8,d0
        bhs.s   .gs_fail
        btst    d0,d1
        bne.s   .gs_fail
.gs_take:
        bset    d0,d1
        move.w  d1,gb_SprUsed(a6)
        move.w  d0,ss_num(a0)
        ext.l   d0
        rts
.gs_fail:
        moveq   #-1,d0
        rts

; ChangeSprite(vp a0, sprite a1, données a2) : nouvelle image du canal ss_num (POS/CTL recalculés à ss_x/ss_y) ;
; le pointeur du canal est aussi écrit dans la liste copper chargée.
gfx_ChangeSprite:
        movem.l a2-a3,-(sp)
        move.l  a2,ss_posctldata(a1)
        move.w  ss_num(a1),d0
        and.w   #7,d0
        move.w  d0,d1
        lsl.w   #2,d1
        lea     gb_SprData(a6),a3
        move.l  a2,0(a3,d1.w)
        move.l  gb_SprCop(a6),d1
        beq.s   .cs_move
        move.l  d1,a3
        lsl.w   #3,d0                ; 8 octets par canal (2 MOVEs)
        add.w   d0,a3
        move.l  a2,d1
        swap    d1
        move.w  d1,(a3)              ; SPRxPTH
        swap    d1
        move.w  d1,4(a3)             ; SPRxPTL
.cs_move:
        movem.l (sp)+,a2-a3
        move.w  ss_x(a1),d0
        move.w  ss_y(a1),d1
        bra.s   gfx_MoveSprite

; MoveSprite(vp a0, sprite a1, x d0, y d1) : place le sprite ; coordonnées en pixels basse résolution, relatives au
; coin haut-gauche de la fenêtre d'affichage de la ViewPort (vp, sinon celle de la View active).
gfx_MoveSprite:
        movem.l d2-d4,-(sp)
        move.w  d0,ss_x(a1)
        move.w  d1,ss_y(a1)
        move.l  ss_posctldata(a1),d2
        beq.s   .ms_ret
        move.w  #$80,d2              ; origines : fenêtre standard (DIWSTRT $2C81)
        move.w  #$2C,d3
        move.l  a0,d4
        bne.s   .ms_vp
        move.l  gb_ActiView(a6),d4
        beq.s   .ms_org
        move.l  d4,a0
        move.l  v_ViewPort(a0),a0
        move.l  a0,d4
        beq.s   .ms_org
.ms_vp:
        tst.w   vp_Modes(a0)
        bmi.s   .ms_org              ; HIRES : fenêtre standard
        cmp.w   #320,vp_DWidth(a0)
        bls.s   .ms_org
        move.w  #(GFX_DIWSTRT&$FF)-1,d2 ; overscan basse résolution
        move.w  #GFX_DIWSTRT>>8,d3
.ms_org:
        add.w   d0,d2                ; d2 = hstart
        add.w   d1,d3                ; d3 = vstart
        move.w  d3,d4
        add.w   ss_height(a1),d4     ; d4 = vstop
        move.l  ss_posctldata(a1),a0
        move.w  d3,d0                ; POS = vstart(7..0) << 8 | hstart(8..1)
        lsl.w   #8,d0
        move.w  d2,d1
        lsr.w   #1,d1
        move.b  d1,d0
        move.w  d0,(a0)+
        move.w  d4,d0                ; CTL = vstop(7..0) << 8 | vstart(8) << 2 | vstop(8) << 1 | hstart(0)
        lsl.w   #8,d0
        btst    #8,d3
        beq.s   .ms_v8
        bset    #2,d0
.ms_v8:
        btst    #8,d4
        beq.s   .ms_e8
        bset    #1,d0
.ms_e8:
        btst    #0,d2
        beq.s   .ms_h0
        bset    #0,d0
.ms_h0:
        move.w  d0,(a0)
.ms_ret:
        movem.l (sp)+,d2-d4
        rts

graphics_end:
