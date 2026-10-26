# uae-int2-v34.md — interruption de la carte UAE (PORTS, niveau 2) et DiagPoint UAE

> Piste ANALYSE (« dirty »). Sources : sondes boîte noire sur la vraie ROM `kick34005.A500` sous FS-UAE 3.2.35
> (`tests/intports.s`, `tests/bootlist.s`) ; débogueur console FS-UAE sur la vraie ROM **et** sur notre ROM
> (`prod.rom` du 26/10, boîte noire : registres matériels et mémoire, aucune lecture de `src/`) ; code source GPL
> de FS-UAE 3.2.35 (`src/filesys.cpp`, `src/filesys.asm`, `src/custom.cpp`, `src/newcpu.cpp`,
> `src/native2amiga.cpp`, `src/autoconf.cpp`, `src/expansion.cpp` — logiciel indépendant de la ROM).
> On décrit le **quoi** ; aucune suite d'instructions transcrite, aucune adresse de routine de la ROM d'origine.
>
> Légende : **[S]** sonde/débogueur · **[U]** source FS-UAE · **[D]** doc publique (RKRM).
> Prérequis : `autoconfig-v34.md` §6 (appel de DiagPoint), `uae-hd-boot-v34.md` (romboot, BootPoint).

---

## 0. Réponse courte

**La carte UAE ne lève PAS d'interruption pendant le démarrage.** Sur notre ROM bloquée, l'indicateur UAE
`$F0FFEB` vaut 0 (aucune requête n'a jamais été émise) et le niveau 2 est alimenté par **le timer A de CIA-A**,
que notre ROM fait tourner à ce moment-là **en mode continu avec un latch de `$00FF`** (256 cycles E, soit
≈ 361 µs ≈ 2 560 cycles CPU) **avec l'interruption TA autorisée** (masque ICR `$03`). **[S]**

Ce que la carte ajoute, c'est **un serveur PORTS de plus** (« UAE filesystem », pri 20, placé **devant** celui
de ciaa.resource) que la DiagPoint installe elle-même. Ce serveur ne fait rien tant qu'UAE n'a rien demandé, mais
il allonge chaque passage dans la chaîne PORTS. Avec un TA à 361 µs, cela suffit pour qu'une nouvelle
interruption TA arrive avant la fin du traitement : le niveau 2 est relevé aussitôt et le code principal ne
reprend jamais la main (le code qui arrêterait TA ne s'exécute donc jamais). Preuves par intervention au
débogueur sur la machine bloquée (§4) : **arrêter TA** ⇒ le démarrage repart ; **retirer le serveur UAE de la
chaîne** ⇒ repart ; **allonger la période de TA ×16** (latch `$0FFF`) ⇒ repart ; ne rien toucher ⇒ toujours
bloqué. **[S]**

Sur la vraie 1.3, **CIA-A TA n'est jamais démarré pendant le démarrage** (CRA `$00`, latch `$FFFF`, masque ICR
`$0A` = TB + SP) : le niveau 2 ne voit que des événements rares (clavier, MICROHZ à la demande), et le serveur UAE
ne coûte rien. **[S]**

**Ce que notre ROM doit faire** (§5) : ne pas laisser de source CIA-A à haute fréquence avec interruption
autorisée pendant l'init des résidents (ou n'importe quand : la vraie 1.3 n'en a pas) ; secondairement, garder le
parcours niveau 2 / chaîne PORTS court et résistant à des serveurs supplémentaires. **Notre appel de la
DiagPoint est conforme** : la ROMTag, `uae.resource` et les deux serveurs UAE sont en place sur notre ROM comme sur
la vraie (§3, §4).

---

## 1. Côté UAE : la source « uae_int » **[U]**

- FS-UAE tient une variable d'émulateur `uae_int_requested`. **Tant que son octet bas est non nul, l'émulateur
  repositionne INTREQ PORTS (`$8008`) à chaque ligne (hsync) et dans la boucle CPU** : c'est une source
  **niveau**, pas une impulsion. (Son octet `$FF00` pilote EXTER/niveau 6 pour d'autres cartes, sans objet ici.)
- Le bit 0 est posé par les fonctions « natif → Amiga » d'UAE (Signal, PutMsg, ReplyMsg, Cause, notification
  de fichier) : réponses aux paquets du handler de fichiers, signal de la tâche de montage, partage de
  presse-papiers, hardfiles. **Aucune de ces sources n'existe avant l'init de `uaehf.device`** (romboot) et le
  montage : rien ne pose le bit pendant l'autoconfig/DiagPoint.
- À chaque pose du bit, UAE recopie aussi l'état du bit 0 dans l'octet **`$F0FFEB`** de sa zone « rtarea »
  (`$F00000–$F0FFFF`). Cet octet n'est **jamais remis à zéro ensuite** : c'est un indicateur « au moins une requête
  a été émise » utilisable par sonde ou débogueur (vraie ROM après boot : `01` ; notre ROM bloquée : `00`).
- **Acquittement côté 68k** : uniquement par le serveur d'interruption PORTS « UAE filesystem » (§2.3). Ce
  serveur appelle un piège émulateur (code dans la rtarea, en `$F0xxxx`) qui, si le bit 0 est posé et qu'aucun
  autre traitement UAE n'est en cours, **efface le bit** et répond « c'est pour moi » ; le serveur dépile alors les
  actions en attente (PutMsg/Signal/ReplyMsg/Cause…) puis libère le verrou et rend Z = 0. Sinon il rend Z = 1
  (D0 = 0) sans rien faire. Aucune lecture/écriture de registre de la carte `$E90000` n'acquitte quoi que ce soit ;
  l'effacement d'INTREQ par le CPU ne suffit pas tant que le bit UAE reste posé (il est reposé à la ligne suivante).
- Conséquence : si un jour UAE demande une interruption alors que le serveur « UAE filesystem » n'est pas dans la
  chaîne PORTS (ou n'est jamais appelé), la machine se bloque en niveau 2 pour de bon. Ce n'est **pas** le cas
  observé ici (indicateur à 0).

---

## 2. DiagPoint de la carte UAE : contrat **[U ; S]**

### 2.1 Entrées attendues

La DiagArea de la carte (`er_InitDiagVec = $2000`) a `da_Config = $90` (DAC_WORDWIDE | DAC_CONFIGTIME),
`da_Flags = 0`, **`da_Size = $0200`**, `da_DiagPoint = $01E0`, `da_BootPoint = $01E6`, nom à +14 (`"UAE"`).
À `+$1E0` comme à `+$1E6` se trouve un **saut absolu vers la rtarea** : le code exécuté ensuite n'est pas
relogé, il travaille sur la **copie** désignée par A2.

| Registre | Utilisation par UAE |
|---|---|
| **A2** | adresse de la **copie RAM** de la DiagArea. UAE **écrit** dedans (ROMTags + code, §2.2) : la copie doit être en RAM inscriptible et faire au moins `da_Size` = 512 octets. |
| **A3** | ConfigDev de la carte : mémorisé par UAE (il le réutilise comme `ln_Name` des BootNodes et le journalise : `filesystem: diagentry <A2+$10> configdev <A3>`). |
| **A5** | ExpansionBase : seulement testé (≠ 0 = chemin normal ; 0 = chemin « KS 1.2 » d'UAE) et utilisé pour l'option « hide autoconfig ». Doit être non nul. |
| **A6** | ExecBase : utilisé tel quel pour InitResident, AllocMem et AddIntServer (pas relu en `4.w`). |
| A0 | ignoré (écrasé). |

Retour : **D0 = 1** ; D0/D1/A0/A1 sont détruits, les autres registres sont rendus intacts.

### 2.2 Ce qu'elle fait, dans l'ordre

1. Écrit à **copie+$10** la ROMTag `uaehf.device` (« UAE hardfile.device 0.4 ») : flags `$81`
   (RTF_COLDSTART | RTF_AUTOINIT), version 50, NT_DEVICE, pri 5, `rt_EndSkip` = copie+$2A ; nom, idstring et
   table d'init en rtarea. **Elle ne l'initialise pas** (c'est romboot, `uae-hd-boot-v34.md` §2.1).
2. Écrit à **copie+$2A** une seconde ROMTag **`uae.resource`** (« UAE resource 3.3.0 ») : flags `$81`, version 1,
   **NT_RESOURCE**, pri 120 (d'autres ROMTags peuvent suivre selon les options UAE : bsdsocket, uaescsi,
   uaenet, uaeserial… — aucune dans la config de test).
3. Écrit à la suite, dans la copie, un petit code qui est **exécuté immédiatement** :
   - **`InitResident(tag, 0)` pour chaque ROMTag après la première** (ici `uae.resource` ⇒ MakeLibrary +
     **AddResource** pendant l'init d'expansion ; sur la vraie 1.3 elle est la **première** entrée de
     ResourceList, avant potgo.resource) ;
   - l'installation des serveurs UAE (§2.3) ;
   - retour D0 = 1.

### 2.3 Les deux serveurs installés pendant la DiagPoint

| Nœud (AllocMem PUBLIC\|CLEAR) | Vecteur | Pri | `is_Data` / `is_Code` | Comportement |
|---|---|---|---|---|
| **« UAE filesystem »**, 26 octets, NT_INTERRUPT | **INTB_PORTS (3)** via **AddIntServer** | **20** | tous deux dans la rtarea | §1 : Z = 1 tant qu'UAE n'a rien demandé ; Z = 0 après avoir servi une requête. Préserve A2 ; détruit D0/D1/A0/A1 et A6 (rechargé avec ExecBase depuis `4.w`). |
| **« UAE heart beat »**, 22 octets, NT_INTERRUPT | **INTB_VERTB (5)** via **AddIntServer** | **−10** | `is_Data` = un long de la rtarea, `is_Code` en rtarea | incrémente le long pointé par A1 (= `is_Data`) et rend Z = 1 (la chaîne continue). UAE s'en sert pour savoir que l'OS tourne. |

Plus, selon la config : un test « mousehack » (piège émulateur) qui peut créer une tâche d'intégration souris
(inactif dans la config de test : aucune tâche correspondante). Le correctif d'InitCode pour le presse-papiers
n'est appliqué que si exec ≥ 37 : rien sur 1.3.

Exigences qui en découlent pour exec/expansion **au moment de la DiagPoint** (avant tous les résidents de
priorité < 110) : AllocMem opérationnel ; **listes de serveurs PORTS et VERTB déjà initialisées** et
AddIntServer fonctionnel (l'ajout doit survivre à l'init ultérieure de ciaa.resource, gameport, timer…) ;
InitResident d'une ROMTag AUTOINIT **NT_RESOURCE** fonctionnel (AddResource).

Ordre d'allocation observé sur la vraie ROM (slow RAM, adresses croissantes) : ConfigDev `$C01620` →
`uae.resource` `$C0166E` → nœud « UAE filesystem » `$C016A0` → nœud « UAE heart beat » `$C016C0` →
`potgo.resource` `$C016EA` (résident pri 100) → … → nœud ciaa.resource `$C017AA`. Les serveurs UAE existent donc
**dès la DiagPoint**, bien avant ciaa.resource (pri 80) et romboot (pri −40). **[S]**

---

## 3. Vraie ROM 1.3 : état des interruptions **[S]**

- **Chaîne PORTS** après démarrage : « UAE filesystem » (pri 20) **puis** ciaa.resource (pri 0). **VERTB** :
  serveur de graphics (pri 10), gameport.device (0), timer.device (0), « UAE heart beat » (−10). **EXTER** :
  ciab.resource (0).
- La chaîne s'arrête au premier serveur qui rend Z = 0 (comportement 1.x des serveurs, RKRM **[D]**) : le serveur
  UAE ne rend Z = 0 que lorsqu'il a effectivement servi une requête UAE.
- **CIA-A pendant et après le démarrage** (débogueur à 5 s et à 25 s) : CRA `$00` (TA arrêté, jamais chargé :
  latch `$FFFF`), CRB `$08` (TB one-shot, latch `$02CB` = MICROHZ), masque ICR **`$0A`** (TB + SP). INTENA
  `$602C` (INTEN, EXTER, VERTB, PORTS, SOFTINT).
- Après démarrage depuis DH0:, `$F0FFEB` = 1 (UAE a déjà émis des requêtes : montage, paquets), et le système
  tourne : la source uae_int est acquittée par le serveur UAE comme prévu.
- Entre la DiagPoint et l'init de `uaehf.device` par romboot, la source uae_int n'a **aucune raison** d'être active
  (§1) ; de toute façon le serveur UAE est déjà dans la chaîne PORTS depuis la DiagPoint (§2.3). La 1.3 ne bloque
  donc jamais, que la source soit active ou non. (Non observé instant par instant sur la vraie ROM : le débogueur
  n'arrive qu'après plusieurs secondes ; déduit des adresses d'allocation + source UAE + indicateur à 0 sur notre
  ROM.)

---

## 4. Notre ROM bloquée : observations boîte noire **[S]**

Config : A500, chip 512 Ko, slow 512 Ko, fast 2 Mo, `hard_drive_0 = <rép.>`, ADF vierge ; débogueur à 25 s
(écran blanc, démarrage figé).

- `INTENA $402C` (INTEN, VERTB, PORTS, SOFTINT ; EXTER pas encore autorisé), `INTREQ $1009`/`$1029` (PORTS en
  attente), IPL 2 ou 3, CPU en superviseur, masque 2 ou 3, dans le parcours de la chaîne PORTS.
- **CIA-A : CRA `$01` (TA démarré, mode continu), latch TA `$00FF`, masque ICR `$03` (TA + TB)**, ICR lu à 0
  (déjà acquitté par le serveur, puis réarmé à chaque sous-dépassement).
- `$F0FFEB = $00` : **UAE n'a jamais demandé d'interruption**. `$F0FFEC` (long) = `$00E92000` (adresse de la
  DiagArea de la carte, posée par UAE à la configuration).
- Chaîne PORTS d'ExecBase : « UAE filesystem » (pri 20, `is_Code` en `$F00300`) → un serveur pri 10 → un serveur
  pri 0. Le serveur VERTB « UAE heart beat » est présent aussi. **La DiagPoint s'est donc exécutée correctement
  sur notre ROM.**
- Interventions au débogueur, puis reprise avec point d'arrêt mémoire en écriture sur SERDAT (`$DFF030`, notre
  ROM écrit sur le série dès qu'elle progresse), 20 s d'attente :

| Intervention | Résultat |
|---|---|
| aucune | **pas** d'écriture SERDAT : toujours bloqué |
| CRA ← `$00` et masque TA retiré (ICR ← `$7F`) | écriture SERDAT, masque CPU 0 : **le démarrage repart** |
| nœud « UAE filesystem » retiré de la chaîne PORTS (TA inchangé) | **repart** |
| latch TA ← `$0FFF` (période ×16, ≈ 5,8 ms), serveur UAE laissé | **repart** |

- Sans `hard_drive_0` (même ROM, 25 s, démarrage normal) : CIA-A CRA `$00`, masque `$0A`, latch TA `$00FF`
  — TA a donc servi pendant le démarrage puis a été arrêté par le code principal ; sans le serveur UAE, le
  traitement de chaque interruption TA tient (de justesse) dans les 361 µs.

Conclusion : le coût d'un passage niveau 2 (entrée, acquittement, parcours de la chaîne PORTS avec 3 serveurs,
dont le dispatch de ciaa.resource) dépasse la période de TA dès qu'on ajoute le serveur UAE ; INTREQ PORTS est
reposé par CIA-A avant le retour, d'où un niveau 2 perpétuel.

---

## 5. Ce que notre ROM doit faire

1. **Supprimer la source CIA-A TA continue à `$00FF` avec interruption autorisée** pendant le démarrage. La vraie
   1.3 ne démarre pas TA de CIA-A (masque ICR `$0A` = TB + SP uniquement). Si une temporisation est nécessaire,
   utiliser un mode one-shot, une période longue, ou une attente sans interruption.
2. Plus généralement, aucune source d'interruption périodique ne doit avoir une période de l'ordre du coût du
   traitement : tout pilote ou carte peut ajouter des serveurs à n'importe quelle chaîne (UAE en ajoute un en PORTS
   à pri 20 et un en VERTB à pri −10 dès la DiagPoint).
3. Garder ce qui est déjà conforme (vérifié §4) : appel de la DiagPoint avec A2 = copie RAM inscriptible de
   ≥ `da_Size` octets, A3 = ConfigDev, A5 = ExpansionBase, A6 = ExecBase ; listes de serveurs PORTS/VERTB
   initialisées avant expansion ; AddIntServer et InitResident(NT_RESOURCE) utilisables à ce moment.
4. Chaîne de serveurs : arrêt au premier serveur qui rend Z = 0 (1.x), sinon parcours complet ; l'acquittement
   d'INTREQ avant le parcours est correct (une source niveau comme uae_int ou CIA-A non lu se réaffirme).

---

## 6. Vecteurs de test

Vraie ROM 34.5, FS-UAE 3.2.35, `slow_memory = 512`, `fast_memory = 2048`, `hard_drive_0 = <rép.>` (startup :
`intports >SER:`), ADF vierge ⇒ démarrage DH0:. Format de `tests/intports.s` : `IE intenar intreqr $F0FFEB` (lu
sous Disable, d'où INTEN absent) ; `SV vecteur nœud type<<8|pri is_Data is_Code nom` ; `RT adr
flags.ver.type.pri nom idstring` ; `RS adr nom`.

```
=== R1 : vraie ROM, après démarrage DH0:
IE 0000282C 00000041 00000001
SV 00000003 00C016A0 00000214 00F00300 00F00300 UAE filesystem
SV 00000003 00C017AA 00000200 00C01780 …        ciaa.resource
SV 00000005 00C02140 0000000A 00C020F6 …                      (graphics)
SV 00000005 00C0258C 00000200 00C0245C … gameport.device
SV 00000005 00C02688 00000200 00C0265E … timer.device
SV 00000005 00C016C0 000002F6 00F0FFFC 00F00408 UAE heart beat
SV 0000000D 00C01D22 00000200 00C01CF8 … ciab.resource
RT 00C01AF0 81320305 uaehf.device UAE hardfile.device 0.4
RT 00C01B0A 81010878 uae.resource UAE resource 3.3.0
RS 00C0166E uae.resource     (1re de ResourceList)
RS 00C016EA potgo.resource / 00C01718 keymap / 00C01780 ciaa / 00C01CF8 ciab / 00C01D96 disk /
   00C01E34 misc / 00C04DB8 FileSystem.resource (créée par uaehf à l'init romboot)
Journal : « filesystem: diagentry 00c01af0 configdev 00c01620 » puis « Mounting uaehf.device 0 ».
=== R2 : vraie ROM, débogueur à 5 s et à 25 s
A: CRA 00 CRB 08 IM 0a TA ffff (ffff) TB 02cb (02cb)     INTENA 602c
=== N1 : notre ROM + hard_drive_0, bloquée (débogueur à 25 s)
A: CRA 01 CRB 08 ICR 00 IM 03 TA 0028 (00ff)             INTENA 402c  INTREQ 1009  IPL 2
$F0FFE0 : 0000 0000 0000 0000 0000 0000 00E9 2000         ($F0FFEB = 00)
chaîne PORTS : UAE filesystem (pri 20) → pri 10 → pri 0
=== N2 : interventions (puis « w 0 dff030 2 w », g, 20 s)
aucune : pas de break ; CRA←00 + ICR←7F : break SERDAT, IMASK 0 ;
UAE retiré de la chaîne : break SERDAT ; latch TA ←0FFF : break SERDAT
=== N3 : notre ROM sans hard_drive_0, 25 s
A: CRA 00 CRB 08 IM 0a TA 00fd (00ff)                    INTENA 602c
```

Non-régression proposée pour notre ROM : N1 doit démarrer jusqu'au CLI ; `intports` doit alors montrer
« UAE filesystem » pri 20 en tête de PORTS, « UAE heart beat » pri −10 en VERTB, `uae.resource` dans
ResourceList, `$F0FFEB = 1` ; et CIA-A au repos doit avoir TA arrêté (comme R2).

---

## 7. Non sondé / incertain

- État instantané de la vraie ROM **entre** DiagPoint et romboot (INTENA, INTREQ) : non observé directement (pas de
  réinitialisation pilotable depuis le débogueur FS-UAE) ; déduit de l'ordre d'allocation et de la source UAE.
- Coût exact, en cycles, d'un passage niveau 2 sur notre ROM : non mesuré ; seul le franchissement du seuil
  (≈ 2 560 cycles CPU pour un latch `$00FF`) est établi par les interventions.
- Option FS-UAE d'intégration souris / presse-papiers activée : ajouterait une tâche et des requêtes uae_int
  après le démarrage, toujours servies par le même serveur PORTS ; non testé.
- Sur la vraie 1.3, AddIntServer autorise le bit INTENA du vecteur : non vérifié isolément (INTENA final cohérent).

---

## Relecture clean-room

- [x] Aucune suite d'instructions de la ROM transcrite ni paraphrasée ; aucune adresse de routine de la ROM
  d'origine (seules des adresses de données/allocations observées, des registres matériels et des adresses de la
  zone émulateur `$F0xxxx`).
- [x] Le code UAE (GPL, indépendant de la ROM) est décrit par son comportement, sans recopie.
- [x] Les observations de notre ROM sont boîte noire (registres matériels, mémoire), sans lecture de `src/`.
- [x] La sonde citée est du code auteur (`tests/intports.s`, en-tête « ASSET DE TEST, PAS du code ROM »).
