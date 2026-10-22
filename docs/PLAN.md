# Plan — Réimplémentation open-source clean-room d'un Kickstart 1.3 (Amiga 500)

## Context

Objectif : produire un **Kickstart open-source compatible 1.3 strict** — image ROM de **256 KiB
chargée à `$FC0000`**, 68000 big-endian, drop-in de la vraie `kick34005.A500`, bootant **d'abord en
émulateur (FS-UAE/WinUAE), puis sur vraie Amiga 500** (EPROM/adaptateur).

ROM d'origine identifiée : 262 144 octets, MD5 `82a21c1890cae844b3df741f2762d48d`, SHA1
`891e9a547772fe0c6c19b610baf8bc4ea7fcb785`, en-tête `JMP $00FC00D2`, ROM-ID `0x1111`. Scan structurel :
**24 ROMTags** valides (carte des modules ci-dessous).

**Pourquoi ce plan a cette forme** — trois contraintes dictent tout :

1. **« Salle blanche » = un mur, pas une personne.** Désassembler la ROM *et* en écrire le
   remplacement dans le même flux produit une œuvre dérivée (l'inverse du clean-room). Le mur sépare
   deux pistes étanches (analyse ↔ implémentation), via des rôles d'agents distincts. L'implémentation
   ne voit **jamais** le désassemblage — seulement des **specs comportementales** (le *quoi*, jamais le
   *comment* transcrit) + les docs publiques.
2. **AROS ne convient pas comme base.** AROS m68k vise l'API **3.1** (ROM ~512 K scindée @ `$F80000`,
   licence **APL v1.1** copyleft par fichier, non-OSI, incompatible GPL) et **exige ≥ 68040** — ni le
   bon niveau d'API, ni la bonne taille/adresse, ni bootable sur un 68000. Il reste une **référence de
   lecture** (algorithmes, structures) ; on **ne copie pas** son code dans `src/` (cf. Licence).
3. **Le 68000 est notre cible par conception.** Puisqu'on réimplémente la 1.3 from-scratch, la vraie
   A500 (68000) reste atteignable pour *nous* — c'est AROS qui ne le peut pas.

**Magnitude (à assumer).** Un KS 1.3 complet = ~24 modules interdépendants (dont `dos.library` en
BCPL) et **aucun art antérieur open-source/clean-room ciblant 1.x** n'existe (projet inédit). La parité
intégrale est un chantier à horizon long. **Ce plan livre : fondations exécutables, discipline
clean-room, banc de test, et une échelle de milestones qui boote de façon incrémentale** — pas une
promesse de parité totale rapide. Priorité au **code qui tourne** avant toute planification exhaustive.

## Carte des modules résidents (source : scan ROMTag ; fait d'ABI documentable, côté analyse)

Ordre d'init = priorité décroissante.

| Pri | Module | Ver | | Pri | Module | Ver |
|----:|--------|-----|-|----:|--------|-----|
| 120 | exec.library | 34.2 | | 50 | timer.device | 34.1 |
| 110 | expansion.library | 34.1 | | 40 | audio.device / input.device | 34.1 |
| 100 | potgo.resource / keymap.resource | 34.1 | | 31 | layers.library | 34.1 |
| 80 | cia.resource | 34.1 | | 20 | console.device / trackdisk.device | 34.1 |
| 70 | disk.resource / misc.resource / ramlib.library | 34.1 | | 10 | intuition.library | 34.3 |
| 65 | graphics.library | 34.1 | | 5 | alert.hook | 34.0 |
| 60 | keyboard.device / gameport.device | 34.1 | | 0 | mathffp.library / workbench.task / **dos.library** (BCPL) | 34.1/34.3 |
| | | | | -40 | romboot.library | 34.1 |
| | | | | -60 | strap | 34.4 |

## Discipline clean-room (le cœur du plan)

Deux pistes, deux rôles d'agents, un mur :

- **Piste ANALYSE (« dirty »)** — accès : ROM + `radare2` (Ghidra headless optionnel pour le
  décompilateur). Produit UNIQUEMENT `docs/analysis/*.md` (séquence de boot, ordre d'init, layout des
  structures = ABI, constantes d'ABI) + des **vecteurs de test** (entrée→sortie observable = oracle).
  Interdit : écrire dans `src/` ; transcrire des suites d'instructions dans un artefact nourrissant
  l'implémentation.
- **Piste IMPLÉMENTATION (« clean »)** — accès : docs publiques (RKRM/AutoDocs/NDK/`.fd`), source AROS
  (lecture seule), et les **specs comportementales + vecteurs de test** de l'analyse. Interdit : lire la
  ROM ou son désassemblage. Produit : `src/`.
- **Règle de spec** : décrire comportement et layout d'ABI (public), jamais une suite d'instructions
  recopiée. Les `.fd`/AutoDocs/RKRM définissent déjà l'API (LVO, signatures) → l'implémentation s'y
  appuie en priorité ; la ROM ne sert qu'à lever des ambiguïtés *comportementales*.
- **Porte de revue de spec** : avant que la piste impl ne consomme une spec, une relecture confirme
  qu'elle ne contient **aucune suite d'instructions transcrite** — c'est ce contrôle qui donne au mur
  sa valeur réelle.
- **Honnêteté** : deux rôles d'agents dans une même session *approximent* le mur sans valoir une
  séparation de personnes « niveau tribunal ». Posture maximale réaliste ici ; pour du juridique dur,
  faire faire analyse et implémentation par des personnes différentes.

## Licence

- **AROS** sous **APL v1.1** (copyleft par fichier, dérivée MPL-1.1, non-OSI/FSF, incompatible GPL) →
  tout fichier AROS *modifié* resterait sous APL. Sous firewall strict on **lit** AROS (comprendre les
  algorithmes), on **ne copie pas** ses sources dans `src/` → notre licence reste libre.
- **Docs** (NDK 3.2, RKRM/AutoDocs) : licences propriétaires, **consommées** pour apprendre l'ABI/le
  comportement, **jamais redistribuées/vendorées** dans le dépôt.
- **Notre licence** : permissive (type MIT/BSD/zlib) recommandée, ou décision différée ; choix à acter
  avant première publication publique (non bloquant pour M0/M1).

## Structure du dépôt (règles project-structure)

```
amiga_kickstart_reverse/
  CLAUDE.md  README.md  .claude/
  src/            # piste CLEAN : exec/ libs/ devices/ resources/ rom/ (linker script, reset/header)
  docs/           # analysis/ (piste DIRTY: specs + vecteurs oracle) · ARCHITECTURE.md CLEANROOM.md HARDWARE.md PLAN.md
  tests/          # harness émulateur + unités vamos + diffs oracle
  assets/         # ROM d'origine (copie lecture seule) + ADF de test
  build/          # artefacts (gitignore) : *.rom *.elf
  third_party/    # AROS (référence lecture seule) ; PAS de NDK/RKRM vendorés
```
La `kick34005.A500` est **copiée** dans `assets/` (jamais modifiée), lisible seulement par la piste
analyse et le banc oracle.

## Toolchain & banc de test

**Présent localement** : `radare2` 6.1.3 (m68k via `-a m68k`), **amitools** CLI complet (`romtool`,
`vamos`, `fdtool`, `xdftool`, `hunktool`, `rdbtool`), `python3`, `git`, `make`, `cmake`.

**À installer** :
- **vasm (`vasmm68k_mot`) + vbcc + vlink** (Frank Wille, `sun.hasenbraten.de`) — standard de fait.
  `vlink` : sorties `rawbin`/`ados`, **option `-kick1`** (compat loader Kickstart 1.x), linker scripts
  (SECTIONS/MEMORY) pour placer le code à `$FC0000`. Alternative C : gcc **bebbo** (`codeberg.org/bebbo/amiga-gcc`),
  runtime KS1.3 via **`-mcrt=nix13`**.
- **Émulateur** : **FS-UAE** natif Linux + **Xvfb** (primaire CI, piloté par fichier de config,
  `kickstart_file = <chemin>`) ; **`WinUAE.exe`** via interop Windows WSL2 (`-f cfg.uae -s use_gui=no`,
  `kickstart_rom_file=`) en secondaire (Wine 64-bit cassé → ne pas l'utiliser).

**Rôle amitools** :
- `romtool build -t kick -s 256 -a fc0000 -o build/kick13.rom <modules>` puis `romtool copy -c`
  (fix checksum, offset 0x3FFE8) ; `romtool info`/`scan` pour valider header/tags/taille et diffier
  l'original (oracle). (Checksum non vérifié par l'OS avant V37, mais les outils l'attendent.)
- `fdtool` : extraire les LVO depuis les `.fd` → table de sauts / offsets d'ABI.
- `vamos` : exécuter des **binaires de test AmigaOS** sur l'hôte contre un env connu et recouper la
  sémantique d'API *documentée* — il fournit son propre exec/dos, il n'héberge donc PAS notre code.
- `xdftool` : fabriquer des ADF de test pour les milestones de boot disquette.

**En-tête/reset (facts pour le code maison)** : au power-on l'overlay mappe la ROM à `$000000` → le
68000 lit **SSP initial au longword `$0`** et **PC initial au longword `$4`**. Convention des 8 premiers
octets : **mot ROM-ID (`0x1111`) + `4EF9` (JMP) + adresse de coldstart** (notre dump : `JMP $00FC00D2`).

## Échelle de milestones (boote de façon incrémentale)

- **M0 — Fondations + hello-ROM (premier code qui tourne).** Scaffolding dépôt + toolchain + harness.
  Image 256K : vecteur reset `$0`/`$4`, en-tête ROM-ID+`JMP`, code écrivant `$DFF180` (couleur de fond)
  → signal « ça tourne » en émulateur. Prouve la chaîne vasm→vlink(`-kick1`)→`romtool`→émulateur.
  **Dès M0, monter la capture du log série (registre `SERDAT`) comme canal d'assertion primaire**
  (déterministe/CI) ; le blink `$DFF180` n'est qu'un signal de vie. Banc oracle : vraie KS 1.3 en UAE
  pour **sondes comportementales ciblées → vecteurs de test** (jamais un diff système global).
- **M1 — Spec de boot (piste analyse).** Cold-start → `InitCode` exec → scan résident (ordre du tableau)
  → strap. Spec `exec` : layout `ExecBase`, table LVO (offsets négatifs via `.fd`), comportements des
  primitives. Livrables : `docs/analysis/{boot-sequence,exec-spec,module-map}.md` + vecteurs oracle.
  ⚠️ **Les docs publiques en ligne sont 2.0+/3.x** (RKRM 2.0/3.5, NDK 3.2) ; la 1.3 (V34) a un ABI plus
  petit/différent (moins de LVO, structs/comportements distincts). Il faut des références **1.x** (RKRM
  1re édition + `.fd` 1.x, jeux de LVO tronqués) ; et **partout où la doc 1.3 publique est mince, c'est
  la piste analyse qui capture le delta comportemental V34↔doc-2.0 dans la spec** — la piste impl ne
  pouvant pas lire la ROM pour le découvrir, sans quoi le mur fuit.
- **M2 — exec.library (impl).** Cold start, `ExecBase`, mémoire (détection, `AllocMem`/`FreeMem`,
  memory list), listes, libs/devices (`MakeLibrary`/`OpenLibrary`/`SetFunction`, jump tables),
  tâches/scheduler, signaux, ports/messages, interruptions/traps, `InitResident` + scan auto-config
  data-driven. Vérif : exec vit jusqu'au scan résident **en machine complète (UAE)** — c'est là que se
  valide le bringup d'exec ; `vamos` fournit SON propre exec/dos et **ne peut pas héberger le nôtre**.
  Assertions via log série ; sondes oracle là où observable.
  **État (suivi fin dans le ledger + README)** : coldstart/ExecBase/jump table V34/mémoire multi-header/
  listes/tâches+signaux+ports non bloquants = livrés (sous-jalons M2.0→M2.4). Plomberie d'interruptions
  VBlank (M3a), **ordonnanceur préemptif superviseur** (M3b), **exclusion mutuelle** — `Forbid()`
  honoré + sections critiques exec enveloppées (M3c), **`Wait`/`WaitPort` + réveil-sur-signal** —
  blocage réel d'une tâche via switch synchrone (M3d) et **yield immédiat sur `Permit`/`Enable`** —
  reschedule synchrone vers une réveillée prioritaire (M3e, prouvé en coopératif), **recombinaison
  yield + préemption** — les deux chemins de switch unifiés coexistent sans corruption (M3f) et
  **machinerie de scan des résidents** — `build_reslist`/`FindResident`/`InitResident`/`InitCode`
  prouvés par 3 résidents démo initialisés en ordre de priorité (M4) = livrés et vérifiés par boot
  FS-UAE, ainsi que **AUTOINIT** — `MakeLibrary`/`MakeFunctions`/`InitStruct` + chemin AUTOINIT de
  `InitResident`, prouvés par un résident AUTOINIT démo (M5a), ainsi que **`cia.resource`** — 1er vrai
  module résident (ciaa/ciab, direct-init via MakeLibrary, `AddResource`/`OpenResource`, M5b) et
  **`timer.device`** (AUTOINIT, 2e vrai résident / 1er device, M5c). L'OS instancie donc désormais de
  VRAIS modules résidents — mais `cia.resource`/`timer.device` sont encore des **squelettes** (nommés,
  créés, listés ; aucun travail fonctionnel : cia sans dispatch d'interruption, timer sans unités/BeginIO).
  Le 1er chemin FONCTIONNEL est livré : unité **VBLANK** de timer pilotée par le handler VBlank
  existant (file de requêtes, décrément au VBlank, reply bas-niveau à l'expiration, M6a) = 1er
  comportement OS observable (timer+interruption+messages+`exec_Signal` depuis l'IRQ). La **dispatch
  d'interruption CIA** (INT2/CIA-A : les vecteurs ICR enregistrés se déclenchent, prouvé bout-en-bout
  par un timer CIA, M6b) est aussi livrée. **M7a** : le vrai gate qui bloquait la coexistence CIA +
  préemption n'était PAS la pile (dans le modèle tâches-superviseur-même-pile les frames d'interruption
  se dépilent correctement ; la corruption de pile par SSP partagée reste **latente** jusqu'au user-mode)
  mais la **ré-entrance des listes du scheduler** : `vbl_handler` faisait son `Enqueue`/`RemHead`
  TaskReady à IPL3, préemptable par INT6 (niveau 6) dont l'`exec_Signal` touche la même liste. Fermé en
  montant IPL7 autour de la seule section critique (+ `timer_reply` AddTail IPL7). Livré avec l'**unité
  MICROHZ** (CIA-B/INT6) et une **tâche qui bloque sur un timer** (Wait→wake), prouvé par un détecteur
  structurel `VBL_CLASH==0` (RED : gate retiré → clash) + yield re-prouvé en coopératif. **M7b** livre le
  **dispatcher d'interruption par numéro** : `IntVects`/`SetIntVector` (vecteur exclusif)/`AddIntServer`
  (chaîne de serveurs par priorité, marchée par `intr_chain_walker`) ; les autovecteurs CIA hardcodés sont
  remplacés par `int2_dispatch`/`int6_dispatch` génériques et cia.resource devient un SERVEUR PORTS/EXTER
  (comme le vrai exec). **M7c** fait passer les tâches en **user-mode** (SR S=0, pile user par tâche) sur une
  **SSP partagée** et remplace le swap de `sp` par un **switch DIFFÉRÉ à relocalisation de frame** (`dispatch`
  relocalise SSP↔pile user, nesting par-tâche, INTENA synchronisé ; switch volontaire via `trap`) — c'est là
  que le hazard de SSP partagée devient réel et que le nest-count (bit S de la SR sauvée) devient load-bearing.
  Dérivé du spec public « Exec Microkernel » (AROS) + manuel 68000 (zéro code transcrit). Un **flag de dispatch
  différé** à la sortie d'IRQ réveille promptement une tâche prioritaire signalée depuis une interruption.
  **M7d** rend les ports INTERRUPT-SAFE : `PutMsg`/`GetMsg`/`ReplyMsg` passent de Forbid (tâche-vs-tâche) à
  Disable (masque aussi les interruptions), prouvé par un port partagé martelé par une TÂCHE et une INTERRUPTION
  (coexistence GREEN + A/B sous contention max : Forbid corrompt la liste, Disable non). Débloque l'I/O device
  piloté par IRQ. **M7e** livre la **fidélité IPL-par-niveau** : les handlers tournent à leur IPL natif (VBlank=3,
  PORTS=2, EXTER=6) au lieu d'IPL7 uniforme — une source de niveau supérieur préempte le CORPS d'un handler
  inférieur (INT6 préempte le corps de vbl, `VBL_PREEMPT_COUNT>0`). La section critique du switch est masquée par
  IPL7 bref (SR = instantané) et NON par INTENA-off : découverte empirique que l'écriture INTENA a un délai de
  propagation (course observée en RED1) ; le choix IPL-vs-INTENA est imposé par le privilège (le switch tourne
  superviseur ; Signal/ports/Wait sont user-mode et ne peuvent pas monter l'IPL -> gardent INTENA-Disable + son
  caveat write-delay, toléré/bénin). Prouvé GREEN 3/3 + RED1 3/3 (clash) + RED2 2/2 (M7E absent) + coopératif.
  **M7f** livre **VERTB EN CHAÎNE DE SERVEURS** : le `vbl_handler` dédié devient `int3_dispatch` générique
  (miroir int2/int6) -> `intr_dispatch_number(VERTB)` -> chaîne de serveurs par priorité (modèle UNIFORME
  PORTS/VERTB/EXTER). Le quantum round-robin devient `sched_server` (pose AttnResched, gardes Forbid/Disable
  conservées) ; `timer.device` passe de son hook `VBL_SVC` à `AddIntServer(VERTB, timer_vblank)`. Risque clé :
  le walker ne restaure pas `a6` après le dernier serveur -> `intr_isr_defer` recharge `a6`. Prouvé « M7F VERTB
  OK » (`VERTB_CHAIN_N` = parcours complet sched/timer/tail en ordre) + scheduler/timer OK via la chaîne, GREEN
  3/3 + RED (sched stoppe la chaîne en Z-clair -> « M6A FAILED » timer VBLANK mort) + coopératif. Découverte :
  retirer le seul quantum VBlank ne stoppe pas la préemption (INT6 co-pilote le round-robin via le dispatch différé).
  **M7g** livre le **décodage INTREQR multi-source** : int3_dispatch lit INTREQR & INTENAR et dispatche+acke
  CHAQUE source de niveau 3 en attente (COPER/VERTB/BLIT) via IntVects[n], au lieu de supposer VERTB seule
  (int2/int6 restent mono-source, correct). Prouvé « M7G MULTISRC OK » : une 2e source niveau 3 (COPER,
  déclenchée par logiciel INTREQ=SETCLR|COPER, sans graphics) est servie via le décodage ; GREEN 3/3 + RED
  (M7G_MONO_SOURCE=1 : décode+acke mais ne dispatche pas -> COPER_FIRED figé, pas de storm) + coopératif.
  **M7h** livre le **quantum réel** : sched_server préempte après M7H_QUANTUM ticks (défaut 4, comme exec)
  au lieu de chaque tick ; QUANTUM_ELAPSED reset sur changement réel de tâche. Priorité stricte déjà
  correcte (RemHead/Enqueue par pri) -> quantum seul. Observable SEULEMENT en isolation (M7H_QUANTUM_DEMO :
  2 spinners pri 0) : en démo normale INT6 reset ELAPSED ~140/s -> quasi-no-op (non-rég M3F..M7G OK, le
  quantum n'est pas load-bearing pour la rotation que pilote INT6). Prouvé « M7H QUANTUM OK »
  (QUANTUM_EXPIRE_N*2<VBL_COUNT) GREEN-iso 2/2 + RED-iso (QUANTUM=1 -> chaque tick) 2/2 + non-rég + coop.
  **M7i** convertit `timer_reply`→`ReplyMsg` : la routine bespoke (créée en M7c pour éviter le Permit/yield
  de ReplyMsg en interruption) est supprimée ; M7d ayant rendu ReplyMsg interrupt-safe (Disable/raw_enable,
  sans yield), les services VBLANK/MICROHZ appellent directement ReplyMsg. Prouvé par ÉQUIVALENCE (jeu de
  marqueurs identique à M7h défaut, GREEN 3/3 + coop) ; justification inversée corrigée partout.
  **M7j** livre `RemTask` (cycle de vie) : retrait d'une tâche + FreeMem pile/TCB. Self-removal (tâche qui
  se termine via task_exit) = trap #2 -> superviseur (sur la SSP, la pile user est libérable) -> FreeMem
  (Forbid externe neutralise le yield du Permit interne) -> bascule (dispatch_in). Non-self = Remove +
  FreeMem en contexte tâche. Prouvé « M7J REMTASK OK » (AvailMem remonte après l'auto-retrait de task_rm) :
  GREEN 2/2 + non-rég défaut 3/3 + coop ; RED M7J_NOFREE (FreeMem sauté -> fuite -> AvailMem ne remonte pas).
  Non-self par-inspection ; tc_MemEntry hors scope. CLÔT la séquence M7e..M7j pré-autorisée.
  **M7l** livre la **calibration µs réelle MICROHZ** : `timer_beginio` sépare la conversion par unité et
  compte l'unité MICROHZ en interruptions CIA-B via `US_PER_INT`=359 / `INTS_PER_SEC`=2782 (E-clock PAL
  709379 Hz, latch 255) au lieu du facteur VBLANK `/20000` -> `TV_MICRO` = µs réelles (résolution ~360 µs).
  Preuve INTER-HORLOGES : une requête de 0,5 s s'écoule en ~25 ticks VBLANK (horloge display indépendante) ;
  GREEN « M7L MICROHZ CALIB OK » 3/3 + RED `M7L_OLD_CONV` (requête trop rapide, M7L absent, chirurgical) 2/2
  + non-régression coop. **M7k REPORTÉ** (décision 2026-10-15) : le décodage INTREQR des niveaux INT1/INT4/INT5
  est de la plomberie sans consommateur réel (audio=M4+, disk=M6, serial plus tard) -> replié dans le
  sous-système concerné quand il arrivera, avec un vrai test. Reste : **M4 graphics** (ci-dessous), puis
  retrait éventuel des démos (le handoff de boot reste la démo M3f/M7a/M7c/M7d/M7e/M7f/M7g/M7j+M7l d'ici là).
- **M3 — resources & timing** : `cia.resource`, `timer.device`, `misc`/`potgo`/`disk.resource`,
  `keymap.resource` ; plomberie d'interruptions (VBlank déjà en place depuis le bringup exec).
- **M4 — graphics.library + affichage minimal** : Copper/Blitter/View suffisants pour afficher.
  Décomposition (user, 2026-10-15) : **M4a** fond de couleur piloté **Copper-only** (prouve le Copper DMA seul,
  sans bitplane) ; **M4b** pixels **bitplane** pilotés Copper (vrai premier affichage) ; **M4c** démarrer l'**ABI
  graphics.library** (GfxBase + View/ViewPort générant la copperlist ; décomposé : **M4c1** squelette résident
  [FAIT : `src/graphics/graphics_lib.s`, ROMTag AUTOINIT pri 65 → `MakeLibrary`/LibList, 1re branche NT_LIBRARY
  exercée, prouvé FindName+Open comme M5c ; RED `M4C1_WRONG_TYPE` route vers DeviceList → absent] → **M4c2**
  [FAIT : `MakeVPort`/`MrgCop`/`LoadView` (graphics_lib.s) génèrent la copper list depuis les structures
  BitMap/ViewPort/View/ColorMap, appelées via la jump table GfxBase ; le template copper M4a/M4b et ses gates
  M4A_NO_COPPER/M4B_NO_BITPLANE sont SUPPRIMÉS → preuve par ÉLIMINATION (rien d'autre ne dessine les rayures) ;
  RED `M4C2_NO_MRGCOP` → MrgCop ne fusionne pas → liste vide → écran blanc]). **M4 COMPLET.** **M4a + M4b FAITS** (`src/graphics/gfx.s`,
  copper list + bitplane en chip RAM — le Copper ET le bitplane DMA ne lisent QUE la chip, pas la ROM) : premier
  jalon où le canal **VISUEL** est load-bearing (l'écran EST le livrable).
  **M4a** = fond piloté Copper-only (COLOR00 = vert) ; écran VERT ⟺ Copper DMA actif ; RED `M4A_NO_COPPER` (pas de
  COPEN) → écran blanc. **M4b** = 1 bitplane 320×256 rempli de rayures verticales (`$FF00`) ; COLOR00 bleu / COLOR01
  vert → **rayures vertes** à l'écran ⟺ bitplane DMA actif ; RED `M4B_NO_BITPLANE` (BPU=0, pas de RASTER) → bleu uni.
  (M4a/M4b utilisaient un template copper codé en dur, gaté par `M4A_NO_COPPER`/`M4B_NO_BITPLANE` — **tout supprimé
  en M4c2**, l'affichage passe par l'ABI.) M4a a aussi corrigé un bug du discriminant couleur de `tests/boot_test.sh`
  (ordre `-opaque`/`+opaque` : le blanc préexistant faussait FRAC ; masqué car le défaut `EXPECT=FFFFFF` ne l'exposait pas).
- **M5 — intuition minimal.** Cadrage (décision user + advisor, 2026-10-16) : l'écran « insert Workbench disk »
  n'a **pas de vrai déclencheur avant M6** (il s'affiche quand le boot ne trouve aucun volume bootable =
  DOS/trackdisk), et `intuition.doc` confirme qu'il n'est **pas une fonction intuition** (seuls les événements
  IDCMP `DISKINSERTED` et les requesters DOS « Please insert volume XXX » le sont) → le dessiner maintenant en le
  forçant via intuition serait un artefact synthétique (même logique que **M7k reporté**). Le cœur M5 honnête et
  prouvable = le **squelette résident `intuition.library`** + une primitive 1re-gen réelle. **FAIT**
  (`src/intuition/intuition_lib.s`, `intuition.i`) : ROMTag AUTOINIT **pri 10** → `MakeLibrary`/`LibList` (branche
  NT_LIBRARY, comme M4c1) ; funcTable 49 vecteurs (Open/Close/Expunge + `ViewAddress` au vecteur 49 = LVO **-294**,
  LVO autoritatifs NDK) ; `IntuitionBase` posée (ViewLord embarqué, `INTUITIONBASE_SIZE`=80). Preuve série
  (marqueur **M5I**) : FindName + version 34 + type NT_LIBRARY + Open→OpenCnt==1 + **`ViewAddress()==IntuitionBase+34`**
  (= `&ib_ViewLord`). RED `M5I_BAD_VIEWADDR` → ViewAddress renvoie 0 → M5I absent (isole la primitive neuve ; le
  routage NT_LIBRARY→LibList est déjà RED-prouvé par `M4C1_WRONG_TYPE`). Non-régression : FRAC **0.299635 identique**
  GREEN/RED/COOP (le résident pri-10 décale le tas mais l'affichage M4 est intact). Différé : OpenScreen/OpenWindow/
  DisplayAlert, rendu de texte, écran insert-disk (→ M6).
- **`OpenLibrary` exec (consolidation M2) — FAIT.** `src/exec/library.s` : `OpenLibrary(libName,version)` (-552),
  `CloseLibrary` (-414), `OldOpenLibrary` (-408), patchés dans `build_jumptable`. Ouverture par nom = `Forbid` +
  `FindName(LibList)` + **gate de version** (`lib_Version >= version` demandée, sinon 0) + appel du vecteur Open/-6
  de la lib (OpenCnt++) ; `CloseLibrary` appelle le vecteur Close/-12. Preuve série **M5O** : OpenLibrary(intuition,34)
  == base & OpenCnt+1 ; version 99 → 0 (gate) ; lib inexistante → 0 ; CloseLibrary → OpenCnt-1. RED
  `OPENLIB_NO_VERCHECK` → gate sautée → version 99 ouvre à tort → M5O absent (isole la gate). FRAC 0.299635 identique
  GREEN/RED/COOP. Différé : chargement disque ramlib (M6, non-résidente → 0) ; delayed-expunge sur Close (résidentes
  → Close renvoie 0). Les preuves M4c1/M5 (FindName+Open à la main) sont candidates à refactorer sur `OpenLibrary`.
- **M6 — dos + trackdisk + FS + strap/romboot → boot disquette jusqu'au CLI.** La `dos.library` 1.3 est
  un portage **BCPL/TRIPOS** : il faut répliquer les quirks d'ABI (**BPTR** word-based, global vector,
  convention d'appel BCPL, **DOS packets**, segments `LoadSeg`). Approche retenue = **réécriture ANSI C
  en conservant `BPTR`/packets** (ce qu'ont fait AROS `rom/dos/` — à lire — et Commodore en 2.0).
  - **M6d — squelette dos.library résident + convention BPTR + DateStamp (FAIT, 1er incrément M6).** Cadrage
    (décision user + advisor, 2026-10-16) : playbook M4c1/M5I. ROMTag AUTOINIT pri 0 → `MakeLibrary` crée `DosBase`
    dans `LibList`. initfunc alloue `RootNode` et `DosInfo` **séparément via AllocMem** (⚠️ garde-fou advisor :
    `BPTR=addr>>2` n'est réversible que sur adresses long-alignées — NE PAS embarquer les structs dans `DosBase`
    comme ViewLord en M5I, sinon le round-trip perd des bits), câble `dl_Root` (APTR) et `rn_Info` (BPTR=&DosInfo>>2).
    `DateStamp`(-192, arg en d1) remplit (0,0,0) « horloge non réglée » (fidèle AutoDoc V34 : dl_TimeReq/battclock
    différés) et renvoie le pointeur. Déviation clean-room assumée : init C-style au lieu du glue BCPL d'origine.
    Preuve série **M6D** : FindName+version 34+NT_LIBRARY+Open→OpenCnt==1 + round-trip BPTR `rn_Info<<2==&DosInfo`
    (compute-then-compare via scaffold `DL_DISHADOW`, **sans déréférencer** le pointeur décodé → RED échoue en
    mismatch, pas en bus error) + DateStamp→(0,0,0)+ptr. RED `M6D_BAD_BPTR` (rn_Info en APTR brut) → M6D absent,
    tous les autres marqueurs présents (isolation chirurgicale). FRAC 0.299635 identique GREEN/RED/COOP. Rebuild
    byte-identique, checksum `0x929C804F`. Différé : packets/LoadSeg/handlers, Open/Read/Lock, strap/trackdisk/FS,
    écran insert-disk (image `assets/boot_screen/cat_amiga_kickslopstart.jpg` choisie, affichée à l'incrément strap
    quand le vrai déclencheur « aucun volume bootable » existera).
  - **M6s — écran de boot (image chaton « KickSlopStart »), 2e incrément M6 (FAIT).** Demande user : afficher son
    image au démarrage. Pipeline `src/graphics/mk_bootscreen.py` (Pillow, auto-vérifié : JPEG → 352×272 → quantize
    32 couleurs → 5 bitplanes planar, plan 0 = LSB, bit 7 = pixel gauche, palette RGB444 ; reconstruit + asserte) →
    `bootscreen.raw` + `bootscreen_data.s` (palette OCS + incbin) + PNG de référence. ABI : `gfx_MakeVPort` rendu
    GÉNÉRIQUE (N pointeurs de plan + `cm_Count` couleurs + BPL2MOD) ; `gfx_display_init` fait évoluer les rayures
    M4b → l'image (5 plans/32 couleurs copiés ROM→chip), affichée via MakeVPort/MrgCop/LoadView au handoff. Overscan
    352×272 (DIW/DDF élargis) pour remplir l'écran bord-à-bord (demande user : « n'occupe pas tout l'écran »). Preuve
    (garde-fous advisor : valider le discriminant sur valeurs réelles GREEN+RED avant seuil ; planariseur auto-vérif ;
    référence depuis les vraies données ROM) : marqueur série **M6S** = liveness ; discriminant VISUEL = nombre de
    couleurs uniques en zone active (GREEN ~19017 vs RED one-plane ~151, séparation ~126×, seuil 1000). RED
    `BOOTSCR_ONE_PLANE` (depth=1 → 2 couleurs → image détruite) ; marqueurs série TOUS présents → isole le rendu
    multi-bitplane sans casser le boot. COOP non-rég. Checksum GREEN `0x92E3ACA7`. ROM ~177 Ko libres. ⚠️ Affiché
    INCONDITIONNELLEMENT au handoff : le vrai déclencheur « aucun volume bootable » reste à l'incrément strap.
    Lancer soi-même : `tests/run_fsuae.sh` (FS-UAE fenêtré, WSLg).
  - **M6r — strap (romboot) + vrai déclencheur insert-disk, 3e incrément M6 (FAIT, 1er maillon boot disquette).**
    Cadrage advisor : (1) le « ça boote ! » visera un bootblock CUSTOM après A+B+C (sans dos) ; (2) le déclencheur
    insert-disk doit venir de l'ÉCHEC d'accès à DF0:, pas d'une liste vide (sinon synthétique comme M5/M6d) ;
    (3) OFS+dos+CLI = UN sous-système packets, re-décomposer plus tard ; (4) ne pas sur-spécifier B→F ; (5) `AddBootNode`
    est V36/2.0+, PAS 1.3 → mécanisme interne clean-room libre, comportement 1.3-compatible. `src/exec/strap.s` :
    `strap_boot(a6)` = ÉCHAFAUDAGE, renvoie toujours 0 = aucun volume bootable (FindName(trackdisk) + CMD_READ +
    validation/exécution du bootblock = incréments B/C). boot.s : si 0 → l'affichage de l'écran de boot (insert-disk)
    est ROUTÉ par cette décision + marqueur M6R, sinon (jamais en GREEN) saute l'écran. ⚠️ Le VRAI déclencheur
    (écran parce que la lecture de DF0: échoue) vient avec B/C ; A ne fait que router l'écran par le strap. Preuve
    DOUBLE : série M6R + VISUEL (couleurs ~19017 écran
    chaton). RED `STRAP_FAKE_BOOTDEV` (strap croit booter → d0≠0) → ni M6R ni M6S ni écran (couleurs basses),
    marqueurs boot M3F..M7 intacts → isole la décision strap. COOP non-rég. PROCHAIN : incrément B trackdisk.device.
  - **B / M6t — trackdisk.device squelette + validation d'unité (FAIT).** B trop gros pour un incrément → re-décomposé :
    B1 squelette (CETTE tranche) → B2 contrôle drive CIA + lecture piste MFM brute (Paula DMA, sync `$4489`) → B3
    décodage MFM (piste → 11 secteurs × 512 o + checksums) → B4 `CMD_READ`. `src/exec/trackdisk.s` : 2e device, ROMTag
    AUTOINIT NT_DEVICE pri 20 → DeviceList ; `Open(unité)` valide le numéro (DF0-3 → io_Unit = base+TDU_UNIT0+unit*8,
    io_Device = base, OpenCnt++ ; unité ≥ 4 → échec OpenDevice io_Error/io_Device=0). `BeginIO` stub `IOERR_NOCMD`
    (garde-fou advisor : devra ReplyMsg dès qu'un consommateur réel l'appellera, sinon DoIO hang). Unités =
    placeholders (→ Unit+MsgPort en B2). Garde-fous advisor : assertion `io_Unit == base+TDU_UNIT0` (adresse EXACTE,
    pas « ≠0 » non-load-bearing) ; ne pas figer le layout d'unité ; ne pas toucher le strap (FindName load-bearing en
    C). Preuve série **M6T** : FindName(DeviceList) + version + NT_DEVICE + Open(0) OK + Open(4) échoue. RED
    `TD_NO_UNITCHECK` (unité 4 ouvre à tort) → M6T absent. COOP non-rég. ⚠️ B1 n'est PAS encore la lecture (= B2-B4) ;
    heads-up B2 : CIA-B partagé avec l'unité MICROHZ M7a. PROCHAIN : B2 (checkpoint user — le plus dur).
  - **B2 / M6u — lecture d'une piste MFM brute de DF0 (FAIT, le plus dur).** La ROM accède pour la 1re fois au
    matériel disque. `src/exec/disk.i` (registres Paula/CIA disque clean-room HRM+NDK) + `td_read_track0` dans
    trackdisk.s. Garde-fous advisor (ont tout débloqué du 1er coup) : (1) **CIA-B DDRB=$FF** avant d'écrire PRB
    (sinon PRB ne pilote rien — jamais posé avant, suspect n°1) ; (2) séquence MINIMALE d'abord (moteur+select+DMA),
    SANS step ni side-select (polarités DSKDIREC/DSKSIDE non vérifiables de mémoire — reportées ; la tête est à track
    0 au reset ; le compte de syncs se fiche de la piste) ; (3) de-risquer le montage ADF (confirmé par la lecture
    elle-même) ; (4) ADKCON=$8400 (SETCLR|WORDSYNC, DD) ; DSKRDY timeout+poursuit ; DSKBLK masqué dans INTENA
    (poll INTREQR) ; timeout sur CHAQUE boucle. Séquence : DDRB=$FF, PRB moteur-on+select DF0 (latch via front SEL0),
    spin-up, disk DMA (DSKSYNC=$4489, DSKPT=buf chip, DSKLEN×2, DMACON DSKEN), poll DSKBLK timeout, stop (clear
    SEULEMENT DSKEN, pas MASTER=affichage). N'écrit que CIA-B PRB -> timers MICROHZ/M7a intacts. Preuve série
    **M6U** + compte de syncs émis (routine `ser_puthex` ajoutée) : **SYNCS=0016 = 22 mots `$4489`** lus (= 11
    secteurs × 2 syncs d'en-tête ; `$4489` impossible dans du MFM normal + buffer MEMF_CLEAR -> 0 faux positif).
    RED `TD_NO_DMA` (DMA non armé -> buffer à 0 -> 0 sync) -> M6U absent. Contrôle sans disque -> timeout -> M6U
    absent (prouve que M6U vient du disque). COOP non-rég. `tests/boot_test.sh` étendu : 5e arg ADF optionnel en DF0.
    PROCHAIN : B2b (step/side vers une piste précise) puis B3 (décodage MFM). Checkpoint user.
  - **B3 / M6v — décodage MFM de la piste (FAIT, cœur algorithmique).** User : « go B3 » (+ B4 + B2b enchaînés).
    Garde-fou : l'algorithme MFM Amiga (split odd/even + checksums) = fait à NE PAS coder de mémoire → VERROUILLÉ
    d'abord par round-trip Python (`scratchpad/mfm_ref.py`) : decode `((odd&$55555555)<<1)|(even&$55555555)` (odd en
    1er), checksums en-tête/data = XOR des longs MFM & masque. `td_decode_track(rawbuf, sectorbuf)` : scanne les syncs
    $4489, décode info (format=$FF, n° secteur < 11), vérifie checksum en-tête (XOR 10 longs info+label) ET checksum
    data (XOR 256 longs), décode 512 o vers sectorbuf+n°*512, renvoie le nombre de secteurs valides. Offsets secteur
    (depuis info_odd) : +0 info +8 label +40 hdrchk +48 datachk +56 data_odd +568 data_even, fin +1080. Preuve série
    **M6V** + compte émis : **SECTORS=000B = 11** secteurs décodés+vérifiés ET secteur 0 == « DOS\0 » (bootblock OFS).
    RED `MFM_BAD_DECODE` (saute le <<1 du combine data → données fausses mais checksums (sur MFM brut) toujours OK →
    SECTORS reste 11 mais secteur 0 != DOS) → M6V absent : isole la correction du décodage data. Contrôle sans disque
    → M6V absent. COOP non-rég. Fixes build : branches `.s`→word (routine grande), `lsl.l #9` interdit (max 8) →
    `lsl #8`+`add`. PROCHAIN : B4 (CMD_READ) puis B2b (step/side).
  - **B4 / M6w — CMD_READ device (FAIT).** `trackdisk_beginio` (le stub B1 `IOERR_NOCMD`) devient un vrai handler :
    CMD_READ -> td_read_track0 + td_decode_track + copie io_Length octets depuis sectorbuf+io_Offset vers io_Data,
    pose io_Actual/io_Error ; autres commandes -> IOERR_NOCMD. **ReplyMsg si NON quick** écrit (dette B1) MAIS ⚠️ seul
    le chemin QUICK est prouvé par M6W ; le non-quick sera exercé par un vrai DoIO (strap/dos) en C.
    Limité à la piste 0 (offset+length <= 11*512) tant que B2b n'existe pas. Constantes disk.i : CMD_READ=2, IOF_QUICK,
    IO_ACTUAL/LENGTH/DATA/OFFSET (IOStdReq 32/36/40/44). Preuve série **M6W** : IOStdReq (CMD_READ, offset 0, length
    512, IOF_QUICK) -> BeginIO via vecteur -30 -> io_Error==0 & io_Actual==512 & secteur lu == « DOS\0 ». RED
    `TD_READ_NOCMD` (BeginIO ne reconnaît pas CMD_READ) -> M6W absent. ⚠️ M6W fait une LECTURE -> gaté sur « disque
    présent » (flag d4 posé par la lecture fusionnée M6U/M6V) pour éviter un 2e timeout sans disque (sinon M7A décalé) :
    M6W ne tourne qu'avec disque (lecture rapide). Fix build : branches .s->word (routine BeginIO grande). PROCHAIN : B2b.
  - **B2b / M6x — step/seek + side-select (FAIT ; trackdisk COMPLET).** Les polarités DSKDIREC/DSKSIDE différées depuis
    B2 (non vérifiables de mémoire) — guessées puis validées à l'émulateur DU 1ER COUP. `td_read_track0` -> `td_read_track(d0=
    n° de piste)` : recalibration cylindre 0 (step OUT, direc bit1=1, jusqu'à DSKTRACK0, cap 85) + step IN (direc bit1=0)
    jusqu'au cylindre=piste/2 + side-select (DSKSIDE bit2 : face 0 = $77, face 1 = $73) ; pulse DSKSTEP (front 1->0) +
    settle busy-loop ; td_read_track0 = wrapper piste 0 (M6U/M6V/BeginIO inchangés : track 0 -> 0 pas -> pas de régression).
    td_decode_track renvoie d1 = n° de piste décodé (oracle). Preuve série **M6X** + diagnostic « M6X TRACK=XXXX » : lire la
    piste 2 -> TRACK=0002 + 11 secteurs avec track==2 (valide le seek ET le side : un mauvais side lirait la piste 3). RED
    SEEK_NOSTEP (pas de step-in -> reste piste 0 -> TRACK=0000) -> M6X absent. Gaté sur disque présent (d4) -> M7A intact.
    trackdisk.device COMPLET : lit n'importe quel secteur logique de n'importe quelle piste de DF0.
  - **C / M6y — « ça boote ! » : le strap lit, valide et EXÉCUTE le bootblock (FAIT).** `strap_boot` lit les secteurs 0+1
    de DF0: (`CMD_READ` offset 0 len 1024 = bootblock, DANS la piste 0 -> pas besoin du wiring multi-piste pour C), valide
    magic « DOS » + **checksum additif** (somme à retenue circulaire des 256 longs == `$FFFFFFFF` — ADDITIF, piège classique
    vs le XOR des checksums MFM ; algo porté puis simulé en Python avant usage), puis **JSR au boot code à +12** (A6=SysBase,
    A1=IORequest ; A0 de handoff dos IGNORÉ = déviation assumée sans dos). Bootable -> « bouté » (**M6Y**, pas d'insert-disk) ;
    checksum invalide (ADF formaté = checksum 0, vérifié empiriquement) ou pas de disque -> 0 -> insert-disk (**M6R**) = VRAI
    déclencheur 1.3. Preuve : marqueur **CBOOT** émis par le bootblock LUI-MÊME (prouve le saut). 6 scénarios : GREEN+ADF
    bootable (CBOOT+M6Y), GREEN+ADF formaté (M6R, checksum rejette), sans disque (M6R+M7A ok), RED STRAP_NO_EXEC (M6Y sans
    CBOOT = isole l'exécution), RED STRAP_BAD_CSUM (bon bloc rejeté = isole la validation), COOP. Correctif trackdisk requis
    pour C : recalibration TOUJOURS faite (lecture depuis position connue — un read piste-0 après seek lisait la mauvaise
    piste silencieusement) + détection lecteur absent via timeout DSKRDY (probe no-disk rapide). ADF bootable custom
    régénérable : `tests/mk_boot_adf.sh` (xdftool format + `tests/bootblock_c.s` assemblé en binaire brut + `tests/patch_bootblock.py`
    qui pose le checksum et round-trip la bootabilité ; sortie `assets/boot_c.adf`, gitignorée). PROCHAIN : D (vraie dos.library,
    packets) — prérequis = wiring `CMD_READ` offset->piste multi-piste pour lire le filesystem au-delà de la piste 0.
  - **M6z — CMD_READ MULTI-PISTE (prérequis D, FAIT).** `trackdisk_beginio` (B4 : piste 0 seulement) devient multi-piste :
    l'offset octet -> (piste, secteur) via `bloc=offset/512`, `piste=bloc/11` (`DIVU #11`), `secteur=bloc%11` ; la boucle lit
    CHAQUE piste touchée (`td_read_track`+`td_decode_track`, sectorbuf réutilisé), copie jusqu'à la fin de piste et avance -> une
    requête qui TRAVERSE une frontière de piste est servie en plusieurs lectures (dos pourra lire le filesystem au-delà de la piste 0).
    Contrat trackdisk honoré : `io_Offset`/`io_Length` multiples de TD_SECTOR (512) -> garde `IOERR_BADLENGTH` ; garde de borne
    `TD_DISKBYTES` (1760*512). Registres : la boucle garde son état en d2-d7/a2-a5 (tous préservés par `td_read_track`
    [sauve d2/d3/d6/a2, n'écrit pas le reste] ET `td_decode_track` [sauve d2-d7/a2-a5]). Preuve série **M6Z** = 2 lectures via
    `BeginIO` (le vrai chemin device) : (1) root block @ **bloc 880 = piste 80** (cyl 40) -> type primaire +0 == 2 (T_SHORT) ET
    type secondaire +508 == 1 (ST_ROOT) — un mauvais mapping renverrait la piste 0 (bootblock) ; (2) lecture **SPANNING** offset
    `10*512` length 1024 = blocs 10+11 -> TRAVERSE la frontière piste 0/1, assemble « SPAN0010 » (bloc 10 = piste 0 sect 10) +
    « SPAN0011 » (bloc 11 = piste 1 sect 0) posés par `patch_bootblock.py` dans des blocs libres (round-trip Python). RED
    `TD_NOSEEK` (lit toujours la piste 0, secteur/octet corrects -> lecture aboutit sans crash) -> les deux contrôles échouent ->
    M6Z absent (isole le mapping offset->piste, discipline M6D_BAD_BPTR). GREEN-BOOT : M6Z + non-rég (M6U/V/W/X, CBOOT/M6Y, M7A/M7L,
    set M3F..M7F complet, 0 FAILED). RED : M6Z absent, reste intact. CTRL-NODISK : M6Z gaté (d4), aucun timeout ajouté, M6R+M7A ok.
    PROCHAIN : dos.library proprement dite (modèle packets BCPL / `LoadSeg` / handlers / OFS) — à re-décomposer + checkpoint user.
  - **D1 — OFS lecture seule (FAIT).** `src/dos/ofs.s` + `ofs.i` : `ofs_read_file(name, dest, max)` lit un fichier
    par nom depuis DF0: en parcourant le filesystem OFS — **machinerie INTERNE** (PAS encore de packets/handler BCPL
    = D3), s'appuie sur trackdisk `CMD_READ` (M6z). Algorithme OFS **verrouillé empiriquement** sur un ADF de test
    (asset, PAS la ROM, discipline du round-trip MFM B3) : root@880 ; hash `h=len ; h=(h*13+toupper(c))&$7FF ;
    idx=h%ht_size` ; table de hash -> header (nom BCPL @long108, sec_type @long127=ST_FILE, first_data @long4,
    hash_chain @long124) ; data block OFS (type 8, data_size @long3, next @long4, données @+24). Insensible à la
    casse (toupper ASCII a-z, OFS non-international). Gardes (coding-principles « valider avant d'utiliser ») : type
    T_SHORT/T_DATA, sec_type ST_FILE, bornes de bloc [2,1760), ht_size<128, data_size<=488, garde buffer `max` ;
    boucles hash-chain/data **cappées** (anti-hang disque corrompu). Appel inter-module via `jsr` (ofs.o lié hors
    portée `bsr` 16 bits). Preuve série **D1** : taille retournée == 1024 (discriminant primaire) + marqueurs aux
    frontières de data block (@0/@488/@976) -> prouve trouvé-par-nom (« kickslop » vs stocké « KickSlop » exerce le
    case-folding) ET chaîne data complète (3 blocks). RED `OFS_NO_DATACHAIN` (ne suit pas next_data) -> taille 488
    -> D1 absent (isole le chaînage). GREEN-BOOT (D1 + non-rég M6U..M6Z/CBOOT/M6Y/M7A, 0 FAILED) + RED + CTRL-NODISK
    (D1 gaté d4) + COOP (D1 + M3F). ⚠️ Lenteur : chaque bloc = 1 lecture de piste avec recalibration (dette : pas de
    tracking de cylindre) -> le boot disquette complet demande ~40 s sous FS-UAE (WAIT=60). FFS + sous-répertoires
    + écriture hors scope. Fichier de test écrit par `tests/mk_ofs_testfile.py` + `xdftool write` (mk_boot_adf.sh).
  - **D2 — LoadSeg (FAIT).** `src/dos/loadseg.s` : `dos_loadseg(name)` -> BPTR seglist | 0 + `dos_unloadseg(BPTR)`.
    Charge un exécutable AmigaDOS **« hunk »** depuis l'OFS (via `ofs_read_file` D1), alloue un segment par hunk,
    copie le contenu, **APPLIQUE les relocations**, bâtit la seglist BPTR et la renvoie. Machinerie INTERNE (pas de
    packets = D3). Format hunk **verrouillé empiriquement** (binaire `vlink -s -bamigahunk`, PAS la ROM) :
    HUNK_HEADER (resident libs=0, table_size, first, last, N tailles [bits 30-31 = flags mémoire masqués]) ; corps
    par hunk : CODE/DATA (nlongs + data) ou BSS (nlongs, pas de data), **HUNK_RELOC32 ($3EC** — vlink n'émet PAS la
    variante compacte $3FC : on gère $3EC, et $3FC/SYMBOL/DEBUG -> échec PROPRE, jamais de skip silencieux de
    relocation), HUNK_END. Seglist (convention AmigaDOS, vérifiée vs AROS InternalLoadSeg) : bloc `[LONG taille][BPTR
    next][contenu]` ; le BPTR pointe sur le champ next (bloc+4) -> contenu à `(BPTR<<2)+4` = bloc+8. Déviations D2
    assumées : flags chip/fast ignorés (MEMF_PUBLIC) ; first!=0 / SYMBOL / resident libs / $3FC / overlays non
    supportés (échec propre). Preuve série **D2LOADSEG** : exécutable de test `D2Test` (section CODE + DATA + 1
    relocation 32 bits CODE->DATA) chargé + relocalisé + EXÉCUTÉ -> le code émet LUI-MÊME « D2LOADSEG OK » depuis la
    RAM (même logique que CBOOT en C : le marqueur vient du code chargé = preuve qu'il tourne AVEC relocation). RED
    `D2_NO_RELOC` : load OK mais relocation NON appliquée -> le pointeur absolu reste l'offset link-time (0) -> le
    code lit la RAM basse (adresse 0 = octet nul -> rien émis) -> « D2LOADSEG OK » absent, SANS bus error -> isole
    l'application des relocations. GREEN-BOOT (D2 + non-rég D1/M6*/CBOOT/M6Y/M7A, 42 lignes, 0 FAILED) + RED (D2
    absent, D1+reste intacts) + CTRL-NODISK (D2 gaté) + COOP (D2 + M3F). Exécutable de test : `tests/loadseg_d2.s`
    -> `vasm -Fhunk` + `vlink -s -bamigahunk` -> `xdftool write D2Test` (mk_boot_adf.sh). ⚠️ WAIT>=90 (I/O disque).
    PROCHAIN : D3 = cœur architectural (modèle packets BCPL + file-handler DF0: + CreateProc + CLI) -> checkpoint user.
  - **D3 — dos packets / handler / process → « exécuter une commande » (en cours).** Cadrage user+advisor
    (2026-10-17) : approche 1 (ABI packet observable fidèle, processes en C, pas de runtime BCPL). Piste ANALYSE
    lancée d'emblée (agent isolé) → `docs/analysis/dos-v34-spec.md` + `dos-boot-sequence.md` (relues, porte de
    revue clean-room passée). Design : `docs/D3-dos-design.md`. Décomposé D3a→D3d, prouvés depuis le scaffold de
    boot comme vrais processes (phase ordonnancée, après `dispatch_in`).
    - **D3a — Process + CreateProc + round-trip packet (FAIT).** `src/dos/process.s` (`proc_create`) + `dospkt.i`
      (layout V34 Process/DosPacket/StandardPacket/FileHandle/DeviceNode + ACTION_*). `proc_create` bâtit un
      `Process` (Task exec + `pr_MsgPort` embarqué @0x5C), initialise ENTIÈREMENT le port dans le parent (sigbit
      réservé `DOS_PORTSIG=8` = SIGB_DOS, pré-alloué via TC_SIGALLOC → pas de handshake, pas de race), `AddTask`,
      renvoie l'APTR du port. Preuve **D3A** : un process driver monte un StandardPacket, `PutMsg` au port d'un
      process handler echo, `WaitPort`/`GetMsg` la réponse (round-trip via switch synchrone M3d) → echo correct.
      RED `D3A_NO_REPLY` (handler ne `ReplyMsg` pas → driver bloqué) → D3A absent. GREEN-BOOT (D3A + non-rég
      D1/D2/M3F/M7A/M7C/M7D, 0 FAILED) + RED + COOP (D3A exercé COOPÉRATIVEMENT, SCHED_ON=0) + CTRL-NODISK (D3A
      présent, disk-indépendant ; D1/D2 absents). checksum GREEN `0x47B39093`. PROCHAIN : D3b (handler OFS).
    - **D3b — process file-handler DF0: + dos_sendpkt (FAIT).** `src/dos/handler.s` (`dos_handler_df0`) : un vrai
      process qui boucle `WaitPort`/`GetMsg` et sert `ACTION_FINDINPUT`/`READ`/`END` via `ofs_read_file` (D1).
      `FINDINPUT` (ARG1=BPTR FileHandle, ARG3=BSTR nom) lit le fichier ENTIER dans un buffer handler (simplification
      assumée : lectures incrémentales OFS différées), pose `fh_Arg1`=état{buffer,taille,pos} ; `READ`(clé,buf,len)
      copie+avance (RES1=octets, 0=EOF) ; `END` libère. Helper `dos_sendpkt` (process.s) : monte le StandardPacket,
      `PutMsg`+`WaitPort`/`GetMsg` sur `ThisTask->pr_MsgPort` (pas de DoPkt public V34). Preuve **D3B** : un fs-driver
      ouvre/lit/ferme « kickslop » À TRAVERS le handler par packets → 1024 o + marqueurs @0/@488/@976. RED
      `D3B_NO_READ` (handler ne sert pas READ → EOF) → octets faux → D3B absent (FINDINPUT/END marchent). GREEN-BOOT
      (D3B + D3A + non-rég D1/D2/M3F/M7C/M7D, 0 FAILED) + RED + CTRL-NODISK (D3A présent disk-indép, D3B absent) +
      COOP. **Découverte (advisor-anticipée)** : notre trackdisk est CPU-BOUND (busy-loops recalibration, pas
      interrupt-driven) → le handler (pri 6) affame les tâches de pri inférieure pendant sa longue lecture → les
      markers de pri<6 arrivent TARD → **WAIT≈280 s** requis. Fix d'entrelacement série : la paire echo (D3a) passe
      pri 8/7 (> paire OFS 6/5) → D3A émis TÔT, D3B tard → émissions non concurrentes. checksum GREEN `0x927FC4D9`.
      ⚠️ La lenteur CPU-bound va dépasser 5 min avec D3c/D3d → **cylinder-tracking = incrément dédié AVANT D3c**
      (advisor : ne pas le bundler ici ; il re-vérifie toutes les preuves disque). PROCHAIN : cylinder-tracking, puis D3c.
  - **Cylinder-tracking (trackdisk, incrément dédié — FAIT).** Résout la dette « recalibration à chaque lecture »
    (devenue bloquante : boots > 5 min sous l'ordonnanceur avec D3b). `td_read_track` suit le cylindre courant
    (`TD_CURCYL`, fiable ssi `TD_CYLVALID`) et steppe le **delta** vers la cible (IN/OUT selon le signe) au lieu de
    recalibrer à 0 à chaque lecture ; recalibration (step OUT jusqu'à DSKTRACK0, cap 85) SEULEMENT si position
    inconnue. Corrige PROPREMENT le bug C (lire après un seek lisait la mauvaise piste) : le delta ramène la tête au
    bon cylindre. Bug attrapé en route : `.rd_settle` clobbait **d3** (que le nouveau code utilise pour le cylindre
    cible) → `TD_CURCYL` stocké faux → le seek suivant allait au mauvais cylindre (M6X lisait bien mais M6Z/D1/D2
    décalés d'1) ; fix : `.rd_settle` compte en d0. Preuve : à **WAIT=90** (impossible avant — il fallait 280) toute
    la suite disque est correcte (M6X TRACK=0002, M6Z, D1, D2, CBOOT/M6Y, D3A, **D3B**, M3F, 0 FAILED). RED
    `TD_NO_CYLTRACK` (force la recalibration à chaque lecture = ancien comportement) → D3B absent à WAIT=90 (trop
    lent) → isole le GAIN de vitesse. Re-vérif correction : RED `SEEK_NOSTEP` → M6X TRACK=0000, « M6X SEEK OK »
    absent (seek toujours RED-prouvé). COOP (WAIT=90) + CTRL-NODISK (seek non atteint sans disque). checksum GREEN
    `0xC422E669`. DETTE restante : pas d'invalidation sur disk-change (eject/swap réel + recal périodique = M7).
    PROCHAIN : D3c (dos Open/Read/Close user-facing via packets).
  - **D3c — dos Open/Read/Close user-facing (LVO) via packets (FAIT).** `dos_lib.s` : vecteurs `Open`(-30)/`Close`
    (-36)/`Read`(-42) implémentés. `Open(name,mode)` résout le handler via `DosInfo.di_DevInfo` → 1er `DeviceNode`
    → `dn_Task`, alloue un `FileHandle` (+buffer BSTR du nom), pose `fh_Type`=port handler, envoie `FINDINPUT`
    (ARG1=BPTR(fh), ARG3=BPTR(nom)) via `dos_sendpkt`, renvoie BPTR(fh). `Read` route via `fh_Type`/`fh_Arg1`
    (ACTION_READ). `Close` : `END` + FreeMem. a6 bascule DosBase↔SysBase ; StandardPacket sur la pile du process ;
    appelé depuis un PROCESS (pr_MsgPort = port de réponse). Setup boot : monte un `DeviceNode` (dn_Task=DOS_FSPORT)
    dans `di_DevInfo`. Preuve **D3C** : un process client `OpenLibrary(dos)` + `Open`/`Read`/`Close` « kickslop » par
    les LVO → 1024 o + marqueurs. RED `D3C_NO_FHTYPE` (Open ne pose pas `fh_Type` → Read garde-fou renvoie 0) → D3C
    absent (isole le câblage de la route Open→Read). GREEN @WAIT=90 (D3C + non-rég D1/D2/D3A/D3B/M3F/CBOOT/M6Y, 0
    FAILED) + RED + CTRL-NODISK + COOP. checksum GREEN `0x7329BBD6`. PROCHAIN : D3d (LoadSeg via dos + run).
  - **D3d — LoadSeg À TRAVERS dos + exécuter une commande (FAIT ; CLÔT D3).** Refactor `loadseg.s` : le parser hunk
    est extrait en `ls_load_hunks(filebuf, taille)` (ne lit/ne libère PAS le fichier) ; `dos_loadseg` (D2) devient
    un wrapper (ofs read + ls_load_hunks). Client D3d (process) : `OpenLibrary(dos)` → `Open`/`Read`/`Close`
    « d3dtest » PAR LES LVO DOS (packets → handler → OFS) dans un filebuf → `ls_load_hunks` → `JSR (seglist<<2)+4`.
    La commande (`tests/loadseg_d3d.s`, hunk avec RELOC32) émet elle-même **D3D LOADSEG-VIA-DOS OK** depuis la RAM
    → prouve toute la chaîne « charger+exécuter une commande via dos » (lecture par packets + reloc + run). RED
    `D3D_NO_RUN` (charge mais saute le JSR) → commande pas exécutée → D3D absent (isole l'exécution). GREEN @WAIT=90
    (D3D + non-rég D1/D2/D3A/D3B/D3C/M3F, 0 FAILED) + RED + CTRL-NODISK + COOP. Exécutable `D3DTest` écrit sur l'ADF
    (mk_boot_adf.sh). **Cible « exécuter une commande » ATTEINTE.** Différé (E/F) : CLI interactif, bootstrap réel
    (Initial CLI, startup-sequence, console, requesters), lectures incrémentales OFS, Write/Lock/Seek.
  - **D3e — LoadSeg / UnLoadSeg via les VRAIS vecteurs LVO (FAIT).** `dos_lib.s` : `dos_fn_loadseg` (vecteur 25 →
    **LVO -150**) + `dos_fn_unloadseg` (vecteur 26 → **LVO -156**). LoadSeg ouvre via le vrai `Open`(-30, MODE_OLDFILE),
    lit ENTIER via le vrai `Read`(-42, boucle jusqu'à EOF ; handler séquentiel) dans un buffer, parse via `ls_load_hunks`
    (hunks + reloc → seglist BPTR), referme via `Close`(-36). Scinde le `dcb.l 24` de la jump table en 17/LoadSeg/
    UnLoadSeg/5 (canary **M6D** : DateStamp -192 reste vecteur 32 → table non décalée). Preuve **D3E LOADSEG LVO OK** :
    `d3e_client` (process pri 2) charge « D3DTest » par `jsr DOS_LVO_LOADSEG(a6)` → seglist non nul → UnLoadSeg. `d3d_client`
    (load inline) RESTE la baseline indépendante (advisor : ne pas refactorer un test prouvé — add+prove) ; RED
    `LOADSEG_LVO_UNWIRED` (-150 → dos_null) → D3E absent, **D3D baseline vert** → isole le câblage du vecteur LVO. GREEN
    (ADF) : M6D + D3C + D3D + D3E + GAMEPORT/M6R/GP-LIVE + DISK VALID + KEYMAP + F1BOOTOK + M7A/M7E/M7F, 0 FAILED ; md5
    `8d9517af1ea696af8334e35b171c00ac`. **Portée (révélée par le test Lemmings)** : charge NOS exécutables hunk via le
    vrai chemin LVO ; whole-file bufferisé (≤ 16 Ko, pas de streaming), handler OFS DF0: seul → ne suffit PAS à exécuter
    du logiciel commercial (manquent `Lock`/`Seek`/`Examine`/`Write`, `expansion.library`, streaming ; et boot.s est un
    harnais de dev). `sh_exec_cmd` (E3) garde son load inline (non touché : ne pas risquer E3/F1/F2b).
  - **expansion.library (autoconfig, parité) FAIT.** `src/exec/expansion.s` : résident AUTOINIT NT_LIBRARY pri 110.
    ExpansionBase (Library + eb_Flags@34 + liste ConfigDev). Fonctions réelles aux offsets LVO confirmés sur AROS
    `expansion.conf` (OpenLib slot0 ; AddConfigDev slot4=-30, AllocConfigDev slot7=-48, FindConfigDev slot11=-72,
    FreeConfigDev slot13=-84 ; LVO=-6*(slot+1)) ; reste = exp_null. Preuve **EXPANSION OK** (synchrone early) :
    OpenLibrary v37→0 (gate) / v34→base ; AllocConfigDev→AddConfigDev→FindConfigDev exact+wildcard+miss ; cleanup
    gardé (Remove ssi ln_Succ≠0). RED `EXP_NO_ENQUEUE`. Non-rég scan résident (M4 RESIDENTS OK) + ADF complète,
    0 FAILED, md5 `b0bb2f2f92f21b84be18a0ab49665ef3`. **Offsets vérifiés via AROS, PAS de mémoire** (le résumé
    WebSearch s'était trompé en plaçant AddBootNode en premier). **Twist Lemmings** : le bootblock ouvre expansion
    en **v37** (KS 2.0) → gate V34 renvoie 0 → branche expansion sautée (tolérée) → ce module ne débloque PAS
    Lemmings, c'est de la parité. Différé : ConfigBoard/ReadExpansionRom (probe HW), MakeDosNode/AddBootNode (montage).
    15/16 ROMTags (RESMAX ; 1 slot de marge).
  - **Fonctions dos manquantes : IoErr(-132) + Seek(-66) FAIT.** `dos_lib.s`/`process.s`/`handler.s`. IoErr renvoie
    `pr_Result2` ; `dos_sendpkt` copie `dp_Res2 → pr_Result2` après chaque packet (faithful, un seul point) ; le
    handler pose `DP_RES2=ERROR_OBJECT_NOT_FOUND`(205) sur Open introuvable (vérifié AVANT de bâtir — il posait 0,
    IoErr aurait été creux). Seek envoie `ACTION_SEEK` → le handler ajuste `HS_POS` (bufferise tout le fichier),
    borné, rend l'ANCIENNE position. Vecteurs 11/22 câblés (DateStamp -192 reste vecteur 32 = canary). Preuve **DOS
    IOERR SEEK OK** (`d3f_client` pri 5, émet sous Forbid) : Open absent→0 + IoErr≠0 ; Open d3dtest→IoErr 0 ; Read 4
    → Seek(0,BEGINNING) → Read 4 identiques. REDs `DOS_NO_IOERR` (pas de propagation dp_Res2) + `HND_NO_SEEK` (handler
    ignore SEEK). GREEN ADF (74s : DOS IOERR SEEK OK + EXPANSION + D3C/D3D/D3E + E3 + M7, 0 FAILED), md5
    `6a24da8be3eee8a03126e86e0b715122`. **Write(-48) différé** (advisor) : OFS lecture seule → Write-fichier ne
    prouverait que l'échec propre ; un vrai Write = câblage console (con_handler + Output -60), hors périmètre de cet
    incrément. Autres dos (Lock/Examine/CurrentDir/Input/Output...) toujours non impl.
  - **Fonctions dos : Write(-48) + Input(-54) + Output(-60) + CurrentDir(-126) FAIT.** `dos_lib.s`. Write envoie
    ACTION_WRITE au port fh_Type (con_handler -> série ; OFS read-only -> erreur). Input/Output = pr_CIS/pr_COS de
    ThisTask. CurrentDir pose pr_CurrentDir + rend l'ancien. Vecteurs 8/9/10/21 (DateStamp -192 reste vecteur 32 =
    canary M6D intact). Preuve **DOS WRITE OK** (d3g_client) : CurrentDir round-trip + Input relu + pr_COS = FileHandle
    console (fh_Type=DOS_CONPORT) -> Output() rend ce BPTR -> Write(Output(),msg) -> le marqueur est émis PAR le Write
    via con_handler (prouve les 4 d'un coup). RED `DOS_NO_WRITE`. GREEN ADF (DOS WRITE OK + M6D + EXPANSION + GAMEPORT
    + DISK VALID + M7, 0 FAILED), md5 `f4e3af995dd7ea908220b02b627be860`. **Write via CONSOLE** (pas fichier : OFS
    read-only).
  - **LoadSeg cap-bump 16K -> 32K FAIT** (PAS du streaming). Le cap de lecture était le buffer whole-file du handler
    (HND_FILEMAX) + celui de LoadSeg (LS_LOADMAX), 16 Ko chacun. Relevés à un `DOS_FILEMAX`=32 Ko partagé (exec.i ;
    handler.s/dos_lib.s/loadseg.s le référencent). Advisor : le vrai streaming (lecture incrémentale OFS sur HS_POS)
    = gros blast radius sur ACTION_READ prouvé (D1/D3B/D3C/D3D/E3/F1) pour rien de consommable maintenant -> DETTE
    différée ; faire un cap-bump honnête + prouvé. Preuve **LOADSEG BIG OK** : `tests/loadseg_big.s` (hunk > 16 Ko :
    24 Ko DATA + sentinelle en fin + 1 RELOC32) écrit sur l'ADF (`bigseg`), chargé par `d3h_client` via LoadSeg(-150)
    + exécuté -> vérifie la sentinelle (tout le gros DATA lu) -> émet. RED `LOADSEG_CAP16K` (re-plafonne 16 Ko ->
    bigseg tronque -> absent ; d3dtest petit OK). Non-rég ADF : D3E + E3 + D1 + M6Z + DOS WRITE, 0 FAILED, layout ADF
    préservé (blocs 10/11 spanning non perturbés par bigseg). md5 `9b279b64b48f65b3a30a8e5ea3c323c8`. 2 buffers
    concurrents = 64 Ko transitoire (sûr). **Streaming réel (incrémental OFS) reste différé** avec Lock/Examine.
  - **Lock(-84) + UnLock(-90) + Examine(-102) + ExNext(-108) FAIT.** `dos_lib.s`/`handler.s`/`ofs.s`/`ofs.i`/`dospkt.i`.
    Locks + lecture de répertoire OFS. Lock résout DF0: → port handler, nom → BSTR long-aligné, `ACTION_LOCATE_OBJECT` ;
    le handler résout le chemin via `ofs_name_to_block` (préfixe `xxx:` ignoré, vide/« : » → racine, sous-rép
    `/`-séparés, final fichier OU dir), alloue un `FileLock` {fl_Key=bloc, fl_Access=mode, fl_Task=port, curseur privé
    flp_Bucket/flp_ChainBlk} → BPTR. UnLock : port via `fl_Task` → `ACTION_FREE_LOCK` (FreeMem). Examine : `ofs_fill_fib`
    (DiskKey/DirEntryType=sec_type/FileName BCPL→C/Size=byte_size@324 si fichier) + reset curseur. ExNext : `ofs_dir_next`
    (parcourt la chaîne hash courante puis avance bucket par bucket dans la hashtable, remplit le FIB, fait avancer le
    curseur DANS le lock). Vecteurs 14/15/17/18 (DateStamp -192 reste vecteur 32 = canary). **Offset OFSB_FILESIZE=324
    vérifié sur l'ADF (kickslop bloc 866 → 1024) AVANT build**, reconfirmé par l'assertion de boot. Preuve **DOS LOCK
    EXAMINE OK** (`d3i_client` pri 5, émet sous ser_lock) : (A) Lock("kickslop")→Examine → DirEntryType<0 + fib_Size==1024
    (oracle) ; (B) Lock(":")→Examine (répertoire)→ExNext boucle trouve l'entrée fichier de 1024 o (= kickslop). RED
    `OFS_NO_DIRNEXT` (found=0 d'emblée → marqueur absent, **D1 OFS READ reste VERT** = isole l'énumération). GREEN ADF
    (DOS LOCK EXAMINE OK + non-rég D1/D3E/DOS IOERR SEEK/DOS WRITE/LOADSEG BIG/M6Z/E3/F1BOOTOK, 0 FAILED), md5
    `5e87d941e436cd29769959d0711c21e2`. **Déviation ASSUMÉE** : curseur d'ExNext dans le lock (pas dans le FIB comme le
    vrai OS) → un lock = une énumération (suffisant pour le harnais, documenté).
  - **Streaming OFS RÉEL FAIT** (dette levée). `ofs.s`/`handler.s`/`ofs.i`. Le handler DF0: ne bufferise PLUS le
    fichier entier à FINDINPUT : primitives `ofs_stream_open`/`ofs_stream_read`/`ofs_stream_seek`, un état SS_* par
    FileHandle (1 AllocMem = champs + ioreq + block buffer 512 o) avec curseur {byte_size, pos, first_data, cur_block,
    blk_base}. Lecture incrémentale data-block par data-block (empreinte O(1) = 512 o au lieu de O(taille)) ; « dumb
    seek » (rewind si cible en arrière, la marche avant est faite par la boucle de READ). Plus AUCUN cap de taille
    (`HND_FILEMAX` retiré du handler ; `DOS_FILEMAX` reste pour LoadSeg). `ofs_read_file`(D1)+`dos_loadseg`(D2) intacts.
    Preuve **OFS STREAM OK** : `d3j_client` ouvre « BigData » (48000 o > ancien cap 32 Ko, 99 data blocks), lit tout en
    chunks de 4096 (12 Read) → total==48000 + sentinelle $B16B00B5 + Seek(500) cross-block == $A5EE3780. Auto-suffisant
    (l'ancien code aurait tronqué à 32 Ko). RED `STREAM_CAP32K` (re-plafonne 32 Ko → BigData tronque → absent ; <32 Ko
    verts). Fichier `tests/mk_bigdata.py` ajouté à l'ADF sans perturber le layout (blocs 10/11 vérifiés).
  - **Atomicité Forbid au point de préemption FAIT** (bug PRÉ-EXISTANT révélé par le streaming). `interrupts.s`. Le
    chemin de préemption (`intr_isr_defer`, tail int2/int3/int6) consommait `EB_ATTNRESCHED` (posé avant le Forbid par
    un quantum périmé, ou par `exec_Signal` d'une tâche prioritaire pendant le Forbid) et switchait à la sortie d'IRQ
    en ne testant QUE le bit S — PAS `EB_TDNEST`. Donc une tâche sous Forbid pouvait être préemptée en plein `ser_puts`
    → marqueurs entrelacés (le streaming a allongé les fenêtres d'émission → collision visible D3B/DOS-IOERR). Fix :
    garde `EB_TDNEST`/`EB_IDNEST` dans `intr_isr_defer` (si Forbid/Disable actif → pas de dispatch différé ; AttnResched
    reste pending → consommé au prochain IRQ non-forbidden ou par le yield volontaire de Permit via `trap #1`, non gardé).
    Preuve DÉTERMINISTE **FORBID ATOMIC OK** (task_fa pri 3 : Forbid → Signal(task_fb pri 7) → attend 2 VBlanks sous
    Forbid → fb n'a PAS préempté). RED `SCHED_NO_FORBID_GATE` (retire la garde → fb préempte → absent ; M3F LIVE reste
    vert). ⚠️ Corrige la croyance « ser_lock = atomicité totale » (c'était de la séparation temporelle). **Reste différé** :
    sortir le harnais du chemin de boot (`make kick-prod`).
- **E — CLI interactif (sur série, via FileHandles DOS).** Décision archi (advisor + firewall) : le canal IO est la
  SÉRIE (tout le harnais de preuve est série ; pas de console.device/keyboard ; « Bootstrap réel » = là où vivent
  console.device/keyboard/requesters). Le CLI fait TOUT son IO via des FileHandles DOS (`pr_CIS`/`pr_COS`) servis par
  un process **handler console-série** (même forme que `dos_handler_df0`) — en F on remplace ce handler par un
  console.device sans toucher au shell. Prérequis prouvé : **spike RX** (FS-UAE livre l'entrée série hôte→Paula via
  SERDATR bit 14 RBF ; harnais `tests/boot_test_interactive.sh` injecte dans `ser_cap`). Décomposé E1→E3 :
  - **E1 — handler console-série (FAIT).** `src/dos/conhandler.s` : process servant `FINDINPUT`(open)/`WRITE`(émet
    sur série, poll TBE borné)/`READ`(lit une ligne depuis RX avec écho)/`END`. READ bloque PROPREMENT via poll sur
    tick timer.device MICROHZ (BeginIO TR_ADDREQUEST + Wait, précédent `task_timer`) — PAS de busy-poll (COOP-safe),
    PAS d'interrupt RBF niveau-5 (différé F, cf. M7k). Monté comme port global `DOS_CONPORT`. Preuves : **WRITE +
    packets** dans les 4 scénarios standard (handler en Wait = idle propre sans entrée) : GREEN « E1 CON WRITE OK » +
    non-rég D1/D2/D3A/D3B/D3C/D3D/M3F (0 FAILED) + RED `E1_NO_WRITE` (marqueur absent, round-trip intact) +
    CTRL-NODISK (console marche SANS disque) + COOP. **READ** prouvé en harnais interactif : injecter « hello\r » →
    « E1 CON READ=hello » (round-trip RX→handler→ligne→écho→client). checksum GREEN `ad9f0f37`.
    PROCHAIN : E2 (process shell : boucle prompt → read ligne → parse → dispatch + builtins).
  - **E2 — shell interactif (FAIT).** `src/dos/shell.s` : `shell_main` = process qui ouvre la console (handler E1 via
    DOS packets), émet une bannière, boucle invite `> ` → read ligne → parse 1er mot → dispatch. Builtins `ver`
    (bannière de version) et `echo <args>` (ré-émet les args) ; sinon `?`. Remplace le client de preuve E1 comme
    consommateur UNIQUE de la console (une seule console série = un lecteur à la fois) ; le handler E1 est réutilisé
    tel quel. PAS de CLI BCPL (pr_CLI/Execute = F). Preuves : GREEN « E2 SHELL READY » + non-rég D1/D2/D3*/M3F (4
    scénarios) ; interactif : « ver\r » → « E2 SHELL ver OK » (parse+dispatch), « echo E2ECHOOK\r » → « E2ECHOOK » ;
    RED `E2_NO_DISPATCH` (« ver » → « ? », marqueur absent) ; NODISK (bannière sans disque) ; COOP. checksum GREEN
    `aa9e1b78`. PROCHAIN : E3 (commande inconnue → load+run DF0: via dos).
  - **E3 — exécuter une commande externe tapée (FAIT ; CLÔT E).** La branche « commande inconnue » du shell null-termine
    le 1er mot et appelle `sh_exec_cmd` : `OpenLibrary(dos)` → `Open`/`Read` du nom depuis DF0: (packets → OFS handler →
    trackdisk) → `ls_load_hunks` → reloc → `JSR` au seglist → `UnLoadSeg` ; renvoie « trouvée » (sinon le shell émet
    « ? »). Même pile que D3d mais déclenchée par le NOM TAPÉ. Commande de test `tests/cmd_e3.s` (hunk, écrite « e3cmd »
    sur l'ADF) émet « E3 CMD RAN OK ». Preuve : injecter « e3cmd\r » au shell → « E3 CMD RAN OK » (chaîne complète
    taper → charger du disque via dos → reloc → run). RED `E3_NO_EXEC` (chargée mais saute le JSR → marqueur absent,
    pas de « ? » car trouvée) ; « bogus\r » → « ? » (introuvable) ; GREEN-standard/NODISK/COOP (bannière + non-rég).
    **Cible « CLI interactif » ATTEINTE** : la ROM présente une invite, lit des commandes tapées, dispatche des
    builtins ET charge+exécute des commandes externes depuis le disque. E CLÔT.
  - **NE PAS** construire en E : BCPL `CommandLineInterface`/`pr_CLI`, `Execute()`, startup-sequence → Bootstrap réel (F).
- **F — Bootstrap réel.** Faire du boot un VRAI bootstrap : l'Initial CLI est créé PAR LE CHEMIN DE BOOT, gaté sur un
  disque bootable (pas un process démo), et exécute une startup-sequence avant l'invite. Décision archi (advisor) : la
  ligne F vs « E4 » = **le gating sur le boot**, pas le fait de lire un fichier. Décomposé :
  - **F1 — Initial CLI + startup-sequence (FAIT).** Le shell (`shell_main`) n'est plus créé inconditionnellement dans
    `setup_demo_tasks` : il est créé dans la branche `.m6r_booted` de boot.s (APRÈS `strap_boot`, SEULEMENT si un disque
    bootable est présent ; sur un disque non bootable → M6R insert-disk, AUCUN Initial CLI). Le shell exécute d'abord
    `sh_run_startup` : `Open`/`Read` « startup-sequence » (RACINE du disque ; sous-rép `s/` différé, déviation documentée)
    via dos, puis `sh_dispatch_line` (extrait de la boucle) sur chaque ligne (builtins + commandes externes, lignes vides
    et « ; » ignorées), PUIS passe à l'invite interactive. Script de test (racine ADF) : `echo F1BOOTOK` + `e3cmd`. Preuve :
    GREEN (ADF bootable, script auto-exécuté sans injection) → « M6Y » + « F1BOOTOK » + « E3 CMD RAN OK » + « E2 SHELL
    READY » + non-rég + 0 FAILED ; **GATING** (CTRL-NODISK) → « M6R » insert-disk, « E2 SHELL READY » ABSENT (Initial CLI
    gaté) ; RED `F1_NO_STARTUP` (CLI créé mais script sauté → F1BOOTOK/E3 CMD absents, bannière présente) ; COOP.
  - **F2a — réception + décodage clavier CIA-A (FAIT).** SPIKE préalable (le spike d'injection demandé par l'advisor) :
    SANS aucun injecteur (xdotool absent, pas de session interactive), la ROM REÇOIT des octets du clavier émulé via
    CIA-A — le clavier émulé envoie sa **séquence power-up handshake au reset**. `src/exec/keyboard.s` : `kbd_selftest`
    appelé TRÈS TÔT au boot (interruptions masquées -> pas de course avec le `cia_wrapper` qui clearait le flag SP) ;
    poll borné du CIA-A (ICR bit 3 = SP), lit SDR, décode `keycode = NOT(ROR.b #1, brut)`, **handshake** (pulse CRA
    bit 6 ~75us), collecte le flux power-up. Assère `$FD` (initiate) + `$FE` (terminate) -> « F2 KBD OK ». Registres
    CIA-A : SDR=$BFEC01, ICR=$BFED01, CRA=$BFEE01 (bit 6 = SPMODE). RED `F2A_NO_HANDSHAKE` (pas de handshake -> le
    clavier stalle après 1 octet -> $FE jamais vu -> marqueur absent ; isole le handshake). Prouve la voie
    réception+décodage+handshake SANS injecteur.
  - **F2b — driver clavier LIVE interrupt-driven (FAIT).** SPIKE préalable (advisor) : `xdotool key` (XTEST sur la
    fenêtre FS-UAE sous Xvfb — PAS `--window`/XSendEvent que SDL ignore) atteint bien le clavier émulé → keycodes RÉELS
    relevés (v=$34 e=$12 r=$13 Return=$44 space=$40 a=$20 ; bit 7 = up). `kbd_install` (après M7B) : `OpenResource`
    « ciaa.resource » + `AddICRVector(bit 3 = SP)` → `kbd_interrupt` + ré-active PORTS/INT2 (coupé après la démo M7B) ;
    `ciaa_server` (resté sur la chaîne PORTS) acquitte l'ICR et route le bit 3. `kbd_interrupt` décode (F2a), handshake,
    ignore les key-up (bit 7), mappe keycode→ASCII (**keymap US minimal**, vérifiée contre les keycodes mesurés) et pousse
    dans un **ring SPSC lock-free** (producteur). `con_handler` READ draine ce ring (`con_ring_get`, consommateur) EN PLUS
    du RBF série → le CLI est piloté au VRAI clavier. Preuves : **E2E** (ADF bootable, `xdotool` tape « ver\r » au clavier
    émulé → écho « ver » + « E2 SHELL ver OK » ; harnais `tests/boot_test_kbd.sh`) ; GREEN non-rég + « F2B KBD OK » ;
    NODISK (install sans disque) ; COOP ; RED `F2B_NO_FEED` (handler décode mais ne nourrit pas le ring → « E2 SHELL ver
    OK » absent alors que « F2 KBD OK »/« F2B KBD OK » restent → câblage clavier→console load-bearing). 0 FAILED.
  - **Sous-répertoires OFS — `s/startup-sequence` réel (FAIT).** `ofs_read_file` résout désormais un CHEMIN à
    composants '/'-séparés : `ofs_split` découpe composant par composant, `ofs_dir_lookup(dir, comp)` hashe+parcourt
    la chaîne du répertoire courant (USERDIR intermédiaire -> fichier final). Détail mesuré sur l'ADF : un bloc
    USERDIR laisse `ht_size` (long[3]) à 0 -> fallback `OFS_HTDEF`=72 (= BSIZE/4-56) ; sectype USERDIR=2. Le shell
    ouvre « s/startup-sequence » (sous-rép `s/` créé par mk_boot_adf via xdftool makedir). Preuve : GREEN (F1BOOTOK
    + E3 CMD RAN OK **sourcés du sous-rép**, + D1/D3D/e3cmd = lookups racine via le même driver = non-rég, 0 FAILED) ;
    RED `OFS_NO_SUBDIR` ('/' = char normal -> chemin entier cherché en racine -> introuvable -> F1BOOTOK/E3 absents,
    D1 OFS READ OK + E2 SHELL READY intacts). Clean-room : format OFS public + ADF de test (asset). AUCUNE lecture ROM.
  - **input.device — chaîne de handlers d'InputEvents (FAIT).** `src/exec/input.s` : device résident AUTOINIT
    NT_DEVICE pri 40. `BeginIO` dispatche par io_Command : `IND_ADDHANDLER`/`IND_REMHANDLER` (Enqueue/Remove le
    struct Interrupt du handler dans la chaîne triée par LN_PRI) ; `IND_WRITEEVENT` (parcourt la chaîne : chaque
    handler reçoit a0=liste d'InputEvents, a1=is_Data, a5=is_Code, rend d0=liste pour le suivant). `IND_WRITEEVENT`
    est le point d'injection PUBLIC (celui qu'Intuition utilise) -> la preuve en isolation exerce le MÉCANISME réel,
    pas un mock. Preuve : OpenDevice (FindName) + 2 handlers pri 10/0 + `IND_WRITEEVENT` d'un RAWKEY ($34) -> « INPUT
    OK » (handlers appelés dans l'ordre de pri + keycode relayé) ; RED `INPUT_NO_PROPAGATE` (chaîne non parcourue ->
    marqueur absent, device + ADDHANDLER intacts). Le câblage clavier LIVE -> input.device -> console se fait en #3
    (console.device = consommateur naturel d'IND_ADDHANDLER ; évite de re-toucher l'INT2). Clean-room : AutoDocs
    input.device + includes NDK publics. AUCUNE lecture ROM.
  - **console.device — rendu texte (WRITE) : #3a FAIT.** `src/exec/console.s` : device résident AUTOINIT NT_DEVICE
    pri 20. `initfunc` alloue un bitplane 1-plan (chip RAM). `CMD_WRITE` interprète le flux : imprimable -> BLIT du
    glyphe 8x8 (copie CPU de 8 octets depuis `font8x8` dans le bitplane à (curx,cury)) + avance colonne ; CR -> col 0 ;
    LF/wrap -> ligne +8 (clampée, pas de scroll ce milestone). graphics.library n'ayant pas de `Text()`, le rendu est
    fait ici. **Police 8x8 HAND-AUTHORED** (domaine public, `tests/mk_font8x8.py` -> `src/graphics/font8x8.s`) —
    JAMAIS la topaz de la ROM (piège clean-room : interdit de l'extraire). Preuve = **READBACK** (headless, série) :
    on écrit une string connue puis on relit chaque cellule du bitplane et on la compare au glyphe attendu -> « CONSOLE
    WRITE OK » (valide le math d'adresse du blitter + la police, sans affichage ni Xvfb) ; RED `CON_NO_BLIT` (blit
    sauté -> readback != police -> marqueur absent). Clean-room : AutoDocs console.device + NDK public. AUCUNE lecture ROM.
  - **console.device READ via input.device : #3b FAIT.** `console.device` enregistre (à l'`initfunc`) un handler sur
    input.device via `IND_ADDHANDLER` (`console_input_handler`, struct Interrupt `CONB_INT` dans la base) : chaque
    RAWKEY key-down reçu est cuit keycode->ASCII (réutilise `kbd_keymap` de F2b) et poussé dans un **read buffer** de
    console (`CONB_RBUF` ring) ; `CMD_READ` le ressert. Preuve : `IND_WRITEEVENT` d'un RAWKEY 'v' ($34) par le chemin
    PUBLIC (celui d'Intuition) -> chaîne input.device -> handler console -> cook -> read buffer -> `CMD_READ` -> « CONSOLE
    READ=v ». La chaîne d'input.device (#2) devient ainsi **load-bearing** avec console.device comme VRAI consommateur.
    RED `CON_NO_READBUF` (handler cuit mais ne bufferise pas -> CMD_READ vide -> marqueur absent). Le FEEDER
    clavier->input.device (kbd_interrupt -> IND_WRITEEVENT depuis une tâche) est l'intégration F ultérieure (unifier
    l'entrée clavier des deux consoles via input.device) ; le clavier atteint déjà la ROM (F2b) et WRITEEVENT propage (#2).
  - **Rendu À L'ÉCRAN (#3, visuel) — différé (limite harnais).** `gfx_text_display` (Copper sur le bitplane texte via
    le pipeline graphics de M6S) écrit mais FS-UAE sous Xvfb n'affiche pas le framebuffer Amiga dans une fenêtre X
    capturable (vérifié : la capture du kitten M6S connu-bon est identique) -> pixel-verification non viable en CI
    headless. Le rendu est prouvé CORRECT par readback (#3a). Visuel = tâche graphics sur vrai display, hors CI.
  - **disk-validator OFS (#4) FAIT.** `src/dos/diskvalidator.s` : `dv_validate` valide le bitmap d'allocation de DF0: —
    (1) checksum OFS du rootblock (somme des 128 longs == 0), (2) sec_type = ST_ROOT, (3) bm_flag == $FFFFFFFF (bitmap
    marqué valide), (4) checksum OFS du bloc bitmap (bm_pages[0]), (5) COHÉRENCE : le rootblock (880) marqué ALLOUÉ
    (bit=0) dans le bitmap (idx=878 -> long[28] bit 14, LSB-first). Offsets/convention vérifiés sur l'ADF de test
    (bm_flag@312, bm_pages@316, bits 1=libre/0=alloué). Preuve : GREEN (ADF) « DISK VALID OK » ; RED `DV_CORRUPT`
    (flip d'un octet du bloc bitmap après lecture -> checksum KO -> rejet -> marqueur absent) ; NODISK -> pas de disque
    -> absent. La REVALIDATION (bm_flag=0 -> reconstruire le bitmap depuis l'arbre) est différée. Clean-room : format OFS
    public + ADF de test (asset). AUCUNE lecture ROM.
  - **keymap complet + keymap.resource + ROM AZERTY (#5) FAIT.** `src/exec/keymap.s` : `keymap.resource` résidente
    (direct-init pri 100) détient la keymap par défaut (US QWERTY, ou FR AZERTY si `KEYMAP_AZERTY=1`) et publie
    `KM_RESBASE`. `kbd_cook(keycode, qualifiers) -> ASCII` applique **SHIFT** (table `_hi`), **CAPS** (majuscule des
    lettres), **CTRL** (char & $1F). Tables US/AZERTY HAND-AUTHORED (`tests/mk_keymaps.py` -> `src/exec/keymapdata.s`,
    96 octets lo/hi par layout) — JAMAIS la ROM. `kbd_cook` est câblé LIVE : `kbd_interrupt` suit les qualifieurs
    (shift/caps/ctrl, keycodes $60-$67 dans `KBD_QUAL`) puis cuit via `kbd_cook` ; `console_input_handler` (#3b) cuit
    via `kbd_cook(keycode, ie_Qualifier)`. Preuves : GREEN US « KEYMAP OK » (q/Q/Q via shift/caps, 1/!, ctrl-C=$03) ;
    GREEN AZERTY « KEYMAP AZERTY OK » (mêmes keycodes -> 'a', '&'/'1', 'é' -> prouve que la table pilote la cuisson) ;
    **F2b E2E « ver » rejoué sur les DEUX ROMs** (cuisson live non-régressée) ; RED `KM_NO_SHIFT` (SHIFT ignoré ->
    marqueur absent). ROM AZERTY = `make kick` avec `KEYMAP_AZERTY=1` (-> `build/kick13-azerty.rom`). Déviation assumée :
    représentation simplifiée (2 tables + règles caps/ctrl) au lieu de la struct KeyMap V34 complète (dead-keys différés).
  - **Feeder clavier -> input.device (intégration F, item 1) FAIT.** `src/dos/feeder.s` : process (poll COOP sur tick
    timer.device MICROHZ) qui draine le **ring BRUT** du clavier (`KBD_FEEDRING`, alimenté par `kbd_interrupt` via un
    raw tap AU MÊME POINT que le push cuit -> snapshot `(KBD_QUAL<<8 | keycode)`, une seule autorité qualifieur) et
    injecte chaque frappe comme un InputEvent RAWKEY dans input.device (`IND_WRITEEVENT`) -> input.device est la SOURCE
    unique du clavier ; `console.device`'s handler cuit. Non-cassant : le ring CUIT (`KBD_RING`) + con_handler série
    restent (transitoire ; après le swap écran ils ne sont plus le chemin du shell). Preuve (self-test ifeq
    SHELL_ON_SCREEN) : taper 'v' -> « FEEDER OK=v » ; **Shift+v -> « FEEDER OK=V »** (prouve le snapshot qualifieur +
    le cook shift via le feeder) ; RED `FEEDER_NO_WRITEEVENT` (pas d'injection -> marqueur absent) ; F2b E2E « ver »
    non-régressé. Mécanisme : timer-poll (pas de Signal depuis l'ICR CIA). Clean-room : AutoDocs input/timer. AUCUNE lecture ROM.
  - **Swap écran du shell (intégration F, item 2) FAIT.** Réalisé par GATING de `con_handler` avec `SHELL_ON_SCREEN`
    (pas de nouveau handler ni de repoint : `DOS_CONPORT` reste `con_handler`, qui devient le handler ÉCRAN). Flag=1 :
    WRITE rend le buffer à l'écran via `console.device CMD_WRITE` (#3a) **+ miroir série inconditionnel** (canal de
    preuve) ; READ source `console.device CMD_READ` (clavier via le feeder -> input.device -> console.device) au lieu du
    `KBD_RING` cuit, avec écho écran+série et discipline de ligne (CR/LF). Le binaire shell est INTACT (IO via
    FileHandles DOS). Preuve : (b) GREEN SHELL_ON_SCREEN=1 -> taper « ver » -> « E2 SHELL ver OK » (miroir série ;
    le shell est piloté par le clavier via feeder->input.device->console.device) ; (c) RED SHELL_ON_SCREEN=1 +
    FEEDER_NO_WRITEEVENT=1 -> input coupé au feeder -> « E2 SHELL ver OK » ABSENT (E3 CMD RAN OK présent = boot/shell
    intacts) -> DISCRIMINE que l'input du shell passe bien par le nouveau chemin ; (a) flag off -> con_handler série
    inchangé (contrôle). ROM écran = `make kick` avec `SHELL_ON_SCREEN=1`. Rendu écran prouvé CORRECT par le readback
    #3a (console.device CMD_WRITE) ; le pixel à l'écran reste non-capturable headless (cf. [[console-keymap-screen-harness]]).
  - **Requester Intuition « insert disk » cliquable FAIT.** `src/intuition/requester.s` : struct Requester + struct
    Gadget (layout NDK : LeftEdge/TopEdge/Width/Height/GadgetType) ; `req_hittest(x,y)` = hit-test de la box ABSOLUE
    du gadget (le cœur du « cliquable ») ; `req_input_handler` enregistré sur input.device -> sur un clic BOUTON
    GAUCHE (IECLASS_RAWMOUSE, ie_Code==IECODE_LBUTTON) hit-teste ie_X/ie_Y et pose `REQ_HIT` ; `req_draw` rend le
    requester (bord haut/bas + texte « INSERT DISK » + label « RETRY » via la police 8x8) dans un bitplane. Preuves :
    **REQUESTER DRAWN OK** (readback : bord haut + glyphe 'I' == font8x8) ; **REQUESTER CLICK OK** (IND_WRITEEVENT d'un
    RAWMOUSE DANS le gadget -> hit ; HORS -> miss) ; RED `REQ_NO_HITTEST` (hit-test coupé -> CLICK absent, DRAWN intact).
    Preuve du clic = chemin PUBLIC IND_WRITEEVENT (comme console.device). Souris matérielle + câblage M6R live désormais
    FAITS (entrée gameport.device ci-dessous). Clean-room : NDK intuition.i + inputevent.i + police hand-authored. AUCUNE lecture ROM.
  - **gameport.device (souris matérielle) + câblage M6R live FAIT.** `src/exec/gameport.s` (device résident AUTOINIT
    NT_DEVICE pri 60) + `src/intuition/pointer.s`. Souris non observable headless (deltas JOY0DAT RELATIFS + pas de
    mouvement injectable + framebuffer invisible) -> on FACTORISE la logique pure du shim matériel. `gp_delta8(cur,prev)` :
    delta signé avec wraparound 8 bits (`sub.b`+`ext.w`, les compteurs quadrature wrappent). `gp_poll(JOY0DAT,CIAA_PRA)` :
    dx/dy via gp_delta8, edge-detect du bouton gauche (CIAA PRA bit 6 actif-bas), et si mouvement/front -> InputEvent
    RAWMOUSE ($68 down / $E8 up / $FF mouvement) injecté dans input.device via IND_WRITEEVENT (pattern du feeder clavier ;
    pas d'input.task, déviation documentée). `gp_vblank_server` : shim matériel mince (lit les vrais registres -> gp_poll),
    enregistré par `gp_install` sur la chaîne VERTB du système tournant = câblage LIVE persistant (pendant du feeder clavier) ;
    `GP_PREV_JOY` primé à la lecture courante (évite le parasite frame 1). `pointer_input_handler` (intuition, pri 50 > requester 0) :
    accumule les deltas RELATIFS en position ABSOLUE `PTR_X/PTR_Y` clampée écran et réécrit ie_X/ie_Y -> le `req_input_handler`
    (pri 0, INCHANGÉ) hit-teste en absolu = le câblage live. Preuves : **GAMEPORT OK** (gp_delta8 wraparound + edge bouton +
    event capturé via IND_WRITEEVENT) ; **M6R LIVE OK** (deltas RAWMOUSE relatifs -> accumulateur -> position absolue clampée
    -> hit-test gadget : sur le gadget->hit, hors->miss) ; **GP VBLANK LIVE OK** (gp_vblank_server tourne sur les VBlanks RÉELS
    du système tournant : GP_POLLS avance). REDs : `GP_NO_WRAP` (sub mot sans sign-extend -> delta faux au wrap -> GAMEPORT OK
    absent), `GP_NO_EDGE` (event à chaque poll tenu -> compteur edge 2->3 -> GAMEPORT OK absent), `PTR_NO_CLAMP` (pas d'écrêtage
    -> position hors écran -> hit-test rate -> M6R LIVE OK absent). Headless JOY0DAT statique -> le serveur live n'injecte rien
    (prev primé = courant) -> inerte vis-à-vis de M7 (non-rég M7A/M7E/M7F/M7G + E3 CMD RAN OK/F1BOOTOK, 0 FAILED). Clean-room :
    HRM (JOY0DAT/CIAA PRA) + NDK gameport.i/inputevent.i. AUCUNE lecture ROM. Différé : bouton DROIT (POTINP, bit flou) +
    clic réel sur écran affiché (invérifiables headless ; attendent un vrai display).
  - **À venir** : bouton droit souris (POTINP) + clic réel sur display ; keymap dead-keys/compose ; parité modules.
- **Écran de chargement (gros fichier) — DÉMO GATÉE FAITE.** `src/graphics/loadscreen.s` (flag `LOADSCREEN_DEMO`,
    lié uniquement sous `make VASMDEF=-DLOADSCREEN_DEMO=1 kick` → ROM par défaut byte-identique, zéro code mort).
    `loadscreen_demo` monte une View sur le bitplane console (352×272, stride 44) via `MakeVPort`/`MrgCop`/`LoadView`,
    écrit « Chargement <nom>... » + barre de progression (un '#' par chunk de 4 Ko) pendant un `ofs_stream_read` RÉEL,
    puis « OK ». Preuve boot FS-UAE : capture `loadscreen_final.png` (texte blanc lisible sur fond bleu nuit). DÉMO
    autonome (nom `bigseg` en dur, tient l'écran, NE REVIENT PAS) — PAS câblée dans `dos_loadseg`. **À venir (wiring live)** :
    refondre en API `begin(nom)`/`progress()`/`end()` appelée depuis `dos_loadseg` (doit RETOURNER, libérer ses allocs,
    réutiliser l'affichage courant) pour déclencher l'écran automatiquement sur un vrai chargement.
- **Trackdisk timing-exact (WinUAE) — FIX FAST FAIT** (4590cb1) + loadscreen DMA-cut (bitplane/copper coupés pendant la lecture) prouvé WinUAE. **À venir** : chargement complet du jeu Lemmings sur WinUAE (bloque ~secteur 46) → aligner la lecture sur l'officielle (fin DMA par interruption, settles 1 ms/15 ms, délai moteur fixe 500 ms).
- **Holiday Lemmings — le jeu DÉMARRE FAIT** : slow RAM `$C00000` en tête de MemList, shell à buffer taille-fichier,
    LoadSeg respectant les flags mémoire (CHIP/FAST, flags dans l'id de hunk), cache de piste trackdisk (invalidé par
    `/CHNG`). Cracktro → clic → menu du jeu prouvé sous FS-UAE ; **lancement d'un niveau confirmé par l'utilisateur**
    (2026-10-18). **À venir** : borner l'offset RELOC32 (dette loadseg).
- **Workbench 1.3.3 — étape 1 FAITE** : résolution `device:`/assign/volume/répertoire courant, assigns de boot
    (SYS: C: S: L: DEVS: LIBS: FONTS:), CLI initial avec `pr_CLI`/`pr_CIS`/`pr_COS`/`pr_ReturnAddr`, arguments,
    exceptions CPU vers `tc_TrapCode` (forme compatible SetPatch), `RawDoFmt`. `c:SetPatch` tourne en entier.
    **Étape 2 — runtime BCPL FAITE** : GV + segarray + segment runtime, ~60 globales, runcommand (pile dédiée,
    injection des arguments) ; AddBuffers, CD, Resident, Mount, Failat, Wait tournent ; **createproc + Run** : le CLI
    de fond (Shell-Seg) exécute Execute et les `resident` de StartupII. Delay bloquant (timer.device), FIB complet
    (BSTR côté packet), FileHandles getvec, getlong/putlong indexés en longs.
    **Étape 3 — handlers de device FAITE** : starthandler (112, handlers BCPL et C) + makeglobvec (13), nœud RAM,
    exec OpenDevice/DoIO/SendIO/WaitIO/CopyMem, timer GET/SETSYSTIME, DeleteFile/Rename/CreateDir ; la
    startup-sequence complète du WB 1.3.3 s'exécute (StartupII sur RAM:, break, MountMF) ; PIPE: prouvé.
    **Étape 4 — devices de DEVS:, AUX:, NEWCON: FAITE** : ramlib (LIBS:/DEVS:), AddDevice/AddLibrary, InitStruct
    complet, autovecteurs 1/4/5, misc.resource, GetPrefs, OpenWindow minimal, console.device asynchrone, globale
    50 ; AUX: (serial.device du disque) et NEWCON: prouvés.
    **Étape 5 — résident workbench.task FAITE** : LoadWB lance un Workbench minimal (process « Workbench », réponse
    au message de démarrage, port public) ; InitCode filtré par classe (RTF_COLDSTART) ; AddPort initialise la file.
    **Lecture disquette ×5 FAITE** (trackdisk : moteur maintenu 2 s, pas de 3 ms + 18 ms de stabilisation, cache
    LRU de 8 pistes) : boot complet WB 1.3.3 de > 400 s à 87 s. À valider sur WinUAE timing-exact.
    **Étape 6 — écran Workbench et fenêtres visibles FAITE** : graphics (primitives de dessin, Text, ScrollRaster,
    MakeVPort générique HIRES), intuition (OpenScreen/OpenWorkBench/GetScreenData, OpenWindow/CloseWindow dessinés),
    console.device rendue dans la fenêtre (ConUnit, CSI, défilement, curseur), dos Open("*"), packets alignés,
    fl_Volume ; NewShell ouvre une fenêtre AmigaShell utilisable au clavier.
    **Étape 7 — AmigaSlopDOS au démarrage et bureau FAITE** : fenêtre AmigaSlopDOS (console du CLI initial, fermée à
    endcli), thème vert pomme / texte noir, effacement et réparation sans layers + REFRESHWINDOW/IDCMP minimal,
    DrawImage (BltBitMapRastPort), AllocRemember, pointeur souris (sprites), fenêtre de fond avec l'icône du disque
    (icon.library), clic / double-clic -> fenêtre du disque et ses icônes, CLOSEWINDOW ; disquette insérée sur
    l'écran insert-disk -> redémarrage et boot.
    **M7+ et L4 FAITS** : mathffp.library, disk.resource, potgo.resource, keyboard.device, audio.device, sémaphores
    exec, regions et BltBitMap général, layers.library (simple/smart/backdrop, dommages), intuition sur layers
    (WindowToFront/Back, MoveWindow, Begin/EndRefresh) ; écrasement mémoire latent du lancement des commandes BCPL
    corrigé (pile du shell trop courte d'un long).
    **Étape 8 (interaction) FAITE** : tiroirs imbriqués, lancement d'outils et de projets (WBStartup ; Shell -> AmigaShell),
    menus Workbench (Open/Close/Redraw) et menus intuition au bouton droit, déplacement et redimensionnement des fenêtres
    (SizeWindow, WindowLimits), Execute (101), NIL:, writef tamponné.
    **Étape 9 FAITE** : polices (topaz TextFont, OpenFont & co), GELs, icônes déplaçables, CLI ROM BCPL (Run, Execute,
    NewCLI sans résident), redirections `<`/`>`, scripts d'Execute, nœuds CON/RAW (handler ROM) et SER/PAR/PRT
    (Port-Handler), clavier routé vers la fenêtre active, MOUSEMOVE/ReportMouse, fermeture de tiroir ×2 plus rapide.
    **Étape 10 (en cours)** : écriture disquette — trackdisk (CMD_WRITE/UPDATE, MFM) et écriture OFS (création,
    flux, suppression, renommage, protection, commentaire, Info) prouvées sous CLI ; dates (DateStamp réel, C:Date,
    en-têtes datés) ; AutoRequest ; Workbench Discard ; BltTemplate (FastFonts) ; performance : timer MICROHZ
    en one-shot (le timer CIA-B continu mangeait plus de la moitié du CPU), sortie console BCPL tamponnée, Text plus
    rapide, ScrollRaster plus rapide (`type` ×10, SysInfo 1,04 × A600) ; échecs de commande et FailAt comme la 1.3 (sondés sur la vraie ROM). Gadgets texte (STRGADGET, ActivateGadget),
    Workbench Rename, requester « Please insert volume » et redirections avant les arguments seulement faits. Textes d'erreur via
    C:Fault faits. Restent : défilement au blitter,
    Snapshot, Info du Workbench, lenteur de lecture des répertoires, échec intermittent de `join` (non reproduit), blocage intermittent de la ROM
    dev en début de boot (1 fois sur 7 avec SysInfo : M7F émis, puis plus rien, ni M7G ni shell ; non reproduit).
    **Intercalé — SetPatch / SysInfo (demande utilisateur 2026-10-21, avant de reprendre le Workbench)** : exec V34
    complet (SetFunction réel & 33 autres LVO), shell qui respecte `cli_Module`, relais Alert, DeleteLayer en trois
    étapes, GfxBase public V34, TOD des CIA démarrés, FileSysStartupMsg de DF0 ; SysInfo affiche toute sa page
    (horloge, Agnus/Denise, PAL, fréquences) ; gadgets d'application d'intuition (GADGETUP/DOWN, AddGadget,
    RefreshGadgets…) : ses boutons fonctionnent (SPEED). Ouverts : gadgets PROP/STRING, disquettes Caesar / Scooby-Doo / bootdisk-amiga-m68k de la suite ADF. Chaque fin d'étape : `tests/adf_suite.sh`
    sur les disquettes de `assets/test_adf/`.
    **Ensuite** : `SetFunction`, NIL:/redirections, LoadWB (workbench, icon.library, layers).
- **M7+ — longue traîne** : layers, console, input, audio, gameport, mathffp, workbench.task, parité ;
  puis **EPROM vraie A500** (ROM 256K, câblage/adaptateur).

## Travail exécutable immédiat (début d'implémentation, à l'approbation)

M0 et M1 démarrent **en parallèle** (pistes étanches) :
1. Scaffolder le dépôt + `git init` + `docs/CLEANROOM.md` (la discipline ci-dessus).
2. Copier la ROM en lecture seule dans `assets/` ; revérifier les empreintes.
3. Installer/épingler vasm+vbcc+vlink (+ bebbo gcc au besoin) ; produire la **hello-ROM** 256K et la
   booter en émulateur (FS-UAE+Xvfb).
4. Monter le banc de test : boot scripté + capture d'état ; diff oracle via `romtool`.
5. Lancer la piste analyse (agent dédié ROM+radare2) sur la séquence de boot et la spec exec.

## Vérification (bout en bout)

- **Intégrité ROM** : `md5sum`/`sha1sum` de la copie == empreintes connues ; `romtool info` valide
  header/checksum/taille de toute image produite.
- **Canal d'assertion primaire** : **log série (`SERDAT`) capturé** par l'émulateur — déterministe,
  greppable, CI-friendly ; chaque milestone émet des marqueurs série vérifiés. L'affichage (couleur
  `$DFF180` → écran → main « insert disk » → CLI) est un signal secondaire, pas la base des assertions.
- **Boot émulateur** : hello-ROM puis chaque milestone bootent sous FS-UAE/WinUAE scripté. CI via Xvfb.
- **Oracle boîte noire** : comparer le comportement observable de notre ROM à la vraie KS 1.3 dans
  l'émulateur via des **sondes comportementales ciblées → vecteurs de test** (piste analyse), jamais en
  recopiant son code ni par un diff système global.
- **Tests hôte** : recouper la sémantique d'API *documentée* et exécuter des binaires de test sous
  `vamos` (pas pour héberger notre exec).
- **Syntaxe/build** : asm/C vérifiés au build (toolchain 68k — pas de `py_compile`).

## Faits confirmés (recherche) — sources principales

- vasm/vlink `sun.hasenbraten.de` · bebbo `codeberg.org/bebbo/amiga-gcc` · amitools romtool
  `amitools.readthedocs.io/en/latest/tools/romtool.html` · checksum `cloanto.com/amiga/roms/help/checksum.html`.
- AROS `github.com/aros-development-team/AROS` ; APL `en.wikipedia.org/wiki/AROS_Public_License` ;
  68k support `en.wikibooks.org/wiki/Aros/Platforms/68k_support`.
- Docs : NDK 3.2 (Aminet `dev/misc/NDK3.2R4`, Hyperion) ; RKRM/AutoDocs `amigadev.elowar.com`.
- BCPL/dos : `en.wikipedia.org/wiki/AmigaDOS` ; AROS ABIv1 DOS draft (sourceforge). Art connexe : ARP,
  BootWB1x/HelloAmi, BlizKick.
- Émulateurs : `fs-uae.net/docs/kickstart-roms/` ; WinUAE headless (forum, à valider).

## À vérifier sur machine à l'exécution (hérité de la recherche)

- `romtool build` écrit-il le checksum ou faut-il `copy -c` en 2e passe (`romtool info` pour comparer).
- Clés de config exactes WinUAE (`kickstart_rom_file`, `-s use_gui=no`) sur la version installée.
- Licences réelles NDK 3.2 / RKRM avant toute redistribution de doc dérivée.
- Modèle BPTR/packets exact d'AROS `rom/dos/` au moment d'attaquer M6.
- Boot d'une config A500/68000 sous UAE pour cadrer les contraintes mémoire minimales.
- Disponibilité de références **1.x** : RKRM 1re édition + `.fd`/includes 1.x (jeux de LVO corrects V34).
- Capacités réelles de `vamos` (ce qu'il peut/ne peut pas tester vis-à-vis de notre propre code).
