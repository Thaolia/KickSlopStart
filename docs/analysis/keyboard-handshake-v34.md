# keyboard-handshake-v34.md — réception d'un octet clavier et poignée de main (KS 1.3)

> Piste ANALYSE (« dirty »). Source : ROM `assets/kick34005.A500`. Repères :
> - keyboard.device : résident $FE4B8E, init $FE4F44, réglage CRA $FE4FD4/$FE4FEC, handler
>   $FE5276, fin du handshake $FE53A2 et $FE5266 ;
> - ciaa.resource : serveur $FC4684, AddICRVector $FC46F8, AbleICR/SetICR $FC4772/$FC4790 ;
> - exec : parcours de chaîne de serveurs $FC1338 ;
> - timer.device : $FE8D6C… (pour CIA-A timer B).
>
> **Légende** : **[O]** observé · **[D]** déduit · **[S]** supposé. Registres CIA-A :
> PRA $BFE001, TBLO $BFE601, TBHI $BFE701, **SDR $BFEC01**, **ICR $BFED01**, **CRA $BFEE01**,
> CRB $BFEF01. Comportement uniquement.

---

## 1. Où l'interruption est servie [O]

1. CIA-A /IRQ ⇒ Paula **INTREQ PORTS (bit 3)** ⇒ **niveau 2** ⇒ chaîne de serveurs PORTS d'exec.
2. Le **serveur de ciaa.resource** fait, dans l'ordre :
   - **une seule lecture de l'ICR ($BFED01)**, au tout début. Cette lecture efface tous les
     drapeaux de la CIA ;
   - bit 7 retiré, OR avec les drapeaux mémorisés (« pending » de la ressource), puis AND avec le
     masque autorisé ;
   - les bits traités sont retirés du pending ;
   - appel des vecteurs **dans l'ordre des bits** : 0 TA, 1 TB, 2 ALRM, **3 SP**, 4 FLG. Chaque
     vecteur reçoit A1 = is_Data et A5 = is_Code.
   - **L'ICR n'est relu à aucun autre moment du service.**
3. Exec acquitte **INTREQ PORTS seulement après** le parcours de toute la chaîne (fin de
   $FC1338). Si la CIA reçoit un nouvel octet pendant le service, son /IRQ reste actif et le bit
   PORTS se relève. Le nouvel octet n'est donc pas perdu, puisque son drapeau SP n'a pas été
   relu [D].
4. keyboard.device installe son handler par **AddICRVector(CIAICRB_SP = 3, &interrupt)**
   (ciaa.resource −6), l'Interrupt étant à keyboard+$5A avec is_Data = la base du device. La
   ressource autorise le bit SP dans l'ICR (écriture $80|$08).

## 2. Initialisation (keyboard.device, une fois) [O]

Sur CIA-A, dans cet ordre :
1. **CRA := $00, puis CRA := $00, puis CRA := $40.** Ce sont des écritures d'octet complet :
   timer A arrêté (START 0), RUNMODE 0, INMODE 0, PBON 0, LOAD 0, **SPMODE 1 (sortie)**.
2. AddICRVector(3, …).
3. **CRA := $00.**

Ensemble, ces deux étapes forment **une impulsion de handshake à l'init**, de la durée de
l'appel AddICRVector, qui acquitte un éventuel octet déjà en attente. Ensuite :
- **CRA vaut $00 en permanence**, hors du bit 6 pendant un handshake ;
- **le timer A de CIA-A ne tourne jamais** : keyboard.device ne l'utilise pas ;
- timer.device 1.3 utilise **CIA-A timer B** (CRB/TBLO/TBHI), jamais CRA.

## 3. Réception d'un octet : ordre exact des accès [O]

Le handler est appelé par le serveur de ciaa.resource, au niveau 2, avec l'ICR déjà lu :
1. **Lecture de SDR ($BFEC01).**
2. **Aussitôt, CRA |= $40** : SPMODE en sortie, KDAT tiré bas, début du handshake. C'est une
   lecture-modification-écriture de CRA, faite **à l'instruction qui suit** la lecture de SDR.
   Les autres bits de CRA restent à 0.
3. Décodage : code = **NOT(octet) puis rotation à droite d'un bit**, soit bit 7 = relâchement et
   bits 6–0 = code de touche.
4. **Cas $78 (avertissement de reset)** : voir §5.
5. Mise à jour de la matrice de touches (bitmap de 13 octets à +$106) pour les codes ≤ $67, et du
   mot de qualificatifs.
6. **Disable** (exec −120). Insertion de (code, qualificatif) dans le tampon circulaire (32
   entrées de 4 octets, index sur 7 bits). Si le tampon est plein, la dernière entrée est
   remplacée par un code de débordement. **Enable** (−126).
7. Si une requête KBD_READEVENT est en attente (en pratique toujours, celle d'input.device) et
   qu'aucune n'est déjà en cours de service : copie des InputEvents dans le tampon de la requête,
   puis **ReplyMsg** (−378).
8. **CRA &= $BF** : SPMODE en entrée, KDAT relâché, **fin du handshake**.
9. Retour au serveur de ciaa.resource.

Ce qui n'est **jamais** fait pendant ce trajet :
- écrire SDR ;
- lire ou écrire l'ICR (déjà lu par la ressource) ;
- toucher aux timers A ou B ;
- toucher à PRA ou DDRA, lire VHPOSR, faire une boucle d'attente.

## 4. Durée de l'impulsion [O sur la structure, D sur la valeur]

- **Aucune temporisation explicite.** La durée est simplement le **temps d'exécution des étapes
  3 à 7** : décodage, matrice, Disable/Enable et, en général, livraison des événements à
  input.device avec ReplyMsg.
- Estimation sur un 68000 à 7,09 MHz, sans contention [D] :
  - de l'ordre de **100 µs** sans requête à satisfaire ;
  - **150–300 µs** avec la copie des événements et le ReplyMsg habituels.
- Elle est toujours supérieure aux **≈ 85 µs** minimum exigés par le clavier [D, valeur de la
  spécification matérielle publique]. Elle n'est **jamais fixe**.
- Notre impulsion d'environ 360 µs est donc **dans la plage plausible**. La durée n'est
  probablement pas le facteur discriminant [D].

## 5. Reset clavier ($78) et codes spéciaux [O]

- Premier **$78** : un drapeau « 1er avertissement » est posé, puis traitement normal ; le code
  est mis en file et le handshake se termine.
- Un **second $78 consécutif** (drapeau déjà posé) :
  - drapeau « reset en cours » posé ;
  - pour chaque handler de la liste KBD_ADDRESETHANDLER : compteur +$102 incrémenté, puis
    **Cause** (exec −180) ;
  - **le handshake n'est PAS terminé** : CRA bit 6 reste à 1 ;
  - il ne se termine qu'au dernier **KBD_RESETHANDLERDONE** (compteur ramené à 0 ⇒ CRA &= $BF,
    $FE5266). S'il n'y a aucun handler, il se termine tout de suite.
  - Le clavier attend ce handshake (au plus environ 10 s) avant de faire le reset matériel [D,
    comportement clavier public].
- Tout code différent de $78 efface le drapeau « 1er avertissement ».
- **$79 à $7E** (après décodage : $F9 dernier code faux, $FA tampon plein, $FC échec
  d'autotest, $FD/$FE début et fin de la séquence de mise sous tension) : pas de mise à jour de
  la matrice (code > $67). Ils sont mis en file **comme des événements ordinaires**, puis le
  handshake se termine normalement. **Il n'y a ni resynchronisation logicielle, ni lecture de
  KCLK, ni accès à DDRA/PRA.**

## 6. Comparaison avec notre handshake et pistes WinUAE [D]

Notre séquence (lire SDR, CRA |= $40, boucle d'environ 360 µs, CRA &= ~$40) a le même ordre que
la ROM. Les différences possibles sont ailleurs :

1. **État des autres bits de CRA.** La ROM garde **CRA = $00**, avec le timer A arrêté. Si
   notre CRA a **START = 1** (timer A de CIA-A utilisé pour autre chose) ou un autre RUNMODE,
   passer SPMODE en sortie avec le timer A en marche **lance un décalage en sortie** sur SP,
   cadencé par le timer A. Un émulateur cycle-exact comme WinUAE peut alors voir KDAT bouger au
   lieu de rester bas, et refuser le handshake.
   - **À vérifier : CRA = $00 hors handshake, et aucun usage du timer A de CIA-A.**
2. **Relecture de l'ICR après le handshake.** WinUAE peut envoyer l'octet suivant (le relâchement
   $92) **très peu de temps après** la fin du handshake, alors que nous sommes encore dans
   l'interruption.
   - Une seconde lecture de **$BFED01** par notre code efface le drapeau SP du nouvel octet. Ce
     peut être notre dispatch qui relit l'ICR après les handlers, une scrutation de l'ICR pour un
     timer, ou un AbleICR/SetICR.
   - Si notre code acquitte en plus PORTS avant la fin, ou ne relit pas les drapeaux mémorisés,
     **l'octet est perdu** et le clavier attend un handshake qui ne viendra jamais.
   - FS-UAE est plus tolérant sur ce délai.
   - **Règle de la ROM** : une seule lecture de l'ICR par passage dans le serveur, au début, avec
     les bits non traités mémorisés.
3. **Acquittement d'INTREQ PORTS** : il doit être fait après le service, et l'IRQ niveau CIA doit
   pouvoir relever le bit.
4. **Init** : impulsion de handshake de mise en route (CRA $00, $00, $40, … $00), qui
   resynchronise un clavier ayant déjà émis un octet avant l'installation du handler (par exemple
   la séquence de mise sous tension $FD…$FE).

---

## Relecture clean-room

- [x] Aucune suite d'instructions recopiée : ordre des accès registres et valeurs, structure du
  service d'interruption, conditions (reset, codes spéciaux) et estimation de durée.
- [x] Aucune donnée de la ROM reproduite (tables de qualificatifs seulement citées).
