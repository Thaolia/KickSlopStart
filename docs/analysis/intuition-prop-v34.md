# intuition-prop-v34.md — proportional gadgets (intuition 34.3)

> ANALYSIS track ("dirty"). Source: ROM `assets/kick34005.A500`, intuition 34.3. Functions covered: container borders
> at opening, box and container, gadget preparation, knob size and position, page step and
> page jump, dragging, clamping, knob redraw, rendering, KNOBHIT test, ModifyProp /
> NewModifyProp. No ROM addresses (removed on 2026-10-29).
>
> **Legend**: **[O]** observed · **[D]** deduced · **[S]** assumed. Rules and layouts
> only, no instruction sequence copied.

---

## 1. `struct PropInfo` (V34) — 22 bytes [O]

| Off. | Field | Written by intuition? |
|---|---|---|
| +$00 | Flags (UWORD) | KNOBHIT ($0100) only |
| +$02 | HorizPot | yes, during dragging and on page jump |
| +$04 | VertPot | same |
| +$06 | HorizBody | no (application, or ModifyProp) |
| +$08 | VertBody | no |
| +$0A | CWidth | **yes**: container width, at each preparation |
| +$0C | CHeight | **yes**: container height |
| +$0E | HPotRes | **yes**: horizontal page step (§3.3) |
| +$10 | VPotRes | **yes**: vertical page step |
| +$12 | LeftBorder | **yes**: when the gadget is added to the window |
| +$14 | TopBorder | **yes**: same |

Flags bits: **AUTOKNOB $0001**, **FREEHORIZ $0002**, **FREEVERT $0004**, **PROPBORDERLESS
$0008**, **KNOBHIT $0100** (set and cleared by intuition).

**LeftBorder / TopBorder**: set when the gadget enters a window, at OpenWindow and at
AddGadget.
- PROPBORDERLESS ⇒ 0 / 0.
- Otherwise ⇒ **the screen's WBorLeft / WBorTop** (Screen +$24 / +$23).
- Values set by the application are **overwritten**.

## 2. Geometry [O]

### 2.1 Box and container

- **Gadget box**: the usual box (LeftEdge/TopEdge/Width/Height with GRELxxx in the
  domain, see `intuition-gzz-v34.md` §4).
- **Container**: the box shrunk by **LeftBorder on the left and on the right**, and by **TopBorder at
  the top and at the bottom**:
  `CL = L + LB, CT = T + TB, CW = W − 2·LB, CH = H − 2·TB`.
  CWidth and CHeight receive CW and CH.

### 2.2 Knob size

It is computed only for **AUTOKNOB**. Without AUTOKNOB, the size of the Image supplied
in GadgetRender is used.
- **FREEHORIZ**: `kw = (HorizBody × CW) >> 16, plus 1`, clamped to **at least 6** and **at most
  CW**, then to at least 1.
- Without FREEHORIZ: **kw = CW**, and the knob sits at the left (x = 0).
- **FREEVERT**: `kh = (VertBody × CH) >> 16, plus 1`, clamped to **at least 4** and **at most CH**,
  then to at least 1.
- Without FREEVERT: **kh = CH**, y = 0.
- These values are **written into the GadgetRender Image**: Width (+$04) and Height (+$06). For
  AUTOKNOB, the application supplies an empty `struct Image` that intuition fills in.

### 2.3 Knob position (relative to the container)

- FREEHORIZ: `kx = ((CW − kw) × (HorizPot + 1)) >> 16`.
- FREEVERT: `ky = ((CH − kh) × (VertPot + 1)) >> 16`.
- Result **written into LeftEdge/TopEdge (+$00/+$02) of the GadgetRender Image**, and also into
  that of **SelectRender** if it exists.
- On-screen position = container corner + (kx, ky).

### 2.4 Inverse (dragging)

During a drag, the knob position follows the mouse, **clamped to the container**. The Pots are
then recomputed:
- `HorizPot = (kx << 16) / (CW − kw)`, **clamped to 0..$FFFF**; if CW = kw ⇒ **$FFFF**;
- same rule for VertPot with CH, kh, ky.
- Only the FREEHORIZ and FREEVERT axes are modified.

## 3. Rendering [O]

### 3.1 Full drawing (refresh of a proportional gadget)

Order:
1. **RectFill of the whole gadget box** in **the window's DetailPen** (JAM2). For a
   WB window, this is pen 0.
2. **Frame**, unless PROPBORDERLESS: outline of the **box** (not the container) in **BlockPen**,
   JAM1. Vertical strokes of **WBorLeft/2** pixels, horizontal strokes of **WBorTop/2** pixels.
   It therefore lies within the LeftBorder/TopBorder margin.
3. **Knob**:
   - **AUTOKNOB**: **filled rectangle** (kx, ky, kw, kh) in **BlockPen**. If the gadget is
     SELECTED **and** KNOBHIT is set, the pen is **inverted** (complement of the pen number).
   - **Supplied Image**: DrawImage of GadgetRender at (kx, ky), or of SelectRender if SELECTED
     + KNOBHIT + GADGHIMAGE and SelectRender exists. With SELECTED + KNOBHIT + GADGHCOMP, the
     knob box is then **inverted**.
4. Text (GadgetText) and GADGDISABLED ghosting, as for any gadget.

### 3.2 Knob movement

- Nothing is redrawn if the position does not change.
- Otherwise, the new knob is drawn, then **the parts of the old rectangle not covered**
  by the new one are **filled in DetailPen** (the background colour).
- The frame is not redrawn.

### 3.3 Page step (HPotRes / VPotRes)

`step(Body) = $FFFF` if Body ≥ $8000, otherwise `(Body << 16) / ($FFFF − Body)`.

## 4. Interaction [O unless stated]

1. **Click in the gadget box**, the point having to be in the **container**:
   - if the point is in the **enlarged knob** (knob grown by LeftBorder on each side and by
     TopBorder at the top and at the bottom) ⇒ **KNOBHIT set**;
   - otherwise ⇒ KNOBHIT cleared.
2. **Outside the knob** (page jump), for each free axis:
   - **Pot += sign × step(Body)**, clamped to 0..$FFFF;
   - the sign comes from the click position relative to the knob: before ⇒ −1, after ⇒ +1, on
     the axis ⇒ 0;
   - then the knob is recomputed (§2.3) and redrawn (§3.2).
   - **A single jump per click**: no repeat while the button stays pressed [O, no
     loop on this path].
3. **On the knob** (dragging): on each mouse movement, new position = previous
   position + displacement, clamped to the container. The Pots are recomputed (§2.4) and the knob is
   redrawn (§3.2).
4. **Messages**:
   - GADGETDOWN on click if **GADGIMMEDIATE**;
   - during the drag, MOUSEMOVE if **FOLLOWMOUSE** (IAddress = the gadget, like the other
     gadget MOUSEMOVEs) [D];
   - **GADGETUP on release if RELVERIFY**, IAddress = the gadget.
   - The Pots are **up to date in PropInfo** at the time of these messages.

## 5. ModifyProp (−156) and NewModifyProp (−468) [O]

- **NewModifyProp exists** in intuition 34.3 (vector −468).
- `ModifyProp(gad, win, req, Flags, HPot, VPot, HBody, VBody)`:
  - writes **Flags, HorizPot, VertPot, HorizBody, VertBody** into the PropInfo;
  - recomputes and **redraws from this gadget to the end of the list** (count −2).
    All the following gadgets are therefore redrawn too: this is the 1.x behaviour.
- `NewModifyProp(…, NumGad)`: same thing, but only redraws **NumGad** gadgets starting from
  `gad`. NumGad = 1 ⇒ only this gadget.
- The redraw goes through preparation (§2: CWidth, CHeight, PotRes, knob), then through full
  rendering (§3.1), frame included.
- The `req` parameter is not used directly: a requester gadget is recognised by its
  REQGADGET type.

---

## Clean-room review

- [x] No instruction sequence copied: formulas on public fields (PropInfo, Image,
  Gadget, Screen), drawing order, pens and constants.
- [x] No bitmap.
- [x] **Correction of 2026-10-29**: removed the header "Landmarks" block (17 ROM routine
  addresses), replaced by the list of functions covered; body unchanged.
