# disk-change-v34.md — floppy change in 1.3: ROM file system, input events, Workbench

> ANALYSIS track ("dirty"). Sources: the ROM `assets/kick34005.A500` (file system = dos segarray
> entry 6, validator = entry 7, module `wb 34.1`), and **black-box probes** on the real ROM
> (FS-UAE, Workbench 1.3.3 `[m2]` + `OctaMED Professional v4.00` + home-made disks) with the probe
> `tests/dskchg.s` and the harness `tests/dskchg_run.sh`.
> Same conventions as `handlers-v34.md`, `boot-clock-v34.md` and `workbench-task-v34.md`: **BPTR**
> = address/4; DosList node seen in longs `!0..!10`; for a **volume** (dn_Type 2):
> `+$08 dl_Task`, `+$0C dl_Lock`, `+$10..+$1B dl_VolumeDate`, `+$1C dl_LockList`, `+$20 dl_DiskType`,
> `+$28 dl_Name` (BSTR). InfoData (9 longs): NumSoftErrors, UnitNumber, DiskState, NumBlocks,
> NumBlocksUsed, BytesPerBlock, DiskType, VolumeNode (BPTR), InUse.
>
> **Legend**: **[O]** observed (ROM or probe) · **[D]** deduced from converging observations ·
> **[S]** assumed.
>
> This document describes behaviours, ABI layouts and constants. **No instruction
> sequence is reproduced or paraphrased.**

Related specs (not repeated here): `workbench-task-v34.md` §3.3 (disk scan), §3.4 (5 s tick),
§3.5 (loop); `boot-clock-v34.md` §1 and §4.2 (validator, lookup/creation of the volume node);
`handlers-v34.md` §4.1 (deviceproc and the "Please insert volume" requester) and §5 (RAM:).

---

## 0. Executable summary

1. **Detection**: each floppy file system (FS) installs at startup a
   **TD_REMOVE (12)** interrupt with trackdisk; it only **resets a "disk
   changed" flag to 0**. The FS tests this flag at **each wake-up** of its loop (packet received or **1 s
   timer tick**, UNIT_VBLANK); flag at 0 ⇒ it sets it back to "seen" then queries **TD_CHANGESTATE (14)**.
   No polling of TD_CHANGENUM, no TD_ADDCHANGEINT (V36). [O ROM]
2. **Ejection**: the FS now answers `DiskType = −1`; it **detaches the current volume**:
   if it has **no lock** open ⇒ the volume node is **removed from the DosList and freed**; otherwise its
   locks are hooked onto `dl_LockList` and **`dl_Task := 0`** (the node stays in place). Then
   **IECLASS_DISKREMOVED** event. Observed delay: 0.1–0.3 s after the increment of
   TD_CHANGENUM. [O]
3. **Insertion**: the FS launches the **"Validator"** process; it reads the boot block and the
   root block, **finds the volume node with the same name AND the same creation date** (reused:
   `dl_Task := FS port`, locks re-adopted, `dl_LockList := 0`) or **creates one at the head of the list**
   (`dl_VolumeDate` = creation date of the root block, `dl_Lock = 0`, `dl_LockList = 0`,
   **`dl_DiskType = 0`**). Bitmap re-read (or disk revalidated) at **every** insertion. At the end of the
   validator: **IECLASS_DISKINSERTED**, including for a non-DOS disk. Observed delays: node
   +1.0–1.6 s, DISKINSERTED +1.2–2.4 s. [O]
4. **Events**: IECLASS_DISKREMOVED (15) / IECLASS_DISKINSERTED (16) are **written by the FS
   itself** into input.device (IND_WRITEEVENT) — neither trackdisk nor input.device generate them.
   intuition broadcasts them as IDCMP **DISKREMOVED ($10000) / DISKINSERTED ($8000) to all the
   windows that request them** (inactive window included), timestamped with the current time. [O]
5. **Workbench**: the backdrop receives these IDCMPs ⇒ **rescan** of the DosList (also at the 5 s tick).
   - new volume mounted (`dl_Task ≠ 0`, unknown) ⇒ icon `Disk.info` from its root, otherwise
     **default icon** (32×16, 2 planes, ROM); label = **volume name**; position = that of the
     `.info` if it overlaps no icon, otherwise **automatic placement** (96 px columns
     from the right, first gap from the top, §4.3);
   - ejected volume: the icon **stays** as long as the node exists (open locks, open window…),
     it **disappears** when the node is removed (disk without lock);
   - non-DOS disk in DF0: ⇒ default icon named **`"DF0:" + 4 bytes of the DiskType`**
     (`DF0:NDOS`, `DF0:BAD`, `DF0:` for a type 0…), removed on ejection;
   - **RAM DISK**: icon as soon as the "RAM DISK" volume exists with `dl_Task ≠ 0` (created by
     L:Ram-Handler at the first access to RAM:, here StartupII's `makedir ram:t`), default image
     (no `Disk.info` in RAM:), label "RAM DISK", placed automatically. [O]

---

## 1. Method (to reproduce)

- Probe `tests/dskchg.s` launched by `run >NIL: dskchg <opts>` just before `LoadWB` in the
  startup-sequence of a copy of the Workbench disk (assembly `-kick1hunks`: the 1.3 LoadSeg refuses
  HUNK_RELOC32SHORT, "file is not an object module"). Every 100 ms: DISKINSERTED/
  DISKREMOVED IDCMP of a 60×10 BORDERLESS window on the WB screen (not active), snapshot of the
  DosList (new/modified/vanished nodes), option D = ACTION_DISK_INFO to the DF0 handler every
  second, option T = TD_CHANGENUM/TD_CHANGESTATE ("hardware" time reference), options L/A
  = lock kept on `DF0:c` then access 3 s after the ejection. Log in memory (address at `$3F0`)
  read back with the FS-UAE debugger. Timestamp `t` = loop counter (≈ 0.1 s).
- Floppy change: **FS-UAE F12 menu** driven by keyboard (`dskchg_run.sh`, command
  `media`). The `keyboard_key_* = action_*_floppy_*` shortcuts are ignored when injected
  by xdotool. The menu pauses emulation: the delays below are measured in **emulated**
  time, relative to the TD_CHANGENUM increment seen by the probe.
- Disks: WB 1.3.3 (volume `Workbench1.3`, creation date [$1616,$4DB,$432]), OctaMED
  (`OctaMEDv4`, creation date [$188F,$406,$8F7], `Disk.info` 112×67 at (264, 2)), entirely
  null ADF, `TestVol` (new OFS, OctaMED's `Disk.info` moved to (560, 10)), `BadRoot` (root block of
  type 7, correct then incorrect checksum).

---

## 2. A — The ROM file system of DF0: (FS) during a change

### 2.1 Detection (A1) [O ROM, delays O probe]

- At startup, the FS opens **timer.device unit 1 (UNIT_VBLANK)** and **input.device unit 0**,
  prepares an **Interrupt** structure (22 bytes, public) whose `is_Data` points to a **"disk
  changed" flag** and whose code merely writes 0 into the long pointed to by `is_Data`
  (A1), then installs it by **TD_REMOVE (12)** on its trackdisk IORequest. The flag starts at 0
  ("changed") ⇒ a first mount is attempted from the first pass of the loop.
- The timer request is re-armed with **tv_secs = 1, tv_micro = 0** (TR_ADDREQUEST): the FS wakes up
  at least once per second even without a packet (`boot-clock-v34.md` §4.3).
- At each wake-up (before processing the received packet): if the flag is 0 ⇒ flag := −1; then,
  **unless the FS is inhibited (ACTION_INHIBIT) or a validation is already in progress** [O for
  the inhibition; D for "validation in progress", internal counter not elucidated in detail],
  **TD_CHANGESTATE (14)** (io_Actual: 0 = disk present):
  - **present** ⇒ start of the validator (§2.5);
  - **absent** ⇒ ejection (§2.2.1).
- Consequence: the FS latency = detection by trackdisk (its own polling of the /CHNG
  line, not measured here) + at most ~1 s. Measured (emulated time, from the increment of
  TD_CHANGENUM): ejection recognised in **0.1–0.3 s**. [O]

### 2.2 Volume nodes of the DosList (A2)

#### 2.2.1 Ejection [O ROM + O probe]

1. FS `DiskType` := **−1** (DISK_INFO replies, §2.3).
2. If either of two internal states of the FS is non-zero (semantics [S]: activity/writes in progress),
   the FS calls dos's error requester (**errorreq, code 3, node of the current volume**) and
   **does not abandon** the volume: it resumes its loop without detaching [O for the call and the
   non-detachment; text and exact condition not recorded by probe].
3. Otherwise: emptying of the buffer lists, **CMD_CLEAR (5)** on trackdisk, then **detachment of the
   current volume**:
   - **no lock open** on the volume (internal lock list empty) ⇒ the node is **removed from the
     DosList** (under Forbid) and **freed, along with its name**. Observed: `X` of the `OctaMEDv4` node on
     ejection (no window open);
   - **at least one lock** ⇒ the lock list is **hooked at the end of `dl_LockList`**, then
     **`dl_Task := 0`**. The node keeps its place, `dl_Lock`, `dl_VolumeDate`, `dl_DiskType`
     unchanged. Observed: `Workbench1.3` (locks of the SYS:, C:… assigns): `+$08` C00ADC → 0,
     `+$1C` 0 → BPTR of the lock chain (= the old `id_InUse`); `OctaMEDv4` with its WB
     window open: same.
4. **IECLASS_DISKREMOVED** event (§3), then the FS answers the following packets.

#### 2.2.2 Insertion of a DOS disk [O ROM (validator, `boot-clock-v34.md` §4.2) + O probe]

- The validator looks in the DosList for a **dn_Type 2** node with the **same name** (case-insensitive BSTR
  comparison, name = BSTR of the root block, 1..30 characters) **and** an **equal date**
  (`dl_VolumeDate` == longs 121..123 of the root block = **creation date**). It **does not look at**
  `dl_Task` (two identical disks would share the same node [D]).
- **Found** (reinsertion): only **`dl_Task := FS port`** is written by the validator. When the
  FS receives the validator's reply, it **re-adopts the locks of `dl_LockList`** (each `fl_Task`
  := its port, added to its internal list) then **`dl_LockList := 0`**. Observed: reinsertion of
  `Workbench1.3` and of `OctaMEDv4` (window open): **same node address**, same rank, `+$08` :=
  C00ADC, `+$1C` := 0. [O]
- **Not found**: `makedevnode(name)` ⇒ new node **inserted at the head of the DosList**, `dn_Type := 2`,
  `dl_Lock := 0`, `dl_LockList := 0`, `dl_VolumeDate := longs 121..123`, `dl_Task := FS port`,
  **`dl_DiskType` left at 0** and `+$24` at 0. Observed:
  `N 0 adr 2 C00ADC 0 188F 406 8F7 0 0 0 OctaMEDv4` (rank 0). [O]
- The `dl_DiskType` of floppy volumes is therefore **0** in 1.3 (unlike the "RAM DISK" node
  that L:Ram-Handler fills with `'DOS\0'`). [O]
- Delays (emulated time, from the TD_CHANGENUM increment): node created or reactivated **+1.0 to
  +1.6 s**; DISKINSERTED **+2.0 to +2.4 s**; `id_DiskState` goes from 81 to 82 just after. [O]

#### 2.2.3 Direct change (disk A replaced by B)

There is **no particular state**: trackdisk sees an ejection then an insertion (two
increments of TD_CHANGENUM); the FS chains §2.2.1 then §2.2.2. Observed `Workbench1.3` → `OctaMEDv4`:
DISKREMOVED, WB `dl_Task` := 0, then new OctaMED node and DISKINSERTED. [O]

### 2.3 Replies to ACTION_DISK_INFO (25) and ACTION_INHIBIT (31) (A3)

**DISK_INFO** (Res1 = −1 always) fills the InfoData from the current state of the FS [O ROM + O probe]:

| Field | Value |
|---|---|
| NumSoftErrors | FS counter (0 observed) |
| UnitNumber | `fssm_Unit` (0) |
| DiskState | **81 ID_VALIDATING** as long as no bitmap is loaded (validation in progress, non-DOS disk, no disk after a failed mount); otherwise **80 ID_WRITE_PROTECTED** if protected, **82 ID_VALIDATED** otherwise |
| NumBlocks / NumBlocksUsed / BytesPerBlock | geometry (1758 / … / 488 in OFS DD); **not reset** on ejection (values of the previous disk) |
| DiskType | **−1** without a disk; **`'BUSY'` ($42555359)** during an active INHIBIT; otherwise the value returned by the validator: `'DOS\0'`, **`'NDOS'`** (`DOS\0` boot block but invalid root block), **`'BAD\0'`** (block 0 unreadable), or **the first long of block 0 as is** when it is not `'DOS\0'` (0 for a null disk, `'KICK'` [D] …) |
| VolumeNode | BPTR of the current volume node; **0** without a disk or with a non-DOS disk |
| InUse | head (BPTR) of the internal lock list; 0 if none |

Sequence observed on ejection then reinsertion: `52,DOS,vol,locks` → ejection `52,−1,0,0` →
detection of the insertion `51,−1,0,0` → node ready `51,DOS,vol,0` → validator finished
`52,DOS,vol,…`. Null disk: `51, 0, 0, 0`; type 7 root: `51,'NDOS',0,0`. [O]

**INHIBIT** (Arg1) [O ROM]: Arg1 ≠ 0 ⇒ the FS goes into the inhibited state: abandon of a validation in
progress, detachment of the volume **like an ejection** (§2.2.1 point 3, without input event) and
`DiskType := 'BUSY'`; Arg1 = 0 ⇒ end of inhibition and **"disk changed" flag reset to 0** ⇒
full remount (validator) at the next wake-up. Reply Res1 = −1. (It is this remount that gives the
DISKINSERTED seen at boot after `LoadWB delay` / MountMF.) [O probe for the boot DISKINSERTED]

### 2.4 Locks and FileHandles on an absent volume (A4)

- The FS **refuses** any packet carrying a lock (or a FileHandle) whose volume is not the
  current volume: **Res1 = 0, Res2 = 218 (ERROR_DEVICE_NOT_MOUNTED)**; exception: closing
  (ACTION_END, 1007) answers Res1 = −1. [O ROM]
- User side [O probe]: `Examine()` on a kept lock of `Workbench1.3:` after ejection ⇒
  system requester **"Please replace volume / Workbench1.3 / in any drive"**, buttons **Retry /
  Cancel**, "System Request" window at (0, 0) of the WB screen. It **disappears on its own on
  reinsertion** of the right disk (the call then completes: `Examine` = −1, IoErr 0), without a click.
  The `Lock("Workbench1.3:c")` and `Lock("DF0:")` issued afterwards complete normally.
- An **unknown** volume name or one without a handler gives "Please insert volume … in any drive"
  (`handlers-v34.md` §4.1). The exact split of the two texts between dos and the FS is not settled here
  [S: "replace" when the volume is known (node present, `dl_Task = 0`), "insert" when it is
  not].
- On reinsertion, locks and FileHandles become valid again (same node, locks re-adopted §2.2.2). [O
  for the locks, D for the FileHandles]

### 2.5 Revalidation on insertion (A5) [O ROM + O probe]

- **Every** insertion relaunches the **Validator** process (segarray entry 7, `boot-clock-v34.md` §1):
  block 0 (disk type), root block (checks: type 2, header key 0, table size 72,
  secondary type 1, name 1..30 chars), lookup/creation of the node (§2.2.2), then **re-read of the
  bitmap** if the root block's bitmap flag is valid, **full validation** otherwise. The bitmap
  of the old disk is freed by the FS as soon as the new insertion occurs.
- Validator reply to the FS in two stages: (1) reply to the startup packet (DiskType, volume
  node) ⇒ the FS stores the type, reads **TD_PROTSTATUS (15)** and re-adopts the locks; (2) at the end,
  a packet from the validator carrying the bitmap ⇒ the FS installs the bitmap and **emits DISKINSERTED**.
  For a non-DOS disk stage (2) also takes place (without bitmap): DISKINSERTED is emitted anyway. [O]
- Unreadable root block or wrong checksum: validator requester **"Error validating disk" /
  "Key 880 checksum error"**, Retry / Cancel; as long as it is displayed, neither DISKINSERTED nor icon;
  ejection makes it disappear. [O probe]

---

## 3. B — Input events

- **Emitter**: the FS of the unit concerned (one per DFx drive), via its input.device IORequest:
  **IND_WRITEEVENT (11)**, `io_Data` = an InputEvent **entirely reset to 0** then `ie_Class` :=
  **15 (IECLASS_DISKREMOVED)** or **16 (IECLASS_DISKINSERTED)** (SubClass, Code, Qualifier,
  EventAddress, TimeStamp = 0), `io_Length` = 26; **asynchronous** send (SendIO). [O ROM]
- **Moments**: DISKREMOVED just after the detachment of the volume (§2.2.1); DISKINSERTED at the end of the
  validator (§2.5), hence **after** the volume node is in place and `dl_Task` set — a rescan
  triggered by the event therefore finds the volume mounted. [O]
- Neither trackdisk nor input.device emit these classes themselves [O: the only
  "input.device" string of the dos/FS segments is the FS's; trackdisk only opens timer.device].
- **intuition**: each event becomes an IntuiMessage of class **DISKREMOVED ($00010000)** /
  **DISKINSERTED ($00008000)** delivered to **all the windows** whose IDCMP contains that bit, active
  or not (the probe's window, never active, receives them). `im_Seconds/im_Micros` = **current system
  time** (non-zero) although `ie_TimeStamp` is 0. [O probe] (Broadcast to
  windows of other screens: [S], not tested.)
- The Workbench requests them on its backdrop (IDCMP $DC76E includes $18000 + NEWPREFS,
  `workbench-task-v34.md` §3.2); system requesters (AutoRequest) use them to
  close on their own on insertion (§2.4). [O / D]

---

## 4. C — Workbench (observable)

### 4.1 Triggers and walk [O ROM, cf. `workbench-task-v34.md` §3.3]

Full rescan: at startup, at **each DISKINSERTED/DISKREMOVED IDCMP** of the backdrop, at each
**5 s tick**, at WBENCHOPEN. Walk of the DosList under Forbid; for each volume:

| Case | Effect |
|---|---|
| volume **unknown** to the WB | new "new" entry ⇒ mount: root lock (ACTION_LOCATE_OBJECT to the `dl_Task`), Info, `GetWBObject("Disk")`, icon (§4.2); failure ⇒ entry removed |
| known, `dl_Task ≠ 0` | "active" (nothing to redraw) |
| known, `dl_Task = 0` | "removed": if the disk object has **no window open** [D: usage counter of the object = 1], the WB **frees its own root lock**; then it looks in the DosList for a volume with the **same name and same `dl_VolumeDate`**; found (including **this same node**) ⇒ the icon **stays** (attached to that node); otherwise the icon and the entry are deleted |
| entry whose node is no longer in the DosList | icon and entry deleted |

For each **device** retained (DF0: etc.): **ACTION_DISK_INFO**; `DiskType` ∈ {`'DOS\0'`, −1} ⇒
no device icon (and deletion of the one that existed); otherwise "device" icon (§4.5).

### 4.2 Icon of a new volume [O ROM + O probe]

- **Image / object**: `Disk.info` of the root (via icon.library); absent ⇒ **default disk
  object**: type **WBDISK (1)**, gadget **32×16**, Flags 5 (GADGIMAGE|GADGHBOX), Activation 3,
  GadgetType 1 (BOOLGADGET), ROM image **32×16, 2 planes, PlanePick 3** (white floppy with an orange
  shutter, copied into CHIP), **CurrentX = CurrentY = NO_ICON_POSITION**, **default tool
  `"SYS:System/DiskCopy"`**.
- **Label**: volume name (`RAM DISK`, `Workbench1.3`, `OctaMEDv4`, `TestVol`), centred under
  the image.
- **Position**: rule of §4.3, applied before the addition to the backdrop.

### 4.3 Placement rule on the backdrop [O ROM; measurements O probe]

Notation: `W` = width of the backdrop window, `H` = its height − 5, `w`,`h` = width/height
of the icon's gadget, `m` = **tf_YSize of the WB font + 3** (topaz 8 ⇒ 11, the room for the label).
Window coordinates (borderless backdrop).

1. **Position of the `.info` kept** if it is not NO_ICON_POSITION **and** if the rectangle
   `[X−2, X+w+2] × [Y−m, Y+h+m]` touches **no** icon already on the backdrop. Observed:
   OctaMED at (264, 2), far from the others ⇒ kept. [O]
2. Otherwise (no position, or overlap) **search for a gap**:
   - columns of **96 px**, from right to left: `x0 = W−96, W−192, …` as long as `x0 ≥ 0`;
   - within a column, the icons whose horizontal extent `[X, X+w]` touches
     `[x0, x0+96[` are considered, **sorted by increasing Y**; candidate `y = 5`; for each: if
     `y + h + m ≤ Y_icon` ⇒ gap found; otherwise `y := max(y, Y_icon + h_icon + m)`;
   - accepted if `y + h + m ≤ H`: **Y = y**, **X = x0 + (96 − w)/2** (integer division, may be
     negative if w > 96);
   - no column ⇒ **X = W − 60, Y = 5**.
3. Measurements (640 px WB screen): RAM DISK (default, w 32) at X ≈ 576; `Workbench1.3` (`Disk.info`
   35×16 without position) at X ≈ 574, below RAM DISK; non-DOS disk below Workbench; `TestVol`
   (112×67, position (560, 10) which overlaps RAM DISK) **moved** below Workbench1.3 at X ≈ 536.
   Vertical step measured between two stacked icons of height 16: **≈ 28 lines** (the rule gives
   h + 11 = 27; difference within the measurement uncertainty of ±1.5 lines). Order: the column fills in
   the order of the DosList volumes (the most recent at the head: RAM DISK before Workbench1.3 at boot). [O]

### 4.4 Ejection [O probe + O ROM]

| Situation | Icon | Disk window |
|---|---|---|
| disk **without** lock (OctaMED without window) | **disappears** at the rescan following DISKREMOVED | — |
| disk with locks (Workbench1.3: assigns, CLI) | **stays** (same image, same place) | — |
| disk window **open** (OctaMED) | **stays** (selected if it was) | **stays open** with its icons |
| reinsertion of the same disk | nothing changes visually (same node, same entry) | same |
| non-DOS disk ejected | `DF0:…` icon **disappears** | — |

### 4.5 Non-DOS disk [O ROM + O probe]

"Device" icon (object type 7) with the **default disk object** (§4.2), label =
**device name + `:` + the 4 bytes of `id_DiskType`** copied as is, the string stopping at the
first null byte: `DF0:NDOS` (invalid root, observed), `DF0:` (null disk, type 0, observed),
`DF0:BAD` (`'BAD\0'`), `DF0:BUSY` during an INHIBIT [D]. If the type changes, the icon is recreated
with the new name. Nothing for `'DOS\0'` nor for −1 (empty drive). Placement: §4.3 (observed below
Workbench1.3).

### 4.6 Delays [O probe, D]

The icon of an inserted disk appears at the rescan triggered by **DISKINSERTED** (≈ 2 emulated s after
the insertion for a DOS disk); capture at 3–4 wall-clock s after the end of the menu: the `TestVol` icon
absent at +3 s, present at +4 s. Failing an event, the 5 s tick catches up. Disappearance follows
DISKREMOVED (≈ 0.2 s). The "free memory" title text is refreshed by the same tick.

### 4.7 RAM DISK [O]

- Condition: a **volume** node "RAM DISK" with `dl_Task ≠ 0`. It only exists after the **first
  access to RAM:** (L:Ram-Handler creates it, `handlers-v34.md` §5); on WB 1.3.3, StartupII's `makedir ram:t`
  creates it **before** `LoadWB` ⇒ the icon is there from the first display.
- Node observed: `+$04 = 2`, `+$08` = RAM port, `+$0C = 0`, **date = 0**, `+$1C = 0`,
  **`+$20 = 'DOS\0'`**, `+$24` not initialised, name `RAM DISK`.
- Image: default object (RAM: has no `Disk.info`); label `RAM DISK`; position §4.3:
  at the top of the right-hand column (X ≈ 576, Y = 5). RAM DISK is never ejected.

---

## 5. D — Test vectors (what a conforming ROM must show)

| # | Input | Expected observable output |
|---|---|---|
| V1 | Boot WB 1.3.3 | icons `RAM DISK` (default disk) then `Workbench1.3` below, right-hand column |
| V2 | Eject the WB (assign locks) | node `Workbench1.3`: same address, `dl_Task = 0`, `dl_LockList ≠ 0`; DISKREMOVED IDCMP; DISK_INFO: type −1, VolumeNode 0, InUse 0; **Workbench1.3 icon still there** |
| V3 | Then insert OctaMED | node `OctaMEDv4` **at the head** of the DosList, date [$188F,$406,$8F7], `dl_Lock = dl_LockList = dl_DiskType = 0`; DISKINSERTED ≈ 2 s later; DiskState 81 then 82; **OctaMED icon at (264, 2)** |
| V4 | Eject OctaMED (without window) | node **removed** from the DosList; DISKREMOVED; OctaMED icon **disappears** |
| V5 | Reinsert the WB | **same node** reactivated (`dl_Task := port`, `dl_LockList := 0`); DISKINSERTED; no new icon |
| V6 | Directly replace WB with OctaMED | DISKREMOVED then DISKINSERTED; same states as V2 + V3 |
| V7 | Open OctaMED's window then eject it | node kept (`dl_Task = 0`, `dl_LockList ≠ 0`); icon and window stay; reinsertion ⇒ same node |
| V8 | All-zero disk | DISKINSERTED; DISK_INFO: type 0, state 81, VolumeNode 0; default icon **`DF0:`** below the column; ejection ⇒ disappears |
| V9 | `DOS\0` boot block, type 7 root (correct checksum) | type `'NDOS'`; icon **`DF0:NDOS`** |
| V10 | Root with wrong checksum | requester "Error validating disk / Key 880 checksum error" (Retry/Cancel); no icon; ejection ⇒ requester closed |
| V11 | Lock kept on `DF0:c`, eject, `Examine(lock)` | requester "Please replace volume / Workbench1.3 / in any drive"; reinsertion ⇒ requester closed on its own, Examine = −1 |
| V12 | `Disk.info` whose position overlaps RAM DISK | icon moved into the right-hand column at the first gap (below Workbench1.3), X = W−96+(96−w)/2 |
| V13 | Window with IDCMP DISKINSERTED\|DISKREMOVED, never active | receives both classes; `im_Seconds` ≠ 0 (current time) |
| V14 | ACTION_DISK_INFO during INHIBIT(1) | DiskType `'BUSY'`; after INHIBIT(0): remount, DISKINSERTED [O ROM, not probed] |

---

## 6. Open points

- Detection delay **by trackdisk** itself (polling of /CHNG, motor stopped): not measured
  (FS-UAE menu paused); only the FS delay (≤ ~1 s after the TD_REMOVE interrupt) is established.
- Semantics of the two internal states that prevent detachment on ejection (§2.2.1 point 2),
  text of the corresponding requester (ROM path seen, not probed); split "replace" / "insert" between dos and FS (§2.4).
- What happens to the node when the **last lock of an absent volume** is freed (ACTION_FREE_LOCK
  on a lock of `dl_LockList`): is the node then removed? [not analysed]
- Exact vertical step between stacked icons: rule h + tf_YSize + 3 (code) versus ≈ 28 lines measured
  (measurement uncertainty) — to be recalibrated on a capture of our ROM.
- Broadcast of the disk IDCMPs to windows of screens other than the WB; disks in DF1:–DF3: (same
  FS, not probed); `'KICK'` and `'BAD\0'` not probed (deduced from the code).

---

## 7. Traceability appendix (landmarks, analysis track only)

- ROM address landmarks: removed at the clean-room review (not transmitted to the implementation track; the analysis
  track finds them again in the ROM if needed).
- Probes: `tests/dskchg.s`, `tests/dskchg_run.sh`, `tests/dskchg_dump.py`; working ADFs outside the repository.

---

## Clean-room review

- [x] No instruction sequence transcribed or paraphrased: the FS, the validator and the Workbench
  are described by their **effects** (DosList fields, InfoData, InputEvent, IDCMP), **public device
  commands** (TD_REMOVE 12, CMD_CLEAR 5, TD_CHANGESTATE 14, TD_PROTSTATUS 15,
  IND_WRITEEVENT 11, TR_ADDREQUEST), **dos action codes** (25, 31, 1007), constants
  (ID_*, IECLASS_*, IDCMP, disk types) and **rules** (name + date lookup, placement by
  96 px columns).
- [x] The FS's TD_REMOVE interrupt routine is described by its effect (setting the `is_Data` long
  to 0), not by its encoding.
- [x] No ROM routine address (appendix §7 expurgated at the review).
- [x] The "probe" facts come from screen captures and a DosList log (public
  structures), without disassembly of the disks' code.
