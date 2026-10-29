# octamed-v34.md — OctaMED Professional v4.00 on the real 1.3: visual reference, OS contract, LoadWB

> ANALYSIS track ("dirty"). Sources:
> - ROM `assets/kick34005.A500` (real KS 1.3, exec 34.2 / graphics 34.1 / intuition 34.3 / dos 34.3)
>   **executed** under FS-UAE (A500, 512K chip + 512K slow) — no reading of its code was
>   needed for this document: everything concerning the ROM is **observed** (screenshots, public
>   structures read back from memory by the FS-UAE debugger afterwards);
> - floppy `OctaMED Professional v4.00 (1992)(RBF Software)[a].adf` (working copy; the original
>   is not modified). Program `OctaMED` (143,668 bytes) and `c/LoadWB` (1,136 bytes): third-party software,
>   unpacked / disassembled to find out **which public functions they call and with which
>   arguments**.
>
> **Legend**: **[O]** observed · **[D]** deduced · **[S]** assumed. This document contains no
> ROM instruction sequence and no ROM routine address; the values cited are
> fields of public structures (NDK 1.3 includes) and API call arguments.

---

## 0. Executive summary

1. On the real 1.3, with the startup reduced to `OctaMED`, the welcome screen is **stable from 120 s to
   160 s** (pixel-identical screenshots), a left click anywhere replaces it with the editor, and
   **all buttons tested respond** (FILES, PLAY, PLAY SONG, STOP). [O] (§1)
2. OctaMED opens **a CUSTOMSCREEN 640 × `-1` × 3 planes, HIRES|SPRITES** then **a single
   BACKDROP|BORDERLESS|ACTIVATE|RMBTRAP|NOCAREREFRESH window** the size of the screen. The real 1.3
   turns the height **-1 into 256** (PAL): Screen.Height = ViewPort.DHeight = BitMap.Rows = 256,
   and the window (whose height OctaMED copies from Screen.Height) is 640 × 256. [O] (§2.1)
3. **The panel buttons (FILES, PLAY, INSTR..., PLAY SONG, STOP...) are NOT Intuition
   gadgets.** The window has only 5 to 7 gadgets in all (2–4 string, 1 boolean, 2 proportional);
   the buttons are detected by OctaMED itself from the IDCMP messages **MOUSEBUTTONS /
   SELECTDOWN ($68)** and the **MouseX / MouseY fields of the IntuiMessage**. [O] (§2.4, §2.5)
4. The "CLICK MOUSE TO CONTINUE" welcome screen also waits for a **MOUSEBUTTONS with Code $68**
   on the window's UserPort. [O] (§2.5)
5. The floppy's `c/LoadWB` is the **LoadWB 38.9 from 2.04**: it asks for `dos.library` **V36** and
   stops as soon as that fails. **The real 1.3 displays exactly "loadwb failed returncode 20"**: this
   message is therefore not a regression of our ROM. [O] (§3)

Most probable causes of the symptoms reported on our ROM (§4): handling of
`NewScreen.Height = -1`, delivery of MOUSEBUTTONS IDCMP (and of window-relative MouseX/MouseY)
to a BACKDROP/BORDERLESS/RMBTRAP window **outside any gadget**, and the `NS_EXTENDED` ($1000) bit
in `NewScreen.Type`.

---

## 1. Reference screenshots (real 1.3) — `docs/analysis/octamed/`

Protocol [O]: copy of the ADF whose `s/startup-sequence` is replaced by the single line `OctaMED`
(xdftool delete + write); cold boot on `kick34005.A500` with the harness `tests/dskchg_run.sh`
(local copy with a `click` command = mousedown/mouseup 1 via xdotool, 120 ms); X screenshots
cropped at +152+100 720×568. Pointer positioned by relative moves from the top-left corner
(1 xdotool step ≈ 1 horizontal hires pixel, ≈ ½ line vertically). Times are counted from the
launch of FS-UAE.

Editor palette (read back from the ColorMap, §2.2): 0 = $000 black (background), 1 = $CCC light grey
(text, light bevels), 2 = $667 dark grey (shadows), 3 = $99A grey-blue (panels), 4 = $F00 red
(edit cursor, track separators), 5 = $F88, 6 = $FAA (pink: track numbers), 7 = $FCC.
Pointer colours (17-19) read back: $00F / $000 / $FE1 (blue / black / yellow), pointer shape
included: they come from the floppy's `devs/system-configuration`, not from OctaMED.

| File | Time / action | What the screenshot shows |
|---|---|---|
| `01_accueil_t120.png` | 124 s (pixel-identical at 166 s) | Welcome screen. At the top, grey-blue ($99A) banner with the title "OctaMED-Professional (v4.00)" drawn, frame "OctaMED Professional (v4.00) / COPYRIGHT © 1992 TEIJO KINNUNEN & RAY BURT-FROST / ILLEGAL DISTRIBUTION... / -CLICK MOUSE TO CONTINUE-" and, on the right, the grid of 15 buttons (FILES MISC ≡ / PLAY VOL ♪ / INSTR MIDI SYNTH / BLOCK TRANS SMPED / EDIT RANGE SLIST). Status line under the panel (empty fields, E SP CHRD, 8-notch bar). Black central area with 4 lines of white topaz 8 text: "OctaMED V4 - now released as freeware! ... commercial version of OctaMED." At the bottom, grey frame of the oscilloscopes/VU meters (2 large graduated rectangles). Pointer at top left. |
| `02_apres_clic.png` | left click in the centre (≈ 320,137 screen), +10 s | Main editor: screen title **"Loading GFX..."** in the title bar (black, white text); PLAY panel (up/down arrows, +/-, INS/DEL, VOL HEX/DEC, FILTER, E1 E2 E3 STS, SPD 033/06, CH.MODE HQ, 4 5 6 7 8, STOP, PLAY SONG, CONT. SONG, PLAY BLOCK, D, CONT. BLOCK, two horizontal sliders); **PLAY button in reverse video**; status line "0001/0001 000/000 ... 01 ... 01/01"; pink track numbers 4 0 1 2 3, red vertical separators; pattern block (lines 000-007, "--- 00000"), current line 000 on a grey band with red cursor; line "Mem 384448/ 206176"; VU frame at the bottom. |
| `03_files.png` | click on FILES (≈ 532,56 screenshot), +6 s | Title "Loading directory...". FILES panel: SAVE FORMAT (MOD1(+INSTR) in reverse, MOD1(NOINST), MOD0(OLD), ST-MODULE), INFO/ICON, LOAD SONG / SAVE SONG / LOAD INSTR / SAVE INSTR, DEL FILE, LOAD/SAVE MSG MAP, fields DIR: "OctaMEDv4:" and FILE: (black). Grey ($99A) central area: "Disk 71 % full (248392 bytes free)", list "ReadMe 8690", "(dir) c", column of volumes/assigns (C: CON: DEVS: DF0: FONTS: L: LIBS: PAR: PRT: RAM: RAW: S: SER:), vertical scrollers. FILES button in reverse. |
| `04_play.png` | click on PLAY, +6 s | Back to the PLAY panel (PLAY in reverse). The screen title bar is no longer visible: the top of the screen shows "TIMER 00:00" + the logo "OctaMED-Professional (v4.00) BY TEIJO KINNUNEN" (window drawing). |
| `05_play_song.png` | click on PLAY SONG (≈ 310,115), +6 s | Playback in progress: PLAY SONG in reverse, TIMER 00:04, the pattern scrolls (current line 036 on the grey band, lines 029-043 visible, track numbers in the pattern). |
| `06_stop.png` | click on STOP (≈ 240,124), +4 s | Playback stopped: TIMER frozen at 00:11, PLAY SONG no longer in reverse, pattern stopped (current line 031). |

Additional measurements [O]: the line "Mem 384448/ 206176" (values not interpreted); the screen title
"Loading GFX..." appears after the welcome click (loading of `OctaMED.gfx*`), then disappears
when the editor redraws the title band.

---

## 2. What OctaMED expects from the OS

### 2.0 Loading

- `OctaMED` is a **self-unpacking** executable: 2 hunks (CODE 652 bytes, DATA 0x22E74 bytes / alloc
  0x3BB38 bytes). The unpacker uses only **AllocMem / FreeMem** (exec) and writes to
  **COLOR17 ($DFF1A2)** during decompression; it builds **43 segments** chained into a seglist
  (BPTR), frees its data hunk then jumps to the first segment. [O] (execution under a
  minimal 68000 emulator with a fake exec)
- The unpacked code is "small data" C (base register on the data segment). [O]
- Classic CLI start-up: FindTask(NULL), pr_CLI, pr_CurrentDir; OpenLibrary("dos.library", 0). [O]

### 2.1 Screen and window [O]

Libraries: `intuition.library` **V33** (failure ⇒ Alert), `graphics.library` V0,
`icon.library` V0 (optional: "No icon.library: no icon."), `dos.library` V0;
later `powerpacker.library`, `audio.device`, `ciax.resource`, `misc.resource`,
`serial.device` (MIDI), `printer.device` on demand.

`OpenScreen(NewScreen)`:

| field | value | note |
|---|---|---|
| LeftEdge, TopEdge | 0, 0 | |
| Width | 640 | |
| **Height** | **-1** ($FFFF) | never modified by the program. **Real 1.3: Screen.Height = 256, ViewPort.DHeight = 256, BitMap.Rows = 256** (PAL machine) [O] |
| Depth | 3 (2 if the "depth" preferences option is set) | |
| DetailPen / BlockPen | 0 / 1 | |
| ViewModes | **$C000 = HIRES \| SPRITES** | read back: ViewPort.Modes = $C000 [O] |
| **Type** | **$100F = CUSTOMSCREEN \| NS_EXTENDED ($1000)** | the real 1.3 accepts and **keeps** the bit: Screen.Flags = $100F [O] |
| Font | TextAttr { "topaz.font", 8, 0, 0 } | |
| DefaultTitle | "OctaMED Professional © 1991-1992 Teijo Kinnunen & Ray Burt-Frost." (string decoded with XOR $CC at start-up) | Screen.Title read back identical [O] |
| Gadgets, CustomBitMap | NULL, NULL | |
| (Extension, V36) | pointer to an `SA_Pens` ($8000003A) tag list | **ignored** by 1.3 [D] |

Result read back on the real 1.3: BarHeight 10, BitMap BytesPerRow 80, Rows 256, Depth 3,
ColorMap Count 32. [O]

Then `OpenFont(topaz 8)` (graphics), `FindTask(NULL)` and `OpenWindow(NewWindow)`:

| field | value |
|---|---|
| Left/Top | 0, 0 |
| Width / Height | 640 / **copied from Screen.Height** just before OpenWindow (hence 256 on the real 1.3) |
| DetailPen / BlockPen | 255 / 255 |
| **IDCMPFlags** | **$478 = MOUSEBUTTONS \| MOUSEMOVE \| GADGETDOWN \| GADGETUP \| RAWKEY** |
| **Flags** | **$31900 = BACKDROP \| BORDERLESS \| ACTIVATE \| RMBTRAP \| NOCAREREFRESH** |
| FirstGadget, CheckMark, Title | NULL |
| Screen | the opened screen; Type = CUSTOMSCREEN |

Read back on the real 1.3: Window 640×256 at (0,0), **Flags $33900** (WINDOWACTIVE added),
IDCMPFlags $478, borders 0/0/0/0, Pointer NULL (default pointer), IntuitionBase.ActiveWindow =
this window, ActiveScreen = this screen. [O]

Next: `pr_WindowPtr := window` (DOS requesters on this screen), RastPort = `window->RPort`,
`ViewPortAddress(window)`, `LoadRGB4(vp, table, 8)`, `SetDrMd(rp, JAM2)`, `SetAPen(rp, 0)`,
`SetBPen(rp, 3)`. [O]

### 2.2 Palette [O]

- `LoadRGB4(vp, 8 colours)` for colours 0-7, occasional `SetRGB4` (blacking out the 8 colours
  before drawing the welcome screen, then sprite colours 21-27), `GetRGB4` (4 sites,
  palette preferences).
- ColorMap read back on the real 1.3:
  - welcome screen: `000 CCC 667 99A 334 556 889 BBC` for 0-7;
  - editor: `000 CCC 667 99A F00 F88 FAA FCC` for 0-7 and `AAA AAA BBB 888 AAA AAA BBB` for
    21-27 (colours of the VU/cursor sprites); 16-20 and 28-31 unchanged
    (`000 00F 000 FE1 444`, `CCC DDD EEE FFF`). [O]

### 2.3 Drawing

- Welcome screen and panels: images loaded from `OctaMED.gfx1..7` into a BitMap
  initialised by `InitBitMap`, copied by **`BltBitMapRastPort(src, 0, 0, rp, 0, 0, 640, 200,
  $C0)`**. If `Screen.Height >= 256`, OctaMED fills the PAL lines with
  `SetAPen(rp, 3)` + `RectFill(rp, 0, 199, 639, 206)` and draws additional elements further
  down: **the layout depends on the actual height obtained for the screen**. [O]
- `ShowTitle(screen, FALSE)` then `SetWindowTitles(window, (char*)-1, title)` (screen title
  only); later the screen title serves as a status line ("Loading GFX...", "Loading
  directory..."). [O]
- Heavily used graphics primitives: Move ×69, Text ×55, SetDrMd ×37, SetAPen ×34, RectFill ×27,
  Draw ×16, SetBPen ×10, WritePixel, PolyDraw, WaitBlit, VBeamPos (beam wait). [O]
- **UCopList** (if the option is active): AllocMem(12, MEMF_PUBLIC|MEMF_CLEAR), then 30 times
  `CWait(ucl, y, 0)` / `CBump` / `CMove(ucl, COLOR22, …)` / `CBump` / `CMove(ucl, COLOR26, …)` /
  `CBump` (y in steps of 2 from a base line), terminated by `CWait(ucl, 10000, 255)` + `CBump`
  (= CEND), then `vp->UCopIns := ucl` and **`RethinkDisplay()`**. Removal: Forbid... `vp->UCopIns :=
  NULL`, RethinkDisplay, `FreeCopList`. Read back on the real 1.3: **UCopIns non-null in the editor
  view, null in the FILES view**. [O]
- **Hardware sprites** via graphics: `GetSprite` (×6), `ChangeSprite` (×10), `MoveSprite` (×11),
  `FreeSprite` (×4) — VU indicators / cursors, in addition to the Intuition pointer. ViewPort.SprIns
  stays NULL (SimpleSprites). [O]
- `SetPointer(window, data, 14, 16, -12, -11)` only if a preference requests it;
  `ClearPointer` otherwise. By default (screenshots): system pointer. [O]
- `CloseWorkBench` / `OpenWorkBench` exist (option), not triggered in the screenshots: the Workbench
  screen (with the "AmigaDOS" CLI window) stays open behind. [O]

### 2.4 Intuition gadgets actually present [O]

Read back from `window->FirstGadget` on the real 1.3 (GadgetType / Flags / Activation in hex):

Editor view (PLAY panel), 5 gadgets:

| ID | type | position, size | Flags | Activation | role |
|---|---|---|---|---|---|
| 320 | STRGADGET ($04) | 178,198 224×8 | 0 (GADGHCOMP) | RELVERIFY | black text field of the "Mem" line |
| 321 | STRGADGET | 406,198 200×8 | 0 | RELVERIFY | text field no. 2 |
| 322 | BOOLGADGET ($01) | 610,198 28×8 | 3 (GADGHNONE) | GADGIMMEDIATE | "NRM" box |
| 775 | PROPGADGET ($03) | 332,19 88×13 | 4 (GADGIMAGE) | RELVERIFY\|GADGIMMEDIATE\|FOLLOWMOUSE ($0B) | right slider of the PLAY panel |
| 777 | PROPGADGET | 106,19 186×13 | 4 | $0B | left slider |

PropInfo: Flags **$001B** (AUTOKNOB | FREEHORIZ | PROPBORDERLESS | bit $10 undefined in 1.3,
kept as is), VPot $FFFF, VBody $FFFF.
Test vectors for the auto knob (GadgetRender Image, recomputed by Intuition):
- 88×13, HPot $294B, HBody $0842 ⇒ Image L/T **13,0**, W/H **6×13**;
- 186×13, HPot $2271, HBody $0112 ⇒ Image L/T **24,0**, W/H **6×13**.
  (minimum knob width 6, position = HPot × (width − knob) / $FFFF, rounded down). [O]

FILES view, 7 gadgets (the PLAY props are removed, `RemoveGList`/`AddGList` on every panel
change):

| ID | type | position, size | Flags | Act | role |
|---|---|---|---|---|---|
| 4126 | PROP | 436,89 16×84 | 4 | $0B | scroller of the file list (PropInfo $001D = AUTOKNOB\|FREEVERT\|PROPBORDERLESS\|$10, VBody $FFFF ⇒ knob 16×84) |
| 4127 | PROP | 620,89 16×84 | 4 | $0B | scroller of the volumes (VBody $EDB5 ⇒ knob **16×78** at 0,0) |
| 320, 321, 322 | same as editor view | | | | |
| 522 | STR | 136,43 320×8 | 0 | RELVERIFY | DIR: field |
| 523 | STR | 136,54 320×8 | 0 | RELVERIFY | FILE: field |

**None of the FILES / PLAY / PLAY SONG / STOP... buttons is a gadget.** [O]

Use of gadget functions (call-site counts): `RefreshGList` ×27, `RemoveGadget` ×22,
`AddGadget` ×18, `ActivateGadget` ×11 (text fields), `AddGList` ×10, `RemoveGList` ×10,
`NewModifyProp` ×3, `ModifyProp` ×2. No menus (no SetMenuStrip). [O]

GadgetID: OctaMED decodes **high byte = group, low byte = number** for GADGETDOWN / GADGETUP
(read from `((struct Gadget*)IAddress)->GadgetID`). [O]

### 2.5 Input: mouse, clicks, keyboard [O]

Main loop: `Wait(UserPort signal | timer/MIDI/serial/... signals)` (with, in "busy"
mode, a `SetSignal(0, 0)` poll), then `GetMsg` in a loop; for each message OctaMED
copies **Class, Code, Qualifier, IAddress, MouseX, MouseY**, then does **ReplyMsg straight away**, and
processes the copy:

- **Class $08 MOUSEBUTTONS**:
  - Code **$68 SELECTDOWN**: hit test against internal tables of rectangles using
    **the message's MouseX / MouseY** (y < 77 ⇒ button panel table, otherwise table of the current
    view) ⇒ button action. **This is the only path by which FILES, PLAY, PLAY SONG, STOP...
    respond.**
  - Code $E8 SELECTUP / $E9 MENUUP: end of drag, `ReportMouse(FALSE, window)` (d0 = 0,
    a0 = window).
  - The right button arrives as MOUSEBUTTONS ($69/$E9) thanks to RMBTRAP (no menus).
- **Class $10 MOUSEMOVE**: drags (enabled by `ReportMouse(TRUE, window)` during a drag,
  5 sites).
- **Class $20 GADGETDOWN / $40 GADGETUP**: gadgets from §2.4, via IAddress→GadgetID.
- **Class $400 RAWKEY**: keyboard (Code bit 7 = release, ignored).
- Class $400000 INTUITICKS: handled if present (not included in $478).
- `ModifyIDCMP(window, 0)` during loads, then `ModifyIDCMP(window, $478)`; also
  `$200000` (VANILLAKEY) and `$400` (RAWKEY) alone during some text entries. [O]

Welcome screen: `WaitPort(UserPort)` / `GetMsg` / `ReplyMsg` until a message with **Class
MOUSEBUTTONS, Code $68**. [O]

Direct hardware reads: only in the **sampling** and playback routines
(`$BFE001` bit 6 = left button, `POTINP $DFF016` bit 10 = right button to interrupt;
INTENA/DMACON/audio registers, CIA). **The user interface never reads the mouse directly.** [O]

Other notable exec uses: `Disable/Enable` ×25, `AddIntServer` (VBlank "OctaMED VBlank"),
software interrupts ("OctaMED SoftInt"), `ciax.resource` (CIA timer), `misc.resource` +
`serial.device` (MIDI), `audio.device` (allocation of the 4 channels), `CopyMem`, `AllocSignal`. [O]

---

## 3. `c/LoadWB` on the OctaMED floppy [O]

- Executable of 1,136 bytes, 2 hunks, string `$VER: loadwb 38.9 (30.3.92)`: **the 2.04 LoadWB**, unrelated
  to the Workbench 1.3.3 one (`loadwb-13.md`).
- Sequence: `OpenLibrary("dos.library", 36)`. **Failure ⇒ `pr_Result2` (ThisTask+$94) := 122
  (ERROR_INVALID_RESIDENT_LIBRARY), return 20**, with no message and no other call.
  Otherwise (2.0+ only): `ReadArgs("-DEBUG/S,DELAY/S,CLEANUP/S,NEWPATH/S")`, failure ⇒
  `PrintFault(IoErr(), …)`; `OpenLibrary("workbench.library", 36)` (failure ⇒ `PrintFault(122)`) [O];
  the rest (CLI path, start-up through workbench.library, `locale.library` /
  `sys/workbench.catalog` catalogue, according to its strings) was not followed [S]. Its strings contain neither
  "workbench.task" nor a "Cannot find resident tag" message: **no contract with the
  1.3 ROM's workbench.task** [D] — and in any case it stops earlier, on dos V36 [O].
- **Real 1.3** (copied ADF, startup = `loadwb` alone, screenshots at 45 s and 75 s identical): the
  "AmigaDOS" CLI window displays
  `Copyright © 1987 Commodore-Amiga, Inc.` / `All rights reserved.` / `Release 1.3` /
  **`loadwb failed returncode 20`** / `1> ` — **no Workbench**. [O]
- Observable contract for our ROM: `OpenLibrary("dos.library", 36)` must fail (lib_Version
  34 < 36); the CLI then displays the standard failure message because 20 ≥ FailAt (10); with the
  original startup (`ppshow c/np` / `loadwb` / `endcli`) the script **aborts** at `loadwb`
  (`endcli` is never executed). Identical behaviour to reproduce, not a bug. [D]
- Note: with the original startup, `ppshow c/np` (PPShow 1.2a) was still displaying its
  "17 BIT SOFTWARE" picture ~20 s after a left click on the real 1.3 (screenshots at 33/64/95 s, click at
  ~125 s, screenshots at 125 and 146 s, all identical); PPShow's exit condition was not determined. [O]

---

## 4. Leads for "the interface loads badly" and "clicks have no effect"

In order of probability [D]:

1. **`NewScreen.Height = -1`**: the real 1.3 makes it **256** (PAL; standard screen height).
   If our OpenScreen takes -1 literally (65535 lines, or NTSC height 200), the window
   (height copied from Screen.Height), the BitMap and OctaMED's `Height >= 256` test diverge ⇒
   wrong layout. Also check `Width` / `Depth` / `ViewModes $C000` / BarHeight 10.
2. **`NewScreen.Type = $100F`**: the $1000 bit (NS_EXTENDED) must be **tolerated** (and kept in
   Screen.Flags); the `Extension` pointer (+32) must not be read by a 1.3 (1.3 NewScreen =
   32 bytes).
3. **MOUSEBUTTONS outside a gadget**: for a click on the active BACKDROP|BORDERLESS|RMBTRAP window
   outside any gadget, Intuition must send an IntuiMessage with **Class $08, Code $68** (release
   $E8; right button $69/$E9 thanks to RMBTRAP), **MouseX/MouseY relative to the window** (here =
   screen coordinates, window at 0,0), any IAddress. Without this: the welcome screen never
   closes, and no panel button responds (they are not gadgets).
4. **Active window**: ACTIVATE must make the window active on opening (WINDOWACTIVE in
   Flags, IntuitionBase.ActiveWindow) — otherwise the MOUSEBUTTONS would go elsewhere.
5. `ModifyIDCMP(window, 0)` then `ModifyIDCMP(window, $478)` (during every load): going to
   0 frees the UserPort, returning to $478 creates a new one (AutoDocs semantics); OctaMED
   re-reads `window->UserPort` on every loop iteration, so the new port must be in place when
   ModifyIDCMP returns [D].
6. Less probable but visible: `BltBitMapRastPort` minterm $C0 from a user BitMap,
   UCopList + `RethinkDisplay`, `ShowTitle(FALSE)`, `SetWindowTitles(w, -1, title)`, auto knobs of the
   PROPBORDERLESS props (vectors in §2.4), GetSprite/ChangeSprite/MoveSprite sprites.

---

## 5. Reproduction (analysis track)

- Unpacking of `OctaMED`: minimal 68000 emulator (unicorn) loading the hunks and simulating
  AllocMem/FreeMem, up to the jump into the first unpacked segment; scan of the `JSR -LVO(A6)`
  grouped by library base variable, named after amitools' public `.fd` files. This
  work and the dumps were kept outside the repository.
- Reading back public structures on the real 1.3: FS-UAE console debugger (`m adresse n`),
  walk ExecBase→LibList→IntuitionBase→FirstScreen→FirstWindow→FirstGadget.
- Ports: only one FS-UAE at a time; ADF renamed for each session.

## 6. Open points

- PPShow exit condition (click, key or timeout?) not determined.
- The `StringInfo` fields of the text gadgets and the exact contents of the UCopList were not read back.
- The meaning of "Mem 384448/ 206176" was not checked against AvailMem.

## Clean-room review

Review of 2026-10-29.

- [x] Disassembled targets = third-party software (`OctaMED`, `c/LoadWB` 2.04); the Kickstart ROM was
  only **executed** (screenshots, public structures read back from memory). No ROM routine address,
  no ROM instruction sequence.
- [x] Data coming from the ROM: only **values observed at run time** (fields of
  public structures, ColorMap read back, screen height 256, window flags) and the initial CLI banner
  (`Copyright © 1987 Commodore-Amiga, Inc.` / `All rights reserved.` / `Release 1.3`), displayed and
  observable text (inventoried in `docs/audit/specs-review.md`). No table, glyph or image
  from the ROM.
- [x] The screenshots in `docs/analysis/octamed/` show OctaMED's screen (third-party software) on the real
  ROM; they contain no image taken from the ROM apart from the pointer/colours coming from the
  floppy's `system-configuration`.
