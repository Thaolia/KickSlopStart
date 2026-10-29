# Zorro II Autoconfig of 1.3 (expansion.library 34.1) — behavioural spec

ANALYSIS track. Source: ROM `kick34005.A500` (34.5) — black-box probes under FS-UAE 3.2.35 + reading
of the ROM limited to the cases the probes do not cover. No instruction sequence is transcribed:
we describe the **what** (order, values, conditions, ABI layout), never the **how**.

Source legend: **[S]** = observed by black-box probe (vectors §8); **[R]** = established by ROM
analysis (behaviour only); **[S+R]** = both agree; **[D]** = public docs (RKRM/NDK).

---

## 0. ABI structures used (reminder, V34 offsets)

`struct ExpansionBase` (size 456 = `0x1C8`, = dataSize of the resident) **[R, agrees with NDK 1.3]**:

| Off. | Field | Observed role |
|---:|---|---|
| `$00` | `eb_LibNode` (34) | |
| `$22` | `eb_Flags` (UBYTE) | bit 0 `EBB_CLOGGED`, bit 1 `EBB_SHORTMEM` (cf. §3, §2.6) |
| `$24` | `eb_ExecBase` | |
| `$28` | `eb_SegList` | |
| `$2C` | `eb_CurrentBinding` (16 bytes) | Get/SetCurrentBinding |
| `$3C` | `eb_BoardList` (List) | list of ConfigDevs |
| `$4A` | `eb_MountList` (List) | AddDosNode BootNodes (autoboot) |
| `$58` | `eb_AllocTable[256]` | 1 byte per 64 KB "slot" of the 24-bit space; **≠0 = free, 0 = taken/unavailable** |
| `$158` | `eb_BindSemaphore` (46) | Obtain/ReleaseConfigBinding |
| `$186` | `eb_Int2List`, `$19C` `eb_Int6List`, `$1B2` `eb_Int7List` (Interrupt ×3) | not used by the autoconfig |

`struct ConfigDev` (size 68 = `0x44`): `cd_Node` `$00`, `cd_Flags` `$0E` (bit 0 `CDF_SHUTUP`, bit 1
`CDF_CONFIGME`), `cd_Pad` `$0F`, `cd_Rom` `$10` (ExpansionRom, 16 bytes), `cd_BoardAddr` `$20`,
`cd_BoardSize` `$24`, `cd_SlotAddr` `$28` (UWORD), `cd_SlotSize` `$2A` (UWORD), `cd_Driver` `$2C`,
`cd_NextCD` `$30`, `cd_Unused[4]` `$34`.

`struct ExpansionRom` (in `cd_Rom`, relative offsets): `er_Type` 0, `er_Product` 1, `er_Flags` 2,
`er_Reserved03` 3, `er_Manufacturer` 4 (UWORD), `er_SerialNumber` 6 (ULONG), `er_InitDiagVec` 10 (UWORD),
`er_Reserved0c..0f` 12 (4 bytes).

Error codes (numeric values returned): `0` OK, `41` (`EE_NOEXPANSION`, no more space), `42`
(`EE_NOMEMORY`, also returned for "no board / invalid ROM").

---

## 1. WHEN the autoconfig happens

1. **In the init of the expansion.library resident** (`RTF_AUTOINIT|RTF_COLDSTART`, pri **110**, 1st module of the
   `InitCode(RTF_COLDSTART)` pass after exec — cf. `module-map.md`, `boot-sequence.md`). **[R]**
   Nobody else triggers the configuration of the chain: it is the library's init function
   (called by `MakeLibrary` via `InitResident`) that, in order:
   1. stores ExecBase (`eb_ExecBase`) and the seglist;
   2. initialises `eb_BindSemaphore` (InitSemaphore);
   3. declares free the slots of the **memory space**: `FreeExpansionMem(0x20, 0x80)` → slots `$20..$9F`
      = `$200000..$9FFFFF`;
   4. declares free the slots of the **I/O space**: `FreeExpansionMem(0xE9, 7)` → slots `$E9..$EF`
      = `$E90000..$EFFFFF` (slot `$E8`, the configuration address, is **never** free);
   5. initialises (NewList) `eb_BoardList` and `eb_MountList`;
   6. calls `ConfigChain($E80000)`;
   7. returns the base.
   All the other slots (`$00..$1F` chip/reserved, `$A0..$E8`, `$F0..$FF`) remain at 0 = unavailable
   (the base is allocated zeroed by MakeLibrary).
2. **After** the memory has been set up by exec (chip + slow RAM `$C00000`, ExecBase already placed):
   the Zorro II fast RAM is added **during** the expansion init, hence **before** all the other COLDSTART
   residents (graphics, devices, etc.) which may already allocate in it. **[S+R]** (without slow RAM, the fast RAM
   receives the MEMF_PUBLIC allocations of the following residents: `mh_Free` < size, cf. vector `f8noslow`.)
3. 1.3 **does not move** ExecBase nor the supervisor stack into fast RAM (ExecBase stays in slow RAM
   `$C00xxx` or in chip). **[S]**

---

## 2. Protocol applied by 1.3

### 2.1 Register access (ReadExpansionByte / WriteExpansionByte)
- A "logical byte" of index `n` occupies two physical registers: **high** nibble at `board + 4n`, **low**
  nibble at `board + 4n + 2` (in both cases it is the **high nibble** of the byte read that carries the data).
  `ReadExpansionByte(board, n)` = `(read(board+4n) & $F0) | (read(board+4n+2) >> 4)`, **without inversion**.
  **[R]**
- `WriteExpansionByte(board, n, v)` writes `v<<4` at `board+4n+2` (low nibble) **then** `v` at `board+4n`
  (high nibble **last**, because it is the write of the high nibble of register `$48` that makes a Zorro II
  board take the address). Returns 0. **[R]**

### 2.2 Reading the ExpansionRom (ReadExpansionRom)
- Reads **17** logical bytes (index 0 to 16): index 0 (`er_Type`, registers `$00/$02`) is taken **as
  is**; indices 1..16 are **inverted** (one's complement). They are stored starting at `cd_Rom`, so the
  17th (index 16 = registers `$40/$42`, inverted) **overflows into the high-order byte of `cd_BoardAddr`**.
  **[R]**, visible consequence **[S]**: a board put to sleep keeps `cd_BoardAddr = $FF000000` (cf. §2.6).
- Validation (otherwise return **42** = "no board") **[R]**:
  - `er_Flags & $3F` must be 0 (only bits 7 `ERFF_MEMSPACE` and 6 `ERFF_NOSHUTUP` are allowed);
  - `er_Reserved03` must be 0;
  - `er_Manufacturer` ≠ `$0000` and ≠ `$FFFF`.
  An empty bus (reads all at 1 or all at 0) therefore fails naturally → **end of chain**.
- Debounce: then re-reads the ROM **11 times** and compares each time the first 16 bytes
  (`cd_Rom`); a single difference → return 42. Otherwise return 0. **[R]**
- The type bits `er_Type & $C0` (Zorro II = `$C0`) and the "chained" bit (`$08`) **are not
  checked**: only the size (`er_Type & 7`) and bits `$20`/`$10` are used. **[R]**

### 2.3 Size (er_Type & 7) → number of 64 KB slots and search start **[R, sizes S]**

| code | size | slots | start of the general search |
|:-:|---|:-:|:-:|
| 0 | 8 MB | `$80` | `$20` |
| 1 | 64 KB | `$01` | `$00` |
| 2 | 128 KB | `$02` | `$00` |
| 3 | 256 KB | `$04` | `$00` |
| 4 | 512 KB | `$08` | `$00` |
| 5 | 1 MB | `$10` | `$00` |
| 6 | 2 MB | `$20` | `$00` |
| 7 | 4 MB | `$40` | `$20` |

### 2.4 ConfigBoard(board, configDev) — observable sequence **[R; results S]**
1. If `eb_Flags.CLOGGED` is already set: does nothing (immediate return, d0 not meaningful).
2. `slot = AllocBoardMem(er_Type & 7)` (§3).
3. **Success** (`slot ≠ -1`): `cd_Flags |= CDF_CONFIGME`; `cd_SlotAddr = slot`; `cd_BoardAddr = slot<<16`;
   `cd_SlotSize = nb_slots`; `cd_BoardSize = nb_slots<<16`; then `WriteExpansionByte(board, $12, slot)`
   (register `$48/$4A` = bits A23..A16) → the board takes its address and hands over to the next one.
   Then **post-configuration**:
   - if `er_Type & $20` (`ERTF_MEMLIST`): addition of the memory (§4);
   - **otherwise** if `er_Type & $10` (`ERTF_DIAGVALID`): DiagArea handling (§6);
   - (a memory board with DIAGVALID therefore does **not** have its DiagArea executed.)
   - return **0**.
4. **Failure, "shut-up-able" board** (`er_Flags` bit 6 `NOSHUTUP` at 0): `WriteExpansionByte(board, $13, 0)`
   (register `$4C/$4E` = shut-up); `cd_Flags |= CDF_SHUTUP`; `eb_Flags |= EBB_SHORTMEM`; return **41**.
   `cd_SlotAddr/SlotSize/BoardSize` stay at 0, `cd_BoardAddr` keeps the §2.2 artefact.
5. **Failure, NOSHUTUP board**: `eb_Flags |= EBB_CLOGGED`; the board receives as address its own
   configuration slot (`$E8`, i.e. it stays at `$E80000` and clogs the chain); the ConfigDev fields are
   filled as in point 3 but with `slot = -1` (`cd_SlotAddr = $FFFF`, `cd_BoardAddr = $FFFF0000`),
   `CDF_CONFIGME` **not** set; the post-configuration (point 3) is still executed; return 0.
   **[R only — not probed]** (pathological case; reproducing it as is is only of interest for fidelity).

### 2.5 ConfigChain(baseAddr) **[R; results S]**
Loop:
1. if `eb_Flags.CLOGGED` → exit, return 0;
2. `cd = AllocConfigDev()`; if NULL → return **42**;
3. `ReadExpansionRom(baseAddr, cd)` ≠ 0 → `FreeConfigDev(cd)`, exit, return **0** (normal end of chain);
4. `r = ConfigBoard(baseAddr, cd)`; if `r == 0` or `r == 41` → `AddConfigDev(cd)` and start again;
   otherwise `FreeConfigDev(cd)`, exit, return 0.
Consequences: boards put to sleep (41) **appear** in the list; the order of the list = physical order
of the chain. **[S]**

### 2.6 End of chain / non-configurable boards
- No board → invalid ROM → end (§2.2). **[R]**
- Board that no longer fits → shut-up + ConfigDev added with `cd_Flags = $01`, `cd_BoardAddr = $FF000000`
  (on UAE: inverted 17th byte = `$FF`), sizes/slots 0; **the chain continues** (the sleeping board
  hands over). **[S]** (vectors `d8_1`, `d4_8`).

---

## 3. Address allocation (AllocBoardMem / AllocExpansionMem) **[S+R]**

- The space is managed by `eb_AllocTable`: 256 slots of 64 KB; free at the start: `$20..$9F`
  (`$200000..$9FFFFF`, 8 MB) and `$E9..$EF` (`$E90000..$EFFFFF`, 448 KB). **[R]**
- Search for a block of `n` slots:
  1. **if `n ≤ 7`** (64, 128 or 256 KB): first in `[$E8, $F0)`, candidates `$E8, $E8+n, $E8+2n…`;
     `$E8` being always taken: 64 KB → `$E9`, 128 KB → `$EA`, 256 KB → `$EC`. **This also applies to
     memory boards**: a 256 KB RAM board ends up at `$EC0000` and its RAM is added there. **[S]**
  2. otherwise (or if the I/O is full): in `[start, $100)` (start from the §2.3 table), candidates
     `start + k·n`. Since `$00..$1F` are taken, this amounts to: **natural alignment on the size** for
     512 KB..2 MB (first free multiple ≥ `$200000`); for **4 MB** candidates `$200000` then `$600000`
     (4 MB alignment **relative to `$200000`**); for **8 MB** only `$200000`.
  3. a candidate is only retained if its `n` slots are all free; they are then marked taken (0). The
     first suitable candidate wins (first fit, increasing order). Nothing is reserved as a hole:
     a 1 MB block placed at `$200000` followed by a 4 MB board puts the latter at `$600000`, leaving
     `$300000..$5FFFFF` free for later boards of ≤ 2 MB. **[S]** (`d1_4`)
- **Space full**: AllocBoardMem returns -1 → board put to sleep (§2.4.4), `EBB_SHORTMEM`. **[S+R]**
- Order: that of the physical chain; no sorting by size (a small board first may waste
  the alignment of the next one). **[S]**
- `er_Flags.MEMSPACE` does **not** influence placement in 1.3; only the number of slots decides. **[R]**

---

## 4. Memory boards (`ERTF_MEMLIST`) **[S+R]**

- Addition by exec `AddMemList(size = cd_BoardSize, attributes = MEMF_PUBLIC|MEMF_FAST ($0005), pri = 0,
  base = cd_BoardAddr, name = "expansion ram")` (exact string, lower case). **[R]**, result **[S]**:
  - the MemHeader is placed **at the start of the board**: `mh_Lower = base + $20` (32 bytes = sizeof MemHeader),
    `mh_Upper = base + size` (first byte **after** the board), `mh_Free = size − $20`;
  - `ln_Type = NT_MEMORY ($0A)`, `ln_Pri = 0`, `mh_Attributes = $0005`, name `"expansion ram"`.
  - One MemHeader **per board** (two contiguous boards are not merged). **[S]** (`d2_1`)
- Position in `ExecBase->MemList` (Enqueue by priority, FIFO at equal priority) **[S]**:
  1. slow RAM `$C00000` (`"Fast Memory"`, attr `$0005`, pri 0) — added by exec before;
  2. the `"expansion ram"` boards (pri 0) in configuration order;
  3. chip (`"Chip Memory"`, attr `$0003`, pri −10).
  Without slow RAM: expansion ram then chip. Consequence: in the presence of slow RAM, allocations without
  constraint go **first into slow RAM**, not fast (e.g. the DiagArea copy, vector `hd2048`).
- The RAM is not tested (no memory test / no `EE_BADMEM` observed). **[R]**

---

## 5. ConfigDev **[S+R]**

- Allocated by `AllocConfigDev` = `AllocMem(68, MEMF_PUBLIC|MEMF_CLEAR)`: everything not cited is 0
  (`ln_Type = 0`, `ln_Name = NULL`, `cd_Driver = 0`, `cd_NextCD = 0`). **[S+R]**
- Configured board: `cd_Flags = $02` (CONFIGME), `cd_Rom` = ROM read (type not inverted, the rest inverted),
  `cd_BoardAddr = slot<<16`, `cd_BoardSize = n<<16`, `cd_SlotAddr = slot`, `cd_SlotSize = n` (unit = 64 KB,
  e.g. `$0020/$0020` for 2 MB at `$200000`, `$00E9/$0001` for 64 KB at `$E90000`). **[S]**
- Sleeping board: `cd_Flags = $01`, `cd_BoardAddr = $FF000000` (artefact), the rest 0. **[S]**
- `cd_Driver` is **not** filled by expansion (it is BindDrivers that does it and clears CONFIGME). The
  pointer to the RAM copy of the DiagArea is stored in **`cd_Rom.er_Reserved0c`** (ULONG at `cd+$1C`).
  **[S+R+D]**
- List: `AddConfigDev` = AddTail on `eb_BoardList` under Forbid → order of the chain; ConfigDevs
  added later by drivers (e.g. UAE adds its own at `$F00000`) come after. **[S+R]**
- `FindConfigDev(old, manuf, prod)`: starts from the first node if `old == NULL`, otherwise from the one after `old`;
  `manuf == -1` (long) = wildcard, otherwise comparison on the word `er_Manufacturer`; `prod == -1` = wildcard, otherwise
  comparison on the byte `er_Product`; returns the first matching ConfigDev or 0. No Forbid.
  **[R; S for the -1/-1 walk]**

---

## 6. DiagArea (`er_InitDiagVec`) **[R; execution proven S]**

1.3 **executes** the DiagArea, **during ConfigBoard**, hence during the init of expansion.library (before all
the other COLDSTART residents: no graphics, no dos, no devices; only exec and expansion).
Condition: board configured successfully, **without** `ERTF_MEMLIST`, with `ERTF_DIAGVALID` ($10).

1. If `er_InitDiagVec == 0` → nothing.
2. DiagArea in ROM = `cd_BoardAddr + er_InitDiagVec` (**configured** address). Its 1st byte `da_Config`
   must satisfy `(da_Config & $30) == $10` (`DAC_CONFIGTIME`) otherwise nothing (BINDTIME alone = ignored).
3. Bus width `da_Config & $C0`: `$00` NIBBLEWIDE (bytes rebuilt from the high nibbles of the
   bytes at +0 and +2, stride 4), `$40` BYTEWIDE (one byte out of two, stride 2), `$80` WORDWIDE (contiguous
   copy via CopyMem), `$C0` → nothing.
4. Copy of the header (14 bytes: `da_Config, da_Flags, da_Size(W), da_DiagPoint(W), da_BootPoint(W),
   da_Name(W), da_Reserved01(W), da_Reserved02(W)`); if `da_Size == 0` → nothing.
5. `AllocMem(da_Size, 0)` (no attribute: first MemHeader, hence slow RAM if present); failure → nothing.
6. Copy of `da_Size` bytes of the DiagArea (same width) into this buffer; **`er_Reserved0c` ← buffer**.
   No relocation: it is up to the diag code to fix itself up (cf. RKRM).
7. If `da_DiagPoint ≠ 0`: call of `buffer + da_DiagPoint` with **A0 = cd_BoardAddr, A2 = buffer (DiagArea
   copy), A3 = ConfigDev, A6 = ExecBase**, and (undocumented) **A5 = ExpansionBase**. D0 return:
   ≠ 0 = success (everything is kept); **0 = failure** → `FreeMem(buffer, da_Size)` and `er_Reserved0c = 0`.
   If `da_DiagPoint == 0`, the buffer is kept without a call.
8. `da_BootPoint` is not called here (that is the business of strap/romboot via `er_Reserved0c` and
   `eb_MountList`, outside this spec).

Minimum so as not to break a controller: copy faithfully (width), store the pointer in
`er_Reserved0c`, call DiagPoint with A0/A2/A3/A6 (A5 as a bonus), respect the return code, and provide
`MakeDosNode`/`AddDosNode`/`eb_MountList` usable at that moment (dos.library absent). Vector `hd2048`:
the UAE card (DiagArea, `InitDiagVec=$2000`) gets its copy at `$00C01AE0` (slow RAM), its DiagPoint
runs (it adds a ConfigDev itself at `$F00000`) and DH0: is mounted at boot. **[S]**

---

## 7. expansion.library V34 LVOs (25 vectors, bias 30, absolute LONG table format) **[R; D for the names]**

| LVO | Function (regs) | Observable 34.1 behaviour |
|---:|---|---|
| −30 | `AddConfigDev(cd)(a0)` | Forbid, AddTail(eb_BoardList), Permit. |
| −36 | *(private, "expansionUnused" in the .fd)* `(size d0, attr d1, base a0)` | AddMemList(d0, d1, pri 0, a0, "expansion ram"). Not used by the autoconfig (which calls exec directly). |
| −42 | `AllocBoardMem(slotSpec)(d0)` | `AllocExpansionMem(n, start)` according to the §2.3 table (spec & 7); returns the slot or −1. |
| −48 | `AllocConfigDev()()` | AllocMem(68, PUBLIC|CLEAR). |
| −54 | `AllocExpansionMem(numSlots, slotAlign)(d0/d1)` | −1 if `numSlots+slotAlign > 256`. If `numSlots ≤ 7`, attempt in I/O `[$E8,$F0)` stride `numSlots`. Then search in `[slotAlign, $100)` stride `numSlots` (**`slotAlign` = start slot**, not an alignment). Marks taken, returns the slot or −1. |
| −60 | `ConfigBoard(board, cd)(a0/a1)` | §2.4. Return 0 / 41. |
| −66 | `ConfigChain(baseAddr)(a0)` | §2.5. Return 0 (or 42 if no more memory for a ConfigDev). |
| −72 | `FindConfigDev(old, manuf, prod)(a0,d0/d1)` | §5. |
| −78 | `FreeBoardMem(startSlot, slotSpec)(d0/d1)` | `FreeExpansionMem(startSlot, n(spec))`. |
| −84 | `FreeConfigDev(cd)(a0)` | FreeMem(cd, 68). |
| −90 | `FreeExpansionMem(startSlot, numSlots)(d0/d1)` | Marks free (≠0). If `start+num > 256`, or if a slot is **already free**: `Alert($0A000001)` (AN_BadExpansionFree, recoverable) and stop (the previous slots remain freed). |
| −96 | `ReadExpansionByte(board, offset)(a0,d0)` | §2.1, without inversion; returns the byte. |
| −102 | `ReadExpansionRom(board, cd)(a0/a1)` | §2.2; 0 = OK, 42 = absent/invalid/unstable. |
| −108 | `RemConfigDev(cd)(a0)` | Forbid, Remove, Permit. |
| −114 | `WriteExpansionByte(board, offset, byte)(a0,d0/d1)` | §2.1; returns 0. |
| −120 | `ObtainConfigBinding()()` | ObtainSemaphore(eb_BindSemaphore). |
| −126 | `ReleaseConfigBinding()()` | ReleaseSemaphore(eb_BindSemaphore). |
| −132 | `SetCurrentBinding(binding, size)(a0,d0)` | Copies `min(size,16)` bytes into `eb_CurrentBinding`, pads to 16 with 0. |
| −138 | `GetCurrentBinding(binding, size)(a0,d0)` | Copies `min(size,16)` bytes **to** the buffer then writes 0 up to 16 bytes **in the buffer** (overflows if `size < 16`); always returns **16**. |
| −144 | `MakeDosNode(parmPacket)(a0)` | AllocEntry of 5 PUBLIC|CLEAR blocks: DeviceNode (44), FileSysStartupMsg (16), environment `(de_TableSize+1)*4`, BSTR DOS name, BSTR exec name; copies the environment; `dn_StackSize = 600`, `dn_Priority = 10`; returns the DeviceNode or 0. |
| −150 | `AddDosNode(bootPri, flags, dosNode)(d0/d1/a0)` | NULL → 0. If dos.library opens: addition path on the DOS side (not detailed here, cf. §9). Otherwise 20-byte BootNode (AllocMem without CLEAR: `ln_Type` not initialised): `ln_Pri = bootPri`, `bn_Flags = flags`, `bn_DeviceNode = dosNode`, `ln_Name` = C name of the DeviceNode, Enqueue into `eb_MountList`; returns 1 (0 if no more memory). |

Called at boot by expansion itself: FreeExpansionMem, ConfigChain → AllocConfigDev,
ReadExpansionRom (→ ReadExpansionByte), ConfigBoard (→ AllocBoardMem → AllocExpansionMem,
WriteExpansionByte), AddConfigDev, FreeConfigDev; exec AddMemList / AllocMem / CopyMem / FreeMem.

---

## 8. Test vectors (real ROM 34.5, FS-UAE 3.2.35, A500 512 KB chip)

Probe: `tests/cfgdev2.s` (extended variant of `tests/cfgdev.s`), launched by `cfgdev2 >SER:` from the
startup-sequence of a copy of the Workbench 1.3.3 ADF. Format:
`CD BoardAddr BoardSize Flags.Type.Product.ErFlags Manufacturer SlotAddr.SlotSize InitDiagVec er_Reserved0c cd_Driver ln_Type<<16|cd_Pad`
then `MH Lower Upper Attr<<16|ln_Type<<8|Pri Free Name`. Base FS-UAE config + indicated lines
(`uae_fastmem2_size` = 2nd Zorro II board, in MB; `uae_fastmem_size_k` in KB). The `mh_Free` values of
slow/chip depend on the state of the boot and are not normative. In the abbreviated blocks, the slow MH lines
(`00C004E8 00C7E800 00050A00`) and chip MH lines (`00000420 00080000 00030AF6`) are identical to `none`.

```
=== none  (slow_memory = 512)
MH 00C004E8 00C7E800 00050A00 00073580 Fast Memory
MH 00000420 00080000 00030AF6 0006FED8 Chip Memory
=== nofast_noslow  (slow_memory = 0)
MH 000008E8 0007E800 00030AF6 00063478 Chip Memory
=== k64  (slow 512, uae_fastmem_size_k = 64)
CD 00E90000 00010000 02E15180 000007DB 00E90001 00000000 00000000 00000000 00000000
MH 00C004E8 00C7E800 00050A00 00073520 Fast Memory
MH 00E90020 00EA0000 00050A00 0000FFE0 expansion ram
MH 00000420 00080000 00030AF6 0006FED8 Chip Memory
=== k128  (uae_fastmem_size_k = 128)
CD 00EA0000 00020000 02E25180 000007DB 00EA0002 00000000 00000000 00000000 00000000
MH 00EA0020 00EC0000 00050A00 0001FFE0 expansion ram
=== k256  (uae_fastmem_size_k = 256)
CD 00EC0000 00040000 02E35180 000007DB 00EC0004 00000000 00000000 00000000 00000000
MH 00EC0020 00F00000 00050A00 0003FFE0 expansion ram
=== k512  (uae_fastmem_size_k = 512)
CD 00200000 00080000 02E45180 000007DB 00200008 00000000 00000000 00000000 00000000
MH 00200020 00280000 00050A00 0007FFE0 expansion ram
=== f1024  (fast_memory = 1024)
CD 00200000 00100000 02E55180 000007DB 00200010 00000000 00000000 00000000 00000000
MH 00200020 00300000 00050A00 000FFFE0 expansion ram
=== f2048  (fast_memory = 2048)
CD 00200000 00200000 02E65180 000007DB 00200020 00000000 00000000 00000000 00000000
MH 00C004E8 00C7E800 00050A00 00073520 Fast Memory
MH 00200020 00400000 00050A00 001FFFE0 expansion ram
MH 00000420 00080000 00030AF6 0006FED8 Chip Memory
=== f4096
CD 00200000 00400000 02E75180 000007DB 00200040 00000000 00000000 00000000 00000000
MH 00200020 00600000 00050A00 003FFFE0 expansion ram
=== f8192
CD 00200000 00800000 02E05180 000007DB 00200080 00000000 00000000 00000000 00000000
MH 00C004E8 00C7E800 00050A00 00073538 Fast Memory
MH 00200020 00A00000 00050A00 007FFFE0 expansion ram
MH 00000420 00080000 00030AF6 0006FED8 Chip Memory
=== f8noslow  (slow_memory = 0, fast_memory = 8192)
CD 00200000 00800000 02E05180 000007DB 00200080 00000000 00000000 00000000 00000000
MH 00200020 00A00000 00050A00 007F5580 expansion ram
MH 000008E8 0007E800 00030AF6 0006DE90 Chip Memory
=== d2_1  (fast 2048 + 2nd board 1 MB)
CD 00200000 00200000 02E65180 000007DB 00200020 00000000 00000000 00000000 00000000
CD 00400000 00100000 02E55180 000007DB 00400010 00000000 00000000 00000000 00000000
MH 00C004E8 00C7E800 00050A00 000734F0 Fast Memory
MH 00200020 00400000 00050A00 001FFFE0 expansion ram
MH 00400020 00500000 00050A00 000FFFE0 expansion ram
MH 00000420 00080000 00030AF6 0006FED8 Chip Memory
=== d1_4  (fast 1024 + 2nd board 4 MB)
CD 00200000 00100000 02E55180 000007DB 00200010 00000000 00000000 00000000 00000000
CD 00600000 00400000 02E75180 000007DB 00600040 00000000 00000000 00000000 00000000
MH 00C004E8 00C7E800 00050A00 000734F0 Fast Memory
MH 00200020 00300000 00050A00 000FFFE0 expansion ram
MH 00600020 00A00000 00050A00 003FFFE0 expansion ram
MH 00000420 00080000 00030AF6 0006FED8 Chip Memory
=== d8_1  (fast 8192 + 2nd board 1 MB: no more room)
CD 00200000 00800000 02E05180 000007DB 00200080 00000000 00000000 00000000 00000000
CD FF000000 00000000 01E55180 000007DB 00000000 00000000 00000000 00000000 00000000
MH 00C004E8 00C7E800 00050A00 000734D8 Fast Memory
MH 00200020 00A00000 00050A00 007FFFE0 expansion ram
MH 00000420 00080000 00030AF6 0006FED8 Chip Memory
=== d4_8  (fast 4096 + 2nd board 8 MB: no more room)
CD 00200000 00400000 02E75180 000007DB 00200040 00000000 00000000 00000000 00000000
CD FF000000 00000000 01E05180 000007DB 00000000 00000000 00000000 00000000 00000000
MH 00200020 00600000 00050A00 003FFFE0 expansion ram
=== hd2048  (fast 2048 + hard_drive_0 = host directory → UAE card with DiagArea)
CD 00200000 00200000 02E65180 000007DB 00200020 00000000 00000000 00000000 00000000
CD 00E90000 00010000 02D15240 000007DB 00E90001 00002000 00C01AE0 00000000 00000000
CD 00F00000 00010000 00010400 000007DB 00000000 00000000 00000000 00000000 00000000
MH 00C004E8 00C7E800 00050A00 00070DF0 Fast Memory
MH 00200020 00400000 00050A00 001FFFE0 expansion ram
MH 00000420 00080000 00030AF6 000721D8 Chip Memory
(+ "info": DH0: mounted, volume hddir — DiagPoint/BootPoint of the UAE card executed.)
```

Reading of the vectors: `er_Type` `$E0..$E7` = Zorro II + MEMLIST + size code; `$D1` = Zorro II +
DIAGVALID + 64 KB; `er_Flags` `$80` (MEMSPACE) for the UAE RAM, `$40` (NOSHUTUP) for the UAE disk card.
The 3rd CD line of `hd2048` (at `$F00000`, flags 0, `er_Type $10`) is a ConfigDev **added by the UAE
diag code** via AddConfigDev, not by the autoconfig: a correct implementation must see it appear
too (proof that DiagPoint ran).

Proposed non-regression tests for our ROM: each block above must be reproduced
identically for the CD lines and for Lower/Upper/Attr/name of the MHs (the Free field of slow/chip excepted).

---

## 9. Not probed / uncertain

- **NOSHUTUP board without room (CLOGGED)**: behaviour §2.4.5 read in the ROM only; not probed.
- **I/O board without DiagArea** and **BYTEWIDE/NIBBLEWIDE boards**: not probed (the UAE card is the only
  DiagArea board simply available; its width was not recorded). Copy rules = ROM.
- **DiagPoint returning 0** (freeing of the buffer, `er_Reserved0c = 0`): ROM only.
- **Read instability** (11 re-reads) and invalid ROM (low er_Flags ≠ 0, manufacturer 0/$FFFF): ROM.
- Value of the `cd_BoardAddr` artefact of a sleeping board: `$FF000000` on UAE; on real hardware
  it depends on what the board presents at `$40/$42` (inverted) — not verified.
- Final `eb_Flags` (SHORTMEM after `d8_1`): not read by probe (ROM only).
- 64–256 KB board when the I/O `$E9..$EF` is full: fallback to the memory space according to the ROM, not probed.
- WinUAE not used: FS-UAE was enough for two boards (`uae_fastmem2_size`); Zorro III ignored (outside A500).
- The "dos.library present" path of AddDosNode and the detail of MakeDosNode are only summarised in broad
  strokes (outside the autoconfig proper).

## Clean-room review

Review of 2026-10-29.

- [x] No 68000 instruction sequence transcribed, no disassembly excerpt, no ROM
  routine address: all the addresses cited are those of the Zorro II space (`$E80000`, `$200000..$9FFFFF`,
  `$E90000..$EFFFFF`), of the slow RAM (`$C00000`), of the UAE card (`$F00000`) or of the configuration
  registers (`$40`/`$48`/`$4C`).
- [x] §1, §2.4, §2.5 and §6 enumerate steps at the level of the **public calls** (expansion/exec
  LVOs) and their results; this is the observable order of the Autoconfig protocol, not a
  code walk-through. The §8 vectors are probe outputs (author code `tests/cfgdev2.s`).
- [x] No ROM data beyond the ABI: `ExpansionBase`/`ConfigDev`/`ExpansionRom` layout, error
  codes, Zorro II size tables (public), MemHeader name `"expansion ram"`, `dn_StackSize`/`dn_Priority`
  values of MakeDosNode.
