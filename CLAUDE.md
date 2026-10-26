# CLAUDE.md — OS opérationnel (Kickstart 1.3 clean-room)

Mission : réimplémenter un Kickstart **compatible 1.3** (256K @ `$FC0000`, 68000) en salle blanche.
Roadmap → `docs/PLAN.md`. Architecture → `docs/ARCHITECTURE.md`. Discipline → `docs/CLEANROOM.md`.

## Firewall clean-room — RÈGLE ABSOLUE

- Deux pistes **étanches**. Ne JAMAIS écrire du code `src/` en te basant sur le désassemblage de la ROM.
- Piste **ANALYSE** (« dirty ») : lit la ROM (`assets/`, radare2/ghidra), écrit UNIQUEMENT dans
  `docs/analysis/`. Décrit comportement + layout d'ABI ; jamais de suites d'instructions recopiées.
- Piste **IMPLÉMENTATION** (« clean ») : lit les docs publiques (RKRM/NDK/AutoDocs/`.fd`), AROS
  (`third_party/`, lecture seule) et `docs/analysis/` ; écrit `src/`. Ne lit JAMAIS la ROM ni son désassemblage.
- Avant qu'une spec d'analyse n'alimente l'implémentation : relire qu'elle ne contient **aucun code transcrit**.
- La ROM propriétaire n'est JAMAIS committée (gitignore) ni modifiée (elle est en `chmod 444`).

## Routage : quand déléguer à un agent dédié

- Toute tâche d'**analyse ROM** → un agent « analyse » séparé, pour préserver le mur. Ne mélange pas
  analyse et implémentation dans le même contexte.
- L'implémentation d'un module peut être inline, mais son contexte ne doit contenir que specs + docs publiques.

## Build / test (référence)

- `make hello` → `build/kick13-hello.rom` · `make verify` (romtool `is_kick`) · `tests/boot_test.sh` (boot FS-UAE).
- Suite ADF de fin d'étape : `tests/adf_suite_winuae.sh` (WinUAE Linux A500 cycle-exact, cf. `docs/HARDWARE.md`).
- Toolchain requise dans le PATH : `vasmm68k_mot`, `vlink`, `romtool` (amitools), `python3`, `fs-uae`, `Xvfb`.
- Vérif syntaxe asm = le build `vasm` lui-même (pas de `py_compile`). Python lisant des données : `python3 -I`.

## Conventions de code

- Commentaires en **français**. Assembleur en syntaxe **vasm Motorola**, **68000 strict** (aucune
  instruction > 68000 : pas de `RESET`-only-060, pas d'adressage 020+). Code bas niveau sans pile tant
  que la RAM/overlay n'est pas configurée.
- `correctness > maintainability > performance > brevity`. Pas de code mort, pas de variable inutile.
- Pas de commentaire sauf si le POURQUOI est non-évident.

## Quality gate avant de déclarer « fait »

- Toute image ROM produite DOIT passer `romtool info` (**is_kick = ok**) avant d'être testée.
- Milestone de comportement : prouvé par un **boot FS-UAE** (écran et/ou marqueur série capturé),
  jamais « supposé ». Consigner le résultat (commande + sortie) dans le ledger `.superpowers/sdd/`.

## Après tout changement significatif

- Mettre à jour `docs/ARCHITECTURE.md` et `docs/PLAN.md` dans la MÊME session.
