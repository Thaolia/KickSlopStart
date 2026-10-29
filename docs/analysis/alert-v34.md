# alert-v34.md — Alert, DisplayAlert et alert.hook dans le Kickstart 1.3 (34.5)

> Spec **comportementale** (piste ANALYSE, spec n° 3 de `coverage-v34.md` §7). Elle **complète sans la
> répéter** `coldstart-hardware-v34.md` §8 (persistance `HELP`/`$100`/`$104`, arbre de décision d'Alert,
> chemin dur avec clignotement LED et ROM-Wack, temporisation et texte d'alert.hook), auquel elle renvoie.
> Aucune suite d'instructions n'est recopiée ni paraphrasée, aucune adresse de routine de la ROM n'est citée :
> seulement des comportements, des valeurs, des textes affichés, des ordres d'opérations et des layouts d'ABI.
>
> Légende : **[O]** observé dans le binaire `kick34005.A500` (radare2, base `$FC0000`) ·
> **[S]** sondé en boîte noire sous FS-UAE (A500, vraie ROM ; `tests/alert_probe.sh`, `tests/coldhw_probe.sh`) ·
> **[D]** déduit (raisonnement sur [O]/[S] ou doc matérielle publique, non exécuté).

---

## 1. exec `Alert(alertNum = D7, A5)` — LVO −108

### 1.1 Rappel de l'arbre (détails dans `coldstart-hardware-v34.md` §8.1-8.3)
- Premier effet : **INTENA ← `$4000`** (maître coupé), sans toucher à `IDNestCnt`. **[O]**
- Écrit `'HELP'` en `$0`, alertNum en `$100`, **le long pointé par A5** en `$104`. **[O]**
- **Chemin dur** (LED ×6 + écoute série DEL → ROM-Wack, sinon reset ; écran non modifié) si l'un des cas
  suivants : `HELP` déjà présent (alerte imbriquée) ; ExecBase jugé invalide (`*(4) & $00FF0001 ≠ 0`, donc
  aussi **toute ExecBase en slow RAM `$C00276`**, ou `ExecBase + ChkBase ≠ $FFFFFFFF`) ; la pile courante ne
  relit pas un long écrit ; **bit 31 posé (dead-end)**. **[O]**
- Sinon **affichage immédiat** par la même routine que le résident alert.hook (§4), précédé de la
  temporisation fixe de ≈ 1 s de cette routine (interruptions maîtresses toujours coupées). **[O]**

### 1.2 Distinction récupérable / fatale — ce que voit l'appelant
| alertNum | Chemin | Retour à l'appelant |
|---|---|---|
| bit 31 = 1 (dead-end, `AT_DeadEnd`) | toujours chemin dur → reset → Guru au boot suivant par alert.hook | **jamais** |
| bit 31 = 0, mot haut ≠ 0 (récupérable, appel `Alert()` normal) | affichage immédiat si ExecBase « basse » et valide ; sinon chemin dur | oui (cas immédiat seulement) |
| mot haut = 0 (numéro de vecteur : exception CPU d'une tâche) | affichage immédiat, puis **gauche → reset**, **droit → ROM-Wack** | jamais |

- Le test « récupérable » se fait **sur le mot haut entier** (`alertNum & $FFFF0000 ≠ 0`), pas sur un bit
  dédié : un `Alert($00000005)` appelé par un programme est traité comme une **exception CPU** (pas de
  retour : reset ou ROM-Wack selon le bouton). Pire : ce chemin recharge **tous les registres, A7 compris,
  depuis `$180-$1BF`**, zone qu'un appel `Alert()` n'a pas remplie (restes de la dernière exception ou
  zéros). Une réimplémentation peut traiter ce cas comme une alerte récupérable sans risque de
  compatibilité connu. **[O]** (portée **[D]**)
- **Retour d'un `Alert()` récupérable** **[O]** :
  - interruptions : si `IDNestCnt < 0` (appelant non `Disable()`), INTENA ← `$C000` ; sinon le maître
    **reste coupé** (l'appelant fera `Enable()`) ;
  - **D0** = valeur rendue par DisplayAlert (1 = bouton gauche, 0 = bouton droit). Si intuition n'a pas pu
    être ouverte, D0 = **valeur d'A2 à l'entrée** (indéfinie) ;
  - **D7 est modifié** : il ressort avec `alertNum & $FFFF0000` (mot bas effacé). D1/A0/A1 détruits,
    **A6 = ExecBase**, A2-A5 et D2-D6 conservés. Une réimplémentation peut préserver D7 (aucun appelant connu
    ne lit D7 après Alert) mais doit rendre le booléen en D0. **[O]** (portée **[D]**)
- `LastAlert[0..1]` reçoit (alertNum, long pointé par A5) avant l'affichage ; après l'affichage, la routine
  remet `$0` à 0 et `LastAlert[0]` à `$FFFFFFFF` (le Guru n'est donc **pas** réaffiché au reset suivant).
  `$100`/`$104` et `LastAlert[1]` gardent leurs valeurs. **[O]**

### 1.3 Disponibilité d'intuition
- La routine d'affichage ouvre `intuition.library` (version 0) par `OpenLibrary` puis la referme. **[O]**
  - Ouverture impossible (alerte avant l'init d'intuition, pri 10 ; ou library retirée) : **rien n'est
    affiché**, `$0` et `LastAlert[0]` sont quand même remis à 0 / `$FFFFFFFF`, et la valeur « rendue » est
    indéfinie (A2). Pour une exception CPU, la décision reset / ROM-Wack dépend alors de cette valeur
    indéfinie (A2 de la tâche fautive ≠ 0 → reset). **[O]**
  - Il n'existe **aucun autre repli** d'affichage dans exec 1.3 (pas d'écran rouge maison, pas de texte
    série) : sans intuition, seul le chemin dur (LED) est visible. **[O]**
- Avant l'init d'intuition (résidents de priorité > 10), une alerte « récupérable » est donc perdue en
  silence ; une dead-end passe par reset et sera affichée **au boot suivant** par alert.hook, après intuition.
  **[D]**

### 1.4 État du système pendant l'affichage immédiat
- INTENA maître coupé à l'entrée ; **aucun** `Disable()`/`Forbid()` explicite ; le multitâche n'est pas
  arrêté par exec. La routine d'affichage appelle `OpenLibrary`, puis DisplayAlert qui appelle
  `ObtainSemaphore`, `AllocMem`, et le recalcul d'affichage d'intuition (dont **`WaitTOF`**). **[O]**
- Conséquence : DisplayAlert **ne peut se terminer que si l'interruption VBlank est servie** (WaitTOF). Le
  premier `Enable()` qu'exécute une fonction appelée (exec `Wait`, etc.) rétablit le maître puisque
  `IDNestCnt` est resté négatif. Voir §5 point 6 (blocage observé sous FS-UAE) et « Points non tranchés ». **[D]**
- DMA : seul le DMA **sprite** est coupé pendant l'attente du clic (§2.6) ; bitplanes, copper, blitter,
  disque et audio continuent. **[O]**

---

## 2. intuition `DisplayAlert(alertNumber = D0, string = A0, height = D1)` — LVO −90

### 2.1 Format de la chaîne **[O][S]**
Suite de blocs, chacun :
| Octets | Contenu |
|---|---|
| 2 | **x** (mot 16 bits gros-boutiste, en pixels hires) |
| 1 | **y** (octet, ligne de **base** du texte, en lignes non entrelacées depuis le haut de l'alerte) |
| n+1 | texte ASCII terminé par `0` |
| 1 | **octet de continuation** : ≠ 0 → un autre bloc suit immédiatement ; 0 → fin |

- Chaque bloc = `Move(x, y)` puis `Text()` de la chaîne entière ; aucun retour à la ligne ni découpage. **[O]**
- **Aucun clipping** : le RastPort de l'alerte n'a pas de layer. Un y supérieur à la hauteur, ou un texte
  dépassant la largeur, écrit **hors du raster** (corruption mémoire chip). Le contrat implicite est que
  l'appelant reste dans le cadre. **[O]** (conséquence **[D]**)

### 2.2 Valeur de `alertNumber`
- DisplayAlert n'examine **que le bit 31** (`AT_DeadEnd`). Aucun autre bit (ni le code, ni le sous-système)
  ne change la couleur, le texte ou le comportement. **[O]**
- Effets du bit 31 : (a) les écrans ne sont pas décalés mais **retirés de la vue** (§2.4) ; (b) sans verrou
  d'intuition pendant la mise en place ; (c) si le raster ne peut pas être alloué, repli sur exec `Alert()`
  (§2.8). **[O]**

### 2.3 Raster, RastPort, ViewPort
- Largeur **W = le mot privé d'IntuitionBase qui sert aussi de largeur à l'écran Workbench** (640 en
  standard). **[O]** Mesuré : **640** (`$280`) en A500 PAL par défaut. **[S]**
- Raster : **1 plan**, `H = height` lignes, `((W+15)/8 arrondi à pair)` octets par ligne, alloué en
  `MEMF_CHIP` (sans `MEMF_CLEAR`) puis effacé par `SetRast(0)`. Taille = `height × 80` pour W = 640. **[O]**
- `InitBitMap(depth 1, W, height)`, `InitRastPort` (police = **police par défaut de graphics**, celle de
  Preferences : topaz 8 en standard, topaz 9 si l'utilisateur a choisi 60 colonnes), `SetRast(0)`. **[O]**
- ViewPort propre (pas d'écran intuition) : `DxOffset = DyOffset = 0`, `DWidth = W`, `DHeight = height`,
  **`Modes = HIRES | SPRITES` (`$C000`)**, non entrelacé, RasInfo à offset 0. `MakeVPort` sur la View
  d'intuition (ou, en dead-end, sur une View locale initialisée par `InitView`). **[O]**
- La ViewPort de l'alerte est **chaînée en queue** de la liste des ViewPorts de la View d'intuition ; les
  écrans ayant été décalés vers le bas (§2.4), elle occupe le haut de l'affichage. **[O]**

### 2.4 Écrans existants
- **Récupérable (bit 31 = 0)** : sous le verrou interne d'intuition, **chaque écran** de la liste est
  déplacé vers le bas de **`height + 1`** lignes (valeur doublée pour un écran entrelacé), avec un recalcul
  complet de l'affichage à chaque écran. À la fin, chaque écran remonte de la même quantité (remontée bornée
  à `TopEdge = 0`). L'utilisateur voit donc ses écrans glisser sous l'alerte, une ligne de séparation
  vide, puis revenir. **[O]** Observé : écran 320×200 ouvert en haut, pendant `DisplayAlert(0, …, 40)` la
  barre de titre de l'écran apparaît **41 lignes** sous le haut de l'alerte (39 lignes de cadre, 1 ligne de
  fond, 1 ligne noire de séparation entre ViewPorts) ; après le clic, l'écran est revenu en haut. **[S]**
  Artefact observé sous FS-UAE : quelques lignes de la couleur de fond de l'écran décalé (≈ 6) restent
  visibles **au-dessus** de l'alerte, avant que la copper list de l'alerte charge ses couleurs ; une
  réimplémentation n'a pas à le reproduire mais ne doit pas s'étonner de le voir. **[S]**
- **Dead-end (bit 31 = 1)** : le pointeur de la première ViewPort de la View d'intuition est **mis à NULL**,
  la ViewPort de l'alerte devient l'unique ViewPort ; les écrans disparaissent de l'affichage. **[O]**
  Après le clic, l'alerte est retirée et l'affichage recalculé, **mais la chaîne des ViewPorts des écrans
  n'est pas reconstruite** : l'écran ouvert avant reste **invisible** (tout l'affichage au fond `$111`),
  bien qu'il soit toujours ouvert. Observé : écran « SONDE » non réapparu après `DisplayAlert($80000000,
  …, 60)` + clic droit, ni 3 s plus tard. **[S]** Sans conséquence en usage normal, puisqu'une alerte
  dead-end est suivie d'un reset. **[D]** Pendant l'alerte, tout l'affichage sous l'alerte est au fond
  `$111` (aucune autre ViewPort). **[S]**
- Dans tous les cas, après installation : recalcul complet de l'affichage (`MrgCop`, `LoadView`, `WaitTOF`,
  DMA bitplanes et sprites rallumés). **[O]**

### 2.5 Palette, cadre, texte
- Couleurs posées par `SetRGB4` sur la ViewPort de l'alerte, **identiques pour toutes les alertes** :
  - **COLOR00 = `$111`** (presque noir) ;
  - **COLOR01 = `$F20`** (rouge orangé : R = 15, G = 2, B = 0) — texte et cadre.
  Mesuré sur capture : fond (17,17,17), texte/cadre (255,34,0). **[O][S]**
- **Cadre** (dessiné avant le texte, stylo 1, mode JAM1) **[O]** :
  - bandes verticales de **6 pixels** à gauche (`x = 0..5`) et à droite (`x = W−6..W−1`), lignes
    `0..height−2` ;
  - bandes horizontales de **3 lignes** en haut (`y = 0..2`) et en bas (`y = height−4..height−2`), entre
    `x = 6` et `x = W−7` (sans recouvrement avec les bandes verticales) ;
  - la **dernière ligne** du raster (`y = height−1`) reste au fond.
- **Texte** : stylo 1, mode JAM1, police par défaut, aux positions données par la chaîne. **[O]**
- **Clignotement** : le cadre est redessiné en mode **COMPLEMENT** à chaque échéance d'un compteur de
  **26 633** sondages des boutons ; il alterne donc présent/absent, le texte reste fixe. **[O]**
  Mesuré (sonde VBlank, tâche appelante, interruptions actives) : basculements toutes les **45 à 48
  trames** à 50 Hz (≈ 0,92 s par phase, ≈ 1,85 s par cycle), identique en récupérable et en dead-end. Le
  cadre est **présent dès l'affichage** (premier basculement = dessin initial). **[S]**
- Observé : police topaz 8 (glyphes des lignes `y−6 … y+1` pour une ligne de base `y`), x ≥ 256 accepté
  (`$0130` = 304 bien placé), pointeur souris absent pendant l'alerte. **[S]**

### 2.6 Attente des boutons
- Avant l'attente : **DMACON ← `$0020`** (DMA sprite coupé → pointeur souris invisible). **[O]**
- Phase 1 : attendre que **les deux boutons soient relâchés**. **[O]**
- Phase 2 : boucle de sondage **actif** (pas de Wait, pas d'interruption) : à chaque tour, lecture directe
  - bouton **gauche** : **CIA-A PRA bit 6** (`$BFE001`, /FIR0, port 0), enfoncé = 0 ;
  - bouton **droit** : **POTGOR (POTINP `$DFF016`) bit 10** (DATLY, port 0), enfoncé = 0.
  Aucune écriture dans POTGO : la lecture du bouton droit suppose que POTGO a déjà été configuré (ce que
  fait le système au boot). **[O]** (dépendance POTGO **[D]**)
  - gauche enfoncé → résultat **TRUE (1)** ; droit enfoncé → **FALSE (0)** ; si les deux sont vus au même
    tour, **gauche l'emporte**. **[O]**
- Phase 3 : attendre à nouveau que **les deux boutons soient relâchés**. **[O]**
- **Aucun délai d'expiration**, quelle que soit l'alerte (récupérable ou dead-end). **[O][S]**
- Seul le port souris 0 est lu ; ni clavier ni joystick ne valident l'alerte. **[O]**

### 2.7 Restauration
Sous le verrou interne : retrait de la ViewPort de l'alerte de la liste, `FreeVPortCopLists`, remontée des
écrans (§2.4), recalcul complet de l'affichage (rallume aussi le DMA sprite), puis `FreeMem` du raster.
Valeur rendue : **1 (gauche) ou 0 (droit)**, étendue en long. **[O]** Mesuré : 1 après clic gauche,
0 après clic droit ; DMACONR après retour = `$23F0` (sprites rallumés). **[S]**

### 2.8 Échec d'allocation du raster **[O]**
- Récupérable : DisplayAlert rend **FALSE immédiatement**, sans rien afficher. Mesuré : hauteur 7000
  (560 000 octets) → 0, retour en moins d'une trame, écran inchangé. **[S]**
- Dead-end : appel d'**exec `Alert(alertNumber)`** (A5 non initialisé → second nombre indéfini) → chemin dur
  d'exec (§1.1) → reset, puis Guru au boot suivant. Mesuré : pas d'affichage, reset après ≈ 5 s, puis au
  boot suivant `$100 = $80000000`, `$104 =` valeur indéfinie (0 dans la sonde), Guru
  « Software Failure.  Press left mouse button to continue. / Guru Meditation #80000000.00000000 ». **[S]**

---

## 3. Texte du Guru (routine commune exec / alert.hook)

Construit en pile au format §2.1 puis passé à `DisplayAlert(0, texte, 40)` **[O]** :

| Bloc | x | y | Texte (exact, espaces compris) | Continuation |
|---|---|---|---|---|
| 1 | 38 | 15 | en-tête, cf. ci-dessous | `$FF` |
| 2 | 234 | 15 | `Press left mouse button to continue.` | `$FF` |
| 3 | 142 | 30 | `Guru Meditation #%08lx.%08lx` formaté | `0` |

- **En-tête** (choisi sur `LastAlert[0]`) **[O]** :
  1. octet `bits 16-23 = $01` (sous-système général `AG_NoMemory`, quel que soit le bit 31) →
     `Not enough memory. `
  2. sinon bit 31 = 0 et mot haut ≠ 0 → `Recoverable Alert. `
  3. sinon (dead-end, ou mot haut nul = exception CPU) → `Software Failure. `
  (chaque en-tête se termine par **un point et une espace**).
- **Formatage** : `RawDoFmt` d'exec avec `%08lx` sur `LastAlert[0]` puis `LastAlert[1]` → 8 chiffres
  hexadécimaux **majuscules** complétés de zéros, séparés par un point, sans espace :
  `Guru Meditation #8100000F.CAFEBABE`. **[O][S]**
- Le **second nombre** est le long lu à l'adresse contenue dans A5 lors d'`Alert()` ; pour une exception CPU
  d'une tâche, **l'adresse de la tâche** (`ThisTask`) ; si ExecBase est jugé invalide lors d'une exception,
  un long de la trame d'exception. (cf. `coldstart-hardware-v34.md` §8.1) **[O][S]**
- **Hauteur 40** : cadre lignes 0-38, dernière ligne au fond. Écrans décalés de 41 lignes. **[O]**
- Les libellés « Software error - task held », « Disk corrupt - task held », « Finish ALL disk activity »,
  « Select CANCEL to reset/debug » existent bien dans la ROM 1.3, mais dans **dos.library** : c'est le
  requester « task held » de DOS (requester système, non le Guru), qui n'appartient pas à exec/alert.hook.
  Le Guru 1.3 ne contient que les trois blocs ci-dessus. **[O]**
- Repli d'AutoRequest (`intuition-requesters-v34.md` §5.3) : autre appelant de DisplayAlert, avec ses
  propres légendes `=LEFT BUTTON OK=` / `=RIGHT BUTTON CANCEL=`. **[O]**

---

## 4. alert.hook (résident pri 5, type UNKNOWN)

- Rappel (`coldstart-hardware-v34.md` §8.4) : temporisation fixe ≈ 1 s, rien si `LastAlert[0] = $FFFFFFFF`,
  sinon texte §3, DisplayAlert, puis remise à zéro de `$0` et `LastAlert[0]`. **[O][S]**
- **Pourquoi le Guru est rouge même pour « Recoverable Alert »** (point laissé ouvert) : DisplayAlert 1.3
  **n'a qu'une palette** (§2.5) ; la couleur ne dépend d'aucun bit de `alertNumber`. De plus alert.hook et
  l'affichage immédiat d'exec passent toujours `alertNumber = 0`. Le Guru jaune des alertes récupérables
  est une nouveauté des Kickstarts 2.x. **[O]** (comparaison 2.x **[D]**)
- Au boot, aucun écran n'est encore ouvert (le Workbench s'ouvre plus tard) : le décalage d'écrans est sans
  effet visible, l'alerte occupe les 40 premières lignes de l'affichage, le reste de l'affichage est au
  fond `$111` (aucune autre ViewPort chaînée). **[D]** Observé (MODE 2 de la sonde) : Guru en haut, tout le
  reste de l'écran gris très foncé, attente du clic, puis le boot reprend (le bootblock s'exécute). **[S]**
- Ordre utile pour une réimplémentation : intuition (pri 10) doit être initialisé, alert.hook (pri 5) passe
  **avant** mathffp, romboot et strap : le Guru d'une alerte précédente s'affiche donc **avant** l'écran
  « insérer une disquette ». **[O]** (ordre des résidents : `module-map.md`)

---

## 5. Vrai A500 vs émulateur

1. **PAL / NTSC** : l'alerte est positionnée en haut de la View d'intuition ; sa hauteur est en lignes non
   entrelacées, identique en PAL et NTSC. Aucune dépendance au standard vidéo dans DisplayAlert. **[O]**
2. **Clignotement** : purement **logiciel**, cadencé par la boucle de sondage (26 633 tours ≈ 230 cycles
   chacun : un appel de lecture CIA-A synchronisé sur l'horloge E, un appel de lecture POTGOR). Estimation à
   7,09 MHz (PAL) : **≈ 0,87 s par phase** (cadre présent puis absent), donc ≈ 1,75 s par cycle complet ;
   7,16 MHz (NTSC) : ≈ 0,86 s. Le temps d'interruption (VBlank, CIA) s'y ajoute si les interruptions sont
   actives. Plus lent sur machine chargée, plus rapide sur 68020+ (aucune référence temporelle).
   **[D]** — mesuré ≈ 0,92 s par phase sous FS-UAE A500 avec interruptions actives (§2.5) **[S]**.
3. **Bouton droit** : lu sur POTGOR sans programmation de POTGO. Sur A500 réel, la broche DATLY n'est fiable
   que si le système a programmé POTGO (input.device/potgo le fait au boot). Une alerte déclenchée par un
   programme qui a écrit POTGO autrement (jeux) peut voir le bouton droit toujours enfoncé ou jamais. **[D]**
4. **Bouton gauche** : CIA-A PRA bit 6, valable si DDRA bit 6 = 0 (entrée), état de reset et état normal
   du système. **[D]**
5. **Écran** : le fond `$111` et le rouge sont rendus tels quels ; la ligne vide sous l'alerte et la ligne
   de séparation des écrans décalés sont visibles. **[D]**
6. **Affichage immédiat d'`Alert()` récupérable sans slow RAM** : bloqué sous FS-UAE
   (`coldstart-hardware-v34.md` §10.7) ; voir « Points non tranchés ».

---

## 6. Sondes

- `tests/alert_probe.s` + `tests/alert_probe.sh <mode> <chip_ko> <slow_ko> <durée_max>` (variable
  `ALERT_OUT`) : bootblock auteur qui appelle DisplayAlert directement depuis une tâche (interruptions
  actives), journalise par un serveur VBlank chaque basculement du premier mot du raster (période de
  clignotement en trames) et rapporte sur la série la valeur rendue et DMACONR. Harnais réactif : captures
  pendant l'alerte, clic gauche ou droit.
  - MODE 0 : écran 320×200×1 ouvert, DisplayAlert(0, …, 40) + clic gauche, puis DisplayAlert($80000000, …,
    60) + clic droit.
  - MODE 1 : hauteur 7000 (raster impossible) en récupérable. MODE 2 : idem en dead-end.
- Résultats (A500 PAL, 512 Ko chip, sans slow RAM) : largeur 640 ; retours 1 (gauche) / 0 (droit) ;
  basculement du cadre toutes les 45-48 trames ; couleurs `$111`/`$F20` ; écrans décalés de 41 lignes et
  restaurés en récupérable, perdus en dead-end ; hauteur impossible → 0 (récupérable) ou reset + Guru
  `#80000000.00000000` (dead-end).

---

## Points non tranchés

- **Affichage immédiat d'un `Alert()` récupérable sur A500 sans slow RAM** : le code mène à l'affichage
  puis au retour, mais FS-UAE reste bloqué (`coldstart-hardware-v34.md` §10.7). DisplayAlert dépend de
  `WaitTOF` (VBlank) alors qu'Alert a coupé le maître INTENA sans changer `IDNestCnt` ; on n'a pas établi
  si le premier `Enable()` interne le rétablit à temps sur matériel réel (blocage réel possible) ou si le
  blocage est un artefact d'émulateur. À trancher sous WinUAE cycle-exact (`tests/coldhw_probe.sh` MODE 2
  adapté) ou sur machine réelle.
- **Verrou interne d'intuition en dead-end** : la mise en place ne le prend pas, mais la restauration le
  prend toujours ; si la tâche fautive le détenait, DisplayAlert dead-end appelée directement bloquerait
  après le clic. Non sondé (sans effet pour exec, qui ne passe jamais de dead-end à DisplayAlert).
- **Bouton droit sans POTGO programmé** (jeux qui reprogramment POTGO puis plantent) : comportement réel
  non mesuré.
- **Durée exacte du clignotement sur A500 réel** : ≈ 0,87 s par phase calculé hors interruptions, 0,92 s
  mesuré sous FS-UAE ; non chronométré sur machine réelle.
- **Bande de couleur de l'écran au-dessus de l'alerte** (§2.4) : vue sous FS-UAE, non vérifiée sur
  matériel ; dépend de la position où MrgCop insère la copper list de l'alerte.
- **Valeur rendue par `Alert()` quand intuition est absente** (A2 de l'appelant) : lue dans le code, non
  provoquée en sonde.

## Relecture clean-room

Relecture du 2026-10-29.

- [x] Aucune suite d'instructions 68000 transcrite ni paraphrasée, aucun extrait de désassemblage,
  aucune adresse de routine ROM (la seule adresse en `$C0xxxx` est une adresse de slow RAM, les autres
  sont des adresses RAM basse `$0`/`$100`/`$104`/`$180` ou de registres matériels).
- [x] Les chemins d'Alert/DisplayAlert sont décrits par leurs **effets** (valeurs écrites, registres
  rendus, ordre visible, géométrie à l'écran), recoupés par sonde [S] là où c'est marqué.
- [x] Données ROM reproduites, toutes **observables à l'écran ou en retour** (inventoriées dans
  `docs/audit/specs-review.md`) : textes du Guru (trois en-têtes, « Press left mouse button… »,
  format `Guru Meditation #%08lx.%08lx`), positions x/y des trois blocs, palette `$111`/`$F20`,
  géométrie du cadre, compteur de clignotement 26 633.
- [x] Les sondes citées (`tests/alert_probe.s`, `tests/coldhw_probe.sh`) sont du code auteur.
