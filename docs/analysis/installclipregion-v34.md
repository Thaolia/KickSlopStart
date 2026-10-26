# installclipregion-v34.md — layers.library 34.1 : InstallClipRegion (spec comportementale)

> Piste ANALYSE (« dirty »). Source : ROM `kick34005.A500` (layers 34.1, intuition 34.3) lue sous
> radare2, plus une sonde boîte noire sur la vraie ROM sous FS-UAE (`tests/clipreg.s`, vecteurs §7).
> On décrit le **quoi** (effets observables, ordre, conditions, layout d'ABI), jamais le **comment** :
> aucune suite d'instructions transcrite, aucune adresse de routine.
>
> Légende : **[R]** analyse ROM (comportement) · **[S]** sonde boîte noire · **[D]** doc publique
> (NDK `layers_lib.fd`, AutoDocs) · **[R+S]** les deux concordent.

---

## 1. Existence et ABI

- `InstallClipRegion` **existe en V34** : c'est le **25ᵉ et dernier** vecteur utilisateur de
  layers.library 34.1, **LVO −174**, `InstallClipRegion(layer, region)(A0/A1)`, retour **D0 = ancienne
  région** (APTR, éventuellement NULL). La table de la 34.1 compte exactement les LVO −30..−174 (25
  fonctions, `InitLayers` … `MoveLayerInFrontOf`, `InstallClipRegion`) ; `MoveSizeLayer` (−180) et
  suivantes n'existent pas en 1.3. **[R ; D pour les noms]**
- Pas de vérification des arguments : `layer` doit être valide (pas de test NULL) ; `region` NULL = retrait.
  **[R]**

### 1.1 Champs d'ABI impliqués (offsets V34)

`struct Layer` (publique, `graphics/clip.h` 1.3) **[R : offsets lus aux accès ; D]** :

| Off. | Champ | Rôle ici |
|---:|---|---|
| `$08` | `ClipRect` | liste **courante** des ClipRects (celle que graphics parcourt pour dessiner) |
| `$0C` | `rp` | RastPort de la couche (sa `BitMap->Depth` sert à allouer les tampons cachés, §3.3) |
| `$10..$17` | `bounds` (MinX, MinY, MaxX, MaxY) | origine des coordonnées de la région (§2) |
| `$1E` | `Flags` (UWORD) | `LAYERUPDATING $0010` (BeginUpdate), `LAYER_CLIPRECTS_LOST $0100` (échec mémoire, §3.5) |
| `$2C/$2E` | `Scroll_X/Scroll_Y` | **ignorés** par la région (§2) ; intuition les met à 0 pendant ses dessins (§5) |
| `$40` | `_cliprects` (privé) | **sauvegarde** de la liste « normale » pendant qu'une liste réduite est en place |
| `$44` | `LayerInfo` | |
| `$48` | `Lock` (SignalSemaphore, 46 octets) | verrou de couche |
| `$7E` | **`ClipRegion`** | la région installée (pointeur de l'appelant, **non copiée**) |
| `$82` | `saveClipRects` (privé) | mis à NULL pour chaque couche au premier `LockLayers` (§4.2) ; pas d'autre usage observé |
| `$9C` | `DamageList` | région de dommages (BeginUpdate) |

`struct ClipRect` (40 octets alloués) : `Next $00`, `prev $04`, `lobs $08`, `BitMap $0C`, `bounds $10`
(coordonnées **écran**, i.e. du BitMap de la LayerInfo), privés `$18..$27`. `struct Region` : `bounds $00`
(8 octets), `RegionRectangle $08` ; `struct RegionRectangle` : `Next $00`, `Prev $04`, `bounds $08`
(relatif à `Region.bounds.MinX/MinY`). **[D ; R pour l'usage]**

---

## 2. Coordonnées

- La région est exprimée en **coordonnées de la couche** : le pixel (0,0) de la région est le coin
  `bounds.MinX/MinY` de la couche. Un rectangle de région `rr` donne en coordonnées écran
  `layer.MinX + region.bounds.MinX + rr.bounds.MinX` (idem Y, et pour Max). **[R+S]** (T1 : rect (10,10)-(29,19)
  d'une couche en (100,50) ⇒ ClipRect écran (110,60)-(129,69)).
- `Scroll_X/Scroll_Y` ne sont **pas** appliqués (en 1.3 ils ne concernent que les couches superbitmap). **[R]**
- La région peut déborder de la couche : seule l'intersection avec la couche compte (§3.1). **[R+S]** (T5).

---

## 3. Sémantique

### 3.1 Effet de `InstallClipRegion(layer, region)` **[R ; S pour les cas visibles]**

Sous le verrou de la couche (`LockLayerRom`/`UnlockLayerRom` de graphics, réentrant) :

1. `old = layer->ClipRegion`.
2. Si `old ≠ NULL` : la liste réduite actuelle est **défaite** (§3.4) et la liste normale restaurée.
3. `layer->ClipRegion = region`.
4. Si `region ≠ NULL` : une **liste réduite** est construite (§3.2) et devient `layer->ClipRect`.
5. Déverrouillage ; retour `old`.

Conséquences :
- `InstallClipRegion(l, NULL)` sans région installée ne fait rien d'observable (retour NULL). **[R+S]**
- Réinstaller la même région (`Install(l, r)` puis `Install(l, r)`) renvoie `r` et **reconstruit** la liste :
  c'est la seule façon de faire prendre en compte une **modification de la région après installation**
  (la liste réduite est un instantané ; graphics ne relit jamais la région). **[R+S]** (T2).
- Le pointeur `region` est conservé tel quel ; layers ne la libère jamais (c'est à l'application de la
  retirer avant `DisposeRegion` / `CloseWindow`). **[R]**

### 3.2 Construction de la liste réduite **[R ; S pour la partie visible]**

La liste normale (`layer->ClipRect`) est rangée dans `_cliprects` (`$40`) et `layer->ClipRect` repart vide.
Soit `C` la région de découpe :
- hors BeginUpdate : `C = ClipRegion` ;
- pendant BeginUpdate (`LAYERUPDATING`) : `C = DamageList ∩ ClipRegion` (copie temporaire, détruite à la fin) ;
  sans ClipRegion : `C = DamageList` (comportement normal de BeginUpdate).

Si `C` n'a **aucun rectangle** : la couche reste **sans aucun ClipRect** (`layer->ClipRect = NULL`) ⇒ tout
dessin dans la couche est sans effet. **[R+S]** (T4 : `ClipRect = 00000000`, pixel inchangé).

Sinon, deux régions sont calculées à partir de la liste normale (en coordonnées couche) :
- **V** = union des ClipRects **visibles** (`lobs == NULL`) ;
- **O** = union des ClipRects **cachés avec tampon** (`lobs ≠ NULL` **et** `BitMap ≠ NULL`, i.e. les
  parties cachées d'une couche smart/superbitmap). Les parties cachées sans tampon (couche simple) ne sont
  pas reprises : y dessiner reste sans effet, comme sans région.

Puis :
1. pour chaque rectangle de `V ∩ C` : un ClipRect visible (`lobs = NULL`, `BitMap = NULL`), bornes écran ;
2. pour chaque rectangle de `O ∩ C` : un ClipRect « caché » avec `lobs = 1` (valeur sentinelle non nulle,
   pas un pointeur de couche) et un **tampon BitMap propre** de la profondeur du `rp->BitMap` de la couche,
   aligné sur 16 pixels comme les tampons smart ; son contenu est **recopié depuis le(s) tampon(s) d'origine**
   qui le recouvrent (BltBitMap, minterm `$CA`, masque `$FF`).
Les ClipRects sont pris dans la LayerInfo ; les tampons des ClipRects cachés sont alloués **hors** de la
comptabilité de la LayerInfo (MEMF_CLEAR). Les régions temporaires V, O (et la copie DamageList ∩ ClipRegion)
sont libérées à la fin. **[R]**

### 3.3 Dessin pendant qu'une région est installée **[R+S]**

graphics dessine à travers `layer->ClipRect` comme d'habitude : il n'y a **aucun cas particulier** dans
graphics. Donc :
- les pixels visibles hors `C` ne sont **pas** modifiés ; ceux dans `V ∩ C` le sont (T1, T6) ;
- les dessins dans des parties cachées d'une couche smart, dans `C`, vont dans les tampons propres de la
  liste réduite et sont **reportés** dans les tampons d'origine au retrait (§3.4).

### 3.4 Retrait de la liste réduite **[R]**

Pour chaque ClipRect caché de la liste réduite (`lobs ≠ NULL`), son contenu est recopié (BltBitMap `$CA`,
masque `$FF`) dans **le premier** ClipRect caché de la liste normale sauvegardée dont les bornes le recouvrent.
Puis la liste réduite est libérée (ClipRects rendus à la LayerInfo, tampons libérés), `layer->ClipRect =
_cliprects`, `_cliprects = NULL`.

### 3.5 Mémoire insuffisante **[R uniquement]**

Si une allocation échoue pendant la construction, la construction s'arrête (liste réduite partielle laissée
en place) et `layer->Flags |= LAYER_CLIPRECTS_LOST ($0100)`. InstallClipRegion n'en informe pas l'appelant
(il renvoie toujours l'ancienne région).

---

## 4. Interactions

### 4.1 BeginUpdate / EndUpdate **[R]**

- **BeginUpdate(l)** : verrouille la couche (et la **laisse verrouillée** jusqu'à EndUpdate) ; si une
  ClipRegion est installée, défait d'abord sa liste réduite ; pose `LAYERUPDATING` ; construit la liste
  réduite avec `C = DamageList ∩ ClipRegion` (ou `DamageList` seule sans ClipRegion). Le dessin d'un refresh
  est donc limité **à la fois** aux dommages et à la région.
- **EndUpdate(l, flag)** : si `flag ≠ 0`, `ClearRegion(DamageList)` ; défait la liste réduite (§3.4) ;
  efface `LAYERUPDATING` ; **si une ClipRegion est installée, reconstruit sa liste** (`C = ClipRegion`) ;
  déverrouille.
- Appeler InstallClipRegion **entre** BeginUpdate et EndUpdate reconstruit avec `DamageList ∩ nouvelle région`
  (le drapeau UPDATING est encore posé) ; le retrait par NULL donne `C = DamageList`.

### 4.2 Opérations de couches (Create*, Upfront, Behind, Move, Size, Delete, MoveLayerInFrontOf) **[R ; S Move]**

Toutes ces fonctions encadrent leur travail par `LockLayers(li)` … `UnlockLayers(li)` (verrou de toutes les
couches de la LayerInfo). layers.library utilise ce verrou global pour neutraliser les régions :
- **au premier niveau** de LockLayers (compteur `LayerInfo+$5B` passant à 1) : pour **chaque couche** de la
  LayerInfo (de `top_layer` vers l'arrière), `saveClipRects := NULL`, et si `ClipRegion ≠ NULL`, sa liste
  réduite est défaite (§3.4) ⇒ l'opération travaille sur les listes normales ;
- **au dernier** UnlockLayers (compteur revenant à 0) : pour chaque couche ayant une `ClipRegion`, la liste
  réduite est **reconstruite** sur le nouvel arrangement (§3.2).
Effets : la région suit la couche (coordonnées couche) après Move/Size ; les parties nouvellement cachées ou
découvertes sont reprises ; une application qui appelle elle-même LockLayers voit les listes normales tant
qu'elle tient ce verrou. `ScrollLayer` ne passe pas par ce mécanisme. **[R]** Vecteur T6 : après
`MoveWindow(+20,+10)` la région installée reste `ClipRegion` et le ClipRect réduit est translaté. **[S]**
- `DeleteLayer` d'une couche ayant encore une ClipRegion : la région n'est **pas** libérée (elle appartient à
  l'application). **[R]**

### 4.3 Avec LockLayer / LockLayerInfo seuls

Pas d'effet sur la région (seul LockLayers la neutralise). **[R]**

---

## 5. Qui l'utilise en 1.3 **[R]**

- Dans toute la ROM, **seule intuition** appelle InstallClipRegion (un seul point d'appel vers le vecteur
  −174, via la base layers rangée dans IntuitionBase `+$68`). console.device, graphics, workbench.task,
  dos ne l'appellent pas.
- Usage d'intuition : autour de **tous ses dessins internes dans une fenêtre** (cadre, gadgets système et
  applicatifs, knob des gadgets proportionnels, etc. — une quinzaine d'appelants) intuition :
  1. verrouille la couche (`LockLayerRom` de graphics) et prend son verrou interne ;
  2. `ancienne = InstallClipRegion(couche, NULL)` (mémorisée dans IntuitionBase, privé) ;
  3. sauvegarde `Scroll_X/Scroll_Y` de la couche et les met à 0 ;
  4. dessine ; puis restaure `Scroll_X/Y`, `InstallClipRegion(couche, ancienne)`, déverrouille.
  Donc : **les dessins d'intuition ignorent la ClipRegion de l'application**, et intuition appelle
  InstallClipRegion **même quand aucune région n'est installée** (appel neutre, §3.1). Une implémentation
  d'intuition peut s'en passer si elle n'a pas de ClipRegion à neutraliser, mais dès qu'une application en
  installe une, l'absence de ce retrait ferait découper les gadgets/cadres par la région de l'application.
- Le Workbench 1.3 n'utilise **pas** InstallClipRegion. Ses fenêtres de tiroir/disque ne sont **pas**
  GIMMEZEROZERO (Flags $0240027F / $0200027F, SIMPLE_REFRESH) : il découpe ses icônes au rectangle de contenu
  en **remplaçant (ou réduisant) la `DamageList` de la couche par ce rectangle, puis BeginUpdate/EndUpdate**
  (cf. `wb-icon-clipping-v34.md`). Seule la fenêtre de info.library est GIMMEZEROZERO.

Ce qui casse sans InstallClipRegion : les applications tierces (éditeurs, jeux/outils « system-friendly »,
programmes de dessin) qui l'appellent obtiennent un saut vers un vecteur absent ; et, si on l'implémente
sans la neutralisation par intuition, le rendu des gadgets dans ces fenêtres.

---

## 6. Résumé pour l'implémentation

1. LVO −174, A0 = couche, A1 = région ou NULL, D0 = ancienne. Verrou de couche.
2. Liste réduite = (visibles ∩ C) + (cachés-avec-tampon ∩ C, tampons propres recopiés à l'aller et au retour),
   `C` = ClipRegion, ou DamageList ∩ ClipRegion pendant BeginUpdate ; région vide ⇒ aucun ClipRect.
3. Coordonnées de région = coordonnées couche (origine `bounds.MinX/MinY`), Scroll ignoré.
4. Instantané : modifier la région impose de la réinstaller.
5. BeginUpdate/EndUpdate et LockLayers/UnlockLayers (donc toutes les opérations de pile) défont et
   reconstruisent la liste réduite.
6. intuition retire la région (et annule Scroll_X/Y) pendant ses propres dessins.

---

## 7. Vecteurs de test (vraie ROM 34.5, FS-UAE 3.2.35)

Sonde `tests/clipreg.s` (copie de l'ADF WB 1.3.3, lancée par `clipreg >SER:` depuis la startup-sequence ;
`slow_memory = 512`). Fenêtre BORDERLESS|ACTIVATE smart, en (100,50), 100×50, entièrement visible ; couche
⇒ bounds écran (100,50)-(199,99). R1 = {(10,10)-(29,19)} en coordonnées couche. Pixels relus dans le
RastPort de l'écran (`P x y pen`, hexadécimal). `CR minX minY maxX maxY lobs BitMap`.

```
T0 00000000                         ClipRegion initiale = NULL
CR 0064 0032 00C7 0063 00000000 00000000      liste normale : 1 ClipRect = toute la couche
T1 00000000 00C05B60                Install(R1) rend NULL ; layer+$7E = R1
CR 006E 003C 0081 0045 00000000 00000000      liste réduite = R1 + (100,50) = (110,60)-(129,69)
P 0069 0037 00000000                (105,55) hors région : intact
P 0073 0041 00000001                (115,65) dans : pen 1
P 0081 0045 00000001                (129,69) coin bas-droit inclus
P 0082 0046 00000000                (130,70) juste dehors : intact
T2                                  OrRectRegion(R1, (50,30)-(59,39)) SANS réinstaller, remplissage pen 2
P 0073 0041 00000002
P 009B 0055 00000000                (155,85) : non dessiné ⇒ la liste réduite est un instantané
00C05B60                            Install(R1) à nouveau : rend R1
CR 0096 0050 009F 0059 00000000 00000000      (150,80)-(159,89)
CR 006E 003C 0081 0045 00000000 00000000
P 0073 0041 00000002
P 009B 0055 00000002                maintenant dessiné
T3 00C05B60 00000000                Install(NULL) rend R1 ; layer+$7E = NULL
CR 0064 0032 00C7 0063 00000000 00000000      liste normale restaurée
P 0069 0037 00000000 … (tout pen 0 après remplissage pen 0)
T4 00000000 00000000                région vide : Install rend NULL ; layer->ClipRect = NULL
P 0069 0037 00000000 / 0073 0041 00000000 / … remplissage pen 1 sans effet
T5                                  région (-20,-20)-(200,200) débordante
CR 0064 0032 00C7 0063 00000000 00000000      bornée à la couche
T6                                  Install(R1 modifiée) puis MoveWindow(+20,+10), Delay 1 s
L 0078 003C 00C05B60                couche en (120,60), ClipRegion toujours R1
CR 00AA 005A 00B3 0063 00000000 00000000      (50,30)-(59,39) + (120,60) = (170,90)-(179,99)
CR 0082 0046 0095 004F 00000000 00000000      (10,10)-(29,19) + (120,60) = (130,70)-(149,79)
P 007D 0041 00000000                (125,65) hors région
P 0087 004B 00000003                (135,75) dans
P 0095 004F 00000003                (149,79) coin inclus
P 0096 0050 00000000                (150,80) dehors
```
Non-régression proposée : reproduire ces lignes (adresses de région exceptées).

---

## 8. Non sondé / incertain

- Parties **cachées** d'une couche smart sous région (tampons propres, recopie aller/retour) : ROM seulement ;
  la sonde n'a qu'une couche entièrement visible.
- Couches **superbitmap** : le traitement des parties cachées suppose que leurs ClipRects cachés portent un
  BitMap (§3.2) ; non vérifié.
- Interaction BeginUpdate/EndUpdate avec une région installée : ROM seulement (pas de dommages
  déterministes dans la sonde).
- Échec mémoire (`LAYER_CLIPRECTS_LOST`) : ROM seulement.
- Ordre des ClipRects dans la liste réduite : non normatif (graphics n'en dépend pas).

---

## Relecture clean-room

- [x] Aucune suite d'instructions transcrite ni paraphrasée ; aucune adresse de routine ROM (seuls des
  offsets de structures publiques/privées, des constantes d'ABI et des plages matérielles).
- [x] Les sondes citées sont du code auteur (`tests/`, en-tête « ASSET DE TEST, PAS du code ROM »).
