# FastFonts `C:FF` (Workbench 1.3.3) : remplacement de `Text()`, contrats d'ABI, cause du texte invisible

Piste **ANALYSE** (« dirty »). Ce document décrit des **comportements et des contrats d'ABI seulement** :
registres attendus, champs lus/écrits (offsets publics), appels de bibliothèque, conditions. **Aucune
suite d'instructions n'y est recopiée** et il ne contient pas de pseudo-code ligne à ligne. La ROM
Kickstart (`assets/kick34005.A500`) n'a **pas** été ouverte : la cible est un programme tiers sur
disquette.

## Provenance

- Fichier : `C:FF` de `assets/test_adf/Workbench 1.3.3 (34.34) - Boot (Commodore) (1991) [m2].adf`
  (lecture seule), extrait par `xdftool … read c/FF`. 3320 octets, md5
  `d8c8c0034a3f6b6b3f289144a0ac7dfa`. Bannière : « FastFonts V1.31 Copyright © 1987 by C.Heath of
  Microsmiths, Inc ».
- Hunks : CODE $BF0, DATA $7C, BSS $4. Relogé à une base fictive (script `python3 -I`), désassemblé
  avec radare2 (`-a m68k`). Toutes les affirmations ci-dessous viennent de ce désassemblage.
- Invocation (`s/startup-sequence`, ligne 9) : **`FF >NIL: -0 ;speed up Text`**.
- Bibliothèques ouvertes (OldOpenLibrary, sans version) : dos, graphics, intuition ; diskfont seulement
  si un nom de police est passé ou si l'option `1` est active. **Aucun test de version** de bibliothèque.

## Options de ligne de commande et état partagé

- Un mot de drapeaux (valeur initiale : bits 0, 1, 2 posés) est modifié par chaque option `-x` :

  | Option | Effet sur les drapeaux | Sens |
  |---|---|---|
  | `B`/`b` | pose bits 0 et 1 | remplacer topaz 8 et topaz 9 par la police donnée |
  | `8` / `9` | pose bit 0 / bit 1 | remplacer seulement topaz 8 / topaz 9 |
  | `1` | pose bit 3 | traiter aussi topaz 11 (chargée via diskfont) |
  | **`0`** | **efface bits 0, 1 et 3** | **aucun remplacement de police** ; FastText (bit 2) intact |
  | `F`/`f` | pose bit 2 | FastText actif |
  | `N`/`n` | efface bit 2 | FastText inactif |
  | `Q`/`q` | efface tout | terminer FastFonts (tout restaurer) |

  Option inconnue → « Bad command line switch ». Un mot sans `-` est le nom d'une police disque.
- **`-0` signifie donc : « accélérer Text seulement, ne toucher à aucune police »**. Pas de copie de
  police ni de remplacement de topaz dans la configuration de la startup-sequence.
- État persistant : un MsgPort public nommé `FF2:)` (FindPort ; sinon AllocMem $48 octets
  PUBLIC|CLEAR, ln_Type = NT_MSGPORT, mp_Flags = PA_IGNORE, AddPort). Il garde les TextFont ouvertes
  (topaz 8 via `OpenFont({"topaz.font",8})`, topaz 9, topaz 11 facultatif) et les deux blocs de patch
  (un pour topaz 8, un pour topaz 11). Un second lancement de FF retrouve le port, **retire d'abord** les
  patchs existants, puis réinstalle selon les nouveaux drapeaux.
- Lancé depuis le Workbench (pr_CLI à $AC nul) : attend/réplique le WBStartup sur pr_MsgPort ($5C).

### Remplacement de police (inactif avec `-0`, pour mémoire)

OpenDiskFont(nom, taille) ; refus si tf_Flags ($17) bit FPF_PROPORTIONAL, si tf_XSize ($18) ou tf_YSize
($14) diffèrent, ou si tf_Baseline ($1A) diffère. Sinon FF **échange en place** le contenu de la TextFont
topaz (même adresse de structure) avec celle de la police disque : mots de tf_BoldSmear ($1C) et de
tf_LoChar ($20) à tf_CharKern ($30) inclus. Cela suppose la TextFont topaz modifiable (en RAM).

## 1. Fonction remplacée et conditions de prise en main

- **Une seule fonction est patchée : `graphics.library Text()`, LVO −60 ($FFC4)**, via
  `exec SetFunction` (−420) entre Forbid/Permit. La valeur rendue (ancien vecteur) est stockée dans le
  bloc de patch et sert de repli (saut absolu vers l'ancienne Text).
- Un bloc par police accélérée : topaz 8 toujours (si FastText actif), topaz 11 si ouverte (option `1`).
  Le second patch chaîne sur le premier (son « ancienne Text » est le patch topaz 8).
- **Conditions d'installation** (sur un RastPort local initialisé par InitRastPort puis SetFont) :
  rp_TxWidth ($3C) **= 8** et 4 ≤ rp_TxHeight ($3A) ≤ 16. Sinon pas de patch. Aucun test de tf_Style,
  tf_Flags ni d'adresse ROM/RAM.
- **Conditions à l'exécution** (sinon saut direct à l'ancienne Text, registres intacts) :
  1. rp_AlgoStyle ($38) = 0 ;
  2. count (D0) ≤ 120 (comparaison signée) ;
  3. **rp_Font ($34) = exactement l'adresse de TextFont** obtenue par OpenFont à l'installation.
- **Non testés** : DrawMode, FgPen/BgPen, Mask, rp_Layer, rp_TxSpacing, rp_TxFlags, BitMap, profondeur.
  Tout cela est délégué à BltTemplate (voir § 2).
- Garde de réentrance : pendant le chemin rapide, la constante de police comparée est altérée (puis
  rétablie à la sortie). Un appel concurrent (autre tâche) ou imbriqué avec la même police tombe donc
  dans l'**ancienne** Text : la Text de la ROM doit rester correcte et réentrante.
- count = 0 : rien n'est dessiné, pas de verrou, sortie par WaitBlit.

## 2. Comment le chemin rapide dessine

Contrat d'entrée = celui de Text : A1 = RastPort, A0 = chaîne, D0 = count, **A6 = GfxBase (utilisé tel
quel pour appeler d'autres LVO graphics)**.

1. **Verrou** : si rp_Layer ($00) ≠ NULL, `LockLayerRom` (graphics −432, **couche en A5**) ; après le
   dessin, `UnlockLayerRom` (−438, A5). FF suppose que LockLayerRom **préserve D0/A0/A1** (il réutilise
   chaîne, RastPort et count juste après) et qu'il est **imbriquable** (BltTemplate peut verrouiller à son
   tour).
2. **Construction d'un gabarit 1 plan au CPU** dans un tampon **CHIP** privé (alloué MEMF_CHIP|PUBLIC
   à l'installation : 120 octets × 8 lignes = 960 octets, ×2 si hauteur > 8). Pas de pas de ligne
   variable : **modulo fixe 120 octets**, un octet (8 pixels) par caractère, une ligne par rangée de la
   police, à partir d'une table de glyphes pré-calculée (§ 3). Le code est auto-modifié à l'installation
   (adresse du tampon, ligne de base, hauteur, déroulage selon TxHeight) et copié dans le bloc de patch.
3. **Dessin : un seul appel `BltTemplate`** (graphics **−36**) avec :
   A0 = début du gabarit, D0 = 0 (xSrc), D1 = 120 (srcMod en octets), A1 = RastPort,
   D2 = rp_cp_x ($24), D3 = rp_cp_y ($26) − TxBaseline (constante figée à l'installation),
   D4 = count × 8 (largeur en pixels), D5 = TxHeight (constante figée).
4. **Mise à jour** : rp_cp_x += count × 8 (rp_TxSpacing ignoré), rp_cp_y inchangé.
5. **Sortie** : saut terminal vers `WaitBlit` (graphics −228).

Conséquences :
- **Aucun registre matériel n'est écrit par FF** ; aucun accès direct au blitter ; le blitter n'est
  utilisé qu'à travers BltTemplate de la ROM.
- Champs lus par FF : RastPort rp_Layer ($00), rp_cp_x/cp_y ($24/$26, cp_x écrit), rp_Font ($34),
  rp_AlgoStyle ($38). À l'installation : rp_TxHeight ($3A), rp_TxWidth ($3C), rp_TxBaseline ($3E)
  (remplis par SetFont), écriture de rp_BitMap ($04) du RastPort local. TextFont : tf_YSize ($14) au
  retrait, tf_LoChar ($20). **Aucun champ de BitMap de destination, de Layer (hors pointeur passé à
  LockLayerRom) ni de ClipRect n'est lu.** Aucun format privé de Layer/ClipRect n'est supposé : le
  clipping, les couches cachées, la smart refresh et la super bitmap sont entièrement à la charge de
  BltTemplate.
- LVO utilisées (graphics) : Text −60 (ancienne, à l'installation), SetFont −66, OpenFont −72,
  CloseFont −78, InitRastPort −198, WaitBlit −228, InitBitMap −390, LockLayerRom −432,
  UnlockLayerRom −438, **BltTemplate −36**. Exec : Forbid/Permit, AllocMem/FreeMem, SetFunction,
  FindPort/AddPort/RemPort, GetMsg/ReplyMsg/WaitPort, OldOpenLibrary/CloseLibrary. Dos : Output/Write,
  Delay(30) au retrait.

## 3. Pré-calcul de la police (pas de copie de strike)

- FF **ne lit jamais tf_CharData/tf_CharLoc/tf_Modulo directement** et ne copie pas le strike. Il
  fait rendre chaque glyphe par **l'ancienne Text de la ROM** :
  - RastPort local sur la pile (non initialisé → doit être entièrement remis à zéro par InitRastPort),
    InitRastPort puis SetFont(police) ;
  - BitMap locale par `InitBitMap(bm, depth 1, width 1024, height 8)` → **BytesPerRow attendu = 128** ;
    bm_Planes[0] ($08) = le tampon CHIP ; rp_BitMap = &bm ; **rp_Layer = NULL** ;
  - pour chaque caractère : cp_x = 0, cp_y = TxBaseline, `Text(rp, &c, 1)` (pinceau par défaut
    d'InitRastPort : FgPen −1, BgPen 0, JAM2, Mask $FF), puis lecture au CPU de TxHeight octets de la
    colonne 0 avec un **pas fixe de 128 octets** ;
  - **même pour une police de hauteur 11 la BitMap déclare 8 lignes** : Text sans couche ne doit pas
    rogner sur bm_Rows (le tampon est assez grand).
- Table résultante dans le bloc de patch : 256 entrées × 8 octets (×16 si hauteur > 8), indexée par le
  code du caractère. Si tf_LoChar = $20, les codes $00–$1F reçoivent les glyphes de $40–$5F **inversés**
  (rendu « vidéo inverse » des caractères de contrôle). Les codes hors [LoChar, HiChar] reçoivent ce que
  l'ancienne Text dessine pour eux.
- Le tampon CHIP sert ensuite de gabarit au chemin rapide (il est réutilisé, d'où la garde de
  réentrance).
- Retrait (`-q`, `-n` ou relance) : SetFunction(ancienne valeur) ; si la valeur rendue n'est pas le
  point d'entrée de FF (quelqu'un a re-patché par-dessus), FF remet en place la valeur qu'il vient de
  retirer, affiche « Text() vector altered-aborting » et quitte (code 5) ; sinon Delay(30) (laisser
  sortir les tâches encore dans le patch) puis FreeMem du tampon et du bloc.

## 4. Pourquoi les glyphes n'apparaissent pas sur notre ROM (par ordre de probabilité)

1. **BltTemplate (graphics −36) n'est pas implémenté** — **vérifié** : dans
   `src/graphics/graphics_lib.s`, les entrées 6..8 (LVO −36..−48) pointent sur `graphics_null`. Tout
   texte topaz 8, AlgoStyle 0, ≤ 120 caractères passe par le chemin rapide, qui ne dessine *que* par
   BltTemplate : rien n'est écrit. Le fond visible vient des effacements faits par la console/intuition
   eux-mêmes. Avant que SetFunction soit réel, le patch ne s'installait pas, d'où l'ancien bon
   comportement. **Cause quasi certaine.**
2. Une fois BltTemplate implémenté, une table de glyphes vide (glyphes muets mais fond JAM2 dessiné)
   viendrait de l'**installation** : Text sur RastPort **sans Layer** vers une BitMap privée qui ne
   dessine pas ; InitRastPort qui ne remet pas tout à zéro (rp_Layer résiduel de la pile) ou ne met pas
   FgPen = −1 / Mask = $FF ; InitBitMap qui ne donne pas BytesPerRow = 128 pour 1024 pixels ; Text qui
   rogne à bm_Rows.
3. BltTemplate implémenté mais incomplet : srcMod interprété en mots, xSrc mal géré, pas de prise en
   compte de rp_Layer (décalage des bornes de la couche, ClipRects, cr_BitMap des parties cachées),
   DrawMode/FgPen/BgPen/Mask ignorés, ou verrou de couche non imbriquable (blocage, FF tenant déjà
   LockLayerRom).
4. LockLayerRom/UnlockLayerRom qui ne prennent pas la couche en **A5** ou qui détruisent D0/A0/A1 →
   chaîne/count/RastPort corrompus.
5. Appel interne de Text via le vecteur avec **A6 ≠ GfxBase** : le chemin rapide appellerait des LVO
   relatifs à une autre base.
6. AllocMem(MEMF_CHIP) rendant de la mémoire non-CHIP alors que BltTemplate utilise le blitter.

## Exigences pour notre ROM

- **Implémenter `BltTemplate`** (LVO −36), contrat AutoDocs : A0 = gabarit (adresse paire), D0 = xSrc
  (décalage en bits dans le premier mot, 0..15), D1 = srcMod (**octets** par ligne), A1 = RastPort,
  D2/D3 = destination (coordonnées du RastPort, donc relatives à la couche si rp_Layer), D4 = largeur,
  D5 = hauteur en pixels. Bit 1 du gabarit = FgPen, bit 0 = BgPen en JAM2 / transparent en JAM1 ;
  COMPLEMENT et INVERSVID ; respecter rp_Mask et la profondeur de la BitMap ; clipper par les ClipRects
  de rp_Layer (parties cachées vers cr_BitMap en smart refresh, ignorées en simple refresh, super
  bitmap) et aux limites de la BitMap sans couche ; coordonnées négatives clippées. Préserver D2–D7/A2–A6
  (FF relit A5 après l'appel).
- Le verrou de couche interne à BltTemplate doit être **imbriquable** par la même tâche (FF tient déjà
  LockLayerRom).
- `LockLayerRom`/`UnlockLayerRom` : couche en **A5**, préservent **tous** les registres, imbriquables.
- `InitRastPort` : remet tout le RastPort à zéro puis valeurs par défaut (FgPen −1, AOlPen −1, BgPen 0,
  Mask $FF, JAM2, LinePtrn $FFFF, police par défaut). `SetFont` remplit TxHeight/TxWidth/TxBaseline
  ($3A/$3C/$3E).
- `InitBitMap` : BytesPerRow = ((width + 15) / 16) × 2, Rows, Depth, sans toucher aux Planes.
- `Text` avec rp_Layer = NULL : dessiner directement dans rp_BitMap, sans rogner à bm_Rows (cas topaz 11).
  Rester réentrante (repli concurrent depuis le patch).
- `SetFunction` : rendre l'ancienne adresse ; le retrait de FF compare la valeur rendue à son point
  d'entrée.
- Tout appel de Text par le vecteur doit avoir A6 = GfxBase ; `WaitBlit` appelable depuis n'importe
  quel contexte de tâche.
- `OpenFont({"topaz.font",8})` doit rendre la **même adresse** de TextFont que celle placée dans rp_Font
  des fenêtres (sinon FF est simplement inactif, sans dégât).
- Test de non-régression proposé : après `FF -0`, un `Text` topaz 8 de ≤ 120 caractères dans une
  fenêtre (console + PrintIText de menu + nom d'icône) doit afficher les glyphes ; un texte > 120
  caractères ou en gras doit aussi s'afficher (chemin de repli).
