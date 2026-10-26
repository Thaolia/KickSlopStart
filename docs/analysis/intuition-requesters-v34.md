# intuition-requesters-v34.md — Request / EndRequest / InitRequester / AutoRequest (intuition 34.3)

> Piste ANALYSE (« dirty »). Sources : ROM `assets/kick34005.A500` (intuition 34.3) et
> `SYS:System/DiskCopy` de `wb133.adf` (« DiskCopy 1.4 », `$VER: diskcopy 36.6`). (Adresses de
> routines ROM retirées du document : elles n'apportent rien à l'implémentation.)
>
> **Légende** : **[O]** observé · **[D]** déduit · **[S]** supposé. Comportements, layouts
> d'ABI et constantes uniquement : **aucune suite d'instructions n'est reproduite**.

---

## 0. Réponse courte pour DiskCopy

**DiskCopy 1.4 n'appelle ni Request, ni EndRequest, ni InitRequester.** Le message « Place SOURCE
disk ( FROM disk ) in drive DF0: » et les boutons Continue/Cancel viennent d'**AutoRequest
(−348)** [O]. En 1.3, AutoRequest est construit **sur** BuildSysRequest, qui ouvre une **nouvelle
fenêtre** contenant un **Requester** posé par Request (§5). Un AutoRequest fidèle exige donc
Request et EndRequest fonctionnels, **ou** une implémentation d'AutoRequest qui produit le même
résultat visible (§5.4).

---

## 1. Layouts d'ABI [O]

### 1.1 `struct Requester` (V34) — taille **$70 = 112 octets**

| Off. | Taille | Champ |
|---|---|---|
| +$00 | ptr | OlderRequest (chaînage, le plus récent en tête) |
| +$04 | WORD | LeftEdge (relatif à la fenêtre, voir §2.2) |
| +$06 | WORD | TopEdge |
| +$08 | WORD | Width |
| +$0A | WORD | Height |
| +$0C | WORD | RelLeft (POINTREL) |
| +$0E | WORD | RelTop |
| +$10 | ptr | ReqGadget (liste de gadgets) |
| +$14 | ptr | ReqBorder |
| +$18 | ptr | ReqText (IntuiText) |
| +$1C | UWORD | Flags : POINTREL $0001, **PREDRAWN $0002**, **NOISYREQ $0004**, REQOFFWINDOW $1000, **REQACTIVE $2000**, SYSREQUEST $4000, DEFERREFRESH $8000 |
| +$1E | UBYTE | BackFill (stylo du fond) |
| +$20 | ptr | ReqLayer |
| +$24 | 32 o. | ReqPad1 |
| +$44 | ptr | ImageBMap (PREDRAWN) |
| +$48 | ptr | RWindow |
| +$4C | 36 o. | ReqPad2 |

### 1.2 Champs de `struct Window` concernés

| Off. | Champ |
|---|---|
| +$18 | Flags : **INREQUEST $4000** |
| +$24 | FirstRequest |
| +$28 | DMRequest |
| +$2C | ReqCount (WORD) |
| +$52 | IDCMPFlags : REQSET $80, REQCLEAR $1000, REQVERIFY $800 |
| +$78 | UserData : utilisé par BuildSysRequest, voir §5.2 |

---

## 2. Request(req, win) (−240) [O sauf mention]

### 2.1 Effets, dans l'ordre

1. `req->RWindow` := win, `req->ReqLayer` := NULL, `req->OlderRequest` := `win->FirstRequest`.
2. **Création de la couche** (§2.2). Si elle échoue ⇒ **retour FALSE**, et rien n'est chaîné.
3. **Chaque gadget de `ReqGadget` reçoit le bit REQGADGET ($1000)** dans GadgetType.
4. `win->FirstRequest` := req ; **`win->ReqCount` += 1** ; **`win->Flags` |= INREQUEST**.
5. Dessin du requester sous LockLayerInfo (§2.3).
6. Si le dessin a réussi : **deux événements différés** sont mis en file pour la tâche
   d'entrée :
   - **classe 9, code 1** ⇒ message IDCMP **REQSET ($80)** à la fenêtre, si elle l'a demandé.
     La table interne fait correspondre classe 9 + code ≠ 0 à REQSET et classe 9 + code 0 à
     REQCLEAR [O pour la table, D pour l'acheminement] ;
   - un second événement (code interne 11) qui marque l'état « requester actif » pour la
     fenêtre active [O ; rôle exact S].
7. **Valeur de retour** : TRUE si la couche et le dessin ont réussi, sinon FALSE.

### 2.2 Couche du requester

- **Origine** : `win->LeftEdge + req->LeftEdge`, `win->TopEdge + req->TopEdge`.
  - Dans une fenêtre **GIMMEZEROZERO**, s'ajoutent BorderLeft/BorderTop : le requester est alors
    relatif à la **zone intérieure**.
  - **POINTREL et RelLeft/RelTop ne sont pas utilisés par Request** [O par absence] ; ils ne
    servent qu'au double-menu (DMRequest).
- **Taille** : Width/Height du requester, **rognés** à la place disponible :
  - fenêtre non GZZ : jusqu'à `Width − BorderRight` / `Height − BorderBottom`, comptés depuis le
    bord gauche ou haut de la fenêtre ;
  - fenêtre GZZ : jusqu'à GZZWidth / GZZHeight.
  - Si la taille rognée est ≤ 0 : **pas de couche** (une couche existante est supprimée), mais
    Request réussit quand même et le requester est chaîné, sans rien d'affiché.
- **Type** : **CreateBehindLayer** (layers −42), flags **LAYERSMART (2)**, sans super-bitmap,
  sur le BitMap de l'écran. `layer->Window` := win.
- **Profondeur** : la couche est placée **juste devant** la couche du requester précédent
  (`OlderRequest->ReqLayer`) s'il y en a un, sinon devant **`win->WLayer`**, par
  **MoveLayerInFrontOf** (layers −168). Elle est donc devant la fenêtre et sous les autres
  fenêtres placées au-dessus.

### 2.3 Rendu

- `req->Flags |= REQACTIVE`.
- Initialisation des PropInfo des gadgets proportionnels du requester (bordures du conteneur,
  comme pour les fenêtres).
- Sans couche ⇒ rien n'est dessiné.
- **PREDRAWN** : **BltBitMapRastPort** (graphics −606) de `ImageBMap` vers le RastPort de la
  couche, à (0,0), sur Width × Height, minterm $C0.
  Ni bordure, ni texte, ni fond ne sont dessinés ; **seuls les gadgets le sont** [O : la branche
  PREDRAWN ne fait que la copie ; les gadgets sont D, voir la remarque].
- **Sinon**, dans un RastPort cloné sur la couche (police de l'écran) :
  1. **RectFill du fond** (0,0)–(Width−1, Height−1) avec le stylo **BackFill**, en JAM1 ;
  2. **DrawBorder(ReqBorder, 0, 0)** ;
  3. **PrintIText(ReqText, 0, 0)** ;
  4. **rendu de la liste ReqGadget** (routine commune, à rebours : le premier de la liste est
     dessiné en dernier, voir `intuition-gzz-v34.md` §6).

Remarque : dans la branche PREDRAWN, le rendu des gadgets n'apparaît pas dans la même routine.
Il intervient par le rafraîchissement de la couche [S].

### 2.4 Domaine des gadgets du requester [O]

Pour un gadget REQGADGET :
- **domaine** = (req LeftEdge, req TopEdge, Width, Height), plus BorderLeft/Top si la fenêtre
  est GZZ ;
- **couche de rendu** = ReqLayer.

Les coordonnées des gadgets sont donc **relatives au coin du requester**, et les GRELxxx
relatives à sa largeur et à sa hauteur.

---

## 3. Entrées pendant un requester [O sauf mention]

### 3.1 Bouton gauche (SELECTDOWN)

- La recherche du gadget sous le pointeur se fait **seulement dans la fenêtre active** :
  - pointeur au-dessus de la couche du **premier** requester (`FirstRequest->ReqLayer`) ⇒ on
    parcourt **sa liste ReqGadget**, à l'endroit (le premier qui contient le point gagne) ;
  - sinon ⇒ on parcourt la liste de la fenêtre.
- Quand la fenêtre a un requester, **seuls les gadgets REQGADGET ou SYSGADGET ($8000) sont
  acceptés**. Les gadgets d'application de la fenêtre sont **inertes**.
  - Le gadget de **fermeture** système est lui aussi **refusé** : son clic est ignoré.
  - Les autres gadgets système (glisser, profondeur, taille) **restent utilisables**.
- Les gadgets GADGDISABLED ne sont jamais retenus.
- Clic dans **une autre fenêtre** ou sur un autre écran ⇒ traitement normal : on peut changer
  de fenêtre active.
- **Seul le requester le plus récent** (FirstRequest) reçoit les clics.

### 3.2 Autres événements (touches, bouton droit, déplacements…)

- Requester **NOISYREQ** ⇒ les événements passent à la fenêtre comme d'habitude.
- Sinon ⇒ ils sont **avalés**.
- Les **menus** : dans ce cas, le bouton droit n'ouvre pas les menus de la fenêtre [D, par
  « avalé »].

### 3.3 Messages des gadgets du requester

- GADGETDOWN / GADGETUP sont envoyés selon les règles normales (GADGIMMEDIATE / RELVERIFY), avec
  **IAddress = le gadget** [D : chemin commun des gadgets].
- **ENDGADGET** (Activation $0004), au relâchement :
  - le requester `FirstRequest` est **retiré** (§4.1) ;
  - un événement **classe 9 code 0 ⇒ REQCLEAR** est mis en file ;
  - **ReqCount −= 1**, et si le compte tombe à 0, **INREQUEST est effacé** ;
  - la fenêtre est ensuite réparée.
  - Le REQCLEAR part ici **à chaque** requester terminé par ENDGADGET [O].

---

## 4. EndRequest(req, win) (−120) et InitRequester (−138) [O]

### 4.1 Retrait commun (EndRequest et ENDGADGET)

1. `req->Flags &= ~REQACTIVE`.
2. Recherche de `req` dans la chaîne `win->FirstRequest`. **S'il n'y est pas ⇒ rien n'est
   fait** (EndRequest revient sans effet).
3. Retrait de la chaîne. On peut retirer un requester qui n'est pas en tête.
4. **DeleteLayer(0, ReqLayer)**, puis `ReqLayer` := NULL. Les layers réparent la zone découverte.

### 4.2 Suite propre à EndRequest

- **ReqCount −= 1**. S'il tombe à **0** :
  - événement **classe 9 code 0 ⇒ REQCLEAR** ;
  - **INREQUEST effacé**.
- Dans tous les cas, un événement de **réparation de la fenêtre** est ensuite mis en file.
- Pas de valeur de retour significative.

### 4.3 InitRequester(req)

**Met à zéro les 112 ($70) octets** de la structure, et rien d'autre [O].

### 4.4 SetDMRequest (−258) / ClearDMRequest (−48)

- **SetDMRequest(win, req)** : `win->DMRequest` (+$28) := req, **sauf** si le DMRequest courant
  est actif (REQACTIVE) ⇒ refus, retour FALSE. Sinon TRUE.
- **ClearDMRequest(win)** : même routine avec NULL, donc refusée si le DMRequest est actif.
- Leur affichage par double clic du bouton droit (DMRequest, POINTREL) n'est pas utilisé par
  DiskCopy et n'a pas été analysé.

---

## 5. AutoRequest (−348) / BuildSysRequest (−360) / FreeSysRequest (−372) [O sauf mention]

### 5.1 AutoRequest(win, body, pos, neg, pflag, nflag, W, H)

1. **IDCMP de la fenêtre créée** = `pflag | nflag | GADGETUP ($40) | RAWKEY ($400)`.
2. Appel de **BuildSysRequest(win, body, pos, neg, IDCMP, W, H)**. S'il rend **0 ou 1**,
   c'est-à-dire le repli Alert (§5.3), ce résultat est **directement** la valeur de retour.
3. Si l'écran de la fenêtre créée n'est pas le premier écran ⇒ **ScreenToFront** de cet écran.
4. **Boucle** : GetMsg sur le UserPort de la fenêtre créée, Wait sur son signal quand le port
   est vide. Pour chaque message :
   - classe ∈ **nflag** ⇒ **FALSE** ;
   - classe ∈ **pflag** ⇒ **TRUE** ;
   - **GADGETUP** ⇒ **TRUE si GadgetID ≠ 0** (gadget positif), **FALSE si GadgetID = 0**
     (négatif) ;
   - **RAWKEY** avec **Amiga gauche** (bit $40 de l'octet de poids faible du qualifier) :
     - code **$34** (V) ⇒ TRUE, seulement si `pos` existe ;
     - code **$35** (B) ⇒ FALSE ;
   - tout autre message est ignoré.
   - **Les messages ne sont pas répondus** (pas de ReplyMsg dans la boucle). CloseWindow les
     récupère.
5. **FreeSysRequest(fenêtre)**, puis retour du booléen.

### 5.2 BuildSysRequest(win, body, pos, neg, idcmp, W, H)

1. **NewWindow** (modèle ROM) :
   - Left 0, Top 0, **Width = W, Height = H** ;
   - DetailPen/BlockPen : ceux de `win` (sinon $FF/$FF) ;
   - IDCMPFlags = idcmp ;
   - **Flags $00021047** : NOCAREREFRESH | ACTIVATE | SIMPLE_REFRESH | DEPTH | DRAG | SIZING ;
   - **Title** = `win->Title`, sinon **`"System Request"`** ;
   - **Screen** = `win->WScreen`, et **Type** = `Screen->Flags & $0F` (sinon WBENCHSCREEN) ;
   - **MinWidth 88, MinHeight 24, MaxWidth = W, MaxHeight = H**.
   OpenWindow. En cas d'échec ⇒ repli Alert (§5.3).
2. **Requester** de 112 octets alloué par AllocRemember (MEMF_PUBLIC|CLEAR), puis
   **InitRequester** :
   - LeftEdge = `newwin->LeftEdge + BorderLeft`, TopEdge = `newwin->TopEdge + BorderTop`.
     Comme la fenêtre est à (0,0), cela revient aux bordures ;
   - Width = W − BorderLeft − BorderRight, Height = H − BorderTop − BorderBottom ;
   - **BackFill = 1**, **Flags |= NOISYREQ** ;
   - **ReqBorder** = cadre construit à la taille du requester ;
   - **ReqText** = body.
3. **Gadgets**, alloués dans la Remember-list (44 octets chacun), s'il y a lieu :
   - **positif** (si `pos`) : **GadgetID = 1**, LeftEdge = **14** ;
   - **négatif** : **GadgetID = 0**, flag **GRELRIGHT** en plus ;
   - attributs communs [O] :
     - Flags **GRELBOTTOM ($0008)** ;
     - Activation **$0101** ;
     - GadgetType **REQGADGET | BOOLGADGET ($1001)** ;
     - **GadgetText = pos/neg** ;
     - Width = longueur du texte en pixels + 12 ;
     - Height = hauteur de police + 6 ;
     - TopEdge = −(Height + 4) ;
     - LeftEdge du négatif = −(Width + 13) ;
     - une bordure à leur taille.
   - Il n'y a **pas d'ENDGADGET** : la fin vient de GADGETUP, traité par AutoRequest.
4. **Request(req, newwin)**. En cas d'échec : CloseWindow, puis repli Alert.
5. La Remember-list est rangée dans **`newwin->UserData` (+$78)**. Retour : la fenêtre.

### 5.2.1 Détail graphique de BuildSysRequest [O sauf mention]

**Fabrique de bordure** `Cadre(W, H, retrait r, stylo p)`, utilisée pour toutes les bordures
ci-dessous :
- **une seule** `struct Border` (16 octets, MEMF_PUBLIC|CLEAR, dans la Remember-list) :
  - LeftEdge = 0, TopEdge = 0 ;
  - **FrontPen = p**, **BackPen = 0** ;
  - **DrawMode = JAM1 (0)** ;
  - **Count = 9** ;
  - NextBorder = NULL ;
  - XY = tableau de 36 octets (même allocation).
- Avec W' = W − 1, H' = H − 1 et s = r + 1, les **9 points** sont :

  `(r, r) (W'−r, r) (W'−r, H'−r) (r, H'−r) (r, r) (s, r) (s, H'−r) (W'−s, H'−r) (W'−s, r)`

  C'est un rectangle en retrait de `r`, suivi d'un second trait vertical décalé d'un pixel vers
  l'intérieur, de chaque côté : les montants font **2 pixels de large**, adaptés au hires.

**1. ReqBorder** :
- **une seule Border** = `Cadre(Width, Height du requester, r = 1, p = 0)`, soit un cadre
  **couleur 0** (bleu) en retrait d'1 pixel ;
- le fond est **BackFill = 1** (blanc), rempli par RectFill avant le dessin du cadre (§2.3).

**2. Gadgets positif et négatif** :
- **GadgetRender** = `Cadre(Wg, Hg, r = 1, p = 0)` (filet **bleu** intérieur), dont la
  **NextBorder** = `Cadre(Wg, Hg, r = −1, p = 3)` (rectangle **orange** 1 pixel **à l'extérieur**
  de la boîte du gadget).
  - Ordre de dessin : filet bleu, puis rectangle orange.
  - Les deux bordures sont seules dans leur allocation : 2 Border par gadget.
- **SelectRender = NULL**.
- **Flags = GRELBOTTOM ($0008)**, plus **GRELRIGHT ($0010)** pour le négatif. Le mode de
  surbrillance (bits 0–1) vaut 0, c'est-à-dire **GADGHCOMP** : inversion de la boîte au clic.
- **Activation = $0101**, **GadgetType = $1001** (REQGADGET | BOOLGADGET).
- **GadgetID** : 1 pour le positif, 0 pour le négatif.

**3. Textes** :
- **ReqText = `body`** et **GadgetText = `pos` / `neg`** sont les pointeurs de l'appelant,
  **utilisés tels quels**. LeftEdge, TopEdge, stylos, DrawMode, police et NextText ne sont pas
  modifiés : aucune écriture dans ces structures [O par absence].
  - Avec DiskCopy, les textes Continue et Cancel sont en FrontPen 3 (orange) et BackPen 1, JAM1,
    à (6,3).
- **Largeur du gadget** = largeur en pixels du **premier IntuiText seulement** (pas de parcours
  de NextText) + **12**. La mesure se fait par TextLength :
  - avec la police `ITextFont` si elle est donnée (ouverte et posée temporairement) ;
  - sinon avec la police du **RastPort de l'écran** (`Screen.RastPort`, +$54) ;
  - l'écran est celui de `win`, sinon le premier écran de type WBENCHSCREEN de la liste.
- **Hauteur du gadget** = hauteur de police + **6**. La hauteur est :
  - `ITextFont->ta_YSize` si `ITextFont` est donnée ;
  - sinon `Screen.RastPort.TxHeight` (écran, +$8E) ;
  - sinon une valeur par défaut d'IntuitionBase [S].
- **Position du gadget** :
  - TopEdge = −(Hauteur + 4), relatif au bas du requester (GRELBOTTOM) ;
  - **positif** : **LeftEdge = 14** ;
  - **négatif** : LeftEdge = −(Largeur + 13), relatif à la droite du requester (GRELRIGHT).
  - Avec le rectangle orange à r = −1, il reste donc 3 pixels de marge en bas et ~13 pixels à
    gauche et à droite par rapport au bord du requester (avant son propre cadre en r = 1).

**4. NewWindow de la fenêtre System Request** :
- **LeftEdge = 0, TopEdge = 0** (modèle ROM, jamais modifié) [O].
- **DetailPen / BlockPen = ceux de `win`** (`Window.DetailPen` +$62, `BlockPen` +$63) quand
  `win` est fourni ; sinon **$FF / $FF**, c'est-à-dire les stylos par défaut de l'écran.
- Title, Screen et Type comme en §5.2 point 1.

### 5.3 Repli Alert

Quand la fenêtre ou le requester ne peut pas être créé :
- l'Alert est **construite depuis les IntuiText** de body, pos et neg (une ligne par texte) ;
- elle porte les légendes ROM `"=LEFT BUTTON OK="` et `"=RIGHT BUTTON CANCEL="` ;
- elle est affichée par **DisplayAlert** (recoverable).
- Le résultat de DisplayAlert (TRUE bouton gauche / FALSE droit) est rendu comme 0 ou 1.

### 5.4 FreeSysRequest(win)

**EndRequest(win->FirstRequest, win)**, puis **FreeRemember(win->UserData, TRUE)**, puis
**CloseWindow(win)**.

---

## 6. Usage par DiskCopy 1.4 [O]

- **Bibliothèques** : intuition et graphics, ouvertes en version 0 ; aucune fonction de
  requester bas niveau.
- **Fenêtre** : sa propre fenêtre (OpenWindow), avec le titre d'écran posé par SetWindowTitles.
- **Invites** (« Place %s %s » / « ( FROM disk ) in drive %s »…) :
  `AutoRequest(sa fenêtre, IntuiText du corps, pos, neg, pflag, nflag, W, H)` avec :
  - **pos = `"Continue"`** et **neg = `"Cancel"`** (IntuiText FrontPen 3, BackPen 1, JAM1,
    position (6,3)) ;
  - **pflag = 0** et **nflag = CLOSEWINDOW ($200)** ;
  - **W = 343 ($157), H = 72 ($48)**.
  - Retour **FALSE** (Cancel, fermeture ou Amiga-B) ⇒ **sortie** de DiskCopy (code 10).
- **Autre requester** : `"Unable to open icon.library"`, en AutoRequest également, avec un
  corps différent.
- **Classes IDCMP attendues dans la fenêtre de l'AutoRequest** : **GADGETUP ($40)**, RAWKEY
  ($400), CLOSEWINDOW ($200, négatif).

**Minimum fidèle pour DiskCopy [D]** :
- AutoRequest doit ouvrir, sur l'écran de la fenêtre passée, une **fenêtre « System Request »**
  de W × H (ACTIVATE, DEPTH, DRAG, SIZING) dont la zone intérieure contient :
  - un fond de couleur 1 ;
  - un cadre ;
  - le texte du corps ;
  - **deux gadgets texte** en bas : `Continue` à gauche (ID 1) et `Cancel` à droite (ID 0).
- Il doit rendre TRUE sur GADGETUP du gadget d'ID ≠ 0, et FALSE sur l'ID 0 ou CLOSEWINDOW.
- Le passage par Request ne change que la structure interne. L'aspect et le comportement
  visible ne dépendent que de §5.2 et §5.1.

---

## 7. DiskCopy 1.4 : séquence entre OpenWindow et « Place SOURCE disk »

Cas traité : lancement depuis le Workbench, `sm_NumArgs = 2`, `ArgList[1] = { wa_Lock = racine
de DF0:, wa_Name = "" }`, un seul lecteur. Les conditions de sortie silencieuse d'avant la fenêtre
sont dans `workbench-task-v34.md` §7.9.1. Toutes les étapes ci-dessous sont **[O]** sauf mention.

### 7.1 Ordre des appels

1. **intuition SetWindowTitles (−276)** (fenêtre, −1, `"DiskCopy"`).
2. **Résolution de la DESTINATION** (ArgList[1]).
   - Avec 2 arguments, source et destination désignent le même WBArg, donc le même wa_Lock.
     DiskCopy note alors « même disque » et ne fait pas les contrôles propres à la destination.
   - Contrôle préalable : le nom passé pour la destination doit être vide, sinon sortie
     silencieuse. Dans le cas « même disque », ce nom est un tampon interne (vide), pas wa_Name.
     wa_Name ne sert ensuite qu'à la source, comme nom de device (vide ⇒ recherche par tâche).
   - Appels, dans l'ordre :
     1. **dos ParentDir (−210)** (wa_Lock) ; s'il rend une valeur ≠ 0 : UnLock, puis sortie ;
     2. **dos IoErr (−132)** ; s'il rend ≠ 0, erreur puis sortie ;
     3. **dos Info (−114)** (wa_Lock, InfoData de 36 octets) ;
     4. **dos Examine (−102)** (wa_Lock, FIB de 260 octets) ;
     5. **dos UnLock (−90)** (wa_Lock), puis **wa_Lock := 0** dans le WBArg.
   - Recherche du device **sans appel système et sans Forbid** : parcours direct de `dl_Root →
     rn_Info → di_DevInfo`, à la recherche du nœud `dn_Type = 0` dont `dn_Task` vaut
     `id_VolumeNode → dol_Task` (§7.9.1 de workbench-task). Résultat : le nom `"DF0:"`.
3. **Résolution de la SOURCE** sur le **même** WBArg, dont **wa_Lock vaut maintenant 0** :
   - pas de ParentDir/Info/Examine (branche « sans lock ») ;
   - un éventuel `':'` final est retiré du nom (vide) ;
   - le libellé `"SOURCE disk"` est pris ;
   - le device est recherché comme ci-dessus, **avec l'InfoData de l'étape 2** (même tâche).
4. **dos DeviceProc (−174)** (`"DF0:"`) pour la source, puis pour la destination. Les deux
   ports sont comparés pour savoir s'il s'agit du même lecteur.
5. **Paquet ACTION_INHIBIT (31), Arg1 = 1 (DOSTRUE)**, envoyé **directement** au port rendu par
   DeviceProc pour la source. La destination n'en reçoit un que si c'est un autre port. Détail
   en §7.2. Si `dp_Res1 = 0`, erreur puis sortie.
6. **Géométrie** : `dn_Startup` (+$1C, BPTR → FileSysStartupMsg) → `fssm_Environ` (+$08, BPTR
   → DosEnvec). Champs lus :
   - `de_Surfaces` (+$0C) ;
   - `de_BlocksPerTrack` (+$14) ;
   - `de_Reserved` (+$18) ;
   - `de_LowCyl` (+$24) ;
   - `de_HighCyl` (+$28).
   Calculs :
   - nombre de cylindres = HighCyl − LowCyl + 1 ;
   - taille d'un cylindre = BlocksPerTrack × 512 × Surfaces.
   La source et la destination doivent avoir la même géométrie, sinon erreur puis sortie.
   **Aucune protection contre `dn_Startup` ou `fssm_Environ` nuls** : un pointeur nul serait
   déréférencé.
7. **exec AllocMem**(taille d'un cylindre, MEMF_CHIP|MEMF_CLEAR) : tampon de vérification.
8. **Tampons de cylindres**, sans appel autre qu'AllocMem et FreeMem :
   - un tableau de (cylindres + 1) pointeurs (MEMF_PUBLIC|CLEAR) ;
   - en mono-lecteur, des cylindres sont alloués un à un (le premier en CHIP|CLEAR, les
     suivants en PUBLIC|CLEAR) **jusqu'à l'échec d'une allocation**, ou jusqu'à couvrir tous les
     cylindres ;
   - au premier échec, **le tampon précédent est rendu**, pour laisser de la marge ;
   - le nombre de tampons est ensuite équilibré entre les passes, et les tampons en trop sont
     rendus.
   - Si aucun tampon n'a pu être alloué : **AutoRequest « Not enough memory… »** (Continue ou
     Cancel), puis nouvel essai.
9. **Mono-lecteur avec moins de cylindres/4 tampons** :
   - tous les tampons sont rendus ;
   - **AutoRequest « Notice: This will take N swaps. »** ;
   - réallocation ;
   - le texte « Diskcopy will take %d swaps. » est **écrit dans la fenêtre** (graphics Move et
     Text) ;
   - puis **dos Delay (−198)(15)**.
   Sinon cette étape est sautée.
10. **exec OpenDevice (−444)**(nom = `fssm_Device` (+$04, BSTR), unité = `fssm_Unit` (+$00),
    IOExtTD de 52 octets créée par CreateExtIO, **flags 0**), pour la source puis pour la
    destination. Un échec donne une erreur puis la sortie. Les flags de `fssm_Flags` ne sont pas
    utilisés.
11. Préparation des deux requêtes :
    - `ln_Type` := **7 (NT_REPLYMSG)** ;
    - `io_Error` := 0 ;
    - un champ privé reçoit `de_LowCyl`.
12. **exec CheckIO (−468)** (requête source) : elle rend « terminée » grâce au NT_REPLYMSG posé
    juste avant. Sinon **WaitIO (−474)** serait appelé.
13. **exec DoIO (−456)** (requête source, **io_Command = 9 (TD_MOTOR)**, **io_Length = 0**) :
    **arrêt du moteur, synchrone**.
14. Construction du texte « Place SOURCE disk ( FROM disk ) in drive DF0: », puis **intuition
    AutoRequest (−348)** (§6).

**Aucune autre commande trackdisk** (TD_CHANGESTATE, TD_PROTSTATUS, TD_ADDCHANGEINT,
TD_CHANGENUM…) n'est envoyée avant cette demande. Elles viennent après la réponse Continue.

### 7.2 Paquet ACTION_INHIBIT : forme exacte et attente [O]

- **Allocation** : **AllocMem(68, MEMF_PUBLIC)**, **sans MEMF_CLEAR**. Cela représente un
  `StandardPacket` : Message de 20 octets, puis DosPacket de 48 octets.
- **Champs remplis** :
  - `mn_Node.ln_Name` (+$0A) := adresse du DosPacket (+$14) ;
  - `dp_Link` (+$14) := le Message ;
  - **`dp_Port` (+$18) := `&FindTask(0)->pr_MsgPort`** (process +$5C) ;
  - **`dp_Type` (+$1C) := 31** ;
  - **`dp_Arg1` (+$28) := 1** (inhibit) ou 0 (fin de l'inhibit, à la sortie).
- **Champs NON remplis** : `mn_ReplyPort` (+$0E), `mn_Length`, `ln_Type` et les autres
  arguments gardent le **contenu aléatoire** de la mémoire allouée.
- **Envoi** : **exec PutMsg (−366)** (port du handler, message).
- **Attente** : **exec WaitPort (−384)** sur **`pr_MsgPort` du process DiskCopy**, puis **exec
  Remove (−252)** du message. Il n'y a **pas** de GetMsg : le message est simplement retiré de
  la liste du port.
- **Résultat** : `dp_Res1` (+$20). Puis FreeMem(68).

**⇒ Point de blocage le plus probable [D]** : DiskCopy attend la réponse **uniquement** sur son
`pr_MsgPort`, et `mn_ReplyPort` contient n'importe quoi. Le handler doit donc renvoyer le paquet
**par `dp_Port`**, selon la convention dos : PutMsg vers `dp_Port`, après avoir réécrit
`dp_Port` avec son propre port. S'il répond par `ReplyMsg()`, qui utilise mn_ReplyPort, ou s'il
ignore ACTION_INHIBIT sans répondre, DiskCopy reste **bloqué pour toujours dans WaitPort**. On
obtient alors exactement le symptôme constaté : fenêtre ouverte et vide, pas d'AutoRequest, pas
de fin du process.

### 7.3 Autres attentes susceptibles de ne jamais finir [D]

| Étape | Attente | Condition de blocage |
|---|---|---|
| 5 | WaitPort(pr_MsgPort) | pas de réponse à ACTION_INHIBIT par `dp_Port` (§7.2) |
| 9 | dos Delay(15) | timer.device ou Delay défaillant (seulement sur le chemin « swaps ») |
| 12 | WaitIO | seulement si CheckIO dit « pas terminé », ce qui n'arrive pas puisque ln_Type = 7 est posé juste avant |
| 13 | DoIO(TD_MOTOR) | trackdisk qui ne répond pas à TD_MOTOR |
| 8 | boucle d'AllocMem | ne boucle que tant que les allocations réussissent, au plus « cylindres » fois ; un AllocMem qui ne rend jamais 0 au-delà de la mémoire libre ferait tout prendre, et l'AutoRequest de l'étape 14 pourrait ensuite échouer faute de mémoire |
| 6 | lecture de DosEnvec | `dn_Startup` / `fssm_Environ` nuls ⇒ lecture à l'adresse 0, sans blocage mais avec des valeurs absurdes (division par 0 possible dans l'équilibrage des tampons [S]) |

**Ordre de vérification conseillé** :
1. Réponse d'ACTION_INHIBIT par `dp_Port` vers `pr_MsgPort`.
2. TD_MOTOR en DoIO.
3. Delay.
4. Mémoire laissée libre après l'étape 8 : la vraie ROM laisse environ un cylindre, soit 11 Ko
   pour une disquette DD.

---

## Relecture clean-room

- [x] Aucune suite d'instructions recopiée : uniquement des layouts publics (Requester, Window,
  NewWindow, Gadget, IntuiText), des constantes (Flags, IDCMP, GadgetType, Activation), des
  appels de librairie (layers CreateBehindLayer −42, MoveLayerInFrontOf −168, DeleteLayer ;
  graphics BltBitMapRastPort / RectFill ; intuition DrawBorder / PrintIText ; layers DeleteLayer −90) et des règles de comportement.
- [x] Les mécanismes internes (file d'événements différés, codes 9/10/11) sont décrits par leur
  effet observable (REQSET/REQCLEAR), sans transcription.
- [x] DiskCopy est décrit par ses appels publics et ses données (textes, flags, tailles).
- [x] §7 (relu) : séquence décrite par les appels publics (exec, dos, intuition, graphics,
  trackdisk), la forme du paquet dos (champs du StandardPacket) et les conditions d'attente.
  Aucune suite d'instructions recopiée.
- [x] §5.2.1 (relu) : bordures décrites par leurs paramètres (nombre, stylos, mode, liste des
  9 points en formule), gadgets et textes par leurs champs publics. Aucune suite d'instructions
  recopiée.
