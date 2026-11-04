# coverage-v34.md — Coverage inventory of the analysis documentation (Kickstart 1.3 / V34)

> ANALYSIS track ("dirty"). This document describes no new behaviour: it **inventories** what
> `docs/analysis/*.md` already specifies, what `src/` implements, and measures in the official ROM
> (`kick34005.A500`, radare2, read only) an **effort indicator** (size in bytes) for each
> function. No ROM instruction, no listing, no routine address appears in it: only
> public ABI names (`.fd`), LVOs, command numbers, counts and sizes.
>
> **Refreshed 2026-11-04 at commit `c4bdddc`.** First version: 2026-10-27 at commit `15b9e8f`. The ROM size
> columns are unchanged from the first version (the ROM does not change; radare2 was not re-run). The
> "Specified?" and "Implemented on our side" columns and the priorities were recomputed (§1).

**Changes since the previous version** (2026-10-27, `15b9e8f`):

- New specs counted: `graphics-area-v34`, `graphics-blitter-v34`, `graphics-display-v34`, `layers-v34`,
  `intuition-screens-v34`, `intuition-screenbehind-v34`, `intuition-input-menus-v34`, `intuition-misc-v34`,
  `exec-scheduling-v34`, `coldstart-hardware-v34`, `alert-v34`, `custom-chips-v34`, `resources-v34`,
  `console-keymap-v34`, `setmap-13`, `keyboard-input-devices-v34`, `gameport-device-v34`, `audio-device-v34`,
  `trackdisk-write-v34`, `trackdisk-raw-changeint-v34`, `rom-filesystem-v34`, `dos-lvo-partial-v34`,
  `dos-exit-packets-v34`, `dos-memory-v34`, `dos-cli-v34`, `softkick-real-ks13`.
- Spec coverage of the 390 LVOs: **91 → 242 specified**, 55 → 46 partial, 123 → 58 cited, 121 → 44 absent.
  Useful coverage (specified + partial) goes from 37.4 % to **73.8 %**. 151 functions moved up to "yes"
  (62 of them from "no", 56 from "cited", 33 from "partial").
- Fully specified now: layers (25/25), the four resources (cia, disk, potgo, misc), console functions,
  keymap.resource, every command of keyboard, gameport, input, console, audio and trackdisk (21/22, TD_MOTOR
  partial), alert.hook, exec scheduling and private LVOs, intuition screens, menus, input engine and misc.
- Implementation: **329 → 386** LVOs with a dedicated routine; **7 → 0** stubs; **54 → 4** null vectors.
  The graphics table now has its 109 vectors (it stopped at −636); the fills, ellipses, Flood, ClipBlit,
  ColorMap, ScrollVPort, QBlit/QBSBlit, BltPattern, SuperBitMap and AttemptLockLayerRom gaps are closed, as are
  the exec private LVOs, Debug, Procure/Vacate, SumKickData, the intuition null vectors (SetPointer, DisplayAlert,
  CloseWorkBench, MoveScreen, LockIBase…), the layers stubs, cia SetICR, console CDInputHandler and the keymap,
  trackdisk raw and change-interrupt commands. The remaining null vectors are graphicsPrivate1/2 (ROM stubs
  themselves) and dos GetPacket/QueuePacket.
- The ranked list of §7 replaces the former "next 15 analysis specs", almost all written since.
- §5: items 3 and 4 settled; items 1 and 2 still open.

## 0. Summary in figures

- **390 V34 LVOs** inventoried across the 13 modules that expose functions (of which **14 private** in the
  sense of the `.fd`s: 9 exec, 2 graphics, 2 dos, 1 expansion); **376 public**.
- Coverage by the analysis documentation: **242 specified** (62.1 %), **46 partial** (11.8 %), **58 only
  cited** as calls made by an analysed piece of software (14.9 %), **44 absent** from any spec (11.3 %).
  Useful coverage (specified + partial): **288 / 390 = 73.8 %**.
- Implementation on our side (vector tables of `src/` at `c4bdddc`): **386 / 390 = 99.0 %** have a dedicated
  routine (which does not mean complete); **0** stubs; **4** null vectors (graphicsPrivate1/2, dos
  GetPacket/QueuePacket); nothing falls outside a table any more.
- Device commands inventoried in addition: 80 (keyboard 14, gameport 14, input 17, console 13, trackdisk 22):
  **79 specified, 1 partial** (TD_MOTOR). Implemented: 75; **5 refused** by us although 1.3 implements them
  (console CMD_RESET, CMD_CLEAR, CMD_STOP, CMD_START, CMD_FLUSH). Timer (3) and audio (15) are described
  globally in §4: both fully specified and implemented.
- What remains unspecified is concentrated in: **graphics** (≈ 11.8 KB of "own" ROM code in 53 unspecified or
  partial LVOs: text and fonts, GELs/animation, regions, line drawing, SetRast), **intuition** gadget lists,
  string gadgets and window operations (small own code but large closures: RefreshGList ≈ 7.2 KB,
  SetWindowTitles ≈ 8.5 KB, CloseWindow ≈ 2.5 KB), **exec** messages/IO/semaphores/memory at AutoDoc level
  (≈ 3 KB, mostly "cited"), and **mathffp** (12 LVOs, nothing specified).

| Module | V34 LVOs | Specified | Partial | Cited | Absent | Implemented (dedicated routine) | ROM bytes reached from the vectors |
|---|--:|--:|--:|--:|--:|--:|--:|
| exec | 101 | 39 | 12 | 34 | 16 | 101 | 6,778 |
| graphics | 105 | 52 | 22 | 16 | 15 | 103 | 48,346 |
| intuition | 74 | 53 | 12 | 8 | 1 | 74 | 42,590 |
| layers | 25 | 25 | 0 | 0 | 0 | 25 | 12,776 |
| dos | 33 | 33 | 0 | 0 | 0 | 31 | n/m (BCPL) |
| expansion | 21 | 21 | 0 | 0 | 0 | 21 | 1,710 |
| mathffp | 12 | 0 | 0 | 0 | 12 | 12 | 1,042 |
| timer (functions) | 3 | 3 | 0 | 0 | 0 | 3 | 360 (whole device) |
| console (functions) | 2 | 2 | 0 | 0 | 0 | 2 | 3,658 (vectors) + 1,878 (commands) |
| cia.resource | 4 | 4 | 0 | 0 | 0 | 4 | 256 |
| disk.resource | 5 | 5 | 0 | 0 | 0 | 5 | 234 |
| potgo.resource | 3 | 3 | 0 | 0 | 0 | 3 | 178 |
| misc.resource | 2 | 2 | 0 | 0 | 0 | 2 | 68 |
| **Total** | **390** | **242** | **46** | **58** | **44** | **386** | |

The ranked list of the most valuable remaining gaps is in §7.

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

**Refresh of 2026-11-04.** Same levels and rules as above. Coverage: whole-word search of each name in the 64
`docs/analysis/*.md` pages (this page excluded), then reading of the passages; for the private exec LVOs the
public names of the `.fd` comments (`ExitIntr`, `Schedule`, `Reschedule`, `Switch`, `Dispatch`, `Exception`,
`RawIOInit`, `RawMayGetChar`, `RawPutChar`) were searched as well. An occurrence of a common English word
(`Allocate`, `Move`, `Request`…) is not counted unless it names the function. Implementation: vector tables
read from the **committed** tree (`git show HEAD:<path>`, commit `c4bdddc`; uncommitted edits of another
session were ignored), conditional assembly resolved for the default dev build (`DOSTRACE` off,
`LOADSEG_LVO_UNWIRED` = 0); exec: entries patched by `build_jumptable` in `src/exec/library.s` over the
`_unimpl` fill; devices: the command tables of each `BeginIO`. A routine of a few instructions that does the
real work (e.g. `SetAPen`, `ClearMenuStrip`) counts as "yes"; "stub" is kept for a body that only returns a
constant. Priorities: same P1/P2/P3 rules, with "absent or stub" read as "null vector, stub, or a command
refused by us that 1.3 implements".

## 2. The 24 residents of the ROM

ROM area = distance between the module's ROMTag and the next ROMTag in the ROM (code + data; for
keymap/keyboard/gameport/input, whose ROMTags are grouped, the code lives in the area following the
ROMTag of console.device: 14,196 shared bytes, split by closure indicated). Sizes unchanged from the first
version.

| # | Resident | ROM area (b) | Analysis coverage | Existing specs | On our side | Priority |
|--:|---|--:|---|---|---|:-:|
| 1 | exec.library 34.2 | 12,736 | **strong**: ExecBase ABI, boot order, scheduling and private LVOs, task context, exceptions, interrupt dispatch, softints, raw serial I/O, Debug, Procure/Vacate, SumKickData, Alert, warm-reset survival; lists, ports, messages, I/O, semaphores and memory sub-allocation only at AutoDoc level (cited) | exec-spec, exec-scheduling, coldstart-hardware, alert, custom-chips §3.3/§4.3, boot-sequence, test-vectors, module-map | `src/exec/*` (101/101 LVOs) | P3 |
| 2 | expansion.library 34.1 | 2,176 | **complete** | autoconfig-v34, uae-hd-boot | `src/exec/expansion.s` | — |
| 3 | potgo.resource | 332 | **complete** | resources §3, custom-chips §4.2 | `src/exec/potgo.s` | — |
| 4 | keymap.resource | 74 (+ init and tables in the console area) | **complete** (structure without LVO, default keymap behaviour) | console-keymap §1.1, §5 ; setmap-13 | `src/exec/keymap.s` (no function vectors, as V34; hand-authored keymaps) | — |
| 5 | cia.resource (ciaa/ciab) | 648 | **complete** | resources §1 ; timer-v34 §1, §6 ; keyboard-handshake §1–§2 | `src/exec/cia.s` | — |
| 6 | disk.resource | 872 | **complete** | resources §2 ; setpatch-disk-resource ; setpatch-138 §1.7 | `src/exec/diskres.s` | — |
| 7 | misc.resource | 268 | **complete** | resources §4 | `src/exec/misc.s` | — |
| 8 | ramlib.library | 1,564 | none (cited at boot) | boot-sequence, dos-boot-sequence | `src/exec/ramlib.s` (without its own process) | P2 |
| 9 | graphics.library 34.1 | 59,816 | **partial, strong on hardware paths**: blitter, display/copper/VBlank, fills/Flood/ellipses/pixels, sprites, colours; still missing: text and fonts, GELs and animation, regions (return value only), line drawing, SetRast | graphics-blitter, graphics-display, graphics-area, custom-chips §4.1, layers §1.1/§6/§7, fastfonts-ff, caesar-boot, monkey-startup, octamed | `src/graphics/*` (103/105, the 2 private ones null) | P2 |
| 10 | keyboard.device | common area (≈ 1.1 KB by closure) | **complete** (14 commands, handshake, reset) | keyboard-input-devices §2, keyboard-handshake | `src/exec/kbddev.s`, `keyboard.s` | — |
| 11 | gameport.device | common area (≈ 1.2 KB) | **complete** | gameport-v34, gameport-device-v34 | `src/exec/gameport.s` (14 commands) | — |
| 12 | timer.device 34.1 | 2,040 | **complete** | timer-v34 | `src/exec/timer.s` | — |
| 13 | audio.device 34.1 | 4,204 | **complete** | audio-device-v34 | `src/exec/audio.s` | — |
| 14 | input.device | common area (≈ 0.8 KB) | **complete** | keyboard-input-devices §3, intuiticks-repeat, disk-change §3 | `src/exec/input.s` | — |
| 15 | layers.library 34.1 | 13,312 | **complete** | layers-v34, installclipregion, wb-icon-clipping, intuition-gzz | `src/graphics/layers.s` | — |
| 16 | console.device | common area (≈ 5.5 KB) | **complete** (CSI automaton, keymaps, CDInputHandler, RawKeyConvert, commands) | console-keymap-v34, setmap-13, handlers-v34 §2 | `src/exec/console.s` (READ, WRITE, the 4 keymap commands, both functions; CMD_RESET/CLEAR/STOP/START/FLUSH refused) | P1 |
| 17 | trackdisk.device 34.1 | 6,908 | **complete** except TD_MOTOR (partial) | trackdisk-official-timing, trackdisk-write, trackdisk-raw-changeint, disk-change | `src/exec/trackdisk.s` (22 commands) | — |
| 18 | intuition.library 34.3 | 52,248 | **strong**: screens, input engine/IDCMP, menus, requesters, prefs, frame, GZZ, prop gadgets, pointer, IBase locks; string gadgets/ActivateGadget (intuition-strgad); still missing: CloseWindow, window operations, SetWindowTitles, rendering helpers | intuition-* (11 pages), alert-v34 §2 | `src/intuition/*` (74/74) | P2 |
| 19 | alert.hook | 658 | **complete** | alert-v34 §4, coldstart-hardware §8.4 | role played from the boot code (`alert_boothook` in `src/exec/execmisc.s`), not a separate resident | — |
| 20 | mathffp.library | 1,324 | none | — | `src/exec/mathffp.s` | P3 |
| 21 | workbench.task 34.1 | 35,302 | **strong** | workbench-task, wb-icon-clipping, disk-change §4, loadwb-13 | `src/dos/workbench.s` | — |
| 22 | dos.library 34.3 | 49,542 | **strong** (33/33 LVOs, ROM file system, CLI, handlers, memory) | dos-v34-spec, dos-lvo-partial, dos-exit-packets, dos-memory, dos-cli, rom-filesystem, bcpl-runtime, handlers, fault, boot-clock, disk-full-write | `src/dos/*` (31/33, GetPacket/QueuePacket null) | — |
| 23 | romboot.library | 1,052 | partial | uae-hd-boot §2 | `src/exec/romboot.s` | P3 |
| 24 | strap 34.4 | 2,444 | partial (DF0: attempt, RomBoot) | uae-hd-boot §3, boot-sequence, coldstart-hardware | `src/exec/strap.s` | P3 |

## 3. Tables per module (public functions)

### exec.library (101 LVOs, −30 to −630)

| LVO | Function | Specified? (file §) | Implemented on our side | ROM size (own / closure) | Priority |
|---:|---|---|---|---|:-:|
| -30 | `Supervisor` | partial — exec-scheduling §1 (privilege-violation mechanism) ; setpatch-138 §1.5 | yes | 14 / 14 | P3 |
| -36 | `execPrivate1` (= `ExitIntr`) *(private)* | yes — exec-scheduling §2.6 | yes | 124 / 162 | — |
| -42 | `execPrivate2` (= `Schedule`) *(private)* | yes — exec-scheduling §2.2 | yes | 4 / 4 (ROM stub) | — |
| -48 | `execPrivate3` (= `Reschedule`) *(private)* | yes — exec-scheduling §2.1 | yes | 48 / 48 | — |
| -54 | `execPrivate4` (= `Switch`) *(private)* | yes — exec-scheduling §2.4 | yes | 204 / 312 | — |
| -60 | `execPrivate5` (= `Dispatch`) *(private)* | yes — exec-scheduling §2.5 | yes | 18 / 18 | — |
| -66 | `execPrivate6` (= `Exception`) *(private)* | yes — exec-scheduling §5 | yes | 108 / 108 | — |
| -72 | `InitCode` | yes — boot-sequence §Phase 4 | yes | 56 / 56 | — |
| -78 | `InitStruct` | partial — module-map §Auto-init structures | yes | 74 / 74 | P3 |
| -84 | `MakeLibrary` | partial — boot-sequence §Phase 4 ; module-map §Auto-init structures | yes | 138 / 192 | P3 |
| -90 | `MakeFunctions` | partial — module-map §Auto-init structures (table format) | yes | 54 / 54 | P3 |
| -96 | `FindResident` | partial — dos-boot-sequence §Phase A | yes | 48 / 48 | P3 |
| -102 | `InitResident` | yes — boot-sequence §Phase 4 ; uae-hd-boot §5 | yes | 88 / 88 | — |
| -108 | `Alert` | yes — alert-v34 §1 ; coldstart-hardware §8 ; setpatch-138 §1.3 | yes | 1264 / 1846 | — |
| -114 | `Debug` | yes — exec-scheduling §9 ; custom-chips §4.3 | yes | 10 / 10 | — |
| -120 | `Disable` | yes — exec-spec §4 ; exec-scheduling §2.7 | yes | 14 / 14 | — |
| -126 | `Enable` | yes — exec-spec §4 ; exec-scheduling §2.7 | yes | 16 / 16 | — |
| -132 | `Forbid` | yes — exec-spec §4 ; exec-scheduling §2.7 | yes | 6 / 6 | — |
| -138 | `Permit` | yes — exec-spec §4 ; exec-scheduling §2.7 | yes | 20 / 20 | — |
| -144 | `SetSR` | no | yes | 12 / 12 | P3 |
| -150 | `SuperState` | no | yes | 12 / 12 | P3 |
| -156 | `UserState` | partial — setpatch-138 §1.5 | yes | 10 / 10 | P3 |
| -162 | `SetIntVector` | yes — custom-chips §3.3 ; graphics-blitter §9.3 | yes | 70 / 70 | — |
| -168 | `AddIntServer` | yes — custom-chips §3.1, §3.3 ; exec-scheduling §8 | yes | 64 / 102 | — |
| -174 | `RemIntServer` | yes — custom-chips §3.1, §3.3 ; exec-scheduling §8 | yes | 72 / 86 | — |
| -180 | `Cause` | yes — custom-chips §3.3 ; exec-scheduling §8 ; trackdisk-raw-changeint §5.4 | yes | 96 / 96 | — |
| -186 | `Allocate` | no | yes | 82 / 82 | P3 |
| -192 | `Deallocate` | no | yes | 236 / 318 | P2 |
| -198 | `AllocMem` | yes — exec-spec §4 ; dos-memory §1.1 | yes | 236 / 318 | — |
| -204 | `AllocAbs` | cited — setpatch-138 §1.1 ; coldstart-hardware §5.3 ; exec-scheduling §7 | yes | 144 / 144 | P3 |
| -210 | `FreeMem` | yes — exec-spec §4 Memory management | yes | 64 / 382 | — |
| -216 | `AvailMem` | yes — exec-spec §4 Memory management | yes | 78 / 78 | — |
| -222 | `AllocEntry` | partial — setpatch-138 §1.4 ; dos-memory §2 | yes | 142 / 142 | P3 |
| -228 | `FreeEntry` | partial — setpatch-138 §Requirements | yes | 62 / 62 | P3 |
| -234 | `Insert` | cited — workbench-task §3.6 | yes | 60 / 60 | P3 |
| -240 | `AddHead` | yes — exec-spec §4 Doubly linked lists | yes | 60 / 60 | — |
| -246 | `AddTail` | yes — exec-spec §4 Doubly linked lists | yes | 24 / 24 | — |
| -252 | `Remove` | yes — exec-spec §4 Doubly linked lists | yes | 14 / 14 | — |
| -258 | `RemHead` | cited — uae-hd-boot §4.1 | yes | 16 / 16 | P3 |
| -264 | `RemTail` | cited — workbench-task §3.1 | yes | 22 / 22 | P3 |
| -270 | `Enqueue` | yes — exec-spec §4 Doubly linked lists | yes | 38 / 38 | — |
| -276 | `FindName` | yes — exec-spec §4 Doubly linked lists ; setpatch-138 §1.6 | yes | 40 / 40 | — |
| -282 | `AddTask` | yes — exec-scheduling §2.7, §4.2 ; workbench-task §1.3 | yes | 164 / 202 | — |
| -288 | `RemTask` | yes — exec-scheduling §2.7 ; bcpl-runtime §13.7 | yes | 122 / 136 | — |
| -294 | `FindTask` | cited — loadwb-13 §1 | yes | 84 / 84 | P3 |
| -300 | `SetTaskPri` | yes — exec-scheduling §2.7 | yes | 80 / 132 | — |
| -306 | `SetSignal` | yes — exec-scheduling §2.7 | yes | 8 / 8 | — |
| -312 | `SetExcept` | yes — exec-scheduling §2.7, §5 | yes | 156 / 194 | — |
| -318 | `Wait` | yes — exec-scheduling §2.7 | yes | 104 / 104 | — |
| -324 | `Signal` | yes — exec-scheduling §2.7 | yes | 20 / 20 | — |
| -330 | `AllocSignal` | cited — workbench-task §3.1 | yes | 56 / 56 | P3 |
| -336 | `FreeSignal` | cited — intuition-misc §4 | yes | 16 / 16 | P3 |
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
| -504 | `execPrivate7` (= `RawIOInit`) *(private)* | yes — custom-chips §4.3 ; exec-scheduling §9 | yes | 10 / 10 | — |
| -510 | `execPrivate8` (= `RawMayGetChar`) *(private)* | yes — custom-chips §4.3 | yes | 32 / 32 | — |
| -516 | `execPrivate9` (= `RawPutChar`) *(private)* | yes — custom-chips §4.3 | yes | 70 / 120 | — |
| -522 | `RawDoFmt` | cited — workbench-task §3.4 | yes | 214 / 452 | P2 |
| -528 | `GetCC` | no | yes | 8 / 8 | P3 |
| -534 | `TypeOfMem` | cited — softkick-real-ks13 §Conclusions | yes | 38 / 38 | P3 |
| -540 | `Procure` | yes — exec-scheduling §6 | yes | 22 / 22 | — |
| -546 | `Vacate` | yes — exec-scheduling §6 | yes | 34 / 34 | — |
| -552 | `OpenLibrary` | cited — caesar-boot §1 ; dos-boot-sequence | yes | 46 / 86 | P3 |
| -558 | `InitSemaphore` | cited — autoconfig-v34 §1 | yes | 32 / 32 | P3 |
| -564 | `ObtainSemaphore` | cited — autoconfig-v34 §7 | yes | 80 / 104 | P3 |
| -570 | `ReleaseSemaphore` | cited — autoconfig-v34 §7 | yes | 100 / 116 | P3 |
| -576 | `AttemptSemaphore` | no | yes | 48 / 48 | P3 |
| -582 | `ObtainSemaphoreList` | cited — layers §7 | yes | 118 / 142 | P3 |
| -588 | `ReleaseSemaphoreList` | cited — layers §7 | yes | 22 / 22 | P3 |
| -594 | `FindSemaphore` | no | yes | 10 / 10 | P3 |
| -600 | `AddSemaphore` | no | yes | 12 / 12 | P3 |
| -606 | `RemSemaphore` | no | yes | 4 / 32 | P3 |
| -612 | `SumKickData` | yes — exec-scheduling §7 ; coldstart-hardware §5.3 | yes | 88 / 88 | — |
| -618 | `AddMemList` | partial — autoconfig-v34 §4 | yes | 84 / 134 | P3 |
| -624 | `CopyMem` | cited — autoconfig-v34 §6 | yes | 38 / 112 | P3 |
| -630 | `CopyMemQuick` | no | yes | 4 / 78 | P3 |

### graphics.library (105 LVOs, −30 to −654)

| LVO | Function | Specified? (file §) | Implemented on our side | ROM size (own / closure) | Priority |
|---:|---|---|---|---|:-:|
| -30 | `BltBitMap` | yes — graphics-blitter §1 | yes | 406 / 1680 | — |
| -36 | `BltTemplate` | yes — graphics-blitter §6 ; fastfonts-ff §2 | yes | 692 / 1864 | — |
| -42 | `ClearEOL` | no | yes | 56 / 120 | P3 |
| -48 | `ClearScreen` | no | yes | 66 / 130 | P3 |
| -54 | `TextLength` | cited — intuition-frame §3.2 ; workbench-task §3.1 | yes | 96 / 96 | P3 |
| -60 | `Text` | partial — fastfonts-ff §1–§4 ; caesar-boot §2.4 ; console-keymap §3.8 (slicing) | yes | 1028 / 1288 | P2 |
| -66 | `SetFont` | partial — setpatch-138 §1.9 (NULL arguments, fixed by SetPatch) | yes | 28 / 28 | P3 |
| -72 | `OpenFont` | cited — preferences-13 §4 ; fastfonts-ff ; intuition-screens §2.5 | yes | 170 / 170 | P3 |
| -78 | `CloseFont` | cited — intuition-prefs §3.3 ; workbench-task §3.1 | yes | 30 / 30 | P3 |
| -84 | `AskSoftStyle` | partial — setpatch-138 §1.9 | yes | 36 / 36 | P3 |
| -90 | `SetSoftStyle` | partial — setpatch-138 §1.9 ; console-keymap §3.7 | yes | 50 / 50 | P3 |
| -96 | `AddBob` | cited — workbench-task §3.6 | yes | 14 / 116 | P3 |
| -102 | `AddVSprite` | no | yes | 14 / 88 | P3 |
| -108 | `DoCollision` | partial — custom-chips §4.1 (software only, blitter overlap test) | yes | 1330 / 1824 | P2 |
| -114 | `DrawGList` | partial — custom-chips §4.1 (VSprite copper output; band allocation open) ; graphics-blitter §9.4 | yes | 3098 / 6552 | P2 |
| -120 | `InitGels` | cited — workbench-task §3.1 | yes | 122 / 122 | P3 |
| -126 | `InitMasks` | no | yes | 12 / 246 | P3 |
| -132 | `RemIBob` | cited — workbench-task §3.6 | yes | 70 / 3166 | P2 |
| -138 | `RemVSprite` | no | yes | 12 / 32 | P3 |
| -144 | `SetCollision` | partial — custom-chips §4.1 (fills the GelsInfo table only) | yes | 42 / 42 | P3 |
| -150 | `SortGList` | cited — workbench-task §3.6 | yes | 190 / 190 | P3 |
| -156 | `AddAnimOb` | no | yes | 96 / 198 | P3 |
| -162 | `Animate` | no | yes | 468 / 570 | P2 |
| -168 | `GetGBuffers` | no | yes | 350 / 382 | P2 |
| -174 | `InitGMasks` | no | yes | 70 / 304 | P2 |
| -180 | `DrawEllipse` | yes — graphics-area §6 | yes | 22 / 672 | — |
| -186 | `AreaEllipse` | yes — graphics-area §3.3 | yes | 188 / 188 | — |
| -192 | `LoadRGB4` | yes — graphics-display §3 | yes | 272 / 676 | — |
| -198 | `InitRastPort` | partial — layers §2.4 (clears 78 bytes) | yes | 10 / 86 | P3 |
| -204 | `InitVPort` | yes — graphics-display §1.2 | yes | 16 / 52 | — |
| -210 | `MrgCop` | yes — graphics-display §5 ; setpatch-138 §1.9 | yes | 1354 / 1474 | — |
| -216 | `MakeVPort` | yes — graphics-display §4 | yes | 2554 / 3722 | — |
| -222 | `LoadView` | yes — graphics-display §7.1 ; caesar-boot §2.7 | yes | 282 / 434 | — |
| -228 | `WaitBlit` | yes — graphics-blitter §2 | yes | 36 / 36 | — |
| -234 | `SetRast` | cited — layers §5.1 ; wb-icon-clipping §5 | yes | 646 / 1160 | P2 |
| -240 | `Move` | cited — graphics-area §4.6, §8 | yes | 20 / 20 | P3 |
| -246 | `Draw` | cited — graphics-area §4.6, §8 | yes | 2424 / 3494 | P2 |
| -252 | `AreaMove` | yes — graphics-area §3.1 | yes | 148 / 148 | — |
| -258 | `AreaDraw` | yes — graphics-area §3.2 | yes | 80 / 80 | — |
| -264 | `AreaEnd` | yes — graphics-area §4 | yes | 1260 / 3056 | — |
| -270 | `WaitTOF` | yes — graphics-display §7.4 ; sysinfo-44 §1.3 | yes | 120 / 236 | — |
| -276 | `QBlit` | yes — graphics-blitter §9.2 | yes | 22 / 638 | — |
| -282 | `InitArea` | yes — graphics-area §2 | yes | 30 / 30 | — |
| -288 | `SetRGB4` | yes — graphics-display §3 | yes | 336 / 794 | — |
| -294 | `QBSBlit` | yes — graphics-blitter §9.4 ; timer-v34 §6.2 | yes | 220 / 836 | — |
| -300 | `BltClear` | yes — graphics-blitter §4 | yes | 224 / 684 | — |
| -306 | `RectFill` | partial — graphics-area §8 (outline mode) | yes | 180 / 234 | P3 |
| -312 | `BltPattern` | yes — graphics-blitter §8 ; graphics-area §5 | yes | 3648 / 4654 | — |
| -318 | `ReadPixel` | yes — graphics-area §9.2 | yes | 264 / 300 | — |
| -324 | `WritePixel` | yes — graphics-area §9.1 | yes | 352 / 812 | — |
| -330 | `Flood` | yes — graphics-area §7 | yes | 5634 / 8750 | — |
| -336 | `PolyDraw` | cited — octamed §2.3 | yes | 32 / 32 | P3 |
| -342 | `SetAPen` | partial — graphics-blitter §6 (rp_minterms precomputed) | yes | 6 / 78 | P3 |
| -348 | `SetBPen` | partial — graphics-blitter §6 (rp_minterms precomputed) | yes | 6 / 78 | P3 |
| -354 | `SetDrMd` | partial — graphics-blitter §6 (rp_minterms precomputed) | yes | 4 / 4 (ROM stub) | P3 |
| -360 | `InitView` | yes — graphics-display §1.1 ; intuition-prefs §1 | yes | 22 / 58 | — |
| -366 | `CBump` | yes — graphics-display §6 | yes | 54 / 300 | — |
| -372 | `CMove` | yes — graphics-display §6 | yes | 76 / 366 | — |
| -378 | `CWait` | yes — graphics-display §6 | yes | 78 / 368 | — |
| -384 | `VBeamPos` | yes — graphics-display §7.4 ; custom-chips §3.6 | yes | 16 / 16 | — |
| -390 | `InitBitMap` | partial — fastfonts-ff §3 (BytesPerRow) | yes | 22 / 22 | P3 |
| -396 | `ScrollRaster` | partial — console-keymap §3.7 (BPen fill) | yes | 142 / 380 | P2 |
| -402 | `WaitBOVP` | yes — graphics-display §7.4 | yes | 6 / 62 | — |
| -408 | `GetSprite` | yes — custom-chips §4.1 | yes | 136 / 168 | — |
| -414 | `FreeSprite` | yes — custom-chips §4.1 | yes | 68 / 132 | — |
| -420 | `ChangeSprite` | yes — custom-chips §4.1 ; intuition-misc §3.3 | yes | 68 / 772 | — |
| -426 | `MoveSprite` | yes — custom-chips §4.1 | yes | 20 / 724 | — |
| -432 | `LockLayerRom` | yes — layers §7 ; fastfonts-ff §2 | yes | 22 / 22 | — |
| -438 | `UnlockLayerRom` | yes — layers §7 | yes | 22 / 22 | — |
| -444 | `SyncSBitMap` | yes — layers §6 | yes | 12 / 2778 | — |
| -450 | `CopySBitMap` | yes — layers §6 | yes | 12 / 1014 | — |
| -456 | `OwnBlitter` | yes — graphics-blitter §3 | yes | 24 / 236 | — |
| -462 | `DisownBlitter` | yes — graphics-blitter §3 | yes | 104 / 234 | — |
| -468 | `InitTmpRas` | yes — graphics-area §2 | yes | 12 / 12 | — |
| -474 | `AskFont` | no | yes | 18 / 18 | P3 |
| -480 | `AddFont` | no | yes | 58 / 58 | P3 |
| -486 | `RemFont` | no | yes | 78 / 78 | P3 |
| -492 | `AllocRaster` | cited — monkey-startup §2 ; intuition-input-menus §3.5 | yes | 18 / 32 | P3 |
| -498 | `FreeRaster` | cited — caesar-boot §1 | yes | 20 / 34 | P3 |
| -504 | `AndRectRegion` | partial — layers §1.1 (return value) | yes | 16 / 1510 | P2 |
| -510 | `OrRectRegion` | partial — layers §1.1 (return value) | yes | 16 / 1278 | P2 |
| -516 | `NewRegion` | cited — layers §1 ; wb-icon-clipping §1 | yes | 20 / 42 | P3 |
| -522 | `ClearRectRegion` | partial — layers §1.1 (return value) | yes | 82 / 2582 | P2 |
| -528 | `ClearRegion` | cited — installclipregion §4.1 ; layers §5.2 | yes | 12 / 110 | P3 |
| -534 | `DisposeRegion` | cited — wb-icon-clipping §2 | yes | 12 / 142 | P3 |
| -540 | `FreeVPortCopLists` | yes — graphics-display §6 | yes | 128 / 214 | — |
| -546 | `FreeCopList` | yes — graphics-display §6 | yes | 14 / 100 | — |
| -552 | `ClipBlit` | yes — graphics-blitter §5.3 | yes | 370 / 3206 | — |
| -558 | `XorRectRegion` | partial — layers §1.1 (return value) | yes | 16 / 1814 | P2 |
| -564 | `FreeCprList` | yes — graphics-display §6 | yes | 74 / 98 | — |
| -570 | `GetColorMap` | yes — graphics-display §3 | yes | 88 / 88 | — |
| -576 | `FreeColorMap` | yes — graphics-display §3 | yes | 36 / 36 | — |
| -582 | `GetRGB4` | yes — graphics-display §3 | yes | 24 / 24 | — |
| -588 | `ScrollVPort` | yes — graphics-display §7.3 | yes | 2362 / 3442 | — |
| -594 | `UCopperListInit` | yes — graphics-display §6 | yes | 16 / 306 | — |
| -600 | `FreeGBuffers` | no | yes | 254 / 264 | P3 |
| -606 | `BltBitMapRastPort` | yes — graphics-blitter §5.2 | yes | 272 / 3108 | — |
| -612 | `OrRegionRegion` | partial — layers §1.1 (return value) | yes | 16 / 1370 | P2 |
| -618 | `XorRegionRegion` | partial — layers §1.1 (return value) | yes | 16 / 1906 | P2 |
| -624 | `AndRegionRegion` | partial — layers §1.1 (return value) | yes | 226 / 2326 | P2 |
| -630 | `SetRGB4CM` | yes — graphics-display §3 | yes | 54 / 54 | — |
| -636 | `BltMaskBitMapRastPort` | yes — graphics-blitter §5.4 | yes | 470 / 3306 | — |
| -642 | `graphicsPrivate1` *(private)* | no | no (null vector) | 4 / 4 (ROM stub) | P3 |
| -648 | `graphicsPrivate2` *(private)* | no | no (null vector) | 4 / 4 (ROM stub) | P3 |
| -654 | `AttemptLockLayerRom` | partial — layers §1.1 (return value) | yes | 22 / 22 | P3 |

### intuition.library (74 LVOs, −30 to −468)

| LVO | Function | Specified? (file §) | Implemented on our side | ROM size (own / closure) | Priority |
|---:|---|---|---|---|:-:|
| -30 | `OpenIntuition` | yes — intuition-misc §1 | yes (= library Open, as 1.3) | 18 / 2530 | — |
| -36 | `Intuition` | yes — intuition-input-menus §1–§2 ; intuition-misc §2 | yes | 15324 / 28100 | — |
| -42 | `AddGadget` | yes — intuition-gadgets §2 | yes | 62 / 474 | — |
| -48 | `ClearDMRequest` | yes — intuition-requesters §4.4 | yes | 30 / 76 | — |
| -54 | `ClearMenuStrip` | yes — intuition-input-menus §3.2 | yes | 44 / 164 | — |
| -60 | `ClearPointer` | yes — intuition-misc §3 | yes | 66 / 922 | — |
| -66 | `CloseScreen` | yes — intuition-screens §6.1 | yes | 54 / 12322 | — |
| -72 | `CloseWindow` | partial — intuition-input-menus §1.10, §2.2 ; workbench-task §6.8 ; intuition-requesters §5.1 | yes | 12 / 2550 | P2 |
| -78 | `CloseWorkBench` | yes — intuition-screens §6.2 ; workbench-task §4 | yes | 84 / 12352 | — |
| -84 | `CurrentTime` | yes — intuition-misc §5 | yes | 38 / 38 | — |
| -90 | `DisplayAlert` | yes — alert-v34 §2 | yes | 18 / 2330 | — |
| -96 | `DisplayBeep` | yes — intuition-screens §9 ; intuition-input-menus §1.3 | yes | 12 / 332 | — |
| -102 | `DoubleClick` | yes — intuition-input-menus §2.6 ; intuition-prefs §3.3 | yes | 86 / 86 | — |
| -108 | `DrawBorder` | partial — intuition-gzz §6.1 | yes | 20 / 572 | P2 |
| -114 | `DrawImage` | partial — intuition-gzz §6.1 ; intuition-prop §3.1 | yes | 20 / 700 | P2 |
| -120 | `EndRequest` | yes — intuition-requesters §4 | yes | 14 / 668 | — |
| -126 | `GetDefPrefs` | yes — intuition-prefs §4.2 | yes | 68 / 260 | — |
| -132 | `GetPrefs` | yes — intuition-prefs §4.1 | yes | 50 / 154 | — |
| -138 | `InitRequester` | yes — intuition-requesters §4.3 | yes | 12 / 26 | — |
| -144 | `ItemAddress` | yes — intuition-input-menus §3.2 | yes | 14 / 244 | — |
| -150 | `ModifyIDCMP` | yes — intuition-input-menus §2.6, §2.2 | yes | 14 / 1014 | — |
| -156 | `ModifyProp` | yes — intuition-prop §5 | yes | 6 / 6 | — |
| -162 | `MoveScreen` | yes — intuition-screens §8.2 | yes | 18 / 804 | — |
| -168 | `MoveWindow` | partial — intuition-input-menus §1.10 (deferred) ; installclipregion §4.2 | yes | 74 / 288 | P3 |
| -174 | `OffGadget` | yes — intuition-gadgets §6 ; intuition-gzz §6.4 | yes | 42 / 7246 | — |
| -180 | `OffMenu` | yes — intuition-input-menus §3.2 | yes | 40 / 486 | — |
| -186 | `OnGadget` | yes — intuition-gadgets §6 ; intuition-gzz §6.4 | yes | 42 / 7246 | — |
| -192 | `OnMenu` | yes — intuition-input-menus §3.2 | yes | 42 / 488 | — |
| -198 | `OpenScreen` | yes — intuition-screens §2 ; intuition-screenbehind | yes | 12 / 10462 | — |
| -204 | `OpenWindow` | yes — intuition-frame §2 ; intuition-gzz §1–§2 | yes | 12 / 15640 | — |
| -210 | `OpenWorkBench` | yes — intuition-screens §7.2 | yes | 6 / 11734 | — |
| -216 | `PrintIText` | partial — intuition-gzz §6.1 ; intuition-requesters §2.3 | yes | 20 / 802 | P2 |
| -222 | `RefreshGadgets` | yes — intuition-gadgets §5 ; intuition-gzz §6.2 | yes | 16 / 7220 | — |
| -228 | `RemoveGadget` | yes — intuition-gadgets §4 | yes | 48 / 498 | — |
| -234 | `ReportMouse` | yes — intuition-input-menus §2.6 | yes | 66 / 94 | — |
| -240 | `Request` | yes — intuition-requesters §2–§3 | yes | 14 / 8662 | — |
| -246 | `ScreenToBack` | yes — intuition-screens §8.1 | yes | 12 / 956 | — |
| -252 | `ScreenToFront` | yes — intuition-screens §8.1 ; intuition-screenbehind | yes | 32 / 984 | — |
| -258 | `SetDMRequest` | yes — intuition-requesters §4.4 | yes | 36 / 82 | — |
| -264 | `SetMenuStrip` | yes — intuition-input-menus §3.2 | yes | 224 / 1446 | — |
| -270 | `SetPointer` | yes — intuition-misc §3 | yes | 96 / 952 | — |
| -276 | `SetWindowTitles` | partial — intuition-frame §3.2 ; workbench-task §6.6 | yes | 122 / 8486 | P2 |
| -282 | `ShowTitle` | yes — intuition-screens §3.2 | yes | 86 / 7914 | — |
| -288 | `SizeWindow` | partial — intuition-gzz §2.5 ; intuition-input-menus §1.10 | yes | 74 / 288 | P3 |
| -294 | `ViewAddress` | yes — intuition-screens §9 | yes | 16 / 16 | — |
| -300 | `ViewPortAddress` | yes — intuition-screens §9 | yes | 28 / 28 | — |
| -306 | `WindowToBack` | partial — intuition-input-menus §1.10 (deferred) | yes | 36 / 250 | P3 |
| -312 | `WindowToFront` | partial — intuition-input-menus §1.10 (deferred) | yes | 36 / 250 | P3 |
| -318 | `WindowLimits` | no | yes | 18 / 142 | P3 |
| -324 | `SetPrefs` | yes — intuition-prefs §3 | yes | 98 / 2530 | — |
| -330 | `IntuiTextLength` | cited — intuition-input-menus §3.5 | yes | 12 / 672 | P2 |
| -336 | `WBenchToBack` | yes — intuition-screens §7.3 | yes | 6 / 1020 | — |
| -342 | `WBenchToFront` | yes — intuition-screens §7.3 | yes | 6 / 1030 | — |
| -348 | `AutoRequest` | yes — intuition-requesters §5.1 | yes | 270 / 20666 | — |
| -354 | `BeginRefresh` | partial — intuition-gzz §2.5 (test vectors) | yes | 12 / 168 | P3 |
| -360 | `BuildSysRequest` | yes — intuition-requesters §5.2 | yes | 20 / 20004 | — |
| -366 | `EndRefresh` | partial — intuition-gzz §2.5 (test vectors) | yes | 14 / 136 | P3 |
| -372 | `FreeSysRequest` | yes — intuition-requesters §5.4 | yes | 12 / 2964 | — |
| -378 | `MakeScreen` | yes — intuition-screens §5.2 | yes | 12 / 322 | — |
| -384 | `RemakeDisplay` | yes — intuition-screens §5.2 | yes | 6 / 802 | — |
| -390 | `RethinkDisplay` | yes — intuition-screens §5.2 | yes | 6 / 6 | — |
| -396 | `AllocRemember` | cited — intuition-screens §2.1 ; intuition-requesters §5.2 | yes | 18 / 164 | P3 |
| -402 | `AlohaWorkbench` | yes — intuition-misc §4 | yes | 24 / 24 | — |
| -408 | `FreeRemember` | cited — intuition-requesters §5.4 | yes | 14 / 102 | P3 |
| -414 | `LockIBase` | yes — intuition-misc §6 ; intuition-screens §9 | yes | 60 / 120 | — |
| -420 | `UnlockIBase` | yes — intuition-misc §6 | yes | 54 / 114 | — |
| -426 | `GetScreenData` | yes — intuition-screens §7.5 | yes | 112 / 11840 | — |
| -432 | `RefreshGList` | yes — intuition-gadgets §5 | yes | 48 / 7222 | — |
| -438 | `AddGList` | yes — intuition-gadgets §3 | yes | 20 / 432 | — |
| -444 | `RemoveGList` | yes — intuition-gadgets §4 | yes | 18 / 468 | — |
| -450 | `ActivateWindow` | yes — intuition-frame §4.1 ; intuition-input-menus §1.11 | yes | 38 / 252 | — |
| -456 | `RefreshWindowFrame` | yes — intuition-frame §2 | yes | 28 / 8686 | — |
| -462 | `ActivateGadget` | yes — intuition-strgad §1 (string-gadget engine §2–§5) | yes | 236 / 1232 | — |
| -468 | `NewModifyProp` | yes — intuition-prop §5 | yes | 82 / 7256 | — |

### layers.library (25 LVOs, −30 to −174)

| LVO | Function | Specified? (file §) | Implemented on our side | ROM size (own / closure) | Priority |
|---:|---|---|---|---|:-:|
| -30 | `InitLayers` | yes — layers §5.10 | yes | 10 / 120 | — |
| -36 | `CreateUpfrontLayer` | yes — layers §5.2 ; intuition-gzz §2 | yes | 118 / 10140 | — |
| -42 | `CreateBehindLayer` | yes — layers §5.1 | yes | 20 / 9850 | — |
| -48 | `UpfrontLayer` | yes — layers §5.3 | yes | 10 / 6284 | — |
| -54 | `BehindLayer` | yes — layers §5.3 | yes | 90 / 6296 | — |
| -60 | `MoveLayer` | yes — layers §5.6 | yes | 320 / 10916 | — |
| -66 | `SizeLayer` | yes — layers §5.7 | yes | 618 / 11232 | — |
| -72 | `ScrollLayer` | yes — layers §5.8 | yes | 108 / 1136 | — |
| -78 | `BeginUpdate` | yes — layers §5.5 ; installclipregion §4.1 | yes | 56 / 2640 | — |
| -84 | `EndUpdate` | yes — layers §5.5 ; installclipregion §4.1 | yes | 76 / 2678 | — |
| -90 | `DeleteLayer` | yes — layers §3.4, §5.4 ; setpatch-138 §1.8 | yes | 10 / 7432 | — |
| -96 | `LockLayer` | yes — layers §7 | yes | 10 / 32 | — |
| -102 | `UnlockLayer` | yes — layers §7 | yes | 10 / 32 | — |
| -108 | `LockLayers` | yes — layers §7 ; installclipregion §4.2 | yes | 10 / 710 | — |
| -114 | `UnlockLayers` | yes — layers §7 | yes | 10 / 2392 | — |
| -120 | `LockLayerInfo` | yes — layers §7 | yes | 10 / 44 | — |
| -126 | `SwapBitsRastPortClipRect` | yes — layers §5.12 | yes | 12 / 320 | — |
| -132 | `WhichLayer` | yes — layers §5.9 | yes | 46 / 46 | — |
| -138 | `UnlockLayerInfo` | yes — layers §7 | yes | 10 / 44 | — |
| -144 | `NewLayerInfo` | yes — layers §5.10 | yes | 72 / 314 | — |
| -150 | `DisposeLayerInfo` | yes — layers §5.10 | yes | 40 / 116 | — |
| -156 | `FattenLayerInfo` | yes — layers §5.10 | yes | 44 / 176 | — |
| -162 | `ThinLayerInfo` | yes — layers §5.10 | yes | 34 / 110 | — |
| -168 | `MoveLayerInFrontOf` | yes — layers §5.3 | yes | 84 / 6230 | — |
| -174 | `InstallClipRegion` | yes — installclipregion §1–§7 ; layers §7 | yes | 78 / 2684 | — |

### dos.library (33 LVOs, −30 to −222)

Sizes: each dos LVO is a thin bridge to a BCPL global (bcpl-runtime §1.4); the size of the BCPL code is not measured here ("n/m" column).

| LVO | Function | Specified? (file §) | Implemented on our side | ROM size (own / closure) | Priority |
|---:|---|---|---|---|:-:|
| -30 | `Open` | yes — dos-v34-spec §2–§3 ; bcpl-runtime §5.1 ; dos-memory §2.1 | yes | n/m | — |
| -36 | `Close` | yes — bcpl-runtime §5.1 ; dos-v34-spec §2b ; dos-memory §2.1 | yes | n/m | — |
| -42 | `Read` | yes — dos-v34-spec §3 ; bcpl-runtime §5.1 | yes | n/m | — |
| -48 | `Write` | yes — disk-full-write §3 ; bcpl-runtime §6.1 | yes | n/m | — |
| -54 | `Input` | yes — dos-lvo-partial-v34 §2.1 ; bcpl-runtime §8.1 | yes | n/m | — |
| -60 | `Output` | yes — dos-lvo-partial-v34 §2.1 ; bcpl-runtime §8.1 | yes | n/m | — |
| -66 | `Seek` | yes — dos-lvo-partial-v34 §2.2 ; bcpl-runtime §8.3 ; disk-full-write §1 | yes | n/m | — |
| -72 | `DeleteFile` | yes — dos-lvo-partial-v34 §2.3 ; bcpl-runtime §8.3 | yes | n/m | — |
| -78 | `Rename` | yes — dos-lvo-partial-v34 §2.4 ; bcpl-runtime §8.4.2 | yes | n/m | — |
| -84 | `Lock` | yes — dos-v34-spec §2b ; disk-change §2.4 ; dos-memory §2.2 | yes | n/m | — |
| -90 | `UnLock` | yes — dos-v34-spec §2b ; dos-memory §2.2 | yes | n/m | — |
| -96 | `DupLock` | yes — dos-lvo-partial-v34 §2.5 ; bcpl-runtime §8.2 | yes | n/m | — |
| -102 | `Examine` | yes — dos-v34-spec §2b | yes | n/m | — |
| -108 | `ExNext` | yes — dos-v34-spec §2b | yes | n/m | — |
| -114 | `Info` | yes — dos-lvo-partial-v34 §2.6 ; bcpl-runtime §8.3 ; disk-change §2.3 | yes | n/m | — |
| -120 | `CreateDir` | yes — dos-lvo-partial-v34 §2.7 ; bcpl-runtime §8.3 | yes | n/m | — |
| -126 | `CurrentDir` | yes — dos-lvo-partial-v34 §2.8 ; bcpl-runtime §8.3 | yes | n/m | — |
| -132 | `IoErr` | yes — dos-lvo-partial-v34 §2.9 ; bcpl-runtime §8.3 | yes | n/m | — |
| -138 | `CreateProc` | yes — dos-v34-spec §4 ; bcpl-runtime §8.1 ; workbench-task §1.3 ; dos-memory §2.4 | yes | n/m | — |
| -144 | `Exit` | yes — dos-exit-packets §1 ; bcpl-runtime §4.3, §8.1 | yes | n/m | — |
| -150 | `LoadSeg` | yes — dos-memory §3 (allocation, hunk memory bits, BSS, failures) ; bcpl-runtime §3 ; dos-boot-sequence §Phase E | yes | n/m | — |
| -156 | `UnLoadSeg` | yes — dos-lvo-partial-v34 §2.10 ; bcpl-runtime §8.2 ; dos-memory §3.5 | yes | n/m | — |
| -162 | `dosPrivate1` (= `GetPacket`) *(private)* | yes — dos-exit-packets §3 (BCPL global −20, `clearvec`) ; bcpl-runtime §1.4 | no (returns 0; no WB 1.3.3 caller) | n/m | — |
| -168 | `dosPrivate2` (= `QueuePacket`) *(private)* | yes — dos-exit-packets §3 (BCPL global −21, segment load by BSTR name) ; bcpl-runtime §1.4 | no (returns 0; no WB 1.3.3 caller) | n/m | — |
| -174 | `DeviceProc` | yes — handlers-v34 §4.1 | yes | n/m | — |
| -180 | `SetComment` | yes — dos-lvo-partial-v34 §2.11 ; bcpl-runtime §8.3 | yes | n/m | — |
| -186 | `SetProtection` | yes — dos-lvo-partial-v34 §2.12 ; bcpl-runtime §8.3 | yes | n/m | — |
| -192 | `DateStamp` | yes — bcpl-runtime §8.4.2 ; boot-clock | yes | n/m | — |
| -198 | `Delay` | yes — dos-lvo-partial-v34 §2.13 ; bcpl-runtime §8.1 | yes | n/m | — |
| -204 | `WaitForChar` | yes — dos-exit-packets §2 ; bcpl-runtime §8.2 | yes | n/m | — |
| -210 | `ParentDir` | yes — dos-lvo-partial-v34 §2.14 ; dos-v34-spec §2b ; bcpl-runtime §8.1 | yes | n/m | — |
| -216 | `IsInteractive` | yes — dos-lvo-partial-v34 §2.15 ; bcpl-runtime §5.1 | yes | n/m | — |
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
| -90 | `SPFloor` | no | yes | 86 / 366 | P2 |
| -96 | `SPCeil` | no | yes | 10 / 376 | P2 |

### timer.device — functions (3 LVOs, −42 to −54)

| LVO | Function | Specified? (file §) | Implemented on our side | ROM size (own / closure) | Priority |
|---:|---|---|---|---|:-:|
| -42 | `AddTime` | yes — timer-v34 §5 | yes | 36 / 36 | — |
| -48 | `SubTime` | yes — timer-v34 §5 | yes | 28 / 28 | — |
| -54 | `CmpTime` | yes — timer-v34 §5 | yes | 28 / 28 | — |

### console.device — functions (2 LVOs, −42 to −48)

| LVO | Function | Specified? (file §) | Implemented on our side | ROM size (own / closure) | Priority |
|---:|---|---|---|---|:-:|
| -42 | `CDInputHandler` | yes — console-keymap §6 | yes | 706 / 1000 | — |
| -48 | `RawKeyConvert` | yes — console-keymap §5.2–§5.3 ; setmap-13 §5.2 | yes | 516 / 516 | — |

### cia.resource (ciaa/ciab, 4 LVOs, −6 to −24)

| LVO | Function | Specified? (file §) | Implemented on our side | ROM size (own / closure) | Priority |
|---:|---|---|---|---|:-:|
| -6 | `AddICRVector` | yes — resources §1.4 ; keyboard-handshake §1–§2 | yes | 58 / 184 | — |
| -12 | `RemICRVector` | yes — resources §1.5 | yes | 36 / 162 | — |
| -18 | `AbleICR` | yes — resources §1.6 | yes | 98 / 98 | — |
| -24 | `SetICR` | yes — resources §1.7 | yes | 36 / 36 | — |

### disk.resource (5 LVOs, −6 to −30)

| LVO | Function | Specified? (file §) | Implemented on our side | ROM size (own / closure) | Priority |
|---:|---|---|---|---|:-:|
| -6 | `AllocUnit` | yes — resources §2.4 | yes | 12 / 12 | — |
| -12 | `FreeUnit` | yes — resources §2.4 | yes | 6 / 6 | — |
| -18 | `GetUnit` | yes — resources §2.4 ; setpatch-138 §1.7 | yes | 120 / 120 | — |
| -24 | `GiveUnit` | yes — resources §2.4 ; setpatch-138 §1.7 | yes | 84 / 84 | — |
| -30 | `GetUnitID` | yes — resources §2.4–§2.5 | yes | 12 / 12 | — |

### potgo.resource (3 LVOs, −6 to −18)

| LVO | Function | Specified? (file §) | Implemented on our side | ROM size (own / closure) | Priority |
|---:|---|---|---|---|:-:|
| -6 | `AllocPotBits` | yes — resources §3.2 | yes | 106 / 106 | — |
| -12 | `FreePotBits` | yes — resources §3.3 | yes | 22 / 22 | — |
| -18 | `WritePotgo` | yes — resources §3.4 ; custom-chips §4.2 | yes | 50 / 50 | — |

### misc.resource (2 LVOs, −6 to −12)

| LVO | Function | Specified? (file §) | Implemented on our side | ROM size (own / closure) | Priority |
|---:|---|---|---|---|:-:|
| -6 | `AllocMiscResource` | yes — resources §4.2 | yes | 56 / 56 | — |
| -12 | `FreeMiscResource` | yes — resources §4.2 | yes | 12 / 12 | — |

## 4. Device commands

The standard vectors (Open, Close, Expunge, reserved, BeginIO, AbortIO) are not repeated; the
commands are the real API. The CMD_INVALID…CMD_FLUSH routines of keyboard, gameport, input and console
are partly **common** to the four devices in the ROM (same code for several entries). "IOERR_NOCMD, as 1.3"
marks a command that both 1.3 and our ROM refuse.

- **timer.device**: TR_ADDREQUEST (9), TR_GETSYSTIME (10), TR_SETSYSTIME (11) — **specified**
  (timer-v34 §2–§4), implemented; whole device ≈ 360 bytes reached from its 9 vectors.
- **audio.device**: CMD_RESET, CMD_READ, CMD_WRITE, CMD_UPDATE, CMD_CLEAR, CMD_STOP, CMD_START,
  CMD_FLUSH, ADCMD_FREE, ADCMD_SETPREC, ADCMD_FINISH, ADCMD_PERVOL, ADCMD_LOCK, ADCMD_WAITCYCLE,
  ADCMD_ALLOCATE — **all specified** (audio-device-v34 §4–§7: allocation, per-command behaviour, interrupt
  automaton, AbortIO, ADCMD_WAITCYCLE bug); all present in the command table of `src/exec/audio.s`
  (commands 1–14 by table, ADCMD_ALLOCATE separately). Size: 2,464 bytes reached from the 6 vectors (BeginIO
  alone ≈ 1.7 KB of closure), ROM area 4,204 bytes.

#### keyboard.device (14 commands, 0–13)

| No. | Command | Specified? | Implemented on our side | ROM size (own / closure) | Priority |
|---:|---|---|---|---|:-:|
| 0 | `CMD_INVALID` | yes — keyboard-input-devices §2.3 | yes (IOERR_NOCMD, as 1.3) | 8 / 134 | — |
| 1 | `CMD_RESET` | yes — keyboard-input-devices §2.3 | yes | 56 / 280 | — |
| 2 | `CMD_READ` | yes — keyboard-input-devices §2.3 | yes (IOERR_NOCMD, as 1.3) | 4 / 4 (shared routine ×3) (ROM stub) | — |
| 3 | `CMD_WRITE` | yes — keyboard-input-devices §2.3 | yes (IOERR_NOCMD, as 1.3) | 4 / 4 (shared routine ×3) (ROM stub) | — |
| 4 | `CMD_UPDATE` | yes — keyboard-input-devices §2.3 | yes (IOERR_NOCMD, as 1.3) | 4 / 4 (shared routine ×3) (ROM stub) | — |
| 5 | `CMD_CLEAR` | yes — keyboard-input-devices §2.3 | yes | 36 / 42 | — |
| 6 | `CMD_STOP` | yes — keyboard-input-devices §2.3 | yes | 16 / 142 | — |
| 7 | `CMD_START` | yes — keyboard-input-devices §2.3 | yes | 44 / 170 | — |
| 8 | `CMD_FLUSH` | yes — keyboard-input-devices §2.3 | yes | 32 / 164 | — |
| 9 | `KBD_READEVENT` | yes — keyboard-input-devices §2.4 ; keyboard-handshake §3 | yes | 230 / 362 | — |
| 10 | `KBD_READMATRIX` | yes — keyboard-input-devices §2.3 | yes | 42 / 42 | — |
| 11 | `KBD_ADDRESETHANDLER` | yes — keyboard-input-devices §2.3 ; keyboard-handshake §5 | yes | 26 / 32 | — |
| 12 | `KBD_REMRESETHANDLER` | yes — keyboard-input-devices §2.3 | yes | 22 / 28 | — |
| 13 | `KBD_RESETHANDLERDONE` | yes — keyboard-input-devices §2.3 ; keyboard-handshake §5 | yes | 16 / 22 | — |

#### gameport.device (14 commands, 0–13)

| No. | Command | Specified? | Implemented on our side | ROM size (own / closure) | Priority |
|---:|---|---|---|---|:-:|
| 0 | `CMD_INVALID` | yes — gameport-v34 | yes (IOERR_NOCMD, as 1.3) | 8 / 134 | — |
| 1 | `CMD_RESET` | yes — gameport-v34 | yes | 14 / 238 | — |
| 2 | `CMD_READ` | yes — gameport-v34 | yes (IOERR_NOCMD, as 1.3) | 4 / 4 (shared routine ×3) (ROM stub) | — |
| 3 | `CMD_WRITE` | yes — gameport-v34 | yes (IOERR_NOCMD, as 1.3) | 4 / 4 (shared routine ×3) (ROM stub) | — |
| 4 | `CMD_UPDATE` | yes — gameport-v34 | yes (IOERR_NOCMD, as 1.3) | 4 / 4 (shared routine ×3) (ROM stub) | — |
| 5 | `CMD_CLEAR` | yes — gameport-v34 | yes | 38 / 38 | — |
| 6 | `CMD_STOP` | yes — gameport-v34 | yes | 16 / 142 | — |
| 7 | `CMD_START` | yes — gameport-v34 | yes | 44 / 170 | — |
| 8 | `CMD_FLUSH` | yes — gameport-v34 | yes | 32 / 164 | — |
| 9 | `GPD_READEVENT` | yes — gameport-v34 | yes | 268 / 394 | — |
| 10 | `GPD_ASKCTYPE` | yes — gameport-v34 | yes | 42 / 42 | — |
| 11 | `GPD_SETCTYPE` | yes — gameport-v34 | yes | 84 / 84 | — |
| 12 | `GPD_ASKTRIGGER` | yes — gameport-v34 | yes | 48 / 48 | — |
| 13 | `GPD_SETTRIGGER` | yes — gameport-v34 | yes | 48 / 48 | — |

#### input.device (17 commands, 0–16)

| No. | Command | Specified? | Implemented on our side | ROM size (own / closure) | Priority |
|---:|---|---|---|---|:-:|
| 0 | `CMD_INVALID` | yes — keyboard-input-devices §3.3 | yes (IOERR_NOCMD, as 1.3) | 8 / 134 | — |
| 1 | `CMD_RESET` | yes — keyboard-input-devices §3.3 | yes | 14 / 242 | — |
| 2 | `CMD_READ` | yes — keyboard-input-devices §3.3 | yes (IOERR_NOCMD, as 1.3) | 4 / 4 (shared routine ×3) (ROM stub) | — |
| 3 | `CMD_WRITE` | yes — keyboard-input-devices §3.3 | yes (IOERR_NOCMD, as 1.3) | 4 / 4 (shared routine ×3) (ROM stub) | — |
| 4 | `CMD_UPDATE` | yes — keyboard-input-devices §3.3 | yes (IOERR_NOCMD, as 1.3) | 4 / 4 (shared routine ×3) (ROM stub) | — |
| 5 | `CMD_CLEAR` | yes — keyboard-input-devices §3.3 (never replied on 1.3) | yes (replies 0, as the spec recommends) | 2 / 2 (ROM stub) | — |
| 6 | `CMD_STOP` | yes — keyboard-input-devices §3.3 | yes | 16 / 142 | — |
| 7 | `CMD_START` | yes — keyboard-input-devices §3.3 | yes | 48 / 48 | — |
| 8 | `CMD_FLUSH` | yes — keyboard-input-devices §3.3 | yes | 32 / 164 | — |
| 9 | `IND_ADDHANDLER` | yes — keyboard-input-devices §3.3 ; intuiticks-repeat §1.4 | yes | 8 / 8 (shared routine ×3) | — |
| 10 | `IND_REMHANDLER` | yes — keyboard-input-devices §3.3 ; intuiticks-repeat §1.4 | yes | 8 / 8 (shared routine ×3) | — |
| 11 | `IND_WRITEEVENT` | yes — keyboard-input-devices §3.3 ; disk-change §3 | yes | 8 / 8 (shared routine ×3) | — |
| 12 | `IND_SETTHRESH` | yes — intuiticks-repeat §1.2, §2 ; keyboard-input-devices §3.3 | yes | 12 / 12 | — |
| 13 | `IND_SETPERIOD` | yes — intuiticks-repeat §1.2, §2 ; keyboard-input-devices §3.3 | yes | 14 / 20 | — |
| 14 | `IND_SETMPORT` | yes — keyboard-input-devices §3.4 | yes | 32 / 32 | — |
| 15 | `IND_SETMTYPE` | yes — keyboard-input-devices §3.4 | yes | 26 / 26 | — |
| 16 | `IND_SETMTRIG` | yes — keyboard-input-devices §3.4 | yes | 46 / 46 | — |

#### console.device (13 commands, 0–12)

| No. | Command | Specified? | Implemented on our side | ROM size (own / closure) | Priority |
|---:|---|---|---|---|:-:|
| 0 | `CMD_INVALID` | yes — console-keymap §2.4 | yes (IOERR_NOCMD, as 1.3) | 8 / 134 | — |
| 1 | `CMD_RESET` | yes — console-keymap §2.4 | no (IOERR_NOCMD) | 14 / 238 | P1 |
| 2 | `CMD_READ` | yes — console-keymap §6.3 | yes | 142 / 318 | — |
| 3 | `CMD_WRITE` | yes — console-keymap §3 | yes | 1314 / 1632 | — |
| 4 | `CMD_UPDATE` | yes — console-keymap §2.4 | yes (IOERR_NOCMD, as 1.3) | 4 / 4 (ROM stub) | — |
| 5 | `CMD_CLEAR` | yes — console-keymap §2.4 | no (IOERR_NOCMD) | 12 / 12 | P1 |
| 6 | `CMD_STOP` | yes — console-keymap §2.4 | no (IOERR_NOCMD) | 16 / 142 | P1 |
| 7 | `CMD_START` | yes — console-keymap §2.4 | no (IOERR_NOCMD) | 44 / 170 | P1 |
| 8 | `CMD_FLUSH` | yes — console-keymap §2.4 | no (IOERR_NOCMD) | 32 / 164 | P1 |
| 9 | `CD_ASKKEYMAP` | yes — console-keymap §5.4 | yes | 16 / 72 | — |
| 10 | `CD_SETKEYMAP` | yes — console-keymap §5.4 | yes | 16 / 72 | — |
| 11 | `CD_ASKDEFAULTKEYMAP` | yes — console-keymap §5.4 | yes | 12 / 68 | — |
| 12 | `CD_SETDEFAULTKEYMAP` | yes — console-keymap §5.4 ; setmap-13 | yes | 10 / 10 | — |

#### trackdisk.device (22 commands, 0–21; bound tested by BeginIO = 22)

| No. | Command | Specified? | Implemented on our side | ROM size (own / closure) | Priority |
|---:|---|---|---|---|:-:|
| 0 | `CMD_INVALID` | yes — trackdisk-raw-changeint §8 | yes | 12 / 72 (shared routine ×5) | — |
| 1 | `CMD_RESET` | yes — trackdisk-raw-changeint §8 | yes (IOERR_NOCMD, as 1.3) | 12 / 72 (shared routine ×5) | — |
| 2 | `CMD_READ` | yes — trackdisk-official-timing §1–§3 | yes | 520 / 2880 (shared routine ×2) | — |
| 3 | `CMD_WRITE` | yes — trackdisk-write §5.2 | yes | 520 / 2880 (shared routine ×2) | — |
| 4 | `CMD_UPDATE` | yes — trackdisk-write §5.3 | yes | 50 / 1086 | — |
| 5 | `CMD_CLEAR` | yes — trackdisk-write §5.1 ; disk-change §2.1 | yes | 22 / 82 | — |
| 6 | `CMD_STOP` | yes — trackdisk-raw-changeint §8 | yes (IOERR_NOCMD, as 1.3) | 12 / 72 (shared routine ×5) | — |
| 7 | `CMD_START` | yes — trackdisk-raw-changeint §8 | yes (IOERR_NOCMD, as 1.3) | 12 / 72 (shared routine ×5) | — |
| 8 | `CMD_FLUSH` | yes — trackdisk-raw-changeint §8 | yes (IOERR_NOCMD, as 1.3) | 12 / 72 (shared routine ×5) | — |
| 9 | `TD_MOTOR` | partial — intuition-requesters §7.1 ; trackdisk-official-timing §1 ; trackdisk-write §5.1 (return `$FF`/0) | yes | 22 / 342 | P2 |
| 10 | `TD_SEEK` | yes — trackdisk-official-timing §2 ; trackdisk-raw-changeint §3 | yes | 38 / 628 | — |
| 11 | `TD_FORMAT` | yes — trackdisk-write §5.4 | yes | 374 / 1668 | — |
| 12 | `TD_REMOVE` | yes — disk-change §2.1 ; trackdisk-raw-changeint §5.1 | yes | 12 / 72 | — |
| 13 | `TD_CHANGENUM` | yes — trackdisk-raw-changeint §5.4, §6.1 ; uae-hd-boot §3 | yes | 12 / 72 | — |
| 14 | `TD_CHANGESTATE` | yes — trackdisk-raw-changeint §6.1 ; disk-change §2.1 | yes | 20 / 80 | — |
| 15 | `TD_PROTSTATUS` | yes — trackdisk-write §5.5 ; disk-change §2.5 | yes | 90 / 410 | — |
| 16 | `TD_RAWREAD` | yes — trackdisk-raw-changeint §4 | yes | 120 / 756 (shared with 17) | — |
| 17 | `TD_RAWWRITE` | yes — trackdisk-raw-changeint §4 ; trackdisk-write §3.2 | yes | 4 / ≈ 756 (4-byte prologue into the routine shared with 16; *corrected 2026-11-02, see trackdisk-raw-changeint §0/§4: the former "4 / 4 (ROM stub)" was a measurement artefact, the command is fully implemented*) | — |
| 18 | `TD_GETDRIVETYPE` | yes — trackdisk-raw-changeint §2.3 | yes | 18 / 78 | — |
| 19 | `TD_GETNUMTRACKS` | yes — trackdisk-raw-changeint §2.3 | yes | 18 / 78 | — |
| 20 | `TD_ADDCHANGEINT` | yes — trackdisk-raw-changeint §5.2, §5.4 | yes | 28 / 28 | — |
| 21 | `TD_REMCHANGEINT` | yes — trackdisk-raw-changeint §5.3 | yes | 22 / 82 | — |

## 5. Inconsistencies found in the existing analysis documentation (to be fixed by the analysis track)

Status re-checked on 2026-11-04 (`c4bdddc`).

1. **Settled 2026-11-04.** `intuition-gzz-v34.md` §6.2 (table row) classified `RefreshGList` as "V36+, absent in 1.3"; the row is corrected and points to `intuition-gadgets-v34.md`.
   That was wrong: `RefreshGList` (−432), `AddGList` (−438), `RemoveGList` (−444), `ActivateWindow` (−450),
   `RefreshWindowFrame` (−456), `ActivateGadget` (−462) and `NewModifyProp` (−468) are **V33** functions
   (`.fd`), and the vector table of intuition 34.3 does have 78 entries (4 + 74).
2. **Still open.** `exec-spec.md` §3 ("Delta") puts `AddMemList` (−618), `CopyMem` (−624) and `CopyMemQuick`
   (−630) among the V36 additions. The ROM's exec table has **105 entries** and goes down to −630: these three
   functions exist in V34 (already flagged in §5 of the same file, but §3 has not been corrected).
3. **Settled 2026-11-02.** `disk-change-v34.md` §2.1 described `TD_ADDCHANGEINT` as V36; trackdisk-raw-changeint-v34
   §5 established that `TD_ADDCHANGEINT`/`TD_REMCHANGEINT` exist and work in V34 (the interrupt is `Cause()`d on
   ejection **and** insertion; the request is never replied while installed, so it must be sent with `SendIO`),
   and `disk-change-v34.md` has been corrected.
4. **Settled.** `module-map.md` no longer states that the LVO counts of the non-AUTOINIT modules cannot be
   measured. For the record (§1): graphics 109, layers 29, exec 105, timer 9, console 8,
   keyboard/gameport/input/audio/trackdisk 6, romboot 5, disk 5, cia 4, potgo 3, misc 2, keymap 0; only the dos
   table has not been located.

## 6. Implementation gaps noticed in passing (reading of `src/` at `c4bdddc`, for information)

- **Null vectors (4)**: graphics `graphicsPrivate1/2` (−642, −648; ROM stubs themselves, no known caller);
  dos `GetPacket/QueuePacket` (−162, −168; return 0, whereas 1.3 maps them to BCPL globals, dos-exit-packets §3;
  no Workbench 1.3.3 caller).
- **console.device**: `CMD_RESET`, `CMD_CLEAR`, `CMD_STOP`, `CMD_START`, `CMD_FLUSH` return IOERR_NOCMD on both
  the unit and the null-unit path; 1.3 implements them (console-keymap §2.4: CLEAR empties the input buffer and
  is never replied, STOP/START hold and release the queued CMD_READs, FLUSH aborts them with −2, RESET = STOP +
  FLUSH + START). `CMD_UPDATE` and `CMD_INVALID` are refused by both.
- **input.device**: `CMD_CLEAR` replies 0, whereas 1.3 never replies it (deliberate, as keyboard-input-devices
  §3.3 recommends).
- **ramlib.library**: no process of its own (the caller must be a process).
- **alert.hook**: not a separate resident; its role (Guru of a dead-end alert from before the reset) is played
  from the boot code.
- **Not checked here**: completeness of the routines behind the "yes" entries. Several specs carry their own
  "implementation gaps" sections (custom-chips §7, dos-memory, rom-filesystem §11–§12 probes); they are the
  reference for what each routine still lacks.

## 7. The most valuable remaining gaps (ranked, 2026-11-04)

Almost all of the former "next 15 analysis specs" (blitter, display, Alert/alert.hook, screens, input
engine and menus, layers, fills, console/keymap, gameport/input/potgo, keyboard, exec scheduling, audio,
sprites, resources, trackdisk raw/change, dos ROM file system and partial LVOs) have been written since the
first version of this page. What is left is ranked below. Rank 1 is the only P1 left (a command 1.3 implements
and we refuse). The others are functions **implemented on our side without a spec** (or with only a partial
one) **while known software uses them**: there the implementation follows the AutoDocs and AROS and has never
been checked against the V34 behaviour. "Used by" names programs analysed in `docs/analysis/`.

| Rank | Module | Function(s) | Spec / our side | Why it matters (used by) | Prio |
|--:|---|---|---|---|:-:|
| 1 | console.device | `CMD_RESET`, `CMD_CLEAR`, `CMD_STOP`, `CMD_START`, `CMD_FLUSH` | specified (console-keymap §2.4) / **refused** (IOERR_NOCMD) | Any program that clears or holds the console input queue before a prompt; CLEAR never being replied on 1.3 (a SendIO + WaitIO caller hangs there) is a behaviour to keep in mind before deciding how far to copy it. Implementation gap only: no analysis needed | P1 |
| 2 | intuition | `RefreshGList`, `AddGList`, `RemoveGList`, `RemoveGadget`, `AddGadget` (beyond §6.2–§6.3 of intuition-gzz) | **specified 2026-11-04** (intuition-gadgets-v34, probe `tests/glist_probe.s`) / yes, with gaps (system gadgets not in FirstGadget, NextGadget cleared on removal, RefreshGList count 0) | OctaMED v4 (RefreshGList ×27, RemoveGadget ×22, AddGadget ×18, AddGList/RemoveGList ×10 each, octamed §2.4); SysInfo 4.4 (AddGList, RefreshGList, sysinfo-44 §1.0). Closure ≈ 7.2 KB for RefreshGList. Also needs §5 item 1 fixed | P2 |
| 3 | intuition | `ActivateGadget` and the string-gadget engine (editing, UNDO, LONGINT; IDCMP of GADGETUP from a string gadget) | **specified 2026-11-04** (intuition-strgad-v34, probe `tests/strg_probe.s`) / yes, with gaps (LONGINT accepts a sign anywhere, GADGETUP Qualifier 0, disabled gadget refused) | OctaMED text fields (×11); Workbench Rename and Info (workbench-task §6.8); any requester with a text field. Closure ≈ 1.2 KB plus the input-engine part | P2 |
| 4 | graphics | Text and fonts: `Text` (full contract: clipping, styles, JAM modes), `TextLength`, `OpenFont`, `CloseFont`, `SetFont`, `AskFont`, `AddFont`, `RemFont`, `AskSoftStyle`/`SetSoftStyle` (algorithmic styles), `ClearEOL`, `ClearScreen` | partial (fastfonts-ff, setpatch-138 §1.9) or none / yes | Every window title, menu and CLI line; OctaMED (Text ×55, OpenFont), Workbench (OpenFont failure = dead-end alert, workbench-task §3.1), console. Text ≈ 1.3 KB of closure | P2 |
| 5 | graphics | `Draw` (line drawing) and `PolyDraw`, `Move` | cited / yes | Workbench drawers and frames, OctaMED (Draw ×16, PolyDraw, Move ×69), Preferences; graphics-area open point 4 asks whether AreaEnd's edges equal Draw's. Draw ≈ 3.5 KB of closure. *A500 risk*: blitter line mode (one-dot, octant, BLTAPT sign) | P2 |
| 6 | graphics | GELs and animation: `DrawGList` (VSprite band allocation), `DoCollision`, `SortGList`, `AddBob`, `RemIBob`, `AddVSprite`, `RemVSprite`, `InitGels`, `InitMasks`, `InitGMasks`, `GetGBuffers`, `FreeGBuffers`, `AddAnimOb`, `Animate` | partial (custom-chips §4.1) or none / yes | Icon dragging on the Workbench (AddBob, DrawGList, RemIBob, SortGList, workbench-task §3.6); games using Bobs/VSprites. DrawGList ≈ 6.5 KB, RemIBob ≈ 3.2 KB, DoCollision ≈ 1.8 KB of closure | P2 |
| 7 | graphics | Region functions: `AndRectRegion`, `OrRectRegion`, `XorRectRegion`, `ClearRectRegion`, `AndRegionRegion`, `OrRegionRegion`, `XorRegionRegion`, `NewRegion`, `ClearRegion`, `DisposeRegion` | return value only (layers §1.1) / yes | Workbench icon clipping (wb-icon-clipping §1), every InstallClipRegion user, layers damage lists. Closures 1.3–2.6 KB each; the rectangle splitting and the memory-failure paths are unspecified | P2 |
| 8 | intuition | `CloseWindow` (full order: IDCMP drain, menus, requesters, active window successor, memory), `MoveWindow`, `SizeWindow`, `WindowToFront`, `WindowToBack`, `WindowLimits` | partial (deferred-action queue in intuition-input-menus §1.10, GZZ layers in intuition-gzz §2.5) / yes | Every program closes windows; Workbench drawers (workbench-task §4.1, §6.8), SysInfo (sysinfo-44 §S1). CloseWindow ≈ 2.5 KB of closure | P2 |
| 9 | intuition | `SetWindowTitles`, `DrawBorder`, `DrawImage`, `PrintIText`, `IntuiTextLength` | partial / yes | Workbench memory title through SetWindowTitles (hooked by LoadWB 1.3.3, workbench-task §6.2–§6.6), OctaMED (`SetWindowTitles(w, -1, title)`), every gadget and requester rendering. SetWindowTitles ≈ 8.5 KB of closure (title bar redraw) | P2 |
| 10 | graphics | `SetRast`, `ScrollRaster`, `RectFill` (full contract), `SetAPen`/`SetBPen`/`SetDrMd` | cited or partial / yes | Layers clear new layers with SetRast (layers §5.1), Workbench window repair (wb-icon-clipping §5), console scrolling (console-keymap §3.7–§3.8), OctaMED (RectFill ×27). SetRast ≈ 1.2 KB of closure | P2 |
| 11 | exec | `RawDoFmt` | cited / yes | Workbench memory title (workbench-task §6.2–§6.4), SetMap (setmap-13), the Guru text (alert-v34 §3), LoadWB, CLI commands. Closure ≈ 450 b; format edge cases (`%ld` vs `%d`, `%b` BSTR, field width, PutChProc registers) unspecified | P2 |
| 12 | exec | Messages and I/O: `PutMsg`, `GetMsg`, `ReplyMsg`, `WaitPort`, `DoIO`, `SendIO`, `WaitIO`, `CheckIO`, `AbortIO`, `OpenDevice`, `CloseDevice`, `OpenLibrary`, `OpenResource` | cited (CheckIO partial) / yes | Everything: dos packets (dos-v34-spec §2a), devices, Workbench. The device-side halves are specified per device; the exec-side details (PA_SIGNAL/PA_SOFTINT/PA_IGNORE, IOF_QUICK handling in DoIO/WaitIO, ReplyMsg to a NULL port, OpenLibrary version test and ramlib fallback) are not | P3 |
| 13 | exec | Memory and semaphores: `Allocate`, `Deallocate`, `AllocAbs`, `AllocEntry`, `FreeEntry`, `TypeOfMem`, `AddMemList`, `CopyMem`, `CopyMemQuick`, `InitSemaphore`, `ObtainSemaphore`, `ReleaseSemaphore`, `AttemptSemaphore`, `ObtainSemaphoreList`, `ReleaseSemaphoreList`, `Add/Rem/FindSemaphore` | partial or cited / yes | SetPatch 1.38 (AllocEntry, setpatch-138 §1.4), KickMem survival (AllocAbs, coldstart-hardware §5.3), dos memory (dos-memory §2), layers (semaphore lists, layers §7), soft-kick (TypeOfMem). Deallocate ≈ 320 b of closure | P3 |
| 14 | ramlib.library | loading of LIBS:/DEVS: by ramlib's own process, expunge on low memory | none / partial (no process) | Every disk library and device: icon.library, info.library, diskfont, serial/parallel.device; a caller that is a plain task cannot load from disk on our side | P2 |
| 15 | mathffp.library | the 12 SP* functions (FFP format, rounding, overflow, condition codes) | none / yes | Programs compiled with FFP floating point, AmigaBASIC [no analysed program uses it yet]. ≈ 1 KB in the ROM | P3 |

Below rank 15: `InitRastPort`/`InitBitMap` beyond the fields already listed; `AllocRaster`/`FreeRaster`;
`AllocRemember`/`FreeRemember`; `BeginRefresh`/`EndRefresh` beyond the GZZ test vectors; `SetFunction` (return
value only); `MakeLibrary`/`MakeFunctions`/`InitStruct` edge cases; exec `SetSR`/`SuperState`/`UserState`/`GetCC`,
`AllocTrap`/`FreeTrap`, `AllocSignal`/`FreeSignal`; the two null dos vectors (no caller known); trackdisk
`TD_MOTOR` (partial). Analysis open points that are not LVO gaps are listed in each spec's "Open points"
section (e.g. rom-filesystem §11 probes P1–P4 and §12, dos-memory §9, graphics-area and graphics-display open
points).

## Clean-room review

- This file contains no ROM instruction sequence, no listing and no routine
  address: only public names and LVOs (`.fd`), ABI command numbers, counts of
  table entries and measured sizes in bytes.
- The mentions of `src/` describe the state of OUR implementation (reading allowed for this
  inventory); no ROM information is reinjected into it in the form of code.
- The 2026-11-04 refresh read only `docs/analysis/*.md` and the committed `src/` tree; the ROM was not opened
  and no size was re-measured.
- The hardware values cited as risks (keyboard pulse, minimum audio period, BBUSY) are
  public facts from the Amiga hardware documentation, not measurements of the ROM.
