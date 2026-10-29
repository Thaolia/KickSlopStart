# coverage-v34.md — Coverage inventory of the analysis documentation (Kickstart 1.3 / V34)

> ANALYSIS track ("dirty"). This document describes no new behaviour: it **inventories** what
> `docs/analysis/*.md` already specifies, what `src/` implements, and measures in the official ROM
> (`kick34005.A500`, radare2, read only) an **effort indicator** (size in bytes) for each
> function. No ROM instruction, no listing, no routine address appears in it: only
> public ABI names (`.fd`), LVOs, command numbers, counts and sizes.
> State as of 2026-10-27 (repository at commit `15b9e8f`).

## 0. Summary in figures

- **390 V34 LVOs** inventoried across the 13 modules that expose functions (of which **14 private** in the
  sense of the `.fd`s: 9 exec, 2 graphics, 2 dos, 1 expansion); **376 public**.
- Coverage by the analysis documentation: **73 specified** (18.7 %), **73 partial** (18.7 %), **123 only
  cited** as calls made by an analysed piece of software (31.5 %), **121 absent** from any spec (31.0 %).
  Useful coverage (specified + partial): **146 / 390 = 37.4 %**.
- Implementation on our side (vector tables of `src/`): **327 / 390 = 83.8 %** have a dedicated routine;
  **6** are stubs (constant return); **57** point to a null vector or fall **outside the table**.
- Device commands inventoried in addition: 80 (keyboard 14, gameport 14, input 17, console 13,
  trackdisk 22), plus timer (3) and audio (15) described globally.
- The four least covered areas, in bytes of unspecified ROM code: **graphics** (≈ 48 KB
  reached from its vectors, 0 function specified), **intuition** (≈ 42 KB, input engine, menus,
  screens), **layers** (≈ 13 KB, stack operations), **console.device** (≈ 5.5 KB, nothing specified).

| Module | V34 LVOs | Specified | Partial | Cited | Absent | Implemented (dedicated routine) | ROM bytes reached from the vectors |
|---|--:|--:|--:|--:|--:|--:|--:|
| exec | 101 | 14 | 15 | 38 | 34 | 90 | 6,778 |
| graphics | 105 | 0 | 12 | 51 | 42 | 78 | 48,346 |
| intuition | 74 | 17 | 14 | 28 | 15 | 58 | 42,590 |
| layers | 25 | 3 | 8 | 6 | 8 | 22 | 12,776 |
| dos | 33 | 15 | 18 | 0 | 0 | 29 | n/m (BCPL) |
| expansion | 21 | 21 | 0 | 0 | 0 | 21 | 1,710 |
| mathffp | 12 | 0 | 0 | 0 | 12 | 12 | 1,042 |
| timer (fonctions) | 3 | 3 | 0 | 0 | 0 | 3 | 360 (device entier) |
| console (fonctions) | 2 | 0 | 1 | 0 | 1 | 1 | 3,658 (vecteurs) + 1,878 (commandes) |
| cia.resource | 4 | 0 | 3 | 0 | 1 | 3 | 256 |
| disk.resource | 5 | 0 | 2 | 0 | 3 | 5 | 234 |
| potgo.resource | 3 | 0 | 0 | 0 | 3 | 3 | 178 |
| misc.resource | 2 | 0 | 0 | 0 | 2 | 2 | 68 |
| **Total** | **390** | **73** | **73** | **123** | **121** | **327** | |

## 1. Method (reproducible)

**List of the LVOs.** amitools `.fd` files (`amitools/data/fd/` of the pipx installation) for exec,
dos, graphics, intuition, mathffp and timer, **truncated at the first "functions in V36 or
higher" marker** (the "V33 or higher" entries are kept). For layers, expansion, console (functions),
cia, disk, potgo and misc, absent from amitools: lists from the public NDK `.fd`s (`##bias 30`, 42 or 6
depending on the module). Each list was **cross-checked against the number of entries of the real
vector table** read in the ROM: exec 105 (= 4 + 101), graphics 109 (= 4 + 105), intuition 78 (= 4 + 74),
layers 29 (= 4 + 25), expansion 25, mathffp 16, timer 9 (= 6 + 3), console 8 (= 6 + 2), cia 4, disk 5,
potgo 3, misc 2. All agree. keymap.resource has **no** function table in V34 (its init
allocates the structure, initialises its list and adds it by AddResource, without MakeFunctions) → 0 LVOs.
dos builds its vectors differently (BCPL bridge, cf. `bcpl-runtime-v34.md` §1.4): its table has not been
located and its sizes are not measured.

**Coverage.** Search for each name (whole word) in `docs/analysis/*.md`, then reading of the passages.
Levels:
- **yes**: a section describes the V34 behaviour of the function (contract, effects, return values);
- **partial**: one aspect of the contract is established (format, side effect, register convention, defect
  fixed by SetPatch…) in passing within another spec;
- **cited**: the function only appears as a call made by an analysed piece of software (no behaviour of the
  ROM described) — counts as **not covered**;
- **no**: no mention.

**Implementation on our side.** Reading of the vector tables of `src/` (and of the filling of the exec jump
table in `src/exec/library.s`): **yes** = dedicated routine (does not guarantee completeness);
**stub** = body of 1–2 instructions returning a constant; **no (null vector)** = points to the module's
"not implemented" routine; **absent (outside the table)** = LVO beyond the end of our table. For the
device commands: reading of the `BeginIO` dispatches.

**Size in the official ROM.** radare2 6.1.3 (`-a m68k -b 32`, base `$FC0000`). The entry points
are read in the ROM's vector tables (and in the devices' command tables); each
entry is analysed as a function, then its direct callees are in turn (closure limited to the
module's ROM area). Two numbers:
- **own**: bytes of basic blocks reachable from THIS entry and from no other entry of the
  same module (= work specific to the function);
- **closure**: all the bytes reachable from the entry within the module's area (includes the shared
  engine: for a thin intuition or layers vector, it is the closure that measures the real effort).
- **ROM stub**: first word = immediate return, or "constant in D0 then return", or closure ≤ 4 bytes.

Limits: indirect calls (via `A6`, internal jump tables) are not followed; the sizes are
**orders of magnitude** (±20 %), not exact counts. The priorities are a proposal:
**P1** = absent/stub on our side **and** used by known software, or real hardware risk;
**P2** = implemented without a spec and bulky (closure ≥ 300 b) or semi-private still called;
**P3** = small, AutoDoc contract sufficient, obsolete or private; **—** = already specified (or out of scope).

## 2. The 24 residents of the ROM

ROM area = distance between the module's ROMTag and the next ROMTag in the ROM (code + data; for
keymap/keyboard/gameport/input, whose ROMTags are grouped, the code lives in the area following the
ROMTag of console.device: 14,196 shared bytes, split by closure indicated).

| # | Resident | ROM area (b) | Analysis coverage | Existing specs | On our side | Priority |
|--:|---|--:|---|---|---|:-:|
| 1 | exec.library 34.2 | 12,736 | partial: ExecBase ABI, jump table, boot order, memory/lists/exclusion at AutoDoc level | exec-spec, boot-sequence, test-vectors, module-map | `src/exec/*` (90/101 LVO) | P1 |
| 2 | expansion.library 34.1 | 2,176 | **complete** | autoconfig-v34 | `src/exec/expansion.s` | — |
| 3 | potgo.resource | 332 | none | — | `src/exec/potgo.s` | P2 |
| 4 | keymap.resource | 74 (+ init and tables in the console area) | none (structure without LVO) | — | `src/exec/keymap.s` (exposes 2 vectors that do not exist in V34) | P2 |
| 5 | cia.resource (ciaa/ciab) | 648 | partial: timer allocation, ICR | timer-v34 §1, §6 ; keyboard-handshake §1–§2 | `src/exec/cia.s` (SetICR = stub) | P2 |
| 6 | disk.resource | 872 | partial: GetUnit/GiveUnit (as seen by SetPatch) | setpatch-disk-resource, setpatch-138 §1.7 | `src/exec/diskres.s` | P1 |
| 7 | misc.resource | 268 | none | — | `src/exec/misc.s` | P2 |
| 8 | ramlib.library | 1,564 | none (cited at boot) | boot-sequence, dos-boot-sequence | `src/exec/ramlib.s` (without its own process) | P2 |
| 9 | graphics.library 34.1 | 59,816 | **very weak**: contracts deduced from callers | fastfonts-ff, caesar-boot, monkey-startup, octamed | `src/graphics/*` (78/105, table too short) | P1 |
| 10 | keyboard.device | common area (≈ 1.1 KB by closure) | partial: reception, reset | keyboard-handshake | `src/exec/kbddev.s`, `keyboard.s` | P1 (hardware) |
| 11 | gameport.device | common area (≈ 1.2 KB) | none | — | `src/exec/gameport.s` (BeginIO refuses everything) | P1 |
| 12 | timer.device 34.1 | 2,040 | **complete** | timer-v34 | `src/exec/timer.s` | — |
| 13 | audio.device 34.1 | 4,204 | none | — | `src/exec/audio.s` | P2 |
| 14 | input.device | common area (≈ 0.8 KB) | partial: repeat, thresholds, handler chain | intuiticks-repeat, disk-change §3 | `src/exec/input.s` | P2 |
| 15 | layers.library 34.1 | 13,312 | partial: InstallClipRegion, Begin/EndUpdate, locks | installclipregion, wb-icon-clipping, intuition-gzz | `src/graphics/layers.s` | P1 |
| 16 | console.device | common area (≈ 5.5 KB) | **almost none** | handlers-v34 §2 (CON: side) | `src/exec/console.s` (READ/WRITE only) | P1 |
| 17 | trackdisk.device 34.1 | 6,908 | partial: reading and timing, disk change | trackdisk-official-timing, disk-change | `src/exec/trackdisk.s` | P2 (writing: other agent) |
| 18 | intuition.library 34.3 | 52,248 | partial: requesters, prefs, frame, GZZ, prop | intuition-* | `src/intuition/*` (58/74) | P1 |
| 19 | alert.hook | 658 | none (cited) | boot-sequence, module-map | absent (Alert = serial message) | P1 |
| 20 | mathffp.library | 1,324 | none | — | `src/exec/mathffp.s` | P3 |
| 21 | workbench.task 34.1 | 35,302 | **strong** | workbench-task, wb-icon-clipping, disk-change §4, loadwb-13 | `src/dos/workbench.s` | — |
| 22 | dos.library 34.3 | 49,542 | **strong** | dos-v34-spec, bcpl-runtime, handlers, fault, boot-clock, disk-full-write | `src/dos/*` | — |
| 23 | romboot.library | 1,052 | partial | uae-hd-boot §2 | `src/exec/romboot.s` | P3 |
| 24 | strap 34.4 | 2,444 | partial (DF0: attempt, RomBoot) | uae-hd-boot §3, boot-sequence | `src/exec/strap.s` | P3 (coldstart: other agent) |

## 3. Tables per module (public functions)

### exec.library (101 LVOs, −30 to −630)

| LVO | Function | Specified? (file §) | Implemented on our side | ROM size (own / closure) | Priority |
|---:|---|---|---|---|:-:|
| -30 | `Supervisor` | partial — setpatch-138 §1.5 | yes | 14 / 14 | P3 |
| -36 | `execPrivate1` (= `ExitIntr`) *(private)* | no | no (null vector) | 124 / 162 | P2 |
| -42 | `execPrivate2` (= `Schedule`) *(private)* | no | no (null vector) | 4 / 4 (ROM stub) | P2 |
| -48 | `execPrivate3` (= `Reschedule`) *(private)* | no | no (null vector) | 48 / 48 | P2 |
| -54 | `execPrivate4` (= `Switch`) *(private)* | no | no (null vector) | 204 / 312 | P2 |
| -60 | `execPrivate5` (= `Dispatch`) *(private)* | no | no (null vector) | 18 / 18 | P2 |
| -66 | `execPrivate6` (= `Exception`) *(private)* | no | no (null vector) | 108 / 108 | P2 |
| -72 | `InitCode` | yes — boot-sequence §Phase 4 | yes | 56 / 56 | — |
| -78 | `InitStruct` | partial — module-map §Auto-init structures | yes | 74 / 74 | P3 |
| -84 | `MakeLibrary` | partial — boot-sequence §Phase 4 ; module-map §Auto-init structures | yes | 138 / 192 | P3 |
| -90 | `MakeFunctions` | partial — module-map §Auto-init structures (table format) | yes | 54 / 54 | P3 |
| -96 | `FindResident` | partial — dos-boot-sequence §Phase A | yes | 48 / 48 | P3 |
| -102 | `InitResident` | yes — boot-sequence §Phase 4 | yes | 88 / 88 | — |
| -108 | `Alert` | partial — setpatch-138 §1.3 ; intuition-requesters §5.3 | yes | 1264 / 1846 | P1 |
| -114 | `Debug` | no | no (null vector) | 10 / 10 | P3 |
| -120 | `Disable` | yes — exec-spec §4 Mutual exclusion | yes | 14 / 14 | — |
| -126 | `Enable` | yes — exec-spec §4 Mutual exclusion | yes | 16 / 16 | — |
| -132 | `Forbid` | yes — exec-spec §4 Mutual exclusion | yes | 6 / 6 | — |
| -138 | `Permit` | yes — exec-spec §4 Mutual exclusion | yes | 20 / 20 | — |
| -144 | `SetSR` | no | yes | 12 / 12 | P3 |
| -150 | `SuperState` | no | yes | 12 / 12 | P3 |
| -156 | `UserState` | partial — setpatch-138 §1.5 | yes | 10 / 10 | P3 |
| -162 | `SetIntVector` | cited — cracktros-exit §2 | yes | 70 / 70 | P2 |
| -168 | `AddIntServer` | cited — monkey-startup §2 ; sysinfo-44 §S2 | yes | 64 / 102 | P2 |
| -174 | `RemIntServer` | cited — sysinfo-44 §2.3 | yes | 72 / 86 | P2 |
| -180 | `Cause` | cited — keyboard-handshake §5 | yes | 96 / 96 | P2 |
| -186 | `Allocate` | no | yes | 82 / 82 | P3 |
| -192 | `Deallocate` | no | yes | 236 / 318 | P2 |
| -198 | `AllocMem` | yes — exec-spec §4 Memory management | yes | 236 / 318 | — |
| -204 | `AllocAbs` | cited — setpatch-138 §1.1 | yes | 144 / 144 | P3 |
| -210 | `FreeMem` | yes — exec-spec §4 Memory management | yes | 64 / 382 | — |
| -216 | `AvailMem` | yes — exec-spec §4 Memory management | yes | 78 / 78 | — |
| -222 | `AllocEntry` | partial — setpatch-138 §1.4 | yes | 142 / 142 | P3 |
| -228 | `FreeEntry` | partial — setpatch-138 §Requirements | yes | 62 / 62 | P3 |
| -234 | `Insert` | cited — workbench-task §3.6 | yes | 60 / 60 | P3 |
| -240 | `AddHead` | yes — exec-spec §4 Doubly linked lists | yes | 60 / 60 | — |
| -246 | `AddTail` | yes — exec-spec §4 Doubly linked lists | yes | 24 / 24 | — |
| -252 | `Remove` | yes — exec-spec §4 Doubly linked lists | yes | 14 / 14 | — |
| -258 | `RemHead` | cited — uae-hd-boot §4.1 | yes | 16 / 16 | P3 |
| -264 | `RemTail` | cited — workbench-task §3.1 | yes | 22 / 22 | P3 |
| -270 | `Enqueue` | yes — exec-spec §4 Doubly linked lists | yes | 38 / 38 | — |
| -276 | `FindName` | yes — exec-spec §4 Doubly linked lists ; setpatch-138 §1.6 | yes | 40 / 40 | — |
| -282 | `AddTask` | partial — workbench-task §1.3 (initial frame) | yes | 164 / 202 | P3 |
| -288 | `RemTask` | partial — bcpl-runtime §8.4.2, §13.7 | yes | 122 / 136 | P3 |
| -294 | `FindTask` | cited — loadwb-13 §1 | yes | 84 / 84 | P3 |
| -300 | `SetTaskPri` | cited — workbench-task §2.2 | yes | 80 / 132 | P3 |
| -306 | `SetSignal` | cited — handlers-v34 §3.6 | yes | 8 / 8 | P3 |
| -312 | `SetExcept` | no | yes | 156 / 194 | P3 |
| -318 | `Wait` | cited — exec-spec §3 | yes | 104 / 104 | P3 |
| -324 | `Signal` | cited — handlers-v34 §3.6 | yes | 20 / 20 | P3 |
| -330 | `AllocSignal` | cited — workbench-task §3.1 | yes | 56 / 56 | P3 |
| -336 | `FreeSignal` | no | yes | 16 / 16 | P3 |
| -342 | `AllocTrap` | no | yes | 38 / 38 | P3 |
| -348 | `FreeTrap` | no | yes | 16 / 16 | P3 |
| -354 | `AddPort` | cited — preferences-13 §4 | yes | 24 / 24 | P3 |
| -360 | `RemPort` | cited — fastfonts-ff §2 | yes | 4 / 32 | P3 |
| -366 | `PutMsg` | cited — dos-v34-spec §2a | yes | 6 / 122 | P3 |
| -372 | `GetMsg` | cited — dos-v34-spec §2a | yes | 46 / 46 | P3 |
| -378 | `ReplyMsg` | cited — dos-v34-spec §2a | yes | 26 / 142 | P3 |
| -384 | `WaitPort` | cited — dos-v34-spec §2a | yes | 40 / 40 | P3 |
| -390 | `FindPort` | cited — preferences-13 §4 | yes | 10 / 10 | P3 |
| -396 | `AddLibrary` | no | yes | 14 / 148 | P3 |
| -402 | `RemLibrary` | no | yes | 26 / 26 | P3 |
| -408 | `OldOpenLibrary` | cited — fastfonts-ff §Provenance | yes | 8 / 8 | P3 |
| -414 | `CloseLibrary` | cited — caesar-boot §1 | yes | 20 / 20 | P3 |
| -420 | `SetFunction` | partial — fastfonts-ff §1, §3 (returned value) | yes | 30 / 114 | P3 |
| -426 | `SumLibrary` | partial — test-vectors §G | yes | 84 / 84 | P3 |
| -432 | `AddDevice` | cited — timer-v34 §1.1 | yes | 14 / 64 | P3 |
| -438 | `RemDevice` | no | yes | 26 / 26 | P3 |
| -444 | `OpenDevice` | cited — dos-boot-sequence §Phase D | yes | 78 / 118 | P3 |
| -450 | `CloseDevice` | cited — handlers-v34 §3.6 | yes | 22 / 22 | P3 |
| -456 | `DoIO` | cited — bcpl-runtime §8.4.2 | yes | 114 / 114 | P3 |
| -462 | `SendIO` | cited — handlers-v34 §3.6 | yes | 18 / 18 | P3 |
| -468 | `CheckIO` | partial — intuition-requesters §7.1 | yes | 28 / 28 | P3 |
| -474 | `WaitIO` | cited — intuition-requesters §7.1 | yes | 114 / 114 | P3 |
| -480 | `AbortIO` | cited — intuiticks-repeat §2.1 | yes | 14 / 14 | P3 |
| -486 | `AddResource` | cited — uae-int2 §2.2 | yes | 8 / 8 | P3 |
| -492 | `RemResource` | no | yes | 4 / 32 | P3 |
| -498 | `OpenResource` | cited — setpatch-disk-resource §1 | yes | 18 / 58 | P3 |
| -504 | `execPrivate7` (= `RawIOInit`) *(private)* | no | stub (constant return) | 10 / 10 | P3 |
| -510 | `execPrivate8` (= `RawMayGetChar`) *(private)* | no | yes | 32 / 32 | P3 |
| -516 | `execPrivate9` (= `RawPutChar`) *(private)* | no | yes | 70 / 120 | P3 |
| -522 | `RawDoFmt` | cited — workbench-task §3.4 | yes | 214 / 452 | P2 |
| -528 | `GetCC` | no | yes | 8 / 8 | P3 |
| -534 | `TypeOfMem` | no | yes | 38 / 38 | P3 |
| -540 | `Procure` | no | no (null vector) | 22 / 22 | P3 |
| -546 | `Vacate` | no | no (null vector) | 34 / 34 | P3 |
| -552 | `OpenLibrary` | cited — caesar-boot §1 ; dos-boot-sequence | yes | 46 / 86 | P3 |
| -558 | `InitSemaphore` | cited — autoconfig-v34 §1 | yes | 32 / 32 | P3 |
| -564 | `ObtainSemaphore` | cited — autoconfig-v34 §7 | yes | 80 / 104 | P3 |
| -570 | `ReleaseSemaphore` | cited — autoconfig-v34 §7 | yes | 100 / 116 | P3 |
| -576 | `AttemptSemaphore` | no | yes | 48 / 48 | P3 |
| -582 | `ObtainSemaphoreList` | no | yes | 118 / 142 | P3 |
| -588 | `ReleaseSemaphoreList` | no | yes | 22 / 22 | P3 |
| -594 | `FindSemaphore` | no | yes | 10 / 10 | P3 |
| -600 | `AddSemaphore` | no | yes | 12 / 12 | P3 |
| -606 | `RemSemaphore` | no | yes | 4 / 32 | P3 |
| -612 | `SumKickData` | no | no (null vector) | 88 / 88 | P2 |
| -618 | `AddMemList` | partial — autoconfig-v34 §4 | yes | 84 / 134 | P3 |
| -624 | `CopyMem` | cited — autoconfig-v34 §6 | yes | 38 / 112 | P3 |
| -630 | `CopyMemQuick` | no | yes | 4 / 78 | P3 |

### graphics.library (105 LVOs, −30 to −654)

| LVO | Function | Specified? (file §) | Implemented on our side | ROM size (own / closure) | Priority |
|---:|---|---|---|---|:-:|
| -30 | `BltBitMap` | cited — installclipregion §3.2 | yes | 406 / 1680 | P1 |
| -36 | `BltTemplate` | partial — fastfonts-ff §2 (expected contract) | yes | 692 / 1864 | P2 |
| -42 | `ClearEOL` | no | yes | 56 / 120 | P3 |
| -48 | `ClearScreen` | no | yes | 66 / 130 | P3 |
| -54 | `TextLength` | cited — intuition-frame §3.2 | yes | 96 / 96 | P3 |
| -60 | `Text` | partial — fastfonts-ff §1–§4 | yes | 1028 / 1288 | P2 |
| -66 | `SetFont` | cited — fastfonts-ff §2 | yes | 28 / 28 | P3 |
| -72 | `OpenFont` | cited — fastfonts-ff §Command-line options | yes | 170 / 170 | P3 |
| -78 | `CloseFont` | cited — intuition-prefs §3.3 | yes | 30 / 30 | P3 |
| -84 | `AskSoftStyle` | partial — setpatch-138 §1.9 | yes | 36 / 36 | P3 |
| -90 | `SetSoftStyle` | partial — setpatch-138 §1.9 | yes | 50 / 50 | P3 |
| -96 | `AddBob` | cited — workbench-task §3.6 | yes | 14 / 116 | P3 |
| -102 | `AddVSprite` | no | yes | 14 / 88 | P3 |
| -108 | `DoCollision` | no | yes | 1330 / 1824 | P2 |
| -114 | `DrawGList` | cited — workbench-task §3.6 | yes | 3098 / 6552 | P2 |
| -120 | `InitGels` | cited — workbench-task §3.1 | yes | 122 / 122 | P3 |
| -126 | `InitMasks` | no | yes | 12 / 246 | P3 |
| -132 | `RemIBob` | cited — workbench-task §3.6 | yes | 70 / 3166 | P2 |
| -138 | `RemVSprite` | no | yes | 12 / 32 | P3 |
| -144 | `SetCollision` | no | yes | 42 / 42 | P3 |
| -150 | `SortGList` | cited — workbench-task §3.6 | yes | 190 / 190 | P3 |
| -156 | `AddAnimOb` | no | yes | 96 / 198 | P3 |
| -162 | `Animate` | no | yes | 468 / 570 | P2 |
| -168 | `GetGBuffers` | no | yes | 350 / 382 | P2 |
| -174 | `InitGMasks` | no | yes | 70 / 304 | P2 |
| -180 | `DrawEllipse` | no | no (null vector) | 22 / 672 | P2 |
| -186 | `AreaEllipse` | no | no (null vector) | 188 / 188 | P2 |
| -192 | `LoadRGB4` | cited — monkey-startup §3 ; octamed §2.2 | yes | 272 / 676 | P2 |
| -198 | `InitRastPort` | cited — fastfonts-ff §3 | yes | 10 / 86 | P3 |
| -204 | `InitVPort` | no | no (null vector) | 16 / 52 | P1 |
| -210 | `MrgCop` | partial — caesar-boot §2.7 ; monkey-startup §3 | yes | 1354 / 1474 | P1 |
| -216 | `MakeVPort` | partial — caesar-boot §1, §2.7 ; monkey-startup §3 | yes | 2554 / 3722 | P1 |
| -222 | `LoadView` | partial — caesar-boot §2.7 | yes | 282 / 434 | P1 |
| -228 | `WaitBlit` | cited — fastfonts-ff §2 | yes | 36 / 36 | P1 |
| -234 | `SetRast` | cited — wb-icon-clipping §5 | yes | 646 / 1160 | P2 |
| -240 | `Move` | cited — preferences-13 §5.3 | yes | 20 / 20 | P3 |
| -246 | `Draw` | cited — preferences-13 §5.3 | yes | 2424 / 3494 | P2 |
| -252 | `AreaMove` | no | no (null vector) | 148 / 148 | P1 |
| -258 | `AreaDraw` | no | no (null vector) | 80 / 80 | P1 |
| -264 | `AreaEnd` | no | no (null vector) | 1260 / 3056 | P1 |
| -270 | `WaitTOF` | cited — sysinfo-44 §1.3 | yes | 120 / 236 | P3 |
| -276 | `QBlit` | no | no (null vector) | 22 / 638 | P2 |
| -282 | `InitArea` | no | no (null vector) | 30 / 30 | P1 |
| -288 | `SetRGB4` | partial — intuition-prefs §3.3 (4-bit mask) | yes | 336 / 794 | P2 |
| -294 | `QBSBlit` | cited — timer-v34 §6.2 | no (null vector) | 220 / 836 | P2 |
| -300 | `BltClear` | cited — workbench-task §3.6 | yes | 224 / 684 | P2 |
| -306 | `RectFill` | cited — intuition-frame §2 | yes | 180 / 234 | P3 |
| -312 | `BltPattern` | no | no (null vector) | 3648 / 4654 | P2 |
| -318 | `ReadPixel` | no | yes | 264 / 300 | P2 |
| -324 | `WritePixel` | cited — octamed §2.3 | yes | 352 / 812 | P2 |
| -330 | `Flood` | cited — workbench-task §3.6 | no (null vector) | 5634 / 8750 | P1 |
| -336 | `PolyDraw` | cited — octamed §2.3 | yes | 32 / 32 | P3 |
| -342 | `SetAPen` | cited — octamed §2.1 | yes | 6 / 78 | P3 |
| -348 | `SetBPen` | cited — octamed §2.1 | yes | 6 / 78 | P3 |
| -354 | `SetDrMd` | cited — preferences-13 §5.3 | yes | 4 / 4 (ROM stub) | P3 |
| -360 | `InitView` | partial — intuition-prefs §1 (DxOffset/DyOffset) | no (null vector) | 22 / 58 | P1 |
| -366 | `CBump` | cited — monkey-startup §3 | yes | 54 / 300 | P2 |
| -372 | `CMove` | cited — monkey-startup §3 | yes | 76 / 366 | P2 |
| -378 | `CWait` | cited — monkey-startup §3 | yes | 78 / 368 | P2 |
| -384 | `VBeamPos` | cited — octamed §2.3 | yes | 16 / 16 | P3 |
| -390 | `InitBitMap` | partial — fastfonts-ff §3 (BytesPerRow) | yes | 22 / 22 | P3 |
| -396 | `ScrollRaster` | cited — wb-icon-clipping §0 | yes | 142 / 380 | P2 |
| -402 | `WaitBOVP` | no | no (null vector) | 6 / 62 | P2 |
| -408 | `GetSprite` | cited — octamed §2.3 | yes | 136 / 168 | P3 |
| -414 | `FreeSprite` | cited — octamed §2.3 | yes | 68 / 132 | P3 |
| -420 | `ChangeSprite` | cited — octamed §2.3 | yes | 68 / 772 | P2 |
| -426 | `MoveSprite` | cited — octamed §2.3 | yes | 20 / 724 | P2 |
| -432 | `LockLayerRom` | partial — fastfonts-ff §2 (A5, registers preserved) | yes | 22 / 22 | P3 |
| -438 | `UnlockLayerRom` | partial — fastfonts-ff §2 | yes | 22 / 22 | P3 |
| -444 | `SyncSBitMap` | no | no (null vector) | 12 / 2778 | P2 |
| -450 | `CopySBitMap` | no | no (null vector) | 12 / 1014 | P2 |
| -456 | `OwnBlitter` | cited — monkey-startup §2 | yes | 24 / 236 | P2 |
| -462 | `DisownBlitter` | cited — monkey-startup §2 | yes | 104 / 234 | P2 |
| -468 | `InitTmpRas` | cited — workbench-task §3.6 | no (null vector) | 12 / 12 | P1 |
| -474 | `AskFont` | no | yes | 18 / 18 | P3 |
| -480 | `AddFont` | no | yes | 58 / 58 | P3 |
| -486 | `RemFont` | no | yes | 78 / 78 | P3 |
| -492 | `AllocRaster` | cited — monkey-startup §2 | yes | 18 / 32 | P3 |
| -498 | `FreeRaster` | cited — caesar-boot §1 | yes | 20 / 34 | P3 |
| -504 | `AndRectRegion` | cited — wb-icon-clipping §1 | yes | 16 / 1510 | P2 |
| -510 | `OrRectRegion` | cited — wb-icon-clipping §1 | yes | 16 / 1278 | P2 |
| -516 | `NewRegion` | cited — wb-icon-clipping §1 | yes | 20 / 42 | P3 |
| -522 | `ClearRectRegion` | no | yes | 82 / 2582 | P2 |
| -528 | `ClearRegion` | cited — installclipregion §4.1 | yes | 12 / 110 | P3 |
| -534 | `DisposeRegion` | cited — wb-icon-clipping §2 | yes | 12 / 142 | P3 |
| -540 | `FreeVPortCopLists` | no | yes | 128 / 214 | P2 |
| -546 | `FreeCopList` | cited — octamed §2.3 | no (null vector) | 14 / 100 | P2 |
| -552 | `ClipBlit` | cited — wb-icon-clipping §0 | no (null vector) | 370 / 3206 | P1 |
| -558 | `XorRectRegion` | no | yes | 16 / 1814 | P2 |
| -564 | `FreeCprList` | no | no (null vector) | 74 / 98 | P1 |
| -570 | `GetColorMap` | no | no (null vector) | 88 / 88 | P1 |
| -576 | `FreeColorMap` | no | no (null vector) | 36 / 36 | P1 |
| -582 | `GetRGB4` | cited — octamed §2.2 | yes | 24 / 24 | P3 |
| -588 | `ScrollVPort` | no | no (null vector) | 2362 / 3442 | P1 |
| -594 | `UCopperListInit` | cited — monkey-startup §3 | yes | 16 / 306 | P2 |
| -600 | `FreeGBuffers` | no | yes | 254 / 264 | P3 |
| -606 | `BltBitMapRastPort` | cited — intuition-requesters §2.3 ; wb-icon-clipping §3 | yes | 272 / 3108 | P2 |
| -612 | `OrRegionRegion` | no | yes | 16 / 1370 | P2 |
| -618 | `XorRegionRegion` | no | yes | 16 / 1906 | P2 |
| -624 | `AndRegionRegion` | no | yes | 226 / 2326 | P2 |
| -630 | `SetRGB4CM` | no | no (null vector) | 54 / 54 | P3 |
| -636 | `BltMaskBitMapRastPort` | cited — wb-icon-clipping §3, §8 | no (null vector) | 470 / 3306 | P1 |
| -642 | `graphicsPrivate1` *(private)* | no | absent (outside the table) | 4 / 4 (ROM stub) | P3 |
| -648 | `graphicsPrivate2` *(private)* | no | absent (outside the table) | 4 / 4 (ROM stub) | P3 |
| -654 | `AttemptLockLayerRom` | no | absent (outside the table) | 22 / 22 | P1 |

### intuition.library (74 LVOs, −30 to −468)

| LVO | Function | Specified? (file §) | Implemented on our side | ROM size (own / closure) | Priority |
|---:|---|---|---|---|:-:|
| -30 | `OpenIntuition` | no | no (null vector) | 18 / 2530 | P3 |
| -36 | `Intuition` | partial — intuiticks-repeat §3 ; intuition-requesters §3 ; intuition-gzz §3 | no (null vector) | 15324 / 28100 | P1 |
| -42 | `AddGadget` | partial — intuition-gzz §6.2 | yes | 62 / 474 | P2 |
| -48 | `ClearDMRequest` | yes — intuition-requesters §4.4 | yes | 30 / 76 | — |
| -54 | `ClearMenuStrip` | cited — workbench-task §4.1 | yes | 44 / 164 | P3 |
| -60 | `ClearPointer` | cited — octamed §2.3 | no (null vector) | 66 / 922 | P1 |
| -66 | `CloseScreen` | cited — sysinfo-44 §S1 | yes | 54 / 12322 | P2 |
| -72 | `CloseWindow` | cited — intuition-requesters §5.1 | yes | 12 / 2550 | P2 |
| -78 | `CloseWorkBench` | cited — monkey-startup §2 ; workbench-task §0 | no (null vector) | 84 / 12352 | P1 |
| -84 | `CurrentTime` | no | no (null vector) | 38 / 38 | P2 |
| -90 | `DisplayAlert` | partial — intuition-requesters §5.3 | no (null vector) | 18 / 2330 | P1 |
| -96 | `DisplayBeep` | cited — workbench-task §6.2 | yes | 12 / 332 | P2 |
| -102 | `DoubleClick` | partial — intuition-prefs §1, §3.3 | yes | 86 / 86 | P3 |
| -108 | `DrawBorder` | partial — intuition-gzz §6.1 | yes | 20 / 572 | P2 |
| -114 | `DrawImage` | partial — intuition-gzz §6.1 ; intuition-prop §3.1 | yes | 20 / 700 | P2 |
| -120 | `EndRequest` | yes — intuition-requesters §4 | yes | 14 / 668 | — |
| -126 | `GetDefPrefs` | yes — intuition-prefs §4.2 | yes | 68 / 260 | — |
| -132 | `GetPrefs` | yes — intuition-prefs §4.1 | yes | 50 / 154 | — |
| -138 | `InitRequester` | yes — intuition-requesters §4.3 | yes | 12 / 26 | — |
| -144 | `ItemAddress` | no | yes | 14 / 244 | P2 |
| -150 | `ModifyIDCMP` | cited — octamed §2.5 | yes | 14 / 1014 | P2 |
| -156 | `ModifyProp` | yes — intuition-prop §5 | yes | 6 / 6 | — |
| -162 | `MoveScreen` | cited — preferences-13 §4 | no (null vector) | 18 / 804 | P2 |
| -168 | `MoveWindow` | partial — installclipregion §4.2 | yes | 74 / 288 | P3 |
| -174 | `OffGadget` | no | yes | 42 / 7246 | P2 |
| -180 | `OffMenu` | cited — workbench-task §3.6 | yes | 40 / 486 | P2 |
| -186 | `OnGadget` | no | yes | 42 / 7246 | P2 |
| -192 | `OnMenu` | cited — workbench-task §3.6 | yes | 42 / 488 | P2 |
| -198 | `OpenScreen` | cited — monkey-startup §2 | yes | 12 / 10462 | P1 |
| -204 | `OpenWindow` | yes — intuition-frame §2 ; intuition-gzz §1–§2 | yes | 12 / 15640 | — |
| -210 | `OpenWorkBench` | partial — intuition-prefs §3.3 | yes | 6 / 11734 | P2 |
| -216 | `PrintIText` | partial — intuition-gzz §6.1 ; intuition-requesters §2.3 | yes | 20 / 802 | P2 |
| -222 | `RefreshGadgets` | yes — intuition-gzz §6.2 | yes | 16 / 7220 | — |
| -228 | `RemoveGadget` | cited — intuition-gzz §6.3 | yes | 48 / 498 | P2 |
| -234 | `ReportMouse` | cited — octamed §2.5 | yes | 66 / 94 | P3 |
| -240 | `Request` | yes — intuition-requesters §2–§3 | yes | 14 / 8662 | — |
| -246 | `ScreenToBack` | no | yes | 12 / 956 | P2 |
| -252 | `ScreenToFront` | cited — intuition-requesters §5.1 | yes | 32 / 984 | P2 |
| -258 | `SetDMRequest` | yes — intuition-requesters §4.4 | yes | 36 / 82 | — |
| -264 | `SetMenuStrip` | cited — workbench-task §3.2 | yes | 224 / 1446 | P2 |
| -270 | `SetPointer` | cited — monkey-startup §2 ; octamed §2.3 | no (null vector) | 96 / 952 | P1 |
| -276 | `SetWindowTitles` | partial — intuition-frame §3.2 ; workbench-task §6.6 | yes | 122 / 8486 | P2 |
| -282 | `ShowTitle` | partial — monkey-startup §3 (d) | yes | 86 / 7914 | P2 |
| -288 | `SizeWindow` | no | yes | 74 / 288 | P3 |
| -294 | `ViewAddress` | cited — preferences-13 §4 | yes | 16 / 16 | P3 |
| -300 | `ViewPortAddress` | cited — octamed §2.1 | yes | 28 / 28 | P3 |
| -306 | `WindowToBack` | no | yes | 36 / 250 | P3 |
| -312 | `WindowToFront` | cited — workbench-task §3.3 | yes | 36 / 250 | P3 |
| -318 | `WindowLimits` | no | yes | 18 / 142 | P3 |
| -324 | `SetPrefs` | yes — intuition-prefs §3 | yes | 98 / 2530 | — |
| -330 | `IntuiTextLength` | no | yes | 12 / 672 | P2 |
| -336 | `WBenchToBack` | no | no (null vector) | 6 / 1020 | P2 |
| -342 | `WBenchToFront` | no | no (null vector) | 6 / 1030 | P2 |
| -348 | `AutoRequest` | yes — intuition-requesters §5.1 | yes | 270 / 20666 | — |
| -354 | `BeginRefresh` | cited — workbench-task §7.2 | yes | 12 / 168 | P3 |
| -360 | `BuildSysRequest` | yes — intuition-requesters §5.2 | yes | 20 / 20004 | — |
| -366 | `EndRefresh` | cited — workbench-task §7.2 | yes | 14 / 136 | P3 |
| -372 | `FreeSysRequest` | yes — intuition-requesters §5.4 | yes | 12 / 2964 | — |
| -378 | `MakeScreen` | no | no (null vector) | 12 / 322 | P2 |
| -384 | `RemakeDisplay` | partial — intuition-prefs §3.3 ; caesar-boot §1 | yes | 6 / 802 | P2 |
| -390 | `RethinkDisplay` | cited — monkey-startup §3 | yes | 6 / 6 | P3 |
| -396 | `AllocRemember` | cited — intuition-requesters §5.2 | yes | 18 / 164 | P3 |
| -402 | `AlohaWorkbench` | partial — workbench-task §3.1 | no (null vector) | 24 / 24 | P2 |
| -408 | `FreeRemember` | cited — intuition-requesters §5.4 | yes | 14 / 102 | P3 |
| -414 | `LockIBase` | no | no (null vector) | 60 / 120 | P2 |
| -420 | `UnlockIBase` | no | no (null vector) | 54 / 114 | P2 |
| -426 | `GetScreenData` | partial — workbench-task §3.2 | yes | 112 / 11840 | P2 |
| -432 | `RefreshGList` | cited — octamed §2.4 (+ error intuition-gzz §6.2) | yes | 48 / 7222 | P2 |
| -438 | `AddGList` | cited — octamed §2.4 | yes | 20 / 432 | P2 |
| -444 | `RemoveGList` | cited — octamed §2.4 | yes | 18 / 468 | P2 |
| -450 | `ActivateWindow` | yes — intuition-frame §4.1 | no (null vector) | 38 / 252 | — |
| -456 | `RefreshWindowFrame` | yes — intuition-frame §2 | no (null vector) | 28 / 8686 | — |
| -462 | `ActivateGadget` | cited — workbench-task §6.8 | yes | 236 / 1232 | P2 |
| -468 | `NewModifyProp` | yes — intuition-prop §5 | yes | 82 / 7256 | — |

### layers.library (25 LVOs, −30 to −174)

| LVO | Function | Specified? (file §) | Implemented on our side | ROM size (own / closure) | Priority |
|---:|---|---|---|---|:-:|
| -30 | `InitLayers` | no | yes | 10 / 120 | P3 |
| -36 | `CreateUpfrontLayer` | partial — intuition-gzz §2 | yes | 118 / 10140 | P2 |
| -42 | `CreateBehindLayer` | partial — intuition-requesters §2.2 | yes | 20 / 9850 | P2 |
| -48 | `UpfrontLayer` | cited — installclipregion §4.2 | yes | 10 / 6284 | P1 |
| -54 | `BehindLayer` | cited — installclipregion §4.2 | yes | 90 / 6296 | P1 |
| -60 | `MoveLayer` | cited — installclipregion §4.2 | yes | 320 / 10916 | P1 |
| -66 | `SizeLayer` | cited — installclipregion §4.2 | yes | 618 / 11232 | P1 |
| -72 | `ScrollLayer` | cited — installclipregion §4.2 | stub (constant return) | 108 / 1136 | P2 |
| -78 | `BeginUpdate` | yes — installclipregion §4.1 ; wb-icon-clipping §1 | yes | 56 / 2640 | — |
| -84 | `EndUpdate` | yes — installclipregion §4.1 ; wb-icon-clipping §2 | yes | 76 / 2678 | — |
| -90 | `DeleteLayer` | partial — setpatch-disk-resource §4 ; installclipregion §4.2 | yes | 10 / 7432 | P2 |
| -96 | `LockLayer` | partial — installclipregion §4.3 | yes | 10 / 32 | P3 |
| -102 | `UnlockLayer` | no | yes | 10 / 32 | P3 |
| -108 | `LockLayers` | partial — installclipregion §4.2 | yes | 10 / 710 | P2 |
| -114 | `UnlockLayers` | partial — installclipregion §4.2 | yes | 10 / 2392 | P2 |
| -120 | `LockLayerInfo` | partial — installclipregion §4.3 | yes | 10 / 44 | P3 |
| -126 | `SwapBitsRastPortClipRect` | no | yes | 12 / 320 | P2 |
| -132 | `WhichLayer` | cited — workbench-task §3.6 | yes | 46 / 46 | P3 |
| -138 | `UnlockLayerInfo` | no | yes | 10 / 44 | P3 |
| -144 | `NewLayerInfo` | no | yes | 72 / 314 | P2 |
| -150 | `DisposeLayerInfo` | no | yes | 40 / 116 | P3 |
| -156 | `FattenLayerInfo` | no | stub (constant return) | 44 / 176 | P3 |
| -162 | `ThinLayerInfo` | no | stub (constant return) | 34 / 110 | P3 |
| -168 | `MoveLayerInFrontOf` | partial — intuition-gzz §2.2 ; installclipregion §4.2 | yes | 84 / 6230 | P2 |
| -174 | `InstallClipRegion` | yes — installclipregion §1–§7 | yes | 78 / 2684 | — |

### dos.library (33 LVOs, −30 to −222)

Sizes: each dos LVO is a thin bridge to a BCPL global (bcpl-runtime §1.4); the size of the BCPL code is not measured here ("n/m" column).

| LVO | Function | Specified? (file §) | Implemented on our side | ROM size (own / closure) | Priority |
|---:|---|---|---|---|:-:|
| -30 | `Open` | yes — dos-v34-spec §2–§3 ; bcpl-runtime §5.1 | yes | n/m | — |
| -36 | `Close` | yes — bcpl-runtime §5.1 ; dos-v34-spec §2b | yes | n/m | — |
| -42 | `Read` | yes — dos-v34-spec §3 ; bcpl-runtime §5.1 | yes | n/m | — |
| -48 | `Write` | yes — disk-full-write §3 ; bcpl-runtime §6.1 | yes | n/m | — |
| -54 | `Input` | partial — bcpl-runtime §8.1 | yes | n/m | P3 |
| -60 | `Output` | partial — bcpl-runtime §8.1 | yes | n/m | P3 |
| -66 | `Seek` | partial — bcpl-runtime §8.3 ; disk-full-write §1 | yes | n/m | P3 |
| -72 | `DeleteFile` | partial — bcpl-runtime §8.3 | yes | n/m | P3 |
| -78 | `Rename` | partial — bcpl-runtime §8.4.2 | yes | n/m | P3 |
| -84 | `Lock` | yes — dos-v34-spec §2b ; disk-change §2.4 | yes | n/m | — |
| -90 | `UnLock` | yes — dos-v34-spec §2b | yes | n/m | — |
| -96 | `DupLock` | partial — bcpl-runtime §8.2 | yes | n/m | P3 |
| -102 | `Examine` | yes — dos-v34-spec §2b | yes | n/m | — |
| -108 | `ExNext` | yes — dos-v34-spec §2b | yes | n/m | — |
| -114 | `Info` | partial — bcpl-runtime §8.3 ; disk-change §2.3 | yes | n/m | P3 |
| -120 | `CreateDir` | partial — bcpl-runtime §8.3 | yes | n/m | P3 |
| -126 | `CurrentDir` | partial — bcpl-runtime §8.3 | yes | n/m | P3 |
| -132 | `IoErr` | partial — bcpl-runtime §8.3 | yes | n/m | P3 |
| -138 | `CreateProc` | yes — dos-v34-spec §4 ; bcpl-runtime §8.1 ; workbench-task §1.3 | yes | n/m | — |
| -144 | `Exit` | yes — bcpl-runtime §4.3, §8.1 | no (null vector) | n/m | — |
| -150 | `LoadSeg` | partial — bcpl-runtime §3 ; dos-boot-sequence §Phase E | yes | n/m | P3 |
| -156 | `UnLoadSeg` | partial — bcpl-runtime §8.2 | yes | n/m | P3 |
| -162 | `dosPrivate1` (= `GetPacket`) *(private)* | yes — bcpl-runtime §1.4 (global anomaly −20) | no (null vector) | n/m | — |
| -168 | `dosPrivate2` (= `QueuePacket`) *(private)* | yes — bcpl-runtime §1.4 (global −21) | no (null vector) | n/m | — |
| -174 | `DeviceProc` | yes — handlers-v34 §4.1 | yes | n/m | — |
| -180 | `SetComment` | partial — bcpl-runtime §8.3 | yes | n/m | P3 |
| -186 | `SetProtection` | partial — bcpl-runtime §8.3 | yes | n/m | P3 |
| -192 | `DateStamp` | yes — bcpl-runtime §8.4.2 ; boot-clock | yes | n/m | — |
| -198 | `Delay` | partial — bcpl-runtime §8.1 | yes | n/m | P3 |
| -204 | `WaitForChar` | partial — bcpl-runtime §8.2 | stub (constant return) | n/m | P2 |
| -210 | `ParentDir` | partial — dos-v34-spec §2b ; bcpl-runtime §8.1 | yes | n/m | P3 |
| -216 | `IsInteractive` | partial — bcpl-runtime §5.1 | yes | n/m | P3 |
| -222 | `Execute` | yes — bcpl-runtime §0, §13 ; setpatch-138 §3.2 | yes | n/m | — |

### expansion.library (21 LVOs, −30 to −150)

| LVO | Function | Specified? (file §) | Implemented on our side | ROM size (own / closure) | Priority |
|---:|---|---|---|---|:-:|
| -30 | `AddConfigDev` | yes — autoconfig-v34 §7 | yes | 28 / 28 | — |
| -36 | `expansionPrivate36` (= `expansionUnused`) *(private)* | yes — autoconfig-v34 §7 | yes | 24 / 24 | — |
| -42 | `AllocBoardMem` | yes — autoconfig-v34 §7 | yes | 24 / 24 | — |
| -48 | `AllocConfigDev` | yes — autoconfig-v34 §7 | yes | 22 / 22 | — |
| -54 | `AllocExpansionMem` | yes — autoconfig-v34 §7 | yes | 140 / 140 | — |
| -60 | `ConfigBoard` | yes — autoconfig-v34 §7 | yes | 380 / 380 | — |
| -66 | `ConfigChain` | yes — autoconfig-v34 §7 | yes | 86 / 86 | — |
| -72 | `FindConfigDev` | yes — autoconfig-v34 §7 | yes | 54 / 54 | — |
| -78 | `FreeBoardMem` | yes — autoconfig-v34 §7 | yes | 16 / 16 | — |
| -84 | `FreeConfigDev` | yes — autoconfig-v34 §7 | yes | 18 / 18 | — |
| -90 | `FreeExpansionMem` | yes — autoconfig-v34 §7 | yes | 56 / 56 | — |
| -96 | `ReadExpansionByte` | yes — autoconfig-v34 §7 | yes | 28 / 28 | — |
| -102 | `ReadExpansionRom` | yes — autoconfig-v34 §7 | yes | 168 / 168 | — |
| -108 | `RemConfigDev` | yes — autoconfig-v34 §7 | yes | 32 / 32 | — |
| -114 | `WriteExpansionByte` | yes — autoconfig-v34 §7 | yes | 20 / 20 | — |
| -120 | `ObtainConfigBinding` | yes — autoconfig-v34 §7 | yes | 18 / 18 | — |
| -126 | `ReleaseConfigBinding` | yes — autoconfig-v34 §7 | yes | 18 / 18 | — |
| -132 | `SetCurrentBinding` | yes — autoconfig-v34 §7 | yes | 12 / 40 | — |
| -138 | `GetCurrentBinding` | yes — autoconfig-v34 §7 | yes | 16 / 44 | — |
| -144 | `MakeDosNode` | yes — autoconfig-v34 §7 | yes | 264 / 264 | — |
| -150 | `AddDosNode` | yes — autoconfig-v34 §7 | yes | 242 / 242 | — |

### mathffp.library (12 LVOs, −30 to −96)

| LVO | Function | Specified? (file §) | Implemented on our side | ROM size (own / closure) | Priority |
|---:|---|---|---|---|:-:|
| -30 | `SPFix` | no | yes | 82 / 82 | P3 |
| -36 | `SPFlt` | no | yes | 56 / 56 | P3 |
| -42 | `SPCmp` | no | yes | 60 / 60 | P3 |
| -48 | `SPTst` | no | yes | 40 / 40 | P3 |
| -54 | `SPAbs` | no | yes | 6 / 6 | P3 |
| -60 | `SPNeg` | no | yes | 10 / 10 | P3 |
| -66 | `SPAdd` | no | yes | 16 / 16 | P3 |
| -72 | `SPSub` | no | yes | 254 / 254 | P3 |
| -78 | `SPMul` | no | yes | 154 / 154 | P3 |
| -84 | `SPDiv` | no | yes | 166 / 166 | P3 |
| -90 | `SPFloor` | no | yes | 86 / 366 | P3 |
| -96 | `SPCeil` | no | yes | 10 / 376 | P3 |

### timer.device — functions (3 LVOs, −42 to −54)

| LVO | Function | Specified? (file §) | Implemented on our side | ROM size (own / closure) | Priority |
|---:|---|---|---|---|:-:|
| -42 | `AddTime` | yes — timer-v34 §5 | yes | 36 / 36 | — |
| -48 | `SubTime` | yes — timer-v34 §5 | yes | 28 / 28 | — |
| -54 | `CmpTime` | yes — timer-v34 §5 | yes | 28 / 28 | — |

### console.device — functions (2 LVOs, −42 to −48)

| LVO | Function | Specified? (file §) | Implemented on our side | ROM size (own / closure) | Priority |
|---:|---|---|---|---|:-:|
| -42 | `CDInputHandler` | no | no (null vector) | 706 / 1000 | P2 |
| -48 | `RawKeyConvert` | partial — monkey-startup §6 | yes | 516 / 516 | P2 |

### cia.resource (ciaa/ciab, 4 LVOs, −6 to −24)

| LVO | Function | Specified? (file §) | Implemented on our side | ROM size (own / closure) | Priority |
|---:|---|---|---|---|:-:|
| -6 | `AddICRVector` | partial — keyboard-handshake §1–§2 ; timer-v34 §1, §6 | yes | 58 / 184 | P3 |
| -12 | `RemICRVector` | no | yes | 36 / 162 | P2 |
| -18 | `AbleICR` | partial — timer-v34 §6.2 | yes | 98 / 98 | P3 |
| -24 | `SetICR` | partial — timer-v34 §6.2 | stub (constant return) | 36 / 36 | P2 |

### disk.resource (5 LVOs, −6 to −30)

| LVO | Function | Specified? (file §) | Implemented on our side | ROM size (own / closure) | Priority |
|---:|---|---|---|---|:-:|
| -6 | `AllocUnit` | no | yes | 12 / 12 | P2 |
| -12 | `FreeUnit` | no | yes | 6 / 6 | P2 |
| -18 | `GetUnit` | partial — setpatch-138 §1.7 ; setpatch-disk-resource §3 | yes | 120 / 120 | P3 |
| -24 | `GiveUnit` | partial — setpatch-138 §1.7 ; setpatch-disk-resource §3 | yes | 84 / 84 | P3 |
| -30 | `GetUnitID` | no | yes | 12 / 12 | P1 |

### potgo.resource (3 LVOs, −6 to −18)

| LVO | Function | Specified? (file §) | Implemented on our side | ROM size (own / closure) | Priority |
|---:|---|---|---|---|:-:|
| -6 | `AllocPotBits` | no | yes | 106 / 106 | P2 |
| -12 | `FreePotBits` | no | yes | 22 / 22 | P2 |
| -18 | `WritePotgo` | no | yes | 50 / 50 | P2 |

### misc.resource (2 LVOs, −6 to −12)

| LVO | Function | Specified? (file §) | Implemented on our side | ROM size (own / closure) | Priority |
|---:|---|---|---|---|:-:|
| -6 | `AllocMiscResource` | no | yes | 56 / 56 | P2 |
| -12 | `FreeMiscResource` | no | yes | 12 / 12 | P2 |

## 4. Device commands

The standard vectors (Open, Close, Expunge, reserved, BeginIO, AbortIO) are not repeated; the
commands are the real API. The CMD_INVALID…CMD_FLUSH routines of keyboard, gameport, input and console
are partly **common** to the four devices in the ROM (same code for several entries).

- **timer.device**: TR_ADDREQUEST (9), TR_GETSYSTIME (10), TR_SETSYSTIME (11) — **specified**
  (timer-v34 §2–§4), implemented; whole device ≈ 360 bytes reached from its 9 vectors.
- **audio.device**: CMD_RESET, CMD_READ, CMD_WRITE, CMD_UPDATE, CMD_CLEAR, CMD_STOP, CMD_START,
  CMD_FLUSH, ADCMD_FREE, ADCMD_SETPREC, ADCMD_FINISH, ADCMD_PERVOL, ADCMD_LOCK, ADCMD_WAITCYCLE,
  ADCMD_ALLOCATE — **none specified** (only cited: octamed §2.5); all present in
  `src/exec/audio.s`. Size: 2,464 bytes reached from the 6 vectors (BeginIO alone ≈ 1.7 KB of
  closure), ROM area 4,204 bytes. Command table not decoded (internal dispatch).

#### keyboard.device (14 commands, 0–13)

| No. | Command | Specified? | Implemented on our side | ROM size (own / closure) | Priority |
|---:|---|---|---|---|:-:|
| 0 | `CMD_INVALID` | no | not verified | 8 / 134 | P3 |
| 1 | `CMD_RESET` | no | not verified | 56 / 280 | P3 |
| 2 | `CMD_READ` | no | not verified | 4 / 4 (shared routine ×3) (ROM stub) | P3 |
| 3 | `CMD_WRITE` | no | not verified | 4 / 4 (shared routine ×3) (ROM stub) | P3 |
| 4 | `CMD_UPDATE` | no | not verified | 4 / 4 (shared routine ×3) (ROM stub) | P3 |
| 5 | `CMD_CLEAR` | no | yes | 36 / 42 | P3 |
| 6 | `CMD_STOP` | no | not verified | 16 / 142 | P3 |
| 7 | `CMD_START` | no | not verified | 44 / 170 | P3 |
| 8 | `CMD_FLUSH` | no | not verified | 32 / 164 | P3 |
| 9 | `KBD_READEVENT` | partial — keyboard-handshake §3 | yes | 230 / 362 | P2 |
| 10 | `KBD_READMATRIX` | no | yes | 42 / 42 | P2 |
| 11 | `KBD_ADDRESETHANDLER` | partial — keyboard-handshake §5 | yes | 26 / 32 | P2 |
| 12 | `KBD_REMRESETHANDLER` | no | yes | 22 / 28 | P3 |
| 13 | `KBD_RESETHANDLERDONE` | partial — keyboard-handshake §5 | yes | 16 / 22 | P2 |

#### gameport.device (14 commands, 0–13)

| No. | Command | Specified? | Implemented on our side | ROM size (own / closure) | Priority |
|---:|---|---|---|---|:-:|
| 0 | `CMD_INVALID` | no | no (IOERR_NOCMD) | 8 / 134 | P3 |
| 1 | `CMD_RESET` | no | no (IOERR_NOCMD) | 14 / 238 | P3 |
| 2 | `CMD_READ` | no | no (IOERR_NOCMD) | 4 / 4 (shared routine ×3) (ROM stub) | P3 |
| 3 | `CMD_WRITE` | no | no (IOERR_NOCMD) | 4 / 4 (shared routine ×3) (ROM stub) | P3 |
| 4 | `CMD_UPDATE` | no | no (IOERR_NOCMD) | 4 / 4 (shared routine ×3) (ROM stub) | P3 |
| 5 | `CMD_CLEAR` | no | no (IOERR_NOCMD) | 38 / 38 | P2 |
| 6 | `CMD_STOP` | no | no (IOERR_NOCMD) | 16 / 142 | P3 |
| 7 | `CMD_START` | no | no (IOERR_NOCMD) | 44 / 170 | P3 |
| 8 | `CMD_FLUSH` | no | no (IOERR_NOCMD) | 32 / 164 | P3 |
| 9 | `GPD_READEVENT` | no | no (IOERR_NOCMD) | 268 / 394 | P1 |
| 10 | `GPD_ASKCTYPE` | no | no (IOERR_NOCMD) | 42 / 42 | P1 |
| 11 | `GPD_SETCTYPE` | cited — intuiticks-repeat §1.1 | no (IOERR_NOCMD) | 84 / 84 | P1 |
| 12 | `GPD_ASKTRIGGER` | no | no (IOERR_NOCMD) | 48 / 48 | P1 |
| 13 | `GPD_SETTRIGGER` | no | no (IOERR_NOCMD) | 48 / 48 | P1 |

#### input.device (17 commands, 0–16)

| No. | Command | Specified? | Implemented on our side | ROM size (own / closure) | Priority |
|---:|---|---|---|---|:-:|
| 0 | `CMD_INVALID` | no | not verified | 8 / 134 | P3 |
| 1 | `CMD_RESET` | no | not verified | 14 / 242 | P3 |
| 2 | `CMD_READ` | no | not verified | 4 / 4 (shared routine ×3) (ROM stub) | P3 |
| 3 | `CMD_WRITE` | no | not verified | 4 / 4 (shared routine ×3) (ROM stub) | P3 |
| 4 | `CMD_UPDATE` | no | not verified | 4 / 4 (shared routine ×3) (ROM stub) | P3 |
| 5 | `CMD_CLEAR` | no | not verified | 2 / 2 (ROM stub) | P3 |
| 6 | `CMD_STOP` | no | not verified | 16 / 142 | P3 |
| 7 | `CMD_START` | no | not verified | 48 / 48 | P3 |
| 8 | `CMD_FLUSH` | no | not verified | 32 / 164 | P3 |
| 9 | `IND_ADDHANDLER` | partial — intuiticks-repeat §1.4 | yes | 8 / 8 (shared routine ×3) | P3 |
| 10 | `IND_REMHANDLER` | partial — intuiticks-repeat §1.4 | yes | 8 / 8 (shared routine ×3) | P3 |
| 11 | `IND_WRITEEVENT` | partial — disk-change §3 | yes | 8 / 8 (shared routine ×3) | P3 |
| 12 | `IND_SETTHRESH` | yes — intuiticks-repeat §1.2, §2 | yes | 12 / 12 | — |
| 13 | `IND_SETPERIOD` | yes — intuiticks-repeat §1.2, §2 | yes | 14 / 20 | — |
| 14 | `IND_SETMPORT` | partial — intuiticks-repeat §1.1–§1.2 | no (IOERR_NOCMD) | 32 / 32 | P1 |
| 15 | `IND_SETMTYPE` | partial — intuiticks-repeat §1.1–§1.2 | no (IOERR_NOCMD) | 26 / 26 | P1 |
| 16 | `IND_SETMTRIG` | partial — intuiticks-repeat §1.2 | no (IOERR_NOCMD) | 46 / 46 | P1 |

#### console.device (13 commands, 0–12)

| No. | Command | Specified? | Implemented on our side | ROM size (own / closure) | Priority |
|---:|---|---|---|---|:-:|
| 0 | `CMD_INVALID` | no | not verified | 8 / 134 | P3 |
| 1 | `CMD_RESET` | no | not verified | 14 / 238 | P3 |
| 2 | `CMD_READ` | cited — handlers-v34 §2 | yes (partial) | 142 / 318 | P1 |
| 3 | `CMD_WRITE` | cited — handlers-v34 §2 (CSI sequences not specified) | yes (partial) | 1314 / 1632 | P1 |
| 4 | `CMD_UPDATE` | no | not verified | 4 / 4 (ROM stub) | P3 |
| 5 | `CMD_CLEAR` | no | no (IOERR_NOCMD) | 12 / 12 | P2 |
| 6 | `CMD_STOP` | no | not verified | 16 / 142 | P3 |
| 7 | `CMD_START` | no | not verified | 44 / 170 | P3 |
| 8 | `CMD_FLUSH` | no | not verified | 32 / 164 | P3 |
| 9 | `CD_ASKKEYMAP` | no | no (IOERR_NOCMD) | 16 / 72 | P1 |
| 10 | `CD_SETKEYMAP` | no | no (IOERR_NOCMD) | 16 / 72 | P1 |
| 11 | `CD_ASKDEFAULTKEYMAP` | no | no (IOERR_NOCMD) | 12 / 68 | P1 |
| 12 | `CD_SETDEFAULTKEYMAP` | no | no (IOERR_NOCMD) | 10 / 10 | P1 |

#### trackdisk.device (22 commands, 0–21; bound tested by BeginIO = 22)

| No. | Command | Specified? | Implemented on our side | ROM size (own / closure) | Priority |
|---:|---|---|---|---|:-:|
| 0 | `CMD_INVALID` | no | yes | 12 / 72 (shared routine ×5) | P3 |
| 1 | `CMD_RESET` | no | no-op | 12 / 72 (shared routine ×5) | P3 |
| 2 | `CMD_READ` | yes — trackdisk-official-timing §1–§3 | yes | 520 / 2880 (shared routine ×2) | — |
| 3 | `CMD_WRITE` | out of scope (write agent) | yes | 520 / 2880 (shared routine ×2) | — |
| 4 | `CMD_UPDATE` | out of scope (write agent) | yes | 50 / 1086 | — |
| 5 | `CMD_CLEAR` | partial — disk-change §2.1 ; uae-hd-boot §3 | yes | 22 / 82 | P3 |
| 6 | `CMD_STOP` | no | no-op | 12 / 72 (shared routine ×5) | P3 |
| 7 | `CMD_START` | no | no-op | 12 / 72 (shared routine ×5) | P3 |
| 8 | `CMD_FLUSH` | no | no-op | 12 / 72 (shared routine ×5) | P3 |
| 9 | `TD_MOTOR` | partial — intuition-requesters §7.1 ; trackdisk-official-timing §1 | yes | 22 / 342 | P3 |
| 10 | `TD_SEEK` | yes — trackdisk-official-timing §2 | no-op | 38 / 628 | P3 |
| 11 | `TD_FORMAT` | out of scope (write agent) | yes | 374 / 1668 | — |
| 12 | `TD_REMOVE` | yes — disk-change §2.1 | no-op | 12 / 72 | P2 |
| 13 | `TD_CHANGENUM` | partial — uae-hd-boot §3 ; disk-change §2.1 | yes | 12 / 72 | P3 |
| 14 | `TD_CHANGESTATE` | partial — disk-change §2.1 | yes | 20 / 80 | P3 |
| 15 | `TD_PROTSTATUS` | partial — disk-change §2.5 | yes | 90 / 410 | P3 |
| 16 | `TD_RAWREAD` | no | no (IOERR_NOCMD) | 120 / 756 | P2 |
| 17 | `TD_RAWWRITE` | no (belongs to the write agent) | no (IOERR_NOCMD) | 4 / 4 (ROM stub) | — |
| 18 | `TD_GETDRIVETYPE` | no | no (IOERR_NOCMD) | 18 / 78 | P2 |
| 19 | `TD_GETNUMTRACKS` | no | yes | 18 / 78 | P3 |
| 20 | `TD_ADDCHANGEINT` | cited — disk-change §2.1 (called "V36", cf. §5) | no-op | 28 / 28 | P2 |
| 21 | `TD_REMCHANGEINT` | cited — disk-change §2.1 | no-op | 22 / 82 | P2 |

## 5. Inconsistencies found in the existing analysis documentation (to be fixed by the analysis track)

1. **`intuition-gzz-v34.md` §6.2** classifies `RefreshGList` as "V36+, absent in 1.3". This is wrong:
   `RefreshGList` (−432), `AddGList` (−438), `RemoveGList` (−444), `ActivateWindow` (−450),
   `RefreshWindowFrame` (−456), `ActivateGadget` (−462) and `NewModifyProp` (−468) are **V33**
   functions (`.fd`), and the vector table of intuition 34.3 does have 78 entries (4 + 74).
2. **`exec-spec.md` §3 ("Delta")** puts `AddMemList` (−618), `CopyMem` (−624) and `CopyMemQuick` (−630)
   among the V36 additions. The ROM's exec table has **105 entries** and goes down to −630: these three
   functions exist in V34 (already flagged in §5 of the same file, but §3 has not been corrected).
3. **`disk-change-v34.md` §2.1** describes `TD_ADDCHANGEINT` as V36. The BeginIO of trackdisk 34.1
   accepts commands **< 22**, and entries 20 (`TD_ADDCHANGEINT`) and 21 (`TD_REMCHANGEINT`) of its
   table point to **dedicated** routines (≈ 28 and 22 bytes), distinct from the "invalid
   command" routine. To be settled by a black-box probe (DoIO `TD_ADDCHANGEINT` on the real 1.3:
   io_Error, and is the interrupt called on ejection?).
4. **`module-map.md`** states that the number of LVOs of the non-AUTOINIT modules "cannot be measured without
   tracing MakeLibrary". It can, by reading the tables: graphics 109, layers 29, exec 105, timer 9,
   console 8, keyboard/gameport/input/audio/trackdisk 6, romboot 5, disk 5, cia 4, potgo 3, misc 2,
   keymap 0 (cf. §1). Only the dos table has not been located.

## 6. Implementation gaps noticed in passing (reading of `src/`, for information)

- **graphics**: our table stops at −636 (106 vectors) whereas V34 has **109**:
  `graphicsPrivate1/2` (−642, −648) and **`AttemptLockLayerRom` (−654)** are **outside the table** — a call
  to LVO −654 ends up outside our jump table. `BltMaskBitMapRastPort` (−636, used by the Workbench
  for the icons, cf. wb-icon-clipping §3), `ScrollVPort`, `ClipBlit`, `Flood`, all the fill functions
  (`AreaMove/Draw/End`, `InitArea`, `InitTmpRas`), `InitView`, `InitVPort`, `GetColorMap`,
  `FreeColorMap`, `FreeCprList`, `QBlit`, `QBSBlit`, `BltPattern`, `WaitBOVP`, `SyncSBitMap`,
  `CopySBitMap` are null vectors (24 in total).
- **intuition**: null vectors for `SetPointer`, `ClearPointer`, `DisplayAlert`, `CloseWorkBench`,
  `MoveScreen`, `CurrentTime`, `MakeScreen`, `WBenchToBack/Front`, `LockIBase/UnlockIBase`,
  `AlohaWorkbench`, `ActivateWindow`, `RefreshWindowFrame` (these last two are nevertheless specified).
- **exec**: `ExitIntr`, `Schedule`, `Reschedule`, `Switch`, `Dispatch`, `Exception`, `Debug`,
  `Procure`, `Vacate`, `SumKickData` are null; `RawIOInit` is a stub; `Alert` displays nothing
  (serial message), and the `alert.hook` resident does not exist.
- **gameport.device**: BeginIO returns IOERR_NOCMD for **all** commands (the mouse goes through
  an internal poller). **input.device**: `IND_SETMPORT/SETMTYPE/SETMTRIG` refused.
- **console.device**: only CMD_READ/CMD_WRITE; the four keymap commands and `CDInputHandler`
  are absent. **keymap.resource** exposes two vectors that do not exist in V34 (without known
  consequence, but the base does not have the same shape).
- **layers**: `ScrollLayer`, `FattenLayerInfo`, `ThinLayerInfo` are stubs.
- **dos**: `Exit` and `GetPacket/QueuePacket` null, `WaitForChar` stub (returns 0).
- **cia.resource**: `SetICR` is a stub (returns 0).
- **trackdisk**: `TD_SEEK`, `TD_REMOVE`, `TD_ADDCHANGEINT`, `TD_REMCHANGEINT` are no-ops;
  `TD_RAWREAD`, `TD_RAWWRITE`, `TD_GETDRIVETYPE` are refused.

## 7. The next 15 analysis specs to write (by priority)

Out of scope, already entrusted to other agents: trackdisk writing (CMD_WRITE/UPDATE/FORMAT/RAWWRITE)
and hardware coldstart (reset, memory/CPU detection, overlay). The "real A500" risks below are
those that a tolerant emulator hides.

1. **graphics — blitter and copies**: `BltBitMap`, `BltTemplate`, `BltClear`, `BltPattern`, `ClipBlit`,
   `BltBitMapRastPort`, `BltMaskBitMapRastPort`, `OwnBlitter/DisownBlitter`, `WaitBlit`, `QBlit`,
   `QBSBlit` (≈ 1.7–4.7 KB of closure each; 6 absent on our side). *Why*: all the drawing of the
   Workbench (masked icons, drawers), PREDRAWN requesters, FastFonts, OctaMED (BltBitMapRastPort
   640×200), "clean" games. *A500 risk*: high — on a real Agnus the BBUSY bit is not reliable
   immediately after the write of BLTSIZE (documented defect, WaitBlit must take it into account), ascending/descending order
   for overlaps, "nasty" mode that starves the 68000, data necessarily in chip RAM.
2. **graphics — display construction and VBlank server**: `InitView`, `InitVPort`, `GetColorMap`,
   `FreeColorMap`, `MakeVPort`, `MrgCop`, `LoadView`, `FreeVPortCopLists`, `FreeCprList`, `ScrollVPort`,
   `VBeamPos`, `WaitTOF`, `WaitBOVP`, `gb_copinit`, LOF/SHF frames (MakeVPort ≈ 3.7 KB, MrgCop ≈ 1.5 KB,
   ScrollVPort ≈ 3.4 KB). *Why*: every intuition screen; the games and demos that build their own
   View (Caesar via RemakeDisplay, Monkey Island via UCopIns); hardware scrolling by ScrollVPort.
   *A500 risk*: high — PAL or NTSC Agnus (DIWSTRT/DDFSTRT, 50/60 Hz), interlace (alternation of the
   LOF/SHF lists at VBlank), OCS fetch limits, exact WAIT positions.
3. **exec `Alert` + `alert.hook` + intuition `DisplayAlert`** (Alert ≈ 1.8 KB of closure, alert.hook
   658 b, DisplayAlert ≈ 2.3 KB). *Why*: AutoRequest fallback (intuition-requesters §5.3),
   Preferences and Monkey Island on allocation failure, alerts from the ROM itself (stack, memory),
   SetPatch replaces Alert in 1.3. On our side: nothing is displayed. *A500 risk*: high — the alert
   drives the hardware directly (its own copper list, wait for the buttons via CIA/POTGO, restart
   on a dead-end alert); it is also the only visible diagnostic if the RAM of a real A500 is faulty.
4. **intuition — screens and Workbench**: `OpenScreen`, `CloseScreen`, `MoveScreen`, `ScreenToBack/Front`,
   `MakeScreen`, `RethinkDisplay`, `RemakeDisplay`, `CloseWorkBench`, `OpenWorkBench`, `WBenchToBack/Front`,
   `ShowTitle`, `GetScreenData`, `LockIBase/UnlockIBase` (OpenScreen ≈ 10 KB, CloseWorkBench ≈ 12 KB of
   closure; 6 absent on our side). *Why*: Monkey Island (CloseWorkBench), Preferences (MoveScreen),
   SysInfo (custom screen, ScreenToFront), OctaMED, pulling of the screen bar by the user.
   *A500 risk*: medium — interlaced display and dragged screens require correct copper lists.
5. **intuition — input engine, menus and gadgets**: `Intuition()` (−36, ≈ 28 KB of closure: the heart
   of intuition), `SetMenuStrip`, `ClearMenuStrip`, `ItemAddress`, `OnMenu/OffMenu`, `OnGadget/OffGadget`,
   `ActivateGadget` (string gadgets: editing, UNDO, LONGINT), `ReportMouse`, `ModifyIDCMP`, exact contents
   of the IDCMP messages of each class, `CurrentTime`, `BeginRefresh/EndRefresh`, `WindowLimits`,
   `SizeWindow`, `MoveWindow`, `WindowToFront/Back`. *Why*: Workbench menus, Rename/Info
   (string gadgets), OctaMED (ActivateGadget ×11, RefreshGList ×27), Preferences; the "no-effect"
   clicks observed come from this engine. *A500 risk*: low in itself (logic), but it is the largest
   unspecified area of the ROM.
6. **layers — stack operations, refresh types, SuperBitMap**: `CreateUpfront/BehindLayer`,
   `UpfrontLayer`, `BehindLayer`, `MoveLayer`, `SizeLayer`, `DeleteLayer`, `MoveLayerInFrontOf`,
   `ScrollLayer`, `SwapBitsRastPortClipRect`, `NewLayerInfo/DisposeLayerInfo/InitLayers`,
   `Fatten/ThinLayerInfo`, `WhichLayer`, plus graphics `SyncSBitMap/CopySBitMap` (CreateUpfrontLayer and
   MoveLayer ≈ 10–11 KB of closure). *Why*: every window; SIMPLE vs SMART vs SUPER_BITMAP
   (SuperBitMap windows of drawing and spreadsheet software), damage and BackFill. *A500 risk*:
   medium — everything goes through the real blitter (cf. 1) and through the chip RAM of the saved ClipRects.
7. **graphics — fills and ellipses**: `AreaMove`, `AreaDraw`, `AreaEnd`, `InitArea`, `InitTmpRas`,
   `Flood`, `DrawEllipse`, `AreaEllipse`, `BltPattern` and the associated RastPort fields (AreaPtrn, AOlPen,
   TmpRas) (AreaEnd ≈ 3 KB, Flood ≈ 8.7 KB of closure; **all absent on our side**). *Why*: the
   Workbench 1.3 calls `Flood` (workbench-task §3.6), drawing tools, demos and games with filled
   polygons. *A500 risk*: medium — the fill goes through the blitter in
   "fill" mode and a TmpRas in chip RAM.
8. **complete console.device + keymap.resource**: ESC/CSI sequences (cursor, clears, styles, SGR,
   scrolling, position/size report), CMD_READ (RAWKEY → string translation, dead keys,
   qualifiers), `CD_ASKKEYMAP/SETKEYMAP/ASKDEFAULTKEYMAP/SETDEFAULTKEYMAP`, `CDInputHandler`,
   `RawKeyConvert`, contents of the KeyMapResource (≈ 5.5 KB of closure; nothing specified).
   *Why*: CLI/Shell, Ed, More, NewCLI; the startup-sequence's **`SetMap`** for any non-US keyboard
   (the user is on AZERTY) goes through CD_SETDEFAULTKEYMAP [D, according to the documented use of
   SetMap, to be confirmed on WB 1.3.3]; Monkey Island expects RawKeyConvert(RETURN)
   = `$0D`. *A500 risk*: medium — a real non-US keyboard produces rawkeys that only the keymap translates.
9. **gameport.device + input.device mouse settings + potgo.resource**: `GPD_READEVENT`,
   `GPD_ASK/SETCTYPE`, `GPD_ASK/SETTRIGGER`, `IND_SETMPORT/SETMTYPE/SETMTRIG`, `AllocPotBits`,
   `FreePotBits`, `WritePotgo` (≈ 1.3 KB + 0.8 KB; gameport refuses everything on our side). *Why*: on the
   real 1.3, input.device reads the mouse **via** gameport.device (intuiticks-repeat §1.1); programs
   that read the joystick through gameport ("clean" games, controller tests); right/middle button through POTGO.
   *A500 risk*: high — real quadrature counters (bounce, overflow), POTGO lines to be
   driven as output/input for the right button, real mouse and joystick on ports 0/1.
10. **complete keyboard.device**: `KBD_READEVENT` (queues, overflow), `KBD_READMATRIX`,
    `KBD_ADD/REMRESETHANDLER`, `KBD_RESETHANDLERDONE`, special codes ($78 reset warning,
    $F9–$FE), Caps Lock LED, **value** of the handshake pulse duration (keyboard-handshake §4 only
    gives it as [D]). *Why*: the whole keyboard; Ctrl-Amiga-Amiga and the reset handlers
    (RAM disks, resident programs). *A500 risk*: **high** — a real keyboard requires a KDAT
    pulse of at least ~75–85 µs (Hardware Reference Manual) and otherwise resynchronises (lost keys), sends an initialisation sequence
    at power-on and a warning followed by a delay before pulling reset.
11. **exec — interrupts, private scheduling software, exceptions**: `ExitIntr`, `Schedule`,
    `Reschedule`, `Switch`, `Dispatch`, `Exception` (null on our side), `Cause` (SoftInt priorities),
    `SetIntVector`, `AddIntServer/RemIntServer` (semantics of the chain: Z return, is_Data, setting
    of INTENA), `Supervisor`, `SetSR`, `SuperState/UserState`, `GetCC`, `SetExcept`, `AllocTrap/FreeTrap`,
    `Debug`, `RawIOInit/RawMayGetChar/RawPutChar` (Switch ≈ 312 b, ExitIntr ≈ 160 b, Exception ≈ 108 b).
    *Why*: old 1.x code that jumps into ExitIntr or Switch, debuggers (Wack/Debug), handling
    of task exceptions (asynchronous CTRL-C), VBlank servers of games and demos. *A500 risk*: high
    — real latency and IPL levels (keyboard, serial, disk), 68010 accelerator card (different exception
    stack format; CPU detection itself = coldstart agent).
12. **audio.device**: allocation (keys, priorities, channel stealing, ADCMD_ALLOCATE/FREE/SETPREC/LOCK),
    CMD_WRITE (cycles, period, volume, ADIOF_PERVOL/SYNCCYCLE/WRITEMESSAGE), ADCMD_PERVOL/FINISH/WAITCYCLE,
    CMD_READ, AUDx interrupts (≈ 2.5 KB). *Why*: OctaMED (allocation of the 4 channels), music
    players, games, `Say`/narrator. *A500 risk*: medium — real minimum period (124), data in chip
    RAM, level 4 interrupts, audio filter linked to the LED.
13. **graphics — sprites and GELs**: `GetSprite`, `FreeSprite`, `ChangeSprite`, `MoveSprite`, SprIns;
    `InitGels`, `AddBob/AddVSprite`, `RemIBob/RemVSprite`, `SortGList`, `DrawGList`, `DoCollision`,
    `SetCollision`, `AddAnimOb`, `Animate`, `InitMasks/InitGMasks`, `GetGBuffers/FreeGBuffers`
    (DrawGList ≈ 6.5 KB, DoCollision ≈ 1.8 KB). *Why*: icon dragging in the Workbench (Bobs),
    OctaMED (6 hardware sprites), games. *A500 risk*: medium — sprites cut off by a plane fetch that is too
    early (overscan), sprite DMA and vertical reuse.
14. **exec — memory and reset survival**: `Allocate`, `Deallocate`, `AllocAbs`, `AllocEntry`,
    `FreeEntry`, `TypeOfMem`, `AddMemList`, `CopyMem`, `CopyMemQuick`, `SumKickData` (null on our side),
    `Procure/Vacate`, semaphores (`AttemptSemaphore`, `ObtainSemaphoreList`…), and the contract of
    `KickMemPtr/KickTagPtr/KickCheckSum`, `ColdCapture/CoolCapture/WarmCapture` at warm reset.
    *Why*: reset-resident programs (RAD:, virus killers that inspect KickTagPtr and the
    capture vectors), SetPatch 1.38 (AllocEntry), ramlib. *A500 risk*: medium — on real hardware the
    RAM survives Ctrl-Amiga-Amiga: ExecBase and the resident lists must be revalidated
    (coordination needed with the coldstart agent).
15. **hardware resources: disk.resource, misc.resource, cia.resource**: `AllocUnit`, `FreeUnit`,
    `GetUnitID` (identification of DF1–DF3), `AllocMiscResource/FreeMiscResource` (serial port, serial bits,
    parallel port, parallel bits), `RemICRVector`, `AbleICR`, `SetICR` (stub on our side) (≈ 70–250 b
    each). *Why*: identification of the drives present [D: exact caller to be confirmed], `serial.device` and `parallel.device`
    from DEVS: (terminal, printer), trackdisk and the keyboard for the ICR. *A500 risk*: **high** — a
    real external drive is detected by shifting its identifier on the SEL lines, and a serial cable
    plugged in for debugging conflicts with serial.device if the allocation is not respected.

### Next ones (16+)

16. graphics — text and fonts (`Text` ≈ 1.3 KB, `OpenFont`, `AddFont/RemFont/AskFont`, algorithmic
    styles `SetSoftStyle`, `ClearEOL/ClearScreen`): partly covered by fastfonts-ff.
17. ramlib.library: loading by a dedicated **process** (on our side the caller must be a process),
    expunge in low memory.
18. mathffp.library (12 functions, ≈ 1 KB): FFP format, edge cases, condition codes (programs
    compiled with FFP floating point, AmigaBASIC).
19. trackdisk: `TD_RAWREAD`, `TD_GETDRIVETYPE`, `TD_ADDCHANGEINT/REMCHANGEINT`, `TD_REMOVE` (to be
    coordinated with the write agent).
20. dos: `Exit`, `WaitForChar` (contracts already sketched in bcpl-runtime §4.3/§8.2: an implementation
    gap more than an analysis one).

## Clean-room review

- This file contains no ROM instruction sequence, no listing and no routine
  address: only public names and LVOs (`.fd`), ABI command numbers, counts of
  table entries and measured sizes in bytes.
- The mentions of `src/` describe the state of OUR implementation (reading allowed for this
  inventory); no ROM information is reinjected into it in the form of code.
- The hardware values cited as risks (keyboard pulse, minimum audio period, BBUSY) are
  public facts from the Amiga hardware documentation, not measurements of the ROM.
