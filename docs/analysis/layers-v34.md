# layers.library 34.1 — complete behavioural spec

> **ANALYSIS** track ("dirty"). Sources: ROM `assets/kick34005.A500` (read-only; radare2 and
> headless Ghidra decompilation, base `$FC0000`, notes outside the repository) and black-box probe
> `tests/layers_probe.s` (harness `tests/layers_probe.sh`) run **twice** on the **real ROM**
> under FS-UAE (A500 PAL, 512 KB chip + 512 KB slow), identical results apart from pointers.
> This document describes **behaviours**, **values**, **orders of operations** and
> **ABI layouts**; it contains no ROM instruction sequence and no routine address.
>
> It complements without repeating them: `installclipregion-v34.md` (InstallClipRegion, construction of
> BeginUpdate's reduced list, neutralisation of regions by LockLayers), `wb-icon-clipping-v34.md`
> (use of BeginUpdate by the Workbench), `intuition-gzz-v34.md` (layers of GZZ windows),
> `graphics-blitter-v34.md` §5 and §12 (drawing through ClipRects, `MinX & ~15` rule),
> `setpatch-disk-resource.md` §4 (SetPatch's DeleteLayer fix).
>
> **Levels of evidence**: **[O]** observed by the probe on the real ROM · **[D]** deduced from reading
> the ROM code (behaviour, not code) · **[S]** reasonable assumption, not verified.

---

## 0. Summary for the implementer

1. **Two kinds of ClipRects.** **Visible** ClipRects (`lobs = NULL`) are **discarded and recomputed
   from scratch** after each successful stack operation, by subtracting from the layer's rectangle the
   rectangles of the layers in front. **Hidden** ClipRects (`lobs ≠ NULL`) are **persistent**
   objects that carry, for non-SIMPLE layers, the backing-store buffer; on a
   change of order, these objects **move from one layer to another** (the content is swapped or
   copied), they are not recreated. [D]
2. **Common tiling of hidden parts**: for a hidden rectangle `R`, all layers located
   behind the one hiding it and that cover `R` have a hidden ClipRect with **bounds identical** to
   `R`, and `lobs` designates **the frontmost layer** that covers it. layers splits the existing hidden
   ClipRects to maintain this property, and **merges** adjacent pieces after a
   DeleteLayer. [D][O]
3. **SIMPLE**: nothing is saved; an area that becomes visible again is **cleared to colour 0**
   (planes of its RastPort's `Mask`) and added to the `DamageList` (layer coordinates), with
   `LAYERREFRESH ($0080)`. **SMART** and **SUPER**: the hidden area is saved in `cr_BitMap`
   (CHIP, aligned on 16 pixels) and restored without damage. [O]
4. **layers never clears `LAYERREFRESH`** (except on its internal temporary layer); EndUpdate(TRUE)
   empties the region but leaves the bit. It is up to the caller (intuition, Workbench) to clear it. [D][O]
5. **MoveLayer and SizeLayer** go through a **temporary layer** created behind, placed in front of
   the original, filled by copying, then **swapped** with the original and deleted. A SIMPLE layer
   that is moved or resized is **entirely damaged**; a SMART layer that grows receives the new strips
   as damage. [O]
6. **Transactions**: CreateUpfront/BehindLayer, UpfrontLayer, BehindLayer, MoveLayerInFrontOf,
   MoveLayer, SizeLayer fail **without changing anything** when memory is short (return 0/NULL).
   Only the final reconstruction of the visible ClipRects, if it runs short of ClipRects, triggers
   the **fatal alert `$83010000`** (AN_LayersNoMem). [O for clean failures, D for the alert]
7. **Locks**: every stack operation = `LockLayerInfo` → (temporary fattening if the
   Layer_Info has not been "fattened") → `LockLayers` … `UnlockLayers` → (thinning) →
   `UnlockLayerInfo`. `LockLayer`/`UnlockLayer` = graphics' `LockLayerRom`/`UnlockLayerRom`. [D][O]

---

## 1. Module and ABI

- ROMTag: name `layers.library`, version **34**, type `NT_LIBRARY`, priority **31**, flags
  `RTF_COLDSTART`; identity string `layers 34.1 (18 Aug 1987)` followed by LF CR. Non-AUTOINIT
  initialisation (explicit MakeLibrary). [D]
- Base: `lib_Version` 34, `lib_Revision` 1, `lib_NegSize` **174** (29 vectors), `lib_PosSize` **42**.
  Private fields: **`+$22` GfxBase**, **`+$26` ExecBase** (obtained by `OpenLibrary("exec.library",0)`).
  `lib_Flags |= LIBF_SUMUSED|LIBF_CHANGED`, `lib_OpenCnt` set to **1** at init (the library is never
  expunged). Close and Expunge return 0. [D; O for version/revision/sizes]
- Vector table: 4 standard + **25 functions, LVO −30 to −174**, order of the 1.3 `.fd` (InitLayers …
  MoveLayerInFrontOf, InstallClipRegion). No vector beyond. [D][O]
- Each vector is an adapter that pushes the argument registers and calls the body (C code):
  **d0/d1/a0/a1 destroyed, d2–d7/a2–a6 preserved**. [D]

| LVO | Function | Registers | Returned value (D0) |
|--:|---|---|---|
| −30 | InitLayers(li) | A0 | none (undefined) [O] |
| −36 | CreateUpfrontLayer(li,bm,x0,y0,x1,y1,flags,bm2) | A0/A1,D0–D4,A2 | layer or NULL [O] |
| −42 | CreateBehindLayer(same) | same | layer or NULL [O] |
| −48 | UpfrontLayer(dummy,layer) | A0/A1 | TRUE (1) / FALSE (0) [O] |
| −54 | BehindLayer(dummy,layer) | A0/A1 | 1 / 0 [O] |
| −60 | MoveLayer(dummy,layer,dx,dy) | A0/A1,D0/D1 | 1 / 0 [O] |
| −66 | SizeLayer(dummy,layer,dx,dy) | A0/A1,D0/D1 | 1 / 0 [O] |
| −72 | ScrollLayer(dummy,layer,dx,dy) | A0/A1,D0/D1 | **undefined** (0 or 4 observed) [O] |
| −78 | BeginUpdate(layer) | A0 | 1 = list built, 0 = memory failure [O for 1, D for 0] |
| −84 | EndUpdate(layer,flag) | A0,D0 | undefined [D] |
| −90 | DeleteLayer(dummy,layer) | A0/A1 | 1 / 0 [O] |
| −96 | LockLayer(dummy,layer) | A0/A1 | undefined |
| −102 | UnlockLayer(layer) | A0 | undefined |
| −108 | LockLayers(li) | A0 | undefined |
| −114 | UnlockLayers(li) | A0 | undefined |
| −120 | LockLayerInfo(li) | A0 | undefined |
| −126 | SwapBitsRastPortClipRect(rp,cr) | A0/A1 | undefined |
| −132 | WhichLayer(li,x,y) | A0,D0/D1 | layer or NULL [O] |
| −138 | UnlockLayerInfo(li) | A0 | undefined |
| −144 | NewLayerInfo() | — | Layer_Info or NULL [O] |
| −150 | DisposeLayerInfo(li) | A0 | undefined [O] |
| −156 | FattenLayerInfo(li) | A0 | 1 / 0 [O] |
| −162 | ThinLayerInfo(li) | A0 | undefined [O] |
| −168 | MoveLayerInFrontOf(layer,other) | A0/A1 | 1 / 0 [O] |
| −174 | InstallClipRegion(layer,region) | A0/A1 | old region (see installclipregion-v34) |

`dummy` (the Layer_Info passed in A0 to the "layer" functions) **is never read**: the Layer_Info is
always taken from `layer->LayerInfo`. [D] No function checks its pointers (NULL forbidden). [D]
The **region functions** (`NewRegion`, `OrRectRegion`, `AndRegionRegion`…) are in
**graphics.library**, not in layers. [D]

---

## 2. Structures

### 2.1 `struct Layer` — 160 bytes (`$A0`), allocated `MEMF_CLEAR` [D]

| Off. | Field | Use by layers 34.1 |
|--:|---|---|
| `$00` | front | layer in front (NULL = top) |
| `$04` | back | layer behind |
| `$08` | ClipRect | current list (visible + hidden; reduced during BeginUpdate/ClipRegion) |
| `$0C` | rp | RastPort **allocated by layers** (§2.4); `rp->Layer` = layer, `rp->BitMap` = common BitMap |
| `$10` | bounds | MinX, MinY, MaxX, MaxY, **BitMap coordinates**, inclusive bounds |
| `$18` | reserved[4] | unused |
| `$1C` | priority (UWORD) | **renumbered** 1000, 999, 998… from the top **before** each effective change of order; 0 as long as no reordering has taken place. It therefore reflects the order **preceding** the last move (stale value) [O] |
| `$1E` | Flags (UWORD) | LAYERSIMPLE 1, LAYERSMART 2, LAYERSUPER 4, LAYERUPDATING $10, LAYERBACKDROP $40, LAYERREFRESH $80, LAYER_CLIPRECTS_LOST $100; copied as is from the `flags` argument [D][O] |
| `$20` | SuperBitMap | caller's BitMap (LAYERSUPER) |
| `$24` | SuperClipRect | list of the pieces of the SuperBitMap **outside** the visible window (§6) |
| `$28` | Window | not touched by layers (intuition) |
| `$2C/$2E` | Scroll_X/Scroll_Y | modified only by ScrollLayer (§5.8) |
| `$30/$34/$38` | cr, cr2, crnew | **scratch** for the merging of hidden ClipRects (§3.5); stale contents afterwards |
| `$3C` | SuperSaveClipRects | reserve of **5** preallocated ClipRects for a SUPER layer |
| `$40` | _cliprects | (1) normal list saved during a reduced list (installclipregion §3.2); (2) **rollback snapshot** during a stack operation — it remains **non-null and stale** after the operation; only EndUpdate/removal of a region resets it to NULL [O] |
| `$44` | LayerInfo | |
| `$48` | Lock | SignalSemaphore (46 bytes); its node is linked into `LayerInfo.gs_Head` |
| `$76` | reserved3[8] | unused |
| `$7E` | ClipRegion | see installclipregion-v34 |
| `$82` | saveClipRects | set to NULL at the first LockLayers; nothing else |
| `$86` | reserved2[22] | unused |
| `$9C` | DamageList | Region (NewRegion at creation, DisposeRegion at deletion), **layer coordinates** (origin `bounds.MinX/MinY`, without Scroll) [O] |

### 2.2 `struct ClipRect` — 40 bytes [D][O]

| Off. | Field | Use |
|--:|---|---|
| `$00` | Next | |
| `$04` | prev | **not a doubly linked list**: serves as a snapshot of `Next` for rollback |
| `$08` | lobs | NULL = visible; otherwise the frontmost layer that hides this rectangle; **1** = sentinel of reduced-list ClipRects (installclipregion) |
| `$0C` | BitMap | backing-store buffer (hidden SMART/SUPER) or NULL |
| `$10` | bounds | BitMap coordinates, inclusive |
| `$18/$1C/$20` | _p1, _p2, reserved | unused |
| `$24` | Flags | bit 0 = internal marker during a reordering, **always 0** between two calls [O] |

`cr_BitMap` buffer [D; O for the dimensions]:
- `BytesPerRow = ((MaxX & ~15) − (MinX & ~15) + 16) / 8` (always even); `Rows = MaxY − MinY + 1`;
  `Depth = rp->BitMap->Depth` of the layer; initialised by InitBitMap (width = BytesPerRow × 8).
- The screen pixel `(x, y)` of the ClipRect is at pixel `(x − (MinX & ~15), y − MinY)` of the buffer: the
  rectangle starts at column `MinX & 15` of the buffer.
- The BitMap structure is allocated with only **8 + 4 × Depth** bytes (MEMF_CLEAR): `Planes[Depth..7]`
  **do not exist**. Each plane: `BytesPerRow × Rows` bytes **MEMF_CHIP**, not cleared (except §5.1).
- Verified: ClipRect (60,30)-(115,59) depth 2 → BytesPerRow 10, Rows 30; (100,20)-(115,29) → 4; (116,30)-
  (159,49) → 6. [O]

### 2.3 `struct Layer_Info` — 102 bytes (`$66`) [D][O]

| Off. | Field | Use |
|--:|---|---|
| `$00` | top_layer | top of the stack |
| `$04` | check_lp | scratch (creation) — stale afterwards [O] |
| `$08` | obs | scratch (ClipRect list under construction) — **stale pointer** afterwards [O] |
| `$0C` | FreeClipRects (MinList) | transient reserve; **empty** between two calls [O] |
| `$18` | Lock (SignalSemaphore) | LockLayerInfo |
| `$46` | gs_Head (List) | the `Layer.Lock` of all layers, **in creation order** (AddTail), for ObtainSemaphoreList |
| `$54` | longreserved | unused |
| `$58` | Flags | bit 0 **NEWLAYERINFO_CALLED** (set by NewLayerInfo/FattenLayerInfo, cleared by ThinLayerInfo) |
| `$5A` | fatten_count (BYTE) | **−1** = thin; Fatten increments it and allocates on the transition −1 → 0 |
| `$5B` | LockLayersCount (BYTE) | nesting level of LockLayers |
| `$5C` | LayerInfo_extra_size | set to **$42** at the first fattening, never reset to 0 [O] |
| `$5E` | blitbuff | **128 bytes MEMF_CHIP** allocated at fattening; **not read by layers**; pointer left stale after freeing [O] |
| `$62` | LayerInfo_extra | 66 bytes MEMF_PUBLIC (failure-recovery context + list of allocations in progress); NULL when thin |

### 2.4 Layer RastPort — **78 bytes** (`$4E`)

layers allocates each layer's RastPort with **78 bytes MEMF_PUBLIC** and initialises it with
`InitRastPort`, which in V34 clears exactly 78 bytes. The fields beyond `$4E` (`wordreserved`,
`reserved` of the 1.3 header) **do not exist** in a layer RastPort: never write to them. [D]

---

## 3. ClipRect model

### 3.1 Visible: complete recomputation [D][O]

After each successful stack operation, for **each** layer: its visible ClipRects are returned to the
reserve, then a ClipRect = the layer's rectangle is split by each layer **in front**, from the
nearest to the farthest (`front`, `front->front`…):
- if it is **entirely contained** in the layer in front, it is deleted;
- if it **overlaps** it, the following parts are detached in this order: the part **on the left** (columns < MinX of the layer
  in front, the whole remaining height), **on the right**, **above**, **below**; each detached
  piece is inserted **at the head** of the list and continues being split by the layers further in front;
  the rest (contained in the layer in front) is deleted.
Observed consequence: the visible ones are at the head of the list, the hidden ones after; e.g. A (16,10)-(115,59)
under B (60,30)-(159,89) → `(60,10)-(115,29)` then `(16,10)-(59,59)` then the hidden `(60,30)-(115,59) lobs B`.
This order is **not normative** (graphics does not depend on it, and ClipBlit permutes it). [O]

### 3.2 Hidden: persistent objects [D]

- A hidden ClipRect describes a covered area of the layer; `lobs` = the **frontmost** layer that
  covers it; `BitMap` = backing store if the layer is not SIMPLE.
- **Tiling**: the hidden areas of all layers form a common tiling; when a new
  layer (or a new order) introduces a boundary, the hidden ClipRects crossed are **split**
  at the bounds of the layer concerned (the saved content is copied into the new buffers). E.g.:
  A hidden by B at (60,30)-(115,59), then C (100,20)-(199,49) created in front → A gets (60,30)-(99,59)
  lobs B, (100,50)-(115,59) lobs B, (100,30)-(115,49) **lobs C**; and B, hidden by C, is split at
  column 115/116: (100,30)-(115,49) and (116,30)-(159,49). [O]
- Hidden ClipRects **are not returned to the reserve** at recomputation: they change owner.

### 3.3 Change of order: fate of each area [D][O]

When a layer X moves **in front of** a layer Y over an area `R` (ClipRect of X hidden by Y):

| X (rises) | Y (descends) | Effect on the screen and the buffers | Damage |
|---|---|---|---|
| non-SIMPLE | non-SIMPLE | **swap** screen ↔ buffer (3 XOR blits, minterm `$6A`, mask = `X.rp->Mask`): X's content appears, Y's is saved in the same buffer | none |
| non-SIMPLE | SIMPLE | X's buffer **restored** to the screen (`$CA`), then blitter wait and **freeing** of the buffer | none (Y loses the area) |
| SIMPLE | non-SIMPLE | the screen (Y's content) is **saved** in a buffer allocated for the occasion, then the area is **cleared** | `R` added to X.DamageList, X |= LAYERREFRESH |
| SIMPLE | SIMPLE | area **cleared** | same |

Then the ClipRect object moves from X's list to Y's with `lobs = X`, and the ClipRects with the same
bounds in the layers further back receive `lobs = X`. The case "X descends behind Y" is the
symmetric one (roles reversed). Verified: UpfrontLayer(A smart) above B simple and C smart → pixels
of A restored, no damage; BehindLayer(A) → B simple receives the two re-exposed rectangles as
damage and the area is cleared to 0, C smart gets its pixels back. [O]

**Clearing** of a re-exposed SIMPLE area: colour **0**, only in the planes of the `Mask` of the
RastPort of the layer concerned, by **direct** programming of the blitter (edges and centre by words). [D]

### 3.4 Merging after DeleteLayer [D][O]

After the deletion of a layer (and therefore also of the temporary layer of Move/Size), layers
**merges** two hidden ClipRects of the same layer if they have the same `lobs` and share an entire
side (same MinX/MaxX and contiguous in Y, or same MinY/MaxY and contiguous in X), **provided that**
all other layers have either both pieces or neither (tiling preserved). The merge allocates
the new ClipRect and its buffer, copies both contents into it, and restarts the examination of the layer;
a memory shortage simply cancels the merge. Verified: after DeleteLayer(C), A gets back a single
hidden (60,30)-(115,59) lobs B. [O]

### 3.5 Coordinates

- ClipRects, `bounds`: **BitMap** coordinates. DamageList: **layer** coordinates. [O]
- `Scroll_X/Y` modify no ClipRect (ScrollLayer of a non-SUPER layer: only the fields
  change, the list stays identical). [O] graphics subtracts them when drawing (graphics-blitter §5.2). [D]
- No check that the layer fits in the BitMap: bounds outside the BitMap lead to
  blits outside the buffer. [D]

---

## 4. Refresh types

| Flags | Hidden parts | Re-exposure | Move | Size (grow) | Size (shrink) |
|---|---|---|---|---|---|
| **LAYERSIMPLE (1)** | ClipRect without buffer: drawings there are lost | cleared to 0 + damage + LAYERREFRESH | **whole layer** damaged + LAYERREFRESH; content largely cleared (§5.6) [O] | whole layer damaged + LAYERREFRESH [O] | same |
| **LAYERSMART (2)** | CHIP buffer | restored, no damage | content copied, no damage [O] | right strip `(W−dx … W−1) × whole height` and bottom strip `(whole width) × (H−dy … H−1)` as damage + LAYERREFRESH; the strips are 0 [O] | damage **not** trimmed (§5.7) [O] |
| **LAYERSUPER (4)** (without SMART) | CHIP buffer, like SMART [D] | restored [D] | content copied [D] | no damage; content taken from the SuperBitMap [O] | same [D] |
| **LAYERBACKDROP ($40)** | (according to SIMPLE/SMART) | | | | |

- A SMART bit is never tested: **everything that does not have LAYERSIMPLE is treated as SMART**. A layer
  `flags = 4` (SUPER alone, which is what intuition creates) therefore has buffers for its hidden parts. [D][O flags]
- **BACKDROP** acts only on the order: CreateBehindLayer of a non-BACKDROP layer places it **in front of the
  first BACKDROP layer**; of a BACKDROP one, at the very back. UpfrontLayer of a BACKDROP layer places it in front of
  the other BACKDROP layers only; BehindLayer of a non-BACKDROP layer places it just in front of the first
  BACKDROP, of a BACKDROP one at the very back. MoveLayerInFrontOf **ignores** BACKDROP. [D; O: D backdrop stays at the
  back after UpfrontLayer, BehindLayer(A) → B, C, A, D]
- LAYERREFRESH: set by layers at each damage; **never cleared by layers** (EndUpdate included). [D][O]

---

## 5. Functions

### 5.1 CreateBehindLayer (−42) [D; O for the visible effects]

1. Locks: LockLayerInfo, temporary fattening if `!(li->Flags & 1)` (failure ⇒ return NULL),
   LockLayers (§7).
2. Layer allocated, `bounds` = arguments, `LayerInfo`, `Lock` initialised then **obtained as many times as
   `LockLayersCount`** (the new layer is locked at the same level as the others).
3. LAYERSUPER: `SuperBitMap = bm2`, 5 ClipRects in reserve in `SuperSaveClipRects`.
4. RastPort 78 bytes + InitRastPort, `rp->BitMap = bm`, `rp->Layer`; DamageList = NewRegion (empty);
   `Flags = flags` (as is).
5. Insertion **at the very back**: the hidden ClipRects of the other layers are split at the bounds of the
   new one (§3.2); the new one receives hidden ClipRects for each covered area (lobs = the frontmost
   layer); non-SIMPLE: each hidden one receives a **cleared** buffer (BltClear); SUPER: list
   `SuperClipRect` built (§6); `Lock` added at the end of `gs_Head`. Then, if the layer is not BACKDROP,
   it is raised in front of the first BACKDROP (§3.3); if this fails, it is deleted and the call
   fails. Recomputation of the visible ones; SUPER: **CopySBitMap** (the content of the SuperBitMap appears).
6. Unlocking, then **outside the locks**: if non-SUPER, **SetRast(rp, 0)** (the whole layer, visible ones and
   buffers, to 0). Return: the layer.

Observed: B SIMPLE created **behind** A: `Flags $0001`, `priority 0`, **no damage** for its hidden
part, `(50,30)-(109,59) lobs A` without buffer. [O]

### 5.2 CreateUpfrontLayer (−36)

= CreateBehindLayer then UpfrontLayer; if UpfrontLayer fails: DeleteLayer, return NULL; otherwise
**ClearRegion(DamageList)**. **LAYERREFRESH is not cleared**: a SIMPLE layer created in front of
another layer has `Flags = $0081` with an empty DamageList. [D][O] Pixels: the area of the new layer
is 0; a covered SMART layer keeps its pixels in its buffer. [O]

### 5.3 UpfrontLayer (−48) / BehindLayer (−54) / MoveLayerInFrontOf (−168)

- UpfrontLayer: target = top (non-BACKDROP) or first BACKDROP (BACKDROP). If the layer is already there:
  **return TRUE without doing anything** (no renumbering). [D][O]
- BehindLayer: target §4. MoveLayerInFrontOf(l, other): places `l` just in front of `other`;
  `other = NULL` ⇒ at the very back; if `l->back == other`: immediate return TRUE. [D]
- Effect: renumbering of priorities (1000 downwards, current order), area swaps §3.3,
  relinking, recomputation of the visible ones. Return 1, or 0 if a buffer could not be allocated (state unchanged).
  [D; O: return 0 and order/ClipRects unchanged when CHIP is exhausted]
- No effect on the moved layer itself as regards damage when it is non-SIMPLE.

### 5.4 DeleteLayer (−90) [D; O for the visible effect]

Under the stack locks: DisposeRegion(DamageList); SUPER: reserve freed, **SyncSBitMap**
(the SuperBitMap receives the final state), SuperClipRects freed, `SuperBitMap = SuperClipRect = NULL`;
WaitBlit; all hidden ClipRects (and buffers) freed; the layer becomes **SIMPLE** (SMART and
SUPER bits cleared); **SetRast(rp, 0)** on its visible part; it is sent **to the very back** (§3.3: re-exposed
SMART layers are restored, SIMPLE ones cleared + damage + LAYERREFRESH); RastPort
freed; removed from the stack and from `gs_Head`; merge §3.4; recomputation of the visible ones; layer freed.
- An area that becomes visible again for **no** layer stays at **0**. [O]
- The `ClipRegion` is not freed (installclipregion §4.2). Return 1 (0 only if the temporary
  fattening fails).
- Observed: DeleteLayer(C) → the BACKDROP SIMPLE D receives as damage `(116,25)-(169,29)` and
  `(170,25)-(199,49)` (areas of C not covered by B), `Flags $00C1`. [O]
- **SetPatch 1.38** replaces this vector by analysing its first bytes (setpatch-disk-resource §4).

### 5.5 BeginUpdate (−78) / EndUpdate (−84)

Detailed in installclipregion-v34 §4.1; additions:
- BeginUpdate takes `LockLayerRom` and **keeps** it until EndUpdate; the reduced list = (visible ∩
  damage) + (hidden with buffer ∩ damage, own buffers copied). **Empty** DamageList ⇒
  `ClipRect = NULL`, return **1** (nothing will be drawn). Allocation failure ⇒ partial list,
  `LAYER_CLIPRECTS_LOST`, return 0. [O for 1 and NULL; D for the failure]
- EndUpdate(l, flag): `flag ≠ 0` ⇒ ClearRegion(DamageList); copy of the own buffers back to the
  original buffers; normal list restored, `_cliprects = NULL`; clears LAYERUPDATING; reinstalls the
  ClipRegion if any; UnlockLayerRom. **LAYERREFRESH is not touched.** [D][O]

### 5.6 MoveLayer (−60) [D; O for the results]

- `dx = dy = 0` ⇒ return 1 **without lock**. [O]
- Otherwise, under the stack locks: temporary layer T = CreateBehindLayer(same BitMap, bounds
  translated, `flags = (flags & 3) | BACKDROP`), BACKDROP removed if the original is not one;
  T placed just in front of the original (§3.3, T playing the role of the rising layer); recomputation;
  LAYERREFRESH cleared on T; **copy** of the original's content to T (through the ClipRects of
  both, `$CA`); if T is SIMPLE: `(0,0)-(W−1,H−1)` as damage + LAYERREFRESH; **swap** of T and
  the original (position in the stack, ClipRects, `lobs` that designate them, bounds); the
  original's DamageList |= T's, LAYERREFRESH carried over; deletion of T (which carries the old geometry:
  §5.4, hence restoration/damage of the re-exposed layers). Return 1, or 0 (state unchanged). [O]
- The `Layer` structure **keeps its address**; so does its `rp`. The SUPER bit is not passed on to T (the
  copy goes through the ClipRects, SuperClipRects unchanged). [D]
- **SIMPLE layer**: the content is largely **lost** (the areas of the old position
  covered by T are cleared before the copy) and the whole layer is damaged. In addition, the
  DamageList receives **spurious** rectangles: for each hidden ClipRect without buffer of the original,
  a rectangle whose MinX/MinY are relative to the ClipRect and MaxX/MaxY in screen coordinates. Observed
  (B 100×60 moved by (+8,+4)): region with bounds `(0,0)-(149,89)` instead of `(0,0)-(99,59)`. No
  visible effect (BeginUpdate intersects with the ClipRects), but the **bounds** of the DamageList can
  overflow the layer. A reimplementation may simply damage the whole layer. [O]
- **SMART layer**: content entirely preserved, no damage for it. [O]

### 5.7 SizeLayer (−66) [D; O]

Same scheme as MoveLayer with T = (MinX, MinY, MaxX + dx, MaxY + dy). Differences:
- Non-SUPER layer: copy of content from the original to T over `min(widths) × min(heights)`; SUPER:
  **SyncSBitMap** of the original instead.
- Damage: T SIMPLE ⇒ T's DamageList **emptied** then = the whole layer, LAYERREFRESH. T SMART non-
  SUPER ⇒ `dx > 0`: right strip `(W−dx, 0)-(W−1, H−1)`; `dy > 0`: bottom strip `(0, H−dy)-(W−1, H−1)`
  (W, H = new dimensions), LAYERREFRESH; `dx < 0` or `dy < 0`: the DamageList **of T** is trimmed
  to the new size — but it is the DamageList of **the original** that survives (merged with T's)
  and it **is not trimmed**: damage outside the shrunken layer remains. SUPER: no damage.
  Observed: SizeLayer(C, +20, +10) on 100×30 → damage `(100,0)-(119,39)` and `(0,30)-(99,39)`; then
  SizeLayer(C, −30, −15) → damage **unchanged** (overflowing the 90×25 layer). [O]
- After the swap: SUPER ⇒ **CopySBitMap** then reconstruction of the SuperClipRects. [D][O]

### 5.8 ScrollLayer (−72) [D; O]

Under `LockLayerRom` only (no LockLayers ⇒ no neutralisation of the ClipRegions):
- **without SuperBitMap**: `Scroll_X += dx`, `Scroll_Y += dy`, **nothing else** (no pixel moved,
  no damage, no bounds); [O]
- **with SuperBitMap**: SyncSBitMap, addition, CopySBitMap, reconstruction of the SuperClipRects. The values
  are **not bounded** to the SuperBitMap. [D; O for the display]
Returned value undefined. [O]

### 5.9 WhichLayer (−132) [D][O]

Walks the stack from `top_layer` and returns the first layer whose `bounds` (**inclusive** bounds,
signed 16-bit comparisons) contains `(x, y)`; NULL otherwise. Takes into account neither ClipRects, nor
BACKDROP, nor any lock (the caller must hold LockLayerInfo). Observed: corners (16,10) and (115,59)
included; point outside any layer → NULL.

### 5.10 Layer_Info: InitLayers, NewLayerInfo, Fatten, Thin, Dispose [D][O]

- **InitLayers(li)**: clears 102 bytes, NewList(FreeClipRects) and NewList(gs_Head), InitSemaphore(Lock),
  `fatten_count = −1`. Flags = 0. [O]
- **NewLayerInfo()**: AllocMem(102, MEMF_PUBLIC), InitLayers, fattening; failure ⇒ frees, NULL;
  otherwise `Flags |= 1`. Observed: `Flags 0001, fatten 00, extra_size 0042, blitbuff ≠ 0, extra ≠ 0`. [O]
- **FattenLayerInfo**: `fatten_count++`; on the transition −1 → 0, allocates the extra (66 bytes, MEMF_PUBLIC) and
  blitbuff (128 bytes, CHIP); failure ⇒ 0 (beware: the counter stays incremented) [D]; otherwise `Flags |= 1`,
  return 1. **ThinLayerInfo**: `fatten_count−−`; if the old value was ≤ 0, frees extra and
  blitbuff (`extra = NULL`, blitbuff **not** reset to NULL); `Flags &= ~1`. [D][O]
- **DisposeLayerInfo**: Thin then FreeMem(102). Does not check whether layers remain. [D]
- **Layer_Info without Fatten** (1.0/1.1 programs, InitLayers only): each operation fattens
  temporarily then thins; it works (creation/deletion observed on a static
  Layer_Info) and `extra_size` stays at `$42`. [O]

### 5.11 LockLayer, UnlockLayer, LockLayers, UnlockLayers, LockLayerInfo, UnlockLayerInfo — §7.

### 5.12 SwapBitsRastPortClipRect (−126) [D; O]

Swaps the content of `rp->BitMap` within `cr->bounds` with `cr->BitMap` (buffer at column `MinX & 15`,
row 0) by **three** XOR BltBitMap calls (minterm `$6A`, mask `rp->Mask`): screen ^= buffer; buffer ^=
screen; screen ^= buffer. No lock, no list modification. Applied twice, the state returns.
Observed: on a hidden ClipRect of A (smart) under B (simple, area at 0), the screen pixels go to 1
(content of A) then return to 0. [O]

---

## 6. SuperBitMap; SyncSBitMap / CopySBitMap (graphics)

- **SuperClipRect** (`$24`) = pieces of the SuperBitMap located **outside the window** `[Scroll_X,
  Scroll_X + W − 1] × [Scroll_Y, Scroll_Y + H − 1]`, in **SuperBitMap coordinates**, `lobs = BitMap =
  NULL`, split as in §3.1 (left, right, top, bottom; insertion at the head ⇒ list order bottom, top,
  right, left). Rebuilt at creation, after ScrollLayer and SizeLayer. They draw from the 5
  ClipRects of `SuperSaveClipRects`. [D][O]
  Observed: layer 80×50, SuperBitMap 256×128, Scroll (0,0) → `(0,50)-(79,127)`, `(80,0)-(255,127)`;
  Scroll (16,7) → `(16,57)-(95,127)`, `(16,0)-(95,6)`, `(96,0)-(255,127)`, `(0,0)-(15,127)`. [O]
- graphics drawing in a SUPER layer writes into the layer (visible ones + buffers) **and** directly
  into the SuperBitMap for the SuperClipRect pieces (graphics-blitter §5.2). [D]
- **SyncSBitMap(l)** (graphics −444): copies the layer (visible ones from the screen, hidden ones from their
  buffers) **to** the SuperBitMap, layer coordinate (0,0) corresponding to SuperBitMap
  `(Scroll_X, Scroll_Y)`; `SuperBitMap` is set to NULL for the duration of the copy so as not to go back through the
  SuperClipRects. **CopySBitMap(l)** (−450): the reverse, SuperBitMap → layer, same temporary setting
  to NULL. Neither one locks. [D]
- Observed: at creation, the screen pixel at the layer's corner = pixel (0,0) of the SuperBitMap; after
  ScrollLayer(16,7) = pixel (16,7). SizeLayer(+8,+4): no LAYERREFRESH. [O]

---

## 7. Locks [D; O for the counters]

| Function | Effect |
|---|---|
| LockLayer(dummy, l) / UnlockLayer(l) | = graphics' `LockLayerRom`/`UnlockLayerRom` = Obtain/ReleaseSemaphore(`&l->Lock`) |
| LockLayerInfo(li) / UnlockLayerInfo(li) | Obtain/ReleaseSemaphore(`&li->Lock`) |
| LockLayers(li) | LockLayerInfo(li) (**kept**), `LockLayersCount++`, **ObtainSemaphoreList(&li->gs_Head)** (all `Layer.Lock`), on the transition to 1: neutralisation of the ClipRegions |
| UnlockLayers(li) | `LockLayersCount−−`, on the transition to 0: reinstallation of the ClipRegions; ReleaseSemaphoreList; UnlockLayerInfo |

- Probe (nest counts: `LockLayersCount / li->Lock / A->Lock`): LockLayers `1/1/1`, again `2/2/2`,
  UnlockLayers `1/1/1`, `0/0/0`; LockLayer(A) `0/0/1`; LockLayerInfo `0/1/0`. [O]
- **Every stack operation** (Create*, Upfront, Behind, MoveInFrontOf, Move, Size, Delete):
  LockLayerInfo → possible temporary fattening → LockLayers … UnlockLayers → thinning →
  UnlockLayerInfo. During the operation, the task therefore holds `li->Lock` at a level ≥ 2 and all the
  layers. Everything is reentrant for the same task (nested semaphores): an application that holds
  LockLayers can call these functions. [D]
- A layer created during a LockLayers is locked at the same level (§5.1). A layer deleted
  under LockLayers disappears from `gs_Head` with its (held) semaphore: another task waiting on this
  lock would be woken up on freed memory. [D]
- Outside the stack: BeginUpdate…EndUpdate hold `LockLayerRom`; ScrollLayer and InstallClipRegion
  take it for the duration of the call; **WhichLayer, SwapBits, Fatten/Thin take no lock**. [D]
- graphics draws under `Layer.Lock`: a task that holds LockLayers blocks the drawing of the others. [D]

---

## 8. Memory and failures

| Object | Size | Attributes |
|---|--:|---|
| Layer | 160 | MEMF_CLEAR |
| Layer RastPort | 78 | MEMF_PUBLIC (cleared by InitRastPort) |
| ClipRect | 40 | MEMF_CLEAR (or recycled from FreeClipRects, then cleared) |
| Buffer BitMap | 8 + 4 × Depth | MEMF_CLEAR |
| Buffer plane | BytesPerRow × Rows | **MEMF_CHIP** |
| DamageList | Region | NewRegion |
| Layer_Info (NewLayerInfo) | 102 | MEMF_PUBLIC |
| extra / blitbuff | 66 / 128 | MEMF_PUBLIC / **MEMF_CHIP** |
| allocation tracking | 278 per batch of 32 | transient |

- **Transactions** [D; O]: stack operations record each allocation; at the first failure,
  everything allocated since the start is freed and the state of the ClipRects is restored from
  the snapshot (`_cliprects`/`prev`), then the function returns 0/NULL. Observed with CHIP exhausted:
  BehindLayer(A smart behind B simple) = 0, CreateUpfrontLayer(overlapping smart) = NULL, SizeLayer = 0,
  MoveLayer = 0; order, ClipRects, damage and pixels **unchanged**; after freeing CHIP, the same
  BehindLayer succeeds. [O]
- **Fatal alert `$83010000`** (AN_LayersNoMem, bit 31 = dead-end) if a ClipRect cannot be obtained
  during the recomputation of the visible ones **after** commit (the reserve is used first, an allocation
  happens only if there are more pieces than before). [D, not probed]
- BeginUpdate / InstallClipRegion / UnlockLayers: failure ⇒ partial list + `LAYER_CLIPRECTS_LOST`, no
  alert, no rollback. [D]
- Merge §3.4: failure ⇒ merge abandoned, without consequence. [D]

---

## 9. What differs on a real A500

1. **Blitter programmed directly** to clear re-exposed SIMPLE areas (registers BLTCON0,
   first/last word masks, modulos, BLTSIZE; OwnBlitter + WaitBlit before each plane,
   DisownBlitter **without waiting** for the end of the last blit). An "instantaneous" emulator hides the missing
   wait; on a real Agnus, the next processor access must be preceded by a WaitBlit. [D]
2. **All ClipRect buffers and blitbuff in CHIP**, and the screen BitMap must be too: an application
   BitMap in slow RAM (`$C00000`) is not accessible to the blitter (silent corruption). [D]
3. **WaitBlit before freeing a buffer** (restoration then FreeMem, DeleteLayer, EndUpdate, merge):
   without it, the returned CHIP memory can be reallocated while the blitter is still reading it. [D]
4. Unchecked OCS limits: clearing width > 64 words truncated, height > 1024 lines overflowing
   (impossible with normal OCS screens). [D]
5. **CHIP memory pressure**: each hidden part of a SMART window costs `BytesPerRow × Rows ×
   Depth` bytes of CHIP; on 512 KB, a window move can **fail** (MoveLayer = 0, the window
   does not move) — normal behaviour to reproduce, not a fault. The fatal alert §8 remains possible. [D]

---

## 10. Test vectors (real ROM 34.5, FS-UAE)

Probe `tests/layers_probe.s`: private BitMap 320×200×2 (planes pre-filled with `$FF`), Layer_Info by
NewLayerInfo. Format: `L<tag> Flags priority bounds(MinX MinY MaxX MaxY) Scroll front back _cliprects`,
`C`/`S` = ClipRect (`bounds lobs BytesPerRow Rows Depth Flags`), `D` = DamageList (bounds then
relative rectangles), `P x y pen`, `=` returned value. A = SMART (16,10)-(115,59), B = SIMPLE
(60,30)-(159,89), C = SMART (100,20)-(199,49), all by CreateUpfrontLayer, filled pen 1/2/3.

```
0022 0001 00AE 002A                          version 34.1, NegSize 174, PosSize 42
T0  I0 0001 00 00 0042 <blitbuff> <extra> …  NewLayerInfo
T1  P(16,10)=00 P(15,10)=03                  SetRast of the new layer, outside intact
T2  LB 0081 03E7 …                           B simple created in front: LAYERREFRESH, empty DamageList
    LA 0002 03E8 …
      C 003C000A0073001D 0 -                 (60,10)-(115,29) visible
      C 0010000A003B003B 0 -                 (16,10)-(59,59) visible
      C 003C001E0073003B B 000A001E02        hidden by B, buffer 10 bytes × 30 × 2
T3  LB … C 0064001E00730031 C - / C 0074001E009F0031 C -    B split at 115/116 (tiling)
    LA … C 006400140073001D C 0004000A02 / C 003C001E0063003B B 0008001E02
         C 006400320073003B B 0004000A02 / C 0064001E00730031 C 0004001402
T4  =1 UpfrontLayer(A)  P(70,40)=01 P(105,25)=01   restored; B: no damage
T5  =1 BehindLayer(A)   LB … D 000000000037001D 002800140037001D 000000000027001D
    P(70,40)=00 P(105,25)=03                   B simple cleared + damage, C smart restored
T6  =1 UpfrontLayer(B)  LB … D 000000000063001D … 0028000000370013 0038000000630013  (cumulative)
T7  =1 MoveLayer(C,+10,+5)  LC 0002 … 006E001900D10036 ; P(105,25)=01 P(205,35)=03
T8  =1 SizeLayer(C,+20,+10) LC 0082 … D 0000000000770027 0064000000770027 0000001E00630027
    =1 SizeLayer(C,-30,-15) LC 0082 … 006E001900C70031 … D (unchanged)
T9  =1 SizeLayer(B simple,+10,0) LB 0081 … D 00000000006D003B 00000000006D003B
    =1 MoveLayer(B,0,0) ; ScrollLayer(B,3,4) → Scroll 0003 0004, ClipRects unchanged
T10 =1 BeginUpdate(A, damage (10,5)-(29,14)) : LA 0012 … C 001A000F002D0018 0 -
    EndUpdate(A,TRUE) : LA 0002 … _cliprects 00000000, D empty ; BeginUpdate empty damage : ClipRect 00000000
T11 WhichLayer : A B A B C 0 A B
T12 k01/0001/0001 k02/0002/0002 k01/0001/0001 k00/0000/0000 k00/0000/0001 … k00/0001/0000
T13 D BACKDROP|SIMPLE full screen : O B:03E8 C:03E6 A:03E5 D:0000 ; UpfrontLayer(D) =1, order unchanged
    MoveLayerInFrontOf(A,B) =1 : O A B C D ; BehindLayer(A) =1 : O B:03E7 C:03E6 A:03E8 D:03E5
T14 S SUPER (200,120)-(279,169), SuperBitMap 256×128 : S 00000032004F007F, S 0050000000FF007F
    ScrollLayer(S,16,7) : S 00100039005F007F, S 00100000005F0006, S 0060000000FF007F, S 00000000000F007F
T15 =1 DeleteLayer(C) : LA … C 003C001E0073003B B 000A001E02 (merged) ;
    LD 00C1 … D 0074001900C70031 0000000000350004 0036000000530018 ; P(180,30)=00
T17 InitLayers on static Layer_Info : I0 0000 FF 00 0000 … ; CreateUpfrontLayer OK without Fatten
T20 CreateBehindLayer(B simple behind A) : LB 0001 0000 …, C 0032001E006D003B A -, D empty
T21 =1 MoveLayer(B simple,+8,+4) : LB 0081 … D 0000000000950059 (12 rectangles, overflows the layer)
T23 SwapBits on A's hidden one : P(60,40) 00 → 01 → 00
T24 CHIP exhausted : BehindLayer(A)=0, CreateUpfrontLayer=NULL, SizeLayer=0, MoveLayer=0, state unchanged ;
    CHIP returned : BehindLayer(A)=1
```

Proposed non-regression: reproduce these lines (except pointers).

---

## Open points

1. **SUPER layer hidden by another**: the presence of buffers for its hidden parts and their
   interaction with SyncSBitMap/CopySBitMap are deduced, not probed (the probe's layer S was
   not covered).
2. **Alert `$83010000`** and memory failure of BeginUpdate (`LAYER_CLIPRECTS_LOST`): read only, not
   provoked.
3. **Use of `blitbuff`**: never read by layers; a use by graphics or intuition has not been
   searched for.
4. **Effect of Scroll_X/Y on the drawing of a non-SUPER layer**: taken from graphics-blitter §5.2 (deduced),
   not verified here by drawing after ScrollLayer.
5. **MoveLayerInFrontOf** with `other` from another Layer_Info, `other = l` or `other = NULL`: deduced
   only.
6. Exact order of the hidden ClipRects and of the SuperClipRects in configurations with more than three
   layers: not normative, only the cases of §10 are observed.
7. Value returned by Open (the base is indeed obtained by OpenLibrary, but the source register has not been
   verified on the 1.3 exec).
8. Spurious rectangles in the DamageList of a moved SIMPLE layer: observed; the explanation
   (mixed coordinates) is deduced. Nothing indicates that any 1.3 software reads these bounds.
9. Deadlocks between tasks (ObtainSemaphoreList while another task holds a `Layer.Lock` and
   waits for `li->Lock`): not studied.

---

## Clean-room review

- [x] No instruction sequence transcribed or paraphrased; no ROM routine address (only
  LVOs, offsets of public/private structures, sizes, ABI constants and hardware registers).
- [x] The algorithms are described by their **effect** (shapes, orders, values), verified by probe where
  marked [O].
- [x] The cited probe is author code (`tests/layers_probe.s`, header "ASSET DE TEST, PAS du code ROM").
