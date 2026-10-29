# alert-v34.md — Alert, DisplayAlert and alert.hook in Kickstart 1.3 (34.5)

> **Behavioural** spec (ANALYSIS track, spec no. 3 of `coverage-v34.md` §7). It **complements without
> repeating** `coldstart-hardware-v34.md` §8 (persistence of `HELP`/`$100`/`$104`, Alert decision tree,
> hard path with LED blinking and ROM-Wack, delay and text of alert.hook), to which it refers.
> No instruction sequence is copied or paraphrased, no ROM routine address is cited:
> only behaviours, values, displayed texts, orders of operations and ABI layouts.
>
> Legend: **[O]** observed in the binary `kick34005.A500` (radare2, base `$FC0000`) ·
> **[S]** black-box probed under FS-UAE (A500, real ROM; `tests/alert_probe.sh`, `tests/coldhw_probe.sh`) ·
> **[D]** deduced (reasoning on [O]/[S] or public hardware documentation, not executed).

---

## 1. exec `Alert(alertNum = D7, A5)` — LVO −108

### 1.1 Reminder of the tree (details in `coldstart-hardware-v34.md` §8.1-8.3)
- First effect: **INTENA ← `$4000`** (master off), without touching `IDNestCnt`. **[O]**
- Writes `'HELP'` at `$0`, alertNum at `$100`, **the long pointed to by A5** at `$104`. **[O]**
- **Hard path** (LED ×6 + serial listening for DEL → ROM-Wack, otherwise reset; screen not modified) in any of the
  following cases: `HELP` already present (nested alert); ExecBase judged invalid (`*(4) & $00FF0001 ≠ 0`, hence
  also **any ExecBase in slow RAM `$C00276`**, or `ExecBase + ChkBase ≠ $FFFFFFFF`); the current stack does not
  read back a written long; **bit 31 set (dead-end)**. **[O]**
- Otherwise **immediate display** by the same routine as the alert.hook resident (§4), preceded by that
  routine's fixed delay of ≈ 1 s (master interrupts still off). **[O]**

### 1.2 Recoverable / fatal distinction — what the caller sees
| alertNum | Path | Return to the caller |
|---|---|---|
| bit 31 = 1 (dead-end, `AT_DeadEnd`) | always hard path → reset → Guru at the next boot by alert.hook | **never** |
| bit 31 = 0, high word ≠ 0 (recoverable, normal `Alert()` call) | immediate display if ExecBase "low" and valid; otherwise hard path | yes (immediate case only) |
| high word = 0 (vector number: CPU exception of a task) | immediate display, then **left → reset**, **right → ROM-Wack** | never |

- The "recoverable" test is done **on the whole high word** (`alertNum & $FFFF0000 ≠ 0`), not on a dedicated
  bit: an `Alert($00000005)` called by a program is treated as a **CPU exception** (no
  return: reset or ROM-Wack depending on the button). Worse: this path reloads **all the registers, A7 included,
  from `$180-$1BF`**, an area that an `Alert()` call has not filled (leftovers of the last exception or
  zeros). A reimplementation can treat this case as a recoverable alert with no known compatibility
  risk. **[O]** (scope **[D]**)
- **Return from a recoverable `Alert()`** **[O]**:
  - interrupts: if `IDNestCnt < 0` (caller not `Disable()`d), INTENA ← `$C000`; otherwise the master
    **stays off** (the caller will do `Enable()`);
  - **D0** = value returned by DisplayAlert (1 = left button, 0 = right button). If intuition could not
    be opened, D0 = **value of A2 on entry** (undefined);
  - **D7 is modified**: it comes out with `alertNum & $FFFF0000` (low word cleared). D1/A0/A1 destroyed,
    **A6 = ExecBase**, A2-A5 and D2-D6 preserved. A reimplementation may preserve D7 (no known caller
    reads D7 after Alert) but must return the boolean in D0. **[O]** (scope **[D]**)
- `LastAlert[0..1]` receives (alertNum, long pointed to by A5) before the display; after the display, the routine
  resets `$0` to 0 and `LastAlert[0]` to `$FFFFFFFF` (the Guru is therefore **not** displayed again at the next reset).
  `$100`/`$104` and `LastAlert[1]` keep their values. **[O]**

### 1.3 Availability of intuition
- The display routine opens `intuition.library` (version 0) by `OpenLibrary` then closes it. **[O]**
  - Open impossible (alert before intuition's init, pri 10; or library removed): **nothing is
    displayed**, `$0` and `LastAlert[0]` are still reset to 0 / `$FFFFFFFF`, and the "returned" value is
    undefined (A2). For a CPU exception, the reset / ROM-Wack decision then depends on this undefined
    value (A2 of the faulting task ≠ 0 → reset). **[O]**
  - There is **no other display fallback** in exec 1.3 (no home-made red screen, no serial
    text): without intuition, only the hard path (LED) is visible. **[O]**
- Before intuition's init (residents of priority > 10), a "recoverable" alert is therefore lost
  silently; a dead-end goes through reset and will be displayed **at the next boot** by alert.hook, after intuition.
  **[D]**

### 1.4 System state during the immediate display
- INTENA master off on entry; **no** explicit `Disable()`/`Forbid()`; multitasking is not
  stopped by exec. The display routine calls `OpenLibrary`, then DisplayAlert which calls
  `ObtainSemaphore`, `AllocMem`, and intuition's display recalculation (including **`WaitTOF`**). **[O]**
- Consequence: DisplayAlert **can only complete if the VBlank interrupt is served** (WaitTOF). The
  first `Enable()` executed by a called function (exec `Wait`, etc.) re-enables the master since
  `IDNestCnt` remained negative. See §5 point 6 (blocking observed under FS-UAE) and "Open points". **[D]**
- DMA: only **sprite** DMA is turned off while waiting for the click (§2.6); bitplanes, copper, blitter,
  disk and audio continue. **[O]**

---

## 2. intuition `DisplayAlert(alertNumber = D0, string = A0, height = D1)` — LVO −90

### 2.1 Format of the string **[O][S]**
Sequence of blocks, each:
| Bytes | Contents |
|---|---|
| 2 | **x** (16-bit big-endian word, in hires pixels) |
| 1 | **y** (byte, **base**line of the text, in non-interlaced lines from the top of the alert) |
| n+1 | ASCII text terminated by `0` |
| 1 | **continuation byte**: ≠ 0 → another block follows immediately; 0 → end |

- Each block = `Move(x, y)` then `Text()` of the whole string; no line break or splitting. **[O]**
- **No clipping**: the alert's RastPort has no layer. A y greater than the height, or a text
  exceeding the width, writes **outside the raster** (chip memory corruption). The implicit contract is that
  the caller stays within the frame. **[O]** (consequence **[D]**)

### 2.2 Value of `alertNumber`
- DisplayAlert examines **only bit 31** (`AT_DeadEnd`). No other bit (neither the code, nor the subsystem)
  changes the colour, the text or the behaviour. **[O]**
- Effects of bit 31: (a) the screens are not shifted but **removed from the view** (§2.4); (b) without
  intuition's lock during the setup; (c) if the raster cannot be allocated, fallback to exec `Alert()`
  (§2.8). **[O]**

### 2.3 Raster, RastPort, ViewPort
- Width **W = the private IntuitionBase word that also serves as the width of the Workbench screen** (640 as
  standard). **[O]** Measured: **640** (`$280`) on a default PAL A500. **[S]**
- Raster: **1 plane**, `H = height` lines, `((W+15)/8 rounded to even)` bytes per line, allocated in
  `MEMF_CHIP` (without `MEMF_CLEAR`) then cleared by `SetRast(0)`. Size = `height × 80` for W = 640. **[O]**
- `InitBitMap(depth 1, W, height)`, `InitRastPort` (font = **graphics default font**, that of
  Preferences: topaz 8 as standard, topaz 9 if the user chose 60 columns), `SetRast(0)`. **[O]**
- Own ViewPort (no intuition screen): `DxOffset = DyOffset = 0`, `DWidth = W`, `DHeight = height`,
  **`Modes = HIRES | SPRITES` (`$C000`)**, non-interlaced, RasInfo at offset 0. `MakeVPort` on intuition's
  View (or, in dead-end, on a local View initialised by `InitView`). **[O]**
- The alert's ViewPort is **chained at the tail** of the list of ViewPorts of intuition's View; since
  the screens have been shifted down (§2.4), it occupies the top of the display. **[O]**

### 2.4 Existing screens
- **Recoverable (bit 31 = 0)**: under intuition's internal lock, **each screen** of the list is
  moved down by **`height + 1`** lines (value doubled for an interlaced screen), with a complete
  recalculation of the display at each screen. At the end, each screen moves back up by the same amount (move-up bounded
  at `TopEdge = 0`). The user therefore sees his screens slide under the alert, an empty separation
  line, then come back. **[O]** Observed: 320×200 screen opened at the top, during `DisplayAlert(0, …, 40)` the
  screen's title bar appears **41 lines** below the top of the alert (39 frame lines, 1 background
  line, 1 black separation line between ViewPorts); after the click, the screen is back at the top. **[S]**
  Artefact observed under FS-UAE: a few lines of the background colour of the shifted screen (≈ 6) remain
  visible **above** the alert, before the alert's copper list loads its colours; a
  reimplementation does not have to reproduce it but should not be surprised to see it. **[S]**
- **Dead-end (bit 31 = 1)**: the pointer to the first ViewPort of intuition's View is **set to NULL**,
  the alert's ViewPort becomes the only ViewPort; the screens disappear from the display. **[O]**
  After the click, the alert is removed and the display recalculated, **but the chain of the screens' ViewPorts
  is not rebuilt**: the screen opened before stays **invisible** (whole display at background `$111`),
  although it is still open. Observed: screen "SONDE" not reappeared after `DisplayAlert($80000000,
  …, 60)` + right click, nor 3 s later. **[S]** No consequence in normal use, since a
  dead-end alert is followed by a reset. **[D]** During the alert, the whole display below the alert is at background
  `$111` (no other ViewPort). **[S]**
- In all cases, after installation: complete recalculation of the display (`MrgCop`, `LoadView`, `WaitTOF`,
  bitplane and sprite DMA turned back on). **[O]**

### 2.5 Palette, frame, text
- Colours set by `SetRGB4` on the alert's ViewPort, **identical for all alerts**:
  - **COLOR00 = `$111`** (almost black);
  - **COLOR01 = `$F20`** (orange-red: R = 15, G = 2, B = 0) — text and frame.
  Measured on a capture: background (17,17,17), text/frame (255,34,0). **[O][S]**
- **Frame** (drawn before the text, pen 1, JAM1 mode) **[O]**:
  - vertical bands of **6 pixels** on the left (`x = 0..5`) and on the right (`x = W−6..W−1`), lines
    `0..height−2`;
  - horizontal bands of **3 lines** at the top (`y = 0..2`) and at the bottom (`y = height−4..height−2`), between
    `x = 6` and `x = W−7` (without overlap with the vertical bands);
  - the **last line** of the raster (`y = height−1`) stays at the background.
- **Text**: pen 1, JAM1 mode, default font, at the positions given by the string. **[O]**
- **Blinking**: the frame is redrawn in **COMPLEMENT** mode at each expiry of a counter of
  **26,633** button polls; it therefore alternates present/absent, the text stays fixed. **[O]**
  Measured (VBlank probe, calling task, interrupts active): toggles every **45 to 48
  frames** at 50 Hz (≈ 0.92 s per phase, ≈ 1.85 s per cycle), identical in recoverable and in dead-end. The
  frame is **present from the display onwards** (first toggle = initial drawing). **[S]**
- Observed: topaz 8 font (glyphs of lines `y−6 … y+1` for a baseline `y`), x ≥ 256 accepted
  (`$0130` = 304 correctly placed), mouse pointer absent during the alert. **[S]**

### 2.6 Waiting for the buttons
- Before the wait: **DMACON ← `$0020`** (sprite DMA off → mouse pointer invisible). **[O]**
- Phase 1: wait for **both buttons to be released**. **[O]**
- Phase 2: **active** polling loop (no Wait, no interrupt): at each round, direct read
  - **left** button: **CIA-A PRA bit 6** (`$BFE001`, /FIR0, port 0), pressed = 0;
  - **right** button: **POTGOR (POTINP `$DFF016`) bit 10** (DATLY, port 0), pressed = 0.
  No write to POTGO: reading the right button assumes that POTGO has already been configured (which
  the system does at boot). **[O]** (POTGO dependency **[D]**)
  - left pressed → result **TRUE (1)**; right pressed → **FALSE (0)**; if both are seen in the same
    round, **left wins**. **[O]**
- Phase 3: wait again for **both buttons to be released**. **[O]**
- **No timeout**, whatever the alert (recoverable or dead-end). **[O][S]**
- Only mouse port 0 is read; neither keyboard nor joystick validates the alert. **[O]**

### 2.7 Restoration
Under the internal lock: removal of the alert's ViewPort from the list, `FreeVPortCopLists`, moving the
screens back up (§2.4), complete recalculation of the display (also turns sprite DMA back on), then `FreeMem` of the raster.
Returned value: **1 (left) or 0 (right)**, extended to long. **[O]** Measured: 1 after left click,
0 after right click; DMACONR after return = `$23F0` (sprites back on). **[S]**

### 2.8 Raster allocation failure **[O]**
- Recoverable: DisplayAlert returns **FALSE immediately**, without displaying anything. Measured: height 7000
  (560,000 bytes) → 0, return in less than one frame, screen unchanged. **[S]**
- Dead-end: call of **exec `Alert(alertNumber)`** (A5 not initialised → undefined second number) → exec's hard
  path (§1.1) → reset, then Guru at the next boot. Measured: no display, reset after ≈ 5 s, then at the
  next boot `$100 = $80000000`, `$104 =` undefined value (0 in the probe), Guru
  "Software Failure.  Press left mouse button to continue. / Guru Meditation #80000000.00000000". **[S]**

---

## 3. Guru text (common exec / alert.hook routine)

Built on the stack in the §2.1 format then passed to `DisplayAlert(0, text, 40)` **[O]**:

| Block | x | y | Text (exact, spaces included) | Continuation |
|---|---|---|---|---|
| 1 | 38 | 15 | header, cf. below | `$FF` |
| 2 | 234 | 15 | `Press left mouse button to continue.` | `$FF` |
| 3 | 142 | 30 | `Guru Meditation #%08lx.%08lx` formatted | `0` |

- **Header** (chosen on `LastAlert[0]`) **[O]**:
  1. byte `bits 16-23 = $01` (general subsystem `AG_NoMemory`, whatever bit 31) →
     `Not enough memory. `
  2. otherwise bit 31 = 0 and high word ≠ 0 → `Recoverable Alert. `
  3. otherwise (dead-end, or null high word = CPU exception) → `Software Failure. `
  (each header ends with **a full stop and a space**).
- **Formatting**: exec's `RawDoFmt` with `%08lx` on `LastAlert[0]` then `LastAlert[1]` → 8 **upper-case**
  hexadecimal digits padded with zeros, separated by a dot, without space:
  `Guru Meditation #8100000F.CAFEBABE`. **[O][S]**
- The **second number** is the long read at the address contained in A5 at `Alert()` time; for a CPU exception
  of a task, **the address of the task** (`ThisTask`); if ExecBase is judged invalid during an exception,
  a long of the exception frame. (cf. `coldstart-hardware-v34.md` §8.1) **[O][S]**
- **Height 40**: frame lines 0-38, last line at the background. Screens shifted by 41 lines. **[O]**
- The labels "Software error - task held", "Disk corrupt - task held", "Finish ALL disk activity",
  "Select CANCEL to reset/debug" do exist in the 1.3 ROM, but in **dos.library**: this is DOS's
  "task held" requester (system requester, not the Guru), which does not belong to exec/alert.hook.
  The 1.3 Guru contains only the three blocks above. **[O]**
- AutoRequest fallback (`intuition-requesters-v34.md` §5.3): another caller of DisplayAlert, with its
  own captions `=LEFT BUTTON OK=` / `=RIGHT BUTTON CANCEL=`. **[O]**

---

## 4. alert.hook (resident pri 5, type UNKNOWN)

- Reminder (`coldstart-hardware-v34.md` §8.4): fixed delay ≈ 1 s, nothing if `LastAlert[0] = $FFFFFFFF`,
  otherwise text §3, DisplayAlert, then reset of `$0` and `LastAlert[0]`. **[O][S]**
- **Why the Guru is red even for "Recoverable Alert"** (point left open): DisplayAlert 1.3
  **has only one palette** (§2.5); the colour depends on no bit of `alertNumber`. Moreover alert.hook and
  exec's immediate display always pass `alertNumber = 0`. The yellow Guru of recoverable alerts
  is a novelty of the 2.x Kickstarts. **[O]** (2.x comparison **[D]**)
- At boot, no screen is open yet (the Workbench opens later): the screen shift has no
  visible effect, the alert occupies the first 40 lines of the display, the rest of the display is at
  background `$111` (no other ViewPort chained). **[D]** Observed (MODE 2 of the probe): Guru at the top, the whole
  rest of the screen very dark grey, wait for the click, then the boot resumes (the bootblock runs). **[S]**
- Useful order for a reimplementation: intuition (pri 10) must be initialised, alert.hook (pri 5) runs
  **before** mathffp, romboot and strap: the Guru of a previous alert is therefore displayed **before** the
  "insert a disk" screen. **[O]** (resident order: `module-map.md`)

---

## 5. Real A500 vs emulator

1. **PAL / NTSC**: the alert is positioned at the top of intuition's View; its height is in non-interlaced
   lines, identical in PAL and NTSC. No dependency on the video standard in DisplayAlert. **[O]**
2. **Blinking**: purely **software**, clocked by the polling loop (26,633 rounds of ≈ 230 cycles
   each: a CIA-A read call synchronised on the E clock, a POTGOR read call). Estimate at
   7.09 MHz (PAL): **≈ 0.87 s per phase** (frame present then absent), hence ≈ 1.75 s per complete cycle;
   7.16 MHz (NTSC): ≈ 0.86 s. Interrupt time (VBlank, CIA) adds to it if interrupts are
   active. Slower on a loaded machine, faster on 68020+ (no time reference).
   **[D]** — measured ≈ 0.92 s per phase under FS-UAE A500 with interrupts active (§2.5) **[S]**.
3. **Right button**: read on POTGOR without programming POTGO. On a real A500, the DATLY pin is only reliable
   if the system has programmed POTGO (input.device/potgo does it at boot). An alert triggered by a
   program that wrote POTGO differently (games) may see the right button always pressed or never. **[D]**
4. **Left button**: CIA-A PRA bit 6, valid if DDRA bit 6 = 0 (input), reset state and normal state
   of the system. **[D]**
5. **Screen**: the `$111` background and the red are rendered as is; the empty line below the alert and the
   separation line of the shifted screens are visible. **[D]**
6. **Immediate display of a recoverable `Alert()` without slow RAM**: blocked under FS-UAE
   (`coldstart-hardware-v34.md` §10.7); see "Open points".

---

## 6. Probes

- `tests/alert_probe.s` + `tests/alert_probe.sh <mode> <chip_ko> <slow_ko> <durée_max>` (variable
  `ALERT_OUT`): author bootblock that calls DisplayAlert directly from a task (interrupts
  active), logs via a VBlank server each toggle of the first word of the raster (blinking
  period in frames) and reports on serial the returned value and DMACONR. Reactive harness: captures
  during the alert, left or right click.
  - MODE 0: 320×200×1 screen opened, DisplayAlert(0, …, 40) + left click, then DisplayAlert($80000000, …,
    60) + right click.
  - MODE 1: height 7000 (impossible raster) in recoverable. MODE 2: same in dead-end.
- Results (PAL A500, 512 KB chip, without slow RAM): width 640; returns 1 (left) / 0 (right);
  frame toggle every 45-48 frames; colours `$111`/`$F20`; screens shifted by 41 lines and
  restored in recoverable, lost in dead-end; impossible height → 0 (recoverable) or reset + Guru
  `#80000000.00000000` (dead-end).

---

## Open points

- **Immediate display of a recoverable `Alert()` on an A500 without slow RAM**: the code leads to the display
  then to the return, but FS-UAE stays blocked (`coldstart-hardware-v34.md` §10.7). DisplayAlert depends on
  `WaitTOF` (VBlank) whereas Alert has turned off the INTENA master without changing `IDNestCnt`; it has not been established
  whether the first internal `Enable()` re-enables it in time on real hardware (real blocking possible) or whether the
  blocking is an emulator artefact. To be settled under cycle-exact WinUAE (`tests/coldhw_probe.sh` MODE 2
  adapted) or on a real machine.
- **intuition's internal lock in dead-end**: the setup does not take it, but the restoration always
  takes it; if the faulting task held it, a dead-end DisplayAlert called directly would block
  after the click. Not probed (without effect for exec, which never passes a dead-end to DisplayAlert).
- **Right button without POTGO programmed** (games that reprogram POTGO then crash): real behaviour
  not measured.
- **Exact duration of the blinking on a real A500**: ≈ 0.87 s per phase computed without interrupts, 0.92 s
  measured under FS-UAE; not timed on a real machine.
- **Band of the screen's colour above the alert** (§2.4): seen under FS-UAE, not verified on
  hardware; depends on the position where MrgCop inserts the alert's copper list.
- **Value returned by `Alert()` when intuition is absent** (caller's A2): read in the code, not
  provoked in a probe.

## Clean-room review

Review of 2026-10-29.

- [x] No 68000 instruction sequence transcribed or paraphrased, no disassembly excerpt,
  no ROM routine address (the only address in `$C0xxxx` is a slow RAM address, the others
  are low RAM addresses `$0`/`$100`/`$104`/`$180` or hardware register addresses).
- [x] The Alert/DisplayAlert paths are described by their **effects** (values written, registers
  returned, visible order, on-screen geometry), cross-checked by probe [S] where marked.
- [x] ROM data reproduced, all **observable on screen or as a return value** (inventoried in
  `docs/audit/specs-review.md`): Guru texts (three headers, "Press left mouse button…",
  format `Guru Meditation #%08lx.%08lx`), x/y positions of the three blocks, palette `$111`/`$F20`,
  frame geometry, blinking counter 26,633.
- [x] The probes cited (`tests/alert_probe.s`, `tests/coldhw_probe.sh`) are author code.
