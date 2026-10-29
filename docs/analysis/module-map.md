# module-map.md — Carte des 24 ROMTags (Kickstart 1.3 / V34.5, `kick34005.A500`)

> Piste ANALYSE (« dirty »). Faits dérivés UNIQUEMENT de la lecture radare2 de la ROM
> (256 Ko, 68000 big-endian, base $FC0000). Aucun listing d'instructions n'est reproduit, ni
> aucune adresse de routine ou de structure dans la ROM : seuls flags, types, priorités, tailles,
> comptes et constantes d'ABI figurent ici.
>
> Provenance : toutes les colonnes sont **mesurées dans la ROM** sauf la décomposition
> nominale des flags/types (constantes d'ABI publiques, `exec/resident.i`, `exec/nodes.i`).

## En-tête ROM (longwords au début de l'image)

| Offset | Valeur mesurée | Sens |
|-------:|----------------|------|
| +0x00 | `0x11114EF9` | SSP initial vu au reset = mot ROM-ID `0x1111` + opcode `0x4EF9` (JMP abs.l) — format d'en-tête Kickstart 256 Ko, vérifié par les outils (`romtool`) |
| +0x04 | adresse ROM | PC de reset → point d'entrée du coldstart exec (= `rt_Init` d'exec, cf. ci-dessous) |
| +0x08 | `0x0000FFFF` | — |
| +0x0C | `0x00220005` | **Version ROM = 34.5** (major `0x22`=34, minor `0x0005`=5) → Kickstart 1.3 |
| +0x10 | `0x00220002` | Marqueur secondaire 34.2 (coïncide avec la révision propre d'exec) |
| +0x14 | `0xFFFFFFFF` | — |
| +0x18 | ASCII | `rt_IdString` d'exec (« exec 34.2 » + date + CR/LF) |
| +0x38 | ASCII | Bannière de copyright Commodore-Amiga (texte non reproduit) |

Pied de ROM (24 derniers octets de l'image) : champ de taille `0x00040000` (256 Ko) + un longword
de checksum de l'image. Non analysé plus avant (hors périmètre spec).

## Constantes de décodage (ABI publique)

- `rt_Flags` : `RTF_AUTOINIT=0x80` · `RTF_AFTERDOS=0x04` · `RTF_SINGLETASK=0x02` · `RTF_COLDSTART=0x01`.
- `rt_Type` (`exec/nodes.i`) : `NT_UNKNOWN=0` · `NT_TASK=1` · `NT_DEVICE=3` · `NT_RESOURCE=8` · `NT_LIBRARY=9`.
- `rt_Version` est un **UBYTE** = numéro **majeur** seulement (34). La révision (`.1`/`.2`/`.3`/`.4`)
  n'existe que dans `rt_IdString` ; elle n'est PAS stockée dans la Resident struct en V34.

## Tableau des 24 ROMTags (ordre de priorité décroissante = ordre d'init, cf. règle de tri plus bas)

Tous : `rt_MatchWord=0x4AFC`, `rt_MatchTag`→lui-même, `rt_Version=34`.

| # | Module | `rt_Flags` | Flags décodés | `rt_Type` | Pri | Révision (`rt_IdString`) |
|--:|--------|:----------:|---------------|:---------:|----:|--------------------------|
| 1 | exec.library | `0x00` | *(aucun)* | `9` LIBRARY | 120 | 34.2 |
| 2 | expansion.library | `0x81` | AUTOINIT+COLDSTART | `9` LIBRARY | 110 | 34.1 |
| 3 | potgo.resource | `0x01` | COLDSTART | `8` RESOURCE | 100 | 34.1 |
| 4 | keymap.resource | `0x01` | COLDSTART | `8` RESOURCE | 100 | 34.1 |
| 5 | cia.resource | `0x01` | COLDSTART | `8` RESOURCE | 80 | 34.1 |
| 6 | disk.resource | `0x01` | COLDSTART | `8` RESOURCE | 70 | 34.1 |
| 7 | misc.resource | `0x01` | COLDSTART | `8` RESOURCE | 70 | 34.1 |
| 8 | ramlib.library | `0x80` | AUTOINIT *(pas COLDSTART)* | `9` LIBRARY | 70 | 34.1 |
| 9 | graphics.library | `0x01` | COLDSTART | `9` LIBRARY | 65 | 34.1 |
| 10 | keyboard.device | `0x01` | COLDSTART | `3` DEVICE | 60 | 34.1 |
| 11 | gameport.device | `0x01` | COLDSTART | `3` DEVICE | 60 | 34.1 |
| 12 | timer.device | `0x01` | COLDSTART | `3` DEVICE | 50 | 34.1 |
| 13 | audio.device | `0x81` | AUTOINIT+COLDSTART | `3` DEVICE | 40 | 34.1 |
| 14 | input.device | `0x01` | COLDSTART | `3` DEVICE | 40 | 34.1 |
| 15 | layers.library | `0x01` | COLDSTART | `9` LIBRARY | 31 | 34.1 |
| 16 | console.device | `0x01` | COLDSTART | `3` DEVICE | 20 | 34.1 |
| 17 | trackdisk.device | `0x01` | COLDSTART | `3` DEVICE | 20 | 34.1 |
| 18 | intuition.library | `0x81` | AUTOINIT+COLDSTART | `9` LIBRARY | 10 | 34.3 |
| 19 | alert.hook | `0x01` | COLDSTART | `0` UNKNOWN | 5 | *(nom seul, `rt_IdString` = `rt_Name`)* |
| 20 | mathffp.library | `0x81` | AUTOINIT+COLDSTART | `9` LIBRARY | 0 | 34.1 |
| 21 | workbench.task | `0x00` | *(aucun)* | `1` TASK | 0 | wb 34.1 |
| 22 | dos.library | `0x00` | *(aucun)* | `9` LIBRARY | 0 | 34.3 |
| 23 | romboot.library | `0x01` | COLDSTART | `9` LIBRARY | -40 | 34.1 |
| 24 | strap | `0x01` | COLDSTART | `0` UNKNOWN | -60 | 34.4 |

### Faits remarquables (mesurés)

- **exec** : `rt_Flags=0` (ni AUTOINIT ni COLDSTART), et son `rt_Init` **est** le PC de reset de
  l'en-tête. exec n'est donc PAS initialisé par le balayage des résidents : le vecteur de reset saute
  directement dans son `rt_Init`, qui EST la routine de coldstart du noyau. Son `rt_EndSkip` désigne
  la ROMTag suivante (`alert.hook`) : le balayage reprend juste après la plage d'exec.
- **Bits de timing présents dans cette ROM** : seul `RTF_COLDSTART` (0x01) parmi les trois bits
  « quand démarrer ». **Aucun** module n'a `RTF_SINGLETASK` (0x02) ni `RTF_AFTERDOS` (0x04).
- **Sans aucun bit de timing** : exec (0x00), **ramlib** (0x80 = AUTOINIT seul), workbench.task
  (0x00), dos (0x00). Ces quatre ne sont pas démarrés par la passe `InitCode(RTF_COLDSTART)`
  générique ; ils sont pris en charge par des chemins dédiés (exec = le noyau lui-même ; ramlib,
  dos et workbench.task par l'amorçage DOS/strap). Voir `boot-sequence.md`.
- **Types « UNKNOWN » (0)** : `alert.hook` (pri 5) et `strap` (pri -60) ne sont ni library ni
  device ni resource — ce sont des hooks de boot invoqués via `rt_Init`.
- **alert.hook** : `rt_Name` et `rt_IdString` désignent la même chaîne (« alert.hook ») ; son
  `rt_Init` est situé avant la tag elle-même (aucune contrainte d'ABI : `rt_Init` est un pointeur libre).
- **dos** : `rt_Init == rt_EndSkip` (même valeur de pointeur).
- Révisions par module (depuis `rt_IdString`) : exec **34.2**, intuition **34.3**, dos **34.3**,
  strap **34.4** ; tous les autres **34.1**. La ROM dans son ensemble s'identifie **34.5 / Release 1.3**.

### Règle de tri de la liste des résidents (= ordre d'initialisation)

Clé de tri : **`rt_Pri` décroissant, puis position dans la ROM croissante** (le balayage ROM
construit la liste en ordre d'adresse croissante, le tri par priorité est stable). Confirmé par
les égalités de priorité mesurées (ordre observé à priorité égale) :
- pri 100 : potgo avant keymap
- pri 70 : disk avant misc avant ramlib
- pri 60 : keyboard avant gameport
- pri 40 : audio avant input
- pri 20 : console avant trackdisk
- pri 0 : mathffp avant workbench.task avant dos

L'ordre du tableau ci-dessus est donc l'ordre exact que la réimplémentation doit reproduire (une
réimplémentation peut placer ses propres tags dans cet ordre d'adresse pour obtenir les mêmes
départages).

## Structures d'auto-init (modules RTF_AUTOINIT)

Pour les 5 modules dont `rt_Flags & RTF_AUTOINIT`, `rt_Init` pointe sur une table de 4 longwords
(`exec/resident.i`, structure dite « auto-init » consommée par `InitResident`→`MakeLibrary`) :

```
+0  LONG  dataSize     taille (octets) de la base de library/device à allouer
+4  APTR  vectors      pointeur sur la table des vecteurs de fonctions (jump table)
+8  APTR  structure    pointeur sur données d'InitStruct (init des champs de la base), ou NULL
+12 APTR  initFunction pointeur sur routine exécutée après allocation/init, ou NULL
```

Format de la table `vectors` (convention `MakeFunctions`) : si le **premier mot = `0xFFFF`**,
les entrées sont des **déplacements WORD signés** (16 bits) relatifs à l'adresse de `vectors`,
terminés par `0xFFFF` ; sinon ce sont des **adresses LONG absolues** (32 bits) terminées par
`0xFFFFFFFF`. Le nombre d'entrées = nombre de LVO exposés par le module.

| Module | `dataSize` | Encodage de `vectors` | **Nb vecteurs (LVO)** | `structure` | `initFunction` |
|--------|-----------:|----------|:---------------------:|-------------|----------------|
| expansion.library | `0x1C8` = 456 | LONG absolu | **25** | présent | présent |
| ramlib.library | `0x0B2` = 178 | WORD relatif | **11** | présent | présent |
| audio.device | `0x27A` = 634 | WORD relatif | **6** | présent | présent |
| intuition.library | `0x564` = 1380 | LONG absolu | **78** | **NULL** | présent |
| mathffp.library | `0x022` = 34 | WORD relatif *(offsets signés, certains négatifs)* | **16** | présent | présent |

Remarques mesurées :
- Les comptes de vecteurs sont **exacts** (comptés jusqu'au terminateur dans la ROM).
- **intuition** : `structure = NULL` → aucune table InitStruct ; les champs de la base sont posés
  par `initFunction` seule. C'est le seul des cinq dans ce cas.
- **mathffp** : `dataSize = 0x22 = sizeof(struct Library)` (34) → aucune donnée d'instance au-delà
  du nœud de library ; sa table de vecteurs emploie des offsets WORD **signés** (des fonctions
  peuvent précéder la table — le format l'autorise).
- expansion/intuition emploient le format **LONG absolu** ; ramlib/audio/mathffp le format
  **WORD relatif**. Les deux formats coexistent dans la même ROM.
- Les autres modules (graphics, dos, layers, keymap/potgo/cia/disk/misc resources, keyboard/
  gameport/timer/input/console/trackdisk devices, romboot) ont `rt_Flags` **sans** AUTOINIT :
  leur `rt_Init` pointe sur du code d'init manuel (pas de table auto-init standard), donc leur
  nombre de LVO n'est pas mesurable sans tracer leur `MakeLibrary` — non reproduit ici.

## Relecture clean-room

Relecture du 2026-10-29.

- [x] Aucune suite d'instructions 68000 transcrite ni paraphrasée, aucun extrait de désassemblage.
- [x] **Corrigé** : la version initiale donnait, pour chacune des 24 ROMTags, l'offset fichier et
  l'adresse dans la ROM de la tag, de `rt_Name`, `rt_IdString`, `rt_Init` et `rt_EndSkip`, ainsi que
  les adresses des tables auto-init (`vectors`, `structure`, `initFunction`), la valeur du PC de reset,
  les bornes de la plage d'exec et les adresses servant à illustrer la règle de départage. Toutes ces
  adresses de routines/données ROM ont été retirées ; l'information comportementale est conservée
  (flags, type, priorité, révision, présence/absence des champs, comptes de LVO, ordre de départage à
  priorité égale exprimé en ordre relatif).
- [x] **Corrigé** : retirés le texte intégral de la bannière de copyright, la valeur du checksum de
  l'image et l'exemple d'offset négatif de la table mathffp (données ROM sans utilité d'ABI).
- [x] Restent : en-tête `0x1111`/`0x4EF9`, version 34.5, taille 256 Ko (format d'image Kickstart
  vérifié par `romtool`), constantes publiques `exec/resident.i` / `exec/nodes.i`, tailles des bases.
