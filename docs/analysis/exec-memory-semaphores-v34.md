# exec.library 34.2 — memory and signal semaphores: behavioural spec

> **ANALYSIS** track ("dirty"), `coverage-v34.md` §7 rank 13. Source: **black-box calls on the real ROM**
> `assets/kick34005.A500` under Amiberry (A500 preset, cycle-exact, 512 KB chip + 512 KB slow RAM, no disk),
> 2026-11-05, sessions `r13a`–`r13h`.
> Method (same as `exec-rawdofmt-v34.md`): the ROM was left at its "insert disk" picture; the debugger stopped the
> `input.device` task at the entry of exec `Wait` (user mode), raised the interrupt mask to 7 for the duration of the
> experiment, allocated a 16 KB work block with an injected `AllocMem`, and then called each function **through its
> library vector** (`ExecBase − LVO`) with a return address pointing at a debugger breakpoint, a private stack in the
> work block, and marker values `$1111000n` in every register not used as an argument. Memory headers, chunk lists,
> semaphore fields and task signal bits were read back after each call. Nested calls were observed with debugger
> breakpoints on the **vector entries** of `AllocMem`, `FreeMem`, `Wait`, `Signal` and `Alert` (arguments read
> there; for `Alert` the call was abandoned at its entry, so no dead-end alert was ever displayed). Forbid/Disable
> use was observed with a write watch on `IDNestCnt`/`TDNestCnt`. Contention was produced with **fake task
> structures** (zeroed `struct Task`, `NT_TASK`, state `TS_WAIT`, `tc_SigWait = 0`, so that a `Signal` only sets
> `tc_SigRecvd`) set as semaphore owners or waiters, and by **faking the return of `Wait`** at its entry. Interrupts
> and the saved task state were restored afterwards. The ROM code was **not** read, disassembled or traced for
> this page. No program was written; the probe to write on the implementation side is described in §10.
> This document describes **behaviours**, **values**, **register contracts** and **test vectors**. It contains no
> ROM instruction sequence, no pseudo-code of any routine and no ROM address.
> Related pages: `exec-spec.md` §4 (MEMF bits, AllocMem/FreeMem summary), `dos-memory-v34.md` (dos allocation
> inventory; AllocEntry leak), `exec-scheduling-v34.md` §2.7 (RemTask/FreeEntry), §6 (Procure/Vacate), §7
> (SumKickData + KickMem AllocAbs), `setpatch-138.md` §1.4 (SetPatch's AllocEntry), `ramlib-v34.md` §6 (AllocMem
> patch), `layers-v34.md` §7 (semaphore lists), `autoconfig-v34.md` §4 (AddMemList), `softkick-real-ks13.md`
> (TypeOfMem).
>
> **Levels of proof**: **[O]** observed on the real ROM · **[D]** deduced from observations (reasoning, stated) ·
> **[S]** assumption, not verified.
>
> Notation: sizes in bytes, decimal unless `$`. "R" is the 8-aligned base of a private test region managed by a
> hand-built MemHeader; "F0" the first free chunk of a system header; offsets are written `R+n`. Test ids refer to
> §9.

## 0. Summary for the implementer

- **Granularity**: every allocator works in **8-byte units**. Sizes round **up** to 8; `Deallocate`/`FreeMem` and
  `AllocAbs` round the **start down** and the **end up** to 8. Rounding is 32-bit and wraps: a size of
  `$FFFFFFF9`–`$FFFFFFFF` rounds to 0 (§2.1). [O]
- **Size 0**: `Allocate`/`AllocMem` return 0; `Deallocate`/`FreeMem` do nothing (no check of the address at all,
  even NULL). [O]
- **Allocation policy**: headers in `MemList` order (priority order), first header whose `mh_Attributes` contain
  **all** requested bits of the low word; inside it **first fit from the lowest address**, carved **from the start
  of the chunk**. Bits in the upper word (`MEMF_CLEAR`, `MEMF_LARGEST`, `$40000`, `$80000`, bit 31) do not take part
  in the match. [O]
- **MEMF_CLEAR** clears the **rounded** size. Without it, the block's first 8 bytes hold the old chunk header
  (next pointer, size). [O]
- **AvailMem**: sum of `mh_Free` over matching headers; with `MEMF_LARGEST` the largest single chunk among them.
  **No `MEMF_TOTAL` in V34**: `$80000` is ignored (same result as without it). [O]
- **Bad frees are dead-end alerts**: an address in no memory header → `Alert($81000005)`; a block overlapping a free
  chunk → `Alert($81000009)` (both from FreeMem, the latter also from Deallocate). [O]
- **AllocAbs** rounds the start down to 8; returns that rounded address, or 0 when the rounded range is not
  entirely inside one free chunk. **Size 0 succeeds** and splits the chunk into two adjacent chunks that are not
  merged again. [O]
- **TypeOfMem**: `mh_Attributes` of the header with `mh_Lower ≤ addr < mh_Upper`, else 0; the MemHeader itself
  (below `mh_Lower`) gives 0; allocation state is irrelevant. [O]
- **AllocEntry**: MemList copy allocated with `MEMF_CLEAR` only (16 + 8n bytes); node fields zeroed, entries
  allocated in order through the **AllocMem vector**; on failure the entries already obtained are freed but **the
  new MemList is not** (leak of 16 + 8n rounded), and D0 = **`me_Reqs` of the failing entry | `$80000000`**
  (`$80010000` when the MemList itself cannot be had). `ml_NumEntries = 0` is broken: one entry is processed anyway
  and written past the 16-byte block (§2.8). [O]
- **FreeEntry**: `FreeMem` (vector) on each entry with a non-zero length, in order, then `FreeMem(list, 16 + 8n)`. [O]
- **AddMemList** (exists in V34, LVO −618): MemHeader written **at the base of the region**, `mh_Lower = base + 32`
  rounded up to 8, `mh_Upper = base + size` rounded down to 8, one chunk, `Enqueue` by priority. [O]
- **CopyMem** copies any size at any alignment, no overrun; overlap works only when the destination is **below**
  the source. **CopyMemQuick** copies `size & ~3` bytes (the low 2 bits of the size are ignored); word-aligned
  pointers work on a 68000. [O]
- **Semaphores** (§4): `InitSemaphore` sets only `ss_NestCount = 0`, `ss_QueueCount = −1`, `ss_Owner = 0` and the
  wait queue. Obtain/Attempt increment both counts; a contested Obtain queues a 12-byte request **on the caller's
  stack** at the **tail**, keeps **Forbid**, and calls `Wait(SIGF_SEMAPHORE = $10)` **once**; ownership is **handed
  over by the releaser** (owner := head waiter, `ss_NestCount := 0`, `Signal(waiter, $10)`), and the woken task then
  increments `ss_NestCount` **without re-checking**. Release does not check the caller; releasing a free semaphore
  is `Alert($81000008)`. [O]
- **AddSemaphore is broken in V34**: it initialises the semaphore at **A0** (not A1) and links the address A0+16
  into `SemaphoreList` (§4.7). FindSemaphore and RemSemaphore work. [O]

## 1. Structures (public ABI, confirmed by the observations)

| Structure | Size | Fields used by V34 [O] |
|---|---|---|
| `MemHeader` | 32 | Node (`ln_Type` 10 = NT_MEMORY, `ln_Pri`, `ln_Name`), `mh_Attributes` +14 (word), `mh_First` +16, `mh_Lower` +20, `mh_Upper` +24 (first byte **after** the region), `mh_Free` +28 |
| `MemChunk` | 8 | `mc_Next` +0, `mc_Bytes` +4; chunks kept in **ascending address order**, never adjacent after a normal free (merged) |
| `MemList` | 16 + 8n | Node (14), `ml_NumEntries` +14 (word), entries at +16: `me_Reqs`/`me_Addr` (+0), `me_Length` (+4) |
| `SignalSemaphore` | 46 | Node (14), `ss_NestCount` +14 (word), `ss_WaitQueue` +16 (MinList, 12), `ss_MultipleLink` +28 (SemaphoreRequest, 12), `ss_Owner` +40, `ss_QueueCount` +44 (word) |
| `SemaphoreRequest` | 12 | MinNode (8), `sr_Waiter` +8 (task) |
| old `Semaphore` (Procure/Vacate) | 36 | `MsgPort` (34) + `sm_Bids` +34 (word); `sm_LockMsg` = `mp_SigTask` (+16) |

System headers at the insert-disk screen (512 KB chip + 512 KB slow) [O]: first header named "Fast Memory",
pri 0, attributes `$0005` (PUBLIC|FAST), covering the slow RAM (ExecBase itself lies in that slow RAM, below the
header's `mh_Lower`); second header "Chip Memory", pri −10, attributes `$0003` (PUBLIC|CHIP), MemHeader at `$400`,
`mh_Lower = $420`, `mh_Upper = $80000`. Each had a single free chunk. The AllocMem vector pointed into the ROM at
that point (no ramlib patch yet, `ramlib-v34.md` §6), so every figure here is exec's own.

## 2. Memory functions

### 2.1 Rounding [O]

- Size: `(size + 7) & ~7`, in 32 bits. Hence 1→8, 7→8, 8→8, 9→16, 15→16, 17→24 (vectors M1–M8).
- The **zero test is made before rounding**: size 0 fails/does nothing, but sizes `$FFFFFFF9`–`$FFFFFFFF` round to
  0 and are treated as a **successful zero-byte request**: `Allocate`/`AllocMem` return the address of the first
  fitting chunk (the lowest chunk of the first matching header) **without consuming anything**, and the matching
  `FreeMem` gives nothing back (M10, A11). `$FFFFFFF8` and every size larger than the largest chunk fail (M11–M14).
  [O] The same request with `MEMF_CLEAR` was **not tried** (it might clear a huge or a null range) [S].
- `Deallocate`/`FreeMem`: start = `addr & ~7`, end = `(addr + size + 7) & ~7`; the freed size is end − start
  (`R+4`,8 frees 16 bytes at R; `R+2`,16 frees 24; `R+5`,3 frees 8). Size 0 returns at once (D7). [O]
- `AllocAbs`: same start/end rounding as a free; the value returned is the **rounded-down** start (L2, L3). [O]

### 2.2 Allocate (−186) `Allocate(memHeader A0, byteSize D0) → D0` [O]

- Walks `mh_First` in address order and takes the **first chunk whose size ≥ rounded size**, from its **start**:
  the chunk shrinks from below (new chunk header written at chunk + size), or is unlinked when the fit is exact.
  `mh_Free` is decreased by the rounded size. No clearing.
- Fails (D0 = 0, nothing changed) when no single chunk is large enough, even if `mh_Free` is (A6), or when the size
  is 0 (A4).
- **No Forbid, no Disable** (the caller provides the exclusion). No check of `ln_Type`, nothing outside the header
  and its chunks is touched.
- Registers: D0 = result; **A1** = the block on success, or the last chunk examined on a failure after a walk
  (unchanged for size 0). D1, A0 and D2–D7/A2–A6 preserved.

### 2.3 Deallocate (−192) `Deallocate(memHeader A0, memoryBlock A1, byteSize D0)` [O]

- Rounds as §2.1, inserts the block in address order, **merges** with the previous chunk when it ends exactly at
  the block and with the next chunk when it starts exactly at the block end (D1–D6); `mh_Free` += rounded size.
  Works on an empty chunk list (D8).
- **Overlap with a free chunk is a dead-end alert `$81000009`**, raised through `Alert` with D7 = `$81000009`:
  a block equal to, inside, or straddling the end of a free chunk is refused **before** any change; a block that
  begins before a free chunk and runs into it is detected only **after** it has been linked into the chunk list
  (the list then holds an overlapping chunk; `mh_Free` not yet updated) (V1–V5). The alert never returns in normal
  operation, so the half-done state does not matter.
- **No range check**: Deallocate does not compare the block with `mh_Lower`/`mh_Upper` (a block outside the header
  was linked in order like any other: D6, "after last") [O for blocks above the last chunk; S for blocks below
  `mh_Lower`].
- No Forbid, no Disable. Registers: D0 = rounded size when it differs from the input, D1 and A1 changed (pointers
  into the chunk list); A0, D2–D7, A2–A6 preserved.

### 2.4 AllocMem (−198) `AllocMem(byteSize D0, requirements D1) → D0` [O]

- `Forbid` … `Permit` around the whole call (TDNestCnt −1 → 0 → −1); no Disable.
- Header choice: headers are tried in `MemList` order; a header matches when **every bit of the low word** of the
  requirements is present in `mh_Attributes`. Requirements 0 and 1 → the fast header; 2, 3, `$10002`, `$20002` →
  chip; 4, 5 → fast; 6, 7, 8, `$100`, `$200`, `$400` → **0** (no header has them); `$10000`, `$20000`, `$40000`,
  `$80000`, `$80000000` → fast (upper-word bits ignored for the match) (F1–F19).
- Inside a header: `Allocate` semantics (§2.2); when the matching header has no fitting chunk the next matching
  header is tried (a request that the fast header could not satisfy was served from chip). [O]
- `MEMF_CLEAR` (`$10000`): the **rounded** size is cleared (13 bytes asked → 16 cleared; the following chunk header
  intact) (C2, C3). Without it, the first 8 bytes of the block are the former free-chunk header (next pointer, then
  chunk size) and the rest is whatever was there (C1).
- Size 0 → 0 after visiting every header (A0 = the last header). Failure → 0, nothing changed, **no alert**.
- Registers: D0 = result; A0 = the header used (or the last one tried); A1 = the block (unchanged on failure);
  **D1 preserved**; D2–D7, A2–A6 preserved.
- **Condition codes on return** [O, 2026-11-11, booted system (dos running, no SetPatch), breakpoint on the
  vector in RAM, then on the caller's return address]: Z reflects D0 = 0 in every sample: three successes
  (sizes 1 and `$10001` requirements, D0 = block) returned with Z and N clear, one failure (requirements 8, D0 = 0)
  with Z set; X was set in all four, N clear. A caller may branch on Z straight after the call [D]; N was not
  seen set (no negative result is possible below 16 MB).

### 2.5 FreeMem (−210) `FreeMem(memoryBlock A1, byteSize D0)` [O]

- Size 0 → returns at once, **whatever A1** (NULL included) (G2, G7).
- Otherwise `Forbid`; finds the header with `mh_Lower ≤ A1 < mh_Upper`; none → **`Alert($81000005)`**
  (AN_MemCorrupt, dead-end): seen for NULL, a ROM address and an unmapped address (G1, G3, G4). Then `Deallocate`
  semantics (§2.3) in that header: freeing a free area → **`Alert($81000009)`** (G5, G6). `Permit`.
- Registers: D0 = rounded size (when different), D1 = address of the header's `mh_First` field, A0 = the header;
  **A1 preserved**; D2–D7, A2–A6 preserved.

### 2.6 AvailMem (−216) `AvailMem(requirements D1) → D0` [O]

- Same header match as AllocMem (low word all present). Result = **sum of `mh_Free`** of the matching headers;
  with `MEMF_LARGEST` (`$20000`) = **size of the largest chunk** among them.
- `$80000` (`MEMF_TOTAL` in V36+) is **not** recognised: `AvailMem($80000)` = `AvailMem(0)` = free sum (here
  959 272), `$80002` = chip free, `$A0000` = largest chunk. `MEMF_CLEAR` is ignored. Requirements nobody has (6, 8,
  `$100`) → 0 (V-vectors T1–T17).
- `Forbid`/`Permit`. Registers: D0 = result; A1 changed (end-of-list pointer); with `MEMF_LARGEST` also A0 (last
  chunk looked at); D1 preserved.

### 2.7 AllocAbs (−204) `AllocAbs(byteSize D0, location A1) → D0` [O]

- `Forbid`/`Permit`. Rounds start down and end up (§2.1), finds the header containing the start, then the free chunk
  that contains the **whole** rounded range; carves it out (the chunk is split in two, or shortened at either end,
  or removed when the range is the whole chunk). Returns the **rounded start** (L1–L3, L5, L11).
- Returns 0, nothing changed, when the range is not entirely inside one free chunk: in an allocated area, straddling
  the start or end of a free chunk, larger than the chunk, or outside every header (L6–L9, L12). No alert.
- **Size 0** (end = start) **succeeds** when the address is inside a free chunk: the chunk is split at that address
  into two **adjacent chunks**, which are **not merged** afterwards by other allocations (they are merged only when
  a free lands next to them); `mh_Free` unchanged (L10). [O]
- Works on any header (chip and fast seen). Registers: D0 = result; A0, A1 changed; D1 preserved.
- Known use: reserving the KickMem entries at reset (`exec-scheduling-v34.md` §7) and SetPatch's ColdCapture stub
  (`setpatch-138.md`).

### 2.8 AllocEntry (−222) `AllocEntry(memList A0) → D0` [O]

1. Allocates the new MemList: `AllocMem(16 + 8 × ml_NumEntries, MEMF_CLEAR)` through the **library vector**
   (requirements exactly `$10000`, so it lands in the first header with room: fast/slow RAM here). The node fields
   stay **zero** (the source node is not copied); `ml_NumEntries` is copied.
2. For each entry in order: `me_Length` is copied **unchanged** (50 stays 50, not rounded); when it is 0 the
   address is 0 and **no AllocMem is made**; otherwise `me_Addr := AllocMem(me_Length, me_Reqs)` through the
   vector, with `me_Reqs` passed as the full 32-bit value.
3. Success: D0 = the new MemList; the source list is never written (E1–E3).
4. **Failure of entry k**: the entries already obtained are freed with `FreeMem` (vector) — seen in order of
   allocation for one entry — and D0 = **`me_Reqs[k] | $80000000`** (`$80010004` for `$10004`, `$80000008` for 8,
   `$80000006` for 6). **The new MemList is not freed**: 16 + 8n bytes (rounded) stay allocated for ever (E4–E6).
   This is the 24-byte leak per failed process creation of `dos-memory-v34.md` §0 item 8.
5. **Failure of the MemList allocation itself** (n = 60 300, 482 416 bytes): D0 = **`$80010000`** (bit 31 |
   `MEMF_CLEAR`), no entry processed, nothing written, no leak (E7).
6. **`ml_NumEntries = 0`**: a 16-byte list is allocated, but **one entry is still processed**: the entry following
   the source header is read and written at list + 16, i.e. **8 bytes past the end of the block**. In two runs this
   overwrote the header of the free chunk that followed (its size field took the copied `me_Length`, its next
   pointer 0), cutting the rest of the header's chunk list off while `mh_Free` stayed unchanged; the length was
   copied **before** the entry's AllocMem, which then carved from the damaged chunk (E8). Nobody can rely on this;
   see §7.
- Registers: D0 = result; D1, A0, A1 changed; D2–D7, A2–A6 preserved. Forbid comes only from the nested AllocMem
  calls [D].
- SetPatch 1.38 replaces this function on exec ≤ 35 with one that frees the list too (`setpatch-138.md` §1.4).

### 2.9 FreeEntry (−228) `FreeEntry(memList A0)` [O]

- For each entry in order, `FreeMem(me_Addr, me_Length)` through the vector, **skipped when `me_Length` = 0**
  (address ignored then); an entry with address 0 and length 8 calls `FreeMem(0, 8)` → `Alert($81000005)` (H3, H4).
- Then `FreeMem(list, 16 + 8 × ml_NumEntries)` — the size is **recomputed**, not taken from anywhere else (a list
  block allocated larger than that leaks the difference) (H5).
- `ml_NumEntries = 0`: only the list (16 bytes) is freed (H2).
- Registers: D0, D1, A0, A1 changed. Used by `RemTask` on every `tc_MemEntry` node (`exec-scheduling-v34.md` §2.7).

### 2.10 TypeOfMem (−534) `TypeOfMem(address A1) → D0` [O]

- `Forbid`/`Permit`. Returns `mh_Attributes` (zero-extended word) of the first header with
  `mh_Lower ≤ A1 < mh_Upper`, else 0. Free or allocated does not matter.
- Boundaries (chip header at `$400`, Lower `$420`, Upper `$80000`): `$41F` → 0, `$420` → 3, `$7FFFF` → 3,
  `$80000` → 0; the MemHeader's own bytes → 0; ROM, custom chips, unmapped → 0 (Y1–Y19).
- Registers: D0 = result; A0 = the header found, or the list's tail address when none; others preserved.

### 2.11 AddMemList (−618) `AddMemList(size D0, attributes D1, pri D2, base A0, name A1)` [O]

- Exists in V34 (the exec vector table has 105 entries, down to −630).
- Writes the MemHeader **at `base`**: `ln_Type` 10, `ln_Pri` = low byte of D2, `ln_Name` = A1 (pointer stored, not
  copied), `mh_Attributes` = low word of D1, `mh_Lower` = `(base + 32 + 7) & ~7`, `mh_Upper` = `(base + size) & ~7`,
  `mh_First` = `mh_Lower`, `mh_Free` = Upper − Lower, one chunk covering it (K1, K4, K5).
- `Forbid`, **Enqueue** into `ExecBase->MemList` by priority (after the headers of equal priority), `Permit` (K1–K3).
  The new memory is immediately used by AllocMem/AvailMem/TypeOfMem.
- No validation of anything; no result. Registers: D0, D1, A0, A1 changed; D2–D7, A2–A6 preserved.
- Users: expansion.library for memory boards (`autoconfig-v34.md` §4: size = board size, `$0005`, pri 0,
  "expansion ram").

## 3. CopyMem (−624) and CopyMemQuick (−630) [O]

`CopyMem(source A0, dest A1, size D0)`, `CopyMemQuick(source A0, dest A1, size D0)`; no result.

- **CopyMem**: exact copy for every size 0–1000 tried, with source and destination offsets 0/1/2 in every
  combination (odd addresses included); **never writes outside** `[dest, dest + size)` (guard bytes intact). Size 0
  writes nothing.
- **CopyMemQuick**: copies **`size & ~3`** bytes: sizes 1–3 copy nothing, 5–7 copy 4 (the tail bytes are left
  untouched). Long-aligned and **word-aligned** pointers (offsets 2) both work on the 68000; odd pointers were not
  tried (they would raise an address error on a 68000) [S].
- **Overlap**: both copy in ascending order. Destination **below** the source gives the memmove result for every
  case tried (offsets 1, 4, 8, 16, 64; sizes 16–256). Destination **above** the source gives **corrupted** data
  (repeated bytes, or a block-wise pattern that depends on size and alignment): undefined, callers must not do it.
- Registers: D0, D1, A0, A1 changed (A0/A1 end just past the copied ranges, D0 holds loop residue); D2–D7, A2–A6
  preserved. Forbid/Disable not traced [S: none].

## 4. Signal semaphores

### 4.1 InitSemaphore (−558) `InitSemaphore(sigSem A0)` [O]

Writes only: `ss_NestCount := 0`, `ss_WaitQueue` initialised as an empty list (head → &tail, tail 0, tailpred →
&head), `ss_Owner := 0`, `ss_QueueCount := −1`. The node (`ln_Succ`/`ln_Pred`/`ln_Type`/`ln_Pri`/`ln_Name`) and
`ss_MultipleLink` are **not touched** (pattern `$AB` kept). No Forbid. Registers: **A1 = sigSem + 16** (address of
`ss_WaitQueue`); everything else preserved (S1).

### 4.2 ObtainSemaphore (−564) `ObtainSemaphore(sigSem A0)` [O]

- `Forbid`; `ss_QueueCount += 1`.
- Free (count became 0) or **already owned by ThisTask**: `ss_Owner := ThisTask`, `ss_NestCount += 1`; `Permit`
  (S2, S3).
- **Owned by another task**: a 12-byte `SemaphoreRequest` {MinNode, `sr_Waiter` = ThisTask} is built **on the
  caller's stack** and **AddTail**ed to `ss_WaitQueue`; the `SIGF_SEMAPHORE` bit (`$10`) of ThisTask is
  **cleared** first (a bit set before the call was gone at Wait time); then `Wait($10)` is called **once**, still
  under Forbid (TDNestCnt 0 at the Wait entry; Wait's own per-task nest handling applies,
  `exec-scheduling-v34.md` §2.4). `ss_NestCount` and `ss_Owner` are not touched before waiting (C1, C3).
- **After Wait returns**, it does **not** re-check the owner: `ss_NestCount += 1` and return (`Permit`). A wake-up
  without a hand-off (Wait faked to return `$10`, owner still the other task) left `ss_NestCount = 2` with the
  other task as owner (C2). Correctness therefore rests on the releaser's hand-off (§4.4).
- Stack: the Wait call was entered 36 bytes below the caller's SP (return addresses included).
- Registers: **all preserved** (D0–D7, A0–A6), contested or not.

### 4.3 AttemptSemaphore (−576) `AttemptSemaphore(sigSem A0) → D0` [O]

- `Forbid`. Free or owned by ThisTask → same as Obtain (both counts +1, owner = ThisTask), **D0 = 1**. Owned by
  another task (with or without waiters) → **D0 = 0**, `ss_QueueCount` and everything else **unchanged** (S4–S6,
  C7). `Permit`.
- Registers: D0 = result, **A1 = ThisTask**; others preserved.

### 4.4 ReleaseSemaphore (−570) `ReleaseSemaphore(sigSem A0)` [O]

- `ss_NestCount −= 1`, `ss_QueueCount −= 1`. **No owner check**: a release by a non-owner task works exactly like a
  release by the owner (C6).
- Nest count still > 0: nothing else (owner kept, waiters not woken), **no Forbid** (S7, C5).
- Nest count reached 0, under `Forbid`:
  - `ss_QueueCount` < 0 (no waiter): `ss_Owner := 0` (S8).
  - waiters present: the **head** request is removed from `ss_WaitQueue`, `ss_Owner := sr_Waiter` of that request,
    `ss_NestCount` stays **0**, and `Signal(sr_Waiter, SIGF_SEMAPHORE = $10)`; the other waiters stay queued and
    `ss_QueueCount` keeps counting them (C4: one waiter → owner = waiter, counts 0/0; two waiters → only the first
    signalled, QueueCount 1). The same happens when the head request is an `ss_MultipleLink` of
    `ObtainSemaphoreList` (C8).
- **Release of a free semaphore** (`ss_NestCount` 0, `ss_QueueCount` −1) → **`Alert($81000008)`** (dead-end) (S9).
- Registers: all preserved in every case observed.

### 4.5 ObtainSemaphoreList (−582) `ObtainSemaphoreList(list A0)` [O]

`list` is a `List` whose nodes are the semaphores' `ss_Link` nodes (layers: `LayerInfo.gs_Head`).

- Phase 1, in list order (head → tail): free or own semaphores are taken at once (counts +1, owner = ThisTask);
  for one owned by another task, `ss_QueueCount += 1` and the semaphore's **own `ss_MultipleLink`** request is
  filled {`sr_Waiter` = ThisTask} and AddTailed to its wait queue (the MultipleLink node is in the semaphore, not on
  the stack) (L-vectors Q1–Q3).
- Phase 2, again in list order, for every semaphore queued in phase 1: while `ss_Owner` ≠ ThisTask, `Wait($10)`;
  then `ss_NestCount += 1`. So, unlike ObtainSemaphore, **it re-checks the owner** after each wake-up: a spurious
  wake-up waits again (Q5); a hand-off of a later semaphore first leaves it at NestCount 0 until the earlier ones are
  obtained (Q4); hand-offs of all pending semaphores before the first wake → returns after one Wait (Q6).
- Forbid held throughout (TDNestCnt 0 at the Wait entries); Wait entered 20 bytes below the caller's SP.
- Two tasks calling it on the same list in the same order cannot deadlock against each other; a task holding one
  member through plain ObtainSemaphore can (`layers-v34.md` open point 9) [D].
- Registers: D1, A1 changed (D0, A0 too when it waited); D2–D7, A2–A6 preserved.

### 4.6 ReleaseSemaphoreList (−588) `ReleaseSemaphoreList(list A0)` [O]

`ReleaseSemaphore` on every node, in list order (one level each: a list obtained twice needs two releases) (Q7, Q8).
Registers: A0 changed; others preserved.

### 4.7 AddSemaphore (−600), FindSemaphore (−594), RemSemaphore (−606) [O]

- **AddSemaphore is unusable in V34.** Called with the semaphore in A1 (the `.fd` register), it does
  `InitSemaphore` on **A0** and then `Forbid` + `Enqueue(&SemaphoreList, A0 + 16)`, A0 + 16 being the address
  InitSemaphore leaves in A1 (the semaphore's `ss_WaitQueue`):
  - with A0 = garbage (A1 = the semaphore): the semaphore is untouched and a garbage address is linked into
    `ExecBase->SemaphoreList`; a later `FindSemaphore` loops for ever on it (seen, session lost) (N1);
  - with A0 = A1 = the semaphore: the semaphore is initialised, but its **wait-queue header** is what gets linked:
    the list links overwrite `ss_WaitQueue`, the priority used is a byte of the wait queue, and FindSemaphore would
    compare the wrong name (N2).
- **FindSemaphore(name A1) → D0**: walks `SemaphoreList` from the head, case-sensitive full-string compare of
  `ln_Name`; D0 = semaphore or 0. **No Forbid** (caller must Forbid). Registers: D0, D1, A0 changed (N3–N5).
- **RemSemaphore(sigSem A1)**: `Forbid`, `Remove`, `Permit` (the node's own succ/pred are left as they were).
  A0 is ignored (N6, N7). Registers: A0, A1 changed.
- `SemaphoreList` is empty after boot on this configuration. No 1.3 user of AddSemaphore is known (§8).

### 4.8 Procure (−540) / Vacate (−546) [O]

The [S] description and vectors of `exec-scheduling-v34.md` §6 were run and hold: with `sm_Bids` = −1 and the port
`PA_IGNORE`, Procure(m1) → D0 = 1, `sm_LockMsg` = m1, Bids 0; Procure(m2) → 0, Bids 1, m2 queued on the port;
Vacate → m2 replied to its reply port (type `NT_REPLYMSG` 7), `sm_LockMsg` = m2, Bids 0; Vacate → `sm_LockMsg` 0,
Bids −1 (P1–P4). Registers: Procure changes D0 only; Vacate D0, D1, A0, A1. These structures share nothing with
`SignalSemaphore` beyond the name.

## 5. Register and exclusion table [O]

| Function | Changed (besides documented result) | Preserved | Forbid / Disable |
|---|---|---|---|
| Allocate | D0, A1 | D1, A0, D2–D7, A2–A6 | none / none |
| Deallocate | D0, D1, A1 | A0, D2–D7, A2–A6 | none / none |
| AllocMem | D0, A0, A1 | D1, D2–D7, A2–A6 | Forbid / none |
| FreeMem | D0, D1, A0 | A1, D2–D7, A2–A6 | Forbid / none (size 0: none) |
| AvailMem | D0, A1 (+A0 with LARGEST) | D1, D2–D7, A2–A6 | Forbid / none |
| AllocAbs | D0, A0, A1 | D1, D2–D7, A2–A6 | Forbid / none |
| AllocEntry, FreeEntry | D0, D1, A0, A1 | D2–D7, A2–A6 | through AllocMem/FreeMem |
| TypeOfMem | D0, A0 | D1, A1, D2–D7, A2–A6 | Forbid / none |
| AddMemList | D0, D1, A0, A1 | D2–D7, A2–A6 | Forbid / none |
| CopyMem, CopyMemQuick | D0, D1, A0, A1 | D2–D7, A2–A6 | not traced |
| InitSemaphore | A1 | all others | none |
| ObtainSemaphore | — | all | Forbid (kept across Wait) |
| AttemptSemaphore | D0, A1 | others | Forbid |
| ReleaseSemaphore | — | all | Forbid only on the last level |
| ObtainSemaphoreList | D1, A1 (D0, A0 after a wait) | D2–D7, A2–A6 | Forbid |
| ReleaseSemaphoreList | A0 | others | per ReleaseSemaphore |
| FindSemaphore | D0, D1, A0 | others | **none** |
| RemSemaphore | A0, A1 | others | Forbid |
| Procure / Vacate | D0 / D0, D1, A0, A1 | others | not traced |

No function used Disable. A6 = ExecBase was always passed; no test with another A6 was made.

## 6. Alerts raised [O]

| Situation | Alert (D7) |
|---|---|
| FreeMem of an address outside every MemHeader (NULL, ROM, unmapped) with size ≠ 0; FreeEntry entry with address 0 and length ≠ 0 | `$81000005` |
| FreeMem/Deallocate of a block overlapping a free chunk (double free, inside a free chunk, straddling) | `$81000009` |
| ReleaseSemaphore on a free semaphore | `$81000008` |

All three have bit 31 set (dead-end). Not seen: any alert from AllocMem, AllocAbs, AllocEntry failures, Attempt,
Obtain.

## 7. Differences from the usual descriptions [O vs. public documentation]

1. `MEMF_TOTAL` does not exist (V36); `AvailMem($80000)` is the free sum. `MEMF_LARGEST` works.
2. Upper-word requirement bits never prevent a match; unknown **low-word** bits make AllocMem fail.
3. Sizes `$FFFFFFF9`–`$FFFFFFFF` wrap to 0 and "succeed" without allocating (AllocMem, Allocate).
4. AllocAbs with size 0 succeeds and fragments the chunk; AllocAbs returns the rounded-down address.
5. AllocEntry leaks its MemList on an entry failure and returns `me_Reqs | $80000000`; with `ml_NumEntries = 0` it
   writes past its block. FreeEntry skips zero-length entries.
6. Deallocate has no range check; overlap is a dead-end alert, not a silent error.
7. CopyMemQuick ignores the low 2 bits of the size; CopyMem/CopyMemQuick are not overlap-safe upwards.
8. ObtainSemaphore does not re-check ownership after its single Wait; ObtainSemaphoreList does.
9. ReleaseSemaphore does not check the caller; it hands ownership to the head waiter itself.
10. AddSemaphore is broken (A0/A1 mix-up); FindSemaphore takes no Forbid.
11. AddMemList, CopyMem and CopyMemQuick exist in V34 (not V36 additions).

**Implementation choices left to the clean side** [D]: the broken cases (5's zero-entry overrun, 10's
AddSemaphore, 3's wrap-around) cannot be relied upon by any working 1.3 program; a working behaviour (AllocEntry
with 0 entries processing none, AddSemaphore = InitSemaphore(A1) + Enqueue(A1)) is the safer target. The AllocEntry
**result codes** and **leak**, the alerts, the hand-off protocol and the register contracts are observable by
programs and should be matched (SetPatch tests only the exec version and replaces AllocEntry anyway).

## 8. Known users [D]

| User | Calls | Vectors that matter |
|---|---|---|
| dos createproc / CreateProc (`dos-memory-v34.md` §2) | AllocEntry 1 entry PUBLIC\|CLEAR; RemTask → FreeEntry | E1, E4, H1 |
| trackdisk units (`dos-memory-v34.md` §2, `trackdisk-raw-changeint-v34.md`) | AllocEntry of 3 blocks incl. CHIP | E1, E4 |
| expansion MakeDosNode (`autoconfig-v34.md`) | AllocEntry of 5 PUBLIC\|CLEAR blocks | E1 |
| SetPatch 1.38 (`setpatch-138.md` §1.4) | replaces AllocEntry (exec ≤ 35) | E4–E7 (the ROM behaviour it fixes) |
| Workbench (`workbench-task-v34.md`) | AllocEntry/FreeEntry (several blocks, one FreeEntry), AvailMem(0) for the title | E1, H1, T1 |
| coldstart KickMem (`exec-scheduling-v34.md` §7), SetPatch ColdCapture stub | AllocAbs | L1–L12 |
| soft-kick disk (`softkick-real-ks13.md`) | TypeOfMem on its image area | Y-vectors |
| expansion.library memory boards (`autoconfig-v34.md` §4) | AddMemList(size, `$0005`, 0, base, "expansion ram") | K1 |
| LoadWB (`loadwb-13.md`), OctaMED, Fast-File-System handler | CopyMem | B-vectors |
| layers.library (`layers-v34.md` §7) | Obtain/Release semaphores, ObtainSemaphoreList on `gs_Head` | S, C, Q |
| graphics (layer locks, LastChanceMemory), intuition (7 IB locks), expansion (BindSemaphore), Preferences | Init/Obtain/Release | S, C |

## 9. Test vectors

All were run on the real ROM as described in the header. Inputs not listed are the register markers. "free" =
`mh_Free`.

#### Allocate / Deallocate on a private header (R: 8-aligned, `mh_Lower` = R, `mh_Upper` = R+1024)

| # | Initial chunks | Call | Result | Chunks after (offset:size), free |
|---|---|---|---|---|
| A1 | 0:1024 | Allocate(1) | R | 8:1016, 1016 |
| A2 | 8:1016 | Allocate(8) | R+8 | 16:1008 |
| A3 | 16:1008 | Allocate(9) | R+16 | 32:992 |
| A4 | 32:992 | Allocate(0) | 0 | unchanged |
| A5 | 32:992 | Allocate(1024) | 0 | unchanged |
| A6 | 0:64, 128:64, 256:64 | Allocate(100) | 0 | unchanged (free 192) |
| A7 | same | Allocate(64), then (32), then (40) | R, R+128, R+256 | 160:32, 296:24, free 56 |
| A8 | 32:992 | Allocate(992) | R+32 | empty list, free 0 |
| A9 | 0:1024 | Allocate(1024) | R | empty, 0 |
| A10 | 0:1024 | Allocate($FFFFFFF8), ($80000000) | 0, 0 | unchanged |
| A11 | 0:1024 | Allocate($FFFFFFFF) | **R** | **unchanged** (nothing consumed) |
| D1 | 64:64, 256:64 | Deallocate(R+0, 64) | — | 0:128, 256:64, free 192 |
| D2 | same | Deallocate(R+128, 64) | — | 64:128, 256:64 |
| D3 | same | Deallocate(R+192, 64) | — | 64:64, 192:128 |
| D4 | same | Deallocate(R+128, 128) | — | 64:256, free 256 |
| D5 | same | Deallocate(R+160, 32) | — | 64:64, 160:32, 256:64 |
| D6 | same | Deallocate(R+512, 64) | — | 64:64, 256:64, 512:64 |
| D7 | 256:64 | Deallocate(R+0, 0) | — | unchanged, registers unchanged |
| D8 | (empty) | Deallocate(R+0, 8) | — | 0:8, free 8 |
| D9 | 256:64 | Deallocate(R+0,1) / (R+0,9) / (R+4,8) / (R+4,4) / (R+2,16) / (R+5,3) | — | 0:8 / 0:16 / 0:16 / 0:8 / 0:24 / 0:8 |
| V1 | 64:64, 256:64 | Deallocate(R+64, 8) | Alert $81000009 | unchanged |
| V2 | same | Deallocate(R+72, 8) | Alert $81000009 | unchanged |
| V3 | same | Deallocate(R+120, 16) | Alert $81000009 | unchanged |
| V4 | same | Deallocate(R+32, 64) | Alert $81000009 | already linked: 32:64, 64:64, 256:64 (free 128) |
| V5 | same | Deallocate(R+0, 512) | Alert $81000009 | already linked: 0:512, 64:64, 256:64 |

#### AllocMem / FreeMem / AvailMem on the system lists (fast = slow-RAM header, 482 328 free in one chunk at F0; chip 476 944 free)

| # | Call | Result |
|---|---|---|
| M1–M8 | AllocMem(1/4/7/8/9/15/16/17, 0) | F0; free −8/−8/−8/−8/−16/−16/−16/−24; FreeMem with the same size restores free exactly |
| M9 | AllocMem(0, 0) | 0, A0 = chip header |
| M10 | AllocMem($FFFFFFFF, 4) and ($FFFFFFF9, 4) | F0, free unchanged; FreeMem(F0, same size) changes nothing |
| M11–M13 | AllocMem($FFFFFFF8 / $80000000 / $7FFFFFFF, 4) | 0 |
| M14 | AllocMem(482 329, 4) / (482 328, 4) | 0 / F0 (whole chunk) |
| F1–F19 | AllocMem(16, req) | 0,1,4,5,$10000,$20000,$40000,$80000,$80000000 → fast; 2,3,$10002,$20002 → chip; 6,7,8,$100,$200,$400 → 0 |
| C1 | chunk bytes 8–63 pre-filled $A5; AllocMem(32, 0) | block = `00000000 00075C18` (old chunk header: next 0, size 482 328) then $A5… |
| C2 | same fill; AllocMem(13, $10000) | 16 bytes zero, then the new chunk header |
| C3 | same fill; AllocMem(8, $10000) | 8 bytes zero, then the chunk header |
| G1 | FreeMem(0, 8) | Alert $81000005 |
| G2 | FreeMem(0, 0) | returns, nothing changed, registers unchanged |
| G3, G4 | FreeMem(ROM address, 8), FreeMem(unmapped, 8) | Alert $81000005 |
| G5, G6 | FreeMem(F0, 8), FreeMem(F0+16, 8) (free memory) | Alert $81000009 |
| G7 | FreeMem(allocated block, 0) | returns, nothing changed |
| T1–T17 | AvailMem(0 / 1 / 2 / 3 / 4 / 5 / 6 / 8 / $100 / $10000 / $20000 / $20002 / $20004 / $80000 / $80002 / $80004 / $A0000) | 959 272 / 959 272 / 476 944 / 476 944 / 482 328 / 482 328 / 0 / 0 / 0 / 959 272 / 482 328 / 476 944 / 482 328 / 959 272 / 476 944 / 482 328 / 482 328 |

#### AllocAbs (F0 = start of the fast header's single free chunk of size FS)

| # | Call | Result | Chunks after |
|---|---|---|---|
| L1 | AllocAbs(64, F0+$100) | F0+$100 | F0:256, F0+$140:rest |
| L2 | AllocAbs(64, F0+$104) | **F0+$100** | F0:256, F0+$148:rest (72 bytes taken) |
| L3 | AllocAbs(60, F0+$103) | F0+$100 | 64 bytes taken |
| L4 | FreeMem of each of the above (64, 72, 64) | — | single chunk again |
| L5 | AllocAbs(64, F0) | F0 | F0+64:FS−64 |
| L6 | AllocAbs(FS+8, F0) | 0 | unchanged |
| L7 | AllocAbs(64, F0−32) (allocated memory below the chunk) | 0 | unchanged |
| L8 | AllocAbs(64, inside an allocated block) | 0 | unchanged |
| L9 | AllocAbs(64, ROM address) | 0 | unchanged |
| L10 | AllocAbs(0, F0+$200) | F0+$200 | **F0:512, F0+$200:FS−512** (adjacent, not merged; free unchanged) |
| L11 | AllocAbs(FS, F0); AllocAbs(64, last 64 bytes of the chunk); AllocAbs(8, inside the chip chunk) | F0; that address; that address | whole chunk taken; chunk shortened at its end; works in chip |
| L12 | AllocAbs(64, chunk end − 32) | 0 | unchanged |

#### TypeOfMem (chip header at $400: Lower $420, Upper $80000; fast header H: Lower = H+32 rounded up to 8, Upper U)

| # | Address | Result |
|---|---|---|
| Y1–Y4 | 0, $3FF, $400, $41F | 0 |
| Y5, Y6 | $420, $7FFFF | 3 |
| Y7, Y8 | $80000, $100000 | 0 |
| Y9–Y11 | slow RAM base, the fast MemHeader itself, Lower − 1 | 0 |
| Y12–Y15 | Lower, an allocated block, a free chunk, U − 1 | 5 |
| Y16–Y19 | U, beyond, ROM, custom chip register | 0 |

#### AllocEntry / FreeEntry (nested AllocMem/FreeMem calls seen at their vectors)

| # | Source list | Nested calls | Result | Leak |
|---|---|---|---|---|
| E1 | n=2: {1, 100}, {$10002, 50} | AllocMem(32,$10000), AllocMem(100,1), AllocMem(50,$10002) | new list: node zero, n=2, [blk1,100] [chip blk,50]; second block zeroed | — |
| E2 | n=2: {1, 0}, {2, 8} | AllocMem(32,$10000), AllocMem(8,2) | [0,0] [blk,8] | — |
| E3 | (any) | source list bytes after the call | identical to before | — |
| E4 | n=3: {1,64}, {$10004,$7FFFFFF0}, {2,64} | AllocMem(40,$10000), AllocMem(64,1), AllocMem($7FFFFFF0,$10004), FreeMem(blk,64) | **$80010004** | 40 (the list) |
| E5 | n=1: {8, 64} | AllocMem(24,$10000), AllocMem(64,8) | **$80000008** | 24 |
| E6 | n=2: {2,64}, {6,64} | list, AllocMem(64,2), AllocMem(64,6), FreeMem of the first | **$80000006** | 32 |
| E7 | n=60 300: {8,64} or {1,64} | AllocMem(482 416,$10000) only | **$80010000** | none; nothing written |
| E8 | n=0, followed by {1,24} | AllocMem(16,$10000), AllocMem(24,1) | list; entry written at list+16 (past the block) | free-chunk list damaged |
| H1 | E1's result | FreeMem(blk1,100), FreeMem(chip blk,50), FreeMem(list,32) | — | free restored exactly |
| H2 | n=0 list | FreeMem(list,16) | — | — |
| H3 | n=1: {addr≠0, length 0}, list in a 32-byte block | FreeMem(list,**24**) only (entry skipped; 16+8n freed whatever the block size, H5) | — | 8 (block was 32) |
| H4 | n=1: {0, 8} | FreeMem(0,8) → Alert $81000005 | — | — |

#### AddMemList (B = an AllocMem'd 4096-byte chip block, attributes `$41`, name "testmem")

| # | Call | Header at the given base | MemList order after |
|---|---|---|---|
| K1 | AddMemList($1000, $41, 5, B, name) | type 10, pri 5, name, attr $41, Lower B+32, Upper B+4096, First = Lower, free 4064, one chunk | new(5), fast(0), chip(−10) |
| K2 | pri 0 | same | fast(0), new(0), chip(−10) |
| K3 | pri −20 | same | fast, chip, new(−20) |
| K4 | AddMemList($FFC, …, 5, B+4) | Lower B+40, Upper B+4096, free 4056 | first |
| K5 | AddMemList($FF9, …, 5, B+8) | Lower B+40, Upper **B+4096** (B+4097 rounded down), free 4056 | first |
| K6 | after K1: AllocMem(16,$40), AllocMem(16,1), TypeOfMem(B+31 / B+32 / B+4095 / B+4096) | B+32, B+32, 3 / $41 / $41 / 3 | — |

#### CopyMem / CopyMemQuick (source pattern, destination pre-filled with $EE and 16 guard bytes each side)

| # | Call | Result |
|---|---|---|
| B1 | CopyMem, src/dst offsets (0,0) (1,0) (0,1) (1,1) (2,0) (0,2) (2,2), sizes 0,1,2,3,4,5,7,8,9,15,16,17,31,32,33,100,1000 | exact copy, guards intact (119 cases) |
| B2 | CopyMemQuick, offsets (0,0) (4,0) (0,4) (2,2) (2,0), sizes 0,4,8,12,16,20,100,1000 | exact |
| B3 | CopyMemQuick, same offsets, sizes 1,2,3 | nothing written |
| B4 | CopyMemQuick, sizes 5,6,7 | first 4 bytes copied only |
| B5 | overlap, dst = src − 1/−4/−8/−16/−64, sizes 16–256 (both functions where aligned) | memmove result |
| B6 | overlap, dst = src + 1/+4/+8/+64, sizes 16–256 | each byte copied from the already overwritten area (forward byte smear) |
| B7 | overlap, dst = src + 2 (16), src + 4 (100), src + 16 (100) | other corrupted patterns; undefined |

#### Signal semaphores (ME = the calling task; FT, FT2 = fake tasks)

| # | Initial state (nest, qc, owner, queue) | Call | After | Notes |
|---|---|---|---|---|
| S1 | 46 bytes of $AB | InitSemaphore | nest 0, qc −1, owner 0, queue empty; node and MultipleLink still $AB | A1 = sem+16 |
| S2 | 0, −1, 0 | Obtain | 1, 0, ME | |
| S3 | 1, 0, ME | Obtain | 2, 1, ME | |
| S4 | 2, 1, ME | Attempt | 3, 2, ME; D0 1 | A1 = ME |
| S5 | 0, −1, 0 | Attempt | 1, 0, ME; D0 1 | |
| S6 | 1, 0, FT | Attempt | unchanged; D0 0 | |
| S7 | 3, 2, ME | Release ×2 | 2, 1, ME then 1, 0, ME | no Forbid |
| S8 | 1, 0, ME | Release | 0, −1, 0 | Forbid |
| S9 | 0, −1, 0 | Release | Alert $81000008 | |
| C1 | 1, 0, FT | Obtain | at Wait($10): 1, 1, FT; queue = [request {waiter ME} on the stack] | Forbid held; SIGF_SEMAPHORE cleared before |
| C2 | as C1, Wait returns $10 with nothing changed | (continue) | 2, 1, **FT**; returns | no re-check |
| C3 | 1, 1, FT, queue [FT2] | Obtain | at Wait: queue [FT2, ME], qc 2 | AddTail |
| C4 | 1, 1, ME, queue [FT] | Release | 0, 0, **FT**, queue empty; Signal(FT, $10) | hand-off |
| C4b | 1, 2, ME, queue [FT, FT2] | Release | 0, 1, FT, queue [FT2]; only FT signalled | |
| C5 | 2, 2, ME, queue [FT] | Release | 1, 1, ME; no Signal | |
| C6 | 1, 0, FT, empty | Release (by ME) | 0, −1, 0 | no owner check |
| C7 | 1, 1, FT, queue [FT2] | Attempt | unchanged; D0 0 | |
| C8 | 1, 1, ME, queue [MultipleLink {FT}] | Release | 0, 0, FT; Signal(FT, $10) | |
| Q1 | list [S, S2, S3], all free | ObtainSemaphoreList | each 1, 0, ME | |
| Q2 | after Q1 | ObtainSemaphoreList | S: 2, 1, ME (all) | |
| Q3 | list, S2 owned by FT | ObtainSemaphoreList | at Wait($10): S 1/0/ME, S3 1/0/ME, S2 1/1/FT with its MultipleLink {ME} queued | |
| Q4 | S2, S3 owned by FT; S3 handed to ME before the first wake | (wake) | Wait again; S3 nest still 0 (owner ME) | list order |
| Q5 | S2, S3 owned by FT; spurious wake | (wake) | Wait again, nothing changed | re-check |
| Q6 | S2, S3 both handed to ME before the first wake | (wake) | returns; S2 and S3 nest 1, owner ME | one Wait |
| Q7 | after Q2 | ReleaseSemaphoreList | each 1, 0, ME | |
| Q8 | after Q7 | ReleaseSemaphoreList | each 0, −1, 0 | |
| N1 | A0 = marker, A1 = sem | AddSemaphore | sem untouched; SemaphoreList head = marker + 16 | broken |
| N2 | A0 = A1 = sem (pri 7, named) | AddSemaphore | sem initialised; SemaphoreList holds sem + 16 (pri read −64 here) | broken |
| N3 | sem linked by hand | FindSemaphore("r13sem") | sem | |
| N4, N5 | | FindSemaphore("nosuch"), ("R13SEM") | 0, 0 | case-sensitive |
| N6 | sem linked | RemSemaphore(A1 = sem) | list empty | |
| N7 | sem linked | RemSemaphore(A0 = sem, A1 = other) | sem still linked | A1 is the argument |
| P1–P4 | old Semaphore, Bids −1 | Procure m1, Procure m2, Vacate, Vacate | 1 / 0 / m2 replied / free | §4.8 |

## 10. Probe to write on the implementation side (`tests/exec_memsem_probe.s`)

A CLI program (KS 1.x hunk executable) that runs the vectors of §9 and prints one line per vector (id, results in
hex, OK/DIFF against the expected values compiled into it), so that it gives the oracle on the real ROM and the
result on ours. Output through dos `Write` with the probe's own hex routine (no RawDoFmt, no AllocMem while
printing).

1. **Private header** (A, D, V vectors): obtain a 2 KB block with AllocMem, build a MemHeader in it with a 1024-byte
   region R aligned to 8 and the chunk layouts of §9, call Allocate/Deallocate, print result offset, the chunk list
   (offset:size) and `mh_Free`. Do V1–V5 only on our ROM, or on the real ROM with `AlertData`-style protection (they
   are dead-end alerts): by default skip them and print "SKIP".
2. **System lists** (M, F, C, T): run under `Forbid()`; record `mh_Free` of each header before/after; M10 and
   AllocMem(0) included; C1–C3 by filling the first free chunk's body (after its 8-byte header) with $A5 before the
   call. G1–G6 (alerts) skipped by default.
3. **AllocAbs** (L): under Forbid, take F0 from the first header's `mh_First`; restore with FreeMem; L10 leaves two
   adjacent chunks: print the chunk list (the split stays until a neighbouring free merges it).
4. **TypeOfMem** (Y): addresses derived from the MemList (Lower, Lower−1, Upper−1, Upper, the header itself) plus
   0, ROM, `$DFF000`.
5. **AllocEntry/FreeEntry** (E, H): patch the AllocMem/FreeMem vectors with `SetFunction` to logging stubs that
   chain to the old vectors and append (D0, D1 / A1, D0) to a table, so that the nested call sequence of §9 can be
   compared; measure leaks with AvailMem(0). E8 (`ml_NumEntries = 0`) only on our ROM.
6. **AddMemList** (K): AllocMem a 4 KB chip block, AddMemList it with attributes `$41`, print the header fields
   and the MemList order, call AllocMem(16, $40) and TypeOfMem, then `Forbid`, `Remove` the header, `Permit`,
   FreeMem the block.
7. **CopyMem/Quick** (B): two 1.2 KB buffers, guards, the loops of B1–B7; print only the failing cases and a count.
8. **Semaphores** (S, C, Q): a second task created by the probe (AddTask with a small stack) acts as FT: it
   obtains a semaphore, signals the probe, waits for a signal, releases. The probe then checks the field values of
   §9 at each step (nest, qc, owner, queue length), the order in which two waiters (the probe and a third task) are
   served, `SIGF_SEMAPHORE` handling, and ObtainSemaphoreList on a 3-member list with one member held by FT. S9 is a
   dead-end alert: skip by default.
9. **Registers**: for every call, load D0–D7/A0–A5 with markers, and print the registers that changed; expected per
   §5.
10. **AddSemaphore** (N): print "SKIP on 1.3" unless a command-line flag is given (it corrupts `SemaphoreList` on
    the real ROM); FindSemaphore/RemSemaphore on a hand-linked semaphore under Forbid.

## Open points

1. AllocMem/Allocate of `$FFFFFFF9`–`$FFFFFFFF` **with `MEMF_CLEAR`**: not tried (risk of clearing all memory) [S].
2. Deallocate of a block **below `mh_Lower`** or inside the MemHeader: not tried; no range check is expected [S].
3. AllocEntry with `ml_NumEntries` ≥ 32 768 (sign of the count) and the exact order of the frees after a failure
   with several obtained entries (only one obtained entry was freed in E4/E6) [S: reverse order, as SetPatch does].
4. CopyMem/CopyMemQuick: Forbid/Disable use not traced; odd pointers to CopyMemQuick not tried.
5. ObtainSemaphore under heavy contention with real tasks: only fake tasks and faked Wait returns were used; the
   behaviour of a real woken task follows from C2/C4 [D].
6. Whether any 1.3 program calls AddSemaphore (expected none, since it cannot work).
7. ReleaseSemaphore when the head waiter is a request of a task that has since died: not tried.
8. Calls with A6 ≠ ExecBase: not tried for any function of this page.

## Clean-room review

Review of 2026-11-05.

- [x] No 68000 instruction sequence transcribed or paraphrased, no disassembly excerpt, no ROM routine or data
  address. The ROM code was not read: every fact comes from calls through the public library vectors with
  debugger-written inputs, breakpoints on public vector entries (AllocMem, FreeMem, Wait, Signal, Alert) and the
  memory, registers and structure fields read back.
- [x] The only addresses given are RAM locations that are part of the observable state (chip MemHeader at `$400`,
  its bounds) and public ABI offsets; test buffers are given relative to their bases.
- [x] The descriptions of AddSemaphore's and AllocEntry's faults are inferred from their observable effects
  (which register's object was initialised, which address was linked, which bytes were overwritten), not from the
  code.
- [x] Alert numbers, MEMF values and LVOs are public ABI values.
- [x] No probe code was written by the analysis track; §10 describes it in words only.
