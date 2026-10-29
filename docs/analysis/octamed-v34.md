# octamed-v34.md — OctaMED Professional v4.00 sur la vraie 1.3 : référence visuelle, contrat OS, LoadWB

> Piste ANALYSE (« dirty »). Sources :
> - ROM `assets/kick34005.A500` (vraie KS 1.3, exec 34.2 / graphics 34.1 / intuition 34.3 / dos 34.3)
>   **exécutée** sous FS-UAE (A500, 512K chip + 512K slow) — aucune lecture de son code n'a été
>   nécessaire pour ce document : tout ce qui concerne la ROM est **observé** (captures, structures
>   publiques relues en mémoire par le débogueur FS-UAE après coup) ;
> - disquette `OctaMED Professional v4.00 (1992)(RBF Software)[a].adf` (copie de travail ; l'original
>   n'est pas modifié). Programme `OctaMED` (143 668 o) et `c/LoadWB` (1 136 o) : logiciels tiers,
>   décompressés / désassemblés pour savoir **quelles fonctions publiques ils appellent et avec quels
>   arguments**.
>
> **Légende** : **[O]** observé · **[D]** déduit · **[S]** supposé. Ce document ne contient aucune
> suite d'instructions de la ROM ni aucune adresse de routine ROM ; les valeurs citées sont des
> champs de structures publiques (includes NDK 1.3) et des arguments d'appels d'API.

---

## 0. Résumé exécutable

1. Sur la vraie 1.3, avec la startup réduite à `OctaMED`, l'écran d'accueil est **stable de 120 s à
   160 s** (captures identiques au pixel), un clic gauche n'importe où le remplace par l'éditeur, et
   **tous les boutons testés réagissent** (FILES, PLAY, PLAY SONG, STOP). [O] (§1)
2. OctaMED ouvre **un écran CUSTOMSCREEN 640 × `-1` × 3 plans, HIRES|SPRITES** puis **une seule
   fenêtre BACKDROP|BORDERLESS|ACTIVATE|RMBTRAP|NOCAREREFRESH** de la taille de l'écran. La vraie 1.3
   transforme la hauteur **-1 en 256** (PAL) : Screen.Height = ViewPort.DHeight = BitMap.Rows = 256,
   et la fenêtre (dont OctaMED recopie la hauteur depuis Screen.Height) fait 640 × 256. [O] (§2.1)
3. **Les boutons du panneau (FILES, PLAY, INSTR…, PLAY SONG, STOP…) ne sont PAS des gadgets
   Intuition.** La fenêtre n'a en tout que 5 à 7 gadgets (2–4 chaînes, 1 booléen, 2 proportionnels) ;
   les boutons sont détectés par OctaMED lui-même à partir des messages IDCMP **MOUSEBUTTONS /
   SELECTDOWN ($68)** et des champs **MouseX / MouseY de l'IntuiMessage**. [O] (§2.4, §2.5)
4. L'écran d'accueil « CLICK MOUSE TO CONTINUE » attend lui aussi un **MOUSEBUTTONS de Code $68**
   sur le UserPort de la fenêtre. [O] (§2.5)
5. `c/LoadWB` de la disquette est le **LoadWB 38.9 de la 2.04** : il demande `dos.library` **V36** et
   s'arrête dès cet échec. **La vraie 1.3 affiche exactement « loadwb failed returncode 20 »** : ce
   message n'est donc pas une régression de notre ROM. [O] (§3)

Causes les plus probables des symptômes rapportés sur notre ROM (§4) : traitement de
`NewScreen.Height = -1`, livraison des IDCMP MOUSEBUTTONS (et de MouseX/MouseY relatifs à la fenêtre)
à une fenêtre BACKDROP/BORDERLESS/RMBTRAP **hors de tout gadget**, et le bit `NS_EXTENDED` ($1000)
dans `NewScreen.Type`.

---

## 1. Captures de référence (vraie 1.3) — `docs/analysis/octamed/`

Protocole [O] : copie de l'ADF dont `s/startup-sequence` est remplacée par la seule ligne `OctaMED`
(xdftool delete + write) ; boot froid sur `kick34005.A500` par le harnais `tests/dskchg_run.sh`
(copie locale avec une commande `click` = mousedown/mouseup 1 par xdotool, 120 ms) ; captures X
recadrées en +152+100 720×568. Pointeur placé par déplacements relatifs depuis le coin haut-gauche
(1 pas xdotool ≈ 1 pixel hires horizontal, ≈ ½ ligne verticale). Les instants sont comptés depuis le
lancement de FS-UAE.

Palette de l'éditeur (relue dans la ColorMap, §2.2) : 0 = $000 noir (fond), 1 = $CCC gris clair
(texte, reliefs clairs), 2 = $667 gris foncé (ombres), 3 = $99A gris-bleu (panneaux), 4 = $F00 rouge
(curseur d'édition, séparateurs de pistes), 5 = $F88, 6 = $FAA (rose : numéros de pistes), 7 = $FCC.
Couleurs du pointeur (17-19) relues : $00F / $000 / $FE1 (bleu / noir / jaune), forme du pointeur
comprise : elles viennent du `devs/system-configuration` de la disquette, pas d'OctaMED.

| Fichier | Instant / action | Ce que montre la capture |
|---|---|---|
| `01_accueil_t120.png` | 124 s (identique au pixel à 166 s) | Écran d'accueil. En haut, bandeau gris-bleu ($99A) avec titre « OctaMED-Professional (v4.00) » dessiné, cadre « OctaMED Professional (v4.00) / COPYRIGHT © 1992 TEIJO KINNUNEN & RAY BURT-FROST / ILLEGAL DISTRIBUTION… / -CLICK MOUSE TO CONTINUE- » et, à droite, la grille de 15 boutons (FILES MISC ≡ / PLAY VOL ♪ / INSTR MIDI SYNTH / BLOCK TRANS SMPED / EDIT RANGE SLIST). Ligne d'état sous le panneau (champs vides, E SP CHRD, barre de 8 crans). Zone centrale noire avec 4 lignes de texte blanc topaz 8 : « OctaMED V4 - now released as freeware! … commercial version of OctaMED. » En bas, cadre gris des oscilloscopes/VU (2 grands rectangles à graduations). Pointeur en haut à gauche. |
| `02_apres_clic.png` | clic gauche au centre (≈ 320,137 écran), +10 s | Éditeur principal : titre d'écran **« Loading GFX... »** dans la barre de titre (noire, texte blanc) ; panneau PLAY (flèches haut/bas, +/-, INS/DEL, VOL HEX/DEC, FILTER, E1 E2 E3 STS, SPD 033/06, CH.MODE HQ, 4 5 6 7 8, STOP, PLAY SONG, CONT. SONG, PLAY BLOCK, D, CONT. BLOCK, deux glissières horizontales) ; bouton **PLAY en vidéo inverse** ; ligne d'état « 0001/0001 000/000 … 01 … 01/01 » ; numéros de pistes roses 4 0 1 2 3, séparateurs rouges verticaux ; bloc de pattern (lignes 000-007, « --- 00000 »), ligne courante 000 sur bande grise avec curseur rouge ; ligne « Mem 384448/ 206176 » ; cadre VU en bas. |
| `03_files.png` | clic sur FILES (≈ 532,56 capture), +6 s | Titre « Loading directory... ». Panneau FILES : SAVE FORMAT (MOD1(+INSTR) en inverse, MOD1(NOINST), MOD0(OLD), ST-MODULE), INFO/ICON, LOAD SONG / SAVE SONG / LOAD INSTR / SAVE INSTR, DEL FILE, LOAD/SAVE MSG MAP, champs DIR: « OctaMEDv4: » et FILE: (noirs). Zone centrale grise ($99A) : « Disk 71 % full (248392 bytes free) », liste « ReadMe 8690 », « (dir) c », colonne de volumes/assigns (C: CON: DEVS: DF0: FONTS: L: LIBS: PAR: PRT: RAM: RAW: S: SER:), ascenseurs verticaux. Bouton FILES en inverse. |
| `04_play.png` | clic sur PLAY, +6 s | Retour au panneau PLAY (PLAY en inverse). La barre de titre d'écran n'est plus visible : le haut de l'écran montre « TIMER 00:00 » + le logo « OctaMED-Professional (v4.00) BY TEIJO KINNUNEN » (dessin de la fenêtre). |
| `05_play_song.png` | clic sur PLAY SONG (≈ 310,115), +6 s | Lecture en cours : PLAY SONG en inverse, TIMER 00:04, le pattern défile (ligne courante 036 sur la bande grise, lignes 029-043 visibles, numéros de piste dans le pattern). |
| `06_stop.png` | clic sur STOP (≈ 240,124), +4 s | Lecture arrêtée : TIMER figé à 00:11, PLAY SONG n'est plus en inverse, pattern arrêté (ligne courante 031). |

Mesures annexes [O] : la ligne « Mem 384448/ 206176 » (valeurs non interprétées) ; le titre d'écran
« Loading GFX... » apparaît après le clic d'accueil (chargement d'`OctaMED.gfx*`), puis disparaît
quand l'éditeur redessine la bande de titre.

---

## 2. Ce qu'OctaMED attend de l'OS

### 2.0 Chargement

- `OctaMED` est un exécutable **auto-décompactant** : 2 hunks (CODE 652 o, DATA 0x22E74 o / alloc
  0x3BB38 o). Le décompacteur n'utilise qu'**AllocMem / FreeMem** (exec) et écrit dans
  **COLOR17 ($DFF1A2)** pendant la décompression ; il construit **43 segments** chaînés en seglist
  (BPTR), libère son hunk de données puis saute au premier segment. [O] (exécution sous un
  émulateur 68000 minimal avec un faux exec)
- Le code décompacté est du C « small data » (registre de base sur le segment de données). [O]
- Démarrage CLI classique : FindTask(NULL), pr_CLI, pr_CurrentDir ; OpenLibrary("dos.library", 0). [O]

### 2.1 Écran et fenêtre [O]

Bibliothèques : `intuition.library` **V33** (échec ⇒ Alert), `graphics.library` V0,
`icon.library` V0 (facultative : « No icon.library: no icon. »), `dos.library` V0 ;
plus tard `powerpacker.library`, `audio.device`, `ciax.resource`, `misc.resource`,
`serial.device` (MIDI), `printer.device` à la demande.

`OpenScreen(NewScreen)` :

| champ | valeur | note |
|---|---|---|
| LeftEdge, TopEdge | 0, 0 | |
| Width | 640 | |
| **Height** | **-1** ($FFFF) | jamais modifié par le programme. **Vraie 1.3 : Screen.Height = 256, ViewPort.DHeight = 256, BitMap.Rows = 256** (machine PAL) [O] |
| Depth | 3 (2 si l'option « depth » des préférences est réglée) | |
| DetailPen / BlockPen | 0 / 1 | |
| ViewModes | **$C000 = HIRES \| SPRITES** | relu : ViewPort.Modes = $C000 [O] |
| **Type** | **$100F = CUSTOMSCREEN \| NS_EXTENDED ($1000)** | la vraie 1.3 accepte et **conserve** le bit : Screen.Flags = $100F [O] |
| Font | TextAttr { "topaz.font", 8, 0, 0 } | |
| DefaultTitle | « OctaMED Professional © 1991-1992 Teijo Kinnunen & Ray Burt-Frost. » (chaîne décodée XOR $CC au démarrage) | Screen.Title relu identique [O] |
| Gadgets, CustomBitMap | NULL, NULL | |
| (Extension, V36) | pointeur vers une liste de tags `SA_Pens` ($8000003A) | **ignorée** par la 1.3 [D] |

Résultat relu sur la vraie 1.3 : BarHeight 10, BitMap BytesPerRow 80, Rows 256, Depth 3,
ColorMap Count 32. [O]

Puis `OpenFont(topaz 8)` (graphics), `FindTask(NULL)` et `OpenWindow(NewWindow)` :

| champ | valeur |
|---|---|
| Left/Top | 0, 0 |
| Width / Height | 640 / **recopiée de Screen.Height** juste avant OpenWindow (donc 256 sur la vraie 1.3) |
| DetailPen / BlockPen | 255 / 255 |
| **IDCMPFlags** | **$478 = MOUSEBUTTONS \| MOUSEMOVE \| GADGETDOWN \| GADGETUP \| RAWKEY** |
| **Flags** | **$31900 = BACKDROP \| BORDERLESS \| ACTIVATE \| RMBTRAP \| NOCAREREFRESH** |
| FirstGadget, CheckMark, Title | NULL |
| Screen | l'écran ouvert ; Type = CUSTOMSCREEN |

Relu sur la vraie 1.3 : Window 640×256 en (0,0), **Flags $33900** (WINDOWACTIVE ajouté),
IDCMPFlags $478, bordures 0/0/0/0, Pointer NULL (pointeur par défaut), IntuitionBase.ActiveWindow =
cette fenêtre, ActiveScreen = cet écran. [O]

Ensuite : `pr_WindowPtr := window` (requesters DOS sur cet écran), RastPort = `window->RPort`,
`ViewPortAddress(window)`, `LoadRGB4(vp, table, 8)`, `SetDrMd(rp, JAM2)`, `SetAPen(rp, 0)`,
`SetBPen(rp, 3)`. [O]

### 2.2 Palette [O]

- `LoadRGB4(vp, 8 couleurs)` pour les couleurs 0-7, `SetRGB4` ponctuels (mise au noir des 8 couleurs
  avant de dessiner l'écran d'accueil, puis couleurs de sprites 21-27), `GetRGB4` (4 sites,
  préférences de palette).
- ColorMap relue sur la vraie 1.3 :
  - écran d'accueil : `000 CCC 667 99A 334 556 889 BBC` pour 0-7 ;
  - éditeur : `000 CCC 667 99A F00 F88 FAA FCC` pour 0-7 et `AAA AAA BBB 888 AAA AAA BBB` pour
    21-27 (couleurs des sprites des VU/curseurs) ; 16-20 et 28-31 inchangées
    (`000 00F 000 FE1 444`, `CCC DDD EEE FFF`). [O]

### 2.3 Dessin

- Écran d'accueil et panneaux : images chargées depuis `OctaMED.gfx1..7` dans une BitMap
  initialisée par `InitBitMap`, copiées par **`BltBitMapRastPort(src, 0, 0, rp, 0, 0, 640, 200,
  $C0)`**. Si `Screen.Height >= 256`, OctaMED complète les lignes PAL par
  `SetAPen(rp, 3)` + `RectFill(rp, 0, 199, 639, 206)` et dessine des éléments supplémentaires plus
  bas : **la mise en page dépend de la hauteur réelle obtenue pour l'écran**. [O]
- `ShowTitle(screen, FALSE)` puis `SetWindowTitles(window, (char*)-1, titre)` (titre d'écran
  seulement) ; plus tard le titre d'écran sert de ligne d'état (« Loading GFX... », « Loading
  directory... »). [O]
- Primitives graphics très utilisées : Move ×69, Text ×55, SetDrMd ×37, SetAPen ×34, RectFill ×27,
  Draw ×16, SetBPen ×10, WritePixel, PolyDraw, WaitBlit, VBeamPos (attente de faisceau). [O]
- **UCopList** (si l'option est active) : AllocMem(12, MEMF_PUBLIC|MEMF_CLEAR), puis 30 fois
  `CWait(ucl, y, 0)` / `CBump` / `CMove(ucl, COLOR22, …)` / `CBump` / `CMove(ucl, COLOR26, …)` /
  `CBump` (y de 2 en 2 depuis une ligne de base), terminée par `CWait(ucl, 10000, 255)` + `CBump`
  (= CEND), puis `vp->UCopIns := ucl` et **`RethinkDisplay()`**. Retrait : Forbid… `vp->UCopIns :=
  NULL`, RethinkDisplay, `FreeCopList`. Relu sur la vraie 1.3 : **UCopIns non nul dans la vue
  éditeur, nul dans la vue FILES**. [O]
- **Sprites matériels** via graphics : `GetSprite` (×6), `ChangeSprite` (×10), `MoveSprite` (×11),
  `FreeSprite` (×4) — indicateurs VU / curseurs, en plus du pointeur Intuition. ViewPort.SprIns
  reste NULL (SimpleSprites). [O]
- `SetPointer(window, données, 14, 16, -12, -11)` seulement si une préférence le demande ;
  `ClearPointer` sinon. Par défaut (captures) : pointeur système. [O]
- `CloseWorkBench` / `OpenWorkBench` existent (option), non déclenchés dans les captures : l'écran
  Workbench (avec la fenêtre CLI « AmigaDOS ») reste ouvert derrière. [O]

### 2.4 Gadgets Intuition réellement présents [O]

Relus dans `window->FirstGadget` sur la vraie 1.3 (GadgetType / Flags / Activation en hexa) :

Vue éditeur (panneau PLAY), 5 gadgets :

| ID | type | position, taille | Flags | Activation | rôle |
|---|---|---|---|---|---|
| 320 | STRGADGET ($04) | 178,198 224×8 | 0 (GADGHCOMP) | RELVERIFY | champ texte noir de la ligne « Mem » |
| 321 | STRGADGET | 406,198 200×8 | 0 | RELVERIFY | 2e champ texte |
| 322 | BOOLGADGET ($01) | 610,198 28×8 | 3 (GADGHNONE) | GADGIMMEDIATE | case « NRM » |
| 775 | PROPGADGET ($03) | 332,19 88×13 | 4 (GADGIMAGE) | RELVERIFY\|GADGIMMEDIATE\|FOLLOWMOUSE ($0B) | glissière droite du panneau PLAY |
| 777 | PROPGADGET | 106,19 186×13 | 4 | $0B | glissière gauche |

PropInfo : Flags **$001B** (AUTOKNOB | FREEHORIZ | PROPBORDERLESS | bit $10 non défini en 1.3,
conservé tel quel), VPot $FFFF, VBody $FFFF.
Vecteurs de test du knob auto (Image de GadgetRender, recalculée par Intuition) :
- 88×13, HPot $294B, HBody $0842 ⇒ Image L/T **13,0**, W/H **6×13** ;
- 186×13, HPot $2271, HBody $0112 ⇒ Image L/T **24,0**, W/H **6×13**.
  (largeur minimale du knob 6, position = HPot × (largeur − knob) / $FFFF, arrondi bas). [O]

Vue FILES, 7 gadgets (les props PLAY sont retirés, `RemoveGList`/`AddGList` à chaque changement de
panneau) :

| ID | type | position, taille | Flags | Act | rôle |
|---|---|---|---|---|---|
| 4126 | PROP | 436,89 16×84 | 4 | $0B | ascenseur de la liste de fichiers (PropInfo $001D = AUTOKNOB\|FREEVERT\|PROPBORDERLESS\|$10, VBody $FFFF ⇒ knob 16×84) |
| 4127 | PROP | 620,89 16×84 | 4 | $0B | ascenseur des volumes (VBody $EDB5 ⇒ knob **16×78** en 0,0) |
| 320, 321, 322 | idem vue éditeur | | | | |
| 522 | STR | 136,43 320×8 | 0 | RELVERIFY | champ DIR: |
| 523 | STR | 136,54 320×8 | 0 | RELVERIFY | champ FILE: |

**Aucun des boutons FILES / PLAY / PLAY SONG / STOP… n'est un gadget.** [O]

Usage des fonctions de gadgets (comptes de sites d'appel) : `RefreshGList` ×27, `RemoveGadget` ×22,
`AddGadget` ×18, `ActivateGadget` ×11 (champs texte), `AddGList` ×10, `RemoveGList` ×10,
`NewModifyProp` ×3, `ModifyProp` ×2. Pas de menus (aucun SetMenuStrip). [O]

GadgetID : OctaMED décode **octet haut = groupe, octet bas = numéro** pour GADGETDOWN / GADGETUP
(lu dans `((struct Gadget*)IAddress)->GadgetID`). [O]

### 2.5 Entrées : souris, clics, clavier [O]

Boucle principale : `Wait(signal du UserPort | signaux timer/MIDI/série/…)` (avec, en mode
« occupé », un sondage `SetSignal(0, 0)`), puis `GetMsg` en boucle ; pour chaque message OctaMED
copie **Class, Code, Qualifier, IAddress, MouseX, MouseY** puis fait **ReplyMsg tout de suite**, et
traite la copie :

- **Class $08 MOUSEBUTTONS** :
  - Code **$68 SELECTDOWN** : test de zone sur des tables internes de rectangles à partir de
    **MouseX / MouseY du message** (y < 77 ⇒ table du panneau de boutons, sinon table de la vue
    courante) ⇒ action du bouton. **C'est le seul chemin par lequel FILES, PLAY, PLAY SONG, STOP…
    réagissent.**
  - Code $E8 SELECTUP / $E9 MENUUP : fin de glissement, `ReportMouse(FALSE, window)` (d0 = 0,
    a0 = window).
  - Le bouton droit arrive en MOUSEBUTTONS ($69/$E9) grâce à RMBTRAP (pas de menus).
- **Class $10 MOUSEMOVE** : glissements (activés par `ReportMouse(TRUE, window)` pendant un drag,
  5 sites).
- **Class $20 GADGETDOWN / $40 GADGETUP** : gadgets du §2.4, via IAddress→GadgetID.
- **Class $400 RAWKEY** : clavier (Code bit 7 = relâchement ignoré).
- Class $400000 INTUITICKS : traitée si présente (non incluse dans $478).
- `ModifyIDCMP(window, 0)` pendant les chargements, puis `ModifyIDCMP(window, $478)` ; aussi
  `$200000` (VANILLAKEY) et `$400` (RAWKEY) seuls pendant certaines saisies. [O]

Écran d'accueil : `WaitPort(UserPort)` / `GetMsg` / `ReplyMsg` jusqu'à un message **Class
MOUSEBUTTONS, Code $68**. [O]

Lecture directe du matériel : seulement dans les routines d'**échantillonnage** et de lecture
(`$BFE001` bit 6 = bouton gauche, `POTINP $DFF016` bit 10 = bouton droit pour interrompre ;
INTENA/DMACON/registres audio, CIA). **L'interface ne lit jamais la souris en direct.** [O]

Autres usages exec notables : `Disable/Enable` ×25, `AddIntServer` (VBlank « OctaMED VBlank »),
interruptions logicielles (« OctaMED SoftInt »), `ciax.resource` (timer CIA), `misc.resource` +
`serial.device` (MIDI), `audio.device` (allocation des 4 canaux), `CopyMem`, `AllocSignal`. [O]

---

## 3. `c/LoadWB` de la disquette OctaMED [O]

- Exécutable 1 136 o, 2 hunks, chaîne `$VER: loadwb 38.9 (30.3.92)` : **LoadWB de la 2.04**, sans
  rapport avec celui du Workbench 1.3.3 (`loadwb-13.md`).
- Séquence : `OpenLibrary("dos.library", 36)`. **Échec ⇒ `pr_Result2` (ThisTask+$94) := 122
  (ERROR_INVALID_RESIDENT_LIBRARY), retour 20**, sans aucun message ni autre appel.
  Sinon (2.0+ seulement) : `ReadArgs("-DEBUG/S,DELAY/S,CLEANUP/S,NEWPATH/S")`, échec ⇒
  `PrintFault(IoErr(), …)` ; `OpenLibrary("workbench.library", 36)` (échec ⇒ `PrintFault(122)`) [O] ;
  la suite (chemin CLI, démarrage par la workbench.library, catalogue `locale.library` /
  `sys/workbench.catalog`, d'après ses chaînes) n'a pas été suivie [S]. Ses chaînes ne contiennent ni
  « workbench.task » ni de message « Cannot find resident tag » : **aucun contrat avec le
  workbench.task de la ROM 1.3** [D] — et de toute façon il s'arrête avant, sur dos V36 [O].
- **Vraie 1.3** (ADF copie, startup = `loadwb` seul, captures à 45 s et 75 s identiques) : la fenêtre
  CLI « AmigaDOS » affiche
  `Copyright © 1987 Commodore-Amiga, Inc.` / `All rights reserved.` / `Release 1.3` /
  **`loadwb failed returncode 20`** / `1> ` — **pas de Workbench**. [O]
- Contrat observable pour notre ROM : `OpenLibrary("dos.library", 36)` doit échouer (lib_Version
  34 < 36) ; le CLI affiche alors le message d'échec standard car 20 ≥ FailAt (10) ; avec la
  startup d'origine (`ppshow c/np` / `loadwb` / `endcli`) le script **s'interrompt** à `loadwb`
  (`endcli` n'est jamais exécuté). Comportement identique à reproduire, pas un bug. [D]
- Remarque : avec la startup d'origine, `ppshow c/np` (PPShow 1.2a) affichait encore son image
  « 17 BIT SOFTWARE » ~20 s après un clic gauche sur la vraie 1.3 (captures à 33/64/95 s, clic à
  ~125 s, captures à 125 et 146 s, toutes identiques) ; la condition de sortie de PPShow n'a pas été déterminée. [O]

---

## 4. Pistes pour « l'interface se charge mal » et « les clics n'ont aucun effet »

Par ordre de probabilité [D] :

1. **`NewScreen.Height = -1`** : la vraie 1.3 en fait **256** (PAL ; hauteur d'écran standard).
   Si notre OpenScreen prend -1 au pied de la lettre (65535 lignes, ou hauteur NTSC 200), la fenêtre
   (hauteur recopiée de Screen.Height), la BitMap et le test `Height >= 256` d'OctaMED divergent ⇒
   mise en page fausse. Vérifier aussi `Width` / `Depth` / `ViewModes $C000` / BarHeight 10.
2. **`NewScreen.Type = $100F`** : le bit $1000 (NS_EXTENDED) doit être **toléré** (et conservé dans
   Screen.Flags) ; le pointeur `Extension` (+32) ne doit pas être lu par une 1.3 (NewScreen 1.3 =
   32 octets).
3. **MOUSEBUTTONS hors gadget** : pour un clic sur la fenêtre active BACKDROP|BORDERLESS|RMBTRAP en
   dehors de tout gadget, Intuition doit envoyer un IntuiMessage **Class $08, Code $68** (relâché
   $E8 ; bouton droit $69/$E9 grâce à RMBTRAP), **MouseX/MouseY relatifs à la fenêtre** (ici =
   coordonnées écran, fenêtre en 0,0), IAddress quelconque. Sans cela : l'écran d'accueil ne se ferme
   jamais, et aucun bouton du panneau ne réagit (ils ne sont pas des gadgets).
4. **Fenêtre active** : ACTIVATE doit rendre la fenêtre active à l'ouverture (WINDOWACTIVE dans
   Flags, IntuitionBase.ActiveWindow) — sinon les MOUSEBUTTONS iraient ailleurs.
5. `ModifyIDCMP(window, 0)` puis `ModifyIDCMP(window, $478)` (pendant chaque chargement) : le
   passage à 0 libère le UserPort, le retour à $478 en recrée un (sémantique AutoDocs) ; OctaMED
   relit `window->UserPort` à chaque tour de boucle, donc le nouveau port doit être en place au retour
   de ModifyIDCMP [D].
6. Moins probables mais visibles : `BltBitMapRastPort` minterm $C0 depuis une BitMap utilisateur,
   UCopList + `RethinkDisplay`, `ShowTitle(FALSE)`, `SetWindowTitles(w, -1, titre)`, knobs auto des
   props PROPBORDERLESS (vecteurs §2.4), sprites GetSprite/ChangeSprite/MoveSprite.

---

## 5. Reproduction (piste analyse)

- Décompactage d'`OctaMED` : émulateur 68000 minimal (unicorn) chargeant les hunks et simulant
  AllocMem/FreeMem, jusqu'au saut dans le premier segment décompacté ; scan des `JSR -LVO(A6)`
  regroupés par variable de base de bibliothèque, nommés d'après les `.fd` publics d'amitools. Ce
  travail et les dumps sont restés hors du dépôt.
- Relecture des structures publiques sur la vraie 1.3 : débogueur console FS-UAE (`m adresse n`),
  parcours ExecBase→LibList→IntuitionBase→FirstScreen→FirstWindow→FirstGadget.
- Ports : un seul FS-UAE à la fois ; ADF renommé à chaque séance.

## 6. Points ouverts

- Code de sortie de PPShow (clic, touche ou délai ?) non déterminé.
- Les champs `StringInfo` des gadgets texte et le contenu exact de l'UCopList n'ont pas été relus.
- La signification de « Mem 384448/ 206176 » n'a pas été vérifiée contre AvailMem.

## Relecture clean-room

Relecture du 2026-10-29.

- [x] Cibles désassemblées = logiciels tiers (`OctaMED`, `c/LoadWB` 2.04) ; la ROM Kickstart n'a été
  qu'**exécutée** (captures, structures publiques relues en mémoire). Aucune adresse de routine ROM,
  aucune suite d'instructions de la ROM.
- [x] Données issues de la ROM : uniquement des **valeurs observées à l'exécution** (champs de
  structures publiques, ColorMap relue, hauteur d'écran 256, flags de fenêtre) et le bandeau du CLI
  initial (`Copyright © 1987 Commodore-Amiga, Inc.` / `All rights reserved.` / `Release 1.3`), texte
  affiché et observable (inventorié dans `docs/audit/specs-review.md`). Pas de table, glyphe ni image
  de la ROM.
- [x] Les captures de `docs/analysis/octamed/` montrent l'écran d'OctaMED (logiciel tiers) sur la vraie
  ROM ; elles ne contiennent pas d'image issue de la ROM hormis le pointeur/couleurs venant du
  `system-configuration` de la disquette.
