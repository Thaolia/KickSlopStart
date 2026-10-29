# Audit clean-room des specs d'analyse — 2026-10-29

Périmètre : `docs/analysis/` (50 fichiers). Méthode : relecture de textes uniquement (la ROM n'a pas été
ouverte, aucun désassembleur lancé) ; comparaison avec `src/` par recherche de valeurs.

Critères (cf. `docs/CLEANROOM.md`) : une spec décrit comportement et ABI ; elle ne contient ni suite
d'instructions transcrite ou paraphrasée pas à pas, ni désassemblage, ni adresse/offset de routine dans
la ROM. Sont permis : adresses matérielles (`$DFFxxx`, `$BFxxxx`), adresses RAM, LVO, offsets de
structures publiques ou privées, valeurs écrites dans les registres.

---

## 1. Relecture des 19 specs sans section « Relecture clean-room »

Chaque fichier a reçu une section « ## Relecture clean-room » datée du 2026-10-29.

| Fichier | Problèmes trouvés | Correction |
|---|---|---|
| `module-map.md` | (a) Pour les 24 ROMTags : offset fichier et adresse ROM de la tag, de `rt_Name`, `rt_IdString`, `rt_Init`, `rt_EndSkip` ; adresses des tables auto-init (`vectors`, `structure`, `initFunction`) ; valeur du PC de reset ; bornes de la plage d'exec ; départages illustrés par adresses (≈ 164 occurrences). (c) Texte intégral de la bannière de copyright, valeur du checksum de l'image, exemple d'offset négatif de la table mathffp. | Tableau réécrit sans aucune adresse (flags, type, pri, révision) ; table auto-init réduite à taille / encodage / nombre de LVO / présence des champs ; départages exprimés en ordre relatif ; bannière et checksum retirés. |
| `dos-boot-sequence.md` | (a) ROMTag et `rt_Init` de dos ; adresse ROM de chacune des chaînes citées (≈ 45 occurrences). | Adresses retirées ; chaînes conservées (noms d'ABI, textes rendus). Copyright non reproduit. |
| `trackdisk-official-timing.md` | (a) ROMTag, `rt_Init`, bornes du module, « carte des routines » (12 adresses), tables de défauts, emplacements des écritures ADKCON et des constantes, emplacement du test `/RDY` (≈ 57 occurrences). (b) Le pulse `/STEP` était décrit par les instructions (« deux `NOP` », idiome « écrire CIA → 2 NOP → accès CIA ») ; titres « déroulé exact / routine ». | Carte remplacée par une liste de fonctions par rôle ; pulse décrit par sa durée (≈ 1 µs d'attente délibérée) ; séquences reformulées en effets observables sur les registres. |
| `dos-v34-spec.md` | (a) ROMTag, `rt_Init`/`rt_EndSkip`, `rt_Name`, `rt_IdString` et adresses des chaînes BSTR (9 occurrences). | Adresses retirées ; relation `rt_Init == rt_EndSkip` gardée sans valeur. |
| `test-vectors.md` | (a) PC de reset (A2), `rt_Init`/`rt_EndSkip` d'exec (B5), adresses des trois tags de pri 0 (C1), renvoi aux « offsets » des tags. | Assertions reformulées en relatif (PC de reset = `rt_Init`, ordre de position). |
| `boot-sequence.md` | (a) Adresse du point d'entrée du coldstart (3 occurrences) et bornes de la plage d'exec. | Remplacées par « adresse dans la ROM » / « plage du module exec ». |
| `coldstart-hardware-v34.md` | (a) Valeur du PC de reset. (b) Nom et opcode de l'instruction placée avant le point d'entrée, mention « pas de BSR/JSR », nombres d'itérations des boucles de temporisation. (c) Motifs de test RAM/pile (`$F2D4B698`, `$F1E2D3C4`), sans portée d'ABI. | Point d'entrée sans adresse ; instruction remplacée par son effet ; itérations remplacées par les durées ; motifs remplacés par « motif de test ». |
| `exec-spec.md` | (a) Adresse ROM de `rt_IdString` d'exec. | Retirée. Remarque de fond (non corrigée) : la liste « Delta V34 → 2.0 » contredit le §5 sur `AddMemList`/`CopyMem`/`CopyMemQuick`. |
| `fault-v34.md` | (a) « Repères » ROM : entrée de `fault()`, segment BCPL, chaînes BSTR, offsets de la table globin ; en-tête présentant les adresses ROM comme repères. | Retirés ; numéros de globales et chaînes émises conservés. |
| `alert-v34.md` | Aucun. | — |
| `audio-device-v34.md` | Aucun. | — |
| `autoconfig-v34.md` | Aucun (adresses Zorro II / slow RAM / carte UAE uniquement). | — |
| `fastfonts-ff.md` | Aucun (logiciel tiers ; aucune donnée Kickstart). | — |
| `graphics-blitter-v34.md` | Aucun. | — |
| `graphics-display-v34.md` | Aucun ; point d'attention : formules du §4.4 et fusion du §5.2 très fines, à utiliser via les vecteurs sondés. | — |
| `octamed-v34.md` | Aucun (logiciel tiers ; ROM seulement exécutée). | — |
| `setpatch-disk-resource.md` | Aucun (programme du disque) ; signalé : deux motifs de code ROM attendus par SetPatch (`$70E56000`, `$E2EF`) cités comme conditions d'application. | — |
| `sysinfo-44.md` | Aucun (logiciel tiers ; offsets « H0+… » internes à SysInfo). | — |
| `trackdisk-write-v34.md` | Aucun (format MFM public, ordre d'accès matériel). | — |

Contrôle final : plus aucune adresse `$FCxxxx`–`$FFxxxx` de routine ou de donnée ROM dans ces 19
fichiers (restent la base `$FC0000`, les offsets d'en-tête `$FC0004`/`$FC000C`, la plage générique
`$FC0000–$FFFFFF` et des masques comme `$00FF0001`).

### 1.1 Constat initial sur les autres specs (corrigé, cf. §1.2)

Ces specs avaient déjà une section « Relecture clean-room » mais contenaient encore des adresses de
routines ou de données ROM (souvent dans un bloc « Repères » d'en-tête) :

| Fichier | Occurrences | Où |
|---|---:|---|
| `workbench-task-v34.md` | 47 | en-tête, §1.1 ROMTag, tableau des étapes d'init, divers |
| `intuition-prefs-v34.md` | 37 | en-tête « Repères » (dont l'image pointeur par défaut et les prefs par défaut), corps |
| `handlers-v34.md` | 21 | `rt_Init` de dos, `cliinit`, table des globales |
| `intuition-prop-v34.md` | 17 | en-tête |
| `bcpl-runtime-v34.md` | 15 | segarray ROM, table des globales par segment |
| `keyboard-handshake-v34.md` | 15 | en-tête, corps |
| `intuition-gzz-v34.md` | 13 | en-tête |
| `intuition-frame-v34.md` | 12 | en-tête |
| `boot-clock-v34.md` | 5 | repères du validateur |
| `caesar-boot.md` | 4 | repères graphics (serveur VBlank, copinit) |
| `cracktros-exit.md` | 3 | repères graphics |
| `loadwb-13.md` | 3 | boucle du CLI, endstream |
| `monkey-startup.md` | 2 | timer.device, trackdisk |

### 1.2 Nettoyage des 13 specs (2026-10-29, seconde passe)

Mêmes règles que le §1. Chaque fichier a reçu, dans sa section de relecture existante, une ligne
« Correction du 2026-10-29 ». Les données de type (ii) du §2 n'ont pas été modifiées.

| Fichier | Retiré | Reformulation |
|---|---|---|
| `workbench-task-v34.md` | 47 adresses : ROMTag et ses pointeurs, points d'entrée, `main`, boucle principale, routines d'abandon / de titre / d'Info, colonne « Repère » du §3.1, AddTask d'exec, chaîne « Workbench » ; description de l'encodage des points d'entrée (« bourrage », opération sur D0) | Positions **relatives au tag** conservées (+26/+34/+42/+44) car imposées par `c:LoadWB` (programme du disque) ; effet observable gardé (sélecteur, `D0 := D0 OU 2`, exigence D0 = 0) ; version Kickstart lue via le champ taille du pied de ROM, sans adresse |
| `intuition-prefs-v34.md` | 37 : bloc « Repères » (vecteurs et corps de Set/Get/GetDefPrefs, table par défaut, image pointeur, TextAttr, souris, NEWPREFS, init, `cliinit`) et adresses du corps | Liste des fonctions couvertes ; table §4.3 inchangée |
| `handlers-v34.md` | 21 : `rt_Init` de dos, `cliinit`, routines locales, table d'environnement, console-handler, makeglobvec, starthandler, deviceproc, routine « objet », colonne « Adresse » | Numéros de globales et contrats conservés |
| `intuition-prop-v34.md` | 17 : bloc « Repères » | Liste des fonctions couvertes |
| `bcpl-runtime-v34.md` | 15 : segarray ROM, colonne « Repère », start du CLI ROM | Globales, offsets GV et segments porteurs conservés ; offset de hunk de `c:Run` (disque) gardé |
| `keyboard-handshake-v34.md` | 15 : bloc « Repères » + 2 dans le corps | Liste des modules ; registres CIA (matériel) conservés |
| `intuition-gzz-v34.md` | 13 : en-tête | Liste des fonctions étudiées |
| `intuition-frame-v34.md` | 12 : en-tête | Liste des fonctions ; §5.3 (type (ii)) intact |
| `boot-clock-v34.md` | 5 : repères du validateur et du FS | — |
| `caesar-boot.md` | 4 : serveur VBlank, copinit | Noms de fonctions |
| `cracktros-exit.md` | 3 : en-tête | Noms de fonctions |
| `loadwb-13.md` | 3 : boucle du CLI, endstream | — |
| `monkey-startup.md` | 2 : timer.device, ciab.resource | — |

Les mentions « les adresses ROM ne sont que des repères » des en-têtes et des sections de relecture
ont été remplacées par « aucune adresse ROM (retirées le 2026-10-29) ».

### 1.3 Recomptage final sur les 50 specs

Recherche de toute valeur `$FCxxxx`–`$FFxxxx` (avec ou sans `$00`, ou `0x`), hors base `$FC0000`,
offsets d'en-tête `$FC0004`/`$FC000C`, bornes de plage `$FCFFFF`/`$FFFFFF`/`$F80000` et valeurs
`…FFFF` :

| Résultat | Nombre | Détail |
|---|---:|---|
| Adresses de routines ou de données ROM | **0** | — |
| Faux positifs (pas des adresses) | 3 | masque `$00FF0001` (`alert-v34.md`, `coldstart-hardware-v34.md`) et motif de données `$00FF0F0F` (`graphics-blitter-v34.md`) |
| Références d'adresse ROM **justifiées** conservées | — | base `$FC0000` et plage `$FC0000–$FFFFFF` (mémoire publique), offsets d'en-tête `+$0C/+$0E`, positions relatives au tag de `workbench.task` (+26…+46, contrat imposé par `c:LoadWB`), conditions de SetPatch `$FC0000–$FFFFFF` / `$F80000`, `lib_IdString` dans les 64 premiers Ko (`sysinfo-44.md`) |

Il ne reste aucune adresse ROM non justifiée dans `docs/analysis/`.

---

## 2. Inventaire des données issues de la ROM Kickstart (50 specs)

Classement : **(i)** donnée d'ABI ou de format observable, imposée pour la compatibilité (valeurs
rendues, structures, textes affichés) ; **(ii)** donnée créative ou fonctionnelle reproduite, qui
serait mieux décrite que copiée. Ces passages n'ont **pas** été modifiés (décision du responsable).
Lignes : état du 2026-10-29 après les deux passes de corrections.

| Fichier | Lignes | Nature | Taille | Avis |
|---|---|---|---|---|
| `console-keymap-v34.md` | 492–497 | Keymap « usa » : octets bruts Capsable/Repeatable Lo et Hi | 30 octets | (i) — mais les octets bruts pourraient être remplacés par la liste des touches qu'ils désignent (déjà donnée à côté) |
| `console-keymap-v34.md` | 499–612 | Keymap « usa » : valeur rendue par RawKeyConvert pour 104 codes × 8 qualificatifs (+ type, Caps, Rép.) | ≈ 115 lignes de tableau | (i) — sortie observable de RawKeyConvert, vérifiée par sonde ; contenu fonctionnel d'une disposition clavier |
| `console-keymap-v34.md` | 614–631 | Touches mortes « usa » : 5 accents × 8 touches modifiables, codes de l'espace | ≈ 15 lignes | (i) — sortie observable |
| `intuition-input-menus-v34.md` | 517–530 | **Images ROM** en art ASCII : coche hires 15×8 et lores 9×8, symbole Amiga hires 23×8 et lores 14×8 | 4 images, 32 lignes de pixels | **(ii)** — dessins de la ROM ; décrire format (taille, PlanePick, sens des bits, LeftEdge) suffirait |
| `intuition-input-menus-v34.md` | 477, 511, 788 | Motif de grisé des menus `$4444/$1111` | 2 mots | (ii) mineur — effet visuel ; une description (« une ligne sur deux, un pixel sur quatre ») suffirait |
| `intuition-frame-v34.md` | 145–197 (§5.3) | **Géométrie pixel des pictogrammes** des gadgets système (profondeur avant/arrière, fermeture, taille ; hires et lores) : coordonnées exactes de chaque rectangle | 8 pictogrammes | **(ii)** — transcription au pixel près des images ROM, équivalente à une copie ; une description de principe (« carré noir derrière un carré creux », tailles de boîte) suffirait |
| `intuition-frame-v34.md` | 74–83, 96–103 | Motif de glissement (8 lignes, lignes 2-3 et 6-7 pleines) et voile d'inactivité (1 pixel sur 4, décalé) | 2 motifs décrits | (ii) mineur — déjà décrits, non copiés en valeurs |
| `intuition-prefs-v34.md` | 196–234 (§4) | Table des **Preferences par défaut** de la ROM (champ par champ, 232 octets) | ≈ 38 lignes | (i) — valeurs rendues par GetDefPrefs |
| `intuition-prefs-v34.md` | 36, 86–99 | Couleurs par défaut (`$05A $FFF $002 $F80`, pointeur `$D22 $000 $FCA`), comparaison ROM / fichier | 7 couleurs | (i) |
| `intuition-screens-v34.md` | 250–257 | Palette d'un écran neuf (32 couleurs = prefs + table graphics) | 32 mots | (i) — valeurs rendues par GetRGB4 |
| `graphics-display-v34.md` | 183–185 | Table de couleurs par défaut de graphics | 32 mots | (i) — rendue par GetColorMap/GetRGB4 |
| `graphics-display-v34.md` | 152–177 (§2) | Contenu de **copinit** (liste copper de démarrage, 92 octets) | ≈ 25 lignes | (i) — en chip RAM, observable, des programmes en dépendent (`caesar-boot.md` §2.7) |
| `graphics-display-v34.md` | 349–368 | Listes copper produites (exemples sondés) | 4 extraits | (i) — sorties sondées |
| `alert-v34.md` | 135–138, 186–199 | Guru : palette `$111`/`$F20`, trois en-têtes, « Press left mouse button to continue. », format `Guru Meditation #%08lx.%08lx`, positions x/y des blocs | 5 chaînes courtes, 6 nombres | (i) — affichage observable |
| `alert-v34.md` | 139–147, 238 | Géométrie du cadre, compteur de clignotement 26 633 | quelques nombres | géométrie (i) ; compteur (ii) mineur — la période observée (≈ 0,9 s/phase) suffit |
| `coldstart-hardware-v34.md` | 310–317, 335–344 | Textes d'alert.hook (doublon d'alert) ; couleurs d'écran `$444`, `$888`, `$CC0`, `$0C0` | 4 couleurs | (i) — observable |
| `module-map.md` / `test-vectors.md` | module-map 15–19, test-vectors 13–19 | En-tête `0x11114EF9`, version `0x00220005`, taille `0x00040000` | 3 longs | (i) — format d'image vérifié par `romtool` |
| `dos-v34-spec.md` | 29–32 | Gabarits BSTR `{3,"DFX"}`, `{11,"File System"}`, `{11,"FileHandler"}`, `{24,"CON:0/0/640/200/AmigaDOS"}` | 4 chaînes | (i) — noms d'ABI / titre de fenêtre visible |
| `dos-boot-sequence.md` | 35–57, 60–70, 84–95 | Noms (libraries, devices, `L:`, `C:`, assigns), messages du CLI et des requesters disque | ≈ 30 chaînes courtes | (i) — noms d'ABI et textes affichés |
| `bcpl-runtime-v34.md` | 268–282, 331, 481, 540, 590–591 | Messages du CLI ROM (« Error in command name », « Unknown command %S », « Unable to load %S: », « too many > or < », « command too long », « %S failed returncode %N »…), requesters `abort`/`deviceproc` | ≈ 12 chaînes | (i) — textes affichés |
| `handlers-v34.md` | 96–101, 144, 249, 295 | Gabarits de montage (`L:RAM-HANDLER`, `L:PORT-HANDLER`, CON), requester « Please insert volume … in any drive » | ≈ 6 chaînes | (i) |
| `disk-change-v34.md`, `disk-full-write-v34.md` | disk-change 182–205, 335–336 ; disk-full 66, 146, 157 | Textes de requesters observés (« Please replace volume », « Error validating disk », « Key 880 checksum error », « Volume … is full ») | ≈ 8 chaînes | (i) — captures d'écran |
| `fault-v34.md` | 20, 36, 79 | Chaîne de repli `Error code %N\n` | 1 chaîne | (i) |
| `intuition-requesters-v34.md` | 228, 324 | « System Request », « =LEFT BUTTON OK= », « =RIGHT BUTTON CANCEL= » | 3 chaînes | (i) |
| `intuition-screens-v34.md` | 433, 442, 540–541 | Titre « Workbench Screen » ; octets de bordure relevés `0B 01 05 02 04 02 04 04 02` | 1 chaîne, 9 octets | (i) — valeurs relues en mémoire |
| `workbench-task-v34.md` | 278, 436, 458, 476–481, 525, 627, 667–669, 715–717 | Textes du Workbench ROM : titre « Workbench release 1.2.  %ld free memory », « Kickstart version %ld.%ld. Workbench version %ld.%ld », « Enter the new name.  Press return when done. », « Error while %s: %ld » + table de 9 actions, « Do not use '%lc' in names », « Cannot read info file %s », « Ran out of memory.  Please free some and try again. », « This disk cannot be copied », « Info not available »… | ≈ 20 chaînes | (i) — titres d'écran observables |
| `octamed-v34.md` | 261, 326 | Bandeau du CLI initial (« Copyright © 1987 Commodore-Amiga, Inc. » / « All rights reserved. » / « Release 1.3 ») | 3 lignes | (i) — texte affiché ; contient une mention de copyright |
| `setpatch-disk-resource.md` | 125, 106–109 | Motifs de code ROM attendus par SetPatch : long `$70E56000` (tête de l'entrée LVO −222 de dos), mot `$E2EF` (gestionnaire d'exception) | 6 octets | (ii) — octets d'instructions ROM, vus à travers SetPatch ; utiles comme conditions d'application |

Hors ROM (non inventorié comme donnée Kickstart) : table des messages de `c/Fault` (`fault-v34.md` §4),
chaînes « We made Amiga, T » / « Still a Champion » (LoadWB 1.3.3, disque, `workbench-task-v34.md`
490–494), palettes et chaînes d'OctaMED, SysInfo, FastFonts, Preferences, jeux et cracktros, dump de
mémoire UAE (`uae-int2-v34.md` 221). Aucune spec ne contient de glyphe de police (topaz) ni d'image
du pointeur par défaut : ces données sont seulement citées (taille), avec adresse dans
`intuition-prefs-v34.md` (cf. §1.1).

---

## 3. Contrôle de `src/` : données identiques

Recherche des valeurs ci-dessus dans `src/` (lecture seule, aucune modification). Les numéros de
ligne sont ceux de l'arbre de travail du 2026-10-29 (`menus.s` y a des modifications non committées ;
les données de coche sont les mêmes que dans le dernier commit).

### 3.1 Correspondances exactes ou quasi exactes

1. **Pictogrammes des gadgets système** — `src/intuition/screens.s` l. 1563–1580 (`pic_front_h`,
   `pic_back_h`, `pic_close_h`, `pic_size_h` et variantes lores). Le commentaire indique « dessinés
   librement d'après leur description géométrique (spec §5.3) », mais les rectangles reprennent **les
   coordonnées exactes** de `intuition-frame-v34.md` §5.3. Exemples : arrière hires, carré creux
   x 4–17 y 1–6 et rectangle noir x 8–21 y 3–8 ⇔ `0,4,1,17,6` / `2,8,3,21,8` ; fermeture hires, cadre
   x 8–23 y 1–8, carré noir x 14–17 y 4–5, bandes x 4–5 et 26–27 ⇔ `0,8,1,23,8` / `2,14,4,17,5` /
   `0,4,0,5,9` / `0,26,0,27,9` ; taille hires x 2–7 y 1–3 et x 6–13 y 3–7 ⇔ `0,2,1,7,3` / `0,6,3,13,7`.
   Le rendu attendu est **identique au pixel** aux images ROM.
2. **Coche des menus** — `src/intuition/menus.s` l. 1025–1039 (`mn_chk_hi_data`, `mn_chk_lo_data`).
   Le commentaire dit « dessinée pour KickSlopStart (pas l'image de la ROM) ». Comparaison avec
   `intuition-input-menus-v34.md` l. 522–529 (15 bits utiles par ligne) :
   - hires : les lignes src 1, 2, 3 et 7 (`$FFE7`, `$FFCF`, `$FF9F`, `$F1FF`) sont **identiques**
     aux lignes ROM 2, 3, 4 et 8 (`$FFE6`, `$FFCE`, `$FF9E`, `$F1FE`, au bit de remplissage près) :
     même dessin décalé d'une ligne vers le haut ; les lignes src 5 et 6 (`$CE7F`, `$E4FF`) diffèrent
     d'un seul pixel des lignes ROM 6 et 7 (`$C67E`, `$E0FE`) ; la ligne src 4 et la ligne src 8
     diffèrent ;
   - lores : la ligne src 5 (`$33FF`) est identique à la ligne ROM 5 (`$3380`) sur 9 bits ; la ligne
     src 4 (`$79FF`) diffère d'un pixel de la ligne ROM 4 (`$F980`) ; le reste diffère.
   Forme très proche de l'original en hires ; à redessiner si l'on veut une indépendance nette.
   Le **symbole Amiga** n'est pas reproduit (remplacé par un chat, `mn_cat_*`, sans correspondance).
3. **Palette par défaut** — `src/intuition/screens.s` l. 3180–3184 (`sc_palette`) : entrées 4–16,
   18 et 20–31 (`$00F $F0F $0FF $FFF $620 $E50 $9F1 $EB0 $55F $92F $0F8 $CCC $000 … $444 … $FFF`)
   **identiques** à la table de graphics (`graphics-display-v34.md` l. 184–185,
   `intuition-screens-v34.md` l. 255–256) ; entrées 0, 17, 19 différentes (thème du projet). (i).
4. **Preferences par défaut** — `src/intuition/prefs.s` l. 286–309 : FontHeight 9, BaudRate 5,
   KeyRptSpeed 0,1 s, KeyRptDelay 0,8 s, DoubleClick 1,5 s, PointerTicks 2, PrinterType 7,
   `"generic"`, marges 5/75, PrintShade 1, PrintThreshold 2, PaperSize `$20`, PaperLength 66 :
   **identiques** à `intuition-prefs-v34.md` §4 ; couleurs 0, 17, 19 et XOffset/YOffset différents.
   (i).
5. **Chaînes** — 50 chaînes de `src/` (≥ 8 caractères, hors noms de libraries/devices) se trouvent
   à l'identique dans les specs, notamment :
   - Guru : `src/exec/execmisc.s` l. 592–600 (« Not enough memory. », « Recoverable Alert. »,
     « Software Failure. », « Press left mouse button to continue. », « Guru Meditation # ») et
     positions x/y 38/234/142, y 15/30 (l. 244–267) ; palette `$111`/`$F20` (`src/intuition/alert.s`) ;
   - Workbench : `src/dos/workbench.s` l. 4325–4414 (titre « Workbench release 1.2.  %ld free
     memory », texte Version, Rename, « Error while %s: %ld » et les 9 actions, « Do not use '%lc' in
     names », « Cannot read info file %s », « Ran out of memory.  Please free some and try again. »,
     « This disk cannot be copied », « Info not available », menus « Duplicate », « Clean Up »,
     « Last Error », « Snapshot », « Initialize ») ;
   - DOS : `src/dos/shell.s` l. 1065, 1503–1506 (« Can't open », « Unknown command », « Unable to
     load », « failed returncode »), `src/dos/dos_lib.s` l. 1708–1710 (« Please insert volume »,
     « Please replace volume », « in any drive »), l. 1998/2079 (`L:RAM-HANDLER`, `L:PORT-HANDLER`),
     `src/dos/bcpl.s` l. 2878 (« Error code ») ;
   - divers : « expansion ram », « Fast Memory », « Chip Memory », « Workbench Screen »,
     « System Request », `devs:system-configuration`.
   Toutes sont des textes affichés ou des noms d'ABI : (i).
6. **copinit** — `src/graphics/graphics_lib.s` l. 318–322 : WAIT `$0C01,$FFFE`, MOVE COPJMP2, fin
   `$FFFF,$FFFE` = la fin du copinit ROM (`graphics-display-v34.md` §2, offsets `$48`–`$57`) ; liste
   réduite (pas de pointeurs de sprites). (i).
7. **Gestionnaire d'exception à la forme SetPatch** — `src/exec/interrupts.s` l. 658–670 : forme
   « bsr.s + soustraction de 6 octets + `lsr.w 2(sp)` (`$E2EF $0002`) », imposée par SetPatch
   (`setpatch-disk-resource.md` §5.3, source = SetPatch, pas la ROM) ; contrainte d'interopérabilité.
   Le motif `$70E56000` n'apparaît pas dans `src/`.
8. **Instruction placée avant le point d'entrée** — `src/rom/start.s` l. 45 et `src/exec/boot.s`
   l. 167 (`dc.w $4E70`, RESET) : même disposition que celle que décrivait `coldstart-hardware-v34.md`
   §1.1 (reformulée ce jour en effet observable). Un mot.

### 3.2 Pas de correspondance

- **Keymap** : `src/exec/keymapdata.s` (généré par `tests/mk_keymaps.py`) est une table simple
  96 codes × (non shifté, shifté), sans structure KeyMap ni bits Capsable/Repeatable. Sur les 132
  valeurs comparables, 106 coïncident avec la keymap « usa » de la spec — ce sont les caractères
  ASCII de la disposition US — et 26 diffèrent (pavé numérique, touche `$30` qui donne `<`/`>` en
  ROM). Colonnes Alt, Ctrl, touches mortes, octets Capsable/Repeatable : absents de `src/`.
  Coïncidence imposée par la disposition, pas une copie.
- Symbole Amiga, motif de grisé `$4444/$1111` (src : rayures maison), textes du bandeau de copyright,
  bannière ROM, `$70E56000`, compteur 26 633 (src : 46 trames par phase) : absents de `src/`.

### 3.3 Chaînes de `src/` sans provenance dans les specs

`src/dos/workbench.s` l. 4294–4296 (« Warning: you cannot get back », « what you discard! »,
« OK to discard ») ressemblent aux textes du Workbench 1.3 mais n'apparaissent dans aucune spec de
`docs/analysis/` (ajoutées avec l'étape 10). Leur provenance (capture d'écran, documentation
publique) devrait être notée.

---

## 4. Recommandations

1. ~~Passe de nettoyage sur les 13 specs du §1.1~~ : faite le 2026-10-29 (§1.2).
2. Décider du sort des données (ii) : images de coche et du symbole Amiga
   (`intuition-input-menus-v34.md` 517–530) et géométrie au pixel des pictogrammes
   (`intuition-frame-v34.md` §5.3) — à remplacer par une description de principe si l'on veut que
   `src/` redessine librement.
3. Côté `src/` : la coche hires (`menus.s`) et les pictogrammes (`screens.s`) sont, respectivement,
   très proches et identiques aux images ROM ; à redessiner si l'objectif est l'indépendance
   graphique, à documenter comme reproduction d'apparence sinon.
