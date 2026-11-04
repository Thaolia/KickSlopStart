# rom-filesystem-v34.md — The ROM file system (OFS handler of DF0:–DF3:) seen through its packets (KS 1.3)

> **ANALYSIS track ("dirty").** Behavioural spec of the file system process that serves the floppy units in
> Kickstart 1.3 (`kick34005.A500`, dos 34.3, segarray entry 6, process name "File System"). It describes what a
> client sees: packet arguments, `dp_Res1`/`dp_Res2`, ordering of observable effects, and the handler's
> choices on the disk (placement, write-back). The on-disk OFS format is public (AmigaDOS Technical Reference)
> and is not described again. No instruction sequence is reproduced or paraphrased, no ROM address or ROM
> offset is given.
>
> **Legend.** **[O]** observed running the real ROM (Amiberry, cycle-exact A500, Workbench 1.3.3 commands, a
> packet tracer on the file system's reply path, and the resulting ADF images). **[O-inj]** observed after
> changing a packet in flight with the debugger (type or arguments rewritten just before the file system
> dispatches it; §0.2). **[D]** deduced from reading the ROM (static) or from converging observations, not run.
> **[?]** not established. "Res2 noise" = the value is whatever was left in the register/slot, not an error code.
>
> **Related pages (not repeated here).** `dos-v34-spec.md` §2 (packet life cycle, read-path argument table),
> `handlers-v34.md` §1.2–§1.3 (DosList node, FileSysStartupMsg, environment table, start-up of the process),
> `disk-change-v34.md` §2 (disk change, ACTION_DISK_INFO fields, ACTION_INHIBIT, packets on an absent volume),
> `disk-full-write-v34.md` (ACTION_WRITE when the disk fills), `boot-clock-v34.md` §5 (dates written, root block
> flag), `dos-memory-v34.md` §2.1–§2.2 and §6 (memory taken per lock, per open file, per buffer),
> `trackdisk-write-v34.md` (trackdisk's own track write-back, which sits under this page's §8).

---

## 0. Summary and method

### 0.1 Summary

1. The file system answers **31 packet types**. Everything else gets **Res1 = 0, Res2 = 209**
   (ERROR_ACTION_NOT_KNOWN), including ACTION_DISK_CHANGE (33), ACTION_WAIT_CHAR (20), ACTION_DIE (5) and
   ACTION_NIL (0). **ACTION_SET_DATE (34) is supported in 1.3** (C:SetDate uses it). [O]/[D] §1
2. Locks: any number of shared locks, or exactly one exclusive lock, per object. FINDINPUT takes a shared
   lock; **FINDOUTPUT and FINDUPDATE take an exclusive lock**; DELETE, SET_PROTECT, SET_COMMENT and SET_DATE
   also need exclusive access. A conflict gives **202**. Lock 0 means the root of the current
   volume. [O]/[D] §3
3. ExNext walks the directory in **hash-slot order (0..71), and inside a slot in chain order**; it keeps no
   state of its own: the next entry is derived from `fib_DiskKey` and the hash of `fib_FileName`. End of
   directory = **Res1 0, Res2 232**. [O] §4
4. SEEK: mode < 0 = from the start, 0 = from the current position, > 0 = from the end; result = old
   position; a target outside `0..size` gives **−1 / 219** and leaves the position unchanged; END keeps the
   highest size written even after a backward seek. [O-inj] §5.4
5. **FINDOUTPUT on an existing name deletes the object and creates a new file** (new header block). It honours
   the delete-protection bit (222) and **replaces an empty directory by a file**; a non-empty directory gives
   216. [O] §5.1
6. FINDUPDATE in 1.3 = open an **existing** file only (205 if missing), exclusive lock (202 while any other
   lock exists); it never creates. [O-inj] §5.1
7. **CREATE_DIR on an existing name also deletes first**: an existing file or empty directory is replaced by a
   new directory, a non-empty directory gives 216. C:MakeDir hides this by checking the name first. [O-inj] §6.3
8. Only the delete bit of the protection long is enforced (by DELETE and by FINDOUTPUT over an existing file).
   **Read, write and execute bits are not checked by the file system.** [O] §6.6
9. RENAME refuses an existing target name (203) except when it is the same object (case-only rename works);
   it **does not refuse moving a directory deeper into its own subtree** (the directory becomes unreachable);
   only a move directly into itself gives 202. [O]/[D] §6.2
10. Placement on an empty disk: headers (and extension blocks) are taken going **up** from the root; the first
    data block of a file sits just after its header; later data blocks fill whole tracks going **down** from
    the root track. **The bitmap block moves on every flush** (written to a newly allocated block, the old one
    freed). [O] §8
11. The file system writes back ~**2–3 s after its last disk access** (1 s timer, counter of 3): bitmap and root
    (valid flag), then CMD_UPDATE and motor off. ACTION_FLUSH waits for that point. [O]/[D] §8.4
12. ACTION_MORE_CACHE(n) adds n buffers of 540 bytes for good (never removed; n ≤ 0 adds none) and returns
    **−1 (DOSTRUE)**, 0 if an allocation failed — not the buffer count. [O]/[D] §7.3

### 0.2 Method

- Boot disk: copy of `wb133.adf` whose `s/startup-sequence` was replaced by a list of C: commands (Copy, Join,
  Echo with redirection, Delete, Rename, MakeDir, Protect, FileNote, SetDate, Relabel, AddBuffers, Info, List,
  Type, CD) with `Why` after each, all output redirected to `SER:` (serial log). DF1:–DF3: were blank OFS
  images. Later commands were typed into the Initial CLI through the emulator's keyboard input.
- Packet tracer: a debugger breakpoint on the BCPL `returnpkt` routine (global 49), filtered on the file system
  process of the unit under test, printing `dp_Type`, `dp_Arg1..4`, `Res1`, `Res2` for every reply. Replies sent
  without `returnpkt` (ACTION_FLUSH, §7.4) are not seen this way.
- In-flight rewriting ([O-inj]): a breakpoint at the point where the file system has dequeued a packet and is
  about to look at `dp_Type`; the debugger rewrote `dp_Type` and/or arguments of a packet sent by a C: command
  (e.g. the first ACTION_READ of `Type` turned into an ACTION_SEEK). This gives packets that no 1.3 command
  sends, without a probe program.
- Disk images: the session's ADF was copied every 0.2 s while commands ran, and successive copies were compared
  block by block (header/data/extension/root/bitmap fields decoded per the public OFS format).
- Static reading of the file system segments (radare2) to confirm the action set and the error codes; facts
  that come only from it are tagged [D].

---

## 1. Supported packet set

The file system dequeues a packet and dispatches on `dp_Type`. Before dispatching it checks the disk-change
flag (`disk-change-v34.md` §2.1). [D]

### 1.1 Client packets

| ACTION_ (value) | Arg1 | Arg2 | Arg3 | Arg4 | Res1 on success | Errors (Res1 0 or −1, Res2) | § |
|---|---|---|---|---|---|---|---|
| CURRENT_VOLUME (7) | 0, or `fh_Arg1` of an open file | — | — | — | BPTR of the volume node (current volume for Arg1 = 0, the file's volume otherwise); **Res2 = unit number** | — | 7.2 |
| LOCATE_OBJECT (8) | lock (0 = root) | BSTR name | mode (−1 exclusive, anything else shared) | — | BPTR of a new FileLock | 0 / 202, 205, 210, 211, 212, 218, 225, 226 | 3 |
| RENAME_DISK (9) | BSTR new volume name | — | — | — | −1 | 0 / 210, 213, 214 | 6.5 |
| FREE_LOCK (15) | lock (0 allowed) | — | — | — | −1 | 0 / 211 | 3.4 |
| DELETE_OBJECT (16) | lock | BSTR name | — | — | −1 | 0 / 202, 205, 212, 213, 214, 216, 222 | 6.1 |
| RENAME_OBJECT (17) | lock (from) | BSTR name (from) | lock (to) | BSTR name (to) | −1 | 0 / 202, 203, 205, 213, 214 | 6.2 |
| MORE_CACHE (18) | number of buffers to add | — | — | — | −1 | 0 if a buffer allocation failed | 7.3 |
| COPY_DIR (19) (DupLock) | lock (0 allowed) | — | — | — | BPTR of a new shared lock | 0 / 202, 211 | 3.4 |
| SET_PROTECT (21) | unused | lock | BSTR name | protection long | −1 | 0 / 202, 205, 212, 213, 214 | 6.4 |
| CREATE_DIR (22) | lock | BSTR name | — | — | **BPTR of a lock on the new directory** (an existing file or empty directory of that name is deleted first) | 0 / 202?, 205, 213, 214, 216, 221, 222? | 6.3 |
| EXAMINE_OBJECT (23) | lock (0 = root) | BPTR FileInfoBlock | — | — | −1, Res2 0 | 0 / 211, 218, 225, 226 | 4 |
| EXAMINE_NEXT (24) | lock of the directory | BPTR FileInfoBlock | — | — | −1, Res2 0 | 0 / **232** at the end; 211, 218 | 4 |
| DISK_INFO (25) | BPTR InfoData | — | — | — | −1 | never fails | 7.1 |
| INFO (26) | lock | BPTR InfoData | — | — | −1 | 0 / 211, 218, 225, 226 | 7.1 |
| FLUSH (27) | — | — | — | — | the packet comes back **unchanged** (Res1/Res2 not written) | — | 7.4 |
| SET_COMMENT (28) | unused | lock | BSTR name | BSTR comment | −1 | 0 / 202, 205, 212, 213, 214, 220 | 6.4 |
| PARENT (29) | lock | — | — | — | BPTR of a new shared lock on the parent; **0 with Res2 0 for the root** | 0 / 202, 211, 218 | 3.5 |
| INHIBIT (31) | flag | — | — | — | −1 | — | `disk-change-v34.md` §2.3 |
| SET_DATE (34) | unused | lock | BSTR name | **APTR** (machine address) of a DateStamp | −1 | 0 / 202, 205, 212, 213, 214 | 6.4 |
| READ ('R' 82) | `fh_Arg1` | APTR buffer | length | — | bytes read, **0 at EOF** | −1 / 218 | 5.2 |
| WRITE ('W' 87) | `fh_Arg1` | APTR buffer | length | — | bytes written; **0 for length ≤ 0** | −1 / 213, 214, 218, 221 | 5.3 |
| FINDUPDATE (1004) | BPTR FileHandle | lock | BSTR name | — | −1 (`fh_Arg1` filled) | 0 / 202, 205, 212, … | 5.1 |
| FINDINPUT (1005) | BPTR FileHandle | lock | BSTR name | — | −1 | 0 / 202, 205, 212, 218, 225, 226 | 5.1 |
| FINDOUTPUT (1006) | BPTR FileHandle | lock | BSTR name | — | −1 | 0 / 202, 212, 213, 214, 216, 221, 222 | 5.1 |
| END (1007) | `fh_Arg1` | — | — | — | −1 | see §5.5 | 5.5 |
| SEEK (1008) | `fh_Arg1` | offset | mode | — | old position | −1 / 219, 218 | 5.4 |

Notes:
- The C: commands of Workbench 1.3.3 send Arg1 = −1 (SetProtect, SetComment) or an unrelated value
  (SetDate) in the unused first argument; the file system ignores it. [O]
- `Res2` after a success is **not** cleared by most actions (the tracer saw values such as 205, 212, 65535 left
  over from earlier work). Only EXAMINE_OBJECT and EXAMINE_NEXT reported Res2 = 0. A client must look at Res2
  only when Res1 says failure. [O]
- A "?" in the error column marks codes found in the code path but not produced in a run.

### 1.2 Internal packet types (answered, but not for clients)

These are used between the file system, its validator process and timer.device. They are listed so that a
reimplementation does not answer them with 209 where the ROM does not, and so that nobody sends them. [D]

| Value | Public name | Role in 1.3 |
|---|---|---|
| 2 | ACTION_GET_BLOCK | block service used by the validator (runs a request in a work area of the file system) |
| 4 | ACTION_SET_MAP | the validator hands over the loaded/rebuilt bitmap; this is the "stage 2" of `disk-change-v34.md` §2.5 (DISKINSERTED follows) |
| 6 | ACTION_EVENT | validator notification (end of validation) |
| 30 | ACTION_TIMER | the 1 s timer request coming back; drives the flush countdown (§8.4) and the disk-change check |
| 32 | ACTION_DISK_TYPE | the validator's reply about the disk type and volume node (stage 1 of `disk-change-v34.md` §2.5); the file system reads TD_PROTSTATUS here |

The reply of a trackdisk I/O request also arrives on the process port and is routed to the work area that
issued it. [D]

### 1.3 Refused types

Any other value, in particular 0 (NIL), 5 (DIE), 20 (WAIT_CHAR), 33 (DISK_CHANGE), 35 and above, gives
**Res1 = 0, Res2 = 209** immediately. [D]; types 33 and 99 checked: 0 / 209. [O-inj]

---

## 2. Rules common to all packets

### 2.1 Lock and volume checks [D, codes O where noted]

- Lock argument 0: accepted when the drive holds a DOS volume (means the root). Without a disk → 226
  (ERROR_NO_DISK); with a non-DOS disk → 225 (ERROR_NOT_A_DOS_DISK) [225 O, §2.3].
- Lock ≠ 0: it must be in the file system's list of locks for the current volume. If it is not there and its
  `fl_Volume` is a volume node, the answer is **218** (ERROR_DEVICE_NOT_MOUNTED; the case of
  `disk-change-v34.md` §2.4); otherwise **211** (ERROR_INVALID_LOCK).
- A FileHandle (`fh_Arg1`) whose volume is not the current volume: READ/WRITE/SEEK → −1 / 218 (§5.5 for END).

### 2.2 Names [O / D]

- A name may carry a device or volume prefix: everything up to the last `:` is skipped by the file system (dos
  has already used it to pick the handler). After the prefix the path is relative to the lock; a leading `/`
  goes to the parent, each component is looked up with the case-insensitive OFS hash. [D]
- **A component longer than 30 characters is truncated to 30 when an object is created** (Echo to a 36-character
  name created a file whose name is the first 30 characters, no error). [O]
- A path that goes through a file (`f/x`) gives **212** (ERROR_OBJECT_WRONG_TYPE), for FINDINPUT and FINDOUTPUT
  alike. [O]
- An empty name after the prefix designates the lock itself (the root for lock 0). [D] DELETE of `df2:` gave
  **205**. [O]
- A new volume name (RENAME_DISK) must be 1..30 characters with no character below `$20` (after masking
  bit 7), no `/` and no `:`; otherwise 210. [D]

### 2.3 Precondition of every modification [D for the order; 213, 214 and the order O]

Before changing the disk (create, delete, rename, protect, comment, date, relabel, write) the file system checks,
in this order:
1. no bitmap loaded (validation in progress, or failed) → **213** (ERROR_DISK_NOT_VALIDATED);
2. the disk is write-protected → **214** (ERROR_DISK_WRITE_PROTECTED).

The write-protect state is the one read with TD_PROTSTATUS when the disk was mounted (`disk-change-v34.md`
§2.5); it is not re-read per operation. [D]

Observed on a write-protected floppy (Info: "Read Only") [O]: FINDOUTPUT, DELETE_OBJECT, CREATE_DIR (new name),
RENAME_OBJECT, SET_PROTECT, SET_DATE and RENAME_DISK all answered **Res1 0, Res2 214**; reading worked. The
check comes before the existence of the name is looked at (CREATE_DIR of a new name and DELETE of an existing
file both gave 214). After a 214, **dos** (not the file system) sent ACTION_CURRENT_VOLUME (Arg1 0) to the file
system to get the volume node, then showed the requester "Volume / WProt / is write protected" (Retry / Cancel)
for Open (FINDOUTPUT), DeleteFile, CreateDir, Rename and Relabel; Cancel returned the failure to the command
("Can't open df3:x", "Not Deleted - disk write-protected", "Can't create directory", "Can't rename …",
"Attempt to rename disk failed"). C:Protect and C:SetDate failed without a requester ("Protect failed",
"SetDate failed"). This is dos's error requester (`bcpl-runtime-v34.md`, global 114); the file system itself
never opens a requester for 214.

Observed 213 [O] (details and command outputs in `dos-lvo-partial-v34.md` §1.4): a volume whose root bitmap
flag is not −1 is validated at mount by `L:Disk-Validator`. When that succeeds (writable disk: the flag is
rewritten to −1; read-only disk: bitmap built in memory) no 213 is ever seen, and a read-only disk answers
writes with 214. When there is no bitmap (validator missing from the boot disk, or validation failed), writes
answer **0 / 213** — on a read-only image too, which confirms the order above — while reads, Lock, Examine and
DISK_INFO work (Info: status "Validating"). dos shows "Volume / <name> / is not validated" (Retry / Cancel) for
FINDOUTPUT, DELETE_OBJECT, CREATE_DIR, RENAME_OBJECT and RENAME_DISK, and nothing for SET_PROTECT, as for 214.
A non-DOS disk (all-zero image) answers 225 to every request tried, FINDINPUT and LOCATE_OBJECT included,
while C:Info got its answer with no requester ("DF1:  Not a DOS disk", presumably through DISK_INFO); dos's
requester then reads "Not a DOS disk / in unit  1". [O]

### 2.4 Concurrency [D]

Each LOCATE, EXAMINE, EXAMINE_NEXT, PARENT, DELETE, RENAME, CREATE_DIR, SET_*, RENAME_DISK and FIND* packet is
served in its own BCPL coroutine with a private stack; an open file keeps its coroutine until END. While one
request waits for the disk, the process takes the next packet. Replies can therefore come back in a different
order from the requests. The stack sizes (in longs: LOCATE 110, EXAMINE 80, EXAMINE_NEXT 100, PARENT 80,
DELETE 110, RENAME 160, CREATE_DIR 150, SET_* 100, RENAME_DISK 100, FIND* 150; a block = 4 × longs + 8) are
the transient blocks of `dos-memory-v34.md` §2.2: 448 for a LOCATE, 408 for an EXAMINE_NEXT, 608 kept for an
open file. FREE_LOCK, COPY_DIR,
INFO, DISK_INFO, CURRENT_VOLUME, MORE_CACHE and FLUSH are answered at once by the main loop.

---

## 3. Locks

### 3.1 Conflict rule [O for the cases marked, D for the rule]

For an object (identified by its header block key) the file system allows either any number of shared locks or
one exclusive lock:
- a new **exclusive** request fails with **202** if any lock exists on the object;
- a new **shared** request fails with **202** if an exclusive lock exists;
- any mode value other than −1 is shared (the value is stored as given in `fl_Access`).

Who asks for what:

| Operation | Access requested on the object |
|---|---|
| LOCATE_OBJECT | Arg3 |
| FINDINPUT | shared |
| FINDOUTPUT, FINDUPDATE | **exclusive** (kept while the file is open) |
| DELETE_OBJECT, SET_PROTECT, SET_COMMENT, SET_DATE | exclusive, released before the reply |
| COPY_DIR, PARENT | shared (new lock) |

Observed conflicts (all Res1 0, Res2 202) [O, last two O-inj]:
- `Type >x x` — x opened for output by the CLI redirection, then FINDINPUT of x.
- `List >x x` — LOCATE (shared) of x while it is open for output.
- `Delete >x x` — DELETE of x while it is open for output.
- `CD e` then `Delete e` — DELETE of a directory on which the CLI holds a shared lock (Delete prints
  "Not Deleted - object in use").
- `CD df2:e` with its LOCATE rewritten to exclusive (−1): granted; then `List df2:e` (shared LOCATE) → 202.
- FINDUPDATE of a file on which shared locks were held → 202.
- An exclusive LOCATE of a file with no other lock was granted, and List went on normally.

### 3.2 The lock returned [O by use; D]

- 20-byte FileLock (in a 24-byte getvec block, `dos-memory-v34.md` §2.2): `fl_Link` (next lock of this file
  system), `fl_Key` = header block key of the object (root key for the root), `fl_Access` = requested mode,
  `fl_Task` = the file system's port, `fl_Volume` = BPTR of the current volume node.
- New locks are put at the head of the file system's lock list; the head of that list is the `InUse` field of
  ACTION_DISK_INFO (`disk-change-v34.md` §2.3).

### 3.3 Locks on the root

LOCATE of `df2:` (empty name) returns a lock [O] on the root (`fl_Key` = 880 on a DD floppy) [D]. An exclusive
lock on the root is possible and blocks every other lock on it, including the shared locks taken by
`EXAMINE` callers that first lock the root. [D]

### 3.4 FREE_LOCK and COPY_DIR [D, cases marked O]

- FREE_LOCK(0) → −1, Res2 0 (UnLock(0) is harmless). [O-inj]
- FREE_LOCK of a lock not found in the current list: the file system also looks in the lock list of the lock's
  own volume (`dl_LockList`, the case of a lock kept across an ejection); found → unlinked and freed; when that
  list becomes empty and the volume is not in the drive, **the volume node is removed and freed**. Not found
  anywhere → 0 / 211. (This answers the open point "last lock of an absent volume" of `disk-change-v34.md` §6;
  [D], not run.)
- COPY_DIR(0) → a **new lock** (on the root), not 0. [O-inj; "on the root" D]
- COPY_DIR of a lock on an absent volume → a new lock linked into that volume's `dl_LockList`. [D]
- COPY_DIR of an **exclusive** lock fails with 202 (the copy is shared and conflicts). [D]
- The duplicate of a lock is always shared, whatever the access of the original. [D]

### 3.5 PARENT

- Of the root (or lock 0): **Res1 0, Res2 0** — not an error code. `CD /` at the root printed "Can't find /". [O]
- Otherwise a new shared lock on the parent directory, read from the object's header (parent field). [D]

---

## 4. EXAMINE_OBJECT and EXAMINE_NEXT

### 4.1 FileInfoBlock fields filled [D, consistent with List/Dir output O]

Both actions fill the FIB from the object's header block (offsets in the FIB, V34 layout):

| FIB field | Value |
|---|---|
| `fib_DiskKey` (+$00) | header block key of the object |
| `fib_DirEntryType` (+$04) | **2 for any directory, including the root**; **−3 for a file**. Built from the header: a header of type T_SHORT with a positive secondary type gives 2, otherwise −3. The root's own secondary type (1) is not passed through. A block that is not a T_SHORT header gives its block type (corrupt disk case). |
| `fib_FileName` (+$08) | the name as a **BCPL string** (length byte first), copied as 32 bytes from the header |
| `fib_Protection` (+$74) | the header's protection long, unchanged |
| `fib_EntryType` (+$78) | same value as `fib_DirEntryType` |
| `fib_Size` (+$7C) | the header's byte size (0 for a directory) |
| `fib_NumBlocks` (+$80) | **number of data blocks only**: the sum of the block counts of the header and of each extension block, each capped at 72; header and extension blocks are not counted. 0 for a directory. |
| `fib_Date` (+$84) | the header's date (3 longs) |
| `fib_Comment` (+$90) | the header's comment as a **BCPL string**; 84 bytes are copied, so 4 bytes of `fib_Reserved` receive whatever follows the comment field in the header |

- Examine of the root fills the volume name and the root's (last-change) date. [D]
- EXAMINE_OBJECT result: Res1 −1, **Res2 0**. [O]

### 4.2 Order of EXAMINE_NEXT [O]

- Entries come out in **hash-slot order** (slot 0..71 of the directory's table), and inside a slot in **chain
  order** (the order of the `hash_chain` links on the disk).
- Observed on a fresh directory where six 2-letter files were created in the order mm, aa, eu, zz, fh, qa (OFS
  slots 48, 24, 24, 14, 24, 16): List printed **zz, qa, aa, eu, fh, mm** — i.e. inside slot 24 the creation
  order (see §6.3 for where a new entry is put in the chain).
- In the root of a test disk, single-letter names came out in alphabetical order (their slots increase with
  the letter), the 30-character name last. [O]

### 4.3 How EXAMINE_NEXT finds the next entry [D]

The file system keeps **no per-scan state**. Given the FIB:
1. if `fib_DiskKey` equals the key of the lock's directory (the FIB was just filled by EXAMINE_OBJECT of that
   directory), the next entry is the first non-empty slot of the directory's hash table, from slot 0;
2. otherwise it reads block `fib_DiskKey` (the previous entry) and follows its `hash_chain` link; if the link is
   0, it computes the hash of **`fib_FileName`** (not of the name in the block) and continues with the first
   non-empty slot after that one;
3. no next entry → **Res1 0, Res2 232** (ERROR_NO_MORE_ENTRIES). [O]

Consequences of changing the directory during a scan (not run; follow from the rule above):
- entries added in a slot already passed are not returned; entries added later in the current chain or in a
  later slot are returned;
- if the previous entry was **deleted**, its old block is read anyway: its stale `hash_chain` link is followed
  (still valid unless the block was reused); if the block was reused for something else the scan may jump to an
  unrelated chain or return a non-entry. No check that the block still belongs to the directory;
- if the previous entry was **renamed** into another slot, the scan continues from the slot of the *old* name
  (taken from the FIB), so entries may be skipped or repeated;
- the caller must not modify `fib_DiskKey` or `fib_FileName` between calls.

### 4.4 Errors

Lock checks of §2.1 (211, 218, 225, 226). A FIB whose key is 0 gives 232. [D]

---

## 5. Files

### 5.1 FINDINPUT, FINDOUTPUT, FINDUPDATE [O / D]

Common:
- Arg1 = BPTR of the caller's FileHandle; on success the file system writes `fh_Arg1` (an internal handle: the
  file's work area) and answers −1. dos then sends READ/WRITE/SEEK/END with Arg1 = `fh_Arg1`.
- The object must be a file: a directory gives **212** for FINDINPUT [O] (and FINDUPDATE [D]); FINDOUTPUT
  instead deletes an empty directory (below).
- A lock is taken on the file and kept until END (§3.1).
- The work area (608-byte block, `dos-memory-v34.md` §2.2) and the lock are freed at END.

FINDINPUT (MODE_OLDFILE): locate with a shared lock; missing → 205. **Writing through such a handle is
accepted**: a READ of `Type` rewritten into a WRITE of 200 bytes answered 200 and the 37-byte file became
200 bytes long. [O-inj]

FINDUPDATE (MODE_READWRITE): **same as FINDINPUT but with an exclusive lock**; a missing file gives **205** —
1.3 does not create it (2.0 does); an existing file on which a shared lock is held gives **202**. [O-inj]

FINDOUTPUT (MODE_NEWFILE):
1. if the name exists, the object is **deleted first**, with the rules of DELETE_OBJECT (§6.1): delete-protected
   → **222** [O]; locked/open → **202** [D]; a non-empty directory → **216** [O]; **an empty directory is
   deleted and replaced by a file of the same name** [O] (Join to `df2:empty`, an empty directory, left a 2-byte
   file `empty`).
2. a new header is allocated (§8) — the file gets a **new header key**; its old blocks return to the free pool
   and may be reused at once (the new header of `small` took the block freed by the old bitmap, and its first
   data block took the old header's block). [O]
3. the new header is written at once with size 0 and the current date; the parent directory's hash chain and
   date are updated (`boot-clock-v34.md` §5). [O]
4. protection of a new file = 0 (all of rwed allowed, archive clear). [O]

### 5.2 READ [O / D]

- Res1 = number of bytes copied; **0 at end of file**; a READ that spans the end returns the bytes up to the end.
  [O] (Join reads in chunks of 400 bytes, Type of 200: a 2-byte file gives 2, then 0.)
- A READ with a zero or negative length: not established (WRITE checks the length first, READ has no such
  early test) [?].
- Errors: −1 / 218 for a file on an absent volume. A data block whose header back-pointer or sequence number does
  not match gives an error [D, code not established].

### 5.3 WRITE [O / D]

- Length ≤ 0 → **Res1 0** (nothing written, Res2 not set). [D]
- Before writing: §2.3 (213, then 214) → Res1 −1. [D]
- Writes at the current position, overwriting existing data and extending the file; the size grows when the
  position passes the end. [D]
- Disk full: `disk-full-write-v34.md` (−1 / 221, position unchanged, blocks allocated meanwhile kept). [O there]
- Res2 after a successful WRITE is 65535 (noise). [O]
- The header (size, block list, date) is updated at END, and also when a new extension block is chained during
  the write (the header of a 37,728-byte file was written with 72 data pointers and size 0 when its first
  extension block was created, then with the real size at END). [O]

### 5.4 SEEK [D for the rule; every case below O-inj]

- Arg2 = offset, Arg3 = mode. **Any negative mode means OFFSET_BEGINNING, 0 OFFSET_CURRENT, any positive
  value OFFSET_END.**
- Target = offset (beginning), current position + offset (current), file size + offset (end).
- **Target < 0 or target > size → Res1 −1, Res2 219** (ERROR_SEEK_ERROR); the position does not change.
- Target = size (end of file) is allowed.
- Success → **Res1 = the old position**; the next READ/WRITE starts at the target (after reading 200 bytes,
  SEEK(10, −1) → 200, and the next READ of 200 returned 190). [O-inj]
- The size used is the file's current size **including what has been written through this handle** — a file
  open for output can be repositioned inside what has already been written, not beyond it.
- If, while walking to the target, a data block turns out inconsistent (wrong header back-pointer or sequence
  number), the answer is also −1 / 219. [D]

Runs on a 37-byte file (the first READ of `Type` rewritten into a SEEK; position 0) [O-inj]:

| Offset, mode | Res1 / Res2 |
|---|---|
| 10, −1 | 0 / 0 |
| −5, 1 | 0 / 0 |
| 37, −1 (= size) | 0 / 0 |
| 0, 5 (positive mode ≠ 1) | 0 / 0 |
| 100, −1 | −1 / 219 |
| −1, −1 | −1 / 219 |

On a file being written (`Join b b as w2`, the second WRITE rewritten): after 37 bytes written, SEEK(−10, 0) →
**Res1 37** (old position), Res2 0; the file closed with size **37**, not 27: END records the highest position
written, not the position at close. On a new empty output file, SEEK(10, −1) → −1 / 219. [O-inj]

### 5.5 END [O / D]

- Res1 −1. [O]
- If the file was written, the header is rewritten with the new size, block count and the **current date**
  (the date of the close, not of the creation: the header of `ed` carried the creation time in its first write
  and the close time after END) [O]; the archive bit is cleared (`boot-clock-v34.md` §5).
- The size recorded is the **highest position reached by the writes**, not the position at close (§5.4: 37
  written, SEEK back to 27, END → size 37). [O-inj; consistent with `disk-full-write-v34.md` §3.2]
- The lock and the 608-byte work area are freed. [O in `dos-memory-v34.md`]
- File on an absent volume: the static reading gives Res1 **0** with Res2 218 for END, whereas
  `disk-change-v34.md` §2.4 states −1 [?]. Not run here; see §12.

---

## 6. Modifying the directory tree

### 6.1 DELETE_OBJECT [O]

| Case | Result |
|---|---|
| file or empty directory, no lock on it | −1; header and data blocks returned to the bitmap; parent entry unlinked; parent date updated |
| name not found | 0 / **205** |
| object locked or open (by anyone, including the caller's current directory) | 0 / **202** |
| directory not empty | 0 / **216** ("Not Deleted - directory not empty") |
| delete bit set in the protection long (Protect without `d`) | 0 / **222** ("file is protected from deletion") |
| the root (`df2:`) | 0 / **205** |
| path through a file | 0 / 212 [D] |
| not validated / write-protected | 0 / 213 / 214 [D] |

### 6.2 RENAME_OBJECT [O]

- Arg1/Arg2 = lock + name of the object, Arg3/Arg4 = lock + new name; the new name may be in another
  directory. Moving a file into a subdirectory (`Rename a d/a2`) works; both parent directories get their date
  updated (`boot-clock-v34.md` §5).
- New name already used by **another** object → 0 / **203** (file onto file, file onto directory). [O]
- New name = same object with different case (`h` → `H`) → −1, the entry is renamed. [O]
- **Moving a directory into its own subtree is accepted**: `Rename p p/q/r` answered −1. On the disk image the
  old `p` header now carries the name `r` and its parent field points to `q`, while `q`'s parent still points
  to it: a two-directory cycle no longer reachable from the root (List of the root no longer shows `p`; the
  blocks stay allocated). A compatible implementation may refuse this (2.0 does); a program that relies on it
  is unlikely. [O]
- Moving a directory **directly** into itself (`Rename p p/x`: the target directory is the object) → 0 / **202**;
  only this one-level case is checked. [D]
- Source missing → 205; target directory missing → 205 [D]. Whether an open or locked source is refused is
  not established [?].
- RENAME_OBJECT does **not** check the delete bit. [D]

### 6.3 CREATE_DIR [O / D]

- Success → **Res1 = BPTR of a lock on the new directory** (the C: MakeDir command then frees it). [O] The
  directory gets protection 0 and the current date; the parent's date is updated. [O]
- MakeDir checks for an existing name itself with LOCATE before sending CREATE_DIR ("df2:d already exists");
  the file system then never sees the duplicate. [O]
- **CREATE_DIR on an existing name goes through the same delete-then-create as FINDOUTPUT** [O-inj]:
  - existing **file** `ord/mm` → Res1 = new lock; the file is gone and `mm` is now an empty directory (it even
    reused the file's header key);
  - existing **empty directory** `ed1` → Res1 = new lock; `ed1` is a new empty directory (new date);
  - existing **non-empty directory** `ord` → 0 / **216**;
  - by the same path a delete-protected or locked object would give 222 / 202 [D].
  A compatible file system may answer 203 instead (2.0 does); only programs that bypass MakeDir's check see the
  difference.
- A new entry is **appended at the end of its hash chain**, whatever its block key: after deleting `eu` (key
  903) from the chain aa(901) → eu(903) → fh(907) and creating `lb` in the same slot, `lb` got key 906 and the
  chain became aa → fh → lb (List: aa, fh, lb). [O]
- No space for the header → 221. [D]

### 6.4 SET_PROTECT, SET_COMMENT, SET_DATE [O]

- Arg2 = lock, Arg3 = name, Arg4 = value. The object is located with exclusive access (202 if in use) [D], its
  header is updated and written, the lock is released, Res1 −1. [O]
- SET_PROTECT: the whole protection long is replaced by Arg4. [O] (`Protect f rwe` sent 1 = only the delete
  bit set.)
- SET_COMMENT: Arg4 = BSTR; a comment longer than **80** characters gives 220 [D]. The C: FileNote command of
  1.3.3 refused a 90-character comment by itself ("Note failed", Why → "packet request type unknown" = 209)
  **without sending any packet**. [O]
- SET_DATE: **supported in 1.3**. Arg4 is a machine address (APTR) of a DateStamp (3 longs). `SetDate f
  01-Jan-80 12:34:56` → List shows `01-Jan-80 12:34:56`. [O]
- Applied to the root (empty name) → 0 / **212**. [D]
- None of the three changes the parent's date or the archive bit beyond what they write (SET_PROTECT writes the
  long as given). [D]

### 6.5 RENAME_DISK [O]

- Arg1 = BSTR of the new name. §2.3 preconditions, name rules §2.2 (210). The root block's name and the volume
  node's name change; `Relabel df2: NewName` → Info shows `NewName`. [O]

### 6.6 What the protection bits do in the file system [O]

- `Protect f wed` (read cleared) then `Type f` → the file is printed: **read bit ignored**.
- `Protect f red` (write cleared) then `Echo >f new` → the file is replaced: **write bit ignored** (FINDOUTPUT
  only checks the delete bit, §5.1).
- Execute and the archive/pure/script bits are not looked at by the file system.
- The delete bit is honoured by DELETE_OBJECT and FINDOUTPUT over an existing object (222). [O]

---

## 7. Volume level

### 7.1 INFO and DISK_INFO

- DISK_INFO: `disk-change-v34.md` §2.3 (InfoData fields). INFO = the lock checks of §2.1, then the same fill
  with Arg2. [D] `Info df2:` sent DISK_INFO. [O]
- `id_NumBlocks` = 1758 on a DD floppy (blocks 2..1759), `id_BytesPerBlock` = 488. [O, Info]

### 7.2 CURRENT_VOLUME [O for Arg1 = 0, D otherwise]

- Arg1 = 0 → Res1 = BPTR of the current volume node (0 if none), **Res2 = the unit number** (`fssm_Unit`; 3
  observed for DF3:). dos sends it after a 214 to name the volume in its requester (§2.3).
- Arg1 = `fh_Arg1` of an open file → Res1 = the volume node the file was opened on, Res2 = unit number.

### 7.3 MORE_CACHE (AddBuffers) [O / D]

- Each buffer = 540 bytes (`dos-memory-v34.md` §6), allocated with the environment's `BufMemType`.
- Arg1 = n: adds n buffers one by one; **Res1 −1** when all were allocated [O: `AddBuffers df2: 10` → −1];
  **0** if an allocation failed (the buffers already added stay). [D]
- **n ≤ 0 adds nothing and answers −1**; buffers are never freed while the file system runs. [D] (C:AddBuffers of
  1.3.3 does not even send the packet for a negative number. [O])
- Res2 is noise (540 observed). [O]
- Initial count = `de_NumBuffers` of the environment (5 for the ROM DFn nodes, `handlers-v34.md` §1.2); the
  start-up fails if they cannot be allocated. [D]

### 7.4 FLUSH [D]

- If modified blocks are pending (the flush countdown of §8.4 is running) and no other FLUSH is waiting, the
  packet is **kept** and returned when the write-back completes; otherwise it is returned at once.
- It is returned **as received**: Res1 and Res2 are not written by the file system. A client that needs a
  success value must preset Res1 (e.g. to −1) before sending.

### 7.5 INHIBIT

See `disk-change-v34.md` §2.3.

---

## 8. Blocks on the disk

### 8.1 Allocation order on an empty disk [O]

Fresh DD disk (root 880, bitmap 881), commands run in this order; block numbers are those found in the image:

| Step | Header / extension | Data blocks (in sequence order) |
|---|---|---|
| `copy Why w1` (576 bytes, 2 data blocks) | 882 | 883, 869 |
| `makedir dir1` | 884 | — |
| `copy Ed ed` (19,564 bytes, 41 blocks) | 885 | 886, 876–879, 870–875, 858–868, 847–857, 836–843 |
| `copy Why dir1/w2` | 887 | 888, 845 |
| `join Ed Edit as big` (37,728 bytes, 78 blocks) | 889, extension 891 | 890, 844, 846, 825–835, 814–824, …, 759–767 |
| `echo >small "hello"` | 892 | 893 |

Reading of the table:
- **Headers and extension blocks** are taken by searching **upward from the root** (first free block above the
  root, the search moving to the next track up when a track is full, wrapping at the end of the disk).
- **The first data block** of a file is taken just after its header (same upward search from the header).
- **Later data blocks** are taken **track by track going down** from the track below the root track (blocks
  869–879, then 858–868, …), skipping the track that holds the header. Inside a track the search starts at the
  sector that follows the previous data block (plus the environment's interleave, 0 here) and wraps inside the
  track: after 886 (sector 6 of its track) the next block of `ed` was 876 (sector 7 of the next track down), and
  the track was then filled 877–879, 870–875. A per-volume "current data track" remembers where the downward
  search stopped, so the next file continues there (w2 found the last free blocks of track 76, `big` followed
  in track 76 then 75, 74, …).
- When the downward search reaches the lowest track it wraps to the top, and if a whole round finds nothing for
  data it falls back to the upward search; nothing free at all → 221.
- The second data block of the very first file (w1) went to the first block of the track (869), not to the
  sector after 883; the exact start of the rotation for that case is not explained [?]. Placement is **not** a
  compatibility contract (no program can rely on it); it is given so that an implementation can produce
  similar images.
[O for the numbers; D for the rule, from the code paths and the numbers]

### 8.2 Re-use after a deletion and after FINDOUTPUT [O]

- `echo >small "...longer..."` over the existing `small` (header 892, data 893): the new header was **881** (the
  block just freed by the bitmap move of §8.3), the new data block **892** (the old header's block).
- `delete w1` then `copy Prompt p1` (584 bytes): header **883** (w1's old first data block, lowest free above
  the root), data **893, 894** — both data blocks above the root this time, because the free blocks nearest to
  the header were there. [O]

### 8.3 The bitmap block moves [O]

The root block's bitmap pointer changed at each flush: **881 → 894 → 893 → 882 → 895** over five flushes. Each
time the bitmap is written to a newly allocated block (upward search, like a header) and the previous bitmap
block is freed. One bitmap block covers a DD floppy (only the first pointer of the root's table is used).
An implementation that keeps the bitmap at a fixed block produces valid disks; the move matters only for
block-exact image comparisons.

### 8.4 When things reach the disk [O timeline, D mechanism]

- The file system arms a countdown of **3** at every disk transfer it issues; the 1 s timer tick (ACTION_TIMER)
  decrements it; when it reaches 1 the file system **flushes**: writes the bitmap (new block) and the root
  (bitmap valid flag −1, new bitmap pointer), sends **CMD_UPDATE** then **TD_MOTOR off** to trackdisk, and
  returns any waiting FLUSH packet. So the write-back happens **2–3 s after the last disk access**. [D; timing
  O: in the image timeline the root with valid flag appeared 2–3 s after the last data track]
- First modification of a clean disk: the root block is written at once with the bitmap flag 0
  (`boot-clock-v34.md` §5). [O]
- New headers are written when created (size 0); the final header at END; data blocks as they are filled. The
  file system hands each modified block to trackdisk at once (its buffers are a **read cache**, not a write-back
  cache) [D]; trackdisk keeps a whole-track buffer and writes it only when it moves to another track or on
  CMD_UPDATE (`trackdisk-write-v34.md` §1). Hence in the image the blocks of the root track (root, header,
  bitmap) often appear only at the flush. [O]
- A disk removed before the flush may lack the last header update and the bitmap; the root then says "bitmap
  invalid" and the next mount revalidates. [D]

### 8.5 Buffers

- 5 buffers of 540 bytes at start (each = a 512-byte block plus the file system's bookkeeping), more with
  MORE_CACHE (§7.3). Used as a cache of recently read blocks (headers, directory blocks, bitmap) [D].

---

## 9. Error codes (Result2) by case

| Code | Name | When (this file system) |
|---|---|---|
| 202 | OBJECT_IN_USE | lock conflict (§3.1); DELETE/FINDOUTPUT/SET_* of a locked or open object; RENAME of a directory directly into itself |
| 203 | OBJECT_EXISTS | RENAME onto another object's name |
| 205 | OBJECT_NOT_FOUND | missing name; FINDUPDATE of a missing file; DELETE of the root |
| 209 | ACTION_NOT_KNOWN | packet type not in §1.1/§1.2 |
| 210 | INVALID_COMPONENT_NAME | bad new volume name (§2.2) [D] |
| 211 | INVALID_LOCK | lock not known to this file system |
| 212 | OBJECT_WRONG_TYPE | FINDINPUT/FINDOUTPUT/FINDUPDATE of a directory; path through a file; SET_* on the root |
| 213 | DISK_NOT_VALIDATED | modification while no bitmap is loaded |
| 214 | DISK_WRITE_PROTECTED | modification of a write-protected disk |
| 216 | DIRECTORY_NOT_EMPTY | DELETE of a non-empty directory; FINDOUTPUT over one |
| 218 | DEVICE_NOT_MOUNTED | lock or file of a volume that is not in the drive |
| 219 | SEEK_ERROR | SEEK outside 0..size, or inconsistent block chain met during SEEK |
| 220 | COMMENT_TOO_BIG | SET_COMMENT longer than 80 [D] |
| 221 | DISK_FULL | no free block (WRITE, FINDOUTPUT/CREATE_DIR header) |
| 222 | DELETE_PROTECTED | DELETE or FINDOUTPUT over an object whose delete bit is set |
| 225 | NOT_A_DOS_DISK | lock 0 / any request with a non-DOS disk in the drive |
| 226 | NO_DISK | same, drive empty |
| 232 | NO_MORE_ENTRIES | end of EXAMINE_NEXT |

Res2 after a success is not cleared (§1.1); `IoErr()` after a successful call returns noise.

---

## 10. Test vectors

Run on our ROM with the same commands; "Why" = output of C:Why after the command.

| # | Input | Expected (real 1.3) |
|---|---|---|
| V1 | `Echo >df2:a "data"`, then `Type >df2:a df2:a` | Why: "object in use" (202) |
| V2 | `List >df2:b df2:b` | Why: object in use (202) |
| V3 | `Delete >df2:c df2:c` | Why: object in use (202) |
| V4 | `MakeDir df2:d`, `Echo >df2:d/x "x"`, `Delete df2:d` | "Not Deleted - directory not empty" |
| V5 | `MakeDir df2:e`, `CD df2:e`, `Delete df2:e` | "Not Deleted - object in use" |
| V6 | `Rename df2:a df2:d` (d exists) | "Can't rename df2:a as df2:d", Why: object already exists |
| V7 | `Rename df2:a df2:d/a2` | success; `a2` listed in `d` |
| V8 | `Rename df2:g df2:h` (h exists) | Why: object already exists |
| V9 | `Rename df2:h df2:H` | success; List shows `H` |
| V10 | `Protect df2:d/a2 rwe`, `Delete df2:d/a2` | "Not Deleted - file is protected from deletion" |
| V11 | `Protect df2:f wed`, `Type df2:f` | content printed |
| V12 | `Protect df2:f red`, `Echo >df2:f "new"`, `Type df2:f` | `new` |
| V13 | `Protect df2:f rwe`, `Join df2:g as df2:f` | FINDOUTPUT → 0 / 222; `f` unchanged |
| V14 | `SetDate df2:f 01-Jan-80 12:34:56`, `List df2:f` | date `01-Jan-80 12:34:56` (packet 34 accepted) |
| V15 | `Echo >df2:abcdefghijklmnopqrstuvwxyz0123456789 "x"` | file `abcdefghijklmnopqrstuvwxyz0123` (30 chars) |
| V16 | `Join df2:f as df2:d` (d non-empty dir) | FINDOUTPUT → 0 / 216 |
| V17 | `MakeDir df2:empty`, `Join df2:g as df2:empty` | success; `empty` is now a 2-byte **file** |
| V18 | `Type df2:d` (dir) / `Type df2:f/x` / `Join df2:f as df2:f/x` | 0 / 212 each |
| V19 | `Delete df2:` | DELETE → 0 / 205 |
| V20 | `CD df2:`, `CD /` | PARENT → 0 / 0; "Can't find /" |
| V21 | List of a directory with files mm, aa, eu, zz, fh, qa created in that order | zz, qa, aa, eu, fh, mm |
| V22 | `MakeDir df2:p`, `MakeDir df2:p/q`, `Rename df2:p df2:p/q/r` | RENAME → −1; `p` gone from the root |
| V23 | `AddBuffers df2: 10` | MORE_CACHE(10) → −1 (and 10 × 540 bytes allocated, per §7.3) |
| V24 | `Relabel df2: NewName`, `Info df2:` | name NewName |
| V25 | CREATE_DIR of the name of an existing file | Res1 = lock; the file is replaced by an empty directory (I15) |
| V26 | CREATE_DIR of the name of a non-empty directory | 0 / 216 (I16) |
| V27 | FINDUPDATE of a missing file | 0 / 205, nothing created (I18) |
| V28 | ExNext to the end of a directory | last EXAMINE_NEXT → 0 / 232 |
| V29 | read-only ADF in DF3:, `Join df3:wpfile as df3:x`, `Delete df3:wpfile`, `MakeDir df3:nd`, `Rename df3:wpfile df3:zz`, `Protect df3:wpfile r`, `SetDate df3:wpfile 01-Jan-80`, `Relabel df3: XX` | each packet → 0 / 214; requester "Volume WProt is write protected" for Join, Delete, MakeDir, Rename, Relabel (preceded by CURRENT_VOLUME → volume node, Res2 = 3); none for Protect and SetDate |
| V30 | packet type 33 or 99 | 0 / 209 (I10) |
| V31 | fresh disk, the allocation sequence of §8.1 | the block numbers of §8.1; bitmap moves 881 → 894 at the first flush |
| V32 | in one hash slot create aa, eu, fh; delete eu; create lb | List: aa, fh, lb |
| V33 | all-zero image in DF1:, `MakeDir df1:x`, `Type df1:x`, `Dir df1:`, `Protect df1:a r`, `Info df1:` | each → 225 with the requester "Not a DOS disk / in unit  1" (Protect too); Info: "Not a DOS disk", no requester |
| V34 | OFS disk in DF1: with root bitmap flag 0, boot disk without `L:Disk-Validator`; `MakeDir df1:x`, `Delete df1:f`, `Protect df1:f r`, `Type df1:f` | MakeDir/Delete → 213 with "Volume / <name> / is not validated"; Protect → 213, no requester; Type works; Info status "Validating" |
| V35 | same disk, validator present | validated at mount (flag −1 on the disk), MakeDir works; read-only image: Info "Read Only", MakeDir → 214 |

### 10.1 In-flight rewriting results [O-inj]

Each line: the command typed, the packet that was rewritten, and the reply.

| # | Command / rewrite | Reply |
|---|---|---|
| I1 | `Type df2:b` (37 bytes), 1st READ → SEEK(10, −1) | 0 / 0 |
| I2 | same → SEEK(−5, 1) | 0 / 0 |
| I3 | same → SEEK(100, −1) | −1 / 219 |
| I4 | same → SEEK(−1, −1) | −1 / 219 |
| I5 | same → SEEK(37, −1) | 0 / 0 |
| I6 | same → SEEK(0, 5) | 0 / 0 |
| I7 | `Type df2:wb` (200 bytes), 2nd READ → SEEK(10, −1) | 200 / 0; next READ → 190 |
| I8 | `Join df2:b df2:b as df2:w2`, 2nd WRITE → SEEK(−10, 0) | 37 / 0; `w2` closed with size 37 |
| I9 | `Join df2:b as df2:w3`, 1st WRITE → SEEK(10, −1) | −1 / 219; `w3` empty |
| I10 | `Info df2:`, DISK_INFO → type 33, then type 99 | 0 / 209 both |
| I11 | `CD df2:e` LOCATE mode → −1, then `List df2:e` | CD granted; List's shared LOCATE → 0 / 202 |
| I12 | `List df2:b` LOCATE mode → −1 | lock granted, List normal |
| I13 | `List df2:b`, FREE_LOCK → COPY_DIR with Arg1 0 | a new lock (≠ 0), Res2 0 |
| I14 | `List df2:b`, FREE_LOCK Arg1 → 0 | −1 / 0 |
| I15 | `MakeDir df2:ord/zx` renamed in the packet to `ord/mm` (an existing file) | new lock; `mm` is now a directory |
| I16 | `MakeDir df2:ozd` renamed to `ord` (non-empty directory) | 0 / 216 |
| I17 | `MakeDir df2:ed2` renamed to `ed1` (existing empty directory) | new lock; `ed1` recreated (new date), no `ed2` |
| I18 | `Type df2:nothere`, FINDINPUT → FINDUPDATE | 0 / 205 |
| I19 | `Type df2:b` (shared locks held on b by I13/I14), FINDINPUT → FINDUPDATE | 0 / 202 |
| I20 | `Type df2:wb` (37 bytes, opened FINDINPUT), 1st READ → WRITE of 200 bytes | 200; `wb` is now 200 bytes |

---

## 11. Probes wanted (described, not written)

- **P1 — packet exerciser.** A small program that builds StandardPackets by hand and sends them to the
  `dn_Task` of DF1: (PutMsg / WaitPort), printing Res1/Res2 to the serial port. Cases: LOCATE exclusive while a
  shared lock exists; COPY_DIR of an exclusive lock; FREE_LOCK of a bogus lock; READ with length 0 and −1;
  SEEK failure followed by a READ (to show the position is unchanged); SET_COMMENT of 80 and 81 characters;
  SET_PROTECT/SET_DATE/SET_COMMENT on the root; INFO with lock 0; CURRENT_VOLUME with `fh_Arg1`; FLUSH with Res1 preset to a marker, and its reply time after a write; MORE_CACHE(−3) and
  MORE_CACHE(0) answers; types 0, 5 and 20.
- **P2 — ExNext under change.** Same program: Examine a directory, ExNext twice, then from a second process
  create, delete and rename entries (in an earlier slot, the current chain and a later slot), continue ExNext and
  print every name returned.
- **P3 — END on an absent volume.** Open a file, eject the disk, Close it, print the Res1 the file system sent
  (raw packet), to settle §5.5 against `disk-change-v34.md` §2.4.
- **P4 — protection changed while mounted.** Mount a writable disk, set the emulator's write-protect while it
  stays in the drive, then write: if the file system really keeps the state read at mount (§2.3), the write is
  attempted and trackdisk reports the error instead of 214.

## 12. Open points

- END for a file of an absent volume: Res1 0 (static reading) vs −1 (`disk-change-v34.md` §2.4) [?] (P3).
- Exact start sector of the data search for the first file on a fresh disk (§8.1, w1) [?].
- READ/SEEK error code for a broken data chain (219 for SEEK; READ not established) [?].
- SET_COMMENT on a write-protected disk not run (214 expected, same path as SET_PROTECT).

---

## Clean-room review

Review of 2026-11-04.

- [x] No instruction listing, no pseudo-code of a ROM routine: the page gives packet arguments and results,
  conditions and their order, error codes, FIB/lock field contents, and block numbers measured in disk images.
- [x] No ROM address or ROM offset. Internal values cited are ABI or observable: packet types, error codes,
  BCPL global 49 (`returnpkt`, already in `bcpl-runtime-v34.md`), FIB and FileLock offsets (public layout),
  block numbers on a floppy (public OFS geometry), coroutine stack sizes (they are the memory blocks of
  `dos-memory-v34.md`).
- [x] No ROM data reproduced (no strings table, no constant table). Messages quoted are user-visible output of
  Workbench 1.3.3 C: commands and the text of dos's write-protect requester as seen on screen (the same family
  as the "is full" requester of `disk-full-write-v34.md`). On 2026-11-04: "Volume / <name> / is not validated"
  and "Not a DOS disk / in unit  1", as seen on screen (§2.3, V33-V35).
- [x] The [O-inj] runs changed packets in memory with the debugger; no program was written. The debugger
  breakpoint locations used for this are not given.
- [x] Test disks were made with xdftool and C: commands (2026-11-04: plus a patch of the root bitmap flag and an
  all-zero image); their contents are described, not copied from the ROM.
