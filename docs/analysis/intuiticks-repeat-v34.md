# intuiticks-repeat-v34.md — keyboard repeat (input.device 34.1) and INTUITICKS (intuition 34.3)

> ANALYSIS track ("dirty"). Source: ROM `kick34005.A500` read under radare2 + black-box probe on the
> real ROM under FS-UAE (`tests/ticks.s`, vectors §6). We describe the **what** (values, public structures,
> order, conditions, timings); no instruction sequence transcribed, no routine address.
>
> Legend: **[R]** ROM analysis · **[S]** black-box probe · **[D]** public documentation · **[R+S]** concordant.
> Related specs (not contradicted, complemented): `intuition-prefs-v34.md` (KeyRpt → SETTHRESH/SETPERIOD),
> `timer-v34.md` (UNIT_VBLANK), `intuition-prop-v34.md` §4 (no repeat of the page jump),
> `workbench-task-v34.md` §8.3 (drawer scrolling by INTUITICKS).

---

## 1. input.device: time sources and internal state

### 1.1 Opens and requests **[R]**

At its init (COLDSTART resident pri 40), input.device opens **timer.device unit 1 = UNIT_VBLANK** and
keyboard.device unit 0, then creates its task (`"input.device"`, NT_TASK, **pri 20**, 4 KB stack). The task
opens gameport.device (unit = `IND_SETMPORT`, 0 by default), sends it `GPD_SETCTYPE` (1 = GPCT_MOUSE by
default) and `GPD_SETTRIGGER` (default `keys = 3` (DOWNKEYS|UPKEYS), `timeout = 1`, `xdelta = 1`, `ydelta = 1`).

Three independent timerequests on the same VBLANK open, plus one for `TR_GETSYSTIME`:

| Request | Command | Delay | Role |
|---|---|---|---|
| tick | TR_ADDREQUEST | **{0 s, 100,000 µs}** fixed | IECLASS_TIMER events (§1.3) |
| repeat | TR_ADDREQUEST | THRESH then PERIOD | keyboard repeat (§2) |
| clock | TR_GETSYSTIME (synchronous, DoIO) | — | timestamping of **every** event produced |

### 1.2 Default values (before any SetPrefs) **[R]**

| Field | input.device default | Command |
|---|---|---|
| repeat threshold (initial delay) | **{0 s, 800,000 µs}** | `IND_SETTHRESH` (12) |
| repeat period | **{0 s, 100,000 µs}** | `IND_SETPERIOD` (13) |
| mouse port | 0 | `IND_SETMPORT` (14), 1 byte |
| controller type | 1 (mouse) | `IND_SETMTYPE` (15), 1 byte |
| trigger | {3, 1, 1, 1} | `IND_SETMTRIG` (16), 8 bytes (io_Length < 8 ⇒ IOERR_BADLENGTH −4; io_Actual = 8) |

- `IND_SETTHRESH`/`IND_SETPERIOD`: copy the timerequest's `timeval` (`+$20` seconds, `+$24` µs)
  **immediately** ("quick" command, replied to at once). The new value is used for the **next**
  arming of the repeat timer (a wait already started keeps the old one). **[R]**
- `IND_SETMPORT/SETMTYPE/SETMTRIG` (io_Length < 1 ⇒ −4) flag the re-opening of gameport, done by the task
  on the next round. **[R]**
- intuition replaces these defaults at its init and at each `SetPrefs` with **KeyRptDelay → SETTHRESH** and
  **KeyRptSpeed → SETPERIOD** (`intuition-prefs-v34.md` §3.3 and §4.3: intuition ROM defaults 0.8 s / 0.1 s; WB 1.3
  `devs:system-configuration` file: **0.4 s / 31,140 µs**). **[R, cf. prefs spec]**
- Commands: 0 invalid, 1 CMD_RESET, 5 CMD_CLEAR, 6 CMD_STOP, 7 CMD_START, 8 CMD_FLUSH; READ/WRITE/UPDATE
  (2/3/4) refused; 9 `IND_ADDHANDLER`, 10 `IND_REMHANDLER`, 11 `IND_WRITEEVENT` **queued** for the
  task; 12..16 immediate. **[R]**

### 1.3 IECLASS_TIMER **[R; frequency S]**

- The "tick" request is re-armed at {0, 100,000} **after** the processing of each tick. In PAL UNIT_VBLANK
  (P = 20,000 µs, `timer-v34.md` §3) this gives **5 frames = 100 ms**, i.e. **10 events per second**
  (60 Hz: ⌈100,000/16,667⌉ = 6 frames ≈ 100 ms). No catching up if the task falls behind.
- Contents of the InputEvent (a **single** event, `ie_NextEvent = NULL`, structure reused at each tick):
  `ie_Class = 6` (IECLASS_TIMER), `ie_SubClass = 0`, `ie_Code = 0`, `ie_X = ie_Y = 0`,
  **`ie_TimeStamp` = system time (TR_GETSYSTIME) at the moment of the tick**. `ie_Qualifier` is **not** written by
  input.device (0 unless a handler modified it — the structure is reused). **[R]**
- Like all events, it is passed to the handler chain (§1.4).

### 1.4 Handler chain **[R; D]**

`IND_ADDHANDLER` does an Enqueue (by `ln_Pri`) of the `Interrupt` into the list; `IND_REMHANDLER` removes it.
Each event produced (tick, keyboard, mouse, repeat, WRITEEVENT) is sent **alone**: handler called
with **A0 = event(s), A1 = is_Data**, entry `is_Code`; the returned D0 is the list passed to the next
handler; **D0 = 0 stops the chain**. `IND_WRITEEVENT` sends the InputEvent pointed to by io_Data **forcing
`ie_NextEvent = NULL`** (a single event), **without** re-timestamping it or touching its qualifier.

### 1.5 Current qualifier **[R]**

input.device keeps a **current qualifier** (UWORD):
- **mouse** event (gameport): `qual = (event_qual & $F000) | (current & $0FFF)`; current := qual;
- **keyboard** event: `qual = (event_qual & $07FF) | (current & $F800)`; current := qual;
- **repeat** event: same rule as keyboard (bits $F800 = buttons/RELATIVEMOUSE refreshed);
  current := qual, which **contains `IEQUALIFIER_REPEAT` ($0200)** ⇒ the following mouse events also carry
  $0200 until the next keyboard event (faithful artefact).
- **timer** event: no update (and qualifier not written, §1.3).

---

## 2. Automatic key repeat (input.device) **[R; timings S]**

State: a single "repeat event" (copy of an InputEvent) + its code; code = $FFFF ⇒ no repeat.

### 2.1 Key pressed (keyboard.device, bit 7 of the code = 0)

1. Code **≥ $60** (Shift, Caps Lock, Ctrl, Alt, Amiga: $60..$67, and $68..$7F): **stops** the repeat in
   progress (AbortIO + WaitIO of the timer, code := $FFFF). These keys **never repeat**.
2. Code **< $60** (any other key, including numeric keypad, arrows, function keys, Esc, Del, Help…):
   - dead-key history: the event's `ie_EventAddress` (the 4 bytes `ie_X/ie_Y`) receives
     **{Prev1DownCode, Prev1DownQual, Prev2DownCode, Prev2DownQual}** = the two previous presses
     **of this type** (code < $60), then the history is shifted (this press becomes Prev1; only the low
     byte of the qualifier is kept);
   - if a repeat was in progress, its timer is cancelled (the **last** key pressed replaces
     the old one: only one key repeats at a time);
   - the event (class, subclass, code, qualifier, address, timestamp) is copied into the repeat
     event, with **`ie_Qualifier |= IEQUALIFIER_REPEAT ($0200)`**;
   - the repeat timer is armed with the **threshold** (THRESH);
   - the original event (without $0200) is sent to the handlers.

### 2.2 Key released (bit 7 = 1)

The repeat is **stopped** if:
- the released code (without bit 7) is that of the repeating key, **or**
- `(repeat_qual & $05FF) ≠ (current & $07FF)` — the current one having just been updated by this release.
  In practice: releasing a qualifier key (Shift, Alt, Ctrl, Amiga, Caps Lock) **held at the moment of
  the press** stops the repeat, and releasing a key whose NUMERICPAD bit ($0100) differs from that
  of the repeating key also stops it.
Otherwise (release of another ordinary key) the repeat continues. The release event is
then sent normally.

### 2.3 Timer expiry

If the repeat is still active: new timestamp (GETSYSTIME) in the repeat event, update
of its $F800 bits from the current one (§1.5), **sending to the handlers** (IECLASS_RAWKEY, same code, same
history bytes as the original press, `ie_Qualifier` with **$0200**), then re-arming with the
**period** (PERIOD). First repeated event at **THRESH**, the following ones every **PERIOD**, each delay
rounded up to the next VBLANK (UNIT_VBLANK: k = max(1, ⌈T/20,000 µs⌉) frames in PAL). PAL examples: defaults
0.8 s / 0.1 s ⇒ 40 then 5 frames; WB 1.3 0.4 s / 31,140 µs ⇒ **20 then 2 frames (25 repeats/s)**.

### 2.4 Several keys

- Only one key repeats: the last one pressed (code < $60). Releasing that last one stops everything, even if
  another repeatable key is still held (no resumption). **[R]**
- Pressing a qualifier during a repeat stops it (2.1-1); releasing it does not restart it. **[R+S]**
- Dead keys are not a special case in input.device (keymap handles them at conversion):
  a dead key (< $60) repeats like the others. **[R]**

---

## 3. intuition 34.3: INTUITICKS **[R; S]**

### 3.1 Emission

For each **IECLASS_TIMER** event received by intuition's handler (hence ≈ 10 per second):
1. intuition first retrieves the already replied messages (ReplyMsg) of the **active window**;
2. if there is an **active window** (`IntuitionBase->ActiveWindow`, +$34), intuition is not in an
   internal wait state (verification in progress, cf. §5), `IDCMPFlags & INTUITICKS ($00400000)`, and the
   **`WINDOWTICKED` ($04000000 in `Window->Flags`, +$18)** flag is 0: an INTUITICKS IntuiMessage is
   sent and `WINDOWTICKED` is set.
3. `WINDOWTICKED` is cleared when intuition retrieves **this** replied message (when processing a subsequent
   event, cf. point 1, or during another walk of the window's replied messages).

Consequences:
- **only the active window** receives INTUITICKS; an inactive window receives none;
- **at most one INTUITICKS in circulation per window**: as long as the application has not replied, no other
  is emitted (no accumulation); after the reply, the next one goes out at the following tick ⇒ max rate 10/s;
- the other classes are not limited.

### 3.2 Contents of the message

| Field (IntuiMessage) | Value |
|---|---|
| `Class` (+$14) | `$00400000` |
| `Code` (+$18) | 0 |
| `Qualifier` (+$1A) | `ie_Qualifier` of the timer event (0 in practice, §1.3) |
| `IAddress` (+$1C) | **the window itself** |
| `MouseX/MouseY` (+$20/+$22) | `Window->MouseX/MouseY` (relative to the window); with DELTAMOVE: `ie_X/ie_Y` of the event (0) |
| `Seconds/Micros` (+$24/+$28) | `IntuitionBase->Seconds/Micros` (timestamp of the last event processed, here the tick) |
| `IDCMPWindow` (+$2C) | the window |
| `mn_ReplyPort` | `Window->WindowPort`; `mn_Length` = **$20** (actual value of intuition 34.3, whatever the class) |

(The message is taken from the window's message pool — 56 bytes, MEMF_PUBLIC|MEMF_CLEAR, reused
when they have been replied — like all IntuiMessages.) **[R]**

---

## 4. Gadgets held down and scrolling **[R; S]**

- intuition 34.3 **repeats nothing** for a held gadget: a GADGIMMEDIATE boolean gadget sends **a single**
  GADGETDOWN on press, then GADGETUP (RELVERIFY) on release inside it; no repeated GADGETDOWN, no
  auto-repeat linked to IECLASS_TIMER. The page jump of a proportional gadget only happens once per
  click (`intuition-prop-v34.md` §4.2). **[R+S]**
- Repeating is **up to the application**, typically on INTUITICKS: this is what the
  Workbench 1.3 does (`workbench-task-v34.md` §8.3): on GADGETDOWN of an **arrow** without Shift, it **adds
  INTUITICKS to the IDCMP** of the drawer window and scrolls by one step (1/8 of the visible area) at each
  INTUITICKS (and at each MOUSEMOVE) as long as the gadget is held; on GADGETUP it removes INTUITICKS. The
  WB's continuous scrolling therefore runs at **≈ 10 steps per second**, with no initial delay other than the first tick.
- INTUITICKS keep arriving at the active window while a gadget is held (the §3.1 test does not
  depend on the gadgets' state). **[R+S]**

---

## 5. Points of detail

- The "internal wait" state that suspends processing (and hence INTUITICKS) corresponds to the moments when
  intuition waits for a verification reply (MENUVERIFY/SIZEVERIFY/REQVERIFY); not probed. **[R]**
- `VANILLAKEY` (not directly related, noticed in passing): if the window has VANILLAKEY, a press converted
  to **exactly one** character goes out as VANILLAKEY; otherwise as RAWKEY (if requested); **releases are
  swallowed** (no message) when VANILLAKEY is set. For RAWKEY, `IAddress` points to a copy (in the
  message) of the 4 dead-key history bytes (§2.1). **[R]**

---

## 6. Test vectors (real ROM 34.5, FS-UAE 3.2.35, WB 1.3.3)

Probe `tests/ticks.s` (window 640×160 BORDERLESS|ACTIVATE|RMBTRAP at (0,0) on the WB screen, covered by
a GADGIMMEDIATE|RELVERIFY boolean gadget; reply to each message within ≤ 20 ms; `slow_memory = 512`).
Active prefs = `devs:system-configuration` of WB 1.3.3 (KeyRptDelay 0.4 s, KeyRptSpeed 31,140 µs).
Injection: XTEST (`xdotool keydown/keyup`, `mousedown/up`) via the FS-UAE harness.
Format: `class code qual secs(low 16 bits) micros mouseX mouseY iaddr` — class `T`=INTUITICKS,
`K`=RAWKEY, `D`/`U`=GADGETDOWN/UP, `A`=ACTIVEWINDOW; iaddr `=` = the window.

```
W 00C07A00                                    window
A 0000 0000 AC4F 00000056 0000 0000 =        ACTIVEWINDOW, same timestamp as the 1st tick
T 0000 0000 AC4F 00000056 0000 0000 =        INTUITICKS: Code 0, Qual 0, IAddress = window
T 0000 0000 AC4F 0004E258 0000 0000 =
T 0000 0000 AC4F 000668F9 0000 0000 =        +100,001 µs
T 0000 0000 AC4F 0007EF9A 0000 0000 =        +100,001 µs …
--- key "a" ($20) held ~2.5 s
K 0020 0000 AC52 000BE75E 0000 0000 00C07B5C press (no $0200)
K 0020 0200 AC53 0002BFA4 0000 0000 00C07B5C 1st repeat: +0.400 s, qualifier $0200
K 0020 0200 AC53 00035BE6 0000 0000 00C07B24 +40,002 µs (2 frames: 31,140 µs rounded up to the VBLANK)
K 0020 0200 AC53 0003F827 0000 0000 00C07B5C +40,001 µs … (≈ 25 repeats/s)
K 00A0 0000 AC55 00044690 0000 0000 00C07B5C release: end
--- "a" held, then Shift_L pressed during the repeat
K 0020 0000 AC56 000B99A1 …                   press; $0200 repeats from AC57.271E7 (+0.4 s)
K 0020 0200 AC58 000B99E0 … 
K 0060 0001 AC58 000B99E1 0000 0000 00C07B24 Shift ($60, qual LSHIFT): NO repeat afterwards
K 00E0 0000 AC5A 0003AAB3 …                   Shift release: no resumption
K 00A0 0000 AC5B 000AFDC4 …                   release of "a"
--- Shift_L alone held 1.5 s
K 0060 0001 AC5D 00030E95 …                   a single event (qualifiers do not repeat)
K 00E0 0000 AC5F 00030EAC …
--- left button held ~2.5 s on the gadget
D 0000 C000 AC60 000AAFDD 0000 0000 00C07E06 a single GADGETDOWN (qual LEFTBUTTON|RELATIVEMOUSE)
   (20 INTUITICKS between AC61 and AC62: the ticks continue during the press)
U 0000 8000 AC63 0002C0BA 0000 0000 00C07E06 GADGETUP on release
--- end of recording, then 2 s WITHOUT reading the port
#
T 0000 0000 AC70 0007F175 0000 0078 =        ONE SINGLE INTUITICKS pending after 2 s
```

Statistics over 335 INTUITICKS (≈ 33 s): interval 100 ms in 263 cases; 80/120 ms (pairs, 40 cases);
a few 140–200 ms (tick skipped when the reply arrives after the next tick). `Qualifier` always 0, even with
key or button held; `MouseX/MouseY` = position of the pointer relative to the window (Y going from 0 to
$78 after moving the mouse), hence the current position, not that of the timer event.

---

## 7. Not probed / uncertain

- **Inactive window**: the probe did not manage to deactivate its window (the click fell back into the
  gadget); "only the active window receives INTUITICKS" is established by the ROM only. **[R]**
- The 80/120 ms jitter of the tick timestamps (a pair at 80 then 120 ms) is not explained: it comes from
  the timestamping (GETSYSTIME) or from the moment of re-arming, the average remaining 100 ms.
- 60 Hz (NTSC): not probed (6 frames expected for a tick, ⌈T/16,667⌉ for the repeat).
- input.device defaults (0.8 s / 0.1 s) and intuition ROM defaults: not probed here (the probe runs with the
  WB prefs file); values read in ROM.
- Stop rule by qualifier difference on release of another key (masks $05FF/$07FF), numeric keypad
  case, propagation of the REPEAT bit into mouse events: ROM only.
- `WRITEEVENT`, handler chain and verification wait state suspending INTUITICKS: ROM
  only.
- VANILLAKEY: ROM only.

---

## Clean-room review

- [x] No instruction sequence transcribed or paraphrased; no ROM routine address (only
  offsets of public/private structures, ABI constants and hardware ranges).
- [x] The probes cited are author code (`tests/`, header "ASSET DE TEST, PAS du code ROM").
