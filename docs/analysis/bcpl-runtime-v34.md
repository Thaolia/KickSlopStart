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
> constantes. **Aucune suite d'instructions n'est reproduite ni paraphrasée**, et aucune adresse ROM n'est
> citée (retirées le 2026-10-29).

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
- Segarray ROM : `V!0 = 4`, mais **7 entrées** utiles :
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
  préservé). Précision : vidage, libération du tampon et ACTION_END sont le fait de la routine
  **fh_Func3** ; endstream ne l'appelle que si elle est non nulle, puis fait toujours le freevec
  du FileHandle (cas du FileHandle mémoire de Run, §13.6.4). [O ROM]
  ⇒ les FileHandles doivent être des blocs **getvec** (en-tête de taille à −4). [O]

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
| 112 | $1C0 | starthandler(nœud, nom) (§13.3) | | | O | |
| 113 | $1C4 | copydir(lock) | DupLock : ACTION_COPY_DIR (19) ; 0 → 0 | handler | O | R (NewCLI) |
| 114 | $1C8 | errorreq(…) | requester d'erreur disque selon Result2 (protégé, plein, pas DOS…) → TRUE = retry | | D | C P |
| 115 | $1CC | copystring(src, dst) | copie un BSTR (longueur+1 octets) — **ordre (source, destination)** | | O | C P M |
| 123 | $1EC | lock(nom, mode) | appelle locateobj (le mode est ignoré : toujours partagé) | | O | C X |
| 124 | $1F0 | (recherche dans la liste DevInfo) | | | S | M |
| 125 | $1F4 | createdir(nom) | ACTION_CREATE_DIR (22) | handler | O | X |
| 127 | $1FC | timerio(cmd, iob, secs, µs) — requête timer.device synchrone (§8.4) | | | O | |
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

Globales définies en ROM et caractérisées plus loin : 21, 46, 50, 86, 91, 94/95, 126, 127, 128 →
§8.4 ; 85/124/112 → §13. Aucune n'est appelée par les commandes cibles de §9 sauf 85/124 (Mount) ;
**C:Date appelle 86 et 128** (§8.4.3). [O]

### 8.4 Globales 21–128 et C:Date (2026-10-21)

Sources : ROM `kick34005.A500` (tables globin des segments du segarray, §3.1) et `c:Date`,
`c:SetClock` du disque Workbench 1.3.3. Contrats uniquement.

#### 8.4.1 Où vivent ces globales [O ROM]

| Gl. | Off. | Segment porteur (segarray ROM) |
|---|---|---|
| 21, 46, 86, 91, 127, 128, −25 | $054, $0B8, $158, $16C, $1FC, $200, −$64 | entrée 2 (dos « BLIB ») |
| 94, 95, 126 | $178, $17C, $1F8 | entrée 1, 2ᵉ segment de la chaîne |
| 50 | $0C8 | entrée 1, 3ᵉ segment (avec −33 sysrequest et 52 requester) |
| 34 (rappel) | $088 | entrée 1, 1ᵉʳ segment |

Ni 83 ni 84 ne sont définies en ROM (84 est fournie par C:Date elle-même). La globale **92** n'est
dans aucune table globin : c'est une **donnée** (IntuitionBase, APTR) écrite par `cliinit` (133). [O]

#### 8.4.2 Contrats [O ROM sauf mention]

Unités comme en §8 ; « vecteur datestamp » = 3 longs consécutifs **[jours, minutes, ticks]**
(jours depuis le 1-jan-1978, minutes depuis minuit 0..1439, ticks de 1/50 s dans la minute 0..2999).

- **128 `setdatstamp(v)`** — D1 = **BPTR** d'un vecteur datestamp. Règle l'heure système :
  1. secondes = v!0 × 86400 + v!1 × 60 + v!2 / 50 ; microsecondes = (v!2 mod 50) × 20000
     (arithmétique 32 bits signée, **aucune validation de plage**, v n'est pas modifié) ;
  2. **Forbid**, puis requête timer **TR_SETSYSTIME (11)** via la globale 127 (secondes,
     microsecondes) sur un vecteur IORequest **local à sa frame** ;
  3. relit l'heure par la globale **86** sur ce même vecteur local — ce qui **rafraîchit
     `rn_Time` du RootNode** (cf. −25 ci-dessous) ;
  4. **Permit**.
  Résultat D1 : **non significatif** (résidu de l'appel Permit ; Date l'ignore). Result2 inchangé.
  Aucun packet DOS, aucun accès à l'horloge sauvegardée (RTC $DC0000) : écrire la RTC est le
  rôle de `SetClock save`. Appelants : C:Date **et le validateur de la ROM** (réglage d'heure au montage de
  DF0:, cf. [boot-clock-v34.md](boot-clock-v34.md) — correction de la mention « la ROM ne l'appelle pas »).
- **86 `datstamp(v)`** — D1 = BPTR d'un vecteur de 3 longs ; appelle l'adaptateur C **−25
  (DateStamp)** sur `BADDR(v)` ; **renvoie v** (le BPTR reçu). Appelants : C:Date et le file
  system (entrée 6).
- **−25 `DateStamp(ds)`** (LVO −192, ABI C : D1 = APTR de 3 longs) :
  1. requête timer **TR_GETSYSTIME (10)** via 127 → (secondes, microsecondes) de l'heure système ;
  2. **Forbid** ; calcule jours = s / 86400, minutes = (s / 60) mod 1440,
     ticks = (s mod 60) × 50 + µs / 20000 ;
  3. écrit ces 3 valeurs **dans `rn_Time` du RootNode** (RootNode +$08 jours, +$0C minutes,
     +$10 ticks), puis les recopie dans ds[0], ds[1], ds[2] ;
  4. **Permit**.
  Le D0 rendu à un appelant C n'est **pas** ds (résidu de Permit) — divergence avec l'AutoDoc ;
  ne pas s'en servir. `rn_Time` n'est donc qu'un **cache** mis à jour à chaque DateStamp ;
  la source de vérité est l'heure système de timer.device. [O]
- **127 `timerio(cmd, iob, secs, micros)`** — requête synchrone à timer.device :
  `iob` = BPTR d'un vecteur **d'au moins 12 longs (48 octets)** fourni par l'appelant (en pratique
  un vecteur de sa frame BCPL). Effets dans l'ordre : `opendevice(iob, "timer.device", unité 0 =
  UNIT_MICROHZ, flags 0)` (globale 31 : ln_Succ/ln_Pred := 0, ReplyPort = MsgPort du process,
  mn_Length = 12 ; **résultat non testé**) ; `setio` (globale 6) : io_Command := cmd,
  io_Length (+$24 = **tv_micro**) := micros, io_Data (+$28) et io_Offset (+$2C) reçoivent des
  valeurs **résiduelles** (d'où l'exigence de 48 octets) ; +$20 (**tv_secs**) := secs ;
  **doio** (21) ; **closedevice** (32). Résultat : non significatif. Au retour, +$20/+$24 contiennent
  la réponse du timer. Le device est **ouvert et fermé à chaque appel**. Commandes utilisées :
  **9 TR_ADDREQUEST** (delay, globale 47 : secs = ticks/50, µs = (ticks mod 50) × 20000),
  **10 TR_GETSYSTIME** (−25), **11 TR_SETSYSTIME** (128).
- **21 `doio(iob)`** — D1 = BPTR d'une IORequest ; exec **DoIO** (−456) ; → **io_Error** (octet +$1F,
  non signé). Appelants : 127, console-handler, validateur.
- **126 `compstamp(a, b)`** — deux BPTR de vecteurs datestamp ; comparaison lexicographique signée
  (jours, puis minutes, puis ticks) ; → **0** si égaux, **+1 si a est plus récent que b**, **−1 si a
  est plus ancien**. Pas d'effet de bord. Appelant : validateur (entrée 7).
- **94 `getword(v, i)`** / **95 `putword(v, i, w)`** — mot 16 bits (non signé à la lecture) à
  `BADDR(v) + 2·i`. [O]
- **46 `unloadseg(seg)` + `endtask()`** — `unloadseg(seg)` (82) puis endtask (34) ; ne revient pas ;
  si l'endtask revenait : `abort($87000002)`. Aucun appelant trouvé dans la ROM. [O]
- **34 `endtask()`** (complément de §8.1) — **arguments ignorés** : freevec de `pr_SegList` (le
  segarray) ; si `pr_GlobVec` ≠ `dl_GV`, freevec du GV (bloc complet, 50 slots négatifs compris) ;
  puis `RemTask(0)`. [O]
- **50 `openwindow(gauche, haut, largeur, hauteur, titre)`** — intuition **OpenWindow** (−204) avec
  pour base la **globale 92** (IntuitionBase). NewWindow : LeftEdge/TopEdge/Width/Height = les 4
  premiers arguments (mots), DetailPen = BlockPen = −1, IDCMPFlags = 0, Flags = **$00021007**
  (WINDOWSIZING | WINDOWDRAG | WINDOWDEPTH | ACTIVATE | NOCAREREFRESH, smart refresh), pas de
  gadget ni de checkmark, Title = `BADDR(5ᵉ arg)` (texte attendu terminé par NUL), Screen/BitMap =
  0, MinWidth 120, MinHeight 50, MaxWidth = MaxHeight = $FFFF, Type = WBENCHSCREEN (1).
  → **Window\*** (APTR) ou 0. Appelant : console-handler (entrée 5). [O]
- **91 `renameobj(ancien, nouveau)`** — deux BSTR. `deviceproc` sur chacun (Result2 de chaque appel
  = lock de référence) ; l'un des deux à 0 → **0** ; ports différents → **Result2 := 215**
  (ERROR_RENAME_ACROSS_DEVICES) et **0** ; sinon `sendpkt` **ACTION_RENAME_OBJECT (17)** avec
  Arg1 = lock ancien, Arg2 = BSTR ancien, Arg3 = lock nouveau, Arg4 = BSTR nouveau → dp_Res1.
  Si Res1 = 0 : `errorreq` (114) ; **s'il renvoie 0 l'opération complète est relancée**, sinon
  renvoie 0. (Sens du booléen de 114 observé ici : 0 = recommencer — à rapprocher de la ligne 114
  de §8.2, marquée [D].) Appelant : l'adaptateur **−10 (Rename, LVO −78)**. [O]
- **112** : voir §13.3.

#### 8.4.3 C:Date (Workbench 1.3.3) [O WB]

Fichier 4208 octets (md5 `16b1601e143f86663d2ec14151d6951d`) : hunk 0 = stub standard (§3.3,
md5 `d6b59e0e…`), hunk 1 = module BCPL de 960 longs, max = **152**, paires globin
**(84, $4D4)** et **(1, $44)**. Commande BCPL ordinaire : seules 86 et 128 la distinguent des
commandes de §9.

**Globales utilisées par le module** (liste exhaustive des accès `GV` du hunk 1) :

| Gl. | Usage | Gl. | Usage |
|---|---|---|---|
| 1 | start (définie par Date) | 74 | writef |
| 2 | stop(20) sur erreur | 78 | rdargs (vecteur 50 longs) |
| 10 | result2 (lecture / écriture d'un drapeau, cf. ci-dessous) | 80 | findarg |
| 60 | findoutput (argument TO) | **84** | restauration de la sortie (définie par Date) |
| 62 | selectoutput | **86** | **datstamp** |
| 64 | endwrite | **128** | **setdatstamp** |
| 66 | output | 150 | statique : flux de sortie initial |
| 73 | writes | 151, 152 | statiques : chaîne d'heure analysée, index de lecture |

Plus, via le stub : 28, 29, 30, 89, 134 et la copie CLI 134..149. Arithmétique A5+$10/+$12.
**Aucun accès direct** à timer.device, au RootNode ni à la RTC ; aucune globale 126/127.

**Comportement** :
1. G150 := output() ; `rdargs("TIME,DATE,TO=VER/K")`. Échec → « usage » : trois `writes`
   (`***Bad args \n`, `- use DD-MMM-YY or <dayname> or yesterday etc. to set date\n`,
   `      HH:MM:SS OR HH:MM to set time\n`), globale 84, **stop(20)**.
2. TO présent : `findoutput(TO)` ; 0 → `writef("***Can't open %S\n", TO)` puis stop(20) ;
   sinon `selectoutput`.
3. **Ni TIME ni DATE** → lecture : `datstamp(v)` (vecteur local), conversion locale en trois
   chaînes, puis `writef("%S %S %S\n", jour_de_semaine, date, heure)` (date `DD-MMM-YY`, heure
   `HH:MM:SS`, jour = `Sunday…Saturday` indexé par jours mod 7, le 1-jan-1978 étant un dimanche ;
   chaînes de repli `<unset>` / `<invalid>` présentes).
4. Sinon, **argv!0 (TIME) puis argv!1 (DATE)** sont traités dans cet ordre, chacun selon son
   contenu et non sa position : présence d'un `:` → **réglage d'heure**, sinon **réglage de date**.
   - **Heure** `HH:MM[:SS]` : HH **obligatoire** ∈ 0..23 ; MM et SS ∈ 0..59 (MM/SS absents → 0 ;
     HH absent ou toute valeur hors plage → usage + stop(20)). `datstamp(w)` (heure courante),
     puis w!1 := HH×60+MM, w!2 := SS×50, **w!0 conservé**, puis **`setdatstamp(w)`** (128).
   - **Date** : à l'entrée de l'analyse `result2` est mis à 0. Formes : `DD-MMM-YY` (mois
     `Jan…Dec` ; **YY < 78 → 20YY, sinon 19YY** ; jours comptés depuis 1978 avec années
     bissextiles = divisibles par 4), `findarg("Tomorrow,Today,Yesterday")` → jours courant +1 / 0
     / −1, `findarg("Sunday,…,Saturday")` → jour de cette semaine-là dans les 7 jours **précédents**,
     avec **Result2 := 1**. Les deux formes relatives exigent une date courante non nulle (jours =
     0 → usage + stop(20)). Échec d'analyse → usage. Puis `datstamp(w)`, **w!0 := jours (+7 si
     Result2 = 1)** — donc nom de jour = prochaine occurrence, aujourd'hui inclus [D] —, w!1/w!2
     conservés, puis **`setdatstamp(w)`** (128).
5. Fin : **globale 84** = si `output()` ≠ G150 : `endwrite()` puis `selectoutput(G150)`. Retour
   normal de start (code 0).

**Appel exact de la globale 128** : D1 = BPTR d'un vecteur de 3 longs (dans la frame de Date)
déjà rempli par `datstamp` puis partiellement remplacé ; frame appelante de $34 (date) ou $30
(heure) octets ; résultat ignoré. `date 21-Oct-26 10:00:00` ⇒ **deux** appels successifs :
(17825, minutes courantes, ticks courants) puis (17825, 600, 0) — ce dernier règle l'heure
système à 1 540 116 000 s ($5BCC4E20), 0 µs. Avec un GV de commande dont GV[128] garde le
marqueur `$474C0001 + 2·128` (§3.3), le premier réglage saute à une adresse impaire. `date` sans
argument n'exige que 86 (et donc −25/127/21).

#### 8.4.4 C:SetClock (`SetClock load`) [O WB, D pour l'identification des appels de bibliothèque]

Fichier 4884 octets (md5 `f2775b9198d12db532b935cb70682cd4`), **exécutable C (17 hunks, avec
relocations), pas BCPL** : il n'utilise **aucune globale** ; il passe par dos.library (LVO) et
timer.device. Syntaxe : `setclock load|save|reset` (sinon texte d'usage, code 0).

- **Horloge** : MSM6242 en **$DC0000**, 16 registres de 4 bits, **un registre par long** (registre
  *i* au quartet bas du long `base + 4·i`) : 0/1 secondes, 2/3 minutes, 4/5 heures, 6/7 jour,
  8/9 mois, 10/11 année (2 chiffres), 12 jour de semaine, 13/14/15 = registres de contrôle D/E/F
  (+$34/+$38/+$3C). Valeurs écrites en longs `$FFFxFFFx` (quartet utile répété).
- **Détection** : lit le registre des secondes, attend ~1,5 s (appel dos de 75 ticks, D), relit ;
  valeur changée ⇒ horloge présente. Sinon retente en **$D80000** (message
  `Warning: Clock is at old address`) ; absente aux deux adresses ⇒ `Battery Backed up Clock not
  found` et code retour **5**. Un `SetClock load` sans RTC émulée sort donc en 5 (startup-sequence :
  sans conséquence si FailAt ≥ 5, cas par défaut 10).
- **load** : gèle l'horloge (bit HOLD du registre D, attente de BUSY = 0), lit les 12 chiffres,
  libère ; secondes depuis le 1-jan-1978 (années depuis 78, tables de mois 365/366 jours,
  bissextile = année mod 4 = 0 ; années 00–77 non gérées) ; puis timer.device unité 0, IORequest de
  40 octets sur un port créé pour l'occasion, **TR_SETSYSTIME (11)**, tv_secs = secondes,
  **tv_micro = 0**, DoIO, fermeture. **Aucun passage par dos** : `rn_Time` n'est mis à jour qu'au
  prochain DateStamp.
- **save** : **TR_GETSYSTIME (10)** → tv_secs décomposé en date/heure, écrit dans les registres de
  la RTC (sous HOLD). **reset** : séquence de réinitialisation des registres de contrôle D/E/F.

#### 8.4.5 Conséquences pour notre runtime [D]

- Une ROM qui veut faire tourner C:Date doit fournir **86** (ou −25) et **128** dans les segments
  installés par globin ; 128 ne demande que timer.device **TR_SETSYSTIME** + la relecture qui
  rafraîchit `rn_Time`.
- 127 n'a pas besoin d'être exportée pour Date, mais toute implémentation de −25/128/47 doit
  fournir un tampon IORequest ≥ 40 octets (≥ 48 si l'on reproduit `setio`).
- Les résultats D1 de 128 et D0 de DateStamp sont non significatifs en V34 : renvoyer v / ds est
  compatible.

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
     incrémenté, jamais s'il vaut −1 = système ; condition exacte au §13.6.5 [O]), sinon
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
     **fin** du CLI (cas Execute() synchrone). [O ROM + WB ; bits et contrat complet : §13.6]
  7. Run affiche `"[CLI %N]\n"` (si pas de BSTR initial) puis stop(0).
  Le CLI de fond lit ses commandes dans le FileHandle mémoire ; à son EOF, étant Background, il
  se termine.
- **NewCLI** : crée un CLI **interactif** dans une fenêtre (`"Window,From"`, défaut
  `CON:0/0/640/100/New CLI`) ; la fenêtre est ouverte **par le nouveau process** (findinput puis
  findoutput(`*`)) dans une routine d'init propre à NewCLI (globale 133 de son GV privé). Contrat
  complet : **§13.7**.
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
  - `r ≤ 0` : drapeaux conservés ; le packet est **rendu à la fin** du CLI (returnpkt, Res2 =
    cli_Result2) ; bit 1 de `r` = ne pas faire endread, bit 0 = faire endwrite (§13.6.4). [O]
- Ce que l'init de Run (routine passée dans dp_Type) consomme du packet et écrit : voir le
  **contrat exact du §13.6** (Arg1 = CLI parent : Prompt/SetName/DefaultStack/CommandDir copiés,
  FailLevel **non** hérité (10) ; sortie `*` si Arg3 = StandardOutput du parent, sinon **NIL:** ;
  Arg4 ⇒ cli_StandardInput = cli_CurrentInput ; Arg5 ⇒ répertoire courant ; Arg6 = sélecteur
  de mode). [O]
- Un CLI de fond dont l'entrée (FileHandle mémoire, routines nulles) s'épuise reçoit EOF ; étant
  Background il se termine (§4.5), libère son slot de rn_TaskArray et sort du process.
- Les points [D] ci-dessus sur l'init de Run sont **remplacés** par le contrat observé du §13.6.

### 13.6 Routine d'init de Run : contrat exact [O WB (c:Run, l:Shell-Seg) + O ROM (CLI, entrée 4)]

Repères d'analyse : dans c:Run (hunk 1, BCPL, globale 1 seule définie, max 134), la routine
d'init est à l'offset **$4B8** du hunk ; Run en place l'**adresse machine** (pas un BPTR) dans
dp_Type. Elle utilise deux sous-routines locales (copie des réglages du CLI parent, copie de la
liste de chemins). Côté CLI : start du CLI ROM = sa globale 1, start de Shell-Seg = globale 1 de son hunk.

#### 13.6.1 Contrat d'appel (Q1)
- **Localisation de la CLI à remplir : exclusivement par `findcli()` (globale 134, GV +$218)
  appelée dans le GV désigné par A2.** Elle n'utilise ni un argument du packet, ni le frame de
  l'appelant, ni une variable fournie par start. `findcli()` doit donc renvoyer le **BPTR**
  rangé dans **pr_CLI du process courant** (= le nouveau CLI ; process +$AC). La ROM le lit
  brut dans le process courant (pas de conversion). [O]
  ⇒ start doit avoir rangé la CLI dans pr_CLI **avant** l'appel, et la globale 134 du GV
  courant doit être la *fonction* findcli (c'est le cas du GV partagé ; dans un GV de commande
  ce slot contient une donnée, cf. §3.3 — init ne doit donc jamais tourner sur un GV privé).
- Le **process courant** est obtenu par `taskid()` (globale 14) ; seul l'usage « mode
  Execute » (13.6.2) s'en sert (écriture de pr_ConsoleTask par putlong). [O]
- Hypothèses sur l'appelant (toutes nécessaires) [O pour l'usage, D pour la nécessité] :
  - appel BCPL standard (§1.1/§1.2) : **A0 = 0**, A2 = GV (partagé) du nouveau process,
    A5/A6 = routines d'appel/retour, **A4 = exactement l'adresse d'entrée** (= dp_Type) —
    la routine adresse ses chaînes (`"NIL:"`, `"*"`, `"%N> "`, `"SYS:"`) et ses sous-routines
    **relativement à A4** ;
  - **D1 = BPTR du packet**, et le packet aussi présent au slot 0 du nouveau frame (la routine
    relit le packet depuis ce slot : la routine d'appel doit avoir rangé D1..D4 dans le frame,
    §1.2) ;
  - **frame long-aligné** : une sous-routine prend le BPTR d'une de ses variables de frame
    (queue de liste chaînée) ;
  - **D0 suffisant** pour que le frame d'init et ceux de ses appelés (copie de chemins →
    getvec, copydir → sendpkt) **ne recouvrent ni la CLI ni ses tampons** si ceux-ci sont dans
    le frame de start. Profondeur propre d'init + sous-routines ≈ $30 + $34 + $24 octets avant
    les appels runtime. Valeurs observées : **CLI ROM D0 = $1A4** (CLI à frame+$154..$193),
    **Shell-Seg D0 = $2BC** (CLI à frame+$25C..$29B). [O]
  - aucune lecture du frame de l'appelant, ni d'autre globale du GV que celles listées
    ci-dessous ; **pr_CIS/pr_COS ne sont ni lus ni écrits**.
- Globales utilisées (GV de A2) : **134** findcli, **14** taskid, **60** findoutput, **−26**
  IsInteractive, **111** putlong, **51** currentdir, **89** findsegarray, **10** result2,
  **29** getvec, **113** copydir ; la **valeur** du slot **42** (adresse de qpkt) est lue mais
  pas appelée. [O]
- Pré-requis sur la CLI : effacée sauf les 4 BPTR de tampons déjà installés et inscriptibles :
  **cli_Prompt ($18)**, **cli_SetName ($04)**, **cli_CommandFile ($24)** (et cli_CommandName ($10),
  non utilisé par init). Init **recopie dans** ces tampons ; elle ne les alloue pas. Tailles des
  tampons du start ROM et Shell-Seg (identiques) : Prompt 68 o, CommandName 108 o, CommandFile
  48 o, SetName 84 o. [O]

#### 13.6.2 Champs remplis (Q2)
Notation : `pkt` = BADDR(D1) ; Arg1..Arg6 = pkt+$14..$28 ; `par` = Arg1 (CLI parent ou 0) ;
`cli` = findcli(). Deux modes selon **Arg6** : **Arg6 = 0 ⇒ mode Run** (lancement par c:Run
depuis un CLI) ; **Arg6 ≠ 0 ⇒ mode Execute** (Run lancé par la globale 101 / LVO Execute,
Arg6 = BSTR de commande). Effets dans cet ordre [O] :

1. **cli_StandardInput ($1C) := Arg4** et **cli_CurrentInput ($20) := Arg4** (inconditionnel).
2. Choix du flux de sortie `out` et des drapeaux (valeur initiale **$FFFFFFFC** = −4) :
   - *mode Run* : si **Arg3 = par.cli_StandardOutput** (BADDR(Arg1)+$38 — Run passe son
     output() en Arg3) ⇒ `out := findoutput("*")` ; sinon (sortie de Run redirigée)
     ⇒ `out := findoutput("NIL:")`. Bit 0 des drapeaux mis. Arg2 est **ignoré**.
   - *mode Execute* : si **Arg2 ≠ 0** : **cli_StandardInput := Arg2** (CurrentInput reste
     Arg4), **pr_ConsoleTask (process +$A4) := Arg2.fh_Type** (FileHandle +$08), entrée
     interactive := IsInteractive(Arg2) (valeur brute fh_Interactive), bit 1 mis. Puis
     `out := Arg3` ; si Arg3 = 0 ⇒ `out := findoutput("*")` et bit 0 mis.
3. **cli_Background ($2C) := NON( IsInteractive(out) ET entrée_interactive )** (opérations
   bit à bit sur les valeurs brutes ; entrée_interactive = 0 en mode Run) ⇒ **toujours TRUE (−1)
   en mode Run**.
4. **currentdir(TRUE, Arg5)** ⇒ pr_CurrentDir := Arg5 (l'ancien n'est pas libéré).
5. Réglages hérités (sous-routine locale, arguments cli, out, par) :
   - si `par ≠ 0` : source Prompt = par.cli_Prompt, SetName = par.cli_SetName, pile =
     par.cli_DefaultStack, chemin = **copie profonde** de par.cli_CommandDir (nouveaux nœuds
     getvec(1) `[suivant, copydir(lock)]`, même ordre ; s'arrête silencieusement si getvec
     échoue) ;
   - si `par = 0` : Prompt `"%N> "`, SetName `"SYS:"`, pile **1000**, chemin 0 ;
   - écrit : **cli_StandardOutput ($38) := out**, **cli_CurrentOutput ($30) := out**,
     **cli_FailLevel ($14) := 10** (non hérité), **longueur du BSTR cli_CommandFile := 0**,
     **cli_DefaultStack ($34)**, **cli_CommandDir ($08)**, puis **copie des octets** du BSTR
     Prompt dans le tampon pointé par cli_Prompt et du BSTR SetName dans celui de cli_SetName
     (longueur + texte ; aucun contrôle de taille).
6. **Entrée 3 du segarray (findsegarray()!3) := 0**.
7. **pr_Result2 := D1 (le packet)** (result2(TRUE, pkt)).

Champs **non touchés** : cli_Result2 ($00), cli_ReturnCode ($0C), cli_CommandName ($10),
**cli_Interactive ($28)**, cli_Module ($3C) ; pr_CIS, pr_COS ; dp_Res1/dp_Res2. [O]

Correspondance avec les globales 134..149 d'un GV de commande (§3.3) : StandardInput ↔ 141,
CurrentInput ↔ 142, Background ↔ 145, CurrentOutput ↔ 146, StandardOutput ↔ 148, FailLevel ↔
139, DefaultStack ↔ 147, CommandDir ↔ 136, Prompt ↔ 140, SetName ↔ 135, CommandFile ↔ 143
(init n'écrit pas via ces globales mais directement dans la structure).

#### 13.6.3 Valeur de retour (Q3)
- **Mode Run (Arg6 = 0)** : renvoie le **contenu du slot 42** du GV courant, c.-à-d. l'adresse
  machine de **qpkt** (> 0). [O]
- **Mode Execute (Arg6 ≠ 0)** : renvoie les drapeaux **$FFFFFFFC | bit0 | bit1**, soit **−4,
  −3, −2 ou −1** : bit 0 = « la sortie a été ouverte par init (`*`) et devra être fermée »,
  bit 1 = « l'entrée a été fournie par l'appelant (Arg2) et ne doit pas être fermée ». [O]
- **Arg6** n'est utilisé **que** comme sélecteur de mode (son contenu BSTR n'est pas lu par
  init : c'est Run lui-même qui en a fait le contenu du FileHandle Arg4). [O]
- **Diagnostic** : −1 n'est produit que si init a lu **Arg6 ≠ 0, Arg2 ≠ 0 et Arg3 = 0**
  (ou si le slot 42 vaut −1). Avec le packet émis par Run (Arg6 = 0, Arg3 ≠ 0), un retour −1
  **et** une CLI intacte indiquent que les **lectures/écritures indirectes de la routine
  n'atteignent pas les structures attendues** — toutes passent par « A0 + BPTR×4 », alors que
  result2/qpkt passent par A2 et restent corrects. Causes compatibles avec les observations, à
  vérifier côté appelant : **A0 ≠ 0** à l'entrée (cause unique expliquant à la fois le retour
  −1, la CLI inchangée et un pr_Result2 correct) ; D1 non BPTR ; findcli() renvoyant une APTR, 0
  ou la CLI d'un autre process. Effet de bord révélateur dans ce cas : pr_CurrentDir écrasé par
  une valeur parasite (étape 4) et écritures parasites en mémoire basse ou ailleurs. [D]

#### 13.6.4 Ce que start() doit faire autour de l'appel (Q4) [O ROM ≡ O Shell-Seg]
Comportement identique dans le start du CLI ROM et dans celui de Shell-Seg :

*Avant* :
1. Réserver dans son propre frame les 4 tampons (Prompt, CommandName, CommandFile, SetName) et
   la CLI (16 longs), **effacer la CLI** (clearvec, globale −20, 16 longs).
2. **pr_CLI := BPTR de la CLI** (putlong sur le process courant).
3. Installer les BPTR de tampons dans cli_Prompt, cli_CommandName, cli_CommandFile, cli_SetName.
4. `init := pkt ? pkt.dp_Type : GV[133]` ; `r := init(pkt)` (appel BCPL, D1 = pkt, D0 = taille
   couvrant CLI + tampons, cf. 13.6.1).

*Après* :
5. **Si r > 0** : appeler `r(result2(FALSE))` — en mode Run : qpkt(pkt) ⇒ **le packet est
   rendu immédiatement** à Run (le dp_Port du packet reçu désigne déjà l'émetteur, car le qpkt
   de l'émetteur a remplacé dp_Port par son propre port ; taskwait ne le modifie pas). Le
   résultat de cet appel est ignoré ; **r reste mémorisé** (valeur > 0) pour la fin.
6. Lire pr_TaskNum (process +$8C) pour le prompt/les messages.
7. **Mémoriser cli_StandardOutput** (valeur posée par init) : c'est **cette copie** qui sera
   resélectionnée comme sortie après chaque commande.
8. **cli_Interactive := NON cli_Background ET (cli_StandardInput = cli_CurrentInput)** ⇒ FALSE
   pour un CLI de Run (pas de prompt ni de bannière).
9. **selectinput(cli_CurrentInput)** ⇒ **pr_CIS := Arg4** (le FileHandle mémoire des
   commandes) ; **selectoutput(StandardOutput mémorisée)** ⇒ **pr_COS := `out`** (`*` ou NIL:).
   C'est start, pas init, qui positionne pr_CIS/pr_COS.
10. Si cli_Interactive : bannière/prompt (non concerné ici). Puis boucle de lecture par rdch
    sur input() ; **à chaque tour** start resélectionne `cli_CurrentInput` en entrée et la
    sortie mémorisée (étape 7).

*Fin* (EOF au niveau supérieur) :
- si cli_CurrentInput ≠ cli_StandardInput (fin d'un script Execute) : endread, suppression du
  fichier cli_CommandFile s'il est non vide puis longueur := 0, CurrentInput := StandardInput,
  FailLevel := 10, on continue ;
- sinon, si **non Background** : le CLI continue (la console est « réarmée » : fh_End := −1,
  fh_Args := 1 sur StandardInput) ;
- sinon (**Background**, cas Run) : sortie du CLI :
  - **r < 0** (mode Execute) : vider la sortie courante si fh_Pos > 0 (writebytes) puis fh_Pos
    := 0 ; **endread() sauf si bit 1** ; **endwrite() si bit 0** ; puis **returnpkt(pkt,
    res1, cli_Result2)** ⇒ l'appelant d'Execute() est débloqué seulement maintenant ; dans
    Shell-Seg, res1 est la **valeur résiduelle d'une variable locale de la boucle** (ancien
    répertoire courant sauvegardé autour d'une commande, souvent 0) : **non significative**,
    seul dp_Res2 = cli_Result2 a un sens ;
  - **r ≥ 0** (mode Run, r = qpkt) : **endread() et endwrite()** inconditionnels (ferme le
    FileHandle mémoire et `out`), pas de returnpkt ;
  - puis : freeobj(répertoire courant), libération de la liste cli_CommandDir (freeobj du lock
    + freevec du nœud), libération des autres ressources du CLI, **rn_TaskArray[pr_TaskNum] :=
    0**, fin du process. [O]

Conséquence pour le FileHandle Arg4 construit par Run (`getvec(n/4 + 11)`, n = longueur du
texte sans le `\n` ajouté, bloc non effacé ; tampon **en ligne** à partir de l'index 11) : fh_Link/fh_Interactive/fh_Type/fh_Pos/fh_Funcs/
fh_Func3 = 0, fh_Buf = BPTR(FH)+11, fh_End = n+1 ; **fh_Func2 et fh_Args ne sont pas
initialisés**. Donc : rdch à fh_Pos = fh_End doit traiter **fh_Funcs = 0 comme EOF** ;
**endstream (globale 93)** appelle fh_Func3 seulement s'il est non nul, puis **freevec du
FileHandle** (Result2 préservé) — le tampon en ligne part avec le bloc, rien d'autre n'est
libéré ni envoyé ; fh_Func2/fh_Args ne doivent jamais être utilisés sur ce flux. [O ROM + WB]

#### 13.6.5 Compléments sur c:Run (côté émetteur) [O WB]
- Arg5 = copydir(lock courant) **seulement si pr_CLI de Run ≠ 0**, sinon 0.
- Arg6 = valeur de **pr_Result2 à l'entrée de Run** (0 attendu quand le CLI lance Run comme
  commande ⇒ le lanceur de commandes doit laisser pr_Result2 = 0 ; BSTR quand Run est lancé
  par la globale 101).
- Compteur d'usage du résident « CLI » : incrémenté **seulement** si Arg6 ≠ 0 **et** le BSTR
  de commande est de longueur 0 (et compteur ≠ −1) ; décrémenté (si ≠ −1) sur le chemin
  d'échec « Unable to create background process ». Le start de Shell-Seg met à −1 le compteur du nœud
  résident « CLI » obtenu par une de ses sous-routines locales (non analysée). [O]
- Dans le segarray du nouveau process, l'entrée 3 est déjà 0 côté Run ; init la remet à 0.
- Après la réponse au packet, Run affiche `"[CLI %N]\n"` (N = slot) seulement si Arg6 = 0,
  puis stop(0).

### 13.7 NewCLI : contrat [O WB (c:NewCLI) + O ROM (findinput/findoutput, endtask)]

Repères d'analyse : c:NewCLI = stub standard (§3.3) + hunk 1 BCPL de 605 longs, **max 136**,
qui définit **deux** globales : **1** (start, offset $4) et **133** (offset **$544** : la routine
d'init du nouveau CLI). Comme le stub installe le module dans le **GV privé**, la globale 133
de ce GV privé (≠ cliinit) désigne la routine d'init de NewCLI ; le GV partagé n'est pas
touché. [O]

#### 13.7.1 Côté NewCLI (process appelant) — ordre des effets [O]
1. Lit **pr_StackSize** (process +$84, octets) et le convertit en longs ; lit **pr_GlobVec**
   (+$88, APTR) et le convertit en BPTR (accès par getlong 110 avec l'index en longs relatif au
   taskid : 10 → +$84, 11 → +$88).
2. **Segarray neuf `getvec(4)`** : copie des indices **0..V!0** du segarray du process courant
   (findsegarray 89) — donc `[V!0, V!1, V!2, V!3, V!4]` du CLI appelant. **Aucun contrôle** :
   si V!0 > 4 la copie déborde le bloc de 5 longs. [O]
3. Segment CLI : recherche dans la liste Resident (DosInfo +$10, comparaison compstring
   insensible à la casse avec le nom du nœud à +12) du **2e** nœud nommé **"CLI"**, à défaut du
   **1er**. Trouvé ⇒ entrée 4 := seglist du nœud (`!2`) et compteur d'usage (`!1`) incrémenté
   **seulement s'il vaut ≥ 1**. Pas trouvé ⇒ l'entrée 4 reste **celle du CLI appelant** (copie de
   l'étape 2). `rn_ConsoleSegment` est lu mais **non utilisé** (≠ Run, §9.2). [O]
4. `rdargs("Window,From", v, 50)` ; échec ⇒ freevec du segarray, `"NEWCLI failed\n"`, stop(20)
   (pas de message spécifique). **Window absent ⇒ `"CON:0/0/640/100/New CLI"`**. [O]
5. Sous **Forbid** : premier slot nul de `rn_TaskArray[1..[0]]` ; aucun ⇒ Permit, freevec,
   `"Too many processes\n"`. [O]
6. **createproc(segarray, max(pile, 800) longs, pri 0, BSTR "New CLI", GV = pr_GlobVec du
   process NewCLI)** — c.-à-d. le **GV partagé** du CLI qui a lancé NewCLI (pr_GlobVec n'est pas
   modifié par le stub). Pri **0 constante** (≠ Run). Échec ⇒ Permit, freevec,
   `"Unable to create new process\n"`. Succès ⇒ `rn_TaskArray[slot] := taskid`,
   **pr_TaskNum (+$8C) du nouveau := slot**, Permit. [O]
7. Prépare : Arg1 = **copydir(currentdir courant)** (DupLock ; même si 0) ; Arg3 = **copie
   profonde de la liste de chemins** lue dans la globale 136 du GV privé (= cli_CommandDir du
   CLI appelant ; nœuds `getvec(1)` = `[suivant, copydir(lock)]`, même ordre, arrêt silencieux si
   getvec échoue — même algorithme que Run) ; Arg5 = **filesystemtask()** (106). [O]
8. **Packet de démarrage** (sendpkt 48, synchrone, vers le taskid du nouveau process) :

| Champ | Valeur |
|---|---|
| dp_Type | **adresse machine** de la routine d'init (valeur de la globale 133 du GV privé) |
| dp_Res1 | **−1 pré-rempli** par NewCLI (c'est cette valeur que voit NewCLI en cas de succès) |
| dp_Res2 | 0 |
| Arg1 | DupLock du répertoire courant |
| Arg2 | **BPTR du vecteur rdargs** de NewCLI : `!0` = BSTR Window (ou le défaut), `!1` = BSTR From ou 0 (vecteur **dans la pile de NewCLI**, valide tant que NewCLI attend la réponse) |
| Arg3 | liste de chemins copiée |
| Arg4 | **BPTR de GV_privé[134]** : les 16 longs = copie de la CommandLineInterface du CLI appelant (§3.3 ; GV[134+i] ↔ champ CLI +4·i) |
| Arg5 | pr_FileSystemTask de NewCLI |
| Arg6.. | non initialisés |

9. Résultat de sendpkt (= dp_Res1 de la réponse) :
   - **≠ 0 ⇒ stop(0)**, aucun message côté NewCLI ;
   - **= 0 ⇒ `"Unable to open new window\n"` puis `"NEWCLI failed\n"`**, `rn_TaskArray[slot] := 0`,
     compteur d'usage du résident trouvé **décrémenté s'il ≠ −1** (même s'il n'avait pas été
     incrémenté), **stop(20)**. Le segarray, le DupLock et la copie de chemins ne sont **pas**
     libérés par NewCLI (le segarray l'est par endtask dans le nouveau process, cf. 13.7.3). [O]

⇒ **Q2 — « Unable to open new window » = la réponse au packet de démarrage a dp_Res1 = 0.**
Seule la routine d'init (13.7.2) produit cette réponse, dans trois cas : findinput de la
fenêtre = 0, fenêtre non interactive (fh_Interactive = 0), ou findoutput(`*`) = 0. [O]

#### 13.7.2 Routine d'init de NewCLI (dans le nouveau process) [O]
Même contrat d'appel que l'init de Run (§13.6.1 : appelée par start avec D1 = pkt, A4 = son
adresse, A2 = GV partagé, A0 = 0, frame aligné ; elle adresse ses chaînes `"*"`,
`"Cannot open From file %S\n"`, `"s:cli-startup"`, `"New CLI process %N\n"` et sa sous-routine
relativement à A4). CLI à remplir = **findcli()** (134) du GV partagé. `par` = BADDR(Arg4).
Effets dans l'ordre :

1. **currentdir(TRUE, Arg1)** ⇒ pr_CurrentDir := DupLock.
2. **pr_FileSystemTask (+$A8) := Arg5** ; **pr_WindowPtr (+$B8) := 0** (putlong 111, index 19
   et 23 relatifs au taskid).
3. **Ouverture de la fenêtre = `findinput(Arg2!0)`** (globale 59, **dans le nouveau process**),
   nom = le BSTR Window tel quel (ex. `CON:0/80/480/100/MyCLI`).
   - **Échec A** : findinput renvoie 0 ;
   - **Échec B** : `IsInteractive(fh)` (globale −26, valeur brute **fh_Interactive**, FH +$04)
     = 0 ⇒ endstream(fh) puis **Result2 := 206**.
   Dans les deux cas : **returnpkt(pkt, 0, Result2)** (⇒ NewCLI affiche « Unable to open new
   window »), puis Result2 := taskid, et init **renvoie le contenu du slot 34 du GV** (adresse
   de **endtask**) ⇒ start l'appelle (r > 0, §13.5) ⇒ le process se termine.
4. Succès : **cli_StandardInput ($1C) := fh**, selectinput(fh), **pr_ConsoleTask (+$A4) :=
   fh_Type** (FH +$08 : le port du handler qui a servi l'open).
5. **cli_StandardOutput ($38) := findoutput("*")** (globale 60) — donc un **2e open, sur la
   console qui vient d'être posée**. Échec (0) ⇒ endread() (ferme la fenêtre d'entrée),
   **returnpkt(pkt, 0, Result2)** ⇒ même message « Unable to open new window », Result2 :=
   taskid, renvoie endtask (comme 3). Succès ⇒ selectoutput(cli_StandardOutput).
6. **cli_CurrentInput ($20) := cli_StandardInput**. Puis :
   - **From fourni** (Arg2!1 ≠ 0) : findinput(From) ; échec ⇒ `writef("Cannot open From file
     %S\n", From)` (dans la nouvelle fenêtre), on continue ; succès ⇒ cli_CurrentInput := ce flux ;
   - **From absent** : sous-routine « ouverture silencieuse » : sauve pr_WindowPtr, le met à
     **−1** (pas de requester), `findinput("s:cli-startup")`, restaure pr_WindowPtr ; résultat ≠ 0
     ⇒ cli_CurrentInput := ce flux. (`s:cli-startup` n'est pas cherché si From est donné.)
7. **cli_CurrentOutput ($30) := cli_StandardOutput** ; **cli_Background ($2C) := 0** (FALSE,
   explicite, ≠ Run) ; **cli_CommandDir ($08) := Arg3** ; **cli_ReturnCode ($0C) := 0** ;
   **cli_FailLevel ($14) := par.FailLevel** (GV[139] : **hérité**, ≠ Run qui force 10) ;
   **cli_Result2 ($00) := 0** ; longueur du BSTR cli_CommandFile := 0 ; **cli_DefaultStack ($34)
   := par.DefaultStack** (GV[147]) ; **cli_Module ($3C) := 0** ; copie des octets (longueur +
   texte, sans contrôle de taille) du **Prompt** de `par` (GV[140]) dans le tampon cli_Prompt et
   du **SetName** de `par` (GV[135]) dans le tampon cli_SetName.
8. `writef("New CLI process %N\n", pr_TaskNum)` (sur la nouvelle fenêtre).
9. **findsegarray()!3 := 0** ; **Result2 := pkt** ; renvoie **le contenu du slot 42** (adresse de
   qpkt) ⇒ start fait qpkt(pkt) ⇒ réponse immédiate, **dp_Res1 = −1** (valeur pré-remplie par
   NewCLI, init ne la modifie pas), dp_Res2 = 0. [O]

Non touchés par init : cli_CommandName ($10), **cli_Interactive ($28)** (calculé ensuite par
start : NON Background ET StandardInput = CurrentInput, §13.6.4 étape 8 ⇒ FALSE tant que
s:cli-startup est l'entrée courante, TRUE ensuite), pr_CIS/pr_COS **sont** positionnés
(selectinput/selectoutput) mais start les resélectionne de toute façon. [O]

Globales du **GV partagé** utilisées par init (toutes doivent exister dans le GV du CLI qui
lance NewCLI) : **10, 14, 49, 51, 59, 60, 61, 62, 63, 74, 89, 93, 110, 111, 134, −26**, et les
**valeurs** des slots **34** (endtask) et **42** (qpkt), qui doivent être des adresses machine
**> 0** (start les appelle comme fonctions). [O]

#### 13.7.3 Démarrage et fin du nouveau CLI (Q3) [O ROM + WB]
- Démarrage §2.4/§13.5 sur le segarray `[V!0, V!1, V!2, V!3, CLI]` : globin de V!1..V!V!0
  **dans le GV partagé** (y compris l'entrée 3 = cliinit du parent, non encore effacée à ce
  moment), taskwait, puis start(pkt) qui alloue la CLI, pr_CLI := elle, appelle `pkt.dp_Type`.
- Contrat de retour identique à Run (r > 0 = fonction appelée avec Result2) mais deux valeurs
  possibles : **qpkt** (succès, 13.7.2 étape 9) ou **endtask** (échec, étapes 3/5).
- **endtask** (globale 34, ROM) : libère (freevec) le **segarray** (pr_SegList) du process
  courant, libère le **GV** s'il diffère de `dl_GV` (GV partagé ⇒ non libéré), puis
  **RemTask(courant)**. Ne revient pas. [O ; libération de la mémoire du process/pile : S]
- **pr_ConsoleTask du nouveau process := fh_Type du flux fenêtre** (étape 4) : c'est ce qui
  rend `*` valide dans le nouveau CLI (et chez ses fils, qui l'héritent via createproc). NewCLI
  lui-même ne touche pas à son propre pr_ConsoleTask. [O]
- CLI **interactif, non Background** : il ne se termine qu'à EOF après EndCLI (qui force
  Background, §9.2) ; à la sortie, r = qpkt ≥ 0 ⇒ endread + endwrite inconditionnels (ferment les
  deux flux fenêtre), pas de returnpkt, rn_TaskArray[slot] := 0 (§13.6.4 *Fin*). [O/D]

#### 13.7.4 findinput / findoutput vus du handler (ROM, globales 59/60) [O ROM]
Routine commune (mode 1005 / 1006) :
- FileHandle **getmem(10, $10001)** (11 longs **effacés**), fh_Pos = fh_End = −1, routines
  fh_Funcs/Func2/Func3 installées (Func3 selon le mode).
- **Nom = `*`** (compstring) : port := **pr_ConsoleTask** (consoletask 105) ; **pas de
  deviceproc** ⇒ **Arg2 = valeur résiduelle de Result2** (en pratique le dp_Res2 du dernier
  packet reçu, non significative : **ne pas l'interpréter comme un lock**).
- **Nom = `NIL:`** : aucun packet, fh_Type 0, routines 0, renvoie le FileHandle.
- Sinon : deviceproc(nom) ⇒ port, Arg2 = Result2 (lock de deviceproc ; 0 pour CON:/RAW:).
- port = 0 ⇒ freevec, renvoie 0. Sinon **fh_Type := port**, puis sendpkt(port, mode,
  **Arg1 = BPTR du FileHandle, Arg2 = lock/résidu, Arg3 = BSTR du nom complet**).
- **dos n'écrit ni fh_Interactive ni fh_Args** : c'est au handler de les remplir dans le
  FileHandle reçu en Arg1. Res1 = 0 ⇒ freevec, puis `errorreq(2, Result2, port)` (114) ; Retry ⇒
  tout recommence ; sinon renvoie 0. Res1 ≠ 0 ⇒ renvoie le FileHandle (BPTR).

#### 13.7.5 Ce que le handler console doit fournir pour que NewCLI réussisse (Q4) [O/D]
1. **Démarrage** (globale 112, packet Arg1 = `CON:0/80/480/100/MyCLI`, Arg2 = 0/1, Arg3 =
   nœud) : ouvrir la fenêtre, **Res1 ≠ 0**. [O]
2. **ACTION_FINDINPUT (1005)** reçu ensuite (Arg1 = FileHandle, Arg2 = 0, Arg3 = même nom) :
   **écrire fh_Interactive (FH +$04) ≠ 0** (le console-handler ROM y met −1 [D]) et fh_Args
   (FH +$24) = clé du flux ; répondre **Res1 = −1**. Un fh_Interactive nul ⇒ échec B ⇒ « Unable
   to open new window » **même si la fenêtre est ouverte** (elle est alors refermée par END). [O]
3. **ACTION_FINDOUTPUT (1006) sur le même port avec Arg3 = BSTR `"*"`** et Arg2 = résidu :
   le handler doit l'accepter comme **un second flux sur la fenêtre déjà ouverte** (sans
   analyser `*` comme une spécification de fenêtre, sans exiger de lock), remplir fh_Interactive
   ≠ 0 et fh_Args, **Res1 = −1**. Refus ⇒ « Unable to open new window ». [O pour l'exigence de
   succès, D pour le remplissage de fh_Interactive sur ce flux]
4. **fh_Type** du flux d'entrée doit être le **port du process handler** (posé par dos, §13.7.4)
   puisqu'il devient pr_ConsoleTask : si notre findinput range le port ailleurs que FH +$08,
   l'étape 5 vise un mauvais port. [O]
5. Le handler doit **rester vivant tant qu'il reste un flux ouvert** : deux ACTION_END arrivent à
   la fin (entrée puis sortie, endread puis endwrite), plus éventuellement ceux de flux `*`
   ouverts par les commandes. Fermer la fenêtre/terminer au premier END casse la sortie. [D]
6. Ensuite, packets habituels de console : READ, WRITE, WAIT_CHAR (20), SCREEN_MODE (994),
   DISK_INFO (25), END (1007) (cf. handlers-v34 §2). [O/D]

Diagnostic pour notre ROM (symptôme « Unable to open new window » + « NEWCLI failed », Run/
Execute OK) [D] : la réponse Res1 = 0 provient forcément de l'init de NewCLI exécutée **dans le
nouveau process sur le GV partagé**. Causes à vérifier, par ordre de probabilité : (a) le
FINDOUTPUT `"*"` vers pr_ConsoleTask est refusé par notre handler, ou notre findoutput("*") ne
vise pas pr_ConsoleTask ; (b) fh_Interactive (+$04) ou fh_Type (+$08) du flux d'entrée non
renseignés au retour de notre findinput ; (c) globale −26 (IsInteractive) absente/incorrecte
dans le GV partagé ; (d) findinput(`CON:…`) échoue dans un process qui n'est pas celui d'un CLI
« standard » (pr_CurrentDir = DupLock, pr_WindowPtr = 0, pr_FileSystemTask = Arg5 déjà posés).
Run ne passe par aucun de ces chemins (il ouvre `*`/`NIL:` en sortie seulement, jamais une
fenêtre en entrée), d'où la différence observée.

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
  (nécessaires à la compatibilité de sortie) ;
- la ROM n'a pas été modifiée ; seules des extractions temporaires des fichiers du disque
  Workbench (et, pour le §13.6, une copie de lecture temporaire de la ROM, supprimée après
  analyse) ont été faites dans le répertoire scratch de session, hors du dépôt.
- **§13.6 (relu le 2026-10-20)** : le contrat de la routine d'init de c:Run et du start des CLI
  est exprimé en entrées/sorties, champs écrits (offsets de structure et numéros de globales),
  valeurs de retour et ordre des effets observables ; aucun encodage, aucune séquence
  d'instructions, aucun nom de registre de travail interne n'y figure (seuls les registres de
  la convention d'appel publique §1.1 sont cités). Les offsets de hunk de c:Run ($4B8) et les
  tailles de frame observées ($1A4, $2BC) sont des repères d'analyse et des éléments d'ABI
  (dimensionnement de D0), pas du code.
- **§13.7 (relu le 2026-10-20)** : le contrat de c:NewCLI (process appelant, routine d'init du
  nouveau CLI, findinput/findoutput et endtask de la ROM) est exprimé en effets observables
  ordonnés, champs écrits (offsets de Process/CLI/FileHandle, numéros de globales), contenu du
  packet de démarrage, chaînes de messages et conditions d'échec ; aucun encodage, aucune séquence
  d'instructions, aucun registre de travail interne. Les offsets $4/$544 du hunk sont des repères
  d'analyse. Sources : extraction temporaire de `c/NewCLI` d'une **copie** de l'ADF dans le scratch
  de session ; ROM lue en place, en lecture seule (non copiée, non modifiée).
- **Correction du 2026-10-29** : retirées les 15 adresses ROM restantes (segarray ROM, colonne
  « Repère » de la table des globales par segment, start du CLI ROM) et la mention « adresses ROM =
  repères » ; numéros de globales, offsets dans le vecteur global et segments porteurs conservés.
