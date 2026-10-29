# wb-icon-clipping-v34.md — workbench.task 34.1: icon clipping, erasing and scrolling

> ANALYSIS track ("dirty"). Source: ROM `assets/kick34005.A500`, module `workbench.task`
> (`wb 34.1`), analysed **statically** under radare2 (no emulator). Complements
> `workbench-task-v34.md` §8 (scroll gadgets) and corrects `installclipregion-v34.md` §5.
>
> **Legend**: **[O]** observed directly in the code · **[D]** deduced from converging
> observations · **[S]** assumed. This document describes behaviours, ABI layouts and
> constants. **No instruction sequence is reproduced or paraphrased, no ROM routine
> address is given.**

Public fields used:
- `struct Window` (1.3): Width +$08, Height +$0A, Flags +$18, RPort +$32, BorderLeft/Top/Right/
  Bottom +$36/+$37/+$38/+$39 (signed bytes), IDCMPFlags +$52, **UserData +$78**.
- `struct RastPort`: Layer +$00, Mask +$18, TxBaseline +$3E.
- `struct Layer` (`graphics/clip.h` 1.3): Flags +$1E (word; **LAYERREFRESH = $0080**),
  **DamageList +$9C** (struct Region *).
- `struct Rectangle`: MinX, MinY, MaxX, MaxY (4 words, **inclusive** bounds).
- `struct Screen`: Width +$0C, Height +$0E.
- `struct TextFont`: tf_YSize +$14.
- WBObject (private structure built by icon.library, cf. `workbench-task-v34.md` §7.3/§7.8):
  parent +$38, flags +$3C, type +$3D (1 = disk), name +$40, name offset +$44/+$46 (words),
  DrawerData +$4C, display window +$50, CurrentX/Y +$54/+$58, **embedded Gadget +$60**
  (hence LeftEdge +$64, TopEdge +$66, Width +$68, Height +$6A, Flags +$6C, GadgetRender +$72,
  SelectRender +$76).
- DrawerData: scroll position +$30/+$34, extent +$38..+$44, list of the drawer's icons
  (struct List) **+$1AC**, open window **+$1A4**.

---

## 0. Short answer

1. **No layer, no RastPort, no ClipRect or ClipRegion of its own.** The Workbench draws
   directly into the drawer window's `Window->RPort` (window **not** GIMMEZEROZERO, so
   its layer also covers the borders). [O]
2. Clipping to the content area is obtained through the **BeginUpdate trick**: the WB **replaces
   (or shrinks) the `DamageList` of the window's layer** with the content rectangle, calls
   **`BeginUpdate`**, draws, then **`EndUpdate`**. During the update, layers only lets
   graphics draw in *visible ∩ damage*: any icon — even straddling the edge, or
   far outside the window — is **drawn in full and clipped by layers** at the edge of the
   content. Borders and gadgets are never touched. [O]
3. **No "visible / invisible" sorting**: partial icons are **neither skipped, nor
   redrawn with border touch-up**. Only exception: an icon whose window position
   exceeds **4 × the screen size** (in absolute value, on X or Y) is not drawn at all
   (safeguard against 16-bit coordinate overflows). [O]
4. The **name** under the icon follows exactly the same path (Text in the same update): it
   is clipped to the pixel at the edge of the content. [O]
5. **Scrolling: no ScrollRaster** (the module calls neither ScrollRaster, nor ClipBlit, nor
   ScrollLayer). Each change of position triggers a **complete redisplay** of the content:
   recomputation of the extent and of the bars, then, under an update forced to the content rectangle,
   **SetRast(rp, 0)** (hence erasing **only the content rectangle**), then drawing of all the
   icons. [O]
6. Bit **$00400000** of `NewWindow.Flags` **plays no role**: intuition 34.3 never tests it
   anywhere in `Window->Flags` (it is simply copied). It is the value of **INTUITICKS**, which the
   WB manipulates elsewhere in `IDCMPFlags`; its presence in the Flags is probably an
   author's mix-up. [O for the absence of test, D for the interpretation]

---

## 1. Opening "drawing in the content" (start of update) [O]

Input: the drawer/disk object (to know the content area), its window, and a **mode**:
**1 = replace** the damage with the content rectangle (spontaneous drawing: complete redisplay,
drawing of one icon); **0 = shrink** the existing damage to the content rectangle (repair
after REFRESHWINDOW/NEWSIZE).

1. Global **nesting counter** (one byte in the WB globals, initialised to 0): it is
   incremented; **if its previous value was not 0, nothing else is done** (nested call,
   the update in progress is used). The counter is **unique for the whole WB**, not per window:
   nested calls always concern the same window.
2. `layer = Window->RPort->Layer`; **LockLayerRom(layer)** (graphics −432).
3. **Content rectangle**, in layer coordinates (= window coordinates, origin at the
   top-left corner of the window, inclusive bounds):
   - MinX = **BorderLeft**, **+ 14 if the object is a disk** (type 1: room for the gauge, cf.
     `workbench-task-v34.md` §8.4);
   - MinY = **BorderTop**;
   - MaxX = **Width − BorderRight − 1**;
   - MaxY = **Height − BorderBottom − 1**.
   (For the borderless backdrop root window: the whole window.)
4. `Window->UserData` (+$78) := 0. **The WB appropriates the UserData of its windows** as a save slot.
5. **Mode 1**:
   - **NewRegion()**; if it succeeds: `UserData := layer->DamageList` (save) then
     `layer->DamageList := new region`;
   - **ClearRegion(layer->DamageList)** then **OrRectRegion(layer->DamageList, &rect)**: the
     "damage" is exactly the content rectangle.
   - If NewRegion fails, it is the real DamageList that is emptied then reduced to the rectangle (the
     pending damage is lost; memory case only).
6. **Mode 0**: **AndRectRegion(layer->DamageList, &rect)**: the real damage is trimmed to the
   content rectangle (the part of the damage falling in the borders is dropped by the WB;
   repairing the frame is intuition's business).
7. **BeginUpdate(layer)** (layers −78).

Effect: until the closing (§2), **any graphics drawing in `Window->RPort` is clipped to
(visible part of the layer) ∩ (content rectangle [∩ real damage in mode 0])**.

## 2. Closing (end of update) [O]

1. Counter decremented; **if it does not reach 0, nothing else**.
2. If `UserData ≠ 0` (mode 1 with allocated region): **DisposeRegion(layer->DamageList)** (the
   WB's region), `layer->DamageList := UserData` (the real pending damage is given back
   intact), then **EndUpdate(layer, FALSE)** (the damage is not cleared: a later repair
   is still due). The LAYERREFRESH bit is not touched.
3. Otherwise (mode 0, or NewRegion failure): **LAYERREFRESH ($0080) is cleared** in
   `layer->Flags`, then **EndUpdate(layer, TRUE)** (damage cleared: the window is
   considered repaired).
4. **UnlockLayerRom(layer)** (graphics −438).

## 3. Drawing an icon [O]

Executed for a single icon (selection/deselection, drop) **wrapped in its own opening/
closing in mode 1** (object = parent `+$38`, window = `+$50`), or for each icon of a
complete redisplay (the opening is then nested, hence neutral).

1. If **bit 3 of `+$3C`** ("too far", §4) is set: **nothing is drawn**.
2. **Image** at window position **(x, y) = (`+$64`, `+$66`)** (LeftEdge/TopEdge of the embedded
   gadget, already converted to window coordinates, §4), offset by the Image's LeftEdge/TopEdge;
   it is copied by **BltBitMapRastPort** (graphics −606) — or **BltMaskBitMapRastPort** (−636)
   for an icon in "backfill" highlight mode (Flags & 3 = 1, the mask being the
   SelectRender data) — from a BitMap built on the Image's planes, the RastPort's `Mask`
   being temporarily reduced to the PlanePick planes present in the image and then restored.
   Minterm $C0 (copy) in the normal state; selected (bit 5 of `+$3C`): SelectRender if mode
   GADGHIMAGE and SelectRender ≠ 0, otherwise inverted copy ($30; $20 in the masked variant; $E0 for
   the normal masked copy). **No intuition DrawImage.** The blit is **always requested in
   full**: it is layers/graphics that clips it.
3. **Name**: SetFont(rp, WB font), **SetAPen(rp, 1)**, **SetDrMd(rp, JAM2)**,
   **Move(rp, x + `+$44`, y + `+$46`)**, **Text(rp, name, strlen(name))**. The JAM2 background is the current
   BPen of the window's RastPort (the WB does not set it; 0 in practice [D]). No measurement
   nor truncation: the whole string is requested and **clipped by layers** at the edge of the content.
   - Name offsets (computed when the icon is loaded): `+$44` = (Gadget.Width −
     TextLength(name)) / 2 (arithmetic division, may be **negative** if the name is wider than
     the image), `+$46` = Gadget.Height + **TxBaseline** of the WB's private RastPort (so the top of the
     text sits right under the image).

## 4. Window position, "too far" and extent [O]

Recomputed for **all** icons of the drawer during the extent recomputation
(`workbench-task-v34.md` §8.2), walking the list `DD+$1AC` from head to tail:

- window x `+$64` := **content MinX** (§1.3) + `CurrentX` − `DD+$30`;
- window y `+$66` := **BorderTop** + `CurrentY` − `DD+$34`;
- **bit 3 of `+$3C`** is first cleared, then **set if |x| > 4 × Screen.Width or |y| > 4 ×
  Screen.Height** (Workbench screen). This is the **only** skip criterion: there is no
  "does the icon intersect the content?" test.
- extent, with o = max(0, −`+$44`) (name overhang on each side):
  min X := min(min X, CurrentX − o); min Y := min(min Y, CurrentY);
  max X := max(max X, CurrentX + Gadget.Width + o);
  max Y := max(max Y, CurrentY + Gadget.Height + **tf_YSize** of the WB font).

## 5. Complete redisplay of a drawer (and scrolling) [O]

Exact order:

1. **Recomputation of the extent** and of the window positions (§4), then, except for the root window,
   **update of both bars** (NewModifyProp, `workbench-task-v34.md` §8.3) — **outside** the
   update: intuition redraws the bar concerned itself.
2. **Opening mode 1** (§1): lock, damage := content rectangle, BeginUpdate.
3. **SetRast(Window->RPort, 0)**: thanks to the update, only the (visible) **content rectangle**
   is filled with colour 0. Borders, title bar, gadgets, disk gauge (left
   of MinX): intact.
4. **Drawing of each icon** (§3) walking the list `DD+$1AC` **from tail to head**:
   the head is drawn last, hence **on top**. (The WB puts an icon that was just moved back at the
   head: it comes to the foreground.)
5. **Closing** (§2): real damage restored, EndUpdate(FALSE), unlock.

**What the WB never does here**: redraw borders, frame or system gadgets; call
RefreshGadgets/RefreshWindowFrame; ScrollRaster; copy the part that stayed visible.

**Triggers** of the complete redisplay: **every scroll step** (arrows, Shift+arrows,
bars, INTUITICKS repeat: the new position is written to `DD+$30/+$34` then complete
redisplay), Clean Up (positions reset to 0 beforehand), drop/move of an icon in a drawer,
removal or addition of an icon, opening of the window, and WBENCHOPEN. [O for scrolling and
Clean Up; D for the list of the others]

Visible consequence: at each scroll step, the content is **erased then redrawn**
(slight flicker); icons straddling the edge appear cut cleanly at the edge of the
content, without ever spilling onto the bars or the frame.

## 6. Repair: REFRESHWINDOW and NEWSIZE [O]

Both IDCMP classes lead to the same processing, **only if `layer->Flags` has LAYERREFRESH**:

1. If the window box (Left/Top/Width/Height) differs from the one stored in the
   DrawerData (+$00..+$06) — except for the root window — it is stored and the extent + the
   bars are recomputed (§5 point 1, without redisplay).
2. **Disk** window: the **gauge** is redrawn (outside the update, directly in the
   RastPort).
3. **Opening mode 0**: real damage ∩ content rectangle, BeginUpdate.
4. **No erasing**: the damaged areas are assumed to be already at background (layers' role for
   a SIMPLE_REFRESH layer [D]).
5. Drawing of all icons (tail → head), clipped to *damage ∩ content*.
6. **Closing**: LAYERREFRESH cleared, **EndUpdate(TRUE)**.

The window's frame and gadgets are repaired by intuition, not by the WB [D].

## 7. Bit $00400000 of the Flags [O]

- Two opening paths of a drawer/disk window pass hard-coded Flags to
  `NewWindow.Flags`: **first opening** (gadgets copied from the templates, §8.1 of
  `workbench-task-v34.md`): **$0240027F**; **reopening** with a DrawerData already prepared:
  **$0200027F**. Behaviour therefore cannot depend on it.
- intuition 34.3 copies `NewWindow.Flags` into `Window->Flags` (only BACKDROP removes bits there)
  and **never tests bit 22** of `Window->Flags` (neither bit test, nor an immediate mask
  containing it); its only uses of $00400000 concern `im_Class` and `IDCMPFlags`
  (INTUITICKS). The WB does not re-read `Window->Flags` for this bit either; it adds and removes
  **INTUITICKS in IDCMPFlags** (ModifyIDCMP) for arrow repeat.
- For our ROM: **ignore** this bit in `Window->Flags` (leave it copied, without effect).

## 8. Requirements for our ROM [D]

- **layers.library**: `BeginUpdate` must build the update ClipRects from the
  `DamageList` **as the caller has set it** at +$9C (region replaced by a third party),
  intersected with the visible part; `EndUpdate(l, FALSE)` restores the normal ClipRects without
  touching the DamageList; `EndUpdate(l, TRUE)` restores them and empties the DamageList.
- **graphics.library**: SetRast, BltBitMapRastPort, BltMaskBitMapRastPort and Text must
  respect the layer's ClipRects (including during an update); regions: NewRegion,
  ClearRegion, OrRectRegion, AndRectRegion, DisposeRegion; LockLayerRom/UnlockLayerRom.
- **intuition**: `Window->UserData` (+$78) belongs to the application (the WB uses it); it
  must itself repair the frame and gadgets of a damaged SIMPLE_REFRESH window.
- **workbench.task**: draw the icons **without** a visibility test (apart from the 4 × screen safeguard),
  in the window's RastPort, between "opening/closing" (§1/§2); scrolling = complete
  redisplay (§5).

## 9. Proposed black-box check (not done, emulator busy)

Not essential: the static analysis is complete. If visual proof is wanted, with the
real ROM then ours (same Workbench 1.3 ADF, same capture harness): open the disk,
shrink the window so that an icon is cut by the right edge and by the bottom edge, capture;
scroll by one arrow step (visible width / 8), capture. Expected: icon and name cut cleanly at
`Width − BorderRight − 1` / `Height − BorderBottom − 1`, bars and frame intact, content erased in
colour 0 then redrawn at each step.

---

## Clean-room review

- [x] No instruction sequence transcribed or paraphrased line by line: only behaviour
  rules, call orders of public libraries (graphics, layers, intuition),
  formulas and structure offsets (public: Window, Layer, RastPort, Region/Rectangle,
  Screen, TextFont; private, already documented: WBObject, DrawerData).
- [x] No ROM routine address; the LVOs cited are those of the public `.fd` files.
- [x] Points not observed directly are marked [D] (role of layers/intuition in the
  repair, exhaustive list of complete-redisplay triggers).
- [x] Correction made to `installclipregion-v34.md` §5 (the WB does not use
  GIMMEZEROZERO windows; clipping goes through the DamageList + BeginUpdate) and clarification of bit
  $00400000 in `workbench-task-v34.md` §8.1.
