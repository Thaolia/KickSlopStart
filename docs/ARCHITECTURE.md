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
| `src/exec/` | exec.library, découpée en modules reliés par vlink : `exec.i` (constantes/ABI), `boot.s` (en-tête/reset, coldstart, ExecBase, init_task, publish, selftest), `lists.s` (listes + Enqueue/Insert/RemHead/RemTail), `memory.s` (AllocMem/FreeMem multi-header, AvailMem, TypeOfMem), `library.s` (Open/Close/Forbid/Permit/Disable/Enable avec yield-sur-reschedule, jump table ; **`OpenLibrary`/`CloseLibrary`/`OldOpenLibrary`** : ouverture par nom = Forbid + `FindName(LibList)` + gate de version (`lib_Version >= version`, sinon 0) + appel du vecteur Open/-6 de la lib ; chargement disque ramlib si non-résidente différé à M6), `tasks.s` (AddTask, FindTask, signaux, Signal réveillant les tâches bloquées + demandant un reschedule si prioritaire, SetTaskPri), `ports.s` (AddPort/RemPort en Forbid ; M7d : PutMsg/GetMsg/ReplyMsg INTERRUPT-SAFE = Disable/raw_enable, atomiques vs une IRQ qui touche le même MP_MSGLIST), `interrupts.s` (init_ints + handlers INT2/INT3/INT6/TRAP partageant un **prologue commun** `movem` (à l'IPL **natif** depuis M7e) et un **épilogue commun** `intr_exit` ; M7f : les 3 autovecteurs utilisés sont UNIFORMES — `int2_dispatch`(PORTS)/`int3_dispatch`(niveau 3)/`int6_dispatch`(EXTER) passent par `intr_dispatch_number` -> chaîne de serveurs ; la décision round-robin est `sched_server`, serveur de la chaîne VERTB ; M7g : `int3_dispatch` décode `INTREQR` et dispatche CHAQUE source de niveau 3 en attente (COPER/VERTB/BLIT) ; M7c : tâches **user-mode** sur **SSP partagée**, `dispatch` **relocalise** la frame de contexte SSP↔pile user et sauve le nesting par-tâche, `dispatch_in` rte en user-mode ; switch volontaire via `trap #0`/`#1` ; **flag de dispatch différé** `intr_isr_defer` à la sortie d'IRQ quand un serveur pose `AttnResched` ; M7e : section critique du switch montée à **IPL7 bref** = gate de ré-entrance des listes, instantané vs le délai de propagation d'INTENA ; dispatcher par numéro `SetIntVector`/`AddIntServer`/`intr_chain_walker`, M7b), `resident.s` (scan ROM des ROMTags → `ResModules` pri-trié, `FindResident`/`InitResident`/`InitCode`), `libinit.s` (`MakeLibrary`/`MakeFunctions`/`InitStruct` — création lib/device, chemin AUTOINIT), `resident.s` ajoute aussi `AddResource`/`OpenResource` ; **`cia.s`** (`cia.resource` : 1er vrai module résident — ciaa/ciab + serveurs PORTS/EXTER `ciaa_server`/`ciab_server` + dispatch ICR), **`timer.s`** (`timer.device` : 2e vrai résident, device AUTOINIT + unité VBLANK + unité MICROHZ via CIA-B/INT6), **`trackdisk.s`** (`trackdisk.device` — **B1/M6t** : 2e device, ROMTag AUTOINIT pri 20 → DeviceList ; `Open` valide le numéro d'unité (DF0-3 → io_Unit = aire de l'unité, io_Device = base, OpenCnt++ ; unité ≥ 4 → échec OpenDevice io_Error/io_Device=0) ; `BeginIO` (**B4/M6w** puis **multi-piste M6z** : traite **`CMD_READ`** — convertit l'offset octet en (piste, secteur) via `bloc=offset/512`, `piste=bloc/11`, `secteur=bloc%11`, boucle sur CHAQUE piste touchée via td_read_track+td_decode_track, copie jusqu'à la fin de piste et avance → une requête TRAVERSANT une frontière de piste est servie en plusieurs lectures ; gardes `IOERR_BADLENGTH` (offset/length multiples de TD_SECTOR) et `TD_DISKBYTES` (borne) ; autres commandes → IOERR_NOCMD ; **ReplyMsg si non-quick** écrit mais seul le chemin QUICK est prouvé pour l'instant — le non-quick sera exercé par un vrai `DoIO` en C) ; unités = placeholders → Unit+MsgPort en B2. **B2/M6u** : `td_read_track0` lit une piste MFM brute de DF0 — CIA-B DDRB=$FF + PRB moteur/select DF0 (latch via front SEL0), spin-up (poll DSKRDY timeout), **disk DMA Paula** (ADKCON WORDSYNC, DSKSYNC=$4489, DSKPT, DSKLEN×2), poll `INTREQR` DSKBLK avec timeout ; registres/bits dans `disk.i`. N'écrit QUE CIA-B PRB (timers MICROHZ/M7a intacts). **B2b/M6x** : `td_read_track(n°)` seek d'abord — recalibration à la piste 0 (step OUT via DSKDIREC jusqu'à DSKTRACK0) puis step IN jusqu'au cylindre cible + side-select (DSKSIDE selon piste&1) → lit n'importe quelle piste ; `td_decode_track` renvoie le n° de piste décodé (oracle du seek). **B3/M6v** : `td_decode_track` scanne les syncs $4489, décode chaque secteur (combine odd/even `((odd&$55555555)<<1)|(even&$55555555)`), vérifie les checksums en-tête ET data (XOR des longs MFM & masque), range les 512 o par n° de secteur → 11 secteurs décodés+vérifiés, secteur 0 = bootblock « DOS\0 » ; algorithme verrouillé par round-trip Python), **`strap.s`** (`strap_boot` — **M6r** : ÉCHAFAUDAGE de la décision de boot ; renvoie 0 = aucun volume bootable → l'appelant **route** l'affichage de l'écran insert-disk par cette décision ; `FindName(trackdisk)` + CMD_READ + validation/exécution du bootblock viendront aux incréments B/C) ; script linker `kick.ld` |
| `src/graphics/` | piste graphique (M4+) : `graphics.i` (registres d'affichage OCS dérivés de `CUSTOM` : COP1LC/COPJMP1/DIW/DDF (overscan 352×272)/BPLCON0/1/BPL1-2MOD/BPL1PT/COLOR00-01 + bits DMACON ; dimensions écran de boot), `gfx.s` (`gfx_display_init` — **M6s** : alloue 5 bitplanes chip, Y COPIE l'**écran de boot** (image chaton « KickSlopStart » 352×272×5 = 32 couleurs, overscan) depuis la ROM, monte BitMap/ViewPort/View/ColorMap(32), `FindName("graphics.library")`, puis `MakeVPort`/`MrgCop`/`LoadView` **via la jump table** → la copper list (5 pointeurs de plan + 32 couleurs) est GÉNÉRÉE par l'ABI ; restaure `a6`=SysBase. Historique M4a/M4b/M4c2 : écran rayé 1 plan, remplacé ici par l'image), **`graphics_lib.s`** (`graphics.library` — ROMTag AUTOINIT pri 65 → `MakeLibrary` dans `LibList`, **M4c1** ; **M4c2** moteur d'affichage, **M6s** : `MakeVPort` rendu **GÉNÉRIQUE** — émet un pointeur BPLxPT par plan (depth) + `cm_Count` couleurs COLOR00.. → supporte 1 plan/2 couleurs comme 5 plans/32 couleurs ; `MrgCop` fusionne → `v_LOFCprList`, `LoadView` installe COP1LC + `DMACON`), `mk_bootscreen.py` (pipeline Pillow générant les données de l'écran de boot : JPEG utilisateur → 352×272 → quantize 32 couleurs → 5 bitplanes planar, **auto-vérifié** ; sort `bootscreen.raw` + palette OCS + PNG de référence) + `bootscreen_data.s` (GÉNÉRÉ : palette + `incbin bootscreen.raw`). Discriminant VISUEL (nb de couleurs uniques capturées) ; preuve par élimination (RED `BOOTSCR_ONE_PLANE`) |
| `src/intuition/` | piste intuition (M5+) : `intuition.i` (layout `IntuitionBase` V34 — champs 1re génération stables : `ib_LibNode`/`ib_ViewLord` (View embarqué = le « ViewLord »)/ActiveWindow/ActiveScreen/FirstScreen/Flags/Mouse/Seconds/Micros ; `INTUITIONBASE_SIZE`=80 ; LVO `ViewAddress`=-294), **`intuition_lib.s`** (`intuition.library` — module résident ROMTag AUTOINIT pri 10 → `MakeLibrary` dans `LibList` (branche NT_LIBRARY), **M5** : squelette Open/Close/Expunge + `ViewAddress` (vecteur 49) renvoyant `&ib_ViewLord`). Différé : OpenScreen/OpenWindow/DisplayAlert, rendu, écran insert-disk (→ M6, vrai déclencheur). Discriminant SÉRIE (marqueur M5I) ; preuve par élimination (RED `M5I_BAD_VIEWADDR`) |
| `src/dos/` | piste dos (M6+) : `dos.i` (layout `DosLibrary`/`RootNode`/`DosInfo` (dosextens.i) + convention **BPTR** (`addr>>2`) + `DateStamp` + LVO `DateStamp`=-192 ; scaffold `DL_DISHADOW` = APTR brut DosInfo pour auto-vérif BPTR sans déréférencement), **`dos_lib.s`** (`dos.library` — module résident ROMTag AUTOINIT pri 0 → `MakeLibrary` dans `LibList`, **M6** : squelette Open/Close/Expunge + initfunc qui alloue RootNode + DosInfo **séparément** via AllocMem (long-alignés, requis pour BPTR), câble `dl_Root` (APTR) et `rn_Info` (BPTR), + `DateStamp` (vecteur 32) remplissant (0,0,0) « horloge non réglée » (fidèle V34) et renvoyant le pointeur. Déviation clean-room assumée : init C-style au lieu du glue BCPL d'origine — ABI observable reproduite, pas le mécanisme). Différé : packets/LoadSeg/handlers, Open/Read/Lock, strap/trackdisk, écran insert-disk. Discriminant SÉRIE (marqueur M6D) ; preuve par élimination (RED `M6D_BAD_BPTR`). **`ofs.i` + `ofs.s`** (**D1** : lecture seule OFS — machinerie INTERNE du filesystem, PAS de packets/handler BCPL = D3) : `ofs_read_file(name, dest, max)` lit un fichier par nom en parcourant root@880 → table de hash (hash `h=(h*13+toupper(c))&$7FF`, idx=`h%ht_size`) → header (nom BCPL, sec_type ST_FILE, first_data, hash_chain) → chaîne de data blocks OFS (type 8, data_size, next, données @+24), via trackdisk `CMD_READ` (M6z). Insensible à la casse ; valide type/sec_type/bornes de bloc avant chaque lecture ; boucles cappées (anti-hang). Format verrouillé empiriquement sur un ADF de test. Discriminant SÉRIE (marqueur **D1**, taille==1024 + marqueurs multi-block) ; preuve par élimination (RED `OFS_NO_DATACHAIN` → taille 488). **`loadseg.s`** (**D2** : LoadSeg — machinerie INTERNE, pas de packets = D3) : `dos_loadseg(name)` → BPTR seglist | 0, `dos_unloadseg(BPTR)`. Charge un exécutable « hunk » depuis l'OFS (via `ofs_read_file`), alloue un segment par hunk, copie le contenu, **applique les relocations HUNK_RELOC32** ($3EC ; $3FC/SYMBOL/DEBUG → échec propre), bâtit la seglist BPTR (`[taille][next BPTR][contenu]`, BPTR → bloc+4, contenu à `(BPTR<<2)+4`). Format hunk verrouillé empiriquement. Discriminant SÉRIE (marqueur **D2LOADSEG**, émis par le code chargé+relocalisé qui tourne depuis la RAM) ; preuve par élimination (RED `D2_NO_RELOC` → reloc non appliquée → pointeur vers RAM basse → marqueur absent) |
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
  convertit la timeval en ticks (`secs*50 + micro/20000` pour l'unité VBLANK ; M7l sépare la conversion de
  l'unité MICROHZ en µs réelles, cf. bullet M7l), stocke le décompte dans `TR_TIME`, enqueue
  la requête sur la file de l'unité VBLANK (sous `Disable` — file partagée avec le handler). Le handler
  VBlank appelle `timer_vblank_service` chaque tick (hook `VBL_SVC` à l'origine ; **M7f** : devenu un
  serveur de la chaîne VERTB) ; le service décrémente chaque requête et, à 0, la retire et la **répond**.
  POINT CLÉ (à l'origine M6a) : la réponse en contexte interruption ne pouvait PAS utiliser `PutMsg`/
  `ReplyMsg` car ils appelaient `Permit` -> `reschedule` **synchrone au milieu de l'interruption** ;
  M6a utilisait donc une routine bespoke (`timer_reply`) qui ne posait qu'`AttnResched`. **M7d** a rendu
  `PutMsg`/`ReplyMsg` interrupt-safe (Disable/`raw_enable`, sans yield) et **M7i** a supprimé `timer_reply`
  au profit de `ReplyMsg` direct (cf. bullet M7i). Prouvé (M6a) : une requête de
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
  MICROHZ en M7a = « 1 tick = 1 IRQ CIA-B » (chemin IRQ/réveil prouvé ; **calibration µs réelle livrée en M7l**).
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
- **M7e** (fidélité IPL-PAR-NIVEAU) : les handlers ne montent plus IPL7 au prologue — ils tournent à leur IPL
  **natif** (VBlank=3, PORTS=2, EXTER=6, posé par le CPU à la prise d'autovecteur). Conséquence : une source de
  niveau supérieur préempte le **corps** d'un handler inférieur (INT6 préempte le corps de `vbl_handler`). La
  section critique du switch (`dispatch` : relocalisation puis Enqueue/RemHead TaskReady) est masquée par **IPL7
  bref** (`move #imm,sr`), PAS par INTENA-off. **Découverte empirique (FS-UAE)** : masquer par INTENA-off laisse
  une course — l'écriture d'INTENA a un **délai de propagation** (quirk Amiga), donc un INT6 déjà asserté sur les
  lignes IPL chevauche la fenêtre de chirurgie. L'écriture SR (IPL) est, elle, **interne au CPU = instantanée**.
  **Argument de privilège** (pourquoi IPL ici mais INTENA ailleurs) : la chirurgie tourne en SUPERVISEUR (atteinte
  via `intr_exit`/trap) → `move to SR` légal → IPL7 possible. `Signal`/`PutMsg`/`GetMsg`/`Wait`/`timer_reply` sont
  appelables depuis une tâche USER-MODE où `move to SR` est **privilégié** (manuel 68000) → ils ne peuvent pas monter
  l'IPL → ils gardent INTENA-Disable. **Honnêteté (cohérence M7d)** : la fenêtre write-delay touche donc TOUTE section
  masquée par INTENA appelable en user-mode — Signal, les ports M7d, Wait, timer_reply — par nécessité ; elle est
  tolérée par le re-check (Wait re-teste au réveil) et empiriquement bénigne pour les ports M7d même en contention
  max. SEUL le switch côté superviseur a été promu à l'IPL. La relocalisation de frame (SSP→pile user) reste à l'IPL
  natif sans masque : INT6 s'imbrique SOUS `sp`, la frame sortante `[sp,sp+66)` est intacte. PREUVE : série
  « M7E IPL OK » gated sur `VBL_PREEMPT_COUNT>0` (INT6 préempte le corps de vbl, détecteur `timer_micro_service`) ET
  `VBL_CLASH==0` (zéro chevauchement INT6/chirurgie — `VBL_CLASH` est un proxy d'OVERLAP, précondition de corruption,
  PAS un détecteur de corruption). GREEN 3/3 ; RED1 (`M7E_SURGERY_INTENA=1`, surgery en INTENA-off) → `VBL_CLASH>0`
  « M7A FAILED » 3/3 (prouve l'IPL7 load-bearing) ; RED2 (`M7E_PROLOGUE_IPL7=1`, IPL7 au prologue) → `M7E IPL OK`
  absent 2/2 sans crash (prouve l'IPL natif load-bearing, pas cosmétique) ; non-régression coopérative
  (`M7E_COOP=1`, `SCHED_ON=0`, yield-only) re-prouvée. L'idle du dispatcher (atteint seulement si TaskReady vide
  après un Wait) n'est pas exercé par ces démos (les tâches round-robin/spin gardent TaskReady peuplée) — documenté.
- **M7f** (VERTB EN CHAÎNE DE SERVEURS) : le handler VBlank dédié `vbl_handler` est remplacé par
  `int3_dispatch`, un dispatcher générique miroir de `int2_dispatch`/`int6_dispatch` -> `intr_dispatch_number`
  `(INTB_VERTB=5)` -> **chaîne de serveurs par priorité**. Modèle désormais UNIFORME pour les 3 autovecteurs
  utilisés : PORTS(int2)/VERTB(int3)/EXTER(int6). La **décision d'ordonnancement** (quantum round-robin) devient
  `sched_server`, serveur VERTB de pri 20 qui pose `EB_ATTNRESCHED` (sous les mêmes gardes que l'ancien
  `vbl_handler` : `SCHED_ON && !Forbid && !Disable && TaskReady` non vide -> le round-robin RESPECTE Forbid) ;
  `intr_isr_defer` la consomme à la sortie d'IRQ (comme un réveil INT6). Faithful : le vrai exec a un serveur
  VBlank qui pose la flag AttnResched. `timer.device` enregistre son service VBLANK via `AddIntServer(VERTB,
  timer_vblank_int)` (pri 0) au lieu du hook `VBL_SVC` (supprimé) ; `timer_vblank_service` retourne Z-set
  (« continue la chaîne »). **Risque clé traité** : `intr_chain_walker` re-fournit `a6` AVANT chaque serveur
  mais NE le restaure PAS après le dernier (les serveurs ne préservent que d2-d7/a2-a4) -> `intr_isr_defer`
  **recharge `a6=SysBase`** avant de lire `EB_ATTNRESCHED` (sinon décisions de dispatch sur a6 clobbé). Les
  structs Interrupt vivent en RAM basse réservée (< `HEAP_LOWER`, hors pool AllocMem ; AddIntServer les Enqueue).
  PREUVE : série « M7F VERTB OK » gated sur `VERTB_CHAIN_N` (compteur du serveur de QUEUE `vbl_tail`, pri -10)
  -> prouve que le walker parcourt TOUTE la chaîne (sched(20) + timer(0) avant tail(-10), en ordre de priorité) ;
  le scheduler (M3F LIVE) ET le timer (M7A/M6A via `timer_vblank`) fonctionnent À TRAVERS la chaîne. GREEN
  3/3 (0 FAILED) ; RED (`M7F_SCHED_STOPS_CHAIN=1`, sched retourne Z-clair) -> le walker ARRÊTE la chaîne
  après sched -> `timer_vblank`/`vbl_tail` jamais appelés -> « M6A FAILED: timer VBLANK unit incorrect »
  2/2 (preuve : la sémantique call-all Z-set = la marche dispatche BIEN les serveurs suivants en séquence).
  Non-régression M3f + coopérative (`M7E_COOP=1`) + M7e (« M7E IPL OK ») + M7a/M7c/M7d re-prouvés dans le même
  boot. **Découverte (hypothèse RED initiale invalidée empiriquement)** : retirer le SEUL quantum VBlank
  (`sched_server`) ne stoppe PAS la préemption -> « M3F LIVE » émet quand même, car INT6 (MICROHZ ~140/s)
  co-pilote le round-robin : TOUT dispatch différé (`intr_isr_defer`, d6=1) requeue la sortante et pivote les
  tâches de pri égale. Le quantum VBlank est donc redondant avec un timer INT6 rapide dans cette démo ; il
  reste la bonne place (fidèle) pour la décision, mais son effet n'est pas isolable ici. HORS SCOPE
  (M7g+) : INT3 reste mono-source VERTB (pas de décodage INTREQR COPER/BLIT).
- **M7g** (DÉCODAGE INTREQR MULTI-SOURCE) : `int3_dispatch` ne suppose plus VERTB seule — il lit
  `INTREQR & INTENAR` et dispatche+acke CHAQUE source de niveau 3 en attente (COPER bit4 / VERTB bit5 /
  BLIT bit6) via `IntVects[n]`. VERTB -> compteur M3a + chaîne (M7f) ; COPER/BLIT -> leur vecteur. `int2`
  (PORTS) / `int6` (EXTER) restent mono-source : leur niveau n'a qu'UNE source Paula (optimisation correcte,
  pas une boucle générique). Le masque des sources en attente est tenu dans `d2`, préservé à travers les
  dispatch par la convention serveur (walker `movem d2/a2-a4` ; `coper_test` ne touche que son compteur) ;
  `a6` est rechargé après chaque dispatch (leçon M7f). **Bonus de correction** : sur un INT3 SPURIOUS (délai
  de propagation d'ack, cf. M7e) les 3 `btst` échouent -> aucun dispatch, vs le dispatch VERTB inconditionnel
  de M7f. PREUVE : une 2e source de niveau 3 (COPER) est DÉCLENCHÉE PAR LOGICIEL (`INTREQ=SETCLR|COPER`
  depuis le serveur VERTB `vbl_tail`, rate-limité 1/4 ; pas de graphics requis) ; `IntVects[COPER]` =
  `coper_test` (vecteur exclusif) incrémente `COPER_FIRED`. Série « M7G MULTISRC OK » gated sur
  `COPER_FIRED>=seuil` -> int3 sert CHAQUE source de niveau 3 en attente (COPER sur son propre INT3, VERTB
  sur le sien), plus seulement VERTB. **Portée exacte** : le per-source SÉQUENTIEL est prouvé (vbl_tail pose
  COPER PENDANT l'INT3 VERTB -> d2 est déjà échantillonné -> COPER servie à l'INT3 SUIVANT) ; le cas
  co-pending (VERTB+COPER sur le MÊME INT3) n'est PAS isolé. BLIT : chemin présent mais par-inspection
  seulement (aucune source BLIT en démo ; identique au chemin COPER prouvé). GREEN 3/3 (0 FAILED) ;
  RED (`M7G_MONO_SOURCE=1`) -> int3 décode+acke COPER mais NE la dispatche PAS -> « M7G » absent,
  `COPER_FIRED` figé, tout le reste identique SANS storm (preuve : le dispatch par source décodée est
  load-bearing). Note : un vrai mono-source (acke VERTB seul) LIVELOCKERAIT la machine (COPER niveau 3
  pending-non-ackée -> INT3 en boucle) ; d'où le RED « dispatch-skip » qui isole proprement la variable.
  Non-régression M3f + coopérative + M7a..M7f re-prouvés dans le même boot.
- **M7h** (QUANTUM RÉEL) : `sched_server` ne pose plus `AttnResched` à CHAQUE tick — il compte
  `QUANTUM_ELAPSED` et ne préempte qu'après `M7H_QUANTUM` ticks de time-slice (défaut 4, comme
  SysBase.Quantum d'exec). `dispatch_in` reset `QUANTUM_ELAPSED` sur un changement RÉEL de tâche
  (entrante != sortante ; pas de reset sur dispatch-vers-soi). La priorité stricte était DÉJÀ correcte
  (RemHead pick la plus haute pri, Enqueue requeue par pri, Signal préempte sur réveil prioritaire) ->
  pas de gap priorité, M7h = quantum seul. **Observabilité (conséquence directe de M7f)** : en démo
  NORMALE, INT6 (task_timer ~140/s) dispatche -> `dispatch_in` reset `QUANTUM_ELAPSED` avant qu'il
  n'atteigne le quantum -> le quantum ne se déclenche QUASI JAMAIS (QUANTUM_EXPIRE_N≈0) ; c'est un
  quasi-no-op et la rotation reste pilotée par INT6 (non-régression M3F..M7G OK). Le quantum n'est
  OBSERVABLE qu'en ISOLATION (`M7H_QUANTUM_DEMO=1`) : `setup_demo_tasks` ne crée que task_s + task_q2
  (2 spinners pri 0, aucun préempteur prioritaire ni yield ; INT6 tourne mais ne Signale personne ->
  ne rotate pas) -> le quantum VBlank devient le SEUL rotateur. PREUVE : « M7H QUANTUM OK » gated sur
  `QUANTUM_EXPIRE_N*2 < VBL_COUNT` (débit ≈ VBL/4 pour QUANTUM=4 -> quantum > ~2 ticks) ET `WP_SPIN>0`
  (task_s a tourné = rotation réelle, pas monopolisé). GREEN-défaut 3/3 (non-rég, M7H absent) ;
  GREEN-isolation 2/2 (« M7H QUANTUM OK ») ; RED-isolation `M7H_QUANTUM=1` -> rotation chaque tick ->
  `QUANTUM_EXPIRE_N≈VBL_COUNT` -> discriminant échoue -> « M7H » absent 2/2 ; coopérative OK. Framing
  honnête : quantum FIDÈLE, observable seulement isolé ; quasi-no-op en défaut = conséquence correcte de
  l'archi (INT6 co-pilote), pas une faiblesse.
- **M7i** (`timer_reply` -> `ReplyMsg`) : la routine de réponse bespoke `timer_reply` (M7c) est SUPPRIMÉE.
  Elle existait parce qu'à l'époque `PutMsg`/`ReplyMsg` appelaient `Permit` -> reschedule SYNCHRONE
  interdit au milieu d'une interruption. M7d a rendu ces primitives interrupt-safe (Disable INTENA +
  `raw_enable`, SANS tail Permit/yield) -> le hack n'a plus de raison d'être. Les 2 services qui
  répondaient (timer_vblank_service / timer_micro_service, chemin interruption) appellent désormais
  directement `LVO_REPLYMSG` (AddTail + Signal + marque NT_REPLYMSG, atomique, aucun yield en IRQ).
  `timer_beginio` n'était PAS un appelant (il force min 1 tick -> reply différé, et tourne en contexte
  tâche). Register-safe : ReplyMsg clobbe d0/d1/a0/a1, préserve d2-d7/a2-a6 (les invariants de boucle
  d2/a2/a4, et d3/a5 pour le chemin micro, survivent). PREUVE = ÉQUIVALENCE : jeu de marqueurs
  IDENTIQUE à la démo par défaut M7h (M3F/M6A/M7A/M7C/M7D/M7E/M7F/M7G, 0 FAILED) sur GREEN 3/3 +
  coopérative — le swap est observablement inerte (refactor, pas nouveau mécanisme ; aucun RED à part un
  bug planté). La justification inversée (« on n'utilise PAS ReplyMsg car Permit yield ») a été corrigée
  partout (en-tête timer.s, commentaires des services, ce document).
- **M7j** (`RemTask` — CYCLE DE VIE) : `RemTask(task a1)` retire une tâche et libère sa pile
  (`TC_SPLOWER..TC_SPUPPER`) + son TCB (`TC_SIZE`). Deux chemins. **SELF** (`a1`=0 ou ThisTask — le cas
  « une tâche se termine » : son corps RTS -> `task_exit` -> `RemTask(self)`) : `trap #2` -> superviseur.
  Réalisation d'option (D) de l'advisor : une fois en superviseur on tourne sur la **SSP partagée**, donc
  la pile user de la sortante n'est PLUS utilisée et est libérable ; on `FreeMem` pile puis TCB, puis on
  bascule sur la tâche suivante exactement comme le lancement de la 1re tâche (`RemHead` + `dispatch_in`,
  NE REVIENT PAS). **Pièges traités** : (1) `FreeMem` utilise Forbid/Permit et Permit YIELD -> on enveloppe
  le teardown dans un `Forbid` EXTERNE (le Permit interne voit TDNEST>=0 -> pas de yield) + IPL7 (masque
  IRQ) ; (2) on efface `EB_THISTASK` AVANT `FreeMem(TCB)` car `dispatch_in` le lit (cmp QUANTUM_ELAPSED M7h)
  -> pas de lecture de TCB libéré ; (3) QUANTUM_ELAPSED est global -> `dispatch_in` le reset sur le switch
  (note M7h close). **NON-SELF** (`a1` != ThisTask, tâche ready/waiting) : pas de trap ni switch — Forbid
  (anti-yield) + Disable (vs IRQ) + `Remove` + `FreeMem` pile+TCB + raw_enable + Permit, retour au caller.
  PREUVE : « M7J REMTASK OK » — task_rm (pri 0) tourne `RM_THRESH` fois puis RTS -> `task_exit` ->
  `RemTask(self)` ; task_timer (survivante) capture `AvailMem` AVANT création de task_rm, puis confirme
  qu'après l'auto-retrait `AvailMem` est remonté d'au moins `M7J_RECOVER` (pile 2048 + TCB) = free réussi.
  GREEN 2/2 + non-régression défaut (M3F..M7G, 0 FAILED, M7J absent car task_rm hors config par défaut) 3/3
  + coopérative ; RED (`M7J_NOFREE=1`, FreeMem sauté) -> `AvailMem` ne remonte pas -> « M7J » absent 2/2,
  SANS crash (task_rm bien retirée de l'ordonnancement, seule la mémoire fuit). **Limites** : non-self par
  inspection (la démo exerce le self) ; `tc_MemEntry` non libéré (aucune tâche démo n'en alloue) -> hors scope.
- **M7l** (CALIBRATION µs RÉELLE MICROHZ) : avant M7l, `timer_beginio` convertissait `TV_MICRO` en ticks via
  `/20000` (le facteur VBLANK 50 Hz) pour les DEUX unités -> sur l'unité MICROHZ (CIA-B, latch `$00FF` = 255
  ticks E-clock) `TV_MICRO` ne valait PAS des µs réelles (une requête « 400000 µs » durait ~7 ms, pas 400 ms).
  M7l SÉPARE la conversion par unité : MICROHZ compte en interruptions CIA-B via `US_PER_INT`=359 /
  `INTS_PER_SEC`=2782 (E-clock PAL 709379 Hz = CPU/10, latch 255 -> ~359,5 µs/int) ; VBLANK garde `/20000`.
  `TV_MICRO` signifie donc des µs réelles, à la résolution d'une interruption (~360 µs). PREUVE = INTER-HORLOGES
  (NON tautologique : E-clock CPU vs raster display, matériels différents) : une requête MICROHZ de 0,5 s doit
  s'écouler en ~25 ticks VBLANK (horloge 50 Hz indépendante). GREEN « M7L MICROHZ CALIB OK » = elapsed ∈ bande
  [22,28] (3/3). RED (`M7L_OLD_CONV=1`, conversion VBLANK rétablie sur MICROHZ) : la requête de 0,5 s expire en
  ~25 interruptions ≈ 9 ms < 1 tick VBLANK -> elapsed ~0-1 -> M7L ABSENT, M3F..M7G verts (2/2, RED chirurgical :
  la valeur de requête de la boucle `task_timer` est gatée en parallèle via `TT_MICRO_REQ` pour garder la PÉRIODE
  ~7 ms sous les deux conversions). COOP : non-régression de tous les marqueurs antérieurs (M3F/M6A/M7A/M7E/M7F/
  M7G, 0 FAILED) ; M7L est une preuve du build PAR DÉFAUT (comme M7C/M7D dépendent des spinners, M7H de
  l'isolation) : en coopératif la latence de réveil (task_timer pri 10 ne préempte pas task_h pri 10 — Signal à
  pri égale ne pose pas AttnResched -> attend le yield de task_h) gonfle la fenêtre VBLANK mesurée au-delà de la
  bande serrée -> M7L non émis. C'est un artefact de MESURE, pas d'erreur de calibration — PROUVÉ PAR CONSTRUCTION :
  le décompte est 1392 interruptions CIA-B sur le timer matériel (latch `$00FF`, non gaté, identique dans TOUT
  build) donc l'achèvement est fixé à ~0,5 s ≈ 25 ticks quel que soit `SCHED_ON` ; donc `elapsed = 25 + head(<1) +
  latence-réveil`, et seule la latence-réveil diffère entre préemptif et coopératif (magnitude immatérielle, mécanisme
  déductif ; confirmé empiriquement aussi : bande élargie [22,250] -> M7L réapparaît en coop). **Limites** : résolution
  sub-interruption (< 360 µs, lecture live du latch E) + unité ECLOCK différées ; le chemin `secs` de la conversion
  n'est pas exercé par les démos (les deux requêtes ont secs=0) -> correct par construction, non prouvé empiriquement.
- **M4 graphics FAIT** (Copper → bitplane → graphics.library résidente → affichage généré par l'ABI). **M5 intuition : squelette résident + `ViewAddress` FAIT** (`src/intuition/`) ; l'écran « insert Workbench disk » est reporté à **M6** (son vrai déclencheur = pas de volume bootable ; les docs publiques confirment qu'il n'est PAS une fonction intuition — refuser l'écran synthétique, cf. logique M7k reporté).
- **`OpenLibrary` exec FAIT** (`library.s` : `OpenLibrary`/`CloseLibrary`/`OldOpenLibrary` ; marqueur série M5O : succès version 34 + OpenCnt+1, gate version 99→0, lib inexistante→0, CloseLibrary→OpenCnt-1 ; RED `OPENLIB_NO_VERCHECK`). Les preuves M4c1/M5 (FindName+Open à la main) peuvent maintenant être refactorées pour passer par `OpenLibrary` (suivi).
- **dos.library squelette résident FAIT** (`src/dos/` : `DosBase`+`RootNode`+`DosInfo` liés par **BPTR**, structures séparément AllocMem'd/long-alignées ; `DateStamp`-192 → (0,0,0) horloge non réglée + renvoie le pointeur ; marqueur série **M6D** : AUTOINIT→LibList + round-trip BPTR `rn_Info<<2==&DosInfo` (compute-then-compare, sans déréférencement) + DateStamp ; RED `M6D_BAD_BPTR` isole l'encodage BPTR ; checksum `0x929C804F`). 1er incrément M6.
- **Écran de boot FAIT** (`src/graphics/` : image chaton « KickSlopStart » 352×272×5 = 32 couleurs en overscan, affichée au handoff via l'ABI graphics.library ; `MakeVPort` rendu générique N plans/M couleurs ; marqueur série **M6S** (liveness) + discriminant VISUEL (couleurs uniques : GREEN ~18-19k vs RED one-plane ~36) ; RED `BOOTSCR_ONE_PLANE` isole le rendu multi-bitplane ; pipeline `mk_bootscreen.py` auto-vérifié). ⚠️ Affiché **inconditionnellement** au handoff pour l'instant : le vrai déclencheur « aucun volume bootable » reste à l'incrément strap.
- **Strap (romboot) — routage FAIT (M6r)** puis **lecture+validation+exécution du bootblock FAIT (C/M6y)** (`src/exec/strap.s`). M6r : `strap_boot` route l'affichage insert-disk par sa décision. **C** : `strap_boot` lit maintenant VRAIMENT les secteurs 0+1 de DF0: (`CMD_READ` offset 0 len 1024, via `BeginIO`-30, pattern M6w), valide magic « DOS » + **checksum additif** (somme à retenue circulaire des 256 longs == `$FFFFFFFF` — ADDITIF, pas XOR comme les checksums MFM), puis **saute au boot code à +12** (A6=SysBase, A1=IORequest ; A0 de handoff dos IGNORÉ, pas de dos en C). Bootable → renvoie « bouté » (**M6Y**, pas d'insert-disk) ; checksum invalide (ADF formaté non installé = checksum 0) ou pas de disque → renvoie 0 → insert-disk (**M6R**) = le VRAI déclencheur 1.3. RED `STRAP_FAKE_BOOTDEV` (route sans lire), `STRAP_NO_EXEC` (valide sans sauter → isole l'exécution), `STRAP_BAD_CSUM` (rejette un bon bloc → isole la validation). Preuve : le marqueur **CBOOT** est émis par le bootblock LUI-MÊME → prouve le saut. ADF de test bootable custom régénérable (`tests/mk_boot_adf.sh` + `tests/bootblock_c.s` + `tests/patch_bootblock.py`, round-trip).
- **trackdisk.device — squelette (B1) FAIT** (`src/exec/trackdisk.s` : 2e device, AUTOINIT pri 20 → DeviceList, `Open` valide les unités DF0-3 ; marqueur série **M6T** ; RED `TD_NO_UNITCHECK` isole la validation d'unité). Fondation de la lecture disque.
- **trackdisk lecture de piste brute (B2) FAIT** (`td_read_track0` : la ROM LIT réellement une piste MFM de DF0 via le disk DMA Paula — 22 mots de synchro `$4489` trouvés sur un ADF de test ; marqueur série **M6U** + compte de syncs ; RED `TD_NO_DMA` isole l'armement du DMA ; harness `tests/boot_test.sh` étendu avec une disquette optionnelle en DF0). 1re fois que la ROM accède au matériel disque.
- **trackdisk décodage MFM (B3) FAIT** (`td_decode_track` : 11 secteurs × 512 o décodés+vérifiés, secteur 0 = bootblock « DOS\0 » ; marqueur série **M6V** ; RED `MFM_BAD_DECODE`).
- **trackdisk CMD_READ (B4) FAIT** (`BeginIO` traite `CMD_READ` ; marqueur série **M6W** ; RED `TD_READ_NOCMD`).
- **trackdisk CMD_READ MULTI-PISTE (M6z, prérequis D) FAIT** : `BeginIO` convertit l'offset octet en (piste, secteur) et boucle sur les pistes touchées (traverse les frontières de piste) ; gardes `IOERR_BADLENGTH`/`TD_DISKBYTES`. Preuve série **M6Z** = root block @bloc 880 (piste 80, +0==T_SHORT, +508==ST_ROOT) + lecture spanning blocs 10+11 (marqueurs « SPAN0010 »/« SPAN0011 » à cheval sur la frontière piste 0/1). RED `TD_NOSEEK` (lit toujours la piste 0, sans crash) → M6Z absent (isole le mapping offset→piste).
- **trackdisk seek + side-select (B2b) FAIT** (`td_read_track(n°)` : seek vers une piste arbitraire + side ; prouvé en lisant la piste 2 → secteurs décodés portent track==2 ; marqueur série **M6X** + diagnostic TRACK= ; RED `SEEK_NOSTEP`). **trackdisk.device est maintenant complet** : il lit n'importe quel secteur logique de n'importe quelle piste de DF0.
- **trackdisk — CYLINDER-TRACKING** : `td_read_track` suit le cylindre courant (`TD_CURCYL`/`TD_CYLVALID`) et steppe le **delta** vers la cible (recalibration à 0 seulement si position inconnue) — corrige PROPREMENT le bug « lecture après un seek lisait la mauvaise piste » (le delta ramène la tête au bon cylindre) ET supprime la recalibration 85-pas à chaque lecture (lectures rapides, requis sous l'ordonnanceur). RED `TD_NO_CYLTRACK` (recalibration systématique → D3B absent à WAIT=90). Détection « lecteur absent/vide » via le **timeout DSKRDY** (retour avant le seek). Wiring `CMD_READ` offset→piste multi-piste livré (M6z). Dette : pas d'invalidation sur disk-change (eject/swap réel → recalibration périodique, M7).
- **« Ça boote ! » (C/M6y) FAIT** : cf. la ligne Strap ci-dessus — le strap lit+valide+exécute le bootblock d'un ADF bootable, prouvé par le marqueur **CBOOT** émis par le bootblock. Premier code EXTERNE (disque) exécuté par la ROM.
- **OFS lecture seule (D1) FAIT** (`src/dos/ofs.s` + `ofs.i`) : `ofs_read_file` lit un fichier par nom de DF0: (root → hash → header → chaîne data blocks) via trackdisk `CMD_READ`. Format OFS verrouillé empiriquement. Marqueur série **D1** (taille 1024 + marqueurs @0/@488/@976) ; RED `OFS_NO_DATACHAIN` (taille 488). Machinerie INTERNE (pas de packets).
- **LoadSeg (D2) FAIT** (`src/dos/loadseg.s`) : `dos_loadseg`/`dos_unloadseg` chargent un exécutable hunk depuis l'OFS, appliquent les relocations (RELOC32 $3EC) et bâtissent la seglist BPTR. Format hunk verrouillé empiriquement. Marqueur série **D2LOADSEG** (émis par le code chargé+relocalisé) ; RED `D2_NO_RELOC`. Machinerie INTERNE.
- **dos packets / process / handler (D3) EN COURS** (`src/dos/process.s`, `handler.s`, `dospkt.i`) : **D3a** `proc_create` (Process = Task + `pr_MsgPort` embarqué @0x5C ; port init par le parent, sigbit réservé `DOS_PORTSIG`=8) + round-trip packet (marqueur **D3A**, RED `D3A_NO_REPLY`) ; **D3b** process file-handler DF0: `dos_handler_df0` servant `ACTION_FINDINPUT`/`READ`/`END` via `ofs_read_file`, + helper `dos_sendpkt` (pas de DoPkt public V34) — dos ouvre/lit/ferme un fichier À TRAVERS le handler par packets (marqueur **D3B**, RED `D3B_NO_READ`). Processes prouvés en phase ordonnancée (créés avec les tâches démo). ⚠️ trackdisk CPU-bound → lecture lente sous l'ordonnanceur (WAIT≈280 s) → **cylinder-tracking** = prochain incrément avant D3c.
- **À venir (reste M6)** : **D3c/d** dos `Open`/`Read`/`Close` user-facing (LVO) via packets + `LoadSeg`-sur-packets + run ; puis **E/F** modèle packets BCPL + file-handler DF0: + `CreateProc` + CLI (UN sous-système : DoPkt → process file-handler → CreateProc → CLI). D3 = cœur architectural (checkpoint user avant le modèle packets BCPL). Les prérequis (trackdisk multi-piste M6z, OFS lecture seule D1, LoadSeg D2) sont livrés.
  **M7k reporté** (décision 2026-10-15) : le décodage INTREQR des niveaux INT1/INT4/INT5 n'a aucun consommateur
  réel aujourd'hui (audio=M4+, disk=M6, serial plus tard) -> replié dans le sous-système concerné quand il
  arrivera, avec un vrai consommateur et un vrai test (pas un self-test synthétique jetable).

Voir `docs/PLAN.md` pour la suite et `docs/CLEANROOM.md` pour le mur.
