# coldstart-hardware-v34.md — Le coldstart d'exec 1.3 face au matériel réel d'un A500

> Spec **comportementale** (piste ANALYSE). Elle complète, sans les répéter,
> `boot-sequence.md` (ordre global), `exec-spec.md` (layout d'ExecBase), `module-map.md` (ROMTags) et
> `test-vectors.md`. Aucune suite d'instructions n'est recopiée, aucune adresse de routine de la ROM
> n'est citée : seulement des ordres d'opérations, des valeurs, des adresses matérielles publiques et
> de RAM basse, et des layouts d'ABI.
>
> Légende : **[O]** observé dans le binaire `kick34005.A500` (radare2, base `$FC0000`) ·
> **[S]** sondé en boîte noire sous FS-UAE avec la vraie ROM (`tests/coldhw_probe.sh`) ·
> **[D]** déduit (raisonnement sur [O]/[S] ou sur la doc matérielle publique, non exécuté).
>
> Cible matérielle : A500 rév. 5/6, Agnus 8370/8371 (512 Ko) ou 8372 (1 Mo), 512 Ko de chip, extension
> trappe 512 Ko à `$C00000` fréquente.

---

## 1. Tout premier code après le reset

### 1.1 Ce qui précède : vecteurs et overlay
- Au reset, l'overlay est actif (CIA-A DDRA = 0 après reset → la broche OVL, en entrée, est tirée
  haut) : la ROM apparaît en `$000000`. Le 68000 lit SSP = `$11114EF9` et PC = l'adresse du point
  d'entrée du coldstart dans la ROM. **[O]**
- Le mot `$4EF9` en ROM `+2` suivi de l'adresse du coldstart en `+4` forme une instruction « JMP
  absolu vers le coldstart » **exécutable à l'adresse 2** tant que l'overlay est actif. C'est ce qui rend
  possible la technique de reboot logiciel publique de l'ère 1.3 (§7.3). **Une ROM compatible doit
  garder cette forme** (`$1111`, `$4EF9`, puis l'adresse de son propre point d'entrée). **[O]**
- Le mot qui précède immédiatement le point d'entrée du coldstart, s'il est exécuté, réinitialise les
  périphériques (effet d'un reset logiciel, overlay remis) puis tombe dans le coldstart. Aucun code de
  la ROM n'y saute ; c'est une commodité placée à côté de l'entrée. **[O]**
- **État CPU à l'entrée** : superviseur, masque d'interruption 7 (état de reset du 68000). Le coldstart ne
  touche pas à SR avant la création de la tâche initiale (§4.4). **[O]**

### 1.2 Ordre exact des opérations (chemin commun froid/chaud)
1. Pose un SSP provisoire à **`$40000`** (le haut des 256 premiers Ko de chip). **[O]** Aucune écriture
   en pile n'a lieu avant le dimensionnement de la RAM : le code de démarrage n'utilise pas la pile,
   de sorte qu'une RAM défectueuse ne fait pas planter le diagnostic. **[O]**
2. **Temporisation d'environ 0,33 s** : attente CPU active (≈ 2,36 M cycles à 7,09 MHz PAL, depuis
   la ROM donc sans contention). **[O]** (durée **[D]**)
3. **Sonde de ROM de diagnostic à `$F00000`** : si la ROM ne s'exécute pas elle-même depuis `$F00000`
   et que le mot lu en `$F00000` vaut **`$1111`**, exec saute en **`$F00002`** en laissant dans A5
   l'adresse où reprendre le coldstart. L'overlay est encore actif à ce moment. **[O]**
4. **CIA-A** : DDRA ← `$03` (OVL et LED en sortie), puis PRA ← `$02` → **overlay levé** (OVL = 0, la
   chip RAM apparaît en `$000000`) et **LED d'alimentation atténuée** (bit 1 = 1 ; sur A500 ce bit
   coupe aussi le filtre audio). **[O]** Comme le registre PRA vaut 0 après un reset matériel, l'écriture
   de DDRA lève déjà l'overlay et allume brièvement la LED avant l'écriture de PRA. **[D]**
5. **Mise au silence des custom chips** : INTENA ← `$7FFF`, INTREQ ← `$7FFF`, DMACON ← `$7FFF`
   (tout coupé, y compris DMAEN). BPLCON0 ← `$0200` (couleur active, 0 plan), BPL1DAT ← 0. **[O]**
6. **COLOR00 ← `$444` (gris foncé)** — premier signe de vie visible. **[O][S]**
7. Remplit les vecteurs d'exception **`$08` à `$BC`** (46 longs : erreurs bus/adresse, illégale, …,
   autovecteurs, TRAP #0-15) avec un gestionnaire unique « écran **jaune** » (§8.6). **[O]**
8. Récupère une éventuelle **dernière alerte** en RAM basse (§8.2), puis tente la **survie à chaud**
   (§5). Sinon chemin **froid** : dimensionnement slow RAM (§3), puis chip (§2), puis effacement.
9. COLOR00 ← **`$888` (gris clair)** et DMACON ← `$7FFF` à nouveau, BPLCON0/BPL1DAT reposés : début de la
   construction d'ExecBase (chemins froid et chaud). **[O][S]**

### 1.3 Ce que le coldstart 1.3 NE fait PAS
- **Aucun test de checksum de la ROM.** Aucun code du binaire ne somme l'image ; le checksum
  « somme à retenue circulaire = `$FFFFFFFF` » est bien présent dans le fichier (vérifié : la somme des
  65 536 longs vaut `$FFFFFFFF`), mais rien ne le contrôle au boot. **[O]**
- **Aucun écran rouge ni bleu.** Les seules couleurs que le coldstart écrit dans COLOR00 sont `$444`,
  `$888`, `$CC0` (jaune) et `$0C0` (vert) ; le blanc `$FFF` vient de l'init de graphics.library. Toute
  table « rouge = ROM, bleu = custom chips » vient de Kickstarts ultérieurs. **[O]**
- Pas de test des custom chips, pas de test de motif sur toute la RAM, pas de compteur de resets. **[O]**

---

## 2. Détection et test de la chip RAM (chemin froid uniquement)

- **Plage sondée** : de `$000000` à `$200000` (exclu), **par pas de 4 Ko**. **[O]**
- **Méthode** **[O]** :
  1. écrire le long `0` en `$000000` (sentinelle anti-miroir) ;
  2. pour chaque frontière de 4 Ko `A = $1000, $2000, …` : écrire un long de motif de test (non nul,
     bits mélangés) en `A` ;
  3. arrêter dès que : (a) la sentinelle `$000000` n'est plus nulle (**miroir** : l'adresse a rebouclé
     sur 0) ; (b) la relecture de `A` diffère du motif ; (c) `A` atteint `$200000` ;
  4. `MaxLocMem` = la première adresse `A` en échec.
- **Miroirs selon l'Agnus** **[D]** : 8370/8371 décodent 512 Ko, l'écriture en `$80000` retombe en
  `$00000` → arrêt par (a) → 512 Ko. Une 8372 câblée en 1 Mo de chip donne `$100000` ; avec 512 Ko seuls
  le miroir à `$80000` donne encore 512 Ko. Sous FS-UAE : chip 256 → `$40000`, 512 → `$80000`,
  1024 → `$100000`. **[S]**
- **Seuil** : si `MaxLocMem < $40000` (moins de 256 Ko détectés) → **écran vert** `$0C0` (§8.6). **[O]**
- **Couverture réelle du test** : un seul long par tranche de 4 Ko. Un défaut ailleurs dans la tranche
  n'est pas vu ; un défaut sur une frontière au-delà de 256 Ko **réduit silencieusement** la chip
  détectée (ex. défaut à `$50000` → 320 Ko, boot normal). **[D]**
- Ensuite : le long en `$000000` est remis à 0, puis **toute la chip de `$0000C0` à `MaxLocMem` est mise
  à zéro** (les vecteurs `$08..$BC` posés à l'étape 7 sont donc préservés). **[O]**

---

## 3. Détection de la slow RAM `$C00000`–`$DBFFFF` (chemin froid uniquement)

Effectuée **avant** la chip. **[O]**

- **Plage** : de `$C00000` à `$DC0000` (exclu), **par blocs de 256 Ko** (max. 1,75 Mo). **[O]**
- **Adresses sondées** dans chaque bloc `[B, B+$40000)` : le mot en `B+$3F09A` et le mot en
  `B+$3F01C` — c'est-à-dire, modulo 512 octets, les offsets **INTENA (`$09A`) et INTENAR (`$01C`)**.
  **[O]**
- **Piège `$DFF000` (registres custom en miroir)** : sur A500, une plage `$C00000+` sans RAM répond par
  un **miroir des registres custom** (décodage partiel). Pour chaque bloc **[O]** :
  1. écrire `$3FFF` à l'emplacement « INTENA » (efface les bits 0-13) ; lire l'emplacement « INTENAR » ;
     si la valeur lue est **non nulle**, ce ne sont pas des registres → test RAM ;
  2. sinon écrire `$BFFF` (pose les bits 0-13) ; si « INTENAR » relit **`$3FFF`**, ce sont les
     registres → **fin de la slow RAM** ; exec réécrit alors `$7FFF` (tout effacé) à cet emplacement.
  - Effet de bord : INTENA réel est brièvement chargé de `$3FFF` ; sans danger car SR masque tout. **[D]**
- **Test RAM d'un bloc** **[O]** :
  1. écrire `0` à l'emplacement de référence du **premier** bloc (`$C3F09A`) ;
  2. écrire un premier mot de motif à l'emplacement sondé du bloc courant, relire → différent = fin ;
  3. si la référence est restée nulle : écrire un second mot de motif, relire → différent = fin, égal =
     bloc accepté ;
  4. si la référence vaut le premier motif : premier bloc (même adresse) → on passe à l'étape 3 ; **autre bloc
     (miroir du premier) → bloc accepté sans 2ᵉ motif**.
  - **Anomalie** : un module qui se répète en miroir dans `$C00000+` serait donc compté jusqu'à la
    limite. Une A501 ne se répète pas (le bloc suivant tombe sur les registres en miroir, arrêt correct).
    Ne pas compter sur cette branche ; une réimplémentation peut traiter le miroir comme une fin. **[D]**
- **Résultat** : `MaxExtMem` = fin de la dernière tranche acceptée, ou **0** si aucune. Si présente, la
  slow RAM est **entièrement mise à zéro** (`$C00000` → `MaxExtMem`). **[O]**
- FS-UAE : slow 0 → `MaxExtMem = 0` (le miroir de registres est émulé) ; 512 → `$C80000` ;
  1024 → `$D00000` ; 1536 → `$D80000`. **[S]**

---

## 4. Placement d'ExecBase, pile superviseur, MemList (complément d'`exec-spec.md`)

### 4.1 Adresse d'ExecBase
- `ExecBase = base_RAM + $400 + $276` (`$276` = taille de la table LVO d'exec, cf. `lib_NegSize`). **[O]**
  - sans slow RAM : **`$00000676`** ; **avec slow RAM : `$00C00276`** (ExecBase en RAM `$C00000`). **[O][S]**
- En-tête de library posé : `LN_Type = 9`, `LN_Pri = 0`, `lib_Flags = 6`, `lib_PosSize = $024C`,
  version 34 rév. 2, `lib_OpenCnt = 1` ; `lib_NegSize` reçoit la taille de la table construite. **[O]**
  → la structure ExecBase V34 occupe **`$24C` octets** côté positif.
- `*(ULONG*)4 = ExecBase`, `ChkBase = ~ExecBase`. **[O]**

### 4.2 Pile superviseur
- Sommet = `MaxExtMem` si de la slow RAM existe, sinon `MaxLocMem`. `SysStkUpper` = ce sommet,
  `SysStkLower = SysStkUpper − $1800` (**6 Ko**). **[O][S]**

### 4.3 MemList construite **[O][S]**
| Config | MemHeader | Nom | Attributs | Pri | Plage déclarée |
|---|---|---|---|---|---|
| sans slow | à `ExecBase+$24C` | `Chip Memory` | `$0003` | −10 | `ExecBase+$24C` → `MaxLocMem − $1800` |
| avec slow | à `ExecBase+$24C` | `Fast Memory` | `$0005` (PUBLIC\|FAST) | 0 | `ExecBase+$24C` → `MaxExtMem − $1800` |
| avec slow | à `$400` | `Chip Memory` | `$0003` | −10 | `$400` → `MaxLocMem` (pile absente de la chip) |

- La slow RAM d'un A500 est donc présentée comme **« Fast Memory » MEMF_FAST**, de priorité supérieure à la
  chip : les allocations sans MEMF_CHIP y vont d'abord. **[S]**
- Valeurs mesurées (512 Ko chip) : sans slow → header `$8C2`, `mh_Lower = $8E8`, `mh_Upper = $7E800` ;
  avec 512 Ko slow → Fast `$C004C2`/`$C004E8`/`$C7E800`, Chip `$400`/`$420`/`$80000`. **[S]**

### 4.4 Interruptions et DMA à la fin du coldstart **[O]**
- Après installation des serveurs d'interruption : INTENA ← `$8004` (SOFTINT seul), puis DMACON ←
  `$8200` (DMAEN, aucun canal), INTENA ← `$C000` (maître), `IDNestCnt = TDNestCnt = −1`.
- Ensuite la tâche initiale est créée et **SR passe à 0** (mode utilisateur, interruptions démasquées) :
  CoolCapture, InitCode et le bootblock tournent **en mode utilisateur** (le bootblock aussi : une
  instruction privilégiée y provoque un Guru `#00000008`). **[O][S]**
- Les canaux DMA d'affichage et le **blanc** (`COLOR00 = COLOR01 = $FFF`, DMACON `$81A0`) arrivent avec
  l'init de graphics.library (pri 65). **[O][S]**

---

## 5. Survie au reset à chaud

### 5.1 Validation d'un ExecBase existant (ordre exact) **[O]**
1. `*(ULONG*)4` doit être **pair** ;
2. `ExecBase + ChkBase` doit valoir `$FFFFFFFF` ;
3. la somme 16 bits des **25 mots de `+$22` à `+$52`** inclus (`SoftVer` … `ChkSum`) doit valoir
   **`$FFFF`** ; à l'init, `ChkSum` reçoit le complément de la somme des mots `+$22..+$4E` (le mot
   `+$50`, moitié basse de `MaxExtMem`, est exclu à la pose mais inclus au contrôle — il vaut toujours 0
   puisque `MaxExtMem` est multiple de 256 Ko) ;
4. **ColdCapture** : si non nul, il est **remis à 0 puis appelé** (saut, retour par l'adresse fournie dans
   A5), en superviseur, SR = `$2700`, overlay levé, SSP = `$40000`, A6 = ExecBase ; **avant** les
   contrôles suivants ;
5. bascule du bit LED (la LED repasse brillante) ;
6. le long `+$14` (version.révision) doit égaler celui de la ROM, **`$00220002`** (34.2) ;
7. **`$40000 ≤ MaxLocMem ≤ $80000`** ;
8. `MaxExtMem` = 0, ou **`$C40000 ≤ MaxExtMem ≤ $DC0000` et multiple de `$40000`**.

Tout échec → chemin froid (ExecBase reconstruit, RAM effacée, pointeurs Kick perdus).

- **Conséquence A500 1 Mo de chip (8372)** : `MaxLocMem = $100000` échoue au point 7 → **chaque reset
  est un démarrage à froid** : RAM effacée, KickMem/KickTag/CoolCapture/WarmCapture perdus (seul
  ColdCapture, appelé avant le test, a encore lieu). Prouvé : sous FS-UAE chip 1024 Ko, un marqueur en
  chip et en slow est effacé à chaque reboot. **[O][S]**

### 5.2 Ce que le chemin chaud conserve ou réécrit **[O]**
- Mémoire : **rien n'est effacé** en chip ni en slow. Les MemHeaders sont reconstruits comme au froid
  (toute la RAM est redéclarée libre, contenu intact). Un marqueur en `$60000` (chip) et en `$C40100`
  (slow) survit au reboot. **[S]**
- ExecBase : les **126 longs de `+$54` à `+$24B`** sont mis à zéro (IntVects, listes, `LastAlert`,
  `VBlankFrequency`…), **sauf `KickMemPtr`, `KickTagPtr`, `KickCheckSum`** sauvegardés et restaurés.
  Les vecteurs Capture (`+$2A..+$35`) ne sont pas touchés (ColdCapture déjà effacé à l'étape 4).
  `SysStkUpper/Lower`, `MaxLocMem`, `MaxExtMem`, `ChkBase` sont réécrits. **[O]**
- Sondé : ColdCapture appelé une fois puis lu à 0 au boot suivant ; CoolCapture appelé et conservé. **[S]**

### 5.3 KickMemPtr / KickTagPtr / KickCheckSum **[O]**
- Après le balayage des ROMTags, exec recalcule la somme Kick (**même routine que `SumKickData`**,
  LVO −612) et la compare à `KickCheckSum` :
  - départ `$FFFFFFFF` ;
  - pour chaque `MemList` de la chaîne `KickMemPtr` (suivie par `LN_Succ`) : ajout de
    **`2·ml_NumEntries + 5` longs** consécutifs depuis le début du nœud (soit tout le nœud **plus un
    long de plus**, particularité à reproduire) ;
  - puis, pour la table `KickTagPtr` : ajout de chaque entrée positive ; une entrée à bit 31 posé est un
    lien (bit effacé → table suivante, non sommée) ; 0 termine.
- Égalité → chaque entrée de chaque `MemList` est réservée par **AllocAbs** ; si **toutes** réussissent,
  les ROMTags de `KickTagPtr` sont fusionnés. Sinon les KickTags sont ignorés (silencieusement).
- **Préséance** lors de la fusion (par `rt_Name`) : le nouveau remplace l'ancien si sa version est
  supérieure, ou égale avec une priorité supérieure ou égale ; ordre de balayage : ROM `$FC0000–$FFFFFF`,
  puis `$F00000–$F7FFFF`, puis KickTags.
- CoolCapture est appelé (JSR, en mode **utilisateur**, multitâche actif, A6 = ExecBase) après la
  construction de `ResModules` et l'allumage de la LED, juste avant `InitCode(RTF_COLDSTART)` ;
  WarmCapture juste après le retour d'InitCode — ce qui, en pratique, n'arrive pas (strap passe la main à
  DOS). **[O]** (dernier point **[D]**)

### 5.4 Compteur de reset
- **Aucun** dans exec 1.3. **[O]**

---

## 6. RAM effacée / préservée — synthèse

| Zone | Froid (power-on ou ExecBase invalide) | Chaud (ExecBase validé) |
|---|---|---|
| `$000000` (long) | lu (`HELP` ?) puis mis à 0 | mis à 0 seulement si `HELP` y était |
| `$000004` | ExecBase | ExecBase (inchangé) |
| `$08–$BC` vecteurs | jaune provisoire, puis vecteurs exec | idem (réécrits) |
| `$C0–MaxLocMem` | **mis à 0** | **préservé** |
| `$100`/`$104` (dernière alerte) | lus puis effacés avec le reste | **préservés** (relus au boot suivant) [S] |
| slow RAM | **mise à 0** | **préservée** |
| ExecBase `+$54..+$24B` | neuf (zéro) | zéro sauf `Kick*` |

- Effacement à froid : environ 0,4 s par 512 Ko (≈ 22 cycles par long, sans DMA) → ≈ 0,4 s sans
  extension, ≈ 0,8 s avec 512 Ko de slow. **[D]**
- Une exception CPU d'une tâche écrit **tous les registres en `$180–$1BF`** (RAM basse). **[O]**

---

## 7. Resets

### 7.1 Reset clavier (Ctrl-Amiga-Amiga)
- **Purement matériel** pour l'essentiel : le contrôleur clavier tient KCLK bas (≈ 500 ms) et la carte
  mère génère le /RESET système (CPU **et** puces) → la ROM repart du vecteur avec l'overlay, RAM
  intacte → **chemin chaud** si ExecBase valide (§5). **[D]** (doc matérielle publique)
- **Avertissement de reset** côté keyboard.device 1.3 **[O]** : le code clavier **`$78`** reçu **deux
  fois de suite** déclenche, à la 2ᵉ occurrence, un `Cause()` sur chaque handler de la liste
  `KBD_ADDRESETHANDLER` et un compteur de handlers en cours ; **la poignée de main (KDAT tenu bas via
  SPMODE de CIA-A) n'est pas relâchée** tant que tous n'ont pas appelé `KBD_RESETHANDLERDONE` ; le
  dernier relâche la poignée. Sans handler, la poignée est relâchée aussitôt. Le premier `$78` est
  traité comme un code ordinaire.
- Le clavier attend ensuite (max. ≈ 10 s selon la doc publique) puis provoque le reset matériel. **[D]**

### 7.2 Chemin de reboot interne de la ROM **[O]**
Utilisé par les écrans d'erreur (§8.6), le chemin « dur » d'Alert (§8.3) et le clic gauche après une
exception CPU :
1. temporisation ≈ 0,33 s (même boucle qu'au §1.2) ;
2. instruction **`RESET`** (≈ 124 cycles de /RESET : les CIA reviennent à zéro → **overlay remis**) ;
3. lecture du long en `$000004` — qui, overlay revenu, est le **vecteur PC de la ROM** — et saut.
- Le CPU n'est pas réinitialisé par `RESET` : seul l'état laissé dans les registres change. RAM intacte →
  chemin chaud. **[D]**

### 7.3 Reboot logiciel « ColdReboot-like » (1.3 n'a pas `ColdReboot`, LVO −726 = V36)
- Technique publique : en superviseur (via `Supervisor()`), A0 = 2, puis `RESET` et `JMP (A0)` **dans le
  même long aligné** (le saut est déjà dans la file de préchargement quand la chip disparaît sous
  l'overlay). À l'adresse 2 l'overlay présente `JMP coldstart` (§1.1). **[S]** (sondé : reboot propre,
  ExecBase réutilisé, marqueurs chip et slow conservés)
- Depuis un bootblock (mode utilisateur), un `RESET` direct produit un Guru `#00000008.<tâche>`. **[S]**

---

## 8. Alert() et alert.hook

### 8.1 Alert(alertNum D7, A5) en V34 **[O]**
- Le **second nombre** du Guru est **le long lu à l'adresse contenue dans A5** (pas A5 lui-même). Prouvé :
  A5 → `$CAFEBABE` affiche `#8100000F.CAFEBABE`. **[S]** Pour une exception de tâche, A5 pointe
  `ExecBase.ThisTask` → second nombre = adresse de la tâche.
- Les exceptions CPU d'une tâche (vecteur → `TaskTrapCode` par défaut) entrent dans le même code avec
  `alertNum = numéro de vecteur` (`$00000003` adresse, `$00000004` illégale, `$00000008` privilège…).

### 8.2 Persistance en RAM basse **[O][S]**
- `$000000` ← **`'HELP'` (`$48454C50`)**, `$000100` ← alertNum, `$000104` ← second nombre.
- Au reset suivant, le coldstart voit `HELP` en `$0`, efface ce long et recopie `$100`/`$104` dans
  `LastAlert[0..1]` (`+$202`/`+$206`) ; sinon `LastAlert[0] = $FFFFFFFF`. Fonctionne aussi bien à froid
  qu'à chaud (valeurs gardées en registres pendant l'effacement). **[O][S]**

### 8.3 Arbre de décision d'Alert **[O]**
1. INTENA ← `$4000` (interruptions maître coupées).
2. `HELP` déjà présent en `$0` (alerte imbriquée) → **chemin dur**.
3. Écrit `HELP`/`$100`/`$104`.
4. **Validité d'ExecBase** : `*(4) & $00FF0001` doit être **nul** (pair **et inférieur à `$10000`**) et
   `ChkBase` cohérent ; sinon **chemin dur**.
   → **Avec slow RAM, ExecBase est en `$C00276` : TOUTE alerte, même récupérable, prend le chemin dur**
   (reset puis affichage au boot suivant). Prouvé : `Alert($35000001)` sous 512+512 Ko → reboot puis
   « Recoverable Alert » affiché par alert.hook ; l'appelant ne reprend jamais la main. **[S]**
5. Test de pile superviseur/utilisateur (écrit puis relit un long de motif) ; échec → SSP ← `$40000`, chemin dur.
6. Bit 31 (dead-end) → chemin dur.
7. Sinon : `LastAlert` ← (alertNum, second nombre) et **affichage immédiat** (routine d'alert.hook, §8.4).
   - mot haut d'alertNum ≠ 0 (appel `Alert()` récupérable) : interruptions réactivées si `IDNestCnt < 0`,
     retour à l'appelant ;
   - mot haut = 0 (exception CPU) : registres restaurés depuis `$180` ; **bouton gauche → reboot**
     (§7.2), **bouton droit → débogueur ROM-Wack** (série).

**Chemin dur** **[O]** : CIA-A DDRA |= 3 et OVL forcé à 0, vecteur `$20` (violation de privilège)
redirigé pour garantir le passage en superviseur, SR ← `$2700`. Puis **6 tours** de : SERPER ←
**`$0174`** (≈ 9600 bauds), **LED atténuée puis brillante** (attente CPU de durée égale pour chaque
phase, rythmée par des accès CIA synchronisés sur l'horloge E), lecture de SERDATR, effacement de RBF dans INTREQ ; si le caractère reçu
(7 bits) vaut **`$7F` (DEL)** → entrée dans **ROM-Wack**. Après 6 tours sans DEL → reboot (§7.2).
L'écran **n'est pas modifié** pendant ce temps. Durée ≈ 5-6 s sous FS-UAE avant le reboot. **[S]**

### 8.4 alert.hook (résident pri 5, type UNKNOWN) **[O][S]**
- Son `rt_Init` est **la même routine** que l'affichage immédiat d'Alert. Lancé dans
  `InitCode(RTF_COLDSTART)` après intuition (pri 10), donc après le blanc de graphics.
- **Temporisation fixe ≈ 1 s à chaque boot** (attente CPU active), **avant** de regarder
  s'il y a une alerte. **[O]** (durée **[D]**)
- Si `LastAlert[0] = $FFFFFFFF` → retour sans rien faire.
- Sinon, texte au format DisplayAlert (x sur 16 bits, y sur 8 bits, chaîne, octet de continuation) :
  - ligne 1, y = 15 : x = 38 → en-tête selon alertNum : octet bits 16-23 = `$01` (AG_NoMemory) →
    `Not enough memory. ` ; sinon bit 31 = 0 et bits 16-31 ≠ 0 → `Recoverable Alert. ` ; sinon
    `Software Failure. ` ; puis x = 234 → `Press left mouse button to continue.` ;
  - ligne 2, y = 30, x = 142 → `Guru Meditation #%08lx.%08lx` (`LastAlert[0]`, `LastAlert[1]`).
- Ouvre `intuition.library` (version 0) ; appelle **DisplayAlert avec alertNumber = 0** et une hauteur
  de **40** lignes, puis ferme la library. Si l'ouverture échoue : rien n'est affiché.
- Ensuite, **toujours** : `$000000` ← 0, `LastAlert[0]` ← `$FFFFFFFF` (`LastAlert[1]`, `$100` et `$104`
  ne sont **pas** effacés). Retourne le résultat de DisplayAlert (gauche = vrai).
- Rendu observé : texte et **cadre rouges**, cadre **clignotant**, fond quasi noir, **attente du clic
  sans délai d'expiration** (affiché 8 s jusqu'au clic dans la sonde). Même en rouge pour
  « Recoverable Alert ». Après le clic, le boot reprend (le bootblock s'exécute). **[S]**

### 8.5 Récapitulatif des cas d'alerte (A500 512 Ko)
| Cas | Sans slow RAM | Avec slow RAM `$C00000` |
|---|---|---|
| `Alert()` récupérable | affichage immédiat puis retour **[O]** (non affiché sous FS-UAE, cf. §10) | reboot, puis Guru au boot suivant **[S]** |
| `Alert()` dead-end | LED ×6, reboot, Guru au boot suivant **[O]** | idem **[S]** |
| Exception CPU d'une tâche | Guru immédiat **[S]** (`#00000008`) ; gauche → reboot, droit → ROM-Wack **[O]** | reboot, puis Guru au boot suivant, le clic gauche **poursuit le boot** **[S]** (`#00000004`) |

### 8.6 Couleurs d'erreur du coldstart **[O]**
Une seule routine d'erreur : BPLCON0 ← `$0200`, BPL1DAT ← 0, **COLOR00 ← couleur**, puis **11
clignotements de la LED** (≈ 0,5 s atténuée, ≈ 0,25 s brillante), puis reboot (§7.2) —
d'où une **boucle de reset** si la panne est permanente.

| COLOR00 | Signification |
|---|---|
| `$444` gris foncé | coldstart démarré (après ≈ 0,33 s) |
| `$888` gris clair | RAM dimensionnée, construction d'ExecBase |
| `$FFF` blanc | graphics.library initialisée |
| **`$0C0` vert** | moins de 256 Ko de chip détectés (§2) |
| **`$CC0` jaune** | exception CPU (vecteurs `$08..$BC`) avant l'installation des vecteurs d'exec |

Durée d'un écran d'erreur : ≈ 11 × (0,5 + 0,25) s ≈ 8-9 s avant le reset. **[D]**

---

## 9. Chronologie et temporisations sur A500 réel (estimations **[D]**, 7,09 MHz PAL)

| Étape | Durée | Écran |
|---|---|---|
| boucle initiale | ≈ 0,33 s | indéfini (souvent noir) |
| sizing + effacement slow (512 Ko) | ≈ 0,4 s | `$444` |
| sizing + effacement chip (512 Ko) | ≈ 0,4 s | `$444` |
| balayage ROMTags `$FC0000–$FFFFFF` | ≈ 0,33 s | `$888` |
| balayage `$F00000–$F7FFFF` (vide sur A500) | ≈ 0,66 s | `$888` |
| init résidents jusqu'à graphics | — | blanc |
| alert.hook | ≈ 1 s fixe | blanc |

Sous FS-UAE (non cycle-exact) la séquence observée est noir → `$444` → `$888` → blanc en ≈ 2-3 s de temps
réel. **[S]** Le chemin chaud saute les deux lignes « sizing + effacement ».

Autres faits : `VBlankFrequency` est posé par graphics.library (50/60 selon PAL/NTSC) et
`PowerSupplyFrequency` par timer.device (mesure de la TOD de CIA-A cadencée par le secteur). Mesuré
50/50 en config A500 PAL. **[O][S]**

---

## 10. Vrai A500 vs émulateur — écarts attendus

1. **Contenu RAM à la mise sous tension** : FS-UAE part d'une RAM à zéro ; un vrai A500 a une RAM
   aléatoire. Effets : validation d'ExecBase quasi toujours en échec (correct) ; `HELP` en `$0` par
   hasard négligeable. **Une coupure courte** peut laisser la DRAM intacte → chemin **chaud** (Capture,
   KickTags, dernière alerte) après un « power-cycle » rapide. **[D]**
2. **Lecture de `$F00000`** : non décodée sur A500 (bus flottant) ; l'émulateur renvoie une valeur fixe.
   Un `$1111` parasite y détournerait le boot ; aucun cas connu, mais c'est une lecture non déterministe
   sur le vrai matériel. Idem pour le balayage `$F00000–$F7FFFF` (`$4AFC` + auto-pointeur requis). **[D]**
3. **Miroir des registres en `$C00000`** : dépend du décodage Gary/Agnus du vrai A500 ; FS-UAE l'émule
   (slow 0 → `MaxExtMem = 0`). Une extension trappe non standard (décodage partiel, 1,5 Mo, cartes
   « 1 Mo » à `$C00000`) peut tomber dans la branche « miroir accepté » du §3. **[S][D]**
4. **Timings** : toutes les temporisations sont des boucles CPU (+ accès CIA synchronisés sur l'horloge E
   pour la LED). En mode non cycle-exact, FS-UAE peut les raccourcir ; utiliser A500 cycle-exact pour
   comparer. **[D]**
5. **8372 / 1 Mo de chip** : reset à chaud impossible (§5.1). Sous émulateur, une config « chip 1024 » le
   reproduit fidèlement (boucle de reboot de la sonde). **[S]**
6. **Slow RAM** : la majorité des A500 réels ont une trappe 512 Ko → ExecBase en `$C00276` → **toute
   alerte provoque un reset** (§8.3). Tester notre ROM dans les deux configurations.
7. **`Alert()` récupérable sans slow RAM** : sous FS-UAE la machine reste figée (pas d'affichage, ni retour
   en 60 s) avec INTENA maître coupé et le CPU qui entre en boucle dans le point d'entrée des
   interruptions de niveau 6 pendant la temporisation d'alert.hook. Sur matériel réel Paula ne lève pas
   d'IPL avec INTEN = 0, ce blocage est donc probablement un artefact d'émulateur. **[S]** (interprétation **[D]**)
8. **Reset clavier** : FS-UAE déclenche en général un reset direct sans passer par la séquence `$78`/KCLK ;
   sur A500 réel, prévoir la poignée de main de reset du §7.1. **[D]**
9. **LED** : invisible sous émulateur sauf indicateur ; sur machine réelle elle sert de diagnostic
   (atténuée au reset, brillante quand la liste des résidents est prête ; clignote 6× pour un dead-end,
   11× pour vert/jaune). **[O]**

---

## 11. Sondes (reproductibles)

- `tests/coldhw_probe.s` + `tests/coldhw_probe.sh <mode> <chip_ko> <slow_ko> <durée> ["clics"] ["captures"]`
  (variable `COLDHW_OUT` obligatoire) : bootblock auteur qui imprime sur la série ExecBase, `MaxLocMem`,
  `MaxExtMem`, piles, Capture, `LastAlert`, MemList et RAM basse, compte les boots dans un marqueur chip et
  slow, puis selon le mode : 1 dead-end, 2 récupérable, 3 ILLEGAL, 4 reboot logiciel, 5 Cold/CoolCapture.
- Résultats clés : §3, §4.3, §5.1-5.2, §7.3, §8.2-8.5.

---

## Points non tranchés

- **Reset clavier sur A500** : le contrôleur clavier A500 envoie-t-il réellement l'avertissement `$78` (deux
  fois) avant de tenir KCLK bas, et avec quel délai maximal ? Le code 1.3 le gère, le matériel A500
  précis n'a pas été vérifié.
- **Lignes touchées par l'instruction `RESET` sur A500** (CIA certainement ; Agnus/Paula selon la
  révision de carte) : sans incidence sur la suite puisque exec réinitialise DMACON/INTENA, mais non vérifié.
- **`Alert()` récupérable sans slow RAM** : affichage immédiat attendu d'après le code, non observé sous
  FS-UAE (§10 point 7). À confirmer sur machine réelle ou WinUAE cycle-exact ; on ignore aussi si
  DisplayAlert 1.3 fonctionne avec INTEN coupé.
- **Couleur du Guru** : DisplayAlert reçoit toujours `alertNumber = 0`, pourtant le rendu est rouge même
  pour « Recoverable Alert » (FS-UAE). La règle de couleur interne d'intuition 1.3 n'a pas été analysée.
- **Branche « miroir accepté » de la slow RAM** (§3) : anomalie lue dans le code, non provoquée en sonde
  (FS-UAE n'émule pas de module qui se répète).
- **Valeur lue en `$F00000` sur un A500 réel** (bus flottant) : non mesurée.
- **Durées sur matériel réel** : toutes les durées du §9 et des clignotements sont calculées (cycles
  68000 + estimation des attentes d'horloge E), pas chronométrées.
- **WarmCapture** : appelé seulement si `InitCode(RTF_COLDSTART)` revient ; qu'il ne revienne jamais
  sur un boot disquette normal est déduit, non prouvé.

## Relecture clean-room

Relecture du 2026-10-29.

- [x] Aucun extrait de désassemblage ; les séquences numérotées (§1.2, §2, §3, §5.1, §8.3) décrivent
  l'ordre des **accès matériels et RAM observables** (registres custom, CIA, couleurs, RAM basse) et
  les conditions de décision, pas l'enchaînement des instructions.
- [x] **Corrigé** : retirée l'adresse ROM du point d'entrée du coldstart (valeur du PC de reset) ; la
  contrainte « 8 premiers octets à l'identique » reformulée en forme d'en-tête (une ROM compatible a son
  propre point d'entrée).
- [x] **Corrigé** : retirés les détails qui relevaient du code plutôt que du comportement : nom et
  opcode de l'instruction placée avant le point d'entrée (remplacés par son effet), mention du mode
  d'enchaînement des sous-routines (« pas de BSR/JSR »), nombres d'itérations des boucles de
  temporisation (remplacés par les durées), valeurs des motifs de test RAM et de pile (remplacés par
  « motif de test », la valeur exacte n'ayant aucune portée d'ABI).
- [x] Restent : adresses matérielles/RAM publiques (`$000000`, `$C00000`, `$DFF0xx`, `$BFE001`,
  `$F00000`, RAM basse `$100`/`$104`/`$180`), valeurs écrites dans les registres (couleurs, INTENA,
  DMACON, SERPER), offsets publics d'ExecBase, règles de validation du reset à chaud et de la somme
  Kick (comportement de compatibilité).
- [x] La sonde citée (`tests/coldhw_probe.s`) est du code auteur.
