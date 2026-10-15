# Architecture

## Modèle de ROM (Kickstart 1.3, 256K)

- Image de **262 144 octets**, chargée à **`$FC0000`** (mappée aussi à `$0` au reset via l'overlay OVL).
- En-tête de reset aux 8 premiers octets : longword `$0` = SSP initial (`0x11114EF9`, mot ROM-ID
  `0x1111` + opcode `0x4EF9`), longword `$4` = PC initial = adresse de coldstart (`$FC00D2` sur une
  ROM authentique ; instruction `RESET` `$4E70` à `$FC00D0`).
- Footer (format conteneur, cf. amitools) : checksum longword à `taille-0x18`, champ taille à
  `taille-0x14`, 8 mots `0x0018..0x001F` à `taille-0x10`. Checksum valide = somme des longwords
  (retenue repliée) égale à `0xFFFFFFFF`. **Non vérifié par l'OS avant la V37**, mais exigé par les outils.

## Modules résidents (ROMTags)

L'OS se construit par un scan de modules résidents (struct `Resident`, matchword `0x4AFC`) dans
l'ordre de **priorité décroissante**. Les 24 modules de la 34.5 et le détail d'ABI sont dans
`docs/analysis/` (piste analyse). Résumé de l'ordre d'init :

`exec`(120) → `expansion`(110) → `potgo`/`keymap`(100) → `cia`(80) → `disk`/`misc`/`ramlib`(70) →
`graphics`(65) → `keyboard`/`gameport`(60) → `timer`(50) → `audio`/`input`(40) → `layers`(31) →
`console`/`trackdisk`(20) → `intuition`(10) → `alert.hook`(5) → `mathffp`/`workbench.task`/`dos`(0) →
`romboot`(-40) → `strap`(-60).

## Structure `src/` (piste clean)

| Dossier | Contenu prévu |
|---------|---------------|
| `src/rom/` | hello-ROM M0 (`start.s`) + `mkrom.py` (padding + footer + checksum) |
| `src/exec/` | exec.library, découpée en modules reliés par vlink : `exec.i` (constantes/ABI), `boot.s` (en-tête/reset, coldstart, ExecBase, init_task, publish, selftest), `lists.s` (listes + Enqueue/Insert/RemHead/RemTail), `memory.s` (AllocMem/FreeMem multi-header, AvailMem, TypeOfMem), `library.s` (Open/Close/Forbid/Permit/Disable/Enable avec yield-sur-reschedule, jump table), `tasks.s` (AddTask, FindTask, signaux, Signal réveillant les tâches bloquées + demandant un reschedule si prioritaire, SetTaskPri), `ports.s` (AddPort/RemPort en Forbid ; M7d : PutMsg/GetMsg/ReplyMsg INTERRUPT-SAFE = Disable/raw_enable, atomiques vs une IRQ qui touche le même MP_MSGLIST), `interrupts.s` (init_ints + handlers VBlank/INT2/INT6/TRAP partageant un **prologue commun** `movem`+IPL7 et un **épilogue commun** `intr_exit` ; M7c : tâches **user-mode** sur **SSP partagée**, `dispatch` **relocalise** la frame de contexte SSP↔pile user et sauve le nesting par-tâche, `dispatch_in` rte en user-mode ; switch volontaire via `trap #0`/`#1` ; préemption round-robin au VBlank + **flag de dispatch différé** à la sortie d'IRQ quand un serveur réveille une tâche prioritaire ; IPL7 du prologue = gate de ré-entrance des listes vs niveau > 3, M7a ; + dispatcher par numéro `SetIntVector`/`AddIntServer`/`intr_chain_walker`, M7b), `resident.s` (scan ROM des ROMTags → `ResModules` pri-trié, `FindResident`/`InitResident`/`InitCode`), `libinit.s` (`MakeLibrary`/`MakeFunctions`/`InitStruct` — création lib/device, chemin AUTOINIT), `resident.s` ajoute aussi `AddResource`/`OpenResource` ; **`cia.s`** (`cia.resource` : 1er vrai module résident — ciaa/ciab + serveurs PORTS/EXTER `ciaa_server`/`ciab_server` + dispatch ICR), **`timer.s`** (`timer.device` : 2e vrai résident, device AUTOINIT + unité VBLANK + unité MICROHZ via CIA-B/INT6) ; script linker `kick.ld` |
| `src/resources/` | cia, disk, misc, potgo, keymap |
| `src/devices/` | timer, keyboard, gameport, input, audio, console, trackdisk |
| `src/libs/` | expansion, graphics, layers, intuition, mathffp, dos |

## Pipeline de build

1. **ROM principale** (`make kick`) : `vasmm68k_mot -Fvobj` assemble chaque module exec en objet
   relogeable, puis `vlink -b rawbin1 -T src/exec/kick.ld` les lie à `$FC0000` en image brute.
   **Ordre load-bearing** : `boot.o` est passé en premier → son CODE porte l'en-tête de reset à `$FC0000`.
2. **hello-ROM** (`make hello`) : fichier unique via `vasmm68k_mot -Fbin` (smoke test M0).
3. `src/rom/mkrom.py` complète à 256K, écrit footer + champ taille + checksum.
4. `romtool info` valide le conteneur (`is_kick = ok`, `chk_sum = ok`) — gate dur de `make verify`.
5. `tests/boot_test.sh` boote l'image sous FS-UAE et assère le **log série** (canal primaire, capturé
   via un pont PTY `socat` sur `serial_port`) : marqueur de succès présent + marqueur d'échec absent ;
   repli automatique sur la couleur d'écran si aucune émission série (ex. hello-ROM). La ROM émet des
   checkpoints (`chk core`/`chk mem`/`chk m24a|b|c` → `self-test passed`) localisant tout échec.

## État

- **M0** (hello-ROM) : livré, vérifié (`is_kick` + boot écran vert).
- **M2.0→M2.3** (exec coldstart, `src/exec/`) : livré, vérifié (boot écran **blanc** = auto-test passé).
  Le reset entre en `$FC00D2`, passe superviseur + gèle le matériel, **coupe l'overlay** (RAM chip à
  `$0`), pose une pile sous la jump table, bâtit **ExecBase** à `$7F000` (nœud library 34.2,
  `ChkBase=~base`, `MaxLocMem=$80000`, `AttnFlags=0`, `VBlankFrequency=50`, 9 listes système `NEWLIST`),
  construit la **jump table LVO V34** (105 vecteurs, `lib_NegSize $276`, cf. `docs/exec-lvo-table.md`)
  avec 13 LVO implémentés (Open/Close/Expunge, Forbid/Permit, Disable/Enable, AddHead/AddTail/Remove/
  FindName, AllocMem/FreeMem), initialise un **MemHeader chip** + MemList, publie `SysBase` en `$4`,
  puis **auto-vérifie** et **auto-teste** les fonctions via la jump table (dispatch + comportement +
  coalescing). Phases tracées en couleur (rouge→bleu→cyan→blanc ; magenta = échec).
- **M2.4** : mémoire **multi-MemHeader** (sélection par attribut, AvailMem, TypeOfMem) ;
  primitives de listes (Enqueue tri par priorité, Insert, RemHead, RemTail) ; **tâches + signaux**
  non bloquants (TCB `ThisTask`, FindTask, AllocSignal/FreeSignal/SetSignal/Signal, SetTaskPri) ;
  **ports/messages** non bloquants (AddPort/RemPort/FindPort, PutMsg+Signal, GetMsg FIFO, ReplyMsg).
  ⚠️ « vert » = structures manipulées correctement, PAS ordonnancement réel. **Différé à M3**
  (exige les interruptions) : `Wait`/`WaitPort` bloquants, `AddTask`/`RemTask`, dispatch
  (`Switch`/`Dispatch`/`Cause`), réveil d'une tâche sur signal.
- **M3a** : **plomberie d'interruptions**. Autovecteur 68000 niveau 3 (`$6C`) → handler VBlank,
  `INTENA = VERTB|INTEN` ($C020), `SR=$2000` → la chaîne d'interruptions tourne (compteur VBlank qui
  avance, prouvé par le série).
- **M3b** : **ordonnanceur préemptif** (tâches **superviseur**). Le handler VBlank est le point de
  préemption : round-robin (sauve SP de la sortante dans `TC_SPREG`, Enqueue en `TaskReady`, RemHead
  l'entrante, restaure son SP + GPR, `RTE`). `AddTask` (-282) pose la frame initiale miroir du pop
  dispatcher. Prouvé par 2 tâches démo qui **alternent** sur le série (preemption) **en préservant
  leur contexte** (sentinelles de registres).
- **M3c** (exclusion mutuelle, prérequis #1) : `Forbid()` est désormais **honoré** par le scheduler.
  Le handler VBlank défère le switch si une section critique est active — double-garde `EB_TDNEST >= 0`
  (Forbid) **ou** `EB_IDNEST >= 0` (Disable, ferme la fenêtre `addq`/`INTENA`). Ces compteurs sont
  **globaux** (ExecBase) : licite car une tâche interdite n'est jamais commutée, donc `EB_TDNEST`
  reflète toujours la tâche courante ; le switch ne touchant pas ces compteurs, aucune tâche n'est
  reprise avec le compte d'une autre. Modèle **défère-au-prochain-VBlank** (pas de yield immédiat sur
  `Permit` ce milestone) : le switch différé est repris au tick suivant, jamais perdu (`Permit`/`Enable`
  restent de simples dé/incréments). Sections critiques exec enveloppées en **Forbid/Permit** (exclusion
  tâche-vs-tâche ; `Disable` n'est PAS employé ce milestone — il perturberait `INTENA` pendant le
  selftest pré-interruptions) à **sortie unique** : `AllocMem`/`FreeMem`/`AvailMem`/`TypeOfMem`
  (listes mémoire) + `AddPort`/`RemPort`/`PutMsg`/`GetMsg`/`ReplyMsg` (PortList + files de messages).
  Les primitives de listes brutes et `FindName`/`FindPort` restent **non enveloppées** (briques
  arbitrées par l'appelant, contrat exec V34 ; et le handler les appelle -> wrapper = ré-entrée).
  Prouvé **déterministe** (compteur partagé observé à travers une fenêtre interdite, indépendant du
  cadencement série) : `M3C LIVE` émis ssi Forbid honoré (A) ET pas de starvation (B). RED vérifiés :
  garde Forbid retirée -> `FAILED` ; `Permit` retiré -> dérive `EB_TDNEST` attrapée dès l'assertion
  Forbid/Permit du selftest.
- **M3d** (`Wait`/`WaitPort` + réveil-sur-signal) : une tâche peut désormais se **bloquer**.
  `Wait(sigset)` fait un **switch SYNCHRONE** (volontaire) : si aucun signal attendu n'est présent,
  il pose sur SA pile une frame **miroir exact** de celle de `vbl_handler` (`[d0-d7/a0-a6][SR][PC]`),
  passe la tâche en `TS_WAIT` dans `TaskWait`, `RemHead` l'entrante de `TaskReady` et bascule — les
  deux chemins de dispatch (préemptif + volontaire) partagent ce format et `interrupts.s`. Toute la
  surgery est à **IPL 7** (atomique vs VBlank). `WaitPort(port)` boucle `Wait(1<<MP_SIGBIT)` tant que
  la file est vide ; pas de lost-wakeup (PutMsg fait `AddTail` AVANT `Signal`, et le recheck de `Wait`
  est atomique). `Signal` **réveille** une tâche `TS_WAIT` dont les bits attendus arrivent
  (`TaskWait` → `TaskReady`, `TS_READY`) ; la réveillée tourne au **prochain point d'ordonnancement**
  (modèle « défère », cf. yield-sur-Permit ci-dessous). Prouvé **déterministe** par un **ping-pong
  requête/réponse** à 2 ports (deadlock-free : exactement une tâche prête à chaque blocage) :
  `M3D LIVE` émis après `M3D_THRESH` aller-retours (blocages+réveils répétés corrects) ; invariant
  `GetMsg != NULL` après `WaitPort`. RED vérifiés : réveil désactivé (`Signal`) → deadlock, marqueur
  absent ; blocage désactivé (`WaitPort` rend sur file vide) → `GetMsg` NULL → `M3D FAILED`.
  Hypothèse V34 assumée : `Wait` appelé hors `Forbid`/`Disable` (qu'il romprait) ; retour à IPL 0.
- **M3e** (yield immédiat sur `Permit`) : une tâche réveillée **prioritaire** tourne désormais **dès le
  `Permit`** qui ferme la section critique du réveilleur, au lieu d'attendre le prochain tick. `Signal`,
  quand il réveille une tâche de priorité > la courante, pose `EB_ATTNRESCHED` (ABI exec `$12A`).
  `Permit`/`Enable`, au retour à l'état permis (`TDNest`/`IDNest` < 0, l'autre non verrouillé), si
  `AttnResched` est posé, appellent `reschedule` : un **switch SYNCHRONE sans blocage** qui requeue la
  courante dans `TaskReady` (round-robin par priorité) et bascule sur la tête (la réveillée prioritaire).
  `reschedule` réutilise la **queue de switch commune `dispatch_head`** (partagée avec `Wait`) et pose la
  même frame miroir dispatcher ; il fonctionne **indépendamment de `SCHED_ON`** (switch direct, pas
  d'IRQ). Prouvé en régime **COOPÉRATIF** (`SCHED_ON=0`, pas de préemption périodique) pour **isoler** la
  preuve : task_L (pri 0, ne bloque jamais) `Forbid`/`Signal(task_H)`/`Permit` ; task_H (pri 10) boucle
  `Wait`. Le SEUL dispatcher de task_H est le `reschedule` de `Permit` → `M3E LIVE` émis après 500 yields
  ⟺ yield-sur-Permit correct. RED : yield désactivé dans `Permit` → task_H starve (marqueur absent).
- **M3f** (recombinaison yield + préemption) : la préemption périodique (`SCHED_ON=1`) et le
  yield-sur-`Permit` **coexistent sans corruption de contexte**. Les trois chemins de switch sont
  unifiés : `dispatch_head` (RemHead + bascule + `rte`, commun aux trois) et `requeue_and_dispatch`
  (requeue round-robin de la sortante + `clr AttnResched` + `dispatch_head`, partagé par le handler et
  `reschedule`). Le handler **efface `AttnResched` à chaque switch** (un tick satisfait une demande de
  yield en attente → pas de `reschedule` redondant au `Permit` suivant) ; `reschedule` re-teste
  `AttnResched` à IPL 7 (idempotent, ferme la course lecture-IPL0/appel). Prouvé par 3 tâches
  (`SCHED_ON=1`) : task_H (pri 10, cible du yield), task_L (pri 0, signale+yield), task_S (pri 0,
  spinner pur dispatché UNIQUEMENT par la préemption). Sentinelle de contexte (d7) vérifiée après
  chaque switch dans les trois tâches → `M3F FAILED` si corrompue. `M3F LIVE` émis quand `WP_CONS`≥100
  (yield répété) ET `WP_SPIN`≥5 (task_S a tourné via préemption). **Préemption confirmée load-bearing**
  par le RED (`SCHED_ON=0` → task_S monopolise → task_L ne signale plus task_H → `WP_CONS` gèle →
  marqueur absent). Portée de la preuve : M3f valide la **mécanique** du yield et la coexistence sans
  corruption ; la **nécessité** du yield reste prouvée par M3e (démo coopérative, commit 18cba43), car
  sous `SCHED_ON=1` un tick dispatcherait task_H de toute façon (preuve non isolable en un seul mode).
  Le code anti-course (handler efface un `AttnResched` posé, branche `.rs_none`) est correct par
  inspection mais **inerte** dans cette démo (task_L signale sous Forbid → le tick défère).
- **M4** (scan des résidents + InitResident) : la **machinerie de découverte data-driven** des modules.
  `build_reslist` (`resident.s`) scanne `[RESSCAN_LO,RESSCAN_HI)` (toute la ROM) pour les ROMTags —
  mot `RTC_MATCHWORD` ($4AFC) à adresse paire dont `RT_MATCHTAG` pointe sur lui-même (rejette un
  `$4AFC` fortuit, p. ex. l'immédiat du `cmp.w` du scan lui-même) — reprend à `RT_ENDSKIP`, bâtit le
  tableau NUL-terminé `ExecBase->ResModules` trié par `RT_PRI` **décroissant** (tri à bulles stable).
  `InitCode` le parcourt et appelle `InitResident` sur chaque module (filtre version). `InitResident`
  valide le matchword puis, en direct-init (RTF_AUTOINIT clair), saute à `RT_INIT` avec la convention
  ABI **`D0=0, A0=segList, A6=ExecBase`** (le resident n'est pas passé) ; **AUTOINIT (MakeLibrary +
  InitStruct) est DIFFÉRÉ** (no-op). `FindResident` cherche par nom dans `ResModules`. Prouvé par 3
  résidents démo (pri 60/10/-20) **rangés en mémoire dans un ordre différent** (mid, lo, hi) pour que
  le tri soit load-bearing : noms émis `hi→mid→lo` (ordre de priorité), `RES_COUNT==3`, FindResident
  retrouve le bon. RED : tri désactivé → init en ordre de scan → échec du contrôle d'ordre ; dispatch
  `InitResident` désactivé → `RES_COUNT=0`. ⚠️ **Ce n'est PAS encore le handoff de boot** : la phase M4
  tourne puis la démo M3f codée en dur s'exécute (le vrai lancement par un résident viendra avec les
  vrais modules). Convention direct-init **vérifiée** contre l'AutoDoc exec (corrigée en cours de route).
- **M5a** (AUTOINIT : `MakeLibrary` + `MakeFunctions` + `InitStruct`) : le chemin AUTOINIT de
  `InitResident`. `MakeLibrary(vectors, structure, init, dataSize, segList)` alloue negSize (jump table)
  + dataSize (`MEMF_CLEAR`), base = alloc+negSize, bâtit la jump table via `MakeFunctions` (vecteurs
  **absolus** longword OU **relatifs** word si 1er mot = -1, terminés par -1), pose
  `LIB_NEGSIZE`/`LIB_POSSIZE`, `InitStruct` la data table puis appelle l'init function (**D0=base,
  A0=segList, A6=ExecBase**). `InitStruct` interprète le flux `ddssnnnn` (chemin INITBYTE/WORD/LONG :
  dd=11 offset 24 bits, ss taille, item unique, + ré-alignement word + terminateur 00). `InitResident`
  AUTOINIT : `MakeLibrary` puis Enqueue de la base dans la liste selon `RT_TYPE`, **sans** remplir
  name/type/version (quirk V34 — le module le fait). Convention d'appel direct-init (D0=0/A0=segList)
  vs init-de-MakeLibrary (D0=base/A0=segList) : **vérifiées contre l'AutoDoc** (distinctes). Prouvé par
  un résident AUTOINIT démo (`demo.autolib`, table de vecteurs relative) : jump table bâtie (func0 rend
  $5A via `jsr -6(base)`, l'ordre des vecteurs est load-bearing), `InitStruct` pose version+type, init
  func pose révision+nom, lib trouvée dans `LibList`. RED : `InitStruct` désactivé → version KO ; appel
  init func retiré → nom KO.
- **M5b** (`cia.resource` — 1er vrai module résident) : ROMTag `cia.resource` (direct-init, pri 80)
  scanné par `build_reslist` ; `cia_init` crée `ciaa.resource` + `ciab.resource` via `MakeLibrary`
  (base library-like + jump table `AddICRVector`/`RemICRVector`/`AbleICR`/`SetICR`), les nomme, pose la
  base matérielle CIA (`$BFE001`/`$BFD000`), `AddResource`. Exec expose `AddResource` (-486, Enqueue
  `ResourceList`) et `OpenResource` (-498, `FindName`). Les fonctions gèrent les 5 slots de vecteurs ICR
  + le shadow du masque ICR + le registre ICR du chip (`AbleICR` bit7=enable). Prouvé : `OpenResource`
  (« ciab.resource ») trouve la base, base matérielle correcte, `AbleICR($81)` pose le bit0 du shadow,
  `AddICRVector` enregistre (rend NULL, slot libre). RED : `AddResource` cassé → introuvable ; `AbleICR`
  cassé → shadow KO. ⚠️ **DIFFÉRÉ** : la **dispatch INT2/INT6** (les vecteurs enregistrés ne se
  déclenchent pas — Paula INTENA PORTS/EXTER + autovecteurs `$68`/`$78` non posés → inerte et sûr).
  `SetICR` est un stub (status d'interruption différée). Table de vecteurs CIA **absolue** (la démo
  AUTOINIT M5a étant relative, les deux branches de `MakeFunctions` restent exercées).
- **M5c** (`timer.device` — 2e vrai résident, 1er device) : ROMTag `timer.device` **AUTOINIT** (pri 50)
  scanné puis créé par le chemin AUTOINIT de `InitResident` (`MakeLibrary` + Enqueue `DeviceList` par
  `RT_TYPE`=NT_DEVICE). Sa data table (`InitStruct`) pose `LN_TYPE`=NT_DEVICE + `LIB_VERSION` ; son init
  func pose `LN_NAME`="timer.device" (quirk V34 : `InitResident` ne remplit pas les champs). Vecteurs
  device standard (Open/Close/Expunge/ExtFunc/BeginIO/AbortIO), stubs. Prouvé : `FindName(DeviceList,
  "timer.device")` trouve la base, `LIB_VERSION`/`LN_TYPE` (InitStruct), `Open` via `jsr -6(base)`
  incrémente `LIB_OPENCNT`. RED : nom non posé → introuvable ; `Open` cassé → compte KO. ⚠️ **PÉRIMÈTRE** :
  device **créé + nommé + listé + jump table (Open)**. **DIFFÉRÉ** : unités (VBLANK/MICROHZ/ECLOCK),
  file de requêtes, `BeginIO` fonctionnel (stub). Le scan produit ainsi l'OS en instanciant de VRAIS
  modules résidents — mais ni `cia.resource` ni `timer.device` ne font encore de travail fonctionnel
  (squelettes nommés/listés). Les résidents **démo** (`demo.res.*` + `demo.autolib`) sont **conservés**
  dans le scan comme couverture de non-régression M4/M5a (ils s'intercalent par priorité et renforcent
  la preuve du tri) — à retirer quand les vrais modules couvriront ces preuves.
- **M6a** (unité VBLANK de `timer.device` **fonctionnelle**, sans CIA) : **premier comportement OS
  observable** produit par la machinerie résidente + interruption + messages. `BeginIO(TR_ADDREQUEST)`
  convertit la timeval en ticks (`secs*50 + micro/20000`), stocke le décompte dans `TR_TIME`, enqueue
  la requête sur la file de l'unité VBLANK (sous `Disable` — file partagée avec le handler). Le handler
  VBlank appelle un **hook de service** (`VBL_SVC`) chaque tick ; `timer_vblank_service` décrémente
  chaque requête et, à 0, la retire et la **répond**. POINT CLÉ : la réponse en contexte interruption
  utilise des **primitives brutes** (`AddTail` au reply port + `exec_Signal`) et **jamais**
  `PutMsg`/`ReplyMsg` — ces derniers appellent `Permit`, qui ferait un `reschedule` **synchrone au
  milieu de l'interruption** ; `exec_Signal` pose seulement `AttnResched` (le switch se fait en fin de
  handler). Le service est transparent (sauve d0-d2/a0-a4, préserve a6). Prouvé : une requête de
  100000 µs (= 5 ticks) est répondue après ~5 VBlank (délai mesuré ∈ [3..40]) **et** `exec_Signal`
  depuis le handler pose bien le bit (vérifié dans `TC_SIGRECVD` de la boot task). RED : hook coupé →
  timeout ; reply retiré → timeout. **PORTÉE** : prouvé = timer+interruption+messages+`exec_Signal`
  depuis l'IRQ ; **PAS encore montré** = une tâche qui **bloque** sur un timer et est réveillée
  (`Wait`→timer-wake) — nécessite une vraie tâche en attente (la boot task est `TS_RUN`, branche no-wake).
- **M6b** (dispatch d'interruption CIA, INT2/CIA-A) : les vecteurs ICR enregistrés dans `cia.resource`
  se **déclenchent** désormais. `init_ints` installe les autovecteurs 68000 `$68` (INT2/CIA-A) et `$78`
  (INT6/CIA-B) et active Paula INTENA PORTS (pas EXTER — voir plus bas). `int2_handler` lève IPL 7,
  lit le registre ICR du chip **une seule fois** (ACK + efface tous les bits pending), puis `cia_dispatch`
  appelle le vecteur de chaque bit posé (`a1`=IS_DATA, `a5`=IS_CODE, `a6`=SysBase), et acquitte Paula.
  Même discipline mid-handler qu'M6a (un vecteur qui `Signal` ne reschedule pas dans l'IRQ ; état de
  boucle en d2/d3/a2 que la convention serveur préserve). Prouvé **bout-en-bout** : `AddICRVector`
  (timer A, bit 0) + démarrage de CIA-A Timer A one-shot → underflow → /IRQ CIA-A → INT2 → autovecteur →
  `cia_dispatch` → le vecteur de test incrémente un compteur (détecté par le boot). RED : appel du vecteur
  coupé → timeout ; **activation ICR du chip coupée → timeout** (ce RED prouve toute la chaîne, car il ne
  peut passer que si le CIA ému pilote réellement l'interruption). Nettoyage après preuve (RemICRVector +
  stop timer + désactivation PORTS).
  ⚠️ **Gate (M6b → requalifié par M7a)** : M6b tournait en contexte **coopératif** (`SCHED_ON=0`) +
  CIA désactivée avant M3f, car une source CIA de niveau > 3 active sous préemption posait un hazard
  (voir M7a pour sa nature exacte, qui n'était pas celle écrite ici à l'origine). `int6_handler`/EXTER
  (CIA-B) restaient câblés mais non activés. **M7a lève ce blocage pour la ré-entrance des listes.**
- **M7a** (gate de ré-entrance des listes + unité MICROHZ via CIA-B/INT6 + tâche bloquant sur un timer) :
  **le vrai hazard n'était pas la pile** (dans le modèle tâches-superviseur-même-pile, les frames
  d'interruption se dépilent correctement ; la corruption de pile par SSP partagée reste **latente**
  jusqu'au user-mode = M7c). Le vrai hazard = **ré-entrance des listes du scheduler** : `vbl_handler`
  faisait son `Enqueue`/`RemHead` TaskReady à **IPL3**, donc INT6/CIA-B (niveau 6 > 3) pouvait le
  préempter en plein milieu, et l'`exec_Signal` du réveil MICROHZ faisait aussi `Enqueue(TaskReady)` sur
  la même liste à moitié mise à jour → corruption. **Fix 1** : `requeue_and_dispatch` monte IPL7 autour
  de la seule section critique (pas tout `vbl_handler` — INT6 doit préempter le VBlank ailleurs) ;
  `exec_Wait`/`reschedule` y entraient déjà à IPL7. **Fix 2** : `timer_reply` fait son `AddTail`
  (msglist de reply-port, partageable entre unités VBLANK et MICROHZ) à IPL7. L'**unité MICROHZ**
  (2e file `TIMER_MICROQ`, décrémentée par `timer_micro_service` enregistré comme vecteur ICR du timer A
  de CIA-B) réveille une **tâche bloquée** (`task_timer` : `BeginIO`→`Wait`→wake par l'IRQ). Preuve
  **structurelle** via `VBL_INSURG`/`VBL_CLASH` : à IPL7 INT6 est masqué pendant la chirurgie →
  `VBL_CLASH==0` est **garanti** (pas probabiliste). GREEN « M7A TIMER OK » (réveils + `VBL_CLASH==0` +
  time-gate 5 s). RED#1 (gate retiré, IPL3) → clash < 1 s → « M7A FAILED ». RED#2 (réveil cassé) →
  `task_timer` figée, « M3F LIVE » toujours présent → isole le chemin de réveil. Yield re-prouvé en
  **coopératif** (`SCHED_ON=0`, `task_S` retiré → `task_timer` réveillée par le seul yield) : ma modif
  des tails partagés n'a pas régressé le reschedule. `int6_handler`/EXTER désormais **activés et testés**.
  MICROHZ ici = « 1 tick = 1 IRQ CIA-B » (chemin IRQ/réveil prouvé, **calibration µs E-clock différée**).
- **M7b** (dispatcher d'interruption PAR NUMÉRO) : table `IntVects[16]` (AllocMem'd, pointeur dans
  `EB_INTVECTS`) + `SetIntVector` (vecteur exclusif : copie IS_DATA/IS_CODE) + `AddIntServer` (chaîne de
  serveurs triée par `LN_PRI`, marchée par `intr_chain_walker` ; retour Z clair = « géré, stop », Z mis =
  continue, cf. AutoDoc). Les autovecteurs hardcodés `int2_handler`/`int6_handler` sont remplacés par
  `int2_dispatch` ($68/PORTS) / `int6_dispatch` ($78/EXTER) **génériques** qui dispatchent via `IntVects`.
  cia.resource est ré-exprimé en SERVEURS : `ciaa_server` (PORTS, via `AddIntServer`) et `ciab_server`
  (EXTER, via `SetIntVector`) — c.-à-d. cia.resource EST le handler PORTS/EXTER, comme dans le vrai exec.
  CAVEAT : dispatch par NUMÉRO + chaîne, PAS la fidélité IPL-PAR-NIVEAU (les handlers restent IPL7 à
  l'entrée, discipline du gate M7a) ; VERTB garde `vbl_handler` dédié (refactor VERTB→chaîne + switch-sur-
  sortie-d'IRQ différé). PREUVE : GREEN « M7B PORTS OK » (chaîne [ciaa_server pri 10, srv2 pri 0], les 2
  appelés dans l'ordre) + « M7A TIMER OK » désormais via `SetIntVector`/EXTER + « M3F LIVE ». RED : 2e
  serveur non ajouté → M7B FAILED ; vecteur EXTER retiré → M7A absent ; gate M7a (IPL7 retiré) re-prouvé
  à travers le nouveau chemin EXTER → `VBL_CLASH>0` → M7A FAILED. Deux bugs attrapés au bringup :
  (1) vasm tronque un opérande d'EQU à l'espace -> `INTVECTS_TOTAL` sous-évalué (128 au lieu de 352) ->
  sous-allocation ; (2) `move.l (an),Ax` = MOVEA qui N'AFFECTE PAS les CC -> `beq` sur flags périmés ->
  lire `node->Succ` dans un registre de DONNÉES d'abord.
- **M7c** (tâches USER-MODE sur SSP partagée + switch DIFFÉRÉ) : les tâches tournent en user-mode
  (SR bit S=0), chacune sur **sa pile user** ; interruptions + noyau sur **UNE pile superviseur partagée**
  (région STACKTOP). Dérivé du spec public « The Exec Microkernel » (AROS) + mécanique 68000, zéro code
  transcrit. Prologue commun (IPL7 + `movem` → frame `[GPR][SR][PC]` 66 o sur la SSP) ; épilogue `intr_exit`
  dispatche SEULEMENT à la **frontière user** (bit S de la SR sauvée == 0 = on interrompait une tâche user,
  pas une IRQ imbriquée — c'est le nest-count, lu dans le bit S). `dispatch` **relocalise** la frame SSP→pile
  user de la sortante (`TC_SPREG` pointe désormais dans une pile user), sauve/restaure le nesting PAR-TÂCHE
  (`TC_IDNESTCNT`/`TC_TDNESTCNT`↔`EB_*`) et synchronise INTENA → la SSP n'est JAMAIS partagée entre contextes
  de tâches (hazard neutralisé). Switch VOLONTAIRE (Wait/reschedule) via `trap #0`/`#1`. `AddTask` pose SR=$0000
  + nesting=-1. `exec_Signal`/`exec_Wait`/`timer_reply` passent de l'atomicité SR à une **section critique nue**
  (Disable INTENA + `raw_enable`, user-safe, appelables depuis une IRQ sans ré-entrance du scheduler). Lancement
  de la 1re tâche = transition superviseur→user. **Flag de dispatch différé** (spec exec) : un serveur d'IRQ qui
  réveille une tâche prioritaire (AttnResched posé par Signal) provoque le switch à la SORTIE d'interruption,
  sans attendre un Permit ou le VBlank — sinon le réveil dépend du hasard de phase (résonance). PREUVE : GREEN
  « M7C USERMODE OK » (user-mode prouvé par `move sr` → bit S==0, + N préemptions survécues) avec M3F/M7A/M7B
  toujours GREEN sur le nouveau modèle (7/7 runs, `VBL_CLASH==0`, sentinelles d7 intactes). RED : tâches en
  superviseur ($2000) → hang ; relocation bypassée (sp-swap inline sur SSP partagée) → crash ; IPL7 du prologue
  retiré → crash. Coopératif (SCHED_ON=0, task_s retiré) re-prouvé : M3F LIVE via le yield seul + M7A.
- **M7d** (ports INTERRUPT-SAFE) : `PutMsg`/`GetMsg`/`ReplyMsg` manipulent `MP_MSGLIST`, qui peut être touché
  depuis une INTERRUPTION (device piloté par IRQ). Forbid (TDNest) ne masque PAS les interruptions -> une IRQ
  qui `PutMsg`/`ReplyMsg` peut s'entrelacer avec le `GetMsg` d'une tâche sur la même liste doublement chaînée
  (RemHead vs AddTail) -> corruption. FIX : section critique NUE (Disable INTENA + `raw_enable`, sans queue
  reschedule -> pas de ré-entrance du scheduler depuis l'IRQ), qui masque AUSSI les interruptions. AddPort/
  RemPort restent Forbid (PortList non touchée par IRQ). Nesting ReplyMsg->PutMsg->Signal : seul le `raw_enable`
  le plus externe rallume INTEN. PREUVE : série « M7D PORTS OK » — un port partagé (K=4 messages, MAGIC +
  IN_HAND + détecteur de nœuds perdus) martelé par task_port (TÂCHE) ET timer_micro_service (INTERRUPTION,
  GetMsg+PutMsg à chaque INT6) en coexistence avec M3F/M7A/M7C (4/4 runs, zéro corruption). RED (A/B sous
  CONTENTION MAX dédiée — task_port pri haute, sans rate-limit, fenêtre 90 s) : ports en Forbid -> « M7D FAILED:
  shared-port list corrupted » ; MÊME contention, ports en Disable -> propre. La course est statistique
  (fenêtre RemHead/AddTail sub-µs, corruption CUMULATIVE sur liste doublement chaînée) : déterministe sous
  contention max + fenêtre longue, non déclenchée par la démo de coexistence allégée.
- **À venir (M7e+)** : **fidélité IPL-par-niveau** (VERTB en chaîne + tourner à l'IPL natif de l'interruption),
  décodage INTREQR multi-source, conversion `timer_reply`->`ReplyMsg` (le hack bas-niveau n'est plus nécessaire),
  `RemTask`, quantum SFB_TQE, priorité réelle, calibration µs réelle de MICROHZ, puis les modules graphiques → écran.

Voir `docs/PLAN.md` pour la suite et `docs/CLEANROOM.md` pour le mur.
