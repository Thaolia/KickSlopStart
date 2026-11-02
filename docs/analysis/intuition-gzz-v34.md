# intuition-gzz-v34.md — window borders, layers and coordinates (GIMMEZEROZERO or not)

> ANALYSIS track ("dirty"). Source: ROM `assets/kick34005.A500`, module intuition 34.3
> (OpenWindow, border adjustment by gadgets, gadget context, system gadgets,
> mouse coordinates, IntuiMessage, rendering of a gadget list, window drawing, AddGadget;
> no ROM address, removed on 2026-10-29). Practical case: `libs/info.library` from `wb133.adf`.
> §2.5 (SizeWindow and the window's layers) comes from the black-box probe `tests/resize_probe.s`
> (harness `tests/resize_probe.sh`, FS-UAE A500 PAL, real ROM, pixel readback of the screen BitMap).
>
> **Legend**: **[O]** observed · **[D]** deduced · **[S]** assumed. **No instruction sequence is reproduced**: only calculation rules,
> fields of public structures (`intuition.h` 1.3) and library calls.

`struct Window` fields used: LeftEdge +$04, TopEdge +$06, Width +$08, Height +$0A,
MouseY +$0C, MouseX +$0E, Flags +$18, RPort +$32, BorderLeft/Top/Right/Bottom +$36/$37/$38/$39
(signed bytes), BorderRPort +$3A, FirstGadget +$3E, IDCMPFlags +$52, GZZMouseX +$6C,
GZZMouseY +$6E, GZZWidth +$70, GZZHeight +$72, WLayer +$7C, IFont +$80.
`struct Screen`: MouseY +$10, MouseX +$12, WBorTop +$23, WBorLeft +$24, WBorRight +$25,
WBorBottom +$26, Font (TextAttr*) +$28, ViewPort.Modes +$4C (HIRES $8000), LayerInfo +$E0,
BarLayer +$14E.

---

## 1. Border calculation at OpenWindow

### 1.1 Base values [O]

In this order:

1. **Screen borders.** If the window is **not BORDERLESS** ($800): BorderLeft,
   BorderTop, BorderRight and BorderBottom := WBorLeft, WBorTop, WBorRight and WBorBottom of
   the screen. Otherwise they are 0.
2. **Title bar.** If the window has WINDOWDRAG, WINDOWDEPTH or WINDOWCLOSE ($0E), **or** a
   non-null Title: **BorderTop += `Screen->Font->ta_YSize` + 1**. This is the height of the
   **screen's** font, not the window's. This rule also applies to a
   BORDERLESS window.
3. **Sizing gadget.** If the window has WINDOWSIZING ($01):
   - with **SIZEBBOTTOM** ($20): **BorderBottom := height of the sizing gadget's image + 1**;
   - with **SIZEBRIGHT** ($10), **or if neither bit is set**: **BorderRight :=
     width of the image + 2**;
   - both bits can be set together.
   The image is the system sizing gadget for the screen's resolution: HIRES variant if
   `ViewPort.Modes` has $8000, otherwise LORES.
4. **BACKDROP** ($100): the SIZING, DRAG and DEPTH bits are removed from the Flags **before**
   step 2 (only CLOSE can then still cause the bar).

### 1.2 Adjustment by user gadgets (all windows) [O]

It is done **after** the base values and **for all windows, GZZ or not**. The
walk covers **the whole `NewWindow.FirstGadget` list**, but not the system gadgets. For
each gadget, intuition computes its **box** (§4.1) in its domain, then applies the
**Activation** bits:

| Activation bit | Rule (max with the current value) |
|---|---|
| **LEFTBORDER** ($20) | BorderLeft := max(BorderLeft, box.Left + box.Width − 1) |
| **RIGHTBORDER** ($10) | BorderRight := max(BorderRight, Window.Width − box.Left) |
| **TOPBORDER** ($40) | BorderTop := max(BorderTop, box.Top + box.Height − 1) |
| **BOTTOMBORDER** ($80) | BorderBottom := max(BorderBottom, Window.Height − box.Top) |

Additional rules:
- The result is stored in the border byte.
- The **type** flags (GZZGADGET) and **position** flags (GRELxxx) play a part **only** in the
  box calculation. It is the **xxxBORDER bits of the Activation** that decide.
- A gadget without an xxxBORDER bit **never enlarges** the border, even if it is placed in the
  frame.
- Borders are **never reduced** by this step.
- **Non-GZZ**: the borders are enlarged in the same way. The value is then used for drawing
  the frame, for the GZZMouse coordinates and for GZZWidth/Height, but **not** for a second layer
  (§2).

**Pitfall [O]**: at the time of this calculation, GZZWidth and GZZHeight are still **0**, because they
are only computed afterwards (§2.3). In a GZZ window, a **non**-GZZGADGET gadget carrying an
xxxBORDER bit therefore has its box computed in an inner domain of size 0: a GRELxxx
adds nothing. For a GZZGADGET, the domain is the whole window (W×H, origin 0,0) and the
calculation is exact.

### 1.3 Verified example: info.library's Info window [O]

NewWindow: 604×190, Flags $146F (SIZING | DRAG | DEPTH | CLOSE | **SIZEBBOTTOM** |
SIMPLE_REFRESH | GIMMEZEROZERO | ACTIVATE). SIZEBRIGHT is not set.

`NewWindow.FirstGadget` list, in this order:

| # | Gadget | Left, Top, W×H | Flags | Activation | Type |
|---|---|---|---|---|---|
| 1 | **QUIT** | −108, −10, 80×9 | GRELBOTTOM \| GRELRIGHT ($18) | RELVERIFY ($01), **without** BOTTOMBORDER | GZZGADGET \| BOOLGADGET ($2001) |
| 2 | **SAVE** | 20, −10, 80×9 | GRELBOTTOM ($08) | RELVERIFY \| **BOTTOMBORDER** ($81) | $2001 |
| 3 | **filler** | 4, −11, 0×0 | GADGHNONE \| GADGIMAGE \| GRELBOTTOM \| GRELWIDTH ($2F) | **BOTTOMBORDER** ($80) | $2001 |

Calculation of BorderBottom, with Height = 190:
- SAVE: Top = −10 + 189 = 179 ⇒ 190 − 179 = 11;
- filler: Top = −11 + 189 = 178 ⇒ 190 − 178 = **12**;
- **BorderBottom = max(sizing image + 1, 11, 12) = 12**, if the sizing image is less than
  12 lines tall.

The inner area ends at line 190 − 12 − 1 = **177**. The filler starts at
line 178 (it spans the whole width thanks to GRELWIDTH); SAVE and QUIT, at line 179, are
drawn on top of it (§6). QUIT plays no role in the calculation.

---

## 2. The layers

### 2.1 Non-GZZ window [O]

- **A single layer**: **CreateUpfrontLayer**(screen's LayerInfo, screen's BitMap,
  rectangle of the whole window, flags, `NewWindow.BitMap`).
- The layer flags come from the window's refresh type:
  - SIMPLE_REFRESH ($40) ⇒ LAYERSIMPLE (1);
  - SUPER_BITMAP ($80) ⇒ LAYERSUPER (4);
  - otherwise (SMART) ⇒ LAYERSMART (2);
  - plus **LAYERBACKDROP ($40)** if BACKDROP.
- WLayer (+$7C) := this layer, and `layer->Window` := the window.
- RPort (+$32) := the layer's RastPort; the screen's font is applied to it by SetFont.
- **BorderRPort (+$3A) = NULL.**

### 2.2 GIMMEZEROZERO window [O]

Creation order:
1. **Outer layer (frame)**:
   - rectangle of the **whole** window;
   - flags **LAYERSIMPLE**, always, whatever refresh is requested (plus
     LAYERBACKDROP if BACKDROP);
   - created **first**, by CreateUpfrontLayer.
   - Temporarily WLayer = this layer and RPort = its RastPort, with the screen font.
2. Borders (§1), system gadgets and addition of the user gadgets.
3. **Inner layer**:
   - CreateUpfrontLayer on the rectangle
     **(LeftEdge + BorderLeft, TopEdge + BorderTop) – (LeftEdge + Width − 1 − BorderRight,
     TopEdge + Height − 1 − BorderBottom)**;
   - flags = **requested refresh type** (SIMPLE, SMART or SUPER, plus BACKDROP), with
     `NewWindow.BitMap` as super-bitmap;
   - then **MoveLayerInFrontOf(inner, outer)**.
4. Final assignments:
   - `inner->Window` := the window, **WLayer (+$7C) := inner layer**;
   - **BorderRPort (+$3A) := RastPort of the outer layer**;
   - **RPort (+$32) := RastPort of the inner layer**, whose TmpRas and AreaInfo are reset to
     NULL.

If creating a layer fails, OpenWindow fails.

### 2.3 GZZWidth / GZZHeight [O]

Computed after the layers, for **all** windows:
- **GZZWidth = Width − BorderLeft − BorderRight**;
- **GZZHeight = Height − BorderTop − BorderBottom**.

### 2.4 Miscellaneous [O]

For a BACKDROP window on a screen whose title bar is displayed, intuition does
MoveLayerInFrontOf(screen's BarLayer, window's layer).

### 2.5 SizeWindow and the window's layers [O]

Probe setup: windows on the Workbench screen (640 wide, 2 planes) at (100,30), 200×80, no title, no
gadget except the sizing gadget (`WINDOWSIZING`), IDCMPFlags = NEWSIZE | REFRESHWINDOW ($6). Borders
measured: BorderLeft 4, BorderTop 2, BorderRight 18, BorderBottom 2. Pattern = 8×8 checker of pens 1/2
relative to the origin of the drawn RastPort. Pixels read from the screen BitMap about 2 s after the
call (50 × Delay(2) while draining the UserPort), **before** any BeginRefresh. Coordinates below are
window-relative.

**Messages.**
- **No NEWSIZE is ever posted by SizeWindow()** in these runs: SIMPLE, SMART, SUPER, GZZ SUPER windows,
  IDCMP NEWSIZE|REFRESHWINDOW, and a control window with IDCMP = NEWSIZE alone (nothing received in
  4 s), although the size is applied (`Width`/`Height` updated). This contradicts
  `intuition-input-menus-v34.md` §2.4 ("NEWSIZE at the end of each SizeWindow"); NEWSIZE after a
  drag of the sizing gadget by the user was not tested here.
- REFRESHWINDOW: **one** message after each SizeWindow of a window whose (single) layer ends up with
  LAYERREFRESH: SIMPLE (grow and shrink), SMART (grow +16,+8), non-GZZ SUPER (grow). **None** for the
  GZZ SUPER window. None at OpenWindow (SIMPLE: the layer has LAYERREFRESH from its creation, Flags
  `$0081`, empty DamageList, but no message).

**SIMPLE_REFRESH, non-GZZ** (single layer, Flags `$0081` after OpenWindow):
- SizeWindow(+40,+20) → 240×100: the **whole window is 0** (old interior included) except the frame,
  which intuition has redrawn completely at the new size (top and bottom lines, 2-pixel left line,
  right band with its line, sizing gadget) before REFRESHWINDOW. Layer Flags `$0081`, DamageList =
  one rectangle `(0,0)-(239,99)` (whole layer). Matches layers `layers-v34.md` §5.7 (SIMPLE: nothing
  survives).
- BeginRefresh + EndRefresh(TRUE) with no drawing: Flags `$0001`, DamageList empty, pixels unchanged.
- Interior refilled, then SizeWindow(−60,−30) → 180×70: interior 0 again, frame complete at the new
  size. Flags `$0081`. DamageList bounds `(0,0)-(239,99)` = the **old** size, rectangles: whole new
  window `(0,0)-(179,69)`, old right band `(222,1)-(239,99)`, new right band extended to the old height
  `(162,70)-(179,99)`, old bottom band `(0,98)-(161,99)` and `(180,98)-(221,99)`, new bottom band
  extended to the old width `(180,68)-(221,69)`, pixel `(239,0)`. These bands of the old and new frame
  are not produced by layers for a SIMPLE layer (whole new layer only), so intuition adds them [D].
  Implementations: the DamageList may extend beyond the shrunken layer.

**GIMMEZEROZERO | SUPER_BITMAP** (`NewWindow.BitMap` = InitBitMap'ed 320×200×2, filled by the CPU):
- `RPort->Layer` = `WLayer` = inner layer; its **`SuperBitMap` = the supplied BitMap** (same pointer);
  inner Flags **`$0004`** (SUPER alone); inner bounds = window rectangle minus borders, 178×76.
- `BorderRPort->Layer` = outer layer, Flags **`$0081`** after OpenWindow (SIMPLE + LAYERREFRESH).
- After OpenWindow the interior shows the SuperBitMap from its (0,0) (inner layer origin ↔ SuperBitMap
  (0,0)).
- SizeWindow(+40,+20): **no message at all**; every interior pixel, newly visible ones included
  (218×96), equals the SuperBitMap; inner Flags `$0004`, DamageList empty; outer Flags `$0001`, empty
  DamageList (frame repaired by intuition itself, complete); the SuperBitMap is unchanged (sampled
  over (0,0)-(241,101)).

**SUPER_BITMAP without GIMMEZEROZERO** (single layer = whole window):
- Layer Flags `$0004`, `SuperBitMap` = supplied BitMap, BorderRPort = NULL. Layer origin = window origin
  ↔ SuperBitMap (0,0): the frame is drawn over the SuperBitMap content (border bands 0, lines pen 1).
- Right after OpenWindow the **SuperBitMap already contains the frame** (rows 0-79, columns 0-199
  equal to the screen); the rest of the SuperBitMap is unchanged.
- SizeWindow(+40,+20) → 240×100: one REFRESHWINDOW; Flags **`$0084`** (LAYERREFRESH set although layers
  gives no damage to a SUPER layer, `layers-v34.md` §5.7); DamageList bounds `(0,0)-(239,99)`,
  rectangles: old right band `(182,1)-(199,79)`, new right band `(222,1)-(239,79)`, old bottom band
  `(0,78)-(181,79)`, new bottom band `(0,98)-(182,99)`, pixels `(199,0)` and `(239,0)`, new sizing gadget
  `(224,91)-(239,99)` — only frame pieces, added by intuition [D].
- Screen: old interior kept; newly exposed pixels (columns 200-239, rows 80-99) come from the
  SuperBitMap; inside the DamageList everything is 0 except the new frame drawn there. The new frame is
  drawn **only inside these rectangles**: the left border on rows 80-97, the right band on rows 80-90,
  the top line on columns 200-238 and the bottom band on columns 183-223 are **not drawn** and show the
  SuperBitMap pattern. The old border bands inside the new interior are 0.
- The SuperBitMap after the resize is **not** equal to the screen: it holds frame pixels that the
  screen does not show (complete top line 0-239; left band columns 0-3 = 0 on rows 1-77 and 80-97,
  i.e. without its line; right band 222-239 = 0 with its line on rows 1-77 and without line on rows
  80-90; new sizing gadget on rows 91-99), plus the old border bands as 0.
- BeginRefresh + EndRefresh(TRUE) without drawing: Flags `$0004`, DamageList empty, screen and
  SuperBitMap unchanged (EndRefresh repairs nothing).
- Consequence for an implementation: a non-GZZ SUPER_BITMAP window is left with an incomplete frame
  after SizeWindow on 1.3; the application is expected to redraw the frame (or use GZZ). How the frame
  pixels reach the SuperBitMap without reaching the screen is not established.

**SMART_REFRESH, non-GZZ** (control): SizeWindow(+16,+8) → one REFRESHWINDOW, no NEWSIZE.

---

## 3. Mouse coordinates

- **Window.MouseX / MouseY** [O]: Screen.MouseX − LeftEdge and Screen.MouseY − TopEdge. They
  are **relative to the corner of the whole window**, GZZ or not.
- **GZZMouseX / GZZMouseY** [O]: MouseX − BorderLeft and MouseY − BorderTop. They are
  computed **for all windows**, at the same time.
- **IntuiMessage.MouseX / MouseY** (+$20 / +$22) [O]:
  - copy of **Window.MouseX / MouseY**, hence relative to the **whole** window, **even for
    a GZZ window**;
  - exception: with **DELTAMOVE** ($100000) in IDCMPFlags, they are deltas.
  - A GZZ application must therefore subtract the borders or read GZZMouseX/Y.

---

## 4. Gadget domains

### 4.1 Box of a gadget in its domain [O]

The domain provides a width DW and a height DH. The box is relative to the **origin of the
domain**:

| Field | Value |
|---|---|
| Left | LeftEdge + (GRELRIGHT ? DW − 1 : 0) |
| Top | TopEdge + (GRELBOTTOM ? DH − 1 : 0) |
| Width | Width + (GRELWIDTH ? DW : 0) |
| Height | Height + (GRELHEIGHT ? DH : 0) |

### 4.2 Domain according to window and gadget type [O]

| Window | Gadget | Domain (origin; size) | Rendering layer |
|---|---|---|---|
| non-GZZ | any gadget | (0,0); Width × Height | WLayer |
| GZZ | **GZZGADGET** ($2000) | (0,0); **Width × Height** (whole window) | **BorderRPort's layer** (frame) |
| GZZ | **non-GZZGADGET** | (**BorderLeft, BorderTop**); **GZZWidth × GZZHeight** | **WLayer** (inner layer) |

Consequences:
- **A non-GZZGADGET gadget in a GZZ window** has coordinates **relative to the interior**,
  and its GRELxxx are relative to **GZZWidth / GZZHeight**.
- Requester gadgets (REQGADGET $1000) and screen gadgets (SCRGADGET $4000): other domains (that of the
  requester, the screen), out of scope here.

### 4.3 System gadgets [O]

- The system gadgets (sizing, drag, depth, close) are created according to the window's Flags,
  from the templates in IntuitionBase and in the variant for the screen's resolution.
- **For a GZZ window, each one receives the GZZGADGET bit**: they belong to the
  "whole window" domain and are **drawn in the frame layer**.
- They are placed **at the head** of the window's list, before the user gadgets.

---

## 5. Drawing layer on refresh

- **Gadgets**: each one is rendered in the layer of its domain (§4.2). In a GZZ window:
  - GZZGADGET and system gadgets ⇒ outer layer (BorderRPort);
  - other gadgets ⇒ inner layer (RPort / WLayer). They are therefore clipped by the inner
    area: a non-GZZ gadget placed in the frame would be invisible. [O for the choice of
    layer, D for the consequence]
- **Frame and title**: in a GZZ window, they go into the outer layer, since it is
  the only RastPort that covers the frame [D].
- **Non-GZZ window**: everything is in the single layer. The frame gadgets share the
  application's RastPort [O: single layer].
- **Outer layer always LAYERSIMPLE**: when it is uncovered, intuition must
  redraw the frame and the GZZGADGETs, since layers keeps no copy of them [D,
  consequence of LAYERSIMPLE].

---

## 6. Gadget drawing order [O]

### 6.1 Common list rendering routine

All the paths listed in §6.2 go through **the same routine**, which receives the first gadget and
a count `n`. It works in two passes.

1. **Rendering pass, backwards.** It first advances to the **last** gadget of the range:
   the n-th, or the end of the list if `n` is −1 or −2. It then draws **from that last one
   up to the first**, walking back up the list (each time the gadget whose Next points to the
   current one). For each gadget, **in this order**:
   1. the rendering: PropGadget (container and knob), otherwise **DrawImage** of GadgetRender if
      GADGIMAGE, otherwise **DrawBorder** of GadgetRender (nothing if the pointer is NULL);
   2. its **GadgetText** (PrintIText);
   3. for a STRGADGET, its text;
   4. if **GADGDISABLED**, the ghosting pattern over its box (exact rule in §6.4).

   So there is **no** "all images, then all texts" pass: each gadget is
   finished before moving to the previous one. **The first gadget of the list is drawn last,
   hence on top of the others.**
2. **Highlight pass, forwards**, from the first to the last of the range: for each
   **SELECTED** gadget, application of its highlight mode (GADGHCOMP, etc.).

Each gadget is drawn in the layer of its domain (§4.2), with its box computed at the time
of drawing.

### 6.2 Who calls this routine, with what range

| Event | Starting gadget | Count |
|---|---|---|
| **OpenWindow** (initial drawing, after the frame) | `Window->FirstGadget`: system gadgets at the head, then the whole NewWindow list | −1 (whole list) |
| **RefreshWindowFrame** (−456), and **frame repair** when the frame layer (GZZ) or the single layer has LAYERREFRESH (BeginUpdate of the frame layer, frame redrawn, all gadgets, EndUpdate) | `Window->FirstGadget` | −1 |
| **RefreshGadgets**(gad, win, req) (−222) | `gad` | **−2** (up to the end of the list) |
| RefreshGList (V36+, absent in 1.3) | — | — |
| Drawing of a requester | first gadget of the requester | −1 |
| Screen title bar | screen gadgets | −1 |
| One-off refresh (window activation or deactivation, frame gadgets) | one gadget | 1 |
| **AddGadget**(win, gad, pos) (−42) | — | **draws nothing**: simple insertion at position `pos` (−1 = end), the gadget is only displayed at the next Refresh |
| **OffGadget**(gad, win, req) (−174) / **OnGadget**(gad, win, req) (−186) | `gad` | **−2**: set / clear GADGDISABLED, then exactly the RefreshGadgets(gad, win) path (§6.4) |

Requester gadgets (GTYP REQGADGET), for every caller of the routine [O, ROM reading, not probed]: the
requester is the one of the window's requester list whose gadget list contains `gad`; if it is not
displayed (no ReqLayer) nothing is drawn. If that requester has Flags bit $0002 (PREDRAWN in the
public headers) nothing is drawn either. With a count of −2 the range starts at the requester's
**first** gadget (`ReqGadget`), not at `gad`: RefreshGadgets/OnGadget/OffGadget on any requester
gadget redraw the whole requester list.

### 6.3 Application to the Info window (info.library) [O]

- **Initial list** passed via `NewWindow.FirstGadget`: **QUIT → SAVE → filler**. The
  templates are copied into an AllocRemember block and chained in this order. OpenWindow inserts
  the system gadgets **in front of** this list.
- **After OpenWindow**, info.library adds the other gadgets with **AddGadget(win, g, −1)**,
  hence **at the end**:
  - the 4 protection boxes;
  - the string gadgets (default tool, tool types…);
  - the scroll arrows;
  - ADD and DEL.
  It removes them and adds them back in the same way (RemoveGadget, then AddGadget −1) when the
  contents change.
- **Refresh**: info.library always calls **RefreshGadgets(win->FirstGadget, win,
  NULL)**, hence the whole list, system gadgets included.
- **Resulting drawing order**: last added (ADD/DEL…), …, **filler**, then
  **SAVE**, then **QUIT**, then the system gadgets.
  - The filler, a 598×10 image with PlanePick 0 and PlaneOnOff 2, hence a solid rectangle
    of colour 2, is painted **before** SAVE and QUIT.
  - Their JAM2 texts ("SAVE", "QUIT") are therefore written **on top**.
  - It is the "end to start" order of the common routine that guarantees the result at
    every refresh: at OpenWindow, at every RefreshGadgets, at every frame
    repair.
- An implementation that drew forwards (first → last) would cover SAVE and QUIT
  with the filler.

### 6.4 Ghosting of GADGDISABLED gadgets

Sources: ROM reading of the gadget list routine, of the gadget environment set-up and of
OnGadget/OffGadget [O]; black-box check on SysInfo 4.4 and on Workbench 1.3.3 menus, Amiberry,
real ROM 34.5, screen pixels read from the emulator picture [O, screenshot].

**What is drawn** [O]. In step 4 of the rendering pass (§6.1), after the gadget's rendering, its
GadgetText and (STRGADGET) its text, a gadget whose Flags has **GADGDISABLED ($0100)** gets a
patterned **RectFill** over its box. It applies to **every gadget type** (boolean, proportional,
string) and to every domain (window, GZZ frame, requester, screen gadgets): the test is the flag
only.

- **Rectangle**: the gadget's box as computed for the domain in §4.1, i.e. after GRELRIGHT,
  GRELBOTTOM, GRELWIDTH and GRELHEIGHT; inclusive corners (Left, Top) – (Left + Width − 1,
  Top + Height − 1), in the coordinates of the domain's rendering layer (§4.2; for a requester
  gadget its requester's layer, for a screen gadget the screen's title-bar layer). Nothing is drawn
  if the resolved Width or Height is ≤ 0. The fill does **not** extend to a GadgetText, a Border or an
  Image that lies outside the box; inside the box the dots are laid over whatever the rendering drew.
- **Pattern**: AreaPtrn = 4 words **$4444, $1111, $4444, $1111**, AreaPtSz = **2** (4 lines; the
  visible period is 2 lines). One pixel out of four on every line: on pattern lines 0 and 2 the
  pixels with x mod 4 = 1, on lines 1 and 3 those with x mod 4 = 3 (diagonal dot grid).
- **Pens**: APen = the **BlockPen of the gadget environment**, BPen = 0, DrawMode = **JAM1** (only
  the dots are written; the other pixels keep what the gadget rendering left). The environment's
  BlockPen is `Window->BlockPen` for window gadgets **and for requester gadgets** (not the
  requester's BackFill), and `Screen->BlockPen` for screen gadgets (SCRGADGET).
- **RastPort**: the list is drawn in a copy of the domain's RastPort held in IntuitionBase (layer of
  §4.2), so AreaPtrn/AreaPtSz/pens set for the ghosting are not left in `Window->RPort`. While the
  list is drawn, the layer is locked, its clip region is removed (InstallClipRegion NULL) and its
  Scroll_X/Scroll_Y are forced to 0; all three are restored afterwards [O].
- **Pattern origin** [O, ROM reading of graphics BltPattern]: the pattern is aligned on the
  **coordinates of the RastPort that is drawn into**, in both directions: the pixel at RastPort
  coordinates (x, y) (layer coordinates; for gadgets the scroll is 0, see above, so the origin is
  the layer's top-left corner) uses word `y mod 4`, bit `15 − (x mod 16)`.
  In a layer, graphics shifts the pattern line by the layer's vertical offset and rotates the pattern
  word by its horizontal offset, so the grid follows the window, not the screen. (The SysInfo check
  below has its window at (0,0), so it confirms the phase but does not discriminate layer from
  screen origin; the layer case is ROM reading only, for the visible ClipRects; obscured
  ClipRects and SuperBitMap layers are assumed to behave the same [S].)

**When it is drawn** [O].
- At every rendering of the list (§6.2): OpenWindow, RefreshGadgets, RefreshWindowFrame/frame
  repair, requester drawing, screen title bar, one-off frame-gadget refreshes. A gadget whose
  GADGDISABLED is set by the application **before** OpenWindow (in the NewWindow list) is ghosted
  at the initial drawing.
- **OffGadget**(gad, win, req): sets GADGDISABLED, then redraws from `gad` to the **end** of the list
  (count −2: not just this gadget). The `req` argument is not used: for a requester gadget the
  requester is found from the gadget (see the note under §6.2, which also makes it redraw the whole
  requester list). The redraw does **not** erase first: the rendering is drawn again over what is
  there, then the dots.
- **OnGadget**(gad, win, req): clears GADGDISABLED, then the same redraw (count −2), still **without
  erasing the box**. The dots disappear only where the gadget rendering itself overwrites them: a
  full Image or a JAM2 text covers them, a Border (lines only) does not, so the dots stay between the
  lines of a Border gadget until the application clears the area and refreshes [D from the absence
  of any erase step in the path; not probed].
- **SELECTED disabled gadget**: the highlight pass (§6.1, step 2) does not test GADGDISABLED; a
  SELECTED gadget is highlighted (e.g. GADGHCOMP complements its box) **after** being ghosted, so the
  dots are complemented with the rest.
- **Hit test**: when the button goes down over a disabled gadget, the search stops on it and reports
  no gadget (a gadget behind it in the list is not reached).

**SysInfo 4.4 on the real ROM** [O, screenshot]. On a 68000, the main window (BORDERLESS backdrop
window at (0,0), 640×256 hires screen, Window BlockPen = 1) has six 64×10 boolean gadgets
(GADGHIMAGE, RELVERIFY) at (420/489/558, 176/188): ICACHE, DCACHE, IBURST, DBURST, CBACK, ALL. In
the live window their Flags are $0102 (GADGDISABLED set); in the program file the same structures
have $0002, and neither OffGadget nor OnGadget is called while SysInfo starts (hardware
breakpoints on both never fired, while the ghosting fill fired): SysInfo sets GADGDISABLED itself
before the gadgets are first drawn, and the ghosting comes from the ordinary list rendering. On
screen the six buttons show a regular grid of single pen-1 dots (white in SysInfo's palette) over
their grey/white/black imagery: every second line has a dot every 4 pixels, the lines between have
the same spacing shifted by 2 pixels; e.g. on line 177 dots at x = 423, 427, … 483 and on line 178 at
x = 421, 425, …, i.e. x mod 4 = 3 on odd lines and 1 on even lines, as the rule above gives for a
layer at (0,0). No dot appears outside x 420..483 / y 176..185 of the ICACHE box. The other buttons
(QUIT, MEMORY, …: Flags $0002) have no dots.

---

## 7. Test vectors

| Case | Expected |
|---|---|
| Non-GZZ window, gadget with BOTTOMBORDER at Top −10 GRELBOTTOM, Height 190 | BorderBottom ≥ 11; a single layer; BorderRPort = NULL |
| Info window (604×190, $146F, QUIT/SAVE/filler) | 2 layers; BorderBottom = 12; inner from (L+BL, T+BT) to (L+603−BR, T+177); GZZHeight = 190 − BT − 12; SAVE and QUIT visible on top of the filler |
| Click at 5,5 in the interior of a GZZ | IntuiMessage.MouseX = 5 + BorderLeft; Window.GZZMouseX = 5 |
| Non-GZZ gadget in a GZZ, LeftEdge 0 TopEdge 0 | drawn at the top-left corner of the inner area |
| Overlapping list A→B→C, RefreshGadgets(A) | drawing order C, B, A: A visible on top |
| AddGadget(win, g, −1) alone | nothing is drawn until a Refresh takes place |
| SizeWindow(±dx,±dy) on any window, IDCMP NEWSIZE\|REFRESHWINDOW | no NEWSIZE; one REFRESHWINDOW unless GZZ SUPER (§2.5) |
| SIMPLE non-GZZ 200×80, interior filled, SizeWindow(+40,+20) | whole window 0 except a complete new frame; Flags $0081; damage (0,0)-(239,99) |
| GZZ SUPER (NewWindow.BitMap 320×200×2), SizeWindow(+40,+20) | inner SuperBitMap = BitMap, inner Flags $0004, outer $0081→$0001; whole interior = SuperBitMap; no message |
| non-GZZ SUPER, SizeWindow(+40,+20) | Flags $0084, REFRESHWINDOW; frame redrawn only inside the damaged frame bands (§2.5) |
| SysInfo 4.4 on a 68000, main window at (0,0), BlockPen 1 | ICACHE box (420,176) 64×10, Flags $0102: pen-1 dots at x mod 4 = 3 on odd lines, x mod 4 = 1 on even lines, only inside x 420..483, y 176..185 (§6.4) |
| Disabled gadget, then OnGadget, Border rendering only | flag cleared, gadget and the rest of the list redrawn, box not erased: dots between the border lines remain [D] |

---

## Clean-room review

- [x] Only calculation rules (formulas on public fields), the order of layer
  creations, library calls (layers CreateUpfrontLayer −36, MoveLayerInFrontOf −168;
  graphics SetFont) and public constants (Flags, Activation, GadgetType, IDCMP). No
  instruction sequence copied.
- [x] §6: the drawing order is described as a rule (backwards, then highlighting
  forwards) with the table of callers. info.library's list is given by its order and
  its public calls (AddGadget −1, RefreshGadgets(FirstGadget)), without copied code.
- [x] **Correction of 2026-10-29**: removed the 13 ROM routine addresses from the header,
  replaced by the list of functions studied; body unchanged.
- [x] §6.4 (2026-11-02): ghosting described as a rule (pattern words, pens, rectangle, alignment, callers);
  public structure fields and library calls only (RectFill, InstallClipRegion, OnGadget/OffGadget LVOs); no
  instruction sequence and no ROM address. SysInfo figures are its own gadget data read from the live
  window and screen pixels from the emulator picture.
- [x] §2.5 (2026-11-01): black-box readback only (pixels, Flags, DamageList, IDCMP classes) from the
  author probe `tests/resize_probe.s`; no ROM code read for it.
