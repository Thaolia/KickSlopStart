# Audit de similarité textuelle : notre assembleur face au code source d'AROS

Ce document répond à une question posée dans une issue GitHub : **le code de `src/` reprend-il du code
d'AROS ?** Le README affirme qu'AROS a été lu comme référence (en lecture seule) et que rien n'a été
copié. La mesure ci-dessous compare tout notre assembleur (`src/**/*.s`, `src/**/*.i`) au code source
d'AROS, puis situe le résultat par rapport au niveau « normal » des coïncidences entre programmes 68000
indépendants.

AROS est un projet public (licence APL). Les deux côtés sont donc cités librement, en extraits courts.

## Verdict

- **Pas de reprise de code AROS mesurable au-delà du bruit de fond, à une exception près, courte et
  imposée par l'ABI.** Au seuil de 20 tokens, 132 tokens sur 221 721 (0,06 %) coïncident textuellement
  avec l'assembleur AROS. Au seuil de 30 tokens, il en reste 69 (0,03 %), dans **deux passages
  seulement**.
- **Le seul passage notable** est l'entrée et le retour du runtime BCPL (`bcpl_call` / `bcpl_ret`,
  `src/dos/bcpl.s:51-62`). Ce sont 8 instructions, identiques à `BCPL_jsr` / `BCPL_rts` d'AROS
  (`arch/m68k-all/dos/bcpl.S:23-29` et `:55-58`).
  - La forme de ce code est dictée par l'ABI binaire des commandes BCPL du Workbench 1.3 : disposition
    du frame (-12/-8/-4), registres A1/A3/A4/D0, multiplication **obligatoirement** à `+$10` et division
    à `+$12`.
  - La séquence d'entrée fait **exactement 16 octets** (2 + 6 + 2 + 4 + 2), ce qui place `bra.s mul` à
    `+$10` sans remplissage. Il n'existe guère d'autre écriture aussi directe.
  - Voir « Correspondances notables » pour le détail et la recommandation.
- **Tout le reste est fait d'idiomes 68000 et Amiga** : sauvegarde/restauration `movem.l d2-d7/a2-a6`,
  copie `move.l (a0)+,(a1)+`, conversion BPTR `lsl.l #2`. On retrouve ces mêmes idiomes, en proportion
  comparable, dans du code Amiga tiers sans aucun lien avec AROS (VMM, AHI, diskimage).
- **Côté C** (l'essentiel d'AROS), aucun signal :
  - 4 n-grammes de commentaires en commun, tous expliqués ;
  - les identifiants partagés hors ABI sont des noms descriptifs génériques ;
  - les constantes « magiques » partagées sont toutes publiques (HRM, formats documentés).
- **La méthode détecte bien une vraie copie.** Un témoin positif (deux fichiers AROS translittérés en
  syntaxe vasm, labels renommés, commentaires remplacés) est retrouvé à 62–100 % de couverture, avec des
  passages de 76 à 199 tokens. Nos fichiers réels plafonnent à 42 tokens.

## Entrées

| Élément | Valeur |
|---|---|
| Notre code | `src/` au commit `ec9f9ab`, plus les modifications non commitées de `src/intuition/` présentes au moment de la mesure ; 75 fichiers `.s`/`.i`, 221 721 tokens (niveau exact) |
| AROS | dépôt officiel `aros-development-team/AROS`, commit `4dbf6509f4fea9a48643ec39565f60c9a6acac9a` (2026-10-29), clone partiel (sparse) des sous-arbres listés plus bas |
| Outil | `tests/audit_aros_similarity.py` (Python 3, bibliothèque standard seule) |

### Copie locale `third_party/aros` : insuffisante pour l'audit

La copie de travail du projet est un clone partiel (`blob:none`) en *sparse checkout*, commit `30cdf16`.
Elle ne contient que les sous-arbres suivants :

- `rom/dos` ;
- `arch/m68k-all/dos` (`bcpl.S`, `bcpl_writef.S`, `callentry.S`, `bcpl.inc`…) ;
- `arch/m68k-amiga/dos` ;
- `compiler/include/dos`.

Il manque donc :

- les autres bibliothèques : `rom/exec`, `rom/graphics`, `rom/intuition`, `rom/hyperlayers` (layers
  d'AROS), `rom/expansion`, `rom/devs/*`, `rom/timer`, `rom/keymap`, `rom/filesys` ;
- `workbench/libs/{workbench,icon,mathffp}` ;
- l'asm `arch/m68k-*` hors dos ;
- tous les en-têtes publics hors `dos`, ce qui réduit la liste blanche ABI ;
- tout corpus sans rapport pour la base de comparaison.

L'outil tourne sur cette copie et affiche alors un avertissement. Ses résultats y sont cohérents avec
ceux de l'audit complet : plus long passage de 39 tokens (le même passage BCPL), 0,046 % de couverture
à k = 20. Ils ne suffisent toutefois pas à conclure. L'audit de référence utilise un clone partiel plus
large (voir « Commandes »).

### Ce qui est comparable dans AROS

- **AROS est écrit en C** : exec, dos, graphics, intuition, layers, devices… Son assembleur 68000 se
  limite à des primitives.
- Corpus « AROS comparable » : 65 fichiers, 22 757 tokens. Il comprend :
  - le runtime BCPL de dos (`bcpl.S`, `bcpl_writef.S`, `callentry.S`), soit 38 % de ce corpus ;
  - exec : `Dispatch`, `Switch`, `Wait`, `Supervisor`, `StackSwap`, `CopyMem*`, caches, `Forbid`… ;
  - le démarrage ROM (`arch/m68k-amiga/boot`) et les stubs blitter/layers de graphics ;
  - utility (multiplication/division 32/64 bits) et mathffp (`spcmp`, `sptst`).
- C comparable : 2 439 fichiers `.c`/`.h` de `rom/`, `arch/m68k-*`, `workbench/{libs,c,fs,devs,system}`.
- Corpus « sans rapport » : 202 fichiers asm, 374 229 tokens, plus 1 308 fichiers C. Il se compose :
  - du code tiers vendu dans l'arbre AROS : FPSP/ISP Motorola 68060 (`m680x0/`), `libgcc1`, `stdc`,
    `posixc`, `inflate`, `rexxsyslib`, `mathieee*` ;
  - de pilotes et applications Amiga tiers : AHI, diskimage, réseau, VMM, pfs3.
  - Sous-ensemble **« Amiga tiers »** : VMM, AHI et diskimage (86 fichiers, 52 214 tokens). C'est du
    logiciel système Amiga en asm, écrit hors du projet AROS, avec les mêmes conventions d'appel que
    nous. C'est la base la plus exigeante.

## Méthode

### asm contre asm : empreintes de tokens (type MOSS)

1. **Canonicalisation des dialectes.** Nous utilisons vasm en syntaxe Motorola. AROS utilise GNU as
   avec `%reg`, la syntaxe MIT `a0@+` / `sp@-` / `a6@(8)` ou la syntaxe Motorola, `0x` ou `$`. Après
   canonicalisation, les deux côtés écrivent `move.l (a0)+,-(a7)`.
   - `sp` devient `a7` ; les suffixes MIT (`movel`) deviennent `move.l` ; `jbsr`/`jra`/`jXX` deviennent
     `bsr`/`bra`/`bXX`.
   - La taille des branchements est retirée : c'est un choix de l'assembleur.
   - Les nombres sont convertis en décimal.
   - Commentaires et directives purement déclaratives (`xdef`, `section`, `.globl`, `include`…) sont
     retirés.
2. **Trois niveaux de normalisation** :
   - `exact` : identifiants, nombres et registres conservés (minuscules) ;
   - `norm` : identifiants → `ID`, nombres → `N`, chaînes → `S` ; les définitions de labels et les
     déclarations (`equ`, `dc`/`ds`, macros de structure) sont retirées, sinon toute table « `NOM equ N` »
     ressemble à toute autre ;
   - `struct` : `norm`, plus registres génériques (`D`/`A`) et mnémoniques fusionnées (`addq`/`addi`/`adda`
     → `add`, `jsr`/`bsr` → `call`, `jmp`/`bra` → `jump`…).
3. **Empreintes.** On calcule les k-grammes de tokens (k = 12, 20, 30), un hachage déterministe (crc32)
   et le *winnowing* (Schleimer et al., 2003) avec une fenêtre w = 8. Le recouvrement par paire de
   fichiers vaut |F(nous) ∩ F(AROS)| / |F(nous)|.
4. **Passages communs maximaux.** Un index complet des k-grammes du corpus cible sert à étendre chaque
   correspondance à sa longueur maximale. Chaque passage est vérifié token par token, sans faux positif
   de hachage. Pour chacun, on relève le fichier et les lignes des deux côtés.
   - **Couverture** : % de nos tokens situés dans un passage commun d'au moins k tokens.
   - Un k-gramme présent plus de 200 fois dans le corpus cible est jugé banal et ne sert pas de point de
     départ.

Ordre de grandeur : une instruction 68000 fait 4 à 8 tokens (`move.l ( a0 ) + , d1` = 8). k = 12
correspond donc à environ 2 instructions, k = 20 à 3–4, k = 30 à 5–6.

### asm contre C : commentaires, identifiants, constantes

Comparer des tokens d'asm à des tokens de C n'aurait pas de sens. On compare plutôt :

- **Les commentaires.** On cherche les 5-grammes de mots communs entre nos commentaires et ceux d'AROS
  (C et asm).
  - **Biais** : nos commentaires sont en français (6 789 lignes identifiées français, 5 lignes
    classées anglais, dont 4 faux positifs), ceux d'AROS en anglais.
  - Une traduction littérale d'un commentaire AROS échapperait donc à cette mesure ; seules les
    citations en anglais sont détectables.
- **Les identifiants.** On compare nos labels et symboles aux identifiants du C et de l'asm AROS, sans
  tenir compte de la casse ni des `_`, et après retrait du préfixe `LVO_`/`_LVO`. Seuls les noms d'au
  moins 6 caractères sont retenus.
  - **Liste blanche ABI** : tout identifiant présent dans un en-tête public d'AROS (`compiler/include`
    et les dossiers `include/` des modules, par exemple `rom/devs/console/include` → `devices/conunit.h`)
    ou dans les listes de fonctions `.conf`/`.fd`.
  - Cela fait 30 249 identifiants : noms de LVO, champs des structures NDK, constantes des en-têtes
    publics. Ces noms sont imposés par l'ABI et ne prouvent rien.
- **Les constantes « magiques ».** On garde les valeurs ≥ `$1000` qui ne sont :
  - ni multiples de 100 ;
  - ni des masques de bits contigus ;
  - ni dans les plages d'adresses matérielles du HRM ;
  - ni présentes dans les en-têtes publics.

### Bases de comparaison

- **src → asm Amiga tiers** (VMM, AHI, diskimage) et **src → tout l'asm sans rapport** : même calcul,
  autres cibles.
- **Base à taille égale.** La couverture augmente avec la taille du corpus cible. On tire donc 5
  sous-ensembles aléatoires (graines 0 à 4) de l'asm Amiga tiers, chacun de la taille du corpus AROS
  comparable (22 757 tokens), et on y mesure la couverture de notre code.
- **BASE : AROS comparable → asm Amiga tiers** : le niveau de recouvrement entre AROS et du code Amiga
  indépendant.
- **Témoin positif** (hors outil, scripts jetables non versionnés), pour vérifier que l'outil voit une
  vraie copie :
  - deux fichiers AROS, `arch/m68k-all/exec/dispatch.S` et `arch/m68k-all/dos/bcpl_writef.S`, ont été
    translittérés automatiquement en syntaxe vasm Motorola ;
  - leurs labels ont été renommés (`ks_…`, `.nN`), leurs commentaires retirés et un commentaire
    français ajouté sur chaque ligne ;
  - les deux fichiers ont été ajoutés à une copie de `src/` ;
  - l'outil a ensuite été lancé sur cette copie.

## Commandes

```sh
# 1. Clone partiel d'AROS limité aux sous-arbres utiles (environ 56 Mo hors .git)
git clone --filter=blob:none --sparse --depth 1 https://github.com/aros-development-team/AROS.git aros
cd aros
git fetch --depth 1 origin 4dbf6509f4fea9a48643ec39565f60c9a6acac9a
git checkout FETCH_HEAD
git sparse-checkout set --no-cone '/arch/m68k-all/' '/arch/m68k-amiga/' '/rom/exec/' '/rom/dos/' \
  '/rom/graphics/' '/rom/intuition/' '/rom/hyperlayers/' '/rom/expansion/' '/rom/devs/console/' \
  '/rom/devs/gameport/' '/rom/devs/input/' '/rom/devs/keyboard/' '/rom/devs/trackdisk/' '/rom/timer/' \
  '/rom/keymap/' '/rom/utility/' '/rom/misc/' '/rom/disk/' '/rom/filesys/' '/rom/dosboot/' \
  '/rom/lddemon/' '/rom/kernel/' '/rom/hidds/' '/workbench/libs/mathffp/' '/workbench/libs/workbench/' \
  '/workbench/libs/icon/' '/workbench/devs/' '/workbench/c/' '/workbench/system/' '/workbench/fs/' \
  '/compiler/include/'
cd ..

# 2. Audit (environ 2 minutes ; rapport Markdown sur stdout, résultats bruts en JSON)
python3 -I tests/audit_aros_similarity.py src aros -k 12 20 30 --limit 20 --json audit.json > audit.md
```

Options utiles :

- `-w` : fenêtre de winnowing ;
- `--levels` : niveaux de normalisation à calculer ;
- `--unrelated` / `--amiga-tiers` : motifs de chemins des corpus de base ;
- `--shingle` : taille des n-grammes de commentaires ;
- `--ident-min-len` : longueur minimale des identifiants comparés ;
- `--draws` : nombre de tirages de la base à taille égale.

## Résultats

### asm contre asm : couverture de notre code (% des tokens)

« Base taille égale » donne la moyenne et l'intervalle [min–max] de 5 tirages d'asm Amiga tiers de
22 757 tokens (21 195 aux niveaux norm/struct).

| k | niveau | src → AROS comparable | src → base taille égale (Amiga tiers) | src → Amiga tiers (52 k tokens) | src → tout l'asm sans rapport (374 k) | BASE : AROS comparable → Amiga tiers |
|---|---|---|---|---|---|---|
| 12 | exact | 2,876 | 1,563 [0,969–2,071] | 2,642 | 2,957 | 6,402 |
| 12 | norm | 6,362 | 8,698 [7,361–10,538] | 12,751 | 14,249 | 13,286 |
| 12 | struct | 28,552 | 34,192 [28,806–40,188] | 42,646 | 49,337 | 30,073 |
| 20 | exact | **0,060** | 0,004 [0–0,009] | 0,009 | 0,009 | 0 |
| 20 | norm | 0,517 | 0,438 [0,241–0,713] | 0,835 | 0,845 | 0,193 |
| 20 | struct | 3,309 | 3,126 [1,748–4,431] | 4,939 | 5,986 | 2,085 |
| 30 | exact | **0,031** | 0 | 0 | 0 | 0 |
| 30 | norm | 0,139 | 0,003 [0–0,017] | 0,017 | 0,017 | 0 |
| 30 | struct | 0,622 | 0,056 [0–0,087] | 0,104 | 0,330 | 0,311 |

Lecture du tableau :

- **Niveaux norm et struct.** Notre code ressemble moins à AROS qu'à du code Amiga tiers de même
  taille, ou guère plus.
- **Niveau exact à k = 12.** L'excédent sur la base (2,9 % contre 1,6 %) s'explique par la composition
  du corpus AROS.
  - Ce corpus est petit, centré sur les mêmes conventions d'appel que nous, et à 38 % fait du runtime
    BCPL que nous implémentons aussi.
  - Les 199 passages distincts sont dominés par `movem.l (a7)+,d2-d7/a2-a6` / `rts`,
    `movem.l d0-d1/a0-a1,…` et `move.l (a0)+,(a1)+`.
  - L'asm AROS lui-même partage deux fois plus (6,4 %) avec le code Amiga tiers.
- **Niveau exact à k ≥ 20 et niveaux norm/struct à k = 30.** L'excédent tient entièrement aux quelques
  passages listés plus bas : 132 tokens au total à k = 20 exact.

### Recouvrement d'empreintes par paire de fichiers (maximum sur toutes nos paires)

| k | exact | norm | struct |
|---|---|---|---|
| 12 | 1,45 % (`exec/romboot.s` ↔ `bcpl.S`, 2 empreintes) | 3,33 % | 8,57 % |
| 20 | 0,24 % (`dos/bcpl.s` ↔ `bcpl.S`) | 0,38 % | 1,79 % |
| 30 | 0,08 % (`dos/bcpl.s` ↔ `bcpl.S`) | 0,05 % | 0,11 % |

### Témoin positif (copie translittérée et renommée)

| Fichier témoin | k = 12 exact | k = 12 norm | k = 30 norm | recouvrement par paire (k = 12 norm) | plus long passage |
|---|---|---|---|---|---|
| `bcpl_writef.S` translittéré | 89,6 % | 100 % | 99,3 % | 93,1 % | 199 tokens (norm) |
| `dispatch.S` translittéré | 75,8 % | (\*) | 62,0 % | 54,2 % | 76 tokens |

(\*) Ce fichier n'apparaît pas dans le top 15 par tokens couverts à ce niveau ; il est couvert à 62 %
aux niveaux k = 20 et k = 30.

L'outil retrouve donc une vraie copie, même reformatée et renommée, avec des scores au moins 25 fois
supérieurs à ceux de nos fichiers réels. Il voit aussi une copie réelle à l'intérieur même de l'arbre
AROS : `arch/m68k-all/exec/stackswap.S:54-108` ↔ `rom/filesys/pfs3/fs/m68k/stackswap.S:57-112`,
160 tokens, 97 % de recouvrement.

### Commentaires (5-grammes de mots)

60 136 n-grammes chez nous, 169 240 chez AROS, **4 en commun** :

| Chez nous | Chez AROS | Nature |
|---|---|---|
| `src/dos/dos_lib.s:181` : « AutoDoc : *All three elements are zero if the date is unset* » (2 n-grammes) | `rom/dos/datestamp.c:41` (bloc AutoDoc de `DateStamp`) | Citation explicite, entre guillemets et attribuée à « AutoDoc », d'une phrase décrivant le comportement public de `DateStamp()` |
| `src/dos/bcpl.s:1072`, `src/exec/keyboard.s:90`, `src/graphics/gfx.s:22` : liste « d0 d1 a0 a1 a2 » | `arch/m68k-all/dos/bcpl.S:1669` | Liste de registres |
| `src/intuition/menus.s:1041` : champs « Left, Top, Width, Height, Depth » de `struct Image` | `rom/intuition/openscreentaglist.c:248` | Noms de champs publics |

### Identifiants

- Nous avons 8 374 identifiants distincts.
  - Avec AROS comparable : 903 en commun, dont 784 sur la liste blanche ABI. Il reste **53** noms
    d'au moins 6 caractères hors ABI.
  - Avec AROS sans rapport : 557 en commun, dont 470 ABI. Il reste **21** noms hors ABI.
- Les 53 noms ont tous été relus. Ils se répartissent ainsi :
  - **Nom de fonction public + préfixe de module** : `exec_openlibrary` ↔ `ExecOpenLibrary`,
    `dos_expunge` ↔ `DosExpunge`, `intuition_open`, `timer_open`, `cia_init` ↔ `Cia_Init`,
    `cia_romtag`, `romboot_end`, `gfx_vblank`, `dev_open`/`dev_close`.
  - **Mots génériques** : `delete`, `frame_size`, `task_name`, `input_size`, `msg_fail`, `c_block`,
    `cb_next`.
  - **Collisions de casse avec des noms publics** : notre `TD_MOTORON` (octet d'état en RAM basse) ↔
    `td_motoron` (fonction AROS) ; nos labels `.findinput`/`.findoutput`/`.copydir`/`.diskinfo`, nommés
    d'après les actions de packets publiques `ACTION_*`.
  - **Préfixe de champ de structure `Layer`** : nos équivalences `LY_FRONT`… `LY_LOCK`… `LY_DAMAGE`
    (série complète, `src/graphics/layers.s:37`, `draw.s:76`). AROS ne génère que `ly_Lock`
    (`compiler/include/asm.c:166`). L'abréviation « LaYer » est naturelle et la série chez nous est
    bien plus large : coïncidence de nommage sans portée.
- Le taux hors ABI (53 sur 41 856 noms côté AROS comparable) est du même ordre que contre le corpus
  sans rapport (21 sur 55 724). Aucun nom interne distinctif d'AROS n'apparaît.

### Constantes

- Nous avons 805 valeurs distinctes, dont 175 non triviales.
  - En commun avec AROS comparable : 22 « magiques » hors en-têtes publics.
  - En commun avec AROS sans rapport : 31.
- Toutes celles de la liste comparable sont publiques ou banales :
  - **mot de synchronisation MFM** `$4489` / `$44894489` (HRM) ;
  - **identifiants 4 caractères** `'CON\0'`, `'RAW\0'`, `'BAD\0'`, `'BUSY'`, `'HELP'` ;
  - **fréquence E-clock PAL** 709 379 Hz (`$AD303`) ;
  - **format FFP** `$80000041` (1,0 en FFP) ;
  - **valeurs de registres custom** `$2C81` (DIWSTRT standard) et `$8240` (DMACON) ;
  - **motifs** `$DEADBEEF`, `$11111111`, `$8888`, `$2222`, `$F0F0`, `$80008000`, `$30003`, `$20003`.
- Aucune constante privée propre à AROS.

## Correspondances notables

| # | Chez nous | Chez AROS | Longueur | Nature |
|---|---|---|---|---|
| 1 | `src/dos/bcpl.s:51-57` (`bcpl_call`) | `arch/m68k-all/dos/bcpl.S:23-29` (`BCPL_jsr`) | 39 tokens exact, 7 instructions + 2 `bra.s` | Entrée BCPL, imposée par l'ABI (voir ci-dessous) |
| 2 | `src/dos/bcpl.s:59-62` (`bcpl_ret`) | `arch/m68k-all/dos/bcpl.S:55-58` (`BCPL_rts`) | 23 tokens exact, 3 instructions | Retour BCPL, imposé par l'ABI |
| 3 | `src/dos/handler.s:962-964` | `arch/m68k-all/exec/copymem_020.S:51-53` | 30 tokens, 3 × `move.l (a0)+,(a1)+` | Copie d'une `DateStamp` de 12 octets : idiome |
| 4 | `src/dos/bcpl.s:1892-1896` (`g_compstamp`) | `arch/m68k-all/dos/bcpl.S:831-835` | 20 tokens | Conversion BPTR → adresse (`lsl.l #2` puis `move.l` vers An), deux fois : idiome BCPL universel |
| 5 | `src/graphics/layers.s:1174-1183` et une dizaine d'autres fins de fonctions | `arch/m68k-all/dos/callentry.S:118-129` | 20–36 tokens | `movem.l (a7)+,d2-d7/a2-a6` / `rts` / `movem.l d2-d7/a2-a6,-(a7)` : convention de registres Amiga, aussi présente dans AHI et VMM |
| 6 | `src/dos/bcpl.s:2107-2115` (writef `%S %T %C…`), `src/exec/rawdofmt.s:83-91` | `arch/m68k-all/dos/bcpl.S:1218-1226` (lecture de nombre) | 33 tokens, niveau struct seulement | Chaîne `cmp.b #c,Dn` / `beq` sur des caractères différents : même forme, code différent |

### Le passage BCPL (n° 1 et 2) en détail

Chez nous (`src/dos/bcpl.s:51-62`) :

```
bcpl_call:
        move.l  (sp)+,a3
        movem.l a1/a3-a4,-12(a1,d0.l)
        adda.l  d0,a1
        movem.l d1-d4,(a1)
        jmp     (a4)
        bra.s   bcpl_mul             ; bcpl_call+$10
        bra.s   bcpl_divmod          ; bcpl_call+$12
bcpl_ret:
        movem.l -12(a1),a1/a3
        move.l  -4(a1),a4
        jmp     (a3)
```

Chez AROS (`arch/m68k-all/dos/bcpl.S:23-29`, `:55-58`), on trouve les mêmes instructions en syntaxe
GNU (`%sp@+`, `%a1`…). Les routines qui suivent diffèrent entièrement :

- chez AROS, `BCPL_jsr_mult` / `_divmod` appellent `__mulsi3` / `__modsi3` / `__divsi3` de GCC ;
- chez nous, `bcpl_mul` / `bcpl_divmod` sont des multiplications et divisions 32 bits écrites à la main
  avec `mulu.w` / `divu.w`.

Le reste de `bcpl.s` (3 027 lignes : vecteur global, 150 globales, `writef`, `rdargs`, `splitname`…)
partage peu de chose avec `bcpl.S` :

- **niveau exact** : aucun passage de plus de 20 tokens ;
- **niveau norm** : un seul, de 22 tokens (`bcpl.s:1892`, double conversion BPTR) ;
- **niveau struct** (registres et noms effacés) : 34 tokens au plus. Ce sont des conversions BPTR suivies
  d'une boucle d'octets et des chaînes `cmp.b`/`beq`, soit environ 5 instructions de forme banale.

Ce passage est contraint par l'ABI, et non par un choix d'écriture :

- les commandes BCPL du Workbench 1.3 font `jsr (a5)` pour appeler, `jsr $10(a5)` pour multiplier et
  `jsr $12(a5)` pour diviser ;
- l'appelé lit ses arguments dans le frame à partir de A1, et l'ancien A1, le retour et la routine
  appelée à -12/-8/-4.

L'entrée doit donc tenir en exactement 16 octets avant les deux `bra.s`. La séquence ci-dessus fait
2 + 6 + 2 + 4 + 2 = 16 octets. C'est l'expression minimale de cette convention, et AROS est arrivé à la
même. L'en-tête de `bcpl.s` indique d'ailleurs qu'AROS `arch/m68k-all/dos` a été lu comme référence
(« lecture seule, rien copié »). La ressemblance textuelle de ces 10 lignes est donc réelle, et elle est
documentée.

**Recommandation** (au choix des mainteneurs, aucune n'est requise pour la conformité) :

- (a) **conserver** le passage en ajoutant dans `bcpl.s` un commentaire qui dit que la séquence est
  imposée (16 octets, `+$10`/`+$12`) et identique à celle d'AROS `BCPL_jsr`/`BCPL_rts` ;
- (b) **réécrire** l'entrée avec une autre séquence de 16 octets fonctionnellement équivalente, par
  exemple en sauvant l'ancien A1, le retour et A4 par trois `move.l` après `adda.l`, puis en ajustant le
  remplissage. On obtient ainsi une identité textuelle nulle, au prix d'un code un peu moins direct.

### Citation AutoDoc (commentaires)

La phrase « *All three elements are zero if the date is unset* » est citée entre guillemets et
attribuée à l'AutoDoc. Si elle provient de l'AutoDoc AROS et non de l'AutoDoc Commodore, il suffit de
corriger l'attribution, ou de la reformuler en français.

## Limites

- **Portée du code comparé.** AROS est presque entièrement en C ; l'asm comparable ne fait que 22 757
  tokens, environ 10 % de notre code.
  - Une transcription de C AROS en assembleur (même algorithme, même découpage) ne laisse pas de trace
    lexicale. Ni cet outil, ni aucune comparaison textuelle ne la détecterait.
  - Seule une revue de conception le ferait. La discipline de salle blanche décrite dans
    `docs/CLEANROOM.md` répond à ce risque.
- **Biais de langue.** Nos commentaires sont en français, ceux d'AROS en anglais. La comparaison de
  commentaires ne voit que les citations anglaises, pas les traductions.
- **Version d'AROS.** La mesure porte sur AROS au 2026-10-29. Un passage présent dans une version plus
  ancienne d'AROS, consultée à l'époque puis réécrite chez eux depuis, échapperait à cette mesure.
  `arch/m68k-all/dos/bcpl.S` et `callentry.S` existent toutefois sous cette forme depuis longtemps.
- **Liste blanche.** Elle est construite depuis les en-têtes AROS, pas depuis le NDK Commodore.
  - Un nom public du NDK absent des en-têtes AROS apparaîtrait à tort comme « hors ABI ». L'erreur va
    dans le sens prudent : elle surestime.
  - La comparaison d'identifiants ignore la casse et les `_`, ce qui surestime aussi les collisions.
- **Base de comparaison.** Le corpus Amiga tiers (VMM, AHI, diskimage) a son propre style. La base à
  taille égale varie d'un tirage à l'autre, d'où les intervalles [min–max] donnés.
- **Paramètres.** Avec k = 12 (environ 2 instructions), les idiomes dominent ; à partir de k = 20, la
  mesure devient discriminante. Les résultats sont donnés pour trois valeurs de k afin que le lecteur
  juge la stabilité.
- **Autre source possible.** Cet audit ne couvre que la relation avec AROS. La relation avec la ROM
  Commodore fait l'objet d'un audit distinct : `docs/audit/rom-similarity.md`.
