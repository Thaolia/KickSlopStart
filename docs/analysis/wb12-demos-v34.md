# Workbench 1.2 demos Lines and Clock on Kickstart 1.3: behavioural observations

> **ANALYSIS** track ("dirty"). Black-box runs of the real Kickstart 1.3 (34.5, A500) under Amiberry (A500 preset,
> cycle-exact, 512 KB chip + 512 KB slow), 2026-11-10. Disk: a copy of the Workbench 1.2 (33.56) boot disk whose
> startup-sequence was replaced by `run Clock` or `run Demos/Lines` followed by `endcli >nil:` (no LoadWB, so the
> Workbench screen holds only the CLI window and the demo window). Observation means: screenshots (looked at),
> intuition/layers structures read from RAM with the debugger, the SuperBitMap planes dumped from RAM, and
> instruction-fetch watches placed on the **demo programs' own** library-call stubs (third-party code) to count and
> order their calls. No ROM code was read for this page; it contains no ROM address and no ROM instruction.
>
> **Marks**: **[O]** observed on the real ROM · **[D]** deduced from observations · **[?]** open / uncertain.
>
> Related specs: `intuition-gzz-v34.md` §2.5 (SUPER_BITMAP windows, with and without GIMMEZEROZERO),
> `layers-v34.md` §5-§6 (SizeLayer/ScrollLayer, SuperClipRects, SyncSBitMap/CopySBitMap), `intuition-windows-v34.md`
> (NEWSIZE after SizeWindow).

## 0. Summary for the implementer

1. **Clock leaves nothing at its old size after a shrink on 1.3** [O]. Right after the size gadget is released the
   whole new window area is blank (no frame yet), then the frame, then Clock's face is redrawn from scratch. No
   pixel of the old dial, hands or date survives inside or outside the new frame in any of 17 screenshots taken
   over the 20 s after the release.
2. **Clock never clears its window itself** [O]: it calls neither `SetRast` nor `RectFill`. Its full redraw (filled
   dial, 60 tick marks, hands, date) runs **between `BeginRefresh` and `EndRefresh`**, i.e. clipped to the damage
   region. A clean result after a resize therefore depends on the window layer being cleared and fully damaged by
   the resize (`layers-v34.md`: 1.3 keeps nothing of a resized SIMPLE layer).
3. **Lines draws about 430 lines per second** into its 1008 × 512 × 2 SuperBitMap on 1.3 (431 `Draw` calls per
   second of emulated time, lines about 280-300 pixels long) [O]. Its small window changes only in rare bursts
   because almost every line falls outside the 78 × 30 visible part.
4. **Lines is a GIMMEZEROZERO | SUPER_BITMAP window**, so its frame lives in the outer layer and never reaches the
   SuperBitMap: after a scroll the SuperBitMap holds the old interior with **no frame pixel** [O]. The "frame copied
   into the SuperBitMap" behaviour of a **non-GZZ** SUPER_BITMAP window (`intuition-gzz-v34.md` §2.5) cannot be
   observed with Lines; it stays established by the resize probe of that page.

## 1. Clock (Workbench 1.2, title "Clock V2.15")

### 1.1 The window [O]

Read from intuition's structures while Clock runs (started from the CLI):

| Field | Value |
|---|---|
| Position / size | (10,15), 170 × 105 |
| Flags | `$0000006F`: WINDOWSIZING, WINDOWDRAG, WINDOWDEPTH, WINDOWCLOSE, SIZEBBOTTOM, SIMPLE_REFRESH |
| IDCMP | `$00000307`: SIZEVERIFY, NEWSIZE, REFRESHWINDOW, MENUPICK, CLOSEWINDOW |
| Borders | left 4, top 11, right 4, bottom 10 |
| Limits | min 105 × 65, max 65535 × 65535 |
| Layer | SIMPLE (flags `$0081` = SIMPLE + LAYERREFRESH at that instant), no SuperBitMap |

Clock uses `SIZEVERIFY`: intuition waits for Clock to reply before the size drag starts (the drag worked normally).

### 1.2 Library calls Clock makes [O]

Library calls found in Clock's code (its own stubs, library identified from the base each stub loads):

- graphics: `Move`, `Draw`, `AreaMove`, `AreaDraw`, `AreaEnd`, `InitArea`, `InitTmpRas`, `AllocRaster`,
  `FreeRaster`, `WaitTOF`, `WaitBOVP`, `RectFill`, `SetAPen`, `SetDrMd`;
- intuition: `OpenWindow`, `CloseWindow`, `BeginRefresh`, `EndRefresh`, `PrintIText`, menu-strip calls and a few
  others.

`RectFill` is present in the code but was **never called** during any tick or resize that was traced; `SetRast` is
not used at all.

### 1.3 What Clock does, traced [O]

Call order recorded with fetch watches on Clock's stubs (no event lost in the two short runs):

- **Every tick** (no resize): `WaitBOVP`, area fills for the hands (`AreaMove`, `AreaEnd`, with `SetAPen` changes:
  the old hands are filled over in the dial colour, the new ones drawn), then `PrintIText` (the date line). No
  `BeginRefresh` around it: tick drawing goes straight to the window's RastPort.
- **After each SizeWindow (enlarge or shrink): two `BeginRefresh` … `EndRefresh` pairs in a row**, each holding a
  complete redraw: `SetAPen`, the dial as an area fill, the tick marks as `Move`/`Draw` (58 `Move` calls in the
  enlarged window, 10 in the small one), the hands as area fills, `PrintIText` twice, then `EndRefresh`. Then
  ticks resume.
- Why two refresh passes per resize is not established [?] (one per REFRESHWINDOW, or one for NEWSIZE and one for
  REFRESHWINDOW). The second pass draws through an empty damage list if the first `EndRefresh` emptied it, so it
  is invisible on screen [D].

### 1.4 Screen sequence after a shrink [O]

Shrink by dragging the size gadget up-left (about −50 × −30 then −120 × −50 pixels in two runs):

1. During the drag the window keeps its old size and Clock keeps ticking at that size.
2. About 40 ms after the button is released: the whole new window rectangle is plain background colour, **no frame
   and no dial**; the area uncovered by the shrink already shows the CLI window's text again (repaired).
3. Next screenshots (about 0.5-2 s later): new frame drawn, the dial disc filled (no tick marks or hands yet), then
   the complete small clock (ticks, hands, date).
4. Nothing drawn with the old geometry is visible at any time after the release: no slice of the old dial, no hand
   longer than the new dial, nothing outside the new frame.

Enlarging behaves the same way (blank window, frame, then full redraw at the new size).

### 1.5 Rules for an implementation [D]

- Clear the resized SIMPLE window layer and damage it completely before Clock gets its REFRESHWINDOW; Clock relies
  on that and redraws only between BeginRefresh/EndRefresh.
- Do not let a tick drawn with the old geometry land in the window after the layer has its new size and before the
  refresh: on 1.3 no such drawing is visible. If our side shows a sliver at the old size, compare when Clock's
  NEWSIZE/REFRESHWINDOW arrive relative to its timer tick (on 1.3 the resize, the clear and both messages happen
  before the next visible tick) [?: the exact message order on 1.3 was not traced].

## 2. Lines (Workbench 1.2, Demos drawer)

### 2.1 The window and its SuperBitMap [O]

| Field | Value |
|---|---|
| Title | "Lines Window" |
| Position / size | (200,100), 100 × 50 |
| Flags | `$0000048F`: WINDOWSIZING, WINDOWDRAG, WINDOWDEPTH, WINDOWCLOSE, SUPER_BITMAP, **GIMMEZEROZERO** |
| IDCMP | `$00000267`: SIZEVERIFY, NEWSIZE, REFRESHWINDOW, GADGETDOWN, GADGETUP, CLOSEWINDOW |
| Borders | left 4, top 11, right 18, bottom 9 (two proportional gadgets: right and bottom) |
| Limits | min 80 × 16, max 640 × 65535 |
| Inner layer | bounds 78 × 30 (screen (204,111)-(281,140)), flags `$0004` (LAYERSUPER), Scroll (0,0) |
| SuperBitMap | BytesPerRow 126, Rows 512, Depth 2: 1008 × 512 pixels |

### 2.2 Drawing speed on 1.3 [O]

Method (reproducible on any ROM): an instruction-fetch watch on the `Draw` call in Lines' own graphics stub, logging
only, and the CIA-A TOD counter (vertical-blank count) read before and after.

- 8,593 `Draw` calls in 995 frames (PAL) = **431 calls per second** of emulated time. A first, shorter window gave
  the same order (6,845 calls over about 14.7 s).
- One `Draw` per line (each preceded by its own `Move`). Twelve consecutive calls sampled: lines from points such
  as (691,76) to (727,367), successive endpoints moving by about 7 and 1 pixels per line, lengths about 280-300
  pixels; both endpoints stay inside the 1008 × 512 SuperBitMap.
- The RastPort drawn into is the window's RastPort (layered, SuperBitMap layer). Almost all of each line lies in the
  SuperClipRects (off-window part of the SuperBitMap), so most pixels are written straight into the SuperBitMap.
- After about 60 s the SuperBitMap is covered with dense, overlapping line fans in all four colours (pen changed
  between fans, colour 0 included), so later fans partly overwrite earlier ones.

What the window shows on 1.3: screenshots every 2 s for 60 s after the window opened changed only 7 times out of
30 intervals (the first fan reaching the visible corner, then a few lines now and then). So "the window is frozen
for long periods" is normal on 1.3 too; compare speed with the `Draw` count, not with the window.

### 2.3 What the SuperBitMap holds [O]

- While Lines runs without scrolling, the SuperBitMap area that corresponds to the visible interior (columns 0-77,
  rows 0-29) stays **all colour 0**: lines drawn there go to the screen only; the SuperBitMap is not updated for the
  visible part until a sync.
- After dragging the bottom proportional gadget (the layer's Scroll_X went from 0 to 422): the SuperBitMap columns
  0-77 × rows 0-29 now hold what the window showed before the scroll (the corner of the line fan, colour 3), and
  **no frame pixel**: no border line, no title-bar pixel, no gadget imagery anywhere around that rectangle. The new
  visible part shows the SuperBitMap content at Scroll_X 422.
- So for a GZZ SUPER_BITMAP window, ScrollLayer syncs only the inner layer (interior) into the SuperBitMap [O]; the
  frame belongs to the outer layer and is never copied [D, consistent with `intuition-gzz-v34.md` §2.5].

### 2.4 Non-GZZ SUPER_BITMAP windows [D]

Lines cannot show the non-GZZ case. `intuition-gzz-v34.md` §2.5 already gives it from a probe on the real ROM: the
single layer covers the whole window, the frame is drawn over the SuperBitMap content and is present in the
SuperBitMap right after OpenWindow, and after a SizeWindow the SuperBitMap holds frame pieces the screen does not
show. An implementation that never puts the frame into the SuperBitMap differs from 1.3 only for programs that open
**non-GZZ** SUPER_BITMAP windows and later scroll or read back the SuperBitMap; Lines is not one of them.

## 3. Open points

1. The exact order of SIZEVERIFY / NEWSIZE / REFRESHWINDOW messages Clock receives on 1.3 and its reaction to each
   (the trace shows two refresh passes per resize but not which message triggers each) [?]. A trace of the Class
   field of the messages Clock replies (breakpoint on Clock's `ReplyMsg` stub, reading the IntuiMessage) would
   settle it.
2. Lines speed was measured with the window inactive and unscrolled; the rate with a larger window (more on-screen
   pixels) was not measured [?].

## Clean-room review

Review of 2026-11-10.

- [x] No ROM instruction, routine address or ROM data. Addresses used during the runs (window, layer, planes,
  program stubs) were RAM addresses of this session and are not reproduced, except structure field offsets that
  are public (`intuition.h`, `clip.h`).
- [x] The library calls listed are those of the **third-party** programs (Clock, Lines), named by their public LVOs.
- [x] Figures are outputs of the real ROM on these programs (counts, sizes, flags), not ROM content.
