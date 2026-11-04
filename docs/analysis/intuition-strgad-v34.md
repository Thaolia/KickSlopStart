# intuition-strgad-v34.md — ActivateGadget and string gadgets (intuition 34.3)

> ANALYSIS track ("dirty"). Sources: black-box probe `tests/strg_probe.s` (harness `tests/strg_probe.sh`) on
> Amiberry A500 with the real ROM `assets/kick34005.A500`, run on 2026-11-04 (serial lines and a screenshot);
> ROM reading of ActivateGadget (−462), of the string-gadget path of the input state machine and of the string
> editing, rendering and LONGINT helpers (behaviour only); the 1.3 `.fd`, `intuition.h` and the AutoDocs.
>
> **Legend**: **[O probe]** observed with the probe on the real ROM · **[O ROM]** observed by reading the ROM, not
> probed · **[AutoDoc]** public documentation · **[D]** deduced · **[S]** assumed.
> No ROM address, no instruction listing, no transcription of a routine.

Related pages: input state machine, deferred actions and activation `intuition-input-menus-v34.md` §1.8–§1.11;
IDCMP construction and targets §2.1–§2.3 of the same page; gadget rendering and ghosting `intuition-gzz-v34.md`
§6; gadget lists `intuition-gadgets-v34.md`; default font without `devs:system-configuration`
`intuition-prefs-v34.md` (topaz 9).

Public structure fields used: `Gadget.LeftEdge` +$04, `TopEdge` +$06, `Width` +$08, `Height` +$0A, `Flags` +$0C,
`Activation` +$0E, `GadgetType` +$10, `SpecialInfo` +$22; `StringInfo.Buffer` +$00, `UndoBuffer` +$04,
`BufferPos` +$08, `MaxChars` +$0A, `DispPos` +$0C, `UndoPos` +$0E, `NumChars` +$10, `DispCount` +$12, `CLeft`
+$14, `CTop` +$16, `LayerPtr` +$18, `LongInt` +$1C, `AltKeyMap` +$20; `Window.FirstRequest` +$24,
`Window.WScreen` +$2E; `Screen.RastPort` +$54 (TxHeight at Screen+$8E, TxWidth at Screen+$90);
`IntuitionBase.ActiveWindow` +$34, `ActiveScreen` +$38. Private: IB state word +$294 (values as in
`intuition-input-menus-v34.md` §1.8, plus 13 below).

---

## 1. ActivateGadget (−462)

`success = ActivateGadget(gadget A0, window A1, requester A2)` — V33+, present in 34.3.

### 1.1 Conditions [O ROM unless stated]

Under Forbid and the IB state lock (the first of the seven), the call succeeds only if **all** of these hold:

1. `GadgetType` with the bits $FC00 masked off (SYSGADGET, SCRGADGET, GZZGADGET, REQGADGET and the two bits
   below them) equals **4 (STRGADGET)**. A boolean gadget returns 0 [O probe A8].
2. `window` is `IntuitionBase.ActiveWindow`. **ActivateGadget never activates the window**; on an inactive
   window it fails.
3. `requester` equals `window->FirstRequest` exactly (the head of the window's requester list). With no
   requester up both are NULL. A requester other than the head fails.
4. `window` is not the window currently waiting for a SIZEVERIFY/MENUVERIFY/REQVERIFY reply.
5. The input state is **1 (idle)** and the window has **no requester** (FirstRequest = NULL), **or** the state
   is **7 (active window in requester)**. Any other state fails: a menu open, a gadget held, another string
   gadget being edited (state 10) or an earlier ActivateGadget not yet carried out (state 13) [O probe A9: a
   string gadget being edited makes a second ActivateGadget return 0].
6. For a REQGADGET gadget: the gadget must be found in one of the window's requesters, and that requester must
   have a layer (be rendered); otherwise 0.

Not checked:

- **GADGDISABLED**: a disabled string gadget is activated and edited like any other [O probe A8: D0 = 1;
  screenshot: the cursor appears in the ghosted box and typing would edit it].
- Whether a non-REQGADGET gadget is really in `window`'s list: it is set up from its own geometry against the
  window, list membership is not verified.

Special case: if the gadget is **already** the gadget being edited (or the one pending activation), the call
returns 1 and does nothing else.

### 1.2 Return value [O ROM, O probe]

D0 = 1 on success (or already active), 0 on failure, as a long (word sign-extended): the probe reads
`00000001` / `00000000`.

### 1.3 What happens, and when [O ROM; O probe for the timing]

ActivateGadget only **records** the gadget (it computes the gadget's box and cursor cell, remembers whether to
return to state 1 or state 7 afterwards) and sets the input state to **13 ("string gadget to activate")**. It
does not draw, does not set SELECTED, does not touch the StringInfo.

The activation is carried out by the input handler at the **next input event that reaches the state machine**
(any class; in practice the next timer tick, ≤ 0.1 s). State 13 runs the same code as a SELECTDOWN on the gadget
(§2), **then feeds that same event to the string editor** (§3): if the triggering event is a key press it is
applied as an edit; if it is a SELECTDOWN outside the box, the gadget is activated and immediately ends (§5.2).

Consequences:

- On return from ActivateGadget, `Flags` may or may not have SELECTED yet [O probe: A1 read $0080, A2–A7 read
  $0000 right after the call]. A caller must not rely on either.
- BufferPos, DispPos and NumChars are unchanged by the call [O probe A1–A7]; the cursor starts at the
  **existing BufferPos** (A1: BufferPos 2 in "Hello", "abc" typed ⇒ "Heabcllo").

---

## 2. Start of editing (click or ActivateGadget) [O ROM unless stated]

A SELECTDOWN on an enabled string gadget (hit test `intuition-input-menus-v34.md` §1.9) and the pending state 13
share this sequence:

1. GADGIMMEDIATE ⇒ **GADGETDOWN** to the window (Code 0, IAddress = gadget, §2.3 of the input page). With
   FOLLOWMOUSE (and no GADGIMMEDIATE) the window gets REPORTMOUSE for the duration of the gadget (restored at
   the end); not probed.
2. SELECTED is set and the gadget is redrawn with its highlight (the cursor, §4.3) [O probe: A1 $0080; the B
   lines show $0000 after the end].
3. If `UndoBuffer` ≠ NULL: **`MaxChars` bytes** are copied from `Buffer` to `UndoBuffer` (whole area, not only
   up to the NUL), and `UndoPos := BufferPos` (the position **before** the activating click moves the cursor)
   [O probe B3, B4: UndoBuffer = the text at activation].
4. Keymap for the editing: `AltKeyMap` if Activation has ALTKEYMAP ($1000), else NULL (default keymap).
5. State 10 (editing) is entered, and the activating event itself is passed to the editor (§3): for a click,
   this places the cursor on the clicked cell (§3.4).

During state 10 **every** input event reaching the state machine goes to the editor; keys are **not** sent as
RAWKEY/VANILLAKEY and are not passed on. Window activations requested meanwhile (ActivateWindow, OpenWindow with
ACTIVATE) are **dropped**, as during a held gadget (`intuition-input-menus-v34.md` §1.10) [O probe A9: a
window opened with ACTIVATE while a string gadget was active never became active; IntuitionBase.ActiveWindow
stayed the probe's window].

---

## 3. Editing

The editor sees one input event at a time. Only RAWKEY (class 1) and RAWMOUSE (class 2) do anything; other
classes are ignored. A key **release** (code bit 7 set) does nothing except the LONGINT recomputation (§3.6).
Key repeats are ordinary key presses. After each event that changed something the gadget's text is redrawn
(§4).

### 3.1 Keys handled by raw code (qualifiers mostly ignored) [O ROM; O probe where stated]

| Raw code | Key | Effect |
|---|---|---|
| $41 | Backspace | if BufferPos > 0: delete the character before the cursor, BufferPos−1, NumChars−1 [O probe test 3] |
| $46 | Del | if BufferPos < NumChars: delete the character under the cursor, NumChars−1, BufferPos kept [O probe test 3] |
| $4F | Cursor left | with either Shift (qualifier bit 0 or 1): BufferPos := 0; otherwise BufferPos−1 if > 0 [O probe test 3] |
| $4E | Cursor right | with either Shift: BufferPos := NumChars; otherwise BufferPos+1 if < NumChars [O probe test 3] |
| $44, $43 | Return, keypad Enter | **end of editing** (§5.1) [O probe tests 1–7] |
| $32 + right Amiga | right-Amiga X | `Buffer[0] := 0`, BufferPos := 0, NumChars := 0 [O probe test 4] |
| $10 + right Amiga | right-Amiga Q | **undo**, only if UndoBuffer ≠ NULL: copy `MaxChars` bytes UndoBuffer → Buffer, BufferPos := UndoPos, NumChars := length of the restored text [O probe test 5] |

- "Right Amiga" means qualifier bit 7 (RCOMMAND); left Amiga does not do X/Q (the key then goes through §3.2).
  Other qualifiers are not checked. Right-Amiga Q with UndoBuffer = NULL also goes through §3.2 [D: inserts the
  keymap's character].
- Del, Backspace, Return and Enter ignore all qualifiers; arrows only look at the Shift bits.
- Up/Down arrows, Help and function keys have no dedicated handling; they go through §3.2 and are dropped
  because they translate to more than one character.
- There is no "cursor to start/end" key other than Shift+arrows, and no Tab handling (see §3.2).

### 3.2 All other keys: character insertion [O ROM]

1. The event alone (its `ie_NextEvent` temporarily cleared) is translated with **console.device
   RawKeyConvert** into a 1-byte buffer, with the keymap of §2 step 4.
2. If the translation does not give **exactly one byte**, or gives the byte $00, the key is ignored (no redraw).
   Hence CSI sequences (arrows Up/Down, Help, F-keys, Shift+Tab) and dead keys are dropped.
3. **Any other single byte is inserted, unfiltered**: printable ASCII, Latin-1 characters ≥ $A0 produced by
   Alt combinations, and **control characters** — Tab inserts $09, Esc $1B, Ctrl+letter $01–$1A. They are
   drawn with whatever glyph the font has for them.
4. If `NumChars ≥ MaxChars − 1`: **DisplayBeep** on `IntuitionBase.ActiveScreen`, nothing inserted.
   **MaxChars counts the terminating NUL**: at most MaxChars−1 characters [O probe test 6: MaxChars 6, "abcd" +
   "123" ⇒ "abcd1"].
5. LONGINT gadget: the character must also pass the filter of §3.5, else DisplayBeep, nothing inserted.
6. Insertion at BufferPos (the tail, NUL included, moves right), NumChars+1, BufferPos+1 [O probe tests 1, 3, 6].

### 3.3 Mouse buttons [O ROM]

- **SELECTDOWN** with the pointer in the same layer as the gadget and inside the gadget box: cursor placement
  (§3.4), editing continues.
- SELECTDOWN anywhere else (other window, screen bar, another gadget, outside the box): **end of editing without
  message**, then the click is processed as in the state it returns to (§5.2).
- **MENUDOWN**: end of editing without message; the menu button is then processed normally (menu opens, or
  MOUSEBUTTONS with RMBTRAP).
- Releases, middle button and pure movements: ignored.

### 3.4 Click → cursor position [O ROM]

`x` = pointer x relative to the gadget box's left edge (GREL* resolved). New BufferPos = `x / w + DispPos`
(integer division, w = TxWidth of the **screen's** font, §4.1), clamped to 0 … NumChars. A click anywhere in a
character cell puts the cursor **on** that character (before it); a click right of the text puts it at the end.
DispPos is not changed by the click itself (the redraw may scroll, §4.2).

### 3.5 LONGINT [O ROM; O probe test 2]

**Typing filter** (in addition to §3.2 step 4):

- `-` or `+`: accepted **only at BufferPos 0**, and only if the buffer does not already start with `-` or `+`.
  A sign elsewhere is refused with a beep [O probe: "12", cursor 0, "5-x9" ⇒ "5912"].
- `0`–`9`: accepted only if the text **with the digit inserted** converts without overflow (the trial conversion
  is done on the buffer, then undone). A digit that would overflow is refused with a beep.
- Anything else (letters, space, control characters): refused with a beep [O probe: `x` refused].
- A digit typed **before** an existing sign (cursor 0 of "−12") is not refused by the filter (the conversion
  does not check for digits, see below) [D, not probed].

**Conversion** (`Buffer` → `LongInt`): an optional leading `-` or `+` is skipped; then each following byte up
to the NUL is taken as a digit (byte − '0', **not checked** to be 0–9), accumulated in base 10. Overflow test:
the magnitude may reach 2 147 483 648 (accumulated as a negative value); one more step that would exceed it
stops the conversion and reports failure, `LongInt` then holds the value of the digits accumulated so far.
The sign is applied at the end. Consequences [D from O ROM, not probed]:

- empty text, `-` or `+` alone ⇒ 0;
- `2147483648` (no sign) is **accepted** and stored as $80000000 (−2147483648); `-2147483648` is exact;
- text set by the application with non-digits converts arithmetically (e.g. "12a" ⇒ 12×10 + 49 = 169).

### 3.6 When LongInt is updated [O ROM]

For a LONGINT gadget the conversion runs after every insertion, Backspace, Del, right-Amiga X/Q, **key
release**, and Return/Enter; not after arrows or clicks (they do not change the text). The typing filter's
trial conversion also writes `LongInt`; a refused digit can leave it momentarily at the trial's partial value
until the next key release recomputes it. The probe's final value: "5912" ⇒ $00001718 [O probe B2].

---

## 4. Display

### 4.1 Font and geometry [O ROM; O probe test 7]

- **All measurements use the screen's font** (TxWidth/TxHeight of the window's screen RastPort), not the
  window's RastPort font: a SetFont on the window has no effect on string gadgets [D].
- `DispCount := gadget box width / screen TxWidth` (integer). It is (re)computed for each string gadget when
  gadgets are drawn by the gadget refresh (OpenWindow, RefreshGadgets/RefreshGList, AddGList set-up), together
  with `NumChars := strlen(Buffer)` and `BufferPos := min(BufferPos, NumChars)`; **not** during editing.
- The cursor cell is TxWidth × TxHeight at (box left + (BufferPos − DispPos) × TxWidth, box top).

### 4.2 Scrolling (DispPos) [O ROM; O probe test 7]

Before each draw:

- if BufferPos < DispPos: DispPos := BufferPos;
- if BufferPos ≥ DispPos + DispCount: DispPos := BufferPos − DispCount + 1.

So the cursor always needs a cell of its own: with the cursor at the end, DispCount−1 characters are visible
plus the cursor cell. DispPos is **not** reset at the end of editing; the text stays scrolled [O probe B7: box 24
px, topaz 9 (10 px wide) ⇒ DispCount 2; "abcdefgh" typed ⇒ BufferPos 8, DispPos 7; screenshot after Return
shows only "h"].

### 4.3 Drawing [O ROM; O probe screenshot]

- Text is drawn with PrintIText of a local IntuiText: **FrontPen 1, BackPen 0, JAM2**, ITextFont NULL (the
  screen font of the RastPort used), at (box left, box top). Window DetailPen/BlockPen are not used.
- Only the characters from DispPos are drawn, at most DispCount cells: the display is cut by temporarily
  writing a NUL into the buffer after the last visible cell (and restoring that byte).
- **Clearing the rest of the box**: when the visible text is shorter than DispCount, the free cells are filled
  by drawing **spaces** (JAM2, pen 0 background). To do so the spaces are **written into `Buffer`** after the
  text, then `Buffer[NumChars]` is set back to NUL: **the bytes after the terminator are left as spaces**. The
  number of padded cells is capped so that no byte at index ≥ MaxChars−1 is written; cells beyond that cap are
  not cleared. Pixels of the box beyond DispCount × TxWidth (and below TxHeight) are never touched [O probe
  screenshot: in the activated disabled gadget, 80 px wide, MaxChars 8, the text cells were cleared over 7 × 10
  px, the 8th cell and the bottom pixel row kept the ghost pattern].
- **Cursor** = the gadget's highlight applied to the cursor cell, while the gadget is the one being edited:
  GADGHCOMP ⇒ the cell is complemented (on the probe screenshot: pen 3 block over pen 0) [O probe];
  GADGHBOX ⇒ a complemented frame around the cell; GADGHIMAGE ⇒ the SelectRender (or GadgetRender) drawn at the
  cell position [O ROM, odd, not probed]; **GADGHNONE ⇒ no visible cursor** [O ROM]. The old cursor is
  removed (complemented again) before the text is redrawn, the new one drawn after.
- The draw is clipped by the window's layer only (no clipping to the box other than the DispCount limit).

### 4.4 STRINGCENTER ($0200) / STRINGRIGHT ($0400) [O ROM, not probed]

Applied at each draw, only when `NumChars < DispCount`:

- pad = DispCount − NumChars − 1 (STRINGRIGHT; one cell is kept on the right for the cursor) or
  (DispCount − NumChars) / 2 rounded down (STRINGCENTER, i.e. (pad_right + 1) / 2);
- **DispPos := −pad** (a negative value is stored in the StringInfo), so the cursor cell and the click mapping
  (§3.4) include the offset;
- the pad cells on the left are cleared with spaces, but only as many as the free room MaxChars − 1 − NumChars
  allows (halved for STRINGCENTER); the leftmost excess pad cells are skipped, not cleared;
- when NumChars ≥ DispCount, the ordinary rule of §4.2 applies; a negative DispPos left from an earlier draw is
  only corrected if the cursor is past the right edge [D: a jump to a long text that keeps the cursor near the
  start, e.g. an undo, could draw from before the buffer — not verified].

---

## 5. End of editing

### 5.1 Return / Enter [O probe; O ROM]

- Raw code $44 (Return) or $43 (keypad Enter), whatever the qualifiers.
- If Activation has **RELVERIFY**: **GADGETUP** to the window: **Code 0**, **Qualifier = the qualifier of the key
  event** (keypad Enter ⇒ $0100 NUMERICPAD; Return ⇒ $0000), IAddress = the gadget [O probe U1–U7]. Without
  RELVERIFY no message [O ROM].
- LongInt is recomputed (§3.6) — the message is already queued but is only read by the application afterwards.
- SELECTED is cleared and the gadget is redrawn without cursor [O probe B lines: Flags $0000].
- The state returns to 1 (or to 7 when the activation started in a requester); the Return event is consumed.
- Not read here: ENDGADGET on a string gadget in a requester (whether Return ends the requester).

### 5.2 Click elsewhere, menu button [O ROM]

- No GADGETUP, no other message for the string gadget. SELECTED cleared, redrawn without cursor.
- The ending event is then **processed again** in the state the gadget returns to (1, or 7 for a requester):
  a click on another gadget activates it (another string gadget starts editing at once), a click in another
  window activates that window, a MENUDOWN opens the menus. The text and LongInt keep their last edited values.

### 5.3 Other ways [O ROM / O probe]

- **ActivateGadget of another gadget** while one is being edited: refused (returns 0), §1.1 point 5 [O probe A9].
- **Window activation** (ActivateWindow, OpenWindow ACTIVATE) during editing: dropped, the editing continues
  [O probe A9].
- Closing the window, RemoveGadget of the active gadget, or a requester appearing while editing: not read;
  treat as undefined.

---

## 6. Test vectors (real ROM, probe output)

Probe set-up (`tests/strg_probe.s`): Workbench screen opened **without `devs:system-configuration`** (default
prefs ⇒ topaz 9, 10 px wide characters), window 400×120 at (20,20), ACTIVATE | WINDOWDRAG | WINDOWDEPTH, IDCMP
GADGETDOWN | GADGETUP. All string gadgets RELVERIFY, GADGHCOMP, no rendering: S1 200×10 ("Hello", BufferPos 2,
MaxChars 32), S2 80×10 LONGINT ("12", BufferPos 0, MaxChars 12), S3 80×10 ("abcd", BufferPos 4, MaxChars 6),
S4 24×10 (empty, MaxChars 20); B boolean; D disabled string gadget (MaxChars 8). Line formats in the header of
`tests/strg_probe.s`. Keys typed per test: 1 "abc" Return; 2 "5-x9" Return; 3 Shift+Left, "Z", Right, Del,
Shift+Right, Backspace, keypad Enter; 4 right-Amiga X, "Q", Return; 5 "zz", right-Amiga Q, Return; 6 "123"
Return; 7 "abcdefgh" Return.

```
ST A1 00000001 0080 0002 0000 0005
ST WAIT 01
ST U1 0000 0000 01
ST B1 0005 0000 0008 00000000 0000 |Heabcllo| |Hello|
ST A2 00000001 0000 0000 0000 0002
ST WAIT 02
ST U2 0000 0000 01
ST B2 0002 0000 0004 00001718 0000 |5912| |12|
ST A3 00000001 0000 0005 0000 0008
ST WAIT 03
ST U3 0000 0100 01
ST B3 0007 0000 0007 00000000 0000 |ZHabcll| |Heabcllo|
ST A4 00000001 0000 0007 0000 0007
ST WAIT 04
ST U4 0000 0000 01
ST B4 0001 0000 0001 00000000 0000 |Q| |ZHabcll|
ST A5 00000001 0000 0001 0000 0001
ST WAIT 05
ST U5 0000 0000 01
ST B5 0001 0000 0001 00000000 0000 |Q| |Q|
ST A6 00000001 0000 0004 0000 0004
ST WAIT 06
ST U6 0000 0000 01
ST B6 0005 0000 0005 00000000 0000 |abcd1| |abcd|
ST A7 00000001 0000 0000 0000 0000
ST WAIT 07
ST U7 0000 0000 01
ST B7 0008 0007 0008 00000000 0000 |abcdefgh| ||
ST A8 00000000 0000
ST A8 00000001 0100 0000 0000 0000
ST A9 00000000 01
ST END
```

Reading notes:

- A1 Flags $0080 vs A2–A7 $0000: timing of the deferred activation (§1.3), not a rule.
- No `ST M` line: no GADGETDOWN (no GADGIMMEDIATE) and no other message while editing.
- B2: '-' (not at position 0) and 'x' refused, LongInt 5912.
- B5: undo restores the text **and** BufferPos = UndoPos (1, the BufferPos at activation).
- B7 depends on the font: DispCount = 24 / 10 = 2. With a topaz 8 screen the same keys give DispPos 6.
- A8 (second line) and A9: the disabled gadget D was activated (D0 = 1) and stayed in editing; the window opened
  next with ACTIVATE did not become active, and ActivateGadget(S1) then failed (D0 = 0) with the probe's
  window still active (01). The screenshot shows D with its cursor and the second window inactive.

---

## 7. Open points — suggested additional probes

1. **Inactive window**: ActivateGadget on a string gadget of a window that is not active (activate another window
   first, with no string gadget pending). Expected 0 (§1.1 point 2), no activation later.
2. **Requester**: ActivateGadget(gad, win, NULL) with a requester up, then (gad, win, req) with the head
   requester and with a non-head requester. Expected 0, 1 (state 7), 0. Also ENDGADGET + RELVERIFY string gadget
   in a requester: does Return end the requester?
3. **Triggering event**: ActivateGadget then immediately (before any tick) a key press: the key should be
   inserted at the old BufferPos; with a SELECTDOWN outside the box: no editing at all, no message.
4. **Click placement**: click at several x inside S1 (cell boundaries, right of the text) and read BufferPos;
   also the click that ends editing on another string gadget (expected: the second starts editing at once, no
   GADGETUP for the first).
5. **Control and Latin-1 characters**: type Tab, Esc, Ctrl+A, Alt+key (e.g. Alt+S on a keymap that gives a
   Latin-1 byte), Up/Down, Help, F1; dump the buffer bytes in hex. Expected: $09, $1B, $01, the Latin-1 byte
   inserted; nothing for the others.
6. **Bytes after the NUL**: fill a buffer of MaxChars 20 with $AA after "ab", activate and type one character
   in a wide box, dump the 20 bytes. Expected: spaces from index 3 up to the visible width (capped at 18), then
   $AA.
7. **LONGINT edges**: "2147483647", "2147483648", "-2147483648", "+12", a sign typed when a sign exists, a
   digit typed before a '-', application text "12a"; read LongInt. Expected per §3.5.
8. **STRINGCENTER / STRINGRIGHT**: short text in an 80 px box, read DispPos (expected negative) and the
   cursor cell on a screenshot; then right-Amiga Q to a long text with UndoPos 0.
9. **GADGHNONE / GADGHBOX** string gadgets: screenshot of the cursor.
10. **Window font**: SetFont(window RastPort, topaz 8) on a topaz 9 screen: the gadget should still measure
    and draw in topaz 9.
11. **No RELVERIFY**: Return should end the editing without any message.

---

## Clean-room review

- [x] Contracts are described as rules on public fields (`intuition.h` 1.3 offsets), `.fd` registers, return
  values, IDCMP messages and observable buffer states. No instruction sequence, no pseudo-code of a routine, no
  ROM address. The private IB state values (10, 13) are named as states, as in `intuition-input-menus-v34.md`.
- [x] The probe lines quoted in §6 are API output of our own test program (return values, flags, StringInfo
  fields, buffer text typed by the harness), not ROM data.
- [x] Facts read in the ROM are marked [O ROM] and listed in §7 as candidates for a black-box confirmation.
