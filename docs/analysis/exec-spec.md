# exec-spec.md — Spec d'ABI d'exec.library (V34 / Kickstart 1.3)

> Deux provenances, étiquetées par champ :
> **[ROM]** mesuré dans `kick34005.A500` ; **[ABI]** layout/offsets issus de l'ABI publique
> documentée (`exec/execbase.i`, `exec/libraries.i`, `exec/nodes.i`, `exec_lib.fd` V34, AutoDocs
> exec). exec n'étant pas RTF_AUTOINIT, sa base n'a pas de `dataSize` ni de table de vecteurs
> statique en ROM : le layout d'ExecBase et la liste des LVO relèvent de l'ABI publique, corroborés
> par la ROM là où c'est possible. Aucun opcode n'est reproduit.

## 1. Point d'ancrage : AbsExecBase

- **[ABI]** `AbsExecBase = *(struct ExecBase **)$00000004`. Après init, le longword à l'adresse
  physique **$000004** contient le pointeur sur `ExecBase` (le vecteur de reset PC n'y est visible
  que durant l'overlay ROM du tout début, cf. `boot-sequence.md`).
- **[ABI]** Intégrité : `ExecBase.ChkBase` (offset +0x26) = `~AbsExecBase` (complément à un).
  `SumExecBase`/checksum valident la cohérence base ↔ complément.

## 2. Layout de struct ExecBase  **[ABI — `exec/execbase.i`]**

ExecBase débute par un nœud de library (`struct Library`, 34 octets = `0x22`), lui-même préfixé
d'un `struct Node` (14 octets). Offsets (décimal entre parenthèses) :

### 2a. En-tête `struct Library` (0x00..0x21)
| Off | Taille | Champ | Note |
|----:|:------:|-------|------|
| 0x00 | APTR | `LN_Succ` | nœud : successeur |
| 0x04 | APTR | `LN_Pred` | nœud : prédécesseur |
| 0x08 | UBYTE | `LN_Type` | = `NT_LIBRARY` (9) |
| 0x09 | BYTE | `LN_Pri` | |
| 0x0A | APTR | `LN_Name` | → `"exec.library"` |
| 0x0E | UBYTE | `lib_Flags` | |
| 0x0F | UBYTE | `lib_pad` | |
| 0x10 | UWORD | `lib_NegSize` | taille de la jump table (octets) = nbLVO×6 |
| 0x12 | UWORD | `lib_PosSize` | taille des données (= sizeof ExecBase) |
| 0x14 | UWORD | `lib_Version` | **= 34** [ROM, cf. en-tête] |
| 0x16 | UWORD | `lib_Revision` | = 2 (exec 34.2) |
| 0x18 | APTR | `lib_IdString` | → `"exec 34.2 (28 Oct 1987)"` [ROM $FC0018] |
| 0x1C | ULONG | `lib_Sum` | checksum de la jump table |
| 0x20 | UWORD | `lib_OpenCnt` | |

### 2b. Champs ExecBase spécifiques
| Off (déc) | Taille | Champ | Rôle |
|----------:|:------:|-------|------|
| 0x22 (34) | UWORD | `SoftVer` | version logicielle |
| 0x24 (36) | WORD | `LowMemChkSum` | |
| 0x26 (38) | ULONG | `ChkBase` | = `~AbsExecBase` |
| 0x2A (42) | APTR | `ColdCapture` | vecteur survie-au-reset (froid) |
| 0x2E (46) | APTR | `CoolCapture` | |
| 0x32 (50) | APTR | `WarmCapture` | |
| 0x36 (54) | APTR | `SysStkUpper` | haut de pile superviseur |
| 0x3A (58) | APTR | `SysStkLower` | bas de pile superviseur |
| 0x3E (62) | ULONG | `MaxLocMem` | sommet RAM chip |
| 0x42 (66) | APTR | `DebugEntry` | |
| 0x46 (70) | APTR | `DebugData` | |
| 0x4A (74) | APTR | `AlertData` | |
| 0x4E (78) | APTR | `MaxExtMem` | sommet RAM d'extension |
| 0x52 (82) | UWORD | `ChkSum` | checksum de la zone IntVects |
| 0x54 (84) | 16×`IntVector` | `IntVects[16]` | 16 autovecteurs d'interruption, **12 octets chacun** (`iv_Data`, `iv_Code`, `iv_Node`) → 192 octets, fin à 0x114 |
| 0x114 (276) | APTR | `ThisTask` | tâche courante |
| 0x118 (280) | ULONG | `IdleCount` | |
| 0x11C (284) | ULONG | `DispCount` | |
| 0x120 (288) | UWORD | `Quantum` | quantum scheduler |
| 0x122 (290) | UWORD | `Elapsed` | |
| 0x124 (292) | UWORD | `SysFlags` | |
| 0x126 (294) | BYTE | `IDNestCnt` | compteur de nesting Disable |
| 0x127 (295) | BYTE | `TDNestCnt` | compteur de nesting Forbid |
| 0x128 (296) | UWORD | `AttnFlags` | capacités CPU/FPU |
| 0x12A (298) | UWORD | `AttnResched` | |
| 0x12C (300) | APTR | `ResModules` | → liste des résidents (cf. boot-sequence) |
| 0x130 (304) | APTR | `TaskTrapCode` | |
| 0x134 (308) | APTR | `TaskExceptCode` | |
| 0x138 (312) | APTR | `TaskExitCode` | |
| 0x13C (316) | ULONG | `TaskSigAlloc` | |
| 0x140 (320) | UWORD | `TaskTrapAlloc` | |
| 0x142 (322) | `List` (14) | `MemList` | liste des `MemHeader` |
| 0x150 (336) | `List` (14) | `ResourceList` | |
| 0x15E (350) | `List` (14) | `DeviceList` | |
| 0x16C (364) | `List` (14) | `IntrList` | |
| 0x17A (378) | `List` (14) | `LibList` | |
| 0x188 (392) | `List` (14) | `PortList` | |
| 0x196 (406) | `List` (14) | `TaskReady` | tâches prêtes |
| 0x1A4 (420) | `List` (14) | `TaskWait` | tâches en attente |
| 0x1B2 (434) | 5×`SoftIntList` (16) | `SoftInts[5]` | 80 octets, fin à 0x202 |
| 0x202 (514) | 4×LONG | `LastAlert[4]` | 16 octets |
| 0x212 (530) | UBYTE | `VBlankFrequency` | 50 (PAL) / 60 (NTSC) |
| 0x213 (531) | UBYTE | `PowerSupplyFrequency` | 50 / 60 |
| 0x214 (532) | `List` (14) | `SemaphoreList` | sémaphores signalés |
| 0x222 (546) | APTR | `KickMemPtr` | survie-au-reset : liste mémoire |
| 0x226 (550) | APTR | `KickTagPtr` | survie-au-reset : ROMTags supplémentaires |
| 0x22A (554) | APTR | `KickCheckSum` | checksum des deux précédents |

**Frontière V34** : en V34, les champs significatifs d'ExecBase **s'arrêtent à `KickCheckSum`
(fin ≈ 0x22E, 558 octets)**. Tout ce qui suit dans les ROM 2.0/3.x — `ex_EClockFrequency`,
`ex_CacheControl`, `ex_TaskID`, `ex_PuddleSize`, `ex_PoolThreshold`, `ex_PublicMemList`,
`ex_MMULock`, `ex_MemHandlers`/`ex_MemHandler` — **n'existe pas / n'est pas utilisé en V34**.
C'est un delta que la piste implémentation ne peut pas découvrir seule : ne pas réserver ni
exposer ces champs pour une cible 1.3.

## 3. Jump table LVO  **[ABI, corroboré ROM]**

- **[ABI]** Chaque entrée de la jump table occupe **6 octets** : opcode `JMP abs.l` (`0x4EF9`)
  + adresse 32 bits de la fonction. Les entrées sont à des **offsets négatifs** depuis la base :
  `-6, -12, -18, …`. Appel standard : `JSR offset(A6)` avec A6 = base de library (= SysBase pour
  exec). LVO *n* ↔ offset `-6·n`.
- **[ABI]** Les 4 premières entrées sont communes à toute library : `-6 Open`, `-12 Close`,
  `-18 Expunge`, `-24` réservé. Les fonctions propres à exec commencent à `-30` (bias 30).

### Offsets LVO des primitives demandées (stables toutes versions, **confirmés utilisés dans la ROM**)
| LVO off | Fonction | Sites d'appel mesurés [ROM] |
|--------:|----------|:---------------------------:|
| -132 | `Forbid` | 19 |
| -138 | `Permit` | 43 |
| -198 | `AllocMem` | 33 |
| -210 | `FreeMem` | 31 |
| -240 | `AddHead` | 8 |
| -246 | `AddTail` | 16 |
| -252 | `Remove` | 7 |
| -276 | `FindName` | 14 |

(Autres repères confirmés [ROM] : `Supervisor` -30, `InitCode` -72, `FindResident` -96,
`InitResident` -102, `Alert` -108, `Disable` -120, `Enable` -126, `Wait` -318, `Signal` -324,
`OldOpenLibrary` -408, `CloseLibrary` -414, `OpenDevice` -444, `DoIO` -456, `OpenResource` -498,
`OpenLibrary` -552, `InitSemaphore` -558, `ObtainSemaphore` -564.)

### Taille de la jump table exec en V34  **[ROM + ABI]**
Mesure ROM : un histogramme de tous les appels `JSR/JMP d16(A6)` (opcodes `0x4EAE`/`0x4EEE`,
déplacement négatif multiple de 6) sur toute la ROM montre un usage **dense et contigu de LVO 1
(-6) jusqu'à LVO ~98 (-588)** — signature des fonctions exec appelées par tous les modules —
puis une **queue éparse** LVO 101..106 (-606 à -636, 1 à 3 sites chacun). L'offset le plus
profond observé **dans toute la ROM** est **-636** (LVO 106).

Interprétation :
- La jump table exec V34 comporte de l'ordre de **~102 entrées** (LVO -6..-612, `lib_NegSize`
  ≈ 612), se terminant côté ABI par le bloc sémaphores signalés + `SumKickData`.
- La queue -618..-636 observée dans la ROM n'est **pas** exec : notamment -636 correspondrait à
  `CacheClearU`, **impossible pour exec sur un 68000 sans cache** → ces appels visent la base
  d'une AUTRE library (A6 ≠ SysBase à ces sites). Ils ne prouvent donc pas la présence de
  `AddMemList`/`CopyMem`/`CopyMemQuick` dans l'exec V34.
- Incertitude résiduelle : la frontière exacte de la table (fin à -606 `RemSemaphore` vs -612
  `SumKickData`) est à ±1 entrée ; les ancrages fermes ci-dessus (jusqu'à `OpenLibrary` -552,
  et les primitives demandées) sont certains.

### Delta V34 → 2.0/3.x (fonctions ABSENTES de la jump table V34)
La jump table exec V34 est **nettement plus courte** que celle des ROM 2.0/3.x. Les fonctions
suivantes sont des ajouts postérieurs — **ne pas** les exposer pour une cible 1.3 :
`AddMemList` (-618, V36), `CopyMem` (-624, V36), `CopyMemQuick` (-630, V36),
`CacheClearU`/`CacheClearE`/`CacheControl` (-636/-642/-648, V37, sans objet sur 68000),
`CreateIORequest`/`CreateMsgPort` (… amiga.lib en réalité), `CachePreDMA`/`CachePostDMA`,
`CreatePool`/`DeletePool`/`AllocPooled`/`FreePooled` (-654.., V39), `AddMemHandler`/`RemMemHandler`
(V39), `ObtainQuickVector`, `StackSwap`, `ColdReboot` (-726), `TaggedOpenLibrary` (offset négatif
privé V36). La piste implémentation doit refuser/ignorer ces LVO pour rester fidèle à V34.

## 4. Comportement observable des primitives  **[ABI AutoDocs exec V34]**

### Gestion mémoire
- `AllocMem(size D0, requirements D1) → D0` : alloue depuis la `MemList` un bloc de `size` octets
  (arrondi à l'aligne mémoire, **8 octets** sur Amiga) satisfaisant les bits `MEMF_*` de `D1`.
  Retourne l'adresse ou **NULL** si échec. **Bits `MEMF_*` disponibles en V34** (`exec/memory.i`) :
  `MEMF_PUBLIC` 0x1, `MEMF_CHIP` 0x2, `MEMF_FAST` 0x4, `MEMF_CLEAR` 0x10000 (bloc mis à zéro),
  `MEMF_LARGEST` 0x20000. **Delta** : `MEMF_LOCAL` 0x100, `MEMF_24BITDMA` 0x200, `MEMF_REVERSE`
  0x40000, `MEMF_TOTAL` 0x80000 sont des ajouts **V36** ; `MEMF_KICK` 0x400 est **V39** — aucun
  n'existe en V34. La sélection parcourt les `MemHeader` par priorité de nœud décroissante ;
  pour un bloc satisfaisant plusieurs attributs, le premier `MemHeader` compatible gagne.
- `FreeMem(addr A1, size D0)` : rend le bloc exact (adresse+taille) à son `MemHeader`, fusionne
  avec les régions libres adjacentes. **La taille passée doit être identique** à celle de
  l'allocation (pas de header de taille implicite).
- Invariant : granularité/alignement **8 octets** ; `AvailMem(req D1)` somme le libre des headers
  compatibles (`MEMF_LARGEST` donne le plus grand bloc contigu, pas la somme).

### Listes doublement chaînées (`struct List` / `struct Node`)
- `AddHead(list A0, node A1)` : insère `node` en tête. `AddTail(list A0, node A1)` : en queue.
- `Remove(node A1)` : retire un nœud (doit déjà être chaîné ; recâble `LN_Succ`/`LN_Pred`).
- `Enqueue(list, node)` : insertion triée par `LN_Pri` décroissant (insertion en fin de la plage
  de même priorité → c'est le mécanisme du tri des résidents, cf. boot-sequence).
- `FindName(list A0, name A1) → D0` : recherche le premier nœud dont `LN_Name` = la chaîne `name`
  (comparaison sensible à la casse), **à partir du premier nœud** ; appelée sur un nœud, elle peut
  reprendre la recherche depuis la suite. Retourne le nœud ou **NULL**.

### Exclusion mutuelle
- `Forbid()` / `Permit()` : incrémentent/décrémentent `TDNestCnt`. Forbid interdit le
  rescheduling (coopératif) tant que le compteur n'est pas revenu à son état initial ; **imbricables**.
- `Disable()` / `Enable()` : interdisent les interruptions via `IDNestCnt` ; imbricables.
  Règle : garder les sections Disable **très courtes**.

## 5. Incertitudes
- Le layout d'ExecBase (section 2) est de l'ABI publique ; non vérifiable champ par champ dans la
  ROM (structure RAM runtime). La **frontière V34 à ~0x22E** est le point le plus important du delta.
- Compte de LVO exec : ~102 (±1 sur la queue). **RÉSOLU** par le NDK `exec_lib.fd` V34 →
  **105 vecteurs, `lib_NegSize` = `$276`**, frontière à `CopyMemQuick` (-630) ; `AddMemList`/`CopyMem`/
  `CopyMemQuick` sont V33 (donc présents en V34), contrairement à l'inférence ci-dessous. Voir
  `docs/exec-lvo-table.md`. L'histogramme ROM avait sous-estimé la queue. Pour figer exactement la dernière entrée, la piste
  implémentation peut recouper le `exec_lib.fd` **V34** officiel ; les offsets des primitives
  demandées sont certains et confirmés par usage dans la ROM.
