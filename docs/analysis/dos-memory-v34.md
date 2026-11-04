# dos-memory-v34.md — memory management of dos.library V34 (Kickstart 1.3)

> ANALYSIS track ("dirty"). Sources: black-box runs of the real Kickstart 1.3 (`kick34005.A500`, dos 34.3)
> under Amiberry (`amiberry-session --analysis`), 2026-11-04, on session copies of
> `Workbench 1.3.3 (34.34) - Boot (Commodore) (1991) [m2].adf`:
> - a copy whose `S:Startup-Sequence` is reduced to one `echo` line (the Initial CLI then stays at its
>   prompt; nothing from the Workbench startup is loaded), with a few **modified copies of `C:Echo`** added
>   (one longword of the hunk file changed, or the file truncated: §3.6);
> - an unmodified copy, booted to the idle Workbench.
>
> Method: every call of exec `AllocMem`, `FreeMem`, `AllocEntry`, `FreeEntry` (and, on the Workbench run, of
> the dos LVOs `Open`, `Close`, `Lock`, `UnLock`, `CreateProc`) was logged by debugger breakpoints on the
> **library vectors in RAM**, with size, flags, the result, the current task's name and the free counts of the
> memory headers; then `mh_Free` of each memory header was read before/after each operation. Some runs
> **injected a failure** by making one chosen `AllocMem` request impossible (its size replaced by a huge value
> at the call), or **pre-filled** a freshly allocated block with a pattern to see what the loader writes.
> Process and CLI structures were read with the debugger. No ROM code was read for this page.
>
> Configuration of every figure below: Amiberry 8.4.2 defaults (68000, not cycle-exact), **512 KB chip +
> 512 KB slow RAM at `$C00000`** (its memory header has attributes `MEMF_PUBLIC|MEMF_FAST`, so the "fast"
> figures below are slow RAM), **no fast RAM**, drives DF0 and DF1 present (two file-system processes).
>
> **Legend**: **[O]** observed on the real ROM / WB disk · **[D]** deduced from converging observations ·
> **[S]** assumption. Sizes are in bytes unless "longs" is stated. "getvec(n)" etc. are BCPL globals of
> `bcpl-runtime-v34.md` §8.
>
> Related pages, **not repeated here**: `bcpl-runtime-v34.md` (§2 GV, §2.4 segarray and BCPL process start,
> §4.3 runcommand, §5.1 FileHandle, §8.1 global table, §13 Run/NewCLI), `dos-v34-spec.md` (§1 structure
> layouts, §4 CreateProc, §4a stack sizes, §4b unusual hunk files), `dos-exit-packets-v34.md` §1.4 (endtask),
> `handlers-v34.md` §1 (boot DeviceNodes) and §3.4 (makeglobvec), `dos-cli-v34.md` (per-Shell memory on the
> Workbench), `fault-v34.md` (C:Fault, used by the CLI for error texts).

---

## 0. Executive summary

1. dos allocates almost everything through **getvec/getmem**: one `AllocMem` of `(n+2)×4` bytes whose first
   long holds **the total block size in bytes**; the caller gets the BPTR of the second long. Flags are
   `MEMF_PUBLIC` (getvec) or the caller's flags (getmem); getvec blocks are **not cleared**. [O]
2. The **segments made by LoadSeg have the same format**: block = hunk size + 8, first long = block size,
   second long = next-segment BPTR. LoadSeg allocates **all hunks at HUNK_HEADER time, in hunk order**, before
   reading any hunk body. BSS hunks are **zeroed by the loader** (no `MEMF_CLEAR` asked); the tail of a
   CODE/DATA hunk beyond the data present in the file is **left as found**. [O]
3. Memory bits 30/31 of the **HUNK_HEADER size** select the requirement (`CHIP`, `FAST`, both = an
   unsatisfiable requirement); bits on the **hunk id** are ignored. [O]
4. **No packet is ever allocated**: the BCPL `sendpkt` path allocates nothing for Open/Lock/Read/Close.
   [D: zero allocation outside FileHandle, lock and handler-internal blocks]
5. **FileHandle** = 48-byte cleared getmem block, allocated **before** the handler is contacted; the 200-byte
   stream buffer is allocated lazily (only by the BCPL stream functions, never by LVO `Read`/`Write`). [O]
6. **FileLock** = 24-byte getvec block allocated **by the file system**, freed by it on `UnLock`. [O]
7. **CLI structure and its BSTR buffers** live **inside the CLI process's own stack** (no allocation). [O]
8. Every dos object observed is freed on the normal path: Open/Close, Lock/UnLock, LoadSeg/UnLoadSeg, running
   a command, `NewCLI` + `EndCLI` and `Run` all return free memory to the byte. [O] Genuine leaks found:
   **24 bytes per failed process creation** (exec `AllocEntry` leaves its MemList copy) [O]; the 56 bytes per
   Workbench Shell of `dos-cli-v34.md` §2 (cause not attributed).
9. Low memory never raises a requester or an alert from dos: the operation fails with **Result2 = 103**. One
   exception crashes the machine: **a lock allocation failure inside the ROM file system** (§5.3). [O]

---

## 1. Primitives

The contracts of getvec (29), freevec (30), getmem (19) and makeglobvec (13) are in `bcpl-runtime-v34.md`
§8.1 and `handlers-v34.md` §3.4. This section adds what the allocation traces show.

### 1.1 Block format [O]

| Call | `AllocMem` size | Flags passed | Header long (block +0) | Value returned |
|---|---|---|---|---|
| `getvec(n)` | `(n + 2) × 4` | `MEMF_PUBLIC` (1) | total block size in bytes | BPTR of block +4 (usable indices 0..n) |
| `getmem(n, flags)` | `(n + 2) × 4` | `flags` as given (seen: `$10001` = PUBLIC+CLEAR) | same | same |

- Measured pairs: getvec(1) 12, getvec(2) 16, getvec(4) 24, getvec(10) 48, getvec(49) 204, getvec(100) 408,
  getvec(199) 804, getvec(400) 1608, getvec(1000) 4008; header long read back = block size (e.g. `$18` for a
  24-byte DosInfo block). [O]
- getvec blocks are **not cleared** (flag word 1, no `MEMF_CLEAR`); objects that need zero fields use
  getmem with `$10001` (FileHandle, DosInfo, rn_TaskArray, FileSysStartupMsg, name copies). [O]
- Not every dos block carries the header: the RootNode (32 bytes) and the dos library base are plain
  `AllocMem` blocks (§2.10). [O]
- `freevec(v)`: v = 0 does nothing; header check and alert `$07000005` on an invalid header:
  `bcpl-runtime-v34.md` §8.1 (not re-probed here). The `FreeMem` size passed is the header value. [O]
- Failure: getvec/getmem return 0 and set **pr_Result2 = 103** (`ERROR_NO_FREE_STORE`); observed through
  every failure path of §5 (`Why` prints "insufficient free store"). [O]
- **Not probed**: getvec(0), getvec of a negative size, freevec of a block from plain `AllocMem`.

### 1.2 What happens below getvec when memory is short [O, mechanism D]

- On this ROM, after boot, the exec `AllocMem` library vector does **not** jump into the ROM: it jumps to a
  small stub held in RAM inside `ramlib.library`'s base area. [O]
- When a request fails, unused libraries are expunged before the failure is returned: during the first
  failing request of a session, `mathffp.library` (open count 0) was removed from the library list and its
  130-byte base freed, in the requesting task's context; the request then still failed (it was impossible
  by construction). A second failing request freed nothing. [O] Attribution of the expunge to the ramlib stub
  rather than to exec is [D].
- Consequence: free-memory figures measured after a failure can be higher than before by the size of the
  expunged libraries (136 bytes here); this is not dos behaviour.

---

## 2. Allocation inventory per DOS object

"Owner" = task in whose context the block is allocated and freed. All blocks below are in the first memory
that satisfies the flags; with slow RAM present that is slow RAM for every `MEMF_PUBLIC` block. [O]

| Object | Size | Primitive / flags | Cleared | Allocated by (when) | Freed by (when) |
|---|---|---|---|---|---|
| FileHandle | 48 (11 longs + header) | getmem, PUBLIC+CLEAR | yes | caller of Open, **before** any packet | caller, at the end of Close (after ACTION_END) |
| Stream buffer | 204 (getvec(49), 200 usable) | getvec | no | first BCPL rdch/wrch fill/flush on the stream | Close (via fh_Func3) |
| FileLock | 24 (getvec(4): 5 longs) | getvec | no | **file system**, on a successful LOCATE / FIND* | file system, on FREE_LOCK / END |
| DosPacket / StandardPacket | — | none | — | caller's BCPL frame (stack) [D] | — |
| Process + stack (BCPL createproc) | 188 + stack bytes | `AllocEntry`, 1 entry, PUBLIC+CLEAR | yes | creator | exec `RemTask` (endtask) |
| Process + stack (C `CreateProc`) | 188 + stack + name copy | same | yes | creator | same |
| AllocEntry's MemList | 16 + 8 × entries (24 for 1) | `AllocMem`, CLEAR only | yes | exec, inside AllocEntry | exec, at RemTask |
| Segarray, C CreateProc | 20 (4 longs + header) | getmem, PUBLIC+CLEAR | yes | CreateProc | endtask (freevec of pr_SegList) |
| Segarray, NewCLI / Run / handlers | 24 (getvec(4)) | getvec | no | NewCLI, Run, starthandler, cliinit | endtask |
| Global vector | `(max + 52) × 4` (FS: 1272; dos: 804) | getvec (makeglobvec) / plain AllocMem (dos) | no | makeglobvec; dos init | endtask if ≠ dl_GV |
| CLI structure + BSTR buffers | 0 | none: BCPL local vectors on the CLI process's own stack | — | — | with the process |
| `cli_CommandDir` node | 12 (getvec(1)) | getvec | no | Run / NewCLI / Path | the CLI at its end (`bcpl-runtime-v34.md` §13.6; not re-observed here) |
| Command stack | `cli_DefaultStack × 4 + 8` (4008 by default) | getvec | no | runcommand, per command | runcommand, after return |
| Command's private GV | 804..848 (per command) | getvec | no | the command's own startup stub | the stub, before returning |
| Run's argument FileHandle | `(len/4 + 13) × 4` (56 for `echo x\n`) | getvec(len/4 + 11) | no | Run | endstream (Close) in the new CLI |
| DeviceNode (makedevnode) | 48 (getvec(10)) | getvec | no | cliinit / Mount | rarely (failed DFn start) |
| DeviceNode name copy | 8 or 12 | getmem, PUBLIC+CLEAR | yes | makedevnode | never on the failed-DFn path (`handlers-v34.md` §1.1) |
| FileSysStartupMsg | 20 (4 longs + header) | getmem, PUBLIC+CLEAR | yes | cliinit | with the node |
| FileInfoBlock, InfoData | — | none in dos | — | the caller (BCPL commands: on their stack/vectors; WB: its own) | — |
| RootNode | 32 | plain `AllocMem`, PUBLIC+CLEAR | yes | dos init | never |
| DosInfo | 24 (5 longs + header) | getmem, PUBLIC+CLEAR | yes | cliinit (Initial CLI) | never |
| rn_TaskArray | 88 (21 longs + header: `[0]` = 20) | getmem, PUBLIC+CLEAR | yes | cliinit | never |

### 2.1 FileHandle and its buffer [O]

- BCPL `findinput`/`findoutput` and the LVO `Open` behave alike: FileHandle first, then (unless the name is
  `*` or `NIL:`) the packet to the handler. `Open("*")` allocates only the FileHandle (no handler block, no
  lock); `NIL:` likewise. A failed open frees the FileHandle before returning 0 (Result2 = handler's error,
  e.g. 205). [O]
- The 204-byte buffer appears only with BCPL stream I/O (`Type`, the CLI's console input/output, scripts).
  The Workbench opening an icon with LVO `Open`/`Read`/`Close` allocates none. [O]
- Close order (BCPL and LVO): buffer, then the handler releases its blocks (lock, then its 608-byte per-file
  block for the ROM file system), then the FileHandle. [O]

### 2.2 FileLock [O]

- A disk lock is a 24-byte getvec block owned by the file system process (allocation logged in the
  `File System` task). `Lock` costs, in the ROM file system, a transient 448-byte block (freed before the reply)
  plus the 24-byte lock kept until `UnLock`. [O]
- `Open` of a disk file costs the 48-byte FileHandle, a 608-byte file-system block and a 24-byte lock, all
  kept until Close. A FIND* on a missing name allocates and frees the 608-byte block and no lock. [O]
- `Examine`/`ExNext` (C:List) cost a transient 408-byte file-system block per call, nothing kept. [O]
- `DupLock` given to a new CLI (NewCLI, Run) is a new 24-byte lock from the file system. [O]
- The ROM file system also allocates and frees a 328-byte block every few seconds while idle. [O] (FS
  internals; listed so that nobody reads it as a leak.)

### 2.3 Packets [D]

No `AllocMem` other than the FileHandle, the stream buffer and the handler's own blocks was seen for
`Open`, `Read`, `Close`, `Lock`, `UnLock`, `Examine`, `ExNext`, nor for the startup packets of new
processes. The packets therefore live in the caller's BCPL frame (stack). Not checked by reading the message
address against the stack bounds.

### 2.4 Processes [O]

- **BCPL createproc** (NewCLI, Run, handlers, the Initial CLI): one `AllocEntry` entry of exactly
  **188 + stack bytes**, `MEMF_PUBLIC|MEMF_CLEAR`: Initial CLI 1788 (1600), New CLI / Background CLI 3388
  (3200), CON handler 2988 (2800), RAM handler 1388 (1200), file system 1028 (840), validator 2588 (2400).
  The **task name is copied into the top of the stack area**: for "Background CLI" the name string sits
  in the last 16 bytes below `tc_SPUpper`, for "Initial CLI" in the last 12. `tc_SPUpper` is not lowered:
  the copy is inside the stack range. [O]
- **C `CreateProc`** (LVO −138): one entry of **188 + stack + name copy**: Workbench (stack 5000,
  name "workbench.task") = **5204**; the name string (15 bytes + pad) sits immediately **above**
  `tc_SPUpper`, outside the stack. Then a 20-byte cleared segarray. [O]
- Both are freed by `RemTask` from `tc_MemEntry` (with the MemList), after endtask has freed the segarray and
  a private GV (`dos-exit-packets-v34.md` §1.4). Observed for New CLI, Background CLI, CON handlers,
  the validator and the Initial CLI at the end of the Workbench startup-sequence. [O]

### 2.5 CLI structure [O]

For the Initial CLI, a New CLI and a Background CLI, `pr_CLI` points **inside the process's own stack**
(between `tc_SPLower` and `tc_SPUpper`), and so do the BSTR buffers of `cli_SetName`, `cli_CommandName`,
`cli_Prompt` and `cli_CommandFile`. No allocation of 64 bytes or of BSTR buffers was seen when a CLI starts.
They are BCPL local vectors near the **bottom** of the stack (the BCPL stack grows upwards,
`bcpl-runtime-v34.md` §2.4) and disappear with the process. [O]

Initial values read: `cli_CommandDir` 0 (no path), `cli_DefaultStack` 1000; the Initial CLI's
`pr_CurrentDir` is **0** at boot (the first `cd` frees no old lock). [O]

### 2.6 Global vectors [O]

- dos GV: 804-byte plain `AllocMem` (MEMF_PUBLIC) at dos init; `dl_GV` = block + 200 (`bcpl-runtime-v34.md` §2.2).
- File-system GV: 1272 bytes (makeglobvec, max = 266). Commands: their stub's GV, 804 to 848 bytes
  depending on the command, allocated after the command stack and freed before it.
- C `CreateProc` processes and the CON handler use `dl_GV` (no block). [O]

### 2.7 Device list nodes [O]

At boot (cliinit, Initial CLI context) every node is a 48-byte block (getvec(10)) followed by a cleared
name copy of 8 bytes (1-character names such as `C`, `L`, `S`) or 12 bytes (2 to 6 characters). Six such
pairs come before the first file system starts; each assign node is followed by a 24-byte lock from the file
system; a DFn node created later also gets a 20-byte FileSysStartupMsg. Each started file system adds a
24-byte segarray, a 1272-byte GV and a 1028-byte process; for a drive whose file system fails to start
(DF2 here) these blocks and its buffers are freed again. [O; which name each early pair carries was not
read, roles from `handlers-v34.md` §1]

### 2.8 Temporary FileInfoBlock / InfoData [O]

dos allocates none: `List`, `Info`, `CD` show no 260/36-byte allocation; BCPL commands keep them in their
own vectors. Callers of the LVOs supply their own (the Workbench allocates its own blocks).

### 2.9 Path nodes copied by LoadWB [O]

Not dos, but seen in the same trace: before `CreateProc("workbench.task")`, LoadWB allocates, for each
path entry of the CLI, an 8-byte `MEMF_CLEAR` node plus a duplicated 24-byte lock.

### 2.10 Boot blocks of dos itself [O]

In order, in the dos init context: the library base (350 bytes, MEMF_PUBLIC; `lib_NegSize` 222,
`lib_PosSize` 124), the RootNode (32, PUBLIC+CLEAR, = `dl_Root`), the GV (804), a 244-byte PUBLIC+CLEAR
block filled with absolute jump vectors into the ROM (role not identified [S: BCPL entry trampolines]), then
`AllocEntry` of the Initial CLI (1788). In the Initial CLI: its segarray (24, cleared, `V!0 = 4`), DosInfo
(24, cleared, = `rn_Info`), `rn_TaskArray` (88, cleared, `[0] = 20`), then the device list (§2.7).

---

## 3. LoadSeg / UnLoadSeg

Observed through the BCPL loadseg called by the CLI for every command, and from the outside of the LVO path
(Workbench runs). The LVO is a bridge to the same global (`bcpl-runtime-v34.md` §1.4) [D].

### 3.1 Order of allocations [O]

1. Read buffer: **getvec(100) = 408 bytes**, before the file is opened.
2. Open of the file (FileHandle 48, file-system block 608, lock 24).
3. At HUNK_HEADER: the **hunk table getvec(number of hunks)** (2 hunks → 16, 3 → 20, 11 → 52), then
   **every hunk block, in hunk order 0..n−1, before any hunk body is read**.
4. For each HUNK_RELOC32 group: a temporary **getvec(count)** holding the offsets, freed right after the
   group is applied (e.g. a group of 11 offsets → 52 bytes).
5. At the end: free the read buffer, Close the file, free the hunk table. The segments stay.

### 3.2 Segment block [O]

- Block size = **hunk size in bytes (from HUNK_HEADER) + 8**: hunks of 316, 636, 9604 and 0 bytes gave
  blocks of 324, 644, 9612 and 8. Zero-size hunks get their own 8-byte block (confirms
  `dos-v34-spec.md` §4b).
- Long 0 = **block size in bytes** (getvec-compatible header), long 1 = BPTR of the next segment (0 for
  the last), hunk data from long 2. The segment BPTR = block + 4. [O, read in a loaded block]
- The size comes from **HUNK_HEADER**, not from the HUNK_CODE/HUNK_DATA length: a copy of `C:Echo` whose
  header announces 16 longs more than its code hunk loads and runs; its block is 64 bytes larger. [O]

### 3.3 Memory type [O]

| HUNK_HEADER size long, bits 31-30 | Flags passed to AllocMem | Result |
|---|---|---|
| 00 | `MEMF_PUBLIC` (1) | normal (slow RAM first here) |
| 01 | `MEMF_CHIP` (2) — **no** MEMF_PUBLIC | chip RAM |
| 10 | `MEMF_FAST` (4) — no MEMF_PUBLIC | slow RAM in this configuration (flagged FAST) |
| 11 | **8** (no memory header has that attribute) | allocation fails: Result2 103, "Unable to load …: insufficient free store" |

- Bits 30/31 on the **hunk id** (HUNK_CODE with bit 30 set) are **ignored**: the hunk is accepted and loaded
  with `MEMF_PUBLIC`. This settles the open question of `dos-v34-spec.md` §4b: the header size is what
  counts. [O]
- With bits 31-30 = 11, whether 1.3 would have consumed a following extra long (the 2.0 format) cannot be
  seen: the allocation fails first. [O for the failure, uncertain for the format]

### 3.4 Clearing [O]

- Hunk blocks are allocated **without `MEMF_CLEAR`**.
- **BSS hunks are zeroed by the loader**: a 4-byte BSS hunk (C:FastFonts) whose block was pre-filled with a
  pattern at allocation read all zero at program entry. [O]
- **CODE/DATA tail not cleared**: in the oversized-header copy of §3.2, the 64 bytes after the code data
  still held the pattern at program entry. [O]

### 3.5 UnLoadSeg [O]

- Frees the chain **in chain order** (hunk 0 first), one `FreeMem` per segment with the header size.
- `UnLoadSeg(0)`: not observed (no caller seen); see probe P1.

### 3.6 Failure in the middle of a load [O]

| Test file (copy of `C:Echo`, 2 hunks) | What happened | Result2 / CLI message |
|---|---|---|
| hunk 1 id replaced by an unknown hunk type | both hunks allocated, then failure; frees: read buffer, Close (lock, FS block, FileHandle), hunk table, **then hunk 0 and hunk 1** | 121, "Unable to load echob: file is not an object module" |
| header size of hunk 1 = 4 MB | hunk 0 allocated, hunk 1 allocation fails; frees everything as above, hunk 0 included | 103, "… insufficient free store" |
| `C:Dir` truncated to 4000 bytes (inside hunk 1 body) | both hunks allocated, read runs short; everything freed | 121 |

- Free memory after each failed load = before (no leak). [O]
- The CLI attempts the load **twice** when the error is not 218 (second pass of `bcpl-runtime-v34.md` §4.1),
  so every allocation above is seen twice. Then, to print the message, the CLI **loads and runs C:Fault**
  (segments 324 + 2328, stack 1608 = 400 longs, GV 804; `fault-v34.md` §2): printing a load error itself
  needs about 5 KB. [O]

---

## 4. Process and CLI life cycle

### 4.1 Running a command in a CLI [O]

Sequence for `echo hi` (2-hunk BCPL command) from the Initial CLI, after the lookup:
1. lookup in the current directory: read buffer 408 + FileHandle 48 + FS block 608, all freed (not found);
2. lookup in `C:`: 408 + 48 + 608 + lock 24 + hunk table 16 + segments 324 + 644; then 408, lock, 608,
   48, hunk table freed;
3. runcommand: stack 4008; the command's stub: GV 804;
4. on return: GV, stack, then UnLoadSeg (324, 644). Net: 0.
`cli_Module` holds the seglist during step 3–4 (`bcpl-runtime-v34.md` §4.4).

### 4.2 NewCLI then EndCLI (ROM CLI) [O]

Created (in NewCLI's context): segarray 24, `AllocEntry` 3388 (+ MemList 24), a dup lock 24 of the current
directory (file system). In the new process: input FileHandle 48, a 20-byte block later freed by the CON
handler [S: copy of the window specification], the CON handler's process 2988 (+24), the console's own blocks
(window: two 7120-byte and two 880-byte chip blocks, etc.), output FileHandle 48, the CLI-Startup script
(FileHandle, FS block, lock, 204 buffer, then the script's command) and the console buffers (204 each).
Measured at the idle `2>` prompt: **8,432 bytes of slow RAM + 16,000 bytes of chip RAM** for one New CLI
with its CON window.

EndCLI (in the New CLI): the EndCLI command (load/run/unload), the console buffers, both FileHandles, the CON
handler ends and frees everything it had (its process last), the script FileHandle, the current-dir lock,
the segarray, then `RemTask` frees the process. **Free memory back to the exact value before NewCLI**, twice
in a row. [O]

### 4.3 Run [O]

`run echo x`: segarray 24, argument FileHandle 56 (getvec(13), `bcpl-runtime-v34.md` §13.6), process 3388
(+24), dup lock 24; in the Background CLI: FileHandle 48 for `*`, the command, its 204-byte output buffer.
At the end: memory FileHandle 56 (freed by Close's freevec, fh_Func3 = 0), buffer, FileHandle, lock,
segarray, process. Net 0. [O]

### 4.4 End of the Initial CLI (`endcli >NIL:` in the WB startup-sequence) [O]

After the EndCLI command: its streams and buffers, the CON handler of the boot window (it frees its own
process), then the Initial CLI's segarray (24) and its process block (1788 + MemList). Nothing of the Initial
CLI stays except what cliinit made for the system (RootNode, DosInfo, rn_TaskArray, device list).

### 4.5 Genuine 1.3 leaks

| Case | Bytes left | Status |
|---|---|---|
| Process creation fails in `AllocEntry` (NewCLI with the 3388-byte request made impossible) | **24** (the MemList copy allocated by AllocEntry is never freed) | [O] exec behaviour, reached through createproc |
| Shell opened from the Workbench `Shell` icon then `endcli` (Shell-Seg + NEWCON) | **56** | [O] in `dos-cli-v34.md` §2; not attributed (the ROM CLI pair leaks 0, §4.2) |
| WB tool that calls Exit without replying WBStartup | its seglist and arguments | [D] `dos-exit-packets-v34.md` §1.5 |
| Process created by C `CreateProc` | its `pr_CurrentDir`, `pr_CIS`/`pr_COS` are not released by endtask | [O] `dos-exit-packets-v34.md` §1.4 (the creator's lock is shared, not duplicated) |

---

## 5. Low-memory behaviour

### 5.1 Failures reported with Result2 = 103 [O]

Each case below was produced on the real ROM by making one chosen allocation fail, then `C:Why`:

| Failing allocation | Visible effect | Cleanup |
|---|---|---|
| FileHandle of `Open` (inside `Type`) | Open returns 0 at once, **no packet sent** (no handler block allocated); `Type` prints "Can't open s:dpat"; Why: "insufficient free store" | nothing left |
| 204-byte stream buffer (first read of `Type`) | read returns end of file: `Type` prints nothing, return code 0 | Close later frees lock, FS block, FileHandle |
| A hunk block in LoadSeg | "Unable to load X: insufficient free store" | all segments freed (§3.6) |
| The command stack in runcommand (4008) | same message as a load failure ("Unable to load echo: insufficient free store"): runcommand returns −1 (`bcpl-runtime-v34.md` §4.4) | segments unloaded after C:Fault ran |
| Process + stack of NewCLI's createproc | "Unable to create new process", then "NEWCLI failed"; Why: "insufficient free store" | segarray freed; **24-byte leak** (§4.5) |

- No requester, no alert, no Guru in any of these. [O]
- `IoErr()` / pr_Result2 is **not cleared on success**: an LVO `Lock` that succeeded returned with
  pr_Result2 still holding an earlier 212. [O]

### 5.2 Expunge on failure [O]

See §1.2: a failing request first makes the system expunge unused libraries.

### 5.3 Lock allocation failure in the ROM file system: system crash [O, cause D]

Making the file system's 24-byte lock allocation fail during `cd s` hung the CLI; the memory list read through
`ExecBase` became garbage, then the machine reset and stopped on a dark red screen. [O] Interpretation [D,
uncertain]: the file system does not test getvec's result and writes the new lock at address 0, overwriting
the ExecBase pointer at `$4`. A replacement does not have to copy this; programs cannot rely on it.

### 5.4 Half-built objects [O]

Every dos-side failure above frees what it had built in the same call (FileHandle, segments, segarray); the
only residue seen is the exec MemList of §4.5.

---

## 6. Measurements on the real ROM

Configuration in the header (512 KB chip + 512 KB slow, no fast, DF0 + DF1). "slow" = the `$C00000` header.

| State | chip free | slow free | total |
|---|---:|---:|---:|
| Minimal boot, Initial CLI idle at `1>` (startup-sequence = one `echo`) | 439,344 | 485,288 – 485,312 | 924,632 – 924,656 |
| Workbench 1.3.3 booted, desktop idle, no CLI alive | 429,512 | 431,480 | **860,992** (= title bar, = `dos-cli-v34.md` §2) |

The two minimal-boot values differ by one 24-byte block between boots (not attributed). Later readings in a
session are not comparable to the first: after the first failing allocation `mathffp.library` is expunged
(+136, §1.2), and after a `cd` the CLI holds a 24-byte lock.

Per-operation cost (slow RAM unless stated; "transient" = freed before the operation returns):

| Operation | Transient | Held while open/loaded | After the matching release |
|---|---:|---:|---:|
| LVO `Open` disk file + `Close` (Workbench, icon) | — | 680 (48 + 608 + 24) | 0 |
| LVO `Open("*")` + `Close` | — | 48 | 0 |
| BCPL stream open + first read (`Type`) | — | 884 (680 + 204) | 0 |
| LVO `Lock` + `UnLock` (disk) | 448 | 24 | 0 |
| LoadSeg + UnLoadSeg of `C:List` (9,972-byte file, hunks 316 + 9,604) | 1,104 (408 + 48 + 608 + 24 + 16) | 9,936 | 0 |
| LoadSeg of `C:Avail` (11 hunks, 3 empty) | 1,140 (408 + 48 + 608 + 24 + 52) + reloc temporaries | 1,540 (hunks 1,452 + 11 × 8) | 0 |
| Running a BCPL command (default stack) | — | 4,008 stack + 804..848 GV | 0 |
| `NewCLI` → idle New CLI → `EndCLI` | — | 8,432 slow + 16,000 chip | **0** |
| `Run echo x` | — | 3,768 while the Background CLI lives (3,388 + 24 MemList + 24 segarray + 56 + 24 lock + 48 + 204), plus the command | 0 |

Other real-side figures useful to `docs/MEMORY-USAGE.md` [O]:
- trackdisk.device, per unit (DF0 and DF1 each): one `AllocEntry` of 412 (PUBLIC+CLEAR) + 512 (CLEAR) +
  **16,388 chip** (PUBLIC+CLEAR+CHIP) — the track buffer.
- ROM file system, per drive: 5 buffers of 540 bytes of chip RAM (`NumBuffers 5`), plus 408, 108 and 20-byte
  blocks; the buffers of the first file system started (DF0) were requested with `MEMF_CHIP` only, those
  of the later ones with `MEMF_PUBLIC|MEMF_CHIP`.
- Validator process (2588) runs at boot and frees itself.

---

## 7. Observable test vectors

| # | Scenario | Expected on a 1.3-compatible dos |
|---|---|---|
| 1 | getvec(9) | `AllocMem(44, MEMF_PUBLIC)`; long at BADDR(v)−4 = 44; not cleared |
| 2 | Open a disk file, Close it | free memory identical before/after; 48-byte cleared FileHandle seen |
| 3 | Open with the FileHandle allocation failing | returns 0, IoErr 103, the handler receives no packet |
| 4 | LoadSeg of a file whose HUNK_HEADER size has bit 30 | that hunk in chip RAM; bit 30 on the hunk id alone: ignored |
| 5 | LoadSeg, bits 31-30 = 11 in a header size | fails with 103 |
| 6 | LoadSeg of a file with a BSS hunk over dirty memory | BSS reads zero at entry |
| 7 | LoadSeg, header size larger than the code length | loads; block sized from the header; tail not cleared |
| 8 | LoadSeg of a truncated file / unknown hunk type | 0, IoErr 121; no memory left allocated |
| 9 | LoadSeg failing on hunk n's allocation | 0, IoErr 103; hunks 0..n−1 freed |
| 10 | Segment chain of a loaded file | each segment block = hunk size + 8; long at BADDR(seg)−4 = block size |
| 11 | NewCLI then EndCLI from a ROM CLI | free memory back to the byte |
| 12 | Run of a one-line command | free memory back to the byte after the Background CLI ends |
| 13 | C `CreateProc(name, pri, seg, 5000)` | Process block = 188 + 5000 + copy of the name above `tc_SPUpper`; `pr_StackSize` = 5000 |
| 14 | `pr_CLI` of a CLI | points inside the CLI process's own stack |
| 15 | CLI command whose stack cannot be allocated | "Unable to load <name>: insufficient free store" |

---

## 8. Probes still wanted (described, not written)

- **P1 — UnLoadSeg(0) and LoadSeg(missing)**: a small C-style program that calls `UnLoadSeg(0)` (does it
  return, does it touch memory 0..7?), then `LoadSeg("nonexistent")` and prints IoErr and the free counts.
- **P2 — getvec edge sizes**: through a BCPL command stub's GV (global 29), call getvec(0), getvec(−1) and
  freevec of an `AllocMem` block; report the AllocMem size seen and whether an alert follows.
- **P3 — 2.0-style memory attribute long**: hunk file whose header size has bits 31-30 = 11 and a following
  attribute long `MEMF_CHIP`, loaded on a machine where the allocation of flag 8 is made to succeed by the
  debugger, to see whether 1.3 consumes the extra long.
- **P4 — 56-byte Shell residue**: the AllocMem/FreeMem tracer of this page on the Workbench `Shell` icon then
  `endcli`, to attribute the 56 bytes of `dos-cli-v34.md` (NEWCON handler, Shell-Seg, or the Workbench).
- **P5 — lock failure via the LVO**: a program calling `Lock` while the file system's lock allocation is made
  to fail, with a watchpoint on `$0-$7`, to confirm or refute the null-pointer write of §5.3.
- **P6 — packets on the stack**: breakpoint on exec `PutMsg` during an LVO `Lock`, comparing the message
  address with the caller's `tc_SPLower..tc_SPUpper` (confirms §2.3).

## 9. Uncertain points

- Role of the 244-byte boot block of §2.10, of the 20-byte block of §4.2, and of the file system's
  608/448/408/328-byte blocks (only their sizes and lifetimes are observed).
- Whether the expunge-on-failure belongs to the ramlib stub or to exec (§1.2).
- Cause of the crash of §5.3.
- §2.3 (packets) is deduced from the absence of allocations.

---

## Clean-room review

Review of 2026-11-04.

- [x] No instruction listing, no pseudo-code of a ROM routine: the page gives allocation sizes, flags, the
  order of `AllocMem`/`FreeMem` calls as seen from the exec library vectors, structure locations relative to
  stacks, Result2 values and CLI messages.
- [x] No ROM address or ROM offset. The only addresses are ABI ones (`$4`, `$C00000` slow RAM base). The
  boot block of §2.10 is described ("absolute jump vectors into the ROM"), not reproduced.
- [x] No ROM data reproduced. CLI messages quoted are user-visible strings already listed in other pages
  ("Unable to load", "NEWCLI failed", "Unable to create new process", "Can't open", Why texts).
- [x] Test files: copies of a Workbench command with one longword changed or truncated; their content is
  not reproduced.
