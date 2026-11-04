# graphics.library 34.1 — Move, Draw, PolyDraw: behavioural spec

> **ANALYSIS** track ("dirty"). Sources: ROM `assets/kick34005.A500` (read only, radare2; disassembly notes kept
> outside the repository) and **black-box calls on the real ROM** under Amiberry (A500 preset, cycle-exact,
> 512 KB chip + 512 KB slow), 2026-11-04. The calls were injected with the debugger: the ROM was stopped at the
> first `Move` issued by the boot "insert disk" picture (a task context), the library vectors were then called
> one by one through a two-word return trampoline placed in RAM by the debugger, on BitMaps and RastPorts
> allocated with `AllocMem` in that context, and the planes were read back after `WaitBlit`. No program was
> written for this page; the probe to write on the implementation side is described in §11.
> This document describes **behaviours**, **values**, **orders of operations** and **ABI layouts**. It contains
> no ROM instruction sequence nor routine address.
> It complements: `graphics-area-v34.md` (AreaEnd edges, RectFill outline, minterm use by BltPattern),
> `graphics-blitter-v34.md` (§2 WaitBlit, §3 OwnBlitter/DisownBlitter, §5.2 ClipRect walk), `layers-v34.md`
> (§2.2 ClipRect, §2.4 layer RastPort, §4 refresh types).
>
> **Levels of proof**: **[O]** observed on the real ROM · **[D]** deduced from reading the ROM code (behaviour,
> not code) · **[S]** reasonable assumption, not verified.
>
> Diagram conventions: one line per y (0 at the top), one column per x; `.` = colour 0, otherwise the colour
> digit (plane 0 = bit 0). Test vectors are in §10.

## 0. Summary for the implementer

- LVOs (checked against the `graphics_lib.fd` order, bias 30): **Move −240** `(rp A1, x D0, y D1)`, **Draw −246**
  `(rp A1, x D0, y D1)`, **PolyDraw −336** `(rp A1, count D0, polyTable A0)`. Only the **low words** of D0/D1 are
  used. No return value. [D][O]
- **Move** writes `cp_x/cp_y`, sets `FRST_DOT` (bit 0 of `rp_Flags`) and sets the byte at **RastPort +$1F** (the
  header's `dummy` byte, see §2) to 15. Nothing else. [O]
- **Draw** draws from `cp` to `(x, y)` **both ends included**, Bresenham from the **start point** with ties
  stepping the minor axis: the pixels of A→B and B→A **differ** when a tie occurs (§4). `cp` = `(x, y)` afterwards.
  [O]
- **Line pattern**: pixel number k of a line (k = 0 at the start) uses bit `(c − k) mod 16` of `LinePtrn`, where c
  is the **byte at +$1F**; after the line, that byte is decreased by the **major length** (pixel count − 1), so
  the shared vertex of two consecutive Draws uses the same bit in both. Move, **SetAPen, SetBPen and SetDrMd**
  reset it to 15. [O]
- **COMPLEMENT continuation**: when `FRST_DOT` is clear (a Draw continues a previous one) and `DrawMode` is
  exactly 2, the first pixel is inverted once more by the processor before the line is drawn, so a shared vertex
  ends up inverted **once**. `DrawMode` 6 (COMPLEMENT|INVERSVID) does not get this. [O]
- **No clipping without a layer**: coordinates are turned into a linear address; x < 0 or x ≥ width wraps to the
  neighbouring row, y outside the BitMap writes outside the plane (§6). [O]
- **With a layer**: drawn ClipRect by ClipRect (visible, SMART buffer, SIMPLE hidden parts lost), exact clipping
  (the pixels are those of the unclipped line), **but** three V34 defects that a compatible clone must know (§7):
  a line entirely inside one ClipRect decreases the pattern byte **twice**; clipped pieces take their pattern
  phase from the **other** byte (+$1E, the documented `linpatcnt`) with a layer-offset error; clipped pieces do
  not clear `FRST_DOT` and never skip the first dot in COMPLEMENT. [O]
- **Blitter**: line mode for every line except rightward horizontal lines (dy = 0, dx ≥ 0), which use an area
  blit of one row; the call **returns before the blit ends** (no final WaitBlit). Lines longer than 1024 pixels
  are truncated to `length mod 1024` pixels. [O]
- **PolyDraw** = `count` calls of **Draw through the library vector** (A6 must be GfxBase), count taken as an
  unsigned word: 0 draws nothing. [D][O]
- Open point 4 of graphics-area is answered: **AreaEnd's edges are Draw's pixels** for the same vertex order (§9).
  [O]

## 1. Calling contract

### 1.1 Registers [O]

Measured by calling each vector with marker values in every register:

| Call | Registers changed on return | Notes |
|---|---|---|
| Move | none | D0/D1/A0/A1 are preserved too |
| Draw | **D0, D1, A0** | A0 = the custom chip base, D0/D1 = scratch values; A1 (rp) preserved; D2–D7/A2–A6 preserved |
| PolyDraw | **D0, D1, A0** | A1 and the table pointer argument register are not significant on return (A1 observed preserved); D2–D7/A2–A6 preserved |

D0 is **not** a result: it holds whatever the last blitter programming left (observed small values related to
the blit size). A caller must not use it. [O]

### 1.2 Arguments [D][O]

- x and y are **signed 16-bit** words; the high words of D0/D1 are ignored (PolyDraw count `$10001` behaved as
  count 1). [O]
- `rp_BitMap` must be valid; the number of planes processed is `BitMap.Depth` (a depth of 0 is not supported:
  it would loop over 256 planes). [D]
- PolyDraw: `count` is an **unsigned word**; a negative word (e.g. −1) means 65535 points. [D]
- A6 must be GfxBase for PolyDraw (it calls Draw through the vector, so a `SetFunction` of Draw is honoured) and
  for Draw on a layered RastPort (it calls `LockLayerRom`/`UnlockLayerRom` through their vectors). [D]

## 2. RastPort fields

Offsets are those of `graphics/rastport.h` (1.3): `$18 Mask`, `$19 FgPen`, `$1A BgPen`, `$1C DrawMode`,
`$1E linpatcnt`, `$1F dummy`, `$20 Flags` (`FRST_DOT` = bit 0, `ONE_DOT` = bit 1), `$22 LinePtrn`,
`$24 cp_x`, `$26 cp_y`, `$28 minterms[8]`.

**The two pattern bytes** [O]: V34 keeps the running pattern counter of the no-layer line engine in the byte at
**+$1F**, not in `linpatcnt` (+$1E):

| Byte | Written by | Read by |
|---|---|---|
| +$1F | Move (= 15), SetAPen/SetBPen/SetDrMd (= 15), InitRastPort (= 0), every Draw (decreased, §5.2; twice in one layer case, §7.3) | the unclipped line engine (no layer, or a line entirely inside one ClipRect) |
| +$1E (`linpatcnt`) | InitRastPort (= 0); **nothing in Move/Draw/Set*Pen** | only the **clipped** layer engine (§7.4) |

Observed: Move after writing 3 into +$1F gives 15 there; a Draw after writing 9 into +$1E and 3 into +$1F uses
the phase 3 (pixels x 3, 4, 19, 20, 35, 36 with pattern `$8001`) and leaves +$1E at 9. A program that uses the
public `SetDrPt` macro (which sets `linpatcnt` and FRST_DOT) gets its phase reset by Move or SetAPen anyway. [O]

**Fields written by each call** [O]:

| Call | cp | Flags | +$1F | other |
|---|---|---|---|---|
| Move(x, y) | (x, y) | FRST_DOT set | 15 | — |
| Draw(x, y), no layer | (x, y) (written **before** drawing) | FRST_DOT cleared | − major length | — |
| Draw(x, y), layer | (x, y), layer coordinates, written **after** drawing | see §7 | see §7 | — |
| PolyDraw | last point | as the last Draw | sum of the Draws | — |
| SetAPen/SetBPen/SetDrMd | — | FRST_DOT **set** | **15** | pen/mode and `minterms[]` |
| InitRastPort | (0, 0) | 0 | 0 (and +$1E = 0) | LinePtrn `$FFFF`, FgPen `$FF`, AOlPen `$FF`, BgPen 0, Mask `$FF`, DrawMode JAM2, all minterms `$CA` |

So a Draw right after InitRastPort without Move starts at pattern bit 0 and with FRST_DOT clear; after any
Set*Pen/SetDrMd it behaves as after a Move. [O]

**Read**: `Mask` (planes whose bit is clear are skipped entirely), `minterms[plane]` (one per plane, computed by
SetAPen/SetBPen/SetDrMd from FgPen/BgPen/DrawMode: observed `$CA`/`$0A` for JAM2 pen bit 1/0 with BgPen bit 0,
`$3A` for JAM2 pen bit 0 / BgPen bit 1, `$EA`/`$2A` for JAM1, `$6A` COMPLEMENT, `$9A` COMPLEMENT|INVERSVID),
`DrawMode` (only the test "exactly 2" of §5.3), `LinePtrn`, `Flags` (FRST_DOT, ONE_DOT). FgPen/BgPen are not
read by Draw itself, only through the minterms. AOlPen, AreaPtrn, TmpRas are not used. [D][O]

## 3. Move (−240) [D][O]

`cp_x = x`, `cp_y = y` (words), `Flags |= FRST_DOT`, byte +$1F = 15. No drawing, no blitter, no layer lock, no
register changed. Coordinates are layer coordinates when the RastPort has a layer; no check. [O]

## 4. Pixel set of a line [O]

Let `dx = x1 − x0`, `dy = y1 − y0` (start = old cp), major axis = the one with the larger absolute delta
(`|dx| = |dy|`: y is taken as the major axis, which only matters for ONE_DOT), `M` = major delta, `m` = minor
delta (absolute values).

- Exactly **M + 1 pixels** are drawn, one per major-axis step, **both ends included**.
- Walk from the **start**: error `e = 2m − M`; after plotting a pixel, if `e ≥ 0` the next pixel also steps on the
  minor axis and `e += 2(m − M)`, otherwise only the major axis advances and `e += 2m`.
- Hence **ties (`e = 0`) step the minor axis**, and because the walk starts at the start point, A→B and B→A
  give **different pixels whenever a tie occurs**. Examples: (0,0)→(2,1) = (0,0) (1,1) (2,1); (2,1)→(0,0) =
  (2,1) (1,0) (0,0). (10,10)→(16,13) = (10,10) (11,11) (12,11) (13,12) (14,12) (15,13) (16,13); the reverse
  gives (11,10) (13,11) (15,12) instead. Lines without ties (e.g. (0,0)–(6,4), (0,0)–(5,2), (3,0)–(0,5)) are
  identical both ways. Horizontal, vertical and 45° lines are always symmetric.
- **Single point** (`x1 = x0`, `y1 = y0`): one pixel is drawn (subject to §5.3 in COMPLEMENT).

All observed vectors are listed in §10.1; they match this rule in all 21 cases tried, in all eight octants.

## 5. Rendering without a layer

### 5.1 Two engines [D][O]

- **Rightward horizontal lines** (`dy = 0`, `dx ≥ 0`, including the single point), when `ONE_DOT` is clear: an area
  blit of **one row** over the words touched, first/last word masks at x0 and x1, channels C and D with the
  plane's minterm, B = `LinePtrn` rotated so that pixel x0 uses bit c (constant for the whole row, which gives the
  same "bit (c − k)" rule as the line engine). [D]
- **Every other line** (leftward horizontals included, and rightward horizontals when ONE_DOT is set): blitter
  **line mode**, one blit per plane, A = the single-dot data, B = `LinePtrn` with the texture shift = c mod 16,
  C/D = the plane, minterm = `minterms[plane]`; the hardware Bresenham parameters are those of §4 (initial error
  `2m − M`, sign flag when negative). Height of the blit = M + 1. [D]
- Both engines give the same pixels and pattern phases (rightward and leftward horizontal lines observed
  symmetric, pattern `$FF00` observed consistent). [O]
- **Length limit**: the blit height field is 10 bits, so a line of `M + 1 > 1024` pixels draws only
  `(M + 1) mod 1024` pixels from the start (0 → 1024). Observed: (0,0)→(1,1100) drew rows 0..76 only (77 = 1101
  mod 1024). The horizontal engine is likewise limited to 64 words (1024 pixels) per row [D]. [O]

### 5.2 Pattern (`LinePtrn`) [O]

- Pixel k (k = 0 at the start point, counted along the major axis) is "on" when bit `(c − k) mod 16` of
  `LinePtrn` is 1, c = byte +$1F at the call. After Move, c = 15: the first pixel uses **bit 15** (MSB).
- After the Draw, +$1F is decreased (8-bit wrap) by **M**, not M + 1: the end pixel of one Draw and the first
  pixel of the next Draw use the **same bit**. Observed: Move(0,8), Draw(10,8), Draw(10,18), Draw(30,18) with
  `$FF00` — x 0..7 on, the vertical starts at bit 5 (off), rows 14..18 on, the last horizontal starts at bit 11
  and draws x 10..13 and 22..29 (§10.2 B4).
- The phase is **per line, along the major axis**, not tied to screen x: a leftward line starts its pattern at
  its start point (right end). Diagonals advance one bit per major step.
- Pattern bits that are 0: **JAM1** leaves the pixel unchanged, **JAM2** writes BgPen, **COMPLEMENT** leaves it
  unchanged. **INVERSVID** inverts the pattern before use: JAM1|INVERSVID draws FgPen where the bits are 0;
  JAM2|INVERSVID writes FgPen for 0 bits and BgPen for 1 bits; COMPLEMENT|INVERSVID inverts where the bits are 0
  (so with the default solid pattern, modes 4 and 6 draw **nothing**). [O]
- With JAM2 the BgPen pixels overwrite: a second Draw starting on the end pixel of the first rewrites that pixel
  with the new phase (only relevant when the phase is inconsistent, §7.3).

### 5.3 First dot and COMPLEMENT [O][D]

- `Draw` tests and **clears FRST_DOT**. If it was set (first Draw after Move or Set*Pen), or if `DrawMode` is not
  exactly 2, the line is drawn whole.
- If FRST_DOT was clear **and DrawMode = 2** (COMPLEMENT without INVERSVID): for each plane enabled by `Mask`, the
  processor first inverts the start pixel in that plane, then the line (start pixel included) is blitted. Net
  effect: the start pixel is inverted **iff its pattern bit is 0**. With a solid pattern a polyline's vertices
  are inverted once instead of twice. Observed:
  - (2,2)→(12,2)→(12,12): vertex (12,2) set; Move between the two Draws → vertex back to 0.
  - (20,2)→(30,2)→(20,2): only (30,2) stays set (the return trip clears x 20..29).
  - (20,6)→(30,6)→(30,6): the zero-length second Draw changes nothing.
  - pattern `$FFDF` on (34,2)→(44,2)→(44,12): the vertex's bit is 0 for both lines, the processor inversion alone
    sets it; every vertex therefore ends inverted exactly once whatever the pattern.
- DrawMode 6 (COMPLEMENT|INVERSVID): no first-dot handling, the vertex is inverted by both lines when its
  (inverted) pattern bit is 1. [D]
- JAM1/JAM2: the vertex is simply written twice with the same bit (§5.2).
- The processor inversion of plane n happens before the blit of plane n is started (the blits of earlier Draws
  are complete by then; the blit of plane n − 1 may still run, on other memory), so it does not race with the
  blitter on the same plane. [D]

### 5.4 ONE_DOT (`Flags` bit 1) [O]

Set by AreaEnd on its own temporary RastPort; honoured by Draw for any RastPort. The line engine's single-dot mode
draws **the first pixel of each row** of the Bresenham line: (0,1)→(12,4) gives (0,1) (2,2) (6,3) (10,4); a
y-major line is unchanged ((20,1)→(23,12) draws all 12 rows); a horizontal line, in either direction, draws only
its **start** pixel ((30,2)→(40,2) → (30,2); (50,2)→(42,2) → (50,2)). The first-dot rule of §5.3 still applies.

### 5.5 Mask and planes [O]

Only planes whose `Mask` bit is 1 are touched, by the blitter and by the §5.3 processor inversion. Observed: Mask
1, FgPen 3, JAM2 → colour 1 only; Mask 2, COMPLEMENT → plane 1 only.

## 6. Coordinates outside the BitMap (no layer) [O][D]

There is **no clipping and no check**. The start address is `plane + y0 × BytesPerRow + (x0 >> 3)` (arithmetic
shift, the multiplication is an **unsigned 16 × 16** product of the y word), the blitter then walks linearly:

- x < 0 or x ≥ width wraps into the previous/next row: (−4,3)→(4,3) and (4,5)→(−4,5) draw x 60..63 of the row
  above and x 0..4 of the row (64-pixel BitMap); (−4,7)→(−1,10) draws (60,6) (61,7) (62,8) (63,9); (60,12)→(70,12)
  draws x 60..63 then x 0..6 of row 13.
- y ≥ height writes past the plane, i.e. into the next plane in memory or beyond (observed: (10,29)→(10,34) on a
  32-row BitMap wrote rows 0..2 of plane 1 and 3 bytes past plane 1).
- y < 0: the unsigned product gives `(65536 + y) × BytesPerRow`. On a 512 KB chip machine with BytesPerRow a
  multiple of 8 this is `y × BytesPerRow` modulo the 512 KB chip address space, so the blitter writes **before**
  the plane, as a signed product would (observed: (20,−2)→(20,2) wrote the two rows just before plane 0, and the
  rows of plane 1 that alias the last rows of plane 0). With other BytesPerRow values or more chip RAM the target
  is elsewhere in chip RAM; and the processor inversion of §5.3 uses the full 32-bit address (outside chip RAM).
  [O for BPR 8 / 512 KB, D otherwise] A clone should not try to emulate more than "writes outside the plane".
- cp is updated whatever the coordinates.

## 7. Rendering with a layer (`rp_Layer ≠ NULL`)

### 7.1 Order of operations [D][O]

1. `LockLayerRom(layer)` through its vector.
2. Line converted to BitMap coordinates: `+ bounds.MinX − Scroll_X`, `+ bounds.MinY − Scroll_Y`.
3. Walk of `Layer.ClipRect` in list order. For each ClipRect, outcodes of both ends against its bounds:
   - **both ends inside** ("contained"): if the ClipRect is visible (`lobs = NULL`), cp is set to the start in
     BitMap coordinates and the **no-layer engine** (§5) draws the line on `rp_BitMap`; if it is hidden with a
     buffer (SMART/SUPER), `rp_BitMap` is temporarily replaced by `cr_BitMap` and the line is drawn there with
     x relative to `MinX & ~15` and y relative to `MinY`; if hidden without buffer (SIMPLE), nothing. In all three
     cases the walk **stops** here.
   - **both ends on the same outer side**: skipped.
   - otherwise ("crossing"): if visible, or hidden with a buffer, the **clipped engine** draws the part of the
     line inside the ClipRect (into the screen or the buffer, same coordinate rule); hidden without buffer:
     skipped. The walk continues.
4. If the walk ended without a "contained" case and `Layer.SuperBitMap ≠ NULL`, the line is also processed
   against `SuperClipRect` into the SuperBitMap. [D only]
5. `UnlockLayerRom`.
6. `cp = (x, y)` (**layer** coordinates) and byte +$1F decreased by M — done **after** drawing, even when nothing
   was visible. [O]

### 7.2 Clipping result [O]

- Pixels: the clipped engine reproduces the pixels of the unclipped line inside each ClipRect. Observed:
  layer (8,4)-(55,27), Draw (30,21)→(60,30) gives screen (38,25) (39,25) (40..42,26) (43..46,27), exactly the
  first 9 pixels of the unclipped Bresenham line; lines crossing the layer's left edge start at the edge.
- SMART layer: the parts under another layer go to the ClipRect buffer and reappear on DeleteLayer of the front
  layer (observed, including the pattern).
- SIMPLE layer: the hidden parts are lost (observed: after DeleteLayer of the front layer, only the visible part
  of the line exists).
- A line entirely outside the layer draws nothing and still moves cp.

### 7.3 Defect 1: pattern byte decreased twice for a contained line [O]

When the line is "contained" in one ClipRect (the common case: a short line inside a window), the no-layer engine
already decreases +$1F by M, then step 6 decreases it **again** by M. Consequences:

- Move(1,1), Draw(10,1), Draw(10,6) in a layer, pattern `$F0F0`: +$1F goes 15 → `$FD` (−18) → `$F3` (−10).
  The second line starts at bit 13 instead of bit 6.
- Move(0,1), Draw(20,1), Draw(40,1), pattern `$FF00`, JAM2: the vertex pixel drawn "on" by the first line is
  rewritten "off" by the second (its first pixel uses bit 7). Pattern continuity across consecutive Draws holds
  **only without a layer** (or by luck when 2M ≡ M mod 16).
- A "contained" line in a hidden SIMPLE ClipRect is not drawn and decreases +$1F only once (observed 15 → `$0C`
  for M = 3); in a hidden SMART ClipRect it is drawn into the buffer and decreases it twice (15 → 9).

### 7.4 Defect 2: phase of clipped pieces [O]

A piece drawn by the clipped engine does **not** use +$1F. Its first pixel uses bit
`(linpatcnt − (S − C)) mod 16`, where `linpatcnt` is the byte **+$1E**, `S` is the major-axis coordinate of the
piece's first pixel **in the target BitMap** (screen, or the ClipRect buffer) and `C` the major-axis coordinate of
the line's start **in layer coordinates** (cp). Following pixels decrease the bit as usual. Because S and C are in
different coordinate systems, the phase depends on the layer position and, in a buffer, on `MinX & ~15`.
Observed (layer at (8,4), +$1E = 0 unless stated, x-major lines):

- Move(−8,5), Draw(40,5), `$FF00`: S = 8, C = −8 → first visible pixel (screen x 8) bit 0; on: x 9..16, 25..32,
  41..48.
- Same with +$1E = 4: first visible pixel bit 4; on: x 13..20, 29..36, 45..48.
- Move(40,7), Draw(−8,7): S = 48 (start, inside), C = 40 → bit 8 at screen x 48, then decreasing leftwards;
  on: x 48, 32..39, 16..23.
- SMART layer, Move(2,8), Draw(40,8) crossing into a hidden ClipRect (30,4)-(55,15), `$F0F0`: visible piece S = 10,
  C = 2 → bit 8 at x 10; hidden piece S = 30 − 16 = 14 (buffer x), C = 2 → bit 4 at x 30.
- y-major pieces use y in the same way; for a hidden buffer the y used is `y − MinY + (MinY & 15)` [D, not
  observed].

The clipped engine never modifies +$1E or +$1F itself (step 6 does the single decrease).

### 7.5 Defect 3: FRST_DOT and COMPLEMENT in clipped pieces [O]

- The clipped engine does not test or clear FRST_DOT: after a Draw that was clipped, FRST_DOT keeps its previous
  value (observed: set after Move + clipped Draw; cleared only by a later contained Draw).
- No first-dot inversion and no ONE_DOT in clipped pieces [D for ONE_DOT]: in COMPLEMENT a vertex shared by two
  lines is inverted twice when either line is clipped. Observed: (15,10)→(30,10)→(30,13) crossing into a hidden
  SMART ClipRect: the vertex is back to 0 after restoration.
- Conversely a contained Draw that follows a clipped Draw sees FRST_DOT still set and does not skip its first
  pixel.

### 7.6 Locks and blitter in the layer path [D]

The layer lock is held across the whole walk. The clipped engine takes the blitter through the OwnBlitter /
DisownBlitter routines (not through their vectors) once per piece, waits for the blitter before each plane, and
does not wait at the end.

## 8. Blitter ownership and asynchrony [O][D]

- Draw takes the blitter with the same counting protocol as OwnBlitter (`GfxBase.BlitLock` incremented; if it
  was not free the task waits for its turn as in OwnBlitter), **not through the OwnBlitter vector**, waits for
  BBUSY (double read) before programming, waits again between planes, and releases it with the DisownBlitter
  protocol (again not through the vector). [D]
- **No final wait**: observed after a 1001-pixel vertical Draw, BBUSY was still set on return while `BlitLock` was
  already back to −1 (free). A processor read of the planes after Draw must be preceded by WaitBlit; ReadPixel
  does it. [O]
- Move never touches the blitter. PolyDraw adds nothing to Draw.
- A short rightward horizontal line (16 pixels) had already finished when the call returned; this is timing, not
  a guarantee. [O]

## 9. PolyDraw (−336) and relation with other functions

### 9.1 PolyDraw [D][O]

`polyTable` = `count` pairs of **words** `(x, y)`, read in order; for each, **Draw(rp, x, y) through the Draw
vector**. The current point is the start of the first segment (no implicit Move: the polyline continues from cp,
with FRST_DOT and the pattern phase as they are). count 0: nothing, cp unchanged. count 1: one Draw. The table is
not modified. Pattern continuity, COMPLEMENT first dots and the layer defects are exactly those of consecutive
Draws. Observed: Move(2,2) + PolyDraw 1 point (20,2) + PolyDraw 3 points with `$F0F0`: identical to the Draw
sequence, +$1F decreased by the sum of the major lengths (15 → `$FD` → `$DD`). [O]

### 9.2 AreaEnd edges (answers graphics-area open point 4) [O]

For 8 polygons (triangles, a quadrilateral, edges with ties, each in both vertex orders), the outline drawn by
Move(v0) + Draw(v1) … Draw(v0) is **contained in** AreaEnd's fill (JAM2, no pattern) and has **the same leftmost
and rightmost pixel on every row**. Reversing the vertex order changes both the outline and the fill in the same
way (tie pixels move), so AreaEnd's edge pixels are Draw's pixels **for the same direction** (previous vertex →
current vertex). An implementation should therefore share one line rasteriser between Draw and AreaEnd.

### 9.3 Callers inside the ROM [D]

RectFill with AREAOUTLINE (graphics-area §8), AreaEnd's outline (graphics-area §4.6) and Flood's span recording
(graphics-area §7.2) call Move/Draw through the vectors. They therefore inherit §5 and §7 (e.g. a RectFill
outline in a window uses the doubled pattern decrease, invisible with the solid pattern they force).

## 10. Test vectors (real ROM, observed)

BitMap 64 × 32, 2 planes, chip RAM, RastPort without layer unless stated; FgPen 1, BgPen 0, JAM2, solid
pattern unless stated. "→" lists the set pixels.

### 10.1 Pixel sets (A → B, then B → A when different)

| Line | Pixels A → B | B → A if different |
|---|---|---|
| (0,0)–(2,1) | (0,0) (1,1) (2,1) | (0,0) (1,0) (2,1) |
| (0,0)–(6,4) | (0,0) (1,1) (2,1) (3,2) (4,3) (5,3) (6,4) | same |
| (0,0)–(4,6) | (0,0) (1,1) (1,2) (2,3) (3,4) (3,5) (4,6) | same |
| (0,0)–(5,2) | (0,0) (1,0) (2,1) (3,1) (4,2) (5,2) | same |
| (0,0)–(10,3) | x 0,1 y0 · x 2..4 y1 · x 5..8 y2 · x 9,10 y3 | x 0,1 y0 · x 2..5 y1 · x 6..8 y2 · x 9,10 y3 |
| (0,10)–(9,0) | (0,10) (1,9) (2,8) (3,7) (4,6) (5,5) (5,4) (6,3) (7,2) (8,1) (9,0) | … (4,6) (4,5) (5,4) … |
| (3,0)–(0,5) | (3,0) (2,1) (2,2) (1,3) (1,4) (0,5) | same |
| (0,0)–(9,0), (0,0)–(0,9), (0,0)–(7,7), (7,0)–(0,7) | all pixels of the segment | same |
| (10,10)–(20,13) | x 10,11 y10 · 12..14 y11 · 15..18 y12 · 19,20 y13 | 12..15 y11 · 16..18 y12 |
| (10,10)–(0,13) | x 9,10 y10 · 6..8 y11 · 2..5 y12 · 0,1 y13 | 5..8 y11 · 2..4 y12 |
| (10,10)–(20,7) | x 10,11 y10 · 12..14 y9 · 15..18 y8 · 19,20 y7 | 12..15 y9 · 16..18 y8 |
| (10,10)–(0,7) | x 9,10 y10 · 6..8 y9 · 2..5 y8 · 0,1 y7 | 5..8 y9 · 2..4 y8 |
| (10,10)–(13,20) | y 10,11 x10 · 12..14 x11 · 15..18 x12 · 19,20 x13 | 12..15 x11 · 16..18 x12 |
| (10,10)–(7,20) | y 10,11 x10 · 12..14 x9 · 15..18 x8 · 19,20 x7 | 12..15 x9 · 16..18 x8 |
| (10,10)–(13,0) | y 9,10 x10 · 6..8 x11 · 2..5 x12 · 0,1 x13 | 5..8 x11 · 2..4 x12 |
| (10,10)–(7,0) | y 9,10 x10 · 6..8 x9 · 2..5 x8 · 0,1 x7 | 5..8 x9 · 2..4 x8 |
| (10,10)–(16,13) | (10,10) (11,11) (12,11) (13,12) (14,12) (15,13) (16,13) | (10,10) (11,10) (12,11) (13,11) (14,12) (15,12) (16,13) |
| (10,10)–(4,7) | (10,10) (9,9) (8,9) (7,8) (6,8) (5,7) (4,7) | (10,10) (9,10) (8,9) (7,9) (6,8) (5,8) (4,7) |
| (5,5)–(5,5) | (5,5) | — |

### 10.2 Patterns (FgPen 1, BgPen 0, JAM2 unless stated)

```
B: LinePtrn $FF00
     0000000000111111111122222222223333333333444
     0123456789012345678901234567890123456789012
  1  11111111........11111111........11111111...      Move(0,1)  Draw(40,1)      +$1F after: $E7
  3  .11111111........11111111........11111111..      Move(40,3) Draw(0,3)
  5  11111111........1111.......................      Move(0,5)  Draw(40,6)
  6  ....................1111........11111111...
  8  11111111...................................      Move(0,8) Draw(10,8) Draw(10,18) Draw(30,18)
 9-13 (column 10 off), 14-17 column 10 on
 18  ..........1111........11111111.............
      column 40 rows 8..15 and 24..30 on            Move(40,8) Draw(40,30)   +$1F after: $F9
      (60,30)→(45,10): rows 23..30 and 10..14 on    +$1F after: $FB
```

- Same lines with BgPen 2: JAM2 gives `2` in every 0-bit position (row 1: `11111111222222221111111122222222111111112`),
  JAM1 leaves them 0.
- `$8001`, Move(0,1) Draw(40,1): x 0, 15, 16, 31, 32. A Draw after InitRastPort + SetAPen without Move gives the
  same; with +$1F forced to 3 before a Draw from (0,4): x 3, 4, 19, 20, 35, 36.
- Draw modes, `$FF00`, FgPen 1, BgPen 2, rightward row then leftward row (0..40):
  - JAM1: `11111111........11111111........11111111.` / `.11111111........11111111........11111111`
  - JAM2: `11111111222222221111111122222222111111112` / `21111111122222222111111112222222211111111`
  - JAM1|INVERSVID: `........11111111........11111111........1` / `1........11111111........11111111........`
  - JAM2|INVERSVID: `22222222111111112222222211111111222222221` / `12222222211111111222222221111111122222222`
  - COMPLEMENT (on 0): `33333333........33333333........33333333.` / `.33333333........33333333........33333333`
  - COMPLEMENT|INVERSVID: `........33333333........33333333........3` / `3........33333333........33333333........`

### 10.3 COMPLEMENT (FgPen 1, all planes, background 0)

```
     0000000000111111111122222222223333333333444
     0123456789012345678901234567890123456789012345
  2  ..33333333333.................3...33333333333   (2,2)-(12,2)-(12,12) ; (20,2)-(30,2)-(20,2) ;
  3  ............3...............................3   $FFDF (34,2)-(44,2)-(44,12)
  6  ............3.......33333333333.............3   (20,6)-(30,6)-(30,6)
 12  ............3...............................3
 20  ..3333333333....                                 (2,20)-(12,20) Move(12,20) Draw(12,30): (12,20) = 0
 21..30 column 12 set
```

DrawMode 6 with the solid pattern: nothing drawn.

### 10.4 ONE_DOT, Mask, out of bounds

- ONE_DOT: (0,1)→(12,4) → (0,1) (2,2) (6,3) (10,4); (20,1)→(23,12) → all 12 rows; (30,2)→(40,2) → (30,2);
  (50,2)→(42,2) → (50,2); (20,20)→(30,20)→(30,25) → (20,20) and (30,20..25).
- Mask 1, FgPen 3: colour 1 only; Mask 2, COMPLEMENT: colour 2 only.
- Out of bounds: see §6 (all values observed).
- (0,0)→(1,1100) on a 16 × 1024 BitMap: rows 0..76 only.

### 10.5 Layer (layer (8,4)-(55,27) on the 64 × 32 BitMap; SIMPLE layer (30,0)-(63,15) in front for K)

| Sequence (layer coordinates) | Result |
|---|---|
| SMART, `$F0F0`: Move(1,1) Draw(10,1) Draw(10,6) | screen row 5: x 9..12, 17, 18; column 18: rows 5, 6; +$1F: 15 → `$FD` → `$F3`; Flags 0 |
| Move(2,8) Draw(40,8) (crosses into the hidden part) | +$1F `$E9`, FRST_DOT still set; screen row 12 after DeleteLayer of the front layer: x 11..14, 19..22, 27..30, 35..38, 43..46 |
| Draw(40,20) from (40,8) | +$1F `$DD` |
| solid: Move(30,21) Draw(60,30) | (38,25) (39,25) (40..42,26) (43..46,27); +$1F `$F1` |
| Move(30,3) Draw(33,6) (inside the hidden SMART part) | drawn in the buffer, visible after DeleteLayer at (38,7) (39,8) (40,9) (41,10); +$1F 9; Flags 0 |
| same in a SIMPLE layer | not drawn; +$1F `$0C`; FRST_DOT still set |
| COMPLEMENT (2,17)→(12,17)→(12,22) | vertex (20,21) set once |
| COMPLEMENT (15,10)→(30,10)→(30,13) (crosses hidden part) | vertex (38,14) back to 0 after restoration |
| single SIMPLE layer, `$FF00`: Move(0,1) Draw(20,1) Draw(40,1) | row 5: x 8..15, 24..27, 36..43 (x 28 rewritten off); +$1F `$E7` then `$BF` |
| Move(0,3) Draw(47,3) | row 7: x 8..15, 24..31, 40..47; +$1F `$B1` |
| Move(−8,5) Draw(40,5) | row 9: x 9..16, 25..32, 41..48; +$1F `$DF`, FRST_DOT set |
| Move(40,7) Draw(−8,7) | row 11: x 16..23, 32..39, 48 |
| Move(−3,9) Draw(10,9) Draw(30,9) | row 13: x 14..17, 21..28, 37, 38; +$1F `$DA` |
| +$1E = 4, Move(−8,11) Draw(40,11) | row 15: x 13..20, 29..36, 45..48 |

### 10.6 AreaEnd vs Draw

Polygons (16,1)(28,14)(4,14); (2,2)(12,7)(2,12); (40,2)(60,5)(50,20)(35,12); (2,20)(30,23)(10,30), each in both
orders: outline ⊆ fill and equal row extents in all eight cases; fill sizes 182, 66, 288 / 294 (the two orders
of the quadrilateral differ by their tie pixels), 158.

## 11. Probe to write (implementation side)

`tests/gline_probe.s` + `.sh`, modelled on `tests/garea_probe.s/.sh` (HUNK executable launched by the
startup-sequence of a floppy built with xdftool; results on the serial port; a final marker such as `GLP fin`).
Everything goes through the public LVOs with A6 = GfxBase (LayersBase for layers calls).

**Setup**: one chip block holding two planes of a **64 × 32** BitMap (BytesPerRow 8, 256 bytes per plane)
**surrounded by 512-byte guards** before and after; BitMap via InitBitMap(depth 2, 64, 32); RastPort via
InitRastPort then `rp_BitMap` set. Between tests: WaitBlit, BltClear of the whole block (flags 1), then Move or
explicit field setup. Output per test: a header line (test id, `cp_x cp_y Flags byte+$1E byte+$1F` in hex), then
32 lines of `plane0 plane1` as 8-byte hex rows, as garea does; for the out-of-bounds test also the list of non-zero
guard byte offsets. Always WaitBlit before reading planes.

**Tests** (expected results = §10):

1. **L0 registers**: call Move, Draw, PolyDraw with marker values (e.g. `$1111000n`) in D0–D7/A0/A2–A5;
   print which registers changed (expect: Move none; Draw and PolyDraw D0, D1, A0).
2. **L1 fields**: InitRastPort then print `Flags`, bytes +$1E/+$1F, cp; then after SetAPen(1), SetBPen(2),
   SetDrMd(0) (expect FRST_DOT set and +$1F = 15 after each); after Move(3,4); after Draw(10,4) (+$1F 8);
   after Draw(20,9) (+$1F `$FE`); after PolyDraw of (30,9) (30,20) (40,25) (+$1F `$DF`, cp (40,25)); PolyDraw
   count 0 (nothing changes).
3. **L2 pixel sets**: for each line of §10.1, clear, Move(A), Draw(B), dump; then the reverse. (Dumping only the
   bounding rows keeps the log short.)
4. **L3 patterns**: §10.2 sequences with `$FF00` (one dump), the BgPen 2 / JAM1 / JAM2 rows, the six-mode table,
   `$8001` with and without Move, and with +$1F poked to 3 and +$1E poked to 9 before a Draw from (0,4).
5. **L4 COMPLEMENT**: the §10.3 sequences in one dump.
6. **L5 ONE_DOT and Mask**: set bit 1 of `Flags` directly, draw the §10.4 lines; Mask 1 / Mask 2 rows.
7. **L6 out of bounds**: the eight lines of §6 in one dump + guard offsets (expected non-zero guard offsets
   relative to plane 0: −14, −13, −6, −5, 513, 521, 529).
8. **L7 asynchrony**: a second BitMap 16 × 1024 × 1 plane; Move(3,0) Draw(3,1000), read DMACONR immediately
   (expect bit 14 set) and `GfxBase+$AA` (expect `$FFFF`); WaitBlit; then (0,0)→(1,1100) and report the last
   row containing a pixel (expect 76).
9. **L8 layers**: NewLayerInfo, CreateUpfrontLayer(li, bm, 8, 4, 55, 27, flags 2 = SMART), then a SIMPLE layer
   (30, 0, 63, 15) in front; BltClear the planes; on the back layer's `rp` run the §10.5 sequences, print the
   fields after each, dump before and after DeleteLayer of the front layer. Repeat with the back layer SIMPLE.
   Then a single SIMPLE layer at (8,4)-(55,27) for the phase vectors (rows 5..17 of §10.5).
10. **L9 AreaEnd vs Draw**: AreaInfo of 40 entries in any RAM, TmpRas of 2 KB in chip set in the RastPort; for
    each polygon of §10.6 in both orders: AreaMove/AreaDraw/AreaEnd, dump; then the outline by Move/Draw, dump.
    The comparison can be done offline on the log.

## Open points

1. **SuperBitMap layers** (§7.1 step 4): deduced only; in particular whether a line contained in a visible
   ClipRect also reaches the SuperBitMap (the walk stops before the SuperClipRect pass).
2. **y-major clipped pieces in a hidden buffer**: the `(MinY & 15)` term of §7.4 is deduced, not observed.
3. **ONE_DOT in a layer**: the clipped engine ignores it (deduced); a contained line honours it (same engine as
   §5.4). Not observed with a layer.
4. **Negative y on machines with more than 512 KB of chip RAM** or BytesPerRow not a multiple of 8 (§6): deduced.
5. **Scroll_X/Scroll_Y ≠ 0**: the offset is applied (deduced, as in graphics-blitter §5.2); not observed.
6. **OwnBlitter contention**: Draw waiting for a blitter held by another task or by the QBlit queue is deduced
   from the shared protocol; not observed.
7. The observations were made on Amiberry (A500, cycle-exact) by debugger-injected calls in the boot picture's
   task; a probe run from a CLI process (§11) should give the same figures but has not been run.

## Clean-room review

Review of 2026-11-04.

- [x] No 68000 instruction sequence transcribed or paraphrased, no disassembly excerpt, no ROM routine or data
  address. The only numbers are public LVOs, public structure offsets (`rastport.h`, `gfxbase.h`, `clip.h`), the
  BlitLock value, custom-register bit meanings (BBUSY) and pixel coordinates of our own test BitMaps.
- [x] The line rule of §4 is the textbook Bresenham criterion stated as a pixel-selection rule, confirmed by the
  observed pixel sets; the engines of §5.1 and §7 are described by their observable effects (pixels, fields,
  order of field updates), not by their code.
- [x] The pixel diagrams and tables are **outputs** of the real ROM on test inputs (test vectors), not ROM data.
- [x] The minterm byte values quoted in §2 are values found in a RastPort after public calls (observable ABI
  state), not tables from the ROM.
- [x] No probe code was written by the analysis track; §11 describes one in words.
