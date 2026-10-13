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
| `src/exec/` | exec.library, découpée en modules reliés par vlink : `exec.i` (constantes/ABI), `boot.s` (en-tête/reset, coldstart, ExecBase, init_task, publish, selftest), `lists.s` (listes + Enqueue/Insert/RemHead/RemTail), `memory.s` (AllocMem/FreeMem multi-header, AvailMem, TypeOfMem), `library.s` (Open/Close/Forbid…/Disable…, jump table), `tasks.s` (AddTask, FindTask, signaux, Signal réveillant les tâches bloquées, SetTaskPri), `ports.s` (AddPort/PutMsg/GetMsg/ReplyMsg/WaitPort…, sections critiques Forbid-enveloppées), `interrupts.s` (init_ints + handler VBlank honorant Forbid/Disable + Wait = switch synchrone) ; script linker `kick.ld` |
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
- **À venir (M3d+)** : **yield immédiat sur Permit** (soft-trigger VERTB) — requis dès qu'une tâche
  réveillée **prioritaire** doit tourner sans attendre un tick ; aujourd'hui une réveillée part en
  `TaskReady` et tourne au prochain switch (correct en round-robin, lacune de latence sous priorité).
  Puis : dispatcher par niveau (`INTREQR`/`IntVects`/`SetIntVector`/`AddIntServer`), **upgrade des
  ports en Disable** (dès qu'un device piloté par IRQ appelle `PutMsg`/`ReplyMsg`), save/restore
  par-TCB du nesting + `Wait`, tâches user-mode (frame USP/SSP), `RemTask`, quantum `SFB_TQE`,
  priorité réelle, puis `InitResident` + scan des résidents → `cia.resource`/`timer.device`.

Voir `docs/PLAN.md` pour la suite et `docs/CLEANROOM.md` pour le mur.
