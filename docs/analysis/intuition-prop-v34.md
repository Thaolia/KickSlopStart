# intuition-prop-v34.md — gadgets proportionnels (intuition 34.3)

> Piste ANALYSE (« dirty »). Source : ROM `assets/kick34005.A500`, intuition 34.3. Repères :
> bordures du conteneur à l'ouverture $FD6370, boîte et conteneur $FD532C, préparation des
> gadgets $FDA55C, taille du knob $FDB1EE, position du knob $FDB34A, pas de page $FDB1B0, saut
> de page $FDB0F0, glissement $FDB40C/$FDB4CC, bornage $FDBD62, redessin du knob $FDB020, rendu
> $FD4B58/$FD4D84, test KNOBHIT $FD4780, ModifyProp / NewModifyProp $FDFC6E/$FDFC6A → $FD50A0.
>
> **Légende** : **[O]** observé · **[D]** déduit · **[S]** supposé. Règles et layouts
> uniquement, aucune suite d'instructions recopiée.

---

## 1. `struct PropInfo` (V34) — 22 octets [O]

| Off. | Champ | Écrit par intuition ? |
|---|---|---|
| +$00 | Flags (UWORD) | KNOBHIT ($0100) seulement |
| +$02 | HorizPot | oui, pendant le glissement et au saut de page |
| +$04 | VertPot | idem |
| +$06 | HorizBody | non (application, ou ModifyProp) |
| +$08 | VertBody | non |
| +$0A | CWidth | **oui** : largeur du conteneur, à chaque préparation |
| +$0C | CHeight | **oui** : hauteur du conteneur |
| +$0E | HPotRes | **oui** : pas de page horizontal (§3.3) |
| +$10 | VPotRes | **oui** : pas de page vertical |
| +$12 | LeftBorder | **oui** : à l'ajout du gadget dans la fenêtre |
| +$14 | TopBorder | **oui** : idem |

Bits de Flags : **AUTOKNOB $0001**, **FREEHORIZ $0002**, **FREEVERT $0004**, **PROPBORDERLESS
$0008**, **KNOBHIT $0100** (posé et effacé par intuition).

**LeftBorder / TopBorder** : fixés quand le gadget entre dans une fenêtre, à l'OpenWindow et à
l'AddGadget.
- PROPBORDERLESS ⇒ 0 / 0.
- Sinon ⇒ **WBorLeft / WBorTop de l'écran** (Screen +$24 / +$23).
- Les valeurs posées par l'application sont **écrasées**.

## 2. Géométrie [O]

### 2.1 Boîte et conteneur

- **Boîte du gadget** : la boîte habituelle (LeftEdge/TopEdge/Width/Height avec GRELxxx dans le
  domaine, voir `intuition-gzz-v34.md` §4).
- **Conteneur** : la boîte réduite de **LeftBorder à gauche et à droite**, et de **TopBorder en
  haut et en bas** :
  `CL = L + LB, CT = T + TB, CW = W − 2·LB, CH = H − 2·TB`.
  CWidth et CHeight reçoivent CW et CH.

### 2.2 Taille du knob

Elle n'est calculée que pour **AUTOKNOB**. Sans AUTOKNOB, c'est la taille de l'Image fournie
dans GadgetRender qui sert.
- **FREEHORIZ** : `kw = (HorizBody × CW) >> 16, plus 1`, ramené à **au moins 6** et **au plus
  CW**, puis à au moins 1.
- Sans FREEHORIZ : **kw = CW**, et le knob est collé à gauche (x = 0).
- **FREEVERT** : `kh = (VertBody × CH) >> 16, plus 1`, ramené à **au moins 4** et **au plus CH**,
  puis à au moins 1.
- Sans FREEVERT : **kh = CH**, y = 0.
- Ces valeurs sont **écrites dans l'Image** de GadgetRender : Width (+$04) et Height (+$06). Pour
  AUTOKNOB, l'application fournit une `struct Image` vide qu'intuition remplit.

### 2.3 Position du knob (relative au conteneur)

- FREEHORIZ : `kx = ((CW − kw) × (HorizPot + 1)) >> 16`.
- FREEVERT : `ky = ((CH − kh) × (VertPot + 1)) >> 16`.
- Résultat **écrit dans LeftEdge/TopEdge (+$00/+$02) de l'Image GadgetRender**, et aussi dans
  celle de **SelectRender** si elle existe.
- Position à l'écran = coin du conteneur + (kx, ky).

### 2.4 Inverse (glissement)

Pendant un glissement, la position du knob suit la souris, **bornée au conteneur**. Les Pot sont
alors recalculés :
- `HorizPot = (kx << 16) / (CW − kw)`, **ramené dans 0..$FFFF** ; si CW = kw ⇒ **$FFFF** ;
- même règle pour VertPot avec CH, kh, ky.
- Seuls les axes FREEHORIZ et FREEVERT sont modifiés.

## 3. Rendu [O]

### 3.1 Dessin complet (refresh d'un gadget proportionnel)

Ordre :
1. **RectFill de toute la boîte du gadget** en **DetailPen de la fenêtre** (JAM2). Pour une
   fenêtre WB, c'est le stylo 0.
2. **Cadre**, sauf si PROPBORDERLESS : contour de la **boîte** (pas du conteneur) en **BlockPen**,
   JAM1. Traits verticaux de **WBorLeft/2** pixels, traits horizontaux de **WBorTop/2** pixels.
   Il se trouve donc dans la marge LeftBorder/TopBorder.
3. **Knob** :
   - **AUTOKNOB** : **rectangle plein** (kx, ky, kw, kh) en **BlockPen**. Si le gadget est
     SELECTED **et** que KNOBHIT est posé, le stylo est **inversé** (complément du numéro).
   - **Image fournie** : DrawImage de GadgetRender en (kx, ky), ou de SelectRender si SELECTED
     + KNOBHIT + GADGHIMAGE et que SelectRender existe. Avec SELECTED + KNOBHIT + GADGHCOMP, la
     boîte du knob est ensuite **inversée**.
4. Texte (GadgetText) et grisé GADGDISABLED, comme pour tout gadget.

### 3.2 Déplacement du knob

- Rien n'est redessiné si la position ne change pas.
- Sinon, le nouveau knob est dessiné, puis **les parties de l'ancien rectangle non recouvertes**
  par le nouveau sont **remplies en DetailPen** (la couleur du fond).
- Le cadre n'est pas redessiné.

### 3.3 Pas de page (HPotRes / VPotRes)

`pas(Body) = $FFFF` si Body ≥ $8000, sinon `(Body << 16) / ($FFFF − Body)`.

## 4. Interaction [O sauf mention]

1. **Clic dans la boîte du gadget**, le point devant être dans le **conteneur** :
   - si le point est dans le **knob élargi** (knob agrandi de LeftBorder de chaque côté et de
     TopBorder en haut et en bas) ⇒ **KNOBHIT posé** ;
   - sinon ⇒ KNOBHIT effacé.
2. **Hors knob** (saut de page), pour chaque axe libre :
   - **Pot += signe × pas(Body)**, ramené à 0..$FFFF ;
   - le signe vient de la position du clic par rapport au knob : avant ⇒ −1, après ⇒ +1, sur
     l'axe ⇒ 0 ;
   - puis le knob est recalculé (§2.3) et redessiné (§3.2).
   - **Un seul saut par clic** : pas de répétition tant que le bouton reste appuyé [O, pas de
     boucle sur ce chemin].
3. **Sur le knob** (glissement) : à chaque mouvement de la souris, nouvelle position = position
   précédente + déplacement, bornée au conteneur. Les Pot sont recalculés (§2.4) et le knob est
   redessiné (§3.2).
4. **Messages** :
   - GADGETDOWN au clic si **GADGIMMEDIATE** ;
   - pendant le glissement, MOUSEMOVE si **FOLLOWMOUSE** (IAddress = le gadget, comme les autres
     MOUSEMOVE de gadget) [D] ;
   - **GADGETUP au relâchement si RELVERIFY**, IAddress = le gadget.
   - Les Pot sont **à jour dans PropInfo** au moment de ces messages.

## 5. ModifyProp (−156) et NewModifyProp (−468) [O]

- **NewModifyProp existe** dans intuition 34.3 (vecteur −468).
- `ModifyProp(gad, win, req, Flags, HPot, VPot, HBody, VBody)` :
  - écrit **Flags, HorizPot, VertPot, HorizBody, VertBody** dans le PropInfo ;
  - recalcule et **redessine à partir de ce gadget jusqu'à la fin de la liste** (compte −2).
    Tous les gadgets suivants sont donc redessinés aussi : c'est le comportement 1.x.
- `NewModifyProp(…, NumGad)` : même chose, mais ne redessine que **NumGad** gadgets à partir de
  `gad`. NumGad = 1 ⇒ seulement ce gadget.
- Le redessin passe par la préparation (§2 : CWidth, CHeight, PotRes, knob), puis par le rendu
  complet (§3.1), cadre compris.
- Le paramètre `req` n'est pas utilisé directement : un gadget de requester est reconnu par son
  type REQGADGET.

---

## Relecture clean-room

- [x] Aucune suite d'instructions recopiée : formules sur des champs publics (PropInfo, Image,
  Gadget, Screen), ordre de dessin, stylos et constantes.
- [x] Aucun bitmap.
