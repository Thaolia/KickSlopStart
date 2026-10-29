# SysInfo 4.4 — startup behaviour, blocking waits, ROM requirements

> **Clean-room warning.** ANALYSIS track document. It describes only
> **observable behaviours** and **ABI contracts** (LVOs called and their arguments,
> public fields read/written, hardware registers touched, exit conditions of waits).
> It contains no copied instruction sequence and no line-by-line pseudo-code.
> The Kickstart ROM was **not** read for this work; the target is a third-party program.

## Provenance

| Item | Value |
|---|---|
| Floppy | `assets/test_adf/SysInfo.adf` (read-only) |
| File | `SYS:SysInfo/SysInfo`, 61892 bytes, `$VER: SysInfo 4.4 (11.11.2020)` (T. Geijersson / N. Wilson) |
| Format | **uncrunched** hunk executable: 7 hunks (CODE 0x8858, CODE 0x1398, CODE 0x3F4, DATA 0x38C4, DATA chip 0x534, BSS 0x20C, BSS chip 0x2564) |
| Tools | `xdftool read`, `hunktool info`, flat relocation (local Python script), `r2 -a m68k` |
| Startup-sequence | `C:SetPatch_1.38 >NIL:` → `C:Initialize` → `SYS:SysInfo/SysInfo` |

**Location conventions.** "H0+0xNNNN" = offset within the data of hunk 0
(data starts at file offset **0x38**); "H1+0xNNNN" = hunk 1 (data at file offset
**0x994C**). The file offset is given in brackets: `H0+0x6F72 [f 0x6FAA]`.

**Remark on console messages.** "Identified Kickstart 34.0 (ROM 34.5)" and
"Kickstart 1.x (<=36), SetPatch 1.38 in use." do **not** come from SysInfo but from
`C:Initialize` 1.1 (same floppy), which formats the exec version and only launches
`c:SetPatch QUIET` if the version is > 36. They only prove that the startup
sequence got as far as SysInfo.

**Strings.** Almost all of SysInfo's strings (labels, names `timer.device`,
`battclock.resource`, `card.resource`, `PAL`/`NTSC`, Agnus/Denise types…) are stored with
bit 7 of each byte set to 1 (area H0+0x4A28…H0+0x63D0) and "deobfuscated" in place at
startup by a logical AND with 0x7F. A raw `strings` therefore does not show them.

---

## 1. Order of operations at startup

### 1.0 Initialisation (H0+0x6AA4 [f 0x6ADC])

1. C-like startup code (opening dos/graphics/intuition/expansion).
2. If `ExecBase->LibNode.lib_Version` (+0x14) < 36: 5 gadgets (the cache buttons
   ICACHE/DCACHE/IBURST/DBURST/CBACK) receive `GFLG_DISABLED` (0x0100) in `gg_Flags` (+0x0C).
   This is the **only guard** protecting the V36+ calls `CacheClearU`/`CacheControl` (§4).
3. `pr_WindowPtr` (+0xB8 of the current Process) saved then forced to -1 (no DOS requesters).
4. String deobfuscation, argument parsing (`-t` = text mode, etc.).
5. Opening of the screen + window from an embedded ILBM (DATA hunk 3), then drawing of
   all the labels (`SetAPen` -342, `SetBPen` -348, `SetDrMd` -354, `RectFill` -306, text via
   `PrintIText` -216 and intuition `RefreshGList` -432 / `AddGList` -438).
6. Computation of the horizontal frequency (see 1.2, "Horiz").

### 1.1 Detection chain (H0+0x0004…H0+0x0038 [f 0x3C…0x70])

Sequential calls, in this order:

| # | Routine | Role | Displayed on ours? |
|---|---|---|---|
| 1 | H0+0x647A | CPU (AttnFlags +0x128, probes under `Supervisor` -30) | yes |
| 2 | H0+0x66AC | FPU | yes |
| 3 | H0+0x679A | MMU / VBR (`FindName` -276 on `ExecBase->ResourceList` +0x150, `Supervisor`) | yes |
| 4 | H0+0x6920 | AttnFlags consistency check (see §4) | yes |
| 5 | H0+0x699E | Caches (Disable/Enable around the probes) | yes |
| 6 | H0+0x729A | "SYSTEM SOFTWARE" list: walks `ExecBase->LibList` (+0x17A), "kickstart" entry | yes |
| 7 | **H0+0x6F72 [f 0x6FAA]** | **Hardware clock detection** ("Clock") | **NO → blocked here** |
| 8 | H0+0x6FDE [f 0x7016] | DMA/Gfx (Agnus) — displays immediately | no |
| 9 | H0+0x703C [f 0x7074] | Mode (PAL/NTSC) — displays immediately | no |
| 10 | H0+0x70E8 [f 0x7120] | Display (Denise) — displays immediately | no |
| 11 | H0+0x711A | List of volumes/units (DOS) | — |
| 12 | H0+0x7182 [f 0x71BA] | Vert Hz, Supply Hz, Horiz KHz | no |
| 13 | H0+0x721C | Card Slot (`OpenResource("card.resource")`) | — |
| 14 | H0+0x7248 [f 0x7280] | Displays "Clock" (result of #7) and EClock Hz | no |

The exact attribution of roles 1 to 5 is approximate (not needed here): these routines
run and display their fields on ours. Routines 8, 9, 10 write their field **as soon as they run**. Since DMA/Gfx, Mode and
Display are empty while the library list (#6) is drawn, execution is
stopped **inside #7** (the only call between the two). See §5.

### 1.2 Sources of each field

- **Clock** (#7, displayed in #14) — `Forbid` (-132) for the whole routine, then:
  - `OpenResource("battclock.resource")` (-498). If present: call of its LVO **-12**
    (`ReadBattClock`); result 0 → "CLOCK NOT FOUND", otherwise "CLOCK FOUND".
  - **If absent** (KS 1.3 case): direct polling of the RTC chip — **byte** read at
    **$DC0001** ("seconds, units" register, low nibble). Wait until this nibble ≠ 9,
    then **wait for 60 ticks of the CIA-A TOD** (≈1.2 s), then re-read: if the
    seconds have advanced by 1 or 2 → FOUND, otherwise NOT FOUND.
  - `Permit` (-138).
- **DMA/Gfx** (#8) — reads **VPOSR $DFF004** (word), Agnus ID = bits 14..8:
  ID = 0x23 → "AGA ALICE"; (ID>>4) > 3 → "UNKNOWN"; (ID>>4) < 2 → "STD AGNUS – 512K";
  (ID>>4) ∈ {2,3} → compares the long word at **$100004** with `SysBase` (chip mirror at 1 MB):
  equal → "ECS AGNUS – 1Meg", otherwise "ECS AGNUS – 2Meg". (The $100004 read only happens
  for an ECS Agnus.)
- **Mode** (#9) — if exec ≥ 36: `GetVPModeID`/`FindDisplayInfo`/`GetDisplayInfoData`
  (graphics -792/-726/-756) on the first screen's ViewPort. **If exec < 36**: same Agnus
  ID as above; ID ∈ {0x0A, 0x1E} → "NTSC", otherwise "PAL". No GfxBase
  field is read (not even `DisplayFlags`).
- **Display** (#10) — reads **DENISEID $DFF07C**, low byte: 0xF8 → "AGA LISA", 0xFC →
  "ECS DENISE", otherwise "STD DENISE".
- **Vert Hz** (#12) — `ExecBase->VBlankFrequency` (**+0x212**, byte); value also stored
  for all the speed computations.
- **Supply Hz** (#12) — `ExecBase->PowerSupplyFrequency` (**+0x213**, byte).
- **Horiz KHz** (computed in 1.0, displayed in #12) — exec ≥ 36: `GetDisplayInfoData`
  (DisplayInfo, PixelSpeed/… fields); **exec < 36: constant 15.72**, no read.
- **EClock Hz** (#14) — exec ≥ 36: `ExecBase->ex_EClockFrequency` (**+0x238**, long);
  **exec < 36: constant** chosen according to `VBlankFrequency`: 50 → 709379, otherwise 716933.
  No measurement, no hardware read.
- **Card Slot** (#13) — mere presence of `card.resource`.

### 1.3 Speed tests (after the chain, H0+0x003C…H0+0x0624)

Order:

1. Displays "COMPUTING SPEED" (progress bar), then **H1+0x0000 [f 0x994C]**:
   `WaitTOF` (graphics -270), then turns off sprite DMA (DMACON $DFF096 ← $0020) and clears
   SPR0POS/SPR0CTL ($DFF140 ← 0x00020000). The pointer disappears during the tests.
2. Clears the "You" column (`RectFill`).
3. `Forbid` → **Dhrystone** (H0+0x3068 [f 0x30A0]) → `Permit`. Measured by a VBlank counter (§2.3).
4. Six comparisons (A500, B2000, A2500, A1200, A3000, A4000) = ratio of the score obtained to
   constants; displayed one by one. Then Dhrystones/s and Mips.
5. If an FPU is detected: MFlops (H0+0x40D0, `WaitTOF` + VBlank counter); otherwise "N/A".
6. `Forbid` → **Chip RAM speed** (H0+0x35CE [f 0x3606]) → `Permit`; display.
7. "Nics Comment": text chosen by thresholds on the Dhrystone score (no system read,
   except AttnFlags bit 10 for a 68080).
8. "COMPUTING MHz" → `Forbid` → **MHz test** (H0+0x2F70 [f 0x2FA8]) → `Permit` → displays
   "CPU speed in MHz" (corrected according to `VBlankFrequency` +0x212 or `ex_EClockFrequency` if V36+).
9. **H1+0x0022 [f 0x996E]**: `WaitTOF` then restores sprite DMA (DMACON ← $8020).
10. IDCMP event loop (`WaitPort` -384 / `GetMsg` -372 / `ReplyMsg` -378) — normal
    wait, not a hang.

timer.device is **not** used at startup: it is only opened by the DRIVES page
(see §2.6).

---

## 2. Blocking waits and wait loops

### 2.1 RTC polling $DC0001 — H0+0x6FA0 [f 0x6FD8] ("no battclock.resource" path)

- Repeated byte read of $DC0001, low nibble; **exit: nibble ≠ 9**.
- Under `Forbid`. No bound.
- With a real RTC (MSM6242), the digit changes every second: exit in ≤ 1 s.
- Without an RTC, the value read is the emulator's "open bus" value: the loop only blocks
  if that value **constantly** has 9 in the low nibble. Unlikely, but to be checked (§5).

### 2.2 Wait for 60 CIA-A TOD ticks — **H0+0x3364 [f 0x339C]** (called only from H0+0x6FAC)

- Read of the 24-bit TOD counter of **CIA-A** by **H1+0x0C0E [f 0xA55A]**: bytes
  **$BFEA01 (TODHI)**, then **$BFE901 (TODMID)**, then **$BFE801 (TODLO)**, in this order
  (reading HI = latch, reading LO = unlatch).
- A first sample is taken, then the counter is re-read in a loop until
  **(current − initial) == 60 exactly** (equality, not ≥).
- Still under the clock detection's `Forbid`. No time bound.
- **What must satisfy it:** the CIA-A TOD must **count** (increment of 1 per
  VSYNC/50 Hz pulse, TOD input wired in hardware). Missed exit conditions:
  1. **TOD stopped**: the 8520 stops the TOD on a write to TODHI and only restarts it on
     a write to TODLO (with CRB bit 7 = 0). In UAE, the TOD is stopped after reset as long
     as TODLO has not been written (emulation behaviour, to be confirmed by a probe). If nobody
     writes TODLO → difference frozen at 0 → **infinite loop**.
  2. **Stale first sample**: if the TOD was left **latched** (TODHI read
     without a later TODLO read) for more than 1.2 s, the first sample is
     old, the difference exceeds 60 straight away and never comes back to it (until the 24-bit
     wrap-around, ~93 h).
  3. **Value skip**: if a tick is skipped between two reads (an interrupt that
     lasts > 20 ms under this `Forbid`), the exact equality can be missed.

### 2.3 Dhrystone — H0+0x3068 [f 0x30A0], exit test H0+0x30DE [f 0x3116]

- Sets a long counter to 0, `WaitTOF`, then **`AddIntServer(INTB_VERTB=5, node)`** (-168).
  Node at **H0+0x4564 [f 0x459C]**: `ln_Type` = NT_INTERRUPT, `ln_Pri` = **127**,
  `ln_Name` = "Sysinfo.Interrupt", `is_Data` = address of the counter, `is_Code` =
  H0+0x33D2 [f 0x340A].
- The server: increments the long word pointed to by **A1 (= is_Data)**, sets A0 = $DFF000,
  D0 = 0 (Z flag set), returns; it **clobbers A5**.
- Computation loop while counter < **4 × VBlankFrequency** (+0x212), then
  `RemIntServer` (-174). Run under `Forbid` (interrupts must keep running).
- **What must satisfy it:** the VERTB server chain (level 3, INTREQ bit 5) must be
  called on every frame, with **A1 = is_Data**, without relying on A5/A0/D0/D1 being preserved.
  If `VBlankFrequency` = 0, the loop exits at once (absurd score, see 2.5).

### 2.4 Generic measurement start/end — H0+0x3376 [f 0x33AE]

- Toggle (bit 0 of a BSS byte): 1st call = `AddIntServer(5, same node)` + TOD
  sample; 2nd call = `RemIntServer`, returns (VBlank counter − 1) and stores a TOD delta
  (**never reused** elsewhere). Used by the MHz test (H0+0x2F70), Chip RAM
  (H0+0x35CE), the blitter (SPEED button) and memory (SPEED button).
- **What must satisfy it:** same VERTB requirement as 2.3. The TOD is only read there for an
  unused result: it cannot block here.

### 2.5 Chip RAM speed — adaptive loop H0+0x363A [f 0x3672]

- Measures the number of VBlanks during a block of `MOVEM` reads of Chip RAM; if
  **≤ 25 frames**, the number of iterations is multiplied (~×100) and it starts again. **No
  bound**: if the VBlank counter does not progress, the loop never ends in practice.
- Divisions by `VBlankFrequency` if ≠ 50: **VBlankFrequency = 0 → division by
  zero exception** (also in the MHz test, H0+0x2FC6 [f 0x2FFE]).

### 2.6 Other waits (outside the startup path)

| Location | Wait | Exit condition | Trigger |
|---|---|---|---|
| H0+0x4546 [f 0x457E] | polling **VHPOSR $DFF006**, high byte | vertical line (bits 7..0) == 1 | refresh of the SYSTEM SOFTWARE list (#6, **passes on ours**) |
| H0+0x3800, H0+0x3836 | same ($DFF006 == 1) | same | SPEED button / `-t` option |
| H0+0x2A92 [f 0x2ACA] | `DoIO` (-456) `TR_GETSYSTIME` loop (cmd 10, `io_Flags` = IOF_QUICK) | `tv_micro` (+0x24 of the IORequest) has advanced by at least 10 µs (signed comparison) | DRIVES page ("READING THE DRIVE") |
| `WaitTOF` (graphics -270) | ~9 calls | graphics returns after the next frame | speed tests |
| H1+0x0066… | `WaitPort`/`GetMsg` | IDCMP message | main loop (normal) |

timer.device (DRIVES page): `OpenDevice("timer.device", unit, ior, 0)` (-444) with
**unit = UNIT_ECLOCK (2) if exec ≥ 36, otherwise UNIT_VBLANK (1)**; IORequest of 0x28 bytes;
`SubTime` (timer LVO -48); `CloseDevice` (-450). Our `TR_GETSYSTIME` must therefore make
`tv_micro`/`tv_secs` advance as VBlanks go by, otherwise the DRIVES page will freeze.

---

## 3. Detections

- **Kickstart.** `ExecBase->LibNode.lib_Version` (+0x14) compared with 36 in many places
  (V34 vs V36+ path). For the "kickstart" entry of the list: takes
  `ExecBase->LibNode.lib_IdString` (+0x18), **rounded to 64 KB** → assumed ROM base; if
  the long word at that base is **$11114EF9** → 256 KB ROM, otherwise 512 KB; displays address and
  version/revision. (Another path reads the initial PC vector at $F80004.) Exec's `lib_IdString`
  must therefore point into the first 64 KB of the ROM ($FC0000–$FCFFFF).
- **Chipset.** VPOSR $DFF004 (Agnus ID bits 14..8) and DENISEID $DFF07C (low byte), cf. §1.2.
  The long word at $100004 is only read if the Agnus is ECS.
- **PAL/NTSC.** In V34: **Agnus ID** (not GfxBase). `GfxBase->DisplayFlags` is **never**
  read. `VBlankFrequency` (+0x212) and `PowerSupplyFrequency` (+0x213) are used for Vert/Supply
  and for all the speed/EClock computations.
- **EClock.** In V34: constant 709379 (if VBlankFrequency = 50) or 716933; +0x238 is only read
  if exec ≥ 36 (or if AttnFlags bit 10 "68080" is set, a case that also reads the
  Vampire-specific register $DFF3FC).
- **Clock.** `battclock.resource` (LVO -12) if present, otherwise RTC at **$DC0001** directly +
  CIA-A TOD wait (§2.1, 2.2). No cia.resource, no timer.device.

---

## 4. Private / > V34 accesses and guards

| Access | Guard | Verdict |
|---|---|---|
| exec `CacheClearU` (-636, V37) | version ≥ 36 in the Dhrystone; in the cache buttons, **indirect** guard: gadgets disabled if V < 36 | safe in V34 as long as our disabled gadgets do not respond |
| exec `CacheControl` (-648, V36) | cache buttons only (disabled in V34) | same |
| graphics `GetVPModeID` -792, `FindDisplayInfo` -726, `GetDisplayInfoData` -756 (V36) | version ≥ 36 | safe |
| `ExecBase->ex_EClockFrequency` +0x238 (V36) | version ≥ 36, or AttnFlags bit 10 | safe if our AttnFlags does not have bit 10 |
| $DFF3FC | AttnFlags bit 10 | safe |
| `ExecBase->AttnFlags` +0x128 **written** | only if the CPU/FPU detection contradicts AttnFlags **and** the user accepts the "Exec does not reflect your hardware correctly" requester | does not happen on ours (no requester observed) |
| `pr_WindowPtr` +0xB8 written (-1), restored on exit | — | public V33 field |
| $DC0001 (RTC), $BFE801/$BFE901/$BFEA01 (CIA-A TOD), $DFF004, $DFF006, $DFF07C, $DFF096, $DFF140, $100004 | — | hardware, read/written directly |

No LVO > V34 is called without a guard on the startup path. The ExecBase fields read are
all public V34: +0x14, +0x18, +0x128, +0x150 (ResourceList), +0x17A (LibList), +0x212, +0x213.

---

## 5. Main hypothesis for the hang

**SysInfo is stuck in clock detection (#7, H0+0x6F72), under `Forbid`, waiting
for 60 ticks of the CIA-A TOD (H0+0x3364).** Reasoning:

1. The SYSTEM SOFTWARE list (#6) is drawn and DMA/Gfx (#8) is not; #7 is the only
   code executed between the two, and #8–#10 wait for nothing.
2. Our ROM does not provide `battclock.resource` (nor does the real 1.3) → direct RTC path
   + TOD wait.
3. Our ROM never writes the CIA-A TOD registers (no reference to TODLO/TODMID/TODHI
   in `src/`). If the TOD is stopped after reset (UAE model), the difference stays 0 →
   infinite loop, with no CPU exception. The `Forbid` also freezes all our other tasks, hence
   "nothing moves any more".

Secondary, less likely hypothesis: FS-UAE without an RTC returns at $DC0001 an open-bus
value whose low nibble is always 9 (loop §2.1).

**Proposed confirmation probe** (harness side, without touching SysInfo): in a test build,
read the CIA-A TOD (HI, MID, LO) at two instants a few frames apart and print the
two values on the serial port; also read $DC0001 several times. Frozen TOD = hypothesis confirmed.

Once unblocked, the speed tests impose the VERTB requirements of §2.3–2.5 (otherwise a hang
in the Chip RAM loop, with no bound).

---

## Requirements for our ROM

1. **Start the CIA-A TOD** during init (as the OS would do for its VSYNC
   clock): write TODHI, TODMID then **TODLO last** with **CRB bit 7 (ALARM) = 0**; never
   leave the TOD latched (every TODHI read must be followed by a TODLO
   read). The TOD must then increment by 1 per frame.
2. Do not run, in our interrupt handlers, processing longer than one frame (20 ms)
   — SysInfo waits for an exact TOD delta value under `Forbid`.
3. **VERTB server chain** (`AddIntServer`/`RemIntServer` INTB_VERTB = 5): called on
   every frame, priority 127 at the head, **A1 = is_Data**, A5 = is_Code; do not rely on A0,
   A1, A5, D0, D1 being preserved on return; honour the returned Z flag (Z = 1 → continue the
   chain). SysInfo's server returns A0 = $DFF000 (1.x convention for VERTB servers).
4. `ExecBase->VBlankFrequency` (+0x212) = 50 and `PowerSupplyFrequency` (+0x213) = 50
   (already the case in our boot) — a value of 0 would cause a division by zero.
5. `ExecBase->LibNode.lib_IdString` within the first 64 KB of the ROM, ROM starting with
   `$1111 4EF9` ("kickstart" entry and size 256K).
6. Exec `lib_Version` < 36 (34) to stay on the V34 paths; AttnFlags without bit 10; the
   `GFLG_DISABLED` gadgets must neither respond nor send GADGETUP (otherwise V36 calls
   `CacheControl`/`CacheClearU` to non-existent vectors).
7. VPOSR/DENISEID readable (hardware); `WaitTOF` (graphics -270) that returns on every frame.
8. Optional: a `battclock.resource` with `ReadBattClock` (LVO -12) would short-circuit the
   RTC + TOD polling (a return of 0 = "CLOCK NOT FOUND"). It is not a 1.3 resource;
   requirement 1 is the compatible fix.
9. For the DRIVES page: timer.device `UNIT_VBLANK`, `TR_GETSYSTIME` via `DoIO` with IOF_QUICK
   whose time advances, and a working `SubTime` (LVO -48).

---

## Follow-up 2026-10-21 — grey screen, serial bytes, robustness of waits

> Same discipline: behaviour and ABI only, no copied instruction sequence.
> Context: the TOD of both CIAs is now started by our init; the §2.2 wait passes.
> Symptoms: grey band at the top then black at 120 s, entirely plain grey screen at 300 s;
> on the serial port, a $FC byte then "f" ($66) characters about every 30 s.

### S1. What follows clock detection, and what SysInfo does to the display

Order (unchanged, see §1.1/§1.3): DMA/Gfx → Mode → Display → list of DOS units → Vert/Supply/
Horiz → Card → Clock/EClock → speed tests → event loop.

**Exhaustive** inventory of the "custom" hardware writes in the whole code (hunks 0 and 1):

| Location | Register | Value / effect | When |
|---|---|---|---|
| H1+0x0000 [f 0x994C] | DMACON $DFF096 | $0020: turns off **only sprite DMA** | start of the speed tests, after a `WaitTOF` |
| H1+0x0000 | SPR0POS/SPR0CTL $DFF140 (long) | $00020000 | same |
| H1+0x0022 [f 0x996E] | DMACON | $8020: restores sprite DMA | end of the speed tests, after a `WaitTOF`; **unconditional** (no error condition) |
| H1+0x011A…0x0172 | AUD0LC/LEN/PER/VOL ($DFF0A0…), ADKCON $DFF09E ← $00FF, DMACON $8201 then $0001 | beep on audio channel 0, dos `Delay` between the two | only on a main loop event |

SysInfo **never** writes BPLCON0, the colours ($DFF180…), COP1LC/COPJMP, BPLxPT, DIWSTRT/STOP,
nor the bitplane/copper/DMAEN bit of DMACON. It calls neither `LoadView` (graphics -222), nor
`OFF_DISPLAY`, nor `LoadRGB4`/`SetRGB4` on the screen palette during the measurements (the only
palette load is the one when the screen is opened from the ILBM). **No measurement
produces a plain grey screen**: during the tests, the display remains that of its screen, only the
pointer disappears.

A plain grey screen with no bitplane corresponds to "no intuition screen displayed" (COLOR00 only).
In SysInfo, the only path that removes its display is **exit** (QUIT gadget):
`CloseWindow` (-72) then `CloseScreen` (-66) of its screen, `ActivateWindow` (-450) on the
first window of the remaining `FirstScreen` (IntuitionBase +0x3C → +0x04), restoration of
`pr_WindowPtr`, return to the CLI with code 0. SysInfo is the last command of the
startup-sequence: the CLI then ends (end of script). If no screen is left at that point,
our ROM displays plain grey.

**Event loop (H0+0x0674, helper H1+0x0060) — fragile point.** Main window:
IDCMP = **GADGETUP only** ($00000040), flags BACKDROP/BORDERLESS/ACTIVATE/NOCAREREFRESH,
CUSTOMSCREEN screen opened behind (SCREENBEHIND) then brought to the front (`ScreenToFront` -252).
On each wake-up:
- `WaitPort` then `GetMsg` on the window's UserPort (Window +0x56);
- if `GetMsg` returns NULL, the helper returns A0 = 0 but **A1 stays whatever `GetMsg` left**;
- otherwise: A1 = `im_IAddress` (+0x1C), D0 = `im_Class` (+0x14), D1 = `im_Code` (+0x18),
  D2 = `im_Qualifier` (+0x1A); the message is **replied (`ReplyMsg`) unless the class is 8
  (MOUSEBUTTONS)**, which is never replied;
- the caller **does not test the class**: it directly reads `GadgetID` (+0x26) at address A1 and
  dispatches. ID 1 → **QUIT**; ID 2 → rerun of the speed tests; 4, 6, 7, 8, 9, 10, 12–17 →
  pages and cache buttons; **any other ID** (including a random value) → PRINT
  requester then `Open` (dos -30) of "prt:" or of the entered name, in MODE_NEWFILE, and the report is written.

So any message received that is not a real GADGETUP from a SysInfo gadget (other class, or
`WaitPort` wake-up without a message) causes a random `GadgetID` to be read, and can trigger QUIT,
SPEED or PRINT without any user action.

### S2. The VERTB server and other installations

- Single server, node H0+0x4564 [f 0x459C] (pri 127, NT_INTERRUPT, "Sysinfo.Interrupt"),
  code H0+0x33D2 [f 0x340A]. **It returns Z = 1** (and D0 = 0): the last operation that sets the
  condition codes before returning is loading the constant 0 into D0; loading
  $DFF000 into A0, which precedes it, does not touch the CCR (address register). A chain that
  continues while Z = 1 **continues** after it.
- Registers modified by the server: the long word pointed to by A1 (incremented), **A0 ← $DFF000**,
  **D0 ← 0**, **A5 ← entry value of D0**. A1 is not modified. Our chain walk must not
  keep its state (current/next node) in any of D0/D1/A0/A1/A5/A6.
- This same node is added/removed by `AddIntServer`/`RemIntServer` (INTB_VERTB) around each
  measurement (Dhrystone, MHz, Chip RAM, MFlops, blitter, memory). It is never added twice
  at the same time (state toggle).
- No `SetIntVector` (-162), no other interrupt number, no direct write into the
  CPU vectors ($64/$68/$6C… or others), no `movec`/VBR write.
- **Trap interception by the task**: to probe the FPU/MMU, it temporarily replaces
  `tc_TrapCode` (+0x32 of its Task) with its own routine, executes an instruction that traps on a
  68000 (line F), then puts the old value back. Expected contract: the CPU exception of a task in
  user mode is sent to `tc_TrapCode` with the trap number on top of the supervisor
  stack; the routine removes it and does an RTE to a resume address of its choosing.
  This already works on ours ("FPU NONE" displayed).
- `Disable`/`Enable` (-120/-126): a single, short pair, in the cache probes (#5). The
  long measurements are under **`Forbid`**, never under `Disable`.

### S3. Serial port

SysInfo **never writes** SERDAT ($DFF030) or SERPER ($DFF032), in any form (absolute
address or offset from a $DFF000 base). Its measurement loops only **read**:
- Chip RAM test: consecutive long reads from **$000200 to ≈$07FC00** (chip only,
  never custom registers);
- SPEED button memory test: reads from an allocated area;
- Dhrystone and MHz: computation on registers and reads from a small table in its hunk.

The only SysInfo path that can produce bytes on a port is **PRINT** (S1): `Open`
of "prt:" then writing of the text report. If our PRT: is redirected to the serial port, a PRINT
triggered by mistake (random gadget ID) would write there. The observed pattern ($FC then an "f"
every ~30 s) does not look like that report (long, readable text): it more probably
comes from elsewhere (our ROM, or a corrupted pointer writing to $DFF030). Nothing in SysInfo
has a 30 s period.

### S4. Loops that do not terminate, depending on the fault

| Fault | Blocked loops (unbounded) | Visible effect |
|---|---|---|
| (a) VERTB chain cut **after** its server | none on the SysInfo side (its counter still runs); but under `Forbid` our following servers (scheduler, timer.device, graphics/`WaitTOF`) no longer run → see (b) and (c) | |
| (a') its server **not called** (chain cut before it, or wrong A1) | Dhrystone (exits when counter ≥ 4×VBlankFrequency); **Chip RAM** (starts again multiplying the work while ≤ 25 frames: 2.6 s, then ~280 s, then hours); MHz/MFlops finish but with wrong values | frozen under `Forbid`, display intact |
| (b) timer.device silent | none at startup (timer.device is only opened by the DRIVES page); DRIVES page: `DoIO` `TR_GETSYSTIME` in a loop as long as `tv_micro` has not advanced by 10 µs | — |
| (c) `WaitTOF` does not return | blocks before Dhrystone (H1+0x0000), before MHz, before MFlops, before Chip RAM, and at the end of the tests (H1+0x0022) | sprite off, no result |
| (d) `Disable` active | TOD wait §2.2 (the TOD advances in hardware, so it passes); **all** measurements by VBlank counter (no interrupts) → Dhrystone and Chip RAM endless; VHPOSR line wait (§2.6): passes (hardware) | frozen |
| main loop | `WaitPort`: blocks as long as no message arrives (normal) | |

### S5. Diagnosis and additional requirements

**Most likely cause of the grey screen:** SysInfo does not act on the display. The plain grey screen
corresponds to **its screen being closed**: exit via the QUIT path, then end of the
startup-sequence CLI, and no screen is left. Since nobody clicks, the likely trigger
is an **IDCMP message that is not a real GADGETUP** (or a `WaitPort` wake-up without a message).
The event loop takes it for a click on a gadget whose `GadgetID` is read at random.
To be confirmed: trace on the serial port `CloseScreen`, the end of the SysInfo process and every `PutMsg`
to its UserPort (class, IAddress).

Our ROM must guarantee:
1. Intuition sends a window **only the IDCMP classes requested** (here GADGETUP alone); for
   GADGETUP, `im_IAddress` = the `struct Gadget` of the released gadget (GadgetID read at +0x26).
2. `WaitPort` only returns if the port's list is not empty (it loops again on a wake-up without a
   message), so that the following `GetMsg` never returns NULL.
3. VERTB chain walk: continue on Z = 1, keep no state in D0/D1/A0/A1/A5/A6
   while a server is called, reload A1 = is_Data and A5 = is_Code for each server.
4. `WaitTOF` returns on every frame, even under `Forbid` (wake-up from the interrupt).
5. CPU exceptions in user mode sent to the current task's `tc_TrapCode`.
6. If PRT: is redirected to the serial port, be aware of it: a PRINT triggered by mistake would write the
   report there.

## Clean-room review

Review of 2026-10-29.

- [x] Target = third-party program SysInfo 4.4 (disassembly allowed); the Kickstart ROM was not read.
  The locations "H0+… / H1+… [f …]" are offsets **within SysInfo**, not within the ROM.
- [x] No ROM routine address and no Kickstart ROM data transcribed: the only
  ROM-related values are the public header `$1111 4EF9`, the expected position of `lib_IdString`
  (first 64 KB) and public offsets of ExecBase/Process/Window/IntuiMessage; the other addresses
  are hardware (`$DFF0xx`, `$BFE801…`, `$DC0001`) or from the generic ROM area (`$F80004`).
- [x] The instruction details mentioned (S2: how SysInfo's VERTB server sets Z)
  concern SysInfo's code and serve to pin down the contract our VERTB chain must honour.
