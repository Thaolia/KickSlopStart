# dos-v34-spec.md — Behavioural spec of dos.library (V34 / Kickstart 1.3)

> ANALYSIS track ("dirty"). Downstream goal: "dos can open/read a file through a
> file-handler process via DOS packets, and load+run an executable from DF0:".
> Three provenances, labelled per field:
> **[ROM]** measured in `assets/kick34005.A500` (hard oracle, falsifiable by re-reading);
> **[ABI]** layout/constants taken from the public NDK includes (`dos/dosextens.i`, `dos/dos.i`,
> `dos/filehandler.i`, `FD/dos_lib.fd`) and from the public packet spec (RKRM/AmigaMail Vol.2) —
> these includes mainly describe **2.0/3.x**, the V34 deltas are flagged explicitly;
> **[inferred]** deduced from known 1.3 behaviour, not verified line by line (the clean-room wall
> forbids transcribing the code). **No opcode or instruction sequence is reproduced here.**

## 0. Founding fact: the V34 dos is the **BCPL** dos (major delta vs 2.0)

- **[ROM]** ROMTag `dos.library`: `rt_Flags = 0` (neither AUTOINIT nor COLDSTART),
  `rt_Type = NT_LIBRARY (9)`, `rt_Pri = 0`, `rt_Init = rt_EndSkip` (same pointer), `rt_Name` → `"dos.library"`,
  `rt_IdString` → `"dos 34.3 (9 Dec 1987)"`. dos therefore has **no** static
  auto-init table: its `rt_Init` is **manual** init code (it allocates and publishes its base
  itself) and it is **not** started by the `InitCode(RTF_COLDSTART)` pass — it is brought in by
  the disk bootstrap (cf. `dos-boot-sequence.md`).
- **[ABI/inferred]** In 1.3, dos is a **BCPL** port. Observable consequences, structuring
  for any V34 reimplementation:
  - **BPTR** = "BCPL pointer" = byte address **divided by 4**. Public conversion:
    `BADDR(bptr) = bptr << 2` (`dos/dos.i`). Every structure designated by a BPTR is therefore
    **4-byte aligned**. The fields noted `BPTR`/`BSTR` below carry shifted
    values; the fields noted `APTR` carry normal exec pointers (not shifted).
  - **BSTR** = BPTR to a **BCPL** string: **first byte = length**, then the characters
    (no terminator). **[ROM]** Corroborated directly in the ROM: the device name template
    is stored as BSTR `{0x03,'D','F','X'}` (the `'X'` = `0x58` is patched with the
    unit number `0`..`3` at run time); the handler name is `{0x0B,"File System"}`;
    the handler's resident task carries `{0x0B,"FileHandler"}`; the CLI window
    template is `{0x18,"CON:0/0/640/200/AmigaDOS"}`. The length byte does precede the
    string in each case → BSTR convention confirmed in ROM.
  - **Global vector**: dos's internal routines are called via a **BCPL global vector**
    (`pr_GlobVec` per process, `dl_GV` in the base). The publicly exposed LVO jump table is
    only a **thin layer** of entry points that switches into the BCPL code via this global vector and the
    standard BCPL registers (`dl_A2`/`dl_A5`/`dl_A6`). This is a V34 **implementation** detail
    (not reproducible field by field without transcribing the code) — but it is **observable** by the
    fact that `pr_GlobVec` and `dl_GV` are not null and that the BCPL handlers share this vector.

## 1. Layout of the V34 structures (offsets)

> Offsets **computed** from the NDK includes (macros `STRUCTURE`/`BYTE`/`WORD`/`LONG`/`APTR`/
> `BPTR`/`BSTR`/`STRUCT` of `exec/types.i`: **sequential addition without auto-alignment**).
> Base sizes used (all [ABI], verified by recomputation): `LN_SIZE=14`, `MLN_SIZE=8`,
> `LH_SIZE=14`, `MLH_SIZE=12`, `MN_SIZE=20`, `MP_SIZE=34 (0x22)`, `LIB_SIZE=34 (0x22)`,
> `TC_SIZE=92 (0x5C)`, `SS_SIZE=46 (0x2E)`, `ds_SIZEOF=12`. The structure offsets are
> **interoperability ABI**; they are **stable 1.3↔2.0** EXCEPT at the places marked "delta".

### 1a. STABLE group (high confidence, identical 1.3/2.0)

#### `FileHandle` — 44 bytes (`0x2C`). **There is NO `fh_Port` field.**
| Off | Field | Role |
|----:|-------|------|
| 0x00 | `fh_Link` | APTR, private use |
| 0x04 | `fh_Interactive` | APTR/BOOL, true if interactive handle (console) |
| 0x08 | `fh_Type` | **APTR = the handler's `MsgPort`** to which packets are `PutMsg()`ed. THIS is the port; no separate `fh_Port`. |
| 0x0C | `fh_Buf` | LONG, buffering buffer (BPTR) |
| 0x10 | `fh_Pos` | LONG, position in the buffer |
| 0x14 | `fh_End` | LONG, end of valid data in the buffer |
| 0x18 | `fh_Func1` (=`fh_Funcs`) | LONG |
| 0x1C | `fh_Func2` | LONG |
| 0x20 | `fh_Func3` | LONG |
| 0x24 | `fh_Arg1` (=`fh_Args`) | **LONG = the file's private key on the handler side** (see §2) |
| 0x28 | `fh_Arg2` | LONG |

#### `DosPacket` — 48 bytes (`0x30`)
| Off | Field | Role |
|----:|-------|------|
| 0x00 | `dp_Link` | APTR → the associated exec `Message` |
| 0x04 | `dp_Port` | APTR → **reply** port (must be filled on EVERY send: dos overwrites it) |
| 0x08 | `dp_Type` (=`dp_Action`) | LONG, `ACTION_*` code (see §2) |
| 0x0C | `dp_Res1` (=`dp_Status`) | LONG, result (what the function would have returned) |
| 0x10 | `dp_Res2` (=`dp_Status2`) | LONG, error code (what `IoErr()` would have returned) |
| 0x14 | `dp_Arg1` (=`dp_BufAddr`) | LONG |
| 0x18 | `dp_Arg2` | LONG |
| 0x1C | `dp_Arg3` | LONG |
| 0x20 | `dp_Arg4` | LONG |
| 0x24 | `dp_Arg5` | LONG |
| 0x28 | `dp_Arg6` | LONG |
| 0x2C | `dp_Arg7` | LONG |

#### `StandardPacket` — 68 bytes (`0x44`)
| Off | Field | Role |
|----:|-------|------|
| 0x00 | `sp_Msg` | `struct Message` (20 bytes, `MN_SIZE`) — the exec message |
| 0x14 | `sp_Pkt` | `struct DosPacket` (48 bytes) |

Conventional coupling: `sp_Msg.mn_Node.ln_Name` points to `sp_Pkt`, and `dp_Link` points to
`sp_Msg`, so that a `GetMsg()` that returns the `Message` allows the packet to be found. **[ABI]**

#### `CommandLineInterface` (CLI) — 64 bytes (`0x40`), identical 1.3/2.0
| Off | Field | | Off | Field |
|----:|-------|--|----:|-------|
| 0x00 | `cli_Result2` (LONG) | | 0x24 | `cli_CommandFile` (BSTR) |
| 0x04 | `cli_SetName` (BSTR) | | 0x28 | `cli_Interactive` (LONG/BOOL) |
| 0x08 | `cli_CommandDir` (BPTR) | | 0x2C | `cli_Background` (LONG/BOOL) |
| 0x0C | `cli_ReturnCode` (LONG) | | 0x30 | `cli_CurrentOutput` (BPTR FileHandle) |
| 0x10 | `cli_CommandName` (BSTR) | | 0x34 | `cli_DefaultStack` (LONG, in **long words**) |
| 0x14 | `cli_FailLevel` (LONG) | | 0x38 | `cli_StandardOutput` (BPTR FileHandle) |
| 0x18 | `cli_Prompt` (BSTR) | | 0x3C | `cli_Module` (BPTR, SegList of the loaded command) |
| 0x1C | `cli_StandardInput` (BPTR FileHandle) | | | |
| 0x20 | `cli_CurrentInput` (BPTR FileHandle) | | | |

#### `FileLock` — 20 bytes (`0x14`)
| Off | Field | Role |
|----:|-------|------|
| 0x00 | `fl_Link` | BPTR, next lock in the handler's chain |
| 0x04 | `fl_Key` | LONG, disk block number of the object |
| 0x08 | `fl_Access` | LONG, `SHARED_LOCK (-2)` or `EXCLUSIVE_LOCK (-1)` |
| 0x0C | `fl_Task` | APTR, the `MsgPort` of the handler owning the lock |
| 0x10 | `fl_Volume` | BPTR → `DLT_VOLUME` node of the volume |

#### `DeviceNode` (= `DevInfo`/`dvi_*` of dosextens) — 44 bytes (`0x2C`), layout stable 1.3/2.0
> This is the node of a DOS "device" (e.g. `DF0:`), linked into the device list. In 1.3, it is
> this form (`dos/filehandler.i`) that is used; the unified `DosList` structure is a
> **2.0 wrapping** of the same storage (cf. §1b).
| Off | Field | Role |
|----:|-------|------|
| 0x00 | `dn_Next` | BPTR, singly linked list |
| 0x04 | `dn_Type` | ULONG, always 0 for a DOS device |
| 0x08 | `dn_Task` | APTR = `MsgPort` of the handler process. **NULL ⇒ the handler will be started on 1st access** |
| 0x0C | `dn_Lock` | BPTR, not used for a device |
| 0x10 | `dn_Handler` | BSTR = file to `LoadSeg` if `dn_SegList` is NULL |
| 0x14 | `dn_StackSize` | ULONG, stack of the handler process at its creation |
| 0x18 | `dn_Priority` | LONG, priority of the handler process |
| 0x1C | `dn_Startup` | BPTR → `FileSysStartupMsg` (for a disk) |
| 0x20 | `dn_SegList` | BPTR, already loaded code of the handler (if NULL → load `dn_Handler`) |
| 0x24 | `dn_GlobalVec` | BPTR, BCPL global vector. **-1** = `dn_SegList` is NOT a BCPL prog (dos does not build a GV); **0** = conforming BCPL prog, dos builds the GV; **>0** = existing GV |
| 0x28 | `dn_Name` | BSTR = node name (e.g. BSTR `{3,"DF0"}`) |

#### `FileSysStartupMsg` — 16 bytes (`0x10`)
| Off | Field | Role |
|----:|-------|------|
| 0x00 | `fssm_Unit` | ULONG, exec unit number of the device (0..3 for DFx) |
| 0x04 | `fssm_Device` | BSTR, name of the low-level device (**[ROM]** `"trackdisk.device"`) |
| 0x08 | `fssm_Environ` | BPTR → environment/geometry table (`DosEnvec`) |
| 0x0C | `fssm_Flags` | ULONG, flags for `OpenDevice()` |

#### `DosLibrary` (dos base) — header + BCPL wiring
| Off | Field | Role |
|----:|-------|------|
| 0x00 | `dl_lib` | `struct Library` (34 bytes, `LIB_SIZE`); `lib_Version=34`, `lib_Revision=3` ([ROM] "dos 34.3") |
| 0x22 | `dl_Root` | APTR → `RootNode` (root of all the DOS wiring, cf. §1b and `dos-boot-sequence.md`) |
| 0x26 | `dl_GV` | APTR → **BCPL global vector** |
| 0x2A | `dl_A2` | LONG, standard BCPL register values |
| 0x2E | `dl_A5` | LONG |
| 0x32 | `dl_A6` | LONG |
| 0x36 | `dl_Errors` | APTR, private: error message table |
| 0x3A | `dl_TimeReq` | APTR, private: timer request |
| 0x3E | `dl_UtilityBase` | APTR, private — **delta: utility.library is 2.0; field irrelevant in V34** |
| 0x42 | `dl_IntuitionBase` | APTR, private: intuition base (for disk requesters) |

### 1b. Group MODIFIED in 2.0 — V34 **differs** (cut off the tails!)

#### `Process` — **V34 boundary: the structure stops at `pr_WindowPtr`**
The offsets from 0x00 to 0xB8 are V34-valid; **everything that follows is "new with 2.0"**
(explicit annotation in `dosextens.i`) and **does not exist in V34**.
| Off | V34 field | Role |
|----:|-----------|------|
| 0x00 | `pr_Task` | `struct Task` (92 bytes, `TC_SIZE`) |
| 0x5C | `pr_MsgPort` | embedded `struct MsgPort` (34 bytes). **This is the port that `CreateProc`/`DeviceProc` return — as a directly usable `APTR` (byte address), NOT a BPTR** (cf. §4). The "BPTR address" comment in `dosextens.i` is misleading: the arithmetic `Process = return − TC_SIZE` is in bytes, and all the other "handler port" fields here are `APTR`s (`pr_ConsoleTask`, `pr_FileSystemTask`, `fl_Task`, `dn_Task`, `dp_Port`, `fh_Type`). |
| 0x7E | `pr_Pad` | WORD |
| 0x80 | `pr_SegList` | BPTR, array of the process's seglists |
| 0x84 | `pr_StackSize` | LONG |
| 0x88 | `pr_GlobVec` | APTR, **BCPL global vector of the process** |
| 0x8C | `pr_TaskNum` | LONG, CLI task no. (0 if not a CLI) |
| 0x90 | `pr_StackBase` | BPTR, top of the process stack |
| 0x94 | `pr_Result2` | LONG, secondary result of the last call (= `IoErr`) |
| 0x98 | `pr_CurrentDir` | BPTR, lock of the current directory |
| 0x9C | `pr_CIS` | BPTR, current CLI input stream (FileHandle) |
| 0xA0 | `pr_COS` | BPTR, current CLI output stream (FileHandle) |
| 0xA4 | `pr_ConsoleTask` | APTR, console handler process of the current window |
| 0xA8 | `pr_FileSystemTask` | APTR, handler process of the current drive |
| 0xAC | `pr_CLI` | BPTR → `CommandLineInterface` |
| 0xB0 | `pr_ReturnAddr` | APTR, previous stack frame |
| 0xB4 | `pr_PktWait` | APTR, function called while waiting for a message |
| 0xB8 | `pr_WindowPtr` | APTR, window for error requesters. **← last V34 field** |

**`Process` size in V34 ≈ `0xBC` (188 bytes).** `pr_HomeDir (0xBC)`, `pr_Flags (0xC0)`,
`pr_ExitCode`, `pr_ExitData`, `pr_Arguments`, `pr_LocalVars`, `pr_ShellPrivate`, `pr_CES` are
**2.0+ additions**: a 1.3 reimplementation must NEITHER reserve NOR expose these fields. (Analogous
to the `ExecBase` boundary at `~0x22E` documented in `exec-spec.md`.)

#### `RootNode` — **V34 boundary: stops at `rn_FileHandlerSegment`**
| Off | V34 field | Role |
|----:|-----------|------|
| 0x00 | `rn_TaskArray` | BPTR: `[0]` = max number of CLIs; `[n]` = APTR to the process id of CLI n |
| 0x04 | `rn_ConsoleSegment` | BPTR, SegList of the CLI |
| 0x08 | `rn_Time` | `DateStamp` (12 bytes), current time |
| 0x14 | `rn_RestartSeg` | LONG/BPTR, **SegList of the disk-validator process** ([ROM] `"L:Disk-Validator"` / `"Validator"`) |
| 0x18 | `rn_Info` | BPTR → `DosInfo` |
| 0x1C | `rn_FileHandlerSegment` | BPTR, **file-handler code** (the resident OFS handler). **← last V34 field** |

**`RootNode` size in V34 ≈ `0x20` (32 bytes).** `rn_CliList`, `rn_BootProc`, `rn_ShellSegment`,
`rn_Flags` are **2.0+** (there is no `MinList`-based CLI list, no Shell, no
dos flags in 1.3: CLI management goes solely through `rn_TaskArray`).

#### `DosInfo` — **V34 boundary: stops at `di_NetHand`; NO semaphores in 1.3**
| Off | V34 field | Role |
|----:|-----------|------|
| 0x00 | `di_McName` (=`di_ResList`) | BPTR, list of DOS resident modules (loaded segments) |
| 0x04 | `di_DevInfo` | BPTR → **head of the device/volume/assign list** (`DeviceNode` chain) |
| 0x08 | `di_Devices` | BPTR, zero in practice |
| 0x0C | `di_Handlers` | BPTR, zero in practice |
| 0x10 | `di_NetHand` | APTR, zero. **← last V34 field** |

**In V34, the device list is protected by `Forbid()/Permit()`**, not by semaphores.
`di_DevLock`, `di_EntryLock`, `di_DeleteLock` (3× `SignalSemaphore`) are **2.0+**: do not
allocate them nor rely on them for a 1.3 target. **`DosInfo` size in V34 ≈ `0x14` (20 bytes).**

#### `DosList` (unified 2.0 view) vs 1.3 nodes
`DosList` (dosextens) is a **union structure introduced in 2.0** to describe interchangeably
device / volume / assign. For 1.3, describe instead:
- **device**: `DeviceNode` (§1a);
- **volume**: `DevList`/`dl_*` (`dl_Next` 0x00, `dl_Type` 0x04, `dl_Task` 0x08, `dl_Lock` 0x0C,
  `dl_VolumeDate` 0x10 `DateStamp`, `dl_LockList` 0x1C, `dl_DiskType` 0x20, `dl_Name` 0x28 BSTR —
  44 bytes).

The useful "DosList" offsets are nevertheless consistent with `DeviceNode` on the first fields
(`dol_Next`/`dol_Type`/`dol_Task`/`dol_Lock` = `dn_Next`/`dn_Type`/`dn_Task`/`dn_Lock`), and
`dol_Startup=0x1C`, `dol_SegList=0x20`, `dol_GlobVec=0x24`, `dol_Name=0x28` coincide with
`dn_Startup`/`dn_SegList`/`dn_GlobalVec`/`dn_Name`. Type constants: `DLT_DEVICE=0`,
`DLT_DIRECTORY=1` (assign), `DLT_VOLUME=2`.

## 2. File-handler packet protocol (open-for-read → read → close path)

### 2a. The life cycle of a packet — **WARNING: no public `DoPkt()` in V34**
**[ABI, major delta]** `DoPkt`, `SendPkt`, `WaitPkt`, `ReplyPkt`, `AbortPkt` are marked
*"functions in V36 or higher (Release 2.0)"* in `dos_lib.fd`: **they do NOT exist in the
V34 jump table**. In 1.3, packet exchange is done by dos's **internal BCPL** routines
(an internal `sendpkt`/`taskwait`), or, on the application side, by **building the packet by hand** and
using the **exec** primitives `PutMsg`/`WaitPort`/`GetMsg`. A 1.3 reimplementation can
therefore NOT rely on `DoPkt()`: it must either provide the internal equivalent, or document the
exec pattern. The observable cycle (identical whatever the wrapping):

1. The caller (the requesting process) obtains/allocates a `StandardPacket` (exec message + DosPacket).
2. It fills `dp_Type` (= `ACTION_*`), `dp_Arg1..n`, and **`dp_Port = &requester->pr_MsgPort`**
   (the reply port; dos/BCPL overwrites it on every send — always refill it).
3. `PutMsg()` of the message to the handler's `MsgPort` (= `fh_Type`, or `dn_Task`, or `fl_Task`).
4. The caller does `WaitPort(&pr_MsgPort)` then `GetMsg()` to retrieve the reply (the handler did
   `ReplyMsg()` to `dp_Port`). The handler is a **process**: it loops in `WaitPort`/`GetMsg`
   on ITS port, processes the packet, fills `dp_Res1`/`dp_Res2`, `ReplyMsg()`.
5. The caller reads `dp_Res1` (result) and `dp_Res2` (error code, = `IoErr`).

**Key identity [ABI, corroborated by dos.i]**: the `mode` passed to `Open()` **IS** the `ACTION_*` code
sent to the handler — `MODE_OLDFILE = 1005 = ACTION_FINDINPUT`, `MODE_NEWFILE = 1006 =
ACTION_FINDOUTPUT`, `MODE_READWRITE = 1004 = ACTION_FINDUPDATE`.

### 2b. Table of the read-path packets (args and results)
> **[ABI]** according to the public packet spec (RKRM Devices / AmigaMail Vol.2). `LOCK` = BPTR to
> `FileLock` (0 = root of the current volume). `BSTR` = BPTR to a length-prefixed BCPL string.

| ACTION_ (val.) | Via | ARG1 | ARG2 | ARG3 | RES1 | RES2 |
|----------------|-----|------|------|------|------|------|
| `FINDINPUT` (1005) | `Open(…,MODE_OLDFILE)` | **BPTR `FileHandle` to fill** | `LOCK` base directory (0=root) | `BSTR` file name (relative to ARG2) | `BOOL` success (DOSTRUE/DOSFALSE) | code on failure |
| `FINDOUTPUT` (1006) | `Open(…,MODE_NEWFILE)` | same | same | same | same | same |
| `FINDUPDATE` (1004) | `Open(…,MODE_READWRITE)` | same | same | same | same | same |
| `READ` (`'R'`=82) | `Read()` | **`fh_Arg1`** of the open FileHandle | `APTR` destination buffer | `LONG` number of bytes to read | `LONG` bytes read (**0 = EOF, -1 = error**) | code if RES1=-1 |
| `WRITE` (`'W'`=87) | `Write()` | `fh_Arg1` | `APTR` source buffer | `LONG` number of bytes | `LONG` bytes written | code if RES1≠ARG3 |
| `SEEK` (1008) | `Seek()` | `fh_Arg1` | `LONG` new position | `LONG` mode (`OFFSET_BEGINNING -1`/`OFFSET_CURRENT 0`/`OFFSET_END 1`) | `LONG` old position (-1 = error) | code if RES1=-1 |
| `END` (1007) | `Close()` | `fh_Arg1` | — | — | `LONG` DOSTRUE | — |
| `LOCATE_OBJECT` (8) | `Lock()` | `LOCK` base directory (0=root) | `BSTR` object name | `LONG` mode (`ACCESS_READ/SHARED_LOCK -2`, `ACCESS_WRITE/EXCLUSIVE_LOCK -1`) | `BPTR` new `FileLock` (0=failure) | code on failure |
| `FREE_LOCK` (15) | `UnLock()` | `LOCK` to free | — | — | `BOOL` success | — |
| `EXAMINE_OBJECT` (23) | `Examine()` | `LOCK` of the object | `BPTR` `FileInfoBlock` to fill | — | `BOOL` success | code |
| `EXAMINE_NEXT` (24) | `ExNext()` | `LOCK` of the examined directory | `BPTR` `FileInfoBlock` (from the previous Examine) | — | `BOOL` (failure = no more entries) | code |
| `PARENT` (29) | `ParentDir()` | `LOCK` of the object | — | — | `BPTR` lock of the parent (0=root) | code |
| `INFO` (26) | `Info()` | `LOCK` | `BPTR` `InfoData` to fill | — | `BOOL` success | code |

**1.3-specific note [ABI]**: for `ACTION_END`, "*Under 1.3, [DOS] does not check the result*"
(under 2.0 a failure prevents deallocation of the FileHandle; in 1.3 the result is ignored).

## 3. FileHandle: what `Open()` returns and how `Read()` routes

**[ABI/inferred]**:
1. `Open(name, accessMode)` **allocates** a `FileHandle` (BPTR-addressable area, 4-aligned). It resolves
   the device/volume/assign of the path via the `di_DevInfo` list (→ `DeviceProc`), starts the handler
   if `dn_Task` is NULL (cf. `dos-boot-sequence.md` §D), then sets **`fh_Type = dn_Task`** (the
   handler's `MsgPort`).
2. It sends the `FINDINPUT/OUTPUT/UPDATE` packet (= `accessMode`) with **ARG1 = BPTR of the FileHandle
   itself** and ARG2/ARG3 = lock+name. The handler, on success, **fills `fh_Arg1`** (its private
   file-object key) and returns `DOSTRUE` in `dp_Res1`.
3. `Open()` returns the **BPTR of the FileHandle** (0 on failure, `IoErr`/`pr_Result2` set).
4. `Read(fh, buf, len)` takes the FileHandle, reads **`fh_Arg1`** and **`fh_Type`**, and sends an
   `ACTION_READ` packet to the `fh_Type` port with ARG1=`fh_Arg1`, ARG2=buffer, ARG3=length. It returns
   `dp_Res1` (bytes read, 0=EOF, -1=error). `Close(fh)` sends `ACTION_END(fh_Arg1)` and frees the
   FileHandle. The `fh_Buf`/`fh_Pos`/`fh_End` fields are used for **line/character buffering**
   (e.g. for interactive reads); block reads go directly through the packet.

## 4. `CreateProc` and **observable** BCPL aspects (never transcribed)

- **[ABI]** `CreateProc(name D1, pri D2, segList D3, stackSize D4)` creates a `Process` and returns
  **an `APTR` (directly usable byte pointer) to its `MsgPort`** (`pr_MsgPort`), ready for
  `PutMsg()` as is. Documented ABI relation: the address of the `Process` = `returned_value − TC_SIZE`
  (= `− 92` **bytes**), because `pr_MsgPort` is at offset `TC_SIZE` in `Process`. `DeviceProc(name)`
  returns the same type of pointer (port of the path's handler).
- **[ABI] BPTR/APTR asymmetry that must absolutely not be confused (classic crash point in 1.3)**:
  `Open()` returns a **BPTR** `FileHandle` → `BADDR()` (×4) is needed to dereference the structure.
  `CreateProc()`/`DeviceProc()` return an **APTR** `MsgPort` → **do NOT `BADDR()`**, it is used
  directly. Same asymmetry in the structures: BPTRs carry /4 addresses (locks,
  FileHandles, seglists, BSTR), whereas the handler port fields (`fh_Type`, `dn_Task`,
  `fl_Task`, `pr_FileSystemTask`, `pr_ConsoleTask`, `dp_Port`) are normal exec APTRs.
- **[ABI/inferred] Observable BCPL linkage**:
  - A DOS process receives its startup context via a **startup packet** (`ACTION_STARTUP`
    = 0) placed at its `pr_MsgPort` at launch; the handler waits for it first.
  - `pr_GlobVec` holds the process's **BCPL global vector**; `dn_GlobalVec` decides, at creation,
    whether dos must build one (`0`), reuse a GV (`>0`) or consider that the code is not
    BCPL (`-1`). The resident OFS handler is a **BCPL** program sharing dos's GV.
  - BCPL routines take their **arguments in registers** and handle **BPTRs**; the BCPL
    stack is distinct from the C stack. These conventions are **observable** (values of `pr_GlobVec`,
    `dl_A2/A5/A6`, BPTRs in the fields) but their internal mechanics belong to the implementation and
    are **not** reproduced here.
- **[ABI]** `LoadSeg(name)` opens the file (via the §2b packets), reads a **hunk** executable
  (`HUNK_HEADER`/`CODE`/`DATA`/`BSS`/`RELOC32`/`HUNK_END`), allocates one memory block per hunk, applies
  the relocations, and **links the segments** BCPL-style: at `BADDR(seg)` one finds the BPTR of the next
  segment, the code starts at `BADDR(seg)+4`. Returns the **BPTR of the 1st segment** (0 = failure, `IoErr`
  set). `UnLoadSeg(seglist)` frees the chain. (Consistent with project milestone D2 "LoadSeg".)

## 5. Public LVO table of dos.library in V34 (1.3 subset)

**[ABI, `dos_lib.fd` `##bias 30`]** — V34 exposes **only** the functions BEFORE the marker
*"V36 or higher (Release 2.0)"*. 4 standard library vectors (`-6 Open`, `-12 Close`,
`-18 Expunge`, `-24` reserved) then, from `-30` to `-222`:

| LVO | Function | LVO | Function | LVO | Function |
|----:|----------|----:|----------|----:|----------|
| -30 | `Open` | -96 | `DupLock` | -162 | *(private dos1)* |
| -36 | `Close` | -102 | `Examine` | -168 | *(private dos2)* |
| -42 | `Read` | -108 | `ExNext` | -174 | `DeviceProc` |
| -48 | `Write` | -114 | `Info` | -180 | `SetComment` |
| -54 | `Input` | -120 | `CreateDir` | -186 | `SetProtection` |
| -60 | `Output` | -126 | `CurrentDir` | -192 | `DateStamp` |
| -66 | `Seek` | -132 | `IoErr` | -198 | `Delay` |
| -72 | `DeleteFile` | -138 | `CreateProc` | -204 | `WaitForChar` |
| -78 | `Rename` | -144 | `Exit` | -210 | `ParentDir` |
| -84 | `Lock` | -150 | `LoadSeg` | -216 | `IsInteractive` |
| -90 | `UnLock` | -156 | `UnLoadSeg` | -222 | `Execute` |

That is **37 vectors** (including 2 private ones `-162`/`-168`), `lib_NegSize ≈ 222`. **Delta**: everything that
follows (`AllocDosObject`/`FreeDosObject`/`DoPkt`/`SendPkt`/`WaitPkt`/`ReplyPkt`/`AbortPkt`/record
locking/buffered I/O `FGetC`…/2.0 object management/`SetIoErr`/`Fault`/`PrintFault`…) is **2.0+**
and **must not exist** in a V34 jump table.

## 6. Uncertainties / to be confirmed by the implementation track

- **`ACTION_STARTUP` (0)**: the exact distribution of `dp_Arg1..7` of the startup packet received by
  a 1.3 handler (which slot carries the `DeviceNode`, which carries the `FileSysStartupMsg`/name) has not
  been pinned down from a primary source — it is **handler-dependent** and must be validated
  (common convention: the `DeviceNode` and its `dn_Startup` are reachable from the startup
  packet; to be checked on real behaviour).
- **Exact sizes** (`pr_SIZEOF`, `rn_SIZEOF`, `DosInfo` in V34): deduced from the "new 2.0"
  boundaries of the includes, not measured in the ROM's init code (the wall forbids tracing
  `rt_Init`). The offsets up to the indicated boundaries are stable ABI facts; the total V34
  sizes are to be confirmed by behaviour on an authentic 1.3.
- **Internal BCPL wiring** (content of the global vector, internal `sendpkt` mechanics): described as
  behaviour, not as code — the implementation must provide a functional equivalent, not a
  copy.
- **`dl_UtilityBase`/`DosInfo` semaphores/`RootNode`/`Process` tails**: marked 2.0+ above;
  NOT to be implemented for a strict 1.3 target.

## Clean-room review

Review of 2026-10-29.

- [x] No 68000 instruction sequence transcribed or paraphrased, no disassembly excerpt:
  §2-§4 describe the packet protocol and the **observable** BCPL conventions (fields, values),
  from the public includes and packet spec.
- [x] **Fixed**: removed the ROM addresses of the dos ROMTag, of `rt_Init`/`rt_EndSkip`,
  `rt_Name`, `rt_IdString` and of the cited BSTR strings (`DFX`, `File System`, `FileHandler`,
  `CON:…`, `trackdisk.device`). The relation `rt_Init == rt_EndSkip` is kept without value.
- [x] Remaining: offsets of public NDK structures (`dosextens.i`, `filehandler.i`), LVOs
  (`dos_lib.fd`), `ACTION_*`/`MODE_*`/`DLT_*` constants, short BSTR templates (ABI names,
  inventoried in `docs/audit/specs-review.md`).
