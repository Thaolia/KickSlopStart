# preferences-13.md — SYS:Prefs/Preferences (wb133.adf): file format and start-up

> ANALYSIS track ("dirty"). Source: `Prefs/Preferences` from `assets/wb133.adf` (56,180
> bytes, 03-10-1990), extracted into the analysis track's scratch area, inspected with `hunktool` and a
> hunk parser, then relocated flat for reading. Public rules and structures
> only, no instruction sequence copied.
>
> **Legend**: **[O]** observed · **[D]** deduced · **[S]** assumed.

---

## 1. File structure [O]

- **HUNK_HEADER**: no resident library, **table of 52 hunks**, first = 0, last = 51.
  **No memory bits** in the sizes (bits 30–31 at 0 everywhere): allocation in any
  public memory.
- **Blocks present**, exclusively:
  - HUNK_CODE ($3E9) × **30**;
  - HUNK_DATA ($3EA) × **22**;
  - HUNK_RELOC32 ($3EC) × 32;
  - HUNK_END ($3F2) × 52.
- **Absent**: HUNK_BSS, RELOC16/8, DREL32, RELOC32SHORT ($3FC), HUNK_SYMBOL, HUNK_DEBUG,
  **HUNK_OVERLAY ($3F5), HUNK_BREAK ($3F6)**. This is **not** an overlay executable. The only
  word $000003F6 in the file is data inside a relocation table.
- **13 hunks of size 0**: nos. **7, 9, 13, 25, 27, 31, 36, 37, 40, 42, 44, 45, 51**. They are
  CODE or DATA of 0 longwords, but they are indeed present in the table and in the file (block
  of length 0 followed by HUNK_END).
- **Relocations**:
  - all RELOC32;
  - many targets are **forward**: hunk 0 targets hunks 1, 10 and 46; hunk 2
    targets 3, 4, 8, 47 and 48...;
  - highest target: hunk 50;
  - **no relocation targets a hunk of size 0**;
  - hunk 3 (DATA, 6,580 bytes) contains 159 pointers to itself (tables of structures).

Sizes in bytes, from #0 to #51:
524, 428, 1176, 6580, 4080, 116, 2700, **0**, 828, **0**, 6456, 992, 936, **0**, 1080, 92,
244, 132, 3032, 308, 1492, 2116, 3736, 140, 472, **0**, 24, **0**, 1528, 160, 208, **0**,
3292, 284, 320, 28, **0**, **0**, 20, 220, **0**, 36, **0**, 116, **0**, **0**, 320, 592, 368,
88, 484, **0**.

Roles:
- #0: start-up code;
- #1: its variables;
- **#10: `main`**;
- **#46 to #50: library call vectors** (one small stub per function: loads the
  base from a global, then JSR −LVO).

## 2. Start-up code (hunk 0) [O]

It is a classic "old-style" C start-up, of the `AStartup` kind: absolute variables, **no
A4 base register**, no overlay.

**Entry**: the start-up saves **SP, D0 (length of the command line) and A0 (its
address)**. It reads **SysBase at $4**, then does **FindTask(NULL)** (exec −294). No other
register is read (neither D1, nor A1–A6, nor A4).

**Launch from the Workbench** (`pr_CLI` (+$AC) = 0):
1. **OpenLibrary("dos.library", 0)** (exec −552). On failure: Alert $00038007 (AG_OpenLib |
   AO_DOSLib), then return 100.
2. **WaitPort(&pr_MsgPort)** (exec −384), then **GetMsg** (exec −372): the WBStartup is stored
   in a global.
3. If `sm_ArgList` (+$24) ≠ 0: **CurrentDir(ArgList[0].wa_Lock)** (dos −126).
4. If **`sm_ToolWindow` (+$20) ≠ 0**: **Open(ToolWindow, MODE_OLDFILE)** (dos −30), then
   `pr_ConsoleTask` (+$A4) := `fh_Type` (+$08) of the FileHandle. This handle also serves as standard input and
   output.
5. **`main(0, WBStartup)`**: jump to the start of hunk 10.
6. On return:
   - CloseLibrary(dos);
   - **Forbid** (exec −132) then **ReplyMsg(WBStartup)** (exec −378);
   - SP restored and return with D0.

**Launch from the CLI**:
1. OpenLibrary("dos");
2. `argv[0]` = `cli_CommandName` (+$10, BSTR);
3. splitting of the D0/A0 line into argv: quotes, and `*N` / `*E` handled;
4. **Input() (dos −54)** and **Output() (dos −60)**;
5. main(argc, argv).

**Start of `main` in Workbench mode**:
1. **OpenLibrary("icon.library", 0)**, through the exec −552 stub;
2. `ArgList[1]` is taken if `sm_NumArgs` > 1 (project), otherwise `ArgList[0]`;
3. **CurrentDir(wa_Lock)**;
4. **GetDiskObject(wa_Name)** (icon −78);
5. **FindToolType(do_ToolTypes (+$36), "PREFS")** (icon −96);
6. **MatchToolValue** (icon −102) with `"pointer"`, `"printer"` and `"serial"`;
7. FreeDiskObject (icon −90);
8. CurrentDir(old);
9. CloseLibrary(icon).

The opening of the screen and windows comes next (intuition and graphics, not detailed here).

## 3. Hypotheses about the jump into data [S, ranked]

Symptom: illegal instruction. The PC points to a **data longword that contains an
address** (the word $00C2 is not a valid opcode). So there was **a jump to a wrongly computed or wrongly
relocated address**, or **a return on a corrupted stack**. No overlay is
involved (§1).

1. **Size-0 hunks mishandled by our LoadSeg** — the most probable hypothesis.
   - The real LoadSeg creates a segment for **each** of the 52 hunks: the size plus the link, i.e.
     at least 8 bytes for an empty hunk, chained into the seglist. **Hunk numbering
     stays that of the table.**
   - If our loader skips size-0 hunks, merges them or gives them no address,
     **all relocations to the following hunks are shifted**: by up to 13 positions for the
     last ones. The JSRs to the stubs in hunks 46–50 then land in other hunks,
     often DATA ones.
   - Same effect if `main` (hunk 10, right after the empty hunk 9) is wrongly addressed: the start-up
     JSR lands in the next or previous hunk.
2. **Forward relocations**: hunk 0 already targets hunks 10 and 46. The real LoadSeg
   **allocates all hunks when reading HUNK_HEADER**, before any relocation. A loader that
   allocates as it goes and relocates with a base still unknown (0 or garbage) would produce
   exactly this kind of jump.
3. **Fixed-size hunk table**: 52 entries, targets up to 50. An internal limit (32,
   48...) would overflow.
4. Less probable: a return from `main` or from a stub on a corrupted stack (usp contains a
   plausible code address), or a wrong library base read by a stub (a6 = $C021DE
   is odd: that is a clue if a6 was supposed to be a library base). See the method
   below.

**Confirmation method [D]**:
1. Display the seglist created by our LoadSeg: for each segment, address = BADDR(link) + 4
   and size. Check that there are **52 segments** and that the 13 empty hunks exist.
2. Locate **pc = $C2AB30** and **(usp) = $C2D1D2** in this seglist, as (hunk no.,
   offset), then compare with the table of sizes above.
   - If (usp) falls in a **CODE** hunk right after an absolute JSR, the target of that JSR, taken
     from the file, tells which hunk was targeted. The numbering shift then becomes visible.
   - If pc falls in a DATA hunk neighbouring the targeted hunk, hypothesis 1 or 2 is confirmed.

---

## 4. From main to display: calls and silent exits (Workbench launch) [O unless stated]

Continuation of the icon.library part (§2). "Exit" means the return to the start-up code, which closes dos,
does ReplyMsg of the WBStartup and returns with D0.

| # | Call (library, LVO) | Exit condition | Visible? |
|---|---|---|---|
| 1 | exec **FindPort("preferences_inuse.task")** (−390) | **port found ⇒ exit with code 0**, safeguard against a second instance | **silent** |
| 2 | creation of the public port `"preferences_inuse.task"`: AllocSignal, AllocMem, AddPort (exec −330/−198/−354) | failure ⇒ exit 0 | silent |
| 3 | exec **OpenLibrary("graphics.library", 0)** | failure ⇒ **DisplayAlert in a loop** (no exit) | alert |
| 4 | exec **OpenLibrary("intuition.library", 0)** | same | alert |
| 5 | intuition **AllocRemember**(... , size, **MEMF_CHIP**) × 6: copy of the image data into CHIP | a failure ⇒ DisplayAlert, FreeRemember, CloseLibrary × 2, exit | alert |
| 6 | exec **AllocMem(5984, MEMF_PUBLIC\|CLEAR)**: 136 gadgets of 44 bytes | failure ⇒ DisplayAlert, exit | alert |
| 7 | exec InitSemaphore / AddTail (two private SignalSemaphores) | — | — |
| 8 | intuition **GetPrefs(buffer, 232)** (−132); two backup copies of 232 bytes | none (return not tested) | — |
| 9 | dos **DateStamp** (−192) | — | — |
| 10 | intuition **ViewAddress** (−294), then possibly **RemakeDisplay** (−384) to recentre the display according to the View/Preferences fields of the next row | — | — |
| 11 | intuition **OpenWindow** of a **1×1** window: Left 0, Top 0, Flags $00021006 (DRAG, DEPTH, ACTIVATE, NOCAREREFRESH), IDCMP 0, MaxW 640, MaxH 200, Type WBENCHSCREEN, Title = internal pointer | failure ⇒ DisplayAlert, FreeMem, CloseLibrary, exit | alert |
| 12 | **MoveScreen(win->WScreen, −Screen.LeftEdge, −Screen.TopEdge)** (−162): brings the WB screen back to (0,0); then **CloseWindow** (−72) of the 1×1 window | — | — |
| 13 | intuition **OpenWindow** of the real window: **640×200** at (0,0), **IDCMP $70** (MOUSEMOVE, GADGETDOWN, GADGETUP), FirstGadget = the mode's gadget set, same Flags | failure ⇒ DisplayAlert, return 0 ⇒ Prefs restored then exit | alert |
| 14 | graphics **OpenFont({"topaz.font", 9, 0, FPF_ROMFONT})** (−72) | see row 15 | — |
| 15 | graphics **SetFont(win->RPort, font)** (−66); **D0 is tested on return** | **D0 = 0 ⇒ CloseFont, CloseWindow, DisplayAlert, return 0 ⇒ exit** | alert |
| 16 | drawing of the mode's screen (graphics), ObtainSemaphore / ReleaseSemaphore (exec −564/−570) | — | — |
| 17 | intuition **RefreshGadgets**(gadgets, window, NULL) (−222) | — | — |
| 18 | loop: exec **Wait(1 << UserPort->mp_SigBit)** (−318), **GetMsg** (−372), ReplyMsg; pending MOUSEMOVEs are drained | — | — |

**Pitfalls for a reimplemented ROM**:
- **Row 15 (SetFont)**: the real 1.3 SetFont **does not touch D0**. D0 therefore still holds the
  value from the preceding OpenFont, the font pointer, which the program's stub has not
  overwritten. The program sees "success" in it.
  - A SetFont that **sets D0 to 0** makes the program exit.
  - Likewise, an OpenFont that returns NULL: the program passes it as is to SetFont.
- **Row 14 (OpenFont)**: the real 1.3 OpenFont **does not require the exact size**. It
  walks the fonts with the same name (`GfxBase->TextFonts`) and returns the **best
  match**:
  - starting score $7FFF;
  - penalty of **256 per line too many** and **64 per line too few**;
  - additional penalties for style and flag differences;
  - kept if the score is > 0.
  A request for topaz 9 therefore returns topaz 8 if topaz 9 does not exist. The real ROM contains topaz 8
  **and** 9. An OpenFont requiring the exact size returns NULL, which leads to row 15.
- **DisplayAlert**: all the "alert" exits above become **silent** if our
  DisplayAlert does nothing. The calls are `DisplayAlert(RECOVERY_ALERT (0), text, 60)`.
- **Row 1**: the port `"preferences_inuse.task"` is only removed on normal exit. After a
  **crash** of Preferences (as with the old LoadSeg), it remains in the list of public
  ports, and **any new run exits immediately, silently, with code 0**. One must
  reboot, or check FindPort, before drawing conclusions.

**Fields read directly**:
- `Window`: WScreen (+$2E), RPort (+$32), UserPort (+$56) → mp_SigBit (+$0F);
- `Screen`: LeftEdge (+$08), TopEdge (+$0A);
- `View` (from ViewAddress): DyOffset (+$0C), DxOffset (+$0E);
- `IntuiMessage`: Class (+$14), compared with MOUSEMOVE;
- `Preferences` (232-byte buffer): ViewXOffset/ViewYOffset (+$76/+$77), ViewInitX/Y
  (+$78/+$7A), +$7C (only the 2 most significant bits are kept) and the fields +$A4, +$A6, +$B2.
- **No private field of IntuitionBase or GfxBase** is read in this sequence [O, by
  absence].

**Recommended order of checks [D]**:
1. FindPort("preferences_inuse.task") after reboot;
2. return of SetFont (D0 preserved) and OpenFont(topaz 9);
3. DisplayAlert visible;
4. OpenWindow 640×200 on the WB screen (height ≥ 200).

## 5. Main window: the screen-centring frame and its small square [O unless stated]

Landmarks (image relocated at $100000, contiguous hunks aligned on 8): gadget constructor
$104A4C, field arrays $103278... (one word per gadget and per field), PropInfo $1039E8 (22 bytes
each), Image $103B04 (20 bytes each), background drawing of a mode $1003C0, initial sequence
$104726...$1047DA, return to the main mode $104F78...$104FDA.

### 5.1 It is a single proportional gadget: gadget no. 17

The large frame **and** the small square are both drawn by **intuition**, when rendering
this gadget. Preferences draws nothing specific in this area: its only drawing that touches it
is the general window background, in colour 2.

| `Gadget` field | Value |
|---|---|
| LeftEdge, TopEdge, Width, Height | **200, 62, 240, 70** (window coordinates) |
| Flags | **$0007** = GADGHNONE (3) \| GADGIMAGE (4); no GRELxxx, neither SELECTED nor DISABLED |
| Activation | **$000B** = RELVERIFY \| GADGIMMEDIATE \| FOLLOWMOUSE |
| GadgetType | **$0003** = PROPGADGET (no REQGADGET, no GZZGADGET) |
| GadgetRender | knob Image (below) |
| SelectRender | **the same** Image (same pointer) |
| GadgetText, MutualExclude, UserData | NULL / 0 / NULL |
| SpecialInfo | PropInfo below |
| GadgetID | 17 |

| `PropInfo` field | Initial value |
|---|---|
| Flags | **$0006** = FREEHORIZ \| FREEVERT; **no AUTOKNOB**, **no PROPBORDERLESS** |
| HorizPot / VertPot | computed before OpenWindow from the prefs (§5.4) |
| HorizBody / VertBody | **$0800 / $0800** |
| CWidth...TopBorder | 0 (filled in by intuition) |

| Knob `Image` field | Value |
|---|---|
| LeftEdge, TopEdge | 0, 0 (rewritten by intuition at the knob position) |
| Width × Height × Depth | **16 × 8 × 1** |
| ImageData | **non-NULL**: copy in CHIP memory (AllocRemember MEMF_CHIP at start-up, pointer patched) |
| PlanePick / PlaneOnOff | **1 / 0** |
| NextImage | NULL |

Geometry of the data (without reproducing it): the **first line** is entirely 1, and on
the **next 7 lines** only the **two leftmost columns** are 1; everything else is 0.
With PlanePick 1 and PlaneOnOff 0, DrawImage gives **colour 1 (white)** on those bits and **colour
0** everywhere else, plane 1 included. The knob is therefore a white "L" (1 line at the top, 2 pixels
on the left) on a colour 0 background. **It is not solid**: its interior has the same colour as
the interior of the container, hence the "outline only" look on the real ROM.

The window is opened with **NewWindow.DetailPen = BlockPen = $FF**. Intuition therefore takes
the Workbench screen's pens: **Window.DetailPen = 0**, **BlockPen = 1** [D, public OpenWindow
rule; no other value is supplied].

### 5.2 What produces the colour 0 background of the large frame

It is intuition's standard rendering of a PROPGADGET (`intuition-prop-v34.md` §3.1), applied
to this gadget:
1. **RectFill of the whole box** (200,62)–(439,131) in **Window.DetailPen = 0**, in JAM2 ⇒ blue
   background;
2. **frame** of the box in **BlockPen = 1** (white), since PROPBORDERLESS is absent. This is the
   "large frame";
3. **DrawImage(GadgetRender)** at the knob position ⇒ the white "L".

GADGHNONE: no highlighting, even when the gadget is selected.

### 5.3 Call order and time of drawing

Opening (§4, rows 13 to 17):
1. **OpenWindow** (−204) with FirstGadget = the mode's list, which contains gadget 17. Intuition
   does a first rendering of the gadgets there.
2. OpenFont / SetFont (§4).
3. **Mode background** ($1003C0, window rastport, mode 0):
   - **SetDrMd(rp, JAM1)** (−354);
   - for each rectangle of the mode: SetAPen (−342), then **RectFill** (−306). The first
     rectangle is **(1,10)–(637,198) in pen 2**: it covers the whole window, gadget 17
     included, **and erases the first rendering**;
   - the following rectangles (pen 1 frames and pen 0 interiors of the other areas) **do not
     touch** the box of gadget 17;
   - next come lines (Move/Draw −240/−246) and texts (Move, SetAPen, Text −60),
     also outside the box.
4. Ancillary drawings: palette, pointer, values ($109CF0, $1005D2, $10557A), all outside the
   box of gadget 17. At start-up, $10557A does not call ModifyProp.
5. **RefreshGadgets(first gadget of the mode, window, NULL)** (−222). This is the rendering that leaves
   the background **in colour 0**, the white frame and the knob (§5.2).

Return to the main mode from another mode ($104F78):
- same background $1003C0;
- **AddGadget(win, gadget i, −1)** (−42) for i = 0...37;
- ancillary drawings, then RefreshGadgets(gadget 0, win, NULL). Same result.

Later:
- **ModifyProp(gad, win, NULL, PropInfo.Flags, HPot, VPot, HBody, VBody)** (−156) ($105616,
  called by $10557A) is used when the prefs are reloaded wholesale (restore
  buttons). It redraws the gadget, background included.
- Dragging the knob is handled by intuition (FOLLOWMOUSE + MOUSEMOVE in IDCMP $70).
  On release, Preferences recomputes ViewX/YOffset then calls RemakeDisplay
  ($1057FA, §4 row 10).

### 5.4 Initial pots (formula) [O]

HorizPot = (31 − (129 − ViewInitX) + ViewXOffset) × 2048, and VertPot = (31 − (56 − ViewInitY) +
ViewYOffset) × 2048, on 16 bits. The offsets are clamped to −32..+31 when they are rewritten.

### 5.5 Diagnosis of the observed discrepancy [D]

- **Background left in colour 2**: our PROPGADGET rendering does not fill the gadget box in
  Window.DetailPen before the frame and the knob. Another possibility is a window DetailPen
  that is not resolved to 0 from the NewWindow's $FF. The general background (pen 2) painted by
  Preferences then remains visible.
- **"Solid" small square**: our knob is correct (colour 0 interior, white L). It only looks
  solid because it sits on a colour 2 background. Once step 1 of §5.2
  is done, it should blend into the background and show only the L.
- Correspondence with the screenshot: the box (200..439, 62..131) matches x ≈ 388..636 and
  y ≈ 246..390 of the screenshot, if a horizontal offset of about +188 and a vertical
  doubling are applied [D].

## Clean-room review

- [x] No instruction sequence copied: public file format (hunks), public
  structures (Process, WBStartup, WBArg, DiskObject, FileHandle), library calls and
  hypotheses.
- [x] No program data reproduced, apart from strings and sizes.
- [x] §4 (reviewed): sequence of public calls, exit conditions, fields of public structures,
  OpenFont selection rule described by its weightings. No instruction sequence copied.
- [x] §5 (reviewed): public Gadget/PropInfo/Image/NewWindow fields, library calls and drawing
  order; knob image described in geometry only (no data reproduced).
