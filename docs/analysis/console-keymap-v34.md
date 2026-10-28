# console-keymap-v34.md — console.device (« console ri 34.1 ») et keymap.resource (« keymap ri 34.1 »)

> Piste ANALYSE (« dirty »). Sources : ROM `assets/kick34005.A500` lue sous radare2 (base `$FC0000`) et
> sonde boîte noire **sur la vraie ROM** sous FS-UAE (`tests/con_probe.s` + `tests/con_probe.sh`, code
> auteur, vecteurs en §8). On décrit le **quoi** : valeurs, séquences, layouts d'ABI, ordre des effets
> visibles. Aucune suite d'instructions transcrite ni paraphrasée, aucune adresse de routine ROM.
>
> **Légende** : **[O]** observé directement (lecture des données/du comportement dans la ROM, ou sortie
> de la sonde) — précisé **[O ROM]**, **[O sonde]** ou **[O ROM+sonde]** quand les deux concordent ;
> **[D]** déduit d'observations convergentes ; **[S]** supposé.
>
> Specs voisines (non dupliquées) : `handlers-v34.md` §2 (CON:/RAW: côté dos : c'est le handler, pas
> console.device, qui fait l'édition de ligne et l'écho) ; `intuiticks-repeat-v34.md` (répétition des
> touches et qualificatif IEQUALIFIER_REPEAT produits par input.device) ; `keyboard-handshake-v34.md`
> (codes bruts du clavier) ; `monkey-startup.md` §6 (RawKeyConvert(RETURN) = `$0D`).
>
> Conditions de la sonde : A500 PAL, 512 Ko chip + 512 Ko slow, aucune disquette système (Preferences
> par défaut de la ROM : police **topaz 9**, cellule **10 × 9** pixels), écran Workbench 640 × 200 à
> 2 plans (couleurs 0 bleu, 1 blanc, 2 noir, 3 orange).

---

## 0. Résumé exécutable

1. console.device est un résident COLDSTART pri 20 qui **exige keymap.resource** (il copie, à son
   init, la KeyMap du **premier** nœud de la liste de keymap.resource comme keymap par défaut ; liste
   vide ⇒ init en échec) et s'installe dans la chaîne d'input.device comme handler **pri 0**. [O ROM]
2. OpenDevice : unité **−1** ⇒ simple accès aux fonctions (io_Unit = −1) ; toute autre unité ⇒
   io_Data **doit** être une Window (sinon io_Error = −1) ; io_Unit reçoit le **ConUnit** (677 octets,
   partie publique = `devices/conunit.h` 1.3). Le numéro d'unité et io_Length sont ignorés. [O ROM+sonde]
3. Le dessin se fait **directement dans le RastPort de la fenêtre** (état du RastPort sauvé puis
   restauré à chaque opération, couche verrouillée par LockLayerRom) ; il n'y a **aucun tampon de
   caractères** : rien n'est redessiné après un REFRESHWINDOW. [O ROM]
4. CMD_WRITE interprète un sous-ensemble ANSI/ECMA-48 (tables complètes en §3–§4) ; après ESC c :
   **LNM, ASM et AWM actifs** (LF = CR+LF, défilement automatique, retour à la ligne automatique). [O ROM+sonde]
5. CMD_READ rend des **octets déjà cuits** (RawKeyConvert avec la keymap de l'unité, ou rapports
   `CSI … |` / `CSI … R` / `CSI … r`) dès qu'au moins un octet est disponible ; tampon circulaire de
   255 octets ; **pas d'écho, pas d'édition de ligne**. [O ROM+sonde]
6. RawKeyConvert (LVO −48) parcourt **toute la chaîne** d'événements, ne traite que IECLASS_RAWKEY, rend
   le nombre d'octets ou **−1** si le tampon est trop court ; touches mortes à un niveau (double morte
   prévue par le format mais inutilisée par « usa »). Modèle validé sur 1 680 combinaisons (§6). [O ROM+sonde]
7. keymap.resource V34 n'a **aucune fonction** : 74 octets (Node + List + un KeyMapNode « usa » dont la
   KeyMap pointe dans la ROM). [O ROM+sonde]

---

## 1. Initialisation et structures

### 1.1 keymap.resource [O ROM+sonde]

- Résident « keymap.resource », COLDSTART, **pri 100**, version 34 (idString « keymap ri 34.1 (18 Aug 1987) »).
- Init : AllocMem(**74**, **MEMF_CLEAR** seul — pas MEMF_PUBLIC), puis :
  - `+$00` Node : ln_Type = **8** (NT_RESOURCE), ln_Pri 0, ln_Name = `"keymap.resource"` ;
  - `+$0E` List `kr_List` (14 octets ; lh_Type laissé à 0) ;
  - `+$1C` **KeyMapNode** (46 octets) copié depuis la ROM : Node (succ/pred mis à jour pour être le
    seul élément de kr_List, ln_Type 0, ln_Pri 0, ln_Name = `"usa"`) suivi de la **KeyMap** (8 pointeurs
    vers les tables ROM, §5) ;
  - AddResource. Aucune table de vecteurs (0 LVO, pas de MakeFunctions).
- Sonde : OpenResource("keymap.resource") ⇒ ln_Type 8 ; lh_Head = ressource + `$1C` ; ln_Succ de ce
  nœud = adresse de lh_Tail ; nom « usa ».

Layout KeyMap (ABI publique `devices/keymap.h`, 32 octets) : `+0` km_LoKeyMapTypes, `+4` km_LoKeyMap,
`+8` km_LoCapsable, `+12` km_LoRepeatable, `+16` km_HiKeyMapTypes, `+20` km_HiKeyMap, `+24` km_HiCapsable,
`+28` km_HiRepeatable. « Lo » = codes `$00–$3F` (tables de 64 types, 64 longs, 8 + 8 octets de bits),
« Hi » = codes `$40–$77` (56 types, 56 longs, 7 + 7 octets de bits). Bit d'un code `c` dans un tableau
de bits : octet `(c & $3F) >> 3`, bit `c & 7`.

### 1.2 console.device : résident et base [O ROM]

- Résident « console.device », COLDSTART, **pri 20**, NT_DEVICE, version 34, idString
  « console ri 34.1 (18 Aug 1987) ». Base de 184 octets (lib_PosSize), 6 vecteurs standard + 2 :
  **−42 CDInputHandler**, **−48 RawKeyConvert**.
- Init, dans l'ordre : ouvre graphics.library (échec ⇒ init en échec) ; OpenResource("keymap.resource")
  (absente ou liste vide ⇒ ferme graphics, init en échec) ; **copie les 32 octets de la KeyMap du premier
  nœud** comme keymap par défaut du device ; initialise la liste des unités ; ouvre **input.device
  unité 0** et lui envoie **IND_ADDHANDLER** (9) avec une structure Interrupt : ln_Type NT_INTERRUPT,
  **ln_Pri 0**, ln_Name `"console.device"`, is_Data = base du device, is_Code = le vecteur −42 (donc
  CDInputHandler(A0 = événements, A1 = base)). Échec d'ouverture d'input.device : le device est quand
  même rendu (sans handler). intuition.library n'est ouverte qu'au **premier OpenDevice** sur fenêtre.
- Expunge : refusé (drapeau LIBF_DELEXP posé) tant que lib_OpenCnt ≠ 0 ; sinon IND_REMHANDLER (10),
  fermeture d'input.device, d'intuition et de graphics, libération de la base.

### 1.3 ConUnit (ABI publique `devices/conunit.h` 1.3) [O ROM+sonde]

Taille allouée : **677 octets** (`$2A5`), MEMF_PUBLIC, effacée. La partie publique occupe `$00–$127` ;
le reste est privé (tampons, état de l'analyseur). Champs publics et usage réel :

| Off. | Champ | Usage V34 |
|---|---|---|
| `$00` | cu_MP (MsgPort, 34 o) | ln_Name `"console.device"`, NT_MSGPORT ; sa liste reçoit les CMD_READ en attente |
| `$22` | cu_Window | io_Data de l'OpenDevice |
| `$26/$28` | cu_XCP / cu_YCP | position logique du curseur (colonne/ligne, base 0) |
| `$2A/$2C` | cu_XMax / cu_YMax | dernière colonne / dernière ligne (base 0) |
| `$2E/$30` | cu_XRSize / cu_YRSize | taille de cellule = TxWidth + TxSpacing / TxHeight du RastPort |
| `$32/$34` | cu_XROrigin / cu_YROrigin | origine de la zone de texte, pixels relatifs à la fenêtre |
| `$36/$38` | cu_XRExtant / cu_YRExtant | dernier pixel de la zone de texte (inclus) |
| `$3A/$3C` | cu_XMinShrink / cu_YMinShrink | plus petite taille (pixels utiles) vue depuis le dernier recalcul ; 9999 = « rien à effacer » |
| `$3E/$40` | cu_XCCP / cu_YCCP | cellule où le bloc curseur est **dessiné** (= XCP/YCP après chaque écriture) |
| `$42` | cu_KeyMapStruct (32 o) | keymap de l'unité (copie de la keymap par défaut à l'ouverture) |
| `$62` | cu_TabStops[80] (UWORD) | taquets triés croissants, terminés par `$FFFF` |
| `$102–$121` | cu_Mask … cu_TxSpacing | copie de l'état RastPort de la console (§2.2) |
| `$122` | cu_Modes[3] | bit n ⇒ octet n/8, bit n%8 ; **20 = LNM, 21 = ASM, 22 = AWM** |
| `$125` | cu_RawEvents[3] | bit n = classe IECLASS n rapportée en brut (n ≤ 18) |

Sonde, juste après OpenDevice sur une fenêtre 640 × 200 bordée (BorderLeft 4, Top 12, Right 18,
Bottom 2), topaz 9 : XCP = YCP = 0, **XMax = 60, YMax = 19**, XRSize 10, YRSize 9, XROrigin 4,
YROrigin 12, XRExtant 613, YRExtant 191, Modes = `00 00 70`, RawEvents = 0, FgPen 1, BgPen 0,
DrawMode 1 (JAM2), AlgoStyle 0, Mask `$FF`, taquets 0, 8, 16, … (§3.4).

---

## 2. OpenDevice, CloseDevice, BeginIO

### 2.1 OpenDevice [O ROM+sonde]

- lib_OpenCnt est incrémenté **en premier, dans tous les cas**, y compris en cas d'échec (il n'est
  jamais redécrémenté : fuite d'un compte par échec ; sonde : 2 → 3 après un échec). [O]
- **unit = −1** : io_Unit := −1, io_Error inchangé (0), succès. Sert à obtenir io_Device pour appeler
  RawKeyConvert / CDInputHandler. CloseDevice d'une telle requête ne fait que le décompte. [O]
- **autre unité (valeur indifférente)** : io_Data = 0 ⇒ **io_Error = −1** (IOERR_OPENFAIL) et
  io_Device := 0 ; mémoire insuffisante ⇒ idem. Sinon :
  1. alloue/initialise le ConUnit (MsgPort, cu_Window := io_Data, keymap := **copie de la keymap par
     défaut courante du device**) ; io_Unit := ConUnit ;
  2. insère l'unité **en tête** de la liste des unités du device ;
  3. exécute l'équivalent d'**ESC c** (§3.6) : police = police courante du RastPort de la fenêtre au
     moment de l'ouverture (mémorisée, restaurée par chaque ESC c), géométrie calculée, zone de texte
     effacée (fenêtre SMART_REFRESH), curseur affiché en (0,0) ;
  4. ouvre intuition.library si ce n'est déjà fait ;
  5. l'unité devient l'**unité active** (destinataire des touches) si aucune fenêtre active n'est
     encore connue du device **ou** si sa fenêtre est la fenêtre active connue (§6.1).
  io_Length (taille de la Window) est ignoré. [O ROM ; sonde : io_Error 0, io_Unit = ConUnit]
- Plusieurs unités peuvent partager une fenêtre ; chacune a son curseur et ses taquets, et dessine
  dans le même RastPort. [O sonde]

### 2.2 Accès au RastPort [O ROM ; sonde §8.4]

Chaque opération de dessin (et chaque CMD_WRITE en entier) : LockLayerRom(rp->Layer), sauvegarde de
`cp_x/cp_y`, Mask/FgPen/BgPen/AOlPen, DrawMode/AreaPtSz, AreaPtrn, Minterms, Font, AlgoStyle/TxFlags,
TxHeight/TxWidth, TxBaseline/TxSpacing du RastPort de la fenêtre, installation des valeurs du ConUnit
(`$102–$121`), dessin, recopie des valeurs du RastPort dans le ConUnit, restauration du RastPort,
UnlockLayerRom. Ces verrous sont imbriquables (compteur). Le programme qui partage la fenêtre retrouve
donc son RastPort intact.

### 2.3 CloseDevice [O ROM]

Unité −1 : rien. Sinon : retire l'unité de la liste ; si c'était l'unité active, **plus aucune unité
n'est active** (même si une autre unité est ouverte sur la même fenêtre — sonde §8.6) ; libère les 677
octets. Le bloc curseur **n'est pas effacé** de la fenêtre ; les CMD_READ en attente ne sont pas
répondus (à l'appelant de les annuler avant). io_Unit et io_Device := 0 ; lib_OpenCnt décrémenté ;
Expunge différé exécuté si demandé.

### 2.4 BeginIO, AbortIO, commandes standard [O ROM+sonde]

Code partagé avec keyboard/gameport/input : io_Flags &= `$0F`, io_Error := 0 ; commande ≥ **13** ⇒
traitée comme 0. Chaque commande est « immédiate » sauf **CMD_READ** (mise en file sur le MsgPort de
l'unité ; exécutée tout de suite si elle est en tête et l'unité non arrêtée, sinon IOF_QUICK effacé
et retour). Réponse : io_Error posé, retrait de la file, ReplyMsg seulement si IOF_QUICK est absent.

| N° | Commande | Comportement V34 |
|---:|---|---|
| 0 | CMD_INVALID | io_Error = −3 (IOERR_NOCMD) |
| 1 | CMD_RESET | = CMD_STOP + CMD_FLUSH + CMD_START, une seule réponse ; io_Error **non initialisé** (voir sous le tableau) |
| 2 | CMD_READ | §6.3 |
| 3 | CMD_WRITE | §3 |
| 4 | CMD_UPDATE | **comme CMD_INVALID** : io_Error = −3 |
| 5 | CMD_CLEAR | vide le tampon d'entrée de l'unité ; **ne répond jamais** : io_Error reste 0, IOF_QUICK reste posé ; envoyée sans IOF_QUICK (SendIO), la requête n'est **jamais** rendue (ln_Type reste NT_MESSAGE) [O sonde] |
| 6 | CMD_STOP | marque l'unité arrêtée : les CMD_READ restent en file (CMD_WRITE continue de fonctionner) |
| 7 | CMD_START | relance : exécute la CMD_READ en tête de file s'il y en a une |
| 8 | CMD_FLUSH | répond **−2** (IOERR_ABORTED) à toutes les CMD_READ en file |
| 9 | CD_ASKKEYMAP | §5.4 |
| 10 | CD_SETKEYMAP | §5.4 |
| 11 | CD_ASKDEFAULTKEYMAP | §5.4 |
| 12 | CD_SETDEFAULTKEYMAP | §5.4 |

**io_Error de CMD_STOP, CMD_START, CMD_FLUSH, CMD_RESET** : ces commandes répondent sans fixer de code :
io_Error reçoit l'**octet bas du D0 de l'appelant** au moment de BeginIO (sonde, BeginIO appelé avec
D0 = n° de commande : io_Error = 1, 6, 7, 8 ; pour FLUSH après au moins un abandon : −2). Une
réimplémentation doit rendre 0. [O ROM+sonde]

AbortIO : répond **−2** à la requête si elle n'a pas déjà été rendue (pas de vérification qu'elle est
en file) ; renvoie 0.

---

## 3. CMD_WRITE : affichage

### 3.1 Contrat [O ROM+sonde]

- io_Data = octets, io_Length = nombre d'octets, ou **−1** ⇒ chaîne terminée par NUL (io_Length est
  alors remplacé par la longueur). io_Length = 0 ⇒ rien n'est écrit (mais un redimensionnement en
  attente est appliqué, §3.9). io_Actual = octets consommés (sonde : « xyz », −1 ⇒ 3). io_Error = 0.
- L'état de l'analyseur (séquence ESC/CSI incomplète) **persiste d'une écriture à l'autre**.
- Pendant toute l'écriture, la couche est verrouillée et le RastPort sauvé (§2.2).
- À la fin, si le tampon d'entrée n'est pas vide (rapports produits par `6n` ou `SP q`) et qu'une
  CMD_READ attend, elle est servie immédiatement.
- Pas de traitement de NUL en mode longueur explicite : `$00` est un caractère de contrôle ignoré.

### 3.2 Automate (tous octets 8 bits) [O ROM+sonde]

États : **normal**, **ESC** (après `$1B`), **ESC-intermédiaire**, **CSI-paramètres**, **CSI-intermédiaire**.

| État | Octet | Effet |
|---|---|---|
| normal | `$00–$1F` | contrôle C0 (§3.3) |
| normal | `$20–$7F` | caractère imprimable (`$7F` aussi : glyphe de la police) |
| normal | `$80–$9F` | contrôle C1 (§3.3) |
| normal | `$A0–$FF` | caractère imprimable |
| ESC | `$00–$1F`, `$80–$FF` | abandon d'ESC, l'octet est retraité en état normal (ESC ESC = nouvel ESC) |
| ESC | `$20–$2F` | intermédiaire mémorisé ⇒ ESC-intermédiaire |
| ESC | `$30–$3F` | **ignoré, on reste en état ESC** (ESC 7 B : le B est consommé comme `ESC B`) |
| ESC | `$40–$5F` | équivaut au C1 `octet + $40` (ESC [ = CSI, ESC D = IND, ESC E = NEL, ESC H = HTS, ESC M = RI ; les autres sont ignorés) |
| ESC | `$60–$7F` | seul **`c`** (RIS, §3.6) est reconnu ; les autres sont consommés sans effet |
| ESC-interm. | `$20–$2F` | intermédiaire de plus (7 au plus mémorisés) |
| ESC-interm. | `$30–$7E` | fin de séquence **ignorée** (ESC ( 0, ESC # 8… sans effet) |
| CSI-param. | `0–9` | chiffre du paramètre courant (base 10) |
| CSI-param. | `;` | paramètre suivant |
| CSI-param. | `:` | ignoré |
| CSI-param. | `<` `=` `>` `?` | le paramètre courant prend la valeur −1, −2, −3, −4 (les chiffres suivants s'ajoutent « en négatif » : `>1` = −31, `?7` = −47) |
| CSI-param. | `$20–$2F` | intermédiaire ⇒ CSI-intermédiaire |
| CSI-param. | `$40–$7E` | octet final ⇒ exécution (§3.5) |
| CSI-param. | contrôle C0/C1 (dont CSI, ESC) | **abandon** de la séquence et retraitement de l'octet (CSI 2 LF ⇒ LF ; CSI 1 CSI 2C ⇒ CSI 2C) |
| CSI-interm. | `$20–$2F` | intermédiaire de plus |
| CSI-interm. | `$30–$3F` | abandon et retraitement (CSI ! 2 C D ⇒ affiche « 2CD ») |
| CSI-interm. | `$40–$6F` | séquence **ignorée** |
| CSI-interm. | `$70–$7E` | exécutée seulement si l'unique intermédiaire est l'espace (`SP p`, `SP q`, §3.5) ; sinon ignorée |

Paramètres : au plus **24** (les suivants sont perdus) ; un paramètre absent vaut « défaut » (valeur
interne −5) ; valeurs sur 16 bits signés (débordement non contrôlé). Pour les commandes de mouvement,
**défaut, 0 et négatif valent 1**. [O ROM ; sonde : CSI 0A = CSI A, CSI 65535C borné]

### 3.3 Contrôles C0 et C1 [O ROM+sonde]

| Octet | Nom | Effet |
|---|---|---|
| `$07` | BEL | DisplayBeep(écran de la fenêtre) |
| `$08` | BS | curseur à gauche de 1 (non destructif) ; en colonne 0 avec AWM : dernière colonne de la ligne précédente (en ligne 0 : ligne 0, colonne XMax, et défilement d'une ligne vers le bas si ASM — comme CUU ; ce dernier cas non sondé) ; sans AWM : rien |
| `$09` | HT | taquet suivant (§3.4) |
| `$0A` | LF | si LNM : comme NEL (`$85`) ; sinon comme IND (`$84`) |
| `$0B` | VT | **ligne précédente** (= RI `$8D`), colonne inchangée |
| `$0C` | FF | curseur en (0,0) et **effacement de toute la zone de texte** (couleur §3.7) |
| `$0D` | CR | colonne 0 |
| `$0E` | SO | jeu « décalé » : les caractères `$20–$7F` sont affichés comme `octet | $80` |
| `$0F` | SI | retour au jeu normal |
| `$1B` | ESC | début de séquence |
| autres `$00–$1F` | — | ignorés (y compris NUL, `$1C`, `$1F`) |
| `$84` | IND | ligne suivante, colonne inchangée ; en bas : défilement si ASM. **Absorbé** si le curseur vient d'être renvoyé à la ligne automatiquement (§3.8) |
| `$85` | NEL | ligne suivante + colonne 0 ; absorbé (en entier) après un retour automatique |
| `$88` | HTS | pose un taquet à la colonne courante |
| `$8D` | RI | ligne précédente ; en haut : défilement inverse si ASM |
| `$9B` | CSI | début de séquence de contrôle |
| autres `$80–$9F` | — | ignorés |

### 3.4 Taquets [O ROM+sonde]

- Défaut (ESC c, ouverture) : colonnes **0, 8, 16, …, 632** (80 taquets ; le 81e mot vaut `$FFFF`).
- HT : va au premier taquet **strictement supérieur** à XCP. S'il dépasse XMax (ou s'il n'y en a plus) :
  avec AWM, colonne 0 de la ligne suivante (défilement si nécessaire) et **retour automatique mémorisé**
  (un LF/NEL immédiatement suivant est absorbé) ; sans AWM, colonne XMax.
- HTS (`$88`, ESC H, `CSI W`/`CSI 0W`) : insère XCP dans la liste triée (pas de doublon ; si la liste
  est pleine, le dernier taquet est perdu).
- `CSI 2W` et `CSI g`/`CSI 0g` : retire le taquet de la colonne courante — **sauf en colonne 0** (le
  taquet 0 est indélébile).
- `CSI 5W`, `CSI 4W`, `CSI 3g` : efface tout ; il ne reste que le taquet 0 (liste = `0, $FFFF`).
- `CSI W` et `CSI g` traitent chaque paramètre de la liste (`CSI 0;2W` …) ; les valeurs non listées
  sont ignorées.
- `CSI n I` (CHT) : n fois HT. `CSI n Z` (CBT) : n fois « taquet précédent » : premier taquet
  strictement inférieur à XCP ; en colonne 0 avec AWM : remonte d'une ligne (défilement inverse si ASM)
  et cherche depuis la fin de cette ligne ; en colonne 0 sans AWM : rien.

### 3.5 Séquences CSI reconnues [O ROM+sonde]

Notation : `Pn` = paramètre (défaut/0/négatif ⇒ 1 pour les mouvements). Tout final absent du tableau
est **ignoré** (dont `G`, `d`, `X`, `p` sans espace, `s`, `r`, `|`, `~`…). [O sonde : G, d, X, CSI 0p, CSI p]

| Séquence | Nom | Effet exact V34 |
|---|---|---|
| `CSI Pn @` | ICH | insère Pn cellules vides à XCP (décalage à droite de la ligne courante jusqu'à XRExtant, ce qui sort est perdu) ; curseur fixe |
| `CSI Pn A` | CUU | YCP −= Pn ; si < 0 : YCP = 0 et, **si ASM, défilement vers le bas** du déficit (CUU au-delà du haut fait apparaître des lignes vides) |
| `CSI Pn B` | CUD | YCP += Pn ; si > YMax : YMax et, si ASM, défilement vers le haut de l'excédent |
| `CSI Pn C` | CUF | XCP += Pn ; si > XMax : avec AWM, retour à la colonne 0 de la ligne suivante (défilement si besoin) et poursuite du reste, retour automatique mémorisé ; sans AWM : XMax |
| `CSI Pn D` | CUB | XCP −= Pn ; si < 0 : avec AWM, dernière colonne de la ligne précédente et poursuite ; sans AWM : 0 |
| `CSI Pn E` | CNL | Pn lignes vers le bas (comme CUD) puis colonne 0 ; **entièrement absorbé** juste après un retour automatique |
| `CSI Pn F` | CPL | Pn lignes vers le haut (comme CUU) puis colonne 0 ; absorbé juste après un retour automatique |
| `CSI Pl;Pc H`, `CSI Pl;Pc f` | CUP | ligne Pl, colonne Pc (base 1) ; défaut/0 ⇒ 1 ; **bornés** à YMax/XMax (pas de défilement) |
| `CSI Pn I` | CHT | Pn tabulations |
| `CSI J` | ED | efface du curseur à la fin de la ligne puis toutes les lignes suivantes de la zone ; **paramètre ignoré** (`1J`, `2J` = `J`) |
| `CSI K` | EL | efface du curseur à la fin de la ligne ; **paramètre ignoré** (`1K`, `2K` = `K`) |
| `CSI Pn L` | IL | insère Pn lignes vides à la ligne courante (le bas de la zone est perdu) ; curseur fixe |
| `CSI Pn M` | DL | supprime Pn lignes à partir de la ligne courante, le bas se remplit de lignes vides |
| `CSI Pn P` | DCH | supprime Pn caractères à XCP, la fin de ligne se décale à gauche, cellules vides à droite |
| `CSI Pn S` | SU | défile toute la zone de Pn lignes vers le haut ; curseur fixe |
| `CSI Pn T` | SD | défile toute la zone de Pn lignes vers le bas ; curseur fixe |
| `CSI Ps;… W` | CTC | 0/défaut : HTS ; 2 : efface le taquet courant ; 4 ou 5 : efface tous (§3.4) |
| `CSI Pn Z` | CBT | Pn tabulations arrière |
| `CSI Ps;… g` | TBC | 0/défaut : efface le taquet courant ; 3 : efface tous |
| `CSI Ps;… h` / `l` | SM / RM | pose / efface le bit Ps de cu_Modes pour 0 ≤ Ps ≤ 20 ; `>1` (−31) ⇒ bit 21 **ASM** ; `?7` (−47) ⇒ bit 22 **AWM** ; autres valeurs ignorées. Seuls 20/21/22 ont un effet |
| `CSI Ps;… m` | SGR | §3.7 |
| `CSI 6n` | DSR | met `CSI <YCP+1>;<XCP+1>R` dans le tampon d'entrée (premier paramètre seul examiné : `6;6n` répond, `5n` et `n` non) |
| `CSI Pn t` | — | Pn > 0 : longueur de page fixée, **YMax = Pn−1** ; défaut/≤ 0 : retour au calcul automatique |
| `CSI Pn u` | — | Pn > 0 : longueur de ligne fixée, **XMax = Pn−1** ; défaut/≤ 0 : automatique |
| `CSI Pn x` | — | Pn ≥ 0 : **XROrigin = Pn pixels** (depuis le bord gauche de la fenêtre, bordure comprise) ; défaut : automatique |
| `CSI Pn y` | — | Pn ≥ 0 : **YROrigin = Pn pixels** ; défaut : automatique |
| `CSI Ps;… {` | — | pose le bit de rapport brut de chaque classe Ps (0 ≤ Ps ≤ 18 ; autres ignorées) |
| `CSI Ps;… }` | — | efface ces bits |
| `CSI 0 SP p` | — | **curseur invisible** (le bloc est effacé) |
| `CSI SP p`, `CSI Pn SP p` (Pn ≠ 0) | — | curseur visible |
| `CSI SP q`, `CSI Pn SP q` | — | met `CSI 1;1;<YMax+1>;<XMax+1> r` dans le tampon d'entrée (rapport de bornes de fenêtre ; paramètre ignoré) |

Après `t`, `u`, `x`, `y`, la géométrie est recalculée immédiatement (§3.9).

### 3.6 RIS — `ESC c` [O ROM+sonde]

Dans l'ordre visible : curseur masqué ; taquets par défaut ; jeu normal (SI) ; analyseur remis à zéro ;
XCP = YCP = 0 ; cu_XCCP/YCCP = 0 ; longueur de page/ligne et origines redeviennent automatiques ;
curseur **visible** ; cu_Modes = 0 puis **LNM, ASM, AWM posés** (`00 00 70`) ; police, style
algorithmique, TxHeight/TxWidth/TxBaseline/TxSpacing **restaurés** depuis ceux mémorisés à
l'OpenDevice ; XRSize = TxWidth + TxSpacing, YRSize = TxHeight ; SGR 0 ; recalcul de la géométrie
avec « plus petite taille vue » = 0, ce qui **efface toute la zone** (y compris la marge partielle à
droite/en bas) **si la fenêtre est SMART_REFRESH** ; rien n'est effacé pour SIMPLE_REFRESH ou
SUPER_BITMAP (§8.7) ; curseur dessiné en (0,0). cu_RawEvents n'est **pas** remis à zéro.

### 3.7 SGR (`CSI Ps;… m`) [O ROM+sonde]

Chaque paramètre est traité dans l'ordre ; défaut/négatif ⇒ 0 ; valeurs > 49 ignorées.

| Ps | Effet sur le RastPort de la console |
|---:|---|
| 0 | Mask = `$FF`, DrawMode = JAM2, SetSoftStyle(0, masque 7) (gras/italique/souligné retirés), APen = 1, BPen = 0 |
| 1 | gras algorithmique (FSF_BOLD) |
| 2 | **APen = 2** (« faible » = couleur 2, pas un style) |
| 3 | italique algorithmique (FSF_ITALIC) |
| 4 | souligné (FSF_UNDERLINED) |
| 7 | DrawMode = JAM2 \| INVERSVID (5) |
| 8 | **Mask = 0** (« caché » : plus rien n'est dessiné, ni texte ni effacements ; voir piège ci-dessous) |
| 30–37 | APen = Ps − 30 |
| 39 | APen = 1 |
| 40–47 | BPen = Ps − 40 |
| 49 | BPen = 0 |
| 5, 6, 9–29 (dont 22, 23, 24, 27), 38, 48 | **sans effet** (aucune annulation individuelle en V34) |

- Plume ≥ nombre de couleurs : masquée par la profondeur (sonde : 34 ⇒ couleur 0, 37 ⇒ couleur 3).
- **Couleur d'effacement** (FF, ED, EL, ESC c, marge de redimensionnement) : **BPen si DrawMode vaut
  exactement JAM2**, sinon couleur 0 (en inverse, EL efface en 0). ICH/DCH/IL/DL/SU/SD et le défilement
  automatique passent par ScrollRaster, qui remplit avec **BPen** quel que soit le mode. [O sonde]
- Piège SGR 8 : le bloc curseur est dessiné/effacé en complément **avec le Mask courant** ; avec Mask 0
  l'effacement du curseur n'a pas lieu et le bloc reste à l'écran à l'ancienne position. [O sonde]

### 3.8 Écriture des caractères, retour automatique, défilement [O ROM+sonde]

- Les octets imprimables consécutifs sont affichés par **Text()** en une fois, par tranche limitée à
  la fin de ligne (XMax − XCP + 1), à la position pixel (XROrigin + XCP × XRSize, YROrigin + YCP × YRSize
  + TxBaseline). En mode SO, un caractère à la fois (octet | `$80`).
- Après chaque tranche, curseur avancé comme `CSI Pn C` : **si AWM**, le caractère écrit en dernière
  colonne renvoie **immédiatement** le curseur en colonne 0 de la ligne suivante (défilement si on
  était en bas et ASM) et **mémorise** ce « retour automatique » ; sinon le curseur reste sur XMax et
  les caractères suivants **réécrivent la dernière colonne**.
- Le marqueur de retour automatique est effacé dès que le curseur change de cellule. Tant qu'il est
  posé, **LF, IND, NEL, CNL et CPL sont absorbés** (une ligne de exactement XMax+1 caractères suivie de
  LF ne laisse pas de ligne vide). CR ne déplace rien (déjà en colonne 0) et ne l'efface pas, donc
  « ligne pleine + CR LF » n'avance aussi que d'une ligne. [O ROM ; sonde §8.3]
- En bas (YCP = YMax), un passage à la ligne **avec ASM** défile toute la zone d'une ligne vers le haut
  (ScrollRaster sur XROrigin..XRExtant × YROrigin..YRExtant, remplissage BPen) ; **sans ASM** le
  curseur reste sur la dernière ligne qui est réécrite.
- Le défilement est limité à la page définie par `t`/`u` (sonde : page 20 × 5, le défilement ne touche
  que ces 20 colonnes × 5 lignes).

### 3.9 Géométrie et redimensionnement [O ROM+sonde]

Recalcul (à l'ouverture, ESC c, `t u x y`, et au début de la première écriture après un
IECLASS_SIZEWINDOW) :

- Fenêtre **non GIMMEZEROZERO** : XROrigin = BorderLeft (sauf `x`), YROrigin = BorderTop (sauf `y`) ;
  largeur utile = Width − XROrigin − BorderRight ; hauteur utile = Height − YROrigin − BorderBottom.
- Fenêtre **GIMMEZEROZERO** : XROrigin = 0 et YROrigin = 0 (sauf `x`/`y`) ; largeur utile = Width −
  BorderLeft − BorderRight − XROrigin ; hauteur utile = Height − BorderTop − BorderBottom − **XROrigin**
  (V34 retranche l'origine **horizontale** de la hauteur : bogue visible seulement après `CSI Pn x`). [O ROM ; sonde §8.7]
- XMax = largeur utile / XRSize − 1 (sauf `u`) ; YMax = hauteur utile / YRSize − 1 (sauf `t`) ;
  XRExtant = (XMax+1) × XRSize − 1 + XROrigin ; YRExtant = (YMax+1) × YRSize − 1 + YROrigin.
- Fenêtre SMART_REFRESH uniquement : si la fenêtre a grandi, effacement (couleur §3.7) de la bande à
  droite des colonnes entières qui existaient à la plus petite taille vue, et de la bande sous les lignes
  entières correspondantes (élimine les demi-caractères révélés).
- Curseur : s'il était dans la partie conservée il est effacé normalement, sinon il est considéré comme
  disparu. Puis (sauf SUPER_BITMAP) : XCP > XMax ⇒ colonne 0 de la ligne suivante ; YCP > YMax ⇒
  YCP = YMax, colonne 0 et **défilement d'une seule ligne** (pas de recentrage) ; curseur redessiné.
- La console apprend le redimensionnement par l'événement **IECLASS_SIZEWINDOW** que lui transmet la
  chaîne d'input.device : il est appliqué à l'**unité active**, quelle que soit la fenêtre redimensionnée
  (pour une console non active, le recalcul n'a pas lieu avant le prochain `ESC c`/`t u x y`). Le
  recalcul effectif est différé au **début de la prochaine CMD_WRITE** (même de longueur 0). [O ROM ; D pour l'effet sur une fenêtre inactive ; sonde §8.5]
- Aucune autre réaction au rafraîchissement : IECLASS_REFRESHWINDOW n'est utilisé que pour le rapport
  brut ; une fenêtre SIMPLE_REFRESH masquée puis révélée perd son texte. [O ROM]

### 3.10 Curseur [O ROM+sonde]

Bloc plein d'une cellule (XRSize × YRSize) dessiné par **RectFill en mode COMPLEMENT** (couleur 0 ⇒ 3
sur 2 plans : le curseur 1.3 orange), à (cu_XCCP, cu_YCCP). Masqué pendant toute opération de dessin,
réaffiché à la position XCP/YCP à la fin. Visible par défaut ; `CSI 0 SP p` le cache. Il n'y a pas de
curseur « fantôme » quand la fenêtre est inactive (même dessin quel que soit l'état d'activation). [O ROM]

---

## 4. Rapports insérés dans le flux d'entrée [O ROM+sonde]

Formats (décimal ASCII, `CSI` = octet `$9B`) :

| Origine | Format |
|---|---|
| `CSI 6n` | `CSI` *ligne* `;` *colonne* `R` (base 1 ; sonde après « xyz » en ligne 1 colonne 9 : `9B 31 3B 39 52`) |
| `CSI SP q` | `CSI 1;1;` *lignes* `;` *colonnes* ` r` (espace avant `r` ; sonde : `CSI 1;1;20;61 r`) |
| événement brut | `CSI` *classe* `;` *sous-classe* `;` *code* `;` *qualificatif* `;` *x* `;` *y* `;` *secondes* `;` *microsecondes* `|` |

Rapport brut : un par événement de la classe activée par `CSI n{`, pour l'unité active (ou toutes les
unités si le qualificatif porte IEQUALIFIER_MULTIBROADCAST `$0800`) ; x et y = ie_X/ie_Y **non signés**
(pour RAWKEY : codes/qualificatifs des touches précédentes) ; secondes et microsecondes avec le bit 31
forcé à 0. Un événement rapporté en brut n'est **pas** cuit en plus. Les octets passent par le même
tampon de 255 octets que les touches ; s'il est plein, la fin du rapport est **tronquée** (octet par
octet), alors qu'une traduction de touche qui ne tient pas est **écartée entière**.

---

## 5. Keymaps

### 5.1 Types (octet de km_*KeyMapTypes) [O ROM ; ABI publique]

`KCF_SHIFT 1`, `KCF_ALT 2`, `KCF_CONTROL 4`, `KCF_DOWNUP 8`, `KCF_DEAD $20`, `KCF_STRING $40`,
`KCF_NOP $80`, `KC_VANILLA 7`. Index de combinaison : on parcourt les bits 0 à 3 du type (SHIFT, ALT,
CONTROL, DOWNUP) ; chaque bit présent dans le type vaut 1, 2, 4… dans l'ordre de rencontre, et compte
s'il est aussi présent dans l'état courant. Nombre de combinaisons = 2^(bits présents).

### 5.2 Traduction d'un code (RawKeyConvert) [O ROM ; modèle validé par sonde §6]

Pour un événement RAWKEY (code `c`, qualificatif `q`) :

1. code = `c & $7F` ; > `$77` ⇒ 0 octet. Tables Lo si < `$40`, sinon Hi.
2. `q & $0200` (IEQUALIFIER_REPEAT) et touche non « Repeatable » ⇒ 0 octet.
3. type `KCF_NOP` ⇒ 0 octet.
4. Relâchement (`c & $80`) : 0 octet si le type n'a pas KCF_DOWNUP ; sinon le bit DOWNUP compte.
5. État : Maj si `q & 3` (LSHIFT|RSHIFT) ; Alt si `q & $30` (LALT|RALT) ; **Caps Lock (`q & 4`) sur une
   touche Capsable ⇒ Maj** (Caps + Maj = Maj, pas d'inversion) ; Ctrl si `q & 8`. Les touches Amiga
   (`$40/$80`) et le pavé (`$100`) sont sans effet.
6. Selon le type :
   - **STRING** : le long est un pointeur vers des paires (longueur, décalage) — une par combinaison —
     le décalage étant relatif au début du descripteur ; longueur > place restante ⇒ **−1**.
   - **DEAD** : le long pointe vers des paires (drapeau, valeur), une par combinaison :
     drapeau 0 ⇒ valeur = l'octet rendu ; drapeau `DPF_DEAD` (8) ⇒ touche morte : **0 octet** (même avec
     un tampon de longueur 0), sa valeur = indice de la morte ; drapeau `DPF_MOD` (1) ⇒ touche
     modifiable : valeur = décalage d'une table de traduction ; l'octet rendu est `table[k]`, où k =
     indice de morte de la **touche précédente** (ie_Prev1DownCode/Qual = octets de ie_X) si elle était
     morte, sinon 0. Si l'indice de la précédente a un quartet haut non nul (double morte), k =
     (haut × bas) + indice bas de la touche d'avant (ie_Prev2DownCode/Qual = octets de ie_Y) ; la keymap
     « usa » n'utilise que des indices 1 à 5, donc une seule morte compte.
   - **VANILLA (7)** sans Ctrl : octet n° (index) du long en partant de l'octet de **poids faible** (0 =
     sans qualificatif, 1 = Maj, 2 = Alt, 3 = Maj+Alt).
   - **VANILLA avec Ctrl** : on part de l'octet sélectionné par Maj/Alt et on cherche, en tournant vers
     les octets de poids plus fort (4 au plus, en rebouclant), le premier octet de la forme `%01xxxxxx`
     (`$40–$7F`) ; résultat = cet octet **& `$1F`**. Aucun ⇒ l'octet sélectionné tel quel. (Ctrl-2 ⇒
     `$00` via « @ », Ctrl-6 ⇒ `$1E`, Ctrl-Alt-q ⇒ `$11`.)
   - **Autre type sans STRING/DEAD** : ≤ 4 combinaisons ⇒ octet n° index du long (poids faible = 0) ;
     plus de 4 (type avec DOWNUP et 2 qualificatifs ou plus, hors VANILLA) ⇒ le long est un pointeur vers
     un tableau d'octets indexé.
7. Place restante 0 pour un résultat d'un octet ⇒ **−1**.

### 5.3 Fonction RawKeyConvert (console LVO −48) [O ROM+sonde]

`actual = RawKeyConvert(events A0, buffer A1, length D1, keyMap A2)`, A6 = base du console.device
(obtenue par OpenDevice unité −1).

- keyMap = NULL ⇒ **keymap par défaut courante du device** (celle que CD_SETDEFAULTKEYMAP remplace).
- Parcourt **toute la chaîne** ie_NextEvent ; seuls les événements de classe 1 (RAWKEY) produisent des
  octets, concaténés ; length décroît d'un événement à l'autre.
- Rend le total (mot, partie haute nulle), ou **−1 (long) dès qu'un résultat ne tient pas** (le début
  déjà écrit reste dans le tampon). Sonde : chaîne « a », « Maj b » ⇒ 2 octets `61 42` ; même chaîne en
  longueur 1 ⇒ −1 ; premier événement RAWMOUSE ⇒ seul `42` (1).
- Ne lit ni ne modifie aucun état global : les touches mortes reposent uniquement sur ie_X/ie_Y de
  l'événement.

### 5.4 Commandes de keymap [O ROM+sonde]

- io_Length doit valoir **exactement 32** ; sinon io_Error = **−4** (IOERR_BADLENGTH), rien n'est copié,
  io_Actual inchangé. Succès : io_Actual = 32.
- **CD_ASKKEYMAP** (9) : copie la KeyMap de l'unité (`cu_KeyMapStruct`) vers io_Data.
- **CD_SETKEYMAP** (10) : copie io_Data vers la KeyMap de l'unité (effet immédiat sur les touches de
  cette unité).
- **CD_ASKDEFAULTKEYMAP** (11) : copie la keymap par défaut du device vers io_Data.
- **CD_SETDEFAULTKEYMAP** (12) : copie io_Data vers la keymap par défaut du device. Effets : (a)
  RawKeyConvert(…, NULL) l'utilise aussitôt ; (b) les unités **ouvertes ensuite** la reçoivent ; (c) les
  unités **déjà ouvertes ne changent pas** ; (d) keymap.resource **n'est pas modifiée**.
- Seuls les 8 pointeurs sont copiés (sous Forbid) : les tables doivent rester en mémoire tant qu'elles
  servent (cas de `SetMap`, qui les charge en RAM).
- Sonde : SETDEFAULT d'une copie où le long de `$21` (s) vaut `$5A7A5A7A` ⇒ RawKeyConvert(s, NULL) = `z` ;
  ASKKEYMAP de l'unité existante = pointeurs ROM ; nouvelle unité ⇒ pointeur modifié ; restauration ⇒ `s`.

### 5.5 Keymap « usa » de la ROM : tables brutes [O ROM+sonde]

- Capsable Lo (8 octets) : `00 00 FF 03 FF 01 FE 00` ⇒ `$10–$19`, `$20–$28`, `$31–$37` ; Hi : tout à 0.
- Repeatable Lo : `FF BF FF EF FF EF FF F7` ⇒ tous sauf `$0E`, `$1C`, `$2C`, `$3B` ;
  Hi : `47 F4 FF 03 00 00 00` ⇒ `$40 $41 $42 $46 $4A $4C–$4F $50–$59` (**Return, Enter, Esc, Help et
  les modificateurs ne se répètent pas**).

### 5.6 Keymap « usa » : résultat par touche et par qualificatif [O ROM+sonde]

Valeurs **rendues par RawKeyConvert** (enfoncement, tampon suffisant), identiques à la sonde sur les
14 qualificatifs testés × 120 codes. « — » = rien ; « morte n » = touche morte d'indice n (rien n'est
rendu) ; « † » = touche modifiable (la valeur affichée est celle sans morte précédente, voir §5.7) ;
`SP` = espace `$20` ; `$xx` = octet non imprimable ou ambigu ; `CSI` = `$9B`. Caps Lock = Maj pour les
touches marquées « Caps ». Codes `$68–$77` : type hors table, toujours rien.

| Code | Touche | Type | Caps | Rép. | — | Maj | Alt | Maj+Alt | Ctrl | Ctrl+Maj | Ctrl+Alt | Ctrl+Maj+Alt |
|---|---|---|:-:|:-:|---|---|---|---|---|---|---|---|
| $00 | `` ` `` (gauche de 1) | $07 |  | x | `` ` `` | ~ | `` ` `` | ~ | $00 | $1E | $00 | $1E |
| $01 | 1 | $03 |  | x | 1 | ! | ¹ | ! | 1 | ! | ¹ | ! |
| $02 | 2 | $07 |  | x | 2 | @ | ² | @ | $00 | $00 | $00 | $00 |
| $03 | 3 | $03 |  | x | 3 | # | ³ | # | 3 | # | ³ | # |
| $04 | 4 | $03 |  | x | 4 | $ | ¢ | $ | 4 | $ | ¢ | $ |
| $05 | 5 | $03 |  | x | 5 | % | ¼ | % | 5 | % | ¼ | % |
| $06 | 6 | $07 |  | x | 6 | ^ | ½ | ^ | $1E | $1E | $1E | $1E |
| $07 | 7 | $03 |  | x | 7 | & | ¾ | & | 7 | & | ¾ | & |
| $08 | 8 | $03 |  | x | 8 | * | · | * | 8 | * | · | * |
| $09 | 9 | $03 |  | x | 9 | ( | « | ( | 9 | ( | « | ( |
| $0A | 0 | $03 |  | x | 0 | ) | » | ) | 0 | ) | » | ) |
| $0B | - | $07 |  | x | - | _ | - | _ | $1F | $1F | $1F | $1F |
| $0C | = | $01 |  | x | = | + | = | + | = | + | = | + |
| $0D | \\ | $07 |  | x | \\ | \\| | \\ | \\| | $1C | $1C | $1C | $1C |
| $0E | (inutilisé) | $80 |  |  | — | — | — | — | — | — | — | — |
| $0F | pavé 0 | $00 |  | x | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| $10 | q | $07 | x | x | q | Q | å | Å | $11 | $11 | $11 | $11 |
| $11 | w | $07 | x | x | w | W | ° | ° | $17 | $17 | $17 | $17 |
| $12 | e | $27 | x | x | e† | E† | © | © | $05 | $05 | $85 | $85 |
| $13 | r | $07 | x | x | r | R | ® | ® | $12 | $12 | $12 | $12 |
| $14 | t | $07 | x | x | t | T | þ | Þ | $14 | $14 | $14 | $14 |
| $15 | y | $27 | x | x | y† | Y† | ¤ | ¥ | $19 | $19 | $99 | $99 |
| $16 | u | $27 | x | x | u† | U† | µ | µ | $15 | $15 | $95 | $95 |
| $17 | i | $27 | x | x | i† | I† | ¡ | ¦ | $09 | $09 | $89 | $89 |
| $18 | o | $27 | x | x | o† | O† | ø | Ø | $0F | $0F | $8F | $8F |
| $19 | p | $07 | x | x | p | P | ¶ | ¶ | $10 | $10 | $10 | $10 |
| $1A | [ | $07 |  | x | [ | { | [ | { | $1B | $1B | $1B | $1B |
| $1B | ] | $07 |  | x | ] | } | ] | } | $1D | $1D | $1D | $1D |
| $1C | (inutilisé) | $80 |  |  | — | — | — | — | — | — | — | — |
| $1D | pavé 1 | $00 |  | x | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 |
| $1E | pavé 2 | $00 |  | x | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 |
| $1F | pavé 3 | $00 |  | x | 3 | 3 | 3 | 3 | 3 | 3 | 3 | 3 |
| $20 | a | $27 | x | x | a† | A† | æ | Æ | $01 | $01 | $81 | $81 |
| $21 | s | $07 | x | x | s | S | ß | § | $13 | $13 | $13 | $13 |
| $22 | d | $07 | x | x | d | D | ð | Ð | $04 | $04 | $04 | $04 |
| $23 | f | $27 | x | x | f | F | morte 1 | morte 1 | $06 | $06 | $86 | $86 |
| $24 | g | $27 | x | x | g | G | morte 2 | morte 2 | $07 | $07 | $87 | $87 |
| $25 | h | $27 | x | x | h | H | morte 3 | morte 3 | $08 | $08 | $88 | $88 |
| $26 | j | $27 | x | x | j | J | morte 4 | morte 4 | $0A | $0A | $8A | $8A |
| $27 | k | $27 | x | x | k | K | morte 5 | morte 5 | $0B | $0B | $8B | $8B |
| $28 | l | $07 | x | x | l | L | £ | £ | $0C | $0C | $0C | $0C |
| $29 | ; | $01 |  | x | ; | : | ; | : | ; | : | ; | : |
| $2A | ' | $01 |  | x | ' | " | ' | " | ' | " | ' | " |
| $2B | intl. (près de Return) | $80 |  | x | — | — | — | — | — | — | — | — |
| $2C | (inutilisé) | $80 |  |  | — | — | — | — | — | — | — | — |
| $2D | pavé 4 | $00 |  | x | 4 | 4 | 4 | 4 | 4 | 4 | 4 | 4 |
| $2E | pavé 5 | $00 |  | x | 5 | 5 | 5 | 5 | 5 | 5 | 5 | 5 |
| $2F | pavé 6 | $00 |  | x | 6 | 6 | 6 | 6 | 6 | 6 | 6 | 6 |
| $30 | intl. (gauche de Z) | $03 |  | x | < | > | « | » | < | > | « | » |
| $31 | z | $07 | x | x | z | Z | ± | ¬ | $1A | $1A | $1A | $1A |
| $32 | x | $07 | x | x | x | X | × | ÷ | $18 | $18 | $18 | $18 |
| $33 | c | $07 | x | x | c | C | ç | Ç | $03 | $03 | $03 | $03 |
| $34 | v | $07 | x | x | v | V | ª | ª | $16 | $16 | $16 | $16 |
| $35 | b | $07 | x | x | b | B | º | º | $02 | $02 | $02 | $02 |
| $36 | n | $27 | x | x | n† | N† | $AD | ¯ | $0E | $0E | $8E | $8E |
| $37 | m | $07 | x | x | m | M | ¸ | ¿ | $0D | $0D | $0D | $0D |
| $38 | , | $01 |  | x | , | < | , | < | , | < | , | < |
| $39 | . | $01 |  | x | . | > | . | > | . | > | . | > |
| $3A | / | $01 |  | x | / | ? | / | ? | / | ? | / | ? |
| $3B | (inutilisé) | $80 |  |  | — | — | — | — | — | — | — | — |
| $3C | pavé . | $00 |  | x | . | . | . | . | . | . | . | . |
| $3D | pavé 7 | $00 |  | x | 7 | 7 | 7 | 7 | 7 | 7 | 7 | 7 |
| $3E | pavé 8 | $00 |  | x | 8 | 8 | 8 | 8 | 8 | 8 | 8 | 8 |
| $3F | pavé 9 | $00 |  | x | 9 | 9 | 9 | 9 | 9 | 9 | 9 | 9 |
| $40 | Espace | $22 |  | x | SP† | SP† | $A0 | $A0 | SP† | SP† | $A0 | $A0 |
| $41 | Backspace | $00 |  | x | $08 | $08 | $08 | $08 | $08 | $08 | $08 | $08 |
| $42 | Tab | $41 |  | x | $09 | CSI Z | $09 | CSI Z | $09 | CSI Z | $09 | CSI Z |
| $43 | Enter (pavé) | $00 |  |  | $0D | $0D | $0D | $0D | $0D | $0D | $0D | $0D |
| $44 | Return | $04 |  |  | $0D | $0D | $0D | $0D | $0A | $0A | $0A | $0A |
| $45 | Esc | $02 |  |  | $1B | $1B | CSI | CSI | $1B | $1B | CSI | CSI |
| $46 | Del | $00 |  | x | $7F | $7F | $7F | $7F | $7F | $7F | $7F | $7F |
| $47 | (inutilisé) | $80 |  |  | — | — | — | — | — | — | — | — |
| $48 | (inutilisé) | $80 |  |  | — | — | — | — | — | — | — | — |
| $49 | (inutilisé) | $80 |  |  | — | — | — | — | — | — | — | — |
| $4A | pavé - | $00 |  | x | - | - | - | - | - | - | - | - |
| $4B | (inutilisé) | $80 |  |  | — | — | — | — | — | — | — | — |
| $4C | ↑ | $41 |  | x | CSI A | CSI T | CSI A | CSI T | CSI A | CSI T | CSI A | CSI T |
| $4D | ↓ | $41 |  | x | CSI B | CSI S | CSI B | CSI S | CSI B | CSI S | CSI B | CSI S |
| $4E | → | $41 |  | x | CSI C | CSI SP @ | CSI C | CSI SP @ | CSI C | CSI SP @ | CSI C | CSI SP @ |
| $4F | ← | $41 |  | x | CSI D | CSI SP A | CSI D | CSI SP A | CSI D | CSI SP A | CSI D | CSI SP A |
| $50 | F1 | $41 |  | x | CSI 0 ~ | CSI 1 0 ~ | CSI 0 ~ | CSI 1 0 ~ | CSI 0 ~ | CSI 1 0 ~ | CSI 0 ~ | CSI 1 0 ~ |
| $51 | F2 | $41 |  | x | CSI 1 ~ | CSI 1 1 ~ | CSI 1 ~ | CSI 1 1 ~ | CSI 1 ~ | CSI 1 1 ~ | CSI 1 ~ | CSI 1 1 ~ |
| $52 | F3 | $41 |  | x | CSI 2 ~ | CSI 1 2 ~ | CSI 2 ~ | CSI 1 2 ~ | CSI 2 ~ | CSI 1 2 ~ | CSI 2 ~ | CSI 1 2 ~ |
| $53 | F4 | $41 |  | x | CSI 3 ~ | CSI 1 3 ~ | CSI 3 ~ | CSI 1 3 ~ | CSI 3 ~ | CSI 1 3 ~ | CSI 3 ~ | CSI 1 3 ~ |
| $54 | F5 | $41 |  | x | CSI 4 ~ | CSI 1 4 ~ | CSI 4 ~ | CSI 1 4 ~ | CSI 4 ~ | CSI 1 4 ~ | CSI 4 ~ | CSI 1 4 ~ |
| $55 | F6 | $41 |  | x | CSI 5 ~ | CSI 1 5 ~ | CSI 5 ~ | CSI 1 5 ~ | CSI 5 ~ | CSI 1 5 ~ | CSI 5 ~ | CSI 1 5 ~ |
| $56 | F7 | $41 |  | x | CSI 6 ~ | CSI 1 6 ~ | CSI 6 ~ | CSI 1 6 ~ | CSI 6 ~ | CSI 1 6 ~ | CSI 6 ~ | CSI 1 6 ~ |
| $57 | F8 | $41 |  | x | CSI 7 ~ | CSI 1 7 ~ | CSI 7 ~ | CSI 1 7 ~ | CSI 7 ~ | CSI 1 7 ~ | CSI 7 ~ | CSI 1 7 ~ |
| $58 | F9 | $41 |  | x | CSI 8 ~ | CSI 1 8 ~ | CSI 8 ~ | CSI 1 8 ~ | CSI 8 ~ | CSI 1 8 ~ | CSI 8 ~ | CSI 1 8 ~ |
| $59 | F10 | $41 |  | x | CSI 9 ~ | CSI 1 9 ~ | CSI 9 ~ | CSI 1 9 ~ | CSI 9 ~ | CSI 1 9 ~ | CSI 9 ~ | CSI 1 9 ~ |
| $5A | pavé ( (A500/A2000) | $80 |  |  | — | — | — | — | — | — | — | — |
| $5B | pavé ) | $80 |  |  | — | — | — | — | — | — | — | — |
| $5C | pavé / | $80 |  |  | — | — | — | — | — | — | — | — |
| $5D | pavé * | $80 |  |  | — | — | — | — | — | — | — | — |
| $5E | pavé + | $80 |  |  | — | — | — | — | — | — | — | — |
| $5F | Help | $40 |  |  | CSI ? ~ | CSI ? ~ | CSI ? ~ | CSI ? ~ | CSI ? ~ | CSI ? ~ | CSI ? ~ | CSI ? ~ |
| $60 | Maj gauche | $80 |  |  | — | — | — | — | — | — | — | — |
| $61 | Maj droite | $80 |  |  | — | — | — | — | — | — | — | — |
| $62 | Caps Lock | $80 |  |  | — | — | — | — | — | — | — | — |
| $63 | Ctrl | $80 |  |  | — | — | — | — | — | — | — | — |
| $64 | Alt gauche | $80 |  |  | — | — | — | — | — | — | — | — |
| $65 | Alt droite | $80 |  |  | — | — | — | — | — | — | — | — |
| $66 | Amiga gauche | $80 |  |  | — | — | — | — | — | — | — | — |
| $67 | Amiga droite | $80 |  |  | — | — | — | — | — | — | — | — |

### 5.7 Touches mortes (keymap « usa ») [O ROM+sonde]

Mortes (Alt ou Alt+Maj sur f, g, h, j, k) : indice **1 = Alt-f accent aigu**, **2 = Alt-g grave**,
**3 = Alt-h circonflexe**, **4 = Alt-j tilde**, **5 = Alt-k tréma**. Ctrl-Alt-f etc. ne sont pas mortes
(`$86`…). Touches modifiables et leur table (indice 0 = sans morte, puis 1 à 5) :

| Touche | Sans Maj : 0, 1, 2, 3, 4, 5 | Avec Maj (ou Caps) : 0, 1, 2, 3, 4, 5 |
|---|---|---|
| Espace (`$40`, aussi avec Maj ; Ctrl sans effet) | SP ´ ` ^ ~ ¨ | idem |
| a (`$20`) | a á à â ã ä | A Á À Â Ã Ä |
| e (`$12`) | e é è ê e ë | E É È Ê E Ë |
| i (`$17`) | i í ì î i ï | I Í Ì Î I Ï |
| o (`$18`) | o ó ò ô õ ö | O Ó Ò Ô Õ Ö |
| u (`$16`) | u ú ù û u ü | U Ú Ù Û U Ü |
| y (`$15`) | y ý y y y ÿ | Y Ý Y Y Y Y |
| n (`$36`) | n n n n ñ n | N N N N Ñ N |

Codes rendus pour l'espace : `$B4`, `$60`, `$5E`, `$7E`, `$A8`. Seules les combinaisons sans Alt et sans
Ctrl sont modifiables (Alt-e = « © » ignore la morte). Une morte suivie d'une touche non modifiable :
la morte est perdue, la touche donne sa valeur normale (sonde : Alt-f puis q ⇒ `q`). La morte doit être
**la touche enfoncée immédiatement avant** (ie_Prev1DownCode) avec son qualificatif Alt (Prev1DownQual) :
« f » sans Alt avant « e » ⇒ `e`.

---

## 6. CDInputHandler (LVO −42) et flux d'entrée

### 6.1 Contrat [O ROM]

`events = CDInputHandler(events A0, consoleDevice A1)` — appelé par input.device (pri 0, après
intuition pri 50). Pour chaque événement de la chaîne :

1. **IECLASS_EVENT (3) / IECODE_NEWACTIVE (1)** : la fenêtre ie_EventAddress devient la « fenêtre active
   connue » ; l'unité active devient la **première unité de la liste** (= la plus récemment ouverte)
   dont cu_Window est cette fenêtre, ou aucune.
2. Qualificatif avec **IEQUALIFIER_MULTIBROADCAST (`$0800`)** : l'événement est traité pour **toutes**
   les unités ; sinon pour l'unité active seulement (rien s'il n'y en a pas).
3. **IECLASS_SIZEWINDOW (12)** (hors multibroadcast) : mémorise la taille minimale vue et marque un
   recalcul de géométrie pour l'unité active (§3.9).
4. Traitement pour une unité : si classe ≤ 18 et bit cu_RawEvents correspondant ⇒ rapport brut (§4) ;
   sinon RawKeyConvert de **cet événement seul** (ie_NextEvent masqué temporairement) avec la keymap de
   l'unité dans un tampon de 127 octets ; si au moins 1 octet et que **tout** tient dans la place libre
   du tampon d'entrée, ajout ; sinon abandon silencieux.
5. Après la chaîne : si quelque chose a été ajouté, les CMD_READ en attente de l'unité active (ou de
   toutes les unités après un multibroadcast) sont servies.

Le handler **rend NULL** : il consomme toute la chaîne (dernier handler standard). [O ROM]

### 6.2 Ce qui arrive vraiment de l'intuition 1.3 [O sonde]

- Ce que la console reçoit est la liste **rendue par intuition** (`intuition-input-menus-v34.md` §1–§2) :
  les RAWKEY destinés à la fenêtre active, IECLASS_EVENT/NEWACTIVE (émis par ActivateWindow **même si la
  fenêtre est déjà active**), IECLASS_SIZEWINDOW (émis aussi par SizeWindow()), les événements NULL ;
  **pas** les boutons de souris RAWMOUSE ni POINTERPOS ni TIMER (avalés par intuition). Sonde : `CSI 2{`
  + boutons injectés ⇒ aucun rapport ; `CSI 0{ 4{ 6{` ⇒ seul un rapport de classe 0. [O sonde]
- Les touches injectées par IND_WRITEEVENT gardent ie_X/ie_Y tels quels : une morte injectée n'agit
  que si l'injecteur remplit lui-même Prev1DownCode/Qual (sonde : Alt-f puis e injectés ⇒ `e` ; e avec
  ie_X = `$2310` ⇒ `é`). Pour les vraies frappes, c'est input.device qui remplit ces champs
  (`intuiticks-repeat-v34.md` §2.1). [O sonde]
- Cuisson observée en CMD_READ (unité active, keymap « usa ») : a ⇒ `61` ; Maj a ⇒ `41` ; ↑ ⇒ `9B 41` ;
  Maj ↑ ⇒ `9B 54` ; F1 ⇒ `9B 30 7E` ; Maj F1 ⇒ `9B 31 30 7E` ; Help ⇒ `9B 3F 7E` ; Maj Tab ⇒ `9B 5A` ;
  Alt Esc ⇒ `9B` ; Ctrl Return ⇒ `0A` ; Backspace ⇒ `08` ; Del ⇒ `7F` ; les relâchements ne produisent
  rien. [O sonde]
- Rapport brut (`CSI 1{`, RAWKEY `$20`, qualificatif `$8000`, ie_X/ie_Y = `$1234`/`$5678`, horodatage
  0) : `CSI 1;0;32;32768;4660;22136;0;0|`. [O sonde]
- **Piège de l'unité active** : ouvrir puis fermer une seconde unité sur la fenêtre active laisse le
  device **sans unité active** (la fermeture ne cherche pas d'autre unité) ; les frappes sont perdues
  jusqu'au prochain NEWACTIVE (ActivateWindow, clic). Sonde : unité active = 0 après la fermeture, `a`
  injecté ⇒ rien ; après ActivateWindow ⇒ `a`. [O ROM+sonde]

### 6.3 CMD_READ [O ROM+sonde]

- io_Length > 0 : sous Forbid, copie au plus io_Length octets du tampon d'entrée vers io_Data,
  io_Actual = nombre copié, réponse immédiate **dès qu'au moins un octet** est disponible ; tampon vide ⇒
  la requête reste en file (IOF_QUICK effacé) jusqu'à l'arrivée d'octets (touche, rapport) ; les
  requêtes en file sont servies dans l'ordre.
- Tampon d'entrée : anneau de **255 octets** utiles par unité, vidé par CMD_CLEAR (sonde : 60 rapports de
  5 octets = 300 octets écrits ⇒ 255 octets relus (51 rapports), le reste perdu).
- **io_Length = 0** : bogue V34 — la réponse « −4 » est faite puis le code lit la file de l'unité via un
  registre **non initialisé** (valeur laissée par l'appelant) ⇒ comportement indéfini (sonde : Guru
  `#00000003` avec A2 = 1 à l'appel de BeginIO). Une réimplémentation doit répondre −4 (IOERR_BADLENGTH) proprement. [O ROM+sonde]
- io_Length = −1 : traité comme « 1 octet au plus ». [O ROM]
- Pas d'écho, pas d'édition, pas de conversion CR → LF : c'est le travail du console-handler (CON:).

---

## 7. Ce qui diffère sur un vrai A500

- **Aucune dépendance matérielle directe** : console.device ne touche ni CIA ni registres custom ; tout
  passe par graphics (Text, RectFill, ScrollRaster → blitter), layers, intuition et input.device. Le
  comportement est donc identique sur un vrai A500 ; seule la vitesse change (ScrollRaster et Text au
  blitter réel). [O ROM]
- **Codes bruts réels** : un clavier A500 US produit `$00–$0D`, `$0F–$1B` (`$1D–$1F` pavé), `$20–$2A`,
  `$2D–$2F`, `$31–$3A`, `$3C–$46`, `$4A`, `$4C–$5F`, `$60–$67` ; les claviers non US ajoutent `$2B`
  (à côté de Return) et `$30` (à gauche de Z). La keymap ROM donne `$2B` ⇒ **rien** (NOP) et `$30` ⇒
  `<`/`>`. **Les touches `( ) / * +` du pavé de l'A500 (`$5A–$5E`) sont NOP dans la keymap ROM** : elles
  ne produisent rien tant qu'un `SetMap` (keymap disque, p. ex. usa1) n'a pas été chargé. [O ROM+sonde ;
  liste des codes physiques : D, doc publique]
- **Claviers non US** (l'utilisateur est en AZERTY) : la ROM ne connaît que « usa » ; `SetMap f` de la
  startup-sequence charge une keymap en RAM et la passe à **CD_SETDEFAULTKEYMAP** (et, pour la console du
  CLI courant, CD_SETKEYMAP) — seules les unités ouvertes **après** héritent du défaut (§5.4). [O ROM pour
  le device ; D pour le mécanisme de SetMap, non sondé ici]
- **Répétition réelle** : les répétitions viennent d'input.device avec IEQUALIFIER_REPEAT ; sur la keymap
  ROM, **Return, Enter, Esc et Help ne se répètent pas** (table Repeatable), contrairement aux
  lettres, flèches et F1–F10. [O ROM+sonde]
- **Police et taille** : la cellule suit la police du RastPort de la fenêtre à l'ouverture (Preferences :
  topaz 8 ⇒ 8 × 8, topaz 9 ⇒ 10 × 9 sur cette ROM sans disque système) ; en NTSC l'écran fait 200 lignes,
  en PAL avec un écran 256 lignes YMax change en conséquence. [O sonde pour topaz 9 ; D pour le reste]
- **Injection d'entrées sous FS-UAE** : les frappes xdotool « alt+… » n'arrivent pas comme Alt Amiga dans
  ce harnais (Alt-k ⇒ `k`), et F1/F10 n'ont rien produit ; les touches mortes et Fn ont donc été validées
  par RawKeyConvert et IND_WRITEEVENT, pas par le clavier émulé. [O sonde]

---

## 8. Vecteurs de test (vraie ROM 34.5, FS-UAE, sonde `tests/con_probe.s`)

Sonde : `tests/con_probe.sh <sortie> 600` (vraie ROM par défaut). Fenêtre 640 × 200 (bordures 4/12/18/2),
topaz 9 ⇒ cellule 10 × 9, XMax 60, YMax 19. Chaque test commence par `ESC c FF`. Notation des résultats :
texte reconnu par ligne et position du curseur (XCP, YCP).

### 8.1 Contrôles et curseur

| Entrée (après ESC c FF) | Résultat |
|---|---|
| `AB LF CD CR LF EF` (LNM) | `AB` / `CD` / `EF`, curseur (2,2) |
| `CSI 20l AB LF CD LF CR EF` | `AB` / `··CD` / `EF` |
| `ABC BS BS X CR Y` | `YXC`, curseur (1,0) |
| `AB LF BS X` (AWM) | X en (60,0), curseur (0,1) après retour |
| `CSI ?7l AB LF BS X` | X en (0,1) |
| `HT A HT B HT HT C` | A col 8, B col 16, C col 32 |
| `CSI 3;10H CSI A A CSI 2B B CSI 5C C CSI 3D D CSI 0A E CSI -2B F` | A (9,1) ; B (10,3) ; C (16,3) ; D (14,3) ; « E2BF » en (15,2) (le `-` intermédiaire abandonne la séquence) |
| `ABCDEF CSI H 1 CSI 2H 2 CSI ;5H 3 CSI 3;f 4 CSI 0;0H 5` | `5BCD3F` / `2` / `4` |
| `CSI 99;999H X` | X en (60,19), retour + défilement : curseur (0,19) |
| `L1 L2 L3` (3 lignes) `CSI 1;1H CSI 2A T` | défilement vers le bas de 2 : `T` / vide / `L1` / `L2` / `L3` |
| idem avec `CSI >1l` | pas de défilement : `T` remplace L1 |
| `CSI 1;78H CSI 5C X` | X en (4,1) |
| `CSI 2;3H CSI 5D X` | X en (58,0) |
| `CSI 3;10H CSI E A CSI 2F B CSI 0E C` | A (0,3), B (0,1), C (0,2) |
| `CSI 3;5H A VT B $8D C` | A (4,2), B (5,1), C (6,0) |
| `CSI 20l A $84 B $85 C` | A (0,0), B (1,1), C (0,2) |
| `AB ESC D C ESC E D ESC M E ESC [2;8H F` | `AB` / `·EC····F` / `D` |
| `A ESC 7B ESC (0C ESC #8D ESC =E ESC aF ESC ESC [2CG` | `ACD` / `F··G` (ESC 7 B = ESC B ignoré ; ESC = E = NEL) |
| `A CSI 2 LF B CSI 1; ESC [CC CSI !pD CSI 5 HE CSI 1 CSI 2CF` | `A` / `B·CDE··F` |
| `A CSI 2!CB CSI 3 CC CSI !2CD` | `ABC2CD` |
| `ABC CSI 10GX CSI 3dY CSI 2XZ` | `ABCXYZ` (G, d, X ignorés) |
| `A $80 $81 $86 $90 $9A $9F B $7F C` | `AB` + glyphe `$7F` + `C` |
| `A $01 B $1C C $1F D` | `ABCD` |

### 8.2 Effacements, insertions, défilements

| Entrée | Résultat |
|---|---|
| `ABCDEFGH CR LF IJKLMNOP CSI 1;4H CSI K CSI 2;4H CSI 1K` | `ABC` / `IJK` |
| `ABCDEFGH CSI 1;4H CSI 2K` | `ABC` |
| 3 lignes `CSI 2;4H CSI J` | `ABCDEFGH` / `IJK` / vide |
| `ABCDEFGH CSI 1;3H CSI @ CSI 1;7H CSI 3@ x` | `AB·CDEx··FGH` |
| `ABCDEFGH CSI 1;3H CSI P CSI 1;4H CSI 2P x` | `ABDxH` |
| `L1 L2 L3 CSI 2;2H CSI L x` | `L1` / `·x` / `L2` / `L3` |
| `L1 L2 L3 L4 CSI 2;2H CSI 2M x` | `L1` / `Lx` (L4) / vide |
| `L1 L2 L3 L4 CSI S CSI 2T x` | vide / vide / `L2` / `L3x` (curseur fixe en (2,3)) |
| `TOP CSI 24;1H BOT LF N` | TOP disparu, `BOT` ligne 18, `N` ligne 19 |
| idem avec `CSI >1l` | `TOP` reste ; `N` écrase `B` en ligne 19 |
| `CSI 5t CSI 20u` + A…Z + `CSI 5;1H X LF Y` | XMax 19, YMax 4, XRExtant 203, YRExtant 56 ; `UVWXYZ` / vide / vide / `X` / `Y` |
| puis `CSI t CSI u Q` | XMax 60, YMax 19 ; Q en (1,4) |
| `CSI 16x CSI 20y AB` | XROrigin 16, YROrigin 20, XMax 59, YMax 18 |
| puis `CSI x CSI y C CSI 0x CSI 0y D` | XROrigin 0, YROrigin 0, XMax 61, YMax 21 |

### 8.3 Retour automatique (page de 20 colonnes : `CSI 20u`)

| Entrée (20 caractères = ligne pleine) | Résultat |
|---|---|
| 20 car. `LF B` | B en (0,1) (LF absorbé) |
| 20 car. `CR LF B` | B en (0,1) |
| 20 car. `B LF C` | B (0,1), C (0,2) |
| 20 car. `CSI E B` / `CSI F B` | B en (0,1) (absorbés) |
| 20 car. `LF LF B` | B en (0,2) (seul le premier LF est absorbé) |
| 20 car. `VT B` | B en (0,0) (VT n'est **pas** absorbé) |
| `CSI 20l` + 20 car. `LF B` | B en (0,1) (IND absorbé) |
| 18 car. `HT LF B` | B en (0,1) (HT a renvoyé à la ligne) |
| 20 car. `BS X` | X remplace T en (19,0), curseur (0,1) |
| `CSI 1;19H CSI 2C LF B` | B en (0,1) |
| `CSI ?7l` + 23 car. | `ABCDEFGHIJKLMNOPQRS` + `W` en colonne 19, curseur (19,0) |

### 8.4 SGR et couleurs (masque des couleurs présentes dans la cellule)

| Entrée | Résultat |
|---|---|
| `CSI 2m D` | D en couleur 2 |
| `CSI 7m R` | R en inverse (fond 1, texte 0) |
| `CSI 8m H CSI 0m N` | H non dessiné ; **bloc curseur résiduel** en colonne 0 |
| `CSI 30m A … CSI 37m F CSI 39m G` | couleurs 0, 1, 2, 3, 0 (34), 3 (37), 1 |
| `CSI 41m B`, `42m C`, `43m D`, `44m E`, `49m F` | fonds 1, 2, 3, 0, 0 |
| `CSI ;32m N` | SGR 0 puis APen 2 (FgPen = 2) |
| `CSI 1;4;7m A CSI 22;24;27m B` | B toujours gras/souligné/inverse |
| `ABCDEFGH CSI 43m CSI 1;4H CSI K` | colonnes 3+ remplies en couleur 3 |
| `CSI 42m FF A` | toute la ligne en couleur 2 |
| `CSI 43m L1 L2 CSI 1;1H CSI T` | ligne 0 libérée remplie en couleur 3 (ScrollRaster ⇒ BPen) |
| `ABCDEF CSI 43m CSI 1;2H CSI 2@` | cellules insérées en couleur 3 |
| `ABCDEFGH CSI 7m CSI 1;4H CSI K` | effacement en couleur 0 (DrawMode ≠ JAM2) |
| `AB CSI 0 SP p` | plus de bloc curseur |
| `C CSI SP p D CSI 0p E CSI p` | curseur visible (`0p`/`p` sans espace ignorés) |

### 8.5 Rapports, modes, entrée

| Entrée | Résultat |
|---|---|
| `xyz` avec io_Length −1 | io_Actual 3, io_Error 0 ; io_Length 0 ⇒ io_Actual 0 |
| `CSI 6n` puis CMD_READ | `9B 31 3B 35 52` (ligne 1, colonne 5) |
| `CSI 5n CSI n CSI 6;6n ESC [6n` | deux rapports |
| `CSI SP q` | `CSI 1;1;20;61 r` |
| `CSI 0 q`, `CSI q`, `CSI ␠␠q` | un seul rapport (le premier) |
| CMD_READ sans donnée, abandon après 10 trames | io_Error −2, io_Actual 0 |
| `CSI 20l CSI >1l CSI ?7l CSI 3h` | cu_Modes `08 00 00` |
| `CSI 20h CSI >1h CSI ?7h CSI 3l CSI 1;2;19h` | cu_Modes `06 00 78` |
| `CSI 1;2;18;19;-1{` | rien n'est exécuté : le `-` est un intermédiaire, le `1` qui suit abandonne la séquence et `1{` s'affiche ; cu_RawEvents reste `00 00 00` |
| SizeWindow(−200, −64) puis CMD_WRITE vide | XMax 40, YMax 12, XRExtant 413, YRExtant 128 ; rapport `CSI 1;1;13;41 r` ; avant l'écriture : inchangé |
| SizeWindow(+200, +64) puis écriture vide | XMax 60, YMax 19 ; zone révélée effacée |

### 8.6 Commandes (BeginIO direct, IOF_QUICK)

| Commande | io_Flags après | io_Error |
|---|---|---|
| 0, 4, 13, 14, `$7FFF` | `$81` | −3 |
| 1, 6, 7, 8 | `$81` | 1, 6, 7, 8 (D0 résiduel) |
| 5 (CLEAR) | `$01` (pas de réponse) | 0 |
| 5 sans IOF_QUICK | requête jamais rendue (ln_Type 5) | — |
| 4 sans IOF_QUICK | rendue (ln_Type 7) | −3 |
| CMD_STOP puis CMD_READ (rapport disponible) | READ non servie (abandon −2) ; après CMD_START : servie | — |
| CMD_READ io_Length 0 (A2 = 1) | Guru `#00000003` | — |

### 8.7 Fenêtres SIMPLE_REFRESH et GIMMEZEROZERO (400 × 100)

| Fenêtre / entrée | Résultat |
|---|---|
| SIMPLE_REFRESH : `HELLO CR LF WORLD` puis `ESC c X` | `XELLO`… : **rien n'est effacé** par ESC c, curseur (1,0) |
| GZZ : ouverture | XROrigin 0, YROrigin 0, XMax 36, YMax 8, YRExtant 80 |
| GZZ : `CSI 16x` | XMax 35, **YMax 6** (la hauteur perd 16 pixels) |
| GZZ : `CSI x CSI 16y` | **YMax 8**, YRExtant 96 > hauteur intérieure 86 (l'origine verticale n'est pas retranchée) |

---

## 9. Points non tranchés

1. **Cuisson des vraies frappes** (chaîne keyboard.device → input.device → intuition → console) non
   sondée de bout en bout avec Alt et les touches de fonction : l'injection xdotool de ce harnais ne
   transmet pas Alt comme Alt Amiga et F1/F10 n'ont rien donné. Le contenu de ie_X/ie_Y repose sur
   `intuiticks-repeat-v34.md` §2.1. À refaire avec un autre moyen d'injection (débogueur, ou
   keyboard.device direct).
2. **Fenêtre redimensionnée non active** : le recalcul est appliqué à l'unité active, pas à celle de la
   fenêtre redimensionnée [O ROM] ; l'effet visible sur une console inactive n'a pas été sondé.
3. **SUPER_BITMAP** : non sondé (le recalcul n'efface rien et ne replace pas le curseur ; curseur
   possiblement non réaffiché — à vérifier).
4. **SetMap du Workbench 1.3.3** : qu'il appelle CD_SETDEFAULTKEYMAP et/ou CD_SETKEYMAP et sur quelle
   unité n'a pas été vérifié sur le disque (D, usage documenté).
5. **Débordement de valeurs de paramètres** (> 32767) : CSI 65535C a borné le curseur comme attendu,
   mais l'arithmétique exacte (produit 16 × 16 signé, saturation partielle) n'est pas spécifiée au-delà.
6. **BEL** : DisplayBeep lu dans la ROM, effet visuel (flash d'écran) non capturé.
7. **Ordre des unités pour NEWACTIVE** : la première unité de la liste (la plus récemment ouverte) sur la
   fenêtre devient active [O ROM] ; non sondé avec deux unités ouvertes simultanément.

---

## Relecture clean-room

- [x] Aucune suite d'instructions 68000 transcrite ni paraphrasée, aucun extrait de désassemblage,
  aucune adresse de routine ROM. Les seules données ROM reproduites sont **fonctionnelles d'ABI** :
  contenu de la keymap « usa » (valeurs par touche, en tableau), chaînes rendues/émises, tailles et
  offsets de structures publiques (`conunit.h`, `keymap.h`) et constantes.
- [x] Les automates et algorithmes (§3.2, §5.2) sont décrits par leurs **entrées/sorties et effets
  visibles**, vérifiés par la sonde boîte noire, pas par la structure du code.
- [x] La sonde citée est du code auteur (`tests/con_probe.s`, en-tête « ASSET DE TEST, PAS du code ROM »).
