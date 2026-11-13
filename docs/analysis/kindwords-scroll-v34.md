# kindwords-scroll-v34.md — KindWords 2.0 (FR) page-down call trace on KS 1.3

> **ANALYSIS** track ("dirty"). Sources: real ROM `assets/kick34005.A500` running in vAmigaWeb
> analysis sessions on vAmiga core 4.3.6 (A500 OCS, 512 KB chip + 512 KB slow, no fast RAM).
> Two independent probe sessions: `kwana1` (2026-11-13) and `kwana3` (2026-11-13).
> KindWords disk 1 (Program) in DF0, disk 2 (Superfont/Dictionnaire) in DF1.
> Document "lettre exemple" opened from the Workbench "Exemples" drawer.
> Two page-down clicks in the empty scroll-bar gutter (each scrolling to the next page).
>
> Method: RetroShell breakpoints at LVO entry points of graphics.library and layers.library; CPU
> registers and public structure fields (RastPort, Layer, TextFont, BitMap) read while paused at each
> entry. All addresses observed are in chip or slow RAM (libraries loaded by the system). No ROM
> address or instruction sequence was read; no ROM routine was disassembled.
> Screenshots examined and confirmed clean: `build/vamigaweb/analysis/kwana3/after_pd2.png`
> (after second page-down: table + paragraph with special characters, no residual pixels).
>
> **Legend**: **[O]** observed directly at a breakpoint or watchpoint · **[S]** structurally deduced
> from observed values and public spec. No instruction listing, no ROM address.

---

## 0. Summary of findings

On Kickstart 1.3 (v34.5), KindWords 2.0 (FR) performs a page-down scroll by **redrawing the entire
visible document content directly on the window's RastPort**, outside any `BeginUpdate`/`EndUpdate`
pair. The key result that explains the clean display on 1.3: KindWords' Superfont (named
`Symboles.font`) and its secondary disk font (`Romain 14.font`) both have `tf_YSize = 10` and
KindWords draws with a **10-pixel line spacing**, so adjacent text lines are perfectly adjacent in
the bitplane — no inter-line gap rows exist. Because each Text call uses `DrawMode = JAM2`, every
row in the document content area that contains a text line is overwritten with `BgPen` (white) for
all non-glyph pixels.

No `ScrollRaster`, `SetRast`, `BltClear` (application level), `ClearEOL`, or `ClearScreen` call was
observed during the content redraw on the real ROM.

---

## 1. Window and layer state [O]

| Field | Value |
|---|---|
| Layer flags (`+$1E`) | `0x0081` = `LAYERSIMPLE` \| `LAYERREFRESH` |
| Window refresh type | `SIMPLE_REFRESH` (no backing store) |
| GZZ flag | not set |
| Layer bounds (screen coordinates) | MinX=0, MinY=3, MaxX=639, MaxY=199 |
| Number of visible ClipRects | **1** |
| Visible ClipRect bounds | (0, 3) − (639, 199) — the full window area |
| ClipRect lobs | NULL (visible, not hidden) |
| ClipRect cr_BitMap | NULL (confirmed SIMPLE, no backing store) |
| RastPort Mask (`+$18`) | `0xFF` (all planes) |
| RastPort Depth | 2 planes |
| Screen width / BytesPerRow | 640 px / 80 bytes |

The KindWords document window is a full-width SIMPLE_REFRESH window covering rows 3–199 of the
640×200 OCS screen, with exactly one ClipRect spanning the whole area. [O]

---

## 2. Fonts in GfxBase at three moments [O]

GfxBase's TextFonts list (`GfxBase+$8C`) is walked at three points. The list contains **two** fonts
at boot, **three** after the letter opens, and **four** during the second page-down.

### 2.1 Workbench ready, before KindWords starts

| Font name | `tf_YSize` | `tf_XSize` | `tf_Baseline` | `tf_Style` | `tf_Flags` | `tf_LoChar`..`tf_HiChar` | `tf_Accessors` |
|---|--:|--:|--:|---|---|---|--:|
| `topaz.font` | **9** | 10 | 6 | `FSF_EXTENDED` (`$08`) | `FPF_ROMFONT \| FPF_TALLDOT \| FPF_DESIGNED` (`$49`) | `$20`..`$FF` | 3 |
| `topaz.font` | 8 | 8 | 6 | 0 | `FPF_ROMFONT \| FPF_DESIGNED` (`$41`) | `$20`..`$FF` | 6 |

List order: **topaz 9 first, topaz 8 second** — consistent with the boot behaviour described in
`graphics-text-v34.md` §2. `GfxBase.DefaultFont` (at `GfxBase+$9A`) = topaz 8: the
`devs:system-configuration` on KindWords disk 1 sets the system font to height 8 (same behaviour
as the Workbench 1.3.3 disk). [O]

### 2.2 After KindWords has opened the letter (before the first page-down)

| Font name | `tf_YSize` | `tf_XSize` | `tf_Baseline` | `tf_Style` | `tf_Flags` | `tf_LoChar`..`tf_HiChar` | `tf_Accessors` |
|---|--:|--:|--:|---|---|---|--:|
| `topaz.font` | 9 | 10 | 6 | `FSF_EXTENDED` (`$08`) | `$49` | `$20`..`$FF` | 6 |
| `topaz.font` | 8 | 8 | 6 | 0 | `$41` | `$20`..`$FF` | 4 |
| `Symboles.font` | **10** | 8 | **7** | 0 | `FPF_DISKFONT \| FPF_DESIGNED` (`$42`) | `$21`..`$FF` | 1 |

**topaz 9 is still present** — it was never removed (no `RemFont` call was observed during the entire
KindWords session). The accessor counts reflect prior Workbench usage; KindWords itself never calls
`OpenFont` for topaz 9. [O]

`Symboles.font` is KindWords' Superfont, loaded from the second disk by `diskfont.library`. An
`AddFont(Symboles.font)` call was observed at a breakpoint before the letter was displayed:
`diskfont.library` loaded the font on-demand when KindWords called `OpenDiskFont` for it.
`tf_YSize = 10`, `tf_Baseline = 7`, 8 pixels wide; `LoChar = $21`. [O]

`GfxBase.DefaultFont` = topaz 8 throughout. [O]

### 2.3 During and after the second page-down

| Font name | `tf_YSize` | `tf_XSize` | `tf_Baseline` | `tf_Style` | `tf_Flags` | `tf_LoChar`..`tf_HiChar` | `tf_Accessors` |
|---|--:|--:|--:|---|---|---|--:|
| `topaz.font` | 9 | 10 | 6 | `$08` | `$49` | `$20`..`$FF` | 6 |
| `topaz.font` | 8 | 8 | 6 | 0 | `$41` | `$20`..`$FF` | 4 |
| `Symboles.font` | 10 | 8 | 7 | 0 | `$42` | `$21`..`$FF` | 1 |
| `Romain 14.font` | **10** | 8 | **7** | 0 | `FPF_DISKFONT \| FPF_DESIGNED` (`$42`) | `$21`..`$FF` | 1 |

`Romain 14.font` was loaded on-demand by a second `AddFont` call (from `diskfont.library`, triggered
by KindWords' `OpenDiskFont`) during the first page-down, when the content lines that use this font
were drawn for the first time. It has the same geometry as `Symboles.font` (YSize 10, Baseline 7,
8 pixels wide) and is used on some body text lines alongside `Symboles.font`. [O]

**topaz 9 never appears in body-text `Text()` calls** — KindWords only uses topaz 8 for ruler marks
and UI text. [O]

---

## 3. LVOs **not** called during the page-down content redraw [O]

The following calls were monitored with breakpoints throughout both page-down sequences. None of them
fired during the document content redraw phase (the blitter/gadget activity during the scroll-bar
update does call a small `RectFill` for the scroll thumb; that is listed in §4):

| LVO | Function | Observation |
|--:|---|---|
| −396 | `ScrollRaster` | Never fired (15-second monitored timeout with no hit) |
| −234 | `SetRast` | Never fired (monitored through full scroll, no hit) |
| −300 | `BltClear` (application-level) | No hit outside Text's internal call |
| −42 | `ClearEOL` | No hit |
| −48 | `ClearScreen` | No hit |
| −552 | `ClipBlit` | No hit for content drawing |
| −72 | `ScrollLayer` (layers) | No hit |
| −486 | `RemFont` | No hit during the entire KindWords session |

---

## 4. Observed call sequence during first and second page-down [O]

Tags: **[O]** directly observed · **[S]** structurally deduced.

### 4.1 Scroll-bar gadget update (immediately after the click)

Before any content redraw, Intuition/KindWords updates the scroll-bar thumb:

| Step | LVO | Function | Key arguments |
|---|--:|---|---|
| 1 | −306 | `RectFill` | rp = window RastPort, xMin≈626, xMax≈635 (scroll-bar track strip, 10 px wide), yMin/yMax varies; DrawMode JAM2, BgPen 1 |

[O] The click position was in the gutter area of the vertical scroll bar (right edge of the 640-px
window). One `RectFill` with a narrow x-range (≈ 626–635) redraws the scroll-bar track strip.

### 4.2 Content redraw — ruler

| Step | LVO | Function | Key arguments |
|---|--:|---|---|
| 2 | −66 | `SetFont` | rp = window RastPort; font = topaz.font 8 |
| 3 | −60 | `Text` | rp; topaz 8; cp_y = 49; DrawMode JAM2, FgPen 0, BgPen 1 |
| 4 | −66 | `SetFont` | topaz 8 |
| 5 | −60 | `Text` | cp_y = 59 |
| (…) | | | Additional ruler-mark Text calls at cp_y = 49, 59; repeating with 10-px spacing |

[O] All ruler text uses topaz.font 8 with JAM2, FgPen 0 (black), BgPen 1 (white), rp_Mask `$FF`.

### 4.3 Content redraw — document body (per-line pattern)

For each visible paragraph line, KindWords issues a **triple of Text calls at the same `cp_y`**
(some lines may have additional font switches when both Symboles.font and Romain 14.font are needed):

| Sub-step | LVO | Font | cp_y | Notes |
|---|--:|---|---|---|
| A | −66 | `SetFont` → topaz.font 8 | | |
| B | −60 | `Text`, topaz 8 | cp_y | JAM2; covers rows cp_y−6 .. cp_y+1 (8 rows) |
| C | −66 | `SetFont` → Symboles.font 10 (or Romain 14.font 10) | | |
| D | −60 | `Text`, disk font 10 | cp_y | JAM2; covers rows cp_y−7 .. cp_y+2 (10 rows) |
| (opt) | −66 | `SetFont` → Romain 14.font 10 | | On mixed-font lines only |
| (opt) | −60 | `Text`, Romain 14.font 10 | cp_y | JAM2; same 10-row rectangle |
| E | −66 | `SetFont` → topaz.font 8 | | |
| F | −60 | `Text`, topaz 8 | cp_y | JAM2; covers rows cp_y−6 .. cp_y+1 (8 rows) |

[O] For the first content line `cp_y = 69`; second `cp_y = 79`; third `cp_y = 89`; and so on,
stepping by **10 pixels per line**.

Each `Text` call enters through the graphics.library LVO vector (not patched by SetPatch in this
boot sequence), which calls `BltTemplate` (LVO −36) internally — one `BltTemplate` call per `Text`
call, fired through the LVO. [O]

### 4.4 Content redraw — image blits

The embedded Deluxe Paint picture in the document body is copied into the visible area by KindWords
using `BltBitMap` or equivalent calls (not broken on during this probe; visible in screenshots as a
multi-colour bitmap rendered correctly). Those calls do not involve `ScrollRaster` or `ClipBlit`. [S
from screenshots; not directly monitored]

### 4.5 BeginUpdate / EndUpdate cycle

After the content draw completes, the SIMPLE_REFRESH layer has a residual `DamageList` covering a
small area (~12 rows in layer coordinates). KindWords processes this:

| Step | LVO | Function | Arguments |
|---|--:|---|---|
| M | −78 (layers) | `BeginUpdate` | layer = document layer (SIMPLE_REFRESH, full-window bounds) |
| M+1 | −60 | `Text` | text calls for the ~12-row damaged area, same font pattern |
| M+2 | −84 (layers) | `EndUpdate` | layer; D0 = 1 (TRUE — empty the DamageList) |

[O] The `DamageList` at `BeginUpdate` entry covered approximately layer coordinates y = 41..52
(12 rows, full width of the content area). `EndUpdate` was called with flag = TRUE.

### 4.6 RastPort state at every Text call

| Field | Value |
|---|---|
| `rp_Layer` | points to the document layer (SIMPLE_REFRESH) |
| `rp_Mask` | `0xFF` |
| `rp_FgPen` | 0 (black) |
| `rp_BgPen` | 1 (white/grey on Workbench palette) |
| `rp_DrawMode` | **1 = `JAM2`** — read directly from `RastPort+$1C`; every Text call sampled |
| Font during disk-font Text calls | Symboles.font 10 or Romain 14.font 10 (`tf_YSize = 10`, `tf_Baseline = 7`) |
| Font during topaz 8 Text calls | topaz.font 8 (`tf_YSize = 8`, `tf_Baseline = 6`) |

[O all] No `SetAPen`, `SetBPen`, or `SetDrMd` call was observed between the font setup and the
`Text` calls, which means FgPen, BgPen and DrawMode do not change between `SetFont` and `Text`
within a single line's triple. [O]

---

## 5. Why the inter-line gap rows are clean on KS 1.3 [O+S]

### 5.1 Disk font geometry

Both `Symboles.font` and `Romain 14.font` have `tf_YSize = 10` and `tf_Baseline = 7`. A `Text` call
at `cp_y` using JAM2 covers:
- Top screen row: `cp_y − 7`
- Bottom screen row: `cp_y − 7 + 10 − 1 = cp_y + 2`
- Height: **10 rows**

With consecutive lines spaced 10 pixels apart (`cp_y` = 69, 79, 89, …):
- Line at 69: rows **62–71**
- Line at 79: rows **72–81** (immediately follows: 71 + 1 = 72)
- **Zero-row inter-line gap** between consecutive disk-font lines [O line spacing, S deduction]

### 5.2 JAM2 semantics

Each `Text` call with `DrawMode = JAM2` has `BltTemplate` write `BgPen` (colour 1 = white) for
every non-glyph pixel in the full 10-row advance-extent rectangle (`graphics-text-v34.md` §7.5).
Since consecutive disk-font lines are adjacent, **every row** in the document body is explicitly
painted white (BgPen) or black (glyph FgPen) during the content redraw. No row is left with its
prior content. [O+S]

---

## 6. Bitplane verification after the second page-down [O]

After the second clean page-down (no breakpoint interference), the bitplane content of the rows
immediately below a Symboles.font text line was read. Those rows showed the pen-1 pattern
(Plane 0 ≈ `$FF` per byte, Plane 1 ≈ `$00` per byte — white) throughout the document content area.
This is consistent with JAM2 Text having overwritten those rows as part of the previous or current
line's 10-row rectangle. The initial state (before any scroll) of the same rows also showed pen-1
(blank white document page), confirming that residual picture data was never present in those rows
on the real ROM. [O, kwana1]

---

## 7. Summary call table (first page-down) [O+S]

| # | Library | LVO | Function | Key args / notes |
|---|---|--:|---|---|
| 1 | graphics | −306 | `RectFill` | scroll-bar thumb strip, x ≈ 626–635; JAM2 |
| 2 | graphics | −66 | `SetFont` | topaz.font 8 |
| 3 | graphics | −60 | `Text` | ruler marks; topaz 8; JAM2; FgPen 0 BgPen 1 |
| 4 | graphics | −66 | `SetFont` | topaz.font 8 (repeated for each ruler mark) |
| 5 | graphics | −60 | `Text` | ruler mark; topaz 8; JAM2 |
| 6 | graphics | −66 | `SetFont` | topaz.font 8 — first content line, element A |
| 7 | graphics | −60 | `Text` | cp_y=69; topaz 8; JAM2; covers rows 63–70 (8 rows) |
| 8 | graphics | −66 | `SetFont` | Symboles.font 10 — element C |
| 9 | graphics | −60 | `Text` | cp_y=69; Symboles.font; JAM2; covers rows 62–71 (10 rows) [S from tf_YSize=10, Baseline=7] |
| 10 | graphics | −66 | `SetFont` | topaz.font 8 — element E |
| 11 | graphics | −60 | `Text` | cp_y=69; topaz 8; JAM2; covers rows 63–70 (8 rows) |
| (repeat 6–11) | | | | cp_y = 79, 89, … +10 per line; some lines also include Romain 14.font Text calls |
| M | layers | −78 | `BeginUpdate` | document layer; DamageList ≈ 12 rows |
| M+1 | graphics | −60 | `Text` | content for the ~12-row damaged area |
| M+2 | layers | −84 | `EndUpdate` | layer; D0 = 1 (TRUE) |

BltTemplate (LVO −36) fires once per Text call, internally. [O] The `BltTemplate` calls are
not shown in the table above as they are internal to `Text` and driven through its LVO.

---

## 8. Relationship to existing specs

- `graphics-text-v34.md` §2 (topaz 9 and topaz 8 on TextFonts after boot, topaz 9 first): **confirmed
  by this probe** [O]. The boot state observed here (topaz 9 Accessors=3, topaz 8 Accessors=6, with
  DefaultFont = topaz 8 set by KindWords disk 1's system-configuration) is fully consistent.
- `graphics-text-v34.md` §7.5 (JAM2 rectangle = advance extent × tf_YSize): confirmed [O]. No
  contradiction found.
- `layers-v34.md` §2.1 (SIMPLE_REFRESH, DamageList, BeginUpdate/EndUpdate): confirmed [O].

---

## 9. Clean-room review

- [x] Behaviour and ABI only: LVO numbers (from public `.fd`/AROS conf), public structure field
  offsets (from RKRM/NDK headers), observed argument values and structure contents. No ROM address,
  no instruction listing, no routine transcription.
- [x] The font `tf_YSize`, `tf_Baseline`, `tf_XSize`, `tf_Flags`, `tf_Accessors` values are public
  fields of the `TextFont` structure read at the entry points of SetFont, Text, and AddFont; no
  glyph bitmap or CharLoc table was read.
- [x] The deductions in §5 about adjacent lines and zero gap rows follow from the publicly documented
  formula `top_row = cp_y − tf_Baseline`, `height = tf_YSize` (confirmed in `graphics-text-v34.md`
  §7.2).
- [x] Font names (`Symboles.font`, `Romain 14.font`) were read from `ln_Name` pointers of the font
  nodes in GfxBase's TextFonts list (slow RAM addresses, not ROM). The name strings are in that RAM
  node, not ROM constants.
- [x] Session `kwana3` on vAmiga core 4.3.6. Screenshots in
  `build/vamigaweb/analysis/kwana3/`.
