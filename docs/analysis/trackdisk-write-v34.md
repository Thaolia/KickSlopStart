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
tracks 100 and 158 → `$3100`. [O] (probe) Boundary probe (blocks 880 and 891 read, written back unchanged,
then `CMD_UPDATE`): track **80** (cyl 40 side 0) → ADKCON `$1100` (no precompensation), track **81** (cyl 40
side 1) → `$3100` (140 ns). The first precompensated track of a 3.5" unit is therefore **81**; the test is
"track > threshold1", not "track ≥ threshold1". [O] (probe)

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
| Protection | read **live** on `/WPRO`, drive selected, just before arming; error 28 at the **flush**, never at the `CMD_WRITE` itself | [O] (probe, Amiberry 2026-11-10, §10.1) |
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
| 9 | `TD_MOTOR` | `io_Length` 0 = off, non-zero = on; `io_Actual` = previous state: **`$FF` (non-zero) if the motor was on**, 0 if it was off (`io_Actual` is the long `$000000FF` or 0, `io_Error` 0). Confirmed by probe 2026-11-10, with the no-disk case and the absence of a motor-off timer: `trackdisk-raw-changeint-v34.md` §13 |
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

Disk absent → 29, `io_Actual` untouched, motor not touched. Otherwise: **switches the motor on** (500 ms if off), reads
`/WPRO`, returns `io_Actual` ≠ 0 if protected (`$FF`), 0 otherwise, then **switches the motor off in every case**.
[O] (probe M then O: `TD_MOTOR` returns "was off"; `$FF` seen on a protected disk and 29 without a disk on
2026-11-10, §10.1)

### 5.6 Error codes met when writing

| Code | Name | Origin |
|-----:|-----|---------|
| −3 | `IOERR_NOCMD` | unhandled command |
| −4 | `IOERR_BADLENGTH` | offset/length not aligned or beyond the disk |
| 21 | `TDERR_NoSecHdr` | prior read: no `$4489 $4489` found in the raw track |
| 22 | `TDERR_BadSecPreamble` | preamble or `$4489 $4489` missing at the expected place of a later sector |
| 23 | `TDERR_BadSecID` | later sector: format byte, track or sector number wrong |
| 24 | `TDERR_BadHdrSum` | later sector: header checksum |
| 25 | `TDERR_BadSecSum` | data checksum of **any** sector of the track |
| 26 | `TDERR_TooFewSecs` | fewer than 11 sectors found |
| 27 | `TDERR_BadSecHdr` | the **first** header found is invalid (checksum or ID) |
| 28 | `TDERR_WriteProt` | `/WPRO` at the time of the physical write |
| 29 | `TDERR_DiskChanged` | disk absent, removed during the write, or `iotd_Count` exceeded |
| 35 | `TDERR_PostReset` | write requested after the announcement of a keyboard reset |

(Codes 21–27 come from the read that precedes a write; which track damage gives which code, and the order of the
checks, were measured on 2026-11-10 with damaged raw tracks: §10.3.)

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
| P/Q/R | READ block 880 (track 80), WRITE it back unchanged, UPDATE | 0 / 0 / 0 | 512 / 512 / unchanged | `00000002`; log: ADKCON `$1100` |
| T/U/V | READ block 891 (track 81), WRITE it back unchanged, UPDATE | 0 / 0 / 0 | 512 / 512 / unchanged | `00000000`; log: ADKCON `$3100` |
| K | FORMAT length 512 | −4 | unchanged | — |
| L/l | FORMAT track 158, pattern `55555555`, then READ | 0 / 0 | unchanged / 512 | `55555555` |
| M | PROTSTATUS | 0 | 0 | — |
| N | WRITE offset 100 | −4 | 0 | — |
| O | MOTOR 0 | 0 | 0 (PROTSTATUS had switched it off) | — |

Disk log: all writes `LEN=1A9F (6815)`, DSKPT = start of the track buffer (gap); reads
`LEN=1CBE (7358)`, DSKPT = buffer + 1664 bytes.
Track writes in the disk log, in order (run of 2026-11-02): track 100 `$3100` (UPDATE F), track 100 again
`$3100` (UPDATE h, the only flush between F and j: the zero-length WRITE H dirtied the track buffer, so the
flush really writes the track),
track 20 `$1100` (j), track 80 `$1100` (R), track 81 `$3100` (V), track 158 `$3100` (FORMAT L): six track
writes. [O] (probe)

---

## 9. Open points

1. ~~Write protection not seen running~~: seen on 2026-11-10 under Amiberry with a read-only image (§10.1).
   Still not seen on a real A500.
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

## 10. Black-box runs of 2026-11-10 (Amiberry, real ROM)

Method common to this section: the author probe `tests/tdwrite.s` (unchanged; its steps A–O are listed in §8),
run on the real ROM under Amiberry v8.4.2, cycle-exact A500 preset. Either the probe disk boots and runs it, or
it is first copied to `RAM:` and started from there, so that a test floppy can be inserted afterwards with the
emulator's floppy command and the DF0: file system is idle (no transfer for > 15 s) when the probe runs. Some
requests were rewritten in flight with the debugger at the probe's **own** DoIO call site (command, length,
`iotd_Count`, `iotd_SecLabel`); no breakpoint was put in the ROM. Raw-track test disks are Amiberry extended
ADFs (`UAE-1ADF`) whose track 100 is a raw MFM track produced by a throwaway generator, every other track
being a normal AmigaDOS track.

### 10.1 Write protection [O]

Protected disk = read-only image given to the emulator as `floppy0` (not `--adf`, whose copy is writable).
Same probe, same order as §8:

| Step | Protected disk | (writable disk, for comparison) |
|---|---|---|
| A `CMD_READ` 1100 | 0, 512 | 0, 512 |
| B `CMD_WRITE` 1100 (into the track buffer) | **0, 512** | 0, 512 |
| C `CMD_CLEAR`, D `CMD_READ` | 0; 0, 512, old data | same |
| E `CMD_WRITE`, F **`CMD_UPDATE`** | 0, 512; **28**, `io_Actual` untouched | 0; 0 |
| g `CMD_CLEAR`, G `CMD_READ` | 0; 0, 512, **old data** (nothing was written) | data of E |
| H `CMD_WRITE` length 0, h `CMD_UPDATE` | 0, 512; **28** | 0; 0 |
| J `CMD_WRITE` 220 (another track), j `CMD_UPDATE` | 0, 512; **28** | 0; 0 |
| P `CMD_READ` 880 (another track) | **28, `io_Actual` 0**, nothing read | 0, 512 |
| Q `CMD_WRITE` 880, R `CMD_UPDATE` | **28, 0**; 28 | 0; 0 |
| T, U, V (track 81, same pattern) | 28 each (`io_Actual` 0 for T and U, untouched for V) | 0 each |
| K `TD_FORMAT` length 512 | **28** (not −4) | −4 |
| L `TD_FORMAT` track 158 | **28**, `io_Actual` untouched | 0 |
| l `CMD_READ` track 158 | **0, 512**, old data (track not formatted) | 0, 512, format pattern |
| M `TD_PROTSTATUS` | 0, **`$FF`** | 0, 0 |
| N `CMD_WRITE` offset 100 | −4, 0 | −4, 0 |

Rules [O]:
- `CMD_WRITE` never checks the protection; it only fills the track buffer. The error **28** comes from the
  physical write: `CMD_UPDATE`, and the implicit flush done before another track is loaded.
- After a failed flush the buffer **stays dirty**, and every later request that needs another track tries the
  flush again and fails with **28** before doing anything: `CMD_READ` of another track returns 28 with
  `io_Actual` 0 and reads nothing, `CMD_WRITE` likewise. The unit is stuck until `CMD_CLEAR` (or a
  `TD_FORMAT`, below) drops the dirty track.
- `TD_FORMAT` flushes a dirty buffer **before** checking its arguments: with a dirty buffer on a protected
  disk, a `TD_FORMAT` of a bad length returned 28, not −4. The dirty data is **lost** at that point (the buffer
  is marked clean before the flush, §5.3): the next `TD_FORMAT` failed with 28 on its own write, and the next
  read of another track succeeded without any flush.
- `TD_PROTSTATUS` returns `$FF` in `io_Actual` on a protected disk, 0 on a writable one; without a disk 29 with
  `io_Actual` untouched (probe of `trackdisk-raw-changeint-v34.md` §13).
- File system and dos level on a protected floppy: `rom-filesystem-v34.md` §2.3 (214 for every modifying
  packet, dos requester "Volume / <name> / is write protected" for some of them, none for SET_PROTECT /
  SET_DATE / SET_COMMENT).
- Emulator note [U]: Amiberry's `floppyNwp` option did not protect the disk; a read-only image file does.

### 10.2 Sector labels (`ETD_READ` / `ETD_WRITE`, `iotd_SecLabel`) [O]

Observed by dumping the unit's MFM track buffer (pointer at unit `+$52`, `trackdisk-raw-changeint-v34.md` §10)
with the debugger after each request and decoding it with the public sector layout (§2.2).

| Request | Label field of the sector in the track buffer afterwards | Caller's label buffer |
|---|---|---|
| `ETD_READ` (`$8002`), `iotd_SecLabel` → 16 bytes pre-filled with `$A5` | unchanged (as read from the disk: zeros, or `11223344 55667788 99AABBCC DDEEFF00` from a raw test track) | **not written** (still `$A5…`), both when the track came from the disk and when it was already cached |
| `ETD_WRITE` (`$8003`), `iotd_SecLabel` → "trackdisk.device", or → `01234567 89ABCDEF FEDCBA98 76543210`, or → 16 zero bytes | **`AAAAAAAA AAAAAAAA AAAAAAAA AAAAAAAA`** in all three cases | — |
| `ETD_WRITE`, `iotd_SecLabel` = 0 | unchanged (a label `11223344…` read from the disk stayed) | — |
| `CMD_WRITE` (`3`) over a sector whose buffer label was `AAAAAAAA…` | unchanged | — |
| `TD_FORMAT` | zeros (§5.4) [O from §5.4; not re-dumped] | — |

- In the MFM image the written label is: odd-bit longs `$55555555` (all data bits 1), even-bit longs all data
  bits 0, with normal clocks; the header checksum is recomputed over it and is valid (all 11 headers checked).
  So V34 `ETD_WRITE` with a non-null label pointer writes a **constant** label whose value does not depend on
  the caller's 16 bytes; with a null pointer it leaves the label that was there. [O for the three sources and
  the null case; "constant" is the generalisation, D]
- `ETD_READ` **never returns labels** in V34: with a non-NULL `iotd_SecLabel` the read succeeded and none of the
  16 bytes was written, even for a sector whose label on the disk was `11223344…` (raw test track). `ETD_READ`
  with a NULL pointer was not tried [?]; since the pointer is not used on reads, nothing different is expected [D].
- `CMD_READ` ignores labels: a raw track whose 11 labels are non-zero (header checksums computed over them) reads
  without error and gives the right data.
- Labels survive on disk only as far as the medium keeps them: Amiberry writes a standard ADF track as sector
  data only (labels lost), and an extended-ADF track whose labels are non-zero as a raw MFM track [U, Amiberry
  `disk.cpp`].
- An implementation that has no label storage (plain ADF) matches 1.3 for every reader: no 1.3 read path
  returns a label. To match the written MFM exactly, `ETD_WRITE` with a non-null pointer puts the constant label
  above in the sector, and `CMD_WRITE` / `ETD_WRITE` with NULL keep the existing one.

### 10.3 Read decoding and error codes 21–27 [O]

Track 100 of the test disk was a raw MFM track built to the layout of §2.2 (correct clocks, 11 sectors, gap of
`$AAAA` words, 12,668 bytes in all), then damaged in one way per disk. The probe's first step (`CMD_READ` of block
1100 = sector 0 of track 100) and its later steps on that track (B, D, E, G, H, I, each preceded by a fresh read)
give 7 results per disk. Each result is the code of the **last** of the driver's 11 read attempts (§5.2 point 4),
and the read starts at a random rotational position each time, so the "first sector found" varies from one
result to the next.

| Damage on track 100 (all other sectors intact) | Codes seen (7 results) |
|---|---|
| none (control); also with non-zero labels; also a gap of only 20 bytes | 0 |
| no `$4489` at all | 21 ×7 |
| every sector with a single `$4489` instead of two | 21 ×6, 27 ×1 |
| sector 3: single `$4489` | 22 ×7 |
| sector 3: first preamble word `$4489` / `$5555`, or second preamble word `$5555` | 22 ×7 (each) |
| 2 extra bytes (`$AAAA`) inserted between sectors 3 and 4 | 22 ×2, 0 ×5 |
| sector 0: header checksum wrong | 24 ×6, 27 ×1 |
| sector 5: header checksum wrong | 24 ×7 |
| every header checksum wrong | 27 ×7 |
| sector 0: format byte `$FE` | 23 ×6, 27 ×1 |
| sector 5: format byte `$FE` | 23 ×7 |
| sector 0: track byte 99 | 27 ×2, 23 ×5 |
| sector 5: track byte 99 | 23 ×7 |
| every format byte `$FE`, or every track byte 99 | 27 ×7 |
| sector 5 numbered 0 (two sectors 0, no sector 5) / numbered 11 | 23 ×7 |
| sectors 4 and 5 swapped (both valid) | 23 ×7 |
| sector 5 missing (10 sectors) | 26 ×4, 23 ×3 |
| "sectors before the gap" byte wrong (sector 0 = 3; all = 5; sector 10 = 3; sector 10 = 0) | 0 |
| sector 0: data checksum wrong | 25 ×7 |
| sector 5: data checksum wrong (sector 0 read) | **25 ×7** |
| every data checksum wrong | 25 ×7 |
| two defects in different sectors: preamble of 3 + data sum of 0 | 22 ×2, 25 ×5 |
| header sum of 5 + data sum of 0 | 24 ×3, 25 ×2, 27 ×2 |
| preamble of 3 + header sum of 5 | 22 ×6, 24 ×1 |
| format byte of 5 + header sum of 6 | 23 ×7 |
| header sum of 5 + track byte of 7 | 24 ×4, 23 ×2, 27 ×1 |
| two defects in the **same** sector 5: format byte + header sum | 24 ×7 |
| header sum + data sum | 24 ×7 |
| track byte + data sum | 23 ×7 |

Decoder rules an implementation can follow (they reproduce every row above) [O for the outcomes; the rule is
the simplest one consistent with them, D]:
1. The raw track is searched in software for `$4489 $4489` (no hardware sync, `trackdisk-official-timing.md`
   §3.1). None found → **21**.
2. The first sector found is checked: header checksum, format byte `$FF`, track = the track read (and, by
   extension, a sector number < 11 [D]). Any failure → **27** (never 23/24 for the first sector; the order of
   these checks cannot be seen since they share the code). Its data checksum is checked like the others
   (rule 3), a failure gives 25, not 27.
3. The following sectors are taken at the fixed 1088-byte pitch, in rotation order, across the gap after the
   last sector before it (a 2-byte shift between two sectors gives 22 when the read crosses it, a 20-byte gap
   is fine). For each one, in this order: the two preamble words must be zero data bytes and be followed by
   `$4489 $4489`, else **22**; header checksum, else **24**; format byte, track, and sector number = previous
   sector's number + 1, else **23**; data checksum, else **25**.
4. Every sector of the track is checked, not only the requested one: a bad data checksum in sector 5 fails a
   read of sector 0 with 25. The first failure met in rotation order ends the attempt with its code.
5. Fewer than 11 sectors → **26** (seen with one sector missing, for the rotations where the numbering check
   did not fire first) [O for the outcome, ? for the exact boundary between 26 and 23].
6. The "sectors before the gap" byte is not checked (0, 3 and 5 instead of the right value were accepted); the
   labels are covered only by the header checksum.

Exact rotation-dependent mixes (which code wins in a given attempt) cannot be reproduced on an emulator that
serves the track from its start; what matters is the set of codes and the per-sector order of checks. The
26-versus-23 rule for a missing sector and the handling of a damaged **first** preamble are not settled [?].

### 10.4 Test vectors (2026-11-10)

| Setup | Expected (real 1.3) |
|---|---|
| read-only image, `CMD_WRITE` then `CMD_UPDATE` | 0, then 28; `CMD_CLEAR` + `CMD_READ` → old data |
| same, then `CMD_READ` of another track without `CMD_CLEAR` | 28, `io_Actual` 0 |
| same, `TD_FORMAT` length 512 with a dirty buffer | 28 (−4 on a writable disk) |
| read-only image, `TD_PROTSTATUS` | 0, `io_Actual` `$FF` |
| `ETD_READ` with `iotd_SecLabel` → buffer | buffer untouched, data read |
| `ETD_WRITE` with `iotd_SecLabel` → any 16 bytes, then dump the MFM sector | label longs `$AAAAAAAA` ×4, header checksum valid |
| raw track: sector 5 data checksum wrong, `CMD_READ` of sector 0 | 25 |
| raw track: sectors 4 and 5 swapped | 23 |
| raw track: every header checksum wrong | 27 |
| raw track: sector 3 preamble or sync damaged | 22 |

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
- [x] 2026-11-10 (§4, §5.1, §5.5, §5.6, §9, §10): black-box runs of the author probe on the real ROM, requests
  rewritten in flight at the probe's own call site; MFM buffer contents decoded with the public format; damaged
  test tracks built by a throwaway generator from the public format. Results are codes, `io_Actual` values and
  label longs; no ROM address, no transcribed code. The decoder rules of §10.3 are inferred from outcomes only.
