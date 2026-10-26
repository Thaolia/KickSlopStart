# intuiticks-repeat-v34.md — répétition clavier (input.device 34.1) et INTUITICKS (intuition 34.3)

> Piste ANALYSE (« dirty »). Source : ROM `kick34005.A500` lue sous radare2 + sonde boîte noire sur la
> vraie ROM sous FS-UAE (`tests/ticks.s`, vecteurs §6). On décrit le **quoi** (valeurs, structures publiques,
> ordre, conditions, timings) ; aucune suite d'instructions transcrite, aucune adresse de routine.
>
> Légende : **[R]** analyse ROM · **[S]** sonde boîte noire · **[D]** doc publique · **[R+S]** concordants.
> Specs liées (non contredites, complétées) : `intuition-prefs-v34.md` (KeyRpt → SETTHRESH/SETPERIOD),
> `timer-v34.md` (UNIT_VBLANK), `intuition-prop-v34.md` §4 (pas de répétition du saut de page),
> `workbench-task-v34.md` §8.3 (défilement des tiroirs par INTUITICKS).

---

## 1. input.device : sources de temps et état interne

### 1.1 Ouvertures et requêtes **[R]**

À son init (résident COLDSTART pri 40), input.device ouvre **timer.device unité 1 = UNIT_VBLANK** et
keyboard.device unité 0, puis crée sa tâche (`"input.device"`, NT_TASK, **pri 20**, pile 4 Ko). La tâche
ouvre gameport.device (unité = `IND_SETMPORT`, 0 par défaut), lui envoie `GPD_SETCTYPE` (1 = GPCT_MOUSE par
défaut) et `GPD_SETTRIGGER` (défaut `keys = 3` (DOWNKEYS|UPKEYS), `timeout = 1`, `xdelta = 1`, `ydelta = 1`).

Trois timerequests indépendantes sur la même ouverture VBLANK, plus une pour `TR_GETSYSTIME` :

| Requête | Commande | Délai | Rôle |
|---|---|---|---|
| tic | TR_ADDREQUEST | **{0 s, 100 000 µs}** fixe | événements IECLASS_TIMER (§1.3) |
| répétition | TR_ADDREQUEST | THRESH puis PERIOD | répétition clavier (§2) |
| horloge | TR_GETSYSTIME (synchrone, DoIO) | — | horodatage de **chaque** événement produit |

### 1.2 Valeurs par défaut (avant tout SetPrefs) **[R]**

| Champ | Défaut input.device | Commande |
|---|---|---|
| seuil de répétition (délai initial) | **{0 s, 800 000 µs}** | `IND_SETTHRESH` (12) |
| période de répétition | **{0 s, 100 000 µs}** | `IND_SETPERIOD` (13) |
| port souris | 0 | `IND_SETMPORT` (14), 1 octet |
| type de contrôleur | 1 (souris) | `IND_SETMTYPE` (15), 1 octet |
| déclencheur | {3, 1, 1, 1} | `IND_SETMTRIG` (16), 8 octets (io_Length < 8 ⇒ IOERR_BADLENGTH −4 ; io_Actual = 8) |

- `IND_SETTHRESH`/`IND_SETPERIOD` : copient la `timeval` de la timerequest (`+$20` secondes, `+$24` µs)
  **immédiatement** (commande « rapide », répondue tout de suite). La nouvelle valeur sert à la **prochaine**
  armement du minuteur de répétition (une attente déjà lancée garde l'ancienne). **[R]**
- `IND_SETMPORT/SETMTYPE/SETMTRIG` (io_Length < 1 ⇒ −4) marquent la ré-ouverture de gameport, faite par la tâche
  au tour suivant. **[R]**
- intuition remplace ces défauts à son init et à chaque `SetPrefs` par **KeyRptDelay → SETTHRESH** et
  **KeyRptSpeed → SETPERIOD** (`intuition-prefs-v34.md` §3.3 et §4.3 : défauts ROM d'intuition 0,8 s / 0,1 s ; fichier
  `devs:system-configuration` du WB 1.3 : **0,4 s / 31 140 µs**). **[R, cf. spec prefs]**
- Commandes : 0 invalide, 1 CMD_RESET, 5 CMD_CLEAR, 6 CMD_STOP, 7 CMD_START, 8 CMD_FLUSH ; READ/WRITE/UPDATE
  (2/3/4) refusées ; 9 `IND_ADDHANDLER`, 10 `IND_REMHANDLER`, 11 `IND_WRITEEVENT` **mises en file** pour la
  tâche ; 12..16 immédiates. **[R]**

### 1.3 IECLASS_TIMER **[R ; fréquence S]**

- La requête « tic » est réarmée à {0, 100 000} **après** le traitement de chaque tic. En UNIT_VBLANK PAL
  (P = 20 000 µs, `timer-v34.md` §3) cela donne **5 trames = 100 ms**, soit **10 événements par seconde**
  (60 Hz : ⌈100 000/16 667⌉ = 6 trames ≈ 100 ms). Pas de rattrapage si la tâche prend du retard.
- Contenu de l'InputEvent (un **seul** événement, `ie_NextEvent = NULL`, structure réutilisée à chaque tic) :
  `ie_Class = 6` (IECLASS_TIMER), `ie_SubClass = 0`, `ie_Code = 0`, `ie_X = ie_Y = 0`,
  **`ie_TimeStamp` = heure système (TR_GETSYSTIME) au moment du tic**. `ie_Qualifier` n'est **pas** écrit par
  input.device (0 sauf si un handler l'a modifié — la structure est réutilisée). **[R]**
- Comme tous les événements, il est passé à la chaîne de handlers (§1.4).

### 1.4 Chaîne de handlers **[R ; D]**

`IND_ADDHANDLER` fait un Enqueue (par `ln_Pri`) de l'`Interrupt` dans la liste ; `IND_REMHANDLER` le retire.
Chaque événement produit (tic, clavier, souris, répétition, WRITEEVENT) est envoyé **seul** : handler appelé
avec **A0 = événement(s), A1 = is_Data**, entrée `is_Code` ; le D0 rendu est la liste passée au handler
suivant ; **D0 = 0 arrête la chaîne**. `IND_WRITEEVENT` envoie l'InputEvent pointé par io_Data **en forçant
`ie_NextEvent = NULL`** (un seul événement), **sans** le réhorodater ni retoucher son qualificatif.

### 1.5 Qualificatif courant **[R]**

input.device tient un **qualificatif courant** (UWORD) :
- événement **souris** (gameport) : `qual = (qual_événement & $F000) | (courant & $0FFF)` ; courant := qual ;
- événement **clavier** : `qual = (qual_événement & $07FF) | (courant & $F800)` ; courant := qual ;
- événement de **répétition** : même règle que clavier (bits $F800 = boutons/RELATIVEMOUSE rafraîchis) ;
  courant := qual, qui **contient `IEQUALIFIER_REPEAT` ($0200)** ⇒ les événements souris suivants portent
  aussi $0200 jusqu'au prochain événement clavier (artefact fidèle).
- événement **timer** : pas de mise à jour (et qualificatif non écrit, §1.3).

---

## 2. Répétition automatique des touches (input.device) **[R ; timings S]**

État : un seul « événement de répétition » (copie d'InputEvent) + son code ; code = $FFFF ⇒ pas de répétition.

### 2.1 Touche enfoncée (keyboard.device, bit 7 du code = 0)

1. Code **≥ $60** (Shift, Caps Lock, Ctrl, Alt, Amiga : $60..$67, et $68..$7F) : **arrête** la répétition en
   cours (AbortIO + WaitIO du minuteur, code := $FFFF). Ces touches **ne se répètent jamais**.
2. Code **< $60** (toute autre touche, y compris pavé numérique, flèches, fonctions, Esc, Del, Help…) :
   - historique des touches mortes : `ie_EventAddress` de l'événement (les 4 octets `ie_X/ie_Y`) reçoit
     **{Prev1DownCode, Prev1DownQual, Prev2DownCode, Prev2DownQual}** = les deux enfoncements précédents
     **de ce type** (code < $60), puis l'historique est décalé (cet enfoncement devient Prev1 ; seul l'octet
     bas du qualificatif est gardé) ;
   - si une répétition était en cours, son minuteur est annulé (la **dernière** touche enfoncée remplace
     l'ancienne : une seule touche répète à la fois) ;
   - l'événement (classe, sous-classe, code, qualificatif, adresse, horodatage) est copié dans l'événement de
     répétition, avec **`ie_Qualifier |= IEQUALIFIER_REPEAT ($0200)`** ;
   - le minuteur de répétition est armé avec le **seuil** (THRESH) ;
   - l'événement original (sans $0200) est envoyé aux handlers.

### 2.2 Touche relâchée (bit 7 = 1)

La répétition est **arrêtée** si :
- le code relâché (sans le bit 7) est celui de la touche qui répète, **ou**
- `(qual_répétition & $05FF) ≠ (courant & $07FF)` — le courant venant d'être mis à jour par ce relâchement.
  En pratique : relâcher une touche qualificative (Shift, Alt, Ctrl, Amiga, Caps Lock) **tenue au moment de
  l'enfoncement** arrête la répétition, et relâcher une touche dont le bit NUMERICPAD ($0100) diffère de celui
  de la touche qui répète l'arrête aussi.
Sinon (relâchement d'une autre touche ordinaire) la répétition continue. L'événement de relâchement est
ensuite envoyé normalement.

### 2.3 Échéance du minuteur

Si la répétition est toujours active : nouvel horodatage (GETSYSTIME) dans l'événement de répétition, mise à
jour de ses bits $F800 depuis le courant (§1.5), **envoi aux handlers** (IECLASS_RAWKEY, même code, mêmes
octets d'historique que l'enfoncement d'origine, `ie_Qualifier` avec **$0200**), puis réarmement avec la
**période** (PERIOD). Premier événement répété à **THRESH**, les suivants toutes les **PERIOD**, chaque délai
arrondi au VBLANK suivant (UNIT_VBLANK : k = max(1, ⌈T/20 000 µs⌉) trames en PAL). Exemples PAL : défauts
0,8 s / 0,1 s ⇒ 40 puis 5 trames ; WB 1.3 0,4 s / 31 140 µs ⇒ **20 puis 2 trames (25 répétitions/s)**.

### 2.4 Plusieurs touches

- Une seule touche répète : la dernière enfoncée (code < $60). Relâcher cette dernière arrête tout, même si
  une autre touche répétable est encore tenue (pas de reprise). **[R]**
- Enfoncer un qualificatif pendant une répétition l'arrête (2.1-1) ; le relâcher ne la relance pas. **[R+S]**
- Les touches mortes ne sont pas un cas particulier dans input.device (keymap les traite à la conversion) :
  une touche morte (< $60) se répète comme les autres. **[R]**

---

## 3. intuition 34.3 : INTUITICKS **[R ; S]**

### 3.1 Émission

Pour chaque événement **IECLASS_TIMER** que reçoit le handler d'intuition (donc ≈ 10 par seconde) :
1. intuition récupère d'abord les messages déjà rendus (ReplyMsg) de la **fenêtre active** ;
2. s'il existe une **fenêtre active** (`IntuitionBase->ActiveWindow`, +$34), qu'intuition n'est pas dans un
   état d'attente interne (vérification en cours, cf. §5), que `IDCMPFlags & INTUITICKS ($00400000)`, et que le
   drapeau **`WINDOWTICKED` ($04000000 dans `Window->Flags`, +$18)** est à 0 : un IntuiMessage INTUITICKS est
   envoyé et `WINDOWTICKED` est posé.
3. `WINDOWTICKED` est effacé quand intuition récupère **ce** message rendu (au traitement d'un événement
   suivant, cf. point 1, ou lors d'un autre parcours des messages rendus de la fenêtre).

Conséquences :
- **seule la fenêtre active** reçoit des INTUITICKS ; une fenêtre inactive n'en reçoit aucun ;
- **au plus un INTUITICKS en circulation par fenêtre** : tant que l'application n'a pas répondu, aucun autre
  n'est émis (pas d'accumulation) ; après réponse, le suivant part au tic d'après ⇒ cadence max 10/s ;
- les autres classes ne sont pas limitées.

### 3.2 Contenu du message

| Champ (IntuiMessage) | Valeur |
|---|---|
| `Class` (+$14) | `$00400000` |
| `Code` (+$18) | 0 |
| `Qualifier` (+$1A) | `ie_Qualifier` de l'événement timer (0 en pratique, §1.3) |
| `IAddress` (+$1C) | **la fenêtre elle-même** |
| `MouseX/MouseY` (+$20/+$22) | `Window->MouseX/MouseY` (relatifs à la fenêtre) ; avec DELTAMOVE : `ie_X/ie_Y` de l'événement (0) |
| `Seconds/Micros` (+$24/+$28) | `IntuitionBase->Seconds/Micros` (horodatage du dernier événement traité, ici le tic) |
| `IDCMPWindow` (+$2C) | la fenêtre |
| `mn_ReplyPort` | `Window->WindowPort` ; `mn_Length` = **$20** (valeur réelle d'intuition 34.3, quelle que soit la classe) |

(Le message est pris dans la réserve de messages de la fenêtre — 56 octets, MEMF_PUBLIC|MEMF_CLEAR, réutilisés
quand ils ont été rendus — comme tous les IntuiMessages.) **[R]**

---

## 4. Gadgets tenus enfoncés et défilement **[R ; S]**

- intuition 34.3 **ne répète rien** pour un gadget tenu : un gadget booléen GADGIMMEDIATE envoie **un seul**
  GADGETDOWN à l'appui, puis GADGETUP (RELVERIFY) au relâchement dedans ; aucun GADGETDOWN répété, aucune
  auto-répétition liée aux IECLASS_TIMER. Le saut de page d'un gadget proportionnel n'a lieu qu'une fois par
  clic (`intuition-prop-v34.md` §4.2). **[R+S]**
- La répétition est **à la charge de l'application**, typiquement sur INTUITICKS : c'est ce que fait le
  Workbench 1.3 (`workbench-task-v34.md` §8.3) : sur GADGETDOWN d'une **flèche** sans Shift, il **ajoute
  INTUITICKS à l'IDCMP** de la fenêtre du tiroir et fait défiler d'un pas (1/8 de la zone visible) à chaque
  INTUITICKS (et à chaque MOUSEMOVE) tant que le gadget est tenu ; au GADGETUP il retire INTUITICKS. Le
  défilement continu du WB va donc à **≈ 10 pas par seconde**, sans délai initial autre que le premier tic.
- Les INTUITICKS continuent d'arriver à la fenêtre active pendant qu'un gadget est tenu (le test du §3.1 ne
  dépend pas de l'état des gadgets). **[R+S]**

---

## 5. Points de détail

- L'état « attente interne » qui suspend le traitement (et donc les INTUITICKS) correspond aux moments où
  intuition attend une réponse de vérification (MENUVERIFY/SIZEVERIFY/REQVERIFY) ; non sondé. **[R]**
- `VANILLAKEY` (sans rapport direct, constaté au passage) : si la fenêtre a VANILLAKEY, un enfoncement converti
  en **exactement un** caractère part en VANILLAKEY ; sinon en RAWKEY (si demandé) ; **les relâchements sont
  avalés** (aucun message) quand VANILLAKEY est posé. Pour RAWKEY, `IAddress` pointe sur une copie (dans le
  message) des 4 octets d'historique des touches mortes (§2.1). **[R]**

---

## 6. Vecteurs de test (vraie ROM 34.5, FS-UAE 3.2.35, WB 1.3.3)

Sonde `tests/ticks.s` (fenêtre 640×160 BORDERLESS|ACTIVATE|RMBTRAP en (0,0) sur l'écran WB, couverte par
un gadget booléen GADGIMMEDIATE|RELVERIFY ; réponse à chaque message sous ≤ 20 ms ; `slow_memory = 512`).
Prefs actives = `devs:system-configuration` du WB 1.3.3 (KeyRptDelay 0,4 s, KeyRptSpeed 31 140 µs).
Injection : XTEST (`xdotool keydown/keyup`, `mousedown/up`) via le harnais FS-UAE.
Format : `classe code qual secs(16 bits bas) micros mouseX mouseY iaddr` — classe `T`=INTUITICKS,
`K`=RAWKEY, `D`/`U`=GADGETDOWN/UP, `A`=ACTIVEWINDOW ; iaddr `=` = la fenêtre.

```
W 00C07A00                                    fenêtre
A 0000 0000 AC4F 00000056 0000 0000 =        ACTIVEWINDOW, même horodatage que le 1er tic
T 0000 0000 AC4F 00000056 0000 0000 =        INTUITICKS : Code 0, Qual 0, IAddress = fenêtre
T 0000 0000 AC4F 0004E258 0000 0000 =
T 0000 0000 AC4F 000668F9 0000 0000 =        +100 001 µs
T 0000 0000 AC4F 0007EF9A 0000 0000 =        +100 001 µs …
--- touche « a » ($20) tenue ~2,5 s
K 0020 0000 AC52 000BE75E 0000 0000 00C07B5C enfoncement (pas de $0200)
K 0020 0200 AC53 0002BFA4 0000 0000 00C07B5C 1re répétition : +0,400 s, qualificatif $0200
K 0020 0200 AC53 00035BE6 0000 0000 00C07B24 +40 002 µs (2 trames : 31 140 µs arrondi au VBLANK)
K 0020 0200 AC53 0003F827 0000 0000 00C07B5C +40 001 µs … (≈ 25 répétitions/s)
K 00A0 0000 AC55 00044690 0000 0000 00C07B5C relâchement : fin
--- « a » tenue, puis Shift_L enfoncé pendant la répétition
K 0020 0000 AC56 000B99A1 …                   enfoncement ; répétitions $0200 dès AC57.271E7 (+0,4 s)
K 0020 0200 AC58 000B99E0 … 
K 0060 0001 AC58 000B99E1 0000 0000 00C07B24 Shift ($60, qual LSHIFT) : AUCUNE répétition ensuite
K 00E0 0000 AC5A 0003AAB3 …                   relâchement Shift : pas de reprise
K 00A0 0000 AC5B 000AFDC4 …                   relâchement « a »
--- Shift_L seul tenu 1,5 s
K 0060 0001 AC5D 00030E95 …                   un seul événement (les qualificatifs ne répètent pas)
K 00E0 0000 AC5F 00030EAC …
--- bouton gauche tenu ~2,5 s sur le gadget
D 0000 C000 AC60 000AAFDD 0000 0000 00C07E06 un seul GADGETDOWN (qual LEFTBUTTON|RELATIVEMOUSE)
   (20 INTUITICKS entre AC61 et AC62 : les tics continuent pendant l'appui)
U 0000 8000 AC63 0002C0BA 0000 0000 00C07E06 GADGETUP au relâchement
--- fin de l'enregistrement, puis 2 s SANS lire le port
#
T 0000 0000 AC70 0007F175 0000 0078 =        UN SEUL INTUITICKS en attente au bout de 2 s
```

Statistiques sur 335 INTUITICKS (≈ 33 s) : intervalle 100 ms dans 263 cas ; 80/120 ms (paires, 40 cas) ;
quelques 140–200 ms (tic sauté quand la réponse arrive après le tic suivant). `Qualifier` toujours 0, même
touche ou bouton tenus ; `MouseX/MouseY` = position du pointeur relative à la fenêtre (Y passant de 0 à
$78 après déplacement de la souris), donc la position courante, pas celle de l'événement timer.

---

## 7. Non sondé / incertain

- **Fenêtre inactive** : la sonde n'a pas réussi à désactiver sa fenêtre (le clic est retombé dans le
  gadget) ; « seule la fenêtre active reçoit des INTUITICKS » est établi par la ROM uniquement. **[R]**
- La gigue 80/120 ms des horodatages de tic (une paire à 80 puis 120 ms) n'est pas expliquée : elle vient de
  l'horodatage (GETSYSTIME) ou du moment de réarmement, la moyenne restant 100 ms.
- 60 Hz (NTSC) : non sondé (6 trames attendues pour un tic, ⌈T/16 667⌉ pour la répétition).
- Défauts d'input.device (0,8 s / 0,1 s) et défauts ROM d'intuition : non sondés ici (la sonde tourne avec le
  fichier de prefs du WB) ; valeurs lues en ROM.
- Règle d'arrêt par différence de qualificatif au relâchement d'une autre touche (masques $05FF/$07FF), cas du
  pavé numérique, propagation du bit REPEAT dans les événements souris : ROM uniquement.
- `WRITEEVENT`, chaîne de handlers et état d'attente de vérification suspendant les INTUITICKS : ROM
  uniquement.
- VANILLAKEY : ROM uniquement.

---

## Relecture clean-room

- [x] Aucune suite d'instructions transcrite ni paraphrasée ; aucune adresse de routine ROM (seuls des
  offsets de structures publiques/privées, des constantes d'ABI et des plages matérielles).
- [x] Les sondes citées sont du code auteur (`tests/`, en-tête « ASSET DE TEST, PAS du code ROM »).
