# timer.device 1.3 (34.1) et partage des CIA — spec comportementale

> Piste **ANALYSE** (dirty). Sources : ROM `assets/kick34005.A500` (lecture seule ; désassemblage
> temporaire hors dépôt), sonde boîte noire `tests/timerprobe.s` sur la vraie ROM (FS-UAE A500 PAL,
> 512 Ko chip, Workbench 1.3.3). Spécification **comportementale** : ressources, registres matériels,
> valeurs, ordre, conditions, timings. Les adresses ROM sont des repères d'analyse, pas des recettes.
> Légende : **[R]** analyse ROM, **[S]** sonde sur la vraie ROM, **[D]** doc publique (AutoDocs/RKRM/
> includes), **[I]** inféré.
> Complète `keyboard-handshake-v34.md` (ciaa.resource, clavier), `trackdisk-official-timing.md`
> (délais disque), `boot-clock-v34.md` (heure au boot), `monkey-startup.md` §5 (vecteur $78).

---

## 0. Réponse courte

- **UNIT_MICROHZ** = **timer B de CIA-A**, obtenu par `ciaa.resource` **AddICRVector(bit 1 = TB)** ⇒
  interruption **niveau 2 (PORTS)**. Mode **one-shot**, tronçons de **≤ 65535 tops E** (≤ 91 541 µs).
  **Aucune** dépendance au niveau 6 : détourner `$78` ne change rien aux délais [R][S].
- **UNIT_VBLANK** = un **serveur VERTB** (niveau 3, chaîne d'exec, pri 0) ; pas de CIA [R][S].
- **Horloge système** = base logicielle + **TOD de CIA-A** (tic secteur 50/60 Hz) ; résolution 20 ms
  (PAL 50 Hz) + **1 µs ajouté à chaque lecture** ⇒ strictement croissante [R][S].
- Au boot, le système 1.3 n'utilise **aucun timer de CIA-B** et **pas le timer A de CIA-A**. Niveau 6
  (EXTER) : seul le serveur de `ciab.resource` (TOD-alarme pour graphics, FLG/index pour
  disk.resource) [R][S].
- trackdisk : **tous ses délais passent par timer.device unité MICROHZ** (DoIO) ; il a en plus une
  requête **VBLANK** périodique (scrutation du changement de disque) [R].

---

## 1. Ressources CIA et mode des timers

### 1.1 Obtention [R][S]

| Étape (init, ROMTag pri 50, après cia.resource pri 80) | Détail |
|---|---|
| OpenResource(`"ciaa.resource"`) | échec ⇒ Alert **$15058020** (AN_TimerDev\|AG_OpenRes\|AO_CIARsrc) et abandon de l'init |
| MakeLibrary (taille positive $D6) | échec ⇒ Alert **$15020000** |
| ExecBase **Quantum** (+$120) := 16 et **Elapsed** (+$122) := 16 | c'est timer.device, pas exec, qui fixe le quantum de 16 trames |
| **AddIntServer(INTB_VERTB = 5)** | serveur nommé `"timer.device"`, pri 0, is_Data = unité VBLANK |
| INTENA := $8020 | autorise VERTB |
| **AddICRVector(CIAICRB_TB = 1)** sur ciaa.resource | Interrupt nommée `"timer.device"`, LN_PRI 30 (sans effet), is_Data = unité MICROHZ |
| **Valeur de retour d'AddICRVector ignorée** | si le bit était déjà pris, MICROHZ serait muet sans erreur (ne se produit pas au boot : personne d'autre ne le prend) |
| Calibrage secteur (§1.3), puis AddDevice | — |

Le **timer A de CIA-A** et **tout CIA-B** ne sont jamais touchés par timer.device [R : seules écritures
CIA du module = CRB, TBLO, TBHI et TOD de CIA-A].

### 1.2 Mode du timer B de CIA-A [R][S]

| Registre | Valeur / usage |
|---|---|
| CRB ($BFEF01) | **$08** en permanence hors calibrage : RUNMODE = one-shot, INMODE = φ2 (E-clock), START = 0 au repos. Bit 7 (ALARM) = 0 |
| Démarrage d'un tronçon | écriture **TBLO puis TBHI** ($BFE601/$BFE701) : en one-shot, l'écriture de l'octet haut charge le latch et **démarre** le décompte (aucune écriture de CRB) |
| Arrêt | mise à 0 du **seul bit START** de CRB (lecture-modification-écriture) |
| Fin d'un tronçon | sous-dépassement ⇒ ICR bit TB ⇒ PORTS ⇒ serveur de ciaa.resource ⇒ gestionnaire timer.device ; le timer s'arrête de lui-même (one-shot) |
| Valeur de repos observée | TB lu = **$02CB** (= 715 = dernier latch chargé, 1000 µs) : le compteur garde le latch après le sous-dépassement [S] |

Relevé après boot [S] : `CIAA cra.crb = $00/$08`, TA = $FFFF (jamais chargé), masque ICR autorisé
**$0A** (TB + SP). Gestionnaire du bit 1 : `timer.device`, is_Code dans le code de timer.device.

### 1.3 Calibrage de la fréquence secteur (init, sous Disable) [R][S]

1. TOD de CIA-A remis à 0 (écritures heure, puis minute, puis LSB : ce dernier relance le TOD).
2. CRB := $08, TBLO := $FF, TBHI := $FF (l'écriture haute lance un décompte de $FFFF).
3. Attente d'un **changement** de l'octet bas du TOD. Garde-fou : si TBHI passe sous $80 (plus de
   32 768 tops E ≈ 46 ms sans tic TOD) ⇒ Alert **$15000002** (récupérable) puis branche « 60 Hz » sur
   une pile déséquilibrée — cas dégradé, voir §9.
4. CRB := $19 (START | one-shot | LOAD) : décompte depuis $FFFF.
5. Attente du tic TOD suivant (même garde-fou), puis CRB := $08 (arrêt), lecture TBHI:TBLO.
6. Si la valeur lue est **≤ $CCDD** (≥ 13 090 tops E par tic) ⇒ **50 Hz**, sinon **60 Hz**.
   PAL 709 379/50 = 14 188 tops ⇒ 50 ; NTSC 715 909/60 = 11 932 ⇒ 60.
7. Effets : fréquence TOD = 50 ou 60 ; **µs par tic TOD = 20 000 ou 16 667** ;
   **ExecBase->PowerSupplyFrequency (+$213)** := 50 ou 60.

Relevé [S] : `EXEC vbf psf = $32 $32` (VBlankFrequency 50, PowerSupplyFrequency 50).

### 1.4 Niveaux d'interruption résultants

| Unité | Source | Niveau 68000 |
|---|---|---|
| MICROHZ | CIA-A TB → INTREQ PORTS (bit 3) → chaîne de serveurs PORTS → serveur ciaa.resource → vecteur ICR bit 1 | **2** |
| VBLANK + horloge + quantum | INTREQ VERTB (bit 5) → chaîne de serveurs VERTB | **3** |

---

## 2. UNIT_MICROHZ

### 2.1 Conversion temps → tops E [R][S]

- **Constante fixe NTSC** : tops = ⌊µs × 46 918 / 65 536⌋ (46 918/65 536 = 0,715 91 = 715 909 Hz,
  l'E-clock **NTSC**). Le calcul est fait sur le mot bas puis le mot haut (µs ≤ 91 541 ⇒ mot haut 0
  ou 1, qui ajoute 46 918) ; résultat sur 16 bits.
- **Aucune lecture** d'une fréquence E-clock : ni ExecBase->EClockFrequency (inexistant en V34), ni
  VBlankFrequency, ni la fréquence secteur. **Même calcul en PAL** ⇒ en PAL (709 379 Hz) chaque délai
  dure **+0,92 %** de trop.
- Tronçon maximal = **91 541 µs** (⇒ 65 535 tops). Chaque tronçon chargé = min(reste, 91 541) si
  `tv_secs` du nœud de tête = 0, sinon 91 541.
- La comptabilité est **nominale** : à chaque interruption, on retranche la durée du tronçon **en µs
  demandés** (pas le temps mesuré). La routine d'arrêt contient un calcul du temps partiel écoulé
  (conversion inverse 45 771/32 768) **mais il est inatteignable** (saut inconditionnel) : un tronçon
  interrompu n'est **jamais** décompté.

### 2.2 File des requêtes : liste **différentielle** [R][S]

- Une liste par unité ; chaque nœud porte son délai **relatif au nœud précédent** ; le `timeval`
  **de la requête de l'appelant est modifié en place** (SubTime successifs).
- **Ordre** : croissant d'échéance ; **ex aequo ⇒ FIFO** (la nouvelle passe derrière les nœuds dont
  le cumul est ≤ au sien).
- Insertion, nouvelle requête T (relative) :
  - liste vide ⇒ tête, démarrage d'un tronçon ;
  - T ≥ tête (comparaison secs puis micro, non signée) ⇒ on retranche à T les deltas des nœuds
    franchis, on l'insère à sa place, et le delta du nœud qui la suit diminue d'autant ; **le timer
    n'est pas touché** ;
  - T < tête ⇒ arrêt du timer, tête := tête − T, nouvelle requête en tête, nouveau tronçon.
- Interruption (fin de tronçon) : écoulé := durée du tronçon ; tant que écoulé ≥ tête ⇒ écoulé −=
  tête, la tête passe dans une liste « terminées » ; sinon tête −= écoulé. Puis nouveau tronçon pour
  la nouvelle tête (ou arrêt si vide). Les deltas nuls qui suivent sont donc terminés **dans la même
  interruption**. Les réponses (**ReplyMsg**) sont faites **après Enable**, depuis l'interruption
  de niveau 2, dans l'ordre **inverse** de terminaison (les terminées sont empilées) : deux requêtes
  échues dans la même interruption sont répondues la dernière d'abord.
- Conséquences de la comptabilité nominale (vérifiées [S]) :
  - **préemption** (T < reste de la tête) : la nouvelle est **juste** ; l'ancienne tête et toutes les
    suivantes sont **en retard** de la part déjà écoulée du tronçon interrompu (≤ 91,5 ms) ;
  - **insertion derrière la tête** : la nouvelle est **en avance** de cette même part écoulée.

### 2.3 Commandes [R][S]

| io_Command | Comportement |
|---|---|
| 0–8 (CMD_INVALID…CMD_FLUSH) | io_Error := **IOERR_NOCMD (−3)** ; ReplyMsg seulement si IOF_QUICK = 0 |
| ≥ 12 | idem −3 (sans remettre ln_Type à NT_MESSAGE) |
| **9 TR_ADDREQUEST** | io_Error := 0 ; **IOF_QUICK effacé** ⇒ toujours asynchrone, réponse par ReplyMsg à l'échéance |
| **10 TR_GETSYSTIME** | synchrone ; remplit `tv` (§4) ; ReplyMsg seulement si IOF_QUICK = 0 |
| **11 TR_SETSYSTIME** | synchrone ; base := `tv`, TOD de CIA-A := 0, compteur d'unicité := 0 ; ReplyMsg si non QUICK |

À l'entrée de BeginIO : io_Error := 0 ; si commande ≤ 11, ln_Type := NT_MESSAGE (5).
GETSYSTIME et SETSYSTIME agissent sur l'horloge **quelle que soit l'unité** ouverte.

### 2.4 Requêtes à 0 µs, petites valeurs, valeurs non normalisées

- `{0,0}`, `{0,1}`, `{0,50}` MICROHZ : chargent 0 ou 35 tops ; terminées **immédiatement** (même
  durée totale qu'un appel à vide, ~12 lignes de surcoût) [S, FS-UAE].
- `{0,91542}` : tronçon 91 541 puis tronçon de 1 µs (0 top) : +4 lignes seulement [S].
- `tv_micro` ≥ 1 000 000 n'est pas normalisé à l'entrée ; `{0,1000000}` se comporte exactement comme
  `{1,0}` [S]. Les comparaisons d'insertion (secs puis micro, non signées) seraient fausses entre une
  valeur normalisée et une non normalisée [R, non sondé].
- Valeur rendue dans `tv` à l'échéance = **le delta restant au moment de la terminaison** (ex.
  `{1,0}` rend `{0,84590}` = dernier tronçon ; `{0,91542}` rend `{0,1}`) [S]. Aucun appelant ne doit s'y
  fier, mais c'est l'état réel.

### 2.5 AbortIO [R][S]

- Cherche la requête dans la liste de **son** unité, sous Disable.
- Absente ⇒ rend **−1** dans d0, requête intacte (io_Error inchangé) [S : `abortNQ = FFFFFFFF`, err
  reste −3].
- Présente ⇒ si c'est la tête : arrêt du timer, retrait, le **suivant récupère le delta** retiré
  (AddTime), nouveau tronçon ; sinon simple retrait + report du delta. io_Error := **IOERR_ABORTED
  (−2)**, ReplyMsg (QUICK déjà effacé) ; rend **0**.
- Retirer la tête perd la part écoulée du tronçon : le suivant est en retard d'autant.

### 2.6 Ouverture / fermeture [R][S]

- Unité 0 ⇒ MICROHZ, unité 1 ⇒ VBLANK (io_Unit = base+$2A / base+$78, privé). Flags ignorés.
- Unité ≥ 2 ⇒ io_Error := **IOERR_OPENFAIL (−1)**, OpenDevice rend −1, lib_OpenCnt inchangé
  (io_Device reste posé par exec, io_Unit inchangé) [S].
- Succès ⇒ lib_OpenCnt + 1. Close ⇒ io_Device := io_Unit := −1, lib_OpenCnt − 1. Expunge/ExtFunc
  rendent 0 : le device n'est jamais déchargé.
- Version 34.1, `rt_Pri` 50, LIB_FLAGS = CHANGED|SUMUSED [R][S].

---

## 3. UNIT_VBLANK [R][S]

- Source : serveur **VERTB** du device (pri 0 ; au boot la chaîne VERTB est : graphics pri 10, puis
  `gameport.device` pri 0, puis `timer.device` pri 0).
- Période P = arrondi(1 000 000 / ExecBase->**VBlankFrequency**) (0 ⇒ 60) : **20 000 µs** en PAL,
  16 667 en NTSC. Pas de CIA, pas de E-clock.
- Même liste différentielle, même algorithme que MICROHZ ; à chaque VBLANK, écoulé := P, et
  **le reliquat se reporte** sur les nœuds suivants dans la même interruption ⇒ comptage
  **en trames absolues**, sans dérive ni perte lors des préemptions (vérifié [S] PREc).
- Échéance : la requête T est terminée au **k-ième VBLANK suivant** avec k = max(1, ⌈T / P⌉).
  `{0,0}`, `{0,1}` **et** `{0,20000}` ⇒ prochain VBLANK (donc entre ~0 et 20 ms) ; `{0,20001}` et
  `{0,40000}` ⇒ 2ᵉ ; `{1,0}` ⇒ 50ᵉ [S].
- Le même serveur fait aussi, **dans cet ordre**, sous Disable :
  1. **quantum d'exec** : Elapsed (+$122) − 1 ; à 0 ⇒ Elapsed := Quantum et **SysFlags (+$124) |=
     $4000** (SFB_TQE, « tranche de temps écoulée ») — exec ne décrémente Elapsed nulle part
     ailleurs ; il le recharge à chaque commutation ;
  2. **repli de l'horloge** (§4) si l'octet haut du TOD de CIA-A ≠ 0 ;
  3. traitement de la liste VBLANK.
  Puis Enable, ReplyMsg des terminées ; rend d0 = 0 (la chaîne continue).

---

## 4. Horloge système [R][S]

- Temps = **base** (secs, micro) + **TOD de CIA-A** converti + **compteur d'unicité** :
  - TOD lu sous Disable, octet haut d'abord (verrouillage 8520), puis milieu, puis bas ;
  - secs += TOD ÷ fréquence secteur ; micro += (TOD mod fréquence) × µs-par-tic + compteur ;
  - normalisation par AddTime ; **puis compteur + 1**.
- Avance donc au **tic secteur** (CIA-A TOD, 50/60 Hz sur A500), **pas** au VBLANK ni à l'E-clock.
  Résolution 20 ms (16 667 µs à 60 Hz) ; entre deux tics, chaque lecture rend **+1 µs** ⇒
  **strictement monotone** [S : `…49472`, `…49473`, `…4E294` (+20 001), `…4E295`].
- **Repli** (serveur VBLANK) dès que TOD ≥ 65 536 tics (≈ 21 min 50 s à 50 Hz) : base := heure
  courante (compteur inclus), TOD := 0, compteur := 0. Le compteur est donc **absorbé** : l'horloge
  gagne définitivement 1 µs par lecture (négligeable). Le quotient TOD ÷ fréquence tient ainsi en 16 bits.
- **TR_SETSYSTIME** : base := valeur, TOD := 0, compteur := 0 ⇒ la première lecture rend
  **exactement** la valeur posée [S : SST(1000,500000) puis `1000/500000`, `500001`, `500002` ;
  0,5 s plus tard `1001/020008`].
- Au reset : base = 0 (mémoire de MakeLibrary), TOD remis à 0 au calibrage ⇒ **1-jan-1978 00:00:00**
  (cohérent `boot-clock-v34.md` §3). Au moment de la sonde le TOD valait $13B (le validateur avait
  fait un SETSYSTIME au montage de DF0:).

---

## 5. AddTime / SubTime / CmpTime [D][R][S]

LVO (vecteurs du device, dans l'ordre Open −6, Close −12, Expunge −18, ExtFunc −24, BeginIO −30,
AbortIO −36) : **AddTime −42**, **SubTime −48**, **CmpTime −54** ; arguments **A0 = dest, A1 = src**.
N'utilisent pas A6 (la base n'est pas lue) ; détruisent D0/D1 ; préservent les autres registres.

| Fonction | Sémantique exacte | Vecteurs [S] |
|---|---|---|
| AddTime | dest += src (secs et micro séparément), puis **tant que micro ≥ 1 000 000** : secs+1, micro−1 000 000. **Pas** de correction d'un micro négatif | {0,999999}+{0,2} = {1,1} ; {0,3000000}+0 = {3,0} ; {5,−3}+0 = {5,−3} |
| SubTime | dest −= src, puis **tant que micro < 0** : secs−1, micro+1 000 000. **Pas** de correction d'un micro ≥ 1e6 | {1,0}−{0,1} = {0,999999} ; {0,0}−{0,3000000} = {−3,0} ; {0,5000000}−0 = {0,5000000} |
| CmpTime | compare secs puis micro, **non signé** ; d0 = 0 si égaux, **+1 si src > dest**, **−1 si src < dest** (« dest a plus de temps » ⇒ −1) | ({2,0},{1,5}) = −1 ; ({1,5},{2,0}) = +1 ; égaux = 0 ; ({0,1},{0,2}) = +1 ; ({−1,0},{1,0}) = −1 |

---

## 6. Carte d'allocation des CIA au boot (1.3, A500) [R][S]

### 6.1 CIA-A ($BFE001, niveau 2 PORTS, ciaa.resource)

| Ressource | Propriétaire | Remarque |
|---|---|---|
| Timer A | **libre** | jamais démarré ; CRA = $00 (keyboard ne bascule que SPMODE). Le démarrer pendant le handshake clavier provoque un décalage SP (cf. `keyboard-handshake-v34.md` §7) |
| Timer B | **timer.device** (ICR bit 1, autorisé) | UNIT_MICROHZ |
| TOD | **timer.device** (lecture/remise à 0, pas d'interruption) | horloge système ; CRB bit 7 = 0 |
| ALRM (bit 2) | **libre** | |
| SP (bit 3) | **keyboard.device** (ICR bit 3, autorisé) | |
| FLG (bit 4) | **libre** | (/ACK parallèle [D]) |

Relevé [S] : `ICRA mask $0A : 0=- 1=timer.device 2=- 3=keyboard.device 4=-`.

### 6.2 CIA-B ($BFD000, niveau 6 EXTER, ciab.resource)

| Ressource | Propriétaire | Remarque |
|---|---|---|
| Timer A | **libre** | aucune référence en ROM |
| Timer B | **libre** | aucune référence en ROM |
| TOD | **graphics.library** | chaque VBLANK, graphics remet le TOD à la ligne verticale courante puis repasse CRB bit 7 (ALARM) à 1 ; le TOD de CIA-B compte donc les **lignes depuis le haut de trame** |
| ALRM (bit 2) | **graphics.library** (Interrupt sans nom ; autorisée au boot) | file de blits synchronisés au faisceau (QBSBlit) : l'alarme se désautorise et relance l'interruption BLIT |
| SP (bit 3) | **libre** | |
| FLG (bit 4) | **disk.resource** (Interrupt sans nom ; **non autorisée** au boot) | impulsion d'index ; trackdisk l'autorise/l'interdit (SetICR/AbleICR $10/$90) autour des opérations synchronisées sur l'index, et disk.resource la renvoie au propriétaire courant du disque |

Relevé [S] : `CIAB cra.crb = $04/$84`, TA = TB = $FFFF, masque ICR **$04** (ALRM seul) ;
`0=- 1=- 2=(sans nom) 3=- 4=(sans nom)`. ciab.resource met aussi CIA-B PRA bits 6–7 (/RTS, /DTR) en
sortie à 1 ; disk.resource met CIA-B PRB en sortie à $FF et les bits 2–5 de CIA-A PRA en entrée.

### 6.3 Chaînes et vecteurs au boot [S]

| Vecteur exec | Contenu (après boot WB 1.3.3, serial.device chargé par `>SER:`) |
|---|---|
| 3 PORTS (serveurs) | **ciaa.resource seul** (pri 0) |
| 4 COPER (serveurs) | vide |
| 5 VERTB (serveurs) | graphics (pri 10), gameport.device (0), timer.device (0) |
| 13 EXTER (serveurs) | **ciab.resource seul** (pri 0) |
| 1 DSKBLK / 12 DSKSYNC | disk.resource |
| 6 BLIT | graphics |
| 7–10 AUDx | audio.device |
| 0 TBE / 11 RBF | serial.device (disque, ouvert ici par la sonde ; absent sinon) |

**Libres pour une application** : CIA-A timer A (avec la réserve clavier), CIA-A ALRM et FLG, CIA-B
timer A, timer B et SP. Un programme qui prend le vecteur `$78` sans chaîner ne casse que
QBSBlit (ALRM) et les opérations disque synchronisées sur l'index (FLG).

---

## 7. Délais de trackdisk [R]

- trackdisk ouvre **timer.device deux fois** à l'init : **unité 0 (MICROHZ)** et **unité 1
  (VBLANK)** (échec ⇒ Alert $14048015), et copie ces ouvertures dans chaque unité de disque.
- **Tous les délais** (pas de tête 3 ms, settle 15 ms, spin-up moteur 500 ms, 1 ms avant DMA, 2 ms
  écriture : voir `trackdisk-official-timing.md`) : requête **TR_ADDREQUEST MICROHZ synchrone (DoIO)**
  sur la requête MICROHZ de l'unité ; en dessous de **300 µs** : boucle CPU.
- La requête **VBLANK** de l'unité est réarmée en asynchrone (SendIO) par la tâche de l'unité :
  scrutation du changement de disque (sélection, lecture de /CHNG, impulsion de pas si besoin) ;
  réarmement avec tv_micro = 500 000 et tv_secs := 2 quand un drapeau d'état de l'unité est posé
  (sinon tv_secs reste à la valeur rendue, en pratique 0) ⇒ période ≈ 0,5 s ou ≈ 2,5 s.
- **Aucun timer CIA** n'est programmé directement par trackdisk ni disk.resource. CIA-B ne sert qu'aux
  sorties de commande lecteur (PRB) et à l'index (FLG).

---

## 8. Vecteurs de test (sorties brutes, vraie ROM, FS-UAE A500 PAL)

Mesure : trames F comptées par un serveur VERTB de la sonde + différence de ligne L ; durée ≈
(F × 313 + L) lignes de 64 µs (313 lignes/trame mesurées : `maxline = $138`). Surcoût fixe de mesure
≈ 12 lignes (requête à 0 µs).

```
EXEC vbf psf quantum elapsed sysflags maxline: 00000032 00000032 00000010 00000010 00000000 00000138
CIAA cra.crb ta tb tod: 00000008 0000FFFF 000002CB 0000013B
CIAB cra.crb ta tb tod: 00000484 0000FFFF 0000FFFF 000000D2
ICRA base mask: 00C01680 0000000A 0=- 1=timer.device/(code ROM)  2=- 3=keyboard.device/(code ROM)  4=-
ICRB base mask: 00C01718 00000004 0=- 1=- 2= 3=- 4=
OPEN dev u0off u1off opencnt ver.rev | u2: d0 err dev unit: 00C022EE 0000002A 00000078 0000000A 00220001 FFFFFFFF FFFFFFFF 00C022EE 00000000
CMD read(d0 type.err) cmd12 invalid | abortNQ(d0 err): FFFFFFFD 000005FD FFFFFFFD 000005FD FFFFFFFD 000005FD FFFFFFFF FFFFFFFD
ADD/SUB: 00000001 00000001 00000003 00000000 00000005 FFFFFFFD 00000000 000F423F FFFFFFFD 00000000 00000000 004C4B40
CMP: FFFFFFFF 00000001 00000000 00000001 FFFFFFFF
```

| Requête | F | L | lignes | Théorie (tops E × 5/227) + surcoût | Remarque |
|---|---|---|---|---|---|
| MZ {0,1000} | 0 | 26 | 26 | 15,8 + 12 | |
| MZ {0,10000} | 0 | 168 | 168 | 157,7 + 12 | |
| MZ {0,20000} | 1 | 13 | 326 | 315,4 + 12 | |
| MZ {0,91541} | 5 | −111 | 1454 | 1443,6 + 12 | 1 tronçon plein |
| MZ {0,91542} | 4 | 206 | 1458 | +1 tronçon de 0 top | tv rendu {0,1} |
| MZ {0,100000} | 5 | 26 | 1591 | 1576,9 + 12 | tv rendu {0,8459} |
| MZ {0,250000} | 13 | −110 | 3959 | 3942,2 + 12 | |
| MZ {1,0} | 51 | −143 | 15820 | 15769 + 12 (+≈3,5 lignes × 11 tronçons) | **1,0125 s** ; tv rendu {0,84590} |
| MZ {0,1000000} | 51 | −141 | 15822 | idem | identique à {1,0} |
| MZ2 {0,50} / {0,1} / {0,0} | 0 | 12 | 12 | surcoût seul | terminées aussitôt |
| VB {0,0} | 1 | −104 | — | prochain VBLANK | |
| VB {0,1} | 1 | −241 | — | prochain | |
| VB {0,20000} | 1 | −294 | — | prochain | tv rendu {0,20000} |
| VB {0,20001} | 2 | −266 | — | 2ᵉ | |
| VB {0,40000} | 2 | −237 | — | 2ᵉ | |
| VB {0,100000} | 6 | −299 | — | 5ᵉ (voir §9) | |
| VB {1,0} | 50 | −269 | — | 50ᵉ | |

Préemption / insertion (deux exécutions, série puis console) :

```
PREa(MZ A=1s B=.5s) poseB F L | ordre: 00000003 FFFFFF7D B 0000001C FFFFFFD5 A 00000036 FFFFFF3C
PREa (2e)                              00000003 FFFFFFC8 B 0000001C 00000020 A 00000036 FFFFFF3E
PREb(MZ A=.2s B=.4s) poseB F L | ordre: 00000003 00000047 A 0000000A 00000029 B 00000014 0000004B
PREb (2e)                              00000003 FFFFFFCA A 0000000A 0000002A B 00000014 00000055
PREc(VB A=1s B=.5s) poseB F L | ordre: 00000003 00000003 B 0000001C FFFFFFC3 A 00000032 FFFFFF7A
```

- PREa : B posée à 808 lignes, finie à 8721 (7913 lignes = sa durée normale) ; A finie à 16 706
  au lieu de 15 820 ⇒ **retard ≈ 886 lignes ≈ 57 ms** ≈ part écoulée du tronçon interrompu (808) +
  rechargements.
- PREb : A juste (3171) ; B posée à 1010, finie à 6335 au lieu de ≈ 7338 ⇒ **avance ≈ 64 ms** = part
  écoulée du tronçon de A au moment de la pose.
- PREc (VBLANK) : B au 28ᵉ VBLANK (posée à ~3 trames + 0,5 s), A au 50ᵉ : **aucune erreur**.

Horloge :

```
GST: 5BD28ADF 00049472 5BD28ADF 00049473 5BD28ADF 0004E294 5BD28ADF 0004E295
SST(1000,500000) err | GST x3 | MZ.5s | GST: 00000000 000003E8 0007A120 000003E8 0007A121 000003E8 0007A122 0000001A FFFFFF23 00000000 tv 00000000 0000A537 000003E9 00004E28
```

Détournements de vecteurs (le point clé pour les jeux) :

```
HJ6 MZ.5s(F L err) VB.5s(F L err) h6cnt: 0000001A FFFFFF1D 00000000 tv 00000000 0000A537 00000019 FFFFFFAE 00000000 tv 00000000 00004E20 0000003C
HJ2 MZ.1s(F L err) h2cnt | apres retablissement MZ.1s: TMO FFFFFFFE tv 00000000 000186A0 00000001 00000005 00000019 00000000 tv 00000000 0000210B
```

- **HJ6** : `$78` pris par un gestionnaire qui lit l'ICR de CIA-B, acquitte EXTER et fait RTE sans
  chaîner, pendant que CIA-B timer B tourne en continu (latch $2E2E, ICR $82, comme la musique de
  Monkey Island) : 60 interruptions détournées ; **MICROHZ 0,5 s = 7911 lignes** (normal : 7917) et
  VBLANK 0,5 s = 25 trames : **délais intacts**.
- **HJ2** (contrôle négatif) : `$68` pris de la même façon ⇒ MICROHZ 0,1 s **jamais servie**
  (garde-fou VBLANK 3 s atteint, AbortIO ⇒ io_Error −2, tv intact {0,100000}, 1 seule interruption
  détournée : le one-shot ne repart pas). Après rétablissement de `$68`, une nouvelle MICROHZ 0,1 s
  dure 1590 lignes : l'unité repart après l'AbortIO.

Reproduire : assembler `tests/timerprobe.s` avec `-kick1hunks`, l'écrire dans une copie de l'ADF
Workbench 1.3.3 avec la startup-sequence `timerprobe >SER:` puis `timerprobe`, booter la vraie ROM.

---

## 9. Non sondé / incertain

- **Charge d'un latch 0 en one-shot** : terminaison immédiate observée sous FS-UAE ; comportement d'un
  vrai 8520 non vérifié (une requête MICROHZ {0,0}/{0,1} pourrait se comporter autrement sur le
  matériel).
- **CIA-B CRA/CRB bit 2 (OUTMODE) = 1** relevé après boot ($04/$84) : aucune écriture correspondante
  trouvée en ROM ; origine (état d'émulateur, programme du disque) non élucidée. Sans effet (PBON = 0).
- **VB {0,100000} = 6 trames** au lieu de 5 : interprété comme une course de mesure (horodatage juste
  avant un VBLANK, SendIO juste après : L = −299 ⇒ horodatage dans les 14 dernières lignes de la
  trame) ; non refait.
- **Calibrage sans tic TOD** (§1.3 étape 3) : chemin d'Alert + pile déséquilibrée analysé, non sondé.
- **Drapeau de l'unité trackdisk** qui fait passer la scrutation VBLANK à 2,5 s : sémantique exacte
  (absence de disque ?) non élucidée.
- Mesure faite en PAL 50 Hz uniquement ; le chemin 60 Hz (16 667 µs/tic, P VBLANK 16 667) est [R].
- Surcoût de rechargement par tronçon MICROHZ (≈ 3–4 lignes ≈ 220 µs) dépend de la charge
  d'interruptions : valeur indicative.

---

## 10. Recommandation pour la réimplémentation

But : un jeu qui détourne `$78` (niveau 6) ne doit casser **aucun** délai système.

1. **Déplacer UNIT_MICROHZ sur le timer B de CIA-A**, obtenu par `ciaa.resource`
   AddICRVector(bit 1) ⇒ niveau 2. Mode one-shot (CRB RUNMODE = 1, INMODE = φ2), démarrage par
   écriture TBLO puis TBHI, arrêt par effacement de START seul (ne pas écraser les autres bits de CRB).
   Tronçons ≤ 65 535 tops.
2. **Ne programmer aucun timer de CIA-B** dans la ROM : les jeux les considèrent comme libres (Monkey
   écrit CIA-B TB, CRB = $11, ICR = $82 directement, sans ressource). Ne pas utiliser non plus le timer A
   de CIA-A.
3. **UNIT_VBLANK sur un serveur VERTB** (niveau 3), période 1e6/VBlankFrequency, avec report du
   reliquat (comptage en trames absolues), échéance au k-ième VBLANK, k = max(1, ⌈T/P⌉).
4. **Horloge système sur le TOD de CIA-A** (tic secteur) + compteur d'unicité +1 µs par lecture,
   repli dans le serveur VBLANK quand le TOD ≥ 65 536, remise à zéro par SETSYSTIME. Laisser le TOD de
   CIA-B à graphics (lignes/alarme).
5. Niveau 6 : n'y installer que le serveur de `ciab.resource` (ALRM graphics, FLG disk.resource).
   Ainsi la prise de `$78` n'a, comme sur la 1.3, que des effets sur QBSBlit et l'index disque.
6. Délais de trackdisk : TR_ADDREQUEST MICROHZ synchrone (≥ 300 µs), boucle CPU en dessous ;
   scrutation du changement de disque par une requête VBLANK périodique.
7. Fidélité (optionnelle mais conseillée) : facteur fixe 46 918/65 536 tops/µs même en PAL (délais
   +0,92 %), comptabilité nominale par tronçon (avance/retard lors des préemptions, §2.2), liste
   différentielle FIFO pour les ex aequo, `tv` de la requête modifié en place, IOF_QUICK effacé par
   ADDREQUEST, AbortIO rendant −1 si la requête n'est pas en file. timer.device fixe Quantum = 16 et
   fournit le tic de quantum (SysFlags bit 14) depuis son serveur VBLANK : si notre exec dépend
   d'une autre source de tranche de temps, la garder cohérente avec 16 trames.
8. Effet de bord accepté : un jeu qui détourne `$68` (niveau 2) tue MICROHZ **et** le clavier, comme sur
   la vraie 1.3 (HJ2).

---

## 11. Relecture clean-room

Relu intégralement : aucune suite d'instructions 68000 recopiée ou paraphrasée, aucun extrait de
désassemblage, aucun pseudo-code ligne à ligne. Le document décrit des ressources, registres
matériels et valeurs écrites, des formules de conversion (constantes), des règles d'ordre et de
comptabilité, des conditions et des sorties de sonde. Les adresses ROM relevées par la sonde (retirées du document)
sont des repères d'identification relevés par la sonde, pas des recettes. La sonde
`tests/timerprobe.s` est du code auteur (structures publiques). La ROM n'a été ni modifiée ni
copiée ; le désassemblage est resté dans le répertoire scratch de session.
