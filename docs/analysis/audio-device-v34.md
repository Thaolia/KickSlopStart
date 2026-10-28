# audio.device 34.1 — spec comportementale

> Piste **ANALYSE** (« dirty »). Sources : ROM `assets/kick34005.A500` (lecture seule, radare2, base
> `$FC0000` ; notes de désassemblage hors dépôt) et sonde boîte noire `tests/audio_probe.s` (harnais
> `tests/audio_probe.sh`) exécutée sur la **vraie ROM** sous FS-UAE (A500 PAL, 512 Ko chip + 512 Ko
> slow, OpenAL forcé sur son pilote `null`).
> Ce document décrit des **comportements**, des **valeurs**, des **ordres d'opérations** et des
> **layouts d'ABI**. Il ne contient aucune suite d'instructions de la ROM ni adresse de routine.
> Spec n° 12 de `coverage-v34.md` (module 13). Usages connus : `octamed-v34.md` §2.5 (allocation des
> 4 canaux), `monkey-startup.md` (vecteur `$70` écrasé directement, audio.device ne voit plus rien).
>
> **Niveaux de preuve** : **[O]** observé par la sonde sur la vraie ROM · **[D]** déduit de la lecture
> du code de la ROM (comportement, pas de code) · **[S]** supposition raisonnable, non vérifiée.
>
> Unité de temps des mesures : **la ligne** (64 µs PAL ; horloge de sonde = trames VERTB × 313 + ligne
> courante). Échantillon de référence : 1000 octets, période 400 ⇒ un passage = 400 000 tops Paula
> ≈ **1761 lignes** (mesuré sur Paula seule, §8.1).

## 0. Résumé pour l'implémenteur

- Module résident `audio.device`, version 34, révision 1, chaîne d'ID `"audio 34.1 (18 Aug 1987)\r\n"`,
  RTF_AUTOINIT|RTF_COLDSTART, priorité 40, base de **634 octets** (dataSize), **6 vecteurs** standard
  (Open, Close, Expunge, réservé, BeginIO, AbortIO). Pas d'unités : le numéro d'unité et les flags
  d'OpenDevice sont **ignorés**. [D]
- **Allocation** = choix d'une combinaison de canaux dans `ioa_Data[0..ioa_Length-1]` (octets, masques
  4 bits) selon la **priorité `ln_Pri`** de la requête ; un canal libre est toujours préféré, un canal
  occupé n'est volé que si sa **précédence est strictement inférieure** à `ln_Pri` ; parmi les
  combinaisons possibles, celle qui fait le **moins de dégâts** (niveau de précédence volé le plus bas)
  puis la **première dans le tableau**. Résultat : `io_Unit` = masque, `ioa_AllocKey` = clé. [D][O]
- **Toutes les autres commandes** vérifient, canal par canal, que la clé du canal = `ioa_AllocKey` ;
  sinon `ADIOERR_NOALLOCATION` (−10) et le canal est retiré de `io_Unit`. [D][O]
- **CMD_WRITE** ne sert que le **canal le plus bas** de `io_Unit` ; file par canal ; la requête suivante
  est chargée dans AUDxLC/AUDxLEN au **début du dernier cycle** de la courante ⇒ **enchaînement sans
  trou** ; une requête est rendue au début du bloc suivant (≈ N passages après son démarrage). [D][O]
- `ioa_Cycles = 0` = boucle infinie (l'interruption du canal est coupée ; seul FINISH/FLUSH/… arrête). [D][O]
- **Bogue V34 majeur** : **ADCMD_WAITCYCLE sur un canal en lecture ne rend jamais la requête** et
  corrompt la liste interne des réponses (§5.13) ; sur un canal inactif il est rendu tout de suite. [D][O]
- Codes produits : −2 (IOERR_ABORTED), −10, −11 (ALLOCFAILED), −12 (CHANNELSTOLEN). **IOERR_NOCMD
  n'est jamais produit** (le code existe mais est inatteignable) ; une commande inconnue avec
  `io_Unit = 0` est rendue sans erreur. [D][O]
- Matériel : interruptions AUD0–3 (bits INTENA/INTREQ 7–10, niveau 4) par **SetIntVector** (pas de
  chaînage), DMACON bits 0–3 seulement (jamais DMAEN), ADKCON seulement **effacé** (bits de modulation
  liés au canal) ; ni filtre, ni contrôle de période, ni contrôle de chip RAM. [D][O]

## 1. Module, initialisation, Open/Close/Expunge

### 1.1 ROMTag et base [D]

| Élément | Valeur |
|---|---|
| Nom (ln_Name de la base et des Interrupt) | `"audio.device"` |
| ln_Type base | 3 (NT_DEVICE) ; lib_Flags = 6 (SUMUSED\|CHANGED) |
| Version / révision | 34 / 1 |
| ROMTag : flags, pri, type | `$81` (AUTOINIT\|COLDSTART), 40, NT_DEVICE |
| dataSize (taille positive) | 634 octets = en-tête Library + données privées + 4 blocs canal |
| Vecteurs | 6, format table de WORD relatifs |

La structure privée de la base est libre pour une réimplémentation ; le modèle de données nécessaire est
au §3.

### 1.2 Initialisation (appelée par InitResident) [D]

Dans l'ordre :
1. DMACON := `$000F` (coupe le DMA des 4 canaux, sans toucher DMAEN).
2. Trois listes vides : réponses en attente, requêtes LOCK, requêtes ALLOCATE en attente.
3. Une **interruption logicielle** (Interrupt NT_INTERRUPT, nom `"audio.device"`, pri 0, is_Data = liste
   des réponses) qui rend (ReplyMsg) toutes les requêtes de la liste des réponses.
4. Pour chaque canal n = 0..3 : listes vides (file d'écriture, file WAITCYCLE) ; une structure Interrupt
   (NT_INTERRUPT, nom `"audio.device"`, pri 0, is_Data = bloc du canal) installée par
   **SetIntVector(7 + n)** ; l'**ancien vecteur est mémorisé** (rendu par Expunge) ; masque DMA = 1 << n ;
   masque d'interruption = `$80` << n ; clé du canal = `$FFFF` (aucun propriétaire) ; précédence =
   **−129** (valeur sentinelle « libre », inférieure à toute ln_Pri) ; puis **remise à zéro du canal**
   (§5.1 : AUDxPER := 1, AUDxVOL := 0, ADKCON nettoyé).
5. Compteur de clés = 0. **INTENA n'est pas touché** à l'init (les bits AUDx restent coupés). [D][O : ie
   = `$4000` hors lecture]

### 1.3 OpenDevice [D][O]

- Incrémente lib_OpenCnt, puis transforme la requête en **ADCMD_ALLOCATE** : `io_Command := $20`,
  `io_Flags := ADIOF_NOWAIT | IOF_QUICK` (`$41`), appel du **BeginIO du device via io_Device**, puis
  **WaitIO** ; ensuite `io_Flags := 0`. Les champs fournis par l'appelant (`ln_Pri`, `ioa_AllocKey`,
  `ioa_Data`, `ioa_Length`) sont utilisés tels quels. [D]
- Succès : efface le drapeau « expunge différé ». `io_Command` **reste à `$0020`**, io_Flags = 0. [O T1/T2]
- Échec (`io_Error ≠ 0`) : appelle **Close** sur la requête (§1.4) ⇒ `io_Device := −1`, OpenCnt
  re-décrémenté ; exec renvoie l'erreur en D0. Exemple observé : D0 = `$FFFFFFF5`, io_Error = `$F5`,
  io_Unit = 0, AllocKey = 0, io_Device = `$FFFFFFFF`. [O T2c]
- `ioa_Length = 0` : succès immédiat **sans allocation** ; une clé est quand même attribuée si
  `ioa_AllocKey` valait 0 (première clé du système = **1**). Au retour d'OpenDevice, io_Unit = 0 (valeur
  d'entrée `$55` perdue — cf. Points non tranchés). [O T1]
- Combinaisons `{1,2,4,8}` pri 0 sur device vierge ⇒ io_Unit = 1, clé 2 ; puis `{1,2}` pri 0 ⇒ io_Unit
  = 2, clé 3 ; puis `{1}` pri 0 ⇒ échec −11 (canal 0 à précédence 0, égalité ⇒ pas de vol). [O T2]
- Cas limite : si la combinaison choisie contient un canal **verrouillé**, l'ALLOCATE est mis en file
  **malgré ADIOF_NOWAIT** (§4.4) ⇒ OpenDevice bloque dans WaitIO jusqu'à libération. [D]

### 1.4 CloseDevice [D][O]

1. Sauve l'octet bas de io_Command, io_Flags et io_Error.
2. `io_Unit := $F`, `io_Command := ADCMD_FREE`, **DoIO** (seuls les canaux dont la clé = celle de la
   requête sont libérés ; les autres donnent −10, ignoré).
3. Restaure io_Command (octet bas étendu à un mot), io_Flags, io_Error ; **io_Device := −1**.
4. lib_OpenCnt−− ; s'il tombe à 0 **et** qu'un expunge est différé ⇒ Expunge ; sinon renvoie 0.
Observé : après Close, io_Device = `$FFFFFFFF`, io_Command = `$0020` (restauré), et le canal 0 qu'elle
possédait est ré-allouable par une requête de pri −128. [O T16]

### 1.5 Expunge [D]

OpenCnt ≠ 0 ⇒ positionne « expunge différé », renvoie 0. Sinon : pour chaque canal, SetIntVector(7+n,
ancien vecteur mémorisé), Remove de la base, FreeMem(base − NegSize, NegSize + PosSize), renvoie le
seglist reçu à l'init (0 pour le résident ROM).

## 2. Structure IOAudio (ABI, `devices/audio.h`)

| Off. | Taille | Champ | Usage par la V34 |
|---:|---:|---|---|
| 0 | 14 | Node (ln_Pri en +9) | **ln_Pri** = priorité d'allocation (octet signé) et valeur de SETPREC |
| 14 | 4 | mn_ReplyPort | port de réponse |
| 20 | 4 | io_Device | mis à −1 par Close |
| 24 | 4 | io_Unit | **masque de canaux** (bits 0–3) ; **doit être ≤ 15** (§5.0) |
| 28 | 2 | io_Command | |
| 30 | 1 | io_Flags | IOF_QUICK (bit 0), ADIOF_PERVOL `$10`, ADIOF_SYNCCYCLE `$20`, ADIOF_NOWAIT `$40`, ADIOF_WRITEMESSAGE `$80` |
| 31 | 1 | io_Error | 0 au début de chaque BeginIO |
| 32 | 2 | ioa_AllocKey | clé ; 0 ⇒ une clé neuve est attribuée à l'allocation |
| 34 | 4 | ioa_Data | ALLOCATE : tableau d'octets-masques ; WRITE : échantillon (chip, **pair**) ; READ : rendu |
| 38 | 4 | ioa_Length | ALLOCATE : nombre de combinaisons ; WRITE : longueur en octets |
| 42 | 2 | ioa_Period | WRITE/PERVOL |
| 44 | 2 | ioa_Volume | WRITE/PERVOL (0–64) |
| 46 | 2 | ioa_Cycles | WRITE : nombre de passages, 0 = infini |
| 48 | 20 | ioa_WriteMsg | Message rendu au démarrage si ADIOF_WRITEMESSAGE |
| | 68 | taille totale | |

Période et volume sont lus **ensemble en un mot long** (Period puis Volume, contigus) et écrits d'un seul
accès long dans AUDxPER puis AUDxVOL : l'ordre des deux champs est donc contractuel. [D]

## 3. Modèle de données (ce qu'une réimplémentation doit garder) [D]

Par canal : clé propriétaire (`$FFFF` = libre), précédence (mot signé, −129 = libre), file d'écriture
(FIFO), file WAITCYCLE, requête **courante** (celle que Paula joue), requête **armée** (celle dont
LC/LEN sont dans Paula ; égale à la courante pendant sa lecture), compteur de cycles restant, drapeau
« arrêté » (CMD_STOP), drapeau « WAITCYCLE en attente », état de l'automate d'interruption (§6).
Global : masque des canaux verrouillés, liste des LOCK, file des ALLOCATE en attente (triée par ln_Pri,
`Enqueue`), liste des réponses + interruption logicielle, compteur de clés (mot).

**Clés** : à chaque attribution, compteur + 1 ; s'il devient ≤ 0 il repart à 1 ⇒ clés 1..32767, jamais
0 ni `$FFFF`. Une clé n'est attribuée que si `ioa_AllocKey = 0` **et** que l'ALLOCATE réussit (ou que
`ioa_Length = 0`) ; une requête qui garde une clé non nulle la réutilise. Conséquence V34 : une requête
portant la clé `$FFFF` « possède » tous les canaux libres (non sondé). [D][O : clés 1,2,3,4,5,… ;
échec ⇒ clé 0 laissée]

## 4. ADCMD_ALLOCATE (`$20`)

### 4.1 Choix de la combinaison [D][O]

1. `ioa_Length = 0` ⇒ succès immédiat, `io_Unit` **inchangé**, clé attribuée si nulle. [O T15 : u = `$33`
   conservé, k = `$000A`]
2. Sinon `io_Unit := 0`, puis on classe les canaux par précédence : niveau 0 = canaux libres (−129),
   puis niveaux croissants des précédences distinctes des canaux alloués.
3. Niveau maximal utilisable = le plus haut niveau dont la précédence est **strictement < ln_Pri**
   (le niveau « libre » l'est toujours). Si aucune combinaison n'est un sous-ensemble des canaux des
   niveaux ≤ maximum ⇒ **échec** (§4.3).
4. Sinon on cherche le **plus petit niveau** j pour lequel une combinaison tient dans les canaux de
   niveau ≤ j, et on prend la **première** combinaison du tableau qui y tient.
Observé (T3) : pri 10 vole un canal de précédence 0 ; `{3, C}` pri 20 avec 2 et 3 libres ⇒ **C** ;
`{1, 2}` pri 15 avec canal 0 à 10 et canal 1 à 0 ⇒ **2** (moindre dégât) ; `{1}` pri 15 vole le 10 ;
`{2}` pri 15 contre précédence 15 ⇒ **échec −11**. [O]
Une combinaison 0 tient toujours ⇒ succès avec io_Unit = 0 (non sondé). [D]

### 4.2 Succès [D][O]

Si aucun canal choisi n'est verrouillé : `io_Unit := combinaison` (étendue à 32 bits), clé attribuée si
nulle, puis pour **chaque canal** du masque (du plus bas au plus haut) : **remise à zéro du canal**
(§5.1 : les écritures de l'ancien propriétaire sont rendues, cf. FLUSH), précédence := ln_Pri, clé :=
ioa_AllocKey. Le vol est **silencieux** pour l'ancien propriétaire : ses commandes suivantes rendent
−10 (`io_Unit := 0` pour WRITE). [O T3b : −10 immédiat] Effet ADKCON observé : `$FF` ⇒ `$EE` après
allocation du canal 0, puis `$88` après le canal 2. [O T5]

### 4.3 Échec [D][O]

- **ADIOF_NOWAIT** ⇒ io_Error := **ADIOERR_ALLOCFAILED (−11, `$F5`)**, io_Unit = 0, rendu. [O]
- Sans NOWAIT ⇒ la requête est **Enqueue**-ée (par ln_Pri) dans la file d'attente, reste en cours
  (ln_Type = NT_MESSAGE, IOF_QUICK effacé). [O T14 : p = 1]
- **Ré-essai** de toute la file, dans l'ordre de la liste, après chaque **ADCMD_FREE** et chaque
  **ADCMD_SETPREC** (donc aussi CloseDevice) — et seulement là. Pendant son ré-essai une requête porte
  io_Error = 1 (marqueur interne) ; succès ⇒ io_Error := 0, retirée et rendue ; si AbortIO l'a marquée
  −2 entre-temps ⇒ retirée et rendue avec −2 ; échec et NOWAIT ⇒ −11, rendue ; sinon elle reste
  en file **avec io_Error = 1** (le marqueur n'est pas effacé). [D]
  Observé : après SETPREC −100 du propriétaire (pri 50), une requête pri 0 en attente obtient le canal. [O T14]

### 4.4 Canal verrouillé dans la combinaison choisie [D][O]

Rien n'est alloué. Toute requête **LOCK** en cours dont io_Unit touche un des canaux verrouillés visés est
retirée et rendue avec **ADIOERR_CHANNELSTOLEN (−12, `$F4`)**, io_Unit inchangé ; l'ALLOCATE est mis en
file **même avec ADIOF_NOWAIT** (il n'échoue pas). Le bit « verrouillé » du canal **reste posé** jusqu'à
un ADCMD_FREE du propriétaire, qui relance la file : l'ALLOCATE obtient alors le canal.
Observé T13 : LOCK (pri 0) en cours, ALLOCATE pri 50 NOWAIT ⇒ en cours, LOCK rendu −12 u = 8 ; FREE du
propriétaire ⇒ ALLOCATE rendu 0, u = 8. [O]

## 5. Autres commandes

### 5.0 Cadre commun de BeginIO [D][O]

- `io_Error := 0` ; tout BeginIO s'exécute sous **Forbid** (Permit à la fin).
- ALLOCATE (`$20`) : §4. Toute autre commande : parcours des canaux de `io_Unit`, **du bit le plus bas
  au plus haut**. `io_Unit` sert d'index dans une table de 16 entrées : **une valeur > 15 sort de la
  table (comportement indéfini)**. `io_Unit = 0` ⇒ aucun canal traité, requête rendue sans erreur, quelle
  que soit la commande (y compris inconnue). [D][O T15 : cmd `$1F`, u = 0 ⇒ e = 0]
- Clé fausse sur un canal : io_Error := −10, bit du canal retiré de io_Unit, puis selon la commande :
  READ, WRITE, LOCK, WAITCYCLE ⇒ `io_Unit := 0` et fin (rendue) ; UPDATE, CLEAR, STOP, FLUSH,
  FINISH, PERVOL ⇒ canal ignoré, on continue ; START, FREE, SETPREC ⇒ on continue, et si c'était le
  dernier canal l'action finale de la commande (DMACON groupé, relance des allocations) a quand même
  lieu ; **CMD_RESET avec clé fausse saute hors de la table d'aiguillage** (indéfini, ne pas reproduire :
  rendre −10). [D]
- Commande 0 (CMD_INVALID) ou 15..31, `$21`.. avec un canal valide : aiguillage hors table, indéfini ;
  une réimplémentation rendra IOERR_NOCMD. [D]
- Fin : les réponses accumulées par d'autres requêtes (liste interne) sont rendues avant le retour ;
  puis la requête elle-même est rendue par ReplyMsg **sauf si IOF_QUICK** ; une requête qui reste en
  cours (WRITE, LOCK, WAITCYCLE en lecture, ALLOCATE en attente) reçoit ln_Type = NT_MESSAGE et
  IOF_QUICK effacé.

### 5.1 CMD_RESET (1) — remise à zéro d'un canal [D][O]

Pour chaque canal : SetIntVector(7+n) **réinstallé** (le handler d'audio.device reprend le vecteur même
si un programme l'avait remplacé) ; **FLUSH** du canal (§5.7) ; **AUDxPER := 1 et AUDxVOL := 0** (un
seul accès long) ; **ADKCON := masque sans bit SET**, masque selon le canal : 0 ⇒ `$11`, 1 ⇒ `$33`,
2 ⇒ `$66`, 3 ⇒ `$CC` (bits USEnVm/USEnPm où le canal est modulateur ou modulé) ; drapeau « arrêté »
effacé. Ne désalloue pas. La même remise à zéro est faite à l'init, à l'allocation et au FREE. [O T5 pour
ADKCON]

### 5.2 CMD_READ (2) [D][O]

Canal le plus bas seulement : `io_Unit := masque du canal`, **`ioa_Data := requête WRITE courante`** (NULL
si inactif), rendue aussitôt. [O T7 : pendant A, ioa_Data = &A ; après, 0]

### 5.3 CMD_WRITE (3) [D][O]

Canal le plus bas seulement ; `io_Unit := masque du canal`. Requête **jamais rendue par BeginIO**.
- Si le canal a déjà une requête armée ⇒ ajout en **fin de file** (FIFO).
- Sinon : **AUDxLEN := ioa_Length / 2** (division entière ; 0 ⇒ 65536 mots pour Paula ; ≥ 131072
  tronqué), **AUDxLC := ioa_Data**, compteur := ioa_Cycles, requête armée. Puis :
  - si une requête courante joue encore (dernier cycle en cours) **ou** si le canal est arrêté : rien
    d'autre (l'interruption de début de bloc suivante prendra le relais ; canal arrêté ⇒ attend START) ;
  - sinon **démarrage à froid** : si INTENAR n'a pas le bit du canal : INTREQ := bit (acquitte) puis
    INTENA := SET|bit ; si ADIOF_PERVOL : **AUDxPER := 1** ; **AUDxDAT := premier octet de l'échantillon
    recopié dans les deux moitiés du mot** (lecture d'un mot à ioa_Data ⇒ adresse paire obligatoire). Le
    DMA n'est **pas** encore allumé : Paula, en mode manuel, joue ce mot très vite (période 1) et lève
    l'interruption, dont le handler allume le DMA (§6).
- Sans ADIOF_PERVOL, la période/volume restent ceux du canal (après remise à zéro : **période 1, volume
  0**) : la première écriture d'un canal doit donc porter ADIOF_PERVOL. [D]
- Période/volume (ADIOF_PERVOL) appliqués **au début du bloc** de la requête (interruption DMA), donc à
  sa première note, y compris pour une requête enchaînée. [D]
- ADIOF_WRITEMESSAGE : `ioa_WriteMsg` est rendu (ReplyMsg, via son propre mn_ReplyPort) **quand la
  requête commence à jouer**. [D]
- **Rendu** : quand la requête suivante démarre (même interruption), ou s'il n'y en a pas, à
  l'interruption qui suit la fin du dernier passage : DMA et interruption du canal coupés, puis rendu.
  io_Error = 0. Mesures (T6) : cycles 1 ⇒ **1773** lignes, 2 ⇒ **3536**, 4 ⇒ **7060** (≈ N × 1761 +
  ≈ 12) ; pendant la lecture DMACONR = `$0201`, INTENAR = `$4080` ; après, `$0200` / `$4000`. [O]
- **Enchaînement** : A (1 cycle) puis B (1 cycle) envoyés d'affilée ⇒ A rendu à **1791**, B à **3536**,
  exactement la durée de A en 2 cycles : pas de trou. [O T7]
- `ioa_Cycles = 0` : boucle infinie, **INTENA du canal coupé** dès le début (aucune interruption ensuite) ;
  observé ie = `$4000`, DMA actif, requête toujours en cours après 6000 lignes. [O T11]

### 5.4 CMD_UPDATE (4), CMD_CLEAR (5) [D]

Aucun effet (hors contrôle de clé). Rendues.

### 5.5 CMD_STOP (6) [D][O]

Pour chaque canal : drapeau « arrêté », **INTENA := bit du canal (effacement)**, puis **DMACON := bit du
canal (effacement)**. Les requêtes restent en place. Observé : DMACONR `$0200`, INTENAR `$4000`, la
requête n'avance plus (en cours après 6000 lignes). Un WRITE sur canal arrêté est armé (LC/LEN écrits)
mais ne démarre pas. [O T12]

### 5.6 CMD_START (7) [D][O]

Pour chaque canal : efface « arrêté » ; si le canal a une requête courante ou armée : ajoute son bit au
masque DMA et, si INTENAR n'a pas le bit, INTREQ := bit puis INTENA := SET|bit. Après le **dernier**
canal : **un seul DMACON := SET | masque** (départ simultané). Paula **repart du début** de l'échantillon
armé (LC/LEN), et l'interruption de redémarrage **consomme un cycle** : A (2 cycles) arrêté à 500 lignes
puis relancé à ≈ 6520 est rendu à **8383** (= reprise + un passage entier). STOP puis WRITE puis START ⇒
rendu à 1771 après START. [O T12]

### 5.7 CMD_FLUSH (8) [D][O]

Pour chaque canal, sous Disable :
1. si une requête est armée : la **suivante de la file** est chargée dans LC/LEN (comme à une fin de
   cycle) ; l'ancienne armée, si elle n'était pas la courante, est rendue avec −2 ;
2. la courante est coupée : s'il n'y a rien d'armé (ou canal arrêté) ⇒ DMACON := bit, INTENA := bit,
   courante rendue (io_Error 0) ; sinon DMA coupé et redémarrage par l'automate (§6, état
   « redémarrage ») ⇒ la courante est rendue (io_Error **0**) quand la suivante démarre ;
3. toutes les requêtes **restant** en file d'écriture ⇒ io_Error −2, rendues ; drapeau WAITCYCLE effacé ;
   file WAITCYCLE ⇒ −2, rendues.
**Particularité V34** : la première requête en file n'est **pas** annulée, elle est promue et joue en
entier. Observé (T10) : A (5 cycles) + B (2 cycles), FLUSH à ≈ 330 ⇒ FLUSH rendu à 330, **A rendu
e = 0 à 1777**, **B rendu e = 0 à 5302** (deux passages). [O]

### 5.8 ADCMD_FREE (9) [D][O]

Pour chaque canal : remise à zéro (§5.1), clé := `$FFFF`, précédence := −129. Après le dernier canal :
si des canaux libérés étaient verrouillés, leurs bits sont ôtés du masque de verrouillage et de
l'io_Unit de chaque LOCK en cours ; un LOCK dont io_Unit tombe à 0 est rendu (io_Error 0, io_Unit 0)
[O T13] ; **`io_Unit := 0`** [O T4] ; puis relance de la file d'ALLOCATE (§4.3). Canal d'un autre
propriétaire ⇒ −10. [O T4]

### 5.9 ADCMD_SETPREC (10) [D][O]

Pour chaque canal : précédence := ln_Pri de la requête. Après le dernier : relance de la file
d'ALLOCATE. [O T14]

### 5.10 ADCMD_FINISH (11) [D][O]

Pour chaque canal, sous Disable : comme l'étape 1 de FLUSH (la suivante de la file est armée, la file
n'est pas vidée), puis :
- **ADIOF_SYNCCYCLE** : la courante finit **à la fin de son passage en cours** (l'interruption du canal
  est ré-autorisée si besoin). Observé sur cycles infinis : FINISH à 6104, requête rendue à **7060**
  (fin du 4ᵉ passage). [O T11]
- sans SYNCCYCLE : coupure immédiate (même traitement que l'étape 2 de FLUSH). Observé, rien en file :
  rendue **81 lignes** après FINISH, DMA et interruption coupés. [O T11]
La requête FINISH est rendue aussitôt ; la requête écrite rendue garde io_Error = 0. [O]

### 5.11 ADCMD_PERVOL (12) [D]

Pour chaque canal : si **ADIOF_SYNCCYCLE** et que le canal est dans l'état « comptage de cycles » (§6) :
ioa_Period/ioa_Volume mémorisés, l'automate passe dans l'état « PERVOL différé » et l'interruption du
canal est autorisée si besoin ⇒ AUDxPER/AUDxVOL écrits **au début du bloc suivant**, ce début comptant
comme un cycle. Sinon : AUDxPER puis AUDxVOL écrits immédiatement (accès long). Rendu aussitôt.
(Registres en écriture seule : non observé.)

### 5.12 ADCMD_LOCK (13) [D][O]

Clé contrôlée sur **tous** les canaux (une seule clé fausse ⇒ −10, io_Unit 0, rendu) ; ensuite masque
de verrouillage |= io_Unit, requête ajoutée à la liste des LOCK, **reste en cours**. Rendue par : FREE de
tous ses canaux (io_Error 0, io_Unit 0) ; tentative de vol par une allocation plus prioritaire
(−12, io_Unit inchangé, §4.4) ; AbortIO (−2). [O T13]

### 5.13 ADCMD_WAITCYCLE (14) — bogue [D][O]

Canal le plus bas seulement, `io_Unit := masque`. Canal **inactif** ⇒ rendu immédiatement, io_Error 0
[O T8]. Canal **en lecture** ⇒ drapeau WAITCYCLE, ajout à la file WAITCYCLE du canal, interruption
autorisée ; à l'interruption suivante, la V34 veut transférer cette file dans la liste des réponses mais
prend le **premier élément de la file pour l'en-tête de liste** : la liste des réponses est corrompue
(pointeurs pris dans les octets ln_Type/ln_Pri/ln_Name de la requête). Observé (T17) : WAITCYCLE pendant
un WRITE de 3 cycles ⇒ **ni le WAITCYCLE ni le WRITE ne sont jamais rendus** (8000 lignes) ; lors d'une
première passe, les tests suivants étaient pollués. Une réimplémentation fera le comportement voulu :
rendre les WAITCYCLE à la fin du cycle en cours (interruption suivante). Un FLUSH/RESET les rend avec −2. [D]

## 6. Automate d'interruption par canal (niveau 4) [D][O]

Le handler (Interrupt de SetIntVector, is_Data = canal) reçoit A0 = `$DFF000`. États :

| État | À l'interruption |
|---|---|
| **Démarrage** (après démarrage à froid §5.3, ou coupure avec suite armée) | INTREQ := bit (acquit), **DMACON := SET\|bit** ; passe à « Début de bloc » |
| **Début de bloc** (la requête armée vient d'être chargée par Paula) | si ADIOF_PERVOL : AUDxPER/AUDxVOL := ioa_Period/ioa_Volume ; l'ancienne courante est mise dans les réponses (io_Error inchangé) ; courante := armée ; si ADIOF_WRITEMESSAGE : ioa_WriteMsg mis dans les réponses ; puis **enchaîne immédiatement** sur « Comptage » |
| **Comptage** | compteur − 1 : > 0 ⇒ acquit ; = 0 ⇒ **charge la suivante** (AUDxLEN, AUDxLC, compteur := ses cycles, armée := elle, retirée de la file, état « Début de bloc ») ou, file vide, armée := aucune et état « Fin » ; puis acquit. Compteur déjà 0 (cycles infinis) ⇒ reste 0, **INTENA := bit (coupe)**, acquit |
| **Fin** | **DMACON := bit (coupe), INTENA := bit (coupe)**, courante mise dans les réponses, courante := aucune ; **pas d'acquit INTREQ** (l'interruption est masquée ; le prochain démarrage à froid acquitte avant d'autoriser) |
| **PERVOL différé** | AUDxPER/AUDxVOL := valeurs mémorisées puis enchaîne sur « Comptage » |

Fin commune : si le drapeau WAITCYCLE est posé ⇒ transfert de la file WAITCYCLE (bogue §5.13) et
**Cause** de l'interruption logicielle ; sinon si la liste des réponses n'est pas vide ⇒ **Cause**. Les
ReplyMsg ne sont donc jamais faits au niveau 4 : ils le sont par l'interruption logicielle (retrait de
chaque nœud sous Disable, ReplyMsg hors Disable) ou, depuis BeginIO/AbortIO, directement avant le retour.
Le compteur est décrémenté dès le début du premier bloc : avec N cycles, la suivante est chargée au début
du N-ième passage, d'où le rendu à ≈ N passages (§5.3). [O]

## 7. AbortIO [D][O]

Canal visé = le plus bas de `io_Unit & $F`. Selon io_Command :
- WAITCYCLE (14) : retrait de la file WAITCYCLE de ce canal ; LOCK (13) : de la liste des LOCK ;
  ≥ `$20` : de la file d'ALLOCATE. Trouvée ⇒ retirée et rendue, **io_Error := −2** ; si elle porte
  le marqueur 1 (ré-essai en cours), elle est seulement marquée −2 et c'est le ré-essai qui la rend. [O T14 : ALLOCATE en attente ⇒ −2, io_Unit 0]
- ≤ 3 (WRITE) : sous Disable ; si c'est la requête **armée** ⇒ traitement de l'étape 1 de FLUSH ; si c'est
  la **courante** ⇒ coupure comme l'étape 2 de FLUSH ⇒ rendue avec **io_Error 0** (pas −2) quand la
  suivante démarre, ou tout de suite s'il n'y a pas de suite ; sinon recherche dans la file d'écriture ⇒
  −2. Observé (T9) : A (5 cycles) + B + C, AbortIO(C) à 327 ⇒ **−2** immédiat ; AbortIO(A) ⇒ A rendu
  **e = 0 à 1783**, B rendu à 3539 (un passage). [O]
- 4..12 : aucun effet.
Toujours : les réponses accumulées sont rendues avant le retour. AbortIO ne renvoie pas de valeur
significative. [D]

## 8. Registres matériels : ordres d'écriture et acquittements

### 8.1 Oracle Paula seule (sans audio.device) [O T0]

AUD0 1000 octets, période 400, interruption masquée, scrutation d'INTREQR : DMA allumé ⇒ INTREQ bit 7 à
**1 ligne** (chargement initial), puis à **1761** et **3523** (rechargements = début de chaque bloc).
Démarrage manuel : AUD0DAT écrit avec AUD0PER = 1, DMA éteint ⇒ INTREQ à 1 ligne ; DMA allumé ensuite ⇒
INTREQ à 22 lignes, puis 1745, 3507. L'interruption marque donc le **début** d'un bloc (LC/LEN déjà
copiés : on peut y écrire le bloc suivant).

### 8.2 Récapitulatif des accès d'audio.device [D]

| Registre | Écritures |
|---|---|
| DMACON | init `$000F` ; STOP/Fin/coupure : bit du canal sans SET ; démarrage : SET\|bit ; START : SET\|masque groupé. Jamais DMAEN ni autre bit. |
| INTENA | SET\|bit avant tout démarrage (si INTENAR ne l'a pas déjà, précédé de INTREQ := bit) ; bit sans SET à STOP, à Fin et en cycles infinis |
| INTREQ | bit du canal (acquit) en fin de chaque interruption sauf l'état Fin ; avant d'autoriser |
| AUDxLC / AUDxLEN | WRITE : **LEN d'abord, puis LC** (au démarrage à froid comme à l'enchaînement) |
| AUDxPER / AUDxVOL | accès long (PER puis VOL) : remise à zéro (1, 0), début de bloc avec PERVOL, PERVOL ; AUDxPER seul := 1 au démarrage à froid avec PERVOL |
| AUDxDAT | démarrage à froid : premier octet dupliqué |
| ADKCON | remise à zéro de canal : effacement `$11`/`$33`/`$66`/`$CC` ; jamais de SET (les modulations sont à la charge du programme) |
| Lus | INTENAR (bit du canal) uniquement |

### 8.3 Vecteurs d'interruption [D]

SetIntVector(INTB_AUD0..3 = 7..10), sans chaînage vers l'ancien vecteur ; réinstallés à chaque remise à
zéro de canal. Un programme qui écrit directement le vecteur 68000 `$70` (cf. monkey-startup) court-
circuite exec et audio.device.

## 9. Ce qui diffère sur un vrai A500

- **Filtre** : audio.device ne touche jamais la CIA-A (bit 1 de PRA, LED/filtre). [D]
- **Période** : aucune borne. Le HRM fixe un minimum de **124** pour le DMA (sinon Paula ne peut pas
  être alimentée à temps : échantillons répétés/sautés) ; la V34 transmet ioa_Period tel quel. La période
  1 écrite au démarrage à froid sert au mode manuel (DMA éteint) et n'est pas concernée. [D][S]
- **Chip RAM** : non vérifiée ; un échantillon en fast/slow RAM est lu par le DMA à la même adresse
  (son faux). Une adresse **impaire** provoque une erreur d'adresse 68000 au démarrage à froid (lecture
  d'un mot). [D]
- **Coupure de DMA en cours de bloc** (FLUSH, FINISH sans SYNCCYCLE, AbortIO de la courante, avec une
  suite armée) : la V34 compte sur l'interruption « mode manuel » que Paula lève après le mot en cours
  quand AUDxEN tombe. Sous FS-UAE cette interruption n'est arrivée qu'à la fin théorique du bloc
  (rendus à ≈ 1780 au lieu de ≈ 330) ; sur vrai matériel elle devrait suivre de quelques lignes. [O][S]

## 10. Points non tranchés

1. **Délai de coupure sur vrai Paula** (§9, dernier point) : FS-UAE rend la courante coupée à la fin de
   son passage ; le comportement réel (interruption quasi immédiate selon l'automate HRM) n'est pas
   mesuré. Une réimplémentation doit seulement reproduire l'ordre : courante rendue (0), puis suivante.
2. **io_Unit après OpenDevice avec ioa_Length = 0** : observé 0 alors que BeginIO direct le laisse
   inchangé ; l'écriture vient vraisemblablement de l'OpenDevice d'exec (unité 0), non vérifié.
3. **ADCMD_PERVOL** et la valeur exacte d'AUDxPER/AUDxVOL aux différents moments : registres en écriture
   seule, déduits du code seulement (le débogueur FS-UAE n'a pas été employé).
4. **CMD_RESET avec clé fausse**, commandes 0 et 15..31 sur un canal valide, io_Unit > 15 : sauts hors
   table dans la V34 (non sondés : risque de plantage). À traiter en erreur propre.
5. **WAITCYCLE en lecture** : corruption démontrée par le code et la sonde ; l'étendue exacte des dégâts
   mémoire (adresses écrites) dépend du contenu de la requête et n'a pas été caractérisée.
6. **Clé `$FFFF`** donnant accès aux canaux libres : déduit, non sondé.
7. Période minimale 124 et filtre : tirés du HRM, aucune mesure sur matériel réel.
