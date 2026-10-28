# graphics.library 34.1 — remplissages, ellipses, Flood, pixels : spec comportementale

> Piste **ANALYSE** (« dirty »). Sources : ROM `assets/kick34005.A500` (lecture seule, radare2, base
> `$FC0000` ; notes de désassemblage hors dépôt) et sonde boîte noire `tests/garea_probe.s` (harnais
> `tests/garea_probe.sh`) exécutée **deux fois** sur la **vraie ROM** sous FS-UAE (A500 PAL, 512 Ko chip +
> 512 Ko slow, boot DOS sur une disquette dont la startup-sequence lance la sonde) ; les tests T0–T25
> communs aux deux passes ont donné une sortie **identique octet pour octet**.
> La sonde dessine dans une BitMap **32 × 20 à 2 plans** en chip RAM, RastPort **sans couche**, puis
> relève les plans par le processeur après WaitBlit.
> Ce document décrit des **comportements**, des **valeurs**, des **ordres d'opérations** et des
> **layouts d'ABI**. Il ne contient aucune suite d'instructions de la ROM ni adresse de routine.
> Il complète, sans les répéter : `graphics-blitter-v34.md` (§8 BltPattern, moteur de rendu final de
> tout ce qui suit ; §5 découpage par ClipRects ; §7 allocations), `workbench-task-v34.md` §3.6 (usage de
> Flood par le Workbench).
>
> **Niveaux de preuve** : **[O]** observé par la sonde sur la vraie ROM · **[D]** déduit de la lecture
> du code de la ROM (comportement, pas de code) · **[S]** supposition raisonnable, non vérifiée.
>
> Conventions des schémas : une ligne par y (0 en haut), une colonne par x (0 à gauche) ; `.` = couleur
> 0, sinon le chiffre de la couleur (plan 0 = bit 0, plan 1 = bit 1).

## 0. Résumé pour l'implémenteur

- Les huit LVO `InitArea` (−282), `AreaMove` (−252), `AreaDraw` (−258), `AreaEnd` (−264),
  `AreaEllipse` (−186), `DrawEllipse` (−180), `InitTmpRas` (−468), `Flood` (−330) sont **tous présents
  en V34** (vecteurs réels dans la table de 109 entrées). `AreaCircle`, `DrawCircle`, `SetAfPt`,
  `SetOPen`, `BNDRYOFF` **n'ont pas de LVO** : ce sont des macros d'en-tête (`graphics/gfxmacros.h`). [D]
- **AreaEnd** = méthode classique du blitter : (1) les arêtes sont tracées **un point par ligne** en
  **XOR** dans un plan masque (la TmpRas), (2) le masque est rempli par le blitter en **remplissage
  exclusif, parcours descendant**, (3) **toutes** les arêtes sont tracées à nouveau **en entier** (OU)
  dans le masque, (4) le masque est rendu par **BltPattern** (stylos, mode, motif, couches). Résultat :
  règle **pair/impair**, **bords inclus des deux côtés**, y compris les arêtes horizontales. [D][O]
- **Exception** : si `DrawMode == JAM1` **et** `AreaPtSz == 2`, l'étape (3) **efface** les arêtes au lieu
  de les ajouter : les bords sont **exclus** (artefact d'une comparaison sur un mot, §4.5). [D][O]
- **AreaEllipse** occupe **2 entrées** (coins du rectangle englobant) ; le remplissage d'ellipse est
  **exactement l'intérieur, bord compris, du tracé de DrawEllipse** avec les mêmes rayons. [O]
- **Valeurs rendues** : 0 = succès, **−1 = plus de place** dans le tampon de sommets (AreaMove/AreaDraw/
  AreaEllipse, et AreaEnd s'il doit ajouter l'arête de fermeture sans place). AreaEnd sur une liste vide
  rend une **valeur indéfinie**. Flood rend **1** (succès) ou **0** (échec). WritePixel rend 0 (−1 hors
  couche) ; ReadPixel rend la couleur (−1 hors couche). [O][D]
- **Aucun contrôle de taille** : AreaEnd **ignore `TmpRas.Size`** ; Flood l'utilise comme taille d'une
  **allocation chip supplémentaire**. Sans couche, WritePixel/ReadPixel/AreaEnd ne **découpent rien**. [O][D]
- **Flood** : remplissage par **graine, 4-connexe** ; mode 0 = « jusqu'à la couleur AOlPen », mode 1 =
  « tant que la couleur du point de départ » ; rendu final par BltPattern (motif et stylos appliqués).
  Sans TmpRas : le mode 0 marche encore (chemin lent), le mode 1 **échoue (0)**. [O][D]

## 1. Structures (ABI)

### 1.1 AreaInfo (24 octets, `graphics/rastport.h`) [D][O]

| Décalage | Champ | Usage V34 |
|---|---|---|
| $00 | `VctrTbl` (long) | début de la table des sommets (paires de mots x, y) |
| $04 | `VctrPtr` (long) | prochaine entrée libre de la table des sommets |
| $08 | `FlagTbl` (long) | début de la table des drapeaux (1 octet par entrée) |
| $0C | `FlagPtr` (long) | prochain drapeau libre |
| $10 | `Count` (mot) | nombre d'entrées enregistrées |
| $12 | `MaxCount` (mot) | capacité en entrées |
| $14 | `FirstX` (mot) | x du dernier AreaMove (point de fermeture du polygone courant) |
| $16 | `FirstY` (mot) | y du même point |

**Tampon fourni à InitArea** : `MaxCount × 5` octets ; les `4 × MaxCount` premiers octets sont la table
des sommets, les `MaxCount` suivants la table des drapeaux. Observé : InitArea(…, 40) → `FlagTbl =
tampon + $A0`. [O] Le décalage est ajouté sur **16 bits signés** : au-delà de 8191 entrées la table des
drapeaux tombe avant le tampon. [D] Le tampon n'est lu et écrit **que par le processeur** : il peut être
en n'importe quelle RAM. [D] Alignement : pair exigé (accès mots/longs sur 68000). [S]

**Drapeau d'une entrée** (octet) [D][O] :

| Bit | Sens |
|---|---|
| 0 | arête **non horizontale** (le y du sommet diffère du y du sommet précédent) |
| 1 | entrée **tracée** (AreaDraw ou ellipse) ; 0 = AreaMove |
| 2 | **contour demandé** : `AREAOUTLINE` (bit 3 de `rp_Flags`) était posé **au moment de l'AreaDraw** |
| 7 | première entrée d'une **ellipse** |

Valeurs observées : AreaMove `$00`, AreaDraw horizontal `$02`, oblique/vertical `$03`, mêmes valeurs
avec contour actif `$06`/`$07`, ellipse `$83` puis `$02`. [O] (T7, T28)

### 1.2 TmpRas (8 octets) [D]

`$00 RasPtr` (long, tampon en **chip**) · `$04 Size` (long). InitTmpRas n'écrit que ces deux champs.

### 1.3 Champs de RastPort concernés [D]

`$0C TmpRas` · `$10 AreaInfo` · `$08 AreaPtrn` · `$1D AreaPtSz` (octet signé) · `$1B AOlPen` ·
`$19 FgPen` · `$1A BgPen` · `$1C DrawMode` · `$20 Flags` (`AREAOUTLINE` = `$0008`, `ONE_DOT` = `$0002`,
`FRST_DOT` = `$0001`) · `$22 LinePtrn` · `$24 cp_x` · `$26 cp_y` · `$28 minterms[8]`.
**InitRastPort** pose `AOlPen = −1` (`$FF`) : un contour non configuré est tracé dans **tous** les plans
(couleur 3 sur 2 plans, T12). [O]

## 2. InitArea (−282) et InitTmpRas (−468)

- `InitArea(areaInfo A0, buffer A1, maxVectors D0)` : `VctrTbl = VctrPtr = buffer`, `FlagTbl = FlagPtr =
  buffer + 4 × maxVectors`, `MaxCount = maxVectors` (mot), `Count = 0`. **FirstX/FirstY ne sont pas
  touchés**. Aucune valeur rendue utile, aucune validation. [D][O] (T0)
- `InitTmpRas(tmpRas A0, buffer A1, size D0)` : `RasPtr = buffer`, `Size = size` (long) ; **rend `tmpRas`
  dans D0**. Aucune validation (ni chip, ni alignement, ni taille). [D][O] (T0)

## 3. Enregistrement des sommets

### 3.1 AreaMove (−252) — `(rp A1, x D0, y D1)` → D0 [D][O]

1. Si `Count + 1 > MaxCount` → rend **−1**, rien n'est modifié.
2. `Count` est incrémenté.
3. Si ce n'est pas la première entrée :
   - si l'entrée précédente est **aussi un AreaMove** (drapeau 0), elle est **remplacée** : Count, VctrPtr
     et FlagPtr reculent d'une entrée (Count revient à sa valeur initiale) ; observé : AreaMove(4,4) puis
     AreaMove(6,6) → Count = 1, FirstX/Y = (6,6) (T23) ;
   - sinon, si le dernier sommet diffère de (FirstX, FirstY), le polygone précédent est **fermé** par un
     appel d'**AreaDraw(FirstX, FirstY) par son LVO** (sensible à SetFunction). Si cet AreaDraw échoue,
     AreaMove rend −1 **en laissant Count incrémenté** sans entrée correspondante (AreaInfo incohérente :
     l'appelant doit refaire InitArea). [D]
4. `FirstX/FirstY = (x, y)`, sommet écrit, drapeau `$00`, rend **0**.

### 3.2 AreaDraw (−258) — `(rp A1, x D0, y D1)` → D0 [D][O]

Si `Count + 1 > MaxCount` → **−1** (rien n'est modifié ; observé T23 avec MaxCount = 3). Sinon Count+1,
sommet écrit, drapeau = `$02` | `$04` si `AREAOUTLINE` est posé maintenant | `$01` si y ≠ y du sommet
précédent ; rend **0**. AreaDraw **ne vérifie pas** qu'un AreaMove a précédé (il compare y avec le mot
situé avant la table si c'est la première entrée). [D]

### 3.3 AreaEllipse (−186) — `(rp A1, cx D0, cy D1, a D2, b D3)` → D0 [D][O]

1. Si Count ≠ 0 : un AreaMove isolé juste avant est **retiré** (comme 3.1) ; sinon, si l'entrée
   précédente n'est pas la fin d'une ellipse et que le dernier sommet ≠ (FirstX, FirstY), le polygone
   courant est **fermé** par AreaDraw (LVO) ; échec → −1.
2. Si `Count + 2 > MaxCount` → **−1** (T23).
3. Deux entrées : `(cx − a, cy − b)` drapeau `$83`, puis `(cx + a, cy + b)` drapeau `$02` ; Count += 2 ;
   rend **0**. [O] (T7 : drapeaux `83 02`)
4. **FirstX/FirstY ne sont pas mis à jour** ; le bit « contour » n'est **jamais** posé sur une ellipse.

Conséquence observée (T31) : `AreaEllipse` suivi d'`AreaDraw` sans `AreaMove` ferme ensuite le
polygone vers un **FirstX/FirstY périmé** (celui d'un AreaMove antérieur) et produit un dessin incohérent.
Il faut toujours commencer un polygone par AreaMove après une ellipse. [O]

`AreaCircle(rp, cx, cy, r)` = macro `AreaEllipse(rp, cx, cy, r, r)`. [D, en-têtes publics]

## 4. AreaEnd (−264) — `(rp A1)` → D0

### 4.1 Fermeture et cas vides [D][O]

- Dernière entrée = AreaMove : si `Count ≤ 1`, **rien n'est dessiné**, la liste est remise à zéro et D0
  est **indéfini** (observé `$0006` et `$FFFF` selon le contexte, T23/T31). Si `Count > 1`, le dernier
  AreaMove reste dans la liste (point isolé, sans effet). [D][O]
- Dernière entrée tracée : si ce n'est pas la fin d'une ellipse et que le dernier sommet ≠ (FirstX,
  FirstY), AreaEnd appelle **AreaDraw(FirstX, FirstY)** par son LVO ; échec → rend **−1** sans rien
  dessiner (T23 : 3 entrées sur MaxCount = 3 → −1). **Prévoir une entrée de plus par polygone** non fermé
  explicitement. [D][O]
- Dans tous les cas, à la sortie : `Count = 0`, `VctrPtr = VctrTbl`, `FlagPtr = FlagTbl` ; FirstX/FirstY
  inchangés. Succès → **0**. [D][O] (T1)

### 4.2 Rectangle englobant et TmpRas [D][O]

- Le rectangle englobant porte sur **toutes** les entrées (les ellipses y entrent par leurs deux coins).
  `x0 = minX & ~15` (arrondi au mot inférieur, arithmétique signée), `y0 = minY`.
- **Les sommets sont translatés en place** de (−x0, −y0) dans la table (observé T1 : après AreaEnd, la
  table contient `(2,0) (10,0) (10,8) (2,8) (2,0)` pour le carré (2,2)–(10,10), entrée de fermeture
  comprise). Le contenu de la table n'est donc **pas réutilisable** après AreaEnd. [O]
- Masque : un plan de `L = ((maxX + 16) & ~15 − x0) / 8` octets par ligne et `H = maxY − minY + 1` lignes,
  placé au début de `TmpRas.RasPtr`, effacé par **BltClear** (forme lignes/octets). **Besoin : `L × H`
  octets de chip.** [D]
- **`TmpRas.Size` n'est pas lu** : avec `Size = 4`, un remplissage plein écran 32 × 20 (80 octets) est
  correct (T24). Une TmpRas trop petite **déborde silencieusement**. [O][D]
- **TmpRas absente** (`rp_TmpRas = NULL`) : le pointeur est déréférencé quand même (lecture de RasPtr à
  l'adresse 0, puis écriture du masque à l'adresse lue) : corruption de la mémoire basse. [D] (non sondé)

### 4.3 Passe 1 : arêtes « un point par ligne » en XOR [D]

Un RastPort temporaire (sans couche, masque d'un plan, mode COMPLEMENT, `ONE_DOT`, motif de ligne plein)
parcourt la liste :

- entrée tracée non horizontale : ligne du blitter du point courant au sommet, **un seul point par ligne
  de balayage**, en XOR ; le **premier point de l'arête est omis** quand le sommet de départ n'est pas un
  extremum local en y (l'arête précédente allait dans le même sens), conservé sinon ;
- entrée tracée horizontale, ou ellipse : déplacement du point courant (les arêtes horizontales ne
  produisent aucun point dans cette passe) ; ellipse : **DrawEllipse** de centre `(coin1 + coin2) / 2` et
  de rayons `coin2 − centre`, en `ONE_DOT` (un point par ligne et par côté), par un traceur XOR direct
  au processeur ;
- AreaMove (et fin de liste) : si la première et la dernière arête non horizontales du polygone qui se
  termine vont **dans le même sens**, le point de départ est inversé une fois de plus (WritePixel par LVO)
  pour corriger la parité au sommet de fermeture.

Effet : sur chaque ligne de balayage, le masque contient un nombre pair de points délimitant les spans.

### 4.4 Passe 2 : remplissage du blitter [D]

Un seul blit sur le masque : canaux C → D, minterm « D = C », **parcours descendant**, **remplissage
exclusif (EFE)**, FCI = 0, largeur `L/2` mots, hauteur `H`, modulos `−2L` (chaque ligne est traitée de
droite à gauche, les lignes de haut en bas). En exclusif, le point qui ouvre le span (côté droit) est
gardé, celui qui le ferme (côté gauche) est perdu : c'est la passe 3 qui rétablit les bords.

### 4.5 Passe 3 : arêtes complètes [D][O]

Toutes les entrées tracées sont retracées **en entier** (premier point compris, lignes horizontales
comprises, ellipses par DrawEllipse normal) avec le minterm de ligne :

- **OU** (point mis à 1) dans le cas général → bords inclus ;
- **ET NON** (point mis à 0) si le **mot** formé par `DrawMode` et `AreaPtSz` vaut exactement `$0002`,
  c'est-à-dire `DrawMode = JAM1` et `AreaPtSz = 2`. Observé T29 : carré (2,2)–(12,12) en JAM1 avec un motif
  plein de 4 lignes → pixels **(3..11, 3..11)** seulement ; même carré avec AreaPtSz = 0 → (2..12, 2..12) ;
  en JAM2 avec AreaPtSz = 2 (T17) → bords inclus. Un clone compatible doit reproduire ce cas. [O]

### 4.6 Passe 4 : rendu et contour [D][O]

- **BltPattern(rp, masque, x0, y0, x0 + 8L − 1, y0 + H − 1, L)** par son **LVO** : stylos, DrawMode, Mask,
  motif `AreaPtrn/AreaPtSz` et découpage par les ClipRects de la couche sont ceux de BltPattern
  (`graphics-blitter-v34.md` §8 et §5.2). Coordonnées sans couche : **aucun découpage** aux bornes de la
  BitMap. [D]
- Puis, si `AREAOUTLINE` est posé **au moment d'AreaEnd** : tracé du contour sur le RastPort de
  l'appelant avec **FgPen = AOlPen, JAM1, LinePtrn = $FFFF, AreaPtrn = NULL** (puis restauration de
  DrawMode, FgPen, minterms, AreaPtrn, LinePtrn) : chaque entrée **dont le bit 2 est posé** est tracée par
  **Draw (LVO)** depuis le point précédent, les autres par Move. Le point courant `cp` du RastPort reste
  sur le dernier sommet. Les **ellipses ne sont jamais entourées**. [D][O]
  Observé T12 : contour activé seulement après les AreaDraw → seule l'arête de fermeture (ajoutée par
  AreaEnd) reçoit le contour. T11 : polygones entourés en AOlPen = 2 (bord et intérieur 1), ellipse sans
  contour.
- Sans `AREAOUTLINE`, le RastPort de l'appelant (cp compris) n'est pas modifié par AreaEnd. [D]

### 4.7 Lecture d'une entrée de trop après une ellipse [D][O]

Chaque ellipse consomme deux entrées en un seul tour de boucle, alors que les passes 1 et 3 font
`Count` tours : **pour chaque ellipse, une entrée située au-delà de Count est traitée** (sommet et
drapeau résiduels du tampon, non translatés). Observé : tampon remis à zéro → ellipse propre (T26) ;
tampon pré-rempli d'entrées `(0,0)` drapeau `$03` → **un point parasite** en (x0, y0) (T27) ; dans T7 et
T11 (résidus d'anciens tests), des **traits parasites** jusqu'à d'anciens sommets. Aucun logiciel ne peut
s'appuyer sur ce défaut ; une implémentation propre doit traiter exactement `Count` entrées [S] — mais
noter que, sur la vraie ROM, un tampon d'AreaInfo **mis à zéro** (AllocMem MEMF_CLEAR, cas courant) rend
le défaut invisible (entrée résiduelle = AreaMove en (x0, y0)).

### 4.8 Règle de remplissage : vecteurs de test [O]

Tous en APen 1, JAM2, BPen 0, sans motif.

- **Carré** (2,2)(10,2)(10,10)(2,10) : pixels x 2..10, y 2..10 (**81 pixels, bords inclus**). Même
  résultat parcouru dans l'autre sens et fermé explicitement (T1, T2).
- **Triangle** (16,1)(28,14)(4,14) (T3) :

```
  1  ................1...............
  2  ...............111..............
  3  ..............11111.............
  4  .............1111111............
  5  ............111111111...........
  6  ...........11111111111..........
  7  ..........1111111111111.........
  8  ..........1111111111111.........
  9  .........111111111111111........
 10  ........11111111111111111.......
 11  .......1111111111111111111......
 12  ......111111111111111111111.....
 13  .....11111111111111111111111....
 14  ....1111111111111111111111111...
```

- **Pentagramme** (16,1)(22,18)(6,7)(26,7)(10,18) (T4) : le pentagone central est **vide** (pair/impair)
  mais les **arêtes qui le traversent sont tracées** :

```
  1  ................1...............
  2  ................1...............
  3  ...............111..............
  4  ...............111..............
  5  ...............111..............
  6  ..............11111.............
  7  ......111111111111111111111.....
  8  .......11111111...11111111......
  9  .........11111.....11111........
 10  ..........1111.....1111.........
 11  ............1.......1...........
 12  ............111....11...........
 13  ............1111.1111...........
 14  ...........11111111111..........
 15  ...........11111.11111..........
 16  ...........111.....111..........
 17  ..........111.......111.........
 18  ..........1...........1.........
```

- **Deux carrés dans le même AreaEnd** (2,2)–(14,14) et (8,8)–(20,18) (T5) : l'intersection
  (9..13, 9..13) est **vide**, ses bords (lignes 8 et 14, colonnes 8 et 14) sont pleins. **Pair/impair,
  pas non nul.** Le second AreaMove a ajouté l'arête de fermeture du premier (Count = 9).
- **Polygone concave en C** (2,2)(28,2)(28,6)(8,6)(8,12)(28,12)(28,16)(2,16) (T6) : lignes 2..6 et
  12..16 pleines de x 2 à 28 ; lignes 7..11 de x 2 à 8 seulement.
- **Figures dégénérées** (T25) : un polygone d'aire nulle dessine ses **arêtes** : (5,2)–(12,2) → segment
  x 5..12 ; (3,5)–(20,5) → x 3..20 ; (3,8)–(3,15) → colonne ; (16,8)–(28,16) → segment oblique.
- **COMPLEMENT** (T16) : deux AreaEnd successifs (carrés (2,2)–(14,14) puis (8,8)–(20,18)) : chaque masque
  inverse **tous les plans du Mask** (0 → 3), l'intersection bords compris revient à 0.

## 5. Motifs de remplissage (AreaPtrn / AreaPtSz) [O]

Rendu par BltPattern, donc commun à AreaEnd, RectFill et Flood.

- **Monochrome** (`AreaPtSz = n ≥ 0`) : `2^n` mots ; la ligne de motif d'un pixel est **`y mod 2^n` en
  coordonnées absolues du RastPort**, le bit 15 du mot correspond à `x mod 16 = 0`. Observé (T13, motif
  `$F0F0,$0F0F`, n = 1) : ligne y = 1 → pixels x 4..7, 12..15… ; ligne y = 2 → x 0..3, 8..11… (le motif ne
  « démarre » pas au sommet de la figure).
- **JAM1** : bits 1 → APen, bits 0 → **fond conservé** ; **JAM2** : bits 0 → BPen ; **COMPLEMENT** : bits 1
  → inversion de tous les plans du Mask, bits 0 → inchangé (T30, sur fond de couleur 2 : JAM1 laisse 2,
  JAM2 met 0, COMPLEMENT change 2 en 1).
- **Multicolore** (`AreaPtSz = −n`) : `2^n` mots **par plan**, plans consécutifs (plan 0 d'abord). Chaque
  plan reçoit **son** motif combiné avec le minterm de ce plan (bit du plan dans APen/BPen, DrawMode).
  T14, motifs plan 0 `$FF00,$FF00`, plan 1 `$F0F0,$0F0F` : en **APen = 3, BPen = 0, JAM2** les couleurs du
  motif sont reproduites telles quelles (ligne impaire : x 0..3 → 1, 4..7 → 3, 8..11 → 0, 12..15 → 2) ;
  en APen = 1, JAM1, seul le plan 0 est écrit (couleur 1 sur x 0..7 de chaque groupe de 16).
- **SetAfPt(rp, ptrn, n)** = macro qui affecte AreaPtrn et AreaPtSz. [D, en-têtes publics]

## 6. DrawEllipse (−180) — `(rp A1, cx D0, cy D1, a D2, b D3)` [D][O]

- Algorithme du **point milieu en deux régions** (arithmétique entière 32 bits, carrés des rayons sur 16
  bits signés), symétrie en 4 quadrants ; chaque point est posé par **WritePixel** appelé via l'adresse
  lue dans la table de saut de GfxBase (**SetFunction de WritePixel respecté**), donc découpé par la couche
  point par point. [D]
- Raccourci interne : RastPort **sans couche**, `minterms[0] = $6A`, bit 0 de Mask posé et BitMap à **1
  plan** → inversion directe des bits par le processeur après WaitBlit (cas du masque d'AreaEnd). [D]
- `ONE_DOT` dans `rp_Flags` : un seul point par ligne de balayage et par côté (usage AreaEnd). [D]
- Ne modifie pas `cp_x/cp_y`. Aucune valeur rendue. [D]
- Rayons nuls acceptés (T10) : (3,3,0,0) → le seul pixel (3,3) ; (9,3,1,0) → x 8..10 sur y 3 ;
  (15,3,0,1) → x 15 sur y 2..4 ; (22,3,3,0) → x 19..25 ; (28,4,0,3) → x 28 sur y 1..7. [O]
- Pixels exacts (T9 ; T10 pour (8,13,6,5) et (24,13,1,1)) : [O]

```
     00000000001111111111222222222233
     01234567890123456789012345678901
  1  ................111.....11111...      (3,3,1,1) (9,3,2,1) (17,3,3,2) (26,4,4,3)
  2  ...1....111...11...11..1.....1..
  3  ..1.1..1...1..1.....1.1.......1.
  4  ...1....111...11...11.1.......1.
  5  ................111...1.......1.
  6  .......................1.....1..
  7  ........................11111...
  8  ......................11111.....      (4,13,3,3) (13,13,4,4) (24,13,5,5)
  9  ............111......1.....1....
 10  ...111....11...11...1.......1...
 11  ..1...1...1.....1..1.........1..
 12  .1.....1.1.......1.1.........1..
 13  .1.....1.1.......1.1.........1..
 14  .1.....1.1.......1.1.........1..
 15  ..1...1...1.....1..1.........1..
 16  ...111....11...11...1.......1...
 17  ............111......1.....1....
 18  ......................11111.....

     (8,13,6,5), colonnes 0..15 :
  8  ......11111.....
  9  ....11.....11...
 10  ...1.........1..
 11  ...1.........1..
 12  ..1...........1.
 13  ..1...........1.
 14  ..1...........1.
 15  ...1.........1..
 16  ...1.........1..
 17  ....11.....11...
 18  ......11111.....
```

- (24,13,1,1) (T10) : (24,12), (23,13), (25,13), (24,14) — losange de 4 pixels, centre vide. [O]
- **AreaEllipse** remplit exactement l'intérieur de ce tracé, bord compris (T8 = T9 rempli ;
  T26 pour (16,10,8,6) : lignes 4 et 16 → x 13..19, 5/15 → 11..21, 6/14 → 10..22, 7/13 → 9..23,
  8..12 → 8..24). Rayons nuls (T31) : AreaEllipse(3,3,0,0) → le pixel (3,3) ; (10,3,3,0) → x 7..13 ;
  (20,3,0,2) → x 20 sur y 1..5. [O]
- `DrawCircle(rp, cx, cy, r)` = macro `DrawEllipse(rp, cx, cy, r, r)`. [D, en-têtes publics]

## 7. Flood (−330) — `success = Flood(rp A1, mode D2, x D0, y D1)` → D0

### 7.1 Aiguillage et valeur rendue [D][O]

1. **Avec couche** : `Layer.Lock` pris (sémaphore) pendant toute l'opération.
   - Couche **SuperBitMap** : SyncSBitMap, Flood sur la SuperBitMap via une copie du RastPort sans couche,
     puis CopySBitMap.
   - Sinon comme ci-dessous, mais le masque est dimensionné sur les **bornes de la couche**.
2. **TmpRas absente** : mode ≠ 0 → rend **0** sans rien faire (T20) ; mode 0 → **chemin lent** sans
   allocation (§7.4), rend **1** (T20 : résultat identique au chemin normal).
3. **TmpRas présente** : chemin normal (§7.2) ; rend **1**, ou **0** si l'allocation chip échoue (T32 :
   `TmpRas.Size = $F00000` → 0 dans les deux modes, rien de dessiné ; **pas de repli** sur le chemin lent).
4. Point de départ déjà sur la frontière (mode 0 sur AOlPen) : rien n'est fait, rend **1** (T21).
   Mode 1 avec APen égal à la couleur de départ : remplissage sans effet visible, rend 1 (T21). [O]

### 7.2 Chemin normal (TmpRas) [D]

- Couleur cible : mode 0 → `AOlPen` ; mode 1 → `ReadPixel(x, y)` (si −1, hors couche : rien n'est fait).
- Masque : un plan dans `TmpRas.RasPtr`, de dimensions `BytesPerRow × Rows` de la BitMap (sans couche) ou
  `RASSIZE(largeur, hauteur)` de la couche ; effacé (SetRast) avant usage.
- **Allocation chip** (`MEMF_CHIP|MEMF_PUBLIC`) d'un second plan de `TmpRas.Size` octets (sans couche) ou
  `RASSIZE` de la couche (avec couche), libéré à la fin après WaitBlit. **Exigence pratique : la TmpRas
  doit couvrir toute la BitMap (ou la couche), et la même quantité de chip doit être libre.** Une
  `TmpRas.Size` plus petite que le plan provoque un débordement (non sondé).
- Construction par blits **plan par plan** du plan « pixels de la couleur cible » (ET sur tous les plans
  de la profondeur d'origine) ; pendant ces blits, la ROM **modifie temporairement la BitMap de
  l'appelant** (`Depth = 1`, `Planes[0]` = plan courant) puis la restaure (copie de 40 octets). Une autre
  tâche dessinant dans la même BitMap pendant un Flood voit une BitMap à 1 plan. En mode 1, le plan est
  ensuite **inversé** : la frontière est « toute couleur différente de la cible ».
- Remplissage par **graine, ligne de balayage**, sur le masque : spans trouvés par lecture processeur,
  enregistrés en traçant des lignes horizontales (Move/Draw par LVO) dans le plan de résultat.
- Rendu final : **BltPattern(rp, résultat, 0, 0, largeur − 1, hauteur − 1, BytesPerRow)** sur toute la
  BitMap (ou la couche) : APen, BPen, DrawMode, motif et ClipRects s'appliquent (T21 : motif `$F0F0/$0F0F`
  appliqué au remplissage).

### 7.3 Comportement observé [O]

Scène : diagonale (0,0)–(19,19) et colonne x = 24 en couleur 1, îlot 2 × 2 de couleur 3 en (14,3) ;
Flood depuis (20,3), APen 2.

- **Mode 1** (T18) : la zone de couleur 0 à droite de la diagonale est remplie ; **l'îlot de couleur 3
  reste** ; la zone sous la diagonale (reliée seulement par les coins) **n'est pas atteinte** → **4-connexe**.
- **Mode 0** avec AOlPen = 1 (T19) : même zone, **l'îlot 3 est recouvert** (seule AOlPen arrête) ; pas de
  fuite par les coins.
- Losange fermé par 4 segments obliques (T33) : remplissage intérieur exact, aucune fuite.

```
T18 (mode 1)                          T19 (mode 0)
  0  1222222222222222222222221        0  1222222222222222222222221
  1  .122222222222222222222221        1  .122222222222222222222221
  2  ..12222222222222222222221        2  ..12222222222222222222221
  3  ...1222222222233222222221        3  ...1222222222222222222221
  4  ....122222222233222222221        4  ....122222222222222222221
  5  .....12222222222222222221        5  .....12222222222222222221
 ...                                 ...
 19  ...................122221       19  ...................122221
```

### 7.4 Chemin lent (mode 0 sans TmpRas) [D][O]

Même règle (frontière = AOlPen, 4-connexe), exécuté par le processeur pixel par pixel (ReadPixel) avec
tracé des spans directement dans le RastPort ; aucune allocation. Résultat identique au chemin normal sur
la scène T19/T20. [O]

## 8. RectFill (−306) avec contour [D][O]

- Sans `AREAOUTLINE` : `BltPattern(rp, NULL, xmin, ymin, xmax, ymax, 0)` (bornes inclusives, motif et
  stylos de BltPattern). [D]
- Avec `AREAOUTLINE` : intérieur rempli d'abord — en **COMPLEMENT**, le rectangle est **réduit d'un pixel
  de chaque côté** (rien si vide) pour ne pas inverser deux fois le bord ; sinon le rectangle entier — puis
  contour par **Move(xmin,ymin), Draw(xmin,ymax), Draw(xmax,ymax), Draw(xmax,ymin), Draw(xmin,ymin)** (LVO)
  avec FgPen = AOlPen et **JAM1**, minterms/FgPen/DrawMode restaurés ensuite. **cp reste en
  (xmin, ymin)**. [D][O] (T15 : cp = (2,2) ; rectangle (2,2)–(12,9) → bord 2, intérieur 1 ; en COMPLEMENT
  sur fond 3 avec contour, (18,3)–(27,8) → bord 2, intérieur (19..26, 4..7) à 0 ; sans contour,
  (18,11)–(27,16) → tout le rectangle à 0.)

## 9. WritePixel (−324) et ReadPixel (−318)

### 9.1 WritePixel — `(rp A1, x D0, y D1)` → D0 [D][O]

- **Sans couche** : **aucun contrôle de bornes** ; adresse = `y × BytesPerRow + (x >> 3)` (multiplication
  signée 16 bits). Observé (T22) : WritePixel(32, 0) sur une BitMap de 32 pixels écrit (0, 1) ;
  WritePixel(0, 20) avec 20 lignes écrit le plan **suivant** en mémoire. Rend **0** dans tous les cas.
- Écriture **au blitter**, un mot par plan dont le bit de `Mask` est posé, avec le minterm de
  `rp_minterms[plan]` (donc FgPen/BgPen/DrawMode) : COMPLEMENT inverse le pixel dans tous les plans du Mask
  (T22 : 2 → 1, 0 → 3). Pas d'attente finale. [D][O]
- **Avec couche** : `LockLayerRom` (LVO), coordonnées translatées par les bornes et le défilement de la
  couche, recherche du ClipRect : visible → écran ; caché avec BitMap de sauvegarde → dans cette BitMap
  (x relatif à `MinX & ~15`) ; caché sans sauvegarde (SIMPLE_REFRESH) ou hors de tout ClipRect et hors
  SuperClipRect → rend **−1** sans écrire ; SuperBitMap via la liste SuperClipRect. [D]

### 9.2 ReadPixel — `(rp A1, x D0, y D1)` → D0 [D][O]

- Attend la fin du blitter (WaitBlit), lit **au processeur** le bit du pixel dans les `Depth` plans et
  rend la couleur (0..2^Depth − 1). **Sans couche, aucun contrôle de bornes** (T22 : ReadPixel(32, 0) rend
  la couleur de (0, 1)). Avec couche : mêmes règles de recherche que WritePixel, **−1** si le pixel n'est
  pas lisible. [D][O]

## 10. Ce qui diffère sur un vrai A500

1. **TmpRas en chip obligatoire** (AreaEnd : BltClear, lignes et remplissage du blitter ; Flood : blits
   de construction du masque) ; la ROM ne vérifie rien. Une TmpRas en slow RAM (`$C00000`) est adressée
   tronquée par Agnus : le masque est écrit ailleurs en chip et le rendu est faux. Le tampon de sommets
   peut être n'importe où (processeur seul). [D]
2. **Flood alloue en plus `TmpRas.Size` octets de chip contigus** : sur 512 Ko de chip fragmentée
   (Workbench + écrans), l'allocation échoue plus tôt qu'en émulation généreuse → Flood rend 0 sans rien
   dessiner. [D][O pour le chemin d'échec]
3. Le remplissage du blitter (mode EFE descendant) et les lignes `ONE_DOT` sont des fonctions matérielles
   Agnus standard ; un émulateur qui implémente mal le **mode fill avec DESC** ou le bit **SING** des
   lignes produit des spans faux sur ce seul chemin. Les résultats de §4.8 sont la référence. [D]
4. Pas d'attente finale du blitter après AreaEnd (BltPattern) ni après WritePixel : un accès processeur
   aux plans doit être précédé de WaitBlit (ReadPixel attend lui-même). [D]
5. Flood est **lent** sur 68000 7 MHz (lecture processeur du masque, une ligne du blitter par span) ; la
   sonde ne mesure pas de temps. [D]

## 11. Sonde

`tests/garea_probe.s` (asset de test, code auteur) : tests T0–T33, une ligne d'en-tête par test (valeurs
rendues en hexadécimal, structures), puis 20 lignes `plan0 plan1`. Assemblage :
`vasmm68k_mot -Fhunkexe -kick1hunks -nosym -o build/garea_probe tests/garea_probe.s` ; exécution :
`tests/garea_probe.sh assets/kick34005.A500 build/garea_probe <sortie> 240`. Les schémas de ce document
sont le décodage de `serial.log`. Les tests T7 et T11 dépendent du **contenu résiduel** du tampon de
sommets (§4.7) et ne sont pas des vecteurs de référence pour un clone.

## Points non tranchés

1. **Chemins avec couche** (AreaEnd/Flood/WritePixel/ReadPixel dans une fenêtre, ClipRects cachés,
   SuperBitMap) : **déduits uniquement** ; la sonde n'utilise qu'un RastPort sans couche. En particulier
   l'origine du motif (coordonnées de couche ou d'écran) dans une couche n'est pas observée.
2. **Coordonnées négatives / hors BitMap dans AreaEnd** (x0 arrondi négatif, rendu sans couche non
   découpé) : déduit, non sondé (écriture hors tampon).
3. **TmpRas trop petite pour Flood** (allocation de `Size` octets puis copie d'un plan entier) et
   **TmpRas NULL pour AreaEnd** : débordement/corruption déduits, non sondés.
4. **Égalité exacte des arêtes d'AreaEnd avec Draw()** : les deux utilisent le tracé de ligne du blitter ;
   l'identité pixel à pixel n'a été vérifiée que sur des cas simples (T3, T25), pas comparée
   systématiquement à Draw.
5. **DrawEllipse en COMPLEMENT** avec un rayon nul (points symétriques confondus inversés deux fois ?) et
   grands rayons (débordement des produits 16 bits au-delà d'environ 180 pixels de rayon) : non sondés.
6. **AreaMove en échec de fermeture** (Count laissé incrémenté) : déduit, non observé.
7. Choix exact du **premier point omis** en passe 1 pour des arêtes consécutives de même sens séparées par
   une arête horizontale : déduit (l'arête horizontale ne change pas le sens mémorisé), non sondé.
8. **Temps** (AreaEnd, Flood) sur matériel réel ou WinUAE cycle-exact : non mesurés (sonde sous FS-UAE).
9. Contenu de D0 rendu par AreaEnd sur liste vide : indéfini ; les deux valeurs observées ne sont pas une
   règle.

## Relecture clean-room

- Aucune suite d'instructions de la ROM, aucun listing, aucune adresse de routine : seulement des LVO
  publics, des décalages de structures publiques (`rastport.h`), des valeurs de drapeaux, des ordres
  d'opérations et des pixels observés.
- Les schémas de pixels sont des **sorties** de la vraie ROM (vecteurs de test), pas du code.
