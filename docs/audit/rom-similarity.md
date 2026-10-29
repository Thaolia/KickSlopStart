# Audit de similarité binaire : notre ROM face au Kickstart 1.3 d'origine

Ce document répond à une question précise : **notre ROM contient-elle du code repris du Kickstart
Commodore**, par exemple via une mémorisation des sources Kickstart qui ont fuité ? La mesure compare
l'image binaire que nous distribuons à la vraie ROM 1.3, puis situe le résultat par rapport au niveau
« normal » des coïncidences entre programmes 68000 sans lien entre eux.

Le rapport ne contient **rien de la ROM d'origine** : ni octets, ni désassemblage, ni offset. Les
correspondances sont localisées uniquement dans **notre** ROM.

## Verdict

- **Aucune suite de code de notre ROM ne coïncide avec la ROM d'origine au-delà de ce que des
  programmes sans lien partagent déjà avec elle.** La plus longue correspondance de code de notre ROM
  fait **20 mots de 16 bits (13 instructions)**. Un corpus de jeux et d'utilitaires tiers sans rapport
  avec Commodore va jusqu'à **39 mots (18 instructions)**.
- Les seules correspondances plus longues que cette base sont des **données imposées** :
  - six tables de vecteurs de fonctions (bibliothèques et `dos`), dont la normalisation ne garde que
    le nombre d'entrées, fixé par l'ABI ;
  - une table arithmétique de localisation de caractères (police à chasse fixe de 8 pixels), qu'on
    retrouve aussi à l'identique dans la ROM AROS.
- La méthode **détecte bien une vraie parenté** quand elle existe :
  - le code Commodore du disque Workbench 1.3.3 (commandes, handlers, bibliothèques), hors ROM mais
    issu de la même chaîne d'outils, partage avec la ROM jusqu'à 121 mots (96 instructions exactes,
    257 en mode souple) et couvre 3,8 % de son code en correspondances de 8 mots ou plus ;
  - l'auto-contrôle par copies relogées retrouve 12 fragments sur 12.
- **Aucune routine de notre code n'est à réécrire** au vu de cette mesure.

## Entrées

| rôle | fichier | taille | sha1 |
|---|---|---|---|
| notre ROM (production, distribuée) | `build/kick13-prod.rom` (`make kick-prod`) | 262 144 o | `3736299fe3bb5daf64732b349d76870b019e60d7` |
| notre ROM (dev) | `build/kick13.rom` (`make kick`) | 262 144 o | `aa2d86620eebc48188594ea50c75e41a5b72c89d` |
| référence | `assets/kick34005.A500`, Kickstart 1.3 rév. 34.5 (A500), hors dépôt | 262 144 o | `891e9a547772fe0c6c19b610baf8bc4ea7fcb785` |

Les deux ROM ont été mesurées sur les builds du 2026-10-29 (commit `ec9f9ab`). La ROM dev
contenait aussi des modifications locales en cours dans `src/intuition/`.

**Table des symboles.** Elle vient d'un nouveau lien des objets existants, sans rien recompiler, avec
la liste d'objets et le script de lien exacts du `Makefile`. Le binaire obtenu est **identique octet
pour octet** au `build/kick.bin` du build dev. Il est aussi identique aux 201 532 (dev) et 200 020
(prod) premiers octets de la ROM correspondante : `mkrom.py` ne fait qu'ajouter le remplissage et le pied
(taille, somme de contrôle, vecteurs).

**Témoins.** Leurs exécutables ont été extraits des ADF de `assets/test_adf/` avec
`xdftool <adf> unpack <dossier>`. Seuls les hunks CODE sont mesurés.

| groupe | rôle | contenu | volume de code |
|---|---|---|---|
| `tiers` | **base sans lien** (fixe le seuil) | Holiday Lemmings (`HolidayLemmings`, `flt-intro`), Monkey Island FR disque 1 (`monkey_island`, `defjam`), SimCity 1.2 (`SimCity`, `SimData3`, `ZoneEvolutionChart`, `S/RAZOR.EXE`), SysInfo (`SysInfo`, `68040.library`, `68060.library`, `mmu.library`, `c/SetPatch` récent), `c/muchmore` (domaine public, disque WB) | 596 048 o, 21 hunks |
| `commodore` | témoin de parenté (code Commodore hors ROM) | Workbench 1.3.3 : `c/*` sauf `muchmore` et `TDPatch13`, `l/*` sauf `MSDOSFileSystem`, `libs/`, `devs/*` sauf `mfm.device` et `keymaps`, `System/`, `Prefs/`, `Utilities/` | 413 374 o, 390 hunks |
| `aros` | autre réimplémentation indépendante | disque d'amorçage AROS m68k : `aros.rom.gz` (décompressé), `AROSBootstrap`, `C/*`, `Libs/*` | 1 167 084 o, 50 hunks |

Le disque Scooby-Doo n'apporte aucun exécutable hunk exploitable, le disque 4 de Monkey Island ne
contient que des données, et le système de fichiers de l'ADF Caesar est illisible par `xdftool`.
Les exécutables fournis avec les jeux (`c/` de Monkey Island, `C/`, `L/`, `LIBS/` et `Devs/` de
SimCity) sont des copies de fichiers Commodore : ils ne sont pas dans le groupe `tiers`.

## Méthode

L'outil est `tests/audit_rom_similarity.py` (Python 3, stdlib ; `capstone` facultatif pour les flux
d'instructions). Son en-tête détaille la méthode, résumée ici.

1. **Alignement sur 16 bits**, comme l'impose le 68000.
2. **Normalisation de ce qui change forcément d'un build à l'autre**, pour ne pas sous-estimer une
   copie relogée :
   - tout mot long pointant dans la ROM (fenêtre `$F80000`–`$FFFFFF`) devient le jeton `ADDR` ;
   - dans les hunks, les mots longs relogés (`HUNK_RELOC32`) deviennent aussi `ADDR` ;
   - les déplacements de `Bcc`/`BRA`/`BSR` (8 et 16 bits), de `DBcc` et des modes `d16(PC)` et
     `d8(PC,Xn)` sont effacés ;
   - les plages de remplissage (8 mots identiques ou plus) deviennent des sentinelles qui ne
     s'apparient jamais.
3. **Trois flux de jetons** :
   - `mots` : flux brut normalisé, sans décodeur, donc insensible aux désynchronisations du
     désassemblage ;
   - `instr` : désassemblage linéaire 68000 (capstone), une instruction = mnémonique + opérandes,
     avec cibles, déplacements PC et adresses ROM masqués ;
   - `instr-souple` : comme `instr`, mais registres et constantes effacés, pour résister à un
     renommage de registres.
4. **Métriques**, pour chaque paire (A, B) :
   - correspondances exactes maximales de A dans B, calculées par automate des suffixes de B :
     longueur maximale, nombre de correspondances de 8, 16 et 32 jetons ou plus, et part de A
     qu'elles couvrent ;
   - recouvrement de n-grammes (n = 4, 8, 16) : part des n-grammes distincts de A présents dans B.
5. **Classement de chaque correspondance** d'après les octets de A : texte, faible entropie, table
   d'adresses (≥ 60 % de jetons `ADDR`/`DISP`), table arithmétique (progression par phase), RomTag,
   en-tête/pied de ROM, ou **code/table non classé**. Seule cette dernière classe pourrait révéler du
   code copié. Les colonnes « code » des tableaux ne comptent qu'elle.
6. **Seuil « notable »** : la plus longue correspondance code/table entre le groupe `tiers` et la
   référence, plus un. Cela donne 40 mots, 19 instructions et 19 instructions souples. Les groupes
   `commodore` et `aros` sont mesurés mais ne fixent pas le seuil : ils ne sont pas « sans lien ».
7. **Auto-contrôle** (`--selftest`) : 12 fragments de 32 à 128 mots de la référence, dont les
   adresses ROM ont été décalées comme après un nouveau lien, sont insérés en mémoire dans une copie
   de notre ROM. L'outil doit retrouver chacun sur au moins 80 % de sa longueur.

### Commandes exactes

Elles sont lancées depuis la racine du dépôt. `<travail>` est un répertoire de travail hors dépôt.

```sh
# 1. Table des symboles : nouveau lien des objets du build prod (même liste et même ordre que le Makefile)
OBJS="boot lists memory library rawdofmt tasks ports io ramlib interrupts resident libinit cia misc timer \
trackdisk strap keyboard input console keymap keymapdata gameport expansion romboot mathffp diskres potgo \
kbddev audio semaphores execmisc gfx graphics_lib draw regions layers bootscreen_data font8x8 text gels area \
intuition_lib screens menus requester request pointer prefs gadgets sysreq alert dos_lib ofs ofswrite loadseg \
bcpl process handler conhandler conwin shell diskvalidator feeder workbench"
L=""; for o in $OBJS; do L="$L build/prod/$o.o"; done          # build/ pour la ROM dev
vlink -b rawbin1 -T src/exec/kick.ld -M<travail>/kick-prod.map -o <travail>/kick-prod.bin $L
cmp <travail>/kick-prod.bin <(head -c $(stat -c%s <travail>/kick-prod.bin) build/kick13-prod.rom)   # aucune différence

# 2. Témoins
for adf in assets/test_adf/*.adf; do xdftool "$adf" unpack "<travail>/adf/<nom>"; done

# 3. Mesure (listes de fichiers des groupes : voir le tableau « Témoins »)
python3 -I tests/audit_rom_similarity.py build/kick13-prod.rom assets/kick34005.A500 \
    --temoin tiers <fichiers tiers...> --temoin commodore <fichiers Workbench...> \
    --temoin aros "<travail>/adf/aros/AROS Kickstart" \
    --map <travail>/kick-prod.map --base tiers --selftest
```

La mesure complète prend environ 30 s. Sans capstone, seul le flux `mots` est mesuré.

## Résultats (ROM de production)

Lecture des colonnes :
- « jetons A » : taille utile de A, hors remplissage ;
- « max (tout) » et « max (code) » : plus longue correspondance, toutes classes ou code/table seul ;
- « code ≥ N » : nombre de correspondances code/table d'au moins N jetons et part de A qu'elles
  couvrent ;
- « n-gr. » : part des n-grammes distincts de A présents dans B, toutes classes confondues.

### Flux `mots` (mots de 16 bits)

| comparaison | jetons A | max (tout) | max (code) | code ≥ 8 : nb / couv. | code ≥ 16 | code ≥ 32 | 4-gr. | 8-gr. | 16-gr. |
|---|---|---|---|---|---|---|---|---|---|
| **notre ROM vs référence** | 96 875 | 218 | **20** | 71 / 0,69 % | 5 / 0,09 % | **0** / 0,00 % | 2,4 % | 0,8 % | 0,3 % |
| tiers vs référence | 272 295 | 216 | 39 | 23 / 0,12 % | 5 / 0,05 % | 1 / 0,01 % | 0,9 % | 0,1 % | 0,0 % |
| notre ROM vs tiers | 96 875 | 224 | 10 | 13 / 0,07 % | 0 / 0,00 % | 0 / 0,00 % | 1,6 % | 0,1 % | 0,0 % |
| commodore vs référence | 205 583 | 121 | 121 | 700 / 3,80 % | 69 / 1,20 % | 22 / 0,74 % | 6,0 % | 1,3 % | 0,5 % |
| notre ROM vs commodore | 96 875 | 47 | 11 | 34 / 0,09 % | 0 / 0,00 % | 0 / 0,00 % | 1,3 % | 0,1 % | 0,0 % |
| aros vs référence | 579 070 | 282 | 282 | 147 / 0,27 % | 5 / 0,06 % | 2 / 0,05 % | 1,2 % | 0,2 % | 0,1 % |
| notre ROM vs aros | 96 875 | 224 | 12 | 31 / 0,17 % | 0 / 0,00 % | 0 / 0,00 % | 2,6 % | 0,4 % | 0,2 % |

### Flux `instr` (instructions, opérandes conservés hors adresses et déplacements)

| comparaison | jetons A | max (tout) | max (code) | code ≥ 8 : nb / couv. | code ≥ 16 | code ≥ 32 | 4-gr. | 8-gr. | 16-gr. |
|---|---|---|---|---|---|---|---|---|---|
| **notre ROM vs référence** | 61 691 | 17 | **13** | 4 / 0,06 % | **0** / 0,00 % | 0 / 0,00 % | 0,9 % | 0,1 % | 0,0 % |
| tiers vs référence | 166 017 | 18 | 18 | 10 / 0,06 % | 1 / 0,01 % | 0 / 0,00 % | 0,2 % | 0,0 % | 0,0 % |
| notre ROM vs tiers | 61 691 | 14 | 6 | 0 / 0,00 % | 0 / 0,00 % | 0 / 0,00 % | 0,5 % | 0,0 % | 0,0 % |
| commodore vs référence | 129 075 | 96 | 96 | 114 / 1,69 % | 32 / 1,04 % | 12 / 0,70 % | 2,3 % | 0,7 % | 0,3 % |
| notre ROM vs commodore | 61 691 | 16 | 7 | 0 / 0,00 % | 0 / 0,00 % | 0 / 0,00 % | 0,4 % | 0,0 % | 0,0 % |
| aros vs référence | 364 095 | 28 | 28 | 4 / 0,02 % | 2 / 0,01 % | 0 / 0,00 % | 0,2 % | 0,0 % | 0,0 % |
| notre ROM vs aros | 61 691 | 19 | 8 | 1 / 0,01 % | 0 / 0,00 % | 0 / 0,00 % | 0,7 % | 0,0 % | 0,0 % |

### Flux `instr-souple` (registres et constantes effacés)

| comparaison | jetons A | max (tout) | max (code) | code ≥ 8 : nb / couv. | code ≥ 16 | code ≥ 32 | 4-gr. | 8-gr. | 16-gr. |
|---|---|---|---|---|---|---|---|---|---|
| **notre ROM vs référence** | 61 691 | 23 | **13** | 12 / 0,18 % | **0** / 0,00 % | 0 / 0,00 % | 4,6 % | 0,2 % | 0,0 % |
| tiers vs référence | 166 017 | 51 | 18 | 14 / 0,09 % | 1 / 0,01 % | 0 / 0,00 % | 2,8 % | 0,1 % | 0,0 % |
| notre ROM vs tiers | 61 691 | 24 | 8 | 2 / 0,03 % | 0 / 0,00 % | 0 / 0,00 % | 5,6 % | 0,1 % | 0,0 % |
| commodore vs référence | 129 075 | 257 | 257 | 1 511 / 11,63 % | 161 / 3,56 % | 32 / 1,91 % | 12,3 % | 3,7 % | 1,8 % |
| notre ROM vs commodore | 61 691 | 23 | 7 | 0 / 0,00 % | 0 / 0,00 % | 0 / 0,00 % | 3,8 % | 0,1 % | 0,0 % |
| aros vs référence | 364 095 | 51 | 28 | 42 / 0,10 % | 2 / 0,01 % | 0 / 0,00 % | 3,0 % | 0,0 % | 0,0 % |
| notre ROM vs aros | 61 691 | 19 | 10 | 18 / 0,15 % | 0 / 0,00 % | 0 / 0,00 % | 8,3 % | 0,2 % | 0,0 % |

### ROM dev

La ROM dev ajoute le harnais de test. Elle donne les mêmes conclusions :
- flux `mots` : code max 19, aucune correspondance code ≥ 32 ;
- flux `instr` : code max 13 ;
- flux `instr-souple` : code max 13 ;
- même liste de données au-dessus du seuil, aux décalages d'adresse près.

### Auto-contrôle

12 fragments relogés de la référence sur 12 sont retrouvés (graine 1). La normalisation et
l'appariement détectent donc une copie relogée de 32 mots ou plus.

## Lecture

- **Notre ROM se comporte comme du code sans lien, pas comme du code Commodore.** Sur les trois flux,
  sa plus longue correspondance de code avec la référence (20 mots, 13 instructions) reste sous celle
  des programmes tiers (39 mots, 18 instructions). Aucune de ses correspondances de code n'atteint
  32 mots ou 16 instructions.
- À l'inverse, le code Commodore hors ROM partage avec la référence :
  - des correspondances jusqu'à 121 mots ou 96 instructions exactes, soit 257 instructions en mode
    souple ;
  - 3,8 % de son code couvert par des correspondances de 8 mots ou plus, et 11,6 % en mode souple ;
  - c'est la signature d'une même chaîne d'outils, notamment des routines d'exécution de
    compilateur liées dans plusieurs exécutables.

  Une mémorisation du code Commodore produirait ce profil : ce n'est pas le nôtre.
- **Les recouvrements courts (4-grammes) sont plus élevés pour notre ROM (2,4 %) que pour les tiers
  (0,9 %).** C'est attendu pour une réimplémentation d'OS : nous appelons les mêmes vecteurs de
  bibliothèque (LVO), sur les mêmes champs de structures et les mêmes registres matériels. Ces
  constantes d'ABI se retrouvent dans des fenêtres de 4 jetons, et le même effet apparaît pour AROS
  (2,6 % avec notre ROM). Dès 8 et 16 jetons, ce recouvrement retombe sous 1 %. Il s'explique alors
  par les tables de données ci-dessous.

## Correspondances au-dessus du seuil : uniquement des données

Les emplacements et symboles sont ceux de notre ROM de production. Ils viennent de la table vlink
ci-dessus ; le fichier source est déduit du nom d'objet.

| offset | adresse | octets | plus longue (jetons) | symbole | source | nature |
|---|---|---|---|---|---|---|
| `$0B0F8` | `$FCB0F8` | 116 | 58 | `expansion_inittab+$4` | `src/exec/expansion.s` | table des vecteurs de fonctions de la bibliothèque |
| `$0B9C8` | `$FCB9C8` | 80 | 40 | `mathffp_inittab+$4` | `src/exec/mathffp.s` | table des vecteurs de fonctions |
| `$0D3A2` | `$FCD3A2` | 452 | 218 | `graphics_inittab+$4` | `src/graphics/graphics_lib.s` | table des vecteurs de fonctions |
| `$1025A` | `$FD025A` | 132 | 66 | `layers_inittab+$4` | `src/graphics/layers.s` | table des vecteurs de fonctions |
| `$21902` | `$FE1902` | 328 | 164 | `intuition_inittab+$4` | `src/intuition/intuition_lib.s` | table des vecteurs de fonctions |
| `$266B6` | `$FE66B6` | 154 | 76 | `dos_rtinit+$42` | `src/dos/dos_lib.s` | table de pointeurs (vecteurs de `dos`) |
| `$2009A` | `$FE009A` | 388 | 194 | `topaz8_loc` | `src/graphics/text.s` | table de localisation des caractères d'une police à chasse fixe : progression arithmétique (position = 8 × rang, largeur 8) |

**Pourquoi ces correspondances sont imposées :**
- **Tables de vecteurs.** Après normalisation, une table de pointeurs vers la ROM n'est plus qu'une
  suite de jetons `ADDR`. Leur égalité ne révèle que le **nombre de fonctions** de la bibliothèque, que
  fixent les fichiers `.fd` publics.
- **Table de localisation de police.** Elle est entièrement calculée à partir de la géométrie
  (8 × 8). La ROM AROS contient la même table : c'est la plus longue correspondance « aros vs
  référence », 282 mots. Les **bitmaps** des glyphes (`src/graphics/font8x8.s`), qui seraient la
  partie expressive, ne correspondent pas.

Dans le flux `instr-souple`, deux autres plages dépassent le seuil. Elles sont classées faible
entropie :
- `rf_outline+$44` (`src/graphics/draw.s`, 50 o, 20 jetons) : quatre appels identiques de tracé de
  segment, que le mode souple réduit à un motif répété ;
- `bcpl_rtdata+$8` (`src/dos/bcpl.s`, 46 o, 23 jetons) : données du runtime BCPL.

### Pour transparence : les plus longues correspondances de code sous le seuil

Aucune n'atteint la base sans lien (39 mots, 18 instructions). Elles sont listées avec leur nature :

| offset | adresse | mots | instr. | symbole | source | nature |
|---|---|---|---|---|---|---|
| `$23FC0` | `$FE3FC0` | 20 | — | `mn_chk_hi` | `src/intuition/menus.s` | deux descripteurs `struct Image` (coche et symbole Amiga des menus) : dimensions observables à l'écran, pointeurs masqués |
| `$0B1D0` | `$FCB1D0` | 19 | 13 | `exp_cpbinding+$22` | `src/exec/expansion.s` | deux relais minimaux vers l'obtention et la libération d'un sémaphore (`ObtainConfigBinding`/`ReleaseConfigBinding`) ; décalages et LVO fixés par l'ABI |
| `$0B800` | `$FCB800` | 18 | — | `romboot_romtag+$C` | `src/exec/romboot.s` | fin de RomTag + noms publics de bibliothèques |
| `$0B0B0` | `$FCB0B0` | 17 | — | `gameport_end+$2` | `src/exec/expansion.s` | RomTag + nom public |
| `$08D98` | `$FC8D98` | 16 | — | `trackdisk_romtag+$C` | `src/exec/trackdisk.s` | fin de RomTag + nom public |
| `$0C0C2` | `$FCC0C2` | 16 | — | `potgo_end+$C` | `src/exec/kbddev.s` | fin de RomTag + nom public |
| `$0D37E` | `$FCD37E` | 15 | — | `graphics_romtag+$C` | `src/graphics/graphics_lib.s` | fin de RomTag + nom public |
| `$24C48` | `$FE4C48` | 14 | — | `pf_defaults` | `src/intuition/prefs.s` | valeurs par défaut des préférences (observables par `GetPrefs`) |
| `$0889C` | `$FC889C` | 13 | — | `timer_romtag+$C` | `src/exec/timer.s` | fin de RomTag + nom public |
| `$10462` | `$FD0462` | 13 | 9 | `ly_WhichLayer+$6` | `src/graphics/layers.s` | test d'appartenance d'un point à un rectangle (quatre comparaisons sur les bornes de la structure) |
| `$23962` | `$FE3962` | 13 | — | `sc_palette+$8` | `src/intuition/screens.s` | table des couleurs par défaut (observables par `GetRGB4`) |
| `$03138` | `$FC3138` | 11 | — | `d3c_client+$16` | `src/exec/boot.s` | allocation mémoire publique et effacée, puis test du résultat |
| `$2D09E` | `$FED09E` | 11 | — | `sh_run_startup+$1A` | `src/dos/shell.s` | même idiome d'allocation |
| `$0DADA` | `$FCDADA` | 10 | — | `gfx_WaitBlit` | `src/graphics/graphics_lib.s` | attente de fin du blitter (idiome du *Hardware Reference Manual*) |
| `$0E6F2` | `$FCE6F2` | 10 | 8 | `rf_outline+$4E` | `src/graphics/draw.s` | appels successifs de tracé (contour de rectangle) |
| `$0E706` | `$FCE706` | 10 | 8 | `rf_outline+$62` | `src/graphics/draw.s` | idem |
| `$28EC4` | `$FE8EC4` | 10 | — | `bcpl_call` | `src/dos/bcpl.s` | liaison d'appel BCPL (convention imposée par le code BCPL de la 1.3) |

Le flux `instr-souple` compte douze correspondances code de 8 à 13 instructions, dont
`exp_cpbinding` et `ly_WhichLayer` ci-dessus, toutes sous la base de 18. Ce sont des tests de bornes, des boucles de tracé et des séquences d'appel de bibliothèque
(`exec_AvailMem`, `exec_ObtainSemaphore`, `dr_line`, `dr_rect`, `gfx_ReadPixel`, `gfx_Animate`,
`exp_makedosnode`, `intuition_AllocRemember`, `rgt_hl`).

**Données imposées par l'ABI et le matériel, signalées à part.** Ce ne sont pas du code :
- l'en-tête de ROM : saut au reset, version 34 ;
- le pied de ROM : taille, vecteurs `$0018`–`$001F` ;
- les structures RomTag (`$4AFC`, drapeaux, version, type, priorité) ;
- les noms publics (`exec.library`, `timer.device`…) et les chaînes de version ;
- les messages affichés à l'écran (Workbench, requêtes), reproduits à l'identique pour la
  compatibilité ;
- les tables de vecteurs de fonctions ;
- les valeurs par défaut observables (palette, préférences).

L'outil les classe `texte`, `RomTag`, `table d'adresses`, `faible entropie` ou `en-tête/pied ROM`.

## Limites : ce que la mesure prouve et ne prouve pas

- **Elle prouve** l'absence de reprise binaire, même relogée ou avec registres renommés, de suites
  de plus de 13 instructions (ou de 20 mots) de la ROM **34.5** dans notre ROM. Elle situe aussi
  notre niveau de coïncidence au niveau de programmes sans lien.
- **Une seule version de référence.** Les sources qui ont fui couvrent d'autres versions (2.x, 3.x)
  dont le code diffère. Une reprise de ces versions ne serait détectée ici que si le code concerné
  est resté identique depuis la 1.3. Pour fermer ce point, il faudrait refaire la mesure contre des
  ROM 2.04 et 3.1 avec le même outil.
- **Mesure binaire, pas sémantique.** Une paraphrase ne laisse pas de trace binaire au-delà des
  idiomes : logique recopiée puis réécrite avec un autre ordre d'instructions, d'autres registres
  et d'autres modes d'adressage. C'est aussi le cas d'une traduction en assembleur d'une source C :
  intuition et graphics étaient largement écrits en C, dos en BCPL. La mesure ne l'exclut pas.
  C'est le rôle du mur clean-room (`docs/CLEANROOM.md`) et de la revue des specs d'analyse.
- **Désassemblage linéaire.** Les flux `instr` traversent aussi des données. Le flux `mots`, sans
  décodeur, est là pour couvrir les désalignements éventuels. Le classement « code/table » ne
  distingue pas une petite table de données d'un fragment de code : il est volontairement
  conservateur, et ces cas ont été qualifiés à la main ci-dessus.
- **Seuil empirique.** Il dépend du corpus `tiers` (environ 600 Ko). Un corpus plus grand relèverait
  la base. Le verdict ne dépend pas du seuil exact : la plus longue correspondance de code de notre
  ROM reste nettement sous la base (20 mots contre 39, 13 instructions contre 18), et elle
  s'explique déjà par l'ABI.
- **Témoin AROS.** Notre implémentation consulte les sources AROS (lecture seule). La faible
  similarité binaire avec la ROM AROS (code max 12 mots, 8 instructions) ne prouve pas l'absence
  d'inspiration : AROS est du C compilé par gcc, et une inspiration ne laisse pas de trace binaire.

## Relecture clean-room

Ce document a été relu avant publication pour confirmer :
- qu'il ne contient **aucun octet, aucun désassemblage et aucun offset de la ROM d'origine** ;
- que chaque correspondance est décrite par son seul emplacement dans **notre** ROM (offset, symbole,
  fichier source), sa longueur et une nature neutre ;
- qu'aucune suite d'instructions n'est transcrite, ni de la ROM d'origine ni de nos plages
  appariées (qui lui sont identiques) ;
- que les seules informations sur la ROM d'origine sont sa taille, son empreinte sha1 (publique,
  identifiant la révision 34.5) et des statistiques agrégées.

L'outil `tests/audit_rom_similarity.py` suit la même règle : il n'affiche que des statistiques et
des emplacements dans la **première** ROM. Il ne contient aucun octet de la référence et aucun chemin
propre à une machine. Le document peut être lu par la piste implémentation.
