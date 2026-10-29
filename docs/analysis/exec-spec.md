# exec-spec.md — ABI spec of exec.library (V34 / Kickstart 1.3)

> Two provenances, labelled per field:
> **[ROM]** measured in `kick34005.A500`; **[ABI]** layout/offsets taken from the documented public
> ABI (`exec/execbase.i`, `exec/libraries.i`, `exec/nodes.i`, `exec_lib.fd` V34, exec
> AutoDocs). Since exec is not RTF_AUTOINIT, its base has no `dataSize` nor static vector table
> in ROM: the ExecBase layout and the LVO list come from the public ABI, corroborated
> by the ROM where possible. No opcode is reproduced.

## 1. Anchor point: AbsExecBase

- **[ABI]** `AbsExecBase = *(struct ExecBase **)$00000004`. After init, the longword at physical
  address **$000004** contains the pointer to `ExecBase` (the reset PC vector is only visible there
  during the ROM overlay at the very beginning, cf. `boot-sequence.md`).
- **[ABI]** Integrity: `ExecBase.ChkBase` (offset +0x26) = `~AbsExecBase` (one's complement).
  `SumExecBase`/checksum validate the base ↔ complement consistency.

## 2. Layout of struct ExecBase  **[ABI — `exec/execbase.i`]**

ExecBase starts with a library node (`struct Library`, 34 bytes = `0x22`), itself prefixed
by a `struct Node` (14 bytes). Offsets (decimal in parentheses):

### 2a. `struct Library` header (0x00..0x21)
| Off | Size | Field | Note |
|----:|:------:|-------|------|
| 0x00 | APTR | `LN_Succ` | node: successor |
| 0x04 | APTR | `LN_Pred` | node: predecessor |
| 0x08 | UBYTE | `LN_Type` | = `NT_LIBRARY` (9) |
| 0x09 | BYTE | `LN_Pri` | |
| 0x0A | APTR | `LN_Name` | → `"exec.library"` |
| 0x0E | UBYTE | `lib_Flags` | |
| 0x0F | UBYTE | `lib_pad` | |
| 0x10 | UWORD | `lib_NegSize` | size of the jump table (bytes) = nbLVO×6 |
| 0x12 | UWORD | `lib_PosSize` | size of the data (= sizeof ExecBase) |
| 0x14 | UWORD | `lib_Version` | **= 34** [ROM, cf. header] |
| 0x16 | UWORD | `lib_Revision` | = 2 (exec 34.2) |
| 0x18 | APTR | `lib_IdString` | → `"exec 34.2 (28 Oct 1987)"` [ROM, image header] |
| 0x1C | ULONG | `lib_Sum` | checksum of the jump table |
| 0x20 | UWORD | `lib_OpenCnt` | |

### 2b. ExecBase-specific fields
| Off (dec) | Size | Field | Role |
|----------:|:------:|-------|------|
| 0x22 (34) | UWORD | `SoftVer` | software version |
| 0x24 (36) | WORD | `LowMemChkSum` | |
| 0x26 (38) | ULONG | `ChkBase` | = `~AbsExecBase` |
| 0x2A (42) | APTR | `ColdCapture` | reset-survival vector (cold) |
| 0x2E (46) | APTR | `CoolCapture` | |
| 0x32 (50) | APTR | `WarmCapture` | |
| 0x36 (54) | APTR | `SysStkUpper` | top of supervisor stack |
| 0x3A (58) | APTR | `SysStkLower` | bottom of supervisor stack |
| 0x3E (62) | ULONG | `MaxLocMem` | top of chip RAM |
| 0x42 (66) | APTR | `DebugEntry` | |
| 0x46 (70) | APTR | `DebugData` | |
| 0x4A (74) | APTR | `AlertData` | |
| 0x4E (78) | APTR | `MaxExtMem` | top of expansion RAM |
| 0x52 (82) | UWORD | `ChkSum` | checksum of the IntVects area |
| 0x54 (84) | 16×`IntVector` | `IntVects[16]` | 16 interrupt autovectors, **12 bytes each** (`iv_Data`, `iv_Code`, `iv_Node`) → 192 bytes, ending at 0x114 |
| 0x114 (276) | APTR | `ThisTask` | current task |
| 0x118 (280) | ULONG | `IdleCount` | |
| 0x11C (284) | ULONG | `DispCount` | |
| 0x120 (288) | UWORD | `Quantum` | scheduler quantum |
| 0x122 (290) | UWORD | `Elapsed` | |
| 0x124 (292) | UWORD | `SysFlags` | |
| 0x126 (294) | BYTE | `IDNestCnt` | Disable nesting counter |
| 0x127 (295) | BYTE | `TDNestCnt` | Forbid nesting counter |
| 0x128 (296) | UWORD | `AttnFlags` | CPU/FPU capabilities |
| 0x12A (298) | UWORD | `AttnResched` | |
| 0x12C (300) | APTR | `ResModules` | → list of residents (cf. boot-sequence) |
| 0x130 (304) | APTR | `TaskTrapCode` | |
| 0x134 (308) | APTR | `TaskExceptCode` | |
| 0x138 (312) | APTR | `TaskExitCode` | |
| 0x13C (316) | ULONG | `TaskSigAlloc` | |
| 0x140 (320) | UWORD | `TaskTrapAlloc` | |
| 0x142 (322) | `List` (14) | `MemList` | list of `MemHeader`s |
| 0x150 (336) | `List` (14) | `ResourceList` | |
| 0x15E (350) | `List` (14) | `DeviceList` | |
| 0x16C (364) | `List` (14) | `IntrList` | |
| 0x17A (378) | `List` (14) | `LibList` | |
| 0x188 (392) | `List` (14) | `PortList` | |
| 0x196 (406) | `List` (14) | `TaskReady` | ready tasks |
| 0x1A4 (420) | `List` (14) | `TaskWait` | waiting tasks |
| 0x1B2 (434) | 5×`SoftIntList` (16) | `SoftInts[5]` | 80 bytes, ending at 0x202 |
| 0x202 (514) | 4×LONG | `LastAlert[4]` | 16 bytes |
| 0x212 (530) | UBYTE | `VBlankFrequency` | 50 (PAL) / 60 (NTSC) |
| 0x213 (531) | UBYTE | `PowerSupplyFrequency` | 50 / 60 |
| 0x214 (532) | `List` (14) | `SemaphoreList` | signal semaphores |
| 0x222 (546) | APTR | `KickMemPtr` | reset survival: memory list |
| 0x226 (550) | APTR | `KickTagPtr` | reset survival: additional ROMTags |
| 0x22A (554) | APTR | `KickCheckSum` | checksum of the two previous ones |

**V34 boundary**: in V34, the meaningful ExecBase fields **stop at `KickCheckSum`
(end ≈ 0x22E, 558 bytes)**. Everything that follows in the 2.0/3.x ROMs — `ex_EClockFrequency`,
`ex_CacheControl`, `ex_TaskID`, `ex_PuddleSize`, `ex_PoolThreshold`, `ex_PublicMemList`,
`ex_MMULock`, `ex_MemHandlers`/`ex_MemHandler` — **does not exist / is not used in V34**.
This is a delta the implementation track cannot discover on its own: do not reserve nor
expose these fields for a 1.3 target.

## 3. LVO jump table  **[ABI, corroborated by ROM]**

- **[ABI]** Each jump-table entry occupies **6 bytes**: opcode `JMP abs.l` (`0x4EF9`)
  + 32-bit address of the function. The entries are at **negative offsets** from the base:
  `-6, -12, -18, …`. Standard call: `JSR offset(A6)` with A6 = library base (= SysBase for
  exec). LVO *n* ↔ offset `-6·n`.
- **[ABI]** The first 4 entries are common to every library: `-6 Open`, `-12 Close`,
  `-18 Expunge`, `-24` reserved. exec's own functions start at `-30` (bias 30).

### LVO offsets of the requested primitives (stable across all versions, **confirmed used in the ROM**)
| LVO off | Function | Measured call sites [ROM] |
|--------:|----------|:---------------------------:|
| -132 | `Forbid` | 19 |
| -138 | `Permit` | 43 |
| -198 | `AllocMem` | 33 |
| -210 | `FreeMem` | 31 |
| -240 | `AddHead` | 8 |
| -246 | `AddTail` | 16 |
| -252 | `Remove` | 7 |
| -276 | `FindName` | 14 |

(Other confirmed landmarks [ROM]: `Supervisor` -30, `InitCode` -72, `FindResident` -96,
`InitResident` -102, `Alert` -108, `Disable` -120, `Enable` -126, `Wait` -318, `Signal` -324,
`OldOpenLibrary` -408, `CloseLibrary` -414, `OpenDevice` -444, `DoIO` -456, `OpenResource` -498,
`OpenLibrary` -552, `InitSemaphore` -558, `ObtainSemaphore` -564.)

### Size of the exec jump table in V34  **[ROM + ABI]**
ROM measurement: a histogram of all `JSR/JMP d16(A6)` calls (opcodes `0x4EAE`/`0x4EEE`,
negative displacement multiple of 6) over the whole ROM shows a **dense and contiguous use from LVO 1
(-6) up to LVO ~98 (-588)** — the signature of the exec functions called by all modules —
then a **sparse tail** LVO 101..106 (-606 to -636, 1 to 3 sites each). The deepest offset
observed **in the whole ROM** is **-636** (LVO 106).

Interpretation:
- The V34 exec jump table has on the order of **~102 entries** (LVO -6..-612, `lib_NegSize`
  ≈ 612), ending on the ABI side with the signal-semaphore block + `SumKickData`.
- The tail -618..-636 observed in the ROM is **not** exec: in particular -636 would correspond to
  `CacheClearU`, **impossible for exec on a 68000 without cache** → these calls target the base
  of ANOTHER library (A6 ≠ SysBase at those sites). They therefore do not prove the presence of
  `AddMemList`/`CopyMem`/`CopyMemQuick` in the V34 exec.
- Residual uncertainty: the exact boundary of the table (end at -606 `RemSemaphore` vs -612
  `SumKickData`) is within ±1 entry; the firm anchors above (up to `OpenLibrary` -552,
  and the requested primitives) are certain.

### Delta V34 → 2.0/3.x (functions ABSENT from the V34 jump table)
The V34 exec jump table is **noticeably shorter** than that of the 2.0/3.x ROMs. The following
functions are later additions — do **not** expose them for a 1.3 target:
`AddMemList` (-618, V36), `CopyMem` (-624, V36), `CopyMemQuick` (-630, V36),
`CacheClearU`/`CacheClearE`/`CacheControl` (-636/-642/-648, V37, irrelevant on 68000),
`CreateIORequest`/`CreateMsgPort` (… actually amiga.lib), `CachePreDMA`/`CachePostDMA`,
`CreatePool`/`DeletePool`/`AllocPooled`/`FreePooled` (-654.., V39), `AddMemHandler`/`RemMemHandler`
(V39), `ObtainQuickVector`, `StackSwap`, `ColdReboot` (-726), `TaggedOpenLibrary` (private negative
offset V36). The implementation track must refuse/ignore these LVOs to stay faithful to V34.

## 4. Observable behaviour of the primitives  **[ABI exec V34 AutoDocs]**

### Memory management
- `AllocMem(size D0, requirements D1) → D0`: allocates from the `MemList` a block of `size` bytes
  (rounded up to the memory alignment, **8 bytes** on Amiga) satisfying the `MEMF_*` bits of `D1`.
  Returns the address or **NULL** on failure. **`MEMF_*` bits available in V34** (`exec/memory.i`):
  `MEMF_PUBLIC` 0x1, `MEMF_CHIP` 0x2, `MEMF_FAST` 0x4, `MEMF_CLEAR` 0x10000 (block zeroed),
  `MEMF_LARGEST` 0x20000. **Delta**: `MEMF_LOCAL` 0x100, `MEMF_24BITDMA` 0x200, `MEMF_REVERSE`
  0x40000, `MEMF_TOTAL` 0x80000 are **V36** additions; `MEMF_KICK` 0x400 is **V39** — none
  exists in V34. The selection walks the `MemHeader`s by decreasing node priority;
  for a block satisfying several attributes, the first compatible `MemHeader` wins.
- `FreeMem(addr A1, size D0)`: returns the exact block (address+size) to its `MemHeader`, merges
  with the adjacent free regions. **The size passed must be identical** to that of the
  allocation (no implicit size header).
- Invariant: **8-byte** granularity/alignment; `AvailMem(req D1)` sums the free space of the compatible
  headers (`MEMF_LARGEST` gives the largest contiguous block, not the sum).

### Doubly linked lists (`struct List` / `struct Node`)
- `AddHead(list A0, node A1)`: inserts `node` at the head. `AddTail(list A0, node A1)`: at the tail.
- `Remove(node A1)`: removes a node (must already be linked; rewires `LN_Succ`/`LN_Pred`).
- `Enqueue(list, node)`: insertion sorted by decreasing `LN_Pri` (insertion at the end of the range
  of the same priority → this is the mechanism of the resident sort, cf. boot-sequence).
- `FindName(list A0, name A1) → D0`: looks for the first node whose `LN_Name` = the string `name`
  (case-sensitive comparison), **starting from the first node**; called on a node, it can
  resume the search from what follows. Returns the node or **NULL**.

### Mutual exclusion
- `Forbid()` / `Permit()`: increment/decrement `TDNestCnt`. Forbid prevents
  rescheduling (cooperative) as long as the counter has not returned to its initial state; **nestable**.
- `Disable()` / `Enable()`: prevent interrupts via `IDNestCnt`; nestable.
  Rule: keep Disable sections **very short**.

## 5. Uncertainties
- The ExecBase layout (section 2) is public ABI; it cannot be verified field by field in the
  ROM (runtime RAM structure). The **V34 boundary at ~0x22E** is the most important point of the delta.
- exec LVO count: ~102 (±1 on the tail). **RESOLVED** by the NDK `exec_lib.fd` V34 →
  **105 vectors, `lib_NegSize` = `$276`**, boundary at `CopyMemQuick` (-630); `AddMemList`/`CopyMem`/
  `CopyMemQuick` are V33 (hence present in V34), contrary to the inference below. See
  `docs/exec-lvo-table.md`. The ROM histogram had underestimated the tail. To pin down the last entry exactly, the implementation
  track can cross-check the official **V34** `exec_lib.fd`; the offsets of the requested primitives
  are certain and confirmed by use in the ROM.

## Clean-room review

Review of 2026-10-29.

- [x] No 68000 instruction sequence transcribed or paraphrased, no disassembly excerpt.
  §3 cites the LVO call opcodes (`0x4EAE`/`0x4EEE`) and `JMP abs.l` (`0x4EF9`) as the **public
  format** of the jump table and a statistical counting criterion, not as copied code.
- [x] **Fixed**: removed the ROM address of exec's `rt_IdString` string.
- [x] Remaining: public `exec/execbase.i` offsets, `exec_lib.fd` LVOs, `MEMF_*` constants, call-site
  counts (statistical, without address).
- [ ] Substantive remark (not fixed, outside the clean-room scope): the "Delta V34 → 2.0/3.x" list
  in §3 still classifies `AddMemList`/`CopyMem`/`CopyMemQuick` as V36, whereas §5 (resolved by
  `exec_lib.fd`) gives them as present in V34; §5 is authoritative.
