# workbench-task-v34.md — `workbench.task` resident (wb 34.1): start-up, init, loop, end

> ANALYSIS track ("dirty"). Sources: the ROM `assets/kick34005.A500` (module `wb 34.1 (18 Aug
> 1987)`, ROMTag, module code and library stubs) and, on the
> disk `assets/wb133.adf`, `c:LoadWB` (extracted to scratch, to cross-check the interface).
> Same conventions as `handlers-v34.md` / `bcpl-runtime-v34.md`: **BPTR** = address/4,
> "R2" = `pr_Result2`, Process fields: `pr_MsgPort` +$5C, `pr_SegList` +$80, `pr_ConsoleTask`
> +$A4, `pr_CLI` +$AC, `pr_WindowPtr` +$B8.
>
> **Legend**: **[O]** directly observed · **[D]** deduced from converging observations ·
> **[S]** assumed. No ROM routine address is cited (removed on 2026-10-29); the
> positions relative to the ROMTag that remain are those imposed by `c:LoadWB` (program on the disk).
>
> This document describes behaviours, ABI layouts and constants. **No instruction
> sequence is reproduced or paraphrased.**

---

## 0. Executive summary

1. ROMTag: `rt_Flags = 0`, version 34, `rt_Type = 1` (NT_TASK), pri 0, name `"workbench.task"`,
   `rt_Init = ROMTag+26`. **Nothing in the ROM starts it** (no reference to its tag or to its
   name outside the tag itself): it only has to **be in the ResModules list** so that
   LoadWB's `FindResident("workbench.task")` finds it. [O]
2. ROMTag+26..+49 = **three 8-byte entry points** (selectors 0, 1, 2) that converge on
   the same `main(selector)`. Each entry begins with 4 bytes of "padding" that do
   nothing and can serve as a **segment link = fake BPTR**; selector 2 is LoadWB's. [O]
3. Entry via CreateProc: PC = `BADDR(seglist)+4`, **D0 = 0** (exec AddTask starts a task with
   all data/address registers at 0). The effective selector is 2 **only if D0 = 0
   on entry** (see §1.3). [O]
4. At the very beginning, **before any library is opened**: allocation of a global block of **$4F2
   bytes MEMF_CHIP|MEMF_CLEAR**, `pr_CLI := BPTR(block)` (fake CLI), **`ln_Name := "Workbench"`**,
   `SetTaskPri(self, 1)`, then (selector 2) `WaitPort/GetMsg` of LoadWB's message, read of 2
   fields, **immediate `ReplyMsg`**. [O]
5. Only then: OpenLibrary (version **0**) of dos, graphics, layers, intuition, mathffp,
   icon. A failure = recoverable Alert `$3103800x` then **dead-end Alert `$80008031`** (reboot);
   LoadWB has already had its reply. [O]
6. The Workbench **calls neither OpenWorkBench nor OpenScreen**: it opens a **backdrop window of
   type WBENCHSCREEN** (after GetScreenData), registers itself with **AlohaWorkbench(port)**, scans the
   DosList (devices then volumes → disk icons), arms a **5 s timer.device UNIT_VBLANK**
   ("free memory" title + disk rescan) then enters an **infinite loop**. [O]
7. It **never terminates**: no loop exit; a return from `main` would fall onto the dead-end
   Alert. CloseWorkBench → WBENCHMESSAGE/WBENCHCLOSE message: it closes its windows and stays
   alive; WBENCHOPEN reopens them. [O]
8. `pr_ConsoleTask` (+$A4): **never read** by the Workbench ROM code [D]; the reset to 0 by LoadWB
   is for the **child processes** (CreateProc inherits ConsoleTask from the parent) [D].

---

## 1. Q1 — ROMTag and entry area

### 1.1 ROMTag [O]

| Off. | Field | Value |
|---|---|---|
| +0 | rt_MatchWord | $4AFC |
| +2 | rt_MatchTag | address of the tag (itself) |
| +6 | rt_EndSkip | end of the module |
| +10 | rt_Flags | **$00** (neither COLDSTART nor AUTOINIT) |
| +11 | rt_Version | 34 |
| +12 | rt_Type | **1** (NT_TASK) |
| +13 | rt_Pri | 0 |
| +14 | rt_Name | → `"workbench.task"` |
| +18 | rt_IdString | → `"wb 34.1 (18 Aug 1987)\r\n"` |
| +22 | rt_Init | **ROMTag+26** (right after the structure) |

- No other place in the ROM contains the address of the tag, of its name or of `rt_Init`, nor the
  string `"workbench.task"`: neither strap nor dos launches it. **Correction** of the
  "*(inferred)*" hypothesis in `boot-sequence.md` ("strap explicitly brings up workbench.task"): it is false,
  only `c:LoadWB` starts it. [O]
- ABI consequence: exec must put **all** ROMTags in ResModules (including those with
  `rt_Flags = 0`), without initialising them. [O for the ROM; FindResident contract]

### 1.2 Area ROMTag+26 .. ROMTag+49 [O]

Three entry points of **8 bytes** each, at ROMTag+26, +34, +42. Each one has the effect of
setting a **selector** (0, 1 or 2) and then calling the Workbench's main function (`main`) with
this selector as its **sole argument** (long). If `main` returned, the dead-end Alert of §2.6
would follow.

| Entry | Selector | Who |
|---|---|---|
| ROMTag+26 = rt_Init | 0 | InitResident (not used in practice) |
| ROMTag+34 | 1 | no one observed |
| ROMTag+42 | **2** | **LoadWB (CreateProc)** |

"Fake segment": at ROMTag+42 the **link long is 0** (end of the segment chain) and the entry
point is at **ROMTag+46**. But, since the original tag is aligned on 4, ROMTag+42 is **not
aligned on 4** (≡ 2 mod 4); see §1.3.

### 1.3 What LoadWB actually passes to CreateProc [O WB + O ROM]

- LoadWB computes `seglist = (address_ROMTag + 26 + 16) >> 2` by **arithmetic shift** (low
  bits truncated) → `BADDR(seglist)` = **ROMTag+40**, **not** ROMTag+42.
- dos CreateProc (C form, global −18) launches the task with AddTask with **initial PC =
  BADDR(seglist)+4** (= ROMTag+44) and **final PC** = its process-end routine. The
  "link" read at BADDR(seglist) is not followed at start-up. [O dos]
- Entered at ROMTag+44 (in the middle of the third entry point), the ROM code has the **effect
  `D0 := D0 OR 2`** (and not "D0 := 2"). The selector is therefore 2 **if and only if the useful bits of D0 are 0
  on entry**; same mechanism for blocks 1 and 2 (OR 1, OR 0). [O]
- exec AddTask builds the initial frame with **15 longs at 0 (D0–D7/A0–A6)**,
  an SR at 0 and the initial PC, below the pushed final PC. ⇒ D0 = 0, **A6 = 0** on entry. [O]
- **Requirement for a reimplementation**: a C process started by CreateProc must enter with
  **D0 = 0** (and assume nothing else about the registers); otherwise, selector 3 ⇒ the Workbench does not
  read LoadWB's message and **LoadWB stays blocked** in WaitPort. [D]

### 1.4 InitCode or LoadWB? [O]

`rt_Flags = 0` ⇒ not initialised by InitCode(RTF_COLDSTART) nor by any other pass. It is
only started by LoadWB (FindResident + CreateProc). Selector 0 (rt_Init, call by
InitResident) would run the Workbench in the caller's context: no caller exists.

---

## 2. Q2 — Process start-up

### 2.1 Entry convention [O]

Nothing special apart from D0 (§1.3): no register argument used, no dos start-up
packet (it is not a BCPL process: segarray `[2, kernel, dos, seglist]` of the C form, direct
entry into the code). The Workbench code is compiled (C, "small data" model) with **A6 =
pointer to its globals** (= block+$40); all its library stubs read the bases from these
globals. [O]

### 2.2 `main` initialisation sequence, in order [O]

1. **AllocMem($4F2, MEMF_CHIP|MEMF_CLEAR)** (global block; via SysBase read at $4); failure ⇒
   Alert `$31010000` (AN_Workbench|AG_NoMemory) then dead-end (§2.6).
2. Globals = block+$40; SysBase stored in the globals.
3. **FindTask(NULL)** → self; **`pr_CLI := BPTR(block)`**: the first $40 bytes of the block (zero)
   serve as a **fake CommandLineInterface**.
4. **SetTaskPri(self, 1)**.
5. **`self->tc_Node.ln_Name := "Workbench"`** (string in the ROM). ⇒ the renaming takes place **before**
   waiting for the message, hence before the reply to LoadWB; LoadWB's `FindTask("Workbench")` always
   succeeds. [O]
6. **If selector = 2**: `WaitPort(&pr_MsgPort)`, `GetMsg(&pr_MsgPort)`, read of
   `msg+$18` (→ "debug flag") and `msg+$14` (→ copied into the fake CLI's **`cli_CommandDir`**,
   block+8), then **`ReplyMsg(msg)` immediately**.
7. The "flag" (msg+$18 if selector 2, otherwise the selector itself) is stored in the globals
   (+$47A); if it is 1, a mode bit is set (globals byte +$23, bit 7). No reader
   of these two values was found [D] → effect of `-debug` unknown/inactive [S].
8. **OpenLibrary(name, 0)** in this order, base stored in the globals:

   | Order | Library | Global | Alert on failure (recoverable) |
   |---|---|---|---|
   | 1 | `dos.library` | +$2B6 | `$31038002` (sic: "graphics" code) |
   | 2 | `graphics.library` | +$2AA | `$31038002` |
   | 3 | `layers.library` | +$2BE | `$31038003` |
   | 4 | `intuition.library` | +$2AE | `$31038004` |
   | 5 | `mathffp.library` | +$2BA | `$31038005` |
   | 6 | `icon.library` | +$2B2 | `$31038009` |

   Each failure: Alert with the code above (dead-end bit **not** set) then dead-end Alert
   `$80008031` (§2.6). icon.library is not in ROM: it comes from `LIBS:` via ramlib (LoadWB has
   already opened it on its side, see §2.4).
9. Then the initialisations of §3.

### 2.3 LoadWB's message (layout) [O WB + O ROM]

| Off. | Size | Contents | Read by the Workbench |
|---|---|---|---|
| +$00 | 20 | `struct Message` (mn_ReplyPort +$0E = LoadWB's `pr_MsgPort`) | no (only ReplyMsg uses it) |
| +$14 | 4 | **BPTR to a copy of LoadWB's command path** (list of `{BPTR next, lock}` pairs duplicated with DupLock, 8-byte nodes) | **yes** → the fake CLI's `cli_CommandDir` |
| +$18 | 4 | `-debug` flag (1 if `LoadWB -debug`, otherwise 0) | **yes** (§2.2 point 7) |

- Total size **28 bytes** (on LoadWB's stack). `mn_Length` is not initialised by
  LoadWB and is not read by the Workbench. [O]
- The message is posted with PutMsg on the **MsgPort returned by CreateProc** (= the new
  process's `pr_MsgPort`). [O WB]

### 2.4 When is LoadWB released? [O]

**Immediately after the message is read**, before any library, the window
or the screen is opened. LoadWB then does `FindTask("Workbench")`, sets its `pr_ConsoleTask` to 0, and exits
(`delay` option: Delay(150)). For the record, on the disk side, LoadWB 1.3.3 also opens icon.library
(exit code 20 if absent) and intuition.library, and installs with **SetFunction** a replacement for
intuition vector **−276 (SetWindowTitles)** (version text "1.3.3"; strings stored
obfuscated) before closing intuition again. [O WB]

### 2.5 What if an init fails? [O]

LoadWB has **already** received its reply (point 6 before point 8). Any later failure (library, memory,
font, screen, timer) causes no additional reply: it is a **dead-end Alert ⇒
reboot**. There is no "clean failure" path that would return control to the CLI.

### 2.6 Abort routines [O]

- Generic "fatal": **Alert(`$80008031`)** (bit 31 = AT_DeadEnd) called with the
  SysBase read at $4; it does not return. Called after each recoverable Alert below and if
  `main` returned.
- Out of memory: Alert `$31010000` then fatal.
- Font: Alert **`$B1000001`** (dead-end) if OpenFont fails.
- timer.device: Alert **`$B1048015`** (dead-end, AG_OpenDev, AO_TimerDev) if OpenDevice fails
  or returns io_Error ≠ 0.

---

## 3. Q3 — What the Workbench does once launched (order of the main calls)

### 3.1 Initialisation (continuation of `main`) [O unless stated]

| # | Observable effect (library calls) |
|---|---|
| 1 | **AllocSignal(−1)** (a single signal); two **public** 34-byte MsgPorts in the globals, **A** (+$38E) and **B** (+$3B0): ln_Type 4, ln_Name `"Workbench"`, mp_Flags 0 (PA_SIGNAL), mp_SigBit = this signal (**shared**), mp_SigTask = self; **AddPort(A)**, **AddPort(B)**. A = reply port (tools' WBStartup, timer); B = IDCMP/Workbench port. |
| 2 | **GetPrefs(buf, 1)** (only reads the `FontHeight` byte); TextAttr `{"topaz.font", FontHeight, 0, 0}`; **InitRastPort** (private rastport); **CloseFont** of any previous font; **OpenFont** (failure ⇒ $B1000001); **SetFont**. Re-run on NEWPREFS. |
| 3 | internal allocations (AllocMem MEMF_CHIP\|CLEAR; failure ⇒ $31010000), construction of the menus (**TextLength** measurements). [D for the role] |
| 4 | 3 empty lists (NewList); **AllocWBObject** (icon) = root object named `"Workbench"`; then opening of the **backdrop window** (§3.2); root added to the list (AddTail) and refresh. Failure ⇒ $31010000 + fatal. |
| 5 | AllocMem + **InitGels** (GelsInfo for icon dragging), attached to the screen's RastPort (Screen+$68 = `RastPort.GelsInfo`). |
| 6 | walk of the object lists (preparation) [D] |
| 7 | `DosInfo := BADDR(DOSBase->dl_Root->rn_Info)` (DOSBase+$22 → RootNode+$18); **DosList scan** (§3.3) |
| 8 | processing of the internal queue (Disable/AddHead/RemTail/Enable, GetMsg) [D] |
| 9 | **AlohaWorkbench(port B)** (intuition −402) |
| 10 | **OpenDevice("timer.device", unit 1 = UNIT_VBLANK, req, 0)** on a 40-byte timerequest (allocated with a 2-byte header marked 4), `mn_ReplyPort = port A`, `io_Command = 9` (TR_ADDREQUEST); then **first tick** (§3.4) |
| 11 | **main loop** (§3.5), never returns |

Order of the modules opened implicitly: the **Workbench screen** is only opened at #4, at the time
of the WBENCHSCREEN-type GetScreenData/OpenWindow. The Workbench calls **neither OpenWorkBench, nor
OpenScreen, nor CloseWorkBench** (no stub to −210/−198/−78 in the module). [O]

### 3.2 Backdrop window [O]

- **GetScreenData(buf, 346 = $15A, WBENCHSCREEN (1), NULL)** (intuition −426); result 0 ⇒ the
  root has no window ⇒ $31010000 + fatal. Whether GetScreenData opens the WB screen if it is closed
  is intuition behaviour to be checked in the AutoDocs [S]; the following OpenWindow, of type
  WBENCHSCREEN, opens it in any case if necessary [D, public intuition contract].
- NewWindow (public layout): LeftEdge 0, **TopEdge = sc_BarHeight+1**, **Width = sc_Width**,
  **Height = sc_Height − (BarHeight+1)** (values read from the copy of Screen: BarHeight byte
  +$1E, Width +$0C, Height +$0E), DetailPen/BlockPen 0, **IDCMPFlags 0** at opening,
  **Flags $02000B40** (WBENCHWINDOW \| BORDERLESS \| BACKDROP \| REPORTMOUSE \| SIMPLE_REFRESH),
  FirstGadget 0, CheckMark 0, Title 0, Screen 0, BitMap 0, **MinWidth 90, MinHeight 40,
  MaxWidth/MaxHeight −1**, **Type 1 (WBENCHSCREEN)**.
- After **OpenWindow**: `wd_UserPort := port B` (port **shared** by all the Workbench's
  windows) then **ModifyIDCMP(win, $C076E \| extra)** — extra = **$1C000** (NEWPREFS \|
  DISKINSERTED \| DISKREMOVED) for the backdrop ⇒ **$DC76E**. Then **SetWindowTitles**(win, title,
  screen title buffer), **SetPointer** (if a "busy" mode is active), **SetMenuStrip**, and
  finally **SetWindowTitles(win, "Workbench", −1)**. The window and its screen are stored
  (globals +$4A8 / +$4A4).
- Drawer/disk windows use the same routine with **Flags $0200027F**
  (WBENCHWINDOW \| REPORTMOUSE \| SIMPLE_REFRESH \| SIZING \| DRAG \| DEPTH \| CLOSE \| SIZEBRIGHT
  \| SIZEBBOTTOM) and the object's name as title. None is opened at start-up apart from
  reopening (§4.2).

### 3.3 Disk scan (DosList → icons) [O]

Walk of `DosInfo->di_DevInfo` (dn_Next chain) **under Forbid** (direct increment of
ExecBase's `TDNestCnt`, then Permit). Two phases:

1. **Devices** (dn_Type 0) having `dn_Task ≠ 0`: the Workbench itself sends a packet
   **ACTION_INHIBIT (31), Arg1 = 0**; if Res1 ≠ 0, and if `dn_Startup ≠ 0` and
   `fssm_Device ≠ 0` and **FindName(SysBase->DeviceList, name of the exec device)** succeeds, the
   device is kept ("device" state, 4).
2. **Full rescan** (also invoked on each 5 s tick, on DISKINSERTED/DISKREMOVED and on
   WBENCHOPEN):
   - for each **volume** (dn_Type 2): unknown entry ⇒ new (state 2 "new");
     known with `dl_Task ≠ 0` ⇒ state 3 ("active", dl_Task stored); otherwise state 1 ("removed");
   - entries not seen again ⇒ deleted;
   - for the kept devices: packet **ACTION_DISK_INFO (25)**, Arg1 = BPTR to an InfoData; if
     `id_DiskType` ∉ { `'DOS\0'` ($444F5300), −1 (no disk) } ⇒ special icon (object type 7)
     named `"<device>:" + 4 characters of the DiskType` (non-DOS / unreadable disks);
   - **new volume**: search for the device whose `dn_Task == dl_Task`, packet
     **ACTION_LOCATE_OBJECT (8)** (Arg1 = 0, Arg2 = BSTR of the name, Arg3 = **−2** = SHARED) to the
     `dl_Task` → root lock; if `dl_Task = 0` ⇒ R2 := **218** and state 1; on failure ⇒ dos
     `errorreq` requester (§3.6) then retry or give up. Then **Info(lock, InfoData)**,
     **CurrentDir(lock)**, **GetWBObject("Disk")** (= `Disk.info` of the root); absent ⇒
     **AllocWBObject** + default image; the icon is added to the backdrop. Volume already open ⇒
     **WindowToFront** of its window.
- The packets are sent **by the Workbench itself** (not via dos): DosPacket in its
  globals, `dp_Port` = **its `pr_MsgPort`**, `mn_Node.ln_Name` = packet, PutMsg to the
  handler's port, wait with **Wait(signal of pr_MsgPort)** until GetMsg, result Res1, **R2 :=
  Res2**. [O]
- `pr_WindowPtr` is temporarily set to **−1** while a `.info` file is being written
  (dos requesters suppressed) then reset to 0. [O]

### 3.4 5-second tick [O]

On each return of the timerequest (and once at start-up): if the Workbench is not "closed":
disk rescan (§3.3), then **AvailMem(0)**; if the value changes, the screen title is reformatted
with **RawDoFmt** using `"Workbench release 1.2.  %ld free memory"` (global buffer +$3DA) and applied
to the windows (SetWindowTitles, which LoadWB 1.3.3 has hooked). Then the request is sent again:
`tv_secs = 5`, `tv_micro = 0`, **SendIO** (asynchronous, reply on port A).
Details ("message displayed" flag, initial value −1, windows concerned): see §6.4.

### 3.5 Main loop [O]

**Infinite** loop: drain **port B** (each IntuiMessage → dispatcher by bit number of
`im_Class`, 23 entries); except in a particular mode, drain **port A**: each message carries a **type
word just before it** (2-byte header of its allocation): **2 = WBStartup** returned from a
tool (UnLoadSeg of the segment, UnLock/freeing of the arguments, FreeMem 42 bytes), **4 =
timerequest** (§3.4); if no message was processed ⇒ **Wait(1 << shared signal)**.

IDCMP classes handled: NEWSIZE/REFRESHWINDOW, MOUSEBUTTONS (SELECTDOWN $68 / SELECTUP $E8,
**DoubleClick**), MOUSEMOVE, GADGETDOWN/UP, INACTIVEWINDOW, MENUPICK, CLOSEWINDOW, MENUVERIFY,
NEWPREFS (font + refresh), DISKINSERTED/DISKREMOVED (rescan), **WBENCHMESSAGE** (§4.1),
INTUITICKS; the others are simply returned with ReplyMsg.

### 3.6 Other interfaces used (to size the implementation) [O]

- **dos**: Open, Close, Read, Write, DeleteFile, Lock, UnLock, DupLock, Examine, ExNext, Info,
  CreateDir, CurrentDir, IoErr, **CreateProc**, **LoadSeg**, **UnLoadSeg**, DateStamp, and the
  private entry **DOSBase−28** (§3.7).
- **exec**: Alert, Disable/Enable, Forbid/Permit, AllocMem/FreeMem, AvailMem, Insert, AddHead,
  AddTail, Remove, RemHead, RemTail, FindName, FindTask, SetTaskPri, Wait, AllocSignal, AddPort,
  PutMsg, GetMsg, ReplyMsg, WaitPort, OpenLibrary, CloseLibrary, OpenDevice, SendIO, RawDoFmt;
  direct access to `TDNestCnt` (ExecBase+$127) and `DeviceList` (ExecBase+$15E).
- **graphics**: BltBitMap, TextLength, Text, SetFont, OpenFont, CloseFont, AddBob, DrawGList,
  InitGels, RemIBob, SortGList, InitRastPort, SetRast, Move, Draw, BltClear, RectFill, Flood,
  SetAPen, SetDrMd, LockLayerRom, UnlockLayerRom, InitTmpRas, and vectors −504/−510/−516/−528/
  −534 (regions: AndRect/OrRect/NewRegion/ClearRegion/DisposeRegion according to the `.fd` order) [D].
- **intuition**: ClearMenuStrip, ClearPointer, CloseWindow, DisplayBeep, DoubleClick, GetPrefs,
  ModifyIDCMP, OffMenu, OnMenu, OpenWindow, SetMenuStrip, SetPointer, SetWindowTitles,
  WindowToFront, **AlohaWorkbench (−402)**, **GetScreenData (−426)**, −450 (ActivateWindow),
  −462 (ActivateGadget), −468 (NewModifyProp) [names according to the V33/V34 `.fd` order].
- **layers**: BeginUpdate, EndUpdate, LockLayers, UnlockLayers, WhichLayer.
- **icon**: GetWBObject, PutWBObject, FreeFreeList, FreeWBObject, AllocWBObject, AddFreeList,
  FindToolType, BumpRevision.
- **timer** (base = io_Device): SubTime (−48).
- Launching a tool: CurrentDir(directory), **LoadSeg(name)**, stack = `do_StackSize` or
  **4096** by default, pri = ToolType **`TOOLPRI`** or **0** by default, **CreateProc(name, pri,
  seglist, stack)**, then a 40-byte **WBStartup** message (type-2 header): `mn_ReplyPort =
  port A`, `sm_Process` = port returned by CreateProc, `sm_Segment`, `sm_NumArgs`, `sm_ArgList`
  (8-byte `{lock, name}` pairs); **PutMsg(sm_Process, msg)**.

### 3.7 Private entry DOSBase−28 [O]

The dos V34 vectors are pairs "load the global number into D0; branch to the common
dispatcher" (6 bytes). **DOSBase−28** lands on the branch of vector −30: it is a call to
**"BCPL global no. D0"** with the arguments in D1..D4. The Workbench uses it for
**errorreq (global 114)**: `D1 = 3, D2 = BPTR of the volume` ("Please insert volume …") and
`D1 = 2, D2 = BPTR of a lock, D3 = its fl_Task` (errors on an object). Return 0 ⇒ retry;
non-zero ⇒ give up (consistent with the "TRUE = give up" correction of step 3). [O]

---

## 4. Q4 — End of the Workbench, CloseWorkBench, `pr_ConsoleTask`

### 4.1 No termination [O]

- The main loop has **no exit condition**; no global freeing, no final
  CloseLibrary/RemPort exists in `main`. A return from `main` would execute the dead-end
  Alert `$80008031`. ⇒ **the Workbench process lives until reboot**.
- **WBENCHMESSAGE** (IDCMP $00020000, received on port B thanks to AlohaWorkbench): the message is
  **returned (ReplyMsg) first**, then depending on `im_Code`:
  - **1 = WBENCHOPEN**: for each object marked "window to reopen", reopening (root ⇒
    same path as §3.2; drawer ⇒ OpenWindow Flags $0200027F); if the root does not reopen,
    the operation stops. Then "closed" state cleared, refreshes, **disk rescan**.
  - **other (2 = WBENCHCLOSE)**: for each object that has a window: under Forbid, removal of the
    IntuiMessages pending for this window on the shared port, **ModifyIDCMP(win, 0)**,
    Permit, **ClearMenuStrip**, **CloseWindow**; the object is marked "to reopen". "Closed" state
    set (the 5 s tick then does nothing more).
- So it is intuition (CloseWorkBench/OpenWorkBench, called by other programs) that is in control;
  the Workbench merely closes/reopens its windows so that the screen can close. [O for
  the Workbench; D for the sequence on the intuition side]

### 4.2 `pr_ConsoleTask` (+$A4) set to 0 by LoadWB [D]

- The Workbench ROM code **neither reads nor writes** its own process's `pr_ConsoleTask` (the accesses
  at a displacement of $A4 found concern its own object structures, not a Process). [D, by
  exhaustive search of the accesses]
- CreateProc (dos) **copies ConsoleTask / FileSystemTask / WindowPtr from the parent process** into the
  child (`bcpl-runtime-v34.md` global 33). The Workbench, created by LoadWB, therefore inherits the console
  of the CLI that launched LoadWB; by resetting it to 0, LoadWB guarantees that **the tools launched from
  the Workbench** (children of the Workbench process) do not inherit a console that will disappear at the
  `EndCLI` of the startup-sequence (`Open("*")` fails cleanly instead of targeting a dead
  handler). [D]
- Order: the reset to 0 takes place **after** the Workbench's reply, hence while the Workbench
  is opening its libraries; no tool is launched before then, so the race has no effect. [D]

---

## 5. Test vectors (observable values)

| Test | Expected |
|---|---|
| FindResident("workbench.task") | the module's tag; rt_Flags 0, rt_Type 1, rt_Pri 0, rt_Version 34 |
| LoadWB: seglist | `(tag+42) >> 2` ⇒ initial PC `tag+44`, D0 = 0 on entry |
| After the reply to LoadWB | `FindTask("Workbench")` ≠ 0, pri 1, `pr_CLI` ≠ 0 |
| Public ports | 2 ports named `"Workbench"`, same pri 0; with an AddPort via Enqueue, FindPort returns the **first added = port A** [D] |
| Screen | Workbench screen open, 1 full-width backdrop window below the title bar |
| Screen title | `"Workbench release 1.2.  <n> free memory"` (without LoadWB's 1.3.3 patch) |
| DOS disk inserted in DF0: | the volume's `Disk.info` icon in the backdrop (≤ 5 s or on DISKINSERTED) |
| missing library (e.g. icon) | Alert `$31038009` then dead-end `$80008031`, LoadWB already finished |

---

## 6. Version / Last Error menus and screen title

Sources: ROM (wb module, landmarks below) and `c:LoadWB` from `wb133.adf` (code hunk no. 4,
164 bytes = the SetWindowTitles replacement); `libs:version.library` from the same disk (header
`versionlib 34.34 (05 OCT 1990)`). Globals = the $4F2-byte block (§2.2), addressed below as
"G+off".

### 6.1 Shared state: two title buffers and one flag byte [O]

| Global | Role |
|---|---|
| **G+$3DA** | buffer of the **"memory" title** (text produced by RawDoFmt at the tick, §6.4). Zero at start (MEMF_CLEAR block). It is also the screen title passed when **each** Workbench window is opened (`SetWindowTitles(win, name, G+$3DA)`, §3.2). |
| **G+$2EE** | pointer to the buffer of the **last message** (errors, Version…). 0 at start; allocated lazily at the first message: **AllocMem(80, 0)** (MEMF_ANY, not cleared), and if it fails, fallback to an internal buffer G+$160. Never freed. No length bound when formatting (80 bytes). |
| **G+$2F2** | last AvailMem value displayed (comparison at the tick). |
| **G+$22** (flag byte) | bit 0 = Workbench "closed" (CloseWorkBench, §4.1); **bit 1 = title locked** (during Rename input); **bit 2 = "a message is displayed"**. |

### 6.2 Common "show a title" routine [O]

Signature (C convention, stack): `ShowTitle(fmt, arg1, arg2, arg3, arg4, arg5)`. Behaviour:

1. **`fmt == G+$3DA` (restoring the memory title)**: if bit 1 (lock) ⇒ nothing. Otherwise, if bit 2
   is **clear** ⇒ nothing. Otherwise bit 2 := 0 and the memory title is applied (step 4 with G+$3DA).
2. **Other `fmt` (message)**: if bit 2 is **already set** ⇒ **nothing** (the first message displayed
   wins until the next restoration). Otherwise bit 2 := 1; obtain the G+$2EE buffer (allocation
   if needed, §6.1).
3. If `fmt` **differs** from the message buffer: **DisplayBeep(WB screen)** (screen stored at G+$4A4),
   then **RawDoFmt(fmt, &arg1, putchar "store the byte", buffer)** (arguments = consecutive long
   words on the stack). If `fmt` **is** the buffer itself: neither beep nor reformatting.
4. Application: for **each object of the master list G+$24** (list to which the root `"Workbench"`
   is added with AddTail, §3.1 #4) whose drawer-data pointer (object+$4C) is non-null
   **and** whose window (data+$1A4) is non-null:
   **`SetWindowTitles(window, (char *)−1, buffer)`** — window title **unchanged**, **screen**
   title = buffer. Hence **the backdrop + all open drawer/disk windows**.

Restoration of the memory title (`ShowTitle(G+$3DA)`) is called: **at the start of every MENUPICK** (before
the item is dispatched), on **SELECTDOWN** (left click), by the tick (§6.4),
and on entry to Rename (no effect, lock set).

### 6.3 Special/Version (menu code $F882 = menu 2, item 4, no sub-item) [O]

1. (Restoration of the memory title, §6.2, common to every MENUPICK: clears bit 2.)
2. **Kickstart version**: read from the **ROM header**, not from a library base:
   ROM base = `$1000000 − ROM size` (size = ROM footer field, located 20 bytes before the end
   of the 24-bit space; `$00040000` here) = $FC0000; unsigned
   words at **base+$0C** (= 34) and **base+$0E** (= 5), extended to longs. (exec.library itself
   is at 34.2: it is **not** `SysBase->lib_Version/lib_Revision`.)
3. **Workbench version**: **OpenLibrary("version.library", 0)**; on success, unsigned words
   **lib_Version (+$14)** and **lib_Revision (+$16)** of **this base**, then **CloseLibrary**. If
   the open fails: **−1 and −1** (displayed "-1.-1"). No internal constant: with the
   `libs:version.library` of WB 1.3.3 (34.34) one gets "34.34"; with another disk, another
   value. OpenLibrary may load the library from LIBS: (ramlib) [D, exec contract].
4. **`ShowTitle("Kickstart version %ld.%ld. Workbench version %ld.%ld", 34, 5, wbVer, wbRev)`**
   ⇒ screen beep, formatting into the G+$2EE buffer, `SetWindowTitles(w, −1, buffer)` on all
   open WB windows (§6.2 step 4). The window title is not touched.
5. **Persistence**: bit 2 stays set ⇒ the **5 s tick no longer updates the memory title**
   (§6.4) ⇒ the Version text stays displayed **indefinitely**, however the memory
   changes, **until the next left click (SELECTDOWN) or the next MENUPICK** in a Workbench
   window. These events re-apply the **current** contents of G+$3DA (the memory value
   formatted at the last tick that wrote, hence potentially stale until the next tick). [O]
   The "flag that blocks the update" is therefore **bit 2 of G+$22** (and bit 1 during a
   Rename).

### 6.4 5 s tick: details of the memory title (complements §3.4) [O]

- When the timer is opened (§3.1 #10): **G+$2F2 := −1**, then an immediate first tick. Before this
  first tick, the screen title passed to the windows is **the empty G+$3DA** (null string).
- On each tick: if bit 0 (closed) ⇒ neither rescan nor title. Otherwise disk rescan; then **if bit 2
  is set ⇒ no title update** (message displayed). Otherwise **AvailMem(0)** (MEMF_ANY,
  total free) compared with **G+$2F2**; if **different**: bit 2 := 1, G+$2F2 := value,
  **RawDoFmt("Workbench release 1.2.  %ld free memory", value) → G+$3DA**, then
  `ShowTitle(G+$3DA)` (which clears bit 2 and applies it to **all** open WB windows,
  §6.2 step 4 — not only the backdrop). Equal ⇒ nothing is re-applied.
- Rename: when its input window is opened, bit 1 := 1, **G+$2F2 := 0** (forces the next
  refresh), copy of `"Enter the new name.  Press return when done."` into G+$3DA,
  applied as screen title to the input window; at the end, bit 1 := 0 and a tick is
  executed immediately (without resending the timer request), which rewrites the memory title. [O]

### 6.5 Special/Last Error (menu code $F822 = menu 2, item 1) [O]

1. Restoration of the memory title (start of MENUPICK, bit 2 := 0).
2. **`ShowTitle(*(G+$2EE))`**: the format passed **is the last-message buffer itself** ⇒
   **no beep, no reformatting**; the **last message displayed** (whatever it is: error,
   Version text, "cannot be moved…", etc.) is re-applied as the screen title of all
   WB windows, and bit 2 is set again (same persistence as §6.3 point 5). It is **not** a
   re-read error code: it is the text already formatted at the time of the error. E.g.: Version then Last
   Error ⇒ shows "Kickstart version 34.5. Workbench version 34.34" again.
3. No message produced yet (G+$2EE = 0): the buffer is allocated at this point, then, as the format
   (0) differs from the buffer, **beep** + RawDoFmt with a format at address 0 [O] ⇒ in practice an
   empty title if the byte at $0 is 0 [S]. A reimplementation may display an empty string.
4. Origin of the error messages [O]: an error routine takes (action index, name); it
   formats into an 80-byte local buffer the action chosen from the table below (with the name
   for `%s`), then calls `ShowTitle("Error while %s: %ld", action, IoErr())` — the code is
   **dos IoErr()** at the time of the error. Table (index → text): 0 `"examining directory"`,
   1 `"accessing %s"`, 2 `"opening %s"`, 3 `"reading"`, 4 `"writing"`, 5 `"moving %s"`,
   6 `"removing %s"`, 7 `"examining %s"`, 8 `"writing %s"`. E.g.: `"Error while opening Foo: 205"`.
   Other direct messages via ShowTitle (not detailed here): `"'%s' cannot be moved out of its
   window"`, `"Do not use '%lc' in names"`, `"Cannot read info file %s"`.

### 6.6 SetWindowTitles replacement installed by LoadWB 1.3.3 [O WB]

Set-up: LoadWB allocates **162 bytes MEMF_PUBLIC|MEMF_CLEAR** (never freed), copies
hunk no. 4 into it, does **SetFunction(IntuitionBase, −276, copy+4)** and stores the old vector in the
first long of the copy (the replacement ends by jumping to the old vector, A0/A1 preserved,
**A2 possibly substituted**). Before the copy, two strings of the hunk are **de-obfuscated in
place**: each byte is **XOR $9E** up to the 0 byte (the terminating 0 is not encrypted).

Strings of the patch (in clear):
- unencrypted reference: `"Workbench release 1.2."` (22 bytes);
- encrypted 1: `"We made Amiga, T"` (16 bytes);
- encrypted 2: `" Still a Champion"` (17 bytes, leading space).

Observable behaviour (only the **screen title**, argument A2, is examined; the window title
is never modified):
1. A2 = NULL or −1 ⇒ original call unchanged.
2. If the byte **A2[20] == '2'** **and** the string **starts with** `"Workbench release 1.2."` (22
   bytes compared) ⇒ the caller's string is **modified in place**: A2[17] := `'.'`,
   A2[18..21] := 4 spaces. `"Workbench release 1.2.  884392 free memory"` becomes
   **`"Workbench release.      884392 free memory"`** ("release." followed by **6 spaces**: the 4
   written + the 2 from the format), then the original call with this same pointer. Since the WB rewrites
   G+$3DA with RawDoFmt on each memory change, the edit is redone on each tick that
   writes; a second pass over an already edited string no longer recognises it (A2[20] = space)
   and leaves it as is.
3. Otherwise, if the string **starts with** `"We made Amiga, T"` ⇒ A2 is **replaced** by the pointer
   to `" Still a Champion"` (the screen title displayed becomes exactly this string).
4. Otherwise ⇒ unchanged. **No** transformation of "34.xx": the Version text
   (`"Kickstart version …"`) passes through intact; the "34.34" comes from version.library (§6.3), not from the
   patch.

Consequence for our ROM [D]: to get, with this LoadWB, the same display as the real ROM,
it is enough to pass to SetWindowTitles a screen title **starting exactly with**
`"Workbench release 1.2."` with a `'2'` at position 20, in a **writable** buffer (the patch
writes into it), and to format Version from the ROM header + version.library. Note: the black-box
reading "`Workbench release.    884392`" (4 spaces) is probably a visual count;
the exact computation gives 6 spaces [D].

### 6.7 Test vectors [O unless stated]

| Action | Expected screen title (with LoadWB 1.3.3 and version.library 34.34) |
|---|---|
| Start-up, tick | `"Workbench release.      <n> free memory"` on the backdrop and open drawers |
| Special/Version | beep; `"Kickstart version 34.5. Workbench version 34.34"`, frozen (ticks ignored) |
| … then 10 s without a click | unchanged |
| … then left click in a WB window | memory title (value of the last tick), updates resumed |
| Special/Last Error after Version | same Version text, **without** beep |
| Special/Version without version.library | `"Kickstart version 34.5. Workbench version -1.-1"` |

### 6.8 Window activation

**Workbench side [O]**

- The module has only **two** calls to OpenWindow: the generic WB window routine (backdrop
  `$02000B40`, drawers/disks `$0200027F`) and the **Rename input window**. The only
  WB window Flags constants are these two: **neither the backdrop nor the drawers have
  ACTIVATE ($1000)**, and nothing adds this bit before opening.
- The **Rename window** is the **only one opened with ACTIVATE**: NewWindow Left 60, Top 100,
  Width 504, Height 11, DetailPen 3, BlockPen 1, IDCMPFlags 0 at opening, **Flags = $1000**
  (ACTIVATE alone), FirstGadget = the name string gadget. Then `wd_UserPort := port B` and
  **ModifyIDCMP(win, $40040)** (ACTIVEWINDOW | GADGETUP).
- **ActivateWindow (−450)**: **a single call site**, in the Rename modal loop (which reads
  port B as long as the input is not finished):
  - **ACTIVEWINDOW ($40000) message coming from a WB window other** than the Rename one ⇒
    **ActivateWindow(Rename window)**: the WB takes the activation back. The other messages of the
    other windows are set aside and then **put back into port B** at the end of the input (under
    Forbid). [O; the exact filter of the messages set aside is D]
  - **ACTIVEWINDOW message from the Rename window itself** ⇒ **ActivateGadget(gadget, Rename
    window, NULL)** (−462) then ReplyMsg: the cursor moves into the text field.
  - any other message from the Rename window (GADGETUP, Return) ends the loop.
- The Workbench **never calls ActivateWindow** for the backdrop or a drawer: not when
  the backdrop is opened, not when a drawer is closed, not on DISKINSERTED, not on the tick, and not
  at the end of Rename (the closing of the Rename window falls under the intuition rule below).

**intuition 34.3 side (ROM): automatic activation rule**

Public `struct Window` fields used: **Parent +$42**, **Descendant +$46**,
WScreen +$2E. Public `struct Screen` fields: FirstWindow +$04. Public
IntuitionBase fields: **ActiveWindow +$34**, ActiveScreen +$38.

- **OpenWindow** [O]:
  - the new window is added at the **head** of `Screen->FirstWindow`;
  - **Parent := current ActiveWindow** (possibly NULL);
  - the window is inserted into the Parent/Descendant chain right after this active window
    (`new->Descendant := active->Descendant`, with the corresponding back link;
    `active->Descendant := new`);
  - it is activated **only if NewWindow.Flags contains ACTIVATE**. **No "no
    active window ⇒ activate" rule** at opening, and no special case for BACKDROP/WBENCHWINDOW.
- **CloseWindow** [O]:
  - the window is removed from the Parent/Descendant chain: its Descendant inherits its
    Parent, and vice versa;
  - it is removed from the screen's window list [D for the exact order];
  - **if it was the ActiveWindow**, the new active window is:
    1. its **Parent** (the window that was active when it was opened, or, if that one
       has been closed in the meantime, the ancestor that inherited the link);
    2. failing that, the **first window of its screen** (`Screen->FirstWindow`, the most
       recently opened one that remains);
    3. failing that, **ActiveWindow := NULL**.
  - When a window is found, ActiveWindow and ActiveScreen are updated and the internal
    activation routine is called, the same one as for ActivateWindow. The new active
    window therefore receives ACTIVEWINDOW if it asked for it [D].
  - If the closed window was not active, nothing changes.
- **ActivateWindow**: calls this internal activation routine directly (mode 1). [O]

**Application to the observed case** [D, consistent with the black box]:

1. At boot, the initial CLI window is active.
2. LoadWB launches the WB, which opens the backdrop without ACTIVATE. It is therefore added at the head of
   FirstWindow, with **Parent = the CLI window**.
3. `endcli` closes the CLI window, which is active. Its Parent is NULL: it was the first
   window opened. Intuition therefore takes **FirstWindow = the backdrop** and activates it.
4. The right button then shows the WB's menus without any click.

To get this behaviour, our intuition only has to reproduce the CloseWindow rule.
The workbench module has nothing to activate itself.

### 6.9 Error messages: call sites

Reminders:
- **"ShowTitle"** is the routine of §6.2: the first message displayed wins until the next
  click or menu choice, and there is a beep.
- **"ErrMsg(i, name)"** is the error routine of §6.5. It formats action no. i (with `name`
  for `%s`), then calls `ShowTitle("Error while %s: %ld", action, IoErr())`.
- **IoErr()** is read **inside ErrMsg**, after the local formatting, which makes no dos call. So
  there is only one dos call between the failure and the read. The value displayed is the one that
  dos left in `pr_Result2` at the failure. There are two exceptions, described below, where an
  intermediate call takes place in between: the errorreq requester (§3.7) and the clean-up after a
  failed launch.
- The actions without `%s` (0 `"examining directory"`, 3 `"reading"`, 4 `"writing"`) ignore the name.
- When the **routine itself** displays a message and **its caller** emits a second one, the
  second is **ignored**: bit 2 is already set (§6.2). Only the first one is visible.

**What triggers a dos error, and which message is displayed [O unless stated]**

1. **Reading the contents of a drawer or a disk** (opening its window)
   - Failure: `Examine(drawer lock)`.
     Message: ErrMsg(**7**, **object name**) ⇒ `"Error while examining <name>: <err>"`.
   - Case: the lock is not a directory (fib_DirEntryType < 0).
     Message: ShowTitle `"This drawer is not really a directory"`.
   - Failure, in the read loop (generic walk routine, which does CurrentDir on the
     directory): `Examine` then `ExNext` when IoErr ≠ 232 (ERROR_NO_MORE_ENTRIES).
     Message: ErrMsg(**0**) ⇒ `"Error while examining directory: <err>"`.
   - Case: the drawer window could not be filled.
     Message: ShowTitle `"This drawer cannot be opened"` (usually hidden by the previous
     message). A failure of OpenWindow or AllocMem gives instead
     `"Ran out of memory.  Please free some and try again."`.
   - An unreadable `.info` during this walk is **silently ignored**: no
     "Cannot read info file" message.
2. **Launching a tool or a project** (double-click, or Open menu)
   - CurrentDir = parent directory of the double-clicked icon. For a project, it is the
     **project's** directory, and `name` is its **Default Tool** as written in the icon,
     relative or with a volume.
   - Failure: `LoadSeg(name)`.
     Message: ErrMsg(**2**, **tool name**) ⇒ `"Error while opening <tool>: <err>"`.
   - Failure: AllocMem of the WBStartup, or CreateProc. The WB does **UnLoadSeg** (and FreeMem), then
     the **same** ErrMsg(2, tool). IoErr is then read after these calls [D: value of the last
     dos call].
   - Case: no tool among the selected icons and no Default Tool.
     Message: ShowTitle `"The icon(s) have no default tool"`.
   - The WB does **no Lock** of the directory that could produce an "accessing" at this stage.
3. **Rename** (Workbench menu, item 3; input in the Rename window)
   - New name identical to the old one ⇒ nothing is done.
   - Forbidden characters: **`':'` ($3A)**, then **`'/'` ($2F)**, in this order, searched for in the
     new name. Message: ShowTitle `"Do not use '%lc' in names"`, with the character
     sign-extended to a long. Examples: `"Do not use ':' in names"`, `"Do not use '/' in names"`.
     No other character is rejected.
   - File, drawer, tool or project: renaming within the same directory with an **ACTION_RENAME_OBJECT
     (17) packet**. It is sent **directly to the handler of the source lock**; it
     is **not** dos `Rename()`. Two renames take place, `name → new`, then
     `name.info → new.info`.
     - For the **first** one only, a failure with IoErr = **205** (object not found) is **tolerated**:
       an icon without a file can still be renamed.
     - Otherwise, on failure, the WB calls **errorreq(2, destination lock, its fl_Task)** (§3.7).
       Return 0 (Retry) ⇒ retry. Non-zero ⇒ ErrMsg(**5**, **old name**, or
       `old.info` on the 2nd rename) ⇒ `"Error while moving <old>: <err>"`. Yes, it really is
       "moving" that is displayed for a Rename.
   - Disk: **ACTION_RENAME_DISK (9) packet** to the volume's handler. On failure, errorreq(2, …):
     Retry ⇒ retry, give up ⇒ ShowTitle `"Can't rename this disk"`.
4. **Dragging an icon into another window** (move)
   - Icon type outside the mask **$001C** (only drawer 2, tool 3 and project 4 can
     leave their window; not disk 1, trashcan 5, etc.).
     Message: ShowTitle `"'%s' cannot be moved out of its window"`, with the **object name**.
   - Drop on a window that is not a known WB window.
     Message: ShowTitle `"Icons cannot be moved into this window"`.
   - Disk dropped on a disk, incompatible types.
     Message: ShowTitle `"Disks are of incompatible type and cannot be copied"`.
   - Disk dropped on a disk, icon without Default Tool (DiskCopy).
     Message: ShowTitle `"This disk cannot be copied"`.
   - **Same volume**: same procedure as Rename (packet 17, `name` then `name.info`, 205 tolerated
     on the first one, errorreq then ErrMsg(**5**, **name**)).
   - **Other volume**: it is a **copy**, the source is not deleted. If `Lock(name)` in the
     source directory fails (205 tolerated for the first one), message: ErrMsg(**1**, **name**) ⇒
     `"Error while accessing <name>: <err>"`. The rest goes through the copy (point 6).
5. **Discard** (Workbench menu, item 5; after the `"ok to discard"` / `"forget it!"` requester)
   - CurrentDir = parent directory, then `Lock(object name, SHARED)`. If this Lock fails:
     with IoErr = 205, it goes straight to the DeleteFiles; with another code, the Discard is
     **abandoned without a message**. If the object is a directory, its contents are emptied
     **recursively** by the generic walk routine: a failure of Examine or ExNext
     gives ErrMsg(**0**), then abandonment. Any other error in the recursion also causes a
     silent abandonment of the upper level (its message, if any, has already been displayed).
   - Each file encountered is deleted with **DeleteFile**:
     - failure with IoErr = **205** ⇒ considered successful, no message;
     - other failure ⇒ ErrMsg(**6**, **name as passed to DeleteFile**) ⇒
       `"Error while removing <name>: <err>"`. It is the **simple name** (fib_FileName relative to the
       current directory), not a path.
   - Finally the object itself: `DeleteFile(name)` then `DeleteFile(name.info)`, same rules
     (message `"removing <name>"` or `"removing <name>.info"`). The caller then emits
     ErrMsg(6, **object name**), but this second message is **hidden** by the first.
   - A failed Lock of a sub-drawer during the recursion stops the deletion **without a message**.
6. **Duplicate** (Workbench menu, item 2) and copy to another volume
   - Disk: launch of its Default Tool (DiskCopy), as in point 4.
   - Object: CurrentDir = parent directory, then `Lock(name, SHARED)`. Failure ⇒ ErrMsg(**1**,
     **object name**).
   - The new name is produced by icon **BumpRevision** (`"copy of …"`). The icon is written with
     PutWBObject, then read back. If the read-back fails, message: ShowTitle
     `"Cannot read info file %s"` with the **new name**. This is the **only** site of this message.
   - Recursive copy:
     - sub-directory that cannot be locked ⇒ ErrMsg(**1**, entry name);
     - failed `Open(source, MODE_OLDFILE 1005)` ⇒ ErrMsg(**2**, **source name**);
     - `Read` ≤ 0 before the announced size has been read ⇒ ErrMsg(**3**) ⇒
       `"Error while reading: <err>"`;
     - on the destination side, failed `Open(dest, MODE_NEWFILE 1006)` ⇒ ErrMsg(**2**, **destination
       name**);
     - destination directory: `Lock(dest)`, then `CreateDir(dest)` if IoErr = 205; final
       failure ⇒ ErrMsg(**1**, destination name);
     - `Write` that writes less than requested ⇒ ErrMsg(**4**) ⇒ `"Error while writing: <err>"`.
7. **Snapshot** (Special menu, item 3)
   - For each selected icon: CurrentDir = parent directory, then
     **PutWBObject(name, object)**, with `"Disk"` as the name for a disk icon.
   - Failure ⇒ ErrMsg(**8**, **object name**, the volume name for a disk) ⇒
     `"Error while writing <name>: <err>"`.
   - The module does not call PutDiskObject: the WB 1.x interface is PutWBObject.
8. **Info** (Workbench menu, item 4): if `OpenLibrary("info.library", 0)` fails, message:
   ShowTitle `"Info not available"`.
9. **Out of memory**: several AllocMems (Duplicate, Discard, launch, drawer
   opening…) give ShowTitle `"Ran out of memory.  Please free some and try again."`.

**dos requesters and title message [O/D]**

- The title message is emitted **in addition to** any requester. It is not one or the other.
- Requester **called explicitly by the WB** (errorreq, only for renaming, moving
  on the same volume and disk renaming):
  - "Retry" ⇒ the operation is redone, without a message;
  - "Cancel" ⇒ the ErrMsg or ShowTitle message **is displayed afterwards**;
  - errorreq does not present a requester for all codes [D, dos behaviour]; when it
    shows none, the message follows immediately;
  - IoErr is re-read **after** errorreq. errorreq is assumed not to modify `pr_Result2` [S].
- Requesters **issued by dos itself** during Lock, Open or LoadSeg (for example `"Please insert
  volume"`): the WB has `pr_WindowPtr = 0` (requesters on the WB screen), except while writing a
  `.info`, where it is −1 (§3.3). After "Cancel", the call fails and the corresponding title
  message is displayed too [D].

---

## 7. Workbench/Info and info.library

Sources: ROM (Info routine of the wb module) and `libs/info.library` from `wb133.adf`
(16 380 bytes, 25 hunks; extracted and relocated in the analysis track's scratch). info.library
is a **disk binary that we do not reimplement**: this section describes **the calling
contract** and the **fields** it reads and writes, so that our ROM can call it.

### 7.1 Workbench side (Workbench menu, item 4, code $F880) [O]

1. As for every MENUPICK, the memory title is restored first (§6.2).
2. The Info routine is called for **each selected icon**, one after the other (same
   iterator as Snapshot) [D for the order].
3. For one icon:
   - **Disk** (type 1) for which the WB knows no directory lock: **nothing** (no
     message).
   - Otherwise **`OpenLibrary("info.library", 0)`** (version **0**).
   - On failure: `ShowTitle("Info not available")` (§6.9 point 8).
   - On success: call of **LVO −30** of the base obtained, with **A6 = InfoBase**,
     **A0 = InfoBase** (copy, unused by the library) and **A1 = pointer to the icon's WBObject**
     (**private** Workbench structure, §7.3). The **return value is ignored**.
   - Then **`CloseLibrary(InfoBase)`**.
4. No icon refresh is done on return, apart from the common end of MENUPICK. What
   info.library changed in the WBObject (default tool, tool types, stack) stays in
   memory as is.
5. **The call is synchronous and modal**: info.library runs **in the Workbench process**, opens its
   own window and waits for its own events until SAVE or QUIT. Meanwhile the WB
   processes neither its ports A and B nor its ticks [D, direct consequence].

### 7.2 info.library: identity, vectors, libraries [O]

- **ROMTag**: `rt_Flags = $80` (AUTOINIT), version 34, `rt_Type = 9` (NT_LIBRARY), pri 0, name
  `"info.library"`, IdString `"info V1.3\r\n"`.
- Base of **$26 bytes** (sizeof Library); **lib_Version 34**, lib_Revision 0. The init stores
  SysBase and the seglist.
- **Vectors**: Open, Close, Expunge, Reserved, then **a single public function**, the
  **LVO −30**, which we call `Info(wbobject)` here (deduced name [D]). Argument: **A1** =
  WBObject. No callback or function pointer supplied by the Workbench.
- **Libraries opened by itself**, all at **version 0**, then closed on exit:
  - `"dos.library"`: Lock, UnLock, Examine, Info, SetComment, SetProtection;
  - `"icon.library"`: **PutWBObject (−36)**, **AddFreeList (−72)**;
  - `"intuition.library"`: OpenWindow, CloseWindow, SetWindowTitles, AddGadget, RemoveGadget,
    RefreshGadgets, ActivateGadget, DisplayBeep, SetPointer, BeginRefresh/EndRefresh,
    AllocRemember/FreeRemember;
  - `"graphics.library"`: OpenFont/CloseFont (`topaz.font`, heights 9 and 8), SetFont, Text,
    Move/Draw, RectFill, SetAPen, SetDrMd, SetRast.
- **exec**: AllocMem, FreeMem, Forbid/Permit, Insert/AddTail/Remove, **FindTask(0)**, Wait,
  GetMsg, ReplyMsg, CloseLibrary, OpenLibrary.
- If a library open, an allocation, the Lock or the font fails: clean-up and return
  **without a message**.

### 7.3 WBObject fields read or written by info.library [O]

The object is the private Workbench 1.x structure as icon.library 1.3 builds it
(AllocWBObject / GetWBObject). Info uses only the following fields.

| Off. | Size | Meaning | Access |
|---|---|---|---|
| **+$38** | ptr | **parent object** (WBObject of the drawer or disk that contains the icon) | R |
| **+$3D** | byte | **type**: 1 disk, 2 drawer, 3 tool, 4 project, 5 trashcan, 6 device, 7 kick | R |
| **+$40** | ptr | **name** (C, without `.info`) | R |
| **+$48** | ptr | **default tool** (C, or NULL) | R, **W** (new string) |
| **+$4C** | ptr | **DrawerData**; only **+$1BA** is read from it = **lock (BPTR) of the directory** | R |
| **+$5C** | ptr | **tool types** (NULL-terminated `char **`, or NULL) | R, **W** (new array or NULL) |
| **+$8C** | struct | the object's **FreeList** (passed to icon **AddFreeList**) | address passed |
| **+$A0** | long | **stack size** (tool and project) | R, **W** |
| **+$A4** | BPTR | **lock of the containing directory**, if known directly (takes priority) | R |

After the call, the complete object is passed to **PutWBObject**. The fields that icon.library reads to
write the `.info` fall under icon.library's contract, not info.library's.

**Working directory used** (order of priority):
1. type 7 ⇒ none (no useful Info);
2. `+$A4` if non-null;
3. for a **disk**, its **own** `+$4C → +$1BA` (root lock);
4. otherwise the **parent's** (`+$38`) `+$4C → +$1BA`;
5. failing that, 0.

**Side effect [O]**: info.library **writes this lock directly into `pr_CurrentDir` (+$98)** of the
calling process (via FindTask(0)), **without CurrentDir() and without restoring it**. The Workbench must
therefore be a **Process** (not a mere Task). Its current directory then points at this lock,
which is harmless since the WB redoes CurrentDir before each operation (§6.9).

**Allocations attached to the object**: the new default tool string, the new tool types
array and each new tool type string are allocated with AllocMem: flags 0 for
the default tool (retry with MEMF_PUBLIC if the allocation fails), **MEMF_CLEAR** for
the tool types. They are then registered with
**AddFreeList(object+$8C, memory, size)**. They are therefore freed with the object (FreeWBObject). The
old strings and the old array are **not** freed.

### 7.4 Course of `Info(object)` [O]

1. Opening of the 4 libraries, then an intuition Remember list (AllocRemember, MEMF_CLEAR |
   MEMF_CHIP) for all the internal data.
2. Forced CurrentDir (§7.3), then **`Lock(name, SHARED)`** with as name:
   - for a disk, the string `"disk.info"`. If this Lock fails, the disk's root lock
     (`+$4C → +$1BA`) is **borrowed** instead, and will not be UnLocked;
   - for the other types, `+$40`.
3. Reads:
   - disk: **`Info(lock, InfoData)`**;
   - the others: **`Examine(lock, FIB)`**. Kept: `fib_Protection` (+$74), size, number of
     blocks, **`fib_Comment` (+$90)**.
   - default tool (`+$48`), copied into a buffer of at least 256 bytes;
   - stack (`+$A0`);
   - tool types (`+$5C`).
4. Opening of the window:
   - NewWindow: Left 0, Top 10, Width 604, Height 190, DetailPen −1, BlockPen 1;
   - IDCMP **$244** (REFRESHWINDOW | GADGETUP | CLOSEWINDOW);
   - Flags **$146F** (SIZING | DRAG | DEPTH | CLOSE | SIZEBBOTTOM | SIMPLE_REFRESH |
     GIMMEZEROZERO | **ACTIVATE**);
   - window title **`"Info release 1.31"`**, Min 210×50, Max 604×190, **Type WBENCHSCREEN**;
   - then **`SetWindowTitles(win, −1, "Info release 1.31")`**: the **screen title** becomes this
     text (the LoadWB patch §6.6 lets it through intact).
5. Event loop on the UserPort of **its own** window (Wait, GetMsg, ReplyMsg), with handling
   of the gadgets.
6. **SAVE**:
   - tool or project: `+$A0` := stack entered;
   - tool types rebuilt (`+$5C`), or NULL if the list is empty;
   - if the default tool has changed: new string in `+$48`;
   - files, for types other than disk:
     1. `SetProtection("<name>.info", 0)` (allows writing);
     2. **`PutWBObject(name, object)`**, with **`"Disk"`** as the name for a disk;
     3. `SetComment(name, comment)`;
     4. `SetProtection(name, protection entered)`;
     5. `SetProtection("<name>.info", protection & ~$10)` (bit 4, archive, removed).
   - Disk: only `PutWBObject("Disk", object)` in the root.
   - A failure is remembered; the exact visible behaviour (beep?) has not been settled [S].
7. **QUIT**, or close gadget: exit without writing.
8. Clean-up: CloseWindow, CloseFont, FreeRemember(…, TRUE), UnLock of the lock (unless it was
   borrowed), CloseLibrary of the 4 libraries. **D0 on return has no defined meaning.**

### 7.5 What the user sees (library strings) [O for the strings, D for the layout]

- **Common labels**: `NAME`, `TYPE`, `STATUS`. Text buttons: **`"  SAVE  "`** and
  **`"  QUIT  "`** (two spaces on each side), **`ADD`** and **`DEL`** (tool types). Font
  topaz 8 and 9.
- **Disk** (TYPE `"Disk"`):
  - `Number of Blocks`, `Number Used`, `Number Free`, `Bytes per Block`, from the InfoData;
  - STATUS according to `id_DiskState`: `Read Only`, `Validating`, `Read/Write`, otherwise
    `I'm not sure`;
  - editable fields `DEFAULT TOOL`, `TOOL TYPES`;
  - no comment or protections.
- **Drawer** (`"Drawer"`): `COMMENT`, `TOOL TYPES`, protections.
- **Tool**: size `in bytes` and `in blocks`, `COMMENT`, `STACK`, `TOOL TYPES`, protections.
- **Project** (`"Project"`): `in bytes`, `in blocks`, `COMMENT`, `STACK`, `DEFAULT TOOL`,
  `TOOL TYPES`, protections.
- **Trashcan** (`"Garbage"`): `COMMENT`, `TOOL TYPES`.
- **Device**: label `"Device"`.
- **Protections**: checkboxes `ARCHIVED`, `READABLE`, `WRITEABLE`, `DELETEABLE`, from the bits of
  `fib_Protection` (1.3 semantics: bit at 1 = forbidden, for R, W and D).

### 7.6 Disk and open drawer: differences [O]

- **Disk**:
  - the WB only calls Info if it knows a lock for this disk (otherwise nothing);
  - info.library uses the root lock **of the disk itself** (`+$4C → +$1BA`);
  - it reads the statistics with `Info()`;
  - it only saves `Disk.info` (PutWBObject `"Disk"`), without SetComment or SetProtection.
- **Drawer**, open or closed: **no difference** for info.library. It **never** looks
  at the window or the DrawerData **of the drawer itself**, only at that of its
  **parent** (or `+$A4`). The object is locked by its name in the parent directory and read with
  Examine, like a file.

### 7.7 Requirements for our ROM [D]

- `OpenLibrary("info.library", 0)` must be able to succeed: the disk's library is loaded
  by ramlib from `LIBS:`.
- **Call**: JSR −30(A6) with **A6 = A0 = InfoBase** and **A1 = WBObject**.
- **WBObject**: fill in at least +$38, +$3D, +$40, +$48, +$4C (and +$1BA of the containers'
  DrawerData), +$5C, +$8C (valid FreeList), +$A0, +$A4, with these offsets and this meaning. The rest of
  the object must suit **PutWBObject** of the icon.library in use.
- **icon.library**: must expose 1.3-compatible **PutWBObject (−36)** and **AddFreeList (−72)**.
- **Process**: the WB must be a Process, because `pr_CurrentDir` (+$98) is written directly.

### 7.8 Obtaining the WBObject from icon.library 1.3 (`libs/icon.library`, "icon 34.2 (22 Jun 1988)") [O]

**Vectors.** Table of absolute pointers, in the order of the public `.fd`:

| LVO | Function | Registers | Return |
|---|---|---|---|
| −30 | **GetWBObject**(name) | A0 | WBObject* or 0 |
| −36 | **PutWBObject**(name, object) | A0, A1 | boolean |
| −42 | GetIcon(name, icon, freelist) | A0, A1, A2 | boolean |
| −48 | PutIcon(name, icon) | A0, A1 | boolean |
| −54 | FreeFreeList(freelist) | A0 | — |
| −60 | **FreeWBObject**(object) | A0 | — |
| −66 | **AllocWBObject**() | — | WBObject* or 0 |
| −72 | AddFreeList(freelist, mem, len) | A0, A1, A2 | boolean |
| −78 | GetDiskObject(name) | A0 | DiskObject* |
| −84 | PutDiskObject(name, diskobj) | A0, A1 | same entry point as −48 |
| −90 | FreeDiskObject(diskobj) | A0 | — |
| −96 | FindToolType(array, name) | A0, A1 | |
| −102 | MatchToolValue(string, value) | A0, A1 | |
| −108 | BumpRevision(new, old) | A0, A1 | |

**AllocWBObject()**
- Allocates **$A8 = 168 bytes MEMF_CLEAR**. This is the total size of the WBObject: all the offsets
  used by the WB and by info.library (≤ +$A4) fit in it.
- Initialises the **FreeList at +$8C**, which occupies +$8C..+$9B: `fl_NumFree` (word) at +$8C, then
  the MemList list at +$8E.
- **Registers the object itself in its FreeList** (AddFreeList(object+$8C, object, 168)).

**GetWBObject(name)**
- Does AllocWBObject, then **GetIcon(name, local DiskObject, object+$8C)**. All the
  icon's allocations therefore go into the object's FreeList.
- GetIcon opens **`"<name>.info"` in MODE_OLDFILE relative to the current directory of the calling
  process**. The caller must therefore do CurrentDir(containing directory) before the call; for a
  disk, name = `"Disk"` in the root.
- GetIcon reads the 78-byte header and checks **magic $E310** and **version 1**. For an allocation
  failure, IoErr is forced to 103.
- On failure, the object is freed and the function returns 0.
- Fields filled in, copied from the DiskObject read:

| WBObject off. | Source (public DiskObject field) |
|---|---|
| +$3D (byte) | `do_Type` |
| +$48 | `do_DefaultTool` (string allocated in the FreeList) |
| +$4C | `do_DrawerData` (0 if the icon has none) |
| +$54 / +$58 | `do_CurrentX` / `do_CurrentY` |
| +$5C | `do_ToolTypes` (array and strings allocated in the FreeList) |
| +$60 .. +$8B | `do_Gadget`, 44 bytes (struct Gadget, GadgetRender/SelectRender images allocated in CHIP in the FreeList) |
| +$9C | `do_ToolWindow` |
| +$A0 | `do_StackSize` |
| +$8C | FreeList (contains the object and all its allocations) |

- **Not filled in, remain at 0**: **+$38** (parent), **+$40 (name: NOT copied from the argument)**,
  **+$A4** (lock), as well as all the rest of the object. WB 1.3 sets +$40 itself. For
  info.library, **it is up to us to fill in +$40, and depending on the case +$38 / +$A4.**
- **DrawerData**, only if the icon has one (drawer, disk, trashcan):
  - block of **$1BE = 446 bytes MEMF_CLEAR|MEMF_CHIP**, allocated in the FreeList;
  - the first 56 bytes (NewWindow + CurrentX/Y) are read from the file;
  - **+$1A8 := pointer to the WBObject** (back link);
  - an empty list is initialised at **+$1AC**;
  - **+$1BA..+$1BD = last long of the block**, covered by the allocation and **left at 0**. It is
    up to us to put the directory lock (BPTR) there for info.library to read (§7.3).

**FreeWBObject(object)**
- = **FreeFreeList(object+$8C)**. All entries are freed, **including the object
  itself**, the DrawerData and **the strings and arrays added by info.library via
  AddFreeList** (§7.3).
- **Does no UnLock or anything else**: no field is examined. There is nothing to reset to 0
  before the call. On the other hand, we must **UnLock ourselves** the locks we have set
  (+$A4, DrawerData+$1BA), and free the +$40 name if we allocated it outside the FreeList.
  The simplest is to allocate it and then register it with AddFreeList(object+$8C, …), so that it
  goes away with the object.
- After the call, the object no longer exists.

**PutWBObject(name, object)**
- Rebuilds a DiskObject: magic $E310, version 1, `do_Gadget` = +$60..+$8B, `do_Type` = +$3D,
  `do_DefaultTool` = +$48, `do_ToolTypes` = +$5C, CurrentX/Y = +$54/+$58,
  `do_DrawerData` = +$4C, `do_ToolWindow` = +$9C, `do_StackSize` = +$A0.
- Calls **PutIcon(name, DiskObject)**, which writes `"<name>.info"` in **MODE_NEWFILE in the
  current directory**. Contents, in order:
  1. the 78-byte header;
  2. if DrawerData: its **first 56 bytes only** (the private part, including +$1A8 and +$1BA,
     is never written);
  3. the gadget images (render, then select if present);
  4. the default tool and the tool types, if they exist (length then string);
  5. the ToolWindow, if it exists.
- **+$40, +$38, +$A4 are not used**: the name comes from the argument.

**Recipe for Workbench/Info with our WB [D]**
1. CurrentDir(directory containing the icon), or the root for a disk.
2. `obj = GetWBObject(name)`, or `GetWBObject("Disk")` for a disk.
3. Fill in:
   - **+$40** := name (allocated then AddFreeList into obj+$8C);
   - **+$A4** := lock of the containing directory (the simplest: takes priority in info.library);
   - **for a disk**: +$A4 := root lock. Since +$A4 takes priority (§7.3),
     info.library then locks `"disk.info"` in the root. **To be safe**, also set
     **+$4C → +$1BA** := root lock (without a separate UnLock, it is the same lock): it is
     info.library's fallback when this Lock fails, and it then dereferences +$4C without testing whether it
     is null [O]. A disk icon without DrawerData (+$4C = 0) is therefore safe only if
     `Disk.info` can be locked [D].
   - +$38 can stay at 0 if +$A4 is set.
4. Call info.library (§7.1).
5. Reload our DiskObject from the disk if SAVE may have changed the icon (no return signal
   indicates it).
6. **UnLock our locks** (+$A4; +$1BA only if it is a distinct lock), then
   **FreeWBObject(obj)**.

### 7.9 Duplicate (Workbench menu, item 2, code $F840)

As for every MENUPICK, the memory title is restored first (§6.2). The Duplicate routine is
then called for **each selected icon** (same iterator as Snapshot and Info) [D for
the order]. The G+off and WBObject notations are those of §6.1 and §7.3.

#### 7.9.1 Disk and kick: launching DiskCopy [O]

- **Case covered**: a type in the mask **$0082**, i.e. **disk (1)** and **kick
  (7)**. It is **not** a copy made by the Workbench: it launches the **icon's default
  tool** (`+$48`, on the 1.3 disk usually `SYS:System/DiskCopy`).
- **No default tool**: ShowTitle `"This disk cannot be copied"` (§6.9).
- **Arguments**: a WBArg array of **2 entries** (AllocMem 2 × 8, MEMF_CLEAR):
  1. the tool, by its name;
  2. **the disk itself**.
  Dragging one disk onto another uses the same routine with 3 entries: tool, source,
  destination.
- **Launch**: same path as a tool launch (LoadSeg, CreateProc, WBStartup), with the
  same `"opening <tool>"` error messages (§6.9 point 2). Nothing else is done for a
  disk.

**Exact contents of the WBArgs [O]** (WBArg construction routine, shared with tool
launching):

| Arg | wa_Lock | wa_Name |
|---|---|---|
| 0: the tool, named by `+$48` | if the name contains `':'` **anywhere other than the first position** (case `"SYS:System/DiskCopy"`): **0 (NULL)**; otherwise **DupLock of the lock of the directory containing the icon** | **copy of the name as is**, hence the full path `"SYS:System/DiskCopy"` when wa_Lock = NULL |
| 1: the disk (type 1, and more generally a type in the mask $0026: disk, drawer, trashcan) | **DupLock(DrawerData+$1BA)**, i.e. of the **volume's root lock** taken at the scan (ACTION_LOCATE_OBJECT packet, §3.3). If +$1BA is still 0, the WB obtains it first, duplicates it, then releases it and resets +$1BA to 0 | **empty string `""`** (allocated copy) |
| (kick icon, type 7) | 0 | `"<device name>:"` from the scan table |

The volume is **that of the duplicated icon**, not necessarily SYS:. Our `Lock("SYS:")` is
only equivalent for the boot disk icon.

**Other launch fields [O]**
- `CreateProc(name = the tool string, pri, seglist, stack)`.
- **Stack** = `do_StackSize` of **the disk icon** (+$A0), or **4096** if it is 0.
- **Priority** = ToolType `TOOLPRI` from the tool types of **the disk icon**, or 0 by default.
- 40-byte WBStartup (MEMF_CLEAR):
  - `mn_ReplyPort` = port A;
  - `sm_Process`, `sm_Segment`;
  - `sm_NumArgs = 2`;
  - `sm_ArgList`;
  - **`sm_ToolWindow` = 0**: no field fills it on this path.
- A **disk rescan** (§3.3) takes place just before the PutMsg.
- LoadSeg is done with CurrentDir = the icon's directory, with no effect here since the path is
  absolute.

**DiskCopy 1.4 (`SYS:System/DiskCopy`, `$VER: diskcopy 36.6 (7.6.90)`): handling of the WBArgs [O]**

Start-up (resident C startup):
- Opens `"dos.library"` at version 0.
- In Workbench mode:
  - WaitPort/GetMsg of the WBStartup;
  - **CurrentDir(ArgList[0].wa_Lock)**, i.e. 0 here;
  - if `sm_ToolWindow` ≠ 0, opening of this window as console;
  - stores `ArgList[0].wa_Name` as program name;
  - calls `main(0, WBStartup)`.

**Exit conditions BEFORE any window, hence "nothing is displayed" [O]**:
1. **`DOSBase->lib_Version` (+$14) < 33** ⇒ exit code 10. This is the very first check
   made in main.
2. `OpenLibrary("intuition.library", 0)` or `("graphics.library", 0)` fails ⇒ exit 10.
3. Failure of CreatePort, of the two CreateExtIOs (52 bytes, IOStdReq for trackdisk), of AllocMem
   (512 bytes CHIP|CLEAR), of 260 bytes (FIB) or of 36 bytes (InfoData) ⇒ exit 10.
4. `OpenLibrary("icon.library", 0)` fails ⇒ requester `"Unable to open icon.library"` (Retry
   or give up).
5. **OpenWindow** of its window fails ⇒ exit 10.
Only then come SetWindowTitles (screen title `"DiskCopy"`) and the reading of the
arguments.

**Choice of disks according to `sm_NumArgs` (+$1C) [O]**:
- **2** ⇒ source = destination = **ArgList[1]** (copy on a single drive);
- **3** ⇒ source = ArgList[1], destination = ArgList[2];
- other value ⇒ display of the help ("To duplicate a disk / select its icon and choose / Copy
  from the / Icons menu") [D for the exact path].

**Resolving the drive from a disk WBArg [O]**:
1. **`wa_Name` must be EMPTY**: if it is not, **silent exit 10**.
2. **`ParentDir(wa_Lock)` must return 0**: the lock must be that of a **root**. Otherwise
   UnLock of the parent and **silent exit 10**.
3. Right after, **`IoErr()` must be 0**. Otherwise error message (internal code $61) then
   exit 10. **So our ParentDir on a root must return 0 while leaving `pr_Result2`
   at 0.**
4. **`Info(wa_Lock, InfoData)`** then **`Examine(wa_Lock, FIB)`** must succeed (otherwise same
   error).
   - Source: displayed name = `fib_FileName` (+$08), i.e. the **volume name**.
   - Destination: additional checks `id_InUse` (+$20), with the requester "Another
     process has destination disk open", and `id_DiskState` (+$08) = 80 (write-protected).
5. **UnLock(wa_Lock)** and **setting of the wa_Lock field to 0** in the WBArg: DiskCopy frees
   the received lock itself.
6. **Device search**:
   - volume task = `InfoData.id_VolumeNode` (+$1C, BPTR) → `dol_Task` (+$08);
   - walk of `DOSBase->dl_Root` (+$22) → `rn_Info` (+$18, BPTR) → `di_DevInfo` (+$04,
     BPTR) → `dn_Next` chain (+$00, BPTR);
   - for each node with **`dn_Type` (+$04) = 0** (DLT_DEVICE) whose **`dn_Task` (+$08) == the volume
     task**;
   - the name `"<dn_Name>:"` is built from `dn_Name` (+$28, BSTR), for example `"DF0:"`.
     It is the one seen in "in drive %s".
   - No node found ⇒ error $61 then exit.
7. Then:
   - **DeviceProc(name)** (dos −174) for the source and for the destination; a failure gives
     error $61;
   - comparison of the two ports (same drive or not);
   - inhibition of the handlers;
   - reading of the geometry from **`dn_Startup` (+$1C) → `fssm_Environ` (+$08) → DosEnvec**
     (`de_HighCyl` +$28 − `de_LowCyl` +$24 + 1, `de_BlocksPerTrack` +$14…);
   - only then the message "Place … ( FROM disk ) in drive %s".

**Diagnosis for our ROM [D]**: DiskCopy displays nothing and leaves no trace. The
culprit is therefore one of conditions 1 to 5 before the window, and **the first one is the
`DOSBase->lib_Version ≥ 33` check**. If the window opens and then closes, look, in
order, at:
- wa_Name ≠ "";
- ParentDir ≠ 0 on the root;
- IoErr ≠ 0 after ParentDir;
- Info or Examine refused on a root lock;
- `id_VolumeNode` or `dol_Task` inconsistent with the DeviceNode's `dn_Task`;
- DeviceProc("DF0:") failing;
- `dn_Startup` / `fssm_Environ` missing.

#### 7.9.2 Other objects (drawer, tool, project…): full sequence [O unless stated]

1. **Parent directory.** The WB takes the lock of the directory that contains the icon. If it has
   none, ErrMsg(1, name) (`"Error while accessing <name>"`) and end. Otherwise **CurrentDir(parent)**,
   keeping the old current directory.
2. **Lock of the original**: **`Lock(name, SHARED (−2))`**. On failure: ErrMsg(1, name), then
   the common end (step 10).
3. **New name**: **icon `BumpRevision` (LVO −108)** (new, old), the new name being
   written into the **global buffer G+$5C**. The result is **truncated to 25 characters** (the byte
   at index 25 is set to 0). Example: `"Expansion"` ⇒ `"copy of Expansion"`. For the rules
   of BumpRevision itself (`"copy 2 of …"` etc.), see icon.library.
4. **Writing of the copy's `.info`, BEFORE any data is copied**:
   - the **original** WBObject is modified **temporarily in memory**:
     - `+$40` := the new name;
     - `+$54/+$58` (CurrentX/Y): see §7.9.3;
   - then CurrentDir(parent) and **`PutWBObject(new name, original)`**;
   - then `+$40`, `+$54` and `+$58` **immediately** get their original values back.
   This is why the copied `.info` is identical to the original except for CurrentX/Y: PutWBObject
   does not write the name (§7.8).
   If PutWBObject fails, there is **neither an icon nor a copy of the data**, and no message specific to
   this step [O; any message depends on icon.library and on the dos requester].
5. **Duplicate icon**: if the parent drawer already contains an icon bearing the new name, it
   is **removed from the display** before the read-back (case of an old "copy of …").
6. **Read-back**: CurrentDir(parent), then **`GetWBObject(new name)`**, then the name is
   allocated in `+$40`, the object is added to the master list G+$24 and prepared (images…).
   - On failure: ShowTitle `"Cannot read info file %s"` (name = G+$5C), and **the data are not
     copied**.
   - If the original has its own lock at `+$A4`, the copy receives a `DupLock` of this lock.
   - Bit 4 of the original's `+$3C` byte is copied onto the copy.
7. **Insertion into the drawer** (without re-reading the whole drawer):
   - `+$38` := parent drawer;
   - if the position is **NO_ICON_POSITION ($80000000)**, a free slot is searched for
     (scan in steps of 96 px);
   - added to the drawer's icon list (DrawerData +$1AC), **attached to its window**
     (`+$50` := DrawerData +$1A4);
   - computation of the gadget position from X/Y, the drawer's scrolling (DrawerData
     +$30/+$34) and the window borders;
   - then rendering of the icon [D for "rendering": call at the end of the routine].
8. **Data copy** (§7.9.4): from the original's lock to the parent directory, under the
   **new name**.
9. **Recomputation of the parent drawer**: its extent and its scroll bars are recomputed
   from the new icon. The drawer is **not re-read** from the disk.
10. **Common end**: `UnLock(lock of the original)`, **CurrentDir(old directory)**. Returns
    "success" if the last step succeeded.

**Selection [O, by absence]**: Duplicate calls no selection or
deselection routine. The original **stays selected**. The copy is created **unselected** (new
object) [D].

**Freeing [O]**: the G+$5C buffer is global (nothing to free). The original's lock is
freed at step 10. The copy's WBObject then belongs to the drawer (it is not freed
here). The resources of the data copy are freed by it (§7.9.4).

#### 7.9.3 Position of the copy [O]

The choice depends on **bit 4 of the original's `+$3C` byte**. This bit goes hand in hand with the
own lock `+$A4`: the move routine clears both together. Its exact meaning
remains [S].

- **Bit 4 at 0 (normal case, Expansion probe)**:
  - while the `.info` is being written, **CurrentX += 30** and **CurrentY += 15**;
  - the `.info` therefore carries these values (203,0 → **233,15**), and the re-read copy takes them over.
- **Bit 4 at 1**:
  - the `.info` is written with **CurrentX = CurrentY = NO_ICON_POSITION ($80000000)**;
  - **in memory**, the re-read copy then receives X+30 / Y+15 of the original.

The offset is **constant (+30, +15)**. It depends **neither on the icon size nor on the
font**. There is neither overlap search nor clamping.

#### 7.9.4 Data copy (files and drawers) [O unless stated]

- **Coroutines.** It runs **in the Workbench process**, with **two coroutines**
  (each has a **4096-byte** stack allocated with AllocMem):
  - a **reader**, which walks the source;
  - a **writer**, which creates the destination.
  They hand over to each other in turn. A **536-byte** context (MEMF_CLEAR) is allocated
  for the operation.
- **Buffer pool.** It is made of **526-byte blocks**: 512 bytes of data plus a
  header.
  - The WB allocates as many blocks as memory allows, up to **limit + 30**:
    - limit **40** if the source and the destination are served by **two different
      handlers**;
    - otherwise a value linked to the source's disk entry in the scan table [S on its
      meaning].
  - It then **gives 50 blocks back** to the system (or all of them, if it has fewer than 50).
  - If **fewer than 10 blocks** remain: ShowTitle `"Ran out of memory.  Please free some and try
    again."` and the copy is abandoned. The `.info` has already been written and the icon is already displayed.
  - At the end of the operation, all the blocks, the two stacks and the context are freed.
- **Stream.** The reader walks the object recursively (Examine/ExNext, §6.9 point 6). It emits,
  for each entry, a **record** (28-byte header, marker $FE12) containing:
  - the type (file or directory);
  - the size;
  - `fib_Protection`;
  - `fib_Date`;
  - the name;
  - **the comment**;
  - then, for a file, the data in **512-byte chunks** (Read of min(remainder, 512)).
  **At level 0** (the duplicated object itself), the name emitted is **BumpRevision(name)**, truncated to
  25 characters as for the `.info`.
- **Writer**:
  - file: `Open(name, MODE_NEWFILE)`, Write of the chunks, Close;
  - directory: `Lock(name)`, then **CreateDir** if IoErr = 205, then UnLock. Descent is done
    with CurrentDir.
- **Attributes**: the writer reads protection, date and comment from the stream **but does not
  apply them**. The module has **no** SetProtection, SetComment or file-date vector
  among its dos calls (§3.6). The copied files therefore have the **current date**, the **default
  protection** and **no comment** [O by absence of these LVOs].
- **No `.info`**: without a WBObject, an object is not displayed by WB 1.3, so Duplicate cannot
  target a file without an icon. Inside a copied drawer, files without `.info`
  are copied like the others: the walk copies **all** entries, `.info` included, without
  distinction [O].
- **Errors**: those of §6.9 point 6 (`"accessing"`, `"opening"`, `"reading"`, `"writing"`).
  The first error stops the copy. What has already been created is **left in place**.

#### 7.9.5 Insufficient memory [O]

| Where | Message | Clean-up |
|---|---|---|
| WBArg array (Duplicate of a disk) | `"Ran out of memory.  Please free some and try again."` | nothing is launched |
| 536-byte context or a coroutine's stack (data copy) | **no message** | what has been allocated is freed; the copy's `.info` and icon remain, data not copied |
| Pool of fewer than 10 blocks | same message | blocks, stacks and context freed; `.info` and icon remain |
| GetWBObject of the copy (allocation in icon.library) | `"Cannot read info file copy of …"` | no data copy; `.info` present, **icon absent** until the next rescan |

---

## 8. Drawer windows: scroll gadgets and gauge


Notation: W, H = window size; BL/BT/BR/BB = its borders; DD = the object's DrawerData
(`+$4C`). The intuition rendering rules are in `intuition-prop-v34.md` and
`intuition-frame-v34.md`.

### 8.1 Window and gadget list [O]

- **Flags** passed when a drawer or a disk is opened: **$0240027F**. This comprises
  SIZING, DRAG, DEPTH, CLOSE, **SIZEBRIGHT, SIZEBBOTTOM**, SIMPLE_REFRESH, REPORTMOUSE,
  WBENCHWINDOW, plus a bit $00400000: **no effect** (intuition 34.3 never tests it in
  `Window->Flags`; it is the value of INTUITICKS; reopening a drawer whose DrawerData
  exists passes $0200027F, see `wb-icon-clipping-v34.md` §7) [O]. Icon clipping, erasing
  and scrolling: `wb-icon-clipping-v34.md`.
- **Six gadgets**, copied from ROM templates into the DrawerData and chained **in this
  order**:

| # | Gadget (GadgetID) | Copy in DD | LeftEdge, TopEdge, Width, Height | Flags | Activation | Type |
|---|---|---|---|---|---|---|
| 1 | vertical bar (2) | +$74 | −15, 16, 16, −31 | GRELRIGHT \| GRELHEIGHT \| GADGIMAGE ($0054) | RELVERIFY \| GADGIMMEDIATE \| RIGHTBORDER ($0013) | PROPGADGET (3) |
| 2 | horizontal bar (1) | +$48 | 13, −8, −40, 9 | GRELBOTTOM \| GRELWIDTH \| GADGIMAGE ($002C) | RELVERIFY \| GADGIMMEDIATE \| BOTTOMBORDER ($0083) | PROPGADGET |
| 3 | left arrow (3) | +$F8 | 2, −7, 12, 7 | GRELBOTTOM \| GADGIMAGE ($000C) | $0083 | BOOLGADGET (1) |
| 4 | right arrow (4) | +$124 | −25, −7, 12, 7 | GRELBOTTOM \| GRELRIGHT \| GADGIMAGE ($001C) | $0083 | BOOLGADGET |
| 5 | up arrow (5) | +$A0 | −14, 10, 14, 6 | GRELRIGHT \| GADGIMAGE ($0014) | RELVERIFY \| GADGIMMEDIATE \| RIGHTBORDER ($0013) | BOOLGADGET |
| 6 | down arrow (6) | +$CC | −14, −14, 14, 6 | GRELBOTTOM \| GRELRIGHT \| GADGIMAGE ($001C) | $0013 | BOOLGADGET |

- **Highlighting**: mode 0, i.e. **GADGHCOMP**, without SelectRender.
- **Bars**: GadgetRender = an empty `struct Image` in the DD (+$164 for the vertical one, +$150 for
  the horizontal one), which intuition fills in (AUTOKNOB). SpecialInfo = a PropInfo in the DD (+$18E
  vertical, +$178 horizontal).
- **Initial PropInfo** (common ROM template):
  - Flags = **AUTOKNOB**;
  - Pots = 0;
  - Bodies = **$FFFF**;
  - the rest at 0.
  Then **FREEVERT** is added to the vertical one and **FREEHORIZ** to the horizontal one.
- **Arrows**: GadgetRender = 4 global Images, prepared once at start-up in WB
  globals (images copied to CHIP memory). Each has **1 useful plane**:
  - PlanePick = 1, PlaneOnOff = 0;
  - set pixels = **pen 1** (white background), clear pixels = **pen 0** (blue drawing).
- **Arrow geometry** (to be redrawn freely):
  - **left**: 14×8 image, offset by (−2, −1) relative to the gadget. Chevron point "<"
    to the left, diagonal strokes 3 pixels wide, with a **horizontal shaft** on the
    middle line (y = 4) running from the point to the right edge;
  - **right**: 12×8 image, offset by (−1, −1). Mirror of the left one: chevron ">", shaft to
    the left;
  - **up**: 16×6 image, offset by (−1, 0). Chevron "^" in 2-pixel strokes, with a
    **2-pixel vertical shaft** in the centre (columns 7–8) that goes down to the bottom;
  - **down**: 16×6, offset by (−1, 0). Vertical mirror: "v" with a rising shaft.
- **Resulting borders** (§1.2 of `intuition-gzz-v34.md`) [D]:
  - BR = max(size gadget + 2, RIGHTBORDER gadgets);
  - BB = max(size gadget + 1, BOTTOMBORDER gadgets).
  - In hires, this gives a right border of 18 and a bottom border of about 10.

### 8.2 Content area and extent [O]

- **Content origin**:
  - left = BL, **plus 14 for a disk window** (the room for the gauge, §8.4);
  - visible width = W − left origin − BR;
  - visible height = H − BT − BB.
- **DrawerData**:
  - +$30 / +$34 = scroll position (X / Y);
  - +$38 / +$3C = minimum of the extent;
  - +$40 / +$44 = maximum of the extent.
- **Recomputation of the extent**, at opening, after Duplicate or after an icon insertion
  (§7.9.2 point 9), and after each scroll:
  - the minimum is the current position, the maximum is position + visible size;
  - then the extent is **widened to the box of each icon** of the drawer.
  - The root window (backdrop) has no bars: no update.

### 8.3 Body / Pot and scrolling [O]

**Computation**, in mathffp floating point, for each axis, with range = max − min and pos = max(0,
current − min):
- **Body = Fix(65535 × visible / range)**;
- **Pot** = **$7FFF** if range = visible; otherwise **Fix(65535 × pos / (range − visible))**.
- If Body or Pot changed: **NewModifyProp(gadget, window, NULL, Flags unchanged, Pot, Pot,
  Body, Body, 1)**. The same values go into H and V; only the free axis matters. A single gadget
  is redrawn.

**Scrolling**:
- **GADGETDOWN** on one of the 6 gadgets: the WB records the window and the gadget.
  - On an **arrow without Shift**: it adds **INTUITICKS** to the window's IDCMP, for
    repetition.
  - On a **bar**, or an **arrow with Shift** (qualifier & 3): "one-shot" mode.
- **Step per event** (INTUITICKS or MOUSEMOVE while pressed):
  - **left / right arrow**: X −= / += **visible width / 8** (Shift: **±1 pixel**);
  - **up / down arrow**: Y −= / += **visible height / 8** (Shift: **±1 pixel**);
  - **horizontal bar**: X = Fix(HorizPot / 65535 × (X range − X visible)) + min X;
  - **vertical bar**: Y = same formula with VertPot.
  - If the value does not change, nothing is done.
- **After each change**: new position in DD +$30 / +$34, then recomputation of
  the extent and of the bars (above), then scrolling and redisplay of the contents.
- **GADGETUP**: end of scrolling. The flag is cleared and INTUITICKS is removed from the IDCMP
  if it had been added.

### 8.4 Fill gauge (disk windows) [O]

**Location**: drawn in the window's RastPort, against the left edge, from **x = 2 to
x = BL + 9**. The contents start at BL + 14.

**Frame**:
- **top block**: RectFill in **pen 2** from (2, BT−1) to (BL+9, BT+5), with an **"F"**
  drawn as lines (Move/Draw) in **pen 1**: top bar, 2-pixel upright on the left,
  shorter middle bar;
- **bottom block**: RectFill in pen 2 from (2, H−BB−6) to (BL+9, H−BB), with an **"E"** in
  pen 1 (2-pixel upright, three bars);
- **rule**: RectFill in **pen 1** from (BL+10, BT−1) to (BL+11, H−BB), to the right of the gauge
  over the full height.

**Bar**, between y0 = BT + 6 and y1 = H − BB − 7 (height h = y1 − y0):
- **filled = Fix(used × h / total + 0.5)**, rounded, with used = `id_NumBlocksUsed` and
  total = `id_NumBlocks` of the volume's InfoData;
- empty part (at the top): RectFill **pen 2** from (2, y0) to (BL+9, y0 + h − filled);
- filled part (at the bottom): RectFill **pen 3** from (2, y0 + h − filled) to (BL+9, y1).
- A line in pen 2 then in pen 1 marks the line y = H − BB, below the gauge.

**Update**:
- when the disk window is opened;
- when the volume's InfoData is re-read (Info, for example after a write or at the rescan) [D for the
  exact list].
- Nothing is drawn if the Workbench is "closed" (bit 0 of G+$22) or if the window is not
  open.

---

## Clean-room review

- [x] No listing, no instruction sequence transcribed or paraphrased line by line: only
  **layouts** (ROMTag, LoadWB message, MsgPort, NewWindow, WBStartup,
  DosPacket), **constants** (Alert codes, window flags, IDCMP, dos action numbers, sizes)
  and **library call sequences** (public API contract) are given.
- [x] §1.2/§1.3 describe the **effect** of the 8 entry bytes (selector, OR on D0) and the resulting ABI
  constraint (D0 = 0 on entry to a C process), not their encoding: the implementation
  track does not have to reproduce them (its own workbench.task module can have any
  form, as long as `(tag+42)>>2` gives a correct executable segment — for example placing its
  ROMTag at an address ≡ 2 mod 4 is **not** required; it is enough that `BADDR((tag+42)>>2)+4` is a
  valid entry point).
- [x] **Correction of 2026-10-29**: removed the 47 remaining ROM addresses (ROMTag, `rt_Name`,
  `rt_IdString`, `rt_Init`, `rt_EndSkip`, entry points, `main`, main loop, abort,
  title-display and Info routines, "Landmark" column of §3.1, exec's AddTask, the
  "Workbench" string) and the description of the encoding of the entry points ("padding", operation on
  D0); kept: positions relative to the tag imposed by `c:LoadWB` (+26/+34/+42/+44) and observable
  effect (selector, `D0 := D0 OR 2`).
- [x] The LVO names beyond the 1.3 AutoDocs (−426…−468 intuition, −504…−534 graphics) are
  deduced from the order of the public `.fd` files and marked [D].
- [x] The disk items (LoadWB) are limited to the interface (message, seglist, SetFunction) already
  known to the implementation track.
- [x] Reported correction of `boot-sequence.md` (strap does not launch workbench.task).
- [x] §6 (reviewed): only strings, offsets of globals/public structures
  (lib_Version +$14, lib_Revision +$16, ROM header +$0C/+$0E), library calls
  (RawDoFmt, DisplayBeep, SetWindowTitles, OpenLibrary/CloseLibrary, AvailMem, IoErr, SetFunction)
  and behaviour rules (flags, display conditions). The LoadWB patch is described by
  its **effect** on the string (prefix comparison, bytes rewritten, pointer substitution)
  and the XOR $9E transformation of the strings — no instruction sequence copied. §3.4 remains
  valid; §6.4 refines it (bit 2, G+$2F2 = −1 initially).
- [x] §6.8 (reviewed): activation rules described by their effect (public Window/Screen/
  IntuitionBase fields, conditions, fallback order Parent → FirstWindow → NULL), no instruction
  sequence of intuition or of the workbench copied.
- [x] §6.9 (reviewed): table "user operation → failing dos call → message", with action
  index, `%s` argument, tolerated codes (205, 232), dos packets (17, 9) and requester rules.
  No instruction sequence transcribed.
- [x] §7 (reviewed): info.library is described by its calling contract (registers, LVO), the
  WBObject fields read and written (offset and meaning), the library calls and the strings displayed.
  No instruction sequence of the library or of the Workbench is copied.
- [x] §7.8 (reviewed): icon.library is described by its LVO table, its allocation sizes, its
  DiskObject field → WBObject offset mapping and the contents written to the `.info`. No
  instruction sequence copied.
- [x] §7.9 (reviewed): Duplicate is described by rules (order of the public dos and icon calls,
  +30/+15 offset, buffer sizes, attributes not copied, messages). No instruction
  sequence copied.
- [x] §7.9.1, DiskCopy complement (reviewed): contents of the WBArgs, launch fields and
  DiskCopy exit conditions, described by rules and public dos fields. No instruction
  sequence copied.
- [x] §8 (reviewed): gadgets, PropInfo, Body/Pot formulas and gauge described by rules, public fields
  and geometry. The arrow images and the letters F/E are described by shape, not as a bitmap.
  No instruction sequence copied. Complement to §7.9.3 [O]: bit 4 of `+$3C` is set
  when an icon is dropped on the root window (backdrop), with a DupLock of the original
  directory in `+$A4`; it is cleared when it is put back into a drawer.
