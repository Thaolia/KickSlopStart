# disk-change-v34.md — changement de disquette en 1.3 : file system ROM, événements d'entrée, Workbench

> Piste ANALYSE (« dirty »). Sources : la ROM `assets/kick34005.A500` (file system = segarray dos
> entrée 6, validateur = entrée 7, module `wb 34.1`), et des **sondes boîte noire** sur la vraie ROM
> (FS-UAE, Workbench 1.3.3 `[m2]` + `OctaMED Professional v4.00` + disques fabriqués) avec la sonde
> `tests/dskchg.s` et le harnais `tests/dskchg_run.sh`.
> Mêmes conventions que `handlers-v34.md`, `boot-clock-v34.md` et `workbench-task-v34.md` : **BPTR**
> = adresse/4 ; nœud de la DosList vu en longs `!0..!10` ; pour un **volume** (dn_Type 2) :
> `+$08 dl_Task`, `+$0C dl_Lock`, `+$10..+$1B dl_VolumeDate`, `+$1C dl_LockList`, `+$20 dl_DiskType`,
> `+$28 dl_Name` (BSTR). InfoData (9 longs) : NumSoftErrors, UnitNumber, DiskState, NumBlocks,
> NumBlocksUsed, BytesPerBlock, DiskType, VolumeNode (BPTR), InUse.
>
> **Légende** : **[O]** observé (ROM ou sonde) · **[D]** déduit d'observations convergentes ·
> **[S]** supposé.
>
> Ce document décrit des comportements, des layouts d'ABI et des constantes. **Aucune suite
> d'instructions n'est reproduite ni paraphrasée.**

Specs liées (non répétées ici) : `workbench-task-v34.md` §3.3 (scan des disques), §3.4 (tic de 5 s),
§3.5 (boucle) ; `boot-clock-v34.md` §1 et §4.2 (validateur, recherche/création du nœud volume) ;
`handlers-v34.md` §4.1 (deviceproc et requester « Please insert volume ») et §5 (RAM:).

---

## 0. Résumé exécutable

1. **Détection** : chaque file system (FS) de disquette installe au démarrage une interruption
   **TD_REMOVE (12)** auprès de trackdisk ; elle ne fait que **remettre à 0 un drapeau « disque
   changé »**. Le FS teste ce drapeau à **chaque réveil** de sa boucle (packet reçu ou **tic timer
   d'1 s**, UNIT_VBLANK) ; drapeau à 0 ⇒ il le remet à « vu » puis interroge **TD_CHANGESTATE (14)**.
   Pas d'interrogation de TD_CHANGENUM, pas de TD_ADDCHANGEINT (V36). [O ROM]
2. **Éjection** : le FS répond désormais `DiskType = −1` ; il **détache le volume courant** :
   s'il n'a **aucun lock** ouvert ⇒ le nœud volume est **retiré de la DosList et libéré** ; sinon ses
   locks sont accrochés à `dl_LockList` et **`dl_Task := 0`** (le nœud reste en place). Puis
   événement **IECLASS_DISKREMOVED**. Délai observé : 0,1–0,3 s après l'incrément de
   TD_CHANGENUM. [O]
3. **Insertion** : le FS lance le process **« Validator »** ; celui-ci lit le bloc d'amorce et le
   bloc racine, **retrouve le nœud volume de même nom ET même date de création** (réutilisé :
   `dl_Task := port du FS`, locks réadoptés, `dl_LockList := 0`) ou **en crée un en tête de liste**
   (`dl_VolumeDate` = date de création du bloc racine, `dl_Lock = 0`, `dl_LockList = 0`,
   **`dl_DiskType = 0`**). Bitmap relu (ou disque revalidé) à **chaque** insertion. À la fin du
   validateur : **IECLASS_DISKINSERTED**, y compris pour un disque non DOS. Délais observés : nœud
   +1,0–1,6 s, DISKINSERTED +1,2–2,4 s. [O]
4. **Événements** : IECLASS_DISKREMOVED (15) / IECLASS_DISKINSERTED (16) sont **écrits par le FS
   lui-même** dans input.device (IND_WRITEEVENT) — ni trackdisk, ni input.device ne les génèrent.
   intuition les diffuse en IDCMP **DISKREMOVED ($10000) / DISKINSERTED ($8000) à toutes les
   fenêtres qui les demandent** (fenêtre inactive comprise), horodatés à l'heure courante. [O]
5. **Workbench** : la backdrop reçoit ces IDCMP ⇒ **rescan** de la DosList (aussi au tic de 5 s).
   - nouveau volume monté (`dl_Task ≠ 0`, inconnu) ⇒ icône `Disk.info` de sa racine, sinon
     **icône par défaut** (32×16, 2 plans, ROM) ; libellé = **nom du volume** ; position = celle du
     `.info` si elle ne chevauche aucune icône, sinon **placement automatique** (colonnes de 96 px
     depuis la droite, premier trou depuis le haut, §4.3) ;
   - volume éjecté : l'icône **reste** tant que le nœud existe (locks ouverts, fenêtre ouverte…),
     elle **disparaît** quand le nœud est retiré (disque sans lock) ;
   - disque non DOS dans DF0: ⇒ icône par défaut nommée **`"DF0:" + 4 octets du DiskType`**
     (`DF0:NDOS`, `DF0:BAD`, `DF0:` pour un type 0…), retirée à l'éjection ;
   - **RAM DISK** : icône dès que le volume « RAM DISK » existe avec `dl_Task ≠ 0` (créé par
     L:Ram-Handler au premier accès à RAM:, ici `makedir ram:t` de StartupII), image par défaut
     (pas de `Disk.info` dans RAM:), libellé « RAM DISK », placé automatiquement. [O]

---

## 1. Méthode (pour reproduire)

- Sonde `tests/dskchg.s` lancée par `run >NIL: dskchg <opts>` juste avant `LoadWB` dans la
  startup-sequence d'une copie du disque Workbench (assemblage `-kick1hunks` : LoadSeg 1.3 refuse
  HUNK_RELOC32SHORT, « file is not an object module »). Tous les 100 ms : IDCMP DISKINSERTED/
  DISKREMOVED d'une fenêtre 60×10 BORDERLESS sur l'écran WB (non active), photographie de la
  DosList (nœuds nouveaux/modifiés/disparus), option D = ACTION_DISK_INFO au handler DF0 chaque
  seconde, option T = TD_CHANGENUM/TD_CHANGESTATE (référence temporelle « matérielle »), options L/A
  = lock gardé sur `DF0:c` puis accès 3 s après l'éjection. Journal en mémoire (adresse en `$3F0`)
  relu au débogueur FS-UAE. Horodatage `t` = compteur de la boucle (≈ 0,1 s).
- Changement de disquette : **menu F12 de FS-UAE** piloté au clavier (`dskchg_run.sh`, commande
  `media`). Les raccourcis `keyboard_key_* = action_*_floppy_*` sont ignorés quand ils sont injectés
  par xdotool. Le menu met l'émulation en pause : les délais ci-dessous sont mesurés en temps
  **émulé**, relativement à l'incrément de TD_CHANGENUM vu par la sonde.
- Disques : WB 1.3.3 (volume `Workbench1.3`, date de création [$1616,$4DB,$432]), OctaMED
  (`OctaMEDv4`, date de création [$188F,$406,$8F7], `Disk.info` 112×67 en (264, 2)), ADF entièrement
  nul, `TestVol` (OFS neuf, `Disk.info` d'OctaMED replacé en (560, 10)), `BadRoot` (bloc racine de
  type 7, somme correcte puis incorrecte).

---

## 2. A — Le file system ROM de DF0: (FS) lors d'un changement

### 2.1 Détection (A1) [O ROM, délais O sonde]

- Au démarrage, le FS ouvre **timer.device unité 1 (UNIT_VBLANK)** et **input.device unité 0**,
  prépare une structure **Interrupt** (22 octets, publique) dont `is_Data` pointe un **drapeau
  « disque changé »** et dont le code se borne à écrire 0 dans le long pointé par `is_Data`
  (A1), puis l'installe par **TD_REMOVE (12)** sur son IORequest trackdisk. Le drapeau part à 0
  (« changé ») ⇒ un premier montage est tenté dès le premier passage de boucle.
- La requête timer est réarmée à **tv_secs = 1, tv_micro = 0** (TR_ADDREQUEST) : le FS se réveille
  au moins une fois par seconde même sans packet (`boot-clock-v34.md` §4.3).
- À chaque réveil (avant de traiter le packet reçu) : si le drapeau vaut 0 ⇒ drapeau := −1 ; puis,
  **sauf si le FS est inhibé (ACTION_INHIBIT) ou si une validation est déjà en cours** [O pour
  l'inhibition ; D pour « validation en cours », compteur interne non élucidé en détail],
  **TD_CHANGESTATE (14)** (io_Actual : 0 = disque présent) :
  - **présent** ⇒ démarrage du validateur (§2.5) ;
  - **absent** ⇒ éjection (§2.2.1).
- Conséquence : la latence FS = détection par trackdisk (sa propre scrutation de la ligne
  /CHNG, non mesurée ici) + au plus ~1 s. Mesuré (temps émulé, depuis l'incrément de
  TD_CHANGENUM) : éjection reconnue en **0,1–0,3 s**. [O]

### 2.2 Nœuds volume de la DosList (A2)

#### 2.2.1 Éjection [O ROM + O sonde]

1. `DiskType` du FS := **−1** (réponses DISK_INFO, §2.3).
2. Si l'un de deux états internes du FS est non nul (sémantique [S] : activité/écritures en cours),
   le FS appelle le requester d'erreur de dos (**errorreq, code 3, nœud du volume courant**) et
   **n'abandonne pas** le volume : il reprend sa boucle sans détacher [O pour l'appel et le
   non-détachement ; texte et condition exacte non relevés en sonde].
3. Sinon : vidage des listes de tampons, **CMD_CLEAR (5)** sur trackdisk, puis **détachement du
   volume courant** :
   - **aucun lock ouvert** sur le volume (liste interne des locks vide) ⇒ le nœud est **retiré de la
     DosList** (sous Forbid) et **libéré, ainsi que son nom**. Observé : `X` du nœud `OctaMEDv4` à
     l'éjection (aucune fenêtre ouverte) ;
   - **au moins un lock** ⇒ la liste des locks est **accrochée en fin de `dl_LockList`**, puis
     **`dl_Task := 0`**. Le nœud garde sa place, `dl_Lock`, `dl_VolumeDate`, `dl_DiskType`
     inchangés. Observé : `Workbench1.3` (locks des assigns SYS:, C:…) : `+$08` C00ADC → 0,
     `+$1C` 0 → BPTR de la chaîne de locks (= l'ancien `id_InUse`) ; `OctaMEDv4` avec sa fenêtre
     WB ouverte : idem.
4. Événement **IECLASS_DISKREMOVED** (§3), puis le FS répond aux packets suivants.

#### 2.2.2 Insertion d'un disque DOS [O ROM (validateur, `boot-clock-v34.md` §4.2) + O sonde]

- Le validateur cherche dans la DosList un nœud **dn_Type 2** de **même nom** (comparaison BSTR
  insensible à la casse, nom = BSTR du bloc racine, 1..30 caractères) **et** de **date égale**
  (`dl_VolumeDate` == longs 121..123 du bloc racine = **date de création**). Il **ne regarde pas**
  `dl_Task` (deux disques identiques partageraient le même nœud [D]).
- **Trouvé** (réinsertion) : seul **`dl_Task := port du FS`** est écrit par le validateur. Quand le
  FS reçoit la réponse du validateur, il **réadopte les locks de `dl_LockList`** (chaque `fl_Task`
  := son port, ajout à sa liste interne) puis **`dl_LockList := 0`**. Observé : réinsertion de
  `Workbench1.3` et d'`OctaMEDv4` (fenêtre ouverte) : **même adresse de nœud**, même rang, `+$08` :=
  C00ADC, `+$1C` := 0. [O]
- **Non trouvé** : `makedevnode(nom)` ⇒ nœud neuf **inséré en tête de la DosList**, `dn_Type := 2`,
  `dl_Lock := 0`, `dl_LockList := 0`, `dl_VolumeDate := longs 121..123`, `dl_Task := port du FS`,
  **`dl_DiskType` laissé à 0** et `+$24` à 0. Observé :
  `N 0 adr 2 C00ADC 0 188F 406 8F7 0 0 0 OctaMEDv4` (rang 0). [O]
- `dl_DiskType` des volumes de disquette vaut donc **0** en 1.3 (à l'inverse du nœud « RAM DISK »
  que L:Ram-Handler remplit avec `'DOS\0'`). [O]
- Délais (temps émulé, depuis l'incrément de TD_CHANGENUM) : nœud créé ou réactivé **+1,0 à
  +1,6 s** ; DISKINSERTED **+2,0 à +2,4 s** ; `id_DiskState` passe de 81 à 82 juste après. [O]

#### 2.2.3 Changement direct (disque A remplacé par B)

Il n'y a **pas d'état particulier** : trackdisk voit une éjection puis une insertion (deux
incréments de TD_CHANGENUM) ; le FS enchaîne §2.2.1 puis §2.2.2. Observé `Workbench1.3` → `OctaMEDv4` :
DISKREMOVED, `dl_Task` WB := 0, puis nœud OctaMED neuf et DISKINSERTED. [O]

### 2.3 Réponses de ACTION_DISK_INFO (25) et ACTION_INHIBIT (31) (A3)

**DISK_INFO** (Res1 = −1 toujours) remplit l'InfoData depuis l'état courant du FS [O ROM + O sonde] :

| Champ | Valeur |
|---|---|
| NumSoftErrors | compteur du FS (0 observé) |
| UnitNumber | `fssm_Unit` (0) |
| DiskState | **81 ID_VALIDATING** tant qu'aucun bitmap n'est chargé (validation en cours, disque non DOS, pas de disque après un montage raté) ; sinon **80 ID_WRITE_PROTECTED** si protégé, **82 ID_VALIDATED** sinon |
| NumBlocks / NumBlocksUsed / BytesPerBlock | géométrie (1758 / … / 488 en OFS DD) ; **non remis à zéro** à l'éjection (valeurs du disque précédent) |
| DiskType | **−1** sans disque ; **`'BUSY'` ($42555359)** pendant un INHIBIT actif ; sinon la valeur rendue par le validateur : `'DOS\0'`, **`'NDOS'`** (amorce `DOS\0` mais bloc racine invalide), **`'BAD\0'`** (bloc 0 illisible), ou **le premier long du bloc 0 tel quel** quand ce n'est pas `'DOS\0'` (0 pour un disque nul, `'KICK'` [D] …) |
| VolumeNode | BPTR du nœud volume courant ; **0** sans disque ou disque non DOS |
| InUse | tête (BPTR) de la liste interne des locks ; 0 si aucun |

Séquence observée à l'éjection puis réinsertion : `52,DOS,vol,locks` → éjection `52,−1,0,0` →
détection de l'insertion `51,−1,0,0` → nœud prêt `51,DOS,vol,0` → validateur fini
`52,DOS,vol,…`. Disque nul : `51, 0, 0, 0` ; racine de type 7 : `51,'NDOS',0,0`. [O]

**INHIBIT** (Arg1) [O ROM] : Arg1 ≠ 0 ⇒ le FS se met en état inhibé : abandon d'une validation en
cours, détachement du volume **comme une éjection** (§2.2.1 point 3, sans événement d'entrée) et
`DiskType := 'BUSY'` ; Arg1 = 0 ⇒ fin d'inhibition et **drapeau « disque changé » remis à 0** ⇒
remontage complet (validateur) au réveil suivant. Réponse Res1 = −1. (C'est ce remontage qui donne le
DISKINSERTED vu au boot après `LoadWB delay` / MountMF.) [O sonde pour le DISKINSERTED du boot]

### 2.4 Locks et FileHandles sur un volume absent (A4)

- Le FS **refuse** tout packet portant un lock (ou un FileHandle) dont le volume n'est pas le
  volume courant : **Res1 = 0, Res2 = 218 (ERROR_DEVICE_NOT_MOUNTED)** ; exception : la fermeture
  (ACTION_END, 1007) répond Res1 = −1. [O ROM]
- Côté utilisateur [O sonde] : `Examine()` sur un lock gardé de `Workbench1.3:` après éjection ⇒
  requester système **« Please replace volume / Workbench1.3 / in any drive »**, boutons **Retry /
  Cancel**, fenêtre « System Request » en (0, 0) de l'écran WB. Il **disparaît tout seul à la
  réinsertion** du bon disque (l'appel aboutit alors : `Examine` = −1, IoErr 0), sans clic.
  Les `Lock("Workbench1.3:c")` et `Lock("DF0:")` lancés ensuite aboutissent normalement.
- Un nom de volume **inconnu** ou sans handler donne, lui, « Please insert volume … in any drive »
  (`handlers-v34.md` §4.1). Le partage exact des deux textes entre dos et FS n'est pas tranché ici
  [S : « replace » quand le volume est connu (nœud présent, `dl_Task = 0`), « insert » quand il ne
  l'est pas].
- À la réinsertion, locks et FileHandles redeviennent valides (même nœud, locks réadoptés §2.2.2). [O
  pour les locks, D pour les FileHandles]

### 2.5 Revalidation à l'insertion (A5) [O ROM + O sonde]

- **Chaque** insertion relance le process **Validator** (segarray entrée 7, `boot-clock-v34.md` §1) :
  bloc 0 (type de disque), bloc racine (contrôles : type 2, clé d'en-tête 0, taille de table 72,
  type secondaire 1, nom 1..30 car.), recherche/création du nœud (§2.2.2), puis **relecture du
  bitmap** si le drapeau bitmap du bloc racine est valide, **validation complète** sinon. Le bitmap
  de l'ancien disque est libéré par le FS dès la nouvelle insertion.
- Réponse du validateur au FS en deux temps : (1) réponse au packet de démarrage (DiskType, nœud
  volume) ⇒ le FS mémorise le type, lit **TD_PROTSTATUS (15)** et réadopte les locks ; (2) à la fin,
  un packet du validateur portant le bitmap ⇒ le FS installe le bitmap et **émet DISKINSERTED**.
  Pour un disque non DOS l'étape (2) a aussi lieu (sans bitmap) : DISKINSERTED est émis quand même. [O]
- Bloc racine illisible ou somme fausse : requester du validateur **« Error validating disk » /
  « Key 880 checksum error »**, Retry / Cancel ; tant qu'il est affiché, ni DISKINSERTED ni icône ;
  l'éjection le fait disparaître. [O sonde]

---

## 3. B — Événements d'entrée

- **Émetteur** : le FS de l'unité concernée (un par lecteur DFx), via son IORequest input.device :
  **IND_WRITEEVENT (11)**, `io_Data` = une InputEvent **remise entièrement à 0** puis `ie_Class` :=
  **15 (IECLASS_DISKREMOVED)** ou **16 (IECLASS_DISKINSERTED)** (SubClass, Code, Qualifier,
  EventAddress, TimeStamp = 0), `io_Length` = 26 ; envoi **asynchrone** (SendIO). [O ROM]
- **Moments** : DISKREMOVED juste après le détachement du volume (§2.2.1) ; DISKINSERTED à la fin du
  validateur (§2.5), donc **après** que le nœud volume est en place et `dl_Task` posé — un rescan
  déclenché par l'événement trouve donc le volume monté. [O]
- Ni trackdisk ni input.device n'émettent ces classes eux-mêmes [O : la seule chaîne
  « input.device » des segments dos/FS est celle du FS ; trackdisk n'ouvre que timer.device].
- **intuition** : chaque événement devient un IntuiMessage de classe **DISKREMOVED ($00010000)** /
  **DISKINSERTED ($00008000)** remis à **toutes les fenêtres** dont l'IDCMP contient ce bit, active
  ou non (la fenêtre de la sonde, jamais active, les reçoit). `im_Seconds/im_Micros` = **heure
  système courante** (non nulle) bien que `ie_TimeStamp` soit 0. [O sonde] (Diffusion à des
  fenêtres d'autres écrans : [S], non testée.)
- Le Workbench les demande sur sa backdrop (IDCMP $DC76E inclut $18000 + NEWPREFS,
  `workbench-task-v34.md` §3.2) ; les requesters système (AutoRequest) s'en servent pour se
  refermer seuls à l'insertion (§2.4). [O / D]

---

## 4. C — Workbench (observable)

### 4.1 Déclencheurs et parcours [O ROM, cf. `workbench-task-v34.md` §3.3]

Rescan complet : au démarrage, à **chaque IDCMP DISKINSERTED/DISKREMOVED** de la backdrop, à chaque
**tic de 5 s**, à WBENCHOPEN. Parcours de la DosList sous Forbid ; pour chaque volume :

| Cas | Effet |
|---|---|
| volume **inconnu** du WB | nouvelle entrée « nouveau » ⇒ montage : lock racine (ACTION_LOCATE_OBJECT au `dl_Task`), Info, `GetWBObject("Disk")`, icône (§4.2) ; échec ⇒ entrée retirée |
| connu, `dl_Task ≠ 0` | « actif » (rien à redessiner) |
| connu, `dl_Task = 0` | « retiré » : si l'objet disque n'a **pas de fenêtre ouverte** [D : compteur d'usage de l'objet = 1], le WB **libère son propre lock** racine ; puis il cherche dans la DosList un volume de **même nom et même `dl_VolumeDate`** ; trouvé (y compris **ce même nœud**) ⇒ l'icône **reste** (rattachée à ce nœud) ; sinon l'icône et l'entrée sont supprimées |
| entrée dont le nœud n'est plus dans la DosList | icône et entrée supprimées |

Pour chaque **device** retenu (DF0: etc.) : **ACTION_DISK_INFO** ; `DiskType` ∈ {`'DOS\0'`, −1} ⇒
pas d'icône device (et suppression de celle qui existait) ; sinon icône « device » (§4.5).

### 4.2 Icône d'un nouveau volume [O ROM + O sonde]

- **Image / objet** : `Disk.info` de la racine (via icon.library) ; absent ⇒ **objet disque par
  défaut** : type **WBDISK (1)**, gadget **32×16**, Flags 5 (GADGIMAGE|GADGHBOX), Activation 3,
  GadgetType 1 (BOOLGADGET), image ROM **32×16, 2 plans, PlanePick 3** (disquette blanche à volet
  orange, copiée en CHIP), **CurrentX = CurrentY = NO_ICON_POSITION**, **outil par défaut
  `"SYS:System/DiskCopy"`**.
- **Libellé** : nom du volume (`RAM DISK`, `Workbench1.3`, `OctaMEDv4`, `TestVol`), centré sous
  l'image.
- **Position** : règle du §4.3, appliquée avant l'ajout à la backdrop.

### 4.3 Règle de placement sur la backdrop [O ROM ; mesures O sonde]

Notations : `W` = largeur de la fenêtre backdrop, `H` = sa hauteur − 5, `w`,`h` = largeur/hauteur
du gadget de l'icône, `m` = **tf_YSize de la police du WB + 3** (topaz 8 ⇒ 11, la place du libellé).
Coordonnées de fenêtre (backdrop sans bordure).

1. **Position du `.info` conservée** si elle n'est pas NO_ICON_POSITION **et** si le rectangle
   `[X−2, X+w+2] × [Y−m, Y+h+m]` ne touche **aucune** icône déjà sur la backdrop. Observé :
   OctaMED en (264, 2), loin des autres ⇒ gardé. [O]
2. Sinon (pas de position, ou chevauchement) **recherche d'un trou** :
   - colonnes de **96 px**, de la droite vers la gauche : `x0 = W−96, W−192, …` tant que `x0 ≥ 0` ;
   - dans une colonne, on considère les icônes dont l'étendue horizontale `[X, X+w]` touche
     `[x0, x0+96[`, **triées par Y croissant** ; candidat `y = 5` ; pour chacune : si
     `y + h + m ≤ Y_icône` ⇒ trou trouvé ; sinon `y := max(y, Y_icône + h_icône + m)` ;
   - accepté si `y + h + m ≤ H` : **Y = y**, **X = x0 + (96 − w)/2** (division entière, peut être
     négative si w > 96) ;
   - aucune colonne ⇒ **X = W − 60, Y = 5**.
3. Mesures (écran WB 640 px) : RAM DISK (défaut, w 32) en X ≈ 576 ; `Workbench1.3` (`Disk.info`
   35×16 sans position) en X ≈ 574, sous RAM DISK ; disque non DOS sous Workbench ; `TestVol`
   (112×67, position (560, 10) qui chevauche RAM DISK) **déplacé** sous Workbench1.3 en X ≈ 536.
   Pas vertical mesuré entre deux icônes de hauteur 16 empilées : **≈ 28 lignes** (la règle donne
   h + 11 = 27 ; écart dans l'incertitude de mesure de ±1,5 ligne). Ordre : la colonne se remplit dans
   l'ordre des volumes de la DosList (le plus récent en tête : RAM DISK avant Workbench1.3 au boot). [O]

### 4.4 Éjection [O sonde + O ROM]

| Situation | Icône | Fenêtre du disque |
|---|---|---|
| disque **sans** lock (OctaMED sans fenêtre) | **disparaît** au rescan suivant DISKREMOVED | — |
| disque avec locks (Workbench1.3 : assigns, CLI) | **reste** (même image, même place) | — |
| fenêtre du disque **ouverte** (OctaMED) | **reste** (sélectionnée si elle l'était) | **reste ouverte** avec ses icônes |
| réinsertion du même disque | rien ne change visuellement (même nœud, même entrée) | idem |
| disque non DOS éjecté | icône `DF0:…` **disparaît** | — |

### 4.5 Disque non DOS [O ROM + O sonde]

Icône « device » (type d'objet 7) avec l'**objet disque par défaut** (§4.2), libellé =
**nom du device + `:` + les 4 octets de `id_DiskType`** copiés tels quels, la chaîne s'arrêtant au
premier octet nul : `DF0:NDOS` (racine invalide, observé), `DF0:` (disque nul, type 0, observé),
`DF0:BAD` (`'BAD\0'`), `DF0:BUSY` pendant un INHIBIT [D]. Si le type change, l'icône est recréée
avec le nouveau nom. Rien pour `'DOS\0'` ni pour −1 (lecteur vide). Placement : §4.3 (observé sous
Workbench1.3).

### 4.6 Délais [O sonde, D]

L'icône d'un disque inséré apparaît au rescan déclenché par **DISKINSERTED** (≈ 2 s émulées après
l'insertion pour un disque DOS) ; capture à 3–4 s murales après la fin du menu : l'icône `TestVol`
absente à +3 s, présente à +4 s. À défaut d'événement, le tic de 5 s rattrape. La disparition suit
DISKREMOVED (≈ 0,2 s). Le texte de titre « free memory » est rafraîchi par le même tic.

### 4.7 RAM DISK [O]

- Condition : un nœud **volume** « RAM DISK » avec `dl_Task ≠ 0`. Il n'existe qu'après le **premier
  accès à RAM:** (L:Ram-Handler le crée, `handlers-v34.md` §5) ; sur le WB 1.3.3, `makedir ram:t` de
  StartupII le crée **avant** `LoadWB` ⇒ l'icône est là dès le premier affichage.
- Nœud observé : `+$04 = 2`, `+$08` = port de RAM, `+$0C = 0`, **date = 0**, `+$1C = 0`,
  **`+$20 = 'DOS\0'`**, `+$24` non initialisé, nom `RAM DISK`.
- Image : objet par défaut (RAM: n'a pas de `Disk.info`) ; libellé `RAM DISK` ; position §4.3 :
  en tête de la colonne de droite (X ≈ 576, Y = 5). RAM DISK n'est jamais éjecté.

---

## 5. D — Vecteurs de test (ce qu'une ROM conforme doit montrer)

| # | Entrée | Sortie observable attendue |
|---|---|---|
| V1 | Boot WB 1.3.3 | icônes `RAM DISK` (disque par défaut) puis `Workbench1.3` en dessous, colonne de droite |
| V2 | Éjecter le WB (locks des assigns) | nœud `Workbench1.3` : même adresse, `dl_Task = 0`, `dl_LockList ≠ 0` ; IDCMP DISKREMOVED ; DISK_INFO : type −1, VolumeNode 0, InUse 0 ; **icône Workbench1.3 toujours là** |
| V3 | Puis insérer OctaMED | nœud `OctaMEDv4` **en tête** de la DosList, date [$188F,$406,$8F7], `dl_Lock = dl_LockList = dl_DiskType = 0` ; DISKINSERTED ≈ 2 s après ; DiskState 81 puis 82 ; **icône OctaMED en (264, 2)** |
| V4 | Éjecter OctaMED (sans fenêtre) | nœud **retiré** de la DosList ; DISKREMOVED ; icône OctaMED **disparaît** |
| V5 | Réinsérer le WB | **même nœud** réactivé (`dl_Task := port`, `dl_LockList := 0`) ; DISKINSERTED ; pas de nouvelle icône |
| V6 | Remplacer directement WB par OctaMED | DISKREMOVED puis DISKINSERTED ; mêmes états que V2 + V3 |
| V7 | Ouvrir la fenêtre d'OctaMED puis l'éjecter | nœud gardé (`dl_Task = 0`, `dl_LockList ≠ 0`) ; icône et fenêtre restent ; réinsertion ⇒ même nœud |
| V8 | Disque tout à zéro | DISKINSERTED ; DISK_INFO : type 0, état 81, VolumeNode 0 ; icône défaut **`DF0:`** sous la colonne ; éjection ⇒ disparaît |
| V9 | Amorce `DOS\0`, racine de type 7 (somme juste) | type `'NDOS'` ; icône **`DF0:NDOS`** |
| V10 | Racine à somme fausse | requester « Error validating disk / Key 880 checksum error » (Retry/Cancel) ; pas d'icône ; éjection ⇒ requester fermé |
| V11 | Lock gardé sur `DF0:c`, éjecter, `Examine(lock)` | requester « Please replace volume / Workbench1.3 / in any drive » ; réinsertion ⇒ requester fermé seul, Examine = −1 |
| V12 | `Disk.info` dont la position chevauche RAM DISK | icône déplacée dans la colonne de droite au premier trou (sous Workbench1.3), X = W−96+(96−w)/2 |
| V13 | Fenêtre avec IDCMP DISKINSERTED\|DISKREMOVED, jamais active | reçoit les deux classes ; `im_Seconds` ≠ 0 (heure courante) |
| V14 | ACTION_DISK_INFO pendant INHIBIT(1) | DiskType `'BUSY'` ; après INHIBIT(0) : remontage, DISKINSERTED [O ROM, non sondé] |

---

## 6. Points non tranchés

- Délai de détection **par trackdisk** lui-même (scrutation de /CHNG, moteur arrêté) : non mesuré
  (menu FS-UAE en pause) ; seul le délai FS (≤ ~1 s après l'interruption TD_REMOVE) est établi.
- Sémantique des deux états internes qui empêchent le détachement à l'éjection (§2.2.1 point 2),
  texte du requester correspondant (chemin ROM vu, non sondé) ; partage « replace » / « insert » entre dos et FS (§2.4).
- Ce qui arrive au nœud quand le **dernier lock d'un volume absent** est libéré (ACTION_FREE_LOCK
  sur un lock de `dl_LockList`) : le nœud est-il alors retiré ? [non analysé]
- Pas vertical exact entre icônes empilées : règle h + tf_YSize + 3 (code) contre ≈ 28 lignes mesurées
  (incertitude de mesure) — à recaler sur une capture de notre ROM.
- Diffusion des IDCMP disque aux fenêtres d'écrans autres que le WB ; disques dans DF1:–DF3: (même
  FS, non sondé) ; `'KICK'` et `'BAD\0'` non sondés (déduits du code).

---

## 7. Annexe de traçabilité (repères, piste analyse seulement)

- Repères d'adresses ROM : retirés à la relecture clean-room (non transmis à la piste implémentation ; la piste
  analyse les retrouve dans la ROM au besoin).
- Sondes : `tests/dskchg.s`, `tests/dskchg_run.sh`, `tests/dskchg_dump.py` ; ADF de travail hors dépôt.

---

## Relecture clean-room

- [x] Aucune suite d'instructions transcrite ni paraphrasée : le FS, le validateur et le Workbench
  sont décrits par leurs **effets** (champs de la DosList, InfoData, InputEvent, IDCMP), des
  **commandes de device publiques** (TD_REMOVE 12, CMD_CLEAR 5, TD_CHANGESTATE 14, TD_PROTSTATUS 15,
  IND_WRITEEVENT 11, TR_ADDREQUEST), des **codes d'action dos** (25, 31, 1007), des constantes
  (ID_*, IECLASS_*, IDCMP, types de disque) et des **règles** (recherche nom + date, placement par
  colonnes de 96 px).
- [x] La routine d'interruption TD_REMOVE du FS est décrite par son effet (mettre à 0 le long de
  `is_Data`), pas par son encodage.
- [x] Aucune adresse de routine ROM (annexe §7 expurgée à la relecture).
- [x] Les faits « sonde » proviennent de captures d'écran et d'un journal de la DosList (structures
  publiques), sans désassemblage du code des disques.
