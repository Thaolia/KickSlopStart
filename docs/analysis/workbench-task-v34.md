# workbench-task-v34.md — résident `workbench.task` (wb 34.1) : démarrage, init, boucle, fin

> Piste ANALYSE (« dirty »). Sources : la ROM `assets/kick34005.A500` (module `wb 34.1 (18 Aug
> 1987)`, ROMTag, code du module et stubs de librairies) et, sur le
> disque `assets/wb133.adf`, `c:LoadWB` (extrait en scratch, pour recouper l'interface).
> Mêmes conventions que `handlers-v34.md` / `bcpl-runtime-v34.md` : **BPTR** = adresse/4,
> « R2 » = `pr_Result2`, champs Process : `pr_MsgPort` +$5C, `pr_SegList` +$80, `pr_ConsoleTask`
> +$A4, `pr_CLI` +$AC, `pr_WindowPtr` +$B8.
>
> **Légende** : **[O]** observé directement · **[D]** déduit d'observations convergentes ·
> **[S]** supposé. Aucune adresse de routine ROM n'est citée (retirées le 2026-10-29) ; les
> positions relatives au ROMTag qui restent sont celles qu'impose `c:LoadWB` (programme du disque).
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

### 1.1 ROMTag [O]

| Off. | Champ | Valeur |
|---|---|---|
| +0 | rt_MatchWord | $4AFC |
| +2 | rt_MatchTag | adresse du tag (lui-même) |
| +6 | rt_EndSkip | fin du module |
| +10 | rt_Flags | **$00** (ni COLDSTART ni AUTOINIT) |
| +11 | rt_Version | 34 |
| +12 | rt_Type | **1** (NT_TASK) |
| +13 | rt_Pri | 0 |
| +14 | rt_Name | → `"workbench.task"` |
| +18 | rt_IdString | → `"wb 34.1 (18 Aug 1987)\r\n"` |
| +22 | rt_Init | **ROMTag+26** (juste après la structure) |

- Aucun autre endroit de la ROM ne contient l'adresse du tag, de son nom ou de `rt_Init`, ni la
  chaîne `"workbench.task"` : ni strap ni dos ne le lancent. **Correction** de l'hypothèse
  « *(inféré)* » de `boot-sequence.md` (« strap amène explicitement workbench.task ») : c'est faux,
  seul `c:LoadWB` le démarre. [O]
- Conséquence ABI : exec doit mettre **tous** les ROMTags dans ResModules (y compris ceux à
  `rt_Flags = 0`), sans les initialiser. [O pour la ROM ; contrat de FindResident]

### 1.2 Zone ROMTag+26 .. ROMTag+49 [O]

Trois points d'entrée de **8 octets** chacun, à ROMTag+26, +34, +42. Chacun a pour effet de
fixer un **sélecteur** (0, 1 ou 2) puis d'appeler la fonction principale du Workbench (`main`) avec
ce sélecteur pour **unique argument** (long). Si `main` rendait la main, l'Alert dead-end du §2.6
suivrait.

| Entrée | Sélecteur | Qui |
|---|---|---|
| ROMTag+26 = rt_Init | 0 | InitResident (non utilisé en pratique) |
| ROMTag+34 | 1 | personne d'observé |
| ROMTag+42 | **2** | **LoadWB (CreateProc)** |

« Faux segment » : à ROMTag+42 le long de **lien vaut 0** (fin de chaîne de segments) et le point
d'entrée est à **ROMTag+46**. Mais, le tag d'origine étant aligné sur 4, ROMTag+42 n'est **pas
aligné sur 4** (≡ 2 mod 4) ; voir §1.3.

### 1.3 Ce que LoadWB passe réellement à CreateProc [O WB + O ROM]

- LoadWB calcule `seglist = (adresse_ROMTag + 26 + 16) >> 2` par **décalage arithmétique** (bits
  bas tronqués) → `BADDR(seglist)` = **ROMTag+40**, **pas** ROMTag+42.
- dos CreateProc (forme C, globale −18) lance la tâche par AddTask avec **PC initial =
  BADDR(seglist)+4** (= ROMTag+44) et **PC final** = sa routine de fin de process. Le
  « lien » lu à BADDR(seglist) n'est pas suivi au démarrage. [O dos]
- Entré à ROMTag+44 (au milieu du troisième point d'entrée), le code ROM a pour **effet
  `D0 := D0 OU 2`** (et non « D0 := 2 »). Le sélecteur vaut donc 2 **si et seulement si les bits utiles de D0 sont 0
  à l'entrée** ; même mécanisme pour les blocs 1 et 2 (OU 1, OU 0). [O]
- exec AddTask construit la frame initiale avec **15 longs à 0 (D0–D7/A0–A6)**,
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

### 2.2 Séquence d'initialisation de `main`, dans l'ordre [O]

1. **AllocMem($4F2, MEMF_CHIP|MEMF_CLEAR)** (bloc global ; via SysBase lu en $4) ; échec ⇒
   Alert `$31010000` (AN_Workbench|AG_NoMemory) puis dead-end (§2.6).
2. Globales = bloc+$40 ; mémorisation de SysBase dans les globales.
3. **FindTask(NULL)** → soi ; **`pr_CLI := BPTR(bloc)`** : les $40 premiers octets du bloc (zéro)
   servent de **faux CommandLineInterface**.
4. **SetTaskPri(soi, 1)**.
5. **`soi->tc_Node.ln_Name := "Workbench"`** (chaîne de la ROM). ⇒ le renommage a lieu **avant**
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

- « Fatal » générique : **Alert(`$80008031`)** (bit 31 = AT_DeadEnd) appelée avec la
  SysBase lue en $4 ; elle ne revient pas. Appelée après chaque Alert récupérable ci-dessous et si
  `main` rendait la main.
- Manque de mémoire : Alert `$31010000` puis fatal.
- Police : Alert **`$B1000001`** (dead-end) si OpenFont échoue.
- timer.device : Alert **`$B1048015`** (dead-end, AG_OpenDev, AO_TimerDev) si OpenDevice échoue
  ou rend io_Error ≠ 0.

---

## 3. Q3 — Ce que fait le Workbench une fois lancé (ordre des appels principaux)

### 3.1 Initialisation (suite de `main`) [O sauf mention]

| # | Effet observable (appels de librairie) |
|---|---|
| 1 | **AllocSignal(−1)** (un seul signal) ; deux MsgPorts **publics** de 34 octets dans les globales, **A** (+$38E) et **B** (+$3B0) : ln_Type 4, ln_Name `"Workbench"`, mp_Flags 0 (PA_SIGNAL), mp_SigBit = ce signal (**partagé**), mp_SigTask = soi ; **AddPort(A)**, **AddPort(B)**. A = port de réponse (WBStartup des outils, timer) ; B = port IDCMP/Workbench. |
| 2 | **GetPrefs(buf, 1)** (lit seulement l'octet `FontHeight`) ; TextAttr `{"topaz.font", FontHeight, 0, 0}` ; **InitRastPort** (rastport privé) ; **CloseFont** de l'ancienne police éventuelle ; **OpenFont** (échec ⇒ $B1000001) ; **SetFont**. Ré-exécuté sur NEWPREFS. |
| 3 | allocations internes (AllocMem MEMF_CHIP\|CLEAR ; échec ⇒ $31010000), construction des menus (mesures **TextLength**). [D pour le rôle] |
| 4 | 3 listes vides (NewList) ; **AllocWBObject** (icon) = objet racine nommé `"Workbench"` ; puis ouverture de la **fenêtre backdrop** (§3.2) ; ajout de la racine en liste (AddTail) et rafraîchissement. Échec ⇒ $31010000 + fatal. |
| 5 | AllocMem + **InitGels** (GelsInfo pour le glisser d'icônes), attaché au RastPort de l'écran (Screen+$68 = `RastPort.GelsInfo`). |
| 6 | parcours des listes d'objets (préparation) [D] |
| 7 | `DosInfo := BADDR(DOSBase->dl_Root->rn_Info)` (DOSBase+$22 → RootNode+$18) ; **scan de la DosList** (§3.3) |
| 8 | traitement de la file interne (Disable/AddHead/RemTail/Enable, GetMsg) [D] |
| 9 | **AlohaWorkbench(port B)** (intuition −402) |
| 10 | **OpenDevice("timer.device", unité 1 = UNIT_VBLANK, req, 0)** sur une timerequest de 40 octets (allouée avec un en-tête de 2 octets marqué 4), `mn_ReplyPort = port A`, `io_Command = 9` (TR_ADDREQUEST) ; puis **premier tic** (§3.4) |
| 11 | **boucle principale** (§3.5), sans retour |

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
Détail (drapeau « message affiché », valeur initiale −1, fenêtres concernées) : voir §6.4.

### 3.5 Boucle principale [O]

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
| FindResident("workbench.task") | le tag du module ; rt_Flags 0, rt_Type 1, rt_Pri 0, rt_Version 34 |
| LoadWB : seglist | `(tag+42) >> 2` ⇒ PC initial `tag+44`, D0 = 0 à l'entrée |
| Après la réponse à LoadWB | `FindTask("Workbench")` ≠ 0, pri 1, `pr_CLI` ≠ 0 |
| Ports publics | 2 ports nommés `"Workbench"`, même pri 0 ; avec un AddPort par Enqueue, FindPort rend le **premier ajouté = port A** [D] |
| Écran | écran Workbench ouvert, 1 fenêtre backdrop pleine largeur sous la barre de titre |
| Titre d'écran | `"Workbench release 1.2.  <n> free memory"` (sans le patch 1.3.3 de LoadWB) |
| Disque DOS inséré en DF0: | icône `Disk.info` du volume dans la backdrop (≤ 5 s ou sur DISKINSERTED) |
| librairie manquante (ex. icon) | Alert `$31038009` puis dead-end `$80008031`, LoadWB déjà terminé |

---

## 6. Menus Version / Last Error et titre d'écran

Sources : ROM (module wb, repères ci-dessous) et `c:LoadWB` de `wb133.adf` (hunk de code n° 4,
164 octets = le remplaçant de SetWindowTitles) ; `libs:version.library` du même disque (en-tête
`versionlib 34.34 (05 OCT 1990)`). Globales = bloc de $4F2 octets (§2.2), adressé ci-dessous
« G+off ».

### 6.1 État partagé : deux tampons de titre et un octet de drapeaux [O]

| Globale | Rôle |
|---|---|
| **G+$3DA** | tampon du **titre « mémoire »** (texte produit par RawDoFmt au tic, §6.4). Nul au départ (bloc MEMF_CLEAR). C'est aussi le titre d'écran passé à l'ouverture de **chaque** fenêtre du Workbench (`SetWindowTitles(win, nom, G+$3DA)`, §3.2). |
| **G+$2EE** | pointeur du tampon du **dernier message** (erreurs, Version…). 0 au départ ; alloué paresseusement au premier message : **AllocMem(80, 0)** (MEMF_ANY, non effacé), et s'il échoue, repli sur un tampon interne G+$160. Jamais libéré. Pas de borne de longueur au formatage (80 octets). |
| **G+$2F2** | dernière valeur AvailMem affichée (comparaison du tic). |
| **G+$22** (octet de drapeaux) | bit 0 = Workbench « fermé » (CloseWorkBench, §4.1) ; **bit 1 = titre verrouillé** (pendant la saisie du Rename) ; **bit 2 = « un message est affiché »**. |

### 6.2 Routine commune « afficher un titre » [O]

Signature (convention C, pile) : `ShowTitle(fmt, arg1, arg2, arg3, arg4, arg5)`. Comportement :

1. **`fmt == G+$3DA` (restauration du titre mémoire)** : si bit 1 (verrou) ⇒ rien. Sinon, si bit 2
   est **clair** ⇒ rien. Sinon bit 2 := 0 et le titre mémoire est appliqué (étape 4 avec G+$3DA).
2. **Autre `fmt` (message)** : si bit 2 est **déjà mis** ⇒ **rien** (le premier message affiché
   gagne jusqu'à la prochaine restauration). Sinon bit 2 := 1 ; obtenir le tampon G+$2EE (allocation
   au besoin, §6.1).
3. Si `fmt` **diffère** du tampon de message : **DisplayBeep(écran WB)** (écran mémorisé en G+$4A4),
   puis **RawDoFmt(fmt, &arg1, putchar « stocker l'octet », tampon)** (arguments = mots longs
   consécutifs sur la pile). Si `fmt` **est** le tampon lui-même : ni bip ni reformatage.
4. Application : pour **chaque objet de la liste maîtresse G+$24** (liste où la racine `"Workbench"`
   est ajoutée par AddTail, §3.1 #4) dont le pointeur de données de tiroir (objet+$4C) est non nul
   **et** dont la fenêtre (données+$1A4) est non nulle :
   **`SetWindowTitles(fenêtre, (char *)−1, tampon)`** — titre de fenêtre **inchangé**, titre
   d'**écran** = tampon. Donc **backdrop + toutes les fenêtres de tiroir/disque ouvertes**.

Restauration du titre mémoire (`ShowTitle(G+$3DA)`) appelée : **au début de tout MENUPICK** (avant
le dispatch de l'élément), sur **SELECTDOWN** (clic gauche), par le tic (§6.4),
et à l'entrée du Rename (sans effet, verrou mis).

### 6.3 Special/Version (code menu $F882 = menu 2, élément 4, pas de sous-élément) [O]

1. (Restauration du titre mémoire, §6.2, commune à tout MENUPICK : efface le bit 2.)
2. **Version Kickstart** : lue dans l'**en-tête de la ROM**, pas dans une base de librairie :
   base ROM = `$1000000 − taille ROM` (taille = champ du pied de ROM, situé 20 octets avant la fin
   de l'espace 24 bits ; `$00040000` ici) = $FC0000 ; mots non
   signés en **base+$0C** (= 34) et **base+$0E** (= 5), étendus en longs. (exec.library, elle,
   est en 34.2 : ce n'est **pas** `SysBase->lib_Version/lib_Revision`.)
3. **Version Workbench** : **OpenLibrary("version.library", 0)** ; si succès, mots non signés
   **lib_Version (+$14)** et **lib_Revision (+$16)** de **cette base**, puis **CloseLibrary**. Si
   l'ouverture échoue : **−1 et −1** (affichés « -1.-1 »). Pas de constante interne : avec le
   `libs:version.library` de WB 1.3.3 (34.34) on obtient « 34.34 » ; avec un autre disque, autre
   valeur. OpenLibrary peut charger la librairie depuis LIBS: (ramlib) [D, contrat exec].
4. **`ShowTitle("Kickstart version %ld.%ld. Workbench version %ld.%ld", 34, 5, wbVer, wbRev)`**
   ⇒ bip d'écran, formatage dans le tampon G+$2EE, `SetWindowTitles(w, −1, tampon)` sur toutes
   les fenêtres WB ouvertes (§6.2 étape 4). Le titre de fenêtre n'est pas touché.
5. **Persistance** : le bit 2 reste mis ⇒ le **tic de 5 s ne met plus à jour le titre mémoire**
   (§6.4) ⇒ le texte Version reste affiché **indéfiniment**, quelle que soit l'évolution de la
   mémoire, **jusqu'au prochain clic gauche (SELECTDOWN) ou au prochain MENUPICK** dans une fenêtre
   du Workbench. Ces événements ré-appliquent le contenu **courant** de G+$3DA (la valeur mémoire
   formatée au dernier tic qui a écrit, donc potentiellement périmée jusqu'au tic suivant). [O]
   Le « drapeau qui bloque la mise à jour » est donc le **bit 2 de G+$22** (et le bit 1 pendant un
   Rename).

### 6.4 Tic de 5 s : détail du titre mémoire (complète §3.4) [O]

- À l'ouverture du timer (§3.1 #10) : **G+$2F2 := −1**, puis premier tic immédiat. Avant ce
  premier tic, le titre d'écran passé aux fenêtres est **G+$3DA vide** (chaîne nulle).
- À chaque tic : si bit 0 (fermé) ⇒ ni rescan ni titre. Sinon rescan disques ; puis **si bit 2
  est mis ⇒ pas de mise à jour du titre** (message affiché). Sinon **AvailMem(0)** (MEMF_ANY,
  total libre) comparé à **G+$2F2** ; si **différent** : bit 2 := 1, G+$2F2 := valeur,
  **RawDoFmt("Workbench release 1.2.  %ld free memory", valeur) → G+$3DA**, puis
  `ShowTitle(G+$3DA)` (qui efface le bit 2 et applique à **toutes** les fenêtres WB ouvertes,
  §6.2 étape 4 — pas seulement la backdrop). Égal ⇒ rien n'est ré-appliqué.
- Rename : à l'ouverture de sa fenêtre de saisie, bit 1 := 1, **G+$2F2 := 0** (force le prochain
  rafraîchissement), copie de `"Enter the new name.  Press return when done."` dans G+$3DA,
  appliquée comme titre d'écran à la fenêtre de saisie ; à la fin, bit 1 := 0 et un tic est
  exécuté immédiatement (sans renvoi de requête timer) qui réécrit le titre mémoire. [O]

### 6.5 Special/Last Error (code menu $F822 = menu 2, élément 1) [O]

1. Restauration du titre mémoire (début de MENUPICK, bit 2 := 0).
2. **`ShowTitle(*(G+$2EE))`** : le format passé **est le tampon du dernier message lui-même** ⇒
   **pas de bip, pas de reformatage** ; le **dernier message affiché** (quel qu'il soit : erreur,
   texte Version, « cannot be moved… », etc.) est ré-appliqué comme titre d'écran de toutes les
   fenêtres WB, et le bit 2 est remis (persistance identique à §6.3 point 5). Ce n'est **pas** un
   code d'erreur relu : c'est le texte déjà formaté au moment de l'erreur. Ex. : Version puis Last
   Error ⇒ réaffiche « Kickstart version 34.5. Workbench version 34.34 ».
3. Aucun message encore produit (G+$2EE = 0) : le tampon est alloué à ce moment, puis, le format
   (0) différant du tampon, **bip** + RawDoFmt avec un format à l'adresse 0 [O] ⇒ en pratique un
   titre vide si l'octet en $0 vaut 0 [S]. Une réimplémentation peut afficher une chaîne vide.
4. Origine des messages d'erreur [O] : une routine d'erreur prend (index d'action, nom) ; elle
   formate dans un tampon local de 80 octets l'action choisie dans la table ci-dessous (avec le nom
   pour `%s`), puis appelle `ShowTitle("Error while %s: %ld", action, IoErr())` — le code est
   **dos IoErr()** au moment de l'erreur. Table (index → texte) : 0 `"examining directory"`,
   1 `"accessing %s"`, 2 `"opening %s"`, 3 `"reading"`, 4 `"writing"`, 5 `"moving %s"`,
   6 `"removing %s"`, 7 `"examining %s"`, 8 `"writing %s"`. Ex. : `"Error while opening Foo: 205"`.
   Autres messages directs via ShowTitle (non détaillés ici) : `"'%s' cannot be moved out of its
   window"`, `"Do not use '%lc' in names"`, `"Cannot read info file %s"`.

### 6.6 Remplaçant de SetWindowTitles installé par LoadWB 1.3.3 [O WB]

Mise en place : LoadWB alloue **162 octets MEMF_PUBLIC|MEMF_CLEAR** (jamais libérés), y copie le
hunk n° 4, fait **SetFunction(IntuitionBase, −276, copie+4)** et range l'ancien vecteur dans le
premier long de la copie (le remplaçant finit en sautant à l'ancien vecteur, A0/A1 préservés,
**A2 éventuellement substitué**). Avant la copie, deux chaînes du hunk sont **désobfusquées en
place** : chaque octet est **XOR $9E** jusqu'à l'octet 0 (le 0 terminal n'est pas chiffré).

Chaînes du patch (en clair) :
- référence non chiffrée : `"Workbench release 1.2."` (22 octets) ;
- chiffrée 1 : `"We made Amiga, T"` (16 octets) ;
- chiffrée 2 : `" Still a Champion"` (17 octets, espace initial).

Comportement observable (seul le **titre d'écran**, argument A2, est examiné ; le titre de fenêtre
n'est jamais modifié) :
1. A2 = NULL ou −1 ⇒ appel original inchangé.
2. Si l'octet **A2[20] == '2'** **et** la chaîne **commence par** `"Workbench release 1.2."` (22
   octets comparés) ⇒ la chaîne de l'appelant est **modifiée en place** : A2[17] := `'.'`,
   A2[18..21] := 4 espaces. `"Workbench release 1.2.  884392 free memory"` devient
   **`"Workbench release.      884392 free memory"`** (« release. » suivi de **6 espaces** : les 4
   écrits + les 2 du format), puis appel original avec ce même pointeur. Comme le WB réécrit
   G+$3DA par RawDoFmt à chaque changement de mémoire, la retouche est refaite à chaque tic qui
   écrit ; un second passage sur une chaîne déjà retouchée ne la reconnaît plus (A2[20] = espace)
   et la laisse telle quelle.
3. Sinon, si la chaîne **commence par** `"We made Amiga, T"` ⇒ A2 est **remplacé** par le pointeur
   vers `" Still a Champion"` (le titre d'écran affiché devient exactement cette chaîne).
4. Sinon ⇒ inchangé. **Aucune** transformation de « 34.xx » : le texte Version
   (`"Kickstart version …"`) passe intact ; le « 34.34 » vient de version.library (§6.3), pas du
   patch.

Conséquence pour notre ROM [D] : pour obtenir avec ce LoadWB le même affichage que la vraie ROM,
il suffit de passer à SetWindowTitles un titre d'écran **commençant exactement par**
`"Workbench release 1.2."` avec un `'2'` en position 20, dans un tampon **inscriptible** (le patch
écrit dedans), et de formater Version depuis l'en-tête ROM + version.library. Remarque : le relevé
boîte noire « `Workbench release.    884392` » (4 espaces) est vraisemblablement un comptage visuel ;
le calcul exact donne 6 espaces [D].

### 6.7 Vecteurs de test [O sauf mention]

| Action | Titre d'écran attendu (avec LoadWB 1.3.3 et version.library 34.34) |
|---|---|
| Démarrage, tic | `"Workbench release.      <n> free memory"` sur backdrop et tiroirs ouverts |
| Special/Version | bip ; `"Kickstart version 34.5. Workbench version 34.34"`, figé (tics ignorés) |
| … puis 10 s sans clic | inchangé |
| … puis clic gauche dans une fenêtre WB | titre mémoire (valeur du dernier tic), mises à jour reprises |
| Special/Last Error après Version | même texte Version, **sans** bip |
| Special/Version sans version.library | `"Kickstart version 34.5. Workbench version -1.-1"` |

### 6.8 Activation des fenêtres

**Côté Workbench [O]**

- Le module n'a que **deux** appels à OpenWindow : la routine générique des fenêtres WB (backdrop
  `$02000B40`, tiroirs/disques `$0200027F`) et la **fenêtre de saisie du Rename**. Les seules
  constantes de Flags de fenêtre WB sont ces deux-là : **ni la backdrop ni les tiroirs n'ont
  ACTIVATE ($1000)**, et rien n'ajoute ce bit avant l'ouverture.
- La **fenêtre Rename** est la **seule ouverte avec ACTIVATE** : NewWindow Left 60, Top 100,
  Width 504, Height 11, DetailPen 3, BlockPen 1, IDCMPFlags 0 à l'ouverture, **Flags = $1000**
  (ACTIVATE seul), FirstGadget = le gadget chaîne du nom. Ensuite `wd_UserPort := port B` et
  **ModifyIDCMP(win, $40040)** (ACTIVEWINDOW | GADGETUP).
- **ActivateWindow (−450)** : **un seul site d'appel**, dans la boucle modale du Rename (qui lit
  le port B tant que la saisie n'est pas finie) :
  - message **ACTIVEWINDOW ($40000) venant d'une autre fenêtre WB** que celle du Rename ⇒
    **ActivateWindow(fenêtre Rename)** : le WB reprend l'activation. Les autres messages des
    autres fenêtres sont mis de côté puis **remis dans le port B** à la fin de la saisie (sous
    Forbid). [O ; le filtre exact des messages mis de côté est D]
  - message **ACTIVEWINDOW de la fenêtre Rename elle-même** ⇒ **ActivateGadget(gadget, fenêtre
    Rename, NULL)** (−462) puis ReplyMsg : le curseur passe dans le champ texte.
  - tout autre message de la fenêtre Rename (GADGETUP, Return) termine la boucle.
- Le Workbench **n'appelle jamais ActivateWindow** pour la backdrop ou un tiroir : ni à
  l'ouverture de la backdrop, ni à la fermeture d'un tiroir, ni sur DISKINSERTED, ni au tic, ni
  à la fin du Rename (la fermeture de la fenêtre Rename relève de la règle intuition ci-dessous).

**Côté intuition 34.3 (ROM) : règle d'activation automatique**

Champs publics de `struct Window` utilisés : **Parent +$42**, **Descendant +$46**,
WScreen +$2E. Champs publics de `struct Screen` : FirstWindow +$04. Champs publics
d'IntuitionBase : **ActiveWindow +$34**, ActiveScreen +$38.

- **OpenWindow** [O] :
  - la nouvelle fenêtre est ajoutée en **tête** de `Screen->FirstWindow` ;
  - **Parent := ActiveWindow courante** (éventuellement NULL) ;
  - la fenêtre est insérée dans la chaîne Parent/Descendant juste après cette fenêtre active
    (`new->Descendant := active->Descendant`, avec le chaînage arrière correspondant ;
    `active->Descendant := new`) ;
  - elle n'est activée **que si NewWindow.Flags contient ACTIVATE**. **Pas de règle « aucune
    fenêtre active ⇒ activer »** à l'ouverture, ni de cas particulier BACKDROP/WBENCHWINDOW.
- **CloseWindow** [O] :
  - la fenêtre est retirée de la chaîne Parent/Descendant : son Descendant hérite de son
    Parent, et inversement ;
  - elle est retirée de la liste des fenêtres de l'écran [D pour l'ordre exact] ;
  - **si c'était l'ActiveWindow**, la nouvelle fenêtre active est :
    1. son **Parent** (la fenêtre qui était active quand elle a été ouverte, ou, si celle-ci
       a été fermée entre-temps, l'ancêtre qui a hérité du lien) ;
    2. à défaut, la **première fenêtre de son écran** (`Screen->FirstWindow`, la plus
       récemment ouverte qui reste) ;
    3. à défaut, **ActiveWindow := NULL**.
  - Quand une fenêtre est trouvée, ActiveWindow et ActiveScreen sont mis à jour et la routine
    interne d'activation est appelée, la même que pour ActivateWindow. La nouvelle fenêtre
    active reçoit donc ACTIVEWINDOW si elle l'a demandé [D].
  - Si la fenêtre fermée n'était pas active, rien ne change.
- **ActivateWindow** : appelle directement cette routine interne d'activation (mode 1). [O]

**Application au cas observé** [D, cohérent avec la boîte noire] :

1. Au boot, la fenêtre du CLI initial est active.
2. LoadWB lance le WB, qui ouvre la backdrop sans ACTIVATE. Elle est donc ajoutée en tête de
   FirstWindow, avec **Parent = la fenêtre CLI**.
3. `endcli` ferme la fenêtre CLI, qui est active. Son Parent est NULL : c'était la première
   fenêtre ouverte. Intuition prend donc **FirstWindow = la backdrop** et l'active.
4. Le bouton droit montre alors les menus du WB sans aucun clic.

Pour obtenir ce comportement, notre intuition doit seulement reproduire la règle de CloseWindow.
Le module workbench n'a rien à activer lui-même.

### 6.9 Messages d'erreur : sites d'appel

Rappels :
- **« ShowTitle »** est la routine de §6.2 : le premier message affiché gagne jusqu'au prochain
  clic ou choix de menu, et il y a un bip.
- **« ErrMsg(i, nom) »** est la routine d'erreur de §6.5. Elle formate l'action n° i (avec `nom`
  pour `%s`), puis appelle `ShowTitle("Error while %s: %ld", action, IoErr())`.
- **IoErr()** est lu **dans ErrMsg**, après le formatage local, qui ne fait aucun appel dos. Il
  n'y a donc qu'un seul appel dos entre l'échec et la lecture. La valeur affichée est celle que
  dos a laissée dans `pr_Result2` lors de l'échec. Il y a deux exceptions, décrites plus bas, où un
  appel intermédiaire a lieu entre-temps : le requester errorreq (§3.7) et le nettoyage d'un
  lancement raté.
- Les actions sans `%s` (0 `"examining directory"`, 3 `"reading"`, 4 `"writing"`) ignorent le nom.
- Quand la **routine elle-même** affiche un message et que **son appelant** en émet un second, le
  second est **ignoré** : le bit 2 est déjà mis (§6.2). Seul le premier est visible.

**Ce qui déclenche une erreur dos, et quel message s'affiche [O sauf mention]**

1. **Lecture du contenu d'un tiroir ou d'un disque** (ouverture de sa fenêtre)
   - Échec : `Examine(lock du tiroir)`.
     Message : ErrMsg(**7**, **nom de l'objet**) ⇒ `"Error while examining <nom>: <err>"`.
   - Cas : le lock n'est pas un répertoire (fib_DirEntryType < 0).
     Message : ShowTitle `"This drawer is not really a directory"`.
   - Échec, dans la boucle de lecture (routine générique de parcours, qui fait CurrentDir sur le
     répertoire) : `Examine` puis `ExNext` quand IoErr ≠ 232 (ERROR_NO_MORE_ENTRIES).
     Message : ErrMsg(**0**) ⇒ `"Error while examining directory: <err>"`.
   - Cas : la fenêtre du tiroir n'a pas pu se remplir.
     Message : ShowTitle `"This drawer cannot be opened"` (en général masqué par le message
     précédent). Un échec d'OpenWindow ou d'AllocMem donne à la place
     `"Ran out of memory.  Please free some and try again."`.
   - Un `.info` illisible pendant ce parcours est **ignoré en silence** : pas de message
     « Cannot read info file ».
2. **Lancer un outil ou un projet** (double-clic, ou menu Open)
   - CurrentDir = répertoire parent de l'icône double-cliquée. Pour un projet, c'est le
     répertoire **du projet**, et `nom` est son **Default Tool** tel qu'il est écrit dans l'icône,
     relatif ou avec un volume.
   - Échec : `LoadSeg(nom)`.
     Message : ErrMsg(**2**, **nom de l'outil**) ⇒ `"Error while opening <outil>: <err>"`.
   - Échec : AllocMem du WBStartup, ou CreateProc. Le WB fait **UnLoadSeg** (et FreeMem), puis
     le **même** ErrMsg(2, outil). IoErr est alors lu après ces appels [D : valeur du dernier
     appel dos].
   - Cas : aucun outil parmi les icônes sélectionnées et aucun Default Tool.
     Message : ShowTitle `"The icon(s) have no default tool"`.
   - Le WB ne fait **pas de Lock** du répertoire qui puisse produire un « accessing » à ce stade.
3. **Rename** (menu Workbench, élément 3 ; saisie dans la fenêtre Rename)
   - Nouveau nom identique à l'ancien ⇒ rien n'est fait.
   - Caractères interdits : **`':'` ($3A)**, puis **`'/'` ($2F)**, dans cet ordre, recherchés dans le
     nouveau nom. Message : ShowTitle `"Do not use '%lc' in names"`, avec le caractère
     sign-étendu en long. Exemples : `"Do not use ':' in names"`, `"Do not use '/' in names"`.
     Aucun autre caractère n'est refusé.
   - Fichier, tiroir, outil ou projet : renommage dans le même répertoire par un **packet
     ACTION_RENAME_OBJECT (17)**. Il est envoyé **directement au handler du lock source** ; ce
     n'est **pas** dos `Rename()`. Deux renommages ont lieu, `nom → nouveau`, puis
     `nom.info → nouveau.info`.
     - Pour le **premier** seulement, un échec avec IoErr = **205** (objet absent) est **toléré** :
       une icône sans fichier peut quand même être renommée.
     - Sinon, sur échec, le WB appelle **errorreq(2, lock de destination, son fl_Task)** (§3.7).
       Retour 0 (Retry) ⇒ nouvel essai. Non nul ⇒ ErrMsg(**5**, **ancien nom**, ou
       `ancien.info` au 2ᵉ renommage) ⇒ `"Error while moving <ancien>: <err>"`. Oui, c'est bien
       « moving » qui s'affiche pour un Rename.
   - Disque : **packet ACTION_RENAME_DISK (9)** au handler du volume. Sur échec, errorreq(2, …) :
     Retry ⇒ nouvel essai, abandon ⇒ ShowTitle `"Can't rename this disk"`.
4. **Glisser une icône dans une autre fenêtre** (déplacement)
   - Type de l'icône hors du masque **$001C** (seuls tiroir 2, outil 3 et projet 4 peuvent
     sortir de leur fenêtre ; pas disque 1, poubelle 5, etc.).
     Message : ShowTitle `"'%s' cannot be moved out of its window"`, avec **nom de l'objet**.
   - Dépôt sur une fenêtre qui n'est pas une fenêtre WB connue.
     Message : ShowTitle `"Icons cannot be moved into this window"`.
   - Disque déposé sur un disque, types incompatibles.
     Message : ShowTitle `"Disks are of incompatible type and cannot be copied"`.
   - Disque déposé sur un disque, icône sans Default Tool (DiskCopy).
     Message : ShowTitle `"This disk cannot be copied"`.
   - **Même volume** : même procédé que le Rename (packet 17, `nom` puis `nom.info`, tolérance 205
     sur le premier, errorreq puis ErrMsg(**5**, **nom**)).
   - **Autre volume** : c'est une **copie**, la source n'est pas supprimée. Si `Lock(nom)` dans le
     répertoire source échoue (205 toléré pour le premier), message : ErrMsg(**1**, **nom**) ⇒
     `"Error while accessing <nom>: <err>"`. La suite passe par la copie (point 6).
5. **Discard** (menu Workbench, élément 5 ; après le requester `"ok to discard"` / `"forget it!"`)
   - CurrentDir = répertoire parent, puis `Lock(nom de l'objet, SHARED)`. Si ce Lock échoue :
     avec IoErr = 205, on passe directement aux DeleteFile ; avec un autre code, le Discard est
     **abandonné sans message**. Si l'objet est un répertoire, son contenu est vidé
     **récursivement** par la routine générique de parcours : un échec d'Examine ou d'ExNext
     donne ErrMsg(**0**), puis l'abandon. Toute autre erreur de la récursion provoque aussi un
     abandon silencieux du niveau supérieur (son message éventuel a déjà été affiché).
   - Chaque fichier rencontré est supprimé par **DeleteFile** :
     - échec avec IoErr = **205** ⇒ considéré comme réussi, aucun message ;
     - autre échec ⇒ ErrMsg(**6**, **nom tel que passé à DeleteFile**) ⇒
       `"Error while removing <nom>: <err>"`. C'est le **nom simple** (fib_FileName relatif au
       répertoire courant), pas un chemin.
   - Enfin l'objet lui-même : `DeleteFile(nom)` puis `DeleteFile(nom.info)`, mêmes règles
     (message `"removing <nom>"` ou `"removing <nom>.info"`). L'appelant émet ensuite
     ErrMsg(6, **nom de l'objet**), mais ce second message est **masqué** par le premier.
   - Un Lock raté d'un sous-tiroir pendant la récursion arrête la suppression **sans message**.
6. **Duplicate** (menu Workbench, élément 2) et copie vers un autre volume
   - Disque : lancement de son Default Tool (DiskCopy), comme au point 4.
   - Objet : CurrentDir = répertoire parent, puis `Lock(nom, SHARED)`. Échec ⇒ ErrMsg(**1**,
     **nom de l'objet**).
   - Le nouveau nom est produit par icon **BumpRevision** (`"copy of …"`). L'icône est écrite par
     PutWBObject, puis relue. Si la relecture échoue, message : ShowTitle
     `"Cannot read info file %s"` avec le **nouveau nom**. C'est le **seul** site de ce message.
   - Copie récursive :
     - sous-répertoire non verrouillable ⇒ ErrMsg(**1**, nom de l'entrée) ;
     - `Open(source, MODE_OLDFILE 1005)` raté ⇒ ErrMsg(**2**, **nom source**) ;
     - `Read` ≤ 0 avant d'avoir lu la taille annoncée ⇒ ErrMsg(**3**) ⇒
       `"Error while reading: <err>"` ;
     - côté destination, `Open(dest, MODE_NEWFILE 1006)` raté ⇒ ErrMsg(**2**, **nom
       destination**) ;
     - répertoire destination : `Lock(dest)`, puis `CreateDir(dest)` si IoErr = 205 ; échec
       final ⇒ ErrMsg(**1**, nom destination) ;
     - `Write` qui écrit moins que demandé ⇒ ErrMsg(**4**) ⇒ `"Error while writing: <err>"`.
7. **Snapshot** (menu Special, élément 3)
   - Pour chaque icône sélectionnée : CurrentDir = répertoire parent, puis
     **PutWBObject(nom, objet)**, avec `"Disk"` comme nom pour une icône de disque.
   - Échec ⇒ ErrMsg(**8**, **nom de l'objet**, le nom du volume pour un disque) ⇒
     `"Error while writing <nom>: <err>"`.
   - Le module n'appelle pas PutDiskObject : l'interface WB 1.x est PutWBObject.
8. **Info** (menu Workbench, élément 4) : si `OpenLibrary("info.library", 0)` échoue, message :
   ShowTitle `"Info not available"`.
9. **Manque de mémoire** : plusieurs AllocMem (Duplicate, Discard, lancement, ouverture de
   tiroir…) donnent ShowTitle `"Ran out of memory.  Please free some and try again."`.

**Requesters dos et message de titre [O/D]**

- Le message de titre est émis **en plus** d'un éventuel requester. Ce n'est pas l'un ou l'autre.
- Requester **appelé explicitement par le WB** (errorreq, uniquement pour le renommage, le
  déplacement sur le même volume et le renommage de disque) :
  - « Retry » ⇒ l'opération est refaite, sans message ;
  - « Cancel » ⇒ le message ErrMsg ou ShowTitle **s'affiche ensuite** ;
  - errorreq ne présente pas de requester pour tous les codes [D, comportement dos] ; quand il
    n'en montre pas, le message suit immédiatement ;
  - IoErr est relu **après** errorreq. On suppose qu'errorreq ne modifie pas `pr_Result2` [S].
- Requesters **émis par dos lui-même** pendant Lock, Open ou LoadSeg (par exemple `"Please insert
  volume"`) : le WB a `pr_WindowPtr = 0` (requesters sur l'écran WB), sauf pendant l'écriture d'un
  `.info`, où il vaut −1 (§3.3). Après « Cancel », l'appel échoue et le message de titre
  correspondant s'affiche aussi [D].

---

## 7. Workbench/Info et info.library

Sources : ROM (routine Info du module wb) et `libs/info.library` de `wb133.adf`
(16 380 octets, 25 hunks ; extraite et relogée dans le scratch de la piste analyse). info.library
est un **binaire du disque que nous ne réimplémentons pas** : cette section décrit **le contrat
d'appel** et les **champs** qu'elle lit et écrit, pour que notre ROM puisse l'appeler.

### 7.1 Côté Workbench (menu Workbench, élément 4, code $F880) [O]

1. Comme pour tout MENUPICK, le titre mémoire est d'abord restauré (§6.2).
2. La routine Info est appelée pour **chaque icône sélectionnée**, l'une après l'autre (même
   itérateur que Snapshot) [D pour l'ordre].
3. Pour une icône :
   - **Disque** (type 1) dont le WB ne connaît pas de lock de répertoire : **rien** (pas de
     message).
   - Sinon **`OpenLibrary("info.library", 0)`** (version **0**).
   - En cas d'échec : `ShowTitle("Info not available")` (§6.9 point 8).
   - En cas de succès : appel du **LVO −30** de la base obtenue, avec **A6 = InfoBase**,
     **A0 = InfoBase** (copie, inutilisée par la librairie) et **A1 = pointeur sur le WBObject**
     de l'icône (structure **privée** du Workbench, §7.3). La **valeur de retour est ignorée**.
   - Puis **`CloseLibrary(InfoBase)`**.
4. Aucun rafraîchissement d'icône n'est fait au retour, à part la fin commune des MENUPICK. Ce
   qu'info.library a changé dans le WBObject (outil par défaut, tool types, pile) reste en
   mémoire tel quel.
5. **L'appel est synchrone et modal** : info.library tourne **dans le process Workbench**, ouvre sa
   propre fenêtre et attend ses propres événements jusqu'à SAVE ou QUIT. Pendant ce temps le WB ne
   traite ni ses ports A et B, ni ses tics [D, conséquence directe].

### 7.2 info.library : identité, vecteurs, librairies [O]

- **ROMTag** : `rt_Flags = $80` (AUTOINIT), version 34, `rt_Type = 9` (NT_LIBRARY), pri 0, nom
  `"info.library"`, IdString `"info V1.3\r\n"`.
- Base de **$26 octets** (sizeof Library) ; **lib_Version 34**, lib_Revision 0. L'init mémorise
  SysBase et la seglist.
- **Vecteurs** : Open, Close, Expunge, Reserved, puis **une seule fonction publique**, le
  **LVO −30**, que nous appelons ici `Info(wbobject)` (nom déduit [D]). Argument : **A1** =
  WBObject. Pas de callback ni de pointeur de fonction fourni par le Workbench.
- **Librairies ouvertes par elle-même**, toutes en **version 0**, puis refermées en sortie :
  - `"dos.library"` : Lock, UnLock, Examine, Info, SetComment, SetProtection ;
  - `"icon.library"` : **PutWBObject (−36)**, **AddFreeList (−72)** ;
  - `"intuition.library"` : OpenWindow, CloseWindow, SetWindowTitles, AddGadget, RemoveGadget,
    RefreshGadgets, ActivateGadget, DisplayBeep, SetPointer, BeginRefresh/EndRefresh,
    AllocRemember/FreeRemember ;
  - `"graphics.library"` : OpenFont/CloseFont (`topaz.font`, hauteurs 9 et 8), SetFont, Text,
    Move/Draw, RectFill, SetAPen, SetDrMd, SetRast.
- **exec** : AllocMem, FreeMem, Forbid/Permit, Insert/AddTail/Remove, **FindTask(0)**, Wait,
  GetMsg, ReplyMsg, CloseLibrary, OpenLibrary.
- Si une ouverture de librairie, une allocation, le Lock ou la police échoue : nettoyage et retour
  **sans message**.

### 7.3 Champs du WBObject lus ou écrits par info.library [O]

L'objet est la structure privée du Workbench 1.x telle qu'icon.library 1.3 la construit
(AllocWBObject / GetWBObject). Info utilise uniquement les champs suivants.

| Off. | Taille | Sens | Accès |
|---|---|---|---|
| **+$38** | ptr | **objet parent** (WBObject du tiroir ou disque qui contient l'icône) | L |
| **+$3D** | octet | **type** : 1 disque, 2 tiroir, 3 outil, 4 projet, 5 poubelle, 6 device, 7 kick | L |
| **+$40** | ptr | **nom** (C, sans `.info`) | L |
| **+$48** | ptr | **outil par défaut** (C, ou NULL) | L, **E** (nouvelle chaîne) |
| **+$4C** | ptr | **DrawerData** ; seul **+$1BA** y est lu = **lock (BPTR) du répertoire** | L |
| **+$5C** | ptr | **tool types** (`char **` terminé par NULL, ou NULL) | L, **E** (nouveau tableau ou NULL) |
| **+$8C** | struct | **FreeList** de l'objet (passée à icon **AddFreeList**) | adresse passée |
| **+$A0** | long | **taille de pile** (outil et projet) | L, **E** |
| **+$A4** | BPTR | **lock du répertoire contenant**, s'il est connu directement (prioritaire) | L |

Après l'appel, l'objet complet est passé à **PutWBObject**. Les champs qu'icon.library lit pour
écrire le `.info` relèvent du contrat d'icon.library, pas de celui d'info.library.

**Répertoire de travail utilisé** (ordre de priorité) :
1. type 7 ⇒ aucun (pas d'Info utile) ;
2. `+$A4` s'il est non nul ;
3. pour un **disque**, son **propre** `+$4C → +$1BA` (lock de la racine) ;
4. sinon le `+$4C → +$1BA` du **parent** (`+$38`) ;
5. à défaut, 0.

**Effet de bord [O]** : info.library **écrit ce lock directement dans `pr_CurrentDir` (+$98)** du
process appelant (via FindTask(0)), **sans CurrentDir() et sans restauration**. Le Workbench doit
donc être un **Process** (pas une simple Task). Son répertoire courant pointe ensuite sur ce lock,
ce qui est sans danger puisque le WB refait CurrentDir avant chaque opération (§6.9).

**Allocations attachées à l'objet** : la nouvelle chaîne d'outil par défaut, le nouveau tableau
de tool types et chaque nouvelle chaîne de tool type sont alloués par AllocMem : flags 0 pour
l'outil par défaut (nouvel essai avec MEMF_PUBLIC si l'allocation échoue), **MEMF_CLEAR** pour
les tool types. Ils sont ensuite enregistrés par
**AddFreeList(objet+$8C, mémoire, taille)**. Ils sont donc libérés avec l'objet (FreeWBObject). Les
anciennes chaînes et l'ancien tableau ne sont **pas** libérés.

### 7.4 Déroulé de `Info(objet)` [O]

1. Ouverture des 4 librairies, puis une Remember-list intuition (AllocRemember, MEMF_CLEAR |
   MEMF_CHIP) pour toutes les données internes.
2. CurrentDir forcé (§7.3), puis **`Lock(nom, SHARED)`** avec comme nom :
   - pour un disque, la chaîne `"disk.info"`. Si ce Lock échoue, le lock de la racine du disque
     (`+$4C → +$1BA`) est **emprunté** à la place, et ne sera pas UnLocké ;
   - pour les autres types, `+$40`.
3. Lectures :
   - disque : **`Info(lock, InfoData)`** ;
   - les autres : **`Examine(lock, FIB)`**. Retenus : `fib_Protection` (+$74), taille, nombre de
     blocs, **`fib_Comment` (+$90)**.
   - outil par défaut (`+$48`), copié dans un tampon d'au moins 256 octets ;
   - pile (`+$A0`) ;
   - tool types (`+$5C`).
4. Ouverture de la fenêtre :
   - NewWindow : Left 0, Top 10, Width 604, Height 190, DetailPen −1, BlockPen 1 ;
   - IDCMP **$244** (REFRESHWINDOW | GADGETUP | CLOSEWINDOW) ;
   - Flags **$146F** (SIZING | DRAG | DEPTH | CLOSE | SIZEBBOTTOM | SIMPLE_REFRESH |
     GIMMEZEROZERO | **ACTIVATE**) ;
   - titre de fenêtre **`"Info release 1.31"`**, Min 210×50, Max 604×190, **Type WBENCHSCREEN** ;
   - puis **`SetWindowTitles(win, −1, "Info release 1.31")`** : le **titre d'écran** devient ce
     texte (le patch LoadWB §6.6 le laisse passer intact).
5. Boucle d'événements sur le UserPort de **sa** fenêtre (Wait, GetMsg, ReplyMsg), avec gestion
   des gadgets.
6. **SAVE** :
   - outil ou projet : `+$A0` := pile saisie ;
   - tool types reconstruits (`+$5C`), ou NULL si la liste est vide ;
   - si l'outil par défaut a changé : nouvelle chaîne dans `+$48` ;
   - fichiers, pour les types autres que disque :
     1. `SetProtection("<nom>.info", 0)` (permet l'écriture) ;
     2. **`PutWBObject(nom, objet)`**, avec **`"Disk"`** comme nom pour un disque ;
     3. `SetComment(nom, commentaire)` ;
     4. `SetProtection(nom, protection saisie)` ;
     5. `SetProtection("<nom>.info", protection & ~$10)` (bit 4, archive, retiré).
   - Disque : seulement `PutWBObject("Disk", objet)` dans la racine.
   - Un échec est mémorisé ; le comportement visible exact (bip ?) n'a pas été tranché [S].
7. **QUIT**, ou gadget de fermeture : sortie sans écrire.
8. Nettoyage : CloseWindow, CloseFont, FreeRemember(…, TRUE), UnLock du lock (sauf s'il était
   emprunté), CloseLibrary des 4 librairies. **D0 au retour n'a pas de sens défini.**

### 7.5 Ce que l'utilisateur voit (chaînes de la librairie) [O pour les chaînes, D pour la disposition]

- **Libellés communs** : `NAME`, `TYPE`, `STATUS`. Boutons texte : **`"  SAVE  "`** et
  **`"  QUIT  "`** (deux espaces de chaque côté), **`ADD`** et **`DEL`** (tool types). Police
  topaz 8 et 9.
- **Disque** (TYPE `"Disk"`) :
  - `Number of Blocks`, `Number Used`, `Number Free`, `Bytes per Block`, d'après l'InfoData ;
  - STATUS selon `id_DiskState` : `Read Only`, `Validating`, `Read/Write`, sinon
    `I'm not sure` ;
  - champs éditables `DEFAULT TOOL`, `TOOL TYPES` ;
  - pas de commentaire ni de protections.
- **Tiroir** (`"Drawer"`) : `COMMENT`, `TOOL TYPES`, protections.
- **Outil** : taille `in bytes` et `in blocks`, `COMMENT`, `STACK`, `TOOL TYPES`, protections.
- **Projet** (`"Project"`) : `in bytes`, `in blocks`, `COMMENT`, `STACK`, `DEFAULT TOOL`,
  `TOOL TYPES`, protections.
- **Poubelle** (`"Garbage"`) : `COMMENT`, `TOOL TYPES`.
- **Device** : libellé `"Device"`.
- **Protections** : cases `ARCHIVED`, `READABLE`, `WRITEABLE`, `DELETEABLE`, d'après les bits de
  `fib_Protection` (sémantique 1.3 : bit à 1 = interdit, pour R, W et D).

### 7.6 Disque et tiroir ouvert : différences [O]

- **Disque** :
  - le WB n'appelle Info que s'il connaît un lock pour ce disque (sinon rien) ;
  - info.library utilise le lock de racine **du disque lui-même** (`+$4C → +$1BA`) ;
  - elle lit les statistiques par `Info()` ;
  - elle sauve seulement `Disk.info` (PutWBObject `"Disk"`), sans SetComment ni SetProtection.
- **Tiroir**, ouvert ou fermé : **aucune différence** pour info.library. Elle ne regarde
  **jamais** la fenêtre ni le DrawerData **du tiroir lui-même**, seulement celui de son
  **parent** (ou `+$A4`). L'objet est verrouillé par son nom dans le répertoire parent et lu par
  Examine, comme un fichier.

### 7.7 Exigences pour notre ROM [D]

- `OpenLibrary("info.library", 0)` doit pouvoir réussir : la librairie du disque est chargée
  par ramlib depuis `LIBS:`.
- **Appel** : JSR −30(A6) avec **A6 = A0 = InfoBase** et **A1 = WBObject**.
- **WBObject** : remplir au minimum +$38, +$3D, +$40, +$48, +$4C (et +$1BA du DrawerData des
  conteneurs), +$5C, +$8C (FreeList valide), +$A0, +$A4, avec ces offsets et ce sens. Le reste de
  l'objet doit convenir à **PutWBObject** de l'icon.library utilisée.
- **icon.library** : doit exposer **PutWBObject (−36)** et **AddFreeList (−72)** compatibles 1.3.
- **Process** : le WB doit être un Process, car `pr_CurrentDir` (+$98) est écrit directement.

### 7.8 Obtenir le WBObject depuis icon.library 1.3 (`libs/icon.library`, « icon 34.2 (22 Jun 1988) ») [O]

**Vecteurs.** Table de pointeurs absolus, dans l'ordre du `.fd` public :

| LVO | Fonction | Registres | Retour |
|---|---|---|---|
| −30 | **GetWBObject**(name) | A0 | WBObject* ou 0 |
| −36 | **PutWBObject**(name, object) | A0, A1 | booléen |
| −42 | GetIcon(name, icon, freelist) | A0, A1, A2 | booléen |
| −48 | PutIcon(name, icon) | A0, A1 | booléen |
| −54 | FreeFreeList(freelist) | A0 | — |
| −60 | **FreeWBObject**(object) | A0 | — |
| −66 | **AllocWBObject**() | — | WBObject* ou 0 |
| −72 | AddFreeList(freelist, mem, len) | A0, A1, A2 | booléen |
| −78 | GetDiskObject(name) | A0 | DiskObject* |
| −84 | PutDiskObject(name, diskobj) | A0, A1 | même point d'entrée que −48 |
| −90 | FreeDiskObject(diskobj) | A0 | — |
| −96 | FindToolType(array, name) | A0, A1 | |
| −102 | MatchToolValue(string, value) | A0, A1 | |
| −108 | BumpRevision(new, old) | A0, A1 | |

**AllocWBObject()**
- Alloue **$A8 = 168 octets MEMF_CLEAR**. C'est la taille totale du WBObject : tous les offsets
  utilisés par le WB et par info.library (≤ +$A4) y tiennent.
- Initialise la **FreeList en +$8C**, qui occupe +$8C..+$9B : `fl_NumFree` (mot) en +$8C, puis
  la liste des MemList en +$8E.
- **Inscrit l'objet lui-même dans sa FreeList** (AddFreeList(objet+$8C, objet, 168)).

**GetWBObject(name)**
- Fait AllocWBObject, puis **GetIcon(name, DiskObject local, objet+$8C)**. Toutes les
  allocations de l'icône vont donc dans la FreeList de l'objet.
- GetIcon ouvre **`"<name>.info"` en MODE_OLDFILE relativement au répertoire courant du process
  appelant**. L'appelant doit donc faire CurrentDir(répertoire contenant) avant l'appel ; pour un
  disque, name = `"Disk"` dans la racine.
- GetIcon lit l'en-tête de 78 octets et vérifie **magic $E310** et **version 1**. Pour un échec
  d'allocation, IoErr est forcé à 103.
- En cas d'échec, l'objet est libéré et la fonction rend 0.
- Champs remplis, copiés depuis le DiskObject lu :

| Off. WBObject | Source (champ public DiskObject) |
|---|---|
| +$3D (octet) | `do_Type` |
| +$48 | `do_DefaultTool` (chaîne allouée dans la FreeList) |
| +$4C | `do_DrawerData` (0 si l'icône n'en a pas) |
| +$54 / +$58 | `do_CurrentX` / `do_CurrentY` |
| +$5C | `do_ToolTypes` (tableau et chaînes alloués dans la FreeList) |
| +$60 .. +$8B | `do_Gadget`, 44 octets (struct Gadget, images GadgetRender/SelectRender allouées en CHIP dans la FreeList) |
| +$9C | `do_ToolWindow` |
| +$A0 | `do_StackSize` |
| +$8C | FreeList (contient l'objet et toutes ses allocations) |

- **Non remplis, restent à 0** : **+$38** (parent), **+$40 (nom : PAS copié de l'argument)**,
  **+$A4** (lock), ainsi que tout le reste de l'objet. Le WB 1.3 pose +$40 lui-même. Pour
  info.library, **c'est à nous de remplir +$40, et selon le cas +$38 / +$A4.**
- **DrawerData**, seulement si l'icône en a une (tiroir, disque, poubelle) :
  - bloc de **$1BE = 446 octets MEMF_CLEAR|MEMF_CHIP**, alloué dans la FreeList ;
  - les 56 premiers octets (NewWindow + CurrentX/Y) sont lus dans le fichier ;
  - **+$1A8 := pointeur vers le WBObject** (lien arrière) ;
  - une liste vide est initialisée en **+$1AC** ;
  - **+$1BA..+$1BD = dernier long du bloc**, couvert par l'allocation et **laissé à 0**. C'est
    à nous d'y mettre le lock du répertoire (BPTR) pour qu'info.library le lise (§7.3).

**FreeWBObject(object)**
- = **FreeFreeList(objet+$8C)**. Toutes les entrées sont libérées, **y compris l'objet
  lui-même**, le DrawerData et **les chaînes et tableaux ajoutés par info.library via
  AddFreeList** (§7.3).
- **Ne fait ni UnLock ni rien d'autre** : aucun champ n'est examiné. Il n'y a rien à remettre à 0
  avant l'appel. En revanche, nous devons **UnLock nous-mêmes** les locks que nous avons posés
  (+$A4, DrawerData+$1BA), et libérer le nom de +$40 si nous l'avons alloué hors de la FreeList.
  Le plus simple est de l'allouer puis de l'enregistrer par AddFreeList(objet+$8C, …), pour qu'il
  parte avec l'objet.
- Après l'appel, l'objet n'existe plus.

**PutWBObject(name, object)**
- Reconstruit un DiskObject : magic $E310, version 1, `do_Gadget` = +$60..+$8B, `do_Type` = +$3D,
  `do_DefaultTool` = +$48, `do_ToolTypes` = +$5C, CurrentX/Y = +$54/+$58,
  `do_DrawerData` = +$4C, `do_ToolWindow` = +$9C, `do_StackSize` = +$A0.
- Appelle **PutIcon(name, DiskObject)**, qui écrit `"<name>.info"` en **MODE_NEWFILE dans le
  répertoire courant**. Contenu, dans l'ordre :
  1. l'en-tête de 78 octets ;
  2. si DrawerData : ses **56 premiers octets seulement** (la partie privée, dont +$1A8 et +$1BA,
     n'est jamais écrite) ;
  3. les images du gadget (rendu, puis sélection si présente) ;
  4. l'outil par défaut et les tool types, s'ils existent (longueur puis chaîne) ;
  5. la ToolWindow, si elle existe.
- **+$40, +$38, +$A4 ne sont pas utilisés** : le nom vient de l'argument.

**Recette pour Workbench/Info avec notre WB [D]**
1. CurrentDir(répertoire contenant l'icône), ou la racine pour un disque.
2. `obj = GetWBObject(nom)`, ou `GetWBObject("Disk")` pour un disque.
3. Remplir :
   - **+$40** := nom (alloué puis AddFreeList dans obj+$8C) ;
   - **+$A4** := lock du répertoire contenant (le plus simple : prioritaire dans info.library) ;
   - **pour un disque** : +$A4 := lock de la racine. Comme +$A4 est prioritaire (§7.3),
     info.library verrouille alors `"disk.info"` dans la racine. **Par sécurité**, poser aussi
     **+$4C → +$1BA** := lock de la racine (sans UnLock séparé, c'est le même lock) : c'est le
     repli d'info.library quand ce Lock échoue, et elle déréférence alors +$4C sans tester s'il
     est nul [O]. Une icône de disque sans DrawerData (+$4C = 0) n'est donc sûre que si
     `Disk.info` est verrouillable [D].
   - +$38 peut rester à 0 si +$A4 est posé.
4. Appeler info.library (§7.1).
5. Recharger notre DiskObject depuis le disque si SAVE a pu changer l'icône (aucun signal de retour
   ne l'indique).
6. **UnLock de nos locks** (+$A4 ; +$1BA seulement s'il s'agit d'un lock distinct), puis
   **FreeWBObject(obj)**.

### 7.9 Duplicate (menu Workbench, élément 2, code $F840)

Comme pour tout MENUPICK, le titre mémoire est d'abord restauré (§6.2). La routine Duplicate est
ensuite appelée pour **chaque icône sélectionnée** (même itérateur que Snapshot et Info) [D pour
l'ordre]. Les notations G+off et WBObject sont celles de §6.1 et §7.3.

#### 7.9.1 Disque et kick : lancement de DiskCopy [O]

- **Cas couvert** : un type dans le masque **$0082**, c'est-à-dire **disque (1)** et **kick
  (7)**. Ce n'est **pas** une copie faite par le Workbench : il lance l'**outil par défaut de
  l'icône** (`+$48`, sur le disque 1.3 en général `SYS:System/DiskCopy`).
- **Pas d'outil par défaut** : ShowTitle `"This disk cannot be copied"` (§6.9).
- **Arguments** : un tableau de WBArg de **2 entrées** (AllocMem 2 × 8, MEMF_CLEAR) :
  1. l'outil, d'après son nom ;
  2. **le disque lui-même**.
  Le glisser d'un disque sur un autre utilise la même routine avec 3 entrées : outil, source,
  destination.
- **Lancement** : même chemin qu'un lancement d'outil (LoadSeg, CreateProc, WBStartup), avec les
  mêmes messages d'erreur `"opening <outil>"` (§6.9 point 2). Rien d'autre n'est fait pour un
  disque.

**Contenu exact des WBArg [O]** (routine de construction d'un WBArg, commune au lancement
d'outils) :

| Arg | wa_Lock | wa_Name |
|---|---|---|
| 0 : l'outil, nommé par `+$48` | si le nom contient `':'` **ailleurs qu'en première position** (cas `"SYS:System/DiskCopy"`) : **0 (NULL)** ; sinon **DupLock du lock du répertoire contenant l'icône** | **copie du nom tel quel**, donc le chemin complet `"SYS:System/DiskCopy"` quand wa_Lock = NULL |
| 1 : le disque (type 1, et plus généralement un type du masque $0026 : disque, tiroir, poubelle) | **DupLock(DrawerData+$1BA)**, c'est-à-dire du **lock de la racine du volume** pris au scan (packet ACTION_LOCATE_OBJECT, §3.3). Si +$1BA est encore 0, le WB l'obtient d'abord, le duplique, puis le relâche et remet +$1BA à 0 | **chaîne vide `""`** (copie allouée) |
| (icône kick, type 7) | 0 | `"<nom du device>:"` d'après la table de scan |

Le volume est **celui de l'icône dupliquée**, pas forcément SYS:. Notre `Lock("SYS:")` n'est
équivalent que pour l'icône du disque de boot.

**Autres champs du lancement [O]**
- `CreateProc(nom = la chaîne de l'outil, pri, seglist, pile)`.
- **Pile** = `do_StackSize` de **l'icône du disque** (+$A0), ou **4096** si elle vaut 0.
- **Priorité** = ToolType `TOOLPRI` des tool types de **l'icône du disque**, ou 0 par défaut.
- WBStartup de 40 octets (MEMF_CLEAR) :
  - `mn_ReplyPort` = port A ;
  - `sm_Process`, `sm_Segment` ;
  - `sm_NumArgs = 2` ;
  - `sm_ArgList` ;
  - **`sm_ToolWindow` = 0** : aucun champ ne le remplit sur ce chemin.
- Un **rescan des disques** (§3.3) a lieu juste avant le PutMsg.
- LoadSeg se fait avec CurrentDir = répertoire de l'icône, sans effet ici puisque le chemin est
  absolu.

**DiskCopy 1.4 (`SYS:System/DiskCopy`, `$VER: diskcopy 36.6 (7.6.90)`) : traitement des WBArg [O]**

Démarrage (startup C résident) :
- Ouvre `"dos.library"` en version 0.
- En mode Workbench :
  - WaitPort/GetMsg du WBStartup ;
  - **CurrentDir(ArgList[0].wa_Lock)**, c'est-à-dire 0 ici ;
  - si `sm_ToolWindow` ≠ 0, ouverture de cette fenêtre comme console ;
  - mémorise `ArgList[0].wa_Name` comme nom de programme ;
  - appelle `main(0, WBStartup)`.

**Conditions de sortie AVANT toute fenêtre, donc « rien ne s'affiche » [O]** :
1. **`DOSBase->lib_Version` (+$14) < 33** ⇒ sortie code 10. C'est la vérification faite en tout
   premier dans main.
2. `OpenLibrary("intuition.library", 0)` ou `("graphics.library", 0)` échoue ⇒ sortie 10.
3. Échec de CreatePort, des deux CreateExtIO (52 octets, IOStdReq pour trackdisk), d'AllocMem
   (512 octets CHIP|CLEAR), de 260 octets (FIB) ou de 36 octets (InfoData) ⇒ sortie 10.
4. `OpenLibrary("icon.library", 0)` échoue ⇒ requester `"Unable to open icon.library"` (Retry
   ou abandon).
5. **OpenWindow** de sa fenêtre échoue ⇒ sortie 10.
Ensuite seulement viennent SetWindowTitles (titre d'écran `"DiskCopy"`) et la lecture des
arguments.

**Choix des disques selon `sm_NumArgs` (+$1C) [O]** :
- **2** ⇒ source = destination = **ArgList[1]** (copie sur un seul lecteur) ;
- **3** ⇒ source = ArgList[1], destination = ArgList[2] ;
- autre valeur ⇒ affichage de l'aide (« To duplicate a disk / select its icon and choose / Copy
  from the / Icons menu ») [D pour le chemin exact].

**Résolution du lecteur à partir d'un WBArg disque [O]** :
1. **`wa_Name` doit être VIDE** : s'il ne l'est pas, **sortie 10 silencieuse**.
2. **`ParentDir(wa_Lock)` doit rendre 0** : le lock doit être celui d'une **racine**. Sinon
   UnLock du parent et **sortie 10 silencieuse**.
3. Juste après, **`IoErr()` doit valoir 0**. Sinon message d'erreur (code interne $61) puis
   sortie 10. **Il faut donc que notre ParentDir sur une racine rende 0 en laissant `pr_Result2`
   à 0.**
4. **`Info(wa_Lock, InfoData)`** puis **`Examine(wa_Lock, FIB)`** doivent réussir (sinon même
   erreur).
   - Source : nom affiché = `fib_FileName` (+$08), c'est-à-dire le **nom du volume**.
   - Destination : contrôles supplémentaires `id_InUse` (+$20), avec le requester « Another
     process has destination disk open », et `id_DiskState` (+$08) = 80 (protégé en écriture).
5. **UnLock(wa_Lock)** et **mise à 0 du champ wa_Lock** dans le WBArg : DiskCopy libère
   lui-même le lock reçu.
6. **Recherche du device** :
   - tâche du volume = `InfoData.id_VolumeNode` (+$1C, BPTR) → `dol_Task` (+$08) ;
   - parcours de `DOSBase->dl_Root` (+$22) → `rn_Info` (+$18, BPTR) → `di_DevInfo` (+$04,
     BPTR) → chaîne `dn_Next` (+$00, BPTR) ;
   - pour chaque nœud **`dn_Type` (+$04) = 0** (DLT_DEVICE) dont **`dn_Task` (+$08) == la tâche
     du volume** ;
   - le nom `"<dn_Name>:"` est construit depuis `dn_Name` (+$28, BSTR), par exemple `"DF0:"`.
     C'est lui qu'on voit dans « in drive %s ».
   - Aucun nœud trouvé ⇒ erreur $61 puis sortie.
7. Ensuite :
   - **DeviceProc(nom)** (dos −174) pour la source et pour la destination ; un échec donne
     l'erreur $61 ;
   - comparaison des deux ports (même lecteur ou non) ;
   - inhibition des handlers ;
   - lecture de la géométrie dans **`dn_Startup` (+$1C) → `fssm_Environ` (+$08) → DosEnvec**
     (`de_HighCyl` +$28 − `de_LowCyl` +$24 + 1, `de_BlocksPerTrack` +$14…) ;
   - puis seulement le message « Place … ( FROM disk ) in drive %s ».

**Diagnostic pour notre ROM [D]** : DiskCopy n'affiche rien et ne laisse aucune trace. Le
coupable est donc l'une des conditions 1 à 5 d'avant la fenêtre, et **la première est le
contrôle `DOSBase->lib_Version ≥ 33`**. Si la fenêtre s'ouvre puis se ferme, regarder dans
l'ordre :
- wa_Name ≠ "" ;
- ParentDir ≠ 0 sur la racine ;
- IoErr ≠ 0 après ParentDir ;
- Info ou Examine refusé sur un lock de racine ;
- `id_VolumeNode` ou `dol_Task` incohérents avec `dn_Task` du DeviceNode ;
- DeviceProc("DF0:") en échec ;
- `dn_Startup` / `fssm_Environ` absents.

#### 7.9.2 Autres objets (tiroir, outil, projet…) : séquence complète [O sauf mention]

1. **Répertoire parent.** Le WB prend le lock du répertoire qui contient l'icône. S'il n'en a
   pas, ErrMsg(1, nom) (`"Error while accessing <nom>"`) et fin. Sinon **CurrentDir(parent)**, en
   gardant l'ancien répertoire courant.
2. **Lock de l'original** : **`Lock(nom, SHARED (−2))`**. En cas d'échec : ErrMsg(1, nom), puis
   la fin commune (étape 10).
3. **Nouveau nom** : **icon `BumpRevision` (LVO −108)** (nouveau, ancien), le nouveau nom étant
   écrit dans le **tampon global G+$5C**. Le résultat est **tronqué à 25 caractères** (l'octet
   d'indice 25 est mis à 0). Exemple : `"Expansion"` ⇒ `"copy of Expansion"`. Pour les règles
   de BumpRevision lui-même (`"copy 2 of …"` etc.), voir icon.library.
4. **Écriture du `.info` de la copie, AVANT toute copie de données** :
   - le WBObject **original** est modifié **temporairement en mémoire** :
     - `+$40` := le nouveau nom ;
     - `+$54/+$58` (CurrentX/Y) : voir §7.9.3 ;
   - puis CurrentDir(parent) et **`PutWBObject(nouveau nom, original)`** ;
   - puis `+$40`, `+$54` et `+$58` reprennent **immédiatement** leurs valeurs d'origine.
   C'est pourquoi le `.info` copié est identique à l'original sauf CurrentX/Y : PutWBObject
   n'écrit pas le nom (§7.8).
   Si PutWBObject échoue, il n'y a **ni icône ni copie des données**, et aucun message propre à
   cette étape [O ; le message éventuel dépend d'icon.library et du requester dos].
5. **Doublon d'icône** : si le tiroir parent contient déjà une icône portant le nouveau nom, elle
   est **retirée de l'affichage** avant la relecture (cas d'un ancien « copy of … »).
6. **Relecture** : CurrentDir(parent), puis **`GetWBObject(nouveau nom)`**, puis le nom est
   alloué dans `+$40`, l'objet est ajouté à la liste maîtresse G+$24 et préparé (images…).
   - En cas d'échec : ShowTitle `"Cannot read info file %s"` (nom = G+$5C), et **les données ne
     sont pas copiées**.
   - Si l'original a un lock propre en `+$A4`, la copie reçoit `DupLock` de ce lock.
   - Le bit 4 de l'octet `+$3C` de l'original est recopié sur la copie.
7. **Insertion dans le tiroir** (sans relire tout le tiroir) :
   - `+$38` := tiroir parent ;
   - si la position vaut **NO_ICON_POSITION ($80000000)**, un emplacement libre est cherché
     (balayage par pas de 96 px) ;
   - ajout à la liste des icônes du tiroir (DrawerData +$1AC), **rattachement à sa fenêtre**
     (`+$50` := DrawerData +$1A4) ;
   - calcul de la position du gadget d'après X/Y, le défilement du tiroir (DrawerData
     +$30/+$34) et les bordures de la fenêtre ;
   - puis rendu de l'icône [D pour « rendu » : appel en fin de routine].
8. **Copie des données** (§7.9.4) : du lock de l'original vers le répertoire parent, sous le
   **nouveau nom**.
9. **Recalcul du tiroir parent** : son étendue et ses barres de défilement sont recalculées
   d'après la nouvelle icône. Le tiroir n'est **pas relu** depuis le disque.
10. **Fin commune** : `UnLock(lock de l'original)`, **CurrentDir(ancien répertoire)**. Retour
    « succès » si la dernière étape a réussi.

**Sélection [O, par absence]** : Duplicate n'appelle aucune routine de sélection ou de
désélection. L'original **reste sélectionné**. La copie est créée **non sélectionnée** (objet
neuf) [D].

**Libérations [O]** : le tampon G+$5C est global (rien à libérer). Le lock de l'original est
libéré à l'étape 10. Le WBObject de la copie appartient ensuite au tiroir (il n'est pas libéré
ici). Les ressources de la copie des données sont libérées par celle-ci (§7.9.4).

#### 7.9.3 Position de la copie [O]

Le choix dépend du **bit 4 de l'octet `+$3C`** de l'original. Ce bit va de pair avec le lock
propre `+$A4` : la routine de déplacement efface les deux ensemble. Sa signification exacte
reste [S].

- **Bit 4 à 0 (cas normal, sonde Expansion)** :
  - pendant l'écriture du `.info`, **CurrentX += 30** et **CurrentY += 15** ;
  - le `.info` porte donc ces valeurs (203,0 → **233,15**), et la copie relue les reprend.
- **Bit 4 à 1** :
  - le `.info` est écrit avec **CurrentX = CurrentY = NO_ICON_POSITION ($80000000)** ;
  - **en mémoire**, la copie relue reçoit ensuite X+30 / Y+15 de l'original.

Le décalage est **constant (+30, +15)**. Il ne dépend **ni de la taille de l'icône ni de la
police**. Il n'y a ni recherche de chevauchement ni bornage.

#### 7.9.4 Copie des données (fichiers et tiroirs) [O sauf mention]

- **Coroutines.** Elle se déroule **dans le process Workbench**, avec **deux coroutines**
  (chacune a une pile de **4096 octets** allouée par AllocMem) :
  - un **lecteur**, qui parcourt la source ;
  - un **écrivain**, qui crée la destination.
  Elles se passent la main tour à tour. Un contexte de **536 octets** (MEMF_CLEAR) est alloué
  pour l'opération.
- **Pool de tampons.** Il est fait de **blocs de 526 octets** : 512 octets de données plus un
  en-tête.
  - Le WB alloue autant de blocs que la mémoire le permet, jusqu'à **limite + 30** :
    - limite **40** si la source et la destination sont servies par **deux handlers
      différents** ;
    - sinon une valeur liée à l'entrée disque de la source dans la table de scan [S sur sa
      signification].
  - Il **rend ensuite 50 blocs** au système (ou tous, s'il en a moins de 50).
  - S'il reste **moins de 10 blocs** : ShowTitle `"Ran out of memory.  Please free some and try
    again."` et abandon de la copie. Le `.info` a déjà été écrit et l'icône est déjà affichée.
  - En fin d'opération, tous les blocs, les deux piles et le contexte sont libérés.
- **Flux.** Le lecteur parcourt l'objet récursivement (Examine/ExNext, §6.9 point 6). Il émet,
  pour chaque entrée, un **enregistrement** (en-tête de 28 octets, marqueur $FE12) contenant :
  - le type (fichier ou répertoire) ;
  - la taille ;
  - `fib_Protection` ;
  - `fib_Date` ;
  - le nom ;
  - **le commentaire** ;
  - puis, pour un fichier, les données par **morceaux de 512 octets** (Read de min(reste, 512)).
  **Au niveau 0** (l'objet dupliqué lui-même), le nom émis est **BumpRevision(nom)**, tronqué à
  25 caractères comme pour le `.info`.
- **Écrivain** :
  - fichier : `Open(nom, MODE_NEWFILE)`, Write des morceaux, Close ;
  - répertoire : `Lock(nom)`, puis **CreateDir** si IoErr = 205, puis UnLock. La descente se fait
    par CurrentDir.
- **Attributs** : l'écrivain lit protection, date et commentaire dans le flux **mais ne les
  applique pas**. Le module n'a **aucun** vecteur SetProtection, SetComment ni date de fichier
  parmi ses appels dos (§3.6). Les fichiers copiés ont donc la **date courante**, la **protection
  par défaut** et **aucun commentaire** [O par absence de ces LVO].
- **Pas de `.info`** : sans WBObject, un objet n'est pas affiché par le WB 1.3, donc Duplicate ne
  peut pas viser un fichier sans icône. À l'intérieur d'un tiroir copié, les fichiers sans `.info`
  sont copiés comme les autres : le parcours copie **toutes** les entrées, `.info` compris, sans
  distinction [O].
- **Erreurs** : celles de §6.9 point 6 (`"accessing"`, `"opening"`, `"reading"`, `"writing"`).
  La première erreur arrête la copie. Ce qui a déjà été créé est **laissé en place**.

#### 7.9.5 Mémoire insuffisante [O]

| Où | Message | Nettoyage |
|---|---|---|
| Tableau WBArg (Duplicate d'un disque) | `"Ran out of memory.  Please free some and try again."` | rien n'est lancé |
| Contexte de 536 octets ou pile d'une coroutine (copie des données) | **aucun message** | ce qui a été alloué est libéré ; `.info` et icône de la copie restent, données non copiées |
| Pool de moins de 10 blocs | même message | blocs, piles et contexte libérés ; `.info` et icône restent |
| GetWBObject de la copie (allocation dans icon.library) | `"Cannot read info file copy of …"` | pas de copie des données ; `.info` présent, **icône absente** jusqu'au prochain rescan |

---

## 8. Fenêtres de tiroir : gadgets de défilement et jauge

Notations : W, H = taille de la fenêtre ; BL/BT/BR/BB = ses bordures ; DD = DrawerData de
l'objet (`+$4C`). Les règles de rendu intuition sont dans `intuition-prop-v34.md` et
`intuition-frame-v34.md`.

### 8.1 Fenêtre et liste de gadgets [O]

- **Flags** passés à l'ouverture d'un tiroir ou d'un disque : **$0240027F**. Cela comprend
  SIZING, DRAG, DEPTH, CLOSE, **SIZEBRIGHT, SIZEBBOTTOM**, SIMPLE_REFRESH, REPORTMOUSE,
  WBENCHWINDOW, plus un bit $00400000 : **sans effet** (intuition 34.3 ne le teste jamais dans
  `Window->Flags` ; c'est la valeur d'INTUITICKS ; la réouverture d'un tiroir dont le DrawerData
  existe passe $0200027F, cf. `wb-icon-clipping-v34.md` §7) [O]. Découpage des icônes, effacement
  et défilement : `wb-icon-clipping-v34.md`.
- **Six gadgets**, copiés depuis des modèles ROM dans le DrawerData et chaînés **dans cet
  ordre** :

| # | Gadget (GadgetID) | Copie dans DD | LeftEdge, TopEdge, Width, Height | Flags | Activation | Type |
|---|---|---|---|---|---|---|
| 1 | barre verticale (2) | +$74 | −15, 16, 16, −31 | GRELRIGHT \| GRELHEIGHT \| GADGIMAGE ($0054) | RELVERIFY \| GADGIMMEDIATE \| RIGHTBORDER ($0013) | PROPGADGET (3) |
| 2 | barre horizontale (1) | +$48 | 13, −8, −40, 9 | GRELBOTTOM \| GRELWIDTH \| GADGIMAGE ($002C) | RELVERIFY \| GADGIMMEDIATE \| BOTTOMBORDER ($0083) | PROPGADGET |
| 3 | flèche gauche (3) | +$F8 | 2, −7, 12, 7 | GRELBOTTOM \| GADGIMAGE ($000C) | $0083 | BOOLGADGET (1) |
| 4 | flèche droite (4) | +$124 | −25, −7, 12, 7 | GRELBOTTOM \| GRELRIGHT \| GADGIMAGE ($001C) | $0083 | BOOLGADGET |
| 5 | flèche haut (5) | +$A0 | −14, 10, 14, 6 | GRELRIGHT \| GADGIMAGE ($0014) | RELVERIFY \| GADGIMMEDIATE \| RIGHTBORDER ($0013) | BOOLGADGET |
| 6 | flèche bas (6) | +$CC | −14, −14, 14, 6 | GRELBOTTOM \| GRELRIGHT \| GADGIMAGE ($001C) | $0013 | BOOLGADGET |

- **Surbrillance** : mode 0, c'est-à-dire **GADGHCOMP**, sans SelectRender.
- **Barres** : GadgetRender = une `struct Image` vide du DD (+$164 pour la verticale, +$150 pour
  l'horizontale), qu'intuition remplit (AUTOKNOB). SpecialInfo = un PropInfo du DD (+$18E
  verticale, +$178 horizontale).
- **PropInfo initiale** (modèle ROM commun) :
  - Flags = **AUTOKNOB** ;
  - Pots = 0 ;
  - Bodies = **$FFFF** ;
  - le reste à 0.
  Puis **FREEVERT** est ajouté à la verticale et **FREEHORIZ** à l'horizontale.
- **Flèches** : GadgetRender = 4 Images globales, préparées une fois au démarrage dans des
  globales du WB (images copiées en mémoire CHIP). Chacune est à **1 plan utile** :
  - PlanePick = 1, PlaneOnOff = 0 ;
  - pixels allumés = **stylo 1** (fond blanc), pixels éteints = **stylo 0** (dessin bleu).
- **Géométrie des flèches** (à redessiner librement) :
  - **gauche** : image 14×8, décalée de (−2, −1) par rapport au gadget. Pointe en chevron « < »
    vers la gauche, traits diagonaux de 3 pixels de large, avec une **hampe horizontale** sur la
    ligne du milieu (y = 4) qui va de la pointe au bord droit ;
  - **droite** : image 12×8, décalée de (−1, −1). Miroir de la gauche : chevron « > », hampe vers
    la gauche ;
  - **haut** : image 16×6, décalée de (−1, 0). Chevron « ^ » en traits de 2 pixels, avec une
    **hampe verticale de 2 pixels** au centre (colonnes 7–8) qui descend jusqu'en bas ;
  - **bas** : 16×6, décalée de (−1, 0). Miroir vertical : « v » avec hampe montante.
- **Bordures qui en résultent** (§1.2 d'`intuition-gzz-v34.md`) [D] :
  - BR = max(gadget de taille + 2, gadgets RIGHTBORDER) ;
  - BB = max(gadget de taille + 1, gadgets BOTTOMBORDER).
  - En hires, cela donne une bordure droite de 18 et une bordure basse de 10 environ.

### 8.2 Zone de contenu et étendue [O]

- **Origine du contenu** :
  - gauche = BL, **plus 14 pour une fenêtre de disque** (la place de la jauge, §8.4) ;
  - largeur visible = W − origine gauche − BR ;
  - hauteur visible = H − BT − BB.
- **DrawerData** :
  - +$30 / +$34 = position de défilement (X / Y) ;
  - +$38 / +$3C = minimum de l'étendue ;
  - +$40 / +$44 = maximum de l'étendue.
- **Recalcul de l'étendue**, à l'ouverture, après Duplicate ou après une insertion d'icône
  (§7.9.2 point 9), et après chaque défilement :
  - le minimum vaut la position courante, le maximum vaut position + taille visible ;
  - puis l'étendue est **élargie à la boîte de chaque icône** du tiroir.
  - La fenêtre racine (backdrop) n'a pas de barres : aucune mise à jour.

### 8.3 Body / Pot et défilement [O]

**Calcul**, en flottant mathffp, pour chaque axe, avec plage = max − min et pos = max(0,
courant − min) :
- **Body = Fix(65535 × visible / plage)** ;
- **Pot** = **$7FFF** si plage = visible ; sinon **Fix(65535 × pos / (plage − visible))**.
- Si Body ou Pot ont changé : **NewModifyProp(gadget, fenêtre, NULL, Flags inchangés, Pot, Pot,
  Body, Body, 1)**. Les mêmes valeurs vont dans H et V ; seul l'axe libre compte. Un seul gadget
  est redessiné.

**Défilement** :
- **GADGETDOWN** sur un des 6 gadgets : le WB note la fenêtre et le gadget.
  - Sur une **flèche sans Shift** : il ajoute **INTUITICKS** à l'IDCMP de la fenêtre, pour la
    répétition.
  - Sur une **barre**, ou une **flèche avec Shift** (qualifier & 3) : mode « un coup ».
- **Pas par événement** (INTUITICKS ou MOUSEMOVE pendant l'appui) :
  - **flèche gauche / droite** : X −= / += **largeur visible / 8** (Shift : **±1 pixel**) ;
  - **flèche haut / bas** : Y −= / += **hauteur visible / 8** (Shift : **±1 pixel**) ;
  - **barre horizontale** : X = Fix(HorizPot / 65535 × (plage X − visible X)) + min X ;
  - **barre verticale** : Y = même formule avec VertPot.
  - Si la valeur ne change pas, rien n'est fait.
- **Après chaque changement** : nouvelle position dans DD +$30 / +$34, puis recalcul de
  l'étendue et des barres (ci-dessus), puis défilement et réaffichage du contenu.
- **GADGETUP** : fin du défilement. Le drapeau est effacé et INTUITICKS est retiré de l'IDCMP
  s'il avait été ajouté.

### 8.4 Jauge de remplissage (fenêtres de disque) [O]

**Emplacement** : dessinée dans le RastPort de la fenêtre, contre le bord gauche, de **x = 2 à
x = BL + 9**. Le contenu commence à BL + 14.

**Cadre** :
- **bloc du haut** : RectFill en **stylo 2** de (2, BT−1) à (BL+9, BT+5), avec un **« F »**
  tracé au trait (Move/Draw) en **stylo 1** : barre du haut, montant de 2 pixels à gauche,
  barre du milieu plus courte ;
- **bloc du bas** : RectFill en stylo 2 de (2, H−BB−6) à (BL+9, H−BB), avec un **« E »** en
  stylo 1 (montant de 2 pixels, trois barres) ;
- **filet** : RectFill en **stylo 1** de (BL+10, BT−1) à (BL+11, H−BB), à droite de la jauge
  sur toute la hauteur.

**Barre**, entre y0 = BT + 6 et y1 = H − BB − 7 (hauteur h = y1 − y0) :
- **rempli = Fix(utilisés × h / total + 0,5)**, arrondi, avec utilisés = `id_NumBlocksUsed` et
  total = `id_NumBlocks` de l'InfoData du volume ;
- partie vide (en haut) : RectFill **stylo 2** de (2, y0) à (BL+9, y0 + h − rempli) ;
- partie remplie (en bas) : RectFill **stylo 3** de (2, y0 + h − rempli) à (BL+9, y1).
- Un trait au stylo 2 puis au stylo 1 marque la ligne y = H − BB, sous la jauge.

**Mise à jour** :
- à l'ouverture de la fenêtre du disque ;
- quand l'InfoData du volume est relu (Info, par exemple après écriture ou au rescan) [D pour la
  liste exacte].
- Rien n'est dessiné si le Workbench est « fermé » (bit 0 de G+$22) ou si la fenêtre n'est pas
  ouverte.

---

## Relecture clean-room

- [x] Aucun listing, aucune suite d'instructions transcrite ni paraphrasée ligne à ligne : seuls des
  **layouts** (ROMTag, message LoadWB, MsgPort, NewWindow, WBStartup,
  DosPacket), des **constantes** (codes d'Alert, flags de fenêtre, IDCMP, n° d'action dos, tailles)
  et des **séquences d'appels de librairie** (contrat d'API public) sont donnés.
- [x] §1.2/§1.3 décrivent l'**effet** des 8 octets d'entrée (sélecteur, OU sur D0) et la contrainte
  d'ABI qui en découle (D0 = 0 à l'entrée d'un process C), pas leur encodage : la piste
  implémentation n'a pas à les reproduire (son propre module workbench.task peut avoir n'importe
  quelle forme, tant que `(tag+42)>>2` donne un segment exécutable correct — par exemple placer son
  ROMTag à une adresse ≡ 2 mod 4 n'est **pas** requis ; il suffit que `BADDR((tag+42)>>2)+4` soit un
  point d'entrée valide).
- [x] **Correction du 2026-10-29** : retirées les 47 adresses ROM restantes (ROMTag, `rt_Name`,
  `rt_IdString`, `rt_Init`, `rt_EndSkip`, points d'entrée, `main`, boucle principale, routines
  d'abandon, d'affichage de titre et d'Info, colonne « Repère » du §3.1, AddTask d'exec, chaîne
  « Workbench ») et la description de l'encodage des points d'entrée (« bourrage », opération sur
  D0) ; conservés : positions relatives au tag imposées par `c:LoadWB` (+26/+34/+42/+44) et effet
  observable (sélecteur, `D0 := D0 OU 2`).
- [x] Les noms de LVO au-delà des AutoDocs 1.3 (−426…−468 intuition, −504…−534 graphics) sont
  déduits de l'ordre des fichiers `.fd` publics et marqués [D].
- [x] Les éléments disque (LoadWB) sont limités à l'interface (message, seglist, SetFunction) déjà
  connue de la piste implémentation.
- [x] Correction signalée de `boot-sequence.md` (strap ne lance pas workbench.task).
- [x] §6 (relu) : uniquement des chaînes, des offsets de globales/structures publiques
  (lib_Version +$14, lib_Revision +$16, en-tête ROM +$0C/+$0E), des appels de librairie
  (RawDoFmt, DisplayBeep, SetWindowTitles, OpenLibrary/CloseLibrary, AvailMem, IoErr, SetFunction)
  et des règles de comportement (drapeaux, conditions d'affichage). Le patch LoadWB est décrit par
  son **effet** sur la chaîne (comparaison de préfixe, octets réécrits, substitution de pointeur)
  et la transformation XOR $9E des chaînes — aucune suite d'instructions recopiée. La §3.4 reste
  valable ; §6.4 la précise (bit 2, G+$2F2 = −1 initial).
- [x] §6.8 (relu) : règles d'activation décrites par leur effet (champs publics Window/Screen/
  IntuitionBase, conditions, ordre de repli Parent → FirstWindow → NULL), aucune séquence
  d'instructions d'intuition ni du workbench recopiée.
- [x] §6.9 (relu) : table « opération utilisateur → appel dos qui échoue → message », avec index
  d'action, argument `%s`, codes tolérés (205, 232), packets dos (17, 9) et règles de requester.
  Aucune séquence d'instructions transcrite.
- [x] §7 (relu) : info.library est décrite par son contrat d'appel (registres, LVO), les champs du
  WBObject lus et écrits (offset et sens), les appels de librairie et les chaînes affichées.
  Aucune séquence d'instructions de la librairie ni du Workbench n'est recopiée.
- [x] §7.8 (relu) : icon.library est décrite par sa table de LVO, ses tailles d'allocation, sa
  correspondance champ DiskObject → offset WBObject et le contenu écrit dans le `.info`. Aucune
  séquence d'instructions recopiée.
- [x] §7.9 (relu) : Duplicate est décrit par des règles (ordre des appels publics dos et icon,
  décalage +30/+15, tailles des tampons, attributs non copiés, messages). Aucune suite
  d'instructions recopiée.
- [x] §7.9.1, complément DiskCopy (relu) : contenu des WBArg, champs du lancement et
  conditions de sortie de DiskCopy, décrits par des règles et des champs dos publics. Aucune suite
  d'instructions recopiée.
- [x] §8 (relu) : gadgets, PropInfo, formules Body/Pot et jauge décrits par règles, champs publics
  et géométrie. Les images des flèches et les lettres F/E sont décrites en forme, pas en bitmap.
  Aucune suite d'instructions recopiée. Complément à §7.9.3 [O] : le bit 4 de `+$3C` est posé
  quand une icône est déposée sur la fenêtre racine (backdrop), avec un DupLock du répertoire
  d'origine dans `+$A4` ; il est effacé quand elle est remise dans un tiroir.
