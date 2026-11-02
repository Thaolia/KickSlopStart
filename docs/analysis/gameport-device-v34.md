# gameport-device-v34.md — gameport.device 34.1 (Kickstart 1.3) full contract

> ANALYSIS track ("dirty"). Source: ROM `assets/kick34005.A500` (static reading of the gameport.device module and of
> the command/IO code it shares with keyboard.device and input.device), plus one black-box check of the live state
> of the real ROM under Amiberry (insert-disk screen, 2026-11-02). No ROM addresses, no instruction listings.
>
> **Legend**: **[S]** static reading of the ROM · **[O]** observed at run time on the real ROM · **[D]** deduced.
> Related pages: [custom-chips-v34.md](custom-chips-v34.md) §4.2 (potgo.resource, VERTB server, mouse path — this
> page refines it), [intuiticks-repeat-v34.md](intuiticks-repeat-v34.md) §1 (how input.device drives gameport),
> [keyboard-input-devices-v34.md](keyboard-input-devices-v34.md) (generic commands of the sister devices).

---

## 0. Short answer: what a program needs

1. **input.device needs** (this is what boots the mouse on the real ROM): `OpenDevice("gameport.device", 0)`,
   `GPD_SETCTYPE` (1 byte, `GPCT_MOUSE`), `GPD_SETTRIGGER` (8 bytes, `{3, 0, 1, 1}`), then **one `GPD_READEVENT` of
   io_Length 22 always pending**, re-sent after every reply; on `IND_SETMPORT/SETMTYPE/SETMTRIG`, `AbortIO` +
   `WaitIO` + `CloseDevice` then the same sequence again (§7).
2. **Games / controller tests** (unit 1 joystick, or unit 0 after taking it): `GPD_ASKCTYPE` (expect
   `GPCT_NOCONTROLLER` = 0 on unit 1), `GPD_SETCTYPE` (`GPCT_ABSJOYSTICK` 3 or `GPCT_RELJOYSTICK` 2),
   `GPD_SETTRIGGER` (**mandatory**: a fresh unit has an all-zero trigger and produces no event at all), then
   `GPD_READEVENT` (synchronous `DoIO` or `SendIO`/`WaitIO`, possibly with `AbortIO`), and at the end
   `GPD_SETCTYPE` back to `GPCT_NOCONTROLLER`, `CMD_CLEAR`, `CloseDevice`.
3. **Every command must be accepted** with the io_Error values of §3. Refusing them (IOERR_NOCMD) makes clean
   gameport software fail; an internal mouse poller is invisible to software only as long as nobody calls
   gameport.

---

## 1. Device, units, Open/Close/Expunge

### 1.1 Device base (private layout, size `$14D` bytes, allocated cleared) [S]

| Offset | Size | Contents |
|---|---|---|
| `$00` | `$22` | `Library` (NT_DEVICE, name `"gameport.device"`, version 34, revision 1, flags SUMUSED\|CHANGED) |
| `$22` | 4 | segment list given to the init (returned by Expunge) |
| `$26` | 4 | ExecBase |
| `$2A` | 4 | pointer to the command routine table (14 entries) |
| `$2E` | 4 | pointer to the per-command "queue" byte table (§2) |
| `$32` | 2 | number of commands = 14 |
| `$34` | 4 | potgo.resource base |
| `$38` | `$7C` | **unit 0** (§1.2) |
| `$B4` | `$7C` | **unit 1** |
| `$130` | `$16` | `Interrupt` of the VERTB server (NT_INTERRUPT, pri 0, name `"gameport.device"`, is_Data = device base) |
| `$146` | 2 | pot bits **requested** by the device (union of both units) |
| `$148` | 2 | pot bits **granted** by `AllocPotBits` (this is the mask passed to `WritePotgo`) |
| `$14A` | 2 | POTGO value written every frame (`$0F00 << 4·unit` for each configured unit) |

### 1.2 Unit structure (private, `$7C` bytes; io_Unit points to its start) [S]

| Offset | Size | Contents |
|---|---|---|
| `$00` | `$22` | `MsgPort` (ln_Type NT_MSGPORT, name `"gameport.device"`): its list is the queue of `GPD_READEVENT` requests. The port is never signalled by anybody (no SigTask): requests are only put in it. **ln_Pri byte (`+$09`) bit 0 = "unit stopped"** (CMD_STOP/START). |
| `$22` | 2 | ring read index (byte offset, 0..`$38`, step 8) |
| `$24` | 2 | ring write index |
| `$26` | `$40` | event ring: **8 slots of 8 bytes** (holds at most **7** events, one slot is sacrificed) |
| `$66` | 8 | trigger, public `GamePortTrigger` layout (§5) |
| `$6E` | 2 | reported button state (bit 15 left, 14 right, 13 middle) |
| `$70` | 2 | frame counter since the last event (saturates at `$FFFF`) |
| `$72` | 2 | X: accumulated delta (relative types) / current position (absolute joystick) |
| `$74` | 2 | Y: same |
| `$76` | 2 | absolute joystick: last reported Y (high byte) / X (low byte) |
| `$78` | 2 | mouse: previous JOYxDAT sample |
| `$7A` | 1 | flags: bit 1 "skip next frame" (set by every SETCTYPE), bit 2 "this is unit 1" (preset for unit 1, it selects the register/bit shift), bit 3 "relative" (mouse, relative joystick) |
| `$7B` | 1 | controller type (signed byte, GPCT_*) |

Ring slot layout (8 bytes): code byte, qualifier high byte, X word, Y word, frame-counter word (the value of `$70`
when the event was made). [S]

### 1.3 Init (COLDSTART resident, pri 60) [S]

MakeLibrary (memory cleared), then: ExecBase stored, `OpenResource("potgo.resource")`, both unit ports' lists
initialised, VERTB server added (`AddIntServer(INTB_VERTB = 5)`), CIA-A DDRA bits 6 and 7 cleared (fire buttons
are inputs) and CIA-A PRA bits 6 and 7 set. Both units start with type 0 (`GPCT_NOCONTROLLER`), trigger `{0,0,0,0}`,
no pot bits. **The device itself never configures any unit**: unit 0 becomes a mouse only because input.device
sends `GPD_SETCTYPE` (§7).

### 1.4 OpenDevice [S]

- D0 = unit: **0 → unit 0, 1 → unit 1**; any other value: `io_Error = −1` (IOERR_OPENFAIL), open count unchanged.
  The test is on the low word only after the "not zero" long test (D0 `$00010001` would open unit 1) — edge only.
- Success: io_Unit = address of the unit structure, delayed-expunge flag cleared, `lib_OpenCnt + 1`.
- io_Flags of the open are ignored. **No exclusive access**: any number of openers per unit, including unit 0
  while input.device uses it.

### 1.5 CloseDevice / Expunge [S]

- Close: io_Unit and io_Device set to 0, `lib_OpenCnt − 1`; if it reaches 0 with the delayed-expunge flag set,
  Expunge. **Close aborts nothing, does not reset the controller type, the trigger or the pot bits.**
- Expunge: if still open, sets the delayed-expunge flag and returns 0. Otherwise removes the VERTB server, unlinks
  and frees the base, returns the segment list. The pot bits are **not** freed.
- Observed on the real ROM at the insert-disk screen: `lib_OpenCnt = 1` (input.device only). [O]

---

## 2. BeginIO / AbortIO and request queueing (code shared with keyboard.device and input.device) [S]

### 2.1 BeginIO

1. `io_Flags &= $0F` (bits 4-7 cleared, IOF_QUICK kept), `io_Error = 0`.
2. io_Command ≥ 14 → treated as command 0 (CMD_INVALID).
3. A per-command byte decides: `$FF` = **immediate** (routine called at once in the caller's context), otherwise
   the value selects which port of the unit receives the request (always 0 here). For gameport, **only
   `GPD_READEVENT` (9) is queued**; commands 0-8 and 10-13 are immediate.
4. Queued command: under `Disable`, `io_Flags &= ~$30`, `PutMsg(unit port, ioreq)`; if the request is now the head
   of the port list, io_Flags bit 5 ("active") is set, else bit 4 ("queued"). `Enable`.
5. If active **and** the unit is not stopped: the command routine is called at once, **IOF_QUICK kept** (a
   `DoIO` that can be satisfied immediately completes without ReplyMsg). Otherwise IOF_QUICK is cleared and BeginIO
   returns (the request waits in the port).

### 2.2 Termination ("reply") routine, common to all commands

Under `Disable`: io_Flags bit 7 ("done") is set; if it **was already set, nothing else happens** (a request is
terminated only once). Otherwise `io_Error = D0` (low byte); if bit 5 (active) the request is removed from the
port and the next request, if any, gets bit 5 (it is **marked**, not started); if bit 4, it is removed; then, if
IOF_QUICK is clear, `ReplyMsg`. `Enable`.

### 2.3 AbortIO

Calls the termination routine with **io_Error = −2 (IOERR_ABORTED)**: any request not yet terminated is removed
from its queue and replied, whatever its command and whatever its position in the queue. Already-terminated
requests are untouched. No hardware or unit state changes. The next request that becomes head is not served until
the next event is produced (§6) or a new BeginIO/CMD_START. The D0 value returned by AbortIO is not meaningful
(1.3 AbortIO has no documented result).

---

## 3. Commands [S]

| No. | Command | Immediate | Length check | io_Actual | io_Error | Effect |
|---:|---|:-:|---|---|---|---|
| 0 | `CMD_INVALID` | yes | — | — | **−3** (IOERR_NOCMD) | none |
| 1 | `CMD_RESET` | yes | — | — | undefined (see note) | `CMD_STOP`, then `CMD_FLUSH`, then `CMD_START` on the same request; the request is replied by the first step. Type, trigger, ring and pot bits are **not** reset. |
| 2 | `CMD_READ` | yes | — | — | **−3** | refused (same routine as CMD_INVALID) |
| 3 | `CMD_WRITE` | yes | — | — | **−3** | refused |
| 4 | `CMD_UPDATE` | yes | — | — | **−3** | refused |
| 5 | `CMD_CLEAR` | yes | — | — | 0 (cleared by BeginIO) | ring emptied (read index = write index = 0) under Disable. **The request is never replied** (see note). |
| 6 | `CMD_STOP` | yes | — | — | undefined | sets the unit "stopped" bit |
| 7 | `CMD_START` | yes | — | — | undefined | clears the bit; if the unit queue is not empty, the head request's command routine is run (serves a pending READEVENT from the ring) |
| 8 | `CMD_FLUSH` | yes | — | — | undefined | every request in the unit queue is aborted (−2), head included |
| 9 | `GPD_READEVENT` | **queued** | io_Length ≥ 22 else **−4** (IOERR_BADLENGTH) | 22 × n | 0 | §4 |
| 10 | `GPD_ASKCTYPE` | yes | low word of io_Length ≥ 1 else −4 | 1 | 0 | `io_Data[0]` = unit type byte |
| 11 | `GPD_SETCTYPE` | yes | ≥ 1 else −4 | 1 | **always 0** (see §5.1) | §5.1 |
| 12 | `GPD_ASKTRIGGER` | yes | ≥ 8 else −4 | 8 | 0 | copies the unit's 8-byte trigger to io_Data |
| 13 | `GPD_SETTRIGGER` | yes | ≥ 8 else −4 | 8 | 0 | copies 8 bytes from io_Data to the unit's trigger; takes effect at the next frame; nothing else is reset |

Notes:
- **"undefined" io_Error**: CMD_STOP, CMD_FLUSH, CMD_RESET and CMD_START reach the termination routine without
  loading D0, so io_Error receives the low byte of whatever D0 held (the caller's D0 for STOP/RESET/FLUSH, since
  exec `DoIO` does not touch D0; for START the value left by the head request's routine, or the caller's D0 when the
  queue is empty). An implementation should return 0; no software can rely on the 1.3 value. [S]
- **CMD_CLEAR is not replied**: with `DoIO` it works (IOF_QUICK still set, DoIO returns at once, io_Error 0); with
  `SendIO` + `WaitIO` the caller **hangs forever** on the real ROM. Replying it (error 0) is the safe choice; it does
  not break `DoIO` callers. [S]
- Length checks of 10-13 subtract on the **low word** of io_Length (io_Length `$10000` is "0"). Edge only.
- `CMD_STOP` does not stop the VERTB server from **completing** pending reads (§6, step 6): it only prevents
  BeginIO and CMD_START-less dispatch. A READEVENT sent while stopped waits even if the ring holds events, and is
  then served by the next produced event.

---

## 4. GPD_READEVENT [S]

### 4.1 Request

`io_Data` = buffer, `io_Length` = buffer size in bytes. Up to `floor(io_Length / 22)` events are written.

### 4.2 Serving algorithm (observable behaviour)

- A re-entrance guard (io_Flags bit 6) prevents the same request from being served twice concurrently.
- io_Length < 22 → terminated at once with −4; then the next queued request, if any, is served.
- **Ring empty** → io_Flags bits 0 (IOF_QUICK) and 6 cleared; the request stays at the head of the unit port
  (**pending**). It is completed later from the VERTB interrupt (`ReplyMsg` at interrupt level).
- **Ring not empty** → events are moved, oldest first, while the buffer has room and the ring is not empty
  (each move under Disable). The events are chained: each `ie_NextEvent` points to the next 22-byte slot of the
  buffer, the last one is **NULL**. `io_Actual = 22 × n`, io_Error 0, terminated (no ReplyMsg if IOF_QUICK is still
  set, i.e. a `DoIO` served at once). Then, if another request is queued on the unit, it is served the same way
  (it gets what remains, or becomes pending).
- A request is never completed with 0 events.

### 4.3 InputEvent produced (22 bytes, public layout)

| Offset | Field | Value |
|---|---|---|
| `$00` | ie_NextEvent | next event in the buffer or NULL |
| `$04` | ie_Class | **2** (IECLASS_RAWMOUSE) for every controller type |
| `$05` | ie_SubClass | **unit number** (0 or 1) |
| `$06` | ie_Code | `IECODE_LBUTTON $68`, `IECODE_RBUTTON $69`, `IECODE_MBUTTON $6A`, OR `$80` for a release (`IECODE_UP_PREFIX`), or **`$FF` IECODE_NOBUTTON** (movement / timeout event). Word, high byte 0. |
| `$08` | ie_Qualifier | high byte only, low byte 0: `$8000` IEQUALIFIER_RELATIVEMOUSE (mouse and relative joystick), `$4000` LEFTBUTTON, `$2000` RBUTTON, `$1000` MIDBUTTON — the **reported** button state after this event (a press event includes its own button, a release event no longer does) |
| `$0A` | ie_X | word: relative types = signed sum of the deltas since the previous event; absolute joystick = current position −1/0/+1 |
| `$0C` | ie_Y | word, same |
| `$0E` | ie_TimeStamp.tv_secs | high word = **number of frames since the previous event** of this unit; low word = the first two bytes of the next ring slot (meaningless) |
| `$12` | ie_TimeStamp.tv_micro | **not written** (whatever was in the buffer) |

Sign conventions: X positive = right, Y positive = down (mouse counters; joystick right/down = +1). [S]
input.device overwrites ie_TimeStamp with the system time, so only direct gameport readers ever see the frame
count. [S]

---

## 5. Controller types and trigger

### 5.1 GPD_SETCTYPE [S]

Type byte (signed) from `io_Data[0]`: `GPCT_ALLOCATED −1`, `GPCT_NOCONTROLLER 0`, `GPCT_MOUSE 1`,
`GPCT_RELJOYSTICK 2`, `GPCT_ABSJOYSTICK 3`. Under Disable:
1. Unit state cleared: reported buttons, frame counter, X/Y accumulators, absolute reference, mouse reference.
2. Type stored (any value; **no range check**: values outside −1..3 make the 1.3 device jump through garbage, i.e.
   crash — an implementation should reject them; no protection of `GPCT_ALLOCATED` either, anyone may set any type).
3. Flags: "skip next frame" and "relative" set; "relative" cleared again for type 3.
4. Pot bits: **all** bits the device holds are freed (`FreePotBits(granted)`), this unit's `$0F01 << 4·unit` are
   removed from the request and from the POTGO value, then:
   - type −1 or 0: re-allocate the remaining request (the other unit's bits) — this unit no longer drives POTGO;
   - types 1, 2, 3: `$0F00 << 4·unit` (OUTLY|DATLY|OUTLX|DATLX for unit 0, OUTRY|DATRY|OUTRX|DATRX for unit 1)
     added to the request **and** to the POTGO value, then `AllocPotBits(request)`; the result becomes the
     granted mask. For type 1 (mouse) the current JOYxDAT is also sampled as the delta reference.
5. If the unit's four bits were not all granted, the routine writes io_Error = 1 (GPDERR_SETCTYPE)… and then
   terminates the request with D0 = 0, which **overwrites it: io_Error is always 0** on 1.3. The unit keeps the
   type and simply has no (or partial) right/middle buttons. io_Actual = 1.

The START bit (POTGO bit 0) is never requested: no 1.3 controller type uses proportional inputs; POT0DAT/POT1DAT
and JOYTEST are never accessed (custom-chips-v34 §4.2).

### 5.2 Trigger (`GamePortTrigger`, 8 bytes at unit `+$66`) [S]

| Offset | Field | Meaning in 1.3 |
|---|---|---|
| 0 | gpt_Keys (UWORD) | bit 0 `GPTF_DOWNKEYS`: report button presses; bit 1 `GPTF_UPKEYS`: report releases. A transition not reported is still recorded silently (it shows in the qualifier of later events). |
| 2 | gpt_Timeout (UWORD) | frames: if non-zero, an event (code `$FF`) is forced when the frame counter reaches this value with nothing else reported. 0 = never. |
| 4 | gpt_XDelta (UWORD) | 0 = X never triggers; else trigger when \|X\| ≥ XDelta (§6) |
| 6 | gpt_YDelta (UWORD) | same for Y |

Defaults: `{0, 0, 0, 0}` for a fresh unit (nothing is ever reported). input.device sets unit 0 to **`{3, 0, 1, 1}`**
(down and up keys, no timeout, any movement) — observed on the live real ROM: unit 0 trigger `3,0,1,1`, type 1,
flags "relative"; unit 1 trigger all zero, type 0. [O]

---

## 6. Per-frame processing (VERTB server, pri 0) [S]

Order: unit 0, then unit 1, then `WritePotgo(POTGO value, granted mask)` — POTGO `$0F00` every frame with the
default configuration [O]. The server returns with Z set (the chain continues). For each unit:

1. If "skip next frame" is set: clear it and do nothing else this frame (the first frame after a SETCTYPE is
   ignored, it is not counted).
2. Frame counter + 1 (saturating at `$FFFF`).
3. Types other than 1-3: stop here.
4. **Read the controller** (unit 0 / unit 1):
   - buttons for every type: left = CIA-A PRA bit 6 / bit 7, right = POTGOR DATLY (bit 10) / DATRY (bit 14),
     middle = POTGOR DATLX (bit 8) / DATRX (bit 12), all active low;
   - mouse: X delta = (JOYxDAT low byte − previous low byte), Y delta = (high byte − previous high byte), 8-bit
     signed wrap-around arithmetic; the sample is kept as the new reference;
   - joysticks (types 2 and 3): from JOYxDAT bits 0, 1, 8, 9 with the public HRM formula: X = +1 if bit 1 (right),
     −1 if bit 9 (left); Y = +1 if bit 1 XOR bit 0 (down), −1 if bit 9 XOR bit 8 (up); opposite directions together
     give 0.
5. **Movement test**:
   - relative types (mouse, relative joystick): the frame's X and Y are **added** to the accumulators. Trigger if
     (XDelta ≠ 0 and \|accX\| ≥ XDelta) or (YDelta ≠ 0 and \|accY\| ≥ YDelta). A held relative joystick therefore
     adds ±1 per frame;
   - absolute joystick: the accumulators receive the current position (−1/0/+1). For each axis with a non-zero
     delta, trigger if \|current − last reported\| ≥ delta, and then (only for that axis) last reported := current.
6. **Ring full** (writing one more would reach the read index) → stop here for this unit: nothing is reset, the
   accumulators and the counter keep growing, and button transitions stay pending (they are reported when room
   comes back).
7. **Buttons** (state word bits 15 left, 14 right, 13 middle compared with the reported state):
   - presses: if DOWNKEYS, only the **highest-priority** newly pressed button (left > right > middle) is reported
     this frame (code `$68/$69/$6A`), its bit is set in the reported state, and step 7's release part is skipped;
     without DOWNKEYS all presses are recorded silently;
   - releases (only if no press was reported this frame): if UPKEYS, the highest-priority released button is
     reported (code | `$80`) and cleared from the reported state; without UPKEYS all releases are recorded silently.
   - So at most **one button transition per frame and per unit**; two buttons pressed in the same frame give two
     events in two consecutive frames.
8. **Timeout**: if nothing triggered and Timeout ≠ 0 and counter ≥ Timeout → event with code `$FF`.
9. If anything triggered: under Disable the event is written to the ring (code, qualifier from the reported state
   plus `$80` RELATIVEMOUSE for relative types, X, Y, frame counter), then counter and X/Y accumulators are cleared.
   **If the unit queue is not empty, the head request is served at once** (§4.2) — regardless of CMD_STOP.

Timing: mouse resolution is one frame (50 Hz PAL / 60 Hz NTSC); input.device's default trigger makes an event in
every frame where the mouse moved or a button changed, and none when idle.

---

## 7. Sharing with input.device (who owns the mouse port) [S, O]

- input.device's task opens **gameport unit = IND_SETMPORT value (default 0)**, sends `GPD_SETCTYPE` (type from
  IND_SETMTYPE, default 1) and `GPD_SETTRIGGER` (IND_SETMTRIG, default `{3,0,1,1}`) synchronously, then keeps
  **one `GPD_READEVENT` with io_Length 22 (exactly one event)** pending on its own reply port, re-sent after each
  reply. It does not check io_Error of the reply: an aborted read (someone's `CMD_FLUSH`/`CMD_RESET`/`AbortIO` on
  the shared unit) makes input.device pass the **previous event again** to its handlers. [S]
- On each reply input.device replaces ie_TimeStamp with the system time, merges the qualifier
  (`(event & $F000) | (current & $0FFF)`) and sends the event down the handler chain (intuiticks-repeat §1.4-1.5).
- Nothing reserves unit 0. The 1.3 convention for other programs is: `Forbid`, `GPD_ASKCTYPE`; if the type is
  `GPCT_NOCONTROLLER`, `GPD_SETCTYPE` your own type, `Permit`; use it; set `GPCT_NOCONTROLLER` back before closing.
  Unit 0 always reads `GPCT_MOUSE` (input.device), so polite programs use unit 1.
- A program that nevertheless queues READEVENTs on unit 0 shares the event stream: events go to whichever request
  is at the head; input.device's request and the program's alternate. A program that SETCTYPEs unit 0 changes the
  type for input.device too, and resets its trigger only if it also sends SETTRIGGER.
- After `IND_SETMPORT 1`, input.device closes unit 0 **without** setting it back to `GPCT_NOCONTROLLER`: unit 0
  keeps reporting `GPCT_MOUSE`, keeps its pot bits and fills its ring (7 events) that nobody reads.

---

## 8. Error codes summary

| io_Error | Where |
|---:|---|
| 0 | every successful command, CMD_CLEAR (not replied), GPD_SETCTYPE even when pot bits were refused |
| −1 IOERR_OPENFAIL | OpenDevice with a unit other than 0/1 |
| −2 IOERR_ABORTED | AbortIO, CMD_FLUSH / CMD_RESET on queued reads |
| −3 IOERR_NOCMD | commands 0, 2, 3, 4 and any io_Command ≥ 14 |
| −4 IOERR_BADLENGTH | READEVENT < 22, ASKCTYPE/SETCTYPE < 1, ASK/SETTRIGGER < 8 |
| 1 GPDERR_SETCTYPE | never seen by the caller on 1.3 (overwritten, §5.1) |
| garbage | CMD_STOP / CMD_FLUSH / CMD_RESET / CMD_START (D0 not loaded) — implement as 0 |

---

## 9. Test vectors

| Action (real 1.3) | Expected |
|---|---|
| live state after boot (insert-disk screen) [O] | gameport open count 1; unit 0 type 1, trigger 3/0/1/1; unit 1 type 0, trigger 0/0/0/0; pot request = granted = POTGO value = `$0F00` |
| OpenDevice unit 2 | io_Error −1 |
| ASKCTYPE unit 1, io_Length 1 | io_Data[0] = 0, io_Actual 1, error 0 |
| ASKCTYPE io_Length 0 | error −4 |
| SETCTYPE unit 1 = 3, SETTRIGGER {3,0,1,1}, push stick right, READEVENT 22 | class 2, subclass 1, code `$FF`, qual 0, X 1, Y 0; release → event X 0 |
| same with type 2 | qual `$8000`, X +1 each frame while held (one event per frame) |
| fire pressed / released (unit 1, keys 3) | code `$68` qual `$4000`, then code `$E8` qual 0 |
| SETTRIGGER {0,10,0,0}, nothing touched | one event code `$FF`, X Y 0, every 10 frames (frame count 10 in tv_secs high word) |
| READEVENT io_Length 66 with 2 events in the ring | io_Actual 44, first ie_NextEvent → buffer+22, second NULL |
| READEVENT io_Length 21 | error −4 |
| CMD_CLEAR via SendIO + WaitIO | never returns on 1.3 (implementation: reply 0) |
| AbortIO of a pending READEVENT | error −2, io_Actual unchanged |

---

## Open points

- The "undefined io_Error" values of STOP/FLUSH/RESET/START and the CMD_CLEAR hang are static deductions; a probe
  issuing those commands through `DoIO` with a known D0 (e.g. D0 = `$55` before the call) and via SendIO/WaitIO with
  a timeout would confirm them. Described only; not written.
- No black-box run of joystick reading or of the trigger semantics was made on the real ROM; §6 is from static
  reading. A probe that opens unit 1, sets each type and trigger of §9 and logs the events while Amiberry injects
  `joy:1,…` input would turn the table of §9 into observed vectors.

## Clean-room review

- [x] No instruction sequence, no pseudo-code transcription, no ROM address. Offsets are device-base/unit layout
  (ABI-level private structures) and public structure fields.
- [x] The joystick decoding is given as the public HRM formula, not as the ROM's lookup table; the button code
  mapping is given as the public IECODE constants.
