# test-vectors.md — Vecteurs d'oracle (Kickstart 1.3 / V34.5)

> Assertions testables en boîte noire qu'une réimplémentation doit reproduire. **Pas de code.**
> Deux niveaux de provenance, étiquetés sur chaque assertion :
> **[M] = mesuré dans la ROM** `kick34005.A500` (oracle dur, falsifiable par relecture r2) ;
> **[D] = comportement documenté** (ABI publique ; la ROM ne dumpe pas la valeur runtime,
> l'assertion découle du contrat exec V34).
> Config de référence pour les vecteurs runtime : **A500, 512 Ko de RAM chip, aucune extension,
> 68000, région PAL** (sauf mention NTSC).

## A. Image ROM (statique)

- **[M] A1** : `*(ULONG*)$FC0000 = 0x11114EF9` (SSP/ROM-ID+opcode).
- **[M] A2** : `*(ULONG*)$FC0004` = une adresse dans la ROM (PC de reset = coldstart exec = `rt_Init`
  d'exec, cf. B5).
- **[M] A3** : `*(ULONG*)$FC000C = 0x00220005` → version **34.5**. (Interprétation : Kickstart 1.3,
  corroborée par les chaînes `"Release 1.3"` et `"exec 34.2 (28 Oct 1987)"` présentes en ROM.)
- **[M] A4** : exactement **24 ROMTags** valides (matchword `0x4AFC` + `rt_MatchTag` auto-référent)
  (liste dans `module-map.md`). Tous ont `rt_Version = 34`.
- **[M] A5** : pied de ROM — champ de taille `0x00040000` (= 256 Ko) dans les derniers longwords.

## B. ROMTags — assertions par champ (toutes **[M]**)

- **[M] B1** : flags des 5 modules RTF_AUTOINIT (bit 0x80) : expansion `0x81`, ramlib `0x80`,
  audio `0x81`, intuition `0x81`, mathffp `0x81`. **Aucun autre** module n'a le bit AUTOINIT.
- **[M] B2** : **aucun** module n'a RTF_SINGLETASK (0x02) ni RTF_AFTERDOS (0x04). Seuls
  COLDSTART (0x01) et AUTOINIT (0x80) apparaissent.
- **[M] B3** : modules à `rt_Flags = 0x00` (aucun bit de timing) : exec, workbench.task, dos.
  Plus ramlib à `0x80` (AUTOINIT sans COLDSTART). → ces 4 ne sont pas démarrés par
  `InitCode(RTF_COLDSTART)`.
- **[M] B4** : `rt_Type` : NT_LIBRARY(9) = exec, expansion, ramlib, graphics, layers, intuition,
  mathffp, dos, romboot (9 modules) ; NT_DEVICE(3) = keyboard, gameport, timer, audio, input,
  console, trackdisk (7) ; NT_RESOURCE(8) = potgo, keymap, cia, disk, misc (5) ;
  NT_TASK(1) = workbench.task (1) ; NT_UNKNOWN(0) = alert.hook, strap (2).
- **[M] B5** : `rt_Init` d'exec = PC de reset (A2). `rt_EndSkip` d'exec = adresse de la ROMTag
  alert.hook (la tag suivante dans la ROM).
- **[M] B6** : priorités (octet signé) exactes : exec 120, expansion 110, potgo 100, keymap 100,
  cia 80, disk 70, misc 70, ramlib 70, graphics 65, keyboard 60, gameport 60, timer 50, audio 40,
  input 40, layers 31, console 20, trackdisk 20, intuition 10, alert.hook 5, mathffp 0,
  workbench.task 0, dos 0, romboot **-40** (octet `0xD8`), strap **-60** (octet `0xC4`).

## C. Ordre d'initialisation (oracle de séquence) **[M pour les clés de tri]**

Deux séquences distinctes à ne pas confondre : (a) `ResModules` = TOUS les résidents valides
(les flags RTF ne filtrent QUE `InitCode`, pas l'appartenance à la liste) ; (b) la passe
`InitCode(RTF_COLDSTART)` = sous-ensemble effectivement démarré.

- **[M] C1 — `ResModules` (24 entrées)** : triée par **`rt_Pri` décroissant, puis adresse ROM
  croissante** pour les ex-æquo (ordre de position dans l'image). Ordre exact :

  1 exec · 2 expansion · 3 potgo · 4 keymap · 5 cia · 6 disk · 7 misc · 8 ramlib · 9 graphics ·
  10 keyboard · 11 gameport · 12 timer · 13 audio · 14 input · 15 layers · 16 console ·
  17 trackdisk · 18 intuition · 19 alert.hook · 20 mathffp · **21 workbench.task · 22 dos** ·
  23 romboot · 24 strap.
  (Trio pri 0 par position croissante dans la ROM : mathffp < workbench.task < dos.)

- **[M] C2 — passe `InitCode(RTF_COLDSTART)` (20 entrées)** : `ResModules` **moins** exec (noyau,
  non démarré par InitCode), ramlib (AUTOINIT sans COLDSTART), workbench.task et dos (`rt_Flags=0`) :

  expansion · potgo · keymap · cia · disk · misc · graphics · keyboard · gameport · timer · audio ·
  input · layers · console · trackdisk · intuition · alert.hook · mathffp · romboot · strap.

- **[M] C3** : vérification des ex-æquo (le tri DOIT produire ces ordres) : pri100 potgo<keymap ;
  pri70 disk<misc<ramlib ; pri60 keyboard<gameport ; pri40 audio<input ; pri20 console<trackdisk.
- **[D] C4** : la passe `InitCode(RTF_SINGLETASK,0)` n'initialise aucun module (liste vide) ;
  la passe `InitCode(RTF_AFTERDOS,…)` non plus. Observable : rien ne doit s'initialiser « avant
  multitâche » ni « après DOS » via le mécanisme de flags.

## D. Tables d'auto-init (toutes **[M]**, oracles durs)

- **[M] D1** `dataSize` (taille de base allouée) : expansion `0x1C8` (456) · ramlib `0x0B2` (178)
  · audio `0x27A` (634) · intuition `0x564` (1380) · mathffp `0x022` (34 = sizeof struct Library).
- **[M] D2** nombre de vecteurs LVO exposés : expansion **25** · ramlib **11** · audio **6**
  · intuition **78** · mathffp **16**.
- **[M] D3** encodage de la table `vectors` : expansion & intuition = **LONG absolu** (terminateur
  `0xFFFFFFFF`) ; ramlib, audio, mathffp = **WORD relatif** (1er mot `0xFFFF`, terminateur `0xFFFF`).
- **[M] D4** `structure` (données InitStruct) : NULL **uniquement** pour intuition ; présent pour
  les 4 autres.
- **[M] D5** audio.device expose exactement 6 LVO = les 4 standard (Open/Close/Expunge/réservé)
  + 2 spécifiques device (BeginIO/AbortIO). mathffp expose 16 LVO = 4 standard + 12 fonctions
  mathématiques simple-précision.

## E. ExecBase après init (runtime) **[D sauf indication]**

- **[D] E1** : `*(ULONG*)$00000004` pointe sur `ExecBase` (valeur non prédictible mais non nulle,
  dans la RAM chip < `MaxLocMem`).
- **[D] E2** : `ExecBase.ChkBase` (+0x26) = `~(*(ULONG*)4)` (complément à un du pointeur base).
- **[D] E3** : `ExecBase.LibNode.lib_Version` (+0x14) = **34** ; `lib_Revision` (+0x16) = 2 ;
  `LN_Type` (+0x08) = `NT_LIBRARY` (9) ; `LN_Name` → `"exec.library"`.
- **[D] E4** : `AttnFlags` (+0x128) = **0x0000** sur 68000 pur (aucun bit 68010/020/030/040/
  68881/882 posé). Sur CPU supérieur, bits correspondants posés.
- **[D] E5** : `VBlankFrequency` (+0x212) = **50** en PAL (60 en NTSC) ;
  `PowerSupplyFrequency` (+0x213) = **50** PAL / 60 NTSC.
- **[D] E6** : `MaxLocMem` (+0x3E) = sommet de la RAM chip = **0x00080000** pour 512 Ko chip
  (0x00200000 si 2 Mo chip).
- **[D] E7** : toutes les listes système d'ExecBase sont des `struct List` valides (vides juste
  après init, puis peuplées) : `MemList`, `ResourceList`, `DeviceList`, `IntrList`, `LibList`,
  `PortList`, `TaskReady`, `TaskWait`, `SemaphoreList`. Une `List` vide vérifie
  `lh_Head == &lh_Tail && lh_TailPred == &lh_Head` (en-tête auto-référent).
- **[D] E8** : `ResModules` (+0x12C) ≠ NULL et énumère les 24 résidents dans l'ordre de C1.
- **[D] E9** : `IDNestCnt`/`TDNestCnt` (+0x126/+0x127) reviennent à **-1** au repos (aucun
  Disable/Forbid actif ; convention : -1 = « hors section critique »).
- **[D] E10** : la zone au-delà de `KickCheckSum` (~0x22E) n'est pas un champ ExecBase en V34
  (cf. exec-spec.md §2). Une implémentation 1.3 ne doit rien y supposer.

## F. Liste mémoire (A500 512 Ko chip, sans extension) **[D]**

- **[D] F1** : `MemList` contient **exactement un** `MemHeader` (RAM chip). Pas de nœud fast.
- **[D] F2** : ce `MemHeader` a `mh_Attributes = MEMF_CHIP|MEMF_PUBLIC` (= **0x3**) en V34
  (les bits `MEMF_LOCAL` 0x100 et `MEMF_24BITDMA` 0x200 sont des ajouts **V36**, absents en 1.3) ;
  `mh_Upper` ≈ `0x00080000` ; `mh_Lower` au-dessus de la zone basse réservée (vecteurs CPU +
  ExecBase + piles). `LN_Type = NT_MEMORY (10)`.
- **[D] F3** : `AvailMem(MEMF_CHIP)` > 0 ; `AvailMem(MEMF_FAST)` = 0 (aucune RAM fast).
- **[D] F4** : granularité d'allocation = **8 octets** (AllocMem arrondit vers le haut).

## G. Jump table exec **[M + D]**

- **[M] G1** : les offsets LVO des primitives sont utilisés dans la ROM aux valeurs canoniques :
  Forbid -132, Permit -138, AllocMem -198, FreeMem -210, AddHead -240, AddTail -246, Remove -252,
  FindName -276 (sites d'appel recensés dans exec-spec.md §3).
- **[M] G2** : l'offset `JSR/JMP d16(A6)` le plus profond de toute la ROM est **-636** ; l'usage
  des LVO exec est dense et contigu jusqu'à ~ -588.
- **[D] G3** : la jump table exec V34 compte ~**102** entrées (`lib_NegSize` ≈ 612), soit bien
  moins que 2.0/3.x. Les LVO ≥ -618 (AddMemList/CopyMem/CopyMemQuick/Cache*/pools…) **ne doivent
  pas exister** dans une réimplémentation V34.
- **[D] G4** : chaque entrée de jump table = 6 octets (`JMP abs.l` `0x4EF9` + adresse 32 bits) ;
  `lib_Sum`/`SumLibrary` recalcule un checksum cohérent de la table.

## H. Limites / zones à confirmer par la piste implémentation
- Section E (ExecBase runtime) et F (liste mémoire) sont **[D]** : non lisibles dans la ROM
  statique. À valider sur émulateur/matériel réel contre une Kickstart 1.3 authentique.
- G3 : compte LVO exec à ±1 sur la dernière entrée ; recouper `exec_lib.fd` **V34** pour figer.
- E6/F2 : `MaxLocMem` et `mh_Upper` dépendent de la quantité de RAM chip réelle de la config testée.

## Relecture clean-room

Relecture du 2026-10-29.

- [x] Aucune suite d'instructions transcrite, aucun pseudo-code : uniquement des assertions boîte
  noire (valeurs, ordres, tailles).
- [x] **Corrigé** : retirées les adresses ROM du PC de reset (A2), de `rt_Init`/`rt_EndSkip` d'exec
  (B5) et des trois ROMTags de priorité 0 (C1), ainsi que le renvoi aux « offsets » des tags ; les
  assertions sont conservées sous forme relative (égalité PC de reset = `rt_Init`, ordre de position).
- [x] Restent : en-tête `0x11114EF9`, version `0x00220005`, taille `0x00040000` (format d'image vérifié
  par `romtool`), offsets publics d'ExecBase, LVO, constantes `MEMF_*`/`NT_*`/`RTF_*`. G2 cite le mode
  d'adressage des appels LVO uniquement pour borner la jump table (aucune instruction recopiée).
