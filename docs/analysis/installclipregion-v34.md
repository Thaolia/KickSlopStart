# installclipregion-v34.md — layers.library 34.1: InstallClipRegion (behavioural spec)

> ANALYSIS track ("dirty"). Source: ROM `kick34005.A500` (layers 34.1, intuition 34.3) read under
> radare2, plus a black-box probe on the real ROM under FS-UAE (`tests/clipreg.s`, vectors §7).
> We describe the **what** (observable effects, order, conditions, ABI layout), never the **how**:
> no instruction sequence transcribed, no routine address.
>
> Legend: **[R]** ROM analysis (behaviour) · **[S]** black-box probe · **[D]** public documentation
> (NDK `layers_lib.fd`, AutoDocs) · **[R+S]** both agree.

---

## 1. Existence and ABI

- `InstallClipRegion` **exists in V34**: it is the **25th and last** user vector of
  layers.library 34.1, **LVO −174**, `InstallClipRegion(layer, region)(A0/A1)`, return **D0 = old
  region** (APTR, possibly NULL). The 34.1 table has exactly the LVOs −30..−174 (25
  functions, `InitLayers` … `MoveLayerInFrontOf`, `InstallClipRegion`); `MoveSizeLayer` (−180) and
  following do not exist in 1.3. **[R; D for the names]**
- No argument checking: `layer` must be valid (no NULL test); `region` NULL = removal.
  **[R]**

### 1.1 ABI fields involved (V34 offsets)

`struct Layer` (public, `graphics/clip.h` 1.3) **[R: offsets read from the accesses; D]**:

| Off. | Field | Role here |
|---:|---|---|
| `$08` | `ClipRect` | **current** list of ClipRects (the one graphics walks to draw) |
| `$0C` | `rp` | RastPort of the layer (its `BitMap->Depth` is used to allocate the hidden buffers, §3.3) |
| `$10..$17` | `bounds` (MinX, MinY, MaxX, MaxY) | origin of the region's coordinates (§2) |
| `$1E` | `Flags` (UWORD) | `LAYERUPDATING $0010` (BeginUpdate), `LAYER_CLIPRECTS_LOST $0100` (memory failure, §3.5) |
| `$2C/$2E` | `Scroll_X/Scroll_Y` | **ignored** by the region (§2); intuition sets them to 0 during its drawing (§5) |
| `$40` | `_cliprects` (private) | **backup** of the "normal" list while a reduced list is in place |
| `$44` | `LayerInfo` | |
| `$48` | `Lock` (SignalSemaphore, 46 bytes) | layer lock |
| `$7E` | **`ClipRegion`** | the installed region (caller's pointer, **not copied**) |
| `$82` | `saveClipRects` (private) | set to NULL for each layer at the first `LockLayers` (§4.2); no other use observed |
| `$9C` | `DamageList` | damage region (BeginUpdate) |

`struct ClipRect` (40 bytes allocated): `Next $00`, `prev $04`, `lobs $08`, `BitMap $0C`, `bounds $10`
(**screen** coordinates, i.e. of the LayerInfo's BitMap), private `$18..$27`. `struct Region`: `bounds $00`
(8 bytes), `RegionRectangle $08`; `struct RegionRectangle`: `Next $00`, `Prev $04`, `bounds $08`
(relative to `Region.bounds.MinX/MinY`). **[D; R for the use]**

---

## 2. Coordinates

- The region is expressed in **layer coordinates**: pixel (0,0) of the region is the corner
  `bounds.MinX/MinY` of the layer. A region rectangle `rr` gives in screen coordinates
  `layer.MinX + region.bounds.MinX + rr.bounds.MinX` (same for Y, and for Max). **[R+S]** (T1: rect (10,10)-(29,19)
  of a layer at (100,50) ⇒ screen ClipRect (110,60)-(129,69)).
- `Scroll_X/Scroll_Y` are **not** applied (in 1.3 they only concern superbitmap layers). **[R]**
- The region may extend beyond the layer: only the intersection with the layer counts (§3.1). **[R+S]** (T5).

---

## 3. Semantics

### 3.1 Effect of `InstallClipRegion(layer, region)` **[R; S for the visible cases]**

Under the layer lock (graphics' `LockLayerRom`/`UnlockLayerRom`, reentrant):

1. `old = layer->ClipRegion`.
2. If `old ≠ NULL`: the current reduced list is **undone** (§3.4) and the normal list restored.
3. `layer->ClipRegion = region`.
4. If `region ≠ NULL`: a **reduced list** is built (§3.2) and becomes `layer->ClipRect`.
5. Unlock; return `old`.

Consequences:
- `InstallClipRegion(l, NULL)` with no region installed does nothing observable (returns NULL). **[R+S]**
- Reinstalling the same region (`Install(l, r)` then `Install(l, r)`) returns `r` and **rebuilds** the list:
  this is the only way to have a **modification of the region after installation** taken into account
  (the reduced list is a snapshot; graphics never re-reads the region). **[R+S]** (T2).
- The `region` pointer is kept as is; layers never frees it (it is up to the application to
  remove it before `DisposeRegion` / `CloseWindow`). **[R]**

### 3.2 Construction of the reduced list **[R; S for the visible part]**

The normal list (`layer->ClipRect`) is stored in `_cliprects` (`$40`) and `layer->ClipRect` starts again empty.
Let `C` be the clipping region:
- outside BeginUpdate: `C = ClipRegion`;
- during BeginUpdate (`LAYERUPDATING`): `C = DamageList ∩ ClipRegion` (temporary copy, destroyed at the end);
  without ClipRegion: `C = DamageList` (normal BeginUpdate behaviour).

If `C` has **no rectangle**: the layer remains **without any ClipRect** (`layer->ClipRect = NULL`) ⇒ any
drawing into the layer has no effect. **[R+S]** (T4: `ClipRect = 00000000`, pixel unchanged).

Otherwise, two regions are computed from the normal list (in layer coordinates):
- **V** = union of the **visible** ClipRects (`lobs == NULL`);
- **O** = union of the **hidden ClipRects with a buffer** (`lobs ≠ NULL` **and** `BitMap ≠ NULL`, i.e. the
  hidden parts of a smart/superbitmap layer). Hidden parts without a buffer (simple layer) are
  not carried over: drawing there remains without effect, as without a region.

Then:
1. for each rectangle of `V ∩ C`: a visible ClipRect (`lobs = NULL`, `BitMap = NULL`), screen bounds;
2. for each rectangle of `O ∩ C`: a "hidden" ClipRect with `lobs = 1` (non-null sentinel value,
   not a layer pointer) and an **own BitMap buffer** of the depth of the layer's `rp->BitMap`,
   aligned on 16 pixels like the smart buffers; its contents are **copied from the original buffer(s)**
   covering it (BltBitMap, minterm `$CA`, mask `$FF`).
The ClipRects are taken from the LayerInfo; the buffers of the hidden ClipRects are allocated **outside** the
LayerInfo's accounting (MEMF_CLEAR). The temporary regions V, O (and the DamageList ∩ ClipRegion copy)
are freed at the end. **[R]**

### 3.3 Drawing while a region is installed **[R+S]**

graphics draws through `layer->ClipRect` as usual: there is **no special case** in
graphics. Hence:
- visible pixels outside `C` are **not** modified; those in `V ∩ C` are (T1, T6);
- drawing into hidden parts of a smart layer, within `C`, goes into the reduced list's own buffers
  and is **carried over** into the original buffers on removal (§3.4).

### 3.4 Removal of the reduced list **[R]**

For each hidden ClipRect of the reduced list (`lobs ≠ NULL`), its contents are copied (BltBitMap `$CA`,
mask `$FF`) into **the first** hidden ClipRect of the saved normal list whose bounds cover it.
Then the reduced list is freed (ClipRects returned to the LayerInfo, buffers freed), `layer->ClipRect =
_cliprects`, `_cliprects = NULL`.

### 3.5 Insufficient memory **[R only]**

If an allocation fails during construction, construction stops (partial reduced list left
in place) and `layer->Flags |= LAYER_CLIPRECTS_LOST ($0100)`. InstallClipRegion does not inform the caller
(it still returns the old region).

---

## 4. Interactions

### 4.1 BeginUpdate / EndUpdate **[R]**

- **BeginUpdate(l)**: locks the layer (and **leaves it locked** until EndUpdate); if a
  ClipRegion is installed, first undoes its reduced list; sets `LAYERUPDATING`; builds the reduced
  list with `C = DamageList ∩ ClipRegion` (or `DamageList` alone without ClipRegion). The drawing of a refresh
  is therefore limited **both** to the damage and to the region.
- **EndUpdate(l, flag)**: if `flag ≠ 0`, `ClearRegion(DamageList)`; undoes the reduced list (§3.4);
  clears `LAYERUPDATING`; **if a ClipRegion is installed, rebuilds its list** (`C = ClipRegion`);
  unlocks.
- Calling InstallClipRegion **between** BeginUpdate and EndUpdate rebuilds with `DamageList ∩ new region`
  (the UPDATING flag is still set); removal by NULL gives `C = DamageList`.

### 4.2 Layer operations (Create*, Upfront, Behind, Move, Size, Delete, MoveLayerInFrontOf) **[R; S Move]**

All these functions bracket their work with `LockLayers(li)` … `UnlockLayers(li)` (lock of all the
layers of the LayerInfo). layers.library uses this global lock to neutralise the regions:
- **at the first level** of LockLayers (counter `LayerInfo+$5B` going to 1): for **each layer** of the
  LayerInfo (from `top_layer` backwards), `saveClipRects := NULL`, and if `ClipRegion ≠ NULL`, its reduced
  list is undone (§3.4) ⇒ the operation works on the normal lists;
- **at the last** UnlockLayers (counter returning to 0): for each layer having a `ClipRegion`, the reduced
  list is **rebuilt** on the new arrangement (§3.2).
Effects: the region follows the layer (layer coordinates) after Move/Size; newly hidden or
uncovered parts are taken into account; an application that calls LockLayers itself sees the normal lists as long as
it holds that lock. `ScrollLayer` does not go through this mechanism. **[R]** Vector T6: after
`MoveWindow(+20,+10)` the installed region remains `ClipRegion` and the reduced ClipRect is translated. **[S]**
- `DeleteLayer` of a layer still having a ClipRegion: the region is **not** freed (it belongs to
  the application). **[R]**

### 4.3 With LockLayer / LockLayerInfo alone

No effect on the region (only LockLayers neutralises it). **[R]**

---

## 5. Who uses it in 1.3 **[R]**

- In the whole ROM, **only intuition** calls InstallClipRegion (a single call site to vector
  −174, via the layers base stored in IntuitionBase `+$68`). console.device, graphics, workbench.task,
  dos do not call it.
- intuition's use: around **all its internal drawing in a window** (frame, system and
  application gadgets, knob of proportional gadgets, etc. — about fifteen callers) intuition:
  1. locks the layer (graphics' `LockLayerRom`) and takes its internal lock;
  2. `old = InstallClipRegion(layer, NULL)` (stored in IntuitionBase, private);
  3. saves the layer's `Scroll_X/Scroll_Y` and sets them to 0;
  4. draws; then restores `Scroll_X/Y`, `InstallClipRegion(layer, old)`, unlocks.
  Hence: **intuition's drawing ignores the application's ClipRegion**, and intuition calls
  InstallClipRegion **even when no region is installed** (neutral call, §3.1). An implementation
  of intuition can do without it if it has no ClipRegion to neutralise, but as soon as an application
  installs one, the absence of this removal would make the gadgets/frames clipped by the application's region.
- The Workbench 1.3 does **not** use InstallClipRegion. Its drawer/disk windows are **not**
  GIMMEZEROZERO (Flags $0240027F / $0200027F, SIMPLE_REFRESH): it clips its icons to the content rectangle
  by **replacing (or reducing) the layer's `DamageList` with that rectangle, then BeginUpdate/EndUpdate**
  (cf. `wb-icon-clipping-v34.md`). Only the info.library window is GIMMEZEROZERO.

What breaks without InstallClipRegion: third-party applications (editors, "system-friendly" games/tools,
drawing programs) that call it get a jump to a missing vector; and, if it is implemented
without the neutralisation by intuition, the rendering of the gadgets in those windows.

---

## 6. Summary for the implementation

1. LVO −174, A0 = layer, A1 = region or NULL, D0 = old one. Layer lock.
2. Reduced list = (visible ∩ C) + (hidden-with-buffer ∩ C, own buffers copied on the way in and on the way out),
   `C` = ClipRegion, or DamageList ∩ ClipRegion during BeginUpdate; empty region ⇒ no ClipRect.
3. Region coordinates = layer coordinates (origin `bounds.MinX/MinY`), Scroll ignored.
4. Snapshot: modifying the region requires reinstalling it.
5. BeginUpdate/EndUpdate and LockLayers/UnlockLayers (hence all stack operations) undo and
   rebuild the reduced list.
6. intuition removes the region (and cancels Scroll_X/Y) during its own drawing.

---

## 7. Test vectors (real ROM 34.5, FS-UAE 3.2.35)

Probe `tests/clipreg.s` (copy of the WB 1.3.3 ADF, launched by `clipreg >SER:` from the startup-sequence;
`slow_memory = 512`). BORDERLESS|ACTIVATE smart window, at (100,50), 100×50, entirely visible; layer
⇒ screen bounds (100,50)-(199,99). R1 = {(10,10)-(29,19)} in layer coordinates. Pixels read back in the
screen's RastPort (`P x y pen`, hexadecimal). `CR minX minY maxX maxY lobs BitMap`.

```
T0 00000000                         initial ClipRegion = NULL
CR 0064 0032 00C7 0063 00000000 00000000      normal list: 1 ClipRect = the whole layer
T1 00000000 00C05B60                Install(R1) returns NULL; layer+$7E = R1
CR 006E 003C 0081 0045 00000000 00000000      reduced list = R1 + (100,50) = (110,60)-(129,69)
P 0069 0037 00000000                (105,55) outside the region: intact
P 0073 0041 00000001                (115,65) inside: pen 1
P 0081 0045 00000001                (129,69) bottom-right corner included
P 0082 0046 00000000                (130,70) just outside: intact
T2                                  OrRectRegion(R1, (50,30)-(59,39)) WITHOUT reinstalling, fill pen 2
P 0073 0041 00000002
P 009B 0055 00000000                (155,85): not drawn ⇒ the reduced list is a snapshot
00C05B60                            Install(R1) again: returns R1
CR 0096 0050 009F 0059 00000000 00000000      (150,80)-(159,89)
CR 006E 003C 0081 0045 00000000 00000000
P 0073 0041 00000002
P 009B 0055 00000002                now drawn
T3 00C05B60 00000000                Install(NULL) returns R1; layer+$7E = NULL
CR 0064 0032 00C7 0063 00000000 00000000      normal list restored
P 0069 0037 00000000 … (all pen 0 after fill pen 0)
T4 00000000 00000000                empty region: Install returns NULL; layer->ClipRect = NULL
P 0069 0037 00000000 / 0073 0041 00000000 / … fill pen 1 without effect
T5                                  overflowing region (-20,-20)-(200,200)
CR 0064 0032 00C7 0063 00000000 00000000      bounded to the layer
T6                                  Install(modified R1) then MoveWindow(+20,+10), Delay 1 s
L 0078 003C 00C05B60                layer at (120,60), ClipRegion still R1
CR 00AA 005A 00B3 0063 00000000 00000000      (50,30)-(59,39) + (120,60) = (170,90)-(179,99)
CR 0082 0046 0095 004F 00000000 00000000      (10,10)-(29,19) + (120,60) = (130,70)-(149,79)
P 007D 0041 00000000                (125,65) outside the region
P 0087 004B 00000003                (135,75) inside
P 0095 004F 00000003                (149,79) corner included
P 0096 0050 00000000                (150,80) outside
```
Proposed non-regression: reproduce these lines (region addresses excepted).

---

## 8. Not probed / uncertain

- **Hidden** parts of a smart layer under a region (own buffers, copy in/out): ROM only;
  the probe only has an entirely visible layer.
- **Superbitmap** layers: the handling of hidden parts assumes that their hidden ClipRects carry a
  BitMap (§3.2); not verified.
- BeginUpdate/EndUpdate interaction with an installed region: ROM only (no deterministic
  damage in the probe).
- Memory failure (`LAYER_CLIPRECTS_LOST`): ROM only.
- Order of the ClipRects in the reduced list: not normative (graphics does not depend on it).

---

## Clean-room review

- [x] No instruction sequence transcribed or paraphrased; no ROM routine address (only
  offsets of public/private structures, ABI constants and hardware ranges).
- [x] The probes cited are author code (`tests/`, header "ASSET DE TEST, PAS du code ROM").
