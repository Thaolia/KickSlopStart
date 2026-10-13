# amiga_kickstart_reverse — Kickstart 1.3 open-source (A500), méthode salle blanche

Réimplémentation open-source, **clean-room**, d'un Kickstart compatible **AmigaOS 1.3** : image ROM
**256 KiB, 68000, chargée à `$FC0000`**, visant un remplacement « drop-in » de la Kickstart 34.5
(A500/A1000/A2000), bootable d'abord en émulateur puis sur vraie Amiga 500.

## Statut

| Milestone | État |
|-----------|------|
| **M0** — fondations + hello-ROM | ✅ **fait et vérifié** (build `romtool is_kick=ok` + boot FS-UAE écran vert) |
| **M1** — spec de boot (piste analyse) | ✅ fait (4 specs clean-room dans `docs/analysis/`) |
| **M2.0** — exec coldstart + squelette ExecBase | ✅ **fait et vérifié** (boot → écran blanc, auto-vérification ExecBase) |
| **M2.1/M2.2** — jump table LVO V34 (105 vec.), fonctions exec, allocateur + coalescing | ✅ **fait et vérifié** (auto-test via jump table → blanc) |
| **M2.3** — découpage en modules (`src/exec/*.s`) + vlink | ✅ **fait et vérifié** (relink vlink, boot blanc inchangé) |
| **M2.4** — multi-MemHeader, listes (Enqueue…), tâches+signaux+ports (non bloquants) | ✅ **fait et vérifié** (auto-test → blanc ; ordonnancement réel = M3) |
| **M3a** — plomberie d'interruptions (VBlank armé) | ✅ **fait et vérifié** (série « VBlank interrupts live » ; RED→GREEN) |
| **M3b** — ordonnanceur préemptif (switch de tâches superviseur) | ✅ **fait et vérifié** (2 tâches alternent sur le série, contexte préservé) |
| **M3c** — exclusion mutuelle : `Forbid()` honoré par le scheduler + sections critiques exec enveloppées | ✅ **fait et vérifié** (série « M3C LIVE » ; RED garde Forbid → `FAILED`, RED Permit manquant → selftest échoue) |
| **M3d** — `Wait`/`WaitPort` + réveil-sur-signal (switch synchrone, blocage réel d'une tâche) | ✅ **fait et vérifié** (série « M3D LIVE » ; ping-pong 2 ports ; RED réveil cassé → deadlock, RED blocage cassé → `FAILED`) |
| **M3e** — yield immédiat sur `Permit`/`Enable` (reschedule synchrone vers une réveillée prioritaire) | ✅ **fait et vérifié** (série « M3E LIVE » ; démo coopérative pri 10/0 ; RED yield désactivé → starvation franche) |
| **M3f** — recombinaison yield + préemption (switchs unifiés, coexistence sans corruption) | ✅ **fait et vérifié** (série « M3F LIVE » ; 3 tâches `SCHED_ON=1` + sentinelles de contexte ; RED préemption off → starvation) |
| **M4** — scan des résidents (ROMTags) + `FindResident`/`InitResident`/`InitCode` | ✅ **fait et vérifié** (série « M4 RESIDENTS OK » ; 3 résidents démo initialisés en ordre de priorité ; RED tri cassé / dispatch cassé → `FAILED`) |
| **M5a** — AUTOINIT : `MakeLibrary` + `MakeFunctions` + `InitStruct` (chemin AUTOINIT de `InitResident`) | ✅ **fait et vérifié** (série « M5A AUTOINIT OK » ; lib démo créée, jump table + InitStruct + init func + ajout LibList ; RED InitStruct/init cassés → `FAILED`) |
| **M5b/M5c** — `cia.resource` (direct-init) + `timer.device` (AUTOINIT) = premiers vrais résidents | à venir (voir `docs/PLAN.md`) |
| **M5+** — dispatcher par niveau, upgrade ports→Disable, user-mode, graphics, dos | à venir |

## ⚠️ Légal / clean-room

Ce dépôt **n'inclut pas** et **ne distribue pas** la Kickstart propriétaire. Pour l'analyse et les
tests oracle, place **ta propre copie** de `kick34005.A500` (256K, md5 `82a21c18…`) dans `assets/`
(fichier gitignoré). La méthode salle blanche est décrite dans `docs/CLEANROOM.md` : le désassemblage
ne sert qu'à **comprendre et tester** ; le code publié s'écrit **uniquement** depuis des docs
publiques (RKRM / NDK / `.fd`) + AROS (référence lecture seule).

## Build & test (hello-ROM M0)

Prérequis : `vasmm68k_mot` + `vlink` dans le PATH, **amitools** (`romtool`), `python3`, **FS-UAE** + **Xvfb**.

```sh
make                  # -> build/kick13.rom  (ROM principale : exec coldstart)
make verify           # taille 256K + romtool is_kick=ok
tests/boot_test.sh    # boot headless FS-UAE ; assertion sur le LOG SÉRIE (marqueur
                      #   « self-test passed ») capturé via un pont PTY socat ;
                      #   repli couleur si aucune émission série. -> build/boot/serial.log
make hello            # -> build/kick13-hello.rom (smoke test M0)
tests/boot_test.sh build/kick13-hello.rom 10 00FF00 HELLO   # test hello (marqueur « HELLO »)
```

Le log série émet des **checkpoints** (`chk core` → `chk mem` → `chk m24a/b/c` →
`self-test passed`) : en cas d'échec, le dernier checkpoint capturé localise le groupe fautif.
Prérequis supplémentaire pour le série : `socat`.

Installation de la toolchain (vasm/vlink se compilent depuis les sources) : voir `docs/HARDWARE.md`.

## Arborescence

```
src/            implémentation (piste CLEAN) — src/exec/ : exec.library modulaire (exec.i + boot/lists/memory/library.s + kick.ld) · src/rom/ : hello-ROM (start.s) + mkrom.py
docs/           PLAN.md · CLEANROOM.md · ARCHITECTURE.md · HARDWARE.md · analysis/ (piste DIRTY)
tests/          harness émulateur (boot_test.sh)
assets/         TA copie de la ROM (gitignorée, lecture seule)
build/          artefacts (gitignoré)
third_party/    AROS en référence lecture seule (non vendoré pour l'instant)
```
