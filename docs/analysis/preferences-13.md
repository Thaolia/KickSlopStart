# preferences-13.md — SYS:Prefs/Preferences (wb133.adf) : format du fichier et démarrage

> Piste ANALYSE (« dirty »). Source : `Prefs/Preferences` de `assets/wb133.adf` (56 180
> octets, 03-10-1990), extrait dans le scratch de la piste analyse, inspecté avec `hunktool` et un
> parseur de hunks, puis relogé à plat pour la lecture. Règles et structures publiques
> uniquement, aucune suite d'instructions recopiée.
>
> **Légende** : **[O]** observé · **[D]** déduit · **[S]** supposé.

---

## 1. Structure du fichier [O]

- **HUNK_HEADER** : aucune bibliothèque résidente, **table de 52 hunks**, first = 0, last = 51.
  **Aucun bit de mémoire** dans les tailles (bits 30–31 à 0 partout) : allocation en mémoire
  publique quelconque.
- **Blocs présents**, exclusivement :
  - HUNK_CODE ($3E9) × **30** ;
  - HUNK_DATA ($3EA) × **22** ;
  - HUNK_RELOC32 ($3EC) × 32 ;
  - HUNK_END ($3F2) × 52.
- **Absents** : HUNK_BSS, RELOC16/8, DREL32, RELOC32SHORT ($3FC), HUNK_SYMBOL, HUNK_DEBUG,
  **HUNK_OVERLAY ($3F5), HUNK_BREAK ($3F6)**. Ce n'est **pas** un exécutable à overlay. Le seul
  mot $000003F6 du fichier est une donnée à l'intérieur d'une table de relocation.
- **13 hunks de taille 0** : n° **7, 9, 13, 25, 27, 31, 36, 37, 40, 42, 44, 45, 51**. Ce sont des
  CODE ou DATA de 0 long-mot, mais ils sont bien présents dans la table et dans le fichier (bloc
  de longueur 0 suivi de HUNK_END).
- **Relocations** :
  - toutes en RELOC32 ;
  - de nombreuses cibles sont **en avant** : le hunk 0 vise les hunks 1, 10 et 46 ; le hunk 2
    vise 3, 4, 8, 47 et 48… ;
  - cible maximale : hunk 50 ;
  - **aucune relocation ne vise un hunk de taille 0** ;
  - le hunk 3 (DATA, 6 580 octets) contient 159 pointeurs vers lui-même (tables de structures).

Tailles en octets, de #0 à #51 :
524, 428, 1176, 6580, 4080, 116, 2700, **0**, 828, **0**, 6456, 992, 936, **0**, 1080, 92,
244, 132, 3032, 308, 1492, 2116, 3736, 140, 472, **0**, 24, **0**, 1528, 160, 208, **0**,
3292, 284, 320, 28, **0**, **0**, 20, 220, **0**, 36, **0**, 116, **0**, **0**, 320, 592, 368,
88, 484, **0**.

Rôles :
- #0 : code de démarrage ;
- #1 : ses variables ;
- **#10 : `main`** ;
- **#46 à #50 : vecteurs d'appel des bibliothèques** (un petit stub par fonction : charge la
  base depuis une globale, puis JSR −LVO).

## 2. Code de démarrage (hunk 0) [O]

C'est un démarrage C classique « à l'ancienne », du type `AStartup` : variables absolues, **pas
de registre de base A4**, aucun overlay.

**Entrée** : le démarrage mémorise **SP, D0 (longueur de la ligne de commande) et A0 (son
adresse)**. Il lit **SysBase en $4**, puis fait **FindTask(NULL)** (exec −294). Aucun autre
registre n'est lu (ni D1, ni A1–A6, ni A4).

**Lancement par le Workbench** (`pr_CLI` (+$AC) = 0) :
1. **OpenLibrary("dos.library", 0)** (exec −552). En cas d'échec : Alert $00038007 (AG_OpenLib |
   AO_DOSLib), puis retour 100.
2. **WaitPort(&pr_MsgPort)** (exec −384), puis **GetMsg** (exec −372) : le WBStartup est rangé
   dans une globale.
3. Si `sm_ArgList` (+$24) ≠ 0 : **CurrentDir(ArgList[0].wa_Lock)** (dos −126).
4. Si **`sm_ToolWindow` (+$20) ≠ 0** : **Open(ToolWindow, MODE_OLDFILE)** (dos −30), puis
   `pr_ConsoleTask` (+$A4) := `fh_Type` (+$08) du FileHandle. Ce handle sert aussi d'entrée et de
   sortie standard.
5. **`main(0, WBStartup)`** : saut au début du hunk 10.
6. Au retour :
   - CloseLibrary(dos) ;
   - **Forbid** (exec −132) puis **ReplyMsg(WBStartup)** (exec −378) ;
   - restauration de SP et retour avec D0.

**Lancement par le CLI** :
1. OpenLibrary("dos") ;
2. `argv[0]` = `cli_CommandName` (+$10, BSTR) ;
3. découpe de la ligne D0/A0 en argv : guillemets, et `*N` / `*E` traités ;
4. **Input() (dos −54)** et **Output() (dos −60)** ;
5. main(argc, argv).

**Début de `main` en mode Workbench** :
1. **OpenLibrary("icon.library", 0)**, par le stub exec −552 ;
2. on prend `ArgList[1]` si `sm_NumArgs` > 1 (projet), sinon `ArgList[0]` ;
3. **CurrentDir(wa_Lock)** ;
4. **GetDiskObject(wa_Name)** (icon −78) ;
5. **FindToolType(do_ToolTypes (+$36), "PREFS")** (icon −96) ;
6. **MatchToolValue** (icon −102) avec `"pointer"`, `"printer"` et `"serial"` ;
7. FreeDiskObject (icon −90) ;
8. CurrentDir(ancien) ;
9. CloseLibrary(icon).

L'ouverture de l'écran et des fenêtres vient ensuite (intuition et graphics, non détaillés ici).

## 3. Hypothèses sur le saut dans les données [S, classées]

Symptôme : instruction illégale. Le PC pointe sur un **long-mot de données qui contient une
adresse** (le mot $00C2 n'est pas un opcode valide). On a donc **sauté vers une adresse
calculée ou relogée fausse**, ou **retourné sur une pile corrompue**. Il n'y a pas d'overlay en
jeu (§1).

1. **Hunks de taille 0 mal traités par notre LoadSeg** — hypothèse la plus probable.
   - Le vrai LoadSeg crée un segment pour **chacun** des 52 hunks : la taille plus le lien, soit
     au minimum 8 octets pour un hunk vide, chaîné dans la seglist. **La numérotation des hunks
     reste celle de la table.**
   - Si notre loader saute les hunks de taille 0, les fusionne ou ne leur donne pas d'adresse,
     **toutes les relocations vers les hunks suivants sont décalées** : jusqu'à 13 rangs pour les
     derniers. Les JSR vers les stubs des hunks 46–50 atterrissent alors dans d'autres hunks,
     souvent des DATA.
   - Même effet si `main` (hunk 10, juste après le hunk 9 vide) est mal adressé : le JSR de
     démarrage tombe dans le hunk suivant ou précédent.
2. **Relocations en avant** : le hunk 0 vise déjà les hunks 10 et 46. Le vrai LoadSeg
   **alloue tous les hunks à la lecture de HUNK_HEADER**, avant toute relocation. Un loader qui
   alloue au fil de l'eau et reloge avec une base encore inconnue (0 ou garbage) produirait
   exactement ce type de saut.
3. **Table de hunks de taille fixe** : 52 entrées, cibles jusqu'à 50. Une limite interne (32,
   48…) déborderait.
4. Moins probable : un retour de `main` ou d'un stub sur une pile corrompue (usp contient une
   adresse plausible de code), ou une base de bibliothèque fausse lue par un stub (a6 = $C021DE
   est impair : c'est un indice si a6 devait être une base de bibliothèque). Voir la méthode
   ci-dessous.

**Méthode de confirmation [D]** :
1. Afficher la seglist créée par notre LoadSeg : pour chaque segment, adresse = BADDR(lien) + 4
   et taille. Vérifier qu'il y a **52 segments** et que les 13 hunks vides existent.
2. Situer **pc = $C2AB30** et **(usp) = $C2D1D2** dans cette seglist, au format (n° de hunk,
   offset), puis comparer avec le tableau des tailles ci-dessus.
   - Si (usp) tombe dans un hunk de **CODE** juste après un JSR absolu, la cible de ce JSR, prise
     dans le fichier, dit quel hunk était visé. On voit alors le décalage de numérotation.
   - Si pc tombe dans un hunk de DATA voisin du hunk visé, l'hypothèse 1 ou 2 est confirmée.

---

## 4. De main jusqu'à l'affichage : appels et sorties silencieuses (lancement Workbench) [O sauf mention]

Suite de la partie icon.library (§2). « Sortie » désigne le retour au démarrage, qui ferme dos,
fait ReplyMsg du WBStartup et revient avec D0.

| # | Appel (bibliothèque, LVO) | Condition de sortie | Visible ? |
|---|---|---|---|
| 1 | exec **FindPort("preferences_inuse.task")** (−390) | **port trouvé ⇒ sortie code 0**, garde-fou contre une deuxième instance | **silencieux** |
| 2 | création du port public `"preferences_inuse.task"` : AllocSignal, AllocMem, AddPort (exec −330/−198/−354) | échec ⇒ sortie 0 | silencieux |
| 3 | exec **OpenLibrary("graphics.library", 0)** | échec ⇒ **DisplayAlert en boucle** (pas de sortie) | alerte |
| 4 | exec **OpenLibrary("intuition.library", 0)** | idem | alerte |
| 5 | intuition **AllocRemember**(… , taille, **MEMF_CHIP**) × 6 : copie en CHIP des données d'images | un échec ⇒ DisplayAlert, FreeRemember, CloseLibrary × 2, sortie | alerte |
| 6 | exec **AllocMem(5984, MEMF_PUBLIC\|CLEAR)** : 136 gadgets de 44 octets | échec ⇒ DisplayAlert, sortie | alerte |
| 7 | exec InitSemaphore / AddTail (deux SignalSemaphore privés) | — | — |
| 8 | intuition **GetPrefs(buffer, 232)** (−132) ; deux copies de sauvegarde de 232 octets | aucune (retour non testé) | — |
| 9 | dos **DateStamp** (−192) | — | — |
| 10 | intuition **ViewAddress** (−294), puis éventuellement **RemakeDisplay** (−384) pour recentrer l'affichage selon les champs View/Preferences de la ligne suivante | — | — |
| 11 | intuition **OpenWindow** d'une fenêtre **1×1** : Left 0, Top 0, Flags $00021006 (DRAG, DEPTH, ACTIVATE, NOCAREREFRESH), IDCMP 0, MaxW 640, MaxH 200, Type WBENCHSCREEN, Title = pointeur interne | échec ⇒ DisplayAlert, FreeMem, CloseLibrary, sortie | alerte |
| 12 | **MoveScreen(win->WScreen, −Screen.LeftEdge, −Screen.TopEdge)** (−162) : ramène l'écran WB en (0,0) ; puis **CloseWindow** (−72) de la fenêtre 1×1 | — | — |
| 13 | intuition **OpenWindow** de la vraie fenêtre : **640×200** en (0,0), **IDCMP $70** (MOUSEMOVE, GADGETDOWN, GADGETUP), FirstGadget = jeu de gadgets du mode, mêmes Flags | échec ⇒ DisplayAlert, retour 0 ⇒ restauration des Prefs puis sortie | alerte |
| 14 | graphics **OpenFont({"topaz.font", 9, 0, FPF_ROMFONT})** (−72) | voir ligne 15 | — |
| 15 | graphics **SetFont(win->RPort, font)** (−66) ; **D0 est testé au retour** | **D0 = 0 ⇒ CloseFont, CloseWindow, DisplayAlert, retour 0 ⇒ sortie** | alerte |
| 16 | dessin de l'écran du mode (graphics), ObtainSemaphore / ReleaseSemaphore (exec −564/−570) | — | — |
| 17 | intuition **RefreshGadgets**(gadgets, fenêtre, NULL) (−222) | — | — |
| 18 | boucle : exec **Wait(1 << UserPort->mp_SigBit)** (−318), **GetMsg** (−372), ReplyMsg ; les MOUSEMOVE en attente sont vidés | — | — |

**Pièges pour une ROM réimplémentée** :
- **Ligne 15 (SetFont)** : le vrai SetFont 1.3 **ne touche pas D0**. D0 contient donc encore la
  valeur de l'OpenFont précédent, le pointeur de police, que le stub du programme n'a pas
  écrasé. Le programme y voit « succès ».
  - Un SetFont qui **met D0 à 0** fait sortir le programme.
  - De même, un OpenFont qui rend NULL : le programme le passe tel quel à SetFont.
- **Ligne 14 (OpenFont)** : le vrai OpenFont 1.3 **ne demande pas la taille exacte**. Il
  parcourt les polices de même nom (`GfxBase->TextFonts`) et rend la **meilleure
  correspondance** :
  - score de départ $7FFF ;
  - pénalité **256 par ligne de trop** et **64 par ligne de moins** ;
  - pénalités supplémentaires pour les différences de style et de drapeaux ;
  - retenue si le score est > 0.
  Une demande topaz 9 rend donc topaz 8 si topaz 9 n'existe pas. La vraie ROM contient topaz 8
  **et** 9. Un OpenFont exigeant la taille exacte rend NULL, ce qui mène à la ligne 15.
- **DisplayAlert** : toutes les sorties « alerte » ci-dessus deviennent **silencieuses** si notre
  DisplayAlert ne fait rien. Les appels sont `DisplayAlert(RECOVERY_ALERT (0), texte, 60)`.
- **Ligne 1** : le port `"preferences_inuse.task"` n'est retiré qu'à la sortie normale. Après un
  **plantage** de Preferences (comme avec l'ancien LoadSeg), il reste dans la liste des ports
  publics, et **toute nouvelle exécution sort aussitôt, en silence, avec le code 0**. Il faut
  rebooter, ou vérifier FindPort, avant de conclure.

**Champs lus directement** :
- `Window` : WScreen (+$2E), RPort (+$32), UserPort (+$56) → mp_SigBit (+$0F) ;
- `Screen` : LeftEdge (+$08), TopEdge (+$0A) ;
- `View` (de ViewAddress) : DyOffset (+$0C), DxOffset (+$0E) ;
- `IntuiMessage` : Class (+$14), comparé à MOUSEMOVE ;
- `Preferences` (buffer de 232 octets) : ViewXOffset/ViewYOffset (+$76/+$77), ViewInitX/Y
  (+$78/+$7A), +$7C (seuls les 2 bits de poids fort sont gardés) et les champs +$A4, +$A6, +$B2.
- **Aucun champ privé d'IntuitionBase ou de GfxBase** n'est lu dans cette séquence [O, par
  absence].

**Ordre de vérification conseillé [D]** :
1. FindPort("preferences_inuse.task") après reboot ;
2. retour de SetFont (D0 préservé) et OpenFont(topaz 9) ;
3. DisplayAlert visible ;
4. OpenWindow 640×200 sur l'écran WB (hauteur ≥ 200).

## 5. Fenêtre principale : cadre de centrage de l'écran et son petit carré [O sauf mention]

Repères (image relogée à $100000, hunks contigus alignés sur 8) : constructeur des gadgets
$104A4C, tableaux de champs $103278… (un mot par gadget et par champ), PropInfo $1039E8 (22 octets
chacun), Image $103B04 (20 octets chacune), dessin de fond d'un mode $1003C0, séquence initiale
$104726…$1047DA, retour au mode principal $104F78…$104FDA.

### 5.1 C'est un seul gadget proportionnel : le gadget n° 17

Le grand cadre **et** le petit carré sont tous deux dessinés par **intuition**, lors du rendu de
ce gadget. Preferences ne trace rien de spécifique dans cette zone : son seul dessin qui la touche
est le fond général de la fenêtre, en couleur 2.

| Champ `Gadget` | Valeur |
|---|---|
| LeftEdge, TopEdge, Width, Height | **200, 62, 240, 70** (coordonnées fenêtre) |
| Flags | **$0007** = GADGHNONE (3) \| GADGIMAGE (4) ; aucun GRELxxx, pas SELECTED ni DISABLED |
| Activation | **$000B** = RELVERIFY \| GADGIMMEDIATE \| FOLLOWMOUSE |
| GadgetType | **$0003** = PROPGADGET (pas de REQGADGET, pas de GZZGADGET) |
| GadgetRender | Image du knob (ci-dessous) |
| SelectRender | **la même** Image (même pointeur) |
| GadgetText, MutualExclude, UserData | NULL / 0 / NULL |
| SpecialInfo | PropInfo ci-dessous |
| GadgetID | 17 |

| Champ `PropInfo` | Valeur initiale |
|---|---|
| Flags | **$0006** = FREEHORIZ \| FREEVERT ; **pas AUTOKNOB**, **pas PROPBORDERLESS** |
| HorizPot / VertPot | calculés avant OpenWindow à partir des prefs (§5.4) |
| HorizBody / VertBody | **$0800 / $0800** |
| CWidth…TopBorder | 0 (remplis par intuition) |

| Champ `Image` du knob | Valeur |
|---|---|
| LeftEdge, TopEdge | 0, 0 (réécrits par intuition à la position du knob) |
| Width × Height × Depth | **16 × 8 × 1** |
| ImageData | **non NULL** : copie en mémoire CHIP (AllocRemember MEMF_CHIP au démarrage, pointeur patché) |
| PlanePick / PlaneOnOff | **1 / 0** |
| NextImage | NULL |

Géométrie des données (sans les reproduire) : la **première ligne** est entièrement à 1, et sur
les **7 lignes suivantes** seules les **deux colonnes de gauche** sont à 1 ; tout le reste est à 0.
Avec PlanePick 1 et PlaneOnOff 0, DrawImage donne **couleur 1 (blanc)** sur ces bits et **couleur
0** partout ailleurs, plan 1 compris. Le knob est donc un « L » blanc (1 ligne en haut, 2 pixels
à gauche) sur un fond de couleur 0. **Il n'est pas plein** : son intérieur a la même couleur que
l'intérieur du conteneur, d'où l'aspect « liseré seul » sur la vraie ROM.

La fenêtre est ouverte avec **NewWindow.DetailPen = BlockPen = $FF**. Intuition reprend donc
les stylos de l'écran Workbench : **Window.DetailPen = 0**, **BlockPen = 1** [D, règle publique
d'OpenWindow ; aucune autre valeur n'est fournie].

### 5.2 Ce qui produit le fond de couleur 0 du grand cadre

C'est le rendu standard d'un PROPGADGET par intuition (`intuition-prop-v34.md` §3.1), appliqué
à ce gadget :
1. **RectFill de toute la boîte** (200,62)–(439,131) en **Window.DetailPen = 0**, en JAM2 ⇒ fond
   bleu ;
2. **cadre** de la boîte en **BlockPen = 1** (blanc), puisque PROPBORDERLESS est absent. C'est le
   « grand cadre » ;
3. **DrawImage(GadgetRender)** à la position du knob ⇒ le « L » blanc.

GADGHNONE : aucun surlignage, même quand le gadget est sélectionné.

### 5.3 Ordre d'appel et moment du dessin

Ouverture (§4, lignes 13 à 17) :
1. **OpenWindow** (−204) avec FirstGadget = la liste du mode, qui contient le gadget 17. Intuition
   y fait un premier rendu des gadgets.
2. OpenFont / SetFont (§4).
3. **Fond du mode** ($1003C0, rastport de la fenêtre, mode 0) :
   - **SetDrMd(rp, JAM1)** (−354) ;
   - pour chaque rectangle du mode : SetAPen (−342), puis **RectFill** (−306). Le premier
     rectangle est **(1,10)–(637,198) en stylo 2** : il recouvre toute la fenêtre, gadget 17
     compris, **et efface le premier rendu** ;
   - les rectangles suivants (cadres stylo 1 et intérieurs stylo 0 des autres zones) **ne
     touchent pas** la boîte du gadget 17 ;
   - viennent ensuite des traits (Move/Draw −240/−246) et des textes (Move, SetAPen, Text −60),
     eux aussi hors de la boîte.
4. Dessins annexes : palette, pointeur, valeurs ($109CF0, $1005D2, $10557A), tous hors de la
   boîte du gadget 17. Au démarrage, $10557A n'appelle pas ModifyProp.
5. **RefreshGadgets(premier gadget du mode, fenêtre, NULL)** (−222). C'est ce rendu qui laisse
   le fond **en couleur 0**, le cadre blanc et le knob (§5.2).

Retour au mode principal depuis un autre mode ($104F78) :
- même fond $1003C0 ;
- **AddGadget(win, gadget i, −1)** (−42) pour i = 0…37 ;
- dessins annexes, puis RefreshGadgets(gadget 0, win, NULL). Même résultat.

Plus tard :
- **ModifyProp(gad, win, NULL, PropInfo.Flags, HPot, VPot, HBody, VBody)** (−156) ($105616,
  appelé par $10557A) est utilisé quand les prefs sont rechargées en bloc (boutons de
  restauration). Il redessine le gadget, fond compris.
- Le glissement du knob est géré par intuition (FOLLOWMOUSE + MOUSEMOVE dans l'IDCMP $70).
  Au relâchement, Preferences recalcule ViewX/YOffset puis appelle RemakeDisplay
  ($1057FA, §4 ligne 10).

### 5.4 Pots initiaux (formule) [O]

HorizPot = (31 − (129 − ViewInitX) + ViewXOffset) × 2048, et VertPot = (31 − (56 − ViewInitY) +
ViewYOffset) × 2048, sur 16 bits. Les offsets sont bornés à −32..+31 lors de leur réécriture.

### 5.5 Diagnostic de l'écart observé [D]

- **Fond resté en couleur 2** : notre rendu de PROPGADGET ne remplit pas la boîte du gadget en
  Window.DetailPen avant le cadre et le knob. Une autre possibilité est un DetailPen de fenêtre
  qui n'est pas résolu en 0 depuis le $FF de la NewWindow. Le fond général (stylo 2) peint par
  Preferences reste alors visible.
- **Petit carré « plein »** : notre knob est correct (intérieur couleur 0, L blanc). Il paraît
  plein uniquement parce qu'il est posé sur un fond de couleur 2. Une fois l'étape 1 de §5.2
  faite, il doit se fondre dans le fond et ne laisser voir que le L.
- Correspondance avec la capture : la boîte (200..439, 62..131) s'accorde avec x ≈ 388..636 et
  y ≈ 246..390 de la capture, si l'on applique un décalage horizontal d'environ +188 et un
  doublement vertical [D].

## Relecture clean-room

- [x] Aucune suite d'instructions recopiée : format de fichier public (hunks), structures
  publiques (Process, WBStartup, WBArg, DiskObject, FileHandle), appels de bibliothèque et
  hypothèses.
- [x] Aucune donnée du programme reproduite, hormis des chaînes et des tailles.
- [x] §4 (relu) : séquence d'appels publics, conditions de sortie, champs de structures publiques,
  règle de choix d'OpenFont décrite par ses pondérations. Aucune suite d'instructions recopiée.
- [x] §5 (relu) : champs publics Gadget/PropInfo/Image/NewWindow, appels de bibliothèque et ordre
  de dessin ; image du knob décrite en géométrie seulement (aucune donnée reproduite).
