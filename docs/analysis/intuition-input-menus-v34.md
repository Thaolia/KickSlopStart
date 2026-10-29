# intuition-input-menus-v34.md — intuition 34.3 input engine (Intuition(), IDCMP) and menus

> ANALYSIS track ("dirty"). Sources: ROM `kick34005.A500` (read-only, radare2 + headless Ghidra
> decompilation to follow the control flow) and black-box probe on the real ROM under FS-UAE
> (`tests/imenu_probe.s` + `tests/imenu_probe.sh`, vectors §5). We describe the **what**: behaviours,
> orders, conditions, values, ABI layouts. No instruction sequence, no listing, no ROM routine
> address. The offsets cited are those of the public structures (NDK 1.3) or of private
> IntuitionBase (IB) fields already named by the neighbouring specs.
>
> **Legend**: **[O]** observed (read in the ROM or measured by the probe) · **[D]** deduced · **[S]** assumed.
>
> Related specs, not duplicated here: `intuiticks-repeat-v34.md` (input.device, repeat, INTUITICKS,
> VANILLAKEY), `intuition-prefs-v34.md` (handler installation, PointerTicks, DoubleClick, IB fields),
> `intuition-gzz-v34.md` §3 (MouseX/Y of windows and messages), `intuition-frame-v34.md` §4
> (active/inactive rendering), `intuition-requesters-v34.md` §3 (input during a requester),
> `intuition-prop-v34.md` §4 (proportional gadgets), `workbench-task-v34.md` §6.8 (activation
> rule at OpenWindow/CloseWindow), `disk-change-v34.md` (DISKINSERTED/REMOVED on the WB side).
> **Screens** (OpenScreen, screen title bar, ShowTitle, screen dragging) are out of scope
> (spec `intuition-screens-v34.md`, another agent).

---

## 0. Executive summary

1. Intuition's handler (priority **50**, `is_Data` = IntuitionBase) calls `Intuition(list)` and returns
   **a fresh list of copies**: whatever intuition has not turned into an IntuiMessage is copied (22
   bytes) and linked for the following handlers (console.device). The original list is never returned.
   [O]
2. An event goes **either** as IDCMP to a window (if it has the corresponding flag and a message could
   be allocated), **or** into the passed-on list — never both (except DISKINSERTED/REMOVED and
   NEWPREFS, broadcast to windows **and** passed on with `IEQUALIFIER_MULTIBROADCAST`). [O]
3. Messages come from a **per-window pool** (56-byte blocks never freed before
   CloseWindow); a message that has not been replied is never reused; **no coalescing** of MOUSEMOVE
   (only INTUITICKS is limited to one copy in circulation). [O]
4. Verifications (MENUVERIFY, SIZEVERIFY, REQVERIFY) **block the input.device task** until the
   reply: the whole input system is frozen (pointer included). [O]
5. Menus: bar drawn in the screen's title layer; boxes rendered off-screen then
   **swapped** with the screen (SwapBitsRastPortClipRect); **LockLayers** on the whole screen while the
   menu is open; intuition's state lock stays held from one event to the next (SetMenuStrip,
   ClearMenuStrip, OnMenu, OffMenu, LockIBase(0) from another task wait for the close). [O]
6. MoveWindow, SizeWindow, WindowToFront/Back, ActivateWindow are **asynchronous**: queued and
   executed at the start of processing of the next input event (≤ 100 ms thanks to the ticks); an
   ActivateWindow requested during a menu or an active gadget is **lost**. [O]

---

## 1. The input handler and `Intuition()`

### 1.1 Installation and call [O]

- Installed at the first OpenLibrary (see `intuition-prefs-v34.md` §1): `IND_ADDHANDLER`, Interrupt
  structure in IntuitionBase, `ln_Pri` = **50**, `is_Data` = IntuitionBase, `is_Code` = a relay that
  calls the public function **`Intuition(ie)` (LVO −36, A0 = list of InputEvents)** with A6 = IB and
  returns its D0 to input.device.
- A handler of priority > 50 sees the raw events before intuition; a handler of priority < 50
  (console.device) sees **only** the list returned by intuition.
- `Intuition(NULL)` returns 0 without doing anything.

### 1.2 Course of a call [O]

1. If no "long" operation is in progress (neither menu nor held gadget — private bits IB+$40 & $600),
   or if a string gadget is being edited: **acquisition of the state lock** (the first of the 7
   semaphores of IB, the one also taken by `LockIBase(0)`, along with no. 5).
2. Reset of the list to pass on (and freeing of the copies from the previous call).
3. Collection of the already-replied messages of the **active window** (§2.2).
4. Execution of the **deferred action queue** (§1.10).
5. For **each** event of the list, in order: pre-processing (§1.3), then state machine
   (§1.8).
6. If no long operation is (yet) in progress, or during string editing: **release** of the state
   lock. So **the lock stays held** from one call to the next as long as a menu is open or a
   gadget (boolean, proportional, system) is held. [O] Consequence: any function that takes this
   lock (SetMenuStrip, ClearMenuStrip, OnMenu, OffMenu, LockIBase(0), ScreenToFront…) called by another
   task **waits** for the end of the menu or the gadget. [D]
7. Return: the list of copies (head pointer), possibly empty (0).

### 1.3 Pre-processing of each event, in order [O]

1. **IECLASS_DISKINSERTED (16) / DISKREMOVED (15)**: broadcast (§2.4) then next event (no
   state machine).
2. **IECLASS_TIMER (6)**: possible INTUITICKS to the active window (`intuiticks-repeat-v34.md` §3).
3. **IECLASS_RAWKEY (1)**:
   - end of keyboard-emulated buttons: if the emulated left button is pressed (§1.7) and the
     qualifier no longer contains LALT ($10) → the event becomes RAWMOUSE code $E8 (SELECTUP); if the
     emulated right button is pressed and the qualifier no longer contains RALT ($20) → RAWMOUSE $E9;
     The released emulated button is handled **as an event inserted before** the key: the original
     keyboard event is then processed normally (the window receives MOUSEBUTTONS $E8 **then** the
     RAWKEY of the Alt release) [O, probe §5 step 13];
   - if it is a **press** (bit 7 of the code at 0): handling of the Amiga keys (§1.7), which can
     transform the event **in place** (in the original list) into RAWMOUSE or IECLASS_NULL.
   - This handling takes place **before** the timestamp update (point 4): the messages produced by
     a menu shortcut (MENUVERIFY, MENUPICK) carry the timestamp of the **previous** event
     [O, probe §5 step 7].
4. **Timestamp**: IB->Seconds/Micros (+$48/+$4C) := `ie_TimeStamp` of the event, **whatever its
   class**. At the same moment, any screen currently in DisplayBeep (flag BEEPING $0020 of
   Screen.Flags) gets its colour 0 back: **a DisplayBeep lasts until the next input event**
   (≤ 100 ms, one tick). [O]
5. **Mouse** (classes RAWMOUSE 2 and POINTERPOS 4):
   - POINTERPOS without RELATIVEMOUSE ($8000): converted to relative (formula of `intuition-prefs-v34.md` §6),
     the class becomes RAWMOUSE;
   - PointerTicks accumulation per axis (same §6); position bounded (§1.5); propagation to screens and
     windows (§1.4); pointer sprite moved to ((MouseX >> 1) + XOffset, (MouseY >> 1) + YOffset);
   - **MOUSEMOVE** (§2.4) to the active window if it has REPORTMOUSE (Window.Flags $0200) and the effective
     delta is not zero, except during a menu or a gadget if the window's layer is locked
     by the input.device task itself (the case of menus, which lock all the layers of the screen):
     **no MOUSEMOVE while a menu is open**. [O]
6. State machine (§1.8).

### 1.4 Coordinates [O]

- **IB->MouseX (+$46)** is in **high-resolution** pixels (0..639), **IB->MouseY (+$44)** in
  **interlaced** lines (0..2 × NormalDisplayRows − 1).
- After each movement, for **all** screens: Screen.MouseX = (IB.MouseX, divided by 2 if the screen
  is not HIRES) − Screen.LeftEdge; Screen.MouseY = (IB.MouseY, divided by 2 if the screen is not
  LACE) − Screen.TopEdge. For **all** windows of each screen: Window.MouseX/Y =
  Screen.MouseX/Y − LeftEdge/TopEdge; GZZMouseX/Y = Window.MouseX/Y − BorderLeft/BorderTop (see
  `intuition-gzz-v34.md` §3).

### 1.5 Pointer bounds [O]

Private fields: MinX +$50, MaxX +$52, MinY +$54, MaxY +$56 (IB units).

- Rest state (recomputed after each change of screen order, end of menu, end of drag):
  MinX = 0, MaxX = IB+$546 − 1 (NormalDisplayColumns − 1), MinY = IB+$378, MaxY = min(IB+$544,
  (TopEdge + Height) of the front screen, ×2 if it is not LACE, − 1).
- **Menu open**: MinY := TopEdge of the menu's screen (×2 if not LACE), if the pointer is below it:
  the pointer cannot leave the screen through the top.
- Dragging/resizing a window or dragging a screen: bounds restricted to keep the object on
  screen (detail: screens / windows spec, not covered here).

### 1.6 Speed and acceleration [O]

No acceleration in 1.3: the only factor is **PointerTicks** (1, 2 or 4; ROM default 2, WB 1.3:
1), applied by the accumulator (`intuition-prefs-v34.md` §6). The actual speed therefore depends on the
number of quadrature counts that gameport.device reports per event (§4).

### 1.7 Amiga keys: keyboard mouse, screen shortcuts, menu shortcuts [O]

Handling of **presses** whose qualifier contains LCOMMAND ($40) or RCOMMAND ($80):

| Key (raw code) | Qualifier | Effect |
|---|---|---|
| ← $4F / → $4E | Amiga (L or R) | the event becomes RAWMOUSE code $FF (no button), ie_X = ±speedX |
| ↑ $4C / ↓ $4D | Amiga | same in Y, ie_Y = ∓/±speedY (↑ negative) |
| Left Alt (LALT $10 in the qualifier) | Amiga | RAWMOUSE $68 (SELECTDOWN), if not already emulated |
| Right Alt (RALT $20) | Amiga | RAWMOUSE $69 (MENUDOWN), if not already emulated |
| N ($36) | **LCOMMAND** | WBenchToFront; the event becomes IECLASS_NULL (swallowed) [O ROM, not probed] |
| M ($37) | **LCOMMAND** | WBenchToBack; swallowed [O ROM, not probed] |
| any convertible key | **RCOMMAND** | menu shortcut (§3.11) |

- Speeds: X (private IB) = 1 on a simple press, **+6** on each repeat (qualifier REPEAT
  $0200), **100** if a Shift key is held; Y = 1, **+4** per repeat, **75** with Shift.
  Any other Amiga key resets the speed of the other axis to 0. These deltas then go through
  PointerTicks like a mouse movement (with PointerTicks = 2, a simple press moves by only half
  a high-resolution pixel, accumulated). [O]
- The emulated buttons are released at the first keyboard event whose qualifier no longer contains
  the corresponding Alt (§1.3), typically the release of the Alt key. [O]
- The order of the tests is: arrows, left Alt, right Alt, N/M, menu shortcut. Shift+Amiga+letter
  is therefore also a menu shortcut. [O]

### 1.8 State machine (private IB, state word) [O]

| State | Meaning | Entry | Exit |
|---|---|---|---|
| 1 | idle | init, end of any operation | — |
| 2 | waiting for the DMRequest double-click (§3.12) | MENUDOWN, window with DMRequest | timeout/movement/2nd click |
| 3 | menu open, pointer tracking | MENUDOWN accepted | MENUUP |
| 6 | boolean gadget held (RELVERIFY) | SELECTDOWN on gadget | SELECTUP |
| 7 | active window in requester | Request, activation of a window with a requester | ReqCount = 0 |
| 8 | proportional gadget held | SELECTDOWN on prop | SELECTUP |
| 9 | screen drag | SELECTDOWN on screen bar | SELECTUP |
| 10 | editing a string gadget | SELECTDOWN on string gadget | end of editing |
| 11 ($B) | right button "handed to the application" | RMBTRAP, MENUCANCEL | MENUUP |
| 12 ($C) | dragging/resizing a window (ghost frame) | SELECTDOWN on WDRAGGING/SIZING | SELECTUP |

An unknown state causes `Alert($8400000C)`. In state 1:

- class ≠ RAWMOUSE: **normal distribution** (§2.3) — except IECLASS_TIMER, never passed on;
- RAWMOUSE code $E8 / $E9 (releases): normal distribution (MOUSEBUTTONS to the active window or
  passing on);
- code $68 (SELECTDOWN): §1.9;
- code $69 (MENUDOWN): §3.3 (if there is no active window: swallowed);
- any other code (pure movement $FF, middle button $6A/$EA, codes < $68): **swallowed**, nothing
  is passed on. [O]

During states 3, 6, 8, 9, 12 all events other than those driving the operation (including
keys) are **swallowed**; only INTUITICKS and MOUSEMOVE (pre-processing) continue. In state 7
they are swallowed except for a NOISYREQ requester (`intuition-requesters-v34.md` §3.2). In state 11 they are
distributed normally (MOUSEBUTTONS SELECTDOWN included, **without** gadget test or change of
active window); pure movements are swallowed there. [O]

### 1.9 Left button (SELECTDOWN) in the idle state [O]

1. **Window under the pointer**: screens walked from the first (front) to the last, skipping screens
   whose ViewPort is hidden (VP_HIDE $2000); in each, `WhichLayer` at (Screen.MouseX, Screen.MouseY):
   - layer found = **the screen's title bar** → the chosen window is **the current active
     window** (no change) and the screen is noted for its gadgets;
   - other layer → its window (`Layer->Window`);
   - no layer and the pointer is below the top of this screen → **no window (NULL)**;
   - otherwise (pointer above this screen) → next screen.
2. If this window ≠ active window: **activation** (§1.11), including with NULL (click on the background
   of a screen without a backdrop window: no active window any more). If the new window has
   requesters, the event is reprocessed in state 7.
3. **Gadget search** (in the now-active window): screen gadgets if the click is on the bar;
   otherwise gadgets of the first requester if the click is on its layer; otherwise `FirstGadget`. First gadget
   (in list order) whose box contains the point:
   - if it is GADGDISABLED ($0100): **no gadget** (it masks those beneath);
   - if the window has a requester and the gadget is neither REQGADGET ($1000) nor SYSGADGET ($8000):
     none;
   - the close gadget (type $80) is ignored when a requester is present.
   The click that activates a window **also acts** on the targeted gadget (no "activation-only" click).
4. Gadget found: selection and rendering; GADGIMMEDIATE ($0002) ⇒ **GADGETDOWN**; otherwise, FOLLOWMOUSE ($0008)
   ⇒ an immediate MOUSEMOVE at the current position; FOLLOWMOUSE sets REPORTMOUSE on the window for the
   duration of the gadget (the previous state is restored at the end). Then according to the type:
   - boolean without RELVERIFY: immediate end (deselection except TOGGLESELECT, no GADGETUP);
   - boolean RELVERIFY: state 6; at SELECTUP, pointer **inside** ⇒ **GADGETUP** (or system action:
     depth, close ⇒ CLOSEWINDOW); **outside** ⇒ **MOUSEBUTTONS SELECTUP** (no GADGETUP);
   - proportional: state 8 (`intuition-prop-v34.md`), GADGETUP on release if RELVERIFY;
   - string: state 10;
   - unknown type (2 or > 4 outside system types): `Alert($04000001)` (recoverable);
   - SIZING ($10): SIZEVERIFY first (§2.5), then state 12; WDRAGGING ($20): state 12; SDRAGGING ($30):
     state 9.
5. No gadget: **MOUSEBUTTONS SELECTDOWN** ($68) to the active window (or passing on).
   A SELECTDOWN on a gadget does **not** produce MOUSEBUTTONS. [O]

### 1.10 Deferred actions (IB queue, 18-byte nodes) [O]

These functions **do not act immediately**: they deposit a request (node reused if it is
free, otherwise public AllocMem; failure ⇒ `Alert($8400000E)`) and return.

| Request | Deposited by | Execution |
|---|---|---|
| activate a window | ActivateWindow; OpenWindow with ACTIVATE; CloseWindow of the active window (successor, `workbench-task-v34.md` §6.8); CloseScreen | §1.11, then event IECLASS_EVENT code 1 passed on |
| repair a screen | CloseWindow, EndRequest, ShowTitle | damaged layers, REFRESHWINDOW (§2.4) |
| NEWPREFS | SetPrefs(…, inform = TRUE) | NEWPREFS broadcast (§2.4) |
| MoveWindow / SizeWindow | MoveWindow / SizeWindow | move / size, then NEWSIZE (§2.4) |
| WindowToFront / WindowToBack | same | change of layer order |
| REQSET / REQCLEAR | Request / EndRequest | message (§2.4) |
| "requester" control | Request | switch to state 7 |

- The queue is executed **at the start of each call to Intuition()** (so at the next event: at most
  ≈ 100 ms thanks to IECLASS_TIMER), in deposit order, **before** the events of that call.
  The timestamp of the messages produced is that of the last processed event.
- During a menu or a held gadget: **activations are dropped** (node freed without effect);
  Move/Size/ToFront/ToBack/requester control concerning the **active screen** stay queued until
  the end of the operation; the others (other screens, REQSET/REQCLEAR, NEWPREFS) are executed. [O]

### 1.11 Activation and deactivation [O]

Common routine (click, deferred queue):
1. old active window ≠ NULL: **INACTIVEWINDOW** (target = the old one), then "inactive" rendering
   (`intuition-frame-v34.md` §4.2);
2. ActiveWindow := new one; current menu codes reset to MENUNULL; if NULL: end;
3. working flags of the window's menus cleared (§3.8), **WINDOWACTIVE** ($2000) set,
   **ACTIVEWINDOW** (target = the new one);
4. if Screen.Title ≠ Window.ScreenTitle: the screen title takes the window's and the bar is
   redrawn; ActiveScreen := the window's screen; mouse coordinates recomputed for the window;
   window's pointer installed; window's title bar redrawn if it has a title or DRAG.

After an activation by click, intuition additionally passes on an event **IECLASS_EVENT (3) code 1**
whose `ie_EventAddress` = the new active window (for console.device); this is also the case for a
deferred activation. [O]

---

## 2. IntuiMessages (IDCMP)

### 2.1 Mapping event class → IDCMP class [O]

| ie_Class | Condition | IDCMP | Message code |
|---|---|---|---|
| $0C SIZEWINDOW | — | NEWSIZE $2 | 0 |
| $0D REFRESHWINDOW | — | REFRESHWINDOW $4 | 0 |
| $02 RAWMOUSE | code ≠ $FF | MOUSEBUTTONS $8 | $68/$E8/$69/$E9 |
| $02 RAWMOUSE | code = $FF | MOUSEMOVE $10 | $FF |
| $07 GADGETDOWN | — | GADGETDOWN $20 | 0 |
| $08 GADGETUP | — | GADGETUP $40 | 0 |
| $09 REQUESTER | code ≠ 0 | REQSET $80 | 1 |
| $09 REQUESTER | code = 0 | REQCLEAR $1000 | 0 |
| $0A MENULIST | — | MENUPICK $100 | menu code |
| $0B CLOSEWINDOW | — | CLOSEWINDOW $200 | 0 |
| $01 RAWKEY | window without VANILLAKEY | RAWKEY $400 | raw code |
| $01 RAWKEY | window with VANILLAKEY | VANILLAKEY $200000 | character (§2.6) |
| $0E NEWPREFS | — | NEWPREFS $4000 | 0 |
| $10 DISKINSERTED | — | DISKINSERTED $8000 | 0 |
| $0F DISKREMOVED | — | DISKREMOVED $10000 | 0 |
| $11 ACTIVEWINDOW | — | ACTIVEWINDOW $40000 | 0 |
| $12 INACTIVEWINDOW | — | INACTIVEWINDOW $80000 | 0 |
| $06 TIMER | — | INTUITICKS $400000 | 0 |

- Outside the table: SIZEVERIFY $1, REQVERIFY $800, MENUVERIFY $2000 (sent by the verification
  mechanism §2.5); **WBENCHMESSAGE $20000 is never emitted by intuition 34.3**; DELTAMOVE
  $100000 is not a class but modifies MouseX/Y (§2.3). [O]

### 2.2 Construction, pool and life cycle [O]

- **Per-window pool**: singly linked list (private window field `MessageKey`, +$5E; link
  in the message's `SpecialLink` +$30). A **free** message has `Class = $80000000`. Allocation: the
  first free one is taken; otherwise AllocMem(**56**, MEMF_PUBLIC|MEMF_CLEAR), `ln_Type` = NT_MESSAGE, added at the head.
  The blocks are freed only when the window is closed.
- **Collection** of replied messages: by GetMsg on the window's **WindowPort** (+$5A), (a) at the
  start of each call to Intuition() for the active window, (b) before each allocation for the
  target window. Each collected message becomes free again ($80000000); if it was an INTUITICKS, the
  WINDOWTICKED flag is cleared. A message found in the WindowPort that is not NT_REPLYMSG ⇒
  `Alert($8400000D)`.
- **A message that has not been replied is never reused**: an application that does not reply makes the
  pool grow by 56 bytes per message, without limit. If AllocMem fails, the message is not sent and
  **the event is passed on instead** (console). [O; console consequence D]
- Sending: under Forbid, `PutMsg(UserPort)`; the WindowPort is PA_IGNORE (no signal to intuition).
- Fields filled in (common):

| Field | Offset | Value |
|---|---|---|
| `mn_ReplyPort` | +$0E | the window's WindowPort |
| `mn_Length` | +$12 | **$20** (fixed value, not the real size) |
| `Class` | +$14 | IDCMP class (§2.1) |
| `Code` | +$18 | see §2.1 / §2.4 |
| `Qualifier` | +$1A | `ie_Qualifier` of the event |
| `IAddress` | +$1C | `ie_EventAddress` of the copy of the event (see §2.3); RAWKEY: address of a copy, in the message (+$34), of the 4 bytes of dead-key history |
| `MouseX/MouseY` | +$20/+$22 | Window.MouseX/MouseY; with **DELTAMOVE**: `ie_X/ie_Y` of the original event |
| `Seconds/Micros` | +$24/+$28 | IB->Seconds/Micros = timestamp of the current event (§1.3) |
| `IDCMPWindow` | +$2C | the window |

- Ports: ModifyIDCMP/OpenWindow create two ports named **"IDCMP"** (added to the public list
  by AddPort): UserPort (signal allocated in the calling task) and WindowPort (signal freed, PA_IGNORE).

### 2.3 Target window and IAddress [O]

| Classes | Target window | IAddress |
|---|---|---|
| MOUSEBUTTONS, MOUSEMOVE, INTUITICKS, ACTIVEWINDOW, INACTIVEWINDOW | active window (for INACTIVEWINDOW: the old one) | **the window** — except the MOUSEBUTTONS MENUUP sent when a menu closes (§3.9): raw value of the event [O, probe] |
| GADGETDOWN, GADGETUP | active window | **the gadget** |
| REQSET, REQCLEAR, REFRESHWINDOW | window designated by the event | **the window** |
| RAWKEY, VANILLAKEY, MENUPICK, CLOSEWINDOW, **NEWSIZE** | **active window** | raw value of `ie_X/ie_Y` of the event (RAWKEY: §2.2) — meaningless |
| DISKINSERTED/REMOVED, NEWPREFS | all requesting windows (§2.4) | raw value |

- **NEWSIZE always goes to the active window**: a SizeWindow on an inactive window sends the NEWSIZE
  to the active window (or passes it on if the latter does not request it). [O, 1.3 defect]
- No active window, window without IDCMP, or flag absent ⇒ the event is **passed on**
  (copy, `ie_EventAddress` = the target window for the classes of the 1st row; a passed-on MOUSEBUTTONS
  keeps its original deltas). [O]

### 2.4 Class by class [O unless stated]

- **MOUSEBUTTONS**: SELECTDOWN without gadget (§1.9), SELECTUP outside a gadget or outside a held RELVERIFY
  gadget, MENUDOWN/MENUUP with RMBTRAP or after MENUCANCEL (§3.10), MENUUP to windows in
  MENUVERIFY when a menu closes (§3.9). Never for the middle button.
- **MOUSEMOVE**: §1.3 point 5; one message **per movement event**, no coalescing; Code $FF.
- **GADGETDOWN / GADGETUP**: §1.9; Code 0.
- **REQSET**: Code 1, at each successful Request (deferred) and at the opening of a DMRequest; **REQCLEAR**:
  Code 0, at each EndRequest (deferred) and at each requester terminated by ENDGADGET
  (`intuition-requesters-v34.md` §3.3).
- **MENUPICK**: §3.9 and §3.11; Code = first code of the chain or MENUNULL ($FFFF).
- **CLOSEWINDOW**: release **inside** the close gadget (type $80); Code 0.
- **NEWSIZE**: at the end of each SizeWindow (dragging of the size gadget included), even if the size could
  not change. See the target §2.3.
- **REFRESHWINDOW**: at each screen repair (end of menu, end of drag, CloseWindow, EndRequest…),
  for each window whose layer is damaged (LAYERREFRESH) and **without NOCAREREFRESH**; with
  NOCAREREFRESH, intuition does the Begin/EndRefresh itself. The frame (and the GZZ border layer)
  is redrawn before the message.
- **ACTIVEWINDOW / INACTIVEWINDOW**: §1.11.
- **DISKINSERTED / DISKREMOVED / NEWPREFS**: for each screen, each window that has the flag; then
  the event is **also** passed on with `ie_Qualifier |= $0800` (MULTIBROADCAST).
- **RAWKEY / VANILLAKEY / INTUITICKS**: `intuiticks-repeat-v34.md` §3 and §5, detailed in §2.6.

### 2.5 Verifications: SIZEVERIFY, MENUVERIFY, REQVERIFY [O]

Common mechanism `verify(window, class, code)`:
1. the window does not have the flag ⇒ returns "1" (continue without waiting);
2. message allocated (failure ⇒ returns **4**); Code = requested code; IAddress = `ie_EventAddress`; MouseX/Y =
   Window.MouseX/Y (**no** DELTAMOVE here); IB records the window and the pending message;
3. the WindowPort switches to **PA_SIGNAL** towards the **input.device task** (signal allocated for the occasion),
   `PutMsg(UserPort)`, **release of the state lock**, then wait: the input.device task is
   **blocked** — no more events are processed (pointer frozen, keyboard waiting);
4. each replied message that arrives is made free again; when it is the expected message: **its Code
   at the time of the reply** is returned; if the wait has been cancelled (below): returns 4;
5. reacquisition of the lock, freeing of the signal, WindowPort back to PA_IGNORE.

Cancellation: ModifyIDCMP that removes the awaited class (or closes the IDCMP) for the waiting window:
the message is removed from the UserPort (Remove), its Code set to 4, it is replied, and the input.device task is
woken up (result 4). [O]

Uses:
- **MENUVERIFY** ($2000): Code **MENUHOT (1)** to the active window at MENUDOWN and at the keyboard shortcut;
  the application can reply Code = **MENUCANCEL (2)** to cancel (§3.10); Code **MENUWAITING (3)** to the
  **other** windows of the active screen that have MENUVERIFY, **one by one** (each waits for its reply),
  just before the menu actually opens; their reply is ignored.
- **SIZEVERIFY** ($1): Code 0, at SELECTDOWN on the size gadget; only result 4 (failure or
  cancellation) prevents the resize, the reply Code is ignored.
- **REQVERIFY** ($800): Code 0, **only** before the opening of a DMRequest (§3.12); only 4 prevents
  the opening. Request() sends no REQVERIFY. [O]

### 2.6 Details per feature [O]

- **No reply**: an application that does not read its port prevents nothing (except verifications, which
  block everything); its messages accumulate (§2.2); only INTUITICKS is limited to one copy.
- **REPORTMOUSE**: Window.Flags $0200, set/cleared by `ReportMouse(bool D0, window A0)` under Forbid
  (only the low word of D0 is tested); immediate effect. **FOLLOWMOUSE**: §1.9.
- **RMBTRAP** ($00010000 of Window.Flags, no API in 1.3): MENUDOWN ⇒ **MOUSEBUTTONS $69** to the active
  window, state 11; MENUUP ⇒ MOUSEBUTTONS $E9. The test is made on the window that is **active** at the time of the
  MENUDOWN.
- **DELTAMOVE**: MouseX/Y of messages = `ie_X/ie_Y` of the event (for MOUSEMOVE: the effective delta
  after PointerTicks; for a RAWKEY: the history bytes; for buttons: the delta carried by
  the event, generally 0).
- **VANILLAKEY**: if the active window has VANILLAKEY, each RAWKEY is converted by
  `RawKeyConvert(ie, buffer, 1, default keymap)`: a press yielding **exactly one** character ⇒
  VANILLAKEY (Code = character); **everything else** (releases, keys without a character, dead
  keys) is **swallowed** — neither RAWKEY (even if RAWKEY is also requested), nor passing on. [O]
- **CurrentTime(secs, micros)** returns IB->Seconds/Micros: the timestamp of the **last input event
  processed**, not the current time (at worst 100 ms late). [O]
- **DoubleClick(s1, µ1, s2, µ2)**: true if (s2 − s1, µ2 − µ1) — with a borrow of one second if µ2 < µ1 —
  is **strictly** less than the double-click duration of the prefs (IB+$336/$33A). No sign
  test: a time 2 earlier than time 1 returns true. Intuition itself uses it only for the
  DMRequest. [O]
- **ModifyIDCMP(window A0, flags D0)**: under Forbid; cancels a pending verification whose
  class disappears; flags = 0 ⇒ IDCMPFlags := 0, UserPort signal freed, **messages still
  present in the UserPort replied** (Code set to 4), UserPort and WindowPort deleted (RemPort, FreeMem
  34 bytes); flags ≠ 0 ⇒ ports created if missing, IDCMPFlags := flags. [O]

---

## 3. Menus

### 3.1 Structures and codes (ABI) [O]

- `Menu` (30 bytes): NextMenu +0, LeftEdge +4, TopEdge +6, Width +8, Height +10, Flags +12
  (MENUENABLED $0001, MIDRAWN $0100), MenuName +14, FirstItem +18, JazzX +22, JazzY +24, BeatX +26,
  BeatY +28.
- `MenuItem` (34 bytes): NextItem +0, LeftEdge +4, TopEdge +6, Width +8, Height +10, Flags +12, MutualExclude
  +14, ItemFill +18, SelectFill +22, Command +26, SubItem +28, NextSelect +32. Flags: CHECKIT $1, ITEMTEXT $2,
  COMMSEQ $4, MENUTOGGLE $8, ITEMENABLED $10, HIGHFLAGS $C0 (HIGHIMAGE 0, HIGHCOMP $40, HIGHBOX $80,
  HIGHNONE $C0), CHECKED $100, ISDRAWN $1000, HIGHITEM $2000, MENUTOGGLED $4000.
- **Menu code** (16 bits): menu = bits 0–4 (NOMENU $1F), item = bits 5–10 (NOITEM $3F),
  sub-item = bits 11–15 (NOSUB $1F). MENUNULL = $FFFF.
- Window: MenuStrip +$1C, Flags MENUSTATE $8000 (set during the menu), RMBTRAP $10000, CheckMark +$64,
  DetailPen +$62, BlockPen +$63.

### 3.2 Functions [O]

- **SetMenuStrip(window A0, menu A1)**: takes the state lock; Window.MenuStrip := menu; for
  **each** menu, computes the bounding box of its items (§3.5, sub-items excluded); if its top
  is < 0 ⇒ `Alert($84000006)`; then left −= MenuHBorder, top −= MenuVBorder, right += MenuHBorder,
  bottom += MenuVBorder; left brought back to 0 if > 0; right raised to Menu.Width − 1 if smaller;
  result in JazzX, JazzY, BeatX, BeatY. **The borders are read from the active screen**
  (IntuitionBase->ActiveScreen), not from the window's screen. Returns TRUE. No drawing.
- **ClearMenuStrip(window)**: under the state lock, MenuStrip := NULL. Nothing else.
- **OnMenu / OffMenu(window A0, code D0)**: menu = NOMENU ⇒ nothing; under the state lock: item NOITEM ⇒
  MENUENABLED bit of the menu; sub-item NOSUB ⇒ ITEMENABLED of the item; otherwise ITEMENABLED of the
  sub-item. **No refresh** (the bar is visible only during a menu and it is
  redrawn at each opening).
- **ItemAddress(menu A0, code D0)**: menu NOMENU ⇒ NULL; item NOITEM ⇒ **NULL** (not the menu);
  sub-item NOSUB ⇒ the item, otherwise the sub-item. No lock, **no bounds check**:
  a number beyond the list follows a NULL pointer.

### 3.3 Opening (MENUDOWN in state 1, without RMBTRAP) [O]

1. Active window mandatory (otherwise the event is swallowed).
2. **MENUVERIFY MENUHOT** to the active window (§2.5): reply MENUCANCEL ⇒ state 11 (§3.10); result 4
   or active window changed in the meantime ⇒ abort (state 1).
3. Menu bar drawn (§3.4).
4. Window with **DMRequest** ⇒ §3.12 (state 2).
5. **MENUWAITING** to the other windows of the active screen that have MENUVERIFY (one by one).
6. If the active window has changed: bar removed, MENUUP to the windows in MENUVERIFY (§3.9), end.
7. Otherwise: first selected code := MENUNULL; "displayed" and "highlighted" codes := MENUNULL;
   Window.Flags |= **MENUSTATE**; **LockLayers(&Screen->LayerInfo)** (all layers of the screen);
   immediate pointer tracking (§3.7); MinY bound (§1.5); state 3.

### 3.4 Menu bar [O]

- Drawn in the **layer of the screen's title bar**, first brought in front of all the others
  (BACKDROP flag of this layer cleared, UpfrontLayer).
- Background: filled rectangle (0, 0)–(Screen.Width − 1, BarHeight − 1) in the **BlockPen of the active window**.
- Title of each menu that has a MenuName: IntuiText {FrontPen = **DetailPen of the window**, BackPen =
  BlockPen, **JAM2**, LeftEdge = BarHBorder, TopEdge = BarVBorder, font = `Screen->Font`} printed at
  (Menu.LeftEdge, 0), hence text at x = LeftEdge + BarHBorder, y = BarVBorder.
- A menu without MENUENABLED still opens: title not highlighted, box displayed with all its
  items ghosted, any selection gives MENUNULL [O, probe]. Its title is "ghosted" by a pattern fill over (BarHBorder + LeftEdge, 0)–(BarHBorder
  + LeftEdge + Width − 1, BarHeight − 1), 2-line pattern **$4444 / $1111**, colour BlockPen, JAM1.
- Closing: the screen's title bar is rebuilt (screen title) and the layer goes back
  behind according to ShowTitle (screens spec).

### 3.5 Item and sub-item boxes [O]

**Bounding box of a list of items** (SetMenuStrip, sub-menus): union, for each item, of
its rectangle (LeftEdge, TopEdge, Width, Height) and of the extents of ItemFill and SelectFill offset by
(LeftEdge, TopEdge). Extent of a rendering: image ⇒ (L, T, L + W − 1, T + H − 1); IntuiText ⇒ (L, T,
L + IntuiTextLength − 1, **font height − 1**) — the bottom does not take TopEdge into account; NULL rendering ⇒
the item's rectangle.

**Item box of a menu** (screen coordinates):
- x0 = Menu.LeftEdge + BarHBorder + JazzX, x1 = Menu.LeftEdge + BarHBorder + BeatX; if x0 < 0, the box
  is shifted right to start at 0;
- y0 = **BarHeight − 1** (JazzY is not used), y1 = BarHeight − 1 + MenuVBorder + BeatY.
- Origin of the items: (Menu.LeftEdge + BarHBorder, BarHeight − 1 + MenuVBorder); the item is at
  (origin.x + LeftEdge, origin.y + TopEdge).

**Sub-item box**: bounding box of the sub-items, widened by MenuHBorder/MenuVBorder;
left ≤ Item.Width − 1, right ≥ 0, top ≤ Item.Height − 1, bottom ≥ 0; then translated by
(Menu.LeftEdge + BarHBorder + Item.LeftEdge, BarHeight − 1 + MenuVBorder + Item.TopEdge). The
sub-items are relative to the (LeftEdge, TopEdge) corner of their item.

**Rendering of a box**: into an off-screen BitMap (same depth, AllocRaster per plane, width aligned
on 16 pixels; **allocation failure ⇒ the box is simply not displayed**):
1. background SetRast **BlockPen** (of the active window);
2. frame in **DetailPen**, JAM1: vertical sides **2** pixels thick, top and bottom **1** line;
3. for each item: ItemFill (image or text according to ITEMTEXT), font = `Screen->Font`;
   - CHECKIT + CHECKED: image `Window->CheckMark` at (x of the item, y of the item + TopEdge of the
     ItemFill);
   - COMMSEQ: character `Command` at x = x_item + Width − char_width − 2, same y, IntuiText
     {DetailPen, 0, JAM1, current font}; Amiga symbol just to the left (x − image_width − 2);
   - item without ITEMENABLED, or menu disabled (for sub-items: menu **or** item
     disabled): ghosted with pattern $4444/$1111 in BlockPen, JAM1, over the item's rectangle.
4. **SwapBitsRastPortClipRect** (layers) between this BitMap and the screen's RastPort: the box appears and
   the screen content is preserved; closing redoes the swap. Layers are not used.

Internal images (Image, PlanePick 1, PlaneOnOff 0, placed in chip): high-resolution checkmark
LeftEdge 2, 15 × 8; low-resolution checkmark LeftEdge 2, 9 × 8; high-resolution Amiga symbol 23 × 8,
low resolution 14 × 8 (choice according to HIRES of the screen's ViewPort). The bits at 1 are the **background** (colour
1) and the drawing is in 0 (colour 0): these images assume BlockPen = 1. Patterns (# = 1):

```
checkmark hires (15x8) checkmark lores (9x8) Amiga hires (23x8)        Amiga lores (14x8)
############...        ######...           ##...................##     #............#
###########..##        ######...           ..............####.....     ........###...
##########..###        #####..##           ............######.....     .......####...
#########..####        #####..##           ..........###..###.....     ......##.##...
....####..#####        ..##..###           ........###....###.....     .....##..##...
##...##..######        ...#..###           ......############.....     ....#######...
###.....#######        #....####           ...######.....######...     ..####..####..
####...########        ##...####           ##...................##     #............#
```

### 3.6 Highlighting [O]

- **Title**: COMPLEMENT (mask $FF) over (Menu.LeftEdge + **BarVBorder**, 0, Width, BarHeight) in the
  screen's RastPort, only if MENUENABLED. Note BarVBorder (and not BarHBorder as for the text).
- **Item / sub-item** (only if menu, item — and for a sub-item, itself — are
  ITEMENABLED/MENUENABLED), at (x, y) = screen position of the item (§3.5), in the screen's RastPort:
  - HIGHCOMP: RectFill COMPLEMENT (x, y)–(x + W − 1, y + H − 1);
  - HIGHBOX: COMPLEMENT frame **on the outside**: (x − 4, y − 2, W + 8, H + 4), sides of 4 pixels,
    top/bottom of 2 lines;
  - HIGHIMAGE: draws SelectFill (or ItemFill to turn off);
  - HIGHNONE: nothing.
  The item's HIGHITEM bit follows the on/off state.

### 3.7 Pointer tracking (state 3, at each event) [O]

Position tests (coordinates of the **active screen**):
- title n: Screen.MouseX − **BarVBorder** ∈ [LeftEdge, LeftEdge + Width) and Screen.MouseY ∈ [0, BarHeight);
- item: x = Screen.MouseX − BarVBorder − Menu.LeftEdge, y = Screen.MouseY − BarHeight − MenuVBorder + 1,
  within [LeftEdge, LeftEdge + Width) × [TopEdge, TopEdge + Height); sub-item: same, minus (Item.LeftEdge,
  Item.TopEdge). The first item of the list containing the point wins; disabled items
  are "hit" (they become the current item) but are neither highlighted nor selectable.

Rules (in order, stop at the first case that applies):
1. A sub-item box is displayed: pointer on a sub-item ⇒ (if different from the current one)
   turn off the old one, turn the parent item back on if it was off, turn on the new one; otherwise turn off
   the old sub-item and continue.
2. An item box is displayed: pointer on an item ⇒ (if different) remove the sub-item
   box, turn off the old item, turn on the new one; **if it has sub-items, their box
   is displayed immediately** (without delay) and the sub-item under the pointer possibly turned on.
   Otherwise (outside the items): the item is turned off; **the sub-item box stays displayed**; current
   item := NOITEM; continue.
3. Pointer on a title: remove the sub-item box; if it is another menu, remove the item
   box, turn off the old title, turn on the new one and display its box; current item and
   sub-item := none.
4. Elsewhere: nothing changes (the last menu stays displayed).

### 3.8 Selection: CHECKIT, MENUTOGGLE, MutualExclude, NextSelect chain [O]

When a menu opens (and when a window is activated), in the **whole** bar: Menu.Flags &= ~MIDRAWN;
items &= ~(MENUTOGGLED | HIGHITEM | ISDRAWN); sub-items &= ~(MENUTOGGLED | HIGHITEM).

"Select the current code" (at MENUUP; at each event as long as the **left** button is held
during the menu; at SELECTDOWN during the menu, after clearing MENUTOGGLED everywhere):
1. item NOITEM ⇒ nothing; menu not MENUENABLED ⇒ nothing; item not ITEMENABLED ⇒ nothing; item having
   sub-items but pointer on none ⇒ nothing; sub-item not ITEMENABLED ⇒ nothing.
2. CHECKIT: if MENUTOGGLED is already set (already toggled since the last click) ⇒ **complete stop**;
   otherwise CHECKED set if it was not, or cleared if it was **and** MENUTOGGLE is present;
   MENUTOGGLED set.
3. NextSelect of the item := MENUNULL, then **chaining**: if the head (first code) is MENUNULL it
   becomes this code. Otherwise the chain is walked from the head: a link that pointed to this code
   takes the item's NextSelect (MENUNULL) — which **cuts** the chain at that point — and the code is
   appended at the tail. Special case: if the item **is** the head, its NextSelect has just been reset to
   MENUNULL and the chain is reduced to the head. [O; verified by the probe §5]
4. **MutualExclude**: for each bit i at 1 (i = rank in the list of items — or of the sub-items
   of the same item), the i-th sibling that is CHECKIT and CHECKED loses CHECKED (the bit of the item itself
   is not excluded: it would uncheck itself). Applied even if the item is not CHECKIT.
5. If a CHECKED has changed and the box is displayed: the box concerned is redrawn (removed, rendered,
   put back) and the item turned back on.

### 3.9 Closing (MENUUP in state 3) [O]

Order: selection of the current code (§3.8); current codes := MENUNULL; MENUSTATE cleared; pointer
bounds restored; sub-item box then item box removed; **UnlockLayers**; screen title
bar restored, repair of damaged layers (possible REFRESHWINDOWs); **MOUSEBUTTONS
MENUUP** ($E9) to **all** windows of the active screen that have MENUVERIFY **and** MOUSEBUTTONS (active window
included); finally **MENUPICK** to the active window, Code = head of the chain (MENUNULL if nothing).
The title left highlighted is not "turned off" separately: the bar is rebuilt. [O]

- Left button during the menu: SELECTDOWN ⇒ MENUTOGGLED cleared everywhere, selection of the current code, and
  as long as the left one is held each event selects the code under the pointer (drag-
  selecting); SELECTUP ⇒ end of this mode. These buttons produce no message. [O]

### 3.10 MENUCANCEL, RMBTRAP [O]

- Reply **MENUCANCEL** to MENUHOT: no menu, no bar, no MENUWAITING; state 11: the
  following events are distributed normally; at MENUUP, the active window receives **MOUSEBUTTONS
  $E9** (if it has MOUSEBUTTONS). The MENUDOWN itself is not resent.
- **RMBTRAP**: §2.6; MENUDOWN and MENUUP arrive as MOUSEBUTTONS.

### 3.11 Keyboard shortcuts (right Amiga) [O]

Conditions: press, qualifier with RCOMMAND ($80), conversion by `RawKeyConvert` (default keymap)
into exactly one character, `char & $5F` ≠ 0, active window **without** INREQUEST ($4000), MENUSTATE ($8000) or
RMBTRAP ($10000).
1. Search in the active window's bar, in the order menus → items → sub-items: for an
   item **without** sub-items, compare `Command & $5F`; for an item **with** sub-items, compare
   **only** its sub-items. The COMMSEQ flag **is not tested** (only `Command` counts). The
   first one found wins. Nothing found ⇒ the event continues as a normal key (RAWKEY…).
2. Found: MENUVERIFY MENUHOT to the window if it has it; reply MENUCANCEL ⇒ no selection; otherwise
   reset of the working flags (as for an opening) and selection of the code (§3.8, without drawing) —
   which refuses disabled menus, items or sub-items.
3. **MENUPICK** to the active window with the code, **or MENUNULL** if the selection was refused or cancelled.
4. The event is swallowed (class IECLASS_NULL): the key release, however, arrives normally.

### 3.12 DMRequest (right double-click) [O]

If the active window has a DMRequest (Window +$28) at an accepted MENUDOWN: the **bar** is displayed, the
layers are not locked, start time := timestamp of the event, position := the window's
mouse position; state 2. Then, for each event:
- pointer within a window of **±10 pixels in X and ±5 in Y** around the start and `DoubleClick` true:
  - second MENUDOWN (after a release): bar removed; **REQVERIFY** (Code 0); if the window is
    still active: the requester receives REQACTIVE; if it is POINTREL, LeftEdge/TopEdge := (RelLeft +
    MouseX, RelTop + MouseY) brought back inside the window (minus the borders if GIMMEZEROZERO); `Request()`;
    success ⇒ **REQSET** (Code 1) and state 7;
  - first release (MENUUP): bar removed, waiting for the second click;
  - other mouse event or tick: keep waiting;
  - other class (key…): if the button has already been released ⇒ bar removed and **MENUPICK MENUNULL**;
    otherwise the menu opens normally.
- outside the position window or timeout exceeded: button still held ⇒ **normal menu** (§3.3 point 5,
  the current event is already treated as a menu event); button released ⇒ **MENUPICK
  MENUNULL** and bar removed.

### 3.13 What is frozen during a menu [O unless stated]

- **All the layers of the menu's screen are locked** (LockLayers): any task that draws in
  a window of this screen (or creates/moves a layer) **waits** for the close. The other screens are
  not affected. [O; blocking of tasks: D, by the semantics of LockLayers]
- Intuition's **state lock** stays held (§1.2): SetMenuStrip, ClearMenuStrip, OnMenu, OffMenu,
  LockIBase(0)… called by another task wait.
- Deferred actions: §1.10 (activation lost, others postponed).
- No MOUSEMOVE, no keys (swallowed); INTUITICKS continue.
- During each **verification wait** (MENUVERIFY, SIZEVERIFY, REQVERIFY): the input.device task
  is blocked, nothing moves any more (pointer included), but the state lock is released.
- Dragging/resizing a window (state 12): LockLayers too, ghost frame in XOR. [O]

---

## 4. What differs on a real A500 [D unless stated]

- **Mouse speed**: the ROM does no acceleration (§1.6). A real mouse reports its
  counts through gameport.device at each frame in which it moved; with PointerTicks = 1 (WB 1.3 prefs), one
  count = one high-resolution pixel = ½ low-resolution pixel. An emulator that converts the
  host mouse movements with another factor, or that groups movements, changes the feel
  but not the logic. [O for the ROM]
- **Double-click**: prefs duration (ROM 1.5 s; WB 1.3 1.1968 s, `intuition-prefs-v34.md`) compared with the
  `ie_TimeStamp` set by input.device (TR_GETSYSTIME): granularity of one frame (20 ms PAL, 16.7 ms NTSC).
- **Latencies**: deferred actions and the end of DisplayBeep wait for the next event; without
  activity, that is the 100 ms tick (5 PAL frames, 6 NTSC). Identical on real hardware.
- **Verifications**: an application slow to reply to MENUVERIFY really freezes the sprite pointer
  (no movement is applied while the input.device task is waiting); mouse movements
  during the wait are accumulated by gameport/the hardware and applied in one go afterwards.
- **Blitter and chip RAM**: menu boxes are rendered off-screen (AllocRaster ⇒ chip RAM) then
  swapped by the blitter; with little free chip, a box may not be displayed at all (§3.5);
  on an A500 512 KB + 512 KB "slow", only chip counts.
- **Keyboard**: without a mouse, Amiga + arrows/Alt (§1.7) remain usable; repeat adds
  the +6/+4 acceleration per repeat (rate = KeyRptSpeed).

---

## 5. Test vectors (real ROM 34.5, FS-UAE)

**Setup**: `tests/imenu_probe.sh <output> [duration]` (probe `tests/imenu_probe.s`, two-stage bootblock,
**without DOS or Workbench**: ROM default preferences, hence PointerTicks = 2 and screen font
topaz **9** — 10 pixels wide). Two windows on the Workbench screen: **A** (0, 12, 400 × 120,
IDCMP $C37FE = NEWSIZE|REFRESHWINDOW|MOUSEBUTTONS|MOUSEMOVE|GADGETDOWN|GADGETUP|REQSET|MENUPICK|
CLOSEWINDOW|RAWKEY|REQCLEAR|MENUVERIFY|ACTIVEWINDOW|INACTIVEWINDOW, ACTIVATE, bar of 3 menus) and
**B** (420, 12, 210 × 100, IDCMP MOUSEBUTTONS|MENUVERIFY|ACTIVEWINDOW|INACTIVEWINDOW|RAWKEY, no menu).
Menus: "Projet" (LeftEdge 0, Width 64; items 140 × 10 at TopEdge 0/10/20/30: "Ouvrir", "Quitter"
COMMSEQ 'Q', "Grise" disabled, "Sous-menu" HIGHBOX with two sub-items at (100, 0) and (100, 10), the second
COMMSEQ 'S'), "Option" (72, 72: "Bascule" CHECKIT|MENUTOGGLE, "Excl A" CHECKIT MutualExclude %100, "Excl B"
CHECKIT|CHECKED MutualExclude %010), "Off" (152, 56, disabled; one item COMMSEQ 'D').
The events are **injected by input.device IND_WRITEEVENT** (absolute IECLASS_POINTERPOS positions
in IB units, buttons, keys) with `ie_TimeStamp` = (step, rank); the log (`M win Class Code
Qualifier IAddress MouseX MouseY Seconds Micros`) is read back over serial. Two runs give identical
logs (except for tick timestamps).

**Measured geometry** [O]: WB screen 640 × 256; BarHeight 11, BarVBorder 1, BarHBorder 5, MenuVBorder 2,
MenuHBorder 4, WBorTop 2, WBorLeft 4, WBorRight 4, WBorBottom 2; IB bounds 0..639 × 0..511
(+$544 = 511, +$546 = 640); Jazz/Beat after SetMenuStrip: "Projet" (−4, −2, 143, 41), "Option"
(−4, −2, 143, 31), "Off" (−4, −2, 143, 11) — consistent with the computation in §3.2.

**Pixels read from the screen BitMap** (menu "Projet" open, "Quitter" highlighted) [O]:
- highlighted title: columns **1..64**, lines 0..9 (line 10 is covered by the box);
  "Option" open: columns 73..144 (= LeftEdge 72 + BarVBorder 1);
- item box: columns **1..148**, lines **10..53**; colour-0 frame of 2 columns (1–2 and
  147–148) and 1 line (10 and 53), colour-1 background;
- item 1 in HIGHCOMP: columns **5..144**, lines **22..31**; text "Quitter" at x = 7;
- COMMSEQ: character cell at x = **133** (= 5 + 140 − TxWidth 10 − 2), Amiga symbol at x = **108**
  (= 133 − 23 − 2), same line as the text (TopEdge 1);
- checkmark of "Excl A" (item 1 of "Option"): image at x = 79 (= 72 + 5 + image LeftEdge 2), y = 23;
- HIGHBOX of "Sous-menu" (item 3, y = 42): complemented frame columns 1..148, lines 40..53, sides
  of 4 columns, top/bottom of 2 lines;
- sub-item box: columns **101..198**, lines **40..63**; sub-item 1 highlighted columns
  105..194, lines 52..61.

**Log** (excerpts, IAddress `=A`/`=B` = the window; timestamp = injected step/rank):

```
READY
M A 00040000 0000 0000 =A 0000 FFF4 00000000 00000000   ACTIVEWINDOW from OpenWindow (deferred queue, timestamp 0)
@T 1  click in B then in A
M A 00080000 0000 8000 =A 01F4 0030 1 2                 INACTIVEWINDOW(A) at SELECTDOWN
M B 00040000 0000 8000 =B 0050 0030 1 2                 ACTIVEWINDOW(B)
M B 00000008 0068 8000 =B 0050 0030 1 2                 MOUSEBUTTONS SELECTDOWN (same event)
M B 00000008 00E8 8000 =B 0050 0030 1 3
@T 2  MENUDOWN on "Projet", pointer on "Quitter", MENUUP
M A 00002000 0001 8000 00000000 0021 FFF9 2 2           MENUVERIFY MENUHOT to A
M B 00002000 0003 8000 00000000 FE7D FFF9 2 2           MENUVERIFY MENUWAITING to B
M A 00000008 00E9 8000 00000000 0047 000F 2 4           MOUSEBUTTONS MENUUP to A (MENUVERIFY + MOUSEBUTTONS)
M A 00000100 F820 8000 00000000 0047 000F 2 4           MENUPICK (menu 0, item 1), IAddress = ie_X/ie_Y (0)
   P F820 2056                                         chain: 1 code, Flags with HIGHITEM
M B 00000008 00E9 8000 00000000 FEA3 000F 2 4           MOUSEBUTTONS MENUUP to B as well
@T 3  multiple selection (left click on item 0 then 1), MENUUP outside the box
M A 00000100 F800 ...                                  P F800 0052 / P F820 0056 (chain of 2)
@T 4  item 0, item 1, then item 0 again (the head)
M A 00000100 F800 ...                                  P F800 0052 alone: chain cut (§3.8 point 3)
@T 5  Option: Bascule ×2, Excl A, opening without a choice
   P F801 415B / P F801 405B                           CHECKED set then cleared (MENUTOGGLE), MENUTOGGLED
   P F821 4153                                         Excl A checked; capture: Excl B unchecked
M A 00000100 FFFF ...                                  MENUUP outside the box: MENUNULL
@T 6  MENUCANCEL reply
M A 00002000 0001 ... (MENUCANCEL)                     no MENUWAITING, no bar
M A 00000008 00E9 8000 =A 0047 0005 6 4                 MENUUP returned as MOUSEBUTTONS, IAddress = window
@T 7  right Amiga + q / s / d, then left Amiga + q
M A 00002000 0001 0080 ... 6 4                          MENUVERIFY, timestamp of the PREVIOUS event
M A 00000100 F820 0080 ... 6 4                          MENUPICK Quitter; no MENUWAITING to B; no RAWKEY $10
M A 00000400 0090 0080 00C05654 ...                    the release arrives as RAWKEY
M A 00000100 0860 0080 ...                             'S': sub-item 1 of item 3
M A 00000100 FFFF 0080 ...                             'D': menu disabled => MENUNULL (after MENUVERIFY)
M A 00000400 0010 0040 ... / 0090 0040                 left Amiga: ordinary RAWKEYs
@T 8  sub-menu: MENUPICK 0860 (pointer at 146, 57 screen)
@T 9  item "Grise": MENUNULL; menu "Off": no title highlight, ghosted box, MENUNULL
@T A  REPORTMOUSE, 6 positions injected without reading the port
M A 00000010 00FF 8000 =A 0064 0026 A 1  ... 0069 0029 A 6   6 MOUSEMOVE, no coalescing; Qualifier
                                                       $8000 set by the POINTERPOS conversion
@T B  RMBTRAP: MOUSEBUTTONS 0069 then 00E9
@T C  VANILLAKEY: 'a' => 00200000 0061 (IAddress in the message); releases, arrow ↑: nothing at all
@T D  Amiga+→ (1: no visible movement, PointerTicks 2), Shift (+50), repeats (+53, +56),
      Amiga+↑ (−1); left Amiga + left Alt => MOUSEBUTTONS 0068 qual 0050; Alt release =>
      MOUSEBUTTONS 00E8 then RAWKEY 00E4
@T E  click on the screen background: INACTIVEWINDOW(A) alone; key 'a': no message (passed on)
@T F  B active (without menu bar) + MENUDOWN: MENUVERIFY MENUHOT to B, MENUWAITING to A, empty bar
      (BlockPen background), MOUSEBUTTONS MENUUP to A and B, MENUPICK not requested by B
IDLE
```

---

## 6. Open points

1. **DMRequest** (§3.12): described from the ROM only; neither the double-click, nor REQVERIFY, nor the
   POINTREL placement have been probed.
2. **SIZEVERIFY** and dragging/resizing (state 12): ROM only; the exact duration during which
   the layers stay locked during a drag is not measured.
3. **NEWSIZE sent to the active window** on a SizeWindow on another window (§2.3): read in the
   ROM, not probed (the probe did not call SizeWindow).
4. **Blocking of other tasks** during a menu (LockLayers, state lock): deduced from the semantics
   of LockLayers/ObtainSemaphore; no probe in which a second task draws or calls ClearMenuStrip
   while a menu is open.
5. **Dropping of ActivateWindow** requested during a menu/gadget (§1.10): ROM only.
6. **Off-screen allocation impossible** (§3.5, box not displayed) and **message not allocated ⇒ event
   passed on** (§2.2): ROM only.
7. **Target of messages during a NOISYREQ requester**, state 10 (string gadget: editing, UNDO,
   LONGINT, ActivateGadget): outside the scope of this spec, not described.
8. **DISKINSERTED/REMOVED and NEWPREFS**: broadcast read in the ROM; on the Workbench side, see
   `disk-change-v34.md`; no dedicated probe here.
9. The ghosting pattern $4444/$1111 is read in the ROM; its exact alignment (pattern origin = line 0 of the
   screen's RastPort or of the layer) has not been verified pixel by pixel.
10. **Method**: under FS-UAE 3.2.35, writing to the serial port character by character during menu
    activity caused hangs ("out of event2's!" in the FS-UAE log: event queue
    saturated, level-6 interrupt left active); the probe therefore buffers its log in RAM and only
    flushes it at the markers. This is **not** a ROM behaviour (see the project memory on CIA IRQs
    lost by FS-UAE); to be redone under WinUAE if any doubt remains.
11. Keyboard speed values (+6/+4, 100/75) measured only with PointerTicks = 2; the case 1 is
    deduced from the accumulation formula.

---

## Clean-room review

- [x] No instruction sequence transcribed or paraphrased, no ROM routine address;
  only offsets of public structures, private IB fields, ABI constants, alert
  numbers and measured values.
- [x] The patterns of the internal images (checkmark, Amiga symbol) are visual data observable on
  screen, reproduced for pixel-identical rendering.
- [x] The cited probes are author code (`tests/`, header "ASSET DE TEST, PAS du code ROM").
