# trackdisk-official-timing.md — Comportement & timing de la lecture de piste (trackdisk.device V34.1, ROM `kick34005.A500`)

> **Piste ANALYSE (« dirty »).** Faits dérivés UNIQUEMENT de la lecture de la ROM propriétaire
> (radare2, 68000 big-endian, base `$FC0000`). Ce document décrit le **COMPORTEMENT** (séquence
> d'opérations, ordre des accès registres, **durées**) et le **layout d'ABI** (offsets de champs
> d'unité, valeurs de constantes). **Aucune suite d'instructions n'est reproduite** : pas de
> désassemblage, pas d'extrait de code 68k. Les adresses de routines ne servent que d'ancres de
> renvoi ; les adresses/valeurs de registres matériels et les constantes de timing sont des **faits
> matériels/ABI**, pas du code.
>
> Cible : trackdisk.device, ROMTag `$FE9564`, `rt_IdString` = `trackdisk 34.1 (18 Aug 1987)`,
> `rt_Init` = `$FE97BE`, plage `$FE9564`–`$FEB05C`. La ROM globale est **34.5 / Kickstart 1.3**.
>
> Matériel (rappel) : CIAB PRB `$BFD100` = `/MTR`(b7) `/SEL0`(b3) `/SIDE`(b2) `/DIR`(b1) `/STEP`(b0),
> tous **actifs-bas**. CIAA PRA `$BFE001` = `/RDY`(b5) `/TRACK0`(b4) `/WPRO`(b3) `/CHNG`(b2), tous
> actifs-bas. Paula `$DFF0xx` : DSKPT `$20`, DSKLEN `$24`, DSKSYNC `$7E`, ADKCON `$9E`, INTENA `$9A`,
> INTREQ `$9C`, DMACON `$96`.

---

## 0. Vue d'ensemble & carte des routines (ancres)

Le driver tient un **shadow RAM** de l'octet de sortie CIAB PRB dans la structure d'unité à
**offset `+0x41`** : toute manipulation des lignes lecteur se fait d'abord sur le shadow, puis le
shadow est écrit en `$BFD100`. Ce shadow est la source de vérité ; `$BFD100` étant *write-only*, le
driver ne relit jamais le port de contrôle.

| Ancre | Rôle comportemental |
|-------|---------------------|
| `$FEA0E2` | **MOTEUR** (on/off + délai de spin-up) |
| `$FE9FE0` | **RECALIBRATE** (step vers `/TRACK0`, vérif, erreur 30 sinon) |
| `$FEA05A` | **SEEK** (vers cylindre cible : calcule delta, pose `/DIR`+`/SIDE`, N pas) |
| `$FEA13E` | **UN PAS** (pulse `/STEP` + délai inter-pas) |
| `$FEA1A4` | **LECTURE DMA** d'un bloc brut (pas de WORDSYNC, pas de precomp) |
| `$FEA234` | **ÉCRITURE DMA** (teste `/WPRO`, applique write-precompensation ADKCON) |
| `$FEA170` | **DÉLAI temporisé** : d0 = µs ; `≥ 300 µs` → requête timer.device, `< 300 µs` → busy-loop |
| `$FEA38A` | **ATTENTE FIN DMA** : `Wait()` sur signal + `GetMsg()` (interruption, PAS de polling) |
| `$FEAA5C` | **GetUnit** disk.resource (acquisition exclusive du canal DMA disque) |
| `$FEAAC2` | **GiveUnit** disk.resource (libération du canal DMA disque) |
| `$FEAA92` | **Teardown DMA** : déselection lecteurs + remise ADKCON au mode lecture par défaut |
| table `$FE9F38`/`$FE9F4E` | **Défauts par type de lecteur** (step, settle, precomp, nb pistes) |

**Dépendances externes** (ouvertes à l'init) : `timer.device` (unité MICROHZ, pour TOUS les délais
temporisés), `disk.resource` (arbitrage du canal DMA disque partagé entre df0..df3), `ciab.resource`,
`keyboard.device`. Les délais ne sont JAMAIS des busy-loops CPU au-delà de 300 µs : ils passent par
une requête `timer.device` synchrone (DoIO).

**Point d'ABI majeur (DMACON) :** le driver **n'écrit JAMAIS DMACON `$DFF096`** (vérifié : zéro
écriture `$96` sur toute la plage `$FE9564`–`$FEB05C`). L'activation maître du DMA disque
(DMACON `DSKEN` b4 + `DMAEN` b9) est donc posée **globalement et une seule fois** ailleurs dans le
système ; trackdisk se contente d'**armer chaque transfert via la double-écriture DSKLEN** (cf. §3).

---

## 1. MOTEUR & READY

### 1.1 Allumage moteur (routine `$FEA0E2`)

Le moteur est contrôlé par `/MTR` (b7) dans le shadow `+0x41`, mais la **latch moteur du lecteur
se fait sur le front de `/SEL`** (le lecteur Amiga mémorise l'état de `/MTR` au moment où `/SEL`
passe actif). La routine :

1. Compare l'état `/MTR` demandé à l'état courant (shadow). **Si inchangé → retour immédiat, aucun
   délai.** (Conséquence : le DOS laissant le moteur allumé entre deux accès, le délai de spin-up
   n'est payé **qu'une fois**, pas à chaque lecture.)
2. Met à jour `/MTR` dans le shadow.
3. Acquiert le canal disque (`GetUnit`, `$FEAA5C`).
4. Produit la **séquence de deux écritures `$BFD100`** nécessaire pour générer le front `/SEL` qui
   *latch* le nouvel état moteur dans le lecteur (d'abord l'état avec `/SEL` relâché, puis l'état
   shadow avec `/SEL` asserté).
5. **Si on vient d'ALLUMER le moteur** : délai **FIXE de 500 ms** (`500000 µs` = `$7A120`, via la
   routine de délai temporisé `$FEA170` → requête timer.device). Si on éteint : pas de délai.
6. Retourne l'ancien état moteur (pour que l'appelant puisse le restaurer).

### 1.2 Attente « ready » — le fait central

**Le trackdisk officiel n'attend PAS `/RDY`. Il n'interroge JAMAIS `/RDY` (CIAA PRA b5).**

- Recherche exhaustive sur toute la ROM : le **seul** test de `/RDY` (b5 de `$BFE001`) se trouve à
  `$FC49A8`, **hors** de trackdisk (zone disk.resource / exec). À l'intérieur de trackdisk.device,
  il n'y a **aucun** accès au bit 5.
- Le « ready » après allumage est donc un **délai aveugle, temporisé, de 500 ms fixe**, indépendant
  de l'état réel du lecteur. C'est le timer.device (unité MICROHZ) qui compte, pas un busy-loop.
- `/RDY` sur un lecteur Amiga ne signifie pas simplement « moteur à vitesse » : la ligne sert aussi
  à horloger l'ID 32 bits du lecteur (quand on toggle `/SEL` moteur éteint). Cette logique d'ID est
  dans disk.resource, pas dans le chemin de spin-up de trackdisk — d'où l'absence de poll `/RDY` ici.

### 1.3 « Timeout » / présence disque

Il n'y a pas de timeout sur un `/RDY` (puisque `/RDY` n'est pas lu). Les conditions d'erreur liées
au lecteur viennent d'ailleurs :

- **Présence disque** : testée via `/CHNG` (CIAA PRA **b2**) au début de chaque transfert DMA
  (§3). Disque absent/changé → code **29** (`TDERR_DiskChanged`, `$1D`).
- **Positionnement** : après recalibrate, si `/TRACK0` (b4) n'est pas atteint → code **30**
  (`TDERR_SeekError`, `$1E`).

---

## 2. SEEK & STEP

### 2.1 Séquence d'un pas unique (routine `$FEA13E`)

Déroulé **exact** d'un pas, dans l'ordre :

1. Lire le shadow `+0x41` (il contient déjà la direction `/DIR` voulue, posée par l'appelant — cf.
   §2.3).
2. **Asserter `/STEP` bas** : une écriture `$BFD100` avec b0 = 0 (et b1/`DIR` + b2/`SIDE` dans leur
   état courant, écrits dans la **même** écriture atomique).
3. **Maintien du pulse** : exactement **deux `NOP`** (≈ 8 cycles CPU, soit ≈ **1,1 µs** @ 7,09 MHz),
   entre l'assertion et la relâche.
4. **Relâcher `/STEP` haut** : une seconde écriture `$BFD100` restaurant b0 = 1.
5. **Libérer le canal disque** (`GiveUnit`, `$FEAAC2`) pendant le temps de settle qui suit.
6. **Délai inter-pas** = valeur d'unité `+0x2C` = **3000 µs = 3 ms** (lecteur 3,5" par défaut), via
   requête timer.device (`$FEA170`).
7. **Ré-acquérir le canal** (`GetUnit`) et réécrire le shadow en `$BFD100` (état stable, `/STEP`
   haut, `/DIR` maintenu).

**Largeur du pulse `/STEP` bas** = durée de la 2e écriture CIA + les 2 `NOP` intercalés. Les deux
`NOP` sont **délibérés** : ils élargissent le pulse au-delà de ce que donneraient deux écritures CIA
dos-à-dos. (La même idiome « écrire CIA → 2 NOP → accès CIA » apparaît aussi là où le driver écrit
`$BFD100` puis relit `$BFE001` : c'est le temps de recouvrement/propagation du 8520.)

**Setup de direction :** `/DIR` et `/STEP`-bas sont posés dans la **même** écriture CIA atomique ⇒
`/DIR` est valide exactement au front descendant de `/STEP` (le lecteur échantillonne `/DIR` sur ce
front). Il n'y a pas de délai de setup `/DIR` *séparé*, mais `/DIR` est **stable et maintenu** sur
toute la durée du seek (réécrit après chaque pas), donc jamais modifié pendant qu'un pulse est actif.

### 2.2 Détection `/TRACK0` et recalibrate (routine `$FE9FE0`)

- `/TRACK0` = CIAA PRA **b4** (actif-bas : 0 = tête sur piste 0).
- Recalibrate = poser `/DIR` « vers l'extérieur », puis **stepper** (via `$FEA13E`, donc avec les
  3 ms inter-pas) jusqu'à ce que `/TRACK0` soit asserté, borné par un compteur dérivé du **nombre
  total de pistes** (unité `+0x36` = **160** pistes = 80 cyl × 2 faces pour le lecteur par défaut).
- Après recalibrate/seek réussi : **délai de settle = valeur d'unité `+0x30` = 15000 µs = 15 ms**
  (via timer.device) **avant de rendre la main** / lire.
- Échec (`/TRACK0` non atteint) → `TDERR_SeekError` = 30.

### 2.3 Seek vers un cylindre (routine `$FEA05A`)

1. Position courante conservée dans l'unité `+0x4C`, encodée `(cyl × 2) | face`.
2. Acquiert le canal disque (`GetUnit`).
3. Pose `/SIDE` (b2) selon la face cible — écriture `$BFD100` immédiate.
4. Calcule le **delta** de cylindres ; choisit `/DIR` (b1) selon le signe (pose `/DIR` dans le
   shadow, **sans** écriture `$BFD100` séparée — il sera appliqué par le 1er pas).
5. Émet **|delta| pas** en bouclant sur la routine de pas `$FEA13E` (donc **3 ms entre chaque pas**).
6. Après le dernier pas : **settle 15 ms** (unité `+0x30`), puis libère le canal.

### 2.4 Résumé des durées de pas/seek

| Grandeur | Valeur (lecteur 3,5" défaut) | Source |
|----------|------------------------------|--------|
| Largeur pulse `/STEP` bas | ≈ 1,1 µs de `NOP` + 1 accès CIA (≈ qq µs) | 2 NOP codés dans `$FEA13E` |
| Setup `/DIR` avant le front `/STEP` | 0 (même écriture CIA) ; `/DIR` maintenu tout le seek | `$FEA13E` |
| **Délai inter-pas (step rate)** | **3 ms** (`3000 µs`, unité `+0x2C`) | table `$FE9F38` |
| **Settle post-seek / post-recal** | **15 ms** (`15000 µs`, unité `+0x30`) | table `$FE9F38` |
| Nombre de pistes (borne recal) | 160 | table `$FE9F38` |
| Type de lecteur alternatif (table `$FE9F4E`) | step **6 ms**, settle 15 ms, 80 pistes | table `$FE9F4E` |

---

## 3. LECTURE DMA (WORDSYNC — le point le plus important)

### 3.1 Fait central : la lecture officielle N'UTILISE PAS WORDSYNC

Vérifié exhaustivement sur toute la plage `$FE9564`–`$FEB05C` :

- **Zéro écriture du registre DSKSYNC `$DFF07E`.** Le driver ne charge jamais `$4489` (ni rien)
  dans DSKSYNC. (La valeur `$44894489` qui apparaît dans la ROM est écrite dans un **buffer** de
  comparaison, pas dans le registre — elle sert au décodage MFM **logiciel**.)
- **WORDSYNC jamais activé.** Les seules écritures ADKCON `$DFF09E` de tout le module sont :
  (a) la **write-precompensation** dans le chemin d'écriture (`$FEA2DA` efface les bits precomp,
  `$FEA306` pose le niveau selon le cylindre), et (b) le **teardown** (`$FEAAB0` = `$0600` =
  *clear* WORDSYNC+MSBSYNC ; `$FEAAB6` = `$9100` = *set* MFMPREC+FAST). Le mode « par défaut » posé
  par trackdisk a donc **WORDSYNC explicitement à 0**.

**Conséquence comportementale :** le trackdisk officiel lit une **piste brute entière, non
synchronisée matériellement**, sur **plus d'une révolution** (buffer pré-rempli de `$AAAAAAAA` =
motif de gap MFM ; longueur DMA dimensionnée pour garantir la capture de tous les secteurs quelle
que soit la position rotationnelle), puis **retrouve les marques de synchro `$4489` en logiciel**
lors du décodage MFM. Il ne dépend donc PAS de l'alignement matériel WORDSYNC.

### 3.2 Séquence exacte d'armement DMA (lecture, routine `$FEA1A4`)

Ordre des opérations (une lecture de bloc brut) :

1. **Acquérir** le canal disque : `GetUnit` disk.resource (`$FEAA5C`) — bloquant tant qu'un autre
   lecteur détient le DMA.
2. Réécrire le shadow `+0x41` en `$BFD100` (rafraîchir la sélection lecteur).
3. **DSKLEN `$DFF024` ← `$4000`** : garantit DMA disque **désarmé** (bit15 `DMAEN` = 0) avant
   reconfiguration.
4. **Délai de 1000 µs (1 ms)** (via `$FEA170`) — temps de stabilisation après select, **avant**
   d'armer le DMA.
5. **DSKPT `$DFF020` ← adresse buffer** (écriture long, pointeur DMA).
6. **INTREQ `$DFF09C` ← `$1002`** : efface les interruptions disque **pendantes** (bit12 `DSKSYN`
   + bit1 `DSKBLK`).
7. **INTENA `$DFF09A` ← `$8002`** : `SET | DSKBLK`(b1) → **active l'interruption fin-de-bloc disque**.
8. **Test présence disque** : `/CHNG` (`$BFE001` b2). Absent → code 29 (`TDERR_DiskChanged`), sortie.
9. **Armer le DMA = DOUBLE-ÉCRITURE DSKLEN `$DFF024`** : la **même** valeur `$8000 | (longueur_octets / 2)`
   est écrite **deux fois de suite**. `$8000` = bit15 `DMAEN` ; la valeur basse est le **compte de
   MOTS** (DSKLEN compte des words, d'où le `/2`). La double-écriture est le mécanisme matériel
   obligatoire de déclenchement (sécurité anti-DMA parasite du hardware disque).
10. **Attendre la fin** : routine `$FEA38A` = `Wait()` sur le **signal de la tâche** (masque `$400`)
    puis `GetMsg()` sur le port d'unité `+0xAE`. **C'est de l'interruption, pas du polling** : le
    serveur d'interruption `DSKBLK` signale la tâche, qui dort dans `Wait()` entre-temps.
11. **Teardown** : INTENA ← `$0002` (clear DSKBLK), **DSKLEN ← `$4000`** (DMA désarmé).
12. **Re-tester `/CHNG`** (le disque a pu être retiré pendant le transfert) → code 29 sinon succès.
13. Libérer le canal (`GiveUnit`) et remettre ADKCON au mode par défaut (`$FEAA92`, WORDSYNC off).

### 3.3 Écriture (routine `$FEA234`) — pour mémoire

Même squelette, plus : test `/WPRO` (`$BFE001` b3) avant d'écrire ; **write-precompensation** posée
dans ADKCON selon le cylindre courant (seuils d'unité `+0x26`/`+0x28`/`+0x2A`, défaut 1er seuil à
cyl 40, c.-à-d. `$4C` = cyl×2 = 80) ; DSKLEN armé avec le bit14 (`WRITE`) en plus de `DMAEN` ; et un
**délai supplémentaire de 2000 µs (2 ms)** (`$7D0`) autour du flush DMA d'écriture.

### 3.4 Résumé séquence/timing DMA lecture

| Étape | Registre / action | Valeur | Note |
|-------|-------------------|--------|------|
| Désarmer | DSKLEN `$24` | `$4000` | DMAEN=0 |
| **Attendre** | timer.device | **1 ms** | settle avant armement |
| Pointeur | DSKPT `$20` | buffer | long |
| Clear IRQ | INTREQ `$9C` | `$1002` | DSKSYN+DSKBLK pendantes |
| Enable IRQ | INTENA `$9A` | `$8002` | SET \| DSKBLK |
| Présence | `/CHNG` `$BFE001` b2 | — | absent → err 29 |
| **Armer** | DSKLEN `$24` | `$8000 \| mots` **×2** | **double-écriture obligatoire** |
| Fin | Wait(signal `$400`)+GetMsg | — | **interruption, pas de poll INTREQR** |
| Désarmer | INTENA `$9A` / DSKLEN `$24` | `$0002` / `$4000` | teardown |
| ADKCON | `$9E` | `$0600` puis `$9100` | **WORDSYNC remis à 0**, MFMPREC+FAST |
| DMACON `$96` | — | **jamais écrit** | activation maître DMA disque = globale, ailleurs |

---

## 4. Constantes de timing (récapitulatif)

| Paramètre | Valeur officielle | Mécanisme | Offset/source |
|-----------|-------------------|-----------|---------------|
| Spin-up moteur (on) | **500 ms** fixe | timer.device, aveugle (pas de `/RDY`) | `$7A120` @ `$FEA128` |
| Attente `/RDY` | **aucune** | — | `/RDY` jamais lu dans trackdisk |
| Largeur pulse `/STEP` | ≈ 2 NOP (~1,1 µs) + accès CIA | codé en dur | `$FEA13E` |
| Step rate (inter-pas) | **3 ms** (3000 µs) | timer.device | unité `+0x2C`, table `$FE9F38` |
| Settle post-seek/recal | **15 ms** (15000 µs) | timer.device | unité `+0x30`, table `$FE9F38` |
| Settle avant armement DMA | **1 ms** (1000 µs) | timer.device | `$3E8` @ `$FEA1C6` |
| Seuil busy-loop vs timer | 300 µs | `$FEA170` | `< 300 µs` → boucle CPU |
| Fin DMA | interruption `DSKBLK` + `Wait` | timer.device / exec | `$FEA38A` |
| Nb pistes | 160 (80 cyl × 2) | — | unité `+0x36` |

---

## 5. Différences probables qui cassent sur émulateur timing-exact (WinUAE)

Comparaison à notre implémentation naïve connue (pulse `/STEP` ≈ 1,4 µs = deux écritures CIA
dos-à-dos ; attente READY = busy-loop poll `/RDY` ≈ 0,5 s sans délai moteur fixe ; pas de délai de
setup direction ; lecture via WORDSYNC matériel + DSKSYNC = `$4489`). Par ordre de risque décroissant :

1. **Settle inter-pas absent (le plus grave).** L'officiel attend **3 ms après CHAQUE pas**
   (timer.device). Notre seek enchaîne les pulses quasi dos-à-dos. Sur WinUAE timing-exact, la tête
   émulée ne « rattrape » pas sa position : stepper plus vite que ~3 ms/pas fait que le modèle de
   position de tête décroche, et la lecture suivante tombe sur le **mauvais cylindre** → données
   fausses / hang (exactement le profil du bug déjà vu : seek court qui hang, seek long qui passe).

2. **Settle post-seek de 15 ms absent.** L'officiel attend **15 ms** après le dernier pas avant de
   lire. Lire immédiatement = lire pendant que la tête se stabilise encore → secteurs illisibles de
   façon intermittente (dépend du cylindre et de la position rotationnelle).

3. **Attente moteur : poll `/RDY` au lieu d'un délai fixe de 500 ms.** L'officiel ne lit JAMAIS
   `/RDY` et applique un **délai aveugle de 500 ms** au seul front d'allumage. Un busy-poll `/RDY`
   sur WinUAE peut (a) se terminer trop tôt (sémantique `/RDY` du lecteur émulé ≠ « moteur à
   vitesse » — `/RDY` encode aussi l'ID lecteur), menant à une lecture avant stabilisation
   rotationnelle, ou (b) ne jamais voir le niveau attendu selon la modélisation → hang. Corollaire :
   notre impl risque de repayer l'attente à chaque accès, alors que l'officiel ne la paie qu'au
   changement d'état moteur.

4. **WORDSYNC matériel vs lecture brute + synchro logicielle.** L'officiel lit une **piste brute
   complète (> 1 révolution), WORDSYNC OFF, DSKSYNC jamais écrit**, et retrouve `$4489` en logiciel.
   Notre lecture WORDSYNC exige que (a) DSKSYNC contienne bien `$4489`, (b) le DMA soit armé AVANT
   que la marque passe sous la tête, (c) la longueur couvre réellement un secteur après synchro.
   Si la longueur vaut pile une piste et que l'armement rate la fenêtre de synchro, on perd des
   secteurs — défaut invisible sur un émulateur « lâche » qui aligne tout, mais exposé par un timing
   rotationnel exact. (Approche officielle = robuste par construction ; l'approche WORDSYNC est
   viable mais seulement si l'armement et la longueur sont irréprochables.)

5. **Pulse `/STEP` trop étroit + pas de délai de stabilisation avant armement DMA.** L'officiel
   intercale **2 NOP** dans le pulse `/STEP` (largeur garantie) et attend **1 ms après le select,
   avant d'armer le DMA** (étapes 3–4 du §3.2). Une impl qui émet un pulse dos-à-dos sans padding
   et/ou arme le DMA immédiatement après le select peut, sur timing-exact, voir le lecteur rater le
   pas et/ou le DMA démarrer sur un bus pas encore stabilisé.

**Détail d'ABI à ne pas oublier (cause possible de « rien ne se lit ») :** trackdisk **n'active
jamais DMACON lui-même** — il suppose `DSKEN`+`DMAEN` déjà posés globalement et n'arme que via la
**double-écriture DSKLEN**. Une impl qui compterait sur trackdisk pour activer DMACON, ou qui
oublierait la **double** écriture DSKLEN, n'obtiendra aucun transfert.
