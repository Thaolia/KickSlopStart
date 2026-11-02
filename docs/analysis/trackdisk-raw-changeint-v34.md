# trackdisk-raw-changeint-v34.md — trackdisk.device V34.1: raw I/O, drive type, seek, change interrupts, control commands

> **ANALYSIS track ("dirty").** Behavioural spec of `trackdisk 34.1 (18 Aug 1987)` (Kickstart 1.3, 34.5).
> Behaviour and ABI only: commands, `io_` fields, error codes, order of observable effects, private structure
> offsets (layout = ABI), hardware registers. No instruction listing, no ROM address.
>
> **Evidence levels.** **[O]** read unambiguously in the ROM (constant, test, order of accesses). **[P]** observed
> at run time on the real ROM under Amiberry (memory of the running system read through the GDB stub, floppy
> ejected/inserted through IPC; session `build/amiberry/analysis/tdres_an/`, 2026-11-02). **[D]** deduced.
> **[S]** assumed / not verified.
>
> Complements, without repeating: `trackdisk-official-timing.md` (motor, step/settle delays, DMA read sequence),
> `trackdisk-write-v34.md` (write path, track buffer, §3.2 RAWWRITE summary, §5.1 dispatch table),
> `disk-change-v34.md` (what the ROM file system does with TD_REMOVE / TD_CHANGESTATE).

---

## 0. Summary

| No. | Command | Path | Effect (V34) |
|---:|---|---|---|
| 0 | `CMD_INVALID` | unit task | `IOERR_NOCMD` (−3) |
| 1, 6, 7, 8 | `CMD_RESET`, `CMD_STOP`, `CMD_START`, `CMD_FLUSH` | **immediate** | `IOERR_NOCMD` (−3), no other effect |
| 10 | `TD_SEEK` | unit task | head to the track of `io_Offset` (bytes); motor untouched; seek errors **not** reported |
| 12 | `TD_REMOVE` | unit task | sets the unit's single "remove" Interrupt = `io_Data` (NULL clears it); replied at once |
| 16 | `TD_RAWREAD` | unit task | motor on, seek to track `io_Offset`, DMA `io_Length` raw MFM bytes into `io_Data` |
| 17 | `TD_RAWWRITE` | unit task | same, writing (protection, reset guard, precomp, 2 ms drain) |
| 18 | `TD_GETDRIVETYPE` | **immediate** | `io_Actual` = 1 (`DRIVE3_5`) or 2 (`DRIVE5_25`) |
| 19 | `TD_GETNUMTRACKS` | **immediate** | `io_Actual` = 160 or 80 |
| 20 | `TD_ADDCHANGEINT` | unit task | request queued on the unit's change list, **never replied** while installed |
| 21 | `TD_REMCHANGEINT` | unit task | unlinks the request from that list, replies it |
| ≥ 22 | — | caller | `IOERR_NOCMD` |

`TD_ADDCHANGEINT`/`TD_REMCHANGEINT` **exist and work in V34** (they are not V36 additions). This settles
inconsistency 3 of `coverage-v34.md` §5 by ROM reading; a black-box probe was not run for them. [O]

---

## 1. Dispatch rules that matter for these commands [O]

1. `BeginIO` clears `io_Error`, then dispatches on the **low byte** of `io_Command` only. The high byte is ignored
   for dispatch: bit 15 selects the ETD variant (see 3), any other high bit is silently ignored
   (`$0110` behaves as 16). Low byte ≥ 22 → `IOERR_NOCMD` in the caller's context.
2. **Immediate** commands (bit set in the mask `$000C61C2`: 1, 6, 7, 8, 13, 14, 18, 19) run in the caller's
   context: the driver sets `io_Flags` bit 7 (private), sets `ln_Type` = `NT_MESSAGE`, and **keeps `IOF_QUICK` as
   the caller set it**. All other commands: `io_Flags` &= `$7E` (clears `IOF_QUICK` and bit 7), then `PutMsg` to
   the unit (the unit structure is itself the request MsgPort, signal bit 9) and the unit task (priority 5, named
   `trackdisk.device`) executes them in FIFO order.
3. In the unit task, before each queued command: change polling (§6.2); then if `io_Command` bit 15 is set, the
   request is an ETD one: if the unit's change counter > `iotd_Count` (offset `+$30` of the IOExtTD) → `io_Error`
   = 29 (`TDERR_DiskChanged`) and the command is not executed. This check applies to **every** queued command with
   bit 15 set, raw ones included; immediate commands never check it. After the command: change polling again.
4. Termination: if `IOF_QUICK` is still set → nothing (no `ReplyMsg`); otherwise `ReplyMsg`. Hence: an immediate
   command sent with `DoIO` completes synchronously without a reply; with `SendIO` (QUICK clear) it is replied
   from the caller's own context before `BeginIO` returns. Queued commands are always replied.
5. **`AbortIO` is a no-op** that returns 0 (it does not remove, mark or reply anything). [O]
6. `Expunge` returns 0 and never expunges; `CloseDevice` returns 0 (see §7 for the unit lifetime).

---

## 2. Units: internal vs external drives, drive type [O]

### 2.1 OpenDevice(unit, flags)

| Check | Result |
|---|---|
| unit ≥ 4 | `io_Error` = 32 (`TDERR_BadUnitNum`) |
| unit not yet created: `GetUnitID(unit)` (disk.resource) = `$00000000` | accepted, type 3.5" |
| ID = `$55555555` | accepted **only if** `flags` bit 0 (`TDF_ALLOW_NON_3_5`) is set, type 5.25"; otherwise 33 |
| any other ID (incl. `$FFFFFFFF` = no drive) | 33 (`TDERR_BadDriveType`) |
| `AllocUnit(unit)` fails (unit owned by another driver) | 34 (`TDERR_DriveInUse`) |
| memory (unit 412 bytes, task stack 512 bytes, MFM buffer 16,388 bytes CHIP; one `AllocEntry`) | 31 (`TDERR_NoMem`), after `FreeUnit` |
| success | `io_Unit` = unit structure; device `lib_OpenCnt`+1; unit open count (`+$24`, word)+1 |

On failure `io_Device` and `io_Unit` are both set to −1. Once a unit exists, later opens **do not re-check** the
drive type nor `flags`. Unit 0 is the internal drive: disk.resource never reads its ID and always reports
`$00000000`, so unit 0 always opens as 3.5". Units 1–3 are external; their ID was read **once** at cold start by
disk.resource (`resources-v34.md` §2.5). A drive plugged in later is invisible.

### 2.2 Per-type parameters (copied into the unit at creation)

| Field (unit offset) | 3.5" (`ID $00000000`) | 5.25" (`ID $55555555`) |
|---|---|---|
| precomp threshold 1 / 2 / 3 (`+$26/+$28/+$2A`, words) | 80 / `$FFFF` / `$FFFF` | 40 / `$FFFF` / `$FFFF` |
| step delay µs (`+$2C`, long) | 3000 | 6000 |
| settle delay µs (`+$30`, long) | 15000 | 15000 |
| retry count (`+$34`, byte) [D: role] | 10 | 10 |
| **drive type** (`+$35`, byte) | **1** (`DRIVE3_5`) | **2** (`DRIVE5_25`) |
| **number of tracks** (`+$36`, word) | **160** | **80** |
| disk size in bytes (`+$38`, long) | 901,120 | 450,560 |

The precomp thresholds are **track numbers** (cyl × 2 + side) compared with the head's current track using
**strictly greater than**: a write on track p gets the 140 ns level only when p > threshold 1 (the higher levels
when p > threshold 2 / 3, unreachable with `$FFFF`). For a 3.5" unit, tracks 0–80 (up to and including cyl 40
side 0) are written **without** precompensation and the **first precompensated track is 81** (cyl 40 side 1);
for a 5.25" unit (same comparison, threshold 40; not probed separately), tracks 0–40 without, first
precompensated track 41. Full rule and ADKCON values:
`trackdisk-write-v34.md` §3.1. [O] (probe: track 80 → no precomp, track 81 → 140 ns)

11 sectors per track in both cases (byte offsets are always converted with 512-byte sectors and 11 sectors per
track). [O] Values for unit 0 confirmed at run time: type 1, 160 tracks, 901,120, 3000, 15000, 10. [P]

### 2.3 `TD_GETDRIVETYPE` (18) and `TD_GETNUMTRACKS` (19)

Immediate. `io_Actual` = byte `+$35` (1 or 2), resp. word `+$36` (160 or 80), zero-extended. No hardware access,
no motor, `io_Error` = 0. The type therefore reflects the drive ID read at boot, never a live measurement. [O]

---

## 3. `TD_SEEK` (10) [O]

- **Input**: `io_Offset` = **byte offset** on the disk (not a track number). It must be a multiple of 512 and
  ≤ the disk size (`+$38`); otherwise `io_Error` = −4 (`IOERR_BADLENGTH`). Track = (`io_Offset` / 512) / 11, i.e.
  `cylinder × 2 + side`. The bound is **inclusive**: `io_Offset` = 901,120 is accepted and seeks to track 160
  (cylinder 80, side 0), one cylinder beyond the last data cylinder.
- **Motor**: not touched (the head steps with the motor off if it is off).
- **Effect**: the normal seek of `trackdisk-official-timing.md` §2.3: if the current position is unknown
  (`+$4C` = `$FFFF`), a recalibration first (§3.1); same track → nothing, no delay; side change only → `/SIDE`
  changed, no settle; otherwise |Δcylinder| steps (step delay each) then the settle delay.
- **Result**: `io_Error` = 0 **even if the recalibration fails** (the seek error 30 is discarded by this command;
  only `TD_RAWREAD`/`TD_RAWWRITE` return it). `io_Actual` untouched.

### 3.1 Recalibration details (supplement to `trackdisk-official-timing.md` §2.2)

1. Selects side 0 (`/SIDE` high) and direction **inward** (`/DIR` low).
2. While `/TRACK0` is asserted, steps inward, at most `tracks/4 + 1` steps (41 for 3.5"), to leave track 0.
3. Direction outward (`/DIR` high), position := 0, then steps until `/TRACK0` is asserted, at most
   `tracks/2 + 21` steps (101 for 3.5").
4. `/TRACK0` still not asserted → error 30 (`TDERR_SeekError`); otherwise settle delay and success.

The position field `+$4C` holds the track (`cyl × 2 + side`); `$FFFF` = unknown. It is set to `$FFFF` at unit
creation, on every disk insertion (§6.2) and at the last close.

---

## 4. `TD_RAWREAD` (16) and `TD_RAWWRITE` (17)

### 4.1 Order of operations [O]

1. **Motor on** (500 ms blind delay if it was off; left on afterwards).
2. `io_Offset` = **track number** (0 … tracks−1, i.e. < 160 for 3.5", < 80 for 5.25"); out of range → −4. The
   motor has already been switched on.
3. Seek to that track; a seek error (30) ends the command with that code.
4. `io_Length` = byte count, must be **< 32,768** (unsigned) → otherwise −4. (Checked after the seek.)
5. DMA transfer (§4.2), result in `io_Error`; reply.

`io_Actual` is **never written** by either command. `io_Data` must be in **CHIP RAM** and word-aligned; the driver
does not check it. The unit's track buffer is neither used nor invalidated: a `TD_RAWWRITE` over the cached track
leaves the cache stale, and the raw commands never flush a dirty buffer. [O]

### 4.2 DMA transfer

Same skeleton as the normal read/write (`trackdisk-official-timing.md` §3.2, `trackdisk-write-v34.md` §3) with
the user's buffer as DSKPT:

| Step | Read | Write |
|---|---|---|
| acquire channel | disk.resource `GetUnit` (waiting if busy); ADKCON ← `$0600` then `$9100` only if the previous owner was another unit | same |
| select, DSKLEN ← `$4000`, 1 ms, DSKPT ← `io_Data`, INTREQ ← `$1002`, INTENA ← `$8002` | yes | yes |
| `/CHNG` low | 29 | 29 |
| `/WPRO` low | — | 28 |
| keyboard reset announced | — | 35 (else "write in progress" flag set) |
| precompensation (ADKCON ← `$6000`, then level by current track) | — | yes |
| DSKLEN value | `$8000 | (io_Length >> 1)` | `$C000 | (io_Length >> 1)` |
| arm | written twice, now — or at the index pulse (§4.3) | same |
| wait | DSKBLK → message on the unit's DMA port (signal bit 10), no timeout | same |
| teardown | INTENA ← `$0002`, DSKLEN ← `$4000` | INTENA ← `$0002`, **2 ms**, DSKLEN ← `$4000`; reset-guard end (`KBD_RESETHANDLERDONE` if a reset came) |
| `/CHNG` low again | 29 | 29 |
| release | `GiveUnit` | `GiveUnit` |

- **Length**: the word count is `io_Length / 2` rounded down; with an odd length the last byte is not
  transferred. Maximum 16,383 words = 32,766 bytes. [O]
- **`io_Length` < 2** gives a DSKLEN word count of 0. Whether Paula then raises DSKBLK is not established; the
  driver has no timeout, so the request may never complete. [S] Avoid it.
- **Disk-absent flag** of the unit is **not** consulted (only the live `/CHNG` line). [O]

### 4.3 `IOTDF_INDEXSYNC` (`io_Flags` bit 4) [O]

- Bit 4 set: instead of arming DSKLEN immediately, the driver installs a handler in its DiscResourceUnit
  `dru_Index` (is_Data → a small context holding the DSKLEN value), then on ciab.resource: `SetICR($10)`
  (drops a stale FLG flag), then `AbleICR($90)` (enables FLG). On the next **index pulse** (CIA-B FLG → level 6 →
  ciab.resource → disk.resource index handler → current owner's `dru_Index`), the handler writes DSKLEN twice
  and disables FLG (`AbleICR($10)`).
- The DMA therefore starts a short, interrupt-latency-dependent delay **after** the index pulse (tens of µs, i.e.
  a few to a few dozen MFM bits). Not measured. [D]
- No index pulse (no disk turning) → the request never completes. [D]
- **Bit 5 (`IOTDF_WORDSYNC`) is ignored in V34**: `io_Flags` bit 4 is the only flag bit tested by the raw
  commands. [O]

### 4.4 What lands in the buffer (read) [O/D]

- Raw MFM words exactly as the DMA receives them: **DSKSYNC is never written and WORDSYNC is never set by
  trackdisk**, so the data starts at an arbitrary rotational position (without INDEXSYNC) and at an **arbitrary
  bit phase**: the `$4489` marks may appear at any bit shift and must be found in software. [O]
- Caveat: ADKCON is reset (WORDSYNC cleared, MFMPREC + FAST set) only when the disk channel changes owner. If an
  application set WORDSYNC itself and this unit was the last owner, the setting survives and the read then
  waits for whatever DSKSYNC holds. [O]
- With FAST set (2 µs MFM bit cell), one word = 32 µs; at 300 rpm one revolution ≈ 200 ms ≈ 6,250 words ≈
  12.5 KB; the 32,766-byte maximum ≈ 2.6 revolutions ≈ 0.52 s of DMA. [D]
- The buffer is not pre-filled by the driver (unlike its own track buffer, pre-filled with `$AAAAAAAA`). [O]

---

## 5. `TD_REMOVE` (12), `TD_ADDCHANGEINT` (20), `TD_REMCHANGEINT` (21) [O]

### 5.1 `TD_REMOVE`

Queued. Stores `io_Data` (pointer to a struct Interrupt, or NULL) into the unit's single "remove interrupt" slot
(`+$12A`), replacing any previous one without notice. Replied at once, `io_Error` = 0, `io_Actual` untouched. Only
one remove interrupt per unit; NULL disables it. The ROM file system uses it (`disk-change-v34.md` §2.1); at run
time unit 0's slot is non-NULL after boot. [P]

### 5.2 `TD_ADDCHANGEINT`

- Queued (must go through the unit task). The IORequest itself is appended with `AddTail` to the unit's change
  list (`+$18E`, a struct List, `lh_Type` 0); its `ln_Succ`/`ln_Pred` are used as the link. **No reply**: the
  request stays in use (`ln_Type` = `NT_MESSAGE` as left by `PutMsg`) as long as it is installed.
- `io_Data` = pointer to the caller's struct Interrupt. `io_Length`, `io_Offset`, `io_Flags` are not examined.
  There is no duplicate check: adding the same request twice corrupts the list.
- **Must be sent with `SendIO`** (or `BeginIO` with `IOF_QUICK` clear). `DoIO` blocks forever in `WaitIO`, since
  the request is not replied. `AbortIO` cannot cancel it (§1.5).

### 5.3 `TD_REMCHANGEINT`

- Queued. `Remove()` of the request passed **from whatever list it is on** (no search, no check that it is in the
  change list), then replied with `io_Error` = 0. The caller must therefore pass **the same IORequest** that was
  used for `TD_ADDCHANGEINT`; passing a request that is not linked corrupts memory.
- Since the request is replied by this command, a `WaitIO` on it then returns; that reply is the only completion
  an installed change interrupt ever gets.

### 5.4 When the interrupts are `Cause()`d

At each **change detected by the unit's polling** (§6.2), in the unit task's context:
1. `Cause(remove interrupt)` if the slot is non-NULL;
2. then `Cause(io_Data)` of every request of the change list, in list (installation) order.

Both on **removal** and on **insertion** (and twice in the same poll for a swap seen as removal + immediate
re-insertion). The change counter (`TD_CHANGENUM`) is incremented **before** the corresponding `Cause()`s. The
code runs later at software-interrupt level with A1 = `is_Data` (standard exec `Cause()` semantics: nothing
happens if the Interrupt is already pending as `NT_SOFTINT`; `ln_Pri` must be one of −32, −16, 0, 16, 32).
The handler cannot know whether it was an ejection or an insertion; it should query `TD_CHANGESTATE`. [O]

---

## 6. Change detection (what drives §5) [O, P]

### 6.1 Unit state

| Unit offset | Meaning |
|---|---|
| `+$40` bit 1 | disk absent (initialised to **1 = absent** when the unit is created) |
| `+$40` bit 4 | write-protected (sampled from `/WPRO` at insertion) |
| `+$126` (long) | change counter returned by `TD_CHANGENUM` (starts at 0) |
| `+$12A` | remove interrupt (`TD_REMOVE`) |
| `+$18E` | change-interrupt list (`TD_ADDCHANGEINT`) |

`TD_CHANGESTATE` (immediate) returns the **cached** absent bit, no hardware access: `io_Actual` = 0 present,
`$FF` absent. [O]

### 6.2 Polling

Run by the unit task: when the unit task starts (at unit creation), at each tick of its VBLANK timer request,
and before and after every queued command. One poll:

1. Acquire the channel, select the drive, read `/CHNG`, release.
2. `/CHNG` high and absent bit clear → nothing.
3. `/CHNG` low and absent bit clear (**removal**): absent bit := 1, counter +1, seek to **track 6** (cylinder 3),
   motor off, `Cause()`s (§5.4); then continue as in 4.
4. Absent bit set: toggle `/DIR`, issue one step pulse, step delay; then re-select and read `/CHNG`:
   still low → still absent, end. High (**insertion**): counter +1, sample `/WPRO`, position := unknown
   (`$FFFF`, next seek recalibrates), absent bit := 0, `Cause()`s.
5. `/CHNG` high while the absent bit is set: goes directly to the verification of step 4 (no step pulse).

Consequences:
- With no disk, each poll steps the head one cylinder alternately in and out around cylinder 3: the familiar
  periodic click of an empty Amiga drive. [O]
- Re-arm period of the VBLANK request: 0.5 s while a disk is present, about 2.5 s while absent (`timer-v34.md`
  §7). Removal is thus seen within ~0.5 s of the next poll, insertion within ~2.5 s. [O + timer-v34]
- After cold boot with a disk in the drive, the counter is **1**, not 2: the unit starts "absent", so the first
  poll only takes the insertion branch. [O] Measured: unit 0 counter = 1 after a Workbench 1.3.3 boot; one write
  to the counter during boot, from the insertion branch; then eject → 2 (absent bit set), insert → 3 (absent bit
  clear). [P] A boot without a disk leaves the counter at 0 and the unit absent.
- Between `OpenDevice` and the unit task's first poll (the task has priority 5), `TD_CHANGESTATE` reports
  "absent" even with a disk inserted. [D]

---

## 7. Unit lifetime and pending change interrupts [O]

- `CloseDevice` decrements the unit open count; reaching 0 only sets a private "last close" flag.
- The unit task acts on it when it next receives any message on its port (in practice the next VBLANK poll tick,
  ≤ 0.5–2.5 s): it flushes a dirty track buffer (error lost), invalidates the buffer, forgets the head position,
  switches the motor off; then under `Forbid`, **if the open count is still 0**: `FreeUnit` (disk.resource),
  clears the device's unit slot and removes itself (`RemTask`), which frees the unit structure, its stack and its
  MFM buffer.
- Consequences: requests still on the change list are **never replied** and their list disappears (a later
  `TD_REMCHANGEINT` on them would unlink through freed memory); the remove interrupt is forgotten; a later
  `OpenDevice` recreates the unit with counter 0 and the "absent" initial state. The ROM file system keeps its
  units open forever, so this never happens to DF0:–DF3: in normal use.

---

## 8. `CMD_RESET` (1), `CMD_STOP` (6), `CMD_START` (7), `CMD_FLUSH` (8), `CMD_INVALID` (0) [O]

- 1, 6, 7, 8 share the "no such command" routine and are **immediate**: `io_Error` = −3 (`IOERR_NOCMD`), no
  effect on the queue, the motor, the buffer or the unit state. With `DoIO` they complete without a reply.
- There is **no stopped state**: `CMD_STOP` does not suspend the unit task, `CMD_START` resumes nothing,
  `CMD_FLUSH` does not abort queued requests, `CMD_RESET` resets nothing.
- `CMD_INVALID` (0) is not immediate: it goes through the unit task and is replied with −3.

---

## 9. Error codes for the commands of this page

| Code | Name | Where |
|---:|---|---|
| −3 | `IOERR_NOCMD` | 0, 1, 6, 7, 8, ≥ 22 |
| −4 | `IOERR_BADLENGTH` | SEEK (offset not ×512 or > disk size); RAW (track ≥ tracks, length ≥ 32,768) |
| 28 | `TDERR_WriteProt` | RAWWRITE, `/WPRO` low |
| 29 | `TDERR_DiskChanged` | RAW, `/CHNG` low before or after the DMA; any ETD command with counter > `iotd_Count` |
| 30 | `TDERR_SeekError` | RAW (recalibration failed); **not** returned by `TD_SEEK` |
| 31 / 32 / 33 / 34 | `NoMem` / `BadUnitNum` / `BadDriveType` / `DriveInUse` | OpenDevice |
| 35 | `TDERR_PostReset` | RAWWRITE after a keyboard reset announcement |

---

## 10. Private structure offsets used above (ABI layout) [O, P]

Device base (positive size `$A8`): `+$22` flags (bit 4 keyboard reset announced, bit 5 write in progress),
`+$24` unit pointers [4], `+$34` ExecBase, `+$38` GfxBase, `+$3C` disk.resource, `+$5E` ciab.resource,
`+$62` reset-handler Interrupt, `+$78` keyboard IOStdReq.

Unit (412 bytes): `+$00` struct Unit (request MsgPort, signal bit 9; `+$22` unit flags; `+$24` open count),
`+$26…+$3B` per-type parameters (§2.2), `+$3C` drive ID, `+$40` state bits, `+$41` CIA-B PRB shadow
(`/SEL` bit = 3 + unit), `+$43` unit number, `+$4C` head position, `+$52` MFM buffer, `+$5E` timer request
(delays), `+$86` timer request (VBLANK poll), `+$AE` DMA/reply MsgPort (signal bit 10), `+$D0` struct
DiscResourceUnit (its `mn_ReplyPort` = `+$AE`), `+$126` change counter, `+$12A` remove interrupt, `+$12E` unit
Task, `+$18E` change list.

---

## 11. Test vectors

| Action (real ROM) | Expected |
|---|---|
| `TD_GETDRIVETYPE` / `TD_GETNUMTRACKS` on unit 0 | 1 / 160, immediate [O; fields P] |
| `CMD_STOP`, `CMD_START`, `CMD_FLUSH`, `CMD_RESET` with `DoIO` | −3, no reply, nothing changes [O] |
| `TD_SEEK` `io_Offset` = 5632×10 | head on track 10, `io_Error` 0, motor unchanged [O] |
| `TD_SEEK` `io_Offset` = 100 | −4 [O] |
| `TD_RAWREAD` track 160 | −4, motor left on [O] |
| `TD_RAWREAD` length 32,768 | −4 after the seek [O] |
| `TD_RAWREAD` track 0, 12,800 bytes, INDEXSYNC | buffer of raw MFM, first words just after index, `io_Actual` unchanged [O/D] |
| `TD_ADDCHANGEINT` with `SendIO`, eject, insert | interrupt runs twice; counter +2; request still pending until `TD_REMCHANGEINT` [O; counter P] |
| counter after cold boot with disk | 1 [P] |

---

## 12. Open points

- DSKLEN with a word count of 0 (`io_Length` < 2): completion behaviour on real Paula not established.
- INDEXSYNC start latency after the index pulse: not measured.
- `TD_ADDCHANGEINT` was established by ROM reading only; a probe (SendIO the command on unit 0 with an
  Interrupt whose code increments a long, then eject/insert through the emulator, then `TD_REMCHANGEINT` and
  check the reply) would confirm it end to end.
- Exact VBLANK poll period with a disk present (depends on what timer.device leaves in `tv_secs`, see
  `timer-v34.md` §7).

## Clean-room review

- [x] No ROM addresses; no instruction listing or pseudo-code transcription; routines described by effects.
- [x] Kept: command numbers, `io_` fields, error codes, register values, unit/device field offsets (ABI layout),
  per-type parameter values (constants), run-time observations.
