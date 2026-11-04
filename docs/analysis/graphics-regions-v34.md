# graphics.library 34.1 — Region functions: behavioural spec

> **ANALYSIS** track ("dirty"). Sources: ROM `assets/kick34005.A500` (read only, radare2; disassembly notes kept
> outside the repository) and **black-box calls on the real ROM** under Amiberry (A500 preset, cycle-exact,
> 512 KB chip + 512 KB slow), 2026-11-04. The calls were injected with the debugger, with the method of
> `graphics-line-v34.md`: the ROM was stopped in a task context (the `input.device` task at the entry of its
> `Wait`), the library vectors were called one by one through a one-word return trampoline placed by the debugger,
> with A6 = GfxBase, and the regions were read back from memory after each call. Memory failures were provoked
> with a debugger breakpoint on exec `AllocMem` that made the N-th call return 0. No program was written for this
> page; the probe to write on the implementation side is described in §12.
> This document describes **behaviours**, **values**, **orders of results** and **ABI layouts**. It contains no
> ROM instruction sequence nor routine address.
> It complements: `layers-v34.md` §1.1 (BOOL value, first measured there), `installclipregion-v34.md` (how layers
> turns a region into ClipRects), `wb-icon-clipping-v34.md` (the Workbench's use of the DamageList), `alert-v34.md`
> (what a dead-end alert does).
>
> **Levels of proof**: **[O]** observed on the real ROM · **[D]** deduced from reading the ROM code (behaviour,
> not code) · **[S]** reasonable assumption, not verified.
>
> Notation: a rectangle is `(MinX,MinY)-(MaxX,MaxY)`, both corners **included**. A region is written
> `B=(bounds) [r1, r2, …]` where the `ri` are the RegionRectangle bounds **as stored** (relative to
> `bounds.MinX/MinY`) in list order. "abs" gives screen/layer coordinates (`bounds.Min + r`).

## 0. Summary for the implementer

- LVOs (checked against AROS `rom/graphics/graphics.conf`, bias 30, 6 bytes per slot, and against the V34 jump
  table, whose last vector is −654): **AndRectRegion −504** `(region A0, rect A1)`, **OrRectRegion −510**
  `(A0, A1)`, **NewRegion −516** `()`, **ClearRectRegion −522** `(A0, A1)`, **ClearRegion −528** `(A0)`,
  **DisposeRegion −534** `(A0)`, **XorRectRegion −558** `(A0, A1)`, **OrRegionRegion −612** `(R1 A0, R2 A1)`,
  **XorRegionRegion −618** `(R1 A0, R2 A1)`, **AndRegionRegion −624** `(R1 A0, R2 A1)`. The three region-region
  functions write their result into **R2**; R1 is never modified. [D][O]
- **Registers**: D0 = result; D1, A0, A1 are scratch; D2–D7 and A2–A6 are preserved by all ten. [O]
- **Layout**: Region = 12 bytes (`bounds` 8, `RegionRectangle` head pointer at +8); RegionRectangle = 16 bytes
  (`Next` +0, `Prev` +4, `bounds` +8, **relative to the region's `bounds.MinX/MinY`**). The **first** node's
  `Prev` is the address of the region's +8 field, not NULL; the last node's `Next` is NULL. [O]
- **Memory**: `AllocMem(12, MEMF_CLEAR)` per Region, `AllocMem(16, MEMF_CLEAR)` per rectangle (no MEMF_PUBLIC,
  any memory type), freed with the same sizes. [O]
- **No canonical form**: rectangles are disjoint but **never merged** (touching rectangles stay separate) and
  **never sorted**; the list order depends on the history and follows the exact rules of §4. [O]
- **Empty region** = head pointer NULL; every function tests emptiness by the pointer only. The bounds of an
  emptied region are **not** reset: after the normalising functions they are the previous origin **+ 15000** on
  both axes (§5). NewRegion and ClearRegion give `(0,0)-(0,0)`. [O]
- **Return values**: TRUE is 1. OrRectRegion returns 0 only when its first allocation fails; NewRegion returns
  NULL on failure; ClearRectRegion and AndRegionRegion return 0 only when their temporary NewRegion fails.
  XorRectRegion, OrRegionRegion and XorRegionRegion **always return 1**. Every other allocation failure inside
  these functions raises the **dead-end alert `$8201000B`** (AN_RegionMemory), which on 1.3 resets the machine
  (§6). [O]
- **AndRectRegion defect** (V34): its bounds step intersects the old bounds with the 8 bytes formed by the
  **rectangle pointer and the caller's return address** instead of with the rectangle. The rectangle list is
  still right and `bounds.MinX/MinY` are repaired by the final normalisation, but **`bounds.MaxX/MaxY` after
  AndRectRegion are meaningless** (§4.6, §5). [O]

## 1. Entry points and registers

| LVO | Function | In | D0 out | Allocations |
|---:|---|---|---|---|
| −504 | AndRectRegion(region, rect) | A0, A1 | void; see §7 | one 16-byte node per result rectangle not reused |
| −510 | OrRectRegion(region, rect) | A0, A1 | 1, or 0 if the first allocation fails | 1 + one per piece cut (§4.5) |
| −516 | NewRegion() | — | Region pointer, or 0 | 12 bytes |
| −522 | ClearRectRegion(region, rect) | A0, A1 | 1, or 0 if the temporary region cannot be allocated | 12 (temporary) + nodes |
| −528 | ClearRegion(region) | A0 | void (observed 0) | frees |
| −534 | DisposeRegion(region) | A0 | void (observed `$10`) | frees nodes + 12 |
| −558 | XorRectRegion(region, rect) | A0, A1 | always 1 | nodes |
| −612 | OrRegionRegion(R1, R2) | A0, A1 | always 1 | nodes |
| −618 | XorRegionRegion(R1, R2) | A0, A1 | always 1 | nodes |
| −624 | AndRegionRegion(R1, R2) | A0, A1 | 1, or 0 if one of the two temporary regions cannot be allocated | 2 × 12 (temporary) + nodes |

- Only the long pointers are used; `rect` points to a `struct Rectangle` (4 signed WORDs) which is **read, never
  written**. [D]
- Register check [O]: D1–D7, A0–A5 loaded with markers before each call. After the call D1, A0 and A1 had changed
  for every function that allocates or frees; all of D2–D7, A2–A5 and A6 (GfxBase) were intact in every case.
  AndRectRegion on an empty region and XorRegionRegion with an empty R1 changed **no** register at all (D0
  included for AndRectRegion; XorRegionRegion still set D0 = 1).
- A6 is not used by the region code; exec is reached through location 4. [D] No lock, no Forbid: a region shared
  between tasks must be protected by the caller. [D]
- No pointer is checked: `DisposeRegion(NULL)`/`ClearRegion(NULL)` write to low memory. [D] (not provoked)

## 2. Structures [O]

`struct Region` (12 bytes, public `graphics/regions.h`):

| Off. | Field | Content |
|---:|---|---|
| `$00` | `bounds.MinX` (WORD) | origin X of the node coordinates |
| `$02` | `bounds.MinY` (WORD) | origin Y |
| `$04` | `bounds.MaxX` (WORD) | see §5 (exact only after Or/AndRegionRegion) |
| `$06` | `bounds.MaxY` (WORD) | see §5 |
| `$08` | `RegionRectangle` | first node, NULL = empty region |

`struct RegionRectangle` (16 bytes):

| Off. | Field | Content |
|---:|---|---|
| `$00` | `Next` | next node, NULL for the last |
| `$04` | `Prev` | previous node; for the **first** node: `region + 8` (the address of the head field) |
| `$08` | `bounds` (4 WORDs) | MinX, MinY, MaxX, MaxY relative to `region.bounds.MinX/MinY` |

- Because `Next` is at offset 0, the head field at `region + 8` acts as a pseudo-node: unlinking the first node
  writes the region's head field through `Prev`. Every observed list (several hundred nodes over all vectors)
  had `first.Prev == region + 8` and `node.Prev == previous node`. Nodes are appended at the tail. [O]
- No count, no tail pointer, no flags. Freshly allocated memory is cleared (MEMF_CLEAR). [O]
- Absolute coordinates of a node: `region.bounds.MinX + node.MinX` (same for Y and for Max). Whenever an
  operation moves `bounds.MinX/MinY`, **all** existing nodes are shifted by the opposite amount, so the absolute
  coordinates of the kept rectangles never change. [O] (V2 step 5, V1 step 4)

## 3. Invariants and coordinate rules

- Rectangles are inclusive; two rectangles **overlap** when `A.MinX ≤ B.MaxX`, `A.MaxX ≥ B.MinX`, `A.MinY ≤ B.MaxY`
  and `A.MaxY ≥ B.MinY` (sharing one row or column counts as overlap; merely touching does not). [D][O]
- "A inside B" means all four of A's edges are within B's, equality included. [D]
- With valid inputs (`Min ≤ Max`) the rectangles of a region produced by these functions are **pairwise
  disjoint**. They are **not coalesced** (`(10,10)-(19,19)` then `(20,10)-(29,19)` gives two nodes) and **not
  sorted**. [O] (V2)
- All coordinates are 16-bit signed WORDs and every addition/subtraction is done on 16 bits (wraps). [O] (V3
  step 5, V10)
- **No validation** of the input rectangle. An inverted rectangle (`Min > Max`) is stored as is in an empty region
  and produces overlapping, inverted garbage when combined (V9). Callers must pass `Min ≤ Max`. [O]

## 4. Behaviour of each function

### 4.1 NewRegion (−516) [O]

Allocates 12 bytes with MEMF_CLEAR: bounds `(0,0)-(0,0)`, list NULL. Returns the pointer, or 0 if AllocMem fails
(nothing else happens; no alert).

### 4.2 ClearRegion (−528) [O]

Sets the four bounds words to 0, frees every node (FreeMem 16 each, list order), sets the head to NULL. On an
empty region it only zeroes the bounds. D0 observed 0 in both cases (not a contract).

### 4.3 DisposeRegion (−534) [O]

ClearRegion, then FreeMem(region, 12). D0 observed `$10` (left over; void).

### 4.4 The cutting rule (shared by Or, Xor, ClearRect) [O]

When a rectangle A must be reduced to "A outside B" and A overlaps B, A is replaced by up to four **bands**, in
this order, each produced only if non-empty:

1. **left**: columns `A.MinX .. B.MinX−1`, all rows of A;
2. **right**: columns `B.MaxX+1 .. A.MaxX`, all rows of A;
3. **top**: columns `max(A.MinX,B.MinX) .. min(A.MaxX,B.MaxX)`, rows `A.MinY .. B.MinY−1`;
4. **bottom**: same columns as top, rows `B.MaxY+1 .. A.MaxY`.

So the left and right bands take the full height of A, the top and bottom bands only the middle columns. Each band
is a new 16-byte node. If A does not overlap B, "A outside B" is A itself (a new node holding A's bounds in the
Xor case, §4.7). If A is inside B nothing is produced.

### 4.5 OrRectRegion (−510) [O]

In this order:
1. **Bounds**: if the region is empty, `bounds := rect`; otherwise `bounds := union(bounds, rect)`, and if the
   origin moved the existing nodes are shifted (§2). This happens **before** any allocation.
2. One node is allocated for the rectangle. **If this allocation fails, return 0**: the bounds stay enlarged, the
   list is unchanged (on an empty region: bounds = rect, list still NULL). [O] (F2a, F2b)
3. A **pending list** starts with the rectangle (relative to the new origin). For each existing node E, **in list
   order**, every pending rectangle that overlaps E is removed from the pending list and freed; if it was not
   inside E its bands outside E (§4.4) are appended **at the end of the pending list** (the other pending
   rectangles keep their order). Pending rectangles that do not overlap E are left in place.
4. The pending list is appended, in its order, at the **tail** of the region's list. Existing nodes are never
   modified, moved or merged.
5. Return 1.

Consequences: a rectangle already covered by one existing node, or equal to one, adds nothing (but one node is
still allocated and freed). Allocation failures in step 3 are dead-end alerts (§6). [O] (F3)

Example (V1 step 4): existing `[E1 (4,0)-(13,9), E2 (14,5)-(18,14), E3 (9,10)-(13,14), E4 (24,3)-(29,4)]`, new
`(0,2)-(34,6)` (relative). Against E1: pending `[(0,2)-(3,6), (14,2)-(34,6)]`. Against E2: the first does not
overlap, the second becomes right `(19,2)-(34,6)` and top `(14,2)-(18,4)`, appended: `[(0,2)-(3,6), (19,2)-(34,6),
(14,2)-(18,4)]`. E3: nothing. Against E4: `(19,2)-(34,6)` becomes left `(19,2)-(23,6)`, right `(30,2)-(34,6)`, top
`(24,2)-(29,2)`, bottom `(24,5)-(29,6)`, appended. Final tail: `(0,2)-(3,6), (14,2)-(18,4), (19,2)-(23,6),
(30,2)-(34,6), (24,2)-(29,2), (24,5)-(29,6)`.

### 4.6 AndRectRegion (−504) [O]

- **Empty region**: returns at once; nothing changes (bounds included), no register is touched, D0 is the
  caller's.
- Otherwise:
  1. **Bounds step (defective)**: the new bounds are the intersection of the old bounds with a "rectangle" `G`
     made of the **two words of the `rect` pointer** (`G.MinX` = high word, `G.MinY` = low word) followed by the
     **two words of the long at the top of the stack on entry**, i.e. the return address of the caller's JSR
     (`G.MaxX` = high word, `G.MaxY` = low word). The nodes are rebased to this origin (§2). The real rectangle is
     not used here. Proven by varying the pointer and the return address independently (V10) and by the state
     caught at an alert (F7: bounds `(192,21544)-(19,19)` for a rectangle pointer `$00C05428`).
  2. **Result list**, built from the existing nodes E in list order:
     - E does not overlap `rect` → E is dropped (freed);
     - `rect` is inside E (equality included) → the result is **exactly one new node holding `rect`**, and the
       remaining nodes are not examined (they are all dropped);
     - E is inside `rect` → **the same node** is kept (moved to the result, address unchanged);
     - otherwise → one new node `E ∩ rect` (never more than one piece); E is freed.
     The result keeps the order of the E it came from.
  3. **Normalisation** (§5): the origin moves to the minimum MinX and the minimum MinY over the result nodes, the
     same shift being added to `bounds.MaxX/MaxY`.
- Because step 3 recomputes MinX/MinY from the nodes, **the absolute rectangles and `bounds.MinX/MinY` are right**,
  whatever `G` was (barring 16-bit wrap when the pointer's low word is large and coordinates are far apart).
  **`bounds.MaxX/MaxY` are `min(oldMax, G.Max) + shift`**: a function of the caller's addresses (V10 shows −168,
  24, −187, 5 for the same call). Nothing may rely on them.
- An empty result leaves list NULL and bounds `I + 15000` on all four words (I = the step-1 intersection).
- Allocation failures (new node for `rect` or for `E ∩ rect`) are dead-end alerts. [O] (F7a, F7b)
- D0 on return (void function) = the Y shift of the normalisation as a zero-extended word (`$3A98` for an empty
  result, 0 when the minimum Y did not move, as in layers §1.1). Not a contract.

### 4.7 XorRectRegion (−558) [O]

- **Empty region**: behaves as OrRectRegion, but **returns 1 even when Or failed** (F4a: bounds = rect, list NULL,
  D0 = 1).
- Otherwise:
  1. Bounds step as Or (union, rebase), before any allocation.
  2. One node is allocated for `rect` (failure → dead-end alert, F4b).
  3. **First part of the result**: for each existing node E in list order, "E outside `rect`" by §4.4 — bands if E
     overlaps `rect`, a **new copy** of E if it does not, nothing if E is inside `rect`.
  4. **Second part**: `rect` minus every old E, computed with the pending-list rule of §4.5 (old nodes in their
     old order).
  5. The old nodes are all freed; the result is first part then second part; normalisation (§5).
  6. Return 1.
- Every node of the result is a new allocation. XOR-ing the same rectangle twice gives back the same area but not
  the same list (V4 steps 2–4).
- `bounds.MaxX/MaxY` = union max + normalisation shift: **overstated** whenever the minimum moved (V4 step 6:
  area `(5,0)-(9,9)`, bounds `(5,0)-(14,9)`).

### 4.8 ClearRectRegion (−522) [O for results and return, D for the composition]

Equivalent to: `T = NewRegion()` (failure → return 0, region untouched, F5); `OrRegionRegion(region, T)` (T = copy of
the region, same order); `AndRectRegion(T, rect)`; `XorRegionRegion(T, region)` (removes `T`'s rectangles from the
region); `DisposeRegion(T)`; return 1. Hence:
- the result order is that of XorRectRegion applied once per rectangle of `region ∩ rect` (V5);
- the bounds are left as they were, then normalised (§5): MinX/MinY exact, MaxX/MaxY overstated by the shift
  (V5 step 2: `(0,5)-(19,24)` for an area whose true maximum is `(19,19)`);
- a rectangle that misses the region leaves it unchanged (no normalisation shift) and returns 1;
- a failed allocation while copying the region into T is silently ignored (T incomplete, so less is cleared) [D];
  failures inside the And/Xor steps are dead-end alerts [D].

### 4.9 OrRegionRegion (−612) [O]

For each node of R1, in order, `OrRectRegion(R2, absolute rectangle)`. The individual results are **ignored**:
returns 1 even when an OrRectRegion failed (F8: R2 bounds include the lost rectangle, list without it). R2's bounds
stay exact (union). R1 empty → R2 untouched, returns 1.

### 4.10 XorRegionRegion (−618) [O]

For each node of R1, in order, `XorRectRegion(R2, absolute rectangle)`; returns 1. R1 empty → nothing at all is
touched (no register but D0 = 1). `XorRegionRegion(R, R)` walks a list that the first Xor frees: undefined, do not
use [D].

### 4.11 AndRegionRegion (−624) [O]

1. Allocates a result region and a temporary region (NewRegion ×2). If the first fails → return 0; if the second
   fails → the first is disposed, return 0. R2 untouched in both cases (F6a, F6b).
2. For each node r of R1, in order: the temporary becomes a copy of R2 (OrRegionRegion), is cut to r
   (AndRectRegion), is OR-ed into the result (OrRegionRegion), then cleared.
3. The temporary is disposed; R2's old nodes are freed and R2 takes over the result's list and bounds, then the
   normalisation of §5 runs; the result Region header is disposed. Return 1.

Result order: for each R1 rectangle in order, the intersections with R2's rectangles in R2's order. Bounds are
exact (union of the pieces, shift 0) when non-empty. An empty result (R1 empty, or disjoint) gives list NULL and
bounds `(15000,15000)-(15000,15000)`. Failed copies inside step 2 are ignored; failures inside the And step are
dead-end alerts [D].

## 5. Bounds after each function [O]

| Function | bounds.MinX/MinY | bounds.MaxX/MaxY | Emptied region |
|---|---|---|---|
| NewRegion, ClearRegion | 0 | 0 | `(0,0)-(0,0)` |
| OrRectRegion, OrRegionRegion | union, exact | union, exact | — (cannot empty) |
| XorRectRegion, XorRegionRegion | minimum of the nodes | union max + shift (≥ true max) | `union + 15000` |
| ClearRectRegion | minimum of the nodes | old max + shift (≥ true max) | `old bounds + 15000` |
| AndRectRegion | minimum of the nodes | **garbage** (§4.6) | `I + 15000` |
| AndRegionRegion | minimum of the nodes | exact | `(15000,15000)-(15000,15000)` |

**Normalisation** (And, Xor, ClearRect through Xor, AndRegionRegion): `sx` = the smallest node MinX, `sy` = the
smallest node MinY (starting from **15000** when there is no node). Every node is shifted by `(−sx, −sy)` and
**all four** bounds words get `+sx`/`+sy` (MinX, MaxX by sx; MinY, MaxY by sy). So MinX/MinY become the true
minimum, while MaxX/MaxY move by the same amount instead of being recomputed. With no node the bounds just move by
15000 (16-bit wrap possible, V3 step 5: MinY −30144).

OrRectRegion does **not** normalise; its MinX/MinY are already the true minimum because it only grows.

## 6. Memory and failure paths [O]

- Region: `AllocMem(12, $10000)` (MEMF_CLEAR only). Node: `AllocMem(16, $10000)`. FreeMem with 12 / 16. No other
  allocation; no use of the LayerInfo or of a private pool. [O]
- Counts observed (one call each): Or of an overlapping rectangle into one node: 3 allocations, 1 free (S1); Xor
  of a 4-node region with a small rectangle: 5 allocations, 4 frees (S2); ClearRect: 12 + 4 × 16, 4 × 16 + 12 freed
  (S3); And of a 4-node region giving 4 pieces: 4 allocations, 4 frees (S4); AndRegionRegion with one R1 rectangle
  and a 4-node R2: 2 × 12 + 12 × 16 allocated, matching frees (S5).
- Failure behaviour:

| Situation | Result | Vector |
|---|---|---|
| NewRegion | returns 0 | F1 |
| OrRectRegion, first node | returns 0; bounds already enlarged (empty region: bounds = rect, list NULL) | F2a, F2b |
| OrRectRegion, a band while cutting | dead-end alert `$8201000B` | F3 |
| XorRectRegion on an empty region | returns **1**; bounds = rect, list NULL | F4a |
| XorRectRegion, any node otherwise | dead-end alert | F4b |
| AndRectRegion, any node | dead-end alert | F7a, F7b |
| ClearRectRegion, temporary region | returns 0, region untouched | F5 |
| AndRegionRegion, 1st / 2nd temporary | returns 0, R2 untouched (1st freed in the 2nd case) | F6a, F6b |
| OrRegionRegion, an inner OrRect first node | ignored, returns 1, rectangle lost, bounds include it | F8 |

- The alert is exec `Alert($8201000B)` (AN_GraphicsLib | AN_RegionMemory | AT_DeadEnd). Observed: the machine
  resets and, at the next boot, shows "Not enough memory. Press left mouse button to continue. Guru Meditation
  #8201000B.00000000" (the second long is not meaningful here). See `alert-v34.md` for the dead-end path. A
  region operation interrupted this way never returns, so its half-built state does not matter. [O]

## 7. Return values (D0) [O]

| Function | D0 |
|---|---|
| NewRegion | Region pointer / 0 |
| OrRectRegion | 1 / 0 (first allocation failed) |
| XorRectRegion, OrRegionRegion, XorRegionRegion | always `$00000001` |
| ClearRectRegion, AndRegionRegion | 1 / 0 (temporary region not allocated) |
| AndRectRegion (void) | caller's D0 when the region is empty; otherwise the Y shift of the normalisation, zero-extended word (e.g. `$00000000`, `$00000005`, `$00003A98`, `$0000B05D`) |
| ClearRegion (void) | `$00000000` observed |
| DisposeRegion (void) | `$00000010` observed |

TRUE is always exactly 1 (consistent with layers-v34 §1.1).

## 8. Who depends on what

- layers.library walks the rectangle lists (ClipRegion, DamageList, the temporary V/O regions of
  `installclipregion-v34.md` §3.2) and uses `bounds.MinX/MinY` as the origin (installclipregion §2). That it builds
  its ClipRects in node order, so that the node order decides the ClipRect order, is assumed, not checked. [S]
- The Workbench uses NewRegion, ClearRegion, OrRectRegion, AndRectRegion, DisposeRegion on a layer's DamageList
  (`wb-icon-clipping-v34.md` §1). [D]
- Whether any V34 code reads `bounds.MaxX/MaxY` was **not searched** (open point 1); given §4.6, none could work
  after an AndRectRegion.

## 9. Requirements for our ROM

1. Exact layout (§2), including `first.Prev = region + 8`, tail insertion and 12/16-byte MEMF_CLEAR allocations.
2. The rectangle **sets** of §11 must be reproduced exactly. Reproducing the **order** and node reuse of §4 is
   recommended (it is cheap and keeps ClipRect order identical to 1.3); merging or sorting is not 1.3 behaviour.
3. `bounds.MinX/MinY` = origin of the nodes, equal to the true minimum after And/Xor/ClearRect/AndRegionRegion and
   to the union after Or. `bounds.MaxX/MaxY`: exact after Or/OrRegionRegion/AndRegionRegion; for Xor/ClearRect
   1.3 gives "old/union max + shift" (deterministic, reproducible); for AndRectRegion 1.3's value depends on the
   caller's addresses and cannot be relied upon: any value is compatible, the natural choice being the same rule
   with the real rectangle. The emptied-region bounds (`+15000`) need not be reproduced unless a program reads them
   (none known).
4. Return values of §7; in particular XorRectRegion/OrRegionRegion/XorRegionRegion return 1 unconditionally, and
   AndRectRegion leaves D0 alone on an empty region (programs must not rely on it either way).
5. Registers: preserve D2–D7/A2–A6.
6. Out of memory: the documented 1.3 outcomes are those of §6. Raising the same dead-end alert where 1.3 does is
   compatible; returning FALSE there instead is an acceptable divergence (no caller can depend on surviving a
   dead-end alert), but the four FALSE/0 paths and the "returns 1 anyway" paths should match.

## 10. Conventions of the test vectors

All vectors below start from NewRegion. Regions were filled with OrRectRegion. Rectangles passed as arguments are
absolute; region contents are given as stored (relative), with "abs" where it helps.

## 11. Test vectors [O]

### 11.1 OrRectRegion (V1, V2)

V1, one region:
1. Or `(0,0)-(9,9)` → `B=(0,0)-(9,9) [(0,0)-(9,9)]`
2. Or `(5,5)-(14,14)` → `B=(0,0)-(14,14) [(0,0)-(9,9), (10,5)-(14,14), (5,10)-(9,14)]`
3. Or `(20,3)-(25,4)` → `B=(0,0)-(25,14)`, `(20,3)-(25,4)` appended
4. Or `(−4,2)-(30,6)` → `B=(−4,0)-(30,14) [(4,0)-(13,9), (14,5)-(18,14), (9,10)-(13,14), (24,3)-(29,4), (0,2)-(3,6),
   (14,2)-(18,4), (19,2)-(23,6), (30,2)-(34,6), (24,2)-(29,2), (24,5)-(29,6)]` (rebased by +4 in X)

V2:
1. Or `(10,10)-(19,19)` → `B=(10,10)-(19,19) [(0,0)-(9,9)]`
2. Or `(12,12)-(15,15)` (inside) → unchanged, D0 = 1
3. Or `(10,10)-(19,19)` (equal) → unchanged, D0 = 1
4. Or `(20,10)-(29,19)` (touching) → `B=(10,10)-(29,19) [(0,0)-(9,9), (10,0)-(19,9)]` (no merge)
5. Or `(5,20)-(8,22)` → `B=(5,10)-(29,22) [(5,0)-(14,9), (15,0)-(24,9), (0,10)-(3,12)]`
6. ClearRegion → `B=(0,0)-(0,0)`, head NULL, D0 = 0

### 11.2 AndRectRegion (V3)

MaxX/MaxY are not given (garbage, §4.6), except where stated.
1. Empty region, And `(0,0)-(5,5)` → nothing changes, D0 and all registers unchanged.
2. `[(0,0)-(9,9), (10,0)-(19,9), (0,10)-(19,19)]` (B `(0,0)-(19,19)`), And `(5,5)-(14,14)` → MinX/MinY `(5,5)`,
   `[(0,0)-(4,4), (5,0)-(9,4), (0,5)-(9,9)]` = abs `(5,5)-(9,9), (10,5)-(14,9), (5,10)-(14,14)`; three new nodes.
3. `[(0,0)-(9,9)]`, And `(2,3)-(4,5)` → Min `(2,3)`, `[(0,0)-(2,2)]` (new node).
4. `B=(0,0)-(29,29) [(0,0)-(9,9), (20,20)-(29,29)]`, And `(0,0)-(25,25)` → Min `(0,0)`, `[(0,0)-(9,9)` **same node**,
   `(20,20)-(25,25)` new`]`.
5. `[(0,0)-(9,9)]`, And `(50,50)-(60,60)` → head NULL, D0 = `$3A98`, bounds `(15192,−30144)-(15009,15009)` (rect
   pointer `$00C0xxxx`; = I + 15000 with wrap). A following Or `(3,3)-(4,4)` gives `B=(3,3)-(4,4) [(0,0)-(1,1)]`.
6. `B=(10,10)-(29,29) [(0,0)-(19,19)]`, And `(0,0)-(99,99)` → same node kept, Min `(10,10)`; then And
   `(15,5)-(40,25)` → Min `(15,10)`, `[(0,0)-(14,15)]` = abs `(15,10)-(29,25)`.

### 11.3 XorRectRegion (V4), one region in sequence

1. Xor `(0,0)-(9,9)` on empty → `B=(0,0)-(9,9) [(0,0)-(9,9)]`
2. Xor `(5,5)-(14,14)` → `B=(0,0)-(14,14) [(0,0)-(4,9), (5,0)-(9,4), (10,5)-(14,14), (5,10)-(9,14)]`
3. Xor `(0,0)-(9,9)` → `B=(5,5)-(19,19) [(5,0)-(9,9), (0,5)-(4,9), (0,0)-(4,4)]` = abs `(10,5)-(14,14),
   (5,10)-(9,14), (5,5)-(9,9)`
4. Xor `(5,5)-(14,14)` → head NULL, `B=(15005,15005)-(15019,15019)`, D0 = 1
5. Xor `(0,0)-(9,9)` → `B=(0,0)-(9,9) [(0,0)-(9,9)]`
6. Xor `(0,0)-(4,9)` → `B=(5,0)-(14,9) [(0,0)-(4,9)]` (abs `(5,0)-(9,9)`; MaxX overstated by 5)
7. Xor `(5,0)-(9,9)` → head NULL, `B=(15005,15000)-(15014,15009)`

### 11.4 ClearRectRegion (V5), one region in sequence

1. `B=(0,0)-(19,19) [(0,0)-(19,19)]`, ClearRect `(5,5)-(9,9)` → `B=(0,0)-(19,19) [(0,0)-(4,19), (10,0)-(19,19),
   (5,0)-(9,4), (5,10)-(9,19)]`
2. ClearRect `(0,0)-(19,4)` → `B=(0,5)-(19,24) [(0,0)-(4,14), (10,0)-(19,14), (5,5)-(9,14)]` = abs `(0,5)-(4,19),
   (10,5)-(19,19), (5,10)-(9,19)`
3. ClearRect `(100,100)-(110,110)` → unchanged, D0 = 1
4. ClearRect `(−5,−5)-(30,30)` → head NULL, `B=(15005,15010)-(15024,15029)`, D0 = 1
5. DisposeRegion → D0 `$10`

### 11.5 Region-region (V6–V8); R1 = `B=(0,0)-(29,9) [(0,0)-(9,9), (20,0)-(29,9)]`, R2 = `B=(5,5)-(24,14) [(0,0)-(19,9)]`, rebuilt before each

- V6 OrRegionRegion(R1, R2) → R2 `B=(0,0)-(29,14) [(5,5)-(24,14), (0,0)-(4,9), (5,0)-(9,4), (25,0)-(29,9),
  (20,0)-(24,4)]`; R1 unchanged; D0 = 1.
- V7 XorRegionRegion(R1, R2) → R2 `B=(0,0)-(29,14) [(10,5)-(19,14), (20,10)-(24,14), (5,10)-(9,14), (0,0)-(4,9),
  (5,0)-(9,4), (25,0)-(29,9), (20,0)-(24,4)]`; D0 = 1.
- V8 AndRegionRegion(R1, R2) → R2 `B=(5,5)-(24,9) [(0,0)-(4,4), (15,0)-(19,4)]` (abs `(5,5)-(9,9), (20,5)-(24,9)`,
  bounds exact); R1 unchanged; D0 = 1.
- V8b R1 `[(0,0)-(9,9)]`, R2 `[(50,50)-(59,59)]`: AndRegionRegion → R2 head NULL, `B=(15000,15000)-(15000,15000)`,
  D0 = 1. Same with R1 empty.
- V8c R1 `[(0,0)-(9,9)]`, R2 empty: OrRegionRegion → R2 `B=(0,0)-(9,9) [(0,0)-(9,9)]`. Then R1 emptied:
  XorRegionRegion(R1, R2) → R2 unchanged, D0 = 1, no other register changed.

### 11.6 Inverted rectangles (V9, garbage in → garbage out)

- Empty, Or `(10,10)-(5,5)` → `B=(10,10)-(5,5) [(0,0)-(−5,−5)]`, D0 = 1; then Or `(0,0)-(19,19)` →
  `B=(0,0)-(19,19) [(10,10)-(5,5), (0,0)-(9,19), (6,0)-(19,19), (10,0)-(5,9), (10,6)-(5,19)]` (overlapping).
- `[(0,0)-(19,19)]`, Or `(10,10)-(5,5)` → unchanged (counts as inside); Xor `(10,10)-(5,5)` → `[(0,0)-(9,19),
  (6,0)-(19,19), (10,0)-(5,9), (10,6)-(5,19)]`.

### 11.7 AndRectRegion bounds versus addresses (V10)

Region `B=(0,0)-(19,19) [(0,0)-(19,19)]`, And `(5,5)-(14,14)`; the list is always `[(0,0)-(9,9)]` and MinX/MinY
`(5,5)`. P = rect pointer, Q = return address (long at the stack top on entry):

| P | Q | MaxX, MaxY | D0 |
|---|---|---|---|
| `$00C05298` | `$00C03726` | −168, −21120 | `$AD6D` |
| `$00C051A8` | `$00C03726` | −168, −20880 | `$AE5D` |
| `$0000B900` | `$00C03726` | 24, 24 | 5 |
| `$00C05668` | `$0000B930` | −187, 25293 | `$A99D` |
| `$0000B900` | `$0000B930` | 5, −18123 | 5 |

All five match `MaxX = min(19, hi(Q)) + 5 − max(0, hi(P))` and `MaxY = min(19, lo(Q)) + 5 − max(0, lo(P))` with
signed words and 16-bit wrap.

### 11.8 Allocation and failure vectors (S, F)

Allocation logs are in §6. Failures (N-th AllocMem returns 0):

| Id | Setup | Call, failing call | D0 | Region afterwards |
|---|---|---|---|---|
| F1 | — | NewRegion, #1 | 0 | — |
| F2a | empty | Or `(5,5)-(14,14)`, #1 | 0 | `B=(5,5)-(14,14)`, head NULL |
| F2b | `[(0,0)-(9,9)]` | Or `(5,5)-(14,14)`, #1 | 0 | `B=(0,0)-(14,14) [(0,0)-(9,9)]` |
| F3 | `[(0,0)-(9,9)]` | Or `(5,5)-(14,14)`, #2 | — | Alert `$8201000B` → reset, Guru at next boot |
| F4a | empty | Xor `(5,5)-(14,14)`, #1 | 1 | `B=(5,5)-(14,14)`, head NULL |
| F4b | `[(0,0)-(9,9)]` | Xor `(5,5)-(14,14)`, #1 | — | Alert `$8201000B` |
| F5 | `[(0,0)-(9,9)]` | ClearRect `(0,0)-(4,4)`, #1 (12 bytes) | 0 | unchanged |
| F6a | R1 `[(0,0)-(9,9)]`, R2 abs `(5,5)-(20,20)` | AndRegionRegion, #1 | 0 | R2 unchanged |
| F6b | same | AndRegionRegion, #2 | 0 | R2 unchanged; the first 12-byte region freed |
| F7a | `[(0,0)-(19,19)]` | And `(5,5)-(9,9)`, #1 | — | Alert `$8201000B` |
| F7b | `[(0,0)-(9,9), (10,0)-(19,9)]` | And `(5,5)-(14,14)`, #1 | — | Alert `$8201000B` |
| F8 | R1 `[(0,0)-(9,9), (20,0)-(29,9)]`, R2 empty | OrRegionRegion, #2 | 1 | R2 `B=(0,0)-(29,9) [(0,0)-(9,9)]` |

## 12. Probe to write (implementation side): `tests/gregion_probe.s` + `.sh`

Modelled on `tests/gtext_probe.s/.sh`: HUNK executable launched by the startup-sequence of a floppy built with
xdftool, output on the serial port between `GRG debut` and `GRG fin`. All calls through the public LVOs with
A6 = GfxBase (A6 = ExecBase for AllocMem/FreeMem/SetFunction).

**Dump format**, after every call: `<id> D0=xxxxxxxx C=<changed register mask> B=minx,miny,maxx,maxy N=<count>
L=<ok|bad>` then one line per node `  minx,miny,maxx,maxy` (relative, signed decimal), where `L` checks
`first.Prev == region+8`, `node.Prev == previous`, last `Next == 0`. For node identity (§4.6), print for each
node `=k` when its address equals the address of node k of the dump taken before the call, `+` otherwise.

**Tests** (expected = §11):

1. **R0 registers**: before every call, load D1–D7/A0–A5 with markers (`$1111000n`); the mask `C` lists the
   registers changed (expect only D1/A0/A1, or none for And on an empty region and Xor-region with an empty R1).
2. **R1–R6**: the sequences V1, V2, V3, V4, V5, V6–V8c, V9 of §11, each starting from a fresh NewRegion
   (or ClearRegion). For AndRectRegion also print the rect pointer and the return address of the JSR so that
   MaxX/MaxY can be checked against §11.7 offline; on our ROM compare only MinX/MinY and the nodes unless the
   implementation chose to reproduce the defect.
3. **R7 allocations**: SetFunction AllocMem and FreeMem with wrappers that log `size,flags` and the freed size to a
   RAM buffer (only while a "logging" flag is set around the region call), print the log after S1–S6 (§6).
4. **R8 failures**: the same AllocMem wrapper, with a countdown that makes the N-th call of the region function
   return 0; run F1, F2a, F2b, F4a, F5, F6a, F6b, F8 only (the alert cases F3, F4b, F7a, F7b reset the machine;
   if wanted, one of them per run as the last test, expecting the Guru `#8201000B` after the reset).
5. Restore the original vectors (SetFunction return values) before printing `GRG fin`.

## Open points

1. **Consumers of `bounds.MaxX/MaxY`**: layers, intuition and the Workbench were not searched for reads of these
   two words. If one exists it is already broken by the AndRectRegion defect on 1.3.
2. **16-bit wrap in AndRectRegion**: with a rect pointer whose low word is near `$7FFF` and node coordinates far
   from it, the relative coordinates can wrap and corrupt the result list. Deduced from §4.6 and §3, not provoked.
3. **ClearRectRegion / AndRegionRegion with a failed copy** (§4.8, §4.11): the silent loss is deduced, only the
   OrRegionRegion case (F8) was observed.
4. `DisposeRegion(NULL)`, `ClearRegion(NULL)`, `XorRegionRegion(R, R)`, `AndRegionRegion(R, R)`: not provoked
   (deduced unsafe or undefined).
5. The observations were made by debugger-injected calls from the `input.device` task context; a probe run from a
   CLI process (§12) should give the same lists (D0 values of the void functions may differ).

## Clean-room review

Review of 2026-11-04.

- [x] No 68000 instruction sequence transcribed or paraphrased, no disassembly excerpt, no ROM routine or data
  address. The only numbers are public LVOs, public structure offsets (`graphics/regions.h`), exec allocation
  flags, the alert number shown on screen, the constant 15000 observed in the bounds of emptied regions, and RAM
  addresses of our own test data (V10, F7).
- [x] The cutting and ordering rules (§4.4–§4.11) are stated as properties of the **results** and were each
  checked against the observed lists of §11; the compositions of §4.8–§4.11 are described in terms of public
  functions.
- [x] The AndRectRegion defect is described by its observable dependence on the caller's pointer and return
  address (V10), not by the code that causes it.
- [x] All lists and bounds in §11 are **outputs** of the real ROM on test inputs (test vectors).
- [x] No probe code was written by the analysis track; §12 describes one in words.
