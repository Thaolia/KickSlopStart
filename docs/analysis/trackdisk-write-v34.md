# trackdisk-write-v34.md — Floppy writing in trackdisk.device V34.1 (ROM `kick34005.A500`)

> **ANALYSIS track ("dirty").** **Behavioural** spec: values, order of operations, layouts. No transcribed
> instruction sequence, no listing, no ROM routine address. Complements
> `trackdisk-official-timing.md` (read, seek, motor), whose §3.3 was only a memo: it is not repeated here.
>
> **Levels of evidence.** **[O]** observed: either read unambiguously in the ROM (constant, test, order of
> register accesses) or measured by the probe; the mention **(probe)** flags what was **seen running** under
> FS-UAE with the real ROM. **[D]** deduced (logical consequence, or standard hardware fact applied to the
> observed behaviour). **[S]** assumed.
>
> **Probe.** `tests/tdwrite.s` + `tests/tdwrite_run.sh`: blank OFS floppy, the startup-sequence launches the
> probe, which chains trackdisk requests on unit 0 and writes `étape E=io_Error A=io_Actual L=1er long` to the
> serial port; the emulator's disk log (`did 2`) gives, for each DSKLEN arming, the length, ADKCON, the
> track and the MFM position. Vectors in §8.

---

## 1. Overview

1. The driver owns **a single MFM track buffer per unit** (write-back cache). `CMD_WRITE`
   **does not write** to the disk: it first reads the whole track (if it is not already cached), encodes the
   requested sectors into the in-memory MFM image and marks the buffer **dirty**. The physical write of the
   complete track only takes place at the **flush** (§5.3). [O] (probe: steps B/C/D)
2. A physical write **always writes a whole track**: a single DMA transfer of **6815 words
   (13,630 MFM bytes)**, with no synchronisation on the index, no WORDSYNC, no verification read-back. [O] (probe)
3. `TD_FORMAT` builds the track image from scratch (no prior read) and writes it track by
   track with the same primitive. [O] (probe: step L)

---

## 2. Written track image (encoding)

### 2.1 Overall layout of the transfer

| Zone | MFM bytes | Content |
|------|-----------:|---------|
| Leading gap | **1660** (`$67C`) | word `$AAAA` repeated (830 words = 830 data bytes `$00`) [O] |
| 11 sectors | 11 × **1088** (`$440`) = 11,968 | §2.2, with no gap at all between sectors [O] |
| Trailing word | **2** | `$AAA8` (or `$2AA8` if the preceding last data bit is 1) after a read-modify; `$AAAA` (or `$2AAA`) after a `TD_FORMAT` [O] |
| **DMA total** | **13,630** = **6815 words** | DSKLEN = `$C000 | $1A9F` = **`$DA9F`** [O] (probe: `LEN=1A9F (6815)`) |

- The DMA starts **at an arbitrary rotational position** (no wait for the index in `CMD_UPDATE`/`TD_FORMAT`).
  [O] (probe: different starting MFM positions on each write)
- Duration: 6815 words × 32 µs = **218.1 ms** (2 µs cell, ADKCON FAST=1). One revolution at 300 rpm =
  200 ms = **12,500 MFM bytes**. The end of the transfer **therefore overlaps the start of the gap** it has just
  written, by about 1130 bytes at nominal speed: ≈ 530 bytes of effective gap remain between the end of the
  last sector and the first sector. [D]
- Resulting speed tolerance: the tail does not reach the first sector as long as the revolution lasts
  ≥ 11,970 MFM bytes, i.e. a speed ≤ ≈ **313 rpm (+4.4 %)**. If the drive is slow (revolution > 13,630
  bytes, < ≈ 275 rpm), a piece of the old track remains between the end and the start of the write. [D]
- The gap stays `$AAAA` permanently: the area of the buffer that holds it is never touched by a read
  (the read DMA writes further into the buffer). [O]

### 2.2 Sector (1088 MFM bytes)

Offsets relative to the start of the sector. "Encoded long" = 8 MFM bytes: first the **odd** bits (bits 31, 29...
1 of the data long, each preceded by its clock bit), then the **even** bits. An "encoded block" of N
bytes = N bytes of odd bits then N bytes of even bits.

| Offset | Size | Content |
|-------:|-------:|---------|
| `+$000` | 4 | preamble: 2 encoded `$00` bytes = `$AAAA $AAAA` (first word `$2AAA` if the preceding bit is 1) [O] |
| `+$004` | 4 | **`$4489 $4489`** written as is (sync marks, deliberately missing clock) [O] |
| `+$008` | 8 | encoded info long: byte 0 = `$FF` (Amiga 1.0 format), byte 1 = **track** (0–159 = cyl×2+side), byte 2 = **sector** (0–10), byte 3 = **sectors remaining before the gap** (11 for the first sector after the gap ... 1 for the last) [O] |
| `+$010` | 32 | label (16 bytes) as an encoded block; zeros in `TD_FORMAT` [O] |
| `+$030` | 8 | header checksum, encoded long (§2.3) [O] |
| `+$038` | 8 | data checksum, encoded long (§2.3) [O] |
| `+$040` | 1024 | 512 data bytes as an encoded block (512 odd bytes then 512 even) [O] |

### 2.3 Checksums

- **Header checksum** = XOR of the **10 MFM longs** from `+$008` to `+$02F` (info + label, clock bits included),
  then AND `$55555555`; the result (a data long) is encoded at `+$030`. [O]
- **Data checksum** = XOR of the **256 MFM longs** from `+$040` to `+$43F`, then AND `$55555555`, encoded at
  `+$038`. [O]
- Equivalence: the mask removes the clock bits; it is the XOR of the odd/even data longs. [D]
- Computation order: the header checksum is computed **after** encoding the info and the label, the data
  checksum **after** encoding the data **and** correcting the junction clocks (§2.4). [O]

### 2.4 Clock bits

- Standard MFM: clock bit = 1 if and only if both neighbouring data bits are 0. [O]
- The leading clock bit of each encoded long or block depends on the **last bit already present in memory** just
  before (bit 0 of the preceding byte): if it is 1, the leading clock is forced to 0. [O]
- After each block encoded by the blitter (label, data), the leading clock of the **next** byte is
  recomputed; this covers the odd→even junction, the data→next sector junction, and the byte that follows the
  last sector (trailing word). [O]
- The `$4489` marks are never re-encoded; the info that follows them sees a preceding bit of 1 (`$89` ends in
  1) and therefore takes a leading clock of 0. [O]

### 2.5 Order of sectors in the written track

- **`TD_FORMAT`**: gap then sectors **0, 1, ... 10** in order, "remaining before gap" field 11...1,
  null labels. [O]
- **Flush after `CMD_WRITE`**: the prior read **reorganises** the buffer: sectors are stored there in
  consecutive number order (modulo 11) **starting from the first sector met by the read DMA**, the
  original gap is removed, and the "remaining before gap" field of each header is **rewritten** (11...1) with
  the header checksum recomputed. The rewritten track therefore begins with an arbitrary sector followed by the other 10
  in order, and the new gap is placed in front of that sector. [O]
- The label and info of unmodified sectors are kept as read. A `CMD_WRITE` without a label keeps
  the label read; an `ETD_WRITE` with a non-null `iotd_SecLabel` replaces the label (16 bytes per sector, the
  pointer advances by 16 per sector) and recomputes the header checksum. [O]
- Requirement for the prior read: 11 **consecutive** sectors (otherwise `TDERR_BadSecID`), track and `$FF` format
  correct, checksums correct. An unreadable or non-conforming track can **not** be rewritten by `CMD_WRITE`,
  even if all 11 sectors are supplied; only `TD_FORMAT` (or `TD_RAWWRITE`) can do it. [O]

### 2.6 Encoding engine

- The data (512 bytes) and the label are encoded and copied by the **blitter** (via the graphics.library
  `QBlit` queue, waiting on a signal), directly from `io_Data` / `iotd_SecLabel`. In V34 these buffers
  **must therefore be in CHIP memory**; no check is made (a buffer in FAST would silently give wrong
  data). [O] (blitter access) / [D] (consequence)
- The info, the preamble, the checksums and the junction clocks are done by the CPU. [O]

---

## 3. Hardware programming of a physical write

Complete sequence of a track write (same primitive for `CMD_UPDATE`, implicit flush, `TD_FORMAT`,
`TD_RAWWRITE`). The motor is already on and the head positioned by the caller (§4).

| # | Action | Value / detail | Evidence |
|--:|--------|-----------------|--------|
| 1 | Acquire the disk channel (disk.resource `GetUnit`, wait on signal if busy) | on acquisition: all drives deselected (PRB = shadow OR `$7F`, `/MTR` kept); **if the last user of the channel was not this unit**: ADKCON ← `$0600` (clears WORDSYNC+MSBSYNC) then ADKCON ← `$9100` (sets **MFMPREC + FAST**) | [O] |
| 2 | Selection | PRB `$BFD100` ← the unit's shadow (motor, `/SEL`, `/SIDE`, `/DIR`) | [O] |
| 3 | Disarm | DSKLEN ← `$4000` | [O] |
| 4 | Settling | **1 ms** (timer.device request) | [O] |
| 5 | Pointer | DSKPT ← buffer address (start of gap) | [O] (probe) |
| 6 | IRQ | INTREQ ← `$1002` (clears DSKSYN+DSKBLK), INTENA ← `$8002` (enables DSKBLK) | [O] |
| 7 | Disk present? | `/CHNG` (CIAA PRA b2) = 0 → **error 29**, nothing is written | [O] |
| 8 | Protection | `/WPRO` (CIAA PRA b3) = 0 → **error 28** (`TDERR_WriteProt`), nothing is written | [O] |
| 9 | Reset guard | under `Disable`: if a keyboard reset has been announced → **error 35** (`TDERR_PostReset`); otherwise the "write in progress" flag is set | [O] |
| 10 | Precompensation | ADKCON ← `$6000` (clears PRECOMP1+PRECOMP0), then ADKCON ← value from §3.1 | [O] (probe) |
| 11 | Arm | DSKLEN ← `$C000 | words` **twice** (DMAEN + WRITE); words = length in bytes / 2 | [O] (probe `LEN=1A9F`) |
| 12 | Wait for the end | sleep until the DSKBLK interrupt (signal + message), **with no guard timeout** | [O] |
| 13 | Cut the IRQ | INTENA ← `$0002` | [O] |
| 14 | **Drain delay** | **2 ms** (timer.device request) **after** DSKBLK and **before** cutting the DMA | [O] |
| 15 | Disarm | DSKLEN ← `$4000` | [O] |
| 16 | End of reset guard | "write in progress" flag cleared; if a reset was announced during the write, only then does the driver signal to keyboard.device that it has finished (`KBD_RESETHANDLERDONE`) | [O] |
| 17 | Disk still there? | `/CHNG` = 0 → **error 29** (disk removed during the write) | [O] |
| 18 | Release the channel | disk.resource `GiveUnit`: PRB ← `$FF` (everything deselected) | [O] |

Remarks:
- **DSKSYNC is never written** and WORDSYNC is never set, for writing as for reading. [O]
  (probe: `SYNC=FFFF`, ADKCON without bit 10)
- **DMACON is not touched** by trackdisk; it is the disk.resource initialisation that sets `DSKEN`
  (DMACON ← `$8010`) and DSKLEN ← `$4000`, once and for all. [O]
- ADKCON MFMPREC+FAST: at the very first `GetUnit` the "last user" holds an invalid initial value
  (`$FFFFFFFF`), so the `$9100` setting is applied from the system's very first disk access. [O]
- The PRECOMP bits **remain set** after the write (no reset at teardown); subsequent reads
  are done with ADKCON = `$3100`, with no effect on reading. [O] (probe)
- No specific delay between the end of a write (step 18) and a later head step: the only
  post-DMA delay is the one of step 14; the next seek applies its usual delays (3 ms/step, 15 ms of
  settle). [O]
- The 2 ms delay (≈ 62 MFM words) lets the last words already fetched by the DMA when DSKBLK fires
  leave Paula's serialiser; the trailing word `$AAA8`/`$AAAA` acts as sacrificial padding if the write
  gate closes a little early. [D]

### 3.1 Write precompensation (ADKCON)

The decision is based on the head's current **track number** (cyl × 2 + side), compared with three unit
thresholds (**inclusive** bounds):

| Condition (track p) | ADKCON written | PRECOMP | Delay |
|---------------------|--------------|---------|--------|
| p ≤ threshold1 | `$8000` (nothing set) | 00 | 0 ns |
| threshold1 < p ≤ threshold2 | `$A000` | 01 | 140 ns |
| threshold2 < p ≤ threshold3 | `$C000` | 10 | 280 ns |
| p > threshold3 | `$E000` | 11 | 560 ns |

Default values [O]:

| Drive | threshold1 | threshold2 | threshold3 | Effect |
|---------|-------:|-------:|-------:|-------|
| 3.5" Amiga (ID `$00000000`) | **80** | `$FFFF` | `$FFFF` | tracks **0–80** (cyl 0–39 and cyl 40 side 0): **none**; tracks **81–159** (from cyl 40 side 1): **140 ns** |
| 5.25" (ID `$55555555`) | 40 | `$FFFF` | `$FFFF` | tracks 0–40: none; 41–79: 140 ns |

The 280/560 ns levels are never reached with the default tables. Probe: track 20 → ADKCON `$1100`,
tracks 100 and 158 → `$3100`. [O] (probe)

### 3.2 `TD_RAWWRITE` (command 17)

Same hardware sequence (§3, including protection, reset guard, precompensation, 2 ms), with: `io_Offset` =
track number (< 160, otherwise `IOERR_BADLENGTH` −4), `io_Length` in bytes (< 32,768, otherwise −4), `io_Data` in
CHIP, seek performed beforehand (a seek error is returned). If `io_Flags` bit 4 (`IOTDF_INDEXSYNC`) is set,
the double DSKLEN write is done **in the index interrupt** (CIA-B FLAG, via ciab.resource) instead of
immediately. Bit 5 (WORDSYNC) is not handled in V34. `io_Actual` is not filled in. [O]

---

## 4. Mechanics around the write

| Point | V34 behaviour | Evidence |
|-------|------------------|--------|
| Motor before flush | switched on if off, then a **blind 500 ms** delay; `/RDY` is not read | [O] |
| `TD_FORMAT` | after switch-on, **an extra 300 ms** if the motor was off (800 ms total); nothing if already on | [O] |
| Seek before write | usual delays: 3 ms/step, **15 ms** of settle after the last step; no delay if the track is already the right one | [O] |
| Side change only (same cylinder) | `/SIDE` changed, **no settle**; only the 1 ms delay of step 4 precedes the DMA | [O] |
| Seek error (failed recalibration) | **ignored** by the flush and by `TD_FORMAT`: the write happens anyway (only `TD_RAWWRITE` returns it) | [O] |
| Protection | read **live** on `/WPRO`, drive selected, just before arming; error 28 at the **flush**, never at the `CMD_WRITE` itself | [O] / [D] |
| Disk absent (unit flag set by the `/CHNG` monitoring) | `CMD_READ`/`CMD_WRITE` → immediate error 29, without motor; `CMD_UPDATE`, `TD_FORMAT` → motor + seek then 29 at step 7 | [O] |
| Removal during the write | 29 at step 17; the buffer stays dirty | [O] |
| Keyboard reset | trackdisk installs a keyboard reset handler: a reset announced **during** a write is deferred until it ends; a write requested **after** the announcement fails with 35 | [O] |
| End of DMA | DSKBLK interrupt only, unbounded wait; since the DMA rate is clocked by Paula and not by the disk, the end always arrives (~218 ms) | [O] / [D] |

---

## 5. Commands

### 5.1 V34 dispatch table [O]

| No. | Command | Handling |
|---:|----------|-----------|
| 0, 1, 6, 7, 8 | `CMD_INVALID`, `CMD_RESET`, `CMD_STOP`, `CMD_START`, `CMD_FLUSH` | `IOERR_NOCMD` (−3) |
| 2 / 3 | `CMD_READ` / `CMD_WRITE` | same engine (§5.2) |
| 4 | `CMD_UPDATE` | flush of the buffer if it is dirty |
| 5 | `CMD_CLEAR` | **invalidates the buffer and DISCARDS the dirty data** without writing |
| 9 | `TD_MOTOR` | `io_Length` 0/1; `io_Actual` = previous state (1 = on) |
| 10 | `TD_SEEK` | seek only |
| 11 | `TD_FORMAT` | §5.4 |
| 15 | `TD_PROTSTATUS` | §5.5 |
| 16 / 17 | `TD_RAWREAD` / `TD_RAWWRITE` | §3.2 |
| ≥ 22 | — | −3 |

Immediate commands (executed in the caller's context): 1, 6, 7, 8, 13, 14, 18, 19; the others go through
the unit task. Bit 15 of `io_Command` = ETD variant (`iotd_Count` check, label). [O]

### 5.2 `CMD_WRITE` / `ETD_WRITE`

1. `io_Actual` ← 0. `io_Offset` and `io_Offset + io_Length` must be multiples of 512 and ≤ 901,120
   (3.5"), otherwise **−4** (`IOERR_BADLENGTH`); `io_Actual` is then 0. [O] (probe N)
2. ETD variant: if the unit's change counter > `iotd_Count` → **29**. [O]
3. Disk absent → **29**. [O]
4. For each sector: if the buffer does not hold the wanted track → **flush** of the old track if dirty
   (a flush error ends the request with that code, the buffer stays dirty on the old track), then
   **read** of the new track (motor, seek, raw read, decoding, reorganisation §2.5). Read
   failure: up to **10 retries**, with a forced **recalibration** before the 4th and the 8th; final
   failure → read code (21–27), buffer invalidated. [O]
5. Encoding of the sector into the buffer (label if ETD, checksums), buffer marked dirty, `io_Actual` += 512. [O]
6. Stops when `io_Actual` ≥ `io_Length`. Since the test is done **after** the first sector, **`io_Length` = 0
   still writes one sector** and returns `io_Actual` = 512. [O] (probe H/I)
7. When crossing a track boundary, the previous track is flushed **during** the command; the last
   track touched **stays dirty** at the end of the command. [O]

No verification read-back after a physical write. [O] (probe: no read DMA between a
flush and the next command)

### 5.3 Buffer flush (physical write)

Triggers: `CMD_UPDATE`; any `CMD_READ`/`CMD_WRITE` to **another** track; start of `TD_FORMAT`;
last `CloseDevice` of the unit (handled by the unit task, which then invalidates the buffer and switches the
motor off). [O]

Non-triggers: `TD_MOTOR` 0, disk change, timeout, `TD_SEEK`, `TD_RAWREAD/RAWWRITE`. [O]

Sequence: motor on (500 ms if off), seek to the buffer's track, write §3. Success → buffer
clean (`CMD_UPDATE`). Failure → `io_Error` = code, **buffer still dirty** (a later `CMD_UPDATE` will
retry). Exceptions: `TD_FORMAT` and the last `CloseDevice` mark the buffer clean **before**
flushing; at `CloseDevice` the error is lost. `io_Actual` is not modified by `CMD_UPDATE`/`CMD_CLEAR`. [O]
(probe F/g)

A disk change does **not** invalidate the buffer: only the head position is forgotten. [O]

### 5.4 `TD_FORMAT`

1. Motor (500 ms + 300 ms if off). Dirty buffer → flushed first (error → end). [O]
2. `io_Offset` and `io_Length` multiples of a **track** (5632 bytes), end ≤ 160 tracks, otherwise **−4**;
   `io_Length` = 0 → success without writing anything (the motor has already been switched on and the buffer flushed). [O] (probe K: −4)
3. For each track: seek (error ignored), image built (gap `$AA`, sectors 0–10, null labels, data
   from `io_Data` in CHIP, 5632 bytes per track), write §3. Error → end with that code. [O]
4. Success: buffer invalidated. `io_Actual` **not modified**. [O] (probe L: `$DEADBEEF` kept)
5. No verification. [O]

### 5.5 `TD_PROTSTATUS`

Disk absent → 29. Otherwise: **switches the motor on** (500 ms if off), reads `/WPRO`, returns `io_Actual` ≠ 0 if
protected (`$FF`), 0 otherwise, then **switches the motor off in every case**. [O] (probe M then O: `TD_MOTOR` returns
"was off")

### 5.6 Error codes met when writing

| Code | Name | Origin |
|-----:|-----|---------|
| −3 | `IOERR_NOCMD` | unhandled command |
| −4 | `IOERR_BADLENGTH` | offset/length not aligned or beyond the disk |
| 21 | `TDERR_NoSecHdr` | prior read: no mark found |
| 22 | `TDERR_BadSecPreamble` | preamble or `$4489 $4489` missing at the expected place |
| 23 | `TDERR_BadSecID` | `$FF`, track or consecutive number wrong |
| 24 | `TDERR_BadHdrSum` | header checksum |
| 25 | `TDERR_BadSecSum` | data checksum |
| 26 | `TDERR_TooFewSecs` | no sector after the gap |
| 27 | `TDERR_BadSecHdr` | first header found invalid |
| 28 | `TDERR_WriteProt` | `/WPRO` at the time of the physical write |
| 29 | `TDERR_DiskChanged` | disk absent, removed during the write, or `iotd_Count` exceeded |
| 35 | `TDERR_PostReset` | write requested after the announcement of a keyboard reset |

(The assignment of codes 21–27 to the exact decoding cases is [O]; their descriptions reuse the public names.)

---

## 6. What distinguishes a real drive from an emulator

1. **ADF image**: FS-UAE re-decodes the written track into sectors and keeps only the data; the gap, the
   end overlap, the trailing word, the clocks and the precompensation leave no trace there. A
   malformed track may look "well written". On a real floppy, every bit counts. [O] (probe) / [D]
2. **Track length**: the emulator models a revolution of 101,344 cells (12,668 bytes): the end of
   the write overlaps ≈ 962 bytes of the gap (probe: start at position 12,307, end at 20,000 modulo the track).
   A real drive at 300 rpm overlaps ≈ 1130 bytes, and its speed varies by a few %. A track image
   shorter than the one in §2.1 (gap too short) can pass under emulation and overwrite the first sector on
   a fast drive. [O] (probe) / [D]
3. **Precompensation** has no effect in emulation; on a real floppy, the absence of 140 ns on the inner
   tracks (> 80) degrades read-back reliability (especially on other drives). [D]
4. **Settle after seek (15 ms) and spin-up (500 ms)**: no effect in emulation; on real hardware, writing
   while the head is settling or before the speed is reached produces an off-centre or too
   long/short track, unreadable later (worse than a failed read, because the old data is lost). [D]
5. **DMA cut-off**: the emulator does not care when DSKLEN goes back to `$4000`; on real Paula,
   cutting right after DSKBLK can truncate the end. The driver waits 2 ms and places a sacrificial
   trailing word. [D]
6. **`/WPRO` and `/CHNG`** are only valid with the drive **selected**; the driver selects, waits 1 ms,
   then tests. An emulator may return the correct value even without selection. [D]
   (The probe did not manage to present a protected floppy under FS-UAE: neither `uae_floppy0wp`, nor
   `floppy_write_protect`, nor a read-only ADF changed `/WPRO` as seen by the ROM.)
7. **Prior read**: a marginal real disk makes `CMD_WRITE` fail (after 11 reads and 2
   recalibrations, several seconds) even if the caller rewrites the whole track; an emulator always reads
   perfectly. [D]
8. **Durations**: on real hardware a track write lasts 218 ms + 2 ms, the prior read ~236 ms per
   attempt; in non-cycle-exact emulation these durations may be shortened. No guard delay may be
   shorter. [D]
9. **Index interrupt** (`TD_RAWWRITE` + `IOTDF_INDEXSYNC`): depends on the real index signal (CIA-B FLAG). [D]

---

## 7. Relation to the read spec

- §3.3 of `trackdisk-official-timing.md` clarified: the "2000 µs delay around the flush" is **after**
  DSKBLK and **before** DSKLEN ← `$4000`; the thresholds are **track numbers** (cyl×2+side), threshold 80
  inclusive.
- The ADKCON `$0600`/`$9100` teardown from the read spec only happens on acquisition of the channel when another
  user had taken it in the meantime, not on every transfer. [O]
- Raw read: 7358 words (14,716 bytes), ADKCON `$1100` or `$3100`. [O] (probe)

---

## 8. Test vectors (probe, real ROM, FS-UAE)

Blank OFS floppy, unit 0, CHIP buffer. `io_Actual` preloaded with `$DEADBEEF`.

| Step | Request | io_Error | io_Actual | 1st long of the buffer after |
|------|---------|---------:|----------:|------------------|
| A | READ block 1100 (track 100) | 0 | 512 | `00000000` |
| B | WRITE block 1100, pattern `11111111` | 0 | 512 | — |
| C | CLEAR | 0 | unchanged | — |
| D | READ block 1100 | 0 | 512 | `00000000` (B discarded) |
| E/F | WRITE `22222222` then UPDATE | 0 / 0 | 512 / unchanged | — |
| g/G | CLEAR then READ | 0 / 0 | — / 512 | `22222222` (written) |
| H/h/i/I | WRITE length 0 `33333333`, UPDATE, CLEAR, READ | 0 | 512 (H) | `33333333` (one sector written) |
| J/j | WRITE block 220 (track 20) + UPDATE | 0 | 512 | log: ADKCON `$1100` |
| K | FORMAT length 512 | −4 | unchanged | — |
| L/l | FORMAT track 158, pattern `55555555`, then READ | 0 / 0 | unchanged / 512 | `55555555` |
| M | PROTSTATUS | 0 | 0 | — |
| N | WRITE offset 100 | −4 | 0 | — |
| O | MOTOR 0 | 0 | 0 (PROTSTATUS had switched it off) | — |

Disk log: all writes `LEN=1A9F (6815)`, DSKPT = start of the track buffer (gap); reads
`LEN=1CBE (7358)`, DSKPT = buffer + 1664 bytes.

---

## 9. Open points

1. **Write protection not seen running**: the 28 codes (`CMD_UPDATE`, flush, `TD_FORMAT`) and the
   `io_Actual` ≠ 0 of `TD_PROTSTATUS` rest on reading the ROM, since FS-UAE could not present a
   protected disk (§6.6). To be confirmed on WinUAE or on the real A500.
2. **Exact moment of DSKBLK when writing** on real Paula (last word fetched by the DMA or last bit
   shifted out): the role of the 2 ms delay and of the trailing word is [D].
3. **Real drive speed**: the +4.4 % / −8.3 % margins of §2.1 are computed for an exact 2 µs
   cell; the spread of real drives has not been measured.
4. **Buffer after a failed `TD_FORMAT`**: the buffer then holds the format image but keeps the track
   number it had before (it is only invalidated on success); a read of that old track
   could return wrong data. [D], not probed; probable V34 defect, not to be reproduced.
5. **Dirty buffer and disk change**: since the buffer is not invalidated, a flush after a
   change would write the old floppy's data onto the new one, unless the file system issues `CMD_CLEAR`.
   The behaviour of the DOS 1.3 handler on this point is not established here.
6. **Size of the track buffer** and origin of its allocation (disk.resource / CHIP memory) not recorded in
   detail; only the layout (gap at offset 4 of the buffer, read DMA at +1668 from the start of the buffer) is
   established.

## Clean-room review

Review of 2026-10-29.

- [x] No 68000 instruction sequence transcribed or paraphrased, no disassembly excerpt,
  no ROM routine address: only hardware registers (`$BFD100`, DSKLEN, DSKPT, ADKCON,
  INTENA/INTREQ), written values and durations.
- [x] The sequence in §3 is the order of **observable hardware accesses** (partly verified by the
  emulator's disk log); §5 describes the commands by their inputs/outputs and effects.
- [x] No ROM data beyond the format: the track image (gap, `$4489`, info, checksums, MFM
  clocks) is the **public Amiga floppy format**, observable on any written disk; precompensation
  thresholds and drive identifiers are behavioural constants.
- [x] The probe cited (`tests/tdwrite.s`) is author code.
