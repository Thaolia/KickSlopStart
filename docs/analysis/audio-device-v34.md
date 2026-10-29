# audio.device 34.1 — behavioural spec

> **ANALYSIS** track ("dirty"). Sources: ROM `assets/kick34005.A500` (read only, radare2, base
> `$FC0000`; disassembly notes outside the repository) and black-box probe `tests/audio_probe.s` (harness
> `tests/audio_probe.sh`) run on the **real ROM** under FS-UAE (PAL A500, 512 KB chip + 512 KB
> slow, OpenAL forced onto its `null` driver).
> This document describes **behaviours**, **values**, **orders of operations** and
> **ABI layouts**. It contains no ROM instruction sequence nor routine address.
> Spec no. 12 of `coverage-v34.md` (module 13). Known uses: `octamed-v34.md` §2.5 (allocation of the
> 4 channels), `monkey-startup.md` (vector `$70` overwritten directly, audio.device no longer sees anything).
>
> **Levels of proof**: **[O]** observed by the probe on the real ROM · **[D]** deduced from reading
> the ROM code (behaviour, not code) · **[S]** reasonable assumption, not verified.
>
> Time unit of the measurements: **the line** (64 µs PAL; probe clock = VERTB frames × 313 + current
> line). Reference sample: 1000 bytes, period 400 ⇒ one pass = 400,000 Paula ticks
> ≈ **1761 lines** (measured on Paula alone, §8.1).

## 0. Summary for the implementer

- Resident module `audio.device`, version 34, revision 1, ID string `"audio 34.1 (18 Aug 1987)\r\n"`,
  RTF_AUTOINIT|RTF_COLDSTART, priority 40, base of **634 bytes** (dataSize), **6 standard vectors**
  (Open, Close, Expunge, reserved, BeginIO, AbortIO). No units: the unit number and the OpenDevice
  flags are **ignored**. [D]
- **Allocation** = choice of a channel combination in `ioa_Data[0..ioa_Length-1]` (bytes, 4-bit
  masks) according to the **priority `ln_Pri`** of the request; a free channel is always preferred, a busy
  channel is only stolen if its **precedence is strictly lower** than `ln_Pri`; among the
  possible combinations, the one that does the **least damage** (lowest stolen precedence level)
  then the **first in the array**. Result: `io_Unit` = mask, `ioa_AllocKey` = key. [D][O]
- **All the other commands** check, channel by channel, that the channel's key = `ioa_AllocKey`;
  otherwise `ADIOERR_NOALLOCATION` (−10) and the channel is removed from `io_Unit`. [D][O]
- **CMD_WRITE** only serves the **lowest channel** of `io_Unit`; one queue per channel; the next request
  is loaded into AUDxLC/AUDxLEN at the **start of the last cycle** of the current one ⇒ **gapless
  chaining**; a request is returned at the start of the following block (≈ N passes after it started). [D][O]
- `ioa_Cycles = 0` = infinite loop (the channel's interrupt is turned off; only FINISH/FLUSH/… stop it). [D][O]
- **Major V34 bug**: **ADCMD_WAITCYCLE on a playing channel never returns the request** and
  corrupts the internal reply list (§5.13); on an idle channel it is returned at once. [D][O]
- Codes produced: −2 (IOERR_ABORTED), −10, −11 (ALLOCFAILED), −12 (CHANNELSTOLEN). **IOERR_NOCMD
  is never produced** (the code exists but is unreachable); an unknown command with
  `io_Unit = 0` is returned without error. [D][O]
- Hardware: AUD0–3 interrupts (INTENA/INTREQ bits 7–10, level 4) via **SetIntVector** (no
  chaining), DMACON bits 0–3 only (never DMAEN), ADKCON only **cleared** (modulation bits
  linked to the channel); no filter, no period check, no chip RAM check. [D][O]

## 1. Module, initialisation, Open/Close/Expunge

### 1.1 ROMTag and base [D]

| Element | Value |
|---|---|
| Name (ln_Name of the base and of the Interrupts) | `"audio.device"` |
| base ln_Type | 3 (NT_DEVICE); lib_Flags = 6 (SUMUSED\|CHANGED) |
| Version / revision | 34 / 1 |
| ROMTag: flags, pri, type | `$81` (AUTOINIT\|COLDSTART), 40, NT_DEVICE |
| dataSize (positive size) | 634 bytes = Library header + private data + 4 channel blocks |
| Vectors | 6, table format of relative WORDs |

The private structure of the base is free for a reimplementation; the necessary data model is
in §3.

### 1.2 Initialisation (called by InitResident) [D]

In order:
1. DMACON := `$000F` (turns off the DMA of the 4 channels, without touching DMAEN).
2. Three empty lists: pending replies, LOCK requests, pending ALLOCATE requests.
3. A **software interrupt** (Interrupt NT_INTERRUPT, name `"audio.device"`, pri 0, is_Data = reply
   list) that returns (ReplyMsg) all the requests of the reply list.
4. For each channel n = 0..3: empty lists (write queue, WAITCYCLE queue); an Interrupt structure
   (NT_INTERRUPT, name `"audio.device"`, pri 0, is_Data = channel block) installed by
   **SetIntVector(7 + n)**; the **old vector is stored** (returned by Expunge); DMA mask = 1 << n;
   interrupt mask = `$80` << n; channel key = `$FFFF` (no owner); precedence =
   **−129** ("free" sentinel value, lower than any ln_Pri); then **channel reset**
   (§5.1: AUDxPER := 1, AUDxVOL := 0, ADKCON cleaned).
5. Key counter = 0. **INTENA is not touched** at init (the AUDx bits stay off). [D][O: ie
   = `$4000` outside playback]

### 1.3 OpenDevice [D][O]

- Increments lib_OpenCnt, then turns the request into an **ADCMD_ALLOCATE**: `io_Command := $20`,
  `io_Flags := ADIOF_NOWAIT | IOF_QUICK` (`$41`), call of the **device's BeginIO via io_Device**, then
  **WaitIO**; then `io_Flags := 0`. The fields supplied by the caller (`ln_Pri`, `ioa_AllocKey`,
  `ioa_Data`, `ioa_Length`) are used as is. [D]
- Success: clears the "deferred expunge" flag. `io_Command` **stays at `$0020`**, io_Flags = 0. [O T1/T2]
- Failure (`io_Error ≠ 0`): calls **Close** on the request (§1.4) ⇒ `io_Device := −1`, OpenCnt
  decremented again; exec returns the error in D0. Observed example: D0 = `$FFFFFFF5`, io_Error = `$F5`,
  io_Unit = 0, AllocKey = 0, io_Device = `$FFFFFFFF`. [O T2c]
- `ioa_Length = 0`: immediate success **without allocation**; a key is still assigned if
  `ioa_AllocKey` was 0 (first key of the system = **1**). On return from OpenDevice, io_Unit = 0 (input
  value `$55` lost — cf. Open points). [O T1]
- Combinations `{1,2,4,8}` pri 0 on a fresh device ⇒ io_Unit = 1, key 2; then `{1,2}` pri 0 ⇒ io_Unit
  = 2, key 3; then `{1}` pri 0 ⇒ failure −11 (channel 0 at precedence 0, equality ⇒ no theft). [O T2]
- Edge case: if the chosen combination contains a **locked** channel, the ALLOCATE is queued
  **despite ADIOF_NOWAIT** (§4.4) ⇒ OpenDevice blocks in WaitIO until release. [D]

### 1.4 CloseDevice [D][O]

1. Saves the low byte of io_Command, io_Flags and io_Error.
2. `io_Unit := $F`, `io_Command := ADCMD_FREE`, **DoIO** (only the channels whose key = that of the
   request are freed; the others give −10, ignored).
3. Restores io_Command (low byte extended to a word), io_Flags, io_Error; **io_Device := −1**.
4. lib_OpenCnt−−; if it drops to 0 **and** an expunge is deferred ⇒ Expunge; otherwise returns 0.
Observed: after Close, io_Device = `$FFFFFFFF`, io_Command = `$0020` (restored), and channel 0 that it
owned can be reallocated by a request of pri −128. [O T16]

### 1.5 Expunge [D]

OpenCnt ≠ 0 ⇒ sets "deferred expunge", returns 0. Otherwise: for each channel, SetIntVector(7+n,
stored old vector), Remove of the base, FreeMem(base − NegSize, NegSize + PosSize), returns the
seglist received at init (0 for the ROM resident).

## 2. IOAudio structure (ABI, `devices/audio.h`)

| Off. | Size | Field | Use by V34 |
|---:|---:|---|---|
| 0 | 14 | Node (ln_Pri at +9) | **ln_Pri** = allocation priority (signed byte) and value for SETPREC |
| 14 | 4 | mn_ReplyPort | reply port |
| 20 | 4 | io_Device | set to −1 by Close |
| 24 | 4 | io_Unit | **channel mask** (bits 0–3); **must be ≤ 15** (§5.0) |
| 28 | 2 | io_Command | |
| 30 | 1 | io_Flags | IOF_QUICK (bit 0), ADIOF_PERVOL `$10`, ADIOF_SYNCCYCLE `$20`, ADIOF_NOWAIT `$40`, ADIOF_WRITEMESSAGE `$80` |
| 31 | 1 | io_Error | 0 at the start of each BeginIO |
| 32 | 2 | ioa_AllocKey | key; 0 ⇒ a new key is assigned at allocation |
| 34 | 4 | ioa_Data | ALLOCATE: array of mask bytes; WRITE: sample (chip, **even**); READ: returned |
| 38 | 4 | ioa_Length | ALLOCATE: number of combinations; WRITE: length in bytes |
| 42 | 2 | ioa_Period | WRITE/PERVOL |
| 44 | 2 | ioa_Volume | WRITE/PERVOL (0–64) |
| 46 | 2 | ioa_Cycles | WRITE: number of passes, 0 = infinite |
| 48 | 20 | ioa_WriteMsg | Message returned at start if ADIOF_WRITEMESSAGE |
| | 68 | total size | |

Period and volume are read **together as one long word** (Period then Volume, contiguous) and written in a single
long access into AUDxPER then AUDxVOL: the order of the two fields is therefore contractual. [D]

## 3. Data model (what a reimplementation must keep) [D]

Per channel: owner key (`$FFFF` = free), precedence (signed word, −129 = free), write queue
(FIFO), WAITCYCLE queue, **current** request (the one Paula is playing), **armed** request (the one whose
LC/LEN are in Paula; equal to the current one during its playback), remaining cycle counter,
"stopped" flag (CMD_STOP), "WAITCYCLE pending" flag, state of the interrupt automaton (§6).
Global: mask of locked channels, list of LOCKs, queue of pending ALLOCATEs (sorted by ln_Pri,
`Enqueue`), reply list + software interrupt, key counter (word).

**Keys**: at each assignment, counter + 1; if it becomes ≤ 0 it restarts at 1 ⇒ keys 1..32767, never
0 nor `$FFFF`. A key is only assigned if `ioa_AllocKey = 0` **and** the ALLOCATE succeeds (or
`ioa_Length = 0`); a request that keeps a non-zero key reuses it. V34 consequence: a request
carrying the key `$FFFF` "owns" all the free channels (not probed). [D][O: keys 1,2,3,4,5,…;
failure ⇒ key 0 left]

## 4. ADCMD_ALLOCATE (`$20`)

### 4.1 Choice of the combination [D][O]

1. `ioa_Length = 0` ⇒ immediate success, `io_Unit` **unchanged**, key assigned if zero. [O T15: u = `$33`
   kept, k = `$000A`]
2. Otherwise `io_Unit := 0`, then the channels are ranked by precedence: level 0 = free channels (−129),
   then increasing levels of the distinct precedences of the allocated channels.
3. Maximum usable level = the highest level whose precedence is **strictly < ln_Pri**
   (the "free" level always is). If no combination is a subset of the channels of the
   levels ≤ maximum ⇒ **failure** (§4.3).
4. Otherwise the **smallest level** j for which a combination fits in the channels of
   level ≤ j is sought, and the **first** combination of the array that fits there is taken.
Observed (T3): pri 10 steals a channel of precedence 0; `{3, C}` pri 20 with 2 and 3 free ⇒ **C**;
`{1, 2}` pri 15 with channel 0 at 10 and channel 1 at 0 ⇒ **2** (least damage); `{1}` pri 15 steals the 10;
`{2}` pri 15 against precedence 15 ⇒ **failure −11**. [O]
A combination 0 always fits ⇒ success with io_Unit = 0 (not probed). [D]

### 4.2 Success [D][O]

If no chosen channel is locked: `io_Unit := combination` (extended to 32 bits), key assigned if
zero, then for **each channel** of the mask (lowest to highest): **channel reset**
(§5.1: the old owner's writes are returned, cf. FLUSH), precedence := ln_Pri, key :=
ioa_AllocKey. The theft is **silent** for the old owner: its following commands return
−10 (`io_Unit := 0` for WRITE). [O T3b: −10 immediately] ADKCON effect observed: `$FF` ⇒ `$EE` after
allocation of channel 0, then `$88` after channel 2. [O T5]

### 4.3 Failure [D][O]

- **ADIOF_NOWAIT** ⇒ io_Error := **ADIOERR_ALLOCFAILED (−11, `$F5`)**, io_Unit = 0, returned. [O]
- Without NOWAIT ⇒ the request is **Enqueue**d (by ln_Pri) into the waiting queue, stays in progress
  (ln_Type = NT_MESSAGE, IOF_QUICK cleared). [O T14: p = 1]
- **Retry** of the whole queue, in list order, after each **ADCMD_FREE** and each
  **ADCMD_SETPREC** (hence also CloseDevice) — and only then. During its retry a request carries
  io_Error = 1 (internal marker); success ⇒ io_Error := 0, removed and returned; if AbortIO has marked it
  −2 in the meantime ⇒ removed and returned with −2; failure and NOWAIT ⇒ −11, returned; otherwise it stays
  in the queue **with io_Error = 1** (the marker is not cleared). [D]
  Observed: after SETPREC −100 by the owner (pri 50), a waiting pri 0 request gets the channel. [O T14]

### 4.4 Locked channel in the chosen combination [D][O]

Nothing is allocated. Any **LOCK** request in progress whose io_Unit touches one of the targeted locked channels is
removed and returned with **ADIOERR_CHANNELSTOLEN (−12, `$F4`)**, io_Unit unchanged; the ALLOCATE is
queued **even with ADIOF_NOWAIT** (it does not fail). The channel's "locked" bit **stays set** until
an ADCMD_FREE by the owner, which restarts the queue: the ALLOCATE then gets the channel.
Observed T13: LOCK (pri 0) in progress, ALLOCATE pri 50 NOWAIT ⇒ in progress, LOCK returned −12 u = 8; FREE by the
owner ⇒ ALLOCATE returned 0, u = 8. [O]

## 5. Other commands

### 5.0 Common BeginIO frame [D][O]

- `io_Error := 0`; every BeginIO runs under **Forbid** (Permit at the end).
- ALLOCATE (`$20`): §4. Any other command: walk of the channels of `io_Unit`, **from the lowest bit
  to the highest**. `io_Unit` serves as an index into a 16-entry table: **a value > 15 goes outside the
  table (undefined behaviour)**. `io_Unit = 0` ⇒ no channel processed, request returned without error, whatever
  the command (including unknown). [D][O T15: cmd `$1F`, u = 0 ⇒ e = 0]
- Wrong key on a channel: io_Error := −10, the channel's bit removed from io_Unit, then depending on the command:
  READ, WRITE, LOCK, WAITCYCLE ⇒ `io_Unit := 0` and end (returned); UPDATE, CLEAR, STOP, FLUSH,
  FINISH, PERVOL ⇒ channel ignored, continue; START, FREE, SETPREC ⇒ continue, and if it was the
  last channel the command's final action (grouped DMACON, restart of the allocations) still
  takes place; **CMD_RESET with a wrong key jumps outside the dispatch table** (undefined, do not reproduce:
  return −10). [D]
- Command 0 (CMD_INVALID) or 15..31, `$21`.. with a valid channel: dispatch outside the table, undefined;
  a reimplementation will return IOERR_NOCMD. [D]
- End: the replies accumulated by other requests (internal list) are returned before the return;
  then the request itself is returned by ReplyMsg **unless IOF_QUICK**; a request that stays in
  progress (WRITE, LOCK, WAITCYCLE while playing, pending ALLOCATE) gets ln_Type = NT_MESSAGE and
  IOF_QUICK cleared.

### 5.1 CMD_RESET (1) — channel reset [D][O]

For each channel: SetIntVector(7+n) **reinstalled** (audio.device's handler takes the vector back even
if a program had replaced it); **FLUSH** of the channel (§5.7); **AUDxPER := 1 and AUDxVOL := 0** (a
single long access); **ADKCON := mask without SET bit**, mask depending on the channel: 0 ⇒ `$11`, 1 ⇒ `$33`,
2 ⇒ `$66`, 3 ⇒ `$CC` (USEnVm/USEnPm bits where the channel is modulator or modulated); "stopped" flag
cleared. Does not deallocate. The same reset is done at init, at allocation and at FREE. [O T5 for
ADKCON]

### 5.2 CMD_READ (2) [D][O]

Lowest channel only: `io_Unit := channel mask`, **`ioa_Data := current WRITE request`** (NULL
if idle), returned at once. [O T7: during A, ioa_Data = &A; afterwards, 0]

### 5.3 CMD_WRITE (3) [D][O]

Lowest channel only; `io_Unit := channel mask`. Request **never returned by BeginIO**.
- If the channel already has an armed request ⇒ added at the **end of the queue** (FIFO).
- Otherwise: **AUDxLEN := ioa_Length / 2** (integer division; 0 ⇒ 65536 words for Paula; ≥ 131072
  truncated), **AUDxLC := ioa_Data**, counter := ioa_Cycles, request armed. Then:
  - if a current request is still playing (last cycle in progress) **or** if the channel is stopped: nothing
    else (the next start-of-block interrupt will take over; stopped channel ⇒ waits for START);
  - otherwise **cold start**: if INTENAR does not have the channel's bit: INTREQ := bit (acknowledge) then
    INTENA := SET|bit; if ADIOF_PERVOL: **AUDxPER := 1**; **AUDxDAT := first byte of the sample
    copied into both halves of the word** (word read at ioa_Data ⇒ even address mandatory). The
    DMA is **not** yet turned on: Paula, in manual mode, plays this word very quickly (period 1) and raises
    the interrupt, whose handler turns on the DMA (§6).
- Without ADIOF_PERVOL, the period/volume remain those of the channel (after reset: **period 1, volume
  0**): the first write to a channel must therefore carry ADIOF_PERVOL. [D]
- Period/volume (ADIOF_PERVOL) applied **at the start of the block** of the request (DMA interrupt), hence at
  its first note, including for a chained request. [D]
- ADIOF_WRITEMESSAGE: `ioa_WriteMsg` is returned (ReplyMsg, via its own mn_ReplyPort) **when the
  request starts playing**. [D]
- **Return**: when the next request starts (same interrupt), or if there is none, at
  the interrupt following the end of the last pass: the channel's DMA and interrupt turned off, then returned.
  io_Error = 0. Measurements (T6): cycles 1 ⇒ **1773** lines, 2 ⇒ **3536**, 4 ⇒ **7060** (≈ N × 1761 +
  ≈ 12); during playback DMACONR = `$0201`, INTENAR = `$4080`; afterwards, `$0200` / `$4000`. [O]
- **Chaining**: A (1 cycle) then B (1 cycle) sent back to back ⇒ A returned at **1791**, B at **3536**,
  exactly the duration of A with 2 cycles: no gap. [O T7]
- `ioa_Cycles = 0`: infinite loop, **the channel's INTENA turned off** from the start (no interrupt afterwards);
  observed ie = `$4000`, DMA active, request still in progress after 6000 lines. [O T11]

### 5.4 CMD_UPDATE (4), CMD_CLEAR (5) [D]

No effect (apart from the key check). Returned.

### 5.5 CMD_STOP (6) [D][O]

For each channel: "stopped" flag, **INTENA := channel bit (clear)**, then **DMACON := channel
bit (clear)**. The requests stay in place. Observed: DMACONR `$0200`, INTENAR `$4000`, the
request no longer advances (in progress after 6000 lines). A WRITE on a stopped channel is armed (LC/LEN written)
but does not start. [O T12]

### 5.6 CMD_START (7) [D][O]

For each channel: clears "stopped"; if the channel has a current or armed request: adds its bit to the
DMA mask and, if INTENAR does not have the bit, INTREQ := bit then INTENA := SET|bit. After the **last**
channel: **a single DMACON := SET | mask** (simultaneous start). Paula **restarts from the beginning** of the armed
sample (LC/LEN), and the restart interrupt **consumes one cycle**: A (2 cycles) stopped at 500 lines
then restarted at ≈ 6520 is returned at **8383** (= resumption + one whole pass). STOP then WRITE then START ⇒
returned at 1771 after START. [O T12]

### 5.7 CMD_FLUSH (8) [D][O]

For each channel, under Disable:
1. if a request is armed: the **next one in the queue** is loaded into LC/LEN (as at an end of
   cycle); the old armed one, if it was not the current one, is returned with −2;
2. the current one is cut: if nothing is armed (or the channel is stopped) ⇒ DMACON := bit, INTENA := bit,
   current one returned (io_Error 0); otherwise DMA turned off and restart by the automaton (§6,
   "restart" state) ⇒ the current one is returned (io_Error **0**) when the next one starts;
3. all the requests **remaining** in the write queue ⇒ io_Error −2, returned; WAITCYCLE flag cleared;
   WAITCYCLE queue ⇒ −2, returned.
**V34 peculiarity**: the first request in the queue is **not** cancelled, it is promoted and plays
entirely. Observed (T10): A (5 cycles) + B (2 cycles), FLUSH at ≈ 330 ⇒ FLUSH returned at 330, **A returned
e = 0 at 1777**, **B returned e = 0 at 5302** (two passes). [O]

### 5.8 ADCMD_FREE (9) [D][O]

For each channel: reset (§5.1), key := `$FFFF`, precedence := −129. After the last channel:
if freed channels were locked, their bits are removed from the lock mask and from the
io_Unit of each LOCK in progress; a LOCK whose io_Unit drops to 0 is returned (io_Error 0, io_Unit 0)
[O T13]; **`io_Unit := 0`** [O T4]; then restart of the ALLOCATE queue (§4.3). Channel of another
owner ⇒ −10. [O T4]

### 5.9 ADCMD_SETPREC (10) [D][O]

For each channel: precedence := ln_Pri of the request. After the last one: restart of the ALLOCATE
queue. [O T14]

### 5.10 ADCMD_FINISH (11) [D][O]

For each channel, under Disable: like step 1 of FLUSH (the next one in the queue is armed, the queue
is not emptied), then:
- **ADIOF_SYNCCYCLE**: the current one finishes **at the end of its pass in progress** (the channel's interrupt
  is re-enabled if needed). Observed on infinite cycles: FINISH at 6104, request returned at **7060**
  (end of the 4th pass). [O T11]
- without SYNCCYCLE: immediate cut (same handling as step 2 of FLUSH). Observed, nothing queued:
  returned **81 lines** after FINISH, DMA and interrupt off. [O T11]
The FINISH request is returned at once; the written request returned keeps io_Error = 0. [O]

### 5.11 ADCMD_PERVOL (12) [D]

For each channel: if **ADIOF_SYNCCYCLE** and the channel is in the "cycle counting" state (§6):
ioa_Period/ioa_Volume stored, the automaton goes into the "deferred PERVOL" state and the channel's
interrupt is enabled if needed ⇒ AUDxPER/AUDxVOL written **at the start of the next block**, that start counting
as a cycle. Otherwise: AUDxPER then AUDxVOL written immediately (long access). Returned at once.
(Write-only registers: not observed.)

### 5.12 ADCMD_LOCK (13) [D][O]

Key checked on **all** channels (a single wrong key ⇒ −10, io_Unit 0, returned); then lock
mask |= io_Unit, request added to the list of LOCKs, **stays in progress**. Returned by: FREE of
all its channels (io_Error 0, io_Unit 0); attempted theft by a higher-priority allocation
(−12, io_Unit unchanged, §4.4); AbortIO (−2). [O T13]

### 5.13 ADCMD_WAITCYCLE (14) — bug [D][O]

Lowest channel only, `io_Unit := mask`. **Idle** channel ⇒ returned immediately, io_Error 0
[O T8]. **Playing** channel ⇒ WAITCYCLE flag, added to the channel's WAITCYCLE queue, interrupt
enabled; at the next interrupt, V34 wants to transfer this queue into the reply list but
takes the **first element of the queue for the list header**: the reply list is corrupted
(pointers taken from the ln_Type/ln_Pri/ln_Name bytes of the request). Observed (T17): WAITCYCLE during
a 3-cycle WRITE ⇒ **neither the WAITCYCLE nor the WRITE are ever returned** (8000 lines); during a
first run, the following tests were polluted. A reimplementation will do the intended behaviour:
return the WAITCYCLEs at the end of the cycle in progress (next interrupt). A FLUSH/RESET returns them with −2. [D]

## 6. Per-channel interrupt automaton (level 4) [D][O]

The handler (SetIntVector Interrupt, is_Data = channel) receives A0 = `$DFF000`. States:

| State | On the interrupt |
|---|---|
| **Start** (after a cold start §5.3, or a cut with an armed continuation) | INTREQ := bit (ack), **DMACON := SET\|bit**; goes to "Start of block" |
| **Start of block** (the armed request has just been loaded by Paula) | if ADIOF_PERVOL: AUDxPER/AUDxVOL := ioa_Period/ioa_Volume; the old current one is put in the replies (io_Error unchanged); current := armed; if ADIOF_WRITEMESSAGE: ioa_WriteMsg put in the replies; then **chains immediately** into "Counting" |
| **Counting** | counter − 1: > 0 ⇒ ack; = 0 ⇒ **loads the next one** (AUDxLEN, AUDxLC, counter := its cycles, armed := it, removed from the queue, "Start of block" state) or, empty queue, armed := none and "End" state; then ack. Counter already 0 (infinite cycles) ⇒ stays 0, **INTENA := bit (off)**, ack |
| **End** | **DMACON := bit (off), INTENA := bit (off)**, current one put in the replies, current := none; **no INTREQ ack** (the interrupt is masked; the next cold start acknowledges before enabling) |
| **Deferred PERVOL** | AUDxPER/AUDxVOL := stored values then chains into "Counting" |

Common end: if the WAITCYCLE flag is set ⇒ transfer of the WAITCYCLE queue (bug §5.13) and
**Cause** of the software interrupt; otherwise if the reply list is not empty ⇒ **Cause**. The
ReplyMsg calls are therefore never made at level 4: they are made by the software interrupt (removal of
each node under Disable, ReplyMsg outside Disable) or, from BeginIO/AbortIO, directly before returning.
The counter is decremented from the start of the first block: with N cycles, the next one is loaded at the start
of the N-th pass, hence the return at ≈ N passes (§5.3). [O]

## 7. AbortIO [D][O]

Targeted channel = the lowest of `io_Unit & $F`. Depending on io_Command:
- WAITCYCLE (14): removal from that channel's WAITCYCLE queue; LOCK (13): from the list of LOCKs;
  ≥ `$20`: from the ALLOCATE queue. Found ⇒ removed and returned, **io_Error := −2**; if it carries
  marker 1 (retry in progress), it is only marked −2 and it is the retry that returns it. [O T14: pending ALLOCATE ⇒ −2, io_Unit 0]
- ≤ 3 (WRITE): under Disable; if it is the **armed** request ⇒ handling of step 1 of FLUSH; if it is
  the **current** one ⇒ cut as in step 2 of FLUSH ⇒ returned with **io_Error 0** (not −2) when the
  next one starts, or at once if there is no continuation; otherwise search in the write queue ⇒
  −2. Observed (T9): A (5 cycles) + B + C, AbortIO(C) at 327 ⇒ **−2** immediately; AbortIO(A) ⇒ A returned
  **e = 0 at 1783**, B returned at 3539 (one pass). [O]
- 4..12: no effect.
Always: the accumulated replies are returned before the return. AbortIO returns no
meaningful value. [D]

## 8. Hardware registers: write orders and acknowledgements

### 8.1 Paula-only oracle (without audio.device) [O T0]

AUD0 1000 bytes, period 400, interrupt masked, polling of INTREQR: DMA on ⇒ INTREQ bit 7 at
**1 line** (initial load), then at **1761** and **3523** (reloads = start of each block).
Manual start: AUD0DAT written with AUD0PER = 1, DMA off ⇒ INTREQ at 1 line; DMA turned on afterwards ⇒
INTREQ at 22 lines, then 1745, 3507. The interrupt therefore marks the **start** of a block (LC/LEN already
copied: the next block can be written there).

### 8.2 Summary of audio.device's accesses [D]

| Register | Writes |
|---|---|
| DMACON | init `$000F`; STOP/End/cut: channel bit without SET; start: SET\|bit; START: grouped SET\|mask. Never DMAEN nor any other bit. |
| INTENA | SET\|bit before any start (if INTENAR does not already have it, preceded by INTREQ := bit); bit without SET at STOP, at End and in infinite cycles |
| INTREQ | channel bit (ack) at the end of each interrupt except the End state; before enabling |
| AUDxLC / AUDxLEN | WRITE: **LEN first, then LC** (at cold start as at chaining) |
| AUDxPER / AUDxVOL | long access (PER then VOL): reset (1, 0), start of block with PERVOL, PERVOL; AUDxPER alone := 1 at cold start with PERVOL |
| AUDxDAT | cold start: first byte duplicated |
| ADKCON | channel reset: clearing `$11`/`$33`/`$66`/`$CC`; never SET (modulations are up to the program) |
| Read | INTENAR (channel bit) only |

### 8.3 Interrupt vectors [D]

SetIntVector(INTB_AUD0..3 = 7..10), without chaining to the old vector; reinstalled at each channel
reset. A program that writes the 68000 vector `$70` directly (cf. monkey-startup) short-
circuits exec and audio.device.

## 9. What differs on a real A500

- **Filter**: audio.device never touches CIA-A (bit 1 of PRA, LED/filter). [D]
- **Period**: no bound. The HRM sets a minimum of **124** for DMA (otherwise Paula cannot
  be fed in time: repeated/skipped samples); V34 passes ioa_Period as is. The period
  1 written at cold start serves the manual mode (DMA off) and is not concerned. [D][S]
- **Chip RAM**: not checked; a sample in fast/slow RAM is read by the DMA at the same address
  (wrong sound). An **odd** address causes a 68000 address error at cold start (word
  read). [D]
- **DMA cut in the middle of a block** (FLUSH, FINISH without SYNCCYCLE, AbortIO of the current one, with an
  armed continuation): V34 relies on the "manual mode" interrupt that Paula raises after the current word
  when AUDxEN drops. Under FS-UAE this interrupt only arrived at the theoretical end of the block
  (returns at ≈ 1780 instead of ≈ 330); on real hardware it should follow within a few lines. [O][S]

## 10. Open points

1. **Cut delay on a real Paula** (§9, last point): FS-UAE returns the cut current request at the end of
   its pass; the real behaviour (near-immediate interrupt according to the HRM automaton) is not
   measured. A reimplementation only has to reproduce the order: current returned (0), then next.
2. **io_Unit after OpenDevice with ioa_Length = 0**: observed 0 whereas a direct BeginIO leaves it
   unchanged; the write most likely comes from exec's OpenDevice (unit 0), not verified.
3. **ADCMD_PERVOL** and the exact value of AUDxPER/AUDxVOL at the various moments: write-only
   registers, deduced from the code only (the FS-UAE debugger was not used).
4. **CMD_RESET with a wrong key**, commands 0 and 15..31 on a valid channel, io_Unit > 15: jumps outside
   the table in V34 (not probed: risk of crash). To be handled as a clean error.
5. **WAITCYCLE while playing**: corruption demonstrated by the code and the probe; the exact extent of the memory
   damage (addresses written) depends on the contents of the request and has not been characterised.
6. **Key `$FFFF`** giving access to the free channels: deduced, not probed.
7. Minimum period 124 and filter: taken from the HRM, no measurement on real hardware.

## Clean-room review

Review of 2026-10-29.

- [x] No 68000 instruction sequence transcribed or paraphrased, no disassembly excerpt,
  no ROM routine address (only `$DFF000` and the 68000 vector `$70`, hardware/CPU addresses).
- [x] The interrupt automaton (§6) and the commands (§4-§7) are described by **states, effects on the
  Paula registers and order of the returns**, cross-checked by the black-box probe [O]; the internal
  dispatch table is only mentioned to flag the undefined cases to be handled as errors.
- [x] No ROM data beyond the ABI: ID string, base size, number of vectors, per-channel ADKCON
  masks (values written into a register, observable), key/precedence sentinels.
- [x] The probe cited (`tests/audio_probe.s`) is author code.
