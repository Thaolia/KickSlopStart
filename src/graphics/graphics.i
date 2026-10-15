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

; M4c2 : l'affichage est désormais GÉNÉRÉ par l'ABI graphics.library (MakeVPort/MrgCop/LoadView) depuis les
; structures View/ViewPort/BitMap/ColorMap — le template copper codé en dur de M4a/M4b est SUPPRIMÉ. La preuve
; « GREEN=rayures » vaut par ÉLIMINATION : plus aucun autre chemin ne dessine les rayures. Les gates M4A_NO_COPPER
; et M4B_NO_BITPLANE (qui gataient ce template) sont donc RETIRÉS.
GFX_DMA_ON    EQU (DMAF_SETCLR|DMAF_MASTER|DMAF_COPPER|DMAF_RASTER)  ; activé par LoadView
GFX_COLOR_BIT EQU $0200        ; BPLCON0 bit 9 (COLOR composite) ; BPLCON0 généré = (depth<<12) | GFX_COLOR_BIT
; M4C2_NO_MRGCOP=1 (RED M4c2) : MrgCop ne fusionne PAS les fragments vp_DspIns -> v_LOFCprList ne contient que
; le WAIT final -> LoadView installe une liste vide -> COLOR00 garde le blanc CPU -> écran BLANC, rayures absentes.
; Prouve que la génération de la copper list par l'ABI est load-bearing. Défaut 0 (inerte).
M4C2_NO_MRGCOP EQU 0

; --- Offsets structures graphics (view.i/gfx.i ; champs de base, stables V34) ---
v_ViewPort   EQU 0            ; View
v_LOFCprList EQU 4
v_SIZEOF     EQU 18
vp_Next      EQU 0            ; ViewPort
vp_ColorMap  EQU 4
vp_DspIns    EQU 8
vp_DWidth    EQU 24
vp_DHeight   EQU 26
vp_Modes     EQU 32
vp_RasInfo   EQU 36
vp_SIZEOF    EQU 40
ri_BitMap    EQU 4            ; RasInfo
ri_SIZEOF    EQU 12
bm_BytesPerRow EQU 0          ; BitMap
bm_Rows      EQU 2
bm_Depth     EQU 5
bm_Planes    EQU 8            ; bm_Planes[0..7] (APTR x8)
bm_SIZEOF    EQU 40
cm_Count     EQU 2            ; ColorMap (début V34 : Flags/Type/Count/ColorTable)
cm_ColorTable EQU 4
GCM_SIZEOF   EQU 8

; --- LVO graphics.library (lvo/graphics_lib.fd) ---
LVO_INITVPORT EQU -204
LVO_MRGCOP    EQU -210
LVO_MAKEVPORT EQU -216
LVO_LOADVIEW  EQU -222

; --- GfxBase : champs minimaux (au-delà de la base Library) ---
gb_ActiView  EQU LIB_SIZE     ; APTR : View actif (posé par LoadView)
gb_LOFlist   EQU LIB_SIZE+4   ; APTR : copper list courante
GFXBASE_SIZE EQU LIB_SIZE+8

; --- Tailles des listes copper générées (chip RAM) ---
GFX_FRAG_WORDS EQU 22         ; fragment MakeVPort : 11 MOVEs (DIW/DDF/BPLCON0/1/BPL1MOD/BPL1PT/COLOR00-01)
GFX_FRAG_SIZE  EQU GFX_FRAG_WORDS*2
GFX_MASTER_SIZE EQU GFX_FRAG_SIZE+4   ; + WAIT final ajouté par MrgCop

; --- Layout du bloc de structures AllocMem'd par gfx_display_init ---
GFX_O_VIEW     EQU 0
GFX_O_VP       EQU 20         ; après View (v_SIZEOF 18, aligné pair)
GFX_O_RASINFO  EQU 60         ; après ViewPort (vp_SIZEOF 40)
GFX_O_BITMAP   EQU 72         ; après RasInfo (ri_SIZEOF 12)
GFX_O_COLORMAP EQU 112        ; après BitMap (bm_SIZEOF 40)
GFX_O_COLORTAB EQU 120        ; après ColorMap (8)
GFX_STRUCT_SIZE EQU 124

; M4c1 : graphics.library comme module résident. M4C1_WRONG_TYPE=1 (RED) : RT_TYPE du ROMTag = NT_DEVICE au
; lieu de NT_LIBRARY -> le chemin AUTOINIT route GfxBase vers DeviceList (pas LibList) -> FindName(LibList)
; échoue -> « M4C1 GFX LIB OK » absent. Isole la branche de routage NT_LIBRARY->LibList (neuve : seul
; NT_DEVICE était exercé jusqu'ici). Défaut 0 (inerte).
M4C1_WRONG_TYPE EQU 0
