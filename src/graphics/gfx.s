; src/graphics/gfx.s — M4c2 : bootstrap de l'affichage VIA L'ABI graphics.library.
; gfx_display_init monte les structures BitMap/RasInfo/ColorMap/ViewPort/View (le bitplane rayé de M4b est
; réutilisé comme plan de la BitMap), ouvre graphics.library (FindName), puis appelle MakeVPort/MrgCop/LoadView
; VIA LA JUMP TABLE -> la copper list est GÉNÉRÉE depuis les structures (plus de template codé en dur). Preuve
; par ÉLIMINATION : les rayures à l'écran ne peuvent venir que de l'ABI, puisqu'aucun template ne subsiste.
; Historique : M4a (fond Copper) / M4b (bitplane) utilisaient un template copper hardcodé -> SUPPRIMÉ en M4c2.
;
; CONTRAINTE : Copper et bitplane DMA (Agnus) lisent UNIQUEMENT la chip RAM -> bitplane, structures et listes
; copper générées sont toutes AllocMem(MEMF_CHIP).
; Piste IMPLÉMENTATION (« clean ») : AutoDocs graphics.library + HRM. AUCUNE lecture ROM.

                include "exec.i"
                include "graphics.i"

                xdef    gfx_display_init

; gfx_display_init(a6 = SysBase) : alloue bitplane + bloc de structures, monte View/ViewPort/BitMap/ColorMap,
; FindName("graphics.library"), puis MakeVPort/MrgCop/LoadView via la jump table GfxBase. RESTAURE a6 = SysBase
; en sortie (le handoff scheduler en dépend). Scratch d0/d1/a0/a1 + d2/d3/a2/a3/a5 (sauvés). Non fatal si KO.
gfx_display_init:
        movem.l d2/d3/a2/a3/a5,-(sp)
        move.l  #GFX_BPL_SIZE,d0            ; 1. bitplane chip + rayures ($FF00)
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .gfx_ret
        move.l  d0,a3                        ; a3 = bitplane
        move.l  a3,a1
        move.w  #(GFX_BPL_SIZE/2)-1,d2
        move.w  #GFX_STRIPE_WORD,d3
.gfx_fill:
        move.w  d3,(a1)+
        dbf     d2,.gfx_fill
        move.l  #GFX_STRUCT_SIZE,d0         ; 2. bloc de structures chip (View/VP/RasInfo/BitMap/ColorMap/Table)
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .gfx_ret
        move.l  d0,a2                        ; a2 = bloc de structures
        ; BitMap
        move.w  #GFX_BPL_BYTES,GFX_O_BITMAP+bm_BytesPerRow(a2)
        move.w  #GFX_BPL_ROWS,GFX_O_BITMAP+bm_Rows(a2)
        move.b  #1,GFX_O_BITMAP+bm_Depth(a2)
        move.l  a3,GFX_O_BITMAP+bm_Planes(a2)      ; Planes[0] = bitplane
        ; RasInfo -> BitMap
        lea     GFX_O_BITMAP(a2),a0
        move.l  a0,GFX_O_RASINFO+ri_BitMap(a2)
        ; ColorTable [bleu, vert] + ColorMap
        move.w  #GFX_BG_COLOR,GFX_O_COLORTAB(a2)
        move.w  #GFX_PROOF_COLOR,GFX_O_COLORTAB+2(a2)
        move.w  #2,GFX_O_COLORMAP+cm_Count(a2)
        lea     GFX_O_COLORTAB(a2),a0
        move.l  a0,GFX_O_COLORMAP+cm_ColorTable(a2)
        ; ViewPort
        move.w  #320,GFX_O_VP+vp_DWidth(a2)
        move.w  #256,GFX_O_VP+vp_DHeight(a2)
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
        beq.s   .gfx_ret                     ; pas de graphics.library -> pas d'affichage
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
        movem.l (sp)+,d2/d3/a2/a3/a5
        rts

gfx_libname:
        dc.b    "graphics.library",0
        EVEN
