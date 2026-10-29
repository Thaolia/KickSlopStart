# boot-sequence.md — Séquence de démarrage (Kickstart 1.3 / V34.5)

> Description **comportementale** (algorithme, ordre des opérations). Aucun opcode ni listing
> reproduit. Faits ancrés sur la ROM : vecteurs de reset, `rt_Init` d'exec, flags/priorités des
> résidents (cf. `module-map.md`). Le mécanisme d'`InitCode`/`InitResident` est décrit d'après
> l'ABI publique (`exec/resident.i`, AutoDocs exec V34) ; les points **inférés** (non vérifiés par
> trace de code, car la piste « dirty » ne transcrit pas d'instructions) sont marqués *(inféré)*.

## Phase 0 — Reset matériel (vecteur 68000)

Au reset, le 68000 lit deux longwords aux adresses physiques **$000000** (SSP initial) et
**$000004** (PC initial). Au tout début, la logique d'**overlay** de l'Agnus/Gary mappe la ROM
($FC0000) sur l'adresse $000000, de sorte que :

- `*(ULONG*)$000000` = `0x11114EF9` → SSP initial. Les deux octets de poids fort `0x1111`
  servent aussi de mot de reconnaissance ROM ; `0x4EF9` est l'opcode qui, exécuté, poursuit vers
  le coldstart (artefact du double usage du longword).
- `*(ULONG*)$000004` = une adresse dans la ROM → PC initial = **coldstart exec** = `rt_Init` de la
  ROMTag exec. Le CPU démarre donc directement dans exec ; exec n'est jamais « initialisé » par le
  balayage des résidents (cf. `module-map.md`).

## Phase 1 — Coldstart exec : amorçage CPU/matériel minimal *(inféré au niveau détail)*

Ordre comportemental :

1. Passer en mode superviseur, masquer toutes les interruptions (SR niveau 7), charger un SSP de
   travail provisoire.
2. Mettre les custom chips dans un état neutre : couper DMA et interruptions (`DMACON`, `INTENA`,
   `INTREQ` effacés), arrêter l'audio, etc. — mise au silence du matériel avant tout.
3. Déterminer la configuration CPU (le résultat sera publié dans `ExecBase.AttnFlags`) et la
   fréquence secteur/VBlank (PAL 50 Hz / NTSC 60 Hz → `VBlankFrequency`, `PowerSupplyFrequency`).
4. Lever l'overlay ROM (via CIA) pour exposer la RAM chip en bas de l'espace d'adressage, puis
   **dimensionner la RAM** (chip, et fast/ranger si présente) par sondage.
5. Décider de l'emplacement d'`ExecBase`. Vérifier d'abord les vecteurs de **survie au reset**
   (`ColdCapture`/`KickMemPtr`/`KickTagPtr`) : si une `ExecBase` valide subsiste et que son
   checksum est correct, on peut la réutiliser ; sinon on en construit une neuve.

## Phase 2 — Construction d'ExecBase et du noyau

1. Allouer/poser la structure `ExecBase` en RAM chip et écrire son pointeur en **`*(ULONG*)$000004`**
   (= `AbsExecBase`/`SysBase`). Poser le complément `ChkBase = ~SysBase` (offset +0x26).
2. Initialiser le nœud de library d'exec : `lib_Version = 34`, `lib_Revision` (rév. 2),
   `lib_IdString` → `"exec 34.2 …"`, type `NT_LIBRARY`, et **construire la jump table LVO d'exec**
   (vecteurs négatifs, pas de 6 octets ; cf. `exec-spec.md`). exec se bootstrappe lui-même : la
   jump table n'est pas une table auto-init statique présente dans la ROM *(vérifié : aucune table
   `MakeFunctions` d'exec parsable dans la plage du module exec)*.
3. Initialiser à vide toutes les listes système d'`ExecBase` : `MemList`, `ResourceList`,
   `DeviceList`, `IntrList`, `LibList`, `PortList`, `TaskReady`, `TaskWait`, `SemaphoreList`,
   les 5 `SoftInts`, et les champs de scheduling (`Quantum`, `ThisTask=NULL`, nest counts).
4. Construire le premier `MemHeader` à partir de la RAM sondée et l'ajouter à `MemList`
   (RAM chip : attributs `MEMF_CHIP|MEMF_PUBLIC` = `0x3` en V34 — `MEMF_LOCAL`/`MEMF_24BITDMA`
   sont des bits **V36**, pas V34 ; cf. `test-vectors.md`).
5. Installer les 16 **autovecteurs d'interruption** (`ExecBase.IntVects[16]`) et les gestionnaires
   de traps/exceptions. Publier `AttnFlags` (config CPU/FPU) et `AttnResched`.

## Phase 3 — Balayage des résidents et construction de la liste `ResModules`

1. Balayer la ROM (et, si présentes, les ROM d'extension/diag) de l'adresse basse vers l'adresse
   haute à la recherche du **matchword `0x4AFC`** suivi d'un `rt_MatchTag` pointant sur lui-même
   (filtre anti-faux-positif). Chaque Resident valide est ajouté à une liste de travail dans
   l'ordre d'adresse **croissante**.
2. **Trier** cette liste par `rt_Pri` **décroissant** ; les ex-æquo conservent l'ordre de balayage
   (adresse croissante). Le résultat est publié dans `ExecBase.ResModules` (tableau de pointeurs
   terminé). → L'ordre final est exactement celui du tableau de `module-map.md`, de exec (pri 120)
   à strap (pri -60).

## Phase 4 — Initialisation pilotée par `InitCode` (passes par flags de timing)

`InitCode(startClass, version)` parcourt `ResModules` dans l'ordre (priorité décroissante) et,
pour chaque résident sélectionné par `startClass`, appelle `InitResident` :

- `InitResident` teste `rt_Flags & RTF_AUTOINIT` : si posé, il appelle `MakeLibrary` avec la table
  auto-init (`dataSize`/`vectors`/`structure`/`initFunction` — cf. `module-map.md`), ajoute la base
  à la bonne liste (`LibList`/`DeviceList`), puis exécute `initFunction`. Sinon, il saute
  directement dans `rt_Init` (code d'init manuel qui se charge d'allouer et de publier sa base).

Dans CETTE ROM, seuls les bits de timing suivants sont présents :

1. `InitCode(RTF_SINGLETASK, 0)` — **aucun module** concerné (aucun flag 0x02). Passe sans effet.
2. Démarrage du multitâche : création de la tâche initiale, activation du scheduler, autorisation
   des interruptions. *(inféré)*
3. `InitCode(RTF_COLDSTART, 0)` — **passe principale**. Initialise, dans l'ordre de priorité :
   expansion → potgo → keymap → cia → disk → misc → graphics → keyboard → gameport → timer →
   audio → input → layers → console → trackdisk → intuition → alert.hook → mathffp → romboot →
   strap. (ramlib, workbench.task, dos n'ont PAS le bit COLDSTART → non démarrés ici.)
4. `InitCode(RTF_AFTERDOS, …)` — **aucun module** concerné (aucun flag 0x04) dans la ROM.

### Rôles des modules de fin de chaîne

- **alert.hook** (pri 5, type UNKNOWN) : hook installé tôt pour l'affichage des Guru Meditation
  (recovery/alert) ; mis en place avant les modules de plus basse priorité.
- **ramlib.library** (AUTOINIT, sans COLDSTART) : service de chargement des bibliothèques/devices
  disque (`LDDemon`). N'étant pas marqué COLDSTART, il est amené par un chemin dédié / à la demande
  plutôt que par la passe `InitCode(RTF_COLDSTART)`. *(inféré)*
- **romboot.library** (pri -40) : gère l'autoboot / le boot depuis cartes d'extension (expansion.library).
- **strap** (pri -60, type UNKNOWN, « bootstrap ») : **dernier** résident COLDSTART. C'est lui qui
  cherche un périphérique amorçable, lit le boot-block, et met en route le côté DOS. Il amène
  explicitement **dos.library** et **workbench.task** (tous deux `rt_Flags=0`, donc non auto-démarrés)
  dans le cadre de l'amorçage du système de fichiers. *(inféré)*

## Résumé de l'ordre global (oracle)

```
reset → coldstart exec (PC de reset = rt_Init d'exec)
      → silence matériel + sizing RAM + AttnFlags/VBlankFreq
      → construction ExecBase (@*(ULONG*)4) + jump table exec + listes + MemHeader chip + IntVects
      → scan ROM (match 0x4AFC) → tri (pri desc, adresse asc) → ResModules
      → InitCode(SINGLETASK)  [vide]
      → démarrage multitâche
      → InitCode(COLDSTART)   [expansion…strap, dans l'ordre de module-map.md]
          └─ strap (dernier) : boot disque → dos.library + workbench.task
      → InitCode(AFTERDOS)    [vide]
```

## Incertitudes

- Le détail des phases 1 et 2 (ordre fin des registres custom touchés, mécanisme exact de sondage
  RAM, placement précis d'ExecBase vs survie au reset) est **inféré** du comportement standard exec
  V34 et non vérifié ligne à ligne (contrainte clean-room : pas de transcription de code).
- Le point exact où ramlib, dos et workbench.task sont initialisés (chemin dédié vs amorçage strap)
  est inféré de leurs flags (`rt_Flags` sans bit de timing) ; la piste implémentation devra le
  confirmer par le comportement observable (ouverture de `dos.library` possible seulement après boot).

## Relecture clean-room

Relecture du 2026-10-29.

- [x] Aucune suite d'instructions 68000 transcrite ni paraphrasée, aucun extrait de désassemblage.
  Les phases 1-4 sont un ordre comportemental de haut niveau (marqué *(inféré)* là où il n'est pas
  observé), conforme à l'ABI publique `exec/resident.i` et aux AutoDocs, pas un déroulé du code ROM.
- [x] **Corrigé** : retirées les adresses ROM du point d'entrée du coldstart (valeur du PC de reset,
  titre de la phase 1, schéma « oracle ») et les bornes de la plage du module exec ; remplacées par
  « adresse dans la ROM » / « plage du module exec ».
- [x] Restent : adresses matérielles ($000000/$000004, overlay, base ROM $FC0000), en-tête
  `0x1111`/`0x4EF9`, offset public `ChkBase` (+0x26), constantes `MEMF_*`.
