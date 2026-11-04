# graphics.library 34.1 — SetRast, RectFill, ScrollRaster, SetAPen/SetBPen/SetDrMd: behavioural spec

> **ANALYSIS** track ("dirty"). Source: **black-box calls on the real ROM** `assets/kick34005.A500` under Amiberry
> (A500 preset, cycle-exact, 512 KB chip + 512 KB slow), 2026-11-04, with the method of `graphics-line-v34.md`:
> the ROM was stopped at the first `Move` issued by the boot "insert disk" picture (a task context), the library
> vectors were then called one by one through a return trampoline placed in RAM by the debugger, with A6 =
> GfxBase (LayersBase for layers calls), on BitMaps (chip memory, surrounded by guard zones) and RastPorts
> allocated with `AllocMem` in that context; planes, RastPort fields, layer fields and custom registers were read
> back after each call. Memory failures were provoked by a debugger breakpoint on exec `AllocMem` that made a
> chosen call return 0. The ROM code was **not** read for this page. No program was written; the probe to write on
> the implementation side is described in §9.
> This document describes **behaviours**, **values**, **orders of operations** and **ABI layouts**. It contains
> no ROM instruction sequence nor routine address.
> It complements: `graphics-area-v34.md` (§5 fill patterns, §8 RectFill outline: both are refined here),
> `graphics-line-v34.md` (§2 the `+$1F` pattern byte and FRST_DOT, which SetAPen/SetBPen/SetDrMd reset; §8
> blitter ownership), `graphics-blitter-v34.md` (§6 use of `rp_minterms`), `graphics-text-v34.md` (ClearEOL and
> ClearScreen are RectFill callers), `layers-v34.md` (§2 Layer layout, DamageList, LAYERREFRESH),
> `graphics-regions-v34.md` (the region functions that hold the DamageList), `console-keymap-v34.md` §3.7
> (console scrolling through ScrollRaster).
>
> **Levels of proof**: **[O]** observed on the real ROM · **[D]** deduced from other analysis pages (cited) ·
> **[S]** reasonable assumption, not verified.
>
> Diagram conventions: one line per y (0 at the top), one column per x; `.` = colour 0, otherwise the colour
> digit (plane 0 = bit 0). Coordinates are RastPort coordinates (BitMap coordinates without a layer, layer
> coordinates with one) unless "screen" is said. Test vectors are in §8.

## 0. Summary for the implementer

- LVOs (public `graphics_lib.fd` order, bias 30, 6 bytes per slot): **SetRast −234** `(rp A1, pen D0)`,
  **RectFill −306** `(rp A1, xmin D0, ymin D1, xmax D2, ymax D3)`, **SetAPen −342** `(rp A1, pen D0)`,
  **SetBPen −348** `(rp A1, pen D0)`, **SetDrMd −354** `(rp A1, mode D0)`, **ScrollRaster −396**
  `(rp A1, dx D0, dy D1, xmin D2, ymin D3, xmax D4, ymax D5)`. None returns a value. [O]
- **Registers**: D2–D7 and A2–A6 are preserved by all six. SetAPen/SetBPen/SetDrMd change **D0 and D1**
  (A0/A1 preserved); SetRast changes **D1, A0, A1**; RectFill and ScrollRaster change **D0, D1, A0, A1**. [O]
- **SetAPen/SetBPen/SetDrMd** store the **low byte** of D0 in FgPen (+$19) / BgPen (+$1A) / DrawMode (+$1C),
  recompute **all eight** `minterms[]` bytes (+$28..+$2F) from FgPen, BgPen and `DrawMode & 7`, **set FRST_DOT**
  (bit 0 of Flags) and **write 15 into the byte at +$1F** — every time, even when the value does not change.
  Nothing else (AOlPen, +$1E, the other Flags bits, cp, Mask) is touched. Minterm table in §2. [O]
- **RectFill**: inclusive bounds; **no validation and no clipping without a layer** (linear addressing as Draw and
  WritePixel; reversed bounds produce huge blits, §3.2); **clipped by the layer** with a layer (SMART hidden parts
  go to the backing store, SIMPLE hidden parts are lost without damage). Per-pixel result as a function of
  DrawMode and the area pattern bit in §3.4 (INVERSVID inverts the pattern; COMPLEMENT|JAM2 inverts the whole
  rectangle). **Pattern phase is absolute in RastPort coordinates**: word `y mod 2^n`, bit 15 at `x mod 16 = 0`,
  in **layer** coordinates inside a layer. `rp_Mask` and the BitMap depth limit the planes; pen bits beyond the
  depth are ignored. RectFill does not change any RastPort field (cp included) except with AREAOUTLINE (§3.7).
  [O]
- **SetRast**: every plane `i < Depth` whose `Mask` bit is set is filled with bit `i` of the pen, over the **whole
  BitMap** (`BytesPerRow × Rows`) without a layer, over the **whole layer** (visible parts and SMART backing
  store, not the rest of the screen) with one. DrawMode, AreaPtrn, FgPen and the minterms are ignored. [O]
- **ScrollRaster**: positive dx/dy move the content **left/up** (`new(x,y) = old(x+dx, y+dy)`); the vacated
  strips are filled with **BgPen, solid, whatever DrawMode and AreaPtrn**; Mask honoured; no RastPort field
  changes. The max corner is clamped to the BitMap (no layer) or to the layer size; the min corner is **not**
  clamped. Without a layer, `|dx| ≥ width` or `|dy| ≥ height` (after clamping) or a reversed rectangle does
  **nothing at all**; with a layer there is no such test and the fill strip can spill outside the rectangle
  (§5.3). [O]
- **ScrollRaster on SIMPLE layers** (§5.4), two V34 defects: (1) the layer's existing DamageList is **offset by
  (+dx, +dy)**, i.e. in the direction opposite to the content; (2) the new damage (visible pixels whose source was
  in a hidden part) is recorded **one pixel too large** on the right and bottom. LAYERREFRESH is set when damage
  is added. A failed damage allocation is silently ignored. [O]
- **Blitter**: SetRast, RectFill and ScrollRaster return **before the last blit ends** (BBUSY observed set on
  return) with the blitter already released (`GfxBase+$AA` = `$FFFF`); WaitBlit before a processor access. All
  three are bounded by the blitter size fields: widths are taken **modulo 64 words** and heights **modulo 1024
  rows** (§6). [O]

## 1. Calling contract

### 1.1 Entry points [O]

| LVO | Function | Inputs | Result |
|---:|---|---|---|
| −234 | SetRast | rp A1, pen D0 | none |
| −306 | RectFill | rp A1, xmin D0, ymin D1, xmax D2, ymax D3 | none |
| −342 | SetAPen | rp A1, pen D0 | none |
| −348 | SetBPen | rp A1, pen D0 | none |
| −354 | SetDrMd | rp A1, mode D0 | none |
| −396 | ScrollRaster | rp A1, dx D0, dy D1, xmin D2, ymin D3, xmax D4, ymax D5 | none |

Coordinates and offsets are signed 16-bit words; pens and the mode are bytes (§2). A6 was GfxBase in every
observation; whether a function works with another A6 was not tested [S: keep A6 = GfxBase].

### 1.2 Registers on return [O]

Measured by calling each vector with marker values (`$1111000n`) in D0–D7/A0–A4 and checking A5/A6:

| Call | Changed | Notes |
|---|---|---|
| SetAPen, SetBPen, SetDrMd | D0, D1 | D1 left at `$0000FFFF` in every case; D0 holds a scratch value (e.g. `$10 + (mode & 7)` after SetDrMd) |
| SetRast | D1, A0, A1 | A0 = the custom chip base; D0 was preserved in the observed cases (do not rely on it) |
| RectFill | D0, D1, A0, A1 | A0 = custom chip base (no layer) or a layer-related pointer; with AREAOUTLINE A1 was preserved |
| ScrollRaster | D0, D1, A0, A1 | same with and without layer |

**No result**: D0 is never a meaningful value. D2–D7, A2–A6 preserved by all six in all paths tried (no layer,
SMART and SIMPLE layers, outline). [O]

### 1.3 Allocations [O]

None of the six functions calls `AllocMem`, without layer, in a SMART layer or in a SIMPLE layer, **except
ScrollRaster on a SIMPLE layer when it adds damage**: one `AllocMem(16, MEMF_CLEAR)` per damage rectangle (a
RegionRectangle, as OrRectRegion allocates them, graphics-regions §1). Failure path in §5.6.

## 2. SetAPen, SetBPen, SetDrMd

### 2.1 Fields written [O]

| Call | Field written | Always also |
|---|---|---|
| SetAPen(pen) | FgPen (+$19) = pen & $FF | minterms[0..7] recomputed, Flags \|= FRST_DOT, byte +$1F = 15 |
| SetBPen(pen) | BgPen (+$1A) = pen & $FF | same |
| SetDrMd(mode) | DrawMode (+$1C) = mode & $FF | same |

- Only the **low byte** of D0 is used: SetAPen(`$1234`) stores `$34`, SetAPen(`$FFFFFFFE`) stores `$FE`,
  SetDrMd(`$1205`) stores 5. [O]
- The byte is stored **as given**: SetDrMd(`$11`) leaves DrawMode = `$11` and SetDrMd(`$FF`) leaves `$FF`; the
  minterms use only `DrawMode & 7` (`$11` behaves as JAM2, 8 as JAM1, `$FF` as 7). Other functions test DrawMode
  for exact values (Draw "exactly 2", graphics-line §5.3; ClearEOL "exactly JAM2", graphics-text), so a clone
  must store the whole byte, not a masked mode. [O]
- FRST_DOT is set and +$1F reset to 15 **even if the new value equals the old one**; the other Flags bits
  (AREAOUTLINE, ONE_DOT …) are kept: Flags `$FFF0` became `$FFF1`. AOlPen (+$1B), `linpatcnt` (+$1E), Mask,
  cp, AreaPtrn/AreaPtSz are not touched. [O]
- The minterms are computed for **all eight planes**, whatever `Mask`, `rp_BitMap` (NULL works) and the BitMap
  depth; pen bits 0–7 are each used for the plane of the same number. [O]
- There is **no SetOPen function in V34**: AOlPen and AREAOUTLINE are set by the public `SetOPen` macro (direct
  field writes). SetAPen does not touch AOlPen. [O for SetAPen; the macro is from the public headers]

### 2.2 Minterm bytes [O]

For plane `i`, let `f` = bit `i` of FgPen and `b` = bit `i` of BgPen. `minterms[i]` (+$28 + i) is:

| `DrawMode & 7` | f=0, b=0 | f=1, b=0 | f=0, b=1 | f=1, b=1 |
|---|---|---|---|---|
| 0 JAM1 | `$2A` | `$EA` | `$2A` | `$EA` |
| 1 JAM2 | `$0A` | `$CA` | `$3A` | `$FA` |
| 2 COMPLEMENT | `$6A` | `$6A` | `$6A` | `$6A` |
| 3 COMPLEMENT\|JAM2 | `$5A` | `$5A` | `$5A` | `$5A` |
| 4 INVERSVID (JAM1) | `$8A` | `$BA` | `$8A` | `$BA` |
| 5 INVERSVID\|JAM2 | `$0A` | `$3A` | `$CA` | `$FA` |
| 6 INVERSVID\|COMPLEMENT | `$9A` | `$9A` | `$9A` | `$9A` |
| 7 | `$5A` | `$5A` | `$5A` | `$5A` |

Read as blitter minterms with A = the area being drawn, B = the pattern (or template) bit and C = the destination,
each value means "where A is 1, D = g(B, C), elsewhere D = C" with g: `$EA` B∨C, `$2A` C∧¬B, `$CA` B, `$0A` 0,
`$3A` ¬B, `$FA` 1, `$6A` B⊕C, `$5A` ¬C, `$BA` C∨¬B, `$8A` C∧B, `$9A` ¬(B⊕C). This reading matches every pixel
result of §3.4 and is the same use as BltTemplate's (graphics-blitter §6). After InitRastPort all eight bytes are
`$CA` (graphics-line §2). [O for the values and the pixel results; the A/B/C reading is an interpretation]

## 3. RectFill (−306)

### 3.1 Rectangle [O]

- Bounds are **inclusive**: RectFill(2,1,9,3) fills x 2..9, y 1..3 (24 pixels); RectFill(5,1,5,1) fills one
  pixel. [O]
- **No layer: no clipping at all**. Pixels are addressed linearly as Draw/WritePixel do (graphics-area §9.1):
  x ≥ `BytesPerRow × 8` continues on the next row, x < 0 on the previous row, y ≥ Rows writes past the plane
  (into the next plane or the memory after the BitMap). Observed on a 64 × 16 BitMap: (60,6)-(70,6) → row 6
  x 60..63 and row 7 x 0..6; (−3,9)-(2,9) → row 8 x 61..63 and row 9 x 0..2; (0,14)-(5,17) → rows 14..15 plus
  bytes in the guard after the planes. [O]
- **With a layer**: clipped to the layer through its ClipRects; parts hidden behind another layer go to the
  SMART layer's backing store (visible after the front layer is deleted) or are lost for a SIMPLE layer; RectFill
  adds **no damage** and does not set LAYERREFRESH. Observed: RectFill(−5,−3,60,40) in a SMART layer at screen
  (5,3)-(50,27) under a SIMPLE layer at (30,0)-(63,15) filled exactly the layer, nothing outside, and the hidden
  part reappeared filled when the front layer was deleted. [O]

### 3.2 Reversed bounds [O]

RectFill does **not** test `xmax < xmin` or `ymax < ymin`. Without a layer the observed results match a blit
of `((xmax >> 4) − (xmin >> 4) + 1) mod 64` words (0 meaning 64) by `(ymax − ymin + 1) mod 1024` rows (0
meaning 1024), starting at (xmin, ymin), with the first-word mask from `xmin & 15` and the last-word mask from
`xmax & 15` (both applied when the width is one word):

| Call (64 × 16 BitMap, 2 planes) | Result |
|---|---|
| (50,1)-(49,1), (45,3)-(40,1) | nothing visible (one word whose two masks do not overlap) |
| (16,4)-(15,4), (17,4)-(15,4), (18,4)-(3,4) | 1024 pixels from (xmin, 4) onwards: the rest of the BitMap and beyond |
| (20,1)-(12,3) | rows 1..3 each 64 words long, overlapping: whole BitMap and 282 guard bytes |
| (30,3)-(35,1), (55,2)-(58,1), (3,4)-(3,3) | the column range drawn down 1023 or 1024 rows, far past the BitMap |

With a layer the result is not empty either: three of four reversed rectangles wrote outside the layer and
outside the BitMap (only (16,4)-(15,4) drew nothing). **A program must never pass reversed bounds**; for a clone,
drawing nothing is the only sane choice and is what every observed same-word case looks like. [O]

### 3.3 Planes, pens, Mask [O]

- Planes written: `0 .. Depth − 1` of `rp_BitMap`, minus those whose `Mask` bit is clear (Mask 0 draws nothing).
- Each plane uses its own `minterms[i]`, so pen bits at or above the depth are ignored: APen 5 / BPen 6 on two
  planes draw colours 1 / 2.
- Mask 1, APen 3, JAM2 on a background `x/8 mod 4`: plane 0 set everywhere, plane 1 untouched (colours 0,1 →
  1; 2,3 → 3). Mask 2, APen 0: plane 1 cleared (2 → 0, 3 → 1). COMPLEMENT with Mask 1 inverts plane 0 only.
- With AREAOUTLINE the outline obeys Mask too (§3.7).

### 3.4 Draw modes and the area pattern [O]

Let `p` be the pattern bit of the pixel (1 when `AreaPtrn` is NULL). Result per pixel (A = FgPen, B = BgPen,
"invert" = every plane of Mask inverted):

| DrawMode | p = 1 | p = 0 | Solid (no pattern) |
|---|---|---|---|
| 0 JAM1 | A | unchanged | A |
| 1 JAM2 | A | B | A |
| 2 COMPLEMENT | invert | unchanged | invert |
| 3 COMPLEMENT\|JAM2 | invert | invert | invert |
| 4 INVERSVID | unchanged | A | **nothing** |
| 5 INVERSVID\|JAM2 | B | A | **B everywhere** |
| 6 INVERSVID\|COMPLEMENT | unchanged | invert | **nothing** |
| 7 | invert | invert | invert |

Observed with A = 1, B = 2 on a background whose colour is `(x / 8) mod 4` (all four colours under both pattern
values), pattern `$F0F0, $0F0F`, AreaPtSz 1: every (mode, background, p) combination gave the table's colour,
rows outside the rectangle intact. COMPLEMENT ignores both pens (background 0,1,2,3 → 3,2,1,0). [O]

### 3.5 Pattern addressing [O]

- **Monochrome** (`AreaPtSz = n ≥ 0`, byte +$1D): `2^n` words; the pixel (x, y) uses word `y mod 2^n` and bit
  `15 − (x mod 16)`, with **x and y in RastPort coordinates**, independent of the rectangle's corner. Observed:
  `$8001`, n = 0, RectFill(3,2,40,2) → pixels x 15, 16, 31, 32 only; four words `$8000,$4000,$2000,$1000`,
  n = 2, RectFill(0,1,15,6) → (1,1) (2,2) (3,3) (0,4) (1,5) (2,6); `$F000,$0F00`, n = 1, RectFill(5,3,30,5) →
  row 3 x 5..7 and 20..23, row 4 x 16..19, row 5 as row 3. [O]
- **Inside a layer the phase is in layer coordinates** (origin = the layer's `bounds.MinX/MinY`, not the screen):
  a SMART layer at screen (5,3), pattern `$F000,$0F00`, n = 1, JAM1, RectFill(0,0,20,3) in layer coordinates →
  screen rows 3 and 5: x 5..8 and 21..24; rows 4 and 6: x 9..12 and 25 (the rectangle ends at layer x 20). The
  same pixels came out when the right part of the layer was hidden behind a SMART layer and then uncovered (the
  backing store keeps the layer phase). This answers graphics-area open point 1 for RectFill. [O]
- **Multicolour** (`AreaPtSz = −n`): `2^n` words per plane, plane k's words at `AreaPtrn + k × 2^n` words; each
  plane combines **its own** pattern with **its own** minterm (§2.2). With plane 0 `$FF00,$FF00` and plane 1
  `$F0F0,$0F0F` on a background `(x/8) mod 4`, rows 1..3, x 0..31:

```
     multi APen 3 BPen 0 JAM2          multi APen 1 BPen 0 JAM1          multi APen 1 COMPLEMENT
  1  11113333....222211113333....2222  11111111111111113333111133331111  11113333111133333333111133331111
  2  333311112222....333311112222....  11111111111111111111333311113333  33331111333311111111333311113333
  3  11113333....222211113333....2222  11111111111111113333111133331111  11113333111133333333111133331111
```

  JAM2 with APen 3/BPen 0 reproduces the pattern colours; APen 0/BPen 3 gives the complement colours. In
  **JAM1 with APen 1**, plane 1 (pen bit 0) is **cleared where plane 1's pattern bit is 1**: on row 1 (plane 0
  `$FF00`, plane 1 `$0F0F`) the colour-2 background becomes 3 at x 16..19 (plane 1 pattern 0: kept; plane 0 set)
  but 1 at x 20..23 (plane 1 pattern 1: cleared). JAM1 does not leave the planes of the pen's zero bits alone.
  This refines graphics-area §5, whose T14 example used a colour-0 background where the clearing is invisible.
  [O]

### 3.6 RastPort fields and blitter [O]

- Without AREAOUTLINE, RectFill **changes no RastPort field**: cp, Flags, +$1E/+$1F, pens, minterms all
  unchanged (cp (33,7) stayed (33,7)). [O]
- The call returns **with the blit possibly still running**: after RectFill(0,0,319,199) on a 320 × 200 × 2
  BitMap, DMACONR had BBUSY set on return while `GfxBase+$AA` was already `$FFFF` (blitter free, as after Draw,
  graphics-line §8). [O]

### 3.7 Outline (AREAOUTLINE, Flags bit 3) [O]

Refines graphics-area §8. With `Flags & $0008`:

1. **Interior** first: the whole rectangle with the current pens, mode, pattern and Mask, except in COMPLEMENT
   where it is **shrunk by one pixel on each side** (nothing when that leaves no interior). [O]
2. **Outline** by Move(xmin,ymin), Draw(xmin,ymax), Draw(xmax,ymax), Draw(xmax,ymin), Draw(xmin,ymin) (the left
   side is drawn first, top to bottom, as the line-pattern phase shows), with **FgPen = AOlPen and JAM1**, the
   current **LinePtrn** and **Mask**. [O]
3. FgPen, DrawMode and minterms are back to their values on return; **cp = (xmin, ymin)**, **FRST_DOT clear**
   (the Draws cleared it), **+$1F = 15 − 2(W−1) − 2(H−1)** modulo 256 (W, H = width, height): `$F3` for
   (2,1)-(12,5), `$05` for (3,2)-(6,4). [O]

Consequences observed:

```
   JAM2 APen 1 AOl 2 (2,1)-(12,5)     COMPLEMENT on colour 3, AOl 2      JAM2 APen 1 BPen 3, AOl 2,
                                                                         AreaPtrn F0F0/0F0F, LinePtrn AAAA
     0123456789012                      0123456789012                      x 2..21
  1  ..22222222222                    1 33222222222223                   1 23212123232121232321
  2  ..21111111112                    2 332.........23                   2 11333311113333111132
  3  ..21111111112                    3 332.........23                   3 23111133331111333311
  4  ..21111111112                    4 332.........23                   4 11333311113333111132
  5  ..22222222222                    5 33222222222223                   5 23111133331111333311
                                                                         6 12323212123232121232
```

- The outline is JAM1 **even in COMPLEMENT** (edge = AOlPen 2, not an inversion) and **even in JAM2** (pattern
  zeros of LinePtrn keep the interior colour, right-hand diagram). [O]
- Degenerate rectangles: one pixel, one column, two columns (JAM2 and COMPLEMENT), two rows (COMPLEMENT) → only
  outline pixels (AOlPen). [O]
- With Mask 1 and AOlPen 2 the outline **clears plane 0** on the edge (JAM1 with pen bit 0) and cannot set plane
  1: a JAM1 APen 1 rectangle (2,1)-(12,5) ends with colour 1 only on x 3..11, y 2..4 and colour 0 on its edge. [O]
- Reversed bounds with outline (COMPLEMENT, (9,3)-(2,3)): the outline Draws ran (row 3 x 2..9 in AOlPen),
  nothing else changed in the observed area; cp = (9,3). In other modes the interior follows §3.2. [O]

## 4. SetRast (−234)

- **Without a layer**: for every plane `i < Depth` whose `Mask` bit is set, all `BytesPerRow × Rows` bytes are
  set to `$FF` if bit `i` of the pen is 1, `$00` otherwise (padding bits beyond the logical width included: a
  20-pixel-wide BitMap with BytesPerRow 4 got four `$FF` bytes per row). Nothing outside the planes is written.
  [O]
- Pen bits ≥ Depth are ignored (SetRast 5 on two planes → colour 1). Mask 1 with pen 3 sets plane 0 only; Mask 2
  with pen 0 clears plane 1 only; Mask 0 does nothing. [O]
- **DrawMode, FgPen, BgPen, minterms and AreaPtrn are ignored**: SetRast 2 with DrawMode COMPLEMENT and APen 1
  set before gives colour 2 everywhere; SetRast 1 with an AreaPtrn set gives solid colour 1. [O]
- **No RastPort field changes** (cp, Flags, +$1F, pens, minterms). [O]
- **With a layer**: only the layer is filled — its visible parts on the screen BitMap and, for a SMART layer, its
  hidden parts in the backing store (they reappear filled when the front layer is deleted); the rest of the
  screen is untouched; a SIMPLE layer's hidden part is not filled and **no damage** is added (Flags and DamageList
  unchanged). Mask is honoured in layers too. [O]
- Returns with the blit possibly still running (BBUSY set on return after a 64 × 8 × 2 SetRast). [O]
- Size limits: §6. [O]

## 5. ScrollRaster (−396)

### 5.1 Direction and the vacated area [O]

- For every pixel of the rectangle, `new(x, y) = old(x + dx, y + dy)` when (x + dx, y + dy) is inside the
  rectangle: **positive dx moves the content left, positive dy moves it up**. Checked pixel by pixel for
  (dx, dy) = (3,0), (−3,0), (0,2), (0,−2), (5,−3), (17,1) on a 64 × 16 × 2 BitMap. [O]
- The pixels whose source is outside the rectangle (the vacated strips: the `dx` rightmost columns for dx > 0,
  the `|dx|` leftmost for dx < 0, same for rows) are filled with **BgPen**, solid, in **every DrawMode** (0–6
  tried), **ignoring AreaPtrn** (a `$F0F0/$0F0F` pattern changed nothing), FgPen and the minterms. Bits of BgPen
  at or above the depth are ignored (BgPen 7 → 3 on two planes). [O]
- **Mask**: planes whose Mask bit is clear are neither moved nor filled (Mask 1: plane 0 scrolled and filled,
  plane 1 intact; Mask 0: nothing). [O]
- **No RastPort field changes**, including Flags, +$1E, +$1F, cp and minterms (checked with Flags 0, +$1F 3,
  JAM1|INVERSVID set before). [O]
- dx = dy = 0: nothing changes. [O]

### 5.2 Without a layer: bounds and the no-op cases [O]

1. `xmax` is clamped to `BytesPerRow × 8 − 1` and `ymax` to `Rows − 1`. On a BitMap with BytesPerRow 4 (20
   pixels of image), ScrollRaster(2, 0, 0, 1, 40, 2) moved x 0..29 and filled x **30..31**. [O]
2. `xmin` and `ymin` are **not** clamped: a negative corner addresses memory before the row or before the plane
   (wrap to the previous row, previous plane or memory before the BitMap). After ScrollRaster(2, 2, −100, −100,
   200, 200) the system crashed (Guru `00000004`, memory overwritten). [O]
3. With W = xmax − xmin + 1 and H = ymax − ymin + 1 **after** the clamp: if `|dx| ≥ W` or `|dy| ≥ H`, the call
   does **nothing** — no move and **no fill**. Hence a reversed rectangle (W ≤ 0) also does nothing. Observed
   on (8,2)-(40,10) (W 33, H 9): dx = ±33, ±50, dy = ±9, −30, (40,20), (33,1), (1,9) → unchanged; dx = ±32,
   dy = 8, (32,8) → normal (one column/row kept, the rest filled). On (50,2)-(80,4) clamped to W 14: dx = 14 →
   unchanged, dx = 13 → normal. Reversed x (40,2)-(8,10) → unchanged. [O]

### 5.3 With a layer [O]

1. `xmax`/`ymax` are clamped to the **layer** size minus one (layer coordinates), not to the BitMap: in a 46 × 25
   layer on a 64 × 32 screen, ScrollRaster(4, 3, −5, −5, 60, 60) filled layer x 42..45 and y 22..24. [O]
2. `xmin`/`ymin` are **not** clamped: with (−5,−5)-(60,60) and dx = −4, dy = −3, the content moved right/down by
   (4,3) but the vacated strips, computed at x −5..−2 and y −5..−3, lie outside the layer and **nothing was
   filled**: layer rows 0..2 and columns 0..3 kept their old content. Same with (−5,−5)-(45,24). [O]
3. **No "too large" test**: dx = 39 on a 39-wide rectangle (2,1)-(40,20) fills it; dx = 40 fills it **and column
   1** (outside the rectangle); dx = −60 fills it and columns 41..45 to the layer's right edge; dx = 101 on
   (0,0)-(100,100) fills the whole layer; dy = 20 on a 20-high rectangle fills it. The fill strip is
   `xmax − dx + 1 .. xmax` (dx > 0) or `xmin .. xmin − dx − 1` (dx < 0), over the rectangle's rows (same for
   dy), clipped to the layer only. [O]
4. The move goes through the ClipRects: SMART hidden parts are moved in the backing store consistently with the
   visible parts (SMART layer under a SIMPLE or SMART layer, checked after deleting the front layer); a SMART
   layer never gets damage. [O]
5. The fill in a layer is BgPen solid as in §5.1 (checked with COMPLEMENT + pattern, and with Mask 1). [O]

### 5.4 SIMPLE layers: damage [O]

Layer fields from layers-v34 §2: Flags at +$1E (LAYERREFRESH `$0080`), DamageList (a Region, layer coordinates)
at +$9C. For a layer with LAYERSIMPLE:

1. **Existing damage is offset by (+dx, +dy)** before anything else, whatever the rectangle: a DamageList
   (25,0)-(45,12) became (28,2)-(48,14) after ScrollRaster(3, 2, rectangle (2,1)-(40,20)) and (21,0)-(41,12)
   after dx = −4; the content moved the **other** way, so pending damage ends up on the wrong pixels (a V34
   defect). The whole region moves, including parts outside the rectangle. dx = dy = 0 leaves it unchanged. With
   an empty DamageList only its bounds move: `(0,0)-(0,0)` becomes `(dx,dy)-(dx,dy)` (e.g. (3,2)-(3,2),
   (−4,−3)-(−4,−3)), with no rectangle and LAYERREFRESH unchanged. [O]
2. **New damage**: the destination pixels that are **visible** and whose source pixel lies in a **hidden part
   without backing store** are left with their old content and added to the DamageList by OrRectRegion, each
   damage rectangle being **one pixel too large to the right and to the bottom** (MaxX + 1, MaxY + 1); then
   LAYERREFRESH is set. Pixels scrolled into hidden parts are lost, as for any drawing in a SIMPLE layer. [O]
3. No damage is added when no visible destination takes its source from a hidden part (e.g. the hidden part is
   to the right and dx ≤ 0), and LAYERREFRESH is then not set by ScrollRaster. [O]

Observed (SIMPLE layer at screen (5,3)-(50,27), 46 × 25, rectangle (2,1)-(40,20) unless said; a front SIMPLE layer
hides layer area (25..45, 0..12)):

| dx, dy | Exact visible area with a hidden source | DamageList after | Flags |
|---|---|---|---|
| 1, 0 | (24,1)-(24,12) | (24,1)-(25,13) | `$0081` |
| 0, 1 | none | empty, bounds (0,1) | `$0001` |
| −2, 0 | none | empty, bounds (−2,0) | `$0001` |
| 0, −2 | (25,13)-(40,14) | (25,13)-(41,15) | `$0081` |
| 3, 2 | (22,1)-(24,10) | (22,1)-(25,11) | `$0081` |
| −3, −2 | (28,13)-(40,14) | (28,13)-(41,15) | `$0081` |
| 2, 0, hidden (15..30, 5..11), rect = layer | (13,5)-(14,11) | (13,5)-(15,12) | `$0081` |
| 0, −2, same | (15,12)-(30,13) | (15,12)-(31,14) | `$0081` |
| 2, 1, same but the front layer SMART | (13,4)-(14,10) ∪ (15,4)-(28,4) | (13,4)-(15,11), (16,4)-(29,5) | `$0081` |

The last row shows the rectangles going through OrRectRegion one after the other (the second is cut by the
first, graphics-regions §4). Whether the front layer is SIMPLE or SMART does not matter: what counts is that the
**scrolled** layer is SIMPLE. [O]

### 5.5 Blitter and sizes [O]

- Returns with the blit possibly still running (BBUSY set on return after a dy = 8 scroll of a 320 × 200 × 2
  BitMap). [O]
- Rectangles wider than 1024 pixels are not handled: a dx = 1 scroll of a 1280-pixel row gave wrong pixels
  (§6). [O]

### 5.6 Memory failure [O]

When the damage allocation fails (`AllocMem(16, MEMF_CLEAR)` returning 0 on its first call), ScrollRaster returns
normally: no alert, the pixels are exactly as in the successful case, LAYERREFRESH is set, the DamageList bounds
are extended to the would-be rectangle but **the rectangle itself is missing** (the damage is lost). [O]

## 6. Size limits common to the three blitter functions [O]

| Call | BitMap | Result |
|---|---|---|
| RectFill(0,0,1279,0) | 1280 × 2 × 1 | x 0..255 only (80 words → 16) |
| RectFill(10,0,1100,0) | 1280 × 2 × 1 | x 10..76 (69 words → 5, last-word mask from 1100 & 15) |
| RectFill(0,0,15,1099) | 16 × 1100 × 1 | rows 0..75 only (1100 → 76) |
| SetRast(1) | 1280 × 2 × 1 | 256 pixels per row (BytesPerRow 160 → 16 words) |
| SetRast(1) | 16 × 1100 × 1 | rows 0..75 only |
| ScrollRaster(1,0, 0,0,1279,0) | 1280 × 2 × 1 | 409 wrong pixels on the row |

Widths are taken modulo 64 words and heights modulo 1024 rows, exactly as Draw truncates lines to `length mod
1024` (graphics-line §0). A BitMap taller than 1024 rows or wider than 1024 pixels is not fully cleared by SetRast
on 1.3. [O]

## 7. Notes for a clone (AutoDocs and AROS vs V34)

These are the places where an implementation written from the AutoDocs or from AROS can be expected to differ;
each is a V34 fact above:

1. **Set*Pen/SetDrMd side effects**: FRST_DOT set, +$1F = 15, eight minterms recomputed (§2). Draw's pattern
   phase and COMPLEMENT first dot depend on them (graphics-line §2). AROS keeps no minterms and uses
   `linpatcnt` (+$1E) instead of +$1F.
2. **DrawMode stored unmasked** (§2.1).
3. **INVERSVID in RectFill** inverts the pattern bit (§3.4): solid JAM1|INVERSVID and COMPLEMENT|INVERSVID draw
   nothing, JAM2|INVERSVID paints BgPen, COMPLEMENT|JAM2 inverts the whole rectangle.
4. **Pattern phase in layer coordinates** inside a layer (§3.5); multicolour JAM1 clears the planes of the pen's
   zero bits where the plane's pattern is set.
5. **No clipping without a layer** for RectFill and the min corner of ScrollRaster; clamping of the max corner
   only for ScrollRaster (§3.1, §5.2). A clone may clip to the BitMap instead of writing outside it; this is a
   deliberate difference only programs with bugs can see.
6. **Reversed RectFill bounds** draw garbage on 1.3 (§3.2); drawing nothing is the safe choice.
7. **ScrollRaster** fills with BgPen whatever the mode and pattern, does nothing without a layer when the shift
   is not smaller than the clamped rectangle, but spills its fill outside the rectangle in a layer (§5.2–§5.3).
   AROS-like code typically clips both corners and either fills through the layer's backfill or tests the size
   in both paths.
8. **SIMPLE-layer damage**: the existing damage offset in the wrong direction and the new damage one pixel too
   large (§5.4). A clone that moves damage the right way and records it exactly will repair slightly less than
   1.3 does; programs that rely on the 1.3 repair area are not known. Recommendation: record exact damage,
   offset by (−dx, −dy), and document the difference; or reproduce both defects if a program shows a
   difference.
9. **1024 limits** (§6): AROS clears or fills any size. Reproducing the truncation is not useful; documenting it
   is.
10. **Asynchrony**: the three blitter functions return before the blit ends; programs that read the planes with
    the processor must WaitBlit (as on real hardware). A synchronous clone is compatible.

## 8. Test vectors (summary)

All on a 64 × 16 × 2 BitMap (BytesPerRow 8) cleared to 0 unless said; "bg" = background `(x / 8) mod 4` over the
whole BitMap.

### 8.1 SetAPen / SetBPen / SetDrMd (from InitRastPort state: FgPen `$FF`, BgPen 0, JAM2, minterms `$CA`)

| Call | FgPen/BgPen/DrMd | minterms[0..7] | Flags / +$1F |
|---|---|---|---|
| SetAPen(3) | 3 / 0 / 1 | `CA CA 0A 0A 0A 0A 0A 0A` | `$0001` / 15 |
| SetAPen(5) | 5 / 0 / 1 | `CA 0A CA 0A 0A 0A 0A 0A` | |
| SetAPen(`$1234`) | `$34` | `0A 0A CA 0A CA CA 0A 0A` | |
| SetBPen(7) after APen `$FE` | `$FE` / 7 | `3A FA FA CA CA CA CA CA` | |
| A1 B0, SetDrMd(0..7) | | `EA 2A…`, `CA 0A…`, `6A…`, `5A…`, `BA 8A…`, `3A 0A…`, `9A…`, `5A…` | |
| A2 B1, SetDrMd(4) / (5) | | `8A BA 8A…` / `CA 3A 0A…` | |
| SetDrMd(`$11`) | DrMd `$11` | as JAM2 | |
| Flags `$FFF0`, +$1F `$44`, AOlPen `$55`; SetAPen(1) | | | Flags `$FFF1`, +$1F 15, AOlPen `$55` |

### 8.2 RectFill

| Setup | Call | Expected |
|---|---|---|
| A3 JAM2, cp (33,7) | (2,1)-(9,3) | x 2..9, y 1..3 colour 3; cp unchanged; D0 D1 A0 A1 changed |
| A3 | (5,1)-(5,1) | one pixel |
| A3 | (50,1)-(49,1) | nothing |
| A3 | (16,4)-(15,4) | 1024 pixels from (16,4) on (whole rest of the BitMap and beyond) |
| A3 | (60,6)-(70,6) | row 6 x 60..63, row 7 x 0..6 |
| A3 | (−3,9)-(2,9) | row 8 x 61..63, row 9 x 0..2 |
| A1 B2 on bg, modes 0..7, solid | (0,1)-(63,6) | per §3.4 last column: 1, 1, bg⊕3, bg⊕3, bg, 2, bg, bg⊕3 |
| A1 B2 on bg, `$F0F0/$0F0F` n 1 | (0,1)-(63,6) | per §3.4 |
| A5 B6 JAM2 | (0,1)-(63,6) | colour 1 (pattern: 1/2) |
| A3 JAM2 Mask 1 on bg | (0,1)-(63,6) | bg 0,1 → 1; 2,3 → 3 |
| A1 JAM1, `$8001` n 0 | (3,2)-(40,2) | x 15, 16, 31, 32 |
| A1 JAM1, 4 words n 2 | (0,1)-(15,6) | (1,1) (2,2) (3,3) (0,4) (1,5) (2,6) |
| multicolour §3.5 | (0,1)-(63,6) | §3.5 diagrams |
| JAM2 A1, AOl 2, AREAOUTLINE, cp (33,7) | (2,1)-(12,5) | §3.7 diagram; cp (2,1); Flags FRST_DOT clear; +$1F `$F3` |
| COMPLEMENT on colour 3, AOl 2, outline | (2,1)-(12,5) | edge 2, interior x 3..11 y 2..4 colour 0 |
| big | (0,0)-(319,199) on 320 × 200 × 2 | DMACONR BBUSY set on return, `GfxBase+$AA` = `$FFFF` |

### 8.3 SetRast

| Setup | Call | Expected |
|---|---|---|
| bg, A1 COMPLEMENT | SetRast(2) | all colour 2; rp unchanged; D1 A0 A1 changed |
| bg | SetRast(5) | all 1 |
| bg, Mask 1 | SetRast(3) | bg 0,1 → 1; 2,3 → 3 |
| bg, Mask 2 | SetRast(0) | bg 0,2 → 0; 1,3 → 1 |
| bg, Mask 0 | SetRast(1) | unchanged |
| 20 × 3 × 1 (BytesPerRow 4) | SetRast(1) | 12 bytes `$FF`, guards intact |
| SMART layer (5,3)-(50,27) under SIMPLE (30,0)-(63,15) on a 64 × 32 screen | SetRast(layer rp, 2) | layer area 2 (hidden part after deleting the front layer too), rest 0 |

### 8.4 ScrollRaster

Content `((x·7 + y·3) XOR (x >> 2)) mod 4`, BgPen 2, APen 1, JAM2, rectangle (8,2)-(40,10) unless said:

| dx, dy (rectangle) | Expected |
|---|---|
| 3, 0 / −3, 0 / 0, 2 / 0, −2 / 5, −3 | moved per §5.1, vacated strips colour 2 |
| 17, 1 on (3,1)-(60,14) | idem |
| 0, 0 | unchanged |
| 32, 0 / 0, 8 / 32, 8 | one column / row kept, rest colour 2 |
| 33, 0 / −33, 0 / 0, 9 / 0, −9 / 33, 1 / 1, 9 / 50, 0 / −50, 0 | **unchanged** |
| 3, 0 in modes 0, 2, 3, 4, 5, 6, with AreaPtrn | same as JAM2 |
| 3, 1 Mask 1 | plane 0 moved and filled (bit 0 of 2 = 0), plane 1 intact |
| 3, 0 on (50,2)-(80,4) | x 50..60 moved, 61..63 colour 2 |
| 14, 0 / 13, 0 on (50,2)-(80,4) | unchanged / normal |
| 3, 0 on (40,2)-(8,10) | unchanged |
| layer cases | §5.3, §5.4 table |

## 9. Probe to write (implementation side)

`tests/graster_probe.s` + `.sh`, modelled on `tests/gline_probe.s/.sh` (HUNK executable launched by the
startup-sequence of a floppy built with xdftool; results on the serial port; final marker such as `GRP fin`).
Everything through the public LVOs with A6 = GfxBase (LayersBase for layers calls).

**Setup**: one chip block holding the two planes of a **64 × 16** BitMap (256 bytes) with **1024-byte guards**
before and after (reversed-bounds tests write far: run them last, or skip R3 on our side if we clip); BitMap by
InitBitMap(2, 64, 16), RastPort by InitRastPort + `rp_BitMap`. Backgrounds written by the processor after WaitBlit:
"bg" = colour `(x / 8) mod 4`; "content" = `((x·7 + y·3) XOR (x >> 2)) mod 4`. A 16-byte chip block holds the area
patterns. Output per test: header (test id, `cp_x cp_y Flags FgPen BgPen DrawMode Mask +$1E +$1F` and the eight
minterms in hex), then 16 lines `plane0 plane1` as 8-byte hex rows (or only the rows named by the test), plus the
non-zero guard offsets where stated. Always WaitBlit before reading.

1. **R0 registers**: each of the six functions called with markers `$1111000n` in D0–D7/A0/A2–A5; print the
   changed registers (expected §1.2).
2. **R1 pens and modes**: the §8.1 sequence, printing the header after each call.
3. **R2 RectFill basics**: §8.2 rows 1–2 and the out-of-BitMap rows (60,6)-(70,6), (−3,9)-(2,9), with guards.
4. **R3 reversed bounds** (optional, see Setup): (50,1)-(49,1) only on our side if we clip; (16,4)-(15,4) shows the
   1.3 garbage and is for the oracle run only.
5. **R4 modes**: for modes 0..7, solid then with `$F0F0,$0F0F` (AreaPtSz 1), A1 B2, on bg, RectFill(0,1,63,6);
   print rows 0..7.
6. **R5 pattern phase**: the three §3.5 monochrome vectors; the multicolour vectors (A3 B0 JAM2, A1 B0 JAM1, A2 B1
   JAM2, A0 B3 JAM2, A1 B2 COMPLEMENT, A3 B0 JAM1, A3 B0 mode 4, A3 B0 mode 5) on bg.
7. **R6 Mask and pens**: §8.2 Mask/pen rows.
8. **R7 outline**: the three §3.7 diagrams (set AOlPen at +$1B and Flags bit 3 directly), the degenerate
   rectangles (40,2)-(40,2), (44,1)-(45,6), (50,1)-(50,6) in JAM2 and COMPLEMENT, Mask 1, printing the header
   after each (cp, Flags, +$1F).
9. **R8 SetRast**: §8.3 rows (the layer row in R10).
10. **R9 ScrollRaster without layer**: §8.4 rows on "content"; print the header to show that no field changes.
11. **R10 layers** on a 64 × 32 × 2 BitMap: NewLayerInfo; (a) SMART layer (5,3)-(50,27) under SIMPLE (30,0)-(63,15):
    RectFill(−5,−3,60,40) APen 3, dump, DeleteLayer(front), dump; SetRast(2) likewise; (b) pattern phase in a
    SMART layer at (5,3): `$F000,$0F00` RectFill(0,0,20,3) JAM1; (c) ScrollRaster in a SMART layer alone: the §5.3
    rows (−5,−5)-(60,60) with (−4,−3) and (4,3); dx 39/40/−60 on (2,1)-(40,20); (d) SIMPLE layer under SIMPLE
    (30,0)-(63,15), content drawn by columns (pen `x mod 4`) plus lines at y 2, 7, 13, 20 in pen 3 before the front
    layer is created: each §5.4 row, printing Flags (+$1E) and the DamageList (bounds and rectangles, +$9C);
    (e) existing damage: create, cover, delete the front layer, then ScrollRaster(3,2) and (−4,0), print the
    DamageList.
12. **R11 sizes**: §6 rows (1280 × 2 and 16 × 1100 BitMaps), printing the pixel counts.

## Open points

1. **SuperBitMap layers and Scroll_X/Scroll_Y ≠ 0**: not observed for any of the three functions (in particular
   whether the pattern phase and the ScrollRaster clamp use the SuperBitMap or the layer size).
2. **Layer locking** (LockLayerRom around the layer paths) and **blitter contention** with another owner: assumed
   as for Draw (graphics-line §7.6, §8), not observed here. [S]
3. **Reversed bounds in a layer** (§3.2): only four cases were tried; no rule was derived.
4. **ScrollRaster damage with several hidden ClipRects** or a hidden part that only partly overlaps the source:
   only one hidden ClipRect per test was used; the "+1 on the max side" is assumed to apply to each rectangle
   added. [S]
5. **The interior shrink of the outline** (§3.7 step 1) was observed with DrawMode exactly COMPLEMENT; whether
   COMPLEMENT|JAM2 or COMPLEMENT|INVERSVID also shrink is not known.
6. The observations were made by debugger-injected calls in the boot picture's task; a probe run from a CLI
   process (§9) should give the same figures but has not been run on the real ROM.

## Clean-room review

Review of 2026-11-04.

- [x] No 68000 instruction sequence transcribed or paraphrased, no disassembly excerpt, no ROM routine or data
  address. The ROM code was not read: every fact comes from black-box calls (registers, memory, custom registers)
  or from other analysis pages, which are cited.
- [x] The only numbers are public LVOs, public structure offsets (`rastport.h`, `clip.h`, `gfxbase.h`), the
  BlitLock value, custom-register bit meanings (BBUSY), memory flags, and coordinates/pixel values of our own test
  BitMaps and layers.
- [x] The minterm bytes of §2.2 are values found in a RastPort after public calls (observable ABI state); their
  A/B/C reading is our interpretation of the published blitter minterm convention.
- [x] The diagrams and tables are **outputs** of the real ROM on test inputs (test vectors), not ROM data.
- [x] No probe code was written by the analysis track; §9 describes one in words.
