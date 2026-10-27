# trackdisk-write-v34.md — Écriture disquette du trackdisk.device V34.1 (ROM `kick34005.A500`)

> **Piste ANALYSE (« dirty »).** Spec **comportementale** : valeurs, ordres d'opérations, layouts. Aucune suite
> d'instructions transcrite, aucun listing, aucune adresse de routine ROM. Complète
> `trackdisk-official-timing.md` (lecture, seek, moteur), dont la §3.3 n'était qu'un mémo : on n'y revient pas.
>
> **Niveaux de preuve.** **[O]** observé : soit lu sans ambiguïté dans la ROM (constante, test, ordre d'accès
> registre), soit mesuré par la sonde ; la mention **(sonde)** signale ce qui a été **vu tourner** sous FS-UAE
> avec la vraie ROM. **[D]** déduit (conséquence logique ou fait matériel standard appliqué au comportement
> observé). **[S]** supposé.
>
> **Sonde.** `tests/tdwrite.s` + `tests/tdwrite_run.sh` : disquette OFS vierge, la startup-sequence lance la
> sonde, qui enchaîne des requêtes trackdisk unité 0 et écrit `étape E=io_Error A=io_Actual L=1er long` sur le
> série ; le journal disque de l'émulateur (`did 2`) donne, pour chaque armement DSKLEN, la longueur, ADKCON, la
> piste et la position MFM. Vecteurs au §8.

---

## 1. Vue d'ensemble

1. Le driver possède **un seul tampon de piste MFM par unité** (cache d'écriture différée). `CMD_WRITE`
   **n'écrit pas** sur le disque : il lit d'abord la piste entière (si elle n'est pas déjà en cache), code les
   secteurs demandés dans l'image MFM en mémoire et marque le tampon **sale**. L'écriture physique de la piste
   complète n'a lieu qu'au **vidage** (§5.3). [O] (sonde : étapes B/C/D)
2. Une écriture physique écrit **toujours une piste entière** : un seul transfert DMA de **6815 mots
   (13 630 octets MFM)**, sans synchronisation sur l'index, sans WORDSYNC, sans relecture de vérification. [O] (sonde)
3. `TD_FORMAT` construit l'image de la piste à partir de rien (pas de lecture préalable) et l'écrit piste par
   piste avec la même primitive. [O] (sonde : étape L)

---

## 2. Image de piste écrite (encodage)

### 2.1 Disposition globale du transfert

| Zone | Octets MFM | Contenu |
|------|-----------:|---------|
| Gap de tête | **1660** (`$67C`) | mot `$AAAA` répété (830 mots = 830 octets de données `$00`) [O] |
| 11 secteurs | 11 × **1088** (`$440`) = 11 968 | §2.2, sans aucun intervalle entre secteurs [O] |
| Mot de queue | **2** | `$AAA8` (ou `$2AA8` si le dernier bit de données précédent vaut 1) après une lecture-modification ; `$AAAA` (ou `$2AAA`) après un `TD_FORMAT` [O] |
| **Total DMA** | **13 630** = **6815 mots** | DSKLEN = `$C000 | $1A9F` = **`$DA9F`** [O] (sonde : `LEN=1A9F (6815)`) |

- Le DMA démarre **à une position de rotation quelconque** (pas d'attente d'index en `CMD_UPDATE`/`TD_FORMAT`).
  [O] (sonde : positions MFM de départ différentes à chaque écriture)
- Durée : 6815 mots × 32 µs = **218,1 ms** (cellule 2 µs, ADKCON FAST=1). Une révolution à 300 tr/min =
  200 ms = **12 500 octets MFM**. La fin du transfert **recouvre donc le début du gap** qu'il vient d'écrire,
  d'environ 1130 octets à vitesse nominale : il reste ≈ 530 octets de gap effectif entre la fin du secteur de
  queue et le premier secteur. [D]
- Tolérance de vitesse qui en découle : la queue n'atteint pas le premier secteur tant que la révolution dure
  ≥ 11 970 octets MFM, soit une vitesse ≤ ≈ **313 tr/min (+4,4 %)**. Si le lecteur est lent (révolution > 13 630
  octets, < ≈ 275 tr/min), un morceau de l'ancienne piste subsiste entre la fin et le début de l'écriture. [D]
- Le gap reste `$AAAA` en permanence : la zone du tampon qui le contient n'est jamais touchée par une lecture
  (le DMA de lecture écrit plus loin dans le tampon). [O]

### 2.2 Secteur (1088 octets MFM)

Offsets relatifs au début du secteur. « Long codé » = 8 octets MFM : d'abord les bits **impairs** (bits 31, 29…
1 du long de données, chacun précédé de son bit d'horloge), puis les bits **pairs**. Un « bloc codé » de N
octets = N octets de bits impairs puis N octets de bits pairs.

| Offset | Taille | Contenu |
|-------:|-------:|---------|
| `+$000` | 4 | préambule : 2 octets `$00` codés = `$AAAA $AAAA` (premier mot `$2AAA` si le bit précédent vaut 1) [O] |
| `+$004` | 4 | **`$4489 $4489`** écrits tels quels (marques de synchro, horloge manquante volontaire) [O] |
| `+$008` | 8 | long d'info codé : octet 0 = `$FF` (format Amiga 1.0), octet 1 = **piste** (0–159 = cyl×2+face), octet 2 = **secteur** (0–10), octet 3 = **secteurs restant avant le gap** (11 pour le premier secteur après le gap … 1 pour le dernier) [O] |
| `+$010` | 32 | label (16 octets) en bloc codé ; zéros en `TD_FORMAT` [O] |
| `+$030` | 8 | somme d'en-tête, long codé (§2.3) [O] |
| `+$038` | 8 | somme de données, long codé (§2.3) [O] |
| `+$040` | 1024 | 512 octets de données en bloc codé (512 octets impairs puis 512 pairs) [O] |

### 2.3 Sommes

- **Somme d'en-tête** = XOR des **10 longs MFM** de `+$008` à `+$02F` (info + label, bits d'horloge compris),
  puis ET `$55555555` ; le résultat (un long de données) est codé à `+$030`. [O]
- **Somme de données** = XOR des **256 longs MFM** de `+$040` à `+$43F`, puis ET `$55555555`, codée à
  `+$038`. [O]
- Équivalence : le masque élimine les bits d'horloge ; c'est le XOR des longs de données impairs/pairs. [D]
- Ordre de calcul : la somme d'en-tête est calculée **après** le codage de l'info et du label, la somme de
  données **après** le codage des données **et** la correction des horloges de jonction (§2.4). [O]

### 2.4 Bits d'horloge

- MFM standard : bit d'horloge = 1 si et seulement si les deux bits de données voisins valent 0. [O]
- Le bit d'horloge de tête de chaque long ou bloc codé dépend du **dernier bit déjà présent en mémoire** juste
  avant (bit 0 de l'octet précédent) : s'il vaut 1, l'horloge de tête est forcée à 0. [O]
- Après chaque bloc codé par le blitter (label, données), l'horloge de tête de l'octet **suivant** est
  recalculée ; cela couvre la jonction impair→pair, la jonction données→secteur suivant, et l'octet qui suit le
  dernier secteur (mot de queue). [O]
- Les marques `$4489` ne sont jamais recodées ; l'info qui les suit voit un bit précédent à 1 (`$89` finit par
  1) et prend donc une horloge de tête à 0. [O]

### 2.5 Ordre des secteurs dans la piste écrite

- **`TD_FORMAT`** : gap puis secteurs **0, 1, … 10** dans l'ordre, champ « restant avant gap » 11…1,
  labels nuls. [O]
- **Vidage après `CMD_WRITE`** : la lecture préalable **réorganise** le tampon : les secteurs y sont rangés en
  ordre de numéro consécutif (modulo 11) **à partir du premier secteur rencontré par le DMA de lecture**, le
  gap d'origine est supprimé, et le champ « restant avant gap » de chaque en-tête est **réécrit** (11…1) avec
  recalcul de la somme d'en-tête. La piste réécrite commence donc par un secteur arbitraire suivi des 10 autres
  dans l'ordre, puis le nouveau gap est placé devant ce secteur. [O]
- Le label et l'info des secteurs non modifiés sont conservés tels que lus. Un `CMD_WRITE` sans label conserve
  le label lu ; un `ETD_WRITE` avec `iotd_SecLabel` non nul remplace le label (16 octets par secteur, le
  pointeur avance de 16 par secteur) et recalcule la somme d'en-tête. [O]
- Exigence de lecture préalable : 11 secteurs **consécutifs** (sinon `TDERR_BadSecID`), piste et format `$FF`
  conformes, sommes justes. Une piste illisible ou non conforme ne peut **pas** être réécrite par `CMD_WRITE`,
  même si les 11 secteurs sont fournis ; seul `TD_FORMAT` (ou `TD_RAWWRITE`) le peut. [O]

### 2.6 Moteur de codage

- Les données (512 octets) et le label sont codés et recopiés par le **blitter** (via la file `QBlit` de
  graphics.library, attente sur signal), directement depuis `io_Data` / `iotd_SecLabel`. En V34 ces tampons
  **doivent donc être en mémoire CHIP** ; aucune vérification n'est faite (un tampon en FAST donnerait des
  données fausses en silence). [O] (accès blitter) / [D] (conséquence)
- L'info, le préambule, les sommes et les horloges de jonction sont faits par le CPU. [O]

---

## 3. Programmation matérielle d'une écriture physique

Séquence complète d'une écriture de piste (même primitive pour `CMD_UPDATE`, vidage implicite, `TD_FORMAT`,
`TD_RAWWRITE`). Le moteur est déjà allumé et la tête positionnée par l'appelant (§4).

| # | Action | Valeur / détail | Preuve |
|--:|--------|-----------------|--------|
| 1 | Acquérir le canal disque (disk.resource `GetUnit`, attente sur signal si occupé) | à l'acquisition : tous les lecteurs désélectionnés (PRB = ombre OU `$7F`, `/MTR` conservé) ; **si le dernier utilisateur du canal n'était pas cette unité** : ADKCON ← `$0600` (efface WORDSYNC+MSBSYNC) puis ADKCON ← `$9100` (pose **MFMPREC + FAST**) | [O] |
| 2 | Sélection | PRB `$BFD100` ← ombre de l'unité (moteur, `/SEL`, `/SIDE`, `/DIR`) | [O] |
| 3 | Désarmer | DSKLEN ← `$4000` | [O] |
| 4 | Stabilisation | **1 ms** (requête timer.device) | [O] |
| 5 | Pointeur | DSKPT ← adresse du tampon (début du gap) | [O] (sonde) |
| 6 | IRQ | INTREQ ← `$1002` (efface DSKSYN+DSKBLK), INTENA ← `$8002` (autorise DSKBLK) | [O] |
| 7 | Disque présent ? | `/CHNG` (CIAA PRA b2) = 0 → **erreur 29**, rien n'est écrit | [O] |
| 8 | Protection | `/WPRO` (CIAA PRA b3) = 0 → **erreur 28** (`TDERR_WriteProt`), rien n'est écrit | [O] |
| 9 | Garde reset | sous `Disable` : si un reset clavier est annoncé → **erreur 35** (`TDERR_PostReset`) ; sinon drapeau « écriture en cours » posé | [O] |
| 10 | Précompensation | ADKCON ← `$6000` (efface PRECOMP1+PRECOMP0), puis ADKCON ← valeur du §3.1 | [O] (sonde) |
| 11 | Armer | DSKLEN ← `$C000 | mots` **deux fois** (DMAEN + WRITE) ; mots = longueur octets / 2 | [O] (sonde `LEN=1A9F`) |
| 12 | Attendre la fin | sommeil jusqu'à l'interruption DSKBLK (signal + message), **sans délai de garde** | [O] |
| 13 | Couper l'IRQ | INTENA ← `$0002` | [O] |
| 14 | **Délai de vidage** | **2 ms** (requête timer.device) **après** DSKBLK et **avant** de couper le DMA | [O] |
| 15 | Désarmer | DSKLEN ← `$4000` | [O] |
| 16 | Fin de garde reset | drapeau « écriture en cours » effacé ; si un reset a été annoncé pendant l'écriture, le driver signale alors seulement au keyboard.device qu'il a fini (`KBD_RESETHANDLERDONE`) | [O] |
| 17 | Disque toujours là ? | `/CHNG` = 0 → **erreur 29** (disque retiré pendant l'écriture) | [O] |
| 18 | Rendre le canal | disk.resource `GiveUnit` : PRB ← `$FF` (tout désélectionné) | [O] |

Remarques :
- **DSKSYNC n'est jamais écrit** et WORDSYNC n'est jamais posé, en écriture comme en lecture. [O]
  (sonde : `SYNC=FFFF`, ADKCON sans bit 10)
- **DMACON n'est pas touché** par trackdisk ; c'est l'initialisation de disk.resource qui pose `DSKEN`
  (DMACON ← `$8010`) et DSKLEN ← `$4000`, une fois pour toutes. [O]
- ADKCON MFMPREC+FAST : au tout premier `GetUnit` le « dernier utilisateur » vaut une valeur initiale invalide
  (`$FFFFFFFF`), donc le réglage `$9100` est appliqué dès le premier accès disque du système. [O]
- Les bits PRECOMP **restent posés** après l'écriture (pas de remise à zéro au teardown) ; les lectures
  suivantes se font avec ADKCON = `$3100`, sans effet sur la lecture. [O] (sonde)
- Pas de délai spécifique entre la fin d'écriture (étape 18) et un pas de tête ultérieur : le seul délai
  post-DMA est celui de l'étape 14 ; le prochain seek applique ses délais habituels (3 ms/pas, 15 ms de
  settle). [O]
- Le délai de 2 ms (≈ 62 mots MFM) laisse sortir du sérialiseur de Paula les derniers mots déjà lus par le DMA
  quand DSKBLK se déclenche ; le mot de queue `$AAA8`/`$AAAA` sert de remplissage sacrifiable si la porte
  d'écriture se ferme un peu tôt. [D]

### 3.1 Précompensation d'écriture (ADKCON)

La décision porte sur le **numéro de piste** courant de la tête (cyl × 2 + face), comparé à trois seuils
d'unité (bornes **inclusives**) :

| Condition (piste p) | ADKCON écrit | PRECOMP | Retard |
|---------------------|--------------|---------|--------|
| p ≤ seuil1 | `$8000` (rien posé) | 00 | 0 ns |
| seuil1 < p ≤ seuil2 | `$A000` | 01 | 140 ns |
| seuil2 < p ≤ seuil3 | `$C000` | 10 | 280 ns |
| p > seuil3 | `$E000` | 11 | 560 ns |

Valeurs par défaut [O] :

| Lecteur | seuil1 | seuil2 | seuil3 | Effet |
|---------|-------:|-------:|-------:|-------|
| 3,5" Amiga (ID `$00000000`) | **80** | `$FFFF` | `$FFFF` | pistes **0–80** (cyl 0–39 et cyl 40 face 0) : **aucune** ; pistes **81–159** (dès cyl 40 face 1) : **140 ns** |
| 5,25" (ID `$55555555`) | 40 | `$FFFF` | `$FFFF` | pistes 0–40 : aucune ; 41–79 : 140 ns |

Les niveaux 280/560 ns ne sont jamais atteints avec les tables par défaut. Sonde : piste 20 → ADKCON `$1100`,
pistes 100 et 158 → `$3100`. [O] (sonde)

### 3.2 `TD_RAWWRITE` (commande 17)

Même séquence matérielle (§3, y compris protection, garde reset, précompensation, 2 ms), avec : `io_Offset` =
numéro de piste (< 160, sinon `IOERR_BADLENGTH` −4), `io_Length` en octets (< 32 768, sinon −4), `io_Data` en
CHIP, seek effectué avant (une erreur de seek est rendue). Si `io_Flags` bit 4 (`IOTDF_INDEXSYNC`) est posé,
la double écriture DSKLEN est faite **dans l'interruption d'index** (CIA-B FLAG, via ciab.resource) au lieu
d'immédiatement. Le bit 5 (WORDSYNC) n'est pas géré en V34. `io_Actual` n'est pas renseigné. [O]

---

## 4. Mécanique autour de l'écriture

| Point | Comportement V34 | Preuve |
|-------|------------------|--------|
| Moteur avant vidage | allumage si éteint, puis délai **aveugle de 500 ms** ; pas de lecture de `/RDY` | [O] |
| `TD_FORMAT` | après l'allumage, **300 ms supplémentaires** si le moteur était éteint (total 800 ms) ; rien si déjà allumé | [O] |
| Seek avant écriture | délais habituels : 3 ms/pas, **15 ms** de settle après le dernier pas ; aucun délai si la piste est déjà la bonne | [O] |
| Changement de face seul (même cylindre) | `/SIDE` changé, **pas de settle** ; seul le délai de 1 ms de l'étape 4 précède le DMA | [O] |
| Erreur de seek (recalibrage raté) | **ignorée** par le vidage et par `TD_FORMAT` : l'écriture a lieu quand même (seul `TD_RAWWRITE` la rend) | [O] |
| Protection | lue **en direct** sur `/WPRO`, lecteur sélectionné, juste avant d'armer ; erreur 28 au **vidage**, jamais au `CMD_WRITE` lui-même | [O] / [D] |
| Disque absent (drapeau d'unité posé par la surveillance de `/CHNG`) | `CMD_READ`/`CMD_WRITE` → erreur 29 immédiate, sans moteur ; `CMD_UPDATE`, `TD_FORMAT` → moteur + seek puis 29 à l'étape 7 | [O] |
| Retrait pendant l'écriture | 29 à l'étape 17 ; le tampon reste sale | [O] |
| Reset clavier | trackdisk installe un gestionnaire de reset clavier : un reset annoncé **pendant** une écriture est différé jusqu'à sa fin ; une écriture demandée **après** l'annonce échoue en 35 | [O] |
| Fin de DMA | interruption DSKBLK uniquement, attente sans limite ; comme le débit du DMA est cadencé par Paula et non par le disque, la fin arrive toujours (~218 ms) | [O] / [D] |

---

## 5. Commandes

### 5.1 Table de distribution V34 [O]

| N° | Commande | Traitement |
|---:|----------|-----------|
| 0, 1, 6, 7, 8 | `CMD_INVALID`, `CMD_RESET`, `CMD_STOP`, `CMD_START`, `CMD_FLUSH` | `IOERR_NOCMD` (−3) |
| 2 / 3 | `CMD_READ` / `CMD_WRITE` | même moteur (§5.2) |
| 4 | `CMD_UPDATE` | vidage du tampon s'il est sale |
| 5 | `CMD_CLEAR` | **invalide le tampon et JETTE les données sales** sans écrire |
| 9 | `TD_MOTOR` | `io_Length` 0/1 ; `io_Actual` = état précédent (1 = allumé) |
| 10 | `TD_SEEK` | seek seul |
| 11 | `TD_FORMAT` | §5.4 |
| 15 | `TD_PROTSTATUS` | §5.5 |
| 16 / 17 | `TD_RAWREAD` / `TD_RAWWRITE` | §3.2 |
| ≥ 22 | — | −3 |

Commandes immédiates (exécutées dans le contexte appelant) : 1, 6, 7, 8, 13, 14, 18, 19 ; les autres passent par
la tâche d'unité. Bit 15 de `io_Command` = variante ETD (contrôle `iotd_Count`, label). [O]

### 5.2 `CMD_WRITE` / `ETD_WRITE`

1. `io_Actual` ← 0. `io_Offset` et `io_Offset + io_Length` doivent être multiples de 512 et ≤ 901 120
   (3,5"), sinon **−4** (`IOERR_BADLENGTH`) ; `io_Actual` vaut alors 0. [O] (sonde N)
2. Variante ETD : si le compteur de changements de l'unité > `iotd_Count` → **29**. [O]
3. Disque absent → **29**. [O]
4. Pour chaque secteur : si le tampon ne contient pas la piste voulue → **vidage** de l'ancienne piste si sale
   (une erreur de vidage termine la requête avec ce code, le tampon reste sale sur l'ancienne piste), puis
   **lecture** de la nouvelle piste (moteur, seek, lecture brute, décodage, réorganisation §2.5). Échec de
   lecture : jusqu'à **10 nouvelles tentatives**, avec un **recalibrage** forcé avant la 4e et la 8e ; échec
   final → code de lecture (21–27), tampon invalidé. [O]
5. Codage du secteur dans le tampon (label si ETD, sommes), tampon marqué sale, `io_Actual` += 512. [O]
6. Arrêt quand `io_Actual` ≥ `io_Length`. Le test étant fait **après** le premier secteur, **`io_Length` = 0
   écrit quand même un secteur** et rend `io_Actual` = 512. [O] (sonde H/I)
7. En traversant une frontière de piste, la piste précédente est vidée **pendant** la commande ; la dernière
   piste touchée **reste sale** en fin de commande. [O]

Pas de relecture de vérification après une écriture physique. [O] (sonde : aucun DMA de lecture entre un
vidage et la commande suivante)

### 5.3 Vidage du tampon (écriture physique)

Déclencheurs : `CMD_UPDATE` ; tout `CMD_READ`/`CMD_WRITE` vers une **autre** piste ; début de `TD_FORMAT` ;
dernier `CloseDevice` de l'unité (traité par la tâche d'unité, qui ensuite invalide le tampon et éteint le
moteur). [O]

Non-déclencheurs : `TD_MOTOR` 0, changement de disquette, temporisation, `TD_SEEK`, `TD_RAWREAD/RAWWRITE`. [O]

Déroulé : moteur allumé (500 ms si éteint), seek vers la piste du tampon, écriture §3. Succès → tampon
propre (`CMD_UPDATE`). Échec → `io_Error` = code, **tampon toujours sale** (un `CMD_UPDATE` ultérieur
réessaiera). Exceptions : `TD_FORMAT` et le dernier `CloseDevice` marquent le tampon propre **avant** de
vider ; au `CloseDevice` l'erreur est perdue. `io_Actual` n'est pas modifié par `CMD_UPDATE`/`CMD_CLEAR`. [O]
(sonde F/g)

Le changement de disquette n'invalide **pas** le tampon : seule la position de tête est oubliée. [O]

### 5.4 `TD_FORMAT`

1. Moteur (500 ms + 300 ms si éteint). Tampon sale → vidé d'abord (erreur → fin). [O]
2. `io_Offset` et `io_Length` multiples d'une **piste** (5632 octets), fin ≤ 160 pistes, sinon **−4** ;
   `io_Length` = 0 → succès sans rien écrire (le moteur a déjà été allumé et le tampon vidé). [O] (sonde K : −4)
3. Pour chaque piste : seek (erreur ignorée), image construite (gap `$AA`, secteurs 0–10, labels nuls, données
   de `io_Data` en CHIP, 5632 octets par piste), écriture §3. Erreur → fin avec ce code. [O]
4. Succès : tampon invalidé. `io_Actual` **non modifié**. [O] (sonde L : `$DEADBEEF` conservé)
5. Pas de vérification. [O]

### 5.5 `TD_PROTSTATUS`

Disque absent → 29. Sinon : **allume le moteur** (500 ms si éteint), lit `/WPRO`, rend `io_Actual` ≠ 0 si
protégé (`$FF`), 0 sinon, puis **éteint le moteur dans tous les cas**. [O] (sonde M puis O : `TD_MOTOR` rend
« était éteint »)

### 5.6 Codes d'erreur rencontrés à l'écriture

| Code | Nom | Origine |
|-----:|-----|---------|
| −3 | `IOERR_NOCMD` | commande non gérée |
| −4 | `IOERR_BADLENGTH` | offset/longueur non alignés ou hors disque |
| 21 | `TDERR_NoSecHdr` | lecture préalable : aucune marque trouvée |
| 22 | `TDERR_BadSecPreamble` | préambule ou `$4489 $4489` absent à l'emplacement attendu |
| 23 | `TDERR_BadSecID` | `$FF`, piste ou numéro consécutif faux |
| 24 | `TDERR_BadHdrSum` | somme d'en-tête |
| 25 | `TDERR_BadSecSum` | somme de données |
| 26 | `TDERR_TooFewSecs` | pas de secteur après le gap |
| 27 | `TDERR_BadSecHdr` | premier en-tête trouvé invalide |
| 28 | `TDERR_WriteProt` | `/WPRO` au moment de l'écriture physique |
| 29 | `TDERR_DiskChanged` | disque absent, retiré pendant l'écriture, ou `iotd_Count` dépassé |
| 35 | `TDERR_PostReset` | écriture demandée après l'annonce d'un reset clavier |

(Les codes 21–27 attribués aux cas exacts de décodage sont [O] ; leur description reprend les noms publics.)

---

## 6. Ce qui distingue un vrai lecteur d'un émulateur

1. **Image ADF** : FS-UAE redécode la piste écrite en secteurs et ne garde que les données ; le gap, le
   recouvrement de fin, le mot de queue, les horloges et la précompensation n'y laissent aucune trace. Une
   piste mal formée peut sembler « bien écrite ». Sur disquette réelle, chaque bit compte. [O] (sonde) / [D]
2. **Longueur de piste** : l'émulateur modélise une révolution de 101 344 cellules (12 668 octets) : la fin de
   l'écriture recouvre ≈ 962 octets du gap (sonde : départ à la position 12 307, fin à 20 000 modulo la piste).
   Un vrai lecteur à 300 tr/min recouvre ≈ 1130 octets, et sa vitesse varie de quelques %. Une image de piste
   plus courte que celle du §2.1 (gap trop court) peut passer sous émulateur et écraser le premier secteur sur
   un lecteur rapide. [O] (sonde) / [D]
3. **Précompensation** sans effet en émulation ; sur une vraie disquette, l'absence de 140 ns sur les pistes
   intérieures (> 80) dégrade la fiabilité de relecture (surtout sur d'autres lecteurs). [D]
4. **Settle après seek (15 ms) et spin-up (500 ms)** : sans effet en émulation ; sur vrai matériel, écrire
   pendant que la tête se stabilise ou que la vitesse n'est pas atteinte produit une piste décentrée ou trop
   longue/courte, illisible plus tard (pire qu'une lecture ratée, car l'ancienne donnée est perdue). [D]
5. **Coupure du DMA** : l'émulateur se moque de l'instant où DSKLEN repasse à `$4000` ; sur Paula réelle,
   couper aussitôt après DSKBLK peut tronquer la fin. Le driver attend 2 ms et place un mot de queue
   sacrifiable. [D]
6. **`/WPRO` et `/CHNG`** ne sont valides que lecteur **sélectionné** ; le driver sélectionne, attend 1 ms,
   puis teste. Un émulateur peut rendre la bonne valeur même sans sélection. [D]
   (La sonde n'a pas réussi à présenter une disquette protégée sous FS-UAE : ni `uae_floppy0wp`, ni
   `floppy_write_protect`, ni un ADF en lecture seule n'ont changé `/WPRO` vu par la ROM.)
7. **Lecture préalable** : un vrai disque marginal fait échouer `CMD_WRITE` (après 11 lectures et 2
   recalibrages, plusieurs secondes) même si l'appelant réécrit toute la piste ; un émulateur lit toujours
   parfaitement. [D]
8. **Durées** : sur vrai matériel une écriture de piste dure 218 ms + 2 ms, la lecture préalable ~236 ms par
   essai ; en émulation non cycle-exact ces durées peuvent être raccourcies. Aucun délai de garde ne doit être
   plus court. [D]
9. **Interruption d'index** (`TD_RAWWRITE` + `IOTDF_INDEXSYNC`) : dépend du signal d'index réel (CIA-B FLAG). [D]

---

## 7. Mise en relation avec la spec de lecture

- §3.3 de `trackdisk-official-timing.md` précisé : le « délai de 2000 µs autour du flush » est **après**
  DSKBLK et **avant** DSKLEN ← `$4000` ; les seuils sont des **numéros de piste** (cyl×2+face), seuil 80
  inclusif.
- Le teardown ADKCON `$0600`/`$9100` de la spec de lecture n'a lieu qu'à l'acquisition du canal quand un autre
  utilisateur l'avait pris entre-temps, pas à chaque transfert. [O]
- Lecture brute : 7358 mots (14 716 octets), ADKCON `$1100` ou `$3100`. [O] (sonde)

---

## 8. Vecteurs de test (sonde, vraie ROM, FS-UAE)

Disquette OFS vierge, unité 0, tampon CHIP. `io_Actual` préchargé à `$DEADBEEF`.

| Étape | Requête | io_Error | io_Actual | 1er long du tampon après |
|------|---------|---------:|----------:|------------------|
| A | READ bloc 1100 (piste 100) | 0 | 512 | `00000000` |
| B | WRITE bloc 1100, motif `11111111` | 0 | 512 | — |
| C | CLEAR | 0 | inchangé | — |
| D | READ bloc 1100 | 0 | 512 | `00000000` (B jeté) |
| E/F | WRITE `22222222` puis UPDATE | 0 / 0 | 512 / inchangé | — |
| g/G | CLEAR puis READ | 0 / 0 | — / 512 | `22222222` (écrit) |
| H/h/i/I | WRITE longueur 0 `33333333`, UPDATE, CLEAR, READ | 0 | 512 (H) | `33333333` (un secteur écrit) |
| J/j | WRITE bloc 220 (piste 20) + UPDATE | 0 | 512 | journal : ADKCON `$1100` |
| K | FORMAT longueur 512 | −4 | inchangé | — |
| L/l | FORMAT piste 158, motif `55555555`, puis READ | 0 / 0 | inchangé / 512 | `55555555` |
| M | PROTSTATUS | 0 | 0 | — |
| N | WRITE offset 100 | −4 | 0 | — |
| O | MOTOR 0 | 0 | 0 (PROTSTATUS l'avait éteint) | — |

Journal disque : toutes les écritures `LEN=1A9F (6815)`, DSKPT = début du tampon de piste (gap) ; lectures
`LEN=1CBE (7358)`, DSKPT = tampon + 1664 octets.

---

## 9. Points non tranchés

1. **Protection en écriture non vue tourner** : les codes 28 (`CMD_UPDATE`, vidage, `TD_FORMAT`) et le
   `io_Actual` ≠ 0 de `TD_PROTSTATUS` reposent sur la lecture de la ROM, FS-UAE n'ayant pas pu présenter un
   disque protégé (§6.6). À confirmer sur WinUAE ou sur le vrai A500.
2. **Instant exact de DSKBLK en écriture** sur Paula réelle (dernier mot lu par le DMA ou dernier bit
   sorti) : le rôle du délai de 2 ms et du mot de queue est [D].
3. **Vitesse réelle des lecteurs** : les marges de +4,4 % / −8,3 % du §2.1 sont calculées pour une cellule de 2 µs
   exacte ; dispersion des vrais lecteurs non mesurée.
4. **Tampon après un `TD_FORMAT` en échec** : le tampon contient alors l'image de format mais garde le numéro
   de piste qu'il avait avant (il n'est invalidé qu'en cas de succès) ; une lecture de cette ancienne piste
   pourrait rendre des données fausses. [D], non sondé ; défaut probable de la V34, à ne pas reproduire.
5. **Tampon sale et changement de disquette** : comme le tampon n'est pas invalidé, un vidage après un
   changement écrirait les données de l'ancienne disquette sur la nouvelle, sauf `CMD_CLEAR` du système de
   fichiers. Le comportement du handler DOS 1.3 sur ce point n'est pas établi ici.
6. **Taille du tampon de piste** et origine de son allocation (disk.resource / mémoire CHIP) non relevées en
   détail ; seule la disposition (gap à l'offset 4 du tampon, DMA de lecture à +1668 du début du tampon) est
   établie.
