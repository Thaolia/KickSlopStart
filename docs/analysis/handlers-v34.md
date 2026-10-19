# handlers-v34.md — DosList initiale, démarrage des handlers, globales « fichier » (dos V34)

> Piste ANALYSE (« dirty »). Sources : la ROM `assets/kick34005.A500` (dos 34.3) et, sur le disque
> `assets/wb133.adf` (Workbench 1.3.3), `c:MakeDir`, `c:Assign`, `c:Delete`, `c:Rename`,
> `l:Ram-Handler`, `l:Newcon-Handler`, `l:Aux-Handler`, `l:Port-Handler` (extraits en scratch).
> Complète `bcpl-runtime-v34.md` (§2, §8, §13) — mêmes conventions : **BPTR** = adresse/4,
> **BSTR** = BPTR d'une chaîne à octet de longueur, **taskid** = adresse (APTR) du MsgPort d'un
> process (process+$5C), « R2 » = `pr_Result2`.
>
> **Légende** : **[O]** observé directement · **[D]** déduit d'observations convergentes ·
> **[S]** supposé. Les adresses ROM ne sont que des repères pour la piste analyse.
>
> Ce document décrit des comportements, des layouts d'ABI et des constantes. **Aucune suite
> d'instructions n'est reproduite ni paraphrasée.**

Layout DeviceNode (rappel, en longs) : `!0` dn_Next · `!1` dn_Type · `!2` dn_Task · `!3` dn_Lock ·
`!4` dn_Handler · `!5` dn_StackSize · `!6` dn_Priority · `!7` dn_Startup · `!8` dn_SegList ·
`!9` dn_GlobalVec · `!10` dn_Name. Pour un **volume** (dn_Type 2) les mêmes slots valent :
`!3` dl_Lock · `!4..!6` dl_VolumeDate · `!7` dl_LockList · `!8` dl_DiskType · `!9` inutilisé.
FileLock : `+$00` fl_Link · `+$04` fl_Key · `+$08` fl_Access · **`+$0C` fl_Task** · `+$10` fl_Volume. [O par usage]

---

## 0. Résumé exécutable

1. **Ce n'est pas l'init de dos (rt_Init) qui peuple la DosList, c'est `cliinit` (globale 133)**,
   exécutée dans le process « Initial CLI ». [O/D]
2. Nœuds créés par la ROM, dans cet ordre (chaque création insère **en tête**) : **DF0**, puis
   **RAM, CON, RAW, SER, PAR, PRT** (devices, dn_Type 0, dn_Task 0), puis les assigns
   **SYS, LIBS, DEVS, FONTS, C, L, S** (dn_Type 1), puis **DF1..DF3** seulement si leur handler
   démarre. Valeurs exactes en §1.2. [O]
3. **CON:/RAW:** = console-handler ROM (segarray entrée 5) via `dn_SegList` déjà renseigné, GV
   **partagé** (`dn_GlobalVec` = BPTR du GV de l'Initial CLI), pile 700 longs, pri 5, Startup 0
   (CON) / 1 (RAW). Démarrage par la **globale 112** standard ; personne n'écrit dn_Task ⇒ **un
   process + une fenêtre par Open**. [O]
4. **RAM:** = `L:RAM-HANDLER` chargé du disque au premier deviceproc, **GV neuf** (makeglobvec),
   pile 300 longs, pri 0. Le handler écrit **lui-même** dn_Task, **efface dn_Handler..dn_GlobalVec**
   de son nœud et crée un nœud **volume « RAM DISK »**. [O WB]
5. Le handler doit répondre au packet de démarrage avec **Res1 ≠ 0** (succès) ; Res2 n'est pas
   interprété par dos en cas de succès. dos n'écrit dn_Task **que** pour les file systems qu'il
   lance lui-même depuis cliinit (DFx), jamais via la globale 112. [O]
6. Toutes les globales « objet » (locateobj 108, deleteobj 90, createdir 125, setcomment/protect)
   passent par une routine commune : `deviceproc(nom)` → port + lock (Result2) ⇒ packet
   **Arg1 = lock, Arg2 = BSTR du nom COMPLET** (préfixe `xxx:` compris), Arg3 = paramètre. [O]

---

## 1. Q1 — Nœuds de la DosList créés par la ROM

### 1.1 Où et dans quel ordre [O ROM]

- **rt_Init de dos** ($FF3E94) ne crée aucun DeviceNode. Il crée le process « Initial CLI »
  puis ouvre `expansion.library` et parcourt `eb_MountList` (ExpansionBase+$4A) : il **chaîne**
  entre eux (dn_Next, BPTR) les DeviceNodes des BootNodes (`bn_DeviceNode`, BootNode+$10), retire
  le premier BootNode de la liste (RemHead) et range **l'APTR de son DeviceNode dans
  `rn_FileHandlerSegment`** (RootNode+$1C) **temporairement**. Sur un A500 sans carte autoboot la
  liste est vide ⇒ ce champ vaut 0. [O pour les accès, D pour la sémantique BootNode]
- **cliinit** (globale 133, segarray ROM entrée 3, code à partir de $FF82DC), exécutée par
  l'Initial CLI [D : start(pkt=0) → GV[133], cf. bcpl-runtime §13.5], fait dans l'ordre :
  1. alloue rn_TaskArray (20 entrées), DosInfo (effacé ⇒ di_DevInfo = 0), les range dans le
     RootNode ; lit l'ancienne valeur de RootNode+$1C (APTR → BPTR) puis y écrit le **vrai**
     `rn_FileHandlerSegment` = segarray ROM `V!6` (file system) ; `rn_ConsoleSegment` = `V!4` ;
     plus tard `rn_RestartSeg` (RootNode+$14) = `V!7` (validateur) ;
  2. **si aucun DeviceNode d'expansion** : crée **DF0** (§1.2) ; sinon la chaîne d'expansion sert
     de tête de liste (et l'octet de longueur du BSTR `fssm_Device` de chaque nœud d'expansion est
     **incrémenté de 1** avant démarrage [O ; raison S : inclure le NUL final]) ;
     `di_DevInfo` := ce nœud de tête ;
  3. crée **RAM, CON, RAW, SER, PAR, PRT** (routine locale, repère $FF8C20) ;
  4. ouvre `intuition.library` (rangée en **GV[92]**, utilisée par la globale 50) ;
  5. **démarre le handler du nœud de tête** (DF0) par la routine FS de cliinit (§1.3), et
     `pr_FileSystemTask` de l'Initial CLI := son port ;
  6. crée les assigns **SYS** (lock de `":"`), **LIBS, DEVS, FONTS, C, L, S** (lock du répertoire
     de même nom, relatif au répertoire courant = racine du volume de boot [D]) ;
  7. démarre le handler des autres nœuds d'expansion éventuels ;
  8. pour **unité = 0..3** : saute l'unité si le nœud de tête a la même unité **et**
     `fssm_Device` = `"trackdisk.device"` ; sinon crée `DF<n>` et démarre son FS ; **si le
     démarrage échoue** (Res1 = 0, lecteur absent) : le nœud (alors en tête) est **retiré** de
     di_DevInfo, FSSM et nœud libérés (freevec ; la copie du nom n'est pas libérée) ;
  9. crée les segments résidents « CLI », « Restart », « FileHandler » (liste DosInfo+$10, hors
     sujet ici).

Liste finale sur A500 nu, de la tête vers la queue : `[DF3] [DF2] DF1 → S → L → C → FONTS →
DEVS → LIBS → SYS → PRT → PAR → SER → RAW → CON → RAM → DF0`, puis le **volume** du disque de
boot est ajouté plus tard par le file system (et « RAM DISK » par le RAM-handler, §5). [D de l'ordre
d'insertion en tête, O pour chaque insertion]

Aucun nœud **NIL:** (traité comme cas spécial par deviceproc et findinput/findoutput). [O]

### 1.2 Valeurs exactes des nœuds ROM [O ROM]

Tous sont créés par **makedevnode** (globale 85) puis complétés. Noms en majuscules.

| Nom | dn_Type | dn_Task | dn_Lock | dn_Handler | dn_StackSize | dn_Priority | dn_Startup | dn_SegList | dn_GlobalVec |
|---|---|---|---|---|---|---|---|---|---|
| DF0 (DF1–3) | 0 | **port du process FS** (écrit par cliinit après réponse) | 0 | 0 | 0 | 0 | BPTR FSSM | **0** | **non initialisé** |
| RAM | 0 | 0 | 0 | BSTR `"L:RAM-HANDLER"` | **300** (longs) | 0 | 0 | 0 | **0** (⇒ makeglobvec) |
| CON | 0 | 0 | 0 | 0 | **700** (longs) | **5** | **0** | segarray ROM **V!5** (console-handler) | **BPTR du GV de l'Initial CLI** (= dl_GV [D]) |
| RAW | 0 | 0 | 0 | 0 | 700 | 5 | **1** | V!5 | idem CON |
| SER | 0 | 0 | 0 | BSTR `"L:PORT-HANDLER"` | **800** | 0 | **0** | 0 | GV Initial CLI |
| PAR | 0 | 0 | 0 | `"L:PORT-HANDLER"` | **800** | 0 | **1** | 0 | GV Initial CLI |
| PRT | 0 | 0 | 0 | `"L:PORT-HANDLER"` | **1000** | 0 | **2** | 0 | GV Initial CLI |
| SYS | **1** | pr_FileSystemTask | locateobj(`":"`) | 0 | 0 | 0 | 0 | 0 | non init. |
| LIBS, DEVS, FONTS, C, L, S | **1** | pr_FileSystemTask | locateobj(nom) (**peut valoir 0** si le répertoire manque : le nœud est créé quand même) | 0 | 0 | 0 | 0 | 0 | non init. |

- Unité de dn_StackSize : **longs** pour tous les nœuds BCPL ci-dessus (cf. §13.3 de la spec :
  octets seulement si dn_GlobalVec = −1). [O]
- **Correction de `dos-boot-sequence.md`** : le nœud DF0 ROM n'a **pas** `dn_SegList =
  rn_FileHandlerSegment` ni `dn_Handler = "File System"`. `"File System"` est le **nom du
  process** FS ; dn_SegList reste **0** et le segment FS est pris directement dans le segarray. [O]
- **FileSysStartupMsg de DF<n>** (getmem 4 longs effacés) : fssm_Unit = n, fssm_Device = BSTR
  `"trackdisk.device"` (texte suivi d'un NUL), fssm_Environ = BPTR d'une table ROM ($FF8970),
  fssm_Flags = 0. Table d'environnement (13 longs) :
  `TableSize 12, SizeBlock 128, SecOrg 0, Surfaces 2, SectorPerBlock 1, BlocksPerTrack 11,
  Reserved 2, PreAlloc 11, Interleave 0, LowCyl 0, HighCyl 79, NumBuffers 5, BufMemType 3`. [O]
- Le nom `DFX` (BSTR ROM `{3,'D','F','X'}`) est copié par makedevnode puis le 3e caractère de la
  **copie** est remplacé par `'0'+unité`. [O]

### 1.3 Démarrage d'un file system par cliinit (≠ globale 112) [O ROM]

Routine locale de cliinit (repère $FF89A8), arguments : nœud, segarray de base, segarray ROM.
- Segarray neuf `getvec(4)` = `[3, V!1, V!2, V!6 ROM (FS)]`.
- **dn_SegList = 0** (cas DF0 ROM) : GV := **makeglobvec(segarray)** (dn_GlobalVec ignoré) ;
  `createproc(segarray, **210 longs**, **pri 10**, BSTR **"File System"**, GV)`.
- **dn_SegList ≠ 0** (nœud d'expansion) : pile = dn_StackSize (si ≤ 0 → 210) ; dn_GlobalVec = −1 ⇒
  CreateProc C (nom = dn_Name en chaîne C, pri dn_Priority, seglist, pile en octets) ; sinon
  segarray `V!3` := dn_SegList, GV = dn_GlobalVec ou makeglobvec si 0, `createproc(…, dn_StackSize,
  dn_Priority, dn_Name, GV)`.
- Packet de démarrage (sendpkt synchrone) : **Res2 = GV**, **Arg1 = non initialisé** (résidu de
  frame), **Arg2 = dn_Startup** (FSSM), **Arg3 = 0**. Type/Res1 non initialisés.
- Res1 ≠ 0 ⇒ **dn_Type := 0, dn_Task := port du FS, dn_Lock := 0** (dos écrit dn_Task) et renvoie
  le port ; Res1 = 0 ⇒ renvoie 0 (dn_Task reste 0).

---

## 2. Q2 — Démarrage de CON: / RAW:

- **Chemin standard** : open → deviceproc (102) → nœud CON, type 0, dn_Lock 0, dn_Task 0 →
  **globale 112** (starthandler). Pas de chemin spécial. [O]
- dn_SegList ≠ 0 ⇒ pas de chargement ; dn_GlobalVec = BPTR(GV Initial CLI) ⇒ branche BCPL avec
  **GV partagé** : segarray `[3, V!1, V!2 du process appelant, V!5]`, `createproc(…, 700 longs,
  pri 5, BSTR "CON"/"RAW", GV partagé)`. Le process fait globin de noyau + dos + console-handler
  **dans ce GV partagé** (le console-handler ne définit que la globale 1). [O]
- **Packet de démarrage** (§3.1) : Arg1 = **BSTR complet passé à deviceproc** (ex.
  `"CON:0/0/640/200/AmigaDOS"`), Arg2 = dn_Startup (**0 = CON, 1 = RAW**), Arg3 = BPTR du nœud,
  Res2 = GV. [O]
- **Côté console-handler ROM** (G1 à $FF9C24) [O] : lit dp_Port, Arg1, Arg2 ; **ne lit pas Arg3**
  et **n'écrit jamais dn_Task** ⇒ chaque deviceproc("CON:…") relance un process, **une fenêtre
  par Open**. Arg2 ≠ 0 ⇒ mode RAW ; Arg2 < 0 ⇒ Arg1 est utilisé tel quel comme fenêtre existante
  [O pour le test, D pour le sens]. Analyse du nom : 4 champs décimaux séparés par `/` à partir du
  **5e caractère** (indice 5 du BSTR, donc après un préfixe de 4 caractères `CON:`/`RAW:`), puis le
  titre (reste). Ouverture de la fenêtre par la **globale 50** (§3.4), puis opendevice
  `"console.device"`. Échec (syntaxe, fenêtre, device) ⇒ **returnpkt(pkt, 0, 206)**
  (ERROR_BAD_STREAM_NAME). Succès ⇒ **returnpkt(pkt, −1, ·)** (Res2 non significatif), puis boucle
  taskwait. Packet inconnu ⇒ Res2 = 209. Une requête d'info disque renvoie id_DiskType
  `'CON\0'` ou `'RAW\0'` et id_VolumeNode = la fenêtre [O pour les valeurs, D pour le type de packet].
- `l:Newcon-Handler` et `l:Aux-Handler` se comportent pareil au démarrage (lisent dp_Port, Arg1,
  Arg2, pas Arg3). [O WB]

---

## 3. Q3 — Contrat du packet de démarrage côté handler BCPL

### 3.1 Ce que dos envoie (globale 112) [O ROM]

| Champ DosPacket | Valeur |
|---|---|
| dp_Link, dp_Type, dp_Res1 | **non initialisés** (résidus de frame) — ne pas interpréter |
| dp_Port | port de réponse (le process appelant, posé par qpkt) |
| dp_Res2 | **BPTR du GV** du handler (branche BCPL) ; résidu en branche C |
| dp_Arg1 | BSTR **complet** du nom donné à deviceproc |
| dp_Arg2 | dn_Startup |
| dp_Arg3 | BPTR du DeviceNode |

### 3.2 Ce que le handler doit faire [O ROM + WB]
- Répondre par **returnpkt** (globale 49) : **Res1 ≠ 0** = succès (tous les handlers observés
  renvoient **−1**) ; **Res1 = 0** = échec, Res2 = code d'erreur (console 206, Port-Handler 202).
- Sur succès, starthandler fait **Result2 := dn_Lock** et renvoie le port ; sur échec renvoie 0
  et Result2 = Res2 du handler (posé par sendpkt). Res2 d'un succès n'est **pas** lu.
- **dn_Task n'est jamais écrit par starthandler.** Un handler qui veut être partagé l'écrit
  lui-même via Arg3 :
  - **Ram-Handler** : dn_Task := taskid(), puis **efface `!4..!9`** (dn_Handler, dn_StackSize,
    dn_Priority, dn_Startup, dn_SegList, dn_GlobalVec) de son nœud. [O WB]
  - **Port-Handler** (SER/PAR/PRT) : dn_Task := taskid() **après** succès d'opendevice, et le remet
    à **0** quand plus aucun flux n'est ouvert (puis se termine [S]). Arg2 choisit le device :
    0 `"serial.device"`, 1 `"parallel.device"`, autre `"printer.device"`. [O WB]
  - console-handler ROM, Newcon, Aux : ne l'écrivent pas (un process par Open). [O]

### 3.3 Globales reçues par le handler [O ROM]
- **dn_GlobalVec > 0** (ni 0 ni −1) : le GV indiqué est **partagé** (CON/RAW/SER/PAR/PRT, NEWCON
  monté) ; globin de V!1, V!2 et du handler y écrit leurs globales (dont la globale 1).
- **dn_GlobalVec = 0** : GV **neuf** par makeglobvec (RAM, DFx). Toutes les globales du runtime
  sont réinstallées par globin des segments V!1..V!3 ; les slots non définis restent **non
  initialisés** (pas de marqueur $474C…).
- Dans les deux cas la valeur est aussi transmise en **dp_Res2** du packet de démarrage.

### 3.4 makeglobvec(segarray) — globale 13 ($FF6D90) [O ROM]
- Parcourt les entrées `1..V!0` du segarray ; pour chaque **chaîne** de segments, lit le dernier
  long de chaque segment (« max », §3.1 de la spec BCPL). `max` = le plus grand, **plancher 15**.
- `getvec(max + 50)` ; échec ⇒ renvoie 0 (R2 = 103 laissé par getvec).
- Slot 0 = début + 50 longs ; **GV[0] := max** ; aucun autre slot écrit (ni positifs ni négatifs).
- Renvoie le **BPTR du slot 0**.

### 3.5 starthandler — globale 112 ($FF5EB0) : précisions [O ROM]
Complète §13.3 de la spec (qui reste exacte) :
- le segarray est construit à partir du `findsegarray()` **du process appelant** (entrées 1 et 2) ;
- branche C : CreateProc(nom C = BADDR(dn_Name)+1, dn_Priority, dn_SegList, **dn_StackSize octets**) ;
  aucun segarray n'est alloué (sa libération en cas d'échec porte sur 0) ;
- branche BCPL : si makeglobvec échoue ⇒ pas de createproc ⇒ échec ;
- Result2 := dn_Lock est posé **avant** l'envoi du packet puis de nouveau après une réponse Res1 ≠ 0.

### 3.6 Autres globales du runtime utilisées par les handlers
| Gl. | Adresse | Nom | Contrat observé | Cert. |
|---|---|---|---|---|
| 6 | $FF4506 | setio(iob, cmd, data, len, off) | iob BPTR ; io_Command (+$1C, **mot**) := cmd ; io_Data (+$28) := **data×4** (data est un BPTR) ; io_Length (+$24) := len ; io_Offset (+$2C) := 5e arg | O |
| 21 | $FF55D0 | **doio(iob)** | exec DoIO sur BADDR(iob) ; renvoie **io_Error** (octet +$1F, non signé) | O |
| 22 | $FF4520 | sendio(iob, pkt) | iob.ln_Name (+$0A) := APTR(pkt) ; pkt.dp_Link := APTR(iob) ; exec SendIO. La réponse arrive sur le port du process ⇒ **taskwait renvoie alors ce pkt** (lien par ln_Name) | O / D pour l'usage |
| 31 | $FF44B4 | opendevice(iob, nom, unité, flags) | nom = BSTR **dont le texte doit être suivi d'un NUL** (passé à OpenDevice en BADDR+1) ; avant l'appel : ln_Succ/ln_Pred := 0, **ln_Name := nom (chaîne C)**, mn_ReplyPort := port du process, mn_Length := 12 ; → **−1** si OpenDevice renvoie 0, sinon **0** | O |
| 32 | $FF4540 | closedevice(iob) | exec CloseDevice ; résultat non significatif | O |
| 36 | $FF469E | setflags(taskid, m) | Signal(mp_SigTask du port `taskid` (+$10), **(m & 15) << 12**) : bit 0 de m = CTRL-C … bit 3 = CTRL-F | O |
| 37 | $FF46C2 | testflags(m) | SetSignal(0, (m&15)<<12) : teste **et efface** ; → −1 si un bit était posé, sinon 0 | O |
| 41 | $FF4648 | taskwait() | si **pr_PktWait** (process+$B4) ≠ 0 : appel `jsr` de cette routine avec **D0 = MsgPort du process**, elle doit rendre le message en **D0** ; sinon : efface SIGF_DOS ($100), GetMsg sur le port du process, Wait($100) tant que vide. → **BPTR(msg.ln_Name)** (= le packet) | O |
| 42 | $FF4600 | qpkt(pkt) | dp_Link (= Message) doit être > 0, sinon renvoie 0, R2 = 101 ; message.ln_Name := pkt ; ln_Succ/Pred := 0 ; destination = ancien dp_Port, **dp_Port := port du process** ; PutMsg ; → 1 | O |
| 50 | $FF4E3E | **openwindow(x, y, l, h, titre)** | Intuition OpenWindow (IntuitionBase = **GV[92]**, posée par cliinit) avec une NewWindow sur la pile : Left/Top/Width/Height = args, Detail/BlockPen = $FF/$FF, IDCMP 0, **Flags $00021007** (SIZING, DRAG, DEPTH, ACTIVATE, NOCAREREFRESH, smart refresh), pas de gadgets/checkmark, **Title = titre×4** (BPTR d'un tampon chaîne C, pas un BSTR), Screen/BitMap 0, **Min 120×50, Max $FFFF×$FFFF, Type WBENCHSCREEN (1)** ; → APTR Window ou 0 | O |
| 86 | $FF7A70 | **datstamp(v)** | DateStamp (C, globale −25) dans BADDR(v) : v!0 jours, v!1 minutes, v!2 ticks ; **renvoie v**. (Pas de rapport avec les volumes.) | O |

---

## 4. Q4 — Globales « fichier » et deviceproc

### 4.1 deviceproc(nom) — globale 102 ($FF58E0) [O ROM]
1. `splitname(préfixe, ':', nom, 1)` → `pos` = indice après `:` (0 si pas de `:`).
2. *(boucle de retry)* `lock` := currentdir courant ; Result2 := 218.
3. `nom` = `"NIL:"` (insensible à la casse) ⇒ renvoie **0**.
4. **Pas de préfixe** (`pos` = 0) **ou** nom commençant par `:` (`pos` = 2) :
   - répertoire courant nul ⇒ port = **pr_FileSystemTask**, lock = 0 ;
   - sinon port = **dn_Task du volume** du lock courant (`fl_Volume`→`!2`), nom de volume mémorisé
     pour le requester ; si `:` initial ⇒ **lock := 0** (racine).
5. **Préfixe** : recherche dans di_DevInfo du **premier nœud de ce nom, tout type** (sous Forbid).
   - aucun ⇒ le préfixe devient le nom de volume du requester (le `:` remplacé par NUL) ;
   - trouvé : **lock := dn_Lock** ; port := `dn_Task` si dn_Lock = 0, sinon **fl_Task du dn_Lock
     (+$0C)** ; si port = 0 : type 0 ⇒ **starthandler(nœud, nom complet)** ; autre type ⇒ requester.
6. Port = 0 et un nom de volume connu : envoie d'abord un packet **ACTION_FLUSH (27)** au FS
   (pr_FileSystemTask), puis requester `"Please insert volume" %S "in any drive"` ; Retry ⇒ étape 2 ;
   Cancel ⇒ Result2 := 218, renvoie 0. Sans nom de volume ⇒ renvoie 0 (R2 = 218).
7. Succès : **Result2 := lock**, renvoie le port.

**Exemples** [D à partir de 1–7] :
| Nom | Port | Result2 (lock → Arg1) |
|---|---|---|
| `RAM:t` (1er accès) | starthandler(RAM) | **0** (dn_Lock de RAM) |
| `RAM:t` (ensuite) | dn_Task écrit par le Ram-Handler | 0 |
| `RAM DISK:t` | dn_Task du volume | 0 |
| `LIBS:x` | fl_Task du lock d'assign | **dn_Lock** de LIBS |
| `t` | handler du volume du répertoire courant | lock du répertoire courant |
| `:t` | idem | **0** |
| `FOO:` inconnu | requester « Please insert volume FOO » | 218 si Cancel |

### 4.2 Routine commune « objet » (repère $FF7CF8) [O ROM]
`obj(nom, action, arg3)` : `port = deviceproc(nom)` ; `lock = Result2` ; port = 0 ⇒ renvoie 0.
Packet synchrone (sendpkt) au port, type = action :
- **cas général** : **Arg1 = lock**, **Arg2 = BSTR du nom complet** (non découpé : le handler doit
  sauter le préfixe jusqu'au `:`), **Arg3 = arg3** ;
- **action 28 (SET_COMMENT) et 21 (SET_PROTECT)** : **Arg1 non initialisé**, Arg2 = lock, Arg3 = nom,
  **Arg4 = arg3** (commentaire / masque).
- Résultat = **dp_Res1** ; Result2 = **dp_Res2**. Res1 = 0 ⇒ `errorreq(2, Result2, port)`
  (globale 114) ; Retry ⇒ **tout recommence** (deviceproc compris) ; sinon renvoie 0.

### 4.3 Table des globales [O ROM]
| Gl. | Nom | Packet | Arg1 | Arg2 | Arg3 / Arg4 | Résultat |
|---|---|---|---|---|---|---|
| 108 | locateobj(nom) | ACTION_LOCATE_OBJECT **8** | lock | nom | **−2** (SHARED) | lock BPTR ou 0 |
| 123 | lock(nom, mode) | = locateobj (**mode ignoré**) | | | | idem |
| −11 | LVO Lock (C) | 8 | lock | nom | **mode passé tel quel** | idem |
| 90 | deleteobj(nom) | ACTION_DELETE_OBJECT **16** | lock | nom | non significatif | ≠0 succès |
| 125 | createdir(nom) | ACTION_CREATE_DIR **22** | lock | nom | non significatif | **lock** du nouveau répertoire |
| 91 | rename(ancien, nouveau) | ACTION_RENAME_OBJECT **17** | lock(ancien) | ancien | Arg3 = lock(nouveau), Arg4 = nouveau | ≠0 succès |
| −23 / −24 | SetComment / SetProtection | 28 / 21 | — | lock | Arg3 nom, Arg4 valeur | |
| 109 | freeobj(lock) | ACTION_FREE_LOCK 15 au fl_Task | | | | R2 préservé |

- **rename** : deviceproc des deux noms ; l'un nul ⇒ 0 ; **ports différents ⇒ Result2 = 215**
  (ERROR_RENAME_ACROSS_DEVICES), renvoie 0 ; échec du packet ⇒ errorreq/retry comme §4.2.
- Les LVO C (DeleteFile → 90, CreateDir → 125, Rename → 91) convertissent les chaînes C en BSTR
  puis appellent la globale BCPL. [O]

### 4.4 Usage par les commandes c: [O WB]
Toutes BCPL (stub 316 octets + module).
| Commande | Globales (hors stub) | Remarques |
|---|---|---|
| MakeDir | 2, 10, 73, 74, 78, 108, 109, 125 | template `"/A"` ; locateobj d'abord ⇒ `"%S already exists"` ; createdir puis **freeobj du lock rendu** ; échec `"Can't create directory %S"` |
| Assign | 2, 10, 30, 35, 39, 48, 68, 73, 74, 77, 78, 85, 88, 107, 109, 114, 115, 123 | template `"NAME,DIR,LIST/S,EXISTS/S,REMOVE/S"` ; vérifie le répertoire par **ACTION_EXAMINE_OBJECT (23)** ; crée le nœud par makedevnode puis **dn_Task := fl_Task du lock, dn_Type := 1, dn_Lock := lock** (lock conservé) ; liste « Volumes / Directories / Devices » |
| Delete | 2, 10, 29, 30, 37, 48, 51, 73–75, 78, 84 (privée), 90, 104, 107–109, 114 | parcourt par EXAMINE_OBJECT (23) / EXAMINE_NEXT (24), supprime par deleteobj |
| Rename | 2, 10, 73, 74, 78, 91 | template `"FROM/A,TO=AS/A"` ; `"Can't rename %s as %s"` |

---

## 5. Q5 — Spécificités de RAM

- **Côté ROM** : rien de spécial au-delà du nœud §1.2 (handler disque, GV neuf, pile 300). Aucune
  chaîne « RAM DISK » dans la ROM. [O]
- **Côté `l:Ram-Handler`** (2 hunks : hunk 0 = petite routine asm installée en **globale 156**
  = CopyMem exec, hunk 1 = module BCPL max 158 ; il **redéfinit la globale 35** (parentdir) dans
  son GV privé). Au démarrage [O WB] :
  1. nœud := Arg3 ; copie le BSTR **"RAM DISK"** dans un getvec(12) ;
  2. crée le **répertoire racine** : getvec(45) effacé, type **2** (ST_USERDIR) au long `!2`,
     nom au long `!9`, **date** (datstamp) aux longs `!6..!8` ; globales privées 150–158 (151 =
     racine, 157 = nœud volume, 158 = `'DOS\0'`) ;
  3. **dn_Task du nœud RAM := taskid()** ; efface `!4..!9` du nœud RAM ;
  4. **makedevnode("RAM DISK")** ⇒ nœud **volume** inséré en tête : dn_Task := taskid(),
     **dn_Type := 2**, dl_Lock := 0, dl_LockList := 0, **dl_DiskType := `'DOS\0'`** ;
     **dl_VolumeDate laissé à 0** (effacé par makedevnode), slot `!9` non initialisé ;
  5. **returnpkt(pkt, −1, 0)** puis boucle taskwait.
- Conséquences : après le premier accès, `RAM:` et `RAM DISK:` désignent le même port ; dn_SegList
  du nœud RAM étant effacé par le handler, dos ne connaît plus le segment (le handler n'est jamais
  rechargé tant que dn_Task ≠ 0). [D]

---

## 6. Relecture clean-room

Je certifie, après relecture intégrale de ce document, que :
- il ne contient **aucune suite d'instructions 68000 recopiée ou paraphrasée ligne à ligne**, ni de
  la ROM ni des binaires du disque Workbench, aucun extrait de désassemblage, aucun opcode ;
- les routines sont décrites comme des **spécifications fonctionnelles** (entrées, sorties, effets
  observables et leur ordre) ; les étapes numérotées de §1.1, §4.1 et §4.2 décrivent l'ordre des
  **effets visibles** (structures écrites, packets envoyés, requesters), pas la structure du code
  (registres, branches et variables de travail internes ne sont pas décrits) ;
- les seules valeurs reprises sont des éléments d'ABI et d'interopérabilité : layouts (DeviceNode,
  volume, FileLock, DosPacket, NewWindow, IORequest), numéros de globales, codes d'action et
  d'erreur, tailles de pile, priorités, constantes d'environnement disque, chaînes et templates
  nécessaires à la compatibilité, et adresses ROM à titre de repère d'analyse ;
- la ROM n'a été ni modifiée ni copiée ; les fichiers du disque Workbench n'ont été extraits que
  dans le répertoire scratch de session.
