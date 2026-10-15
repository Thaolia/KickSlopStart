; src/graphics/graphics.i — registres d'affichage OCS + constantes M4.
; Piste IMPLÉMENTATION (« clean ») : Amiga Hardware Reference Manual + AutoDocs (public). AUCUNE lecture ROM.
; CUSTOM est défini dans exec.i (inclus AVANT ce fichier). Un copper MOVE vise un OFFSET custom (reg-CUSTOM).

; --- registres d'affichage (adresses absolues ; HRM) ---
COP1LC   EQU CUSTOM+$080      ; pointeur Copper list 1 (longword ; rechargé par le hardware à chaque VBlank)
COPJMP1  EQU CUSTOM+$088      ; strobe : (re)démarre le Copper sur COP1LC (write-strobe, valeur ignorée)
DIWSTRT  EQU CUSTOM+$08E      ; display window start (coin haut-gauche)
DIWSTOP  EQU CUSTOM+$090      ; display window stop  (coin bas-droit)
DDFSTRT  EQU CUSTOM+$092      ; display data fetch start
DDFSTOP  EQU CUSTOM+$094      ; display data fetch stop
BPLCON0  EQU CUSTOM+$100      ; bitplane control ; bits 14-12 = BPU (nb de bitplanes) ; 0 = fond COLOR00 seul

; --- bits DMACON (dmabits.i) ---
DMAF_SETCLR EQU $8000         ; 1 = positionne les bits à 1 ; 0 = les met à 0
DMAF_COPPER EQU $0080         ; canal DMA Copper
DMAF_MASTER EQU $0200         ; DMA maître (requis pour que TOUT canal DMA fonctionne)

; --- valeurs d'init display standard (HRM) : fenêtre lores ~320x256 PAL, 0 bitplane en M4a ---
GFX_DIWSTRT  EQU $2C81        ; vstart=$2C (44), hstart=$81 (129)
GFX_DIWSTOP  EQU $2CC1        ; PAL : vstop field $2C -> 300 (V8 = complément de V7), hstop $C1 -> 449
GFX_DDFSTRT  EQU $0038        ; lores
GFX_DDFSTOP  EQU $00D0        ; lores
; Couleur de preuve M4a : vert 12-bit $0F0. JAMAIS écrite par le CPU (cf. C_RED/BLUE/CYAN/WHITE/FAIL) ->
; sa présence à l'écran ⟺ le Copper DMA pilote COLOR00. C'est l'UNIQUE discriminant GREEN/RED de M4a.
GFX_PROOF_COLOR EQU $0F0

; M4A_NO_COPPER=1 (RED) : gfx_display_init construit la copper list et pose COP1LC, mais SAUTE l'activation
; de DMACON (COPEN) -> le Copper reste inerte -> COLOR00 garde la dernière valeur CPU (blanc « self-test
; passed ») -> le vert est ABSENT. Prouve que c'est bien le Copper DMA qui affiche. Défaut 0 (inerte).
M4A_NO_COPPER   EQU 0
