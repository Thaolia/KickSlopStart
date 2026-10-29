# graphics.library 34 — display construction and VBlank server — behavioural spec

> **ANALYSIS** track (dirty). Sources: ROM `assets/kick34005.A500` (read only; temporary disassembly
> outside the repository) and black-box probe `tests/gdisp_probe.s` / `tests/gdisp_probe.sh` run
> on the real ROM (FS-UAE A500, 512 KB chip + 512 KB slow, PAL then NTSC). **Behavioural**
> specification: structures read and written, contents and order of the copper lists, values, conditions.
> No ROM instruction sequence is reproduced; the addresses cited are **RAM** addresses
> of the probed run (examples), never routine addresses.
>
> Legend: **[O]** observed in the binary `kick34005.A500` (radare2, base `$FC0000`) ·
> **[S]** black-box probed under FS-UAE with the real ROM (`tests/gdisp_probe.sh`) ·
> **[D]** deduced (reasoning on [O]/[S] or on the public hardware documentation, not executed).
>
> Complements, without repeating them: `caesar-boot.md` §2.7 (copinit → COPJMP2 → COP2LC dependency),
> `cracktros-exit.md` (programs that restart copinit or rewrite COP1LC), `monkey-startup.md` §3
> (a game's UCopIns), `sysinfo-44.md` §1.3 (WaitTOF).

---

## 0. Short answer

- 1.3 builds the display in **three stages**: `MakeVPort` fills for each ViewPort an
  **intermediate** list (`vp_DspIns`, 6-byte instructions, positions **relative to the top of the
  ViewPort**); `MrgCop` **merges** by WAIT position all the intermediate lists of the View into
  one or two **hardware** lists (`v_LOFCprList`, `v_SHFCprList`, copper words in CHIP); `LoadView`
  only publishes these lists in GfxBase. [O][S]
- The copper is started at each frame by the hardware on **copinit** (COP1LC, never modified after
  init); copinit ends with **WAIT line 12 then COPJMP2 strobe**; it is **graphics' VBlank
  server** that writes **COP2LC := gb_LOFlist** (or gb_SHFlist according to the LOF bit in interlace) at each
  frame. [O][S] (cf. `caesar-boot.md` §2.7)
- Within a ViewPort, the **vertical window is not made by DIWSTRT/DIWSTOP**: DIWSTRT is
  always `$05xx` and DIWSTOP `$40xx` (window open from lines 5 to 320); the display is switched on and
  off by two writes of **BPLCON0** (number of planes, then 0 planes) placed on WAITs at the top
  and at the bottom of the ViewPort. [O][S]
- Between two stacked ViewPorts there must be **at least one empty line** (two if the bottom ViewPort has more
  than 4 planes, or more than 3 planes with SPRITES); with **contiguous** ViewPorts, the bottom ViewPort
  stays **off** (the "off" BPLCON0 of the top one is emitted after its "on" BPLCON0). [S]
- `SetRGB4`/`LoadRGB4` and `ScrollVPort` **modify the hardware lists in place** (without MrgCop);
  `ScrollVPort` swaps the two frames in interlace (1.3 bug, §7.3). [O][S]
- `VideoControl` **does not exist** in V34 (LVO −708, appeared in V36; the V34 table stops at −654). [O]

---

## 1. Structures (V34 offsets) [O][S]

### 1.1 View (18 bytes)

| Off | Field | Read/written by |
|---|---|---|
| $00 | ViewPort (first) | MrgCop (walk), LoadView (search for the topmost ViewPort) |
| $04 | LOFCprList | MrgCop (allocates/reuses), LoadView (reads `start`) |
| $08 | SHFCprList | MrgCop (only if Modes & LACE), LoadView (reads `start` **without a NULL test**, §5.1) |
| $0C | DyOffset (w) | MrgCop (added to all WAIT lines), WaitBOVP, ScrollVPort |
| $0E | DxOffset (w) | MakeVPort/ScrollVPort (added to the horizontal position) |
| $10 | Modes (w) | only the **LACE ($0004)** bit is used: BPLCON0, SHF list, modulo, LoadView |

`InitView`: sets the 18 bytes to 0 then **DyOffset := $2C (44), DxOffset := $81 (129)**; Modes = 0.
Nothing else (no PAL/NTSC dependency). [O][S]

### 1.2 ViewPort (40 bytes)

| Off | Field | Notes |
|---|---|---|
| $00 | Next | chaining within the View |
| $04 | ColorMap | NULL allowed (default table, §3) |
| $08 | DspIns | intermediate CopList built by MakeVPort |
| $0C | SprIns | not built by MakeVPort; merged if present |
| $10 | ClrIns | same |
| $14 | UCopIns | chain of UCopLists (§6); merged |
| $18 | DWidth (w) | in pixels of the mode (hires = hires pixels) |
| $1A | DHeight (w) | in lines of the mode (interlace = interlaced lines) |
| $1C | DxOffset (w) | same as DWidth |
| $1E | DyOffset (w) | same as DHeight |
| $20 | Modes (w) | HIRES $8000, SPRITES $4000, VP_HIDE $2000, HAM $0800, DUALPF $0400, EXTRA_HALFBRITE $0080, PFBA $0040, LACE $0004 |
| $22 | SpritePriorities (b) | |
| $23 | (reserved, b) | |
| $24 | RasInfo | |

`InitVPort`: sets the 40 bytes to 0 then **SpritePriorities := $24** (verified: nothing is written beyond
byte 40). [O][S]

### 1.3 RasInfo (12) and BitMap

RasInfo: Next $00 (second playfield in DUALPF), BitMap $04, RxOffset $08 (w), RyOffset $0A (w).
BitMap: BytesPerRow $00 (w), Rows $02 (w), Flags $04 (b), **Depth $05 (b)**, Planes[8] $08. MakeVPort
reads BytesPerRow, Depth and Planes; never Rows. [O][S]

### 1.4 ColorMap (8 bytes)

Flags $00 (b), Type $01 (b), Count $02 (w), ColorTable $04 (l). [O][S]

### 1.5 Intermediate CopList (34 bytes = $22) and CopIns (6 bytes)

| Off | Field | Observed role |
|---|---|---|
| $00 | Next | next block of the same list (overflow) |
| $04 | _CopList | **reused by MrgCop** as the link of its merge list |
| $08 | _ViewPort | set by MrgCop (owning ViewPort) |
| $0C | CopIns | array of instructions (6 bytes each) |
| $10 | CopPtr | current instruction (builder, then merge cursor) |
| $14 | CopLStart | address, in the LOF hardware list, of the first word emitted for this CopList |
| $18 | CopSStart | same in the SHF list (or 0) |
| $1C | Count (w) | instructions written in this block |
| $1E | MaxCount (w) | capacity of the block |
| $20 | DyOffset (w) | not used in 1.3 (0) |

CopIns: `OpCode` (w), then two words: for a **MOVE** (OpCode & 3 = 0) `DestAddr`, `DestData`; for
a **WAIT** (OpCode & 3 = 1) `VWaitPos`, `HWaitPos`; for **CPRNXTBUF** (OpCode & 3 = 2) a long pointer
to the next CopList. Frame bits in OpCode (**observed** semantics, §4.4):
**$8000 = instruction emitted in the LOF list only**, **$4000 = in the SHF list only**.
DestAddr is kept as is in the intermediate list (e.g. `$F180` for COLOR00, low word of
`$DFF180`); only `DestAddr & $1FE` goes into the hardware list. [O][S]

### 1.6 cprlist (10 bytes)

Next $00, start $04 (array of copper words, **MEMF_CHIP|MEMF_PUBLIC**), MaxCount $08 (w, in
**4-byte instructions**). [O][S]

### 1.7 UCopList (12 bytes)

Next $00, FirstCopList $04, CopList $08 (current block). [O][S]

### 1.8 GfxBase fields concerned (PAL readings, at bootblock time) [S]

| Off | Field | Value / role |
|---|---|---|
| $22 | ActiView | last View passed to LoadView (NULL accepted) |
| $26 | copinit | startup copper list, 92 bytes CHIP (here `$420`) |
| $32 | LOFlist | address put into COP2LC by the VBlank (long frame or non-interlaced) |
| $36 | SHFlist | same, short frame in interlace |
| $4A | vbsrv | Interrupt of the VERTB server, **pri 10**, is_Data = GfxBase |
| $9E | Modes (w) | copy of View.Modes made by LoadView |
| $A0 | VBlank (b) | set to 0 at each VBlank |
| $A4 | system_bplcon0 (w) | 0, or `$0102` if genlock detected (§8.1); ORed into **all** BPLCON0s |
| $C0 | TOF_WaitQ | list of the tasks in WaitTOF |
| $CE | DisplayFlags (w) | **4 = PAL**, **1 = NTSC**, + 2 (GENLOC) if system_bplcon0 has ERSY |
| $D4 | MaxDisplayRow | PAL **$137 (311)**, NTSC **$105 (261)** |
| $D6 | MaxDisplayColumn | **$1D1** (both) |
| $D8 | NormalDisplayRows | PAL **256**, NTSC **200** |
| $DA | NormalDisplayColumns | **640** |
| $DC/$DE | NormalDPMX / NormalDPMY | PAL **$4CA / $513**, NTSC **$500 / $44A** |
| $E0 | LastChanceMemory | SignalSemaphore (46 bytes) |
| $E4 | LCMptr | 2 KB CHIP buffer allocated **just after copinit** (here `$480`) |
| $E8 | MicrosPerLine | **$3F9D** (both) |
| $EA | MinDisplayColumn | **$30** |

Side effect to reproduce: the graphics init writes **ExecBase→VBlankFrequency (+$212) := 50 (PAL) or
60 (NTSC)** according to the detection (§8.1). [O][S]

---

## 2. copinit [O][S]

Allocated at init (92 bytes, CHIP|PUBLIC), never reallocated. Contents (offsets in bytes):

| Off | Instruction | Notes |
|---|---|---|
| $00 | MOVE BPL1PTH, 0 | **rewritten by LoadView/SetRGB4/LoadRGB4**: becomes `MOVE COLOR00, <colour 0 of the topmost ViewPort>` as soon as a View with a ColorMap is loaded; goes back to `MOVE BPL1PTH` (data unchanged) if that ViewPort has no ColorMap |
| $04 | MOVE BPL1PTL, 0 | |
| $08–$47 | 8 × (MOVE SPRxPTH, MOVE SPRxPTL) | at the start, the 8 pointers target the empty sprite at copinit+$58; GetSprite/ChangeSprite install the sprites there (probed: sprite 0 → `$0C80`, the pointer, reserved: SpriteReserved = 1) |
| $48 | WAIT `$0C01,$FFFE` | line 12 |
| $4C | MOVE COPJMP2 (`$008A,$0000`) | jump to COP2LC |
| $50 | `$FFFE,$FFFF` | MOVE to register $1FE (no effect); never executed normally |
| $54 | `$FFFF,$FFFE` | end; **initial COP2LC** of the init points here |
| $58 | `$FE00,$FF00` | control words of the empty sprite (VSTART $FE); the 2 end words that follow are **outside** the 92 bytes |

At init: DMACON := $0080 (copper off), COP1LC := copinit, then the **hardware** SPRxPOS/CTL :=
$FE00/$FF00, COP2LC := copinit+$54; later DMACON := $81A0 (SET, BPLEN, COPEN, SPREN),
COLOR00 = COLOR01 = $FFF. The display registers are initialised directly by the CPU (also
at each `LoadView(NULL)`): BPLCON0 := system_bplcon0 | $1200, BPLCON1 := 0, BPLCON2 := $24,
BPL1MOD = BPL2MOD := 0, **DIWSTRT := $2C81, DIWSTOP := $F4C1, DDFSTRT := $38, DDFSTOP := $D0**, then
wait until the vertical position is no longer in `$FFxx`, then **VPOSW := VPOSR | $8000** (forces a
long frame). [O]

**Anomaly to reproduce as is**: the initial gb_LOFlist and `LoadView(NULL)` are
**copinit + $A0**, an address **outside** copinit (92 bytes): on the probed machine it falls in the
LCM buffer (`$4C0`, filled with zeros, which the copper executes as MOVEs to $000 without effect). [O][S]

---

## 3. Colours: ColorMap, GetRGB4, SetRGB4CM, SetRGB4, LoadRGB4

Default table (32 entries) [O][S]:
`000 F00 0F0 FF0 00F F0F 0FF FFF 620 E50 9F1 EB0 55F 92F 0F8 CCC 000 111 222 333 444 555 666 777 888
999 AAA BBB CCC DDD EEE FFF`.

- **GetColorMap(n)**: AllocMem(8, PUBLIC) **without CLEAR** (Flags not initialised, Type := 0), Count := n,
  ColorTable := AllocMem(2n, PUBLIC) copied from the default table over **n entries without bound**:
  for n > 32 the entries 32+ are arbitrary bytes (probed: contents of the ROM that follows). Failure of
  the 2nd allocation: the 1st is freed, return 0. [O][S]
- **FreeColorMap(cm)**: frees the table (2·Count) then the structure; no NULL test. [O]
- **GetRGB4(cm, i)**: i ≥ Count ⇒ **−1**; otherwise ColorTable[i] (word, extended). [O][S]
- **SetRGB4CM(cm, i, r, g, b)**: cm NULL ⇒ returns 0 without doing anything; i ≥ Count ⇒ −1; otherwise
  `(r&15)<<8 | (g&15)<<4 | (b&15)` and returns 0 (probed: (15,$10,$21) → `$0F01`). [O][S]
- **SetRGB4(vp, i, r, g, b)**: i > 31 ⇒ −1 (signed comparison). vp NULL ⇒ direct write of the
  COLORi register. Otherwise: SetRGB4CM on vp→ColorMap (−1 propagated); then, if vp→DspIns exists and vp is not
  VP_HIDE, **in-place replacement** of the data of the first `MOVE COLORi` found in the LOF hardware
  list starting from DspIns→CopLStart, and likewise in the SHF list (CopSStart); then update
  of the corresponding MOVE in the intermediate list; then update of copinit (§2). Return 0.
  **No MrgCop/LoadView is needed**: the new colour is visible at the next frame. [O][S]
- **LoadRGB4(vp, table, n)**: n capped at 32. vp NULL ⇒ direct write COLOR0..n−1. Otherwise: if
  ColorMap, n := min(n, Count) and copy into ColorTable; then, if DspIns and not hidden, in-place patch
  of the n consecutive colours starting from the first `MOVE COLOR00` of the LOF and SHF lists (a colour whose
  MOVE is not at the expected position is skipped), update of the intermediate list, then copinit. [O][S]

---

## 4. MakeVPort(view, vp) — intermediate list

### 4.1 Allocation [O]

DspIns is **reused** if it exists (Count reset to 0, chained blocks kept and reused);
otherwise CopList (34 bytes, CLEAR) + 40 instructions. Overflow: when Count reaches MaxCount, a following
block (34 bytes + 16 instructions, MEMF_PUBLIC) is allocated or reused, the last instruction is
moved into it and replaced by a **CPRNXTBUF** to that block (probed in HAM/EHB: CPRNXTBUF at rank 40).
DspIns allocation failure ⇒ **Alert $82010030**. [O][S]

### 4.2 Derived parameters [O][S]

- `depth` = Depth of the BitMap (+ Depth of the 2nd RasInfo in DUALPF); outside DUALPF/HAM/EHB, capped at 5. No
  other check (hires 5 planes accepted → BPLCON0 `$D200`, illegal on OCS).
- `ncol` = 16 if HAM or DUALPF, otherwise `1 << min(depth,5)` (EHB 6 planes → 32).
- Lead-in line `L0` = **−1**, or **−2** if (depth > 4 and not DUALPF) or (depth > 3 and SPRITES);
  **doubled if vp LACE**.
- Colour table: ColorMap→ColorTable, or the default table if ColorMap NULL. **ncol colours are
  emitted whatever Count is** (a ColorMap that is too short is read beyond its end). [O]

### 4.3 Contents, in order (single-playfield case) [S]

1. `WAIT(L0, 0)`
2. `MOVE COLOR00..COLOR(ncol−1)`; if SPRITES and depth < 5: in addition `COLOR16..COLOR(Count−1)` taken from
   entries 16+ (Count capped at 32, 32 if no ColorMap).
3. `MOVE DIWSTRT := $0500 | (x & $FF)`
4. `MOVE BPLCON0 := system_bplcon0 | $0200 | (View.Modes & LACE)` (0 planes: screen off)
5. `MOVE BPLCON2 := (vp.Modes & PFBA) | SpritePriorities`
6. `MOVE DIWSTOP := $4000 | ((x + w) & $FF)`
7. `MOVE DDFSTRT`, `MOVE DDFSTOP`, `MOVE BPLCON1 := s | s<<4`
8. `MOVE BPL1MOD`; `MOVE BPL2MOD` (if depth > 1) — same value
9. for each plane i: `MOVE BPLiPTH`, `MOVE BPLiPTL` (address = Planes[i] + offset); if vp LACE:
   pair marked **$8000** (LOF) with the address, and, if View **and** vp LACE, pair marked **$4000** (SHF)
   with address + BytesPerRow
10. `WAIT(0, 0)` — top of the ViewPort
11. `MOVE BPLCON0 := depth<<12 | system_bplcon0 | $0200 | (View.Modes & LACE) | (vp.Modes & (HIRES|HAM|DUALPF))`
    (EHB adds no bit; SPRITES neither)
12. `WAIT(DHeight, 0)` — bottom of the ViewPort
13. `MOVE BPLCON0 := ` value of point 4
14. `WAIT(10000, 255)` — end

DUALPF: points 3–9 computed for each playfield (§4.5); planes alternated PF1 (BPL1, 3, 5) / PF2 (BPL2,
4, 6); BPL1MOD/BPL2MOD computed separately. As long as the vertical DIWSTRT is `$05`, the hardware vertical
window covers lines 5 to $140: only BPLCON0 cuts out the ViewPort.

### 4.4 Horizontal: DIW, DDF, BPLCON1, modulo, plane offset [O][S]

Notation: `w` = DWidth, `x` = vp.DxOffset, `rx` = RxOffset; in HIRES, `w`, `x` and `rx` are first
divided by 2 (arithmetic shift), mask `m` = 7, fetch base `B` = $3C; in LORES `m` = 15,
`B` = $38.

1. `s` = (−rx) & m; "scroll" flag `S` = (s ≠ 0), or, in DUALPF, s of the other playfield ≠ 0.
2. `xmax` = MaxDisplayColumn ($1D1), **−10 if S**. `x` += View.DxOffset. If `x + w > xmax` then
   `w := xmax − x` (right clipping).
3. `x' = x − $81`; plane offset = `RyOffset × BytesPerRow + 2 × (rx >> (HIRES ? 3 : 4))` (rx already
   divided in HIRES).
4. `s` := (x' & m) + s; if s > m then s := s & m and S := false.
5. If S: `B` −= 8 and, in HIRES only, offset −= 2.
6. `DDFSTRT` = B + ((x' >> 1) & (HIRES ? ~3 : ~7)).
7. Left clipping: if `DDFSTRT < MinDisplayColumn/2` ($18), advance by `d` = 2 × gap (×2 again in
   HIRES): rx += d, x = vp.DxOffset + d, w = DWidth − d, and start again at 1.
8. `DDFSTOP` = (((w + 15) >> 1) & ~7) + DDFSTRT − (rx & m ? 0 : 8), capped at **$D8**; in HIRES −4 then
   capped at **$D4**.
9. Bytes fetched per line: HIRES `((STOP − STRT)/2 + 6) & ~3`, LORES `(STOP − STRT)/4 + 2`.
   **Modulo** = BytesPerRow − bytes fetched, **+ BytesPerRow if View and vp LACE**.
10. DIW (point 3/6 of §4.3) with `x` restored (= x' + $81) and `w` clipped.

DUALPF: if the two `s` differ, DIWSTOP −1; DDFSTRT = min of the two, DDFSTOP = max; the playfield whose
DDFSTRT was larger sees its plane offset reduced by 4 (HIRES) or 2 (LORES).

Probed vectors (default View, Dy 0):

| Config | DIWSTRT/STOP | DDFSTRT/STOP | BPLCON1 | MOD | BPL1PT | top BPLCON0 |
|---|---|---|---|---|---|---|
| LORES 320×200, 2 pl, bpr 40 | $0581/$40C1 | $38/$D0 | $00 | 0 | P0 | $2200 |
| HIRES 640×200, 4 pl, bpr 80 | $0581/$40C1 | $3C/$D0 | $00 | 0 | P0 | $C200 |
| LORES rx=5 ry=3, bpr 80 | $0581/$40C1 | $30/$D0 | $BB | $26 | P0+$F0 | $2200 |
| HIRES rx=3, bpr 80 | $0581/$40C1 | $34/$D0 | $77 | −4 | P0−2 | $A200 |
| LORES Dx=−10 | $0577/$40B7 | $30/$C8 | $66 | 0 | P0 | $1200 |
| LORES DW=400, bpr 50 | $0581/$40D1 | $38/$D8 | $00 | 8 | P0 | $1200 |
| LORES Dx=20 DW=200 | $0595/$405D | $40/$A0 | $44 | $0E | P0 | $1200 |
| View Dx=$85 | $0585/$40C5 | $38/$D0 | $44 | 0 | P0 | $1200 |
| DUALPF 2+2, PF2 rx=3 | $0581/$40C0 | $30/$D0 | $D0 | −2/−2 | PF1 P0−2, PF2 P0 | $4600 |
| HAM 6 pl (16 col., WAIT −2) | $0581/$40C1 | $38/$D0 | 0 | 0 | P0 | $6A00 |
| EHB 6 pl (32 col., WAIT −2) | same | same | 0 | 0 | P0 | $6200 |
| DUALPF 3+3 | same | same | 0 | 0 | PF1/PF2 alternated | $6600 |
| LACE view+vp, 320×400 | same | $38/$D0 | 0 | $28 | LOF P0, SHF P0+$28 | $1204 |

### 4.5 Behavioural remarks [O][S]

- MakeVPort **does not look at VP_HIDE** (the list is built; MrgCop ignores it).
- vp LACE in a non-LACE View: WAIT −2 (relative, divided by 2 at merge time), BPLxPT pairs marked
  $8000 only, modulo without the extra BytesPerRow, BPLCON0 without LACE; there is no
  SHF list, so the $8000 pair is emitted in LOF and the image skips every other line. [S]
- non-LACE vp in a LACE View: BPLCON0 with LACE, WAIT −1, same instructions in LOF and SHF. [S]
- SprIns/ClrIns are never built by MakeVPort; only UCopIns and DspIns come from
  the caller/MakeVPort in the probed 1.3. [O]

---

## 5. MrgCop(view) — merge into hardware lists

### 5.1 Collection and allocation [O][S]

For each ViewPort of the View **not VP_HIDE**, in chain order, the following are added to the merge
list: DspIns, SprIns, ClrIns then each UCopList of UCopIns (its FirstCopList). A NULL CopList or
one with Count 0 is ignored. Each addition is made **at the head** (the last one added is examined first);
for each block, CopLStart/CopSStart := 0, _ViewPort := vp, CopPtr := CopIns. No CopList ⇒ MrgCop
returns **without touching** the existing lists.

Size = sum of the Counts + 3. `LOFCprList` is created (10 bytes PUBLIC + size×4 bytes CHIP|PUBLIC)
or reused; if the size exceeds MaxCount, the old array is freed and reallocated. `SHFCprList`
likewise **only if View.Modes & LACE**; otherwise it is **neither created nor freed**. [O][S]

### 5.2 Merge algorithm [O][S]

Repeat until the last horizontal position emitted is ≥ 255:
1. For each CopList of the merge: emit the **consecutive MOVEs** starting from CopPtr (in LOF
   unless bit $4000, in SHF unless bit $8000; word 1 = DestAddr & $1FE, word 2 = data), follow the
   CPRNXTBUFs, and leave CopPtr on the next WAIT.
2. Choose the CopList whose current WAIT has the smallest key
   `((vp.DyOffset + VWaitPos) [÷2 if vp LACE]) × 1024 + HWaitPos`; on a tie, **the first one
   examined** (hence the last one added: UCopIns before DspIns, bottom ViewPort before the top one).
3. If its CopLStart is 0, CopLStart := current position in LOF, CopSStart := position in SHF.
4. Emit its WAIT then advance its CopPtr:
   - line `v` = View.DyOffset + (vp.DyOffset + VWaitPos) [÷2 if vp LACE]; if v ≥ MaxDisplayRow,
     v := MaxDisplayRow − 1;
   - if v > 255: the first time, emit `WAIT(255, hx)` then `WAIT(v − 256, h)` (and all the
     following ones directly as `v − 256`); `hx` is **$DE**, unless the last BPLCON0 emitted has its 4 high
     bits = `$C` (HIRES 4 planes) **and** the last DDFSTOP emitted is **$D4**: then `hx` = the value of the
     last DDFSTRT (the copper no longer has a cycle at $DE in this mode);
   - word 1 = `(v << 8) | (h & $FE) | 1`, word 2 = `$FFFE` (comparison on all positions);
   - a WAIT **identical** to the previous one emitted (same v, same h) is not repeated;
   - the end WAIT (10000, 255) becomes `v = 255, h = $FE` → **`$FFFF,$FFFE`** which ends the list.
5. In interlace, each WAIT goes into both lists.

End in interlace: just before `$FFFF,$FFFE`, each list receives `MOVE COP2LCH`, `MOVE COP2LCL` pointing to
**the other** list (LOF → address of SHF, SHF → address of LOF). [S]

### 5.3 Probed examples (PAL, default View) [S]

LORES 320×200, 2 planes, dummy planes `$20000/$21000`, ColorMap of 4:
```
2B01 FFFE  0180 0000  0182 0F00  0184 00F0  0186 0FF0  008E 0581  0100 0200  0104 0024
0090 40C1  0092 0038  0094 00D0  0102 0000  0108 0000  010A 0000  00E0 0002  00E2 0000
00E4 0002  00E6 1000  2C01 FFFE  0100 2200  F401 FFFE  0100 0200  FFFF FFFE
```
(MaxCount 26 = 23 instructions + 3.)

Interlaced (View and vp LACE, 320×400, 1 plane) — LOF then SHF:
```
LOF : 2B01 FFFE … 0108 0028  00E0 0002  00E2 0000  2C01 FFFE  0100 1204  F401 FFFE  0100 0204  0084 0000  0086 <SHF>  FFFF FFFE
SHF : 2B01 FFFE … 0108 0028  00E0 0002  00E2 0028  2C01 FFFE  0100 1204  F401 FFFE  0100 0204  0084 0000  0086 <LOF>  FFFF FFFE
```

256 lines (LORES or HIRES 4 planes, DDFSTOP $D0): `… 2C01 FFFE 0100 x200 FFDF FFFE 2C01 FFFE 0100 0200
FFFF FFFE` (crossing of line 255 at $DE, then line $12C noted $2C).

UCopList (`CWAIT(10,0) CMOVE(COLOR00,$F00) CWAIT(20,$40) CMOVE(COLOR00,$0F0) CEND`) on a vp Dy 0:
`… 2C01 FFFE 0100 1200 3601 FFFE 0180 0F00 4041 FFFE 0180 00F0 F401 FFFE 0100 0200 FFFF FFFE` — the
positions of the UCopList are **relative to the top of the ViewPort** (and to View.DyOffset).

### 5.4 Stacked ViewPorts [S]

| Case | List produced around the junction | Result |
|---|---|---|
| vp0 Dy 0 DH 100; vp1 HIRES Dy **102** | `9001 0100 0200` · `9101` colours/DIW/DDF/PT of vp1 · `9201 0100 9200` · `F601 0100 0200` | one empty line ($90) and one preparation line ($91) |
| vp0 Dy 0 DH 100; vp1 Dy **100** (contiguous) | `8F01` settings of vp1 (during the last line of vp0) · `9001 0100 1200 0100 0200` | **vp1 stays off** until its end; the last line of vp0 takes the colours/pointers of vp1 |
| vp1 with VP_HIDE | vp1 absent from the list, CopLStart = 0 | |

Deduced rule: the bottom ViewPort must start at least at `Dy_top + DH_top − L0` (L0 = −1 or −2,
§4.2), i.e. **one empty line** normally, **two** for a ViewPort with WAIT −2. [D]

---

## 6. UCopList: UCopperListInit, CMove, CWait, CBump, FreeCopList [O][S]

- **UCopperListInit(ucl, n)**: if ucl→FirstCopList exists, it is reused (Count := 0, CopPtr :=
  CopIns); otherwise CopList (34 b, CLEAR) + n instructions. FirstCopList = CopList := this block; returns the
  block or 0.
- **CMove(ucl, reg, val)** / **CWait(ucl, v, h)**: if ucl→CopList is NULL, implicit `UCopperListInit(ucl, 16)`;
  write the instruction at CopPtr (MOVE: OpCode 0, DestAddr = low word of `reg`, data;
  WAIT: OpCode 1, v, h) **without advancing**.
- **CBump(ucl)**: advances CopPtr, Count+1, overflow by CPRNXTBUF as in MakeVPort (block of 16).
  Count only increases with CBump: a CMove not followed by CBump does not exist.
- **CEND** (WAIT 10000, 255 + CBump): merges with the end of the list (no extra instruction).
- The UCopList is only taken into account at the next **MrgCop** (after MakeVPort or not: MrgCop reads
  UCopIns directly).
- **FreeVPortCopLists(vp)**: vp NULL ⇒ nothing; frees DspIns, ClrIns, SprIns (FreeCopList: each block
  → MaxCount×6 then 34 bytes), then **each UCopList of UCopIns, 12-byte structure included**,
  then sets the four pointers to NULL (probed). A program must therefore not free its
  UCopLists itself after FreeVPortCopLists.
- **FreeCopList(cl)**: walks Next. **FreeCprList(cpr)**: walks Next, frees `start` (MaxCount×4)
  then 10 bytes; resets nothing in the View.

---

## 7. LoadView, ScrollVPort, WaitTOF, WaitBOVP, VBeamPos

### 7.1 LoadView(view) [O][S]

1. If GfxBase.Modes has LACE and the new View does not: busy wait for a **short frame**
   (LOF bit of VPOSR at 0) then for a line ≥ 10.
2. INTENA := $0020 (VERTB off).
3. ActiView := view.
4. view not NULL: GfxBase.Modes := View.Modes; LOFlist := LOFCprList→start; **SHFlist :=
   SHFCprList→start without a NULL test** — for a non-interlaced View, it is the long at address 4
   (**ExecBase**) that is copied (probed: SHFlist = `$C00276` = ExecBase); then update of the first
   word of copinit (§2: colour 0 of the topmost visible ViewPort, in the sense of the smallest
   DyOffset [÷2 if LACE]). A View without LOFCprList (MrgCop never called) would likewise read
   address 4.
5. view NULL: LOFlist := copinit + $A0 (§2), Modes := 0, CPU reinitialisation of the display
   registers (§2) — SHFlist is not touched.
6. INTENA := $8020.

LoadView **writes neither COP1LC nor COP2LC**: the new View appears at the next VBlank. [O]

### 7.2 graphics VBlank server (VERTB, pri 10) [O][S]

At each VERTB interrupt:
1. GfxBase.VBlank := 0.
2. COP2LC := LOFlist, or, if GfxBase.Modes has LACE: LOFlist if the LOF bit of VPOSR is 1, SHFlist
   otherwise. (In interlace the lists also swap themselves via their final MOVE COP2LC, §5.2.)
3. **CIA-B TOD** (HSYNC counter): TOD write (CRB bit 7 := 0), TODHI := 0, TODMID := 0, TODLO
   := current vertical position (low 8 bits), then CRB bit 7 := 1 — CIA-B's TOD therefore follows the line
   number; it is used for the beam synchronisation of blits (QBSBlit, out of scope).
4. Signal(**SIGF_SINGLE**, $10) to each task of TOF_WaitQ (the node carries the task in ln_Name).
5. Return with Z = 1 (the chain continues).

The server **touches neither copinit, nor the sprites, nor COP1LC**. Nothing else (no frame
counter in GfxBase). [O]

### 7.3 ScrollVPort(vp) [O][S]

- VP_HIDE ⇒ nothing. Uses **GfxBase.ActiView** (no View parameter): the ViewPort must belong to
  the loaded View, otherwise the positions and the DxOffset are those of the active View.
- Recomputes DDFSTRT, DDFSTOP, BPLCON1, modulos and plane offset as MakeVPort does (§4.4) — **not
  DIWSTRT/DIWSTOP nor the colours**.
- Waits for the beam to have passed the **1st line** of the ViewPort (same wait as WaitBOVP with
  height 1), then replaces in place, starting from CopLStart/CopSStart: DDFSTRT, BPL1MOD, BPL2MOD (if
  depth > 1), DDFSTOP, BPLCON1, then the BPLxPT pairs; finally updates the intermediate list (same
  $8000/$4000 marking as MakeVPort).
- **Bug reproduced by the probe**: in interlace, the hardware patch puts the base address in the
  **SHF** list and base + BytesPerRow in the **LOF** list — the reverse of MakeVPort/MrgCop. Probed (vp LACE
  2 planes, bpr 40, rx 16, ry 3): LOF `00E2 00A2`, SHF `00E2 007A` (base = $7A). The intermediate list,
  however, keeps MakeVPort's order: a later MrgCop restores the frames. [S]
- DUALPF: DDFSTRT is only patched in the LOF list. [O]
- Non-interlaced probed (rx 21, ry 5, bpr 80): DDFSTRT $30, BPLCON1 $BB, modulos $26, BPL1PT P0+$192. [S]

### 7.4 WaitTOF, WaitBOVP, VBeamPos [O][S]

- **WaitTOF**: node on the stack (ln_Name := FindTask(NULL)); Disable; SetSignal(0, SIGF_SINGLE);
  AddTail(TOF_WaitQ); Wait(SIGF_SINGLE); Remove; Enable. Returns just after the VBlank (probed: line
  **$0C** on return).
- **WaitBOVP(vp)**: **busy** wait (no signal) until VBeamPos() ≥ View.DyOffset (ActiView, without
  NULL test) + vp.DyOffset + DHeight, target capped at MaxDisplayRow − 1. The ROM's "vp LACE ⇒
  DHeight/2" test reads a **wrong byte** (high byte of ClrIns) and is never true in practice:
  in interlace the wait targets DHeight undivided lines. Probed: vp Dy 0 DH 100 → return at line $90;
  vp Dy 110 DH 80 → line $EA.
- **VBeamPos()**: `(VPOSR:VHPOSR read as a long >> 8) & $1FF` (V8 included). [O]

---

## 8. PAL/NTSC, genlock and real A500

### 8.1 Detections made at init [O]

- **Genlock**: BPLCON0 := $0102 (ERSY); if the vertical counter moves over a short interval, an external
  sync is present ⇒ system_bplcon0 := $0102, otherwise BPLCON0 := 0 and system_bplcon0 := 0.
- **PAL/NTSC**: by observing the beam: if VBeamPos exceeds **270** ($10E) ⇒ PAL (DisplayFlags 4),
  otherwise (after having gone above 100 then back below 50 without exceeding 270) ⇒ NTSC (1). The Agnus
  identifier is **not** read. ExecBase.VBlankFrequency := 50/60 accordingly.
- Dependent values: §1.8. Nothing else depends on the standard: InitView, DIW/DDF, WAIT positions
  are identical; only the end-of-frame line (MaxDisplayRow) and hence the capping of the WAITs
  and of WaitBOVP change.

### 8.2 NTSC probed [S]

Same probe with `ntsc_mode = 1`: DisplayFlags = **1**, MaxDisplayRow = **$105**, NormalDisplayRows =
**200**, NormalDPMX/Y = **$500/$44A**, VBlankFrequency = **60**; MaxDisplayColumn, MinDisplayColumn,
NormalDisplayColumns, MicrosPerLine, copinit, InitView (DyOffset **$2C** in NTSC too) and **all** the
copper lists are identical to PAL, **except** the capping: a 256-line ViewPort at Dy 0 (theoretical
bottom $12C) has its bottom WAIT capped at MaxDisplayRow − 1 = $104 → `… FFDF FFFE 0401 FFFE 0100
0200 FFFF FFFE` (PAL: `2C01`). No automatic adaptation of the height: it is up to the caller
(intuition) to use NormalDisplayRows.

### 8.3 What a real A500 will render differently from a tolerant emulator [D]

- **Agnus 8370/8371 (OCS)**: standard fixed by the chip (8371 PAL, 8370 NTSC); detection by the beam
  hence reliable. **8372A (ECS, A500 rev. 6+)**: 1.3 writes neither BEAMCON0 nor DIWHIGH; the writes of
  DIWSTRT/DIWSTOP restore the OCS behaviour, hence the same results.
- **OCS vertical window**: DIWSTOP V `$40` is interpreted as `$140` (implicit V8 = ¬V7) and DIWSTRT
  V `$05` as line 5 — hence the "always open" window; an emulator that ignores DIWSTOP's implicit V8
  would close the window at line $40.
- **Bitplane DMA cut by BPLCON0**: with 0 planes between two ViewPorts, the line displays COLOR00; the
  lead-in WAIT at −1/−2 gives the copper time to write colours and pointers during the
  previous line — in 6-plane LORES the copper is starved during the fetch, hence −2.
- **HIRES 5 planes** (accepted by MakeVPort): BPU = 5 in HIRES is illegal on OCS (inconsistent display).
- **DDFSTRT minimum $18** (MinDisplayColumn/2) and **DDFSTOP maximum $D8** (LORES) / $D4 (HIRES):
  OCS fetch limits; beyond them the real hardware no longer reads data (an emulator may continue).
- **Line 255**: the copper's vertical counter only has 8 bits; the WAIT `$FFDF` (h = $DE) is
  indispensable for any ViewPort extending beyond line 255 (PAL), and in HIRES 4 planes with maximal fetch the
  position $DE is never reached by the copper (stolen cycles), hence the fallback to DDFSTRT.
- **Addresses outside CHIP**: gb_SHFlist = ExecBase (slow RAM `$C0xxxx` on 512+512) is never read by the
  copper in non-interlace; on a real A500, a COP2LC ≥ $80000 would be folded into chip (limited address
  bits) — not to be "fixed" by reading elsewhere.
- **Interlace**: the LOF bit of VPOSR alternates at each frame on real hardware when BPLCON0.LACE = 1;
  the init forces a long frame (VPOSW bit 15). The two mechanisms (VBlank choosing from LOF, and
  crossed MOVE COP2LC at the end of the list) give the same result as long as they are consistent.

---

## 9. Open points

- **SprIns/ClrIns**: never built in the probed paths; their production (simple sprites,
  GELs) belongs to the "sprites and GELs" spec.
- **Exact priority order** between CopLists at an equal position when several UCopLists are chained in
  the same ViewPort: deduced from the head insertion (the last UCopList of the chain first), not probed.
- **ColorMap Flags** not initialised by GetColorMap: its value depends on the previous contents of the
  memory (0 in the probe); no known reader in V34.
- **LoadView(NULL)**: the list executed at copinit+$A0 depends on the order of the allocations at init (here
  the LCM buffer); on a machine where this buffer is not null, the copper would execute arbitrary
  data. Not probed outside the 512+512 configuration.
- **Genlock** and **NTSC detection on a forced PAL Agnus** (jumper/JP): not probed; the logic is
  described from the ROM.
- **Real delays** of WaitBOVP/ScrollVPort in interlace (undivided target): behaviour deduced from the
  ROM, only the non-interlaced variant has been measured.
- Behaviour of `MrgCop` when a View changes from LACE to non-LACE: the old SHFCprList is
  kept (not freed) — leak or later reuse, not probed.

## Clean-room review

Review of 2026-10-29.

- [x] No 68000 instruction sequence transcribed, no disassembly excerpt, no ROM routine
  address: the addresses cited are custom registers, RAM addresses of the probed run
  (`$420`, `$480`, `$C00276`…) or values of copper lists (**copper** instructions, data
  produced in RAM and observable, not 68000 code).
- [x] The computations of §4.4 (DIW/DDF/BPLCON1/modulo) and the merge of §5.2 are expressed as
  **functions of the inputs** (formulas and selection rules) and cross-checked by the probed vectors [S]; point
  of attention: their granularity is fine, a reimplementation must rely on the vectors of
  §4.4/§5.3 as an oracle rather than on the order of the steps.
- [x] ROM data reproduced (inventoried in `docs/audit/specs-review.md`): default colour table
  of 32 entries (§3, values returned by GetColorMap/GetRGB4, observable) and contents of copinit
  (§2, copper list in chip RAM, observable and on which programs depend, cf. `caesar-boot.md`).
- [x] The probe cited (`tests/gdisp_probe.s`) is author code.
