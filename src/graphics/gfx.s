; src/graphics/gfx.s — M4a : PREMIER AFFICHAGE piloté par le Copper.
; Premier module de la piste graphique. M4a prouve le COPPER DMA seul (pas encore de bitplane, pas encore
; l'ABI graphics.library) : une copper list pose la fenêtre display standard + 0 bitplane + COLOR00 = vert
; de preuve. Le Copper ré-exécute la liste à chaque frame -> COLOR00 = vert en permanence (une écriture CPU
; unique ne peut pas être « rejouée » chaque frame ; et le vert n'est JAMAIS écrit par le CPU). L'écran vert
; ⟺ Copper DMA actif = UNIQUE discriminant M4a (canal VISUEL load-bearing, cf. preuve FRAC du harnais).
;
; CONTRAINTE MATÉRIELLE CLÉ : le Copper (Agnus) lit UNIQUEMENT la chip RAM, jamais la ROM ($FC0000, bus CPU).
; La liste est donc copiée ROM -> buffer chip (AllocMem MEMF_CHIP) avant d'être pointée par COP1LC.
;
; Piste IMPLÉMENTATION (« clean ») : Amiga Hardware Reference Manual + AutoDocs graphics. AUCUNE lecture ROM.

                include "exec.i"
                include "graphics.i"

                xdef    gfx_display_init

; gfx_display_init(a6 = SysBase) : alloue la copper list en chip RAM, la remplit depuis le template ROM,
; pointe COP1LC dessus et active le Copper DMA. PRÉSERVE a6 (le handoff scheduler juste après en dépend) ;
; scratch d0/d1/a0/a1 + d2/a2 (sauvés). Non fatal si l'AllocMem échoue (la démo exec reste intacte).
gfx_display_init:
        movem.l d2/a2,-(sp)
        move.l  #(gfx_cop_end-gfx_cop),d0   ; taille de la liste (octets)
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.s   .gfx_ret                    ; pas de chip RAM -> pas d'affichage
        move.l  d0,a2                        ; a2 = copper list (chip RAM)
        lea     gfx_cop(pc),a0               ; template (ROM)
        move.l  a2,a1
        move.w  #((gfx_cop_end-gfx_cop)/2)-1,d2
.gfx_copy:
        move.w  (a0)+,(a1)+                  ; ROM -> chip (le Copper lira la copie chip)
        dbf     d2,.gfx_copy
        move.l  a2,COP1LC                    ; COP1LC = adresse chip de la liste (longword)
                ifeq    M4A_NO_COPPER
        move.w  #(DMAF_SETCLR|DMAF_MASTER|DMAF_COPPER),DMACON  ; DMA maître + Copper ON (gaté : RED = sauté)
                endc
        move.w  #0,COPJMP1                   ; strobe COP1 : démarre le Copper (no-op si COPEN off = RED)
        move.l  a2,GFX_COPLIST_PTR           ; publie la liste (M4b + libération éventuelle)
.gfx_ret:
        movem.l (sp)+,d2/a2
        rts

; Template copper list (ROM), copié en chip RAM. Un MOVE vise l'OFFSET custom (reg-CUSTOM, bit0=0) ;
; les constantes exec.i (DIWSTRT, ... COLOR00) sont des adresses absolues -> « reg-CUSTOM » = l'offset.
; M4a : fenêtre display standard, BPLCON0=0 (0 bitplane -> fond COLOR00 seul), COLOR00 = vert de preuve,
; puis WAIT $FFFF,$FFFE (position inatteignable -> fin de liste jusqu'au rechargement de COP1LC au VBlank).
        EVEN
gfx_cop:
        dc.w    DIWSTRT-CUSTOM,GFX_DIWSTRT
        dc.w    DIWSTOP-CUSTOM,GFX_DIWSTOP
        dc.w    DDFSTRT-CUSTOM,GFX_DDFSTRT
        dc.w    DDFSTOP-CUSTOM,GFX_DDFSTOP
        dc.w    BPLCON0-CUSTOM,$0000
        dc.w    COLOR00-CUSTOM,GFX_PROOF_COLOR
        dc.w    $FFFF,$FFFE
gfx_cop_end:
        EVEN
