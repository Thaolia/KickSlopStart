# dos-boot-sequence.md — Amorçage côté DOS (Kickstart 1.3 / V34.5)

> Piste ANALYSE (« dirty »). **Reprend là où `boot-sequence.md` s'arrête** (passe
> `InitCode(RTF_COLDSTART)` → le résident `strap` pri -60 amorce le disque). Ce document décrit le
> **flux DOS** : init de `dos.library`, câblage des structures, démarrage du file-handler DF0:, et
> le chemin « charger + lancer une commande ». Description **comportementale** (ordre des
> opérations, effets de bord, champs touchés). **Aucun opcode ni suite d'instructions.** Provenance :
> **[ROM]** = chaîne/donnée mesurée dans `assets/kick34005.A500` ; **[ABI]** = contrat public
> (`dos/*`, RKRM) ; **[inféré]** = comportement 1.3 connu, non vérifié ligne à ligne. Les offsets de
> structures citées sont dans `dos-v34-spec.md`.

## Rappel du point de jonction (depuis `boot-sequence.md`)

`strap` (résident, type UNKNOWN, pri -60, dernier de la passe COLDSTART) cherche un périphérique
amorçable, lit et valide le **bootblock** de DF0: et lui passe la main (jalon projet C/M6y : « ça
boote »). dos.library et workbench.task ont `rt_Flags = 0` : ils ne sont **pas** démarrés par
`InitCode` — ils sont amenés par cet amorçage disque. Le bootblock a pour rôle de **localiser et
initialiser dos**, puis de lui rendre la main.

## Phase A — Initialisation de `dos.library` ([ROM] ancrages + [inféré] séquence)

Déclencheur : le code d'amorçage (bootblock + `strap`) localise le résident dos
(`FindResident "dos.library"`, ROMTag `$FF3E62`) et l'initialise (`InitResident` → saut dans
`rt_Init = $FF3E94`, init **manuel** car `rt_Flags` sans AUTOINIT). Effets observables :

1. Allocation + init de la base `DosLibrary` (`lib_Version=34`, `lib_Revision=3` → [ROM] « dos 34.3 »),
   insertion dans `ExecBase.LibList`, construction de la **jump table** (37 LVO, cf. `dos-v34-spec.md`
   §5) et du **vecteur global BCPL** (`dl_GV`, registres `dl_A2/A5/A6`).
2. Construction du `RootNode` (pointé par `dl_Root`) : `rn_TaskArray` (table des CLI),
   `rn_ConsoleSegment`, `rn_Time`, `rn_RestartSeg` (**[ROM]** seglist du disk-validator, cf. Phase D),
   `rn_Info` → `DosInfo`, `rn_FileHandlerSegment` (**[ROM]** code du handler OFS résident —
   tâche `{0x0B,"FileHandler"}` `$FF8861`).
3. Construction du `DosInfo` (`di_DevInfo` = tête de la liste device/volume/assign). **En V34 la
   liste est protégée par `Forbid()/Permit()`**, pas par sémaphores (cf. frontière §1b de la spec).
4. **[ROM]** Ouverture des libraries dont dos dépend — chaînes mesurées près du code d'init :
   `"expansion.library"` (`$FF403C`), `"ramlib.library"` (`$FF404E`), `"intuition.library"`
   (`$FF4E2B`/`$FF8815`), `"timer.device"` (`$FF54F9`), `"console.device"` (`$FFA711`),
   `"input.device"` (`$FFD365`). expansion fournit la config des unités montables ; ramlib
   (`LDDemon`) permet le `LoadSeg` des handlers/commandes disque ; intuition sert aux **requesters**
   d'erreur disque (cf. Phase D).

## Phase B — Table de montage : devices, volumes, assigns ([ROM] ancrages)

dos publie dans `di_DevInfo` une chaîne de `DeviceNode` (cf. `dos-v34-spec.md` §1a). Mesures ROM :

- **DFx:** — gabarit de nom BSTR `{0x03,'D','F','X'}` (`$FF89A5`), le `'X'` (`0x58`) patché par le
  n° d'unité `0`..`3`. Chaque `DeviceNode` DFx a :
  - `dn_SegList` = `rn_FileHandlerSegment` (handler OFS résident) et `dn_GlobalVec` (prog BCPL) ;
  - `dn_Handler` = BSTR `{0x0B,"File System"}` (`$FF8B45`) — nom chargé si le seglist était NULL ;
  - `dn_Startup` → `FileSysStartupMsg` avec `fssm_Device` = `"trackdisk.device"` (`$FF87F9`),
    `fssm_Unit` = n° de drive, `fssm_Environ` = géométrie (OFS 880 Ko) ;
  - `dn_Task` = NULL au départ ⇒ **handler démarré au 1er accès** (Phase D).
- **Handlers chargés depuis le disque** (`L:`) : `"L:PORT-HANDLER"` (`$FF8D2D`), `"L:RAM-HANDLER"`
  (`$FF8D41`) → nœuds dont `dn_Handler` pointe un fichier à `LoadSeg` ; `"NIL:"` (`$FF5A9D`/`$FF5CF9`).
- **Console** : gabarit `{0x18,"CON:0/0/640/200/AmigaDOS"}` (`$FF886D`) — la fenêtre du CLI initial.
- **Assigns système** : `"LIBS"` (`$FF8831`), `"DEVS"` (`$FF8839`), `"FONTS"` (`$FF8841`),
  et la lecture de `"devs:system-configuration"` (`$FF8FD5`) pour la config.

## Phase C — Premier process (« Initial CLI ») et script de démarrage ([ROM] + [inféré])

1. **[ROM]** dos crée le process du CLI initial — chaîne `"Initial CLI"` (`$FF4025`). Ce process
   (un `Process`, cf. §1b) reçoit un `CommandLineInterface` (`pr_CLI`), un répertoire courant
   (`pr_CurrentDir`), et des flux `pr_CIS`/`pr_COS` branchés sur une fenêtre **CON:** (gabarit
   Phase B) via le handler console.
2. **[ROM/inféré]** Le CLI exécute le script d'amorçage : `":S/STARTUP-SEQUENCE"` (`$FF88D5`), lu via
   le mécanisme `Execute`. Les commandes sont chargées depuis `C:` (`"C:RUN"` `$FF7939`,
   `"C:FAULT"` `$FF501D`). La bannière `"Release 1.3"` (`$FF88C8`) + copyright (`$FF888C`) est
   affichée.
3. **[ROM]** Diagnostics CLI présents : `"Unknown command %S"` (`$FF972D`), `"Unable to load %S: "`
   (`$FF9741`), `"%S failed returncode %N"` (`$FF9755`), `"**BREAK - CLI"` (`$FF9719`),
   `"CLI error: %S"` (`$FF9BFD`) — confirment un CLI capable de charger+lancer des commandes
   externes et de rapporter les codes retour.

## Phase D — Démarrage du file-handler DF0: au 1er accès ([ABI] + [ROM] + [inféré])

Quand un chemin sur DFx: est référencé pour la 1re fois (p. ex. `Open("DF0:…")` ou l'`Execute` du
startup) :

1. `DeviceProc`/`Open` cherche le `DeviceNode` DF0: dans `di_DevInfo`. Si `dn_Task` est **NULL** :
2. dos **démarre le handler** via `CreateProc` en utilisant `dn_SegList` (= `rn_FileHandlerSegment`,
   handler OFS résident), `dn_GlobalVec`, `dn_StackSize`, `dn_Priority`. Il dépose un **packet de
   démarrage** (`ACTION_STARTUP`) au port du nouveau process, référant le `DeviceNode`/`dn_Startup`
   (répartition exacte des `dp_Arg` = incertitude, cf. `dos-v34-spec.md` §6).
3. Le handler s'initialise : `OpenDevice("trackdisk.device", fssm_Unit, …)` (depuis
   `FileSysStartupMsg`), lit le bloc racine, et **valide le disque** — s'il faut valider, il lance
   le process **disk-validator** (`rn_RestartSeg` ; **[ROM]** `"L:Disk-Validator"` `$FFFAE1`/`$FFFAF5`,
   `"Validator"` `$FFD52D`, `"Error validating disk"` `$FFFDDD`). Puis il boucle en
   `WaitPort/GetMsg` sur son `MsgPort` pour servir les packets.
4. dos pose **`dn_Task` = le `MsgPort` du handler**. Les `Open/Read/Close` suivants sur DF0: sont
   routés vers ce port (cf. `dos-v34-spec.md` §2–§3).

**[ROM]** Gestion d'erreurs/médias du handler (requesters intuition) — chaînes mesurées :
`"Volume"`/`"in unit 0X "`/`"is not validated"`/`"is write protected"`/`"Please replace volume"`/
`"is full"`/`"Not a DOS disk"`/`"No disk present"`/`"has a read/write error"`/`"You MUST replace
volume"`/`"Please insert volume"` ($FF5293..$FF5ABD), `"Error code %N"` (`$FF5025`),
`"Disk corrupt - task held"`/`"Software error - task held"` ($FF4875/$FF4891), boutons
`"Retry"`/`"Cancel"` ($FF4E1C/$FF4E24). Codes retour associés (`dos/dos.i`) : `ERROR_DISK_WRITE_PROTECTED`
214, `ERROR_NOT_A_DOS_DISK` 225, `ERROR_NO_DISK` 226, `ERROR_DISK_FULL` 221, etc.

## Phase E — Charger + lancer UNE commande (flux LoadSeg + Run) ([ABI] + [inféré])

Chemin « ce qu'il faut pour lancer une commande » :

1. Le CLI résout le nom de commande (répertoire courant puis `C:` via `cli_CommandDir`).
2. `LoadSeg(name)` ouvre le fichier **à travers le handler** (packets `FINDINPUT` → `READ` → `END`,
   cf. §2b), lit l'exécutable **hunk**, alloue/relocate, renvoie le **BPTR du 1er segment** (jalon
   projet D2). Le seglist est mémorisé dans `cli_Module`.
3. **Exécution** :
   - **Commande en avant-plan** : lancée sur **le process du CLI lui-même** (pas de nouveau process) —
     dos bascule la pile sur `cli_DefaultStack`, entre dans le segment chargé selon les conventions
     de démarrage (ligne de commande passée en argument, BPTR/registres BCPL ; cf. `dos-v34-spec.md`
     §4), récupère le code retour dans `cli_ReturnCode`.
   - **`RUN` (asynchrone)** : **[ROM]** `"C:RUN"` — un **nouveau** process CLI est créé
     (`CreateProc`) pour exécuter la commande en tâche de fond (`cli_Background` vrai).
4. `UnLoadSeg(seglist)` libère le code en fin d'exécution ; `IoErr()`/`pr_Result2` porte l'erreur
   secondaire éventuelle.

## Résumé de l'ordre (oracle DOS)

```
strap (COLDSTART, pri -60) → bootblock DF0: valide
   → FindResident("dos.library") + InitResident → rt_Init $FF3E94 (init manuel)
      → DosLibrary (dl_Root, dl_GV) + RootNode + DosInfo + jump table + GV BCPL
      → OpenLibrary expansion / ramlib / intuition + OpenDevice timer/console/input
      → table de montage : DeviceNode DFx (handler résident "File System", startup trackdisk),
        CON:, NIL:, L:RAM-HANDLER / L:PORT-HANDLER, assigns LIBS/DEVS/FONTS
   → création du process "Initial CLI" (CON: window, pr_CLI/pr_CIS/pr_COS)
   → Execute ":S/STARTUP-SEQUENCE" (commandes depuis C:)
        └─ 1er accès DF0: → CreateProc(handler, rn_FileHandlerSegment) → ACTION_STARTUP
              → OpenDevice trackdisk + validation (L:Disk-Validator) → dn_Task = port handler
challenge commande : LoadSeg(C:nom) [FINDINPUT/READ/END] → run (CLI ou RUN) → UnLoadSeg
```

## Incertitudes

- **[inféré]** Le point de jonction précis bootblock → dos (qui appelle `FindResident`/`InitResident`,
  et quel est le point d'entrée « boot » rendu par l'init de dos) n'est pas tracé ligne à ligne
  (contrainte clean-room). Cohérent avec le jalon C/M6y mais à confirmer par comportement.
- **[inféré]** L'ordre exact des `OpenLibrary`/montages dans l'init de dos est déduit des chaînes
  présentes et du comportement 1.3 standard, pas d'une trace du code.
- **`ACTION_STARTUP`** : slots `dp_Arg` exacts non figés (cf. `dos-v34-spec.md` §6).
- **[inféré]** Convention d'entrée exacte d'une commande (registres/pile au saut dans le segment,
  format de la ligne d'argument) décrite au niveau comportemental ; à valider sur 1.3 réelle.
- Les phases observables (création process, ouverture/lecture à travers le handler, LoadSeg+run)
  sont prouvables par **boot FS-UAE** + marqueur ; les détails internes BCPL ne le sont pas et
  n'ont pas à l'être pour la réimplémentation (équivalent fonctionnel, pas copie).
