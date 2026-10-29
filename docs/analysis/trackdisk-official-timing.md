# trackdisk-official-timing.md — Track read behaviour & timing (trackdisk.device V34.1, ROM `kick34005.A500`)

> **ANALYSIS track ("dirty").** Facts derived SOLELY from reading the proprietary ROM
> (radare2, 68000 big-endian, base `$FC0000`). This document describes **BEHAVIOUR** (sequence
> of operations, order of register accesses, **durations**) and the **ABI layout** (unit field
> offsets, constant values). **No instruction sequence is reproduced**: no
> disassembly, no 68k code excerpt, no ROM routine address. Hardware register addresses/values
> and timing constants are **hardware/ABI facts**, not code.
>
> Target: trackdisk.device, `rt_IdString` = `trackdisk 34.1 (18 Aug 1987)`. The overall ROM is **34.5 / Kickstart 1.3**.
>
> Hardware (reminder): CIAB PRB `$BFD100` = `/MTR`(b7) `/SEL0`(b3) `/SIDE`(b2) `/DIR`(b1) `/STEP`(b0),
> all **active-low**. CIAA PRA `$BFE001` = `/RDY`(b5) `/TRACK0`(b4) `/WPRO`(b3) `/CHNG`(b2), all
> active-low. Paula `$DFF0xx`: DSKPT `$20`, DSKLEN `$24`, DSKSYNC `$7E`, ADKCON `$9E`, INTENA `$9A`,
> INTREQ `$9C`, DMACON `$96`.

---

## 0. Overview & driver functions

The driver keeps a **RAM shadow** of the CIAB PRB output byte in the unit structure at
**offset `+0x41`**: every manipulation of the drive lines is done first on the shadow, then the
shadow is written to `$BFD100`. This shadow is the source of truth; since `$BFD100` is *write-only*, the
driver never reads the control port back.

| Function | Behavioural role |
|----------|---------------------|
| Motor | **MOTOR** (on/off + spin-up delay) |
| Recalibrate | **RECALIBRATE** (step towards `/TRACK0`, check, error 30 otherwise) |
| Seek | **SEEK** (to target cylinder: delta, `/DIR`+`/SIDE`, N steps) |
| Step | **ONE STEP** (`/STEP` pulse + inter-step delay) |
| Read | **DMA READ** of a raw block (no WORDSYNC, no precomp) |
| Write | **DMA WRITE** (tests `/WPRO`, applies ADKCON write-precompensation) |
| Delay | **TIMED DELAY** in µs; `≥ 300 µs` → timer.device request, `< 300 µs` → CPU wait |
| Wait for end of DMA | `Wait()` on signal + `GetMsg()` (interrupt, NOT polling) |
| Acquisition | disk.resource **GetUnit** (exclusive acquisition of the disk DMA channel) |
| Release | disk.resource **GiveUnit** (release of the disk DMA channel) |
| DMA teardown | deselect drives + reset ADKCON to the default read mode |
| Per-type defaults | two parameter sets per drive type (step, settle, precomp, number of tracks), see §2.4 |

**External dependencies** (opened at init): `timer.device` (MICROHZ unit, for ALL the timed
delays), `disk.resource` (arbitration of the disk DMA channel shared between df0..df3), `ciab.resource`,
`keyboard.device`. Delays are NEVER CPU busy-loops beyond 300 µs: they go through
a synchronous `timer.device` request (DoIO).

**Major ABI point (DMACON):** the driver **NEVER writes DMACON `$DFF096`** (verified: zero
writes to `$96` in the whole trackdisk module). The master enable of disk DMA
(DMACON `DSKEN` b4 + `DMAEN` b9) is therefore set **globally and only once** elsewhere in the
system; trackdisk merely **arms each transfer via the DSKLEN double write** (see §3).

---

## 1. MOTOR & READY

### 1.1 Motor switch-on

The motor is controlled by `/MTR` (b7) in the `+0x41` shadow, but the **drive's motor latch
happens on the `/SEL` edge** (the Amiga drive latches the state of `/MTR` at the moment `/SEL`
goes active). The routine:

1. Compares the requested `/MTR` state with the current state (shadow). **If unchanged → immediate return, no
   delay.** (Consequence: since DOS leaves the motor on between two accesses, the spin-up delay
   is paid **only once**, not on every read.)
2. Updates `/MTR` in the shadow.
3. Acquires the disk channel (`GetUnit`).
4. Produces the **sequence of two `$BFD100` writes** needed to generate the `/SEL` edge that
   *latches* the new motor state in the drive (first the state with `/SEL` released, then the shadow
   state with `/SEL` asserted).
5. **If the motor has just been switched ON**: **FIXED 500 ms** delay (`500000 µs`, via the timed
   delay → timer.device request). If switching off: no delay.
6. Returns the old motor state (so that the caller can restore it).

### 1.2 Waiting for "ready" — the central fact

**The official trackdisk does NOT wait for `/RDY`. It NEVER queries `/RDY` (CIAA PRA b5).**

- Exhaustive search over the whole ROM: the **only** test of `/RDY` (b5 of `$BFE001`) is
  **outside** trackdisk (disk.resource / exec area). Inside trackdisk.device,
  there is **no** access to bit 5.
- The "ready" after switch-on is therefore a **blind, timed, fixed 500 ms delay**, independent
  of the drive's actual state. It is timer.device (MICROHZ unit) that counts, not a busy-loop.
- `/RDY` on an Amiga drive does not simply mean "motor up to speed": the line is also used
  to clock out the drive's 32-bit ID (when `/SEL` is toggled with the motor off). That ID logic is
  in disk.resource, not in trackdisk's spin-up path — hence the absence of a `/RDY` poll here.

### 1.3 "Timeout" / disk presence

There is no timeout on `/RDY` (since `/RDY` is not read). Drive-related error conditions
come from elsewhere:

- **Disk presence**: tested via `/CHNG` (CIAA PRA **b2**) at the start of each DMA transfer
  (§3). Disk absent/changed → code **29** (`TDERR_DiskChanged`, `$1D`).
- **Positioning**: after recalibrate, if `/TRACK0` (b4) is not reached → code **30**
  (`TDERR_SeekError`, `$1E`).

---

## 2. SEEK & STEP

### 2.1 Sequence of a single step

Observable effects of a step on the control port, in order:

1. Read the `+0x41` shadow (it already contains the wanted `/DIR` direction, set by the caller — see
   §2.3).
2. **Assert `/STEP` low**: one `$BFD100` write with b0 = 0 (and b1/`DIR` + b2/`SIDE` in their
   current state, written in the **same** atomic write).
3. **Pulse hold**: a deliberate very short wait (of the order of **1 µs**, a few
   CPU cycles at 7.09 MHz) between assertion and release.
4. **Release `/STEP` high**: a second `$BFD100` write restoring b0 = 1.
5. **Release the disk channel** (`GiveUnit`) during the settle time that follows.
6. **Inter-step delay** = unit value `+0x2C` = **3000 µs = 3 ms** (default 3.5" drive), via
   a timer.device request.
7. **Re-acquire the channel** (`GetUnit`) and rewrite the shadow to `$BFD100` (stable state, `/STEP`
   high, `/DIR` held).

**Width of the `/STEP` low pulse** = duration of the 2nd CIA write + the short wait inserted,
**deliberate**: it widens the pulse beyond what two back-to-back CIA writes would give.
(The same small delay also separates a `$BFD100` write from a `$BFE001` read-back: this is the
recovery/propagation time of the 8520.)

**Direction setup:** `/DIR` and `/STEP`-low are set in the **same** atomic CIA write ⇒
`/DIR` is valid exactly at the falling edge of `/STEP` (the drive samples `/DIR` on that
edge). There is no *separate* `/DIR` setup delay, but `/DIR` is **stable and held** for
the whole duration of the seek (rewritten after each step), so it is never changed while a pulse is active.

### 2.2 `/TRACK0` detection and recalibrate

- `/TRACK0` = CIAA PRA **b4** (active-low: 0 = head on track 0).
- Recalibrate = set `/DIR` "outwards", then **step** (single steps as in §2.1, hence with
  the 3 ms inter-step delay) until `/TRACK0` is asserted, bounded by a counter derived from the **total
  number of tracks** (unit `+0x36` = **160** tracks = 80 cyl × 2 sides for the default drive).
- After a successful recalibrate/seek: **settle delay = unit value `+0x30` = 15000 µs = 15 ms**
  (via timer.device) **before returning** / reading.
- Failure (`/TRACK0` not reached) → `TDERR_SeekError` = 30.

### 2.3 Seek to a cylinder

1. Current position kept in unit `+0x4C`, encoded `(cyl × 2) | side`.
2. Acquires the disk channel (`GetUnit`).
3. Sets `/SIDE` (b2) according to the target side — immediate `$BFD100` write.
4. Computes the cylinder **delta**; chooses `/DIR` (b1) according to the sign (sets `/DIR` in the
   shadow, **without** a separate `$BFD100` write — it will be applied by the 1st step).
5. Issues **|delta| single steps** (§2.1, hence **3 ms between each step**).
6. After the last step: **15 ms settle** (unit `+0x30`), then releases the channel.

### 2.4 Summary of step/seek durations

| Quantity | Value (default 3.5" drive) | Source |
|----------|------------------------------|--------|
| `/STEP` low pulse width | ≈ 1 µs wait + 1 CIA access (≈ a few µs) | hard-coded |
| `/DIR` setup before the `/STEP` edge | 0 (same CIA write); `/DIR` held for the whole seek | single step |
| **Inter-step delay (step rate)** | **3 ms** (`3000 µs`, unit `+0x2C`) | type 1 defaults |
| **Post-seek / post-recal settle** | **15 ms** (`15000 µs`, unit `+0x30`) | type 1 defaults |
| Number of tracks (recal bound) | 160 | type 1 defaults |
| Alternative drive type | step **6 ms**, settle 15 ms, 80 tracks | type 2 defaults |

---

## 3. DMA READ (WORDSYNC — the most important point)

### 3.1 Central fact: the official read does NOT USE WORDSYNC

Exhaustively verified over the whole trackdisk module:

- **Zero writes to the DSKSYNC register `$DFF07E`.** The driver never loads `$4489` (or anything)
  into DSKSYNC. (The value `$44894489` that appears in the ROM is written into a comparison
  **buffer**, not into the register — it is used for **software** MFM decoding.)
- **WORDSYNC never enabled.** The only ADKCON `$DFF09E` writes in the whole module are:
  (a) the **write-precompensation** in the write path (clearing of the precomp bits, then
  setting of the level according to the cylinder), and (b) the **teardown** (`$0600` = *clear* WORDSYNC+MSBSYNC,
  then `$9100` = *set* MFMPREC+FAST). The "default" mode set
  by trackdisk therefore has **WORDSYNC explicitly at 0**.

**Behavioural consequence:** the official trackdisk reads a **whole raw track, not
hardware-synchronised**, over **more than one revolution** (buffer pre-filled with `$AAAAAAAA` =
MFM gap pattern; DMA length sized to guarantee capture of all sectors whatever
the rotational position), then **finds the `$4489` sync marks in software**
during MFM decoding. It therefore does NOT depend on WORDSYNC hardware alignment.

### 3.2 DMA arming sequence observable on the registers (read)

Order of operations (one raw block read):

1. **Acquire** the disk channel: disk.resource `GetUnit` — blocking as long as another
   drive holds the DMA.
2. Rewrite the `+0x41` shadow to `$BFD100` (refresh the drive selection).
3. **DSKLEN `$DFF024` ← `$4000`**: guarantees disk DMA is **disarmed** (bit15 `DMAEN` = 0) before
   reconfiguration.
4. **1000 µs (1 ms) delay** (timer.device) — stabilisation time after select, **before**
   arming the DMA.
5. **DSKPT `$DFF020` ← buffer address** (long write, DMA pointer).
6. **INTREQ `$DFF09C` ← `$1002`**: clears **pending** disk interrupts (bit12 `DSKSYN`
   + bit1 `DSKBLK`).
7. **INTENA `$DFF09A` ← `$8002`**: `SET | DSKBLK`(b1) → **enables the disk end-of-block interrupt**.
8. **Disk presence test**: `/CHNG` (`$BFE001` b2). Absent → code 29 (`TDERR_DiskChanged`), exit.
9. **Arm the DMA = DSKLEN `$DFF024` DOUBLE WRITE**: the **same** value `$8000 | (length_bytes / 2)`
   is written **twice in a row**. `$8000` = bit15 `DMAEN`; the low value is the **WORD
   count** (DSKLEN counts words, hence the `/2`). The double write is the mandatory hardware
   trigger mechanism (protection of the disk hardware against stray DMA).
10. **Wait for the end**: `Wait()` on the **task's signal** (mask `$400`)
    then `GetMsg()` on the unit port `+0xAE`. **This is interrupt-driven, not polling**: the
    `DSKBLK` interrupt server signals the task, which sleeps in `Wait()` in the meantime.
11. **Teardown**: INTENA ← `$0002` (clear DSKBLK), **DSKLEN ← `$4000`** (DMA disarmed).
12. **Re-test `/CHNG`** (the disk may have been removed during the transfer) → code 29, otherwise success.
13. Release the channel (`GiveUnit`) and reset ADKCON to the default mode (WORDSYNC off).

### 3.3 Write — for the record

Same skeleton, plus: `/WPRO` test (`$BFE001` b3) before writing; **write-precompensation** set
in ADKCON according to the current cylinder (unit thresholds `+0x26`/`+0x28`/`+0x2A`, default 1st threshold at
cyl 40, i.e. `$4C` = cyl×2 = 80); DSKLEN armed with bit14 (`WRITE`) in addition to `DMAEN`; and an
**extra 2000 µs (2 ms) delay** around the write DMA flush.

### 3.4 Summary of the DMA read sequence/timing

| Step | Register / action | Value | Note |
|-------|-------------------|--------|------|
| Disarm | DSKLEN `$24` | `$4000` | DMAEN=0 |
| **Wait** | timer.device | **1 ms** | settle before arming |
| Pointer | DSKPT `$20` | buffer | long |
| Clear IRQ | INTREQ `$9C` | `$1002` | pending DSKSYN+DSKBLK |
| Enable IRQ | INTENA `$9A` | `$8002` | SET \| DSKBLK |
| Presence | `/CHNG` `$BFE001` b2 | — | absent → err 29 |
| **Arm** | DSKLEN `$24` | `$8000 \| words` **×2** | **mandatory double write** |
| End | Wait(signal `$400`)+GetMsg | — | **interrupt, no INTREQR polling** |
| Disarm | INTENA `$9A` / DSKLEN `$24` | `$0002` / `$4000` | teardown |
| ADKCON | `$9E` | `$0600` then `$9100` | **WORDSYNC reset to 0**, MFMPREC+FAST |
| DMACON `$96` | — | **never written** | disk DMA master enable = global, elsewhere |

---

## 4. Timing constants (summary)

| Parameter | Official value | Mechanism | Offset/source |
|-----------|-------------------|-----------|---------------|
| Motor spin-up (on) | **500 ms** fixed | timer.device, blind (no `/RDY`) | constant 500000 µs |
| `/RDY` wait | **none** | — | `/RDY` never read in trackdisk |
| `/STEP` pulse width | ≈ 1 µs + CIA access | hard-coded | single step |
| Step rate (inter-step) | **3 ms** (3000 µs) | timer.device | unit `+0x2C`, type 1 defaults |
| Post-seek/recal settle | **15 ms** (15000 µs) | timer.device | unit `+0x30`, type 1 defaults |
| Settle before DMA arming | **1 ms** (1000 µs) | timer.device | constant 1000 µs |
| Busy-loop vs timer threshold | 300 µs | timed delay | `< 300 µs` → CPU wait |
| End of DMA | `DSKBLK` interrupt + `Wait` | exec | signal `$400` |
| Number of tracks | 160 (80 cyl × 2) | — | unit `+0x36` |

---

## 5. Probable differences that break on a timing-exact emulator (WinUAE)

Comparison with our known naive implementation (`/STEP` pulse ≈ 1.4 µs = two back-to-back CIA
writes; READY wait = busy-loop polling `/RDY` ≈ 0.5 s with no fixed motor delay; no direction setup
delay; read via hardware WORDSYNC + DSKSYNC = `$4489`). In decreasing order of risk:

1. **Missing inter-step settle (the most serious).** The official one waits **3 ms after EACH step**
   (timer.device). Our seek chains the pulses almost back-to-back. On timing-exact WinUAE, the
   emulated head does not "catch up" with its position: stepping faster than ~3 ms/step makes the head
   position model lose track, and the next read lands on the **wrong cylinder** → wrong
   data / hang (exactly the profile of the bug already seen: short seek that hangs, long seek that passes).

2. **Missing 15 ms post-seek settle.** The official one waits **15 ms** after the last step before
   reading. Reading immediately = reading while the head is still settling → intermittently unreadable
   sectors (depends on the cylinder and the rotational position).

3. **Motor wait: polling `/RDY` instead of a fixed 500 ms delay.** The official one NEVER reads
   `/RDY` and applies a **blind 500 ms delay** only on the switch-on edge. A busy-poll of `/RDY`
   on WinUAE can (a) end too early (`/RDY` semantics of the emulated drive ≠ "motor up to
   speed" — `/RDY` also encodes the drive ID), leading to a read before rotational
   stabilisation, or (b) never see the expected level depending on the modelling → hang. Corollary:
   our impl risks paying the wait again on every access, whereas the official one only pays it on a
   motor state change.

4. **Hardware WORDSYNC vs raw read + software sync.** The official one reads a **complete raw
   track (> 1 revolution), WORDSYNC OFF, DSKSYNC never written**, and finds `$4489` in software.
   Our WORDSYNC read requires that (a) DSKSYNC really contains `$4489`, (b) the DMA is armed BEFORE
   the mark passes under the head, (c) the length really covers a sector after sync.
   If the length is exactly one track and the arming misses the sync window, sectors are
   lost — a defect invisible on a "loose" emulator that aligns everything, but exposed by exact
   rotational timing. (Official approach = robust by construction; the WORDSYNC approach is
   viable but only if the arming and the length are flawless.)

5. **`/STEP` pulse too narrow + no stabilisation delay before DMA arming.** The official one
   deliberately widens the `/STEP` pulse (guaranteed width) and waits **1 ms after the select,
   before arming the DMA** (steps 3–4 of §3.2). An impl that issues a back-to-back pulse without padding
   and/or arms the DMA immediately after the select may, under exact timing, see the drive miss the
   step and/or the DMA start on a bus not yet stabilised.

**ABI detail not to forget (possible cause of "nothing reads"):** trackdisk **never enables
DMACON itself** — it assumes `DSKEN`+`DMAEN` are already set globally and only arms via the
**DSKLEN double write**. An impl that relied on trackdisk to enable DMACON, or that
forgot the **double** DSKLEN write, would get no transfer.

## Clean-room review

Review of 2026-10-29.

- [x] **Fixed**: removed all ROM addresses (about fifty): ROMTag, `rt_Init` and
  module bounds, "routine map" (motor, seek, step, read, write, delay, DMA wait,
  GetUnit/GiveUnit, teardown), per-drive-type default tables, locations of the ADKCON
  writes and of the delay constants, location of the `/RDY` test outside trackdisk. The map is
  replaced by a list of functions by role.
- [x] **Fixed**: the description of the `/STEP` pulse cited the instructions themselves ("two
  `NOP`s", idiom "write CIA → 2 NOP → CIA access"); reworded as an observable duration (≈ 1 µs
  deliberate wait) without naming any instruction. Headings "exact sequence / routine" reworded as
  observable effects on the control port.
- [x] Kept (observable hardware behaviour, verifiable on an emulator by tracing register
  accesses): order of the `$BFD100`/DSKLEN/DSKPT/INTREQ/INTENA/ADKCON writes and their values,
  durations (500 ms, 3 ms, 15 ms, 1 ms, 2 ms, 300 µs threshold), public error codes, unit field
  offsets (private structure, layout).
- [x] No ROM data beyond these constants (the gap pattern `$AAAAAAAA` and the mark `$4489`
  are values of the public Amiga MFM format).
