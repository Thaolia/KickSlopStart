# Autoconfig Zorro II de la 1.3 (expansion.library 34.1) — spec comportementale

Piste ANALYSE. Source : ROM `kick34005.A500` (34.5) — sondes boîte noire sous FS-UAE 3.2.35 + lecture
de la ROM limitée aux cas que les sondes ne couvrent pas. Aucune suite d'instructions n'est transcrite :
on décrit le **quoi** (ordre, valeurs, conditions, layout d'ABI), jamais le **comment**.

Légende des sources : **[S]** = observé par sonde boîte noire (vecteurs §8) ; **[R]** = établi par analyse
ROM (comportement seulement) ; **[S+R]** = les deux concordent ; **[D]** = docs publiques (RKRM/NDK).

---

## 0. Structures d'ABI utilisées (rappel, offsets V34)

`struct ExpansionBase` (taille 456 = `0x1C8`, = dataSize du résident) **[R, concorde NDK 1.3]** :

| Off. | Champ | Rôle observé |
|---:|---|---|
| `$00` | `eb_LibNode` (34) | |
| `$22` | `eb_Flags` (UBYTE) | bit 0 `EBB_CLOGGED`, bit 1 `EBB_SHORTMEM` (cf. §3, §2.6) |
| `$24` | `eb_ExecBase` | |
| `$28` | `eb_SegList` | |
| `$2C` | `eb_CurrentBinding` (16 octets) | Get/SetCurrentBinding |
| `$3C` | `eb_BoardList` (List) | liste des ConfigDev |
| `$4A` | `eb_MountList` (List) | BootNodes d'AddDosNode (autoboot) |
| `$58` | `eb_AllocTable[256]` | 1 octet par « slot » de 64 Ko de l'espace 24 bits ; **≠0 = libre, 0 = pris/indisponible** |
| `$158` | `eb_BindSemaphore` (46) | Obtain/ReleaseConfigBinding |
| `$186` | `eb_Int2List`, `$19C` `eb_Int6List`, `$1B2` `eb_Int7List` (Interrupt ×3) | non utilisés par l'autoconfig |

`struct ConfigDev` (taille 68 = `0x44`) : `cd_Node` `$00`, `cd_Flags` `$0E` (bit 0 `CDF_SHUTUP`, bit 1
`CDF_CONFIGME`), `cd_Pad` `$0F`, `cd_Rom` `$10` (ExpansionRom, 16 octets), `cd_BoardAddr` `$20`,
`cd_BoardSize` `$24`, `cd_SlotAddr` `$28` (UWORD), `cd_SlotSize` `$2A` (UWORD), `cd_Driver` `$2C`,
`cd_NextCD` `$30`, `cd_Unused[4]` `$34`.

`struct ExpansionRom` (dans `cd_Rom`, offsets relatifs) : `er_Type` 0, `er_Product` 1, `er_Flags` 2,
`er_Reserved03` 3, `er_Manufacturer` 4 (UWORD), `er_SerialNumber` 6 (ULONG), `er_InitDiagVec` 10 (UWORD),
`er_Reserved0c..0f` 12 (4 octets).

Codes d'erreur (valeurs numériques renvoyées) : `0` OK, `41` (`EE_NOEXPANSION`, plus d'espace), `42`
(`EE_NOMEMORY`, aussi renvoyé pour « pas de carte / ROM invalide »).

---

## 1. QUAND l'autoconfig a lieu

1. **Dans l'init du résident expansion.library** (`RTF_AUTOINIT|RTF_COLDSTART`, pri **110**, 1er module de la
   passe `InitCode(RTF_COLDSTART)` après exec — cf. `module-map.md`, `boot-sequence.md`). **[R]**
   Personne d'autre ne déclenche la configuration de la chaîne : c'est la fonction d'init de la library
   (appelée par `MakeLibrary` via `InitResident`) qui, dans l'ordre :
   1. mémorise ExecBase (`eb_ExecBase`) et la seglist ;
   2. initialise `eb_BindSemaphore` (InitSemaphore) ;
   3. déclare libres les slots de l'**espace mémoire** : `FreeExpansionMem(0x20, 0x80)` → slots `$20..$9F`
      = `$200000..$9FFFFF` ;
   4. déclare libres les slots de l'**espace E/S** : `FreeExpansionMem(0xE9, 7)` → slots `$E9..$EF`
      = `$E90000..$EFFFFF` (le slot `$E8`, adresse de configuration, n'est **jamais** libre) ;
   5. initialise (NewList) `eb_BoardList` et `eb_MountList` ;
   6. appelle `ConfigChain($E80000)` ;
   7. renvoie la base.
   Tous les autres slots (`$00..$1F` chip/réservé, `$A0..$E8`, `$F0..$FF`) restent à 0 = indisponibles
   (la base est allouée remise à zéro par MakeLibrary).
2. **Après** la mise en place de la mémoire par exec (chip + slow RAM `$C00000`, ExecBase déjà placée) :
   la fast RAM Zorro II est ajoutée **pendant** l'init d'expansion, donc **avant** tous les autres résidents
   COLDSTART (graphics, devices, etc.) qui peuvent déjà y allouer. **[S+R]** (sans slow RAM, la fast RAM
   reçoit les allocations MEMF_PUBLIC des résidents suivants : `mh_Free` < taille, cf. vecteur `f8noslow`.)
3. La 1.3 **ne déplace pas** ExecBase ni la pile superviseur en fast RAM (ExecBase reste en slow RAM
   `$C00xxx` ou en chip). **[S]**

---

## 2. Protocole appliqué par la 1.3

### 2.1 Accès aux registres (ReadExpansionByte / WriteExpansionByte)
- Un « octet logique » d'index `n` occupe deux registres physiques : quartet **haut** à `board + 4n`, quartet
  **bas** à `board + 4n + 2` (dans les deux cas c'est le **quartet haut** de l'octet lu qui porte la donnée).
  `ReadExpansionByte(board, n)` = `(lire(board+4n) & $F0) | (lire(board+4n+2) >> 4)`, **sans inversion**.
  **[R]**
- `WriteExpansionByte(board, n, v)` écrit `v<<4` à `board+4n+2` (quartet bas) **puis** `v` à `board+4n`
  (quartet haut **en dernier**, car c'est l'écriture du quartet haut du registre `$48` qui fait prendre
  l'adresse à une carte Zorro II). Renvoie 0. **[R]**

### 2.2 Lecture de l'ExpansionRom (ReadExpansionRom)
- Lit **17** octets logiques (index 0 à 16) : l'index 0 (`er_Type`, registres `$00/$02`) est pris **tel
  quel** ; les index 1..16 sont **inversés** (complément à un). Ils sont rangés à partir de `cd_Rom`, donc le
  17e (index 16 = registres `$40/$42`, inversé) **déborde dans l'octet de poids fort de `cd_BoardAddr`**.
  **[R]**, conséquence visible **[S]** : une carte mise en sommeil garde `cd_BoardAddr = $FF000000` (cf. §2.6).
- Validation (sinon retour **42** = « pas de carte ») **[R]** :
  - `er_Flags & $3F` doit être 0 (seuls les bits 7 `ERFF_MEMSPACE` et 6 `ERFF_NOSHUTUP` sont admis) ;
  - `er_Reserved03` doit être 0 ;
  - `er_Manufacturer` ≠ `$0000` et ≠ `$FFFF`.
  Un bus vide (lectures toutes à 1 ou toutes à 0) échoue donc naturellement → **fin de chaîne**.
- Anti-rebond : relit ensuite la ROM **11 fois** et compare à chaque fois les 16 premiers octets
  (`cd_Rom`) ; une seule différence → retour 42. Sinon retour 0. **[R]**
- Les bits de type `er_Type & $C0` (Zorro II = `$C0`) et le bit « chained » (`$08`) **ne sont pas
  vérifiés** : seule la taille (`er_Type & 7`) et les bits `$20`/`$10` sont exploités. **[R]**

### 2.3 Taille (er_Type & 7) → nombre de slots de 64 Ko et départ de recherche **[R, tailles S]**

| code | taille | slots | départ de la recherche générale |
|:-:|---|:-:|:-:|
| 0 | 8 Mo | `$80` | `$20` |
| 1 | 64 Ko | `$01` | `$00` |
| 2 | 128 Ko | `$02` | `$00` |
| 3 | 256 Ko | `$04` | `$00` |
| 4 | 512 Ko | `$08` | `$00` |
| 5 | 1 Mo | `$10` | `$00` |
| 6 | 2 Mo | `$20` | `$00` |
| 7 | 4 Mo | `$40` | `$20` |

### 2.4 ConfigBoard(board, configDev) — déroulé observable **[R ; résultats S]**
1. Si `eb_Flags.CLOGGED` est déjà posé : ne fait rien (retour immédiat, d0 non significatif).
2. `slot = AllocBoardMem(er_Type & 7)` (§3).
3. **Succès** (`slot ≠ -1`) : `cd_Flags |= CDF_CONFIGME` ; `cd_SlotAddr = slot` ; `cd_BoardAddr = slot<<16` ;
   `cd_SlotSize = nb_slots` ; `cd_BoardSize = nb_slots<<16` ; puis `WriteExpansionByte(board, $12, slot)`
   (registre `$48/$4A` = bits A23..A16) → la carte prend son adresse et passe la main à la suivante.
   Puis **post-configuration** :
   - si `er_Type & $20` (`ERTF_MEMLIST`) : ajout de la mémoire (§4) ;
   - **sinon** si `er_Type & $10` (`ERTF_DIAGVALID`) : traitement DiagArea (§6) ;
   - (une carte mémoire avec DIAGVALID n'a donc **pas** sa DiagArea exécutée.)
   - retour **0**.
4. **Échec, carte « shut-up-able »** (`er_Flags` bit 6 `NOSHUTUP` à 0) : `WriteExpansionByte(board, $13, 0)`
   (registre `$4C/$4E` = shut-up) ; `cd_Flags |= CDF_SHUTUP` ; `eb_Flags |= EBB_SHORTMEM` ; retour **41**.
   `cd_SlotAddr/SlotSize/BoardSize` restent à 0, `cd_BoardAddr` garde l'artefact de §2.2.
5. **Échec, carte NOSHUTUP** : `eb_Flags |= EBB_CLOGGED` ; la carte reçoit comme adresse son propre slot de
   configuration (`$E8`, i.e. elle reste en `$E80000` et bouche la chaîne) ; les champs du ConfigDev sont
   remplis comme au point 3 mais avec `slot = -1` (`cd_SlotAddr = $FFFF`, `cd_BoardAddr = $FFFF0000`),
   `CDF_CONFIGME` **non** posé ; la post-configuration (point 3) est quand même exécutée ; retour 0.
   **[R uniquement — non sondé]** (cas pathologique ; reproduire tel quel n'a d'intérêt que pour la fidélité).

### 2.5 ConfigChain(baseAddr) **[R ; résultats S]**
Boucle :
1. si `eb_Flags.CLOGGED` → sortie, retour 0 ;
2. `cd = AllocConfigDev()` ; si NULL → retour **42** ;
3. `ReadExpansionRom(baseAddr, cd)` ≠ 0 → `FreeConfigDev(cd)`, sortie, retour **0** (fin de chaîne normale) ;
4. `r = ConfigBoard(baseAddr, cd)` ; si `r == 0` ou `r == 41` → `AddConfigDev(cd)` et on recommence ;
   sinon `FreeConfigDev(cd)`, sortie, retour 0.
Conséquences : les cartes mises en sommeil (41) **figurent** dans la liste ; l'ordre de la liste = ordre
physique de la chaîne. **[S]**

### 2.6 Fin de chaîne / cartes non configurables
- Absence de carte → ROM invalide → fin (§2.2). **[R]**
- Carte qui ne tient plus → shut-up + ConfigDev ajouté avec `cd_Flags = $01`, `cd_BoardAddr = $FF000000`
  (sur UAE : 17e octet inversé = `$FF`), tailles/slots 0 ; **la chaîne continue** (la carte en sommeil
  passe la main). **[S]** (vecteurs `d8_1`, `d4_8`).

---

## 3. Attribution des adresses (AllocBoardMem / AllocExpansionMem) **[S+R]**

- L'espace est géré par `eb_AllocTable` : 256 slots de 64 Ko ; libres au départ : `$20..$9F`
  (`$200000..$9FFFFF`, 8 Mo) et `$E9..$EF` (`$E90000..$EFFFFF`, 448 Ko). **[R]**
- Recherche d'un bloc de `n` slots :
  1. **si `n ≤ 7`** (64, 128 ou 256 Ko) : d'abord dans `[$E8, $F0)`, candidats `$E8, $E8+n, $E8+2n…` ;
     `$E8` étant toujours pris : 64 Ko → `$E9`, 128 Ko → `$EA`, 256 Ko → `$EC`. **Cela vaut aussi pour les
     cartes mémoire** : une carte de 256 Ko de RAM finit en `$EC0000` et sa RAM y est ajoutée. **[S]**
  2. sinon (ou si l'E/S est pleine) : dans `[départ, $100)` (départ de la table §2.3), candidats
     `départ + k·n`. Comme `$00..$1F` sont pris, cela revient à : **alignement naturel sur la taille** pour
     512 Ko..2 Mo (premier multiple libre ≥ `$200000`) ; pour **4 Mo** candidats `$200000` puis `$600000`
     (alignement 4 Mo **relatif à `$200000`**) ; pour **8 Mo** seulement `$200000`.
  3. un candidat n'est retenu que si ses `n` slots sont tous libres ; ils sont alors marqués pris (0). Le
     premier candidat convenable gagne (premier ajusté, ordre croissant). Rien n'est réservé en trou :
     un bloc de 1 Mo placé en `$200000` suivi d'une carte de 4 Mo met celle-ci en `$600000`, laissant
     `$300000..$5FFFFF` libre pour des cartes ultérieures de ≤ 2 Mo. **[S]** (`d1_4`)
- **Espace plein** : AllocBoardMem renvoie -1 → carte mise en sommeil (§2.4.4), `EBB_SHORTMEM`. **[S+R]**
- Ordre : celui de la chaîne physique ; pas de tri par taille (une petite carte en premier peut gaspiller
  l'alignement de la suivante). **[S]**
- `er_Flags.MEMSPACE` n'influe **pas** sur le placement en 1.3 ; seul le nombre de slots décide. **[R]**

---

## 4. Cartes mémoire (`ERTF_MEMLIST`) **[S+R]**

- Ajout par exec `AddMemList(size = cd_BoardSize, attributes = MEMF_PUBLIC|MEMF_FAST ($0005), pri = 0,
  base = cd_BoardAddr, name = "expansion ram")` (chaîne exacte, minuscules). **[R]**, résultat **[S]** :
  - le MemHeader est placé **au début de la carte** : `mh_Lower = base + $20` (32 octets = sizeof MemHeader),
    `mh_Upper = base + size` (premier octet **après** la carte), `mh_Free = size − $20` ;
  - `ln_Type = NT_MEMORY ($0A)`, `ln_Pri = 0`, `mh_Attributes = $0005`, nom `"expansion ram"`.
  - Une MemHeader **par carte** (deux cartes contiguës ne sont pas fusionnées). **[S]** (`d2_1`)
- Position dans `ExecBase->MemList` (Enqueue par priorité, FIFO à priorité égale) **[S]** :
  1. slow RAM `$C00000` (`"Fast Memory"`, attr `$0005`, pri 0) — ajoutée par exec avant ;
  2. les cartes `"expansion ram"` (pri 0) dans l'ordre de configuration ;
  3. chip (`"Chip Memory"`, attr `$0003`, pri −10).
  Sans slow RAM : expansion ram puis chip. Conséquence : en présence de slow RAM, les allocations sans
  contrainte vont **d'abord en slow RAM**, pas en fast (ex. la copie DiagArea, vecteur `hd2048`).
- La RAM n'est pas testée (aucun test mémoire / pas de `EE_BADMEM` observé). **[R]**

---

## 5. ConfigDev **[S+R]**

- Alloué par `AllocConfigDev` = `AllocMem(68, MEMF_PUBLIC|MEMF_CLEAR)` : tout ce qui n'est pas cité vaut 0
  (`ln_Type = 0`, `ln_Name = NULL`, `cd_Driver = 0`, `cd_NextCD = 0`). **[S+R]**
- Carte configurée : `cd_Flags = $02` (CONFIGME), `cd_Rom` = ROM lue (type non inversé, reste inversé),
  `cd_BoardAddr = slot<<16`, `cd_BoardSize = n<<16`, `cd_SlotAddr = slot`, `cd_SlotSize = n` (unité = 64 Ko,
  ex. `$0020/$0020` pour 2 Mo en `$200000`, `$00E9/$0001` pour 64 Ko en `$E90000`). **[S]**
- Carte en sommeil : `cd_Flags = $01`, `cd_BoardAddr = $FF000000` (artefact), le reste 0. **[S]**
- `cd_Driver` n'est **pas** rempli par expansion (c'est BindDrivers qui le fait et efface CONFIGME). Le
  pointeur vers la copie RAM de la DiagArea est rangé dans **`cd_Rom.er_Reserved0c`** (ULONG à `cd+$1C`).
  **[S+R+D]**
- Liste : `AddConfigDev` = AddTail sur `eb_BoardList` sous Forbid → ordre de la chaîne ; les ConfigDev
  ajoutés plus tard par des pilotes (ex. UAE ajoute le sien en `$F00000`) viennent après. **[S+R]**
- `FindConfigDev(old, manuf, prod)` : part du premier nœud si `old == NULL`, sinon du suivant de `old` ;
  `manuf == -1` (long) = joker, sinon comparaison sur le mot `er_Manufacturer` ; `prod == -1` = joker, sinon
  comparaison sur l'octet `er_Product` ; renvoie le premier ConfigDev qui correspond ou 0. Pas de Forbid.
  **[R ; S pour le parcours -1/-1]**

---

## 6. DiagArea (`er_InitDiagVec`) **[R ; exécution prouvée S]**

La 1.3 **exécute** la DiagArea, **pendant ConfigBoard**, donc pendant l'init d'expansion.library (avant tous
les autres résidents COLDSTART : pas de graphics, pas de dos, pas de devices ; seuls exec et expansion).
Condition : carte configurée avec succès, **sans** `ERTF_MEMLIST`, avec `ERTF_DIAGVALID` ($10).

1. Si `er_InitDiagVec == 0` → rien.
2. DiagArea en ROM = `cd_BoardAddr + er_InitDiagVec` (adresse **configurée**). Son 1er octet `da_Config`
   doit vérifier `(da_Config & $30) == $10` (`DAC_CONFIGTIME`) sinon rien (BINDTIME seul = ignoré).
3. Largeur de bus `da_Config & $C0` : `$00` NIBBLEWIDE (octets reconstitués à partir des quartets hauts des
   octets à +0 et +2, pas de 4), `$40` BYTEWIDE (un octet sur deux, pas de 2), `$80` WORDWIDE (copie
   contiguë via CopyMem), `$C0` → rien.
4. Copie de l'en-tête (14 octets : `da_Config, da_Flags, da_Size(W), da_DiagPoint(W), da_BootPoint(W),
   da_Name(W), da_Reserved01(W), da_Reserved02(W)`) ; si `da_Size == 0` → rien.
5. `AllocMem(da_Size, 0)` (aucun attribut : premier MemHeader, donc slow RAM si présente) ; échec → rien.
6. Copie de `da_Size` octets de la DiagArea (même largeur) dans ce tampon ; **`er_Reserved0c` ← tampon**.
   Aucune relocation : c'est au code de diag de se corriger (cf. RKRM).
7. Si `da_DiagPoint ≠ 0` : appel de `tampon + da_DiagPoint` avec **A0 = cd_BoardAddr, A2 = tampon (copie
   DiagArea), A3 = ConfigDev, A6 = ExecBase**, et (non documenté) **A5 = ExpansionBase**. Retour D0 :
   ≠ 0 = succès (on garde tout) ; **0 = échec** → `FreeMem(tampon, da_Size)` et `er_Reserved0c = 0`.
   Si `da_DiagPoint == 0`, le tampon est gardé sans appel.
8. `da_BootPoint` n'est pas appelé ici (c'est l'affaire de strap/romboot via `er_Reserved0c` et
   `eb_MountList`, hors de cette spec).

Minimum pour ne pas casser un contrôleur : copier fidèlement (largeur), ranger le pointeur dans
`er_Reserved0c`, appeler DiagPoint avec A0/A2/A3/A6 (A5 en bonus), respecter le code retour, et fournir
`MakeDosNode`/`AddDosNode`/`eb_MountList` utilisables à ce moment-là (dos.library absente). Vecteur `hd2048` :
la carte UAE (DiagArea, `InitDiagVec=$2000`) obtient sa copie en `$00C01AE0` (slow RAM), son DiagPoint
s'exécute (il ajoute lui-même un ConfigDev en `$F00000`) et DH0: est monté au boot. **[S]**

---

## 7. LVO d'expansion.library V34 (25 vecteurs, biais 30, format table LONG absolu) **[R ; D pour les noms]**

| LVO | Fonction (regs) | Comportement observable 34.1 |
|---:|---|---|
| −30 | `AddConfigDev(cd)(a0)` | Forbid, AddTail(eb_BoardList), Permit. |
| −36 | *(privé, « expansionUnused » au .fd)* `(size d0, attr d1, base a0)` | AddMemList(d0, d1, pri 0, a0, "expansion ram"). Non utilisé par l'autoconfig (qui appelle exec directement). |
| −42 | `AllocBoardMem(slotSpec)(d0)` | `AllocExpansionMem(n, départ)` selon la table §2.3 (spec & 7) ; renvoie le slot ou −1. |
| −48 | `AllocConfigDev()()` | AllocMem(68, PUBLIC|CLEAR). |
| −54 | `AllocExpansionMem(numSlots, slotAlign)(d0/d1)` | −1 si `numSlots+slotAlign > 256`. Si `numSlots ≤ 7`, essai en E/S `[$E8,$F0)` pas `numSlots`. Puis recherche dans `[slotAlign, $100)` pas `numSlots` (**`slotAlign` = slot de départ**, pas un alignement). Marque pris, renvoie le slot ou −1. |
| −60 | `ConfigBoard(board, cd)(a0/a1)` | §2.4. Retour 0 / 41. |
| −66 | `ConfigChain(baseAddr)(a0)` | §2.5. Retour 0 (ou 42 si plus de mémoire pour un ConfigDev). |
| −72 | `FindConfigDev(old, manuf, prod)(a0,d0/d1)` | §5. |
| −78 | `FreeBoardMem(startSlot, slotSpec)(d0/d1)` | `FreeExpansionMem(startSlot, n(spec))`. |
| −84 | `FreeConfigDev(cd)(a0)` | FreeMem(cd, 68). |
| −90 | `FreeExpansionMem(startSlot, numSlots)(d0/d1)` | Marque libres (≠0). Si `start+num > 256`, ou si un slot est **déjà libre** : `Alert($0A000001)` (AN_BadExpansionFree, récupérable) et arrêt (les slots précédents restent libérés). |
| −96 | `ReadExpansionByte(board, offset)(a0,d0)` | §2.1, sans inversion ; renvoie l'octet. |
| −102 | `ReadExpansionRom(board, cd)(a0/a1)` | §2.2 ; 0 = OK, 42 = absente/invalide/instable. |
| −108 | `RemConfigDev(cd)(a0)` | Forbid, Remove, Permit. |
| −114 | `WriteExpansionByte(board, offset, byte)(a0,d0/d1)` | §2.1 ; renvoie 0. |
| −120 | `ObtainConfigBinding()()` | ObtainSemaphore(eb_BindSemaphore). |
| −126 | `ReleaseConfigBinding()()` | ReleaseSemaphore(eb_BindSemaphore). |
| −132 | `SetCurrentBinding(binding, size)(a0,d0)` | Copie `min(size,16)` octets dans `eb_CurrentBinding`, complète à 16 par des 0. |
| −138 | `GetCurrentBinding(binding, size)(a0,d0)` | Copie `min(size,16)` octets **vers** le tampon puis écrit des 0 jusqu'à 16 octets **dans le tampon** (déborde si `size < 16`) ; renvoie toujours **16**. |
| −144 | `MakeDosNode(parmPacket)(a0)` | AllocEntry de 5 blocs PUBLIC|CLEAR : DeviceNode (44), FileSysStartupMsg (16), environnement `(de_TableSize+1)*4`, BSTR nom DOS, BSTR nom exec ; recopie l'environnement ; `dn_StackSize = 600`, `dn_Priority = 10` ; renvoie le DeviceNode ou 0. |
| −150 | `AddDosNode(bootPri, flags, dosNode)(d0/d1/a0)` | NULL → 0. Si dos.library s'ouvre : chemin d'ajout côté DOS (non détaillé ici, cf. §9). Sinon BootNode de 20 octets (AllocMem sans CLEAR : `ln_Type` non initialisé) : `ln_Pri = bootPri`, `bn_Flags = flags`, `bn_DeviceNode = dosNode`, `ln_Name` = nom C du DeviceNode, Enqueue dans `eb_MountList` ; renvoie 1 (0 si plus de mémoire). |

Appelés au boot par expansion elle-même : FreeExpansionMem, ConfigChain → AllocConfigDev,
ReadExpansionRom (→ ReadExpansionByte), ConfigBoard (→ AllocBoardMem → AllocExpansionMem,
WriteExpansionByte), AddConfigDev, FreeConfigDev ; exec AddMemList / AllocMem / CopyMem / FreeMem.

---

## 8. Vecteurs de test (vraie ROM 34.5, FS-UAE 3.2.35, A500 512 Ko chip)

Sonde : `tests/cfgdev2.s` (variante étendue de `tests/cfgdev.s`), lancée par `cfgdev2 >SER:` depuis la
startup-sequence d'une copie de l'ADF Workbench 1.3.3. Format :
`CD BoardAddr BoardSize Flags.Type.Product.ErFlags Manufacturer SlotAddr.SlotSize InitDiagVec er_Reserved0c cd_Driver ln_Type<<16|cd_Pad`
puis `MH Lower Upper Attr<<16|ln_Type<<8|Pri Free Nom`. Config FS-UAE de base + lignes indiquées
(`uae_fastmem2_size` = 2e carte Zorro II, en Mo ; `uae_fastmem_size_k` en Ko). Les valeurs `mh_Free` de
slow/chip dépendent de l'état du boot et ne sont pas normatives. Dans les blocs abrégés, les lignes MH
slow (`00C004E8 00C7E800 00050A00`) et chip (`00000420 00080000 00030AF6`) sont identiques à `none`.

```
=== none  (slow_memory = 512)
MH 00C004E8 00C7E800 00050A00 00073580 Fast Memory
MH 00000420 00080000 00030AF6 0006FED8 Chip Memory
=== nofast_noslow  (slow_memory = 0)
MH 000008E8 0007E800 00030AF6 00063478 Chip Memory
=== k64  (slow 512, uae_fastmem_size_k = 64)
CD 00E90000 00010000 02E15180 000007DB 00E90001 00000000 00000000 00000000 00000000
MH 00C004E8 00C7E800 00050A00 00073520 Fast Memory
MH 00E90020 00EA0000 00050A00 0000FFE0 expansion ram
MH 00000420 00080000 00030AF6 0006FED8 Chip Memory
=== k128  (uae_fastmem_size_k = 128)
CD 00EA0000 00020000 02E25180 000007DB 00EA0002 00000000 00000000 00000000 00000000
MH 00EA0020 00EC0000 00050A00 0001FFE0 expansion ram
=== k256  (uae_fastmem_size_k = 256)
CD 00EC0000 00040000 02E35180 000007DB 00EC0004 00000000 00000000 00000000 00000000
MH 00EC0020 00F00000 00050A00 0003FFE0 expansion ram
=== k512  (uae_fastmem_size_k = 512)
CD 00200000 00080000 02E45180 000007DB 00200008 00000000 00000000 00000000 00000000
MH 00200020 00280000 00050A00 0007FFE0 expansion ram
=== f1024  (fast_memory = 1024)
CD 00200000 00100000 02E55180 000007DB 00200010 00000000 00000000 00000000 00000000
MH 00200020 00300000 00050A00 000FFFE0 expansion ram
=== f2048  (fast_memory = 2048)
CD 00200000 00200000 02E65180 000007DB 00200020 00000000 00000000 00000000 00000000
MH 00C004E8 00C7E800 00050A00 00073520 Fast Memory
MH 00200020 00400000 00050A00 001FFFE0 expansion ram
MH 00000420 00080000 00030AF6 0006FED8 Chip Memory
=== f4096
CD 00200000 00400000 02E75180 000007DB 00200040 00000000 00000000 00000000 00000000
MH 00200020 00600000 00050A00 003FFFE0 expansion ram
=== f8192
CD 00200000 00800000 02E05180 000007DB 00200080 00000000 00000000 00000000 00000000
MH 00C004E8 00C7E800 00050A00 00073538 Fast Memory
MH 00200020 00A00000 00050A00 007FFFE0 expansion ram
MH 00000420 00080000 00030AF6 0006FED8 Chip Memory
=== f8noslow  (slow_memory = 0, fast_memory = 8192)
CD 00200000 00800000 02E05180 000007DB 00200080 00000000 00000000 00000000 00000000
MH 00200020 00A00000 00050A00 007F5580 expansion ram
MH 000008E8 0007E800 00030AF6 0006DE90 Chip Memory
=== d2_1  (fast 2048 + 2e carte 1 Mo)
CD 00200000 00200000 02E65180 000007DB 00200020 00000000 00000000 00000000 00000000
CD 00400000 00100000 02E55180 000007DB 00400010 00000000 00000000 00000000 00000000
MH 00C004E8 00C7E800 00050A00 000734F0 Fast Memory
MH 00200020 00400000 00050A00 001FFFE0 expansion ram
MH 00400020 00500000 00050A00 000FFFE0 expansion ram
MH 00000420 00080000 00030AF6 0006FED8 Chip Memory
=== d1_4  (fast 1024 + 2e carte 4 Mo)
CD 00200000 00100000 02E55180 000007DB 00200010 00000000 00000000 00000000 00000000
CD 00600000 00400000 02E75180 000007DB 00600040 00000000 00000000 00000000 00000000
MH 00C004E8 00C7E800 00050A00 000734F0 Fast Memory
MH 00200020 00300000 00050A00 000FFFE0 expansion ram
MH 00600020 00A00000 00050A00 003FFFE0 expansion ram
MH 00000420 00080000 00030AF6 0006FED8 Chip Memory
=== d8_1  (fast 8192 + 2e carte 1 Mo : plus de place)
CD 00200000 00800000 02E05180 000007DB 00200080 00000000 00000000 00000000 00000000
CD FF000000 00000000 01E55180 000007DB 00000000 00000000 00000000 00000000 00000000
MH 00C004E8 00C7E800 00050A00 000734D8 Fast Memory
MH 00200020 00A00000 00050A00 007FFFE0 expansion ram
MH 00000420 00080000 00030AF6 0006FED8 Chip Memory
=== d4_8  (fast 4096 + 2e carte 8 Mo : plus de place)
CD 00200000 00400000 02E75180 000007DB 00200040 00000000 00000000 00000000 00000000
CD FF000000 00000000 01E05180 000007DB 00000000 00000000 00000000 00000000 00000000
MH 00200020 00600000 00050A00 003FFFE0 expansion ram
=== hd2048  (fast 2048 + hard_drive_0 = répertoire hôte → carte UAE à DiagArea)
CD 00200000 00200000 02E65180 000007DB 00200020 00000000 00000000 00000000 00000000
CD 00E90000 00010000 02D15240 000007DB 00E90001 00002000 00C01AE0 00000000 00000000
CD 00F00000 00010000 00010400 000007DB 00000000 00000000 00000000 00000000 00000000
MH 00C004E8 00C7E800 00050A00 00070DF0 Fast Memory
MH 00200020 00400000 00050A00 001FFFE0 expansion ram
MH 00000420 00080000 00030AF6 000721D8 Chip Memory
(+ « info » : DH0: monté, volume hddir — DiagPoint/BootPoint de la carte UAE exécutés.)
```

Lecture des vecteurs : `er_Type` `$E0..$E7` = Zorro II + MEMLIST + code taille ; `$D1` = Zorro II +
DIAGVALID + 64 Ko ; `er_Flags` `$80` (MEMSPACE) pour la RAM UAE, `$40` (NOSHUTUP) pour la carte disque UAE.
La 3e ligne CD de `hd2048` (en `$F00000`, flags 0, `er_Type $10`) est un ConfigDev **ajouté par le code de
diag UAE** via AddConfigDev, pas par l'autoconfig : une implémentation correcte doit le voir apparaître
aussi (preuve que DiagPoint a tourné).

Tests de non-régression proposés pour notre ROM : chaque bloc ci-dessus doit être reproduit à
l'identique pour les lignes CD et pour Lower/Upper/Attr/nom des MH (le champ Free de slow/chip excepté).

---

## 9. Non sondé / incertain

- **Carte NOSHUTUP sans place (CLOGGED)** : comportement §2.4.5 lu dans la ROM seulement ; non sondé.
- **Carte E/S sans DiagArea** et **cartes BYTEWIDE/NIBBLEWIDE** : non sondées (la carte UAE est la seule
  carte à DiagArea disponible simplement ; sa largeur n'a pas été relevée). Règles de copie = ROM.
- **DiagPoint renvoyant 0** (libération du tampon, `er_Reserved0c = 0`) : ROM seulement.
- **Instabilité de lecture** (11 relectures) et ROM invalide (er_Flags bas ≠ 0, manufacturer 0/$FFFF) : ROM.
- Valeur de l'artefact `cd_BoardAddr` d'une carte en sommeil : `$FF000000` sur UAE ; sur du vrai matériel
  elle dépend de ce que la carte présente en `$40/$42` (inversé) — non vérifié.
- `eb_Flags` final (SHORTMEM après `d8_1`) : non lu par sonde (ROM seulement).
- Carte 64–256 Ko quand l'E/S `$E9..$EF` est pleine : repli vers l'espace mémoire selon la ROM, non sondé.
- WinUAE non utilisé : FS-UAE suffisait pour deux cartes (`uae_fastmem2_size`) ; Zorro III ignoré (hors A500).
- Le chemin « dos.library présente » d'AddDosNode et le détail de MakeDosNode ne sont résumés qu'à grands
  traits (hors autoconfig proprement dit).

## Relecture clean-room

Relecture du 2026-10-29.

- [x] Aucune suite d'instructions 68000 transcrite, aucun extrait de désassemblage, aucune adresse de
  routine ROM : toutes les adresses citées sont celles de l'espace Zorro II (`$E80000`, `$200000..$9FFFFF`,
  `$E90000..$EFFFFF`), de la slow RAM (`$C00000`), de la carte UAE (`$F00000`) ou des registres de
  configuration (`$40`/`$48`/`$4C`).
- [x] Les §1, §2.4, §2.5 et §6 énumèrent des étapes au niveau des **appels publics** (LVO
  d'expansion/exec) et de leurs résultats ; c'est l'ordre observable du protocole Autoconfig, pas un
  déroulé de code. Les vecteurs §8 sont des sorties de sonde (code auteur `tests/cfgdev2.s`).
- [x] Pas de données ROM au-delà de l'ABI : layout `ExpansionBase`/`ConfigDev`/`ExpansionRom`, codes
  d'erreur, tables de tailles Zorro II (publiques), nom de MemHeader `"expansion ram"`, valeurs
  `dn_StackSize`/`dn_Priority` de MakeDosNode.
