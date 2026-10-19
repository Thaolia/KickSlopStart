# bcpl-runtime-v34.md — Runtime BCPL de dos.library V34 (spec comportementale)

> Piste ANALYSE (« dirty »). Sources : la ROM `assets/kick34005.A500` (dos 34.3) et les
> commandes `c:` / `l:Shell-Seg` du disque `assets/wb133.adf` (Workbench 1.3.3).
> Objectif aval : permettre à notre ROM d'exécuter les commandes BCPL du Workbench 1.3
> (AddBuffers, CD, Path, Execute, Run, Wait, Resident, Mount, EndCLI, Shell-Seg).
>
> **Légende de certitude** (sur chaque affirmation) :
> **[O]** observé directement (ROM ou binaire WB) · **[D]** déduit d'observations convergentes ·
> **[S]** supposé (plausible, non vérifié).
> Provenance : **ROM** = Kickstart, **WB** = binaire du disque Workbench.
>
> Ce document décrit des comportements, des layouts d'ABI, des numéros de globales et des
> constantes. **Aucune suite d'instructions n'est reproduite ni paraphrasée.** Les adresses ROM
> citées servent uniquement de repères pour la piste analyse (l'implémentation n'en a pas besoin).

---

## 0. Résumé exécutable (ce qu'il faut absolument respecter)

1. **Le CLI ne distingue pas** un exécutable BCPL d'un exécutable C/asm. Il appelle toujours le
   premier hunk avec la même convention (§4). Le « côté BCPL » d'une commande `c:` 1.3 est porté
   par **son propre hunk 0** (stub de démarrage de 316 octets, identique dans les 14 commandes
   examinées), qui se fabrique un **vecteur global privé** puis appelle sa globale 1 (§3.3).
2. Ce stub **exige** à l'entrée : A2 = un GV valide contenant au minimum les globales
   **28 (globin), 29 (getvec), 89 (findsegarray)** ; A5/A6 = routines d'appel/retour BCPL ;
   `pr_SegList` du process = un **segarray** dont les entrées 1..`V!0` sont des segments au
   **format BCPL** (table d'init des globales en fin de hunk) qui fournissent tout le runtime
   (dont la globale **134 findCLI**, **30 freevec**). [O WB + D]
3. Les arguments d'une commande BCPL sont lus par `rdargs`/`rditem` **via `rdch` sur `input()`**.
   Le CLI a **remplacé temporairement le tampon** du FileHandle d'entrée par une copie du reste de
   la ligne (fh_Buf/fh_Pos=0/fh_End=n). La même copie est passée en A0/D0 aux programmes C. (§5) [O ROM]
4. Les globales **134..149** du GV privé d'une commande sont une **copie des 16 longs de la
   `CommandLineInterface`** : copiée à l'entrée, **recopiée dans la vraie structure au retour**.
   C'est ainsi que Failat/Prompt/Stack/Path/CD/Execute/EndCLI modifient le CLI. (§3.3, §8) [O WB]

---

## 1. Conventions d'appel BCPL (confirmation / corrections de la table publique)

### 1.1 Registres [O ROM + WB]

| Registre | Rôle | Statut |
|---|---|---|
| A0 | **toujours 0** (base d'adressage : les accès mémoire BCPL se font en « 0 + adresse octet », adresse = BPTR×4) | [O] |
| A1 | pointeur de frame BCPL courant (adresse octet, pas un BPTR) | [O] |
| A2 | adresse (octet) du **slot 0** du vecteur global courant | [O] |
| A4 | adresse d'entrée de la routine **en cours d'exécution** (sert de base pour les chaînes et appels locaux PC-indépendants) | [O] |
| A5 | routine d'**appel** (call) ; A5+$10 = multiply, A5+$12 = divide | [O] |
| A6 | routine de **retour** ; une routine BCPL rend la main par un saut à A6 | [O] |
| D0 | à l'appel : **taille en octets de la frame de l'appelant** = décalage du nouveau A1 par rapport à l'actuel | [O] |
| D1–D4 | 4 premiers arguments ; **D1 = résultat** au retour | [O] |
| A7 | pile 68000 ; **inchangée** au travers d'un appel BCPL (la routine d'appel retire immédiatement l'adresse de retour qu'empile le `jsr`) | [O] |

Registres non préservés par un appel : D0, D2–D7, A3 (scratch). A0 doit rester 0 ; A2/A5/A6 sont
invariants ; A1/A4 sont restaurés par la routine de retour. [D]

### 1.2 Frame [O ROM]

Sur un appel avec D0 = *t* : la nouvelle frame commence à `A1 + t`. La routine d'appel range, dans
les 3 longs **précédant** la nouvelle frame :

| Offset / nouvelle frame | Contenu |
|---|---|
| −12 | A1 de l'appelant (frame de l'appelant) |
| −8 | adresse de retour |
| −4 | **A4 de l'appelé** = adresse d'entrée de la routine propriétaire de cette frame |

puis range D1..D4 aux offsets 0, 4, 8, 12 de la nouvelle frame et saute à A4.
Les arguments 5, 6, … sont écrits **par l'appelant** directement en mémoire aux offsets 16, 20, …
de la future frame (= `A1_appelant + t + 16`, …) avant l'appel. Il n'y a **pas de limite** de
nombre d'arguments (writef, sendpkt en utilisent ≥ 6).

Au retour (saut à A6) : A1 et l'adresse de retour sont relus aux offsets −12/−8 de la frame
courante, puis **A4 est relu à l'offset −4 de la frame de l'appelant** (donc A4 retrouve l'entrée
de la routine appelante).

> **Correction de la table publique** : « −4 = ancien A4 » est imprécis. Le slot −4 d'une frame
> contient l'**entrée de la routine qui possède la frame** (A4 de l'appelé), et A4 est restauré
> depuis la frame **de l'appelant**. [O ROM]

### 1.3 Arithmétique (A5+$10, A5+$12) [O ROM]

- **A5+$10 multiply** : D1 := D1 × D2 (32 bits bas, signe indifférent). Les autres registres sont préservés.
- **A5+$12 divide** : division **signée**, quotient tronqué vers 0 en **D1**, reste en **D2** (signe
  du reste = signe du dividende, sémantique C). Les deux résultats sont utilisables.
- A5+$14 existe (variante interne « diviseur supposé ≥ 0 ») ; aucune commande examinée ne
  l'utilise. Les commandes WB n'utilisent que +$10 et +$12. [O WB]

### 1.4 Pont LVO → BCPL (pour mémoire) [O ROM]

Chaque vecteur LVO public de dos (−30 Open … −222 Execute) charge un **numéro de globale** puis
saute dans un pont commun qui : sauve D2–D7/A2–A6 sur la pile C, met A0 = 0, installe une frame
BCPL **1500 octets ($5DC) sous le SP courant** (alignée pair), charge A2/A5/A6 depuis
`dl_A2`/`dl_A5`/`dl_A6` (base +$2A/+$2E/+$32), appelle la globale avec D1–D4 **tels que fournis
par l'appelant C**, et renvoie D1 dans D0. Conséquence : tout appelant C d'une LVO dos doit
disposer d'au moins ~1,5 Ko de pile libre. Correspondance LVO → globale observée :

| LVO | Fonction | Gl. | | LVO | Fonction | Gl. |
|---|---|---|---|---|---|---|
| −30 | Open | −1 | | −132 | IoErr | −17 |
| −36 | Close | **93** | | −138 | CreateProc | −18 |
| −42 | Read | −3 | | −144 | Exit | **2** |
| −48 | Write | −6 | | −150 | LoadSeg | −19 |
| −54 | Input | **65** | | −156 | UnLoadSeg | **82** |
| −60 | Output | **66** | | −162 | GetPacket | −20 (!) |
| −66 | Seek | −8 | | −168 | QueuePacket | −21 (!) |
| −72 | DeleteFile | −9 | | −174 | DeviceProc | −22 |
| −78 | Rename | −10 | | −180 | SetComment | −23 |
| −84 | Lock | −11 | | −186 | SetProtection | −24 |
| −90 | UnLock | **109** | | −192 | DateStamp | −25 |
| −96 | DupLock | **113** | | −198 | Delay | **47** |
| −102 | Examine | −12 | | −204 | WaitForChar | **87** |
| −108 | ExNext | −13 | | −210 | ParentDir | **35** |
| −114 | Info | −14 | | −216 | IsInteractive | −26 |
| −120 | CreateDir | −15 | | −222 | Execute | −27 |
| −126 | CurrentDir | −16 | | | | |

(!) **Anomalie V34** : la globale −20 est `clearvec` (utilitaire BCPL) et −21 sert de « LoadSeg
sans requester » ; les LVO GetPacket/QueuePacket de la 1.3 aboutissent donc à des fonctions sans
rapport avec leur nom documenté. [O ROM pour le câblage, D pour −21]

Les globales **négatives** sont des adaptateurs « ABI C » (arguments C : chaînes C, APTR) ; les
positives sont l'ABI BCPL (BPTR/BSTR). Les globales positives citées en gras sont partagées : la LVO
appelle directement la globale BCPL (arguments déjà au format BPTR, ex. FileHandle/lock). [O]

---

## 2. Q1 — Le vecteur global (GV)

### 2.1 Format général [O ROM + WB]
- Un GV est un bloc de longs indexé de **−N_neg à +N_max**. A2 (et `dl_GV`, `pr_GlobVec`)
  pointent sur le **slot 0** (adresse octet, pas BPTR).
- **GV[0] = numéro de la plus grande globale autorisée** (« slot count »). `globin` refuse
  d'installer une globale de numéro > GV[0] (comparaison signée : les numéros négatifs passent
  toujours). [O ROM]
- Partie négative : **50 longs** (slots −50..−1) dans tous les GV observés (dos et commandes). [O]

### 2.2 Le GV de dos (`dl_GV`) [O ROM]
- Alloué par le code d'init de dos (rt_Init) : un bloc `AllocMem(804 octets = 201 longs,
  MEMF_PUBLIC)` **non effacé** ; `dl_GV` (base+$26) = début du bloc + 200 octets (50 longs
  négatifs) → slots −50..+150. **GV[0] = 150**.
- Les slots non définis gardent **le contenu indéfini de la mémoire** (pas de remplissage). [O]
- Il est rempli par `globin` des segments BCPL de la ROM lors du démarrage du **premier process**
  (§2.4).
- C'est **le même GV** que : le premier process (« Initial CLI »), tous les CLI créés par
  Run/NewCLI (qui passent le GV de leur parent, cf. §8), et le pont LVO. [O ROM + WB]
- **GV partagé ≠ GV de commande** : une commande BCPL ne travaille **jamais** dans `dl_GV` ; son
  stub crée un GV privé (§3.3). `pr_GlobVec` du process CLI n'est pas modifié pendant la commande. [O WB]

### 2.3 Rangement [O ROM]
- `pr_GlobVec` (process +$88) = **APTR** (adresse octet du slot 0), pas un BPTR. (Run le relit
  et le convertit en BPTR avant de le passer à createproc.) [O]
- `dl_GV` (DosLibrary +$26) = APTR idem. `dl_A2` (+$2A) = même valeur ; `dl_A5` (+$2E) / `dl_A6`
  (+$32) = adresses des routines d'appel / retour. [O]

### 2.4 Segarray (`pr_SegList`) et initialisation [O ROM]
- `pr_SegList` (process +$80) = **BPTR vers un « segarray »** : `V!0 = n`, `V!1..V!n` = BPTR de
  chaînes de segments. La globale 89 (`findsegarray`) le renvoie.
- Segarray ROM (à $FF3E24) : `V!0 = 4`, mais **7 entrées** utiles :
  1. noyau BCPL (chaîne de 4 segments : mémoire, process, I/O devices, coroutines, chaînes…),
  2. dos (« BLIB » : flux, rdargs, writef, fichiers…),
  3. `cliinit` (globale 133 ; startup-sequence, fenêtre CON:…),
  4. le **CLI** (globale 1),
  5. console-handler, 6. file system (chaîne de 10 segments, globales jusqu'à 266), 7. validateur.
  Seules les entrées 1..4 (`V!0`) sont « installées » dans les GV ; les 5..7 servent de segments
  pour d'autres process (handlers). [O pour le contenu, D pour le rôle exact de 5..7]
- Démarrage d'un process BCPL (créé par la globale 33) : remplissage de sa pile avec le motif
  **$ABABABAB**, création de la frame de base BCPL au **bas** de la pile (`!1 = −1`, `!2` = limite
  haute), GV[12] := BPTR de cette base, puis `globin(V!i)` pour i = 1..V!0 dans **pr_GlobVec**,
  puis **attente du packet de démarrage** (taskwait), puis `start(pkt)` (globale 1, frame 32
  octets). Au retour de start : fin du process. [O]
- Le premier process est créé par l'init de dos avec : segarray ROM, pile **400 longs (1600
  octets)**, pri 0, nom BSTR **"Initial CLI"**, GV = `dl_GV`. [O]

---

## 3. Q3 — Format d'un segment BCPL, `globin`, stub des commandes

### 3.1 Format d'un hunk BCPL [O ROM + WB]
Pour un hunk de code de *N* longs (les données chargées du hunk, c.-à-d. `BADDR(seg)+4`) :

| Position (en longs, depuis le début des données du hunk) | Contenu |
|---|---|
| 0 | **N** = longueur de la section en longs (égale à la taille du hunk) |
| 1 … | code (la routine globale 1 commence typiquement à l'octet 4) |
| … | (chaînes BSTR alignées sur 4, données) |
| N−2k−2 | **0** (terminateur) |
| N−2k−1, N−2k | paire k : **numéro de globale**, puis **offset octet** |
| … | … autres paires (numéro à l'adresse basse, offset à l'adresse haute) |
| N−1 | **plus grande globale référencée** par ce segment |

- L'**offset est relatif au début des données du hunk** (le long « N »), en octets. Valeur
  installée = adresse absolue `BADDR(seg)+4+offset` (une **adresse machine**, pas un BPTR). [O]
- Exemples [O WB] : AddBuffers (127 longs) : paire (1, $4), max 102. CD : (84, $2B8), (1, $4),
  max 153. Execute : (166, $582), (1, $4), max 168. Resident : (1, $CC), max 109.
  Shell-Seg (1 hunk de 1770 longs) : (1, $4), max 133.
- Un exécutable BCPL de commande = fichier hunk ordinaire (HUNK_HEADER/HUNK_CODE), **sans
  relocations** dans les cas examinés, avec deux hunks : hunk 0 = stub (79 longs), hunk 1 = le
  module BCPL au format ci-dessus. Rien dans le fichier ne le marque « BCPL » (pas de magic). [O]

### 3.2 `globin(seg)` — globale 28 (GV +$70) [O ROM]
- Parcourt la **chaîne** de segments à partir de `seg` (BPTR ; suit le lien en tête de chaque
  segment jusqu'à 0). Pour chaque segment, parcourt la table depuis la fin (en sautant le long
  « max ») vers le terminateur 0, et pour chaque paire écrit `GV[num] := adresse`.
  `seg = 0` : rien à faire, succès.
- **Pas de vérification** du long « max » ; seule vérification : `num > GV[0]` → échec.
- Renvoie **−1 (TRUE)** si tout est installé ; sinon **0** avec **Result2 = 111** (valeur non
  documentée publiquement). Les paires déjà traitées avant l'erreur restent installées.
- Les paires sont traitées de la dernière vers la première : si un même numéro apparaît deux fois,
  **la paire de plus basse adresse l'emporte**. [D]

### 3.3 Stub de démarrage des commandes `c:` (hunk 0, 316 octets) [O WB]
Identique (md5 `d6b59e0e42e7bc95b5f0dd07c9697e85`) dans AddBuffers, CD, Echo, EndCLI, Execute,
Failat, Mount, NewCLI, Path, Prompt, Resident, Run, Stack, Wait. Effets observables, dans l'ordre :

1. Lit le segarray du process via la globale **89** du GV appelant (A2 à l'entrée).
2. Calcule `max` = le plus grand des longs « max » des hunks **de la commande** (hunks suivant le
   stub dans la seglist), avec un **plancher de 149**. (Les segments ROM ne sont pas pris en compte.)
3. Alloue via la globale **29** du GV appelant un vecteur de `max + 50` longs (→ 50 slots négatifs
   + slots 0..max). Échec → la commande renvoie **−1** en D0.
4. Initialise **GV[0] = max** et **GV[i] = $474C0001 + 2·i** pour i = 1..max (marqueur « GL » +
   nombre impair : appeler une globale non définie saute à une adresse **impaire** → erreur
   d'adresse 68000). **Les slots négatifs ne sont pas initialisés** (sauf par globin ensuite).
5. Construit la frame BCPL de base **au bas de la pile de la commande** : base = (A7 d'entrée + 8)
   − taille de pile en octets (lue à 4(A7) d'entrée) ; `base!1 = −1`, `base!2 = base + taille
   − 160` (limite) ; **GV[12] := BPTR(base)** (« currco »/stackbase).
6. Avec la globale **28** du GV **appelant** (mais A2 = nouveau GV), installe : les entrées
   1..`V!0` du segarray (le runtime), puis la seglist de la commande (à partir du hunk 1). Tout
   échec → D0 = −1.
7. Appelle la globale **134** (findCLI) du **nouveau** GV. Si non nul : copie les **16 longs** de
   la `CommandLineInterface` dans **GV[134..149]**.
8. Remplace **GV[2] (stop)** par sa propre routine de sortie (stop(n) fait revenir de l'étape 9
   avec le code n, quel que soit le niveau d'imbrication — A7 n'ayant pas bougé).
9. Appelle **GV[1] (start)** avec D1 = 0, frame 32 octets. Retour normal ⇒ code retour **0** (le
   D1 rendu par start est **ignoré**) ; sortie par stop(n) ⇒ code **n**.
10. Si l'étape 7 avait trouvé une CLI : **recopie GV[134..149] dans la `CommandLineInterface`**.
11. Libère le GV privé (globale 30 du nouveau GV) et revient (`rts`) avec le code en **D0**.

Correspondance GV[134+i] ↔ champ CLI (offset 4·i) [O WB par usage : Failat→139, Prompt→140,
Stack→147, Path→136, CD→135, EndCLI→141/142/145, Execute→142/143] :

| Gl. | CLI | Gl. | CLI | Gl. | CLI | Gl. | CLI |
|---|---|---|---|---|---|---|---|
| 134 | Result2 | 138 | CommandName | 142 | CurrentInput | 146 | CurrentOutput |
| 135 | SetName | 139 | FailLevel | 143 | CommandFile | 147 | DefaultStack |
| 136 | CommandDir | 140 | Prompt | 144 | Interactive | 148 | StandardOutput |
| 137 | ReturnCode | 141 | StandardInput | 145 | Background | 149 | Module |

Les commandes utilisent aussi des globales **≥ 150** comme variables statiques privées (CD 150–153,
Execute 150–168, Mount 150–158) — d'où l'intérêt du GV privé. [O WB]

### 3.4 Distinguer BCPL / C [O ROM]
- **Le CLI ne fait aucune différence** : il charge (LoadSeg), puis appelle le premier hunk via la
  globale 121 (§4) dans tous les cas.
- `dn_GlobalVec` (DeviceNode) est l'unique « drapeau BCPL » de dos, et ne concerne que les
  **handlers** lancés par dos (cf. `dos-v34-spec.md`), pas les commandes.
- Un segment directement BCPL **sans stub** (ex. `l:Shell-Seg`, le CLI ROM, les handlers) n'est
  exécutable que comme **entrée de segarray d'un process** (createproc + globin au démarrage), pas
  comme commande. [O/D]

---

## 4. Q4 — Lancement d'une commande par le CLI

### 4.1 Recherche [O ROM]
- Nom lu par `rditem` dans `cli_CommandName` (tampon de 25 longs → ≤ 103 caractères). Item vide
  → ligne ignorée ; erreur → message « Error in command name ».
- Recherche : répertoire courant, puis chaque nœud du **chemin `cli_CommandDir`** (liste de nœuds
  `!0` = BPTR suivant, `!1` = lock), puis `C:` (via deviceproc + le lock rendu en Result2). Une
  seconde passe a lieu si l'échec n'est pas 218 (device non monté). **Pas de liste Resident** dans
  le CLI ROM (c'est Shell-Seg qui la gère). [O]
- Non trouvé : si l'erreur est 205 (objet absent) ou 218 → « Unknown command %S » ; sinon
  « Unable to load %S: » + message d'erreur (globale 104). [O]

### 4.2 Préparation (routine « run » locale au CLI) [O ROM]
1. Lit des caractères après le nom (le terminateur du nom a été remis par `unrdch`), saute blancs
   et tabulations, traite les redirections **`<fichier`** (findinput) et **`>fichier`**
   (findoutput) — uniquement **avant** les arguments ; une deuxième redirection du même sens →
   « too many > or < » ; échec d'ouverture → « Unable to open redirection file ».
2. Copie **le reste de la ligne** (jusqu'au `\n` inclus ou EOF) dans un tampon local de **256
   octets** (dépassement → « command too long ») avec ces règles :
   - `"` bascule l'état « entre guillemets » (le `"` est copié) ;
   - `;` hors guillemets **arrête la copie** (commentaire), la lecture continue jusqu'au `\n` ;
   - `+` suivi immédiatement de `\n` : le `\n` est copié **et la lecture continue sur la ligne
     suivante** (continuation) ; `+` sinon : copié tel quel ;
   - le `\n` final est copié (sauf s'il tombe dans un commentaire).
3. Entrée de la commande = le fichier `<` sinon **`cli_StandardInput`** (pas CurrentInput : dans un
   script Execute, la commande lit la console). Sortie = le fichier `>` sinon `output()` courant.
4. **Injection des arguments** : sauvegarde `fh_Buf`, `fh_Pos`, `fh_End` du FileHandle d'entrée,
   puis `fh_Buf` := BPTR du tampon local, `fh_Pos` := 0, `fh_End` := *n* (octets copiés).
   `selectinput`/`selectoutput` sur ces flux ; **pr_Result2 := 0**.
5. Appel `runcommand(seg, cli_DefaultStack, BPTR tampon, n)` (globale 121).
6. Au retour : restaure `fh_Buf` (seulement s'il pointe encore sur le tampon local) et `fh_Pos` ;
   restaure `fh_End` **sauf s'il vaut 0** (une commande peut forcer l'EOF, cf. EndCLI) ; ferme les
   fichiers `<`/`>` éventuels.

### 4.3 `runcommand(seg, pile, args, len)` — globale 121 (GV +$1E4) [O ROM]
- Alloue la pile par `getvec(pile)` (pile en **longs** ; échec → renvoie **−1** sans appeler).
- Haut de pile = fin du vecteur. Sur la nouvelle pile (de haut en bas) : l'ancien A7, puis la
  **taille de pile en octets** (= pile×4) ; **`pr_ReturnAddr` := adresse de ce long « taille »**
  (l'ancienne valeur est sauvée et restaurée au retour).
- Appel par `jsr` de `BADDR(seg)+4` (premier hunk). **État à l'entrée de la commande** :

| Élément | Valeur |
|---|---|
| (A7) | adresse de retour |
| 4(A7) | taille de la pile en octets (= cli_DefaultStack × 4) |
| 8(A7) | (interne : ancien A7) |
| A0 | adresse octet de la copie des arguments |
| D0 | longueur des arguments (**inclut** le `\n` final) |
| D2 | taille de pile en octets (même valeur que 4(A7)) [O, non contractuel] |
| A1 | frame BCPL de l'appelant (dans la pile du CLI) |
| A2 | GV du CLI (= `dl_GV` pour le CLI ROM) |
| A5 / A6 | routines BCPL d'appel / retour |
| A3 | BADDR(seg) [O, non contractuel] |
| input()/output() | flux préparés §4.2, tampon d'entrée = arguments |
| pr_Result2 | 0 |

- **Pile BCPL = pile 68000** : même bloc mémoire. Le stub BCPL bâtit ses frames **depuis le bas**
  (début du vecteur getvec) vers le haut, tandis que A7 descend depuis le haut. [O WB]
- Le programme rend la main par `rts` avec **D0 = code retour**. `runcommand` restaure lui-même
  A1/A2/A5/A6, `pr_ReturnAddr` et l'ancien A7 : la commande n'a **aucun registre à préserver**. [O]
- Sortie anticipée : la globale 2 de `dl_GV` (= LVO Exit) remet A7 à `pr_ReturnAddr − 4` et
  exécute un `rts` avec D0 = code → retour au même point que le `rts` normal. [O]
- Libère la pile, renvoie le code en D1. **Ne touche pas pr_Result2.** [O]

### 4.4 Après la commande (CLI) [O ROM]
- `cli_ReturnCode` := code ; `cli_Result2` := pr_Result2 si code ≠ 0, sinon 0.
- `selectoutput(cli_StandardOutput)`, `selectinput(cli_CurrentInput)`.
- Si code ≥ `cli_FailLevel` **et CLI non interactif** : affiche « %S failed returncode %N », puis
  traite l'entrée courante **comme en fin de fichier** (abandon du script Execute, §4.5). En mode
  interactif, aucun effet (ni message ni abandon).
- Se resynchronise sur la fin de ligne : `unrdch()` puis lit jusqu'à `\n`/EOF (normalement 1 seul
  caractère, puisque la ligne a déjà été consommée par l'étape §4.2).
- `unloadseg(cli_Module)`, `cli_Module` := 0.
- Code **−1** = cas spécial « impossible de lancer » (traité comme un échec de chargement).

### 4.5 Boucle et fin de flux du CLI [O ROM]
- `cli_Interactive` := (non `cli_Background`) **et** (`cli_StandardInput` = `cli_CurrentInput`).
- Interactif : écrit le caractère 15, puis `writef(cli_Prompt, numéro de tâche)`, puis `wrch(0)`
  (le NUL force le vidage du tampon console). Non interactif : teste CTRL-D →
  « **BREAK - CLI » et abandon du script.
- EOF sur l'entrée courante :
  - script (CurrentInput ≠ StandardInput) : ferme le script, **supprime `cli_CommandFile`** s'il
    est non vide (fichier temporaire d'Execute) puis le vide, revient à StandardInput,
    **FailLevel := 10** ;
  - console, CLI non Background : `fh_End` := −1 sur stdin (prochaine lecture redemande au
    handler) et écrit 1 à l'offset $24 du FileHandle [O, sens non élucidé] ;
  - **Background** : fin du CLI (vidage de la sortie, fermetures, libération de la liste de
    chemins, `rn_TaskArray[n]` := 0, fin du process).

---

## 5. Q5 — Lecture des arguments : flux, rdargs, rditem

### 5.1 FileHandle vu par le runtime BCPL [O ROM]
FileHandle = vecteur `getvec` de **11 longs** (44 o) + en-tête getvec, alloué effacé :

| Off. | Champ | Usage runtime |
|---|---|---|
| $04 | fh_Interactive (fh_Port) | ≠ 0 ⇒ flux interactif (renvoyé tel quel par IsInteractive, gl. −26) |
| $08 | fh_Type | MsgPort du handler (0 pour NIL:) |
| $0C | fh_Buf | **BPTR** du tampon |
| $10 | fh_Pos | index **octet** du prochain caractère |
| $14 | fh_End | index octet de fin de données (lecture) / capacité (écriture) |
| $18 | fh_Funcs | **adresse machine** d'une routine BCPL « remplir » (lecture) |
| $1C | fh_Func2 | adresse d'une routine BCPL « vider » (écriture) |
| $20 | fh_Func3 | adresse d'une routine BCPL « fermer » |
| $24 | fh_Args | argument handler (fh_Arg1) passé dans les packets |

- À l'ouverture (`findinput`/`findoutput`, mode 1005/1006) : `fh_Pos = fh_End = −1`, les trois
  routines installées. `*` → console (`pr_ConsoleTask`) ; `NIL:` → aucun handler, routines à 0
  (lecture = EOF immédiat, écriture = caractères ignorés). Sinon deviceproc + packet
  ACTION_FINDINPUT/OUTPUT (arg1 = FileHandle, arg2 = lock rendu par deviceproc, arg3 = nom). [O]
- Tampon alloué **paresseusement** au premier remplissage/vidage : `getvec(49)` = **200 octets**.
  Remplissage = Read de ≤ 200 octets ; `fh_Pos` := 0, `fh_End` := octets lus. Échec d'allocation :
  EOF, Result2 = 103. [O]
- Fermeture (globale 93 = LVO Close) : vide si nécessaire, libère le tampon, envoie ACTION_END
  (1007, arg1 = fh_Args) (avec requester de retry), puis **freevec du FileHandle** (Result2
  préservé). ⇒ les FileHandles doivent être des blocs **getvec** (en-tête de taille à −4). [O]

### 5.2 rdch / unrdch [O ROM]
- **rdch()** (54) opère **toujours sur `input()`**. Si `fh_Pos < fh_End` : renvoie l'octet
  `buf[fh_Pos]` (non signé) et incrémente `fh_Pos`. Sinon : si `fh_End = 0` → **−1 (EOF)** sans
  contacter le handler ; sinon appelle fh_Funcs ; succès → renvoie le premier octet (fh_Pos = 1) ;
  échec → `fh_Pos = fh_End = 0` et −1.
- **unrdch()** (55) : si `fh_Pos > 0` → `fh_Pos−1`, renvoie TRUE ; sinon renvoie TRUE ssi
  `fh_End = 0` (EOF « relisible »), FALSE sinon.
- Conséquence pour l'injection d'arguments : une commande lit exactement les *n* octets copiés ;
  lire au-delà déclenche un vrai remplissage depuis le handler (c'est ainsi que le `?` de rdargs
  relit une ligne au clavier). [D]

### 5.3 rditem(v, taille) — globale 79 (GV +$13C) [O ROM]
- `v` = BPTR d'un vecteur de *taille*+1 longs, **effacé** au début (clearvec) ; l'item y est
  rangé comme **BSTR** (longueur dans l'octet 0). Capacité : (taille+1)·4 − 1 caractères.
- Saute blancs/tabulations. `"` initial ⇒ item entre guillemets.
- Non quoté : se termine sur `\n`, EOF, `;`, espace, tab ou `=` ; le terminateur est **remis**
  (unrdch).
- Quoté : se termine sur le `"` fermant (consommé, **non** remis) ; `*N`/`*n` → LF, `*E`/`*e` →
  ESC (27), `*x` → x littéral ; `\n`/EOF avant le `"` fermant ⇒ erreur.
- Résultats : **1** item normal ; **2** item quoté ; **0** fin (rien lu avant `\n`/`;`/EOF —
  terminateur remis) ; **−2** `=` rencontré sans item (le `=` est consommé) ; **−1** erreur
  (débordement ou guillemet non fermé).

### 5.4 rdargs(template, argv, taille) — globale 78 (GV +$138) [O ROM]
- Arguments : D1 = **BSTR** du template, D2 = **BPTR** argv, D3 = taille d'argv en **longs**.
- **Template** : clés séparées par `,` ; alias par `=` (`SEC=SECS/S`, `TO=AS`) ; qualificatifs
  insensibles à la casse `/A` (obligatoire), `/K` (mot-clé requis), `/S` (switch). Les **noms vides
  sont permis** (clé positionnelle pure : Path `",,,,,,,,,,ADD/S,SHOW/S,RESET/S,QUIET/S"`, Wait
  `",SEC=SECS/S,MIN=MINS/S,UNTIL/K"`). Un template vide `""` consomme la ligne (EndCLI).
- **Vecteur résultat** : `argv!i` (i = 0..nclés−1) =
  - **0** : clé absente (après contrôle /A) ;
  - **−1** : switch /S présent ;
  - sinon **BPTR d'un BSTR** stocké dans la **zone libre d'argv** (à partir de `argv!nclés`).
  Pendant l'analyse, `argv!i` contient temporairement les drapeaux de la clé (bit0 /A, bit1 /K,
  bit2 /S), d'où la valeur 0..7 testée pour « non rempli ».
- Algorithme observable : chaque item non quoté est d'abord cherché comme mot-clé (findarg,
  insensible à la casse, alias compris). Mot-clé /S → −1. Autre mot-clé → l'item **suivant**
  (éventuellement après `=`) est sa valeur. Sinon (ou item quoté) → valeur positionnelle affectée
  à la **première clé non remplie qui n'est ni /K ni /S**. Item non-clé égal à `?` suivi de `\n` →
  écrit `"<template>: "` et continue l'analyse sur une nouvelle lecture.
- Fin (rditem = 0) : toute clé /A non remplie ⇒ erreur ; sinon consomme le terminateur
  (`\n` ou `;`) et renvoie **non nul** (BPTR du premier long libre d'argv).
- Erreur (clé inconnue en trop, /A manquant, item trop long, plus de place) : **saute le reste
  de la ligne** jusqu'à `\n`, `;` ou EOF, **Result2 = 120**, renvoie **0**.
- [O] La taille restante passée à rditem est calculée **une fois** au début (pas décrémentée au
  fil des items) : un argv trop petit peut déborder. À reproduire tel quel ou à durcir.

### 5.5 findarg(template, item) — globale 80 (GV +$140) [O ROM]
Renvoie l'index (0-based) de la clé dont un des alias égale `item` (insensible à la casse), ou −1.

---

## 6. Q6 — Sortie : wrch, writes, writef, newline…

### 6.1 wrch(c) — globale 56 [O ROM]
- Opère sur `output()`. Si `fh_Pos ≥ fh_End` : appelle fh_Func2 (vider) puis `fh_Pos` repart
  à 0 ; si fh_Func2 est nul (NIL:), le caractère est perdu. Range `c` (octet bas) en `buf[fh_Pos++]`.
- Puis, si `c < 32` **et** flux interactif **et** `c ∈ {0, 10, 12, 13}` : vide immédiatement et
  `fh_Pos := 0`.
- Premier vidage = allocation du tampon de 200 octets (`fh_Pos = 0`, `fh_End = 200`), sans écriture.
  Vidage suivant = Write de `fh_Pos` octets. Le vidage **ignore** les erreurs d'écriture et
  préserve Result2. Fermeture = vidage final si `fh_Pos > 0`.
- ⇒ Fichiers : tamponnés par 200, vidés à la fermeture. Console : vidée à chaque LF/CR/FF/NUL.

### 6.2 Fonctions d'écriture [O ROM]

| Gl. | Off. | Fonction | Sémantique |
|---|---|---|---|
| 53 | $0D4 | writet(s, w) | écrit le BSTR `s` puis des espaces jusqu'à `w` colonnes (pas de troncature) |
| 68 | $110 | newline() | wrch(10) |
| 69 | $114 | writed(n, w) | décimal signé, aligné à droite sur `w` (espaces avant le `-`), pas de troncature |
| 70 | $118 | writen(n) | writed(n, 0) |
| 71 | $11C | writehex(n, d) | exactement `d` chiffres hexa **majuscules** (zéros de tête ; d ≤ 1 → 1 chiffre ; bits hauts tronqués) |
| 72 | $120 | writeoct(n, d) | idem en octal |
| 73 | $124 | writes(s) | écrit le BSTR `s` (D1 = BPTR) |
| 74 | $128 | writef(fmt, a1, a2, …) | voir ci-dessous |

### 6.3 writef [O ROM]
`fmt` = BSTR ; les arguments sont les longs consécutifs suivant `fmt` dans la frame (nombre
illimité). Chaque `%` lit la lettre suivante (insensible à la casse) :

| Code | Effet | Consomme un arg | Lit un chiffre de largeur |
|---|---|---|---|
| `%S` | writes(arg) (BSTR) | oui | non |
| `%T` | writet(arg, w) | oui | **oui** |
| `%C` | wrch(arg) | oui | non |
| `%N` | writen(arg) | oui | non |
| `%I` | writed(arg, w) | oui | **oui** |
| `%U` | décimal **non signé**, largeur w | oui | **oui** |
| `%X` | writehex(arg, w) | oui | **oui** |
| `%O` | writeoct(arg, w) | oui | **oui** |
| `%$` | **saute** un argument, n'écrit rien | oui | non |
| autre | écrit la lettre elle-même (`%%` → `%`) | non | non |

Chiffre de largeur : `0`–`9` → 0–9 ; une lettre → valeur `10 + (code − 'A')` (`A`=10, `B`=11…).
Exemples : `"%N> "` (prompt), `"[CLI %N]\n"`, `"%S failed returncode %N\n"`, `"%TH %I3"` (Resident :
nom sur 17 colonnes, nombre sur 3).

### 6.4 Lecture numérique — readn() (67) [O ROM]
Saute espaces/tab/LF, accepte `+`/`-`, lit les chiffres décimaux, remet le caractère suivant.
Succès : Result2 = 0, renvoie la valeur. Aucun chiffre : remet le caractère, Result2 = −1, renvoie 0.

---

## 7. Q7 — Coroutines

**Non.** Aucune des commandes examinées (AddBuffers, CD, Echo, EndCLI, Execute, Failat, Mount,
NewCLI, Path, Prompt, Resident, Run, Stack, Wait) ni `l:Shell-Seg` n'appelle les globales 23–27
(createco, deleteco, callco, cowait, resumeco). [O WB] Elles existent dans le noyau ROM (globale 12
= coroutine courante / base de pile, mise à jour par le stub). [O ROM]

---

## 8. Q2 — Table des globales (ROM V34)

Numéro → offset octet = 4×n. Unités : **BPTR** (adresse/4), **BSTR** (BPTR vers chaîne à
longueur), **APTR** (adresse octet), **taskid** = adresse du MsgPort d'un process (process+$5C).
« R2 » = effet sur Result2 (`pr_Result2`). Colonne « Cmd » : commandes cibles qui l'appellent
(A=AddBuffers, C=CD, P=Path, X=Execute, R=Run, W=Wait, E=EndCLI, S=Resident, M=Mount, H=Shell-Seg).

### 8.1 Noyau (segments ROM entrée 1)

| Gl. | Off. | Nom | Arguments → résultat (D1) | R2 | Cert. | Cmd |
|---|---|---|---|---|---|---|
| 0 | $000 | globsize | (valeur) nombre max de globales | | O | |
| 1 | $004 | start | entrée du programme/process | | O | toutes |
| 2 | $008 | stop(code) | dl_GV : quitte jusqu'à pr_ReturnAddr avec D0=code (= LVO Exit) ; GV de commande : remplacée par le stub | | O | A C P X R W S M |
| 3 | $00C | muldiv: mult(a,b) | a×b | | O | |
| 4 | $010 | div(a,b) | a/b (troncature vers 0) | | O | |
| 5 | $014 | rem(a,b) | reste (signe du dividende) | | O | |
| 6 | $018 | setio(iob, cmd, data, len, offset) | remplit io_Command (mot), io_Data (BPTR→APTR), io_Length, io_Offset (5e arg) | | O | |
| 8 | $020 | getlongbytes(adr, n) | assemble *n* octets big-endian lus à l'**APTR** adr | | O | |
| 9 | $024 | putlongbytes(adr, n, v) | inverse | | O | |
| 10 | $028 | result2(set, v) | set=0 : renvoie pr_Result2 ; set≠0 : renvoie l'ancien et écrit v | lit/écrit | O | C P X R H… |
| 12 | $030 | currco | (valeur) BPTR de la coroutine courante / base de pile BCPL | | O | |
| 13 | $034 | makeglobvec(segarray) | alloue un GV (max des « max » des segments, plancher 15, +50 négatifs), GV[0]=max, reste **non initialisé** ; renvoie BPTR du slot 0 ; 0 si échec | 103 | O | |
| 14 | $038 | taskid() | MsgPort du process courant (APTR) | | O | X R E P |
| 15/16 | $03C/$040 | getbyte(v,i) / putbyte(v,i,b) | octet `i` à partir de BADDR(v) | | O | |
| 17 | $044 | level() | frame de l'appelant (APTR) | | O | X |
| 18 | $048 | longjump(level, label) | reprend à `label` (APTR) dans la frame `level` | | O | X |
| 19 | $04C | getmem(n, flags) | comme getvec avec flags AllocMem (ex. $10001) | 103 | O | S |
| 20 | $050 | aptovec(f, n) | appelle f(v, n) avec v = vecteur de n+1 longs pris sur la pile BCPL | | O | |
| 22 | $058 | sendio(iob, pkt) | lie iob↔pkt (ln_Name = pkt, pkt!0 = iob) puis SendIO | | O | |
| 23–27 | $05C–$06C | createco, deleteco, callco, cowait, resumeco | coroutines (non utilisées) | | D | — |
| 28 | $070 | globin(seg) | §3.2 → −1 / 0 | 111 | O | stub |
| 29 | $074 | getvec(n) | vecteur de n+1 longs (indices 0..n), **non effacé**, MEMF_PUBLIC ; en-tête caché à −4 = taille octets totale ; renvoie BPTR, 0 si échec | 103 | O | P R M H stub |
| 30 | $078 | freevec(v) | v=0 : rien ; en-tête invalide (bits $FF000003) → alerte $07000005 | | O | P R S M H stub |
| 31 | $07C | opendevice(iob, nom, unité, flags) | port de réponse = MsgPort du process ; → −1 succès / 0 | | O | |
| 32 | $080 | closedevice(iob) | | | O | |
| 33 | $084 | createproc(segarray, pile, pri, nom, gv) | pile en **longs** ; nom BSTR ; gv BPTR (5e arg) ; process + pile en un bloc ; hérite ConsoleTask/FileSystemTask/WindowPtr ; démarrage §2.4 ; → **taskid** (0 si échec) | 103 | O | R (NewCLI) |
| 34 | $088 | endtask() | fin du process courant | | D | |
| 35 | $08C | parentdir(lock) | = LVO ParentDir (ACTION_PARENT 29) | handler | O | C P |
| 36 | $090 | setflags(taskid, m) | Signal des bits CTRL (m bit0=C…bit3=F) | | O | |
| 37 | $094 | testflags(m) | **teste et efface** les bits CTRL de m ; → −1 si l'un était posé | | O | X W H |
| 38 | $098 | abort(code) | requester « Software error / Disk corrupt - task held » (retry), puis Alert si code < 0 | | O | |
| 39 | $09C | rootstruct() | BPTR du RootNode | | O | R E S M H |
| 40 | $0A0 | readbytes(adr, n) | Read(input(), APTR adr, n) → octets lus | handler | O | |
| 41 | $0A4 | taskwait() | attend un packet (pr_PktWait si défini, sinon port du process) → BPTR packet | | O | |
| 42 | $0A8 | qpkt(pkt) | envoie le packet à dp_Port, dp_Port := port de réponse du process ; dp_Link ≤ 0 → 0 | 101 | O | |
| 43 | $0AC | writebytes(adr, n) | Write(output(), APTR, n) | handler | O | H |
| 44/45 | $0B0/$0B4 | packstring(v,s) / unpackstring(s,v) | vecteur de caractères ↔ BSTR | | O | |
| 47 | $0BC | delay(ticks) | 1/50 s, via timer.device (= LVO Delay) | | O | W |
| 48 | $0C0 | sendpkt(_, port, type, r1, r2, a1, a2, …) | le packet **est la frame d'arguments** (layout DosPacket : Link, Port, Type, Res1, Res2, Arg1…) ; envoi + attente synchrone ; → dp_Res1 | := dp_Res2 | O | A C P R S H |
| 49 | $0C4 | returnpkt(pkt, r1, r2) | | | O | |
| 51 | $0CC | currentdir(set, lock) | set=0 : renvoie pr_CurrentDir ; sinon renvoie l'ancien et écrit lock | | O | C X R H |
| 52 | $0D0 | requester(l1, l2, l3) | 3 BSTR ; → TRUE = « Retry » | | D | |
| 88 | $160 | callexec(lvo, d0, d1, a0, a1, a2) | appel exec (ex. Forbid −132, Permit −138) → D0 | | O | R E S M |
| 89 | $164 | findsegarray() | pr_SegList (BPTR) | | O | R stub |
| 103 | $19C | calllib(base, lvo, d0, d1, a0, a1) | appel d'une library quelconque → D0 | | O | |
| 105/106 | $1A4/$1A8 | consoletask() / filesystemtask() | pr_ConsoleTask / pr_FileSystemTask | | O | |
| 110 | $1B8 | getlong(b, off) | long à `BADDR(b) + off` (**off en octets**) | | O | P R S H |
| 111 | $1BC | putlong(b, off, v) | écriture idem | | O | P R E H |
| 121 | $1E4 | runcommand(seg, pile, args, len) | §4.3 → code retour, −1 si pile impossible | | O | H |
| 134 | $218 | findcli() | pr_CLI (BPTR) — **dans un GV de commande, ce slot est écrasé par cli_Result2** | | O | stub |
| −18 | −$48 | CreateProc (C) | segarray `[2, V!1, V!2 du parent, seglist]`, entrée directe au code | | O | |

### 8.2 dos / BLIB (segment ROM entrée 2) et utilitaires

| Gl. | Off. | Nom | Arguments → résultat | R2 | Cert. | Cmd |
|---|---|---|---|---|---|---|
| 53 | $0D4 | writet(s, w) | §6.2 | | O | |
| 54/55/56 | $0D8/$0DC/$0E0 | rdch / unrdch / wrch | §5.2, §6.1 | | O | X M H |
| 57 | $0E4 | readwords(v, n) | readbytes en longs ; → longs lus (ou code ≤ 0) | | O | |
| 58 | $0E8 | writewords(v, n) | | | O | |
| 59/60 | $0EC/$0F0 | findinput(nom) / findoutput(nom) | BSTR ; → FileHandle BPTR ou 0 ; requester retry sur erreur disque | handler | O | X M |
| 61/62 | $0F4/$0F8 | selectinput(fh) / selectoutput(fh) | écrit pr_CIS / pr_COS | | O | X M H |
| 63/64 | $0FC/$100 | endread() / endwrite() | endstream(input()) / endstream(output()) (ne resélectionne rien) | | O | X M H |
| 65/66 | $104/$108 | input() / output() | pr_CIS / pr_COS | | O | X R M H |
| 67 | $10C | readn() | §6.4 | 0/−1 | O | |
| 68–74 | $110–$128 | newline, writed, writen, writehex, writeoct, writes, writef | §6 | | O | toutes |
| 75 | $12C | capitalch(c) | a–z → A–Z | | O | X M |
| 76 | $130 | compch(a, b) | capitalch(a) − capitalch(b) | | O | H |
| 77 | $134 | compstring(s1, s2) | comparaison BSTR insensible à la casse ; 0 = égales | | O | E S M H |
| 78 | $138 | rdargs(tpl, argv, n) | §5.4 | 120 | O | toutes |
| 79 | $13C | rditem(v, n) | §5.3 | | O | X H |
| 80 | $140 | findarg(tpl, item) | §5.5 | | O | X M |
| 81 | $144 | load(nom) | LoadSeg BCPL (nom BSTR) → seglist | handler | O | S H |
| 82 | $148 | unloadseg(seg) | gère le cas overlay ($ABCD) ; = LVO UnLoadSeg | | O | S H |
| 85 | $154 | (ajout de nœud device) | utilisée par Mount | | S | M |
| 87 | $15C | waitforchar(fh, µs) | = LVO WaitForChar | | O | |
| 90 | $168 | deleteobj(nom) | ACTION_DELETE_OBJECT (16) | handler | O | X H |
| 93 | $174 | endstream(fh) | = LVO Close (§5.1) | préservé | O | E H |
| 100 | $190 | taskwait (alias de 41) | | | O | |
| 101 | $194 | execute(cmd, in, out) | charge **C:RUN**, sélectionne in/out, **pr_Result2 := cmd (BSTR)**, runcommand(pile 600 longs) | | O | |
| 102 | $198 | deviceproc(nom) | → MsgPort du handler ; Result2 = lock associé (assign/répertoire) ; nom inconnu → 0 et 218 ; volume absent → requester « Please insert volume … in any drive » (retry) ; `NIL:` → 0 | 218 / lock | O | A S M H |
| 104 | $1A0 | fault(code) | code≠0 : exécute **C:FAULT** (pile 400 longs) avec pr_Result2 = code ; si C:FAULT introuvable → `"Error code %N\n"` | := code | O | C P H |
| 107 | $1AC | splitname(préfixe, car, chaîne, pos) | extrait jusqu'à `car` (≤ 30 car.) dans le BSTR préfixe ; → position après `car` ou 0 | | O | M |
| 108 | $1B0 | locateobj(nom) | lock **partagé** (−2) via ACTION_LOCATE_OBJECT (8) | handler | O | P S H |
| 109 | $1B4 | freeobj(lock) | ACTION_FREE_LOCK (15) au fl_Task du lock ; lock 0 → rien ; Result2 préservé | préservé | O | C P X E S H |
| 112 | $1C0 | (démarrage du handler d'un DeviceNode) | | | S | |
| 113 | $1C4 | copydir(lock) | DupLock : ACTION_COPY_DIR (19) ; 0 → 0 | handler | O | R (NewCLI) |
| 114 | $1C8 | errorreq(…) | requester d'erreur disque selon Result2 (protégé, plein, pas DOS…) → TRUE = retry | | D | C P |
| 115 | $1CC | copystring(src, dst) | copie un BSTR (longueur+1 octets) — **ordre (source, destination)** | | O | C P M |
| 123 | $1EC | lock(nom, mode) | appelle locateobj (le mode est ignoré : toujours partagé) | | O | C X |
| 124 | $1F0 | (recherche dans la liste DevInfo) | | | S | M |
| 125 | $1F4 | createdir(nom) | ACTION_CREATE_DIR (22) | handler | O | X |
| 127 | $1FC | (requête timer interne de delay) | | | D | |
| 133 | $214 | cliinit(pkt) | init du CLI initial (startup-sequence…) ; FailLevel 10, **DefaultStack 1000 longs** | | O | |

### 8.3 Globales négatives (ABI « C », segments ROM 2–4)

| Gl. | Off. | Nom | Cert. |
|---|---|---|---|
| −1 | −$04 | Open (nom C) | O |
| −2 | −$08 | copyvec(src, dst, n) : copie n+1 longs (BPTR) | O |
| −3 | −$0C | Read | O |
| −6 | −$18 | Write | O |
| −8 | −$20 | Seek | O |
| −9 … −16 | −$24 … −$40 | DeleteFile, Rename, Lock, Examine, ExNext, Info, CreateDir, CurrentDir | O (câblage LVO) |
| −17 | −$44 | IoErr | O |
| −18 | −$48 | CreateProc | O |
| −19 | −$4C | LoadSeg | O |
| −20 | −$50 | clearvec(v, n) : met à 0 n+1 longs (aussi câblée sur LVO GetPacket) | O |
| −21 | −$54 | chargement de segment **sans requester**, nom **BSTR** → seglist (utilisée par le CLI pour chercher les commandes et par fault pour C:FAULT ; aussi câblée sur LVO QueuePacket) | O (usage) / D (sans requester) |
| −22 … −27 | −$58 … −$6C | DeviceProc, SetComment, SetProtection, DateStamp, IsInteractive, Execute | O (câblage LVO) |
| −26 | −$68 | IsInteractive(fh) : renvoie **brut** fh!1 (fh_Interactive), pas normalisé à −1 | O |
| −31 | −$7C | C-string → BSTR (dest BPTR), longueur plafonnée à 255 | O |
| −32 | −$80 | BSTR → C-string **en place** (décale d'un octet, ajoute NUL), renvoie l'APTR | O |
| −33 | −$84 | sysrequest (entrée C) | O |

Globales définies en ROM mais non caractérisées ici : 21, 46, 50, 86, 91, 94/95 (getword/putword
16 bits, O), 112, 126, 128. Elles ne sont appelées par aucune des commandes cibles sauf 85/124 (Mount). [O]

---

## 9. Q8 — Autres comportements nécessaires aux commandes cibles

### 9.1 Globales minimales par commande [O WB]
(appels par la table GV ; s'ajoutent 28/29/30/89/134 utilisées par le stub)

| Commande | Globales appelées | Champs CLI (GV 134–149) |
|---|---|---|
| AddBuffers | 2, 48, 73, 74, 78, 102 (+ mult) | — |
| CD | 2, 10, 35, 48, 51, 73, 74, 78, 104, 109, 114, 115, 123 (+ 84 privée) | 135 SetName (lecture/écriture du tampon) |
| Path | 2, 10, 14, 29, 30, 35, 48, 73, 74, 78, 104, 108, 109, 110, 111, 114, 115 | 136 CommandDir |
| Wait | 2, 37, 39, 47, 73, 78 (+ mult/div) | — |
| EndCLI | 14, 39, 74, 77, 78, 88, 93, 110 | 141, 142, 144, 145 |
| Execute | 2, 10, 14, 17, 18, 37, 51, 54, 55, 56, 59–66, 70, 73–75, 78–80, 90, 109–111, 123, 125 (+ div) | 142 CurrentInput, 143 CommandFile, 144 |
| Run | −26, 2, 10, 14, 29, 30, 33, 39, 48, 51, 60, 65, 66, 73, 74, 77, 88, 89, 110, 111, 113, 134 (+ div) | — (via packet) |
| Resident | 2, 19, 30, 39, 48, 73, 74, 77, 81, 82, 88, 102, 108, 109 | — |
| Mount | −2, 2, 14, 29, 30, 37, 39, 54–56, 59–64, 68, 73–75, 77, 78, 80, 85, 102, 107, 110, 115, 124 (+ 84 privée) | — |
| Shell-Seg | −20, −8, −1, 10, 14, 29, 30, 34, 37, 39, 43, 48, 49, 51, 54–56, 61–66, 73, 74, 76, 77, 79, 81, 82, 90, 93, 102, 104, 108–111, 121 | — (segment de process) |

### 9.2 Particularités par commande [O WB sauf mention]
- **AddBuffers** : `rdargs("DRIVE/A,BUFFERS/A")`, deviceproc(DRIVE) (« Drive %S not found »),
  conversion décimale locale (« Invalid char '%C' in number »), puis `sendpkt(−, port,
  ACTION_MORE_CACHE = 18, −, −, n)` ; résultat 0 → « Warning: Insufficient memory for buffers ».
  Échecs : stop(20).
- **CD** : template `"DIR"`. Utilise ACTION_EXAMINE_OBJECT (23) via sendpkt, parentdir pour
  reconstruire le nom complet, currentdir(TRUE, lock), freeobj de l'ancien ; écrit le nom dans le
  **tampon BSTR pointé par cli_SetName** (copystring). Messages : « Can't find %S »,
  « %s is a file not a directory », « Unable to find current directory name ». [O/D]
- **Path** : template `",,,,,,,,,,ADD/S,SHOW/S,RESET/S,QUIET/S"`. Met **pr_WindowPtr := −1**
  (process +$B8 via putlong) pendant l'exécution pour supprimer les requesters, puis le restaure.
  Gère la liste `cli_CommandDir` : nœuds `getvec(1)` = `[BPTR suivant, lock]` (le CLI libère ces
  nœuds par freevec + unlock à sa fin). Examine (23) pour refuser les fichiers.
- **Wait** : template `",SEC=SECS/S,MIN=MINS/S,UNTIL/K"` ; boucle de delay() avec testflags(CTRL-C)
  → « **BREAK » ; UNTIL lit l'heure via le RootNode (rn_Time) [D].
- **EndCLI** : `rdargs("")` ; **stdin.fh_End := 0** (EOF forcé, que le CLI ne restaure pas) ; si
  CurrentInput ≠ StandardInput : ferme le script et CurrentInput := StandardInput ;
  **cli_Background := TRUE** ; si cli_Interactive : `"CLI process %N ending\n"` ; sous Forbid,
  décrémente le compteur d'usage du résident « CLI » s'il existe et est > 0. Le CLI sort alors à la
  lecture suivante (§4.5).
- **Execute** : lit le nom du script par **rditem** (pas rdargs) ; ouvre le fichier (findinput),
  sinon réessaie relativement à `S:` ; « Can't open %S ».
  - Script **sans directive** (premier caractère non blanc ≠ `.`) et pas d'imbrication
    (CurrentInput = StandardInput) : remet le caractère, **cli_CurrentInput := le script**, stop(0).
    Le CLI exécute alors les lignes du script. Les paramètres de la ligne Execute sont ignorés.
  - Sinon : traite les directives `.KEY/.K`, `.DEFAULT/.DEF`, `.BRA`, `.KET`, `.DOLLAR`, `.DOT`
    (délimiteurs par défaut `<` `>` `$` `.`), écrit le script substitué dans un fichier temporaire
    `T:Command-<n>-T<m>` (repli `:T/Command-0-Tnn`), recopie le reste du script englobant en cas
    d'imbrication, puis CurrentInput := temporaire et **cli_CommandFile := son nom** (supprimé par
    le CLI à l'EOF). Erreurs internes gérées par level()/longjump. [O/D]
- **Run** (protocole de création d'un CLI de fond) :
  1. Texte de commande : si pr_Result2 ≠ 0 à l'entrée, c'est un **BSTR de commande** (cas de la
     globale 101 / LVO Execute) ; sinon le **tampon d'entrée injecté** (fh_Buf[0..fh_End−1]) suivi
     d'un `\n`, placé dans un FileHandle mémoire construit à la main (getvec ; `fh_Buf` = données
     internes, `fh_Pos` = 0, `fh_End` = longueur+1, aucune routine).
  2. Segarray neuf `getvec(4)` : `[4, V!1, V!2 du parent, 0, CLI]` où CLI = segment du résident
     nommé **"CLI"** s'il existe dans la liste Resident (son compteur d'usage peut être
     incrémenté, jamais s'il vaut −1 = système ; condition exacte non élucidée [D]), sinon
     `rn_ConsoleSegment` (RootNode +4).
  3. Sous Forbid : premier slot libre de `rn_TaskArray` (`[0]` = taille) ; échec → « Unable to
     create background process ».
  4. createproc(segarray, **800 longs**, pri du parent, `"Background CLI"`, **GV du parent**
     = pr_GlobVec du CLI appelant) ; `rn_TaskArray[slot]` := taskid ; `pr_TaskNum` du nouveau
     process (+$8C) := slot. Permit.
  5. **Packet de démarrage** (sendpkt synchrone) : `dp_Type` = **adresse machine d'une routine
     d'init BCPL** contenue dans Run ; Arg1 = pr_CLI du parent, Arg2 = input(), Arg3 = output(),
     Arg4 = FileHandle des commandes, Arg5 = DupLock du répertoire courant (si CLI parent), Arg6 =
     BSTR de commande initial (ou 0).
  6. Côté nouveau CLI : `start(pkt)` appelle `init = pkt.dp_Type` (ou GV[133] si pkt = 0) avec
     pkt ; si `init` renvoie une valeur **> 0**, le CLI l'appelle comme une fonction avec
     pr_Result2 en argument (Run renvoie ainsi `qpkt` après avoir mis pkt dans Result2 → réponse
     **immédiate**, Run continue) ; une valeur **< 0** = drapeaux, le packet n'est rendu qu'à la
     **fin** du CLI (cas Execute() synchrone). [O ROM + WB, D pour l'interprétation des bits]
  7. Run affiche `"[CLI %N]\n"` (si pas de BSTR initial) puis stop(0).
  Le CLI de fond lit ses commandes dans le FileHandle mémoire ; à son EOF, étant Background, il
  se termine.
- **Resident** : liste des segments résidents = chaîne partant de **DosInfo +$10** (DosInfo = BADDR
  de rn_Info, RootNode +$18). Nœud : `!0` BPTR suivant, `!1` compteur d'usage (−1 = SYSTEM), `!2`
  seglist, `!3…` nom BSTR (octet +12). Exige le bit de protection **p** (« Pure bit not set »).
  Template `"Name,File,Remove/S,Add/S,Replace/S,Pure/S,SYSTEM/S"`. [O/D]
- **Mount** : lit `devs:mountlist` (template `"DEVICE/A,FROM/K"`) par findinput/rdch ; mots-clés
  `Handler, StackSize, Priority, GlobVec, FileSystem, Startup, …` ; crée DeviceNode/environnement.
  Non analysé en détail. [S]
- **Shell-Seg** : segment BCPL d'**un seul hunk sans stub** (globale 1, max 133) ; il s'installe
  comme résident « CLI » et est utilisé comme entrée 4 du segarray (comme le CLI ROM) ; il gère
  lui-même la liste Resident et appelle runcommand (121). Partage le GV du CLI. [O/D]

### 9.3 Contraintes d'interopérabilité pour notre ROM [D]
- Nos FileHandles doivent respecter le layout §5.1 (tampon BPTR, index octets) car le CLI y
  **injecte** les arguments et les commandes (EndCLI, Run) écrivent directement `fh_End`/`fh_Buf`.
  Si nos rdch/wrch BCPL sont natifs, ils doivent appliquer exactement les règles §5.2/§6.1 sur ces
  champs ; si les routines fh_Funcs/Func2/Func3 sont appelées, elles doivent être **appelables
  en BCPL** (entrée A4, retour par A6).
- Les FileHandles et nœuds alloués par les commandes le sont par getvec et libérés par freevec
  (et réciproquement) : l'en-tête getvec (taille à −4) doit être compatible avec tous les blocs
  échangés (FileHandle, nœuds de chemin, segarray, GV).
- Le runtime doit exister sous forme de **segments au format §3.1** listés dans le segarray de
  chaque CLI (entrées 1..V!0), car c'est la globin de la commande qui les installe dans son GV
  privé.
- `cli_DefaultStack` par défaut = 1000 longs ; le stub prend sa pile BCPL **dans** cette pile.

---

## 10. Divergences avec la table publique (Kinnersley/AROS)

| Point | Table publique | V34 observé |
|---|---|---|
| Frame −4 | « ancien A4 » | A4 **de l'appelé** ; A4 restauré depuis la frame de l'appelant [O] |
| Global 1 Start | (commenté chez AROS) | **confirmé** : start(D1) [O] |
| $0C/$10/$14 | multiply/divide/mod | confirmé (3/4/5) [O] |
| $48 (18) | longcall | **longjump(level, label)** [O] |
| $50 (20) | longjump | **aptovec(f, n)** [O] |
| $1A0 (104) | writeErr | **fault(code)** : lance C:FAULT, repli `"Error code %N"` [O] |
| $13C (79) | rditem (K : rdline) | rditem confirmé [O] |
| $140 (80) | subString (K : parseline) | **findarg(template, item)** [O] |
| $1E4 (121) | runCommand (K : runloaded) | confirmé, convention §4.3 [O] |
| $204 (129) | DOSBase (valeur) | **inexistant en V34** : aucune référence dans la ROM ni dans les commandes [O] |
| $218 (134) | findCLI | confirmé dans dl_GV ; **dans le GV d'une commande, 134..149 = copie de la CLI** [O] |
| −$08 (−2) | copyvec (K : strncpy) | copyvec (n+1 longs) [O] |
| −$50 (−20) | clearvec (K : clearmem) | clearvec ; **aussi LVO GetPacket** [O] |
| −$54 (−21) | NoReqLoadSeg (K : queuepkt) | chargement de segment (nom BSTR) — NoReqLoadSeg confirmé par l'usage ; **aussi LVO QueuePacket** [O/D] |
| −$58 (−22) | DeviceProc | confirmé [O] |
| Taille GV | — | dl_GV : 0..150 (+50 négatifs) ; commande : 0..max(149, max cmd) (+50) [O] |
| Slots non définis | — | dl_GV : indéfinis ; commande : $474C0001+2n [O] |
| Pile BCPL | « distincte de la pile C » (dos-v34-spec §4) | **même bloc** que la pile 68000 ; frames BCPL depuis le bas, A7 depuis le haut [O] — à corriger dans dos-v34-spec.md |

---

## 11. Vecteurs de test (observables)

1. `Failat 15` dans un CLI : après la commande, `cli_FailLevel` (CLI +$14) = 15 (écrit via GV[139]
   puis recopie du stub). [D]
2. Commande `Echo "a b"` (BCPL) lancée par le CLI : à l'entrée du stub, A0 pointe sur `"a b"\n`
   (avec les guillemets), D0 = 6 ; input().fh_Pos = 0, fh_End = 6. [D à partir de §4.2]
3. rdargs(`"DRIVE/A,BUFFERS/A"`, v, 20) sur l'entrée `DF0: 30\n` → v!0 = BSTR "DF0:", v!1 = BSTR
   "30", résultat ≠ 0, ligne consommée jusqu'au `\n` inclus. Sur `DF0:\n` → 0, Result2 = 120.
4. rdargs(`",SEC=SECS/S,MIN=MINS/S,UNTIL/K"`, v, n) sur `5 MINS\n` → v!0 = "5", v!1 = 0,
   v!2 = −1, v!3 = 0.
5. writef(`"%X4|%I5|%T8|%%|%$%N"`, 255, −42, "ab", 7, 9) → `00FF|  -42|ab      |%|9`.
6. Une globale non définie dans un GV de commande contient $474C0001+2n (ex. GV[7], définie par
   aucun segment ROM, vaut $474C000F dans le GV de toute commande qui ne la définit pas).
7. getvec(9) → bloc de 44 octets dont le long caché (BADDR(v)−4) vaut 44.
8. Après `EndCLI` dans le CLI initial (interactif) : message `"CLI process 1 ending"`, puis le
   process CLI se termine à la lecture suivante.

---

## 13. Compléments (globales 85/124/112, c:Mount, démarrage des handlers et des CLI de fond)

Layout DeviceNode (DevInfo) V34 utilisé ci-dessous, en longs (offset octet) [O ROM + WB] :
`!0` dn_Next ($00) · `!1` dn_Type ($04, 0 = DLT_DEVICE, 2 = volume) · `!2` dn_Task ($08) ·
`!3` dn_Lock ($0C) · `!4` dn_Handler ($10, BSTR) · `!5` dn_StackSize ($14) · `!6` dn_Priority ($18) ·
`!7` dn_Startup ($1C) · `!8` dn_SegList ($20) · `!9` dn_GlobalVec ($24) · `!10` dn_Name ($28, BSTR).
La liste des nœuds part de **DosInfo +$04** (di_DevInfo ; DosInfo = BADDR de rn_Info, RootNode +$18).

### 13.1 Globale 85 (GV +$154) — `makedevnode(nom)` [O ROM]
- **Argument** : D1 = BSTR du nom **sans `:`** (Mount le passe en majuscules).
- Alloue le nœud par **getvec(10)** (11 longs, **non effacé**) et une copie du nom par getmem
  effacé de `(longueur+1)/4` longs (+1 implicite), donc la copie est suivie d'au moins un octet
  NUL. Copie le BSTR (copystring).
- Initialise : dn_Name := la copie ; **dn_Type, dn_Task, dn_Lock, dn_Handler, dn_StackSize,
  dn_Priority, dn_Startup, dn_SegList := 0**. **dn_GlobalVec n'est pas initialisé** (contenu
  indéfini : l'appelant doit l'écrire).
- Sous Forbid/Permit : insère le nœud **en tête** de la liste di_DevInfo.
- **Résultat** : BPTR du nœud ; 0 si une allocation échoue (les deux blocs sont alors libérés,
  Result2 = 103 laissé par getvec). Aucun autre effet sur Result2.

### 13.2 Globale 124 (GV +$1F0) — `finddevinfo(nom)` [O ROM]
- **Argument** : D1 = BSTR du nom sans `:`. Comparaison **insensible à la casse** (compstring) avec
  dn_Name de chaque nœud, sous Forbid/Permit.
- **Résultat** : le **premier nœud de type DLT_DEVICE (0)** portant ce nom ; à défaut, le
  **dernier** nœud de même nom d'un autre type (volume, assign) ; 0 si aucun. Result2 inchangé.
- (deviceproc utilise la même recherche en mode « premier nœud de ce nom, quel que soit le type ».)

### 13.3 Globale 112 (GV +$1C0) — `starthandler(nœud, nom)` [O ROM]
Appelée par **deviceproc** (globale 102) quand le nœud trouvé est de type 0, a dn_Lock = 0 et
dn_Task = 0. Arguments : D1 = BPTR du DeviceNode, D2 = **le BSTR complet passé à deviceproc**
(ex. `NEWCON:0/0/640/200/Titre` pour un Open). Résultat : MsgPort du handler, ou 0.
1. **Segment** : si dn_SegList = 0, charge dn_Handler par la globale 81 (load, nom BSTR) ; échec →
   0 (Result2 = erreur du chargement). Le segment est **mémorisé dans dn_SegList** (chargé une
   seule fois, jamais déchargé ici).
2. **dn_GlobalVec = −1 → handler C** : CreateProc ABI C (globale −18) avec nom = texte de
   dn_Name **comme chaîne C** (BADDR+1, terminée par le NUL garanti par 13.1), pri = dn_Priority,
   seglist = dn_SegList, pile = dn_StackSize **en octets**. Entrée directe au code du premier
   segment (pas de globin).
3. **Sinon → handler BCPL** : construit un segarray `getvec(3)` = `[3, V!1, V!2 du process
   appelant, dn_SegList]` (noyau + dos + handler) ; GV = dn_GlobalVec s'il est non nul (**GV
   existant partagé**, BPTR), sinon **makeglobvec(segarray)** (globale 13 : GV neuf dimensionné sur
   les « max » des segments, plancher 15, non initialisé hors globin) ; puis **createproc(segarray,
   dn_StackSize en longs, dn_Priority, dn_Name BSTR, GV)**. Le process démarre selon §2.4 : globin
   de V!1..V!3 dans ce GV, puis attente du packet de démarrage.
4. Échec de création → libère le segarray, renvoie 0. Succès → **Result2 := dn_Lock**.
5. **Packet de démarrage** (sendpkt synchrone vers le port créé) : **Arg1 = BSTR complet du nom**
   (D2), **Arg2 = dn_Startup**, **Arg3 = BPTR du DeviceNode** ; dp_Res2 = GV (cas BCPL) ;
   **dp_Type, dp_Res1 et le reste ne sont pas initialisés** par la ROM (valeurs résiduelles de
   la frame : un handler ne doit pas les interpréter). Si le handler répond avec Res1 ≠ 0 :
   Result2 := dn_Lock et renvoie le port ; sinon renvoie 0.
6. **dn_Task n'est jamais écrit par dos** : c'est au handler de le renseigner (via Arg3) s'il veut
   rester partagé. Sinon chaque deviceproc relance un nouveau process (comportement de type
   CON:/NEWCON:, une fenêtre par Open). [O pour l'absence d'écriture, D pour la conséquence]

> Asymétrie d'unités observée : **dn_StackSize est en octets pour un handler C mais en longs
> (×4) pour un handler BCPL**. [O]

### 13.4 c:Mount — déroulé pour `mount newcon:` [O WB, D pour la lecture du fichier]
1. `rdargs("DEVICE/A,FROM/K")`. Fichier = FROM, sinon **`devs:mountlist`** (findinput ; échec →
   « Could not open %S for input »).
2. Lecture du mountlist par rdch : commentaires `/* */`, recherche de l'entrée dont le nom égale
   DEVICE (insensible à la casse), puis lecture des affectations `Mot-clé = valeur` jusqu'à `#`.
   Mots-clés reconnus par findarg sur le gabarit
   `",BlockSize,,Surfaces,,BlocksPerTrack,Reserved,PreAlloc,Interleave,LowCyl,HighCyl,Buffers,
   BufMemType,MaxTransfer,Mask,BootPri,DosType,Device,Unit,Flags,Handler,StackSize,Priority,
   GlobVec,FileSystem,Startup,Mount,Baud,Controlr"` (index = position, Handler = 20, StackSize =
   21, Priority = 22, GlobVec = 23, FileSystem = 24, Startup = 25).
3. Valeurs par défaut des champs absents (marqueur interne « non fourni » remplacé) :
   **StackSize = 600, Priority = 10, GlobVec = −3** (= « GV du process appelant »), Handler = 0,
   Startup = 0, FileSystem = 0, Mount = 0 ; pour les FS : BlockSize = 512, Reserved = 2,
   Interleave = 0, Buffers = 5, BufMemType = 3, MaxTransfer = $7FFFFFFF, Mask = $FFFFFFFF,
   DosType = `'DOS\0'`, Baud = 1200, Unit/Flags/LowCyl/HighCyl/PreAlloc… = 0.
4. Création du nœud : extrait le nom avant `:` (splitname, globale 107), **le met en
   majuscules**, `finddevinfo` (124) → déjà présent ⇒ « Device %S already mounted », fin.
   Sinon `makedevnode` (85) (échec ⇒ « Unable to create new node ») ; puis dn_Lock = dn_Type =
   dn_Task = 0, **dn_StackSize = StackSize, dn_Priority = Priority**.
5. **Entrée sans `Device =` (cas NEWCON)** : dn_SegList = 0, **dn_Startup = valeur Startup**
   (0 ici), **dn_Handler = BSTR de Handler** (`L:Newcon-Handler`), **dn_GlobalVec** déduit de
   GlobVec : −3 (défaut) ou 2 → **BPTR du `pr_GlobVec` du process Mount** (= GV du CLI, donc
   `dl_GV` pour le CLI ROM) ; 0 → 0 ; toute autre valeur (ex. −1) → **−1**.
   Pour NEWCON (mountlist WB : `Handler = L:Newcon-Handler`, `Priority = 5`, `StackSize = 1000`,
   pas de GlobVec) : **dn_Handler = "L:Newcon-Handler", dn_StackSize = 1000, dn_Priority = 5,
   dn_Startup = 0, dn_SegList = 0, dn_GlobalVec = BPTR(GV du CLI)**, dn_Type = 0, dn_Name =
   "NEWCON", inséré en tête de di_DevInfo. Mount **ne charge pas** le handler (le mot-clé
   `Mount =` n'a pas été examiné).
6. **Entrée avec `Device =` (système de fichiers)** : construit un FileSysStartupMsg (unité,
   nom de device, environnement copié depuis les champs numériques) ; **dn_Startup = BPTR de ce
   message** ; si FileSystem absent → **dn_SegList = rn_FileHandlerSegment** (RootNode +$1C, le FS
   ROM) et dn_Handler = 0, sinon dn_SegList = 0 et dn_Handler = FileSystem ; dn_GlobalVec déduit
   de GlobVec avec « GV appelant » remplacé par **0** (−3/2/0 → 0 ⇒ dos construira un GV neuf ;
   autre → −1). [O pour les affectations, D pour le détail du FSSM]
7. Le binaire `l:Newcon-Handler` du disque est un **segment BCPL d'un seul hunk** (globale 1 à
   l'offset 4, max 111, pas de stub) — cohérent avec un démarrage en BCPL sur GV partagé. [O WB]

Premier accès à `NEWCON:` (ex. Open("NEWCON:0/0/640/100/x")) : open BCPL → deviceproc → nœud
DLT_DEVICE sans tâche ni lock → **globale 112** (13.3) : chargement de `L:Newcon-Handler` dans
dn_SegList, segarray `[3, noyau, dos, handler]`, **createproc avec le GV partagé** (dn_GlobalVec ≠
0, ≠ −1), pile 1000 longs, pri 5, nom "NEWCON" ; globin du noyau, de dos et du handler **dans ce
GV partagé** (le handler y écrase la globale 1, sans effet sur les process déjà démarrés [D]) ;
packet de démarrage (Arg1 = nom complet, Arg2 = 0, Arg3 = nœud) ; à la réponse, deviceproc
renvoie le port et l'open poursuit par ACTION_FINDINPUT/OUTPUT.

### 13.5 Démarrage d'un CLI (ROM ou Shell-Seg en entrée 4 du segarray) [O ROM + WB]
- createproc → démarrage §2.4 : pile remplie de $ABABABAB, globin de V!1..V!0 (noyau, dos,
  [cliinit ou 0], CLI) dans le GV fourni, **taskwait** du packet, puis **start(pkt)**.
- `start(pkt)` du CLI ROM **et** de Shell-Seg (même comportement observé) : la fonction d'init est
  **`pkt.dp_Type`** (adresse machine d'une routine BCPL), ou **GV[133] (cliinit)** si pkt = 0. La
  CLI est d'abord allouée **dans la frame du CLI** (effacée, tampons Prompt/CommandName/
  CommandFile/SetName internes) et rangée dans pr_CLI ; puis `r = init(pkt)` :
  - `r > 0` : `r` est une routine, appelée avec **pr_Result2** comme argument (Run : init met pkt
    dans Result2 et renvoie l'adresse de `qpkt` ⇒ **réponse immédiate** au créateur) ;
  - `r ≤ 0` : drapeaux conservés ; le packet est **rendu à la fin** du CLI (returnpkt avec
    cli_Result2) ; les bits 0/1 de `r` décident des endread/endwrite finaux [D].
- Ce que l'init de Run (routine passée dans dp_Type) consomme du packet : **Arg1** = CLI parent
  (copie de Prompt, CommandDir, DefaultStack, FailLevel… [D]), **Arg2/Arg3** = entrée/sortie du
  parent (choix de la sortie : `*` si la sortie du parent est sa StandardOutput, sinon autre flux
  [D]), **Arg4** = FileHandle des commandes ⇒ **cli_StandardInput = cli_CurrentInput = Arg4**,
  **Arg5** = lock dupliqué ⇒ répertoire courant, **Arg6** = BSTR de commande (0 = lancement par
  Run depuis un CLI ⇒ réponse immédiate). Elle remet à 0 l'entrée 3 du segarray du nouveau
  process. [O pour les champs lus, D pour la sémantique fine]
- Un CLI de fond dont l'entrée (FileHandle mémoire, routines nulles) s'épuise reçoit EOF ; étant
  Background il se termine (§4.5), libère son slot de rn_TaskArray et sort du process.

---

## 12. Relecture clean-room

Je certifie, après relecture intégrale de ce document, que :
- il ne contient **aucune suite d'instructions 68000 recopiée ou paraphrasée ligne à ligne**,
  ni de la ROM ni des binaires du disque Workbench, aucun extrait de désassemblage, aucun opcode
  ni encodage d'instruction ;
- les descriptions de routines sont formulées comme des **spécifications fonctionnelles**
  (entrées, sorties, effets, ordre des effets observables), sans pseudo-code calqué sur la
  structure du code d'origine (boucles, branches et registres de travail internes ne sont pas
  décrits) ;
- les seules valeurs reprises sont des **éléments d'ABI et d'interopérabilité** : numéros et
  offsets de globales, layouts (frame, GV, FileHandle, CLI, segarray, hunk BCPL, nœuds de liste),
  conventions de registres, constantes (codes d'action packets, codes d'erreur, tailles de
  tampons/piles, valeur du marqueur de globale non définie), chaînes de messages et templates
  (nécessaires à la compatibilité de sortie), et adresses ROM à titre de repère d'analyse ;
- la ROM n'a été ni modifiée ni copiée ; seules des extractions temporaires des fichiers du
  disque Workbench ont été faites dans le répertoire scratch de session.
