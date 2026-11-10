# graphics.library 34.1 — GELs and animation (VSprites, Bobs, AnimObs): behavioural spec

> **ANALYSIS** track ("dirty"). Sources: ROM `assets/kick34005.A500` (read only; radare2 and a headless Ghidra
> decompilation kept outside the repository) and **black-box calls on the real ROM** under Amiberry (A500 preset,
> cycle-exact, 512 KB chip + 512 KB slow), 2026-11-04. The calls were injected with the debugger in the task that
> draws the boot "insert disk" picture (stopped at its first `Move`), through a two-word `jsr`/loop stub placed in
> RAM by the debugger, on BitMaps, RastPorts, GelsInfos, VSprites, Bobs and AnimObs allocated with `AllocMem` in
> that context. Collision and animation routines were small RAM stubs that log their stack arguments. No program
> was written for this page; the probe to write on the implementation side is described in §12.
> This document describes **behaviours**, **values**, **orders of operations** and **ABI layouts**. It contains
> no ROM instruction sequence nor routine address.
> It complements: `custom-chips-v34.md` §4.1 (hardware sprites, `SetCollision`, no CLXCON/CLXDAT use),
> `graphics-blitter-v34.md` §9 (QBlit/QBSBlit queues), `graphics-display-v34.md` §5–§6 (MrgCop, copper lists),
> `layers-v34.md` §2 (ClipRects), `workbench-task-v34.md` §3.1/§3.6 (the Workbench drags icons with
> `InitGels`, `AddBob`, `SortGList`, `DrawGList`, `RemIBob`).
>
> **Levels of proof**: **[O]** observed on the real ROM · **[D]** deduced from reading the ROM code (behaviour,
> not code) · **[S]** reasonable assumption, not verified.
>
> Diagram conventions: one line per y (0 at the top), one column per x; `.` = colour 0, otherwise the colour
> digit (plane 0 = bit 0).

## 0. Summary for the implementer

- **All 15 GEL LVOs exist in 1.3**, including `GetGBuffers` (−168), `InitGMasks` (−174) and `FreeGBuffers`
  (−600). Each vector is a thin register-to-stack shim in front of a C routine: arguments are the `.fd` registers,
  the callee preserves D2–D7/A2–A6, and the scratch registers it leaves changed are listed in §1. [O]
- **List**: one doubly linked list between two sentinels set by `InitGels` (head Y = X = −32767, tail Y = X =
  32767). The sort key is the **32-bit signed long at `VSprite.Y`** (Y in the high word, X in the low word), so
  for a same Y a **negative X sorts after every non-negative X** (X behaves as unsigned). `AddVSprite`/`AddBob`
  insert **before** existing GELs with an equal key; `SortGList` is an insertion sort, **stable**. [O]
- **InitMasks**: `CollMask` = OR of all `Depth` planes, row by row; `BorderLine` = OR of the rows of **plane 0
  only**. VSprite (flag `VSPRITE`): `CollMask` row = OR of the two words of the row; `BorderLine` = OR of the
  **first Height words** of `ImageData` (half the lines, both words) — a V34 quirk. [O]
- **DrawGList(rp, vp)**: runs under **Forbid** and the layer's lock; always (re)builds `vp->SprIns` and
  `vp->ClrIns` (32-entry copper lists, reused when present); resets `nextLine[]` to −1 and `lastColor[]` to NULL;
  sets the byte `GfxBase->VBlank` (+$A0) to 1; then walks the list once (Bobs drawn, VSprites given hardware
  sprites), chains the drawn Bobs through `DrawPath`, updates `OldX/OldY/ClearPath` (or swaps them with the
  `DBufPacket`), **queues every blit and waits for all of them** before returning. A ViewPort is mandatory, even
  for Bobs only. [O][D]
- **Bobs**: rectangle `X..X+16·Width−1` × `Y..Y+Height−1`, clipped to the RastPort BitMap then to the layer's
  ClipRects (hidden SMART parts go to the obscured buffers). `SAVEBACK` restores the old background (recursively,
  in reverse drawing order, through `ClearPath`) then saves the new one; `SAVEBOB` keeps the picture (never
  restored); `OVERLAY` cuts the image through `ImageShadow`, otherwise the whole rectangle is replaced. Planes
  not in `PlanePick` are set or cleared from `PlaneOnOff` **through `ImageShadow`** (even without `OVERLAY`; with
  a non-`OVERLAY` Bob whose X is not a multiple of 16 that shape is misplaced, V34 defect, §5.4). [O]
- **Before/After**: `X.After = Y` makes X wait (`BWAITING`) until Y is drawn; when Y is drawn, `Y.Before` (if
  `BWAITING`) is drawn next. A Bob whose `After` points at a Bob not in the list is **never drawn again**. [O]
- **RemIBob(bob, rp, vp)**: restores the Bob's background at once (and, first, every Bob drawn after it that
  overlaps, which disappears until the next `DrawGList`), unlinks it, sets `BOBNIX`. `RemBob` (macro: set
  `BOBSAWAY`) removes it at the next `DrawGList` (two with a `DBuffer`, which must keep alternating the
  BitMaps: the first removal call goes on the BitMap **not** drawn last, §5.7). [O]
- **VSprites**: hardware sprites by pairs, first pass prefers a pair whose other half is busy with **the same
  `SprColors` pointer** (pointer comparison, not values), second pass takes the even sprite of a fully free pair;
  a sprite is free for a VSprite whose top is **> previous top + height + 2** (3 empty lines). Failure sets
  `VSOVERFLOW`, which **is never cleared** afterwards. Copper output detailed in §5.8. [O]
- **DoCollision**: per GEL in list order, the boundary routine (`collHandler[0]`) if `HitMask ≠ 0` (any bit),
  then the pairs with the GELs that follow it while their top is above its bottom. A pair uses
  **first.MeMask & second.HitMask** only (asymmetric), bit 0 ignored, lowest remaining bit = routine index; the
  pixel test is done by the blitter. **V34 defect**: a pair where the second GEL starts **left** of the first is
  tested wrongly; equal-width partial overlaps are never reported (§7.4). Routines get C arguments on the stack
  and no NULL check is made. TOPHIT also counts the two rows just inside the top bound (§7.2). [O]
- **Animate**: per AnimOb (from `*key`): Clock+1, Old = An, An += Vel, Vel += Accel, `AnimORoutine(ob)`; per
  component: timer countdown, sequence switch (links, Before/After and flags carried over, old Bob `BOBSAWAY`,
  `RINGTRIGGER` adds `RingX/RingYTrans`), `AnimCRoutine(comp)`, then position = (An + Trans + 32) >> 6. [O]
- **GetGBuffers** allocates per sequence member: SaveBuffer (BitMap depth × height × width words), optional
  DBufPacket + its buffer, BorderLine, CollMask (= ImageShadow); TRUE/FALSE, no cleanup on failure.
  `FreeGBuffers` frees the same, without NULL checks. [O][D]

## 1. LVOs and calling contract

LVOs checked against `graphics_lib.fd` (amitools) and AROS `rom/graphics/graphics.conf` (bias 30); the same
registers in both. Registers changed on return were measured by calling each vector with marker values in D0–D7
and A0–A5. [O]

| LVO | Function | Arguments | Result | Registers changed on return |
|---:|---|---|---|---|
| −96 | `AddBob` | bob A0, rp A1 | — | D0, A0, A1 |
| −102 | `AddVSprite` | vs A0, rp A1 | — | D0, A0, A1 |
| −108 | `DoCollision` | rp A1 | — | D0, A0; also D1 in most runs and A1 when a pixel test ran |
| −114 | `DrawGList` | rp A1, vp A0 | — | D0, D1, A0, A1 |
| −120 | `InitGels` | head A0, tail A1, gInfo A2 | — | D0 |
| −126 | `InitMasks` | vs A0 | — | D0, D1, A0, A1 |
| −132 | `RemIBob` | bob A0, rp A1, vp A2 | — | D0, D1, A0, A1 |
| −138 | `RemVSprite` | vs A0 | — | A0, A1 |
| −144 | `SetCollision` | num D0, routine A0, gInfo A1 | — | D0, D1, A0 |
| −150 | `SortGList` | rp A1 | — | D0, A0, A1 |
| −156 | `AddAnimOb` | anOb A0, anKey A1, rp A2 | D0 = 0 | D0, A0, A1 |
| −162 | `Animate` | anKey A0, rp A1 | (D0 = 0) [D] | D0, D1, A0, A1 |
| −168 | `GetGBuffers` | anOb A0, rp A1, db D0 | D0 = 1 success / 0 failure | D0, D1, A0, A1 |
| −174 | `InitGMasks` | anOb A0 | D0 = 0 | D0, D1, A0, A1 |
| −600 | `FreeGBuffers` | anOb A0, rp A1, db D0 | none (D0 garbage, 8 observed) | D0, D1, A0, A1 |

- Every argument is used as a full 32-bit value; `SetCollision` uses `num` as a **32-bit index without range
  check** (`num = $10003` wrote 256 KB past the table). [O]
- A6 is not needed by the list functions; `DrawGList`, `RemIBob`, `DoCollision` and `Animate` (through
  `AddBob`) use GfxBase and exec internally, so call them with A6 = GfxBase as usual. [D]
- `DrawGList` and `RemIBob` must run in a **task** (they `Wait` on the blitter signal, §5.9). [D]

## 2. Structures and the fields the ROM uses

Layouts are the public `graphics/gels.h` and `graphics/rastport.h` ones (offsets in hex).

**VSprite (60 bytes)**: NextVSprite +00, PrevVSprite +04, DrawPath +08, ClearPath +0C, OldY +10, OldX +12, Flags
+14, Y +16, X +18, Height +1A, Width +1C (words), Depth +1E, MeMask +20, HitMask +22, ImageData +24, BorderLine +28,
CollMask +2C, SprColors +30, VSBob +34, PlanePick +38 (byte), PlaneOnOff +39 (byte), VUserExt +3A.

**Bob (32 bytes)**: Flags +00, SaveBuffer +02, ImageShadow +06, Before +0A, After +0E, BobVSprite +12, BobComp +16,
DBuffer +1A, BUserExt +1E. **DBufPacket (12)**: BufY +00, BufX +02, BufPath +04, BufBuffer +08.

**AnimComp (38)**: Flags +00, Timer +02, TimeSet +04, NextComp +06, PrevComp +0A, NextSeq +0E, PrevSeq +12,
AnimCRoutine +16, YTrans +1A, XTrans +1C, HeadOb +1E, AnimBob +22. **AnimOb (42)**: NextOb +00, PrevOb +04, Clock
+08 (long), AnOldY +0C, AnOldX +0E, AnY +10, AnX +12, YVel +14, XVel +16, YAccel +18, XAccel +1A, RingYTrans +1C,
RingXTrans +1E, AnimORoutine +20, HeadComp +24, AUserExt +28.

**GelsInfo (38)**: sprRsrvd +00 (byte), Flags +01 (byte), gelHead +02, gelTail +06, nextLine +0A (WORD[8] or
NULL), lastColor +0E (pointer[8] or NULL), collHandler +12 (pointer to 16 routine pointers), leftmost +16,
rightmost +18, topmost +1A, bottommost +1C, firstBlissObj +1E, lastBlissObj +22.

Flag values: VSprite `VSPRITE` 1, `SAVEBACK` 2, `OVERLAY` 4, `MUSTDRAW` 8, system `BACKSAVED` $100, `BOBUPDATE`
$200, `GELGONE` $400, `VSOVERFLOW` $800. Bob `SAVEBOB` 1, `BOBISCOMP` 2, system `BWAITING` $100, `BDRAWN` $200,
`BOBSAWAY` $400, `BOBNIX` $800, `SAVEPRESERVE` $1000, `OUTSTEP` $2000. AnimComp `RINGTRIGGER` 1.

Private uses observed in V34:

- **`GelsInfo.firstBlissObj` / `lastBlissObj`** are **work fields of `DrawGList` and `RemIBob`**: both are cleared
  on entry and used to chain the blitter request blocks of the call; on return `firstBlissObj` is 0 and
  `lastBlissObj` still points at the **freed** last block. A program must not use them. [O]
- **`GelsInfo.Flags`** receives the `DBUFFER` bit (4) of `rp->Flags` (all other bits cleared) every time a Bob is
  blitted through a layer; it selects QBlit vs QBSBlit (§5.9). [D]
- `MUSTDRAW` and `BOBISCOMP` are never tested. `VUserExt`, `BUserExt`, `AUserExt`, `BobComp`, `HeadOb`, `PrevSeq`
  are never read. [D]
- `VSprite.Depth` is used by the VSprite copper output (rows skipped × Depth words, §5.8) and by `InitMasks`; Bob
  drawing uses the **BitMap depth** for the plane loop, never `VSprite.Depth`. [D][O]

## 3. List management

### 3.1 InitGels (−120) [O]

- `gInfo->gelHead = head`, `gInfo->gelTail = tail`.
- head: Next = tail, Prev = 0, **ClearPath = tail**, OldY = OldX = Y = X = −32767 ($8001); DrawPath, Flags untouched
  (0 in fresh memory).
- tail: Next = 0, Prev = head, OldY = OldX = Y = X = 32767 ($7FFF).
- If `collHandler` is not NULL, its entry 0 (the boundary routine) is set to NULL; the other 15 are untouched. [D]
- `nextLine`, `lastColor`, `sprRsrvd`, the bounds and the bliss fields are not touched.

### 3.2 AddVSprite (−102) and AddBob (−96) [O]

- `AddBob(bob, rp)` clears the system bits of `bob->Flags` (keeps the low byte) and then does
  `AddVSprite(bob->BobVSprite, rp)`.
- `AddVSprite(vs, rp)` clears the system bits of `vs->Flags` (keeps the low byte), finds in `rp->GelsInfo`'s list
  the first GEL whose key is **≥** the new key, inserts the new one **before** it, and sets OldY/OldX = Y/X.
  DrawPath and ClearPath are not touched.
- Key = the long at Y (signed compare). Test (insertion order A(5,10) B(5,3) C(5,10) D(5,−2) E(4,0) F(−3,10)
  G(5,32766), given as (Y,X)): list F E B C A G D. C lands before A (equal key); D (X = −2) after G (X = 32766).

### 3.3 RemVSprite (−138) and RemBob [O]

- `RemVSprite(vs)` unlinks the node (`prev->Next = next`, `next->Prev = prev`). The node's own links are left
  as they were; nothing is drawn or restored.
- `RemBob` is the `gels.h` macro (sets `BOBSAWAY`); the removal happens in `DrawGList` (§5.7).

### 3.4 SortGList (−150) [O]

- Walks the list from the first GEL to the tail; each GEL whose key is below its predecessor's is moved back to
  just after the first GEL (going backwards) whose key is ≤ its own; each GEL whose key is above its successor's
  is moved forward to just before the first GEL whose key is ≥ its own. [D]
- Result: sorted by the long key, **stable** for equal keys (observed C, A, G, all at (1,10), kept their order). [O]

## 4. InitMasks (−126) [O]

For a GEL **without** `VSPRITE`:

- `BorderLine[c]` (c = 0..Width−1) = OR over the `Height` rows of **plane 0** of `ImageData` (word column c).
  Pixels present only in planes ≥ 1 are **not** in BorderLine (vector §11.2).
- `CollMask` (Height × Width words) = word-by-word OR of the `Depth` planes.

With `VSPRITE` (two words per line, `Width` normally 1):

- `CollMask[r]` = word 0 | word 1 of line r, for r = 0..Height−1.
- `BorderLine` is computed by the same column walk as for a Bob, i.e. OR of the **first `Height × Width` words of
  `ImageData`**: for Width 1, both words of the first Height/2 lines. Lines below are ignored (vector §11.2).

`InitMasks` writes into the buffers that `BorderLine` and `CollMask` point to (no allocation). It does not touch
`ImageShadow` (the Workbench and `GetGBuffers` make `ImageShadow` = `CollMask`).

## 5. DrawGList (−114)

### 5.1 Order of operations [D][O]

1. `Forbid()`; if `rp->Layer`, obtain the layer's semaphore (the same lock as `LockLayerRom`).
2. Clear `firstBlissObj` and `lastBlissObj`.
3. Prepare `vp->SprIns` and `vp->ClrIns`: when NULL, allocate a CopList header (34 bytes, MEMF_CLEAR) and a buffer
   of 32 instructions; when present, rewind it (pointer back to the start, count 0) — the same lists are reused
   from call to call [O]. A list that fills up is extended by another 16-instruction block chained from it.
   **If either preparation fails, nothing else is done** (no drawing), apart from the unlock and Permit.
4. If `nextLine` is not NULL, its 8 words are set to −1; if `lastColor` is not NULL, its 8 longs to NULL.
5. `GfxBase->VBlank` (+$A0) := 1 [O] (read back as 1 in the debugger-injected runs, read while the machine was
   stopped). From a CLI process (probe G9a/G9b, byte read and printed after `DrawGList` returned and after
   other serial output) it read **0** both times [O]: something clears it later, presumably at the next vertical
   blank; an implementation must not expect a caller to still see 1 (Open point 4).
6. **Pass 1**, list order from the first GEL: a VSprite (flag `VSPRITE`) gets its hardware sprite (§5.8); a Bob
   is handled as in §5.2 (with the removal cases of §5.7). The drawn Bobs are chained through `DrawPath`,
   starting at the head sentinel; the last one's `DrawPath` = tail. A Bob that is not drawn keeps its old
   `DrawPath`.
7. **Pass 2**, list order: for each GEL still `BACKSAVED` (a Bob left waiting, §5.3) the background is restored;
   `BOBUPDATE` becomes `BACKSAVED`; for each GEL with a `VSBob`: clear `BWAITING` and `BDRAWN`, then either
   (no DBuffer) OldX = X, OldY = Y, ClearPath = DrawPath, or the double-buffer swap of §5.6. VSprites without a
   Bob keep OldX/OldY.
8. Terminate both copper lists with a WAIT on line 10000, position 255 (end of list).
9. Wait for every queued blit of this call, free the request blocks (§5.9).
10. Release the layer lock, `Permit()`.

After the call, `vs->Flags` has `BACKSAVED` for each drawn `SAVEBACK` Bob and `bob->Flags` has neither `BDRAWN`
nor `BWAITING` (cleared in pass 2) [O]. The pixels are final when the call returns (no `WaitBlit` needed) [O].

### 5.2 One Bob in pass 1 [D][O]

Let B be the Bob and V its VSprite. Rectangle = `V.X .. V.X+16·Width−1`, `V.Y .. V.Y+Height−1`.

1. If `B.After` is not NULL and `B.After` is not `BDRAWN` yet: set `BWAITING` on B and stop (B will be drawn
   right after `B.After`, if `B.After.Before` = B; otherwise never in this call).
2. Clip the rectangle against the RastPort BitMap (`0..BytesPerRow·8−1` × `0..Rows−1`, in the RastPort's own
   coordinates). Entirely outside: set `GELGONE` on V; otherwise clear it.
3. If V has `SAVEBACK`:
   - if V is `BACKSAVED`, restore its old background (§5.3);
   - for every GEL of the list that is `BACKSAVED` and whose **old** rectangle (OldX/OldY) intersects B's **new**
     rectangle, restore it (§5.3);
   - if B is visible: save the background under the new (clipped) rectangle into `B.SaveBuffer`, set
     `BOBUPDATE` on V.
4. If visible: append V to the DrawPath chain and draw the image (§5.4).
5. `B.Flags`: clear `BWAITING`, set `BDRAWN` (also for a `GELGONE` Bob).
6. If `B.Before` is not NULL and is `BWAITING`, process `B.Before`'s VSprite now (step 1 onwards).

Observed [O]: two overlapping Bobs without links are drawn in list order (the lower one covers the upper one);
with `A.After = B` and `B.Before = A`, B is drawn first and A over it, the chain is head → B → A → tail and
`B.ClearPath = A`, `A.ClearPath = tail`.

### 5.3 Background restore [D][O]

Restoring a GEL G (in `DrawGList`, `RemIBob` and the removal paths):

1. First, along G's `ClearPath` chain (G.ClearPath, its ClearPath, … until the list tail), every GEL that is
   `BACKSAVED` and whose old rectangle intersects G's old rectangle is restored (recursively, same rule). Since
   ClearPath follows the drawing order, the Bobs drawn after G come back off before G.
2. If G is `BACKSAVED`: clear `BACKSAVED`; then, **unless the Bob has `SAVEBOB`**, copy `SaveBuffer` back to
   the old rectangle (OldX/OldY, clipped against the BitMap, then through the layer).

Consequences [O]: a `SAVEBOB` Bob leaves a copy of itself at each position (paintbrush), and `RemIBob` does not
erase it; a Bob without `SAVEBACK` is never saved nor restored (it leaves a trail and `RemIBob` leaves it on
screen); restoring a Bob also erases every overlapping Bob drawn after it.

### 5.4 Planes, PlanePick/PlaneOnOff, OVERLAY, rp->Mask [O][D]

One blit per plane of the **RastPort BitMap** (`BitMap.Depth` planes); with B the image plane, S the
`ImageShadow`, D the screen:

| Plane p of the BitMap | `rp->Mask` bit p clear | in `PlanePick`, not OVERLAY | in `PlanePick`, OVERLAY | not in `PlanePick`, `PlaneOnOff` bit 1 | not in `PlanePick`, bit 0 |
|---|---|---|---|---|---|
| result | untouched | D := B over the whole rectangle | D := B where S, D elsewhere | D := 1 where S | D := 0 where S |

- Image planes are taken **in order**, one per plane that is actually blitted (`Mask` bit set and in
  `PlanePick`); an image plane is `Height × Width` words, planes consecutive.
- **`rp->Mask` shifts the sources**: with Mask = 5 on 3 planes, an image whose planes are (1, 0, 1) gives plane 0
  = image plane 0 and plane 2 = **image plane 1**. The save and restore use the same counting: the save buffer
  slot is indexed by the plane number while the source plane is taken by count, so with a Mask hole a save stores
  the wrong plane (observed: slot 2 received BitMap plane 1). [O]
- **The PlaneOnOff fill uses `ImageShadow` even without `OVERLAY`** (correct when X is a multiple of 16).
  **V34 defect**: for a non-`OVERLAY` Bob, the shadow is not shifted to X mod 16, so the PlaneOnOff shape lands
  wrong (shifted to the next word, rows offset) — vectors §11.4. `OVERLAY` Bobs are correct at every X. [O]
- `ImageShadow` must be valid whenever `OVERLAY` is set **or** a plane of the BitMap is not in `PlanePick`. [D]
- Save buffer layout: for each blitted plane, `Height` rows of `Width` words, holding the pixels
  `X .. X+16·Width−1` of the rectangle (shifted to word alignment); size needed = BitMap depth × Height × Width ×
  2 bytes. Nothing outside it was written (guards checked). [O]

### 5.5 Clipping and layers [O][D]

- Without a layer: clipped to the BitMap (vectors §11.5: a Bob at (−5,−2) draws its last two rows from x = 0; a Bob
  at (25,6) on a 32 × 8 BitMap keeps 7 columns and 2 rows; a Bob entirely outside gets `GELGONE`, is not chained,
  and is not saved).
- With `rp->Layer`: coordinates are layer-relative (bounds MinX/MinY added, Scroll_X/Scroll_Y subtracted); each
  blit (save, draw, restore) is split over the layer's ClipRects: visible ones go to the BitMap, obscured ones of
  a SMART layer go to their own BitMap (the hidden part shows after the front layer goes away), SIMPLE hidden parts
  are skipped; with a SuperBitMap the parts in the SuperClipRects go to the SuperBitMap too. Observed with a SMART
  layer (8,4)-(55,27) behind a SMART layer (30,0)-(63,15): clipping on the left, bottom and right edges of the
  layer, the hidden part written into the obscured buffer, and `RemIBob` restoring both parts. [O]
- The BitMap clip of step 2 is done first, in RastPort coordinates, against the full BitMap. [D]

### 5.6 Double buffering (`B.DBuffer ≠ NULL`) [O]

In pass 2, for a Bob with a DBufPacket P, instead of the plain update:

- OldX := P.BufX, P.BufX := X; OldY := P.BufY, P.BufY := Y; ClearPath := P.BufPath, P.BufPath := DrawPath;
- `B.SaveBuffer` and `P.BufBuffer` are exchanged;
- V's `BACKSAVED` takes the value of B's `SAVEPRESERVE`, and `SAVEPRESERVE` takes the old `BACKSAVED`.

So each buffer restores, two frames later, what was saved in the same BitMap. The application alternates
`rp->BitMap` (and should set `DBUFFER` in `rp->Flags`, §5.9). The DBufPacket is **not initialised** by the ROM
(`GetGBuffers` neither): after the first frame OldX/OldY/ClearPath hold whatever P contained, harmless only
because `BACKSAVED` is then 0 (vectors §11.6). [O]

Consequence: after the call that drew frame N on BitMap A, `OldX/OldY`, `SaveBuffer` and `BACKSAVED` describe
frame N−1, i.e. the **other** BitMap B, which is the BitMap the next call is expected to use. The ROM does not
know which BitMap was used last; it only trusts the alternation. Every later restore (a normal frame, or the
removal of §5.7) writes that state into whatever `rp->BitMap` the next call gets. Calling `DrawGList` twice in a
row on the same BitMap therefore writes B's saved background into A at B's old position (observed, §11.6). [O]

### 5.7 Removal (`BOBSAWAY`) [O]

In pass 1, a Bob with `BOBSAWAY`:

- no DBuffer, or already `OUTSTEP`: restore its background if `BACKSAVED`, unlink it, set `BOBNIX`;
- with a DBuffer, first time: restore if `BACKSAVED`, set `OUTSTEP`; it is **not drawn**, stays in the list and
  goes through the pass-2 swap, so the next `DrawGList` erases it on the remaining BitMap and sets `BOBNIX`.

Both removal restores use the ordinary state of §5.3: the current `OldX/OldY` and `SaveBuffer`, i.e. the
DrawGList state that §5.6 left for the **next BitMap of the alternation**. There is no special path that restores
from the DBufPacket side, and no check of `rp->BitMap`. [O] (§11.6, both calls observed)

- The first removal call must use the BitMap that the next normal frame would have used (the one **not** drawn
  last); it erases the Bob there. Its pass-2 swap then brings back the other BitMap's position and buffer, with
  `BACKSAVED` taken from `SAVEPRESERVE` (set: the Bob was saved there), so the second call, on the other BitMap,
  erases it there too. Both BitMaps end clean. [D] (follows from the swap rule, which the observed figures
  confirm; the correctly alternated sequence itself was not run, see §11.6)
- Called on the BitMap drawn last (as in the observed run of §11.6), each removal writes the other BitMap's
  saved background at the other BitMap's old position, and the Bob stays visible on both BitMaps. [O]

Observed flags: single buffer → $0C00 after one call; double buffer → $2400 then $2C00 (`OUTSTEP|BOBNIX|BOBSAWAY`);
`vs->Flags` `BACKSAVED` is set again after the first removal call (from `SAVEPRESERVE`) and clear after the second. [O]

### 5.8 VSprites [O][D]

**Allocation** (pass 1, list order). Let `top` = the VSprite's top after clipping against the RastPort BitMap
(same clip as Bobs; entirely outside → `GELGONE`, nothing emitted). Usable sprites = `gInfo->sprRsrvd` minus
`GfxBase->SpriteReserved` (+$A6; 1 at the boot screen: sprite 0, the pointer). Sprite n is **free** if usable and
`nextLine[n] < top`.

1. For the pairs (0,1), (2,3), (4,5), (6,7) in that order: if **exactly one** sprite of the pair is free, take it
   when the VSprite has no `SprColors`, or the other sprite's `lastColor` is NULL, or equals the VSprite's
   `SprColors` **pointer**.
2. Otherwise, the first pair whose two sprites are free: take the **even** one.
3. Otherwise set `VSOVERFLOW` (never cleared later, even when a sprite becomes available; only `AddVSprite` clears
   it) and emit nothing.

On success `lastColor[n] := SprColors` (when not NULL) and `nextLine[n] := top + clipped height + 2`, so the next
VSprite on sprite n must start at least 3 lines below the last line of this one. `nextLine`/`lastColor` NULL are
not supported by the allocator (it reads them). [O][D]

**Copper output**, all in the ViewPort's lists (instructions = OpCode word 0 MOVE / 1 WAIT, then two words):

- `SprIns`: WAIT(line = the previous `nextLine[n]`, i.e. −1 for the first use, h 0); MOVE SPRnPTH, MOVE SPRnPTL with
  `ImageData + (rows clipped at the top) × Depth` words; MOVE SPRnPOS; MOVE SPRnCTL.
- POS/CTL: VSTART = clipped top + `ActiView->DyOffset` (the ViewPort's DyOffset is **not** added); VSTOP = VSTART
  + clipped height; HSTART = X (halved when `vp->Modes` has HIRES; not clipped) + `ActiView->DxOffset`; encoded as
  in custom-chips §4.1 (POS = VSTART[7:0]·256 + HSTART[8:1]; CTL = VSTOP[7:0]·256 + VSTART8·4 + VSTOP8·2 +
  HSTART0). LACE is not taken into account.
- The MOVE destination words hold the register offset **minus $1000** (observed $F128/$F12A for SPR2PTH/L, $F150/
  $F152 for SPR2POS/CTL, $F1AA for COLOR21). [O]
- `ClrIns`, only for a VSprite with `SprColors`: WAIT(clipped top − 1, 0), then MOVE of `SprColors[0..2]` to
  COLOR(17 + 4·(n/2)) .. COLOR(19 + 4·(n/2)).
- Observed (View DyOffset 44, DxOffset 129): VSprite (X 50, Y 10, H 5) on sprite 2 → `W(-1) M(SPR2PTH) M(SPR2PTL)
  M(SPR2POS,$3659) M(SPR2CTL,$3B01)`; colours → `W(9) M(COLOR21..23)`. HIRES ViewPort, X 101, Y −2, H 6 on sprite 1
  → POS $2C59, CTL $3001, pointer = ImageData + 8 bytes. [O]

VSprites are not chained in `DrawPath`, never saved or restored, and keep OldX/OldY. [D][O]

### 5.9 Blit queue, beam sync, signals [D]

- Each Bob blit (save, draw, restore; one per ClipRect piece) is a request block of 126 bytes taken from pools of
  8 (1014 bytes, MEMF_PUBLIC, chained from `firstBlissObj`); it processes the BitMap planes one per call of its
  blitter routine and, at the end, signals the calling task with **SIGF_BLIT** (bit 4).
- Queued with **QBSBlit** (beam-synchronised) on the line `Y + Height + vp->DyOffset + ActiView->DyOffset` (plus
  the layer's MinY − Scroll_Y), unless `rp->Flags` has `DBUFFER`, then with **QBlit**.
- At the end the caller `Wait`s SIGF_BLIT until every block is done, then frees the pools (and the temporary
  edge-mask copies made for some clipped pieces). A missing pool block (no memory) silently skips that blit.
- Not observed: the beam wait itself (the dumps were read after the call returned).

## 6. RemIBob (−132) [O][D]

`RemIBob(bob, rp, vp)`:

1. clears `firstBlissObj` / `lastBlissObj`;
2. if the VSprite is `BACKSAVED`, restores it as in §5.3 — first every overlapping `BACKSAVED` GEL on its
   ClearPath chain (they vanish too: observed with A drawn under B, `RemIBob(A)` erased B, B's `BACKSAVED` cleared,
   B redrawn by the next `DrawGList`);
3. unlinks the VSprite (`RemVSprite`), sets `BOBNIX` on the Bob;
4. waits for its blits (§5.9).

No Forbid and **no layer lock** are taken [D]. `vp` is used for the beam-sync line, so it must be valid [D].
Other Bobs are **not** redrawn. A Bob whose `After` is the removed Bob is never drawn again (§5.2, observed). The
Workbench uses it to drop an icon after a drag (workbench-task §3.6).

## 7. DoCollision (−108) and SetCollision (−144)

### 7.1 Order [O][D]

`gInfo = rp->GelsInfo`; `collHandler` must not be NULL (it is read without test). For each GEL G from the first to
the last:

1. if `collHandler[0]` is not NULL and `G.HitMask ≠ 0` (**any bit**, not only bit 0): compute the boundary flags
   (§7.2) and, if not 0, call `collHandler[0](G, flags)`;
2. for each GEL H after G, stopping at the first one with `H.Y ≥ G.Y + G.Height`: if the boxes overlap in X
   (`H.X − G.X < 16·G.Width` when H.X ≥ G.X, else `G.X − H.X < 16·H.Width`), m = `(G.MeMask & H.HitMask) & ~1`;
   if m ≠ 0 and the pixel test (§7.4) finds a common pixel, call `collHandler[i](G, H)` with i = index of the
   lowest set bit of m (1..15). The routine pointer is **not** checked for NULL.

Routines are called with **C arguments on the stack** (two longs: first argument at 4(sp)); the register values
at the call are incidental. Observed sequence for three mutually overlapping GELs P, Q, S (list order):
`(P,Q) (P,S) (Q,S)`. [O]

### 7.2 Boundary flags [O]

Bounds = `topmost`, `bottommost`, `leftmost`, `rightmost` of the GelsInfo. Flags: TOPHIT 1, BOTTOMHIT 2,
LEFTHIT 4, RIGHTHIT 8.

- **TOPHIT**: only when `Y < topmost`; set if any `CollMask` pixel lies in the rows **Y .. topmost + 1** — two
  rows more than the rows above the bound (V34 quirk): Y 4 / topmost 5 with a pixel on y 6 hits, on y 7 does not;
  Y = topmost never hits.
- **BOTTOMHIT**: when `Y + Height − 1 > bottommost`; set if a `CollMask` pixel lies on a row **> bottommost**.
- **LEFTHIT**: when `X < leftmost`; set if `BorderLine` has a pixel in the columns **X .. leftmost − 1**.
- **RIGHTHIT**: when `X + 16·Width − 1 > rightmost`; set if `BorderLine` has a pixel in a column
  **> rightmost**.
- Left/right use `BorderLine` only (plane 0 for a Bob, §4); top/bottom use `CollMask`.

### 7.3 MeMask / HitMask [O]

- Asymmetric: only the **earlier** GEL's `MeMask` against the **later** GEL's `HitMask` (P me 2 / Q hit 2 → call;
  P hit 2 / Q me 2 → none).
- Bit 0 is ignored for pairs; MeMask $0C & HitMask $0E → routine 2; $8001 & $8001 → routine 15.

### 7.4 Pixel test and its V34 defect [O][D]

The test ANDs the two `CollMask`s with the blitter over the intersection of the two rectangles (no destination,
result from the blitter zero flag; it owns the blitter and waits for it). It is correct when the second GEL (later
in the list) starts at or right of the first (`H.X ≥ G.X`): boxes overlapping without common pixels give no call;
a 1-column overlap is found.

**Defect** when `H.X < G.X`: the first-word mask is computed from `(H.X − G.X) mod 16` and H's mask is read one
word to the left, so

- two GELs of the **same width** that overlap partially with H left of G are **never** reported (observed for
  overlaps of 1, 2, 3, 8, 12 and 15 columns);
- with G full (16 wide at X 26) and H 32 wide at X 18, only H pixels in columns 18..25 (outside G!) trigger a
  call; at X 20 only 20..25; with G at 32 and H at 24 only 24..31 (single-pixel sweeps, §11.7).

A compatible implementation must decide whether to reproduce this; programs written for 1.3 cannot rely on
these pairs being reported.

### 7.5 SetCollision [O]

`collHandler[num] := routine` (num as a long index, no check). It does not touch anything else
(custom-chips §4.1: no CLXCON/CLXDAT access anywhere).

## 8. Animation

### 8.1 AddAnimOb (−156) [O]

`AddAnimOb(ob, key, rp)`: `ob->PrevOb = NULL`, `ob->NextOb = *key`, the old first object's `PrevOb = ob`,
`*key = ob` (insertion at the head). Then for each component of the `HeadComp`/`NextComp` chain: `Timer :=
TimeSet` and `AddBob(comp->AnimBob, rp)`. The other members of each sequence are not touched (Timer, list). The
Bobs keep their VSprite X/Y (0 in the test, so they sort at (0,0) until the first `Animate`). Returns 0.

### 8.2 Animate (−162) [O]

For each AnimOb from `*key` along `NextOb`:

1. `Clock += 1`; `AnOldY = AnY`, `AnOldX = AnX`; `AnY += YVel`, `AnX += XVel`; then `YVel += YAccel`,
   `XVel += XAccel` (the position uses the old velocity).
2. If `AnimORoutine` ≠ NULL: call it with `ob` (C argument on the stack).
3. For each component C along `NextComp` (from `HeadComp`):
   - if `C.Timer ≠ 0`, decrement it; if it reaches 0, switch to N = `C.NextSeq` (Timer 0 never switches):
     - when N's Bob differs from C's Bob: N.Bob's `Before`/`After` := C.Bob's, the Bobs they point to are re-linked
       to N.Bob, and N.Bob's whole `Flags` word := C.Bob's;
     - N's VSprite X/Y := C's; C.Bob gets `BOBSAWAY`; `AddBob(N.Bob, rp)` (inserted at C's position, the list is
       then unsorted); C's VSprite X/Y := −32767; N's VSprite ClearPath/DrawPath := C's;
     - N replaces C in the component chain (`PrevComp`/`NextComp` both ways), `N.Timer := N.TimeSet`,
       `HeadComp := N` if C was the head;
     - if N has `RINGTRIGGER`: `AnX += RingXTrans`, `AnY += RingYTrans`;
     - the rest of this step uses N;
   - if the component's `AnimCRoutine` ≠ NULL: call it with the component;
   - its VSprite: `X = (AnX + XTrans + 32) >> 6`, `Y = (AnY + YTrans + 32) >> 6` (arithmetic shift, 6 fraction
     bits, rounded).

Observations: the ring translation applies to the components processed **after** the switching one in the same
call; earlier ones were positioned with the old AnX/AnY (vector §11.8). The removed Bob stays in the list (at
Y = X = −32767 once sorted) until `DrawGList` removes it (two calls with DBuffers). Only `AddBob` is used; the
caller must still call `SortGList` before `DrawGList`. [O]

Hazard [D, not run]: a one-member sequence (`NextSeq` = itself) with a non-zero `TimeSet` re-adds a Bob that is
already in the list (double insertion).

## 9. GetGBuffers, FreeGBuffers, InitGMasks

For every member of every sequence (outer loop along `NextComp` from `HeadComp`, inner loop along `NextSeq` until
back to the first member or NULL), with `bpr = 2·Width`, `plane = Height · bpr`, `save = BitMap.Depth · plane` (the
`rp->BitMap` depth):

- **GetGBuffers(ob, rp, db)** [O]: `SaveBuffer` := AllocMem(save, MEMF_CHIP|MEMF_PUBLIC); if `db`: `DBuffer` :=
  AllocMem(12, MEMF_PUBLIC) and `DBuffer->BufBuffer` := AllocMem(save, MEMF_CHIP|MEMF_PUBLIC); `BorderLine` :=
  AllocMem(bpr, CHIP|PUBLIC); `CollMask` := AllocMem(plane, CHIP|PUBLIC) and `ImageShadow` := the same pointer.
  Nothing is cleared (no MEMF_CLEAR), the DBufPacket fields are left as allocated. Returns 1; on the first failure
  returns 0 at once **without freeing** what was obtained. Measured for 3 members, depth 2, 16 × 3, db = 1:
  144 bytes chip and 48 bytes public taken.
- **FreeGBuffers(ob, rp, db)** [O][D]: FreeMem of the same blocks with the same sizes (DBuffer's buffer and packet
  when `db`), **no NULL test**, pointers left as they are. The sizes are recomputed from the current BitMap depth
  and VSprite sizes; the save buffers are freed whichever of the two a DrawGList swap left in `SaveBuffer`.
  Returned the same amounts in the test.
- **InitGMasks(ob)** [O]: `InitMasks` on every member's VSprite; returns 0.

## 10. Workbench and other users

- The Workbench drags icons with one Bob in the screen's GelsInfo (workbench-task §3.1 #5, §3.6): `AddBob`,
  `SortGList`, `DrawGList(screen rp, screen vp)`, `RemIBob`. The vp argument is the screen's ViewPort, which is why
  DrawGList always rebuilds its SprIns/ClrIns (empty lists) during a drag. [D]
- The order of `DoCollision` routines, `BorderLine` content and the allocator rules matter to games using GELs;
  none of the analysed programs (octamed, sysinfo, caesar, monkey) calls the GEL vectors. [D]

## 11. Test vectors (real ROM, observed)

### 11.1 InitGels sentinels

head (60 bytes) after `InitGels` on cleared memory: `Next=tail Prev=0 DrawPath=0 ClearPath=tail OldY=$8001
OldX=$8001 Flags=0 Y=$8001 X=$8001`; tail: `Next=0 Prev=head DrawPath=0 ClearPath=0 OldY=OldX=Y=X=$7FFF`.

### 11.2 InitMasks

- Bob W 2, H 3, D 2; plane 0 rows `8000 0000 / 0000 0000 / 0000 0001`, plane 1 rows `0000 00F0 / 0000 0F00 /
  0000 0000` → BorderLine `8000 0001`, CollMask `8000 00F0 / 0000 0F00 / 0000 0001`.
- VSprite (flag 1) W 1, H 4, words `8001 4002 / 2004 1008 / 0810 0420 / 0240 0180` → CollMask `C003 300C 0C30 03C0`,
  BorderLine `F00F`.

### 11.3 Bob draw / move / restore (64 × 32, 2 planes, background plane 0 = $33, plane 1 = $0F per byte)

Bob W 1, H 4, D 2, flags SAVEBACK|OVERLAY, PlanePick 3, image plane 0 `0180 03C0 07E0 0FF0`, plane 1 `0000 0180
03C0 0000`, ImageShadow = CollMask, at (5,3):

```
 3 ..112233..111133..112233
 4 ..112233..113313..112233
 5 ..112233..133331..112233
 6 ..112233.11111111.112233
```
SaveBuffer = `6666 6666 6666 6666 E1E1 E1E1 E1E1 E1E1`; vs Flags $0106, DrawPath = ClearPath = tail, bob Flags 0.
Moved to (20,10) + SortGList + DrawGList: rows 3–6 back to the background, the Bob at rows 10–13. OVERLAY
cleared + DrawGList: the 16 × 4 rectangle (x 20..35) replaced (transparent pixels 0). `RemIBob`: whole picture =
background; vs Flags $0002, bob Flags $0800, list empty.

### 11.4 PlanePick / PlaneOnOff (3 planes, background 0, ring image `F000 9000 9000 F000`, 1 plane)

(pick, onoff, flags) at x = 0, 8, 16, … : (1,0,ov) → ring of 1; (2,0,ov) → 2; (4,6,ov) → 6; (0,7,ov) → 7;
(0,7,SAVEBACK at x 48) → 7, inside 0; in isolation, non-OVERLAY at x 0, 16 or 32 with (2,5), (1,6), (4,3) → a
correct ring of 7. Non-OVERLAY, PlanePick 1, PlaneOnOff 2, depth 2, background 0, rows y 1..4:

```
x 0  (correct)          x 4                       x 24
3333                    ....1111........2..2      ........................1111....2..2
3..3                    ....1..1........2..2      ........................1..1....2..2
3..3                    ....1..1........2222      ........................1..1....2222
3333                    ....1111                  ........................1111

x 33
.................................3331...........2
.................................1.21...........2
.................................1.21...........2
.................................3331
```
The same with OVERLAY gives a correct ring of 3 at every x. The misplaced shape can land on a neighbouring Bob
(observed: a non-OVERLAY Bob at x 24 put plane-2 pixels inside a correct Bob at x 32).

### 11.5 rp->Mask and clipping

- 3 planes, background plane 1 all set, Mask 5, image planes (FF00×4, 0×4, FF00×4) at (2,1): pixels 2..9 of rows
  1..4 = colour 3 (plane 2 got the zero image plane); SaveBuffer slots `0…0 / 0…0 / FFFF…` (slot 2 = BitMap plane 1).
- 32 × 8, 1 plane: Bob `FFFF 8001 8001 FFFF` at (−5,−2) → row 0 pixel 10, row 1 pixels 0..10; at (25,6) → row 6
  pixels 25..31, row 7 pixel 25; at (40,2) → nothing, Flags $0406.

### 11.6 Double buffering (48 × 6, 1 plane, BM1 = $AA, BM2 = $55, Bob FF00 × 3, DBufPacket preset $1111/$2222/$33333333)

| frame | BitMap, X | vs Flags | Old (Y,X) | ClearPath | bob Flags | visible |
|---|---|---|---|---|---|---|
| 1 | BM1, 2 | $0002 | (4369, 8738) | $33333333 | $1000 | BM1 at 2 |
| 2 | BM2, 10 | $0102 | (1, 2) | tail | $1000 | BM1 at 2, BM2 at 10 |
| 3 | BM1, 20 | $0102 | (1, 10) | tail | $1000 | BM1 at 20 only, BM2 at 10 |
| 4 | BM2, 30 | $0102 | (1, 20) | tail | $1000 | BM1 at 20, BM2 at 30 only |
| RemBob 1 | BM2 | $0102 | (1, 30) | tail | $2400 | still in list; see below |
| RemBob 2 | BM1 | $0002 | (1, 30) | tail | $2C00 | out of list; see below |

The two RemBob rows were observed with the probe's G8 section (`tests/gels_probe.s`), Bob at Y 1, 1 word × 3
rows, which (following the BitMap column of an earlier version of this table) calls the removal on **BM2 then
BM1**, i.e. starting on the
BitMap drawn last by frame 4. That breaks the alternation (§5.6), and **neither BitMap ends clean** [O]:

- after RemBob 1 (BM2): BM2 columns 20–35 of rows 1–3 hold BM1's background pattern ($AA: even columns set),
  i.e. the background saved on BM1 at X 20 (frame 3), written at X 20; columns 36–45 still show the right part of
  the frame-4 Bob (36–37 set, 38–45 clear). BM1 unchanged (Bob at X 20). Old becomes (1, 30) by the swap.
- after RemBob 2 (BM1): BM1 columns 30–45 of rows 1–3 hold BM2's background pattern ($55: odd columns set), i.e.
  the background saved on BM2 at X 30 (frame 4), written at X 30; columns 20–29 still show the left part of the
  frame-3 Bob (20–27 set, 28–29 clear). BM2 unchanged from the previous row. The Bob is unlinked (empty list).
- Guards around both planes intact after every call.

With the alternation respected (RemBob 1 on **BM1**, RemBob 2 on **BM2**), the rule of §5.7 gives: RemBob 1
restores X 20 on BM1 from BM1's own buffer → BM1 clean; RemBob 2 restores X 30 on BM2 from BM2's buffer → BM2
clean; same flags as the table. [D] — not run. Probe to add on the implementation side (described, not written by
this track): a G8 variant identical to the current one except that the two removal calls use BM1 then BM2, dumping
both BitMaps after each call; expected: BM1 equal to its $AA background after the first call, BM2 equal to its $55
background after the second, `vs->Flags` $0102 then $0002, `bob->Flags` $2400 then $2C00.

### 11.7 DoCollision (bounds left 10, right 50, top 5, bottom 20; 16-wide GELs, `collHandler[i]` = logger i)

| GEL | expected call |
|---|---|
| Y 4, pixel row 2 (y 6) | `[0](G, 1)` |
| Y 4, pixel row 3 (y 7) | none |
| Y 5, row 0 | none |
| Y 18 H 4, row 2 (y 20) / row 3 (y 21) | none / `[0](G, 2)` |
| X 8, pixel column 9 / 10 (any row) | `[0](G, 4)` / none |
| X 40, pixel column 51 / 50 | `[0](G, 8)` / none |
| X 4, Y 2, all set, HitMask 1 or 2 | `[0](G, 5)` |
| same, HitMask 0, or collHandler[0] NULL | none |

Pairs (bounds 0..63 × 0..31, both 16 × 4 all set unless stated; P first in the list):

| P | Q | call |
|---|---|---|
| (10,5) me 2 | (14,7) hit 2 | `[1](P,Q)` |
| (10,5) hit 2 | (14,7) me 2 | none |
| (10,5) `FF00` me 2 | (18,7) `00FF` hit 2 | none |
| (10,5) me $0C | (14,7) hit $0E | `[2](P,Q)` |
| (10,5) me 2 | (25,6) hit 2 (1 column) | `[1](P,Q)` |
| (26,5) me 2 | (11..25,6) hit 2 | none (defect) |
| (26,5) me 2 | (26,6) hit 2 | `[1](P,Q)` |
| (10,5) me 2 | (14,9) or (26,6) hit 2 | none (adjacent) |
| P (26,5); Q 32 wide at 18, one pixel at column c | | call only for c = 18..25 |
| P (18,5) 32 wide all set; Q (26,6) one pixel at c | | call for every c = 26..41 |

### 11.8 Animation

AnimOb: An (Y,X) = (640,320), Vel (32,100), Accel (0,−6), Ring (192,1280). Components: c1 TimeSet 0, Trans 0;
c2a TimeSet 2, Trans (256,512), NextSeq c2b; c2b TimeSet 3, Trans (256,544), `RINGTRIGGER`, NextSeq c2a.
Chain c1 → c2a; `bob_c1.Before = bob_c2a` and `bob_c2a.After = bob_c1` set after AddAnimOb; all three AnimCRoutines
and the AnimORoutine are loggers.

| call | Clock | An (Y,X) | XVel | c1 vs (Y,X) | active c2 | c2 vs (Y,X) | routine calls |
|---|---|---|---|---|---|---|---|
| AddAnimOb | 0 | (640,320) | 100 | (0,0) | c2a T2 | (0,0) | — |
| Animate 1 | 1 | (672,420) | 94 | (11,7) | c2a T1 | (15,15) | ob, c1, c2a |
| Animate 2 | 2 | (896,1794) | 88 | (11,8) | c2b T3 | (18,37) | ob, c1, c2b |
| Animate 3 | 3 | (928,1882) | 82 | (15,29) | c2b T2 | (19,38) | ob, c1, c2b |

After Animate 2: c2a's Bob $0400 at (−32767,−32767), c1.NextComp = c2b, c2b.PrevComp = c1, bob_c2b.After = bob_c1,
bob_c1.Before = bob_c2b. GetGBuffers(db 1) = 1; FreeGBuffers returned the same 144 + 48 bytes.

## 12. Probe to write (implementation side): `tests/gels_probe.s` + `.sh`

Model: `tests/gtext_probe.s/.sh` (HUNK executable, `-kick1hunks`, launched by the startup-sequence of an OFS disk
made with xdftool, no SetPatch; results on the serial port between `GEL debut` and `GEL fin`). Everything through
the public LVOs, A6 = GfxBase (LayersBase for layers). Hex output, one line per item.

**Setup**: chip blocks for the BitMap planes with 64-byte guards before/after; InitBitMap, InitRastPort,
`rp_BitMap`; GelsInfo, head and tail (60 bytes each, MEMF_CLEAR) + InitGels; a 64-byte `collHandler` table; a
ViewPort with InitVPort (DyOffset 0); `nextLine` (16 bytes) and `lastColor` (32 bytes) for the VSprite tests.
Collision/animation routines: 16 small routines that append `(index, 4(sp), 8(sp))` to a RAM log, printed after
the call. Dumps: one line per row, planes as hex, plus the guard check.

1. **G0 registers**: call each LVO with marker values in D0–D7/A0–A5 and print the changed registers (expect §1).
2. **G1 list**: InitGels → print head/tail (§11.1); the AddVSprite sequence of §3.2 → order F E B C A G D; change
   A, C, G to (1,10) → SortGList → F C A G E B D; RemVSprite(E).
3. **G2 InitMasks**: the two cases of §11.2.
4. **G3 Bob**: §11.3 (draw, SaveBuffer, flags, move + sort + draw, OVERLAY off, RemIBob).
5. **G4 planes**: §11.4 and the Mask case of §11.5.
6. **G5 save modes**: SAVEBOB and no-SAVEBACK Bobs drawn at x 0, 10, 20 then RemIBob (three copies stay).
7. **G6 Before/After**: two overlapping non-OVERLAY Bobs, without then with `A.After = B, B.Before = A` (B under
   A, chain head → B → A); RemIBob(B) then DrawGList (A never comes back); then the unlinked case of §6 (B comes
   back at the next DrawGList).
8. **G7 clipping**: §11.5 edge Bobs; optional layer case of §5.5 (CreateUpfrontLayer SMART behind SMART, dump,
   DeleteLayer of the front one, dump).
9. **G8 double buffer**: §11.6 table; the removal calls must alternate correctly (first on BM1, then BM2) to show
   both BitMaps clean; the current BM2-then-BM1 order shows the misuse case of §11.6.
10. **G9 VSprites**: sprRsrvd $FC, the seven VSprites a–g of the analysis run (X 50/100/150/200/250 at Y 10 H 5,
    then (60,18,3) and (300,17,3); colours: separate 3-word arrays C1 C1 C2 C1 C3 C1 C2); print flags (a b c f
    $0001; d e g $0801), `nextLine` (−1 −1 23 −1 17 −1 17 −1) and the instructions of `vp->SprIns`/`ClrIns`
    (sprite numbers 2, 4, 6, 2; WAIT lines −1 −1 −1 17; colour WAITs 9 9 9 17). The POS/CTL values depend on the
    View offsets: print `ActiView->DxOffset/DyOffset` with them. Then sprRsrvd $0C with VSprites at Y 10 H 5,
    Y 17, Y 18, Y 19 (H 2): sprites 2, 3, 2, overflow.
11. **G10 collisions**: the tables of §11.7.
12. **G11 animation**: §11.8 (AnimOb, three components, GetGBuffers with db 1 and the AvailMem deltas, InitGMasks,
    AddAnimOb, four Animates with positions, timers, links and the routine log, FreeGBuffers).

Run it on the real ROM through an analysis agent (`GT_ANALYSIS=1`-style switch) and on ours; compare the logs.

## 13. CLI probe G9-G11 and VSprites on a real display (2026-11-10)

Runs of the real ROM (Amiberry A500 preset, cycle-exact, 512 KB chip + 512 KB slow). Two programs of the
implementation track were run **unchanged** as black boxes: `tests/gels_probe.s` (through `tests/gels_probe.sh`
with `GE_ANALYSIS=1`) and `tests/vsprite_test.s` (six 16 × 12 VSprites on a 320 × 200 × 2 custom screen, rows at
Y 30 and Y 60, `SortGList`/`DrawGList`/`MrgCop`/`LoadView`/`WaitTOF` per frame for 120 frames). Copper lists were
read from RAM with the debugger after the calls; screenshots were looked at. For the LACE case the screen's
`NewScreen.ViewModes` word in the test program's data was set to LACE with the debugger before `OpenScreen`
(no code change).

### 13.1 Why the CLI probe stopped in G9b [O]

The stop is a **defect of the probe**, not of the ROM: its CopList printer keeps the `CopIns` pointer in a register
that its own decimal print of `Count` overwrites (the serial character routine uses that register), then walks the
instructions from the last printed character code. With `Count` 20 the printed pointer is even and the dump shows
low-memory garbage (`M4EF9,00FC` repeated, as in the G9a log); with `Count` 15 it is odd and the walk takes an
address error, which ends the run. The lists themselves are correct when read with the debugger (below). The
probe needs its pointer saved across the count print (implementation side); with the four G9 dumps skipped by the
debugger, the run completes and prints G10, G11 and the G0 table up to "GEL fin".

### 13.2 G9 results read with the debugger [O]

Sprites 0-1 reserved (`sprRsrvd` $FC unless stated), View DyOffset 44, DxOffset 129, image at a chip address
ending in `…490`. `W(v,h)` = WAIT, `M(dest,data)` = MOVE as stored in the CopList (destination word as stored).

| Case | SprIns | ClrIns | nextLine | Flags |
|---|---|---|---|---|
| G9a (seven VSprites a–g, §12 item 10) | `W(-1,0) M(F128) M(F12A) M(F150,3659) M(F152,3B01)`, `W(-1,0)` + sprite 4 `POS 3672`, `W(-1,0)` + sprite 6 `POS 368B`, `W(17,0)` + sprite 2 `POS 3E5E CTL 4101`: 20 instructions | `W(9,0)` + COLOR21-23, `W(9,0)` + COLOR25-27, `W(9,0)` + COLOR29-31, `W(17,0)` + COLOR21-23: 16 | −1 −1 23 −1 17 −1 17 −1 | a b c f `$0001`, d e g `$0801` |
| G9b (`sprRsrvd` $0C; Y 10 H 5, then Y 17/18/19 H 2) | sprite 2 `POS 3659 CTL 3B01`; sprite 3 (`M(F12C) M(F12E) M(F158,3D68) M(F15A,3F01)`); `W(17,0)` + sprite 2 `POS 3E77 CTL 4001`: 15 | none (Count 0) | −1 −1 22 21 −1 −1 −1 −1 | a b c `$0001`, d `$0801` |
| **G9c** HIRES ViewPort, X 101, Y −2, H 6 | `W(-1,0) M(F128) M(F12A, image+8) M(F150,2C59) M(F152,3001)`: 5 | Count 0 | −1 −1 **6** −1 … | `$0001` |
| **G9d** LACE ViewPort, `vp.DyOffset` 20, X 50, Y 10, H 5 | `W(-1,0) M(F128) M(F12A) M(F150,3659) M(F152,3B01)`: 5, **identical to G9a's first VSprite** | Count 0 | −1 −1 17 −1 … | `$0001` |

- G9c confirms §5.8: the two rows above the BitMap are clipped (pointer + 8 bytes = 2 rows × 2 words), VSTART =
  0 + View DyOffset = $2C, VSTOP = $30 (4 visible rows), HSTART = 101 / 2 + 129 = 179 (`POS` low byte $59, CTL bit 0
  = 1). `nextLine` = clipped top 0 + clipped height 4 + 2 = 6.
- G9d confirms that neither `vp.DyOffset` nor LACE changes what DrawGList writes: same POS/CTL, same WAIT −1, same
  `nextLine` 17 as the non-LACE ViewPort at DyOffset 0.
- G10 and G11 printed by the CLI probe agree with §11.7 and §11.8 (all collision cases, the three defect sweeps,
  Animate 1-4, GetGBuffers 1, FreeGBuffers returning 144 chip + 48 other bytes). The G0 table printed by the probe
  lists fewer changed registers for AddAnimOb, Animate, GetGBuffers, InitGMasks and FreeGBuffers than §1; the probe
  calls them with its minimal G0 objects, so §1 (measured with complete objects) is kept.

### 13.3 MrgCop merge of the VSprite lists, non-LACE ViewPort at DyOffset 0 [O]

`tests/vsprite_test.s` after its 120 frames (screen ViewPort DyOffset 0, View DyOffset 44): the six VSprites are
shown at Y 30 and Y 60 with **their own colours** (red/green/blue frames on the first row, yellow/cyan/magenta on
the second), exactly as intended. The merged LOF list (no SHF list, View not LACE) contains, in order:

1. `WAIT(43,0)` — the SprIns WAIT −1 merged as View.DyOffset + vp.DyOffset + (−1) = 43 — then the first-row
   sprite MOVEs: SPR2PTH/L, `SPR2POS $4A86`, `SPR2CTL $5601`, the same for sprites 4 and 6;
2. the ViewPort's own display instructions (colours, DIWSTRT … BPLxPT), `WAIT(44,0)` + BPLCON0;
3. `WAIT(73,0)` + COLOR21-23/25-27/29-31 of the first row (ClrIns WAIT 29 + 44);
4. `WAIT(88,0)` + the second-row sprite MOVEs (`SPRnPOS $68..`, `CTL $7401`) (SprIns WAIT = previous `nextLine` 44,
   + 44);
5. `WAIT(103,0)` + the second-row colours (ClrIns WAIT 59 + 44); then the end-of-screen BPLCON0 and the end WAIT.

Rules shown by this list:

- The `$F000`-style destination words are emitted as the plain register (destination & `$1FE`): `$F128` → SPR2PTH,
  `$F1AA` → COLOR21. They are emitted in the LOF list of a non-LACE View even though their high bits are set; the
  `$8000`/`$4000` field rule of `graphics-display-v34.md` §5.2 does not drop them [O].
- SprIns/ClrIns WAITs are ViewPort-relative: line = View.DyOffset + vp.DyOffset + VWaitPos, merged in line order
  with the ViewPort's own list (graphics-display §5.2) [O].
- SPRxPOS/CTL are **absolute** (VSTART = Y + View.DyOffset only, §5.8), so the picture is right only while
  vp.DyOffset is 0 [O, next section].

### 13.4 ViewPort DyOffset ≠ 0 on screen [O]

Same program, then the custom screen dragged down by its title bar (screen ViewPort DyOffset 0 → 25); intuition
remakes the display with the VSprite lists left by the last DrawGList.

- Merged list: the first-row sprite MOVEs now follow `WAIT(68,0)` (43 + 25) and still hold `SPR2POS $4A86` (VSTART
  74); the first-row colours wait for line 98; the second-row sprite MOVEs wait for line 113 and still hold VSTART
  $68 (104).
- Screen: the **first-row VSprites stay at the same absolute height** (View lines 74-86) while the screen has
  moved down by 25 lines, so they now sit over the screen's title bar; they are drawn in the **default sprite
  colours** (greys) because their colour MOVEs come at line 98, after them. The **second-row VSprites are not
  shown at all**: their pointer/POS/CTL are loaded at line 113, after their VSTART line 104 has passed.
- So the [S] of open point 3 is confirmed: on 1.3 a ViewPort with DyOffset ≠ 0 shows VSprites at the wrong height,
  with wrong colours, and sprites reused lower down may vanish.

### 13.5 LACE ViewPort on screen [O]

Same program with the screen opened LACE (320 × 200, so the View becomes LACE and has LOF and SHF lists):

- The SprIns/ClrIns WAIT lines are **halved** like the ViewPort's other WAITs (graphics-display §5.2, vp LACE):
  first-row sprites at line 43 (−1 stays −1, + 44), first-row colours at 58 (29 / 2 + 44), second-row sprites at 66 (44 / 2 +
  44), second-row colours at 73 (59 / 2 + 44). The POS/CTL values are **not** halved: VSTART 74 and 104 as in the
  non-LACE run.
- Effect: the second-row sprite MOVEs (line 66) reload the same hardware sprites before the first row's VSTART (74)
  is reached, so **the first-row VSprites never appear**; the second row appears at its non-LACE absolute height
  (line 104), i.e. at about twice its intended distance from the top of the interlaced picture; in the screenshot
  it is striped (every other line) and paler than the intended colours, which fits the damaged LOF list described
  below.
- The VSprite MOVEs (`$F1xx` destinations) are present in the **SHF** list too: neither high bit of the destination
  word keeps them out of either field's list [O].
- Side observation, list sizes [O][?]: the SHF list was a 47-entry block (`MaxCount` 47) while the instruction
  stream written for the SHF field was 85 entries long; its last 38 entries lay in the first 38 entries of the
  LOF list's block (`MaxCount` 101), which therefore started at the first-row colour WAIT (line 58) and no longer
  contained the LOF field's sprite and display set-up (the rest of the LOF block still held the tail of its own
  set-up). The SHF block seems to have kept the size computed by an earlier MrgCop (before
  the VSprite lists existed) instead of growing. Whether this is a 1.3 defect of MrgCop's SHF reallocation or an
  effect of the test calling MrgCop on intuition's View every frame was not settled. An implementation must size
  both lists from the current instruction count.

### 13.6 Rules for an implementation (VSprites, as 1.3 behaves) [O][D]

1. DrawGList writes sprite POS/CTL from Y + View.DyOffset (and X, halved for HIRES, + View.DxOffset); it ignores
   vp.DyOffset and LACE (G9c, G9d).
2. The SprIns/ClrIns WAITs are ViewPort lines: MrgCop adds View.DyOffset + vp.DyOffset and halves VWaitPos for a
   LACE ViewPort, exactly as for the ViewPort's other lists.
3. MrgCop emits the `$F000 | register` MOVEs as plain MOVEs to `register & $1FE`, in LOF and (for a LACE View) in
   SHF.
4. Consequences to reproduce, not to fix, if strict 1.3 behaviour is wanted: VSprites on a dragged-down screen keep
   their absolute height and lose their colours/lower reuses; on a LACE screen the first VSprite row of a reused
   sprite is lost.

## Open points

1. **Beam synchronisation** (§5.9): QBSBlit vs QBlit chosen from `rp->Flags` DBUFFER is deduced; the effect on
   display timing was not observed.
2. **SuperBitMap layers**: the SuperClipRect pass of §5.5 is deduced only.
3. **VSprites on screen**: answered 2026-11-10 (§13.3-§13.5): MrgCop emits the $F000-style MOVEs as plain register
   MOVEs in LOF and SHF, adds View + ViewPort DyOffset (halved WAITs for LACE) to the WAITs only, so a ViewPort with
   DyOffset ≠ 0 or LACE shows VSprites at the wrong height [O]. Still open: the SHF list size seen in the LACE run
   (§13.5) [?].
4. **`GfxBase->VBlank` := 1**: who reads and clears it (the vertical-blank server?) was not traced. Observed:
   1 right after the call under the debugger, 0 when the CLI probe printed it after the call (G9a, G9b).
5. **Collision defect formula** (§7.4): the "one word to the left" description fits all sweeps but was derived
   from three of them; other width combinations (H wider than G by more than one word) are [S].
6. **Before without After** (or the reverse): only the paired use was observed; a Bob with only `After` set is
   expected to wait forever [D].
7. **One-member sequence in Animate** (§8.2 hazard) and `GetGBuffers` failure paths: deduced, not run.
8. **Error paths of DrawGList** (copper list or request block allocation failure): deduced, not run.
9. The observations were made with debugger-injected calls in the boot picture's task. The CLI probe (§12) was
   run once on the real ROM (2026-11-04) for the double-buffer question: its G8 rows are in §11.6 and agree with
   §5.6/§5.7; the run stopped printing in G9b (during the `SprIns` dump) and never reached "GEL fin" within
   300 s, so G10/G11 were not obtained from it. Resolved 2026-11-10 (§13.1-§13.2): a defect of the probe's CopList
   printer (address error on an odd pointer); with those dumps skipped, G9a-G9d (read with the debugger), G10, G11
   and G0 were obtained and agree with this page.

## Clean-room review

Review of 2026-11-04.

- [x] No 68000 instruction sequence transcribed or paraphrased, no disassembly or decompiler excerpt, no ROM
  routine or data address. Numbers are public LVOs, public structure offsets (`gels.h`, `rastport.h`,
  `gfxbase.h`, `view.h`, `copper.h`, `clip.h`), custom-register names, exec signal and memory flags, sizes in
  bytes, and coordinates of our own test objects.
- [x] The algorithms of §3–§9 are stated as observable rules (which GEL is drawn, saved, restored or called, in
  which order, with which values), checked against black-box runs; where a rule comes only from reading the code
  it is marked [D].
- [x] The pixel diagrams, save-buffer contents, copper instructions and tables are **outputs** of the real ROM on
  test inputs (test vectors), not ROM data. The copper destination words and the colour/register numbers were read
  from lists the ROM built for our VSprites.
- [x] No ROM data (images, tables) is reproduced; no blitter minterm constants are given, only the logical effect
  of each blit.
- [x] No probe code was written by the analysis track; §12 describes one in words.
- [x] Review of 2026-11-10 (§13): only outputs of the real ROM on our two test programs (copper instructions
  built for our VSprites, merged lists read from RAM, screenshots); no ROM instruction or address. The two
  programs were run unchanged; the LACE variant changed one data word of the test program's NewScreen through the
  debugger. No code was written by the analysis track.
