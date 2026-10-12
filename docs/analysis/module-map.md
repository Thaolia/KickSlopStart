# module-map.md — Carte des 24 ROMTags (Kickstart 1.3 / V34.5, `kick34005.A500`)

> Piste ANALYSE (« dirty »). Faits dérivés UNIQUEMENT de la lecture radare2 de la ROM
> (256 Ko, 68000 big-endian, base $FC0000). Aucun listing d'instructions n'est reproduit :
> seuls adresses, offsets, tailles, flags et constantes d'ABI figurent ici.
>
> Provenance : toutes les colonnes sont **mesurées dans la ROM** sauf la décomposition
> nominale des flags/types (constantes d'ABI publiques, `exec/resident.i`, `exec/nodes.i`).

## En-tête ROM (longwords à la base $FC0000)

| Offset | Valeur mesurée | Sens |
|-------:|----------------|------|
| +0x00 | `0x11114EF9` | SSP initial vu au reset = mot ROM-ID `0x1111` + opcode `0x4EF9` (JMP abs.l) |
| +0x04 | `0x00FC00D2` | PC de reset → coldstart exec (= `rt_Init` d'exec, cf. ci-dessous) |
| +0x08 | `0x0000FFFF` | — |
| +0x0C | `0x00220005` | **Version ROM = 34.5** (major `0x22`=34, minor `0x0005`=5) → Kickstart 1.3 |
| +0x10 | `0x00220002` | Marqueur secondaire 34.2 (coïncide avec la révision propre d'exec) |
| +0x14 | `0xFFFFFFFF` | — |
| +0x18 | ASCII | `"exec 34.2 (28 Oct 1987)\r\n"` (= `rt_IdString` d'exec) |
| +0x38 | ASCII | Bannière `"AMIGA ROM Operating System and Libraries / Copyright (C) 1985, Commodore-Amiga, Inc."` |

Pied de ROM (24 derniers octets, $FFFFE8..$FFFFFF) : champ de taille `0x00040000` (256 Ko)
+ longword d'allure checksum `0x15267DB3`. Non analysé plus avant (hors périmètre spec).

## Constantes de décodage (ABI publique)

- `rt_Flags` : `RTF_AUTOINIT=0x80` · `RTF_AFTERDOS=0x04` · `RTF_SINGLETASK=0x02` · `RTF_COLDSTART=0x01`.
- `rt_Type` (`exec/nodes.i`) : `NT_UNKNOWN=0` · `NT_TASK=1` · `NT_DEVICE=3` · `NT_RESOURCE=8` · `NT_LIBRARY=9`.
- `rt_Version` est un **UBYTE** = numéro **majeur** seulement (34). La révision (`.1`/`.2`/`.3`/`.4`)
  n'existe que dans `rt_IdString` ; elle n'est PAS stockée dans la Resident struct en V34.

## Tableau des 24 ROMTags (ordre de priorité décroissante = ordre d'init, cf. règle de tri plus bas)

Adresse = $FC0000 + offset fichier. Tous : `rt_MatchWord=0x4AFC`, `rt_MatchTag`→lui-même, `rt_Version=34`.

| # | Module | Off. fichier | Adresse | `rt_Flags` | Flags décodés | `rt_Type` | Pri | `rt_Name` | `rt_IdString` (rév.) | `rt_Init` | `rt_EndSkip` |
|--:|--------|-------------:|---------|:----------:|---------------|:---------:|----:|-----------|----------------------|-----------|--------------|
| 1 | exec.library | 0x0000B6 | $FC00B6 | `0x00` | *(aucun)* | `9` LIBRARY | 120 | $FC00A8 | $FC0018 (34.2) | **$FC00D2** | $FC3276 |
| 2 | expansion.library | 0x004B64 | $FC4B64 | `0x81` | AUTOINIT+COLDSTART | `9` LIBRARY | 110 | $FC4BB0 | $FC4B7E (34.1) | $FC4BA0 | $FC51D8 |
| 3 | potgo.resource | 0x0243DC | $FE43DC | `0x01` | COLDSTART | `8` RESOURCE | 100 | $FE43F6 | $FE4406 (34.1) | $FE4424 | $FE4524 |
| 4 | keymap.resource | 0x024B44 | $FE4B44 | `0x01` | COLDSTART | `8` RESOURCE | 100 | $FE4B5E | $FE4B6E (34.1) | $FE7F24 | $FE4B8E |
| 5 | cia.resource | 0x004574 | $FC4574 | `0x01` | COLDSTART | `8` RESOURCE | 80 | $FC458E | $FC45B8 (34.1) | $FC45E0 | $FC47F8 |
| 6 | disk.resource | 0x0047FC | $FC47FC | `0x01` | COLDSTART | `8` RESOURCE | 70 | $FC4816 | $FC4824 (34.1) | $FC4840 | $FC4B5C |
| 7 | misc.resource | 0x0242D0 | $FE42D0 | `0x01` | COLDSTART | `8` RESOURCE | 70 | $FE42EA | $FE42F8 (34.1) | $FE4314 | $FE43D8 |
| 8 | ramlib.library | 0x024528 | $FE4528 | `0x80` | AUTOINIT *(pas COLDSTART)* | `9` LIBRARY | 70 | $FE45BC | $FE4542 (34.1) | $FE4560 | $FE4AC8 |
| 9 | graphics.library | 0x0053E4 | $FC53E4 | `0x01` | COLDSTART | `9` LIBRARY | 65 | $FC53FE | $FC540F (34.1) | $FCABA2 | $FD08B8 |
| 10 | keyboard.device | 0x024B8E | $FE4B8E | `0x01` | COLDSTART | `3` DEVICE | 60 | $FE4BA8 | $FE4BB8 (34.1) | $FE4F44 | $FE4BDA |
| 11 | gameport.device | 0x024BDA | $FE4BDA | `0x01` | COLDSTART | `3` DEVICE | 60 | $FE4BF4 | $FE4C04 (34.1) | $FE53B0 | $FE4C26 |
| 12 | timer.device | 0x028D6C | $FE8D6C | `0x01` | COLDSTART | `3` DEVICE | 50 | $FE8D86 | $FE8D94 (34.1) | $FE8DF4 | $FE9558 |
| 13 | audio.device | 0x003508 | $FC3508 | `0x81` | AUTOINIT+COLDSTART | `3` DEVICE | 40 | $FC3522 | $FC3530 (34.1) | $FC354C | $FC445C |
| 14 | input.device | 0x024C26 | $FE4C26 | `0x01` | COLDSTART | `3` DEVICE | 40 | $FE4C40 | $FE4C4E (34.1) | $FE5AD0 | $FE4C6C |
| 15 | layers.library | 0x0209A4 | $FE09A4 | `0x01` | COLDSTART | `9` LIBRARY | 31 | $FE0994 | $FE09BE (34.1) | $FE0A2C | $FE0A0C |
| 16 | console.device | 0x024C6C | $FE4C6C | `0x01` | COLDSTART | `3` DEVICE | 20 | $FE4C86 | $FE4C96 (34.1) | $FE66E4 | $FE6234 |
| 17 | trackdisk.device | 0x029564 | $FE9564 | `0x01` | COLDSTART | `3` DEVICE | 20 | $FE957E | $FE9590 (34.1) | $FE97BE | $FEB05C |
| 18 | intuition.library | 0x013D8C | $FD3D8C | `0x81` | AUTOINIT+COLDSTART | `9` LIBRARY | 10 | $FD3DCA | $FD3D64 (34.3) | $FD3DA6 | $FDFF94 |
| 19 | alert.hook | 0x003276 | $FC3276 | `0x01` | COLDSTART | `0` UNKNOWN | 5 | $FC3269 | $FC3269 *(nom seul)* | $FC3128 | $FC3290 |
| 20 | mathffp.library | 0x023DA4 | $FE3DA4 | `0x81` | AUTOINIT+COLDSTART | `9` LIBRARY | 0 | $FE3DBE | $FE3DCE (34.1) | $FE3DEC | $FE4288 |
| 21 | workbench.task | 0x02B47C | $FEB47C | `0x00` | *(aucun)* | `1` TASK | 0 | $FEB4CA | $FEB464 (wb 34.1) | $FEB496 | $FF310C |
| 22 | dos.library | 0x033E62 | $FF3E62 | `0x00` | *(aucun)* | `9` LIBRARY | 0 | $FF4030 | $FF3E7C (34.3) | $FF3E94 | $FF3E94 |
| 23 | romboot.library | 0x02B060 | $FEB060 | `0x01` | COLDSTART | `9` LIBRARY | -40 | $FEB07A | $FEB08A (34.1) | $FEB0A8 | $FEB380 |
| 24 | strap | 0x0283E0 | $FE83E0 | `0x01` | COLDSTART | `0` UNKNOWN | -60 | $FE83FA | $FE8400 (34.4) | $FE8444 | $FE841A |

### Faits remarquables (mesurés)

- **exec** : `rt_Flags=0` (ni AUTOINIT ni COLDSTART), et `rt_Init = $FC00D2 = PC de reset`. exec
  n'est donc PAS initialisé par le balayage des résidents : le vecteur de reset saute directement
  dans son `rt_Init`, qui EST la routine de coldstart du noyau. `rt_EndSkip` d'exec (`$FC3276`)
  pointe exactement sur la ROMTag `alert.hook` → exec « possède » la plage $FC00B6..$FC3276.
- **Bits de timing présents dans cette ROM** : seul `RTF_COLDSTART` (0x01) parmi les trois bits
  « quand démarrer ». **Aucun** module n'a `RTF_SINGLETASK` (0x02) ni `RTF_AFTERDOS` (0x04).
- **Sans aucun bit de timing** : exec (0x00), **ramlib** (0x80 = AUTOINIT seul), workbench.task
  (0x00), dos (0x00). Ces quatre ne sont pas démarrés par la passe `InitCode(RTF_COLDSTART)`
  générique ; ils sont pris en charge par des chemins dédiés (exec = le noyau lui-même ; ramlib,
  dos et workbench.task par l'amorçage DOS/strap). Voir `boot-sequence.md`.
- **Types « UNKNOWN » (0)** : `alert.hook` (pri 5) et `strap` (pri -60) ne sont ni library ni
  device ni resource — ce sont des hooks de boot invoqués via `rt_Init`.
- **alert.hook** : `rt_Name == rt_IdString == $FC3269` (même chaîne « alert.hook ») et
  `rt_Init = $FC3128` se situe AVANT l'adresse de la tag ($FC3276).
- **dos** : `rt_Init == rt_EndSkip == $FF3E94`.
- Révisions par module (depuis `rt_IdString`) : exec **34.2**, intuition **34.3**, dos **34.3**,
  strap **34.4** ; tous les autres **34.1**. La ROM dans son ensemble s'identifie **34.5 / Release 1.3**.

### Règle de tri de la liste des résidents (= ordre d'initialisation)

Clé de tri : **`rt_Pri` décroissant, puis adresse ROM croissante** (le balayage ROM construit
la liste en ordre d'adresse croissante, le tri par priorité est stable). Confirmé par les égalités
de priorité mesurées :
- pri 100 : potgo ($FE43DC) < keymap ($FE4B44)
- pri 70 : disk ($FC47FC) < misc ($FE42D0) < ramlib ($FE4528)
- pri 60 : keyboard ($FE4B8E) < gameport ($FE4BDA)
- pri 40 : audio ($FC3508) < input ($FE4C26)
- pri 20 : console ($FE4C6C) < trackdisk ($FE9564)
- pri 0 : mathffp ($FE3DA4) < workbench.task ($FEB47C) < dos ($FF3E62)

L'ordre du tableau ci-dessus est donc l'ordre exact que la réimplémentation doit reproduire.

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

| Module | `rt_Init` | `dataSize` | `vectors` | Encodage | **Nb vecteurs (LVO)** | `structure` | `initFunction` |
|--------|-----------|-----------:|-----------|----------|:---------------------:|-------------|----------------|
| expansion.library | $FC4BA0 | `0x1C8` = 456 | $FC4BEE | LONG absolu | **25** | $FC4BC2 (présent) | $FC4C56 |
| ramlib.library | $FE4560 | `0x0B2` = 178 | $FE4570 | WORD relatif | **11** | $FE458A (présent) | $FE45CC |
| audio.device | $FC354C | `0x27A` = 634 | $FC3592 | WORD relatif | **6** | $FC355C (présent) | $FC3586 |
| intuition.library | $FD3DA6 | `0x564` = 1380 | $FD3DE6 | LONG absolu | **78** | **$00000000 (NULL)** | $FD3DB6 |
| mathffp.library | $FE3DEC | `0x022` = 34 | $FE3EB0 | WORD relatif *(offsets signés, certains négatifs)* | **16** | $FE3E1A (présent) | $FE3EAC |

Remarques mesurées :
- Les comptes de vecteurs sont **exacts** (comptés jusqu'au terminateur dans la ROM).
- **intuition** : `structure = NULL` → aucune table InitStruct ; les champs de la base sont posés
  par `initFunction` seule. C'est le seul des cinq dans ce cas.
- **mathffp** : `dataSize = 0x22 = sizeof(struct Library)` (34) → aucune donnée d'instance au-delà
  du nœud de library ; sa table de vecteurs emploie des offsets WORD **signés** (ex. 1er offset
  `0xFFD6` = −42 → fonction située avant la table).
- expansion/intuition emploient le format **LONG absolu** ; ramlib/audio/mathffp le format
  **WORD relatif**. Les deux formats coexistent dans la même ROM.
- Les autres modules (graphics, dos, layers, keymap/potgo/cia/disk/misc resources, keyboard/
  gameport/timer/input/console/trackdisk devices, romboot) ont `rt_Flags` **sans** AUTOINIT :
  leur `rt_Init` pointe sur du code d'init manuel (pas de table auto-init standard), donc leur
  nombre de LVO n'est pas mesurable sans tracer leur `MakeLibrary` — non reproduit ici.
