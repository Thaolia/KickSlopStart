# FastFonts `C:FF` (Workbench 1.3.3): replacement of `Text()`, ABI contracts, cause of the invisible text

**ANALYSIS** track ("dirty"). This document describes **behaviours and ABI contracts only**:
expected registers, fields read/written (public offsets), library calls, conditions. **No
instruction sequence is copied here** and it contains no line-by-line pseudo-code. The Kickstart
ROM (`assets/kick34005.A500`) was **not** opened: the target is a third-party program on
floppy.

## Provenance

- File: `C:FF` from `assets/test_adf/Workbench 1.3.3 (34.34) - Boot (Commodore) (1991) [m2].adf`
  (read only), extracted by `xdftool … read c/FF`. 3320 bytes, md5
  `d8c8c0034a3f6b6b3f289144a0ac7dfa`. Banner: "FastFonts V1.31 Copyright © 1987 by C.Heath of
  Microsmiths, Inc".
- Hunks: CODE $BF0, DATA $7C, BSS $4. Relocated to a dummy base (script `python3 -I`), disassembled
  with radare2 (`-a m68k`). All the statements below come from this disassembly.
- Invocation (`s/startup-sequence`, line 9): **`FF >NIL: -0 ;speed up Text`**.
- Libraries opened (OldOpenLibrary, without version): dos, graphics, intuition; diskfont only
  if a font name is passed or if option `1` is active. **No version test** of any library.

## Command-line options and shared state

- A flag word (initial value: bits 0, 1, 2 set) is modified by each `-x` option:

  | Option | Effect on the flags | Meaning |
  |---|---|---|
  | `B`/`b` | sets bits 0 and 1 | replace topaz 8 and topaz 9 with the given font |
  | `8` / `9` | sets bit 0 / bit 1 | replace only topaz 8 / topaz 9 |
  | `1` | sets bit 3 | also handle topaz 11 (loaded via diskfont) |
  | **`0`** | **clears bits 0, 1 and 3** | **no font replacement**; FastText (bit 2) intact |
  | `F`/`f` | sets bit 2 | FastText active |
  | `N`/`n` | clears bit 2 | FastText inactive |
  | `Q`/`q` | clears everything | terminate FastFonts (restore everything) |

  Unknown option → "Bad command line switch". A word without `-` is the name of a disk font.
- **`-0` therefore means: "speed up Text only, touch no font"**. No copy of
  a font nor replacement of topaz in the startup-sequence configuration.
- Persistent state: a public MsgPort named `FF2:)` (FindPort; otherwise AllocMem $48 bytes
  PUBLIC|CLEAR, ln_Type = NT_MSGPORT, mp_Flags = PA_IGNORE, AddPort). It keeps the open TextFonts
  (topaz 8 via `OpenFont({"topaz.font",8})`, topaz 9, optional topaz 11) and the two patch blocks
  (one for topaz 8, one for topaz 11). A second launch of FF finds the port, **first removes** the
  existing patches, then reinstalls according to the new flags.
- Launched from the Workbench (pr_CLI at $AC null): waits for/replies to the WBStartup on pr_MsgPort ($5C).

### Font replacement (inactive with `-0`, for the record)

OpenDiskFont(name, size); refused if tf_Flags ($17) has bit FPF_PROPORTIONAL, if tf_XSize ($18) or tf_YSize
($14) differ, or if tf_Baseline ($1A) differs. Otherwise FF **swaps in place** the contents of the topaz
TextFont (same structure address) with those of the disk font: words of tf_BoldSmear ($1C) and from
tf_LoChar ($20) to tf_CharKern ($30) inclusive. This assumes the topaz TextFont is modifiable (in RAM).

## 1. Replaced function and takeover conditions

- **Only one function is patched: `graphics.library Text()`, LVO −60 ($FFC4)**, via
  `exec SetFunction` (−420) between Forbid/Permit. The returned value (old vector) is stored in the
  patch block and serves as the fallback (absolute jump to the old Text).
- One block per accelerated font: topaz 8 always (if FastText active), topaz 11 if opened (option `1`).
  The second patch chains onto the first (its "old Text" is the topaz 8 patch).
- **Installation conditions** (on a local RastPort initialised by InitRastPort then SetFont):
  rp_TxWidth ($3C) **= 8** and 4 ≤ rp_TxHeight ($3A) ≤ 16. Otherwise no patch. No test of tf_Style,
  tf_Flags nor of a ROM/RAM address.
- **Run-time conditions** (otherwise direct jump to the old Text, registers intact):
  1. rp_AlgoStyle ($38) = 0;
  2. count (D0) ≤ 120 (signed comparison);
  3. **rp_Font ($34) = exactly the TextFont address** obtained by OpenFont at installation.
- **Not tested**: DrawMode, FgPen/BgPen, Mask, rp_Layer, rp_TxSpacing, rp_TxFlags, BitMap, depth.
  All of that is delegated to BltTemplate (see § 2).
- Reentrancy guard: during the fast path, the compared font constant is altered (then
  restored on exit). A concurrent (other task) or nested call with the same font therefore falls
  into the **old** Text: the ROM's Text must remain correct and reentrant.
- count = 0: nothing is drawn, no lock, exit through WaitBlit.

## 2. How the fast path draws

Entry contract = that of Text: A1 = RastPort, A0 = string, D0 = count, **A6 = GfxBase (used as
is to call other graphics LVOs)**.

1. **Lock**: if rp_Layer ($00) ≠ NULL, `LockLayerRom` (graphics −432, **layer in A5**); after the
   drawing, `UnlockLayerRom` (−438, A5). FF assumes that LockLayerRom **preserves D0/A0/A1** (it reuses
   string, RastPort and count right afterwards) and that it is **nestable** (BltTemplate may lock in
   turn).
2. **Construction of a 1-plane template by the CPU** in a private **CHIP** buffer (allocated MEMF_CHIP|PUBLIC
   at installation: 120 bytes × 8 lines = 960 bytes, ×2 if height > 8). No variable line
   stride: **fixed modulo of 120 bytes**, one byte (8 pixels) per character, one line per row of the
   font, from a pre-computed glyph table (§ 3). The code is self-modified at installation
   (buffer address, baseline, height, unrolling according to TxHeight) and copied into the patch block.
3. **Drawing: a single `BltTemplate` call** (graphics **−36**) with:
   A0 = start of the template, D0 = 0 (xSrc), D1 = 120 (srcMod in bytes), A1 = RastPort,
   D2 = rp_cp_x ($24), D3 = rp_cp_y ($26) − TxBaseline (constant frozen at installation),
   D4 = count × 8 (width in pixels), D5 = TxHeight (frozen constant).
4. **Update**: rp_cp_x += count × 8 (rp_TxSpacing ignored), rp_cp_y unchanged.
5. **Exit**: terminal jump to `WaitBlit` (graphics −228).

Consequences:
- **No hardware register is written by FF**; no direct access to the blitter; the blitter is
  only used through the ROM's BltTemplate.
- Fields read by FF: RastPort rp_Layer ($00), rp_cp_x/cp_y ($24/$26, cp_x written), rp_Font ($34),
  rp_AlgoStyle ($38). At installation: rp_TxHeight ($3A), rp_TxWidth ($3C), rp_TxBaseline ($3E)
  (filled by SetFont), write of rp_BitMap ($04) of the local RastPort. TextFont: tf_YSize ($14) on
  removal, tf_LoChar ($20). **No field of the destination BitMap, of the Layer (apart from the pointer passed to
  LockLayerRom) nor of a ClipRect is read.** No private Layer/ClipRect format is assumed: the
  clipping, hidden layers, smart refresh and super bitmap are entirely the responsibility of
  BltTemplate.
- LVOs used (graphics): Text −60 (old, at installation), SetFont −66, OpenFont −72,
  CloseFont −78, InitRastPort −198, WaitBlit −228, InitBitMap −390, LockLayerRom −432,
  UnlockLayerRom −438, **BltTemplate −36**. Exec: Forbid/Permit, AllocMem/FreeMem, SetFunction,
  FindPort/AddPort/RemPort, GetMsg/ReplyMsg/WaitPort, OldOpenLibrary/CloseLibrary. Dos: Output/Write,
  Delay(30) on removal.

## 3. Pre-computation of the font (no strike copy)

- FF **never reads tf_CharData/tf_CharLoc/tf_Modulo directly** and does not copy the strike. It
  has each glyph rendered by **the ROM's old Text**:
  - local RastPort on the stack (uninitialised → must be entirely zeroed by InitRastPort),
    InitRastPort then SetFont(font);
  - local BitMap via `InitBitMap(bm, depth 1, width 1024, height 8)` → **expected BytesPerRow = 128**;
    bm_Planes[0] ($08) = the CHIP buffer; rp_BitMap = &bm; **rp_Layer = NULL**;
  - for each character: cp_x = 0, cp_y = TxBaseline, `Text(rp, &c, 1)` (InitRastPort default
    brush: FgPen −1, BgPen 0, JAM2, Mask $FF), then CPU read of TxHeight bytes of
    column 0 with a **fixed stride of 128 bytes**;
  - **even for a font of height 11 the BitMap declares 8 lines**: Text without a layer must not
    clip at bm_Rows (the buffer is large enough).
- Resulting table in the patch block: 256 entries × 8 bytes (×16 if height > 8), indexed by the
  character code. If tf_LoChar = $20, codes $00–$1F receive the glyphs of $40–$5F **inverted**
  ("reverse video" rendering of control characters). Codes outside [LoChar, HiChar] receive what
  the old Text draws for them.
- The CHIP buffer then serves as the template for the fast path (it is reused, hence the reentrancy
  guard).
- Removal (`-q`, `-n` or relaunch): SetFunction(old value); if the returned value is not FF's
  entry point (someone re-patched on top), FF puts back the value it just
  removed, displays "Text() vector altered-aborting" and exits (code 5); otherwise Delay(30) (let
  the tasks still inside the patch leave) then FreeMem of the buffer and of the block.

## 4. Why the glyphs do not appear on our ROM (in order of probability)

1. **BltTemplate (graphics −36) is not implemented** — **verified**: in
   `src/graphics/graphics_lib.s`, entries 6..8 (LVO −36..−48) point to `graphics_null`. Any
   topaz 8 text, AlgoStyle 0, ≤ 120 characters goes through the fast path, which draws *only* through
   BltTemplate: nothing is written. The visible background comes from the clears done by the console/intuition
   themselves. Before SetFunction was real, the patch did not install, hence the former good
   behaviour. **Near-certain cause.**
2. Once BltTemplate is implemented, an empty glyph table (silent glyphs but JAM2 background drawn)
   would come from the **installation**: Text on a RastPort **without Layer** to a private BitMap that does not
   draw; InitRastPort that does not zero everything (residual rp_Layer from the stack) or does not set
   FgPen = −1 / Mask = $FF; InitBitMap that does not give BytesPerRow = 128 for 1024 pixels; Text that
   clips at bm_Rows.
3. BltTemplate implemented but incomplete: srcMod interpreted in words, xSrc mishandled, rp_Layer not
   taken into account (offset of the layer bounds, ClipRects, cr_BitMap of hidden parts),
   DrawMode/FgPen/BgPen/Mask ignored, or non-nestable layer lock (deadlock, FF already holding
   LockLayerRom).
4. LockLayerRom/UnlockLayerRom that do not take the layer in **A5** or that destroy D0/A0/A1 →
   string/count/RastPort corrupted.
5. Internal call of Text via the vector with **A6 ≠ GfxBase**: the fast path would call LVOs
   relative to another base.
6. AllocMem(MEMF_CHIP) returning non-CHIP memory whereas BltTemplate uses the blitter.

## Requirements for our ROM

- **Implement `BltTemplate`** (LVO −36), AutoDocs contract: A0 = template (even address), D0 = xSrc
  (bit offset in the first word, 0..15), D1 = srcMod (**bytes** per line), A1 = RastPort,
  D2/D3 = destination (RastPort coordinates, hence relative to the layer if rp_Layer), D4 = width,
  D5 = height in pixels. Template bit 1 = FgPen, bit 0 = BgPen in JAM2 / transparent in JAM1;
  COMPLEMENT and INVERSVID; respect rp_Mask and the BitMap depth; clip by the ClipRects
  of rp_Layer (hidden parts to cr_BitMap in smart refresh, ignored in simple refresh, super
  bitmap) and to the BitMap limits without a layer; negative coordinates clipped. Preserve D2–D7/A2–A6
  (FF re-reads A5 after the call).
- The layer lock internal to BltTemplate must be **nestable** by the same task (FF already holds
  LockLayerRom).
- `LockLayerRom`/`UnlockLayerRom`: layer in **A5**, preserve **all** registers, nestable.
- `InitRastPort`: zeroes the whole RastPort then default values (FgPen −1, AOlPen −1, BgPen 0,
  Mask $FF, JAM2, LinePtrn $FFFF, default font). `SetFont` fills TxHeight/TxWidth/TxBaseline
  ($3A/$3C/$3E).
- `InitBitMap`: BytesPerRow = ((width + 15) / 16) × 2, Rows, Depth, without touching the Planes.
- `Text` with rp_Layer = NULL: draw directly into rp_BitMap, without clipping at bm_Rows (topaz 11 case).
  Remain reentrant (concurrent fallback from the patch).
- `SetFunction`: return the old address; FF's removal compares the returned value with its entry
  point.
- Every call of Text through the vector must have A6 = GfxBase; `WaitBlit` callable from any
  task context.
- `OpenFont({"topaz.font",8})` must return the **same address** of TextFont as the one placed in rp_Font
  of the windows (otherwise FF is simply inactive, without damage).
- Proposed non-regression test: after `FF -0`, a topaz 8 `Text` of ≤ 120 characters in a
  window (console + menu PrintIText + icon name) must display the glyphs; a text > 120
  characters or in bold must also display (fallback path).

## Clean-room review

Review of 2026-10-29.

- [x] Target = third-party program `C:FF` (FastFonts V1.31, Workbench disk); the Kickstart ROM was not
  opened. No ROM routine address, no disassembly excerpt (neither of FF nor of the ROM).
- [x] No Kickstart ROM data transcribed: no glyph, no topaz strike, no table;
  FF's glyph table is described (size, indexing, inversion of control codes) without
  contents. The offsets cited are those of the public structures (RastPort, TextFont, BitMap, Process)
  and the public LVOs.
- [x] The requirements for our ROM are formulated as AutoDocs/ABI contracts (registers, fields).
