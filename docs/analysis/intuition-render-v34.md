# intuition-render-v34.md — SetWindowTitles, DrawBorder, DrawImage, PrintIText, IntuiTextLength (intuition 34.3)

> ANALYSIS track ("dirty"). Sources: reading of the intuition 34.3 routines behind the five LVOs below in the ROM
> `assets/kick34005.A500` (radare2; behaviour only, notes kept outside the repository), and **black-box calls on
> the real ROM** under Amiberry (A500 preset, cycle-exact, `--analysis` session `ar9a`, Workbench 1.3.3 disk),
> 2026-11-04. Method, as for `graphics-line-v34.md` and `graphics-text-v34.md`: the CPU was stopped by the debugger
> at an exec `Wait` of the **Workbench process** (user mode), registers and memory were set up, the public LVO was
> called with A6 = IntuitionBase through a return trampoline placed in RAM, and the result (registers, RastPort
> fields, BitMap planes, screen BitMap) was read back after `WaitBlit`. Test BitMaps and RastPorts were allocated
> with AllocMem/InitBitMap/InitRastPort in that context; the SetWindowTitles tests used a real window opened with
> OpenWindow on the Workbench screen. No program was written for this page; §8 describes the probe to write.
>
> **Legend**: **[O]** observed by calling the function on the real ROM · **[O ROM]** read in the ROM code
> (behaviour), not confirmed by a call · **[D]** deduced · **[S]** assumption · **[?]** uncertain.
> No ROM address, no instruction listing, no transcription of a routine, no glyph or pictogram image. The pixel
> diagrams in §7 are outputs of the real ROM on our own test inputs (lines, rectangles, our own image data); text
> results are given as bounding boxes and positions only.

Related pages: frame and title bar layout `intuition-frame-v34.md` (§2–§4; §3.2 corrected by this page, see §2.4);
screen title and ShowTitle `intuition-screens-v34.md` §3.2–§3.3; gadget list rendering (DrawImage/DrawBorder/
PrintIText per gadget) `intuition-gzz-v34.md` §6.1; prop knobs `intuition-prop-v34.md` §3.1; requester rendering
`intuition-requesters-v34.md` §2.3; menu extents through IntuiTextLength `intuition-input-menus-v34.md` §3.5;
the Workbench memory title and LoadWB's SetWindowTitles patch `workbench-task-v34.md` §6.2–§6.6; IBase locks
`intuition-misc-v34.md` §6; the graphics primitives these functions call: Move/Draw `graphics-line-v34.md`,
Text/TextLength/OpenFont/SetFont/SetSoftStyle `graphics-text-v34.md`, BltBitMapRastPort `graphics-blitter-v34.md`.

## 0. Summary for the implementer

| LVO | Function | Registers (1.3 `.fd`) | One-line V34 behaviour |
|---|---|---|---|
| −108 | `DrawBorder(rp, border, left, top)` | A0, A1, D0, D1 | Per Border: SetAPen/SetBPen/SetDrMd from the Border, Move to the first point, Count−1 Draws; points are offsets from (LeftEdge+left, TopEdge+top); Count is a **signed byte**; Mask forced to `$FF` while drawing; RastPort state restored at the end, **cp not restored** |
| −114 | `DrawImage(rp, image, left, top)` | A0, A1, D0, D1 | Per Image: a temporary BitMap of the **RastPort's depth** is built (picked planes from ImageData in order, others from an all-ones or all-zeros chip plane per PlaneOnOff) and copied with **BltBitMapRastPort, minterm `$C0`**; `Image.Depth` is **ignored**; rp Mask honoured; RastPort untouched |
| −216 | `PrintIText(rp, itext, left, top)` | A0, A1, D0, D1 | Per IntuiText: pens and mode from the IntuiText, optional font (OpenFont + SetFont + SetSoftStyle(ta_Style)), Move to (LeftEdge+left, TopEdge+top+**TxBaseline**), Text of the whole string; Mask forced `$FF`; state restored, **cp not restored** |
| −276 | `SetWindowTitles(win, title, screenTitle)` | A0, A1, A2 | title ≠ −1: Window.Title := title, the window's title bar redrawn (then veiled if inactive); screenTitle ≠ −1: Window.ScreenTitle := screenTitle and, **only if the window is active**, Screen.Title := screenTitle and the screen bar redrawn |
| −330 | `IntuiTextLength(itext)` | A0 | TextLength of the **first** IntuiText's string in a fresh RastPort (InitRastPort ⇒ GfxBase **DefaultFont**) or in its ITextFont; NextText, LeftEdge and styles ignored; D0 = pixels |

LVOs checked against the slot order of AROS `rom/intuition/intuition.conf` with the 30-byte bias (two private
`.skip` slots first): DrawBorder is slot 14 (−108), DrawImage 15 (−114), PrintIText 32 (−216), SetWindowTitles 42
(−276), IntuiTextLength 51 (−330). A6 must be IntuitionBase for all five: every one reaches graphics.library and
exec through IntuitionBase's own library pointers [O ROM].

Registers on return [O] (marker values in D0–D7/A0–A5): DrawBorder, DrawImage, PrintIText and SetWindowTitles
change only **D0, D1, A0, A1** (scratch values, no result); IntuiTextLength returns the width in **D0** and also
changes D1, A0, A1. D2–D7/A2–A6 are preserved by all five.

## 1. The RastPort state save/restore shared by DrawBorder, PrintIText and IntuiTextLength [O ROM][O]

DrawBorder, PrintIText (and IntuiTextLength on its private RastPort, and the title-bar drawing of §2) bracket
their work with the same pair of operations.

**Saved on entry**: rp_Font, AlgoStyle, TxFlags, TxHeight, TxWidth, TxBaseline, FgPen, BgPen, DrawMode, Mask and
rp_Layer. DrawBorder and PrintIText then set **Mask := `$FF`** before drawing.

**Restored on exit**, in this order: the six font fields by direct writes (no SetFont call), then **SetAPen(FgPen),
SetBPen(BgPen), SetDrMd(DrawMode)** through the graphics vectors, then Mask and rp_Layer by direct writes.

Consequences, all observed:
- Pens, DrawMode and Mask are back to their entry values (a caller that set JAM2 and its pens once keeps them —
  SysInfo relies on this, see project memory "RastPort intact after PrintIText").
- Because the pens are restored **through SetAPen/SetBPen/SetDrMd**, the RastPort leaves with **FRST_DOT set**
  (rp_Flags bit 0) and the line-pattern byte at RastPort +$1F reset to 15 (`graphics-line-v34.md` §2), even if
  they were different on entry. Observed on a window RastPort that had Flags `$0000` and +$1F `$00` on entry:
  `$0001` and `$0F` after PrintIText.
- **cp_x/cp_y are not restored**: after DrawBorder cp is the last point drawn (or the first point when nothing is
  drawn); after PrintIText cp is at the end of the last string, on its baseline.
- LinePtrn, AreaPtrn, the minterms and the other fields are not saved; DrawBorder does not change LinePtrn, so a
  line pattern set by the caller **is used** by DrawBorder (§7.1 DB7).
- DrawImage does **not** use this save/restore and changes nothing in the RastPort (§4).

## 2. SetWindowTitles (−276)

### 2.1 Contract [O ROM][O]

`SetWindowTitles(window A0, windowTitle A1, screenTitle A2)`. Each title is compared with **−1 as a full 32-bit
value** (`$FFFFFFFF`); NULL is a valid title (no text). The window pointer is not checked. No return value.
LoadWB 1.3.3 replaces this vector (`workbench-task-v34.md` §6.6); everything below is the ROM function.

Order of operations:
1. **Window title**, if windowTitle ≠ −1:
   - `Window.Title := windowTitle` (+$20);
   - the window's **title bar is redrawn** with the gadget refresh enabled (§2.2);
   - if the window is **not active** (Window.Flags bit 13, WINDOWACTIVE `$2000`, clear), the **inactivity veil**
     is applied over the title area (`intuition-frame-v34.md` §4.2).
2. **Screen title**, if screenTitle ≠ −1:
   - `Window.ScreenTitle := screenTitle` (+$68), whether the window is active or not;
   - **only if the window is active**: `Screen.Title := screenTitle` (+$16) and the **screen bar is redrawn**
     (§2.3). An inactive window's new screen title appears only when that window is next activated (activation
     copies Window.ScreenTitle to Screen.Title, `intuition-screens-v34.md` §3.3) [O].

Both parts are independent: `SetWindowTitles(w, −1, −1)` does nothing [O]. A NULL window title leaves the bar
without text (fill and drag pattern only); a NULL screen title leaves the screen bar filled without text (no
fallback to DefaultTitle) [O].

### 2.2 Title-bar redraw [O ROM][O]

Nothing at all is drawn when the window's **BorderTop is 0** (e.g. the Workbench backdrop window): the title
pointer is still stored [O ROM; observed: Title changed, nothing visible changes].

Otherwise:
1. **RastPort**: a single IntuitionBase RastPort, protected by **IBase lock 6**, is loaded with a copy of the
   **screen's RastPort** (screen font and its style) and attached to the frame layer (the GZZ border layer, or
   the window layer): the frame layer is locked (LockLayerRom), its **ClipRegion is removed** for the duration
   (InstallClipRegion NULL, the old one reinstalled afterwards), its Scroll_X/Scroll_Y are zeroed for the duration
   and restored, Mask is `$FF` and AreaPtrn NULL. So the title bar ignores any application clip region on a
   non-GZZ window [O ROM].
2. x0, x1 = start and end of the title area (`intuition-frame-v34.md` §3.1: x0 = 30 hires / 16 lores with a close
   gadget, else the screen's WBorLeft; x1 = W−54 hires / W−35 lores with depth gadgets, else W−1).
3. If x0 < x1: RectFill (x0, 0)–(x1, BT−2) in **BlockPen**, JAM2 (pens and mode set for the fill).
4. If Window.Title ≠ NULL: an IntuiText {FrontPen = **DetailPen**, BackPen = **BlockPen**, DrawMode **JAM2**,
   LeftEdge 0, TopEdge 0, ITextFont NULL, NextText NULL} is drawn with **PrintIText at (x0, 1)**; the current x
   becomes **x0 + width + 3**, the width being the TextLength of the title **in this RastPort** (screen font —
   not the GfxBase default font that the public IntuiTextLength uses, §6).
5. If WINDOWDRAG: the 8-line drag pattern from the current x to x1−3, rows 1..BT−3, APen DetailPen, BPen BlockPen,
   JAM1 (`intuition-frame-v34.md` §3.2). Without a title the pattern starts at **x0** (§2.4).
6. The RastPort is released (clip region, scroll and layer lock restored, lock 6 released).
7. Gadget refresh (SetWindowTitles always asks for it): under **LockLayerInfo of the screen's LayerInfo** and
   **IBase lock 2**, the window's gadget list (FirstGadget, system gadgets included) is walked and each gadget is
   refreshed individually when either:
   - its Activation has **TOPBORDER** (`$0040`), or
   - the title **overflowed**: x0 + width + 3 > x1, and the gadget is a depth gadget (GadgetType & `$F0` =
     `$40` WUPFRONT or `$60` WDOWNBACK).
   The text itself is **not clipped at x1**: a long title is drawn up to the layer's edge, over the depth
   gadgets, which are then redrawn on top [O: a 51-character title in a 300-pixel window leaves the two depth
   gadgets intact].

Afterwards, step 1 of §2.1 applies the veil when the window is inactive [O: title and drag lines dotted with
BlockPen one pixel in four after `SetWindowTitles(inactive, "Inactive", …)`].

### 2.3 Screen-bar redraw [O ROM][O]

Done only for the active window's screen title (§2.1 step 2). Skipped when the screen fails an internal
validity test (not identified [?]) or has **SCREENQUIET** (Screen.Flags `$0100`). Otherwise, under LockLayerInfo of the screen's LayerInfo, on the RastPort
of the screen's **BarLayer**:
1. RectFill (0, 0)–(Screen.Width−1, **BarHeight−1**) in the screen's **BlockPen**, JAM2 (observed: rows 0..9 for
   BarHeight 10; row 10 untouched);
2. if Screen.Title ≠ NULL: PrintIText of an IntuiText {FrontPen = screen **DetailPen**, BackPen = screen
   **BlockPen**, **JAM2**, LeftEdge = **BarHBorder**, TopEdge = **BarVBorder**, font NULL} at offset (0, 0), in
   the BarLayer RastPort's font (the screen font);
3. the **screen's** gadgets are refreshed (the whole list, with the same per-gadget routine as RefreshGList).

**ShowTitle** is not consulted: the bar is redrawn into the BarLayer whatever SHOWTITLE says; when the bar is
behind a backdrop window (ShowTitle FALSE) the drawing is clipped by the layers like any other [O ROM; observed
only on the Workbench screen, whose backdrop window starts below the bar, so the text stayed visible both ways —
see Open point 2]. ShowTitle(TRUE) later redraws the bar with the current Screen.Title (`intuition-screens-v34.md`
§3.2) [O].

### 2.4 Correction to intuition-frame-v34 §3.2 [O]

`intuition-frame-v34.md` §3.2 said "without a title, the pattern starts at x0 + 3". Measured on a hires window
(x0 = 30, x1 = 246, BT = 11): with title "Changed" (56 pixels) the drag lines span **x 89..243** (= x0 + 56 + 3 to
x1 − 3); with a NULL title they span **x 30..243**. The "+3" is added only together with the text width. The frame
page was corrected in the same session.

## 3. DrawBorder (−108) [O ROM][O]

`DrawBorder(rp A0, border A1, leftOffset D0, topOffset D1)`; offsets are taken as 32-bit values but only
sign-extended words matter in practice. Border layout (public `intuition.h`): LeftEdge W +0, TopEdge W +2,
FrontPen B +4, BackPen B +5, DrawMode B +6, **Count B +7 (signed)**, XY L +8, NextBorder L +12.

1. Save the RastPort state, Mask := `$FF` (§1).
2. For each Border of the NextBorder chain (stops at NULL; a NULL first border draws nothing):
   1. **SetAPen(FrontPen), SetBPen(BackPen), SetDrMd(DrawMode)** through the graphics vectors (each one resets
      the line-pattern byte to 15; DrawMode is passed as is, INVERSVID included);
   2. ox = LeftEdge + leftOffset, oy = TopEdge + topOffset;
   3. **Move(ox + XY[0].x, oy + XY[0].y)** — always, even when Count ≤ 1;
   4. **Count − 1 calls of Draw(ox + XY[i].x, oy + XY[i].y)**, i = 1.., while the remaining count is > 0. The
      XY pairs are **offsets from (ox, oy)**, not deltas from the previous point. Count is a **signed byte**:
      0, 1 and any value ≥ 128 (−128..−1) draw **nothing** but still move cp to the first point [O: Count 0, 1,
      129, 200].
3. Restore the RastPort state (§1).

The pixels are those of graphics `Move`/`Draw` (`graphics-line-v34.md`): both ends included, LinePtrn honoured
and continued from one segment to the next inside a Border (restarted at each Border by SetAPen), COMPLEMENT
shared vertices of a polyline inverted once (Draw's FRST_DOT rule), clipping by the layer if `rp_Layer` is set,
**no clipping** without a layer. Because Mask is forced to `$FF`, a pen is drawn in all its planes even if the
caller's Mask excluded some (observed: pen 2 drawn on plane 1 with rp Mask 1). No check of XY being non-NULL when
Count ≤ 1 (XY[0] is always read).

## 4. DrawImage (−114) [O ROM][O]

`DrawImage(rp A0, image A1, leftOffset D0, topOffset D1)`. Image layout (public): LeftEdge W +0, TopEdge W +2,
Width W +4, Height W +6, Depth W +8, ImageData L +10, PlanePick B +14, PlaneOnOff B +15, NextImage L +16.

For each Image of the NextImage chain (each one independent; a failure on one image does not stop the chain):

1. **Temporary BitMap**: BytesPerRow = ((Width + 15) / 16) × 2, Rows = Height, **Depth = the RastPort BitMap's
   depth** (`rp_BitMap->Depth`). The **Image.Depth field is never read** [O ROM; O: Depth 1 with PlanePick 5
   used two data planes; Depth 2 with PlanePick `$FF` on a 3-plane BitMap used three].
2. **Source planes**, for each destination plane p = 0..depth−1, in increasing order:
   - PlanePick bit p set ⇒ the **next ImageData plane**, taken in order: the k-th picked plane uses ImageData +
     k × (words per row × Height) × 2. Planes are consecutive, rows padded to a word. So with PlanePick = `%010`
     the **first** data plane goes to plane 1 [O];
   - otherwise PlaneOnOff bit p set ⇒ a plane of **all ones**;
   - otherwise ⇒ a plane of **all zeros**.
   Unpicked planes are therefore **written** (with 0 or 1), not left alone: an image drawn with PlanePick 3 /
   PlaneOnOff 0 on a 3-plane BitMap clears plane 2 under its rectangle [O]. PlanePick bits ≥ depth are ignored;
   a PlanePick bit set below depth with no matching data plane reads past the declared data.
3. **Fill planes**: when at least one of the depth planes is not picked, a zero plane (MEMF_CHIP|MEMF_CLEAR) is
   allocated — even if PlaneOnOff covers all unpicked planes — and, if PlaneOnOff ≠ 0, a ones plane (MEMF_CHIP,
   filled with `$FF` by the processor). Size of each = BytesPerRow × Height computed as a **16-bit unsigned
   product**. If an allocation fails (or the size is 0), **this image is not drawn** [O ROM; O: Width 0 with an
   unpicked plane draws nothing]. Both are freed after the copy.
4. **Copy**: `BltBitMapRastPort(temp, 0, 0, rp, LeftEdge + leftOffset, TopEdge + topOffset, Width, Height,
   $C0)` — a plain copy. Hence [O]:
   - **rp Mask is honoured** (planes whose Mask bit is 0 are not written; observed with Mask 1);
   - FgPen, BgPen and **DrawMode are ignored** (COMPLEMENT in the RastPort still copies);
   - clipping is BltBitMapRastPort's: by the layer's ClipRects when `rp_Layer` is set (observed: an image at
     x = −4 in a window RastPort is cut at the window's left edge, one at W−6 is cut at its right edge); no layer
     ⇒ no clipping (`graphics-blitter-v34.md`);
   - pixel columns of the data beyond Width are not drawn (observed with Width 20: 16 + 4 columns);
   - ImageData is read by the **blitter**: it must be in chip memory.
5. The RastPort is not modified at all: pens, mode, Mask, cp, Flags, pattern byte unchanged [O].

There is no other path: no BltTemplate, no processor drawing, no special case for PlanePick 0 (an image with
PlanePick 0 is a solid rectangle of colour PlaneOnOff, computed with the same temporary BitMap) [O ROM][O].

## 5. PrintIText (−216) [O ROM][O]

`PrintIText(rp A0, iText A1, leftOffset D0, topOffset D1)`. IntuiText layout (public): FrontPen B +0, BackPen B
+1, DrawMode B +2, LeftEdge W +4, TopEdge W +6, ITextFont L +8 (TextAttr), IText L +12, NextText L +16.

1. Save the RastPort state, Mask := `$FF` (§1).
2. For each IntuiText of the NextText chain:
   1. SetAPen(FrontPen), SetBPen(BackPen), SetDrMd(DrawMode);
   2. if **ITextFont ≠ NULL**: **OpenFont(ITextFont)** (memory fonts only, graphics OpenFont; no diskfont); if it
      succeeds: **SetFont(rp, font)** then **SetSoftStyle(rp, ta_Style, `$FF`)** — SetFont clears AlgoStyle, so
      the rp's own soft style is **replaced** by the TextAttr's style. If OpenFont fails, the RastPort's current
      font and AlgoStyle are used [O: "nosuch.font" drew in the current topaz 8];
   3. **Move(LeftEdge + leftOffset, TopEdge + topOffset + rp_TxBaseline)**, TxBaseline being read **after** the
      font change, i.e. that of the IntuiText's font: TopEdge is the **top** of the text cell [O: TopEdge 2 +
      offset 4 ⇒ JAM2 cell rows 6..13 with topaz 8; O ROM for the "after" order, topaz 8 and 9 both have
      baseline 6];
   4. if IText ≠ NULL: **Text(rp, IText, strlen(IText))** — the whole NUL-terminated string, one Text call;
      IText NULL ⇒ the Move only; an empty string ⇒ Text with count 0, nothing drawn [O];
   5. if a font was opened: **CloseFont** it, then **restore the saved state** (font fields, pens, mode, Mask,
      Layer, §1) — so the next IntuiText of the chain starts again from the caller's font and style.
3. Restore the RastPort state (§1).

Rendering is graphics Text's (`graphics-text-v34.md` §7): JAM1/JAM2/COMPLEMENT/INVERSVID as there; the JAM2
background covers the whole advance extent × font YSize; algorithmic styles come from the RastPort's AlgoStyle
when ITextFont is NULL (observed: a bold rp gives bold IntuiText) and from ta_Style otherwise (observed: italic
TextAttr on a bold rp gives italic, and the rp is back to bold afterwards). Because Mask is forced to `$FF`, the
pens are drawn in every plane whatever the caller's Mask [O]. **cp is left after the last string**, on its
baseline (observed `"AB"` from (4, 12): cp (20, 12)).

Without a layer there is no clipping, and graphics Text writes **outside the BitMap** for a negative destination
x — italic at x = 0 included (`graphics-text-v34.md` §7.6): observed again here, an italic IntuiText at x 0 on a
layerless BitMap drew nothing in it.

## 6. IntuiTextLength (−330) [O ROM][O]

`IntuiTextLength(iText A0)` → D0.

1. A RastPort on intuition's stack is initialised with **InitRastPort** (so its font is GfxBase's
   **DefaultFont**, the Preferences font — topaz 8 or 9 — and AlgoStyle 0).
2. Same font handling as PrintIText step 2.2 (OpenFont of ITextFont, SetFont, SetSoftStyle), on that RastPort.
3. **D0 = TextLength(rp, IText, strlen(IText))**, then CloseFont.

Consequences [O]:
- Only the **first** IntuiText is measured: **NextText is ignored**; LeftEdge/TopEdge are ignored; pens and modes
  do not matter.
- **ITextFont NULL ⇒ GfxBase DefaultFont**, not a screen or window font: "Hello" = 40 with DefaultFont topaz 8,
  and **50** after the test pointed GfxBase DefaultFont at topaz 9. A window title bar measures its title in the
  screen font instead (§2.2), so the two can differ when the screen font is not the default font.
- Styles do not change the result (TextLength ignores them): topaz 8 with ta_Style BOLD ⇒ 40.
- A font that cannot be opened ⇒ DefaultFont's width. Empty string ⇒ 0. OpenFont/CloseFont are balanced
  (accessor count unchanged afterwards).
- IText must not be NULL (its length is computed by scanning from the pointer) [O ROM].

## 7. Test vectors (real ROM, observed)

Diagrams: one line per y, one column per x from 0; `.` = colour 0, otherwise the colour number (plane 0 = bit 0).
Before each test the BitMap was filled (colour given), then SetAPen 3, SetBPen 0, SetDrMd JAM2 (DrawBorder,
DrawImage) or JAM1 (PrintIText), Mask `$FF` unless stated, and Move(40, 14) (DrawBorder) / (40, 10) (DrawImage) /
(50, 20) (PrintIText), so that "state after" can be compared.

### 7.1 DrawBorder (48 × 16 BitMap, 2 planes, no layer)

| # | Border (L, T, pens F/B, mode, Count, XY) and offsets | Result | cp after |
|---|---|---|---|
| DB1 | (2, 3) F1 B2 JAM1, Count 3, (0,0) (10,0) (10,5); offsets (4, 1); rp **Mask 1** | row 4 x 6..16 colour 1; column 16 rows 5..9 colour 1; rp after: Fg 3, Bg 0, JAM2, **Mask 1**, Flags `$0001`, +$1F = 15 | (16, 9) |
| DB2 | (2, 3) F2 JAM1, Count **0**, (5,5) (10,0) | nothing | (7, 8) |
| DB3 | same, Count **1** | nothing | (7, 8) |
| DB4 | (0, 0) F2, Count **200**, (1,1) (10,1) (10,8) | nothing | (1, 1) |
| DB4b | same, F3, Count **129** | nothing | (1, 1) |
| DB5 | box (1, 1) F3 JAM1 Count 5 (0,0) (20,0) (20,10) (0,10) (0,0), then NextBorder (0, 0) F1 **COMPLEMENT** Count 2 (0,6) (20,6); offsets (2, 0) | diagram below | (22, 6) |
| DB6 | (−2, 10) F1 JAM1 Count 2 (−3,−4) (30,−4); offsets (5, −1) | row 5 x 0..33 colour 1 | (33, 5) |
| DB7 | rp LinePtrn `$F0F0`; (0, 0) F1 B2 **JAM2** Count 3 (0,2) (40,2) (40,10) | row 2: x 0..40 = `1111 2222` repeated, x 40 = 1; column 40 rows 3..5 = 1, rows 6..9 = 2, row 10 = 1 (pattern continues across the vertex); LinePtrn still `$F0F0` after | (40, 10) |
| DB8 | (0, 0) F1 JAM2 Count 3, all three points (5,5) | single pixel (5, 5) colour 1 | (5, 5) |
| DB9 | (0, 0) F3 COMPLEMENT Count 3 (2,3) (20,3) (20,9) on colour 0 | row 3 x 2..20 colour 3, column 20 rows 4..9 colour 3 (shared vertex inverted once) | (20, 9) |
| DB10 | (0, 0) **F2** JAM1 Count 2 (0,2) (20,2); rp **Mask 1** | row 2 x 0..20 colour **2** (Mask forced `$FF`); rp Mask 1 after | (20, 2) |

DB5 (rows 0..12, columns 0..24):

```
 0 .........................
 1 ...333333333333333333333.
 2 ...3...................3.
 3 ...3...................3.
 4 ...3...................3.
 5 ...3...................3.
 6 ..3.33333333333333333333.
 7 ...3...................3.
 8 ...3...................3.
 9 ...3...................3.
10 ...3...................3.
11 ...333333333333333333333.
12 .........................
```

(The COMPLEMENT line x 2..22 inverts both planes: 0 → 3, the box side at x 3 → 0.)

### 7.2 DrawImage (48 × 12 BitMap, **3 planes**, no layer)

Image data (one word per row): P0 = `$F800 $8800 $F800`, P1 = `$2000 $7000 $2000`, P2 = `$FFFF $0000 $FFFF`.
Width 5, Height 3 unless stated. Results at rows 2..4, columns 3..7 unless stated.

| # | Image (Depth field, data planes, PlanePick, PlaneOnOff), fill | Rows 2..4 at x 3..7 |
|---|---|---|
| DI1 | Depth 2, P0 P1, pick 3, onoff 0, at L2 T1 + offsets (1,1); fill colour 7 | `11311` / `12221` / `11311` (plane 2 cleared in the rectangle, 7 elsewhere) |
| DI2 | Depth 2, P0 P1, pick 1, onoff 6; fill 0 | `77777` / `76667` / `77777` |
| DI3 | Width 7, Height 2, no data, pick 0, onoff 5 | rows 2..3, x 3..9 all `5` |
| DI4 | **Depth 1**, P0 P1, pick 5 | `11511` / `14441` / `11511` (P1 went to plane 2) |
| DI5 | **Depth 2**, P0 P1 P2, pick `$FF` | `55755` / `12221` / `55755` (a third plane read) |
| DI6 | Depth 2, P0 P1, pick 3, onoff 4, rp **Mask 1** | `11111` / `1...1` / `11111` (planes 1, 2 not written) |
| DI7 | chain: first image P1 P0 at L0, NextImage P0 P1 at **L10**; pick 3 | x 3..7: `22322` / `21112` / `22322`; x 13..17: `11311` / `12221` / `11311` |
| DI8 | Width **20**, Height 2, Depth 1, one plane `$AAAA $F000` / `$5555 $F000`, pick 1 | row 2 x 3..22: `1.1.1.1.1.1.1.1.1111`; row 3: `.1.1.1.1.1.1.1.11111` |
| DI9 | Width **0**, Depth 1, pick 1, onoff 2 | nothing |
| DI10 | Depth 1, P0, pick 0, onoff 0; fill 7 | rectangle x 3..7, rows 2..4 all `.` |
| DI11 | Depth 2, P0 P1, pick **2** | `22222` / `2...2` / `22222` (first data plane went to plane 1) |
| DI12 | Depth 1, P0, pick 1, rp DrawMode **COMPLEMENT** | `11111` / `1...1` / `11111` (mode ignored) |

In every case the RastPort was unchanged afterwards (pens, mode, Mask, cp (40, 10), Flags).

Window (layer) clipping, test window at screen (100, 40), 300 wide: a 10 × 4 solid image (pick 0, onoff 3) at
offset (−4, 20) in the window RastPort fills window x **0..5** of row 20 (cut at the window's left edge); a
solid onoff-2 image at (W−6, 30) fills x **294..299** (cut at the right edge).

### 7.3 PrintIText (64 × 24 BitMap, 2 planes, no layer, rp font topaz 8 = DefaultFont)

Results as bounding boxes of each colour (glyph images are not reproduced).

| # | IntuiText(s) and offsets | Result | cp after | rp after |
|---|---|---|---|---|
| PT1 | `"AB"` F1 B2 **JAM2**, L1 T2, font NULL, offsets (3, 4); rp Mask 1, JAM1, Fg 3 | colour-2 cell x 4..19, y 6..13; glyph pixels colour 1 inside x 4..18, y 6..12 | (20, 12) | Fg 3, Bg 0, JAM1, **Mask 1** |
| PT2a | `"B"` F3 JAM1 at L20, ITextFont **topaz 9** | glyph inside x 21..28, y 0..6 | (30, 6) (advance 10) | font back to topaz 8, TxHeight 8 |
| PT2 | chain `"A"` F1 font NULL at L0 → `"B"` F2 topaz 9 at L20 → `"C"` F3 font NULL at L40 | colour 1 in x 0..7, colour 2 in x 21..28, colour 3 in x 40..46, all y 0..6 | (48, 6) | topaz 8 |
| PT3a | `"MM"` F1 JAM1, rp AlgoStyle 0 | ink x 0..14, y 0..6, 64 pixels | (16, 6) | — |
| PT3b | same, rp AlgoStyle **BOLD** | ink x 0..**15**, 92 pixels (bold applied) | (16, 6) | AlgoStyle still BOLD |
| PT4 | `"MM"` with ITextFont `"nosuch.font"` 8 | same as PT3a (current font used) | (16, 6) | — |
| PT5 | IText **NULL**, L5 T3, offsets (2, 1) | nothing | (7, 10) (= Move to 7, 4 + baseline 6) | — |
| PT6 | `""` JAM2 at offsets (2, 1) | nothing | (2, 7) | — |
| PT7 | `"MM"` F1 B2 **COMPLEMENT** on colour 3 | exactly the 64 glyph pixels become colour 0 | (16, 6) | — |
| PT8 | `"MM"` F1 B2 **JAM2 \| INVERSVID** | glyph pixels colour 2 (64), rest of the 16 × 8 cell colour 1 (64) | (16, 6) | — |

In a window RastPort (layer): `"MM"` with ITextFont topaz 8 **italic** at (8, 40) on a rp with AlgoStyle 0: the
ink of the top row reaches 3 pixels further right than the plain text at (8, 60) (italic shift), cp (24, 46),
AlgoStyle 0 after; the RastPort's Flags went from `$0000` to `$0001` and its +$1F byte from 0 to 15 (§1).

All PrintIText calls: the five saved fields as on entry; cp **not** restored.

### 7.4 IntuiTextLength

| IntuiText | D0 |
|---|---|
| `"Hello"`, font NULL (DefaultFont topaz 8) | 40 |
| `"Hello"`, ITextFont topaz 9 | 50 |
| `"Hello"`, NextText → `"more text"` | 40 |
| `"Hello"`, ITextFont topaz 8 BOLD | 40 |
| `""` | 0 |
| `"Hello"`, ITextFont `"nosuch.font"` 8 | 40 |
| `"Hi"`, LeftEdge 77, TopEdge 9 | 16 |
| `"Hello"`, font NULL, after setting GfxBase DefaultFont to topaz 9 | 50 |

### 7.5 SetWindowTitles (Workbench screen, hires, BarHeight 10, BarVBorder 1, BarHBorder 5)

Test window: NewWindow (100, 40) 300 × 80, DetailPen 0, BlockPen 1, Flags `$100F` (SIZING, DRAG, DEPTH, CLOSE,
ACTIVATE), title `"Test window"`, WBENCHSCREEN. BT = 11, x0 = 30, x1 = 246.

| Step | Call | Window.Title / Window.ScreenTitle | Screen.Title | Visible |
|---|---|---|---|---|
| open | OpenWindow (ACTIVATE) | "Test window" / DefaultTitle | "Workbench Screen" (was the WB memory title) | — |
| A1 | (w, "Changed", −1), active | "Changed" / unchanged | unchanged | title from x 30; drag lines rows 2–3 and 6–7, **x 89..243** |
| A2 | (w, −1, "Screen T"), active | unchanged / "Screen T" | "Screen T" | bar rows 0..9 BlockPen with the text; row 10 untouched |
| A3 | (w, −1, NULL), active | / NULL | NULL | bar filled, no text |
| A4 | (w, NULL, −1), active | NULL / | unchanged | drag lines **x 30..243** |
| A5 | (w, 51-char title, "Back") | long / "Back" | "Back" | title runs under the depth gadgets, which are redrawn intact |
| A6 | (w, −1, −1) | unchanged | unchanged | nothing |
| B1 | after ActivateWindow(backdrop) (deferred, took effect once the emulator ran): (w, "Inactive", "Scr2") | "Inactive" / "Scr2" | **unchanged** (WB memory title) | title drawn then veiled (BlockPen dots one pixel in four on the title and drag lines) |
| B2 | backdrop window (BT 0): (wb, "X", −1) | "X" / | unchanged | nothing drawn |
| — | ActivateWindow(w) then run | — | **"Scr2"** | bar shows Scr2 |

Screen bar with ShowTitle(FALSE) then `(wb, −1, "Hidden T")` on the active backdrop: Screen.Title = "Hidden T",
Screen.Flags `$0011` → `$0001` (SHOWTITLE clear), the bar bitmap rows 0..9 hold the new text (nothing covers the
bar on that screen); ShowTitle(TRUE) leaves the same text (Flags `$0011`).

Registers: D0, D1, A0, A1 changed; A2 (the screen title) preserved.

## 8. Probe to write (implementation side): `tests/irender_probe.s` + `.sh`

Modelled on `tests/gline_probe.s/.sh` and `tests/gtext_probe.s/.sh`: a HUNK executable started from the
startup-sequence of a floppy built with xdftool, results on the serial port (`RawPutChar`-style output as the
existing probes do), final marker `IRP fin`. All calls through the public LVOs: A6 = IntuitionBase for the five
functions under test (and OpenWindow, CloseWindow, ActivateWindow −450, ShowTitle −282), GfxBase for InitBitMap,
InitRastPort, SetAPen/SetBPen/SetDrMd, Move, SetSoftStyle, OpenFont/CloseFont, WaitBlit, BltClear.

**Setup**: one chip block for a 3-plane 64 × 32 BitMap (BytesPerRow 8) between two 512-byte guards; InitBitMap,
InitRastPort, `rp_BitMap` set. Before each test: WaitBlit, fill the planes with the stated colour, SetAPen 3,
SetBPen 0, SetDrMd (JAM2 for borders/images, JAM1 for texts), Mask `$FF` (or as stated), Move(40, 14). Per test,
print one header line: test id, `Fg Bg DrMd Mask cp_x cp_y Flags byte+$1F Font AlgoStyle` after the call, then the
rows that §7 lists (as `plane0 plane1 plane2` 8-byte hex rows, offline comparison like garea), and for text tests
only the per-colour bounding box and pixel count (computed by the probe) — **never** dump glyph rows.

**Tests** (expected values = §7):
1. **R0 registers**: call each of the five LVOs with markers `$1111000n` in D2–D7/A2–A5 (and the arguments in
   their registers); print which registers changed (expect only D0, D1, A0, A1; IntuiTextLength D0 = result).
2. **R1 DrawBorder**: DB1–DB10 of §7.1 on a 2-plane BitMap of 48 × 16 (or the 64 × 32 one, coordinates
   unchanged); for DB1 and DB10 set Mask 1 before; for DB7 set LinePtrn `$F0F0` and print it after.
3. **R2 DrawImage**: DI1–DI12 of §7.2 on the 3-plane BitMap, image data in chip memory (AllocMem MEMF_CHIP); then
   AvailMem(MEMF_CHIP) before/after a DrawImage to check that nothing leaks.
4. **R3 PrintIText**: PT1–PT8 of §7.3 (TextAttr `topaz.font` 9 and `nosuch.font` 8 built in the probe); print
   the bounding boxes and cp. Also a chain where the second IntuiText has ITextFont: print rp_Font, TxHeight,
   AlgoStyle after. **Do not** draw italic or at a negative x on the layerless BitMap (§5).
5. **R4 IntuiTextLength**: the eight rows of §7.4; print `GfxBase->DefaultFont->tf_YSize` first, because the
   NULL-font result follows it (40 for topaz 8, 50 for topaz 9; the real 1.3 without system-configuration has
   topaz 9, `graphics-text-v34.md` §11). For the last row, swap GfxBase DefaultFont (offset `$9A`) under Forbid
   and restore it.
6. **R5 SetWindowTitles**: open the §7.5 window on the Workbench screen (or on a custom hires screen opened by the
   probe, to be independent of LoadWB's patch — LoadWB 1.3.3 replaces −276, and its patch rewrites some screen
   titles, `workbench-task-v34.md` §6.6). For A1–A6 print Window.Title, Window.ScreenTitle, Screen.Title as
   strings or `NULL`, and read back from the screen BitMap the colour runs of title-bar rows 2 and 6 between x0
   and x1 (expect the drag lines at 89..243 for "Changed", 30..243 for NULL). For B1: ActivateWindow another
   window, Delay(25), check `Window.Flags & $2000` = 0, then SetWindowTitles and print the three titles; then
   ActivateWindow the test window, Delay(25), print Screen.Title (expect "Scr2"). Close the window, CloseScreen.
7. **R6 clipping in a layer**: in the test window RastPort, DrawImage of a 10 × 4 solid image at (−4, 20) and at
   (Width−6, 30); print the colour runs of those window rows read from the screen BitMap (expect x 0..5 and
   294..299 for a 300-pixel window).

## Open points

1. **ShowTitle(FALSE) with a backdrop window covering the bar** (a custom screen with a backdrop window from
   y = 0): the bar redraw should then be clipped away and appear only at ShowTitle(TRUE) [O ROM, not observed —
   the Workbench backdrop window starts below the bar].
2. **DrawImage when every plane is picked and Width or Height is 0**: no fill plane is allocated, so the copy is
   requested with a zero size; what BltBitMapRastPort does then was not observed.
3. **PlanePick bits beyond the BitMap's depth with fewer data planes than picked bits** read past the data
   (deduced from DI5); a compatible clone may do the same or stop at Image.Depth — no known program depends on
   it [S].
4. **SetWindowTitles on a window being closed or on a window of a hidden (SCREENQUIET) screen**: only the
   validity tests named in §2.2–§2.3 were read; not observed.
5. **TxBaseline after the font change** (§5 step 3): read in the ROM; the two ROM fonts both have baseline 6, so
   no call could tell "before" from "after". A probe with a disk font of another baseline would settle it.
6. The observations were made by debugger-injected calls in the Workbench process; the probe of §8 run from a
   CLI process should give the same figures but has not been run.

## Clean-room review

Review of 2026-11-04.

- [x] No 68000 instruction sequence transcribed or paraphrased, no disassembly excerpt, no ROM routine or data
  address. Numbers are public LVOs and structure offsets (`intuition.h`, `rastport.h`, `gfxbase.h`), flag values,
  IntuitionBase lock numbers already documented in `intuition-misc-v34.md`, the Screen/Window field offsets used
  in other specs, and coordinates in our own test BitMaps and windows.
- [x] The orders of operations of §1–§6 are stated as observable effects (calls made, fields written, what is
  restored), not as a routine transcription.
- [x] The diagrams and tables of §7 are outputs of the real ROM on our test inputs; the image data words are ours.
  Text results are bounding boxes, counts and positions only: no glyph of the ROM fonts is reproduced, and no
  system pictogram or fill pattern image.
- [x] No probe code was written by the analysis track; §8 describes one in words.
