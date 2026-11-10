# intuition-misc-v34.md — intuition 34.3: OpenIntuition, Intuition(), SetPointer/ClearPointer, AlohaWorkbench, CurrentTime, Lock/UnlockIBase, Begin/EndRefresh, Alloc/FreeRemember

> ANALYSIS track ("dirty"). Sources: ROM `kick34005.A500` (read-only, radare2 static reading of the
> intuition library vectors and the routines they reach). No probe was run for this page. We describe
> the **what**: registers, fields, order of observable effects, return values. No instruction sequence,
> no ROM address. Offsets are those of public NDK 1.3 structures or of private IntuitionBase (IB) fields
> already named by the neighbouring specs.
>
> **Legend**: **[O]** observed (read in the ROM) · **[D]** deduced · **[S]** assumed.
>
> Only what is **not** already specified elsewhere is written here. See:
> `intuition-input-menus-v34.md` §1 (input handler, course of an `Intuition()` call, event classes,
> pointer bounds, CurrentTime/DoubleClick §2.6), `intuition-screens-v34.md` §1.3 (IB fields, lock
> numbering), §7.4 (messages to the Workbench), §9 (LockIBase/UnlockIBase), `intuition-prefs-v34.md` §1
> (library init, first open), §3.3 (prefs application, default pointer image and offsets),
> `custom-chips-v34.md` §4 (graphics GetSprite/ChangeSprite/MoveSprite), `workbench-task-v34.md` §3.1
> and §4.1 (AlohaWorkbench call and WBENCHMESSAGE handling on the Workbench side).

---

## 0. Executive summary

1. The library **Open vector (−6) is OpenIntuition (−30)**: every `OpenLibrary("intuition.library")`
   runs it. Only the **first** call does work; it sets `lib_OpenCnt` to 1, and **Close (−12) and
   Expunge (−18) do nothing and return 0**: `lib_OpenCnt` stays 1 forever, intuition is never
   expunged. [O]
2. The first call turns **sprite and bitplane DMA off**, recomputes pointer bounds, obtains the
   timer.device base, opens input.device and adds the input handler (priority 50). [O]
3. **LVO −36 `Intuition()` reads its event list from the stack**, not from A0 as the fd file states;
   the input handler relay pushes A0 and calls the body directly. [O]
4. **SetPointer/ClearPointer** only store the pointer in the Window (+$4A…+$51) under Forbid; the sprite
   changes **only if the window is the active window** (otherwise at its next activation). The image
   is used **in place** (must be CHIP RAM, writable, kept until replaced); width is stored but
   ignored; height and offsets are **signed bytes**. [O]
5. **AlohaWorkbench(port)** only stores the port in IB+$3A8 (NULL unregisters); no message is sent by
   it. Messages go out only from OpenWorkBench (WBENCHOPEN) and CloseWorkBench (WBENCHCLOSE). [O]
6. **LockIBase(n)** (D0) / **UnlockIBase(n)** (**A0**): no range check of n; 7 semaphores exist (0–6). [O]
7. **BeginRefresh** locks the GZZ outer layer (LockLayerRom, no BeginUpdate) and BeginUpdate's the inner one,
   whatever the refresh type (on an undamaged SMART window everything drawn is discarded); nesting corrupts the
   saved ClipRect list. **EndRefresh** tests `complete` as a **word** and clears LAYERREFRESH of the inner layer only
   (§6b). [O]
8. **AllocRemember** allocates its 12-byte node with requirements 0 and pushes it at the head; **FreeRemember**
   tests `reallyForget` as a **word**, frees the nodes in every case (and the blocks only when TRUE) and sets the
   key to NULL (§6c). [O]

---

## 1. OpenIntuition (LVO −30) = library Open (LVO −6)

### 1.1 Wiring [O]

- Vector −6 jumps to the same entry as −30. Vectors −12 (Close), −18 (Expunge), −24 (reserved) all return
  **0** with no other effect.
- Entry: A6 = IntuitionBase. Return: **D0 = IntuitionBase**, always (also when input.device could not be
  opened).
- `lib_OpenCnt` (IB+$20) is tested: **≠ 0 ⇒ return IB at once**, nothing else. So the open counter is
  incremented **once** (0 → 1) and never moves again; CloseLibrary does not decrement it. [O]

### 1.2 First call: order of effects [O]

1. `lib_OpenCnt` := 1.
2. Re-application of the current preferences (`intuition-prefs-v34.md` §3.3, without copy).
3. **DMACON := $0020** (clear SPREN: sprite DMA off), then **DMACON := $0100** (clear BPLEN: bitplane
   DMA off). Whatever the strap or a previous owner was displaying disappears until a screen is
   opened and the display remade. [O; visible effect D]
4. IB Flags (+$40) := **$1000**; private word IB+$78 := $FFFF.
5. Pointer bounds recomputed (`intuition-input-menus-v34.md` §1.5): MinX = 0, MaxX =
   NormalDisplayColumns − 1, MinY = IB+$378, MaxY from FirstScreen (top + height, doubled if not LACE,
   − 1) capped to 2 × NormalDisplayRows − 1. When no screen exists FirstScreen is NULL and the
   computation reads low memory; the cap normally yields 2 × NormalDisplayRows − 1. [O; result D]
6. **OpenDevice("timer.device", unit −1, local request, 0)**: unit −1 is invalid, so the open fails, but
   exec has already set `io_Device`; **IB+$6C := io_Device** (the timer device base, used for time
   arithmetic). The request is a stack local and is never closed. `io_Device` = 0 (no timer.device) ⇒
   dead-end alert **$8400000F**. [O]
7. Private input state: state word IB+$294 := **1** (idle, cf. `intuition-input-menus-v34.md` §1.8),
   IB+$1C8 / +$1CC (long) and +$1D0 (word) := 0.
8. **OpenDevice("input.device", 0, IB+$182, 0)**. Failure ⇒ return IB (no handler, no alert).
9. Handler installation with the same request: `mn_ReplyPort` (IB+$190) := **0**, `io_Command` :=
   **9 (IND_ADDHANDLER)**, `io_Data` := IB+$1B2 (Interrupt structure inside IB): `ln_Pri` = **50**,
   `is_Data` = IB, `is_Code` = relay (§2.1), `ln_Name` left 0. **DoIO**. [O]
   - Requirement for our input.device: IND_ADDHANDLER must complete **quickly** (IOF_QUICK honoured):
     the request has **no reply port**. [D]

### 1.3 When it is first called [O/D]

- No ROM module opens intuition during resident initialisation on a normal boot (console.device and
  trackdisk initialise before intuition, priority 20 vs 10; the strap draws with graphics only).
- `alert.hook` (priority 5) opens it **only** when a pending alert from before the reset must be shown.
- Otherwise the first opener is dos, from the initial CLI, before `devs:system-configuration` is applied
  (cf. `intuition-prefs-v34.md` §2.1) and before the CON: window opens the Workbench screen. [D]
- Until the first open, no input handler exists: input.device events go to console.device only.

---

## 2. Intuition() (LVO −36)

### 2.1 Entry convention — differs from the fd file [O]

- The fd/AutoDoc give `Intuition(iEvent)(A0)`. In 34.3 the vector jumps straight into a body that reads
  its argument as **the first long on the stack** (C convention: `jsr` then (SP) = return address,
  4(SP) = event list). **A0 is ignored.** A6 must be IntuitionBase.
- The input handler does not go through the LVO: its `is_Code` relay receives the input.device handler
  convention (A0 = event list, A1 = `is_Data` = IB), sets A6 := A1, pushes A0, calls the body, and
  returns the body's D0 with **A0 and A6 preserved**.
- An external caller of LVO −36 must therefore push the list pointer; a caller passing A0 only gets
  whatever is on its stack. No program of the WB 1.3.3 disk calls LVO −36 [S: not scanned
  exhaustively, no reason to].
- Return D0: head of the list to pass on (fresh copies), possibly 0; `Intuition(NULL)` returns 0 with no
  effect. Everything else (classes consumed or passed on, locks, order) is in
  `intuition-input-menus-v34.md` §0–§2.

---

## 3. SetPointer (−270) / ClearPointer (−60)

### 3.1 Registers [O]

- `SetPointer(window A0, pointer A1, height D0, width D1, xOffset D2, yOffset D3)`; no return value.
- `ClearPointer(window A0)`; no return value.
- No argument is validated (window NULL ⇒ writes into low memory).

### 3.2 Effects [O]

SetPointer, in order:
1. Window fields: **Pointer (+$4A) := A1**, **PtrHeight (+$4E) := low byte of D0**, **PtrWidth (+$4F) :=
   low byte of D1**, **XOffset (+$50) := low byte of D2**, **YOffset (+$51) := low byte of D3**.
2. Forbid.
3. If window = **IB->ActiveWindow** (+$34): apply the window pointer (§3.3).
4. Permit.

ClearPointer: Pointer := 0, PtrHeight := 0, PtrWidth := 0 (**XOffset/YOffset are left unchanged**, they are
ignored while Pointer = 0), then the same steps 2–4.

### 3.3 Applying a pointer (common routine) [O]

Called by SetPointer/ClearPointer for the active window, during **window activation** (after the
window has been marked WINDOWACTIVE), by **CloseWindow** when the closed window was the active
one (for the new active window, or with no window ⇒ default), and once at library init (default).

1. Source: if a window is given **and** its Pointer ≠ 0 ⇒ (Pointer, PtrHeight, XOffset, YOffset) of the
   window; otherwise the **default pointer**: data IB+$32E, height IB+$332 (= 16), offsets IB+$334/$335
   (prefs XOffset/YOffset, init −1/−1, `intuition-prefs-v34.md` §1, §3.3).
2. Height, XOffset and YOffset are **sign-extended bytes**: heights 128–255 become negative (broken
   sprite) ⇒ usable height **1–127**; offsets −128…127. Width is never read.
3. The intuition SimpleSprite (12 bytes, IB+$3E8 points to it, hardware **sprite 0** reserved by
   `GetSprite(ss, 0)` at library init): `height` := height; then
   **graphics ChangeSprite(NULL, ss, data)**.
4. A second-sprite path exists (private IB+$3EC / +$3F0, GetSprite(…, 1) / FreeSprite(1) when switching
   to/from the default pointer) but IB+$3EC is never set by 34.3: dead code. [O]
5. IB current pointer: data IB+$70, height IB+$74, X/YOffset IB+$76/$77 := the values used.
6. Mouse clamp + propagation to screens/windows + **MoveSprite(NULL, ss, (MouseX >> 1) + XOffset,
   (MouseY >> 1) + YOffset)** (same routine as for mouse movement, `intuition-input-menus-v34.md`
   §1.3 point 5). So the new hot spot is applied immediately, not at the next mouse move.

### 3.4 Sprite data format and lifetime [O for use, D for consequences]

- Standard simple-sprite layout, used **in place** by graphics (no copy):
  `{posctl[2]} {plane0, plane1} × height {0, 0}` = **4 × (height + 2) bytes**, word-aligned.
  - The first two words are **overwritten by graphics** at every ChangeSprite/MoveSprite (control words,
    `custom-chips-v34.md` §4); bits 3–7 of the second word (ATTACH included) are preserved, so they
    should be 0.
  - The final pair of zero words stops sprite DMA.
- Must be in **CHIP RAM** (sprite DMA reads it) and stay valid while it can be the active pointer: until
  ClearPointer / another SetPointer on that window, the window's CloseWindow, or another window becoming
  active. Intuition never frees or copies it.
- Pixel colours: sprite 0 ⇒ colour registers 17–19 (pointer colours from prefs).
- Units: XOffset is in **low-resolution pixels** and YOffset in **non-interlaced lines** relative to
  the mouse position (MouseX hires / 2, MouseY interlaced / 2); the sprite's top-left pixel is drawn at
  (mouse + offset). Example: OctaMED passes (−12, −11) for a 16 × 14 image (`octamed-v34.md` §2.3).
- Visibility: graphics re-points the copinit SPRxPT MOVE; sprite DMA uses it from the **next video
  frame**. Nothing waits for that. [D]

### 3.5 Active window rule — summary [O]

| Situation | Visible pointer |
|---|---|
| SetPointer on the active window | new image from the next frame |
| SetPointer on an inactive window | unchanged; image appears when that window is activated |
| ClearPointer on the active window | default pointer |
| Active window closed | pointer of the next active window (Parent, else screen's first window) or default |
| No active window | default pointer |
| Menu open / gadget held / requester | unchanged (no pointer switch for these) |

---

## 4. AlohaWorkbench (LVO −402)

- Register: **A0 = MsgPort** of the Workbench (fd: `AlohaWorkbench(wbport)(A0)`).
- Effect: **IB+$3A8 := A0**. Nothing else: no Forbid, no lock, no check, no message, no reply port
  creation. Passing **0 unregisters** the Workbench (later Open/CloseWorkBench send nothing). D0 on
  return happens to hold the argument (not contractual). [O]
- The 1.3 Workbench calls it once, with its IDCMP/Workbench port "B", at the end of its initialisation
  (`workbench-task-v34.md` §3.1 #9).
- Messages to the registered port (complement to `intuition-screens-v34.md` §7.4) [O]:
  - sent only by **OpenWorkBench** after it actually opened a new WB screen (**Code 1, WBENCHOPEN**)
    and by **CloseWorkBench** after its window check succeeded (**Code 2, WBENCHCLOSE**), never by
    AlohaWorkbench, OpenScreen or CloseScreen;
  - the reply port "**WBenchPort**" is created at the first send by intuition's own CreatePort: it is a
    **public** port (AddPort, 34 bytes MEMF_PUBLIC|CLEAR); its creation allocates a signal in the
    first sending task that is never freed; the port is never deleted (not even by AlohaWorkbench(0));
  - per send: AllocSignal(−1) (result not checked), `mp_SigBit`/`mp_SigTask` := that signal / current
    task, message in IB (+$3B0): ln_Type 7, `mn_ReplyPort` = WBenchPort, **Class $00020000**, Code =
    1 or 2, other IntuiMessage fields not set (whatever they held); PutMsg; Wait for that signal once;
    GetMsg; FreeSignal;
  - the caller is blocked until the Workbench replies; a Workbench task calling OpenWorkBench /
    CloseWorkBench itself would wait for itself (deadlock) [D]; two tasks sending at the same time
    share the single IB message (no lock) [D].

---

## 5. CurrentTime (LVO −84)

- `CurrentTime(seconds A0, micros A1)`: writes **IB->Seconds (+$48)** to *A0 and **IB->Micros (+$4C)** to
  *A1; returns nothing. [O]
- Source: `ie_TimeStamp` of the **last input event processed** by Intuition() (any class, timer ticks
  included ⇒ ≤ ~100 ms stale while input.device runs), see `intuition-input-menus-v34.md` §1.3 point 4,
  §2.6. Units: seconds and microseconds of the system time as stamped by input.device (timer.device
  system clock, epoch 1-Jan-1978). Before the first event: 0 / 0 (IB is cleared at creation). [O/D]
- No locking, no call to timer.device.

---

## 6. LockIBase (LVO −414) / UnlockIBase (LVO −420)

Complement to `intuition-screens-v34.md` §9:

- Registers: **LockIBase(lock D0)**, **UnlockIBase(lock A0)** — the unlock takes its argument in **A0**
  (matches the 1.3 fd). Return of LockIBase: **D0 = the lock number passed**; UnlockIBase: nothing
  defined. [O]
- Lock n = SignalSemaphore at **IB + $400 + n × $2E**, n = 0…6 (the table ends at IB+$542, followed by
  display-size fields). **No range check**: n ≥ 7 obtains a "semaphore" over unrelated IB fields
  (corruption). n = 0 takes 0 then 5 (released 5 then 0). [O]
- Nesting: exec SignalSemaphores, so the same task may nest calls; each LockIBase must be balanced by an
  UnlockIBase with the same number. Another task blocks. [O]
- Internal use (count of acquisition sites in 34.3): lock 0 ×12, 5 ×10, 2 ×7, 4 ×3, 6 ×1; 1 and 3
  unused. 0 = intuition state (held across a menu or held gadget, `intuition-input-menus-v34.md` §1.2),
  4 = view, 5 = IntuitionBase fields; the roles of 2 and 6 were not characterised (2.0 names them
  GADGETSLOCK and RPLOCK [S]). [O for counts]
- What LockIBase(0) protects for an application: reading IB fields (ActiveWindow, FirstScreen, screen and
  window lists) consistently against the input task. Holding it while calling an intuition function that
  needs another task's cooperation (e.g. a verification) can deadlock. [D]

---

## 6b. BeginRefresh (LVO −354) / EndRefresh (LVO −366)

Added 2026-11-10 (REMAINING-WORK D7). Source: static reading of the two vectors and of the routines they reach
(radare2), cross-checked with the black-box results already in `intuition-gzz-v34.md` §2.5 and
`intuition-windows-v34.md` §2.2. Layer behaviour (BeginUpdate/EndUpdate) is in `layers-v34.md` §5.5 and
`installclipregion-v34.md` §4.1; it is not repeated here.

### 6b.1 Registers [O]

| LVO | Call | Inputs | Result |
|---:|---|---|---|
| −354 | BeginRefresh | window A0 | none (D0 = leftover of the last internal call) |
| −366 | EndRefresh | window A0, complete D0 | none |

- Both are thin register-to-stack relays into compiled code: D0, D1, A0, A1 are scratch; D2–D7 and A2–A6 are
  preserved. A6 must be IntuitionBase (the bodies reach layers and graphics through IntuitionBase fields).
  [O, D for the C register convention]
- **`complete` is tested as a 16-bit word**: only the low word of D0 counts. `EndRefresh(w, $00010000)` behaves as
  `EndRefresh(w, FALSE)`. The low word is sign-extended before being passed to EndUpdate. [O]
- No argument is validated: a NULL window, a window without a layer, or a closed window crashes or corrupts. [O]

### 6b.2 BeginRefresh(window): order of effects [O]

1. `LockLayerInfo(&window->WScreen->LayerInfo)` (screen + $E0).
2. Sets **WINDOWREFRESH** (`$01000000`) in `window->Flags` (+$18).
3. If `window->BorderRPort` (+$3A) is non-NULL (GIMMEZEROZERO window): **`LockLayerRom` of the outer (border)
   layer** (`BorderRPort->Layer`). The outer layer is only *locked*, **not** BeginUpdate'd: its ClipRects stay
   the full visible list, its DamageList is untouched.
4. `BeginUpdate(window->WLayer)` (+$7C, the inner layer for GZZ): the layer's ClipRect list is reduced to its
   damage, and BeginUpdate's `LockLayerRom` of that layer is **kept** until EndRefresh (`layers-v34.md` §5.5).
   BeginUpdate's result (0 on memory failure) is **ignored**: BeginRefresh reports nothing.
5. `UnlockLayerInfo(...)`.

On return the calling task holds the inner layer's lock (and the outer one for GZZ). Any other task that draws
in these layers, intuition's input task included (frame, gadgets, menus over the window), blocks until
EndRefresh. [O for the lock calls, D for the consequence]

**No check of the refresh type.** BeginRefresh does the same on SIMPLE, SMART and SUPER_BITMAP windows and on
NOCAREREFRESH windows. Consequences, from `layers-v34.md` §5.5 [D]:
- With an **empty DamageList** (the normal state of a SMART or SUPER layer, and of a SIMPLE layer that was
  already refreshed) BeginUpdate leaves `ClipRect = NULL`: **everything drawn until EndRefresh is discarded**.
  This is the observable effect of a BeginRefresh on a SMART window that was not damaged.
- With damage (a SIMPLE layer after exposure; any layer to which intuition added frame damage after a
  SizeWindow, `intuition-gzz-v34.md` §2.5) drawing is clipped to the damage, in every refresh type.
- WINDOWREFRESH is set whatever the type.

**No check of WINDOWREFRESH either: nesting is not supported.** A second BeginRefresh before EndRefresh runs a
second BeginUpdate on the same layer. That BeginUpdate saves the **current, already reduced** ClipRect list as
the "normal" list (`_cliprects`, layer +$40, `layers-v34.md` §2), so the normal list saved by the first call is
lost and the following EndRefresh restores the reduced list. Do not nest; an implementation may either refuse
the nested call or reproduce the corruption, but must not rely on it. [O for the saving step, D for the
consequence]

### 6b.3 EndRefresh(window, complete): order of effects [O]

1. `EndUpdate(window->WLayer, (LONG)(WORD)complete)`: with a non-zero word the DamageList is cleared; the normal
   ClipRect list comes back; the layer lock taken by BeginUpdate is released (`layers-v34.md` §5.5).
2. If `BorderRPort` is non-NULL: `UnlockLayerRom` of the outer layer.
3. Clears **WINDOWREFRESH** in `window->Flags`.
4. Only if the low word of `complete` is non-zero: clears **LAYERREFRESH** (`$0080`) in `WLayer->Flags` (+$1E).
   The **outer layer's** LAYERREFRESH is never touched by EndRefresh (the screen repair clears it,
   `intuition-windows-v34.md` §2.2).

- **No LockLayerInfo** in EndRefresh (only BeginRefresh takes it, and only around BeginUpdate).
- **EndRefresh(w, FALSE)**: the DamageList and LAYERREFRESH are kept, so the next screen repair of any cause sends
  another REFRESHWINDOW to this window (`intuition-windows-v34.md` §2.2), and the next BeginRefresh is again
  clipped to the same, possibly larger, damage. This is the intended way to refresh in several passes.
- EndRefresh without a prior BeginRefresh: EndUpdate on a layer that is not updating, then an UnlockLayerRom that
  was not locked (unbalanced semaphore). Not protected. [D]
- EndRefresh repairs nothing by itself: pixels are only what the application drew in between
  (`intuition-gzz-v34.md` §2.5: SIMPLE and SUPER cases observed). [O there]

### 6b.4 Test vectors

| Case | After BeginRefresh | After EndRefresh |
|---|---|---|
| SIMPLE window, damage = whole layer (just opened or resized) | Flags has `$01000000`; WLayer ClipRects = damage ∩ visible; WLayer locked | `complete = 1`: DamageList empty, WLayer Flags lose `$0080`, Flags lose `$01000000` (observed `$0081` → `$0001`, `intuition-gzz-v34.md` §2.5) |
| Same, `complete = 0` | same | DamageList unchanged, LAYERREFRESH still set, WINDOWREFRESH cleared |
| Same, `complete = $00010000` | same | same as `complete = 0` |
| SMART window, no damage, RectFill over the whole window between the two calls | WLayer `ClipRect` = NULL | no pixel changed |
| GZZ window | outer layer locked, its ClipRects and DamageList unchanged | outer LAYERREFRESH unchanged even with `complete = 1` |

---

## 6c. AllocRemember (LVO −396) / FreeRemember (LVO −408)

Added 2026-11-10 (REMAINING-WORK D7). Source: static reading of the vectors and of their compiled bodies.
Callers inside intuition are described in `intuition-screens-v34.md` §2.1 and `intuition-requesters-v34.md` §5.

### 6c.1 Registers and layout [O]

| LVO | Call | Inputs | Result |
|---:|---|---|---|
| −396 | AllocRemember | rememberKey A0 (address of a `struct Remember *`), size D0, flags D1 | D0 = memory or 0 |
| −408 | FreeRemember | rememberKey A0, reallyForget D0 | none |

- D0, D1, A0, A1 scratch; D2–D7 and A2–A6 preserved. A6 must be IntuitionBase: exec is reached through the
  ExecBase pointer kept in IntuitionBase (+$60), not through location 4. [O]
- `struct Remember` (public layout, 12 bytes): `NextRemember` +0, `RememberSize` +4 (ULONG), `Memory` +8.
  `*rememberKey` points to the **most recent** node; the list is LIFO, terminated by NULL. [O]

### 6c.2 AllocRemember(key, size, flags) [O]

1. Remembers the old head `*key`.
2. `AllocMem(12, 0)`: the node itself is allocated with **requirements 0** (any memory, not cleared, not
   MEMF_PUBLIC), whatever `flags`. The result is written **straight into `*key`**; on failure `*key` is put back
   to the old head and 0 is returned.
3. `AllocMem(size, flags)` with the caller's full D0 and D1 (all `MEMF_*` bits honoured, including MEMF_CLEAR,
   MEMF_CHIP). On failure: `FreeMem(node, 12)`, `*key` = old head, return 0.
4. `node->RememberSize = size` (the **requested** size, not rounded), `node->NextRemember = old head`,
   `node->Memory = block`; returns the block.

- Between steps 2 and 4 `*key` points to a node whose fields are not yet written; nothing is locked (no
  Forbid). A key shared between tasks needs the caller's own locking. [O/D]
- `size = 0`: AllocMem returns 0 (`exec-memory-semaphores-v34.md` §2.4), so the node is freed and 0 returned;
  the key is unchanged.
- The two allocations are separate: the node does not live in the remembered block and is not counted in
  `RememberSize`.

### 6c.3 FreeRemember(key, reallyForget) [O]

- **`reallyForget` is tested as a 16-bit word** (low word of D0): `$00010000` means FALSE.
- Walks from `*key` (newest first). For each node: reads `NextRemember` first; if `reallyForget` ≠ 0,
  `FreeMem(node->Memory, node->RememberSize)`; then **always** `FreeMem(node, 12)`. At the end **`*key = NULL`**
  (also when the list was already empty).
- **`reallyForget = FALSE` frees only the 12-byte nodes**: the remembered blocks stay allocated and are no longer
  tracked (this is how intuition keeps a screen's memory after building it, `intuition-screens-v34.md` §2.1
  step 23). It is not a no-op.
- A node whose `Memory`/`RememberSize` were modified by the caller is freed with the modified values (exec
  FreeMem rules apply: a size 0 frees nothing; an address outside every MemHeader is the dead-end alert
  `$81000005`).
- `key` itself is dereferenced without a check (`key = NULL` reads location 0 and then writes NULL to it).

### 6c.4 Test vectors (free memory measured with AvailMem(0) before and after)

| Sequence | Expected |
|---|---|
| `k = NULL`; `p1 = AllocRemember(&k, 100, MEMF_CLEAR)` | `p1` ≠ 0 and 100 bytes of 0; `k->RememberSize = 100`, `k->Memory = p1`, `k->NextRemember = NULL` |
| then `p2 = AllocRemember(&k, 50, 0)` | `k->Memory = p2`, `k->NextRemember` = the first node |
| then `FreeRemember(&k, TRUE)` | `k = NULL`; free memory back to its value before the first call |
| same two allocations, then `FreeRemember(&k, FALSE)` | `k = NULL`; free memory = before − 104 − 56 (the two blocks, rounded to 8, stay allocated; the two 16-byte nodes are freed) |
| same, `FreeRemember(&k, $00010000)` | same as FALSE |
| `AllocRemember(&k, 0, 0)` with `k = X` | returns 0, `k` still X, free memory unchanged |
| `AllocRemember(&k, $7FFFFFF0, 0)` with `k = X` | returns 0, `k` still X, free memory unchanged (node allocated then freed) |

---

## 7. Open points

- First opener of intuition on a normal boot: deduced (dos/initial CLI), not confirmed by a breakpoint.
- Exact moment a new pointer image becomes visible: deduced from graphics (next frame), not measured.
- Roles of locks 2 and 6.
- Whether any 1.3 program calls LVO −36 directly (stack convention) — not scanned.

## Clean-room review

- [x] No instruction sequence transcribed or paraphrased; no ROM routine address. Behaviour is given as
  registers, structure fields and ordered observable effects.
- [x] Values reproduced are ABI/interoperability elements: LVOs, register assignments, public offsets of
  Window/IORequest/Interrupt/IntuiMessage, private IB field offsets already used by the neighbouring
  specs, custom register values (DMACON), alert number, port name, IDCMP class/code values.
- [x] No ROM data (pointer image) reproduced.
- [x] §6b/§6c (added 2026-11-10): same rules; the only values are public Window/Layer/Remember offsets, flag bits,
  library LVOs called and memory flags.
