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
graphics_romtag:
        dc.w    RTC_MATCHWORD
        dc.l    graphics_romtag          ; RT_MATCHTAG = self
        dc.l    graphics_end             ; RT_ENDSKIP
                ifne    M4C1_WRONG_TYPE
        dc.b    RTF_AUTOINIT,34,NT_DEVICE,65   ; RED : RT_TYPE device -> routé DeviceList -> absent de LibList
                else
        dc.b    RTF_AUTOINIT,34,NT_LIBRARY,65  ; RT_FLAGS, RT_VERSION, RT_TYPE, RT_PRI (65 : entre cia 80 / timer 50)
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
graphics_vectors:
        dc.l    graphics_open            ; 1 : LVO -6
        dc.l    graphics_close           ; 2 : LVO -12
        dc.l    graphics_expunge         ; 3 : LVO -18
        dc.l    graphics_null            ; 4 : LVO -24 (réservé)
        dcb.l   30,graphics_null         ; 5..34 : LVO -30..-204 (non implémentés : InitVPort -204 inclus)
        dc.l    gfx_MrgCop               ; 35 : LVO -210
        dc.l    gfx_MakeVPort            ; 36 : LVO -216
        dc.l    gfx_LoadView             ; 37 : LVO -222
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

; initFunc (D0=base, A0=segList, A6=ExecBase) -> D0=base. Pose le nom (quirk V34).
graphics_initfunc:
        move.l  d0,a1
        lea     graphics_name(pc),a0
        move.l  a0,LN_NAME(a1)
        rts

; === M4c2 : moteur d'affichage (copper list GÉNÉRÉE depuis les structures) ===
; Convention Amiga pour les 3 fonctions : a6 = GfxBase, préservent d2-d7/a2-a6, scratch d0/d1/a0/a1.
; AllocMem demande a6 = SysBase -> on sauve/restaure a6 et on prend SysBase via ($4).w.

; gfx_MakeVPort(view a0, vp a1) : génère le fragment copper de la ViewPort dans vp_DspIns (chip RAM).
; GÉNÉRIQUE (comme la vraie graphics.library) : BPLCON0 depuis BitMap.Depth ; UN pointeur BPLxPT par plan
; (BitMap.Planes[0..depth-1], BPLxPT = BPL1PT + (x-1)*4) ; cm_Count couleurs COLOR00..COLOR(Count-1) depuis
; ColorTable. Supporte donc 1 plan/2 couleurs (rayures) comme 5 plans/32 couleurs (écran de boot). view
; inutilisé (1 seule ViewPort). Pas de WAIT final (ajouté par MrgCop).
gfx_MakeVPort:
        movem.l d2/d3/d4/d5/a2/a3/a4/a6,-(sp)
        move.l  a1,a2                ; a2 = ViewPort
        move.l  ($4).w,a6            ; a6 = SysBase
        move.l  #GFX_FRAG_SIZE,d0
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .mv_ret              ; alloc KO -> vp_DspIns reste 0
        move.l  d0,a3                ; a3 = fragment (chip)
        move.l  a3,a1                ; a1 = ptr d'écriture
        move.w  #DIWSTRT-CUSTOM,(a1)+
        move.w  #GFX_DIWSTRT,(a1)+
        move.w  #DIWSTOP-CUSTOM,(a1)+
        move.w  #GFX_DIWSTOP,(a1)+
        move.w  #DDFSTRT-CUSTOM,(a1)+
        move.w  #GFX_DDFSTRT,(a1)+
        move.w  #DDFSTOP-CUSTOM,(a1)+
        move.w  #GFX_DDFSTOP,(a1)+
        move.l  vp_RasInfo(a2),a0    ; RasInfo
        move.l  ri_BitMap(a0),a4     ; a4 = BitMap
        moveq   #0,d4
        move.b  bm_Depth(a4),d4      ; d4 = depth (compteur de plans)
        move.w  d4,d2
        lsl.w   #8,d2
        lsl.w   #4,d2                ; depth << 12
        or.w    #GFX_COLOR_BIT,d2    ; | COLOR
        move.w  #BPLCON0-CUSTOM,(a1)+
        move.w  d2,(a1)+
        move.w  #BPLCON1-CUSTOM,(a1)+
        move.w  #0,(a1)+
        move.w  #BPL1MOD-CUSTOM,(a1)+
        move.w  #0,(a1)+
        move.w  #BPL2MOD-CUSTOM,(a1)+
        move.w  #0,(a1)+
        ; pointeurs de bitplane : un BPLxPTH/L par plan (plans contigus, Planes[i])
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

; gfx_MrgCop(view a1) : fusionne le fragment vp_DspIns de chaque ViewPort dans v_LOFCprList (master, chip RAM)
; + WAIT final. 1 ViewPort ici. Gaté M4C2_NO_MRGCOP (RED) : saute la fusion -> master = WAIT seul -> écran blanc.
gfx_MrgCop:
        movem.l d2/a2/a3/a4/a6,-(sp)
        move.l  a1,a2                ; a2 = View
        move.l  ($4).w,a6            ; SysBase
        move.l  #GFX_MASTER_SIZE,d0
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.s   .mc_ret
        move.l  d0,a3                ; a3 = master
        move.l  a3,a4                ; a4 = ptr d'écriture
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
        movem.l (sp)+,d2/a2/a3/a4/a6
        rts

; gfx_LoadView(view a1) : installe v_LOFCprList (COP1LC) + active Copper/bitplane DMA + pose gb_ActiView.
gfx_LoadView:
        move.l  a1,gb_ActiView(a6)   ; GfxBase.ActiView = view
        move.l  v_LOFCprList(a1),d0
        beq.s   .lv_ret              ; pas de copper list -> rien
        move.l  d0,gb_LOFlist(a6)
        move.l  d0,COP1LC            ; COP1LC = master (longword)
        move.w  #GFX_DMA_ON,DMACON   ; DMA maître + Copper + bitplane
        move.w  #0,COPJMP1           ; strobe COP1
.lv_ret:
        rts
graphics_end:
