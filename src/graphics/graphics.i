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
BPLCON1  EQU CUSTOM+$102      ; scroll fin (0 = pas de décalage)
BPL1MOD  EQU CUSTOM+$108      ; modulo bitplane impair (0 = bitplane contigu)
BPL1PTH  EQU CUSTOM+$0E0      ; pointeur bitplane 1, mot HAUT (patché au runtime dans la copper list)
BPL1PTL  EQU CUSTOM+$0E2      ; pointeur bitplane 1, mot BAS
COLOR01  EQU CUSTOM+$182      ; couleur du pixel « 1 » (1er bitplane)

; --- bits DMACON (dmabits.i) ---
DMAF_SETCLR EQU $8000         ; 1 = positionne les bits à 1 ; 0 = les met à 0
DMAF_COPPER EQU $0080         ; canal DMA Copper
DMAF_RASTER EQU $0100         ; canal DMA bitplane (fetch des données de pixels depuis la chip RAM)
DMAF_MASTER EQU $0200         ; DMA maître (requis pour que TOUT canal DMA fonctionne)

; --- valeurs d'init display standard (HRM) : fenêtre lores ~320x256 PAL, 0 bitplane en M4a ---
GFX_DIWSTRT  EQU $2C81        ; vstart=$2C (44), hstart=$81 (129)
GFX_DIWSTOP  EQU $2CC1        ; PAL : vstop field $2C -> 300 (V8 = complément de V7), hstop $C1 -> 449
GFX_DDFSTRT  EQU $0038        ; lores
GFX_DDFSTOP  EQU $00D0        ; lores
; Couleur de preuve : vert 12-bit $0F0. JAMAIS écrite par le CPU (cf. C_RED/BLUE/CYAN/WHITE/FAIL) -> sa
; présence à l'écran ⟺ l'affichage chipset la produit. En M4b elle est portée par COLOR01 (pixel bitplane).
GFX_PROOF_COLOR EQU $0F0       ; COLOR01 : pixel « 1 » (preuve M4b)
GFX_BG_COLOR    EQU $00F       ; COLOR00 : fond bleu (M4b) ; le vert vient alors UNIQUEMENT du bitplane

; --- M4b : bitplane 320x256x1 plan (lores, fenêtre display standard) ---
GFX_BPL_BYTES   EQU 40         ; octets par ligne (320 px / 8)
GFX_BPL_ROWS    EQU 256
GFX_BPL_SIZE    EQU GFX_BPL_BYTES*GFX_BPL_ROWS   ; 10240 o
GFX_STRIPE_WORD EQU $FF00      ; motif de remplissage : 8 px « 1 » (vert) + 8 px « 0 » (bleu) -> rayures verticales

; M4A_NO_COPPER=1 (RED M4a) : gfx_display_init construit tout mais SAUTE l'activation de DMACON -> le Copper
; reste inerte -> COLOR00 garde la dernière valeur CPU (blanc) -> écran BLANC. Prouve le Copper DMA. Défaut 0.
M4A_NO_COPPER   EQU 0
; M4B_NO_BITPLANE=1 (RED M4b) : BPLCON0 BPU=0 + pas de DMAF_RASTER -> aucun bitplane fetché -> fenêtre = fond
; bleu uni (COLOR00), les rayures vertes (COLOR01) sont ABSENTES. Prouve que le bitplane DMA est load-bearing.
M4B_NO_BITPLANE EQU 0
; Valeurs gatées : BPLCON0 (BPU) et bits DMACON. Trois états cohérents du display selon les gates :
;   défaut (0/0)            -> bleu + rayures vertes (M4b complet)
;   M4B_NO_BITPLANE=1       -> bleu uni (Copper OK, pas de bitplane)
;   M4A_NO_COPPER=1         -> blanc (Copper off)
                ifeq    M4B_NO_BITPLANE
GFX_BPLCON0     EQU $1200      ; BPU=1 (bit 12) + COLOR (bit 9) ; ni HIRES/HAM/DBLPF
GFX_DMA_BITS    EQU (DMAF_SETCLR|DMAF_MASTER|DMAF_COPPER|DMAF_RASTER)
                else
GFX_BPLCON0     EQU $0000      ; BPU=0 -> aucun bitplane
GFX_DMA_BITS    EQU (DMAF_SETCLR|DMAF_MASTER|DMAF_COPPER)
                endc
