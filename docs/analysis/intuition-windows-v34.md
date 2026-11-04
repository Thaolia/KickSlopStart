# intuition-windows-v34.md — CloseWindow, MoveWindow, SizeWindow, WindowToFront/Back, WindowLimits (intuition 34.3)

> ANALYSIS track ("dirty"). Sources: ROM `assets/kick34005.A500` (read-only, radare2; disassembly notes kept
> outside the repository) and **black-box calls on the real ROM** under Amiberry (A500 preset, cycle-exact,
> 512 KB chip + 512 KB slow, Workbench 1.3.3 boot disk `assets/wb133.adf`), 2026-11-04. The calls were injected
> with the debugger into the **Workbench process** once the desktop was up (no SetPatch-free context was needed:
> SetPatch 1.38 replaces none of the functions studied here, but it does replace layers DeleteLayer, see
> `layers-v34.md` §5.4). Windows, requesters and a custom screen were built in memory allocated by that process;
> results were read back from the structures, the UserPorts and the emulator picture. Between calls the process
> slept in dos `Delay` so that the input task could run the deferred actions. No program was written for this
> page; the probe to write on the implementation side is described in §9.
> This document describes **behaviours**, **values**, **orders of operations** and **ABI layouts**. It contains
> no ROM instruction sequence and no routine address.
>
> **Legend**: **[O]** observed on the real ROM · **[D]** deduced from reading the ROM (behaviour, not code) ·
> **[S]** assumption, not verified.
>
> Related specs, not repeated here: `intuition-input-menus-v34.md` §1.10 (deferred-action queue) and §1.11
> (activation routine), §2.2–§2.5 (IntuiMessage pool, targets, verifications); `intuition-gzz-v34.md` §2
> (window layers) and §2.5 (pixels and damage after SizeWindow); `intuition-frame-v34.md` (frame drawing);
> `intuition-requesters-v34.md` §2.2 (requester layer geometry) and §4 (EndRequest); `layers-v34.md` §5.3–§5.7
> (UpfrontLayer, BehindLayer, DeleteLayer, MoveLayer, SizeLayer); `workbench-task-v34.md` §4.1 (WBENCHCLOSE) and
> §6.8 (activation rule, first written from the ROM, now proved below).

---

## 0. Summary for the implementer

1. **CloseWindow is synchronous for the window itself and deferred for the screen.** When it returns, the
   window is unlinked, its layers deleted, its memory freed and **ActiveWindow already points to the successor**;
   the successor's activation (INACTIVEWINDOW, ACTIVEWINDOW, title, frame) and the repair of the windows below
   (frame redraw, REFRESHWINDOW) happen at the next input event. [O]
2. **CloseWindow deletes whatever port is in `UserPort`**, its own or one the caller installed: every message
   in that port (from any window) is replied with Code 4, the signal is freed, the port is removed from the
   public list and its 34 bytes are freed. A program that shares a port must set `UserPort` to NULL before
   closing. [O]
3. **CloseWindow ends nothing else**: no ClearMenuStrip, no EndRequest. A requester still up stays on the
   screen as an orphan layer, still REQACTIVE, whose `layer->Window` points to the freed window. [O]
4. **Successor** of an active window: its `Parent`, else its screen's `FirstWindow`, else none. The successor
   receives **INACTIVEWINDOW then ACTIVEWINDOW** (both), then REFRESHWINDOW if its layer is damaged. [O]
5. **MoveWindow, SizeWindow, WindowToFront, WindowToBack only queue a request** and return. Nothing changes
   before the next input event (≤ 100 ms). A request whose window is closed in the meantime is dropped. [O]
6. **No clamping anywhere**: MoveWindow does not keep the window on the screen (LeftEdge 610 for a 50-pixel
   window on a 640-pixel screen, and −50, were accepted and drawn outside the visible rectangle); SizeWindow
   ignores MinWidth/MaxWidth/MinHeight/MaxHeight and the screen size. [O]
7. **SizeWindow always ends with NEWSIZE**, even for (0, 0), and the NEWSIZE goes to the **active window**,
   not to the sized one (input-menus §2.3). MoveWindow posts no NEWSIZE. [O]
8. **WindowLimits** is synchronous and checks each of the four values on its own: a value that the current size
   violates is not stored and makes the result FALSE, the others are still stored. 0 means "leave unchanged".
   The minima are compared as 32-bit signed numbers, the maxima as 16-bit unsigned numbers. [O]

---

## 1. ABI

### 1.1 LVOs [O]

Checked against `intuition_lib.fd` (amitools, bias 30) and AROS `rom/intuition/intuition.conf` (master), and
against the 78-entry vector table of the ROM:

| LVO | Function | Registers | Return |
|---|---|---|---|
| −72 | `CloseWindow(window)` | A0 | none |
| −168 | `MoveWindow(window, dx, dy)` | A0, D0, D1 | none |
| −288 | `SizeWindow(window, dx, dy)` | A0, D0, D1 | none |
| −306 | `WindowToBack(window)` | A0 | none |
| −312 | `WindowToFront(window)` | A0 | none |
| −318 | `WindowLimits(window, minW, minH, maxW, maxH)` | A0, D0, D1, D2, D3 | D0 = 1 or 0 (long) |

- MoveWindow and SizeWindow use only the **low words** of D0/D1, sign-extended: dx and dy are signed 16-bit. [D]
- No vector checks its window pointer; A0 = NULL is not tested. [D]
- `MoveWindowInFrontOf` (−480) is V36 and absent from 34.3 (74 V34 LVOs, `coverage-v34.md` §1). [O]

### 1.2 Fields used (public `intuition.h` 1.3 layouts)

`struct Window` (132 = `$84` bytes, freed with that size by CloseWindow [D]): NextWindow +$00, LeftEdge +$04,
TopEdge +$06, Width +$08, Height +$0A, MinWidth +$10, MinHeight +$12, MaxWidth +$14, MaxHeight +$16, Flags +$18,
MenuStrip +$1C, FirstRequest +$24, DMRequest +$28, ReqCount +$2C, WScreen +$2E, RPort +$32, BorderLeft..Bottom
+$36..+$39, BorderRPort +$3A, FirstGadget +$3E, Parent +$42, Descendant +$46, Pointer +$4A, IDCMPFlags +$52,
UserPort +$56, WindowPort +$5A, MessageKey +$5E, ScreenTitle +$68, GZZWidth +$70, GZZHeight +$72, WLayer +$7C,
IFont +$80.

`struct Screen`: FirstWindow +$04, Title +$16, DefaultTitle +$1A, LayerInfo +$E0, BarLayer +$14E.
IntuitionBase: ActiveWindow +$34, ActiveScreen +$38, FirstScreen +$3C. `struct Requester`: ReqLayer +$20,
Flags +$1C (REQACTIVE $2000). `struct Layer`: bounds +$10, Flags +$1E (LAYERREFRESH $80), Window +$28,
DamageList +$9C.

### 1.3 Window chain and defaults set by OpenWindow [O]

- OpenWindow inserts the new window **at the head** of `Screen.FirstWindow`, sets `Parent` := the active window
  at that moment (on any screen) and inserts it into the Parent/Descendant chain just after that window
  (`workbench-task-v34.md` §6.8). The chain is **one chain for all screens**: a window on a custom screen can
  have a WB-screen window as Parent. [O]
- OpenWindow sets `ScreenTitle` := `Screen.DefaultTitle`, and applies the NewWindow limits through the same
  routine as WindowLimits (§7). [D]

---

## 2. Common mechanics

### 2.1 Deferred requests [O]

MoveWindow, SizeWindow, WindowToFront and WindowToBack append a request to intuition's deferred-action queue
(`intuition-input-menus-v34.md` §1.10: free 18-byte node reused, else AllocMem(18, MEMF_PUBLIC) under Forbid,
failure = dead-end `Alert($8400000E)`). The request holds the window and, for Move/Size, dx and dy packed as two
words. CloseWindow queues two requests itself: "activate this window" (only when the closed window was active)
and "repair this screen".

- The queue runs at the **start of the next Intuition() call**, in deposit order, before that call's event. On
  an idle machine this is the next IECLASS_TIMER event, at most about 100 ms later. Observed: the window fields
  are unchanged right after each of these calls returns, and changed after a `Delay(5)`. [O]
- Nodes are never freed; the queue only grows to the largest number of requests ever pending at once
  (observed: 2 nodes after ordinary use, 4 after queueing Move + Size + ToFront + the two CloseWindow requests in
  a row). [O]
- Each deferred Move/Size/ToFront/ToBack/activate request first checks that its window still exists (its
  screen is in IntuitionBase's screen list and the window is in that screen's window list); otherwise the
  request is dropped silently. Observed: Move + Size + ToFront queued then CloseWindow before the input task
  ran: nothing happened, no crash. A new window allocated at the address of the closed one would receive the
  request [D].
- During a menu or a held gadget, the requests concerning the active screen stay queued until the end of the
  operation, an activation request is dropped (input-menus §1.10). [O there]

### 2.2 Screen repair [D; O for the messages]

Run at the end of a deferred Move, Size, ToFront/ToBack, and as the second request queued by CloseWindow (also
by EndRequest and ShowTitle). Under LockLayerInfo of the screen, for **every window of the screen** (list order):

1. If the window's layer (the inner one for GIMMEZEROZERO) has LAYERREFRESH, or the GZZ outer layer has it
   (LAYERREFRESH of the outer layer is then cleared): the frame is redrawn completely (frame layer locked) and,
   for a NOCAREREFRESH window, intuition does BeginRefresh/EndRefresh itself.
2. Each requester whose layer has LAYERREFRESH is redrawn under its layer lock and its LAYERREFRESH cleared.
3. If the window's (inner) layer had LAYERREFRESH and the window is not NOCAREREFRESH: an IECLASS_REFRESHWINDOW
   event targets it ⇒ **REFRESHWINDOW** IDCMP (or passed on). Damage of the GZZ outer layer alone gives no
   message.

Then the screen's BarLayer, if damaged, is redrawn (title bar) and its LAYERREFRESH cleared.

Consequence [O]: LAYERREFRESH of a window layer is cleared only by the application's BeginRefresh/EndRefresh
(or by intuition for NOCAREREFRESH). As long as an application has not refreshed, **every** later repair of its
screen sends it another REFRESHWINDOW, whatever caused the repair (observed after WindowToFront of a window
already in front, after SizeWindow(0,0), after CloseWindow of an unrelated window).

---

## 3. CloseWindow(window) — LVO −72

### 3.1 Order of effects [D; O where marked]

1. **Locks**: intuition's state lock and the screen's `Layer_Info` lock are taken together: if the Layer_Info
   lock is not free, the state lock is released, `WaitTOF` is called and both are tried again. The state lock is
   held by the input task during a menu (input-menus §0 point 5), so **CloseWindow waits for any open menu to
   close**. [D]
2. **IDCMP shut down**, as ModifyIDCMP(window, 0) (input-menus §2.6), under Forbid (details §3.2). [O]
3. **Parent/Descendant chain**: the window's Descendant gets the window's Parent, and the Parent gets the
   window's Descendant. [O: X, Y, Z opened in turn, closing Y leaves Z.Parent = X and X.Descendant = Z]
4. Under a second internal lock: the window is removed from `Screen.FirstWindow` (search by pointer, any
   position). [O]
5. **If the window is ActiveWindow** (§3.3): successor chosen, `ActiveWindow` and `ActiveScreen` written now,
   the successor's pointer sprite (or the default pointer if there is no successor) installed now, an
   "activate successor" request queued. If the window was not active, ActiveWindow is untouched. [O]
6. `CloseFont(window->IFont)`. [D]
7. GIMMEZEROZERO: `DeleteLayer` of the outer (frame) layer; then `DeleteLayer` of `WLayer` (`layers-v34.md` §5.4:
   uncovered SMART layers restored, SIMPLE ones cleared and damaged, an area covered by no layer cleared to 0). [O
   for the result: the backdrop area under the closed window cleared to colour 0, backdrop layer Flags $00C1]
8. Layer_Info and state locks released.
9. "**Repair screen**" request queued (§2.2). [O]
10. **System gadgets freed**: every gadget of `FirstGadget` with the SYSGADGET bit ($8000 of GadgetType) is unlinked
    and freed (44 bytes each). User gadgets are left alone (their NextGadget links no longer reach the freed
    system gadgets). [D]
11. **Message pool freed**: every IntuiMessage of the `MessageKey` chain (56 bytes each), free or not. [D; O for
    the total, §8 vector V9]
12. The Window structure is freed (132 bytes). [D; O for the total]

No return value.

### 3.2 IDCMP ports and messages [O unless stated]

Done under Forbid, before anything else is unlinked:

1. If the input task is waiting for a verification reply from this window (MENUVERIFY, SIZEVERIFY, REQVERIFY),
   the pending message is removed from the UserPort, its Code set to 4, it is replied and the input task is
   woken up (input-menus §2.5, cancellation). [D]
2. `IDCMPFlags` := 0.
3. If `UserPort` ≠ NULL:
   - `FreeSignal(UserPort->mp_SigBit)` — in the context of the **task calling CloseWindow**, whatever task
     created the port [D for the cross-task case; O: the bit was cleared in the calling task's `tc_SigAlloc`];
   - every message still queued in the port is taken with GetMsg, gets **Code = 4** and is **replied**: messages
     of **other windows** that share the port included;
   - the port is removed from the public port list (RemPort) and **freed as a 34-byte block** (the size of the
     ports intuition creates), whoever allocated it;
   - `UserPort` := NULL.
4. If `WindowPort` ≠ NULL: the replied messages waiting in it are collected (made free again; a message there
   that is not NT_REPLYMSG ⇒ dead-end `Alert($8400000D)`), then it is removed and freed (34 bytes),
   `WindowPort` := NULL. [D]

**Shared port, observed** (W3 and W4 on one port created by intuition for W4, installed in W3 by writing
`UserPort` then `ModifyIDCMP(W3, ACTIVEWINDOW|INACTIVEWINDOW)`): after `ActivateWindow(W3)`,
`ActivateWindow(W4)`, the port held three messages (W3 ACTIVE, W3 INACTIVE, W4 ACTIVE). `CloseWindow(W3)` with
`UserPort` still set: the port is empty, out of the public list, its signal bit freed in the caller, its memory
reused by the allocator; W4's message came back to W4's pool as free; **W4->UserPort still points to the freed
port**. Any later message for W4 would be put into freed memory.

**Consequences for programs** [D]:
- The 1.3 way to close one window of a shared port is: Forbid; remove (and reply) the messages of that window
  from the port; `window->UserPort` := NULL; `ModifyIDCMP(window, 0)`; Permit; CloseWindow (the Workbench does
  exactly this for WBENCHCLOSE, `workbench-task-v34.md` §4.1).
- Setting `UserPort` to NULL without removing the window's messages leaves them linked in the shared port while
  CloseWindow frees them with the pool (step 11).
- A message that the application has taken with GetMsg and not yet replied is freed too; replying it after
  CloseWindow writes to freed memory.

### 3.3 Active window successor and the messages it gets [O]

Rule (proves `workbench-task-v34.md` §6.8):
1. the window's **Parent** (after step 3 of §3.1 this is the nearest surviving ancestor), on **any screen**;
2. else the first window of its screen's list (`Screen.FirstWindow` after removal, i.e. the most recently opened
   one left);
3. else no window: `ActiveWindow` := NULL.

Observed: W2 (Parent W1) closed ⇒ W1; W1 (Parent = the Workbench backdrop) closed ⇒ backdrop; a custom-screen
window whose Parent is a WB-screen window ⇒ that WB window, and `ActiveScreen` switches to the Workbench screen
at once; Parent forced to NULL ⇒ the custom screen's FirstWindow; Parent NULL on an otherwise empty screen ⇒
`ActiveWindow` = NULL, `ActiveScreen` unchanged.

Immediately, before CloseWindow returns: `ActiveWindow` := successor, `ActiveScreen` := successor's screen (left
unchanged when there is none), a private "current active state" field of IntuitionBase is cleared, and the
pointer sprite is set from the successor's custom pointer, or to the Preferences pointer when there is no
successor or it has none. [O for the two IntuitionBase fields; D for the pointer]

At the next input event the queued activation runs the common activation routine (input-menus §1.11) with the
successor. Because ActiveWindow **already** designates the successor, the routine's "deactivate the old active
window" step applies to the successor itself. The successor therefore receives, in this order [O, twice]:

1. **INACTIVEWINDOW** (and is drawn inactive);
2. **ACTIVEWINDOW** (drawn active, menu state reset, WINDOWACTIVE set, screen title updated);
3. then, from the repair request, **REFRESHWINDOW** if its layer is damaged.

The closed window itself receives nothing (its ports are gone). After the activation, the event IECLASS_EVENT
code 1 is passed on (console.device) as for any deferred activation; with no successor, `ActiveScreen` is set to
the closed window's screen at that time. [D]

### 3.4 Screen title bar [O]

CloseWindow does not touch `Screen.Title` itself:
- successor on the **same screen**: when its activation runs, `Screen.Title` := successor's `ScreenTitle`
  (normally `DefaultTitle`) and the bar is redrawn if it differed. Observed: W2 with `SetWindowTitles(W2, −1,
  "SCRTITLE2")` closed, `Screen.Title` still "SCRTITLE2" right after the call, `DefaultTitle` after the delay;
- **no successor**, or a successor on **another** screen: `Screen.Title` keeps pointing to the closed window's
  ScreenTitle string for good (observed on a custom screen in both cases). If that string was not the screen's
  DefaultTitle and the application frees it, the screen title shows freed memory at the next bar redraw. [O; the
  freed-string consequence D]
- The bar's own damage (the window covered it) is repaired by the screen repair (§2.2). [D]

### 3.5 What CloseWindow does not do [O unless stated]

- **Menu strip**: `MenuStrip` is not read; the application's Menu structures are not touched (nothing to free:
  they are the application's). ClearMenuStrip before CloseWindow is still the 1.3 rule, because of the menu-time
  lock (§3.1 step 1) [D].
- **Requesters still up**: not ended, not unlinked, layers not deleted. Observed with one SMART requester
  (Request on a SMART window, then CloseWindow): the requester rectangle stays on the screen in front of
  everything, its layer remains in the screen's layer list, `Flags` still has REQACTIVE, `ReqLayer` still set
  and `layer->Window` = the freed window. Moving the pointer or clicking over it can make the input engine use
  the freed window [D, not provoked]. The application must EndRequest first.
- **DMRequest**: untouched. [D]
- **Custom pointer data** (SetPointer): the sprite image belongs to the application; only the hardware pointer
  is switched (§3.3). [D]
- **User gadgets**: not freed (§3.1 step 10).
- **Font**: the window's IFont is closed (step 6); a font the application set with SetFont on the RastPort is
  the application's.

### 3.6 Memory [O]

Open + close of a window with IDCMP, whose messages were all replied, returns AvailMem to its value except for
what **other** windows received meanwhile: with the Workbench process frozen (it never replies), each cycle
cost exactly 4 × 56 bytes when the window was opened with ACTIVATE (backdrop: INACTIVEWINDOW at the open;
INACTIVEWINDOW, ACTIVEWINDOW, REFRESHWINDOW at the close) and 1 × 56 bytes when it was not (REFRESHWINDOW only).
So CloseWindow frees everything OpenWindow allocated: window, system gadgets, both ports, the message pool,
layers (and GZZ outer layer, its RastPort), the opened font reference.

---

## 4. MoveWindow(window, dx, dy) — LVO −168

- Queues a "move" request and returns. [O: LeftEdge unchanged right after the call]
- Deferred part [D unless stated]:
  1. window gone ⇒ dropped; **dx = dy = 0 ⇒ nothing at all** (no repair, so no REFRESHWINDOW even to damaged
     windows) [O];
  2. under LockLayerInfo of the screen, `MoveLayer(dx, dy)` on each of the window's layers, in this order: the
     requester layers (FirstRequest chain order), `WLayer`, then the GZZ outer layer;
  3. if one MoveLayer fails, the remaining layers are not moved, the layers already moved **stay moved**, and
     LeftEdge/TopEdge and the screen are left as they are (no repair) [D];
  4. otherwise `LeftEdge += dx`, `TopEdge += dy`, then screen repair (§2.2) [O].
- **No clamping**, no comparison with the screen size [O]: on a 640 × 256 screen, a 50 × 80 window moved to
  LeftEdge 610 and then to −50 was accepted both times. The layers then lie partly outside the BitMap: the frame
  was drawn wrapped onto the neighbouring rows (picture: right border and gadgets reappearing at the left edge
  one row down, debris left after moving back). Callers must keep windows on the screen themselves (the drag
  gadget path clamps; MoveWindow does not).
- Messages: none of its own. A SIMPLE window that moves is wholly damaged by layers (§5.6 there) and gets
  REFRESHWINDOW from the repair; windows uncovered by the move get REFRESHWINDOW if SIMPLE. [O for the moved
  window] **No NEWSIZE.** [O]
- Requesters move with the window. [O: window (300,120) with a requester at (320,140)-(439,169); MoveWindow(−20,
  −10) ⇒ requester layer (300,130)-(419,159)]
- MouseX/MouseY of the window are not recomputed by the move itself; they follow at the next mouse event. [S]

## 5. SizeWindow(window, dx, dy) — LVO −288

- Queues a "size" request and returns. [O: Width unchanged right after the call]
- Deferred part [D unless stated], under LockLayerInfo of the screen:
  1. window gone ⇒ dropped (no NEWSIZE);
  2. **dx = dy = 0**: no layer operation, but steps 6 and 7 still run [O: NEWSIZE received];
  3. GIMMEZEROZERO: `SizeLayer(outer, dx, dy)` first; failure ⇒ go to step 6. Then `SizeLayer(WLayer, dx, dy)`;
     failure ⇒ the outer layer is sized back by (−dx, −dy), go to step 6;
  4. on success: each requester is fitted again to the new interior by the Request geometry rule
     (`intuition-requesters-v34.md` §2.2): its layer is resized, **deleted** when the clipped size becomes ≤ 0,
     **created again** (new layer, damaged so that it is redrawn) when the window grows back [O: requester 120
     wide at window-relative (20,20) in a 220-wide window: 82 wide when the window is 120 wide (right border
     18), layer NULL at 30 wide, a new 120-wide layer at 220 wide];
  5. the frame and the right/bottom-relative gadgets are prepared for redraw: in the frame layer, the old right
     border band, the old bottom border band and the right end of the top border are cleared and added to the
     DamageList, and so are the same bands at the new size; every gadget with GRELRIGHT, GRELBOTTOM,
     GRELWIDTH or GRELHEIGHT (and the system gadgets anchored to the right or bottom edge) has its old box
     cleared and damaged and its new box damaged; the frame layer gets LAYERREFRESH. Then `Width += dx`,
     `Height += dy`, `GZZWidth += dx`, `GZZHeight += dy` [O for the fields: GZZ window 200 × 80 / 178 × 67 ⇒
     230 × 100 / 208 × 87; the damaged rectangles are those measured in `intuition-gzz-v34.md` §2.5];
  6. an IECLASS_SIZEWINDOW event is produced ⇒ **NEWSIZE to the active window** (input-menus §2.3) or passed on
     to the following handlers (console.device) if the active window does not ask for NEWSIZE [O];
  7. screen repair (§2.2): frame redrawn, REFRESHWINDOW to damaged windows [O].
- So NEWSIZE is posted **even when nothing changed** (dx = dy = 0, or a failed SizeLayer). [O for (0,0)]
- **NEWSIZE goes to the active window**: SizeWindow on an inactive window W7 sent NEWSIZE to the active W6 and
  only REFRESHWINDOW to W7. IAddress of that NEWSIZE is meaningless (observed 0 once, the backdrop window's
  address once). [O] This explains why `intuition-gzz-v34.md` §2.5 (probe windows opened without ACTIVATE)
  saw no NEWSIZE.
- Order: NEWSIZE before REFRESHWINDOW. [O]
- **No limit check**: MinWidth/MinHeight/MaxWidth/MaxHeight are not read (observed: MinWidth 100, Width 400 ⇒
  SizeWindow(−350, 0) ⇒ Width 50), nor the screen size [D]. The size gadget drag applies the limits; SizeWindow
  does not. A window narrower than its system gadgets is drawn with the gadgets over the title (picture,
  Width 50). Sizes ≤ 0 reach SizeLayer unchecked [D, not provoked].
- SIZEVERIFY is not sent by SizeWindow (only at the size gadget's SELECTDOWN, input-menus §2.5). [D]
- Pixels and damage per refresh type: `intuition-gzz-v34.md` §2.5 and `layers-v34.md` §5.7.

## 6. WindowToFront(window) / WindowToBack(window) — LVO −312 / −306

- Each queues a request and returns; the layer order is unchanged right after the call. [O]
- Deferred part [D unless stated]: window gone ⇒ dropped. Under LockLayerInfo, the window's layers are taken in
  the list order of §4 step 2 (requesters, WLayer, GZZ outer):
  - **ToFront**: `UpfrontLayer` on them **from the last to the first** (GZZ outer, WLayer, then the requesters
    from the oldest to the newest);
  - **ToBack**: `BehindLayer` on them **from the first to the last**;
  - both give the final order newest requester, …, oldest requester, WLayer, outer [O: requester layer in front
    of the window layer after each operation];
  - if one call fails, the layers already moved are moved back by the opposite call, in reverse order;
  - then screen repair (§2.2), **even when nothing moved**.
- WindowToBack of a normal window puts it behind the other non-BACKDROP layers but **in front of** the BACKDROP
  layers (the screen title bar layer and the Workbench backdrop window): `layers-v34.md` §4. [O]
- WindowToFront of a window already in front changes no layer (UpfrontLayer returns at once) but the repair
  still runs. [O: REFRESHWINDOW re-sent to the two windows whose LAYERREFRESH was pending]
- `Screen.FirstWindow` order, ActiveWindow and the Parent chain are not changed. [O]
- A BACKDROP window is only reordered among BACKDROP layers (layers rule). [D]

## 7. WindowLimits(window, minW, minH, maxW, maxH) — LVO −318

Synchronous (no queue, no lock, no Forbid). Result = TRUE (1); then each value on its own [O for every line
below except where marked]:

| Argument | Ignored when | Accepted when | Effect if accepted | If refused |
|---|---|---|---|---|
| minW (D0) | D0 = 0 (all 32 bits) | Width (sign-extended) ≥ D0, **signed 32-bit** compare | MinWidth := low word of D0 | MinWidth unchanged, result FALSE |
| minH (D1) | D1 = 0 (32 bits) | Height ≥ D1, signed 32-bit | MinHeight := low word | unchanged, FALSE |
| maxW (D2) | low word of D2 = 0 | Width ≤ low word, **unsigned 16-bit** compare | MaxWidth := low word | unchanged, FALSE |
| maxH (D3) | low word of D3 = 0 | Height ≤ low word, unsigned 16-bit | MaxHeight := low word | unchanged, FALSE |

- Return value in D0: **1 or 0** (a word result sign-extended to a long). [O]
- 0 means "leave unchanged" for each value. [O]
- Current size outside a new limit: that limit is not stored, the call returns FALSE, the other limits of the same
  call are still stored, and **the window is not resized**. [O]
- Quirks of the compare widths [O]: D0 = `$00010000` (low word 0) is not "unchanged" but a minimum of 65536, which
  is refused (FALSE); D0 = −5 is accepted and stores MinWidth = `$FFFB` (−5 as a signed word); D2 = `$00010500`
  stores MaxWidth = 1280 and returns TRUE.
- No check that min ≤ max, nor against the screen size. [D]
- The limits are only used by the size gadget drag; SizeWindow ignores them (§5). [D]

---

## 8. Test vectors (real ROM 34.5, Amiberry A500, Workbench 1.3.3 desktop)

Setup common to all: Workbench screen 640 × 256, 2 planes; the Workbench backdrop window (Flags `$02002B40` when
active, layer Flags `$0041`/`$00C1`) is the first window and its process does not reply; windows opened with
DetailPen/BlockPen −1, NewWindow MinWidth 60, MinHeight 30, MaxWidth 640, MaxHeight 256 unless stated. "After
the delay" = after dos `Delay(5..10)`.

| # | Steps | Observed |
|---|---|---|
| V1 | W1 (40,30) 300×100, Flags `$104F` (sizing, drag, depth, close, SIMPLE, ACTIVATE), IDCMP `$C0206`; then W2 (100,60) same flags | W2.Parent = W1, W1.Parent = backdrop, W1.Descendant = W2; W1's port: ACTIVEWINDOW, INACTIVEWINDOW; W2's port: ACTIVEWINDOW |
| V2 | SetWindowTitles(W2, −1, "SCRTITLE2"), then CloseWindow(W2) | right after the call: ActiveWindow = W1, FirstWindow = W1, Screen.Title still "SCRTITLE2", W1's port empty; after the delay: Screen.Title = DefaultTitle, W1's port = INACTIVEWINDOW, ACTIVEWINDOW, REFRESHWINDOW (in that order) |
| V3 | CloseWindow(W1) | ActiveWindow = backdrop at once; after the delay Screen.Title = the backdrop's ScreenTitle |
| V4 | X, Y, Z opened in turn with ACTIVATE (Parent chain W6 → X → Y → Z); CloseWindow(Y) (inactive) | Z.Parent = X, X.Descendant = Z; ActiveWindow stays Z |
| V5 | custom screen (320×200, 2 planes); WA, WB on it with ACTIVATE while a WB-screen window W6 is active; CloseWindow(WB) | successor WA (same screen) |
| V6 | SetWindowTitles(WA, −1, custom) then CloseWindow(WA) | ActiveWindow = W6, ActiveScreen = Workbench screen at once; custom screen FirstWindow = 0, Title still the custom string |
| V7 | WC, WD on the custom screen (WD active), WD.Parent forced to 0, CloseWindow(WD); then WC.Parent forced to 0, CloseWindow(WC) | first: successor WC (FirstWindow), WC's port gets INACTIVEWINDOW, ACTIVEWINDOW, REFRESHWINDOW; second: ActiveWindow = 0, ActiveScreen = custom screen, its Title still the closed window's custom string |
| V8 | shared port (§3.2) | port emptied, removed from the public list, signal bit 30 freed in the caller (`tc_SigAlloc` `$C000FFFF` ⇒ `$8000FFFF`), memory reused; W4's message free again in W4's pool; W4.UserPort dangling |
| V9 | open + close a window with ACTIVATE (IDCMP `$C0206`), its messages replied; then without ACTIVATE and IDCMP 0 | AvailMem −224 (4 unreplied backdrop messages, 4 × 56), then −56 (1 message); nothing else lost |
| V10 | SMART window (200,80) 250×100, InitRequester + Request (20,20) 120×30 BackFill 3; CloseWindow | requester rectangle (colour 3) still on screen, its layer still first in the screen's layer list, REQACTIVE still set, `layer->Window` = the closed window; the rest of the window area cleared to colour 0 |
| V11 | W6 (40,30) 200×80, SIMPLE, sizing, ACTIVATE, IDCMP NEWSIZE\|REFRESHWINDOW, MinWidth 100, MaxHeight 150; SizeWindow(W6, +200, 0) | Width 200 right after the call, 400 after the delay; port: NEWSIZE (IAddress 0), REFRESHWINDOW |
| V12 | SizeWindow(W6, 0, 0) | NEWSIZE, REFRESHWINDOW |
| V13 | W7 (300,120) 200×80, no ACTIVATE, same IDCMP; SizeWindow(W7, +20, +10) | W7 220 × 90; W6 (active) gets NEWSIZE (+ REFRESHWINDOW, still pending); W7 gets REFRESHWINDOW only |
| V14 | SizeWindow(W6, −350, 0) with MinWidth 100 | Width 50 (not clamped) |
| V15 | WindowLimits on W6 at 400 × 80, limits 100/50/640/150, calls in this order: (100,50,300,150); (0,0,0,0); (`$10000`,0,0,0); (0,0,`$10500`,0); (500,0,0,0); (−5,0,0,0); (100,0,0,0) | 0 (MaxWidth stays 640, others stored); 1; 0; 1 with MaxWidth 1280; 0; 1 with MinWidth −5; 1 with MinWidth 100 |
| V16 | MoveWindow(W6, 10, 5) at (40,30) | (40,30) right after the call, (50,35) after the delay; REFRESHWINDOW |
| V17 | MoveWindow(W6, 0, 0) after draining | no message |
| V18 | MoveWindow(W6, 560, 0) (50 wide) then back, then MoveWindow(W6, −100, 0) | LeftEdge 610, then −50: not clamped; frame drawn wrapped onto neighbouring rows |
| V19 | W6 behind W7 (layers W7, W6, bar, backdrop); WindowToFront(W7) | order unchanged; REFRESHWINDOW to both (pending LAYERREFRESH) |
| V20 | WindowToBack(W7) | order W6, W7, bar layer, backdrop |
| V21 | Request on W7 then MoveWindow(−20,−10), SizeWindow(−100,0), (−90,0), (+190,0) | requester layer follows; 82 wide; deleted; recreated 120 wide (new layer) |
| V22 | same requester, WindowToBack(W7), WindowToFront(W7) | order: W6, req, W7, bar, backdrop; then req, W7, W6, bar, backdrop |
| V23 | GZZ window (100,40) 200×80 Flags `$144F`, ACTIVATE; WindowToBack, SizeWindow(+30,+20) | right after each call: unchanged; after the delay: inner then outer layer behind the other windows, 230 × 100, GZZ 208 × 87; port: REFRESHWINDOW, NEWSIZE, REFRESHWINDOW |
| V24 | MoveWindow, SizeWindow, WindowToFront queued, then CloseWindow before the input task runs | nothing happens after the delay, no crash; queue 4 nodes |

## 9. Probe to write (implementation side)

`tests/iwin_probe.s` + `tests/iwin_probe.sh`, modelled on `tests/glist_probe.s/.sh` (bootblock stage that
reloads the rest, then stage 2) or on `tests/resize_probe.s/.sh`. It must run on both ROMs (`IW_ANALYSIS=1` for
the real one, analysis agent only). Delays: `WaitTOF` × 10 (the strap context has no dos). Serial lines
`"IW <step> ..."` with hexadecimal fields; `IW END` at the end. Steps (public calls only):

1. Open the Workbench screen through OpenWindow (Type WBENCHSCREEN). Open **A** (40,30) 300×100 Flags `$104F`,
   IDCMP `$C0206`, title "A"; wait; open **B** (100,60) same, title "B"; wait. Print for A and B: Parent,
   Descendant (as "A"/"B"/"0"/"?"), and ActiveWindow. Expect B.Parent = A, A.Descendant = B, Active = B.
2. Drain both ports (GetMsg + ReplyMsg). SetWindowTitles(B, −1, "T2"); wait; drain.
3. CloseWindow(B). At once print ActiveWindow (expect A), `Screen.Title` = "T2" (print 1 if equal to the T2
   pointer). Wait. Print `Screen.Title` = DefaultTitle (1/0) and the classes of A's queued messages in order
   (expect `80000 40000 4`).
4. Shared port: open **C** with IDCMP 0 and **D** with IDCMP `$C0000` (no ACTIVATE). C.UserPort := D.UserPort,
   ModifyIDCMP(C, `$C0000`). ActivateWindow(C), wait, ActivateWindow(D), wait. Print the number of messages in
   the port (expect 3) and whether the port is in the public list (FindPort("IDCMP") is ambiguous: walk
   `ExecBase->PortList`). CloseWindow(C). Print: message count 0, in-list 0, the signal bit allocated (expect 0 in
   `tc_SigAlloc`). Then D.UserPort := NULL, CloseWindow(D).
5. Requester: open **E** SMART (200,80) 250×100; InitRequester; Request (20,20) 120×30 BackFill 3; wait;
   CloseWindow(E); wait. Print: `ReqLayer` ≠ 0, REQACTIVE set, the layer still linked from
   `Screen.LayerInfo.top_layer`, and the pen read with ReadPixel on the screen RastPort at the requester centre
   (expect 3). Then DeleteLayer(0, ReqLayer) to clean up.
6. Size: open **F** (40,30) 200×80 Flags `$1047` IDCMP 6, MinWidth 100; wait; drain. SizeWindow(F, 200, 0); print
   Width at once (200); wait; print Width (400) and F's classes (`2 4`). SizeWindow(F, 0, 0); wait; classes
   (`2 4`). Open **G** (300,120) 200×80 Flags `$47` IDCMP 6; wait; drain F and G; SizeWindow(G, 20, 10); wait;
   print G's size (220×90), F's classes (`2 4`) and G's classes (`4`). SizeWindow(F, −350, 0); wait; Width 50.
7. Limits on F after SizeWindow(F, 350, 0) (Width 400): the seven calls of V15, printing D0 and the four
   limit words after each.
8. Move: MoveWindow(F, 10, 5); print LeftEdge at once and after the wait; drain; MoveWindow(F, 0, 0); wait; message
   count 0. MoveWindow(F, 560, 0) on a 50-wide F: LeftEdge 610 after the wait, then move back.
9. Depth: with G in front of F, WindowToBack(G); print at once whether `top_layer` is still G's layer (expect
   1), then after the wait the first three layers of the screen (expect F's layer, G's layer, the bar layer). WindowToFront(G); wait; G first.
10. Queue drop: MoveWindow(F, 5, 5), SizeWindow(F, 5, 5), WindowToFront(F), CloseWindow(F) without waiting; wait;
    print `IW ALIVE`. Close G.
11. AvailMem(MEMF_ANY) before step 1 and at the end, printed; on our ROM with a replying backdrop the two values
    should match except for queue nodes.

## 10. Open points

1. **CloseWindow during an open menu** blocks on the state lock until the menu closes (§3.1 step 1) [D, not
   provoked]. Likewise a CloseWindow from the task that is waiting for a MENUVERIFY reply would cancel it (§3.2
   step 1) [D].
2. **Orphan requester after CloseWindow** (§3.5): what the input engine does when the pointer goes over the orphan
   layer (it carries the freed window) was not provoked. An implementation may delete requester layers in
   CloseWindow; that is more robust but differs from 1.3 on screen (the rectangle disappears).
3. **MoveLayer/SizeLayer failure paths** (§4 step 3, §5 step 3) were not provoked (needs chip RAM exhaustion).
4. **Off-screen windows** (§4): only the 640-pixel right and left edges were tried; the bottom edge (writes past
   the end of the BitMap) was not, on purpose.
5. **IAddress of NEWSIZE** is whatever the internal event carried; do not rely on it [O: 0 and a window address].
6. The private IntuitionBase field cleared by CloseWindow of the active window (§3.3) is not identified [S: the
   "current gadget/state" of the old active window].
7. Pointer switch at CloseWindow (§3.3) was read in the ROM, not measured.
8. `intuition-gzz-v34.md` §2.5's statement "no NEWSIZE is ever posted by SizeWindow()" is corrected there: its probe
   windows were inactive.
9. Our side, for the record: `docs/PLAN.md` lists "Next: NEWSIZE only for the size gadget"; on 1.3 SizeWindow
   does post NEWSIZE, to the active window (§5).

## Clean-room review

- [x] No instruction sequence, no listing, no pseudo-code transcription of a routine: orders of observable effects,
  conditions and values only.
- [x] No ROM routine address or ROM offset. The only addresses are those of RAM objects in the test runs (not
  reproduced here) and public structure field offsets (`intuition.h`, `exec/ports.h`, `graphics/layers.h`,
  NDK 1.3) plus IntuitionBase public fields; LVOs from the `.fd` file and AROS `intuition.conf`.
- [x] No ROM data reproduced (no image, string or table). The alert numbers are the ones already published in
  `intuition-input-menus-v34.md`.
- [x] Black-box facts come from debugger-injected calls into the Workbench process on the real ROM; [D] facts
  come from reading the ROM and are described as behaviour.
- [x] Written in English by the analysis track; no file outside `docs/analysis/` was written.
