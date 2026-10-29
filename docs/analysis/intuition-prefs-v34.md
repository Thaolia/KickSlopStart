# intuition-prefs-v34.md — Preferences: SetPrefs / GetPrefs / GetDefPrefs, system-configuration

> ANALYSIS track ("dirty"). Sources: ROM `assets/kick34005.A500` (intuition 34.3, dos V34 BCPL),
> file `devs/system-configuration` from `assets/wb133.adf`. Functions covered: SetPrefs (−324),
> GetPrefs (−132), GetDefPrefs (−126), default prefs table (232 bytes), default pointer
> image (36 words, not reproduced), TextAttr topaz 8/9, POINTERPOS conversion and PointerTicks
> accumulator, mouse clamping, NEWPREFS broadcast, intuition init, reading of
> `devs:system-configuration` by `cliinit` (dos global 133). No ROM address (removed on
> 2026-10-29).
>
> **Legend**: **[O]** observed · **[D]** deduced · **[S]** assumed. Behaviour and layouts
> only, no instruction sequence copied, no bitmap.

---

## 1. Internal storage [O]

- IntuitionBase (IB) +$364 = pointer to **the current copy of the Preferences**, a block of
  **232 bytes** allocated at library init by AllocMem(232, MEMF_CLEAR). All the rest
  of intuition reads the prefs **through this pointer** (never a frozen copy).
- Derived fields kept separately in IB (written by the application step §3.3):

| IB | Contents | Source |
|---|---|---|
| +$2E / +$30 | View.DyOffset / View.DxOffset (ViewLord at +$22) | ViewInitY/X + ViewY/XOffset |
| +$334 / +$335 | XOffset / YOffset of the default pointer (init: $FF/$FF) | prefs +$64/+$65 |
| +$336 / +$33A | DoubleClick seconds / microseconds (read by DoubleClick()) | prefs +$14/+$18 |
| +$34E…+$354 | colours 0–3 | prefs +$6E…+$74 |
| +$356…+$35A | colours 17–19 | prefs +$66…+$6A |
| +$35C (8 bytes) | default TextAttr (name, YSize, Style at +$362, Flags) | FontHeight |
| +$36C / +$36E | DxOffset / DyOffset returned by InitView at init | (fixed after init) |
| +$542 / +$544 | 2 × NormalDisplayRows, and that value − 1 | GfxBase +$D8 |
| +$546 | NormalDisplayColumns (width of the WB screen) | GfxBase +$DA |
| +$37E (40 bytes) | copy of the input.device IORequest used for SETTHRESH/SETPERIOD | IB +$182 |

- Library init [O]: colours IB+$34E… pre-filled ($05A, $FFF, $002, $F80; $D22, 0,
  $FCA), InitView(IB+$22), DxOffset/DyOffset stored at IB+$36C/$36E, allocation of the prefs
  block, then **GetDefPrefs(block, 232)** and **SetPrefs(block, 232, FALSE)**. At this point no
  screen exists and input.device is not open: only the internal data is set.
- First OpenLibrary (OpenCnt = 0) [O]: re-applies the prefs (§3.3, without copy), then
  **IB+$40 (Flags) := $1000** — which clears bit 16 ("rows/columns already adjusted", §3.3)
  — then opens timer.device and input.device (IORequest at IB+$182) and installs the input
  handler (IND_ADDHANDLER, priority 50). So the **first SetPrefs after opening**
  (the one from system-configuration) can still adjust rows/columns, and it is the first one able
  to pass KeyRpt on to input.device.

## 2. Loading `devs:system-configuration` (dos, initial CLI) [O]

### 2.1 Who, when

- Code in the BCPL section of **`cliinit` (global 133)**, **local** routine (called by
  address relative to the routine's base, not through the global vector — hence the absence of an
  absolute reference).
- Order observed in `cliinit`: loop over units DF0–DF3 (mounting) → **reading of
  system-configuration** → registration of the names "CLI", "Restart", "FileHandler" → opening
  of the window **`CON:0/0/640/200/AmigaDOS`** → banner "Copyright … Release 1.3" → rest
  (startup-sequence).
- Consequence [D]: the disk's prefs are in place **before** the CON: window opens
  the Workbench screen (OpenWorkBench). Font (FontHeight), colours, LaceWB and rows/columns
  therefore apply from the first screen.
- The name is `"devs:system-configuration"` (BSTR); the DEVS: assign must therefore already exist
  (set earlier in the same init, cf. `dos-boot-sequence.md` phase B) [D].

### 2.2 What is read

1. `findinput` (global 59) on the name; null stream (file absent) ⇒ **nothing**, no SetPrefs,
   no message.
2. Read of **232 bytes** into a local buffer. Result ≠ 232 (short file or error)
   ⇒ close, **no SetPrefs**: the prefs keep the ROM values.
3. Byte +$E7 (`ext_size`, in blocks of 64 bytes):
   - 0 ⇒ **SetPrefs(buffer, 232, TRUE)** (`calllib` call, global 103, on IntuitionBase read
     from global 92, LVO −324, A0 = buffer, D0 = 232, D1 = 1);
   - n > 0 ⇒ allocation of a buffer of 232 + 64·n bytes (getvec), copy of the 232, read of
     64·n additional bytes:
     - 0 bytes read ⇒ SetPrefs(original buffer, 232, TRUE);
     - exactly 64·n ⇒ SetPrefs(large buffer, 232 + 64·n, TRUE) (intuition 34 clamps to 232,
       the extension is ignored);
     - other ⇒ nothing;
     - then release (freevec).
4. `endstream` (global 93).

- `inform = TRUE`: NEWPREFS will be broadcast (§3.4); at boot no window listens for it [D].

### 2.3 Contents of the WB 1.3 file (232 bytes, ext_size 0) [O]

| Field | WB 1.3 file | ROM default (§4) |
|---|---|---|
| FontHeight | 8 | **9** |
| KeyRptSpeed | 0 s, 31,140 µs | 0 s, 100,000 µs |
| KeyRptDelay | 0 s, 400,000 µs | 0 s, 800,000 µs |
| DoubleClick | 1 s, 196,800 µs | 1 s, 500,000 µs |
| XOffset / YOffset | −2 / −1 | −2 / −1 |
| colours 17/18/19 | $D22 / $000 / **$ABC** | $D22 / $000 / $FCA |
| **PointerTicks** | **1** | **2** |
| colours 0–3 | $05A, $FFF, $002, $F80 | same |
| ViewInitX / ViewInitY | 129 / 44 (ignored, §3.1) | 0 / 0 |
| LaceWB, RowSizeChange, ColumnSizeChange, wb_* | 0 | 0 |

- **Explanation of the coordinator's symptom** [D]: without reading the file, the real ROM
  would also show **PointerTicks = 2** (displayed "2" by Preferences) and the
  KeyRepeat knobs at the ROM values (0.8 s / 0.1 s) instead of 0.4 s / 0.031 s. It requires (a) loading the
  file as in §2.2, (b) a GetPrefs that returns the current copy, (c) a complete SetPrefs.

## 3. SetPrefs(prefs A0, size D0, inform D1) — LVO −324 [O]

Return: D0 = `prefs` (the pointer passed), in all cases. `inform` = low word of D1.

### 3.1 Bounded copy (common to the three functions)

- `size` is **signed**: ≤ 0 ⇒ no copy; > 232 ⇒ reduced to 232. Byte-by-byte copy of the first
  `size` bytes (layout §5) from source to destination.
- If `size` ≥ 124 ($7C): in the **destination**, ViewInitX (+$78) and ViewInitY (+$7A) are
  **overwritten** with IB+$36C / IB+$36E (InitView offsets). The values provided by the caller
  (129/44 in the WB file) therefore have no effect.
- For SetPrefs: source = `prefs`, destination = block IB+$364.

### 3.2 After the copy

1. `ext_size` (+$E7) of the internal copy **forced to 0**.
2. Complete application (§3.3) — **even if size ≤ 0** (nothing copied, everything re-applied).
3. If `inform` ≠ 0: posting of a deferred "new prefs" event (§3.4).

### 3.3 Application (common routine, also called at the first OpenLibrary)

Effects, in the observed order (p = internal copy):

1. **DoubleClick**: IB+$336/$33A := p.DoubleClick (seconds, microseconds).
2. **Default font**: TextAttr IB+$35C := **topaz.font 8** if p.FontHeight = 8, **topaz.font
   9 in all other cases** (Style 0, Flags 0). OpenFont(IB+$35C) → **GfxBase.DefaultFont**
   (+$9A). No CloseFont of the old font (the open count grows with each
   SetPrefs) [O].
3. **Rows / columns**, only if bit 16 of IB+$40 is 0 (then it is set to 1):
   - if wb_Height (+$E4) = 0: GfxBase.NormalDisplayRows (+$D8) += RowSizeChange (signed);
   - IB+$542 := 2 × NormalDisplayRows; IB+$544 := IB+$542 − 1;
   - if wb_Width (+$E2) = 0: GfxBase.NormalDisplayColumns (+$DA) += ColumnSizeChange (signed);
   - IB+$546 := NormalDisplayColumns (width given to the WB screen).
   - The bit is set by the init, cleared by the first OpenLibrary ⇒ in practice **a single**
     adjustment, the one from system-configuration; later SetPrefs calls (Preferences) no longer
     touch it [D].
4. **Workbench screen** (first screen in the list whose Type & $F = WBENCHSCREEN), if it exists:
   Screen.Font (+$28) := &IB+$35C; SetFont(&Screen.RastPort, DefaultFont);
   SetSoftStyle(&Screen.RastPort, style of IB+$35C, $FF); SetFont(rastport of the title bar
   layer, DefaultFont).
5. **Display offset**: View.DxOffset := IB+$36C + ViewXOffset (signed byte +$76);
   View.DyOffset := IB+$36E + ViewYOffset (+$77).
6. **Colours**: IB+$34E…$354 := color0..3; IB+$356…$35A := color17..19. If the WB screen exists:
   SetRGB4(&Screen.ViewPort, i, c>>8, c>>4, c) for i = 0..3 then 17..19 (SetRGB4 masks to 4 bits).
   The colours go **only** to the WB screen; OpenWorkBench redoes this loading after
   opening.
7. **Pointer offsets**: IB+$334/$335 := XOffset/YOffset; if the active pointer (IB+$70)
   is the default pointer (IB+$32E), its current offsets IB+$76/$77 are updated too.
8. **Pointer image**: the 36 words of PointerMatrix (+$1C, sprite control words
   included) are copied into the sprite buffer of the default pointer (*IB+$32E).
9. **RemakeDisplay()** (LVO −384).
10. **Mouse clamping and pointer repositioning**: MouseX clamped to
    [IB+$50, IB+$52], MouseY to [IB+$54, IB+$56], then update of sprites/screens [D].
11. **Key repeat**, only if input.device is open (io_Device of IB+$182 ≠ 0):
    copy of the 40 bytes of the IORequest to IB+$37E, then two **synchronous DoIO**s:
    - io_Command = **12 (IND_SETTHRESH)**, timeval (+$20 seconds, +$24 µs) = **KeyRptDelay**;
    - io_Command = **13 (IND_SETPERIOD)**, timeval = **KeyRptSpeed**.

Fields **not** applied by SetPrefs: PointerTicks (read on the fly, §6), LaceWB (read by
OpenWorkBench: bit 0 ⇒ ViewModes |= LACE), EnableCLI, printer, serial, WorkName,
wb_Depth. In intuition's code, the only other direct reads of the copy are
PointerTicks, FontHeight (computation of a height with fallback on FontHeight + 6) and LaceWB
[O]. The printer/serial fields are intended for the devices via GetPrefs [S].

### 3.4 `inform` and NEWPREFS

- SetPrefs posts a **code 4** node, null arguments, into IB's deferred queue (+$368).
- The queue is emptied by intuition's input processing (at the next input event,
  hence with a latency of at most one tick) [D].
- Code 4 ⇒ for **all screens** (list IB+$3C) and **all their windows** whose IDCMPFlags
  contains **NEWPREFS ($4000)**: sending of a NEWPREFS IDCMP message (code 0).
- `inform = FALSE` ⇒ no notification.

## 4. GetPrefs / GetDefPrefs and default values

### 4.1 GetPrefs(buf A0, size D0) — LVO −132 [O]

- Bounded copy §3.1 of the **current copy** (IB+$364) to `buf` (ViewInitX/Y copied from
  IB if size ≥ 124). Return D0 = `buf`. PointerMatrix = that of the current copy (default
  image as long as nobody has changed it, since the init goes through GetDefPrefs).

### 4.2 GetDefPrefs(buf A0, size D0) — LVO −126 [O]

- Bounded copy §3.1 from the **ROM default table** (§4.3, not from the current copy), ViewInitX/Y
  from IB if size ≥ 124.
- Then, if size ≥ 100: PointerMatrix (36 words, +$1C) := **ROM default image, 36 words**.
  The default table has its PointerMatrix at zero: it is this filling that provides it.
- Return D0 = `buf`. No side effect (nothing is applied).
- Difference from GetPrefs: ROM source instead of the current copy, and forced pointer image.

### 4.3 Table of default values (ROM) [O]

| Off. | Field | Default |
|---|---|---|
| $00 | FontHeight | 9 |
| $01 | PrinterPort | 0 (PARALLEL) |
| $02 | BaudRate | 5 (9600) |
| $04 | KeyRptSpeed | 0 s, 100,000 µs |
| $0C | KeyRptDelay | 0 s, 800,000 µs |
| $14 | DoubleClick | 1 s, 500,000 µs |
| $1C | PointerMatrix | (zeros in the table; 36-word default image via GetDefPrefs) |
| $64 / $65 | XOffset / YOffset | −2 / −1 |
| $66 / $68 / $6A | color17 / 18 / 19 | $D22 / $000 / $FCA |
| $6C | PointerTicks | 2 |
| $6E…$74 | color0..3 | $05A, $FFF, $002, $F80 |
| $76 / $77 | ViewXOffset / ViewYOffset | 0 / 0 |
| $78 / $7A | ViewInitX / ViewInitY | 0 / 0 (replaced by IB+$36C/$36E on copy) |
| $7C | EnableCLI | 0 |
| $7E | PrinterType | 7 |
| $80 | PrinterFilename[30] | "generic" |
| $9E | PrintPitch | 0 |
| $A0 | PrintQuality | 0 |
| $A2 | PrintSpacing | 0 |
| $A4 | PrintLeftMargin | 5 |
| $A6 | PrintRightMargin | 75 |
| $A8 | PrintImage | 0 |
| $AA | PrintAspect | 0 |
| $AC | PrintShade | 1 |
| $AE | PrintThreshold | 2 |
| $B0 | PaperSize | $20 |
| $B2 | PaperLength | 66 |
| $B4 | PaperType | 0 |
| $B6 / $B7 / $B8 | SerRWBits / SerStopBuf / SerParShk | 0 / 0 / 0 |
| $B9 | LaceWB | 0 |
| $BA | WorkName[30] | empty |
| $D8 / $D9 | RowSizeChange / ColumnSizeChange | 0 / 0 |
| $DA | PrintFlags | 0 |
| $DC / $DE | PrintMaxWidth / PrintMaxHeight | 0 / 0 |
| $E0 / $E1 | PrintDensity / PrintXOffset | 0 / 0 |
| $E2 / $E4 / $E6 | wb_Width / wb_Height / wb_Depth | 0 / 0 / 0 |
| $E7 | ext_size | 0 |

## 5. Layout of `struct Preferences` 1.3 (232 bytes)

That of table §4.3 [O for the offsets used by the code: $00, $04, $0C, $14, $1C, $64–$77,
$78/$7A, $B9, $D8/$D9, $E2/$E4, $E7; the rest follows the public 1.3 `preferences.h`, consistent with the
observed values].

## 6. PointerTicks and mouse movements [O]

In intuition's processing of input events:

- **IECLASS_POINTERPOS (4)** (absolute position): converted to relative movement —
  ie_X := (ie_X − MouseX) × PointerTicks, ie_Y := (ie_Y − MouseY) × PointerTicks, qualifier
  RELATIVEMOUSE ($8000) set, class changed to RAWMOUSE (2). Then processed as below.
- **IECLASS_RAWMOUSE (2)** relative: for each axis, with a per-axis remainder accumulator
  (IB+$37A for X, IB+$37C for Y) and t = PointerTicks, s = t >> 1 (arithmetic):
  - zero delta ⇒ nothing;
  - remainder += delta & (2^s − 1); delta := delta >> s (arithmetic, rounded towards −∞);
    mouse position (MouseX/MouseY) += delta;
  - if remainder ≥ t: position += 1, delta += 1, remainder −= t.
  - The event's delta is rewritten with the effective value (used afterwards for
    moving screens/gadgets).
  - Then clamping + pointer repositioning (§3.3 point 10).
- Result: t = 1 ⇒ native speed (1 pixel per count), t = 2 ⇒ half, t = 4 ⇒ quarter.
  For t = 3 the divisor is 2 (s = 1) but the carry threshold is 3: the formula is only consistent
  for 1, 2, 4 (values offered by Preferences) [D].
- PointerTicks is re-read from the current copy at **every** event: a SetPrefs takes effect
  immediately, without specific application.

## 7. Test vectors

1. Without `devs:system-configuration`: GetPrefs(buf, 232) ⇒ PointerTicks = 2, FontHeight = 9,
   KeyRptDelay = 0.8 s, KeyRptSpeed = 0.1 s, color19 = $FCA; WB in topaz 9.
2. With the WB 1.3 file: GetPrefs ⇒ PointerTicks = 1, FontHeight = 8, KeyRptDelay = 0.4 s,
   KeyRptSpeed = 31,140 µs, DoubleClick = 1.1968 s, color19 = $ABC; ViewInitX/Y = InitView
   offsets (not 129/44).
3. 100-byte file: no SetPrefs (read ≠ 232).
4. SetPrefs(p, 0, FALSE): nothing copied, but font/colours/RemakeDisplay/KeyRpt re-applied.
5. SetPrefs(p, 120, TRUE): bytes 0–119 copied; internal ViewInitX/Y (bytes 120–123) neither
   copied nor rewritten; NEWPREFS received by a window opened with IDCMP NEWPREFS, not by the
   others.
6. GetDefPrefs(buf, 100): buf[0..99] = ROM table, PointerMatrix = default image; the current
   copy is not modified.
7. PointerTicks = 2, two RAWMOUSE events dx = +1: the mouse moves by 0 then by 1.
8. SetPrefs with FontHeight = 7 ⇒ topaz 9 font (anything that is not 8).

---

## Clean-room review

- [x] No instruction sequence copied: effects described on public fields (Preferences,
  IntuitionBase, GfxBase, Screen, IORequest), with formulas and application order.
- [x] No bitmap: the default pointer image is only mentioned (size, 36 words).
- [x] Default values = configuration data (constants), presented as a table.
- [x] IB's internal offsets are analysis landmarks; the implementation is free to use its
  own storage as long as the observable behaviour (§3, §4, §6) is respected.
- [x] **Correction of 2026-10-29**: removed the header "Landmarks" block (37 ROM addresses: vectors
  and bodies of SetPrefs/GetPrefs/GetDefPrefs, default table, pointer image, TextAttr, mouse/NEWPREFS/init
  routines, dos `cliinit` section) and the addresses cited in the body (§3.3, §4);
  replaced by the list of covered functions. Behaviour and table §4.3 unchanged.
