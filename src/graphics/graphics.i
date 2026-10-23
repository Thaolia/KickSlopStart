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
BPLCON2  EQU CUSTOM+$104      ; priorités sprites / playfields
GFX_BPLCON2 EQU $0024         ; PF2P = PF1P = 4 : tous les sprites devant les playfields
BPL1MOD  EQU CUSTOM+$108      ; modulo bitplane impair (plans 1,3,5 ; 0 = plans contigus)
BPL2MOD  EQU CUSTOM+$10A      ; modulo bitplane pair (plans 2,4,6 ; 0 = plans contigus)
BPL1PTH  EQU CUSTOM+$0E0      ; pointeur bitplane 1, mot HAUT ; BPLxPTH = BPL1PTH + (x-1)*4 (généré au runtime)
BPL1PTL  EQU CUSTOM+$0E2      ; pointeur bitplane 1, mot BAS
COLOR01  EQU CUSTOM+$182      ; couleur du pixel « 1 » (1er bitplane) ; COLORxx = COLOR00 + xx*2

; --- bits DMACON (dmabits.i) ---
DMAF_SETCLR EQU $8000         ; 1 = positionne les bits à 1 ; 0 = les met à 0
DMAF_COPPER EQU $0080         ; canal DMA Copper
DMAF_RASTER EQU $0100         ; canal DMA bitplane (fetch des données de pixels depuis la chip RAM)
DMAF_MASTER EQU $0200         ; DMA maître (requis pour que TOUT canal DMA fonctionne)

; --- valeurs d'init display (HRM) : OVERSCAN lores 352x272 PAL (remplit l'écran bord-à-bord pour l'écran de boot) ---
; hstart=$71 (113), hstop=113+352=465=$1D1 (H8 forcé 1) ; vstart=$24 (36), vstop=36+272=308=$134 (V8=~V7).
GFX_DIWSTRT  EQU $2471        ; vstart=$24 (36), hstart=$71 (113)
GFX_DIWSTOP  EQU $34D1        ; vstop field $34 -> $134=308 (V8=~V7) ; hstop $D1 -> $1D1=465
GFX_DDFSTRT  EQU $0030        ; lores : (hstart-17)/2 = (113-17)/2 = 48
GFX_DDFSTOP  EQU $00D8        ; lores : DDFSTRT + 8*(words-1) = $30 + 8*21 = $D8 (22 mots = 352 px)
; Couleur de preuve : vert 12-bit $0F0. JAMAIS écrite par le CPU (cf. C_RED/BLUE/CYAN/WHITE/FAIL) -> sa
; présence à l'écran ⟺ l'affichage chipset la produit. En M4b elle est portée par COLOR01 (pixel bitplane).
GFX_PROOF_COLOR EQU $0F0       ; COLOR01 : pixel « 1 » (preuve M4b)
GFX_BG_COLOR    EQU $00F       ; COLOR00 : fond bleu (M4b) ; le vert vient alors UNIQUEMENT du bitplane

; --- bitplane 320x256 (lores, fenêtre display standard) ; 1 plan en M4b/stripes, 5 plans pour l'écran de boot ---
GFX_BPL_BYTES   EQU 40         ; octets par ligne (320 px / 8)
GFX_BPL_ROWS    EQU 256
GFX_BPL_SIZE    EQU GFX_BPL_BYTES*GFX_BPL_ROWS   ; 10240 o (un plan)
GFX_STRIPE_WORD EQU $FF00      ; motif de remplissage M4b : 8 px « 1 » + 8 px « 0 » -> rayures (historique)

; --- Écran de boot (image chaton « KickSlopStart », générée par src/graphics/mk_bootscreen.py) ---
; Résolution overscan 352x272 (doit coïncider avec WIDTH/HEIGHT de mk_bootscreen.py et avec GFX_DIWSTRT/DDF* ci-dessus).
GFX_BOOT_DEPTH    EQU 5                         ; 5 bitplanes = 32 couleurs (OCS lores)
GFX_BOOT_NCOLORS  EQU 32
GFX_BOOT_W        EQU 352                       ; largeur display (overscan)
GFX_BOOT_H        EQU 272                       ; hauteur display (overscan)
GFX_BOOT_BYTES    EQU GFX_BOOT_W/8              ; 44 octets par ligne
GFX_BOOT_PLANE_SZ EQU GFX_BOOT_BYTES*GFX_BOOT_H ; 11968 o (un plan)
GFX_BOOT_PLANES_SZ EQU GFX_BOOT_PLANE_SZ*GFX_BOOT_DEPTH  ; 59840 o (5 plans contigus en chip RAM)
; BOOTSCR_ONE_PLANE=1 (RED) : gfx_display_init pose bm_Depth=1 (plan 0 seul) -> l'ABI n'émet qu'un pointeur de
; plan + 2 couleurs -> l'image chaton est détruite (2 couleurs, structure fausse) -> la preuve VISUELLE (RMSE
; capture vs référence) échoue, sans toucher le boot (marqueurs série intacts). Isole le rendu multi-bitplane.
BOOTSCR_ONE_PLANE EQU 0

; M4c2 : l'affichage est désormais GÉNÉRÉ par l'ABI graphics.library (MakeVPort/MrgCop/LoadView) depuis les
; structures View/ViewPort/BitMap/ColorMap — le template copper codé en dur de M4a/M4b est SUPPRIMÉ. La preuve
; « GREEN=rayures » vaut par ÉLIMINATION : plus aucun autre chemin ne dessine les rayures. Les gates M4A_NO_COPPER
; et M4B_NO_BITPLANE (qui gataient ce template) sont donc RETIRÉS.
GFX_DMA_ON    EQU (DMAF_SETCLR|DMAF_MASTER|DMAF_COPPER|DMAF_RASTER|DMAF_SPRITE)  ; activé par LoadView
GFX_HIRES_BIT EQU $8000        ; BPLCON0 bit 15 (HIRES), posé si vp_Modes a le bit HIRES ($8000)
GFX_COLOR_BIT EQU $0200        ; BPLCON0 bit 9 (COLOR composite) ; BPLCON0 généré = (depth<<12) | GFX_COLOR_BIT
; M4C2_NO_MRGCOP=1 (RED M4c2) : MrgCop ne fusionne PAS les fragments vp_DspIns -> v_LOFCprList ne contient que
; le WAIT final -> LoadView installe une liste vide -> COLOR00 garde le blanc CPU -> écran BLANC, rayures absentes.
; Prouve que la génération de la copper list par l'ABI est load-bearing. Défaut 0 (inerte).
M4C2_NO_MRGCOP EQU 0

; --- Offsets structures graphics (view.i/gfx.i ; champs de base, stables V34) ---
v_ViewPort   EQU 0            ; View
v_LOFCprList EQU 4
v_Modes      EQU 16
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
rp_Layer     EQU 0            ; RastPort (graphics/rastport.i, V34)
rp_BitMap    EQU 4
rp_Mask      EQU 24
rp_FgPen     EQU 25
rp_BgPen     EQU 26
rp_AOlPen    EQU 27
rp_DrawMode  EQU 28
rp_LinePtrn  EQU 34
rp_cp_x      EQU 36
rp_cp_y      EQU 38
rp_Font      EQU 52
rp_TxHeight  EQU 58
rp_TxWidth   EQU 60
rp_TxBaseline EQU 62
rp_AlgoStyle EQU 56           ; UBYTE : styles algorithmiques (SetSoftStyle)
rp_TxSpacing EQU 64           ; WORD : espacement ajouté après chaque caractère
rp_SIZEOF    EQU 100
lr_rp        EQU 12           ; Layer : RastPort de la couche
lr_MinX      EQU 16           ; Layer : bounds (struct Rectangle) — seul champ exploité (décalage + découpage)
lr_MinY      EQU 18
lr_MaxX      EQU 20
lr_MaxY      EQU 22
lr_SIZEOF    EQU 160          ; struct Layer V34 (champs au-delà de bounds non utilisés ici)
JAM1         EQU 0            ; rp_DrawMode
JAM2         EQU 1
COMPLEMENT   EQU 2
INVERSVID    EQU 4
; TextFont / TextAttr (graphics/text.h) : en-tête Message (mn_Node + ReplyPort + Length) puis la police
tf_YSize     EQU 20
tf_Style     EQU 22
tf_Flags     EQU 23
tf_XSize     EQU 24
tf_Baseline  EQU 26
tf_BoldSmear EQU 28
tf_Accessors EQU 30
tf_LoChar    EQU 32
tf_HiChar    EQU 33
tf_CharData  EQU 34
tf_Modulo    EQU 38
tf_CharLoc   EQU 40           ; par caractère : décalage en bits (WORD) puis largeur (WORD)
tf_CharSpace EQU 44           ; WORD par caractère, 0 = tf_XSize pour tous
tf_CharKern  EQU 48           ; WORD par caractère, 0 = aucun
tf_SIZEOF    EQU 52
ta_Name      EQU 0
ta_YSize     EQU 4
ta_Style     EQU 6
ta_Flags     EQU 7
NT_FONT      EQU 12
FSF_UNDERLINED EQU $01
FSF_BOLD     EQU $02
FSF_ITALIC   EQU $04
FPF_ROMFONT  EQU $01
FPF_DESIGNED EQU $40
FPB_REMOVED  EQU 7
GFX_FONTW    EQU 8            ; police 8x8 de la ROM (font8x8) : largeur, hauteur, ligne de base
GFX_FONTH    EQU 8
GFX_FONTBASE EQU 6
cm_Count     EQU 2            ; ColorMap (début V34 : Flags/Type/Count/ColorTable)
cm_ColorTable EQU 4
GCM_SIZEOF   EQU 8

; --- LVO graphics.library (lvo/graphics_lib.fd) ---
LVO_INITVPORT EQU -204
LVO_MRGCOP    EQU -210
LVO_MAKEVPORT EQU -216
LVO_LOADVIEW  EQU -222
LVO_TEXT      EQU -60
LVO_SETFONT   EQU -66
LVO_INITRASTPORT EQU -198
LVO_SETRAST   EQU -234
LVO_MOVE      EQU -240
LVO_DRAW      EQU -246
LVO_RECTFILL  EQU -306
LVO_SETAPEN   EQU -342
LVO_SETBPEN   EQU -348
LVO_SETDRMD   EQU -354
LVO_INITBITMAP EQU -390
LVO_SCROLLRASTER EQU -396
LVO_FREEVPORTCOPLISTS EQU -540
LVO_GETSPRITE EQU -408
LVO_BLTBITMAPRASTPORT EQU -606
LVO_CHANGESPRITE EQU -420
LVO_MOVESPRITE EQU -426
V_HIRES       EQU $8000        ; vp_Modes : haute résolution (640 px)

; --- GfxBase : disposition publique V34 (graphics/gfxbase.i) puis champs privés au-delà ---
gb_ActiView  EQU 34           ; APTR : View actif (posé par LoadView)
gb_copinit   EQU 38
gb_LOFlist   EQU 50           ; APTR : copper list longue en cours d'affichage
gb_SHFlist   EQU 54
gb_TextFonts EQU 140          ; struct List des polices
gb_DefaultFont EQU 154        ; APTR : police par défaut des RastPort (topaz 8)
gb_Modes     EQU 158          ; UWORD : modes de la vue affichée (View->Modes)
gb_VBlank    EQU 160          ; BYTE : fréquence de trame
gb_system_bplcon0 EQU 164     ; WORD : bits BPLCON0 imposés par le système
gb_DisplayFlags EQU 206       ; UWORD : NTSC 1 / GENLOC 2 / PAL 4
gb_MaxDisplayRow EQU 212
gb_MaxDisplayColumn EQU 214
gb_NormalDisplayRows EQU 216
gb_NormalDisplayColumns EQU 218
gb_NormalDPMX EQU 220
gb_NormalDPMY EQU 222
gb_MicrosPerLine EQU 232      ; UWORD : 256 × durée d'une ligne en µs
GB_PUBLIC    EQU 242          ; fin de la partie publique V34 (dont reserved[2])
; champs privés : sprites matériels
gb_SprNull   EQU GB_PUBLIC    ; APTR : sprite vide (chip, POS/CTL = 0) pour les canaux sans image
gb_SprCop    EQU GB_PUBLIC+4  ; APTR : mot de valeur de SPR0PTH dans la liste copper chargée (0 = aucune)
gb_SprData   EQU GB_PUBLIC+8  ; 8 x APTR : données (POS/CTL + image) de chaque canal, 0 = sprite vide
gb_SprUsed   EQU GB_PUBLIC+40 ; WORD : canaux réservés par GetSprite (bit n = canal n)
gb_BlitSem   EQU GB_PUBLIC+42 ; SignalSemaphore (46 o) : propriété du blitter (OwnBlitter / DisownBlitter)
GB_SS_OWNER  EQU 40           ; struct SignalSemaphore : ss_Owner
GFXBASE_SIZE EQU GB_PUBLIC+42+46
DISPF_PAL    EQU 4

; --- struct SimpleSprite (graphics/sprite.h) et registres sprite ---
ss_posctldata EQU 0           ; APTR : POS, CTL, image (2 mots par ligne), 0, 0
ss_height    EQU 4
ss_x         EQU 6
ss_y         EQU 8
ss_num       EQU 10
ss_SIZEOF    EQU 12
SPR0PTH      EQU CUSTOM+$120  ; SPRxPTH = SPR0PTH + x*4
DMAF_SPRITE  EQU $0020

; --- Tailles des listes copper générées (chip RAM) ---
; MakeVPort est générique : DIW/DDF (4) + BPLCON0/1/2/BPL1MOD/BPL2MOD (5) + depth*2 (pointeurs de plan) + Count
; (couleurs) MOVEs. Dimensionné pour le pire cas de ce projet (6 plans + 32 couleurs = 53 MOVEs = 106 mots) ;
; MrgCop copie le fragment entier -> le reliquat mis à 0 (MEMF_CLEAR) = MOVEs inertes vers BLTDDAT, inoffensifs.
GFX_FRAG_WORDS EQU 106
GFX_FRAG_SIZE  EQU GFX_FRAG_WORDS*2
GFX_SPRCOP_SIZE EQU 8*2*4            ; SPR0PTH/L..SPR7PTH/L : 16 MOVEs ajoutés par MrgCop
GFX_MASTER_SIZE EQU GFX_FRAG_SIZE+GFX_SPRCOP_SIZE+4   ; + WAIT final ajouté par MrgCop

; --- Layout du bloc de structures AllocMem'd par gfx_display_init ---
GFX_O_VIEW     EQU 0
GFX_O_VP       EQU 20         ; après View (v_SIZEOF 18, aligné pair)
GFX_O_RASINFO  EQU 60         ; après ViewPort (vp_SIZEOF 40)
GFX_O_BITMAP   EQU 72         ; après RasInfo (ri_SIZEOF 12)
GFX_O_COLORMAP EQU 112        ; après BitMap (bm_SIZEOF 40)
GFX_O_COLORTAB EQU 120        ; après ColorMap (8)
GFX_STRUCT_SIZE EQU GFX_O_COLORTAB+GFX_BOOT_NCOLORS*2  ; 184 : ColorTable de 32 couleurs (écran de boot)

; M4c1 : graphics.library comme module résident. M4C1_WRONG_TYPE=1 (RED) : RT_TYPE du ROMTag = NT_DEVICE au
; lieu de NT_LIBRARY -> le chemin AUTOINIT route GfxBase vers DeviceList (pas LibList) -> FindName(LibList)
; échoue -> « M4C1 GFX LIB OK » absent. Isole la branche de routage NT_LIBRARY->LibList (neuve : seul
; NT_DEVICE était exercé jusqu'ici). Défaut 0 (inerte).
M4C1_WRONG_TYPE EQU 0
