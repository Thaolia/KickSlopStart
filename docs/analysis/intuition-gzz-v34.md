# intuition-gzz-v34.md — window borders, layers and coordinates (GIMMEZEROZERO or not)

> ANALYSIS track ("dirty"). Source: ROM `assets/kick34005.A500`, module intuition 34.3
> (OpenWindow, border adjustment by gadgets, gadget context, system gadgets,
> mouse coordinates, IntuiMessage, rendering of a gadget list, window drawing, AddGadget;
> no ROM address, removed on 2026-10-29). Practical case: `libs/info.library` from `wb133.adf`.
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
   4. if **GADGDISABLED**, the ghosting pattern over its box.

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
