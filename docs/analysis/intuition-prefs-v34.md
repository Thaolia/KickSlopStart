# intuition-prefs-v34.md — Preferences : SetPrefs / GetPrefs / GetDefPrefs, system-configuration

> Piste ANALYSE (« dirty »). Sources : ROM `assets/kick34005.A500` (intuition 34.3, dos V34 BCPL),
> fichier `devs/system-configuration` de `assets/wb133.adf`. Repères :
> - vecteurs : SetPrefs (−324) $FDFE08 → $FDB5DA ; GetPrefs (−132) $FDFC34 → $FDB5B6 ;
>   GetDefPrefs (−126) $FDFC26 → $FDB580 ; copie bornée $FDB62A ; application $FDB67A ;
>   PointerMatrix $FDB914 ; couleurs $FDB868/$FDB87E/$FDB8B8 ;
> - prefs par défaut $FDB96C (232 octets), image pointeur par défaut $FD6322 (36 mots),
>   TextAttr topaz 8 / topaz 9 $FDBA54 / $FDBA5C ;
> - souris : conversion POINTERPOS $FD6AE4, accumulateur PointerTicks $FD7C16, bornage $FD8556 ;
> - NEWPREFS : file différée $FD7F2C (code 4) → $FD8044 → diffusion $FD7FFC ;
> - init intuition $FD65E4 (prefs en $FD6862…), premier OpenLibrary $FD8A62 ;
> - dos : section BCPL de `cliinit` (globale 133) $FF82D8–$FF9000, routine locale
>   system-configuration $FF8E34 (appelée en $FF8684), nom BSTR $FF8FD5.
>
> **Légende** : **[O]** observé · **[D]** déduit · **[S]** supposé. Comportement et layouts
> uniquement, aucune suite d'instructions recopiée, aucun bitmap.

---

## 1. Stockage interne [O]

- IntuitionBase (IB) +$364 = pointeur vers **la copie courante des Preferences**, un bloc de
  **232 octets** alloué à l'init de la librairie par AllocMem(232, MEMF_CLEAR). Tout le reste
  d'intuition lit les prefs **à travers ce pointeur** (jamais une copie figée).
- Champs dérivés tenus à part dans IB (écrits par l'application §3.3) :

| IB | Contenu | Source |
|---|---|---|
| +$2E / +$30 | View.DyOffset / View.DxOffset (ViewLord en +$22) | ViewInitY/X + ViewY/XOffset |
| +$334 / +$335 | XOffset / YOffset du pointeur par défaut (init : $FF/$FF) | prefs +$64/+$65 |
| +$336 / +$33A | DoubleClick secondes / microsecondes (lus par DoubleClick()) | prefs +$14/+$18 |
| +$34E…+$354 | couleurs 0–3 | prefs +$6E…+$74 |
| +$356…+$35A | couleurs 17–19 | prefs +$66…+$6A |
| +$35C (8 oct.) | TextAttr par défaut (nom, YSize, Style en +$362, Flags) | FontHeight |
| +$36C / +$36E | DxOffset / DyOffset rendus par InitView à l'init | (fixes après l'init) |
| +$542 / +$544 | 2 × NormalDisplayRows, et cette valeur − 1 | GfxBase +$D8 |
| +$546 | NormalDisplayColumns (largeur de l'écran WB) | GfxBase +$DA |
| +$37E (40 oct.) | copie de l'IORequest input.device servant à SETTHRESH/SETPERIOD | IB +$182 |

- Init de la librairie [O] : couleurs IB+$34E… pré-remplies ($05A, $FFF, $002, $F80 ; $D22, 0,
  $FCA), InitView(IB+$22), mémorisation de DxOffset/DyOffset en IB+$36C/$36E, allocation du bloc
  prefs, puis **GetDefPrefs(bloc, 232)** et **SetPrefs(bloc, 232, FALSE)**. À ce moment aucun
  écran n'existe et input.device n'est pas ouvert : seules les données internes sont posées.
- Premier OpenLibrary (OpenCnt = 0) [O] : réapplique les prefs (§3.3, sans copie), puis
  **IB+$40 (Flags) := $1000** — ce qui efface le bit 16 (« lignes/colonnes déjà ajustées », §3.3)
  — puis ouvre timer.device et input.device (IORequest en IB+$182) et installe le handler
  d'entrée (IND_ADDHANDLER, priorité 50). Donc le **premier SetPrefs après l'ouverture**
  (celui de system-configuration) peut encore ajuster lignes/colonnes, et il est le premier à
  pouvoir transmettre KeyRpt à input.device.

## 2. Chargement de `devs:system-configuration` (dos, CLI initial) [O]

### 2.1 Qui, quand

- Code dans la section BCPL de **`cliinit` (globale 133)**, routine **locale** (appelée par
  adresse relative à la base de la routine, pas par le vecteur global — d'où l'absence de
  référence absolue).
- Ordre observé dans `cliinit` : boucle sur les unités DF0–DF3 (montage) → **lecture de
  system-configuration** → enregistrement des noms "CLI", "Restart", "FileHandler" → ouverture
  de la fenêtre **`CON:0/0/640/200/AmigaDOS`** → bannière "Copyright … Release 1.3" → suite
  (startup-sequence).
- Conséquence [D] : les prefs du disque sont en place **avant** que la fenêtre CON: n'ouvre
  l'écran Workbench (OpenWorkBench). Police (FontHeight), couleurs, LaceWB et lignes/colonnes
  s'appliquent donc dès le premier écran.
- Le nom est `"devs:system-configuration"` (BSTR) ; il faut donc que l'assign DEVS: existe déjà
  (posé plus tôt dans la même init, cf. `dos-boot-sequence.md` phase B) [D].

### 2.2 Ce qui est lu

1. `findinput` (globale 59) sur le nom ; flux nul (fichier absent) ⇒ **rien**, aucun SetPrefs,
   aucun message.
2. Lecture de **232 octets** dans un tampon local. Résultat ≠ 232 (fichier court ou erreur)
   ⇒ fermeture, **aucun SetPrefs** : les prefs restent les valeurs ROM.
3. Octet +$E7 (`ext_size`, en blocs de 64 octets) :
   - 0 ⇒ **SetPrefs(tampon, 232, TRUE)** (appel `calllib`, globale 103, sur IntuitionBase lue
     dans la globale 92, LVO −324, A0 = tampon, D0 = 232, D1 = 1) ;
   - n > 0 ⇒ allocation d'un tampon de 232 + 64·n octets (getvec), recopie des 232, lecture de
     64·n octets supplémentaires :
     - 0 octet lu ⇒ SetPrefs(tampon d'origine, 232, TRUE) ;
     - exactement 64·n ⇒ SetPrefs(grand tampon, 232 + 64·n, TRUE) (intuition 34 borne à 232,
       l'extension est ignorée) ;
     - autre ⇒ rien ;
     - puis libération (freevec).
4. `endstream` (globale 93).

- `inform = TRUE` : NEWPREFS sera diffusé (§3.4) ; au boot aucune fenêtre ne l'écoute [D].

### 2.3 Contenu du fichier WB 1.3 (232 octets, ext_size 0) [O]

| Champ | Fichier WB 1.3 | Défaut ROM (§4) |
|---|---|---|
| FontHeight | 8 | **9** |
| KeyRptSpeed | 0 s, 31 140 µs | 0 s, 100 000 µs |
| KeyRptDelay | 0 s, 400 000 µs | 0 s, 800 000 µs |
| DoubleClick | 1 s, 196 800 µs | 1 s, 500 000 µs |
| XOffset / YOffset | −2 / −1 | −2 / −1 |
| couleurs 17/18/19 | $D22 / $000 / **$ABC** | $D22 / $000 / $FCA |
| **PointerTicks** | **1** | **2** |
| couleurs 0–3 | $05A, $FFF, $002, $F80 | idem |
| ViewInitX / ViewInitY | 129 / 44 (ignorés, §3.1) | 0 / 0 |
| LaceWB, RowSizeChange, ColumnSizeChange, wb_* | 0 | 0 |

- **Explication du symptôme coordinateur** [D] : sans lecture du fichier, la vraie ROM
  présenterait elle aussi **PointerTicks = 2** (affiché « 2 » par Preferences) et les knobs
  KeyRepeat aux valeurs ROM (0,8 s / 0,1 s) au lieu de 0,4 s / 0,031 s. Il faut (a) charger le
  fichier comme en §2.2, (b) un GetPrefs qui rend la copie courante, (c) un SetPrefs complet.

## 3. SetPrefs(prefs A0, size D0, inform D1) — LVO −324 [O]

Retour : D0 = `prefs` (le pointeur passé), dans tous les cas. `inform` = mot bas de D1.

### 3.1 Copie bornée (commune aux trois fonctions)

- `size` est **signé** : ≤ 0 ⇒ aucune copie ; > 232 ⇒ ramené à 232. Copie octet par octet des
  `size` premiers octets (layout §5) de la source vers la destination.
- Si `size` ≥ 124 ($7C) : dans la **destination**, ViewInitX (+$78) et ViewInitY (+$7A) sont
  **écrasés** par IB+$36C / IB+$36E (offsets d'InitView). Les valeurs fournies par l'appelant
  (129/44 dans le fichier WB) sont donc sans effet.
- Pour SetPrefs : source = `prefs`, destination = bloc IB+$364.

### 3.2 Après la copie

1. `ext_size` (+$E7) de la copie interne **forcé à 0**.
2. Application complète (§3.3) — **même si size ≤ 0** (rien copié, tout réappliqué).
3. Si `inform` ≠ 0 : dépôt d'un événement différé « nouvelles prefs » (§3.4).

### 3.3 Application (routine commune, aussi appelée au premier OpenLibrary)

Effets, dans l'ordre observé (p = copie interne) :

1. **DoubleClick** : IB+$336/$33A := p.DoubleClick (secondes, microsecondes).
2. **Police par défaut** : TextAttr IB+$35C := **topaz.font 8** si p.FontHeight = 8, **topaz.font
   9 dans tous les autres cas** (Style 0, Flags 0). OpenFont(IB+$35C) → **GfxBase.DefaultFont**
   (+$9A). Pas de CloseFont de l'ancienne police (le compteur d'ouverture croît à chaque
   SetPrefs) [O].
3. **Lignes / colonnes**, seulement si le bit 16 de IB+$40 est à 0 (puis il est mis à 1) :
   - si wb_Height (+$E4) = 0 : GfxBase.NormalDisplayRows (+$D8) += RowSizeChange (signé) ;
   - IB+$542 := 2 × NormalDisplayRows ; IB+$544 := IB+$542 − 1 ;
   - si wb_Width (+$E2) = 0 : GfxBase.NormalDisplayColumns (+$DA) += ColumnSizeChange (signé) ;
   - IB+$546 := NormalDisplayColumns (largeur donnée à l'écran WB).
   - Le bit est posé par l'init, effacé par le premier OpenLibrary ⇒ en pratique **un seul**
     ajustement, celui de system-configuration ; les SetPrefs ultérieurs (Preferences) n'y
     touchent plus [D].
4. **Écran Workbench** (premier écran de la liste dont Type & $F = WBENCHSCREEN), s'il existe :
   Screen.Font (+$28) := &IB+$35C ; SetFont(&Screen.RastPort, DefaultFont) ;
   SetSoftStyle(&Screen.RastPort, style de IB+$35C, $FF) ; SetFont(rastport de la couche de
   barre de titre, DefaultFont).
5. **Décalage de l'affichage** : View.DxOffset := IB+$36C + ViewXOffset (octet signé +$76) ;
   View.DyOffset := IB+$36E + ViewYOffset (+$77).
6. **Couleurs** : IB+$34E…$354 := color0..3 ; IB+$356…$35A := color17..19. Si l'écran WB existe :
   SetRGB4(&Screen.ViewPort, i, c>>8, c>>4, c) pour i = 0..3 puis 17..19 (SetRGB4 masque à 4 bits).
   Les couleurs ne vont **que** vers l'écran WB ; OpenWorkBench refait ce chargement après
   ouverture.
7. **Offsets du pointeur** : IB+$334/$335 := XOffset/YOffset ; si le pointeur actif (IB+$70)
   est le pointeur par défaut (IB+$32E), ses offsets courants IB+$76/$77 sont mis à jour aussi.
8. **Image du pointeur** : les 36 mots de PointerMatrix (+$1C, mots de contrôle du sprite
   compris) sont recopiés dans le tampon sprite du pointeur par défaut (*IB+$32E).
9. **RemakeDisplay()** (LVO −384).
10. **Bornage souris et repositionnement du pointeur** ($FD8556) : MouseX bornée à
    [IB+$50, IB+$52], MouseY à [IB+$54, IB+$56], puis mise à jour des sprites/écrans [D].
11. **Répétition clavier**, seulement si input.device est ouvert (io_Device de IB+$182 ≠ 0) :
    copie des 40 octets de l'IORequest en IB+$37E, puis deux **DoIO synchrones** :
    - io_Command = **12 (IND_SETTHRESH)**, timeval (+$20 secondes, +$24 µs) = **KeyRptDelay** ;
    - io_Command = **13 (IND_SETPERIOD)**, timeval = **KeyRptSpeed**.

Champs **non** appliqués par SetPrefs : PointerTicks (lu à la volée, §6), LaceWB (lu par
OpenWorkBench : bit 0 ⇒ ViewModes |= LACE), EnableCLI, imprimante, série, WorkName,
wb_Depth. Dans le code d'intuition, les seules autres lectures directes de la copie sont
PointerTicks, FontHeight ($FDDF16, calcul d'une hauteur avec repli sur FontHeight + 6) et LaceWB
[O]. Les champs imprimante/série sont destinés aux devices via GetPrefs [S].

### 3.4 `inform` et NEWPREFS

- SetPrefs dépose dans la file différée d'IB (+$368) un nœud **code 4**, arguments nuls.
- La file est vidée par le traitement d'entrée d'intuition (au prochain événement d'entrée,
  donc avec la latence d'un tic au plus) [D].
- Code 4 ⇒ pour **tous les écrans** (liste IB+$3C) et **toutes leurs fenêtres** dont IDCMPFlags
  contient **NEWPREFS ($4000)** : envoi d'un message IDCMP NEWPREFS (code 0).
- `inform = FALSE` ⇒ aucune notification.

## 4. GetPrefs / GetDefPrefs et valeurs par défaut

### 4.1 GetPrefs(buf A0, size D0) — LVO −132 [O]

- Copie bornée §3.1 de la **copie courante** (IB+$364) vers `buf` (ViewInitX/Y recopiés depuis
  IB si size ≥ 124). Retour D0 = `buf`. PointerMatrix = celle de la copie courante (image par
  défaut tant que personne ne l'a changée, puisque l'init passe par GetDefPrefs).

### 4.2 GetDefPrefs(buf A0, size D0) — LVO −126 [O]

- Copie bornée §3.1 depuis la **table ROM $FDB96C** (pas depuis la copie courante), ViewInitX/Y
  depuis IB si size ≥ 124.
- Puis, si size ≥ 100 : PointerMatrix (36 mots, +$1C) := **image par défaut de la ROM, 36 mots**
  ($FD6322). La table $FDB96C a sa PointerMatrix à zéro : c'est ce remplissage qui la fournit.
- Retour D0 = `buf`. Aucun effet de bord (rien n'est appliqué).
- Différence avec GetPrefs : source ROM au lieu de la copie courante, et image pointeur forcée.

### 4.3 Table des valeurs par défaut (ROM $FDB96C) [O]

| Off. | Champ | Défaut |
|---|---|---|
| $00 | FontHeight | 9 |
| $01 | PrinterPort | 0 (PARALLEL) |
| $02 | BaudRate | 5 (9600) |
| $04 | KeyRptSpeed | 0 s, 100 000 µs |
| $0C | KeyRptDelay | 0 s, 800 000 µs |
| $14 | DoubleClick | 1 s, 500 000 µs |
| $1C | PointerMatrix | (zéros dans la table ; image par défaut 36 mots via GetDefPrefs) |
| $64 / $65 | XOffset / YOffset | −2 / −1 |
| $66 / $68 / $6A | color17 / 18 / 19 | $D22 / $000 / $FCA |
| $6C | PointerTicks | 2 |
| $6E…$74 | color0..3 | $05A, $FFF, $002, $F80 |
| $76 / $77 | ViewXOffset / ViewYOffset | 0 / 0 |
| $78 / $7A | ViewInitX / ViewInitY | 0 / 0 (remplacés par IB+$36C/$36E à la copie) |
| $7C | EnableCLI | 0 |
| $7E | PrinterType | 7 |
| $80 | PrinterFilename[30] | "generic" |
| $9E | PrintPitch | 0 |
| $A0 | PrintQuality | 0 |
| $A2 | PrintSpacing | 0 |
| $A4 | PrintLeftMargin | 5 |
| $A6 | PrintRightMargin | 75 |
| $A8 | PrintImage | 0 |
| $AA | PrintAspect | 0 |
| $AC | PrintShade | 1 |
| $AE | PrintThreshold | 2 |
| $B0 | PaperSize | $20 |
| $B2 | PaperLength | 66 |
| $B4 | PaperType | 0 |
| $B6 / $B7 / $B8 | SerRWBits / SerStopBuf / SerParShk | 0 / 0 / 0 |
| $B9 | LaceWB | 0 |
| $BA | WorkName[30] | vide |
| $D8 / $D9 | RowSizeChange / ColumnSizeChange | 0 / 0 |
| $DA | PrintFlags | 0 |
| $DC / $DE | PrintMaxWidth / PrintMaxHeight | 0 / 0 |
| $E0 / $E1 | PrintDensity / PrintXOffset | 0 / 0 |
| $E2 / $E4 / $E6 | wb_Width / wb_Height / wb_Depth | 0 / 0 / 0 |
| $E7 | ext_size | 0 |

## 5. Layout `struct Preferences` 1.3 (232 octets)

Celui du tableau §4.3 [O pour les offsets utilisés par le code : $00, $04, $0C, $14, $1C, $64–$77,
$78/$7A, $B9, $D8/$D9, $E2/$E4, $E7 ; le reste suit le `preferences.h` public 1.3, cohérent avec les
valeurs observées].

## 6. PointerTicks et mouvements de la souris [O]

Dans le traitement des événements d'entrée d'intuition :

- **IECLASS_POINTERPOS (4)** (position absolue) : converti en mouvement relatif —
  ie_X := (ie_X − MouseX) × PointerTicks, ie_Y := (ie_Y − MouseY) × PointerTicks, qualificatif
  RELATIVEMOUSE ($8000) posé, classe passée à RAWMOUSE (2). Puis traité comme ci-dessous.
- **IECLASS_RAWMOUSE (2)** relatif : pour chaque axe, avec un accumulateur de reste par axe
  (IB+$37A pour X, IB+$37C pour Y) et t = PointerTicks, s = t >> 1 (arithmétique) :
  - delta nul ⇒ rien ;
  - reste += delta & (2^s − 1) ; delta := delta >> s (arithmétique, arrondi vers −∞) ;
    position souris (MouseX/MouseY) += delta ;
  - si reste ≥ t : position += 1, delta += 1, reste −= t.
  - Le delta de l'événement est réécrit avec la valeur effective (utilisée ensuite pour le
    déplacement des écrans/gadgets).
  - Puis bornage + repositionnement du pointeur ($FD8556, §3.3 point 10).
- Résultat : t = 1 ⇒ vitesse native (1 pixel par comptage), t = 2 ⇒ moitié, t = 4 ⇒ quart.
  Pour t = 3 le diviseur est 2 (s = 1) mais le seuil de report 3 : la formule n'est cohérente que
  pour 1, 2, 4 (valeurs proposées par Preferences) [D].
- PointerTicks est relu dans la copie courante à **chaque** événement : un SetPrefs prend effet
  immédiatement, sans application spécifique.

## 7. Vecteurs de test

1. Sans `devs:system-configuration` : GetPrefs(buf, 232) ⇒ PointerTicks = 2, FontHeight = 9,
   KeyRptDelay = 0,8 s, KeyRptSpeed = 0,1 s, color19 = $FCA ; WB en topaz 9.
2. Avec le fichier WB 1.3 : GetPrefs ⇒ PointerTicks = 1, FontHeight = 8, KeyRptDelay = 0,4 s,
   KeyRptSpeed = 31 140 µs, DoubleClick = 1,1968 s, color19 = $ABC ; ViewInitX/Y = offsets
   d'InitView (pas 129/44).
3. Fichier de 100 octets : aucun SetPrefs (lecture ≠ 232).
4. SetPrefs(p, 0, FALSE) : rien copié, mais police/couleurs/RemakeDisplay/KeyRpt réappliqués.
5. SetPrefs(p, 120, TRUE) : octets 0–119 copiés ; ViewInitX/Y internes (octets 120–123) ni
   copiés ni réécrits ; NEWPREFS reçu par une fenêtre ouverte avec IDCMP NEWPREFS, pas par les
   autres.
6. GetDefPrefs(buf, 100) : buf[0..99] = table ROM, PointerMatrix = image par défaut ; la copie
   courante n'est pas modifiée.
7. PointerTicks = 2, deux événements RAWMOUSE dx = +1 : la souris avance de 0 puis de 1.
8. SetPrefs avec FontHeight = 7 ⇒ police topaz 9 (tout ce qui n'est pas 8).

---

## Relecture clean-room

- [x] Aucune suite d'instructions recopiée : effets décrits sur des champs publics (Preferences,
  IntuitionBase, GfxBase, Screen, IORequest), avec formules et ordre d'application.
- [x] Aucun bitmap : l'image pointeur par défaut est seulement citée (adresse, 36 mots).
- [x] Valeurs par défaut = données de configuration (constantes), présentées en tableau.
- [x] Les offsets internes d'IB sont des repères d'analyse ; l'implémentation est libre de son
  propre stockage tant que le comportement observable (§3, §4, §6) est respecté.
