# intuition-gzz-v34.md — bordures, couches et coordonnées des fenêtres (GIMMEZEROZERO ou non)

> Piste ANALYSE (« dirty »). Source : ROM `assets/kick34005.A500`, module intuition 34.3
> (OpenWindow à $FDEB1E, ajustement des bordures par les gadgets à $FDE95A, contexte de gadget
> à $FD5416/$FD5596/$FD532C, gadgets système à $FDF266/$FDE8E0, coordonnées souris à $FD8686,
> IntuiMessage à $FD59C8, rendu d'une liste de gadgets à $FD4AA6/$FD4B58, dessin de la fenêtre
> à $FDF8E8, AddGadget à $FD4ED2). Cas pratique : `libs/info.library` de `wb133.adf`.
>
> **Légende** : **[O]** observé · **[D]** déduit · **[S]** supposé. Les adresses ne sont que des
> repères. **Aucune suite d'instructions n'est reproduite** : seuls des règles de calcul, des
> champs de structures publiques (`intuition.h` 1.3) et des appels de librairie.

Champs `struct Window` utilisés : LeftEdge +$04, TopEdge +$06, Width +$08, Height +$0A,
MouseY +$0C, MouseX +$0E, Flags +$18, RPort +$32, BorderLeft/Top/Right/Bottom +$36/$37/$38/$39
(octets signés), BorderRPort +$3A, FirstGadget +$3E, IDCMPFlags +$52, GZZMouseX +$6C,
GZZMouseY +$6E, GZZWidth +$70, GZZHeight +$72, WLayer +$7C, IFont +$80.
`struct Screen` : MouseY +$10, MouseX +$12, WBorTop +$23, WBorLeft +$24, WBorRight +$25,
WBorBottom +$26, Font (TextAttr*) +$28, ViewPort.Modes +$4C (HIRES $8000), LayerInfo +$E0,
BarLayer +$14E.

---

## 1. Calcul des bordures à l'OpenWindow

### 1.1 Valeurs de base [O]

Dans cet ordre :

1. **Bordures de l'écran.** Si la fenêtre n'est **pas BORDERLESS** ($800) : BorderLeft,
   BorderTop, BorderRight et BorderBottom := WBorLeft, WBorTop, WBorRight et WBorBottom de
   l'écran. Sinon elles valent 0.
2. **Barre de titre.** Si la fenêtre a WINDOWDRAG, WINDOWDEPTH ou WINDOWCLOSE ($0E), **ou** un
   Title non nul : **BorderTop += `Screen->Font->ta_YSize` + 1**. C'est la hauteur de la police
   de l'**écran**, pas celle de la fenêtre. Cette règle s'applique aussi à une fenêtre
   BORDERLESS.
3. **Gadget de redimensionnement.** Si la fenêtre a WINDOWSIZING ($01) :
   - avec **SIZEBBOTTOM** ($20) : **BorderBottom := hauteur de l'image du gadget de taille + 1** ;
   - avec **SIZEBRIGHT** ($10), **ou si aucun des deux bits n'est mis** : **BorderRight :=
     largeur de l'image + 2** ;
   - les deux bits peuvent être mis ensemble.
   L'image est le gadget de taille système de la résolution de l'écran : variante HIRES si
   `ViewPort.Modes` a $8000, sinon LORES.
4. **BACKDROP** ($100) : les bits SIZING, DRAG et DEPTH sont retirés des Flags **avant**
   l'étape 2 (seul CLOSE peut alors encore provoquer la barre).

### 1.2 Ajustement par les gadgets utilisateur (toutes les fenêtres) [O]

Il est fait **après** les valeurs de base et **pour toutes les fenêtres, GZZ ou non**. Le
parcours couvre **toute la liste `NewWindow.FirstGadget`**, mais pas les gadgets système. Pour
chaque gadget, intuition calcule sa **boîte** (§4.1) dans son domaine, puis applique les bits
d'**Activation** :

| Bit d'Activation | Règle (max avec la valeur courante) |
|---|---|
| **LEFTBORDER** ($20) | BorderLeft := max(BorderLeft, box.Left + box.Width − 1) |
| **RIGHTBORDER** ($10) | BorderRight := max(BorderRight, Window.Width − box.Left) |
| **TOPBORDER** ($40) | BorderTop := max(BorderTop, box.Top + box.Height − 1) |
| **BOTTOMBORDER** ($80) | BorderBottom := max(BorderBottom, Window.Height − box.Top) |

Règles complémentaires :
- Le résultat est rangé dans l'octet de bordure.
- Les flags de **type** (GZZGADGET) et de **position** (GRELxxx) n'interviennent **que** dans le
  calcul de la boîte. Ce sont les **bits xxxBORDER de l'Activation** qui décident.
- Un gadget sans bit xxxBORDER **n'agrandit jamais** la bordure, même s'il est placé dans le
  cadre.
- Les bordures ne sont **jamais réduites** par cette étape.
- **Non-GZZ** : les bordures sont agrandies de la même façon. La valeur sert ensuite au dessin
  du cadre, aux coordonnées GZZMouse et à GZZWidth/Height, mais **pas** à une seconde couche
  (§2).

**Piège [O]** : au moment de ce calcul, GZZWidth et GZZHeight valent encore **0**, car ils ne
sont calculés qu'ensuite (§2.3). Dans une fenêtre GZZ, un gadget **non**-GZZGADGET qui porte un
bit xxxBORDER a donc sa boîte calculée dans un domaine intérieur de taille 0 : un GRELxxx
n'ajoute rien. Pour un GZZGADGET, le domaine est la fenêtre entière (W×H, origine 0,0) et le
calcul est exact.

### 1.3 Exemple vérifié : fenêtre Info d'info.library [O]

NewWindow : 604×190, Flags $146F (SIZING | DRAG | DEPTH | CLOSE | **SIZEBBOTTOM** |
SIMPLE_REFRESH | GIMMEZEROZERO | ACTIVATE). SIZEBRIGHT n'est pas mis.

Liste `NewWindow.FirstGadget`, dans cet ordre :

| # | Gadget | Left, Top, W×H | Flags | Activation | Type |
|---|---|---|---|---|---|
| 1 | **QUIT** | −108, −10, 80×9 | GRELBOTTOM \| GRELRIGHT ($18) | RELVERIFY ($01), **sans** BOTTOMBORDER | GZZGADGET \| BOOLGADGET ($2001) |
| 2 | **SAVE** | 20, −10, 80×9 | GRELBOTTOM ($08) | RELVERIFY \| **BOTTOMBORDER** ($81) | $2001 |
| 3 | **remplisseur** | 4, −11, 0×0 | GADGHNONE \| GADGIMAGE \| GRELBOTTOM \| GRELWIDTH ($2F) | **BOTTOMBORDER** ($80) | $2001 |

Calcul de BorderBottom, avec Height = 190 :
- SAVE : Top = −10 + 189 = 179 ⇒ 190 − 179 = 11 ;
- remplisseur : Top = −11 + 189 = 178 ⇒ 190 − 178 = **12** ;
- **BorderBottom = max(image de taille + 1, 11, 12) = 12**, si l'image de taille fait moins de
  12 lignes.

La zone intérieure se termine à la ligne 190 − 12 − 1 = **177**. Le remplisseur commence à la
ligne 178 (il fait toute la largeur grâce à GRELWIDTH) ; SAVE et QUIT, à la ligne 179, sont
dessinés par-dessus (§6). QUIT ne joue aucun rôle dans le calcul.

---

## 2. Les couches

### 2.1 Fenêtre non GZZ [O]

- **Une seule couche** : **CreateUpfrontLayer**(LayerInfo de l'écran, BitMap de l'écran,
  rectangle de la fenêtre entière, flags, `NewWindow.BitMap`).
- Les flags de couche viennent du type de rafraîchissement de la fenêtre :
  - SIMPLE_REFRESH ($40) ⇒ LAYERSIMPLE (1) ;
  - SUPER_BITMAP ($80) ⇒ LAYERSUPER (4) ;
  - sinon (SMART) ⇒ LAYERSMART (2) ;
  - plus **LAYERBACKDROP ($40)** si BACKDROP.
- WLayer (+$7C) := cette couche, et `layer->Window` := la fenêtre.
- RPort (+$32) := le RastPort de la couche ; la police de l'écran lui est appliquée par SetFont.
- **BorderRPort (+$3A) = NULL.**

### 2.2 Fenêtre GIMMEZEROZERO [O]

Ordre de création :
1. **Couche extérieure (cadre)** :
   - rectangle de la fenêtre **entière** ;
   - flags **LAYERSIMPLE**, toujours, quel que soit le rafraîchissement demandé (plus
     LAYERBACKDROP si BACKDROP) ;
   - créée **en premier**, par CreateUpfrontLayer.
   - Provisoirement WLayer = cette couche et RPort = son RastPort, avec la police d'écran.
2. Bordures (§1), gadgets système et ajout des gadgets utilisateur.
3. **Couche intérieure** :
   - CreateUpfrontLayer sur le rectangle
     **(LeftEdge + BorderLeft, TopEdge + BorderTop) – (LeftEdge + Width − 1 − BorderRight,
     TopEdge + Height − 1 − BorderBottom)** ;
   - flags = **type de rafraîchissement demandé** (SIMPLE, SMART ou SUPER, plus BACKDROP), avec
     `NewWindow.BitMap` en super-bitmap ;
   - puis **MoveLayerInFrontOf(intérieure, extérieure)**.
4. Affectations finales :
   - `inner->Window` := la fenêtre, **WLayer (+$7C) := couche intérieure** ;
   - **BorderRPort (+$3A) := RastPort de la couche extérieure** ;
   - **RPort (+$32) := RastPort de la couche intérieure**, dont TmpRas et AreaInfo sont remis à
     NULL.

Si la création d'une couche échoue, OpenWindow échoue.

### 2.3 GZZWidth / GZZHeight [O]

Calculés après les couches, pour **toutes** les fenêtres :
- **GZZWidth = Width − BorderLeft − BorderRight** ;
- **GZZHeight = Height − BorderTop − BorderBottom**.

### 2.4 Divers [O]

Pour une fenêtre BACKDROP sur un écran dont la barre de titre est affichée, intuition fait
MoveLayerInFrontOf(BarLayer de l'écran, couche de la fenêtre).

---

## 3. Coordonnées de la souris

- **Window.MouseX / MouseY** [O] : Screen.MouseX − LeftEdge et Screen.MouseY − TopEdge. Elles
  sont **relatives au coin de la fenêtre entière**, GZZ ou non.
- **GZZMouseX / GZZMouseY** [O] : MouseX − BorderLeft et MouseY − BorderTop. Elles sont
  calculées **pour toutes les fenêtres**, au même moment.
- **IntuiMessage.MouseX / MouseY** (+$20 / +$22) [O] :
  - copie de **Window.MouseX / MouseY**, donc relatives à la fenêtre **entière**, **même pour
    une fenêtre GZZ** ;
  - exception : avec **DELTAMOVE** ($100000) dans IDCMPFlags, ce sont des deltas.
  - Une application GZZ doit donc soustraire les bordures ou lire GZZMouseX/Y.

---

## 4. Domaines des gadgets

### 4.1 Boîte d'un gadget dans son domaine [O]

Le domaine fournit une largeur DW et une hauteur DH. La boîte est relative à l'**origine du
domaine** :

| Champ | Valeur |
|---|---|
| Left | LeftEdge + (GRELRIGHT ? DW − 1 : 0) |
| Top | TopEdge + (GRELBOTTOM ? DH − 1 : 0) |
| Width | Width + (GRELWIDTH ? DW : 0) |
| Height | Height + (GRELHEIGHT ? DH : 0) |

### 4.2 Domaine selon le type de fenêtre et de gadget [O]

| Fenêtre | Gadget | Domaine (origine ; taille) | Couche de rendu |
|---|---|---|---|
| non GZZ | tout gadget | (0,0) ; Width × Height | WLayer |
| GZZ | **GZZGADGET** ($2000) | (0,0) ; **Width × Height** (fenêtre entière) | **couche du BorderRPort** (cadre) |
| GZZ | **non GZZGADGET** | (**BorderLeft, BorderTop**) ; **GZZWidth × GZZHeight** | **WLayer** (couche intérieure) |

Conséquences :
- **Un gadget non-GZZGADGET d'une fenêtre GZZ** a des coordonnées **relatives à l'intérieur**,
  et ses GRELxxx sont relatifs à **GZZWidth / GZZHeight**.
- Gadgets de requester (REQGADGET $1000) et d'écran (SCRGADGET $4000) : autres domaines (celui du
  requester, l'écran), hors sujet ici.

### 4.3 Gadgets système [O]

- Les gadgets système (taille, glisser, profondeur, fermeture) sont créés selon les Flags de la
  fenêtre, à partir des modèles d'IntuitionBase et dans la variante de la résolution de l'écran.
- **Pour une fenêtre GZZ, chacun reçoit le bit GZZGADGET** : ils appartiennent au domaine
  « fenêtre entière » et sont **dessinés dans la couche du cadre**.
- Ils sont placés **en tête** de la liste de la fenêtre, avant les gadgets utilisateur.

---

## 5. Couche de dessin au rafraîchissement

- **Gadgets** : chacun est rendu dans la couche de son domaine (§4.2). Dans une fenêtre GZZ :
  - GZZGADGET et gadgets système ⇒ couche extérieure (BorderRPort) ;
  - autres gadgets ⇒ couche intérieure (RPort / WLayer). Ils sont donc découpés par la zone
    intérieure : un gadget non-GZZ posé dans le cadre serait invisible. [O pour le choix de
    couche, D pour la conséquence]
- **Cadre et titre** : dans une fenêtre GZZ, ils vont dans la couche extérieure, puisque c'est
  le seul RastPort qui couvre le cadre [D].
- **Fenêtre non GZZ** : tout est dans l'unique couche. Les gadgets du cadre partagent le
  RastPort de l'application [O : couche unique].
- **Couche extérieure toujours LAYERSIMPLE** : quand elle est découverte, intuition doit
  redessiner le cadre et les GZZGADGET, puisque les layers n'en gardent pas de copie [D,
  conséquence de LAYERSIMPLE].

---

## 6. Ordre de dessin des gadgets [O]

### 6.1 Routine commune de rendu d'une liste

Tous les chemins listés en §6.2 passent par **la même routine**, qui reçoit le premier gadget et
un compte `n`. Elle travaille en deux passes.

1. **Passe de rendu, à rebours.** Elle avance d'abord jusqu'au **dernier** gadget de la plage :
   le n-ième, ou la fin de liste si `n` est −1 ou −2. Elle dessine ensuite **de ce dernier
   jusqu'au premier**, en remontant la liste (chaque fois le gadget dont le Next pointe sur le
   courant). Pour chaque gadget, **dans cet ordre** :
   1. le rendu : PropGadget (cadre et bouton), sinon **DrawImage** de GadgetRender si
      GADGIMAGE, sinon **DrawBorder** de GadgetRender (rien si le pointeur est NULL) ;
   2. son **GadgetText** (PrintIText) ;
   3. pour un STRGADGET, son texte ;
   4. si **GADGDISABLED**, le motif de grisé sur sa boîte.

   Il n'y a donc **pas** de passe « toutes les images, puis tous les textes » : chaque gadget est
   terminé avant de passer au précédent. **Le premier gadget de la liste est dessiné en dernier,
   donc au-dessus des autres.**
2. **Passe de surbrillance, à l'endroit**, du premier au dernier de la plage : pour chaque gadget
   **SELECTED**, application de son mode de surbrillance (GADGHCOMP, etc.).

Chaque gadget est dessiné dans la couche de son domaine (§4.2), avec sa boîte calculée au moment
du dessin.

### 6.2 Qui appelle cette routine, avec quelle plage

| Événement | Gadget de départ | Compte |
|---|---|---|
| **OpenWindow** (dessin initial, après le cadre) | `Window->FirstGadget` : gadgets système en tête, puis toute la liste NewWindow | −1 (toute la liste) |
| **RefreshWindowFrame** (−456), et la **réparation du cadre** quand la couche du cadre (GZZ) ou la couche unique a LAYERREFRESH (BeginUpdate de la couche du cadre, cadre redessiné, tous les gadgets, EndUpdate) | `Window->FirstGadget` | −1 |
| **RefreshGadgets**(gad, win, req) (−222) | `gad` | **−2** (jusqu'à la fin de la liste) |
| RefreshGList (V36+, absent en 1.3) | — | — |
| Dessin d'un requester | premier gadget du requester | −1 |
| Barre de titre d'écran | gadgets de l'écran | −1 |
| Rafraîchissement ponctuel (activation ou désactivation de fenêtre, gadgets du cadre) | un gadget | 1 |
| **AddGadget**(win, gad, pos) (−42) | — | **ne dessine rien** : simple insertion à la position `pos` (−1 = fin), le gadget n'est affiché qu'au prochain Refresh |

### 6.3 Application à la fenêtre Info (info.library) [O]

- **Liste initiale** passée par `NewWindow.FirstGadget` : **QUIT → SAVE → remplisseur**. Les
  modèles sont copiés dans un bloc AllocRemember et chaînés dans cet ordre. OpenWindow insère
  les gadgets système **devant** cette liste.
- **Après OpenWindow**, info.library ajoute les autres gadgets par **AddGadget(win, g, −1)**,
  donc **à la fin** :
  - les 4 cases de protection ;
  - les gadgets chaîne (outil par défaut, tool types…) ;
  - les flèches de défilement ;
  - ADD et DEL.
  Elle les retire et les rajoute de la même façon (RemoveGadget, puis AddGadget −1) quand le
  contenu change.
- **Rafraîchissement** : info.library appelle toujours **RefreshGadgets(win->FirstGadget, win,
  NULL)**, donc toute la liste, gadgets système compris.
- **Ordre de dessin qui en résulte** : derniers ajoutés (ADD/DEL…), …, **remplisseur**, puis
  **SAVE**, puis **QUIT**, puis les gadgets système.
  - Le remplisseur, une image de 598×10 à PlanePick 0 et PlaneOnOff 2, donc un rectangle plein
    de couleur 2, est peint **avant** SAVE et QUIT.
  - Leurs textes JAM2 (« SAVE », « QUIT ») sont donc écrits **par-dessus**.
  - C'est l'ordre « de la fin vers le début » de la routine commune qui garantit le résultat à
    chaque rafraîchissement : à OpenWindow, à chaque RefreshGadgets, à chaque réparation du
    cadre.
- Une implémentation qui dessinerait à l'endroit (premier → dernier) recouvrirait SAVE et QUIT
  par le remplisseur.

---

## 7. Vecteurs de test

| Cas | Attendu |
|---|---|
| Fenêtre non-GZZ, gadget avec BOTTOMBORDER à Top −10 GRELBOTTOM, Height 190 | BorderBottom ≥ 11 ; une seule couche ; BorderRPort = NULL |
| Fenêtre Info (604×190, $146F, QUIT/SAVE/remplisseur) | 2 couches ; BorderBottom = 12 ; intérieure de (L+BL, T+BT) à (L+603−BR, T+177) ; GZZHeight = 190 − BT − 12 ; SAVE et QUIT visibles par-dessus le remplisseur |
| Clic à 5,5 dans l'intérieur d'une GZZ | IntuiMessage.MouseX = 5 + BorderLeft ; Window.GZZMouseX = 5 |
| Gadget non-GZZ dans une GZZ, LeftEdge 0 TopEdge 0 | dessiné au coin haut-gauche de la zone intérieure |
| Liste A→B→C qui se chevauchent, RefreshGadgets(A) | ordre de dessin C, B, A : A visible au-dessus |
| AddGadget(win, g, −1) seul | rien n'est dessiné tant qu'aucun Refresh n'a lieu |

---

## Relecture clean-room

- [x] Uniquement des règles de calcul (formules sur des champs publics), l'ordre des créations
  de couches, des appels de librairie (layers CreateUpfrontLayer −36, MoveLayerInFrontOf −168 ;
  graphics SetFont) et des constantes publiques (Flags, Activation, GadgetType, IDCMP). Aucune
  séquence d'instructions recopiée.
- [x] §6 : l'ordre de dessin est décrit comme une règle (à rebours, puis surbrillance à
  l'endroit) avec la table des appelants. La liste d'info.library est donnée par son ordre et
  ses appels publics (AddGadget −1, RefreshGadgets(FirstGadget)), sans code recopié.
