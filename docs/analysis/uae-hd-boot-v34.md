# uae-hd-boot-v34.md — démarrage et montage depuis une carte à DiagArea (cas « uaehf » de FS-UAE)

> Piste ANALYSE (« dirty »). Sources : ROM `kick34005.A500` (exec 34.2, expansion 34.1, romboot 34.1,
> strap 34.4, dos 34.3) lue sous radare2 ; sondes boîte noire sur la vraie ROM sous FS-UAE 3.2.35
> (`tests/bootlist.s`, `tests/adn.s`, `tests/cfgdev2.s`, vecteurs §7) ; code source GPL de FS-UAE 3.2.35
> (`src/filesys.cpp`, `src/filesys.asm` — logiciel indépendant de la ROM) pour le côté émulateur.
> On décrit le **quoi** ; aucune suite d'instructions transcrite, aucune adresse de routine.
>
> Légende : **[R]** analyse ROM · **[S]** sonde · **[U]** source FS-UAE · **[D]** doc publique.
> Prérequis : `autoconfig-v34.md` (ConfigChain, DiagArea, `er_Reserved0c`, MakeDosNode/AddDosNode).

---

## 0. Réponse courte : pourquoi « rien n'apparaît » sur notre ROM

Sur la vraie 1.3, la DiagPoint de la carte UAE **ne fait presque rien** : elle construit une **ROMTag**
(`uaehf.device`, RTF_AUTOINIT|RTF_COLDSTART, NT_DEVICE) dans la **copie RAM de sa DiagArea** (à
`copie + $10`) et rend D0 = 1 **[U]**. C'est **romboot.library** (résident COLDSTART pri −40) qui, à son
init, cherche cette ROMTag dans la copie de DiagArea de chaque carte configurée et l'**InitResident()** **[R]**.
L'init de `uaehf.device` (code UAE) ouvre alors expansion.library, **ajoute le ConfigDev « factice » en
$F00000** (AddConfigDev), crée les DeviceNodes (MakeDosNode) et **enfile un BootNode par unité amorçable dans
`eb_MountList`** **[U]**. Ensuite strap essaie DF0:, puis appelle romboot qui saute au **BootPoint** de la
carte ; et **dos.library, à son init, chaîne les DeviceNodes de `eb_MountList`** dans sa liste de devices
(DH0: monté) ; **la tête de `eb_MountList` devient SYS:** — après un bootblock DF0: réussi, strap y a ajouté
un BootNode DF0: de priorité 5, si bien qu'une carte de priorité ≥ 5 démarre même avec une disquette
amorçable **[R+S]**. Il manque donc, dans l'ordre : (1) le balayage de ROMTag de romboot, (2) l'appel du
BootPoint par romboot depuis strap (et le BootNode DF0: de strap), (3) la consommation de `eb_MountList` par
dos.

---

## 1. Résidents hors ROM Kickstart (exec, coldstart) **[R ; S]**

- Au coldstart, avant toute init de résident, exec construit `ExecBase->ResModules` (+$12C) en balayant une
  table de plages **[début, fin)** : **`$FC0000–$1000000`** (deux fois, entrée répétée dans la table 34.5) puis
  **`$F00000–$F80000`**. Donc **oui, la zone `$F00000–$F7FFFF` est balayée**, dans le **même** tri que la ROM.
- Critère : mot `RTC_MATCHWORD = $4AFC` à une adresse **paire** et `rt_MatchTag == adresse de la structure` ;
  après une ROMTag reconnue, le balayage reprend à `rt_EndSkip`. Aucune condition sur `rt_Flags` pour
  l'inscription.
- Doublons (même `rt_Name`) : la nouvelle remplace l'ancienne si `rt_Version` est **supérieure**, ou égale avec
  `rt_Pri` **≥** ; sinon elle est ignorée. Le tri final est par `rt_Pri` décroissant (règle de
  `module-map.md`). Les ROMTags de `KickTagPtr` (si `KickCheckSum` valide) sont fusionnées de la même façon.
- Ensuite `InitCode(RTF_COLDSTART, 0)` initialise, par priorité, toutes les entrées ayant RTF_COLDSTART, qu'elles
  viennent de `$FC…` ou de `$F0…`.
- Indépendamment (tout au début du reset, avant même la RAM) : si exec ne s'exécute pas déjà depuis `$F00000`
  et que le mot en `$F00000` vaut **`$1111`**, il saute en `$F00002` (ROM de diagnostic/cartouche).
- **Ce n'est PAS par là que la carte UAE s'installe** : la zone `$F00000` d'UAE (« rtarea ») ne contient pas
  de ROMTag visible par ce balayage (sonde §7 : aucune entrée de ResModules hors `$FC…–$FF…`) et ne commence pas
  par `$1111`. **[S]** (vecteur C1 : 24 entrées, toutes en `$FC…`–`$FF…` ; `uaehf.device` n'est pas dans
  ResModules mais dans DeviceList.)

---

## 2. romboot.library 34.1 **[R]**

Résident COLDSTART, NT_LIBRARY, pri **−40** (après intuition, avant strap). Une seule fonction publique (LVO
−30, « RomBoot »), plus Open/Close/Expunge.

### 2.1 Init : ROMTags des cartes (« InitResidents »)

1. `OpenLibrary("expansion.library", 33)` ; échec ⇒ rien.
2. Pour chaque ConfigDev de `eb_BoardList` (ordre de la liste) dont `cd_Flags & CDF_CONFIGME ($02)` :
   1. `ObtainConfigBinding()` ; `SetCurrentBinding({cb_ConfigDev = cd, FileName = 0, ProductString = 0,
      ToolTypes = 0}, 16)` ;
   2. si `er_Type & ERTF_DIAGVALID ($10)` et que `cd_Rom.er_Reserved0c` (pointeur de la **copie RAM** de la
      DiagArea, posé par expansion, `autoconfig-v34.md` §6) est non nul, et que `da_Config & DAC_CONFIGTIME
      ($10)` : recherche, par pas de 2 octets depuis le début de la copie et sur `da_Size` octets, de la
      **première** ROMTag (`$4AFC` + `rt_MatchTag` = elle-même) ; si trouvée : **`InitResident(tag, 0)`**
      (une seule par carte) ;
   3. `ReleaseConfigBinding()`.
3. `CloseLibrary(expansion)`. `CDF_CONFIGME` n'est pas effacé (c'est BindDrivers qui le fait).

À ce moment toutes les libraries/devices ROM sont initialisés (expansion est dans LibList, graphics,
intuition, timer, trackdisk… existent), **mais pas dos**.

### 2.2 RomBoot (LVO −30) : appel des BootPoint

1. `OpenLibrary("expansion.library", 33)`.
2. Parcours de `eb_MountList` dans l'ordre (Enqueue ⇒ `ln_Pri` décroissant). Un nœud est retenu si
   `bn_DeviceNode ≠ 0`, **`ln_Type == NT_BOOTNODE (16)`** et `ln_Name ≠ 0` (dans un BootNode, `ln_Name` porte
   le **ConfigDev** de la carte). Pour chaque nœud retenu, avec ce ConfigDev :
   - si `er_Type & DIAGVALID`, copie DiagArea non nulle, et `da_Config & DAC_CONFIGTIME` : appel de
     **`copie + da_BootPoint`** (`da_BootPoint` = UWORD à +6, non signé) avec **A0 = adresse appelée,
     A1 = ConfigDev**, le ConfigDev aussi en argument sur la pile (4(SP)), **A6 = ExecBase**.
   - **pas de test `da_BootPoint == 0`** : une DiagArea sans BootPoint ferait sauter au début de la copie
     (ne pas reproduire tel quel : traiter 0 comme « pas de BootPoint » est plus sûr et invisible en pratique).
   - si le BootPoint **revient**, le parcours continue avec le nœud suivant (sa valeur de retour est ignorée).
3. `CloseLibrary` ; retour (D0 = 0) à l'appelant.

Les BootNodes posés par `AddDosNode` avant dos (`ln_Type` non initialisé, `ln_Name` = nom C du device,
`autoconfig-v34.md` §7) **ne sont pas** des BootNodes amorçables pour romboot (type ≠ 16 en pratique) :
seuls ceux enfilés par le pilote lui-même avec `ln_Type = NT_BOOTNODE` et `ln_Name = ConfigDev` le sont.

---

## 3. strap 34.4 : essai floppy, RomBoot, BootNode DF0: **[R ; S]**

1. Alloue un bloc de `$488` octets (MEMF_CHIP|MEMF_CLEAR, tampon d'amorce + variables), un port, ouvre
   trackdisk.device unité 0.
2. **Essai DF0:** (CMD_CLEAR, TD_CHANGENUM, lecture de 1024 octets) : mot `'DOS\0'` et somme de contrôle
   (somme avec retenue des 256 longs, complémentée = 0) ⇒ exécution du bootblock (A1 = IORequest,
   A6 = ExecBase). Si D0 ≠ 0 au retour ⇒ Alert `$30000001`. Si D0 = 0 :
   - strap **crée le DeviceNode DF0: et le déclare comme BootNode** : `OpenLibrary("expansion.library", 33)`,
     `MakeDosNode` avec le paquet {`"DF0"`, `"trackdisk.device"`, unité 0, flags 0, environnement
     `de_TableSize = 12`, SizeBlock 128, SecOrg 0, Surfaces 2, SectorPerBlock 1, BlocksPerTrack 11,
     Reserved 2, PreAlloc 0, Interleave 0, LowCyl 0, HighCyl 79, NumBuffers 5, BufMemType 2 (CHIP)}, puis
     **`AddDosNode(5, 0, dn)`** — dos n'existant pas encore, c'est un BootNode **`ln_Pri = 5`**, `ln_Type` non
     initialisé, `ln_Name = "DF0"`, enfilé (Enqueue) **derrière** les nœuds de priorité ≥ 5 déjà présents ;
   - puis saut au point d'entrée rendu par le bootblock en A0 (l'init de dos).
3. **Si DF0: n'est pas amorçable** (pas de disque, pas DOS, somme fausse) : **une seule fois**,
   `OpenLibrary("romboot.library")` → **RomBoot()** (§2.2) → CloseLibrary. Aucun BootNode DF0: n'est créé sur ce
   chemin. Un BootPoint qui démarre dos ne revient pas.
4. Si RomBoot revient : nouvel essai DF0:, puis écran « insérer une disquette » et attente de changement de
   disque, essais DF0: suivants **sans** rappeler romboot.

Le **choix du volume de démarrage** n'est donc pas fait par strap mais par dos (§4.1) : c'est la **tête de
`eb_MountList`** qui gagne. Le bootblock d'une disquette amorçable s'exécute toujours en premier, mais
**une carte dont le BootNode a `ln_Pri ≥ 5` devient quand même SYS:** (son nœud précède celui de DF0:, pri 5,
enfilé plus tard) ; avec `ln_Pri < 5`, DF0: devient SYS: et la carte est seulement montée. **[R+S]**
(vecteurs P10, P5, P1, C1, C2).

---

## 4. dos.library 34.3 et `eb_MountList` **[R ; S]**

### 4.1 À l'init de dos (appelée par le bootblock DF0: ou par le BootPoint de la carte)

Dans la partie assembleur de l'init, avant le démarrage du CLI initial :
1. `OpenLibrary("expansion.library", 0)` (jamais refermée ; pas de test d'échec).
2. **Chaînage** : parcours de `eb_MountList` ; pour chaque couple de nœuds consécutifs (N, N+1) tant que
   `N.bn_DeviceNode ≠ 0`, que `N.bn_DeviceNode->dn_Next == 0` et que `(N+1).bn_DeviceNode ≠ 0` :
   `N.bn_DeviceNode->dn_Next = BPTR((N+1).bn_DeviceNode)`. Les DeviceNodes de **tous** les nœuds (quel que
   soit `ln_Type`) forment ainsi une chaîne dans l'ordre de la liste.
3. **`RemHead(eb_MountList)`** : le **premier** nœud est retiré (non libéré) ; son `bn_DeviceNode` (APTR) est
   passé à la partie BCPL de l'init (rangé provisoirement dans `RootNode+$1C`, qui reprend ensuite sa valeur
   normale `rn_FileHandlerSegment`). Ce DeviceNode est le **périphérique de démarrage** (SYS:) et la chaîne
   qui commence à lui est placée dans `DosInfo->di_DevInfo`, au **fond** de la liste (les nœuds créés ensuite
   par dos — RAM, CON, RAW, SER, PAR, PRT, volumes, assigns — sont insérés devant). **[R+S]**
4. Les autres nœuds **restent** dans `eb_MountList` (sonde : après un boot DF0: avec DH0 pri 0 ou 1, le
   BootNode de DH0 y est toujours). **[S]**
5. Si le périphérique de démarrage n'est pas le DF0: de strap (boot par BootPoint, ou carte prioritaire), dos
   crée **son propre** DeviceNode DF0: (insertion devant) ; si un BootNode DF0: de strap était aussi présent
   (carte prioritaire + disquette amorçable), **DF0 apparaît deux fois** dans la liste des devices (les deux
   montés sur la même disquette) — artefact fidèle de la 1.3. **[S]** (vecteur P10/P5)

### 4.2 AddDosNode après l'init de dos **[R ; S]**

`AddDosNode(bootPri, flags, dn)` (expansion −150) tente d'abord `OpenLibrary("dos.library")` ; si dos existe :
- si `dn_Task`, `dn_Handler` et `dn_SegList` sont tous nuls : `dn_SegList = rn_FileHandlerSegment` (le
  handler OFS de la ROM) ;
- sous Forbid, **insertion en tête** de `di_DevInfo` (`dn_Next = ancienne tête`) ;
- si `flags & 1` : appel interne de dos (entrée privée, D1 = BPTR du DeviceNode) — non sondé ;
- CloseLibrary(dos) ; comme CloseLibrary de dos rend 0, la fonction **enfile en plus** un BootNode dans
  `eb_MountList` (`ln_Pri = bootPri`, `ln_Name` = nom C du device) et rend **1**. Ce BootNode supplémentaire est
  inoffensif (dos ne relit `eb_MountList` qu'à son init). **[R+S]** (vecteur ADN)

### 4.3 Avant l'init de dos

`AddDosNode` ⇒ BootNode de 20 octets non effacé enfilé dans `eb_MountList` (`autoconfig-v34.md` §7) ; il sera
chaîné et monté par §4.1, et peut même devenir SYS: s'il est en tête ; il n'est pas amorçable par romboot
(§2.2), faute de `ln_Type = NT_BOOTNODE` et de ConfigDev.

---

## 5. Séquence complète observée pour la carte UAE (`hard_drive_0 = <répertoire>`)

1. exec : balayage ROMTags (ROM + `$F00000–$F7FFFF`) — aucune ROMTag UAE trouvée —, init COLDSTART ;
   **expansion** (pri 110) : ConfigChain ⇒ carte UAE en `$E90000` (`er_Type $D1`, manuf. 2011,
   `InitDiagVec $2000`), copie de la DiagArea en slow RAM (`$C01AE0`), **DiagPoint** appelé (A0/A2/A3/A5/A6,
   `autoconfig-v34.md` §6) ⇒ ROMTag `uaehf.device` écrite à copie+$10 (`$C01AF0`) ; D0 = 1. **[S+U]**
2. … résidents ROM (graphics … intuition, alert.hook, mathffp) …
3. **romboot init** (pri −40) : ROMTag trouvée dans la copie ⇒ `InitResident` ⇒ device `uaehf.device` dans
   DeviceList, dont l'init (code UAE) fait `AddConfigDev` d'un ConfigDev en **`$F00000`** (64 Ko, `er_Type $01`,
   produit 4, manuf. 2011, série 1), puis par unité MakeDosNode + BootNode (`ln_Type = 16`, `ln_Pri =
   bootpri`, `ln_Name` = **ConfigDev de la carte `$E90000`**) Enqueue dans `eb_MountList`. **[U ; S]**
4. **strap** (pri −60) : DF0: amorçable ⇒ bootblock + BootNode DF0: pri 5 + init dos ; sinon RomBoot ⇒
   BootPoint de la carte UAE ⇒ `FindResident("dos.library")` + appel de son `rt_Init`. **[R+U ; S]**
5. **dos init** : chaînage + RemHead de `eb_MountList` ⇒ SYS: = tête de liste, DH0: monté dans tous les cas.
   **[R+S]**

Minimum pour notre ROM : (a) romboot §2.1 (balayage de la copie de DiagArea + InitResident sous
ConfigBinding) ; (b) strap §3 (dont le BootNode DF0: pri 5 après un bootblock réussi) + RomBoot §2.2 ;
(c) dos §4.1 (chaînage de `eb_MountList`, tête = SYS:, DF0: créé par dos s'il n'est pas le périphérique de
démarrage) ; (d) un InitResident d'AUTOINIT NT_DEVICE appelé depuis un résident doit marcher (AddDevice) ;
(e) le balayage `$F00000` d'exec n'est pas nécessaire pour UAE mais fait partie du comportement 1.3.

---

## 6. Côté émulateur (FS-UAE 3.2.35) — repères **[U]**

- Journal `~/FS-UAE/Cache/Logs/fs-uae.log.txt` : `filesystem: diagentry <copie+$10> configdev <ConfigDev>`
  au moment de la DiagPoint.
- `filesys_init` (appelée par l'init de `uaehf.device`) essaie `OpenLibrary("expansion.library", 36)` puis 0 ;
  crée le ConfigDev factice (sauf option « hide autoconfig ») ; `make_dev` par unité ; sur KS ≥ 34 crée en plus
  une tâche de montage.
- BootPoint UAE = `FindResident("dos.library")` puis appel de `rt_Init` (A6 = ExecBase requis).
- La DiagPoint UAE installe aussi `uae.resource` et deux serveurs d'interruption (PORTS pri 20, VERTB pri −10) ;
  mécanisme « uae_int » (PORTS) et blocage niveau 2 de notre ROM : voir `uae-int2-v34.md`.

---

## 7. Vecteurs de test

Sondes : `tests/bootlist.s`, `tests/cfgdev2.s`, `tests/adn.s` (+ commandes C:CD/Assign/Info), sur la vraie
ROM 34.5, FS-UAE 3.2.35, `slow_memory = 512`, `fast_memory = 2048`, `hard_drive_0 = <rép. hôte>` (contenant
`s/startup-sequence`, `c/`, `l/Port-Handler`, `devs/serial.device`, les sondes). Disquette = copie du WB
1.3.3 (sondes dans sa startup-sequence) ou ADF vierge formaté sans bootblock. Formats :
`BN nœud type<<24|pri<<16|bn_Flags ln_Name bn_DeviceNode` ; `DN adr type task lock handler startup seglist gv nom`.

```
=== C1 : WB amorçable + DH0 (bootpri 0)
FLOPPYBOOT                                   (startup de la disquette)
RM … 24 lignes, toutes $FC…/$FF… (aucune en $F0…)
DV 00C04A34 uaehf.device                     (device initialisé, absent de ResModules)
BN 00C04DD8 10000000 00C01620 00C04E10       BootNode UAE : type 16, pri 0, ln_Name = ConfigDev $E90000 (C01620)
DN … RAM / DF0 00C04D80 / DH0 00C04E10 en fin de liste
DN 00C04E10 00000000 00C0757C 00000000 003C3F94 0030117A 003C0002 FFFFFFFF DH0
CD 00E90000 00010000 02D15240 000007DB 00E90001 00002000 00C01AE0 …
CD 00F00000 00010000 00010400 000007DB 00000000 …               ConfigDev ajouté par uaehf
Assign : SYS = Workbench1.3:      Info : DF0: Workbench1.3, DH0: hddir
AD 00C0A070 00000001                         AddDosNode(0,0,"ZZ0") après dos : rend 1
BN 00C04DD8 10000000 00C01620 00C04E10
BN 00C0A038 00000000 00C014D1 00C0A070       + BootNode enfilé (type 0, nom "ZZ0")
DN 00C0A070 … 003FE9E2 … ZZ0                 en tête de DevInfo, dn_SegList = rn_FileHandlerSegment
=== C2 : ADF vierge non amorçable + DH0 (bootpri 0)
HDBOOT                                        (startup de DH0 ⇒ BootPoint appelé)
(aucune ligne BN : eb_MountList vide)
DN 00C0097C … DF0                            DF0 créé par dos, en tête
DN 00C04E10 … DH0                            au fond de la liste
Assign : SYS = hddir:
=== P1 : WB amorçable + DH0 bootpri 1
FLOPPYBOOT ; BN 00C04DD8 10010000 00C01620 00C04E10 (reste) ; SYS = Workbench1.3:
=== P5 et P10 : WB amorçable + DH0 bootpri 5 / 10 (résultats identiques)
HDBOOT                                        (bootblock DF0 exécuté, mais SYS = DH0)
BN 00C04D48 00050000 00C04DB1 00C04D80       BootNode DF0: de strap restant : type 0, pri 5, "DF0"
DN 00C08F5C … DF0                            DF0 recréé par dos
DN 00C04E10 … DH0
DN 00C04D80 … DF0                            DF0 de strap chaîné derrière DH0 ⇒ DF0 listé 2 fois
Assign : SYS = hddir:
```

Journal FS-UAE (C1) : `filesystem: diagentry 00c01af0 configdev 00c01620` puis `Mounting uaehf.device 0 (0)`.
Non-régression proposée pour notre ROM : C2 (boot DH0 par BootPoint, SYS = DH0) et C1 (boot disquette, DH0 monté,
ConfigDev `$F00000` présent).

---

## 8. Non sondé / incertain

- **Mécanisme exact du choix SYS: dans la partie BCPL de dos** : déduit (tête de `eb_MountList` retirée par
  RemHead et passée au BCPL) et confirmé par les cinq vecteurs, mais le code BCPL n'a pas été suivi.
- Cas « carte prioritaire + disquette amorçable » : le bootblock de la disquette s'exécute (strap) avant que dos
  ne démarre sur DH0 ; un bootblock non standard (qui ne rend pas l'init de dos) court-circuiterait tout — non sondé.
- `AddDosNode` avec `flags & 1` (appel interne de dos) : ROM seulement, non sondé.
- BootPoint d'une DiagArea avec `da_BootPoint = 0` : ROM seulement (saut au début de la copie).
- Une carte à DiagArea **BYTEWIDE/NIBBLEWIDE** avec ROMTag : romboot balaie la copie RAM, donc indifférent ;
  non sondé.
- Balayage `$F00000–$F7FFFF` par exec et saut `$1111` en `$F00000` : ROM seulement (aucune ROM de cartouche
  disponible dans l'émulateur).
- Le ln_Type « non initialisé » des BootNodes d'AddDosNode valait 0 dans les sondes (AllocMem sans CLEAR) ; une
  valeur résiduelle 16 rendrait le nœud éligible à RomBoot avec un ln_Name qui n'est pas un ConfigDev — non
  reproduit.

---

## Relecture clean-room

- [x] Aucune suite d'instructions transcrite ni paraphrasée ; aucune adresse de routine ROM (seuls des
  offsets de structures publiques/privées, des constantes d'ABI et des plages matérielles).
- [x] Les sondes citées sont du code auteur (`tests/`, en-tête « ASSET DE TEST, PAS du code ROM »).
