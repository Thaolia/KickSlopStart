# ramlib.library 34.1 (Kickstart 1.3) — behavioural spec

> **ANALYSIS** track (dirty). Sources: ROM `assets/kick34005.A500` (read-only; temporary disassembly outside the
> repository) and black-box runs of the real ROM under Amiberry (A500, cycle-exact, 512 KB chip + 512 KB slow,
> copy of the Workbench 1.3.3 disk whose startup-sequence was reduced to one `echo` line, so that neither SetPatch
> nor any other patch was loaded), 2026-11-04. The calls of §8 were **injected with the debugger** into a running
> task (a stop at the entry of `Wait` in that task, a three-instruction trampoline in RAM that loads A7 and calls
> the vector, a stop on its return), exactly as a program would call the vectors; no program was written.
> Legend: **[R]** ROM analysis, **[S]** observed on the real ROM, **[D]** public doc (AutoDocs, RKRM, includes),
> **[I]** inferred. ROM addresses are deliberately absent.
> Answers rank 14 of `coverage-v34.md` §7. Complements `module-map.md` (ROMTag), `dos-boot-sequence.md`
> (when dos starts), `dos-memory-v34.md` §1.2 (low-memory expunge seen from dos).

---

## 0. Short answer

- In 1.3, ramlib **has no process and no task of its own**. There is no "LDDemon" (that is a 2.0 design). The
  whole disk load runs **in the context of the task that called `OpenLibrary`/`OpenDevice`**: the `Lock`,
  `CurrentDir` and `LoadSeg` calls are made by that task. [R][S]
- ramlib works by **patching seven exec vectors with SetFunction** when it is initialised: `AllocMem`,
  `OpenLibrary`, `OpenDevice`, `CloseLibrary`, `CloseDevice`, `RemLibrary`, `RemDevice`. The previous
  functions are kept in ramlib's own vectors −30 to −66. [R][S]
- ramlib is initialised **by dos.library's init**, right after dos adds itself to the library list. Before
  that (e.g. on the insert-disk screen) the exec vectors still point into the ROM and ramlib is not in the
  library list. [R][S]
- `OpenLibrary(name)` of a name that is not in memory: the base name (after the last `/`, otherwise the last
  `:`) is searched; if absent, the file is loaded with `LoadSeg(name as given)` **with the current directory
  set to `LIBS:`** (`DEVS:` for devices), its RomTag is found in the first hunk and passed to `InitResident`,
  then the real open is retried. The version test is the ordinary exec test, done on that retry. [R][S]
- **The caller must be a Process.** A plain Task that triggers a disk load crashes the machine on 1.3:
  observed Guru `#00000004.<task address>` (illegal instruction in the task), after the task entered dos
  `Lock`. [S]
- **Low-memory expunge belongs to ramlib, not to exec.** ramlib's `AllocMem` replacement, on failure,
  expunges **every** library and device whose open count is 0 (and frees their seglists), then retries
  once; if that fails too and the caller is a Process, `pr_Result2` becomes 103. [R][S]
- `CloseLibrary`, `CloseDevice`, `RemLibrary`, `RemDevice` replacements free the seglist returned by an
  `Expunge` vector. Exec itself never unloads code. [R][S]

---

## 1. The resident [R][S]

| Field | Value |
|---|---|
| RomTag | `rt_Flags` = RTF_AUTOINIT only (no COLDSTART), `rt_Version` 34, `rt_Type` NT_LIBRARY, `rt_Pri` 70, name `"ramlib.library"`, id string `"ramlib 34.1 (18 Aug 1987)\r\n"` (see module-map.md) |
| Base size | 178 bytes positive (dataSize), 11 vectors (66 bytes negative) |
| InitStruct data | ln_Type NT_LIBRARY, ln_Name, lib_Flags = LIBF_SUMUSED\|LIBF_CHANGED, lib_Version 34, lib_Revision 1, lib_IdString, **lib_OpenCnt = 1** |
| Vectors | −6 Open, −12 Close, −18 Expunge, −24 reserved (returns 0), −30…−66: seven slots that initially return 0 and are overwritten at init with the original exec functions (§2.2) |

- **lib_OpenCnt starts at 1 from the init data table** and nobody else opens ramlib: after boot the library
  list shows `ramlib.library 34.1 open 1` [S]. The count of 1 is what keeps ramlib out of its own low-memory
  expunge walk (§6), which only touches nodes whose count is 0. Observed with a write watch on the field: the
  value 1 is written by exec's InitStruct during `InitResident` of ramlib, in the boot task (named
  `exec.library`). [S]
- ramlib's library node has priority 0 and is the last library of the list after boot (it is added after
  dos). [S]

### 1.1 When it is initialised [R][S]

1. dos.library's init allocates and fills its base, calls `AddLibrary(dos)`, then
   `FindResident("ramlib.library")` and, if found, `InitResident(tag, 0)`. This happens in the task that
   initialises dos (the boot task when booting from a floppy). No COLDSTART pass ever initialises ramlib.
2. ramlib's init routine (A6 = ExecBase, D0 = base, A0 = segment list 0):
   - keeps ExecBase and the seglist argument in its base;
   - `OpenLibrary("dos.library", 0)` and keeps DOSBase; on failure, `Alert($08038007)` (AN_RAMLib \|
     AG_OpenLib \| AO_DOSLib; not a dead-end alert) and initialisation continues;
   - prepares two "kinds": libraries (list = `ExecBase->LibList`, directory `"LIBS:"`, real function =
     original `OpenLibrary`) and devices (list = `ExecBase->DeviceList`, directory `"DEVS:"`, real function =
     original `OpenDevice`), and an empty list of loads in progress (§4);
   - patches the seven exec vectors (§2.2) and returns the base.
3. Observed: with no disk inserted (insert-disk picture), exec's `OpenLibrary`, `AllocMem` and `CloseLibrary`
   vectors jump into the ROM and the library list has no dos and no ramlib. After a floppy boot, the seven
   vectors jump into RAM inside ramlib's base. [S]

### 1.2 Open / Close / Expunge of ramlib itself [R]

- Open: open count + 1, clears the delayed-expunge flag, returns the base.
- Close: open count − 1; if the count is now ≤ 1 and a delayed expunge is pending, Expunge; returns 0
  otherwise.
- Expunge: if the open count is above 1, sets the delayed-expunge flag and returns 0. Otherwise it removes
  ramlib from the library list, tries to undo its patches, frees its base and returns its seglist. As far as
  the analysis can tell, **the undo step does not reinstate the original exec vectors correctly** (uncertain);
  nothing in 1.3 reaches it (ramlib's count never drops to 0, §6). Recommendation: an Expunge that always
  returns 0 and never removes ramlib.

---

## 2. Exec patches

### 2.1 Mechanism [R][S]

- For each patched function, ramlib calls `SetFunction(ExecBase, LVO, stub)` and stores the returned
  previous function with `SetFunction(ramlibBase, slot, previous)` into its own jump table. So a caller of
  ramlib's slot gets the **previous** exec function (the ROM one, or whatever a program had put there
  before dos started).
- The new exec vectors point to small per-function stubs held in ramlib's base (RAM). Each stub enters the
  replacement routine with **A6 = ExecBase (unchanged) and A5 = ramlib's base**, the caller's A5 being saved
  and restored around the call; all other registers arrive as the caller set them. The way the stubs are
  built is free; only "A5 is preserved for the caller" matters.
- A later `SetFunction` on the same exec vector (SetPatch, a program) chains in front of ramlib's
  replacement; ramlib keeps calling the function it saved, not the current vector.
- Exec's library checksum: SetFunction marks exec as changed and re-sums it (ordinary SetFunction contract);
  the exec flags read `$04` (SUMUSED) after boot. [S]

### 2.2 Table of patches [R][S]

| exec vector | ramlib slot holding the previous function | Replacement behaviour |
|---|---|---|
| −198 `AllocMem` | −30 | §6: retry after expunging all unused libraries and devices |
| −552 `OpenLibrary` | −36 | §3: load from `LIBS:` |
| −444 `OpenDevice` | −42 | §3: load from `DEVS:` |
| −414 `CloseLibrary` | −48 | call the previous function; if it returns non-zero, free that value as a seglist (§5) |
| −450 `CloseDevice` | −54 | same |
| −402 `RemLibrary` | −60 | same |
| −438 `RemDevice` | −66 | same |

- The four Close/Rem replacements **return the value returned by the previous function unchanged** in D0
  (the seglist BPTR, which has just been freed, or 0). [R]
- Order of installation: the order of the table. [R]

---

## 3. OpenLibrary / OpenDevice replacement [R][S]

Inputs are the exec ones: `OpenLibrary(A1 = name, D0 = version)`, `OpenDevice(A0 = name, D0 = unit,
A1 = ioRequest, D1 = flags)`. D0, D1, A0, A1 are saved on entry and restored before each attempt of the real
function, so every attempt sees the caller's arguments except the name.

"An attempt with name N" below = call the saved original exec function with the name replaced by N;
**success** = non-zero base for a library, return value 0 for a device. The value returned to the caller is
always the result of the **last attempt** (a base or 0 for a library; the error byte, sign-extended, for a
device — the original OpenDevice sets `io_Error`).

1. **Attempt with the name as given.** Success → return.
2. Failure: `FindName(list, name as given)` in LibList / DeviceList. **Found → return the failure, no disk
   access** (typical case: the library is in memory but its version is too low). [S T4]
3. Compute the **base name**: the part after the last `/`; if there is no `/`, the part after the last `:`;
   if there is neither, the name itself. If the base name differs from the name as given, **attempt with
   the base name**; success, or failure with the base name present in the list → return.
   (`OpenLibrary("LIBS:diskfont.library")` therefore opens an already loaded `diskfont.library`.)
4. Allocate a 48-byte load request, `MEMF_CLEAR` (no other flag), **through ramlib's own AllocMem
   replacement** (so a shortage triggers §6). Allocation failure → return the failure of step 1/3. The request
   records the full name as given, the calling task, the base name (as its node name) and a list of waiters.
5. **Serialisation by base name** (§4). After it, the request is the active load for that base name. If
   meanwhile another task made the name appear in the list, the request is freed and the whole procedure
   restarts at step 1 with the name as given.
6. **ROM residents first**: `FindResident(base name)`. Found → `InitResident(tag, 0)`, then the final
   attempt of step 10 and step 12 (no disk access).
7. **Directory**: `Lock("LIBS:" or "DEVS:", SHARED_LOCK)` through dos. Lock failure (no such assign) →
   step 12 without loading; the result is that of the last attempt. Otherwise `CurrentDir(lock)`, keeping the
   previous directory.
8. **`LoadSeg(name as given)`** — the full string, not the base name. Hence:
   - `"diskfont.library"` → `LIBS:diskfont.library`; `"x/y.library"` → `LIBS:x/y.library`;
   - a name with a volume or assign (`"LIBS:diskfont.library"`, `"SYS:libs/icon.library"`,
     `"DF1:x.device"`) is loaded from there, the current directory being irrelevant. [S T7, T8]
   LoadSeg failure → step 11 (`pr_Result2` keeps dos's code, 205 for a missing file). [S T9, T10]
9. **Find and start the module** (first hunk only):
   - scan the **first hunk** on even offsets for a RomTag: a word `$4AFC` followed by `rt_MatchTag` pointing
     to that word; positions too close to the end of the hunk to hold a whole RomTag are not examined. Found →
     `InitResident(tag, seglist)` (A1 = tag, D1 = seglist BPTR).
   - **No RomTag** in the first hunk → the first hunk's code is **called** as a subroutine (entry = first
     byte after the hunk link), with A6 = ExecBase, A0 = seglist BPTR, A1 = D0 = address of the hunk link.
     The code is expected to create and add the library or device itself.
   - Then `FindName(list, base name)`. **Not found → the seglist is freed** (§5) — this includes a module
     whose node name differs from the file's base name, even if it did add a node under another name
     (dangerous; see Open points).
10. **Final attempt with the base name** — this is where the **version test** happens (the original exec
    OpenLibrary compares `lib_Version >= version`). A version failure leaves the library loaded, in the list,
    with open count 0; it is not reloaded by later opens (step 2) and goes away at the next low-memory expunge.
    [S T4, T6]
11. `CurrentDir(previous)` and `UnLock(lock)` if a lock was taken.
12. **End of load** (§4): remove the request from the list of loads in progress, wake every waiter, free the
    request, return the result of the last attempt.

Not done by ramlib: no `"libs/"` or `"devs/"` subdirectory of the current directory, no search of `C:`, of
the program's own directory or of `PROGDIR:`, no requester of its own (dos may put up "Please insert volume"
for an absent assign, through the caller's `pr_WindowPtr`) [R][I].

### 3.1 Calling context [R][S]

- Every dos call of the load is made **by the calling task**, on its stack, with its message port: the
  task list during the load shows only the usual tasks, the caller being the current one (§8, T1). [S]
- **Plain Task caller**: the call reaches dos `Lock` with `ThisTask` = that Task; the result on 1.3 is a
  crash, Guru `#00000004.<address of the task>` (illegal instruction, task held), then the alert at the next
  reset. Observed with the `input.device` task asking for `mathtrans.library`. [S P1]
  A plain Task can still open a library or device **already in memory** (steps 1–3 involve no dos). [R]
- A caller under `Forbid`: dos waits for packets, so the Forbid is broken during the load ([D] exec Wait
  contract) [I].
- Stack: ramlib itself adds a few dozen bytes; LoadSeg and the module's init run on the caller's stack.
  The loads of §8 ran on a 16 KB stack; the minimum a load needs was not measured.

---

## 4. Concurrency [R]

- No global lock: loads of **different** base names may run at the same time in different tasks.
- Loads of the **same** base name are serialised with the list of loads in progress, under `Forbid`:
  - the requester looks for the base name first in LibList/DeviceList (appeared meanwhile → restart, §3
    step 5), then in the list of loads in progress;
  - if another request of that base name is in progress, the requester adds itself to that request's waiter
    list, clears its **SIGF_SINGLE** (signal bit 4) with `SetSignal(0, SIGF_SINGLE)`, `Wait(SIGF_SINGLE)`,
    and re-checks (the Wait breaks the Forbid);
  - otherwise it adds its own request (node name = base name) to the list and leaves Forbid: it is the loader.
- End of a load: under Forbid, the request is removed; after Permit, every waiter's task gets
  `Signal(task, SIGF_SINGLE)`.
- A waiter woken after a **failed** load finds neither the module nor a request: it becomes the loader and
  tries the disk again (a failure is retried once per waiter).
- The same base name for a library and a device shares the same list of loads in progress (single list).
- A task that waits on a load does so with SIGF_SINGLE; a caller using that bit for its own purpose loses it.

---

## 5. Freeing a seglist (ramlib's own unloader) [R][S]

Used by step 9 of §3, by the Close/Rem replacements and by the low-memory expunge. It does **not** call dos
`UnLoadSeg`:

- argument 0 → nothing;
- if the second longword of the first hunk's contents (8 bytes after the first hunk link) is `$0000ABCD`:
  `Alert($08000001)` (AN_BadSegList, not dead-end) and nothing is freed;
- otherwise each hunk is freed with `FreeMem(hunk − 4, size)`, the size being the longword before the link.
  A negative size longword is treated as its absolute value and that value is then also passed in A1 to
  the exec `CloseLibrary` vector (purpose unknown; dos LoadSeg never writes a negative size; **uncertain,
  no need to reproduce**).
- [S]: after a low-memory expunge of `diskfont.library` the free-memory hole is reused by the next load
  (the reloaded base sat 48 bytes lower than the first one, §8 T6).

---

## 6. AllocMem replacement — the 1.3 "memory handler" [R][S]

`AllocMem(D0 = size, D1 = requirements)`:

1. `Forbid()` for the whole call.
2. Call the previous AllocMem. Success → `Permit()`, return.
3. Failure: walk **LibList**, then **DeviceList**. For each node whose **`lib_OpenCnt` is 0** (the successor
   is read before the call, so removal is safe): call the **previous** `RemLibrary` / `RemDevice` on it. The
   original exec Rem functions call the node's **Expunge vector** (A6 = node); a non-zero return is a seglist
   and is freed (§5). Every eligible node is expunged, not only as many as the request needs.
4. Call the previous AllocMem **once more** with the same arguments.
5. Still failing and `ThisTask` is a Process (`ln_Type` 13) → `pr_Result2 = 103` (ERROR_NO_FREE_STORE).
   A plain Task gets nothing.
6. `Permit()`, return the result.

- Everything runs in the **allocating task's context**, including the Expunge vectors and the FreeMem of the
  expunged seglists. [R][S, dos-memory §1.2]
- Observed [S T5]: a failing `AllocMem($7FFFF0, 0)` from a process removed `mathffp.library` (ROM, count 0)
  and `diskfont.library` (loaded, count 0; its expunge closed dos: dos count 2 → 1), left `audio.device`
  (count 0, ROM) in the device list, left ramlib (count 1), returned 0 and set `pr_Result2 = 103`.
- Interrupt code must not call AllocMem anyway; with this patch it would also run Expunge vectors in the
  interrupt [I].
- The other exec allocators (`Allocate`, `AllocEntry`, `AllocAbs`) are not patched; `AllocEntry` calls
  AllocMem through the library vector or not — not checked (open point).

---

## 7. What our side has to match (summary for the implementation)

| Point | 1.3 behaviour |
|---|---|
| Own process | none; caller's context |
| Plain-Task caller needing a disk load | crash on 1.3 (Guru 4); a clean failure is a strict improvement, nothing can rely on the crash |
| Search | in-memory by full name, then by base name; ROM resident by base name; then `LoadSeg(full name)` with current dir `LIBS:`/`DEVS:` |
| Module start | RomTag in first hunk → InitResident(tag, seglist); otherwise call the first hunk |
| Kept only if | a node named exactly as the base name is in the list afterwards |
| Version | ordinary exec test on the final attempt; a too-old module stays loaded, unopened |
| Failure values | OpenLibrary 0; OpenDevice −1 and `io_Error` −1, `io_Device` 0; `pr_Result2` from dos (205 not found) |
| Same-name concurrency | one loader, the others wait on SIGF_SINGLE and retry |
| Unload | Close/Rem paths free the seglist an Expunge returns; exec never does |
| Low memory | AllocMem failure → expunge all count-0 libraries and devices, one retry, `pr_Result2` 103 for a process |
| ramlib's open count | 1 from its init data, never 0 |

---

## 8. Test vectors (raw observations, real ROM, Amiberry A500)

Setup: copy of the Workbench 1.3.3 disk, startup-sequence = one `echo` line, then the `Initial CLI` prompt.
The calls were made in the context of `Initial CLI` (a Process, `ln_Type` 13) stopped at the entry of exec
`Wait`; the first call (`AllocMem(16384, MEMF_PUBLIC|MEMF_CLEAR)`) ran on the CLI's own stack, the next ones
on a stack taken in that block. Library list before: exec 34.2, expansion, graphics, layers, intuition 34.3,
mathffp (count 0), romboot, dos 34.3 (count 1), ramlib 34.1 (count 1); devices keyboard, gameport, timer,
audio (count 0), input, console, trackdisk.

| # | Call | LoadSeg calls (name passed) | Result | State after |
|---|---|---|---|---|
| T1 | OpenLibrary("diskfont.library", 0) | 1, `"diskfont.library"`, ThisTask = Initial CLI; task list unchanged during the load | base (34.37) | diskfont added last in LibList; dos count 1 → 2 (diskfont opened dos); diskfont's `lib_OpenCnt` reads 0 (this diskfont does not count its opens) |
| T2 | same again | 0 | same base | — |
| T3 | CloseLibrary(base) ×2 | — | D0 = 0 both times | diskfont still listed |
| T4 | OpenLibrary("diskfont.library", 99) | 0 | 0 | no reload when the name is present with a lower version |
| T5 | AllocMem($7FFFF0, 0) | — | 0, `pr_Result2` = 103 | mathffp and diskfont removed; dos count 1; audio.device (count 0) still listed; ramlib still listed |
| T6 | OpenLibrary("diskfont.library", 99), not in memory | 1, `"diskfont.library"` | 0 | diskfont 34.37 loaded and listed (count 0) |
| T7 | AllocMem($7FFFF0, 0), then OpenLibrary("LIBS:diskfont.library", 0) | 1, `"LIBS:diskfont.library"` | base | listed as `diskfont.library` |
| T8 | OpenLibrary("SYS:libs/icon.library", 0) | 1, `"SYS:libs/icon.library"` | base (icon 34.2) | listed as `icon.library`, count 1 (dos count 3 at the end of T10) |
| T9 | OpenDevice("nosuch.device", 0, ior, 0) | 1, `"nosuch.device"` | D0 = −1 | `io_Error` = −1, `io_Device` = 0, `pr_Result2` = 205 |
| T10 | OpenLibrary("nosuch.library", 0) | 1, `"nosuch.library"` | 0 | `pr_Result2` = 205 |
| P1 | from the `input.device` task (plain Task, `ln_Type` 1, on a separate 8 KB stack): OpenLibrary("mathtrans.library", 0) | — (dos `Lock` entered, D1 = `"LIBS:"`, D2 = −2, ThisTask = input.device) | **crash**: Guru `#00000004.<input.device task address>`, machine reset by the alert | — |
| B1 | no disk, insert-disk picture | — | exec −552/−198/−414 point into the ROM | no dos, no ramlib in LibList |
| B2 | after the floppy boot | — | the seven vectors of §2.2 point into RAM inside ramlib's base, 10 bytes apart, in table order | ramlib count 1 |

### 8.1 Probe to write (implementation side): `tests/ramlib_probe.s`

A CLI executable (`vasmm68k_mot -Fhunkexe -kick1hunks`), run from a startup-sequence on a copy of the
Workbench 1.3.3 disk with **no SetPatch**. It prints one line per step through `Output()`/`Write()` (the serial
line is not reliable once dos runs), in the form `RL <step> <values in hex>`, and ends with `RL DONE`.
Steps and expected 1.3 values:

1. `RL VEC`: for exec −198, −552, −444, −414, −450, −402, −438, print whether the JMP target of the vector
   lies inside ramlib's base (`FindName(LibList, "ramlib.library")` .. base + 178). Expected: all seven
   inside. Also print ramlib's `lib_OpenCnt` (expected 1) and `lib_Version.lib_Revision` (34.1).
2. `RL T1`: `OpenLibrary("diskfont.library", 0)` → non-zero; print `lib_Version` (34) and whether
   `FindName(LibList, "diskfont.library")` equals the base. Print `FindTask(0)` before and after (same).
3. `RL T4`: CloseLibrary, then `OpenLibrary("diskfont.library", 99)` → 0, and `IoErr()` unchanged by the
   call (no disk access: optionally measure that the drive motor did not start, or that it returned within
   one frame).
4. `RL T5`: `AllocMem($7FFFF0, 0)` → 0; `IoErr()` = 103; `FindName(LibList, "diskfont.library")` = 0;
   `FindName(LibList, "mathffp.library")` = 0; ramlib still listed.
5. `RL T6`: `OpenLibrary("diskfont.library", 99)` → 0; then `FindName(LibList, "diskfont.library")` ≠ 0
   (left loaded).
6. `RL T7`: `AllocMem($7FFFF0, 0)`; `OpenLibrary("LIBS:diskfont.library", 0)` → non-zero, node name
   `diskfont.library`.
7. `RL T8`: `OpenLibrary("SYS:libs/icon.library", 0)` → non-zero, node name `icon.library`.
8. `RL T9`: `OpenDevice("nosuch.device", 0, ior, 0)` with a zeroed 48-byte IORequest → D0 = −1
   (`$FFFFFFFF`), `io_Error` = −1, `io_Device` = 0, `IoErr()` = 205.
9. `RL T10`: `OpenLibrary("nosuch.library", 0)` → 0, `IoErr()` = 205.
10. `RL CONC` (optional): two child processes made with `CreateProc` both call
    `OpenLibrary("info.library", 0)` at once and report their base; expected: the same base, one
    `info.library` node.
11. `RL TASK` (only when given the argument `TASK`, because it crashes 1.3): `AddTask` a plain Task
    (4 KB stack) that calls `OpenLibrary("mathtrans.library", 0)`. Expected on 1.3: Guru `00000004.<task>`.
    On our ROM the result is a design choice (§7).

---

## 9. Open points

1. **Name mismatch** (step 9 of §3): a file whose base name differs from the name of the node it creates
   (`LIBS:df2.library` that adds `diskfont.library`) gets its seglist freed while the node stays in the list.
   Derived from the ROM; not run (it would leave freed code reachable). An implementation may refuse more
   cleanly.
2. The "call the first hunk" path (no RomTag) and the ROM-resident path (`FindResident` by base name) were
   read in the ROM, not observed: no 1.3 disk module without a RomTag is known, and every ROM resident is
   already initialised after boot.
3. The `$0000ABCD` check and the negative-size case of §5: read in the ROM, not observed; their purpose is
   not known.
4. Same-name concurrency (§4) was read in the ROM, not observed (probe step 10).
5. ramlib's Expunge undo step (§1.2) looks defective; unreachable in 1.3.
6. Whether `AllocEntry` (and other exec code that allocates internally) goes through the patched vector
   was not checked; exec code that calls its own allocator directly would bypass the expunge.
7. diskfont.library 34.37 leaving `lib_OpenCnt` at 0 while open (T1–T3) is a property of that library, not
   of ramlib; it makes diskfont expungeable while in use.

---

## 10. Corrections to earlier pages

- `boot-sequence.md` and `dos-boot-sequence.md` called ramlib `LDDemon` (a 2.0 process name) and placed its
  initialisation on an unspecified "dedicated path": in 1.3 it is initialised by dos's init (§1.1) and has
  no process. Both pages were corrected in this session.
- `dos-memory-v34.md` §1.2 attributed the expunge-on-failure to ramlib only as a guess [D]; §6 confirms it
  [R][S].
- `coverage-v34.md` §6 lists "no process of its own (the caller must be a process)" as a gap of our ramlib:
  that **is** the 1.3 behaviour (§0, §3.1).

---

## Clean-room review

- No ROM instruction sequence, listing, pseudo-code transcription, ROM address or ROM offset appears in
  this page. The algorithm of §3–§6 is given as ordered observable effects (calls made, lists searched,
  values returned), at the level of the AutoDocs-style contract the implementation needs.
- Values cited are ABI constants (LVOs from the `.fd`, alert numbers, error codes, signal bit, structure
  fields of public includes), the RomTag fields already published in `module-map.md`, and black-box
  results of §8.
- ramlib's private base layout (where its stubs, saved pointers and lists live) is intentionally not
  given: only its size (178, already in module-map) and its initial open count matter.
- The debugger trampolines used for §8 were three-instruction scaffolds written by the analysis agent into
  emulated RAM for the session only; they are not ROM content and nothing of them is meant to be reused.
- The probe of §8.1 is a description; it is written on the implementation side from that description only.
