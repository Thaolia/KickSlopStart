# monkey-startup.md — `monkey_island` (Monkey Island FR [cr Defjam]) : démarrage jusqu'à « Appuyez sur ENTER »

> Piste ANALYSE (« dirty »). Source : disque 1/4, fichier racine `monkey_island` (108 408 o, en-tête
> bloc 881), extrait par le lecteur OFS tolérant et relogé à plat à $100000.
>
> L'exécutable **n'est pas compacté**. C'est un programme C (Lattice, données adressées par A4 =
> début du hunk 4) avec 5 hunks :
> - #0 : stub ajouté par le crack ;
> - #1 : stub ;
> - #2 : CODE de 98 800 o ;
> - #3 : **DATA en CHIP** de 296 o (copper lists) ;
> - #4 : DATA + BSS de 29 312 o.
>
> Bases de bibliothèques : SysBase (4), IntuitionBase (A4+$7258), GfxBase (A4+$725C),
> DOSBase (A4+$726C), ConsoleDevice (A4+$6FAC). **Légende** : **[O]** observé · **[D]** déduit ·
> **[S]** supposé. Appels publics et comportement ; aucune suite d'instructions recopiée, aucune
> donnée.

---

## 0. Ajout du crack (hunk 0) [O]

Avant le démarrage C, le stub du crack **copie une routine de 50 octets à l'adresse absolue
$300–$35F**, dans la zone des vecteurs utilisateur. Elle est appelée plus tard par le code du jeu à
la place de la protection. **$300–$360 doit donc rester libre et intact.**

## 1. Démarrage C (Lattice) [O]

- Effacement du BSS ; SetSignal(0, $3000) (exec −306).
- OpenLibrary("dos.library", 0) (−552). Échec ⇒ sortie, code 100.
- ExecBase->ThisTask (+$114) : pr_CurrentDir est gardé.
- **Lancé depuis le CLI** (pr_CLI ≠ 0) : argv est construit à partir de `cli_CommandName` et de
  la ligne d'arguments. Il n'y a **ni Open ni WaitPort**.
- **Lancé depuis le WB** :
  - WaitPort/GetMsg (−384/−372) du WBStartup sur pr_MsgPort ;
  - CurrentDir(sm_ArgList→wa_Lock) (−126) ;
  - si sm_ToolWindow existe : Open(ToolWindow, MODE_OLDFILE) (−30), et pr_ConsoleTask reçoit le
    port de son handler.
- Appel de `main`. La sortie passe par CloseLibrary, Forbid et ReplyMsg du WBStartup s'il y en a
  un.

## 2. Initialisation (fonction $11414C), dans l'ordre [O]

1. AllocMem(n, MEMF_PUBLIC) (exec −198). Échec ⇒ retour 0, **sortie silencieuse**.
2. Init interne (réglages, puis tables de la souris et du pointeur).
3. **OpenLibrary("intuition.library", 1)** et **OpenLibrary("graphics.library", 1)**. Un échec
   ferme ce qui est ouvert, puis sortie silencieuse.
   - **GfxBase+$CF bit 2** est testé : c'est l'octet bas de `gb_DisplayFlags`, bit **PAL**. Le
     programme en tire deux paramètres : (5, 5) en PAL, (4, 6) en NTSC.
4. **OpenDevice("console.device", −1, ioreq local, 0)** (exec −444) : io_Device est gardé comme
   **ConsoleDevice**, qui ne servira qu'à RawKeyConvert. **Le résultat d'OpenDevice n'est pas
   testé.**
5. Intuition **CloseWorkBench()** (−78). Le résultat n'est pas testé.
6. **Bitmaps du jeu** ($114436) :
   - graphics **InitBitMap(bm1 = A4+$6FE6, profondeur 5, 320, 200)** (−390) ;
   - graphics **InitBitMap(bm2 = A4+$700E, profondeur 5, 320, …)** ;
   - pour chacun, **AllocMem(40 000, MEMF_CHIP|MEMF_PUBLIC)** (−198), découpé à la main en
     5 plans de 8 000 o, à +0, +$1F40, +$3E80, +$5DC0 et +$7D00. Il n'y a pas d'AllocRaster.
   - Échec d'une allocation ⇒ DisplayAlert (point 11) avec le code 6, puis sortie.
7. AllocMem($24, PUBLIC|CLEAR) (code 5 en cas d'échec).
8. **OpenScreen(NewScreen)** (−198), avec la NewScreen de A4+$151A :

   | Champ | Valeur |
   |---|---|
   | LeftEdge, TopEdge, Width, Height | 0, 0, **320, 200** |
   | Depth | **5** |
   | DetailPen, BlockPen | 0, 1 |
   | ViewModes | **$4000 (SPRITES)** : lores, ni HIRES ni LACE |
   | Type | **$004F = CUSTOMSCREEN \| CUSTOMBITMAP**. **Ni SCREENQUIET ($0100) ni SHOWTITLE ($0010)** |
   | Font | **TextAttr { "topaz.font", 8, style 0, FPF_ROMFONT }** |
   | DefaultTitle, Gadgets | NULL, NULL |
   | **CustomBitMap** | **bm1 (A4+$6FE6)**, renseigné juste avant l'appel |

   Échec ⇒ code 4, sortie.
9. **ShowTitle(screen, FALSE)** (−282) : la barre de titre passe derrière les fenêtres BACKDROP.
10. **OpenWindow(NewWindow)** (−204), avec la NewWindow de A4+$153A et `Screen` = cet écran :

    | Champ | Valeur |
    |---|---|
    | LeftEdge, TopEdge, Width, Height | 0, 0, 320, 200 |
    | DetailPen, BlockPen | 0, 1 |
    | **IDCMPFlags** | **$0004840C** : REFRESHWINDOW, MOUSEBUTTONS, **RAWKEY**, DISKINSERTED, ACTIVEWINDOW |
    | **Flags** | **$00011940** : SIMPLE_REFRESH ($40), **BACKDROP** ($100), **BORDERLESS** ($800), **ACTIVATE** ($1000), **RMBTRAP** ($10000) |
    | FirstGadget, CheckMark, Title, BitMap | NULL |
    | Min / Max | 48×24 / 320×189 |
    | Type | CUSTOMSCREEN |

    Échec ⇒ code 2, sortie.
11. Chaque sortie sur erreur passe par la routine $11430E. Celle-ci **DisplayAlert(0 =
    RECOVERY, texte, 50)** (−90), puis ferme dans l'ordre inverse : RemIntServer, pointeur,
    CloseWindow, CloseScreen, FreeMem, **OpenWorkBench** (−210), CloseLibrary.
12. **Mise en place de l'affichage ($114ED0)** : voir §3.
13. FindTask(NULL) (−294) : **pr_WindowPtr (+$B8) := la fenêtre**, l'ancienne valeur étant
    gardée. Les requesters de dos s'ouvrent donc sur cet écran.
14. Tables internes ; init du pointeur ($113BA8 : AllocMem, **SetPointer** −270, ClearPointer
    −60, FreeMem).
15. **AddIntServer(INTB_VERTB = 5, &interrupt)** (exec −168) :
    - Interrupt : ln_Type 2, **ln_Pri −60**, is_Data = A4+$59C4 ;
    - le serveur **ajoute une vitesse à un compteur et incrémente un compteur de trames**, puis
      rend 0, ce qui laisse la chaîne continuer ;
    - **le jeu chronomètre tout avec ce compteur.**
16. Détection du support ($114568) :
    - dos **CurrentDir(0)** puis CurrentDir(ancien) (−126) ;
    - **Info(lock, InfoData)** (−114) ;
    - **id_NumBlocks (+$0C) = 1758** ⇒ indicateur « disquette ».
17. **GetPrefs(buf, 232)** (−132) : ViewXOffset/ViewYOffset (+$76/+$77) et ViewInitX/ViewInitY
    (+$78/+$7A) servent à placer la ligne de séparation de la copper list (§3).

Le jeu lit ensuite ses données (§4) et arrive à l'écran « Appuyez sur ENTER ». Ce texte n'est
**pas** une chaîne du programme : il vient des données de jeu (charsets et scripts SCUMM des
fichiers Rooms). Il est **dessiné par le jeu lui-même dans bm1/bm2**, au CPU et au blitter :
- **OwnBlitter (−456) / WaitBlit (−228) / DisownBlitter (−462)** ;
- registres blitter écrits directement.

**Il n'y a ni Text(), ni Move(), ni SetAPen, ni SetRast, ni OpenFont, ni OpenDiskFont.**

## 3. Construction de l'affichage : liste copper utilisateur + copper lists maison en CHIP [O]

$114ED0, appelée avec la fenêtre :
1. **LoadRGB4(&Screen.ViewPort, table, 1)** (−192) : **une seule couleur** (COLOR00). Les autres
   couleurs sont écrites plus tard par le jeu, dans ses propres copper lists.
2. **Lecture des 5 pointeurs de plan de `Screen.BitMap`** (Screen +$B8, Planes à +8), recopiés
   dans la copper list maison n°1 du hunk 3 (CHIP, $118240). Les 5 plans de **bm2** sont recopiés
   dans la liste n°2 ($118320).
3. **Lecture de gb_copinit (GfxBase +$26)**, recopié dans les deux listes maison pour y recharger
   COP1LC.
4. AllocMem(12, MEMF_CHIP? $10002 = CLEAR|CHIP), puis graphics **UCopperListInit(ucl, 12)**
   (−594), puis les instructions :
   - **CWait(v = −1, h = $24)** (−378) et CBump (−366) ;
   - **CMove(BPLCON0, $0200)** (−372) et CBump ;
   - **CMove(COP1LCH, haut de la liste n°1)**, CMove(COP1LCL, bas), **CMove(COPJMP1, 0)** :
     **le copper système saute dans la liste maison** ;
   - CWait(100, 128), CWait(10000, 255) : fin de liste.
5. **Screen.ViewPort.UCopIns (Screen +$40) := ucl**, puis intuition **RethinkDisplay()** (−390).

Copper lists maison (hunk 3, CHIP), décrites en registres :

| Liste n°1 ($118240) | Liste n°2 ($118320) |
|---|---|
| BPLCON2/BPLCON1 := 0 | |
| **COLOR00–COLOR31** (32 MOVE, valeurs posées par le jeu) | |
| DMACON := $0000 ; **COP1LC := liste n°2 et COPJMP1** (ce MOVE est activé ou désactivé par le jeu, en réécrivant son registre) | |
| DMACON := $8100 (BPLEN) ; **BPLCON0 := $5200** (5 plans, COLOR) | DMACON := $8100 ; **BPLCON0 := $5200** |
| **BPL1PT…BPL5PT := plans de Screen.BitMap** | **BPL1PT…BPL5PT := plans de bm2** |
| **COP1LC := gb_copinit** | **COP1LC := gb_copinit** |
| WAIT ligne de séparation ($80E1 ou $00E1, puis (200 + décalage) << 8) | idem |
| BPLCON0 := $0200 (écran éteint sous la zone) ; fin | idem |

**Ce que cela exige de la ROM** :
- **(a)** OpenScreen avec **CUSTOMBITMAP** doit **afficher la BitMap fournie**. Intuition copie
  `*ns_CustomBitMap` dans `Screen.BitMap` et **n'alloue aucun plan**. Le jeu lit
  `Screen.BitMap.Planes[]` et dessine dans bm1. Si notre OpenScreen alloue ses propres plans :
  - le copper affiche nos plans, vides, donc **un écran noir sans texte** ;
  - le jeu dessine ailleurs.
- **(b)** MakeVPort/MrgCop (via RethinkDisplay) doivent **insérer `vp_UCopIns`** dans la copper
  list de la vue, à la position du CWait relative au ViewPort. Si UCopIns est ignoré :
  - les listes maison ne tournent jamais ;
  - on ne voit que l'écran intuition : barre de titre, gadgets, nos plans ;
  - c'est **exactement le symptôme décrit**.
- **(c)** `gb_copinit` (GfxBase +$26) doit être la vraie copinit, relancée par le matériel à
  chaque trame, comme pour les cracktros.
- **(d)** ShowTitle(FALSE) avec une fenêtre BACKDROP plein écran doit cacher la barre de titre.
  C'est secondaire : sur la vraie ROM, la liste maison prend la main dès le haut de l'écran.

## 4. Fichiers [O]

Toutes les E/S passent par les enveloppes Lattice :
- **open** : Lock(nom, SHARED −2) pour tester l'existence, puis UnLock, DeleteFile si création,
  et Open(MODE_OLDFILE 1005 / MODE_NEWFILE 1006) ;
- **read** et **write** (−42/−48) : Read(fh, buf, n) ; résultat −1 ⇒ IoErr (−132) ;
- **lseek** : **Seek(fh, pos, mode − 1)** (−66), donc C 0/1/2 ⇒ OFFSET_BEGINNING −1, CURRENT 0,
  END 1. Valeur rendue :
  - SEEK_SET ⇒ pos ;
  - SEEK_CUR ⇒ **ancienne position rendue par Seek + pos** ;
  - SEEK_END ⇒ un second **Seek(fh, 0, OFFSET_CURRENT)**.

  **Cela exige que Seek rende l'ANCIENNE position**, comme le dos 1.3, et −1 en cas d'erreur.
  Un Seek qui rend la nouvelle position fausse tous les décalages relatifs et les tailles.
- **close** (−36).

Noms construits (chaînes du programme) :
- "Rooms/%s" et "%sRooms/%s" (préfixe de volume) ;
- **"music.dat"** et **"sample.dat"** (messages « Can't open … » s'ils manquent) ;
- "%s.%d\\%s" et "XXX.lfl" (salles) ;
- **"diskXX.lec"** (DISK01.LEC, 365 Ko, lu par Seek + Read) ;
- "savegame._x_".

Messages du moteur en cas d'échec : « Room %d not in disk%02d.LEC », « Please Insert Disk %c »,
« Unable to find '%s' Press ENTER ». Ils s'affichent eux aussi dans les bitmaps du jeu.

Lecteur de disque (DISKINSERTED dans l'IDCMP) : changements de disquette.

## 5. Accès matériels et vecteurs (lecteur de musique, $100F20–$1017BE) [O]

Le lecteur de musique, activé au premier morceau, prend le matériel **directement** :
- **Autovecteurs écrits directement** (sauvés, puis restaurés à l'arrêt) :
  - **$6C (niveau 3)** := son handler. Celui-ci appelle le lecteur sur COPER, ou sur VERTB si
    VHPOSR < ligne $0A, puis **chaîne vers l'ancien vecteur**. La chaîne VERTB de l'OS continue
    donc ;
  - **$70 (niveau 4, audio)** := son handler, **sans chaînage** : audio.device ne voit plus ses
    interruptions ;
  - **$78 (niveau 6, EXTER)** := son handler. Il lit l'ICR de CIA-B, acquitte INTREQ $2000,
    appelle le lecteur et fait RTE, **sans chaîner vers l'OS**.
- **CIA-B** :
  - timer B ($BFD600/$BFD700) := $2E2E si ExecBase->VBlankFrequency (+$212) = 50, ajusté selon
    un bit de configuration (valeurs $2E2E ou $37F0) ;
  - **CRB ($BFDF00) := $11** (démarrage, mode continu) ;
  - **ICR ($BFDD00) := $82** (autorise l'interruption du timer B) ;
  - **INTENA := $A000** (EXTER).
- INTENA $8020, DMACON des canaux audio, registres audio $A8/$B8/$C8/$D8, ADKCON $00FF.
- CIA-A PRA bit 1 (filtre) mis à 1.

**Conséquence pour notre ROM [D, à vérifier]** :
- **Tant que la musique joue, tout ce qui passe par l'interruption de niveau 6 de l'OS est mort.**
  - Notre timer.device **UNIT_MICROHZ utilise CIA-B / INT6** (notes du projet). Après l'arrivée
    de la musique, **toute requête MICROHZ, ou tout code qui en dépend, n'est plus jamais
    servie**.
  - Cela vaut pour un trackdisk qui attend des délais MICROHZ, un Delay() s'il passe par MICROHZ,
    la répétition clavier… ⇒ **blocage silencieux du chargement**.
- **Sur la vraie 1.3, timer.device utilise ciaa.resource** : la chaîne « ciaa.resource » est
  dans timer.device. Le niveau 6 n'y sert pas à MICROHZ, et la prise du vecteur $78
  par le jeu est sans effet sur le chargement disque.
  - trackdisk ouvre bien ciab.resource, mais rien n'indique qu'il ait besoin de
    l'interruption pour lire [S].
- **Recommandation** : MICROHZ et tout délai disque doivent passer par CIA-A (niveau 2, PORTS).
  Sinon, il faut ne dépendre d'aucune interruption de niveau 6 pendant les lectures.

## 6. Attente de ENTER [O]

Boucle de lecture des événements ($1136B8), par **GetMsg(window->UserPort)** (−372). C'est une
scrutation : le jeu ne fait pas de WaitPort dans ce chemin. Puis ReplyMsg (−378).
- **im_Class = RAWKEY ($400)** :
  - code 50 (`$32`, avec qualificatifs $30) ⇒ code interne $12D ;
  - **codes $50–$59 (F1–F10)** ⇒ codes internes, en tenant compte de Shift ;
  - **bit 7 du code à 1 (touche relâchée) ⇒ ignoré** ;
  - sinon, construction d'un **InputEvent sur la pile** :
    - ie_Class = 1 (RAWKEY), ie_SubClass = 0 ;
    - ie_Code = im_Code, ie_Qualifier = im_Qualifier ;
    - **ie_EventAddress = *(im_IAddress)** : le long pointé par IAddress, c'est-à-dire les
      touches précédentes pour les touches mortes ;
    - puis **RawKeyConvert(ie, buf, 8, keymap NULL)** (console −48). **Seul un résultat de
      exactement 1** est pris : le caractère. ENTER/RETURN ⇒ $0D.
- **im_Class = MOUSEBUTTONS ($8)** : SELECTDOWN ($68) / MENUDOWN ($69) avec un test de double
  clic sur im_Seconds/im_Micros. Le bouton droit est piégé par RMBTRAP.
- Autres classes : ignorées.

**Exigences [D]** :
- l'IDCMP RAWKEY doit arriver à cette fenêtre BACKDROP ACTIVATE ;
- **im_IAddress doit être un pointeur valide** (déréférencé). Un NULL lit l'adresse 0, ce qui
  est sans danger mais donne une valeur arbitraire ;
- RawKeyConvert doit rendre **1** et `$0D` pour RETURN ($44) et ENTER du pavé ($43), avec la
  keymap par défaut.

## 7. Récapitulatif des points de blocage ou d'écran noir possibles [D]

| # | Condition | Effet chez nous |
|---|---|---|
| 1 | OpenScreen **CUSTOMBITMAP** non respecté (plans alloués par nous) | écran noir, aucun texte, jeu vivant |
| 2 | **vp_UCopIns** ignoré par MakeVPort/MrgCop/RethinkDisplay | écran intuition visible (barre, gadgets), pas d'affichage du jeu |
| 3 | gb_copinit (GfxBase+$26) faux, ou COP1LC non relancé par trame | affichage incohérent |
| 4 | **Vecteur $78 pris par la musique, et MICROHZ ou délais disque sur CIA-B/INT6** | chargement gelé sans message |
| 5 | Serveur VBlank (AddIntServer 5, pri −60) jamais appelé, ou compteur de trames figé | moteur figé (tout est chronométré par trames) |
| 6 | **Seek** qui rend la nouvelle position au lieu de l'ancienne | mauvaises lectures dans DISK01.LEC, salle introuvable |
| 7 | RawKeyConvert ≠ 1 caractère pour ENTER, ou RAWKEY non livré | ENTER sans effet (après l'affichage) |
| 8 | Zone $300–$35F écrasée (routine du crack) | plantage au passage de la protection |

Ordre conseillé :
1. sonder `Screen.BitMap.Planes[0]` contre les plans de bm1 (A4+$6FE6+8) ;
2. vérifier la présence de la liste UCopIns dans la copper list système (MOVE COP1LC puis COPJMP1
   vers une adresse du hunk 3) ;
3. vérifier que le vecteur $78 est modifié pendant le chargement, et l'état de nos requêtes
   MICROHZ.

---

## Relecture clean-room

- [x] Aucune suite d'instructions recopiée : appels publics avec LVO et arguments, NewScreen et
  NewWindow champ par champ, registres matériels et valeurs, conditions.
- [x] Aucune donnée du jeu (image, musique, texte) reproduite ; les copper lists sont décrites
  comme des tables registre → rôle.
- [x] **Correction du 2026-10-29** : retirées les 2 adresses ROM (chaîne dans timer.device,
  ouverture de ciab.resource par trackdisk) ; constat inchangé.
