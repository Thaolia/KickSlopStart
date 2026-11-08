# Plan — Open-source clean-room reimplementation of a Kickstart 1.3 (Amiga 500)

## Context

Goal: produce an **open-source, strictly 1.3-compatible Kickstart** — a ROM image of **256 KiB
loaded at `$FC0000`**, 68000 big-endian, drop-in for the real `kick34005.A500`, booting **first in an
emulator (FS-UAE/WinUAE), then on a real Amiga 500** (EPROM/adapter).

Original ROM identified: 262,144 bytes, MD5 `82a21c1890cae844b3df741f2762d48d`, SHA1
`891e9a547772fe0c6c19b610baf8bc4ea7fcb785`, header `JMP $00FC00D2`, ROM-ID `0x1111`. Structural scan:
**24 valid ROMTags** (module map below).

**Why this plan has this shape** — three constraints dictate everything:

1. **"Clean room" = a wall, not a person.** Disassembling the ROM *and* writing its
   replacement in the same flow produces a derivative work (the opposite of clean-room). The wall separates
   two sealed tracks (analysis ↔ implementation), through distinct agent roles. The implementation
   **never** sees the disassembly — only **behavioural specs** (the *what*, never the transcribed
   *how*) + the public docs.
2. **AROS is not used as a base, by choice.** AROS m68k mainly targets the **3.1** API, with compatibility for
   1.3 programs (BCPL support; it is reported to boot Workbench 1.3 and to run 1.3 tools such as the Shell and Ed).
   It **runs on a plain 68000**: its Amiga build explicitly handles the 68000/010 alignment rules for the A500. Its
   ROM is **1 MB** (a 512 K image at `$F80000` plus a 512 K extension at `$E00000`) and it is under the **APL v1.1**
   licence (per-file copyleft). This project aims at a **256 K, 1.3-sized ROM written from scratch under MIT**, so
   AROS remains a **reading reference** (algorithms, structures); we **do not copy** its code into `src/` (see
   Licence and `docs/audit/aros-similarity.md`). *Corrected on 2026-10-30 after GitHub issue #3: an earlier
   version wrongly stated that AROS m68k requires a 68040.*
3. **The 68000 is our target by design.** Since we reimplement 1.3 from scratch, the real
   A500 (68000) remains reachable for *us* — it is AROS that cannot reach it.

**Magnitude (to be accepted).** A complete KS 1.3 = ~24 interdependent modules (including `dos.library` in
BCPL) and **no open-source/clean-room prior art targeting 1.x** exists (an unprecedented project). Full
parity is a long-horizon undertaking. **This plan delivers: executable foundations, clean-room
discipline, a test bench, and a milestone ladder that boots incrementally** — not a
promise of fast total parity. Priority to **code that runs** over any exhaustive planning.

## Resident module map (source: ROMTag scan; documentable ABI fact, analysis side)

Init order = decreasing priority.

| Pri | Module | Ver | | Pri | Module | Ver |
|----:|--------|-----|-|----:|--------|-----|
| 120 | exec.library | 34.2 | | 50 | timer.device | 34.1 |
| 110 | expansion.library | 34.1 | | 40 | audio.device / input.device | 34.1 |
| 100 | potgo.resource / keymap.resource | 34.1 | | 31 | layers.library | 34.1 |
| 80 | cia.resource | 34.1 | | 20 | console.device / trackdisk.device | 34.1 |
| 70 | disk.resource / misc.resource / ramlib.library | 34.1 | | 10 | intuition.library | 34.3 |
| 65 | graphics.library | 34.1 | | 5 | alert.hook | 34.0 |
| 60 | keyboard.device / gameport.device | 34.1 | | 0 | mathffp.library / workbench.task / **dos.library** (BCPL) | 34.1/34.3 |
| | | | | -40 | romboot.library | 34.1 |
| | | | | -60 | strap | 34.4 |

## Clean-room discipline (the heart of the plan)

Two tracks, two agent roles, one wall:

- **ANALYSIS track ("dirty")** — access: ROM + `radare2` (Ghidra headless optional for the
  decompiler). Produces ONLY `docs/analysis/*.md` (boot sequence, init order, layout of the
  structures = ABI, ABI constants) + **test vectors** (input→observable output = oracle).
  Forbidden: writing to `src/`; transcribing instruction sequences into an artefact feeding
  the implementation.
- **IMPLEMENTATION track ("clean")** — access: public docs (RKRM/AutoDocs/NDK/`.fd`), AROS source
  (read-only), and the analysis's **behavioural specs + test vectors**. Forbidden: reading the
  ROM or its disassembly. Produces: `src/`.
- **Spec rule**: describe behaviour and ABI layout (public), never a copied instruction
  sequence. The `.fd`/AutoDocs/RKRM already define the API (LVOs, signatures) → the implementation relies
  on them first; the ROM only serves to resolve *behavioural* ambiguities.
- **Spec review gate**: before the impl track consumes a spec, a review confirms
  that it contains **no transcribed instruction sequence** — it is this check that gives the wall
  its real value.
- **Honesty**: two agent roles in the same session *approximate* the wall without being worth a
  "court-grade" separation of people. Realistic maximal posture here; for hard legal needs,
  have analysis and implementation done by different people.

## Licence

- **AROS** under **APL v1.1** (per-file copyleft, derived from MPL-1.1, non-OSI/FSF, GPL-incompatible) →
  any *modified* AROS file would remain under APL. Under a strict firewall we **read** AROS (to understand the
  algorithms), we **do not copy** its sources into `src/` → our licence stays free.
- **Docs** (NDK 3.2, RKRM/AutoDocs): proprietary licences, **consumed** to learn the ABI/the
  behaviour, **never redistributed/vendored** in the repository.
- **Our licence**: **MIT** (`LICENSE` file at the root, decided on 2026-10-26 at publication on GitHub).

## Repository structure (project-structure rules)

```
amiga_kickstart_reverse/
  CLAUDE.md  README.md  .claude/
  src/            # CLEAN track: exec/ libs/ devices/ resources/ rom/ (linker script, reset/header)
  docs/           # analysis/ (DIRTY track: specs + oracle vectors) · ARCHITECTURE.md CLEANROOM.md HARDWARE.md PLAN.md
  tests/          # emulator harness + vamos units + oracle diffs
  assets/         # original ROM (read-only copy) + test ADFs
  build/          # artefacts (gitignore): *.rom *.elf
  third_party/    # AROS (read-only reference); NO vendored NDK/RKRM
```
The `kick34005.A500` is **copied** into `assets/` (never modified), readable only by the analysis
track and the oracle bench.

## Toolchain & test bench

**Present locally**: `radare2` 6.1.3 (m68k via `-a m68k`), complete **amitools** CLI (`romtool`,
`vamos`, `fdtool`, `xdftool`, `hunktool`, `rdbtool`), `python3`, `git`, `make`, `cmake`.

**To install**:
- **vasm (`vasmm68k_mot`) + vbcc + vlink** (Frank Wille, `sun.hasenbraten.de`) — de facto standard.
  `vlink`: `rawbin`/`ados` outputs, **`-kick1` option** (Kickstart 1.x loader compat), linker scripts
  (SECTIONS/MEMORY) to place the code at `$FC0000`. C alternative: gcc **bebbo** (`codeberg.org/bebbo/amiga-gcc`),
  KS1.3 runtime via **`-mcrt=nix13`**.
- **Emulator**: **FS-UAE** native Linux + **Xvfb** (primary for CI, driven by config file,
  `kickstart_file = <chemin>`); **`WinUAE.exe`** via WSL2 Windows interop (`-f cfg.uae -s use_gui=no`,
  `kickstart_rom_file=`) as secondary (64-bit Wine broken → do not use it).

**amitools role**:
- `romtool build -t kick -s 256 -a fc0000 -o build/kick13.rom <modules>` then `romtool copy -c`
  (checksum fix, offset 0x3FFE8); `romtool info`/`scan` to validate header/tags/size and diff against
  the original (oracle). (Checksum not verified by the OS before V37, but the tools expect it.)
- `fdtool`: extract the LVOs from the `.fd` files → jump table / ABI offsets.
- `vamos`: run **AmigaOS test binaries** on the host against a known environment and cross-check the
  *documented* API semantics — it provides its own exec/dos, so it does NOT host our code.
- `xdftool`: build test ADFs for the floppy boot milestones.

**Header/reset (facts for our own code)**: at power-on the overlay maps the ROM at `$000000` → the
68000 reads the **initial SSP at longword `$0`** and the **initial PC at longword `$4`**. Convention of the first 8
bytes: **ROM-ID word (`0x1111`) + `4EF9` (JMP) + coldstart address** (our dump: `JMP $00FC00D2`).

## Milestone ladder (boots incrementally)

- **M0 — Foundations + hello-ROM (first code that runs).** Repository scaffolding + toolchain + harness.
  256K image: reset vector `$0`/`$4`, ROM-ID+`JMP` header, code writing `$DFF180` (background colour)
  → "it runs" signal in the emulator. Proves the vasm→vlink(`-kick1`)→`romtool`→emulator chain.
  **From M0 on, set up capture of the serial log (`SERDAT` register) as the primary assertion channel**
  (deterministic/CI); the `$DFF180` blink is only a sign of life. Oracle bench: real KS 1.3 in UAE
  for **targeted behavioural probes → test vectors** (never a global system diff).
- **M1 — Boot spec (analysis track).** Cold-start → exec `InitCode` → resident scan (order of the table)
  → strap. `exec` spec: `ExecBase` layout, LVO table (negative offsets via `.fd`), behaviours of the
  primitives. Deliverables: `docs/analysis/{boot-sequence,exec-spec,module-map}.md` + oracle vectors.
  ⚠️ **The public docs online are 2.0+/3.x** (RKRM 2.0/3.5, NDK 3.2); 1.3 (V34) has a smaller/different
  ABI (fewer LVOs, distinct structs/behaviours). **1.x** references are needed (RKRM
  1st edition + 1.x `.fd`, truncated LVO sets); and **wherever the public 1.3 docs are thin, it is
  the analysis track that captures the V34↔2.0-docs behavioural delta in the spec** — since the impl track
  cannot read the ROM to discover it, otherwise the wall leaks.
- **M2 — exec.library (impl).** Cold start, `ExecBase`, memory (detection, `AllocMem`/`FreeMem`,
  memory list), lists, libs/devices (`MakeLibrary`/`OpenLibrary`/`SetFunction`, jump tables),
  tasks/scheduler, signals, ports/messages, interrupts/traps, `InitResident` + data-driven auto-config
  scan. Check: exec lives up to the resident scan **on a complete machine (UAE)** — that is where
  exec bringup is validated; `vamos` provides ITS own exec/dos and **cannot host ours**.
  Assertions via serial log; oracle probes where observable.
  **Status (detailed tracking in the ledger + README)**: coldstart/ExecBase/V34 jump table/multi-header memory/
  lists/tasks+signals+non-blocking ports = delivered (sub-milestones M2.0→M2.4). VBlank interrupt
  plumbing (M3a), **supervisor preemptive scheduler** (M3b), **mutual exclusion** — `Forbid()`
  honoured + exec critical sections wrapped (M3c), **`Wait`/`WaitPort` + wake-on-signal** —
  real blocking of a task via synchronous switch (M3d) and **immediate yield on `Permit`/`Enable`** —
  synchronous reschedule to a higher-priority woken task (M3e, proven in cooperative mode), **recombination of
  yield + preemption** — the two unified switch paths coexist without corruption (M3f) and
  **resident scan machinery** — `build_reslist`/`FindResident`/`InitResident`/`InitCode`
  proven by 3 demo residents initialised in priority order (M4) = delivered and verified by FS-UAE
  boot, as well as **AUTOINIT** — `MakeLibrary`/`MakeFunctions`/`InitStruct` + AUTOINIT path of
  `InitResident`, proven by a demo AUTOINIT resident (M5a), as well as **`cia.resource`** — 1st real
  resident module (ciaa/ciab, direct-init via MakeLibrary, `AddResource`/`OpenResource`, M5b) and
  **`timer.device`** (AUTOINIT, 2nd real resident / 1st device, M5c). The OS therefore now instantiates
  REAL resident modules — but `cia.resource`/`timer.device` are still **skeletons** (named,
  created, listed; no functional work: cia without interrupt dispatch, timer without units/BeginIO).
  The 1st FUNCTIONAL path is delivered: timer's **VBLANK** unit driven by the existing VBlank handler
  (request queue, decrement on VBlank, low-level reply on expiry, M6a) = 1st
  observable OS behaviour (timer+interrupt+messages+`exec_Signal` from the IRQ). The **CIA interrupt
  dispatch** (INT2/CIA-A: the registered ICR vectors fire, proven end-to-end
  by a CIA timer, M6b) is also delivered. **M7a**: the real gate that blocked CIA +
  preemption coexistence was NOT the stack (in the supervisor-tasks-same-stack model the interrupt frames
  unstack correctly; stack corruption through a shared SSP remains **latent** until user mode)
  but the **re-entrancy of the scheduler lists**: `vbl_handler` did its TaskReady `Enqueue`/`RemHead`
  at IPL3, preemptible by INT6 (level 6) whose `exec_Signal` touches the same list. Closed by
  raising IPL7 around the critical section only (+ `timer_reply` AddTail IPL7). Delivered with the **MICROHZ
  unit** (CIA-B/INT6) and a **task that blocks on a timer** (Wait→wake), proven by a structural
  detector `VBL_CLASH==0` (RED: gate removed → clash) + yield re-proven in cooperative mode. **M7b** delivers the
  **interrupt dispatcher by number**: `IntVects`/`SetIntVector` (exclusive vector)/`AddIntServer`
  (server chain by priority, walked by `intr_chain_walker`); the hardcoded CIA autovectors are
  replaced by generic `int2_dispatch`/`int6_dispatch` and cia.resource becomes a PORTS/EXTER SERVER
  (like the real exec). **M7c** moves tasks to **user mode** (SR S=0, per-task user stack) on a
  **shared SSP** and replaces the `sp` swap by a **DEFERRED switch with frame relocation** (`dispatch`
  relocates SSP↔user stack, per-task nesting, INTENA synchronised; voluntary switch via `trap`) — this is
  where the shared-SSP hazard becomes real and the nest count (S bit of the saved SR) becomes load-bearing.
  Derived from the public "Exec Microkernel" spec (AROS) + 68000 manual (zero transcribed code). A **deferred
  dispatch flag** at IRQ exit promptly wakes a higher-priority task signalled from an interrupt.
  **M7d** makes ports INTERRUPT-SAFE: `PutMsg`/`GetMsg`/`ReplyMsg` go from Forbid (task-vs-task) to
  Disable (also masks interrupts), proven by a shared port hammered by a TASK and an INTERRUPT
  (GREEN coexistence + A/B under max contention: Forbid corrupts the list, Disable does not). Unblocks
  IRQ-driven device I/O. **M7e** delivers **per-level IPL fidelity**: handlers run at their native IPL (VBlank=3,
  PORTS=2, EXTER=6) instead of a uniform IPL7 — a higher-level source preempts the BODY of a lower
  handler (INT6 preempts the vbl body, `VBL_PREEMPT_COUNT>0`). The critical section of the switch is masked by
  a brief IPL7 (SR = instantaneous) and NOT by INTENA-off: empirical discovery that the INTENA write has a
  propagation delay (race observed in RED1); the IPL-vs-INTENA choice is imposed by privilege (the switch runs
  in supervisor; Signal/ports/Wait are user-mode and cannot raise the IPL -> they keep INTENA-Disable + its
  write-delay caveat, tolerated/benign). Proven GREEN 3/3 + RED1 3/3 (clash) + RED2 2/2 (M7E absent) + cooperative.
  **M7f** delivers **VERTB AS A SERVER CHAIN**: the dedicated `vbl_handler` becomes a generic `int3_dispatch`
  (mirror of int2/int6) -> `intr_dispatch_number(VERTB)` -> server chain by priority (UNIFORM
  PORTS/VERTB/EXTER model). The round-robin quantum becomes `sched_server` (sets AttnResched, Forbid/Disable guards
  kept); `timer.device` moves from its `VBL_SVC` hook to `AddIntServer(VERTB, timer_vblank)`. Key risk:
  the walker does not restore `a6` after the last server -> `intr_isr_defer` reloads `a6`. Proven "M7F VERTB
  OK" (`VERTB_CHAIN_N` = full sched/timer/tail walk in order) + scheduler/timer OK via the chain, GREEN
  3/3 + RED (sched stops the chain with Z clear -> "M6A FAILED" VBLANK timer dead) + cooperative. Discovery:
  removing the VBlank quantum alone does not stop preemption (INT6 co-drives the round-robin via the deferred dispatch).
  **M7g** delivers **multi-source INTREQR decoding**: int3_dispatch reads INTREQR & INTENAR and dispatches+acks
  EACH pending level-3 source (COPER/VERTB/BLIT) via IntVects[n], instead of assuming VERTB alone
  (int2/int6 remain single-source, correct). Proven "M7G MULTISRC OK": a 2nd level-3 source (COPER,
  triggered by software INTREQ=SETCLR|COPER, without graphics) is served via the decoding; GREEN 3/3 + RED
  (M7G_MONO_SOURCE=1: decodes+acks but does not dispatch -> COPER_FIRED frozen, no storm) + cooperative.
  **M7h** delivers the **real quantum**: sched_server preempts after M7H_QUANTUM ticks (default 4, like exec)
  instead of every tick; QUANTUM_ELAPSED reset on an actual task change. Strict priority already
  correct (RemHead/Enqueue by pri) -> quantum only. Observable ONLY in isolation (M7H_QUANTUM_DEMO:
  2 spinners pri 0): in the normal demo INT6 resets ELAPSED ~140/s -> quasi no-op (non-regression M3F..M7G OK, the
  quantum is not load-bearing for the rotation that INT6 drives). Proven "M7H QUANTUM OK"
  (QUANTUM_EXPIRE_N*2<VBL_COUNT) GREEN-iso 2/2 + RED-iso (QUANTUM=1 -> every tick) 2/2 + non-reg + coop.
  **M7i** converts `timer_reply`→`ReplyMsg`: the bespoke routine (created in M7c to avoid ReplyMsg's Permit/yield
  in interrupts) is removed; M7d having made ReplyMsg interrupt-safe (Disable/raw_enable,
  without yield), the VBLANK/MICROHZ services call ReplyMsg directly. Proven by EQUIVALENCE (set of
  markers identical to M7h default, GREEN 3/3 + coop); inverted justification corrected everywhere.
  **M7j** delivers `RemTask` (life cycle): removal of a task + FreeMem of stack/TCB. Self-removal (task that
  ends via task_exit) = trap #2 -> supervisor (on the SSP, the user stack can be freed) -> FreeMem
  (outer Forbid neutralises the yield of the inner Permit) -> switch (dispatch_in). Non-self = Remove +
  FreeMem in task context. Proven "M7J REMTASK OK" (AvailMem rises again after task_rm's self-removal):
  GREEN 2/2 + default non-reg 3/3 + coop; RED M7J_NOFREE (FreeMem skipped -> leak -> AvailMem does not rise).
  Non-self by inspection; tc_MemEntry out of scope. CLOSES the pre-authorised M7e..M7j sequence.
  **M7l** delivers **real µs MICROHZ calibration**: `timer_beginio` separates the conversion per unit and
  counts the MICROHZ unit in CIA-B interrupts via `US_PER_INT`=359 / `INTS_PER_SEC`=2782 (PAL E-clock
  709379 Hz, latch 255) instead of the VBLANK factor `/20000` -> `TV_MICRO` = real µs (resolution ~360 µs).
  CROSS-CLOCK proof: a 0.5 s request elapses in ~25 VBLANK ticks (independent display clock);
  GREEN "M7L MICROHZ CALIB OK" 3/3 + RED `M7L_OLD_CONV` (request too fast, M7L absent, surgical) 2/2
  + coop non-regression. **M7k POSTPONED** (decision 2026-10-15): INTREQR decoding of levels INT1/INT4/INT5
  is plumbing without a real consumer (audio=M4+, disk=M6, serial later) -> folded into the
  relevant subsystem when it arrives, with a real test. Remaining: **M4 graphics** (below), then
  possible removal of the demos (the boot handoff remains the M3f/M7a/M7c/M7d/M7e/M7f/M7g/M7j+M7l demo until then).
- **M3 — resources & timing**: `cia.resource`, `timer.device`, `misc`/`potgo`/`disk.resource`,
  `keymap.resource`; interrupt plumbing (VBlank already in place since the exec bringup).
- **M4 — graphics.library + minimal display**: Copper/Blitter/View sufficient to display.
  Breakdown (user, 2026-10-15): **M4a** colour background driven **Copper-only** (proves Copper DMA alone,
  without bitplane); **M4b** **bitplane** pixels driven by the Copper (real first display); **M4c** start the **graphics.library
  ABI** (GfxBase + View/ViewPort generating the copperlist; broken down: **M4c1** resident skeleton
  [DONE: `src/graphics/graphics_lib.s`, ROMTag AUTOINIT pri 65 → `MakeLibrary`/LibList, 1st NT_LIBRARY branch
  exercised, proven by FindName+Open like M5c; RED `M4C1_WRONG_TYPE` routes to DeviceList → absent] → **M4c2**
  [DONE: `MakeVPort`/`MrgCop`/`LoadView` (graphics_lib.s) generate the copper list from the
  BitMap/ViewPort/View/ColorMap structures, called through the GfxBase jump table; the M4a/M4b copper template and its gates
  M4A_NO_COPPER/M4B_NO_BITPLANE are REMOVED → proof by ELIMINATION (nothing else draws the stripes);
  RED `M4C2_NO_MRGCOP` → MrgCop does not merge → empty list → white screen]). **M4 COMPLETE.** **M4a + M4b DONE** (`src/graphics/gfx.s`,
  copper list + bitplane in chip RAM — the Copper AND bitplane DMA read ONLY chip, not ROM): first
  milestone where the **VISUAL** channel is load-bearing (the screen IS the deliverable).
  **M4a** = Copper-only driven background (COLOR00 = green); GREEN screen ⟺ Copper DMA active; RED `M4A_NO_COPPER` (no
  COPEN) → white screen. **M4b** = 1 bitplane 320×256 filled with vertical stripes (`$FF00`); COLOR00 blue / COLOR01
  green → **green stripes** on screen ⟺ bitplane DMA active; RED `M4B_NO_BITPLANE` (BPU=0, no RASTER) → plain blue.
  (M4a/M4b used a hard-coded copper template, gated by `M4A_NO_COPPER`/`M4B_NO_BITPLANE` — **all removed
  in M4c2**, the display goes through the ABI.) M4a also fixed a bug in the colour discriminant of `tests/boot_test.sh`
  (`-opaque`/`+opaque` order: the pre-existing white skewed FRAC; masked because the default `EXPECT=FFFFFF` did not expose it).
- **M5 — minimal intuition.** Framing (user + advisor decision, 2026-10-16): the "insert Workbench disk" screen
  has **no real trigger before M6** (it is displayed when the boot finds no bootable volume =
  DOS/trackdisk), and `intuition.doc` confirms it is **not an intuition function** (only the
  IDCMP `DISKINSERTED` events and the DOS "Please insert volume XXX" requesters are) → drawing it now by
  forcing it through intuition would be a synthetic artefact (same logic as **M7k postponed**). The honest and
  provable core of M5 = the **`intuition.library` resident skeleton** + one real 1st-gen primitive. **DONE**
  (`src/intuition/intuition_lib.s`, `intuition.i`): ROMTag AUTOINIT **pri 10** → `MakeLibrary`/`LibList` (NT_LIBRARY
  branch, like M4c1); funcTable 49 vectors (Open/Close/Expunge + `ViewAddress` at vector 49 = LVO **-294**,
  authoritative NDK LVOs); `IntuitionBase` set up (embedded ViewLord, `INTUITIONBASE_SIZE`=80). Serial proof
  (marker **M5I**): FindName + version 34 + type NT_LIBRARY + Open→OpenCnt==1 + **`ViewAddress()==IntuitionBase+34`**
  (= `&ib_ViewLord`). RED `M5I_BAD_VIEWADDR` → ViewAddress returns 0 → M5I absent (isolates the new primitive; the
  NT_LIBRARY→LibList routing is already RED-proven by `M4C1_WRONG_TYPE`). Non-regression: FRAC **0.299635 identical**
  GREEN/RED/COOP (the pri-10 resident shifts the heap but the M4 display is intact). Deferred: OpenScreen/OpenWindow/
  DisplayAlert, text rendering, insert-disk screen (→ M6).
- **exec `OpenLibrary` (M2 consolidation) — DONE.** `src/exec/library.s`: `OpenLibrary(libName,version)` (-552),
  `CloseLibrary` (-414), `OldOpenLibrary` (-408), patched in `build_jumptable`. Opening by name = `Forbid` +
  `FindName(LibList)` + **version gate** (`lib_Version >= version` requested, otherwise 0) + call of the lib's Open/-6
  vector (OpenCnt++); `CloseLibrary` calls the Close/-12 vector. Serial proof **M5O**: OpenLibrary(intuition,34)
  == base & OpenCnt+1; version 99 → 0 (gate); non-existent lib → 0; CloseLibrary → OpenCnt-1. RED
  `OPENLIB_NO_VERCHECK` → gate skipped → version 99 wrongly opens → M5O absent (isolates the gate). FRAC 0.299635 identical
  GREEN/RED/COOP. Deferred: ramlib disk loading (M6, non-resident → 0); delayed-expunge on Close (residents
  → Close returns 0). The M4c1/M5 proofs (FindName+Open by hand) are candidates for refactoring onto `OpenLibrary`.
- **M6 — dos + trackdisk + FS + strap/romboot → floppy boot up to the CLI.** The 1.3 `dos.library` is
  a **BCPL/TRIPOS** port: the ABI quirks must be replicated (word-based **BPTR**, global vector,
  BCPL calling convention, **DOS packets**, `LoadSeg` segments). Approach chosen = **ANSI C rewrite
  keeping `BPTR`/packets** (what AROS `rom/dos/` did — to be read — and Commodore in 2.0).
  - **M6d — resident dos.library skeleton + BPTR convention + DateStamp (DONE, 1st M6 increment).** Framing
    (user + advisor decision, 2026-10-16): M4c1/M5I playbook. ROMTag AUTOINIT pri 0 → `MakeLibrary` creates `DosBase`
    in `LibList`. initfunc allocates `RootNode` and `DosInfo` **separately via AllocMem** (⚠️ advisor safeguard:
    `BPTR=addr>>2` is only reversible on long-aligned addresses — do NOT embed the structs in `DosBase`
    like ViewLord in M5I, otherwise the round-trip loses bits), wires `dl_Root` (APTR) and `rn_Info` (BPTR=&DosInfo>>2).
    `DateStamp`(-192, arg in d1) fills (0,0,0) "clock not set" (faithful to the V34 AutoDoc: dl_TimeReq/battclock
    deferred) and returns the pointer. Deliberate clean-room deviation: C-style init instead of the original BCPL glue.
    Serial proof **M6D**: FindName+version 34+NT_LIBRARY+Open→OpenCnt==1 + BPTR round-trip `rn_Info<<2==&DosInfo`
    (compute-then-compare via the `DL_DISHADOW` scaffold, **without dereferencing** the decoded pointer → RED fails with a
    mismatch, not a bus error) + DateStamp→(0,0,0)+ptr. RED `M6D_BAD_BPTR` (rn_Info as a raw APTR) → M6D absent,
    all other markers present (surgical isolation). FRAC 0.299635 identical GREEN/RED/COOP. Rebuild
    byte-identical, checksum `0x929C804F`. Deferred: packets/LoadSeg/handlers, Open/Read/Lock, strap/trackdisk/FS,
    insert-disk screen (image `assets/boot_screen/cat_amiga_kickslopstart.jpg` chosen, displayed at the strap increment
    when the real "no bootable volume" trigger exists).
  - **M6s — boot screen (kitten image "KickSlopStart"), 2nd M6 increment (DONE).** User request: display their
    image at startup. Pipeline `src/graphics/mk_bootscreen.py` (Pillow, self-checking: JPEG → 352×272 → quantize
    32 colours → 5 planar bitplanes, plane 0 = LSB, bit 7 = left pixel, RGB444 palette; rebuilds + asserts) →
    `bootscreen.raw` + `bootscreen_data.s` (OCS palette + incbin) + reference PNG. ABI: `gfx_MakeVPort` made
    GENERIC (N plane pointers + `cm_Count` colours + BPL2MOD); `gfx_display_init` evolves the M4b stripes
    → the image (5 planes/32 colours copied ROM→chip), displayed via MakeVPort/MrgCop/LoadView at handoff. (2026-11-04: 16 colours, 4 planes, ByteRun1 in the ROM: 39 KB instead of 60 KB, see ARCHITECTURE 7aa.) Overscan
    352×272 (DIW/DDF widened) to fill the screen edge to edge (user request: "it does not fill the whole screen"). Proof
    (advisor safeguards: validate the discriminant on real GREEN+RED values before the threshold; self-checking planariser;
    reference from the real ROM data): serial marker **M6S** = liveness; VISUAL discriminant = number of
    unique colours in the active area (GREEN ~19017 vs RED one-plane ~151, separation ~126×, threshold 1000). RED
    `BOOTSCR_ONE_PLANE` (depth=1 → 2 colours → image destroyed); serial markers ALL present → isolates the
    multi-bitplane rendering without breaking the boot. COOP non-reg. GREEN checksum `0x92E3ACA7`. ROM ~177 KB free. ⚠️ Displayed
    UNCONDITIONALLY at handoff: the real "no bootable volume" trigger remains for the strap increment.
    Run it yourself: `tests/run_fsuae.sh` (windowed FS-UAE, WSLg).
  - **M6r — strap (romboot) + real insert-disk trigger, 3rd M6 increment (DONE, 1st link of floppy boot).**
    Advisor framing: (1) the "it boots!" will target a CUSTOM bootblock after A+B+C (without dos); (2) the insert-disk
    trigger must come from the FAILURE to access DF0:, not from an empty list (otherwise synthetic like M5/M6d);
    (3) OFS+dos+CLI = ONE packets subsystem, to be re-broken down later; (4) do not over-specify B→F; (5) `AddBootNode`
    is V36/2.0+, NOT 1.3 → free clean-room internal mechanism, 1.3-compatible behaviour. `src/exec/strap.s`:
    `strap_boot(a6)` = SCAFFOLD, always returns 0 = no bootable volume (FindName(trackdisk) + CMD_READ +
    validation/execution of the bootblock = increments B/C). boot.s: if 0 → the display of the boot screen (insert-disk)
    is ROUTED by this decision + marker M6R, otherwise (never in GREEN) skips the screen. ⚠️ The REAL trigger
    (screen because reading DF0: fails) comes with B/C; A only routes the screen through the strap. DOUBLE
    proof: serial M6R + VISUAL (colours ~19017 kitten
    screen). RED `STRAP_FAKE_BOOTDEV` (strap believes it boots → d0≠0) → neither M6R nor M6S nor screen (low colours),
    boot markers M3F..M7 intact → isolates the strap decision. COOP non-reg. NEXT: increment B trackdisk.device.
  - **B / M6t — trackdisk.device skeleton + unit validation (DONE).** B too big for one increment → re-broken down:
    B1 skeleton (THIS slice) → B2 CIA drive control + raw MFM track read (Paula DMA, sync `$4489`) → B3
    MFM decoding (track → 11 sectors × 512 bytes + checksums) → B4 `CMD_READ`. `src/exec/trackdisk.s`: 2nd device, ROMTag
    AUTOINIT NT_DEVICE pri 20 → DeviceList; `Open(unit)` validates the number (DF0-3 → io_Unit = base+TDU_UNIT0+unit*8,
    io_Device = base, OpenCnt++; unit ≥ 4 → OpenDevice failure io_Error/io_Device=0). `BeginIO` stub `IOERR_NOCMD`
    (advisor safeguard: will have to ReplyMsg as soon as a real consumer calls it, otherwise DoIO hangs). Units =
    placeholders (→ Unit+MsgPort in B2). Advisor safeguards: assertion `io_Unit == base+TDU_UNIT0` (EXACT address,
    not a non-load-bearing "≠0"); do not freeze the unit layout; do not touch the strap (FindName load-bearing in
    C). Serial proof **M6T**: FindName(DeviceList) + version + NT_DEVICE + Open(0) OK + Open(4) fails. RED
    `TD_NO_UNITCHECK` (unit 4 wrongly opens) → M6T absent. COOP non-reg. ⚠️ B1 is NOT yet the read (= B2-B4);
    heads-up B2: CIA-B shared with the M7a MICROHZ unit. NEXT: B2 (user checkpoint — the hardest).
  - **B2 / M6u — reading a raw MFM track from DF0 (DONE, the hardest).** The ROM accesses the
    disk hardware for the 1st time. `src/exec/disk.i` (clean-room Paula/CIA disk registers HRM+NDK) + `td_read_track0` in
    trackdisk.s. Advisor safeguards (unblocked everything on the 1st try): (1) **CIA-B DDRB=$FF** before writing PRB
    (otherwise PRB drives nothing — never set before, suspect no. 1); (2) MINIMAL sequence first (motor+select+DMA),
    WITHOUT step or side-select (DSKDIREC/DSKSIDE polarities not verifiable from memory — postponed; the head is at track
    0 at reset; the sync count does not care about the track); (3) de-risk the ADF mounting (confirmed by the reading
    itself); (4) ADKCON=$8400 (SETCLR|WORDSYNC, DD); DSKRDY timeout+continue; DSKBLK masked in INTENA
    (poll INTREQR); timeout on EACH loop. Sequence: DDRB=$FF, PRB motor-on+select DF0 (latched via the SEL0 edge),
    spin-up, disk DMA (DSKSYNC=$4489, DSKPT=chip buf, DSKLEN×2, DMACON DSKEN), poll DSKBLK with timeout, stop (clear
    ONLY DSKEN, not MASTER=display). Writes only CIA-B PRB -> MICROHZ/M7a timers intact. Serial proof
    **M6U** + emitted sync count (routine `ser_puthex` added): **SYNCS=0016 = 22 `$4489` words** read (= 11
    sectors × 2 header syncs; `$4489` impossible in normal MFM + MEMF_CLEAR buffer -> 0 false positives).
    RED `TD_NO_DMA` (DMA not armed -> buffer at 0 -> 0 syncs) -> M6U absent. Control without disk -> timeout -> M6U
    absent (proves that M6U comes from the disk). COOP non-reg. `tests/boot_test.sh` extended: optional 5th ADF arg in DF0.
    NEXT: B2b (step/side to a precise track) then B3 (MFM decoding). User checkpoint.
  - **B3 / M6v — MFM decoding of the track (DONE, algorithmic core).** User: "go B3" (+ B4 + B2b chained).
    Safeguard: the Amiga MFM algorithm (odd/even split + checksums) = a fact NOT to be coded from memory → LOCKED
    first by a Python round-trip (reference script outside the repository): decode `((odd&$55555555)<<1)|(even&$55555555)` (odd
    1st), header/data checksums = XOR of the MFM longs & mask. `td_decode_track(rawbuf, sectorbuf)`: scans the
    $4489 syncs, decodes info (format=$FF, sector no. < 11), checks the header checksum (XOR of 10 info+label longs) AND the data
    checksum (XOR of 256 longs), decodes 512 bytes into sectorbuf+no.*512, returns the number of valid sectors. Sector offsets
    (from info_odd): +0 info +8 label +40 hdrchk +48 datachk +56 data_odd +568 data_even, end +1080. Serial proof
    **M6V** + emitted count: **SECTORS=000B = 11** sectors decoded+verified AND sector 0 == "DOS\0" (OFS bootblock).
    RED `MFM_BAD_DECODE` (skips the <<1 of the data combine → wrong data but checksums (on raw MFM) still OK →
    SECTORS stays 11 but sector 0 != DOS) → M6V absent: isolates the correctness of the data decoding. Control without disk
    → M6V absent. COOP non-reg. Build fixes: `.s` branches→word (large routine), `lsl.l #9` forbidden (max 8) →
    `lsl #8`+`add`. NEXT: B4 (CMD_READ) then B2b (step/side).
  - **B4 / M6w — device CMD_READ (DONE).** `trackdisk_beginio` (the B1 stub `IOERR_NOCMD`) becomes a real handler:
    CMD_READ -> td_read_track0 + td_decode_track + copy of io_Length bytes from sectorbuf+io_Offset to io_Data,
    sets io_Actual/io_Error; other commands -> IOERR_NOCMD. **ReplyMsg if NOT quick** written (B1 debt) BUT ⚠️ only
    the QUICK path is proven by M6W; the non-quick one will be exercised by a real DoIO (strap/dos) in C.
    Limited to track 0 (offset+length <= 11*512) as long as B2b does not exist. disk.i constants: CMD_READ=2, IOF_QUICK,
    IO_ACTUAL/LENGTH/DATA/OFFSET (IOStdReq 32/36/40/44). Serial proof **M6W**: IOStdReq (CMD_READ, offset 0, length
    512, IOF_QUICK) -> BeginIO via vector -30 -> io_Error==0 & io_Actual==512 & sector read == "DOS\0". RED
    `TD_READ_NOCMD` (BeginIO does not recognise CMD_READ) -> M6W absent. ⚠️ M6W does a READ -> gated on "disk
    present" (flag d4 set by the merged M6U/M6V read) to avoid a 2nd timeout without disk (otherwise M7A shifted):
    M6W only runs with a disk (fast read). Build fix: .s branches->word (large BeginIO routine). NEXT: B2b.
  - **B2b / M6x — step/seek + side-select (DONE; trackdisk COMPLETE).** The DSKDIREC/DSKSIDE polarities deferred since
    B2 (not verifiable from memory) — guessed then validated in the emulator ON THE 1ST TRY. `td_read_track0` -> `td_read_track(d0=
    track no.)`: recalibration to cylinder 0 (step OUT, direc bit1=1, until DSKTRACK0, cap 85) + step IN (direc bit1=0)
    up to cylinder=track/2 + side-select (DSKSIDE bit2: side 0 = $77, side 1 = $73); DSKSTEP pulse (1->0 edge) +
    settle busy-loop; td_read_track0 = track 0 wrapper (M6U/M6V/BeginIO unchanged: track 0 -> 0 steps -> no regression).
    td_decode_track returns d1 = decoded track no. (oracle). Serial proof **M6X** + diagnostic "M6X TRACK=XXXX": read
    track 2 -> TRACK=0002 + 11 sectors with track==2 (validates the seek AND the side: a wrong side would read track 3). RED
    SEEK_NOSTEP (no step-in -> stays on track 0 -> TRACK=0000) -> M6X absent. Gated on disk present (d4) -> M7A intact.
    trackdisk.device COMPLETE: reads any logical sector of any track of DF0.
  - **C / M6y — "it boots!": the strap reads, validates and EXECUTES the bootblock (DONE).** `strap_boot` reads sectors 0+1
    of DF0: (`CMD_READ` offset 0 len 1024 = bootblock, WITHIN track 0 -> no need for the multi-track wiring for C), validates
    the "DOS" magic + **additive checksum** (end-around-carry sum of the 256 longs == `$FFFFFFFF` — ADDITIVE, classic trap
    vs the XOR of the MFM checksums; algorithm ported then simulated in Python before use), then **JSR to the boot code at +12** (A6=SysBase,
    A1=IORequest; dos handoff A0 IGNORED = deliberate deviation without dos). Bootable -> "booted" (**M6Y**, no insert-disk);
    invalid checksum (formatted ADF = checksum 0, verified empirically) or no disk -> 0 -> insert-disk (**M6R**) = REAL
    1.3 trigger. Proof: marker **CBOOT** emitted by the bootblock ITSELF (proves the jump). 6 scenarios: GREEN+bootable
    ADF (CBOOT+M6Y), GREEN+formatted ADF (M6R, checksum rejects), without disk (M6R+M7A ok), RED STRAP_NO_EXEC (M6Y without
    CBOOT = isolates execution), RED STRAP_BAD_CSUM (good block rejected = isolates validation), COOP. trackdisk fix required
    for C: recalibration ALWAYS done (read from a known position — a track-0 read after a seek silently read the wrong
    track) + detection of an absent drive via DSKRDY timeout (fast no-disk probe). Custom bootable ADF
    regenerable: `tests/mk_boot_adf.sh` (xdftool format + `tests/bootblock_c.s` assembled to a raw binary + `tests/patch_bootblock.py`
    which sets the checksum and round-trips bootability; output `assets/boot_c.adf`, gitignored). NEXT: D (real dos.library,
    packets) — prerequisite = multi-track `CMD_READ` offset->track wiring to read the filesystem beyond track 0.
  - **M6z — MULTI-TRACK CMD_READ (D prerequisite, DONE).** `trackdisk_beginio` (B4: track 0 only) becomes multi-track:
    the byte offset -> (track, sector) via `bloc=offset/512`, `piste=bloc/11` (`DIVU #11`), `secteur=bloc%11`; the loop reads
    EACH touched track (`td_read_track`+`td_decode_track`, sectorbuf reused), copies up to the end of the track and advances -> a
    request that CROSSES a track boundary is served in several reads (dos will be able to read the filesystem beyond track 0).
    trackdisk contract honoured: `io_Offset`/`io_Length` multiples of TD_SECTOR (512) -> `IOERR_BADLENGTH` guard; bound guard
    `TD_DISKBYTES` (1760*512). Registers: the loop keeps its state in d2-d7/a2-a5 (all preserved by `td_read_track`
    [saves d2/d3/d6/a2, does not write the rest] AND `td_decode_track` [saves d2-d7/a2-a5]). Serial proof **M6Z** = 2 reads via
    `BeginIO` (the real device path): (1) root block @ **block 880 = track 80** (cyl 40) -> primary type +0 == 2 (T_SHORT) AND
    secondary type +508 == 1 (ST_ROOT) — a wrong mapping would return track 0 (bootblock); (2) **SPANNING** read offset
    `10*512` length 1024 = blocks 10+11 -> CROSSES the track 0/1 boundary, assembles "SPAN0010" (block 10 = track 0 sect 10) +
    "SPAN0011" (block 11 = track 1 sect 0) placed by `patch_bootblock.py` in free blocks (Python round-trip). RED
    `TD_NOSEEK` (always reads track 0, sector/byte correct -> the read completes without crash) -> both checks fail ->
    M6Z absent (isolates the offset->track mapping, M6D_BAD_BPTR discipline). GREEN-BOOT: M6Z + non-reg (M6U/V/W/X, CBOOT/M6Y, M7A/M7L,
    complete M3F..M7F set, 0 FAILED). RED: M6Z absent, rest intact. CTRL-NODISK: M6Z gated (d4), no timeout added, M6R+M7A ok.
    NEXT: dos.library proper (BCPL packets model / `LoadSeg` / handlers / OFS) — to be re-broken down + user checkpoint.
  - **D1 — read-only OFS (DONE).** `src/dos/ofs.s` + `ofs.i`: `ofs_read_file(name, dest, max)` reads a file
    by name from DF0: by walking the OFS filesystem — **INTERNAL machinery** (NOT yet BCPL packets/handler
    = D3), relies on trackdisk `CMD_READ` (M6z). OFS algorithm **locked empirically** on a test ADF
    (asset, NOT the ROM, B3 MFM round-trip discipline): root@880; hash `h=len ; h=(h*13+toupper(c))&$7FF ;
    idx=h%ht_size`; hash table -> header (BCPL name @long108, sec_type @long127=ST_FILE, first_data @long4,
    hash_chain @long124); OFS data block (type 8, data_size @long3, next @long4, data @+24). Case-
    insensitive (ASCII toupper a-z, non-international OFS). Guards (coding-principles "validate before use"): type
    T_SHORT/T_DATA, sec_type ST_FILE, block bounds [2,1760), ht_size<128, data_size<=488, `max` buffer guard;
    hash-chain/data loops **capped** (anti-hang on a corrupted disk). Inter-module call via `jsr` (ofs.o linked out of
    16-bit `bsr` range). Serial proof **D1**: returned size == 1024 (primary discriminant) + markers at the
    data block boundaries (@0/@488/@976) -> proves found-by-name ("kickslop" vs stored "KickSlop" exercises
    case-folding) AND complete data chain (3 blocks). RED `OFS_NO_DATACHAIN` (does not follow next_data) -> size 488
    -> D1 absent (isolates the chaining). GREEN-BOOT (D1 + non-reg M6U..M6Z/CBOOT/M6Y/M7A, 0 FAILED) + RED + CTRL-NODISK
    (D1 gated d4) + COOP (D1 + M3F). ⚠️ Slowness: each block = 1 track read with recalibration (debt: no
    cylinder tracking) -> the full floppy boot takes ~40 s under FS-UAE (WAIT=60). FFS + subdirectories
    + writing out of scope. Test file written by `tests/mk_ofs_testfile.py` + `xdftool write` (mk_boot_adf.sh).
  - **D2 — LoadSeg (DONE).** `src/dos/loadseg.s`: `dos_loadseg(name)` -> BPTR seglist | 0 + `dos_unloadseg(BPTR)`.
    Loads an AmigaDOS **"hunk"** executable from the OFS (via D1's `ofs_read_file`), allocates one segment per hunk,
    copies the contents, **APPLIES the relocations**, builds the BPTR seglist and returns it. INTERNAL machinery (no
    packets = D3). Hunk format **locked empirically** (binary `vlink -s -bamigahunk`, NOT the ROM):
    HUNK_HEADER (resident libs=0, table_size, first, last, N sizes [bits 30-31 = memory flags masked]); body
    per hunk: CODE/DATA (nlongs + data) or BSS (nlongs, no data), **HUNK_RELOC32 ($3EC** — vlink does NOT emit the
    compact $3FC variant: we handle $3EC, and $3FC/SYMBOL/DEBUG -> CLEAN failure, never a silent skip of a
    relocation), HUNK_END. Seglist (AmigaDOS convention, checked against AROS InternalLoadSeg): block `[LONG size][BPTR
    next][contents]`; the BPTR points to the next field (block+4) -> contents at `(BPTR<<2)+4` = block+8. Deliberate D2
    deviations: chip/fast flags ignored (MEMF_PUBLIC); first!=0 / SYMBOL / resident libs / $3FC / overlays not
    supported (clean failure) [since lifted: memory flags honoured, SYMBOL skipped, overlays loaded (2026-11-06)]. Serial proof **D2LOADSEG**: test executable `D2Test` (CODE + DATA section + 1
    32-bit CODE->DATA relocation) loaded + relocated + EXECUTED -> the code ITSELF emits "D2LOADSEG OK" from
    RAM (same logic as CBOOT in C: the marker comes from the loaded code = proof that it runs WITH relocation). RED
    `D2_NO_RELOC`: load OK but relocation NOT applied -> the absolute pointer stays the link-time offset (0) -> the
    code reads low RAM (address 0 = null byte -> nothing emitted) -> "D2LOADSEG OK" absent, WITHOUT a bus error -> isolates
    the application of relocations. GREEN-BOOT (D2 + non-reg D1/M6*/CBOOT/M6Y/M7A, 42 lines, 0 FAILED) + RED (D2
    absent, D1+rest intact) + CTRL-NODISK (D2 gated) + COOP (D2 + M3F). Test executable: `tests/loadseg_d2.s`
    -> `vasm -Fhunk` + `vlink -s -bamigahunk` -> `xdftool write D2Test` (mk_boot_adf.sh). ⚠️ WAIT>=90 (disk I/O).
    NEXT: D3 = architectural core (BCPL packets model + DF0: file-handler + CreateProc + CLI) -> user checkpoint.
  - **D3 — dos packets / handler / process → "run a command" (in progress).** User+advisor framing
    (2026-10-17): approach 1 (faithful observable packet ABI, processes in C, no BCPL runtime). ANALYSIS track
    launched straight away (isolated agent) → `docs/analysis/dos-v34-spec.md` + `dos-boot-sequence.md` (reviewed, clean-room
    review gate passed). Design: `docs/D3-dos-design.md`. Broken down D3a→D3d, proven from the boot scaffold
    as real processes (scheduled phase, after `dispatch_in`).
    - **D3a — Process + CreateProc + packet round-trip (DONE).** `src/dos/process.s` (`proc_create`) + `dospkt.i`
      (V34 layout of Process/DosPacket/StandardPacket/FileHandle/DeviceNode + ACTION_*). `proc_create` builds a
      `Process` (exec Task + embedded `pr_MsgPort` @0x5C), FULLY initialises the port in the parent (sigbit
      reserved `DOS_PORTSIG=8` = SIGB_DOS, pre-allocated via TC_SIGALLOC → no handshake, no race), `AddTask`,
      returns the port's APTR. Proof **D3A**: a driver process sets up a StandardPacket, `PutMsg` to the port of an
      echo handler process, `WaitPort`/`GetMsg` the reply (round-trip via M3d synchronous switch) → correct echo.
      RED `D3A_NO_REPLY` (handler does not `ReplyMsg` → driver blocked) → D3A absent. GREEN-BOOT (D3A + non-reg
      D1/D2/M3F/M7A/M7C/M7D, 0 FAILED) + RED + COOP (D3A exercised COOPERATIVELY, SCHED_ON=0) + CTRL-NODISK (D3A
      present, disk-independent; D1/D2 absent). GREEN checksum `0x47B39093`. NEXT: D3b (OFS handler).
    - **D3b — DF0: file-handler process + dos_sendpkt (DONE).** `src/dos/handler.s` (`dos_handler_df0`, `dos_handler` since DF1): a real
      process that loops `WaitPort`/`GetMsg` and serves `ACTION_FINDINPUT`/`READ`/`END` via `ofs_read_file` (D1).
      `FINDINPUT` (ARG1=BPTR FileHandle, ARG3=BSTR name) reads the WHOLE file into a handler buffer (deliberate
      simplification: incremental OFS reads deferred), sets `fh_Arg1`=state{buffer,size,pos}; `READ`(key,buf,len)
      copies+advances (RES1=bytes, 0=EOF); `END` frees. Helper `dos_sendpkt` (process.s): sets up the StandardPacket,
      `PutMsg`+`WaitPort`/`GetMsg` on `ThisTask->pr_MsgPort` (no public DoPkt in V34). Proof **D3B**: an fs-driver
      opens/reads/closes "kickslop" THROUGH the handler by packets → 1024 bytes + markers @0/@488/@976. RED
      `D3B_NO_READ` (handler does not serve READ → EOF) → wrong bytes → D3B absent (FINDINPUT/END work). GREEN-BOOT
      (D3B + D3A + non-reg D1/D2/M3F/M7C/M7D, 0 FAILED) + RED + CTRL-NODISK (D3A present disk-indep, D3B absent) +
      COOP. **Discovery (anticipated by the advisor)**: our trackdisk is CPU-BOUND (recalibration busy-loops, not
      interrupt-driven) → the handler (pri 6) starves lower-priority tasks during its long read → the
      markers of pri<6 arrive LATE → **WAIT≈280 s** required. Serial interleaving fix: the echo pair (D3a) moves to
      pri 8/7 (> OFS pair 6/5) → D3A emitted EARLY, D3B late → non-concurrent emissions. GREEN checksum `0x927FC4D9`.
      ⚠️ The CPU-bound slowness will exceed 5 min with D3c/D3d → **cylinder-tracking = dedicated increment BEFORE D3c**
      (advisor: do not bundle it here; it re-verifies all the disk proofs). NEXT: cylinder-tracking, then D3c.
  - **Cylinder-tracking (trackdisk, dedicated increment — DONE).** Resolves the "recalibration on every read" debt
    (which became blocking: boots > 5 min under the scheduler with D3b). `td_read_track` tracks the current cylinder
    (`TD_CURCYL`, reliable iff `TD_CYLVALID`) and steps the **delta** to the target (IN/OUT depending on the sign) instead of
    recalibrating to 0 on every read; recalibration (step OUT until DSKTRACK0, cap 85) ONLY if the position is
    unknown. CLEANLY fixes bug C (reading after a seek read the wrong track): the delta brings the head back to the
    right cylinder. Bug caught along the way: `.rd_settle` clobbered **d3** (which the new code uses for the target
    cylinder) → wrong `TD_CURCYL` stored → the next seek went to the wrong cylinder (M6X read correctly but M6Z/D1/D2
    off by 1); fix: `.rd_settle` counts in d0. Proof: at **WAIT=90** (impossible before — it needed 280) the whole
    disk suite is correct (M6X TRACK=0002, M6Z, D1, D2, CBOOT/M6Y, D3A, **D3B**, M3F, 0 FAILED). RED
    `TD_NO_CYLTRACK` (forces recalibration on every read = old behaviour) → D3B absent at WAIT=90 (too
    slow) → isolates the speed GAIN. Correctness re-check: RED `SEEK_NOSTEP` → M6X TRACK=0000, "M6X SEEK OK"
    absent (seek still RED-proven). COOP (WAIT=90) + CTRL-NODISK (seek not reached without disk). GREEN checksum
    `0xC422E669`. Remaining DEBT: no invalidation on disk change (real eject/swap + periodic recal = M7).
    NEXT: D3c (user-facing dos Open/Read/Close via packets).
  - **D3c — user-facing dos Open/Read/Close (LVO) via packets (DONE).** `dos_lib.s`: vectors `Open`(-30)/`Close`
    (-36)/`Read`(-42) implemented. `Open(name,mode)` resolves the handler via `DosInfo.di_DevInfo` → 1st `DeviceNode`
    → `dn_Task`, allocates a `FileHandle` (+ BSTR buffer for the name), sets `fh_Type`=handler port, sends `FINDINPUT`
    (ARG1=BPTR(fh), ARG3=BPTR(name)) via `dos_sendpkt`, returns BPTR(fh). `Read` routes via `fh_Type`/`fh_Arg1`
    (ACTION_READ). `Close`: `END` + FreeMem. a6 switches DosBase↔SysBase; StandardPacket on the process's stack;
    called from a PROCESS (pr_MsgPort = reply port). Boot setup: mounts a `DeviceNode` (dn_Task=DOS_FSPORT)
    in `di_DevInfo`. Proof **D3C**: a client process `OpenLibrary(dos)` + `Open`/`Read`/`Close` "kickslop" through
    the LVOs → 1024 bytes + markers. RED `D3C_NO_FHTYPE` (Open does not set `fh_Type` → Read safeguard returns 0) → D3C
    absent (isolates the wiring of the Open→Read route). GREEN @WAIT=90 (D3C + non-reg D1/D2/D3A/D3B/M3F/CBOOT/M6Y, 0
    FAILED) + RED + CTRL-NODISK + COOP. GREEN checksum `0x7329BBD6`. NEXT: D3d (LoadSeg via dos + run).
  - **D3d — LoadSeg THROUGH dos + running a command (DONE; CLOSES D3).** `loadseg.s` refactor: the hunk parser
    is extracted into `ls_load_hunks(filebuf, taille)` (does NOT read/free the file); `dos_loadseg` (D2) becomes
    a wrapper (ofs read + ls_load_hunks). D3d client (process): `OpenLibrary(dos)` → `Open`/`Read`/`Close`
    "d3dtest" THROUGH THE DOS LVOs (packets → handler → OFS) into a filebuf → `ls_load_hunks` → `JSR (seglist<<2)+4`.
    The command (`tests/loadseg_d3d.s`, hunk with RELOC32) itself emits **D3D LOADSEG-VIA-DOS OK** from RAM
    → proves the whole "load+run a command via dos" chain (read by packets + reloc + run). RED
    `D3D_NO_RUN` (loads but skips the JSR) → command not run → D3D absent (isolates execution). GREEN @WAIT=90
    (D3D + non-reg D1/D2/D3A/D3B/D3C/M3F, 0 FAILED) + RED + CTRL-NODISK + COOP. Executable `D3DTest` written to the ADF
    (mk_boot_adf.sh). **"Run a command" target REACHED.** Deferred (E/F): interactive CLI, real bootstrap
    (Initial CLI, startup-sequence, console, requesters), incremental OFS reads, Write/Lock/Seek.
  - **D3e — LoadSeg / UnLoadSeg via the REAL LVO vectors (DONE).** `dos_lib.s`: `dos_fn_loadseg` (vector 25 →
    **LVO -150**) + `dos_fn_unloadseg` (vector 26 → **LVO -156**). LoadSeg opens via the real `Open`(-30, MODE_OLDFILE),
    reads the WHOLE file via the real `Read`(-42, loop until EOF; sequential handler) into a buffer, parses via `ls_load_hunks`
    (hunks + reloc → BPTR seglist), closes via `Close`(-36). Splits the jump table's `dcb.l 24` into 17/LoadSeg/
    UnLoadSeg/5 (canary **M6D**: DateStamp -192 stays vector 32 → table not shifted). Proof **D3E LOADSEG LVO OK**:
    `d3e_client` (process pri 2) loads "D3DTest" through `jsr DOS_LVO_LOADSEG(a6)` → non-null seglist → UnLoadSeg. `d3d_client`
    (inline load) REMAINS the independent baseline (advisor: do not refactor a proven test — add+prove); RED
    `LOADSEG_LVO_UNWIRED` (-150 → dos_null) → D3E absent, **D3D baseline green** → isolates the wiring of the LVO vector. GREEN
    (ADF): M6D + D3C + D3D + D3E + GAMEPORT/M6R/GP-LIVE + DISK VALID + KEYMAP + F1BOOTOK + M7A/M7E/M7F, 0 FAILED; md5
    `8d9517af1ea696af8334e35b171c00ac`. **Scope (revealed by the Lemmings test)**: loads OUR hunk executables via the
    real LVO path; whole-file buffered (≤ 16 KB, no streaming), DF0: OFS handler only → NOT enough to run
    commercial software (missing `Lock`/`Seek`/`Examine`/`Write`, `expansion.library`, streaming; and boot.s is a
    dev harness). `sh_exec_cmd` (E3) keeps its inline load (not touched: do not risk E3/F1/F2b).
  - **expansion.library (autoconfig, parity) DONE.** `src/exec/expansion.s`: AUTOINIT NT_LIBRARY resident pri 110.
    ExpansionBase (Library + eb_Flags@34 + ConfigDev list). Real functions at the LVO offsets confirmed on AROS
    `expansion.conf` (OpenLib slot0; AddConfigDev slot4=-30, AllocConfigDev slot7=-48, FindConfigDev slot11=-72,
    FreeConfigDev slot13=-84; LVO=-6*(slot+1)); rest = exp_null. Proof **EXPANSION OK** (synchronous early):
    OpenLibrary v37→0 (gate) / v34→base; AllocConfigDev→AddConfigDev→FindConfigDev exact+wildcard+miss; cleanup
    guarded (Remove iff ln_Succ≠0). RED `EXP_NO_ENQUEUE`. Non-reg resident scan (M4 RESIDENTS OK) + complete ADF,
    0 FAILED, md5 `b0bb2f2f92f21b84be18a0ab49665ef3`. **Offsets verified via AROS, NOT from memory** (the
    WebSearch summary had got it wrong by placing AddBootNode first). **Lemmings twist**: the bootblock opens expansion
    at **v37** (KS 2.0) → the V34 gate returns 0 → expansion branch skipped (tolerated) → this module does NOT unblock
    Lemmings, it is parity. Deferred: ConfigBoard/ReadExpansionRom (HW probe), MakeDosNode/AddBootNode (mounting).
    15/16 ROMTags (RESMAX; 1 spare slot).
  - **Missing dos functions: IoErr(-132) + Seek(-66) DONE.** `dos_lib.s`/`process.s`/`handler.s`. IoErr returns
    `pr_Result2`; `dos_sendpkt` copies `dp_Res2 → pr_Result2` after each packet (faithful, a single point); the
    handler sets `DP_RES2=ERROR_OBJECT_NOT_FOUND`(205) on an Open not found (checked BEFORE building — it set 0,
    IoErr would have been hollow). Seek sends `ACTION_SEEK` → the handler adjusts `HS_POS` (buffers the whole file),
    bounded, returns the OLD position. Vectors 11/22 wired (DateStamp -192 stays vector 32 = canary). Proof **DOS
    IOERR SEEK OK** (`d3f_client` pri 5, emits under Forbid): Open of absent file→0 + IoErr≠0; Open d3dtest→IoErr 0; Read 4
    → Seek(0,BEGINNING) → Read 4 identical. REDs `DOS_NO_IOERR` (no dp_Res2 propagation) + `HND_NO_SEEK` (handler
    ignores SEEK). GREEN ADF (74s: DOS IOERR SEEK OK + EXPANSION + D3C/D3D/D3E + E3 + M7, 0 FAILED), md5
    `6a24da8be3eee8a03126e86e0b715122`. **Write(-48) deferred** (advisor): read-only OFS → a file Write would only
    prove the clean failure; a real Write = console wiring (con_handler + Output -60), outside the scope of this
    increment. Other dos functions (Lock/Examine/CurrentDir/Input/Output...) still not implemented.
  - **dos functions: Write(-48) + Input(-54) + Output(-60) + CurrentDir(-126) DONE.** `dos_lib.s`. Write sends
    ACTION_WRITE to the fh_Type port (con_handler -> serial; read-only OFS -> error). Input/Output = pr_CIS/pr_COS of
    ThisTask. CurrentDir sets pr_CurrentDir + returns the old one. Vectors 8/9/10/21 (DateStamp -192 stays vector 32 =
    M6D canary intact). Proof **DOS WRITE OK** (d3g_client): CurrentDir round-trip + Input read back + pr_COS = console
    FileHandle (fh_Type=DOS_CONPORT) -> Output() returns this BPTR -> Write(Output(),msg) -> the marker is emitted BY the Write
    via con_handler (proves all 4 at once). RED `DOS_NO_WRITE`. GREEN ADF (DOS WRITE OK + M6D + EXPANSION + GAMEPORT
    + DISK VALID + M7, 0 FAILED), md5 `f4e3af995dd7ea908220b02b627be860`. **Write via CONSOLE** (not a file: OFS
    read-only).
  - **LoadSeg cap bump 16K -> 32K DONE** (NOT streaming). The read cap was the handler's whole-file buffer
    (HND_FILEMAX) + LoadSeg's (LS_LOADMAX), 16 KB each. Raised to a shared `DOS_FILEMAX`=32 KB (exec.i;
    handler.s/dos_lib.s/loadseg.s reference it). Advisor: real streaming (incremental OFS read on HS_POS)
    = large blast radius on the proven ACTION_READ (D1/D3B/D3C/D3D/E3/F1) for nothing consumable now -> DEBT
    deferred; do an honest, proven cap bump. Proof **LOADSEG BIG OK**: `tests/loadseg_big.s` (hunk > 16 KB:
    24 KB DATA + sentinel at the end + 1 RELOC32) written to the ADF (`bigseg`), loaded by `d3h_client` via LoadSeg(-150)
    + executed -> checks the sentinel (the whole large DATA read) -> emits. RED `LOADSEG_CAP16K` (re-caps 16 KB ->
    bigseg truncated -> absent; small d3dtest OK). ADF non-reg: D3E + E3 + D1 + M6Z + DOS WRITE, 0 FAILED, ADF layout
    preserved (spanning blocks 10/11 not disturbed by bigseg). md5 `9b279b64b48f65b3a30a8e5ea3c323c8`. 2 concurrent
    buffers = 64 KB transient (safe). **Real streaming (incremental OFS) remains deferred** with Lock/Examine.
  - **Lock(-84) + UnLock(-90) + Examine(-102) + ExNext(-108) DONE.** `dos_lib.s`/`handler.s`/`ofs.s`/`ofs.i`/`dospkt.i`.
    Locks + OFS directory reading. Lock resolves DF0: → handler port, name → long-aligned BSTR, `ACTION_LOCATE_OBJECT`;
    the handler resolves the path via `ofs_name_to_block` (`xxx:` prefix ignored, empty/":" → root, `/`-separated
    subdirs, final element file OR dir), allocates a `FileLock` {fl_Key=block, fl_Access=mode, fl_Task=port, private cursor
    flp_Bucket/flp_ChainBlk} → BPTR. UnLock: port via `fl_Task` → `ACTION_FREE_LOCK` (FreeMem). Examine: `ofs_fill_fib`
    (DiskKey/DirEntryType=sec_type/FileName BCPL→C/Size=byte_size@324 if file) + cursor reset. ExNext: `ofs_dir_next`
    (walks the current hash chain then advances bucket by bucket in the hashtable, fills the FIB, advances the
    cursor INSIDE the lock). Vectors 14/15/17/18 (DateStamp -192 stays vector 32 = canary). **Offset OFSB_FILESIZE=324
    verified on the ADF (kickslop block 866 → 1024) BEFORE building**, reconfirmed by the boot assertion. Proof **DOS LOCK
    EXAMINE OK** (`d3i_client` pri 5, emits under ser_lock): (A) Lock("kickslop")→Examine → DirEntryType<0 + fib_Size==1024
    (oracle); (B) Lock(":")→Examine (directory)→ExNext loop finds the 1024-byte file entry (= kickslop). RED
    `OFS_NO_DIRNEXT` (found=0 straight away → marker absent, **D1 OFS READ stays GREEN** = isolates enumeration). GREEN ADF
    (DOS LOCK EXAMINE OK + non-reg D1/D3E/DOS IOERR SEEK/DOS WRITE/LOADSEG BIG/M6Z/E3/F1BOOTOK, 0 FAILED), md5
    `5e87d941e436cd29769959d0711c21e2`. **DELIBERATE deviation**: ExNext cursor in the lock (not in the FIB as in the
    real OS) → one lock = one enumeration (enough for the harness, documented).
  - **REAL OFS streaming DONE** (debt lifted). `ofs.s`/`handler.s`/`ofs.i`. The DF0: handler NO LONGER buffers the
    whole file at FINDINPUT: primitives `ofs_stream_open`/`ofs_stream_read`/`ofs_stream_seek`, one SS_* state per
    FileHandle (1 AllocMem = fields + ioreq + 512-byte block buffer) with cursor {byte_size, pos, first_data, cur_block,
    blk_base}. Incremental reading data block by data block (O(1) footprint = 512 bytes instead of O(size)); "dumb
    seek" (rewind if the target is backwards, forward movement is done by the READ loop). NO size cap any more
    (`HND_FILEMAX` removed from the handler; `DOS_FILEMAX` remains for LoadSeg). `ofs_read_file`(D1)+`dos_loadseg`(D2) intact.
    Proof **OFS STREAM OK**: `d3j_client` opens "BigData" (48000 bytes > old 32 KB cap, 99 data blocks), reads it all in
    4096-byte chunks (12 Reads) → total==48000 + sentinel $B16B00B5 + cross-block Seek(500) == $A5EE3780. Self-sufficient
    (the old code would have truncated at 32 KB). RED `STREAM_CAP32K` (re-caps 32 KB → BigData truncated → absent; <32 KB
    green). File `tests/mk_bigdata.py` added to the ADF without disturbing the layout (blocks 10/11 checked).
  - **Forbid atomicity at the preemption point DONE** (PRE-EXISTING bug revealed by streaming). `interrupts.s`. The
    preemption path (`intr_isr_defer`, int2/int3/int6 tail) consumed `EB_ATTNRESCHED` (set before the Forbid by
    a stale quantum, or by `exec_Signal` of a higher-priority task during the Forbid) and switched at IRQ exit
    testing ONLY the S bit — NOT `EB_TDNEST`. So a task under Forbid could be preempted in the middle of `ser_puts`
    → interleaved markers (streaming lengthened the emission windows → visible D3B/DOS-IOERR collision). Fix:
    `EB_TDNEST`/`EB_IDNEST` guard in `intr_isr_defer` (if Forbid/Disable active → no deferred dispatch; AttnResched
    stays pending → consumed at the next non-forbidden IRQ or by Permit's voluntary yield via `trap #1`, unguarded).
    DETERMINISTIC proof **FORBID ATOMIC OK** (task_fa pri 3: Forbid → Signal(task_fb pri 7) → waits 2 VBlanks under
    Forbid → fb did NOT preempt). RED `SCHED_NO_FORBID_GATE` (removes the guard → fb preempts → absent; M3F LIVE stays
    green). ⚠️ Corrects the belief "ser_lock = total atomicity" (it was temporal separation). **Still deferred**:
    take the harness out of the boot path (`make kick-prod`).
- **E — interactive CLI (on serial, via DOS FileHandles).** Architectural decision (advisor + firewall): the IO channel is the
  SERIAL line (the whole proof harness is serial; no console.device/keyboard; "Real bootstrap" = where
  console.device/keyboard/requesters live). The CLI does ALL its IO via DOS FileHandles (`pr_CIS`/`pr_COS`) served by
  a **serial-console handler** process (same shape as `dos_handler_df0`) — in F we replace this handler by a
  console.device without touching the shell. Proven prerequisite: **RX spike** (FS-UAE delivers host→Paula serial input via
  SERDATR bit 14 RBF; harness `tests/boot_test_interactive.sh` injects into `ser_cap`). Broken down E1→E3:
  - **E1 — serial-console handler (DONE).** `src/dos/conhandler.s`: process serving `FINDINPUT`(open)/`WRITE`(emits
    on serial, bounded TBE poll)/`READ`(reads a line from RX with echo)/`END`. READ blocks CLEANLY via polling on a
    timer.device MICROHZ tick (BeginIO TR_ADDREQUEST + Wait, `task_timer` precedent) — NO busy-poll (COOP-safe),
    NO level-5 RBF interrupt (deferred to F, see M7k). Mounted as global port `DOS_CONPORT`. Proofs: **WRITE +
    packets** in the 4 standard scenarios (handler in Wait = clean idle without input): GREEN "E1 CON WRITE OK" +
    non-reg D1/D2/D3A/D3B/D3C/D3D/M3F (0 FAILED) + RED `E1_NO_WRITE` (marker absent, round-trip intact) +
    CTRL-NODISK (console works WITHOUT disk) + COOP. **READ** proven in the interactive harness: inject "hello\r" →
    "E1 CON READ=hello" (round-trip RX→handler→line→echo→client). GREEN checksum `ad9f0f37`.
    NEXT: E2 (shell process: prompt loop → read line → parse → dispatch + builtins).
  - **E2 — interactive shell (DONE).** `src/dos/shell.s`: `shell_main` = process that opens the console (E1 handler via
    DOS packets), emits a banner, loops prompt `> ` → read line → parse 1st word → dispatch. Builtins `ver`
    (version banner) and `echo <args>` (re-emits the args); otherwise `?`. Replaces the E1 proof client as the
    ONLY consumer of the console (a single serial console = one reader at a time); the E1 handler is reused
    as is. NO BCPL CLI (pr_CLI/Execute = F). Proofs: GREEN "E2 SHELL READY" + non-reg D1/D2/D3*/M3F (4
    scenarios); interactive: "ver\r" → "E2 SHELL ver OK" (parse+dispatch), "echo E2ECHOOK\r" → "E2ECHOOK";
    RED `E2_NO_DISPATCH` ("ver" → "?", marker absent); NODISK (banner without disk); COOP. GREEN checksum
    `aa9e1b78`. NEXT: E3 (unknown command → load+run from DF0: via dos).
  - **E3 — running a typed external command (DONE; CLOSES E).** The shell's "unknown command" branch null-terminates
    the 1st word and calls `sh_exec_cmd`: `OpenLibrary(dos)` → `Open`/`Read` of the name from DF0: (packets → OFS handler →
    trackdisk) → `ls_load_hunks` → reloc → `JSR` to the seglist → `UnLoadSeg`; returns "found" (otherwise the shell emits
    "?"). Same stack as D3d but triggered by the TYPED NAME. Test command `tests/cmd_e3.s` (hunk, written as "e3cmd"
    on the ADF) emits "E3 CMD RAN OK". Proof: inject "e3cmd\r" into the shell → "E3 CMD RAN OK" (complete chain
    type → load from disk via dos → reloc → run). RED `E3_NO_EXEC` (loaded but skips the JSR → marker absent,
    no "?" since found); "bogus\r" → "?" (not found); GREEN-standard/NODISK/COOP (banner + non-reg).
    **"Interactive CLI" target REACHED**: the ROM presents a prompt, reads typed commands, dispatches
    builtins AND loads+runs external commands from the disk. E CLOSED.
  - **DO NOT** build in E: BCPL `CommandLineInterface`/`pr_CLI`, `Execute()`, startup-sequence → Real bootstrap (F).
- **F — Real bootstrap.** Make the boot a REAL bootstrap: the Initial CLI is created BY THE BOOT PATH, gated on a
  bootable disk (not a demo process), and runs a startup-sequence before the prompt. Architectural decision (advisor): the
  F vs "E4" line = **gating on the boot**, not the fact of reading a file. Broken down:
  - **F1 — Initial CLI + startup-sequence (DONE).** The shell (`shell_main`) is no longer created unconditionally in
    `setup_demo_tasks`: it is created in the `.m6r_booted` branch of boot.s (AFTER `strap_boot`, ONLY if a bootable
    disk is present; on a non-bootable disk → M6R insert-disk, NO Initial CLI). The shell first runs
    `sh_run_startup`: `Open`/`Read` "startup-sequence" (disk ROOT; `s/` subdirectory deferred, documented deviation)
    via dos, then `sh_dispatch_line` (extracted from the loop) on each line (builtins + external commands, empty lines
    and ";" ignored), THEN moves on to the interactive prompt. Test script (ADF root): `echo F1BOOTOK` + `e3cmd`. Proof:
    GREEN (bootable ADF, script auto-run without injection) → "M6Y" + "F1BOOTOK" + "E3 CMD RAN OK" + "E2 SHELL
    READY" + non-reg + 0 FAILED; **GATING** (CTRL-NODISK) → "M6R" insert-disk, "E2 SHELL READY" ABSENT (Initial CLI
    gated); RED `F1_NO_STARTUP` (CLI created but script skipped → F1BOOTOK/E3 CMD absent, banner present); COOP.
  - **F2a — CIA-A keyboard reception + decoding (DONE).** Preliminary SPIKE (the injection spike requested by the advisor):
    WITHOUT any injector (xdotool absent, no interactive session), the ROM RECEIVES bytes from the emulated keyboard via
    CIA-A — the emulated keyboard sends its **power-up handshake sequence at reset**. `src/exec/keyboard.s`: `kbd_selftest`
    called VERY EARLY at boot (interrupts masked -> no race with the `cia_wrapper` that cleared the SP flag);
    bounded poll of CIA-A (ICR bit 3 = SP), reads SDR, decodes `keycode = NOT(ROR.b #1, brut)`, **handshake** (CRA
    bit 6 pulse ~75us), collects the power-up stream. Asserts `$FD` (initiate) + `$FE` (terminate) -> "F2 KBD OK". CIA-A
    registers: SDR=$BFEC01, ICR=$BFED01, CRA=$BFEE01 (bit 6 = SPMODE). RED `F2A_NO_HANDSHAKE` (no handshake -> the
    keyboard stalls after 1 byte -> $FE never seen -> marker absent; isolates the handshake). Proves the
    reception+decoding+handshake path WITHOUT an injector.
  - **F2b — LIVE interrupt-driven keyboard driver (DONE).** Preliminary SPIKE (advisor): `xdotool key` (XTEST on the
    FS-UAE window under Xvfb — NOT `--window`/XSendEvent which SDL ignores) does reach the emulated keyboard → REAL keycodes
    recorded (v=$34 e=$12 r=$13 Return=$44 space=$40 a=$20; bit 7 = up). `kbd_install` (after M7B): `OpenResource`
    "ciaa.resource" + `AddICRVector(bit 3 = SP)` → `kbd_interrupt` + re-enables PORTS/INT2 (turned off after the M7B demo);
    `ciaa_server` (still on the PORTS chain) acknowledges the ICR and routes bit 3. `kbd_interrupt` decodes (F2a), handshakes,
    ignores key-ups (bit 7), maps keycode→ASCII (**minimal US keymap**, checked against the measured keycodes) and pushes
    into a **lock-free SPSC ring** (producer). `con_handler` READ drains this ring (`con_ring_get`, consumer) IN ADDITION
    to the serial RBF → the CLI is driven by the REAL keyboard. Proofs: **E2E** (bootable ADF, `xdotool` types "ver\r" on the
    emulated keyboard → echo "ver" + "E2 SHELL ver OK"; harness `tests/boot_test_kbd.sh`); GREEN non-reg + "F2B KBD OK";
    NODISK (install without disk); COOP; RED `F2B_NO_FEED` (handler decodes but does not feed the ring → "E2 SHELL ver
    OK" absent while "F2 KBD OK"/"F2B KBD OK" remain → keyboard→console wiring load-bearing). 0 FAILED.
  - **OFS subdirectories — real `s/startup-sequence` (DONE).** `ofs_read_file` now resolves a PATH of
    '/'-separated components: `ofs_split` splits component by component, `ofs_dir_lookup(dir, comp)` hashes+walks
    the chain of the current directory (intermediate USERDIR -> final file). Detail measured on the ADF: a
    USERDIR block leaves `ht_size` (long[3]) at 0 -> fallback `OFS_HTDEF`=72 (= BSIZE/4-56); sectype USERDIR=2. The shell
    opens "s/startup-sequence" (`s/` subdirectory created by mk_boot_adf via xdftool makedir). Proof: GREEN (F1BOOTOK
    + E3 CMD RAN OK **sourced from the subdirectory**, + D1/D3D/e3cmd = root lookups via the same driver = non-reg, 0 FAILED);
    RED `OFS_NO_SUBDIR` ('/' = normal char -> whole path looked up in the root -> not found -> F1BOOTOK/E3 absent,
    D1 OFS READ OK + E2 SHELL READY intact). Clean-room: public OFS format + test ADF (asset). NO ROM reading.
  - **input.device — InputEvent handler chain (DONE).** `src/exec/input.s`: AUTOINIT resident device
    NT_DEVICE pri 40. `BeginIO` dispatches by io_Command: `IND_ADDHANDLER`/`IND_REMHANDLER` (Enqueue/Remove the
    handler's Interrupt struct in the chain sorted by LN_PRI); `IND_WRITEEVENT` (walks the chain: each
    handler receives a0=InputEvent list, a1=is_Data, a5=is_Code, returns d0=list for the next one). `IND_WRITEEVENT`
    is the PUBLIC injection point (the one Intuition uses) -> the proof in isolation exercises the real MECHANISM,
    not a mock. Proof: OpenDevice (FindName) + 2 handlers pri 10/0 + `IND_WRITEEVENT` of a RAWKEY ($34) -> "INPUT
    OK" (handlers called in pri order + keycode relayed); RED `INPUT_NO_PROPAGATE` (chain not walked ->
    marker absent, device + ADDHANDLER intact). The LIVE keyboard -> input.device -> console wiring is done in #3
    (console.device = natural consumer of IND_ADDHANDLER; avoids touching INT2 again). Clean-room: AutoDocs
    input.device + public NDK includes. NO ROM reading.
  - **console.device — text rendering (WRITE): #3a DONE.** `src/exec/console.s`: AUTOINIT resident device NT_DEVICE
    pri 20. `initfunc` allocates a 1-plane bitplane (chip RAM). `CMD_WRITE` interprets the stream: printable -> BLIT of the
    8x8 glyph (CPU copy of 8 bytes from `font8x8` into the bitplane at (curx,cury)) + column advance; CR -> col 0;
    LF/wrap -> line +8 (clamped, no scroll in this milestone). graphics.library having no `Text()`, rendering is
    done here. **HAND-AUTHORED 8x8 font** (public domain, `tests/mk_font8x8.py` -> `src/graphics/font8x8.s`) —
    NEVER the ROM's topaz (clean-room trap: forbidden to extract it). Proof = **READBACK** (headless, serial):
    a known string is written then each bitplane cell is read back and compared with the expected glyph -> "CONSOLE
    WRITE OK" (validates the blitter address math + the font, without display or Xvfb); RED `CON_NO_BLIT` (blit
    skipped -> readback != font -> marker absent). Clean-room: AutoDocs console.device + public NDK. NO ROM reading.
  - **console.device READ via input.device: #3b DONE.** `console.device` registers (in `initfunc`) a handler on
    input.device via `IND_ADDHANDLER` (`console_input_handler`, Interrupt struct `CONB_INT` in the base): each
    RAWKEY key-down received is cooked keycode->ASCII (reuses F2b's `kbd_keymap`) and pushed into a console **read buffer**
    (`CONB_RBUF` ring); `CMD_READ` serves it back. Proof: `IND_WRITEEVENT` of a RAWKEY 'v' ($34) through the
    PUBLIC path (Intuition's) -> input.device chain -> console handler -> cook -> read buffer -> `CMD_READ` -> "CONSOLE
    READ=v". The input.device chain (#2) thus becomes **load-bearing** with console.device as a REAL consumer.
    RED `CON_NO_READBUF` (handler cooks but does not buffer -> CMD_READ empty -> marker absent). The keyboard->input.device
    FEEDER (kbd_interrupt -> IND_WRITEEVENT from a task) is the later F integration (unify the
    keyboard input of both consoles via input.device); the keyboard already reaches the ROM (F2b) and WRITEEVENT propagates (#2).
  - **ON-SCREEN rendering (#3, visual) — deferred (harness limitation).** `gfx_text_display` (Copper on the text bitplane via
    the M6S graphics pipeline) writes but FS-UAE under Xvfb does not display the Amiga framebuffer in a capturable X
    window (checked: the capture of the known-good M6S kitten is identical) -> pixel verification not viable in headless
    CI. The rendering is proven CORRECT by readback (#3a). Visual = graphics task on a real display, outside CI.
  - **OFS disk-validator (#4) DONE.** `src/dos/diskvalidator.s`: `dv_validate` validates the allocation bitmap of DF0: —
    (1) OFS checksum of the rootblock (sum of the 128 longs == 0), (2) sec_type = ST_ROOT, (3) bm_flag == $FFFFFFFF (bitmap
    marked valid), (4) OFS checksum of the bitmap block (bm_pages[0]), (5) CONSISTENCY: the rootblock (880) marked ALLOCATED
    (bit=0) in the bitmap (idx=878 -> long[28] bit 14, LSB-first). Offsets/convention checked on the test ADF
    (bm_flag@312, bm_pages@316, bits 1=free/0=allocated). Proof: GREEN (ADF) "DISK VALID OK"; RED `DV_CORRUPT`
    (flip of one byte of the bitmap block after reading -> checksum fails -> rejection -> marker absent); NODISK -> no disk
    -> absent. REVALIDATION (bm_flag=0 -> rebuild the bitmap from the tree) is deferred. Clean-room: public OFS
    format + test ADF (asset). NO ROM reading.
  - **complete keymap + keymap.resource + AZERTY ROM (#5) DONE.** `src/exec/keymap.s`: resident `keymap.resource`
    (direct-init pri 100) holds the default keymap (US QWERTY, or FR AZERTY if `KEYMAP_AZERTY=1`) and publishes
    `KM_RESBASE`. `kbd_cook(keycode, qualifiers) -> ASCII` applies **SHIFT** (`_hi` table), **CAPS** (upper case of
    letters), **CTRL** (char & $1F). HAND-AUTHORED US/AZERTY tables (`tests/mk_keymaps.py` -> `src/exec/keymapdata.s`,
    96 lo/hi bytes per layout) — NEVER the ROM. `kbd_cook` is wired LIVE: `kbd_interrupt` tracks the qualifiers
    (shift/caps/ctrl, keycodes $60-$67 in `KBD_QUAL`) then cooks via `kbd_cook`; `console_input_handler` (#3b) cooks
    via `kbd_cook(keycode, ie_Qualifier)`. Proofs: GREEN US "KEYMAP OK" (q/Q/Q via shift/caps, 1/!, ctrl-C=$03);
    GREEN AZERTY "KEYMAP AZERTY OK" (same keycodes -> 'a', '&'/'1', 'é' -> proves that the table drives the cooking);
    **F2b E2E "ver" replayed on BOTH ROMs** (live cooking non-regressed); RED `KM_NO_SHIFT` (SHIFT ignored ->
    marker absent). AZERTY ROM = `make kick` with `KEYMAP_AZERTY=1` (-> `build/kick13-azerty.rom`). Deliberate deviation:
    simplified representation (2 tables + caps/ctrl rules) instead of the complete V34 KeyMap struct (dead keys deferred).
  - **Keyboard feeder -> input.device (F integration, item 1) DONE.** `src/dos/feeder.s`: process (COOP poll on a
    timer.device MICROHZ tick) that drains the keyboard's **RAW ring** (`KBD_FEEDRING`, fed by `kbd_interrupt` via a
    raw tap AT THE SAME POINT as the cooked push -> snapshot `(KBD_QUAL<<8 | keycode)`, a single qualifier authority) and
    injects each keystroke as a RAWKEY InputEvent into input.device (`IND_WRITEEVENT`) -> input.device is the only
    SOURCE of the keyboard; `console.device`'s handler cooks. Non-breaking: the COOKED ring (`KBD_RING`) + serial con_handler
    remain (transitional; after the screen swap they are no longer the shell's path). Proof (self-test ifeq
    SHELL_ON_SCREEN): typing 'v' -> "FEEDER OK=v"; **Shift+v -> "FEEDER OK=V"** (proves the qualifier snapshot +
    the shift cook via the feeder); RED `FEEDER_NO_WRITEEVENT` (no injection -> marker absent); F2b E2E "ver"
    non-regressed. Mechanism: timer poll (no Signal from the CIA ICR). Clean-room: AutoDocs input/timer. NO ROM reading.
  - **Shell screen swap (F integration, item 2) DONE.** Achieved by GATING `con_handler` with `SHELL_ON_SCREEN`
    (no new handler nor repointing: `DOS_CONPORT` stays `con_handler`, which becomes the SCREEN handler). Flag=1:
    WRITE renders the buffer on screen via `console.device CMD_WRITE` (#3a) **+ unconditional serial mirror** (proof
    channel); READ sources `console.device CMD_READ` (keyboard via the feeder -> input.device -> console.device) instead of the
    cooked `KBD_RING`, with screen+serial echo and line discipline (CR/LF). The shell binary is INTACT (IO via
    DOS FileHandles). Proof: (b) GREEN SHELL_ON_SCREEN=1 -> typing "ver" -> "E2 SHELL ver OK" (serial mirror;
    the shell is driven by the keyboard via feeder->input.device->console.device); (c) RED SHELL_ON_SCREEN=1 +
    FEEDER_NO_WRITEEVENT=1 -> input cut at the feeder -> "E2 SHELL ver OK" ABSENT (E3 CMD RAN OK present = boot/shell
    intact) -> DISCRIMINATES that the shell's input does go through the new path; (a) flag off -> serial con_handler
    unchanged (control). Screen ROM = `make kick` with `SHELL_ON_SCREEN=1`. On-screen rendering proven CORRECT by the readback
    #3a (console.device CMD_WRITE); the on-screen pixel remains non-capturable headless (see [[console-keymap-screen-harness]]).
  - **Clickable Intuition "insert disk" requester DONE.** `src/intuition/requester.s`: Requester struct + Gadget
    struct (NDK layout: LeftEdge/TopEdge/Width/Height/GadgetType); `req_hittest(x,y)` = hit-test of the gadget's ABSOLUTE
    box (the core of "clickable"); `req_input_handler` registered on input.device -> on a LEFT BUTTON
    click (IECLASS_RAWMOUSE, ie_Code==IECODE_LBUTTON) hit-tests ie_X/ie_Y and sets `REQ_HIT`; `req_draw` renders the
    requester (top/bottom border + text "INSERT DISK" + label "RETRY" via the 8x8 font) into a bitplane. Proofs:
    **REQUESTER DRAWN OK** (readback: top border + glyph 'I' == font8x8); **REQUESTER CLICK OK** (IND_WRITEEVENT of a
    RAWMOUSE INSIDE the gadget -> hit; OUTSIDE -> miss); RED `REQ_NO_HITTEST` (hit-test cut -> CLICK absent, DRAWN intact).
    Click proof = PUBLIC IND_WRITEEVENT path (like console.device). Hardware mouse + live M6R wiring now
    DONE (gameport.device entry below). Clean-room: NDK intuition.i + inputevent.i + hand-authored font. NO ROM reading.
  - **gameport.device (hardware mouse) + live M6R wiring DONE.** `src/exec/gameport.s` (AUTOINIT resident device
    NT_DEVICE pri 60) + `src/intuition/pointer.s`. Mouse not observable headless (RELATIVE JOY0DAT deltas + no
    injectable movement + invisible framebuffer) -> we FACTOR OUT the pure logic of the hardware shim. `gp_delta8(cur,prev)`:
    signed delta with 8-bit wraparound (`sub.b`+`ext.w`, the quadrature counters wrap). `gp_poll(JOY0DAT,CIAA_PRA)`:
    dx/dy via gp_delta8, edge detection of the left button (CIAA PRA bit 6 active-low), and if movement/edge -> InputEvent
    RAWMOUSE ($68 down / $E8 up / $FF movement) injected into input.device via IND_WRITEEVENT (keyboard feeder pattern;
    no input.task, documented deviation). `gp_vblank_server`: thin hardware shim (reads the real registers -> gp_poll),
    registered by `gp_install` on the VERTB chain of the running system = persistent LIVE wiring (counterpart of the keyboard feeder);
    `GP_PREV_JOY` primed with the current reading (avoids the frame-1 glitch). `pointer_input_handler` (intuition, pri 50 > requester 0):
    accumulates the RELATIVE deltas into an ABSOLUTE position `PTR_X/PTR_Y` clamped to the screen and rewrites ie_X/ie_Y -> the `req_input_handler`
    (pri 0, UNCHANGED) hit-tests in absolute terms = the live wiring. Proofs: **GAMEPORT OK** (gp_delta8 wraparound + button edge +
    event captured via IND_WRITEEVENT); **M6R LIVE OK** (relative RAWMOUSE deltas -> accumulator -> clamped absolute position
    -> gadget hit-test: on the gadget->hit, outside->miss); **GP VBLANK LIVE OK** (gp_vblank_server runs on the REAL VBlanks
    of the running system: GP_POLLS advances). REDs: `GP_NO_WRAP` (word sub without sign-extend -> wrong delta at wrap -> GAMEPORT OK
    absent), `GP_NO_EDGE` (event on every held poll -> edge counter 2->3 -> GAMEPORT OK absent), `PTR_NO_CLAMP` (no clipping
    -> position off screen -> hit-test misses -> M6R LIVE OK absent). Headless JOY0DAT static -> the live server injects nothing
    (prev primed = current) -> inert with respect to M7 (non-reg M7A/M7E/M7F/M7G + E3 CMD RAN OK/F1BOOTOK, 0 FAILED). Clean-room:
    HRM (JOY0DAT/CIAA PRA) + NDK gameport.i/inputevent.i. NO ROM reading. Deferred: RIGHT button (POTINP, fuzzy bit) +
    real click on a displayed screen (unverifiable headless; waiting for a real display).
  - **Coming up**: right mouse button (POTINP) + real click on a display; keymap dead keys/compose; module parity.
- **Loading screen (large file) — GATED DEMO DONE.** `src/graphics/loadscreen.s` (flag `LOADSCREEN_DEMO`,
    linked only under `make VASMDEF=-DLOADSCREEN_DEMO=1 kick` → default ROM byte-identical, zero dead code).
    `loadscreen_demo` sets up a View on the console bitplane (352×272, stride 44) via `MakeVPort`/`MrgCop`/`LoadView`,
    writes "Chargement <name>..." + progress bar (one '#' per 4 KB chunk) during a REAL `ofs_stream_read`,
    then "OK". FS-UAE boot proof: capture `loadscreen_final.png` (readable white text on a midnight-blue background). Standalone
    DEMO (name `bigseg` hard-coded, holds the screen, DOES NOT RETURN) — NOT wired into `dos_loadseg`. **Coming up (live wiring)**:
    rework into a `begin(nom)`/`progress()`/`end()` API called from `dos_loadseg` (must RETURN, free its allocations,
    reuse the current display) to trigger the screen automatically on a real load.
- **Timing-exact trackdisk (WinUAE) — FAST FIX DONE** (4590cb1) + loadscreen DMA-cut (bitplane/copper cut during the read) proven on WinUAE. **Coming up**: complete loading of the Lemmings game on WinUAE (blocks ~sector 46) → align the read on the official one (end of DMA by interrupt, settles 1 ms/15 ms, fixed motor delay 500 ms).
- **Holiday Lemmings — the game STARTS, DONE**: slow RAM `$C00000` at the head of the MemList, shell with a file-size buffer,
    LoadSeg honouring the memory flags (CHIP/FAST, flags in the hunk id), trackdisk track cache (invalidated by
    `/CHNG`). Cracktro → click → game menu proven under FS-UAE; **launching a level confirmed by the user**
    (2026-10-18). **Coming up**: bound the RELOC32 offset (loadseg debt).
- **Workbench 1.3.3 — step 1 DONE**: resolution of `device:`/assign/volume/current directory, boot assigns
    (SYS: C: S: L: DEVS: LIBS: FONTS:), initial CLI with `pr_CLI`/`pr_CIS`/`pr_COS`/`pr_ReturnAddr`, arguments,
    CPU exceptions to `tc_TrapCode` (SetPatch-compatible shape), `RawDoFmt`. `c:SetPatch` runs in full.
    **Step 2 — BCPL runtime DONE**: GV + segarray + runtime segment, ~60 globals, runcommand (dedicated stack,
    argument injection); AddBuffers, CD, Resident, Mount, Failat, Wait run; **createproc + Run**: the background
    CLI (Shell-Seg) runs Execute and the `resident` commands of StartupII. Blocking Delay (timer.device), complete FIB
    (BSTR on the packet side), getvec FileHandles, getlong/putlong indexed in longs.
    **Step 3 — device handlers DONE**: starthandler (112, BCPL and C handlers) + makeglobvec (13), RAM node,
    exec OpenDevice/DoIO/SendIO/WaitIO/CopyMem, timer GET/SETSYSTIME, DeleteFile/Rename/CreateDir; the
    complete WB 1.3.3 startup-sequence runs (StartupII on RAM:, break, MountMF); PIPE: proven.
    **Step 4 — DEVS: devices, AUX:, NEWCON: DONE**: ramlib (LIBS:/DEVS:), AddDevice/AddLibrary, complete
    InitStruct, autovectors 1/4/5, misc.resource, GetPrefs, minimal OpenWindow, asynchronous console.device, global
    50; AUX: (the disk's serial.device) and NEWCON: proven.
    **Step 5 — workbench.task resident DONE**: LoadWB launches a minimal Workbench (process "Workbench", reply
    to the startup message, public port); InitCode filtered by class (RTF_COLDSTART); AddPort initialises the queue.
    **Floppy reading ×5 DONE** (trackdisk: motor kept on 2 s, 3 ms steps + 18 ms settling, LRU cache
    of 8 tracks): complete WB 1.3.3 boot from > 400 s to 87 s. To be validated on timing-exact WinUAE.
    **Step 6 — Workbench screen and visible windows DONE**: graphics (drawing primitives, Text, ScrollRaster,
    generic HIRES MakeVPort), intuition (OpenScreen/OpenWorkBench/GetScreenData, drawn OpenWindow/CloseWindow),
    console.device rendered in the window (ConUnit, CSI, scrolling, cursor), dos Open("*"), aligned packets,
    fl_Volume; NewShell opens an AmigaShell window usable with the keyboard.
    **Step 7 — AmigaSlopDOS at startup and desktop DONE**: AmigaSlopDOS window (console of the initial CLI, closed at
    endcli), apple-green / black-text theme, erasing and repair without layers + minimal REFRESHWINDOW/IDCMP,
    DrawImage (BltBitMapRastPort), AllocRemember, mouse pointer (sprites), backdrop window with the disk icon
    (icon.library), click / double-click -> disk window and its icons, CLOSEWINDOW; floppy inserted on
    the insert-disk screen -> restart and boot.
    **M7+ and L4 DONE**: mathffp.library, disk.resource, potgo.resource, keyboard.device, audio.device, exec
    semaphores, regions and general BltBitMap, layers.library (simple/smart/backdrop, damage), intuition on layers
    (WindowToFront/Back, MoveWindow, Begin/EndRefresh); latent memory overwrite when launching BCPL commands
    fixed (shell stack one long too short).
    **Step 8 (interaction) DONE**: nested drawers, launching tools and projects (WBStartup; Shell -> AmigaShell),
    Workbench menus (Open/Close/Redraw) and intuition menus on the right button, moving and resizing windows
    (SizeWindow, WindowLimits), Execute (101), NIL:, buffered writef.
    **Step 9 DONE**: fonts (topaz TextFont, OpenFont & co), GELs, draggable icons, BCPL ROM CLI (Run, Execute,
    NewCLI without resident), `<`/`>` redirections, Execute scripts, CON/RAW nodes (ROM handler) and SER/PAR/PRT
    (Port-Handler), keyboard routed to the active window, MOUSEMOVE/ReportMouse, drawer closing ×2 faster.
    **Step 10 (in progress)**: floppy writing — trackdisk (CMD_WRITE/UPDATE, MFM) and OFS writing (creation,
    stream, deletion, renaming, protection, comment, Info) proven under the CLI; dates (real DateStamp, C:Date,
    dated headers); AutoRequest; Workbench Discard; BltTemplate (FastFonts); performance: MICROHZ timer
    in one-shot mode (the continuous CIA-B timer ate more than half of the CPU), buffered BCPL console output, faster Text,
    faster ScrollRaster (`type` ×10, SysInfo 1.04 × A600); command failures and FailAt like 1.3 (probed on the real ROM). Text gadgets (STRGADGET, ActivateGadget),
    Workbench Rename, "Please insert volume" requester and redirections before the arguments only, done. Error texts via
    C:Fault done. Directory reading: same speed as the real 1.3 (3 × `list df0:` = 25 s against ~22 s
    on our side: physical re-reads of tracks, like 1.3). System time taken from the boot disk
    (like 1.3). Faithful memory releases: RemTask only frees `tc_MemEntry`, FreeEntry reads A0, Execute no
    longer leaks. The WB boot crashed if the time was set before SetClock; MEMTRACK tracer silent over the whole WB boot.
    Workbench Clean Up and Snapshot done (Clean Up identical to the real 1.3 on SYS:). Screen title (free
    memory), Version and Last Error done; intuition 34.3 window activation rule. Console scrolling with the
    blitter done (type 89 → 70 s). Workbench "Error while ..." error messages done (identical to 1.3). Console: Text by
    strings (70 → 45 s for 400 lines; real 1.3: 38 s). Rest of the gap: scrolling (~11 s) and per-line
    overhead (packet, cursor).
    Workbench Info done (info.library, GIMMEZEROZERO windows, gadgets drawn in reverse order like 1.3; SAVE and
    QUIT proven). Duplicate done (identical to 1.3), DiskCopy works (compliant AutoRequest, handler returnpkt,
    ACTION_INHIBIT, DeviceProc). RAWKEY to the active window and Alt/Amiga qualifiers done.
    Requesters done (Request/EndRequest/InitRequester/SetDMRequest, BuildSysRequest/FreeSysRequest, AutoRequest
    built on top, ScreenToFront/ScreenToBack). Window frame redone like 1.3: done. Proportional gadgets
    (ModifyProp/NewModifyProp) and WB drawer scroll bars done; LoadSeg with an extensible buffer. Remaining:
    InstallClipRegion done, partial icons of WB drawers clipped at the content edge (INTUITICKS done). Preferences is displayed (SetFont preserves D0, SetPrefs,
    devs:system-configuration, PointerTicks); key repeat done (black centring frame = DetailPen 2 theme).
    Caesar loads from the floppy (copinit/COPJMP2 + VBlank, RemakeDisplay, streaming LoadSeg).
    Intros of the ADF suite: Scooby (title), Monkey 1 and SimCity (back to WB) like 1.3 (ExecBase in LibList,
    public IntVects, ExecBase in low chip, no more TRAP in exec, system "CLI" resident).
    SimCity (menu) and Monkey Island (title screen) launched from the CLI: RawKeyConvert, UCopList, LoadRGB4, permanent
    blitter DMA, direct OFS Seek. To do: MICROHZ on CIA-A like 1.3 (Monkey's music on level 6).
    Keyboard under WinUAE fixed (low-RAM variables zeroed at coldstart): Caesar and Monkey with the keyboard under WinUAE.
    SysInfo MEMORY readable after NEXT/PREV (PrintIText/DrawBorder restore pens and mode, probed); ClearEOL/ClearScreen.
    Title bar of a SCREENQUIET screen never drawn any more (SysInfo: no more black bar on click). End-of-step ADF
    suite under WinUAE Linux (tests/adf_suite_winuae.sh) instead of Amiberry.
    Zorro II autoconfig (complete expansion.library, fast RAM added, 1.3 vectors reproduced). UAE disk
    board: romboot.library (DiagArea ROMTag, RomBoot/BootPoint), eb_MountList consumed by dos: boot from DH0:
    (SYS: = DH0) without a bootable floppy or with a priority >= 5, otherwise DH0 mounted.
    MICROHZ on CIA-A timer B (level 2) like 1.3: games that take $78 no longer break delays;
    AddTime/SubTime/CmpTime, compliant Open/Close/AbortIO, strictly increasing time. MICROHZ accuracy under
    load tuned (1.007 s for 1 s, real 1.3: 1.0125 s; cause: feeder on MICROHZ, moved to VBLANK). Key repeat (input.device delay/period, Preferences) and INTUITICKS done: the
    WB drawer arrows scroll as long as they are held; ModifyIDCMP. trackdisk: end of DMA by interrupt (the processor stays available to other tasks while a track is read).
    Full volume: requester "Volume <name> is full" like 1.3. `join`: 25/25 exact joins on a free disk;
    a full disk truncated the file silently (only way found to reproduce the original failure, without
    proof that it is the same cause). Dev ROM hang early in boot (1 time out of 7 with SysInfo) and LoadSeg
    of DiskCopy returning 121 (1 time out of 6): not reproduced on 2026-10-26 (20 dev SysInfo boots: 20 up to SetPatch;
    Duplicate -> DiskCopy: 18 prompts out of 18 valid runs); reproduction loops (repeated boots, DiskCopy
    launches) to be redone if it comes back.
    Accelerated drawing (2026-10-26, reported slow under WinUAE): RectFill/SetRast/ClearEOL/ClearScreen go through
    `dr_rect` (clipping, masks and address computed once per ClipRect and per plane; full bytes by longs,
    SetAfPt pattern by words) and Draw traces horizontals/verticals with `dr_rect`, the others with `dr_line` (same
    Bresenham, address followed from point to point). Byte-identical pixels (probe `tests/drawcheck.s`, 16
    fingerprints); measurements `tests/drawperf.s` (production ROM, FS-UAE): 620 px horizontal line 173 ms -> 0.7 ms,
    180 px vertical 50 -> 5 ms, diagonal 174 -> 42 ms, RectFill 620x180 154 -> 40 ms, the same with a pattern 35 s -> 0.16 s.
    Text: the "string" path of Text (fixed 8-pixel font without style) also covers JAM1, COMPLEMENT and INVERSVID
    (dst = (dst AND K) XOR V): 1,400 JAM1 characters 1.74 -> 0.61 s, COMPLEMENT 5.4 -> 0.62 s (JAM2 unchanged,
    0.5 s; bold and underline remain rendered by spans). BltTemplate (FastFonts, launched by the 1.3 startup-sequence,
    routes all text through it): one fixed operation per ClipRect and per plane (OR, AND-NOT, XOR, set to 1/0,
    replace), template read as a stream: 20 lines of 560 x 8 3.2 -> 0.30 s. Identical pixels (drawcheck T8, T9).
    Disk change (reported by the user: OctaMED inserted, no icon; no RAM DISK icon): analysis spec
    disk-change-v34 (separate agent, address appendix removed at review); DF0: handler (detection by
    1 s tick, volumes by name + date, DISKINSERTED/DISKREMOVED, locks of another volume refused), trackdisk (no
    probe), intuition (broadcast of the IDCMPs), Workbench (one icon per volume, default icon, 96 px placement).
    Proven under FS-UAE with tests/dskchg.s + tests/dskchg_run.sh (change through the F12 menu): WB -> OctaMED -> WB,
    nodes and events conforming to the spec (V2-V5), RAM DISK + Workbench1.3 icons at boot, OctaMED at (264, 2) then
    removed, OctaMEDv4 and RAM DISK windows opened. Requester "Please replace volume / <name> / in any drive"
    (lock or file of an ejected volume; Retry or reinsertion restart the call, Cancel returns 218): proven by the
    dskchg LA probe (V11). Remaining: DF0:NDOS icon.
    Blitter and alerts (specs graphics-blitter-v34, alert-v34): BltMaskBitMapRastPort, ClipBlit, QBlit/QBSBlit,
    common planes in BltBitMap; DisplayAlert and Guru (recoverable Alert, dead-end -> reset then Guru at the next
    boot, task exception -> Software Failure); gblit_probe and alert_probe probes conforming to the real ROM.
    Following analysis specs (separate agents, reviewed): intuition-screens, intuition-input-menus, graphics-area —
    basis of the next implementations (faithful OpenScreen/RethinkDisplay, input engine and menus, Area*/Flood).
    Before a trial on a real A500: track written in the real 1.3 format (gap 1660 bytes, 6815 words, precompensation
    from track 81 on; tdwrite probe identical to the real ROM), graphics table with 109 vectors (SetRGB4CM,
    AttemptLockLayerRom). Analysis specs added: trackdisk-write, coldstart-hardware, coverage (inventory of the 390
    V34 LVOs), then graphics-blitter, graphics-display, alert.
    Area*/Flood/DrawEllipse (graphics-area spec, garea probe conforming except intended deviations T27/T32), RectFill outline and
    multicolour pattern, Amiga key symbol (a cat) in the menus. Analysis specs delivered: layers,
    audio-device, console-keymap. Right-Amiga menu shortcuts (§3.11: MENUPICK, MENUNULL if inactive).
    CHECKIT checkmarks drawn (Window->CheckMark, our own internal checkmark).
    Submenus displayed (sub-item box, tracking, codes with sub-item).
    Remaining in the menus: MENUVERIFY, MutualExclude, multi-selection, HIGHBOX/HIGHIMAGE.
    Clean-room audit (docs/AUDIT.md), code comments and docs/ translated to English (ROM md5 unchanged), and GitHub
    releases: a tag v* makes .github/workflows/release.yml build the production ROM (pinned vasm 2.0f / vlink 0.18a)
    and publish it with its SHA-256.
    Real keymaps (struct KeyMap, keymap.resource V34 layout, console CD_* commands, dead keys) and SetMap support: the
    German Workbench 1.3.3 disk boots with its keyboard (GitHub user report). Remaining: Latin-1 glyphs in the font.
    Memory audit against 1.3 (docs/MEMORY-USAGE.md, MEMTRACK now records the caller): the 45 KB track cache and
    the 4 KB intuition input task are kept on purpose; the 10 KB chip bitmap left by the console boot self-test is
    now freed. Race audit: Flood holds the layer lock, and a CON handler EOF READ no longer falls into
    DISK_INFO. Also fixed: trackdisk serialized by a semaphore; input and gameport reply to non-QUICK requests;
    the intuition event ring, the IntuiMessage pool and the console keymap are made atomic; the DosList is walked
    under Forbid; CloseWindow no longer races the input task (clicks, drags, menus). Remaining suspects: lock
    order in ClipBlit/ScrollRaster, sendpkt reply matching, the boot CLI console handler blocking on READ.
    Ed 1.14 works (issue #6): console window bounds report, CSI @/P line shifts, BCPL output through an
    overridden wrch, and the feeder self-test that stole a key is removed from the production ROM.
    ScrollRaster scrolls horizontally too, ACTION_WAIT_CHAR waits up to its delay, and the last race suspects are
    fixed: ClipBlit lock order, ScrollRaster without waiting for a busy blitter, sendpkt reply matching
    (dos_waitreply), boot CLI console serving WRITEs while a READ waits.
    Workbench icons selected with their alternate image when the icon asks for it (GADGHIMAGE, issue #7).
    Window resizing (issue #10): simple layers come out blank and fully damaged after Move/SizeLayer, real
    SuperBitMap layers (SuperClipRects, ScrollLayer, Sync/CopySBitMap, GZZ interior), RectFill pattern regression
    fixed. Workbench 1.2 boots to its desktop: rdargs("") = one key, startup-sequence run as cli_CurrentInput,
    commands looked up in the CLI path. SizeWindow posts NEWSIZE to the active window, as 1.3 does (2026-11-04).
    Default pointer filled in dark purple (deliberate difference; a different arrow from the original, measured).
    Soft-kick disk (`make adf`, published with each release and on the `rom` branch): loads an image linked at
    $C00000 into slow RAM from a real Kickstart 1.3; coldstart honours ColdCapture and exec computes ChkSum, so a
    reset comes back to the image.
    Chip RAM sized up to 2 MB as on 1.3 (was a fixed 512 KB): Caesar loads with 2 MB chip and no fast RAM.
    SCREENBEHIND honoured by OpenScreen: SimCity's title screen stays hidden while it is drawn.
    gameport.device units 0/1 with every GPD_* command (joysticks on port 2); exec raw serial as in 1.3.
    trackdisk robust to long tracks (ESP32 emulator amiga500-esp32, error 121): decoder up to the very end of the
    buffer, mask of distinct sectors, re-read of an incomplete track (4 times), error rather than stale
    contents; unicorn test tests/td_decode_test.py (99/99, the old code 30 failures out of 33 with an 830-byte gap).
    OctaMED Professional v4 (reported: interface badly loaded, no button responds): analysis spec octamed-v34
    (separate agent; its buttons are zones tested on MOUSEBUTTONS, not gadgets). Causes and fixes:
    the M7B self-test left the CIA-A timer A latch at $00FF, and OctaMED starts this timer without reloading it
    (~2.8 kHz of interrupts instead of ~11 Hz: machine saturated, editor never drawn) -> latch restored to $FFFF;
    the M5B/M7B self-tests also give back their dummy vector (CIA-B bit 1) and their PORTS server; prop_render and
    the knob update restore the RastPort's pens and mode (the file list, redrawn after RefreshGList
    of its scroller, was drawn with the background pen); graphics: SetRGB4 on every ViewPort of the view, WaitTOF,
    BltClear, PolyDraw, VBeamPos, FreeSprite, GetRGB4; intuition: ShowTitle, ViewPortAddress. Proven under FS-UAE
    (tests/dskchg_run.sh): welcome screen, editor, FILES (disk list), PLAY, PLAY SONG (playback, TIMER),
    STOP, keyboard arrows; harness: serial capture (DSKCHG_SERIAL), key command, keyboard joystick turned off.
    DF1: external drive (2026-10-30, user request: Extras 1.3 icon with the Extras disk in DF1): trackdisk units
    1-3 made real (per-unit select line, motor, head position, change counter; device semaphore; shared cache keyed
    by unit), one file-handler process per drive (context in tc_UserData, unit from the FileSysStartupMsg), "DF1"
    DeviceNode mounted when disk.resource identifies a 3.5" drive. Proven under Copperline (Extras 1.3 icon, 1-drive
    boot unchanged, DF1 insertion after boot). Remaining: DF2/DF3 mounting, writes to DF1 not exercised on a
    writable disk yet.
    **Interleaved — SetPatch / SysInfo (user request 2026-10-21, before resuming the Workbench)**: complete V34
    exec (real SetFunction & 33 other LVOs), shell that honours `cli_Module`, Alert relay, DeleteLayer in three
    steps, public V34 GfxBase, CIA TODs started, DF0 FileSysStartupMsg; SysInfo displays its whole page
    (clock, Agnus/Denise, PAL, frequencies); intuition application gadgets (GADGETUP/DOWN, AddGadget,
    RefreshGadgets...): its buttons work (SPEED). Open: PROP/STRING gadgets, Caesar / Scooby-Doo / bootdisk-amiga-m68k floppies of the ADF suite. Each end of step: `tests/adf_suite.sh`
    on the floppies of `assets/test_adf/`.
    **Next**: `SetFunction`, NIL:/redirections, LoadWB (workbench, icon.library, layers).
- **M7+ — long tail**: layers, console, input, audio, gameport, mathffp, workbench.task, parity;
  then **real A500 EPROM** (256K ROM, wiring/adapter).
  **Custom-chip parity (2026-11-02)**: `docs/analysis/custom-chips-v34.md` maps every Agnus/Denise/Paula access of
  the official ROM to its module and LVO; its §7 lists our gaps by impact. Done the same day: AddIntServer /
  RemIntServer drive INTENA, LoadView(NULL) keeps the DMA on (empty list + CPU display reset), DSKEN enabled once
  by disk.resource, PAL/NTSC detected from the beam. Then: POTGO rewritten every frame by the gameport server,
  middle button events, Workbench and default-height screens 200 lines on NTSC (pointer bounded likewise). Open:
  autovector order and acknowledge timing, raw serial, the 272-line boot picture on NTSC.
  **Already-specified LVOs (lot 1, 2026-11-02)**: done — graphics InitView/InitVPort/Get-FreeColorMap/FreeCprList/
  FreeCopList/WaitBOVP/BltPattern/ScrollVPort (+ RasInfo offsets in MakeVPort), intuition SetPointer/ClearPointer/
  Lock-UnlockIBase/CurrentTime/Intuition()/AlohaWorkbench/CloseWorkBench/WBenchToFront-Back/MoveScreen/MakeScreen/
  ActivateWindow/RefreshWindowFrame, layers Fatten/ThinLayerInfo, console CDInputHandler, dos WaitForChar.
  **Lot 2 specs (2026-11-02)**: done — gameport GPD_* (f1f5e23), keyboard/input generic commands and
  IND_SETMPORT/MTYPE/MTRIG, trackdisk RAWREAD/RAWWRITE/GETDRIVETYPE/CHANGEINT/SEEK/REMOVE, cia SetICR and the
  resource layouts, exec Schedule/Reschedule/Switch/Dispatch/ExitIntr/Exception/Debug/Procure/Vacate/SumKickData,
  dos Exit (GetPacket/QueuePacket left null on purpose). Binary and AROS similarity audits at the base level.
  Open: trackdisk unit task (autonomous change polling), input.device task, joystick types through SETMTYPE,
  INDEXSYNC now that SetICR exists, the Workbench menu items (Open, Info, Discard...) stay enabled while no
  icon is selected (our workbench task; 1.3 behaviour to probe), trackdisk allocates its 12.8 KB chip DMA buffer
  at each read (1.3 shows no such per-read allocation: a chip-full game could lose its disk reads), Bubble Bobble
  makes two allocations on 1.3 (9,876 and 177,152 bytes) that it does not make on ours (other code path, cause
  unknown). (The "Empty"/"Diverse" overlap in the Workbench 1.3.3 [m2] disk window is in the disk's data: the
  "Diverse.info" added in 1997 is positioned at 329,15, over "Empty" at 299,0.)
  **Blitter masks, issue #15 (2026-11-02)**: BLTAFWM/BLTALWM = $FFFF at graphics init; the Kefrens Desert Dream
  spaceship is drawn again. Other blitter registers 1.3 leaves behind are not known (oracle probe if a program needs
  one).
  **Workbench Shells, issue #13 (2026-11-02)**: EndCLI closes the window, the first Shell is number 1, a second
  Shell after an EndCLI no longer crashes (stale console read, CreateProc block freed twice), 48 bytes per Shell
  cycle (1.3: 56). Open: per-Shell cost ~52 KB vs 33-40 KB on 1.3 (CP_STKEXTRA 4 KB per BCPL stack; 1.3 refresh
  type of the Workbench backdrop and drawers to probe), idle desktop ~22 KB below 1.3 (docs/MEMORY-USAGE.md).
  **ROM ID block (2026-11-03, vAmigaWeb request)**: `KSS!` at `$18` + version string at `$1C`, so emulators label
  any KickSlopStart image without a hash database; documented as a stable format in the README.
  **Issue #19 (2026-11-03)**: screens are stacked on the display and dragged by their title bar (graphics: ViewPorts
  placed by DyOffset; intuition: 1.3 layout, clicks routed to the screen under the pointer, pointer bounds). Screen
  depth gadgets work (real Gadget structures with their Images, act on release). Interlaced screens are displayed
  (short-frame copper list, View LACE when a LACE screen is visible), dragged and clicked
  (`tests/lace_test.s`). Open: the pointer moves in non-interlaced lines (1.3 MouseY is in interlaced lines);
  MrgCop copies fragments whole instead of interleaving their WAITs by line; the boot desktop has 1,128 bytes less
  free memory (copper fragments are 1,032 bytes).
  **IDCMP (2026-11-03)**: ACTIVEWINDOW/INACTIVEWINDOW, MENUDOWN/MENUUP for RMBTRAP windows, VANILLAKEY; PPShow
  now closes on the right button or a key. MENUVERIFY (MENUHOT/MENUCANCEL, MENUWAITING, MENUUP), SIZEVERIFY,
  REQVERIFY with the DMRequest double click (bar only on the first press), DELTAMOVE, the dead-key history, the
  IECLASS_EVENT after an activation, a growing message pool, the pointer held still during a verification
  (`tests/idcmp_test.s`), one INTUITICKS in circulation over the whole pool, MOUSEMOVE no longer merged and never
  with a zero delta.
  **Sprites (2026-11-03)**: MoveSprite/ChangeSprite/GetSprite as in custom-chips §4.1 (View and ViewPort offsets,
  HIRES/LACE scaling, attached pairs, hidden ViewPort, SpriteReserved, SimpleSprites); hardware VSprites through
  DrawGList and MrgCop, with sprite reuse down the screen and pair-colour aware allocation (`tests/vsprite_test.s`).
  Open: the exact 1.3 VSprite allocation by band is not specified (ours is described in ARCHITECTURE); nextLine and
  lastColor of the GelsInfo are not filled; a VSprite partly above its ViewPort is not clipped; DoCollision ignores
  hardware sprite collisions as 1.3 does (software only).
  **HAM and dual playfield (2026-11-03)**: MakeVPort emits HAM/DUALPF/PFBA, two playfields with their own scroll,
  modulo and offset; ScrollVPort scrolls either playfield (`tests/hamdpf_test.s`). Open from the spec (§4.4): DIW/DDF
  still come from three fixed windows, shifted by vp.DxOffset + View.DxOffset (issue #23) but without the left/right
  clipping steps, so other DWidths are ignored; the number of colours emitted is min(Count, 32) instead of the ncol
  rule.
  **Issue #23 (2026-11-04)**: since v0.2.16 MoveSprite adds View.DxOffset (spec) but MakeVPort ignored it, so a
  Preferences ViewXOffset moved the pointer and not the screen (-4 = clicks 8 hires pixels right of the tip).
  MakeVPort now shifts the display window by vp.DxOffset + View.DxOffset - $81 (§4.4 steps 3-6: DIW, DDF by words,
  BPLCON1 for the rest). Checked with a WB 1.3.3 copy whose system-configuration has ViewXOffset -4.
  **Warm reset (2026-11-03)**: an ExecBase that passes the full §5.1 check of `coldstart-hardware-v34.md` keeps
  KickMemPtr/KickTagPtr/KickCheckSum and CoolCapture/WarmCapture; the KickMem areas are reserved with AllocAbs, the
  KickTags merged into ResModules by name, version and priority, and CoolCapture called before
  InitCode(RTF_COLDSTART) (`tests/kicktag_test.s`), on our ROM and on the soft-kick image. Open: CoolCapture runs in supervisor mode without tasks (user
  mode with multitasking on 1.3); the memory self-test still writes into the first heap blocks before the KickMem
  areas are reserved; the cold path does not clear the RAM; the LED toggle of §5.1 step 5 is not done.
  **OFS write streams (2026-11-04)**: Seek/Read on write handles, MODE_READWRITE in place, failed writes keep the
  position, bitmap reload before allocating, no write on END of an absent volume; dos Info D2, Seek NIL:, 219
  (`tests/fsrw_probe.sh`). **Locks (2026-11-04)**: lock list and 202 conflicts, open files hold a lock, delete bit
  (222), FINDOUTPUT replaces an empty directory, SET_DATE/RENAME_DISK/FLUSH (`tests/fslock_probe.sh`). **FS details
  (2026-11-04)**: names truncated at 30, 212, root 205/212, root fib_DirEntryType 2, ExNext in creation order,
  rename into itself 202, 213/214 before the name, id_DiskState 80, -1/218 on an absent volume
  (`tests/fsgap_probe.sh`). Open from the `rom-filesystem-v34` comparison: stateless ExNext (fib_DiskKey and
  fib_FileName), locks kept in dl_LockList
  of an absent volume, RENAME of a locked source (spec open point);
  **ROM file system on any block device (2026-11-05)**: the OFS handler takes device, unit, flags and geometry from
  its DeviceNode's FileSysStartupMsg (blocks = cylinders x surfaces x blocks per track, partition offset = LowCyl
  cylinders, root = (blocks - 1 + reserved) / 2), goes through DoIO (devices that queue requests), and keeps the whole
  bitmap (bm_pages, then bitmap extension blocks) in memory. A DeviceNode with neither seglist nor handler but a
  FileSysStartupMsg (a UAE hardfile without RDB) gets a "File System" process on first use. Under Amiberry the
  hardfile only mounted once three boot issues were fixed: expansion.library is in LibList before the ConfigChain
  (the UAE DiagPoint opens it: ramlib had initialised a second, empty expansion), InitCode/FindResident follow the
  bit-31 links a DiagPoint inserts into ResModules, and the DF0:/DF1: nodes no longer replace a DeviceNode added
  before them. Proven by `tests/hdfs_probe.sh` (40 MiB, 21 bitmap blocks; 64 MiB with `FILL`, 33 bitmap blocks and an
  extension block) and `tests/wbfs_probe.sh` (Workbench 1.3.3 floppy). Open: only 512-byte blocks; files over
  65535 data blocks (32 MiB) are not followed (16-bit block index); the bitmap block does not move at each flush
  (rom-filesystem §8.3); what 1.3 does with TD_CHANGESTATE / TD_PROTSTATUS / TD_CHANGENUM on a device that rejects
  them (ours: present, writable, count 0) is not specified.
  **Write-back as on 1.3 (2026-11-05)**: root bitmap flag cleared (and disk date set) on the first change, bitmap
  and root (flag valid) written 2-3 s after the last disk access with CMD_UPDATE and motor off, ACTION_FLUSH held
  until then and returned unchanged, INHIBIT writes back first. Copy of C: to a floppy 159.0 s -> 43.7 s
  (`tests/writeback_probe.sh`, production ROM). Open: the bitmap block does not move at each write-back (§8.3); an
  ejection with a pending write-back loses it silently (1.3 shows a requester through dos's errorreq and keeps the
  volume, disk-change §2.2.1 point 2); ACTION_FLUSH holding was not run against a packet probe.
  **File system answers from 1.3 (2026-11-05)** (rom-filesystem §1.4, §2.5, §8.4, §8.6; maintainer decisions):
  rejected device commands, write-back on the third tick and the validator requester frames already behave as on
  1.3. Deliberate differences kept: (1) a bitmap block with a bad checksum under a valid root flag is rebuilt by the
  validator (1.3: "Key n checksum error", "Disk structure corrupt", volume not validated); (2) the reason line for a
  block met twice stays "Key n already used" (1.3: "already set"; its "- bad block type" comes from
  L:Disk-Validator); (3) bitmap extension blocks are followed, so partitions above about 50 MB work (1.3 handles
  at most the 25 root pointers and damages larger partitions).
  **Disk validator rebuilds the bitmap (2026-11-05)**: a volume whose root says "bitmap not valid" is validated at
  mount in the handler (`dv_rebuild`: tree walk from the root, headers, extension blocks, data block tables), written
  back with the flag valid, or kept in memory on a write-protected disk (214 instead of 213); a broken chain shows
  "Error validating disk" / "Key n out of range" then "Disk structure corrupt" and leaves the volume not validated
  (213). Proven by `tests/validate_probe.sh` (rebuilt bitmap identical to xdftool's). Open: 1.3 validates in a
  separate process and its rebuild lives in `L:Disk-Validator` (ours is in ROM and blocks the handler while a
  requester is up); the text of the "key met twice" requester and the Retry behaviour of "Disk structure corrupt" are
  not specified; 1.3's handling of a bad bitmap checksum under a valid flag is not specified (ours rebuilds).
  **dos LVO details (2026-11-04)**: D1 = D0 on packet LVOs, Info(0) to pr_FileSystemTask, ParentDir(0) Result2 0,
  IsInteractive(0), requesters for 214 and 226 with ACTION_CURRENT_VOLUME (`tests/fsgap_probe.sh`,
  `tests/fsnodisk_probe.sh`). 213 and 225 requesters done the same day from the analysis track's observation (`fsnodisk_probe.sh notdos|notval`).
  Open: left Amiga + B closes our requester but did not close 1.3's in the analysis runs; LoadSeg of HUNK_OVERLAY
  files and UnLoadSeg's overlay case are done (2026-11-06, see "Overlay executables" in ARCHITECTURE.md), Retry restarting the whole call (name resolution
  included) instead of resending the packet; the mouse does not move the pointer while a dos requester is open on
  a CLI-only boot (Amiga-B answers it); from `dos-lvo-partial-v34`: D1 = result on packet LVOs, Info(0) to
  pr_FileSystemTask, disk-error requesters (213/214/225/226), UnLoadSeg of overlays, IsInteractive(0).
  **Console CSI (2026-11-04)**: the §3 automaton and sequences, tab stops, modes, full SGR, font-sized cells, DSR and
  raw-event reports (`tests/con_probe.s` on our ROM). Open: italic is not drawn by Text; MULTIBROADCAST raw events
  go to the active unit only; the RastPort copy in the ConUnit is not kept; IECLASS_SIZEWINDOW does not recompute
  the geometry yet.
  **Console commands (2026-11-04)**: CMD_RESET, CMD_CLEAR, CMD_STOP, CMD_START and CMD_FLUSH on open units
  (`tests/concmd_probe.sh`); the last P1 gap of `docs/analysis/coverage-v34.md`. Open: the input ring is 16 bytes
  shared by all units (1.3: 255 bytes per unit), and CMD_READ with io_Length 0 still waits instead of replying -4.
  **Gadget lists (2026-11-04)**: system gadgets in Window.FirstGadget, RemoveGList keeps NextGadget, RefreshGList
  count 0 = to the end (`tests/glist_probe.sh`, identical to 1.3). Then removed system gadgets (no pictogram, no
  click) and requester gadgets (AddGList/RemoveGList/refresh rules, PREDRAWN = image only), `tests/reqg_probe.sh`
  identical to 1.3. Open: AddGadget on a REQGADGET goes to the window list (1.3 uses whatever D2 holds); the
  highlight of a clicked gadget in a PREDRAWN requester is not specified.
  **Text gadgets (2026-11-04)**: ActivateGadget conditions, SELECTED while edited, window activation dropped,
  any-byte insertion, LONGINT filter and conversion, beeps, GADGETUP qualifier, NUMERICPAD on keypad keys
  (`tests/strg_probe.sh`). Open: the 1.3 activation is deferred to the next input event, which is then fed to the
  editor (ours is immediate); the text clear does not write spaces past the NUL as 1.3 does; STRINGCENTER/STRINGRIGHT,
  GADGHBOX/GADGHIMAGE cursors and the ghost pattern of an edited disabled gadget are not done.
  **Issue #22 (2026-11-04)**: endtask and the end of a BCPL process free the process's segarray (getvec block), as
  1.3 does: a NewShell/EndCLI cycle lost 48 bytes (Shell and Newcon-Handler segarrays). The first cycle still keeps
  `L:Newcon-Handler` loaded in the NEWCON DeviceNode (7504 bytes), as on 1.3 (`docs/analysis/newshell-memory-v34.md`).
  Open: the GV of a handler whose dn_GlobalVec is 0 (makeglobvec) is not freed at its end.
  **Intuition rendering (2026-11-04)**: spec `intuition-render-v34`. PrintIText honours ITextFont (OpenFont, SetFont,
  SetSoftStyle) and the font's baseline, DrawBorder sets BackPen and takes Count as a signed byte, both save and
  restore the RastPort state as 1.3 (font fields, pens through SetAPen/SetBPen/SetDrMd, Mask forced $FF, Layer);
  DrawImage ignores Image.Depth; window titles are drawn and measured in the screen font, the drag pattern starts
  at x0 without a title; SetWindowTitles shows a screen title only for the active window (NULL = no text);
  ActivateWindow updates the screen title; OpenWindow sets ScreenTitle to DefaultTitle; SHOWTITLE is kept in
  Screen.Flags. `tests/irender_probe.sh` matches every §7 vector (text ink differs with our own glyphs). Open:
  BorderTop stays 10 (frame spec: WBorTop + font height + 1, which gives 11 on a WBorTop-2 screen with topaz 8,
  while 10 was measured on 1.3 Workbench windows: the Workbench screen's WBorTop is to be measured).
  **Windows (2026-11-04)**: spec `intuition-windows-v34`. WindowLimits checks each value as 1.3 (signed 32-bit
  minima, unsigned 16-bit maxima, a refused value not stored, result 0); SizeWindow posts NEWSIZE to the active
  window, also for (0,0); the successor of a closed active window gets INACTIVEWINDOW then ACTIVEWINDOW;
  CloseWindow and ModifyIDCMP(0) reply another window's messages of a shared port with Code 4; MoveWindow(0,0) does
  nothing. `tests/iwin_probe.sh` matches §8 except deliberate differences: our Move/Size/ToFront/ToBack and the
  close-time activation run at once (1.3 defers them to the next input event), windows are kept on the screen
  (1.3 does not bound them and draws past the BitMap), CloseWindow ends the window's requesters (1.3 leaves them
  orphaned) and gives an empty screen its DefaultTitle. Open: IDCMP ports are not in the public port list; a
  window holds one REFRESHWINDOW at a time (1.3 sends one per repair while LAYERREFRESH is pending, deduced).
  **Regions (2026-11-04)**: spec `graphics-regions-v34`. The ten Region functions keep the 1.3 node order (no merge,
  no sort: Or cuts the new rectangle through a pending list, Xor puts the old nodes outside first, And keeps or cuts
  nodes in place), the 1.3 bounds (union for Or, normalised minimum and shifted maximum otherwise, +15000 when
  emptied), the return values and the AN_RegionMemory alert where 1.3 has it; ClearRect and the region-region
  functions are the 1.3 compositions. `tests/gregion_probe.sh` matches every §11 vector. Open: AndRectRegion's
  MaxX/MaxY follow the real rectangle (1.3: garbage from its own pointers).
  **Text and fonts (2026-11-04)**: spec `graphics-text-v34`. Two ROM fonts, topaz 9 (10x9, derived from our 8x8 glyphs)
  then topaz 8, codes $20-$FF (Latin-1 composed by `tests/mk_font8x8.py`); the Preferences font is the default font
  from intuition's start (topaz 9 without devs:system-configuration). OpenFont scoring, exact name; CloseFont/AddFont/
  RemFont/AskSoftStyle/SetSoftStyle as 1.3 (SetSoftStyle returns the SetPatch value). Text: styles, spacing,
  kerning and other widths drawn through a line buffer and one BltTemplate (bold smear, italic slant, gap
  underline, JAM2 rectangle = advance extent, truncation at the 1.3 buffer width); the 8-pixel fast path stays.
  ClearEOL/ClearScreen by RectFill; RectFill honours INVERSVID. `tests/gtext_probe.sh` matches every §10 vector.
  Open: a removed font replied without a reply port gets NT_REPLYMSG (1.3: NT_FREEMSG, exec ReplyMsg; our boot
  self-tests rely on NT_REPLYMSG); TmpRas is not used as the line buffer; the 1.3 topaz glyphs are not ours.
  **Lines (2026-11-04)**: spec `graphics-line-v34`. Draw walks the 1.3 Bresenham (major axis, ties step the minor
  axis), LinePtrn with the +$1F counter, FRST_DOT and the exact-COMPLEMENT first dot, ONE_DOT, (M+1) mod 1024
  pixels, and the three V34 layer defects (double counter decrease, clipped-piece phase from linpatcnt, no first dot
  in clipped pieces); Move and Set*Pen restart the pattern; PolyDraw calls Draw through its vector.
  `tests/gline_probe.sh` matches §10 except by design: no write outside the BitMap without a layer (clipped);
  asynchronous completion for eligible common solid Draw calls (CPU consumers wait before access). Open: GfxBase BlitLock (+$AA) not
  kept, a y-major clipped piece in a hidden buffer uses y - MinY (spec §7.4 deduces + (MinY & 15), not observed).
  **Drawing acceleration (2026-11-05)**: contained solid non-horizontal lines use OCS line DMA; large solid
  rectangles and source-independent BltBitMap clear/set/invert operations use masked area blits. Horizontal
  lines keep the inexpensive CPU row-fill path (large spans may use rectangle DMA). Eligibility checks preserve
  plane masks, layer clipping, SMART backups, patterns, ONE_DOT and ownership fallbacks. Common solid Draw
  completes asynchronously; CPU consumers and owned-raster release paths wait before using or freeing memory.
  Short strokes use a bounded scheduling guard; polygon masks and shifted templates use DMA with checked CPU
  fallbacks. Mode/pen-pair and AreaEnd-versus-RectFill checks retain upstream raster semantics. Normal and quick
  graphics groups check pixels, guards, state, ownership and memory lifetime; five speed gates plus a horizontal
  non-regression gate cover performance. Exec groups check true-fast-memory allocation preference.
  Workbench window closing and Clock rendering improved; **original Clock speed parity remains open**.
  Reproduction, dated measurements and geometry limitations: `tests/README.md`. Remaining: patterned/clipped-piece
  line acceleration, patterned fills, and broader asynchronous blit API behavior.
  **Screen fonts (2026-11-04)**: NewScreen.Font opened and set, Screen.Font, BarHeight from the font, IntuiTextLength
  in the text's font, Preferences read before the Workbench screen opens (`tests/scrfont_probe.s`). Open: window
  title bars stay 10 lines whatever the font (measured on 1.3 with topaz 8); menu texts still assume 8-pixel
  characters.
  **System clock (2026-11-04)**: CIA-A TOD at the measured mains rate, uniqueness counter, fold-over,
  PowerSupplyFrequency, UNIT_VBLANK and the input/intuition clocks at the real VBlank rate (`tests/systime_probe.s`).
  Open: the exec quantum is still counted by our scheduler server, not by timer.device's VBlank server (§3).
  **GELs (2026-11-04)**: spec `graphics-gels-v34`. List keyed by the long at VSprite.Y (negative X after positive X),
  inserted before equal keys; InitGels sentinels at -32767 with head.ClearPath = tail; InitMasks BorderLine from the
  first image plane (a VSprite's from its first Height x Width words); DrawGList under Forbid with Before/After
  (BWAITING), DrawPath/ClearPath chains and recursive restore of the Bobs drawn later, BOBUPDATE then BACKSAVED,
  SAVEBOB never restored, GELGONE, double buffering (DBufPacket swap, SAVEPRESERVE, OUTSTEP removal), PlanePick/
  PlaneOnOff through ImageShadow and image planes counted over the written planes; VSprites: sprRsrvd is the usable
  set, nextLine/lastColor kept, pair rules of §5.8, sticky VSOVERFLOW; DoCollision with any HitMask bit, first.MeMask
  & second.HitMask without bit 0, boundary tests on CollMask/BorderLine pixels (TOPHIT two rows past the bound);
  Animate moves with the old velocity, (An + Trans + 32) >> 6, sequence switch carries links, flags, position and
  paths; GetGBuffers chip buffers with ImageShadow = CollMask. `tests/gels_probe.sh` matches §11 (G8 also checked
  against the real ROM's output: a double-buffered removal must keep alternating the BitMaps) except the V34
  defects we do not reproduce: a non-OVERLAY PlaneOnOff shape at an X not multiple of 16, the save slot shifted by
  an rp->Mask hole, collision pairs with the second GEL on the left, a one-member sequence added twice. Our
  VSprites still go through our SprIns stream (1.3 builds SprIns/ClrIns CopLists). Buffers are cleared on
  allocation (1.3 leaves them as allocated).
  **CDE theme (2026-11-04, issue #24)**: the apple-green theme is replaced by the CDE colours proposed in the issue:
  Workbench colour 0 Sun/Solaris CDE purple $A9C (`SC_BGCOLOR`), 1 cream $FFE, 2 black $000 (text, DetailPen),
  3 slate blue $78A; ROM pointer fill mauve $A57 with cream highlight (`pf_defaults`, `sc_palette`). The user then
  swapped the issue's grey-blue $AAB background for the purple and its dark grey $566 text for black. A deliberate
  difference from 1.3, like the green before it.
  **Screen drag (2026-11-04, issues #22/#25)**: dragging a screen in the upper half showed doubled title bars and
  icons (vAmigaWeb's DMA view: copper activity in the upper third). Two causes: MrgCop rewrote the running list in
  place, and LoadView strobed COPJMP1 mid-frame so the new list's past WAITs fired at once. Now RethinkDisplay builds
  new lists, LoadView, WaitTOF, FreeCprList of the old ones (intuition-screens §5.2), and LoadView leaves a running
  copper alone (graphics-display §7.1; the "COPJMP1 strobe kept" note of custom-chips-v34 "Done 2" is superseded).
  Drag test (90 shots per half, title bands counted): 12 garbled before, 0 after; free memory unchanged after the
  drags. The other #22 report (memory not returned after the first NewShell) is the one-time load of
  `L:Newcon-Handler` (7,504 bytes, kept in the DeviceNode as on 1.3), not a leak: later cycles return everything.
  **Workbench window memory (2026-11-04, issue #22)**: opening the boot disk's drawer cost 21,384 bytes against
  ~11 KB on 1.3. MEMTRACK showed a 10,192-byte ClipRect backing store: the backdrop window was SMART_REFRESH, so
  layers saved the desktop area hidden by the drawer. The backdrop and the drawer windows are now SIMPLE_REFRESH as
  in workbench-task-v34 §3.2 (they already redraw on REFRESHWINDOW): the open costs 11,192 bytes (icons 9,888 from
  the disk's icon.library, window/layer/port 1,168, arrows 136 kept once), a drawer over a drawer saves no backup,
  and closing both returns everything but the 136 bytes. Still different from 1.3: one IDCMP port per drawer
  (1.3 shares one through ModifyIDCMP) and the 5-message pool reserved in each Window block.
  **Drawer layout as on 1.3 (2026-11-04)**: a probe of the real 1.3 (workbench-task-v34 §8.5) read BorderTop 11 for
  a titled window (WBorTop 2 + screen font 8 + 1, as intuition-gzz §1 says), with the bar on lines 0-9 and line 10
  blank. We used 10, so every drawer's contents sat one line high and the top line of MountMF (CurrentY 74) showed
  above the scroll bar. `WD_TBARH` is now 11 (the bar drawing already follows BorderTop - 2). Icon names sit right
  under the image (no extra line) and are drawn JAM2 on pen 0, so Empty's name covers Diverse as on 1.3.
  **vAmiga fast RAM after the insert-disk reboot (2026-11-04)**: vAmiga's RESET instruction does not put Zorro boards
  back into autoconfig mode, so the reboot of `disk_watch` lost the fast RAM. Reset memo at $480 written before that
  RESET and replayed by the expansion init when the chain finds no board (ARCHITECTURE 7ac). Possible follow-ups:
  boot the inserted floppy without a reset as 1.3 does; report the RESET behaviour to vAmiga.
  **ramlib (2026-11-04)**: spec `ramlib-v34`. OpenLibrary/OpenDevice try the base name of a path, then a ROM
  resident, then LoadSeg in the calling process (a plain task fails; 1.3 has no ramlib process either); the RomTag
  is searched in the first hunk only, a module without one runs its first hunk; loads of one base name are
  serialised (waiters on SIGF_SINGLE, a failed load retried by each waiter); Close/Expunge seglists are freed and
  returned; a failed AllocMem expunges every unused library and device once, then retries; IoErr 103 on failure.
  `tests/ramlib_probe.sh` matches §8 (T1-T10, CONC). Differences: LoadSeg gets "LIBS:"/"DEVS:" + name (1.3:
  CurrentDir(LIBS:) + the name as given), our ROM libraries never expunge (except mathffp since rank 15, as on
  1.3), a seglist is only freed for a module whose vector points into RAM, no ramlib.library node or exec SetFunction patches.
  **WaitTOF (2026-11-04)**: signal-based on TOF_WaitQ, VBlank server per spec (gb_VBlank, CIA-B TOD = line),
  input.device task woken by keystrokes and deadlines instead of every frame (`tests/waittof_probe.s`). Open: the
  VERTB chain costs ~19 lines (1.3 returns from WaitTOF at line $0C); QBSBlit is still QBlit.
  **trackdisk errors (2026-11-04)**: read codes 21-26 instead of 20, 10 retries with recalibrations, -4 beyond
  the disk, 29 without a floppy, 31 without memory, ETD_* commands with the change-count check
  (`tests/tdcode_probe.s`, `tests/td_decode_test.py`). Open: ETD sector labels, codes 22 and 27 (preamble and
  first-header cases of the 1.3 decoder are not specified precisely enough), TD_FORMAT without a floppy.
  **Issue #20 (2026-11-03)**: 68010 and 68020 CPUs (exception frame format word, MOVE from SR in user mode,
  AttnFlags). An emulated A1200 (68020, AGA, 2 MB chip, 24- or 32-bit addressing) boots the Workbench 1.3.3 and runs
  SysInfo (68EC020, AGA Alice 2 MB). Open: 68030/68040 (MMU, other frame formats), FPU (AFF_68881 not set), a real
  A1200's 512 KB ROM at $F80000 (the 256 KB image relies on the emulator's mapping).
  **Issue #21 (2026-11-03)**: intuition BOOL functions return 1 for TRUE; a double-click in a Directory Opus 4
  lister opens the directory. layers.library and the graphics region functions return 1 too (2026-11-04, probed
  on 1.3: layers-v34 §1.1, `tests/booltrue_probe.s`); AndRectRegion leaves d0 = 0 as 1.3 does. Open: other
  graphics functions not probed.
  **Issue #18 (2026-11-03)**: Window/Screen MouseX/MouseY follow the pointer; Directory Opus selects entries. Open:
  on 1.3, are all windows of the screen updated or only the active one; GZZMouse of a non-GZZ window (we copy
  MouseX/Y); MOUSEBUTTONS messages carry qualifier 0 (shift-click); it_scrxy ignores the screen's TopEdge.
  **Cluedo, 2026-11-03**: reaches its player selection (implicit hunk end, wd_IFont, Seek result in D1, trackdisk
  recalibration after a wrong track). To confirm on 1.3 through the analysis track: dos LVOs returning their result in
  D1 too, and how 1.3 trackdisk recovers when a program moved the head behind its back.
  **WinUAE suite, 2026-11-03**: Shanghai (hunk count bound, doubled HUNK_END, LED bit of CIA-A PRA) and the
  Lemmings demo (boot assigns with lock 0 for missing directories, TAB in command lines) start as on 1.3.
  Not checked on 1.3: whether S and SYS also get a lock-0 assign when missing (we create S).
  **pr_StackSize, issue #16 (2026-11-03)**: set at process creation (dos-v34-spec §4a, measured on 1.3); Directory
  Opus 4.12 starts from its boot disk (it stopped on "Stack must be at least 16384 bytes!"). Differences left: our
  Initial CLI reports 8192 (1.3: 1600, its commands run on a separate stack in both), and the stack block is a
  separate allocation instead of following the Process.
  **Custom bootblocks (2026-11-02)**: the strap jumps to the entry the bootblock returns in A0 and runs the
  boot code with the interrupts enabled. Tintin on the Moon reaches its game (it started AmigaDOS), Spaceballs
  "State of the Art" starts (white screen before); Zool, Kefrens Desert Dream, Workbench 1.3.3 and Lemmings
  unchanged. `assets/boot_c.adf` must be regenerated with `tests/mk_boot_adf.sh` (its bootblock now returns the
  dos init).
  **Zool (2026-11-02)**: stuck on "PLEASE PRESS FIRE TO START" (issue seen on a real A500, reproduced under
  Amiberry); the game had crashed after copying its code to the wrong place, because ExecBase (in low chip) was
  overwritten by its load and MaxExtMem was never set. Fixed: ExecBase at the bottom of the slow RAM as on 1.3,
  MaxExtMem set. Zool reaches its front-end and hiscores with port-2 fire, on the ROM and through the soft-kick
  disk; on 1.3, port-1 fire, left click and Space do not start it either (oracle probe).
  **First run on real hardware (2026-11-02)**: the soft-kick disk boots KickSlopStart on a real A500 (512 KB chip +
  512 KB slow RAM, the minimum for the `.adf`, now stated in the README). Workbench 1.2 then reached its screen, but
  the title bar kept switching to the menu strip (right button read as pressed and released) and the pointer froze
  while the mouse moved; no desktop icon was shown yet. Not reproduced under Amiberry (WB 1.2, 512+512 KB, 40 fast
  right-button toggles while moving: no freeze). Suspected cause: a badly seated mouse (pin 7 +5 V, pin 9 right
  button). To retest after reseating it; if it persists, try the same mouse on the real Kickstart 1.3, then have an
  analysis agent probe what 1.3 writes to POTGO.
  **POTGO probe (2026-11-04, gameport-v34 §10)**: 1.3 writes only $0000 then $0F00, once per frame from the gameport
  VBlank server after one POTGOR read, never START, never an OUT bit back to 0; Intuition never touches it, menus
  included. Ours matched in steady state ($0F00 every frame). The only difference was the boot proof of
  potgo.resource, which wrote $0C01 (START) then $0000 to the hardware: it is now dev-only (`ifeq PROD`), so the
  production ROM's first POTGO write is gameport's $0F00, as on 1.3. Nothing found that would make the right button
  float on a real A500; the reseated-mouse retest and the same mouse on the real 1.3 remain the next steps.
  **Raster functions (2026-11-05, coverage §7 rank 10)**: spec `graphics-raster-v34`. SetAPen/SetBPen/SetDrMd store
  the low byte (DrawMode unmasked) and, every time, recompute the eight minterms (InitRastPort: `$CA`), set FRST_DOT
  and +$1F = 15 (this closes the "rp minterms[] not computed" point of the Lines entry). RectFill takes each plane's
  operation from the §2.2 minterm of its pen bits and the mode: INVERSVID inverts the pattern, COMPLEMENT|JAM2 and
  mode 7 invert everything, solid JAM1|INVERSVID and COMPLEMENT|INVERSVID draw nothing, JAM2|INVERSVID paints BgPen;
  pattern phase in RastPort (layer) coordinates, multicolour patterns per plane, Mask and depth; AREAOUTLINE restores
  FgPen, DrawMode and the minterms directly, so cp = (xmin, ymin), FRST_DOT clear and +$1F are those the Draws leave.
  Without a layer RectFill addresses pixels linearly as 1.3 does (x past the right edge continues on the next row).
  SetRast ignores mode and pattern. ScrollRaster: max corner clamped (BitMap or layer), the no-layer "shift not
  smaller than the rectangle -> nothing" rule, BgPen solid strips that may spill out of the rectangle in a layer,
  destinations whose source is outside the layer kept, and one combined dx/dy move (ClipBlit slices of |dy| rows or
  |dx| columns, so the ClipRect order cannot read an overwritten source; the old two-pass move lost pixels through a
  hidden SIMPLE part). `tests/graster_probe.sh` (+ `tests/graster_check.py`, which models the expected results):
  156/156 vectors pass on kick-prod and the dev ROM (131 failed before, mostly the minterms, the outline fields, the
  INVERSVID/COMPLEMENT|JAM2 modes, the linear wrap and ScrollRaster's rules). Its output now goes to a memory buffer
  read through gdb: the emulated serial link dropped about one character per KB under load. gline, garea, gregion
  and irender probes unchanged (only the gline minterm fields differ, now the spec values). drawperf on kick-prod,
  before -> after (video lines): screen H 1620 -> 1639, V 7944 -> 8021, R 6042 -> 6060, P 2398 -> 2379, text X1-X4
  and BltTemplate within 60 lines of 33,000 / 4,500; window H 2130 -> 2202, R 4373 -> 4395, others equal: at most 3 %,
  within the run-to-run noise. drawcheck: identical except screen T4 plane 1, which draws a pattern rectangle at
  x = -20 without a layer: the new linear wrap puts its left columns at the end of the previous rows, as on 1.3.
  Deliberate differences from 1.3 (V34 defects not reproduced): reversed RectFill bounds draw nothing (1.3: huge
  blits); without a layer RectFill wraps only inside each plane (1.3 writes past the plane and the BitMap); no 64-word
  or 1024-row truncation in the three functions; ScrollRaster without a layer clamps a negative min corner to 0 after
  the no-op test (1.3 writes before the BitMap, Guru); SIMPLE-layer damage is exact and the existing DamageList moves
  by (-dx, -dy) with the content (1.3: one pixel too large on the right and bottom, existing damage moved by
  (+dx, +dy)); the three setters and ScrollRaster preserve every register, SetRast and RectFill change only
  d0/d1/a0 (probe R0; 1.3 changes d0/d1, plus a0/a1 for the three drawing ones);
  CPU rendering is synchronous (BBUSY clear on return, BlitLock untouched). Assumptions and open points: RectFill,
  SetRast and the ScrollRaster fill compute the minterm from FgPen/BgPen/DrawMode at the call instead of reading
  rp_minterms (the same whenever the setters are used; our intuition writes pens directly); wrapped row pieces keep
  the pattern row of their rectangle row (not observed); the COMPLEMENT interior shrink of the outline applies to any
  mode with the COMPLEMENT bit (spec open point 5); a layer with Scroll_X/Y or a SuperBitMap uses the RastPort area
  for the clamp and the phase (open point 1); ClipBlit still walks the source ClipRects in list order for other
  overlapping copies.
  **Console resize (2026-11-05, issue #26)**: a console window made narrower kept its old line length, so `info`
  in a shrunk CLI wrote over the right border and was cut off instead of wrapping. Each window unit now remembers the
  window size of its last geometry (cu_geom); a CMD_WRITE that finds another size first runs `cu_resize`
  (console-keymap §3.9): new XMax/YMax/extents; in a SMART_REFRESH window that grew, the band right of the old whole
  columns and the band below the old whole lines are cleared; the cursor is erased only if its cell is still in the
  text area; then (not SUPER_BITMAP) XCP > XMax -> column 0 of the next line, YCP > YMax -> last line, column 0 and a
  one-line scroll. `tests/con_probe.sh` (CON_ROM = our production ROM), §8.5 vectors: after SizeWindow(-200, -64)
  the empty write gives XMax 40, YMax 12, XRExtant 413 and the report `CSI 1;1;13;41 r` as on 1.3 (before: 60, 19,
  `CSI 1;1;20;61 r`); after (+200, +64), XMax 60, YMax 19; the rest of the probe output is unchanged. Workbench
  1.3.3 NewCLI window shrunk with the mouse, then `info`: lines wrap as on the issue's 1.3 screenshot; grown again,
  `info` uses the whole width. Deliberate difference: 1.3 learns the resize from IECLASS_SIZEWINDOW for the active
  unit only; here every unit checks its own window at its next write (the inactive case was never probed on 1.3,
  §9 open point 2), and the size seen is the one at the write, not the smallest one in between. Seen while testing,
  not from this change: after a window grows, intuition leaves one pixel of the old right border on line
  BorderTop - 1.
  **Shell double prompt (2026-11-05)**: after a command loaded from the floppy, the Shell printed an empty line
  before the output and a second prompt after it ("2> 2>"). Cause: the keyboard feeder (`src/dos/feeder.s`, pri 4)
  ran its due key repeat before draining the keyboard ring; while it was starved during the disk load, Return's
  release already waited in the ring but the 0.8 s repeat fired first, so the CLI read a second empty line. The ring
  is now drained first, so a released key never repeats. Checked on a Workbench 1.3.3 NewCLI window: `echo`, `info`,
  `echo` each give one prompt (before: two of three commands doubled, in two runs); prepush FAIL=0. Open: the feeder
  stays at pri 4 where 1.3's input.device task runs at 20 (intuiticks-repeat §1), so keyboard events are still late
  during disk loads (since the same day the feeder runs at priority 20: "One input task" below).
  The other report from the same review, a Workbench "without title or icons" after a NewShell in
  the startup-sequence, is not a bug: the 640x100 Shell window at 0/0 covers the screen title and the icon column.
  **Screen bar in Monkey Island (2026-11-05)**: a blue screen title bar with its depth gadgets flickered over the
  game. The game opens a custom screen with SHOWTITLE set and covers it with a BACKDROP BORDERLESS window, then
  draws straight into the screen BitMap over the bar. Each left click went through `wn_scrtitle`, which always
  redrew the bar. It is now redrawn on activation only when Window.ScreenTitle differs from Screen.Title
  (intuition-screens §3.3). SetWindowTitles keeps its own redraw, so the Workbench memory title still updates.
  Checked on Monkey Island (no bar over 40 bursts of in-game clicks) and Workbench 1.3.3; prepush FAIL=0.
  **RawDoFmt (2026-11-05, coverage §7 rank 11)**: spec `exec-rawdofmt-v34`. `rawdofmt.s` rewritten to the 1.3
  grammar: `%[-][0][width][.limit][l]type` in that order only; d/x/s/c are the only conversions (x upper case, %d
  sign-extends a word, %x does not); %u, %X, %b and every other type character are echoed with no padding and no
  data read (%b leaves its BPTR in the stream); the limit truncates every type, sign included; width, limit and the
  pad count are 16-bit, a pad count that is negative as a 16-bit value pads nothing; zeros pad on the padding side
  only (`%05d` of -42 -> `00-42`, `%-05d` of 42 -> `42000`); `%c` of a zero byte is an empty field; packed data
  without alignment; the final NUL is sent; PutChProc is called through A2 with A3 carried from call to call, A3 is
  restored and A1 = just past the last item read on exit, D2-D7/A2/A4-A6 preserved. The dev self-test now expects
  `000-7` for `%05ld` of -7 (it expected the C-style `-0007`). `tests/rawdofmt_probe.sh` (+ `tests/rawdofmt_check.py`,
  case table and model; output through a gdb-read memory buffer, as graster): 205 vectors, 155 failed before (41 on
  the output bytes: no limit on numbers, C-style zero padding, %u/%b known, 32-bit widths that padded 65534 spaces
  for `%65535d`; the rest A1 on exit, D0 and stack depth), 0 after on kick-prod. Workbench 1.3.3 on kick-prod: the
  memory title ("Workbench release. ... 836152 free memory", touched up by LoadWB) and `avail`/`info` in a Shell are
  pixel-identical to the previous ROM. Deliberate differences from 1.3: a format that ends inside a conversion
  (`"abc%"`, `"abc%5"`) ends the call at its terminator (1.3 sends that NUL as a character and keeps formatting the
  bytes after the string, §2.6), probe vectors Z1-Z7/T1-T8; D0 on exit = next data pointer, as V36+ documents (1.3:
  garbage, so no 1.3 caller can depend on it); PutChProc gets D0 with the upper 24 bits clear and the caller's A6,
  usually ExecBase (1.3: garbage upper bits and a pointer into its frame: a PutChProc using A6 as SysBase works here,
  and A6 is still restored on exit if PutChProc changes it); A1 on exit is the data cursor even when PutChProc
  changed A1 (1.3: that A1); stack 64 bytes below the caller's SP at PutChProc, 68 while padding (1.3: 68/72). Kept
  from 1.3 on purpose: a NULL `%s` prints the bytes at address 0 (empty on a running system), and RawDoFmt relies on
  PutChProc preserving D2, D3, D5, D6, A2, A4, A5 (it tolerates D0, D1, D4, D7, A0, A1, A6). One safe addition with
  identical output: `%.<n>s` stops counting the string at n characters, so an unterminated buffer is not read past
  the limit. Open points: limits 32768-65535 act as large limits here (indistinguishable on 1.3 for strings shorter
  than 32 KB); an odd DataStream still raises an address error, as expected on 1.3. Seen while testing, not from this
  change: a `NewShell` added after `LoadWB` in the Workbench 1.3.3 startup-sequence leaves the desktop without its
  title bar and icons (same on the previous ROM).
  **Track cache under memory pressure (2026-11-05)**: AllocMem's failure path calls `td_lowmem` (trackdisk.s)
  before `ram_expungeall` and its retry: the 8-slot cache (45,056 bytes) is freed when the device semaphore is free
  and no slot is dirty, and is allocated again at the next access. `tests/lowmem_probe.s`: 45,192 bytes of fast
  memory come back after a failing AllocMem (136 before). Not in 1.3, which has no cache (memory-budget-v34).
  **Track cache 8 -> 4 slots (2026-11-06)**: `TD_NCACHE` = 4 (`exec.i`), 22,528 bytes of slow RAM back at idle.
  Workbench 1.3.3, A/2, production ROM: 871,312 free (848,784 with 8 slots), 10,264 more than 1.3; boot to the end
  of the startup-sequence 63.1-63.9 s instead of 54.2-54.4 s (two runs each). `docs/MEMORY-USAGE.md` section 6.1.
  **Ask in the startup-sequence (2026-11-05)**: `ask` as the first line of a startup-sequence never returned: the
  boot console handler (`conhandler.s`) ended a READ line with CR, and c:Ask (BCPL) reads up to LF, so it asked the
  handler for more and waited for ever. Shown live: after "y" + Return the handler state held a second READ of 200
  bytes; Ctrl-J put one LF into it but the READ still waited for a CR; one more Return delivered "LF CR" and Ask
  printed its prompt again. Return is now delivered as LF (echo unchanged), a typed LF is ignored as on CON:, and the
  initial shell's builtin match accepts LF. Copy of the Workbench 1.3.3 disk with `ask` first, again after SetPatch
  and `if warn`: "ASK1 YES" / "ASK2 NO", dev and production ROMs; `ask` at the initial prompt and in a Workbench
  Shell also return.
  **Boot console line editing (2026-11-06)**: the boot console handler (`conhandler.s`, initial AmigaSlopDOS CLI and
  startup-sequence) stored Backspace as a character ("abcdef", 6 Backspaces, `ask` ran "abcdefask"). Its READ now
  edits the pending line like the CON: handler (`conwin.s`): Backspace/Ctrl-H rubs out the last byte (echo BS,
  space, BS), never past the start of the READ; Ctrl-X rubs out the whole pending line (also added to `conwin.s`;
  AmigaDOS manual line editing); Ctrl-\ ends the READ with 0 bytes; CSI sequences (cursor, function, Help keys)
  are skipped up to their final byte; other control bytes are ignored; Return still delivers LF with a CR LF echo.
  A READ now returns as soon as its buffer is full (the next key used to be echoed, then dropped). Copy of the
  Workbench 1.3.3 disk with `ask "Q?"` first: "abc" + 3 Backspaces + "y" + Return -> echo "y", `if warn` true, dev
  and production ROMs; at the initial prompt "dirx" + Backspace + Return runs `dir`; "garbage" + Ctrl-X then
  `echo "X1=KILLED"` prints X1=KILLED; cursor left/up and F1 inside a word are skipped; Backspace on an empty line
  does nothing; Ctrl-X in a NewCLI CON: window erases the line on screen. prepush-check FAIL=0 (first run lost one
  serial byte of "AUDIO ALLOC OK" under load, rerun clean), concmd_probe as expected. Open point: the initial
  shell (`shell.s`) does not treat a 0-byte READ as end of file, so Ctrl-\ at its prompt parses the stale buffer
  ("Unknown command") instead of ending the CLI as 1.3 does.
  **Initial CLI leftovers (2026-11-05)**: at EndCLI the initial CLI sent END on its console key and kept the
  FileHandle (312) and its 512-byte write buffer. It now closes the FileHandle through dos Close; a breakpoint on
  dos Close for that FileHandle hits once, from the shell process at its end (Run's background CLI never closes
  it). A typed `endcli` now ends the initial CLI as well (it printed a new prompt and stayed). The 808-byte BCPL
  global vector is not freed: the idle Workbench process has the same pr_GlobVec (CreateProc copies the
  creator's), so it is the shared GV of everything started from the initial CLI. Saving: 824 bytes.
  **Console handler stack (2026-11-05)**: 4,096 -> 2,048 bytes (`CON_STK`, boot.s). Deepest use measured with a
  pattern-filled stack (filled through gdb at the shell's entry, read back at the end) on the production ROM: 982
  bytes over a Workbench 1.3.3 startup with FastFonts, `dir sys: all`, `list`, `type`, `info`, `avail`, `ask`, a
  wrapped 110-character line, the AmigaSlopDOS window shrunk and grown with the mouse, and a typed `endcli`. Letting
  the process exit at idle was not chosen: processes keep its port in pr_ConsoleTask (copied by CreateProc) and
  dos keeps it in DOS_CONPORT, so a restarted handler would leave them with a dangling port. Saving: 2,048 bytes.
  Workbench 1.3.3 idle (production ROM, A500 preset, empty DF1, 150 s): 839,024 bytes free (836,152 before).
  Open: the initial console READ has no line editing (Backspace is stored as a character), unlike CON:.
  **MakeLibrary sizes (2026-11-05)**: MakeLibrary set LIB_NEGSIZE/LIB_POSSIZE, then called InitStruct with the
  data size, which clears that size first and wiped both fields: every AUTOINIT library and device built at boot
  had NegSize = PosSize = 0 (seen with a gdb walk of LibList/DeviceList on the Workbench), so SumLibrary summed
  nothing and an Expunge freed the wrong size. The block is already MEMF_CLEAR, so InitStruct now gets size 0;
  the walk shows the real sizes (graphics 654/362, intuition 468/1288, dos 222/82...).
  **exec messages, ports, I/O, libraries and devices (2026-11-05, coverage §7 rank 12)**: spec
  `exec-messages-io-v34`. `ports.s`: PutMsg runs the action `mp_Flags AND 3` (bits 2-7 ignored) only when
  `mp_SigTask` is not NULL: Signal with the bit number modulo 32 (a bit >= 32 used to signal nothing), Cause for
  PA_SOFTINT (it was ignored; the softint now runs before PutMsg returns), nothing for PA_IGNORE, and action 3 calls the
  routine held in `mp_SigTask` (A0 = routine, A1 = port, D0 = flags, its D0/D1/A0/A1 returned); ReplyMsg without a
  reply port marks the message NT_FREEMSG and returns 0 (it was NT_REPLYMSG); AddPort no longer sets NT_MSGPORT and
  empties `mp_MsgList` under Forbid; RemPort/RemResource keep D0/D1; WaitPort returns the message in A1 too and keeps
  D1/A0 when the port is not empty. `io.s`: DoIO/SendIO no longer write `ln_Type` (exec used to mark every request
  NT_MESSAGE), so audio.device, console.device (held CMD_READ) and gameport.device now mark a request they keep
  pending NT_MESSAGE themselves (gameport at BeginIO entry: its reply routine skips a request still typed
  NT_REPLYMSG); OpenDevice clears `io_Unit` before the device's Open, passes A0 = device, returns A0 = device / 0 and
  reads `io_Error` with its own saved request pointer; RemLibrary/RemDevice give Expunge D0 = base; AddLibrary/
  AddDevice run the SumLibrary step. `library.s`: OpenLibrary compares versions as signed words and walks past a
  too-old node of the same name (OL13), the Open vector gets A0 = D0 = base and A1 = D1 = name. `execmisc.s`:
  SumLibrary only with LIBF_SUMUSED, word sum in the upper half of `lib_Sum` (it wrote a long, low word), CHANGED
  -> stored, otherwise verified and a mismatch is the dead-end alert `$81000003`. `resident.s`: AddResource no
  longer sets NT_RESOURCE (every resource of ours sets it itself), OpenResource under Forbid. Dev self-tests KBDDEV,
  AUDIO ALLOC and DISKRES now expect NT_FREEMSG for their reply-port-less requests. `tests/exec_msgio_probe.sh` (+
  `tests/exec_msgio_check.py`; output through a gdb-read buffer; argument N runs N1, `MLP_ALERT=1` boots a second
  time for AL4): 131 vectors, 40 failed on the previous kick-prod (39 values + N1 not run there: PA_SOFTINT and
  action 3, bit modulo 32, ReplyMsg without port, WaitPort A1, AddPort type, DoIO type, OpenDevice io_Unit/A0,
  Expunge D0, signed and walking OpenLibrary, the whole checksum table, AddResource type, RemPort/RemResource D0); 0 of
  132 after (AL4 included) on kick-prod. Dev ROM: every value passes, but the startup-sequence CLI runs there with
  TDNestCnt 0 (so `ne=FF00`), the same on the previous dev ROM: a Forbid left by the dev runtime harness, not by this
  change. prepush FAIL=0 (Lemmings menu looked at), Workbench 1.3.3 on kick-prod: desktop (836152 free memory, as
  before), disk drawer and a Shell with `info`/`dir`; rawdofmt (205) and graster (156) probes 0 FAIL. Deliberate
  differences from 1.3: CloseLibrary(NULL) returns 0 (1.3: illegal-instruction Guru), probe N1; OpenDevice reads
  `io_Error` and returns A0 through its own saved registers, so a device Open that changes A2/A3 does not disturb it;
  PutMsg action 3 restores A6 after the routine; the message type is written inside PutMsg's Disable (same values).
  Open points: the PA_SOFTINT softint runs at SR $2100 here (level-1 dispatch), $2000 on 1.3
  (`exec-scheduling-v34` §8, not this page; probe P4 tagged "ours"); InitResident's AUTOINIT path still Enqueues
  instead of calling AddLibrary/AddDevice/AddResource, so a ROM-tag library with LIBF_SUMUSED keeps its flags until a
  SetFunction (1.3: summed at init, flags 4); exec's OpenLibrary/OpenDevice/CloseLibrary/RemLibrary still carry the
  ramlib layer (loading, seglist freeing) from coldstart, where 1.3 adds it when dos starts; WaitIO without a Wait
  keeps the caller's D1 (1.3 replaces its low byte with `mp_SigBit`, a scratch register); the probe has not been run
  on the real ROM (an analysis agent can, `MLP_ANALYSIS=1 MLP_ARGS=`).
  **exec memory and signal semaphores (2026-11-05, coverage §7 rank 13)**: spec `exec-memory-semaphores-v34`.
  `memory.s`: 8-byte units everywhere (Deallocate/FreeMem/AllocAbs now round the start down and the end up; before,
  a free at an odd address wrote an unaligned chunk header and crashed), a header matches when it holds every
  low-word bit of the request (bits 3-15 were ignored: AllocMem(16, 8) succeeded), first fit, MEMF_CLEAR of the
  rounded size, AllocAbs of size 0 splits the chunk, AddMemList rounds mh_Upper down, MEMF_TOTAL ignored. Dead-end
  alerts as on 1.3: FreeMem of an address in no MemHeader (NULL included) $81000005, a range overlapping a free
  chunk $81000009 (FreeMem or Deallocate), ReleaseSemaphore of a free semaphore $81000008 (before: all ignored).
  AllocEntry/FreeEntry (moved from `execmisc.s`): list copy with MEMF_CLEAR only, zero lengths not allocated (before:
  AllocMem(0) made the whole call fail), results me_Reqs|$80000000 or $80010000 (before: -1), the copy leaked on an
  entry failure as on 1.3 (docs/MEMORY-USAGE.md). Semaphores: InitSemaphore writes only its four fields (it set
  ln_Type and cleared ss_MultipleLink), hand-off with ss_NestCount left at 0 and counted by the woken task (before:
  set to 1 by the releaser), Release takes Forbid only on the last level, ObtainSemaphoreList in two passes with
  ss_MultipleLink (before: a plain Obtain per member, which blocked on the first busy one with the later ones still
  free), CopyMemQuick copies size & ~3. Register contracts of spec §5 (Allocate/Deallocate keep A0, AllocMem keeps
  D1, FreeMem keeps A1, Obtain/Release keep everything, RemSemaphore/Procure keep D0...). Every internal caller
  checked: none relied on the old clobbers, on FreeMem(NULL), on AllocEntry's -1 (they test bit 31) or on CopyMem
  overlap (expansion's two copies are disjoint). `tests/exec_memsem_probe.sh` (+ `tests/exec_memsem_check.py`;
  private MemHeaders at the head of the MemList so that the figures do not depend on the system lists, two helper
  tasks for contention, nested AllocMem/FreeMem logged through SetFunction; `MSP_ALERTS=1` runs the ten dead-end
  vectors, one boot each, alert number read from $100): 188 vectors, 65 failed before (and D9c-D9f crashed the old
  ROM), 0 after on kick-prod and on the dev ROM, 10/10 alerts. The dev ROM's shell runs commands under Forbid
  (`ser_lock`, shell.s), which starves the helper tasks: the probe drops that level first, prints
  TDNestCnt/IDNestCnt between its sections (Z lines, expected FF) and runs at priority 20 (helpers 22/21, 15 when
  one must wait for the probe) above the dev ROM's always-ready demo tasks. Workbench 1.3.3 on kick-prod: desktop and memory
  title "836152 free memory" as before; the disk window opens. Deliberate differences from 1.3: (1) sizes that round
  to 0 ($FFFFFFF9-$FFFFFFFF) fail in Allocate/AllocMem (1.3 returns the first chunk without consuming it; A11,
  M10); (2) AllocEntry with ml_NumEntries = 0 returns an empty list (1.3 processes one entry past its block; E8);
  (3) AddSemaphore initialises and links the semaphore in A1 and sets ln_Type (1.3 uses A0 and links A0+16); (4)
  ObtainSemaphore checks the owner after each wake-up, so a stray SIGF_SEMAPHORE does not break in (1.3 returns after
  its single Wait with the other task still owner; C2); (5) an overlapping free alerts before any change (1.3 links
  some straddling ranges first; not observable, the alert is a dead end); (6) exact scratch-register values are not
  reproduced (A1 after a failed Allocate, D1 after FreeMem...), only which registers change. Kept from our previous
  allocator: the expunge-and-retry of a failed AllocMem and pr_Result2 = 103 for a process (ramlib-v34 §6), now
  skipped for sizes that round to 0. Choices where the spec is silent: AllocEntry frees the obtained entries in
  allocation order after a failure (open point 3); "free semaphore" for the alert = ss_QueueCount < 0; AllocAbs of
  size 0 at the very start of a chunk succeeds without changing anything; ObtainSemaphoreList's second pass counts a
  level for a member it owns with ss_NestCount 0 (a hand-off). Open points: from a task, Signal() of a
  higher-priority waiter only sets SAR and AddTask() of a higher-priority task does not reschedule, so the other task
  runs at the next Permit, Wait or interrupt exit, where exec-scheduling-v34 §1 and §2.7 have both call Reschedule
  (the probe waits for its helpers and follows each Signal with Forbid/Permit; scheduling code, not changed here);
  ss_NestCount values for a release in the handed-off-but-not-yet-woken state are not specified.
  **mathffp.library 34.1 (2026-11-05, coverage §7 rank 15)**: spec `mathffp-v34`. `src/exec/mathffp.s` rewritten
  from the arithmetic rules of §4: a value with low byte 0 is zero (`$00000080` is not); SPTst reads D1; SPCmp
  returns +1 when D1 > D0 with the codes of "D0 compared with D1" (sign, exponent, then the mantissa as a signed
  24-bit number); SPFlt/SPMul round to nearest with ties away from zero, SPDiv to nearest, SPFix truncates and
  saturates ($7FFFFFFF V, $80000000 Z+V, low byte 0 returned unchanged); SPAdd/SPSub align with 8 guard bits, round
  half up before normalising, truncate a carry-out and ignore an operand 24 or more exponents below; SPMul
  saturates as soon as the exponent sum reaches 192; SPDiv selects its exponent step by a signed compare of the
  mantissas, saturates with the divisor's sign when the step reaches exponent 128, and a divisor with low byte 0 (or
  a zero mantissa reached by the division) takes the 68000 zero-divide exception; exponent-0 results are kept when
  negative and flushed when positive; SPFloor/SPCeil exact, Ceil = Neg(Floor(Neg)). Registers: D1 preserved by
  Abs/Neg/Add/Sub/Mul/Div, D2-D7/A0-A6 by all, A6 unused, at most 28 bytes of stack (return address included). Base:
  version 34.1, ID string `mathffp 34.1 (18 Aug 1987)` CR LF, lib_Flags LIBF_SUMUSED, NegSize 96 / PosSize 34 (no
  data table any more: our MakeLibrary's InitStruct clears the whole base and so zeroed both sizes), Null returns D0
  unchanged, Close never expunges, Expunge sets LIBF_DELEXP while open and otherwise removes the base and frees its
  130 bytes. The dev self-test expected the old SPCmp order and an overflow for 3/0; it now checks SPCmp the 1.3 way
  and a "-0" divisor. Because a failing AllocMem now really removes mathffp (count 0), `td_cachebuf` asks
  AvailMem(MEMF_FAST|MEMF_LARGEST) before trying its 8-track cache, so a chip-only A500 does not lose mathffp at the
  first floppy read (the Workbench needs it). `tests/mathffp_probe.sh` (+ `tests/mathffp_check.py`: the 202 vectors
  of §7, A6 = 0, entry CCR $1F, stack, trap and library checks, 264 in all, plus an arithmetic model of §4): 94 of
  the 202 vectors failed before (62 only because D1 was clobbered; the others: SPCmp reversed, no trap on division
  by zero, saturation flags, exponent-0 and low-byte-0 cases, Add/Sub rounding), 0 of 264 checks fail after on
  kick-prod and dev. Workbench 1.3.3: the disk window and its scroll bars are pixel-identical to the previous ROM.
  Deliberate differences from 1.3: none in the results; stack depths are smaller (Fix/Flt/Tst/Abs/Neg 4, Cmp and
  Floor 8, Ceil 12, Add/Sub/Mul/Div 28; 1.3: 4/12/4..28/8..32/16). Choices where the spec is open: SPAdd/SPSub
  result with final exponent 0 follows SPMul (kept when negative, 0 when positive; open point 2); Open does not
  clear LIBF_DELEXP (open point 3); SPAdd/SPSub of unnormalised operands whose aligned mantissas cancel past zero
  wrap in 32 bits (unspecified).
  **Memory budget against 1.3, same configuration (2026-11-05)**: measured stage by stage and caller by caller
  against the black-box 1.3 budget (`docs/analysis/memory-budget-v34.md`), Amiberry A500, 512 KB chip + 512 KB
  slow, Workbench 1.3.3 (`docs/MEMORY-USAGE.md`). Idle gap 24,896 bytes with an empty DF1, 42,752 with DF0 only;
  free chip is 35,848 bytes better than 1.3. SetPatch, FF/BindDrivers, resident and loaded-code steps are
  byte-identical to 1.3. The gap is the track cache (+28,664 against one 1.3 MFM buffer), process stacks (+10,904),
  the keyboard feeder process (+4,632), the Workbench state block, 6,344 bytes of low chip outside the chip
  MemHeader, and 1,632 bytes the initial CLI leaves after `endcli`; offset by no file system buffers (−8,160) and
  less chip for the display (−4,696). Ranked reduction candidates are in that page (not implemented). Also seen:
  `ask` as the first startup-sequence line does not return on our ROM; icon.library is loaded by BindDrivers
  (stage 4) on our ROM, and very likely on 1.3 too (the step is byte-identical), where the 1.3 page says LoadWB.
  **One input task (2026-11-05)**: the keyboard feeder process (priority 4, 4 KB stack) is gone; its work (raw
  keys into input.device, IECLASS_TIMER tick, key repeat) runs in the intuition input task at priority 20, as on 1.3
  where Intuition runs inside the input.device task. `src/dos/feeder.s` now exports `fd_init` (one 248-byte block:
  state, timer reply port, two timerequests), `fd_arm` (before each Wait: timer request for the next deadline,
  returns the feeder's signal, shared by the keyboard interrupt and the timer reply) and `fd_service` (at each turn
  of the input task's loop, before the next ring item: timer reply, every key of the raw ring, then the due tick and
  repeat; the ring-drain-before-repeat rule of 3e62aa5 is kept). The input handlers run at the top of that loop,
  never inside an action. Starvation and deadlock: menus held open, drags, sizing and requesters are handled event
  by event, so the keyboard is serviced between events; only an action that waits (a verification waiting for the
  application's reply, a layer lock held by another task, WaitTOF) delays it, the keys waiting in the 16-entry raw
  ring; a verification freezes the whole input system on 1.3 too (intuition-input-menus §1 point 4). None of our
  own windows asks for a verification. Stack: one 4 KB stack for both jobs, high-water mark 916 bytes (pattern fill
  through gdb once the desktop was idle, 324 bytes used by then; then the session below), 3,180 bytes never touched.
  Validation: `make` and `make kick-prod` is_kick ok; prepush (dev) FAIL=0, missing=[], Lemmings menu looked at;
  boot_c dev shell: `ver` typed -> E2 SHELL ver OK and FEEDER OK=v. Workbench 1.3.3 on kick-prod: title 840,536
  free (836,152 before, +4,384 = TCB 240 + stack 4,096 + MemList 32 + 16 from merging the feeder's blocks); disk
  window, drag and resize, right-button menus, Utilities and Prefs drawers, Shell `echo`/`info`/`dir` one prompt
  each, a held `a` repeats, Shift+b, Preferences opened and cancelled, Rename with a held Backspace in the string
  gadget, Info. `tests/ticks.s` from the Shell (log copied to AUX:), new ROM against the previous one, same disk:
  INTUITICKS 301 in 30.00 s (10/s, every gap 100 ms) on both; held `a` and cursor up: first repeat 0.400 s, period
  0.040 s (the disk's Preferences), no repeat after the release, on both. `tests/menucat.s`: right Amiga + O ->
  MENUPICK F800 qual 0080, right Amiga + T -> 0080 (Export/Texte sub-item).
  **Initial CLI end of file and low RAM clear (2026-11-06)**: a READ of 0 bytes (Ctrl-\ in the boot console since
  cf47ed1) now ends the initial CLI as EndCLI does, as on 1.3 (`shell.s` main loop sets cli_Background and takes the
  EndCLI path); before, it parsed the stale buffer ("Unknown command"). Checked on kick-prod: the AmigaSlopDOS window
  closes and the Workbench screen shows. Coldstart now zeroes `$500` up to `LOWHEAP_LO` (`$1000`) instead of `$800`:
  the `$800`-`$1000` cushion is never allocated, and L:Shell-Seg reads `$9D8` as an alias name at each NewShell (it
  would free a bogus node if a word `$0009` or a matching name were there on a real machine whose RAM is not zero at
  power-up); read back as 0 at `$800` and `$9D0` after boot.
  **Memory, merged result (2026-11-05)**: one input task (+4,384), console handler and initial CLI (+2,872) and
  low chip (+5,376) together: Workbench 1.3.3 idle on kick-prod, default harness (512+512, DF1 empty), title
  **848,784** free against 836,152 before and 861,048 on 1.3 (gap 24,896 -> 12,264). Prepush FAIL=0, probes of
  ranks 12/13/15 all pass, Bubble Bobble credits and Sanity-Arte run on the merged ROM.
  **Low chip made allocatable (2026-11-05, MEMORY-USAGE candidate 3)**: with slow RAM the supervisor stack moves to
  the top 4,096 bytes of slow RAM, as on 1.3 (ExecBase `SysStkLower`/`SysStkUpper` now set; coldstart switches SP
  there as soon as `slow_probe` answers), and `add_low_chip` lowers the chip MemHeader to `$1000` (`LOWHEAP_LO`)
  after the memory self-test. `$800`-`$1000` stays out as a cushion. Without slow RAM nothing changes (ExecBase, the
  `$1500`-`$2500` margin, which only protects ExecBase from a supervisor stack overflow, and the stack stay).
  Workbench 1.3.3 idle on kick-prod, 512+512: 836,152 → **841,528** free (+9,472 chip, −4,096 slow). Before the
  change, a log-only IPC watch over `$800`-`$2500` (CPU and DMA) through a whole Workbench session with a Shell saw no
  write; only L:Shell-Seg reads `$9D8` at each NewShell (it hands ExecBase `$C00276` to a BCPL string routine as a
  BSTR; `<< 2` wraps to `$9D8`; explained on 2026-11-06, see below: not a DOS field). Deepest supervisor
  stack seen: 896 bytes. Two designs failed on real programs first: heap down to `$800` (Bubble Bobble loads SP with
  the start of a 512-byte chip block it allocates; the block landed at `$8E0` and the stack ran over the low-RAM
  variables), then a separate low-chip MemHeader (Sanity-Arte crashed; not traced, most likely it expects 1.3's
  single chip header in the MemList).
  Validation of the final ROM: prepush FAIL=0 (Lemmings menu looked at); Holiday Lemmings/FLT intro, Bubble Bobble,
  Sanity-Arte, Spaceballs, Desert Dream, Monkey Island 1, SimCity on 512+512 and chip only against the previous ROM
  (same screens, demos at other frames); soft-kick ADF hosted by our ROM.
  **Shell-Seg `$9D8` read explained (2026-11-06)**: no DOS/CLI/process field of ours holds ExecBase. Caught with a
  log-only IPC read watch on `$9D8`, then a gdb break on Shell-Seg's string-compare routine when its second argument
  was `$C00276`, following the BCPL frames back (Shell-Seg disassembled, behaviour only): the caller is the Shell's
  alias insertion (sorted singly linked list of `[next, BSTR "name<TAB>value"]` nodes). When the walk reaches the
  end of the list it still compares the new name with the name field of the nil node, `!(0+1)`, which is the
  longword at absolute address 4, AbsExecBase. The list head is a local of Shell-Seg's main routine, cleared by
  Shell-Seg itself, so the first `alias` line of `S:Shell-Startup` hits it at each NewShell (the later ones sort
  before `xcopy`). A/B on kick-prod, Workbench 1.3.3: with a `S:Shell-Startup` holding only `Prompt`, opening the
  Shell icon and a NewShell gives no `$9D8` access; `alias foo dir` typed then gives exactly the 4 reads, `alias bar
  dir` none, and `alias` lists both. 1.3 does the same with slow RAM (ExecBase `$C00276`, coldstart-hardware-v34),
  where `$9D8` is chip heap. Our `$9D8` sits in the never-allocated `$800`-`$1000` cushion and reads 0, so the compare
  answers "different" and the insertion is normal; nothing to change in the ROM. Constraint kept in
  ARCHITECTURE.md ("Low chip memory map"): a word `$0009` at `$9D8` would make Shell-Seg free the nil node.

## Immediately actionable work (start of implementation, upon approval)

M0 and M1 start **in parallel** (sealed tracks):
1. Scaffold the repository + `git init` + `docs/CLEANROOM.md` (the discipline above).
2. Copy the ROM read-only into `assets/`; re-check the fingerprints.
3. Install/pin vasm+vbcc+vlink (+ bebbo gcc if needed); produce the 256K **hello-ROM** and
   boot it in the emulator (FS-UAE+Xvfb).
4. Set up the test bench: scripted boot + state capture; oracle diff via `romtool`.
5. Launch the analysis track (dedicated ROM+radare2 agent) on the boot sequence and the exec spec.

## Verification (end to end)

- **ROM integrity**: `md5sum`/`sha1sum` of the copy == known fingerprints; `romtool info` validates
  header/checksum/size of any produced image.
- **Primary assertion channel**: **serial log (`SERDAT`) captured** by the emulator — deterministic,
  greppable, CI-friendly; each milestone emits verified serial markers. The display (colour
  `$DFF180` → screen → "insert disk" hand → CLI) is a secondary signal, not the basis of the assertions.
- **Emulator boot**: hello-ROM then each milestone boot under scripted FS-UAE/WinUAE. CI via Xvfb.
- **Black-box oracle**: compare the observable behaviour of our ROM with the real KS 1.3 in
  the emulator via **targeted behavioural probes → test vectors** (analysis track), never by
  copying its code nor by a global system diff.
- **Host tests**: cross-check the *documented* API semantics and run test binaries under
  `vamos` (not to host our exec).
- **Syntax/build**: asm/C checked at build time (68k toolchain — no `py_compile`).

## Confirmed facts (research) — main sources

- vasm/vlink `sun.hasenbraten.de` · bebbo `codeberg.org/bebbo/amiga-gcc` · amitools romtool
  `amitools.readthedocs.io/en/latest/tools/romtool.html` · checksum `cloanto.com/amiga/roms/help/checksum.html`.
- AROS `github.com/aros-development-team/AROS`; APL `en.wikipedia.org/wiki/AROS_Public_License`;
  68k support `en.wikibooks.org/wiki/Aros/Platforms/68k_support`.
- Docs: NDK 3.2 (Aminet `dev/misc/NDK3.2R4`, Hyperion); RKRM/AutoDocs `amigadev.elowar.com`.
- BCPL/dos: `en.wikipedia.org/wiki/AmigaDOS`; AROS ABIv1 DOS draft (sourceforge). Related art: ARP,
  BootWB1x/HelloAmi, BlizKick.
- Emulators: `fs-uae.net/docs/kickstart-roms/`; WinUAE headless (forum, to be validated).

## To verify on hardware at run time (inherited from research)

- Does `romtool build` write the checksum or is `copy -c` needed as a 2nd pass (`romtool info` to compare).
- Exact WinUAE config keys (`kickstart_rom_file`, `-s use_gui=no`) on the installed version.
- Actual NDK 3.2 / RKRM licences before any redistribution of derived documentation.
- Exact BPTR/packets model of AROS `rom/dos/` when tackling M6.
- Boot of an A500/68000 configuration under UAE to frame the minimal memory constraints.
- Availability of **1.x** references: RKRM 1st edition + 1.x `.fd`/includes (correct V34 LVO sets).
- Actual capabilities of `vamos` (what it can/cannot test with respect to our own code).
