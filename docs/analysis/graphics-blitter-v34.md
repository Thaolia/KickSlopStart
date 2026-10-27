# graphics.library 34.1 — opérations blitter : spec comportementale

> Piste **ANALYSE** (« dirty »). Sources : ROM `assets/kick34005.A500` (lecture seule, radare2, base
> `$FC0000` ; notes de désassemblage hors dépôt) et sonde boîte noire `tests/gblit_probe.s`
> (harnais `tests/gblit_probe.sh`) exécutée sur la **vraie ROM** sous FS-UAE (A500 PAL, 512 Ko chip +
> 512 Ko slow, boot DOS sur une disquette dont la startup-sequence lance la sonde).
> Ce document décrit des **comportements**, des **valeurs**, des **ordres d'opérations** et des
> **layouts d'ABI**. Il ne contient aucune suite d'instructions de la ROM ni adresse de routine.
> Il complète, sans les répéter : `fastfonts-ff.md` (contrat de BltTemplate vu de FastFonts),
> `installclipregion-v34.md` (sauvegarde des ClipRects par BltBitMap), `timer-v34.md` §6 (alarme TOD
> de la CIA-B utilisée par QBSBlit), `wb-icon-clipping-v34.md` §3 (usage des icônes).
>
> **Niveaux de preuve** : **[O]** observé par la sonde sur la vraie ROM · **[D]** déduit de la lecture
> du code de la ROM (comportement, pas de code) · **[S]** supposition raisonnable, non vérifiée.

## 0. Résumé pour l'implémenteur

- Le cœur est **BltBitMap** : un **descripteur de 28 octets par plan** est préparé (au plus 8, sur la
  pile), puis la fonction prend le blitter par le **LVO OwnBlitter**, programme les plans **un par un en
  attendant BBUSY entre chaque**, et rend le blitter par le **LVO DisownBlitter** **sans attendre la fin
  du dernier plan** (sauf si elle a dû allouer un tampon temporaire). [D]
- **Seul le quartet haut du minterm compte** (fonction de B = source et C = destination) ; le quartet
  bas est remplacé par `$A` : le canal A sert de **masque de bord** (BLTADAT = `$FFFF` ou ligne de
  masque en mémoire), et hors masque la destination est recopiée telle quelle. [D][O]
- Le **recouvrement** est traité exactement lorsque source et destination ont le **même BytesPerRow**
  (critère : comparaison des BytesPerRow et des adresses, pas de l'identité des BitMap) : six schémas de
  parcours (§1.4), dont deux utilisent une **ligne de masque en chip RAM** (TempA, 128 octets alloués si
  l'appelant n'en fournit pas). [D][O]
- **Aucune validation** des arguments dans BltBitMap/BltTemplate (sans couche) : pas de clipping aux
  bornes de la BitMap, pas de test des plans `NULL`/`-1` (ils sont traités comme des adresses), largeur
  ou hauteur nulle = **blit maximal** du matériel (64 mots / 1024 lignes). [D][O]
- Les fonctions « RastPort » (BltBitMapRastPort, ClipBlit, BltMaskBitMapRastPort, BltTemplate,
  BltPattern) découpent par les **ClipRects** de la couche et appellent **BltBitMap par son LVO** (donc
  sensibles à SetFunction) une fois par morceau visible ou sauvegardé. [D]
- File de blits : **QBlit** appelle la fonction **immédiatement, dans le contexte de l'appelant**, si
  le blitter est libre ; sinon le nœud est chaîné et l'interruption BLIT (niveau 3) déroule la file.
  **QBSBlit n'attend le faisceau que si `gb_VBlank ≠ 0` ou si un blit synchronisé est déjà en attente** ;
  sinon il se comporte comme QBlit. [D][O]

## 1. BltBitMap (LVO −30)

### 1.1 Contrat d'appel

`planes = BltBitMap(srcBM A0, srcX D0, srcY D1, dstBM A1, dstX D2, dstY D3, sizeX D4, sizeY D5,
minterm D6, mask D7, TempA A2)`, A6 = GfxBase. Seuls les **mots bas** de D0–D6 et l'**octet bas** de D7
sont utilisés. Registres conservés : D2–D7/A2–A6 (A0/A1/D1 détruits). [D]

**Valeur rendue (D0, long)** : le **nombre de plans effectivement blittés**, c'est-à-dire
`min(srcBM.Depth, dstBM.Depth)` moins les plans dont le bit de `mask` est à 0. Rend **0 sans rien
faire** (ni prise du blitter, ni attente) si l'une des deux profondeurs vaut 0 ou si l'octet `mask`
vaut 0. Plans parcourus de 0 vers le haut ; le bit *i* de `mask` sélectionne le plan *i*. [D]
Observé : profondeurs 3→3, masque `$05` → 2 ; masque `$00` → 0 ; profondeurs 2→3, masque `$FF` → 2 ;
3→3, `$FF` → 3. [O]

### 1.2 Arguments non validés

- **Pas de clipping** aux dimensions de la BitMap (`Rows`, `BytesPerRow`) ; coordonnées et tailles sont
  converties en adresses par décalages **non signés** (un X négatif devient une très grande valeur).
  L'adresse de ligne utilise une multiplication **signée 16 bits** `y × BytesPerRow`. [D]
- **Plans `NULL` ou `-1`** : aucun traitement particulier en V34 (la convention « plan à 0 = tout à 0,
  plan à −1 = tout à 1 » n'existe pas encore) ; le pointeur est utilisé comme adresse de plan. [D]
- **sizeY = 0** : le champ hauteur de BLTSIZE vaut 0, soit **1024 lignes** pour le matériel. Observé :
  BltBitMap(…, 16 × 0) entre deux BitMap de BytesPerRow 2 a écrit **1024 lignes**. [O]
- **sizeX = 0** : le nombre de mots calculé vaut 0 si dstX est multiple de 16 (BLTSIZE largeur 0 =
  **64 mots**, masques `$FFFF`), donc 128 octets écrits par ligne. Observé : à x = 16, 64 mots écrits
  sur la ligne. Si dstX n'est pas multiple de 16, un mot est traité avec un masque nul (aucun effet
  visible). Si dstX = 0, le calcul déborde (largeur « −1 » en non signé) et **corrompt le champ hauteur**
  de BLTSIZE avec un modulo aberrant : **écriture hors de la BitMap**. [D][O]
- **Largeur > 1008 pixels environ** (> 64 mots, ou > 62 mots dans les schémas à mot supplémentaire) et
  **hauteur > 1024** : débordent des champs de BLTSIZE (limite OCS), sans contrôle. [D]
- **Négatifs** : sizeX/sizeY négatifs ne sont pas rejetés (même effet de débordement). [D]

Le **contrat à respecter** par un appelant correct est donc : 1 ≤ sizeX ≤ 1008 (ou moins selon le
schéma), 1 ≤ sizeY ≤ 1024, rectangles entièrement dans les BitMap. Une implémentation compatible peut
rejeter les cas dégénérés (rendre 0) sans casser de logiciel connu ; elle ne doit pas les « réparer »
autrement. [S]

### 1.3 Programmation du blitter (commune à tous les schémas)

Canaux : **A = masque** (constante `$FFFF` dans BLTADAT, sauf schémas à tampon), **B = source**,
**C = D = destination** (même pointeur, même modulo). BLTCON0 = `USEB|USEC|USED` (+ `USEA` pour les
schémas à tampon) | `(minterm & $F0)` | `$0A` | décalage ASH ; BLTCON1 = décalage BSH (+ `DESC`).
Le quartet `$0A` signifie : là où A = 0 (hors masque), D = C. [D]

Observé avec source `$FF00`, destination `$F0F0`, 16 × 1 : minterm `$C0`, `$CF`, `$C5` → tous
`$FF00` ; `$60` et `$6A` → tous deux `$0FF0` (B xor C) ; `$30` → `$00FF` ; `$0A` → `$0000`. Le
quartet bas est donc **ignoré** et le minterm `$0A` (« garder C » au sens matériel) donne **0** : en V34,
la fonction est entièrement définie par le quartet haut, un quartet haut nul efface la zone. [O]

Masques de bord (tables de 16 mots) : premier mot = `$FFFF >> (x & 15)` ; dernier mot =
`$FFFF << (15 − ((x + w − 1) & 15))`, calculés en coordonnées **destination** dans les schémas
ascendants et en coordonnées **source** dans les schémas descendants (où A est décalé du même ASH que
B). [D]

**Ordre d'écriture des registres pour chaque plan**, après une attente BBUSY : BLTCON0+BLTCON1 (un
long), BLTAFWM+BLTALWM (un long), puis soit BLTAPT + BLTAMOD (tampon), soit BLTADAT = `$FFFF` ; puis
BLTBPT, BLTBMOD, BLTCPT, BLTDPT, BLTCMOD, BLTDMOD, et **BLTSIZE en dernier** (démarre le blit). [D]

**Séquence d'ensemble** : préparation de tous les descripteurs (éventuel remplissage du tampon de
masque au processeur) → **OwnBlitter par son LVO** → pour chaque plan : attente BBUSY puis
programmation → **DisownBlitter par son LVO** juste après le BLTSIZE du dernier plan. Si un tampon a été
alloué par la fonction : attente BBUSY, puis libération. **Pas d'attente finale sinon** : l'appelant qui
veut lire ou écrire la destination au processeur doit appeler WaitBlit. [D]

### 1.4 Choix du sens de parcours et recouvrement

Notations : `S` = adresse du premier mot source de la première ligne, `D` idem destination,
`sx = srcX & 15`, `dx = dstX & 15`. Quatre parcours sont obtenus en combinant le mode ascendant/
descendant du blitter (sens dans la ligne) et le **signe des modulos** (sens des lignes : un modulo
« négatif » de −(BytesPerRow + largeur) fait progresser à l'inverse du mode). [D]

| Cas | Condition | Mode | Décalage | Lignes | Départ |
|---|---|---|---|---|---|
| P1 | même BPR, D < S, dx ≥ sx | ascendant | B décalé à droite de dx−sx | haut → bas | coin haut-gauche |
| P2 | (BPR différents, dx ≥ sx) ou (même BPR, D ≥ S, dx > sx, D au-delà du dernier mot source de la ligne) | ascendant | dx−sx | **bas → haut** | coin bas-gauche |
| P3 | même BPR, D ≥ S, dx ≤ sx | descendant | B et A décalés à gauche de sx−dx | bas → haut | coin bas-droit |
| P4 | (BPR différents, dx < sx) ou (même BPR, D < S, dx < sx, dernier mot destination de la ligne avant S) | descendant | sx−dx | **haut → bas** | coin haut-droit |
| P5 | même BPR, D < S, dx < sx, dernier mot destination de la ligne ≥ S (glissement à gauche dans la même ligne) | ascendant + **canal A en mémoire** | (dx−sx) & 15, destination commencée **un mot plus tôt** | haut → bas | |
| P6 | même BPR, D ≥ S, dx > sx, D ≤ dernier mot source de la ligne (glissement à droite dans la même ligne) | descendant + **canal A en mémoire** | (sx−dx) & 15, un mot de plus à droite | haut → bas | |

Largeur en mots : P1/P2 = étendue en mots de la **destination** ; P3/P4 = étendue de la **source** ;
P5/P6 = étendue destination **+ 2**. [D]

P5/P6 exigent une **ligne de masque** de (étendue destination + 2) mots. P5 : un mot nul, le masque de
premier mot (`$FFFF >> dx`), des `$FFFF`, le dernier mot ET-é avec le masque de fin. P6 : le masque de
premier mot, des `$FFFF`, le dernier mot ET-é avec le masque de fin, puis un mot nul. Observé : glissement
de 2 → 5 sur 40 px : `07FF FFFF FFF8 0000` ; 20 → 3 sur 30 px : `0000 1FFF FFFF 8000` ; 3 → 20 :
`0FFF FFFF C000 0000` (le 4ᵉ mot, nul, est le mot final). [O] Elle est lue par le canal A avec un modulo négatif égal
à sa longueur (la même ligne est relue pour chaque ligne). Elle est écrite au processeur **une seule fois
par appel** (le premier plan concerné), dans :
- **TempA** (A2) si l'appelant le fournit — après une attente BBUSY ;
- sinon un bloc de **128 octets** `MEMF_CHIP` alloué par la fonction (une fois par appel), libéré en fin
  d'appel après une attente BBUSY. En cas d'échec d'AllocMem, repli sur le tampon de dernier recours
  `gb_LCMptr` (§7). [D]

Conséquence : 128 octets limitent ces deux schémas à 62 mots + 2 ; au-delà la ligne de masque déborde du
bloc. Aucun autre cas n'utilise TempA. [D]

Vérification [O] (`gblit_probe`, BitMap 64 × 4, BytesPerRow 8, motif d'octets `11 + 37 i`, minterm
`$C0`, TempA pré-rempli de `$DEAD`) : les 14 déplacements testés (gauche/droite de 3, 17, 16 pixels dans
la même ligne, haut/bas d'une ligne avec et sans décalage, diagonales) donnent **exactement** le
résultat d'une copie « memmove » calculée sur l'hôte ; TempA n'est modifié que pour les glissements
horizontaux où les adresses de mot diffèrent (P5/P6 : 2 → 5, 20 → 3, 3 → 20) — **pas** pour 5 → 2
(même mot de départ, D = S : schéma P3 descendant, sans tampon) ; avec TempA = NULL le résultat est
identique (tampon interne) ; aucun octet de garde (16 octets de part et d'autre) n'est modifié. [O]

## 2. WaitBlit (LVO −228)

Lit **deux fois** le bit BBUSY (bit 14 de DMACONR) — la première lecture absorbe le défaut d'Agnus
ancien, qui peut montrer BBUSY = 0 juste après l'écriture de BLTSIZE — puis, si occupé, reboucle sur la
lecture jusqu'à BBUSY = 0. Ne touche aucun registre (hormis CCR), n'utilise ni A6 ni la pile en dehors
du retour, **ne prend pas le blitter**, ne teste pas BLTEN/DMAEN (si le DMA blitter est coupé pendant un
blit, WaitBlit boucle indéfiniment). Appelable depuis une interruption. [D]

Toute la bibliothèque utilise la même **double lecture** avant chaque programmation de registres
(BltBitMap, BltTemplate, BltClear, file QBlit, DisownBlitter). C'est le point « vrai A500 » n°1 :
une implémentation qui ne teste BBUSY qu'une fois immédiatement après BLTSIZE peut réécrire les
registres d'un blit en cours. [D]

## 3. OwnBlitter (−456) / DisownBlitter (−462)

État dans GfxBase (layout public `graphics/gfxbase.h`) : `BlitLock` (WORD, $AA) = **compteur de
demandeurs − 1** (`−1` = libre, initialisé à −1), `BlitWaitQ` (List, $AE) = tâches en attente,
`Flags` ($A8, WORD) : bit 1 = **le blitter appartient à la file QBlit**, bit 2 = **passation en attente**
(privés). `BlitNest` ($AC) initialisé à −1, non utilisé par ces fonctions. **`BlitOwner` ($BC) n'est jamais
écrit en V34.** [D] Observé : BlitLock = `$FFFF` avant, `$0000` après OwnBlitter, `$FFFF` après
DisownBlitter ; BlitOwner = 0 ; `Flags` = 0 après. [O]

**OwnBlitter** : incrémente BlitLock ; si le résultat est 0, rend immédiatement (chemin rapide : ni
Disable, ni Forbid, registres tous conservés). Sinon, sous Disable : si le drapeau « passation en
attente » est mis, il est effacé et la tâche est propriétaire ; sinon la tâche place sur sa pile un nœud
de 16 octets (le pointeur de tâche dans le champ `ln_Name`), efface le signal **SIGF_BLIT (bit 4,
`$10`)**, s'ajoute en queue de BlitWaitQ et fait `Wait($10)` ; Enable. **Non imbriquable** : un second
OwnBlitter de la même tâche se bloque pour toujours. **N'attend pas** la fin d'un blit en cours (faire
WaitBlit avant d'écrire les registres). Registres D0/D1/A0/A1 conservés. [D]

**DisownBlitter** : décrémente BlitLock ; si le résultat est négatif (personne d'autre), rend
immédiatement. Sinon, sous Disable : si la file QBlit ou la file synchronisée n'est pas vide, le
blitter est donné à la file (drapeau bit 1), l'interruption BLIT est autorisée (INTENA SET|BLIT) et, si
le blitter est déjà au repos, **provoquée** (INTREQ SET|BLIT) ; sinon la première tâche de BlitWaitQ est
retirée et reçoit `Signal(task, $10)` ; si la liste est vide (demandeur entre son incrément et son
AddTail), le drapeau « passation en attente » est mis. Enable. Un DisownBlitter **non apparié** amène
BlitLock à −2 et le prochain OwnBlitter attend indéfiniment. [D]

Priorité : **les blits de la file QBlit passent avant les tâches en attente** à chaque DisownBlitter. [D]

## 4. BltClear (LVO −300)

`BltClear(memBlock A1, byteCount D0, flags D1)`. Prend le blitter **en interne** (même protocole que
OwnBlitter mais sans passer par le LVO), attend BBUSY, programme BLTCON1 = 0, BLTDMOD = 0,
BLTCON0 = `$0100` (D seul, minterm 0), BLTDPT = memBlock, puis un ou plusieurs BLTSIZE ; rend le
blitter (protocole DisownBlitter interne). Rien n'est rendu (D0 indéfini). [D]

- **flags bit 0** : attendre la fin du dernier blit avant de rendre. Sinon retour pendant l'effacement.
- **flags bit 1** : D0 = `(lignes << 16) | octetsParLigne`. Si octetsParLigne ≤ 128 : **un seul blit**
  hauteur = lignes, largeur = octetsParLigne / 2 ; le nombre de lignes est pris **modulo 1024** (0 =
  1024) sans contrôle. Si octetsParLigne > 128 : le produit lignes × octetsParLigne (16 × 16 bits) est
  traité en mode linéaire.
- **Mode linéaire** (bit 1 à 0, ou cas ci-dessus) : nombre de mots = octets / 2 (**un octet impair final
  n'est pas effacé**) ; d'abord une ligne de (mots mod 64) mots, puis un blit de ⌊mots/64⌋ mod 1024
  lignes de 64 mots, puis autant de blits de 1024 × 64 mots (128 Ko) que nécessaire ; le pointeur D
  continue d'un blit à l'autre ; attente BBUSY entre deux BLTSIZE.
- **Bit 2 (remplissage par valeur, V36)** : ignoré. [D]

Observé : 7 octets → 6 effacés, le 7ᵉ intact ; `(1100 << 16) | 2`, flags 3 → **152** octets effacés
(76 lignes = 1100 mod 1024) ; `(3 << 16) | 130`, flags 3 → 390 ; 130 octets linéaires → 130 ;
`(5 << 16) | 8` → 40. [O]

## 5. Fonctions « RastPort » et découpage par les couches

### 5.1 Tampon TempA commun

BltBitMapRastPort, ClipBlit et BltMaskBitMapRastPort obtiennent **avant tout** un TempA : `TmpRas.RasPtr`
de la RastPort destination si `rp_TmpRas ≠ NULL` et `TmpRas.Size ≥ 128` ; pour ClipBlit, à défaut celui
de la RastPort **source** ; sinon allocation de **128 octets MEMF_CHIP** (repli `gb_LCMptr`, §7),
libérée en fin d'appel **après WaitBlit**. Ce TempA est passé à chaque BltBitMap. [D]
Conséquence : une RastPort avec un TmpRas de ≥ 128 octets évite toute allocation ; les sorties
avec allocation **attendent la fin** du dernier blit avant de rendre, les autres non. [D]

### 5.2 Découpage destination (BltBitMapRastPort, BltMaskBitMapRastPort, ClipBlit)

Masque de plans = **`rp_Mask`** de la RastPort destination. [D]

- **Sans couche** (`rp_Layer = NULL`) : un seul BltBitMap vers `rp_BitMap`, coordonnées telles quelles,
  **sans clipping**. [D]
- **Avec couche** : verrou de la couche (ObtainSemaphore sur `Layer.Lock`, imbriquable) pour la durée de
  l'appel. Rectangle destination converti en coordonnées écran : `+ bounds.MinX − Scroll_X`,
  `+ bounds.MinY − Scroll_Y`. Pour chaque ClipRect de `Layer.ClipRect`, dans l'ordre de la liste :
  intersection (bornes inclusives) ; si non vide —
  - ClipRect visible (`lobs = NULL`) : BltBitMap vers `rp_BitMap` aux coordonnées écran ;
  - ClipRect caché avec `cr_BitMap` (smart refresh) : vers `cr_BitMap`, X relatif à `MinX & ~15`,
    Y relatif à `MinY` ;
  - caché sans BitMap (simple refresh) : **ignoré**.
  Puis, si `Layer.SuperBitMap ≠ NULL`, pour chaque ClipRect de `Layer.SuperClipRect`, intersection avec
  le rectangle **en coordonnées de couche** et BltBitMap vers la SuperBitMap. [D]
- **Couche SUPER_BITMAP en destination de BltBitMapRastPort / BltMaskBitMapRastPort** : la fonction
  synchronise d'abord la SuperBitMap depuis l'écran (équivalent SyncSBitMap), met temporairement
  `rp_Layer = NULL` et `rp_BitMap = SuperBitMap`, blitte **directement dans la SuperBitMap sans
  clipping**, restaure, puis recopie vers l'écran (équivalent CopySBitMap). [D]

**BltBitMapRastPort (−606)** : `(srcBM A0, srcX D0, srcY D1, destRP A1, destX D2, destY D3, sizeX D4,
sizeY D5, minterm D6)`. Rend **toujours 1** (D0 = TRUE). [D] Observé : 1 ; ClipBlit sans couche : 1. [O]

### 5.3 ClipBlit (LVO −552)

`ClipBlit(srcRP A0, srcX D0, srcY D1, destRP A1, destX D2, destY D3, xSize D4, ySize D5, minterm D6)`.
Rend **1**. [D]

1. **Verrous** : si les deux couches existent, sont différentes et ont la même `LayerInfo`, prise du
   sémaphore de la LayerInfo, puis verrou source, verrou destination, puis libération de la LayerInfo
   (évite l'étreinte fatale) ; sinon verrou source puis destination. Libération : source puis
   destination. [D]
2. **Même RastPort et SuperBitMap** : synchronisation, blit interne à la SuperBitMap sans couche,
   recopie (comme §5.2). [D]
3. **Même RastPort, rectangles source et destination qui se touchent** : la liste `Layer.ClipRect` est
   **retriée en place, définitivement** (les champs `prev` sont reconstruits) pour que les morceaux soient
   copiés dans l'ordre sûr : pour deux ClipRects qui se chevauchent verticalement, tri par MinX dans le
   sens opposé au déplacement horizontal (déplacement vers la droite → ClipRect le plus à droite
   d'abord) ; sinon tri par MinY dans le sens opposé au déplacement vertical. [D]
4. **Découpage source** : sans couche source, un seul passage avec `srcRP.BitMap` ; avec couche, le
   rectangle source (coordonnées écran de la couche source) est intersecté avec chaque ClipRect de la
   source (BitMap = `rp_BitMap`, `cr_BitMap` ou ignoré, comme §5.2), puis avec les `SuperClipRect`
   (BitMap = SuperBitMap). Chaque morceau source est envoyé au **découpage destination** de §5.2 avec la
   position destination décalée d'autant. Le résultat est l'intersection des parties visibles ou
   sauvegardées des deux côtés ; une partie source cachée sans sauvegarde **laisse la destination
   intacte**. [D]
5. Les rectangles ne sont **pas** contrôlés : xSize/ySize ≤ 0 produisent des intersections « vides
   inversées » qui sont quand même transmises à BltBitMap (cf. §1.2). [D]

### 5.4 BltMaskBitMapRastPort (LVO −636)

`(srcBM A0, srcX D0, srcY D1, destRP A1, destX D2, destY D3, sizeX D4, sizeY D5, minterm D6,
bltMask A2)`. Rien n'est rendu (D0 indéfini). [D]

- **bltMask = NULL : la fonction ne fait rien** (aucun verrou, aucun blit). [D][O]
- Sinon une BitMap fictive est construite sur la pile : en-tête copié de `srcBM` (donc **même
  BytesPerRow, Rows, Depth**), tous les plans pointant sur `bltMask`. Le masque doit donc avoir la
  géométrie d'un plan de la source et être en chip RAM. [D]
- Trois passes complètes du découpage destination (§5.2), chacune sur tous les plans de `rp_Mask` et tous
  les ClipRects : (1) source → destination, minterm **`$90`** (D = ¬(B ⊕ C)) ; (2) masque → destination,
  **minterm de l'appelant** ; (3) source → destination, `$90`. Avec le minterm documenté
  `ABC|ABNC|ANBC` (`$E0`, D = B ∨ C) on obtient « source là où le masque vaut 1, destination intacte
  ailleurs » ; avec `ANBC` (`$20`) « source inversée à travers le masque ». [D][O]
- Effet visible : la destination passe par deux états intermédiaires (scintillement possible), coût ≈ 3
  BltBitMap. [D]

Observé (32 × 1, source `$FF00FF00`, destination `$0F0F0F0F`, masque `$FFFF0000`) : `$E0` →
`$FF000F0F` ; `$20` → `$00FF0F0F` ; masque NULL → `$0F0F0F0F` (inchangé). [O]

## 6. BltTemplate (LVO −36)

Contrat d'appel décrit dans `fastfonts-ff.md` §2/Exigences ; ce qui suit précise le comportement V34.

- **Plans** : de 0 à `Depth − 1` de la BitMap destination, ignorés si le bit correspondant de `rp_Mask`
  est à 0. **Minterm du plan i = `rp_minterms[i]`** (tableau de 8 octets à l'offset `$28` de la RastPort,
  précalculé par SetAPen/SetBPen/SetDrMd) OR `$0A`, avec USEB|USEC|USED (+USEA/décalage selon le
  schéma). B = gabarit (modulo `srcMod − largeur`), C = D = plan destination, A = masque de bord. [D]
- **Un seul descripteur** (même géométrie pour tous les plans) construit par le même moteur que
  BltBitMap (mêmes six schémas, « BytesPerRow source » = srcMod). BLTADAT/masques/BLTCON1/modulos ne sont
  écrits **qu'au premier plan** ; ensuite seuls BLTCON0, BLTBPT, BLTCPT, BLTDPT, BLTSIZE. Attente BBUSY
  avant chaque plan. Prise/restitution du blitter par les **LVO** OwnBlitter/DisownBlitter, pas
  d'attente finale. [D]
- **Sans couche** : pas de clipping (contrairement à ce que demande `fastfonts-ff.md` Exigences, la ROM
  ne rogne **ni** aux bornes de la BitMap **ni** les coordonnées négatives). **xSrc n'est pas normalisé** :
  seuls ses 4 bits bas décalent ; sa partie mots (xSrc ≥ 16) n'avance **pas** le pointeur de gabarit.
  [D] Observé (gabarit `$0000 $FFFF $0F0F`, JAM2, APen 1, BPen 0, 16 × 1) : xSrc 0 → `$0000`, xSrc 16 →
  `$0000` (et non `$FFFF`), xSrc 4 → `$000F` (dans les trois cas le second mot `$5555` est intact). [O]
- **Avec couche** : `LockLayerRom` / `UnlockLayerRom` **par leurs LVO** (−432/−438, couche en A5) autour
  de tout l'appel. Coordonnées converties comme §5.2 ; pour chaque ClipRect, rognage à gauche/en haut
  (avance de xSrc et du pointeur de `srcMod` par ligne sautée), rognage à droite/en bas, morceau ignoré
  si largeur ≤ 0 ou hauteur ≤ 0 ; **puis xSrc est normalisé** (pointeur + (xSrc ≫ 4) × 2, xSrc & 15) —
  donc xSrc ≥ 16 fonctionne avec couche. Destination : rp_BitMap, cr_BitMap (relative à `MinX & ~15`,
  `MinY`), ignorée si cachée sans BitMap ; puis SuperClipRects vers la SuperBitMap. [D]
- Valeur rendue : aucune (D0 indéfini). [D]
- Le registre A2 transmis au moteur commun est le pointeur de **BitMap destination** : si le gabarit
  recouvrait une ligne de la destination avec srcMod = BytesPerRow (schémas P5/P6), la ligne de masque
  serait écrite dans la structure BitMap. Cas pathologique, à ne pas reproduire. [D]

## 7. Allocation temporaire et mémoire de dernier recours

Toutes les allocations temporaires du blitter passent par un même allocateur : `AllocMem(taille,
MEMF_CHIP)` ; en cas d'échec, si taille > 2048 → `Alert($82011234)` ; puis (et dans tous les cas
d'échec) prise du sémaphore **`gb_LastChanceMemory`** (GfxBase $E0) et usage du bloc **`gb_LCMptr`**
(GfxBase $E4), **2048 octets chip** alloués à l'initialisation de la bibliothèque ; la libération
correspondante relâche le sémaphore si le pointeur est `gb_LCMptr`, sinon FreeMem. Le tampon de dernier
recours **sérialise** donc tous les blits à court de mémoire. [D]

Tailles demandées : 128 octets (TempA de BltBitMap et des fonctions RastPort) ; BltPattern : `bytecnt ×
hauteur` (copie réalignée du masque, §8). [D]

## 8. BltPattern (LVO −312)

`BltPattern(rp A1, mask A0, xl D0, yl D1, maxX D2, maxY D3, bytecnt D4)`, bornes **inclusives**. [D]

- Sans couche : moteur direct ; avec couche : moteur découpé par ClipRects (même logique que §5.2). [D]
- **mask = NULL** : remplissage du rectangle (C, D actifs, BLTCON0 `$0300`|minterm), masques de bord
  `$FFFF >> (xl & 15)` / complément de `$FFFF >> ((maxX + 1) & 15)`. Motif `rp_AreaPtrn` sur `2^|AreaPtSz|`
  lignes (AreaPtSz < 0 = motif multicolore, un motif par plan), stylos et mode via `rp_minterms`. [D]
- **mask ≠ NULL** : canal A = masque, modulo A = `bytecnt − largeur`, décalage A = `xl & 15`. Si la
  largeur en mots du rectangle ne correspond pas à `bytecnt`, le masque est **recopié et réaligné** dans
  un tampon chip temporaire de `bytecnt × hauteur` octets (BltClear puis BltBitMap `$CA` d'un plan),
  libéré après WaitBlit. [D]
- Valeur rendue : aucune. Comportement fin du moteur (≈ 3,6 Ko) non entièrement décrit ici : voir
  « Points non tranchés ». [D]

## 9. QBlit (−276) et QBSBlit (−294) : files de blits

Nœud (`hardware/blit.h`, `struct bltnode`, 18 octets) : `n` (+0, suivant), `function` (+4), `stat`
(+8, octet, `CLEANUP = $40`), `blitsize` (+$A, non utilisé par la ROM), `beamsync` (+$C, ligne),
`cleanup` (+$E). GfxBase : `blthd/blttl` ($3A/$3E) file normale, `bsblthd/bsblttl` ($42/$46) file
synchronisée, `BeamSync` ($A2, WORD) = beamsync du premier nœud synchronisé en attente, `VBlank` ($A0,
octet). [D]

### 9.1 Appel de la fonction utilisateur

- Entrée : **A0 = `$DFF000`**, **A1 = nœud**, A6 = GfxBase (appel direct) ; la fonction peut détruire
  D0/D1/A0/A1 (A5 est rechargé par la ROM). [D] Observé : A0 = `$00DFF000`, A1 = nœud, A6 = GfxBase,
  **SR = `$0000`** (mode utilisateur, IPL 0 : appel depuis la tâche, interruptions masquées seulement par
  Disable/INTENA). [O]
- **Sortie : le résultat est lu dans les codes conditions (Z)**, pas dans D0 : Z = 1 (« 0 ») = nœud
  terminé ; Z = 0 = la fonction a lancé un blit et veut être rappelée. Une fonction doit donc finir par
  une instruction qui positionne Z selon D0 (p. ex. `moveq`). [D]
- Avant chaque appel la ROM attend que le blitter soit au repos (double test BBUSY). [D]
- Si la fonction rend « non nul » et que le blitter est **déjà au repos** au retour (aucun blit lancé,
  ou blit très court), la ROM **rappelle immédiatement** la fonction (en tâche : en ouvrant brièvement
  Disable/Enable entre deux appels). Observé : une fonction rendant non nul deux fois sans lancer de
  blit est appelée 3 fois avant le retour de QBlit, puis `cleanup` une fois. [O]
- Fin d'un nœud : attente BBUSY, appel de `cleanup` si `stat & CLEANUP`, BlitLock décrémenté.

### 9.2 QBlit

Met `n = NULL`, puis sous Disable + Forbid : si la file normale n'est pas vide, ajout en queue
(BlitLock incrémenté, INTENA SET|BLIT). Sinon incrément de BlitLock : si le blitter est **libre**, la
fonction est appelée **tout de suite, dans le contexte de l'appelant** (tâche), avec le drapeau
« blitter à la file » posé et l'interruption BLIT acquittée, jusqu'à ce qu'elle rende « terminé » ou
qu'un blit soit en cours (le nœud devient alors tête de file et l'interruption BLIT prend le relais) ;
si le blitter est **pris** par une tâche, le nœud devient tête de file et attend le DisownBlitter.
Permit + Enable. Observé : appel synchrone (avant le retour de QBlit) quand le blitter est libre. [D][O]

### 9.3 Interruption BLIT (niveau 3, vecteur posé par SetIntVector, is_Data = GfxBase)

Acquitte INTREQ BLIT ; si la file normale est vide, traite la file synchronisée (ci-dessous) ; si le
drapeau « blitter à la file » n'est pas posé, sort (le blitter appartient à une tâche) ; sinon boucle :
appel de la tête, fin de nœud (§9.1), passage au suivant. File vidée : effacement du drapeau, passation
aux tâches en attente (§3) et **INTENA CLR|BLIT**. [D]

### 9.4 QBSBlit et synchronisation faisceau

- **Si `gb_VBlank = 0` et `gb_BeamSync = 0` : QBSBlit se comporte exactement comme QBlit** (beamsync
  ignoré). `gb_VBlank` est **remis à 0 par le serveur VBlank de graphics à chaque trame** et mis à 1 par
  **DrawGList** ; hors usage des GELs, QBSBlit n'attend donc pas le faisceau. [D] Observé : nœud avec
  beamsync = 200 soumis à la ligne 50 → fonction appelée **à la ligne 51**, avant le
  retour de QBSBlit (retour ligne 53) ; `gb_VBlank` = 0 et `gb_BeamSync` = 0 ; deux essais identiques. [O]
- Sinon : beamsync est plafonné à `gb_MaxDisplayRow` ; si la file synchronisée n'est pas vide, ajout en
  queue (**pas de tri par ligne**) ; sinon, si la file normale est occupée, le nœud devient tête
  synchronisée (BeamSync = sa ligne, INTENA SET|BLIT) ; sinon, si la ligne courante (VPOSR/VHPOSR) est
  **avant** beamsync, l'**alarme TOD de la CIA-B** est programmée (TOD = compteur de lignes, remis à la
  ligne courante par le serveur VBlank ; valeur divisée par 2 si le bit `$0002` de `gb_system_bplcon0`
  est mis) et le nœud attend ; si la ligne est déjà atteinte : exécution comme QBlit.
- Dans l'interruption BLIT, quand la file normale est vide et `BeamSync ≠ 0` : ligne courante (0 lue
  comme MaxDisplayRow + 1) ≥ BeamSync → la tête synchronisée passe en tête de file normale et est
  exécutée ; sinon, si `gb_VBlank ≠ 0`, réarmement de l'alarme (avec, si une VERTB est pendante, une
  fenêtre brève à IPL 2 pour la laisser passer), et si `gb_VBlank = 0` **toute la file synchronisée est
  transférée devant la file normale** et exécutée sans attendre. [D]
- Serveur d'alarme (ICR bit 2, cf. `timer-v34.md` §6) : désautorise l'alarme ; si la file normale est
  vide, autorise et **provoque** l'interruption BLIT. [D]

## 10. Initialisation (ce qui concerne le blitter)

À l'init de graphics : BLTCON0 = BLTCON1 = 0, un BLTSIZE `$0041` (1 mot × 1 ligne) avant et après
DMACON SET|BLTEN (`$8040`) ; vecteur BLIT posé par **SetIntVector** (pas de chaîne de serveurs) ;
serveur VBlank ajouté (AddIntServer) ; alarme TOD de la CIA-B enregistrée (AddICRVector bit 2) et CRB
bit 7 (écriture de l'alarme) mis ; BlitLock = BlitNest = −1, listes BlitWaitQ et TOF_WaitQ initialisées ;
bloc LCM 2048 octets chip + sémaphore. **Le bit BLTPRI (« nasty ») n'est jamais mis par graphics V34.** [D]

## 11. Points « vrai A500 »

1. **Chip RAM obligatoire** : plans, gabarits, masques, TempA, TmpRas doivent être en chip (512 Ko sur
   OCS : adresses < `$80000`). La ROM ne vérifie rien : un plan en slow RAM (`$C00000`) est lu/écrit par
   le blitter à l'adresse tronquée (données d'une autre zone chip). Les allocations internes de la ROM
   demandent toutes MEMF_CHIP. [D]
2. **BBUSY** : double lecture systématique (§2) avant toute programmation. [D]
3. **Pas de mode nasty** : le 68000 garde ses cycles pendant les blits graphics ; un logiciel qui met
   BLTPRI lui-même change les temps, pas la sémantique. [D]
4. **Pas d'attente finale** dans BltBitMap/BltTemplate/BltClear (bit 0 à 0)/ClipBlit sans allocation :
   le premier accès processeur à la destination doit être précédé de WaitBlit (FastFonts, Workbench et
   intuition le font). Un émulateur « instantané » masque l'oubli. [D]
5. Les limites OCS de BLTSIZE (1024 lignes, 64 mots) s'appliquent **sans contrôle** (§1.2, §4). [D][O]

## 12. Ce qui relie le blitter aux layers

- layers.library sauvegarde/restaure les ClipRects cachés par **BltBitMap** via le LVO de graphics
  (`installclipregion-v34.md` §3) ; la règle « X relatif à `MinX & ~15` » de cr_BitMap (§5.2) est la
  même des deux côtés. [D]
- Les verrous pris par le blitter côté graphics sont : `Layer.Lock` (ObtainSemaphore direct) pour
  BltBitMapRastPort/ClipBlit/BltMaskBitMapRastPort, `LockLayerRom` (LVO) pour BltTemplate ; la LayerInfo
  seulement transitoirement dans ClipBlit (§5.3). Tous imbriquables pour la même tâche. [D]
- ClipBlit **modifie l'ordre de la liste `Layer.ClipRect`** (§5.3) : les layers ne doivent pas dépendre
  de cet ordre. [D]

## Points non tranchés

1. **BltPattern** : seuls les grands cas sont décrits (masque nul, masque réaligné, motif) ; le choix
   exact des modulos et la gestion du motif multicolore n'ont pas été sondés. À sonder avant
   implémentation fine.
2. **Comportement de QBSBlit quand `gb_VBlank ≠ 0`** (après DrawGList) : la logique d'alarme TOD est
   déduite mais **non observée** ; l'effet du bit `$0002` de `gb_system_bplcon0` (division par 2) n'est
   pas expliqué (ERSY ? entrelacé ?).
3. **Comportement réel d'Agnus** pour les cas dégénérés de §1.2 (dstX = 0, sizeX = 0) : déduit, non
   sondé (écrit hors tampon, dangereux pour la sonde).
4. **Plans `NULL`/`-1`** : non sondés (écriture en basse mémoire) ; la conclusion « adresse brute » est
   déduite.
5. **Ordre des ClipRects après tri** quand des ClipRects se chevauchent à la fois en X et en Y de façon
   non transitive : le tri par insertion n'est pas une relation d'ordre totale ; l'ordre résultant pour
   des dispositions complexes n'a pas été vérifié.
6. **Tampon de masque de 128 octets** au-delà de 62 mots (≈ 990 pixels, SuperBitMap très large) :
   débordement déduit, non sondé.
7. **Bit 0 de `stat`** et champ `blitsize` du bltnode : non lus par la ROM d'après le code ; aucune
   sonde.
8. Les chemins **avec couche** (ClipRects cachés, SuperBitMap, tri de ClipBlit) sont **déduits
   uniquement** : la sonde n'utilise que des RastPorts sans couche. Une sonde en fenêtre (smart refresh
   recouverte) serait la suite logique.
