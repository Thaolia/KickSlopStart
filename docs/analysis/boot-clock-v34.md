# System time at boot from the floppy — KS 1.3 (V34)

> **ANALYSIS** track (dirty). Source: ROM `assets/kick34005.A500` (read only), dos segarray
> (`bcpl-runtime-v34.md` §2.4): entry 6 = file system (FS), entry 7 = "restart" process /
> validator (`rn_RestartSeg`, process name `"Validator"`). **Behavioural** specification
> only: conditions, values, effects, ABI fields. No ROM address (removed on 2026-10-29).
> Conventions: **[O]** observed in the ROM, **[D]** deduced. Global numbers = numbers in the
> GV **of the process concerned** (the validator has its own GV: its globals 186/187/203 have nothing
> to do with those of the FS or of dos bearing the same number).
> Complements `bcpl-runtime-v34.md` §8.4 (DateStamp −25, datstamp 86, compstamp 126, timerio 127,
> setdatstamp 128) and `handlers-v34.md`.

---

## 0. Short answer

It is neither dos, nor the strap, nor the FS itself: it is the **restart/validator process** (entry 7
of the segarray) that the FS launches **at every mount of a DOS volume**. At the end of a successful run, it
sets the system time (TR_SETSYSTIME, via dos global **128 setdatstamp**) to the **more recent
of two dates of the root block** — modification date of the root directory (longs 105..107) and
modification date of the disk (longs 118..120) — **only if**: the volume is in **unit 0** of the
device (DF0:), the current system time has **days = 0** (clock never set), and that time is
**strictly earlier** than the retained date. [O]

The black-box fact ("Date shows the time at which xdftool modified the image") is explained thus:
xdftool rewrote the root block dates; at the mount of DF0: the validator copied the more
recent one into the system clock still "at zero". [D, consistent with O]

> **Correction** of `bcpl-runtime-v34.md` §8.4.2 (setdatstamp, "Observed caller: only
> C:Date — the ROM does not call it"): this is **wrong**; the ROM calls it from the validator. [O]

---

## 1. Who, and when

| Step | Actor | Effect | Cert. |
|---|---|---|---|
| 1 | FS (DFx handler, entry 6) | In its main loop, on detection of a (new) disk, launches a process with the **restart** segment (name `"Validator"`) and sends it a startup packet | O |
| 2 | Validator | Opens the FS's device (same name, **same unit**, same flags as the FS), reads the root block | O |
| 3 | Validator | Checks the root block; disk type ≠ `'DOS\0'` → ends in failure | O |
| 4 | Validator | Looks up/creates the volume node (§4.2) | O |
| 5 | Validator | **Stores the most recent date** among two fields of the root block (§2) | O |
| 6 | Validator | Valid bitmap → re-reads it; invalid → full validation (or abort, §3) | O (branches) / D (sequencing after reconstruction) |
| 7 | Validator | **Successful end → conditional setting of the time (§3)**, then frees, reply to the FS, closing of the device, end of the process | O |
| 7' | Validator | End in failure → **no** time setting | O |

- The launch happens **at every insertion/mount** of a DOS disk, not only at boot (it is
  the same process that loads the bitmap in 1.3). [D: triggered by the "disk changed" state of the
  FS loop; the "valid bitmap" path runs every time]
- At boot, the mount of DF0: happens at the first DOS access to the disk (startup-sequence…), hence
  **before** `C:Date` or `SetClock` run. The validator runs as a separate process; the
  setting can therefore occur in parallel with the first commands. [D]
- dos (init, strap, `cliinit`) **does not set** the time. The FS itself never calls 128; it
  only uses DateStamp (read). [O: the only occurrences of 128 in entries 6–7 = validator]

### Validator startup packet (internal ABI FS → validator) [O]

The validator reads from the arguments of the received packet:

| Argument | Contents (FS side) | Use on the validator side |
|---|---|---|
| Arg1 | environment vector (`fssm_Environ`, BPTR DosEnvec) | block size: `de_SizeBlock` (env!1) |
| Arg2 | **unit number** (`fssm_Unit`) | unit for opening the device **and "unit 0" condition of the time setting** |
| Arg3 | device name (`fssm_Device`) | opening of the device |
| Arg4 | flag supplied by the FS (role not elucidated) | if non-zero **and** bitmap invalid → abort without validating |
| Arg5 | open flags (`fssm_Flags`) | opening of the device |

(The FS copies `fssm_Unit`, `fssm_Device`, `fssm_Environ`, `fssm_Flags` at its startup.)

---

## 2. Which date is taken

### 2.1 Fields of the OFS root block (block 880 on DD, 128 longs = 512 bytes) [O]

The FS and the validator express these positions **relative to the end of the block** (block size
in longs, `de_SizeBlock` = 128, minus a constant); for a block of 128 longs:

| Longs (from the start) | Bytes | From the end (longs) | Contents | Written by the V34 FS when… |
|---|---|---|---|---|
| 105, 106, 107 | $1A4, $1A8, $1AC | −23, −22, −21 | **modification date of the root directory** [days, minutes, ticks] (same position as the date of a file/directory header) | an entry is created/deleted/renamed in the root (§5) |
| 118, 119, 120 | $1D8, $1DC, $1E0 | −10, −9, −8 | **modification date of the disk** [days, minutes, ticks] | the root block is rewritten to toggle the bitmap flag (§5) |
| 121, 122, 123 | $1E4, $1E8, $1EC | −7, −6, −5 | **creation date of the volume** [days, minutes, ticks] = identity of the volume | never by the FS in normal operation (formatting/Relabel out of scope) |

Reminder of the datestamp format: days since 1-Jan-1978, minutes since midnight (0..1439), ticks
of 1/50 s within the minute (0..2999).

### 2.2 Selection rule [O]

- The validator keeps a "**most recent seen**" datestamp, initialised to **[0, 0, 0]**.
- It compares it successively with longs **105..107**, then **118..120** of the root block: each
  time the candidate is **strictly more recent** (`compstamp` comparison: days, then
  minutes, then ticks, signed), it replaces the "most recent seen" (copy of the 3 longs).
- Result: **max(root date 105..107, disk date 118..120)**, or [0,0,0] if both are null.
- The **creation** date (121..123) does **not** enter this computation.
- No other block (file headers, subdirectories) is consulted for this maximum.
- The values are not validated (ranges not checked). [O: no range test]

---

## 3. Setting condition [O]

At the **successful** end of the validator (bitmap read or rebuilt without error), it:

1. reads the current system time by **datstamp** (dos global 86 → DateStamp, which incidentally refreshes
   `rn_Time`);
2. **sets the time** if and only if the following three conditions are true:

| Condition | Detail |
|---|---|
| **Unit 0** | the received unit number (Arg2 = `fssm_Unit`) is 0 → DF0: in practice; DF1:…DF3: never set the time |
| **Clock "not set"** | **days** of the current time = **0** (we are still on 1-Jan-1978); the current minutes/ticks do not count for this test |
| **Older** | `compstamp(current, most_recent_seen) < 0`: the current time is strictly earlier than the maximum of §2.2 |

3. the setting = **setdatstamp(most_recent_seen)** (dos global 128); result ignored.

Consequences:

- **No setting** if the disk is not DOS, if validation fails ("Error validating
  disk"…), if the bitmap is invalid and the FS has set the Arg4 flag (abort), or if
  both dates of the root block are null (the maximum [0,0,0] is never later). [O]
- **Not a "first mount" matter**: the test is redone at every mount on unit 0;
  it stops succeeding as soon as the system time has days ≥ 1, i.e. as soon as it has been set
  once (by this mechanism, `Date`, `SetClock load`…) **or** after 24 h of operation from a
  system time that started from zero. [O for the test, D for the initial system time = 0]
- Never goes backwards: a current time more recent than the disk is not modified. [O]
- The initial system time of timer.device at reset is **0 s** (1-Jan-1978 00:00:00), hence
  "days = 0" as long as nothing has set it. [D: consistent with the black-box `<unset>`; not
  analysed in timer.device here]

---

## 4. Conversion and effects

### 4.1 Conversion to TR_SETSYSTIME [O, cf. bcpl-runtime §8.4.2]

setdatstamp converts the datestamp [D, M, T]:

| timer.device field | Value |
|---|---|
| `tv_secs` (seconds since 1-Jan-1978 00:00) | D × 86400 + M × 60 + T / 50 (integer division) |
| `tv_micro` | (T mod 50) × 20000 |

Signed 32-bit arithmetic, without validation. **TR_SETSYSTIME (11)** request on `timer.device`
unit 0 (UNIT_MICROHZ), under Forbid, device opened and closed within the call.

### 4.2 Observable effects [O]

| Object | Effect of the setting |
|---|---|
| System time (timer.device) | := retained date; it then keeps advancing normally |
| `rn_Time` (RootNode +$08/+$0C/+$10) | refreshed **immediately** by setdatstamp's internal re-read (DateStamp) → equals the retained date (to within a few ticks) |
| `dl_VolumeDate` of the volume node | **unchanged** by the setting. It equals the **creation date** of the root block (longs **121..123**): the validator looks in the DOS list for a **volume** node (dn_Type 2) with the **same name** (BSTR of the root block, longs 108.., length 1..30) **and** a date **equal** (compstamp = 0) to 121..123; failing that it creates the node (makedevnode) and copies 121..123 into `dl_VolumeDate` (`dl_Lock` := 0, dl_Type := 2, `dl_LockList` := 0); in both cases the node is attached to the FS's port |
| Root block on disk | **not written** by this mechanism |

### 4.3 Periodic refresh of rn_Time (unit 0) [O call / D period]

Independently of the setting: the FS whose unit is **0** calls **DateStamp** at each return of
its periodic timer request, just before re-arming it (request re-armed with tv_secs = 1,
tv_micro = 0). Effect: `rn_Time` (the cache) follows the system time about every second as long as the
DF0: handler runs. The FSes of the other units do not do this.

---

## 5. Conversely: dates written by the FS during a modification [O]

All these dates are obtained by **datstamp** (global 86 → DateStamp) = **current system
time**, without any other source.

| Event | Block written | Dated field (longs, block 128) | Other effect |
|---|---|---|---|
| Creation of an object (file/directory) | new header | 105..107 | — |
| Update of the header of a written file (size) — [D] on close | file header | 105..107 | archive bit (protection, long 80, bit 4) reset to 0 |
| Addition / removal of an entry in a directory — [D] creation, deletion, renaming (for a rename between two directories, **both** parents are dated [O]) | header **of the parent directory** (= root block if the object is at the root) | 105..107 | archive bit of the parent reset to 0 (no visible effect for the root) |
| First modification of a "clean" disk (switch to the modified state) | **root block** | **118..120** | bitmap flag (long 78) := 0 (invalid) |
| Deferred write of the bitmap (end of the burst of modifications) | **root block** | **118..120** | bitmap flag (long 78) := −1 (valid), bitmap page pointers (longs 79..) rewritten |

- The **volume creation** date (121..123) is never touched by these operations.
- Corollary: a disk modified under a set clock carries in 118..120 (and in 105..107 if the
  root changed) the time of that modification; put later into DF0: of a machine with an
  unset clock, it will "give" it that time. This is 1.3's "last modified
  disk" clock mechanism. [D]
- If the system time is not set, the dates written are close to 1-Jan-1978 (days = 0);
  they can then never advance another machine beyond days = 0. [D]

---

## 6. Test vectors (input → observable output)

Notation: R105 = longs 105..107, R118 = longs 118..120, R121 = longs 121..123 of the root block;
"unset clock" = no RTC loaded, no SetClock/Date before the mount. "Date shows
X" = output of `C:Date` without argument shortly after the mount (X + elapsed time).

| # | Input | Expected output |
|---|---|---|
| T1 | Unset clock; DF0: R105 = D1, R118 = D2, D2 > D1 | Date shows **D2**; `rn_Time` ≈ D2 |
| T2 | Same, D1 > D2 | Date shows **D1** |
| T3 | Unset clock; R105 = R118 = [0,0,0] | Date shows `<unset>` (time unchanged) |
| T4 | Unset clock; only R118 non-zero (R105 = 0) | Date shows R118 |
| T5 | Unset clock; R121 = recent D, R105 = R118 = 0 | **unchanged** (the creation date is not used) |
| T6 | Unset clock; disk dated D inserted **only in DF1:** (DF0: empty or non-DOS) | **unchanged** (unit ≠ 0) |
| T7 | Unset clock; non-DOS disk in DF0: | unchanged |
| T8 | Clock already set to C (days ≥ 1), DF0: disk dated D > C | **unchanged** (C, which advances) |
| T9 | Clock already set to C, disk dated D < C | unchanged |
| T10 | Boot on disk A (R118 = DA) then insertion into DF0: of a disk B with R118 = DB > DA | stays on DA (+ elapsed): days ≥ 1 after the first setting |
| T11 | Unset clock, D on the disk with days = 0 (e.g. 00:05) while the current time is 00:10 | unchanged (current not earlier) |
| T12 | Unset clock, D = 22-Oct-26 10:22:49; then `SetClock load` (RTC at C) | Date shows C (SetClock overwrites afterwards) |
| T13 | Clock set to T; create a file at the root of DF0: then wait for the bitmap write | R105 ≈ T (creation), R118 ≈ T (two rewrites of the root, invalid then valid); R121 unchanged; long 78 = −1 at the end |
| T14 | Clock set to T; write a file in a subdirectory | R105 **unchanged** (only the subdirectory header is dated), R118 ≈ T |
| T15 | After T1: `Info`/list of volumes | volume date (dl_VolumeDate) = **R121**, not the setting date |

---

## 7. Clean-room review

Fully re-read: this document contains **no 68000 instruction sequence** copied or
paraphrased, no disassembly excerpt, no opcode, nor line-by-line pseudo-code. It describes
**observable conditions, values and effects**, the order of the visible effects, and
ABI/interoperability elements (OFS root block fields, timer.device fields, RootNode, DeviceList,
startup packet arguments). No ROM address is cited. The ROM was
neither modified nor copied (temporary disassembly in the session scratch directory).
- [x] **Correction of 2026-10-29**: removed the 5 ROM address landmarks (call of setdatstamp
  by the validator, restart segment, copy of the FSSM); behaviour unchanged.
