# SetPatch 1.38 (Workbench 1.3.3) — correctifs disk.resource, layers et voisins

Piste **ANALYSE**. Source : `C/SetPatch` extrait d'une **copie** de `assets/wb133.adf`
(`xdftool … read C/SetPatch`, 5964 octets, 35 hunks, chaîne de version « SetPatch 1.38 (24-Sep-90) »).
Relocation des hunks à une base fictive puis désassemblage radare2 (m68k). La ROM Kickstart n'a **pas**
été ouverte. Ce document décrit des **comportements** (vecteurs touchés, offsets lus/écrits, attentes) ;
aucune suite d'instructions n'est recopiée.

Invocation réelle : la `Startup-Sequence` du disque lance **`c:SetPatch >NIL: r`** (argument `r`).

## 0. Déroulé global (ordre d'exécution)

1. Ouvre `dos.library`. Si l'argument 1 commence par `?` → usage + sortie. Si `r`/`R` et exec
   `lib_Version ≤ 35` → tentative du correctif RAD (§6).
2. `FindPort("SetPatch-01")` : si trouvé → « already installed », sortie code 5.
3. `AllocMem(34, MEMF_PUBLIC|MEMF_CLEAR)` → MsgPort nommé `SetPatch-01`, `ln_Type = NT_MSGPORT`,
   `mp_SigTask = NULL`, `mp_Flags = 0` (PA_SIGNAL) → `AddPort`. Marqueur de présence, jamais libéré ;
   personne n'est censé y envoyer de message (un PutMsg dessus ferait `Signal(NULL)`).
4. **Correctif disk.resource** (§1-3) → affiche « disk resource patched » si appliqué.
5. Correctif Alert si exec `lib_Version` = 33 ou 34 (§5.1).
6. graphics.library ≤ 35 : MrgCop / SetFont / SetSoftStyle (§5.2).
7. layers.library ≤ 35 : DeleteLayer (§4).
8. exec ≤ 35 : vecteurs d'exception FPU (écriture directe, §5.3) puis UserState / FindName / AllocEntry (§5.4).
9. « Location zero » (§5.5).
10. DOS `Execute` → RUN résident (§5.6).
11. **`cli_Module` du CLI appelant mis à 0** : le seglist de SetPatch n'est jamais déchargé (tout le code
    des correctifs vit dans ses hunks). Sortie code 0.

Toutes les installations de vecteurs passent par **exec `SetFunction` (-420)**, sauf les vecteurs
d'exception FPU (écriture directe en mémoire basse) et le test de motif DOS.

## 1. Localisation de disk.resource et conditions

- `OpenResource("disk.resource")` (exec -498). Résultat NULL → correctif ignoré, rien n'est affiché.
- Seule condition : `lib_Version` (offset 20 de la base) **≤ 35**. Aucun test de révision, de `dr_Flags`,
  de taille, ni de motif de code. Notre ressource (version 34) **passe** le test.
- Valeur rendue : non nulle (-1) si appliqué → message ; 0 sinon.

## 2. Vecteurs remplacés et méthode

- Section critique **faite à la main** : écriture `INTENA = $4000` (coupe le maître) puis
  `ExecBase->IDNestCnt` (offset $126) **+1** ; à la fin **-1**, et seulement si le compteur redevient
  négatif, `INTENA = $C000`. Ni `Disable()` ni `Enable()` ne sont appelés (donc pas de reschedule différé).
  Suppose `IDNestCnt` à $126 et la convention « -1 = interruptions permises » (notre exec : conforme).
- **`SetFunction(diskres, -18, newGetUnit)`** → ancien vecteur rangé dans une variable privée du hunk.
- **`SetFunction(diskres, -24, newGiveUnit)`** → idem.
- AllocUnit (-6), FreeUnit (-12), GetUnitID (-30) : **non touchés**. Aucune écriture directe dans la jump
  table de la ressource, aucun accès aux champs `dr_*` pendant l'installation.

## 3. Ce que font les remplaçants

Variable privée « propriétaire » (long, dans le hunk SetPatch), **initialisée à -1**.

- **newGetUnit(a1 = DiscResourceUnit, a6 = ressource)** : appelle l'**ancien vecteur complet** (appel
  normal, adresse de retour empilée), registres d'entrée transmis tels quels sauf **a0** (écrasé par
  l'adresse de l'ancienne routine). Au retour, si `d0 ≠ 0` (contrôleur obtenu immédiatement) →
  propriétaire := `ExecBase->ThisTask` (offset $114). Rend le `d0` d'origine.
- **newGiveUnit()** : compare propriétaire et `ThisTask` ; si égal **ou** propriétaire = -1 → **saut**
  (sans retour intermédiaire) à l'ancien GiveUnit complet ; sinon **retour immédiat, GiveUnit avalé**.
  Écrase d0/d1/a0. Le propriétaire n'est **jamais** remis à -1 ni effacé.
- **Aucun champ de la structure DiscResource n'est lu ou écrit** par SetPatch (ni `dr_Current`, ni
  `dr_Flags`, ni `dr_Waiting`, ni les interruptions `dr_DiscBlock/dr_DiscSync/dr_Index`, ni `dr_CurrTask`).
- **Pas de saut dans le milieu de la routine ROM** : l'ancien vecteur est appelé/sauté à son point
  d'entrée. Aucune adresse interne ROM, aucun motif de code attendu.
- Sémantique imposée : « seul le task qui a obtenu le contrôleur par un GetUnit immédiat (`d0≠0`) peut le
  rendre ». Un GetUnit **mis en file** (`d0 = 0`, puis ReplyMsg différé) ne met pas à jour le propriétaire.

## 4. Correctif « Layers patched » (DeleteLayer, -90)

- `OpenLibrary("layers.library", 0)`, condition `lib_Version ≤ 35`.
- `SetFunction(layers, -90, newDeleteLayer)` puis **analyse du code de l'ancien DeleteLayer** :
  - décode l'instruction située **2 octets après le point d'entrée** comme un branchement (déplacement
    8 bits, ou 16 bits si l'octet bas est nul) et va à sa cible ;
  - de là, balaie mot par mot jusqu'au premier mot dont l'octet haut vaut **$61 (BSR)**, décode sa cible
    → **routine interne ROM n°1** ; reprend après ce BSR → routine n°2 ; puis → routine n°3.
  - Les trois adresses (internes à la ROM, non publiques) sont rangées dans le hunk.
- **newDeleteLayer(a1 = Layer)** : **ne rappelle pas** l'ancien vecteur. Appelle routine n°1 avec
  `layer->LayerInfo` (offset 68 de struct Layer) passé sur la pile (convention C) ; si résultat ≠ 0 :
  routine n°2 avec le Layer, puis routine n°3 avec le LayerInfo ; rend 1. Sinon rend 0.
  Aucun autre champ de Layer / Layer_Info / ClipRect n'est touché directement par SetPatch.
- **Dépendance totale au code interne de la ROM** : forme du prologue, présence et ordre de trois BSR.
  Sur une autre implémentation, les « routines » sont des adresses quelconques → tout DeleteLayer
  (fermeture de fenêtre/écran) sauterait dans du code ou des données arbitraires.
- Avec un `SetFunction` qui rend 0 (cas actuel, cf. §7) : le balayage part de l'adresse 2 (mémoire basse,
  lecture seule, inoffensif) et le vecteur n'est pas remplacé.

## 5. Autres correctifs du même programme (pour mémoire)

### 5.1 Alert (-108), exec version 33/34 uniquement
- `SetFunction(exec, -108, newAlert)`. Si l'ancien vecteur n'est **pas** dans `$FC0000-$FFFFFF` →
  re-SetFunction avec l'ancien (annulation) + « skipped (vector in use) ».
- newAlert : coupe INTENA, écrit `'HELP'` en `$0`, le code d'alerte (bit 31 forcé) en `$100`, un long lu
  via a5 en `$104`, puis **saute à ancienAlert + $30 ou + $88** (selon la validité du pointeur ExecBase en
  `$4`) → **adresses internes ROM calculées depuis l'ancien vecteur**. Notre ROM étant en `$FC0000`, avec
  un vrai SetFunction ce correctif **serait installé** et tout `Alert()` sauterait au milieu de notre code.

### 5.2 graphics.library ≤ 35
- MrgCop (-210) : compare `View->Modes` (offset 16) à un champ de GfxBase (offset $9E) sur le bit LACE ;
  si LACE vient d'apparaître, parcourt les ViewPort (`vp_Next`, `vp->Modes` offset 32, bits $2000 et LACE)
  et appelle MakeVPort (-216) ; puis **saute à l'ancien MrgCop** (entrée normale).
- SetFont (-66) : garde NULL (rastport ou font NULL → retour) puis **ancien SetFont**.
- SetSoftStyle (-90) : réimplémentation complète via AskSoftStyle (-84) ; lit `rp->Font` (52),
  lit/écrit `rp->AlgoStyle` (56), lit `tf_Style` (22) ; ne rappelle pas l'ancien.

### 5.3 Vecteurs d'exception FPU (exec ≤ 35) — écriture directe
- Lit le vecteur **5** (`$14`), suit le `bsr.s`/branchement 8 bits du gestionnaire, avance de 6 octets et
  exige le mot `$E2EF` ; sinon accès mot à une adresse impaire (**plantage volontaire**, address error).
- Écrit **16 longs en `$C0-$FC`** (vecteurs 48-63) pointant vers une table de stubs dans le hunk SetPatch ;
  ces stubs rejoignent le gestionnaire commun ROM **6 octets après son début** avec 2×n° de vecteur sur
  la pile. Ne se déclenche jamais sur 68000 (pas de FPU/MMU). Notre exec a déjà la forme attendue.

### 5.4 exec ≤ 35 : UserState (-156), FindName (-276), AllocEntry (-222)
- Réimplémentations autonomes : UserState via Supervisor (-30) + RTE ; FindName qui saute les nœuds à
  `ln_Name` NULL ; AllocEntry qui libère proprement en cas d'échec partiel (bit 31 du résultat).
  Aucune adresse interne ROM.

### 5.5 « Location zero reset to zero »
- Via `Supervisor` (-30) : écriture mot 0 en `$F80000` (zone ROM, ignorée), puis si le long en `$0`
  est non nul → `$0 := 0`. Message si c'était le cas.

### 5.6 DOS Execute (-222) → RUN résident
- Cherche dans **son propre seglist** (depuis `cli_Module` de `pr_CLI`, offset $AC du Process) le hunk dont
  la taille stockée **à -4** du lien vaut $22C et dont le premier long de code vaut $89 (en-tête de
  segment BCPL) = le RUN BCPL embarqué.
- Exige que l'**entrée de jump table** dos -222 commence par le long `$70E56000` (stub BCPL de la ROM) ;
  sinon « already patched ». Si oui : SetFunction vers une glue qui appelle le BCPL (registres a2/a5/a6
  pris à DOSBase+$2A, pile BCPL ~1500 octets **sous** le sp courant) avec le RUN résident.

### 6. RAD (argument `r`)
- Seulement si exec < 35 **et** `MaxLocMem` (ExecBase+$3E) > `$80000` **et** `ColdCapture` (+$2A) nul :
  copie un stub de 44 octets (AllocAbs près de `SysStkLower` (+$3A) ou AllocMem chip), le pose en
  ColdCapture et recalcule `ChkSum` (+$52). Le stub, au reset, cherche un motif dans le code ROM.
  Notre exec pose `MaxLocMem = $80000` → **ignoré**.

## 7. Confrontation avec notre implémentation (lecture `src/`, sans la ROM)

- `SetFunction` (-420) n'est **pas implémenté** : le vecteur pointe sur le stub générique qui rend
  `d0 = 0`. Conséquence : **aucun** correctif par SetFunction n'est réellement installé ; SetPatch range
  0 comme « ancien vecteur » partout, et affiche quand même ses messages. Pour disk.resource, le seul effet
  réel est la section critique manuelle (INTENA + IDNestCnt +1/-1, cohérente avec notre exec) et
  **une ligne de sortie supplémentaire** (vers NIL:).
- Effets directs réels quelle que soit la ressource : port `SetPatch-01`, vecteurs `$C0-$FC`, `$0`
  remis à 0, seglist SetPatch rendu résident (si notre CLI relit `cli_Module` après la commande).
- **Donc, dans l'arbre actuel, le correctif disk.resource ne peut pas, à lui seul, corrompre la pile
  d'un autre process** : il n'écrit rien dans la ressource, et ses remplaçants ne sont jamais branchés.

## 8. Hypothèses pour le crash « execute » (PC dans sa propre pile)

Classées de la plus à la moins probable vu l'analyse ci-dessus :

1. **Cause hors SetPatch, liée à la présence de la ressource elle-même** : la différence avec/sans
   ressource ne vient pas des vecteurs patchés (non installés). À vérifier côté ressource : les vecteurs
   exclusifs DSKBLK/DSKSYNC posés par SetIntVector et le vecteur CIA-B FLG (index) ; le relais saute à
   `IS_CODE` lu dans le DRU désigné par `dr_Current` dès que le bit « actif » est posé. Si un
   `dr_Current` pointe vers un DRU **sur une pile** (cas de l'auto-test de boot, DRU sur la pile
   superviseur/boot) ou vers de la mémoire libérée et que le bit actif reste/devient vrai, une interruption
   disque/index exécutée **dans le contexte du task courant** sauterait vers une valeur lue dans une zone
   de pile → PC dans une pile, attribué au task interrompu (ici le BCPL `execute`). Les frames BCPL
   contiennent justement des adresses de pile. Expérience discriminante : garder la ressource mais
   retirer `SetPatch` de la startup-sequence (ou l'inverse : SetPatch présent, ressource renommée pour que
   OpenResource échoue mais interruptions conservées).
2. **Effet de bord de la sortie supplémentaire** « disk resource patched » vers NIL: (une Write de plus) :
   à n'envisager que si (1) est écarté.
3. **Futur, dès que SetFunction sera implémenté** :
   - disk.resource : les remplaçants sont sains (appel du vecteur entier) mais **avalent tout GiveUnit
     émis par un task différent** de celui qui a obtenu le contrôleur par un GetUnit immédiat (ou après un
     GetUnit mis en file). Le contrôleur resterait « actif » avec `dr_Current` figé → blocage disque, et
     avec un DRU de pile/libéré → scénario (1) garanti. Notre trackdisk doit donc faire GetUnit **et**
     GiveUnit depuis le même task.
   - layers DeleteLayer et Alert : dépendance à du **code interne ROM** (motif BSR / offsets +$30/+$88) →
     sauts arbitraires. Parade côté implémentation : faire échouer proprement les gardes de SetPatch
     (p. ex. Alert : vecteur hors `$FC0000-$FFFFFF` → SetPatch annule lui-même ; DeleteLayer : aucune
     garde autre que la version — prévoir une forme de prologue qui rende des cibles inoffensives, ou une
     version de layers > 35 si acceptable).
   - Les remplaçants vivant dans le seglist de SetPatch, notre CLI doit **relire `cli_Module` après la
     commande** et ne pas décharger si 0 ; sinon tous les vecteurs patchés pointeraient vers de la mémoire
     libérée, réallouée ensuite (p. ex. comme pile d'un nouveau process) → PC dans une pile.
