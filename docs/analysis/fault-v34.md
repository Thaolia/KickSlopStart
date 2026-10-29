# fault() (globale BCPL 104) et C:Fault — comportement V34 / Workbench 1.3.3

Piste ANALYSE. Sources : ROM `kick34005.A500` (lecture seule) et `c/Fault`, `c/Copy` extraits de
`assets/wb133.adf` (Workbench 1.3.3) dans un répertoire temporaire. Contrats observables uniquement ;
aucune adresse de routine ROM n'est citée.

Légende : **[O]** observé dans le binaire · **[D]** déduit (raisonnement sur l'observé, non exécuté).

Références internes : convention d'appel BCPL (§1), `runcommand` (§4.3), globales (§8.2/8.3),
`rdargs` (§5.4), `writef` (§6.3) dans [bcpl-runtime-v34.md](bcpl-runtime-v34.md).

---

## 1. Résumé

- `fault(code)` ne contient **aucun texte d'erreur** : pour `code ≠ 0` elle charge **`C:FAULT`** depuis
  le disque (sans requester, pas de recherche dans la liste Resident), pose **pr_Result2 := code**,
  l'exécute via `runcommand` avec une pile de **400 longs**, puis décharge le segment. [O]
- Si `C:FAULT` n'a pas pu être chargé (ou si `runcommand` renvoie −1), repli :
  `writef("Error code %N\n", code)` — **avec** saut de ligne. [O]
- `code = 0` : ne fait rien, n'écrit rien. [O]
- `C:Fault` distingue ses deux modes par **pr_Result2 à l'entrée** :
  - **≠ 0** (appel par `fault()`) : écrit **le texte seul** + `\n`, sans préfixe, sans lire d'argument ; [O]
  - **= 0** (ligne de commande, le CLI met Result2 à 0) : lit jusqu'à 10 numéros via `rdargs` et écrit
    `Fault %I3: <texte>\n` pour chacun. [O]
- Code inconnu : texte `Error <n>` (format `"Error %N"`). [O]
- Exemple C:Copy : `Can't open zzz for input - ` vient de **Copy** (sans `\n`), `object not found\n`
  vient de **C:Fault** appelé par `fault(205)`. [O]

---

## 2. `fault(code)` — globale 104 (GV +$1A0), ROM

Repères : `fault()` est définie dans un segment BCPL résident de dos dont la table globin fournit
les globales 104 (`fault`) et −21 (chargement sans requester, §2.2). Chaînes BSTR utilisées :
`"C:FAULT"` et `"Error code %N\n"` (longueur 14 : le `\n` est **dans** la chaîne). [O]

### 2.1 Déroulé observable

| Étape | Comportement | Cert. |
|---|---|---|
| 1 | `code = 0` → retour immédiat, rien n'est écrit, Result2 inchangé. | O |
| 2 | Chargement du segment nommé par le BSTR **`C:FAULT`** (7 caractères, majuscules, chemin via l'assign `C:`) par la globale **−21**. | O |
| 3 | **pr_Result2 := code** (via `result2(TRUE, code)`, globale 10), **après** le chargement (donc le Result2 éventuellement posé par LoadSeg est écrasé). Fait même si le chargement a échoué. | O |
| 4 | Si seglist ≠ 0 : `runcommand(seg, 400, ?, ?)` (globale 121). Pile = **400 longs** (1600 octets). Code retour mémorisé. | O |
| 5 | `unloadseg(seg)` (globale 82) **toujours appelé**, y compris avec seg = 0. | O (appel) / D (sans effet pour 0) |
| 6 | Si seglist = 0 **ou** si le code retour de `runcommand` vaut **−1** (pile impossible à allouer, ou commande sortie avec −1) : `writef("Error code %N\n", code)`. | O |
| 7 | Retour à l'appelant. | O |

### 2.2 Détails d'interface

- **Chargement (globale −21)** [O] : sauvegarde **pr_WindowPtr**, le met à **−1** (supprime les
  requesters système, p. ex. « Please insert volume »), appelle `load(nom)` (globale 81 = LoadSeg
  BCPL, nom BSTR), restaure pr_WindowPtr, renvoie la seglist (0 si échec). **Pas** de consultation
  de la liste Resident, **pas** de recherche dans le chemin de commandes du CLI : uniquement le nom
  littéral `C:FAULT`.
- **Arguments de la commande** [O] : `fault()` ne fournit que les deux premiers paramètres de
  `runcommand` ; les paramètres 3 et 4 (adresse/longueur d'arguments → A0/D0 à l'entrée de la
  commande) sont **indéterminés** (valeurs résiduelles de registres). `runcommand` ne copie rien, il
  convertit seulement le 3ᵉ en adresse octet. Aucun tampon d'arguments n'est injecté dans le flux
  d'entrée (contrairement au CLI §4.2). C:Fault ne lit ni A0/D0 ni l'entrée dans ce mode, donc
  c'est sans conséquence. **Recommandation clean** [D] : passer adresse 0 / longueur 0.
- **Flux** [O] : `fault()` ne touche ni à `input()` ni à `output()` : la commande écrit sur le
  `output()` **courant de l'appelant** (pr_COS) et hérite de son `input()` (pr_CIS) sans le lire.
- **Pile** : 400 longs, allouée/libérée par `runcommand` (§4.3). [O]
- **pr_Result2 avant l'appel** = `code`. [O]
- **Code retour** : seul le test « = −1 » est exploité (déclenche le repli). Sinon ignoré. [O]
- **Valeur rendue par fault()** : aucune valeur explicite ; D1 au retour = résultat du dernier appel
  interne (unloadseg ou writef). Non contractuel ; aucun appelant observé ne l'utilise (Copy l'ignore). [O]
- **pr_Result2 après fault()** : `fault()` ne le restaure pas. Il vaut `code` tel que posé à l'étape 3,
  sauf modification par les E/S de C:Fault (écriture console) ou du repli `writef`. C:Fault en mode
  fault() ne le réécrit pas lui-même. [O pour fault/C:Fault, D pour l'effet des E/S]
- **CLI** : `fault()` ne modifie pas cli_ReturnCode / cli_Result2. Le stub de C:Fault recopie à sa
  sortie GV[134..149] vers la structure CLI (§3 de bcpl-runtime), mais C:Fault ne modifie aucune de
  ces globales → valeurs inchangées. [O stub / D effet nul]

### 2.3 Repli sans C:FAULT

Texte exact : `Error code ` + code décimal signé (`%N`) + `\n`. Exemple : `fault(205)` sans C:FAULT
→ `Error code 205\n`. [O]

---

## 3. `C:Fault` (Workbench 1.3.3, `c/Fault`, 2688 octets)

Commande BCPL standard : hunk 0 = stub de commande (§3.3 bcpl-runtime, 0x13C octets), hunk 1 = code
BCPL (0x910 octets), globin : **globale 1 (start)** seule, max global 138. Données internes :
template `",,,,,,,,,"` (10 clés positionnelles anonymes), vecteur d'arguments de 25 longs. [O]

### 3.1 Sélection du mode

À l'entrée, `start` lit **pr_Result2** (lecture seule, `result2(FALSE)`), `input()` et `output()`. [O]

- Si `output() = 0` : ouvre `"*"` (findoutput) et le sélectionne ; il sera fermé (`endwrite`) à la
  fin. Vaut pour les deux modes. [O]
- **Result2 ≠ 0 → mode « fault() »** : liste de codes = { Result2 } ; **aucune** lecture
  d'arguments (pas de rdargs, pas d'accès à `input()`). [O]
- **Result2 = 0 → mode « ligne de commande »** (`FAULT n …`) : voir §3.2. [O]

### 3.2 Mode ligne de commande

| Cas | Comportement | Cert. |
|---|---|---|
| `input() = 0` ou `rdargs` échoue (p. ex. plus de 10 nombres) | écrit `"%S failed - bad args\n"` avec %S = **cli_CommandName** (GV 138, nom tel que tapé), ferme la sortie `*` si ouverte, `stop(20)` → code retour **20**. | O |
| Chaque argument présent (dans l'ordre, s'arrête au premier absent) | converti en nombre décimal ; succès → ajouté à la liste **sauf s'il y figure déjà** (doublons ignorés silencieusement) ; échec → `"argument %S ignored\n"`. | O |
| Aucun argument | rien n'est écrit, code retour 0. | O |

Conversion nombre [O] : chaîne non vide ; un signe `+` ou `-` est accepté **uniquement en première
position** et **pas seul** ; ensuite uniquement des chiffres `0`–`9` ; tout autre caractère → échec.
`-` rend la valeur négative. Pas de contrôle de débordement. (La conversion passe la valeur par
Result2 en interne, sans effet externe car Result2 n'est plus relu ensuite.)

### 3.3 Écriture d'un code

Pour chaque code de la liste, dans l'ordre :

1. mode ligne de commande seulement : `writef("Fault %I3: ", code)` (décimal signé, cadré à droite
   sur 3 colonnes minimum) ; [O]
2. `writef(texte, code, code)` — le texte de la table §4 (sans `%`, donc écrit tel quel), ou
   `"Error %N"` pour un code inconnu ; [O]
3. `wrch('\n')`. [O]

Puis fermeture de la sortie `*` si elle avait été ouverte, et retour normal de `start` → code
retour **0**. [O]

---

## 4. Table des messages (C:Fault 1.3.3) [O]

| Code | Texte |
|---|---|
| 103 | `insufficient free store` |
| 105 | `task table full` |
| 120 | `argument line invalid or too long` |
| 121 | `file is not an object module` |
| 122 | `invalid resident library during load` |
| 202 | `object in use` |
| 203 | `object already exists` |
| 204 | `directory not found` |
| 205 | `object not found` |
| 206 | `invalid window description` |
| 209 | `packet request type unknown` |
| 210 | `stream name component invalid` |
| 211 | `invalid object lock` |
| 212 | `object not of required type` |
| 213 | `disk not validated` |
| 214 | `disk write-protected` |
| 215 | `rename across devices attempted` |
| 216 | `directory not empty` |
| 218 | `device (or volume) not mounted` |
| 219 | `seek failure` |
| 220 | `comment too big` |
| 221 | `disk full` |
| 222 | `file is protected from deletion` |
| 223 | `file is write protected` |
| 224 | `file is read protected` |
| 225 | `not a valid DOS disk` |
| 226 | `no disk in drive` |
| 232 | `no more entries in directory` |
| tout autre (dont 0 en ligne de commande, 104, 207, 208, 217, 227–231, **303**, négatifs) | `Error <n>` (format `"Error %N"`) |

Remarques : 303 n'existe pas en 1.3 → `Error 303`. Les textes sont en minuscules, sans point final.
Le saut de ligne n'est pas dans les chaînes : il est ajouté par `wrch('\n')`.

---

## 5. Exemple C:Copy : `Can't open zzz for input - object not found`

- C:Copy (1.3.3) possède une routine d'erreur commune : elle **lit Result2 d'abord** (pour le
  protéger des E/S suivantes), écrit le message de Copy par `writef(fmt, a, b, c)`, puis appelle
  **`fault(Result2 sauvé)`** (unique appel à la globale 104 dans Copy). [O]
- Le format de Copy est `"Can't open %S for input - "` : il se termine par `" - "` **sans** `\n`. [O]
  Autres formats Copy suivis de fault : `"Can't open %S - "`, `"Could not get information for \"%S\" - "`,
  `"Unable to create directory %S - "`. [O]
- `Open("zzz")` échoue avec Result2 = 205 → `fault(205)` → C:Fault en mode fault() écrit
  `object not found` + `\n`. [O/D pour la valeur 205, standard ERROR_OBJECT_NOT_FOUND]

Ligne finale : `Can't open zzz for input - ` (Copy) + `object not found\n` (C:Fault).
Sans `C:FAULT` accessible : `Can't open zzz for input - Error code 205\n` (repli ROM).

---

## 6. Vecteurs de test (entrée → sortie attendue)

`⏎` = `\n`. « C: présent » = un C:Fault conforme au §3 accessible sous `C:FAULT`.

| # | Situation | Sortie attendue sur output() | Code retour / Result2 |
|---|---|---|---|
| T1 | `fault(0)` | (rien) | Result2 inchangé |
| T2 | `fault(205)`, C: présent | `object not found⏎` | Result2 = 205 [D si E/S neutres] |
| T3 | `fault(303)`, C: présent | `Error 303⏎` | |
| T4 | `fault(232)`, C: présent | `no more entries in directory⏎` | |
| T5 | `fault(205)`, C:FAULT absent (pas de requester même si C: assigné à un volume absent) | `Error code 205⏎` | Result2 = 205 |
| T6 | `fault(205)` alors que `output()` = 0, C: présent | ouvre `*`, y écrit `object not found⏎`, le ferme | |
| T7 | CLI : `FAULT 205` | `Fault 205: object not found⏎` | rc 0 |
| T8 | CLI : `FAULT 205 303` | `Fault 205: object not found⏎Fault 303: Error 303⏎` | rc 0 |
| T9 | CLI : `FAULT 205 205` | `Fault 205: object not found⏎` (une seule fois) | rc 0 |
| T10 | CLI : `FAULT 5` | `Fault   5: Error 5⏎` | rc 0 |
| T11 | CLI : `FAULT abc 103` | `argument abc ignored⏎Fault 103: insufficient free store⏎` | rc 0 |
| T12 | CLI : `FAULT` | (rien) | rc 0 |
| T13 | CLI : `fault 1 2 3 4 5 6 7 8 9 10 11` | `fault failed - bad args⏎` | rc 20 |
| T14 | CLI : `FAULT -205` | `Fault -205: Error -205⏎` | rc 0 |
| T15 | `copy zzz to ram:x` (zzz inexistant) | `Can't open zzz for input - object not found⏎` | |

Notes : T13 dépend de `rdargs` (§5.4 : item positionnel sans clé libre → erreur) ; le nom affiché
est cli_CommandName tel que tapé. T10/T14 : `%I3` cadre à droite sur 3 colonnes, la largeur
s'étend si nécessaire.

---

## 7. Points pour l'implémentation clean [D]

- `fault()` doit **charger depuis le disque** (`C:FAULT`), pas embarquer les textes : c'est ce qui
  rend la sortie identique à la 1.3 quand le disque Workbench fournit C:Fault. Un C:Fault maison
  doit suivre le §3 (sélection du mode par Result2, pas de préfixe en mode fault()).
- Ordre à respecter : chargement **puis** pose de Result2 (sinon LoadSeg l'écrase).
- Suppression des requesters pendant le chargement (pr_WindowPtr = −1, restauré ensuite).
- Le repli contient son propre `\n` ; le texte de C:Fault aussi (via wrch) : l'appelant ne doit
  pas en ajouter.

## Relecture clean-room

Relecture du 2026-10-29.

- [x] Aucune suite d'instructions 68000 transcrite, aucun extrait de désassemblage.
- [x] **Corrigé** : retirés les « repères » ROM du §2 (adresse d'entrée de `fault()`, adresse du
  segment BCPL, adresses des chaînes BSTR, offsets internes de la table globin) et la mention d'en-tête
  qui présentait les adresses ROM comme repères. Conservés : numéros de globales (ABI du vecteur
  global BCPL), chaînes émises.
- [x] Le tableau §2.1 décrit les **effets observables** dans leur ordre (chargement puis pose de
  Result2, repli, déchargement), ordre qui conditionne la sortie ; ce n'est pas un déroulé
  d'instructions.
- [x] La table des messages du §4 provient de `c/Fault` (disque Workbench), pas de la ROM. La seule
  donnée ROM reproduite est la chaîne de repli `Error code %N\n` (texte émis, observable).
