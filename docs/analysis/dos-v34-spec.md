# dos-v34-spec.md — Spec comportementale de dos.library (V34 / Kickstart 1.3)

> Piste ANALYSE (« dirty »). Objectif aval : « dos peut ouvrir/lire un fichier à travers un
> process file-handler via des DOS packets, et charger+exécuter un exécutable depuis DF0: ».
> Trois provenances, étiquetées par champ :
> **[ROM]** mesuré dans `assets/kick34005.A500` (oracle dur, falsifiable par relecture) ;
> **[ABI]** layout/constantes issus des includes publics NDK (`dos/dosextens.i`, `dos/dos.i`,
> `dos/filehandler.i`, `FD/dos_lib.fd`) et de la spec packets publique (RKRM/AmigaMail Vol.2) —
> ces includes décrivent surtout la **2.0/3.x**, les deltas V34 sont signalés explicitement ;
> **[inféré]** déduit du comportement 1.3 connu, non vérifié ligne à ligne (le mur clean-room
> interdit de transcrire le code). **Aucun opcode ni suite d'instructions n'est reproduit ici.**

## 0. Fait fondateur : la dos V34 est la dos **BCPL** (delta majeur vs 2.0)

- **[ROM]** ROMTag `dos.library` : `rt_Flags = 0` (ni AUTOINIT ni COLDSTART),
  `rt_Type = NT_LIBRARY (9)`, `rt_Pri = 0`, `rt_Init = rt_EndSkip` (même pointeur), `rt_Name` → `"dos.library"`,
  `rt_IdString` → `"dos 34.3 (9 Dec 1987)"`. dos n'a donc **pas** de table
  auto-init statique : son `rt_Init` est du code d'init **manuel** (il alloue et publie sa base
  lui-même) et il n'est **pas** démarré par la passe `InitCode(RTF_COLDSTART)` — il est amené par
  l'amorçage disque (cf. `dos-boot-sequence.md`).
- **[ABI/inféré]** En 1.3, dos est un portage **BCPL**. Conséquences observables, structurantes
  pour toute réimplémentation V34 :
  - **BPTR** = « BCPL pointer » = adresse octet **divisée par 4**. Conversion publique :
    `BADDR(bptr) = bptr << 2` (`dos/dos.i`). Toute structure désignée par un BPTR est donc
    **alignée sur 4 octets**. Les champs notés `BPTR`/`BSTR` ci-dessous portent des valeurs
    décalées ; les champs notés `APTR` portent des pointeurs exec normaux (non décalés).
  - **BSTR** = BPTR vers une chaîne **BCPL** : **premier octet = longueur**, puis les caractères
    (pas de terminateur). **[ROM]** Corroboré directement dans la ROM : le gabarit de nom de device
    est stocké comme BSTR `{0x03,'D','F','X'}` (le `'X'` = `0x58` est patché par le
    numéro d'unité `0`..`3` à l'exécution) ; le nom de handler est `{0x0B,"File System"}` ;
    la tâche résidente du handler porte `{0x0B,"FileHandler"}` ; le gabarit de fenêtre
    CLI est `{0x18,"CON:0/0/640/200/AmigaDOS"}`. L'octet de longueur précède bien la
    chaîne dans chaque cas → convention BSTR confirmée en ROM.
  - **Global vector** : les routines internes de dos sont appelées via un **vecteur global BCPL**
    (`pr_GlobVec` par process, `dl_GV` dans la base). La jump table LVO exposée publiquement n'est
    qu'une **mince couche** d'entrées qui bascule dans le code BCPL via ce vecteur global et les
    registres BCPL standard (`dl_A2`/`dl_A5`/`dl_A6`). C'est un détail d'**implémentation** V34
    (non reproductible champ à champ sans transcrire le code) — mais il est **observable** par le
    fait que `pr_GlobVec` et `dl_GV` ne sont pas nuls et que les handlers BCPL partagent ce vecteur.

## 1. Layout des structures V34 (offsets)

> Offsets **calculés** depuis les includes NDK (macros `STRUCTURE`/`BYTE`/`WORD`/`LONG`/`APTR`/
> `BPTR`/`BSTR`/`STRUCT` de `exec/types.i` : **addition séquentielle sans auto-alignement**).
> Tailles de base utilisées (toutes [ABI], vérifiées par recalcul) : `LN_SIZE=14`, `MLN_SIZE=8`,
> `LH_SIZE=14`, `MLH_SIZE=12`, `MN_SIZE=20`, `MP_SIZE=34 (0x22)`, `LIB_SIZE=34 (0x22)`,
> `TC_SIZE=92 (0x5C)`, `SS_SIZE=46 (0x2E)`, `ds_SIZEOF=12`. Les offsets de structure sont de
> l'**ABI d'interopérabilité** ; ils sont **stables 1.3↔2.0** SAUF aux endroits marqués « delta ».

### 1a. Groupe STABLE (haute confiance, identique 1.3/2.0)

#### `FileHandle` — 44 octets (`0x2C`). **Il n'existe PAS de champ `fh_Port`.**
| Off | Champ | Rôle |
|----:|-------|------|
| 0x00 | `fh_Link` | APTR, usage privé |
| 0x04 | `fh_Interactive` | APTR/BOOL, vrai si handle interactif (console) |
| 0x08 | `fh_Type` | **APTR = le `MsgPort` du handler** auquel `PutMsg()` les packets. C'EST le port ; pas de `fh_Port` séparé. |
| 0x0C | `fh_Buf` | LONG, tampon de bufférisation (BPTR) |
| 0x10 | `fh_Pos` | LONG, position dans le tampon |
| 0x14 | `fh_End` | LONG, fin de données valides dans le tampon |
| 0x18 | `fh_Func1` (=`fh_Funcs`) | LONG |
| 0x1C | `fh_Func2` | LONG |
| 0x20 | `fh_Func3` | LONG |
| 0x24 | `fh_Arg1` (=`fh_Args`) | **LONG = la clé privée du fichier côté handler** (voir §2) |
| 0x28 | `fh_Arg2` | LONG |

#### `DosPacket` — 48 octets (`0x30`)
| Off | Champ | Rôle |
|----:|-------|------|
| 0x00 | `dp_Link` | APTR → le `Message` exec associé |
| 0x04 | `dp_Port` | APTR → port de **réponse** (doit être rempli à CHAQUE envoi : dos l'écrase) |
| 0x08 | `dp_Type` (=`dp_Action`) | LONG, code `ACTION_*` (voir §2) |
| 0x0C | `dp_Res1` (=`dp_Status`) | LONG, résultat (ce que la fonction aurait renvoyé) |
| 0x10 | `dp_Res2` (=`dp_Status2`) | LONG, code d'erreur (ce que `IoErr()` aurait renvoyé) |
| 0x14 | `dp_Arg1` (=`dp_BufAddr`) | LONG |
| 0x18 | `dp_Arg2` | LONG |
| 0x1C | `dp_Arg3` | LONG |
| 0x20 | `dp_Arg4` | LONG |
| 0x24 | `dp_Arg5` | LONG |
| 0x28 | `dp_Arg6` | LONG |
| 0x2C | `dp_Arg7` | LONG |

#### `StandardPacket` — 68 octets (`0x44`)
| Off | Champ | Rôle |
|----:|-------|------|
| 0x00 | `sp_Msg` | `struct Message` (20 oct., `MN_SIZE`) — le message exec |
| 0x14 | `sp_Pkt` | `struct DosPacket` (48 oct.) |

Couplage conventionnel : `sp_Msg.mn_Node.ln_Name` pointe sur `sp_Pkt`, et `dp_Link` pointe sur
`sp_Msg`, de sorte qu'un `GetMsg()` qui rend le `Message` permet de retrouver le packet. **[ABI]**

#### `CommandLineInterface` (CLI) — 64 octets (`0x40`), identique 1.3/2.0
| Off | Champ | | Off | Champ |
|----:|-------|--|----:|-------|
| 0x00 | `cli_Result2` (LONG) | | 0x24 | `cli_CommandFile` (BSTR) |
| 0x04 | `cli_SetName` (BSTR) | | 0x28 | `cli_Interactive` (LONG/BOOL) |
| 0x08 | `cli_CommandDir` (BPTR) | | 0x2C | `cli_Background` (LONG/BOOL) |
| 0x0C | `cli_ReturnCode` (LONG) | | 0x30 | `cli_CurrentOutput` (BPTR FileHandle) |
| 0x10 | `cli_CommandName` (BSTR) | | 0x34 | `cli_DefaultStack` (LONG, en **long words**) |
| 0x14 | `cli_FailLevel` (LONG) | | 0x38 | `cli_StandardOutput` (BPTR FileHandle) |
| 0x18 | `cli_Prompt` (BSTR) | | 0x3C | `cli_Module` (BPTR, SegList commande chargée) |
| 0x1C | `cli_StandardInput` (BPTR FileHandle) | | | |
| 0x20 | `cli_CurrentInput` (BPTR FileHandle) | | | |

#### `FileLock` — 20 octets (`0x14`)
| Off | Champ | Rôle |
|----:|-------|------|
| 0x00 | `fl_Link` | BPTR, lock suivant dans la chaîne du handler |
| 0x04 | `fl_Key` | LONG, numéro de bloc disque de l'objet |
| 0x08 | `fl_Access` | LONG, `SHARED_LOCK (-2)` ou `EXCLUSIVE_LOCK (-1)` |
| 0x0C | `fl_Task` | APTR, le `MsgPort` du handler propriétaire du lock |
| 0x10 | `fl_Volume` | BPTR → nœud `DLT_VOLUME` du volume |

#### `DeviceNode` (= `DevInfo`/`dvi_*` de dosextens) — 44 octets (`0x2C`), layout stable 1.3/2.0
> C'est le nœud d'un « device » DOS (ex. `DF0:`), chaîné dans la liste device. En 1.3, c'est
> cette forme (`dos/filehandler.i`) qui est utilisée ; la structure unifiée `DosList` est un
> **habillage 2.0** du même stockage (cf. §1b).
| Off | Champ | Rôle |
|----:|-------|------|
| 0x00 | `dn_Next` | BPTR, liste simplement chaînée |
| 0x04 | `dn_Type` | ULONG, toujours 0 pour un device DOS |
| 0x08 | `dn_Task` | APTR = `MsgPort` du process handler. **NULL ⇒ le handler sera démarré au 1er accès** |
| 0x0C | `dn_Lock` | BPTR, non utilisé pour un device |
| 0x10 | `dn_Handler` | BSTR = fichier à `LoadSeg` si `dn_SegList` est NULL |
| 0x14 | `dn_StackSize` | ULONG, pile du process handler à sa création |
| 0x18 | `dn_Priority` | LONG, priorité du process handler |
| 0x1C | `dn_Startup` | BPTR → `FileSysStartupMsg` (pour un disque) |
| 0x20 | `dn_SegList` | BPTR, code déjà chargé du handler (si NULL → charger `dn_Handler`) |
| 0x24 | `dn_GlobalVec` | BPTR, vecteur global BCPL. **-1** = `dn_SegList` n'est PAS un prog BCPL (dos ne construit pas de GV) ; **0** = prog BCPL conforme, dos construit le GV ; **>0** = GV existant |
| 0x28 | `dn_Name` | BSTR = nom du nœud (ex. BSTR `{3,"DF0"}`) |

#### `FileSysStartupMsg` — 16 octets (`0x10`)
| Off | Champ | Rôle |
|----:|-------|------|
| 0x00 | `fssm_Unit` | ULONG, numéro d'unité exec du device (0..3 pour DFx) |
| 0x04 | `fssm_Device` | BSTR, nom du device bas niveau (**[ROM]** `"trackdisk.device"`) |
| 0x08 | `fssm_Environ` | BPTR → table d'environnement/géométrie (`DosEnvec`) |
| 0x0C | `fssm_Flags` | ULONG, flags pour `OpenDevice()` |

#### `DosLibrary` (base de dos) — en-tête + câblage BCPL
| Off | Champ | Rôle |
|----:|-------|------|
| 0x00 | `dl_lib` | `struct Library` (34 oct., `LIB_SIZE`) ; `lib_Version=34`, `lib_Revision=3` ([ROM] « dos 34.3 ») |
| 0x22 | `dl_Root` | APTR → `RootNode` (racine de tout le câblage DOS, cf. §1b et `dos-boot-sequence.md`) |
| 0x26 | `dl_GV` | APTR → **vecteur global BCPL** |
| 0x2A | `dl_A2` | LONG, valeurs de registres BCPL standard |
| 0x2E | `dl_A5` | LONG |
| 0x32 | `dl_A6` | LONG |
| 0x36 | `dl_Errors` | APTR, privé : table des messages d'erreur |
| 0x3A | `dl_TimeReq` | APTR, privé : requête timer |
| 0x3E | `dl_UtilityBase` | APTR, privé — **delta : utility.library est 2.0 ; champ sans objet en V34** |
| 0x42 | `dl_IntuitionBase` | APTR, privé : base intuition (pour les requesters disque) |

### 1b. Groupe MODIFIÉ en 2.0 — le V34 **diffère** (couper les queues !)

#### `Process` — **frontière V34 : la structure s'arrête à `pr_WindowPtr`**
Les offsets de 0x00 à 0xB8 sont V34-valides ; **tout ce qui suit est « new with 2.0 »**
(annotation explicite de `dosextens.i`) et **n'existe pas en V34**.
| Off | Champ V34 | Rôle |
|----:|-----------|------|
| 0x00 | `pr_Task` | `struct Task` (92 oct., `TC_SIZE`) |
| 0x5C | `pr_MsgPort` | `struct MsgPort` (34 oct.) embarqué. **C'est ce port que `CreateProc`/`DeviceProc` renvoient — comme un `APTR` directement utilisable (adresse octet), PAS un BPTR** (cf. §4). Le commentaire « BPTR address » de `dosextens.i` est trompeur : l'arithmétique `Process = retour − TC_SIZE` est en octets, et tous les autres champs « port de handler » ici sont des `APTR` (`pr_ConsoleTask`, `pr_FileSystemTask`, `fl_Task`, `dn_Task`, `dp_Port`, `fh_Type`). |
| 0x7E | `pr_Pad` | WORD |
| 0x80 | `pr_SegList` | BPTR, tableau des seglists du process |
| 0x84 | `pr_StackSize` | LONG |
| 0x88 | `pr_GlobVec` | APTR, **vecteur global BCPL du process** |
| 0x8C | `pr_TaskNum` | LONG, n° de tâche CLI (0 si pas un CLI) |
| 0x90 | `pr_StackBase` | BPTR, haut de pile du process |
| 0x94 | `pr_Result2` | LONG, résultat secondaire du dernier appel (= `IoErr`) |
| 0x98 | `pr_CurrentDir` | BPTR, lock du répertoire courant |
| 0x9C | `pr_CIS` | BPTR, flux d'entrée CLI courant (FileHandle) |
| 0xA0 | `pr_COS` | BPTR, flux de sortie CLI courant (FileHandle) |
| 0xA4 | `pr_ConsoleTask` | APTR, process handler console de la fenêtre courante |
| 0xA8 | `pr_FileSystemTask` | APTR, process handler du drive courant |
| 0xAC | `pr_CLI` | BPTR → `CommandLineInterface` |
| 0xB0 | `pr_ReturnAddr` | APTR, cadre de pile précédent |
| 0xB4 | `pr_PktWait` | APTR, fonction appelée en attente de message |
| 0xB8 | `pr_WindowPtr` | APTR, fenêtre pour les requesters d'erreur. **← dernier champ V34** |

**Taille `Process` en V34 ≈ `0xBC` (188 octets).** `pr_HomeDir (0xBC)`, `pr_Flags (0xC0)`,
`pr_ExitCode`, `pr_ExitData`, `pr_Arguments`, `pr_LocalVars`, `pr_ShellPrivate`, `pr_CES` sont
**des ajouts 2.0+** : une réimplémentation 1.3 ne doit NI réserver NI exposer ces champs. (Analogue
à la frontière `ExecBase` à `~0x22E` documentée dans `exec-spec.md`.)

#### `RootNode` — **frontière V34 : s'arrête à `rn_FileHandlerSegment`**
| Off | Champ V34 | Rôle |
|----:|-----------|------|
| 0x00 | `rn_TaskArray` | BPTR : `[0]` = nb max de CLI ; `[n]` = APTR vers le process id du CLI n |
| 0x04 | `rn_ConsoleSegment` | BPTR, SegList du CLI |
| 0x08 | `rn_Time` | `DateStamp` (12 oct.), heure courante |
| 0x14 | `rn_RestartSeg` | LONG/BPTR, **SegList du process disk-validator** ([ROM] `"L:Disk-Validator"` / `"Validator"`) |
| 0x18 | `rn_Info` | BPTR → `DosInfo` |
| 0x1C | `rn_FileHandlerSegment` | BPTR, **code du file-handler** (le handler OFS résident). **← dernier champ V34** |

**Taille `RootNode` en V34 ≈ `0x20` (32 octets).** `rn_CliList`, `rn_BootProc`, `rn_ShellSegment`,
`rn_Flags` sont **2.0+** (il n'y a pas de liste de CLI à base de `MinList`, ni de Shell, ni de
flags dos en 1.3 : la gestion des CLI passe uniquement par `rn_TaskArray`).

#### `DosInfo` — **frontière V34 : s'arrête à `di_NetHand` ; PAS de sémaphores en 1.3**
| Off | Champ V34 | Rôle |
|----:|-----------|------|
| 0x00 | `di_McName` (=`di_ResList`) | BPTR, liste des modules résidents DOS (segments chargés) |
| 0x04 | `di_DevInfo` | BPTR → **tête de la liste des devices/volumes/assigns** (`DeviceNode` chaîne) |
| 0x08 | `di_Devices` | BPTR, zéro en pratique |
| 0x0C | `di_Handlers` | BPTR, zéro en pratique |
| 0x10 | `di_NetHand` | APTR, zéro. **← dernier champ V34** |

**En V34, la liste device est protégée par `Forbid()/Permit()`**, pas par des sémaphores.
`di_DevLock`, `di_EntryLock`, `di_DeleteLock` (3× `SignalSemaphore`) sont **2.0+** : ne pas les
allouer ni s'appuyer dessus pour une cible 1.3. **Taille `DosInfo` en V34 ≈ `0x14` (20 octets).**

#### `DosList` (vue unifiée 2.0) vs nœuds 1.3
`DosList` (dosextens) est une **structure unionée introduite en 2.0** pour décrire indifféremment
device / volume / assign. Pour la 1.3, décrire plutôt :
- **device** : `DeviceNode` (§1a) ;
- **volume** : `DevList`/`dl_*` (`dl_Next` 0x00, `dl_Type` 0x04, `dl_Task` 0x08, `dl_Lock` 0x0C,
  `dl_VolumeDate` 0x10 `DateStamp`, `dl_LockList` 0x1C, `dl_DiskType` 0x20, `dl_Name` 0x28 BSTR —
  44 oct.).

Les offsets « DosList » utiles sont néanmoins cohérents avec `DeviceNode` sur les premiers champs
(`dol_Next`/`dol_Type`/`dol_Task`/`dol_Lock` = `dn_Next`/`dn_Type`/`dn_Task`/`dn_Lock`), et
`dol_Startup=0x1C`, `dol_SegList=0x20`, `dol_GlobVec=0x24`, `dol_Name=0x28` coïncident avec
`dn_Startup`/`dn_SegList`/`dn_GlobalVec`/`dn_Name`. Constantes de type : `DLT_DEVICE=0`,
`DLT_DIRECTORY=1` (assign), `DLT_VOLUME=2`.

## 2. Protocole packet du file-handler (chemin ouvrir-en-lecture → lire → fermer)

### 2a. Le cycle d'un packet — **ATTENTION : pas de `DoPkt()` public en V34**
**[ABI, delta majeur]** `DoPkt`, `SendPkt`, `WaitPkt`, `ReplyPkt`, `AbortPkt` sont marqués
*« functions in V36 or higher (Release 2.0) »* dans `dos_lib.fd` : **ils n'existent PAS dans la
jump table V34**. En 1.3, l'échange de packet est fait par les routines **BCPL internes** de dos
(un `sendpkt`/`taskwait` interne), ou, côté application, en **montant le packet à la main** et en
utilisant les primitives **exec** `PutMsg`/`WaitPort`/`GetMsg`. Une réimplémentation 1.3 ne peut
donc PAS s'appuyer sur `DoPkt()` : elle doit soit fournir l'équivalent interne, soit documenter le
pattern exec. Le cycle observable (identique quel que soit l'habillage) :

1. L'appelant (le process demandeur) obtient/alloue un `StandardPacket` (message exec + DosPacket).
2. Il remplit `dp_Type` (= `ACTION_*`), `dp_Arg1..n`, et **`dp_Port = &demandeur->pr_MsgPort`**
   (le port de réponse ; dos/BCPL l'écrase à chaque envoi — toujours le re-remplir).
3. `PutMsg()` du message au `MsgPort` du handler (= `fh_Type`, ou `dn_Task`, ou `fl_Task`).
4. L'appelant `WaitPort(&pr_MsgPort)` puis `GetMsg()` pour récupérer la réponse (le handler a fait
   `ReplyMsg()` vers `dp_Port`). Le handler est un **process** : il boucle en `WaitPort`/`GetMsg`
   sur SON port, traite le packet, remplit `dp_Res1`/`dp_Res2`, `ReplyMsg()`.
5. L'appelant lit `dp_Res1` (résultat) et `dp_Res2` (code d'erreur, = `IoErr`).

**Identité clé [ABI, corroborée dos.i]** : le `mode` passé à `Open()` **EST** le code `ACTION_*`
envoyé au handler — `MODE_OLDFILE = 1005 = ACTION_FINDINPUT`, `MODE_NEWFILE = 1006 =
ACTION_FINDOUTPUT`, `MODE_READWRITE = 1004 = ACTION_FINDUPDATE`.

### 2b. Table des packets du chemin lecture (args et résultats)
> **[ABI]** d'après la spec packets publique (RKRM Devices / AmigaMail Vol.2). `LOCK` = BPTR vers
> `FileLock` (0 = racine du volume courant). `BSTR` = BPTR vers chaîne BCPL longueur-préfixée.

| ACTION_ (val.) | Via | ARG1 | ARG2 | ARG3 | RES1 | RES2 |
|----------------|-----|------|------|------|------|------|
| `FINDINPUT` (1005) | `Open(…,MODE_OLDFILE)` | **BPTR `FileHandle` à remplir** | `LOCK` répertoire de base (0=racine) | `BSTR` nom du fichier (relatif à ARG2) | `BOOL` succès (DOSTRUE/DOSFALSE) | code si échec |
| `FINDOUTPUT` (1006) | `Open(…,MODE_NEWFILE)` | idem | idem | idem | idem | idem |
| `FINDUPDATE` (1004) | `Open(…,MODE_READWRITE)` | idem | idem | idem | idem | idem |
| `READ` (`'R'`=82) | `Read()` | **`fh_Arg1`** du FileHandle ouvert | `APTR` buffer destination | `LONG` nb d'octets à lire | `LONG` octets lus (**0 = EOF, -1 = erreur**) | code si RES1=-1 |
| `WRITE` (`'W'`=87) | `Write()` | `fh_Arg1` | `APTR` buffer source | `LONG` nb d'octets | `LONG` octets écrits | code si RES1≠ARG3 |
| `SEEK` (1008) | `Seek()` | `fh_Arg1` | `LONG` nouvelle position | `LONG` mode (`OFFSET_BEGINNING -1`/`OFFSET_CURRENT 0`/`OFFSET_END 1`) | `LONG` ancienne position (-1 = erreur) | code si RES1=-1 |
| `END` (1007) | `Close()` | `fh_Arg1` | — | — | `LONG` DOSTRUE | — |
| `LOCATE_OBJECT` (8) | `Lock()` | `LOCK` répertoire de base (0=racine) | `BSTR` nom de l'objet | `LONG` mode (`ACCESS_READ/SHARED_LOCK -2`, `ACCESS_WRITE/EXCLUSIVE_LOCK -1`) | `BPTR` nouveau `FileLock` (0=échec) | code si échec |
| `FREE_LOCK` (15) | `UnLock()` | `LOCK` à libérer | — | — | `BOOL` succès | — |
| `EXAMINE_OBJECT` (23) | `Examine()` | `LOCK` de l'objet | `BPTR` `FileInfoBlock` à remplir | — | `BOOL` succès | code |
| `EXAMINE_NEXT` (24) | `ExNext()` | `LOCK` du répertoire examiné | `BPTR` `FileInfoBlock` (du précédent Examine) | — | `BOOL` (échec = plus d'entrées) | code |
| `PARENT` (29) | `ParentDir()` | `LOCK` de l'objet | — | — | `BPTR` lock du parent (0=racine) | code |
| `INFO` (26) | `Info()` | `LOCK` | `BPTR` `InfoData` à remplir | — | `BOOL` succès | code |

**Note 1.3 spécifique [ABI]** : pour `ACTION_END`, « *Under 1.3, [DOS] does not check the result* »
(sous 2.0 un échec empêche la désallocation du FileHandle ; en 1.3 le résultat est ignoré).

## 3. FileHandle : ce que renvoie `Open()` et comment `Read()` route

**[ABI/inféré]** :
1. `Open(name, accessMode)` **alloue** un `FileHandle` (zone BPTR-adressable, alignée 4). Il résout
   le device/volume/assign du chemin via la liste `di_DevInfo` (→ `DeviceProc`), démarre le handler
   si `dn_Task` est NULL (cf. `dos-boot-sequence.md` §D), puis pose **`fh_Type = dn_Task`** (le
   `MsgPort` du handler).
2. Il envoie le packet `FINDINPUT/OUTPUT/UPDATE` (= `accessMode`) avec **ARG1 = BPTR du FileHandle
   lui-même** et ARG2/ARG3 = lock+nom. Le handler, en succès, **remplit `fh_Arg1`** (sa clé privée
   d'objet fichier) et renvoie `DOSTRUE` dans `dp_Res1`.
3. `Open()` renvoie le **BPTR du FileHandle** (0 en échec, `IoErr`/`pr_Result2` posé).
4. `Read(fh, buf, len)` prend le FileHandle, lit **`fh_Arg1`** et **`fh_Type`**, et envoie un packet
   `ACTION_READ` au port `fh_Type` avec ARG1=`fh_Arg1`, ARG2=buffer, ARG3=longueur. Il retourne
   `dp_Res1` (octets lus, 0=EOF, -1=erreur). `Close(fh)` envoie `ACTION_END(fh_Arg1)` et libère le
   FileHandle. Les champs `fh_Buf`/`fh_Pos`/`fh_End` servent à la **bufférisation ligne/caractère**
   (p. ex. pour les lectures interactives) ; les lectures en bloc passent directement par le packet.

## 4. `CreateProc` et aspects BCPL **observables** (jamais transcrits)

- **[ABI]** `CreateProc(name D1, pri D2, segList D3, stackSize D4)` crée un `Process` et renvoie
  **un `APTR` (pointeur octet directement utilisable) sur son `MsgPort`** (`pr_MsgPort`), prêt pour
  `PutMsg()` tel quel. Relation d'ABI documentée : l'adresse du `Process` = `valeur_rendue − TC_SIZE`
  (= `− 92` **octets**), car `pr_MsgPort` est à l'offset `TC_SIZE` dans `Process`. `DeviceProc(name)`
  renvoie le même type de pointeur (port du handler du chemin).
- **[ABI] Asymétrie BPTR/APTR à ne surtout pas confondre (point de crash classique en 1.3)** :
  `Open()` renvoie un **BPTR** `FileHandle` → il faut `BADDR()` (×4) pour déréférencer la structure.
  `CreateProc()`/`DeviceProc()` renvoient un **APTR** `MsgPort` → **ne PAS `BADDR()`**, on l'utilise
  directement. Même asymétrie dans les structures : les BPTR portent des adresses /4 (locks,
  FileHandles, seglists, BSTR), tandis que les champs de port de handler (`fh_Type`, `dn_Task`,
  `fl_Task`, `pr_FileSystemTask`, `pr_ConsoleTask`, `dp_Port`) sont des APTR exec normaux.
- **[ABI/inféré] Linkage BCPL observable** :
  - Un process DOS reçoit son contexte de démarrage via un **packet de démarrage** (`ACTION_STARTUP`
    = 0) déposé à son `pr_MsgPort` au lancement ; le handler l'attend en premier.
  - `pr_GlobVec` tient le **vecteur global BCPL** du process ; `dn_GlobalVec` décide, à la création,
    si dos doit en construire un (`0`), réutiliser un GV (`>0`) ou considérer que le code n'est pas
    BCPL (`-1`). Le handler OFS résident est un programme **BCPL** partageant le GV de dos.
  - Les routines BCPL prennent leurs **arguments en registres** et manipulent des **BPTR** ; la pile
    BCPL est distincte de la pile C. Ces conventions sont **observables** (valeurs de `pr_GlobVec`,
    `dl_A2/A5/A6`, BPTR dans les champs) mais leur mécanique interne relève de l'implémentation et
    n'est **pas** reproduite ici.
- **[ABI]** `LoadSeg(name)` ouvre le fichier (via les packets §2b), lit un exécutable **hunk**
  (`HUNK_HEADER`/`CODE`/`DATA`/`BSS`/`RELOC32`/`HUNK_END`), alloue un bloc mémoire par hunk, applique
  les relocations, et **chaîne les segments** à la BCPL : à `BADDR(seg)` on trouve le BPTR du segment
  suivant, le code commence à `BADDR(seg)+4`. Renvoie le **BPTR du 1er segment** (0 = échec, `IoErr`
  posé). `UnLoadSeg(seglist)` libère la chaîne. (Cohérent avec le jalon projet D2 « LoadSeg ».)

## 5. Table LVO publique de dos.library en V34 (sous-ensemble 1.3)

**[ABI, `dos_lib.fd` `##bias 30`]** — la V34 expose **uniquement** les fonctions AVANT le marqueur
*« V36 or higher (Release 2.0) »*. 4 vecteurs standard de library (`-6 Open`, `-12 Close`,
`-18 Expunge`, `-24` réservé) puis, de `-30` à `-222` :

| LVO | Fonction | LVO | Fonction | LVO | Fonction |
|----:|----------|----:|----------|----:|----------|
| -30 | `Open` | -96 | `DupLock` | -162 | *(privé dos1)* |
| -36 | `Close` | -102 | `Examine` | -168 | *(privé dos2)* |
| -42 | `Read` | -108 | `ExNext` | -174 | `DeviceProc` |
| -48 | `Write` | -114 | `Info` | -180 | `SetComment` |
| -54 | `Input` | -120 | `CreateDir` | -186 | `SetProtection` |
| -60 | `Output` | -126 | `CurrentDir` | -192 | `DateStamp` |
| -66 | `Seek` | -132 | `IoErr` | -198 | `Delay` |
| -72 | `DeleteFile` | -138 | `CreateProc` | -204 | `WaitForChar` |
| -78 | `Rename` | -144 | `Exit` | -210 | `ParentDir` |
| -84 | `Lock` | -150 | `LoadSeg` | -216 | `IsInteractive` |
| -90 | `UnLock` | -156 | `UnLoadSeg` | -222 | `Execute` |

Soit **37 vecteurs** (dont 2 privés `-162`/`-168`), `lib_NegSize ≈ 222`. **Delta** : tout ce qui
suit (`AllocDosObject`/`FreeDosObject`/`DoPkt`/`SendPkt`/`WaitPkt`/`ReplyPkt`/`AbortPkt`/record
locking/I/O bufférisée `FGetC`…/gestion d'objets 2.0/`SetIoErr`/`Fault`/`PrintFault`…) est **2.0+**
et **ne doit pas exister** dans une jump table V34.

## 6. Incertitudes / à confirmer par la piste implémentation

- **`ACTION_STARTUP` (0)** : la répartition exacte de `dp_Arg1..7` du packet de démarrage reçu par
  un handler 1.3 (quel slot porte le `DeviceNode`, lequel porte le `FileSysStartupMsg`/nom) n'a pas
  été figée à partir d'une source primaire — elle est **handler-dépendante** et doit être validée
  (convention courante : le `DeviceNode` et son `dn_Startup` sont atteignables depuis le packet de
  démarrage ; à vérifier sur comportement réel).
- **Tailles exactes** (`pr_SIZEOF`, `rn_SIZEOF`, `DosInfo` en V34) : déduites des frontières
  « new 2.0 » des includes, non mesurées dans le code d'init de la ROM (le mur interdit de tracer
  `rt_Init`). Les offsets jusqu'aux frontières indiquées sont des faits d'ABI stables ; les tailles
  totales V34 sont à confirmer par comportement sur une 1.3 authentique.
- **Câblage BCPL interne** (contenu du vecteur global, mécanique `sendpkt` interne) : décrit comme
  comportement, non comme code — l'implémentation doit fournir un équivalent fonctionnel, pas une
  copie.
- **`dl_UtilityBase`/sémaphores `DosInfo`/queues `RootNode`/`Process`** : marqués 2.0+ ci-dessus ;
  à NE PAS implémenter pour une cible 1.3 stricte.

## Relecture clean-room

Relecture du 2026-10-29.

- [x] Aucune suite d'instructions 68000 transcrite ni paraphrasée, aucun extrait de désassemblage :
  les §2-§4 décrivent le protocole packet et les conventions BCPL **observables** (champs, valeurs),
  d'après les includes et la spec packets publics.
- [x] **Corrigé** : retirées les adresses ROM de la ROMTag de dos, de `rt_Init`/`rt_EndSkip`,
  `rt_Name`, `rt_IdString` et des chaînes BSTR citées (`DFX`, `File System`, `FileHandler`,
  `CON:…`, `trackdisk.device`). La relation `rt_Init == rt_EndSkip` est conservée sans valeur.
- [x] Restent : offsets de structures publiques NDK (`dosextens.i`, `filehandler.i`), LVO
  (`dos_lib.fd`), constantes `ACTION_*`/`MODE_*`/`DLT_*`, gabarits BSTR courts (noms d'ABI,
  inventoriés dans `docs/audit/specs-review.md`).
