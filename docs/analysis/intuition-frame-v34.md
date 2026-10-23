# intuition-frame-v34.md — cadre des fenêtres, gadgets système, barre d'écran (intuition 34.3)

> Piste ANALYSE (« dirty »). Source : ROM `assets/kick34005.A500`, intuition 34.3. Repères :
> dessin du cadre $FDF3CA, barre de titre $FDF52C, limites du titre $FDF356/$FDF38A, activation
> $FDF6D0, désactivation $FDF7D4, contour $FDA470, remplissage à motif $FDA402, rectangle plein
> $FDA71A, motifs dans IntuitionBase (init à $FD67D4), modèles de gadgets système (ROM $FD6062,
> 8 modèles par résolution), barre d'écran $FDD03A.
>
> **Légende** : **[O]** observé · **[D]** déduit · **[S]** supposé. Aucune suite d'instructions
> n'est reproduite, et **aucune image bitmap n'est transcrite** : les pictogrammes sont décrits
> en géométrie, pour être redessinés.
>
> Notation : W, H = Width, Height de la fenêtre ; BL, BT, BR, BB = bordures (calcul dans
> `intuition-gzz-v34.md` §1) ; DP, BP = DetailPen (+$62) et BlockPen (+$63) de la fenêtre.
> Les couleurs citées sont les **numéros de stylo** ; sur l'écran WB 1.3 : 0 bleu, 1 blanc,
> 2 noir, 3 orange. Une fenêtre WB a DP = 0 et BP = 1.

---

## 1. RastPort et couche du cadre [O]

- **Couche** : celle du cadre si la fenêtre est GZZ (`BorderRPort->Layer`), sinon WLayer.
- **RastPort** : un clone du **RastPort de l'écran** (police de l'écran) attaché à cette couche,
  avec Mask $FF.

## 2. Dessin complet du cadre (OpenWindow, RefreshWindowFrame, réparation) [O]

Ordre :

1. **Effacement des bordures en stylo 0 (JAM1)**, par RectFill :
   - gauche : (0, 0)–(BL−1, H−1), si BL > 0 ;
   - droite : (W−BR, 0)–(W−1, H−1), si BR > 0 ;
   - basse : (0, H−BB)–(W−1, H−1), si BB > 0.
   La bordure haute n'est **pas** effacée ici.
2. **Contour**, si la fenêtre n'est pas BORDERLESS, en **BP**, JAM1 :
   - **traits verticaux de BL/2 pixels d'épaisseur** collés aux bords gauche **et droit** (la
     même épaisseur des deux côtés, calculée depuis **BorderLeft**), sur toute la hauteur ;
   - **traits horizontaux de 1 pixel** sur la première ligne (y = 0) et la dernière (y = H−1),
     entre les traits verticaux.
   - **Conséquence** : la bordure droite ne contient de BP que sur BL/2 colonnes. Le reste de BR
     reste au **stylo 0**. Avec le gadget de taille à droite, BR vaut 18 en hires, mais seul un
     filet de BL/2 pixels (2 pixels sur l'écran WB) est en BP : la bordure **paraît fine** et
     le reste est bleu. Même règle pour la bordure basse : seule la ligne H−1 est en BP.
3. **Fond de la barre de titre**, si BT > 0 : RectFill **(0, 0)–(W−1, BT−2) en BP**.
   - La ligne **y = BT−1 n'est pas peinte**. Elle garde le fond de la couche (stylo 0) et forme
     le filet sous la barre [D].
4. **Contenu de la barre de titre** (§3).
5. **Tous les gadgets de la fenêtre**, gadgets système compris, dessinés à rebours (voir
   `intuition-gzz-v34.md` §6) : le premier de la liste est dessiné en dernier.
6. **Si la fenêtre n'est PAS active** : application du **voile d'inactivité** (§4.2).

## 3. Barre de titre [O]

### 3.1 Géométrie

- **Hauteur** : BT = WBorTop de l'écran + `Screen->Font->ta_YSize` + 1 (dès que la fenêtre a
  DRAG, DEPTH, CLOSE ou un titre).
  - Les gadgets système ont une **hauteur de 10** ;
  - le fond est peint jusqu'à BT−2.
- **Début de la zone de titre** (x0) :
  - avec CLOSEGADGET : **30** en hires, **16** en lores ;
  - sinon : **WBorLeft** de l'écran.
- **Fin de la zone de titre** (x1) :
  - avec DEPTHGADGET : **W − 54** en hires, **W − 35** en lores ;
  - sinon : **W − 1**.

### 3.2 Contenu, dans l'ordre

1. Si x0 < x1 : RectFill (x0, 0)–(x1, BT−2) en **BP**.
2. **Titre** (Window.Title ≠ NULL) :
   - IntuiText **FrontPen = DP, BackPen = BP, JAM2**, police de l'écran (ITextFont NULL), placé
     à **(x0, 1)** ;
   - la position courante avance alors de **largeur du texte + 3** :
     `x = x0 + TextLength(titre) + 3`.
3. **Motif de glissement**, seulement si la fenêtre a **WINDOWDRAG** :
   - RectFill de (x, 1) à (x1 − 3, BT − 3) avec un **motif de remplissage** de **8 lignes**,
     APen = **DP**, BPen = BP, **JAM1** ;
   - le motif, indexé par y modulo 8 : lignes **0, 1, 4, 5 vides** ; lignes **2, 3, 6, 7
     pleines** ;
   - les pixels « vides » ne sont pas touchés (JAM1) : ils gardent le BP du fond.
   - **Résultat pour BT = 11** (topaz 8, WBorTop 2) : deux **doubles lignes horizontales en DP**
     aux lignes **y = 2–3 et y = 6–7**, du bout du titre jusqu'à x1 − 3.
   - Sans titre, le motif commence à x0 + 3, puisque la largeur du texte vaut 0.
   - Rien n'est dessiné si la zone est vide (x > x1−3 ou BT−3 < 1).

## 4. Fenêtre active ou inactive [O]

### 4.1 Activation (ActivateWindow, clic…)

1. L'ancienne fenêtre active est désactivée (§4.2) et reçoit **INACTIVEWINDOW**.
2. La nouvelle fenêtre reçoit le drapeau **WINDOWACTIVE ($2000)** et **ACTIVEWINDOW**.
3. Si elle a un titre ou DRAG : **la barre de titre est redessinée** (§3.2), ce qui efface le
   voile. Sont aussi rafraîchis, un par un :
   - les gadgets dont l'Activation contient **TOPBORDER ($40)** ;
   - les deux gadgets de profondeur, si le titre a débordé sur leur zone.

### 4.2 Désactivation

- **WINDOWACTIVE est effacé**.
- Si la fenêtre a un titre ou DRAG : **voile** = RectFill de **(x0, 1) à (x1, BT−3)** avec un
  **motif de 4 lignes**, APen = **BP**, **JAM1**. Chaque ligne du motif n'allume qu'**un pixel
  sur quatre**, et le point est décalé d'une ligne à l'autre (deux décalages en alternance).
  - **Effet** : les pixels du titre et des doubles lignes sont partiellement repeints en BP. Le
    titre et le motif apparaissent **tramés ou estompés**.
  - Le fond, les bordures et les gadgets ne changent pas.
- **Le cadre n'a pas d'autre différence entre actif et inactif** : mêmes stylos, mêmes traits,
  mêmes gadgets.

## 5. Gadgets système [O]

### 5.1 Création et ordre

Ils sont créés selon les Flags de la fenêtre, à partir des modèles de la résolution de
l'écran (**hires** si `ViewPort.Modes` a $8000, sinon lores). Ordre dans la liste, en tête, avant
les gadgets de l'application :

| # | Gadget | Condition | Type |
|---|---|---|---|
| 1 | profondeur « avant » (WUPFRONT) | WINDOWDEPTH | $8040 |
| 2 | profondeur « arrière » (WDOWNBACK) | WINDOWDEPTH | $8060 |
| 3 | taille (SIZING) | WINDOWSIZING | $8010 |
| 4 | fermeture (CLOSE) | WINDOWCLOSE | $8080 |
| 5 | glissement (WDRAGGING) | WINDOWDRAG | $8020 |

- Dessin à rebours : glissement (rien à dessiner), puis fermeture, taille, arrière, et
  **avant en dernier**.
- Une fenêtre GZZ reçoit le bit GZZGADGET sur chacun d'eux.
- **Surbrillance** : tous sont en **GADGHCOMP** (bits 0–1 des Flags à 0), sans SelectRender. Le
  clic **inverse** la boîte du gadget, et non l'image. Seul le glissement est en **GADGHNONE**.
- Les **images sont dessinées avec PlanePick = 3 et PlaneOnOff = 0**, sur 2 plans. Les
  **couleurs sont donc fixes** (stylos 0, 1, 2), **indépendantes de DP/BP**. Exception :
  l'image hires du gadget de taille n'a qu'un plan (PlanePick = 1) ; ses pixels allumés sont en
  stylo 1, les autres en stylo 0.
- Il n'y a **aucune différence active/inactive** dans les images.

### 5.2 Positions et tailles

| Gadget | Hires : boîte (relative à) | Hires : image | Lores : boîte | Lores : image |
|---|---|---|---|---|
| Avant | x = W−29, y = 0, 26×10 (GRELRIGHT, LeftEdge −28) | 29×10 en (0,0) du gadget, jusqu'au bord droit | x = W−17, 17×10 | 17×10 |
| Arrière | x = W−53, y = 0, 24×10 (LeftEdge −52) | 24×10 | x = W−34, 17×10 | 17×10 |
| Taille | x = W−16, y = H−9, 16×9 (GRELRIGHT et GRELBOTTOM, −15/−8) | 16×9, **1 plan** | x = W−11, y = H−10, 11×10 | 11×10, 2 plans |
| Fermeture | gadget x = 4, y = 0, 24×10 ; **image décalée de −4**, donc à x = 0 | 28×10 | x = 0, 14×10 | 14×10 |
| Glissement | x = 0, y = 0, largeur W + 0 (GRELWIDTH), hauteur 10, sans image | — | idem | — |

### 5.3 Géométrie des pictogrammes (pour les redessiner)

Fond = **stylo 1 (blanc)** sauf mention. « Trait » = ligne de 1 pixel de haut, ou de 2 pixels
de large pour un montant vertical en hires (1 pixel en lores).

**Profondeur « avant »** (29×10 hires / 17×10 lores) :
- **2 colonnes de stylo 0** à gauche (bande de séparation), le reste à fond 1 sur toute la
  hauteur ;
- un **carré « arrière » plein en stylo 2 (noir)**, en haut à gauche de la zone utile :
  - hires : x 4–7, y 1–6, prolongé par la ligne y = 1 jusqu'à x = 17 ;
  - lores : x 4–10 sur la ligne 1, colonnes 4–7 sur y 1–6.
- **Devant lui**, un **carré blanc creux** : contour en **stylo 0 (bleu)** de 2 pixels de large
  sur les montants, ses côtés étant :
  - hires : x 8–21, y 2–8 ;
  - lores : x 8–14, y 2–8.
  Son intérieur reste blanc et masque une partie du carré noir, qui ne déborde qu'en haut et à
  gauche. Le carré bleu est donc « devant » le noir.
- **Hires seulement** : une **bande verticale de stylo 0 de 2 pixels** (x 24–25) sur toute la
  hauteur, à droite du pictogramme, puis 3 colonnes de fond 1 jusqu'au bord. En lores, le bord
  droit est directement à fond 1.

**Profondeur « arrière »** (24×10 hires / 17×10 lores) :
- 2 colonnes de stylo 0 à gauche, puis le fond 1 ;
- un **carré creux en stylo 0** en haut à gauche :
  - hires : contour x 4–17, y 1–6, montants de 2 pixels ;
  - lores : x 4–10, y 1–6.
- **Devant lui**, en bas à droite, un **rectangle plein en stylo 2 (noir)** :
  - hires : x 8–21, y 3–8 ;
  - lores : x 8–14, y 3–8.
  Il recouvre le coin inférieur droit du carré creux. Le carré **noir est devant**.

**Fermeture** (28×10 hires / 14×10 lores) :
- hires : 4 colonnes de fond 1, puis une bande de stylo 0 de 2 pixels (x 4–5) sur toute la
  hauteur, puis le pictogramme, puis 2 colonnes de fond 1 (x 24–25) et 2 de stylo 0 (x 26–27) ;
- **pictogramme** : un **cadre creux en stylo 0** (x 8–23, y 1–8 en hires ; x 2–11, y 1–8 en
  lores), à intérieur blanc, contenant au centre un **petit carré plein en stylo 2 (noir)** :
  - hires : x 14–17, y 4–5 ;
  - lores : x 6–7, y 4–5.
  Entre le cadre et le carré, un anneau de fond 1.

**Taille hires** (16×9, 1 plan : allumé = stylo 1, éteint = stylo 0) :
- fond **stylo 1** ;
- deux **rectangles creux en stylo 0** qui se chevauchent :
  - un **petit** en haut à gauche (x 2–7, y 1–3) ;
  - un **grand** en bas à droite (x 6–13, y 3–7) ;
  - leurs traits ont **2 pixels** de large sur les montants et 1 pixel en horizontal.
- Ce sont les coins d'une fenêtre « petite » et d'une fenêtre « grande ».

**Taille lores** (11×10, 2 plans) :
- fond stylo 1 ;
- un **petit carré plein en stylo 2** en haut à gauche (x 2–4, y 1–3) ;
- un **grand rectangle plein en stylo 2** en bas à droite (x 5–8, y 4–8).
- Les deux carrés se touchent par un coin.

## 6. Barre de titre de l'écran [O]

Elle est dessinée dans la **BarLayer** de l'écran (Screen +$14E), sous LockLayerInfo.
- **Fond** : RectFill **(0, 0)–(Screen.Width−1, BarHeight−1)** en **BlockPen de l'écran**
  (Screen +$14B).
- **Titre** (Screen.Title, +$16) :
  - IntuiText **FrontPen = DetailPen de l'écran** (+$14A), **BackPen = BlockPen**, **JAM2**,
    police de l'écran ;
  - placé à **(BarHBorder, BarVBorder)**, soit Screen +$20 et +$1F.
- **Pas de motif de lignes** sur la barre d'écran, et pas de voile.
- **Gadgets de l'écran** (liste Screen +$146), dessinés à rebours :
  - **profondeur avant et arrière d'écran** (types $C050 et $C070), avec **les mêmes images et
    les mêmes positions relatives au bord droit** que les gadgets de profondeur des fenêtres
    (tableau §5.2, en remplaçant W par la largeur de l'écran) ;
  - **glissement d'écran** ($C030), sans image.
- Rien n'est dessiné pour un écran SCREENQUIET (bit $100 de Screen.Flags).

## 7. Résumé des différences avec notre rendu [D]

1. **Bordure droite** : seules les BL/2 colonnes extérieures sont en BP ; le reste de BR est au
   stylo 0. Le dessin n'est pas un remplissage de toute la bordure.
2. **Bordure basse** : seule la ligne H−1 est en BP.
3. **Motif de glissement** : doubles lignes DP aux lignes y ≡ 2, 3 (mod 4) de la barre, de la
   fin du titre + 3 jusqu'à x1 − 3, seulement avec WINDOWDRAG.
4. **Inactif** : tramage BP d'un pixel sur quatre sur la zone de titre, pas de changement de
   couleur du fond.
5. **Gadgets** : pictogrammes à couleurs fixes, positions du §5.2, surbrillance par inversion
   de la boîte.

---

## Relecture clean-room

- [x] Aucune suite d'instructions recopiée : uniquement des règles de dessin (rectangles, traits,
  stylos, ordre), des positions relatives aux champs publics (Window, Screen) et des constantes
  (Flags, types de gadgets).
- [x] **Aucun bitmap transcrit** : les pictogrammes système sont décrits en géométrie (zones,
  rectangles, épaisseurs, couleurs), à redessiner librement. Les deux motifs de remplissage
  sont décrits par leur effet (lignes pleines ou vides, un pixel sur quatre), pas comme des
  tableaux de mots.
