# amiga_kickstart_reverse — Kickstart 1.3 open-source (A500), méthode salle blanche

Réimplémentation open-source, **clean-room**, d'un Kickstart compatible **AmigaOS 1.3** : image ROM
**256 KiB, 68000, chargée à `$FC0000`**, visant un remplacement « drop-in » de la Kickstart 34.5
(A500/A1000/A2000), bootable d'abord en émulateur puis sur vraie Amiga 500.

## Statut

| Milestone | État |
|-----------|------|
| **M0** — fondations + hello-ROM | ✅ **fait et vérifié** (build `romtool is_kick=ok` + boot FS-UAE écran vert) |
| **M1** — spec de boot (piste analyse) | ✅ fait (4 specs clean-room dans `docs/analysis/`) |
| **M2.0** — exec coldstart + squelette ExecBase | ✅ **fait et vérifié** (boot → écran blanc, auto-vérification ExecBase) |
| **M2.1/M2.2** — jump table LVO V34 (105 vec.), fonctions exec, allocateur + coalescing | ✅ **fait et vérifié** (auto-test via jump table → blanc) |
| **M2.3** — découpage en modules (`src/exec/*.s`) + vlink | ✅ **fait et vérifié** (relink vlink, boot blanc inchangé) |
| **M2.4** — multi-MemHeader, listes (Enqueue…), tâches+signaux+ports (non bloquants) | ✅ **fait et vérifié** (auto-test → blanc ; ordonnancement réel = M3) |
| **M3a** — plomberie d'interruptions (VBlank armé) | ✅ **fait et vérifié** (série « VBlank interrupts live » ; RED→GREEN) |
| **M3b** — ordonnanceur préemptif (switch de tâches superviseur) | ✅ **fait et vérifié** (2 tâches alternent sur le série, contexte préservé) |
| **M3c** — exclusion mutuelle : `Forbid()` honoré par le scheduler + sections critiques exec enveloppées | ✅ **fait et vérifié** (série « M3C LIVE » ; RED garde Forbid → `FAILED`, RED Permit manquant → selftest échoue) |
| **M3d** — `Wait`/`WaitPort` + réveil-sur-signal (switch synchrone, blocage réel d'une tâche) | ✅ **fait et vérifié** (série « M3D LIVE » ; ping-pong 2 ports ; RED réveil cassé → deadlock, RED blocage cassé → `FAILED`) |
| **M3e** — yield immédiat sur `Permit`/`Enable` (reschedule synchrone vers une réveillée prioritaire) | ✅ **fait et vérifié** (série « M3E LIVE » ; démo coopérative pri 10/0 ; RED yield désactivé → starvation franche) |
| **M3f** — recombinaison yield + préemption (switchs unifiés, coexistence sans corruption) | ✅ **fait et vérifié** (série « M3F LIVE » ; 3 tâches `SCHED_ON=1` + sentinelles de contexte ; RED préemption off → starvation) |
| **M4** — scan des résidents (ROMTags) + `FindResident`/`InitResident`/`InitCode` | ✅ **fait et vérifié** (série « M4 RESIDENTS OK » ; 3 résidents démo initialisés en ordre de priorité ; RED tri cassé / dispatch cassé → `FAILED`) |
| **M5a** — AUTOINIT : `MakeLibrary` + `MakeFunctions` + `InitStruct` (chemin AUTOINIT de `InitResident`) | ✅ **fait et vérifié** (série « M5A AUTOINIT OK » ; lib démo créée, jump table + InitStruct + init func + ajout LibList ; RED InitStruct/init cassés → `FAILED`) |
| **M5b** — `cia.resource` (ciaa/ciab) = 1er vrai module résident (direct-init via `MakeLibrary`) | ✅ **fait et vérifié** (série « M5B CIA OK » ; `OpenResource`+`AbleICR`+`AddICRVector` ; RED AddResource/AbleICR cassés → `FAILED`) |
| **M5c** — `timer.device` (AUTOINIT) = 2e vrai résident (1er device) | ✅ **fait et vérifié** (série « M5C TIMER OK » ; créé+nommé+listé DeviceList, Open ; RED nom/Open cassés → `FAILED`) |
| **M6a** — unité VBLANK de `timer.device` fonctionnelle (requête temporisée + répondue par le handler VBlank) | ✅ **fait et vérifié** (série « M6A TIMER OK » ; requête répondue après ~5 ticks + `exec_Signal` depuis l'IRQ ; RED hook/reply coupés → timeout) |
| **M6b** — dispatch d'interruption CIA (INT2/CIA-A : les vecteurs ICR enregistrés se déclenchent) | ✅ **fait et vérifié** (série « M6B CIA INT OK » ; timer CIA-A → INT2 → vecteur ; RED vecteur/activation-chip coupés → timeout) |
| **M7a** — gate de ré-entrance des listes scheduler (IPL7) + unité MICROHZ (CIA-B/INT6) + tâche bloquant sur un timer (Wait→wake) | ✅ **fait et vérifié** (série « M7A TIMER OK » ; task réveillée par l'IRQ MICROHZ sous préemption, `VBL_CLASH==0` ; RED gate retiré → clash « M7A FAILED », RED réveil cassé → tâche figée ; yield re-prouvé en coopératif `SCHED_ON=0`) |
| **M7b** — dispatcher d'interruption par numéro : `IntVects` + `SetIntVector` (vecteur exclusif) + `AddIntServer` (chaîne de serveurs par priorité) ; cia.resource ré-exprimé en serveurs PORTS/EXTER | ✅ **fait et vérifié** (série « M7B PORTS OK » : chaîne 2 serveurs en ordre de priorité ; M7A/M3F toujours OK à travers le dispatcher ; RED serveur-non-ajouté → FAILED, RED vecteur-EXTER-retiré → M7A absent, gate M7a re-prouvé via EXTER) |
| **M7c** — tâches **user-mode** (SR S=0, pile user par tâche) sur **SSP partagée** + **switch différé** (deferred Dispatch à relocalisation de frame) + flag de dispatch différé à la sortie d'IRQ (spec exec) + nesting par-tâche | ✅ **fait et vérifié** (série « M7C USERMODE OK » : user-mode prouvé par lecture SR + N préemptions survécues ; M3F/M7A/M7B toujours OK sur le nouveau modèle ; RED tâches-superviseur → hang, RED relocation-bypass → crash, RED gate-IPL7-retiré → crash ; coopératif SCHED_ON=0 re-prouvé) |
| **M7d** — ports **interrupt-safe** : `PutMsg`/`GetMsg`/`ReplyMsg` passent de Forbid à **Disable** (atomiques vs une interruption qui touche le même `MP_MSGLIST`) | ✅ **fait et vérifié** (série « M7D PORTS OK » : port partagé martelé par une TÂCHE et le service timer **INTERRUPTION** en coexistence avec M3F/M7A/M7C, 4/4 ; RED A/B sous contention max : Forbid → « M7D FAILED » liste corrompue, Disable → propre sur 90 s) |
| **M7e** — fidélité **IPL-par-niveau** : les handlers tournent à leur IPL **natif** (VBlank=3, PORTS=2, EXTER=6) au lieu d'IPL7 uniforme → une source de niveau supérieur préempte le **corps** d'un handler de niveau inférieur ; la section critique du switch est masquée par **IPL7 bref** (écriture SR = instantanée), PAS par INTENA-off (qui a un délai de propagation) | ✅ **fait et vérifié** (série « M7E IPL OK » : INT6 préempte le corps de vbl `VBL_PREEMPT_COUNT>0` ET la chirurgie reste atomique `VBL_CLASH==0` ; GREEN 3/3 ; RED1 `M7E_SURGERY_INTENA=1` surgery en INTENA-off → clash « M7A FAILED » 3/3 ; RED2 `M7E_PROLOGUE_IPL7=1` → « M7E IPL OK » absent 2/2 sans crash ; non-régression coopérative `M7E_COOP=1` `SCHED_ON=0` re-prouvée) |
| **M7f** — **VERTB en chaîne de serveurs** : le `vbl_handler` dédié devient `int3_dispatch` générique → `intr_dispatch_number(VERTB)` → chaîne de serveurs par priorité (modèle UNIFORME PORTS/VERTB/EXTER). Le quantum round-robin devient `sched_server` (pose `AttnResched`, consommé par `intr_isr_defer`) ; `timer.device` enregistre son service VBLANK via `AddIntServer` au lieu du hook `VBL_SVC` | ✅ **fait et vérifié** (série « M7F VERTB OK » : `VERTB_CHAIN_N` prouve que le walker parcourt sched(pri 20)+timer(0)+tail(-10) en ordre, scheduler ET timer OK à travers la chaîne ; GREEN 3/3, 0 FAILED ; RED `M7F_SCHED_STOPS_CHAIN=1` → sched retourne Z-clair → chaîne stoppée → timer_vblank mort → « M6A FAILED: timer VBLANK unit incorrect » 2/2 ; non-régression M3f + coopérative `M7E_COOP=1` + M7a/c/d/e re-prouvés). Découverte : retirer le seul quantum VBlank ne stoppe PAS la préemption — INT6 co-pilote le round-robin (tout dispatch différé requeue la sortante) |
| **M7g** — **décodage INTREQR multi-source** : `int3_dispatch` lit `INTREQR & INTENAR` et dispatche+acke **chaque** source de niveau 3 en attente (COPER bit4 / VERTB bit5 / BLIT bit6) via `IntVects[n]`, au lieu de supposer VERTB seule. int2(PORTS)/int6(EXTER) restent mono-source (leur niveau n'a qu'une source) | ✅ **fait et vérifié** (série « M7G MULTISRC OK » : une 2e source de niveau 3, COPER, déclenchée par logiciel `INTREQ=SETCLR\|COPER`, est servie `COPER_FIRED>0` via le décodage (int3 sert CHAQUE source niveau 3 en attente, plus seulement VERTB ; co-pending sur un même INT3 non isolé — seul le per-source séquentiel est prouvé) ; GREEN 3/3, 0 FAILED ; RED `M7G_MONO_SOURCE=1` → COPER ackée mais NON dispatchée → « M7G » absent, `COPER_FIRED` figé, reste identique sans storm 2/2 ; bonus : sur un INT3 spurious, aucun dispatch (plus correct que M7f) ; non-régression M3f + coopérative + M7a..M7f re-prouvés) |
| **M7h** — **quantum réel** : `sched_server` préempte après `M7H_QUANTUM` ticks (défaut 4, comme exec) au lieu de chaque tick ; `QUANTUM_ELAPSED` compté par tick, reset sur changement réel de tâche (`dispatch_in`). La priorité stricte était déjà correcte (RemHead/Enqueue par pri) → M7h = quantum seul | ✅ **fait et vérifié** (observable SEULEMENT en isolation : la découverte M7f fait qu'INT6 reset `ELAPSED` ~140/s en démo normale → quantum quasi-no-op là, non-régression M3F..M7G 3/3 ; démo d'isolation `M7H_QUANTUM_DEMO=1` = 2 spinners pri 0, rotation pilotée uniquement par le quantum → « M7H QUANTUM OK » quand `QUANTUM_EXPIRE_N*2 < VBL_COUNT` 2/2 ; RED `M7H_QUANTUM=1` → rotation chaque tick → « M7H » absent 2/2 ; coopérative) |
| **M7i** — **`timer_reply`→`ReplyMsg`** : la routine de réponse bespoke (M7c, créée pour éviter le `Permit`/yield de `ReplyMsg` en interruption) est supprimée ; les services VBLANK/MICROHZ appellent directement `ReplyMsg`, devenu interrupt-safe en M7d (Disable/`raw_enable`, sans tail reschedule). Consolidation : un cas spécial de moins | ✅ **fait et vérifié** (équivalence : jeu de marqueurs IDENTIQUE à M7h défaut — M3F/M6A/M7A/M7C/M7D/M7E/M7F/M7G, 0 FAILED, GREEN 3/3 + coopérative ; le timer réveille toujours task_timer via `ReplyMsg` ; justification inversée corrigée dans les commentaires/docs) |
| **M7j** — **`RemTask`** (cycle de vie des tâches) : `RemTask(task)` retire une tâche et libère sa pile + TCB. **Self-removal** (`RemTask(NULL/ThisTask)`, le cas « tâche terminée » via `task_exit`) : `trap #2` → superviseur → sur la SSP la pile user n'est plus utilisée → `FreeMem` pile+TCB (Permit interne de FreeMem neutralisé par un `Forbid` externe) → bascule sur la suivante (`dispatch_in`, ne revient pas). Non-self : `Remove` + `FreeMem` en contexte tâche | ✅ **fait et vérifié** (série « M7J REMTASK OK » : task_rm tourne N fois puis RTS → `task_exit` → `RemTask(self)` ; une tâche survivante confirme qu'`AvailMem` remonte de ≥ pile+TCB ; GREEN 2/2 + non-régression défaut M3F..M7G 3/3 + coopérative ; RED `M7J_NOFREE=1` → `FreeMem` sauté → `AvailMem` ne remonte pas (fuite) → « M7J » absent 2/2, sans crash). Non-self RemTask par-inspection ; `tc_MemEntry` hors scope |
| **M7l** — **calibration µs réelle MICROHZ** : `timer_beginio` sépare la conversion par unité et compte l'unité MICROHZ en **interruptions CIA-B** (`US_PER_INT`=359 µs/int, `INTS_PER_SEC`=2782 ; E-clock PAL 709379 Hz, latch 255) au lieu du facteur VBLANK `/20000` → `TV_MICRO` = **µs réelles** (résolution ~360 µs) | ✅ **fait et vérifié** (série « M7L MICROHZ CALIB OK » : preuve **inter-horloges** non tautologique — une requête MICROHZ de 0,5 s s'écoule en ~25 ticks **VBLANK** (horloge display indépendante), elapsed ∈ [22,28] ; GREEN 3/3, 0 FAILED ; RED `M7L_OLD_CONV=1` → conversion VBLANK rétablie sur MICROHZ → requête trop rapide (~0-1 tick) → « M7L » absent, M3F..M7G verts 2/2, chirurgical via `TT_MICRO_REQ` gaté ; coop : non-régression de tous les marqueurs antérieurs — M7L est une preuve du build par défaut, la latence de réveil coopératif gonfle la fenêtre mesurée hors bande, artefact confirmé bénin). Résolution sub-interruption + unité ECLOCK différées |
| **M4a** — **premier affichage piloté par le Copper** : `src/graphics/gfx.s` alloue une copper list en **chip RAM** (le Copper ne lit QUE la chip, pas la ROM), pose la fenêtre display + 0 bitplane + `COLOR00` = vert, active `DMACON` COPEN → écran **vert** permanent. 1er jalon où le canal **VISUEL** est le livrable | ✅ **fait et vérifié** (écran VERT via `FRAC(00FF00)`=0.67, le vert n'étant AUCUNE couleur CPU → vert ⟺ Copper DMA ; GREEN 3/3 + non-rég série M3F..M7L ; RED `M4A_NO_COPPER=1` → pas de COPEN → écran **blanc** → vert absent `FRAC`=0, série identique 2/2, chirurgical ; coop : écran vert, non-rég. A corrigé un bug du discriminant couleur de `tests/boot_test.sh`) |
| **M4b** — **pixels bitplane pilotés Copper** : +1 bitplane 320×256 en **chip RAM** rempli de rayures verticales (`$FF00`), `BPL1PT` patché dans la copper list au runtime, `DMACON` RASTER, `COLOR00`=bleu/`COLOR01`=vert → **rayures vertes** à l'écran (vrais pixels fetchés depuis le bitmap) | ✅ **fait et vérifié** (rayures vertes `FRAC(00FF00)`≈0.30 ⟺ bitplane DMA ; GREEN 3/3 + non-rég M3F..M7L ; RED `M4B_NO_BITPLANE=1` → BPU=0 + pas de RASTER → **bleu uni** → vert absent `FRAC`=0, série identique 2/2 ; coop rayures. 3 états de gate : blanc/bleu-uni/bleu+rayures) |
| **M4c1** — **squelette résident `graphics.library`** : 1er vrai module LIBRARY (ROMTag AUTOINIT pri 65 → `MakeLibrary` → `LibList`, 1re fois que la branche `NT_LIBRARY`→LibList est exercée). GfxBase + Open/Close ; fonctions d'affichage en M4c2 | ✅ **fait et vérifié** (`FindName(LibList,"graphics.library")`+Open → « M4C1 GFX LIB OK » comme M5c timer ; RED `M4C1_WRONG_TYPE=1` → `RT_TYPE`=NT_DEVICE → routé DeviceList → M4C1 absent, FRAC inchangé 0.30 ; coop OK. Non-rég = l'insertion d'un résident pri-65 ne décale rien : FRAC reste 0.30 + M3F..M7L) |
| **M4c2+** — moteur d'affichage graphics.library (MakeVPort/MrgCop/LoadView), intuition, dos/trackdisk | à venir (voir `docs/PLAN.md`). **M7k reporté** : décodage INTREQR INT1/4/5 = plomberie sans consommateur réel (audio=M4, disk=M6, serial plus tard) → replié dans son sous-système le moment venu |

## ⚠️ Légal / clean-room

Ce dépôt **n'inclut pas** et **ne distribue pas** la Kickstart propriétaire. Pour l'analyse et les
tests oracle, place **ta propre copie** de `kick34005.A500` (256K, md5 `82a21c18…`) dans `assets/`
(fichier gitignoré). La méthode salle blanche est décrite dans `docs/CLEANROOM.md` : le désassemblage
ne sert qu'à **comprendre et tester** ; le code publié s'écrit **uniquement** depuis des docs
publiques (RKRM / NDK / `.fd`) + AROS (référence lecture seule).

## Build & test (hello-ROM M0)

Prérequis : `vasmm68k_mot` + `vlink` dans le PATH, **amitools** (`romtool`), `python3`, **FS-UAE** + **Xvfb**.

```sh
make                  # -> build/kick13.rom  (ROM principale : exec coldstart)
make verify           # taille 256K + romtool is_kick=ok
tests/boot_test.sh    # boot headless FS-UAE ; assertion sur le LOG SÉRIE (marqueur
                      #   « self-test passed ») capturé via un pont PTY socat ;
                      #   repli couleur si aucune émission série. -> build/boot/serial.log
make hello            # -> build/kick13-hello.rom (smoke test M0)
tests/boot_test.sh build/kick13-hello.rom 10 00FF00 HELLO   # test hello (marqueur « HELLO »)
```

Le log série émet des **checkpoints** (`chk core` → `chk mem` → `chk m24a/b/c` →
`self-test passed`) : en cas d'échec, le dernier checkpoint capturé localise le groupe fautif.
Prérequis supplémentaire pour le série : `socat`.

Installation de la toolchain (vasm/vlink se compilent depuis les sources) : voir `docs/HARDWARE.md`.

## Arborescence

```
src/            implémentation (piste CLEAN) — src/exec/ : exec.library modulaire (exec.i + boot/lists/memory/library.s + kick.ld) · src/rom/ : hello-ROM (start.s) + mkrom.py
docs/           PLAN.md · CLEANROOM.md · ARCHITECTURE.md · HARDWARE.md · analysis/ (piste DIRTY)
tests/          harness émulateur (boot_test.sh)
assets/         TA copie de la ROM (gitignorée, lecture seule)
build/          artefacts (gitignoré)
third_party/    AROS en référence lecture seule (non vendoré pour l'instant)
```
