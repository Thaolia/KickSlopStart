# intuition-input-menus-v34.md — moteur d'entrées d'intuition 34.3 (Intuition(), IDCMP) et menus

> Piste ANALYSE (« dirty »). Sources : ROM `kick34005.A500` (lecture seule, radare2 + décompilation
> Ghidra headless pour suivre le flot de contrôle) et sonde boîte noire sur la vraie ROM sous FS-UAE
> (`tests/imenu_probe.s` + `tests/imenu_probe.sh`, vecteurs §5). On décrit le **quoi** : comportements,
> ordres, conditions, valeurs, layouts d'ABI. Aucune suite d'instructions, aucun listing, aucune adresse
> de routine de la ROM. Les offsets cités sont ceux des structures publiques (NDK 1.3) ou de champs
> privés d'IntuitionBase (IB) déjà nommés par les specs voisines.
>
> **Légende** : **[O]** observé (lu dans la ROM ou mesuré par la sonde) · **[D]** déduit · **[S]** supposé.
>
> Specs liées, non dupliquées ici : `intuiticks-repeat-v34.md` (input.device, répétition, INTUITICKS,
> VANILLAKEY), `intuition-prefs-v34.md` (installation du handler, PointerTicks, DoubleClick, champs IB),
> `intuition-gzz-v34.md` §3 (MouseX/Y des fenêtres et des messages), `intuition-frame-v34.md` §4
> (rendu actif/inactif), `intuition-requesters-v34.md` §3 (entrées pendant un requester),
> `intuition-prop-v34.md` §4 (gadgets proportionnels), `workbench-task-v34.md` §6.8 (règle
> d'activation à OpenWindow/CloseWindow), `disk-change-v34.md` (DISKINSERTED/REMOVED côté WB).
> Les **écrans** (OpenScreen, barre de titre d'écran, ShowTitle, glisser d'écran) sont hors périmètre
> (spec `intuition-screens-v34.md`, autre agent).

---

## 0. Résumé exécutable

1. Le handler d'intuition (priorité **50**, `is_Data` = IntuitionBase) appelle `Intuition(liste)` et rend
   **une liste neuve de copies** : ce qu'intuition n'a pas transformé en IntuiMessage est recopié (22
   octets) et chaîné pour les handlers suivants (console.device). La liste d'origine n'est jamais rendue.
   [O]
2. Un événement va **soit** en IDCMP à une fenêtre (si elle a le drapeau correspondant et qu'un message a
   pu être alloué), **soit** dans la liste transmise — jamais les deux (sauf DISKINSERTED/REMOVED et
   NEWPREFS, diffusés aux fenêtres **et** transmis avec `IEQUALIFIER_MULTIBROADCAST`). [O]
3. Les messages viennent d'une **réserve par fenêtre** (blocs de 56 octets jamais libérés avant
   CloseWindow) ; un message non rendu n'est jamais réutilisé ; **aucune coalescence** de MOUSEMOVE
   (seul INTUITICKS est limité à un exemplaire en circulation). [O]
4. Les vérifications (MENUVERIFY, SIZEVERIFY, REQVERIFY) **bloquent la tâche input.device** jusqu'à la
   réponse : tout le système d'entrée est gelé (pointeur compris). [O]
5. Menus : barre dessinée dans la couche de titre de l'écran ; boîtes rendues hors écran puis
   **échangées** avec l'écran (SwapBitsRastPortClipRect) ; **LockLayers** sur tout l'écran pendant que le
   menu est ouvert ; le verrou d'état d'intuition reste pris d'un événement à l'autre (SetMenuStrip,
   ClearMenuStrip, OnMenu, OffMenu, LockIBase(0) d'une autre tâche attendent la fermeture). [O]
6. MoveWindow, SizeWindow, WindowToFront/Back, ActivateWindow sont **asynchrones** : mis en file et
   exécutés au début du traitement du prochain événement d'entrée (≤ 100 ms grâce aux tics) ; un
   ActivateWindow demandé pendant un menu ou un gadget actif est **perdu**. [O]

---

## 1. Le handler d'entrée et `Intuition()`

### 1.1 Installation et appel [O]

- Installé au premier OpenLibrary (cf. `intuition-prefs-v34.md` §1) : `IND_ADDHANDLER`, structure
  Interrupt dans IntuitionBase, `ln_Pri` = **50**, `is_Data` = IntuitionBase, `is_Code` = un relais qui
  appelle la fonction publique **`Intuition(ie)` (LVO −36, A0 = liste d'InputEvents)** avec A6 = IB et
  rend son D0 au input.device.
- Un handler de priorité > 50 voit les événements bruts avant intuition ; un handler de priorité < 50
  (console.device) ne voit **que** la liste rendue par intuition.
- `Intuition(NULL)` rend 0 sans rien faire.

### 1.2 Déroulé d'un appel [O]

1. Si aucune opération « longue » n'est en cours (ni menu, ni gadget tenu — bits privés IB+$40 & $600),
   ou si un gadget chaîne est en édition : **prise du verrou d'état** (le premier des 7 sémaphores
   d'IB, celui que prend aussi `LockIBase(0)`, avec le n° 5).
2. Remise à zéro de la liste à transmettre (et libération des copies de l'appel précédent).
3. Récupération des messages déjà rendus de la **fenêtre active** (§2.2).
4. Exécution de la **file d'actions différées** (§1.10).
5. Pour **chaque** événement de la liste, dans l'ordre : pré-traitement (§1.3), puis machine à états
   (§1.8).
6. Si aucune opération longue n'est (encore) en cours, ou en édition de chaîne : **libération** du verrou
   d'état. Donc **le verrou reste pris** d'un appel à l'autre tant qu'un menu est ouvert ou qu'un
   gadget (booléen, proportionnel, système) est tenu. [O] Conséquence : toute fonction qui prend ce
   verrou (SetMenuStrip, ClearMenuStrip, OnMenu, OffMenu, LockIBase(0), ScreenToFront…) appelée par une
   autre tâche **attend** la fin du menu ou du gadget. [D]
7. Rendu : la liste de copies (pointeur de tête), éventuellement vide (0).

### 1.3 Pré-traitement de chaque événement, dans l'ordre [O]

1. **IECLASS_DISKINSERTED (16) / DISKREMOVED (15)** : diffusion (§2.4) puis événement suivant (pas de
   machine à états).
2. **IECLASS_TIMER (6)** : INTUITICKS éventuel à la fenêtre active (`intuiticks-repeat-v34.md` §3).
3. **IECLASS_RAWKEY (1)** :
   - fin des boutons émulés au clavier : si le bouton gauche émulé est enfoncé (§1.7) et que le
     qualificatif ne contient plus LALT ($10) → l'événement devient RAWMOUSE code $E8 (SELECTUP) ; si le
     bouton droit émulé est enfoncé et que le qualificatif ne contient plus RALT ($20) → RAWMOUSE $E9 ;
     Le bouton émulé relâché est traité **comme un événement inséré avant** la touche : l'événement
     clavier d'origine est ensuite traité normalement (la fenêtre reçoit MOUSEBUTTONS $E8 **puis** le
     RAWKEY du relâchement d'Alt) [O, sonde §5 étape 13] ;
   - si c'est un **enfoncement** (bit 7 du code à 0) : traitement des touches Amiga (§1.7), qui peut
     transformer l'événement **en place** (dans la liste d'origine) en RAWMOUSE ou en IECLASS_NULL.
   - Ce traitement a lieu **avant** la mise à jour de l'horodatage (point 4) : les messages produits par
     un raccourci de menu (MENUVERIFY, MENUPICK) portent l'horodatage de l'événement **précédent**
     [O, sonde §5 étape 7].
4. **Horodatage** : IB->Seconds/Micros (+$48/+$4C) := `ie_TimeStamp` de l'événement, **quelle que soit
   sa classe**. Au même moment, tout écran en cours de DisplayBeep (drapeau BEEPING $0020 de
   Screen.Flags) retrouve sa couleur 0 : **un DisplayBeep dure jusqu'au prochain événement d'entrée**
   (≤ 100 ms, un tic). [O]
5. **Souris** (classes RAWMOUSE 2 et POINTERPOS 4) :
   - POINTERPOS sans RELATIVEMOUSE ($8000) : converti en relatif (formule de `intuition-prefs-v34.md` §6),
     la classe devient RAWMOUSE ;
   - accumulation PointerTicks par axe (même §6) ; position bornée (§1.5) ; propagation aux écrans et
     fenêtres (§1.4) ; déplacement du sprite pointeur à ((MouseX >> 1) + XOffset, (MouseY >> 1) + YOffset) ;
   - **MOUSEMOVE** (§2.4) à la fenêtre active si elle a REPORTMOUSE (Window.Flags $0200) et que le delta
     effectif n'est pas nul, sauf pendant un menu ou un gadget si la couche de la fenêtre est verrouillée
     par la tâche input.device elle-même (cas des menus, qui verrouillent toutes les couches de l'écran) :
     **pas de MOUSEMOVE pendant qu'un menu est ouvert**. [O]
6. Machine à états (§1.8).

### 1.4 Coordonnées [O]

- **IB->MouseX (+$46)** est en pixels **haute résolution** (0..639), **IB->MouseY (+$44)** en lignes
  **entrelacées** (0..2 × NormalDisplayRows − 1).
- Après chaque mouvement, pour **tous** les écrans : Screen.MouseX = (IB.MouseX, divisé par 2 si l'écran
  n'est pas HIRES) − Screen.LeftEdge ; Screen.MouseY = (IB.MouseY, divisé par 2 si l'écran n'est pas
  LACE) − Screen.TopEdge. Pour **toutes** les fenêtres de chaque écran : Window.MouseX/Y =
  Screen.MouseX/Y − LeftEdge/TopEdge ; GZZMouseX/Y = Window.MouseX/Y − BorderLeft/BorderTop (cf.
  `intuition-gzz-v34.md` §3).

### 1.5 Bornes du pointeur [O]

Champs privés : MinX +$50, MaxX +$52, MinY +$54, MaxY +$56 (unités IB).

- État de repos (recalculé après chaque changement d'ordre d'écrans, fin de menu, fin de glisser) :
  MinX = 0, MaxX = IB+$546 − 1 (NormalDisplayColumns − 1), MinY = IB+$378, MaxY = min(IB+$544,
  (TopEdge + Height) de l'écran de tête, ×2 s'il n'est pas LACE, − 1).
- **Menu ouvert** : MinY := TopEdge de l'écran du menu (×2 si non LACE), si le pointeur est en dessous :
  le pointeur ne peut pas quitter l'écran par le haut.
- Glisser/redimensionner une fenêtre ou glisser un écran : bornes restreintes pour garder l'objet à
  l'écran (détail : spec écrans / fenêtres, non traité ici).

### 1.6 Vitesse et accélération [O]

Aucune accélération en 1.3 : le seul facteur est **PointerTicks** (1, 2 ou 4 ; défaut ROM 2, WB 1.3 :
1), appliqué par l'accumulateur (`intuition-prefs-v34.md` §6). La vitesse réelle dépend donc du
nombre de comptes de quadrature que gameport.device remonte par événement (§4).

### 1.7 Touches Amiga : souris au clavier, raccourcis d'écran, raccourcis de menu [O]

Traitement des **enfoncements** dont le qualificatif contient LCOMMAND ($40) ou RCOMMAND ($80) :

| Touche (code brut) | Qualificatif | Effet |
|---|---|---|
| ← $4F / → $4E | Amiga (G ou D) | l'événement devient RAWMOUSE code $FF (sans bouton), ie_X = ±vitesseX |
| ↑ $4C / ↓ $4D | Amiga | idem en Y, ie_Y = ∓/±vitesseY (↑ négatif) |
| Alt gauche (LALT $10 dans le qualificatif) | Amiga | RAWMOUSE $68 (SELECTDOWN), si pas déjà émulé |
| Alt droite (RALT $20) | Amiga | RAWMOUSE $69 (MENUDOWN), si pas déjà émulé |
| N ($36) | **LCOMMAND** | WBenchToFront ; l'événement devient IECLASS_NULL (avalé) [O ROM, non sondé] |
| M ($37) | **LCOMMAND** | WBenchToBack ; avalé [O ROM, non sondé] |
| toute touche convertible | **RCOMMAND** | raccourci de menu (§3.11) |

- Vitesses : X (IB privé) = 1 à l'enfoncement simple, **+6** à chaque répétition (qualificatif REPEAT
  $0200), **100** si une touche Shift est tenue ; Y = 1, **+4** par répétition, **75** avec Shift.
  Toute autre touche Amiga remet la vitesse de l'axe non concerné à 0. Ces deltas passent ensuite par
  PointerTicks comme un mouvement de souris (avec PointerTicks = 2, un appui simple ne déplace que d'un
  demi-pixel haute résolution, accumulé). [O]
- Les boutons émulés se relâchent au premier événement clavier dont le qualificatif ne contient plus
  l'Alt correspondant (§1.3), typiquement le relâchement de la touche Alt. [O]
- L'ordre des tests est : flèches, Alt gauche, Alt droite, N/M, raccourci de menu. Shift+Amiga+lettre
  est donc aussi un raccourci de menu. [O]

### 1.8 Machine à états (IB privé, mot d'état) [O]

| État | Signification | Entrée | Sortie |
|---|---|---|---|
| 1 | repos | init, fin de toute opération | — |
| 2 | attente du double-clic de DMRequest (§3.12) | MENUDOWN, fenêtre avec DMRequest | délai/mouvement/2ᵉ clic |
| 3 | menu ouvert, suivi du pointeur | MENUDOWN accepté | MENUUP |
| 6 | gadget booléen tenu (RELVERIFY) | SELECTDOWN sur gadget | SELECTUP |
| 7 | fenêtre active en requester | Request, activation d'une fenêtre à requester | ReqCount = 0 |
| 8 | gadget proportionnel tenu | SELECTDOWN sur prop | SELECTUP |
| 9 | glisser d'écran | SELECTDOWN sur barre d'écran | SELECTUP |
| 10 | édition d'un gadget chaîne | SELECTDOWN sur gadget chaîne | fin d'édition |
| 11 ($B) | bouton droit « rendu à l'application » | RMBTRAP, MENUCANCEL | MENUUP |
| 12 ($C) | glisser/redimensionner une fenêtre (cadre fantôme) | SELECTDOWN sur WDRAGGING/SIZING | SELECTUP |

Un état inconnu provoque `Alert($8400000C)`. Dans l'état 1 :

- classe ≠ RAWMOUSE : **distribution normale** (§2.3) — sauf IECLASS_TIMER, jamais transmis ;
- RAWMOUSE code $E8 / $E9 (relâchements) : distribution normale (MOUSEBUTTONS à la fenêtre active ou
  transmission) ;
- code $68 (SELECTDOWN) : §1.9 ;
- code $69 (MENUDOWN) : §3.3 (s'il n'y a pas de fenêtre active : avalé) ;
- tout autre code (déplacement pur $FF, bouton du milieu $6A/$EA, codes < $68) : **avalé**, rien
  n'est transmis. [O]

Pendant les états 3, 6, 8, 9, 12 tous les événements autres que ceux qui pilotent l'opération (y compris
les touches) sont **avalés** ; seuls INTUITICKS et MOUSEMOVE (pré-traitement) continuent. Dans l'état 7
ils sont avalés sauf requester NOISYREQ (`intuition-requesters-v34.md` §3.2). Dans l'état 11 ils sont
distribués normalement (MOUSEBUTTONS SELECTDOWN compris, **sans** test de gadget ni changement de
fenêtre active) ; les déplacements purs y sont avalés. [O]

### 1.9 Bouton gauche (SELECTDOWN) à l'état de repos [O]

1. **Fenêtre sous le pointeur** : écrans parcourus du premier (devant) au dernier, en sautant les écrans
   dont le ViewPort est caché (VP_HIDE $2000) ; dans chacun, `WhichLayer` à (Screen.MouseX, Screen.MouseY) :
   - couche trouvée = **barre de titre de l'écran** → la fenêtre retenue est **la fenêtre active
     actuelle** (pas de changement) et l'écran est noté pour ses gadgets ;
   - autre couche → sa fenêtre (`Layer->Window`) ;
   - aucune couche et le pointeur est sous le haut de cet écran → **aucune fenêtre (NULL)** ;
   - sinon (pointeur au-dessus de cet écran) → écran suivant.
2. Si cette fenêtre ≠ fenêtre active : **activation** (§1.11), y compris avec NULL (clic sur le fond
   d'un écran sans fenêtre de fond : plus aucune fenêtre active). Si la nouvelle fenêtre a des
   requesters, l'événement est retraité dans l'état 7.
3. **Recherche du gadget** (dans la fenêtre désormais active) : gadgets d'écran si clic sur la barre ;
   sinon gadgets du premier requester si le clic est sur sa couche ; sinon `FirstGadget`. Premier gadget
   (dans l'ordre de la liste) dont la boîte contient le point :
   - s'il est GADGDISABLED ($0100) : **aucun gadget** (il masque ceux qui sont dessous) ;
   - si la fenêtre a un requester et que le gadget n'est ni REQGADGET ($1000) ni SYSGADGET ($8000) :
     aucun ;
   - le gadget de fermeture (type $80) est ignoré quand un requester est présent.
   Le clic qui active une fenêtre **agit aussi** sur le gadget visé (pas de clic « d'activation seule »).
4. Gadget trouvé : sélection et rendu ; GADGIMMEDIATE ($0002) ⇒ **GADGETDOWN** ; sinon, FOLLOWMOUSE ($0008)
   ⇒ un MOUSEMOVE immédiat à la position courante ; FOLLOWMOUSE pose REPORTMOUSE sur la fenêtre pour la
   durée du gadget (l'état antérieur est restauré à la fin). Puis selon le type :
   - booléen sans RELVERIFY : fin immédiate (désélection sauf TOGGLESELECT, pas de GADGETUP) ;
   - booléen RELVERIFY : état 6 ; au SELECTUP, pointeur **dedans** ⇒ **GADGETUP** (ou action système :
     profondeur, fermeture ⇒ CLOSEWINDOW) ; **dehors** ⇒ **MOUSEBUTTONS SELECTUP** (pas de GADGETUP) ;
   - proportionnel : état 8 (`intuition-prop-v34.md`), GADGETUP au relâchement si RELVERIFY ;
   - chaîne : état 10 ;
   - type inconnu (2 ou > 4 hors types système) : `Alert($04000001)` (récupérable) ;
   - SIZING ($10) : SIZEVERIFY d'abord (§2.5), puis état 12 ; WDRAGGING ($20) : état 12 ; SDRAGGING ($30) :
     état 9.
5. Pas de gadget : **MOUSEBUTTONS SELECTDOWN** ($68) à la fenêtre active (ou transmission).
   Un SELECTDOWN sur gadget ne produit **pas** de MOUSEBUTTONS. [O]

### 1.10 Actions différées (file d'IB, nœuds de 18 octets) [O]

Ces fonctions **n'agissent pas tout de suite** : elles déposent une demande (nœud réutilisé s'il est
libre, sinon AllocMem public ; échec ⇒ `Alert($8400000E)`) et rendent la main.

| Demande | Déposée par | Exécution |
|---|---|---|
| activer une fenêtre | ActivateWindow ; OpenWindow avec ACTIVATE ; CloseWindow de la fenêtre active (successeur, `workbench-task-v34.md` §6.8) ; CloseScreen | §1.11, puis événement IECLASS_EVENT code 1 transmis |
| réparer un écran | CloseWindow, EndRequest, ShowTitle | couches endommagées, REFRESHWINDOW (§2.4) |
| NEWPREFS | SetPrefs(…, inform = TRUE) | diffusion NEWPREFS (§2.4) |
| MoveWindow / SizeWindow | MoveWindow / SizeWindow | déplacement / taille, puis NEWSIZE (§2.4) |
| WindowToFront / WindowToBack | idem | changement d'ordre des couches |
| REQSET / REQCLEAR | Request / EndRequest | message (§2.4) |
| contrôle « requester » | Request | passage en état 7 |

- La file est exécutée **au début de chaque appel d'Intuition()** (donc au prochain événement : au plus
  ≈ 100 ms grâce aux IECLASS_TIMER), dans l'ordre de dépôt, **avant** les événements de cet appel.
  L'horodatage des messages produits est celui du dernier événement traité.
- Pendant un menu ou un gadget tenu : les **activations sont abandonnées** (nœud libéré sans effet) ;
  Move/Size/ToFront/ToBack/contrôle requester qui concernent l'**écran actif** restent en file jusqu'à
  la fin de l'opération ; les autres (autres écrans, REQSET/REQCLEAR, NEWPREFS) s'exécutent. [O]

### 1.11 Activation et désactivation [O]

Routine commune (clic, file différée) :
1. ancienne fenêtre active ≠ NULL : **INACTIVEWINDOW** (cible = l'ancienne), puis rendu « inactif »
   (`intuition-frame-v34.md` §4.2) ;
2. ActiveWindow := nouvelle ; codes de menu courants remis à MENUNULL ; si NULL : fin ;
3. drapeaux de travail des menus de la fenêtre effacés (§3.8), **WINDOWACTIVE** ($2000) posé,
   **ACTIVEWINDOW** (cible = la nouvelle) ;
4. si Screen.Title ≠ Window.ScreenTitle : le titre d'écran prend celui de la fenêtre et la barre est
   redessinée ; ActiveScreen := écran de la fenêtre ; coordonnées souris recalculées pour la fenêtre ;
   pointeur de la fenêtre installé ; barre de titre de la fenêtre redessinée si elle a un titre ou DRAG.

Après une activation par clic, intuition transmet en plus un événement **IECLASS_EVENT (3) code 1**
dont `ie_EventAddress` = la nouvelle fenêtre active (pour console.device) ; c'est aussi le cas pour une
activation différée. [O]

---

## 2. IntuiMessages (IDCMP)

### 2.1 Correspondance classe d'événement → classe IDCMP [O]

| ie_Class | Condition | IDCMP | Code du message |
|---|---|---|---|
| $0C SIZEWINDOW | — | NEWSIZE $2 | 0 |
| $0D REFRESHWINDOW | — | REFRESHWINDOW $4 | 0 |
| $02 RAWMOUSE | code ≠ $FF | MOUSEBUTTONS $8 | $68/$E8/$69/$E9 |
| $02 RAWMOUSE | code = $FF | MOUSEMOVE $10 | $FF |
| $07 GADGETDOWN | — | GADGETDOWN $20 | 0 |
| $08 GADGETUP | — | GADGETUP $40 | 0 |
| $09 REQUESTER | code ≠ 0 | REQSET $80 | 1 |
| $09 REQUESTER | code = 0 | REQCLEAR $1000 | 0 |
| $0A MENULIST | — | MENUPICK $100 | code de menu |
| $0B CLOSEWINDOW | — | CLOSEWINDOW $200 | 0 |
| $01 RAWKEY | fenêtre sans VANILLAKEY | RAWKEY $400 | code brut |
| $01 RAWKEY | fenêtre avec VANILLAKEY | VANILLAKEY $200000 | caractère (§2.6) |
| $0E NEWPREFS | — | NEWPREFS $4000 | 0 |
| $10 DISKINSERTED | — | DISKINSERTED $8000 | 0 |
| $0F DISKREMOVED | — | DISKREMOVED $10000 | 0 |
| $11 ACTIVEWINDOW | — | ACTIVEWINDOW $40000 | 0 |
| $12 INACTIVEWINDOW | — | INACTIVEWINDOW $80000 | 0 |
| $06 TIMER | — | INTUITICKS $400000 | 0 |

- Hors table : SIZEVERIFY $1, REQVERIFY $800, MENUVERIFY $2000 (envoyés par le mécanisme de
  vérification §2.5) ; **WBENCHMESSAGE $20000 n'est jamais émis par intuition 34.3** ; DELTAMOVE
  $100000 n'est pas une classe mais modifie MouseX/Y (§2.3). [O]

### 2.2 Construction, réserve et cycle de vie [O]

- **Réserve par fenêtre** : liste simplement chaînée (champ privé `MessageKey` de la fenêtre, +$5E ; lien
  dans `SpecialLink` +$30 du message). Un message **libre** a `Class = $80000000`. Allocation : on prend le
  premier libre ; sinon AllocMem(**56**, MEMF_PUBLIC|MEMF_CLEAR), `ln_Type` = NT_MESSAGE, ajouté en tête.
  Les blocs ne sont libérés qu'à la fermeture de la fenêtre.
- **Récupération** des messages rendus : par GetMsg sur le **WindowPort** (+$5A) de la fenêtre, (a) au
  début de chaque appel d'Intuition() pour la fenêtre active, (b) avant chaque allocation pour la
  fenêtre cible. Chaque message récupéré redevient libre ($80000000) ; si c'était un INTUITICKS, le
  drapeau WINDOWTICKED est effacé. Un message trouvé dans le WindowPort qui n'est pas NT_REPLYMSG ⇒
  `Alert($8400000D)`.
- **Un message non rendu n'est jamais réutilisé** : une application qui ne répond pas fait croître la
  réserve de 56 octets par message, sans limite. Si AllocMem échoue, le message n'est pas envoyé et
  **l'événement est transmis à la place** (console). [O ; conséquence console D]
- Envoi : sous Forbid, `PutMsg(UserPort)` ; le WindowPort est en PA_IGNORE (pas de signal à intuition).
- Champs remplis (communs) :

| Champ | Offset | Valeur |
|---|---|---|
| `mn_ReplyPort` | +$0E | WindowPort de la fenêtre |
| `mn_Length` | +$12 | **$20** (valeur fixe, pas la taille réelle) |
| `Class` | +$14 | classe IDCMP (§2.1) |
| `Code` | +$18 | voir §2.1 / §2.4 |
| `Qualifier` | +$1A | `ie_Qualifier` de l'événement |
| `IAddress` | +$1C | `ie_EventAddress` de la copie de l'événement (voir §2.3) ; RAWKEY : adresse d'une copie, dans le message (+$34), des 4 octets d'historique des touches mortes |
| `MouseX/MouseY` | +$20/+$22 | Window.MouseX/MouseY ; avec **DELTAMOVE** : `ie_X/ie_Y` de l'événement d'origine |
| `Seconds/Micros` | +$24/+$28 | IB->Seconds/Micros = horodatage de l'événement en cours (§1.3) |
| `IDCMPWindow` | +$2C | la fenêtre |

- Ports : ModifyIDCMP/OpenWindow créent deux ports nommés **« IDCMP »** (ajoutés à la liste publique
  par AddPort) : UserPort (signal alloué dans la tâche appelante) et WindowPort (signal libéré, PA_IGNORE).

### 2.3 Fenêtre cible et IAddress [O]

| Classes | Fenêtre cible | IAddress |
|---|---|---|
| MOUSEBUTTONS, MOUSEMOVE, INTUITICKS, ACTIVEWINDOW, INACTIVEWINDOW | fenêtre active (pour INACTIVEWINDOW : l'ancienne) | **la fenêtre** — sauf les MOUSEBUTTONS MENUUP envoyés à la fermeture d'un menu (§3.9) : valeur brute de l'événement [O, sonde] |
| GADGETDOWN, GADGETUP | fenêtre active | **le gadget** |
| REQSET, REQCLEAR, REFRESHWINDOW | fenêtre désignée par l'événement | **la fenêtre** |
| RAWKEY, VANILLAKEY, MENUPICK, CLOSEWINDOW, **NEWSIZE** | **fenêtre active** | valeur brute de `ie_X/ie_Y` de l'événement (RAWKEY : §2.2) — sans signification |
| DISKINSERTED/REMOVED, NEWPREFS | toutes les fenêtres demandeuses (§2.4) | valeur brute |

- **NEWSIZE va toujours à la fenêtre active** : un SizeWindow sur une fenêtre inactive envoie le NEWSIZE
  à la fenêtre active (ou le transmet si elle ne le demande pas). [O, défaut de la 1.3]
- Pas de fenêtre active, fenêtre sans IDCMP, ou drapeau absent ⇒ l'événement est **transmis**
  (copie, `ie_EventAddress` = la fenêtre cible pour les classes de la 1ʳᵉ ligne ; MOUSEBUTTONS transmis
  garde ses deltas d'origine). [O]

### 2.4 Classe par classe [O sauf mention]

- **MOUSEBUTTONS** : SELECTDOWN sans gadget (§1.9), SELECTUP hors gadget ou hors d'un gadget RELVERIFY
  tenu, MENUDOWN/MENUUP avec RMBTRAP ou après MENUCANCEL (§3.10), MENUUP aux fenêtres en
  MENUVERIFY à la fermeture d'un menu (§3.9). Jamais pour le bouton du milieu.
- **MOUSEMOVE** : §1.3 point 5 ; un message **par événement de mouvement**, aucune coalescence ; Code $FF.
- **GADGETDOWN / GADGETUP** : §1.9 ; Code 0.
- **REQSET** : Code 1, à chaque Request réussi (différé) et à l'ouverture d'un DMRequest ; **REQCLEAR** :
  Code 0, à chaque EndRequest (différé) et à chaque requester terminé par ENDGADGET
  (`intuition-requesters-v34.md` §3.3).
- **MENUPICK** : §3.9 et §3.11 ; Code = premier code de la chaîne ou MENUNULL ($FFFF).
- **CLOSEWINDOW** : relâchement **dans** le gadget de fermeture (type $80) ; Code 0.
- **NEWSIZE** : à la fin de chaque SizeWindow (glisser du gadget de taille compris), même si la taille n'a
  pas pu changer. Voir la cible §2.3.
- **REFRESHWINDOW** : à chaque réparation d'écran (fin de menu, fin de glisser, CloseWindow, EndRequest…),
  pour chaque fenêtre dont la couche est endommagée (LAYERREFRESH) et **sans NOCAREREFRESH** ; avec
  NOCAREREFRESH, intuition fait elle-même le Begin/EndRefresh. Le cadre (et la couche de bordure GZZ)
  est redessiné avant le message.
- **ACTIVEWINDOW / INACTIVEWINDOW** : §1.11.
- **DISKINSERTED / DISKREMOVED / NEWPREFS** : pour chaque écran, chaque fenêtre qui a le drapeau ; puis
  l'événement est **aussi** transmis avec `ie_Qualifier |= $0800` (MULTIBROADCAST).
- **RAWKEY / VANILLAKEY / INTUITICKS** : `intuiticks-repeat-v34.md` §3 et §5, précisé §2.6.

### 2.5 Vérifications : SIZEVERIFY, MENUVERIFY, REQVERIFY [O]

Mécanisme commun `verify(fenêtre, classe, code)` :
1. la fenêtre n'a pas le drapeau ⇒ rend « 1 » (on continue sans attendre) ;
2. message alloué (échec ⇒ rend **4**) ; Code = code demandé ; IAddress = `ie_EventAddress` ; MouseX/Y =
   Window.MouseX/Y (**pas** de DELTAMOVE ici) ; IB note la fenêtre et le message en attente ;
3. le WindowPort passe en **PA_SIGNAL** vers la **tâche input.device** (signal alloué pour l'occasion),
   `PutMsg(UserPort)`, **libération du verrou d'état**, puis attente : la tâche input.device est
   **bloquée** — plus aucun événement n'est traité (pointeur figé, clavier en attente) ;
4. chaque message rendu qui arrive est remis libre ; quand c'est le message attendu : on rend **son Code
   au moment de la réponse** ; si l'attente a été annulée (ci-dessous) : rend 4 ;
5. reprise du verrou, libération du signal, WindowPort de nouveau PA_IGNORE.

Annulation : ModifyIDCMP qui retire la classe attendue (ou ferme l'IDCMP) pour la fenêtre en attente :
le message est retiré du UserPort (Remove), son Code mis à 4, il est rendu, et la tâche input.device est
réveillée (résultat 4). [O]

Usages :
- **MENUVERIFY** ($2000) : Code **MENUHOT (1)** à la fenêtre active au MENUDOWN et au raccourci clavier ;
  l'application peut répondre Code = **MENUCANCEL (2)** pour annuler (§3.10) ; Code **MENUWAITING (3)** aux
  **autres** fenêtres de l'écran actif qui ont MENUVERIFY, **une par une** (chacune attend sa réponse),
  juste avant l'ouverture effective du menu ; leur réponse est ignorée.
- **SIZEVERIFY** ($1) : Code 0, au SELECTDOWN sur le gadget de taille ; seul le résultat 4 (échec ou
  annulation) empêche le redimensionnement, le Code de réponse est ignoré.
- **REQVERIFY** ($800) : Code 0, **uniquement** avant l'ouverture d'un DMRequest (§3.12) ; seul 4 empêche
  l'ouverture. Request() n'envoie pas de REQVERIFY. [O]

### 2.6 Précisions par fonctionnalité [O]

- **Non-réponse** : une application qui ne lit pas son port n'empêche rien (sauf les vérifications, qui
  bloquent tout) ; ses messages s'accumulent (§2.2) ; seul INTUITICKS est limité à un exemplaire.
- **REPORTMOUSE** : Window.Flags $0200, posé/effacé par `ReportMouse(bool D0, fenêtre A0)` sous Forbid
  (seul le mot bas de D0 est testé) ; effet immédiat. **FOLLOWMOUSE** : §1.9.
- **RMBTRAP** ($00010000 de Window.Flags, pas d'API en 1.3) : MENUDOWN ⇒ **MOUSEBUTTONS $69** à la fenêtre
  active, état 11 ; MENUUP ⇒ MOUSEBUTTONS $E9. Le test se fait sur la fenêtre **active** au moment du
  MENUDOWN.
- **DELTAMOVE** : MouseX/Y des messages = `ie_X/ie_Y` de l'événement (pour MOUSEMOVE : le delta effectif
  après PointerTicks ; pour un RAWKEY : les octets d'historique ; pour les boutons : le delta porté par
  l'événement, en général 0).
- **VANILLAKEY** : si la fenêtre active a VANILLAKEY, chaque RAWKEY est converti par
  `RawKeyConvert(ie, tampon, 1, keymap par défaut)` : un enfoncement donnant **exactement un** caractère ⇒
  VANILLAKEY (Code = caractère) ; **tout le reste** (relâchements, touches sans caractère, touches
  mortes) est **avalé** — ni RAWKEY (même si RAWKEY est aussi demandé), ni transmission. [O]
- **CurrentTime(secs, micros)** rend IB->Seconds/Micros : l'horodatage du **dernier événement d'entrée
  traité**, pas l'heure courante (au pire 100 ms de retard). [O]
- **DoubleClick(s1, µ1, s2, µ2)** : vrai si (s2 − s1, µ2 − µ1) — avec emprunt d'une seconde si µ2 < µ1 —
  est **strictement** inférieur à la durée de double-clic des prefs (IB+$336/$33A). Aucun test de
  signe : un temps 2 antérieur au temps 1 rend vrai. Intuition ne s'en sert elle-même que pour le
  DMRequest. [O]
- **ModifyIDCMP(fenêtre A0, drapeaux D0)** : sous Forbid ; annule une vérification en attente dont la
  classe disparaît ; drapeaux = 0 ⇒ IDCMPFlags := 0, signal du UserPort libéré, **messages encore
  présents dans le UserPort rendus** (Code mis à 4), UserPort et WindowPort supprimés (RemPort, FreeMem
  34 octets) ; drapeaux ≠ 0 ⇒ ports créés s'ils manquent, IDCMPFlags := drapeaux. [O]

---

## 3. Menus

### 3.1 Structures et codes (ABI) [O]

- `Menu` (30 octets) : NextMenu +0, LeftEdge +4, TopEdge +6, Width +8, Height +10, Flags +12
  (MENUENABLED $0001, MIDRAWN $0100), MenuName +14, FirstItem +18, JazzX +22, JazzY +24, BeatX +26,
  BeatY +28.
- `MenuItem` (34 octets) : NextItem +0, LeftEdge +4, TopEdge +6, Width +8, Height +10, Flags +12, MutualExclude
  +14, ItemFill +18, SelectFill +22, Command +26, SubItem +28, NextSelect +32. Flags : CHECKIT $1, ITEMTEXT $2,
  COMMSEQ $4, MENUTOGGLE $8, ITEMENABLED $10, HIGHFLAGS $C0 (HIGHIMAGE 0, HIGHCOMP $40, HIGHBOX $80,
  HIGHNONE $C0), CHECKED $100, ISDRAWN $1000, HIGHITEM $2000, MENUTOGGLED $4000.
- **Code de menu** (16 bits) : menu = bits 0–4 (NOMENU $1F), élément = bits 5–10 (NOITEM $3F),
  sous-élément = bits 11–15 (NOSUB $1F). MENUNULL = $FFFF.
- Window : MenuStrip +$1C, Flags MENUSTATE $8000 (posé pendant le menu), RMBTRAP $10000, CheckMark +$64,
  DetailPen +$62, BlockPen +$63.

### 3.2 Fonctions [O]

- **SetMenuStrip(fenêtre A0, menu A1)** : prend le verrou d'état ; Window.MenuStrip := menu ; pour
  **chaque** menu, calcule la boîte englobante de ses éléments (§3.5, sous-éléments exclus) ; si son haut
  est < 0 ⇒ `Alert($84000006)` ; puis gauche −= MenuHBorder, haut −= MenuVBorder, droite += MenuHBorder,
  bas += MenuVBorder ; gauche ramenée à 0 si > 0 ; droite portée à Menu.Width − 1 si plus petite ;
  résultat dans JazzX, JazzY, BeatX, BeatY. **Les bordures sont lues dans l'écran actif**
  (IntuitionBase->ActiveScreen), pas dans l'écran de la fenêtre. Rend TRUE. Aucun dessin.
- **ClearMenuStrip(fenêtre)** : sous verrou d'état, MenuStrip := NULL. Rien d'autre.
- **OnMenu / OffMenu(fenêtre A0, code D0)** : menu = NOMENU ⇒ rien ; sous verrou d'état : élément NOITEM ⇒
  bit MENUENABLED du menu ; sous-élément NOSUB ⇒ ITEMENABLED de l'élément ; sinon ITEMENABLED du
  sous-élément. **Aucun rafraîchissement** (la barre n'est visible que pendant un menu et elle est
  redessinée à chaque ouverture).
- **ItemAddress(menu A0, code D0)** : menu NOMENU ⇒ NULL ; élément NOITEM ⇒ **NULL** (pas le menu) ;
  sous-élément NOSUB ⇒ l'élément, sinon le sous-élément. Pas de verrou, **aucun contrôle de bornes** :
  un numéro au-delà de la liste suit un pointeur NULL.

### 3.3 Ouverture (MENUDOWN dans l'état 1, sans RMBTRAP) [O]

1. Fenêtre active obligatoire (sinon l'événement est avalé).
2. **MENUVERIFY MENUHOT** à la fenêtre active (§2.5) : réponse MENUCANCEL ⇒ état 11 (§3.10) ; résultat 4
   ou fenêtre active changée entre-temps ⇒ abandon (état 1).
3. Barre de menus dessinée (§3.4).
4. Fenêtre avec **DMRequest** ⇒ §3.12 (état 2).
5. **MENUWAITING** aux autres fenêtres de l'écran actif qui ont MENUVERIFY (une par une).
6. Si la fenêtre active a changé : barre retirée, MENUUP aux fenêtres en MENUVERIFY (§3.9), fin.
7. Sinon : premier code sélectionné := MENUNULL ; codes « affiché » et « surligné » := MENUNULL ;
   Window.Flags |= **MENUSTATE** ; **LockLayers(&Screen->LayerInfo)** (toutes les couches de l'écran) ;
   suivi immédiat du pointeur (§3.7) ; borne MinY (§1.5) ; état 3.

### 3.4 Barre de menus [O]

- Dessinée dans la **couche de la barre de titre de l'écran**, d'abord passée devant toutes les autres
  (drapeau BACKDROP de cette couche effacé, UpfrontLayer).
- Fond : rectangle plein (0, 0)–(Screen.Width − 1, BarHeight − 1) en **BlockPen de la fenêtre active**.
- Titre de chaque menu ayant un MenuName : IntuiText {FrontPen = **DetailPen de la fenêtre**, BackPen =
  BlockPen, **JAM2**, LeftEdge = BarHBorder, TopEdge = BarVBorder, police = `Screen->Font`} imprimé en
  (Menu.LeftEdge, 0), donc texte en x = LeftEdge + BarHBorder, y = BarVBorder.
- Un menu sans MENUENABLED s'ouvre quand même : titre non surligné, boîte affichée avec tous ses
  éléments grisés, toute sélection donne MENUNULL [O, sonde]. Son titre est « grisé » par un remplissage à motif sur (BarHBorder + LeftEdge, 0)–(BarHBorder
  + LeftEdge + Width − 1, BarHeight − 1), motif 2 lignes **$4444 / $1111**, couleur BlockPen, JAM1.
- Fermeture : la barre de titre de l'écran est reconstruite (titre de l'écran) et la couche repasse
  derrière selon ShowTitle (spec écrans).

### 3.5 Boîtes d'éléments et de sous-éléments [O]

**Boîte englobante d'une liste d'éléments** (SetMenuStrip, sous-menus) : union, pour chaque élément, de
son rectangle (LeftEdge, TopEdge, Width, Height) et des étendues de ItemFill et SelectFill décalées de
(LeftEdge, TopEdge). Étendue d'un rendu : image ⇒ (L, T, L + W − 1, T + H − 1) ; IntuiText ⇒ (L, T,
L + IntuiTextLength − 1, **hauteur de police − 1**) — le bas ne tient pas compte de TopEdge ; rendu NULL ⇒
le rectangle de l'élément.

**Boîte d'éléments d'un menu** (coordonnées écran) :
- x0 = Menu.LeftEdge + BarHBorder + JazzX, x1 = Menu.LeftEdge + BarHBorder + BeatX ; si x0 < 0, la boîte
  est décalée à droite pour commencer en 0 ;
- y0 = **BarHeight − 1** (JazzY n'est pas utilisé), y1 = BarHeight − 1 + MenuVBorder + BeatY.
- Origine des éléments : (Menu.LeftEdge + BarHBorder, BarHeight − 1 + MenuVBorder) ; l'élément est en
  (origine.x + LeftEdge, origine.y + TopEdge).

**Boîte de sous-éléments** : boîte englobante des sous-éléments, élargie de MenuHBorder/MenuVBorder ;
gauche ≤ Item.Width − 1, droite ≥ 0, haut ≤ Item.Height − 1, bas ≥ 0 ; puis translatée de
(Menu.LeftEdge + BarHBorder + Item.LeftEdge, BarHeight − 1 + MenuVBorder + Item.TopEdge). Les
sous-éléments sont relatifs au coin (LeftEdge, TopEdge) de leur élément.

**Rendu d'une boîte** : dans un BitMap hors écran (même profondeur, AllocRaster par plan, largeur alignée
sur 16 pixels ; **échec d'allocation ⇒ la boîte n'est simplement pas affichée**) :
1. fond SetRast **BlockPen** (de la fenêtre active) ;
2. cadre en **DetailPen**, JAM1 : côtés verticaux de **2** pixels d'épaisseur, haut et bas de **1** ligne ;
3. pour chaque élément : ItemFill (image ou texte selon ITEMTEXT), police = `Screen->Font` ;
   - CHECKIT + CHECKED : image `Window->CheckMark` en (x de l'élément, y de l'élément + TopEdge du
     ItemFill) ;
   - COMMSEQ : caractère `Command` en x = x_élément + Width − largeur_car − 2, même y, IntuiText
     {DetailPen, 0, JAM1, police courante} ; symbole Amiga juste à gauche (x − largeur_image − 2) ;
   - élément sans ITEMENABLED, ou menu désactivé (pour les sous-éléments : menu **ou** élément
     désactivé) : grisé motif $4444/$1111 en BlockPen, JAM1, sur le rectangle de l'élément.
4. **SwapBitsRastPortClipRect** (layers) entre ce BitMap et le RastPort de l'écran : la boîte apparaît et
   le contenu de l'écran est conservé ; la fermeture refait l'échange. Les couches ne sont pas utilisées.

Images internes (Image, PlanePick 1, PlaneOnOff 0, déposées en chip) : coche haute résolution
LeftEdge 2, 15 × 8 ; coche basse résolution LeftEdge 2, 9 × 8 ; symbole Amiga haute résolution 23 × 8,
basse résolution 14 × 8 (choix selon HIRES du ViewPort de l'écran). Les bits à 1 sont le **fond** (couleur
1) et le dessin est en 0 (couleur 0) : ces images supposent BlockPen = 1. Motifs (# = 1) :

```
coche hires (15x8)     coche lores (9x8)   Amiga hires (23x8)          Amiga lores (14x8)
############...        ######...           ##...................##     #............#
###########..##        ######...           ..............####.....     ........###...
##########..###        #####..##           ............######.....     .......####...
#########..####        #####..##           ..........###..###.....     ......##.##...
....####..#####        ..##..###           ........###....###.....     .....##..##...
##...##..######        ...#..###           ......############.....     ....#######...
###.....#######        #....####           ...######.....######...     ..####..####..
####...########        ##...####           ##...................##     #............#
```

### 3.6 Surlignage [O]

- **Titre** : COMPLEMENT (masque $FF) sur (Menu.LeftEdge + **BarVBorder**, 0, Width, BarHeight) dans le
  RastPort de l'écran, seulement si MENUENABLED. Noter BarVBorder (et non BarHBorder comme pour le texte).
- **Élément / sous-élément** (seulement si menu, élément — et pour un sous-élément, lui-même — sont
  ITEMENABLED/MENUENABLED), en (x, y) = position écran de l'élément (§3.5), dans le RastPort de l'écran :
  - HIGHCOMP : RectFill COMPLEMENT (x, y)–(x + W − 1, y + H − 1) ;
  - HIGHBOX : cadre COMPLEMENT **à l'extérieur** : (x − 4, y − 2, W + 8, H + 4), côtés de 4 pixels,
    haut/bas de 2 lignes ;
  - HIGHIMAGE : dessine SelectFill (ou ItemFill pour éteindre) ;
  - HIGHNONE : rien.
  Le bit HIGHITEM de l'élément suit l'état allumé/éteint.

### 3.7 Suivi du pointeur (état 3, à chaque événement) [O]

Tests de position (coordonnées de l'**écran actif**) :
- titre n : Screen.MouseX − **BarVBorder** ∈ [LeftEdge, LeftEdge + Width) et Screen.MouseY ∈ [0, BarHeight) ;
- élément : x = Screen.MouseX − BarVBorder − Menu.LeftEdge, y = Screen.MouseY − BarHeight − MenuVBorder + 1,
  dans [LeftEdge, LeftEdge + Width) × [TopEdge, TopEdge + Height) ; sous-élément : idem, moins (Item.LeftEdge,
  Item.TopEdge). Le premier élément de la liste qui contient le point gagne ; les éléments désactivés
  sont « touchés » (ils deviennent l'élément courant) mais ne sont ni surlignés ni sélectionnables.

Règles (dans l'ordre, s'arrêter au premier cas qui s'applique) :
1. Une boîte de sous-éléments est affichée : pointeur sur un sous-élément ⇒ (si différent du courant)
   éteindre l'ancien, rallumer l'élément parent s'il était éteint, allumer le nouveau ; sinon éteindre
   l'ancien sous-élément et continuer.
2. Une boîte d'éléments est affichée : pointeur sur un élément ⇒ (si différent) retirer la boîte de
   sous-éléments, éteindre l'ancien élément, allumer le nouveau ; **s'il a des sous-éléments, leur boîte
   est affichée immédiatement** (sans délai) et le sous-élément sous le pointeur éventuellement allumé.
   Sinon (hors éléments) : l'élément est éteint ; **la boîte de sous-éléments reste affichée** ; élément
   courant := NOITEM ; continuer.
3. Pointeur sur un titre : retirer la boîte de sous-éléments ; si c'est un autre menu, retirer la boîte
   d'éléments, éteindre l'ancien titre, allumer le nouveau et afficher sa boîte ; élément et
   sous-élément courants := aucun.
4. Ailleurs : rien ne change (le dernier menu reste affiché).

### 3.8 Sélection : CHECKIT, MENUTOGGLE, MutualExclude, chaîne NextSelect [O]

À l'ouverture d'un menu (et à l'activation d'une fenêtre), dans **toute** la barre : Menu.Flags &= ~MIDRAWN ;
éléments &= ~(MENUTOGGLED | HIGHITEM | ISDRAWN) ; sous-éléments &= ~(MENUTOGGLED | HIGHITEM).

« Sélectionner le code courant » (au MENUUP ; à chaque événement tant que le bouton **gauche** est tenu
pendant le menu ; au SELECTDOWN pendant le menu, après avoir effacé MENUTOGGLED partout) :
1. élément NOITEM ⇒ rien ; menu non MENUENABLED ⇒ rien ; élément non ITEMENABLED ⇒ rien ; élément ayant
   des sous-éléments mais pointeur sur aucun ⇒ rien ; sous-élément non ITEMENABLED ⇒ rien.
2. CHECKIT : si MENUTOGGLED est déjà posé (déjà basculé depuis le dernier clic) ⇒ **arrêt complet** ;
   sinon CHECKED posé s'il ne l'était pas, ou effacé s'il l'était **et** que MENUTOGGLE est présent ;
   MENUTOGGLED posé.
3. NextSelect de l'élément := MENUNULL, puis **chaînage** : si la tête (premier code) est MENUNULL elle
   devient ce code. Sinon on parcourt la chaîne depuis la tête : un maillon qui pointait sur ce code
   prend le NextSelect de l'élément (MENUNULL) — ce qui **coupe** la chaîne à cet endroit — et le code est
   ajouté en queue. Cas particulier : si l'élément **est** la tête, son NextSelect vient d'être remis à
   MENUNULL et la chaîne se réduit à la tête. [O ; vérifié par la sonde §5]
4. **MutualExclude** : pour chaque bit i à 1 (i = rang dans la liste des éléments — ou des sous-éléments
   du même élément), le i-ème frère qui est CHECKIT et CHECKED perd CHECKED (le bit de l'élément lui-même
   n'est pas exclu : il se décocherait). Appliqué même si l'élément n'est pas CHECKIT.
5. Si un CHECKED a changé et que la boîte est affichée : la boîte concernée est redessinée (retirée, rendue,
   remise) et l'élément rallumé.

### 3.9 Fermeture (MENUUP dans l'état 3) [O]

Ordre : sélection du code courant (§3.8) ; codes courants := MENUNULL ; MENUSTATE effacé ; bornes du
pointeur rétablies ; boîte de sous-éléments puis boîte d'éléments retirées ; **UnlockLayers** ; barre de
titre de l'écran rétablie, réparation des couches endommagées (REFRESHWINDOW éventuels) ; **MOUSEBUTTONS
MENUUP** ($E9) à **toutes** les fenêtres de l'écran actif qui ont MENUVERIFY **et** MOUSEBUTTONS (fenêtre
active comprise) ; enfin **MENUPICK** à la fenêtre active, Code = tête de chaîne (MENUNULL si rien).
Le titre resté en surbrillance n'est pas « éteint » séparément : la barre est reconstruite. [O]

- Bouton gauche pendant le menu : SELECTDOWN ⇒ MENUTOGGLED effacé partout, sélection du code courant, et
  tant que le gauche est tenu chaque événement sélectionne le code sous le pointeur (glisser en
  sélectionnant) ; SELECTUP ⇒ fin de ce mode. Ces boutons ne produisent aucun message. [O]

### 3.10 MENUCANCEL, RMBTRAP [O]

- Réponse **MENUCANCEL** au MENUHOT : aucun menu, aucune barre, aucun MENUWAITING ; état 11 : les
  événements suivants sont distribués normalement ; au MENUUP, la fenêtre active reçoit **MOUSEBUTTONS
  $E9** (si elle a MOUSEBUTTONS). Le MENUDOWN lui-même n'est pas renvoyé.
- **RMBTRAP** : §2.6 ; MENUDOWN et MENUUP arrivent en MOUSEBUTTONS.

### 3.11 Raccourcis clavier (Amiga droite) [O]

Conditions : enfoncement, qualificatif avec RCOMMAND ($80), conversion `RawKeyConvert` (keymap par défaut)
en exactement un caractère, `car & $5F` ≠ 0, fenêtre active **sans** INREQUEST ($4000), MENUSTATE ($8000) ni
RMBTRAP ($10000).
1. Recherche dans la barre de la fenêtre active, dans l'ordre menus → éléments → sous-éléments : pour un
   élément **sans** sous-éléments, comparer `Command & $5F` ; pour un élément **avec** sous-éléments, ne
   comparer **que** ses sous-éléments. Le drapeau COMMSEQ **n'est pas testé** (seul `Command` compte). Le
   premier trouvé gagne. Rien trouvé ⇒ l'événement continue comme une touche normale (RAWKEY…).
2. Trouvé : MENUVERIFY MENUHOT à la fenêtre si elle l'a ; réponse MENUCANCEL ⇒ pas de sélection ; sinon
   remise à zéro des drapeaux de travail (comme une ouverture) et sélection du code (§3.8, sans dessin) —
   ce qui refuse les menus, éléments ou sous-éléments désactivés.
3. **MENUPICK** à la fenêtre active avec le code, **ou MENUNULL** si la sélection a été refusée ou annulée.
4. L'événement est avalé (classe IECLASS_NULL) : le relâchement de la touche, lui, arrive normalement.

### 3.12 DMRequest (double-clic droit) [O]

Si la fenêtre active a un DMRequest (Window +$28) au MENUDOWN accepté : la **barre** est affichée, les
couches ne sont pas verrouillées, temps de départ := horodatage de l'événement, position := souris de la
fenêtre ; état 2. Puis, pour chaque événement :
- pointeur dans une fenêtre de **±10 pixels en X et ±5 en Y** autour du départ et `DoubleClick` vrai :
  - deuxième MENUDOWN (après un relâchement) : barre retirée ; **REQVERIFY** (Code 0) ; si la fenêtre est
    toujours active : le requester reçoit REQACTIVE ; s'il est POINTREL, LeftEdge/TopEdge := (RelLeft +
    MouseX, RelTop + MouseY) ramenés dans la fenêtre (moins les bordures si GIMMEZEROZERO) ; `Request()` ;
    succès ⇒ **REQSET** (Code 1) et état 7 ;
  - premier relâchement (MENUUP) : barre retirée, on attend le second clic ;
  - autre événement de souris ou tic : on attend ;
  - autre classe (touche…) : si le bouton a déjà été relâché ⇒ barre retirée et **MENUPICK MENUNULL** ;
    sinon le menu s'ouvre normalement.
- hors de la fenêtre de position ou délai dépassé : bouton encore tenu ⇒ **menu normal** (§3.3 point 5,
  l'événement courant est déjà traité comme un événement de menu) ; bouton relâché ⇒ **MENUPICK
  MENUNULL** et barre retirée.

### 3.13 Ce qui est gelé pendant un menu [O sauf mention]

- **Toutes les couches de l'écran du menu sont verrouillées** (LockLayers) : toute tâche qui dessine dans
  une fenêtre de cet écran (ou crée/déplace une couche) **attend** la fermeture. Les autres écrans ne sont
  pas touchés. [O ; blocage des tâches : D, par la sémantique de LockLayers]
- Le **verrou d'état** d'intuition reste pris (§1.2) : SetMenuStrip, ClearMenuStrip, OnMenu, OffMenu,
  LockIBase(0)… appelés par une autre tâche attendent.
- Actions différées : §1.10 (activation perdue, autres reportées).
- Pas de MOUSEMOVE, pas de touches (avalées) ; INTUITICKS continuent.
- Pendant chaque **attente de vérification** (MENUVERIFY, SIZEVERIFY, REQVERIFY) : la tâche input.device
  est bloquée, plus rien ne bouge (pointeur compris), mais le verrou d'état est relâché.
- Glisser/redimensionner une fenêtre (état 12) : LockLayers aussi, cadre fantôme en XOR. [O]

---

## 4. Ce qui diffère sur un vrai A500 [D sauf mention]

- **Vitesse de la souris** : la ROM ne fait aucune accélération (§1.6). Une souris réelle remonte ses
  comptes par gameport.device à chaque trame où elle a bougé ; avec PointerTicks = 1 (prefs WB 1.3), un
  compte = un pixel haute résolution = ½ pixel basse résolution. Un émulateur qui convertit les
  mouvements de la souris hôte avec un autre facteur, ou qui regroupe les mouvements, change la sensation
  mais pas la logique. [O pour la ROM]
- **Double-clic** : durée des prefs (ROM 1,5 s ; WB 1.3 1,1968 s, `intuition-prefs-v34.md`) comparée aux
  `ie_TimeStamp` posés par input.device (TR_GETSYSTIME) : granularité d'une trame (20 ms PAL, 16,7 ms NTSC).
- **Latences** : les actions différées et la fin de DisplayBeep attendent le prochain événement ; sans
  activité, c'est le tic de 100 ms (5 trames PAL, 6 NTSC). Identique sur matériel réel.
- **Vérifications** : une application lente à répondre à MENUVERIFY fige réellement le pointeur sprite
  (aucun mouvement n'est appliqué tant que la tâche input.device attend) ; les mouvements de la souris
  pendant l'attente sont accumulés par gameport/le matériel et appliqués d'un coup ensuite.
- **Blitter et chip RAM** : les boîtes de menu sont rendues hors écran (AllocRaster ⇒ chip RAM) puis
  échangées par le blitter ; avec peu de chip libre, une boîte peut ne pas s'afficher du tout (§3.5) ;
  sur un A500 512 Ko + 512 Ko « slow », seule la chip compte.
- **Clavier** : sans souris, Amiga + flèches/Alt (§1.7) restent utilisables ; la répétition y ajoute
  l'accélération +6/+4 par répétition (cadence = KeyRptSpeed).

---

## 5. Vecteurs de test (vraie ROM 34.5, FS-UAE)

**Montage** : `tests/imenu_probe.sh <sortie> [durée]` (sonde `tests/imenu_probe.s`, bootblock à deux étages,
**sans DOS ni Workbench** : préférences par défaut de la ROM, donc PointerTicks = 2 et police d'écran
topaz **9** — 10 pixels de large). Deux fenêtres sur l'écran Workbench : **A** (0, 12, 400 × 120,
IDCMP $C37FE = NEWSIZE|REFRESHWINDOW|MOUSEBUTTONS|MOUSEMOVE|GADGETDOWN|GADGETUP|REQSET|MENUPICK|
CLOSEWINDOW|RAWKEY|REQCLEAR|MENUVERIFY|ACTIVEWINDOW|INACTIVEWINDOW, ACTIVATE, barre de 3 menus) et
**B** (420, 12, 210 × 100, IDCMP MOUSEBUTTONS|MENUVERIFY|ACTIVEWINDOW|INACTIVEWINDOW|RAWKEY, sans menu).
Menus : « Projet » (LeftEdge 0, Width 64 ; éléments 140 × 10 à TopEdge 0/10/20/30 : Ouvrir, Quitter
COMMSEQ 'Q', Grise désactivé, Sous-menu HIGHBOX avec deux sous-éléments à (100, 0) et (100, 10), le second
COMMSEQ 'S'), « Option » (72, 72 : Bascule CHECKIT|MENUTOGGLE, Excl A CHECKIT MutualExclude %100, Excl B
CHECKIT|CHECKED MutualExclude %010), « Off » (152, 56, désactivé ; un élément COMMSEQ 'D').
Les événements sont **injectés par input.device IND_WRITEEVENT** (positions absolues IECLASS_POINTERPOS
en unités IB, boutons, touches) avec `ie_TimeStamp` = (étape, rang) ; le journal (`M fen Class Code
Qualifier IAddress MouseX MouseY Seconds Micros`) est relu en série. Deux exécutions donnent des journaux
identiques (hors horodatages des tics).

**Géométrie mesurée** [O] : écran WB 640 × 256 ; BarHeight 11, BarVBorder 1, BarHBorder 5, MenuVBorder 2,
MenuHBorder 4, WBorTop 2, WBorLeft 4, WBorRight 4, WBorBottom 2 ; bornes IB 0..639 × 0..511
(+$544 = 511, +$546 = 640) ; Jazz/Beat après SetMenuStrip : Projet (−4, −2, 143, 41), Option
(−4, −2, 143, 31), Off (−4, −2, 143, 11) — conforme au calcul §3.2.

**Pixels relevés dans le BitMap de l'écran** (menu « Projet » ouvert, « Quitter » surligné) [O] :
- titre en surbrillance : colonnes **1..64**, lignes 0..9 (la ligne 10 est recouverte par la boîte) ;
  « Option » ouvert : colonnes 73..144 (= LeftEdge 72 + BarVBorder 1) ;
- boîte d'éléments : colonnes **1..148**, lignes **10..53** ; cadre couleur 0 de 2 colonnes (1–2 et
  147–148) et 1 ligne (10 et 53), fond couleur 1 ;
- élément 1 en HIGHCOMP : colonnes **5..144**, lignes **22..31** ; texte « Quitter » en x = 7 ;
- COMMSEQ : cellule du caractère en x = **133** (= 5 + 140 − TxWidth 10 − 2), symbole Amiga en x = **108**
  (= 133 − 23 − 2), même ligne que le texte (TopEdge 1) ;
- coche de « Excl A » (élément 1 de « Option ») : image en x = 79 (= 72 + 5 + LeftEdge d'image 2), y = 23 ;
- HIGHBOX de « Sous-menu » (élément 3, y = 42) : cadre complémenté colonnes 1..148, lignes 40..53, côtés
  de 4 colonnes, haut/bas de 2 lignes ;
- boîte de sous-éléments : colonnes **101..198**, lignes **40..63** ; sous-élément 1 surligné colonnes
  105..194, lignes 52..61.

**Journal** (extraits, IAddress `=A`/`=B` = la fenêtre ; horodatage = étape/rang injectés) :

```
READY
M A 00040000 0000 0000 =A 0000 FFF4 00000000 00000000   ACTIVEWINDOW d'OpenWindow (file différée, horodatage 0)
@T 1  clic dans B puis dans A
M A 00080000 0000 8000 =A 01F4 0030 1 2                 INACTIVEWINDOW(A) au SELECTDOWN
M B 00040000 0000 8000 =B 0050 0030 1 2                 ACTIVEWINDOW(B)
M B 00000008 0068 8000 =B 0050 0030 1 2                 MOUSEBUTTONS SELECTDOWN (même événement)
M B 00000008 00E8 8000 =B 0050 0030 1 3
@T 2  MENUDOWN sur « Projet », pointeur sur « Quitter », MENUUP
M A 00002000 0001 8000 00000000 0021 FFF9 2 2           MENUVERIFY MENUHOT à A
M B 00002000 0003 8000 00000000 FE7D FFF9 2 2           MENUVERIFY MENUWAITING à B
M A 00000008 00E9 8000 00000000 0047 000F 2 4           MOUSEBUTTONS MENUUP à A (MENUVERIFY + MOUSEBUTTONS)
M A 00000100 F820 8000 00000000 0047 000F 2 4           MENUPICK (menu 0, élément 1), IAddress = ie_X/ie_Y (0)
   P F820 2056                                         chaîne : 1 code, Flags avec HIGHITEM
M B 00000008 00E9 8000 00000000 FEA3 000F 2 4           MOUSEBUTTONS MENUUP à B aussi
@T 3  sélection multiple (clic gauche sur élément 0 puis 1), MENUUP hors boîte
M A 00000100 F800 ...                                  P F800 0052 / P F820 0056 (chaîne de 2)
@T 4  élément 0, élément 1, puis de nouveau élément 0 (la tête)
M A 00000100 F800 ...                                  P F800 0052 seul : chaîne coupée (§3.8 point 3)
@T 5  Option : Bascule ×2, Excl A, ouverture sans choix
   P F801 415B / P F801 405B                           CHECKED posé puis effacé (MENUTOGGLE), MENUTOGGLED
   P F821 4153                                         Excl A coché ; capture : Excl B décoché
M A 00000100 FFFF ...                                  MENUUP hors boîte : MENUNULL
@T 6  réponse MENUCANCEL
M A 00002000 0001 ... (MENUCANCEL)                     aucun MENUWAITING, aucune barre
M A 00000008 00E9 8000 =A 0047 0005 6 4                 MENUUP rendu en MOUSEBUTTONS, IAddress = fenêtre
@T 7  Amiga droite + q / s / d, puis Amiga gauche + q
M A 00002000 0001 0080 ... 6 4                          MENUVERIFY, horodatage de l'événement PRÉCÉDENT
M A 00000100 F820 0080 ... 6 4                          MENUPICK Quitter ; pas de MENUWAITING à B ; pas de RAWKEY $10
M A 00000400 0090 0080 00C05654 ...                    le relâchement arrive en RAWKEY
M A 00000100 0860 0080 ...                             'S' : sous-élément 1 de l'élément 3
M A 00000100 FFFF 0080 ...                             'D' : menu désactivé => MENUNULL (après MENUVERIFY)
M A 00000400 0010 0040 ... / 0090 0040                 Amiga gauche : RAWKEY ordinaires
@T 8  sous-menu : MENUPICK 0860 (pointeur en 146, 57 écran)
@T 9  élément « Grise » : MENUNULL ; menu « Off » : pas de surbrillance du titre, boîte grisée, MENUNULL
@T A  REPORTMOUSE, 6 positions injectées sans lire le port
M A 00000010 00FF 8000 =A 0064 0026 A 1  ... 0069 0029 A 6   6 MOUSEMOVE, aucune coalescence ; Qualifier
                                                       $8000 posé par la conversion POINTERPOS
@T B  RMBTRAP : MOUSEBUTTONS 0069 puis 00E9
@T C  VANILLAKEY : 'a' => 00200000 0061 (IAddress dans le message) ; relâchements, flèche ↑ : rien du tout
@T D  Amiga+→ (1 : pas de mouvement visible, PointerTicks 2), Shift (+50), répétitions (+53, +56),
      Amiga+↑ (−1) ; Amiga gauche + Alt gauche => MOUSEBUTTONS 0068 qual 0050 ; relâchement d'Alt =>
      MOUSEBUTTONS 00E8 puis RAWKEY 00E4
@T E  clic sur le fond de l'écran : INACTIVEWINDOW(A) seul ; touche 'a' : aucun message (transmise)
@T F  B active (sans barre de menus) + MENUDOWN : MENUVERIFY MENUHOT à B, MENUWAITING à A, barre vide
      (fond BlockPen), MOUSEBUTTONS MENUUP à A et B, MENUPICK non demandé par B
IDLE
```

---

## 6. Points non tranchés

1. **DMRequest** (§3.12) : décrit d'après la ROM seulement ; ni le double-clic, ni REQVERIFY, ni le
   placement POINTREL n'ont été sondés.
2. **SIZEVERIFY** et le glisser/redimensionner (état 12) : ROM seulement ; la durée exacte pendant laquelle
   les couches restent verrouillées pendant un glisser n'est pas mesurée.
3. **NEWSIZE envoyé à la fenêtre active** lors d'un SizeWindow sur une autre fenêtre (§2.3) : lu dans la
   ROM, non sondé (la sonde n'a pas appelé SizeWindow).
4. **Blocage des autres tâches** pendant un menu (LockLayers, verrou d'état) : déduit de la sémantique
   de LockLayers/ObtainSemaphore ; pas de sonde où une seconde tâche dessine ou appelle ClearMenuStrip
   pendant un menu ouvert.
5. **Abandon des ActivateWindow** demandés pendant un menu/gadget (§1.10) : ROM seulement.
6. **Allocation hors écran impossible** (§3.5, boîte non affichée) et **message non alloué ⇒ événement
   transmis** (§2.2) : ROM seulement.
7. **Cible des messages pendant un requester NOISYREQ**, état 10 (gadget chaîne : édition, UNDO,
   LONGINT, ActivateGadget) : hors périmètre de cette spec, non décrits.
8. **DISKINSERTED/REMOVED et NEWPREFS** : diffusion lue dans la ROM ; côté Workbench, voir
   `disk-change-v34.md` ; pas de sonde dédiée ici.
9. Le motif de grisé $4444/$1111 est lu dans la ROM ; son alignement exact (origine du motif = ligne 0 du
   RastPort de l'écran ou de la couche) n'a pas été vérifié pixel à pixel.
10. **Méthode** : sous FS-UAE 3.2.35, écrire le port série caractère par caractère pendant l'activité
    des menus a provoqué des blocages (« out of event2's! » dans le journal de FS-UAE : file d'événements
    saturée, interruption de niveau 6 restée active) ; la sonde tamponne donc son journal en RAM et ne le
    vide qu'aux marqueurs. Ce n'est **pas** un comportement de la ROM (cf. mémoire projet sur les IRQ CIA
    perdues par FS-UAE) ; à refaire sous WinUAE si un doute subsiste.
11. Valeurs de vitesse au clavier (+6/+4, 100/75) mesurées seulement avec PointerTicks = 2 ; le cas 1 est
    déduit de la formule d'accumulation.

---

## Relecture clean-room

- [x] Aucune suite d'instructions transcrite ni paraphrasée, aucune adresse de routine de la ROM ;
  seuls des offsets de structures publiques, des champs privés d'IB, des constantes d'ABI, des numéros
  d'alerte et des valeurs mesurées.
- [x] Les motifs des images internes (coche, symbole Amiga) sont des données visuelles observables à
  l'écran, reproduites pour un rendu pixel-identique.
- [x] Les sondes citées sont du code auteur (`tests/`, en-tête « ASSET DE TEST, PAS du code ROM »).
