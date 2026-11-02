# keyboard-input-devices-v34.md — keyboard.device and input.device commands (Kickstart 1.3)

> ANALYSIS track ("dirty"). Source: ROM `assets/kick34005.A500`, static reading of keyboard.device 34.1 and
> input.device 34.1 (their command routines and the BeginIO/AbortIO/termination code shared with gameport.device),
> plus one live check of input.device's mouse settings on the real ROM under Amiberry. No ROM addresses, no
> instruction listings.
>
> **Legend**: **[S]** static reading · **[O]** observed on the running real ROM · **[D]** deduced.
> Complements, without repeating: [keyboard-handshake-v34.md](keyboard-handshake-v34.md) (byte reception, ring
> insertion, reset handlers), [intuiticks-repeat-v34.md](intuiticks-repeat-v34.md) §1-2 (input.device task, timer,
> repeat, handler chain, qualifier merge), [gameport-device-v34.md](gameport-device-v34.md) (the shared BeginIO,
> queueing, termination and AbortIO rules are in its §2; they apply word for word to both devices here).

---

## 1. Shared mechanics (summary of gameport-device-v34 §2) [S]

- BeginIO: `io_Flags &= $0F`, `io_Error = 0`, io_Command ≥ number of commands → CMD_INVALID. A per-command byte
  says "immediate" (routine runs in the caller's context, IOF_QUICK kept) or "queued" (PutMsg to the unit port;
  run at once only if it became head and the unit is not stopped).
- Termination: done-bit guard (a request is terminated once), `io_Error = D0`, removed from the queue, ReplyMsg
  unless IOF_QUICK.
- **AbortIO**: terminates any not-yet-terminated request with **−2**, wherever it is in the queue.
- Unit "stopped" flag = bit 0 of the unit MsgPort's ln_Pri byte (`unit + $09`).
- **"undefined" io_Error**: the common CMD_STOP and CMD_FLUSH routines (and CMD_RESET, which replies through
  CMD_STOP; and the common CMD_START) terminate the request without loading D0: io_Error = low byte of whatever D0
  held (exec `DoIO` does not set D0). Implement as 0.

---

## 2. keyboard.device 34.1

### 2.1 Open / Close / Expunge [S]

- Single unit: the unit number and flags are **ignored**, OpenDevice always succeeds; io_Unit = the unit MsgPort
  at device base `+$34`. No exclusive access.
- Close: io_Unit = io_Device = 0, open count − 1 (delayed expunge if flagged). Expunge while open = delayed; never
  happens in practice (input.device keeps it open).

### 2.2 Private layout used below [S]

| Offset (device base) | Contents |
|---|---|
| `$34` | unit MsgPort (queue of KBD_READEVENT) |
| `$56` | ciaa.resource base |
| `$5A` | `Interrupt` given to AddICRVector(SP) |
| `$70` / `$72` | ring read / write index (byte offsets, step 4, mask `$7F`) |
| `$74` | ring: **32 entries of 4 bytes** = code word, qualifier word (holds at most 31) |
| `$F4` | reset-handler list (`KBD_ADDRESETHANDLER`) |
| `$102` | reset handlers still running (counter) |
| `$104` | `$78` warning flags |
| `$105` | current qualifier low byte (matrix row of codes `$60`-`$67`) |
| `$106` | key matrix, 13 bytes (codes `$00`-`$67`) |

### 2.3 Commands (14) [S]

| No. | Command | Immediate | io_Error | Effect |
|---:|---|:-:|---|---|
| 0 | `CMD_INVALID` | yes | **−3** | none |
| 1 | `CMD_RESET` | yes | undefined | in order: CMD_STOP (the request is replied here); **CIA-A CRA := `$00`, `$00`, `$40`** (start of a handshake pulse, KDAT low); CMD_FLUSH; **CRA := `$00`** (end of pulse); CMD_START. The ring, the matrix and the qualifier are **not** cleared. The pulse lasts as long as the flush. |
| 2 | `CMD_READ` | yes | **−3** | refused — there is **no CMD_READ** on keyboard.device; reading is `KBD_READEVENT` only |
| 3 | `CMD_WRITE` | yes | **−3** | refused |
| 4 | `CMD_UPDATE` | yes | **−3** | refused |
| 5 | `CMD_CLEAR` | yes | **0** | ring emptied (both indexes 0) under Disable; replied normally |
| 6 | `CMD_STOP` | yes | undefined | unit stopped: bytes keep being received, handshaken and stored in the ring, but the interrupt no longer serves pending reads and BeginIO no longer starts new ones |
| 7 | `CMD_START` | yes | undefined | clears the flag; if a read is queued, the head is served from the ring at once |
| 8 | `CMD_FLUSH` | yes | undefined | every queued KBD_READEVENT aborted (−2) |
| 9 | `KBD_READEVENT` | **queued** | 0 / −4 | §2.4 |
| 10 | `KBD_READMATRIX` | yes | 0 / −4 | io_Length must be **exactly 13** (any other value, larger included → −4); copies the 13-byte matrix to io_Data, io_Actual = 13. Bit *n* of byte *k* = key `8k + n` down. Codes above `$67` are never in the matrix. |
| 11 | `KBD_ADDRESETHANDLER` | yes | 0 | `Enqueue` (by ln_Pri) of the `Interrupt` pointed to by io_Data into the reset-handler list |
| 12 | `KBD_REMRESETHANDLER` | yes | 0 | `Remove` of the `Interrupt` pointed to by io_Data (no check that it is in the list) |
| 13 | `KBD_RESETHANDLERDONE` | yes | 0 | handler counter − 1, **unconditionally**; when it reaches 0, CRA bit 6 cleared (end of the reset handshake, keyboard-handshake §5). A spurious call outside a reset makes the counter negative. |

io_Actual is only written by KBD_READEVENT and KBD_READMATRIX. No command checks io_Length except those two.

### 2.4 KBD_READEVENT [S]

Same serving rules as GPD_READEVENT (gameport-device-v34 §4.2): io_Length < 22 → −4 (then the next queued read is
served); ring empty → pending (IOF_QUICK cleared), completed later from the keyboard interrupt (unless stopped);
otherwise as many events as fit and are available, chained by ie_NextEvent, last NULL, io_Actual = 22 × n, io_Error
0; then the next queued read is served. Event contents:

| Field | Value |
|---|---|
| ie_Class | **1** (IECLASS_RAWKEY) |
| ie_SubClass | 0 |
| ie_Code | raw key code word: bits 0-6 key, bit 7 = release (`$80` IECODE_UP_PREFIX); also the keyboard's special codes (`$78` first reset warning, `$F9`…`$FE`) and the overflow marker `$7D` below |
| ie_Qualifier | low byte = qualifier keys held (`$60` LSHIFT bit 0 … `$67` RAMIGA bit 7, i.e. IEQUALIFIER_LSHIFT…RCOMMAND; Caps Lock follows the keyboard's own down/up = LED state), plus `$0100` IEQUALIFIER_NUMERICPAD for the keypad keys `$0F`, `$1D`-`$1F`, `$2D`-`$2F`, `$3C`-`$3F`, `$43`, `$4A`. The state includes the key of the event itself (Shift press carries its own bit). High byte otherwise 0. |
| ie_X, ie_Y (ie_EventAddress) | 0 |
| ie_TimeStamp | only the **high word of tv_secs** is cleared; the rest is whatever was in the buffer |

Ring overflow: when the ring is full the newest stored entry is **replaced** by code `$007D` with the current
qualifier (the byte that did not fit is lost, the one before it is lost too). keyboard-handshake §3 step 6.

There is no KBD_READEVENT/CMD_READ duality: command 9 is the only read; command 2 is refused with −3.

---

## 3. input.device 34.1

### 3.1 Open / Close / Expunge [S]

- Unit number and flags ignored, always succeeds; io_Unit = the MsgPort at device base `+$34`, whose SigTask is the
  input.device task (pri 20) — so PutMsg of a queued command wakes the task.
- **Expunge never expunges** (always sets the delayed-expunge flag and returns 0).

### 3.2 Private fields used below [S, O]

| Offset | Contents |
|---|---|
| `$3D` | unit port ln_Pri used as flags: bit 0 = stopped, bit 1 = **"gameport must be re-opened"** (preset to 1 at init, so the task opens gameport on its first round) |
| `$1228` | mouse port (byte), default 0 |
| `$1229` | mouse controller type (byte), default 1 |
| `$122A` | mouse trigger, 8 bytes, default **`{keys 3, timeout 0, xdelta 1, ydelta 1}`** |

Observed on the live real ROM at the insert-disk screen: port 0, type 1, trigger 3/0/1/1, flags byte 0. [O]
No ROM component (intuition, Preferences support) ever sends IND_SETMPORT/SETMTYPE/SETMTRIG. [S]

### 3.3 Commands (17) [S]

| No. | Command | Immediate | io_Error | Effect |
|---:|---|:-:|---|---|
| 0 | `CMD_INVALID` | yes | **−3** | none |
| 1 | `CMD_RESET` | yes | undefined | CMD_STOP (replied here), CMD_FLUSH, then input's CMD_START (no second reply). Thresholds, period, handlers and mouse settings are **not** reset. |
| 2 | `CMD_READ` | yes | **−3** | refused |
| 3 | `CMD_WRITE` | yes | **−3** | refused (events are injected with IND_WRITEEVENT) |
| 4 | `CMD_UPDATE` | yes | **−3** | refused |
| 5 | `CMD_CLEAR` | yes | 0 | **does nothing and is never replied**: fine with DoIO (IOF_QUICK still set), **hangs** a SendIO + WaitIO caller. Implement: reply 0. |
| 6 | `CMD_STOP` | yes | undefined | stopped: the task waits only on its command port, so keyboard, gameport and timer replies are left unprocessed (events stay buffered in keyboard.device's and gameport.device's rings; the 100 ms tick stops). Signals that arrive meanwhile are re-posted, not lost. Queued commands 9-11 are **still processed** by the task (see note). |
| 7 | `CMD_START` | yes | **0** | clears the flag; if it was set, `Signal(task, port signal)` to wake the task; replied 0 (input's own routine, not the common one) |
| 8 | `CMD_FLUSH` | yes | undefined | every request still queued on input's port (commands 9-11 not yet taken by the task) aborted with −2 |
| 9 | `IND_ADDHANDLER` | **queued** | 0 | the task Enqueues the `Interrupt` (io_Data) by ln_Pri into the handler chain, then replies |
| 10 | `IND_REMHANDLER` | **queued** | 0 | the task Removes it, then replies |
| 11 | `IND_WRITEEVENT` | **queued** | 0 | the task sends the InputEvent at io_Data down the chain with ie_NextEvent forced to NULL (intuiticks-repeat §1.4), then replies |
| 12 | `IND_SETTHRESH` | yes | 0 | timerequest tv_secs/tv_micro copied (no length check); used at the next arming |
| 13 | `IND_SETPERIOD` | yes | 0 | same for the period |
| 14 | `IND_SETMPORT` | yes | 0 / −4 | low word of io_Length < 1 → −4 (replied). Else `io_Data[0]` → mouse port, flag bit 1 set, **no reply, io_Actual not written** (see §3.4) |
| 15 | `IND_SETMTYPE` | yes | 0 / −4 | same, `io_Data[0]` → controller type |
| 16 | `IND_SETMTRIG` | yes | 0 / −4 | io_Length < 8 → −4. Else 8 bytes from io_Data → trigger, flag bit 1 set, io_Actual = 8, **replied** 0 |

Notes:
- Commands 9-11 while stopped: BeginIO does not start them, but PutMsg signals the task and the task dispatches the
  head of its port without testing the stop flag, so they complete anyway. [S]
- io_Command ≥ 17 → CMD_INVALID (−3).

### 3.4 IND_SETMPORT / SETMTYPE / SETMTRIG and gameport [S]

- The three commands only store the value and set the "re-open gameport" flag. **The task is not signalled**: the
  change takes effect at the task's next wake-up — at most one tick (100 ms) later while the tick runs, or at the
  next key / mouse event.
- SETMPORT and SETMTYPE are **not replied**: correct with `DoIO` (returns at once, io_Error 0), a SendIO caller never
  gets them back. Implementation: reply 0, io_Actual = 1 (harmless for DoIO callers).
- Values are not checked: port other than 0/1 makes the gameport OpenDevice fail (no mouse at all afterwards, until
  a valid SETMPORT); a type outside −1..3 crashes the 1.3 gameport (gameport-device-v34 §5.1); type 0 = no mouse
  events.
- **Re-open sequence** done by the task when it sees the flag (always the full sequence, even if only the trigger
  changed):
  1. while the flag is set, a gameport reply that arrives is ignored and not re-sent;
  2. if gameport is open: `AbortIO` of the pending READEVENT, `WaitIO`, `CloseDevice` (the old unit keeps its type,
     trigger and pot bits — it is not set back to GPCT_NOCONTROLLER);
  3. flag cleared; `OpenDevice("gameport.device", port)`; on failure: no mouse, stop;
  4. `GPD_SETCTYPE` (length 1, io_Data = type byte) and `GPD_SETTRIGGER` (length 8, io_Data = trigger), each sent
     with IOF_QUICK through BeginIO then WaitIO (errors not checked);
  5. `GPD_READEVENT` of **io_Length 22** (one event) into the task's mouse event buffer.
- Each mouse event received: ie_TimeStamp := TR_GETSYSTIME, qualifier merge (`(event & $F000) | (current & $0FFF)`,
  intuiticks-repeat §1.5), handler chain, READEVENT re-sent. io_Error of the reply is **not** checked: an aborted
  read (−2, e.g. a program flushing the shared gameport unit) replays the previous mouse event once. The same holds
  for keyboard.device: a `CMD_FLUSH` or `CMD_RESET` sent to keyboard.device by a program aborts input.device's
  KBD_READEVENT, and input.device processes its previous key event again (which can also restart key repeat). [S, D]
- input.device reads keyboard.device the same way: one pending `KBD_READEVENT` of io_Length 22 (one event per
  request).

---

## 4. What an implementation needs (summary)

- keyboard.device: commands 0-13 with the io_Error column above; READMATRIX length exactly 13; CMD_RESET emits the
  CRA handshake pulse and flushes but keeps the ring; CMD_READ = −3.
- input.device: commands 0-16; 9-11 through the task; 14-15 store + flag (reply 0 is the safe choice); 16 store +
  flag + io_Actual 8 + reply; the task performs the re-open sequence of §3.4 and keeps one 22-byte READEVENT
  pending on gameport and one on keyboard.device.
- Deterministic 0 instead of the 1.3 "undefined" io_Error of STOP/FLUSH/RESET (and keyboard START); a reply instead
  of the 1.3 silence for CMD_CLEAR (input) and IND_SETMPORT/SETMTYPE.

## 5. Test vectors (static unless marked)

| Action | Expected on 1.3 |
|---|---|
| keyboard `CMD_READ` | io_Error −3 |
| keyboard `KBD_READMATRIX` io_Length 16 | −4; io_Length 13 → io_Actual 13, error 0 |
| keyboard `KBD_READEVENT` io_Length 44 with 3 keys buffered | io_Actual 44, two events chained, the third stays for the next read |
| press keypad 7 (`$3D`) with left Shift held | code `$3D`, qualifier `$0101` |
| input `IND_SETMTRIG` io_Length 8 | io_Actual 8, error 0, mouse re-opened within ~100 ms |
| input `IND_SETMPORT` via DoIO, data 1 | DoIO returns at once, error 0; mouse now read from port 2 connector (unit 1); unit 0 still reports GPCT_MOUSE |
| input `CMD_CLEAR` via DoIO | returns, error 0; via SendIO/WaitIO: never returns |
| live mouse settings [O] | port 0, type 1, trigger 3/0/1/1 |

## Open points

- "Undefined" io_Error values and the two never-replied commands are static deductions; a probe calling them with a
  known D0 through DoIO, and through SendIO with a timeout + AbortIO, would confirm them (described only).
- The replay of the previous event after an aborted keyboard/gameport read is deduced from the task code (no error
  test); not observed.

## Clean-room review

- [x] No instruction sequence, no pseudo-code transcription, no ROM address. Offsets are device-base private layout
  and public structure fields; the numeric-pad key set is given as the list of public raw key codes.
