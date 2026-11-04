# intuition-gadgets-v34.md — gadget list functions (intuition 34.3)

> ANALYSIS track ("dirty"). Sources: black-box probes `tests/glist_probe.s` (harness `tests/glist_probe.sh`) and
> `tests/reqg_probe.s` (harness `tests/reqg_probe.sh`: requester gadgets, removed system gadget), both on Amiberry
> A500 with the real ROM `assets/kick34005.A500`, run on 2026-11-04; ROM reading of the eight LVO entries and
> of the list helpers they share (behaviour only), the 1.3 `.fd` and the AutoDocs.
> Functions: AddGadget (−42), RemoveGadget (−228), RefreshGadgets (−222), OffGadget (−174), OnGadget (−186),
> RefreshGList (−432), AddGList (−438), RemoveGList (−444). All eight exist in V34 (V33 for the last three).
>
> **Legend**: **[O probe]** observed with the probe on the real ROM · **[O ROM]** observed by reading the ROM, not
> probed · **[AutoDoc]** public documentation · **[D]** deduced · **[S]** assumed.
> No ROM address, no instruction listing, no transcription of a routine.

Related pages: the rendering routine every refresh goes through (backward drawing, highlight pass, requester
range rule) is `intuition-gzz-v34.md` §6.1–§6.2; ghosting of GADGDISABLED is §6.4 of the same page; system gadgets
(creation, order, types) are `intuition-frame-v34.md` §5; PropInfo LeftBorder/TopBorder are
`intuition-prop-v34.md` §1.

Public structure fields used: `Window.FirstGadget` +$3E, `Window.FirstRequest` +$24, `Window.WScreen` +$2E;
`Requester.ReqGadget` +$10; `Gadget.NextGadget` +$00, `Flags` +$0C, `GadgetType` +$10, `SpecialInfo` +$22;
`Screen.WBorTop` +$23, `WBorLeft` +$24; `PropInfo.Flags` +$00, `LeftBorder` +$12, `TopBorder` +$14.

---

## 1. Common rules

### 1.1 What a "list" is, and positions

- A window's gadget list starts at `Window.FirstGadget`. After OpenWindow it holds the **system gadgets at the
  head**, then the NewWindow gadgets ([O probe] step 0: a window with WINDOWDEPTH, WINDOWCLOSE and WINDOWDRAG
  starts with types $8040, $8060, $8080, $8020 in that order, as `intuition-frame-v34.md` §5.1 says).
- **Positions count every gadget of the list, system gadgets included**, from 0 at the head [O probe]. AddGadget
  at position 2 in the list `F s40 s60 s80 s20 E` puts the gadget **between the two depth gadgets**; nothing
  protects the system gadgets from an insertion or a removal [O probe, steps 3 and 5].
- A requester list starts at `Requester.ReqGadget` and is counted the same way, from its own first gadget
  [O probe, reqg steps 1, 2 and 7: AddGList at 0 returns 0, RemoveGList of the second requester gadget returns 1,
  AddGList at −1 on a list of 2 returns 2; the window list is untouched in all three].
- A position that is **negative** (any negative value, not only −1) or **not smaller than the length** of the list
  means "at the end" [O probe for −1 and 100; O ROM for other negative values].

### 1.2 Counts (`numgad`) — two different conventions

- **Add and remove** (AddGList, RemoveGList): the range is "the `numgad` gadgets starting at `gad`, or fewer if
  the chain ends first". **`numgad` ≤ 0 means "up to the end of the chain"** — 0 included, not only −1
  [O probe for −1; O ROM for 0 and other values ≤ 0].
- **Refresh** (RefreshGList and the shared rendering routine): `numgad` > 0 draws that many gadgets (fewer if the
  list ends); **`numgad` ≤ 0 draws up to the end of the list** [O probe: count 0 drew the four gadgets A–D and
  everything after them]. The value **−2** is special in the rendering routine (requester range rule,
  `intuition-gzz-v34.md` §6.2); RefreshGList passes the caller's count through unchanged, so a caller that passes
  −2 gets that rule too [O ROM].
- AddGList's prop-gadget set-up (§3.2) uses a **third** reading: it visits the first `numgad` gadgets of the
  passed chain, where **0 visits none** and a negative value visits the whole chain [O ROM, not probed]. So
  `AddGList(..., numgad = 0)` inserts the whole chain but does **not** initialise the PropInfo borders of the prop
  gadgets in it.

### 1.3 Return values

- The functions that return a position return it as an **unsigned 16-bit value, zero-extended to 32 bits in D0**.
  "Not found / nothing done" is therefore **D0 = $0000FFFF**, not $FFFFFFFF: a caller testing the sign of the
  long word does not see the failure; one testing the low word (or comparing with (UWORD)−1) does [O probe, reqg
  steps 8 and Z: the full 32-bit D0 of a failed RemoveGList and of RemoveGadget on a gadget in no list is
  $0000FFFF].
- AddGadget, AddGList, RemoveGadget and RemoveGList return a position; RefreshGadgets, RefreshGList, OnGadget and
  OffGadget return nothing defined [O ROM, AutoDoc].

### 1.4 Locking

- AddGList, AddGadget, RemoveGList and RemoveGadget hold **IntuitionBase semaphore no. 2** (the one
  `LockIBase(2)` takes, `intuition-misc-v34.md` §6) across the whole list update, and release it before returning
  [O ROM]. This characterises lock 2 as the gadget-list lock (2.0 calls it GADGETSLOCK [S]).
- The search for the requester that owns a gadget (RemoveGList on a REQGADGET, §4.2) walks the window's requester
  list **under Forbid** [O ROM].
- OnGadget and OffGadget change the gadget's Flags **without** taking any lock, then redraw [O ROM].
- None of the four list functions checks that the window is open, that the gadget is not already in a list, or
  that the gadget is the one currently held by the input engine [O ROM]. Adding a gadget twice makes a cycle.

### 1.5 No rendering on add or remove

AddGadget, AddGList, RemoveGadget and RemoveGList **draw nothing and erase nothing** [O probe step "a": after
AddGList of four bordered gadgets, no pixel of their borders is set; AutoDoc]. A removed gadget's imagery stays on
screen until the application clears it.

---

## 2. AddGadget (−42)

`Position = AddGadget(Window, Gadget, Position)` — A0, A1, D0 (`.fd`).

- Exactly `AddGList(Window, Gadget, Position, 1, <requester>)` (§3) [O ROM]: inserts **one** gadget.
- **The gadget's NextGadget is overwritten** with the successor at the insertion point (NULL at the end of the
  list), whatever it held before [O probe step 1: E.NextGadget preset to A, after AddGadget(−1) it is NULL].
- Returns the position where the gadget landed, i.e. the requested position clamped to the list length: 4 for −1
  on a list of 4 system gadgets, 7 for 100 on a list of 7 [O probe steps 1 and 4].
- **Requester gadgets**: AddGadget has no requester argument. If the gadget has the REQGADGET bit ($1000) in
  GadgetType, the shared insertion path still looks for a requester, and the pointer it uses is not an argument of
  the call (it is the value the caller left in D2) [O ROM, not probed]. The result is undefined; 1.3 programs add
  requester gadgets with AddGList or through the NewRequester structure. An implementation may do anything
  sensible here (e.g. insert into the window list); no known program depends on it [D].
- Flags, Activation and GadgetType of the gadget are not changed [O ROM; O probe: B's Flags read $0000 after three
  add/remove cycles]. For a PROPGADGET, PropInfo LeftBorder/TopBorder are set (§3.2).

## 3. AddGList (−438)

`Position = AddGList(Window, Gadget, Position, Numgad, Requester)` — A0, A1, D0, D1, A2 (`.fd`).

### 3.1 Insertion

- **Target list**: if the **first** gadget passed (`Gadget`) has REQGADGET in GadgetType, the list of the
  `Requester` argument (its ReqGadget chain); otherwise the window's FirstGadget list. Only the first gadget's
  type is tested [O ROM; O probe reqg steps 1 and 7: REQGADGET gadgets with the Requester argument land in the
  requester's list, the window list is unchanged]. The requester does not have to be displayed and is not looked
  up in the window [O ROM, not probed: the probe's requester was up].
- **Insertion point**: position `Position` of the target list, counted as in §1.1 (system gadgets count; negative
  or too large = end) [O probe].
- **Range inserted**: `Gadget` and the gadgets that follow it through their NextGadget links, `Numgad` of them,
  or up to the end of the passed chain if it is shorter or if `Numgad` ≤ 0 (§1.2) [O probe for 2 and −1; O ROM
  for 0].
- **Links**: the gadget before the insertion point (or the list head) now points to `Gadget`; the **last inserted
  gadget's NextGadget is overwritten** with the old successor at the insertion point (NULL at the end); the links
  **inside** the range are kept as the caller built them; a gadget of the passed chain **beyond** the range is not
  touched and is not linked from the list any more (the caller's chain is split only logically: the last inserted
  gadget no longer points to it) [O probe step 7: AddGList(A→B→C→D, at 1, 2) gives `F A B s40 …`,
  B.Next = the old gadget at position 1 (a system gadget), C.Next still D].
- **Return**: the position of the first inserted gadget (clamped as in §1.1) [O probe: 1, 7, 0 in steps 7, 9,
  S; reqg 0 and 2 in steps 1 and 7].
- Inserting at 0 puts the range before the system gadgets: the last inserted gadget then points to the old head
  [O probe step S: `A B C D F s40 …`, D.Next = F].
- Draws nothing (§1.5). Lock 2 held (§1.4).

### 3.2 Prop gadget set-up

For each gadget visited (the first `Numgad` of the passed chain; 0 visits none, negative visits all, §1.2) whose
GadgetType, **ignoring the high flag bits (SYSGADGET, SCRGADGET, GZZGADGET, REQGADGET)**, equals PROPGADGET (3):
PropInfo LeftBorder and TopBorder are set to 0 if PropInfo Flags has PROPBORDERLESS ($0008), otherwise to the
**WBorLeft and WBorTop of the window's screen** (signed bytes, sign-extended) — for requester gadgets too, the
screen being the window's [O ROM, not probed; same rule as `intuition-prop-v34.md` §1]. Values the application
put there are overwritten. Nothing else is set up (no GadgetType/Flags change, no string-gadget set-up) [O ROM].

## 4. RemoveGadget (−228) and RemoveGList (−444)

`Position = RemoveGadget(Window, Gadget)` — A0, A1.
`Position = RemoveGList(Window, Gadget, Numgad)` — A0, A1, D0. **No requester argument in V34** (`.fd`).

### 4.1 Contract

- RemoveGadget is exactly `RemoveGList(Window, Gadget, 1)` [O ROM].
- `Gadget` = NULL: nothing is done, returns $FFFF (§1.3) [O ROM].
- **Source list**: for a gadget without REQGADGET, the window's FirstGadget list. For a REQGADGET gadget, see §4.2.
- The gadget is **searched** in the list by address. Not found ⇒ nothing changes, returns **$FFFF** [O probe
  step 6].
- **Range removed**: from `Gadget`, `Numgad` gadgets, or up to the **end of the list** if fewer follow it or if
  `Numgad` ≤ 0 (§1.2) [O probe for 1, 2, −1; O ROM for 0]. With −1 (or 0) **every gadget after `Gadget` goes too**,
  system gadgets included if they follow it.
- **Links**: the predecessor (or the list head) takes the NextGadget of the last removed gadget. **The NextGadget of
  the removed gadgets is left as it was**: the last removed gadget still points into the window list (to the
  gadget that followed it), it is **not** cleared to NULL [O probe: step 5 G.Next still points to the system
  gadget that followed it; step 8 B.Next still points to the system gadget after B; step R, D.Next = NULL only
  because D was last]. A caller that wants a NULL-terminated sublist must clear it itself.
- **Return**: the position `Gadget` had in the list before the removal [O probe: 2, 1, 7 in steps 5, 8, R].
- Flags are not changed (a removed SELECTED gadget stays SELECTED) [O ROM]. Draws nothing (§1.5). Lock 2 held
  (§1.4).

### 4.2 Requester gadgets

If `Gadget` has REQGADGET, the function looks for the requester **in the window's requester list**
(`Window.FirstRequest` chain, i.e. the requesters currently displayed in that window) whose ReqGadget list
contains `Gadget`, under Forbid. If none is found, nothing is removed and $0000FFFF is returned. Otherwise the
removal and the position work on that requester's list [O ROM; O probe reqg step 2: with the requester up,
RemoveGList(L, 1) on the list `K L J` returns 1 and leaves `K J`]. Consequence: a requester gadget cannot be
removed while its requester is not up [O probe reqg step 8: after EndRequest, RemoveGList(K, 1) returns
$0000FFFF and the requester's list `K J L` is unchanged].

### 4.3 System gadgets

- System gadgets are ordinary members of the window list for the list functions: RemoveGList(Window.FirstGadget,
  1) on a fresh window removes the front depth gadget and returns 0 [O probe, reqg GS step 1]. No check protects
  them (§1.1).
- A removed system gadget is **no longer drawn** by a refresh of the list: after RemoveGList of the front depth
  gadget and RefreshGadgets(new Window.FirstGadget), its box stays at pen 0 while the back depth gadget, now at
  the head, is redrawn [O probe, reqg GS step 2: 0 vs 20 non-zero pixels on line 4 of the two boxes]. Its old
  imagery is not erased by the removal either (§1.5); the probe cleared it itself.
- **Input**: the gadget under the pointer is found **only by walking a list** [O ROM]: on a button press in the
  active window, the first requester's ReqGadget list if the pointer is inside that requester's layer, otherwise
  `Window.FirstGadget`, in forward order, the first gadget whose box contains the point wins (a GADGDISABLED one
  stops the search with no gadget, `intuition-gzz-v34.md` §6.4; with a requester up only REQGADGET or SYSGADGET
  gadgets are accepted, `intuition-requesters-v34.md` §3.1). The action is then chosen from the **GadgetType of
  the gadget found** (SYSGADGET types: drag, depth, sizing, close). The window keeps no other reference to its
  system gadgets for input. Consequence: once a system gadget is removed from the list, a click on its old box
  **does nothing of its own** (no CLOSEWINDOW, no depth change): it goes to the next gadget of the list whose box
  contains the point — for the front or back depth box or the close box, the **drag gadget**, whose box spans
  the whole title bar width (`intuition-frame-v34.md` §5.2), so the click starts a window drag; if no gadget of
  the list covers it, the click is an ordinary click in the window [O ROM, not probed].

## 5. RefreshGadgets (−222) and RefreshGList (−432)

`RefreshGadgets(Gadgets, Window, Requester)` — A0, A1, A2.
`RefreshGList(Gadgets, Window, Requester, NumGad)` — A0, A1, A2, D0.

- Both call the shared rendering routine of `intuition-gzz-v34.md` §6.1 with the window, the first gadget and a
  count: **−2** for RefreshGadgets, **`NumGad` unchanged** for RefreshGList [O ROM].
- **The `Requester` argument is ignored by both** [O ROM; the probe passes NULL and the requester gadgets are
  still drawn in the requester layer]. For a REQGADGET gadget the requester is found from the window's requester
  list (`intuition-gzz-v34.md` §6.2: nothing drawn if the requester is not displayed or has Flags bit $0002; with
  count −2 the range restarts at the requester's first gadget).
  - RefreshGList(K, 1), K being the **first** requester gadget, draws K only [O probe, reqg step 3].
  - RefreshGadgets(J), J being the **second** gadget of the requester list `K J`, draws **K and J**: the range
    restarted at ReqGadget [O probe, reqg step 4]. RefreshGList(J, −2) does the same [O probe, reqg step 5].
  - With the requester down (after EndRequest), RefreshGList(K, 1) returns without drawing or crashing [O probe,
    reqg step 9: the program went on; nothing can be read, the layer is gone].
- **PREDRAWN requesters** (Flags $0002): their gadgets are **never drawn by intuition** [O ROM, not probed].
  Request() (and the redraw of a damaged requester layer, which goes through the same display step) only copies
  `ImageBMap` into the layer (`intuition-requesters-v34.md` §2.3); the gadget list is not rendered there, and the
  rendering routine itself draws nothing for a gadget of a PREDRAWN requester, so RefreshGadgets, RefreshGList,
  OnGadget and OffGadget on such a gadget draw nothing either. The gadget imagery must be part of the ImageBMap.
  The prop-gadget set-up of §3.2 is still applied to the requester's gadgets at Request() time [O ROM]. Whether
  the highlight of a clicked gadget (e.g. GADGHCOMP) is still drawn in a PREDRAWN requester was not read.
- `Gadgets` = NULL: nothing is drawn [O ROM].
- **Range**: from `Gadgets`; RefreshGadgets to the end of the list; RefreshGList `NumGad` gadgets, or to the end if
  `NumGad` ≤ 0 (§1.2) [O probe steps b, c, d, g].
- **Order and contents** (gzz §6.1): last gadget of the range first, `Gadgets` last (on top); per gadget its
  Border/Image/prop imagery, GadgetText, string text, then ghosting if GADGDISABLED; then a forward pass that
  applies the highlight of every SELECTED gadget of the range. A refresh of a list that starts at
  `Window.FirstGadget` draws the system gadgets too.
- **No erase**: the box is not cleared before drawing [O ROM, gzz §6.4].
- **Highlight**: a SELECTED GADGHCOMP gadget gets its select box complemented on **all planes** of the screen
  after its imagery is drawn [O probe step g: on a 2-plane Workbench screen the pen-1 border reads pen 2 and the
  pen-0 interior reads pen 3].

## 6. OffGadget (−174) and OnGadget (−186)

`OffGadget(Gadget, Window, Requester)` / `OnGadget(Gadget, Window, Requester)` — A0, A1, A2.

- OffGadget **sets** GADGDISABLED ($0100) in Flags; OnGadget **clears** it. No other Flags bit changes
  [O probe: B's Flags $0100 after OffGadget, $0000 after OnGadget].
- Then exactly `RefreshGadgets(Gadget, Window)`: **from `Gadget` to the end of the list**, not only the gadget
  [O probe steps e and f: A (before B) is not drawn, B, C and D are]. `Requester` is ignored (§5); a requester
  gadget redraws its whole requester list (count −2 rule) [O probe, reqg step 6: OffGadget(J), J second in `K J`,
  draws K and J].
- **Ghosting** after OffGadget: the dot grid of gzz §6.4 (one pixel in four on every line, pattern
  $4444/$1111 aligned on the rendering layer, APen = BlockPen, JAM1) over the gadget's box [O probe step e: on
  window line 45 (pattern line 1) of gadget B, window x 78..85 read `.x...x..` = dots at x mod 4 = 3, as the
  gzz §6.4 rule gives. The window sits at screen (20,20), multiples of 4, so this does not separate layer from
  screen alignment].
- **OnGadget does not erase the box** (gzz §6.4, [D] there): the dots stay where the gadget's own rendering does
  not overwrite them (a Border gadget keeps them between its lines). The probe cleared the area before OnGadget,
  so it confirms only that no new dot is drawn (step f: `00`), not the absence of an erase — see the additional
  probe 4 in §8.
- No lock; no IDCMP; no check that the gadget is in the window [O ROM].

## 7. Test vectors (real ROM, probe output)

### 7.1 Gadget list functions (`tests/glist_probe.s`)

Probe set-up (`tests/glist_probe.s`): Workbench screen, window 400×100 at (20,20), Flags $100E (ACTIVATE,
WINDOWDRAG, WINDOWDEPTH, WINDOWCLOSE), no IDCMP. Our boolean gadgets 'A'..'H' (GADGHCOMP, RELVERIFY, 30×10):
A–D at y = 40 with a pen-1 JAM1 Border rectangle, E–H at y = 70 without rendering. Initial chains: A→B→C→D→NULL,
E→A, F, G, H unlinked. List notation: our gadgets by GadgetID letter, system gadgets `s` + GadgetType low byte
(s40 front depth, s60 back depth, s80 close, s20 drag). `N x y` = NextGadget of x (`?` = not one of our
gadgets). `P` = pen at the middle of the top border line of A, B, C, D (area cleared to pen 0 before each step).

```
GP 0 0000 | s40 s60 s80 s20                      fresh window
GP 1 0004 | s40 s60 s80 s20 E                    AddGadget(E, -1)
GP N E 0
GP 2 0000 | F s40 s60 s80 s20 E                  AddGadget(F, 0)
GP 3 0002 | F s40 G s60 s80 s20 E                AddGadget(G, 2)
GP 4 0007 | F s40 G s60 s80 s20 E H              AddGadget(H, 100)
GP 5 0002 | F s40 s60 s80 s20 E H                RemoveGadget(G)
GP N G ?                                         (still the back-depth gadget)
GP 6 FFFF | F s40 s60 s80 s20 E H                RemoveGadget(G) again
GP 7 0001 | F A B s40 s60 s80 s20 E H            AddGList(A->B->C->D, 1, 2)
GP N B ?                                         (the front-depth gadget)
GP N C D
GP 8 0001 | F s40 s60 s80 s20 E H                RemoveGList(A, 2)
GP N B ?                                         (not cleared)
GP 9 0007 | F s40 s60 s80 s20 E H A B C D        B.Next := C, AddGList(A, -1, -1)
GP R 0007 | F s40 s60 s80 s20 E H                RemoveGList(A, -1)
GP N D 0
GP S 0000 | A B C D F s40 s60 s80 s20 E H        chain A->B->C->D, AddGList(A, 0, 4)
GP N D F
GP P a 00 00 00 00                               no call: AddGList drew nothing
GP P b 01 01 00 00                               RefreshGList(A, 2)
GP P c 00 01 01 01                               RefreshGadgets(B)
GP P d 01 01 01 01                               RefreshGList(A, 0)
GP P e 00 01 01 01                               OffGadget(B)
GP M e 44                                        window x 78..85, y 45 inside B
GP F B 0100
GP P f 00 01 01 01                               OnGadget(B)
GP M f 00
GP F B 0000
GP P g 02 00 00 00                               A SELECTED, RefreshGList(A, 1)
GP I g 03                                        pixel inside A
GP END
```

The screenshot taken at the end shows only gadget A, as a pen-3 box with a pen-2 frame (complemented), and the
window's four system gadgets intact.

### 7.2 Requester gadgets and a removed system gadget (`tests/reqg_probe.s`)

Set-up: Workbench screen, window 400×100 at (20,20) with sizing, drag, depth and close gadgets (system list
`s40 s60 s10 s80 s20`: front depth, back depth, sizing, close, drag, as `intuition-frame-v34.md` §5.1). Requester R
at (10,15), 200×40, ReqGadget = J; our REQGADGET boolean gadgets J, K, L with a pen-1 Border (30×10 at (10,10),
(60,10), (110,10) in R); initial chains J alone, K→L. `GQ <step> <D0, 32 bits> | <R list> / <window list>`;
`GQ P` = pen read in R's layer at the middle of the top border of J, K, L, after clearing the layer to pen 0
(`Requester` argument NULL in every refresh call). `GS P` = number of non-zero pixels on line 4 of the front /
back depth boxes after clearing the right end of the title bar and RefreshGadgets(Window.FirstGadget). Steps 9,
GS 0 print a constant 0, not a return value.

```
GQ 0 00000001 | J / s40 s60 s10 s80 s20          Request(R): TRUE
GQ 1 00000000 | K L J / s40 s60 s10 s80 s20      AddGList(K->L, 0, 2, R)
GQ 2 00000001 | K J / s40 s60 s10 s80 s20        RemoveGList(L, 1), R up
GQ P 3 00 01 00                                  RefreshGList(K, 1)
GQ P 4 01 01 00                                  RefreshGadgets(J)
GQ P 5 01 01 00                                  RefreshGList(J, -2)
GQ P 6 01 01 00                                  OffGadget(J)
GQ 7 00000002 | K J L / s40 s60 s10 s80 s20      AddGList(L, -1, 1, R)
GQ 8 0000FFFF | K J L / s40 s60 s10 s80 s20      EndRequest(R), RemoveGList(K, 1)
GQ 9 00000000 | K J L / s40 s60 s10 s80 s20      RefreshGList(K, 1), R down: no crash
GQ Z 0000FFFF | K J L / s40 s60 s10 s80 s20      RemoveGadget(Z), Z in no list
GS 0 00000000 | s40 s60 s10 s80 s20              fresh list
GS 1 00000000 | s60 s10 s80 s20                  RemoveGList(Window.FirstGadget, 1)
GS P 2 00 14                                     front box not redrawn, back box redrawn
GQ END
```

Our ROM gave the same 15 lines on 2026-11-04.

## 8. Not covered by the probe — suggested additional probes

1. **Full D0 on failure**: done for RemoveGadget on an absent gadget and for RemoveGList on a requester gadget
   whose requester is down (reqg steps Z and 8: $0000FFFF). Still open: RemoveGList(win, NULL, 1), expected the
   same (§4.1).
2. **Counts of 0**: AddGList(chain of 3, pos, 0) — expected: all three inserted, return = position; with a
   PROPGADGET in the chain whose LeftBorder/TopBorder are preset to $55, expected: left unchanged with 0, set to
   WBorLeft/WBorTop with 1 or −1. RemoveGList(gad, 0) and RemoveGList(gad, −1) on a gadget followed by others —
   expected: everything up to the end of the window list removed, system gadgets included.
3. **Requesters**: done (§7.2). Still open: AddGList with the REQGADGET range into a requester that is **not**
   up (expected: inserted in its ReqGadget list all the same, §3.1); AddGadget of a REQGADGET gadget (§2,
   undefined); a PREDRAWN requester with bordered gadgets and an ImageBMap that does not contain them (expected
   §5: only the bitmap appears, RefreshGadgets on one of its gadgets draws nothing); a GADGHCOMP gadget of a
   PREDRAWN requester clicked (highlight not read).
4. **OnGadget without clearing**: OffGadget(B), then OnGadget(B) with no RectFill in between; read the ghost byte
   again. Expected (gzz §6.4 [D]): dots still there for a Border gadget; the same with a full-box Image gadget —
   expected: dots gone where the image covers them.
5. **System gadgets in a refresh**: partly done (§7.2 GS 2: a refresh from the head redraws the back depth
   gadget, a removed front depth gadget is not drawn). Still open: RefreshGList(Window.FirstGadget, 1) should
   redraw only the head gadget; a pixel of the close image after RefreshGadgets(Window.FirstGadget).
7. **Click on a removed system gadget's box** (§4.3): remove the close gadget (or the front depth gadget) with
   RemoveGList, then click its old box with the window's IDCMP set to CLOSEWINDOW | GADGETDOWN | MOUSEBUTTONS.
   Expected: no CLOSEWINDOW and no depth change; the drag gadget takes the click (moving the mouse with the button
   held moves the window). Then also remove the drag gadget: expected an ordinary SELECTDOWN in the window.
6. **Pattern origin**: repeat step e with the window at an x position that is not a multiple of 4 (e.g. 22,21)
   to separate layer-aligned from screen-aligned ghosting (gzz §6.4 says layer-aligned, ROM reading only).

---

## Clean-room review

- [x] Contracts are described as rules on public fields (`intuition.h` 1.3 offsets), `.fd` registers, return
  values and observable list states. No instruction sequence, no pseudo-code of a routine, no ROM address.
- [x] The probe lines quoted in §7 are API output of our own test program (positions, letters, pens), not ROM
  data.
- [x] Facts read in the ROM are marked [O ROM] and listed in §8 as candidates for a black-box confirmation.
- [x] The §7.2 lines are API output of our own test program (return values, list letters, pen numbers, pixel
  counts), not ROM data. §4.3 (hit test) and the PREDRAWN rule in §5 are behaviour descriptions only.
