# graphics-text-v34.md — Text and fonts (graphics.library 34.1)

> ANALYSIS track ("dirty"). Sources: calls made on the real ROM `assets/kick34005.A500` running in Amiberry (A500,
> cycle-exact, `--analysis` sessions `gtext1` with the Workbench 1.3.3 disk and `gtext2` without a disk), driven
> from the debugger: registers and memory set up, the public LVO called from a stopped user task (input.device),
> results read back, on 2026-11-04; reading of the ROM routines behind the LVOs below (behaviour only); the 1.3
> `.fd` (checked against AROS `rom/graphics/graphics.conf`), `graphics/text.h`, `rastport.h` and the AutoDocs.
>
> **Legend**: **[O call]** observed by calling the function on the real ROM · **[O read]** observed by reading
> live structures on a running real ROM · **[O ROM]** read in the ROM code, not confirmed by a call ·
> **[AutoDoc]** public documentation · **[D]** deduced · **[?]** uncertain.
> No ROM address, no instruction listing, no transcription of a routine, no glyph image.

Related pages: FastFonts (Text replacement, BltTemplate contract) `fastfonts-ff.md`; BltTemplate engine, clipping
by layer and the chip-memory fallback `graphics-blitter-v34.md` §6–§7; RectFill and area patterns
`graphics-area-v34.md`; SetPatch fixes of SetFont/SetSoftStyle `setpatch-138.md` §1.9; screen fonts
`intuition-screens-v34.md` §2.5; default font from Preferences `intuition-prefs-v34.md` §3.3; console text output
`console-keymap-v34.md` §3.7–§3.8; Preferences' use of OpenFont `preferences-13.md`.

## 0. Summary

| LVO | Function | Registers (`.fd`) | One-line V34 behaviour |
|---|---|---|---|
| −42 | `ClearEOL(rp)` | A1 | RectFill from cp_x to the BitMap's right edge over the text line, in BgPen if DrawMode is exactly JAM2, else pen 0, honouring AreaPtrn/Mask/DrawMode |
| −48 | `ClearScreen(rp)` | A1 | ClearEOL, then RectFill of the full BitMap width from the line below down to the BitMap's last row |
| −54 | `TextLength(rp, string, count)` | A1, A0, D0 | Sum of kern + advance (CharSpace or XSize) per character, plus count × TxSpacing; styles ignored |
| −60 | `Text(rp, string, count)` | A1, A0, D0 | Builds the line in a 1-plane chip buffer with the CPU, applies bold/italic/underline, draws it with one BltTemplate; cp_x advances |
| −66 | `SetFont(rp, font)` | A1, A0 | Font, TxHeight, TxWidth, TxBaseline from the TextFont; AlgoStyle := 0; no NULL test |
| −72 | `OpenFont(textAttr)` | A0 | Best-score match among fonts of the exact same name in GfxBase's list; accessors + 1 |
| −78 | `CloseFont(font)` | A1 | Accessors − 1; replies the font as a message when it reaches ≤ 0 and the font was removed |
| −84 | `AskSoftStyle(rp)` | A1 | NOT of the font's tf_Style, underline excluded when the font cannot hold it |
| −90 | `SetSoftStyle(rp, style, enable)` | A1, D0, D1 | AlgoStyle updated under enable ∩ possible; return value wrong in the ROM (reads through the caller's A2) |
| −474 | `AskFont(rp, textAttr)` | A1, A0 | Copies the font's name pointer, YSize, Style, Flags into the TextAttr |
| −480 | `AddFont(font)` | A1 | Accessors := 0, type NT_FONT, Enqueue into GfxBase's font list under Forbid |
| −486 | `RemFont(font)` | A1 | Remove under Forbid, type NT_MESSAGE, FPF_REMOVED set; replied at once if accessors ≤ 0 |

LVOs checked: bias 30, slot order of AROS `graphics.conf` (ClearEOL is the 3rd vector, AskFont the 75th).

## 1. Structures and GfxBase fields

Public offsets used throughout (`graphics/text.h`, `rastport.h`, `gfx.h`):

- **TextFont** (52 bytes): `tf_Message` (Node: ln_Type +$08, ln_Pri +$09, ln_Name +$0A; mn_ReplyPort +$0E,
  mn_Length +$12), `tf_YSize` +$14 (W), `tf_Style` +$16 (B), `tf_Flags` +$17 (B), `tf_XSize` +$18 (W),
  `tf_Baseline` +$1A (W), `tf_BoldSmear` +$1C (W), `tf_Accessors` +$1E (W), `tf_LoChar` +$20 (B), `tf_HiChar`
  +$21 (B), `tf_CharData` +$22 (L), `tf_Modulo` +$26 (W, bytes per strike row), `tf_CharLoc` +$28 (L),
  `tf_CharSpace` +$2C (L), `tf_CharKern` +$30 (L).
- **TextAttr** (8 bytes): `ta_Name` +0, `ta_YSize` +4 (W), `ta_Style` +6, `ta_Flags` +7. V34 has no TTextAttr.
- **RastPort**: `Layer` +$00, `BitMap` +$04, `AreaPtrn` +$08, `TmpRas` +$0C, `Mask` +$18, `FgPen` +$19,
  `BgPen` +$1A, `DrawMode` +$1C, `AreaPtSz` +$1D, `cp_x` +$24, `cp_y` +$26, `minterms` +$28, `Font` +$34,
  `AlgoStyle` +$38, `TxFlags` +$39, `TxHeight` +$3A, `TxWidth` +$3C, `TxBaseline` +$3E, `TxSpacing` +$40 (signed W).
- **GfxBase**: `TextFonts` list header at +$8C, `DefaultFont` at +$9A [O read].
- Style bits: FSF_UNDERLINED 1, FSF_BOLD 2, FSF_ITALIC 4, FSF_EXTENDED 8. Flag bits: FPF_ROMFONT 1, FPF_DISKFONT 2,
  FPF_REVPATH 4, FPF_TALLDOT 8, FPF_WIDEDOT $10, FPF_PROPORTIONAL $20, FPF_DESIGNED $40, FPF_REMOVED $80.

## 2. The fonts built into the 1.3 ROM [O read]

Exactly **two** fonts are on GfxBase's list after boot, both named `topaz.font`, both at priority 0, type NT_FONT,
list order **topaz 9 first, then topaz 8**. Their TextFont structures live in **RAM** (so they can be modified,
which FastFonts relies on, `fastfonts-ff.md`); only the strike data, CharLoc tables and the name string are in ROM.

| Field | topaz 8 | topaz 9 |
|---|---|---|
| tf_YSize / tf_XSize / tf_Baseline | 8 / 8 / 6 | 9 / **10** / 6 |
| tf_Style | 0 | FSF_EXTENDED |
| tf_Flags | ROMFONT \| DESIGNED (`$41`) | ROMFONT \| TALLDOT \| DESIGNED (`$49`) |
| tf_BoldSmear | 1 | 1 |
| tf_LoChar .. tf_HiChar | `$20` .. `$FF` | `$20` .. `$FF` |
| CharLoc entries | 225 (224 codes + 1 default glyph) | 225 |
| Glyph width in every CharLoc entry | 8 | 10 |
| tf_Modulo (strike width) | 192 bytes (192 glyph slots of 8 px) | 240 bytes (192 slots of 10 px) |
| tf_CharSpace / tf_CharKern | NULL / NULL (fixed width) | NULL / NULL (fixed width) |

Content described in words (no image reproduced):
- Codes `$80`–`$9F` and the **default glyph** (entry 224, used for codes below `$20`) all point to the **same strike
  slot**: a hollow rectangle placeholder. Codes `$20` (space) and `$A0` (no-break space) share one blank slot. In
  topaz 9, `-` and the soft hyphen `$AD` also share a slot. All other codes have their own glyph; `$7F` has a
  visible glyph (a checkered pattern), not the placeholder.
- No other size and no other font is in the ROM: `topaz 11` (and every disk font) comes from `diskfont.library`.

Boot state [O read]:
- Without a disk (insert-disk screen, so without `devs:system-configuration`): `GfxBase.DefaultFont` = **topaz 9**;
  accessors topaz 8 = 1, topaz 9 = 2. This confirms the 1.3 behaviour of `intuition-prefs-v34.md` §3.3 (FontHeight
  9 by default) and `intuition-screens-v34.md` §2.5 (Workbench screen in topaz 9, bar height 11).
- After the Workbench 1.3.3 boot (its `system-configuration` asks for 8): DefaultFont = topaz 8.
- InitRastPort gives the RastPort `GfxBase.DefaultFont` (observed: a fresh RastPort at the insert-disk screen has
  TxHeight 9, TxWidth 10, TxBaseline 6) [O call].

**Consequence for our ROM**: a real 1.3 `OpenFont({"topaz.font", 9})` returns a genuine 9-line, 10-pixel-wide font;
a ROM that has only topaz 8 returns topaz 8 (§3 scoring) and every topaz-9 user (Workbench without
system-configuration, Preferences 60-column mode, programs asking topaz 9) gets 8-pixel text in 9/10-pixel cells.

## 3. OpenFont (−72) [O call + O ROM]

`font = OpenFont(textAttr A0)` → D0 (A0, A1, D1 trashed). No NULL test of the TextAttr.

1. Candidates are the nodes of `GfxBase.TextFonts` whose name **equals** `ta_Name` by exec `FindName` semantics:
   exact, **case-sensitive**, whole string including `.font`. `"Topaz.font"`, `"TOPAZ.FONT"` and `"topaz"` all
   return NULL [O call]. No diskfont fallback, no default-font fallback.
2. A candidate whose `tf_YSize` is 0 is skipped [O call].
3. Score of a candidate, starting at 32767 (`$7FFF`):
   - size: font **larger** than requested by n lines → −256·n; font **smaller** by n lines → −64·n (smaller fonts
     are preferred);
   - style/flags: the 16-bit word (tf_Style:tf_Flags) is compared with (ta_Style:ta_Flags); for every differing
     bit, subtract the weight of the case "requested but missing in the font" / "present in the font but not
     requested":

     | Bit | requested, font lacks it | font has it, not requested |
     |---|--:|--:|
     | FPF_ROMFONT | 1 | 1 |
     | FPF_DISKFONT | 1 | 1 |
     | FPF_REVPATH | 32768 | 32768 |
     | FPF_TALLDOT | 32 | 32 |
     | FPF_WIDEDOT | 32 | 32 |
     | FPF_PROPORTIONAL | 32 | 128 |
     | FPF_DESIGNED | 2 | 2 |
     | FPF_REMOVED | 0 | 0 |
     | FSF_UNDERLINED | 4 | 128 |
     | FSF_BOLD | 8 | 128 |
     | FSF_ITALIC | 16 | 128 |
     | FSF_EXTENDED and style bits 4–7 | 0 | 0 |

     A REVPATH mismatch alone drives an exact-size candidate to −1: such a font is never chosen.
4. The candidate with the **strictly** highest score wins; on a tie the **first in list order** wins (list order
   is the Enqueue order of AddFont, §4). If the best score is ≤ 0 → NULL. So a same-name font is always returned
   unless it is ≥ 128 lines too large or ≥ 512 lines too small (`topaz 600` → NULL, `topaz 200` → topaz 9).
5. The winner's `tf_Accessors` is incremented (no other field touched) and it is returned.

Observed with the ROM fonts [O call]: size 8, 7, 1, 0 → topaz 8; size 9, 10, 11, 200 → topaz 9; 600 → NULL.
Style/flags requests (EXTENDED, PROPORTIONAL, TALLDOT, ROMFONT|DESIGNED|TALLDOT) do not change the result with
only one font per size. All the weights of the table were checked by two-font contests (test vectors §10.4).

## 4. CloseFont, AddFont, RemFont, AskFont, SetFont

- **CloseFont(font A1)** [O call]: `tf_Accessors` − 1 (signed word; it may go negative: three CloseFont on a font
  opened once gave 0, −1, −2). If the result is ≤ 0 **and** FPF_REMOVED is set, exec `ReplyMsg(font)` is called
  (the TextFont is a Message: with mn_ReplyPort NULL the node type becomes NT_FREEMSG, 6). No NULL test. Nothing
  else (no list change).
- **AddFont(font A1)** [O call]: `tf_Accessors` := **0** (whatever it was), ln_Type := NT_FONT (12), then under
  Forbid/Permit exec `Enqueue(&GfxBase.TextFonts, font)`: priority order, after the existing nodes of the same
  priority. FPF_REMOVED is not cleared. No name or duplicate check: two fonts with the same name and size can
  coexist (OpenFont then follows §3).
- **RemFont(font A1)** [O call]: under Forbid/Permit the node is unlinked; then ln_Type := NT_MESSAGE (5),
  FPF_REMOVED set; if `tf_Accessors` ≤ 0 the font is replied at once (ReplyMsg), otherwise the last CloseFont
  replies it. The disk-font owner (diskfont) gets its memory back through that reply.
- **AskFont(rp A1, textAttr A0)** [O call]: from `rp->Font`: ta_Name := ln_Name **pointer** (not a copy),
  ta_YSize := tf_YSize, ta_Style := **tf_Style** (not AlgoStyle), ta_Flags := tf_Flags. Topaz 9 gives
  (`topaz.font`, 9, `$08`, `$49`).
- **SetFont(rp A1, font A0)** [O call]: rp_Font := font; TxHeight := tf_YSize; TxWidth := tf_XSize; TxBaseline :=
  tf_Baseline; **AlgoStyle := 0**. TxSpacing, TxFlags, pens, cp are not touched (TxSpacing 3 survived). Accessors
  not touched. **No NULL test** of either argument (SetPatch 1.38 adds it, `setpatch-138.md` §1.9). D0 is not
  touched (`preferences-13.md` relies on it).

## 5. AskSoftStyle (−84) and SetSoftStyle (−90)

- **AskSoftStyle(rp A1)** → D0 [O call + O ROM]: the bits that may be generated algorithmically, as a full 32-bit
  value: `NOT tf_Style` of rp_Font (all upper bits set). If the font is not itself underlined, underline is also
  excluded when the font has no room below the baseline: the intended test is "Baseline + 2 > YSize", but the ROM
  reads the **high byte** of tf_Baseline and keeps bits 8–15 of the caller's **D1**, so in practice the test is
  "(D1 & `$FF00`) + 2 > YSize" (signed word compare). Observed: topaz 8 → `$FFFFFFFF`; topaz 9 → `$FFFFFFF7`;
  topaz 8 with D1 = `$0100` on entry → `$FFFFFFFE`; D1 = `$FFFF` → `$FFFFFFFF`. [O call]
  Implementation advice: return `NOT tf_Style`, minus FSF_UNDERLINED when Baseline + 2 > YSize; callers pass
  small D1 values (SetSoftStyle passes its enable mask) and see the same result.
- **SetSoftStyle(rp A1, style D0, enable D1)** → D0 [O call]: calls AskSoftStyle through the **library vector**
  (A6 must be GfxBase); `possible` = its low byte; `e = enable ∩ possible` (low byte only);
  `AlgoStyle := (AlgoStyle AND NOT e) OR (style AND e)` (bytes). Any bit 0–7 the font does not have can be set,
  including bits 4–7 (topaz 9 with style/enable `$FF` → AlgoStyle `$F7`). **Return value (ROM bug)**: new
  AlgoStyle OR the byte at **(caller's A2) + $16** instead of `rp->Font->tf_Style`, zero-extended. Observed with
  A2 pointing at a byte `$40` at +$16: SetSoftStyle(BOLD, `$FF`) → `$42`. SetPatch 1.38 replaces the function with
  the intended `AlgoStyle | tf_Style` (`setpatch-138.md` §1.9). D0, D1, A0, A1 trashed; D2 preserved.
- Text only interprets AlgoStyle bits 0–2 (§7.6); EXTENDED and bits 4–7 have no rendering effect. tf_Style is
  never used by Text (the font's own style is in its glyphs).

## 6. TextLength (−54) [O call]

`width = TextLength(rp A1, string A0, count D0)` → D0.

- count = low 16 bits of D0, **unsigned** (D0 = `$10002` → 2 characters); 0 → returns 0.
- Character index: `c − LoChar` if LoChar ≤ c ≤ HiChar, else the default entry `HiChar − LoChar + 1` (also used for
  CharSpace/CharKern).
- Sum over the characters of `kern[i]` (if tf_CharKern ≠ NULL) + (`space[i]` if tf_CharSpace ≠ NULL, else
  tf_XSize), plus `count × rp_TxSpacing` (signed). Uses the **font's** tf_XSize, not rp_TxWidth.
- **Styles are ignored**: bold, italic, underline do not change the result (`"ABCD"` with all three = without).
- Result: 16-bit sum, **zero-extended** in D0 (2 chars of 8 px with TxSpacing −16 → `$0000FFF0`).
- Registers: D0 result, D1 and A0 (advanced) trashed, A1 kept, D2–D7/A2–A6 preserved.

## 7. Text (−60)

### 7.1 Contract [O call + O ROM]
- `Text(rp A1, string A0, count D0)`; **A6 must be GfxBase** (internal calls go through GfxBase's vectors:
  LockLayerRom/UnlockLayerRom, BltClear, BltTemplate). D0, D1, A0, A1 trashed; D2–D7/A2–A6 preserved [O call].
- If `rp_Layer` ≠ NULL: `LockLayerRom(layer)` on entry and `UnlockLayerRom` on exit, even when count is 0 [O ROM].
- count = low 16 bits, **unsigned**; 0 → nothing drawn, cp unchanged [O call].

### 7.2 Where the text goes [O call]
- Top row of the text = **cp_y − tf_Baseline** of the **font** (rp_TxBaseline is ignored: setting it to 2 did not
  move the text). Height = **tf_YSize** rows of the font. topaz 8 at cp_y 8 touches rows 2–9; topaz 9 rows 2–10.
- Character origin of the first glyph = cp_x (plus its kern). Each glyph is drawn at its pen position + kern;
  the pen position then advances by `space[i]` (or tf_XSize) + **rp_TxSpacing**, i.e. kern, glyph, advance.
- **cp_x after = cp_x + the sum of all (kern + advance + TxSpacing)** of the characters actually drawn (the
  TextLength value when nothing is truncated). cp_y unchanged. Styles never change the advance.
- Overlapping glyphs (negative kern, negative TxSpacing) are **ORed** together before drawing.
- Out-of-range characters (below LoChar or above HiChar) use the default entry `HiChar − LoChar + 1` for CharLoc,
  CharSpace and CharKern. Glyph width 0 in CharLoc → nothing drawn, advance still applied.

### 7.3 The line buffer and the width limit [O ROM + O call]
- Text renders the whole call into **one single-plane buffer** of `rp_TxHeight + 1` rows; row stride =
  destination BytesPerRow (rp_BitMap, or the layer's SuperBitMap when `rp_Layer->SuperBitMap` ≠ NULL) + **slack**,
  slack = 4 + 2·⌊(⌊(TxHeight+1)/2⌋ + BoldSmear) / 32⌋ bytes (4 bytes for every font below ~60 lines). The glyphs
  occupy rows 1..YSize of it.
- The buffer is the RastPort's **TmpRas** if `rp_TmpRas` ≠ NULL, its RasPtr ≠ NULL and its Size ≥ the buffer size
  (observed: a 200-byte TmpRas was used for a 108-byte buffer and left modified; a 50-byte one was not used);
  otherwise it is allocated with `AllocMem(size, MEMF_CHIP)` and freed on exit, through the graphics allocator with
  the last-chance memory fallback (`graphics-blitter-v34.md` §7).
- It is cleared with **BltClear (blitter, waiting)**, then the glyphs are ORed in by the **CPU** from tf_CharData
  (tf_Modulo stride, CharLoc bit offset and width; glyphs up to and beyond 16 px wide are handled).
- **Truncation**: the extent `[minX, maxX)` of the line (pen positions and kerned origins, relative to cp_x) is
  tracked; before a character is accepted, if `(maxX − minX) / 8 ≥ buffer stride` the character and **all the
  following ones are dropped** (not drawn, not counted in cp_x). Observed: an 8-pixel font on a 4-byte-wide
  BitMap (stride 8 bytes = 64 px) draws 7 characters of 10 and advances cp_x by 56; count `$FFFF` behaves the same.
  On a 640-px screen (80 + 4 bytes) at most 83 characters of 8 px are drawn by one call [D].

### 7.4 Algorithmic styles (AlgoStyle bits 0–2), in this order [O call]
1. **Bold** (FSF_BOLD): the whole composed buffer is ORed with **one copy of itself shifted right by
   tf_BoldSmear pixels**. Smear 1 widens strokes by one pixel; smear 2 gives the stroke and a second stroke two
   pixels to the right (a one-pixel gap stays); smear 0 has **no effect**. The drawn extent grows by BoldSmear on
   the right; cp_x does not.
2. **Italic** (FSF_ITALIC): each font row is shifted horizontally relative to the baseline row: a row **d rows
   above** the baseline (d = Baseline − row ≥ 0) moves **right by ⌊d/2⌋**; a row **k rows below** the baseline moves
   **left by ⌊(k+1)/2⌋**. topaz 8: rows 0..7 shift +3, +2, +2, +1, +1, 0, 0, −1. The slant leans right (`/`). The
   extent grows by the largest right shift on the right and by the largest left shift on the left (the drawn
   rectangle starts left of cp_x). Pixels that the left shift pushes left of the first buffer word are **lost**:
   the leftmost pixel column of the first character, in rows below the baseline, disappears (observed: an italic
   `_` as first character draws 6 of its 7 pixels; the same `_` as second character draws 7).
3. **Underline** (FSF_UNDERLINED): only if `tf_Baseline + 2 ≤ tf_YSize`, on font row **Baseline + 1** (topaz 8 and
   9: the row just below the baseline, rows 7). Over the whole drawn extent (including the bold and italic
   extensions), every pixel that is clear **and whose left and right neighbours are clear** is set; existing pixels
   stay. The underline therefore skips descenders with a one-pixel gap on each side. The pixel left of the extent
   counts as clear.

Combined styles apply in that order (bold, then italic, then underline on the result).

### 7.5 Drawing [O call]
- **One BltTemplate call** (through its LVO) with: template = buffer row 1 at the word of minX, xSrc = minX & 15,
  srcMod = buffer stride, destination x = **cp_x + minX**, y = **cp_y − tf_Baseline**, width = **maxX − minX**,
  height = **tf_YSize**. Everything about pens, modes, mask and clipping is BltTemplate's
  (`graphics-blitter-v34.md` §6). Observed effects:
  - **JAM1**: glyph pixels in FgPen, others untouched.
  - **JAM2**: glyph pixels FgPen, the rest of the rectangle (full extent × YSize, including inter-character
    spacing, bold/italic extensions and the underline row) in BgPen.
  - **COMPLEMENT**: glyph pixels inverted in every plane enabled by Mask; pens ignored.
  - **JAM1 | INVERSVID**: the non-glyph pixels of the rectangle in FgPen; glyph pixels untouched.
  - **JAM2 | INVERSVID**: glyph pixels BgPen, the rest FgPen.
  - **Mask**: planes whose Mask bit is 0 are not written.
- The rectangle is the **advance extent**, not the glyph ink: a glyph whose image extends beyond its advance is
  cut at maxX (proportional fonts) [D].
- No wait for the end of the blit before returning (BltTemplate does not wait) [O ROM, ?]: the buffer is freed
  right after the BltTemplate call.

### 7.6 Clipping [O call]
- **With a layer**: BltTemplate clips by the layer's ClipRects: text past the right or bottom edge, at negative
  layer x, or with its top above the layer is cut cleanly; italic text at cp_x 0 is drawn (its first pixel column
  clipped) — checked on the Workbench backdrop window (screenshot).
- **Without a layer**: **no clipping at all**. Text past the right edge continues on the next row (memory
  continuity); rows above row 0 are written before the plane; rows below bm_Rows are written after it
  (FastFonts relies on this, `fastfonts-ff.md` §3). A **negative destination x** (cp_x + minX < 0, which includes
  italic at cp_x 0) draws **nothing in the BitMap but corrupts a few bytes of unrelated memory** below the plane
  (observed twice, 1–2 KB below; one run overwrote a font name). Do not reproduce; a clean implementation may draw
  nothing or clip.

## 8. ClearEOL (−42) and ClearScreen (−48) [O call + O ROM]

- **ClearEOL(rp A1)**: one `RectFill` over x = **cp_x** .. **BytesPerRow(rp_BitMap) × 8 − 1**, y = **cp_y −
  rp_TxBaseline** .. that + **tf_YSize − 1** (top from the **RastPort's** TxBaseline, height from the **font**: with
  TxBaseline 2 and TxHeight 3 on topaz 8 at cp_y 8 the cleared rows are 6–13).
  - Pen: FgPen is saved, `SetAPen(BgPen)` if DrawMode is **exactly JAM2** (1), else `SetAPen(0)`; RectFill; then
    `SetAPen(saved FgPen)` (so minterms are recomputed). DrawMode, BgPen, Mask, **AreaPtrn and AreaPtSz are
    used as they are** (an area pattern in the RastPort patterns the clear; AreaPtrn is saved and restored around
    the call but never cleared).
  - Results on a colour-3 background (2 planes, FgPen 1, BgPen 2, AreaPtrn NULL): JAM2 → colour 2; JAM1 → colour 0;
    COMPLEMENT → inverted (colour 0); JAM2|INVERSVID → **colour 2** (RectFill in inverse video paints BgPen);
    JAM1|INVERSVID → **unchanged**.
  - cp unchanged. No clipping without a layer (rows past bm_Rows go into the next plane); with a layer the
    rectangle is in layer coordinates, RectFill clips it to the layer [D].
- **ClearScreen(rp A1)**: ClearEOL first; then, if `cp_y − TxBaseline + tf_YSize ≤ bm_Rows − 1`, one RectFill
  over x = 0 .. BytesPerRow × 8 − 1, y = cp_y − TxBaseline + tf_YSize .. **bm_Rows − 1** with the same pen choice
  and the same restoration. Columns left of cp_x on the cursor line are kept. Both use the BitMap's dimensions, not
  the layer's.
- Registers: D0, D1, A0, A1 trashed; D2–D7/A2–A6 preserved [O call].

## 9. Requirements for our ROM

- A **topaz 9** ROM font (9 lines, 10 px wide, baseline 6, style EXTENDED, flags ROMFONT|TALLDOT|DESIGNED, codes
  `$20`–`$FF` + default) next to topaz 8, both in a list ordered topaz 9 then topaz 8, TextFont structures in RAM.
  Hand-authored glyphs only.
- OpenFont scoring of §3 (smaller preferred, REVPATH disqualifies, first-in-list on ties, ≤ 0 → NULL).
- Text: baseline from tf_Baseline, height tf_YSize, JAM2 rectangle = advance extent, styles as §7.4 (bold smear
  copy, italic ⌊d/2⌋ / ⌊(k+1)/2⌋, gap underline), cp_x not including styles, TmpRas reuse, truncation at the
  buffer width (programs rarely hit it; drawing more is harmless but cp_x must then match).
- SetFont resets AlgoStyle; AskSoftStyle returns NOT tf_Style; SetSoftStyle masks with it. Returning the intended
  `AlgoStyle | tf_Style` from SetSoftStyle is the SetPatch behaviour and is safe.
- ClearEOL/ClearScreen honour the area pattern and use BgPen only in exact JAM2.

## 10. Test vectors

All Text vectors below use a **synthetic font** (not a ROM font), so they contain no ROM data. Hex rows are bytes
of the plane, left to right, from x = 0.

### 10.1 Synthetic font "probe.font"
TextFont in RAM, name `probe.font`, YSize 8, XSize 8, Baseline 6, BoldSmear 1, Style 0, Flags DISKFONT (`$02`),
LoChar `'A'`, HiChar `'D'`, Modulo 2, CharSpace/CharKern NULL unless stated. Strike: 8 rows of 2 bytes, row r =
`$F4`, (`$80` >> r). CharLoc (offset in bits, width): A = (0,4) a 4×8 block; B = (4,3) a vertical line in its
column 1; C = (8,8) a diagonal (row r has only column r); D = (0,0) empty; default = (0,2) a 2×8 block.
AddFont, then OpenFont(`probe.font`, 8) returns it (accessors 1).

### 10.2 Text on a 1-plane BitMap 8 bytes × 16 rows, no layer, InitRastPort + SetFont (JAM2, FgPen −1, BgPen 0)

| # | Setup | Call | cp_x after | Rows 1–10, first 6 bytes |
|---|---|---|---|---|
| V1 | — | `"ABCD"` at (8,8) | 40 | y1 `000000000000`; y2..y9 = `00F040` + C byte + `0000` with C byte `80,40,20,10,08,04,02,01`; y10 zero |
| V2 | — | `'Z',$10,'@'` at (8,8) | 32 | y2..y9 `00C0C0C00000` |
| V3 | SetSoftStyle(BOLD,$FF) | `"ABC"` at (8,8) | 32 | y2..y9 `00F860` + C byte `C0,60,30,18,0C,06,03,01` + `80` in byte 4 on y9 only (`00F860018000`) |
| V3b | BoldSmear 2, BOLD | `"C"` at (8,8) | 16 | y2..y9 `00A0..`, `0050..`, `0028..`, `0014..`, `000A..`, `0005..`, `000280`, `000140` |
| V4 | ITALIC | `"CB"` at (16,8) | 32 | y2 `000010080000`, y3 `000010100000`, y4 `000008100000`, y5 `000008200000`, y6 `000004200000`, y7 `000004400000`, y8 `000002400000`, y9 `000002800000` |
| V5 | UNDERLINED | `"ABD"` at (8,8) | 32 | y2..y8 `00F040000000`; y9 `00F75FFF0000` |
| V5b | BOLD+ITALIC+UNDERLINED | `"C"` at (16,8) | 24 | y2,y3 `000018000000`; y4,y5 `00000C000000`; y6,y7 `000006000000`; y8 `000003000000`; y9 `0001FB700000` |
| V7 | TxSpacing 2 | `"AA"` at (8,8) | 28 | y2..y9 `00F03C000000` |
| V8 | BitMap 4 bytes wide | 10 × `'A'` at (8,8) | 64 | y2 `00F0F0F0` (7 characters drawn) |
| V9 | — | count 0 at (8,8) | 8 | all zero |

V2: `'Z'` (above HiChar), `$10` and `'@'` (below LoChar) all draw the default 2-column block.

### 10.3 Modes on a 2-plane BitMap (plane 0 | plane 1), `"AB"` at (8,8), rows y2..y9 (y1, y10 = initial fill)

| # | Initial planes | Pens / mode | Rows y2..y9 | cp_x |
|---|---|---|---|---|
| V6 | `00` / `FF` | Fg 1, Bg 0, JAM1 | `00F040000000` \| `FF0FBFFFFFFF` | 24 |
| V6b | `00` / `00` | Fg 1, Bg 2, JAM2 | `00F040000000` \| `000FBF000000` | 24 |
| V6c | `0F` / `00` | COMPLEMENT | `0FFF4F0F0F0F` \| `00F040000000` | 24 |
| V6d | `00` / `00` | Fg 1, Bg 2, JAM1\|INVERSVID | `000FBF000000` \| `000000000000` | 24 |
| V6e | `00` / `00` | Fg 1, Bg 2, JAM2\|INVERSVID | `000FBF000000` \| `00F040000000` | 24 |
| V6f | `00` / `FF` | Fg 3, Bg 0, JAM2, Mask 1 | `00F040000000` \| `FFFFFFFFFFFF` | 24 |

Proportional (V12): CharSpace = A 5, B 12, C 8, D 3, default 4; CharKern = A −2, B 3, C 0, D 0, default 1;
Fg 1, Bg 2, JAM2, `"AB"` at (16,8) on 2 planes cleared: rows y2..y9 = `0003C1000000` \| `00003EFFC000`, cp_x 34.
TextLength: `"AB"` 18, `"ABCD"` 29, `"Z"` 5. Without the tables: `"ABCD"` 32; TxSpacing 3 → 44; with all three
styles → 44.

### 10.4 OpenFont contests (two fonts named `w.font`, A added before B, priority 0 unless stated)

| A (YSize, Style, Flags) | B | Request | Winner |
|---|---|---|---|
| 8, ITALIC, 0 | 7, 0, 0 | 8, 0, 0 | B |
| 8, UNDERLINED, 0 | 7, 0, 0 | 8, 0, 0 | B |
| 8, 0, 0 | 7, UNDERLINED, 0 | 8, UNDERLINED, 0 | A |
| 9, 0, 0 | 4, 0, 0 | 8, 0, 0 | A (tie, first) |
| 9, 0, 0 | 5, 0, 0 | 8, 0, 0 | B |
| 9, 0, 0 | 3, 0, 0 | 8, 0, 0 | A |
| 8, 0, PROPORTIONAL | 7, 0, 0 | 8, 0, 0 | B |
| 8, 0, 0 | 8, 0, PROPORTIONAL | 8, 0, PROPORTIONAL | B |
| 8, 0, 0 | 7, 0, PROPORTIONAL | 8, 0, PROPORTIONAL | A |
| 8, BOLD, 0 | 7, 0, 0 | 8, 0, 0 | B |
| 8, 0, 0 | 7, BOLD, 0 | 8, BOLD, 0 | A |
| 8, 0, 0 | 7, ITALIC, 0 | 8, ITALIC, 0 | A |
| 8, EXTENDED, 0 | 8, 0, 0 | 8, 0, 0 | A |
| 8, 0, 0 | 8, 0, 0, priority 5 | 8, 0, 0 | B (head of list) |
| 0, 0, 0 | 0, 0, 0 | 8, 0, 0 | NULL |
| 8, 0, DISKFONT | 8, 0, ROMFONT | 8, 0, ROMFONT | B |
| 8, 0, TALLDOT | 7, 0, 0 | 8, 0, 0 | A |
| 8, 0, REVPATH | 8, 0, 0 | 8, 0, 0 | B |
| 8, 0, 0 | 8, 0, REVPATH | 8, 0, 0 | A |
| 8, 0, REMOVED | 8, 0, 0 | 8, 0, 0 | A |
| 8, `$10`, 0 / 8, `$80`, 0 | 8, 0, 0 | 8, 0, 0 | A |

### 10.5 Other vectors [O call]
- AddFont on a TextFont with accessors 5 → 0. RemFont with accessors 1 → type 5, flags gain `$80`, off the list;
  CloseFont → accessors 0, type 6 (replied, no reply port). Further CloseFont → −1, −2, nothing else.
- SetFont on a RastPort with AlgoStyle 7, TxSpacing 3 → AlgoStyle 0, TxSpacing 3.
- AskSoftStyle: probe font → `$FFFFFFFF`; SetSoftStyle(`$F5`, `$0F`) after BOLD → AlgoStyle 5.
- ClearEOL on 2 planes 4 bytes × 12 rows filled `$FF`, topaz-independent (any 8-line font with Baseline 6), cp
  (12,7), Fg 1, Bg 2: JAM2 → rows 1..8, x 12..31 colour 2; JAM1 → colour 0; JAM1 with AreaPtrn {`$AAAA`,`$0000`},
  AreaPtSz 1 → even rows (2,4,6,8) get pattern `$AAAA` cleared in both planes (x ≥ 12), odd rows unchanged;
  COMPLEMENT → colour 0; JAM2|INVERSVID → colour 2; JAM1|INVERSVID → unchanged. FgPen 1 afterwards, AreaPtrn
  restored.
- ClearScreen, 2 planes × 16 rows `$FF`, cp (12,8), JAM2, Bg 2: rows 2..9 from x 12 and rows 10..15 entirely
  colour 2; rows 0–1 and x < 12 of rows 2–9 unchanged. At cp_y 14: only rows 8..15 from x 12.

## 11. Probe to write (implementation side): `tests/gtext_probe.s` + `.sh`

Imitate `tests/garea_probe.s/.sh`: a HUNK executable started from the startup-sequence of a bootable OFS floppy
**without SetPatch and without `devs:system-configuration`**, FS-UAE or Amiberry, results on the serial line
(SERDAT), end marker `GTX fin`. Open graphics.library (any version). One `AllocMem(8192, MEMF_CHIP|MEMF_CLEAR)`
block holding: BitMap struct, RastPort, TextAttr + name, strings, planes (2 × 8 bytes × 16 rows), the synthetic
font (§10.1) with its strike, CharLoc, CharSpace and CharKern tables.

Per Text test: InitBitMap-equivalent fill of the BitMap (BytesPerRow, Rows, Depth, plane pointers), fill the
planes with the initial bytes, `InitRastPort`, `rp_BitMap := &bm` (rp_Layer stays NULL), `SetFont(rp, probefont)`,
optional SetAPen/SetBPen/SetDrMd/SetSoftStyle/field writes, `Move` or direct cp writes, `Text(rp, s, n)`. Print
one header line `Vn cpx=<dec>` then rows 1..10, each as `<plane0 6 bytes hex> | <plane1 6 bytes hex>`. Expected:
§10.2–§10.3. Call SetSoftStyle with A2 pointing to a known block and print its D0 to catch the ROM's return value
(§5); do not compare that value on our ROM unless we decide to keep the bug.

Numeric lines (`name=value`): InitRastPort TxHeight/TxWidth/TxBaseline (real 1.3 without system-configuration:
9/10/6); OpenFont of `topaz.font` sizes 7, 8, 9, 10, 11, 200, 600 and of `Topaz.font` 8 → print the returned
YSize (or 0 for NULL): 8, 8, 9, 9, 9, 9, 0, 0; AskFont of topaz 9 → `9 08 49`; TextLength vectors of §10.3;
AskSoftStyle on topaz 8 and topaz 9 → `FFFFFFFF`, `FFFFFFF7`; the OpenFont contests of §10.4 (build A and B in
the block, AddFont both, OpenFont, print `A`/`B`/`0`, RemFont both); AddFont/RemFont/CloseFont sequence of §10.5
(print accessors, ln_Type, tf_Flags after each step); ClearEOL/ClearScreen vectors of §10.5 on a 4-byte BitMap
(print rows 0..15 of both planes, 4 bytes each).

**Do not run** a Text with a negative destination x or italic at cp_x 0 on a layerless BitMap: on 1.3 it corrupts
memory (§7.6). Keep the rest of the probe independent of any ROM font's glyphs (only line numbers, cp and returned
values are printed for topaz).

## 12. Open points

1. Italic with a font whose Baseline = YSize − 1 (no row below the baseline): the left extent adjustment uses a
   value left over from earlier work [O ROM, ?]; the drawn rectangle may start at an arbitrary offset. Probe with a
   synthetic font of Baseline 7.
2. Text with `rp_TxHeight` smaller than `tf_YSize` (buffer sized from TxHeight, glyphs drawn for YSize rows) —
   probably overruns the buffer [D, ?].
3. A Text whose total extent is 0 (e.g. TxSpacing = −XSize) calls BltTemplate with width 0, which the blitter
   engine treats as a maximal blit (`graphics-blitter-v34.md` §0) [D, not run].
4. Layers with a SuperBitMap: buffer stride from the SuperBitMap [O ROM]; not exercised.
5. Where exactly a negative-x Text without layer writes (§7.6) — not needed for compatibility.
6. Whether 1.3 graphics init sets DefaultFont to topaz 8 before intuition switches it to topaz 9 (would explain
   topaz 8's accessor count of 1 at the insert-disk screen) [?].

## Clean-room review

Review of 2026-11-04.

- [x] Behaviour, ABI (public `.fd` registers and `text.h`/`rastport.h`/`gfx.h` offsets, GfxBase list offsets) and
  observed results only. No instruction sequence, no pseudo-code transcription, no ROM routine or data address.
- [x] The two ROM fonts are described by their public TextFont fields and in words (shared placeholder slot, blank
  slots); no glyph bitmap, strike or CharLoc table is reproduced. All pixel test vectors use a synthetic font
  defined in §10.1, so the hex rows are outputs for authored data, not ROM data. Implementers must not draw topaz
  9 from any description here: there is none.
- [x] The OpenFont weight table (§3) is a matching rule needed for compatibility; every weight that decides a
  choice in practice was checked black-box (§10.4).
- [x] Facts only read in the ROM are marked [O ROM] and listed in §12 where a probe would settle them.
