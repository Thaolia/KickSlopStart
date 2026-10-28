# intuition-screens-v34.md — écrans d'intuition 34.3 : ouverture, fermeture, ordre, déplacement, Workbench

> Piste **ANALYSE** (« dirty »). Sources : ROM `assets/kick34005.A500` (intuition 34.3, lecture seule,
> désassemblage temporaire hors dépôt) et sonde boîte noire `tests/iscr_probe.s` / `tests/iscr_probe.sh`
> exécutée sous FS-UAE avec la vraie ROM (A500, 512 Ko chip + 512 Ko slow, PAL puis NTSC, lancée depuis le
> bootblock, donc **avant** `devs:system-configuration`, sans Workbench chargé). Spécification
> **comportementale** : structures lues et écrites, valeurs, ordres d'opérations, conditions. Aucune suite
> d'instructions n'est reproduite ; aucune adresse de routine de la ROM n'est citée. Les adresses `$C0xxxx`
> des vecteurs de test sont des adresses **RAM** de l'exécution sondée (exemples).
>
> **Légende** : **[O]** observé dans le binaire (radare2, base `$FC0000`) · **[S]** sondé en boîte noire
> sur la vraie ROM · **[D]** déduit (raisonnement sur [O]/[S], non exécuté).
>
> Complète sans les répéter : `intuition-frame-v34.md` §6 (dessin de la barre d'écran),
> `intuition-prefs-v34.md` §1 et §3.3 (police par défaut, couleurs, NormalDisplayRows/Columns),
> `graphics-display-v34.md` (MakeVPort/MrgCop/LoadView, ViewPorts empilées),
> `workbench-task-v34.md` §4 (côté Workbench de CloseWorkBench).
>
> Notation : IB = IntuitionBase. Les offsets d'IB au-delà des champs publics (`$3C`…`$4F`) sont
> l'**état interne V34**, donnés pour faciliter l'implémentation et les sondes ; seuls les champs publics
> sont une ABI que des programmes lisent. « Lignes entrelacées » (le) = unité verticale dans laquelle
> intuition tient MouseY : une ligne non entrelacée vaut 2 le.

---

## 0. Réponse courte

- `OpenScreen` lit **32 octets** de NewScreen (l'extension NS_EXTENDED est ignorée, le bit `$1000` est
  recopié tel quel dans `Screen.Flags`). Seul **Height = −1** est spécial (hauteur d'affichage, doublée si
  LACE) ; **Width = −1 ne l'est pas**. `LeftEdge` est mémorisé mais **n'a aucun effet d'affichage**
  (DxOffset de la ViewPort forcé à 0). [O][S]
- Le nouvel écran est mis **en tête** de la liste (`IB.FirstScreen`), ou **en queue** avec SCREENBEHIND ;
  sa ViewPort est toujours mise **en tête** de la chaîne de la View d'intuition. `ActiveScreen` **n'est pas**
  modifié par OpenScreen. [O][S]
- Palette d'un écran neuf (custom ou Workbench) : table par défaut de graphics (GetColorMap(32)), dont les
  couleurs **0–3 et 17–19 sont remplacées par celles des Preferences**. [O][S]
- Disposition verticale (RethinkDisplay) : l'écran de tête est toujours affiché sur toute sa hauteur ;
  chaque écran suivant est rogné pour finir **3 lignes (non entrelacées) au-dessus** du haut de l'écran
  qui le précède, et **caché (VP_HIDE)** s'il commence à ce niveau ou plus bas. [O][S]
- `MoveScreen` n'utilise **que dy** ; TopEdge borné à ≥ 0, **sans borne basse**. [O][S]
- `CloseScreen` **ne refuse rien** (pas de test des fenêtres ouvertes) ; si c'était le **dernier écran**, il
  **rouvre le Workbench**. `CloseWorkBench` refuse (FALSE) s'il existe une fenêtre non-WBENCHWINDOW sur
  l'écran WB, sinon prévient le Workbench, ferme l'écran **sans** réouverture et rend TRUE. [O][S]
- `OpenWorkBench` rend le **pointeur d'écran** (pas un booléen 0/1), et ne rouvre rien si l'écran existe. [O][S]
- Amiga **gauche** + N → `WBenchToFront`, Amiga gauche + M → `WBenchToBack`. [O]

---

## 1. Layouts d'ABI

### 1.1 `struct NewScreen` — 32 octets lus [O]

| Off | Champ | Taille | Traitement |
|---:|---|---|---|
| $00 | LeftEdge | W | → Screen.LeftEdge (sans effet d'affichage, §2.4) |
| $02 | TopEdge | W | → Screen.TopEdge ; ViewPort.DyOffset = max(TopEdge, 0) |
| $04 | Width | W | tel quel (−1 **non** traité) |
| $06 | Height | W | −1 ⇒ hauteur par défaut (§2.2) |
| $08 | Depth | W | nombre de plans alloués (aucun contrôle) |
| $0A | DetailPen | B | → Screen +$14A |
| $0B | BlockPen | B | → Screen +$14B |
| $0C | ViewModes | W | → ViewPort.Modes, **OR SPRITES ($4000)** forcé |
| $0E | Type | W | → Screen.Flags = Type **OR SHOWTITLE ($10)** |
| $10 | Font | L | TextAttr ; NULL ⇒ TextAttr par défaut d'IB |
| $14 | DefaultTitle | L | → Screen.Title **et** Screen.DefaultTitle |
| $18 | Gadgets | L | chaînés **après** les gadgets système |
| $1C | CustomBitMap | L | lu seulement si Type & CUSTOMBITMAP |

Bits de Type utilisés : `$000F` type d'écran (1 = WBENCHSCREEN, $F = CUSTOMSCREEN), `$0040`
CUSTOMBITMAP, `$0080` SCREENBEHIND, `$0100` SCREENQUIET. Aucun autre bit n'est testé ; `$1000`
(NS_EXTENDED) est simplement recopié dans Flags [O][S : Flags = $101F pour Type $100F].

### 1.2 `struct Screen` V34 — `$15A` = 346 octets [O][S]

| Off | Champ | Valeur initiale posée par OpenScreen |
|---:|---|---|
| $00 | NextScreen | chaînage IB (§2.6) |
| $04 | FirstWindow | 0 |
| $08 | LeftEdge | NewScreen.LeftEdge |
| $0A | TopEdge | NewScreen.TopEdge |
| $0C | Width | NewScreen.Width |
| $0E | Height | NewScreen.Height résolu (§2.2) |
| $10 | MouseY | (IB.MouseY, ÷2 si l'écran n'est pas LACE) − TopEdge |
| $12 | MouseX | (IB.MouseX, ÷2 si l'écran n'est pas HIRES) − LeftEdge |
| $14 | Flags | Type OR $10 |
| $16 | Title | DefaultTitle |
| $1A | DefaultTitle | DefaultTitle |
| $1E | BarHeight (B) | 2 × BarVBorder + ta_YSize de la TextAttr retenue |
| $1F | BarVBorder (B) | 1 |
| $20 | BarHBorder (B) | HIRES 5 · non HIRES 2 |
| $21 | MenuVBorder (B) | HIRES 2 · non HIRES 4 |
| $22 | MenuHBorder (B) | 4 |
| $23 | WBorTop (B) | 2 |
| $24 | WBorLeft (B) | 4 |
| $25 | WBorRight (B) | 4 |
| $26 | WBorBottom (B) | 2 |
| $27 | (remplissage) | 0 |
| $28 | Font | pointeur vers la **TextAttr retenue** (celle de l'appelant ou celle d'IB) |
| $2C | ViewPort (40) | §2.3 |
| $54 | RastPort (100) | InitRastPort, BitMap = &Screen.BitMap, police posée (§2.5) |
| $B8 | BitMap (40) | InitBitMap(Depth, Width, Height) ou copie de CustomBitMap |
| $E0 | LayerInfo (102) | InitLayers + FattenLayerInfo |
| $146 | FirstGadget | gadgets système (§4) puis NewScreen.Gadgets |
| $14A | DetailPen (B) | NewScreen.DetailPen |
| $14B | BlockPen (B) | NewScreen.BlockPen |
| $14C | SaveColor0 (W) | 0 (servira à DisplayBeep) |
| $14E | BarLayer | couche de la barre (§3.1) |
| $152 | ExtData | 0 |
| $156 | UserData | 0 |

Le choix « HIRES / non HIRES » des bordures se fait sur `ViewModes & $8000`. Les valeurs viennent de
deux tables d'octets d'IB (§1.3), indexées 0 = HIRES, 1 = sinon. [O][S]

Bits de `Screen.Flags` gérés par intuition : `$0010` SHOWTITLE (posé à l'ouverture, ShowTitle),
`$0020` BEEPING (DisplayBeep en cours ; SaveColor0 garde la couleur 0 d'origine). [O]

### 1.3 Champs d'IntuitionBase concernés [O][S]

| IB | Contenu |
|---:|---|
| $22 | View d'intuition (ViewLord, 18 octets) : ViewPort, LOFCprList, SHFCprList, DyOffset, DxOffset, Modes |
| $34 | ActiveWindow |
| $38 | ActiveScreen |
| $3C | FirstScreen |
| $40 | Flags (vaut `$1000` après la première ouverture, cf. intuition-prefs §1) |
| $44 / $46 | MouseY / MouseX (le / pixels hires) |
| $50 / $52 | borne X min / max du pointeur |
| $54 / $56 | borne Y min / max du pointeur |
| $33E…$34D | tables de bordures par défaut, paires (HIRES, autre) : WBorLeft (4,4), WBorTop (2,2), WBorRight (4,4), WBorBottom (2,2), BarVBorder (1,1), BarHBorder (5,2), MenuVBorder (2,4), MenuHBorder (4,4) |
| $35C | TextAttr par défaut (topaz 8 ou 9, intuition-prefs §3.3) |
| $378 | haut (le) de l'écran visible le plus haut (§5.3) |
| $3A8 | port du Workbench (posé par AlohaWorkbench) |
| $3AC / $3B0 | port de réponse et message d'intuition vers le Workbench (§7.4) |
| $400 | 7 SignalSemaphores de $2E octets : verrou n à IB + $400 + n × $2E |
| $542 / $544 / $546 | 2 × NormalDisplayRows, ce nombre − 1, NormalDisplayColumns |

Verrous (numérotation de LockIBase) : 0 = état d'intuition (ISTATELOCK), 4 = vue (VIEWLOCK),
5 = IntuitionBase (IBASELOCK) ; les autres (1–3, 6) ne servent pas aux écrans. [O]

À l'init de la librairie : FirstScreen = 0, View initialisée par InitView (ViewPort nul), Modes = `$4000`
au moment de la sonde. [S : T0]

---

## 2. OpenScreen(newscreen) — LVO −198

### 2.1 Ordre des opérations [O]

Tout se fait sous le **verrou 0** (pris au début, rendu à la fin, y compris en cas d'échec). Les
allocations passent par une **liste Remember locale** (AllocRemember), oubliée sans libérer en cas de
succès, libérée en cas d'échec.

1. Lecture des champs ; si Height = −1, résolution (§2.2).
2. Allocation de la Screen : 346 octets, MEMF_PUBLIC|MEMF_CLEAR. Échec ⇒ rend 0.
3. Allocation d'un RasInfo : 12 octets, MEMF_PUBLIC|MEMF_CLEAR. Échec ⇒ 0.
4. `GetColorMap(32)`. Échec ⇒ 0.
5. Champs Width, Height, LeftEdge, TopEdge, Flags, DetailPen, BlockPen (§1.2).
6. `InitLayers(&LayerInfo)`, `FattenLayerInfo(&LayerInfo)`.
7. `InitVPort(&ViewPort)` puis : ColorMap, DxOffset = 0, DyOffset = TopEdge si ≥ 0 sinon 0,
   DWidth = Width, DHeight = Height, Modes = ViewModes | SPRITES.
8. **La ViewPort est chaînée en tête** de la View d'intuition (vp.Next = View.ViewPort ;
   View.ViewPort = vp), quel que soit SCREENBEHIND.
9. BitMap :
   - CUSTOMBITMAP : copie des 40 octets de *CustomBitMap dans Screen.BitMap (la structure est
     copiée, les plans restent ceux de l'appelant) ;
   - sinon `InitBitMap(&BitMap, Depth, Width, Height)` puis, pour chaque plan,
     AllocRemember de `((Width + 15) >> 3 & $FFFE) × Height` octets en **MEMF_CHIP|MEMF_PUBLIC
     (sans CLEAR)**. Échec d'un plan ⇒ échec global.
10. `InitRastPort(&RastPort)` ; RastPort.BitMap = &Screen.BitMap.
11. Gadgets système (§4) ; échec d'allocation ⇒ échec global. Puis NewScreen.Gadgets est accroché
    **à la fin** de la liste.
12. Police (§2.5) ; Screen.Font = TextAttr retenue.
13. Pour chaque gadget **proportionnel** de la liste : si PropInfo.Flags a PROPBORDERLESS ($08),
    LeftBorder = TopBorder = 0 ; sinon LeftBorder = WBorLeft, TopBorder = WBorTop de l'écran.
14. BarVBorder…WBorBottom puis BarHeight (§1.2).
15. Screen.MouseX/MouseY (§1.2).
16. Sans CUSTOMBITMAP : `SetRast(&RastPort, 0)` — c'est ce qui efface les plans. Avec CUSTOMBITMAP,
    le contenu de l'appelant est conservé.
17. Couche de barre : `CreateUpfrontLayer(&LayerInfo, &BitMap, 0, 0, Width − 1, BarHeight,
    LAYERSIMPLE|LAYERBACKDROP)` → Screen.BarLayer. Échec ⇒ échec global. Police posée sur le
    RastPort de cette couche (second OpenFont de la même TextAttr).
18. Title = DefaultTitle = NewScreen.DefaultTitle.
19. RasInfo.BitMap = &Screen.BitMap ; si ViewModes & DUALPF ($400), un **second RasInfo** de 12 octets
    (vide : BitMap nul) est alloué et chaîné en RasInfo.Next — à l'appelant de le remplir.
20. vp.RasInfo = RasInfo.
21. Sous Forbid : SCREENBEHIND ⇒ écran ajouté **en queue** de la liste IB ; sinon **en tête**
    (Next = FirstScreen, FirstScreen = écran).
22. Dessin de la barre (intuition-frame §6) ; `RemakeDisplay()` (§5.2) ; recalcul des bornes du
    pointeur (§5.3).
23. FreeRemember(clé, FALSE) (oubli de la liste, la mémoire reste).
24. **Couleurs des Preferences** : SetRGB4 des couleurs 0–3 (IB couleurs prefs 0–3) et 17–19 (couleurs
    du pointeur) sur la ViewPort de l'écran — **pour tout écran**, pas seulement le Workbench.
25. Rend le pointeur d'écran.

Échec à partir de l'étape 9 : la ViewPort est décrochée de la View, puis FreeRemember(clé, TRUE).
**Ne sont pas libérés** : la ColorMap, l'épaississement du LayerInfo, les polices éventuellement
ouvertes. Aucun RemakeDisplay. [O] (fuite propre à la V34 ; inutile de la reproduire [D]).

### 2.2 Height = −1 [O][S]

- Sans LACE dans ViewModes : Height = IB+$542 / 2 = **NormalDisplayRows** (256 PAL, 200 NTSC).
- Avec LACE ($0004) : Height = IB+$542 = **2 × NormalDisplayRows** (512 PAL, 400 NTSC).
- Width = −1 n'est pas traité : la largeur −1 donnerait des plans de 0 octet par ligne [D]. Le
  Workbench ne passe pas par là : il fixe lui-même sa largeur (§7.1).
- Sondé PAL : S1 (lores, −1) ⇒ Height 256 ; S2 (HIRES|LACE, −1) ⇒ 512. [S]

### 2.3 ViewPort, View et mode entrelacé [O][S]

- vp.Modes = ViewModes | `$4000`. Exemples sondés : WB `$C000`, écran lores `$4000`, HIRES|LACE `$C004`.
- La View d'intuition n'a **jamais** de mode propre aux écrans sauf **LACE**, posé ou effacé globalement
  (§5.1). DxOffset/DyOffset de la View viennent des Preferences (intuition-prefs §3.3 étape 5) ;
  sondé PAL au boot : Dy `$2C`, Dx `$81`.
- Le champ `SpritePriorities` (+$22 de la ViewPort) vaut `$24` (InitVPort de graphics). [S]

### 2.4 LeftEdge [O][S]

LeftEdge est mémorisé dans la Screen et entre dans le calcul de Screen.MouseX, mais la ViewPort reçoit
toujours **DxOffset = 0** et **MoveScreen ignore dx** : un écran 1.3 ne se décale jamais horizontalement.
Sondé : LeftEdge 7 ⇒ vp.DxOffset 0, Screen.MouseX = −7 avec le pointeur en 0.

### 2.5 Police [O][S]

1. TextAttr candidate = NewScreen.Font, ou à défaut la TextAttr d'IB (+$35C).
2. `OpenFont(candidate)` (graphics seulement : **pas de diskfont**). Si succès : SetFont sur le RastPort
   de l'écran puis `SetSoftStyle(rp, ta_Style, $FF)`.
3. Si échec : même opération avec la TextAttr d'IB (supposée toujours ouvrable).
4. Screen.Font = la TextAttr retenue (pointeur vers la structure de l'**appelant** si elle a réussi :
   elle doit donc rester valide pendant la vie de l'écran).
5. BarHeight se calcule sur le **ta_YSize demandé** de la TextAttr retenue (pas sur tf_YSize).
6. La police est rouverte (second OpenFont) pour le RastPort de la BarLayer.

Sondé au bootblock (avant system-configuration, FontHeight par défaut 9) : police topaz 9, BarHeight
**11** pour le WB et les écrans sans Font ; RastPort.TxHeight 9, TxWidth 10, TxBaseline 6. Police
introuvable (`nonexist.font`) ⇒ repli sur la TextAttr d'IB. Avec le system-configuration du WB 1.3
(FontHeight 8) la barre fait **10** [D, cohérent avec intuition-frame : BT = 10 mesuré].
TextAttr fournie topaz 8 (sondé, S2) : acceptée, **Screen.Font = pointeur de l'appelant**, BarHeight
**10**, BarLayer (0,0)–(639,10), TxHeight 8, TxWidth 8. [S]

### 2.6 Ordre dans la liste et écran actif [O][S]

- Écran normal ⇒ tête de liste ; SCREENBEHIND ⇒ queue (sondé : S2 BEHIND derrière le WB).
- La ViewPort est **toujours** chaînée en tête de la View : l'ordre de la chaîne de ViewPorts n'est
  **pas** l'ordre des écrans (sondé : chaîne S3, S2, S1, WB alors que la liste d'écrans est
  S3, S1, WB, S2). Ce n'est pas un problème : graphics fusionne par position verticale.
- ActiveScreen inchangé par OpenScreen (sondé : reste le WB après ouverture de S1, S2, S3). Il est
  modifié par l'activation d'une fenêtre (ActiveScreen = écran de la fenêtre, et Screen.Title =
  Window.ScreenTitle si différent, puis redessin de la barre), par OpenWorkBench (§7.1) et par
  CloseScreen de l'écran actif (§6.1).

### 2.7 Palette par défaut [O][S]

Couleurs relevées par GetRGB4 sur un écran neuf (WB ou custom, identiques), Preferences par défaut :

```
 0-15 : 05A FFF 002 F80 00F F0F 0FF FFF 620 E50 9F1 EB0 55F 92F 0F8 CCC
16-31 : 000 D22 000 FCA 444 555 666 777 888 999 AAA BBB CCC DDD EEE FFF
```

0–3 et 17–19 = Preferences (bleu, blanc, noir, orange ; pointeur D22/000/FCA) ; le reste = table par
défaut de graphics. Un écran 1 plan n'affiche que 0–1, etc. Après SetPrefs, seules les couleurs de
l'écran **Workbench** sont remises à jour (intuition-prefs §3.3) ; les écrans custom gardent les
couleurs prefs de leur ouverture.

---

## 3. Barre de titre de l'écran

### 3.1 Couche [O][S]

- BarLayer = couche **LAYERSIMPLE | LAYERBACKDROP** (Flags `$41`), bornes (0, 0)–(Width − 1,
  **BarHeight**) : elle couvre **BarHeight + 1** lignes (sondé : MaxY = 11 pour BarHeight 11).
- Étant BACKDROP, les fenêtres non-backdrop passent devant ; la barre est devant les fenêtres
  BACKDROP tant que SHOWTITLE est posé (§3.2).
- Dessin : intuition-frame §6 (fond BlockPen, Title en DetailPen/BlockPen JAM2 à
  (BarHBorder, BarVBorder), gadgets de l'écran). Rien n'est dessiné pour un écran SCREENQUIET ni pour
  un écran absent de la liste.

### 3.2 ShowTitle(screen, flag) — LVO −282 [O][S]

- flag ≠ 0 : Flags |= SHOWTITLE ; sous LockLayerInfo, la BarLayer perd BACKDROP, passe **devant tout**
  (UpfrontLayer), puis **BehindLayer** (elle se range alors derrière les fenêtres normales mais devant
  les backdrop), puis reprend BACKDROP ; puis la barre est redessinée.
- flag = 0 : Flags &= ~SHOWTITLE ; BACKDROP posé, BehindLayer ⇒ la barre passe **derrière toutes les
  couches**, y compris les fenêtres backdrop (qui la cachent alors).
- Dans les deux cas, une demande différée « réparer les fenêtres endommagées de cet écran » est
  déposée dans la file d'intuition (traitée au prochain événement d'entrée : REFRESHWINDOW pour les
  SIMPLE_REFRESH, réparation pour les autres).
- Sondé : Flags $101F → $100F → $101F ; la couche garde Flags `$41`.

### 3.3 Titre affiché [O]

- OpenScreen : Title = DefaultTitle.
- OpenWindow : Window.ScreenTitle = Screen.DefaultTitle.
- Activation d'une fenêtre : si Screen.Title ≠ Window.ScreenTitle, Screen.Title = Window.ScreenTitle
  et redessin de la barre. **La désactivation ne restaure rien.**
- `SetWindowTitles(win, wtitle, stitle)` côté écran : si stitle ≠ −1, Window.ScreenTitle = stitle ;
  **seulement si la fenêtre est active** (Window.Flags & $2000), Screen.Title = stitle et redessin de
  la barre. stitle = 0 ⇒ barre **sans texte** (pas de repli sur DefaultTitle). Côté fenêtre
  (wtitle ≠ −1) : Window.Title = wtitle, redessin de la barre de la fenêtre, puis rendu « inactif » si
  elle n'est pas active.

---

## 4. Gadgets système de l'écran [O][S]

Créés à l'ouverture, toujours **trois**, dans cet ordre, copiés de modèles internes (44 octets chacun,
alloués dans la liste Remember ; images recopiées en CHIP) :

| # | GadgetType | Rôle | HIRES (L, T, W, H) | non HIRES (L, T, W, H) | Flags | Activation |
|--:|---|---|---|---|---|---|
| 1 | `$C050` SUPFRONT | écran devant | −28, 0, 26, 10 | −16, 0, 17, 10 | `$14` GRELRIGHT\|GADGIMAGE | `$01` RELVERIFY |
| 2 | `$C070` SDOWNBACK | écran derrière | −52, 0, 24, 10 | −33, 0, 17, 10 | `$14` | `$01` |
| 3 | `$C030` SDRAGGING | glissement | 0, 0, 0, 10 | 0, 0, 0, 10 | `$23` GRELWIDTH\|GADGHNONE | 0 |

- Le gadget de glissement couvre toute la largeur (largeur relative 0) et **10 lignes fixes**, même
  quand BarHeight vaut 11 (police 9). Les gadgets de profondeur, placés avant lui dans la liste,
  sont trouvés en premier au test de clic [D].
- SCREENQUIET : les trois gadgets existent quand même, mais GadgetRender = 0 et Flags |= GADGHNONE
  (sondé : Flags `$17`, rendu nul).
- Les gadgets de NewScreen.Gadgets suivent le troisième (sondé : gadget utilisateur en 4e position,
  non modifié).
- CloseScreen libère (FreeMem de 44 octets) **tous les gadgets de la liste qui ont SYSGADGET ($8000)**
  et laisse les autres à l'appelant.

---

## 5. Disposition de l'affichage

### 5.1 Mode entrelacé global [O][S]

Parcours des écrans dans l'ordre de la liste, avec une limite L (le) partant de 2 × NormalDisplayRows :
pour chaque écran, haut = TopEdge (×2 si l'écran n'est pas LACE) ; si haut < L, l'écran est
« visible » : s'il est LACE, la View doit être LACE ; puis L = haut − 6. View.Modes reçoit ou perd
**LACE ($4)** selon qu'**au moins un écran visible** est LACE. Sondé : un écran LACE caché derrière le WB
laisse View.Modes à `$4000`.

### 5.2 MakeScreen, RemakeDisplay, RethinkDisplay [O][S]

- **MakeScreen(s)** (−378) : verrou 4 ; recalcul du LACE global (§5.1) ; `MakeVPort(&View, &s.ViewPort)` ;
  rend le verrou. **Ni MrgCop ni LoadView** : l'appelant doit faire RethinkDisplay.
- **RemakeDisplay()** (−384) : verrou 4 ; LACE global ; `MakeVPort` de **chaque ViewPort de la chaîne de
  la View** ; rend le verrou ; puis RethinkDisplay.
- **RethinkDisplay()** (−390) : verrou 5, puis :
  1. **mise en page** (ci-dessous), qui refait MakeVPort (via MakeScreen) des seuls écrans dont la
     hauteur affichée change, ou de tous les visibles si le LACE global vient de changer ;
  2. sous verrou 4 : mémorise LOFCprList et SHFCprList de la View, les **met à 0**, `MrgCop(&View)`
     (donc listes **neuves**), `LoadView(&View)`, `WaitTOF()`, puis écrit **DMACON = $8100** (BPLEN)
     et **DMACON = $8020** (SPREN), puis `FreeCprList` des deux anciennes listes ;
  3. rend le verrou 5.

Mise en page (étape 1), avec h(s) = TopEdge (×2 si l'écran n'est pas LACE) en le :
- L = h(premier) + Height du premier (×2 si non LACE) — donc **l'écran de tête est toujours entier** ;
- pour chaque écran, dans l'ordre de la liste : si h < L : VP_HIDE ($2000) effacé ;
  lignes = (L − h), ÷2 si non LACE, **plafonné à Height** ; si DHeight ≠ lignes (ou LACE global changé),
  DHeight = lignes et MakeScreen ; puis **L = h − 6**. Sinon : VP_HIDE posé (DHeight inchangé).
- À la fin : IB+$378 = L + 6 (haut du dernier écran visible, c'est-à-dire du plus haut à l'écran) ; si
  aucun glissement/menu n'est en cours (bits `$600` d'IB.Flags à 0), borne Y min du pointeur = IB+$378.

Conséquence : entre un écran et celui qui est devant lui il reste **3 lignes non entrelacées vides**
(6 le), ce qui satisfait l'exigence d'au moins une ligne vide de graphics (graphics-display §5.4).

Vecteurs sondés (PAL, WB 640×256 derrière S1 lores 320×256) :

| S1.TopEdge | WB DHeight | WB Modes | S1 DHeight |
|---:|---:|---|---:|
| 40 | 37 | `$C000` | 256 |
| 100 | 97 | `$C000` | 256 |
| 0 | 97 (inchangé) | `$E000` (caché) | 256 |
| 300 | 256 (plafonné à Height) | `$C000` | 256 |
| S1 derrière le WB, TopEdge 100 | 256 | — | 256, `$6000` (caché) |
| S3 (Top 150, H 50) devant S1 (Top 100) | — | — | S1 : 47 |

### 5.3 Bornes du pointeur [O][S]

Recalculées après OpenScreen, CloseScreen, ScreenToFront/Back, et à la fin d'un glissement :
- X : [0, NormalDisplayColumns − 1] (sondé 0…$27F) ;
- Y min : IB+$378 (haut de l'écran visible le plus haut ; le pointeur **ne peut pas monter** dans la
  zone vide au-dessus des écrans) ;
- Y max : min(2 × NormalDisplayRows − 1, bas de l'**écran de tête** − 1) en le (sondé : $1FF avec le WB
  en tête ; **$18F** = (150 + 50) × 2 − 1 avec S3 en tête).

---

## 6. Fermeture

### 6.1 CloseScreen(screen) — LVO −66 [O][S]

Sous le verrou 0. **Aucun refus** : ni test de FirstWindow, ni vérification que l'écran est dans la
liste ; pas de valeur de retour utile (void en V34). Ordre :

1. Si screen = ActiveScreen : demande différée « activer (fenêtre nulle, écran nul) » ⇒ la fenêtre
   active est désactivée et ActiveScreen = 0 au prochain événement d'entrée.
2. ViewPort décrochée de la View ; écran décroché de la liste IB.
3. CloseFont de la police du RastPort de l'écran et de celle de la BarLayer.
4. DeleteLayer de la BarLayer.
5. Libération des gadgets SYSGADGET (§4).
6. Sans CUSTOMBITMAP : WaitBlit, puis FreeMem de chaque plan (taille recalculée depuis
   BytesPerRow × 8, Rows, Depth de Screen.BitMap).
7. FreeColorMap, FreeVPortCopLists(&vp), FreeMem du second RasInfo s'il existe puis du premier (12).
8. ThinLayerInfo(&LayerInfo) ; FreeMem(screen, 346).
9. Sous Forbid : si la liste est vide, ActiveScreen = 0 et **OpenWorkBench()** (réouverture
   automatique) ; Permit.
10. Si la liste n'est pas vide : RemakeDisplay. Puis recalcul des bornes du pointeur.

Fenêtres encore ouvertes : leurs couches et structures ne sont **pas** libérées et pointent sur une
Screen libérée — comportement indéfini [D]. Sondé : ouvrir puis fermer un écran custom quand il est
seul ⇒ un nouvel écran Workbench apparaît (T10).

### 6.2 CloseWorkBench() — LVO −78 [O][S]

1. Cherche le premier écran de la liste dont Flags & $F = WBENCHSCREEN ; absent ⇒ **FALSE**.
2. Parcourt ses fenêtres : une seule fenêtre **sans WBENCHWINDOW** (Window.Flags & $02000000) ⇒
   **FALSE** (refus, rien n'est fait).
3. Message **WBENCHCLOSE** au Workbench et attente synchrone de la réponse (§7.4) — seulement si un
   Workbench s'est déclaré (AlohaWorkbench).
4. Fermeture de l'écran comme CloseScreen **sans** l'étape de réouverture (et sans prendre le
   verrou 0) ; **TRUE**.

La présence de fenêtres n'est **pas** revérifiée après la réponse du Workbench : si celui-ci n'a pas
fermé ses fenêtres, l'écran est fermé quand même [O]. Si l'écran WB était le seul, la View garde ses
anciennes listes copper (pas de RemakeDisplay quand la liste est vide) [O][S : View.ViewPort = 0,
LOFCprList non nul]. Sondé : CloseWorkBench sans fenêtre ⇒ 1 puis 0 au second appel.

---

## 7. Workbench

### 7.1 Écran Workbench par défaut [O][S]

NewScreen interne : LeftEdge 0, TopEdge 0, Width **NormalDisplayColumns** (IB+$546), Height −1,
Depth **2**, DetailPen **0**, BlockPen **1**, ViewModes **HIRES ($8000)**, OR **LACE** si
Preferences.LaceWB (bit 0 de l'octet +$B9), Type WBENCHSCREEN (1), Font = TextAttr d'IB,
DefaultTitle **« Workbench Screen »**, ni gadgets ni bitmap.

| Vidéo | Taille sondée / déduite |
|---|---|
| PAL | 640 × 256 (LACE : 640 × 512) [S] |
| NTSC | 640 × 200 (LACE : 640 × 400) [S] |

Après OpenScreen : demande différée « activer (fenêtre nulle, cet écran) » ⇒ **ActiveScreen = WB** au
prochain événement d'entrée (sondé) ; rechargement des couleurs prefs sur le WB ; bornage du pointeur.
Flags sondé `$0011`, BarHeight 11 (topaz 9), Title = DefaultTitle = « Workbench Screen ».

### 7.2 OpenWorkBench() — LVO −210 [O][S]

- Si un écran WBENCHSCREEN existe : le rend tel quel (pas de second écran, pas de message).
- Sinon : ouvre l'écran par défaut (§7.1). Échec ⇒ 0. Succès ⇒ message **WBENCHOPEN** au Workbench
  s'il s'est déclaré (§7.4), puis rend le **pointeur d'écran**.
- Sondé : deux appels successifs rendent le même pointeur `$C04AD0`.
- OpenWindow sur WBENCHSCREEN passe par la même recherche-ou-ouverture ; pour un autre type d'écran
  système inexistant, intuition lève l'alerte morte **$84000009** (AN_SysScrnType). [O]

### 7.3 WBenchToFront / WBenchToBack (−342 / −336) et Amiga-N / Amiga-M [O][S]

- Cherchent l'écran WB ; absent ⇒ **FALSE** ; sinon ScreenToFront / ScreenToBack de cet écran et
  **TRUE** (sondé : 1 et 1). WBenchToFront ne prend pas le verrou 0 (ScreenToFront si).
- Clavier (traitement d'entrée d'intuition) : événement RAWKEY avec qualificateur
  **IEQUALIFIER_LCOMMAND ($40)** et code **$36 (N)** ⇒ WBenchToFront, **$37 (M)** ⇒ WBenchToBack ;
  l'événement est consommé. Avec Amiga **droit** seul, N/M suivent le chemin des raccourcis de menu.

### 7.4 Messages au Workbench [O]

Si IB+$3A8 (port déclaré par AlohaWorkbench) est non nul : à la première fois, création d'un port de
réponse nommé « WBenchPort » (IB+$3AC) ; à chaque envoi, AllocSignal(−1) pour ce port, SigTask =
tâche courante, message intégré à IB (IB+$3B0, forme IntuiMessage) avec **Class = $00020000
(WBENCHMESSAGE)** et **Code = 1 (WBENCHOPEN) ou 2 (WBENCHCLOSE)** ; PutMsg au Workbench, **Wait**
du signal, GetMsg, FreeSignal. L'appelant est bloqué jusqu'à la réponse.

### 7.5 GetScreenData(buffer, size, type, screen) — LVO −426 [O][S]

- type = CUSTOMSCREEN ($F) : écran = argument ; type = WBENCHSCREEN (1) : écran = **OpenWorkBench()**
  (le WB est **ouvert** s'il ne l'était pas) ; autre type : rien.
- Écran nul ⇒ **FALSE**. Sinon copie de **min(size, 346)** octets de la Screen dans buffer ⇒ **TRUE**.
- Sondé : size 400 ⇒ rien n'est écrit au-delà de 346 ; type 2 ⇒ 0 ; WB fermé ⇒ rouvert, 1.

---

## 8. Profondeur et déplacement

### 8.1 ScreenToFront(s) / ScreenToBack(s) — LVO −252 / −246 [O][S]

- ScreenToFront : verrou 0, verrou 5 ; décroche s ; **s en tête** ; rend le verrou 5 ; RethinkDisplay ;
  bornes du pointeur ; rend le verrou 0.
- ScreenToBack : verrou 5 ; décroche ; **s en queue** ; rend le verrou 5 ; RethinkDisplay ; bornes.
- Aucun effet sur ActiveScreen ni sur la chaîne des ViewPorts (seuls DHeight et VP_HIDE changent).
- Gadgets de l'écran : un clic validé sur `$C050` ⇒ ScreenToFront(écran), sur `$C070` ⇒ ScreenToBack.

### 8.2 MoveScreen(s, dx, dy) — LVO −162 [O][S]

- **dx ignoré**.
- Si TopEdge + dy ≥ 0 : TopEdge += dy. Sinon, si TopEdge > 0 : TopEdge = 0. Sinon (TopEdge ≤ 0) : rien.
- **Aucune borne basse** (sondé : TopEdge 300 accepté sur un affichage de 256 lignes).
- vp.DyOffset = TopEdge (0 si négatif) ; puis **RethinkDisplay** (listes copper refaites à chaque appel).
- Pas de verrou propre en dehors de ceux de RethinkDisplay.

### 8.3 Glisser par la barre [O]

Un clic sur le gadget SDRAGGING (toute la barre hors gadgets de profondeur) démarre l'état
« glissement d'écran » :
- bornes du pointeur : X figé (min = max = MouseX courant) ; Y min = MouseY − haut de l'écran (le), de
  sorte que TopEdge ne peut devenir négatif ; Y max = 2 × NormalDisplayRows − 1 : le point saisi peut
  descendre jusqu'au bas de l'affichage (l'écran peut quasiment disparaître par le bas) ;
- à chaque événement où MouseY change : delta = MouseY − précédent (le) ; pour un écran non LACE,
  delta est converti en lignes (+1 si MouseY est pair, puis division par 2 arrondie vers −∞) ;
  **MoveScreen(écran, 0, delta)** ⇒ l'affichage est refait en direct à chaque mouvement ;
- SELECTUP (RAWMOUSE code $E8) : fin de l'état ; bornes normales recalculées (§5.3).

Test de clic entre écrans : les écrans sont parcourus dans l'ordre de la liste, les VP_HIDE ignorés ;
WhichLayer à (Screen.MouseX, Screen.MouseY) ; une couche trouvée ⇒ fenêtre (ou barre d'écran,
dont les gadgets sont alors testés) ; sinon, si le pointeur est sous le haut de cet écran, la recherche
s'arrête sur « rien ». [O]

### 8.4 Double-clic sur la barre [O]

Aucun traitement : DoubleClick n'est utilisé en interne que pour le double clic du bouton de menu
(SetDMRequest). Un double clic sur la barre d'écran donne deux débuts de glissement ordinaires.

---

## 9. Autres fonctions

- **ViewAddress()** (−294) : rend **&IB->ViewLord** (IB + $22) [O][S : `$C03D46` = IB + $22].
- **ViewPortAddress(win)** (−300) : rend **&win->WScreen->ViewPort** (Screen + $2C) [O].
- **LockIBase(n)** (−414) : n = 0 ⇒ prend le verrou 0 **puis** le 5 ; sinon le verrou n. Rend n.
  **UnlockIBase(n)** (−420) : n = 0 ⇒ rend le 5 puis le 0 ; sinon le n. Les verrous sont des
  SignalSemaphores (réentrants pour la même tâche) [O].
- **DisplayBeep(screen)** (rappel) : met BEEPING, sauve la couleur 0 dans SaveColor0 et l'inverse ;
  la restauration se fait au tic d'intuition suivant pour tous les écrans BEEPING [O].

---

## 10. Vecteurs de test (sonde `tests/iscr_probe.sh`, vraie ROM, PAL) [S]

Lancée depuis le bootblock (aucun écran au départ) :

| Étape | Observation |
|---|---|
| T0 | FirstScreen 0, ActiveScreen 0, IB.Flags `$1000`, View : ViewPort 0, Dy `$2C`, Dx `$81`, Modes `$4000` ; IB+$542/$544/$546 = 512/511/640 |
| OpenWorkBench ×2 | `$C04AD0` deux fois ; après ~0,6 s ActiveScreen = WB |
| WB | 640 × 256, Flags `$0011`, octets $1E–$26 = `0B 01 05 02 04 02 04 04 02`, Font = IB+$35C, BitMap 80 o/ligne, 2 plans CHIP, vp.Modes `$C000`, BarLayer (0,0)–(639,11) Flags `$41`, DetailPen 0, BlockPen 1 |
| S1 = {7, 40, 320, −1, 3, 2, 3, 0, `$100F`, NULL} | Height 256, Flags `$101F`, octets $1E–$26 = `0B 01 02 04 04 02 04 04 02`, vp Dx 0 Dy 40, gadgets lores (−16/17, −33/17, 0/0), MouseX −7 |
| MoveScreen(S1, 50, 60) | TopEdge 100, LeftEdge 7 (dx ignoré) |
| MoveScreen(S1, 0, −500) | TopEdge 0, WB caché (`$E000`) |
| MoveScreen(S1, 0, +300) | TopEdge 300, WB DHeight 256 |
| ScreenToBack(S1) / ScreenToFront(S1) | listes WB,S1 puis S1,WB ; S1 caché derrière (`$6000`) |
| WBenchToFront / WBenchToBack | 1 / 1 |
| S2 = {0, 20, 640, −1, 1, 0, 1, `$8004`, `$018F`} | Height 512, en queue, caché, vp.Modes `$E004`, View.Modes reste `$4000`, gadgets Flags `$17` sans rendu |
| S3 CUSTOMBITMAP 320×50×2, Top 150, + 1 gadget | Flags `$005F`, BitMap copiée, gadget utilisateur 4e ; bornes Y max `$18F` |
| GetScreenData(400, CUSTOM) / (20, WB) / (20, type 2) | 1 (346 o copiés) / 1 / 0 |
| CloseScreen S3, S2, S1 | WB seul, DHeight 256 |
| CloseWorkBench ×2 | 1 puis 0 ; FirstScreen 0, ActiveScreen 0 |
| GetScreenData(WB) écran fermé | 1, WB rouvert et actif |
| OpenScreen + CloseScreen d'un écran seul | WB rouvert automatiquement |

NTSC (même sonde, `ntsc`) : IB+$542/$544/$546 = 400/399/640 ; WB 640 × 200 ; S1 Height −1 ⇒ 200 ;
S2 HIRES|LACE ⇒ 400 ; borne Y max `$18F` ; View Dy `$2C` Dx `$81`. TextAttr topaz 8 fournie pour S2 ⇒
Screen.Font = cette TextAttr, BarHeight 10 ; `nonexist.font` pour S3 ⇒ Screen.Font = IB+$35C,
BarHeight 11. Retours identiques à PAL (OpenWorkBench ×2, WBenchToFront/Back, GetScreenData,
CloseWorkBench).

Capture finale (S1 lores 3 plans en Top 100 devant le WB) : barre de S1 en BlockPen 3 (orange) avec
ses deux gadgets de profondeur, WB visible au-dessus.

---

## 11. Points non tranchés

1. **Vrai A500 NTSC/PAL** : seules les valeurs FS-UAE ont été sondées ; la View garde Dy `$2C`, Dx
   `$81` en NTSC comme en PAL au moment du bootblock (valeurs de graphics + prefs par défaut).
2. **Écran plus large que l'affichage** ou plus étroit : intuition ne fait rien de particulier (DWidth =
   Width) ; le rognage relève de graphics (graphics-display §4.4). Non sondé ici.
3. **DUALPF** : le second RasInfo vide est remis à MakeVPort par le RemakeDisplay d'OpenScreen avant que
   l'appelant ait pu le remplir ; effet exact (lecture d'un BitMap nul) non sondé.
4. **Arrondi du glissement** pour les écrans non LACE (§8.3) : décrit d'après le code, non mesuré
   avec une vraie souris.
5. **Width = −1** : comportement déduit (plans de 0 octet, couche de largeur −2), non sondé ; à ne pas
   imiter, aucun programme 1.3 sérieux ne devrait le passer.
6. Les bits `$600` d'IB.Flags (glissement d'écran / menus) qui gèlent la borne Y min : leur sens exact
   relève de la spec « moteur d'entrées » (n° 5 de coverage-v34).
7. Fenêtres laissées ouvertes à CloseScreen : comportement indéfini, non sondé.

---

## Relecture clean-room

- [x] Aucune suite d'instructions recopiée ni paraphrasée : uniquement des effets, des ordres
  d'opérations au niveau des appels de librairie publics, des conditions et des valeurs.
- [x] Aucune adresse de routine de la ROM ; seuls des offsets de structures (ABI et état interne d'IB)
  et des adresses RAM d'exemple de la sonde.
- [x] Aucun bitmap transcrit (les images des gadgets de profondeur sont décrites dans intuition-frame).
