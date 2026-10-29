# intuition-screens-v34.md — intuition 34.3 screens: opening, closing, ordering, moving, Workbench

> **ANALYSIS** track ("dirty"). Sources: ROM `assets/kick34005.A500` (intuition 34.3, read-only,
> temporary disassembly outside the repository) and black-box probe `tests/iscr_probe.s` / `tests/iscr_probe.sh`
> run under FS-UAE with the real ROM (A500, 512 KB chip + 512 KB slow, PAL then NTSC, launched from the
> bootblock, hence **before** `devs:system-configuration`, with no Workbench loaded). **Behavioural**
> specification: structures read and written, values, order of operations, conditions. No instruction
> sequence is reproduced; no ROM routine address is quoted. The `$C0xxxx` addresses
> in the test vectors are **RAM** addresses from the probed run (examples).
>
> **Legend**: **[O]** observed in the binary (radare2, base `$FC0000`) · **[S]** black-box probed
> on the real ROM · **[D]** deduced (reasoning on [O]/[S], not executed).
>
> Complements without repeating them: `intuition-frame-v34.md` §6 (drawing of the screen bar),
> `intuition-prefs-v34.md` §1 and §3.3 (default font, colours, NormalDisplayRows/Columns),
> `graphics-display-v34.md` (MakeVPort/MrgCop/LoadView, stacked ViewPorts),
> `workbench-task-v34.md` §4 (Workbench side of CloseWorkBench).
>
> Notation: IB = IntuitionBase. IB offsets beyond the public fields (`$3C`…`$4F`) are
> **V34 internal state**, given to ease implementation and probing; only the public fields
> are an ABI that programs read. "Interlaced lines" (le, from French *lignes entrelacées*) = vertical unit in which
> intuition keeps MouseY: one non-interlaced line equals 2 le.

---

## 0. Short answer

- `OpenScreen` reads **32 bytes** of NewScreen (the NS_EXTENDED extension is ignored, bit `$1000` is
  copied as is into `Screen.Flags`). Only **Height = −1** is special (display height, doubled if
  LACE); **Width = −1 is not**. `LeftEdge` is stored but **has no display effect**
  (the ViewPort's DxOffset is forced to 0). [O][S]
- The new screen is put **at the head** of the list (`IB.FirstScreen`), or **at the tail** with SCREENBEHIND;
  its ViewPort is always put **at the head** of the intuition View's chain. `ActiveScreen` is **not**
  modified by OpenScreen. [O][S]
- Palette of a new screen (custom or Workbench): graphics' default table (GetColorMap(32)), whose
  colours **0–3 and 17–19 are replaced by those from Preferences**. [O][S]
- Vertical layout (RethinkDisplay): the front screen is always displayed over its full height;
  each following screen is clipped to end **3 (non-interlaced) lines above** the top of the screen
  preceding it, and **hidden (VP_HIDE)** if it starts at that level or lower. [O][S]
- `MoveScreen` uses **only dy**; TopEdge bounded to ≥ 0, **with no lower bound**. [O][S]
- `CloseScreen` **refuses nothing** (no test for open windows); if it was the **last screen**, it
  **reopens the Workbench**. `CloseWorkBench` refuses (FALSE) if there is a non-WBENCHWINDOW window on
  the WB screen, otherwise notifies the Workbench, closes the screen **without** reopening and returns TRUE. [O][S]
- `OpenWorkBench` returns the **screen pointer** (not a 0/1 boolean), and reopens nothing if the screen exists. [O][S]
- **Left** Amiga + N → `WBenchToFront`, left Amiga + M → `WBenchToBack`. [O]

---

## 1. ABI layouts

### 1.1 `struct NewScreen` — 32 bytes read [O]

| Off | Field | Size | Handling |
|---:|---|---|---|
| $00 | LeftEdge | W | → Screen.LeftEdge (no display effect, §2.4) |
| $02 | TopEdge | W | → Screen.TopEdge; ViewPort.DyOffset = max(TopEdge, 0) |
| $04 | Width | W | as is (−1 **not** handled) |
| $06 | Height | W | −1 ⇒ default height (§2.2) |
| $08 | Depth | W | number of planes allocated (no check) |
| $0A | DetailPen | B | → Screen +$14A |
| $0B | BlockPen | B | → Screen +$14B |
| $0C | ViewModes | W | → ViewPort.Modes, **OR SPRITES ($4000)** forced |
| $0E | Type | W | → Screen.Flags = Type **OR SHOWTITLE ($10)** |
| $10 | Font | L | TextAttr; NULL ⇒ IB's default TextAttr |
| $14 | DefaultTitle | L | → Screen.Title **and** Screen.DefaultTitle |
| $18 | Gadgets | L | chained **after** the system gadgets |
| $1C | CustomBitMap | L | read only if Type & CUSTOMBITMAP |

Type bits used: `$000F` screen type (1 = WBENCHSCREEN, $F = CUSTOMSCREEN), `$0040`
CUSTOMBITMAP, `$0080` SCREENBEHIND, `$0100` SCREENQUIET. No other bit is tested; `$1000`
(NS_EXTENDED) is simply copied into Flags [O][S: Flags = $101F for Type $100F].

### 1.2 `struct Screen` V34 — `$15A` = 346 bytes [O][S]

| Off | Field | Initial value set by OpenScreen |
|---:|---|---|
| $00 | NextScreen | IB chaining (§2.6) |
| $04 | FirstWindow | 0 |
| $08 | LeftEdge | NewScreen.LeftEdge |
| $0A | TopEdge | NewScreen.TopEdge |
| $0C | Width | NewScreen.Width |
| $0E | Height | resolved NewScreen.Height (§2.2) |
| $10 | MouseY | (IB.MouseY, ÷2 if the screen is not LACE) − TopEdge |
| $12 | MouseX | (IB.MouseX, ÷2 if the screen is not HIRES) − LeftEdge |
| $14 | Flags | Type OR $10 |
| $16 | Title | DefaultTitle |
| $1A | DefaultTitle | DefaultTitle |
| $1E | BarHeight (B) | 2 × BarVBorder + ta_YSize of the selected TextAttr |
| $1F | BarVBorder (B) | 1 |
| $20 | BarHBorder (B) | HIRES 5 · non-HIRES 2 |
| $21 | MenuVBorder (B) | HIRES 2 · non-HIRES 4 |
| $22 | MenuHBorder (B) | 4 |
| $23 | WBorTop (B) | 2 |
| $24 | WBorLeft (B) | 4 |
| $25 | WBorRight (B) | 4 |
| $26 | WBorBottom (B) | 2 |
| $27 | (padding) | 0 |
| $28 | Font | pointer to the **selected TextAttr** (the caller's or IB's) |
| $2C | ViewPort (40) | §2.3 |
| $54 | RastPort (100) | InitRastPort, BitMap = &Screen.BitMap, font set (§2.5) |
| $B8 | BitMap (40) | InitBitMap(Depth, Width, Height) or copy of CustomBitMap |
| $E0 | LayerInfo (102) | InitLayers + FattenLayerInfo |
| $146 | FirstGadget | system gadgets (§4) then NewScreen.Gadgets |
| $14A | DetailPen (B) | NewScreen.DetailPen |
| $14B | BlockPen (B) | NewScreen.BlockPen |
| $14C | SaveColor0 (W) | 0 (will be used by DisplayBeep) |
| $14E | BarLayer | bar layer (§3.1) |
| $152 | ExtData | 0 |
| $156 | UserData | 0 |

The "HIRES / non-HIRES" choice for the borders is made on `ViewModes & $8000`. The values come from
two byte tables in IB (§1.3), indexed 0 = HIRES, 1 = otherwise. [O][S]

`Screen.Flags` bits managed by intuition: `$0010` SHOWTITLE (set on opening, ShowTitle),
`$0020` BEEPING (DisplayBeep in progress; SaveColor0 keeps the original colour 0). [O]

### 1.3 Relevant IntuitionBase fields [O][S]

| IB | Contents |
|---:|---|
| $22 | intuition's View (ViewLord, 18 bytes): ViewPort, LOFCprList, SHFCprList, DyOffset, DxOffset, Modes |
| $34 | ActiveWindow |
| $38 | ActiveScreen |
| $3C | FirstScreen |
| $40 | Flags (equals `$1000` after the first opening, cf. intuition-prefs §1) |
| $44 / $46 | MouseY / MouseX (le / hires pixels) |
| $50 / $52 | pointer X min / max bound |
| $54 / $56 | pointer Y min / max bound |
| $33E…$34D | default border tables, pairs (HIRES, other): WBorLeft (4,4), WBorTop (2,2), WBorRight (4,4), WBorBottom (2,2), BarVBorder (1,1), BarHBorder (5,2), MenuVBorder (2,4), MenuHBorder (4,4) |
| $35C | default TextAttr (topaz 8 or 9, intuition-prefs §3.3) |
| $378 | top (le) of the highest visible screen (§5.3) |
| $3A8 | Workbench port (set by AlohaWorkbench) |
| $3AC / $3B0 | reply port and message from intuition to the Workbench (§7.4) |
| $400 | 7 SignalSemaphores of $2E bytes: lock n at IB + $400 + n × $2E |
| $542 / $544 / $546 | 2 × NormalDisplayRows, that number − 1, NormalDisplayColumns |

Locks (LockIBase numbering): 0 = intuition state (ISTATELOCK), 4 = view (VIEWLOCK),
5 = IntuitionBase (IBASELOCK); the others (1–3, 6) are not used for screens. [O]

At library init: FirstScreen = 0, View initialised by InitView (null ViewPort), Modes = `$4000`
at the time of the probe. [S: T0]

---

## 2. OpenScreen(newscreen) — LVO −198

### 2.1 Order of operations [O]

Everything is done under **lock 0** (taken at the start, released at the end, including on failure). The
allocations go through a **local Remember list** (AllocRemember), forgotten without freeing on
success, freed on failure.

1. Reading of the fields; if Height = −1, resolution (§2.2).
2. Allocation of the Screen: 346 bytes, MEMF_PUBLIC|MEMF_CLEAR. Failure ⇒ returns 0.
3. Allocation of a RasInfo: 12 bytes, MEMF_PUBLIC|MEMF_CLEAR. Failure ⇒ 0.
4. `GetColorMap(32)`. Failure ⇒ 0.
5. Fields Width, Height, LeftEdge, TopEdge, Flags, DetailPen, BlockPen (§1.2).
6. `InitLayers(&LayerInfo)`, `FattenLayerInfo(&LayerInfo)`.
7. `InitVPort(&ViewPort)` then: ColorMap, DxOffset = 0, DyOffset = TopEdge if ≥ 0 otherwise 0,
   DWidth = Width, DHeight = Height, Modes = ViewModes | SPRITES.
8. **The ViewPort is chained at the head** of intuition's View (vp.Next = View.ViewPort;
   View.ViewPort = vp), regardless of SCREENBEHIND.
9. BitMap:
   - CUSTOMBITMAP: copy of the 40 bytes of *CustomBitMap into Screen.BitMap (the structure is
     copied, the planes remain the caller's);
   - otherwise `InitBitMap(&BitMap, Depth, Width, Height)` then, for each plane,
     AllocRemember of `((Width + 15) >> 3 & $FFFE) × Height` bytes in **MEMF_CHIP|MEMF_PUBLIC
     (without CLEAR)**. Failure of one plane ⇒ overall failure.
10. `InitRastPort(&RastPort)`; RastPort.BitMap = &Screen.BitMap.
11. System gadgets (§4); allocation failure ⇒ overall failure. Then NewScreen.Gadgets is hooked
    **at the end** of the list.
12. Font (§2.5); Screen.Font = selected TextAttr.
13. For each **proportional** gadget in the list: if PropInfo.Flags has PROPBORDERLESS ($08),
    LeftBorder = TopBorder = 0; otherwise LeftBorder = WBorLeft, TopBorder = WBorTop of the screen.
14. BarVBorder…WBorBottom then BarHeight (§1.2).
15. Screen.MouseX/MouseY (§1.2).
16. Without CUSTOMBITMAP: `SetRast(&RastPort, 0)` — this is what clears the planes. With CUSTOMBITMAP,
    the caller's contents are kept.
17. Bar layer: `CreateUpfrontLayer(&LayerInfo, &BitMap, 0, 0, Width − 1, BarHeight,
    LAYERSIMPLE|LAYERBACKDROP)` → Screen.BarLayer. Failure ⇒ overall failure. Font set on the
    RastPort of this layer (second OpenFont of the same TextAttr).
18. Title = DefaultTitle = NewScreen.DefaultTitle.
19. RasInfo.BitMap = &Screen.BitMap; if ViewModes & DUALPF ($400), a **second RasInfo** of 12 bytes
    (empty: null BitMap) is allocated and chained in RasInfo.Next — up to the caller to fill it.
20. vp.RasInfo = RasInfo.
21. Under Forbid: SCREENBEHIND ⇒ screen added **at the tail** of the IB list; otherwise **at the head**
    (Next = FirstScreen, FirstScreen = screen).
22. Drawing of the bar (intuition-frame §6); `RemakeDisplay()` (§5.2); recomputation of the
    pointer bounds (§5.3).
23. FreeRemember(key, FALSE) (the list is forgotten, the memory stays).
24. **Preferences colours**: SetRGB4 of colours 0–3 (IB prefs colours 0–3) and 17–19 (pointer
    colours) on the screen's ViewPort — **for every screen**, not just the Workbench.
25. Returns the screen pointer.

Failure from step 9 onwards: the ViewPort is unhooked from the View, then FreeRemember(key, TRUE).
**Not freed**: the ColorMap, the LayerInfo fattening, any fonts that were
opened. No RemakeDisplay. [O] (a V34-specific leak; no need to reproduce it [D]).

### 2.2 Height = −1 [O][S]

- Without LACE in ViewModes: Height = IB+$542 / 2 = **NormalDisplayRows** (256 PAL, 200 NTSC).
- With LACE ($0004): Height = IB+$542 = **2 × NormalDisplayRows** (512 PAL, 400 NTSC).
- Width = −1 is not handled: a width of −1 would give planes of 0 bytes per line [D]. The
  Workbench does not go through this path: it sets its own width (§7.1).
- Probed PAL: S1 (lores, −1) ⇒ Height 256; S2 (HIRES|LACE, −1) ⇒ 512. [S]

### 2.3 ViewPort, View and interlaced mode [O][S]

- vp.Modes = ViewModes | `$4000`. Probed examples: WB `$C000`, lores screen `$4000`, HIRES|LACE `$C004`.
- intuition's View **never** has a screen-specific mode except **LACE**, set or cleared globally
  (§5.1). The View's DxOffset/DyOffset come from Preferences (intuition-prefs §3.3 step 5);
  probed PAL at boot: Dy `$2C`, Dx `$81`.
- The `SpritePriorities` field (+$22 of the ViewPort) is `$24` (graphics' InitVPort). [S]

### 2.4 LeftEdge [O][S]

LeftEdge is stored in the Screen and enters the computation of Screen.MouseX, but the ViewPort always
receives **DxOffset = 0** and **MoveScreen ignores dx**: a 1.3 screen never shifts horizontally.
Probed: LeftEdge 7 ⇒ vp.DxOffset 0, Screen.MouseX = −7 with the pointer at 0.

### 2.5 Font [O][S]

1. Candidate TextAttr = NewScreen.Font, or failing that IB's TextAttr (+$35C).
2. `OpenFont(candidate)` (graphics only: **no diskfont**). On success: SetFont on the screen's
   RastPort then `SetSoftStyle(rp, ta_Style, $FF)`.
3. On failure: same operation with IB's TextAttr (assumed always openable).
4. Screen.Font = the selected TextAttr (pointer to the **caller's** structure if it succeeded:
   it must therefore remain valid for the lifetime of the screen).
5. BarHeight is computed from the **requested ta_YSize** of the selected TextAttr (not from tf_YSize).
6. The font is reopened (second OpenFont) for the BarLayer's RastPort.

Probed at bootblock time (before system-configuration, default FontHeight 9): font topaz 9, BarHeight
**11** for the WB and screens without Font; RastPort.TxHeight 9, TxWidth 10, TxBaseline 6. Font
not found (`nonexist.font`) ⇒ fallback to IB's TextAttr. With the WB 1.3 system-configuration
(FontHeight 8) the bar is **10** [D, consistent with intuition-frame: BT = 10 measured].
Supplied TextAttr topaz 8 (probed, S2): accepted, **Screen.Font = caller's pointer**, BarHeight
**10**, BarLayer (0,0)–(639,10), TxHeight 8, TxWidth 8. [S]

### 2.6 Order in the list and active screen [O][S]

- Normal screen ⇒ head of the list; SCREENBEHIND ⇒ tail (probed: S2 BEHIND behind the WB).
- The ViewPort is **always** chained at the head of the View: the order of the ViewPort chain is
  **not** the order of the screens (probed: chain S3, S2, S1, WB while the screen list is
  S3, S1, WB, S2). This is not a problem: graphics merges by vertical position.
- ActiveScreen unchanged by OpenScreen (probed: stays the WB after opening S1, S2, S3). It is
  modified by activating a window (ActiveScreen = the window's screen, and Screen.Title =
  Window.ScreenTitle if different, then the bar is redrawn), by OpenWorkBench (§7.1) and by
  CloseScreen of the active screen (§6.1).

### 2.7 Default palette [O][S]

Colours read back with GetRGB4 on a new screen (WB or custom, identical), default Preferences:

```
 0-15 : 05A FFF 002 F80 00F F0F 0FF FFF 620 E50 9F1 EB0 55F 92F 0F8 CCC
16-31 : 000 D22 000 FCA 444 555 666 777 888 999 AAA BBB CCC DDD EEE FFF
```

0–3 and 17–19 = Preferences (blue, white, black, orange; pointer D22/000/FCA); the rest = graphics'
default table. A 1-plane screen only displays 0–1, etc. After SetPrefs, only the colours of the
**Workbench** screen are updated (intuition-prefs §3.3); custom screens keep the
prefs colours from when they were opened.

---

## 3. Screen title bar

### 3.1 Layer [O][S]

- BarLayer = **LAYERSIMPLE | LAYERBACKDROP** layer (Flags `$41`), bounds (0, 0)–(Width − 1,
  **BarHeight**): it covers **BarHeight + 1** lines (probed: MaxY = 11 for BarHeight 11).
- Being BACKDROP, non-backdrop windows go in front of it; the bar is in front of BACKDROP
  windows as long as SHOWTITLE is set (§3.2).
- Drawing: intuition-frame §6 (BlockPen background, Title in DetailPen/BlockPen JAM2 at
  (BarHBorder, BarVBorder), screen gadgets). Nothing is drawn for a SCREENQUIET screen nor for
  a screen absent from the list.

### 3.2 ShowTitle(screen, flag) — LVO −282 [O][S]

- flag ≠ 0: Flags |= SHOWTITLE; under LockLayerInfo, the BarLayer loses BACKDROP, goes **in front of everything**
  (UpfrontLayer), then **BehindLayer** (it then sits behind the normal windows but in front of
  the backdrop ones), then gets BACKDROP back; then the bar is redrawn.
- flag = 0: Flags &= ~SHOWTITLE; BACKDROP set, BehindLayer ⇒ the bar goes **behind all
  layers**, including backdrop windows (which then hide it).
- In both cases, a deferred request "repair the damaged windows of this screen" is
  posted in intuition's queue (processed at the next input event: REFRESHWINDOW for
  SIMPLE_REFRESH windows, repair for the others).
- Probed: Flags $101F → $100F → $101F; the layer keeps Flags `$41`.

### 3.3 Displayed title [O]

- OpenScreen: Title = DefaultTitle.
- OpenWindow: Window.ScreenTitle = Screen.DefaultTitle.
- Activation of a window: if Screen.Title ≠ Window.ScreenTitle, Screen.Title = Window.ScreenTitle
  and the bar is redrawn. **Deactivation restores nothing.**
- `SetWindowTitles(win, wtitle, stitle)` screen side: if stitle ≠ −1, Window.ScreenTitle = stitle;
  **only if the window is active** (Window.Flags & $2000), Screen.Title = stitle and the bar is
  redrawn. stitle = 0 ⇒ bar **without text** (no fallback to DefaultTitle). Window side
  (wtitle ≠ −1): Window.Title = wtitle, the window's bar is redrawn, then rendered "inactive" if
  it is not active.

---

## 4. Screen system gadgets [O][S]

Created on opening, always **three**, in this order, copied from internal templates (44 bytes each,
allocated in the Remember list; images copied to CHIP):

| # | GadgetType | Role | HIRES (L, T, W, H) | non-HIRES (L, T, W, H) | Flags | Activation |
|--:|---|---|---|---|---|---|
| 1 | `$C050` SUPFRONT | screen to front | −28, 0, 26, 10 | −16, 0, 17, 10 | `$14` GRELRIGHT\|GADGIMAGE | `$01` RELVERIFY |
| 2 | `$C070` SDOWNBACK | screen to back | −52, 0, 24, 10 | −33, 0, 17, 10 | `$14` | `$01` |
| 3 | `$C030` SDRAGGING | dragging | 0, 0, 0, 10 | 0, 0, 0, 10 | `$23` GRELWIDTH\|GADGHNONE | 0 |

- The drag gadget covers the whole width (relative width 0) and **a fixed 10 lines**, even
  when BarHeight is 11 (font 9). The depth gadgets, placed before it in the list,
  are found first by the hit test [D].
- SCREENQUIET: the three gadgets still exist, but GadgetRender = 0 and Flags |= GADGHNONE
  (probed: Flags `$17`, no rendering).
- The gadgets of NewScreen.Gadgets follow the third one (probed: user gadget in 4th position,
  unmodified).
- CloseScreen frees (FreeMem of 44 bytes) **all gadgets in the list that have SYSGADGET ($8000)**
  and leaves the others to the caller.

---

## 5. Display layout

### 5.1 Global interlaced mode [O][S]

The screens are walked in list order, with a limit L (le) starting from 2 × NormalDisplayRows:
for each screen, top = TopEdge (×2 if the screen is not LACE); if top < L, the screen is
"visible": if it is LACE, the View must be LACE; then L = top − 6. View.Modes gains or loses
**LACE ($4)** depending on whether **at least one visible screen** is LACE. Probed: a LACE screen hidden behind the WB
leaves View.Modes at `$4000`.

### 5.2 MakeScreen, RemakeDisplay, RethinkDisplay [O][S]

- **MakeScreen(s)** (−378): lock 4; recomputation of global LACE (§5.1); `MakeVPort(&View, &s.ViewPort)`;
  releases the lock. **Neither MrgCop nor LoadView**: the caller must do RethinkDisplay.
- **RemakeDisplay()** (−384): lock 4; global LACE; `MakeVPort` of **each ViewPort in the View's
  chain**; releases the lock; then RethinkDisplay.
- **RethinkDisplay()** (−390): lock 5, then:
  1. **layout** (below), which redoes MakeVPort (via MakeScreen) only for the screens whose
     displayed height changes, or for all visible ones if global LACE has just changed;
  2. under lock 4: saves the View's LOFCprList and SHFCprList, **sets them to 0**, `MrgCop(&View)`
     (hence **new** lists), `LoadView(&View)`, `WaitTOF()`, then writes **DMACON = $8100** (BPLEN)
     and **DMACON = $8020** (SPREN), then `FreeCprList` of the two old lists;
  3. releases lock 5.

Layout (step 1), with h(s) = TopEdge (×2 if the screen is not LACE) in le:
- L = h(first) + Height of the first (×2 if not LACE) — so **the front screen is always whole**;
- for each screen, in list order: if h < L: VP_HIDE ($2000) cleared;
  lines = (L − h), ÷2 if not LACE, **capped at Height**; if DHeight ≠ lines (or global LACE changed),
  DHeight = lines and MakeScreen; then **L = h − 6**. Otherwise: VP_HIDE set (DHeight unchanged).
- At the end: IB+$378 = L + 6 (top of the last visible screen, i.e. the highest on the display); if
  no drag/menu is in progress (bits `$600` of IB.Flags at 0), pointer Y min bound = IB+$378.

Consequence: between a screen and the one in front of it there remain **3 empty non-interlaced lines**
(6 le), which satisfies graphics' requirement of at least one empty line (graphics-display §5.4).

Probed vectors (PAL, WB 640×256 behind S1 lores 320×256):

| S1.TopEdge | WB DHeight | WB Modes | S1 DHeight |
|---:|---:|---|---:|
| 40 | 37 | `$C000` | 256 |
| 100 | 97 | `$C000` | 256 |
| 0 | 97 (unchanged) | `$E000` (hidden) | 256 |
| 300 | 256 (capped at Height) | `$C000` | 256 |
| S1 behind the WB, TopEdge 100 | 256 | — | 256, `$6000` (hidden) |
| S3 (Top 150, H 50) in front of S1 (Top 100) | — | — | S1: 47 |

### 5.3 Pointer bounds [O][S]

Recomputed after OpenScreen, CloseScreen, ScreenToFront/Back, and at the end of a drag:
- X: [0, NormalDisplayColumns − 1] (probed 0…$27F);
- Y min: IB+$378 (top of the highest visible screen; the pointer **cannot go up** into the
  empty area above the screens);
- Y max: min(2 × NormalDisplayRows − 1, bottom of the **front screen** − 1) in le (probed: $1FF with the WB
  in front; **$18F** = (150 + 50) × 2 − 1 with S3 in front).

---

## 6. Closing

### 6.1 CloseScreen(screen) — LVO −66 [O][S]

Under lock 0. **No refusal**: neither a FirstWindow test, nor a check that the screen is in the
list; no useful return value (void in V34). Order:

1. If screen = ActiveScreen: deferred request "activate (null window, null screen)" ⇒ the active
   window is deactivated and ActiveScreen = 0 at the next input event.
2. ViewPort unhooked from the View; screen unhooked from the IB list.
3. CloseFont of the font of the screen's RastPort and of the BarLayer's.
4. DeleteLayer of the BarLayer.
5. Freeing of the SYSGADGET gadgets (§4).
6. Without CUSTOMBITMAP: WaitBlit, then FreeMem of each plane (size recomputed from
   BytesPerRow × 8, Rows, Depth of Screen.BitMap).
7. FreeColorMap, FreeVPortCopLists(&vp), FreeMem of the second RasInfo if it exists then of the first (12).
8. ThinLayerInfo(&LayerInfo); FreeMem(screen, 346).
9. Under Forbid: if the list is empty, ActiveScreen = 0 and **OpenWorkBench()** (automatic
   reopening); Permit.
10. If the list is not empty: RemakeDisplay. Then recomputation of the pointer bounds.

Windows still open: their layers and structures are **not** freed and point to a freed
Screen — undefined behaviour [D]. Probed: opening then closing a custom screen when it is
alone ⇒ a new Workbench screen appears (T10).

### 6.2 CloseWorkBench() — LVO −78 [O][S]

1. Looks for the first screen in the list whose Flags & $F = WBENCHSCREEN; absent ⇒ **FALSE**.
2. Walks its windows: a single window **without WBENCHWINDOW** (Window.Flags & $02000000) ⇒
   **FALSE** (refusal, nothing is done).
3. **WBENCHCLOSE** message to the Workbench and synchronous wait for the reply (§7.4) — only if a
   Workbench has registered (AlohaWorkbench).
4. Closing of the screen like CloseScreen **without** the reopening step (and without taking
   lock 0); **TRUE**.

The presence of windows is **not** rechecked after the Workbench's reply: if the latter has not
closed its windows, the screen is closed anyway [O]. If the WB screen was the only one, the View keeps its
old copper lists (no RemakeDisplay when the list is empty) [O][S: View.ViewPort = 0,
LOFCprList non-null]. Probed: CloseWorkBench without a window ⇒ 1 then 0 on the second call.

---

## 7. Workbench

### 7.1 Default Workbench screen [O][S]

Internal NewScreen: LeftEdge 0, TopEdge 0, Width **NormalDisplayColumns** (IB+$546), Height −1,
Depth **2**, DetailPen **0**, BlockPen **1**, ViewModes **HIRES ($8000)**, OR **LACE** if
Preferences.LaceWB (bit 0 of byte +$B9), Type WBENCHSCREEN (1), Font = IB's TextAttr,
DefaultTitle **"Workbench Screen"**, neither gadgets nor bitmap.

| Video | Probed / deduced size |
|---|---|
| PAL | 640 × 256 (LACE: 640 × 512) [S] |
| NTSC | 640 × 200 (LACE: 640 × 400) [S] |

After OpenScreen: deferred request "activate (null window, this screen)" ⇒ **ActiveScreen = WB** at the
next input event (probed); reload of the prefs colours on the WB; pointer bounding.
Probed Flags `$0011`, BarHeight 11 (topaz 9), Title = DefaultTitle = "Workbench Screen".

### 7.2 OpenWorkBench() — LVO −210 [O][S]

- If a WBENCHSCREEN screen exists: returns it as is (no second screen, no message).
- Otherwise: opens the default screen (§7.1). Failure ⇒ 0. Success ⇒ **WBENCHOPEN** message to the Workbench
  if it has registered (§7.4), then returns the **screen pointer**.
- Probed: two successive calls return the same pointer `$C04AD0`.
- OpenWindow on WBENCHSCREEN goes through the same find-or-open; for another non-existent system
  screen type, intuition raises the dead-end alert **$84000009** (AN_SysScrnType). [O]

### 7.3 WBenchToFront / WBenchToBack (−342 / −336) and Amiga-N / Amiga-M [O][S]

- They look for the WB screen; absent ⇒ **FALSE**; otherwise ScreenToFront / ScreenToBack of that screen and
  **TRUE** (probed: 1 and 1). WBenchToFront does not take lock 0 (ScreenToFront does).
- Keyboard (intuition input handling): RAWKEY event with qualifier
  **IEQUALIFIER_LCOMMAND ($40)** and code **$36 (N)** ⇒ WBenchToFront, **$37 (M)** ⇒ WBenchToBack;
  the event is consumed. With **right** Amiga alone, N/M follow the menu shortcut path.

### 7.4 Messages to the Workbench [O]

If IB+$3A8 (port registered by AlohaWorkbench) is non-null: the first time, a reply port
named "WBenchPort" is created (IB+$3AC); on each send, AllocSignal(−1) for that port, SigTask =
current task, message embedded in IB (IB+$3B0, IntuiMessage form) with **Class = $00020000
(WBENCHMESSAGE)** and **Code = 1 (WBENCHOPEN) or 2 (WBENCHCLOSE)**; PutMsg to the Workbench, **Wait**
for the signal, GetMsg, FreeSignal. The caller is blocked until the reply.

### 7.5 GetScreenData(buffer, size, type, screen) — LVO −426 [O][S]

- type = CUSTOMSCREEN ($F): screen = argument; type = WBENCHSCREEN (1): screen = **OpenWorkBench()**
  (the WB is **opened** if it was not); other type: nothing.
- Null screen ⇒ **FALSE**. Otherwise copy of **min(size, 346)** bytes of the Screen into buffer ⇒ **TRUE**.
- Probed: size 400 ⇒ nothing is written beyond 346; type 2 ⇒ 0; WB closed ⇒ reopened, 1.

---

## 8. Depth and movement

### 8.1 ScreenToFront(s) / ScreenToBack(s) — LVO −252 / −246 [O][S]

- ScreenToFront: lock 0, lock 5; unhooks s; **s at the head**; releases lock 5; RethinkDisplay;
  pointer bounds; releases lock 0.
- ScreenToBack: lock 5; unhooks; **s at the tail**; releases lock 5; RethinkDisplay; bounds.
- No effect on ActiveScreen nor on the ViewPort chain (only DHeight and VP_HIDE change).
- Screen gadgets: a validated click on `$C050` ⇒ ScreenToFront(screen), on `$C070` ⇒ ScreenToBack.

### 8.2 MoveScreen(s, dx, dy) — LVO −162 [O][S]

- **dx ignored**.
- If TopEdge + dy ≥ 0: TopEdge += dy. Otherwise, if TopEdge > 0: TopEdge = 0. Otherwise (TopEdge ≤ 0): nothing.
- **No lower bound** (probed: TopEdge 300 accepted on a 256-line display).
- vp.DyOffset = TopEdge (0 if negative); then **RethinkDisplay** (copper lists rebuilt on every call).
- No lock of its own apart from those of RethinkDisplay.

### 8.3 Dragging by the bar [O]

A click on the SDRAGGING gadget (the whole bar except the depth gadgets) starts the
"screen dragging" state:
- pointer bounds: X frozen (min = max = current MouseX); Y min = MouseY − top of the screen (le), so
  that TopEdge cannot become negative; Y max = 2 × NormalDisplayRows − 1: the grabbed point can
  go down to the bottom of the display (the screen can almost disappear off the bottom);
- on each event where MouseY changes: delta = MouseY − previous (le); for a non-LACE screen,
  delta is converted to lines (+1 if MouseY is even, then division by 2 rounded towards −∞);
  **MoveScreen(screen, 0, delta)** ⇒ the display is rebuilt live on every movement;
- SELECTUP (RAWMOUSE code $E8): end of the state; normal bounds recomputed (§5.3).

Hit test across screens: the screens are walked in list order, VP_HIDE ones ignored;
WhichLayer at (Screen.MouseX, Screen.MouseY); a layer found ⇒ window (or screen bar,
whose gadgets are then tested); otherwise, if the pointer is below the top of this screen, the search
stops on "nothing". [O]

### 8.4 Double click on the bar [O]

No handling: DoubleClick is only used internally for the menu button double click
(SetDMRequest). A double click on the screen bar gives two ordinary drag starts.

---

## 9. Other functions

- **ViewAddress()** (−294): returns **&IB->ViewLord** (IB + $22) [O][S: `$C03D46` = IB + $22].
- **ViewPortAddress(win)** (−300): returns **&win->WScreen->ViewPort** (Screen + $2C) [O].
- **LockIBase(n)** (−414): n = 0 ⇒ takes lock 0 **then** lock 5; otherwise lock n. Returns n.
  **UnlockIBase(n)** (−420): n = 0 ⇒ releases 5 then 0; otherwise n. The locks are
  SignalSemaphores (reentrant for the same task) [O].
- **DisplayBeep(screen)** (reminder): sets BEEPING, saves colour 0 in SaveColor0 and inverts it;
  restoration happens at the next intuition tick for all BEEPING screens [O].

---

## 10. Test vectors (probe `tests/iscr_probe.sh`, real ROM, PAL) [S]

Launched from the bootblock (no screen at the start):

| Step | Observation |
|---|---|
| T0 | FirstScreen 0, ActiveScreen 0, IB.Flags `$1000`, View: ViewPort 0, Dy `$2C`, Dx `$81`, Modes `$4000`; IB+$542/$544/$546 = 512/511/640 |
| OpenWorkBench ×2 | `$C04AD0` twice; after ~0.6 s ActiveScreen = WB |
| WB | 640 × 256, Flags `$0011`, bytes $1E–$26 = `0B 01 05 02 04 02 04 04 02`, Font = IB+$35C, BitMap 80 B/line, 2 CHIP planes, vp.Modes `$C000`, BarLayer (0,0)–(639,11) Flags `$41`, DetailPen 0, BlockPen 1 |
| S1 = {7, 40, 320, −1, 3, 2, 3, 0, `$100F`, NULL} | Height 256, Flags `$101F`, bytes $1E–$26 = `0B 01 02 04 04 02 04 04 02`, vp Dx 0 Dy 40, lores gadgets (−16/17, −33/17, 0/0), MouseX −7 |
| MoveScreen(S1, 50, 60) | TopEdge 100, LeftEdge 7 (dx ignored) |
| MoveScreen(S1, 0, −500) | TopEdge 0, WB hidden (`$E000`) |
| MoveScreen(S1, 0, +300) | TopEdge 300, WB DHeight 256 |
| ScreenToBack(S1) / ScreenToFront(S1) | lists WB,S1 then S1,WB; S1 hidden behind (`$6000`) |
| WBenchToFront / WBenchToBack | 1 / 1 |
| S2 = {0, 20, 640, −1, 1, 0, 1, `$8004`, `$018F`} | Height 512, at the tail, hidden, vp.Modes `$E004`, View.Modes stays `$4000`, gadgets Flags `$17` with no rendering |
| S3 CUSTOMBITMAP 320×50×2, Top 150, + 1 gadget | Flags `$005F`, BitMap copied, user gadget 4th; Y max bound `$18F` |
| GetScreenData(400, CUSTOM) / (20, WB) / (20, type 2) | 1 (346 B copied) / 1 / 0 |
| CloseScreen S3, S2, S1 | WB alone, DHeight 256 |
| CloseWorkBench ×2 | 1 then 0; FirstScreen 0, ActiveScreen 0 |
| GetScreenData(WB) screen closed | 1, WB reopened and active |
| OpenScreen + CloseScreen of a lone screen | WB reopened automatically |

NTSC (same probe, `ntsc`): IB+$542/$544/$546 = 400/399/640; WB 640 × 200; S1 Height −1 ⇒ 200;
S2 HIRES|LACE ⇒ 400; Y max bound `$18F`; View Dy `$2C` Dx `$81`. TextAttr topaz 8 supplied for S2 ⇒
Screen.Font = that TextAttr, BarHeight 10; `nonexist.font` for S3 ⇒ Screen.Font = IB+$35C,
BarHeight 11. Return values identical to PAL (OpenWorkBench ×2, WBenchToFront/Back, GetScreenData,
CloseWorkBench).

Final capture (S1 lores 3 planes at Top 100 in front of the WB): S1's bar in BlockPen 3 (orange) with
its two depth gadgets, WB visible above.

---

## 11. Open points

1. **Real A500 NTSC/PAL**: only FS-UAE values were probed; the View keeps Dy `$2C`, Dx
   `$81` in NTSC as in PAL at bootblock time (graphics values + default prefs).
2. **Screen wider than the display** or narrower: intuition does nothing special (DWidth =
   Width); clipping is graphics' business (graphics-display §4.4). Not probed here.
3. **DUALPF**: the empty second RasInfo is handed to MakeVPort by OpenScreen's RemakeDisplay before
   the caller has had a chance to fill it; exact effect (reading a null BitMap) not probed.
4. **Drag rounding** for non-LACE screens (§8.3): described from the code, not measured
   with a real mouse.
5. **Width = −1**: deduced behaviour (planes of 0 bytes, layer of width −2), not probed; not to be
   imitated, no serious 1.3 program should pass it.
6. Bits `$600` of IB.Flags (screen drag / menus) that freeze the Y min bound: their exact meaning
   belongs to the "input engine" spec (no. 5 of coverage-v34).
7. Windows left open at CloseScreen: undefined behaviour, not probed.

---

## Clean-room review

- [x] No instruction sequence copied or paraphrased: only effects, orders of
  operations at the level of public library calls, conditions and values.
- [x] No ROM routine address; only structure offsets (ABI and IB internal state)
  and example RAM addresses from the probe.
- [x] No bitmap transcribed (the depth gadget images are described in intuition-frame).
