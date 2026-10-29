# boot-sequence.md — Boot sequence (Kickstart 1.3 / V34.5)

> **Behavioural** description (algorithm, order of operations). No opcode or listing
> reproduced. Facts anchored on the ROM: reset vectors, exec's `rt_Init`, flags/priorities of the
> residents (cf. `module-map.md`). The `InitCode`/`InitResident` mechanism is described from the
> public ABI (`exec/resident.i`, exec V34 AutoDocs); the **inferred** points (not verified by a
> code trace, since the "dirty" track does not transcribe instructions) are marked *(inferred)*.

## Phase 0 — Hardware reset (68000 vector)

At reset, the 68000 reads two longwords at the physical addresses **$000000** (initial SSP) and
**$000004** (initial PC). At the very beginning, the Agnus/Gary **overlay** logic maps the ROM
($FC0000) onto address $000000, so that:

- `*(ULONG*)$000000` = `0x11114EF9` → initial SSP. The two high-order bytes `0x1111`
  also serve as the ROM recognition word; `0x4EF9` is the opcode which, when executed, continues on to
  the coldstart (an artefact of the longword's dual use).
- `*(ULONG*)$000004` = an address in the ROM → initial PC = **exec coldstart** = `rt_Init` of the
  exec ROMTag. The CPU therefore starts directly in exec; exec is never "initialised" by the
  resident scan (cf. `module-map.md`).

## Phase 1 — exec coldstart: minimal CPU/hardware bring-up *(inferred at the detail level)*

Behavioural order:

1. Switch to supervisor mode, mask all interrupts (SR level 7), load a provisional working
   SSP.
2. Put the custom chips in a neutral state: turn off DMA and interrupts (`DMACON`, `INTENA`,
   `INTREQ` cleared), stop audio, etc. — silencing the hardware before anything else.
3. Determine the CPU configuration (the result will be published in `ExecBase.AttnFlags`) and the
   mains/VBlank frequency (PAL 50 Hz / NTSC 60 Hz → `VBlankFrequency`, `PowerSupplyFrequency`).
4. Lift the ROM overlay (via CIA) to expose chip RAM at the bottom of the address space, then
   **size the RAM** (chip, and fast/ranger if present) by probing.
5. Decide where `ExecBase` goes. First check the **reset-survival** vectors
   (`ColdCapture`/`KickMemPtr`/`KickTagPtr`): if a valid `ExecBase` survives and its
   checksum is correct, it can be reused; otherwise a new one is built.

## Phase 2 — Construction of ExecBase and of the kernel

1. Allocate/place the `ExecBase` structure in chip RAM and write its pointer at **`*(ULONG*)$000004`**
   (= `AbsExecBase`/`SysBase`). Set the complement `ChkBase = ~SysBase` (offset +0x26).
2. Initialise exec's library node: `lib_Version = 34`, `lib_Revision` (rev. 2),
   `lib_IdString` → `"exec 34.2 …"`, type `NT_LIBRARY`, and **build exec's LVO jump table**
   (negative vectors, 6-byte stride; cf. `exec-spec.md`). exec bootstraps itself: the
   jump table is not a static auto-init table present in the ROM *(verified: no parsable exec
   `MakeFunctions` table in the exec module's range)*.
3. Initialise all of `ExecBase`'s system lists to empty: `MemList`, `ResourceList`,
   `DeviceList`, `IntrList`, `LibList`, `PortList`, `TaskReady`, `TaskWait`, `SemaphoreList`,
   the 5 `SoftInts`, and the scheduling fields (`Quantum`, `ThisTask=NULL`, nest counts).
4. Build the first `MemHeader` from the probed RAM and add it to `MemList`
   (chip RAM: attributes `MEMF_CHIP|MEMF_PUBLIC` = `0x3` in V34 — `MEMF_LOCAL`/`MEMF_24BITDMA`
   are **V36** bits, not V34; cf. `test-vectors.md`).
5. Install the 16 **interrupt autovectors** (`ExecBase.IntVects[16]`) and the trap/exception
   handlers. Publish `AttnFlags` (CPU/FPU config) and `AttnResched`.

## Phase 3 — Resident scan and construction of the `ResModules` list

1. Scan the ROM (and, if present, the extension/diag ROMs) from the low address to the high
   address looking for the **matchword `0x4AFC`** followed by an `rt_MatchTag` pointing to itself
   (false-positive filter). Each valid Resident is added to a working list in
   **increasing** address order.
2. **Sort** this list by **decreasing** `rt_Pri`; ties keep the scan order
   (increasing address). The result is published in `ExecBase.ResModules` (terminated pointer
   array). → The final order is exactly that of the table in `module-map.md`, from exec (pri 120)
   to strap (pri -60).

## Phase 4 — Initialisation driven by `InitCode` (passes by timing flags)

`InitCode(startClass, version)` walks `ResModules` in order (decreasing priority) and,
for each resident selected by `startClass`, calls `InitResident`:

- `InitResident` tests `rt_Flags & RTF_AUTOINIT`: if set, it calls `MakeLibrary` with the
  auto-init table (`dataSize`/`vectors`/`structure`/`initFunction` — cf. `module-map.md`), adds the base
  to the right list (`LibList`/`DeviceList`), then runs `initFunction`. Otherwise, it jumps
  directly into `rt_Init` (manual init code that takes care of allocating and publishing its base).

In THIS ROM, only the following timing bits are present:

1. `InitCode(RTF_SINGLETASK, 0)` — **no module** concerned (no flag 0x02). Pass without effect.
2. Multitasking start: creation of the initial task, activation of the scheduler, enabling
   of interrupts. *(inferred)*
3. `InitCode(RTF_COLDSTART, 0)` — **main pass**. Initialises, in priority order:
   expansion → potgo → keymap → cia → disk → misc → graphics → keyboard → gameport → timer →
   audio → input → layers → console → trackdisk → intuition → alert.hook → mathffp → romboot →
   strap. (ramlib, workbench.task, dos do NOT have the COLDSTART bit → not started here.)
4. `InitCode(RTF_AFTERDOS, …)` — **no module** concerned (no flag 0x04) in the ROM.

### Roles of the end-of-chain modules

- **alert.hook** (pri 5, type UNKNOWN): hook installed early for the display of Guru Meditations
  (recovery/alert); set up before the lower-priority modules.
- **ramlib.library** (AUTOINIT, without COLDSTART): service for loading libraries/devices from
  disk (`LDDemon`). Since it is not marked COLDSTART, it is brought in by a dedicated / on-demand path
  rather than by the `InitCode(RTF_COLDSTART)` pass. *(inferred)*
- **romboot.library** (pri -40): handles autoboot / booting from expansion cards (expansion.library).
- **strap** (pri -60, type UNKNOWN, "bootstrap"): **last** COLDSTART resident. It is the one that
  looks for a bootable device, reads the boot block, and starts up the DOS side. It explicitly brings in
  **dos.library** and **workbench.task** (both `rt_Flags=0`, hence not auto-started)
  as part of the file-system bootstrap. *(inferred)*

## Summary of the overall order (oracle)

```
reset → coldstart exec (reset PC = exec's rt_Init)
      → hardware silence + RAM sizing + AttnFlags/VBlankFreq
      → ExecBase construction (@*(ULONG*)4) + exec jump table + lists + chip MemHeader + IntVects
      → ROM scan (match 0x4AFC) → sort (pri desc, address asc) → ResModules
      → InitCode(SINGLETASK)  [empty]
      → multitasking start
      → InitCode(COLDSTART)   [expansion…strap, in module-map.md order]
          └─ strap (last): disk boot → dos.library + workbench.task
      → InitCode(AFTERDOS)    [empty]
```

## Uncertainties

- The detail of phases 1 and 2 (fine order of the custom registers touched, exact RAM probing
  mechanism, precise placement of ExecBase vs reset survival) is **inferred** from standard exec
  V34 behaviour and not verified line by line (clean-room constraint: no code transcription).
- The exact point where ramlib, dos and workbench.task are initialised (dedicated path vs strap bootstrap)
  is inferred from their flags (`rt_Flags` without a timing bit); the implementation track will have to
  confirm it through observable behaviour (opening `dos.library` possible only after boot).

## Clean-room review

Review of 2026-10-29.

- [x] No 68000 instruction sequence transcribed or paraphrased, no disassembly excerpt.
  Phases 1-4 are a high-level behavioural order (marked *(inferred)* where it is not
  observed), consistent with the public ABI `exec/resident.i` and the AutoDocs, not a walk-through of the ROM code.
- [x] **Fixed**: removed the ROM addresses of the coldstart entry point (value of the reset PC,
  title of phase 1, "oracle" diagram) and the bounds of the exec module's range; replaced by
  "address in the ROM" / "exec module's range".
- [x] Remaining: hardware addresses ($000000/$000004, overlay, ROM base $FC0000), header
  `0x1111`/`0x4EF9`, public `ChkBase` offset (+0x26), `MEMF_*` constants.
