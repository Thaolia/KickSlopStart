# layers.library 34.1 — spec comportementale complète

> Piste **ANALYSE** (« dirty »). Sources : ROM `assets/kick34005.A500` (lecture seule ; radare2 et
> décompilation Ghidra headless, base `$FC0000`, notes hors dépôt) et sonde boîte noire
> `tests/layers_probe.s` (harnais `tests/layers_probe.sh`) exécutée **deux fois** sur la **vraie ROM**
> sous FS-UAE (A500 PAL, 512 Ko chip + 512 Ko slow), résultats identiques aux pointeurs près.
> Ce document décrit des **comportements**, des **valeurs**, des **ordres d'opérations** et des
> **layouts d'ABI** ; il ne contient aucune suite d'instructions de la ROM ni adresse de routine.
>
> Il complète sans les répéter : `installclipregion-v34.md` (InstallClipRegion, construction de la
> liste réduite de BeginUpdate, neutralisation des régions par LockLayers), `wb-icon-clipping-v34.md`
> (usage de BeginUpdate par le Workbench), `intuition-gzz-v34.md` (couches des fenêtres GZZ),
> `graphics-blitter-v34.md` §5 et §12 (dessin à travers les ClipRects, règle `MinX & ~15`),
> `setpatch-disk-resource.md` §4 (correctif DeleteLayer de SetPatch).
>
> **Niveaux de preuve** : **[O]** observé par la sonde sur la vraie ROM · **[D]** déduit de la lecture
> du code de la ROM (comportement, pas de code) · **[S]** supposition raisonnable, non vérifiée.

---

## 0. Résumé pour l'implémenteur

1. **Deux sortes de ClipRects.** Les ClipRects **visibles** (`lobs = NULL`) sont **jetés et recalculés
   de zéro** après chaque opération de pile réussie, en soustrayant du rectangle de la couche les
   rectangles des couches de devant. Les ClipRects **cachés** (`lobs ≠ NULL`) sont des objets
   **persistants** qui portent, pour les couches non SIMPLE, le tampon de sauvegarde ; lors d'un
   changement d'ordre, ces objets **passent d'une couche à l'autre** (le contenu est échangé ou
   recopié), ils ne sont pas recréés. [D]
2. **Pavage commun des parties cachées** : pour un rectangle caché `R`, toutes les couches situées
   derrière celle qui le cache et qui recouvrent `R` ont un ClipRect caché de **bornes identiques** à
   `R`, et `lobs` désigne **la couche la plus en avant** qui le recouvre. layers coupe les ClipRects
   cachés existants pour maintenir cette propriété, et **fusionne** les morceaux adjacents après un
   DeleteLayer. [D][O]
3. **SIMPLE** : rien n'est sauvegardé ; une zone qui redevient visible est **effacée à la couleur 0**
   (plans du `Mask` de son RastPort) et ajoutée à la `DamageList` (coordonnées couche), avec
   `LAYERREFRESH ($0080)`. **SMART** et **SUPER** : la zone cachée est sauvegardée dans `cr_BitMap`
   (CHIP, alignée sur 16 pixels) et restaurée sans dommage. [O]
4. **layers n'efface jamais `LAYERREFRESH`** (sauf sur sa couche temporaire interne) ; EndUpdate(TRUE)
   vide la région mais laisse le bit. C'est à l'appelant (intuition, Workbench) de l'effacer. [D][O]
5. **MoveLayer et SizeLayer** passent par une **couche temporaire** créée derrière, placée devant
   l'originale, remplie par copie, puis **échangée** avec l'originale et supprimée. Une couche SIMPLE
   déplacée ou retaillée est **entièrement endommagée** ; une SMART qui grandit reçoit les bandes
   nouvelles en dommage. [O]
6. **Transactions** : CreateUpfront/BehindLayer, UpfrontLayer, BehindLayer, MoveLayerInFrontOf,
   MoveLayer, SizeLayer échouent **sans rien changer** en cas de manque de mémoire (retour 0/NULL).
   Seule la reconstruction finale des ClipRects visibles, si elle manque de ClipRects, déclenche
   l'alerte **fatale `$83010000`** (AN_LayersNoMem). [O pour les échecs propres, D pour l'alerte]
7. **Verrous** : toute opération de pile = `LockLayerInfo` → (engraissement temporaire si la
   Layer_Info n'a pas été « fattened ») → `LockLayers` … `UnlockLayers` → (amaigrissement) →
   `UnlockLayerInfo`. `LockLayer`/`UnlockLayer` = `LockLayerRom`/`UnlockLayerRom` de graphics. [D][O]

---

## 1. Module et ABI

- ROMTag : nom `layers.library`, version **34**, type `NT_LIBRARY`, priorité **31**, drapeaux
  `RTF_COLDSTART` ; chaîne d'identité `layers 34.1 (18 Aug 1987)` suivie de LF CR. Initialisation non
  AUTOINIT (MakeLibrary explicite). [D]
- Base : `lib_Version` 34, `lib_Revision` 1, `lib_NegSize` **174** (29 vecteurs), `lib_PosSize` **42**.
  Champs privés : **`+$22` GfxBase**, **`+$26` ExecBase** (obtenue par `OpenLibrary("exec.library",0)`).
  `lib_Flags |= LIBF_SUMUSED|LIBF_CHANGED`, `lib_OpenCnt` posé à **1** à l'init (la bibliothèque n'est
  jamais expurgée). Close et Expunge rendent 0. [D ; O pour version/revision/tailles]
- Table de vecteurs : 4 standard + **25 fonctions, LVO −30 à −174**, ordre du `.fd` 1.3 (InitLayers …
  MoveLayerInFrontOf, InstallClipRegion). Aucun vecteur au-delà. [D][O]
- Chaque vecteur est un adaptateur qui empile les registres d'arguments et appelle le corps (code C) :
  **d0/d1/a0/a1 détruits, d2–d7/a2–a6 préservés**. [D]

| LVO | Fonction | Registres | Valeur rendue (D0) |
|--:|---|---|---|
| −30 | InitLayers(li) | A0 | aucune (indéfinie) [O] |
| −36 | CreateUpfrontLayer(li,bm,x0,y0,x1,y1,flags,bm2) | A0/A1,D0–D4,A2 | couche ou NULL [O] |
| −42 | CreateBehindLayer(idem) | idem | couche ou NULL [O] |
| −48 | UpfrontLayer(dummy,layer) | A0/A1 | TRUE (1) / FALSE (0) [O] |
| −54 | BehindLayer(dummy,layer) | A0/A1 | 1 / 0 [O] |
| −60 | MoveLayer(dummy,layer,dx,dy) | A0/A1,D0/D1 | 1 / 0 [O] |
| −66 | SizeLayer(dummy,layer,dx,dy) | A0/A1,D0/D1 | 1 / 0 [O] |
| −72 | ScrollLayer(dummy,layer,dx,dy) | A0/A1,D0/D1 | **indéfinie** (0 ou 4 observés) [O] |
| −78 | BeginUpdate(layer) | A0 | 1 = liste bâtie, 0 = échec mémoire [O pour 1, D pour 0] |
| −84 | EndUpdate(layer,flag) | A0,D0 | indéfinie [D] |
| −90 | DeleteLayer(dummy,layer) | A0/A1 | 1 / 0 [O] |
| −96 | LockLayer(dummy,layer) | A0/A1 | indéfinie |
| −102 | UnlockLayer(layer) | A0 | indéfinie |
| −108 | LockLayers(li) | A0 | indéfinie |
| −114 | UnlockLayers(li) | A0 | indéfinie |
| −120 | LockLayerInfo(li) | A0 | indéfinie |
| −126 | SwapBitsRastPortClipRect(rp,cr) | A0/A1 | indéfinie |
| −132 | WhichLayer(li,x,y) | A0,D0/D1 | couche ou NULL [O] |
| −138 | UnlockLayerInfo(li) | A0 | indéfinie |
| −144 | NewLayerInfo() | — | Layer_Info ou NULL [O] |
| −150 | DisposeLayerInfo(li) | A0 | indéfinie [O] |
| −156 | FattenLayerInfo(li) | A0 | 1 / 0 [O] |
| −162 | ThinLayerInfo(li) | A0 | indéfinie [O] |
| −168 | MoveLayerInFrontOf(layer,other) | A0/A1 | 1 / 0 [O] |
| −174 | InstallClipRegion(layer,region) | A0/A1 | ancienne région (cf. installclipregion-v34) |

`dummy` (la Layer_Info passée en A0 aux fonctions « couche ») **n'est jamais lue** : la Layer_Info est
toujours prise dans `layer->LayerInfo`. [D] Aucune fonction ne teste ses pointeurs (NULL interdit). [D]
Les **fonctions de région** (`NewRegion`, `OrRectRegion`, `AndRegionRegion`…) sont dans
**graphics.library**, pas dans layers. [D]

---

## 2. Structures

### 2.1 `struct Layer` — 160 octets (`$A0`), allouée `MEMF_CLEAR` [D]

| Off. | Champ | Usage par layers 34.1 |
|--:|---|---|
| `$00` | front | couche devant (NULL = sommet) |
| `$04` | back | couche derrière |
| `$08` | ClipRect | liste courante (visibles + cachés ; réduite pendant BeginUpdate/ClipRegion) |
| `$0C` | rp | RastPort **alloué par layers** (§2.4) ; `rp->Layer` = couche, `rp->BitMap` = BitMap commune |
| `$10` | bounds | MinX, MinY, MaxX, MaxY, **coordonnées de la BitMap**, bornes incluses |
| `$18` | reserved[4] | non utilisé |
| `$1C` | priority (UWORD) | **renuméroté** 1000, 999, 998… depuis le sommet **avant** chaque changement d'ordre effectif ; 0 tant qu'aucun réordonnancement n'a eu lieu. Il reflète donc l'ordre **précédant** le dernier déplacement (valeur périmée) [O] |
| `$1E` | Flags (UWORD) | LAYERSIMPLE 1, LAYERSMART 2, LAYERSUPER 4, LAYERUPDATING $10, LAYERBACKDROP $40, LAYERREFRESH $80, LAYER_CLIPRECTS_LOST $100 ; recopié tel quel depuis l'argument `flags` [D][O] |
| `$20` | SuperBitMap | BitMap de l'appelant (LAYERSUPER) |
| `$24` | SuperClipRect | liste des morceaux de la SuperBitMap **hors** de la fenêtre visible (§6) |
| `$28` | Window | non touché par layers (intuition) |
| `$2C/$2E` | Scroll_X/Scroll_Y | modifiés uniquement par ScrollLayer (§5.8) |
| `$30/$34/$38` | cr, cr2, crnew | **brouillons** de la fusion des ClipRects cachés (§3.5) ; contenu périmé ensuite |
| `$3C` | SuperSaveClipRects | réserve de **5** ClipRects préalloués pour une couche SUPER |
| `$40` | _cliprects | (1) liste normale sauvegardée pendant une liste réduite (installclipregion §3.2) ; (2) **instantané de retour arrière** pendant une opération de pile — il reste **non nul et périmé** après l'opération ; seul EndUpdate/le retrait d'une région le remet à NULL [O] |
| `$44` | LayerInfo | |
| `$48` | Lock | SignalSemaphore (46 octets) ; son nœud est chaîné dans `LayerInfo.gs_Head` |
| `$76` | reserved3[8] | non utilisé |
| `$7E` | ClipRegion | cf. installclipregion-v34 |
| `$82` | saveClipRects | mis à NULL au premier LockLayers ; rien d'autre |
| `$86` | reserved2[22] | non utilisé |
| `$9C` | DamageList | Region (NewRegion à la création, DisposeRegion à la suppression), **coordonnées couche** (origine `bounds.MinX/MinY`, sans Scroll) [O] |

### 2.2 `struct ClipRect` — 40 octets [D][O]

| Off. | Champ | Usage |
|--:|---|---|
| `$00` | Next | |
| `$04` | prev | **pas une liste double** : sert d'instantané de `Next` pour le retour arrière |
| `$08` | lobs | NULL = visible ; sinon la couche la plus en avant qui cache ce rectangle ; **1** = sentinelle des ClipRects de liste réduite (installclipregion) |
| `$0C` | BitMap | tampon de sauvegarde (SMART/SUPER caché) ou NULL |
| `$10` | bounds | coordonnées BitMap, incluses |
| `$18/$1C/$20` | _p1, _p2, reserved | non utilisés |
| `$24` | Flags | bit 0 = marqueur interne pendant un réordonnancement, **toujours 0** entre deux appels [O] |

Tampon `cr_BitMap` [D ; O pour les dimensions] :
- `BytesPerRow = ((MaxX & ~15) − (MinX & ~15) + 16) / 8` (toujours pair) ; `Rows = MaxY − MinY + 1` ;
  `Depth = rp->BitMap->Depth` de la couche ; initialisé par InitBitMap (largeur = BytesPerRow × 8).
- Le pixel écran `(x, y)` du ClipRect est au pixel `(x − (MinX & ~15), y − MinY)` du tampon : le
  rectangle commence à la colonne `MinX & 15` du tampon.
- La structure BitMap n'est allouée que sur **8 + 4 × Depth** octets (MEMF_CLEAR) : `Planes[Depth..7]`
  **n'existent pas**. Chaque plan : `BytesPerRow × Rows` octets **MEMF_CHIP**, non effacé (sauf §5.1).
- Vérifié : ClipRect (60,30)-(115,59) prof. 2 → BytesPerRow 10, Rows 30 ; (100,20)-(115,29) → 4 ; (116,30)-
  (159,49) → 6. [O]

### 2.3 `struct Layer_Info` — 102 octets (`$66`) [D][O]

| Off. | Champ | Usage |
|--:|---|---|
| `$00` | top_layer | sommet de la pile |
| `$04` | check_lp | brouillon (création) — périmé ensuite [O] |
| `$08` | obs | brouillon (liste de ClipRects en construction) — **pointeur périmé** ensuite [O] |
| `$0C` | FreeClipRects (MinList) | réserve transitoire ; **vide** entre deux appels [O] |
| `$18` | Lock (SignalSemaphore) | LockLayerInfo |
| `$46` | gs_Head (List) | les `Layer.Lock` de toutes les couches, **dans l'ordre de création** (AddTail), pour ObtainSemaphoreList |
| `$54` | longreserved | non utilisé |
| `$58` | Flags | bit 0 **NEWLAYERINFO_CALLED** (posé par NewLayerInfo/FattenLayerInfo, effacé par ThinLayerInfo) |
| `$5A` | fatten_count (BYTE) | **−1** = maigre ; Fatten l'incrémente et alloue au passage −1 → 0 |
| `$5B` | LockLayersCount (BYTE) | niveau d'imbrication de LockLayers |
| `$5C` | LayerInfo_extra_size | posé à **$42** au premier engraissement, jamais remis à 0 [O] |
| `$5E` | blitbuff | **128 octets MEMF_CHIP** alloués à l'engraissement ; **non lus par layers** ; pointeur laissé périmé après libération [O] |
| `$62` | LayerInfo_extra | 66 octets MEMF_PUBLIC (contexte de reprise sur échec + liste des allocations en cours) ; NULL quand maigre |

### 2.4 RastPort de couche — **78 octets** (`$4E`)

layers alloue le RastPort de chaque couche sur **78 octets MEMF_PUBLIC** et l'initialise par
`InitRastPort`, qui en V34 efface exactement 78 octets. Les champs au-delà de `$4E` (`wordreserved`,
`reserved` de l'en-tête 1.3) **n'existent pas** dans un RastPort de couche : ne jamais y écrire. [D]

---

## 3. Modèle des ClipRects

### 3.1 Visibles : recalcul complet [D][O]

Après chaque opération de pile réussie, pour **chaque** couche : ses ClipRects visibles sont rendus à la
réserve, puis un ClipRect = rectangle de la couche est découpé par chaque couche **de devant**, de la
plus proche à la plus lointaine (`front`, `front->front`…) :
- s'il est **entièrement contenu** dans la couche de devant, il est supprimé ;
- s'il la **chevauche**, on détache dans cet ordre la partie **à gauche** (colonnes < MinX de la couche
  de devant, toute la hauteur restante), **à droite**, **au-dessus**, **au-dessous** ; chaque morceau
  détaché est inséré **en tête** de la liste et poursuit le découpage avec les couches plus en avant ;
  le reste (inclus dans la couche de devant) est supprimé.
Conséquence observée : les visibles sont en tête de liste, les cachés à la suite ; ex. A (16,10)-(115,59)
sous B (60,30)-(159,89) → `(60,10)-(115,29)` puis `(16,10)-(59,59)` puis le caché `(60,30)-(115,59) lobs B`.
Cet ordre n'est **pas normatif** (graphics n'en dépend pas, et ClipBlit le permute). [O]

### 3.2 Cachés : objets persistants [D]

- Un ClipRect caché décrit une zone de la couche recouverte ; `lobs` = couche **la plus en avant** qui la
  recouvre ; `BitMap` = sauvegarde si la couche n'est pas SIMPLE.
- **Pavage** : les zones cachées de toutes les couches forment un pavage commun ; quand une nouvelle
  couche (ou un nouvel ordre) introduit une frontière, les ClipRects cachés traversés sont **coupés**
  aux bornes de la couche concernée (le contenu sauvegardé est recopié dans les nouveaux tampons). Ex. :
  A caché par B en (60,30)-(115,59), puis C (100,20)-(199,49) créé devant → A obtient (60,30)-(99,59)
  lobs B, (100,50)-(115,59) lobs B, (100,30)-(115,49) **lobs C** ; et B, caché par C, est coupé à la
  colonne 115/116 : (100,30)-(115,49) et (116,30)-(159,49). [O]
- Les ClipRects cachés **ne sont pas rendus à la réserve** au recalcul : ils changent de propriétaire.

### 3.3 Changement d'ordre : sort de chaque zone [D][O]

Quand une couche X passe **devant** une couche Y sur une zone `R` (ClipRect de X caché par Y) :

| X (monte) | Y (descend) | Effet sur l'écran et les tampons | Dommage |
|---|---|---|---|
| non SIMPLE | non SIMPLE | **échange** écran ↔ tampon (3 blits XOR, minterm `$6A`, masque = `X.rp->Mask`) : le contenu de X apparaît, celui de Y est sauvé dans le même tampon | aucun |
| non SIMPLE | SIMPLE | tampon de X **restauré** à l'écran (`$CA`), puis attente blitter et **libération** du tampon | aucun (Y perd la zone) |
| SIMPLE | non SIMPLE | l'écran (contenu de Y) est **sauvé** dans un tampon alloué pour l'occasion, puis la zone est **effacée** | `R` ajouté à X.DamageList, X |= LAYERREFRESH |
| SIMPLE | SIMPLE | zone **effacée** | idem |

Puis l'objet ClipRect passe de la liste de X à celle de Y avec `lobs = X`, et les ClipRects de mêmes
bornes des couches plus en arrière reçoivent `lobs = X`. Le cas « X descend derrière Y » est le
symétrique (rôles inversés). Vérifié : UpfrontLayer(A smart) au-dessus de B simple et C smart → pixels
de A restaurés, aucun dommage ; BehindLayer(A) → B simple reçoit les deux rectangles redécouverts en
dommage et la zone est effacée à 0, C smart retrouve ses pixels. [O]

**Effacement** d'une zone SIMPLE redécouverte : couleur **0**, uniquement dans les plans du `Mask` du
RastPort de la couche concernée, par programmation **directe** du blitter (bords et centre par mots). [D]

### 3.4 Fusion après DeleteLayer [D][O]

Après la suppression d'une couche (et donc aussi de la couche temporaire de Move/Size), layers
**fusionne** deux ClipRects cachés d'une même couche s'ils ont le même `lobs` et partagent un côté
entier (même MinX/MaxX et contigus en Y, ou même MinY/MaxY et contigus en X), **à condition** que
toutes les autres couches aient soit les deux morceaux, soit aucun (pavage préservé). La fusion alloue
le nouveau ClipRect et son tampon, y recopie les deux contenus, et recommence l'examen de la couche ;
un manque de mémoire annule simplement la fusion. Vérifié : après DeleteLayer(C), A retrouve un unique
caché (60,30)-(115,59) lobs B. [O]

### 3.5 Coordonnées

- ClipRects, `bounds` : coordonnées **BitMap**. DamageList : coordonnées **couche**. [O]
- `Scroll_X/Y` ne modifient aucun ClipRect (ScrollLayer d'une couche non SUPER : seuls les champs
  changent, la liste reste identique). [O] graphics les soustrait en dessinant (graphics-blitter §5.2). [D]
- Aucune vérification que la couche tient dans la BitMap : des bornes hors BitMap conduisent à des
  blits hors tampon. [D]

---

## 4. Types de rafraîchissement

| Flags | Parties cachées | Redécouverte | Move | Size (agrandir) | Size (réduire) |
|---|---|---|---|---|---|
| **LAYERSIMPLE (1)** | ClipRect sans tampon : les dessins y sont perdus | effacée à 0 + dommage + LAYERREFRESH | **toute la couche** endommagée + LAYERREFRESH ; contenu en grande partie effacé (§5.6) [O] | toute la couche endommagée + LAYERREFRESH [O] | idem |
| **LAYERSMART (2)** | tampon CHIP | restaurée, pas de dommage | contenu copié, pas de dommage [O] | bande droite `(W−dx … W−1) × toute la hauteur` et bande basse `(toute la largeur) × (H−dy … H−1)` en dommage + LAYERREFRESH ; les bandes valent 0 [O] | dommages **non** rognés (§5.7) [O] |
| **LAYERSUPER (4)** (sans SMART) | tampon CHIP, comme SMART [D] | restaurée [D] | contenu copié [D] | pas de dommage ; contenu repris de la SuperBitMap [O] | idem [D] |
| **LAYERBACKDROP ($40)** | (selon SIMPLE/SMART) | | | | |

- Un bit SMART n'est jamais testé : **tout ce qui n'a pas LAYERSIMPLE est traité comme SMART**. Une couche
  `flags = 4` (SUPER seul, ce que crée intuition) a donc des tampons pour ses parties cachées. [D][O flags]
- **BACKDROP** n'agit que sur l'ordre : CreateBehindLayer d'une couche non BACKDROP la place **devant la
  première couche BACKDROP** ; d'une BACKDROP, tout au fond. UpfrontLayer d'une BACKDROP la place devant
  les autres BACKDROP seulement ; BehindLayer d'une non BACKDROP la place juste devant la première
  BACKDROP, d'une BACKDROP tout au fond. MoveLayerInFrontOf **ignore** BACKDROP. [D ; O : D backdrop reste au
  fond après UpfrontLayer, BehindLayer(A) → B, C, A, D]
- LAYERREFRESH : posé par layers à chaque dommage ; **jamais effacé par layers** (EndUpdate inclus). [D][O]

---

## 5. Fonctions

### 5.1 CreateBehindLayer (−42) [D ; O pour les effets visibles]

1. Verrous : LockLayerInfo, engraissement temporaire si `!(li->Flags & 1)` (échec ⇒ retour NULL),
   LockLayers (§7).
2. Couche allouée, `bounds` = arguments, `LayerInfo`, `Lock` initialisé puis **obtenu autant de fois que
   `LockLayersCount`** (la nouvelle couche est verrouillée au même niveau que les autres).
3. LAYERSUPER : `SuperBitMap = bm2`, 5 ClipRects en réserve dans `SuperSaveClipRects`.
4. RastPort 78 octets + InitRastPort, `rp->BitMap = bm`, `rp->Layer` ; DamageList = NewRegion (vide) ;
   `Flags = flags` (tel quel).
5. Insertion **tout au fond** : les ClipRects cachés des autres couches sont coupés aux bornes de la
   nouvelle (§3.2) ; la nouvelle reçoit des ClipRects cachés pour chaque zone recouverte (lobs = couche la
   plus en avant) ; non SIMPLE : chaque caché reçoit un tampon **effacé** (BltClear) ; SUPER : liste
   `SuperClipRect` bâtie (§6) ; `Lock` ajouté en fin de `gs_Head`. Puis, si la couche n'est pas BACKDROP,
   elle est remontée devant la première BACKDROP (§3.3) ; si cela échoue, elle est supprimée et l'appel
   échoue. Recalcul des visibles ; SUPER : **CopySBitMap** (le contenu de la SuperBitMap apparaît).
6. Déverrouillage, puis **hors verrous** : si non SUPER, **SetRast(rp, 0)** (toute la couche, visibles et
   tampons, à 0). Retour : la couche.

Observé : B SIMPLE créée **derrière** A : `Flags $0001`, `priority 0`, **aucun dommage** pour sa partie
cachée, `(50,30)-(109,59) lobs A` sans tampon. [O]

### 5.2 CreateUpfrontLayer (−36)

= CreateBehindLayer puis UpfrontLayer ; si UpfrontLayer échoue : DeleteLayer, retour NULL ; sinon
**ClearRegion(DamageList)**. **LAYERREFRESH n'est pas effacé** : une couche SIMPLE créée devant une
autre couche a `Flags = $0081` avec une DamageList vide. [D][O] Pixels : la zone de la nouvelle couche
vaut 0 ; une SMART recouverte garde ses pixels dans son tampon. [O]

### 5.3 UpfrontLayer (−48) / BehindLayer (−54) / MoveLayerInFrontOf (−168)

- UpfrontLayer : cible = sommet (non BACKDROP) ou première BACKDROP (BACKDROP). Si la couche y est déjà :
  **retour TRUE sans rien faire** (pas de renumérotation). [D][O]
- BehindLayer : cible §4. MoveLayerInFrontOf(l, other) : place `l` juste devant `other` ;
  `other = NULL` ⇒ tout au fond ; si `l->back == other` : retour TRUE immédiat. [D]
- Effet : renumérotation des priorités (1000 vers le bas, ordre courant), échanges de zones §3.3,
  rechaînage, recalcul des visibles. Retour 1, ou 0 si un tampon n'a pu être alloué (état inchangé).
  [D ; O : retour 0 et ordre/ClipRects inchangés quand la CHIP est épuisée]
- Aucun effet sur la couche déplacée elle-même s'agissant des dommages lorsqu'elle est non SIMPLE.

### 5.4 DeleteLayer (−90) [D ; O pour l'effet visible]

Sous les verrous de pile : DisposeRegion(DamageList) ; SUPER : réserve libérée, **SyncSBitMap**
(la SuperBitMap reçoit l'état final), SuperClipRects libérés, `SuperBitMap = SuperClipRect = NULL` ;
WaitBlit ; tous les ClipRects cachés (et tampons) libérés ; la couche devient **SIMPLE** (bits SMART et
SUPER effacés) ; **SetRast(rp, 0)** sur sa partie visible ; elle est envoyée **tout au fond** (§3.3 : les
couches SMART redécouvertes sont restaurées, les SIMPLE effacées + dommage + LAYERREFRESH) ; RastPort
libéré ; retirée de la pile et de `gs_Head` ; fusion §3.4 ; recalcul des visibles ; couche libérée.
- Une zone qui ne redevient visible pour **aucune** couche reste à **0**. [O]
- La `ClipRegion` n'est pas libérée (installclipregion §4.2). Retour 1 (0 seulement si l'engraissement
  temporaire échoue).
- Observé : DeleteLayer(C) → la BACKDROP SIMPLE D reçoit en dommage `(116,25)-(169,29)` et
  `(170,25)-(199,49)` (zones de C non couvertes par B), `Flags $00C1`. [O]
- **SetPatch 1.38** remplace ce vecteur en analysant ses premiers octets (setpatch-disk-resource §4).

### 5.5 BeginUpdate (−78) / EndUpdate (−84)

Détaillés dans installclipregion-v34 §4.1 ; compléments :
- BeginUpdate prend `LockLayerRom` et le **garde** jusqu'à EndUpdate ; la liste réduite = (visibles ∩
  dommages) + (cachés avec tampon ∩ dommages, tampons propres recopiés). DamageList **vide** ⇒
  `ClipRect = NULL`, retour **1** (rien ne sera dessiné). Échec d'allocation ⇒ liste partielle,
  `LAYER_CLIPRECTS_LOST`, retour 0. [O pour 1 et NULL ; D pour l'échec]
- EndUpdate(l, flag) : `flag ≠ 0` ⇒ ClearRegion(DamageList) ; recopie des tampons propres vers les
  tampons d'origine ; liste normale rétablie, `_cliprects = NULL` ; efface LAYERUPDATING ; réinstalle la
  ClipRegion éventuelle ; UnlockLayerRom. **LAYERREFRESH n'est pas touché.** [D][O]

### 5.6 MoveLayer (−60) [D ; O pour les résultats]

- `dx = dy = 0` ⇒ retour 1 **sans verrou**. [O]
- Sinon, sous les verrous de pile : couche temporaire T = CreateBehindLayer(même BitMap, bornes
  translatées, `flags = (flags & 3) | BACKDROP`), BACKDROP retiré si l'originale n'en est pas une ;
  T placée juste devant l'originale (§3.3, T jouant le rôle de la couche qui monte) ; recalcul ;
  LAYERREFRESH effacé sur T ; **copie** du contenu de l'originale vers T (à travers les ClipRects des
  deux, `$CA`) ; si T est SIMPLE : `(0,0)-(W−1,H−1)` en dommage + LAYERREFRESH ; **échange** de T et de
  l'originale (position dans la pile, ClipRects, `lobs` qui les désignent, bounds) ; DamageList de
  l'originale |= celle de T, LAYERREFRESH reporté ; suppression de T (qui porte l'ancienne géométrie :
  §5.4, d'où restauration/dommage des couches redécouvertes). Retour 1, ou 0 (état inchangé). [O]
- La structure `Layer` **garde son adresse** ; son `rp` aussi. Le bit SUPER n'est pas transmis à T (la
  copie passe par les ClipRects, SuperClipRects inchangés). [D]
- **Couche SIMPLE** : le contenu est en grande partie **perdu** (les zones de l'ancienne position
  recouvertes par T sont effacées avant la copie) et toute la couche est endommagée. En outre, la
  DamageList reçoit des rectangles **parasites** : pour chaque ClipRect caché sans tampon de l'originale,
  un rectangle dont MinX/MinY sont relatifs au ClipRect et MaxX/MaxY en coordonnées écran. Observé
  (B 100×60 déplacée de (+8,+4)) : région de bornes `(0,0)-(149,89)` au lieu de `(0,0)-(99,59)`. Sans
  effet visible (BeginUpdate intersecte avec les ClipRects), mais les **bornes** de la DamageList peuvent
  déborder de la couche. Une réimplémentation peut se contenter d'endommager la couche entière. [O]
- **Couche SMART** : contenu intégralement conservé, aucun dommage pour elle. [O]

### 5.7 SizeLayer (−66) [D ; O]

Même schéma que MoveLayer avec T = (MinX, MinY, MaxX + dx, MaxY + dy). Différences :
- Couche non SUPER : copie de contenu de l'originale vers T sur `min(largeurs) × min(hauteurs)` ; SUPER :
  **SyncSBitMap** de l'originale à la place.
- Dommages : T SIMPLE ⇒ DamageList de T **vidée** puis = toute la couche, LAYERREFRESH. T SMART non
  SUPER ⇒ `dx > 0` : bande droite `(W−dx, 0)-(W−1, H−1)` ; `dy > 0` : bande basse `(0, H−dy)-(W−1, H−1)`
  (W, H = nouvelles dimensions), LAYERREFRESH ; `dx < 0` ou `dy < 0` : la DamageList **de T** est rognée
  à la nouvelle taille — or c'est la DamageList de **l'originale** qui survit (fusionnée avec celle de T)
  et elle **n'est pas rognée** : des dommages hors de la couche réduite subsistent. SUPER : aucun dommage.
  Observé : SizeLayer(C, +20, +10) sur 100×30 → dommages `(100,0)-(119,39)` et `(0,30)-(99,39)` ; puis
  SizeLayer(C, −30, −15) → dommages **inchangés** (débordant de la couche 90×25). [O]
- Après l'échange : SUPER ⇒ **CopySBitMap** puis reconstruction des SuperClipRects. [D][O]

### 5.8 ScrollLayer (−72) [D ; O]

Sous `LockLayerRom` seulement (pas de LockLayers ⇒ pas de neutralisation des ClipRegions) :
- **sans SuperBitMap** : `Scroll_X += dx`, `Scroll_Y += dy`, **rien d'autre** (aucun pixel déplacé,
  aucun dommage, aucune borne) ; [O]
- **avec SuperBitMap** : SyncSBitMap, ajout, CopySBitMap, reconstruction des SuperClipRects. Les valeurs
  ne sont **pas bornées** à la SuperBitMap. [D ; O pour l'affichage]
Valeur rendue indéfinie. [O]

### 5.9 WhichLayer (−132) [D][O]

Parcourt la pile depuis `top_layer` et rend la première couche dont `bounds` (bornes **incluses**,
comparaisons signées 16 bits) contient `(x, y)` ; NULL sinon. Ne tient compte ni des ClipRects, ni de
BACKDROP, ni d'un verrou (l'appelant doit tenir LockLayerInfo). Observé : coins (16,10) et (115,59)
inclus ; point hors de toute couche → NULL.

### 5.10 Layer_Info : InitLayers, NewLayerInfo, Fatten, Thin, Dispose [D][O]

- **InitLayers(li)** : efface 102 octets, NewList(FreeClipRects) et NewList(gs_Head), InitSemaphore(Lock),
  `fatten_count = −1`. Flags = 0. [O]
- **NewLayerInfo()** : AllocMem(102, MEMF_PUBLIC), InitLayers, engraissement ; échec ⇒ libère, NULL ;
  sinon `Flags |= 1`. Observé : `Flags 0001, fatten 00, extra_size 0042, blitbuff ≠ 0, extra ≠ 0`. [O]
- **FattenLayerInfo** : `fatten_count++` ; au passage −1 → 0, alloue l'extra (66 o, MEMF_PUBLIC) et
  blitbuff (128 o, CHIP) ; échec ⇒ 0 (attention : le compteur reste incrémenté) [D] ; sinon `Flags |= 1`,
  retour 1. **ThinLayerInfo** : `fatten_count−−` ; si l'ancienne valeur était ≤ 0, libère extra et
  blitbuff (`extra = NULL`, blitbuff **non** remis à NULL) ; `Flags &= ~1`. [D][O]
- **DisposeLayerInfo** : Thin puis FreeMem(102). Ne vérifie pas qu'il reste des couches. [D]
- **Layer_Info sans Fatten** (programmes 1.0/1.1, InitLayers seul) : chaque opération engraisse
  temporairement puis amaigrit ; ça fonctionne (création/suppression observées sur une Layer_Info
  statique) et `extra_size` reste à `$42`. [O]

### 5.11 LockLayer, UnlockLayer, LockLayers, UnlockLayers, LockLayerInfo, UnlockLayerInfo — §7.

### 5.12 SwapBitsRastPortClipRect (−126) [D ; O]

Échange le contenu de `rp->BitMap` dans `cr->bounds` avec `cr->BitMap` (tampon à la colonne `MinX & 15`,
ligne 0) par **trois** BltBitMap XOR (minterm `$6A`, masque `rp->Mask`) : écran ^= tampon ; tampon ^=
écran ; écran ^= tampon. Aucun verrou, aucune modification de liste. Appliqué deux fois, l'état revient.
Observé : sur un ClipRect caché de A (smart) sous B (simple, zone à 0), les pixels écran passent à 1
(contenu de A) puis reviennent à 0. [O]

---

## 6. SuperBitMap ; SyncSBitMap / CopySBitMap (graphics)

- **SuperClipRect** (`$24`) = morceaux de la SuperBitMap situés **hors de la fenêtre** `[Scroll_X,
  Scroll_X + W − 1] × [Scroll_Y, Scroll_Y + H − 1]`, en **coordonnées SuperBitMap**, `lobs = BitMap =
  NULL`, découpés comme §3.1 (gauche, droite, haut, bas ; insertion en tête ⇒ ordre de liste bas, haut,
  droite, gauche). Reconstruits à la création, après ScrollLayer et SizeLayer. Ils puisent dans les 5
  ClipRects de `SuperSaveClipRects`. [D][O]
  Observé : couche 80×50, SuperBitMap 256×128, Scroll (0,0) → `(0,50)-(79,127)`, `(80,0)-(255,127)` ;
  Scroll (16,7) → `(16,57)-(95,127)`, `(16,0)-(95,6)`, `(96,0)-(255,127)`, `(0,0)-(15,127)`. [O]
- Le dessin graphics dans une couche SUPER écrit dans la couche (visibles + tampons) **et** directement
  dans la SuperBitMap pour les morceaux SuperClipRect (graphics-blitter §5.2). [D]
- **SyncSBitMap(l)** (graphics −444) : copie la couche (visibles depuis l'écran, cachés depuis leurs
  tampons) **vers** la SuperBitMap, la coordonnée couche (0,0) correspondant à la SuperBitMap
  `(Scroll_X, Scroll_Y)` ; `SuperBitMap` est mis à NULL le temps de la copie pour ne pas repasser par les
  SuperClipRects. **CopySBitMap(l)** (−450) : l'inverse, SuperBitMap → couche, même mise à NULL
  temporaire. Ni l'un ni l'autre ne verrouille. [D]
- Observé : à la création, le pixel écran du coin de la couche = pixel (0,0) de la SuperBitMap ; après
  ScrollLayer(16,7) = pixel (16,7). SizeLayer(+8,+4) : pas de LAYERREFRESH. [O]

---

## 7. Verrous [D ; O pour les compteurs]

| Fonction | Effet |
|---|---|
| LockLayer(dummy, l) / UnlockLayer(l) | = `LockLayerRom`/`UnlockLayerRom` de graphics = Obtain/ReleaseSemaphore(`&l->Lock`) |
| LockLayerInfo(li) / UnlockLayerInfo(li) | Obtain/ReleaseSemaphore(`&li->Lock`) |
| LockLayers(li) | LockLayerInfo(li) (**conservé**), `LockLayersCount++`, **ObtainSemaphoreList(&li->gs_Head)** (tous les `Layer.Lock`), au passage à 1 : neutralisation des ClipRegions |
| UnlockLayers(li) | `LockLayersCount−−`, au passage à 0 : réinstallation des ClipRegions ; ReleaseSemaphoreList ; UnlockLayerInfo |

- Sonde (nids : `LockLayersCount / li->Lock / A->Lock`) : LockLayers `1/1/1`, encore `2/2/2`,
  UnlockLayers `1/1/1`, `0/0/0` ; LockLayer(A) `0/0/1` ; LockLayerInfo `0/1/0`. [O]
- **Toute opération de pile** (Create*, Upfront, Behind, MoveInFrontOf, Move, Size, Delete) :
  LockLayerInfo → engraissement temporaire éventuel → LockLayers … UnlockLayers → amaigrissement →
  UnlockLayerInfo. Pendant l'opération, la tâche tient donc `li->Lock` à un niveau ≥ 2 et toutes les
  couches. Tout est réentrant pour la même tâche (sémaphores imbriqués) : une application qui tient
  LockLayers peut appeler ces fonctions. [D]
- Une couche créée pendant un LockLayers est verrouillée au même niveau (§5.1). Une couche supprimée
  sous LockLayers disparaît de `gs_Head` avec son sémaphore (tenu) : une autre tâche en attente sur ce
  verrou serait réveillée sur une mémoire libérée. [D]
- Hors pile : BeginUpdate…EndUpdate tiennent `LockLayerRom` ; ScrollLayer et InstallClipRegion le
  prennent le temps de l'appel ; **WhichLayer, SwapBits, Fatten/Thin ne prennent aucun verrou**. [D]
- graphics dessine sous `Layer.Lock` : une tâche qui tient LockLayers bloque le dessin des autres. [D]

---

## 8. Mémoire et échecs

| Objet | Taille | Attributs |
|---|--:|---|
| Layer | 160 | MEMF_CLEAR |
| RastPort de couche | 78 | MEMF_PUBLIC (effacé par InitRastPort) |
| ClipRect | 40 | MEMF_CLEAR (ou recyclé depuis FreeClipRects, alors effacé) |
| BitMap de tampon | 8 + 4 × Depth | MEMF_CLEAR |
| Plan de tampon | BytesPerRow × Rows | **MEMF_CHIP** |
| DamageList | Region | NewRegion |
| Layer_Info (NewLayerInfo) | 102 | MEMF_PUBLIC |
| extra / blitbuff | 66 / 128 | MEMF_PUBLIC / **MEMF_CHIP** |
| suivi d'allocations | 278 par lot de 32 | transitoire |

- **Transactions** [D ; O] : les opérations de pile enregistrent chaque allocation ; au premier échec,
  tout ce qui a été alloué depuis le début est libéré et l'état des ClipRects est restauré depuis
  l'instantané (`_cliprects`/`prev`), puis la fonction rend 0/NULL. Observé avec la CHIP épuisée :
  BehindLayer(A smart derrière B simple) = 0, CreateUpfrontLayer(smart chevauchant) = NULL, SizeLayer = 0,
  MoveLayer = 0 ; ordre, ClipRects, dommages et pixels **inchangés** ; après libération de la CHIP, le même
  BehindLayer réussit. [O]
- **Alerte fatale `$83010000`** (AN_LayersNoMem, bit 31 = dead-end) si un ClipRect ne peut être obtenu
  pendant le recalcul des visibles **après** validation (la réserve est d'abord utilisée, une allocation
  n'arrive que si les morceaux sont plus nombreux qu'avant). [D, non sondé]
- BeginUpdate / InstallClipRegion / UnlockLayers : échec ⇒ liste partielle + `LAYER_CLIPRECTS_LOST`, pas
  d'alerte, pas de retour arrière. [D]
- Fusion §3.4 : échec ⇒ fusion abandonnée, sans conséquence. [D]

---

## 9. Ce qui diffère sur un vrai A500

1. **Blitter programmé directement** pour effacer les zones SIMPLE redécouvertes (registres BLTCON0,
   masques de premier/dernier mot, modulos, BLTSIZE ; OwnBlitter + WaitBlit avant chaque plan,
   DisownBlitter **sans attendre** la fin du dernier blit). Un émulateur « instantané » masque l'absence
   d'attente ; sur Agnus réel, l'accès processeur suivant doit être précédé d'un WaitBlit. [D]
2. **Tous les tampons de ClipRects et blitbuff en CHIP**, et la BitMap de l'écran doit l'être : une BitMap
   d'application en slow RAM (`$C00000`) n'est pas accessible au blitter (corruption silencieuse). [D]
3. **WaitBlit avant de libérer un tampon** (restauration puis FreeMem, DeleteLayer, EndUpdate, fusion) :
   sans cela, la mémoire CHIP rendue peut être réallouée pendant que le blitter la lit encore. [D]
4. Limites OCS non contrôlées : largeur d'effacement > 64 mots tronquée, hauteur > 1024 lignes débordante
   (impossible avec des écrans OCS normaux). [D]
5. **Pression mémoire CHIP** : chaque partie cachée d'une fenêtre SMART coûte `BytesPerRow × Rows ×
   Depth` octets CHIP ; sur 512 Ko, un déplacement de fenêtre peut **échouer** (MoveLayer = 0, la fenêtre
   ne bouge pas) — comportement normal à reproduire, pas une panne. L'alerte fatale §8 reste possible. [D]

---

## 10. Vecteurs de test (vraie ROM 34.5, FS-UAE)

Sonde `tests/layers_probe.s` : BitMap privée 320×200×2 (plans pré-remplis à `$FF`), Layer_Info par
NewLayerInfo. Format : `L<tag> Flags priority bounds(MinX MinY MaxX MaxY) Scroll front back _cliprects`,
`C`/`S` = ClipRect (`bounds lobs BytesPerRow Rows Depth Flags`), `D` = DamageList (bornes puis
rectangles relatifs), `P x y pen`, `=` valeur rendue. A = SMART (16,10)-(115,59), B = SIMPLE
(60,30)-(159,89), C = SMART (100,20)-(199,49), toutes par CreateUpfrontLayer, remplies pen 1/2/3.

```
0022 0001 00AE 002A                          version 34.1, NegSize 174, PosSize 42
T0  I0 0001 00 00 0042 <blitbuff> <extra> …  NewLayerInfo
T1  P(16,10)=00 P(15,10)=03                  SetRast de la nouvelle couche, extérieur intact
T2  LB 0081 03E7 …                           B simple créée devant : LAYERREFRESH, DamageList vide
    LA 0002 03E8 …
      C 003C000A0073001D 0 -                 (60,10)-(115,29) visible
      C 0010000A003B003B 0 -                 (16,10)-(59,59) visible
      C 003C001E0073003B B 000A001E02        caché par B, tampon 10 o × 30 × 2
T3  LB … C 0064001E00730031 C - / C 0074001E009F0031 C -    B coupé à 115/116 (pavage)
    LA … C 006400140073001D C 0004000A02 / C 003C001E0063003B B 0008001E02
         C 006400320073003B B 0004000A02 / C 0064001E00730031 C 0004001402
T4  =1 UpfrontLayer(A)  P(70,40)=01 P(105,25)=01   restauré ; B : aucun dommage
T5  =1 BehindLayer(A)   LB … D 000000000037001D 002800140037001D 000000000027001D
    P(70,40)=00 P(105,25)=03                   B simple effacée + dommages, C smart restauré
T6  =1 UpfrontLayer(B)  LB … D 000000000063001D … 0028000000370013 0038000000630013  (cumul)
T7  =1 MoveLayer(C,+10,+5)  LC 0002 … 006E001900D10036 ; P(105,25)=01 P(205,35)=03
T8  =1 SizeLayer(C,+20,+10) LC 0082 … D 0000000000770027 0064000000770027 0000001E00630027
    =1 SizeLayer(C,-30,-15) LC 0082 … 006E001900C70031 … D (inchangé)
T9  =1 SizeLayer(B simple,+10,0) LB 0081 … D 00000000006D003B 00000000006D003B
    =1 MoveLayer(B,0,0) ; ScrollLayer(B,3,4) → Scroll 0003 0004, ClipRects inchangés
T10 =1 BeginUpdate(A, dommage (10,5)-(29,14)) : LA 0012 … C 001A000F002D0018 0 -
    EndUpdate(A,TRUE) : LA 0002 … _cliprects 00000000, D vide ; BeginUpdate dommage vide : ClipRect 00000000
T11 WhichLayer : A B A B C 0 A B
T12 k01/0001/0001 k02/0002/0002 k01/0001/0001 k00/0000/0000 k00/0000/0001 … k00/0001/0000
T13 D BACKDROP|SIMPLE plein écran : O B:03E8 C:03E6 A:03E5 D:0000 ; UpfrontLayer(D) =1, ordre inchangé
    MoveLayerInFrontOf(A,B) =1 : O A B C D ; BehindLayer(A) =1 : O B:03E7 C:03E6 A:03E8 D:03E5
T14 S SUPER (200,120)-(279,169), SuperBitMap 256×128 : S 00000032004F007F, S 0050000000FF007F
    ScrollLayer(S,16,7) : S 00100039005F007F, S 00100000005F0006, S 0060000000FF007F, S 00000000000F007F
T15 =1 DeleteLayer(C) : LA … C 003C001E0073003B B 000A001E02 (fusionné) ;
    LD 00C1 … D 0074001900C70031 0000000000350004 0036000000530018 ; P(180,30)=00
T17 InitLayers sur Layer_Info statique : I0 0000 FF 00 0000 … ; CreateUpfrontLayer OK sans Fatten
T20 CreateBehindLayer(B simple derrière A) : LB 0001 0000 …, C 0032001E006D003B A -, D vide
T21 =1 MoveLayer(B simple,+8,+4) : LB 0081 … D 0000000000950059 (12 rectangles, déborde la couche)
T23 SwapBits sur le caché de A : P(60,40) 00 → 01 → 00
T24 CHIP épuisée : BehindLayer(A)=0, CreateUpfrontLayer=NULL, SizeLayer=0, MoveLayer=0, état inchangé ;
    CHIP rendue : BehindLayer(A)=1
```

Non-régression proposée : reproduire ces lignes (pointeurs exceptés).

---

## Points non tranchés

1. **Couche SUPER cachée par une autre** : la présence de tampons pour ses parties cachées et leur
   interaction avec SyncSBitMap/CopySBitMap sont déduites, non sondées (la couche S de la sonde n'était
   pas recouverte).
2. **Alerte `$83010000`** et échec mémoire de BeginUpdate (`LAYER_CLIPRECTS_LOST`) : lecture seule, non
   provoqués.
3. **Usage de `blitbuff`** : jamais lu par layers ; un usage par graphics ou intuition n'a pas été
   recherché.
4. **Effet de Scroll_X/Y sur le dessin d'une couche non SUPER** : repris de graphics-blitter §5.2 (déduit),
   non vérifié ici par un dessin après ScrollLayer.
5. **MoveLayerInFrontOf** avec `other` d'une autre Layer_Info, `other = l` ou `other = NULL` : déduit
   seulement.
6. Ordre exact des ClipRects cachés et des SuperClipRects dans des configurations à plus de trois
   couches : non normatif, seuls les cas du §10 sont observés.
7. Valeur rendue par Open (la base est bien obtenue par OpenLibrary, mais le registre source n'a pas été
   vérifié sur l'exec 1.3).
8. Rectangles parasites de la DamageList d'une couche SIMPLE déplacée : observés ; l'explication
   (coordonnées mixtes) est déduite. Rien n'indique qu'un logiciel 1.3 lise ces bornes.
9. Interblocages entre tâches (ObtainSemaphoreList pendant qu'une autre tâche tient un `Layer.Lock` et
   attend `li->Lock`) : non étudiés.

---

## Relecture clean-room

- [x] Aucune suite d'instructions transcrite ni paraphrasée ; aucune adresse de routine ROM (seuls des
  LVO, offsets de structures publiques/privées, tailles, constantes d'ABI et registres matériels).
- [x] Les algorithmes sont décrits par leur **effet** (formes, ordres, valeurs), vérifiés par sonde quand
  c'est marqué [O].
- [x] La sonde citée est du code auteur (`tests/layers_probe.s`, en-tête « ASSET DE TEST, PAS du code ROM »).
