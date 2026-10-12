# Architecture

## Modèle de ROM (Kickstart 1.3, 256K)

- Image de **262 144 octets**, chargée à **`$FC0000`** (mappée aussi à `$0` au reset via l'overlay OVL).
- En-tête de reset aux 8 premiers octets : longword `$0` = SSP initial (`0x11114EF9`, mot ROM-ID
  `0x1111` + opcode `0x4EF9`), longword `$4` = PC initial = adresse de coldstart (`$FC00D2` sur une
  ROM authentique ; instruction `RESET` `$4E70` à `$FC00D0`).
- Footer (format conteneur, cf. amitools) : checksum longword à `taille-0x18`, champ taille à
  `taille-0x14`, 8 mots `0x0018..0x001F` à `taille-0x10`. Checksum valide = somme des longwords
  (retenue repliée) égale à `0xFFFFFFFF`. **Non vérifié par l'OS avant la V37**, mais exigé par les outils.

## Modules résidents (ROMTags)

L'OS se construit par un scan de modules résidents (struct `Resident`, matchword `0x4AFC`) dans
l'ordre de **priorité décroissante**. Les 24 modules de la 34.5 et le détail d'ABI sont dans
`docs/analysis/` (piste analyse). Résumé de l'ordre d'init :

`exec`(120) → `expansion`(110) → `potgo`/`keymap`(100) → `cia`(80) → `disk`/`misc`/`ramlib`(70) →
`graphics`(65) → `keyboard`/`gameport`(60) → `timer`(50) → `audio`/`input`(40) → `layers`(31) →
`console`/`trackdisk`(20) → `intuition`(10) → `alert.hook`(5) → `mathffp`/`workbench.task`/`dos`(0) →
`romboot`(-40) → `strap`(-60).

## Structure `src/` (piste clean)

| Dossier | Contenu prévu |
|---------|---------------|
| `src/rom/` | En-tête/reset, assemblage image (hello-ROM M0 : `start.s` + `mkrom.py`) ; linker script vlink dès M2 |
| `src/exec/` | exec.library : ExecBase, mémoire, listes, libs/devices, tâches, signaux, ports, interruptions, `InitResident` |
| `src/resources/` | cia, disk, misc, potgo, keymap |
| `src/devices/` | timer, keyboard, gameport, input, audio, console, trackdisk |
| `src/libs/` | expansion, graphics, layers, intuition, mathffp, dos |

## Pipeline de build

1. `vasmm68k_mot -Fbin` assemble chaque source en binaire placé à son adresse absolue.
2. (dès M2) `vlink` lie/place les modules relogeables et génère l'image brute.
3. `src/rom/mkrom.py` complète à 256K, écrit footer + champ taille + checksum.
4. `romtool info` valide le conteneur (`is_kick = ok`).
5. `tests/boot_test.sh` boote l'image sous FS-UAE et contrôle l'écran (puis le série dès M2).

## État

M0 (hello-ROM) livré et vérifié. Voir `docs/PLAN.md` pour la suite et `docs/CLEANROOM.md` pour le mur.
