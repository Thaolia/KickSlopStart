# SetPatch 1.38 (disquette SysInfo) : remplacements installés, contrats d'ABI, cause du `jsr -$24(a6)`

Piste **ANALYSE** (« dirty »). Ce document décrit des **comportements et des contrats d'ABI seulement** :
registres attendus, champs lus/écrits, appels effectués, conditions. **Aucune suite d'instructions n'y est
recopiée** et il ne contient pas de pseudo-code ligne à ligne. La ROM Kickstart (`assets/kick34005.A500`)
n'a **pas** été ouverte. Il complète `docs/analysis/setpatch-disk-resource.md` (même binaire, analyse
antérieure) sans le remplacer.

## Provenance

- Fichier : `C:SetPatch_1.38` de `assets/test_adf/SysInfo.adf` (lecture seule), extrait par
  `xdftool … read c/SetPatch_1.38` dans un répertoire scratch. 5964 octets, md5
  `b78212216d1ddac4901d72199981b942`, chaîne de version « SetPatch 1.38 (24-Sep-90) ».
- Format hunk LOADSEG, 35 hunks. J'ai relogé les hunks à une base fictive avec un script Python
  (`python3 -I`), puis désassemblé avec radare2 (`-a m68k`). Toutes les fonctions citées ci-dessous ont
  été lues dans ce désassemblage.
- Invocation sur ce disque (`s/startup-sequence`) : **`C:SetPatch_1.38 > NIL:`**, donc **sans argument
  `r`**. Viennent ensuite `C:Initialize` puis `SYS:SysInfo/SysInfo`.

### Carte des hunks utiles

« Fichier » = offset du premier octet de données du hunk dans le fichier. « +x » = offset dans le hunk.

| Hunk | Type, taille | Fichier | Contenu (comportement) |
|---|---|---|---|
| 0 | CODE $218 | $0A8 | Startup C : parse des arguments, chemin Workbench, et `_exit` à +$1B2. **Seul `jsr -$24(a6)` du fichier, à +$1DC (fichier $284)** |
| 1 | DATA $10 | $300 | Variables globales : +0 SysBase, +4 **DOSBase** |
| 2 | CODE $224 | $31C | Segment BCPL « RUN » embarqué (taille stockée $22C, premier long $89) |
| 3 | CODE $3DC | $54C | `printf` à +0, `main` à +$30 |
| 4 | DATA $28C | $B70 | Chaînes (messages) |
| 5 | CODE $54 | $E08 | Nouveau **Alert** à +0. Ancien vecteur stocké à +$4E |
| 6 | CODE $1C | $E68 | Nouveau **UserState** à +0, callback superviseur à +$10 |
| 7 | CODE $B4 | $E90 | Installeur d'AllocEntry à +0, nouvel **AllocEntry** à +$1E |
| 8 | CODE $E0 | $F50 | Installeur RAD à +0, stub ColdCapture de 44 octets à +$B4 (seul code recopié) |
| 9 | CODE $78 | $103C | Installeur des vecteurs FPU à +0, adresse ROM mémorisée à +$38, 16 stubs à +$3C, partie commune à +$5E |
| 10 | CODE $CC | $10D8 | Scanner « mot dont l'octet haut vaut $61 » à +0, décodeur de branchement à +$1E, analyse de DeleteLayer à +$76 |
| 11 | DATA $0C | $11D8 | 3 pointeurs de routines « internes » de layers |
| 12 | CODE $3C | $11F0 | Nouveau **DeleteLayer** à +0 |
| 13 | CODE $CC | $1254 | Installeur disk.resource à +0, nouveau **GetUnit** à +$7C, nouveau **GiveUnit** à +$94, propriétaire à +$B0 (valeur initiale -1), ancien GetUnit à +$B4, ancien GiveUnit à +$B8, nom à +$BC |
| 14 | CODE $54 | $1348 | Nouveau **MrgCop** à +0, ancien à +$4E |
| 16 | CODE $3C | $13B4 | Pointeur du segment RUN à +0, glue **Execute** à +4 |
| 17 | CODE $14 | $1410 | Nouveau **SetFont** à +0, ancien à +$0E |
| 18 | CODE $30 | $1430 | Nouveau **FindName** à +0 |
| 19 | CODE $28 | $146C | « Location zero » à +0, callback superviseur à +$16 |
| 20 | CODE $38 | $14A0 | Nouveau **SetSoftStyle** à +0, ancien stocké à +$32 (jamais utilisé) |
| 29/30/31/28 | CODE | — | Stubs d'appel exec/dos (convention C → registres) et RawDoFmt/Write |

Ordre d'exécution dans `main` (hunk 3) : test de `?`, puis RAD si l'argument vaut `r`/`R`. Ensuite
`FindPort("SetPatch-01")` et, si le port existe, sortie avec le code 5. Sinon création et ajout du port.
Viennent ensuite, dans cet ordre, disk.resource, Alert, graphics, layers, le bloc exec (FPU, puis
AllocEntry, UserState, FindName), « location zero » et DOS Execute. En fin de `main` (+$3C0),
**`cli_Module` (CLI +$3C) est mis à 0**, puis `_exit(0)`.

---

## 1. Mémoire allouée, code recopié, contrats de chaque remplacement

### 1.1 Tous les appels AllocMem du programme

| Où | Taille | Flags | Usage | Libéré ? |
|---|---|---|---|---|
| Hunk 0 (startup) | $184 | `MEMF_PUBLIC\|MEMF_CLEAR` ($10001) | Tampon des arguments (argv + copie de la ligne). Le long +0 sert au filehandle « NIL: » du chemin Workbench | Oui, dans `_exit` |
| Hunk 3 (`main`) | 34 | `MEMF_PUBLIC\|MEMF_CLEAR` | MsgPort marqueur « SetPatch-01 » (`ln_Type` = NT_MSGPORT, puis AddPort) | Jamais |
| Hunk 8 (RAD) | 44 | AllocAbs près de `SysStkLower`, sinon `MEMF_PUBLIC\|MEMF_CHIP` (3) | **Seul code recopié** : stub ColdCapture | Jamais |
| Hunk 7 (nouvel AllocEntry, au runtime) | 16 + 8×n | `MEMF_CLEAR` seul ($10000) | Copie de la MemList pour le compte de l'appelant, puis une AllocMem par entrée | Par FreeEntry de l'appelant |

**Conclusion.** Hors chemin RAD, SetPatch **ne recopie aucun code** en mémoire allouée. Tous les
remplacements installés par SetFunction (et les 16 stubs FPU) s'exécutent **sur place, dans les hunks
chargés par LoadSeg**. Or ces hunks sont eux-mêmes des blocs AllocMem remplis par copie depuis le
fichier : c'est très probablement le « bloc alloué et recopié » observé (cf. §2). Le chemin RAD n'est pas
pris ici, pour trois raisons : il n'y a pas d'argument `r`, il faut `lib_Version` d'exec < 35, et il faut
`MaxLocMem` > $80000 (512K de chip donnent exactement $80000).

### 1.2 Conventions communes

- Tous les remplacements installés par SetFunction rendent la main à l'**ancienne fonction**, quand ils
  l'appellent, par **la valeur rendue par SetFunction** (d0), rangée dans une variable du hunk. Ils n'ont
  aucune adresse ROM fixe ni ne relisent la table de vecteurs. Exceptions : Alert (§1.3, saute à
  ancien+$30 ou +$88), DeleteLayer (§1.8, routines déduites du code de l'ancien) et les vecteurs FPU (§3).
- **SysBase lu en $4** : par tous les installeurs, par le nouveau GetUnit/GiveUnit (`ThisTask`), par le
  nouvel Alert (test de validité seulement) et par « location zero ». **Non lu** (a6 supposé valoir
  SysBase en entrée) par les nouveaux **AllocEntry** et **UserState**. FindName n'utilise pas a6.
- Aucun remplacement ne lit `AttnFlags`.

### 1.3 Alert (exec -108). Condition : exec `lib_Version` vaut 33 ou 34

- Installation : SetFunction, puis test de l'ancien vecteur. S'il n'est **pas** dans
  `$FC0000..$FFFFFF`, nouveau SetFunction avec l'ancien (annulation) et message « skipped (vector in use) ».
  Notre ROM est en $FC0000, donc le remplacement est **installé** (le message « Alert patched » le confirme).
- Entrée : d7 = numéro d'alerte, a5 = pointeur de paramètres (convention Alert). a6 n'est pas utilisé.
- Comportement : coupe le maître INTENA ($4000). Si le long en $0 vaut déjà `'HELP'`, saute directement
  au second point d'entrée. Sinon il écrit `'HELP'` en $0, le numéro d'alerte (bit 31 forcé) en $100 et
  **le long pointé par a5** en $104. Il faut donc a5 pair, sinon erreur d'adresse.
- Il teste ensuite la validité de SysBase en $4 (le pointeur doit avoir l'octet haut nul et être pair).
  S'il est valide, il **saute à ancienAlert + $30**, sinon à **ancienAlert + $88**. Ce sont des **points
  d'entrée internes à la ROM 1.3, calculés depuis l'ancien vecteur**. Il ne revient jamais.

### 1.4 AllocEntry (exec -222). Condition : exec ≤ 35

- Entrée : a0 = MemList source, **a6 = SysBase supposé** (aucune lecture de $4).
- Comportement : alloue une MemList neuve de 16 + 8×`ml_NumEntries` octets (`MEMF_CLEAR`). Elle reçoit
  `ml_NumEntries` (offset 14) et des champs de nœud à zéro. Pour chaque entrée (à 16 + 8i), la longueur
  (+4) est recopiée. Si elle est nulle, l'adresse vaut 0 ; sinon l'adresse est rendue par
  `AllocMem(me_Length, me_Reqs)`.
- En cas d'échec d'une entrée, il libère dans l'ordre inverse les entrées déjà obtenues puis la liste
  (même taille), et rend **les `me_Reqs` de l'entrée fautive avec le bit 31 posé**. Si l'allocation de la
  liste elle-même échoue, il rend $80000000.
- Sortie : d0 = MemList neuve. d2-d3/a2-a4 préservés ; d1/a0/a1 perdus. **L'ancien AllocEntry n'est
  jamais appelé.**

### 1.5 UserState (exec -156). Condition : exec ≤ 35

- Entrée : appelé **en mode superviseur**, d0 = pile superviseur à restaurer, **a6 = SysBase supposé**.
- Comportement : retire l'adresse de retour de la pile, met la pile courante dans USP, puis prend d0 comme
  nouveau SSP. Il appelle ensuite **exec Supervisor (-30) via a6 alors qu'il est déjà en mode
  superviseur**, avec a5 = callback (a5 de l'appelant mis de côté puis restauré).
- Le callback trouve à sp le cadre d'exception 68000 (SR.w, PC.l) que Supervisor a empilé. Il y remplace
  le PC par l'adresse de retour de l'appelant et efface le bit S du SR empilé. Le RTE renvoie alors
  l'appelant en mode utilisateur, sur sa pile.
- Il n'appelle jamais l'ancien UserState.

### 1.6 FindName (exec -276). Condition : exec ≤ 35

- Entrée : a0 = liste, a1 = nom. a6 n'est pas utilisé.
- Comportement : parcours depuis `lh_Head` jusqu'au nœud sentinelle (`ln_Succ` nul) en **ignorant les
  nœuds dont `ln_Name` (+10) est NULL**. La comparaison respecte la casse.
- Sortie : d0 = nœud ou 0. **a1 restauré**, a2 préservé. **a0 et d1 sont détruits** (a0 pointe dans une
  chaîne). Il n'appelle jamais l'ancien FindName.

### 1.7 disk.resource GetUnit (-18) et GiveUnit (-24). Condition : `lib_Version` ≤ 35

Ce correctif est déjà détaillé dans `setpatch-disk-resource.md` §1-3, et le désassemblage le confirme :

- Section critique faite à la main : INTENA $4000 et `IDNestCnt` (+$126) +1, puis -1 et INTENA $C000 si
  le compteur redevient négatif.
- Nouveau GetUnit : appelle l'ancien en lui transmettant les registres (a0 est écrasé). Si l'ancien rend
  d0 ≠ 0, le propriétaire devient `ThisTask` (+$114 lu via $4).
- Nouveau GiveUnit : saute à l'ancien si le propriétaire vaut `ThisTask` ou -1. Sinon il **avale l'appel**.
- **Ni l'un ni l'autre n'appelle quoi que ce soit via a6.** Le GiveUnit d'origine est atteint par un saut
  au pointeur mémorisé (hunk 13 +$B8). Aucun champ `dr_*` n'est touché.

### 1.8 layers DeleteLayer (-90). Condition : `lib_Version` ≤ 35

- Après SetFunction, **analyse du code de l'ancien DeleteLayer** (hunk 10 +$76) :
  - le mot situé à entrée+2 est décodé comme un branchement (déplacement 8 bits, ou 16 bits si l'octet
    bas est nul) ;
  - depuis la cible, le scanner cherche le premier mot dont l'octet haut vaut $61 (BSR) et décode sa
    cible, ce qui donne la routine n°1. Il reprend après ce BSR pour la routine n°2, puis pour la n°3.
  - Les trois adresses sont rangées dans le hunk 11.
- Nouveau DeleteLayer : entrée a1 = Layer. Il appelle la routine n°1 avec `Layer->LayerInfo` (+$44)
  **passé sur la pile** (convention C). Si elle rend un résultat ≠ 0, il appelle la routine n°2 avec le
  Layer, puis la n°3 avec le LayerInfo, et rend 1. Sinon il rend 0. Il n'appelle jamais l'ancien.
- **Dépendance totale à la forme du code de la ROM 1.3.** Sur notre layers, les trois cibles sont des
  adresses quasi arbitraires : elles pointent dans notre ROM, au voisinage du code de DeleteLayer.

### 1.9 graphics MrgCop (-210), SetFont (-66), SetSoftStyle (-90). Condition : `lib_Version` ≤ 35

- **MrgCop** : entrée a1 = View, **a6 = GfxBase supposé**. Il compare le bit LACE ($0004) de `View->Modes`
  (+16) à celui de `GfxBase->Modes` (+$9E). Si LACE vient d'apparaître dans la View, il parcourt les
  ViewPort depuis `View->ViewPort` (+0) par `vp_Next` (+0). Pour chaque ViewPort dont `Modes` (+32) a à
  la fois $2000 et LACE, il appelle **MakeVPort (-216) via a6**. Il finit par **sauter à l'ancien MrgCop**
  (pointeur mémorisé), a1 restauré.
- **SetFont** : entrée a0 = font, a1 = RastPort. Si l'un des deux est NULL, retour immédiat. Sinon saut à
  l'ancien (pointeur mémorisé), registres inchangés.
- **SetSoftStyle** : entrée a1 = RastPort, d0 = style, d1 = masque, **a6 = GfxBase supposé**. Il appelle
  AskSoftStyle (-84) via a6 pour obtenir les bits algorithmiquement possibles. Le nouvel `AlgoStyle` (+$38)
  vaut l'ancien `AlgoStyle` sans les bits (masque ∩ possibles), plus les bits (style ∩ masque ∩
  possibles). Il le stocke et rend `AlgoStyle | tf_Style` de `rp->Font` (+$34, champ +$16), d2 préservé.
  L'ancien n'est jamais appelé, bien que son pointeur soit stocké.

### 1.10 Remarque générale

Aucun de ces remplacements ne fait de `jsr` via a6 avec un déplacement de -24 (décimal). Les seuls appels
via a6 effectués à l'intérieur des remplacements sont AllocMem/FreeMem (AllocEntry), Supervisor
(UserState), AskSoftStyle (SetSoftStyle) et MakeVPort (MrgCop).

---

## 2. Qui peut exécuter un `jsr -24(a6)` / `jsr -$24(a6)` avec a6 = 0 ou 1

**Constat 1 : il n'existe aucun `jsr -24(a6)` (décimal, -$18) dans tout le fichier.** La seule occurrence
de $FFE8 (-24) est l'**offset passé à SetFunction** pour GiveUnit (hunk 13 +$56, fichier $12AA), et ce
n'est pas un appel.

**Constat 2 : il existe exactement un `jsr -$24(a6)` (hexadécimal, soit -36, dos `Close`)** : hunk 0 +$1DC
(fichier $284), dans **`_exit` du startup C** (+$1B2). Les débogueurs UAE affichent les déplacements en
hexadécimal (`-$0024`). Il est donc très probable que « -24 » soit ce `-$24`. Contrat de `_exit` :

- Il refait `FindTask(NULL)` (a6 = SysBase rechargé depuis $4) et prend **`pr_ReturnAddr` (+$B0) de la
  tâche courante**. Il pose sp = `pr_ReturnAddr` − 12, puis dépile deux longs posés par le startup : le
  message Workbench (a2) et le tampon d'arguments (a5).
- Si le long +0 du tampon (filehandle « NIL: » du chemin Workbench) est non nul, il charge **a6 depuis la
  variable globale DOSBase (hunk 1 +4)** et appelle `Close` (-$24). Il appelle ensuite CloseLibrary(DOS),
  puis, si a2 ≠ 0, ReplyMsg du message Workbench sous Forbid. Il libère le tampon ($184 octets) et fait un
  `rts` à l'adresse située à `pr_ReturnAddr` − 4.
- **La valeur d'a6 attendue est DOSBase**, qu'aucun registre d'entrée ne fournit. Elle vient d'une
  variable du hunk DATA 1, remplie au démarrage par `OpenLibrary("dos.library", 0)`. Si a6 vaut 0 ou 1,
  cette variable a été **écrasée**, ce qui suppose que le bloc du hunk 1 a été libéré puis réalloué.
- Lancé depuis un CLI, le long +0 du tampon vaut 0 (`MEMF_CLEAR`), donc cet appel **n'est normalement
  jamais exécuté**. Il ne l'est que si `_exit` dépile un faux tampon. C'est le cas lorsque `pr_ReturnAddr`
  est faux, ou lorsque la « tâche courante » n'est pas ce process : un Task simple n'a pas de champ +$B0,
  qui tombe hors de la structure.

**Cause la plus probable : les hunks de SetPatch sont libérés après son exécution.**

- SetPatch suppose que le CLI **ne décharge pas** sa seglist : il met lui-même `cli_Module` (CLI +$3C,
  via `pr_CLI` +$AC) à 0 juste avant `_exit`. Tout son code résident (remplacements, variables
  « ancien vecteur », propriétaire disk.resource, stubs FPU des vecteurs $C0-$FC, DOSBase du hunk 1) vit
  dans ces hunks.
- Lecture de notre `src/dos/shell.s` : la commande est déchargée via la seglist sauvegardée au lancement
  (`XF_SEG`), **sans relire `cli_Module`** (`sh_cli_end` le remet d'ailleurs à 0 lui-même). Les hunks de
  SetPatch sont donc rendus à la mémoire libre alors que ces vecteurs pointent encore dedans :
  - exec FindName, AllocEntry, UserState et Alert ;
  - graphics SetFont, SetSoftStyle et MrgCop ;
  - layers DeleteLayer ;
  - disk.resource GetUnit et GiveUnit.
- Ces blocs sont ensuite réalloués par LoadSeg (`C:Initialize`, puis SysInfo, qui sont eux aussi « alloués
  et recopiés »), par des piles de tâches ou par de petites allocations (sémaphores, messages, IORequest).
  Toute tâche qui appelle un vecteur patché exécute alors ce qui occupe la place, ou l'ancien code de
  SetPatch dont les variables sont corrompues.
- FindName est appelé en interne par OpenLibrary, OpenDevice (audio.device…), OpenResource, FindPort et
  FindTask(nom). Le contrôleur disque passe par GetUnit/GiveUnit à chaque accès trackdisk. **Toutes les
  tâches convergent donc vers les mêmes adresses**, ce qui correspond au symptôme « même plantage partout ».
- Pour départager, **comparer le PC du plantage aux adresses des hunks de SetPatch** relevées pendant son
  LoadSeg (début du bloc + 8 = données du hunk). Si le PC vaut hunk0 + $1DC, ou tombe dans l'un des hunks
  5 à 20, la cause est confirmée. Contre-épreuve : ne pas décharger la seglist lorsque `cli_Module` vaut 0
  au retour ; le plantage doit alors disparaître.

**Causes secondaires possibles, à n'envisager qu'après celle-ci :**

- (a) **Alert** est installé et saute à ancien+$30 / +$88 **au milieu de notre code ROM**. Il lit aussi
  (a5), qui provoque une erreur d'adresse si a5 est impair. Mais le PC tomberait alors en ROM, pas en RAM.
- (b) **DeleteLayer** est installé et saute aux trois cibles déduites de notre code. Le PC tomberait
  également en ROM.
- (c) **UserState** et **AllocEntry** utilisent a6 tel qu'il est reçu. Un appelant interne qui ne passe pas
  a6 = SysBase ferait un appel à a6+déplacement (-30, -198 ou -210), mais jamais -24 ni -$24.

---

## 3. « Exec 68881/68882 exceptions patched » et « DOS Execute call already patched »

### 3.1 Vecteurs d'exception FPU (exec ≤ 35, sans SetFunction ni test d'AttnFlags)

- SetPatch lit le **vecteur CPU 5** ($14, division par zéro). Il prend l'**octet bas** du premier mot du
  gestionnaire comme déplacement de branchement court et calcule la cible, puis avance de 6 octets et
  **exige le mot $E2EF** à cet endroit. Sinon il fait un accès mot à l'adresse impaire $1 : erreur
  d'adresse, plantage volontaire. Le message ayant été affiché, notre ROM passe ce test.
- Il mémorise l'adresse « cible + 6 » (hunk 9 +$38) et **écrit directement 16 longs en $C0..$FC**
  (vecteurs 48 à 63) qui pointent vers 16 stubs de 2 octets du hunk 9. Il n'écrit ni dans les champs
  d'ExecBase, ni dans les `tc_*`.
- Un stub empile un long valant **2 × numéro de vecteur** (96 à 126), puis rejoint « cible + 6 » dans la
  ROM. Le gestionnaire commun de la ROM doit donc accepter à cet endroit un long « 2 × vecteur » au sommet
  de la pile superviseur.
- Sur 68000, ces vecteurs ne sont jamais déclenchés (pas de FPU/MMU, interruptions en autovecteur). Ils
  pointent néanmoins dans les hunks de SetPatch et restent pendants une fois ceux-ci déchargés.

### 3.2 DOS Execute (dos -222)

- Condition : DOSBase `lib_Version` ≤ 35. SetPatch parcourt **sa propre seglist** à partir de
  `cli_Module` (CLI +$3C, via `pr_CLI` +$AC du process courant) pour y trouver le segment dont le long à −4
  (taille du bloc) vaut $22C et dont le premier long de données vaut $89. C'est le RUN BCPL du hunk 2 ; s'il
  est trouvé, il affiche « DOS Execute call ».
- Il lit ensuite **le premier long de l'entrée -222 de la jump table de DOSBase** et le compare à
  **$70E56000**, signature des entrées de la jump table BCPL de la ROM 1.3 (chargement de l'index de
  fonction suivi d'un branchement long vers le dispatcher commun). En cas d'égalité, il fait SetFunction
  vers la glue du hunk 16 et affiche « patched to use resident RUN ». Sinon il affiche « **already
  patched** » et **n'installe rien**. C'est notre cas.
- Si la glue était installée, voici ce qu'elle ferait. Elle réserverait une pile BCPL de $5DC octets
  **sous** le sp courant (sans l'allouer) et chargerait a2/a5/a6 depuis DOSBase+$2A/+$2E/+$32 (`dl_A2`,
  `dl_A5`, `dl_A6`). Elle prendrait a4 = code du RUN résident, a0 = 0 et d0 = 12, puis ferait un appel
  BCPL par a5, avec d1/d2/d3 d'Execute transmis et le résultat rendu en d0 depuis d1. Elle ne s'exécute
  pas chez nous.

---

## 4. Signatures et adresses ROM recherchées

| Correctif | Hypothèse sur la ROM 1.3 |
|---|---|
| Alert | L'ancien vecteur doit être dans `$FC0000..$FFFFFF`. Les points d'entrée internes **ancien + $30** et **ancien + $88** sont fixes. Version exec 33 ou 34 exactement |
| FPU | Le gestionnaire du vecteur 5 commence par un branchement court. À sa cible + 6 doit se trouver le mot **$E2EF**. Le point d'entrée commun est cible + 6 (long « 2 × vecteur » sur la pile) |
| Layers DeleteLayer | Entrée + 2 = branchement (court ou 16 bits). Le corps visé contient **trois mots à octet haut $61** (BSR), qui désignent trois routines internes à convention C |
| DOS Execute | Le premier long de l'entrée -222 vaut **$70E56000** |
| Location zero | Écriture d'un mot 0 à l'adresse fixe **$F80000** (zone ROM, sans effet attendu) sous Supervisor, puis $0 remis à 0 s'il était non nul |
| RAD (non pris) | Exec < 35, `MaxLocMem` (+$3E) > $80000, `ColdCapture` (+$2A) nul. Le stub copié recalcule `ChkSum` (+$52) sur les mots +$22..+$4F. Au reset, il compare le long situé à (a5)+$1E (code ROM appelant ColdCapture) à **$B7FC0004** ; en cas d'égalité, il prend `a3 := MaxLocMem` et reprend en a5+$1E, ce qui saute un bout du code ROM |
| disk.resource, gfx, UserState, FindName, AllocEntry | Aucune signature ni adresse ROM. Seul `lib_Version` ≤ 35 est testé. Jamais `lib_Revision` |

Aucune somme de contrôle ROM, aucune révision et aucun `AttnFlags` ne sont testés.

---

## Exigences pour notre ROM

**DOS / CLI (cause principale) :**

1. Au retour d'une commande, **relire `cli_Module` et ne décharger que cette valeur**. Si elle vaut 0, ne
   rien décharger : la commande s'est rendue résidente. Cela vaut aussi pour tout chemin
   Execute/Run/BCPL qui décharge une seglist. Ne pas effacer `cli_Module` avant de l'avoir relu.
2. `pr_ReturnAddr` (+$B0) doit pointer de sorte que `pr_ReturnAddr` − 4 contienne l'adresse de retour vers
   le CLI : le startup C empile deux longs en dessous et `_exit` repart de `pr_ReturnAddr` − 12. Il doit
   rester valide pendant toute la commande.
3. `pr_CLI` (+$AC) → `cli_Module` (+$3C) doit désigner la seglist de la commande en cours, chaînée en BPTR,
   avec la taille du bloc à −4 de chaque lien (SetPatch y cherche son RUN). DOSBase+$2A/$2E/$32
   (`dl_A2`/`dl_A5`/`dl_A6`) ne servent que si l'entrée -222 porte la signature BCPL. Ce n'est pas notre
   cas, donc rien n'est exigé ici.

**Exec :**

4. SetFunction doit rendre l'ancienne adresse complète. C'est déjà le cas ; tous les remplacements
   rappellent l'ancien par cette valeur.
5. **Alert** : soit placer le vecteur -108 **hors de `$FC0000..$FFFFFF`** (trampoline en RAM), pour que
   SetPatch annule lui-même son correctif (« skipped ») ; soit garantir qu'ancien+$30 et ancien+$88 sont
   des points d'entrée valides. Ils seraient atteints INTENA coupé, avec d7 = alerte, $0 = 'HELP' et
   $100/$104 renseignés ; +$30 si $4 est valide, +$88 sinon ou en cas de récursion. Le trampoline est la
   solution la plus simple et la plus sûre.
6. **UserState** remplacé : Supervisor (-30) doit fonctionner **appelé depuis le mode superviseur**. Il
   doit empiler un cadre 68000 standard (SR.w, PC.l) sur le SSP courant, sans mot supplémentaire, entrer
   en a5, et le RTE du code a5 doit consommer ce cadre directement. Les appelants d'UserState doivent
   passer a6 = SysBase.
7. **AllocEntry** remplacé : a6 = SysBase chez tous les appelants. FreeEntry doit libérer
   16 + 8×`ml_NumEntries` octets pour la liste, taille allouée par SetPatch. Il ne faut pas se fier aux
   champs de nœud de la MemList rendue (mis à zéro).
8. **FindName** remplacé : aucun appelant interne ne doit se fier à a0 ou d1 après FindName (a1 est
   conservé). Les nœuds à `ln_Name` NULL sont sautés.
9. `IDNestCnt` à +$126 avec la convention « −1 = autorisé » et `ThisTask` à +$114 : déjà conformes.
10. Vecteur 5 : la forme actuelle passe déjà le test $E2EF. Si on la modifie, il faut garder un branchement
    court en tête et le mot $E2EF à cible + 6, sinon SetPatch plante volontairement.

**Graphics / layers / disk.resource :**

11. MrgCop, SetSoftStyle et SetFont doivent être appelés avec a6 = GfxBase. `GfxBase->Modes` (+$9E) doit
    refléter le LACE de la vue active, MakeVPort (-216) et AskSoftStyle (-84) doivent être de vrais
    vecteurs, et les offsets RastPort `Font` +$34 / `AlgoStyle` +$38 et ViewPort `Modes` +32 doivent être
    respectés.
12. **DeleteLayer** : avec un SetFunction réel, le remplacement est **installé** et ses trois cibles sont
    déduites de notre code. **Tout DeleteLayer (fermeture de fenêtre ou d'écran) est donc actuellement
    dangereux.** Il faut choisir une parade : soit une forme de notre DeleteLayer qui fournisse, depuis
    l'entrée + 2, un branchement vers un corps dont les trois premiers mots à octet haut $61 sont de vrais
    BSR vers trois routines à convention C (n°1(LayerInfo) → ≠ 0 pour continuer, n°2(Layer), n°3(LayerInfo)) ;
    soit faire échouer la garde de version (layers > 35), si c'est acceptable pour la compatibilité.
13. disk.resource : le même task doit faire GetUnit et GiveUnit, sinon GiveUnit est avalé (cf.
    `setpatch-disk-resource.md` §3). Notre GetUnit doit rendre d0 ≠ 0 en cas d'obtention immédiate.

## Relecture clean-room

Relu : ce document ne contient aucune suite d'instructions transcrite ni de pseudo-code ligne à ligne.
Il contient uniquement des offsets, des contrats de registres, des champs, des constantes de signature
(valeurs testées par SetPatch) et des descriptions de comportement.
