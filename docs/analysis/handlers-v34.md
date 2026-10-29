# handlers-v34.md — Initial DosList, start of the handlers, "file" globals (dos V34)

> ANALYSIS track ("dirty"). Sources: the ROM `assets/kick34005.A500` (dos 34.3) and, on the disk
> `assets/wb133.adf` (Workbench 1.3.3), `c:MakeDir`, `c:Assign`, `c:Delete`, `c:Rename`,
> `l:Ram-Handler`, `l:Newcon-Handler`, `l:Aux-Handler`, `l:Port-Handler` (extracted into scratch).
> Complements `bcpl-runtime-v34.md` (§2, §8, §13) — same conventions: **BPTR** = address/4,
> **BSTR** = BPTR of a string with a length byte, **taskid** = address (APTR) of the MsgPort of a
> process (process+$5C), "R2" = `pr_Result2`.
>
> **Legend**: **[O]** observed directly · **[D]** deduced from converging observations ·
> **[S]** assumed. No ROM address is cited (removed on 2026-10-29).
>
> This document describes behaviours, ABI layouts and constants. **No instruction
> sequence is reproduced or paraphrased.**

DeviceNode layout (reminder, in longs): `!0` dn_Next · `!1` dn_Type · `!2` dn_Task · `!3` dn_Lock ·
`!4` dn_Handler · `!5` dn_StackSize · `!6` dn_Priority · `!7` dn_Startup · `!8` dn_SegList ·
`!9` dn_GlobalVec · `!10` dn_Name. For a **volume** (dn_Type 2) the same slots are:
`!3` dl_Lock · `!4..!6` dl_VolumeDate · `!7` dl_LockList · `!8` dl_DiskType · `!9` unused.
FileLock: `+$00` fl_Link · `+$04` fl_Key · `+$08` fl_Access · **`+$0C` fl_Task** · `+$10` fl_Volume. [O by use]

---

## 0. Executable summary

1. **It is not the dos init (rt_Init) that populates the DosList, it is `cliinit` (global 133)**,
   run in the "Initial CLI" process. [O/D]
2. Nodes created by the ROM, in this order (each creation inserts **at the head**): **DF0**, then
   **RAM, CON, RAW, SER, PAR, PRT** (devices, dn_Type 0, dn_Task 0), then the assigns
   **SYS, LIBS, DEVS, FONTS, C, L, S** (dn_Type 1), then **DF1..DF3** only if their handler
   starts. Exact values in §1.2. [O]
3. **CON:/RAW:** = ROM console-handler (segarray entry 5) via the already filled `dn_SegList`, **shared**
   GV (`dn_GlobalVec` = BPTR of the Initial CLI's GV), stack 700 longs, pri 5, Startup 0
   (CON) / 1 (RAW). Started by the standard **global 112**; nobody writes dn_Task ⇒ **one
   process + one window per Open**. [O]
4. **RAM:** = `L:RAM-HANDLER` loaded from disk at the first deviceproc, **new GV** (makeglobvec),
   stack 300 longs, pri 0. The handler writes dn_Task **itself**, **clears dn_Handler..dn_GlobalVec**
   of its node and creates a **volume node "RAM DISK"**. [O WB]
5. The handler must reply to the startup packet with **Res1 ≠ 0** (success); Res2 is not
   interpreted by dos on success. dos writes dn_Task **only** for the file systems it
   launches itself from cliinit (DFx), never via global 112. [O]
6. All the "object" globals (locateobj 108, deleteobj 90, createdir 125, setcomment/protect)
   go through a common routine: `deviceproc(name)` → port + lock (Result2) ⇒ packet
   **Arg1 = lock, Arg2 = BSTR of the COMPLETE name** (`xxx:` prefix included), Arg3 = parameter. [O]

---

## 1. Q1 — DosList nodes created by the ROM

### 1.1 Where and in which order [O ROM]

- **The dos rt_Init** creates no DeviceNode. It creates the "Initial CLI" process
  then opens `expansion.library` and walks `eb_MountList` (ExpansionBase+$4A): it **chains**
  together (dn_Next, BPTR) the DeviceNodes of the BootNodes (`bn_DeviceNode`, BootNode+$10), removes
  the first BootNode from the list (RemHead) and stores **the APTR of its DeviceNode in
  `rn_FileHandlerSegment`** (RootNode+$1C) **temporarily**. On an A500 without an autoboot card the
  list is empty ⇒ this field is 0. [O for the accesses, D for the BootNode semantics]
- **cliinit** (global 133, ROM segarray entry 3), run by
  the Initial CLI [D: start(pkt=0) → GV[133], cf. bcpl-runtime §13.5], does in order:
  1. allocates rn_TaskArray (20 entries), DosInfo (cleared ⇒ di_DevInfo = 0), stores them in the
     RootNode; reads the old value of RootNode+$1C (APTR → BPTR) then writes there the **real**
     `rn_FileHandlerSegment` = ROM segarray `V!6` (file system); `rn_ConsoleSegment` = `V!4`;
     later `rn_RestartSeg` (RootNode+$14) = `V!7` (validator);
  2. **if there is no expansion DeviceNode**: creates **DF0** (§1.2); otherwise the expansion chain serves
     as list head (and the length byte of the `fssm_Device` BSTR of each expansion node is
     **incremented by 1** before start [O; reason S: include the final NUL]);
     `di_DevInfo` := this head node;
  3. creates **RAM, CON, RAW, SER, PAR, PRT** (local routine);
  4. opens `intuition.library` (stored in **GV[92]**, used by global 50);
  5. **starts the handler of the head node** (DF0) by cliinit's FS routine (§1.3), and
     the Initial CLI's `pr_FileSystemTask` := its port;
  6. creates the assigns **SYS** (lock of `":"`), **LIBS, DEVS, FONTS, C, L, S** (lock of the directory
     of the same name, relative to the current directory = root of the boot volume [D]);
  7. starts the handler of any other expansion nodes;
  8. for **unit = 0..3**: skips the unit if the head node has the same unit **and**
     `fssm_Device` = `"trackdisk.device"`; otherwise creates `DF<n>` and starts its FS; **if the
     start fails** (Res1 = 0, drive absent): the node (then at the head) is **removed** from
     di_DevInfo, FSSM and node freed (freevec; the copy of the name is not freed);
  9. creates the resident segments "CLI", "Restart", "FileHandler" (DosInfo+$10 list, off
     topic here).

Final list on a bare A500, from head to tail: `[DF3] [DF2] DF1 → S → L → C → FONTS →
DEVS → LIBS → SYS → PRT → PAR → SER → RAW → CON → RAM → DF0`, then the **volume** of the boot
disk is added later by the file system (and "RAM DISK" by the RAM-handler, §5). [D for the order
of head insertion, O for each insertion]

No **NIL:** node (treated as a special case by deviceproc and findinput/findoutput). [O]

### 1.2 Exact values of the ROM nodes [O ROM]

All are created by **makedevnode** (global 85) then completed. Names in upper case.

| Name | dn_Type | dn_Task | dn_Lock | dn_Handler | dn_StackSize | dn_Priority | dn_Startup | dn_SegList | dn_GlobalVec |
|---|---|---|---|---|---|---|---|---|---|
| DF0 (DF1–3) | 0 | **port of the FS process** (written by cliinit after the reply) | 0 | 0 | 0 | 0 | BPTR FSSM | **0** | **not initialised** |
| RAM | 0 | 0 | 0 | BSTR `"L:RAM-HANDLER"` | **300** (longs) | 0 | 0 | 0 | **0** (⇒ makeglobvec) |
| CON | 0 | 0 | 0 | 0 | **700** (longs) | **5** | **0** | ROM segarray **V!5** (console-handler) | **BPTR of the Initial CLI's GV** (= dl_GV [D]) |
| RAW | 0 | 0 | 0 | 0 | 700 | 5 | **1** | V!5 | same as CON |
| SER | 0 | 0 | 0 | BSTR `"L:PORT-HANDLER"` | **800** | 0 | **0** | 0 | Initial CLI GV |
| PAR | 0 | 0 | 0 | `"L:PORT-HANDLER"` | **800** | 0 | **1** | 0 | Initial CLI GV |
| PRT | 0 | 0 | 0 | `"L:PORT-HANDLER"` | **1000** | 0 | **2** | 0 | Initial CLI GV |
| SYS | **1** | pr_FileSystemTask | locateobj(`":"`) | 0 | 0 | 0 | 0 | 0 | not init. |
| LIBS, DEVS, FONTS, C, L, S | **1** | pr_FileSystemTask | locateobj(name) (**may be 0** if the directory is missing: the node is created anyway) | 0 | 0 | 0 | 0 | 0 | not init. |

- Unit of dn_StackSize: **longs** for all the BCPL nodes above (cf. §13.3 of the spec:
  bytes only if dn_GlobalVec = −1). [O]
- **Correction of `dos-boot-sequence.md`**: the ROM DF0 node does **not** have `dn_SegList =
  rn_FileHandlerSegment` nor `dn_Handler = "File System"`. `"File System"` is the **name of the
  FS process**; dn_SegList stays **0** and the FS segment is taken directly from the segarray. [O]
- **FileSysStartupMsg of DF<n>** (getmem 4 cleared longs): fssm_Unit = n, fssm_Device = BSTR
  `"trackdisk.device"` (text followed by a NUL), fssm_Environ = BPTR of a ROM table,
  fssm_Flags = 0. Environment table (13 longs):
  `TableSize 12, SizeBlock 128, SecOrg 0, Surfaces 2, SectorPerBlock 1, BlocksPerTrack 11,
  Reserved 2, PreAlloc 11, Interleave 0, LowCyl 0, HighCyl 79, NumBuffers 5, BufMemType 3`. [O]
- The name `DFX` (ROM BSTR `{3,'D','F','X'}`) is copied by makedevnode then the 3rd character of the
  **copy** is replaced by `'0'+unit`. [O]

### 1.3 Start of a file system by cliinit (≠ global 112) [O ROM]

Local routine of cliinit, arguments: node, base segarray, ROM segarray.
- New segarray `getvec(4)` = `[3, V!1, V!2, V!6 ROM (FS)]`.
- **dn_SegList = 0** (ROM DF0 case): GV := **makeglobvec(segarray)** (dn_GlobalVec ignored);
  `createproc(segarray, **210 longs**, **pri 10**, BSTR **"File System"**, GV)`.
- **dn_SegList ≠ 0** (expansion node): stack = dn_StackSize (if ≤ 0 → 210); dn_GlobalVec = −1 ⇒
  C CreateProc (name = dn_Name as a C string, pri dn_Priority, seglist, stack in bytes); otherwise
  segarray `V!3` := dn_SegList, GV = dn_GlobalVec or makeglobvec if 0, `createproc(…, dn_StackSize,
  dn_Priority, dn_Name, GV)`.
- Startup packet (synchronous sendpkt): **Res2 = GV**, **Arg1 = not initialised** (frame
  residue), **Arg2 = dn_Startup** (FSSM), **Arg3 = 0**. Type/Res1 not initialised.
- Res1 ≠ 0 ⇒ **dn_Type := 0, dn_Task := FS port, dn_Lock := 0** (dos writes dn_Task) and returns
  the port; Res1 = 0 ⇒ returns 0 (dn_Task stays 0).

---

## 2. Q2 — Start of CON: / RAW:

- **Standard path**: open → deviceproc (102) → CON node, type 0, dn_Lock 0, dn_Task 0 →
  **global 112** (starthandler). No special path. [O]
- dn_SegList ≠ 0 ⇒ no loading; dn_GlobalVec = BPTR(Initial CLI GV) ⇒ BCPL branch with a
  **shared GV**: segarray `[3, V!1, V!2 of the calling process, V!5]`, `createproc(…, 700 longs,
  pri 5, BSTR "CON"/"RAW", shared GV)`. The process does the globin of kernel + dos + console-handler
  **into this shared GV** (the console-handler only defines global 1). [O]
- **Startup packet** (§3.1): Arg1 = **complete BSTR passed to deviceproc** (e.g.
  `"CON:0/0/640/200/AmigaDOS"`), Arg2 = dn_Startup (**0 = CON, 1 = RAW**), Arg3 = BPTR of the node,
  Res2 = GV. [O]
- **ROM console-handler side** (its global 1) [O]: reads dp_Port, Arg1, Arg2; **does not read Arg3**
  and **never writes dn_Task** ⇒ each deviceproc("CON:…") relaunches a process, **one window
  per Open**. Arg2 ≠ 0 ⇒ RAW mode; Arg2 < 0 ⇒ Arg1 is used as is as an existing window
  [O for the test, D for the meaning]. Parsing of the name: 4 decimal fields separated by `/` from the
  **5th character** (index 5 of the BSTR, hence after a 4-character prefix `CON:`/`RAW:`), then the
  title (the rest). Opening of the window by **global 50** (§3.4), then opendevice
  `"console.device"`. Failure (syntax, window, device) ⇒ **returnpkt(pkt, 0, 206)**
  (ERROR_BAD_STREAM_NAME). Success ⇒ **returnpkt(pkt, −1, ·)** (Res2 not meaningful), then taskwait
  loop. Unknown packet ⇒ Res2 = 209. A disk info request returns id_DiskType
  `'CON\0'` or `'RAW\0'` and id_VolumeNode = the window [O for the values, D for the packet type].
- **Second open `*` (NewCLI case)**: after a successful FINDINPUT on `CON:…`, the new CLI does
  `findoutput("*")`, which sends **ACTION_FINDOUTPUT to the same handler process** (pr_ConsoleTask :=
  fh_Type of the input stream) with **Arg3 = BSTR `"*"`** and **Arg2 = Result2 residue** (not a
  lock). The handler must accept it as a second stream on the existing window (fh_Interactive
  ≠ 0, Res1 = −1) and only terminate after the END of **all** its streams. Details:
  `bcpl-runtime-v34.md` §13.7. [O on the dos/NewCLI side, D on the handler side]
- `l:Newcon-Handler` and `l:Aux-Handler` behave the same at startup (read dp_Port, Arg1,
  Arg2, not Arg3). [O WB]

---

## 3. Q3 — Contract of the startup packet on the BCPL handler side

### 3.1 What dos sends (global 112) [O ROM]

| DosPacket field | Value |
|---|---|
| dp_Link, dp_Type, dp_Res1 | **not initialised** (frame residues) — do not interpret |
| dp_Port | reply port (the calling process, set by qpkt) |
| dp_Res2 | **BPTR of the handler's GV** (BCPL branch); residue in the C branch |
| dp_Arg1 | **complete** BSTR of the name given to deviceproc |
| dp_Arg2 | dn_Startup |
| dp_Arg3 | BPTR of the DeviceNode |

### 3.2 What the handler must do [O ROM + WB]
- Reply by **returnpkt** (global 49): **Res1 ≠ 0** = success (all the observed handlers
  return **−1**); **Res1 = 0** = failure, Res2 = error code (console 206, Port-Handler 202).
- On success, starthandler does **Result2 := dn_Lock** and returns the port; on failure returns 0
  and Result2 = the handler's Res2 (set by sendpkt). The Res2 of a success is **not** read.
- **dn_Task is never written by starthandler.** A handler that wants to be shared writes it
  itself via Arg3:
  - **Ram-Handler**: dn_Task := taskid(), then **clears `!4..!9`** (dn_Handler, dn_StackSize,
    dn_Priority, dn_Startup, dn_SegList, dn_GlobalVec) of its node. [O WB]
  - **Port-Handler** (SER/PAR/PRT): dn_Task := taskid() **after** a successful opendevice, and resets it
    to **0** when no stream is open any more (then terminates [S]). Arg2 chooses the device:
    0 `"serial.device"`, 1 `"parallel.device"`, other `"printer.device"`. [O WB]
  - ROM console-handler, Newcon, Aux: do not write it (one process per Open). [O]

### 3.3 Globals received by the handler [O ROM]
- **dn_GlobalVec > 0** (neither 0 nor −1): the indicated GV is **shared** (CON/RAW/SER/PAR/PRT, mounted
  NEWCON); the globin of V!1, V!2 and of the handler writes their globals into it (including global 1).
- **dn_GlobalVec = 0**: **new** GV by makeglobvec (RAM, DFx). All the runtime globals
  are reinstalled by globin of the segments V!1..V!3; undefined slots remain **not
  initialised** (no $474C… marker).
- In both cases the value is also transmitted in **dp_Res2** of the startup packet.

### 3.4 makeglobvec(segarray) — global 13 [O ROM]
- Walks entries `1..V!0` of the segarray; for each segment **chain**, reads the last
  long of each segment ("max", §3.1 of the BCPL spec). `max` = the largest, **floor 15**.
- `getvec(max + 50)`; failure ⇒ returns 0 (R2 = 103 left by getvec).
- Slot 0 = start + 50 longs; **GV[0] := max**; no other slot written (neither positive nor negative).
- Returns the **BPTR of slot 0**.

### 3.5 starthandler — global 112: clarifications [O ROM]
Complements §13.3 of the spec (which remains exact):
- the segarray is built from the `findsegarray()` **of the calling process** (entries 1 and 2);
- C branch: CreateProc(C name = BADDR(dn_Name)+1, dn_Priority, dn_SegList, **dn_StackSize bytes**);
  no segarray is allocated (its freeing on failure concerns 0);
- BCPL branch: if makeglobvec fails ⇒ no createproc ⇒ failure;
- Result2 := dn_Lock is set **before** sending the packet and again after a reply Res1 ≠ 0.

### 3.6 Other runtime globals used by the handlers
| Gl. | Name | Observed contract | Cert. |
|---|---|---|---|
| 6 | setio(iob, cmd, data, len, off) | iob BPTR; io_Command (+$1C, **word**) := cmd; io_Data (+$28) := **data×4** (data is a BPTR); io_Length (+$24) := len; io_Offset (+$2C) := 5th arg | O |
| 21 | **doio(iob)** | exec DoIO on BADDR(iob); returns **io_Error** (byte +$1F, unsigned) | O |
| 22 | sendio(iob, pkt) | iob.ln_Name (+$0A) := APTR(pkt); pkt.dp_Link := APTR(iob); exec SendIO. The reply arrives on the process's port ⇒ **taskwait then returns this pkt** (link via ln_Name) | O / D for the use |
| 31 | opendevice(iob, name, unit, flags) | name = BSTR **whose text must be followed by a NUL** (passed to OpenDevice as BADDR+1); before the call: ln_Succ/ln_Pred := 0, **ln_Name := name (C string)**, mn_ReplyPort := process port, mn_Length := 12; → **−1** if OpenDevice returns 0, otherwise **0** | O |
| 32 | closedevice(iob) | exec CloseDevice; result not meaningful | O |
| 36 | setflags(taskid, m) | Signal(mp_SigTask of the `taskid` port (+$10), **(m & 15) << 12**): bit 0 of m = CTRL-C … bit 3 = CTRL-F | O |
| 37 | testflags(m) | SetSignal(0, (m&15)<<12): tests **and clears**; → −1 if a bit was set, otherwise 0 | O |
| 41 | taskwait() | if **pr_PktWait** (process+$B4) ≠ 0: `jsr` call of that routine with **D0 = the process's MsgPort**, it must return the message in **D0**; otherwise: clears SIGF_DOS ($100), GetMsg on the process's port, Wait($100) as long as empty. → **BPTR(msg.ln_Name)** (= the packet) | O |
| 42 | qpkt(pkt) | dp_Link (= Message) must be > 0, otherwise returns 0, R2 = 101; message.ln_Name := pkt; ln_Succ/Pred := 0; destination = old dp_Port, **dp_Port := process port**; PutMsg; → 1 | O |
| 50 | **openwindow(x, y, w, h, title)** | Intuition OpenWindow (IntuitionBase = **GV[92]**, set by cliinit) with a NewWindow on the stack: Left/Top/Width/Height = args, Detail/BlockPen = $FF/$FF, IDCMP 0, **Flags $00021007** (SIZING, DRAG, DEPTH, ACTIVATE, NOCAREREFRESH, smart refresh), no gadgets/checkmark, **Title = title×4** (BPTR of a C-string buffer, not a BSTR), Screen/BitMap 0, **Min 120×50, Max $FFFF×$FFFF, Type WBENCHSCREEN (1)**; → APTR Window or 0 | O |
| 86 | **datstamp(v)** | DateStamp (C, global −25) into BADDR(v): v!0 days, v!1 minutes, v!2 ticks; **returns v**. (Unrelated to volumes.) | O |

---

## 4. Q4 — "File" globals and deviceproc

### 4.1 deviceproc(name) — global 102 [O ROM]
1. `splitname(prefix, ':', name, 1)` → `pos` = index after `:` (0 if no `:`).
2. *(retry loop)* `lock` := current currentdir; Result2 := 218.
3. `name` = `"NIL:"` (case-insensitive) ⇒ returns **0**.
4. **No prefix** (`pos` = 0) **or** name starting with `:` (`pos` = 2):
   - null current directory ⇒ port = **pr_FileSystemTask**, lock = 0;
   - otherwise port = **dn_Task of the volume** of the current lock (`fl_Volume`→`!2`), volume name stored
     for the requester; if leading `:` ⇒ **lock := 0** (root).
5. **Prefix**: search in di_DevInfo for the **first node of that name, any type** (under Forbid).
   - none ⇒ the prefix becomes the requester's volume name (the `:` replaced by NUL);
   - found: **lock := dn_Lock**; port := `dn_Task` if dn_Lock = 0, otherwise **fl_Task of the dn_Lock
     (+$0C)**; if port = 0: type 0 ⇒ **starthandler(node, complete name)**; other type ⇒ requester.
6. Port = 0 and a known volume name: first sends an **ACTION_FLUSH (27)** packet to the FS
   (pr_FileSystemTask), then requester `"Please insert volume" %S "in any drive"`; Retry ⇒ step 2;
   Cancel ⇒ Result2 := 218, returns 0. Without a volume name ⇒ returns 0 (R2 = 218).
7. Success: **Result2 := lock**, returns the port.

**Examples** [D from 1–7]:
| Name | Port | Result2 (lock → Arg1) |
|---|---|---|
| `RAM:t` (1st access) | starthandler(RAM) | **0** (dn_Lock of RAM) |
| `RAM:t` (afterwards) | dn_Task written by the Ram-Handler | 0 |
| `RAM DISK:t` | dn_Task of the volume | 0 |
| `LIBS:x` | fl_Task of the assign lock | **dn_Lock** of LIBS |
| `t` | handler of the current directory's volume | lock of the current directory |
| `:t` | same | **0** |
| `FOO:` unknown | requester "Please insert volume FOO" | 218 if Cancel |

### 4.2 Common "object" routine [O ROM]
`obj(name, action, arg3)`: `port = deviceproc(name)`; `lock = Result2`; port = 0 ⇒ returns 0.
Synchronous packet (sendpkt) to the port, type = action:
- **general case**: **Arg1 = lock**, **Arg2 = BSTR of the complete name** (not split: the handler must
  skip the prefix up to the `:`), **Arg3 = arg3**;
- **action 28 (SET_COMMENT) and 21 (SET_PROTECT)**: **Arg1 not initialised**, Arg2 = lock, Arg3 = name,
  **Arg4 = arg3** (comment / mask).
- Result = **dp_Res1**; Result2 = **dp_Res2**. Res1 = 0 ⇒ `errorreq(2, Result2, port)`
  (global 114); Retry ⇒ **everything starts again** (deviceproc included); otherwise returns 0.

### 4.3 Table of the globals [O ROM]
| Gl. | Name | Packet | Arg1 | Arg2 | Arg3 / Arg4 | Result |
|---|---|---|---|---|---|---|
| 108 | locateobj(name) | ACTION_LOCATE_OBJECT **8** | lock | name | **−2** (SHARED) | lock BPTR or 0 |
| 123 | lock(name, mode) | = locateobj (**mode ignored**) | | | | same |
| −11 | LVO Lock (C) | 8 | lock | name | **mode passed as is** | same |
| 90 | deleteobj(name) | ACTION_DELETE_OBJECT **16** | lock | name | not meaningful | ≠0 success |
| 125 | createdir(name) | ACTION_CREATE_DIR **22** | lock | name | not meaningful | **lock** of the new directory |
| 91 | rename(old, new) | ACTION_RENAME_OBJECT **17** | lock(old) | old | Arg3 = lock(new), Arg4 = new | ≠0 success |
| −23 / −24 | SetComment / SetProtection | 28 / 21 | — | lock | Arg3 name, Arg4 value | |
| 109 | freeobj(lock) | ACTION_FREE_LOCK 15 to the fl_Task | | | | R2 preserved |

- **rename**: deviceproc of both names; either null ⇒ 0; **different ports ⇒ Result2 = 215**
  (ERROR_RENAME_ACROSS_DEVICES), returns 0; packet failure ⇒ errorreq/retry as in §4.2.
- The C LVOs (DeleteFile → 90, CreateDir → 125, Rename → 91) convert the C strings into BSTRs
  then call the BCPL global. [O]

### 4.4 Use by the c: commands [O WB]
All BCPL (316-byte stub + module).
| Command | Globals (apart from the stub) | Remarks |
|---|---|---|
| MakeDir | 2, 10, 73, 74, 78, 108, 109, 125 | template `"/A"`; locateobj first ⇒ `"%S already exists"`; createdir then **freeobj of the returned lock**; failure `"Can't create directory %S"` |
| Assign | 2, 10, 30, 35, 39, 48, 68, 73, 74, 77, 78, 85, 88, 107, 109, 114, 115, 123 | template `"NAME,DIR,LIST/S,EXISTS/S,REMOVE/S"`; checks the directory by **ACTION_EXAMINE_OBJECT (23)**; creates the node by makedevnode then **dn_Task := fl_Task of the lock, dn_Type := 1, dn_Lock := lock** (lock kept); list "Volumes / Directories / Devices" |
| Delete | 2, 10, 29, 30, 37, 48, 51, 73–75, 78, 84 (private), 90, 104, 107–109, 114 | walks by EXAMINE_OBJECT (23) / EXAMINE_NEXT (24), deletes by deleteobj |
| Rename | 2, 10, 73, 74, 78, 91 | template `"FROM/A,TO=AS/A"`; `"Can't rename %s as %s"` |

---

## 5. Q5 — Specifics of RAM

- **ROM side**: nothing special beyond the §1.2 node (disk handler, new GV, stack 300). No
  "RAM DISK" string in the ROM. [O]
- **`l:Ram-Handler` side** (2 hunks: hunk 0 = small asm routine installed as **global 156**
  = exec CopyMem, hunk 1 = BCPL module max 158; it **redefines global 35** (parentdir) in
  its private GV). At startup [O WB]:
  1. node := Arg3; copies the BSTR **"RAM DISK"** into a getvec(12);
  2. creates the **root directory**: cleared getvec(45), type **2** (ST_USERDIR) at long `!2`,
     name at long `!9`, **date** (datstamp) at longs `!6..!8`; private globals 150–158 (151 =
     root, 157 = volume node, 158 = `'DOS\0'`);
  3. **dn_Task of the RAM node := taskid()**; clears `!4..!9` of the RAM node;
  4. **makedevnode("RAM DISK")** ⇒ **volume** node inserted at the head: dn_Task := taskid(),
     **dn_Type := 2**, dl_Lock := 0, dl_LockList := 0, **dl_DiskType := `'DOS\0'`**;
     **dl_VolumeDate left at 0** (cleared by makedevnode), slot `!9` not initialised;
  5. **returnpkt(pkt, −1, 0)** then taskwait loop.
- Consequences: after the first access, `RAM:` and `RAM DISK:` designate the same port; the RAM node's
  dn_SegList having been cleared by the handler, dos no longer knows the segment (the handler is never
  reloaded as long as dn_Task ≠ 0). [D]

---

## 6. Clean-room review

I certify, after a full re-reading of this document, that:
- it contains **no 68000 instruction sequence copied or paraphrased line by line**, neither from
  the ROM nor from the Workbench disk binaries, no disassembly excerpt, no opcode;
- the routines are described as **functional specifications** (inputs, outputs, observable
  effects and their order); the numbered steps of §1.1, §4.1 and §4.2 describe the order of the
  **visible effects** (structures written, packets sent, requesters), not the structure of the code
  (registers, branches and internal working variables are not described);
- the only values reproduced are ABI and interoperability elements: layouts (DeviceNode,
  volume, FileLock, DosPacket, NewWindow, IORequest), global numbers, action and
  error codes, stack sizes, priorities, disk environment constants, strings and templates
  needed for compatibility;
- the ROM was neither modified nor copied; the Workbench disk files were only extracted
  into the session scratch directory.
- **correction of 2026-10-29**: removed the 21 ROM addresses (dos `rt_Init`, `cliinit`, local
  routines, environment table, console-handler, makeglobvec, starthandler, deviceproc, "object"
  routine, "Address" column of the globals table); global numbers and contracts
  kept.
