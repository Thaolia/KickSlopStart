# dos-lvo-partial-v34.md — dos.library V34: exact contracts of 16 "partial" LVOs

> ANALYSIS track ("dirty"). Sources: the real Kickstart 1.3 ROM (`kick34005.A500`, read-only) run under
> Amiberry (cycle-exact A500, 512 KB chip + 512 KB slow, copy of the Workbench 1.3.3 disk), observed as a
> black box; static reading of the dos kernel and BLIB segments with radare2 to know *what* is sent and
> returned. No instruction sequence, no ROM address or ROM offset below. Date: 2026-11-04.
>
> **Legend**: **[O]** observed on the running real ROM (registers and memory read with the debugger, screenshots)
> · **[S]** read statically in the ROM (behaviour only, not probed) · **[D]** deduced · **[?]** uncertain ·
> **AutoDocs** = public 1.3 AutoDoc/NDK contract.
>
> **How the [O] facts were obtained.** Each LVO was called **inside the Workbench process** ("Workbench",
> started by `LoadWB`, stack 5000 bytes, `pr_CIS = pr_COS = 0`, `pr_ConsoleTask = 0`, `pr_WindowPtr = 0`,
> `pr_CurrentDir` = a lock on the boot disk). The process was stopped by the debugger at the entry of its idle
> `Wait()` (only when it was not waiting for a DOS packet), its registers were saved, the argument registers
> were loaded (A6 = DosBase, D2–D7/A2–A5 set to marker values), the PC was pointed at the LVO vector with a
> return address under a hardware breakpoint, and the registers were restored afterwards. `pr_Result2` was
> set to a marker value (777 or 1234) before the calls where its behaviour mattered. Strings and buffers were
> placed in the unused part of the Workbench stack. No program was written or loaded.
>
> Related pages, not repeated here: `bcpl-runtime-v34.md` §1.4 (LVO → BCPL bridge, LVO/global table),
> §5.1 (FileHandle fields), §8 (globals, in particular 10, 47, 48, 51, 82, 91, 102, 108, 109, 113, 114, 127);
> `handlers-v34.md` §4.1 (deviceproc) and §4.2 (the common "object" routine); `dos-v34-spec.md` §1 (Process,
> FileLock, FileHandle layouts), §2b (packet table); `dos-memory-v34.md` §3.5 (UnLoadSeg freeing order), §5.1
> (Result2 not cleared by Lock); `disk-full-write-v34.md` §2/§4 (the "is full" requester);
> `dos-exit-packets-v34.md` (Exit, WaitForChar); **`rom-filesystem-v34.md`** (what the ROM file system itself
> answers to each packet: Res1/Res2 values, InfoData fields, lock list) — this page only describes the
> dos.library side, before and after the packet.

---

## 0. Executive summary

1. **Registers.** Every LVO of this page returns with **D0 = D1 = result**, **A0 = 0**, **A1 = scratch** (a
   pointer into the caller's stack, about 1.5 KB below SP), and **D2–D7/A2–A6 preserved**. Verified on every
   call made for this page. [O] The same holds for Open, Close, Read, Write, Seek, Lock, UnLock and Examine
   called by real programs (2026-11-10, §1.1a); Cluedo's `Type` relies on D1 after Seek. [O]
2. **Result2 has three behaviours** (§1.2). (a) Pure LVOs never touch it: Input, Output, CurrentDir, IoErr,
   IsInteractive, UnLoadSeg, Delay, DupLock(0), Seek/Open on `NIL:`. (b) Every LVO that sends a packet
   **copies `dp_Res2` into `pr_Result2` on success too**; the handlers leave stale values there (seen: 205,
   210, 202, 5492, 24132, −1). (c) A few failures are produced by dos itself before any packet (218, 215).
   **IoErr is only meaningful after a failure.** [O]
3. **Retry requester.** A failing packet (Res1 = 0; for Seek, Res1 < 0) goes through dos's disk-error
   requester, which only appears for disk-type errors (213, 214, 218, 221, 225, 226 and two internal codes) and
   only if `pr_WindowPtr` ≠ −1. Retry restarts the whole operation; Cancel returns the failure. Other errors
   (205, 202, 209, 219…) return at once. Observed: "No disk present / in unit 0" after a CreateDir. [O]
4. **Surprises a replacement must reproduce:** `IsInteractive(0)` returns the long at address 4 (ExecBase,
   non-zero); `Seek` on a CON: handle returns **0** (not −1) with IoErr 209; `Seek` on a `NIL:` handle returns
   0 without a packet; `Info(0, buf)` and `ParentDir(0)` go to `pr_FileSystemTask` with a zero lock (boot
   volume root); `Delay(−1)` had not returned after about 8 minutes. [O]

---

## 1. Common mechanics

### 1.1 Call bridge and register state [O]

The LVO vector loads a global number and enters the common bridge described in `bcpl-runtime-v34.md` §1.4.
Observed on return, for every LVO of this page:

| Register | On return |
|---|---|
| D0 | result (BCPL D1) |
| D1 | **same value as D0** |
| A0 | 0 |
| A1 | modified: points into the caller's stack, ≈ 1.5 KB below the caller's SP |
| D2–D7, A2–A5 | preserved (marker values intact) |
| A6 | preserved (DosBase) |
| SP | balanced |

- The bridge builds its BCPL frame 1500 bytes below SP and the called routines grow it upwards; the call
  consumes **about 1.5 KB of the caller's stack plus the packet/IORequest frames** (Delay keeps a 48-byte
  timer request there, §2.13). [S]
- Every LVO here must be called from a **Process**: they read `pr_*` fields through `FindTask(0)` and wait for
  packet replies on `pr_MsgPort` (signal bit 8). From a plain exec Task, Input/Output/IoErr read beyond the
  Task structure and packet LVOs wait on a non-existent port. [S]
- "No return value" LVOs (UnLoadSeg, Delay, Close, UnLock) still leave **something** in D0: a residue (0, a
  pointer into the stack, the last Result2…). Programs cannot rely on it; a replacement may return anything,
  but returning 0 for UnLoadSeg(0) matches what was seen. [O]

### 1.1a D1 = D0 for the core LVOs, seen in real programs (2026-11-10) [O]

Question: do Open, Close, Read, Write, Seek, Lock, UnLock, Examine (and the others) leave their result in D1 as
well as in D0, as §1.1 found for the LVOs of this page? A program relying on it exists: the `Type` command on the
Cluedo (French) boot disk (a 1380-byte command calling the dos LVOs, not the Workbench one), run twice by its
startup-sequence, takes the file
length from **D1** after Seek.

Method: real ROM under Amiberry (A500, 512 KB chip + 512 KB slow, cycle-exact). Hardware breakpoints on the
entry of each dos LVO vector (in the library's jump table, in RAM); at a hit the caller's return address was
read from the stack and a breakpoint put there; at the return D0, D1, A0 and the calling process's `pr_Result2`
were read. Callers: the Cluedo boot (its `Type`, the game's own process "BackGround_Process", the Workbench
process started by its LoadWB, the Initial CLI), and a Workbench 1.3.3 boot (the Workbench process opening a
drawer, the Initial CLI running commands, the third-party C command `muchmore` of that disk printing its usage).
No program was written; nothing was patched.

| LVO | Calls seen | D0 on return | D1 on return | A0 |
|---|---|---|---|---|
| Open (−30) | 9 (MODE_OLDFILE, files and icons) | FileHandle BPTR | **= D0** | 0 |
| Close (−36) | 9 | residue: always $57 in these runs | **= D0** | 0 |
| Read (−42) | 20 (full, short and 0-byte reads) | bytes read (e.g. 40000, 78, 9, 0 at end of file) | **= D0** | 0 |
| Write (−48) | 2 (to the CLI's output handle) | bytes written (20, 1) | **= D0** | 0 |
| Seek (−66) | 2, by Cluedo's `Type`: Seek(fh, 0, OFFSET_END) twice on a 315-byte file | 0, then **315** | **0, then 315** | 0 |
| Lock (−84) | 5 (four successes, one failure) | lock BPTR; 0 on failure (Result2 205) | **= D0** | 0 |
| UnLock (−90) | 5 | residue: 0, or 205 when `pr_Result2` was 205 | **= D0** | 0 |
| Examine (−102) | 1 (Workbench, a drawer lock) | −1 (DOSTRUE) | **= D0** | 0 |

- Every call, from ROM code and from programs alike, returned **D1 = D0** and **A0 = 0**: this is the common
  bridge (`bcpl-runtime-v34.md` §1.4), which returns the BCPL result register in both. IoErr and DeleteFile were
  already seen doing the same (§1.1, §3 row R). [O] The remaining LVOs of the vector table go through the same
  bridge [S], so the rule holds for all of them [D].
- Cluedo's `Type` calls Seek(fh, 0, OFFSET_END) **twice** and uses the second result (the previous position, i.e.
  the length) from D1; with D1 left unchanged it would read whatever the caller had there (the handle).
  Result2 after both Seeks was 0. [O]
- The UnLock residue is the value of `pr_Result2` in every call seen (0 or 205); Close's residue was $57 in all
  nine calls, from three different callers. Neither is a documented result. [O, meaning not established]
- **Rule for an implementation**: every dos LVO returns with D1 equal to D0 (for the "no result" LVOs, whatever
  D0 holds), A0 = 0, D2–D7/A2–A6 preserved.

### 1.2 `pr_Result2` (IoErr) [O]

| Class | LVOs | pr_Result2 |
|---|---|---|
| (a) no packet | Input, Output, CurrentDir, IoErr, IsInteractive, UnLoadSeg, Delay, DupLock(0), Seek on a `NIL:` handle | **unchanged** (marker 777/1234 survived) |
| (b) packet sent | Seek, DeleteFile, Rename, DupLock, Info, CreateDir, SetComment, SetProtection, ParentDir (also Lock, Open, Examine…) | **:= dp_Res2 of the reply, whatever Res1 is** — the copy is unconditional (BCPL `sendpkt`, global 48) |
| (c) dos-side failure, no packet | unknown device/volume (deviceproc), Rename across handlers, Cancel of the "Please insert volume" requester | 218 / 215 / 218 |

Values seen in class (b) **on success** (all stale handler values, not error reports):

| Call (success) | pr_Result2 after |
|---|---|
| Open of `s:startup-sequence` (DF0:, ROM file system) | 24132 |
| Seek(file, 0, OFFSET_BEGINNING) | 5492 |
| Seek(file, 0, OFFSET_END) / (…, OFFSET_CURRENT) | 0 |
| Open of `CON:0/0/300/60/x` | −1 |
| CreateDir("ram:newdir") | 205 |
| CreateDir("df0:wpdir") | 205 |
| Rename("ram:newdir", "ram:newdi2") | 210 |
| DeleteFile("ram:newdir") after a failed one | 202 (the value of the previous failure, re-reported by RAM:) |
| Lock, DupLock, Info, ParentDir on DF0:/RAM: | 0 |

- **Implementation guidance [D]:** copy `dp_Res2` into `pr_Result2` after every packet, success or not (a
  replacement handler may return 0 on success; nothing observable relies on the stale values). Never clear
  `pr_Result2` in the class (a) LVOs.
- `Open("NIL:")` sends no packet and leaves `pr_Result2` unchanged. [O]

### 1.3 Name resolution (name-based LVOs) [S, O where stated]

DeleteFile, Rename, CreateDir, SetComment, SetProtection (and Lock) are C adapters that convert the C name to a
BSTR (at most 255 characters, `bcpl-runtime-v34.md` §8.3, global −31) and call the BCPL routines of
`handlers-v34.md` §4.2–§4.3. Resolution is `deviceproc` (§4.1 there):

- **no prefix** (`t`): handler of the volume of `pr_CurrentDir`, Arg lock = `pr_CurrentDir`;
  **`pr_CurrentDir = 0`**: `pr_FileSystemTask`, lock 0 = root of the boot volume [O: `Lock(NULL)` with
  CurrentDir 0 returned a valid lock, D: on the root];
- **leading `:`** (`:t`): same handler, lock 0;
- **device, volume or assign prefix** (`DF0:t`, `Workbench1.3:t`, `LIBS:t`): first node of that name in the
  DevInfo list; lock = `dn_Lock` (assigns) or 0; port = `dn_Task`, or `fl_Task` of the assign lock; a device
  node without a task gets its handler started first;
- the **complete name** (prefix included) is sent in the packet; the handler skips up to the `:`;
- **unknown name** → requester "Please insert volume / NAME / in any drive" (Retry/Cancel); Cancel → the LVO
  returns 0 with Result2 = 218. With `pr_WindowPtr = −1`: no requester, immediate 0 / 218. [O]
- `NIL:` given to a name-based LVO: deviceproc returns no port and the LVO returns 0 with Result2 = 218 (set
  before the `NIL:` test). [S]
- **NULL name pointer**: the adapters of DeleteFile/CreateDir/Lock pass BPTR 0, which reads as an **empty
  name** (the byte at address 0 is 0 on a running system) → the object designated is the current directory
  itself. [O for Lock(NULL) → a valid lock with CurrentDir 0 (the root, D); S for the others] Rename and SetComment do
  not test their second string either (an empty string results). [S]

### 1.4 The retry requester after a failed packet [S, O where stated]

When the handler's reply means failure, dos calls its disk-error routine (global 114, "errorreq") with the
error in Result2:

- **Which errors show a requester**: 213 (not validated), 214 (write protected), 218 (volume to replace, "in any
  drive"), 221 (disk full), 225 (not a DOS disk), 226 (no disk present, with the unit number), and two
  non-standard codes 288 ("you must replace volume") and 296 ("read/write error"). The volume name shown comes
  from the lock's or the handle's volume, or is asked from the handler (ACTION_CURRENT_VOLUME, 7). [S; O for
  213, 214, 225, 226]
- **All other errors** (202, 203, 205, 209, 210, 212, 219, 222…): no requester, the LVO fails at once. [O for
  202/205/209/210/219]
- **Window**: the requester is an AutoRequest-style "System Request" window opened for the **calling process**:
  `pr_WindowPtr = −1` → no requester, treated as Cancel; `pr_WindowPtr = 0` → on the Workbench screen, top
  left; otherwise on the screen of that window. Buttons Retry (left) / Cancel (right); left Amiga + V selects
  Retry and left Amiga + B selects Cancel while the requester is the active window (keyboard details below). [O for
  −1 and 0]
- **Retry** restarts the whole call (name resolution and packet included); **Cancel** returns the failure value
  with Result2 = the error. [S; O for Cancel, and for Retry below]
- **A disk inserted while the requester is up answers it as Retry** [O]: with the requester shown for DF1:
  (213 and 225 cases below), inserting a valid DOS disk in DF1: closed the window with no click, the call ran
  again and succeeded (`MakeDir df1:x` / `df1:y` printed nothing, and the directory was then listed on the new
  disk). Clicking Retry with the faulty disk still in the drive brought the same requester back at once.
- **Left Amiga + B** did not dismiss the 213/225 requesters in the runs of 2026-11-04 (requester over the boot
  CLI window, keys sent by the emulator, also after clicking inside the requester); a mouse click on Cancel did.
  **Settled 2026-11-10, see the next bullet**: the keys only act while the requester window is the active
  window; the most likely explanation of the 2026-11-04 runs is that it was not active when the keys came. [D]
- **Keyboard answers, 2026-11-10** [O]. Real ROM, Amiberry A500 (512 KB chip + 512 KB slow, cycle-exact); keys
  sent as raw key codes (Amiga key held down, letter pressed and released, Amiga key released), every state
  looked at on a screenshot. Two setups: (1) **no Workbench**: an xdftool boot floppy with only a `c` directory
  (no startup-sequence), commands typed in the Initial CLI; (2) **with the Workbench**: a Workbench 1.3.3 copy
  whose startup-sequence keeps the boot CLI open after LoadWB, a drawer window open, commands typed in the boot
  CLI. Requesters: "Please insert volume / foo / in any drive" (`dir foo:`, unknown name) and "No disk present /
  in unit  1" (`dir df1:`, DF1: empty). Both appear at the top left of the Workbench screen, titled
  "System Request", and **are the active window when they appear** (highlighted title bar; the CLI window's
  title turns inactive).
  - **Left Amiga + B = Cancel**, in both setups and on both requesters: the window closes at once and the call
    fails (`Dir` printed "Could not get information for foo:" then the error, 218 / 226).
  - **Left Amiga + V = Retry**, in both setups. Proof: with the requester for `foo` up, a background
    `run wait 12 +` / `assign foo: c:` typed beforehand created the `FOO` assign (checked in the DevInfo list with
    the debugger; the requester stayed on screen, identical screenshots before and after); Left Amiga + V then
    closed the requester and `Dir` listed the `c` directory. On "No disk present" with the drive still empty,
    Left Amiga + V closed the requester and **the same requester was rebuilt at once** (caught half-drawn
    within 1 s; the first one had taken about 5 s to appear after the command); Left Amiga + B then cancelled
    it (226).
  - **Right Amiga + B** and **B alone**: no effect, the requester stays (Retry/Cancel need the left Amiga
    qualifier, as AutoRequest specifies: `intuition-requesters-v34.md` §5.1).
  - **Requester not active**: after a click in the CLI window (the requester stays on screen, inactive), Left
    Amiga + B went to the console: it **typed a `b`** on the CLI's input line and the requester stayed. A click
    inside the requester's body (not on a gadget) made it active again, and Left Amiga + B then cancelled it.
  - Side effect seen there [O]: while that `b` sat on the CLI input line, the output of the command (`Dir`'s
    error message, written after the Cancel) **did not appear** on the console; it appeared as soon as Backspace
    erased the `b`. The console holds back output while a partly typed line is pending.
  - After the requester closed, the window that was active before it (the CLI) was active again (debugger read
    of `ActiveWindow`, Workbench setup). [O]
  - One unexplained run [?]: in the no-Workbench setup, a sequence Right Amiga + B then B alone, sent 4 s after
    `dir baz:`, left a `b` on the CLI line although the requester looked active; repeated with each key
    separately, neither typed anything. Possibly the keys arrived before the activation was complete.
- Observed [O]: with DF0: reporting "no disk" (the emulator's write-protect switch toggled at run time made
  trackdisk report no disk), `CreateDir("df0:wpdir2")` with `pr_WindowPtr = 0` showed a "System Request"
  window "No disk present / in unit  0" (Retry/Cancel) on the Workbench screen; Cancel → D0 = 0, Result2 = 226.
  The same call with `pr_WindowPtr = −1` returned 0 / 226 immediately, and so did `DeleteFile("df0:nofile")`.
- **225, not a DOS disk** [O]. Setup: Workbench 1.3.3 copy in DF0: (startup-sequence cut down to SetPatch,
  Path and a serial marker; the boot CLI stays open, `pr_WindowPtr = 0`), an all-zero image in DF1:.
  The requester has **two lines and no volume name**: "Not a DOS disk" / "in unit  1" (the drive number, after
  two spaces, as for 226); buttons Retry / Cancel. After Cancel, C:Why printed "not a valid DOS disk" (225) for
  every command below. Commands and what they printed after Cancel:
  - `MakeDir df1:x` (CreateDir): requester; "Can't create directory df1:x".
  - `Delete df1:x`: requester; "Could not get information for "df1:x" - not a valid DOS disk".
  - `Echo >df1:x hi` (Open MODE_NEWFILE by the CLI): requester; "CLI error: Unable to open redirection file".
  - `Type df1:x` (Open MODE_OLDFILE): requester; "Can't open df1:x".
  - `Dir df1:` (Lock): requester; "Could not get information for df1:" / "not a valid DOS disk".
  - `CD df1:` (Lock): requester; "Can't find df1:".
  - `Rename df1:a df1:b`: requester; "Can't rename df1:a as df1:b".
  - `Protect df1:a r`: **requester** (unlike 214); "Protect failed". Which call inside C:Protect raised it was
    not traced. [?]
  - `Relabel df1: Foo`: requester; no message.
  - `Info df1:`: **no requester**; Info listed "DF1:  Not a DOS disk".
  With a non-DOS disk every call that reaches the drive's handler fails with 225, so the requester comes from
  the first call a command makes, whatever it is.
- **213, not validated** [O]. The requester has **three lines**, like 214: "Volume" / the volume name /
  "is not validated"; buttons Retry / Cancel. After Cancel, C:Why printed "disk not validated" (213) where the
  command sets Result2. Commands (DF1: holding a volume with no bitmap loaded, see below):
  - requester: `MakeDir df1:x` ("Can't create directory df1:x"), `Delete df1:f` ("Not Deleted - disk not
    validated"), `Echo >df1:x hi` ("CLI error: Unable to open redirection file"), `Rename df1:f df1:g` ("Can't
    rename df1:f as df1:g"), `Relabel df1: Foo` ("Attempt to rename disk failed");
  - **no requester**: `Protect df1:f r` ("Protect failed", Why: disk not validated) — the same split as for 214;
  - reading works normally: `Dir df1:`, `Type df1:f`, `CD df1:`; `Info df1:` shows the status "Validating" and
    leaves Used/Free/Full empty.
- **When 213 is actually met** [O]: a volume whose root block bitmap flag is not −1 is handed to the disk
  validator (`L:Disk-Validator` of the boot disk) when it is mounted.
  - Well-formed writable disk: validated before the first command was typed; no requester ever; the flag on
    the disk was −1 afterwards; MakeDir worked.
  - Same disk read-only: validated in memory (Info "Read Only", with used/free figures); writes gave **214**
    ("Volume / NoValF / is write protected"), not 213.
  - `L:Disk-Validator` deleted from the boot disk: for a disk already in the drive at power-on, no message at
    all; Info stays "Validating"; writes give the 213 requester. The same disk **inserted after boot** shows
    "Error validating disk" / volume name / "Unable to load disk validator" (Retry / Cancel), then the
    "Disk structure corrupt" requester after Cancel (2026-11-05). A disk whose flag is −1 needs no
    `L:Disk-Validator`: the ROM loads its bitmap (`rom-filesystem-v34.md` §2.5).
  - Validation failing (the xdftool test image had the disk type "DOS" + 0 in the hash-chain field of its root
    block; 1146049280 is that value read as a number): two requesters shown while validating, "Error validating
    disk" / volume name / "Key 1146049280 out of range", then "Disk structure corrupt" / "Use DISKDOCTOR to
    correct it" (Retry / Cancel each); afterwards Info stays "Validating" and writes give the 213 requester,
    **also on a read-only image** (213 is checked before 214). **Settled 2026-11-05**: these texts, and "Key n
    already set" / "Key n checksum error" / "Unable to load disk validator", are in the ROM; "Key n - bad block
    type" uses a text of `L:Disk-Validator`. Every xdftool-formatted disk that needs a full validation (flag not −1)
    fails this way on 1.3 (xdftool puts `'DOS\0'` in that field). The full table of causes and what Retry and Cancel do on each requester:
    `rom-filesystem-v34.md` §2.5. [O]
  - A write during the validation itself (the window between mount and the end of validation) was not caught. [?]
- Which LVOs go through it: name-based ones (DeleteFile, CreateDir, Rename, SetComment, SetProtection, Lock),
  lock-based ones (Info, ParentDir, Examine, ExNext) and handle-based ones (Read, Write, Seek). **DupLock does
  not** (plain packet, no retry). [S]

---

## 2. Per-LVO contracts

Notation: `fh` = BPTR of a FileHandle, `lock` = BPTR of a FileLock, "C string" = APTR to a NUL-terminated
string. Packet arguments are `dp_Arg1…`; "port" is the handler MsgPort the packet goes to.

### 2.1 Input (−54) and Output (−60)

- In: nothing. Out: D0 = `pr_CIS` (−54) / `pr_COS` (−60), raw BPTRs (0 if the process has no stream). [O: 0
  in the Workbench process] Pure read, BCPL globals 65/66 shared with the BCPL runtime. Result2 unchanged. [O]
- A process created by `CreateProc` or started by the Workbench has 0 in both. [O for the Workbench process]

### 2.2 Seek (−66)

- In: D1 = fh, D2 = position (signed), D3 = mode (−1 OFFSET_BEGINNING, 0 OFFSET_CURRENT, 1 OFFSET_END).
  Out: D0 = **previous** position, or −1 on error.
- **`fh_Type` (FileHandle +$08) = 0** (a `NIL:` handle): returns **0** immediately, no packet, Result2
  unchanged, whatever the arguments. [O]
- Otherwise sends **ACTION_SEEK (1008)** to `fh_Type` with Arg1 = `fh_Arg1` (FileHandle +$24), Arg2 =
  position, Arg3 = mode, and returns **dp_Res1** with Result2 := dp_Res2. If Res1 is **negative**, the retry
  requester logic of §1.4 runs (no requester for 219). [S; O for the results below]
- dos does **not** validate the mode, does not consult or flush the FileHandle buffer fields (`fh_Buf/Pos/End`
  used by the BCPL stream routines), and does not test fh for 0. [S]
- ROM file system (DF0:, `s:startup-sequence`, 819 bytes, fresh handle) [O]:

| Call (in order) | D0 | Result2 |
|---|---|---|
| Seek(fh, 0, OFFSET_END) | 0 | 0 |
| Seek(fh, 0, OFFSET_BEGINNING) | 819 | 5492 (stale) |
| Seek(fh, 0, OFFSET_CURRENT) | 0 | — |
| Seek(fh, 100000, OFFSET_BEGINNING) | −1 | 219 (ERROR_SEEK_ERROR), no requester |
| Seek(fh, 0, OFFSET_CURRENT) | 0 (position unchanged by the failed seek) | |
| Seek(fh, 5, mode 7) | −1 | 219 |
| Seek(fh, −5, OFFSET_CURRENT) at position 0 | −1 | 219 |

- **CON: handle** (`CON:0/0/300/60/x`, MODE_NEWFILE): Seek(fh, 0, OFFSET_CURRENT) and Seek(fh, 0,
  OFFSET_BEGINNING) both return **0** with Result2 = **209** (ERROR_ACTION_NOT_KNOWN): the console handler
  answers Res1 = 0, which dos treats as a valid position. A program testing for −1 sees success. [O]
- `NIL:` handle: Seek(fh, 0, OFFSET_CURRENT) → 0; Seek(fh, 10, OFFSET_BEGINNING) → 0; Result2 unchanged. [O]
- **Seek(0, …)** (NULL handle): `fh_Type` is read from address 8 (an exception vector), the packet goes to a
  bogus "port" → system failure. Not reproduced as a feature. [S, not probed]

### 2.3 DeleteFile (−72)

- In: D1 = C string. Out: D0 = dp_Res1 (−1 = DOSTRUE on success, 0 on failure).
- Packet **ACTION_DELETE_OBJECT (16)** via the object routine (`handlers-v34.md` §4.2): Arg1 = reference lock
  from deviceproc, Arg2 = BSTR of the complete name. Retry requester on disk errors (§1.4). [S]
- Observed on RAM: [O]:

| Situation | D0 | Result2 |
|---|---|---|
| directory exists, a lock on it is held | 0 | 202 (ERROR_OBJECT_IN_USE) |
| same after UnLock | −1 | 202 (stale, re-reported) |
| deleted again (absent) | 0 | 205 |
| never existed (`ram:nfx`) | 0 | 205 |

- DF0: with the drive reporting no disk: `pr_WindowPtr = −1` → 0 / 226 immediately. [O]

### 2.4 Rename (−78)

- In: D1 = old C string, D2 = new C string. Out: D0 = dp_Res1.
- Both names are converted, then BCPL global 91 (`bcpl-runtime-v34.md` §8.4.2): deviceproc on each name;
  **different handler ports → 0 with Result2 = 215, no packet**; otherwise **ACTION_RENAME_OBJECT (17)** with
  Arg1 = old reference lock, Arg2 = old name, Arg3 = new reference lock, Arg4 = new name; failure → retry
  requester logic. [S]
- Observed [O]:

| Call | D0 | Result2 |
|---|---|---|
| Rename("ram:newdir", "ram:newdi2") | −1 | 210 (stale) |
| Rename("ram:newdi2", "df0:newdi") | 0 | 215, no requester |
| Rename("ram:nfx", "ram:newdir") (source absent) | 0 | 205 |

### 2.5 DupLock (−96)

- In: D1 = lock. Out: D0 = new lock or 0.
- **lock = 0 → returns 0 at once, no packet, Result2 unchanged.** [O] (Unlike 2.0 AutoDocs, DupLock(0) is
  not "a lock on the root".)
- Otherwise **ACTION_COPY_DIR (19)** to the lock's `fl_Task` (FileLock +$0C) with Arg1 = lock; returns
  dp_Res1, Result2 := dp_Res2. **No retry requester**: a failure (e.g. disk gone) returns 0. [S]
- Observed: DupLock(lock on `s:`) → a new, distinct lock BPTR with the same `fl_Volume`; Result2 0. [O]

### 2.6 Info (−114)

- In: D1 = lock, D2 = APTR of an InfoData (36 bytes). Out: D0 = dp_Res1 (−1 success, 0 failure).
- D2 is converted to a BPTR by **dropping its two low bits**: the buffer must be longword-aligned (an
  unaligned buffer silently shifts down to the previous longword boundary). [S]
- Port: **lock ≠ 0 → `fl_Task`; lock = 0 → `pr_FileSystemTask`**. Packet **ACTION_INFO (26)**, Arg1 = lock (0
  passed as is), Arg2 = BPTR of the buffer. Failure → retry requester logic. [S]
- Observed [O]:

| Call | D0 | InfoData read back |
|---|---|---|
| Info(lock on `s:` of DF0:) | −1 | NumSoftErrors 0, UnitNumber 0, DiskState 82 (ID_VALIDATED), NumBlocks 1758, NumBlocksUsed 1431, BytesPerBlock 488, DiskType `DOS\0`, VolumeNode = BPTR of the volume node, InUse ≠ 0 |
| **Info(0, buf)** (Workbench process, `pr_FileSystemTask` = DF0:'s handler) | −1 | identical to the line above (boot volume) |
| Info(lock on `ram:`) | −1 | NumSoftErrors 0, **UnitNumber −1**, DiskState 82, NumBlocks = NumBlocksUsed = 4, BytesPerBlock 488, DiskType `DOS\0`, VolumeNode ≠ 0, InUse ≠ 0 |

  `id_InUse` read back equal to the BPTR of a lock held on that volume (the one passed, or the one still
  held when 0 was passed); its exact meaning belongs to the handler (`rom-filesystem-v34.md`). Result2 after
  each: 0. [O]
- Info on a console: a lock on CON: cannot be obtained in 1.3 (the console handler does not answer
  LOCATE_OBJECT with a lock), so this case does not arise through dos. [D, not probed]

### 2.7 CreateDir (−120)

- In: D1 = C string. Out: D0 = **lock** (BPTR) on the new directory, or 0. The caller owns that lock and must
  UnLock it (C:MakeDir does). [S + AutoDocs]
- Packet **ACTION_CREATE_DIR (22)** via the object routine, Arg1 = reference lock, Arg2 = complete name.
  Retry requester logic on failure. [S]
- Observed [O]: CreateDir("ram:newdir") → lock, Result2 205 (stale); again while that lock is held → 0 / 202;
  CreateDir("df0:wpdir") → lock, Result2 205; with DF0: reporting no disk: requester "No disk present / in
  unit 0" (`pr_WindowPtr = 0`) or immediate 0 / 226 (`pr_WindowPtr = −1`), §1.4.
- [?] The result for an existing directory with no lock held was not probed (handler-dependent: see
  `rom-filesystem-v34.md` for DF0:).

### 2.8 CurrentDir (−126)

- In: D1 = lock (or 0). Out: D0 = the **previous** `pr_CurrentDir`.
- Writes D1 into `pr_CurrentDir` (Process +$98) **without any check, packet, DupLock or UnLock**; Result2
  unchanged. [O]
- **CurrentDir(0)** is valid: afterwards relative names resolve through `pr_FileSystemTask` from the root of
  that handler's volume (§1.3). [O: CurrentDir(0) returned the old lock and left 0; `Lock(NULL)` then returned
  a lock (the boot volume root, D)] Cross-reference: `dos-v34-spec.md` §4b (a detached program calls CurrentDir(0) first).

### 2.9 IoErr (−132)

- Out: D0 = `pr_Result2` (Process +$94). **Never clears it**: with the marker 1234 preset, IoErr returned
  1234 and `pr_Result2` still held 1234 afterwards. [O]

### 2.10 UnLoadSeg (−156)

- In: D1 = seglist BPTR (BCPL global 82 called directly, no adapter). Out: D0 not meaningful.
- **UnLoadSeg(0)**: returns at once, **D0 = 0**, nothing freed, Result2 unchanged. [O]
- Normal list: frees the segments in chain order (`dos-memory-v34.md` §3.5). Result2 unchanged. [S]
- **Overlaid program**: if the first segment carries the public overlay-manager signature (the longword
  `$0000ABCD` right after the first code longword, and the dos global vector address five longwords after the
  start of the code, as written by the hunk loader for `HUNK_OVERLAY` files), dos first closes the overlay
  file handle stored there (selected as input, ended, previous input reselected), frees the hunk table and the
  overlay table vectors stored there, then frees the resident chain. [S, layout = public AmigaDOS overlay ABI]
- A segment whose size header (the longword before the segment) is **negative** is treated specially: its first
  code longword is passed to exec `CloseLibrary`, the size is made positive and the block freed. [S, purpose
  [?]: no loader path that produces it was identified]

### 2.11 SetComment (−180)

- In: D1 = C string (object name), D2 = C string (comment). Out: D0 = dp_Res1 (−1 / 0).
- The comment is converted to a BSTR in the adapter's frame (≤ 255 characters; the 80-character limit is the
  handler's). Packet **ACTION_SET_COMMENT (28)** via the object routine, with the special layout of
  `handlers-v34.md` §4.2: **Arg1 not initialised**, Arg2 = reference lock, Arg3 = complete name, Arg4 =
  comment BSTR. Retry requester logic on failure. [S]
- Observed [O]: SetComment("ram:newdir", "hello") → −1, and a later Examine shows the comment; on an absent
  name → 0 / 205.

### 2.12 SetProtection (−186)

- In: D1 = C string, D2 = protection mask (long, passed as is). Out: D0 = dp_Res1.
- Packet **ACTION_SET_PROTECT (21)**, same layout as SetComment (Arg1 not initialised, Arg2 = lock, Arg3 =
  name, Arg4 = mask). Retry requester logic on failure. [S]
- Observed [O]: SetProtection("ram:newdir", 5) → −1, Examine then reads `fib_Protection` = 5; absent name → 0 /
  205.

### 2.13 Delay (−198)

- In: D1 = ticks (1/50 s, signed). Out: D0 not meaningful (a pointer into the caller's stack was seen).
  Result2 unchanged. [O]
- BCPL global 47: seconds = ticks / 50 (signed division, truncated towards 0), microseconds = (ticks rem 50) ×
  20000 (remainder has the sign of ticks); then a **TR_ADDREQUEST** on timer.device **UNIT_MICROHZ** through
  global 127 (device opened, DoIO, closed at each call, request in the caller's stack, reply port =
  `pr_MsgPort`). [S]
- Delay(0) and Delay(25) return normally. [O]
- **Delay(−1)** (seconds 0, microseconds −20000 = $FFFFB1E0 as an unsigned field) **did not return within about 8
  minutes** (the debugger session ended first). [O] [D] timer.device takes the microseconds field unsigned, i.e. ≈ 4295 s
  (≈ 72 minutes). Any negative argument therefore blocks for a long time (−50 and below: seconds negative,
  i.e. ≈ 136 years unsigned). No program should depend on it; a replacement may treat negative values the
  same way or clamp them, but must not return early for positive ones. [?] not probed beyond −1.

### 2.14 ParentDir (−210)

- In: D1 = lock. Out: D0 = lock on the parent, or 0.
- Port: lock ≠ 0 → `fl_Task`; **lock = 0 → `pr_FileSystemTask`**. Packet **ACTION_PARENT (29)**, Arg1 = lock,
  Arg2 = 0. Res1 = 0 goes through the retry requester logic (no requester when Result2 is 0). [S]
- Observed [O]:

| Call | D0 | Result2 |
|---|---|---|
| ParentDir(lock on `df0:s`) | lock on the root | 0 |
| ParentDir(root lock of DF0:) | 0 | 0, no requester |
| **ParentDir(0)** | 0 | 0 |
| ParentDir(root lock of RAM:) | 0 | 0 |

### 2.15 IsInteractive (−216)

- In: D1 = fh. Out: D0 = `fh_Interactive` (FileHandle +$04), **raw, not normalised**. Result2 unchanged.
- Observed [O]: CON: handle → **−1**; ROM file system file → **0**; `NIL:` handle → **0**.
- **IsInteractive(0)** → the longword at address 4, i.e. **ExecBase** (non-zero, "interactive"). [O] A
  replacement must not crash on 0; returning a non-zero value matches 1.3.

---

## 3. Test vectors (observable, all from the Workbench process)

| # | Call | Expected D0 | Expected pr_Result2 |
|---|---|---|---|
| T1 | IoErr() with Result2 preset to 1234 | 1234 | still 1234 |
| T2 | Input(), Output() in a Workbench-started process | 0, 0 | unchanged |
| T3 | IsInteractive(0) | the long at address 4 (≠ 0) | unchanged |
| T4 | IsInteractive(CON: fh / file fh / NIL: fh) | −1 / 0 / 0 | unchanged |
| T5 | UnLoadSeg(0) | 0 | unchanged |
| T6 | CurrentDir(0) | the old lock; `pr_CurrentDir` = 0 afterwards | unchanged |
| T7 | DupLock(0) | 0 | unchanged |
| T8 | Seek(NIL: fh, 10, OFFSET_BEGINNING) | 0 | unchanged |
| T9 | Seek(file of 819 bytes, 0, END) then (0, BEGINNING) | 0, then 819 | — |
| T10 | Seek(file, 100000, OFFSET_BEGINNING) | −1, no requester, position unchanged | 219 |
| T11 | Seek(CON: fh, 0, OFFSET_CURRENT) | **0** | 209 |
| T12 | Info(0, aligned buf) | −1, buffer = boot volume data | 0 (ROM FS) |
| T13 | ParentDir(0), ParentDir(root lock) | 0, 0 | 0, no requester |
| T14 | Rename("ram:a", "df0:a") | 0 | 215, no packet |
| T15 | Lock("FOOVOL:x", SHARED) with pr_WindowPtr = −1 | 0 at once | 218 |
| T16 | same with pr_WindowPtr = 0 | requester "Please insert volume / FOOVOL / in any drive"; Cancel → 0 | 218 |
| T17 | CreateDir on a drive reporting no disk, pr_WindowPtr = 0 | requester "No disk present / in unit 0"; Cancel → 0 | 226 |
| T18 | CreateDir("ram:d") | a lock | stale (205 seen) — do not test for 0 |
| T19 | DeleteFile("ram:d") while its lock is held | 0 | 202 |
| T20 | SetComment / SetProtection on an absent name | 0 | 205 |
| T21 | Delay(0) | returns at once | unchanged |
| R | every call above | D1 = D0, A0 = 0, D2–D7/A2–A6 preserved | |

---

## 4. Probes still wanted (described, not written)

1. **Write-protected disk from boot.** Toggling the emulator's write-protect switch at run time made the drive
   report "no disk" (226), so the 214 path was not seen. Boot from a copy of an ADF that is write-protected
   before power-on, then `DeleteFile`, `CreateDir`, `Rename`, `SetComment` on DF0: with `pr_WindowPtr` 0 and
   −1: expect a "… is write protected" requester naming the volume, Cancel → 0 / 214.
2. **Delay with negative values**: time Delay(−1), Delay(−49), Delay(−50) against the TOD clock from a small
   CLI program (print the elapsed 1/50 s), to confirm the unsigned-microseconds reading and whether timer.device
   normalises tv_micro ≥ 1 000 000.
3. **Seek on `*`** (the console of a CLI) and on RAW:/NEWCON: handles, and Seek right after a BCPL-buffered
   read (to show that dos does not account for `fh_Pos/fh_End`).
4. **Overlay UnLoadSeg**: load and unload an overlaid executable (any 1.3-era program using `HUNK_OVERLAY`),
   checking that free memory returns to its initial value and the overlay file's lock is released.
5. **DeleteFile(NULL) / CreateDir(NULL)** with `pr_CurrentDir` on an empty RAM: directory: expect the handler to
   act on the current directory itself (likely 202 because of the CurrentDir lock).
6. **CreateDir on an existing directory** with no lock held, on DF0: and RAM: (203 expected, not seen).
7. **Info with an unaligned buffer** (APTR = aligned + 2): confirm the data lands 2 bytes lower.

## 5. Open / uncertain points

- The meaning of `id_InUse` and of the stale success Result2 values belongs to the handlers
  (`rom-filesystem-v34.md`); dos passes them through unchanged.
- The negative-size segment case of UnLoadSeg (§2.10) is read statically; its producer is unknown.
- Codes 288 and 296 of the retry requester are not standard `ERROR_*` codes; which component produces them was
  not traced.

---

## Clean-room review

Review of 2026-11-04; the two validator bullets of §1.4 updated 2026-11-05 (texts seen on screen only).

- [x] No instruction sequence transcribed or paraphrased; routines are described as inputs, outputs, packets
  and ordered observable effects. No pseudo-code of a ROM routine.
- [x] No ROM address or offset inside the ROM. Addresses that appear are ABI or public: address 4 (ExecBase
  pointer), address 8 (an exception vector), structure offsets of public NDK structures (Process +$94/+$98/
  +$B8, FileHandle +$04/+$08/+$24, FileLock +$0C), BCPL global numbers, LVOs, packet types, error codes, the
  public overlay signature `$ABCD`.
- [x] RAM addresses seen during the probes (task, lock and stack addresses) are not reproduced; values quoted
  are results (lengths, positions, error codes, InfoData fields of the test disk).
- [x] ROM data: the requester texts quoted are the ones **seen on screen** during the probes ("Please insert
  volume / … / in any drive", "No disk present / in unit 0", and on 2026-11-04 "Not a DOS disk / in unit  1",
  "Volume / <name> / is not validated" and the two validation-failure requesters); the other requester messages
  are described by meaning only, not copied. Command output quoted in §1.4 is what the Workbench 1.3.3 C:
  commands printed on screen.
- [x] The 2026-11-04 runs (§1.4, 213/225) were black-box: commands typed in the boot CLI of the real ROM,
  screenshots, test disks made with xdftool plus a root-block flag patch; no debugger, no disassembly.
- [x] No code was written: the probes were debugger register/memory manipulations of the running Workbench
  process; the further probes of §4 are described only.
- [x] 2026-11-10 additions (§1.1a registers of the core LVOs, §1.4 keyboard answers to the requester): black box.
  Breakpoints were set only on the library's jump-table entries (in RAM) and on the callers' return addresses;
  only register values on return are reported (no addresses). The requester tests were commands typed in a CLI
  and keys sent by the emulator, every state looked at on a screenshot. No disassembly, no code written.
