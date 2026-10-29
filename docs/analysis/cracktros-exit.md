# cracktros-exit.md — sortie des intros NOMAD/QUARTEX (Scooby-Doo), defjam (Monkey Island), RAZOR (SimCity)

> Piste ANALYSE (« dirty »). Fichiers extraits des ADF par un lecteur OFS tolérant. Les quatre
> exécutables sont **un seul hunk CODE sans relocation, compacté** (décompacteur maison en tête).
> Ils ont été décompactés **par émulation 68000** (Unicorn, scratch de la piste analyse : RAM à
> plat, registres custom/CIA simulés et journalisés, ExecBase factice qui journalise les LVO
> appelés), puis désassemblés. Fonctions ROM concernées : graphics 34 (serveur VBlank,
> installation des interruptions).
>
> **Légende** : **[O]** observé · **[D]** déduit · **[S]** supposé. Comportement, registres et
> valeurs ; aucune suite d'instructions recopiée, aucune donnée d'image ni de musique.
> « Absolu » = adresse fixe écrite **sans** AllocMem/AllocAbs.

---

## 0. Points communs [O]

- Aucun des quatre n'alloue la mémoire qu'il utilise. Chacun **se décompacte vers une adresse
  absolue** en CHIP (tableau §5).
- Le clic est toujours lu **en scrutant CIA-A PRA ($BFE001) bit 6** (actif à 0). Aucun ne
  passe par une interruption, gameport.device ou input.device.
- Le seul autre bouton lu est le bouton droit (POTINP $DFF016 bit 10), par RAZOR, et seulement
  dans son chemin d'échec d'ouverture de dos.library.
- Ils prennent la main en **superviseur** de deux façons :
  - `trap #0` après avoir écrit le vecteur $80 (NOMAD, defjam) ;
  - ou un MOVE vers SR qui déclenche une violation de privilège, dont le vecteur $20 a été
    redirigé vers l'instruction suivante (QUARTEX).

---

## 1. Scooby-Doo [cr QTX] : `NOMAD` (5 872 o) puis `QUARTEX` (58 740 o)

### 1.1 NOMAD = l'intro affichée (clic → retour au CLI)

**Démarrage** :
- décompactage vers **$50000–$5E150** ;
- écriture du vecteur **$80** (trap #0) = $50038, puis `trap #0`.

**En superviseur** :
- sauvegarde de SR, **DMACONR** et **INTENAR** ;
- SR := $2700 ;
- **DMACON := $7FFF** (tout coupé), **INTENA := $7FFF** (tout coupé, INTEN compris) ;
- COLOR31 := 0 ; INTREQ := $0020 (acquitte VERTB) ;
- **COP2LC := $50D80** (sa liste) ;
- init des tables, effacement d'un port clavier (CIA-A SDR := 0) ;
- **COPJMP2 strobe** ($DFF08A) : il lance lui-même sa liste et ne dépend pas de copinit ;
- **DMACON := $87C0** (DMAEN, BPLEN, COPEN, BLTEN, BLTPRI ; sprites, disque et audio coupés) ;
- PRA bit 1 mis à 1 (LED / filtre).

**Boucle par trame**, toutes interruptions masquées :
1. **attente active de INTREQR bit 5 (VERTB)**, levé par le matériel même avec INTENA à 0 ;
2. travail de la trame, puis INTREQ := $0020 ;
3. lecture clavier : si INTREQR bit 3 (PORTS) vaut 1, lecture de CIA-A SDR, handshake par CRA
   bit 6 avec une attente CPU, décodage du code. **Ni ICR ni INTREQ ne sont acquittés** ;
4. **sortie si code = $40 (barre d'espace) ou si PRA bit 6 = 0 (bouton gauche)**.

**Sortie** :
- PRA bit 1 remis à 0 ;
- DMACON := $7FFF, INTENA := $7FFF ;
- DIWSTRT/DIWSTOP := $2C81/$2CC1, DDFSTRT/DDFSTOP := $0038/$00D0, BPL1MOD = BPL2MOD := 0 ;
- **copie d'une routine de chargement (≈1 Ko) vers l'absolu $7F000** ;
- **COPJMP1 strobe** ($DFF088), **sans écrire COP1LC** : redémarrage du copinit système déjà
  chargé ;
- **DMACON := DMACONR sauvé \| $8000**, **INTENA := INTENAR sauvé \| $8000** ;
- SR restauré, RTE, retour D0 = 0.

**Pas d'appel système** : ni Forbid, ni LoadView, ni lecture de GfxBase. Après la sortie, le
copinit relancé saute (COPJMP2) vers **COP2LC, qui pointe encore sur $50D80**. C'est la première
VBlank, une fois INTEN rétabli, qui remet gb_LOFlist dans COP2LC (cf. `caesar-boot.md` §2.7).

### 1.2 QUARTEX = chargeur du jeu (prise de contrôle totale, pas de retour)

**Prise de contrôle** :
- DMACON, INTENA et ADKCON := $7FFF ;
- CIA-B PRB := $87 ;
- vecteur $20 := suite, puis SR := $2700 ;
- **SP := $7FFFE** ;
- copie d'un décompacteur à **$7E000** ;
- décompactage en **$2000–$5C00, $3FC00–$50800, $64000–$6C000, $7FC00–$80000**. Il
  **écrase les vecteurs utilisateur à partir de $100**. La zone $400–$1000 n'a pas pu être
  observée : l'émulateur y place son ExecBase factice. L'OS est abandonné ensuite [D].

**À $40000** :
- SR := $2700 ; INTENA et DMACON := $7FFF ; PRA bit 1 := 1 ;
- **COP1LC := $40664** (liste maison : DIW $4081/$08C1, DDF $38/$D0, BPLCON0 $4200…),
  lecture de COPJMP1 ($DFF088), qui sert de strobe ;
- attente de VPOS < $40 ;
- DMACON := $7FFF puis $87FF ;
- **saut au jeu ($49D0E)**. Celui-ci réécrit les vecteurs $80/$84/$24 (trap #0, trace) et
  pilote le lecteur lui-même (CIA-B PRB, chargeur de pistes).

**Conséquences** :
- l'écran titre Scooby est affiché par ce code, sans aucune dépendance à la ROM ;
- les seules dépendances sont matérielles, plus le fait que **l'hunk de QUARTEX lui-même ne
  doit pas se trouver dans les zones qu'il écrase** (§5).

### 1.3 Pistes pour « le clic est ignoré, l'intro reste affichée » [D]

1. **NOMAD est peut-être bien sorti.** Une seule chose ramène l'affichage système : la VBlank
   de graphics qui réécrit COP2LC. Si notre VBlank ne rafraîchit COP2LC qu'après un LoadView, le
   copinit continue de sauter dans la liste de NOMAD ($50D80), et l'image de l'intro reste figée
   pendant que le CLI lance QUARTEX. **À vérifier : le serveur VBlank écrit gb_LOFlist dans
   COP2LC à chaque trame.**
2. **QUARTEX se détruit lui-même.** Il copie et décompacte vers $2000–$80000. Si notre LoadSeg
   place son hunk de 58 Ko en CHIP basse (entre $40000 et $80000), le décompacteur écrase sa
   propre source et tout bloque.
   - Sur la vraie 1.3 [S], AllocMem(MEMF_PUBLIC) sert d'abord la RAM $C00000, de priorité
     supérieure à la CHIP : les hunks sans drapeau mémoire tombent hors de CHIP.
   - **À vérifier : l'adresse du segment de QUARTEX (et de NOMAD) donnée par notre LoadSeg.**
3. Le test du bouton de NOMAD n'a lieu qu'**une fois par trame**, après l'attente de VERTB dans
   INTREQR. Si l'image est **figée** (pas de défilement), le programme est bloqué ailleurs.

---

## 2. Monkey Island [cr Defjam] : `defjam` (5 080 o)

**Démarrage** :
- décompactage vers **$50000–$53000** ;
- vecteur **$80** := $501FE, puis `trap #0`.

**Init** :
- CIA-B PRB := $87 (moteurs coupés) ;
- exec **Forbid** (−132) ;
- **sauvegarde du vecteur $6C** (autovecteur de niveau 3), de **INTENAR \| $C000** et de
  **DMACONR \| $8100** ;
- effacement **absolu $64FFC–$72000** ;
- construction de sa copper list dans son code ($51152 ; plans en $65028, $672B0, $6E380 ;
  sprites en $64FFC ; double tampon $65000/$699C0).

**Prise de l'affichage** :
- INTENA := $3FFF puis **$C018** : INTEN + **COPER** + **PORTS**. VERTB, BLIT et le disque
  sont coupés ; **PORTS reste servi par l'OS** (vecteur $68 inchangé) ;
- DMACON := $3FFF puis $83E0 (DMAEN, BPL, COP, BLT, SPR) ;
- BPLCON2 := $0040 ; DIW $2984/$29D0 ; DDF $0038/$00D0 ;
- **COP1LC := $51152** + COPJMP1 strobe ;
- couleurs de sprite ;
- **vecteur $6C := $5056E**. Son handler ne fait quelque chose que si INTREQR bit 4 (COPER)
  vaut 1, puis acquitte COPER. **La copper list ne contient aucun MOVE vers INTREQ** : ce
  handler ne travaille donc jamais [O].

**Boucle principale**, en superviseur et sous Forbid :
1. attente active de **VHPOSR octet haut = 0**, c'est-à-dire la ligne 0 ou 256 ;
2. animation (blitter, avec attente BBUSY sur DMACONR bit 14) ;
3. **PRA bit 6 = 0 ⇒ sortie**, sinon on reboucle.

Le clic n'est donc vu qu'**une fois par trame**, et seulement si la boucle tourne.

**Sortie** :
1. attente de la fin du blitter ;
2. **vecteur $6C restauré** ;
3. **INTENA := valeur sauvée** (avec SET). Les bits COPER et PORTS posés par l'intro **ne sont
   pas effacés** ;
4. **DMACON := $7FFF** ;
5. **COP1LC := GfxBase->copinit**, où GfxBase est obtenu de façon détournée :
   **`ExecBase->IntVects[INTB_BLIT].iv_Data`** (ExecBase +$9C), puis **+$26 (gb_copinit)** ;
6. COPJMP1 strobe ;
7. DMACON := valeur sauvée \| $8100 ;
8. exec **Permit** (−138), RTE, retour D0 = 0.

**Dépendance privée [O ROM]** : sur la vraie ROM, graphics installe son serveur blitter par
**SetIntVector(INTB_BLIT = 6, &GfxBase+$76)** (−162), avec is_Data = GfxBase. C'est ainsi que
`IntVects[6].iv_Data` vaut GfxBase. Dans le même bloc d'init, graphics ajoute son serveur VBlank
par AddIntServer(5, &GfxBase+$4A) (−168).

**Pistes [D]** :
- « L'intro continue de s'animer, clic ignoré » : c'est la boucle principale qui anime (le
  handler $6C ne fait rien). Elle tourne donc, et le seul test est PRA bit 6 une fois par trame.
  À vérifier par sonde :
  - la valeur lue de $BFE001 pendant le clic ;
  - CIA-A **DDRA** : le bit 6 doit être une entrée. Sur la vraie ROM DDRA = $03 [S] ;
  - qu'aucun serveur PORTS de notre ROM (encore actif ici) ne modifie DDRA ou PRA.
- **Après** la sortie : si notre `IntVects[6].iv_Data` n'est pas GfxBase (pas de SetIntVector
  BLIT, ou is_Data différent), COP1LC reçoit un pointeur quelconque, ce qui donne un écran de
  déchets. C'est le même mécanisme que SimCity (§3) : **il faut le reproduire.**

---

## 3. SimCity [cr RZR] : `S/RAZOR.EXE` (22 196 o)

**Démarrage** :
- INTENA := $4000 (INTEN coupé), DMACON := $0200 (DMAEN coupé) ;
- CIA-B PRB := $FD/$87/$FD ; CIA-B CRA bit 1 mis à 1 ;
- **copie d'un décompacteur dans l'absolu $100–$316** (vecteurs utilisateur, cf. §5) ;
- décompactage vers **$59C00–$6E800** (code en $60000, lecteur de musique en $5A000) ;
- DMACON := $8200, INTENA := $C000.

**Init** (encore dans l'OS) :
- exec **OldOpenLibrary("dos.library")** (−408) ;
- si l'ouverture échoue : boucle COLOR00 := VHPOSR jusqu'au **bouton droit** (POTINP bit 10) ;
- dos **Open("SECTOR9.TXT", MODE_OLDFILE)** (−30) dans le répertoire courant (`cd s`) ;
- **Read(fh, tampon à une adresse impaire, $FFFFFF)** (−42) : longueur demandée de 16 Mo ;
  le fichier fait 1 284 o ;
- Close (−36) ;
- CIA-B PRB := $FB puis $F5 (sélection DF0, moteur coupé) ;
- init musique ; plans en $70000 et au-delà.

**Prise de l'affichage** :
- BLTCON1 := 0 ;
- DMACON, INTENA et INTREQ := $7FFF ;
- **DMACON := $83E0**, **INTENA := $C010** (COPER seul) ;
- **vecteur $6C sauvé puis := $600CE**. Le handler, déclenché par COPER depuis sa copper
  list, anime, joue la musique et acquitte COPER ;
- **COP1LC := $632E4** + COPJMP1 strobe.

**Attente** : **boucle serrée sur PRA bit 6** (clic gauche), sans trame ni interruption.

**Sortie** :
1. attente de la fin du blitter ;
2. **vecteur $6C restauré** ;
3. **INTENA := $E03C**, valeur **codée en dur** (INTEN, EXTER, VERTB, COPER, PORTS, SOFTINT) :
   **BLIT, DSKBLK, TBE, RBF, audio restent coupés** ;
4. **DMACON := $83F0 puis $8020** (codés en dur) ;
5. **COP1LC := `(*(*(*(ExecBase))))`+$26**, c'est-à-dire :
   - ExecBase→LibNode.ln_Succ (la bibliothèque qui suit exec dans LibList) ;
   - →ln_Succ (la suivante) ;
   - lu comme une GfxBase : +$26 = gb_copinit.

   **Pas de COPJMP1** : la nouvelle liste est prise à la prochaine trame ;
6. arrêt de la musique, retour D0 = 0 (pas de Forbid/Permit ni de RTE : il est resté en
   utilisateur).

**Dépendance à l'ordre de LibList [O hack, D pour la ROM]** :
- Ce hack suppose que la **3ᵉ bibliothèque** de la chaîne qui part d'ExecBase est
  **graphics.library**.
- Sur la vraie 1.3, les bibliothèques ROM sont ajoutées dans l'ordre des résidents :
  exec, puis **expansion.library (pri 110)**, puis **graphics.library (pri 65)**, puis layers,
  intuition…
- Que LibList soit triée par priorité ou en FIFO, on obtient exec → expansion → graphics.
- **Chez nous, si l'ordre diffère, COP1LC reçoit +$26 d'une autre bibliothèque.** Les cas
  possibles :
  - exec n'est pas en tête ;
  - pas d'expansion.library avant graphics ;
  - une autre bibliothèque est insérée entre les deux ;
  - priorités de nœud différentes.

  Le copper exécute alors de la mémoire quelconque : c'est **exactement l'« écran plein de
  motifs rouges »**.
- **À reproduire** : LibList = exec, expansion, graphics, … dans cet ordre, au moins au moment où
  la startup-sequence tourne.

**Autre conséquence [D]** : INTENA codé en dur laisse **TBE/RBF, DSKBLK et BLIT coupés**. Si
notre ROM attend une de ces interruptions (sortie série, fin de DMA disque, blitter), elle se
bloque après RAZOR. Sur la vraie ROM, trackdisk, serial et graphics les réactivent à la demande.
- À vérifier : SetPatch et LoadWB derrière ne dépendent pas d'un bit d'INTENA posé une fois pour
  toutes au boot.

---

## 4. Tableau des restaurations

| | NOMAD | QUARTEX | defjam | RAZOR |
|---|---|---|---|---|
| Superviseur | trap #0 (vecteur $80) | violation de privilège (vecteur $20) | trap #0 | non |
| Forbid/Permit | non | non | **oui** (−132/−138) | non |
| INTENA pendant l'intro | $0000 (tout coupé) | $0000 | $C018 (COPER+PORTS) | $C010 (COPER) |
| Interruption utilisée | aucune (scrutation INTREQR VERTB) | — | $6C installé mais jamais déclenché | **$6C + COPER de la copper list** |
| Détection du clic | PRA bit 6 (+ espace), 1×/trame | (jeu) | PRA bit 6, 1×/trame (VPOS = 0) | PRA bit 6, boucle serrée |
| INTENA en sortie | sauvé \| $8000 | — | sauvé \| $8000 (COPER/PORTS restent) | **$E03C en dur** |
| DMACON en sortie | sauvé \| $8000 | — | $7FFF puis sauvé \| $8100 | **$83F0 + $8020 en dur** |
| Copper en sortie | COPJMP1 seul (COP1LC inchangé) ; COP2LC reste le sien jusqu'à la VBlank | — | **COP1LC := IntVects[6].iv_Data + $26** + COPJMP1 | **COP1LC := 3ᵉ lib de LibList + $26**, sans strobe |
| Vecteurs restaurés | $80 non restauré | — | $6C oui, $80 non | $6C oui |

---

## 5. Zones absolues écrites (sans allocation) [O, émulation]

| Programme | Zones |
|---|---|
| NOMAD | $50000–$56400 (code décompacté, liste copper $50D80), plans en $37000 et au-delà (liste copper), **$7F000–$7F800** (routine copiée en sortie, laissée en place) |
| QUARTEX | **$100–$3FF (vecteurs utilisateur)**, $2000–$5C00, $3FC00–$50800, $64000–$6C000, $7E000–$7E400, $7FC00–$80000 ; SP = $7FFFE |
| defjam | $50000–$53000, **$64FFC–$72000** (effacé : plans, sprites) |
| RAZOR | **$100–$316** (décompacteur), $59C00–$5E800, $60000–$60800, $62C00–$65000, $68000–$6E800, plans en $70000 et au-delà |

- Les vecteurs utilisateur $100–$3FF ne servent pas à la vraie 1.3. **Si notre ROM y range
  quelque chose** (ExecBase, tables, pile), RAZOR le détruit dès son lancement.
- De même, les zones $50000–$72000 doivent être libres. Ni les bitmaps d'écran, ni les copper
  lists, ni les **segments des intros eux-mêmes** ne doivent s'y trouver.

## 6. Champs privés ou détournés

- **defjam** : `ExecBase+$9C` = IntVects[6].iv_Data, supposé être GfxBase, puis `+$26` =
  gb_copinit. Lit aussi ExecBase+4 pour Forbid/Permit (normal).
- **RAZOR** : `ExecBase->ln_Succ->ln_Succ`, supposé être GfxBase, puis `+$26`.
- **NOMAD, QUARTEX** : aucun champ système. Ils reposent sur les registres COP1LC/COP2LC
  laissés par l'OS : copinit dans COP1LC, et la VBlank qui réécrit COP2LC (NOMAD).

---

## Relecture clean-room

- [x] Aucune suite d'instructions recopiée : appels publics avec LVO, registres et valeurs,
  vecteurs touchés, conditions d'attente et de sortie, champs lus, zones mémoire.
- [x] Les décompacteurs ne sont pas décrits ; aucune donnée graphique ni musicale, aucun texte
  d'intro reproduit (seuls des noms de fichiers).
- [x] **Correction du 2026-10-29** : retirées les 3 adresses de routines graphics de la ROM
  (en-tête) ; comportement inchangé.
