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

## Relecture clean-room

- [x] Aucune suite d'instructions recopiée : format de fichier public (hunks), structures
  publiques (Process, WBStartup, WBArg, DiskObject, FileHandle), appels de bibliothèque et
  hypothèses.
- [x] Aucune donnée du programme reproduite, hormis des chaînes et des tailles.
- [x] §4 (relu) : séquence d'appels publics, conditions de sortie, champs de structures publiques,
  règle de choix d'OpenFont décrite par ses pondérations. Aucune suite d'instructions recopiée.
