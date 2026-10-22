# Heure système au boot depuis la disquette — KS 1.3 (V34)

> Piste **ANALYSE** (dirty). Source : ROM `assets/kick34005.A500` (lecture seule), segarray dos
> (`bcpl-runtime-v34.md` §2.4) : entrée 6 = file system (FS), entrée 7 = process « restart » /
> validateur (`rn_RestartSeg`, nom de process `"Validator"`). Spécification **comportementale**
> uniquement : conditions, valeurs, effets, champs d'ABI. Adresses ROM = repères d'analyse.
> Conventions : **[O]** observé dans la ROM, **[D]** déduit. Numéros de globales = numéros dans le
> GV **du process concerné** (le validateur a son propre GV : ses globales 186/187/203 n'ont rien à
> voir avec celles du FS ou de dos portant le même numéro).
> Complète `bcpl-runtime-v34.md` §8.4 (DateStamp −25, datstamp 86, compstamp 126, timerio 127,
> setdatstamp 128) et `handlers-v34.md`.

---

## 0. Réponse courte

Ce n'est ni dos, ni le strap, ni le FS lui-même : c'est le **process restart/validateur** (entrée 7
du segarray) que le FS lance **à chaque montage d'un volume DOS**. En fin d'exécution réussie, il
règle l'heure système (TR_SETSYSTIME, via la globale dos **128 setdatstamp**) sur la **plus récente
de deux dates du bloc racine** — date de modification du répertoire racine (longs 105..107) et date
de modification du disque (longs 118..120) — **seulement si** : le volume est dans l'**unité 0** du
device (DF0:), l'heure système courante a **jours = 0** (horloge jamais réglée), et cette heure est
**strictement antérieure** à la date retenue. [O]

Le fait boîte noire (« Date affiche l'heure où xdftool a modifié l'image ») s'explique ainsi :
xdftool a réécrit les dates du bloc racine ; au montage de DF0: le validateur a recopié la plus
récente dans l'horloge système encore « à zéro ». [D, cohérent avec O]

> **Correction** de `bcpl-runtime-v34.md` §8.4.2 (setdatstamp, « Appelant observé : uniquement
> C:Date — la ROM ne l'appelle pas ») : c'est **faux** ; la ROM l'appelle depuis le validateur
> (repère `$FFFF8E`). [O]

---

## 1. Qui, et quand

| Étape | Acteur | Effet | Cert. |
|---|---|---|---|
| 1 | FS (handler DFx, entrée 6) | Dans sa boucle principale, sur détection d'un (nouveau) disque, lance un process avec le segment **restart** (nom `"Validator"`, repère `$FFD440..$FFD52A`) et lui envoie un packet de démarrage | O |
| 2 | Validateur | Ouvre le device du FS (même nom, **même unité**, mêmes flags que le FS), lit le bloc racine | O |
| 3 | Validateur | Contrôle le bloc racine ; type de disque ≠ `'DOS\0'` → fin en échec | O |
| 4 | Validateur | Cherche/crée le nœud de volume (§4.2) | O |
| 5 | Validateur | **Mémorise la date la plus récente** parmi deux champs du bloc racine (§2) | O |
| 6 | Validateur | Bitmap valide → le relit ; invalide → validation complète (ou abandon, §3) | O (branches) / D (enchaînement après reconstruction) |
| 7 | Validateur | **Fin réussie → réglage conditionnel de l'heure (§3)**, puis libérations, réponse au FS, fermeture du device, fin du process | O |
| 7' | Validateur | Fin en échec → **aucun** réglage d'heure | O |

- Le lancement a lieu **à chaque insertion/montage** d'un disque DOS, pas seulement au boot (c'est
  le même process qui charge le bitmap en 1.3). [D : déclenché par l'état « disque changé » de la
  boucle du FS ; le chemin « bitmap valide » s'exécute à chaque fois]
- Au boot, le montage de DF0: a lieu au premier accès DOS au disque (startup-sequence…), donc
  **avant** que `C:Date` ou `SetClock` ne s'exécutent. Le validateur tourne en process séparé ; le
  réglage peut donc survenir en parallèle des premières commandes. [D]
- dos (init, strap, `cliinit`) **ne règle pas** l'heure. Le FS lui-même n'appelle jamais 128 ; il
  n'utilise que DateStamp (lecture). [O : seules occurrences de 128 dans les entrées 6–7 = validateur]

### Packet de démarrage du validateur (ABI interne FS → validateur) [O]

Le validateur lit dans les arguments du packet reçu :

| Argument | Contenu (côté FS) | Usage côté validateur |
|---|---|---|
| Arg1 | vecteur d'environnement (`fssm_Environ`, BPTR DosEnvec) | taille de bloc : `de_SizeBlock` (env!1) |
| Arg2 | **numéro d'unité** (`fssm_Unit`) | unité pour l'ouverture du device **et condition « unité 0 » du réglage d'heure** |
| Arg3 | nom du device (`fssm_Device`) | ouverture du device |
| Arg4 | drapeau fourni par le FS (rôle non élucidé) | si non nul **et** bitmap invalide → abandon sans valider |
| Arg5 | flags d'ouverture (`fssm_Flags`) | ouverture du device |

(Le FS recopie `fssm_Unit`, `fssm_Device`, `fssm_Environ`, `fssm_Flags` à son démarrage — repère
`$FFEE2A..$FFEE3C`.)

---

## 2. Quelle date est prise

### 2.1 Champs du bloc racine OFS (bloc 880 sur DD, 128 longs = 512 octets) [O]

Le FS et le validateur expriment ces positions **relativement à la fin du bloc** (taille du bloc
en longs, `de_SizeBlock` = 128, moins une constante) ; pour un bloc de 128 longs :

| Longs (depuis le début) | Octets | Depuis la fin (longs) | Contenu | Écrit par le FS V34 quand… |
|---|---|---|---|---|
| 105, 106, 107 | $1A4, $1A8, $1AC | −23, −22, −21 | **date de modification du répertoire racine** [jours, minutes, ticks] (même position que la date d'un en-tête de fichier/répertoire) | une entrée est créée/supprimée/renommée dans la racine (§5) |
| 118, 119, 120 | $1D8, $1DC, $1E0 | −10, −9, −8 | **date de modification du disque** [jours, minutes, ticks] | le bloc racine est réécrit pour basculer le drapeau bitmap (§5) |
| 121, 122, 123 | $1E4, $1E8, $1EC | −7, −6, −5 | **date de création du volume** [jours, minutes, ticks] = identité du volume | jamais par le FS en fonctionnement normal (formatage/Relabel hors périmètre) |

Rappel du format datestamp : jours depuis le 1-jan-1978, minutes depuis minuit (0..1439), ticks
de 1/50 s dans la minute (0..2999).

### 2.2 Règle de choix [O]

- Le validateur tient un datestamp « **plus récent vu** », initialisé à **[0, 0, 0]**.
- Il le confronte successivement aux longs **105..107**, puis **118..120** du bloc racine : chaque
  fois que le candidat est **strictement plus récent** (comparaison `compstamp` : jours, puis
  minutes, puis ticks, signée), il remplace le « plus récent vu » (copie des 3 longs).
- Résultat : **max(date racine 105..107, date disque 118..120)**, ou [0,0,0] si les deux sont nulles.
- La date de **création** (121..123) n'entre **pas** dans ce calcul.
- Aucun autre bloc (en-têtes de fichiers, sous-répertoires) n'est consulté pour ce maximum.
- Les valeurs ne sont pas validées (plages non contrôlées). [O : pas de test de plage]

---

## 3. Condition de réglage [O]

À la fin **réussie** du validateur (bitmap lu ou reconstruit sans erreur), il :

1. lit l'heure système courante par **datstamp** (globale dos 86 → DateStamp, ce qui rafraîchit au
   passage `rn_Time`) ;
2. **règle l'heure** si et seulement si les trois conditions suivantes sont vraies :

| Condition | Détail |
|---|---|
| **Unité 0** | le numéro d'unité reçu (Arg2 = `fssm_Unit`) vaut 0 → DF0: en pratique ; DF1:…DF3: ne règlent jamais l'heure |
| **Horloge « non réglée »** | **jours** de l'heure courante = **0** (on est encore le 1-jan-1978) ; les minutes/ticks courants ne comptent pas pour ce test |
| **Plus ancienne** | `compstamp(courante, plus_récent_vu) < 0` : l'heure courante est strictement antérieure au maximum du §2.2 |

3. le réglage = **setdatstamp(plus_récent_vu)** (globale dos 128) ; résultat ignoré.

Conséquences :

- **Pas de réglage** si le disque n'est pas DOS, si la validation échoue (« Error validating
  disk »…), si le bitmap est invalide et que le FS a positionné le drapeau Arg4 (abandon), ou si
  les deux dates du bloc racine sont nulles (le maximum [0,0,0] n'est jamais postérieur). [O]
- **Pas une affaire de « premier montage »** : le test est refait à chaque montage sur l'unité 0 ;
  il cesse de réussir dès que l'heure système a jours ≥ 1, c.-à-d. dès qu'elle a été réglée une
  fois (par ce mécanisme, `Date`, `SetClock load`…) **ou** après 24 h de fonctionnement depuis une
  heure système partie de zéro. [O pour le test, D pour l'heure système initiale = 0]
- Jamais de retour en arrière : une heure courante plus récente que le disque n'est pas modifiée. [O]
- L'heure système initiale de timer.device au reset vaut **0 s** (1-jan-1978 00:00:00), d'où
  « jours = 0 » tant que rien ne l'a réglée. [D : cohérent avec la boîte noire `<unset>` ; non
  analysé dans timer.device ici]

---

## 4. Conversion et effets

### 4.1 Conversion vers TR_SETSYSTIME [O, cf. bcpl-runtime §8.4.2]

setdatstamp convertit le datestamp [J, M, T] :

| Champ timer.device | Valeur |
|---|---|
| `tv_secs` (secondes depuis le 1-jan-1978 00:00) | J × 86400 + M × 60 + T / 50 (division entière) |
| `tv_micro` | (T mod 50) × 20000 |

Arithmétique 32 bits signée, sans validation. Requête **TR_SETSYSTIME (11)** sur `timer.device`
unité 0 (UNIT_MICROHZ), sous Forbid, device ouvert et refermé dans l'appel.

### 4.2 Effets observables [O]

| Objet | Effet du réglage |
|---|---|
| Heure système (timer.device) | := date retenue ; elle continue ensuite d'avancer normalement |
| `rn_Time` (RootNode +$08/+$0C/+$10) | rafraîchi **immédiatement** par la relecture interne de setdatstamp (DateStamp) → vaut la date retenue (à quelques ticks près) |
| `dl_VolumeDate` du nœud de volume | **inchangé** par le réglage. Il vaut la **date de création** du bloc racine (longs **121..123**) : le validateur cherche dans la liste DOS un nœud **volume** (dn_Type 2) de **même nom** (BSTR du bloc racine, longs 108.., longueur 1..30) **et** de date **égale** (compstamp = 0) à 121..123 ; à défaut il crée le nœud (makedevnode) et y recopie 121..123 dans `dl_VolumeDate` (`dl_Lock` := 0, dl_Type := 2, `dl_LockList` := 0) ; dans les deux cas le nœud est rattaché au port du FS |
| Bloc racine sur disque | **non écrit** par ce mécanisme |

### 4.3 Rafraîchissement périodique de rn_Time (unité 0) [O appel / D période]

Indépendamment du réglage : le FS dont l'unité vaut **0** appelle **DateStamp** à chaque retour de
sa requête timer périodique, juste avant de la réarmer (requête réarmée avec tv_secs = 1,
tv_micro = 0). Effet : `rn_Time` (le cache) suit l'heure système environ chaque seconde tant que le
handler DF0: tourne. Les FS des autres unités ne le font pas.

---

## 5. Inversement : dates écrites par le FS lors d'une modification [O]

Toutes ces dates sont obtenues par **datstamp** (globale 86 → DateStamp) = **heure système
courante**, sans aucune autre source.

| Événement | Bloc écrit | Champ daté (longs, bloc 128) | Autre effet |
|---|---|---|---|
| Création d'un objet (fichier/répertoire) | nouvel en-tête | 105..107 | — |
| Mise à jour de l'en-tête d'un fichier écrit (taille) — [D] à la fermeture | en-tête du fichier | 105..107 | bit archive (protection, long 80, bit 4) remis à 0 |
| Ajout / retrait d'une entrée dans un répertoire — [D] création, suppression, renommage (pour un renommage entre deux répertoires, les **deux** parents sont datés [O]) | en-tête **du répertoire parent** (= bloc racine si l'objet est à la racine) | 105..107 | bit archive du parent remis à 0 (sans effet visible pour la racine) |
| Première modification d'un disque « propre » (passage à l'état modifié) | **bloc racine** | **118..120** | drapeau bitmap (long 78) := 0 (invalide) |
| Écriture différée du bitmap (fin de la rafale de modifications) | **bloc racine** | **118..120** | drapeau bitmap (long 78) := −1 (valide), pointeurs de pages bitmap (longs 79..) réécrits |

- La date de **création du volume** (121..123) n'est jamais touchée par ces opérations.
- Corollaire : un disque modifié sous une horloge réglée porte en 118..120 (et en 105..107 si la
  racine a changé) l'heure de cette modification ; remis plus tard dans DF0: d'une machine à
  l'horloge non réglée, il lui « donnera » cette heure. C'est le mécanisme d'horloge « au dernier
  disque modifié » de la 1.3. [D]
- Si l'heure système n'est pas réglée, les dates écrites sont proches du 1-jan-1978 (jours = 0) ;
  elles ne peuvent alors jamais faire avancer une autre machine au-delà de jours = 0. [D]

---

## 6. Vecteurs de test (entrée → sortie observable)

Notation : R105 = longs 105..107, R118 = longs 118..120, R121 = longs 121..123 du bloc racine ;
« horloge non réglée » = pas de RTC chargée, pas de SetClock/Date avant le montage. « Date affiche
X » = sortie de `C:Date` sans argument peu après le montage (X + temps écoulé).

| # | Entrée | Sortie attendue |
|---|---|---|
| T1 | Horloge non réglée ; DF0: R105 = D1, R118 = D2, D2 > D1 | Date affiche **D2** ; `rn_Time` ≈ D2 |
| T2 | Idem, D1 > D2 | Date affiche **D1** |
| T3 | Horloge non réglée ; R105 = R118 = [0,0,0] | Date affiche `<unset>` (heure inchangée) |
| T4 | Horloge non réglée ; seul R118 non nul (R105 = 0) | Date affiche R118 |
| T5 | Horloge non réglée ; R121 = D récente, R105 = R118 = 0 | **inchangée** (la date de création n'est pas utilisée) |
| T6 | Horloge non réglée ; disque daté D inséré **seulement dans DF1:** (DF0: vide ou non DOS) | **inchangée** (unité ≠ 0) |
| T7 | Horloge non réglée ; disque non DOS dans DF0: | inchangée |
| T8 | Horloge déjà réglée à C (jours ≥ 1), disque DF0: daté D > C | **inchangée** (C, qui avance) |
| T9 | Horloge déjà réglée à C, disque daté D < C | inchangée |
| T10 | Boot sur disque A (R118 = DA) puis insertion dans DF0: d'un disque B avec R118 = DB > DA | reste sur DA (+ écoulé) : jours ≥ 1 après le premier réglage |
| T11 | Horloge non réglée, D sur le disque avec jours = 0 (ex. 00:05) alors que l'heure courante est 00:10 | inchangée (courante non antérieure) |
| T12 | Horloge non réglée, D = 22-Oct-26 10:22:49 ; puis `SetClock load` (RTC à C) | Date affiche C (SetClock écrase ensuite) |
| T13 | Horloge réglée à T ; créer un fichier à la racine de DF0: puis attendre l'écriture du bitmap | R105 ≈ T (création), R118 ≈ T (deux réécritures du racine, invalide puis valide) ; R121 inchangé ; long 78 = −1 à la fin |
| T14 | Horloge réglée à T ; écrire un fichier dans un sous-répertoire | R105 **inchangé** (seul l'en-tête du sous-répertoire est daté), R118 ≈ T |
| T15 | Après T1 : `Info`/liste des volumes | date du volume (dl_VolumeDate) = **R121**, pas la date de réglage |

---

## 7. Relecture clean-room

Relu intégralement : ce document ne contient **aucune suite d'instructions 68000** recopiée ou
paraphrasée, aucun extrait de désassemblage, aucun opcode, ni pseudo-code ligne à ligne. Il décrit
des **conditions, valeurs et effets observables**, l'ordre des effets visibles, et des éléments
d'ABI/interopérabilité (champs du bloc racine OFS, champs timer.device, RootNode, DeviceList,
arguments du packet de démarrage). Les adresses ROM ne sont que des repères d'analyse. La ROM n'a
été ni modifiée ni copiée (désassemblage temporaire dans le répertoire scratch de session).
