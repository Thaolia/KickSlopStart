# graphics.library 34.1 — fills, ellipses, Flood, pixels: behavioural spec

> **ANALYSIS** track ("dirty"). Sources: ROM `assets/kick34005.A500` (read only, radare2, base
> `$FC0000`; disassembly notes outside the repository) and black-box probe `tests/garea_probe.s` (harness
> `tests/garea_probe.sh`) run **twice** on the **real ROM** under FS-UAE (PAL A500, 512 KB chip +
> 512 KB slow, DOS boot on a floppy whose startup-sequence launches the probe); tests T0–T25
> common to both runs gave **byte-for-byte identical** output.
> The probe draws into a **32 × 20, 2-plane** BitMap in chip RAM, RastPort **without a layer**, then
> reads the planes back with the processor after WaitBlit.
> This document describes **behaviours**, **values**, **orders of operations** and
> **ABI layouts**. It contains no ROM instruction sequence nor routine address.
> It complements, without repeating them: `graphics-blitter-v34.md` (§8 BltPattern, final rendering engine of
> everything that follows; §5 clipping by ClipRects; §7 allocations), `workbench-task-v34.md` §3.6 (use of
> Flood by the Workbench).
>
> **Levels of proof**: **[O]** observed by the probe on the real ROM · **[D]** deduced from reading
> the ROM code (behaviour, not code) · **[S]** reasonable assumption, not verified.
>
> Diagram conventions: one line per y (0 at the top), one column per x (0 on the left); `.` = colour
> 0, otherwise the digit of the colour (plane 0 = bit 0, plane 1 = bit 1).

## 0. Summary for the implementer

- The eight LVOs `InitArea` (−282), `AreaMove` (−252), `AreaDraw` (−258), `AreaEnd` (−264),
  `AreaEllipse` (−186), `DrawEllipse` (−180), `InitTmpRas` (−468), `Flood` (−330) are **all present
  in V34** (real vectors in the 109-entry table). `AreaCircle`, `DrawCircle`, `SetAfPt`,
  `SetOPen`, `BNDRYOFF` **have no LVO**: they are header macros (`graphics/gfxmacros.h`). [D]
- **AreaEnd** = classic blitter method: (1) the edges are drawn **one point per line** in
  **XOR** into a mask plane (the TmpRas), (2) the mask is filled by the blitter in **exclusive
  fill, descending walk**, (3) **all** the edges are drawn again **in full** (OR)
  into the mask, (4) the mask is rendered by **BltPattern** (pens, mode, pattern, layers). Result:
  **even/odd** rule, **edges included on both sides**, including horizontal edges. [D][O]
- **Exception**: if `DrawMode == JAM1` **and** `AreaPtSz == 2`, step (3) **clears** the edges instead
  of adding them: the edges are **excluded** (artefact of a comparison on a word, §4.5). [D][O]
- **AreaEllipse** occupies **2 entries** (corners of the bounding rectangle); the ellipse fill is
  **exactly the interior, edge included, of DrawEllipse's outline** with the same radii. [O]
- **Returned values**: 0 = success, **−1 = no more room** in the vertex buffer (AreaMove/AreaDraw/
  AreaEllipse, and AreaEnd if it has to add the closing edge without room). AreaEnd on an empty list
  returns an **undefined value**. Flood returns **1** (success) or **0** (failure). WritePixel returns 0 (−1 outside
  the layer); ReadPixel returns the colour (−1 outside the layer). [O][D]
- **No size check**: AreaEnd **ignores `TmpRas.Size`**; Flood uses it as the size of an
  **additional chip allocation**. Without a layer, WritePixel/ReadPixel/AreaEnd **clip nothing**. [O][D]
- **Flood**: **seed, 4-connected** fill; mode 0 = "up to the AOlPen colour", mode 1 =
  "as long as the colour of the starting point"; final rendering by BltPattern (pattern and pens applied).
  Without TmpRas: mode 0 still works (slow path), mode 1 **fails (0)**. [O][D]

## 1. Structures (ABI)

### 1.1 AreaInfo (24 bytes, `graphics/rastport.h`) [D][O]

| Offset | Field | V34 use |
|---|---|---|
| $00 | `VctrTbl` (long) | start of the vertex table (pairs of words x, y) |
| $04 | `VctrPtr` (long) | next free entry of the vertex table |
| $08 | `FlagTbl` (long) | start of the flag table (1 byte per entry) |
| $0C | `FlagPtr` (long) | next free flag |
| $10 | `Count` (word) | number of recorded entries |
| $12 | `MaxCount` (word) | capacity in entries |
| $14 | `FirstX` (word) | x of the last AreaMove (closing point of the current polygon) |
| $16 | `FirstY` (word) | y of the same point |

**Buffer supplied to InitArea**: `MaxCount × 5` bytes; the first `4 × MaxCount` bytes are the vertex
table, the following `MaxCount` the flag table. Observed: InitArea(…, 40) → `FlagTbl =
buffer + $A0`. [O] The offset is added on **16 signed bits**: beyond 8191 entries the flag
table falls before the buffer. [D] The buffer is read and written **only by the processor**: it can be
in any RAM. [D] Alignment: even required (word/long accesses on the 68000). [S]

**Flag of an entry** (byte) [D][O]:

| Bit | Meaning |
|---|---|
| 0 | **non-horizontal** edge (the vertex's y differs from the previous vertex's y) |
| 1 | **drawn** entry (AreaDraw or ellipse); 0 = AreaMove |
| 2 | **outline requested**: `AREAOUTLINE` (bit 3 of `rp_Flags`) was set **at the time of the AreaDraw** |
| 7 | first entry of an **ellipse** |

Observed values: AreaMove `$00`, horizontal AreaDraw `$02`, oblique/vertical `$03`, same values
with outline active `$06`/`$07`, ellipse `$83` then `$02`. [O] (T7, T28)

### 1.2 TmpRas (8 bytes) [D]

`$00 RasPtr` (long, buffer in **chip**) · `$04 Size` (long). InitTmpRas only writes these two fields.

### 1.3 RastPort fields concerned [D]

`$0C TmpRas` · `$10 AreaInfo` · `$08 AreaPtrn` · `$1D AreaPtSz` (signed byte) · `$1B AOlPen` ·
`$19 FgPen` · `$1A BgPen` · `$1C DrawMode` · `$20 Flags` (`AREAOUTLINE` = `$0008`, `ONE_DOT` = `$0002`,
`FRST_DOT` = `$0001`) · `$22 LinePtrn` · `$24 cp_x` · `$26 cp_y` · `$28 minterms[8]`.
**InitRastPort** sets `AOlPen = −1` (`$FF`): an unconfigured outline is drawn in **all** planes
(colour 3 on 2 planes, T12). [O]

## 2. InitArea (−282) and InitTmpRas (−468)

- `InitArea(areaInfo A0, buffer A1, maxVectors D0)`: `VctrTbl = VctrPtr = buffer`, `FlagTbl = FlagPtr =
  buffer + 4 × maxVectors`, `MaxCount = maxVectors` (word), `Count = 0`. **FirstX/FirstY are not
  touched**. No useful returned value, no validation. [D][O] (T0)
- `InitTmpRas(tmpRas A0, buffer A1, size D0)`: `RasPtr = buffer`, `Size = size` (long); **returns `tmpRas`
  in D0**. No validation (neither chip, nor alignment, nor size). [D][O] (T0)

## 3. Recording the vertices

### 3.1 AreaMove (−252) — `(rp A1, x D0, y D1)` → D0 [D][O]

1. If `Count + 1 > MaxCount` → returns **−1**, nothing is modified.
2. `Count` is incremented.
3. If it is not the first entry:
   - if the previous entry is **also an AreaMove** (flag 0), it is **replaced**: Count, VctrPtr
     and FlagPtr go back one entry (Count returns to its initial value); observed: AreaMove(4,4) then
     AreaMove(6,6) → Count = 1, FirstX/Y = (6,6) (T23);
   - otherwise, if the last vertex differs from (FirstX, FirstY), the previous polygon is **closed** by a
     call of **AreaDraw(FirstX, FirstY) through its LVO** (sensitive to SetFunction). If this AreaDraw fails,
     AreaMove returns −1 **leaving Count incremented** without a corresponding entry (inconsistent AreaInfo:
     the caller must redo InitArea). [D]
4. `FirstX/FirstY = (x, y)`, vertex written, flag `$00`, returns **0**.

### 3.2 AreaDraw (−258) — `(rp A1, x D0, y D1)` → D0 [D][O]

If `Count + 1 > MaxCount` → **−1** (nothing is modified; observed T23 with MaxCount = 3). Otherwise Count+1,
vertex written, flag = `$02` | `$04` if `AREAOUTLINE` is set now | `$01` if y ≠ y of the previous
vertex; returns **0**. AreaDraw **does not check** that an AreaMove preceded (it compares y with the word
located before the table if it is the first entry). [D]

### 3.3 AreaEllipse (−186) — `(rp A1, cx D0, cy D1, a D2, b D3)` → D0 [D][O]

1. If Count ≠ 0: an isolated AreaMove just before is **removed** (as in 3.1); otherwise, if the previous
   entry is not the end of an ellipse and the last vertex ≠ (FirstX, FirstY), the current
   polygon is **closed** by AreaDraw (LVO); failure → −1.
2. If `Count + 2 > MaxCount` → **−1** (T23).
3. Two entries: `(cx − a, cy − b)` flag `$83`, then `(cx + a, cy + b)` flag `$02`; Count += 2;
   returns **0**. [O] (T7: flags `83 02`)
4. **FirstX/FirstY are not updated**; the "outline" bit is **never** set on an ellipse.

Observed consequence (T31): `AreaEllipse` followed by `AreaDraw` without `AreaMove` then closes the
polygon towards a **stale FirstX/FirstY** (that of an earlier AreaMove) and produces an inconsistent drawing.
A polygon must always be started with AreaMove after an ellipse. [O]

`AreaCircle(rp, cx, cy, r)` = macro `AreaEllipse(rp, cx, cy, r, r)`. [D, public headers]

## 4. AreaEnd (−264) — `(rp A1)` → D0

### 4.1 Closing and empty cases [D][O]

- Last entry = AreaMove: if `Count ≤ 1`, **nothing is drawn**, the list is reset and D0
  is **undefined** (observed `$0006` and `$FFFF` depending on the context, T23/T31). If `Count > 1`, the last
  AreaMove stays in the list (isolated point, without effect). [D][O]
- Last entry drawn: if it is not the end of an ellipse and the last vertex ≠ (FirstX,
  FirstY), AreaEnd calls **AreaDraw(FirstX, FirstY)** through its LVO; failure → returns **−1** without
  drawing anything (T23: 3 entries out of MaxCount = 3 → −1). **Provide one extra entry per polygon** not
  closed explicitly. [D][O]
- In all cases, on exit: `Count = 0`, `VctrPtr = VctrTbl`, `FlagPtr = FlagTbl`; FirstX/FirstY
  unchanged. Success → **0**. [D][O] (T1)

### 4.2 Bounding rectangle and TmpRas [D][O]

- The bounding rectangle covers **all** the entries (ellipses enter it through their two corners).
  `x0 = minX & ~15` (rounded down to the word, signed arithmetic), `y0 = minY`.
- **The vertices are translated in place** by (−x0, −y0) in the table (observed T1: after AreaEnd, the
  table contains `(2,0) (10,0) (10,8) (2,8) (2,0)` for the square (2,2)–(10,10), closing entry
  included). The table's contents are therefore **not reusable** after AreaEnd. [O]
- Mask: one plane of `L = ((maxX + 16) & ~15 − x0) / 8` bytes per line and `H = maxY − minY + 1` lines,
  placed at the start of `TmpRas.RasPtr`, cleared by **BltClear** (lines/bytes form). **Requirement: `L × H`
  bytes of chip.** [D]
- **`TmpRas.Size` is not read**: with `Size = 4`, a full-screen 32 × 20 fill (80 bytes) is
  correct (T24). A TmpRas that is too small **overflows silently**. [O][D]
- **TmpRas absent** (`rp_TmpRas = NULL`): the pointer is dereferenced anyway (read of RasPtr at
  address 0, then write of the mask at the address read): corruption of low memory. [D] (not probed)

### 4.3 Pass 1: "one point per line" edges in XOR [D]

A temporary RastPort (without layer, one-plane mask, COMPLEMENT mode, `ONE_DOT`, solid line pattern)
walks the list:

- non-horizontal drawn entry: blitter line from the current point to the vertex, **a single point per scan
  line**, in XOR; the **first point of the edge is omitted** when the starting vertex is not a
  local extremum in y (the previous edge went in the same direction), kept otherwise;
- horizontal drawn entry, or ellipse: move of the current point (horizontal edges
  produce no point in this pass); ellipse: **DrawEllipse** with centre `(corner1 + corner2) / 2` and
  radii `corner2 − centre`, in `ONE_DOT` (one point per line and per side), by a direct XOR plotter
  using the processor;
- AreaMove (and end of list): if the first and the last non-horizontal edge of the polygon that
  ends go **in the same direction**, the starting point is inverted once more (WritePixel through LVO)
  to correct the parity at the closing vertex.

Effect: on each scan line, the mask contains an even number of points delimiting the spans.

### 4.4 Pass 2: blitter fill [D]

A single blit on the mask: channels C → D, minterm "D = C", **descending walk**, **exclusive
fill (EFE)**, FCI = 0, width `L/2` words, height `H`, modulos `−2L` (each line is processed from
right to left, the lines from top to bottom). In exclusive mode, the point that opens the span (right side) is
kept, the one that closes it (left side) is lost: it is pass 3 that restores the edges.

### 4.5 Pass 3: complete edges [D][O]

All the drawn entries are redrawn **in full** (first point included, horizontal lines
included, ellipses by normal DrawEllipse) with the line minterm:

- **OR** (point set to 1) in the general case → edges included;
- **AND NOT** (point set to 0) if the **word** formed by `DrawMode` and `AreaPtSz` is exactly `$0002`,
  i.e. `DrawMode = JAM1` and `AreaPtSz = 2`. Observed T29: square (2,2)–(12,12) in JAM1 with a solid
  4-line pattern → pixels **(3..11, 3..11)** only; same square with AreaPtSz = 0 → (2..12, 2..12);
  in JAM2 with AreaPtSz = 2 (T17) → edges included. A compatible clone must reproduce this case. [O]

### 4.6 Pass 4: rendering and outline [D][O]

- **BltPattern(rp, mask, x0, y0, x0 + 8L − 1, y0 + H − 1, L)** through its **LVO**: pens, DrawMode, Mask,
  pattern `AreaPtrn/AreaPtSz` and clipping by the layer's ClipRects are those of BltPattern
  (`graphics-blitter-v34.md` §8 and §5.2). Coordinates without a layer: **no clipping** to the bounds of the
  BitMap. [D]
- Then, if `AREAOUTLINE` is set **at the time of AreaEnd**: drawing of the outline on the caller's
  RastPort with **FgPen = AOlPen, JAM1, LinePtrn = $FFFF, AreaPtrn = NULL** (then restoration of
  DrawMode, FgPen, minterms, AreaPtrn, LinePtrn): each entry **whose bit 2 is set** is drawn by
  **Draw (LVO)** from the previous point, the others by Move. The RastPort's current point `cp` stays
  on the last vertex. **Ellipses are never outlined**. [D][O]
  Observed T12: outline enabled only after the AreaDraws → only the closing edge (added by
  AreaEnd) gets the outline. T11: polygons outlined in AOlPen = 2 (edge and interior 1), ellipse without
  outline.
- Without `AREAOUTLINE`, the caller's RastPort (cp included) is not modified by AreaEnd. [D]

### 4.7 Reading one entry too many after an ellipse [D][O]

Each ellipse consumes two entries in a single loop iteration, whereas passes 1 and 3 do
`Count` iterations: **for each ellipse, one entry located beyond Count is processed** (residual vertex and
flag of the buffer, not translated). Observed: buffer reset to zero → clean ellipse (T26);
buffer pre-filled with `(0,0)` entries flag `$03` → **one stray point** at (x0, y0) (T27); in T7 and
T11 (residues of old tests), **stray strokes** up to old vertices. No software can
rely on this defect; a clean implementation must process exactly `Count` entries [S] — but
note that, on the real ROM, an AreaInfo buffer **set to zero** (AllocMem MEMF_CLEAR, common case) makes
the defect invisible (residual entry = AreaMove at (x0, y0)).

### 4.8 Fill rule: test vectors [O]

All in APen 1, JAM2, BPen 0, without pattern.

- **Square** (2,2)(10,2)(10,10)(2,10): pixels x 2..10, y 2..10 (**81 pixels, edges included**). Same
  result walked in the other direction and closed explicitly (T1, T2).
- **Triangle** (16,1)(28,14)(4,14) (T3):

```
  1  ................1...............
  2  ...............111..............
  3  ..............11111.............
  4  .............1111111............
  5  ............111111111...........
  6  ...........11111111111..........
  7  ..........1111111111111.........
  8  ..........1111111111111.........
  9  .........111111111111111........
 10  ........11111111111111111.......
 11  .......1111111111111111111......
 12  ......111111111111111111111.....
 13  .....11111111111111111111111....
 14  ....1111111111111111111111111...
```

- **Pentagram** (16,1)(22,18)(6,7)(26,7)(10,18) (T4): the central pentagon is **empty** (even/odd)
  but the **edges that cross it are drawn**:

```
  1  ................1...............
  2  ................1...............
  3  ...............111..............
  4  ...............111..............
  5  ...............111..............
  6  ..............11111.............
  7  ......111111111111111111111.....
  8  .......11111111...11111111......
  9  .........11111.....11111........
 10  ..........1111.....1111.........
 11  ............1.......1...........
 12  ............111....11...........
 13  ............1111.1111...........
 14  ...........11111111111..........
 15  ...........11111.11111..........
 16  ...........111.....111..........
 17  ..........111.......111.........
 18  ..........1...........1.........
```

- **Two squares in the same AreaEnd** (2,2)–(14,14) and (8,8)–(20,18) (T5): the intersection
  (9..13, 9..13) is **empty**, its edges (lines 8 and 14, columns 8 and 14) are filled. **Even/odd,
  not non-zero.** The second AreaMove added the closing edge of the first (Count = 9).
- **Concave C-shaped polygon** (2,2)(28,2)(28,6)(8,6)(8,12)(28,12)(28,16)(2,16) (T6): lines 2..6 and
  12..16 filled from x 2 to 28; lines 7..11 from x 2 to 8 only.
- **Degenerate figures** (T25): a polygon of zero area draws its **edges**: (5,2)–(12,2) → segment
  x 5..12; (3,5)–(20,5) → x 3..20; (3,8)–(3,15) → column; (16,8)–(28,16) → oblique segment.
- **COMPLEMENT** (T16): two successive AreaEnds (squares (2,2)–(14,14) then (8,8)–(20,18)): each mask
  inverts **all the planes of the Mask** (0 → 3), the intersection, edges included, returns to 0.

## 5. Fill patterns (AreaPtrn / AreaPtSz) [O]

Rendered by BltPattern, hence common to AreaEnd, RectFill and Flood.

- **Monochrome** (`AreaPtSz = n ≥ 0`): `2^n` words; the pattern line of a pixel is **`y mod 2^n` in
  absolute RastPort coordinates**, bit 15 of the word corresponds to `x mod 16 = 0`. Observed (T13, pattern
  `$F0F0,$0F0F`, n = 1): line y = 1 → pixels x 4..7, 12..15…; line y = 2 → x 0..3, 8..11… (the pattern does
  not "start" at the top of the figure).
- **JAM1**: bits 1 → APen, bits 0 → **background kept**; **JAM2**: bits 0 → BPen; **COMPLEMENT**: bits 1
  → inversion of all the planes of the Mask, bits 0 → unchanged (T30, on a colour 2 background: JAM1 leaves 2,
  JAM2 sets 0, COMPLEMENT changes 2 into 1).
- **Multicolour** (`AreaPtSz = −n`): `2^n` words **per plane**, consecutive planes (plane 0 first). Each
  plane receives **its** pattern combined with that plane's minterm (plane bit in APen/BPen, DrawMode).
  T14, patterns plane 0 `$FF00,$FF00`, plane 1 `$F0F0,$0F0F`: in **APen = 3, BPen = 0, JAM2** the pattern's
  colours are reproduced as is (odd line: x 0..3 → 1, 4..7 → 3, 8..11 → 0, 12..15 → 2);
  in APen = 1, JAM1, only plane 0 is written (colour 1 on x 0..7 of each group of 16).
- **SetAfPt(rp, ptrn, n)** = macro that assigns AreaPtrn and AreaPtSz. [D, public headers]

## 6. DrawEllipse (−180) — `(rp A1, cx D0, cy D1, a D2, b D3)` [D][O]

- **Two-region midpoint** algorithm (32-bit integer arithmetic, squares of the radii on 16
  signed bits), 4-quadrant symmetry; each point is set by **WritePixel** called via the address
  read in GfxBase's jump table (**SetFunction of WritePixel respected**), hence clipped by the layer
  point by point. [D]
- Internal shortcut: RastPort **without layer**, `minterms[0] = $6A`, bit 0 of Mask set and BitMap with **1
  plane** → direct inversion of the bits by the processor after WaitBlit (case of the AreaEnd mask). [D]
- `ONE_DOT` in `rp_Flags`: a single point per scan line and per side (AreaEnd use). [D]
- Does not modify `cp_x/cp_y`. No returned value. [D]
- Zero radii accepted (T10): (3,3,0,0) → the single pixel (3,3); (9,3,1,0) → x 8..10 on y 3;
  (15,3,0,1) → x 15 on y 2..4; (22,3,3,0) → x 19..25; (28,4,0,3) → x 28 on y 1..7. [O]
- Exact pixels (T9; T10 for (8,13,6,5) and (24,13,1,1)): [O]

```
     00000000001111111111222222222233
     01234567890123456789012345678901
  1  ................111.....11111...      (3,3,1,1) (9,3,2,1) (17,3,3,2) (26,4,4,3)
  2  ...1....111...11...11..1.....1..
  3  ..1.1..1...1..1.....1.1.......1.
  4  ...1....111...11...11.1.......1.
  5  ................111...1.......1.
  6  .......................1.....1..
  7  ........................11111...
  8  ......................11111.....      (4,13,3,3) (13,13,4,4) (24,13,5,5)
  9  ............111......1.....1....
 10  ...111....11...11...1.......1...
 11  ..1...1...1.....1..1.........1..
 12  .1.....1.1.......1.1.........1..
 13  .1.....1.1.......1.1.........1..
 14  .1.....1.1.......1.1.........1..
 15  ..1...1...1.....1..1.........1..
 16  ...111....11...11...1.......1...
 17  ............111......1.....1....
 18  ......................11111.....

     (8,13,6,5), columns 0..15:
  8  ......11111.....
  9  ....11.....11...
 10  ...1.........1..
 11  ...1.........1..
 12  ..1...........1.
 13  ..1...........1.
 14  ..1...........1.
 15  ...1.........1..
 16  ...1.........1..
 17  ....11.....11...
 18  ......11111.....
```

- (24,13,1,1) (T10): (24,12), (23,13), (25,13), (24,14) — 4-pixel diamond, empty centre. [O]
- **AreaEllipse** fills exactly the interior of this outline, edge included (T8 = T9 filled;
  T26 for (16,10,8,6): lines 4 and 16 → x 13..19, 5/15 → 11..21, 6/14 → 10..22, 7/13 → 9..23,
  8..12 → 8..24). Zero radii (T31): AreaEllipse(3,3,0,0) → the pixel (3,3); (10,3,3,0) → x 7..13;
  (20,3,0,2) → x 20 on y 1..5. [O]
- `DrawCircle(rp, cx, cy, r)` = macro `DrawEllipse(rp, cx, cy, r, r)`. [D, public headers]

## 7. Flood (−330) — `success = Flood(rp A1, mode D2, x D0, y D1)` → D0

### 7.1 Dispatch and returned value [D][O]

1. **With a layer**: `Layer.Lock` taken (semaphore) during the whole operation.
   - **SuperBitMap** layer: SyncSBitMap, Flood on the SuperBitMap via a copy of the RastPort without a layer,
     then CopySBitMap.
   - Otherwise as below, but the mask is sized on the **bounds of the layer**.
2. **TmpRas absent**: mode ≠ 0 → returns **0** without doing anything (T20); mode 0 → **slow path** without
   allocation (§7.4), returns **1** (T20: result identical to the normal path).
3. **TmpRas present**: normal path (§7.2); returns **1**, or **0** if the chip allocation fails (T32:
   `TmpRas.Size = $F00000` → 0 in both modes, nothing drawn; **no fallback** to the slow path).
4. Starting point already on the boundary (mode 0 on AOlPen): nothing is done, returns **1** (T21).
   Mode 1 with APen equal to the starting colour: fill without visible effect, returns 1 (T21). [O]

### 7.2 Normal path (TmpRas) [D]

- Target colour: mode 0 → `AOlPen`; mode 1 → `ReadPixel(x, y)` (if −1, outside the layer: nothing is done).
- Mask: one plane in `TmpRas.RasPtr`, of dimensions `BytesPerRow × Rows` of the BitMap (without a layer) or
  `RASSIZE(width, height)` of the layer; cleared (SetRast) before use.
- **Chip allocation** (`MEMF_CHIP|MEMF_PUBLIC`) of a second plane of `TmpRas.Size` bytes (without a layer) or
  `RASSIZE` of the layer (with a layer), freed at the end after WaitBlit. **Practical requirement: the TmpRas
  must cover the whole BitMap (or the layer), and the same amount of chip must be free.** A
  `TmpRas.Size` smaller than the plane causes an overflow (not probed).
- Construction by blits, **plane by plane**, of the "pixels of the target colour" plane (AND over all the planes
  of the original depth); during these blits, the ROM **temporarily modifies the caller's
  BitMap** (`Depth = 1`, `Planes[0]` = current plane) then restores it (copy of 40 bytes). Another
  task drawing into the same BitMap during a Flood sees a 1-plane BitMap. In mode 1, the plane is
  then **inverted**: the boundary is "any colour different from the target".
- **Seed, scan-line** fill on the mask: spans found by processor reads,
  recorded by drawing horizontal lines (Move/Draw through LVO) into the result plane.
- Final rendering: **BltPattern(rp, result, 0, 0, width − 1, height − 1, BytesPerRow)** over the whole
  BitMap (or layer): APen, BPen, DrawMode, pattern and ClipRects apply (T21: pattern `$F0F0/$0F0F`
  applied to the fill).

### 7.3 Observed behaviour [O]

Scene: diagonal (0,0)–(19,19) and column x = 24 in colour 1, 2 × 2 island of colour 3 at (14,3);
Flood from (20,3), APen 2.

- **Mode 1** (T18): the colour 0 area to the right of the diagonal is filled; **the colour 3 island
  remains**; the area under the diagonal (connected only by the corners) **is not reached** → **4-connected**.
- **Mode 0** with AOlPen = 1 (T19): same area, **island 3 is covered** (only AOlPen stops); no
  leak through the corners.
- Diamond closed by 4 oblique segments (T33): exact interior fill, no leak.

```
T18 (mode 1)                          T19 (mode 0)
  0  1222222222222222222222221        0  1222222222222222222222221
  1  .122222222222222222222221        1  .122222222222222222222221
  2  ..12222222222222222222221        2  ..12222222222222222222221
  3  ...1222222222233222222221        3  ...1222222222222222222221
  4  ....122222222233222222221        4  ....122222222222222222221
  5  .....12222222222222222221        5  .....12222222222222222221
 ...                                 ...
 19  ...................122221       19  ...................122221
```

### 7.4 Slow path (mode 0 without TmpRas) [D][O]

Same rule (boundary = AOlPen, 4-connected), executed by the processor pixel by pixel (ReadPixel) with
the spans drawn directly into the RastPort; no allocation. Result identical to the normal path on
the T19/T20 scene. [O]

## 8. RectFill (−306) with outline [D][O]

- Without `AREAOUTLINE`: `BltPattern(rp, NULL, xmin, ymin, xmax, ymax, 0)` (inclusive bounds, pattern and
  pens of BltPattern). [D]
- With `AREAOUTLINE`: interior filled first — in **COMPLEMENT**, the rectangle is **shrunk by one pixel
  on each side** (nothing if empty) so as not to invert the edge twice; otherwise the whole rectangle — then
  outline by **Move(xmin,ymin), Draw(xmin,ymax), Draw(xmax,ymax), Draw(xmax,ymin), Draw(xmin,ymin)** (LVO)
  with FgPen = AOlPen and **JAM1**, minterms/FgPen/DrawMode restored afterwards. **cp stays at
  (xmin, ymin)**. [D][O] (T15: cp = (2,2); rectangle (2,2)–(12,9) → edge 2, interior 1; in COMPLEMENT
  on background 3 with outline, (18,3)–(27,8) → edge 2, interior (19..26, 4..7) at 0; without outline,
  (18,11)–(27,16) → whole rectangle at 0.)

## 9. WritePixel (−324) and ReadPixel (−318)

### 9.1 WritePixel — `(rp A1, x D0, y D1)` → D0 [D][O]

- **Without a layer**: **no bounds check**; address = `y × BytesPerRow + (x >> 3)` (16-bit signed
  multiplication). Observed (T22): WritePixel(32, 0) on a 32-pixel BitMap writes (0, 1);
  WritePixel(0, 20) with 20 lines writes the **next** plane in memory. Returns **0** in all cases.
- Write **by the blitter**, one word per plane whose `Mask` bit is set, with the minterm of
  `rp_minterms[plane]` (hence FgPen/BgPen/DrawMode): COMPLEMENT inverts the pixel in all the planes of the Mask
  (T22: 2 → 1, 0 → 3). No final wait. [D][O]
- **With a layer**: `LockLayerRom` (LVO), coordinates translated by the bounds and the scroll of the
  layer, lookup of the ClipRect: visible → screen; hidden with a backup BitMap → into that BitMap
  (x relative to `MinX & ~15`); hidden without backup (SIMPLE_REFRESH) or outside any ClipRect and outside
  SuperClipRect → returns **−1** without writing; SuperBitMap via the SuperClipRect list. [D]

### 9.2 ReadPixel — `(rp A1, x D0, y D1)` → D0 [D][O]

- Waits for the end of the blitter (WaitBlit), reads **with the processor** the pixel's bit in the `Depth` planes and
  returns the colour (0..2^Depth − 1). **Without a layer, no bounds check** (T22: ReadPixel(32, 0) returns
  the colour of (0, 1)). With a layer: same lookup rules as WritePixel, **−1** if the pixel is not
  readable. [D][O]

## 10. What differs on a real A500

1. **TmpRas in chip mandatory** (AreaEnd: BltClear, blitter lines and fill; Flood: mask
   construction blits); the ROM checks nothing. A TmpRas in slow RAM (`$C00000`) is addressed
   truncated by Agnus: the mask is written elsewhere in chip and the rendering is wrong. The vertex buffer
   can be anywhere (processor only). [D]
2. **Flood additionally allocates `TmpRas.Size` contiguous bytes of chip**: on 512 KB of fragmented chip
   (Workbench + screens), the allocation fails sooner than in generous emulation → Flood returns 0 without
   drawing anything. [D][O for the failure path]
3. The blitter fill (descending EFE mode) and the `ONE_DOT` lines are standard Agnus hardware
   functions; an emulator that implements the **fill mode with DESC** or the **SING** bit of
   lines badly produces wrong spans on this path only. The results of §4.8 are the reference. [D]
4. No final blitter wait after AreaEnd (BltPattern) nor after WritePixel: a processor access
   to the planes must be preceded by WaitBlit (ReadPixel waits itself). [D]
5. Flood is **slow** on a 7 MHz 68000 (processor reading of the mask, one blitter line per span); the
   probe measures no time. [D]

## 11. Probe

`tests/garea_probe.s` (test asset, author code): tests T0–T33, one header line per test (returned values
in hexadecimal, structures), then 20 `plan0 plan1` lines. Assembly:
`vasmm68k_mot -Fhunkexe -kick1hunks -nosym -o build/garea_probe tests/garea_probe.s`; execution:
`tests/garea_probe.sh assets/kick34005.A500 build/garea_probe <sortie> 240`. The diagrams in this document
are the decoding of `serial.log`. Tests T7 and T11 depend on the **residual contents** of the vertex
buffer (§4.7) and are not reference vectors for a clone.

## Open points

1. **Paths with a layer** (AreaEnd/Flood/WritePixel/ReadPixel in a window, hidden ClipRects,
   SuperBitMap): **deduced only**; the probe only uses a RastPort without a layer. In particular
   the origin of the pattern (layer or screen coordinates) within a layer is not observed.
2. **Negative coordinates / outside the BitMap in AreaEnd** (x0 rounded negative, rendering without a layer not
   clipped): deduced, not probed (write outside the buffer).
3. **TmpRas too small for Flood** (allocation of `Size` bytes then copy of a whole plane) and
   **TmpRas NULL for AreaEnd**: overflow/corruption deduced, not probed.
4. **Exact equality of AreaEnd's edges with Draw()**: both use the blitter's line drawing;
   pixel-for-pixel identity has only been verified on simple cases (T3, T25), not compared
   systematically with Draw.
5. **DrawEllipse in COMPLEMENT** with a zero radius (coincident symmetric points inverted twice?) and
   large radii (overflow of the 16-bit products beyond a radius of about 180 pixels): not probed.
6. **AreaMove failing to close** (Count left incremented): deduced, not observed.
7. Exact choice of the **omitted first point** in pass 1 for consecutive edges in the same direction separated by
   a horizontal edge: deduced (the horizontal edge does not change the stored direction), not probed.
8. **Timing** (AreaEnd, Flood) on real hardware or cycle-exact WinUAE: not measured (probe under FS-UAE).
9. Contents of D0 returned by AreaEnd on an empty list: undefined; the two values observed are not a
   rule.

## Clean-room review

- No ROM instruction sequence, no listing, no routine address: only public
  LVOs, offsets of public structures (`rastport.h`), flag values, orders of
  operations and observed pixels.
- The pixel diagrams are **outputs** of the real ROM (test vectors), not code.
