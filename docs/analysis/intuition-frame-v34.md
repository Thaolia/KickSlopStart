# intuition-frame-v34.md — window frame, system gadgets, screen bar (intuition 34.3)

> ANALYSIS track ("dirty"). Source: ROM `assets/kick34005.A500`, intuition 34.3. Functions covered:
> drawing of the frame, title bar and its limits, activation, deactivation, outline, pattern
> fill, filled rectangle, patterns kept in IntuitionBase, system gadget templates (8 per
> resolution), screen bar. No ROM address (removed on 2026-10-29).
>
> **Legend**: **[O]** observed · **[D]** deduced · **[S]** assumed. No instruction sequence
> is reproduced, and **no bitmap image is transcribed**: the pictograms are described
> geometrically, so as to be redrawn.
>
> Notation: W, H = Width, Height of the window; BL, BT, BR, BB = borders (computation in
> `intuition-gzz-v34.md` §1); DP, BP = DetailPen (+$62) and BlockPen (+$63) of the window.
> The colours cited are **pen numbers**; on the WB 1.3 screen: 0 blue, 1 white,
> 2 black, 3 orange. A WB window has DP = 0 and BP = 1.

---

## 1. RastPort and layer of the frame [O]

- **Layer**: that of the frame if the window is GZZ (`BorderRPort->Layer`), otherwise WLayer.
- **RastPort**: a clone of the **screen's RastPort** (screen font) attached to this layer,
  with Mask $FF.

## 2. Complete drawing of the frame (OpenWindow, RefreshWindowFrame, repair) [O]

Order:

1. **Clearing of the borders in pen 0 (JAM1)**, by RectFill:
   - left: (0, 0)–(BL−1, H−1), if BL > 0;
   - right: (W−BR, 0)–(W−1, H−1), if BR > 0;
   - bottom: (0, H−BB)–(W−1, H−1), if BB > 0.
   The top border is **not** cleared here.
2. **Outline**, if the window is not BORDERLESS, in **BP**, JAM1:
   - **vertical strokes BL/2 pixels thick** against the left **and right** edges (the
     same thickness on both sides, computed from **BorderLeft**), over the full height;
   - **1-pixel horizontal strokes** on the first line (y = 0) and the last (y = H−1),
     between the vertical strokes.
   - **Consequence**: the right border contains BP on only BL/2 columns. The rest of BR
     stays at **pen 0**. With the sizing gadget on the right, BR is 18 in hires, but only a
     BL/2-pixel rule (2 pixels on the WB screen) is in BP: the border **looks thin** and
     the rest is blue. Same rule for the bottom border: only line H−1 is in BP.
3. **Background of the title bar**, if BT > 0: RectFill **(0, 0)–(W−1, BT−2) in BP**.
   - Line **y = BT−1 is not painted**. It keeps the layer's background (pen 0) and forms
     the rule under the bar [D].
4. **Contents of the title bar** (§3).
5. **All the window's gadgets**, system gadgets included, drawn in reverse order (see
   `intuition-gzz-v34.md` §6): the first in the list is drawn last.
6. **If the window is NOT active**: application of the **inactivity veil** (§4.2).

## 3. Title bar [O]

### 3.1 Geometry

- **Height**: BT = the screen's WBorTop + `Screen->Font->ta_YSize` + 1 (as soon as the window has
  DRAG, DEPTH, CLOSE or a title).
  - System gadgets have a **height of 10**;
  - the background is painted down to BT−2.
- **Start of the title area** (x0):
  - with CLOSEGADGET: **30** in hires, **16** in lores;
  - otherwise: the screen's **WBorLeft**.
- **End of the title area** (x1):
  - with DEPTHGADGET: **W − 54** in hires, **W − 35** in lores;
  - otherwise: **W − 1**.

### 3.2 Contents, in order

1. If x0 < x1: RectFill (x0, 0)–(x1, BT−2) in **BP**.
2. **Title** (Window.Title ≠ NULL):
   - IntuiText **FrontPen = DP, BackPen = BP, JAM2**, screen font (ITextFont NULL), placed
     at **(x0, 1)**;
   - the current position then advances by **text width + 3**:
     `x = x0 + TextLength(title) + 3`.
3. **Drag pattern**, only if the window has **WINDOWDRAG**:
   - RectFill from (x, 1) to (x1 − 3, BT − 3) with a **fill pattern** of **8 lines**,
     APen = **DP**, BPen = BP, **JAM1**;
   - the pattern, indexed by y modulo 8: lines **0, 1, 4, 5 empty**; lines **2, 3, 6, 7
     full**;
   - the "empty" pixels are not touched (JAM1): they keep the background BP.
   - **Result for BT = 11** (topaz 8, WBorTop 2): two **double horizontal lines in DP**
     at lines **y = 2–3 and y = 6–7**, from the end of the title up to x1 − 3.
   - Without a title, the pattern starts at x0 + 3, since the text width is 0.
   - Nothing is drawn if the area is empty (x > x1−3 or BT−3 < 1).

## 4. Active or inactive window [O]

### 4.1 Activation (ActivateWindow, click…)

1. The old active window is deactivated (§4.2) and receives **INACTIVEWINDOW**.
2. The new window receives the **WINDOWACTIVE ($2000)** flag and **ACTIVEWINDOW**.
3. If it has a title or DRAG: **the title bar is redrawn** (§3.2), which erases the
   veil. Also refreshed, one by one:
   - the gadgets whose Activation contains **TOPBORDER ($40)**;
   - the two depth gadgets, if the title overflowed onto their area.

### 4.2 Deactivation

- **WINDOWACTIVE is cleared**.
- If the window has a title or DRAG: **veil** = RectFill from **(x0, 1) to (x1, BT−3)** with a
  **4-line pattern**, APen = **BP**, **JAM1**. Each line of the pattern lights only **one pixel
  in four**, and the dot is shifted from one line to the next (two alternating shifts).
  - **Effect**: the pixels of the title and of the double lines are partially repainted in BP. The
    title and the pattern appear **dithered or faded**.
  - The background, the borders and the gadgets do not change.
- **The frame has no other difference between active and inactive**: same pens, same strokes,
  same gadgets.

## 5. System gadgets [O]

### 5.1 Creation and order

They are created according to the window's Flags, from the templates of the screen's
resolution (**hires** if `ViewPort.Modes` has $8000, otherwise lores). Order in the list, at the head, before
the application's gadgets:

| # | Gadget | Condition | Type |
|---|---|---|---|
| 1 | "front" depth (WUPFRONT) | WINDOWDEPTH | $8040 |
| 2 | "back" depth (WDOWNBACK) | WINDOWDEPTH | $8060 |
| 3 | sizing (SIZING) | WINDOWSIZING | $8010 |
| 4 | close (CLOSE) | WINDOWCLOSE | $8080 |
| 5 | drag (WDRAGGING) | WINDOWDRAG | $8020 |

- Drawing in reverse order: drag (nothing to draw), then close, sizing, back, and
  **front last**.
- A GZZ window gets the GZZGADGET bit on each of them.
- **Highlighting**: all are **GADGHCOMP** (bits 0–1 of the Flags at 0), without SelectRender. The
  click **inverts** the gadget's box, not the image. Only the drag gadget is **GADGHNONE**.
- The **images are drawn with PlanePick = 3 and PlaneOnOff = 0**, on 2 planes. The
  **colours are therefore fixed** (pens 0, 1, 2), **independent of DP/BP**. Exception:
  the hires image of the sizing gadget has only one plane (PlanePick = 1); its lit pixels are in
  pen 1, the others in pen 0.
- There is **no active/inactive difference** in the images.

### 5.2 Positions and sizes

| Gadget | Hires: box (relative to) | Hires: image | Lores: box | Lores: image |
|---|---|---|---|---|
| Front | x = W−29, y = 0, 26×10 (GRELRIGHT, LeftEdge −28) | 29×10 at (0,0) of the gadget, up to the right edge | x = W−17, 17×10 | 17×10 |
| Back | x = W−53, y = 0, 24×10 (LeftEdge −52) | 24×10 | x = W−34, 17×10 | 17×10 |
| Sizing | x = W−16, y = H−9, 16×9 (GRELRIGHT and GRELBOTTOM, −15/−8) | 16×9, **1 plane** | x = W−11, y = H−10, 11×10 | 11×10, 2 planes |
| Close | gadget x = 4, y = 0, 24×10; **image offset by −4**, hence at x = 0 | 28×10 | x = 0, 14×10 | 14×10 |
| Drag | x = 0, y = 0, width W + 0 (GRELWIDTH), height 10, no image | — | same | — |

### 5.3 Geometry of the pictograms (to redraw them)

Background = **pen 1 (white)** unless stated. "Stroke" = line 1 pixel high, or 2 pixels
wide for a vertical upright in hires (1 pixel in lores).

**"Front" depth** (29×10 hires / 17×10 lores):
- **2 columns of pen 0** on the left (separation band), the rest with background 1 over the full
  height;
- a **filled "back" square in pen 2 (black)**, at the top left of the useful area:
  - hires: x 4–7, y 1–6, extended by line y = 1 up to x = 17;
  - lores: x 4–10 on line 1, columns 4–7 over y 1–6.
- **In front of it**, a **hollow white square**: outline in **pen 0 (blue)** 2 pixels wide
  on the uprights, its sides being:
  - hires: x 8–21, y 2–8;
  - lores: x 8–14, y 2–8.
  Its interior stays white and hides part of the black square, which only sticks out at the top and on
  the left. The blue square is therefore "in front of" the black one.
- **Hires only**: a **vertical band of pen 0, 2 pixels** (x 24–25) over the full
  height, to the right of the pictogram, then 3 columns of background 1 up to the edge. In lores, the right
  edge is directly background 1.

**"Back" depth** (24×10 hires / 17×10 lores):
- 2 columns of pen 0 on the left, then background 1;
- a **hollow square in pen 0** at the top left:
  - hires: outline x 4–17, y 1–6, uprights 2 pixels wide;
  - lores: x 4–10, y 1–6.
- **In front of it**, at the bottom right, a **filled rectangle in pen 2 (black)**:
  - hires: x 8–21, y 3–8;
  - lores: x 8–14, y 3–8.
  It covers the bottom-right corner of the hollow square. The **black** square **is in front**.

**Close** (28×10 hires / 14×10 lores):
- hires: 4 columns of background 1, then a band of pen 0, 2 pixels wide (x 4–5), over the full
  height, then the pictogram, then 2 columns of background 1 (x 24–25) and 2 of pen 0 (x 26–27);
- **pictogram**: a **hollow frame in pen 0** (x 8–23, y 1–8 in hires; x 2–11, y 1–8 in
  lores), with a white interior, containing in the centre a **small filled square in pen 2 (black)**:
  - hires: x 14–17, y 4–5;
  - lores: x 6–7, y 4–5.
  Between the frame and the square, a ring of background 1.

**Hires sizing** (16×9, 1 plane: lit = pen 1, unlit = pen 0):
- background **pen 1**;
- two overlapping **hollow rectangles in pen 0**:
  - a **small** one at the top left (x 2–7, y 1–3);
  - a **large** one at the bottom right (x 6–13, y 3–7);
  - their strokes are **2 pixels** wide on the uprights and 1 pixel horizontally.
- These are the corners of a "small" window and a "large" window.

**Lores sizing** (11×10, 2 planes):
- background pen 1;
- a **small filled square in pen 2** at the top left (x 2–4, y 1–3);
- a **large filled rectangle in pen 2** at the bottom right (x 5–8, y 4–8).
- The two squares touch at a corner.

## 6. Screen title bar [O]

It is drawn in the screen's **BarLayer** (Screen +$14E), under LockLayerInfo.
- **Background**: RectFill **(0, 0)–(Screen.Width−1, BarHeight−1)** in the **screen's BlockPen**
  (Screen +$14B).
- **Title** (Screen.Title, +$16):
  - IntuiText **FrontPen = screen's DetailPen** (+$14A), **BackPen = BlockPen**, **JAM2**,
    screen font;
  - placed at **(BarHBorder, BarVBorder)**, i.e. Screen +$20 and +$1F.
- **No line pattern** on the screen bar, and no veil.
- **Screen gadgets** (list Screen +$146), drawn in reverse order:
  - **screen front and back depth** (types $C050 and $C070), with **the same images and
    the same positions relative to the right edge** as the window depth gadgets
    (table §5.2, replacing W with the screen width);
  - **screen drag** ($C030), without image.
- Nothing is drawn for a SCREENQUIET screen (bit $100 of Screen.Flags).

## 7. Summary of the differences with our rendering [D]

1. **Right border**: only the outer BL/2 columns are in BP; the rest of BR is at
   pen 0. The drawing is not a fill of the whole border.
2. **Bottom border**: only line H−1 is in BP.
3. **Drag pattern**: DP double lines at lines y ≡ 2, 3 (mod 4) of the bar, from the
   end of the title + 3 up to x1 − 3, only with WINDOWDRAG.
4. **Inactive**: BP dithering of one pixel in four over the title area, no change of
   background colour.
5. **Gadgets**: fixed-colour pictograms, positions of §5.2, highlighting by inverting
   the box.

---

## Clean-room review

- [x] No copied instruction sequence: only drawing rules (rectangles, strokes,
  pens, order), positions relative to public fields (Window, Screen) and constants
  (Flags, gadget types).
- [x] **No bitmap transcribed**: the system pictograms are described geometrically (areas,
  rectangles, thicknesses, colours), to be redrawn freely. The two fill patterns
  are described by their effect (full or empty lines, one pixel in four), not as
  word arrays.
- [x] **Correction of 2026-10-29**: removed the 12 addresses of ROM routines/data from the header.
  The geometry of the pictograms (§5.3, inventoried data of type (ii) in
  `docs/audit/specs-review.md`) was not modified (decision of the person in charge).
