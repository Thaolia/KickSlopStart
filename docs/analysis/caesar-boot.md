# caesar-boot.md — Caesar (Impressions) [cr FLT] : `caesar.boot` et `flt.exe`

> Piste ANALYSE (« dirty »). Source : `assets/test_adf/Caesar (1992)(Impressions)[cr FLT].adf`,
> fichiers extraits par un lecteur OFS tolérant (en-têtes de fichier blocs 899 et 966). Désassemblés
> avec r2. `flt.exe` est compacté : il a été décompacté hors ligne, en Python, en reproduisant le
> décompacteur. Repères ROM : graphics 34 (serveur VBlank $FC6D48, construction de copinit
> $FCAD40…$FCAD6E).
>
> **Légende** : **[O]** observé · **[D]** déduit · **[S]** supposé. Comportement, registres et
> valeurs uniquement ; aucune suite d'instructions recopiée, aucune donnée d'image ni texte
> reproduit (hors chaînes courtes).

---

## 1. `caesar.boot` (488 octets, 1 hunk CODE de $C4, RELOC32, HUNK_SYMBOL) [O]

Petit utilitaire « gagner de la mémoire CHIP » : il réduit l'écran actif à 1 plan.

1. exec **OpenLibrary("graphics.library", 0)** (−552). Le résultat **n'est pas testé**.
2. exec **OpenLibrary("intuition.library", 0)** (−552). Le résultat n'est pas testé et il est
   déréférencé aussitôt.
3. Lecture de **IntuitionBase+$38 = ActiveScreen** (champ public). Pas de test de NULL.
4. Sur cet écran, il lit `Screen.RastPort.BitMap` (Screen +$58, soit RastPort +$04).
5. Si **BitMap.Depth (+$05) = 1** : rien n'est fait.
6. Sinon :
   - **BitMap.Depth := 1**, écrit directement dans la structure de l'écran ;
   - graphics **FreeRaster(BitMap.Planes[1] (+$0C), Screen.Width (+$0C), Screen.Height
     (+$0E))** (−498). Le **2ᵉ plan est rendu à l'allocateur**, mais **son pointeur reste dans
     Planes[1]** ;
   - intuition **RemakeDisplay()** (−384).
7. CloseLibrary(intuition), CloseLibrary(graphics) (−414). Retour D0 = 0.

- La chaîne "dos.library" est présente mais inutilisée.
- Aucun accès matériel direct, aucune allocation, aucune attente.

**Effet attendu sur une ROM conforme [D]** :
- L'écran Workbench (celui de la console initiale) passe en **1 plan, 2 couleurs**.
- Ce passage repose sur trois points :
  - MakeVPort/MrgCop (via RemakeDisplay) dérivent le nombre de plans (BPU de BPLCON0) et les
    pointeurs BPLxPT de **`ViewPort.RasInfo->BitMap->Depth`** ;
  - tout le rendu (console, layers, Text, RectFill, ScrollRaster…) n'écrit que dans
    `rp->BitMap->Depth` plans ;
  - le ViewPort, le RastPort de l'écran et ceux des fenêtres (couches) partagent **la même**
    BitMap, `&Screen.BitMap`.

**Comment il peut corrompre l'affichage ou la mémoire chez nous [D]** :
- **(a)** Notre construction de display ne relit pas `BitMap.Depth` : nombre de plans fixe, ou
  copie interne de la profondeur faite à l'OpenScreen. Le DMA continue alors d'afficher le plan 2,
  qui est **de la mémoire libérée** et vite réutilisée (LoadSeg de flt.exe, tampons…). On voit
  des pixels parasites en couleurs 2/3, ce qui correspond au « vert » du thème.
- **(b)** Pire : notre console, nos layers ou nos primitives écrivent encore dans 2 plans. Elles
  **écrivent alors dans la mémoire libérée** : corruption de la liste libre de l'allocateur ou de
  ce qui y a été chargé (le code de flt.exe), donc gel possible.
- **(c)** Notre `IntuitionBase+$38` n'est pas l'écran WB, ou vaut NULL. Le programme lit alors
  une « BitMap » quelconque (adresse basse), y écrit 1 et libère un pointeur arbitraire.

**Tests à faire** :
- après caesar.boot : `ActiveScreen->BitMap.Depth = 1` ;
- le BPLCON0 effectif de la copper list a BPU = 1 ;
- plus aucune écriture dans l'ancien Planes[1] (sonde mémoire) ;
- console encore fonctionnelle, en 2 couleurs.

## 2. `flt.exe` (1 552 octets, 1 hunk CODE de $5EC, aucune relocation) [O]

### 2.1 Décompactage vers une adresse fixe

- Le hunk est un **décompacteur** suivi des données compactées : 1 316 octets compactés pour
  2 046 décompactés.
- Il **écrit le résultat à l'adresse absolue `$4A000`** : de `$4A000` à `$4A7FE`, **sans
  AllocMem ni AllocAbs**. Il décompacte de la fin vers le début.
- Pendant le décompactage, il écrit des octets de contrôle dans **COLOR00 ($DFF180)**, ce qui
  produit un clignotement du fond.
- Il saute ensuite à `$4A000`, en **mode utilisateur, sans aucun appel de bibliothèque**.

### 2.2 Le code décompacté : 100 % matériel, aucun appel système

Le code n'ouvre aucune bibliothèque : ni graphics, ni intuition, ni dos. Il ne fait **ni
OpenScreen, ni View, ni LoadView, ni OpenFont**. Il ne lit **aucun champ de GfxBase**. Il
n'appelle pas Forbid/Disable/OwnBlitter.

Séquence :
1. **Effacement de `$53000`–`$63FFF`** par longs, à adresse fixe, sans allocation. C'est
   68 Ko de CHIP.
2. Sauvegarde de **DMACONR** OR $8000 dans un mot interne.
3. **INTENA := $4000** : effacement du bit maître **INTEN**, donc **plus aucune interruption**.
   Plus de VBlank, de clavier, de timer, de disque, de série. **Le système est gelé**
   jusqu'à la sortie.
4. **COP2LC ($DFF084) := $4A16A** : adresse de sa copper list, à l'intérieur du code
   décompacté. **Il n'y a ni écriture de COPJMP2 ni écriture de COP1LC.**
5. **DMACON := DMACONR | $00F0 | $8000** : DSKEN, SPREN, BLTEN et COPEN mis à 1, rien
   d'effacé. BPLEN n'est pas touché : il est supposé déjà actif.
6. Affichage du texte (§2.4), attente du bouton (§2.5), puis sortie (§2.6).

### 2.3 Copper list maison (à `$4A16A`)

Elle ne contient que des MOVE, sans WAIT, et se termine par $FFFF,$FFFE :

| Registre | Valeur |
|---|---|
| DMACON | $0020 (efface SPREN : sprites coupés) |
| DIWSTRT / DIWSTOP | $3081 / $30C1 (lignes $30–$130 : 256 lignes PAL) |
| DDFSTRT / DDFSTOP | $0038 / $00D0 (hires, 80 octets par ligne) |
| BPLCON1, BPL1MOD, BPLCON2, BPL2MOD | 0 |
| BPLCON0 | **$A400** : HIRES, **2 plans**, **DBLPF** (double playfield), PF2PRI = 0 |
| COLOR00 | $000 |
| COLOR01 | variable (fondu, §2.4), réécrite par le CPU dans la liste |
| BPL1PT / BPL2PT | **$53000 / $53000** (le même plan pour les deux) |

En double playfield, le plan 1 forme le playfield 1, dont les couleurs sont 0 et 1, et il est
devant. Le texte apparaît donc en **COLOR01 sur COLOR00 noir**. C'est le « blanc sur noir »
observé sur la vraie ROM.

### 2.4 Texte et police

- **Police embarquée** à la fin du code : 8 octets par caractère, dont 7 lignes utilisées, à
  partir du caractère $20. Il n'y a **ni OpenFont, ni DefaultFont, ni lecture de tf_CharData**.
- Les glyphes sont recopiés octet par octet dans le plan `$53000` :
  - colonne = 2 + numéro du caractère dans la ligne ;
  - ligne de texte n à la ligne raster 8·n + 13 (pas de 80 octets, 7 lignes raster par glyphe).
- Format du texte :
  - octet 0 = fin de ligne ;
  - **$FF = fin de page** ;
  - **$FE = fin du texte**.
- Il y a ici **une seule page** de 25 lignes. Chaînes courtes visibles : « F A I R L I G H T »,
  « PRESENTS », « CAESAR FROM IMPRESSIONS ».
- **Fondu** : COLOR01 est augmenté de $111 par pas, de $000 à $FFF. À chaque pas, COP2LC est
  réécrit avec la même valeur et le programme fait une **boucle d'attente CPU** de $6000
  itérations (`dbra`) : la durée dépend de la vitesse du CPU.

### 2.5 Attente

- **Bouton gauche de la souris uniquement** : **CIA-A PRA ($BFE001) bit 6**, actif à 0.
- Il n'y a ni test POTINP (bouton droit), ni lecture clavier, ni interruption.
- Pendant le tracé, avant chaque ligne : bouton enfoncé ⇒ **sortie immédiate**.
- Après le fondu d'entrée : **attente active tant que le bit 6 vaut 1**. Il n'attend pas que le
  bouton soit relâché.
- Ensuite : fondu de sortie (−$111 par pas jusqu'à 0), nouvel effacement de `$53000`–`$63FFF`,
  et COLOR01 de la liste remis à $FFF.
- `$FE` ⇒ fin (sinon page suivante).

### 2.6 Sortie et restauration

- **DMACON := valeur sauvée** (avec SET) : les sprites reviennent.
- **INTENA := $C000** : le bit maître INTEN est remis à 1.
- Retour au CLI avec les registres d'entrée restaurés : D0 = longueur des arguments, donc code
  de retour très faible.
- **Rien d'autre n'est restauré** : ni COP1LC, ni COP2LC, ni LoadView, ni gb_copinit.

### 2.7 Pourquoi l'écran FLT apparaît sur la vraie ROM : dépendance au schéma copper de graphics 1.3 [O ROM]

Tout repose sur l'organisation copper de graphics 34 :
1. **copinit** (gb_copinit, chargé dans COP1LC et relancé par le matériel à chaque trame) se
   termine par :
   - un WAIT sur la ligne 12 ($0C01,$FFFE) ;
   - puis un **MOVE COPJMP2** ($008A) ;
   - puis la fin de liste.
   Le copper **saute donc à l'adresse contenue dans COP2LC** à chaque trame.
2. **COP2LC n'est jamais écrit par le copper.** C'est le **serveur VBlank de graphics**
   ($FC6D48, interruption VERTB) qui y écrit à chaque trame, par le CPU :
   - **gb_LOFlist** (GfxBase +$32) ;
   - ou, en entrelacé, gb_LOFlist ou gb_SHFlist (+$36) selon le bit LOF de VPOSR.
3. FLT coupe INTEN : le serveur VBlank ne tourne plus et **son COP2LC reste en place**. Le
   copinit du système y saute à chaque trame et affiche l'écran FLT.
4. À la sortie, INTEN est rétabli : dès la VBlank suivante, graphics réécrit gb_LOFlist dans
   COP2LC. **L'affichage système revient tout seul**, sans aucun appel.

**Conséquence pour notre ROM [D]** : si notre display n'utilise pas ce schéma, l'écriture de
COP2LC par FLT est sans effet. C'est le cas si, par exemple :
- la liste de la vue est mise directement dans COP1LC ;
- copinit n'a pas de COPJMP2 ;
- COP2LC est rechargé par le copper lui-même ;
- ou une interruption non masquable par INTEN récrit COP2LC.

On garde alors notre vue à l'écran pendant que le programme a coupé les interruptions et attend
un clic gauche. Cela correspond au symptôme : **système « figé », aucun echo**. En pratique, un
clic gauche devrait le libérer, après le fondu d'environ 1 s.

À reproduire :
- COP1LC = copinit, avec à la fin MOVE COPJMP2 puis $FFFF,$FFFE ;
- COP2LC chargé par le CPU dans le serveur VBlank (gb_LOFlist / gb_SHFlist) ;
- LoadView ne fait que mettre à jour gb_LOFlist / gb_SHFlist (+ gb_ActiView) et COP2LC.

## 3. Dépendances aux adresses fixes et aux champs [O]

| Dépendance | Programme | Risque chez nous |
|---|---|---|
| Code décompacté à **$4A000–$4A7FE**, sans allocation | flt.exe | écrase ce que notre ROM y a mis (bitmap d'écran, copper list, pile, tampons de handler) |
| Plan d'affichage effacé et écrit à **$53000–$63FFF**, sans allocation | flt.exe | idem, sur 68 Ko |
| CHIP ≥ $64000 (512 Ko) | flt.exe | — |
| copinit → COPJMP2 → COP2LC chargé par le VBlank de gfx | flt.exe | §2.7 |
| INTENA maître coupé pendant toute l'intro | flt.exe | tout le système est suspendu |
| CIA-A PRA bit 6 (bouton gauche) | flt.exe | doit refléter le bouton en lecture directe |
| `IntuitionBase+$38` (ActiveScreen), Screen +$0C/+$0E/+$58, BitMap +$05/+$0C | caesar.boot | §1, champs publics |
| BitMap.Depth réellement relu par MakeVPort et par tout le rendu | caesar.boot | §1 (a)/(b) |
| Aucun champ privé de GfxBase ou d'IntuitionBase, aucun appel à une adresse de la ROM | les deux | — |

**Sur la vraie 1.3 [D]** : au moment où flt.exe tourne, l'allocateur exec sert la CHIP par le
bas. Les bitmaps et listes du WB et de la console sont plutôt au-dessous de $4A000, et la zone
$4A000–$64000 est libre en pratique. **Une ROM dont les allocations du boot montent plus haut, ou
qui place des structures fixes dans cette zone, verra des corruptions.** C'est un candidat direct
pour les « pixels parasites dans la console ». Le plan 2 libéré par caesar.boot (§1) en est un
autre.

**Diagnostic conseillé** :
1. Relever l'emplacement de nos bitmaps d'écran, de nos copper lists et des segments chargés
   après la startup-sequence, et le comparer à $4A000–$64000.
2. Vérifier BitMap.Depth = 1 après caesar.boot (§1).
3. Vérifier le schéma COPJMP2 / VBlank (§2.7).
4. Pendant le « gel », un clic gauche doit rendre la main : le programme sort et les echo
   arrivent.

---

## Relecture clean-room

- [x] Aucune suite d'instructions recopiée : appels de bibliothèque avec LVO, registres matériels
  et valeurs, adresses fixes, conditions d'attente et de sortie.
- [x] Le décompacteur est seulement nommé, son algorithme n'est pas décrit pas à pas. Aucune
  donnée de police ni texte reproduit, hors trois chaînes courtes.
- [x] La copper list est décrite comme une table registre → valeur (données matérielles
  publiques).
