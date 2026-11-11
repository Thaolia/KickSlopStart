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
   second of emulated time; one `Move` + one `Draw` per line, JAM2, solid pattern, one `SetAPen` per fan of 321
   lines; median line 377 pixels along its major axis; 81 % of the lines lie in a single clip rectangle) [O],
   §3.1. Its small window changes only in rare bursts because almost every line falls outside the 78 × 30 visible
   part.
4. **Timing baselines** (2026-11-11, §3): growing Clock from 170 × 105 to 300 × 200 takes **38 frames** from the
   release of the size gadget to the last `EndRefresh` (two refresh passes of 15 and 10 frames, after up to about
   10.5 frames of Clock's own polling latency); one per-second tick redraw takes **about 2 frames** from Clock's
   wake-up to its next `Delay` [O].
5. **Lines is a GIMMEZEROZERO | SUPER_BITMAP window**, so its frame lives in the outer layer and never reaches the
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
- Two refresh passes per resize: **one per message** [O, 2026-11-11, §3.2]: Clock gets NEWSIZE (class `$2`), runs
  a complete `BeginRefresh` … `EndRefresh` pass and replies it, then gets REFRESHWINDOW (class `$4`), runs a second
  complete pass and replies it. The second pass draws through an empty damage list if the first `EndRefresh`
  emptied it, so it is invisible on screen [D]; it is also shorter (10 frames against 15).

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

## 3. Timing on 1.3 (2026-11-11)

Real Kickstart 1.3 under Amiberry (A500 preset, cycle-exact, 512 KB chip + 512 KB slow), same disks as above
(copies of the Workbench 1.2 boot disk with `run Demos/Lines` or `run Clock` + `endcli >nil:`). All counts and
timings come from hardware breakpoints placed on the JSR instructions inside the **programs' own library stubs**
(third-party code) and from the emulator's frame counter; no ROM code was read. The Workbench 1.3.3 boot disk has
**no Clock** (its `Utilities` drawer holds only More and Say), so only the Workbench 1.2 Clock was measured.

### 3.1 Lines: graphics calls per line, lengths, clipping [O]

Method: breakpoints on the JSRs of Lines' `Move`, `Draw`, `SetAPen` and `SetDrMd` stubs (Lines' graphics stub hunk
is hunk 12 of 16; the JSRs sit at offsets +18, +46, +128 and +152 of that hunk); at each hit A1 (RastPort), D0/D1
(target point) and the RastPort fields `cp_x`/`cp_y` (start point), `FgPen`, `DrawMode`, `LinePtrn` and `Flags` were
logged. Four samples taken minutes apart: 299, 1,495, 1,496 and 1,496 `Draw` calls (4,786 lines).

- **Calls per line**: exactly one `Move` (start point) then one `Draw` (end point); no `SetAPen`/`SetDrMd` between
  the lines of a fan. (Lines' other graphics stubs, `InitArea`, `BltClear`, `InitBitMap`, `InitTmpRas`,
  `AllocRaster`, `FreeRaster`, are set-up calls and were not traced.)
- **`SetAPen`**: once per **fan of 321 lines**, before the fan; its pen argument goes up by one per fan (values far
  above 3 and negative values seen: it is a running counter; the low byte lands in `FgPen`, and with a 2-plane
  SuperBitMap only its two low bits select the colour [D]).
- **`SetDrMd`**: never called while lines are drawn. `DrawMode` = 1 (**JAM2**) on every call.
- **Line pattern**: `LinePtrn` = `$FFFF` on every call (solid). `Flags` = `$0001` (FRST_DOT, set by the preceding
  `Move`) at each `Draw`.
- **RastPort**: the window's RastPort, i.e. the GIMMEZEROZERO inner layer (LAYERSUPER).
- **Lengths** (pixels along the major axis, endpoints included): min 7, 10th percentile 151, quartiles 231 / 377 /
  640, 90th percentile 753, max 1,005; mean 428. Both endpoints always inside the 1008 × 512 SuperBitMap. (The
  "280-300 pixels" of §2.2 came from twelve calls of one fan; the four samples show the real spread.)
- **Clip rectangles of the inner layer** (read from RAM while Lines ran, window unscrolled, Scroll (0,0)): one
  `ClipRect` = the visible 78 × 30 part (layer coordinates (0,0)-(77,29), on screen, no BitMap), and two
  `SuperClipRect`s in SuperBitMap coordinates: **(0,30)-(77,511)** and **(78,0)-(1007,511)**. The three rectangles
  tile the 1008 × 512 SuperBitMap.
- **Pieces per line** (each logged segment intersected with the three rectangles, pixel bounds inclusive; geometry
  computed from the logged endpoints, not from graphics' internals) [D from O]:

  | Rectangles crossed | Draw calls | Share |
  |---|---|---|
  | only the right SuperClipRect (78,0)-(1007,511) | 3,854 | 80.5 % |
  | only the lower-left SuperClipRect (0,30)-(77,511) | 24 | 0.5 % |
  | both SuperClipRects | 862 | 18.0 % |
  | the on-screen ClipRect + the right SuperClipRect | 35 | 0.7 % |
  | all three | 11 | 0.2 % |
  | only the on-screen ClipRect | 0 | 0 % |

  So **81.0 % of the lines lie entirely inside one rectangle** (all of them off-screen, written straight into the
  SuperBitMap) and **19.0 % are split into two or three pieces**; **0.9 %** reach the visible window at all.

### 3.2 Clock: resize from 170 × 105 to 300 × 200 [O]

Method (repeatable on any ROM, the program and the emulator being the same):

1. Hunks of Clock: `amiberry-session gdb <s> -ex 'monitor process-break name Clock' -ex continue -ex 'monitor
   segments'` (index = hunk number, address = start of the hunk's data). Clock's stub hunks and the JSR offsets
   used (third-party code): hunk 24 (dos): `Delay` JSR at +64, the instruction after it (return from `Delay`) at
   +68; hunk 25 (exec): `GetMsg` JSR at +180, its return at +184, `ReplyMsg` JSR at +200; hunk 26 (graphics):
   `WaitBOVP` JSR at +268; hunk 27 (intuition): `PrintIText` JSR at +248, `BeginRefresh` at +492, `EndRefresh`
   at +516. A1 at the `ReplyMsg` JSR is the IntuiMessage (Class at offset 20).
2. Frame stamps: at every breakpoint hit, `monitor execution-status` returns the emulated `frame` and `vpos`
   (breakpoint stops do not advance them). PAL: 313 lines per frame.
3. Drag: with the pointer on the size gadget of the 170 × 105 window at (10,15) (`mouse:-900,-400` then
   `mouse:170,228` in an `input` script), `ldown`, `mouse:130,190`, 1.5 s pause. Then the **release with a frame
   stamp**: IPC `PAUSE`, `MONITOR execution-status` (frame F0), `SEND_MOUSE 0 0 0` (button up while paused), attach
   gdb with the breakpoints and `continue` in a loop, IPC `RESUME`. The window was then exactly **300 × 200** at
   (10,15) (read from the Window structure).
4. Reference point for the system's reaction (optional): a breakpoint on layers.library's public `SizeLayer`
   (LVO −66) jump-table entry in RAM.

Results (two runs, F0 = frame in which the button-up was delivered):

| Frame (line) | Event |
|---|---|
| F0+1 (223) | `SizeLayer` entered (run 2, the only one with that breakpoint): intuition resizes the window layer, 1 frame after the release |
| F0+12 (133) | Clock's next poll (return from its `Delay`): `GetMsg` returns **NEWSIZE**; `BeginRefresh` |
| F0+27 (173) | `EndRefresh` of pass 1 (two `PrintIText` just before it): **15.1 frames** |
| F0+27 (184-186) | `ReplyMsg` NEWSIZE; `GetMsg` returns **REFRESHWINDOW**; `BeginRefresh` |
| F0+37 (309) | `EndRefresh` of pass 2: **10.4 frames** (run 1: F0+37, line 286) |
| F0+38 (9) | `ReplyMsg` REFRESHWINDOW; `GetMsg` returns nothing; a tick redraw follows at once (`WaitBOVP` F0+38, `PrintIText` F0+39, `Delay` F0+40) |

- **Release → last `EndRefresh` = 38 frames** (37 frames + 286-309 lines) in both runs.
- Of these, about 1 frame is intuition's reaction (release → `SizeLayer`) and the next 10.7 frames are Clock's
  **polling latency**: Clock never waits on its IDCMP port; it calls `Delay` (about 10 ticks, from its duration) and then polls with `GetMsg`
  (§3.3), so the messages wait for the next poll. That part depends on the poll phase (0 to about 10.5 frames; it
  happened to be near the maximum in both runs); the two refresh passes (25.5 frames together) do not.

### 3.3 Clock: one per-second tick [O]

- **Main loop**: `Delay` (call to return 10.2-10.8 frames, i.e. a 10-tick delay), then `GetMsg` on the IDCMP port,
  then the time check. No `WaitTOF` and no exec `Wait` are called by Clock in this loop (breakpoints on both stubs
  never hit). A poll comes about every 10.3 frames (12-13 when a redraw falls in between).
- When the second has changed, the poll redraws: `SetAPen`, **`WaitBOVP`**, three area fills (`AreaEnd` ×3, pens 1,
  2, 3: old hands covered, new hands drawn), `PrintIText` (date line), then the next `Delay`. Redraws start
  44-53 frames apart (poll quantisation of the 50 Hz second); their mean period over ten ticks is 50.3 frames.
- **Duration of one tick redraw**, from the return of `Delay` to the next `Delay` call:
  - 300 × 200 window: **1.94 / 2.06 / 2.10 frames** (three ticks), e.g. `Delay` returns F+0 line 262, `WaitBOVP`
    called F+1 line 76, `PrintIText` F+2 line 216, `Delay` F+2 line 280.
  - 170 × 105 window (six ticks): from the poll's `GetMsg` to `PrintIText` 1.36-1.68 frames, `Delay` about 60
    lines later.
  - `WaitBOVP` returns at the bottom of the screen: the first `AreaEnd` comes at line 300 of the frame in which
    `WaitBOVP` was called. So a tick is up to one frame of **waiting** for the beam plus the drawing, which takes
    about 0.8 frame (170 × 105: line 300 → line ~235 of the next frame) to 0.9 frame (300 × 200: line 300 → line
    ~280 of the next frame) [D from O].
- For the implementation side: compare the frame counts of the same breakpoints (`Delay` return → next `Delay`,
  `BeginRefresh` → `EndRefresh`) on its own ROM; the waiting part (`Delay` itself, `WaitBOVP`) is set by the
  program, not by the ROM's speed.

## 4. Open points

1. The exact order of SIZEVERIFY / NEWSIZE / REFRESHWINDOW messages Clock receives on 1.3 and its reaction to each
   (the trace shows two refresh passes per resize but not which message triggers each) [?]. A trace of the Class
   field of the messages Clock replies (breakpoint on Clock's `ReplyMsg` stub, reading the IntuiMessage) would
   settle it. **Answered 2026-11-11 for NEWSIZE / REFRESHWINDOW (§3.2)**: NEWSIZE first, one refresh pass, reply;
   then REFRESHWINDOW, one pass, reply. The SIZEVERIFY exchange at the start of the drag was not traced.
2. Lines speed was measured with the window inactive and unscrolled; the rate with a larger window (more on-screen
   pixels) was not measured [?].

## Clean-room review

Review of 2026-11-10; §3 added and reviewed 2026-11-11.

- [x] No ROM instruction, routine address or ROM data. Addresses used during the runs (window, layer, planes,
  program stubs) were RAM addresses of this session and are not reproduced, except structure field offsets that
  are public (`intuition.h`, `clip.h`).
- [x] The library calls listed are those of the **third-party** programs (Clock, Lines), named by their public LVOs.
- [x] Figures are outputs of the real ROM on these programs (counts, sizes, flags), not ROM content.
- [x] §3 (2026-11-11): breakpoints only on the programs' own stub JSRs (offsets given are inside Clock's and
  Lines' hunks, third-party code) and on one public LVO jump-table entry in RAM; frame numbers from the emulator. No
  ROM address, no ROM instruction.
