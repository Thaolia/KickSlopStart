# coldstart-hardware-v34.md — The exec 1.3 coldstart facing the real hardware of an A500

> **Behavioural** spec (ANALYSIS track). It complements, without repeating them,
> `boot-sequence.md` (overall order), `exec-spec.md` (ExecBase layout), `module-map.md` (ROMTags) and
> `test-vectors.md`. No instruction sequence is copied, no ROM routine address
> is cited: only orders of operations, values, public hardware and low RAM
> addresses, and ABI layouts.
>
> Legend: **[O]** observed in the binary `kick34005.A500` (radare2, base `$FC0000`) ·
> **[S]** black-box probed under FS-UAE with the real ROM (`tests/coldhw_probe.sh`) ·
> **[D]** deduced (reasoning on [O]/[S] or on the public hardware documentation, not executed).
>
> Hardware target: A500 rev. 5/6, Agnus 8370/8371 (512 KB) or 8372 (1 MB), 512 KB of chip, trapdoor
> 512 KB expansion at `$C00000` common.

---

## 1. Very first code after reset

### 1.1 What precedes: vectors and overlay
- At reset, the overlay is active (CIA-A DDRA = 0 after reset → the OVL pin, as an input, is pulled
  high): the ROM appears at `$000000`. The 68000 reads SSP = `$11114EF9` and PC = the address of the
  coldstart entry point in the ROM. **[O]**
- The word `$4EF9` at ROM `+2` followed by the coldstart address at `+4` forms an "absolute JMP
  to the coldstart" instruction **executable at address 2** as long as the overlay is active. This is what makes
  possible the public software-reboot technique of the 1.3 era (§7.3). **A compatible ROM must
  keep this form** (`$1111`, `$4EF9`, then the address of its own entry point). **[O]**
- The word immediately preceding the coldstart entry point, if executed, resets the
  peripherals (effect of a software reset, overlay restored) then falls into the coldstart. No ROM code
  jumps to it; it is a convenience placed next to the entry. **[O]**
- **CPU state on entry**: supervisor, interrupt mask 7 (68000 reset state). The coldstart does not
  touch SR before the creation of the initial task (§4.4). **[O]**

### 1.2 Exact order of operations (common cold/warm path)
1. Sets a provisional SSP at **`$40000`** (the top of the first 256 KB of chip). **[O]** No stack write
   takes place before the RAM sizing: the startup code does not use the stack,
   so that a faulty RAM does not crash the diagnostic. **[O]**
2. **Delay of about 0.33 s**: active CPU wait (≈ 2.36 M cycles at 7.09 MHz PAL, from
   the ROM hence without contention). **[O]** (duration **[D]**)
3. **Diagnostic ROM probe at `$F00000`**: if the ROM is not itself executing from `$F00000`
   and the word read at `$F00000` is **`$1111`**, exec jumps to **`$F00002`** leaving in A5
   the address at which to resume the coldstart. The overlay is still active at that moment. **[O]**
4. **CIA-A**: DDRA ← `$03` (OVL and LED as outputs), then PRA ← `$02` → **overlay lifted** (OVL = 0, the
   chip RAM appears at `$000000`) and **power LED dimmed** (bit 1 = 1; on the A500 this bit
   also turns off the audio filter). **[O]** Since the PRA register is 0 after a hardware reset, the write
   of DDRA already lifts the overlay and briefly lights the LED before the PRA write. **[D]**
5. **Silencing of the custom chips**: INTENA ← `$7FFF`, INTREQ ← `$7FFF`, DMACON ← `$7FFF`
   (everything off, DMAEN included). BPLCON0 ← `$0200` (colour active, 0 planes), BPL1DAT ← 0. **[O]**
6. **COLOR00 ← `$444` (dark grey)** — first visible sign of life. **[O][S]**
7. Fills the exception vectors **`$08` to `$BC`** (46 longs: bus/address errors, illegal, …,
   autovectors, TRAP #0-15) with a single "**yellow** screen" handler (§8.6). **[O]**
8. Retrieves any **last alert** in low RAM (§8.2), then attempts **warm survival**
   (§5). Otherwise **cold** path: slow RAM sizing (§3), then chip (§2), then clearing.
9. COLOR00 ← **`$888` (light grey)** and DMACON ← `$7FFF` again, BPLCON0/BPL1DAT set again: start of the
   construction of ExecBase (cold and warm paths). **[O][S]**

### 1.3 What the 1.3 coldstart does NOT do
- **No ROM checksum test.** No code in the binary sums the image; the checksum
  "end-around-carry sum = `$FFFFFFFF`" is indeed present in the file (verified: the sum of the
  65,536 longs is `$FFFFFFFF`), but nothing checks it at boot. **[O]**
- **No red or blue screen.** The only colours the coldstart writes into COLOR00 are `$444`,
  `$888`, `$CC0` (yellow) and `$0C0` (green); the white `$FFF` comes from the graphics.library init. Any
  "red = ROM, blue = custom chips" table comes from later Kickstarts. **[O]**
- No custom chip test, no pattern test over the whole RAM, no reset counter. **[O]**

---

## 2. Detection and test of the chip RAM (cold path only)

- **Probed range**: from `$000000` to `$200000` (excluded), **in steps of 4 KB**. **[O]**
- **Method** **[O]**:
  1. write the long `0` at `$000000` (anti-mirror sentinel);
  2. for each 4 KB boundary `A = $1000, $2000, …`: write a test-pattern long (non-zero,
     mixed bits) at `A`;
  3. stop as soon as: (a) the sentinel `$000000` is no longer zero (**mirror**: the address has wrapped
     around to 0); (b) the read-back of `A` differs from the pattern; (c) `A` reaches `$200000`;
  4. `MaxLocMem` = the first address `A` that failed.
- **Mirrors depending on the Agnus** **[D]**: 8370/8371 decode 512 KB, the write at `$80000` falls back to
  `$00000` → stop by (a) → 512 KB. An 8372 wired for 1 MB of chip gives `$100000`; with 512 KB only
  the mirror at `$80000` still gives 512 KB. Under FS-UAE: chip 256 → `$40000`, 512 → `$80000`,
  1024 → `$100000`. **[S]**
- **Threshold**: if `MaxLocMem < $40000` (less than 256 KB detected) → **green screen** `$0C0` (§8.6). **[O]**
- **Actual test coverage**: a single long per 4 KB slice. A defect elsewhere in the slice
  is not seen; a defect on a boundary beyond 256 KB **silently reduces** the detected chip
  (e.g. defect at `$50000` → 320 KB, normal boot). **[D]**
- Then: the long at `$000000` is reset to 0, then **the whole chip from `$0000C0` to `MaxLocMem` is
  zeroed** (the vectors `$08..$BC` set in step 7 are therefore preserved). **[O]**

---

## 3. Detection of the slow RAM `$C00000`–`$DBFFFF` (cold path only)

Done **before** the chip. **[O]**

- **Range**: from `$C00000` to `$DC0000` (excluded), **in blocks of 256 KB** (max. 1.75 MB). **[O]**
- **Addresses probed** in each block `[B, B+$40000)`: the word at `B+$3F09A` and the word at
  `B+$3F01C` — that is, modulo 512 bytes, the offsets **INTENA (`$09A`) and INTENAR (`$01C`)**.
  **[O]**
- **`$DFF000` trap (mirrored custom registers)**: on the A500, a `$C00000+` range without RAM answers with
  a **mirror of the custom registers** (partial decoding). For each block **[O]**:
  1. write `$3FFF` at the "INTENA" location (clears bits 0-13); read the "INTENAR" location;
     if the value read is **non-zero**, these are not registers → RAM test;
  2. otherwise write `$BFFF` (sets bits 0-13); if "INTENAR" reads back **`$3FFF`**, these are the
     registers → **end of the slow RAM**; exec then rewrites `$7FFF` (everything cleared) at that location.
  - Side effect: the real INTENA is briefly loaded with `$3FFF`; harmless since SR masks everything. **[D]**
- **RAM test of a block** **[O]**:
  1. write `0` at the reference location of the **first** block (`$C3F09A`);
  2. write a first pattern word at the probed location of the current block, read back → different = end;
  3. if the reference stayed zero: write a second pattern word, read back → different = end, equal =
     block accepted;
  4. if the reference equals the first pattern: first block (same address) → go to step 3; **other block
     (mirror of the first) → block accepted without the 2nd pattern**.
  - **Anomaly**: a module that repeats as a mirror within `$C00000+` would therefore be counted up to the
    limit. An A501 does not repeat (the next block falls on the mirrored registers, correct stop).
    Do not rely on this branch; a reimplementation may treat the mirror as an end. **[D]**
- **Result**: `MaxExtMem` = end of the last accepted slice, or **0** if none. If present, the
  slow RAM is **entirely zeroed** (`$C00000` → `MaxExtMem`). **[O]**
- FS-UAE: slow 0 → `MaxExtMem = 0` (the register mirror is emulated); 512 → `$C80000`;
  1024 → `$D00000`; 1536 → `$D80000`. **[S]**

---

## 4. Placement of ExecBase, supervisor stack, MemList (complement to `exec-spec.md`)

### 4.1 ExecBase address
- `ExecBase = RAM_base + $400 + $276` (`$276` = size of exec's LVO table, cf. `lib_NegSize`). **[O]**
  - without slow RAM: **`$00000676`**; **with slow RAM: `$00C00276`** (ExecBase in `$C00000` RAM). **[O][S]**
- Library header set: `LN_Type = 9`, `LN_Pri = 0`, `lib_Flags = 6`, `lib_PosSize = $024C`,
  version 34 rev. 2, `lib_OpenCnt = 1`; `lib_NegSize` receives the size of the built table. **[O]**
  → the V34 ExecBase structure occupies **`$24C` bytes** on the positive side.
- `*(ULONG*)4 = ExecBase`, `ChkBase = ~ExecBase`. **[O]**

### 4.2 Supervisor stack
- Top = `MaxExtMem` if slow RAM exists, otherwise `MaxLocMem`. `SysStkUpper` = that top,
  `SysStkLower = SysStkUpper − $1800` (**6 KB**). **[O][S]**

### 4.3 MemList built **[O][S]**
| Config | MemHeader | Name | Attributes | Pri | Declared range |
|---|---|---|---|---|---|
| without slow | at `ExecBase+$24C` | `Chip Memory` | `$0003` | −10 | `ExecBase+$24C` → `MaxLocMem − $1800` |
| with slow | at `ExecBase+$24C` | `Fast Memory` | `$0005` (PUBLIC\|FAST) | 0 | `ExecBase+$24C` → `MaxExtMem − $1800` |
| with slow | at `$400` | `Chip Memory` | `$0003` | −10 | `$400` → `MaxLocMem` (stack absent from chip) |

- An A500's slow RAM is therefore presented as **"Fast Memory" MEMF_FAST**, with a priority higher than
  chip: allocations without MEMF_CHIP go there first. **[S]**
- Measured values (512 KB chip): without slow → header `$8C2`, `mh_Lower = $8E8`, `mh_Upper = $7E800`;
  with 512 KB slow → Fast `$C004C2`/`$C004E8`/`$C7E800`, Chip `$400`/`$420`/`$80000`. **[S]**

### 4.4 Interrupts and DMA at the end of the coldstart **[O]**
- After installation of the interrupt servers: INTENA ← `$8004` (SOFTINT only), then DMACON ←
  `$8200` (DMAEN, no channel), INTENA ← `$C000` (master), `IDNestCnt = TDNestCnt = −1`.
- Then the initial task is created and **SR goes to 0** (user mode, interrupts unmasked):
  CoolCapture, InitCode and the bootblock run **in user mode** (the bootblock too: a
  privileged instruction there causes a Guru `#00000008`). **[O][S]**
- The display DMA channels and the **white** (`COLOR00 = COLOR01 = $FFF`, DMACON `$81A0`) arrive with
  the init of graphics.library (pri 65). **[O][S]**

---

## 5. Warm reset survival

### 5.1 Validation of an existing ExecBase (exact order) **[O]**
1. `*(ULONG*)4` must be **even**;
2. `ExecBase + ChkBase` must equal `$FFFFFFFF`;
3. the 16-bit sum of the **25 words from `+$22` to `+$52`** inclusive (`SoftVer` … `ChkSum`) must equal
   **`$FFFF`**; at init, `ChkSum` receives the complement of the sum of the words `+$22..+$4E` (the word
   `+$50`, low half of `MaxExtMem`, is excluded when setting but included when checking — it is always 0
   since `MaxExtMem` is a multiple of 256 KB);
4. **ColdCapture**: if non-zero, it is **reset to 0 then called** (jump, return via the address provided in
   A5), in supervisor mode, SR = `$2700`, overlay lifted, SSP = `$40000`, A6 = ExecBase; **before** the
   following checks;
5. toggle of the LED bit (the LED goes bright again);
6. the long `+$14` (version.revision) must equal the ROM's, **`$00220002`** (34.2);
7. **`$40000 ≤ MaxLocMem ≤ $80000`**;
8. `MaxExtMem` = 0, or **`$C40000 ≤ MaxExtMem ≤ $DC0000` and a multiple of `$40000`**.

Any failure → cold path (ExecBase rebuilt, RAM cleared, Kick pointers lost).

- **Consequence for an A500 with 1 MB of chip (8372)**: `MaxLocMem = $100000` fails at point 7 → **every reset
  is a cold start**: RAM cleared, KickMem/KickTag/CoolCapture/WarmCapture lost (only
  ColdCapture, called before the test, still takes place). Proven: under FS-UAE chip 1024 KB, a marker in
  chip and in slow is cleared at each reboot. **[O][S]**

### 5.2 What the warm path keeps or rewrites **[O]**
- Memory: **nothing is cleared** in chip or slow. The MemHeaders are rebuilt as in the cold case
  (all the RAM is redeclared free, contents intact). A marker at `$60000` (chip) and at `$C40100`
  (slow) survives the reboot. **[S]**
- ExecBase: the **126 longs from `+$54` to `+$24B`** are zeroed (IntVects, lists, `LastAlert`,
  `VBlankFrequency`…), **except `KickMemPtr`, `KickTagPtr`, `KickCheckSum`**, saved and restored.
  The Capture vectors (`+$2A..+$35`) are not touched (ColdCapture already cleared in step 4).
  `SysStkUpper/Lower`, `MaxLocMem`, `MaxExtMem`, `ChkBase` are rewritten. **[O]**
- Probed: ColdCapture called once then read as 0 at the next boot; CoolCapture called and kept. **[S]**

### 5.3 KickMemPtr / KickTagPtr / KickCheckSum **[O]**
- After the scan of the ROMTags, exec recomputes the Kick sum (**same routine as `SumKickData`**,
  LVO −612) and compares it with `KickCheckSum`:
  - start `$FFFFFFFF`;
  - for each `MemList` of the `KickMemPtr` chain (followed via `LN_Succ`): addition of
    **`2·ml_NumEntries + 5` consecutive longs** from the start of the node (i.e. the whole node **plus one
    extra long**, a peculiarity to reproduce);
  - then, for the `KickTagPtr` table: addition of each positive entry; an entry with bit 31 set is a
    link (bit cleared → next table, not summed); 0 terminates.
- Equality → each entry of each `MemList` is reserved by **AllocAbs**; if **all** succeed,
  the ROMTags of `KickTagPtr` are merged. Otherwise the KickTags are ignored (silently).
- **Precedence** during the merge (by `rt_Name`): the new one replaces the old one if its version is
  higher, or equal with a higher or equal priority; scan order: ROM `$FC0000–$FFFFFF`,
  then `$F00000–$F7FFFF`, then KickTags.
- CoolCapture is called (JSR, in **user** mode, multitasking active, A6 = ExecBase) after the
  construction of `ResModules` and the lighting of the LED, just before `InitCode(RTF_COLDSTART)`;
  WarmCapture just after InitCode returns — which, in practice, does not happen (strap hands over to
  DOS). **[O]** (last point **[D]**)

### 5.4 Reset counter
- **None** in exec 1.3. **[O]**

---

## 6. RAM cleared / preserved — summary

| Area | Cold (power-on or invalid ExecBase) | Warm (ExecBase validated) |
|---|---|---|
| `$000000` (long) | read (`HELP`?) then set to 0 | set to 0 only if `HELP` was there |
| `$000004` | ExecBase | ExecBase (unchanged) |
| `$08–$BC` vectors | provisional yellow, then exec vectors | same (rewritten) |
| `$C0–MaxLocMem` | **set to 0** | **preserved** |
| `$100`/`$104` (last alert) | read then cleared with the rest | **preserved** (re-read at the next boot) [S] |
| slow RAM | **set to 0** | **preserved** |
| ExecBase `+$54..+$24B` | new (zero) | zero except `Kick*` |

- Cold clearing: about 0.4 s per 512 KB (≈ 22 cycles per long, without DMA) → ≈ 0.4 s without
  expansion, ≈ 0.8 s with 512 KB of slow. **[D]**
- A CPU exception of a task writes **all the registers at `$180–$1BF`** (low RAM). **[O]**

---

## 7. Resets

### 7.1 Keyboard reset (Ctrl-Amiga-Amiga)
- **Purely hardware** for the most part: the keyboard controller holds KCLK low (≈ 500 ms) and the
  motherboard generates the system /RESET (CPU **and** chips) → the ROM restarts from the vector with the overlay, RAM
  intact → **warm path** if ExecBase valid (§5). **[D]** (public hardware documentation)
- **Reset warning** on the keyboard.device 1.3 side **[O]**: keyboard code **`$78`** received **twice
  in a row** triggers, on the 2nd occurrence, a `Cause()` on each handler of the
  `KBD_ADDRESETHANDLER` list and a counter of handlers in progress; **the handshake (KDAT held low via
  CIA-A SPMODE) is not released** until all have called `KBD_RESETHANDLERDONE`; the
  last one releases the handshake. Without a handler, the handshake is released immediately. The first `$78` is
  treated as an ordinary code.
- The keyboard then waits (max. ≈ 10 s according to the public documentation) then causes the hardware reset. **[D]**

### 7.2 Internal reboot path of the ROM **[O]**
Used by the error screens (§8.6), the "hard" path of Alert (§8.3) and the left click after a
CPU exception:
1. delay ≈ 0.33 s (same loop as in §1.2);
2. **`RESET`** instruction (≈ 124 cycles of /RESET: the CIAs return to zero → **overlay restored**);
3. read of the long at `$000004` — which, with the overlay back, is the **ROM's PC vector** — and jump.
- The CPU is not reinitialised by `RESET`: only the state left in the registers changes. RAM intact →
  warm path. **[D]**

### 7.3 "ColdReboot-like" software reboot (1.3 does not have `ColdReboot`, LVO −726 = V36)
- Public technique: in supervisor mode (via `Supervisor()`), A0 = 2, then `RESET` and `JMP (A0)` **in the
  same aligned long** (the jump is already in the prefetch queue when chip disappears under
  the overlay). At address 2 the overlay presents `JMP coldstart` (§1.1). **[S]** (probed: clean reboot,
  ExecBase reused, chip and slow markers kept)
- From a bootblock (user mode), a direct `RESET` produces a Guru `#00000008.<task>`. **[S]**

---

## 8. Alert() and alert.hook

### 8.1 Alert(alertNum D7, A5) in V34 **[O]**
- The **second number** of the Guru is **the long read at the address contained in A5** (not A5 itself). Proven:
  A5 → `$CAFEBABE` displays `#8100000F.CAFEBABE`. **[S]** For a task exception, A5 points to
  `ExecBase.ThisTask` → second number = address of the task.
- CPU exceptions of a task (vector → `TaskTrapCode` by default) enter the same code with
  `alertNum = vector number` (`$00000003` address, `$00000004` illegal, `$00000008` privilege…).

### 8.2 Persistence in low RAM **[O][S]**
- `$000000` ← **`'HELP'` (`$48454C50`)**, `$000100` ← alertNum, `$000104` ← second number.
- At the next reset, the coldstart sees `HELP` at `$0`, clears that long and copies `$100`/`$104` into
  `LastAlert[0..1]` (`+$202`/`+$206`); otherwise `LastAlert[0] = $FFFFFFFF`. Works both cold
  and warm (values kept in registers during the clearing). **[O][S]**

### 8.3 Alert decision tree **[O]**
1. INTENA ← `$4000` (master interrupts off).
2. `HELP` already present at `$0` (nested alert) → **hard path**.
3. Writes `HELP`/`$100`/`$104`.
4. **Validity of ExecBase**: `*(4) & $00FF0001` must be **zero** (even **and below `$10000`**) and
   `ChkBase` consistent; otherwise **hard path**.
   → **With slow RAM, ExecBase is at `$C00276`: ANY alert, even recoverable, takes the hard path**
   (reset then display at the next boot). Proven: `Alert($35000001)` under 512+512 KB → reboot then
   "Recoverable Alert" displayed by alert.hook; the caller never gets control back. **[S]**
5. Supervisor/user stack test (writes then reads back a pattern long); failure → SSP ← `$40000`, hard path.
6. Bit 31 (dead-end) → hard path.
7. Otherwise: `LastAlert` ← (alertNum, second number) and **immediate display** (alert.hook routine, §8.4).
   - high word of alertNum ≠ 0 (recoverable `Alert()` call): interrupts re-enabled if `IDNestCnt < 0`,
     return to the caller;
   - high word = 0 (CPU exception): registers restored from `$180`; **left button → reboot**
     (§7.2), **right button → ROM-Wack debugger** (serial).

**Hard path** **[O]**: CIA-A DDRA |= 3 and OVL forced to 0, vector `$20` (privilege violation)
redirected to guarantee entry into supervisor mode, SR ← `$2700`. Then **6 rounds** of: SERPER ←
**`$0174`** (≈ 9600 baud), **LED dimmed then bright** (CPU wait of equal duration for each
phase, paced by CIA accesses synchronised on the E clock), read of SERDATR, clearing of RBF in INTREQ; if the character received
(7 bits) is **`$7F` (DEL)** → entry into **ROM-Wack**. After 6 rounds without DEL → reboot (§7.2).
The screen **is not modified** during this time. Duration ≈ 5-6 s under FS-UAE before the reboot. **[S]**

### 8.4 alert.hook (resident pri 5, type UNKNOWN) **[O][S]**
- Its `rt_Init` is **the same routine** as Alert's immediate display. Launched in
  `InitCode(RTF_COLDSTART)` after intuition (pri 10), hence after the graphics white.
- **Fixed delay ≈ 1 s at every boot** (active CPU wait), **before** checking
  whether there is an alert. **[O]** (duration **[D]**)
- If `LastAlert[0] = $FFFFFFFF` → return without doing anything.
- Otherwise, text in DisplayAlert format (x on 16 bits, y on 8 bits, string, continuation byte):
  - line 1, y = 15: x = 38 → header according to alertNum: byte bits 16-23 = `$01` (AG_NoMemory) →
    `Not enough memory. `; otherwise bit 31 = 0 and bits 16-31 ≠ 0 → `Recoverable Alert. `; otherwise
    `Software Failure. `; then x = 234 → `Press left mouse button to continue.`;
  - line 2, y = 30, x = 142 → `Guru Meditation #%08lx.%08lx` (`LastAlert[0]`, `LastAlert[1]`).
- Opens `intuition.library` (version 0); calls **DisplayAlert with alertNumber = 0** and a height
  of **40** lines, then closes the library. If the open fails: nothing is displayed.
- Then, **always**: `$000000` ← 0, `LastAlert[0]` ← `$FFFFFFFF` (`LastAlert[1]`, `$100` and `$104`
  are **not** cleared). Returns the result of DisplayAlert (left = true).
- Observed rendering: **red** text and **frame**, **blinking** frame, almost black background, **wait for the click
  without timeout** (displayed 8 s until the click in the probe). Red as well for
  "Recoverable Alert". After the click, the boot resumes (the bootblock runs). **[S]**

### 8.5 Summary of the alert cases (A500 512 KB)
| Case | Without slow RAM | With slow RAM `$C00000` |
|---|---|---|
| recoverable `Alert()` | immediate display then return **[O]** (not displayed under FS-UAE, cf. §10) | reboot, then Guru at the next boot **[S]** |
| dead-end `Alert()` | LED ×6, reboot, Guru at the next boot **[O]** | same **[S]** |
| CPU exception of a task | immediate Guru **[S]** (`#00000008`); left → reboot, right → ROM-Wack **[O]** | reboot, then Guru at the next boot, the left click **continues the boot** **[S]** (`#00000004`) |

### 8.6 Coldstart error colours **[O]**
A single error routine: BPLCON0 ← `$0200`, BPL1DAT ← 0, **COLOR00 ← colour**, then **11
blinks of the LED** (≈ 0.5 s dimmed, ≈ 0.25 s bright), then reboot (§7.2) —
hence a **reset loop** if the fault is permanent.

| COLOR00 | Meaning |
|---|---|
| `$444` dark grey | coldstart started (after ≈ 0.33 s) |
| `$888` light grey | RAM sized, construction of ExecBase |
| `$FFF` white | graphics.library initialised |
| **`$0C0` green** | less than 256 KB of chip detected (§2) |
| **`$CC0` yellow** | CPU exception (vectors `$08..$BC`) before the installation of the exec vectors |

Duration of an error screen: ≈ 11 × (0.5 + 0.25) s ≈ 8-9 s before the reset. **[D]**

---

## 9. Timeline and delays on a real A500 (estimates **[D]**, 7.09 MHz PAL)

| Step | Duration | Screen |
|---|---|---|
| initial loop | ≈ 0.33 s | undefined (often black) |
| sizing + clearing slow (512 KB) | ≈ 0.4 s | `$444` |
| sizing + clearing chip (512 KB) | ≈ 0.4 s | `$444` |
| ROMTag scan `$FC0000–$FFFFFF` | ≈ 0.33 s | `$888` |
| scan `$F00000–$F7FFFF` (empty on A500) | ≈ 0.66 s | `$888` |
| init of residents up to graphics | — | white |
| alert.hook | ≈ 1 s fixed | white |

Under FS-UAE (not cycle-exact) the observed sequence is black → `$444` → `$888` → white in ≈ 2-3 s of real
time. **[S]** The warm path skips the two "sizing + clearing" lines.

Other facts: `VBlankFrequency` is set by graphics.library (50/60 depending on PAL/NTSC) and
`PowerSupplyFrequency` by timer.device (measurement of the CIA-A TOD clocked by the mains). Measured
50/50 in a PAL A500 config. **[O][S]**

---

## 10. Real A500 vs emulator — expected differences

1. **RAM contents at power-on**: FS-UAE starts from zeroed RAM; a real A500 has random
   RAM. Effects: ExecBase validation almost always fails (correct); `HELP` at `$0` by
   chance negligible. **A short power cut** can leave the DRAM intact → **warm** path (Capture,
   KickTags, last alert) after a quick "power-cycle". **[D]**
2. **Read of `$F00000`**: not decoded on the A500 (floating bus); the emulator returns a fixed value.
   A spurious `$1111` there would divert the boot; no known case, but it is a non-deterministic read
   on real hardware. Same for the `$F00000–$F7FFFF` scan (`$4AFC` + self-pointer required). **[D]**
3. **Register mirror at `$C00000`**: depends on the Gary/Agnus decoding of the real A500; FS-UAE emulates it
   (slow 0 → `MaxExtMem = 0`). A non-standard trapdoor expansion (partial decoding, 1.5 MB,
   "1 MB" boards at `$C00000`) may fall into the "mirror accepted" branch of §3. **[S][D]**
4. **Timings**: all the delays are CPU loops (+ CIA accesses synchronised on the E clock
   for the LED). In non-cycle-exact mode, FS-UAE may shorten them; use cycle-exact A500 to
   compare. **[D]**
5. **8372 / 1 MB of chip**: warm reset impossible (§5.1). Under the emulator, a "chip 1024" config
   reproduces it faithfully (reboot loop of the probe). **[S]**
6. **Slow RAM**: most real A500s have a 512 KB trapdoor → ExecBase at `$C00276` → **any
   alert causes a reset** (§8.3). Test our ROM in both configurations.
7. **Recoverable `Alert()` without slow RAM**: under FS-UAE the machine stays frozen (no display, no return
   within 60 s) with the INTENA master off and the CPU looping in the entry point of the
   level 6 interrupts during alert.hook's delay. On real hardware Paula does not raise
   an IPL with INTEN = 0, so this blocking is probably an emulator artefact. **[S]** (interpretation **[D]**)
8. **Keyboard reset**: FS-UAE generally triggers a direct reset without going through the `$78`/KCLK sequence;
   on a real A500, provide for the reset handshake of §7.1. **[D]**
9. **LED**: invisible under the emulator except for an indicator; on a real machine it serves as a diagnostic
   (dimmed at reset, bright when the resident list is ready; blinks 6× for a dead-end,
   11× for green/yellow). **[O]**

---

## 11. Probes (reproducible)

- `tests/coldhw_probe.s` + `tests/coldhw_probe.sh <mode> <chip_ko> <slow_ko> <durée> ["clics"] ["captures"]`
  (variable `COLDHW_OUT` mandatory): author bootblock that prints on serial ExecBase, `MaxLocMem`,
  `MaxExtMem`, stacks, Capture, `LastAlert`, MemList and low RAM, counts the boots in a chip and
  slow marker, then depending on the mode: 1 dead-end, 2 recoverable, 3 ILLEGAL, 4 software reboot, 5 Cold/CoolCapture.
- Key results: §3, §4.3, §5.1-5.2, §7.3, §8.2-8.5.

---

## Open points

- **Keyboard reset on the A500**: does the A500 keyboard controller really send the `$78` warning (twice)
  before holding KCLK low, and with what maximum delay? The 1.3 code handles it, the precise A500
  hardware has not been verified.
- **Lines affected by the `RESET` instruction on the A500** (CIAs certainly; Agnus/Paula depending on the
  board revision): no effect on what follows since exec reinitialises DMACON/INTENA, but not verified.
- **Recoverable `Alert()` without slow RAM**: immediate display expected according to the code, not observed under
  FS-UAE (§10 point 7). To be confirmed on a real machine or cycle-exact WinUAE; it is also unknown whether
  DisplayAlert 1.3 works with INTEN off.
- **Guru colour**: DisplayAlert always receives `alertNumber = 0`, yet the rendering is red even
  for "Recoverable Alert" (FS-UAE). intuition 1.3's internal colour rule has not been analysed.
- **"Mirror accepted" branch of the slow RAM** (§3): anomaly read in the code, not provoked by probe
  (FS-UAE does not emulate a module that repeats).
- **Value read at `$F00000` on a real A500** (floating bus): not measured.
- **Durations on real hardware**: all the durations of §9 and of the blinks are computed (68000
  cycles + estimate of the E-clock waits), not timed.
- **WarmCapture**: called only if `InitCode(RTF_COLDSTART)` returns; that it never returns
  on a normal floppy boot is deduced, not proven.

## Clean-room review

Review of 2026-10-29.

- [x] No disassembly excerpt; the numbered sequences (§1.2, §2, §3, §5.1, §8.3) describe
  the order of the **observable hardware and RAM accesses** (custom registers, CIA, colours, low RAM) and
  the decision conditions, not the sequencing of the instructions.
- [x] **Fixed**: removed the ROM address of the coldstart entry point (value of the reset PC); the
  constraint "first 8 bytes identical" reformulated as a header form (a compatible ROM has its
  own entry point).
- [x] **Fixed**: removed the details that belonged to the code rather than to the behaviour: name and
  opcode of the instruction placed before the entry point (replaced by its effect), mention of the way
  subroutines are chained ("no BSR/JSR"), iteration counts of the delay loops
  (replaced by the durations), values of the RAM and stack test patterns (replaced by
  "test pattern", the exact value having no ABI significance).
- [x] Remaining: public hardware/RAM addresses (`$000000`, `$C00000`, `$DFF0xx`, `$BFE001`,
  `$F00000`, low RAM `$100`/`$104`/`$180`), values written into the registers (colours, INTENA,
  DMACON, SERPER), public ExecBase offsets, validation rules of the warm reset and of the Kick
  sum (compatibility behaviour).
- [x] The probe cited (`tests/coldhw_probe.s`) is author code.
