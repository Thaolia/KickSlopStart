; src/graphics/gfx.s — bootstrap de l'affichage VIA L'ABI graphics.library (moteur M4c2, étendu à l'écran de boot).
; gfx_display_init alloue les bitplanes chip, Y COPIE l'image de boot (chaton « KickSlopStart », 320x256x5 = 32
; couleurs) depuis la ROM, monte les structures BitMap/RasInfo/ColorMap(32)/ViewPort/View, ouvre graphics.library
; (FindName), puis appelle MakeVPort/MrgCop/LoadView VIA LA JUMP TABLE -> la copper list (5 pointeurs de plan + 32
; couleurs) est GÉNÉRÉE par l'ABI. Les données image/palette sont générées par src/graphics/mk_bootscreen.py.
; Historique : M4a (fond Copper) / M4b/M4c2 (bitplane rayé) -> l'écran rayé est remplacé ici par l'image de boot ;
; le même chemin ABI (MakeVPort générique N plans/M couleurs) est donc exercé plus largement.
;
; CONTRAINTE : Copper et bitplane DMA (Agnus) lisent UNIQUEMENT la chip RAM -> bitplanes, structures et listes
; copper générées sont toutes AllocMem(MEMF_CHIP) ; l'image est copiée ROM -> chip.
; Piste IMPLÉMENTATION (« clean ») : AutoDocs graphics.library + HRM + image fournie par l'utilisateur. AUCUNE lecture ROM.

                include "exec.i"
                include "graphics.i"

                xdef    gfx_display_init
                xref    bootscreen_planes    ; bootscreen_data.s (généré) : 5 bitplanes planar
                xref    bootscreen_palette   ; bootscreen_data.s (généré) : 32 couleurs OCS RGB444

; gfx_display_init(a6 = SysBase) : alloue bitplanes + bloc de structures, copie l'image, monte View/ViewPort/
; BitMap/ColorMap, FindName("graphics.library"), puis MakeVPort/MrgCop/LoadView via la jump table GfxBase.
; RESTAURE a6 = SysBase en sortie (le handoff scheduler en dépend). Scratch d0/d1/a0/a1 + a2/a4/a5 (sauvés).
; Non fatal si une alloc ou FindName échoue (pas d'affichage, boot poursuit).
gfx_display_init:
        movem.l a2/a4/a5,-(sp)
        ; 1. bitplanes chip (5 plans contigus) + copie de l'image depuis la ROM
        move.l  #GFX_BOOT_PLANES_SZ,d0
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .gfx_ret
        move.l  d0,a4                        ; a4 = base des bitplanes (chip)
        move.l  #bootscreen_planes,a0        ; src = données planar (ROM)
        move.l  a4,a1                         ; dst = chip
        move.w  #(GFX_BOOT_PLANES_SZ/4)-1,d0
.gfx_copy:
        move.l  (a0)+,(a1)+
        dbf     d0,.gfx_copy
        ; 2. bloc de structures chip (View/VP/RasInfo/BitMap/ColorMap/ColorTable[32])
        move.l  #GFX_STRUCT_SIZE,d0
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .gfx_ret
        move.l  d0,a2                        ; a2 = bloc de structures
        ; BitMap (overscan 352x272)
        move.w  #GFX_BOOT_BYTES,GFX_O_BITMAP+bm_BytesPerRow(a2)
        move.w  #GFX_BOOT_H,GFX_O_BITMAP+bm_Rows(a2)
                ifeq    BOOTSCR_ONE_PLANE
        move.b  #GFX_BOOT_DEPTH,GFX_O_BITMAP+bm_Depth(a2)
                else
        move.b  #1,GFX_O_BITMAP+bm_Depth(a2) ; RED BOOTSCR_ONE_PLANE : 1 plan -> image détruite (2 couleurs)
                endc
        ; Planes[0..GFX_BOOT_DEPTH-1] = base + i*GFX_BPL_SIZE (plans contigus)
        lea     GFX_O_BITMAP+bm_Planes(a2),a0
        move.l  a4,d0
        moveq   #GFX_BOOT_DEPTH-1,d1
.gfx_pl:
        move.l  d0,(a0)+
        add.l   #GFX_BOOT_PLANE_SZ,d0
        dbf     d1,.gfx_pl
        ; RasInfo -> BitMap
        lea     GFX_O_BITMAP(a2),a0
        move.l  a0,GFX_O_RASINFO+ri_BitMap(a2)
        ; ColorMap : 32 couleurs copiées depuis la palette ROM
        move.w  #GFX_BOOT_NCOLORS,GFX_O_COLORMAP+cm_Count(a2)
        lea     GFX_O_COLORTAB(a2),a0
        move.l  a0,GFX_O_COLORMAP+cm_ColorTable(a2)
        move.l  #bootscreen_palette,a1
        move.w  #GFX_BOOT_NCOLORS-1,d0
.gfx_pal:
        move.w  (a1)+,(a0)+
        dbf     d0,.gfx_pal
        ; ViewPort (overscan 352x272)
        move.w  #GFX_BOOT_W,GFX_O_VP+vp_DWidth(a2)
        move.w  #GFX_BOOT_H,GFX_O_VP+vp_DHeight(a2)
        lea     GFX_O_RASINFO(a2),a0
        move.l  a0,GFX_O_VP+vp_RasInfo(a2)
        lea     GFX_O_COLORMAP(a2),a0
        move.l  a0,GFX_O_VP+vp_ColorMap(a2)
        ; View -> ViewPort
        lea     GFX_O_VP(a2),a0
        move.l  a0,GFX_O_VIEW+v_ViewPort(a2)
        ; 3. FindName("graphics.library")
        lea     EB_LIBLIST(a6),a0
        lea     gfx_libname(pc),a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        beq     .gfx_ret                     ; pas de graphics.library -> pas d'affichage
        move.l  d0,a5                        ; a5 = GfxBase
        ; 4. MakeVPort(view,vp) ; MrgCop(view) ; LoadView(view) VIA LA JUMP TABLE
        lea     GFX_O_VIEW(a2),a0
        lea     GFX_O_VP(a2),a1
        move.l  a5,a6
        jsr     LVO_MAKEVPORT(a6)
        move.l  a5,a6
        lea     GFX_O_VIEW(a2),a1
        jsr     LVO_MRGCOP(a6)
        move.l  a5,a6
        lea     GFX_O_VIEW(a2),a1
        jsr     LVO_LOADVIEW(a6)
.gfx_ret:
        move.l  ($4).w,a6                    ; restaure a6 = SysBase (handoff scheduler)
        movem.l (sp)+,a2/a4/a5
        rts

gfx_libname:
        dc.b    "graphics.library",0
        EVEN
