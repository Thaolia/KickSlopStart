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
  comportement OS observable (timer+interruption+messages+`exec_Signal` depuis l'IRQ). Reste :
  **dispatch CIA INT2/INT6** (M6b), tâche bloquant sur timer (Wait→wake), retrait éventuel des démos
  (le handoff de boot reste la démo M3f codée en dur d'ici là), dispatcher par niveau, tâches
  user-mode, quantum/priorité.
- **M3 — resources & timing** : `cia.resource`, `timer.device`, `misc`/`potgo`/`disk.resource`,
  `keymap.resource` ; plomberie d'interruptions (VBlank déjà en place depuis le bringup exec).
- **M4 — graphics.library + affichage minimal** : Copper/Blitter/View suffisants pour afficher.
- **M5 — intuition minimal → écran « insert Workbench disk »** (la main iconique du boot KS 1.3).
- **M6 — dos + trackdisk + FS + strap/romboot → boot disquette jusqu'au CLI.** La `dos.library` 1.3 est
  un portage **BCPL/TRIPOS** : il faut répliquer les quirks d'ABI (**BPTR** word-based, global vector,
  convention d'appel BCPL, **DOS packets**, segments `LoadSeg`). Approche retenue = **réécriture ANSI C
  en conservant `BPTR`/packets** (ce qu'ont fait AROS `rom/dos/` — à lire — et Commodore en 2.0).
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
