# disk-change-v34.md — floppy change in 1.3: ROM file system, input events, Workbench

> ANALYSIS track ("dirty"). Sources: the ROM `assets/kick34005.A500` (file system = dos segarray
> entry 6, validator = entry 7, module `wb 34.1`), and **black-box probes** on the real ROM
> (FS-UAE, the Workbench 1.3.3 boot disk + `OctaMED Professional v4.00` + home-made disks) with the probe
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
   No polling of TD_CHANGENUM, no TD_ADDCHANGEINT. [O ROM] (*Corrected 2026-11-02, see
   trackdisk-raw-changeint-v34.md §5: TD_ADDCHANGEINT exists and works in V34, it is not V36; the FS simply
   does not use it.*)
2. **Ejection**: the FS now answers `DiskType = −1`; it **detaches the current volume**:
   if it has **no lock** open ⇒ the volume node is **removed from the DosList and freed**; otherwise its
   locks are hooked onto `dl_LockList` and **`dl_Task := 0`** (the node stays in place). Then
   **IECLASS_DISKREMOVED** event. Observed delay: 0.1–0.3 s after the increment of
   TD_CHANGENUM. [O] A pending write-back is then lost silently; only an ejection **during** a transfer gives
   the "You MUST replace volume" requester instead, which blocks the operation until Retry with the disk back
   or Cancel (§2.2.1 point 2). [O]
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
- Ejection during disk activity (§2.2.1 point 2, 2026-11-09): real ROM in headless Amiberry sessions
  (`amiberry-session start --analysis`, cycle-exact A500), a copy of the Workbench 1.3.3 boot disk whose
  startup-sequence only runs SetPatch and leaves the boot CLI open, in DF0; blank OFS disks made with
  `xdftool` in DF1 (fresh copy and name per run). Ejection and insertion through the Amiberry IPC commands
  `EJECT_FLOPPY 1` / `INSERTFLOPPY <adf> 1`, commands typed with IPC keys, timing from the moment the CLI
  prompt came back (cursor position on IPC screenshots), screens read on IPC screenshots, disk contents
  read with `xdftool` on the image after the ejection. Times are wall-clock with the emulator at normal
  speed (±0.3 s, the screenshot period).

---

## 2. A — The ROM file system of DF0: (FS) during a change

### 2.1 Detection (A1) [O ROM, delays O probe]

- At startup, the FS opens **timer.device unit 1 (UNIT_VBLANK)** and **input.device unit 0**,
  prepares an **Interrupt** structure (22 bytes, public) whose `is_Data` points to a **"disk
  changed" flag** and whose code merely writes 0 into the long pointed to by `is_Data`
  (A1), then installs it by **TD_REMOVE (12)** on its trackdisk IORequest. The flag starts at 0
  ("changed") ⇒ a first mount is attempted from the first pass of the loop.
- Trackdisk side (*Corrected 2026-11-02, see trackdisk-raw-changeint-v34.md §5.1, §5.4, §6.2*): the unit has a
  **single** remove-interrupt slot (TD_REMOVE replaces any previous one; NULL clears it; replied at once). At each
  change seen by the unit's own polling, **on removal and on insertion alike**, trackdisk first increments the
  change counter (TD_CHANGENUM), then `Cause()`s the TD_REMOVE interrupt (if set), then the Interrupt of every
  TD_ADDCHANGEINT request of the unit, in installation order. The FS flag is therefore reset on insertion
  too; the FS cannot tell the two apart and relies on TD_CHANGESTATE. TD_ADDCHANGEINT requests are **never
  replied** while installed (only TD_REMCHANGEINT replies them). A swap seen within one poll gives two
  increments and two rounds of `Cause()`s.
- The timer request is re-armed with **tv_secs = 1, tv_micro = 0** (TR_ADDREQUEST): the FS wakes up
  at least once per second even without a packet (`boot-clock-v34.md` §4.3).
- At each wake-up (before processing the received packet): if the flag is 0 ⇒ flag := −1; then,
  **unless the FS is inhibited (ACTION_INHIBIT) or a validation is already in progress** [O for
  the inhibition; D for "validation in progress", internal counter not elucidated in detail],
  **TD_CHANGESTATE (14)** (io_Actual: 0 = disk present):
  - **present** ⇒ start of the validator (§2.5);
  - **absent** ⇒ ejection (§2.2.1).
- Other block devices (hard-disk drivers) [O-inj 2026-11-05, `rom-filesystem-v34.md` §1.4]: the FS reads only
  `io_Actual` of TD_CHANGESTATE and TD_PROTSTATUS and ignores `io_Error` (also for TD_REMOVE); it never sends
  TD_CHANGENUM. A driver that rejects TD_CHANGESTATE with `io_Actual` 0 is "disk present"; with a nonzero
  `io_Actual` the unit shows "No disk present". A driver that never calls the TD_REMOVE interrupt is checked
  once per mount (start, INHIBIT off), never again.
- Consequence: the FS latency = detection by trackdisk (its own polling of the /CHNG
  line: every ~0.5 s with a disk present, ~2.5 s with the drive empty, plus before/after each queued
  command — trackdisk-raw-changeint-v34.md §6.2, ROM reading; not measured here) + at most ~1 s. Measured (emulated time, from the increment of
  TD_CHANGENUM): ejection recognised in **0.1–0.3 s**. [O]

### 2.2 Volume nodes of the DosList (A2)

#### 2.2.1 Ejection [O ROM + O probe]

1. FS `DiskType` := **−1** (DISK_INFO replies, §2.3).
2. If either of two internal states of the FS is non-zero, the FS calls dos's error requester
   (**errorreq, code 3, node of the current volume**) and **does not abandon** the volume: it resumes its
   loop without detaching [O ROM for the call and the non-detachment]. Black-box probe (2026-11-09, real
   ROM under Amiberry, method in §1) [O]:
   - **Condition**: the requester appears only when the disk is removed **while an operation is doing disk
     I/O**: in the middle of `Copy C: DF1:` (writing), of `Echo >DF1:x hello` before its prompt came back,
     and of `Copy DF1:big NIL:` (**reading** a 300,000-byte file). It does **not** appear for a disk removed
     with only a **pending write-back** (`Copy C:Dir DF1:` or `Echo >DF1:e hello` finished, ejection
     0.06 s and 1.3 s after the prompt, i.e. before the 2–3 s write-back of `rom-filesystem-v34.md` §8.4),
     nor with a **file open for writing but idle** (`Copy * DF1:w` waiting for console input, ejection 2.5 s
     after its start or after > 5 s), nor after > 5 s of inactivity. The two states therefore mean "an
     operation with device I/O outstanding", not "bitmap/root not yet written back" [D].
   - **Text**: window title **"System Request"**, three lines **`You MUST replace volume`** / **volume
     name** (e.g. `Data`) / **`in unit  1 !!!`** (two spaces between "unit" and the unit number, one space
     before "!!!"; unit = `fssm_Unit` of the drive), buttons **Retry** (left) and **Cancel** (right). The
     window is 320 × 72 at (0, 0) of the Workbench screen (measured on a capture, ±1 line), the same frame as
     the "Please replace volume" requester. It appears **at the ejection**, without any further access, about
     0.5 s after the disk left the drive (wall-clock time, Amiberry at normal speed). The operation that was
     running stays blocked behind it.
   - **Reinserting the same disk** does **not** close it (still up 25 s after the reinsertion): unlike the
     "Please replace volume" requester (§2.4), it waits for a click. **Retry** with the disk back: the
     operation resumes where it stopped and completes; the file was complete afterwards (`hello`, header
     and data present) and, after the next write-back, the root's bitmap flag was valid (−1). Retry or
     Cancel **without** a disk: the requester comes back at once.
   - **Cancel** with the disk back (read case): the requester closes and the interrupted read fails
     (`Copy` prints "Error while Reading"). Cancel without a disk, read case: the read fails, then the next
     read on the same FileHandle gives the ordinary "Please replace volume / Data7 / in unit  1"
     requester (§2.4), i.e. the volume is then detached as in point 3. Cancel without a disk, write case:
     the requester comes back for each further write; `Copy` went on, printed "..copied" for a file whose
     data never reached the disk, then "Destination is a directory" and "Error while Writing"; after five
     Cancels the command ended and `Info` showed "No disk present". The disk kept the root written at the
     first modification (**bitmap flag 0**, so the next mount revalidates) and the interrupted file with a
     header of size 0.
   - **Retry with a different disk** in the drive: the FS does **not** check the disk. It carries on with
     the old volume's state and writes onto the new disk: the remaining files, the old volume's **root
     block (its name and creation date)** and its bitmap. The other disk became a corrupt copy of the old
     volume (its own name lost; entries for files written before the swap point to blocks that exist only
     on the first disk). Observed twice, the second time in a fresh session (`VolD2` → root named `VolD1`).
     This is what "You MUST replace" guards against. Inserting the other disk alone (without a click) did
     not write to it.
   - **Without the requester**, the pending write-back is **lost silently**: the FS detaches as in point 3
     (`CMD_CLEAR` drops the track that trackdisk was still holding [D]), so the image showed **nothing** of the last
     command (not even the first-modification root write, which sits on the same track), or, when the
     command had crossed tracks, the root with bitmap flag 0 and a header of size 0. On reinsertion the
     validator rebuilds the bitmap (full validation) without any requester: `List` shows the file as
     "empty"; after the next write-back the disk is valid again (flag −1, orphan data blocks freed).
     No requester at the ejection, at the next access ("No disk present" from `Info`) or at the
     reinsertion.
   - Probe caveat: a disk formatted by `xdftool` has `'DOS\0'` in the root block's last-but-three long (the
     hash-chain field, 0 on the Workbench 1.3.3 disk). The 1.3 validator follows it as a key: a full
     validation of such a disk stops at "Error validating disk / <name> / Key 1146049280 out of range". Clear
     that long (and fix the checksum) on probe disks that will be revalidated.
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
5. The same "absent" branch is taken at the **start** of the FS when the unit's first TD_CHANGESTATE answers
   a nonzero `io_Actual`, whatever `io_Error` says: no volume is mounted, Info "<unit>: No disk present", and
   a write (`Echo >DH0:z`) gave dos's "No disk present / in unit  0" requester. Observed on a hard-disk unit with the reply
   rewritten in flight (`rom-filesystem-v34.md` §1.4). [O-inj 2026-11-05]

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
  for the locks; FileHandles: see the next point]
- FileHandle open for writing on DF1, disk removed while idle, then a write/close by the program
  (`Copy * DF1:z`, a line typed, ejection, then Ctrl-\) [O probe 2026-11-09, Amiberry]: requester
  **"Please replace volume / Data3 / in unit  1"** (here the third line names the **unit**, two spaces
  before the number, no "!!!"; not "in any drive" as for the `Examine` above), Retry / Cancel, same 320 × 72
  frame at (0, 0). Reinserting the same disk closed it on its own (a few seconds, the time of the
  revalidation) and `Copy` completed: file `z` = "line one", bitmap flag valid after the write-back.
  **Exception**: when the disk was removed **before the write-back** that would have written the new file's
  header (ejection 2.5 s after `Copy * DF1:w` started), the requester also closed on reinsertion, but
  `Copy` **never returned** (still waiting for its packet reply 65 s later; the file systems and the CLI all
  waiting, no CPU activity). Reproduced in a fresh session. [O; cause not analysed]

#### 2.4.1 Open FileHandle whose disk moves to another drive (probe 2026-11-10)

Method: real ROM, headless Amiberry (`amiberry-session start --analysis`, cycle-exact A500, 512 KB chip +
512 KB slow), **three drives** (`-s nr_floppies=3 -s floppy2type=0`: without `floppy2type` the third drive
is not seen and `DF2:` is not mounted). DF0 = copy of the Workbench 1.3.3 boot disk whose startup-sequence
only runs SetPatch and leaves the boot CLI open; DF1 = blank OFS disk made with `xdftool`, volume `Data3`,
holding a 200,025-byte text file `longfile` (3,175 numbered lines); DF2 = a scratch disk ejected after boot,
so DF2 is mounted and empty. Floppies moved with IPC `EJECT_FLOPPY` / `INSERTFLOPPY`, the **same image** being
inserted in the other drive about 2 s after the ejection. Screens read on IPC screenshots; the DosList
(volume node `dl_Task`, `dl_LockList`) read through IPC memory reads; disk contents read with `xdftool`
after the run. Times are wall-clock at normal emulator speed. Four fresh sessions, a fresh copy of the data
disk each.

**Main result**: the open FileHandle **stays bound to the file system of the drive it was opened on**
(DF1, unit 1). It does **not** follow the volume to DF2, although the DF2 file system **takes over the volume
node** (see below). Every access through that FileHandle waits behind a "Please replace volume" requester
naming the **original unit**, which closes on its own only when the disk is back in **that** drive.

1. **Volume node** [O, three sessions]: while the disk is out, the `Data3` node stays in the DosList with
   `dl_Task = 0` and a non-zero `dl_LockList` (the open file keeps a lock, §2.2.1 point 3). When the disk
   is inserted in DF2, the DF2 file system's validator finds that node (same name and date) and **reuses
   it**: `dl_Task` = DF2's handler port, `dl_LockList = 0` (locks re-adopted by DF2's file system, as in
   §2.2.2). `Info` then lists "DF2: … Data3", "DF1: No disk present"; a path through the volume name
   (`List Data3:`) is served by DF2 normally. Moving the disk back to DF1 flips the node again: out of
   DF2 → `dl_Task = 0` with a lock list; in DF1 → `dl_Task` = DF1's port, `dl_LockList = 0`.
2. **Writing** (`Copy * DF1:w`, "line one" + Return, 5 s idle so that the write-back is done, ejection,
   insertion in DF2, then "line two" + Return): no requester at the ejection or at the insertion (the file
   was idle). The next write gives **"Please replace volume / Data3 / in unit  1"** (same text, spacing and
   320 × 72 "System Request" frame at (0, 0) as §2.4; unit **1**, not 2), Retry / Cancel.
   - With the disk sitting in DF2 it **does not close on its own** (still up after > 40 s). **Retry**: the
     requester disappears and reappears at once (screenshots 0.15 s apart).
   - **Disk moved back to DF1** while the requester is up: it **closes on its own** 4 to 6 s after the
     insertion (the revalidation time), without a click, and the write completes. After Ctrl-\ (the console
     window must be made active again: keys typed while the requester was up went to the requester window),
     `Copy` returned normally. File `w` = "line one\nline two\n" (18 bytes), root bitmap flag valid (−1). [O]
   - **Cancel** with the disk in DF2 (second session; the two requesters come from two calls, point 6): the requester comes back once; a second Cancel makes
     `Copy` print **"Error while Writing"**, then a **"No disk present / in unit  1"** requester (two text
     lines, Retry / Cancel) appears; Cancel on it returns to the prompt. Afterwards the disk holds the file `w` whose header says **size 0**
     but whose data table lists **one data block containing "line one\n"** (written by DF1's write-back before the
     ejection [D]); "line two" is lost. Bitmap flag valid (−1). The 1.3 `List Data3:`
     shows `w` as "empty"; `xdftool` reports a block-count mismatch for it. Which call raised the
     "No disk present" requester (the close of the FileHandle, or `Copy`'s next access) was not
     established by this run; the single-call probe (point 6) shows that `Close` does **not** raise it, so it
     is a later call of `Copy` [S: deletion of the incomplete destination].
3. **Reading** (`type DF1:longfile`, ejection about 6 s after the start, at line 52, insertion in DF2):
   the requester **"Please replace volume / Data3 / in unit  1"** appears within 2 s of the ejection (no
   "You MUST replace" requester: the ejection fell between reads, §2.2.1 point 2); output stops.
   - With the disk in DF2: the requester stays (> 25 s).
   - **Disk moved back to DF1**: the requester closes on its own 6 to 8 s after the insertion and `Type`
     **resumes exactly where it stopped** (line 52 followed by line 53, no gap, no repeat) and runs to the
     last line (03174) and the prompt. [O]
   - **Cancel** with the disk in DF2 (separate session): the output first advances to the middle of
     line 53 (3,400 bytes into the file) and the requester comes back; a second Cancel ends `Type` **without any error message**, back to the prompt. [O]
4. **Consequence for an implementation** [D]: the file system keeps owning its FileHandles (and the locks
   inside them) per drive; there is no hand-over of an open file between file system instances. A packet
   on a FileHandle whose volume is not mounted in **its** drive is refused (Res2 = 218, §2.4) even when the
   volume is mounted elsewhere, and dos turns that into the "replace volume … in unit N" requester with
   the FileHandle's own unit. The volume node, in contrast, is shared: the validator of whichever drive
   gets the disk re-adopts the node and its lock list.
5. Not probed: a **lock** (not a FileHandle) kept across the move, e.g. `Examine` on a `Lock("Data3:")`
   taken while the disk was in DF1 and used while it sits in DF2 [S: refused by DF1's file system like a
   FileHandle, giving "in any drive" as in the `Examine` case above, since the lock list was handed to
   DF2 but the lock's `fl_Task` still names DF1; not verified]; the "You MUST replace volume" case
   (ejection during a transfer) followed by insertion in another drive (now seen, point 6).
6. **Single-call probe (2026-11-10)** [O]. Question: in points 2 and 3, does the requester that "comes back
   once" belong to the same dos call (dos asking again after a Cancel) or to a new call of the program?
   Method: real ROM, same three-drive Amiberry setup as above; the project probe `tests/fhmove_probe.s`
   (assembled unchanged) run from the startup-sequence of a non-Workbench boot floppy. It makes one dos
   call at a time and prints on the serial line: one line per 2,048-byte `Read` of `DF1:longfile` (0.5 s
   `Delay` after each), then the result of the last `Read` and `IoErr()`, then `Close`; then
   `Open("DF1:w", MODE_NEWFILE)`, a first 9-byte `Write`, a 20 s `Delay`, a second 9-byte `Write`, `Close`,
   and the second `Write`'s result. To tie each requester to one call, hardware breakpoints were set
   **in the probe's own code** on the instruction following each dos call (the probe's load address was
   found by searching RAM for its strings); a hit gives the call's D0 and, read from the calling process,
   `pr_Result2` (= `IoErr()`). Requesters were answered with the keyboard (Left-Amiga + V = Retry,
   Left-Amiga + B = Cancel), every state looked at on a screenshot. Seven sessions, a fresh data disk copy
   each; disk moved DF1 → DF2 with IPC `EJECT_FLOPPY 1`, 2 s, `INSERTFLOPPY … 2`.
   - **Read** (ejection after the 3rd to 8th block, six sessions): with this probe's 0.5 s cadence the
     ejection always (6 of 6) caught an operation with device I/O outstanding, so the requester was
     **"You MUST replace volume / Data3 / in unit  1 !!!"** (§2.2.1 point 2), not "Please replace".
     **Retry** with the disk in DF2: the same requester again at once (four screenshots over 4 s), the
     `Read` does not return. **One Cancel**: the pending `Read` returns at once with **Res1 = −1**,
     **IoErr = 286** (two sessions, identical) [the meaning of 286 is not established; it is not one of the
     documented dos codes, and may be 256 + a device error code ?]. No requester came back for that call;
     the program's next call (`Close`) raised the next requester. Bytes delivered before the failing call
     were correct (count and sum checked).
   - **Close** of that read FileHandle (disk in DF2, the FS having detached the volume): **one**
     "Please replace volume / Data3 / in unit  1" requester (dos's, §2.4); one Cancel and `Close` returns
     (D0 on return held 218, which is not a defined result of `Close` in 1.3). The next requester,
     **"No disk present / in unit  1"** (two lines, Retry / Cancel), belonged to the **next call**,
     `Open("DF1:w", MODE_NEWFILE)` with DF1 empty; one Cancel and `Open` returned **0**.
   - **Write** (read left to finish, disk moved 7 s into the 20 s `Delay`, so the FS was idle at the
     ejection and had detached the volume before the call): the second `Write` raised **one** "Please
     replace volume / Data3 / in unit  1" requester. **Retry** with the disk in DF2: the requester vanished
     (one screenshot without it) and came back within 0.2 s, the call still pending. **One Cancel**: `Write`
     returns **Res1 = −1, IoErr = 218** (two sessions, identical). Then `Close`: **one** "Please replace"
     requester; one Cancel, `Close` returns (D0 and IoErr 218), and **no further requester** (no "No disk
     present"). The disk then holds `w` with a header of size 0 and one data block "line one\n", as in
     point 2.
   - **Reading of points 2 and 3**: each requester belongs to a **different call**. `Copy`: the first
     "Please replace" is its `Write`, the one that "comes back once" is its `Close` (or a further `Write`),
     and the final "No disk present / in unit  1" is a third call made after "Error while Writing" with DF1
     empty — most likely `Copy` deleting its incomplete destination [S: `Close` was shown not to raise it].
     `Type`: two calls as well (consistent with the small advance of the output between the two requesters,
     data delivered by the first, failing, call or by `Type`'s buffering) [S].
   - **Rule for an implementation** [O for the cases above, D for the generalisation]: dos shows **at most
     one** volume requester per dos call on Cancel. **Retry** re-sends the request; if the file system
     refuses it again, the same requester is shown again within the same call. **Cancel** ends the call at
     once with the failure: `Read`/`Write` Res1 = −1 with IoErr = the code the file system gave (218 for a
     packet refused because the volume is not in the FileHandle's drive; 286 after Cancel on the "You MUST
     replace" requester); `Open` returns 0; `Close` returns normally (the handle is gone for the program).
     dos never re-asks after a Cancel; any second requester comes from the program's next call.

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
- Failures found later in the validation (bitmap checksum on a disk flagged valid, a key out of range or used
  twice, a bad header in the full scan): same requester family, then "Disk structure corrupt" / "Use
  DISKDOCTOR to correct it"; the full list, Retry/Cancel effects and the ROM / `L:Disk-Validator` split are in
  `rom-filesystem-v34.md` §2.5. For a "Key n out of range" requester, **ejecting the disk did not remove it**
  (> 10 s; a Retry then showed it again with an empty volume line); only Cancel ended it. [O 2026-11-05]

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
| drive **inhibited** (DiskCopy waiting at its requester), volume **without** lock (`Data` in DF1) | **disappears**, replaced **in the same slot** by `DF1:BUSY` (§4.5) | — |
| drive inhibited, volume **with** locks (`Workbench1.3` in DF0) | **stays** (same image, same place, selection kept); `DF0:BUSY` is **added** at the next free slot | **stays open** with its icons |
| end of the inhibition (DiskCopy Cancel) | `DFn:BUSY` removed, then the volume icon comes back in its slot; settled ≈ 4 s after the click | unchanged |

Inhibition rows: [O probe, 2026-11-09, Amiberry, real ROM]; details and timings in
`workbench-task-v34.md` §10.6.

### 4.5 Non-DOS disk [O ROM + O probe]

"Device" icon (object type 7) with the **default disk object** (§4.2), label =
**device name + `:` + the 4 bytes of `id_DiskType`** copied as is, the string stopping at the
first null byte: `DF0:NDOS` (invalid root, observed), `DF0:` (null disk, type 0, observed),
`DF0:BAD` (`'BAD\0'`) [D], **`DF0:BUSY` / `DF1:BUSY` during an INHIBIT** [O probe 2026-11-09:
DiskCopy at its requester, both drives inhibited; default disk image, pixel-identical to the
`RAM DISK` image]. If the type changes, the icon is recreated with the new name. Nothing for
`'DOS\0'` nor for −1 (empty drive). Placement: §4.3. Observed: a non-DOS disk inserted after boot
lands below Workbench1.3; a **BUSY icon replacing a volume without locks takes that volume's freed
slot**, while `DF0:BUSY` next to a volume that stays lands in the next free slot below it.
**At boot**, an all-zero disk in DF1 gave a `DF1:` icon (default image) at the **top** of the
right-hand column, **above `RAM DISK`** (column: `DF1:`, `RAM DISK`, `Workbench1.3`) [O probe
2026-11-09, Amiberry]: the first Workbench scan adds it before the volumes; why it comes first is
not established [S: the non-DOS device entries are reached before the volume entries in that
scan].

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
| V14 | ACTION_DISK_INFO during INHIBIT(1) | DiskType `'BUSY'`; after INHIBIT(0): remount, DISKINSERTED [O ROM, not probed at packet level] |
| V15 | `Workbench1.3` (DF0) dragged on `Data` (DF1), DiskCopy requester up | `Data` → `DF1:BUSY` in the same slot; `Workbench1.3` stays; `DF0:BUSY` added below it; Cancel ⇒ back to the start within ≈ 4 s [O probe, `workbench-task-v34.md` §10.6] |
| V16 | All-zero disk in DF1 at boot | `DF1:` icon at the top of the column, above `RAM DISK` [O probe] |
| V17 | `Copy C: DF1:` (or `Copy DF1:big NIL:`), eject DF1 mid-transfer | ≈ 0.5 s later, without further access: "System Request" 320 × 72 at (0, 0), `You MUST replace volume` / `<name>` / `in unit  1 !!!`, Retry / Cancel; the command stays blocked [O probe, §2.2.1 point 2] |
| V18 | V17, then reinsert the same disk | requester **stays**; Retry ⇒ the command completes, file complete, bitmap valid after the write-back [O probe] |
| V19 | V17, then Retry or Cancel with the drive empty | write: requester shown again at each further write, the command eventually fails ("Error while Writing"), disk left with bitmap flag 0; read: the read fails, next access ⇒ "Please replace volume / `<name>` / in unit  1" [O probe] |
| V20 | V17, then insert another disk and Retry | the old volume's data **and root block (name, date)** are written onto the other disk [O probe]; a conforming ROM must at least never write before Retry |
| V21 | `Echo >DF1:e hello`, eject < 1.5 s after the prompt (write-back pending) | **no requester**; the write is lost (nothing or a size-0 header on the disk, bitmap flag 0 if the root went out); reinsertion ⇒ silent revalidation, `List` shows the file "empty" or absent [O probe] |
| V22 | `Copy * DF1:z` waiting for input, eject after > 5 s, then Ctrl-\ | "Please replace volume / `<name>` / in unit  1"; reinsertion ⇒ closed on its own, file written [O probe, §2.4] |

---

## 6. Open points

- Detection delay **by trackdisk** itself (polling of /CHNG, motor stopped): not measured
  (FS-UAE menu paused); only the FS delay (≤ ~1 s after the TD_REMOVE interrupt) is established. The poll
  period is now known from the ROM (~0.5 s disk present, ~2.5 s empty: trackdisk-raw-changeint-v34.md §6.2,
  added 2026-11-02); the measurement remains open.
- Text, timing and button effects of the §2.2.1 point 2 requester: settled by probe (2026-11-09). Still
  open: which exact operations set the two internal states (a short operation with no I/O in flight, e.g.
  an `Info`, was not tried), and whether the requester comes from the ejection branch or from a failed
  device request inside the operation (indistinguishable from outside). Split "replace" / "insert" and
  "in any drive" / "in unit  n" between dos and the FS (§2.4). The `Copy` hang of §2.4 (header never
  written back) is not explained.
- §2.4.1 point 6: IoErr **286** after Cancel on "You MUST replace" is unexplained (not a documented dos
  code). A `Read` reaching the dos "Please replace" requester (volume already detached when the call
  starts) was not produced: the probe's 0.5 s cadence always caught I/O in flight. Probe wanted: open a
  file, `Delay` 20 s (disk moved meanwhile), then one `Read`, printing Res1 and IoErr per Cancel/Retry
  [expected as for `Write`: one requester, Res1 −1, IoErr 218].
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
- [x] 2026-11-05 additions (§2.1 other block devices, §2.2.1 point 5, §2.5 later failures): device replies
  rewritten in flight with the debugger and requesters read on screen; no breakpoint address given.
- [x] 2026-11-09 additions (§1 last point, §2.2.1 point 2, §2.4 FileHandles, V17–V22): pure black box
  (IPC eject/insert, screenshots, exec task list, disk images read with `xdftool`); no ROM code read, no
  address.
