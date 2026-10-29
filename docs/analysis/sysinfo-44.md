# SysInfo 4.4 — comportement au démarrage, attentes bloquantes, exigences ROM

> **Avertissement clean-room.** Document de la piste ANALYSE. Il décrit uniquement des
> **comportements observables** et des **contrats d'ABI** (LVO appelés et leurs arguments,
> champs publics lus/écrits, registres matériels touchés, conditions de sortie des attentes).
> Il ne contient aucune suite d'instructions recopiée ni pseudo-code ligne à ligne.
> La ROM Kickstart n'a **pas** été lue pour ce travail ; la cible est un programme tiers.

## Provenance

| Élément | Valeur |
|---|---|
| Disquette | `assets/test_adf/SysInfo.adf` (lecture seule) |
| Fichier | `SYS:SysInfo/SysInfo`, 61892 octets, `$VER: SysInfo 4.4 (11.11.2020)` (T. Geijersson / N. Wilson) |
| Format | exécutable hunk **non crunché** : 7 hunks (CODE 0x8858, CODE 0x1398, CODE 0x3F4, DATA 0x38C4, DATA chip 0x534, BSS 0x20C, BSS chip 0x2564) |
| Outils | `xdftool read`, `hunktool info`, relocation à plat (script Python local), `r2 -a m68k` |
| Startup-sequence | `C:SetPatch_1.38 >NIL:` → `C:Initialize` → `SYS:SysInfo/SysInfo` |

**Conventions de localisation.** « H0+0xNNNN » = offset dans les données du hunk 0
(début des données à l'offset fichier **0x38**) ; « H1+0xNNNN » = hunk 1 (données à l'offset
fichier **0x994C**). L'offset fichier est donné entre crochets : `H0+0x6F72 [f 0x6FAA]`.

**Remarque sur les messages console.** « Identified Kickstart 34.0 (ROM 34.5) » et
« Kickstart 1.x (<=36), SetPatch 1.38 in use. » ne viennent **pas** de SysInfo mais de
`C:Initialize` 1.1 (même disquette), qui formate la version d'exec et ne lance
`c:SetPatch QUIET` que si la version est > 36. Ils prouvent seulement que la séquence de
démarrage est arrivée jusqu'à SysInfo.

**Chaînes.** La quasi-totalité des chaînes de SysInfo (libellés, noms `timer.device`,
`battclock.resource`, `card.resource`, `PAL`/`NTSC`, types d'Agnus/Denise…) est stockée avec le
bit 7 de chaque octet à 1 (zone H0+0x4A28…H0+0x63D0) et « désobfusquée » en place au
démarrage par un ET logique 0x7F. Un `strings` brut ne les montre donc pas.

---

## 1. Ordre des opérations au démarrage

### 1.0 Initialisation (H0+0x6AA4 [f 0x6ADC])

1. Code de démarrage C-like (ouverture dos/graphics/intuition/expansion).
2. Si `ExecBase->LibNode.lib_Version` (+0x14) < 36 : 5 gadgets (les boutons de cache
   ICACHE/DCACHE/IBURST/DBURST/CBACK) reçoivent `GFLG_DISABLED` (0x0100) dans `gg_Flags` (+0x0C).
   C'est le **seul garde** qui protège les appels V36+ `CacheClearU`/`CacheControl` (§4).
3. `pr_WindowPtr` (+0xB8 du Process courant) sauvé puis forcé à -1 (pas de requesters DOS).
4. Désobfuscation des chaînes, analyse des arguments (`-t` = mode texte, etc.).
5. Ouverture de l'écran + fenêtre à partir d'un ILBM embarqué (DATA hunk 3), puis dessin de
   tous les libellés (`SetAPen` -342, `SetBPen` -348, `SetDrMd` -354, `RectFill` -306, texte via
   `PrintIText` -216 et `RefreshGList` -432 / `AddGList` -438 d'intuition).
6. Calcul de la fréquence horizontale (voir 1.2, « Horiz »).

### 1.1 Chaîne de détection (H0+0x0004…H0+0x0038 [f 0x3C…0x70])

Appel séquentiel, dans cet ordre :

| # | Routine | Rôle | Affiché chez nous ? |
|---|---|---|---|
| 1 | H0+0x647A | CPU (AttnFlags +0x128, sondes sous `Supervisor` -30) | oui |
| 2 | H0+0x66AC | FPU | oui |
| 3 | H0+0x679A | MMU / VBR (`FindName` -276 sur `ExecBase->ResourceList` +0x150, `Supervisor`) | oui |
| 4 | H0+0x6920 | Contrôle de cohérence AttnFlags (voir §4) | oui |
| 5 | H0+0x699E | Caches (Disable/Enable autour des sondes) | oui |
| 6 | H0+0x729A | Liste « SYSTEM SOFTWARE » : parcourt `ExecBase->LibList` (+0x17A), entrée « kickstart » | oui |
| 7 | **H0+0x6F72 [f 0x6FAA]** | **Détection d'horloge matérielle** (« Clock ») | **NON → blocage ici** |
| 8 | H0+0x6FDE [f 0x7016] | DMA/Gfx (Agnus) — affiche immédiatement | non |
| 9 | H0+0x703C [f 0x7074] | Mode (PAL/NTSC) — affiche immédiatement | non |
| 10 | H0+0x70E8 [f 0x7120] | Display (Denise) — affiche immédiatement | non |
| 11 | H0+0x711A | Liste des volumes/unités (DOS) | — |
| 12 | H0+0x7182 [f 0x71BA] | Vert Hz, Supply Hz, Horiz KHz | non |
| 13 | H0+0x721C | Card Slot (`OpenResource("card.resource")`) | — |
| 14 | H0+0x7248 [f 0x7280] | Affiche « Clock » (résultat de #7) et EClock Hz | non |

L'attribution exacte des rôles 1 à 5 est approximative (non nécessaire ici) : ces routines
s'exécutent et affichent leurs champs chez nous. Les routines 8, 9, 10 écrivent leur champ **dès leur exécution**. Comme DMA/Gfx, Mode et
Display sont vides alors que la liste des bibliothèques (#6) est dessinée, l'exécution est
arrêtée **dans #7** (seul appel entre les deux). Voir §5.

### 1.2 Sources de chaque champ

- **Clock** (#7, affiché en #14) — `Forbid` (-132) pendant toute la routine, puis :
  - `OpenResource("battclock.resource")` (-498). Si présente : appel de son LVO **-12**
    (`ReadBattClock`) ; résultat 0 → « CLOCK NOT FOUND », sinon « CLOCK FOUND ».
  - **Si absente** (cas KS 1.3) : sondage direct de la puce RTC — lecture **octet** à
    **$DC0001** (registre « secondes, unités », quartet bas). Attente que ce quartet ≠ 9,
    puis **attente de 60 ticks du TOD de la CIA-A** (≈1,2 s), puis relecture : si les
    secondes ont avancé de 1 ou 2 → FOUND, sinon NOT FOUND.
  - `Permit` (-138).
- **DMA/Gfx** (#8) — lit **VPOSR $DFF004** (mot), ID Agnus = bits 14..8 :
  ID = 0x23 → « AGA ALICE » ; (ID>>4) > 3 → « UNKNOWN » ; (ID>>4) < 2 → « STD AGNUS – 512K » ;
  (ID>>4) ∈ {2,3} → compare le long mot à **$100004** à `SysBase` (miroir chip à 1 Mo) :
  égal → « ECS AGNUS – 1Meg », sinon « ECS AGNUS – 2Meg ». (La lecture $100004 n'a lieu que
  pour un Agnus ECS.)
- **Mode** (#9) — si exec ≥ 36 : `GetVPModeID`/`FindDisplayInfo`/`GetDisplayInfoData`
  (graphics -792/-726/-756) sur le ViewPort du premier écran. **Si exec < 36** : même ID
  Agnus que ci-dessus ; ID ∈ {0x0A, 0x1E} → « NTSC », sinon « PAL ». Aucun champ
  GfxBase n'est lu (ni `DisplayFlags`).
- **Display** (#10) — lit **DENISEID $DFF07C**, octet bas : 0xF8 → « AGA LISA », 0xFC →
  « ECS DENISE », sinon « STD DENISE ».
- **Vert Hz** (#12) — `ExecBase->VBlankFrequency` (**+0x212**, octet) ; valeur aussi mémorisée
  pour tous les calculs de vitesse.
- **Supply Hz** (#12) — `ExecBase->PowerSupplyFrequency` (**+0x213**, octet).
- **Horiz KHz** (calculé en 1.0, affiché en #12) — exec ≥ 36 : `GetDisplayInfoData`
  (DisplayInfo, champs PixelSpeed/… ) ; **exec < 36 : constante 15.72**, aucune lecture.
- **EClock Hz** (#14) — exec ≥ 36 : `ExecBase->ex_EClockFrequency` (**+0x238**, long) ;
  **exec < 36 : constante** choisie selon `VBlankFrequency` : 50 → 709379, sinon 716933.
  Aucune mesure, aucune lecture matérielle.
- **Card Slot** (#13) — simple présence de `card.resource`.

### 1.3 Tests de vitesse (après la chaîne, H0+0x003C…H0+0x0624)

Ordre :

1. Affiche « COMPUTING SPEED » (barre de progression), puis **H1+0x0000 [f 0x994C]** :
   `WaitTOF` (graphics -270), puis coupe le DMA sprite (DMACON $DFF096 ← $0020) et efface
   SPR0POS/SPR0CTL ($DFF140 ← 0x00020000). Le pointeur disparaît pendant les tests.
2. Efface la colonne « You » (`RectFill`).
3. `Forbid` → **Dhrystone** (H0+0x3068 [f 0x30A0]) → `Permit`. Mesure par compteur de VBlank (§2.3).
4. Six comparaisons (A500, B2000, A2500, A1200, A3000, A4000) = rapport du score obtenu à des
   constantes ; affichées une par une. Puis Dhrystones/s et Mips.
5. Si FPU détecté : MFlops (H0+0x40D0, `WaitTOF` + compteur VBlank) ; sinon « N/A ».
6. `Forbid` → **vitesse de la Chip RAM** (H0+0x35CE [f 0x3606]) → `Permit` ; affichage.
7. « Nics Comment » : texte choisi par seuils sur le score Dhrystone (aucune lecture système,
   sauf AttnFlags bit 10 pour un 68080).
8. « COMPUTING MHz » → `Forbid` → **test MHz** (H0+0x2F70 [f 0x2FA8]) → `Permit` → affiche
   « CPU speed in MHz » (corrigé selon `VBlankFrequency` +0x212 ou `ex_EClockFrequency` si V36+).
9. **H1+0x0022 [f 0x996E]** : `WaitTOF` puis rétablit le DMA sprite (DMACON ← $8020).
10. Boucle d'événements IDCMP (`WaitPort` -384 / `GetMsg` -372 / `ReplyMsg` -378) — attente
    normale, pas un blocage.

timer.device n'est **pas** utilisé au démarrage : il n'est ouvert que par la page DRIVES
(voir §2.6).

---

## 2. Attentes bloquantes et boucles d'attente

### 2.1 Sondage RTC $DC0001 — H0+0x6FA0 [f 0x6FD8] (chemin « pas de battclock.resource »)

- Lecture octet répétée de $DC0001, quartet bas ; **sortie : quartet ≠ 9**.
- Sous `Forbid`. Aucune borne.
- Avec une vraie RTC (MSM6242), le chiffre change chaque seconde : sortie en ≤ 1 s.
- Sans RTC, la valeur lue est celle du « bus ouvert » de l'émulateur : la boucle ne bloque que
  si cette valeur a **constamment** 9 en quartet bas. Peu probable, mais à vérifier (§5).

### 2.2 Attente de 60 ticks du TOD CIA-A — **H0+0x3364 [f 0x339C]** (appelée seulement depuis H0+0x6FAC)

- Lecture du compteur 24 bits TOD de la **CIA-A** par **H1+0x0C0E [f 0xA55A]** : octets
  **$BFEA01 (TODHI)**, puis **$BFE901 (TODMID)**, puis **$BFE801 (TODLO)**, dans cet ordre
  (lecture de HI = verrouillage, lecture de LO = déverrouillage).
- Un premier échantillon est pris, puis le compteur est relu en boucle jusqu'à ce que
  **(courant − initial) == 60 exactement** (égalité, pas ≥).
- Toujours sous le `Forbid` de la détection d'horloge. Aucune borne de temps.
- **Ce qui doit la satisfaire :** le TOD de la CIA-A doit **compter** (incrément de 1 par
  impulsion VSYNC/50 Hz, entrée TOD câblée en matériel). Conditions de sortie ratées :
  1. **TOD arrêté** : le 8520 arrête le TOD sur écriture de TODHI et ne le relance que sur
     écriture de TODLO (avec CRB bit 7 = 0). Dans UAE, le TOD est arrêté après le reset tant
     que TODLO n'a pas été écrit (comportement d'émulation, à confirmer par sonde). Si personne
     n'écrit TODLO → différence figée à 0 → **boucle infinie**.
  2. **Premier échantillon périmé** : si le TOD a été laissé **verrouillé** (lecture de TODHI
     sans lecture ultérieure de TODLO) depuis plus de 1,2 s, le premier échantillon est
     ancien, la différence dépasse d'emblée 60 et n'y revient jamais (jusqu'au rebouclage
     24 bits, ~93 h).
  3. **Saut de valeur** : si un tick est sauté entre deux lectures (une interruption qui
     dure > 20 ms sous ce `Forbid`), l'égalité exacte peut être manquée.

### 2.3 Dhrystone — H0+0x3068 [f 0x30A0], test de sortie H0+0x30DE [f 0x3116]

- Met à 0 un compteur long, `WaitTOF`, puis **`AddIntServer(INTB_VERTB=5, node)`** (-168).
  Node à **H0+0x4564 [f 0x459C]** : `ln_Type` = NT_INTERRUPT, `ln_Pri` = **127**,
  `ln_Name` = « Sysinfo.Interrupt », `is_Data` = adresse du compteur, `is_Code` =
  H0+0x33D2 [f 0x340A].
- Le serveur : incrémente le long mot pointé par **A1 (= is_Data)**, met A0 = $DFF000,
  D0 = 0 (flag Z positionné), retourne ; il **écrase A5**.
- Boucle de calcul tant que compteur < **4 × VBlankFrequency** (+0x212), puis
  `RemIntServer` (-174). Exécuté sous `Forbid` (les interruptions doivent tourner).
- **Doit la satisfaire :** la chaîne de serveurs VERTB (niveau 3, INTREQ bit 5) doit être
  appelée à chaque trame, avec **A1 = is_Data**, sans dépendre de A5/A0/D0/D1 préservés.
  Si `VBlankFrequency` = 0, la boucle sort tout de suite (score absurde, voir 2.5).

### 2.4 Début/fin de mesure générique — H0+0x3376 [f 0x33AE]

- Bascule (bit 0 d'un octet BSS) : 1er appel = `AddIntServer(5, même node)` + échantillon
  TOD ; 2e appel = `RemIntServer`, renvoie (compteur VBlank − 1) et mémorise un delta TOD
  (**jamais réutilisé** ailleurs). Utilisée par le test MHz (H0+0x2F70), la Chip RAM
  (H0+0x35CE), le blitter (bouton SPEED) et la mémoire (bouton SPEED).
- **Doit la satisfaire :** même exigence VERTB que 2.3. Le TOD n'y est lu que pour un
  résultat inutilisé : il ne peut pas bloquer ici.

### 2.5 Vitesse Chip RAM — boucle adaptative H0+0x363A [f 0x3672]

- Mesure le nombre de VBlanks pendant un bloc de lectures `MOVEM` de la Chip RAM ; si
  **≤ 25 trames**, le nombre d'itérations est multiplié (~×100) et on recommence. **Aucune
  borne** : si le compteur VBlank ne progresse pas, la boucle ne termine jamais en pratique.
- Divisions par `VBlankFrequency` si ≠ 50 : **VBlankFrequency = 0 → exception division
  par zéro** (aussi dans le test MHz, H0+0x2FC6 [f 0x2FFE]).

### 2.6 Autres attentes (hors chemin de démarrage)

| Lieu | Attente | Condition de sortie | Déclencheur |
|---|---|---|---|
| H0+0x4546 [f 0x457E] | sondage **VHPOSR $DFF006**, octet haut | ligne verticale (bits 7..0) == 1 | rafraîchissement de la liste SYSTEM SOFTWARE (#6, **passe chez nous**) |
| H0+0x3800, H0+0x3836 | idem ($DFF006 == 1) | idem | bouton SPEED / option `-t` |
| H0+0x2A92 [f 0x2ACA] | boucle `DoIO` (-456) `TR_GETSYSTIME` (cmd 10, `io_Flags` = IOF_QUICK) | `tv_micro` (+0x24 de l'IORequest) a avancé d'au moins 10 µs (comparaison signée) | page DRIVES (« READING THE DRIVE ») |
| `WaitTOF` (graphics -270) | ~9 appels | retour de graphics après la prochaine trame | tests de vitesse |
| H1+0x0066… | `WaitPort`/`GetMsg` | message IDCMP | boucle principale (normal) |

timer.device (page DRIVES) : `OpenDevice("timer.device", unit, ior, 0)` (-444) avec
**unit = UNIT_ECLOCK (2) si exec ≥ 36, sinon UNIT_VBLANK (1)** ; IORequest de 0x28 octets ;
`SubTime` (timer LVO -48) ; `CloseDevice` (-450). Notre `TR_GETSYSTIME` doit donc faire avancer
`tv_micro`/`tv_secs` au fil des VBlanks, sinon la page DRIVES gèlera.

---

## 3. Détections

- **Kickstart.** `ExecBase->LibNode.lib_Version` (+0x14) comparée à 36 en de nombreux endroits
  (chemin V34 vs V36+). Pour l'entrée « kickstart » de la liste : prend
  `ExecBase->LibNode.lib_IdString` (+0x18), **arrondi à 64 Ko** → base supposée de la ROM ; si
  le long mot à cette base vaut **$11114EF9** → ROM 256 Ko, sinon 512 Ko ; affiche adresse et
  version/révision. (Un autre chemin lit le vecteur PC initial à $F80004.) Il faut donc que
  `lib_IdString` d'exec pointe dans les 64 premiers Ko de la ROM ($FC0000–$FCFFFF).
- **Chipset.** VPOSR $DFF004 (ID Agnus bits 14..8) et DENISEID $DFF07C (octet bas), cf. §1.2.
  Le long mot à $100004 n'est lu que si l'Agnus est ECS.
- **PAL/NTSC.** En V34 : **ID Agnus** (pas GfxBase). `GfxBase->DisplayFlags` n'est **jamais**
  lu. `VBlankFrequency` (+0x212) et `PowerSupplyFrequency` (+0x213) servent pour Vert/Supply
  et pour tous les calculs de vitesse/EClock.
- **EClock.** En V34 : constante 709379 (si VBlankFrequency = 50) ou 716933 ; +0x238 n'est lu que
  si exec ≥ 36 (ou si AttnFlags bit 10 « 68080 » est mis, cas qui lit aussi le registre
  $DFF3FC propre au Vampire).
- **Horloge.** `battclock.resource` (LVO -12) si présente, sinon RTC à **$DC0001** directement +
  attente TOD CIA-A (§2.1, 2.2). Pas de cia.resource, pas de timer.device.

---

## 4. Accès privés / > V34 et gardes

| Accès | Garde | Verdict |
|---|---|---|
| exec `CacheClearU` (-636, V37) | version ≥ 36 dans le Dhrystone ; dans les boutons de cache, garde **indirecte** : gadgets désactivés si V < 36 | sûr en V34 tant que nos gadgets désactivés ne répondent pas |
| exec `CacheControl` (-648, V36) | boutons de cache uniquement (désactivés en V34) | idem |
| graphics `GetVPModeID` -792, `FindDisplayInfo` -726, `GetDisplayInfoData` -756 (V36) | version ≥ 36 | sûr |
| `ExecBase->ex_EClockFrequency` +0x238 (V36) | version ≥ 36, ou AttnFlags bit 10 | sûr si notre AttnFlags n'a pas le bit 10 |
| $DFF3FC | AttnFlags bit 10 | sûr |
| `ExecBase->AttnFlags` +0x128 **écrit** | seulement si la détection CPU/FPU contredit AttnFlags **et** que l'utilisateur accepte le requester « Exec does not reflect your hardware correctly » | ne se produit pas chez nous (pas de requester observé) |
| `pr_WindowPtr` +0xB8 écrit (-1), restauré à la sortie | — | champ public V33 |
| $DC0001 (RTC), $BFE801/$BFE901/$BFEA01 (TOD CIA-A), $DFF004, $DFF006, $DFF07C, $DFF096, $DFF140, $100004 | — | matériel, lu/écrit directement |

Aucun LVO > V34 n'est appelé sans garde sur le chemin de démarrage. Les champs ExecBase lus sont
tous publics V34 : +0x14, +0x18, +0x128, +0x150 (ResourceList), +0x17A (LibList), +0x212, +0x213.

---

## 5. Hypothèse principale du blocage

**SysInfo est bloqué dans la détection d'horloge (#7, H0+0x6F72), sous `Forbid`, dans
l'attente de 60 ticks du TOD de la CIA-A (H0+0x3364).** Raisonnement :

1. La liste SYSTEM SOFTWARE (#6) est dessinée et DMA/Gfx (#8) ne l'est pas ; #7 est le seul
   code exécuté entre les deux, et #8–#10 n'attendent rien.
2. Notre ROM ne fournit pas `battclock.resource` (pas plus que le vrai 1.3) → chemin RTC direct
   + attente TOD.
3. Notre ROM n'écrit jamais les registres TOD de la CIA-A (aucune référence à TODLO/TODMID/TODHI
   dans `src/`). Si le TOD est arrêté après le reset (modèle UAE), la différence reste 0 →
   boucle infinie, sans exception CPU. Le `Forbid` gèle aussi toutes nos autres tâches, d'où
   « ça ne bouge plus ».

Hypothèse secondaire, moins probable : FS-UAE sans RTC renvoie à $DC0001 une valeur de bus
ouvert dont le quartet bas vaut toujours 9 (boucle §2.1).

**Sonde de confirmation proposée** (côté harnais, sans toucher SysInfo) : dans un build de test,
lire le TOD de la CIA-A (HI, MID, LO) à deux instants séparés de quelques trames et imprimer les
deux valeurs sur la série ; lire aussi $DC0001 plusieurs fois. TOD figé = hypothèse confirmée.

Une fois débloqué, les tests de vitesse imposent les exigences VERTB de §2.3–2.5 (sinon blocage
dans la boucle Chip RAM, sans borne).

---

## Exigences pour notre ROM

1. **Démarrer le TOD de la CIA-A** pendant l'init (comme le ferait l'OS pour son horloge
   VSYNC) : écrire TODHI, TODMID puis **TODLO en dernier** avec **CRB bit 7 (ALARM) = 0** ; ne
   jamais laisser le TOD verrouillé (toute lecture de TODHI doit être suivie d'une lecture de
   TODLO). Le TOD doit ensuite s'incrémenter de 1 par trame.
2. Ne pas exécuter, dans nos handlers d'interruption, de traitement de plus d'une trame (20 ms)
   — SysInfo attend une valeur exacte de delta TOD sous `Forbid`.
3. **Chaîne de serveurs VERTB** (`AddIntServer`/`RemIntServer` INTB_VERTB = 5) : appel à
   chaque trame, priorité 127 en tête, **A1 = is_Data**, A5 = is_Code ; ne pas compter sur A0,
   A1, A5, D0, D1 préservés au retour ; respecter le flag Z de retour (Z = 1 → continuer la
   chaîne). Le serveur de SysInfo rend A0 = $DFF000 (convention 1.x pour les serveurs VERTB).
4. `ExecBase->VBlankFrequency` (+0x212) = 50 et `PowerSupplyFrequency` (+0x213) = 50
   (déjà le cas dans notre boot) — une valeur 0 provoquerait une division par zéro.
5. `ExecBase->LibNode.lib_IdString` dans les 64 premiers Ko de la ROM, ROM commençant par
   `$1111 4EF9` (entrée « kickstart » et taille 256K).
6. `lib_Version` d'exec < 36 (34) pour rester sur les chemins V34 ; AttnFlags sans bit 10 ; les
   gadgets `GFLG_DISABLED` ne doivent ni répondre ni envoyer de GADGETUP (sinon appels V36
   `CacheControl`/`CacheClearU` vers des vecteurs inexistants).
7. VPOSR/DENISEID lisibles (matériel) ; `WaitTOF` (graphics -270) qui revient à chaque trame.
8. Optionnel : `battclock.resource` avec `ReadBattClock` (LVO -12) court-circuiterait le
   sondage RTC + TOD (un retour 0 = « CLOCK NOT FOUND »). Ce n'est pas une ressource 1.3 ;
   l'exigence 1 est la correction compatible.
9. Pour la page DRIVES : timer.device `UNIT_VBLANK`, `TR_GETSYSTIME` via `DoIO` avec IOF_QUICK
   dont le temps avance, et `SubTime` (LVO -48) fonctionnel.

---

## Suite 2026-10-21 — écran gris, octets série, robustesse des attentes

> Même discipline : comportement et ABI uniquement, aucune suite d'instructions recopiée.
> Contexte : le TOD des deux CIA est maintenant démarré par notre init ; l'attente §2.2 passe.
> Symptômes : bande grise en haut puis noir à 120 s, écran entièrement gris uni à 300 s ;
> sur la série, un octet $FC puis des « f » ($66) environ toutes les 30 s.

### S1. Ce qui suit la détection d'horloge, et ce que SysInfo fait à l'affichage

Ordre (inchangé, voir §1.1/§1.3) : DMA/Gfx → Mode → Display → liste des unités DOS → Vert/Supply/
Horiz → Card → Clock/EClock → tests de vitesse → boucle d'événements.

Inventaire **exhaustif** des écritures matérielles « custom » de tout le code (hunks 0 et 1) :

| Lieu | Registre | Valeur / effet | Quand |
|---|---|---|---|
| H1+0x0000 [f 0x994C] | DMACON $DFF096 | $0020 : coupe **seulement le DMA sprite** | début des tests de vitesse, après un `WaitTOF` |
| H1+0x0000 | SPR0POS/SPR0CTL $DFF140 (long) | $00020000 | idem |
| H1+0x0022 [f 0x996E] | DMACON | $8020 : rétablit le DMA sprite | fin des tests de vitesse, après un `WaitTOF` ; **inconditionnel** (pas de condition d'erreur) |
| H1+0x011A…0x0172 | AUD0LC/LEN/PER/VOL ($DFF0A0…), ADKCON $DFF09E ← $00FF, DMACON $8201 puis $0001 | bip sur la voie audio 0, `Delay` dos entre les deux | sur un événement de la boucle principale seulement |

SysInfo n'écrit **jamais** BPLCON0, les couleurs ($DFF180…), COP1LC/COPJMP, BPLxPT, DIWSTRT/STOP,
ni le bit bitplane/copper/DMAEN de DMACON. Il n'appelle ni `LoadView` (graphics -222), ni
`OFF_DISPLAY`, ni `LoadRGB4`/`SetRGB4` sur la palette de l'écran pendant les mesures (le seul
chargement de palette est celui de l'ouverture de l'écran depuis l'ILBM). **Aucune mesure ne
produit un écran gris uni** : pendant les tests, l'affichage reste celui de son écran, seul le
pointeur disparaît.

Un écran gris uni sans bitplane correspond à « aucun écran intuition affiché » (COLOR00 seul).
Chez SysInfo, le seul chemin qui retire son affichage est la **sortie** (gadget QUIT) :
`CloseWindow` (-72) puis `CloseScreen` (-66) de son écran, `ActivateWindow` (-450) sur la
première fenêtre du `FirstScreen` restant (IntuitionBase +0x3C → +0x04), restauration de
`pr_WindowPtr`, retour au CLI avec code 0. SysInfo est la dernière commande de la
startup-sequence : le CLI se termine ensuite (fin de script). S'il ne reste alors aucun écran,
notre ROM affiche du gris uni.

**Boucle d'événements (H0+0x0674, aide H1+0x0060) — point fragile.** Fenêtre principale :
IDCMP = **GADGETUP seulement** ($00000040), drapeaux BACKDROP/BORDERLESS/ACTIVATE/NOCAREREFRESH,
écran CUSTOMSCREEN ouvert derrière (SCREENBEHIND) puis passé devant (`ScreenToFront` -252).
À chaque réveil :
- `WaitPort` puis `GetMsg` sur le UserPort de la fenêtre (Window +0x56) ;
- si `GetMsg` rend NULL, l'aide rend A0 = 0 mais **A1 reste celui que `GetMsg` a laissé** ;
- sinon : A1 = `im_IAddress` (+0x1C), D0 = `im_Class` (+0x14), D1 = `im_Code` (+0x18),
  D2 = `im_Qualifier` (+0x1A) ; le message est **renvoyé (`ReplyMsg`) sauf si la classe vaut 8
  (MOUSEBUTTONS)**, qui n'est jamais renvoyé ;
- l'appelant **ne teste pas la classe** : il lit directement `GadgetID` (+0x26) à l'adresse A1 et
  aiguille. ID 1 → **QUIT** ; ID 2 → relance des tests de vitesse ; 4, 6, 7, 8, 9, 10, 12–17 →
  pages et boutons de cache ; **tout autre ID** (y compris une valeur aléatoire) → requester
  PRINT puis `Open` (dos -30) de « prt: » ou du nom saisi, en MODE_NEWFILE, et écriture du rapport.

Donc tout message reçu qui n'est pas un vrai GADGETUP d'un gadget de SysInfo (autre classe, ou
réveil de `WaitPort` sans message) fait lire un `GadgetID` au hasard, et peut déclencher QUIT,
SPEED ou PRINT sans action de l'utilisateur.

### S2. Le serveur VERTB et les autres installations

- Serveur unique, node H0+0x4564 [f 0x459C] (pri 127, NT_INTERRUPT, « Sysinfo.Interrupt »),
  code H0+0x33D2 [f 0x340A]. **Il rend Z = 1** (et D0 = 0) : la dernière opération qui pose les
  codes conditions avant le retour est le chargement de la constante 0 dans D0 ; le chargement de
  $DFF000 dans A0 qui la précède ne touche pas les CCR (registre d'adresse). Une chaîne qui
  continue tant que Z = 1 **continue** après lui.
- Registres modifiés par le serveur : le long mot pointé par A1 (incrémenté), **A0 ← $DFF000**,
  **D0 ← 0**, **A5 ← valeur d'entrée de D0**. A1 n'est pas modifié. Notre parcours de chaîne ne
  doit garder son état (nœud courant/suivant) dans aucun de D0/D1/A0/A1/A5/A6.
- Ce même node est ajouté/retiré par `AddIntServer`/`RemIntServer` (INTB_VERTB) autour de chaque
  mesure (Dhrystone, MHz, Chip RAM, MFlops, blitter, mémoire). Il n'est jamais ajouté deux fois
  en même temps (bascule d'état).
- Aucun `SetIntVector` (-162), aucun autre numéro d'interruption, aucune écriture directe dans les
  vecteurs CPU ($64/$68/$6C… ni autres), pas de `movec`/VBR en écriture.
- **Interception de pièges par la tâche** : pour sonder FPU/MMU, il remplace temporairement
  `tc_TrapCode` (+0x32 de sa Task) par sa routine, exécute une instruction qui fait un piège sur un
  68000 (ligne F), puis remet l'ancienne valeur. Contrat attendu : l'exception CPU d'une tâche en
  mode utilisateur est envoyée à `tc_TrapCode` avec le numéro de piège en haut de la pile
  superviseur ; la routine le retire et fait un RTE vers une adresse de reprise qu'elle a choisie.
  Ça marche déjà chez nous (« FPU NONE » affiché).
- `Disable`/`Enable` (-120/-126) : une seule paire, courte, dans les sondes de cache (#5). Les
  longues mesures sont sous **`Forbid`**, jamais sous `Disable`.

### S3. Port série

SysInfo **n'écrit jamais** SERDAT ($DFF030) ni SERPER ($DFF032), sous aucune forme (adresse
absolue ou décalage depuis une base $DFF000). Ses boucles de mesure ne font que **lire** :
- test Chip RAM : lectures longues consécutives de **$000200 à ≈$07FC00** (chip seulement,
  jamais de registres custom) ;
- test mémoire du bouton SPEED : lectures d'une zone allouée ;
- Dhrystone et MHz : calcul sur registres et lectures d'une petite table de son hunk.

Le seul chemin de SysInfo qui peut produire des octets sur un port est **PRINT** (S1) : `Open`
de « prt: » puis écriture du rapport texte. Si notre PRT: est redirigé vers la série, un PRINT
déclenché par erreur (ID de gadget aléatoire) écrirait là. Le motif observé ($FC puis un « f »
toutes les ~30 s) ne ressemble pas à ce rapport (texte lisible et long) : il est plus probable
qu'il vienne d'ailleurs (notre ROM, ou un pointeur corrompu qui écrit à $DFF030). Rien dans SysInfo
n'a une période de 30 s.

### S4. Boucles qui ne se terminent pas selon la panne

| Panne | Boucles bloquées (sans borne) | Effet visible |
|---|---|---|
| (a) chaîne VERTB coupée **après** son serveur | aucune côté SysInfo (son compteur tourne quand même) ; mais sous `Forbid` nos serveurs suivants (ordonnanceur, timer.device, graphics/`WaitTOF`) ne tournent plus → voir (b) et (c) | |
| (a') son serveur **non appelé** (chaîne coupée avant lui, ou mauvais A1) | Dhrystone (sort quand compteur ≥ 4×VBlankFrequency) ; **Chip RAM** (recommence en multipliant le travail tant que ≤ 25 trames : 2,6 s, puis ~280 s, puis des heures) ; MHz/MFlops finissent mais avec des valeurs fausses | figé sous `Forbid`, affichage intact |
| (b) timer.device muet | aucune au démarrage (timer.device n'est ouvert que par la page DRIVES) ; page DRIVES : `DoIO` `TR_GETSYSTIME` en boucle tant que `tv_micro` n'a pas avancé de 10 µs | — |
| (c) `WaitTOF` ne revient pas | bloque avant Dhrystone (H1+0x0000), avant MHz, avant MFlops, avant Chip RAM, et à la fin des tests (H1+0x0022) | sprite coupé, pas de résultat |
| (d) `Disable` actif | attente TOD §2.2 (le TOD avance en matériel, donc elle passe) ; **toutes** les mesures par compteur VBlank (aucune interruption) → Dhrystone et Chip RAM sans fin ; attente de ligne VHPOSR (§2.6) : passe (matériel) | figé |
| boucle principale | `WaitPort` : bloque tant qu'aucun message n'arrive (normal) | |

### S5. Diagnostic et exigences complémentaires

**Cause la plus probable de l'écran gris :** SysInfo n'agit pas sur l'affichage. L'écran gris uni
correspond à **son écran fermé** : sortie par le chemin QUIT, puis fin du CLI de la
startup-sequence, et il ne reste plus d'écran. Comme personne ne clique, le déclencheur probable
est un **message IDCMP qui n'est pas un vrai GADGETUP** (ou un réveil de `WaitPort` sans message).
La boucle d'événements le prend pour un clic sur un gadget dont le `GadgetID` est lu au hasard.
À confirmer : tracer sur la série `CloseScreen`, la fin du process SysInfo et chaque `PutMsg`
vers son UserPort (classe, IAddress).

Notre ROM doit garantir :
1. Intuition n'envoie à une fenêtre **que les classes IDCMP demandées** (ici GADGETUP seul) ; pour
   GADGETUP, `im_IAddress` = la `struct Gadget` du gadget relâché (GadgetID lu à +0x26).
2. `WaitPort` ne revient que si la liste du port n'est pas vide (il reboucle sur un réveil sans
   message), afin que le `GetMsg` qui suit ne rende jamais NULL.
3. Parcours de la chaîne VERTB : continuer sur Z = 1, ne garder aucun état dans D0/D1/A0/A1/A5/A6
   pendant l'appel d'un serveur, recharger A1 = is_Data et A5 = is_Code à chaque serveur.
4. `WaitTOF` revient à chaque trame, même sous `Forbid` (réveil depuis l'interruption).
5. Exceptions CPU en mode utilisateur envoyées à `tc_TrapCode` de la tâche courante.
6. Si PRT: est redirigé vers la série, le savoir : un PRINT déclenché par erreur y écrirait le
   rapport.

## Relecture clean-room

Relecture du 2026-10-29.

- [x] Cible = programme tiers SysInfo 4.4 (désassemblage permis) ; la ROM Kickstart n'a pas été lue.
  Les localisations « H0+… / H1+… [f …] » sont des offsets **dans SysInfo**, pas dans la ROM.
- [x] Aucune adresse de routine ROM et aucune donnée de la ROM Kickstart transcrite : les seules
  valeurs liées à la ROM sont l'en-tête public `$1111 4EF9`, la position attendue de `lib_IdString`
  (64 premiers Ko) et des offsets publics d'ExecBase/Process/Window/IntuiMessage ; les autres adresses
  sont matérielles (`$DFF0xx`, `$BFE801…`, `$DC0001`) ou de la zone ROM générique (`$F80004`).
- [x] Les détails d'instructions évoqués (S2 : comment le serveur VERTB de SysInfo positionne Z)
  concernent le code de SysInfo et servent à fixer le contrat que notre chaîne VERTB doit respecter.
