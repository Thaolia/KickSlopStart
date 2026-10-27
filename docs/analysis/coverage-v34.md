# coverage-v34.md — Inventaire de couverture de la documentation d'analyse (Kickstart 1.3 / V34)

> Piste ANALYSE (« dirty »). Ce document ne décrit aucun comportement nouveau : il **inventorie** ce que
> `docs/analysis/*.md` spécifie déjà, ce que `src/` implémente, et mesure dans la ROM officielle
> (`kick34005.A500`, radare2, lecture seule) un **indicateur d'effort** (taille en octets) pour chaque
> fonction. Aucune instruction ROM, aucun listing, aucune adresse de routine n'y figure : seulement des
> noms d'ABI publics (`.fd`), des LVO, des numéros de commande, des comptes et des tailles.
> État au 2026-10-27 (dépôt au commit `15b9e8f`).

## 0. Résumé chiffré

- **390 LVO V34** inventoriés sur les 13 modules qui exposent des fonctions (dont **14 privés** au sens
  des `.fd` : 9 exec, 2 graphics, 2 dos, 1 expansion) ; **376 publics**.
- Couverture par la doc d'analyse : **73 spécifiés** (18,7 %), **73 partiels** (18,7 %), **123 seulement
  cités** comme appels d'un logiciel analysé (31,5 %), **121 absents** de toute spec (31,0 %).
  Couverture utile (spécifié + partiel) : **146 / 390 = 37,4 %**.
- Implémentation chez nous (tables de vecteurs de `src/`) : **327 / 390 = 83,8 %** ont une routine dédiée ;
  **6** sont des stubs (retour constant) ; **57** pointent sur un vecteur nul ou tombent **hors de la table**.
- Commandes de devices inventoriées en plus : 80 (keyboard 14, gameport 14, input 17, console 13,
  trackdisk 22), plus timer (3) et audio (15) décrits globalement.
- Les quatre zones les moins couvertes, en octets de code ROM non spécifiés : **graphics** (≈ 48 Ko
  atteints depuis ses vecteurs, 0 fonction spécifiée), **intuition** (≈ 42 Ko, moteur d'entrées, menus,
  écrans), **layers** (≈ 13 Ko, opérations de pile), **console.device** (≈ 5,5 Ko, rien de spécifié).

| Module | LVO V34 | Spécifiés | Partiels | Cités | Absents | Implémentés (routine dédiée) | Octets ROM atteints depuis les vecteurs |
|---|--:|--:|--:|--:|--:|--:|--:|
| exec | 101 | 14 | 15 | 38 | 34 | 90 | 6 778 |
| graphics | 105 | 0 | 12 | 51 | 42 | 78 | 48 346 |
| intuition | 74 | 17 | 14 | 28 | 15 | 58 | 42 590 |
| layers | 25 | 3 | 8 | 6 | 8 | 22 | 12 776 |
| dos | 33 | 15 | 18 | 0 | 0 | 29 | n/m (BCPL) |
| expansion | 21 | 21 | 0 | 0 | 0 | 21 | 1 710 |
| mathffp | 12 | 0 | 0 | 0 | 12 | 12 | 1 042 |
| timer (fonctions) | 3 | 3 | 0 | 0 | 0 | 3 | 360 (device entier) |
| console (fonctions) | 2 | 0 | 1 | 0 | 1 | 1 | 3 658 (vecteurs) + 1 878 (commandes) |
| cia.resource | 4 | 0 | 3 | 0 | 1 | 3 | 256 |
| disk.resource | 5 | 0 | 2 | 0 | 3 | 5 | 234 |
| potgo.resource | 3 | 0 | 0 | 0 | 3 | 3 | 178 |
| misc.resource | 2 | 0 | 0 | 0 | 2 | 2 | 68 |
| **Total** | **390** | **73** | **73** | **123** | **121** | **327** | |

## 1. Méthode (reproductible)

**Liste des LVO.** Fichiers `.fd` d'amitools (`amitools/data/fd/` de l'installation pipx) pour exec,
dos, graphics, intuition, mathffp et timer, **tronqués au premier marqueur « functions in V36 or
higher »** (les entrées « V33 or higher » sont gardées). Pour layers, expansion, console (fonctions),
cia, disk, potgo et misc, absents d'amitools : listes des `.fd` publics du NDK (`##bias 30`, 42 ou 6
selon le module). Chaque liste a été **recoupée avec le nombre d'entrées de la table de vecteurs
réelle** lue dans la ROM : exec 105 (= 4 + 101), graphics 109 (= 4 + 105), intuition 78 (= 4 + 74),
layers 29 (= 4 + 25), expansion 25, mathffp 16, timer 9 (= 6 + 3), console 8 (= 6 + 2), cia 4, disk 5,
potgo 3, misc 2. Tous concordent. keymap.resource n'a **aucune** table de fonctions en V34 (son init
alloue la structure, initialise sa liste et l'ajoute par AddResource, sans MakeFunctions) → 0 LVO.
dos construit ses vecteurs autrement (pont BCPL, cf. `bcpl-runtime-v34.md` §1.4) : sa table n'a pas été
localisée et ses tailles ne sont pas mesurées.

**Couverture.** Recherche de chaque nom (mot entier) dans `docs/analysis/*.md`, puis lecture des passages.
Niveaux :
- **oui** : une section décrit le comportement V34 de la fonction (contrat, effets, valeurs de retour) ;
- **partiel** : un aspect du contrat est établi (format, effet de bord, convention de registres, défaut
  corrigé par SetPatch…) au détour d'une autre spec ;
- **cité** : la fonction n'apparaît que comme appel fait par un logiciel analysé (aucun comportement de la
  ROM décrit) — compte comme **non couvert** ;
- **non** : aucune mention.

**Implémentation chez nous.** Lecture des tables de vecteurs de `src/` (et du remplissage de la jump
table exec dans `src/exec/library.s`) : **oui** = routine dédiée (ne garantit pas la complétude) ;
**stub** = corps de 1–2 instructions rendant une constante ; **non (vecteur nul)** = pointe sur la routine
« non implémenté » du module ; **absent (hors table)** = LVO au-delà de la fin de notre table. Pour les
commandes de devices : lecture des aiguillages de `BeginIO`.

**Taille dans la ROM officielle.** radare2 6.1.3 (`-a m68k -b 32`, base `$FC0000`). Les points d'entrée
sont lus dans les tables de vecteurs de la ROM (et dans les tables de commandes des devices) ; chaque
entrée est analysée comme fonction, puis ses appelés directs le sont à leur tour (clôture limitée à la
zone ROM du module). Deux nombres :
- **propre** : octets de blocs de base atteignables depuis CETTE entrée et depuis aucune autre entrée du
  même module (= travail spécifique à la fonction) ;
- **clôture** : tous les octets atteignables depuis l'entrée dans la zone du module (inclut le moteur
  partagé : pour un vecteur mince d'intuition ou de layers, c'est la clôture qui mesure l'effort réel).
- **stub ROM** : premier mot = retour immédiat, ou « constante dans D0 puis retour », ou clôture ≤ 4 octets.

Limites : les appels indirects (via `A6`, tables de saut internes) ne sont pas suivis ; les tailles sont
des **ordres de grandeur** (±20 %), pas des comptes exacts. Les priorités sont une proposition :
**P1** = absent/stub chez nous **et** utilisé par un logiciel connu, ou risque matériel réel ;
**P2** = implémenté sans spec et volumineux (clôture ≥ 300 o) ou semi-privé encore appelé ;
**P3** = petit, contrat AutoDoc suffisant, obsolète ou privé ; **—** = déjà spécifié (ou hors périmètre).

## 2. Les 24 résidents de la ROM

Zone ROM = distance entre la ROMTag du module et la ROMTag suivante dans la ROM (code + données ; pour
keymap/keyboard/gameport/input, dont les ROMTags sont groupées, le code vit dans la zone qui suit la
ROMTag de console.device : 14 196 octets partagés, répartition par clôture indiquée).

| # | Résident | Zone ROM (o) | Couverture d'analyse | Specs existantes | Chez nous | Priorité |
|--:|---|--:|---|---|---|:-:|
| 1 | exec.library 34.2 | 12 736 | partielle : ABI ExecBase, jump table, ordre de boot, mémoire/listes/exclusion au niveau AutoDoc | exec-spec, boot-sequence, test-vectors, module-map | `src/exec/*` (90/101 LVO) | P1 |
| 2 | expansion.library 34.1 | 2 176 | **complète** | autoconfig-v34 | `src/exec/expansion.s` | — |
| 3 | potgo.resource | 332 | aucune | — | `src/exec/potgo.s` | P2 |
| 4 | keymap.resource | 74 (+ init et tables dans la zone console) | aucune (structure sans LVO) | — | `src/exec/keymap.s` (expose 2 vecteurs qui n'existent pas en V34) | P2 |
| 5 | cia.resource (ciaa/ciab) | 648 | partielle : allocation des timers, ICR | timer-v34 §1, §6 ; keyboard-handshake §1–§2 | `src/exec/cia.s` (SetICR = stub) | P2 |
| 6 | disk.resource | 872 | partielle : GetUnit/GiveUnit (vus par SetPatch) | setpatch-disk-resource, setpatch-138 §1.7 | `src/exec/diskres.s` | P1 |
| 7 | misc.resource | 268 | aucune | — | `src/exec/misc.s` | P2 |
| 8 | ramlib.library | 1 564 | aucune (citée au boot) | boot-sequence, dos-boot-sequence | `src/exec/ramlib.s` (sans process propre) | P2 |
| 9 | graphics.library 34.1 | 59 816 | **très faible** : contrats déduits d'appelants | fastfonts-ff, caesar-boot, monkey-startup, octamed | `src/graphics/*` (78/105, table trop courte) | P1 |
| 10 | keyboard.device | zone commune (≈ 1,1 Ko par clôture) | partielle : réception, reset | keyboard-handshake | `src/exec/kbddev.s`, `keyboard.s` | P1 (matériel) |
| 11 | gameport.device | zone commune (≈ 1,2 Ko) | aucune | — | `src/exec/gameport.s` (BeginIO refuse tout) | P1 |
| 12 | timer.device 34.1 | 2 040 | **complète** | timer-v34 | `src/exec/timer.s` | — |
| 13 | audio.device 34.1 | 4 204 | aucune | — | `src/exec/audio.s` | P2 |
| 14 | input.device | zone commune (≈ 0,8 Ko) | partielle : répétition, seuils, chaîne de handlers | intuiticks-repeat, disk-change §3 | `src/exec/input.s` | P2 |
| 15 | layers.library 34.1 | 13 312 | partielle : InstallClipRegion, Begin/EndUpdate, verrous | installclipregion, wb-icon-clipping, intuition-gzz | `src/graphics/layers.s` | P1 |
| 16 | console.device | zone commune (≈ 5,5 Ko) | **quasi nulle** | handlers-v34 §2 (côté CON:) | `src/exec/console.s` (READ/WRITE seulement) | P1 |
| 17 | trackdisk.device 34.1 | 6 908 | partielle : lecture et timing, changement de disque | trackdisk-official-timing, disk-change | `src/exec/trackdisk.s` | P2 (écriture : autre agent) |
| 18 | intuition.library 34.3 | 52 248 | partielle : requesters, prefs, cadre, GZZ, prop | intuition-* | `src/intuition/*` (58/74) | P1 |
| 19 | alert.hook | 658 | aucune (citée) | boot-sequence, module-map | absent (Alert = message série) | P1 |
| 20 | mathffp.library | 1 324 | aucune | — | `src/exec/mathffp.s` | P3 |
| 21 | workbench.task 34.1 | 35 302 | **forte** | workbench-task, wb-icon-clipping, disk-change §4, loadwb-13 | `src/dos/workbench.s` | — |
| 22 | dos.library 34.3 | 49 542 | **forte** | dos-v34-spec, bcpl-runtime, handlers, fault, boot-clock, disk-full-write | `src/dos/*` | — |
| 23 | romboot.library | 1 052 | partielle | uae-hd-boot §2 | `src/exec/romboot.s` | P3 |
| 24 | strap 34.4 | 2 444 | partielle (essai DF0:, RomBoot) | uae-hd-boot §3, boot-sequence | `src/exec/strap.s` | P3 (coldstart : autre agent) |

## 3. Tableaux par module (fonctions publiques)

### exec.library (101 LVO, −30 à −630)

| LVO | Fonction | Spécifiée ? (fichier §) | Implémentée chez nous | Taille ROM (propre / clôture) | Priorité |
|---:|---|---|---|---|:-:|
| -30 | `Supervisor` | partiel — setpatch-138 §1.5 | oui | 14 / 14 | P3 |
| -36 | `execPrivate1` (= `ExitIntr`) *(privé)* | non | non (vecteur nul) | 124 / 162 | P2 |
| -42 | `execPrivate2` (= `Schedule`) *(privé)* | non | non (vecteur nul) | 4 / 4 (stub ROM) | P2 |
| -48 | `execPrivate3` (= `Reschedule`) *(privé)* | non | non (vecteur nul) | 48 / 48 | P2 |
| -54 | `execPrivate4` (= `Switch`) *(privé)* | non | non (vecteur nul) | 204 / 312 | P2 |
| -60 | `execPrivate5` (= `Dispatch`) *(privé)* | non | non (vecteur nul) | 18 / 18 | P2 |
| -66 | `execPrivate6` (= `Exception`) *(privé)* | non | non (vecteur nul) | 108 / 108 | P2 |
| -72 | `InitCode` | oui — boot-sequence §Phase 4 | oui | 56 / 56 | — |
| -78 | `InitStruct` | partiel — module-map §Structures d'auto-init | oui | 74 / 74 | P3 |
| -84 | `MakeLibrary` | partiel — boot-sequence §Phase 4 ; module-map §Structures d'auto-init | oui | 138 / 192 | P3 |
| -90 | `MakeFunctions` | partiel — module-map §Structures d'auto-init (format de table) | oui | 54 / 54 | P3 |
| -96 | `FindResident` | partiel — dos-boot-sequence §Phase A | oui | 48 / 48 | P3 |
| -102 | `InitResident` | oui — boot-sequence §Phase 4 | oui | 88 / 88 | — |
| -108 | `Alert` | partiel — setpatch-138 §1.3 ; intuition-requesters §5.3 | oui | 1264 / 1846 | P1 |
| -114 | `Debug` | non | non (vecteur nul) | 10 / 10 | P3 |
| -120 | `Disable` | oui — exec-spec §4 Exclusion mutuelle | oui | 14 / 14 | — |
| -126 | `Enable` | oui — exec-spec §4 Exclusion mutuelle | oui | 16 / 16 | — |
| -132 | `Forbid` | oui — exec-spec §4 Exclusion mutuelle | oui | 6 / 6 | — |
| -138 | `Permit` | oui — exec-spec §4 Exclusion mutuelle | oui | 20 / 20 | — |
| -144 | `SetSR` | non | oui | 12 / 12 | P3 |
| -150 | `SuperState` | non | oui | 12 / 12 | P3 |
| -156 | `UserState` | partiel — setpatch-138 §1.5 | oui | 10 / 10 | P3 |
| -162 | `SetIntVector` | cité — cracktros-exit §2 | oui | 70 / 70 | P2 |
| -168 | `AddIntServer` | cité — monkey-startup §2 ; sysinfo-44 §S2 | oui | 64 / 102 | P2 |
| -174 | `RemIntServer` | cité — sysinfo-44 §2.3 | oui | 72 / 86 | P2 |
| -180 | `Cause` | cité — keyboard-handshake §5 | oui | 96 / 96 | P2 |
| -186 | `Allocate` | non | oui | 82 / 82 | P3 |
| -192 | `Deallocate` | non | oui | 236 / 318 | P2 |
| -198 | `AllocMem` | oui — exec-spec §4 Gestion mémoire | oui | 236 / 318 | — |
| -204 | `AllocAbs` | cité — setpatch-138 §1.1 | oui | 144 / 144 | P3 |
| -210 | `FreeMem` | oui — exec-spec §4 Gestion mémoire | oui | 64 / 382 | — |
| -216 | `AvailMem` | oui — exec-spec §4 Gestion mémoire | oui | 78 / 78 | — |
| -222 | `AllocEntry` | partiel — setpatch-138 §1.4 | oui | 142 / 142 | P3 |
| -228 | `FreeEntry` | partiel — setpatch-138 §Exigences | oui | 62 / 62 | P3 |
| -234 | `Insert` | cité — workbench-task §3.6 | oui | 60 / 60 | P3 |
| -240 | `AddHead` | oui — exec-spec §4 Listes | oui | 60 / 60 | — |
| -246 | `AddTail` | oui — exec-spec §4 Listes | oui | 24 / 24 | — |
| -252 | `Remove` | oui — exec-spec §4 Listes | oui | 14 / 14 | — |
| -258 | `RemHead` | cité — uae-hd-boot §4.1 | oui | 16 / 16 | P3 |
| -264 | `RemTail` | cité — workbench-task §3.1 | oui | 22 / 22 | P3 |
| -270 | `Enqueue` | oui — exec-spec §4 Listes | oui | 38 / 38 | — |
| -276 | `FindName` | oui — exec-spec §4 Listes ; setpatch-138 §1.6 | oui | 40 / 40 | — |
| -282 | `AddTask` | partiel — workbench-task §1.3 (cadre initial) | oui | 164 / 202 | P3 |
| -288 | `RemTask` | partiel — bcpl-runtime §8.4.2, §13.7 | oui | 122 / 136 | P3 |
| -294 | `FindTask` | cité — loadwb-13 §1 | oui | 84 / 84 | P3 |
| -300 | `SetTaskPri` | cité — workbench-task §2.2 | oui | 80 / 132 | P3 |
| -306 | `SetSignal` | cité — handlers-v34 §3.6 | oui | 8 / 8 | P3 |
| -312 | `SetExcept` | non | oui | 156 / 194 | P3 |
| -318 | `Wait` | cité — exec-spec §3 | oui | 104 / 104 | P3 |
| -324 | `Signal` | cité — handlers-v34 §3.6 | oui | 20 / 20 | P3 |
| -330 | `AllocSignal` | cité — workbench-task §3.1 | oui | 56 / 56 | P3 |
| -336 | `FreeSignal` | non | oui | 16 / 16 | P3 |
| -342 | `AllocTrap` | non | oui | 38 / 38 | P3 |
| -348 | `FreeTrap` | non | oui | 16 / 16 | P3 |
| -354 | `AddPort` | cité — preferences-13 §4 | oui | 24 / 24 | P3 |
| -360 | `RemPort` | cité — fastfonts-ff §2 | oui | 4 / 32 | P3 |
| -366 | `PutMsg` | cité — dos-v34-spec §2a | oui | 6 / 122 | P3 |
| -372 | `GetMsg` | cité — dos-v34-spec §2a | oui | 46 / 46 | P3 |
| -378 | `ReplyMsg` | cité — dos-v34-spec §2a | oui | 26 / 142 | P3 |
| -384 | `WaitPort` | cité — dos-v34-spec §2a | oui | 40 / 40 | P3 |
| -390 | `FindPort` | cité — preferences-13 §4 | oui | 10 / 10 | P3 |
| -396 | `AddLibrary` | non | oui | 14 / 148 | P3 |
| -402 | `RemLibrary` | non | oui | 26 / 26 | P3 |
| -408 | `OldOpenLibrary` | cité — fastfonts-ff §Provenance | oui | 8 / 8 | P3 |
| -414 | `CloseLibrary` | cité — caesar-boot §1 | oui | 20 / 20 | P3 |
| -420 | `SetFunction` | partiel — fastfonts-ff §1, §3 (valeur rendue) | oui | 30 / 114 | P3 |
| -426 | `SumLibrary` | partiel — test-vectors §G | oui | 84 / 84 | P3 |
| -432 | `AddDevice` | cité — timer-v34 §1.1 | oui | 14 / 64 | P3 |
| -438 | `RemDevice` | non | oui | 26 / 26 | P3 |
| -444 | `OpenDevice` | cité — dos-boot-sequence §Phase D | oui | 78 / 118 | P3 |
| -450 | `CloseDevice` | cité — handlers-v34 §3.6 | oui | 22 / 22 | P3 |
| -456 | `DoIO` | cité — bcpl-runtime §8.4.2 | oui | 114 / 114 | P3 |
| -462 | `SendIO` | cité — handlers-v34 §3.6 | oui | 18 / 18 | P3 |
| -468 | `CheckIO` | partiel — intuition-requesters §7.1 | oui | 28 / 28 | P3 |
| -474 | `WaitIO` | cité — intuition-requesters §7.1 | oui | 114 / 114 | P3 |
| -480 | `AbortIO` | cité — intuiticks-repeat §2.1 | oui | 14 / 14 | P3 |
| -486 | `AddResource` | cité — uae-int2 §2.2 | oui | 8 / 8 | P3 |
| -492 | `RemResource` | non | oui | 4 / 32 | P3 |
| -498 | `OpenResource` | cité — setpatch-disk-resource §1 | oui | 18 / 58 | P3 |
| -504 | `execPrivate7` (= `RawIOInit`) *(privé)* | non | stub (retour constant) | 10 / 10 | P3 |
| -510 | `execPrivate8` (= `RawMayGetChar`) *(privé)* | non | oui | 32 / 32 | P3 |
| -516 | `execPrivate9` (= `RawPutChar`) *(privé)* | non | oui | 70 / 120 | P3 |
| -522 | `RawDoFmt` | cité — workbench-task §3.4 | oui | 214 / 452 | P2 |
| -528 | `GetCC` | non | oui | 8 / 8 | P3 |
| -534 | `TypeOfMem` | non | oui | 38 / 38 | P3 |
| -540 | `Procure` | non | non (vecteur nul) | 22 / 22 | P3 |
| -546 | `Vacate` | non | non (vecteur nul) | 34 / 34 | P3 |
| -552 | `OpenLibrary` | cité — caesar-boot §1 ; dos-boot-sequence | oui | 46 / 86 | P3 |
| -558 | `InitSemaphore` | cité — autoconfig-v34 §1 | oui | 32 / 32 | P3 |
| -564 | `ObtainSemaphore` | cité — autoconfig-v34 §7 | oui | 80 / 104 | P3 |
| -570 | `ReleaseSemaphore` | cité — autoconfig-v34 §7 | oui | 100 / 116 | P3 |
| -576 | `AttemptSemaphore` | non | oui | 48 / 48 | P3 |
| -582 | `ObtainSemaphoreList` | non | oui | 118 / 142 | P3 |
| -588 | `ReleaseSemaphoreList` | non | oui | 22 / 22 | P3 |
| -594 | `FindSemaphore` | non | oui | 10 / 10 | P3 |
| -600 | `AddSemaphore` | non | oui | 12 / 12 | P3 |
| -606 | `RemSemaphore` | non | oui | 4 / 32 | P3 |
| -612 | `SumKickData` | non | non (vecteur nul) | 88 / 88 | P2 |
| -618 | `AddMemList` | partiel — autoconfig-v34 §4 | oui | 84 / 134 | P3 |
| -624 | `CopyMem` | cité — autoconfig-v34 §6 | oui | 38 / 112 | P3 |
| -630 | `CopyMemQuick` | non | oui | 4 / 78 | P3 |

### graphics.library (105 LVO, −30 à −654)

| LVO | Fonction | Spécifiée ? (fichier §) | Implémentée chez nous | Taille ROM (propre / clôture) | Priorité |
|---:|---|---|---|---|:-:|
| -30 | `BltBitMap` | cité — installclipregion §3.2 | oui | 406 / 1680 | P1 |
| -36 | `BltTemplate` | partiel — fastfonts-ff §2 (contrat attendu) | oui | 692 / 1864 | P2 |
| -42 | `ClearEOL` | non | oui | 56 / 120 | P3 |
| -48 | `ClearScreen` | non | oui | 66 / 130 | P3 |
| -54 | `TextLength` | cité — intuition-frame §3.2 | oui | 96 / 96 | P3 |
| -60 | `Text` | partiel — fastfonts-ff §1–§4 | oui | 1028 / 1288 | P2 |
| -66 | `SetFont` | cité — fastfonts-ff §2 | oui | 28 / 28 | P3 |
| -72 | `OpenFont` | cité — fastfonts-ff §Options | oui | 170 / 170 | P3 |
| -78 | `CloseFont` | cité — intuition-prefs §3.3 | oui | 30 / 30 | P3 |
| -84 | `AskSoftStyle` | partiel — setpatch-138 §1.9 | oui | 36 / 36 | P3 |
| -90 | `SetSoftStyle` | partiel — setpatch-138 §1.9 | oui | 50 / 50 | P3 |
| -96 | `AddBob` | cité — workbench-task §3.6 | oui | 14 / 116 | P3 |
| -102 | `AddVSprite` | non | oui | 14 / 88 | P3 |
| -108 | `DoCollision` | non | oui | 1330 / 1824 | P2 |
| -114 | `DrawGList` | cité — workbench-task §3.6 | oui | 3098 / 6552 | P2 |
| -120 | `InitGels` | cité — workbench-task §3.1 | oui | 122 / 122 | P3 |
| -126 | `InitMasks` | non | oui | 12 / 246 | P3 |
| -132 | `RemIBob` | cité — workbench-task §3.6 | oui | 70 / 3166 | P2 |
| -138 | `RemVSprite` | non | oui | 12 / 32 | P3 |
| -144 | `SetCollision` | non | oui | 42 / 42 | P3 |
| -150 | `SortGList` | cité — workbench-task §3.6 | oui | 190 / 190 | P3 |
| -156 | `AddAnimOb` | non | oui | 96 / 198 | P3 |
| -162 | `Animate` | non | oui | 468 / 570 | P2 |
| -168 | `GetGBuffers` | non | oui | 350 / 382 | P2 |
| -174 | `InitGMasks` | non | oui | 70 / 304 | P2 |
| -180 | `DrawEllipse` | non | non (vecteur nul) | 22 / 672 | P2 |
| -186 | `AreaEllipse` | non | non (vecteur nul) | 188 / 188 | P2 |
| -192 | `LoadRGB4` | cité — monkey-startup §3 ; octamed §2.2 | oui | 272 / 676 | P2 |
| -198 | `InitRastPort` | cité — fastfonts-ff §3 | oui | 10 / 86 | P3 |
| -204 | `InitVPort` | non | non (vecteur nul) | 16 / 52 | P1 |
| -210 | `MrgCop` | partiel — caesar-boot §2.7 ; monkey-startup §3 | oui | 1354 / 1474 | P1 |
| -216 | `MakeVPort` | partiel — caesar-boot §1, §2.7 ; monkey-startup §3 | oui | 2554 / 3722 | P1 |
| -222 | `LoadView` | partiel — caesar-boot §2.7 | oui | 282 / 434 | P1 |
| -228 | `WaitBlit` | cité — fastfonts-ff §2 | oui | 36 / 36 | P1 |
| -234 | `SetRast` | cité — wb-icon-clipping §5 | oui | 646 / 1160 | P2 |
| -240 | `Move` | cité — preferences-13 §5.3 | oui | 20 / 20 | P3 |
| -246 | `Draw` | cité — preferences-13 §5.3 | oui | 2424 / 3494 | P2 |
| -252 | `AreaMove` | non | non (vecteur nul) | 148 / 148 | P1 |
| -258 | `AreaDraw` | non | non (vecteur nul) | 80 / 80 | P1 |
| -264 | `AreaEnd` | non | non (vecteur nul) | 1260 / 3056 | P1 |
| -270 | `WaitTOF` | cité — sysinfo-44 §1.3 | oui | 120 / 236 | P3 |
| -276 | `QBlit` | non | non (vecteur nul) | 22 / 638 | P2 |
| -282 | `InitArea` | non | non (vecteur nul) | 30 / 30 | P1 |
| -288 | `SetRGB4` | partiel — intuition-prefs §3.3 (masque 4 bits) | oui | 336 / 794 | P2 |
| -294 | `QBSBlit` | cité — timer-v34 §6.2 | non (vecteur nul) | 220 / 836 | P2 |
| -300 | `BltClear` | cité — workbench-task §3.6 | oui | 224 / 684 | P2 |
| -306 | `RectFill` | cité — intuition-frame §2 | oui | 180 / 234 | P3 |
| -312 | `BltPattern` | non | non (vecteur nul) | 3648 / 4654 | P2 |
| -318 | `ReadPixel` | non | oui | 264 / 300 | P2 |
| -324 | `WritePixel` | cité — octamed §2.3 | oui | 352 / 812 | P2 |
| -330 | `Flood` | cité — workbench-task §3.6 | non (vecteur nul) | 5634 / 8750 | P1 |
| -336 | `PolyDraw` | cité — octamed §2.3 | oui | 32 / 32 | P3 |
| -342 | `SetAPen` | cité — octamed §2.1 | oui | 6 / 78 | P3 |
| -348 | `SetBPen` | cité — octamed §2.1 | oui | 6 / 78 | P3 |
| -354 | `SetDrMd` | cité — preferences-13 §5.3 | oui | 4 / 4 (stub ROM) | P3 |
| -360 | `InitView` | partiel — intuition-prefs §1 (DxOffset/DyOffset) | non (vecteur nul) | 22 / 58 | P1 |
| -366 | `CBump` | cité — monkey-startup §3 | oui | 54 / 300 | P2 |
| -372 | `CMove` | cité — monkey-startup §3 | oui | 76 / 366 | P2 |
| -378 | `CWait` | cité — monkey-startup §3 | oui | 78 / 368 | P2 |
| -384 | `VBeamPos` | cité — octamed §2.3 | oui | 16 / 16 | P3 |
| -390 | `InitBitMap` | partiel — fastfonts-ff §3 (BytesPerRow) | oui | 22 / 22 | P3 |
| -396 | `ScrollRaster` | cité — wb-icon-clipping §0 | oui | 142 / 380 | P2 |
| -402 | `WaitBOVP` | non | non (vecteur nul) | 6 / 62 | P2 |
| -408 | `GetSprite` | cité — octamed §2.3 | oui | 136 / 168 | P3 |
| -414 | `FreeSprite` | cité — octamed §2.3 | oui | 68 / 132 | P3 |
| -420 | `ChangeSprite` | cité — octamed §2.3 | oui | 68 / 772 | P2 |
| -426 | `MoveSprite` | cité — octamed §2.3 | oui | 20 / 724 | P2 |
| -432 | `LockLayerRom` | partiel — fastfonts-ff §2 (A5, registres conservés) | oui | 22 / 22 | P3 |
| -438 | `UnlockLayerRom` | partiel — fastfonts-ff §2 | oui | 22 / 22 | P3 |
| -444 | `SyncSBitMap` | non | non (vecteur nul) | 12 / 2778 | P2 |
| -450 | `CopySBitMap` | non | non (vecteur nul) | 12 / 1014 | P2 |
| -456 | `OwnBlitter` | cité — monkey-startup §2 | oui | 24 / 236 | P2 |
| -462 | `DisownBlitter` | cité — monkey-startup §2 | oui | 104 / 234 | P2 |
| -468 | `InitTmpRas` | cité — workbench-task §3.6 | non (vecteur nul) | 12 / 12 | P1 |
| -474 | `AskFont` | non | oui | 18 / 18 | P3 |
| -480 | `AddFont` | non | oui | 58 / 58 | P3 |
| -486 | `RemFont` | non | oui | 78 / 78 | P3 |
| -492 | `AllocRaster` | cité — monkey-startup §2 | oui | 18 / 32 | P3 |
| -498 | `FreeRaster` | cité — caesar-boot §1 | oui | 20 / 34 | P3 |
| -504 | `AndRectRegion` | cité — wb-icon-clipping §1 | oui | 16 / 1510 | P2 |
| -510 | `OrRectRegion` | cité — wb-icon-clipping §1 | oui | 16 / 1278 | P2 |
| -516 | `NewRegion` | cité — wb-icon-clipping §1 | oui | 20 / 42 | P3 |
| -522 | `ClearRectRegion` | non | oui | 82 / 2582 | P2 |
| -528 | `ClearRegion` | cité — installclipregion §4.1 | oui | 12 / 110 | P3 |
| -534 | `DisposeRegion` | cité — wb-icon-clipping §2 | oui | 12 / 142 | P3 |
| -540 | `FreeVPortCopLists` | non | oui | 128 / 214 | P2 |
| -546 | `FreeCopList` | cité — octamed §2.3 | non (vecteur nul) | 14 / 100 | P2 |
| -552 | `ClipBlit` | cité — wb-icon-clipping §0 | non (vecteur nul) | 370 / 3206 | P1 |
| -558 | `XorRectRegion` | non | oui | 16 / 1814 | P2 |
| -564 | `FreeCprList` | non | non (vecteur nul) | 74 / 98 | P1 |
| -570 | `GetColorMap` | non | non (vecteur nul) | 88 / 88 | P1 |
| -576 | `FreeColorMap` | non | non (vecteur nul) | 36 / 36 | P1 |
| -582 | `GetRGB4` | cité — octamed §2.2 | oui | 24 / 24 | P3 |
| -588 | `ScrollVPort` | non | non (vecteur nul) | 2362 / 3442 | P1 |
| -594 | `UCopperListInit` | cité — monkey-startup §3 | oui | 16 / 306 | P2 |
| -600 | `FreeGBuffers` | non | oui | 254 / 264 | P3 |
| -606 | `BltBitMapRastPort` | cité — intuition-requesters §2.3 ; wb-icon-clipping §3 | oui | 272 / 3108 | P2 |
| -612 | `OrRegionRegion` | non | oui | 16 / 1370 | P2 |
| -618 | `XorRegionRegion` | non | oui | 16 / 1906 | P2 |
| -624 | `AndRegionRegion` | non | oui | 226 / 2326 | P2 |
| -630 | `SetRGB4CM` | non | non (vecteur nul) | 54 / 54 | P3 |
| -636 | `BltMaskBitMapRastPort` | cité — wb-icon-clipping §3, §8 | non (vecteur nul) | 470 / 3306 | P1 |
| -642 | `graphicsPrivate1` *(privé)* | non | absent (hors table) | 4 / 4 (stub ROM) | P3 |
| -648 | `graphicsPrivate2` *(privé)* | non | absent (hors table) | 4 / 4 (stub ROM) | P3 |
| -654 | `AttemptLockLayerRom` | non | absent (hors table) | 22 / 22 | P1 |

### intuition.library (74 LVO, −30 à −468)

| LVO | Fonction | Spécifiée ? (fichier §) | Implémentée chez nous | Taille ROM (propre / clôture) | Priorité |
|---:|---|---|---|---|:-:|
| -30 | `OpenIntuition` | non | non (vecteur nul) | 18 / 2530 | P3 |
| -36 | `Intuition` | partiel — intuiticks-repeat §3 ; intuition-requesters §3 ; intuition-gzz §3 | non (vecteur nul) | 15324 / 28100 | P1 |
| -42 | `AddGadget` | partiel — intuition-gzz §6.2 | oui | 62 / 474 | P2 |
| -48 | `ClearDMRequest` | oui — intuition-requesters §4.4 | oui | 30 / 76 | — |
| -54 | `ClearMenuStrip` | cité — workbench-task §4.1 | oui | 44 / 164 | P3 |
| -60 | `ClearPointer` | cité — octamed §2.3 | non (vecteur nul) | 66 / 922 | P1 |
| -66 | `CloseScreen` | cité — sysinfo-44 §S1 | oui | 54 / 12322 | P2 |
| -72 | `CloseWindow` | cité — intuition-requesters §5.1 | oui | 12 / 2550 | P2 |
| -78 | `CloseWorkBench` | cité — monkey-startup §2 ; workbench-task §0 | non (vecteur nul) | 84 / 12352 | P1 |
| -84 | `CurrentTime` | non | non (vecteur nul) | 38 / 38 | P2 |
| -90 | `DisplayAlert` | partiel — intuition-requesters §5.3 | non (vecteur nul) | 18 / 2330 | P1 |
| -96 | `DisplayBeep` | cité — workbench-task §6.2 | oui | 12 / 332 | P2 |
| -102 | `DoubleClick` | partiel — intuition-prefs §1, §3.3 | oui | 86 / 86 | P3 |
| -108 | `DrawBorder` | partiel — intuition-gzz §6.1 | oui | 20 / 572 | P2 |
| -114 | `DrawImage` | partiel — intuition-gzz §6.1 ; intuition-prop §3.1 | oui | 20 / 700 | P2 |
| -120 | `EndRequest` | oui — intuition-requesters §4 | oui | 14 / 668 | — |
| -126 | `GetDefPrefs` | oui — intuition-prefs §4.2 | oui | 68 / 260 | — |
| -132 | `GetPrefs` | oui — intuition-prefs §4.1 | oui | 50 / 154 | — |
| -138 | `InitRequester` | oui — intuition-requesters §4.3 | oui | 12 / 26 | — |
| -144 | `ItemAddress` | non | oui | 14 / 244 | P2 |
| -150 | `ModifyIDCMP` | cité — octamed §2.5 | oui | 14 / 1014 | P2 |
| -156 | `ModifyProp` | oui — intuition-prop §5 | oui | 6 / 6 | — |
| -162 | `MoveScreen` | cité — preferences-13 §4 | non (vecteur nul) | 18 / 804 | P2 |
| -168 | `MoveWindow` | partiel — installclipregion §4.2 | oui | 74 / 288 | P3 |
| -174 | `OffGadget` | non | oui | 42 / 7246 | P2 |
| -180 | `OffMenu` | cité — workbench-task §3.6 | oui | 40 / 486 | P2 |
| -186 | `OnGadget` | non | oui | 42 / 7246 | P2 |
| -192 | `OnMenu` | cité — workbench-task §3.6 | oui | 42 / 488 | P2 |
| -198 | `OpenScreen` | cité — monkey-startup §2 | oui | 12 / 10462 | P1 |
| -204 | `OpenWindow` | oui — intuition-frame §2 ; intuition-gzz §1–§2 | oui | 12 / 15640 | — |
| -210 | `OpenWorkBench` | partiel — intuition-prefs §3.3 | oui | 6 / 11734 | P2 |
| -216 | `PrintIText` | partiel — intuition-gzz §6.1 ; intuition-requesters §2.3 | oui | 20 / 802 | P2 |
| -222 | `RefreshGadgets` | oui — intuition-gzz §6.2 | oui | 16 / 7220 | — |
| -228 | `RemoveGadget` | cité — intuition-gzz §6.3 | oui | 48 / 498 | P2 |
| -234 | `ReportMouse` | cité — octamed §2.5 | oui | 66 / 94 | P3 |
| -240 | `Request` | oui — intuition-requesters §2–§3 | oui | 14 / 8662 | — |
| -246 | `ScreenToBack` | non | oui | 12 / 956 | P2 |
| -252 | `ScreenToFront` | cité — intuition-requesters §5.1 | oui | 32 / 984 | P2 |
| -258 | `SetDMRequest` | oui — intuition-requesters §4.4 | oui | 36 / 82 | — |
| -264 | `SetMenuStrip` | cité — workbench-task §3.2 | oui | 224 / 1446 | P2 |
| -270 | `SetPointer` | cité — monkey-startup §2 ; octamed §2.3 | non (vecteur nul) | 96 / 952 | P1 |
| -276 | `SetWindowTitles` | partiel — intuition-frame §3.2 ; workbench-task §6.6 | oui | 122 / 8486 | P2 |
| -282 | `ShowTitle` | partiel — monkey-startup §3 (d) | oui | 86 / 7914 | P2 |
| -288 | `SizeWindow` | non | oui | 74 / 288 | P3 |
| -294 | `ViewAddress` | cité — preferences-13 §4 | oui | 16 / 16 | P3 |
| -300 | `ViewPortAddress` | cité — octamed §2.1 | oui | 28 / 28 | P3 |
| -306 | `WindowToBack` | non | oui | 36 / 250 | P3 |
| -312 | `WindowToFront` | cité — workbench-task §3.3 | oui | 36 / 250 | P3 |
| -318 | `WindowLimits` | non | oui | 18 / 142 | P3 |
| -324 | `SetPrefs` | oui — intuition-prefs §3 | oui | 98 / 2530 | — |
| -330 | `IntuiTextLength` | non | oui | 12 / 672 | P2 |
| -336 | `WBenchToBack` | non | non (vecteur nul) | 6 / 1020 | P2 |
| -342 | `WBenchToFront` | non | non (vecteur nul) | 6 / 1030 | P2 |
| -348 | `AutoRequest` | oui — intuition-requesters §5.1 | oui | 270 / 20666 | — |
| -354 | `BeginRefresh` | cité — workbench-task §7.2 | oui | 12 / 168 | P3 |
| -360 | `BuildSysRequest` | oui — intuition-requesters §5.2 | oui | 20 / 20004 | — |
| -366 | `EndRefresh` | cité — workbench-task §7.2 | oui | 14 / 136 | P3 |
| -372 | `FreeSysRequest` | oui — intuition-requesters §5.4 | oui | 12 / 2964 | — |
| -378 | `MakeScreen` | non | non (vecteur nul) | 12 / 322 | P2 |
| -384 | `RemakeDisplay` | partiel — intuition-prefs §3.3 ; caesar-boot §1 | oui | 6 / 802 | P2 |
| -390 | `RethinkDisplay` | cité — monkey-startup §3 | oui | 6 / 6 | P3 |
| -396 | `AllocRemember` | cité — intuition-requesters §5.2 | oui | 18 / 164 | P3 |
| -402 | `AlohaWorkbench` | partiel — workbench-task §3.1 | non (vecteur nul) | 24 / 24 | P2 |
| -408 | `FreeRemember` | cité — intuition-requesters §5.4 | oui | 14 / 102 | P3 |
| -414 | `LockIBase` | non | non (vecteur nul) | 60 / 120 | P2 |
| -420 | `UnlockIBase` | non | non (vecteur nul) | 54 / 114 | P2 |
| -426 | `GetScreenData` | partiel — workbench-task §3.2 | oui | 112 / 11840 | P2 |
| -432 | `RefreshGList` | cité — octamed §2.4 (+ erreur intuition-gzz §6.2) | oui | 48 / 7222 | P2 |
| -438 | `AddGList` | cité — octamed §2.4 | oui | 20 / 432 | P2 |
| -444 | `RemoveGList` | cité — octamed §2.4 | oui | 18 / 468 | P2 |
| -450 | `ActivateWindow` | oui — intuition-frame §4.1 | non (vecteur nul) | 38 / 252 | — |
| -456 | `RefreshWindowFrame` | oui — intuition-frame §2 | non (vecteur nul) | 28 / 8686 | — |
| -462 | `ActivateGadget` | cité — workbench-task §6.8 | oui | 236 / 1232 | P2 |
| -468 | `NewModifyProp` | oui — intuition-prop §5 | oui | 82 / 7256 | — |

### layers.library (25 LVO, −30 à −174)

| LVO | Fonction | Spécifiée ? (fichier §) | Implémentée chez nous | Taille ROM (propre / clôture) | Priorité |
|---:|---|---|---|---|:-:|
| -30 | `InitLayers` | non | oui | 10 / 120 | P3 |
| -36 | `CreateUpfrontLayer` | partiel — intuition-gzz §2 | oui | 118 / 10140 | P2 |
| -42 | `CreateBehindLayer` | partiel — intuition-requesters §2.2 | oui | 20 / 9850 | P2 |
| -48 | `UpfrontLayer` | cité — installclipregion §4.2 | oui | 10 / 6284 | P1 |
| -54 | `BehindLayer` | cité — installclipregion §4.2 | oui | 90 / 6296 | P1 |
| -60 | `MoveLayer` | cité — installclipregion §4.2 | oui | 320 / 10916 | P1 |
| -66 | `SizeLayer` | cité — installclipregion §4.2 | oui | 618 / 11232 | P1 |
| -72 | `ScrollLayer` | cité — installclipregion §4.2 | stub (retour constant) | 108 / 1136 | P2 |
| -78 | `BeginUpdate` | oui — installclipregion §4.1 ; wb-icon-clipping §1 | oui | 56 / 2640 | — |
| -84 | `EndUpdate` | oui — installclipregion §4.1 ; wb-icon-clipping §2 | oui | 76 / 2678 | — |
| -90 | `DeleteLayer` | partiel — setpatch-disk-resource §4 ; installclipregion §4.2 | oui | 10 / 7432 | P2 |
| -96 | `LockLayer` | partiel — installclipregion §4.3 | oui | 10 / 32 | P3 |
| -102 | `UnlockLayer` | non | oui | 10 / 32 | P3 |
| -108 | `LockLayers` | partiel — installclipregion §4.2 | oui | 10 / 710 | P2 |
| -114 | `UnlockLayers` | partiel — installclipregion §4.2 | oui | 10 / 2392 | P2 |
| -120 | `LockLayerInfo` | partiel — installclipregion §4.3 | oui | 10 / 44 | P3 |
| -126 | `SwapBitsRastPortClipRect` | non | oui | 12 / 320 | P2 |
| -132 | `WhichLayer` | cité — workbench-task §3.6 | oui | 46 / 46 | P3 |
| -138 | `UnlockLayerInfo` | non | oui | 10 / 44 | P3 |
| -144 | `NewLayerInfo` | non | oui | 72 / 314 | P2 |
| -150 | `DisposeLayerInfo` | non | oui | 40 / 116 | P3 |
| -156 | `FattenLayerInfo` | non | stub (retour constant) | 44 / 176 | P3 |
| -162 | `ThinLayerInfo` | non | stub (retour constant) | 34 / 110 | P3 |
| -168 | `MoveLayerInFrontOf` | partiel — intuition-gzz §2.2 ; installclipregion §4.2 | oui | 84 / 6230 | P2 |
| -174 | `InstallClipRegion` | oui — installclipregion §1–§7 | oui | 78 / 2684 | — |

### dos.library (33 LVO, −30 à −222)

Tailles : chaque LVO de dos est un pont mince vers une globale BCPL (bcpl-runtime §1.4) ; la taille du code BCPL n'est pas mesurée ici (colonne « n/m »).

| LVO | Fonction | Spécifiée ? (fichier §) | Implémentée chez nous | Taille ROM (propre / clôture) | Priorité |
|---:|---|---|---|---|:-:|
| -30 | `Open` | oui — dos-v34-spec §2–§3 ; bcpl-runtime §5.1 | oui | n/m | — |
| -36 | `Close` | oui — bcpl-runtime §5.1 ; dos-v34-spec §2b | oui | n/m | — |
| -42 | `Read` | oui — dos-v34-spec §3 ; bcpl-runtime §5.1 | oui | n/m | — |
| -48 | `Write` | oui — disk-full-write §3 ; bcpl-runtime §6.1 | oui | n/m | — |
| -54 | `Input` | partiel — bcpl-runtime §8.1 | oui | n/m | P3 |
| -60 | `Output` | partiel — bcpl-runtime §8.1 | oui | n/m | P3 |
| -66 | `Seek` | partiel — bcpl-runtime §8.3 ; disk-full-write §1 | oui | n/m | P3 |
| -72 | `DeleteFile` | partiel — bcpl-runtime §8.3 | oui | n/m | P3 |
| -78 | `Rename` | partiel — bcpl-runtime §8.4.2 | oui | n/m | P3 |
| -84 | `Lock` | oui — dos-v34-spec §2b ; disk-change §2.4 | oui | n/m | — |
| -90 | `UnLock` | oui — dos-v34-spec §2b | oui | n/m | — |
| -96 | `DupLock` | partiel — bcpl-runtime §8.2 | oui | n/m | P3 |
| -102 | `Examine` | oui — dos-v34-spec §2b | oui | n/m | — |
| -108 | `ExNext` | oui — dos-v34-spec §2b | oui | n/m | — |
| -114 | `Info` | partiel — bcpl-runtime §8.3 ; disk-change §2.3 | oui | n/m | P3 |
| -120 | `CreateDir` | partiel — bcpl-runtime §8.3 | oui | n/m | P3 |
| -126 | `CurrentDir` | partiel — bcpl-runtime §8.3 | oui | n/m | P3 |
| -132 | `IoErr` | partiel — bcpl-runtime §8.3 | oui | n/m | P3 |
| -138 | `CreateProc` | oui — dos-v34-spec §4 ; bcpl-runtime §8.1 ; workbench-task §1.3 | oui | n/m | — |
| -144 | `Exit` | oui — bcpl-runtime §4.3, §8.1 | non (vecteur nul) | n/m | — |
| -150 | `LoadSeg` | partiel — bcpl-runtime §3 ; dos-boot-sequence §Phase E | oui | n/m | P3 |
| -156 | `UnLoadSeg` | partiel — bcpl-runtime §8.2 | oui | n/m | P3 |
| -162 | `dosPrivate1` (= `GetPacket`) *(privé)* | oui — bcpl-runtime §1.4 (anomalie globale −20) | non (vecteur nul) | n/m | — |
| -168 | `dosPrivate2` (= `QueuePacket`) *(privé)* | oui — bcpl-runtime §1.4 (globale −21) | non (vecteur nul) | n/m | — |
| -174 | `DeviceProc` | oui — handlers-v34 §4.1 | oui | n/m | — |
| -180 | `SetComment` | partiel — bcpl-runtime §8.3 | oui | n/m | P3 |
| -186 | `SetProtection` | partiel — bcpl-runtime §8.3 | oui | n/m | P3 |
| -192 | `DateStamp` | oui — bcpl-runtime §8.4.2 ; boot-clock | oui | n/m | — |
| -198 | `Delay` | partiel — bcpl-runtime §8.1 | oui | n/m | P3 |
| -204 | `WaitForChar` | partiel — bcpl-runtime §8.2 | stub (retour constant) | n/m | P2 |
| -210 | `ParentDir` | partiel — dos-v34-spec §2b ; bcpl-runtime §8.1 | oui | n/m | P3 |
| -216 | `IsInteractive` | partiel — bcpl-runtime §5.1 | oui | n/m | P3 |
| -222 | `Execute` | oui — bcpl-runtime §0, §13 ; setpatch-138 §3.2 | oui | n/m | — |

### expansion.library (21 LVO, −30 à −150)

| LVO | Fonction | Spécifiée ? (fichier §) | Implémentée chez nous | Taille ROM (propre / clôture) | Priorité |
|---:|---|---|---|---|:-:|
| -30 | `AddConfigDev` | oui — autoconfig-v34 §7 | oui | 28 / 28 | — |
| -36 | `expansionPrivate36` (= `expansionUnused`) *(privé)* | oui — autoconfig-v34 §7 | oui | 24 / 24 | — |
| -42 | `AllocBoardMem` | oui — autoconfig-v34 §7 | oui | 24 / 24 | — |
| -48 | `AllocConfigDev` | oui — autoconfig-v34 §7 | oui | 22 / 22 | — |
| -54 | `AllocExpansionMem` | oui — autoconfig-v34 §7 | oui | 140 / 140 | — |
| -60 | `ConfigBoard` | oui — autoconfig-v34 §7 | oui | 380 / 380 | — |
| -66 | `ConfigChain` | oui — autoconfig-v34 §7 | oui | 86 / 86 | — |
| -72 | `FindConfigDev` | oui — autoconfig-v34 §7 | oui | 54 / 54 | — |
| -78 | `FreeBoardMem` | oui — autoconfig-v34 §7 | oui | 16 / 16 | — |
| -84 | `FreeConfigDev` | oui — autoconfig-v34 §7 | oui | 18 / 18 | — |
| -90 | `FreeExpansionMem` | oui — autoconfig-v34 §7 | oui | 56 / 56 | — |
| -96 | `ReadExpansionByte` | oui — autoconfig-v34 §7 | oui | 28 / 28 | — |
| -102 | `ReadExpansionRom` | oui — autoconfig-v34 §7 | oui | 168 / 168 | — |
| -108 | `RemConfigDev` | oui — autoconfig-v34 §7 | oui | 32 / 32 | — |
| -114 | `WriteExpansionByte` | oui — autoconfig-v34 §7 | oui | 20 / 20 | — |
| -120 | `ObtainConfigBinding` | oui — autoconfig-v34 §7 | oui | 18 / 18 | — |
| -126 | `ReleaseConfigBinding` | oui — autoconfig-v34 §7 | oui | 18 / 18 | — |
| -132 | `SetCurrentBinding` | oui — autoconfig-v34 §7 | oui | 12 / 40 | — |
| -138 | `GetCurrentBinding` | oui — autoconfig-v34 §7 | oui | 16 / 44 | — |
| -144 | `MakeDosNode` | oui — autoconfig-v34 §7 | oui | 264 / 264 | — |
| -150 | `AddDosNode` | oui — autoconfig-v34 §7 | oui | 242 / 242 | — |

### mathffp.library (12 LVO, −30 à −96)

| LVO | Fonction | Spécifiée ? (fichier §) | Implémentée chez nous | Taille ROM (propre / clôture) | Priorité |
|---:|---|---|---|---|:-:|
| -30 | `SPFix` | non | oui | 82 / 82 | P3 |
| -36 | `SPFlt` | non | oui | 56 / 56 | P3 |
| -42 | `SPCmp` | non | oui | 60 / 60 | P3 |
| -48 | `SPTst` | non | oui | 40 / 40 | P3 |
| -54 | `SPAbs` | non | oui | 6 / 6 | P3 |
| -60 | `SPNeg` | non | oui | 10 / 10 | P3 |
| -66 | `SPAdd` | non | oui | 16 / 16 | P3 |
| -72 | `SPSub` | non | oui | 254 / 254 | P3 |
| -78 | `SPMul` | non | oui | 154 / 154 | P3 |
| -84 | `SPDiv` | non | oui | 166 / 166 | P3 |
| -90 | `SPFloor` | non | oui | 86 / 366 | P3 |
| -96 | `SPCeil` | non | oui | 10 / 376 | P3 |

### timer.device — fonctions (3 LVO, −42 à −54)

| LVO | Fonction | Spécifiée ? (fichier §) | Implémentée chez nous | Taille ROM (propre / clôture) | Priorité |
|---:|---|---|---|---|:-:|
| -42 | `AddTime` | oui — timer-v34 §5 | oui | 36 / 36 | — |
| -48 | `SubTime` | oui — timer-v34 §5 | oui | 28 / 28 | — |
| -54 | `CmpTime` | oui — timer-v34 §5 | oui | 28 / 28 | — |

### console.device — fonctions (2 LVO, −42 à −48)

| LVO | Fonction | Spécifiée ? (fichier §) | Implémentée chez nous | Taille ROM (propre / clôture) | Priorité |
|---:|---|---|---|---|:-:|
| -42 | `CDInputHandler` | non | non (vecteur nul) | 706 / 1000 | P2 |
| -48 | `RawKeyConvert` | partiel — monkey-startup §6 | oui | 516 / 516 | P2 |

### cia.resource (ciaa/ciab, 4 LVO, −6 à −24)

| LVO | Fonction | Spécifiée ? (fichier §) | Implémentée chez nous | Taille ROM (propre / clôture) | Priorité |
|---:|---|---|---|---|:-:|
| -6 | `AddICRVector` | partiel — keyboard-handshake §1–§2 ; timer-v34 §1, §6 | oui | 58 / 184 | P3 |
| -12 | `RemICRVector` | non | oui | 36 / 162 | P2 |
| -18 | `AbleICR` | partiel — timer-v34 §6.2 | oui | 98 / 98 | P3 |
| -24 | `SetICR` | partiel — timer-v34 §6.2 | stub (retour constant) | 36 / 36 | P2 |

### disk.resource (5 LVO, −6 à −30)

| LVO | Fonction | Spécifiée ? (fichier §) | Implémentée chez nous | Taille ROM (propre / clôture) | Priorité |
|---:|---|---|---|---|:-:|
| -6 | `AllocUnit` | non | oui | 12 / 12 | P2 |
| -12 | `FreeUnit` | non | oui | 6 / 6 | P2 |
| -18 | `GetUnit` | partiel — setpatch-138 §1.7 ; setpatch-disk-resource §3 | oui | 120 / 120 | P3 |
| -24 | `GiveUnit` | partiel — setpatch-138 §1.7 ; setpatch-disk-resource §3 | oui | 84 / 84 | P3 |
| -30 | `GetUnitID` | non | oui | 12 / 12 | P1 |

### potgo.resource (3 LVO, −6 à −18)

| LVO | Fonction | Spécifiée ? (fichier §) | Implémentée chez nous | Taille ROM (propre / clôture) | Priorité |
|---:|---|---|---|---|:-:|
| -6 | `AllocPotBits` | non | oui | 106 / 106 | P2 |
| -12 | `FreePotBits` | non | oui | 22 / 22 | P2 |
| -18 | `WritePotgo` | non | oui | 50 / 50 | P2 |

### misc.resource (2 LVO, −6 à −12)

| LVO | Fonction | Spécifiée ? (fichier §) | Implémentée chez nous | Taille ROM (propre / clôture) | Priorité |
|---:|---|---|---|---|:-:|
| -6 | `AllocMiscResource` | non | oui | 56 / 56 | P2 |
| -12 | `FreeMiscResource` | non | oui | 12 / 12 | P2 |

## 4. Commandes des devices

Les vecteurs standard (Open, Close, Expunge, réservé, BeginIO, AbortIO) ne sont pas répétés ; les
commandes sont la vraie API. Les routines CMD_INVALID…CMD_FLUSH de keyboard, gameport, input et console
sont en partie **communes** aux quatre devices dans la ROM (même code pour plusieurs entrées).

- **timer.device** : TR_ADDREQUEST (9), TR_GETSYSTIME (10), TR_SETSYSTIME (11) — **spécifiées**
  (timer-v34 §2–§4), implémentées ; device entier ≈ 360 octets atteints depuis ses 9 vecteurs.
- **audio.device** : CMD_RESET, CMD_READ, CMD_WRITE, CMD_UPDATE, CMD_CLEAR, CMD_STOP, CMD_START,
  CMD_FLUSH, ADCMD_FREE, ADCMD_SETPREC, ADCMD_FINISH, ADCMD_PERVOL, ADCMD_LOCK, ADCMD_WAITCYCLE,
  ADCMD_ALLOCATE — **aucune spécifiée** (seulement citées : octamed §2.5) ; toutes présentes dans
  `src/exec/audio.s`. Taille : 2 464 octets atteints depuis les 6 vecteurs (BeginIO seul ≈ 1,7 Ko de
  clôture), zone ROM 4 204 octets. Table de commandes non décodée (aiguillage interne).

#### keyboard.device (14 commandes, 0–13)

| N° | Commande | Spécifiée ? | Implémentée chez nous | Taille ROM (propre / clôture) | Priorité |
|---:|---|---|---|---|:-:|
| 0 | `CMD_INVALID` | non | non vérifié | 8 / 134 | P3 |
| 1 | `CMD_RESET` | non | non vérifié | 56 / 280 | P3 |
| 2 | `CMD_READ` | non | non vérifié | 4 / 4 (routine partagée ×3) (stub ROM) | P3 |
| 3 | `CMD_WRITE` | non | non vérifié | 4 / 4 (routine partagée ×3) (stub ROM) | P3 |
| 4 | `CMD_UPDATE` | non | non vérifié | 4 / 4 (routine partagée ×3) (stub ROM) | P3 |
| 5 | `CMD_CLEAR` | non | oui | 36 / 42 | P3 |
| 6 | `CMD_STOP` | non | non vérifié | 16 / 142 | P3 |
| 7 | `CMD_START` | non | non vérifié | 44 / 170 | P3 |
| 8 | `CMD_FLUSH` | non | non vérifié | 32 / 164 | P3 |
| 9 | `KBD_READEVENT` | partiel — keyboard-handshake §3 | oui | 230 / 362 | P2 |
| 10 | `KBD_READMATRIX` | non | oui | 42 / 42 | P2 |
| 11 | `KBD_ADDRESETHANDLER` | partiel — keyboard-handshake §5 | oui | 26 / 32 | P2 |
| 12 | `KBD_REMRESETHANDLER` | non | oui | 22 / 28 | P3 |
| 13 | `KBD_RESETHANDLERDONE` | partiel — keyboard-handshake §5 | oui | 16 / 22 | P2 |

#### gameport.device (14 commandes, 0–13)

| N° | Commande | Spécifiée ? | Implémentée chez nous | Taille ROM (propre / clôture) | Priorité |
|---:|---|---|---|---|:-:|
| 0 | `CMD_INVALID` | non | non (IOERR_NOCMD) | 8 / 134 | P3 |
| 1 | `CMD_RESET` | non | non (IOERR_NOCMD) | 14 / 238 | P3 |
| 2 | `CMD_READ` | non | non (IOERR_NOCMD) | 4 / 4 (routine partagée ×3) (stub ROM) | P3 |
| 3 | `CMD_WRITE` | non | non (IOERR_NOCMD) | 4 / 4 (routine partagée ×3) (stub ROM) | P3 |
| 4 | `CMD_UPDATE` | non | non (IOERR_NOCMD) | 4 / 4 (routine partagée ×3) (stub ROM) | P3 |
| 5 | `CMD_CLEAR` | non | non (IOERR_NOCMD) | 38 / 38 | P2 |
| 6 | `CMD_STOP` | non | non (IOERR_NOCMD) | 16 / 142 | P3 |
| 7 | `CMD_START` | non | non (IOERR_NOCMD) | 44 / 170 | P3 |
| 8 | `CMD_FLUSH` | non | non (IOERR_NOCMD) | 32 / 164 | P3 |
| 9 | `GPD_READEVENT` | non | non (IOERR_NOCMD) | 268 / 394 | P1 |
| 10 | `GPD_ASKCTYPE` | non | non (IOERR_NOCMD) | 42 / 42 | P1 |
| 11 | `GPD_SETCTYPE` | cité — intuiticks-repeat §1.1 | non (IOERR_NOCMD) | 84 / 84 | P1 |
| 12 | `GPD_ASKTRIGGER` | non | non (IOERR_NOCMD) | 48 / 48 | P1 |
| 13 | `GPD_SETTRIGGER` | non | non (IOERR_NOCMD) | 48 / 48 | P1 |

#### input.device (17 commandes, 0–16)

| N° | Commande | Spécifiée ? | Implémentée chez nous | Taille ROM (propre / clôture) | Priorité |
|---:|---|---|---|---|:-:|
| 0 | `CMD_INVALID` | non | non vérifié | 8 / 134 | P3 |
| 1 | `CMD_RESET` | non | non vérifié | 14 / 242 | P3 |
| 2 | `CMD_READ` | non | non vérifié | 4 / 4 (routine partagée ×3) (stub ROM) | P3 |
| 3 | `CMD_WRITE` | non | non vérifié | 4 / 4 (routine partagée ×3) (stub ROM) | P3 |
| 4 | `CMD_UPDATE` | non | non vérifié | 4 / 4 (routine partagée ×3) (stub ROM) | P3 |
| 5 | `CMD_CLEAR` | non | non vérifié | 2 / 2 (stub ROM) | P3 |
| 6 | `CMD_STOP` | non | non vérifié | 16 / 142 | P3 |
| 7 | `CMD_START` | non | non vérifié | 48 / 48 | P3 |
| 8 | `CMD_FLUSH` | non | non vérifié | 32 / 164 | P3 |
| 9 | `IND_ADDHANDLER` | partiel — intuiticks-repeat §1.4 | oui | 8 / 8 (routine partagée ×3) | P3 |
| 10 | `IND_REMHANDLER` | partiel — intuiticks-repeat §1.4 | oui | 8 / 8 (routine partagée ×3) | P3 |
| 11 | `IND_WRITEEVENT` | partiel — disk-change §3 | oui | 8 / 8 (routine partagée ×3) | P3 |
| 12 | `IND_SETTHRESH` | oui — intuiticks-repeat §1.2, §2 | oui | 12 / 12 | — |
| 13 | `IND_SETPERIOD` | oui — intuiticks-repeat §1.2, §2 | oui | 14 / 20 | — |
| 14 | `IND_SETMPORT` | partiel — intuiticks-repeat §1.1–§1.2 | non (IOERR_NOCMD) | 32 / 32 | P1 |
| 15 | `IND_SETMTYPE` | partiel — intuiticks-repeat §1.1–§1.2 | non (IOERR_NOCMD) | 26 / 26 | P1 |
| 16 | `IND_SETMTRIG` | partiel — intuiticks-repeat §1.2 | non (IOERR_NOCMD) | 46 / 46 | P1 |

#### console.device (13 commandes, 0–12)

| N° | Commande | Spécifiée ? | Implémentée chez nous | Taille ROM (propre / clôture) | Priorité |
|---:|---|---|---|---|:-:|
| 0 | `CMD_INVALID` | non | non vérifié | 8 / 134 | P3 |
| 1 | `CMD_RESET` | non | non vérifié | 14 / 238 | P3 |
| 2 | `CMD_READ` | cité — handlers-v34 §2 | oui (partiel) | 142 / 318 | P1 |
| 3 | `CMD_WRITE` | cité — handlers-v34 §2 (séquences CSI non spécifiées) | oui (partiel) | 1314 / 1632 | P1 |
| 4 | `CMD_UPDATE` | non | non vérifié | 4 / 4 (stub ROM) | P3 |
| 5 | `CMD_CLEAR` | non | non (IOERR_NOCMD) | 12 / 12 | P2 |
| 6 | `CMD_STOP` | non | non vérifié | 16 / 142 | P3 |
| 7 | `CMD_START` | non | non vérifié | 44 / 170 | P3 |
| 8 | `CMD_FLUSH` | non | non vérifié | 32 / 164 | P3 |
| 9 | `CD_ASKKEYMAP` | non | non (IOERR_NOCMD) | 16 / 72 | P1 |
| 10 | `CD_SETKEYMAP` | non | non (IOERR_NOCMD) | 16 / 72 | P1 |
| 11 | `CD_ASKDEFAULTKEYMAP` | non | non (IOERR_NOCMD) | 12 / 68 | P1 |
| 12 | `CD_SETDEFAULTKEYMAP` | non | non (IOERR_NOCMD) | 10 / 10 | P1 |

#### trackdisk.device (22 commandes, 0–21 ; borne testée par BeginIO = 22)

| N° | Commande | Spécifiée ? | Implémentée chez nous | Taille ROM (propre / clôture) | Priorité |
|---:|---|---|---|---|:-:|
| 0 | `CMD_INVALID` | non | oui | 12 / 72 (routine partagée ×5) | P3 |
| 1 | `CMD_RESET` | non | no-op | 12 / 72 (routine partagée ×5) | P3 |
| 2 | `CMD_READ` | oui — trackdisk-official-timing §1–§3 | oui | 520 / 2880 (routine partagée ×2) | — |
| 3 | `CMD_WRITE` | hors périmètre (agent écriture) | oui | 520 / 2880 (routine partagée ×2) | — |
| 4 | `CMD_UPDATE` | hors périmètre (agent écriture) | oui | 50 / 1086 | — |
| 5 | `CMD_CLEAR` | partiel — disk-change §2.1 ; uae-hd-boot §3 | oui | 22 / 82 | P3 |
| 6 | `CMD_STOP` | non | no-op | 12 / 72 (routine partagée ×5) | P3 |
| 7 | `CMD_START` | non | no-op | 12 / 72 (routine partagée ×5) | P3 |
| 8 | `CMD_FLUSH` | non | no-op | 12 / 72 (routine partagée ×5) | P3 |
| 9 | `TD_MOTOR` | partiel — intuition-requesters §7.1 ; trackdisk-official-timing §1 | oui | 22 / 342 | P3 |
| 10 | `TD_SEEK` | oui — trackdisk-official-timing §2 | no-op | 38 / 628 | P3 |
| 11 | `TD_FORMAT` | hors périmètre (agent écriture) | oui | 374 / 1668 | — |
| 12 | `TD_REMOVE` | oui — disk-change §2.1 | no-op | 12 / 72 | P2 |
| 13 | `TD_CHANGENUM` | partiel — uae-hd-boot §3 ; disk-change §2.1 | oui | 12 / 72 | P3 |
| 14 | `TD_CHANGESTATE` | partiel — disk-change §2.1 | oui | 20 / 80 | P3 |
| 15 | `TD_PROTSTATUS` | partiel — disk-change §2.5 | oui | 90 / 410 | P3 |
| 16 | `TD_RAWREAD` | non | non (IOERR_NOCMD) | 120 / 756 | P2 |
| 17 | `TD_RAWWRITE` | non (relève de l'agent écriture) | non (IOERR_NOCMD) | 4 / 4 (stub ROM) | — |
| 18 | `TD_GETDRIVETYPE` | non | non (IOERR_NOCMD) | 18 / 78 | P2 |
| 19 | `TD_GETNUMTRACKS` | non | oui | 18 / 78 | P3 |
| 20 | `TD_ADDCHANGEINT` | cité — disk-change §2.1 (dit « V36 », cf. §5) | no-op | 28 / 28 | P2 |
| 21 | `TD_REMCHANGEINT` | cité — disk-change §2.1 | no-op | 22 / 82 | P2 |

## 5. Incohérences relevées dans la doc d'analyse existante (à corriger par la piste analyse)

1. **`intuition-gzz-v34.md` §6.2** classe `RefreshGList` « V36+, absent en 1.3 ». C'est faux :
   `RefreshGList` (−432), `AddGList` (−438), `RemoveGList` (−444), `ActivateWindow` (−450),
   `RefreshWindowFrame` (−456), `ActivateGadget` (−462) et `NewModifyProp` (−468) sont des fonctions
   **V33** (`.fd`), et la table de vecteurs d'intuition 34.3 compte bien 78 entrées (4 + 74).
2. **`exec-spec.md` §3 (« Delta »)** range `AddMemList` (−618), `CopyMem` (−624) et `CopyMemQuick` (−630)
   parmi les ajouts V36. La table exec de la ROM compte **105 entrées** et va jusqu'à −630 : ces trois
   fonctions existent en V34 (déjà signalé en §5 du même fichier, mais le §3 n'a pas été corrigé).
3. **`disk-change-v34.md` §2.1** qualifie `TD_ADDCHANGEINT` de V36. Le BeginIO de trackdisk 34.1
   accepte les commandes **< 22**, et les entrées 20 (`TD_ADDCHANGEINT`) et 21 (`TD_REMCHANGEINT`) de sa
   table pointent sur des routines **dédiées** (≈ 28 et 22 octets), distinctes de la routine « commande
   invalide ». À trancher par une sonde boîte noire (DoIO `TD_ADDCHANGEINT` sur la vraie 1.3 :
   io_Error, et l'interruption est-elle appelée à l'éjection ?).
4. **`module-map.md`** indique que le nombre de LVO des modules non-AUTOINIT « n'est pas mesurable sans
   tracer MakeLibrary ». Il l'est par lecture des tables : graphics 109, layers 29, exec 105, timer 9,
   console 8, keyboard/gameport/input/audio/trackdisk 6, romboot 5, disk 5, cia 4, potgo 3, misc 2,
   keymap 0 (cf. §1). Seule la table de dos n'a pas été localisée.

## 6. Écarts d'implémentation repérés au passage (lecture de `src/`, pour information)

- **graphics** : notre table s'arrête à −636 (106 vecteurs) alors que la V34 en a **109** :
  `graphicsPrivate1/2` (−642, −648) et **`AttemptLockLayerRom` (−654)** sont **hors table** — un appel
  au LVO −654 aboutit hors de notre jump table. `BltMaskBitMapRastPort` (−636, utilisé par le Workbench
  pour les icônes, cf. wb-icon-clipping §3), `ScrollVPort`, `ClipBlit`, `Flood`, tout le remplissage
  (`AreaMove/Draw/End`, `InitArea`, `InitTmpRas`), `InitView`, `InitVPort`, `GetColorMap`,
  `FreeColorMap`, `FreeCprList`, `QBlit`, `QBSBlit`, `BltPattern`, `WaitBOVP`, `SyncSBitMap`,
  `CopySBitMap` sont des vecteurs nuls (24 au total).
- **intuition** : vecteurs nuls pour `SetPointer`, `ClearPointer`, `DisplayAlert`, `CloseWorkBench`,
  `MoveScreen`, `CurrentTime`, `MakeScreen`, `WBenchToBack/Front`, `LockIBase/UnlockIBase`,
  `AlohaWorkbench`, `ActivateWindow`, `RefreshWindowFrame` (ces deux derniers sont pourtant spécifiés).
- **exec** : `ExitIntr`, `Schedule`, `Reschedule`, `Switch`, `Dispatch`, `Exception`, `Debug`,
  `Procure`, `Vacate`, `SumKickData` sont nuls ; `RawIOInit` est un stub ; `Alert` n'affiche rien
  (message série), et le résident `alert.hook` n'existe pas.
- **gameport.device** : BeginIO renvoie IOERR_NOCMD pour **toutes** les commandes (la souris passe par
  un poller interne). **input.device** : `IND_SETMPORT/SETMTYPE/SETMTRIG` refusées.
- **console.device** : seules CMD_READ/CMD_WRITE ; les quatre commandes de keymap et `CDInputHandler`
  sont absentes. **keymap.resource** expose deux vecteurs qui n'existent pas en V34 (sans conséquence
  connue, mais la base n'a pas la même forme).
- **layers** : `ScrollLayer`, `FattenLayerInfo`, `ThinLayerInfo` sont des stubs.
- **dos** : `Exit` et `GetPacket/QueuePacket` nuls, `WaitForChar` stub (rend 0).
- **cia.resource** : `SetICR` est un stub (rend 0).
- **trackdisk** : `TD_SEEK`, `TD_REMOVE`, `TD_ADDCHANGEINT`, `TD_REMCHANGEINT` sont des no-op ;
  `TD_RAWREAD`, `TD_RAWWRITE`, `TD_GETDRIVETYPE` sont refusées.

## 7. Les 15 prochaines specs d'analyse à écrire (par priorité)

Hors périmètre, déjà confiés à d'autres agents : écriture trackdisk (CMD_WRITE/UPDATE/FORMAT/RAWWRITE)
et coldstart matériel (reset, détection mémoire/CPU, overlay). Les risques « vrai A500 » ci-dessous sont
ceux qu'un émulateur tolérant masque.

1. **graphics — blitter et copies** : `BltBitMap`, `BltTemplate`, `BltClear`, `BltPattern`, `ClipBlit`,
   `BltBitMapRastPort`, `BltMaskBitMapRastPort`, `OwnBlitter/DisownBlitter`, `WaitBlit`, `QBlit`,
   `QBSBlit` (≈ 1,7–4,7 Ko de clôture chacune ; 6 absentes chez nous). *Pourquoi* : tout le dessin du
   Workbench (icônes masquées, tiroirs), requesters PREDRAWN, FastFonts, OctaMED (BltBitMapRastPort
   640×200), jeux « propres ». *Risque A500* : élevé — sur Agnus réel le bit BBUSY n'est pas fiable
   immédiatement après l'écriture de BLTSIZE (défaut documenté, WaitBlit doit en tenir compte), ordre ascendant/descendant
   pour les recouvrements, mode « nasty » qui affame le 68000, données obligatoirement en chip RAM.
2. **graphics — construction de l'affichage et serveur VBlank** : `InitView`, `InitVPort`, `GetColorMap`,
   `FreeColorMap`, `MakeVPort`, `MrgCop`, `LoadView`, `FreeVPortCopLists`, `FreeCprList`, `ScrollVPort`,
   `VBeamPos`, `WaitTOF`, `WaitBOVP`, `gb_copinit`, trames LOF/SHF (MakeVPort ≈ 3,7 Ko, MrgCop ≈ 1,5 Ko,
   ScrollVPort ≈ 3,4 Ko). *Pourquoi* : chaque écran intuition ; les jeux et démos qui bâtissent leur propre
   View (Caesar via RemakeDisplay, Monkey Island via UCopIns) ; défilement matériel par ScrollVPort.
   *Risque A500* : élevé — Agnus PAL ou NTSC (DIWSTRT/DDFSTRT, 50/60 Hz), entrelacé (alternance des
   listes LOF/SHF au VBlank), limites de fetch OCS, positions WAIT exactes.
3. **exec `Alert` + `alert.hook` + intuition `DisplayAlert`** (Alert ≈ 1,8 Ko de clôture, alert.hook
   658 o, DisplayAlert ≈ 2,3 Ko). *Pourquoi* : repli d'AutoRequest (intuition-requesters §5.3),
   Preferences et Monkey Island sur échec d'allocation, alertes de la ROM elle-même (pile, mémoire),
   SetPatch remplace Alert en 1.3. Chez nous : rien n'est affiché. *Risque A500* : élevé — l'alerte
   pilote le matériel directement (sa propre copper list, attente des boutons via CIA/POTGO, redémarrage
   sur alerte sans issue) ; c'est aussi le seul diagnostic visible si la RAM d'un vrai A500 est défaillante.
4. **intuition — écrans et Workbench** : `OpenScreen`, `CloseScreen`, `MoveScreen`, `ScreenToBack/Front`,
   `MakeScreen`, `RethinkDisplay`, `RemakeDisplay`, `CloseWorkBench`, `OpenWorkBench`, `WBenchToBack/Front`,
   `ShowTitle`, `GetScreenData`, `LockIBase/UnlockIBase` (OpenScreen ≈ 10 Ko, CloseWorkBench ≈ 12 Ko de
   clôture ; 6 absentes chez nous). *Pourquoi* : Monkey Island (CloseWorkBench), Preferences (MoveScreen),
   SysInfo (écran custom, ScreenToFront), OctaMED, tirage de la barre d'écran par l'utilisateur.
   *Risque A500* : moyen — affichage entrelacé et écrans glissés exigent des copper lists justes.
5. **intuition — moteur d'entrées, menus et gadgets** : `Intuition()` (−36, ≈ 28 Ko de clôture : le cœur
   d'intuition), `SetMenuStrip`, `ClearMenuStrip`, `ItemAddress`, `OnMenu/OffMenu`, `OnGadget/OffGadget`,
   `ActivateGadget` (gadgets chaîne : édition, UNDO, LONGINT), `ReportMouse`, `ModifyIDCMP`, contenu exact
   des messages IDCMP de chaque classe, `CurrentTime`, `BeginRefresh/EndRefresh`, `WindowLimits`,
   `SizeWindow`, `MoveWindow`, `WindowToFront/Back`. *Pourquoi* : menus du Workbench, Rename/Info
   (gadgets chaîne), OctaMED (ActivateGadget ×11, RefreshGList ×27), Preferences ; les clics « sans
   effet » observés viennent de ce moteur. *Risque A500* : faible en soi (logique), mais c'est la plus grosse
   zone non spécifiée de la ROM.
6. **layers — opérations de pile, types de rafraîchissement, SuperBitMap** : `CreateUpfront/BehindLayer`,
   `UpfrontLayer`, `BehindLayer`, `MoveLayer`, `SizeLayer`, `DeleteLayer`, `MoveLayerInFrontOf`,
   `ScrollLayer`, `SwapBitsRastPortClipRect`, `NewLayerInfo/DisposeLayerInfo/InitLayers`,
   `Fatten/ThinLayerInfo`, `WhichLayer`, plus graphics `SyncSBitMap/CopySBitMap` (CreateUpfrontLayer et
   MoveLayer ≈ 10–11 Ko de clôture). *Pourquoi* : chaque fenêtre ; SIMPLE vs SMART vs SUPER_BITMAP
   (fenêtres SuperBitMap de logiciels de dessin et de tableurs), dommages et BackFill. *Risque A500* :
   moyen — tout passe par le blitter réel (cf. 1) et par la chip RAM des ClipRects sauvegardés.
7. **graphics — remplissages et ellipses** : `AreaMove`, `AreaDraw`, `AreaEnd`, `InitArea`, `InitTmpRas`,
   `Flood`, `DrawEllipse`, `AreaEllipse`, `BltPattern` et les champs RastPort associés (AreaPtrn, AOlPen,
   TmpRas) (AreaEnd ≈ 3 Ko, Flood ≈ 8,7 Ko de clôture ; **toutes absentes chez nous**). *Pourquoi* : le
   Workbench 1.3 appelle `Flood` (workbench-task §3.6), outils de dessin, démos et jeux en polygones
   pleins. *Risque A500* : moyen — le remplissage passe par le blitter en
   mode « fill » et une TmpRas en chip RAM.
8. **console.device complet + keymap.resource** : séquences ESC/CSI (curseur, effacements, styles, SGR,
   défilement, rapport de position/taille), CMD_READ (traduction RAWKEY → chaînes, touches mortes,
   qualificatifs), `CD_ASKKEYMAP/SETKEYMAP/ASKDEFAULTKEYMAP/SETDEFAULTKEYMAP`, `CDInputHandler`,
   `RawKeyConvert`, contenu de la KeyMapResource (≈ 5,5 Ko de clôture ; rien de spécifié).
   *Pourquoi* : CLI/Shell, Ed, More, NewCLI ; **`SetMap`** de la startup-sequence pour tout clavier non-US
   (l'utilisateur est en AZERTY) passe par CD_SETDEFAULTKEYMAP [D, d'après l'usage documenté de
   SetMap, à confirmer sur le WB 1.3.3] ; Monkey Island attend RawKeyConvert(RETURN)
   = `$0D`. *Risque A500* : moyen — un clavier réel non-US produit des rawkeys que seule la keymap traduit.
9. **gameport.device + réglages souris d'input.device + potgo.resource** : `GPD_READEVENT`,
   `GPD_ASK/SETCTYPE`, `GPD_ASK/SETTRIGGER`, `IND_SETMPORT/SETMTYPE/SETMTRIG`, `AllocPotBits`,
   `FreePotBits`, `WritePotgo` (≈ 1,3 Ko + 0,8 Ko ; gameport refuse tout chez nous). *Pourquoi* : sur la
   vraie 1.3, input.device lit la souris **via** gameport.device (intuiticks-repeat §1.1) ; programmes
   qui lisent le joystick par gameport (jeux « propres », tests de manette) ; bouton droit/milieu par POTGO.
   *Risque A500* : élevé — compteurs de quadrature réels (rebond, débordement), lignes POTGO à
   piloter en sortie/entrée pour le bouton droit, souris et joystick réels sur les ports 0/1.
10. **keyboard.device complet** : `KBD_READEVENT` (files, débordement), `KBD_READMATRIX`,
    `KBD_ADD/REMRESETHANDLER`, `KBD_RESETHANDLERDONE`, codes spéciaux ($78 avertissement de reset,
    $F9–$FE), LED Caps Lock, **valeur** de la durée d'impulsion de poignée de main (keyboard-handshake §4 ne
    la donne qu'en [D]). *Pourquoi* : tout le clavier ; Ctrl-Amiga-Amiga et les handlers de reset
    (disques RAM, programmes résidents). *Risque A500* : **élevé** — un vrai clavier exige une impulsion
    KDAT d'au moins ~75–85 µs (Hardware Reference Manual) et resynchronise sinon (perte de touches), envoie une séquence d'initialisation
    à la mise sous tension et un avertissement suivi d'un délai avant de tirer le reset.
11. **exec — interruptions, logiciel d'ordonnancement privé, exceptions** : `ExitIntr`, `Schedule`,
    `Reschedule`, `Switch`, `Dispatch`, `Exception` (nuls chez nous), `Cause` (priorités des SoftInts),
    `SetIntVector`, `AddIntServer/RemIntServer` (sémantique de la chaîne : retour Z, is_Data, réglage
    d'INTENA), `Supervisor`, `SetSR`, `SuperState/UserState`, `GetCC`, `SetExcept`, `AllocTrap/FreeTrap`,
    `Debug`, `RawIOInit/RawMayGetChar/RawPutChar` (Switch ≈ 312 o, ExitIntr ≈ 160 o, Exception ≈ 108 o).
    *Pourquoi* : vieux codes 1.x qui sautent dans ExitIntr ou Switch, débogueurs (Wack/Debug), gestion
    des exceptions de tâche (CTRL-C asynchrone), serveurs VBlank de jeux et démos. *Risque A500* : élevé
    — latence et niveaux IPL réels (clavier, série, disque), carte accélératrice 68010 (format de pile
    d'exception différent ; détection CPU elle-même = agent coldstart).
12. **audio.device** : allocation (clés, priorités, vol de canaux, ADCMD_ALLOCATE/FREE/SETPREC/LOCK),
    CMD_WRITE (cycles, période, volume, ADIOF_PERVOL/SYNCCYCLE/WRITEMESSAGE), ADCMD_PERVOL/FINISH/WAITCYCLE,
    CMD_READ, interruptions AUDx (≈ 2,5 Ko). *Pourquoi* : OctaMED (allocation des 4 canaux), lecteurs de
    musique, jeux, `Say`/narrator. *Risque A500* : moyen — période minimale réelle (124), données en chip
    RAM, interruptions de niveau 4, filtre audio lié à la LED.
13. **graphics — sprites et GELs** : `GetSprite`, `FreeSprite`, `ChangeSprite`, `MoveSprite`, SprIns ;
    `InitGels`, `AddBob/AddVSprite`, `RemIBob/RemVSprite`, `SortGList`, `DrawGList`, `DoCollision`,
    `SetCollision`, `AddAnimOb`, `Animate`, `InitMasks/InitGMasks`, `GetGBuffers/FreeGBuffers`
    (DrawGList ≈ 6,5 Ko, DoCollision ≈ 1,8 Ko). *Pourquoi* : glisser d'icônes du Workbench (Bobs),
    OctaMED (6 sprites matériels), jeux. *Risque A500* : moyen — sprites coupés par un fetch de plans trop
    précoce (overscan), DMA sprite et réutilisation verticale.
14. **exec — mémoire et survie au reset** : `Allocate`, `Deallocate`, `AllocAbs`, `AllocEntry`,
    `FreeEntry`, `TypeOfMem`, `AddMemList`, `CopyMem`, `CopyMemQuick`, `SumKickData` (nul chez nous),
    `Procure/Vacate`, sémaphores (`AttemptSemaphore`, `ObtainSemaphoreList`…), et contrat de
    `KickMemPtr/KickTagPtr/KickCheckSum`, `ColdCapture/CoolCapture/WarmCapture` au reset à chaud.
    *Pourquoi* : programmes résidents au reset (RAD:, tueurs de virus qui inspectent KickTagPtr et les
    vecteurs de capture), SetPatch 1.38 (AllocEntry), ramlib. *Risque A500* : moyen — sur matériel réel la
    RAM survit à Ctrl-Amiga-Amiga : ExecBase et les listes résidentes doivent être revalidées
    (coordination nécessaire avec l'agent coldstart).
15. **ressources matérielles : disk.resource, misc.resource, cia.resource** : `AllocUnit`, `FreeUnit`,
    `GetUnitID` (identification DF1–DF3), `AllocMiscResource/FreeMiscResource` (port série, bits série,
    port parallèle, bits parallèles), `RemICRVector`, `AbleICR`, `SetICR` (stub chez nous) (≈ 70–250 o
    chacune). *Pourquoi* : identification des lecteurs présents [D : appelant exact à confirmer], `serial.device` et `parallel.device`
    de DEVS: (terminal, imprimante), trackdisk et le clavier pour l'ICR. *Risque A500* : **élevé** — un
    lecteur externe réel se détecte par décalage de son identifiant sur les lignes SEL, et un câble série
    branché pour le débogage entre en conflit avec serial.device si l'allocation n'est pas respectée.

### Suivants (16+)

16. graphics — texte et polices (`Text` ≈ 1,3 Ko, `OpenFont`, `AddFont/RemFont/AskFont`, styles
    algorithmiques `SetSoftStyle`, `ClearEOL/ClearScreen`) : partiellement couvert par fastfonts-ff.
17. ramlib.library : chargement par un **process** dédié (chez nous l'appelant doit être un process),
    expunge en mémoire basse.
18. mathffp.library (12 fonctions, ≈ 1 Ko) : format FFP, cas limites, codes condition (programmes
    compilés en flottant FFP, AmigaBASIC).
19. trackdisk : `TD_RAWREAD`, `TD_GETDRIVETYPE`, `TD_ADDCHANGEINT/REMCHANGEINT`, `TD_REMOVE` (à
    coordonner avec l'agent écriture).
20. dos : `Exit`, `WaitForChar` (contrats déjà esquissés dans bcpl-runtime §4.3/§8.2 : lacune
    d'implémentation plus que d'analyse).

## Relecture clean-room

- Ce fichier ne contient aucune suite d'instructions de la ROM, aucun listing et aucune adresse de
  routine : uniquement des noms et LVO publics (`.fd`), des numéros de commande d'ABI, des comptes
  d'entrées de tables et des tailles en octets mesurées.
- Les mentions de `src/` décrivent l'état de NOTRE implémentation (lecture autorisée pour cet
  inventaire) ; aucune information ROM n'y est réinjectée sous forme de code.
- Les valeurs de matériel citées comme risques (impulsion clavier, période audio minimale, BBUSY) sont des
  faits publics de la documentation matérielle Amiga, pas des mesures de la ROM.
