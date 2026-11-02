# gameport-v34.md — gameport.device 34.1 (Kickstart 1.3, 34.5)

> ANALYSIS track ("dirty"). Behavioural spec of `gameport.device` ("gameport ri 34.1 (18 Aug 1987)") as found in
> the official ROM `kick34005.A500`, written so that the implementation track can implement both units and every
> GPD_* command. Behaviour and ABI only: no ROM address, no ROM offset, no instruction sequence. Public names come
> from the NDK (`devices/gameport.h`, `devices/inputevent.h`, `exec/io.h`, `exec/errors.h`), the RKRM Devices
> chapter "Gameport device" and the HRM (JOYxDAT, POTGO/POTGOR, CIA-A PRA).
>
> Tags: **[M:s]** measured statically (radare2 disassembly of the ROM), **[M:d]** measured dynamically (real ROM
> in Amiberry, `--analysis` session, memory snapshots of the device while moving the mouse and pressing the right
> button), **[M:sd]** both, **[D]** deduced, **[P]** public documentation.
>
> Builds on, and does not contradict: [custom-chips-v34.md](custom-chips-v34.md) §4.2 (potgo, VERTB server,
> readers, buttons) and [coverage-v34.md](coverage-v34.md) §4. **Corrects** one figure of
> [intuiticks-repeat-v34.md](intuiticks-repeat-v34.md) §1.1/§1.2: input.device's default trigger timeout is **0**,
> not 1 (§3.4 below). Resolves the custom-chips open point on the gameport START bit (§7.3).

## 0. Short answer

- Two units, 0 (port 1 connector, JOY0DAT, "mouse port") and 1 (port 2 connector, JOY1DAT, "joystick port").
  OpenDevice of any other unit fails with `IOERR_OPENFAIL` (−1). Units are shared: no exclusivity, no owner, no
  per-opener state; the controller type, the trigger and the event buffer belong to the **unit**, not to the
  opener, and **survive CloseDevice**. [M:s]
- Commands 0-13. Only `GPD_READEVENT` (9) is queued; everything else is executed at once. `CMD_READ`,
  `CMD_WRITE`, `CMD_UPDATE` and `CMD_INVALID` answer `IOERR_NOCMD` (−3); a command number ≥ 14 is treated as
  0 (→ −3). [M:s]
- `GPD_SETCTYPE` accepts one signed byte: −1 (GPCT_ALLOCATED), 0 (NOCONTROLLER), 1 (MOUSE), 2 (RELJOYSTICK),
  3 (ABSJOYSTICK). It is **not range-checked**: any other value is undefined behaviour (crash). It resets the
  unit's button state, frame counter and accumulators, never the event buffer or the trigger. MOUSE and both
  joystick types allocate the unit's four pot bits (`$0F00 << 4·unit`); `GPDERR_SETCTYPE` (1) is returned when
  potgo.resource refuses them, but the new type stays in force. [M:s]
- GPCT_ALLOCATED is only a stored value: it behaves exactly like NOCONTROLLER (no reading, pot bits freed) and
  does not stop anybody from setting another type later. [M:s]
- The **trigger is all zeros after boot** on unit 1 (and on unit 0 until input.device sets it). With an all-zero
  trigger **no event is ever produced**: a program must send `GPD_SETTRIGGER`. [M:sd]
- Each vertical blank, for unit 0 then unit 1, the server samples the controller and decides whether to produce
  one event: a button transition allowed by `keys`, an accumulated (relative types) or changed (absolute type)
  axis value reaching `xdelta`/`ydelta`, or `timeout` frames elapsed since the last event. At most **one event
  per unit per frame**, and at most **one button transition per event**. [M:sd]
- Events go to an 8-slot ring (**7 usable**); when it is full nothing is lost from the button state or the
  relative accumulators — the event is simply produced later (§5.5). [M:s]
- `GPD_READEVENT` fills `io_Length / 22` InputEvents (at least one, otherwise `IOERR_BADLENGTH` −4), with
  whatever is buffered, chained through `ie_NextEvent`; it never waits for more than **one** event: it completes
  as soon as at least one event has been copied. **V34 bug**: when the request has room for more events than
  are buffered, the device leaves one `Disable` unbalanced (§5.3). [M:s]
- Every event is `ie_Class = IECLASS_RAWMOUSE` (2), `ie_SubClass = unit number`, `ie_Code` = IECODE_LBUTTON /
  RBUTTON / MBUTTON (with `IECODE_UP_PREFIX` for a release) or `IECODE_NOBUTTON` ($FF), `ie_Qualifier` = button
  qualifiers + `IEQUALIFIER_RELATIVEMOUSE` for mouse and relative joystick, `ie_X/ie_Y` = mouse counts or joystick
  −1/0/+1 (relative types: accumulated since the previous event; absolute type: current position). Only the high
  word of `tv_secs` in `ie_TimeStamp` is meaningful: it holds the number of frames since the previous event. [M:sd]

## 1. Device base, units, Open / Close / Expunge

### 1.1 Base and per-unit state [M:s]

- COLDSTART resident, pri 60, after keyboard.device; device node `gameport.device`, version 34, revision 1,
  `lib_Flags` = SUMUSED|CHANGED. Function table: Open, Close, Expunge, the null vector, BeginIO, AbortIO.
  BeginIO/AbortIO, the reply routine and commands 0-8 are the code shared with keyboard.device and input.device
  (same dispatcher as described for console.device in [console-keymap-v34.md](console-keymap-v34.md) §2.4).
- Positive size of the base: **333 bytes**. Besides the Library header it holds: the ExecBase pointer, the
  command table and per-command type table and the command count (14), the potgo.resource base (opened at init),
  the two units, one `Interrupt` node (NT_INTERRUPT, pri 0, name `gameport.device`, `is_Data` = device base) used
  as VERTB server, and three potgo words (§7.2).
- Init: `OpenResource("potgo.resource")`, initialise both unit ports, `AddIntServer(INTB_VERTB, …)`, then CIA-A
  DDRA bits 6 and 7 := 0 (fire buttons as inputs) and PRA bits 6/7 := 1. No pot bit is allocated, no POTGO write
  at init (the server writes POTGO `$0000` every frame until a type is set, custom-chips §4.2).
- Each **unit** is 124 bytes and holds, in this order of meaning:

| Field | Size | Role |
|---|---|---|
| MsgPort | 34 | request queue of `GPD_READEVENT` (a plain MsgPort, PA_SIGNAL with no SigTask: `PutMsg` only queues). Its `ln_Pri` byte carries the "stopped" flag (CMD_STOP) |
| read index, write index | 2 + 2 | byte offsets into the ring, step 8, modulo 64 |
| event ring | 8 × 8 | per slot: code byte, qualifier high byte, X word, Y word, frame-count word |
| trigger | 8 | `struct GamePortTrigger` image: `gpt_Keys`, `gpt_Timeout`, `gpt_XDelta`, `gpt_YDelta` (UWORDs) |
| button state | 2 | pressed buttons as *known to the device* (bit 15 left/fire, 14 right, 13 middle) |
| frame counter | 2 | frames since the last event produced, saturating at 65535 |
| X, Y | 2 + 2 | relative types: accumulated motion; absolute type: current position |
| last reported Y, X | 1 + 1 | absolute type only: the axis values of the last event triggered by that axis |
| JOYxDAT reference | 2 | mouse only: previous JOYxDAT sample |
| flags | 1 | "unit 1" (constant, set at init for unit 1), "relative mode", "skip next frame" |
| controller type | 1 | signed GPCT_* value |

  All fields start at zero (the base is allocated cleared); only the "unit 1" flag is preset.

### 1.2 OpenDevice [M:s]

- exec `OpenDevice` clears `io_Error` and `io_Unit` before calling the device's Open.
- Unit number (D0): 0 → unit 0, 1 → unit 1. Anything else: `io_Error := IOERR_OPENFAIL` (−1), `lib_OpenCnt`
  unchanged, `io_Unit` stays 0 (`io_Device` was already written by exec and is not cleared).
- Success: `io_Unit` := pointer to the unit structure, LIBF_DELEXP cleared, `lib_OpenCnt++`. Flags (D1), the
  request size and any previous opener are ignored. Nothing in the unit is reset: type, trigger, buffered events
  and button state are whatever the last user left.

### 1.3 CloseDevice and Expunge [M:s]

- Close: `io_Unit := 0`, `io_Device := 0`, `lib_OpenCnt--`; if it reaches 0 and LIBF_DELEXP is set, Expunge.
  Returns 0. Close does **not** abort queued `GPD_READEVENT`s (a request left queued is still filled and replied
  later by the VERTB server, into memory the caller may have freed), does **not** reset the controller type and
  does **not** free the pot bits: a unit set to a joystick keeps being read every frame after its last Close.
- Expunge: with openers, sets LIBF_DELEXP and returns 0. Otherwise removes the VERTB server, frees the base and
  unlinks the device (seglist returned). Pot bits are not freed. (Never happens in practice: the device is in ROM
  and input.device keeps it open.)

## 2. BeginIO, AbortIO, commands

### 2.1 Dispatcher [M:s]

1. `io_Flags &= $0F` (IOF_QUICK kept, private bits 4-7 cleared), `io_Error := 0`.
2. `io_Command ≥ 14` → treated as command 0.
3. Immediate commands are called at once in the caller's context. `GPD_READEVENT` is queued: under `Disable` it
   is `PutMsg`'d to the unit's port (ln_Type becomes NT_MESSAGE); if it is now the first request of the queue it
   is marked "current" and, unless the unit is stopped, executed at once; otherwise IOF_QUICK is cleared and
   BeginIO returns (the request will be completed later and `ReplyMsg`'d).
4. Reply (common routine): under `Disable`; a request already replied is left alone (so a request is never
   replied twice); sets `io_Error`, removes the request from the unit queue if it was in it (the next one becomes
   "current", but is not started from here), then `ReplyMsg` only if IOF_QUICK is clear.

### 2.2 Command table [M:s]

| No. | Command | Kind | V34 behaviour |
|---:|---|---|---|
| 0 | CMD_INVALID | immediate | reply `IOERR_NOCMD` (−3) |
| 1 | CMD_RESET | immediate | = CMD_STOP, CMD_FLUSH, CMD_START in sequence; the request is replied by the STOP step, with an **uninitialised** `io_Error` (low byte of the caller's D0); the later steps cannot reply again. Leaves the unit **running**, queue flushed. Type, trigger, ring untouched |
| 2 | CMD_READ | immediate | `IOERR_NOCMD` |
| 3 | CMD_WRITE | immediate | `IOERR_NOCMD` |
| 4 | CMD_UPDATE | immediate | `IOERR_NOCMD` |
| 5 | CMD_CLEAR | immediate | empties the event ring (read = write = 0) under Disable. Button state, accumulators, counter, last-reported values are **not** reset. **Never replies**: `io_Error` stays 0, IOF_QUICK unchanged; sent with SendIO (no IOF_QUICK) the request never comes back (same as console.device's CMD_CLEAR) |
| 6 | CMD_STOP | immediate | sets the unit's stopped flag; reply with uninitialised `io_Error` |
| 7 | CMD_START | immediate | clears the stopped flag; if a request is queued, runs the head request's command (GPD_READEVENT) now; reply with uninitialised `io_Error` |
| 8 | CMD_FLUSH | immediate | replies every queued request with `IOERR_ABORTED` (−2), then replies itself (its `io_Error` = −2 if something was flushed, otherwise uninitialised) |
| 9 | GPD_READEVENT | queued | §5 |
| 10 | GPD_ASKCTYPE | immediate | §3.1 |
| 11 | GPD_SETCTYPE | immediate | §3.2 |
| 12 | GPD_ASKTRIGGER | immediate | §4.1 |
| 13 | GPD_SETTRIGGER | immediate | §4.1 |

- "Uninitialised io_Error": the shared STOP/START/FLUSH/RESET code passes whatever D0 holds on entry to the reply
  routine. With `DoIO` that is the caller's D0. A reimplementation should return 0; callers cannot rely on the
  original value. [M:s][D]
- **CMD_STOP is weak on gameport**: it only stops BeginIO from starting a new request; the VERTB server serves
  the head of the queue whenever it produces an event, **without checking the stopped flag**. So a stopped unit
  still completes queued `GPD_READEVENT`s at the next event. [M:s]

### 2.3 AbortIO [M:s]

- Shared routine: reply with `io_Error := IOERR_ABORTED` (−2) if the request has not been replied yet; it is
  removed from the unit queue and `ReplyMsg`'d (IOF_QUICK is clear for any request that was left pending).
  Aborting an already completed request does nothing. Aborting the current request does not start the next one
  (the next event will). The caller must still `WaitIO`/`GetMsg` it. D0 on return is not meaningful.

## 3. Controller type

### 3.1 GPD_ASKCTYPE [M:s]

- Low 16 bits of `io_Length` must be ≥ 1, else `IOERR_BADLENGTH` (−4) (`io_Actual` untouched).
- Writes **one byte** (the signed type) to `io_Data`, `io_Actual := 1`, `io_Error := 0`. After boot: unit 0 =
  1 (MOUSE, set by input.device), unit 1 = 0 (NOCONTROLLER). [M:sd]

### 3.2 GPD_SETCTYPE [M:s]

- Low 16 bits of `io_Length` must be ≥ 1, else −4 and nothing changes.
- Under `Disable`:
  1. button state, frame counter, X and Y := 0; last-reported X/Y := 0; JOYxDAT reference := 0;
  2. type := the signed byte at `io_Data` (no check, no ownership test — any opener can change it at any time,
     including over GPCT_ALLOCATED);
  3. flags: "relative mode" and "skip next frame" set;
  4. per type:
     - **−1 GPCT_ALLOCATED, 0 GPCT_NOCONTROLLER**: the unit's pot bits are released (§7.2). The server ignores the
       unit from now on.
     - **1 GPCT_MOUSE**: reference sample := current JOYxDAT of the unit, then pot bits allocated.
     - **2 GPCT_RELJOYSTICK**: pot bits allocated (relative mode stays set).
     - **3 GPCT_ABSJOYSTICK**: relative mode cleared, pot bits allocated.
     - **any other value**: the device jumps through an index outside its type table → crash (undefined). A
       reimplementation should reject such values (e.g. `GPDERR_SETCTYPE`) rather than reproduce this.
  5. For types 1-3: if potgo.resource did not grant all four bits of the unit, `io_Error := GPDERR_SETCTYPE`
     (1). **The type is still set** (ASKCTYPE reports it, the server reads the controller), only the pot pins
     are not driven by the device; right/middle buttons are then still read from POTGOR.
- `io_Actual := 1` (also on GPDERR_SETCTYPE), reply.
- Not touched: the event ring (old events of the previous controller stay buffered — send CMD_CLEAR), the
  trigger, the request queue.
- The frame right after SETCTYPE is skipped entirely by the server (no sampling, no counter increment). [M:s]
- Consequence of the reset of the button state: a button already held when SETCTYPE runs produces a DOWN event
  (if `keys` asks for it) on the second frame. [D]

### 3.3 Pot bits and GPDERR_SETCTYPE in practice [M:s][D]

- Unit 0 asks for `$0F00` (OUTLY|DATLY|OUTLX|DATLX), unit 1 for `$F000` (OUTRY|DATRY|OUTRX|DATRX).
- The device frees **all** its own bits and re-requests the union for both units at every SETCTYPE (§7.2), so
  re-setting a type the device already holds always succeeds. GPDERR_SETCTYPE only happens when a third party
  holds some of those bits through potgo.resource `AllocPotBits`.

### 3.4 What input.device does with gameport [M:sd]

- Its task opens `gameport.device` unit = mouse port (default 0, `IND_SETMPORT`), sends `GPD_SETCTYPE` (1 byte,
  default 1 = MOUSE, `IND_SETMTYPE`) and `GPD_SETTRIGGER` (8 bytes, `IND_SETMTRIG`) synchronously, ignoring the
  errors, then keeps **exactly one** `GPD_READEVENT` outstanding with `io_Length` = 22 (one event), re-sent
  after each completion.
- Default trigger: **keys = 3 (DOWNKEYS|UPKEYS), timeout = 0, xdelta = 1, ydelta = 1**. Measured in the live
  unit 0 state of the real ROM, and consistent with input.device's initial data (keys word and the two delta
  words set, timeout left zero). [M:sd] — [intuiticks-repeat-v34.md](intuiticks-repeat-v34.md) states timeout 1;
  that figure is wrong. Consequence: an idle mouse produces **no** gameport events (measured: the unit's frame
  counter had climbed to several thousand frames at the insert-disk screen with an empty ring).
- input.device replaces `ie_TimeStamp` with the system time and merges the qualifier
  ([intuiticks-repeat-v34.md](intuiticks-repeat-v34.md) §1.5).
- On a port change it aborts its request and closes/reopens gameport on the new unit **without** resetting the
  old unit's type (the old unit stays a mouse for the device).

## 4. Trigger

### 4.1 GPD_ASKTRIGGER / GPD_SETTRIGGER [M:s]

- Data: `struct GamePortTrigger` = `UWORD gpt_Keys; UWORD gpt_Timeout; UWORD gpt_XDelta; UWORD gpt_YDelta;`
  (8 bytes, even address expected).
- Low 16 bits of `io_Length` must be ≥ 8, else −4. Copies 8 bytes from/to the unit; `io_Actual := 8`,
  `io_Error := 0`.
- SETTRIGGER performs **no validation and no reset**: frame counter, accumulators, button state and ring are kept;
  the new values apply from the next frame.
- After boot: unit 0 = input.device's trigger (§3.4); unit 1 = all zero. A trigger stays in the unit after
  CloseDevice.

### 4.2 Semantics (evaluated once per frame per unit, in this order) [M:sd]

1. **Axes**
   - Relative types (MOUSE, RELJOYSTICK): this frame's X/Y (mouse counts, or −1/0/+1) are **added** to the signed
     word accumulators. An axis triggers when its delta is non-zero and `delta ≤ |accumulator|` (signed word
     compare: a delta ≥ $8000 triggers on every frame). Both axes are tested independently; either is enough.
   - Absolute type (ABSJOYSTICK): X/Y := this frame's −1/0/+1 position. An axis triggers when its delta is
     non-zero and `delta ≤ |position − last reported position|` for that axis; the last reported value of **that
     axis** is then updated. With delta = 1 this means "an event on every change of that axis"; delta ≥ 3 can
     never trigger.
   - Delta = 0 disables that axis as a trigger (motion is still accumulated and reported in the next event).
2. **Ring full?** If the ring has no free slot, the unit stops here for this frame (§5.5).
3. **Buttons** (`gpt_Keys`: bit 0 GPTF_DOWNKEYS, bit 1 GPTF_UPKEYS; only the low byte is looked at):
   - newly pressed buttons (pressed now, not in the known state): if DOWNKEYS, the **highest** one (left/fire >
     right > middle) produces this event's code and only that bit is added to the known state; the others will be
     reported on following frames; release processing is skipped this frame. Without DOWNKEYS, all new presses
     are silently added to the known state.
   - otherwise, newly released buttons: if UPKEYS, the highest one gives the code (with the up prefix) and only that
     bit is removed from the known state; without UPKEYS, all releases are silently removed.
   - so a transition that `keys` does not ask for is never reported later, and with `keys` = 3 every transition is
     reported exactly once, one per frame.
4. **Timeout**: if nothing above triggered, an event is produced when `gpt_Timeout ≠ 0` and frame counter ≥
   `gpt_Timeout` (unsigned). The counter is incremented at the start of every frame (saturating at 65535) and
   reset to 0 by every event, so `timeout = n` gives an event every n frames while nothing else happens
   (`timeout = 1` = every frame). Timeout 0 = never.
5. **After an event**: frame counter := 0, X and Y := 0 (relative accumulators cleared; for the absolute type the
   position is re-sampled next frame anyway). The last-reported absolute values are changed only by step 1.
- With an all-zero trigger nothing ever triggers: the unit is sampled but never produces events.

## 5. GPD_READEVENT

### 5.1 Rules [M:s]

- `io_Data` → array of InputEvents; `io_Length` ≥ 22 (`sizeof(struct InputEvent)`), else reply
  `IOERR_BADLENGTH` (−4) with `io_Actual` untouched (the next queued request is then processed).
- Capacity = ⌊io_Length / 22⌋ events. Queue: requests are served in FIFO order, one at a time (only the head).
- When run (at BeginIO if it is the head and the unit is not stopped, or from the VERTB server right after an
  event was buffered, or from CMD_START):
  - ring empty → IOF_QUICK cleared, the request stays at the head of the queue (DoIO then waits). Nothing written.
  - otherwise copies buffered events, oldest first, until the ring is empty or the array is full; each copied
    event's `ie_NextEvent` points to the next array element, the last one's is NULL. `io_Actual` = number of
    **bytes** written (22 × events), `io_Error` = 0, reply (no `ReplyMsg` if IOF_QUICK is still set, i.e. DoIO
    satisfied immediately). Then, if another request is queued, it is run in turn (it normally finds the ring
    empty and waits).
- Hence a request never accumulates events across frames: it completes as soon as ≥ 1 event exists. A request with
  room for 8 events gets them only if they were buffered beforehand (e.g. while no request was pending).
- A private "in progress" flag in `io_Flags` (bit 6) keeps the server from re-entering a request being filled by
  the task; the server's event then waits in the ring for the next request.

### 5.2 Buffering without a request [M:s]

- Events are produced whether or not a request is pending. The ring has 8 slots of which **7** can be full
  (write index never catches the read index).

### 5.3 V34 bug: unbalanced Disable [M:s]

- The copy loop takes `Disable` at the top of each iteration. When it stops because the **ring became empty**
  (i.e. the array had room for more events than were buffered: io_Length ≥ 44 and fewer buffered events than its
  capacity), it leaves without the matching `Enable`. ExecBase IDNestCnt stays one higher: interrupts remain
  disabled for the calling task (exec restores the per-task nest count on task switches, so other tasks are not
  affected once a switch happens); if the run was started from the VERTB server, the leak is in interrupt context
  and interrupts stay off until some task does an `Enable`.
- Requests of exactly 22 bytes (input.device, the RKRM examples) never hit it. A reimplementation should balance
  the Disable (reproducing it only freezes programs that read several events at once). Not yet confirmed by a
  black-box run (probe §9).

### 5.4 CMD_CLEAR and AbortIO

- CMD_CLEAR drops the buffered events only (§2.2). AbortIO: §2.3 (−2, removed, replied).

### 5.5 Ring full [M:s][D]

- The decision step 2 (§4.2) returns before buttons are examined: the known button state is not updated, the
  counter keeps rising, relative accumulators keep growing. Nothing is lost: when a slot frees, the next frame
  reports the accumulated motion and the pending transitions (one per frame).
- Exception, absolute type: if an axis triggered in the frame where the ring was full, its last-reported value
  was already updated, so that change is **not** reported later (lost).

## 6. Event construction

### 6.1 Sampling (per frame, per unit with type 1-3) [M:sd]

Buttons (all types, active low; unit 0 / unit 1):
- left / fire: CIA-A PRA bit 6 / bit 7;
- right: POTGOR DATLY (bit 10) / DATRY (bit 14);
- middle: POTGOR DATLX (bit 8) / DATRX (bit 12).
  The device's known button word uses bit 15 = left/fire, 14 = right, 13 = middle for both units. Right and middle
  are read for joysticks too (second/third fire buttons).

Motion:
- MOUSE: X = (JOYxDAT low byte − previous low byte), Y = (high byte − previous high byte), each as a signed 8-bit
  difference (wrap-around absorbed), sign-extended; the reference sample is then replaced. Max ±127 counts per
  frame per axis.
- Joysticks: X and Y in {−1, 0, +1} from JOYxDAT bits 0, 1, 8, 9 with the HRM formula: right = bit 1, left =
  bit 9, down = bit 1 XOR bit 0, up = bit 9 XOR bit 8; X = right − left, Y = down − up (down positive, up
  negative). Impossible combinations (both opposite directions decoded) give 0 on that axis — with one exception
  of the ROM's decode table: when left, up and down are all decoded (bit 9 = 1, bit 8 = 0, bit 1 = 0, bit 0 = 1)
  the result is (0, 0) instead of (−1, 0). Not reachable with a normal digital stick.

### 6.2 InputEvent fields (as written by GPD_READEVENT) [M:sd]

| Field | Value |
|---|---|
| `ie_NextEvent` | next element of the caller's array, NULL for the last one |
| `ie_Class` | 2 = IECLASS_RAWMOUSE, for **every** controller type |
| `ie_SubClass` | unit number (0 or 1) |
| `ie_Code` (UWORD) | `$0068` IECODE_LBUTTON (left/fire), `$0069` IECODE_RBUTTON, `$006A` IECODE_MBUTTON; `$00E8`/`$00E9`/`$00EA` for the releases (IECODE_UP_PREFIX); `$00FF` IECODE_NOBUTTON when the event was triggered by motion or timeout |
| `ie_Qualifier` | high byte only (low byte 0): `$4000` IEQUALIFIER_LEFTBUTTON, `$2000` IEQUALIFIER_RBUTTON, `$1000` IEQUALIFIER_MIDBUTTON for each button in the known state **after** this event's transition (a press includes its own bit, a release no longer has it), plus `$8000` IEQUALIFIER_RELATIVEMOUSE for MOUSE and RELJOYSTICK (not for ABSJOYSTICK) |
| `ie_X`, `ie_Y` | relative types: accumulated motion since the previous event (signed words; joystick: number of frames deflected, signed); ABSJOYSTICK: the current position −1/0/+1 |
| `ie_TimeStamp.tv_secs` | **high word** = frames elapsed since the previous event of the unit (saturating 65535, the frame counter at emission); **low word = junk** (two bytes of the next ring slot, or of the trigger for the last slot) |
| `ie_TimeStamp.tv_micro` | not written (keeps what the caller's buffer contained) |

- Measured on the real ROM (mouse unit 0, input.device trigger): a move of 30 counts to the right produced
  {code $FF, qualifier `$8000` (RELATIVEMOUSE only), X = 30, Y = 0, frames = a few thousand}; pressing the right button then
  produced {code $69, qualifier `$A000`, X = Y = 0, frames = 18}; the known button word held only the right bit.
  [M:d]
- Joystick held right with RELJOYSTICK and xdelta = 1: one event per frame, X = +1, code $FF. With xdelta = 0,
  ydelta = 0 and timeout = 10: one event every 10 frames carrying X = +10. ABSJOYSTICK with deltas 1: one event
  per change, X/Y = new position, e.g. {+1, 0} on deflection and {0, 0} on return to centre. [D, from §4.2]
- No vertical-blank timestamp from timer.device and no system time is involved.

## 7. The VERTB server

### 7.1 Order and per-unit work [M:sd]

- One server, pri 0, on the VERTB chain after graphics (pri 10) and before timer.device (pri 0) — see
  [timer-v34.md](timer-v34.md). Returns with Z set (chain continues).
- Unit 0 first, then unit 1, then the POTGO write. For each unit:
  1. if "skip next frame" is set (just after SETCTYPE): clear it, done for this unit;
  2. frame counter + 1 (saturating) — done for every unit, even without controller;
  3. type not in 1-3 (NOCONTROLLER, ALLOCATED): done;
  4. sample (§6.1), decide (§4.2), store at most one event, then if a request is queued run GPD_READEVENT on the
     head (in interrupt context, under the server).

### 7.2 Pot bits and POTGO [M:sd]

- The device keeps three words: *requested* bits (both units), *allocated* bits (what `AllocPotBits` granted),
  and the *POTGO data* word.
- SETCTYPE of a unit: `FreePotBits(allocated)`; remove the unit's four bits (and its private START flag, see §7.3)
  from requested and from data; for types 1-3 add `$0F00 << 4·unit` to requested and to data (pins driven high);
  allocated := `AllocPotBits(requested)`.
- Every frame, after both units: `WritePotgo(data, allocated)`. So: no type → `$0000` (mask 0, POTGO written
  with nothing driven); mouse on unit 0 → `$0F00`; plus a joystick on unit 1 → `$FF00`. Bits the device failed to
  allocate are never written by it.

### 7.3 START bit [M:s]

- The device has a private per-unit "start" flag (bit 0 of its words for unit 0, bit 4 for unit 1) which the
  server would translate into POTGO START. No command or type ever sets it: it is only ever cleared. Proportional
  joysticks / paddles (POT0DAT/POT1DAT) are not supported by 1.3. This settles the open point of
  custom-chips-v34.md.

## 8. What a game using unit 1 notices

1. Typical RKRM sequence: CreatePort/CreateStdIO; `OpenDevice("gameport.device", 1, req, 0)`; under Forbid,
   `GPD_ASKCTYPE` and, if it reads GPCT_NOCONTROLLER, `GPD_SETCTYPE` GPCT_RELJOYSTICK or ABSJOYSTICK (some
   programs set GPCT_ALLOCATED first as a "lock"); `GPD_SETTRIGGER` (e.g. keys = DOWNKEYS|UPKEYS, timeout = 0
   or a few frames, deltas = 1); `CMD_CLEAR`; then loop on `SendIO(GPD_READEVENT, 22 bytes)` + Wait; at exit
   AbortIO/WaitIO, `GPD_SETCTYPE` NOCONTROLLER, CloseDevice. All of these work as described.
2. Opening unit 1 and reading without SETCTYPE: the type is NOCONTROLLER, so the request **never completes**
   (the unit is never sampled). Same if the trigger is left at zero after SETCTYPE.
3. Nothing is reset at Open: a program that opens unit 1 after another one finds the previous type, trigger and
   possibly stale buffered events; a program that forgets to restore NOCONTROLLER leaves the port being read and
   POTGO `$F000` driven after it quits.
4. The joystick events are IECLASS_RAWMOUSE with SubClass 1 and the mouse-button codes: fire = IECODE_LBUTTON;
   second/third buttons (POTGOR) appear as RBUTTON/MBUTTON. Y is positive **down**.
5. A held direction with RELJOYSTICK, delta 1 → 50 (PAL) / 60 (NTSC) events per second; the ring holds 7, so a
   program that reads slowly sees the motion coalesced into larger X/Y values rather than lost.
6. Code $FF events are frequent; programs must ignore NOBUTTON when looking for fire.
7. Unit 0 is permanently owned by input.device's outstanding READEVENT: a second program reading unit 0 competes
   with it (requests are served FIFO, one event each) and steals mouse events from Intuition — the reason the
   RKRM tells programs to use unit 1 (or change input.device's port).
8. A reader with `io_Length` > 22 risks the Disable leak (§5.3) on the real 1.3.
9. GPD_SETCTYPE with a byte outside −1…3 crashes the real ROM.

## 9. Probes that would refine this page (described, not written)

- **Disable leak probe** (§5.3): open unit 1, SETCTYPE RELJOYSTICK, SETTRIGGER {keys 3, timeout 1, deltas 0}
  (one event per frame), CMD_CLEAR, wait two frames, then DoIO a GPD_READEVENT with io_Length = 10 × 22; print
  `io_Actual` and ExecBase IDNestCnt before and after (and whether a later `Wait` still lets the system run).
  Expected on V34: io_Actual = 22 × buffered events (2), IDNestCnt one higher after the call.
- **Abs/rel joystick probe**: with the emulator's joystick on port 2, record events (code, qualifier, X, Y, high
  word of tv_secs) for: right held 10 frames, fire press/release, both while holding right; for the three types and
  triggers {3,0,1,1}, {3,10,0,0}, {1,0,0,0}. Expected: §4.2/§6.2.
- **Ring-full probe**: SETTRIGGER timeout 1 with no pending request for 20 frames, then read with io_Length
  22 × 10: expect 7 events (each with frames = 1) and the eighth onward produced later with a larger frame count.
- **CMD_STOP probe**: stop the unit, queue a READEVENT, move the joystick: expect completion anyway.

## Open points

- §5.3 is static only (probe above). Real-hardware impact depends on what the program does next.
- Whether any 1.3 program relies on the junk low word of `tv_secs` or on `tv_micro` being untouched — unknown;
  zero would be the natural choice for a reimplementation (only the high word is defined by the device).
- The CMD_RESET / STOP / START / FLUSH `io_Error` values are uninitialised in the ROM; the value seen through DoIO
  depends on the caller's D0 (not measured).

## Clean-room review

Review of 2026-11-02.

- [x] No 68000 instruction sequence transcribed or paraphrased line by line; no disassembly or decompiler excerpt.
  Behaviour is described as rules, orders of operations and values.
- [x] No ROM routine or data address, no ROM offset. Values cited are public constants (GPD_*, GPCT_*, IECODE_*,
  IEQUALIFIER_*, IOERR_*, register bits of the HRM), sizes, and values observed in RAM on the running ROM.
- [x] The private device/unit layout is given as fields, sizes and meanings (ABI-style); no field offset of the
  device base is needed by the implementation and none is given except sizes.
- [x] The two ROM tables involved (button-code table, joystick decode table) are described by their meaning (the
  public IECODE values and the HRM formula, plus the one deviating entry), not dumped.
- [x] Tools and raw outputs (radare2 listings, gdb memory dumps) stayed outside the repository (scratch area and
  `build/amiberry/analysis/`).
