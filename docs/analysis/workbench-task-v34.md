# workbench-task-v34.md — résident `workbench.task` (wb 34.1) : démarrage, init, boucle, fin

> Piste ANALYSE (« dirty »). Sources : la ROM `assets/kick34005.A500` (module `wb 34.1 (18 Aug
> 1987)`, ROMTag à $FEB47C, code jusqu'à $FF310C, stubs de librairies jusqu'à ~$FF3DD0) et, sur le
> disque `assets/wb133.adf`, `c:LoadWB` (extrait en scratch, pour recouper l'interface).
> Mêmes conventions que `handlers-v34.md` / `bcpl-runtime-v34.md` : **BPTR** = adresse/4,
> « R2 » = `pr_Result2`, champs Process : `pr_MsgPort` +$5C, `pr_SegList` +$80, `pr_ConsoleTask`
> +$A4, `pr_CLI` +$AC, `pr_WindowPtr` +$B8.
>
> **Légende** : **[O]** observé directement · **[D]** déduit d'observations convergentes ·
> **[S]** supposé. Les adresses ROM ne sont que des repères pour la piste analyse.
>
> Ce document décrit des comportements, des layouts d'ABI et des constantes. **Aucune suite
> d'instructions n'est reproduite ni paraphrasée.**

---

## 0. Résumé exécutable

1. ROMTag : `rt_Flags = 0`, version 34, `rt_Type = 1` (NT_TASK), pri 0, nom `"workbench.task"`,
   `rt_Init = ROMTag+26`. **Rien dans la ROM ne le démarre** (aucune référence à son tag ni à son
   nom hors du tag lui-même) : il doit seulement **figurer dans la liste ResModules** pour que
   `FindResident("workbench.task")` de LoadWB le trouve. [O]
2. ROMTag+26..+49 = **trois points d'entrée de 8 octets** (sélecteurs 0, 1, 2) qui convergent vers
   le même `main(sélecteur)`. Chaque entrée commence par un « bourrage » de 4 octets qui ne fait
   rien et peut tenir lieu de **lien de segment = faux BPTR** ; le sélecteur 2 est celui de LoadWB. [O]
3. Entrée via CreateProc : PC = `BADDR(seglist)+4`, **D0 = 0** (exec AddTask démarre une tâche avec
   tous les registres de données/adresses à 0). Le sélecteur effectif vaut 2 **uniquement si D0 = 0
   à l'entrée** (voir §1.3). [O]
4. Au tout début, **avant toute ouverture de librairie** : allocation d'un bloc global de **$4F2
   octets MEMF_CHIP|MEMF_CLEAR**, `pr_CLI := BPTR(bloc)` (faux CLI), **`ln_Name := "Workbench"`**,
   `SetTaskPri(soi, 1)`, puis (sélecteur 2) `WaitPort/GetMsg` du message de LoadWB, lecture de 2
   champs, **`ReplyMsg` immédiat**. [O]
5. Ensuite seulement : OpenLibrary (version **0**) de dos, graphics, layers, intuition, mathffp,
   icon. Un échec = Alert de récupération `$3103800x` puis **Alert dead-end `$80008031`** (reboot) ;
   LoadWB a déjà eu sa réponse. [O]
6. Le Workbench **n'appelle ni OpenWorkBench ni OpenScreen** : il ouvre une **fenêtre backdrop de
   type WBENCHSCREEN** (après GetScreenData), s'enregistre par **AlohaWorkbench(port)**, scanne la
   DosList (devices puis volumes → icônes disque), arme un **timer.device UNIT_VBLANK de 5 s**
   (titre « free memory » + rescan disques) puis entre dans une **boucle infinie**. [O]
7. Il **ne se termine jamais** : pas de sortie de boucle ; un retour de `main` tomberait sur l'Alert
   dead-end. CloseWorkBench → message WBENCHMESSAGE/WBENCHCLOSE : il ferme ses fenêtres et reste
   vivant ; WBENCHOPEN les rouvre. [O]
8. `pr_ConsoleTask` (+$A4) : **jamais lu** par le code ROM du Workbench [D] ; la remise à 0 par LoadWB
   sert aux **process fils** (CreateProc hérite ConsoleTask du parent) [D].

---

## 1. Q1 — ROMTag et zone d'entrée

### 1.1 ROMTag ($FEB47C) [O]

| Off. | Champ | Valeur |
|---|---|---|
| +0 | rt_MatchWord | $4AFC |
| +2 | rt_MatchTag | $00FEB47C (lui-même) |
| +6 | rt_EndSkip | $00FF310C |
| +10 | rt_Flags | **$00** (ni COLDSTART ni AUTOINIT) |
| +11 | rt_Version | 34 |
| +12 | rt_Type | **1** (NT_TASK) |
| +13 | rt_Pri | 0 |
| +14 | rt_Name | $FEB4CA → `"workbench.task"` |
| +18 | rt_IdString | $FEB464 → `"wb 34.1 (18 Aug 1987)\r\n"` |
| +22 | rt_Init | **$FEB496 = ROMTag+26** |

- Aucun autre endroit de la ROM ne contient l'adresse du tag, de son nom ou de `rt_Init`, ni la
  chaîne `"workbench.task"` : ni strap ni dos ne le lancent. **Correction** de l'hypothèse
  « *(inféré)* » de `boot-sequence.md` (« strap amène explicitement workbench.task ») : c'est faux,
  seul `c:LoadWB` le démarre. [O]
- Conséquence ABI : exec doit mettre **tous** les ROMTags dans ResModules (y compris ceux à
  `rt_Flags = 0`), sans les initialiser. [O pour la ROM ; contrat de FindResident]

### 1.2 Zone ROMTag+26 .. ROMTag+49 [O]

Trois blocs consécutifs de **8 octets**, à ROMTag+26, +34, +42 (soit $FEB496, $FEB49E, $FEB4A6).
Chaque bloc = **4 octets de bourrage** (une opération neutre sur D0 dont les 2 derniers octets
valent $0000) suivis de **4 octets** qui chargent le sélecteur (0, 1 ou 2) dans D0. Les deux
premiers blocs rejoignent ensuite le troisième ; le code commun empile D0 comme **unique argument
(long) de `main` ($FEE398)** et l'appelle. Le code qui suit l'appel (si `main` rendait la main)
est la routine d'Alert dead-end du §2.6.

| Entrée | Adresse | Sélecteur | Qui |
|---|---|---|---|
| ROMTag+26 = rt_Init | $FEB496 | 0 | InitResident (non utilisé en pratique) |
| ROMTag+34 | $FEB49E | 1 | personne d'observé |
| ROMTag+42 | $FEB4A6 | **2** | **LoadWB (CreateProc)** |

« Faux segment » : à ROMTag+42 le long de **lien vaut 0** (fin de chaîne de segments) et le point
d'entrée est à **ROMTag+46** (charge 2 dans D0). Mais ROMTag+42 = $FEB4A6 n'est **pas aligné sur 4**
(≡ 2 mod 4) ; voir §1.3.

### 1.3 Ce que LoadWB passe réellement à CreateProc [O WB + O ROM]

- LoadWB calcule `seglist = (adresse_ROMTag + 26 + 16) >> 2` par **décalage arithmétique** (bits
  bas tronqués) → BPTR $003FAD29 → `BADDR = $FEB4A4` (= ROMTag+40), **pas** $FEB4A6.
- dos CreateProc (forme C, globale −18) lance la tâche par AddTask avec **PC initial =
  BADDR(seglist)+4 = $FEB4A8** (= ROMTag+44) et **PC final** = sa routine de fin de process. Le
  « lien » lu à BADDR(seglist) n'est pas suivi au démarrage. [O dos $FF43DA..$FF43E6]
- À $FEB4A8 se trouvent les 2 derniers octets du bourrage du bloc 3 suivis du chargement du
  sélecteur : les 4 octets vus depuis cette adresse forment **une opération qui fait `D0 := D0 OU 2`**
  (et non « D0 := 2 »). Le sélecteur vaut donc 2 **si et seulement si les bits utiles de D0 sont 0
  à l'entrée** ; même mécanisme pour les blocs 1 et 2 (OU 1, OU 0). [O]
- exec AddTask (ROM, $FC1CCA..) construit la frame initiale avec **15 longs à 0 (D0–D7/A0–A6)**,
  un SR à 0 et le PC initial, sous le PC final empilé. ⇒ D0 = 0, **A6 = 0** à l'entrée. [O]
- **Exigence pour une réimplémentation** : un process C démarré par CreateProc doit entrer avec
  **D0 = 0** (et ne rien supposer d'autre des registres) ; à défaut, sélecteur 3 ⇒ le Workbench ne
  lit pas le message de LoadWB et **LoadWB reste bloqué** dans WaitPort. [D]

### 1.4 InitCode ou LoadWB ? [O]

`rt_Flags = 0` ⇒ non initialisé par InitCode(RTF_COLDSTART) ni par une autre passe. Il n'est
démarré que par LoadWB (FindResident + CreateProc). Le sélecteur 0 (rt_Init, appel par
InitResident) ferait tourner le Workbench dans le contexte de l'appelant : aucun appelant n'existe.

---

## 2. Q2 — Démarrage du process

### 2.1 Convention d'entrée [O]

Rien de particulier hors D0 (§1.3) : pas d'argument registre utilisé, pas de packet de démarrage
dos (ce n'est pas un process BCPL : segarray `[2, noyau, dos, seglist]` de la forme C, entrée
directe au code). Le code du Workbench est compilé (C, modèle « petites données ») avec **A6 =
pointeur sur ses globales** (= bloc+$40) ; tous ses stubs de librairie lisent les bases dans ces
globales. [O]

### 2.2 Séquence d'initialisation de `main` ($FEE398), dans l'ordre [O]

1. **AllocMem($4F2, MEMF_CHIP|MEMF_CLEAR)** (bloc global ; via SysBase lu en $4) ; échec ⇒
   Alert `$31010000` (AN_Workbench|AG_NoMemory) puis dead-end (§2.6).
2. Globales = bloc+$40 ; mémorisation de SysBase dans les globales.
3. **FindTask(NULL)** → soi ; **`pr_CLI := BPTR(bloc)`** : les $40 premiers octets du bloc (zéro)
   servent de **faux CommandLineInterface**.
4. **SetTaskPri(soi, 1)**.
5. **`soi->tc_Node.ln_Name := "Workbench"`** (chaîne ROM $FECD72). ⇒ le renommage a lieu **avant**
   l'attente du message, donc avant la réponse à LoadWB ; `FindTask("Workbench")` de LoadWB réussit
   toujours. [O]
6. **Si sélecteur = 2** : `WaitPort(&pr_MsgPort)`, `GetMsg(&pr_MsgPort)`, lecture de
   `msg+$18` (→ « drapeau debug ») et `msg+$14` (→ copié dans **`cli_CommandDir`** du faux CLI,
   bloc+8), puis **`ReplyMsg(msg)` immédiatement**.
7. Le « drapeau » (msg+$18 si sélecteur 2, sinon le sélecteur lui-même) est rangé dans les globales
   (+$47A) ; s'il vaut 1, un bit de mode est positionné (globales octet +$23, bit 7). Aucun lecteur
   de ces deux valeurs n'a été trouvé [D] → effet de `-debug` inconnu/inactif [S].
8. **OpenLibrary(nom, 0)** dans cet ordre, base rangée dans les globales :

   | Ordre | Librairie | Globale | Alert si échec (récupérable) |
   |---|---|---|---|
   | 1 | `dos.library` | +$2B6 | `$31038002` (sic : code « graphics ») |
   | 2 | `graphics.library` | +$2AA | `$31038002` |
   | 3 | `layers.library` | +$2BE | `$31038003` |
   | 4 | `intuition.library` | +$2AE | `$31038004` |
   | 5 | `mathffp.library` | +$2BA | `$31038005` |
   | 6 | `icon.library` | +$2B2 | `$31038009` |

   Chaque échec : Alert du code ci-dessus (bit dead-end **non** positionné) puis Alert dead-end
   `$80008031` (§2.6). icon.library n'est pas en ROM : elle vient de `LIBS:` via ramlib (LoadWB l'a
   déjà ouverte de son côté, cf. §2.4).
9. Puis les initialisations du §3.

### 2.3 Message de LoadWB (layout) [O WB + O ROM]

| Off. | Taille | Contenu | Lu par le Workbench |
|---|---|---|---|
| +$00 | 20 | `struct Message` (mn_ReplyPort +$0E = `pr_MsgPort` de LoadWB) | non (seul ReplyMsg l'utilise) |
| +$14 | 4 | **BPTR d'une copie du chemin de commandes** de LoadWB (liste de paires `{BPTR suivant, lock}` dupliquée par DupLock, nœuds de 8 octets) | **oui** → `cli_CommandDir` du faux CLI |
| +$18 | 4 | drapeau `-debug` (1 si `LoadWB -debug`, sinon 0) | **oui** (§2.2 point 7) |

- Taille totale **28 octets** (sur la pile de LoadWB). `mn_Length` n'est pas initialisé par
  LoadWB et n'est pas lu par le Workbench. [O]
- Le message est posté par PutMsg sur le **MsgPort renvoyé par CreateProc** (= `pr_MsgPort` du
  nouveau process). [O WB]

### 2.4 Quand LoadWB est-il libéré ? [O]

**Immédiatement après la lecture du message**, avant l'ouverture de toute librairie, de la fenêtre
ou de l'écran. LoadWB fait ensuite `FindTask("Workbench")`, met à 0 son `pr_ConsoleTask`, et sort
(option `delay` : Delay(150)). Pour mémoire, côté disque, LoadWB 1.3.3 ouvre aussi icon.library
(sortie code 20 si absente) et intuition.library, et installe par **SetFunction** un remplaçant du
vecteur intuition **−276 (SetWindowTitles)** (texte de version « 1.3.3 » ; chaînes stockées
obfusquées) avant de refermer intuition. [O WB]

### 2.5 Et si une init échoue ? [O]

LoadWB a **déjà** reçu sa réponse (point 6 avant point 8). Tout échec ultérieur (librairie, mémoire,
police, écran, timer) n'entraîne aucune réponse supplémentaire : c'est une **Alert dead-end ⇒
reboot**. Il n'existe pas de chemin « échec propre » qui rendrait la main au CLI.

### 2.6 Routines d'abandon [O]

- « Fatal » générique ($FEB4B4) : **Alert(`$80008031`)** (bit 31 = AT_DeadEnd) appelée avec la
  SysBase lue en $4 ; elle ne revient pas. Appelée après chaque Alert récupérable ci-dessous et si
  `main` rendait la main.
- Manque de mémoire : Alert `$31010000` puis fatal.
- Police : Alert **`$B1000001`** (dead-end) si OpenFont échoue.
- timer.device : Alert **`$B1048015`** (dead-end, AG_OpenDev, AO_TimerDev) si OpenDevice échoue
  ou rend io_Error ≠ 0.

---

## 3. Q3 — Ce que fait le Workbench une fois lancé (ordre des appels principaux)

### 3.1 Initialisation (suite de `main`) [O sauf mention]

| # | Repère | Effet observable (appels de librairie) |
|---|---|---|
| 1 | $FEE130 | **AllocSignal(−1)** (un seul signal) ; deux MsgPorts **publics** de 34 octets dans les globales, **A** (+$38E) et **B** (+$3B0) : ln_Type 4, ln_Name `"Workbench"`, mp_Flags 0 (PA_SIGNAL), mp_SigBit = ce signal (**partagé**), mp_SigTask = soi ; **AddPort(A)**, **AddPort(B)**. A = port de réponse (WBStartup des outils, timer) ; B = port IDCMP/Workbench. |
| 2 | $FEC4F2 | **GetPrefs(buf, 1)** (lit seulement l'octet `FontHeight`) ; TextAttr `{"topaz.font", FontHeight, 0, 0}` ; **InitRastPort** (rastport privé) ; **CloseFont** de l'ancienne police éventuelle ; **OpenFont** (échec ⇒ $B1000001) ; **SetFont**. Ré-exécuté sur NEWPREFS. |
| 3 | $FEF1A8, $FECD18, $FF2632 | allocations internes (AllocMem MEMF_CHIP\|CLEAR ; échec ⇒ $31010000), construction des menus (mesures **TextLength**). [D pour le rôle] |
| 4 | $FEDFE0 | 3 listes vides (NewList) ; **AllocWBObject** (icon) = objet racine nommé `"Workbench"` ; puis ouverture de la **fenêtre backdrop** (§3.2) ; ajout de la racine en liste (AddTail) et rafraîchissement. Échec ⇒ $31010000 + fatal. |
| 5 | $FF2C20 | AllocMem + **InitGels** (GelsInfo pour le glisser d'icônes), attaché au RastPort de l'écran (Screen+$68 = `RastPort.GelsInfo`). |
| 6 | $FEFF3A | parcours des listes d'objets (préparation) [D] |
| 7 | $FF1436 | `DosInfo := BADDR(DOSBase->dl_Root->rn_Info)` (DOSBase+$22 → RootNode+$18) ; **scan de la DosList** (§3.3) |
| 8 | $FEFF6C | traitement de la file interne (Disable/AddHead/RemTail/Enable, GetMsg) [D] |
| 9 | $FF3CD0 | **AlohaWorkbench(port B)** (intuition −402) |
| 10 | $FF2398 | **OpenDevice("timer.device", unité 1 = UNIT_VBLANK, req, 0)** sur une timerequest de 40 octets (allouée avec un en-tête de 2 octets marqué 4), `mn_ReplyPort = port A`, `io_Command = 9` (TR_ADDREQUEST) ; puis **premier tic** (§3.4) |
| 11 | $FEE18E | **boucle principale** (§3.5), sans retour |

Ordre des modules ouverts implicitement : l'**écran Workbench** n'est ouvert qu'au #4, au moment
de GetScreenData/OpenWindow de type WBENCHSCREEN. Le Workbench n'appelle **ni OpenWorkBench, ni
OpenScreen, ni CloseWorkBench** (aucun stub vers −210/−198/−78 dans le module). [O]

### 3.2 Fenêtre backdrop [O]

- **GetScreenData(buf, 346 = $15A, WBENCHSCREEN (1), NULL)** (intuition −426) ; résultat 0 ⇒ la
  racine n'a pas de fenêtre ⇒ $31010000 + fatal. Que GetScreenData ouvre l'écran WB s'il est fermé
  est un comportement intuition à vérifier dans les AutoDocs [S] ; l'OpenWindow qui suit, de type
  WBENCHSCREEN, l'ouvre en tout cas si nécessaire [D, contrat intuition public].
- NewWindow (layout public) : LeftEdge 0, **TopEdge = sc_BarHeight+1**, **Width = sc_Width**,
  **Height = sc_Height − (BarHeight+1)** (valeurs lues dans la copie de Screen : BarHeight octet
  +$1E, Width +$0C, Height +$0E), DetailPen/BlockPen 0, **IDCMPFlags 0** à l'ouverture,
  **Flags $02000B40** (WBENCHWINDOW \| BORDERLESS \| BACKDROP \| REPORTMOUSE \| SIMPLE_REFRESH),
  FirstGadget 0, CheckMark 0, Title 0, Screen 0, BitMap 0, **MinWidth 90, MinHeight 40,
  MaxWidth/MaxHeight −1**, **Type 1 (WBENCHSCREEN)**.
- Après **OpenWindow** : `wd_UserPort := port B` (port **partagé** par toutes les fenêtres du
  Workbench) puis **ModifyIDCMP(win, $C076E \| extra)** — extra = **$1C000** (NEWPREFS \|
  DISKINSERTED \| DISKREMOVED) pour la backdrop ⇒ **$DC76E**. Puis **SetWindowTitles**(win, titre,
  tampon de titre d'écran), **SetPointer** (si un mode « occupé » est actif), **SetMenuStrip**, et
  enfin **SetWindowTitles(win, "Workbench", −1)**. La fenêtre et son écran sont mémorisés
  (globales +$4A8 / +$4A4).
- Les fenêtres de tiroir/disque utilisent la même routine avec **Flags $0200027F**
  (WBENCHWINDOW \| REPORTMOUSE \| SIMPLE_REFRESH \| SIZING \| DRAG \| DEPTH \| CLOSE \| SIZEBRIGHT
  \| SIZEBBOTTOM) et le nom de l'objet comme titre. Aucune n'est ouverte au démarrage hors
  réouverture (§4.2).

### 3.3 Scan des disques (DosList → icônes) [O]

Parcours de `DosInfo->di_DevInfo` (chaîne dn_Next) **sous Forbid** (incrément direct de
`TDNestCnt` de ExecBase, puis Permit). Deux temps :

1. **Devices** (dn_Type 0) ayant `dn_Task ≠ 0` : le Workbench envoie lui-même un packet
   **ACTION_INHIBIT (31), Arg1 = 0** ; si Res1 ≠ 0, et si `dn_Startup ≠ 0` et
   `fssm_Device ≠ 0` et que **FindName(SysBase->DeviceList, nom du device exec)** réussit, le
   device est retenu (état « device », 4).
2. **Rescan complet** (aussi rappelé à chaque tic de 5 s, sur DISKINSERTED/DISKREMOVED et à
   WBENCHOPEN) :
   - pour chaque **volume** (dn_Type 2) : entrée inconnue ⇒ nouvelle (état 2 « nouveau ») ;
     connue avec `dl_Task ≠ 0` ⇒ état 3 (« actif », dl_Task mémorisé) ; sinon état 1 (« retiré ») ;
   - entrées non revues ⇒ supprimées ;
   - pour les devices retenus : packet **ACTION_DISK_INFO (25)**, Arg1 = BPTR d'un InfoData ; si
     `id_DiskType` ∉ { `'DOS\0'` ($444F5300), −1 (pas de disque) } ⇒ icône spéciale (type objet 7)
     nommée `"<device>:" + 4 caractères du DiskType` (disques non DOS / illisibles) ;
   - **nouveau volume** : recherche du device dont `dn_Task == dl_Task`, packet
     **ACTION_LOCATE_OBJECT (8)** (Arg1 = 0, Arg2 = BSTR du nom, Arg3 = **−2** = SHARED) au
     `dl_Task` → lock racine ; si `dl_Task = 0` ⇒ R2 := **218** et état 1 ; si échec ⇒ requester
     dos `errorreq` (§3.6) puis nouvel essai ou abandon. Puis **Info(lock, InfoData)**,
     **CurrentDir(lock)**, **GetWBObject("Disk")** (= `Disk.info` de la racine) ; absent ⇒
     **AllocWBObject** + image par défaut ; l'icône est ajoutée à la backdrop. Volume déjà ouvert ⇒
     **WindowToFront** de sa fenêtre.
- Les packets sont envoyés **par le Workbench lui-même** (pas via dos) : DosPacket dans ses
  globales, `dp_Port` = **son `pr_MsgPort`**, `mn_Node.ln_Name` = packet, PutMsg au port du
  handler, attente par **Wait(signal de pr_MsgPort)** jusqu'à GetMsg, résultat Res1, **R2 :=
  Res2**. [O]
- `pr_WindowPtr` est mis temporairement à **−1** pendant l'écriture d'un fichier `.info`
  (requesters dos supprimés) puis remis à 0. [O]

### 3.4 Tic de 5 secondes [O]

À chaque retour de la timerequest (et une fois au démarrage) : si le Workbench n'est pas « fermé » :
rescan disques (§3.3), puis **AvailMem(0)** ; si la valeur change, le titre d'écran est reformaté
par **RawDoFmt** avec `"Workbench release 1.2.  %ld free memory"` (tampon global +$3DA) et appliqué
aux fenêtres (SetWindowTitles, que LoadWB 1.3.3 a détourné). Puis renvoi de la requête :
`tv_secs = 5`, `tv_micro = 0`, **SendIO** (asynchrone, réponse sur le port A).

### 3.5 Boucle principale ($FEE18E) [O]

Boucle **infinie** : vider le **port B** (chaque IntuiMessage → dispatcher par numéro de bit de
`im_Class`, 23 entrées) ; sauf mode particulier, vider le **port A** : chaque message porte un **mot
de type juste avant lui** (en-tête de 2 octets de son allocation) : **2 = WBStartup** revenu d'un
outil (UnLoadSeg du segment, UnLock/libération des arguments, FreeMem 42 octets), **4 =
timerequest** (§3.4) ; si aucun message n'a été traité ⇒ **Wait(1 << signal partagé)**.

Classes IDCMP traitées : NEWSIZE/REFRESHWINDOW, MOUSEBUTTONS (SELECTDOWN $68 / SELECTUP $E8,
**DoubleClick**), MOUSEMOVE, GADGETDOWN/UP, INACTIVEWINDOW, MENUPICK, CLOSEWINDOW, MENUVERIFY,
NEWPREFS (police + rafraîchissement), DISKINSERTED/DISKREMOVED (rescan), **WBENCHMESSAGE** (§4.1),
INTUITICKS ; les autres sont simplement renvoyées par ReplyMsg.

### 3.6 Autres interfaces utilisées (pour dimensionner l'implémentation) [O]

- **dos** : Open, Close, Read, Write, DeleteFile, Lock, UnLock, DupLock, Examine, ExNext, Info,
  CreateDir, CurrentDir, IoErr, **CreateProc**, **LoadSeg**, **UnLoadSeg**, DateStamp, et l'entrée
  privée **DOSBase−28** (§3.7).
- **exec** : Alert, Disable/Enable, Forbid/Permit, AllocMem/FreeMem, AvailMem, Insert, AddHead,
  AddTail, Remove, RemHead, RemTail, FindName, FindTask, SetTaskPri, Wait, AllocSignal, AddPort,
  PutMsg, GetMsg, ReplyMsg, WaitPort, OpenLibrary, CloseLibrary, OpenDevice, SendIO, RawDoFmt ;
  accès direct à `TDNestCnt` (ExecBase+$127) et `DeviceList` (ExecBase+$15E).
- **graphics** : BltBitMap, TextLength, Text, SetFont, OpenFont, CloseFont, AddBob, DrawGList,
  InitGels, RemIBob, SortGList, InitRastPort, SetRast, Move, Draw, BltClear, RectFill, Flood,
  SetAPen, SetDrMd, LockLayerRom, UnlockLayerRom, InitTmpRas, et les vecteurs −504/−510/−516/−528/
  −534 (régions : AndRect/OrRect/NewRegion/ClearRegion/DisposeRegion d'après l'ordre `.fd`) [D].
- **intuition** : ClearMenuStrip, ClearPointer, CloseWindow, DisplayBeep, DoubleClick, GetPrefs,
  ModifyIDCMP, OffMenu, OnMenu, OpenWindow, SetMenuStrip, SetPointer, SetWindowTitles,
  WindowToFront, **AlohaWorkbench (−402)**, **GetScreenData (−426)**, −450 (ActivateWindow),
  −462 (ActivateGadget), −468 (NewModifyProp) [noms d'après l'ordre `.fd` V33/V34].
- **layers** : BeginUpdate, EndUpdate, LockLayers, UnlockLayers, WhichLayer.
- **icon** : GetWBObject, PutWBObject, FreeFreeList, FreeWBObject, AllocWBObject, AddFreeList,
  FindToolType, BumpRevision.
- **timer** (base = io_Device) : SubTime (−48).
- Lancement d'un outil : CurrentDir(répertoire), **LoadSeg(nom)**, pile = `do_StackSize` ou
  **4096** par défaut, pri = ToolType **`TOOLPRI`** ou **0** par défaut, **CreateProc(nom, pri,
  seglist, pile)**, puis message **WBStartup** de 40 octets (en-tête de type 2) : `mn_ReplyPort =
  port A`, `sm_Process` = port renvoyé par CreateProc, `sm_Segment`, `sm_NumArgs`, `sm_ArgList`
  (paires `{lock, nom}` de 8 octets) ; **PutMsg(sm_Process, msg)**.

### 3.7 Entrée privée DOSBase−28 [O]

Les vecteurs dos V34 sont des paires « charger le n° de globale dans D0 ; brancher au dispatcher
commun » (6 octets). **DOSBase−28** tombe sur le branchement du vecteur −30 : c'est un appel
**« globale BCPL n° D0 »** avec les arguments en D1..D4. Le Workbench s'en sert pour
**errorreq (globale 114)** : `D1 = 3, D2 = BPTR du volume` (« Please insert volume … ») et
`D1 = 2, D2 = BPTR d'un lock, D3 = son fl_Task` (erreurs sur objet). Retour 0 ⇒ réessayer ;
non nul ⇒ abandon (cohérent avec la correction « TRUE = abandon » de l'étape 3). [O]

---

## 4. Q4 — Fin du Workbench, CloseWorkBench, `pr_ConsoleTask`

### 4.1 Pas de terminaison [O]

- La boucle principale n'a **aucune condition de sortie** ; aucune libération globale, aucun
  CloseLibrary/RemPort de fin n'existe dans `main`. Un retour de `main` exécuterait l'Alert
  dead-end `$80008031`. ⇒ **le process Workbench vit jusqu'au reboot**.
- **WBENCHMESSAGE** (IDCMP $00020000, reçu sur le port B grâce à AlohaWorkbench) : le message est
  **renvoyé (ReplyMsg) d'abord**, puis selon `im_Code` :
  - **1 = WBENCHOPEN** : pour chaque objet marqué « fenêtre à rouvrir », réouverture (racine ⇒
    même chemin que §3.2 ; tiroir ⇒ OpenWindow Flags $0200027F) ; si la racine ne se rouvre pas,
    arrêt de l'opération. Puis état « fermé » effacé, rafraîchissements, **rescan disques**.
  - **autre (2 = WBENCHCLOSE)** : pour chaque objet ayant une fenêtre : sous Forbid, retrait des
    IntuiMessages en attente pour cette fenêtre sur le port partagé, **ModifyIDCMP(win, 0)**,
    Permit, **ClearMenuStrip**, **CloseWindow** ; l'objet est marqué « à rouvrir ». État « fermé »
    positionné (le tic de 5 s ne fait alors plus rien).
- C'est donc intuition (CloseWorkBench/OpenWorkBench, appelés par d'autres programmes) qui pilote ;
  le Workbench se contente de fermer/rouvrir ses fenêtres pour que l'écran puisse se fermer. [O pour
  le Workbench ; D pour l'enchaînement côté intuition]

### 4.2 `pr_ConsoleTask` (+$A4) mis à 0 par LoadWB [D]

- Le code ROM du Workbench **ne lit ni n'écrit** `pr_ConsoleTask` de son propre process (les accès
  à un déplacement $A4 trouvés concernent ses propres structures d'objet, pas un Process). [D, par
  recherche exhaustive des accès]
- CreateProc (dos) **copie ConsoleTask / FileSystemTask / WindowPtr du process parent** dans le
  fils (`bcpl-runtime-v34.md` globale 33). Le Workbench, créé par LoadWB, hérite donc de la console
  du CLI qui a lancé LoadWB ; en la remettant à 0, LoadWB garantit que **les outils lancés depuis
  le Workbench** (fils du process Workbench) n'héritent pas d'une console qui disparaîtra au
  `EndCLI` de la startup-sequence (`Open("*")` échoue proprement au lieu de viser un handler
  mort). [D]
- Ordre : la remise à 0 a lieu **après** la réponse du Workbench, donc pendant que le Workbench
  ouvre ses librairies ; aucun outil n'est lancé avant, la course est sans effet. [D]

---

## 5. Vecteurs de test (valeurs observables)

| Test | Attendu |
|---|---|
| FindResident("workbench.task") | tag $FEB47C (ROM d'origine) ; rt_Flags 0, rt_Type 1, rt_Pri 0, rt_Version 34 |
| LoadWB : seglist | `(tag+42) >> 2` ⇒ PC initial `tag+44`, D0 = 0 à l'entrée |
| Après la réponse à LoadWB | `FindTask("Workbench")` ≠ 0, pri 1, `pr_CLI` ≠ 0 |
| Ports publics | 2 ports nommés `"Workbench"`, même pri 0 ; avec un AddPort par Enqueue, FindPort rend le **premier ajouté = port A** [D] |
| Écran | écran Workbench ouvert, 1 fenêtre backdrop pleine largeur sous la barre de titre |
| Titre d'écran | `"Workbench release 1.2.  <n> free memory"` (sans le patch 1.3.3 de LoadWB) |
| Disque DOS inséré en DF0: | icône `Disk.info` du volume dans la backdrop (≤ 5 s ou sur DISKINSERTED) |
| librairie manquante (ex. icon) | Alert `$31038009` puis dead-end `$80008031`, LoadWB déjà terminé |

---

## Relecture clean-room

- [x] Aucun listing, aucune suite d'instructions transcrite ni paraphrasée ligne à ligne : seules des
  **adresses-repères**, des **layouts** (ROMTag, message LoadWB, MsgPort, NewWindow, WBStartup,
  DosPacket), des **constantes** (codes d'Alert, flags de fenêtre, IDCMP, n° d'action dos, tailles)
  et des **séquences d'appels de librairie** (contrat d'API public) sont donnés.
- [x] §1.2/§1.3 décrivent l'**effet** des 8 octets d'entrée (sélecteur, OU sur D0) et la contrainte
  d'ABI qui en découle (D0 = 0 à l'entrée d'un process C), pas leur encodage : la piste
  implémentation n'a pas à les reproduire (son propre module workbench.task peut avoir n'importe
  quelle forme, tant que `(tag+42)>>2` donne un segment exécutable correct — par exemple placer son
  ROMTag à une adresse ≡ 2 mod 4 n'est **pas** requis ; il suffit que `BADDR((tag+42)>>2)+4` soit un
  point d'entrée valide).
- [x] Les noms de LVO au-delà des AutoDocs 1.3 (−426…−468 intuition, −504…−534 graphics) sont
  déduits de l'ordre des fichiers `.fd` publics et marqués [D].
- [x] Les éléments disque (LoadWB) sont limités à l'interface (message, seglist, SetFunction) déjà
  connue de la piste implémentation.
- [x] Correction signalée de `boot-sequence.md` (strap ne lance pas workbench.task).
