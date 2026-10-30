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
    → the image (5 planes/32 colours copied ROM→chip), displayed via MakeVPort/MrgCop/LoadView at handoff. Overscan
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
    supported (clean failure). Serial proof **D2LOADSEG**: test executable `D2Test` (CODE + DATA section + 1
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
    - **D3b — DF0: file-handler process + dos_sendpkt (DONE).** `src/dos/handler.s` (`dos_handler_df0`): a real
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
    Remaining: horizontal ScrollRaster (dx), ACTION_WAIT_CHAR timeout (answers at once).
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
    **Interleaved — SetPatch / SysInfo (user request 2026-10-21, before resuming the Workbench)**: complete V34
    exec (real SetFunction & 33 other LVOs), shell that honours `cli_Module`, Alert relay, DeleteLayer in three
    steps, public V34 GfxBase, CIA TODs started, DF0 FileSysStartupMsg; SysInfo displays its whole page
    (clock, Agnus/Denise, PAL, frequencies); intuition application gadgets (GADGETUP/DOWN, AddGadget,
    RefreshGadgets...): its buttons work (SPEED). Open: PROP/STRING gadgets, Caesar / Scooby-Doo / bootdisk-amiga-m68k floppies of the ADF suite. Each end of step: `tests/adf_suite.sh`
    on the floppies of `assets/test_adf/`.
    **Next**: `SetFunction`, NIL:/redirections, LoadWB (workbench, icon.library, layers).
- **M7+ — long tail**: layers, console, input, audio, gameport, mathffp, workbench.task, parity;
  then **real A500 EPROM** (256K ROM, wiring/adapter).

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
