# test-vectors.md — Oracle vectors (Kickstart 1.3 / V34.5)

> Black-box testable assertions that a reimplementation must reproduce. **No code.**
> Two levels of provenance, labelled on each assertion:
> **[M] = measured in the ROM** `kick34005.A500` (hard oracle, falsifiable by re-reading with r2);
> **[D] = documented behaviour** (public ABI; the ROM does not dump the runtime value,
> the assertion follows from the exec V34 contract).
> Reference config for the runtime vectors: **A500, 512 KB of chip RAM, no expansion,
> 68000, PAL region** (unless NTSC is stated).

## A. ROM image (static)

- **[M] A1**: `*(ULONG*)$FC0000 = 0x11114EF9` (SSP/ROM-ID+opcode).
- **[M] A2**: `*(ULONG*)$FC0004` = an address in the ROM (reset PC = exec coldstart = exec's
  `rt_Init`, see B5).
- **[M] A3**: `*(ULONG*)$FC000C = 0x00220005` → version **34.5**. (Interpretation: Kickstart 1.3,
  corroborated by the strings `"Release 1.3"` and `"exec 34.2 (28 Oct 1987)"` present in the ROM.)
- **[M] A4**: exactly **24 valid ROMTags** (matchword `0x4AFC` + self-referencing `rt_MatchTag`)
  (list in `module-map.md`). All have `rt_Version = 34`.
- **[M] A5**: ROM footer — size field `0x00040000` (= 256 KB) in the last longwords.

## B. ROMTags — per-field assertions (all **[M]**)

- **[M] B1**: flags of the 5 RTF_AUTOINIT modules (bit 0x80): expansion `0x81`, ramlib `0x80`,
  audio `0x81`, intuition `0x81`, mathffp `0x81`. **No other** module has the AUTOINIT bit.
- **[M] B2**: **no** module has RTF_SINGLETASK (0x02) or RTF_AFTERDOS (0x04). Only
  COLDSTART (0x01) and AUTOINIT (0x80) appear.
- **[M] B3**: modules with `rt_Flags = 0x00` (no timing bit): exec, workbench.task, dos.
  Plus ramlib at `0x80` (AUTOINIT without COLDSTART). → these 4 are not started by
  `InitCode(RTF_COLDSTART)`.
- **[M] B4**: `rt_Type`: NT_LIBRARY(9) = exec, expansion, ramlib, graphics, layers, intuition,
  mathffp, dos, romboot (9 modules); NT_DEVICE(3) = keyboard, gameport, timer, audio, input,
  console, trackdisk (7); NT_RESOURCE(8) = potgo, keymap, cia, disk, misc (5);
  NT_TASK(1) = workbench.task (1); NT_UNKNOWN(0) = alert.hook, strap (2).
- **[M] B5**: exec's `rt_Init` = reset PC (A2). Exec's `rt_EndSkip` = address of the
  alert.hook ROMTag (the next tag in the ROM).
- **[M] B6**: exact priorities (signed byte): exec 120, expansion 110, potgo 100, keymap 100,
  cia 80, disk 70, misc 70, ramlib 70, graphics 65, keyboard 60, gameport 60, timer 50, audio 40,
  input 40, layers 31, console 20, trackdisk 20, intuition 10, alert.hook 5, mathffp 0,
  workbench.task 0, dos 0, romboot **-40** (byte `0xD8`), strap **-60** (byte `0xC4`).

## C. Initialisation order (sequence oracle) **[M for the sort keys]**

Two distinct sequences not to be confused: (a) `ResModules` = ALL valid residents
(the RTF flags filter ONLY `InitCode`, not membership of the list); (b) the
`InitCode(RTF_COLDSTART)` pass = the subset actually started.

- **[M] C1 — `ResModules` (24 entries)**: sorted by **descending `rt_Pri`, then ascending ROM
  address** for ties (order of position in the image). Exact order:

  1 exec · 2 expansion · 3 potgo · 4 keymap · 5 cia · 6 disk · 7 misc · 8 ramlib · 9 graphics ·
  10 keyboard · 11 gameport · 12 timer · 13 audio · 14 input · 15 layers · 16 console ·
  17 trackdisk · 18 intuition · 19 alert.hook · 20 mathffp · **21 workbench.task · 22 dos** ·
  23 romboot · 24 strap.
  (Pri 0 trio by ascending position in the ROM: mathffp < workbench.task < dos.)

- **[M] C2 — `InitCode(RTF_COLDSTART)` pass (20 entries)**: `ResModules` **minus** exec (kernel,
  not started by InitCode), ramlib (AUTOINIT without COLDSTART), workbench.task and dos (`rt_Flags=0`):

  expansion · potgo · keymap · cia · disk · misc · graphics · keyboard · gameport · timer · audio ·
  input · layers · console · trackdisk · intuition · alert.hook · mathffp · romboot · strap.

- **[M] C3**: tie check (the sort MUST produce these orders): pri100 potgo<keymap;
  pri70 disk<misc<ramlib; pri60 keyboard<gameport; pri40 audio<input; pri20 console<trackdisk.
- **[D] C4**: the `InitCode(RTF_SINGLETASK,0)` pass initialises no module (empty list);
  nor does the `InitCode(RTF_AFTERDOS,…)` pass. Observable: nothing must initialise "before
  multitasking" or "after DOS" via the flags mechanism.

## D. Auto-init tables (all **[M]**, hard oracles)

- **[M] D1** `dataSize` (allocated base size): expansion `0x1C8` (456) · ramlib `0x0B2` (178)
  · audio `0x27A` (634) · intuition `0x564` (1380) · mathffp `0x022` (34 = sizeof struct Library).
- **[M] D2** number of LVO vectors exposed: expansion **25** · ramlib **11** · audio **6**
  · intuition **78** · mathffp **16**.
- **[M] D3** encoding of the `vectors` table: expansion & intuition = **absolute LONG** (terminator
  `0xFFFFFFFF`); ramlib, audio, mathffp = **relative WORD** (1st word `0xFFFF`, terminator `0xFFFF`).
- **[M] D4** `structure` (InitStruct data): NULL **only** for intuition; present for
  the other 4.
- **[M] D5** audio.device exposes exactly 6 LVOs = the 4 standard ones (Open/Close/Expunge/reserved)
  + 2 device-specific ones (BeginIO/AbortIO). mathffp exposes 16 LVOs = 4 standard + 12
  single-precision math functions.

## E. ExecBase after init (runtime) **[D unless indicated]**

- **[D] E1**: `*(ULONG*)$00000004` points to `ExecBase` (value not predictable but non-zero,
  in chip RAM < `MaxLocMem`).
- **[D] E2**: `ExecBase.ChkBase` (+0x26) = `~(*(ULONG*)4)` (ones' complement of the base pointer).
- **[D] E3**: `ExecBase.LibNode.lib_Version` (+0x14) = **34**; `lib_Revision` (+0x16) = 2;
  `LN_Type` (+0x08) = `NT_LIBRARY` (9); `LN_Name` → `"exec.library"`.
- **[D] E4**: `AttnFlags` (+0x128) = **0x0000** on a pure 68000 (no 68010/020/030/040/
  68881/882 bit set). On a higher CPU, the corresponding bits are set.
- **[D] E5**: `VBlankFrequency` (+0x212) = **50** in PAL (60 in NTSC);
  `PowerSupplyFrequency` (+0x213) = **50** PAL / 60 NTSC.
- **[D] E6**: `MaxLocMem` (+0x3E) = top of chip RAM = **0x00080000** for 512 KB chip
  (0x00200000 if 2 MB chip).
- **[D] E7**: all of ExecBase's system lists are valid `struct List`s (empty right
  after init, then populated): `MemList`, `ResourceList`, `DeviceList`, `IntrList`, `LibList`,
  `PortList`, `TaskReady`, `TaskWait`, `SemaphoreList`. An empty `List` satisfies
  `lh_Head == &lh_Tail && lh_TailPred == &lh_Head` (self-referencing header).
- **[D] E8**: `ResModules` (+0x12C) ≠ NULL and enumerates the 24 residents in the order of C1.
- **[D] E9**: `IDNestCnt`/`TDNestCnt` (+0x126/+0x127) return to **-1** when idle (no
  Disable/Forbid active; convention: -1 = "outside a critical section").
- **[D] E10**: the area beyond `KickCheckSum` (~0x22E) is not an ExecBase field in V34
  (see exec-spec.md §2). A 1.3 implementation must assume nothing there.

## F. Memory list (A500 512 KB chip, no expansion) **[D]**

- **[D] F1**: `MemList` contains **exactly one** `MemHeader` (chip RAM). No fast node.
- **[D] F2**: this `MemHeader` has `mh_Attributes = MEMF_CHIP|MEMF_PUBLIC` (= **0x3**) in V34
  (the `MEMF_LOCAL` 0x100 and `MEMF_24BITDMA` 0x200 bits are **V36** additions, absent in 1.3);
  `mh_Upper` ≈ `0x00080000`; `mh_Lower` above the reserved low area (CPU vectors +
  ExecBase + stacks). `LN_Type = NT_MEMORY (10)`.
- **[D] F3**: `AvailMem(MEMF_CHIP)` > 0; `AvailMem(MEMF_FAST)` = 0 (no fast RAM).
- **[D] F4**: allocation granularity = **8 bytes** (AllocMem rounds up).

## G. Exec jump table **[M + D]**

- **[M] G1**: the LVO offsets of the primitives are used in the ROM with the canonical values:
  Forbid -132, Permit -138, AllocMem -198, FreeMem -210, AddHead -240, AddTail -246, Remove -252,
  FindName -276 (call sites listed in exec-spec.md §3).
- **[M] G2**: the deepest `JSR/JMP d16(A6)` offset in the whole ROM is **-636**; the use
  of exec LVOs is dense and contiguous down to ~ -588.
- **[D] G3**: the exec V34 jump table has ~**102** entries (`lib_NegSize` ≈ 612), i.e. far
  fewer than 2.0/3.x. LVOs ≥ -618 (AddMemList/CopyMem/CopyMemQuick/Cache*/pools…) **must not
  exist** in a V34 reimplementation.
- **[D] G4**: each jump table entry = 6 bytes (`JMP abs.l` `0x4EF9` + 32-bit address);
  `lib_Sum`/`SumLibrary` recomputes a consistent checksum of the table.

## H. Limits / areas to be confirmed by the implementation track
- Section E (runtime ExecBase) and F (memory list) are **[D]**: not readable in the static
  ROM. To be validated on an emulator/real hardware against an authentic Kickstart 1.3.
- G3: exec LVO count to within ±1 on the last entry; cross-check `exec_lib.fd` **V34** to settle it.
- E6/F2: `MaxLocMem` and `mh_Upper` depend on the actual amount of chip RAM of the tested config.

## Clean-room review

Review of 2026-10-29.

- [x] No instruction sequence transcribed, no pseudo-code: only black-box
  assertions (values, orders, sizes).
- [x] **Fixed**: removed the ROM addresses of the reset PC (A2), of exec's `rt_Init`/`rt_EndSkip`
  (B5) and of the three priority-0 ROMTags (C1), as well as the reference to the tags' "offsets"; the
  assertions are kept in relative form (equality reset PC = `rt_Init`, order of position).
- [x] Remaining: header `0x11114EF9`, version `0x00220005`, size `0x00040000` (image format checked
  by `romtool`), public ExecBase offsets, LVOs, `MEMF_*`/`NT_*`/`RTF_*` constants. G2 cites the addressing
  mode of the LVO calls only to bound the jump table (no instruction copied).
