# graphics.library 34 — construction de l'affichage et serveur VBlank — spec comportementale

> Piste **ANALYSE** (dirty). Sources : ROM `assets/kick34005.A500` (lecture seule ; désassemblage
> temporaire hors dépôt) et sonde boîte noire `tests/gdisp_probe.s` / `tests/gdisp_probe.sh` exécutée
> sur la vraie ROM (FS-UAE A500, 512 Ko chip + 512 Ko slow, PAL puis NTSC). Spécification
> **comportementale** : structures lues et écrites, contenu et ordre des listes copper, valeurs, conditions.
> Aucune suite d'instructions de la ROM n'est reproduite ; les adresses citées sont des adresses **RAM**
> de l'exécution sondée (exemples), jamais des adresses de routines.
>
> Légende : **[O]** observé dans le binaire `kick34005.A500` (radare2, base `$FC0000`) ·
> **[S]** sondé en boîte noire sous FS-UAE avec la vraie ROM (`tests/gdisp_probe.sh`) ·
> **[D]** déduit (raisonnement sur [O]/[S] ou sur la doc matérielle publique, non exécuté).
>
> Complète, sans les répéter : `caesar-boot.md` §2.7 (dépendance copinit → COPJMP2 → COP2LC),
> `cracktros-exit.md` (programmes qui relancent copinit ou réécrivent COP1LC), `monkey-startup.md` §3
> (UCopIns d'un jeu), `sysinfo-44.md` §1.3 (WaitTOF).

---

## 0. Réponse courte

- La 1.3 fabrique l'affichage en **trois étages** : `MakeVPort` remplit pour chaque ViewPort une liste
  **intermédiaire** (`vp_DspIns`, instructions de 6 octets, positions **relatives au haut de la
  ViewPort**) ; `MrgCop` **fusionne** par position de WAIT toutes les listes intermédiaires de la View en
  une ou deux listes **matérielles** (`v_LOFCprList`, `v_SHFCprList`, mots copper en CHIP) ; `LoadView`
  ne fait que publier ces listes dans GfxBase. [O][S]
- Le copper est lancé à chaque trame par le matériel sur **copinit** (COP1LC, jamais modifié après
  l'init) ; copinit se termine par **WAIT ligne 12 puis strobe COPJMP2** ; c'est le **serveur VBlank de
  graphics** qui écrit **COP2LC := gb_LOFlist** (ou gb_SHFlist selon le bit LOF en entrelacé) à chaque
  trame. [O][S] (cf. `caesar-boot.md` §2.7)
- Dans une ViewPort, la **fenêtre verticale n'est pas faite par DIWSTRT/DIWSTOP** : DIWSTRT vaut
  toujours `$05xx` et DIWSTOP `$40xx` (fenêtre ouverte des lignes 5 à 320) ; l'affichage est allumé et
  éteint par deux écritures de **BPLCON0** (nombre de plans, puis 0 plan) placées sur des WAIT au haut
  et au bas de la ViewPort. [O][S]
- Entre deux ViewPorts empilées il faut **au moins une ligne vide** (deux si la ViewPort du bas a plus
  de 4 plans, ou plus de 3 plans avec SPRITES) ; avec des ViewPorts **contiguës**, la ViewPort du bas
  reste **éteinte** (le BPLCON0 « éteint » de celle du haut est émis après son BPLCON0 « allumé »). [S]
- `SetRGB4`/`LoadRGB4` et `ScrollVPort` **modifient les listes matérielles sur place** (sans MrgCop) ;
  `ScrollVPort` inverse les deux trames en entrelacé (bug de la 1.3, §7.3). [O][S]
- `VideoControl` **n'existe pas** en V34 (LVO −708, apparu en V36 ; la table V34 s'arrête à −654). [O]

---

## 1. Structures (offsets V34) [O][S]

### 1.1 View (18 octets)

| Off | Champ | Lu/écrit par |
|---|---|---|
| $00 | ViewPort (première) | MrgCop (parcours), LoadView (recherche de la ViewPort la plus haute) |
| $04 | LOFCprList | MrgCop (alloue/réutilise), LoadView (lit `start`) |
| $08 | SHFCprList | MrgCop (seulement si Modes & LACE), LoadView (lit `start` **sans test de NULL**, §5.1) |
| $0C | DyOffset (w) | MrgCop (ajouté à toutes les lignes de WAIT), WaitBOVP, ScrollVPort |
| $0E | DxOffset (w) | MakeVPort/ScrollVPort (ajouté à la position horizontale) |
| $10 | Modes (w) | seul le bit **LACE ($0004)** est utilisé : BPLCON0, liste SHF, modulo, LoadView |

`InitView` : met les 18 octets à 0 puis **DyOffset := $2C (44), DxOffset := $81 (129)** ; Modes = 0.
Rien d'autre (pas de dépendance PAL/NTSC). [O][S]

### 1.2 ViewPort (40 octets)

| Off | Champ | Notes |
|---|---|---|
| $00 | Next | chaînage dans la View |
| $04 | ColorMap | NULL autorisé (table par défaut, §3) |
| $08 | DspIns | CopList intermédiaire construite par MakeVPort |
| $0C | SprIns | non construite par MakeVPort ; fusionnée si présente |
| $10 | ClrIns | idem |
| $14 | UCopIns | chaîne de UCopList (§6) ; fusionnée |
| $18 | DWidth (w) | en pixels du mode (hires = pixels hires) |
| $1A | DHeight (w) | en lignes du mode (entrelacé = lignes entrelacées) |
| $1C | DxOffset (w) | idem DWidth |
| $1E | DyOffset (w) | idem DHeight |
| $20 | Modes (w) | HIRES $8000, SPRITES $4000, VP_HIDE $2000, HAM $0800, DUALPF $0400, EXTRA_HALFBRITE $0080, PFBA $0040, LACE $0004 |
| $22 | SpritePriorities (b) | |
| $23 | (réservé, b) | |
| $24 | RasInfo | |

`InitVPort` : met les 40 octets à 0 puis **SpritePriorities := $24** (vérifié : rien n'est écrit au-delà
de l'octet 40). [O][S]

### 1.3 RasInfo (12) et BitMap

RasInfo : Next $00 (deuxième terrain de jeu en DUALPF), BitMap $04, RxOffset $08 (w), RyOffset $0A (w).
BitMap : BytesPerRow $00 (w), Rows $02 (w), Flags $04 (b), **Depth $05 (b)**, Planes[8] $08. MakeVPort
lit BytesPerRow, Depth et Planes ; jamais Rows. [O][S]

### 1.4 ColorMap (8 octets)

Flags $00 (b), Type $01 (b), Count $02 (w), ColorTable $04 (l). [O][S]

### 1.5 CopList intermédiaire (34 octets = $22) et CopIns (6 octets)

| Off | Champ | Rôle observé |
|---|---|---|
| $00 | Next | bloc suivant de la même liste (débordement) |
| $04 | _CopList | **réutilisé par MrgCop** comme lien de sa liste de fusion |
| $08 | _ViewPort | posé par MrgCop (ViewPort propriétaire) |
| $0C | CopIns | tableau d'instructions (6 octets chacune) |
| $10 | CopPtr | instruction courante (constructeur, puis curseur de fusion) |
| $14 | CopLStart | adresse, dans la liste matérielle LOF, du premier mot émis pour cette CopList |
| $18 | CopSStart | idem dans la liste SHF (ou 0) |
| $1C | Count (w) | instructions écrites dans ce bloc |
| $1E | MaxCount (w) | capacité du bloc |
| $20 | DyOffset (w) | non utilisé en 1.3 (0) |

CopIns : `OpCode` (w), puis deux mots : pour un **MOVE** (OpCode & 3 = 0) `DestAddr`, `DestData` ; pour
un **WAIT** (OpCode & 3 = 1) `VWaitPos`, `HWaitPos` ; pour **CPRNXTBUF** (OpCode & 3 = 2) un pointeur
long sur la CopList suivante. Bits de trame dans OpCode (sémantique **observée**, §4.4) :
**$8000 = instruction émise dans la liste LOF seulement**, **$4000 = dans la liste SHF seulement**.
DestAddr est conservé tel quel dans la liste intermédiaire (ex. `$F180` pour COLOR00, mot bas de
`$DFF180`) ; seul `DestAddr & $1FE` passe dans la liste matérielle. [O][S]

### 1.6 cprlist (10 octets)

Next $00, start $04 (tableau de mots copper, **MEMF_CHIP|MEMF_PUBLIC**), MaxCount $08 (w, en
**instructions de 4 octets**). [O][S]

### 1.7 UCopList (12 octets)

Next $00, FirstCopList $04, CopList $08 (bloc courant). [O][S]

### 1.8 Champs de GfxBase concernés (relevés PAL, au moment du bootblock) [S]

| Off | Champ | Valeur / rôle |
|---|---|---|
| $22 | ActiView | dernière View passée à LoadView (NULL accepté) |
| $26 | copinit | liste copper de démarrage, 92 octets CHIP (ici `$420`) |
| $32 | LOFlist | adresse mise dans COP2LC par le VBlank (trame longue ou non entrelacé) |
| $36 | SHFlist | idem, trame courte en entrelacé |
| $4A | vbsrv | Interrupt du serveur VERTB, **pri 10**, is_Data = GfxBase |
| $9E | Modes (w) | copie de View.Modes faite par LoadView |
| $A0 | VBlank (b) | mis à 0 à chaque VBlank |
| $A4 | system_bplcon0 (w) | 0, ou `$0102` si genlock détecté (§8.1) ; OR-é dans **tous** les BPLCON0 |
| $C0 | TOF_WaitQ | liste des tâches en WaitTOF |
| $CE | DisplayFlags (w) | **4 = PAL**, **1 = NTSC**, + 2 (GENLOC) si system_bplcon0 a ERSY |
| $D4 | MaxDisplayRow | PAL **$137 (311)**, NTSC **$105 (261)** |
| $D6 | MaxDisplayColumn | **$1D1** (les deux) |
| $D8 | NormalDisplayRows | PAL **256**, NTSC **200** |
| $DA | NormalDisplayColumns | **640** |
| $DC/$DE | NormalDPMX / NormalDPMY | PAL **$4CA / $513**, NTSC **$500 / $44A** |
| $E0 | LastChanceMemory | SignalSemaphore (46 octets) |
| $E4 | LCMptr | tampon CHIP de 2 Ko alloué **juste après copinit** (ici `$480`) |
| $E8 | MicrosPerLine | **$3F9D** (les deux) |
| $EA | MinDisplayColumn | **$30** |

Effet de bord à reproduire : l'init de graphics écrit **ExecBase→VBlankFrequency (+$212) := 50 (PAL) ou
60 (NTSC)** selon la détection (§8.1). [O][S]

---

## 2. copinit [O][S]

Allouée à l'init (92 octets, CHIP|PUBLIC), jamais réallouée. Contenu (offsets en octets) :

| Off | Instruction | Notes |
|---|---|---|
| $00 | MOVE BPL1PTH, 0 | **réécrit par LoadView/SetRGB4/LoadRGB4** : devient `MOVE COLOR00, <couleur 0 de la ViewPort la plus haute>` dès qu'une View avec ColorMap est chargée ; redevient `MOVE BPL1PTH` (donnée inchangée) si cette ViewPort n'a pas de ColorMap |
| $04 | MOVE BPL1PTL, 0 | |
| $08–$47 | 8 × (MOVE SPRxPTH, MOVE SPRxPTL) | au départ, les 8 pointeurs visent le sprite vide en copinit+$58 ; GetSprite/ChangeSprite y installent les sprites (sondé : sprite 0 → `$0C80`, le pointeur, réservé : SpriteReserved = 1) |
| $48 | WAIT `$0C01,$FFFE` | ligne 12 |
| $4C | MOVE COPJMP2 (`$008A,$0000`) | saut vers COP2LC |
| $50 | `$FFFE,$FFFF` | MOVE vers le registre $1FE (sans effet) ; jamais exécuté normalement |
| $54 | `$FFFF,$FFFE` | fin ; **COP2LC initial** de l'init pointe ici |
| $58 | `$FE00,$FF00` | mots de contrôle du sprite vide (VSTART $FE) ; les 2 mots de fin qui suivent sont **hors** des 92 octets |

À l'init : DMACON := $0080 (copper coupé), COP1LC := copinit, puis les SPRxPOS/CTL **matériels** :=
$FE00/$FF00, COP2LC := copinit+$54 ; plus tard DMACON := $81A0 (SET, BPLEN, COPEN, SPREN),
COLOR00 = COLOR01 = $FFF. Les registres d'affichage sont initialisés directement par le CPU (aussi
à chaque `LoadView(NULL)`) : BPLCON0 := system_bplcon0 | $1200, BPLCON1 := 0, BPLCON2 := $24,
BPL1MOD = BPL2MOD := 0, **DIWSTRT := $2C81, DIWSTOP := $F4C1, DDFSTRT := $38, DDFSTOP := $D0**, puis
attente que la position verticale ne soit plus dans `$FFxx`, puis **VPOSW := VPOSR | $8000** (force une
trame longue). [O]

**Anomalie à reproduire telle quelle** : gb_LOFlist initial et `LoadView(NULL)` valent
**copinit + $A0**, adresse **hors** de copinit (92 octets) : sur la machine sondée elle tombe dans le
tampon LCM (`$4C0`, rempli de zéros, que le copper exécute comme des MOVE vers $000 sans effet). [O][S]

---

## 3. Couleurs : ColorMap, GetRGB4, SetRGB4CM, SetRGB4, LoadRGB4

Table par défaut (32 entrées) [O][S] :
`000 F00 0F0 FF0 00F F0F 0FF FFF 620 E50 9F1 EB0 55F 92F 0F8 CCC 000 111 222 333 444 555 666 777 888
999 AAA BBB CCC DDD EEE FFF`.

- **GetColorMap(n)** : AllocMem(8, PUBLIC) **sans CLEAR** (Flags non initialisé, Type := 0), Count := n,
  ColorTable := AllocMem(2n, PUBLIC) recopiée depuis la table par défaut sur **n entrées sans borne** :
  pour n > 32 les entrées 32+ sont des octets quelconques (sondé : contenu de la ROM qui suit). Échec de
  la 2ᵉ allocation : la 1ʳᵉ est libérée, retour 0. [O][S]
- **FreeColorMap(cm)** : libère la table (2·Count) puis la structure ; pas de test de NULL. [O]
- **GetRGB4(cm, i)** : i ≥ Count ⇒ **−1** ; sinon ColorTable[i] (mot, étendu). [O][S]
- **SetRGB4CM(cm, i, r, g, b)** : cm NULL ⇒ retourne 0 sans rien faire ; i ≥ Count ⇒ −1 ; sinon
  `(r&15)<<8 | (g&15)<<4 | (b&15)` et retourne 0 (sondé : (15,$10,$21) → `$0F01`). [O][S]
- **SetRGB4(vp, i, r, g, b)** : i > 31 ⇒ −1 (comparaison signée). vp NULL ⇒ écriture directe du registre
  COLORi. Sinon : SetRGB4CM sur vp→ColorMap (−1 propagé) ; puis, si vp→DspIns existe et vp n'est pas
  VP_HIDE, **remplacement sur place** de la donnée du premier `MOVE COLORi` trouvé dans la liste
  matérielle LOF à partir de DspIns→CopLStart, et de même dans la liste SHF (CopSStart) ; puis mise à
  jour du MOVE correspondant dans la liste intermédiaire ; puis mise à jour de copinit (§2). Retour 0.
  **Aucun MrgCop/LoadView n'est nécessaire** : la nouvelle couleur est visible à la trame suivante. [O][S]
- **LoadRGB4(vp, table, n)** : n plafonné à 32. vp NULL ⇒ écriture directe COLOR0..n−1. Sinon : si
  ColorMap, n := min(n, Count) et recopie dans ColorTable ; puis, si DspIns et non caché, patch en place
  des n couleurs consécutives à partir du premier `MOVE COLOR00` des listes LOF et SHF (une couleur dont le
  MOVE n'est pas à la position attendue est sautée), mise à jour de l'intermédiaire, puis copinit. [O][S]

---

## 4. MakeVPort(view, vp) — liste intermédiaire

### 4.1 Allocation [O]

DspIns est **réutilisée** si elle existe (Count remis à 0, blocs chaînés conservés et réutilisés) ;
sinon CopList (34 octets, CLEAR) + 40 instructions. Débordement : quand Count atteint MaxCount, un bloc
suivant (34 octets + 16 instructions, MEMF_PUBLIC) est alloué ou réutilisé, la dernière instruction y
est déplacée et remplacée par un **CPRNXTBUF** vers ce bloc (sondé en HAM/EHB : CPRNXTBUF au rang 40).
Échec d'allocation de DspIns ⇒ **Alert $82010030**. [O][S]

### 4.2 Paramètres dérivés [O][S]

- `prof` = Depth du BitMap (+ Depth du 2ᵉ RasInfo en DUALPF) ; hors DUALPF/HAM/EHB, plafonné à 5. Aucun
  autre contrôle (hires 5 plans accepté → BPLCON0 `$D200`, illégal sur OCS).
- `ncoul` = 16 si HAM ou DUALPF, sinon `1 << min(prof,5)` (EHB 6 plans → 32).
- Ligne d'amorce `L0` = **−1**, ou **−2** si (prof > 4 et pas DUALPF) ou (prof > 3 et SPRITES) ;
  **doublée si vp LACE**.
- Table de couleurs : ColorMap→ColorTable, ou la table par défaut si ColorMap NULL. **ncoul couleurs sont
  émises quel que soit Count** (une ColorMap trop courte est lue au-delà de sa fin). [O]

### 4.3 Contenu, dans l'ordre (cas un seul terrain de jeu) [S]

1. `WAIT(L0, 0)`
2. `MOVE COLOR00..COLOR(ncoul−1)` ; si SPRITES et prof < 5 : en plus `COLOR16..COLOR(Count−1)` pris aux
   entrées 16+ (Count plafonné à 32, 32 si pas de ColorMap).
3. `MOVE DIWSTRT := $0500 | (x & $FF)`
4. `MOVE BPLCON0 := system_bplcon0 | $0200 | (View.Modes & LACE)` (0 plan : écran éteint)
5. `MOVE BPLCON2 := (vp.Modes & PFBA) | SpritePriorities`
6. `MOVE DIWSTOP := $4000 | ((x + w) & $FF)`
7. `MOVE DDFSTRT`, `MOVE DDFSTOP`, `MOVE BPLCON1 := s | s<<4`
8. `MOVE BPL1MOD` ; `MOVE BPL2MOD` (si prof > 1) — même valeur
9. pour chaque plan i : `MOVE BPLiPTH`, `MOVE BPLiPTL` (adresse = Planes[i] + décalage) ; si vp LACE :
   paire marquée **$8000** (LOF) avec l'adresse, et, si View **et** vp LACE, paire marquée **$4000** (SHF)
   avec adresse + BytesPerRow
10. `WAIT(0, 0)` — haut de la ViewPort
11. `MOVE BPLCON0 := prof<<12 | system_bplcon0 | $0200 | (View.Modes & LACE) | (vp.Modes & (HIRES|HAM|DUALPF))`
    (EHB n'ajoute aucun bit ; SPRITES non plus)
12. `WAIT(DHeight, 0)` — bas de la ViewPort
13. `MOVE BPLCON0 := ` valeur du point 4
14. `WAIT(10000, 255)` — fin

DUALPF : points 3–9 calculés pour chaque terrain (§4.5) ; plans alternés PF1 (BPL1, 3, 5) / PF2 (BPL2,
4, 6) ; BPL1MOD/BPL2MOD calculés séparément. Tant que le DIWSTRT vertical est `$05`, la fenêtre
verticale matérielle couvre les lignes 5 à $140 : seule BPLCON0 découpe la ViewPort.

### 4.4 Horizontale : DIW, DDF, BPLCON1, modulo, décalage de plan [O][S]

Notations : `w` = DWidth, `x` = vp.DxOffset, `rx` = RxOffset ; en HIRES, `w`, `x` et `rx` sont d'abord
divisés par 2 (décalage arithmétique), masque `m` = 7, base de fetch `B` = $3C ; en LORES `m` = 15,
`B` = $38.

1. `s` = (−rx) & m ; drapeau « défilement » `S` = (s ≠ 0), ou, en DUALPF, s de l'autre terrain ≠ 0.
2. `xmax` = MaxDisplayColumn ($1D1), **−10 si S**. `x` += View.DxOffset. Si `x + w > xmax` alors
   `w := xmax − x` (rognage droit).
3. `x' = x − $81` ; décalage de plan = `RyOffset × BytesPerRow + 2 × (rx >> (HIRES ? 3 : 4))` (rx déjà
   divisé en HIRES).
4. `s` := (x' & m) + s ; si s > m alors s := s & m et S := faux.
5. Si S : `B` −= 8 et, en HIRES seulement, décalage −= 2.
6. `DDFSTRT` = B + ((x' >> 1) & (HIRES ? ~3 : ~7)).
7. Rognage gauche : si `DDFSTRT < MinDisplayColumn/2` ($18), on avance de `d` = 2 × écart (×2 encore en
   HIRES) : rx += d, x = vp.DxOffset + d, w = DWidth − d, et on recommence au 1.
8. `DDFSTOP` = (((w + 15) >> 1) & ~7) + DDFSTRT − (rx & m ? 0 : 8), plafonné à **$D8** ; en HIRES −4 puis
   plafonné à **$D4**.
9. Octets lus par ligne : HIRES `((STOP − STRT)/2 + 6) & ~3`, LORES `(STOP − STRT)/4 + 2`.
   **Modulo** = BytesPerRow − octets lus, **+ BytesPerRow si View et vp LACE**.
10. DIW (point 3/6 du §4.3) avec `x` restauré (= x' + $81) et `w` rogné.

DUALPF : si les deux `s` diffèrent, DIWSTOP −1 ; DDFSTRT = min des deux, DDFSTOP = max ; le terrain dont
le DDFSTRT était plus grand voit son décalage de plan diminué de 4 (HIRES) ou 2 (LORES).

Vecteurs sondés (View par défaut, Dy 0) :

| Config | DIWSTRT/STOP | DDFSTRT/STOP | BPLCON1 | MOD | BPL1PT | BPLCON0 haut |
|---|---|---|---|---|---|---|
| LORES 320×200, 2 pl, bpr 40 | $0581/$40C1 | $38/$D0 | $00 | 0 | P0 | $2200 |
| HIRES 640×200, 4 pl, bpr 80 | $0581/$40C1 | $3C/$D0 | $00 | 0 | P0 | $C200 |
| LORES rx=5 ry=3, bpr 80 | $0581/$40C1 | $30/$D0 | $BB | $26 | P0+$F0 | $2200 |
| HIRES rx=3, bpr 80 | $0581/$40C1 | $34/$D0 | $77 | −4 | P0−2 | $A200 |
| LORES Dx=−10 | $0577/$40B7 | $30/$C8 | $66 | 0 | P0 | $1200 |
| LORES DW=400, bpr 50 | $0581/$40D1 | $38/$D8 | $00 | 8 | P0 | $1200 |
| LORES Dx=20 DW=200 | $0595/$405D | $40/$A0 | $44 | $0E | P0 | $1200 |
| View Dx=$85 | $0585/$40C5 | $38/$D0 | $44 | 0 | P0 | $1200 |
| DUALPF 2+2, PF2 rx=3 | $0581/$40C0 | $30/$D0 | $D0 | −2/−2 | PF1 P0−2, PF2 P0 | $4600 |
| HAM 6 pl (16 coul., WAIT −2) | $0581/$40C1 | $38/$D0 | 0 | 0 | P0 | $6A00 |
| EHB 6 pl (32 coul., WAIT −2) | idem | idem | 0 | 0 | P0 | $6200 |
| DUALPF 3+3 | idem | idem | 0 | 0 | PF1/PF2 alternés | $6600 |
| LACE vue+vp, 320×400 | idem | $38/$D0 | 0 | $28 | LOF P0, SHF P0+$28 | $1204 |

### 4.5 Remarques de comportement [O][S]

- MakeVPort **ne regarde pas VP_HIDE** (la liste est construite ; MrgCop l'ignore).
- vp LACE dans une View non LACE : WAIT −2 (relatif, divisé par 2 à la fusion), paires BPLxPT marquées
  $8000 seulement, modulo sans le BytesPerRow supplémentaire, BPLCON0 sans LACE ; il n'existe pas de
  liste SHF, donc la paire $8000 est émise dans LOF et l'image saute une ligne sur deux. [S]
- vp non LACE dans une View LACE : BPLCON0 avec LACE, WAIT −1, mêmes instructions dans LOF et SHF. [S]
- SprIns/ClrIns ne sont jamais construites par MakeVPort ; seules UCopIns et DspIns proviennent de
  l'appelant/MakeVPort dans la 1.3 sondée. [O]

---

## 5. MrgCop(view) — fusion en listes matérielles

### 5.1 Collecte et allocation [O][S]

Pour chaque ViewPort de la View **non VP_HIDE**, dans l'ordre de la chaîne, sont ajoutées à la liste de
fusion : DspIns, SprIns, ClrIns puis chaque UCopList de UCopIns (son FirstCopList). Une CopList NULL ou
de Count 0 est ignorée. Chaque ajout se fait **en tête** (la dernière ajoutée est examinée en premier) ;
pour chaque bloc, CopLStart/CopSStart := 0, _ViewPort := vp, CopPtr := CopIns. Aucune CopList ⇒ MrgCop
retourne **sans toucher** aux listes existantes.

Taille = somme des Count + 3. `LOFCprList` est créée (10 octets PUBLIC + taille×4 octets CHIP|PUBLIC)
ou réutilisée ; si la taille dépasse MaxCount, l'ancien tableau est libéré et réalloué. `SHFCprList`
de même **seulement si View.Modes & LACE** ; sinon elle n'est **ni créée ni libérée**. [O][S]

### 5.2 Algorithme de fusion [O][S]

Répéter jusqu'à ce que la dernière position horizontale émise soit ≥ 255 :
1. Pour chaque CopList de la fusion : émettre les **MOVE consécutifs** à partir de CopPtr (dans LOF
   sauf bit $4000, dans SHF sauf bit $8000 ; mot 1 = DestAddr & $1FE, mot 2 = donnée), suivre les
   CPRNXTBUF, et laisser CopPtr sur le WAIT suivant.
2. Choisir la CopList dont le WAIT courant a la plus petite clé
   `((vp.DyOffset + VWaitPos) [÷2 si vp LACE]) × 1024 + HWaitPos` ; en cas d'égalité, **la première
   examinée** (donc la dernière ajoutée : UCopIns avant DspIns, ViewPort du bas avant celle du haut).
3. Si sa CopLStart est 0, CopLStart := position courante dans LOF, CopSStart := position dans SHF.
4. Émettre son WAIT puis avancer son CopPtr :
   - ligne `v` = View.DyOffset + (vp.DyOffset + VWaitPos) [÷2 si vp LACE] ; si v ≥ MaxDisplayRow,
     v := MaxDisplayRow − 1 ;
   - si v > 255 : la première fois, émettre `WAIT(255, hx)` puis `WAIT(v − 256, h)` (et toutes les
     suivantes en `v − 256` directement) ; `hx` vaut **$DE**, sauf si le dernier BPLCON0 émis a les 4 bits
     hauts = `$C` (HIRES 4 plans) **et** que le dernier DDFSTOP émis vaut **$D4** : alors `hx` = la valeur du
     dernier DDFSTRT (le copper n'a plus de cycle en $DE dans ce mode) ;
   - mot 1 = `(v << 8) | (h & $FE) | 1`, mot 2 = `$FFFE` (comparaison sur toutes les positions) ;
   - un WAIT **identique** au précédent émis (même v, même h) n'est pas répété ;
   - le WAIT de fin (10000, 255) devient `v = 255, h = $FE` → **`$FFFF,$FFFE`** qui termine la liste.
5. En entrelacé, chaque WAIT va dans les deux listes.

Fin en entrelacé : juste avant `$FFFF,$FFFE`, chaque liste reçoit `MOVE COP2LCH`, `MOVE COP2LCL` vers
**l'autre** liste (LOF → adresse de SHF, SHF → adresse de LOF). [S]

### 5.3 Exemples sondés (PAL, View par défaut) [S]

LORES 320×200, 2 plans, plans fictifs `$20000/$21000`, ColorMap de 4 :
```
2B01 FFFE  0180 0000  0182 0F00  0184 00F0  0186 0FF0  008E 0581  0100 0200  0104 0024
0090 40C1  0092 0038  0094 00D0  0102 0000  0108 0000  010A 0000  00E0 0002  00E2 0000
00E4 0002  00E6 1000  2C01 FFFE  0100 2200  F401 FFFE  0100 0200  FFFF FFFE
```
(MaxCount 26 = 23 instructions + 3.)

Entrelacé (View et vp LACE, 320×400, 1 plan) — LOF puis SHF :
```
LOF : 2B01 FFFE … 0108 0028  00E0 0002  00E2 0000  2C01 FFFE  0100 1204  F401 FFFE  0100 0204  0084 0000  0086 <SHF>  FFFF FFFE
SHF : 2B01 FFFE … 0108 0028  00E0 0002  00E2 0028  2C01 FFFE  0100 1204  F401 FFFE  0100 0204  0084 0000  0086 <LOF>  FFFF FFFE
```

256 lignes (LORES ou HIRES 4 plans, DDFSTOP $D0) : `… 2C01 FFFE 0100 x200 FFDF FFFE 2C01 FFFE 0100 0200
FFFF FFFE` (franchissement de la ligne 255 en $DE, puis ligne $12C notée $2C).

UCopList (`CWAIT(10,0) CMOVE(COLOR00,$F00) CWAIT(20,$40) CMOVE(COLOR00,$0F0) CEND`) sur une vp Dy 0 :
`… 2C01 FFFE 0100 1200 3601 FFFE 0180 0F00 4041 FFFE 0180 00F0 F401 FFFE 0100 0200 FFFF FFFE` — les
positions de la UCopList sont **relatives au haut de la ViewPort** (et à View.DyOffset).

### 5.4 ViewPorts empilées [S]

| Cas | Liste produite autour de la jonction | Résultat |
|---|---|---|
| vp0 Dy 0 DH 100 ; vp1 HIRES Dy **102** | `9001 0100 0200` · `9101` couleurs/DIW/DDF/PT de vp1 · `9201 0100 9200` · `F601 0100 0200` | une ligne vide ($90) et une ligne de préparation ($91) |
| vp0 Dy 0 DH 100 ; vp1 Dy **100** (contiguë) | `8F01` réglages de vp1 (pendant la dernière ligne de vp0) · `9001 0100 1200 0100 0200` | **vp1 reste éteinte** jusqu'à sa fin ; la dernière ligne de vp0 prend les couleurs/pointeurs de vp1 |
| vp1 avec VP_HIDE | vp1 absente de la liste, CopLStart = 0 | |

Règle déduite : la ViewPort du bas doit commencer au moins à `Dy_haut + DH_haut − L0` (L0 = −1 ou −2,
§4.2), soit **une ligne vide** normalement, **deux** pour une ViewPort à WAIT −2. [D]

---

## 6. UCopList : UCopperListInit, CMove, CWait, CBump, FreeCopList [O][S]

- **UCopperListInit(ucl, n)** : si ucl→FirstCopList existe, elle est réutilisée (Count := 0, CopPtr :=
  CopIns) ; sinon CopList (34 o, CLEAR) + n instructions. FirstCopList = CopList := ce bloc ; retourne le
  bloc ou 0.
- **CMove(ucl, reg, val)** / **CWait(ucl, v, h)** : si ucl→CopList est NULL, `UCopperListInit(ucl, 16)`
  implicite ; écrivent l'instruction à CopPtr (MOVE : OpCode 0, DestAddr = mot bas de `reg`, donnée ;
  WAIT : OpCode 1, v, h) **sans avancer**.
- **CBump(ucl)** : avance CopPtr, Count+1, débordement par CPRNXTBUF comme MakeVPort (bloc de 16).
  Le Count n'augmente qu'avec CBump : un CMove non suivi de CBump n'existe pas.
- **CEND** (WAIT 10000, 255 + CBump) : fusionne avec la fin de liste (aucune instruction de plus).
- La UCopList n'est prise en compte qu'au **MrgCop** suivant (après MakeVPort ou non : MrgCop lit
  UCopIns directement).
- **FreeVPortCopLists(vp)** : vp NULL ⇒ rien ; libère DspIns, ClrIns, SprIns (FreeCopList : chaque bloc
  → MaxCount×6 puis 34 octets), puis **chaque UCopList de UCopIns, structure de 12 octets comprise**,
  puis met les quatre pointeurs à NULL (sondé). Un programme ne doit donc pas libérer lui-même ses
  UCopList après FreeVPortCopLists.
- **FreeCopList(cl)** : parcourt Next. **FreeCprList(cpr)** : parcourt Next, libère `start` (MaxCount×4)
  puis 10 octets ; ne remet rien à zéro dans la View.

---

## 7. LoadView, ScrollVPort, WaitTOF, WaitBOVP, VBeamPos

### 7.1 LoadView(view) [O][S]

1. Si GfxBase.Modes a LACE et que la nouvelle View ne l'a pas : attente active d'une **trame courte**
   (bit LOF de VPOSR à 0) puis d'une ligne ≥ 10.
2. INTENA := $0020 (VERTB coupé).
3. ActiView := view.
4. view non NULL : GfxBase.Modes := View.Modes ; LOFlist := LOFCprList→start ; **SHFlist :=
   SHFCprList→start sans test de NULL** — pour une View non entrelacée, c'est le long en adresse 4
   (**ExecBase**) qui est copié (sondé : SHFlist = `$C00276` = ExecBase) ; puis mise à jour du premier
   mot de copinit (§2 : couleur 0 de la ViewPort visible la plus haute, au sens du plus petit
   DyOffset [÷2 si LACE]). Une View sans LOFCprList (MrgCop jamais appelé) ferait de même lire
   l'adresse 4.
5. view NULL : LOFlist := copinit + $A0 (§2), Modes := 0, réinitialisation CPU des registres
   d'affichage (§2) — SHFlist n'est pas touché.
6. INTENA := $8020.

LoadView **n'écrit ni COP1LC ni COP2LC** : la nouvelle View apparaît au VBlank suivant. [O]

### 7.2 Serveur VBlank de graphics (VERTB, pri 10) [O][S]

À chaque interruption VERTB :
1. GfxBase.VBlank := 0.
2. COP2LC := LOFlist, ou, si GfxBase.Modes a LACE : LOFlist si le bit LOF de VPOSR est à 1, SHFlist
   sinon. (En entrelacé les listes s'échangent aussi elles-mêmes via leur MOVE COP2LC final, §5.2.)
3. **TOD de CIA-B** (compteur de HSYNC) : écriture TOD (CRB bit 7 := 0), TODHI := 0, TODMID := 0, TODLO
   := position verticale courante (8 bits bas), puis CRB bit 7 := 1 — le TOD de CIA-B suit donc le numéro
   de ligne ; il sert à la synchronisation faisceau des blits (QBSBlit, hors périmètre).
4. Signal(**SIGF_SINGLE**, $10) à chaque tâche de TOF_WaitQ (le nœud porte la tâche dans ln_Name).
5. Retour avec Z = 1 (la chaîne continue).

Le serveur **ne touche ni copinit, ni les sprites, ni COP1LC**. Rien d'autre (pas de compteur de
trames dans GfxBase). [O]

### 7.3 ScrollVPort(vp) [O][S]

- VP_HIDE ⇒ rien. Utilise **GfxBase.ActiView** (pas de paramètre View) : la ViewPort doit appartenir à
  la View chargée, sinon les positions et le DxOffset sont ceux de la View active.
- Recalcule DDFSTRT, DDFSTOP, BPLCON1, modulos et décalage de plan comme MakeVPort (§4.4) — **pas
  DIWSTRT/DIWSTOP ni les couleurs**.
- Attend que le faisceau ait dépassé la **1ʳᵉ ligne** de la ViewPort (même attente que WaitBOVP avec
  hauteur 1), puis remplace sur place, à partir de CopLStart/CopSStart : DDFSTRT, BPL1MOD, BPL2MOD (si
  prof > 1), DDFSTOP, BPLCON1, puis les paires BPLxPT ; enfin met à jour la liste intermédiaire (même
  marquage $8000/$4000 que MakeVPort).
- **Bug reproduit par la sonde** : en entrelacé, le patch matériel met l'adresse de base dans la liste
  **SHF** et base + BytesPerRow dans la liste **LOF** — l'inverse de MakeVPort/MrgCop. Sondé (vp LACE
  2 plans, bpr 40, rx 16, ry 3) : LOF `00E2 00A2`, SHF `00E2 007A` (base = $7A). La liste intermédiaire,
  elle, garde l'ordre de MakeVPort : un MrgCop ultérieur rétablit les trames. [S]
- DUALPF : DDFSTRT n'est patché que dans la liste LOF. [O]
- Non entrelacé sondé (rx 21, ry 5, bpr 80) : DDFSTRT $30, BPLCON1 $BB, modulos $26, BPL1PT P0+$192. [S]

### 7.4 WaitTOF, WaitBOVP, VBeamPos [O][S]

- **WaitTOF** : nœud sur la pile (ln_Name := FindTask(NULL)) ; Disable ; SetSignal(0, SIGF_SINGLE) ;
  AddTail(TOF_WaitQ) ; Wait(SIGF_SINGLE) ; Remove ; Enable. Retour juste après le VBlank (sondé : ligne
  **$0C** au retour).
- **WaitBOVP(vp)** : attente **active** (pas de signal) que VBeamPos() ≥ View.DyOffset (ActiView, sans
  test de NULL) + vp.DyOffset + DHeight, cible plafonnée à MaxDisplayRow − 1. Le test « vp LACE ⇒
  DHeight/2 » de la ROM lit un **mauvais octet** (octet haut de ClrIns) et n'est jamais vrai en pratique :
  en entrelacé l'attente vise DHeight lignes non divisées. Sondé : vp Dy 0 DH 100 → retour ligne $90 ;
  vp Dy 110 DH 80 → ligne $EA.
- **VBeamPos()** : `(VPOSR:VHPOSR lu en long >> 8) & $1FF` (V8 inclus). [O]

---

## 8. PAL/NTSC, genlock et vrai A500

### 8.1 Détections faites à l'init [O]

- **Genlock** : BPLCON0 := $0102 (ERSY) ; si le compteur vertical bouge sur un court intervalle, un sync
  externe est présent ⇒ system_bplcon0 := $0102, sinon BPLCON0 := 0 et system_bplcon0 := 0.
- **PAL/NTSC** : par observation du faisceau : si VBeamPos dépasse **270** ($10E) ⇒ PAL (DisplayFlags 4),
  sinon (après être passé au-dessus de 100 puis redescendu sous 50 sans dépasser 270) ⇒ NTSC (1). On ne lit
  **pas** l'identifiant d'Agnus. ExecBase.VBlankFrequency := 50/60 en conséquence.
- Valeurs dépendantes : §1.8. Rien d'autre ne dépend du standard : InitView, DIW/DDF, positions de
  WAIT sont identiques ; seule la ligne de fin de trame (MaxDisplayRow) et donc le plafonnement des WAIT
  et de WaitBOVP changent.

### 8.2 NTSC sondé [S]

Même sonde avec `ntsc_mode = 1` : DisplayFlags = **1**, MaxDisplayRow = **$105**, NormalDisplayRows =
**200**, NormalDPMX/Y = **$500/$44A**, VBlankFrequency = **60** ; MaxDisplayColumn, MinDisplayColumn,
NormalDisplayColumns, MicrosPerLine, copinit, InitView (DyOffset **$2C** aussi en NTSC) et **toutes** les
listes copper sont identiques au PAL, **sauf** le plafonnement : une ViewPort de 256 lignes à Dy 0 (bas
théorique $12C) voit son WAIT de bas plafonné à MaxDisplayRow − 1 = $104 → `… FFDF FFFE 0401 FFFE 0100
0200 FFFF FFFE` (PAL : `2C01`). Aucune adaptation automatique de la hauteur : c'est à l'appelant
(intuition) d'utiliser NormalDisplayRows.

### 8.3 Ce qu'un vrai A500 rendra différemment d'un émulateur tolérant [D]

- **Agnus 8370/8371 (OCS)** : standard figé par la puce (8371 PAL, 8370 NTSC) ; détection par le faisceau
  donc fiable. **8372A (ECS, A500 rév. 6+)** : la 1.3 n'écrit ni BEAMCON0 ni DIWHIGH ; les écritures de
  DIWSTRT/DIWSTOP remettent le comportement OCS, donc mêmes résultats.
- **Fenêtre verticale OCS** : DIWSTOP V `$40` est interprété comme `$140` (V8 implicite = ¬V7) et DIWSTRT
  V `$05` comme ligne 5 — d'où la fenêtre « toujours ouverte » ; un émulateur qui ignore le V8 implicite de
  DIWSTOP fermerait la fenêtre à la ligne $40.
- **Bitplane DMA coupé par BPLCON0** : avec 0 plan entre deux ViewPorts, la ligne affiche COLOR00 ; le
  WAIT d'amorce à −1/−2 laisse le temps au copper d'écrire couleurs et pointeurs pendant la ligne
  précédente — en 6 plans LORES le copper est affamé pendant le fetch, d'où −2.
- **HIRES 5 plans** (accepté par MakeVPort) : BPU = 5 en HIRES est illégal sur OCS (affichage incohérent).
- **DDFSTRT minimum $18** (MinDisplayColumn/2) et **DDFSTOP maximum $D8** (LORES) / $D4 (HIRES) :
  limites de fetch OCS ; au-delà le matériel réel ne lit plus de données (un émulateur peut continuer).
- **Ligne 255** : le compteur vertical du copper n'a que 8 bits ; le WAIT `$FFDF` (h = $DE) est
  indispensable pour toute ViewPort dépassant la ligne 255 (PAL), et en HIRES 4 plans à fetch maximal la
  position $DE n'est jamais atteinte par le copper (cycles volés) d'où le repli sur DDFSTRT.
- **Adresses hors CHIP** : gb_SHFlist = ExecBase (slow RAM `$C0xxxx` sur 512+512) n'est jamais lu par le
  copper en non entrelacé ; sur un A500 réel, un COP2LC ≥ $80000 serait replié dans la chip (bits
  d'adresse limités) — à ne pas « corriger » en lisant ailleurs.
- **Entrelacé** : le bit LOF de VPOSR alterne à chaque trame sur le vrai matériel quand BPLCON0.LACE = 1 ;
  l'init force une trame longue (VPOSW bit 15). Les deux mécanismes (VBlank qui choisit d'après LOF, et
  MOVE COP2LC croisés en fin de liste) donnent le même résultat tant qu'ils sont cohérents.

---

## 9. Points non tranchés

- **SprIns/ClrIns** : jamais construites dans les chemins sondés ; leur production (sprites simples,
  GELs) relève de la spec « sprites et GELs ».
- **Ordre exact de priorité** entre CopLists à position égale quand plusieurs UCopList sont chaînées dans
  une même ViewPort : déduit de l'ajout en tête (la dernière UCopList de la chaîne d'abord), non sondé.
- **Flags de ColorMap** non initialisé par GetColorMap : sa valeur dépend du contenu antérieur de la
  mémoire (0 dans la sonde) ; aucun lecteur connu en V34.
- **LoadView(NULL)** : la liste exécutée en copinit+$A0 dépend de l'ordre des allocations à l'init (ici
  le tampon LCM) ; sur une machine où ce tampon n'est pas nul, le copper exécuterait des données
  quelconques. Non sondé hors de la configuration 512+512.
- **Genlock** et **détection NTSC sur Agnus PAL forcé** (cavalier/JP) : non sondés ; la logique est
  décrite d'après la ROM.
- **Délais réels** de WaitBOVP/ScrollVPort en entrelacé (cible non divisée) : comportement déduit de la
  ROM, seule la variante non entrelacée a été mesurée.
- Comportement de `MrgCop` quand une View change de LACE à non-LACE : l'ancienne SHFCprList est
  conservée (non libérée) — fuite ou réutilisation ultérieure, non sondé.
