; src/graphics/gfx.s — M4a/M4b : PREMIER AFFICHAGE piloté par le Copper.
; M4a prouvait le COPPER DMA (fond de couleur). M4b ajoute un vrai BITPLANE : le chipset va chercher les
; données de pixels en chip RAM (DMA bitplane) et les composite -> on affiche de vrais PIXELS. Motif = rayures
; verticales (mots $FF00) : 8 px « 1 » = COLOR01 vert, 8 px « 0 » = COLOR00 bleu. Rayures vertes à l'écran
; ⟺ bitplane DMA actif (le vert $0F0 n'est AUCUNE couleur écrite par le CPU). Canal de preuve = VISUEL.
;
; CONTRAINTE MATÉRIELLE : le Copper ET le bitplane DMA (Agnus) lisent UNIQUEMENT la chip RAM, jamais la ROM
; ($FC0000 = bus CPU). Copper list ET bitplane sont donc AllocMem(MEMF_CHIP). Le pointeur bitplane (BPL1PT)
; vit DANS la copper list (rechargé à chaque VBlank, car il auto-incrémente pendant la frame) -> on le patche
; au runtime dans la copie chip avec l'adresse du bitplane alloué.
;
; Piste IMPLÉMENTATION (« clean ») : Amiga Hardware Reference Manual + AutoDocs graphics. AUCUNE lecture ROM.

                include "exec.i"
                include "graphics.i"

                xdef    gfx_display_init

; --- Template copper list (ROM), copié en chip RAM. Un MOVE vise l'OFFSET custom (reg-CUSTOM, bit0=0). ---
; Placé AVANT la fonction -> les labels de patch se résolvent en références arrière. Fenêtre display standard,
; BPU=1 (gaté), BPL1PT patché au runtime, COLOR00=bleu/COLOR01=vert, WAIT $FFFF,$FFFE (fin de liste).
        EVEN
gfx_cop:
        dc.w    DIWSTRT-CUSTOM,GFX_DIWSTRT
        dc.w    DIWSTOP-CUSTOM,GFX_DIWSTOP
        dc.w    DDFSTRT-CUSTOM,GFX_DDFSTRT
        dc.w    DDFSTOP-CUSTOM,GFX_DDFSTOP
        dc.w    BPLCON0-CUSTOM,GFX_BPLCON0
        dc.w    BPLCON1-CUSTOM,$0000
        dc.w    BPL1MOD-CUSTOM,$0000
gfx_cop_bpl1h:
        dc.w    BPL1PTH-CUSTOM,$0000       ; patché : mot HAUT de l'adresse du bitplane
gfx_cop_bpl1l:
        dc.w    BPL1PTL-CUSTOM,$0000       ; patché : mot BAS
        dc.w    COLOR00-CUSTOM,GFX_BG_COLOR
        dc.w    COLOR01-CUSTOM,GFX_PROOF_COLOR
        dc.w    $FFFF,$FFFE
gfx_cop_end:
        EVEN

GFX_COP_SIZE EQU gfx_cop_end-gfx_cop        ; octets de la liste
GFX_P_BPL1H  EQU gfx_cop_bpl1h+2-gfx_cop    ; offset du mot-donnée BPL1PTH dans la liste (patch)
GFX_P_BPL1L  EQU gfx_cop_bpl1l+2-gfx_cop    ; offset du mot-donnée BPL1PTL

; gfx_display_init(a6 = SysBase) : alloue bitplane + copper list en chip RAM, remplit les rayures, patche le
; pointeur bitplane dans la liste, pointe COP1LC et active Copper + bitplane DMA. PRÉSERVE a6 (le handoff
; scheduler juste après en dépend) ; scratch d0/d1/a0/a1 + d2/d3/a2/a3 (sauvés). Non fatal si AllocMem échoue.
gfx_display_init:
        movem.l d2/d3/a2/a3,-(sp)
        move.l  #GFX_BPL_SIZE,d0            ; 1. bitplane en chip RAM
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.s   .gfx_ret
        move.l  d0,a3                        ; a3 = bitplane
        move.l  a3,a1                         ; 2. remplir les rayures ($FF00 : 8 px vert / 8 px bleu)
        move.w  #(GFX_BPL_SIZE/2)-1,d2
        move.w  #GFX_STRIPE_WORD,d3
.gfx_fill:
        move.w  d3,(a1)+
        dbf     d2,.gfx_fill
        move.l  #GFX_COP_SIZE,d0             ; 3. copper list en chip RAM
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.s   .gfx_ret                     ; (bitplane fuit mais non fatal)
        move.l  d0,a2                         ; a2 = copper list (chip)
        lea     gfx_cop(pc),a0               ; 4. copier le template ROM -> chip
        move.l  a2,a1
        move.w  #(GFX_COP_SIZE/2)-1,d2
.gfx_copy:
        move.w  (a0)+,(a1)+
        dbf     d2,.gfx_copy
        move.l  a3,d0                         ; 5. patcher BPL1PT avec l'adresse du bitplane (hi/lo)
        move.w  d0,GFX_P_BPL1L(a2)           ; mot BAS -> entrée BPL1PTL ($0E2)
        swap    d0
        move.w  d0,GFX_P_BPL1H(a2)           ; mot HAUT -> entrée BPL1PTH ($0E0)
        move.l  a2,COP1LC                     ; 6. activer : COP1LC = liste chip
                ifeq    M4A_NO_COPPER
        move.w  #GFX_DMA_BITS,DMACON         ; DMA maître + Copper (+ bitplane RASTER sauf RED M4b) ; gaté M4a
                endc
        move.w  #0,COPJMP1                    ; strobe COP1 (no-op si COPEN off = RED M4a)
        move.l  a2,GFX_COPLIST_PTR           ; publie la liste
.gfx_ret:
        movem.l (sp)+,d2/d3/a2/a3
        rts
