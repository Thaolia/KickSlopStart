# graphics.library 34.1 — blitter operations: behavioural spec

> **ANALYSIS** track ("dirty"). Sources: ROM `assets/kick34005.A500` (read only, radare2, base
> `$FC0000`; disassembly notes outside the repository) and black-box probe `tests/gblit_probe.s`
> (harness `tests/gblit_probe.sh`) run on the **real ROM** under FS-UAE (PAL A500, 512 KB chip +
> 512 KB slow, DOS boot on a floppy whose startup-sequence launches the probe).
> This document describes **behaviours**, **values**, **orders of operations** and
> **ABI layouts**. It contains no ROM instruction sequence nor routine address.
> It complements, without repeating them: `fastfonts-ff.md` (BltTemplate contract as seen from FastFonts),
> `installclipregion-v34.md` (saving of the ClipRects by BltBitMap), `timer-v34.md` §6 (TOD alarm
> of CIA-B used by QBSBlit), `wb-icon-clipping-v34.md` §3 (use by the icons).
>
> **Levels of proof**: **[O]** observed by the probe on the real ROM · **[D]** deduced from reading
> the ROM code (behaviour, not code) · **[S]** reasonable assumption, not verified.

## 0. Summary for the implementer

- The core is **BltBitMap**: a **28-byte descriptor per plane** is prepared (at most 8, on the
  stack), then the function takes the blitter through the **OwnBlitter LVO**, programs the planes **one by one,
  waiting for BBUSY between each**, and gives the blitter back through the **DisownBlitter LVO** **without waiting for the end
  of the last plane** (unless it had to allocate a temporary buffer). [D]
- **Only the high nibble of the minterm counts** (function of B = source and C = destination); the low
  nibble is replaced by `$A`: channel A serves as an **edge mask** (BLTADAT = `$FFFF` or mask line
  in memory), and outside the mask the destination is copied as is. [D][O]
- **Overlap** is handled exactly when source and destination have the **same BytesPerRow**
  (criterion: comparison of the BytesPerRow and of the addresses, not of the BitMap identity): six walk
  schemes (§1.4), two of which use a **mask line in chip RAM** (TempA, 128 bytes allocated if
  the caller does not supply one). [D][O]
- **No validation** of the arguments in BltBitMap/BltTemplate (without a layer): no clipping to the
  BitMap bounds, no test of `NULL`/`-1` planes (they are treated as addresses), zero width
  or height = **maximal blit** of the hardware (64 words / 1024 lines). [D][O]
- The "RastPort" functions (BltBitMapRastPort, ClipBlit, BltMaskBitMapRastPort, BltTemplate,
  BltPattern) clip by the layer's **ClipRects** and call **BltBitMap through its LVO** (hence
  sensitive to SetFunction) once per visible or saved piece. [D]
- Blit queue: **QBlit** calls the function **immediately, in the caller's context**, if
  the blitter is free; otherwise the node is chained and the BLIT interrupt (level 3) unrolls the queue.
  **QBSBlit only waits for the beam if `gb_VBlank ≠ 0` or if a synchronised blit is already waiting**;
  otherwise it behaves like QBlit. [D][O]

## 1. BltBitMap (LVO −30)

### 1.1 Calling contract

`planes = BltBitMap(srcBM A0, srcX D0, srcY D1, dstBM A1, dstX D2, dstY D3, sizeX D4, sizeY D5,
minterm D6, mask D7, TempA A2)`, A6 = GfxBase. Only the **low words** of D0–D6 and the **low byte** of D7
are used. Registers preserved: D2–D7/A2–A6 (A0/A1/D1 destroyed). [D]

**Returned value (D0, long)**: the **number of planes actually blitted**, i.e.
`min(srcBM.Depth, dstBM.Depth)` minus the planes whose `mask` bit is 0. Returns **0 without doing
anything** (neither taking the blitter, nor waiting) if either of the two depths is 0 or if the `mask` byte
is 0. Planes walked from 0 upwards; bit *i* of `mask` selects plane *i*. [D]
Observed: depths 3→3, mask `$05` → 2; mask `$00` → 0; depths 2→3, mask `$FF` → 2;
3→3, `$FF` → 3. [O]

### 1.2 Arguments not validated

- **No clipping** to the dimensions of the BitMap (`Rows`, `BytesPerRow`); coordinates and sizes are
  converted to addresses by **unsigned** shifts (a negative X becomes a very large value).
  The line address uses a **signed 16-bit** multiplication `y × BytesPerRow`. [D]
- **`NULL` or `-1` planes**: no special handling in V34 (the convention "plane at 0 = all 0,
  plane at −1 = all 1" does not exist yet); the pointer is used as a plane address. [D]
- **sizeY = 0**: the height field of BLTSIZE is 0, i.e. **1024 lines** for the hardware. Observed:
  BltBitMap(…, 16 × 0) between two BitMaps of BytesPerRow 2 wrote **1024 lines**. [O]
- **sizeX = 0**: the computed number of words is 0 if dstX is a multiple of 16 (BLTSIZE width 0 =
  **64 words**, masks `$FFFF`), hence 128 bytes written per line. Observed: at x = 16, 64 words written
  on the line. If dstX is not a multiple of 16, one word is processed with a null mask (no visible
  effect). If dstX = 0, the computation overflows (width "−1" in unsigned) and **corrupts the height field**
  of BLTSIZE with an aberrant modulo: **write outside the BitMap**. [D][O]
- **Width > about 1008 pixels** (> 64 words, or > 62 words in the schemes with an extra word) and
  **height > 1024**: overflow the BLTSIZE fields (OCS limit), without check. [D]
- **Negatives**: negative sizeX/sizeY are not rejected (same overflow effect). [D]

The **contract to be respected** by a correct caller is therefore: 1 ≤ sizeX ≤ 1008 (or less depending on the
scheme), 1 ≤ sizeY ≤ 1024, rectangles entirely within the BitMaps. A compatible implementation may
reject the degenerate cases (return 0) without breaking known software; it must not "repair" them
otherwise. [S]

### 1.3 Blitter programming (common to all schemes)

Channels: **A = mask** (constant `$FFFF` in BLTADAT, except buffer schemes), **B = source**,
**C = D = destination** (same pointer, same modulo). BLTCON0 = `USEB|USEC|USED` (+ `USEA` for the
buffer schemes) | `(minterm & $F0)` | `$0A` | ASH shift; BLTCON1 = BSH shift (+ `DESC`).
The nibble `$0A` means: where A = 0 (outside the mask), D = C. [D]

Observed with source `$FF00`, destination `$F0F0`, 16 × 1: minterm `$C0`, `$CF`, `$C5` → all
`$FF00`; `$60` and `$6A` → both `$0FF0` (B xor C); `$30` → `$00FF`; `$0A` → `$0000`. The
low nibble is therefore **ignored** and the minterm `$0A` ("keep C" in the hardware sense) gives **0**: in V34,
the function is entirely defined by the high nibble, a null high nibble clears the area. [O]

Edge masks (tables of 16 words): first word = `$FFFF >> (x & 15)`; last word =
`$FFFF << (15 − ((x + w − 1) & 15))`, computed in **destination** coordinates in the ascending
schemes and in **source** coordinates in the descending schemes (where A is shifted by the same ASH as
B). [D]

**Register write order for each plane**, after a BBUSY wait: BLTCON0+BLTCON1 (one
long), BLTAFWM+BLTALWM (one long), then either BLTAPT + BLTAMOD (buffer), or BLTADAT = `$FFFF`; then
BLTBPT, BLTBMOD, BLTCPT, BLTDPT, BLTCMOD, BLTDMOD, and **BLTSIZE last** (starts the blit). [D]

**Overall sequence**: preparation of all the descriptors (possible filling of the mask buffer by the
processor) → **OwnBlitter through its LVO** → for each plane: BBUSY wait then
programming → **DisownBlitter through its LVO** just after the BLTSIZE of the last plane. If a buffer was
allocated by the function: BBUSY wait, then freeing. **No final wait otherwise**: a caller that
wants to read or write the destination with the processor must call WaitBlit. [D]

### 1.4 Choice of walk direction and overlap

Notation: `S` = address of the first source word of the first line, `D` same for destination,
`sx = srcX & 15`, `dx = dstX & 15`. Four walks are obtained by combining the blitter's ascending/
descending mode (direction within the line) and the **sign of the modulos** (direction of the lines: a
"negative" modulo of −(BytesPerRow + width) progresses opposite to the mode). [D]

| Case | Condition | Mode | Shift | Lines | Start |
|---|---|---|---|---|---|
| P1 | same BPR, D < S, dx ≥ sx | ascending | B shifted right by dx−sx | top → bottom | top-left corner |
| P2 | (different BPR, dx ≥ sx) or (same BPR, D ≥ S, dx > sx, D beyond the last source word of the line) | ascending | dx−sx | **bottom → top** | bottom-left corner |
| P3 | same BPR, D ≥ S, dx ≤ sx | descending | B and A shifted left by sx−dx | bottom → top | bottom-right corner |
| P4 | (different BPR, dx < sx) or (same BPR, D < S, dx < sx, last destination word of the line before S) | descending | sx−dx | **top → bottom** | top-right corner |
| P5 | same BPR, D < S, dx < sx, last destination word of the line ≥ S (slide left within the same line) | ascending + **channel A in memory** | (dx−sx) & 15, destination started **one word earlier** | top → bottom | |
| P6 | same BPR, D ≥ S, dx > sx, D ≤ last source word of the line (slide right within the same line) | descending + **channel A in memory** | (sx−dx) & 15, one more word to the right | top → bottom | |

Width in words: P1/P2 = extent in words of the **destination**; P3/P4 = extent of the **source**;
P5/P6 = destination extent **+ 2**. [D]

P5/P6 require a **mask line** of (destination extent + 2) words. P5: a null word, the first-word
mask (`$FFFF >> dx`), `$FFFF`s, the last word ANDed with the end mask. P6: the first-word
mask, `$FFFF`s, the last word ANDed with the end mask, then a null word. Observed: slide
from 2 → 5 over 40 px: `07FF FFFF FFF8 0000`; 20 → 3 over 30 px: `0000 1FFF FFFF 8000`; 3 → 20:
`0FFF FFFF C000 0000` (the 4th word, null, is the final word). [O] It is read by channel A with a negative modulo equal
to its length (the same line is re-read for each line). It is written by the processor **only once
per call** (the first plane concerned), into:
- **TempA** (A2) if the caller supplies it — after a BBUSY wait;
- otherwise a **128-byte** `MEMF_CHIP` block allocated by the function (once per call), freed at the end
  of the call after a BBUSY wait. If AllocMem fails, fallback to the last-resort buffer
  `gb_LCMptr` (§7). [D]

Consequence: 128 bytes limit these two schemes to 62 words + 2; beyond that the mask line overflows the
block. No other case uses TempA. [D]

Verification [O] (`gblit_probe`, BitMap 64 × 4, BytesPerRow 8, byte pattern `11 + 37 i`, minterm
`$C0`, TempA pre-filled with `$DEAD`): the 14 moves tested (left/right by 3, 17, 16 pixels within
the same line, up/down by one line with and without shift, diagonals) give **exactly** the
result of a "memmove" copy computed on the host; TempA is only modified for the horizontal
slides where the word addresses differ (P5/P6: 2 → 5, 20 → 3, 3 → 20) — **not** for 5 → 2
(same starting word, D = S: descending scheme P3, without buffer); with TempA = NULL the result is
identical (internal buffer); no guard byte (16 bytes on each side) is modified. [O]

## 2. WaitBlit (LVO −228)

Reads the BBUSY bit (bit 14 of DMACONR) **twice** — the first read absorbs the defect of the old
Agnus, which may show BBUSY = 0 just after the write of BLTSIZE — then, if busy, loops on the
read until BBUSY = 0. Touches no register (apart from CCR), uses neither A6 nor the stack apart from
the return, **does not take the blitter**, does not test BLTEN/DMAEN (if blitter DMA is turned off during a
blit, WaitBlit loops forever). Callable from an interrupt. [D]

The whole library uses the same **double read** before each register programming
(BltBitMap, BltTemplate, BltClear, QBlit queue, DisownBlitter). This is "real A500" point no. 1:
an implementation that tests BBUSY only once immediately after BLTSIZE may rewrite the
registers of a blit in progress. [D]

## 3. OwnBlitter (−456) / DisownBlitter (−462)

State in GfxBase (public layout `graphics/gfxbase.h`): `BlitLock` (WORD, $AA) = **count of
requesters − 1** (`−1` = free, initialised to −1), `BlitWaitQ` (List, $AE) = waiting tasks,
`Flags` ($A8, WORD): bit 1 = **the blitter belongs to the QBlit queue**, bit 2 = **handover pending**
(private). `BlitNest` ($AC) initialised to −1, not used by these functions. **`BlitOwner` ($BC) is never
written in V34.** [D] Observed: BlitLock = `$FFFF` before, `$0000` after OwnBlitter, `$FFFF` after
DisownBlitter; BlitOwner = 0; `Flags` = 0 after. [O]

**OwnBlitter**: increments BlitLock; if the result is 0, returns immediately (fast path: neither
Disable, nor Forbid, all registers preserved). Otherwise, under Disable: if the "handover pending" flag
is set, it is cleared and the task is the owner; otherwise the task places on its stack a 16-byte
node (the task pointer in the `ln_Name` field), clears the signal **SIGF_BLIT (bit 4,
`$10`)**, adds itself at the tail of BlitWaitQ and does `Wait($10)`; Enable. **Not nestable**: a second
OwnBlitter from the same task blocks forever. **Does not wait** for the end of a blit in progress (do
WaitBlit before writing the registers). Registers D0/D1/A0/A1 preserved. [D]

**DisownBlitter**: decrements BlitLock; if the result is negative (nobody else), returns
immediately. Otherwise, under Disable: if the QBlit queue or the synchronised queue is not empty, the
blitter is given to the queue (flag bit 1), the BLIT interrupt is enabled (INTENA SET|BLIT) and, if
the blitter is already idle, **caused** (INTREQ SET|BLIT); otherwise the first task of BlitWaitQ is
removed and receives `Signal(task, $10)`; if the list is empty (requester between its increment and its
AddTail), the "handover pending" flag is set. Enable. An **unpaired** DisownBlitter brings
BlitLock to −2 and the next OwnBlitter waits forever. [D]

Priority: **QBlit queue blits pass before the waiting tasks** at each DisownBlitter. [D]

## 4. BltClear (LVO −300)

`BltClear(memBlock A1, byteCount D0, flags D1)`. Takes the blitter **internally** (same protocol as
OwnBlitter but without going through the LVO), waits for BBUSY, programs BLTCON1 = 0, BLTDMOD = 0,
BLTCON0 = `$0100` (D only, minterm 0), BLTDPT = memBlock, then one or more BLTSIZEs; gives back the
blitter (internal DisownBlitter protocol). Nothing is returned (D0 undefined). [D]

- **flags bit 0**: wait for the end of the last blit before returning. Otherwise return during the clearing.
- **flags bit 1**: D0 = `(lines << 16) | bytesPerLine`. If bytesPerLine ≤ 128: **a single blit**
  height = lines, width = bytesPerLine / 2; the number of lines is taken **modulo 1024** (0 =
  1024) without check. If bytesPerLine > 128: the product lines × bytesPerLine (16 × 16 bits) is
  handled in linear mode.
- **Linear mode** (bit 1 at 0, or the case above): number of words = bytes / 2 (**a final odd byte
  is not cleared**); first one line of (words mod 64) words, then one blit of ⌊words/64⌋ mod 1024
  lines of 64 words, then as many blits of 1024 × 64 words (128 KB) as needed; the D pointer
  continues from one blit to the next; BBUSY wait between two BLTSIZEs.
- **Bit 2 (fill by value, V36)**: ignored. [D]

Observed: 7 bytes → 6 cleared, the 7th intact; `(1100 << 16) | 2`, flags 3 → **152** bytes cleared
(76 lines = 1100 mod 1024); `(3 << 16) | 130`, flags 3 → 390; 130 linear bytes → 130;
`(5 << 16) | 8` → 40. [O]

## 5. "RastPort" functions and clipping by the layers

### 5.1 Common TempA buffer

BltBitMapRastPort, ClipBlit and BltMaskBitMapRastPort obtain **first of all** a TempA: `TmpRas.RasPtr`
of the destination RastPort if `rp_TmpRas ≠ NULL` and `TmpRas.Size ≥ 128`; for ClipBlit, failing that the one
of the **source** RastPort; otherwise allocation of **128 bytes MEMF_CHIP** (fallback `gb_LCMptr`, §7),
freed at the end of the call **after WaitBlit**. This TempA is passed to each BltBitMap. [D]
Consequence: a RastPort with a TmpRas of ≥ 128 bytes avoids any allocation; the exits
with allocation **wait for the end** of the last blit before returning, the others do not. [D]

### 5.2 Destination clipping (BltBitMapRastPort, BltMaskBitMapRastPort, ClipBlit)

Plane mask = **`rp_Mask`** of the destination RastPort. [D]

- **Without a layer** (`rp_Layer = NULL`): a single BltBitMap to `rp_BitMap`, coordinates as they are,
  **without clipping**. [D]
- **With a layer**: lock of the layer (ObtainSemaphore on `Layer.Lock`, nestable) for the duration of
  the call. Destination rectangle converted to screen coordinates: `+ bounds.MinX − Scroll_X`,
  `+ bounds.MinY − Scroll_Y`. For each ClipRect of `Layer.ClipRect`, in list order:
  intersection (inclusive bounds); if not empty —
  - visible ClipRect (`lobs = NULL`): BltBitMap to `rp_BitMap` at screen coordinates;
  - hidden ClipRect with `cr_BitMap` (smart refresh): to `cr_BitMap`, X relative to `MinX & ~15`,
    Y relative to `MinY`;
  - hidden without BitMap (simple refresh): **ignored**.
  Then, if `Layer.SuperBitMap ≠ NULL`, for each ClipRect of `Layer.SuperClipRect`, intersection with
  the rectangle **in layer coordinates** and BltBitMap to the SuperBitMap. [D]
- **SUPER_BITMAP layer as destination of BltBitMapRastPort / BltMaskBitMapRastPort**: the function
  first synchronises the SuperBitMap from the screen (equivalent to SyncSBitMap), temporarily sets
  `rp_Layer = NULL` and `rp_BitMap = SuperBitMap`, blits **directly into the SuperBitMap without
  clipping**, restores, then copies back to the screen (equivalent to CopySBitMap). [D]

**BltBitMapRastPort (−606)**: `(srcBM A0, srcX D0, srcY D1, destRP A1, destX D2, destY D3, sizeX D4,
sizeY D5, minterm D6)`. Returns **always 1** (D0 = TRUE). [D] Observed: 1; ClipBlit without a layer: 1. [O]

### 5.3 ClipBlit (LVO −552)

`ClipBlit(srcRP A0, srcX D0, srcY D1, destRP A1, destX D2, destY D3, xSize D4, ySize D5, minterm D6)`.
Returns **1**. [D]

1. **Locks**: if both layers exist, are different and have the same `LayerInfo`, the
   LayerInfo semaphore is taken, then source lock, destination lock, then release of the LayerInfo
   (avoids deadlock); otherwise source lock then destination. Release: source then
   destination. [D]
2. **Same RastPort and SuperBitMap**: synchronisation, blit internal to the SuperBitMap without a layer,
   copy back (as in §5.2). [D]
3. **Same RastPort, source and destination rectangles that touch**: the `Layer.ClipRect` list is
   **re-sorted in place, permanently** (the `prev` fields are rebuilt) so that the pieces are
   copied in the safe order: for two ClipRects that overlap vertically, sort by MinX in the
   direction opposite to the horizontal move (move to the right → rightmost ClipRect
   first); otherwise sort by MinY in the direction opposite to the vertical move. [D]
4. **Source clipping**: without a source layer, a single pass with `srcRP.BitMap`; with a layer, the
   source rectangle (screen coordinates of the source layer) is intersected with each ClipRect of the
   source (BitMap = `rp_BitMap`, `cr_BitMap` or ignored, as in §5.2), then with the `SuperClipRect`s
   (BitMap = SuperBitMap). Each source piece is sent to the **destination clipping** of §5.2 with the
   destination position shifted by the same amount. The result is the intersection of the visible or
   saved parts on both sides; a hidden source part without backup **leaves the destination
   intact**. [D]
5. The rectangles are **not** checked: xSize/ySize ≤ 0 produce "empty inverted" intersections
   which are still passed to BltBitMap (cf. §1.2). [D]

### 5.4 BltMaskBitMapRastPort (LVO −636)

`(srcBM A0, srcX D0, srcY D1, destRP A1, destX D2, destY D3, sizeX D4, sizeY D5, minterm D6,
bltMask A2)`. Nothing is returned (D0 undefined). [D]

- **bltMask = NULL: the function does nothing** (no lock, no blit). [D][O]
- Otherwise a dummy BitMap is built on the stack: header copied from `srcBM` (hence **same
  BytesPerRow, Rows, Depth**), all planes pointing to `bltMask`. The mask must therefore have the
  geometry of one plane of the source and be in chip RAM. [D]
- Three complete passes of the destination clipping (§5.2), each over all the planes of `rp_Mask` and all
  the ClipRects: (1) source → destination, minterm **`$90`** (D = ¬(B ⊕ C)); (2) mask → destination,
  **caller's minterm**; (3) source → destination, `$90`. With the documented minterm
  `ABC|ABNC|ANBC` (`$E0`, D = B ∨ C) one gets "source where the mask is 1, destination intact
  elsewhere"; with `ANBC` (`$20`) "source inverted through the mask". [D][O]
- Visible effect: the destination goes through two intermediate states (possible flicker), cost ≈ 3
  BltBitMaps. [D]

Observed (32 × 1, source `$FF00FF00`, destination `$0F0F0F0F`, mask `$FFFF0000`): `$E0` →
`$FF000F0F`; `$20` → `$00FF0F0F`; NULL mask → `$0F0F0F0F` (unchanged). [O]

## 6. BltTemplate (LVO −36)

Calling contract described in `fastfonts-ff.md` §2/Requirements; what follows details the V34 behaviour.

- **Planes**: from 0 to `Depth − 1` of the destination BitMap, skipped if the corresponding bit of `rp_Mask`
  is 0. **Minterm of plane i = `rp_minterms[i]`** (8-byte array at offset `$28` of the RastPort,
  precomputed by SetAPen/SetBPen/SetDrMd) OR `$0A`, with USEB|USEC|USED (+USEA/shift depending on the
  scheme). B = template (modulo `srcMod − width`), C = D = destination plane, A = edge mask. [D]
- **A single descriptor** (same geometry for all planes) built by the same engine as
  BltBitMap (same six schemes, "source BytesPerRow" = srcMod). BLTADAT/masks/BLTCON1/modulos are
  written **only for the first plane**; afterwards only BLTCON0, BLTBPT, BLTCPT, BLTDPT, BLTSIZE. BBUSY wait
  before each plane. Taking/giving back the blitter through the **LVOs** OwnBlitter/DisownBlitter, no
  final wait. [D]
- **Without a layer**: no clipping (contrary to what `fastfonts-ff.md` Requirements asks, the ROM
  clips **neither** to the BitMap bounds **nor** negative coordinates). **xSrc is not normalised**:
  only its low 4 bits shift; its word part (xSrc ≥ 16) does **not** advance the template pointer.
  [D] Observed (template `$0000 $FFFF $0F0F`, JAM2, APen 1, BPen 0, 16 × 1): xSrc 0 → `$0000`, xSrc 16 →
  `$0000` (and not `$FFFF`), xSrc 4 → `$000F` (in all three cases the second word `$5555` is intact). [O]
- **With a layer**: `LockLayerRom` / `UnlockLayerRom` **through their LVOs** (−432/−438, layer in A5) around
  the whole call. Coordinates converted as in §5.2; for each ClipRect, clipping on the left/at the top
  (advance of xSrc and of the pointer by `srcMod` per skipped line), clipping on the right/at the bottom, piece skipped
  if width ≤ 0 or height ≤ 0; **then xSrc is normalised** (pointer + (xSrc ≫ 4) × 2, xSrc & 15) —
  so xSrc ≥ 16 works with a layer. Destination: rp_BitMap, cr_BitMap (relative to `MinX & ~15`,
  `MinY`), skipped if hidden without BitMap; then SuperClipRects to the SuperBitMap. [D]
- Returned value: none (D0 undefined). [D]
- The A2 register passed to the common engine is the **destination BitMap** pointer: if the template
  overlapped a line of the destination with srcMod = BytesPerRow (schemes P5/P6), the mask line
  would be written into the BitMap structure. Pathological case, not to be reproduced. [D]

## 7. Temporary allocation and last-resort memory

All the blitter's temporary allocations go through one allocator: `AllocMem(size,
MEMF_CHIP)`; on failure, if size > 2048 → `Alert($82011234)`; then (and in all cases
of failure) the **`gb_LastChanceMemory`** semaphore (GfxBase $E0) is taken and the block **`gb_LCMptr`**
(GfxBase $E4), **2048 bytes of chip** allocated at the library's initialisation, is used; the corresponding
freeing releases the semaphore if the pointer is `gb_LCMptr`, otherwise FreeMem. The last-resort
buffer therefore **serialises** all the blits short of memory. [D]

Sizes requested: 128 bytes (TempA of BltBitMap and of the RastPort functions); BltPattern: `bytecnt ×
height` (realigned copy of the mask, §8). [D]

## 8. BltPattern (LVO −312)

`BltPattern(rp A1, mask A0, xl D0, yl D1, maxX D2, maxY D3, bytecnt D4)`, **inclusive** bounds. [D]

- Without a layer: direct engine; with a layer: engine clipped by ClipRects (same logic as §5.2). [D]
- **mask = NULL**: fill of the rectangle (C, D active, BLTCON0 `$0300`|minterm), edge masks
  `$FFFF >> (xl & 15)` / complement of `$FFFF >> ((maxX + 1) & 15)`. Pattern `rp_AreaPtrn` on `2^|AreaPtSz|`
  lines (AreaPtSz < 0 = multicolour pattern, one pattern per plane), pens and mode via `rp_minterms`. [D]
- **mask ≠ NULL**: channel A = mask, A modulo = `bytecnt − width`, A shift = `xl & 15`. If the
  width in words of the rectangle does not match `bytecnt`, the mask is **copied and realigned** into
  a temporary chip buffer of `bytecnt × height` bytes (BltClear then BltBitMap `$CA` of one plane),
  freed after WaitBlit. [D]
- Returned value: none. Fine behaviour of the engine (≈ 3.6 KB) not entirely described here: see
  "Open points". [D]

## 9. QBlit (−276) and QBSBlit (−294): blit queues

Node (`hardware/blit.h`, `struct bltnode`, 18 bytes): `n` (+0, next), `function` (+4), `stat`
(+8, byte, `CLEANUP = $40`), `blitsize` (+$A, not used by the ROM), `beamsync` (+$C, line),
`cleanup` (+$E). GfxBase: `blthd/blttl` ($3A/$3E) normal queue, `bsblthd/bsblttl` ($42/$46) synchronised
queue, `BeamSync` ($A2, WORD) = beamsync of the first waiting synchronised node, `VBlank` ($A0,
byte). [D]

### 9.1 Call of the user function

- Entry: **A0 = `$DFF000`**, **A1 = node**, A6 = GfxBase (direct call); the function may destroy
  D0/D1/A0/A1 (A5 is reloaded by the ROM). [D] Observed: A0 = `$00DFF000`, A1 = node, A6 = GfxBase,
  **SR = `$0000`** (user mode, IPL 0: call from the task, interrupts masked only by
  Disable/INTENA). [O]
- **Exit: the result is read in the condition codes (Z)**, not in D0: Z = 1 ("0") = node
  finished; Z = 0 = the function has started a blit and wants to be called again. A function must therefore end with
  an instruction that sets Z according to D0 (e.g. `moveq`). [D]
- Before each call the ROM waits for the blitter to be idle (double BBUSY test). [D]
- If the function returns "non-zero" and the blitter is **already idle** on return (no blit started,
  or a very short blit), the ROM **calls the function again immediately** (in a task: briefly opening
  Disable/Enable between two calls). Observed: a function returning non-zero twice without starting a
  blit is called 3 times before QBlit returns, then `cleanup` once. [O]
- End of a node: BBUSY wait, call of `cleanup` if `stat & CLEANUP`, BlitLock decremented.

### 9.2 QBlit

Sets `n = NULL`, then under Disable + Forbid: if the normal queue is not empty, added at the tail
(BlitLock incremented, INTENA SET|BLIT). Otherwise increment of BlitLock: if the blitter is **free**, the
function is called **right away, in the caller's context** (task), with the
"blitter to the queue" flag set and the BLIT interrupt acknowledged, until it returns "finished" or
a blit is in progress (the node then becomes the head of the queue and the BLIT interrupt takes over);
if the blitter is **held** by a task, the node becomes the head of the queue and waits for the DisownBlitter.
Permit + Enable. Observed: synchronous call (before QBlit returns) when the blitter is free. [D][O]

### 9.3 BLIT interrupt (level 3, vector set by SetIntVector, is_Data = GfxBase)

Acknowledges INTREQ BLIT; if the normal queue is empty, processes the synchronised queue (below); if the
"blitter to the queue" flag is not set, exits (the blitter belongs to a task); otherwise loops:
call of the head, end of node (§9.1), move to the next. Queue emptied: clearing of the flag, handover
to the waiting tasks (§3) and **INTENA CLR|BLIT**. [D]

### 9.4 QBSBlit and beam synchronisation

- **If `gb_VBlank = 0` and `gb_BeamSync = 0`: QBSBlit behaves exactly like QBlit** (beamsync
  ignored). `gb_VBlank` is **reset to 0 by graphics' VBlank server at every frame** and set to 1 by
  **DrawGList**; outside the use of GELs, QBSBlit therefore does not wait for the beam. [D] Observed: node with
  beamsync = 200 submitted at line 50 → function called **at line 51**, before the
  return of QBSBlit (return at line 53); `gb_VBlank` = 0 and `gb_BeamSync` = 0; two identical attempts. [O]
- Otherwise: beamsync is capped at `gb_MaxDisplayRow`; if the synchronised queue is not empty, added at the
  tail (**no sorting by line**); otherwise, if the normal queue is busy, the node becomes the synchronised
  head (BeamSync = its line, INTENA SET|BLIT); otherwise, if the current line (VPOSR/VHPOSR) is
  **before** beamsync, the **CIA-B TOD alarm** is programmed (TOD = line counter, reset to the
  current line by the VBlank server; value divided by 2 if bit `$0002` of `gb_system_bplcon0`
  is set) and the node waits; if the line is already reached: execution as QBlit.
- In the BLIT interrupt, when the normal queue is empty and `BeamSync ≠ 0`: current line (0 read
  as MaxDisplayRow + 1) ≥ BeamSync → the synchronised head moves to the head of the normal queue and is
  executed; otherwise, if `gb_VBlank ≠ 0`, re-arming of the alarm (with, if a VERTB is pending, a
  brief window at IPL 2 to let it through), and if `gb_VBlank = 0` **the whole synchronised queue is
  transferred in front of the normal queue** and executed without waiting. [D]
- Alarm server (ICR bit 2, cf. `timer-v34.md` §6): disables the alarm; if the normal queue is
  empty, enables and **causes** the BLIT interrupt. [D]

## 10. Initialisation (as far as the blitter is concerned)

At graphics init: BLTCON0 = BLTCON1 = 0, a BLTSIZE `$0041` (1 word × 1 line) before and after
DMACON SET|BLTEN (`$8040`); BLIT vector set by **SetIntVector** (no server chain);
VBlank server added (AddIntServer); CIA-B TOD alarm registered (AddICRVector bit 2) and CRB
bit 7 (alarm write) set; BlitLock = BlitNest = −1, BlitWaitQ and TOF_WaitQ lists initialised;
LCM block of 2048 bytes of chip + semaphore. **The BLTPRI ("nasty") bit is never set by graphics V34.** [D]

## 11. "Real A500" points

1. **Chip RAM mandatory**: planes, templates, masks, TempA, TmpRas must be in chip (512 KB on
   OCS: addresses < `$80000`). The ROM checks nothing: a plane in slow RAM (`$C00000`) is read/written by
   the blitter at the truncated address (data from another chip area). The ROM's internal allocations
   all request MEMF_CHIP. [D]
2. **BBUSY**: systematic double read (§2) before any programming. [D]
3. **No nasty mode**: the 68000 keeps its cycles during graphics blits; software that sets
   BLTPRI itself changes the timings, not the semantics. [D]
4. **No final wait** in BltBitMap/BltTemplate/BltClear (bit 0 at 0)/ClipBlit without allocation:
   the first processor access to the destination must be preceded by WaitBlit (FastFonts, Workbench and
   intuition do it). An "instantaneous" emulator hides the omission. [D]
5. The OCS limits of BLTSIZE (1024 lines, 64 words) apply **without check** (§1.2, §4). [D][O]

## 12. What links the blitter to the layers

- layers.library saves/restores the hidden ClipRects by **BltBitMap** via graphics' LVO
  (`installclipregion-v34.md` §3); the "X relative to `MinX & ~15`" rule of cr_BitMap (§5.2) is the
  same on both sides. [D]
- The locks taken by the blitter on the graphics side are: `Layer.Lock` (direct ObtainSemaphore) for
  BltBitMapRastPort/ClipBlit/BltMaskBitMapRastPort, `LockLayerRom` (LVO) for BltTemplate; the LayerInfo
  only transiently in ClipBlit (§5.3). All nestable for the same task. [D]
- ClipBlit **modifies the order of the `Layer.ClipRect` list** (§5.3): the layers must not depend
  on that order. [D]

## Open points

1. **BltPattern**: only the main cases are described (null mask, realigned mask, pattern); the
   exact choice of modulos and the handling of the multicolour pattern have not been probed. To be probed before
   fine implementation.
2. **QBSBlit behaviour when `gb_VBlank ≠ 0`** (after DrawGList): the TOD alarm logic is
   deduced but **not observed**; the effect of bit `$0002` of `gb_system_bplcon0` (division by 2) is
   not explained (ERSY? interlace?).
3. **Real behaviour of Agnus** for the degenerate cases of §1.2 (dstX = 0, sizeX = 0): deduced, not
   probed (writes outside the buffer, dangerous for the probe).
4. **`NULL`/`-1` planes**: not probed (write into low memory); the "raw address" conclusion is
   deduced.
5. **Order of the ClipRects after sorting** when ClipRects overlap both in X and in Y in a
   non-transitive way: the insertion sort is not a total order relation; the resulting order for
   complex arrangements has not been verified.
6. **128-byte mask buffer** beyond 62 words (≈ 990 pixels, very wide SuperBitMap):
   overflow deduced, not probed.
7. **Bit 0 of `stat`** and `blitsize` field of the bltnode: not read by the ROM according to the code; no
   probe.
8. The paths **with a layer** (hidden ClipRects, SuperBitMap, ClipBlit sorting) are **deduced
   only**: the probe only uses RastPorts without a layer. A probe in a window (covered smart refresh)
   would be the logical next step.

## Clean-room review

Review of 2026-10-29.

- [x] No 68000 instruction sequence transcribed or paraphrased, no disassembly excerpt,
  no ROM routine address (only addresses: custom registers `$DFF000`, chip/slow RAM).
- [x] The engines (BltBitMap, BltTemplate, BltClear, QBlit/QBSBlit queues) are described by **calling
  contracts, order of the blitter register writes, choice of scheme and observed results** [O]; the
  mention "instruction that sets Z" (§9.1) is a constraint imposed on the caller's functions,
  not ROM code.
- [x] No ROM data beyond the ABI: public offsets of `GfxBase`/`RastPort`/`bltnode`, register values
  (BLTCON0, computed edge masks), alert code `$82011234`, buffer sizes.
- [x] The probe cited (`tests/gblit_probe.s`) is author code.
