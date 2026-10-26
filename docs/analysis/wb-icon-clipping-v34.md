# wb-icon-clipping-v34.md — workbench.task 34.1 : découpage des icônes, effacement et défilement

> Piste ANALYSE (« dirty »). Source : ROM `assets/kick34005.A500`, module `workbench.task`
> (`wb 34.1`), analysé de façon **statique** sous radare2 (aucun émulateur). Complète
> `workbench-task-v34.md` §8 (gadgets de défilement) et corrige `installclipregion-v34.md` §5.
>
> **Légende** : **[O]** observé directement dans le code · **[D]** déduit d'observations
> convergentes · **[S]** supposé. Ce document décrit des comportements, des layouts d'ABI et des
> constantes. **Aucune suite d'instructions n'est reproduite ni paraphrasée, aucune adresse de
> routine ROM n'est donnée.**

Champs publics utilisés :
- `struct Window` (1.3) : Width +$08, Height +$0A, Flags +$18, RPort +$32, BorderLeft/Top/Right/
  Bottom +$36/+$37/+$38/+$39 (octets signés), IDCMPFlags +$52, **UserData +$78**.
- `struct RastPort` : Layer +$00, Mask +$18, TxBaseline +$3E.
- `struct Layer` (`graphics/clip.h` 1.3) : Flags +$1E (mot ; **LAYERREFRESH = $0080**),
  **DamageList +$9C** (struct Region *).
- `struct Rectangle` : MinX, MinY, MaxX, MaxY (4 mots, bornes **incluses**).
- `struct Screen` : Width +$0C, Height +$0E.
- `struct TextFont` : tf_YSize +$14.
- WBObject (structure privée bâtie par icon.library, cf. `workbench-task-v34.md` §7.3/§7.8) :
  parent +$38, flags +$3C, type +$3D (1 = disque), nom +$40, décalage du nom +$44/+$46 (mots),
  DrawerData +$4C, fenêtre d'affichage +$50, CurrentX/Y +$54/+$58, **Gadget intégré +$60**
  (donc LeftEdge +$64, TopEdge +$66, Width +$68, Height +$6A, Flags +$6C, GadgetRender +$72,
  SelectRender +$76).
- DrawerData : position de défilement +$30/+$34, étendue +$38..+$44, liste des icônes du tiroir
  (struct List) **+$1AC**, fenêtre ouverte **+$1A4**.

---

## 0. Réponse courte

1. **Aucune couche, aucun RastPort, aucune ClipRect ni ClipRegion propres.** Le Workbench dessine
   directement dans `Window->RPort` de la fenêtre du tiroir (fenêtre **non** GIMMEZEROZERO, donc
   sa couche couvre aussi les bordures). [O]
2. Le découpage à la zone de contenu est obtenu par le **truc de BeginUpdate** : le WB **remplace
   (ou réduit) la `DamageList` de la couche** de la fenêtre par le rectangle de contenu, appelle
   **`BeginUpdate`**, dessine, puis **`EndUpdate`**. Pendant la mise à jour, layers ne laisse
   dessiner graphics que dans *visible ∩ dommages* : toute icône — même à cheval sur le bord, ou
   largement hors de la fenêtre — est **dessinée en entier et découpée par layers** au bord du
   contenu. Les bordures et les gadgets ne sont jamais touchés. [O]
3. **Pas de tri « visible / invisible »** : les icônes partielles ne sont **ni sautées, ni
   redessinées avec retouche des bordures**. Seule exception : une icône dont la position fenêtre
   dépasse **4 × la taille de l'écran** (en valeur absolue, sur X ou Y) n'est pas dessinée du tout
   (garde-fou contre les débordements de coordonnées 16 bits). [O]
4. Le **nom** sous l'icône suit exactement le même chemin (Text dans la même mise à jour) : il
   est découpé au pixel près au bord du contenu. [O]
5. **Défilement : pas de ScrollRaster** (le module n'appelle ni ScrollRaster, ni ClipBlit, ni
   ScrollLayer). Chaque changement de position provoque un **réaffichage complet** du contenu :
   recalcul de l'étendue et des barres, puis, sous mise à jour forcée au rectangle de contenu,
   **SetRast(rp, 0)** (donc effacement du **seul rectangle de contenu**), puis dessin de toutes les
   icônes. [O]
6. Le bit **$00400000** de `NewWindow.Flags` **n'a aucun rôle** : intuition 34.3 ne le teste nulle
   part dans `Window->Flags` (il est simplement recopié). C'est la valeur de **INTUITICKS**, que le
   WB manipule par ailleurs dans `IDCMPFlags` ; sa présence dans les Flags est vraisemblablement une
   confusion d'auteur. [O pour l'absence de test, D pour l'interprétation]

---

## 1. Ouverture « dessin dans le contenu » (début de mise à jour) [O]

Entrée : l'objet tiroir/disque (pour connaître la zone de contenu), sa fenêtre, et un **mode** :
**1 = remplacer** les dommages par le rectangle de contenu (dessin spontané : réaffichage complet,
dessin d'une icône) ; **0 = réduire** les dommages existants au rectangle de contenu (réparation
après REFRESHWINDOW/NEWSIZE).

1. **Compteur d'imbrication** global (un octet dans les globales du WB, initialisé à 0) : il est
   incrémenté ; **si sa valeur précédente n'était pas 0, rien d'autre n'est fait** (appel imbriqué,
   la mise à jour en cours sert). Le compteur est **unique pour tout le WB**, pas par fenêtre :
   les appels imbriqués portent toujours sur la même fenêtre.
2. `couche = Window->RPort->Layer` ; **LockLayerRom(couche)** (graphics −432).
3. **Rectangle de contenu**, en coordonnées de la couche (= de la fenêtre, origine au coin
   haut-gauche de la fenêtre, bornes incluses) :
   - MinX = **BorderLeft**, **+ 14 si l'objet est un disque** (type 1 : place de la jauge, cf.
     `workbench-task-v34.md` §8.4) ;
   - MinY = **BorderTop** ;
   - MaxX = **Width − BorderRight − 1** ;
   - MaxY = **Height − BorderBottom − 1**.
   (Pour la fenêtre racine backdrop sans bordure : toute la fenêtre.)
4. `Window->UserData` (+$78) := 0. **Le WB s'approprie UserData de ses fenêtres** comme sauvegarde.
5. **Mode 1** :
   - **NewRegion()** ; si elle réussit : `UserData := couche->DamageList` (sauvegarde) puis
     `couche->DamageList := nouvelle région` ;
   - **ClearRegion(couche->DamageList)** puis **OrRectRegion(couche->DamageList, &rect)** : les
     « dommages » valent exactement le rectangle de contenu.
   - Si NewRegion échoue, c'est la vraie DamageList qui est vidée puis réduite au rectangle (les
     dommages en attente sont perdus ; cas mémoire seulement).
6. **Mode 0** : **AndRectRegion(couche->DamageList, &rect)** : les dommages réels sont rognés au
   rectangle de contenu (la partie des dommages tombant dans les bordures est abandonnée par le WB ;
   la réparation du cadre est l'affaire d'intuition).
7. **BeginUpdate(couche)** (layers −78).

Effet : jusqu'à la fermeture (§2), **tout dessin graphics dans `Window->RPort` est découpé à
(partie visible de la couche) ∩ (rectangle de contenu [∩ dommages réels en mode 0])**.

## 2. Fermeture (fin de mise à jour) [O]

1. Compteur décrémenté ; **s'il n'atteint pas 0, rien d'autre**.
2. Si `UserData ≠ 0` (mode 1 avec région allouée) : **DisposeRegion(couche->DamageList)** (la
   région du WB), `couche->DamageList := UserData` (les vrais dommages en attente sont rendus
   intacts), puis **EndUpdate(couche, FALSE)** (les dommages ne sont pas effacés : une réparation
   ultérieure reste due). Le bit LAYERREFRESH n'est pas touché.
3. Sinon (mode 0, ou échec de NewRegion) : **LAYERREFRESH ($0080) est effacé** dans
   `couche->Flags`, puis **EndUpdate(couche, TRUE)** (dommages effacés : la fenêtre est
   considérée réparée).
4. **UnlockLayerRom(couche)** (graphics −438).

## 3. Dessin d'une icône [O]

Exécuté pour une icône seule (sélection/désélection, dépôt) **entouré de sa propre ouverture/
fermeture en mode 1** (objet = parent `+$38`, fenêtre = `+$50`), ou pour chaque icône d'un
réaffichage complet (l'ouverture est alors imbriquée, donc neutre).

1. Si le **bit 3 de `+$3C`** (« trop loin », §4) est mis : **rien n'est dessiné**.
2. **Image** à la position fenêtre **(x, y) = (`+$64`, `+$66`)** (LeftEdge/TopEdge du gadget
   intégré, déjà convertis en coordonnées fenêtre, §4), décalée du LeftEdge/TopEdge de l'Image ;
   elle est copiée par **BltBitMapRastPort** (graphics −606) — ou **BltMaskBitMapRastPort** (−636)
   pour une icône en mode de surbrillance « backfill » (Flags & 3 = 1, le masque étant la donnée de
   SelectRender) — depuis un BitMap construit sur les plans de l'Image, la `Mask` de la RastPort
   étant temporairement réduite aux plans de PlanePick présents dans l'image puis restaurée.
   Minterm $C0 (copie) à l'état normal ; sélectionnée (bit 5 de `+$3C`) : SelectRender si mode
   GADGHIMAGE et SelectRender ≠ 0, sinon copie inversée ($30 ; $20 en variante masquée ; $E0 pour
   la copie masquée normale). **Aucun DrawImage intuition.** Le blit est **toujours demandé en
   entier** : c'est layers/graphics qui le découpe.
3. **Nom** : SetFont(rp, police du WB), **SetAPen(rp, 1)**, **SetDrMd(rp, JAM2)**,
   **Move(rp, x + `+$44`, y + `+$46`)**, **Text(rp, nom, strlen(nom))**. Le fond JAM2 est le BPen
   courant de la RastPort de la fenêtre (le WB ne le pose pas ; 0 en pratique [D]). Pas de mesure
   ni de troncature : la chaîne entière est demandée et **découpée par layers** au bord du contenu.
   - Décalages du nom (calculés au chargement de l'icône) : `+$44` = (Gadget.Width −
     TextLength(nom)) / 2 (division arithmétique, peut être **négatif** si le nom est plus large que
     l'image), `+$46` = Gadget.Height + **TxBaseline** de la RastPort privée du WB (donc le haut du
     texte est collé sous l'image).

## 4. Position fenêtre, « trop loin » et étendue [O]

Recalculées pour **toutes** les icônes du tiroir lors du recalcul d'étendue
(`workbench-task-v34.md` §8.2), en parcourant la liste `DD+$1AC` de la tête vers la queue :

- x fenêtre `+$64` := **MinX du contenu** (§1.3) + `CurrentX` − `DD+$30` ;
- y fenêtre `+$66` := **BorderTop** + `CurrentY` − `DD+$34` ;
- le **bit 3 de `+$3C`** est d'abord effacé, puis **mis si |x| > 4 × Screen.Width ou |y| > 4 ×
  Screen.Height** (écran du Workbench). C'est le **seul** critère de saut : il n'existe aucun test
  « l'icône intersecte-t-elle le contenu ? ».
- étendue, avec o = max(0, −`+$44`) (débord du nom de chaque côté) :
  min X := min(min X, CurrentX − o) ; min Y := min(min Y, CurrentY) ;
  max X := max(max X, CurrentX + Gadget.Width + o) ;
  max Y := max(max Y, CurrentY + Gadget.Height + **tf_YSize** de la police du WB).

## 5. Réaffichage complet d'un tiroir (et défilement) [O]

Ordre exact :

1. **Recalcul de l'étendue** et des positions fenêtre (§4), puis, sauf pour la fenêtre racine,
   **mise à jour des deux barres** (NewModifyProp, `workbench-task-v34.md` §8.3) — **hors** de la
   mise à jour : intuition redessine la barre concernée elle-même.
2. **Ouverture mode 1** (§1) : verrou, dommages := rectangle de contenu, BeginUpdate.
3. **SetRast(Window->RPort, 0)** : grâce à la mise à jour, seul le **rectangle de contenu**
   (visible) est rempli en couleur 0. Bordures, barre de titre, gadgets, jauge du disque (à gauche
   de MinX) : intacts.
4. **Dessin de chaque icône** (§3) en parcourant la liste `DD+$1AC` **de la queue vers la tête** :
   la tête est dessinée en dernier, donc **au-dessus**. (Le WB remet en tête une icône qu'on vient
   de déplacer : elle passe au premier plan.)
5. **Fermeture** (§2) : dommages réels restaurés, EndUpdate(FALSE), déverrouillage.

**Ce que le WB ne fait jamais ici** : redessiner bordures, cadre ou gadgets système ; appeler
RefreshGadgets/RefreshWindowFrame ; ScrollRaster ; recopier la partie restée visible.

**Déclencheurs** du réaffichage complet : **chaque pas de défilement** (flèches, Shift+flèches,
barres, répétition INTUITICKS : la nouvelle position est écrite en `DD+$30/+$34` puis réaffichage
complet), Clean Up (positions remises à 0 avant), dépôt/déplacement d'une icône dans un tiroir,
suppression ou ajout d'une icône, ouverture de la fenêtre, et WBENCHOPEN. [O pour défilement et
Clean Up ; D pour la liste des autres]

Conséquence visible : à chaque pas de défilement, le contenu est **effacé puis redessiné**
(léger clignotement) ; les icônes à cheval sur le bord apparaissent coupées net au bord du
contenu, sans jamais déborder sur les barres ou le cadre.

## 6. Réparation : REFRESHWINDOW et NEWSIZE [O]

Les deux classes IDCMP mènent au même traitement, **seulement si `couche->Flags` a LAYERREFRESH** :

1. Si la boîte de la fenêtre (Left/Top/Width/Height) diffère de celle mémorisée dans le
   DrawerData (+$00..+$06) — sauf pour la fenêtre racine — elle est mémorisée et l'étendue + les
   barres sont recalculées (§5 point 1, sans réaffichage).
2. Fenêtre de **disque** : la **jauge** est redessinée (hors mise à jour, directement dans la
   RastPort).
3. **Ouverture mode 0** : dommages réels ∩ rectangle de contenu, BeginUpdate.
4. **Pas d'effacement** : les zones endommagées sont supposées déjà au fond (rôle de layers pour
   une couche SIMPLE_REFRESH [D]).
5. Dessin de toutes les icônes (queue → tête), découpées à *dommages ∩ contenu*.
6. **Fermeture** : LAYERREFRESH effacé, **EndUpdate(TRUE)**.

Le cadre et les gadgets de la fenêtre sont réparés par intuition, pas par le WB [D].

## 7. Bit $00400000 des Flags [O]

- Deux chemins d'ouverture d'une fenêtre de tiroir/disque passent les Flags en dur à
  `NewWindow.Flags` : **première ouverture** (gadgets copiés depuis les modèles, §8.1 de
  `workbench-task-v34.md`) : **$0240027F** ; **réouverture** avec un DrawerData déjà prêt :
  **$0200027F**. Le comportement ne peut donc pas en dépendre.
- intuition 34.3 recopie `NewWindow.Flags` dans `Window->Flags` (seul BACKDROP y retire des bits)
  et **ne teste jamais le bit 22** de `Window->Flags` (ni test de bit, ni masque immédiat le
  contenant) ; ses seuls usages de $00400000 portent sur `im_Class` et `IDCMPFlags`
  (INTUITICKS). Le WB ne relit pas non plus `Window->Flags` pour ce bit ; il ajoute et retire
  **INTUITICKS dans IDCMPFlags** (ModifyIDCMP) pour la répétition des flèches.
- Pour notre ROM : **ignorer** ce bit dans `Window->Flags` (le laisser recopié, sans effet).

## 8. Exigences pour notre ROM [D]

- **layers.library** : `BeginUpdate` doit construire les ClipRects de mise à jour à partir de la
  `DamageList` **telle que l'appelant l'a posée** en +$9C (région remplacée par un tiers),
  intersectée avec la partie visible ; `EndUpdate(l, FALSE)` restaure les ClipRects normaux sans
  toucher la DamageList ; `EndUpdate(l, TRUE)` les restaure et vide la DamageList.
- **graphics.library** : SetRast, BltBitMapRastPort, BltMaskBitMapRastPort et Text doivent
  respecter les ClipRects de la couche (y compris pendant une mise à jour) ; régions : NewRegion,
  ClearRegion, OrRectRegion, AndRectRegion, DisposeRegion ; LockLayerRom/UnlockLayerRom.
- **intuition** : `Window->UserData` (+$78) appartient à l'application (le WB s'en sert) ; elle
  doit réparer elle-même cadre et gadgets d'une fenêtre SIMPLE_REFRESH endommagée.
- **workbench.task** : dessiner les icônes **sans** test de visibilité (hors garde-fou 4 × écran),
  dans la RastPort de la fenêtre, entre « ouverture/fermeture » (§1/§2) ; défilement = réaffichage
  complet (§5).

## 9. Vérification boîte noire proposée (non faite, émulateur occupé)

Non indispensable : l'analyse statique est complète. Si l'on veut une preuve visuelle, avec la
vraie ROM puis la nôtre (même ADF Workbench 1.3, même harnais de capture) : ouvrir le disque,
réduire la fenêtre pour qu'une icône soit coupée par le bord droit et par le bord bas, capturer ;
défiler d'un pas de flèche (largeur visible / 8), capturer. Attendu : icône et nom coupés net à
`Width − BorderRight − 1` / `Height − BorderBottom − 1`, barres et cadre intacts, contenu effacé en
couleur 0 puis redessiné à chaque pas.

---

## Relecture clean-room

- [x] Aucune suite d'instructions transcrite ni paraphrasée ligne à ligne : seuls des règles de
  comportement, des ordres d'appels de librairies publiques (graphics, layers, intuition), des
  formules et des offsets de structures (publiques : Window, Layer, RastPort, Region/Rectangle,
  Screen, TextFont ; privées déjà documentées : WBObject, DrawerData).
- [x] Aucune adresse de routine ROM ; les LVO cités sont ceux des `.fd` publics.
- [x] Les points non observés directement sont marqués [D] (rôle de layers/intuition dans la
  réparation, liste exhaustive des déclencheurs du réaffichage complet).
- [x] Correction apportée à `installclipregion-v34.md` §5 (le WB n'utilise pas de fenêtres
  GIMMEZEROZERO ; le découpage passe par la DamageList + BeginUpdate) et précision du bit
  $00400000 dans `workbench-task-v34.md` §8.1.
