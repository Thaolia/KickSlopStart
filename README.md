# amiga_kickstart_reverse — Kickstart 1.3 open-source (A500), méthode salle blanche

Réimplémentation open-source, **clean-room**, d'un Kickstart compatible **AmigaOS 1.3** : image ROM
**256 KiB, 68000, chargée à `$FC0000`**, visant un remplacement « drop-in » de la Kickstart 34.5
(A500/A1000/A2000), bootable d'abord en émulateur puis sur vraie Amiga 500.

## Statut

| Milestone | État |
|-----------|------|
| **M0** — fondations + hello-ROM | ✅ **fait et vérifié** (build `romtool is_kick=ok` + boot FS-UAE écran vert) |
| **M1** — spec de boot (piste analyse) | en cours |
| **M2+** — exec.library puis le reste | à venir (voir `docs/PLAN.md`) |

## ⚠️ Légal / clean-room

Ce dépôt **n'inclut pas** et **ne distribue pas** la Kickstart propriétaire. Pour l'analyse et les
tests oracle, place **ta propre copie** de `kick34005.A500` (256K, md5 `82a21c18…`) dans `assets/`
(fichier gitignoré). La méthode salle blanche est décrite dans `docs/CLEANROOM.md` : le désassemblage
ne sert qu'à **comprendre et tester** ; le code publié s'écrit **uniquement** depuis des docs
publiques (RKRM / NDK / `.fd`) + AROS (référence lecture seule).

## Build & test (hello-ROM M0)

Prérequis : `vasmm68k_mot` + `vlink` dans le PATH, **amitools** (`romtool`), `python3`, **FS-UAE** + **Xvfb**.

```sh
make hello            # -> build/kick13-hello.rom (vasm -> mkrom.py)
make verify           # taille 256K + romtool info (is_kick = ok)
tests/boot_test.sh    # boot headless FS-UAE + contrôle écran vert
```

Installation de la toolchain (vasm/vlink se compilent depuis les sources) : voir `docs/HARDWARE.md`.

## Arborescence

```
src/            implémentation (piste CLEAN) — src/rom/ : hello-ROM (start.s) + mkrom.py
docs/           PLAN.md · CLEANROOM.md · ARCHITECTURE.md · HARDWARE.md · analysis/ (piste DIRTY)
tests/          harness émulateur (boot_test.sh)
assets/         TA copie de la ROM (gitignorée, lecture seule)
build/          artefacts (gitignoré)
third_party/    AROS en référence lecture seule (non vendoré pour l'instant)
```
