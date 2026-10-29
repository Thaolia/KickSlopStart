# timer.device 1.3 (34.1) and CIA sharing — behavioural spec

> **ANALYSIS** track (dirty). Sources: ROM `assets/kick34005.A500` (read-only; temporary
> disassembly outside the repository), black-box probe `tests/timerprobe.s` on the real ROM (FS-UAE A500 PAL,
> 512 KB chip, Workbench 1.3.3). **Behavioural** specification: resources, hardware registers,
> values, order, conditions, timings. ROM addresses are analysis landmarks, not recipes.
> Legend: **[R]** ROM analysis, **[S]** probe on the real ROM, **[D]** public doc (AutoDocs/RKRM/
> includes), **[I]** inferred.
> Complements `keyboard-handshake-v34.md` (ciaa.resource, keyboard), `trackdisk-official-timing.md`
> (disk delays), `boot-clock-v34.md` (time at boot), `monkey-startup.md` §5 (vector $78).

---

## 0. Short answer

- **UNIT_MICROHZ** = **CIA-A timer B**, obtained via `ciaa.resource` **AddICRVector(bit 1 = TB)** ⇒
  **level 2 (PORTS)** interrupt. **One-shot** mode, chunks of **≤ 65535 E ticks** (≤ 91 541 µs).
  **No** dependency on level 6: hijacking `$78` changes nothing about the delays [R][S].
- **UNIT_VBLANK** = a **VERTB server** (level 3, exec chain, pri 0); no CIA [R][S].
- **System clock** = software base + **CIA-A TOD** (mains tick 50/60 Hz); resolution 20 ms
  (PAL 50 Hz) + **1 µs added on every read** ⇒ strictly increasing [R][S].
- At boot, the 1.3 system uses **no CIA-B timer** and **not CIA-A timer A**. Level 6
  (EXTER): only the `ciab.resource` server (TOD alarm for graphics, FLG/index for
  disk.resource) [R][S].
- trackdisk: **all its delays go through timer.device unit MICROHZ** (DoIO); in addition it has a
  periodic **VBLANK** request (disk-change polling) [R].

---

## 1. CIA resources and timer mode

### 1.1 Acquisition [R][S]

| Step (init, ROMTag pri 50, after cia.resource pri 80) | Detail |
|---|---|
| OpenResource(`"ciaa.resource"`) | failure ⇒ Alert **$15058020** (AN_TimerDev\|AG_OpenRes\|AO_CIARsrc) and init aborted |
| MakeLibrary (positive size $D6) | failure ⇒ Alert **$15020000** |
| ExecBase **Quantum** (+$120) := 16 and **Elapsed** (+$122) := 16 | it is timer.device, not exec, that sets the 16-frame quantum |
| **AddIntServer(INTB_VERTB = 5)** | server named `"timer.device"`, pri 0, is_Data = VBLANK unit |
| INTENA := $8020 | enables VERTB |
| **AddICRVector(CIAICRB_TB = 1)** on ciaa.resource | Interrupt named `"timer.device"`, LN_PRI 30 (no effect), is_Data = MICROHZ unit |
| **Return value of AddICRVector ignored** | if the bit were already taken, MICROHZ would be silent with no error (does not happen at boot: nobody else takes it) |
| Mains calibration (§1.3), then AddDevice | — |

**CIA-A timer A** and **all of CIA-B** are never touched by timer.device [R: the module's only CIA
writes = CIA-A CRB, TBLO, TBHI and TOD].

### 1.2 CIA-A timer B mode [R][S]

| Register | Value / usage |
|---|---|
| CRB ($BFEF01) | **$08** permanently outside calibration: RUNMODE = one-shot, INMODE = φ2 (E-clock), START = 0 at rest. Bit 7 (ALARM) = 0 |
| Starting a chunk | write **TBLO then TBHI** ($BFE601/$BFE701): in one-shot mode, writing the high byte loads the latch and **starts** the countdown (no CRB write) |
| Stop | setting **only the START bit** of CRB to 0 (read-modify-write) |
| End of a chunk | underflow ⇒ ICR bit TB ⇒ PORTS ⇒ ciaa.resource server ⇒ timer.device handler; the timer stops by itself (one-shot) |
| Observed idle value | TB read = **$02CB** (= 715 = last loaded latch, 1000 µs): the counter keeps the latch after underflow [S] |

Snapshot after boot [S]: `CIAA cra.crb = $00/$08`, TA = $FFFF (never loaded), enabled ICR mask
**$0A** (TB + SP). Bit 1 handler: `timer.device`, is_Code inside timer.device's code.

### 1.3 Mains frequency calibration (init, under Disable) [R][S]

1. CIA-A TOD reset to 0 (writes to hours, then minutes, then LSB: the latter restarts the TOD).
2. CRB := $08, TBLO := $FF, TBHI := $FF (the high write starts a $FFFF countdown).
3. Wait for a **change** of the TOD low byte. Safeguard: if TBHI drops below $80 (more than
   32 768 E ticks ≈ 46 ms without a TOD tick) ⇒ Alert **$15000002** (recoverable) then branch to "60 Hz" on
   an unbalanced stack — degraded case, see §9.
4. CRB := $19 (START | one-shot | LOAD): countdown from $FFFF.
5. Wait for the next TOD tick (same safeguard), then CRB := $08 (stop), read TBHI:TBLO.
6. If the value read is **≤ $CCDD** (≥ 13 090 E ticks per tick) ⇒ **50 Hz**, otherwise **60 Hz**.
   PAL 709 379/50 = 14 188 ticks ⇒ 50; NTSC 715 909/60 = 11 932 ⇒ 60.
7. Effects: TOD frequency = 50 or 60; **µs per TOD tick = 20 000 or 16 667**;
   **ExecBase->PowerSupplyFrequency (+$213)** := 50 or 60.

Snapshot [S]: `EXEC vbf psf = $32 $32` (VBlankFrequency 50, PowerSupplyFrequency 50).

### 1.4 Resulting interrupt levels

| Unit | Source | 68000 level |
|---|---|---|
| MICROHZ | CIA-A TB → INTREQ PORTS (bit 3) → PORTS server chain → ciaa.resource server → ICR vector bit 1 | **2** |
| VBLANK + clock + quantum | INTREQ VERTB (bit 5) → VERTB server chain | **3** |

---

## 2. UNIT_MICROHZ

### 2.1 Time → E ticks conversion [R][S]

- **Fixed NTSC constant**: ticks = ⌊µs × 46 918 / 65 536⌋ (46 918/65 536 = 0.715 91 = 715 909 Hz,
  the **NTSC** E-clock). The computation is done on the low word then the high word (µs ≤ 91 541 ⇒ high word 0
  or 1, which adds 46 918); 16-bit result.
- **No read** of an E-clock frequency: neither ExecBase->EClockFrequency (does not exist in V34), nor
  VBlankFrequency, nor the mains frequency. **Same computation in PAL** ⇒ in PAL (709 379 Hz) each delay
  lasts **+0.92 %** too long.
- Maximum chunk = **91 541 µs** (⇒ 65 535 ticks). Each loaded chunk = min(remainder, 91 541) if
  `tv_secs` of the head node = 0, otherwise 91 541.
- Accounting is **nominal**: on each interrupt, the chunk duration **in requested µs** is subtracted
  (not the measured time). The stop routine contains a computation of the elapsed partial time
  (inverse conversion 45 771/32 768) **but it is unreachable** (unconditional branch): an
  interrupted chunk is **never** accounted for.

### 2.2 Request queue: **differential** list [R][S]

- One list per unit; each node carries its delay **relative to the previous node**; the **caller's
  request** `timeval` **is modified in place** (successive SubTime calls).
- **Order**: ascending deadline; **ties ⇒ FIFO** (the new one goes behind the nodes whose
  cumulative value is ≤ its own).
- Insertion, new request T (relative):
  - empty list ⇒ head, a chunk is started;
  - T ≥ head (compare secs then micro, unsigned) ⇒ the deltas of the traversed nodes are subtracted
    from T, it is inserted in its place, and the delta of the node following it decreases by the same amount; **the timer
    is not touched**;
  - T < head ⇒ timer stopped, head := head − T, new request at the head, new chunk.
- Interrupt (end of chunk): elapsed := chunk duration; while elapsed ≥ head ⇒ elapsed −=
  head, the head moves to a "completed" list; otherwise head −= elapsed. Then a new chunk for
  the new head (or stop if empty). Zero deltas that follow are therefore completed **in the same
  interrupt**. Replies (**ReplyMsg**) are made **after Enable**, from the level 2
  interrupt, in **reverse** completion order (completed requests are stacked): two requests
  expiring in the same interrupt are replied to last one first.
- Consequences of nominal accounting (verified [S]):
  - **preemption** (T < remainder of the head): the new one is **exact**; the old head and all
    following ones are **late** by the already-elapsed part of the interrupted chunk (≤ 91.5 ms);
  - **insertion behind the head**: the new one is **early** by that same elapsed part.

### 2.3 Commands [R][S]

| io_Command | Behaviour |
|---|---|
| 0–8 (CMD_INVALID…CMD_FLUSH) | io_Error := **IOERR_NOCMD (−3)**; ReplyMsg only if IOF_QUICK = 0 |
| ≥ 12 | same, −3 (without resetting ln_Type to NT_MESSAGE) |
| **9 TR_ADDREQUEST** | io_Error := 0; **IOF_QUICK cleared** ⇒ always asynchronous, reply via ReplyMsg at the deadline |
| **10 TR_GETSYSTIME** | synchronous; fills `tv` (§4); ReplyMsg only if IOF_QUICK = 0 |
| **11 TR_SETSYSTIME** | synchronous; base := `tv`, CIA-A TOD := 0, uniqueness counter := 0; ReplyMsg if not QUICK |

On entry to BeginIO: io_Error := 0; if command ≤ 11, ln_Type := NT_MESSAGE (5).
GETSYSTIME and SETSYSTIME act on the clock **whichever unit** is open.

### 2.4 0 µs requests, small values, non-normalised values

- `{0,0}`, `{0,1}`, `{0,50}` MICROHZ: load 0 or 35 ticks; completed **immediately** (same
  total duration as an empty call, ~12 lines of overhead) [S, FS-UAE].
- `{0,91542}`: chunk of 91 541 then chunk of 1 µs (0 ticks): only +4 lines [S].
- `tv_micro` ≥ 1 000 000 is not normalised on entry; `{0,1000000}` behaves exactly like
  `{1,0}` [S]. Insertion comparisons (secs then micro, unsigned) would be wrong between a
  normalised value and a non-normalised one [R, not probed].
- Value returned in `tv` at the deadline = **the delta remaining at the moment of completion** (e.g.
  `{1,0}` returns `{0,84590}` = last chunk; `{0,91542}` returns `{0,1}`) [S]. No caller should
  rely on it, but it is the real state.

### 2.5 AbortIO [R][S]

- Searches for the request in the list of **its** unit, under Disable.
- Absent ⇒ returns **−1** in d0, request untouched (io_Error unchanged) [S: `abortNQ = FFFFFFFF`, err
  stays −3].
- Present ⇒ if it is the head: timer stopped, removal, the **next one recovers the removed delta**
  (AddTime), new chunk; otherwise simple removal + carry-over of the delta. io_Error := **IOERR_ABORTED
  (−2)**, ReplyMsg (QUICK already cleared); returns **0**.
- Removing the head loses the elapsed part of the chunk: the next one is late by that much.

### 2.6 Open / close [R][S]

- Unit 0 ⇒ MICROHZ, unit 1 ⇒ VBLANK (io_Unit = base+$2A / base+$78, private). Flags ignored.
- Unit ≥ 2 ⇒ io_Error := **IOERR_OPENFAIL (−1)**, OpenDevice returns −1, lib_OpenCnt unchanged
  (io_Device remains set by exec, io_Unit unchanged) [S].
- Success ⇒ lib_OpenCnt + 1. Close ⇒ io_Device := io_Unit := −1, lib_OpenCnt − 1. Expunge/ExtFunc
  return 0: the device is never unloaded.
- Version 34.1, `rt_Pri` 50, LIB_FLAGS = CHANGED|SUMUSED [R][S].

---

## 3. UNIT_VBLANK [R][S]

- Source: the device's **VERTB** server (pri 0; at boot the VERTB chain is: graphics pri 10, then
  `gameport.device` pri 0, then `timer.device` pri 0).
- Period P = round(1 000 000 / ExecBase->**VBlankFrequency**) (0 ⇒ 60): **20 000 µs** in PAL,
  16 667 in NTSC. No CIA, no E-clock.
- Same differential list, same algorithm as MICROHZ; on each VBLANK, elapsed := P, and
  **the remainder carries over** to the following nodes in the same interrupt ⇒ counting
  **in absolute frames**, with no drift or loss on preemption (verified [S] PREc).
- Deadline: request T is completed at the **k-th following VBLANK** with k = max(1, ⌈T / P⌉).
  `{0,0}`, `{0,1}` **and** `{0,20000}` ⇒ next VBLANK (thus between ~0 and 20 ms); `{0,20001}` and
  `{0,40000}` ⇒ 2nd; `{1,0}` ⇒ 50th [S].
- The same server also does, **in this order**, under Disable:
  1. **exec quantum**: Elapsed (+$122) − 1; at 0 ⇒ Elapsed := Quantum and **SysFlags (+$124) |=
     $4000** (SFB_TQE, "time quantum elapsed") — exec does not decrement Elapsed anywhere
     else; it reloads it on each task switch;
  2. **clock fold-over** (§4) if the high byte of the CIA-A TOD ≠ 0;
  3. processing of the VBLANK list.
  Then Enable, ReplyMsg of the completed requests; returns d0 = 0 (the chain continues).

---

## 4. System clock [R][S]

- Time = **base** (secs, micro) + converted **CIA-A TOD** + **uniqueness counter**:
  - TOD read under Disable, high byte first (8520 latching), then middle, then low;
  - secs += TOD ÷ mains frequency; micro += (TOD mod frequency) × µs-per-tick + counter;
  - normalisation by AddTime; **then counter + 1**.
- It therefore advances on the **mains tick** (CIA-A TOD, 50/60 Hz on A500), **not** on VBLANK nor on the E-clock.
  Resolution 20 ms (16 667 µs at 60 Hz); between two ticks, each read returns **+1 µs** ⇒
  **strictly monotonic** [S: `…49472`, `…49473`, `…4E294` (+20 001), `…4E295`].
- **Fold-over** (VBLANK server) as soon as TOD ≥ 65 536 ticks (≈ 21 min 50 s at 50 Hz): base := current
  time (counter included), TOD := 0, counter := 0. The counter is therefore **absorbed**: the clock
  permanently gains 1 µs per read (negligible). The TOD ÷ frequency quotient thus fits in 16 bits.
- **TR_SETSYSTIME**: base := value, TOD := 0, counter := 0 ⇒ the first read returns
  **exactly** the value set [S: SST(1000,500000) then `1000/500000`, `500001`, `500002`;
  0.5 s later `1001/020008`].
- At reset: base = 0 (MakeLibrary memory), TOD reset to 0 during calibration ⇒ **1-jan-1978 00:00:00**
  (consistent with `boot-clock-v34.md` §3). At the time of the probe the TOD was $13B (the validator had
  done a SETSYSTIME when mounting DF0:).

---

## 5. AddTime / SubTime / CmpTime [D][R][S]

LVO (device vectors, in the order Open −6, Close −12, Expunge −18, ExtFunc −24, BeginIO −30,
AbortIO −36): **AddTime −42**, **SubTime −48**, **CmpTime −54**; arguments **A0 = dest, A1 = src**.
They do not use A6 (the base is not read); they trash D0/D1; they preserve the other registers.

| Function | Exact semantics | Vectors [S] |
|---|---|---|
| AddTime | dest += src (secs and micro separately), then **while micro ≥ 1 000 000**: secs+1, micro−1 000 000. **No** correction of a negative micro | {0,999999}+{0,2} = {1,1}; {0,3000000}+0 = {3,0}; {5,−3}+0 = {5,−3} |
| SubTime | dest −= src, then **while micro < 0**: secs−1, micro+1 000 000. **No** correction of a micro ≥ 1e6 | {1,0}−{0,1} = {0,999999}; {0,0}−{0,3000000} = {−3,0}; {0,5000000}−0 = {0,5000000} |
| CmpTime | compares secs then micro, **unsigned**; d0 = 0 if equal, **+1 if src > dest**, **−1 if src < dest** ("dest has more time" ⇒ −1) | ({2,0},{1,5}) = −1; ({1,5},{2,0}) = +1; equal = 0; ({0,1},{0,2}) = +1; ({−1,0},{1,0}) = −1 |

---

## 6. CIA allocation map at boot (1.3, A500) [R][S]

### 6.1 CIA-A ($BFE001, level 2 PORTS, ciaa.resource)

| Resource | Owner | Remark |
|---|---|---|
| Timer A | **free** | never started; CRA = $00 (keyboard only toggles SPMODE). Starting it during the keyboard handshake causes an SP shift (cf. `keyboard-handshake-v34.md` §7) |
| Timer B | **timer.device** (ICR bit 1, enabled) | UNIT_MICROHZ |
| TOD | **timer.device** (read/reset to 0, no interrupt) | system clock; CRB bit 7 = 0 |
| ALRM (bit 2) | **free** | |
| SP (bit 3) | **keyboard.device** (ICR bit 3, enabled) | |
| FLG (bit 4) | **free** | (parallel /ACK [D]) |

Snapshot [S]: `ICRA mask $0A : 0=- 1=timer.device 2=- 3=keyboard.device 4=-`.

### 6.2 CIA-B ($BFD000, level 6 EXTER, ciab.resource)

| Resource | Owner | Remark |
|---|---|---|
| Timer A | **free** | no reference in ROM |
| Timer B | **free** | no reference in ROM |
| TOD | **graphics.library** | on every VBLANK, graphics resets the TOD to the current vertical line then sets CRB bit 7 (ALARM) back to 1; the CIA-B TOD therefore counts **lines since the top of the frame** |
| ALRM (bit 2) | **graphics.library** (unnamed Interrupt; enabled at boot) | beam-synchronised blit queue (QBSBlit): the alarm disables itself and retriggers the BLIT interrupt |
| SP (bit 3) | **free** | |
| FLG (bit 4) | **disk.resource** (unnamed Interrupt; **not enabled** at boot) | index pulse; trackdisk enables/disables it (SetICR/AbleICR $10/$90) around index-synchronised operations, and disk.resource forwards it to the current owner of the disk |

Snapshot [S]: `CIAB cra.crb = $04/$84`, TA = TB = $FFFF, ICR mask **$04** (ALRM only);
`0=- 1=- 2=(sans nom) 3=- 4=(sans nom)`. ciab.resource also sets CIA-B PRA bits 6–7 (/RTS, /DTR) as
outputs at 1; disk.resource sets CIA-B PRB as output at $FF and bits 2–5 of CIA-A PRA as inputs.

### 6.3 Chains and vectors at boot [S]

| Exec vector | Contents (after WB 1.3.3 boot, serial.device loaded by `>SER:`) |
|---|---|
| 3 PORTS (servers) | **ciaa.resource only** (pri 0) |
| 4 COPER (servers) | empty |
| 5 VERTB (servers) | graphics (pri 10), gameport.device (0), timer.device (0) |
| 13 EXTER (servers) | **ciab.resource only** (pri 0) |
| 1 DSKBLK / 12 DSKSYNC | disk.resource |
| 6 BLIT | graphics |
| 7–10 AUDx | audio.device |
| 0 TBE / 11 RBF | serial.device (disk-based, opened here by the probe; absent otherwise) |

**Free for an application**: CIA-A timer A (with the keyboard caveat), CIA-A ALRM and FLG, CIA-B
timer A, timer B and SP. A program that takes vector `$78` without chaining breaks only
QBSBlit (ALRM) and index-synchronised disk operations (FLG).

---

## 7. trackdisk delays [R]

- trackdisk opens **timer.device twice** at init: **unit 0 (MICROHZ)** and **unit 1
  (VBLANK)** (failure ⇒ Alert $14048015), and copies these opens into each disk unit.
- **All delays** (head step 3 ms, settle 15 ms, motor spin-up 500 ms, 1 ms before DMA, 2 ms
  write: see `trackdisk-official-timing.md`): **synchronous (DoIO) TR_ADDREQUEST MICROHZ** request
  on the unit's MICROHZ request; below **300 µs**: CPU loop.
- The unit's **VBLANK** request is re-armed asynchronously (SendIO) by the unit's task:
  disk-change polling (selection, reading /CHNG, step pulse if needed);
  re-armed with tv_micro = 500 000 and tv_secs := 2 when a unit status flag is set
  (otherwise tv_secs stays at the returned value, in practice 0) ⇒ period ≈ 0.5 s or ≈ 2.5 s.
- **No CIA timer** is programmed directly by trackdisk or disk.resource. CIA-B is only used for
  the drive control outputs (PRB) and the index (FLG).

---

## 8. Test vectors (raw outputs, real ROM, FS-UAE A500 PAL)

Measurement: frames F counted by a probe VERTB server + line difference L; duration ≈
(F × 313 + L) lines of 64 µs (313 lines/frame measured: `maxline = $138`). Fixed measurement overhead
≈ 12 lines (0 µs request).

```
EXEC vbf psf quantum elapsed sysflags maxline: 00000032 00000032 00000010 00000010 00000000 00000138
CIAA cra.crb ta tb tod: 00000008 0000FFFF 000002CB 0000013B
CIAB cra.crb ta tb tod: 00000484 0000FFFF 0000FFFF 000000D2
ICRA base mask: 00C01680 0000000A 0=- 1=timer.device/(code ROM)  2=- 3=keyboard.device/(code ROM)  4=-
ICRB base mask: 00C01718 00000004 0=- 1=- 2= 3=- 4=
OPEN dev u0off u1off opencnt ver.rev | u2: d0 err dev unit: 00C022EE 0000002A 00000078 0000000A 00220001 FFFFFFFF FFFFFFFF 00C022EE 00000000
CMD read(d0 type.err) cmd12 invalid | abortNQ(d0 err): FFFFFFFD 000005FD FFFFFFFD 000005FD FFFFFFFD 000005FD FFFFFFFF FFFFFFFD
ADD/SUB: 00000001 00000001 00000003 00000000 00000005 FFFFFFFD 00000000 000F423F FFFFFFFD 00000000 00000000 004C4B40
CMP: FFFFFFFF 00000001 00000000 00000001 FFFFFFFF
```

| Request | F | L | lines | Theory (E ticks × 5/227) + overhead | Remark |
|---|---|---|---|---|---|
| MZ {0,1000} | 0 | 26 | 26 | 15.8 + 12 | |
| MZ {0,10000} | 0 | 168 | 168 | 157.7 + 12 | |
| MZ {0,20000} | 1 | 13 | 326 | 315.4 + 12 | |
| MZ {0,91541} | 5 | −111 | 1454 | 1443.6 + 12 | 1 full chunk |
| MZ {0,91542} | 4 | 206 | 1458 | +1 chunk of 0 ticks | tv returned {0,1} |
| MZ {0,100000} | 5 | 26 | 1591 | 1576.9 + 12 | tv returned {0,8459} |
| MZ {0,250000} | 13 | −110 | 3959 | 3942.2 + 12 | |
| MZ {1,0} | 51 | −143 | 15820 | 15769 + 12 (+≈3.5 lines × 11 chunks) | **1.0125 s**; tv returned {0,84590} |
| MZ {0,1000000} | 51 | −141 | 15822 | same | identical to {1,0} |
| MZ2 {0,50} / {0,1} / {0,0} | 0 | 12 | 12 | overhead only | completed at once |
| VB {0,0} | 1 | −104 | — | next VBLANK | |
| VB {0,1} | 1 | −241 | — | next | |
| VB {0,20000} | 1 | −294 | — | next | tv returned {0,20000} |
| VB {0,20001} | 2 | −266 | — | 2nd | |
| VB {0,40000} | 2 | −237 | — | 2nd | |
| VB {0,100000} | 6 | −299 | — | 5th (see §9) | |
| VB {1,0} | 50 | −269 | — | 50th | |

Preemption / insertion (two runs, serial then console):

```
PREa(MZ A=1s B=.5s) poseB F L | ordre: 00000003 FFFFFF7D B 0000001C FFFFFFD5 A 00000036 FFFFFF3C
PREa (2e)                              00000003 FFFFFFC8 B 0000001C 00000020 A 00000036 FFFFFF3E
PREb(MZ A=.2s B=.4s) poseB F L | ordre: 00000003 00000047 A 0000000A 00000029 B 00000014 0000004B
PREb (2e)                              00000003 FFFFFFCA A 0000000A 0000002A B 00000014 00000055
PREc(VB A=1s B=.5s) poseB F L | ordre: 00000003 00000003 B 0000001C FFFFFFC3 A 00000032 FFFFFF7A
```

- PREa: B posted at 808 lines, finished at 8721 (7913 lines = its normal duration); A finished at 16 706
  instead of 15 820 ⇒ **delay ≈ 886 lines ≈ 57 ms** ≈ elapsed part of the interrupted chunk (808) +
  reloads.
- PREb: A exact (3171); B posted at 1010, finished at 6335 instead of ≈ 7338 ⇒ **early by ≈ 64 ms** = elapsed
  part of A's chunk at the moment of posting.
- PREc (VBLANK): B at the 28th VBLANK (posted at ~3 frames + 0.5 s), A at the 50th: **no error**.

Clock:

```
GST: 5BD28ADF 00049472 5BD28ADF 00049473 5BD28ADF 0004E294 5BD28ADF 0004E295
SST(1000,500000) err | GST x3 | MZ.5s | GST: 00000000 000003E8 0007A120 000003E8 0007A121 000003E8 0007A122 0000001A FFFFFF23 00000000 tv 00000000 0000A537 000003E9 00004E28
```

Vector hijacks (the key point for games):

```
HJ6 MZ.5s(F L err) VB.5s(F L err) h6cnt: 0000001A FFFFFF1D 00000000 tv 00000000 0000A537 00000019 FFFFFFAE 00000000 tv 00000000 00004E20 0000003C
HJ2 MZ.1s(F L err) h2cnt | apres retablissement MZ.1s: TMO FFFFFFFE tv 00000000 000186A0 00000001 00000005 00000019 00000000 tv 00000000 0000210B
```

- **HJ6**: `$78` taken by a handler that reads the CIA-B ICR, acknowledges EXTER and does RTE without
  chaining, while CIA-B timer B runs continuously (latch $2E2E, ICR $82, like the Monkey Island
  music): 60 hijacked interrupts; **MICROHZ 0.5 s = 7911 lines** (normal: 7917) and
  VBLANK 0.5 s = 25 frames: **delays intact**.
- **HJ2** (negative control): `$68` taken in the same way ⇒ MICROHZ 0.1 s **never served**
  (VBLANK safeguard of 3 s reached, AbortIO ⇒ io_Error −2, tv intact {0,100000}, only 1 hijacked
  interrupt: the one-shot does not restart). After `$68` is restored, a new MICROHZ 0.1 s
  lasts 1590 lines: the unit restarts after the AbortIO.

To reproduce: assemble `tests/timerprobe.s` with `-kick1hunks`, write it to a copy of the Workbench
1.3.3 ADF with the startup-sequence `timerprobe >SER:` then `timerprobe`, boot the real ROM.

---

## 9. Not probed / uncertain

- **Loading a latch of 0 in one-shot mode**: immediate completion observed under FS-UAE; behaviour of a
  real 8520 not verified (a MICROHZ {0,0}/{0,1} request might behave differently on the
  hardware).
- **CIA-B CRA/CRB bit 2 (OUTMODE) = 1** observed after boot ($04/$84): no corresponding write
  found in ROM; origin (emulator state, program on the disk) not elucidated. No effect (PBON = 0).
- **VB {0,100000} = 6 frames** instead of 5: interpreted as a measurement race (timestamp just
  before a VBLANK, SendIO just after: L = −299 ⇒ timestamp within the last 14 lines of the
  frame); not redone.
- **Calibration without a TOD tick** (§1.3 step 3): Alert path + unbalanced stack analysed, not probed.
- **trackdisk unit flag** that switches VBLANK polling to 2.5 s: exact semantics
  (no disk?) not elucidated.
- Measurement done in PAL 50 Hz only; the 60 Hz path (16 667 µs/tick, VBLANK P 16 667) is [R].
- Reload overhead per MICROHZ chunk (≈ 3–4 lines ≈ 220 µs) depends on the interrupt
  load: indicative value.

---

## 10. Recommendation for the reimplementation

Goal: a game that hijacks `$78` (level 6) must break **no** system delay.

1. **Move UNIT_MICROHZ to CIA-A timer B**, obtained via `ciaa.resource`
   AddICRVector(bit 1) ⇒ level 2. One-shot mode (CRB RUNMODE = 1, INMODE = φ2), start by
   writing TBLO then TBHI, stop by clearing START alone (do not overwrite the other CRB bits).
   Chunks ≤ 65 535 ticks.
2. **Program no CIA-B timer** in the ROM: games consider them free (Monkey
   writes CIA-B TB, CRB = $11, ICR = $82 directly, without a resource). Do not use CIA-A timer A
   either.
3. **UNIT_VBLANK on a VERTB server** (level 3), period 1e6/VBlankFrequency, with carry-over of the
   remainder (counting in absolute frames), deadline at the k-th VBLANK, k = max(1, ⌈T/P⌉).
4. **System clock on the CIA-A TOD** (mains tick) + uniqueness counter +1 µs per read,
   fold-over in the VBLANK server when TOD ≥ 65 536, reset by SETSYSTIME. Leave the CIA-B TOD
   to graphics (lines/alarm).
5. Level 6: install only the `ciab.resource` server there (graphics ALRM, disk.resource FLG).
   That way, taking `$78` has, as on 1.3, effects only on QBSBlit and the disk index.
6. trackdisk delays: synchronous TR_ADDREQUEST MICROHZ (≥ 300 µs), CPU loop below;
   disk-change polling via a periodic VBLANK request.
7. Fidelity (optional but advised): fixed factor 46 918/65 536 ticks/µs even in PAL (delays
   +0.92 %), nominal per-chunk accounting (early/late on preemption, §2.2), differential
   list with FIFO for ties, request `tv` modified in place, IOF_QUICK cleared by
   ADDREQUEST, AbortIO returning −1 if the request is not queued. timer.device sets Quantum = 16 and
   provides the quantum tick (SysFlags bit 14) from its VBLANK server: if our exec depends
   on another time-slice source, keep it consistent with 16 frames.
8. Accepted side effect: a game that hijacks `$68` (level 2) kills MICROHZ **and** the keyboard, as on
   the real 1.3 (HJ2).

---

## 11. Clean-room review

Fully reviewed: no 68000 instruction sequence copied or paraphrased, no disassembly
excerpt, no line-by-line pseudo-code. The document describes resources, hardware
registers and values written, conversion formulas (constants), ordering and
accounting rules, conditions and probe outputs. The ROM addresses captured by the probe (removed from the document)
are identification landmarks captured by the probe, not recipes. The probe
`tests/timerprobe.s` is author code (public structures). The ROM was neither modified nor
copied; the disassembly stayed in the session scratch directory.
