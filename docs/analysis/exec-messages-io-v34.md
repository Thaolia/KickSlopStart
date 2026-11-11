# exec.library 34.2 — messages, ports, I/O, opening libraries and devices: behavioural spec

> **ANALYSIS** track ("dirty"), `coverage-v34.md` §7 rank 12. Source: **black-box calls on the real ROM**
> `assets/kick34005.A500` under Amiberry (A500 preset, cycle-exact, 512 KB chip + 512 KB slow, no disk), 2026-11-05.
> Method: the ROM was left at its "insert disk" picture (no dos, no ramlib: the exec vectors are the ROM ones, see
> `ramlib-v34.md` §1.1). For each run the machine was reset, the debugger stopped the `input.device` task at the
> entry of exec `Wait` (user mode, interrupts enabled, IDNestCnt = TDNestCnt = −1), allocated a work block with an
> injected `AllocMem` call and then called the exec vectors through the library base (`ExecBase − LVO`) from that
> task, with a return trampoline, and finally resumed the task's own `Wait`. Every structure (ports, messages,
> IORequests, `Interrupt` nodes) was built by the debugger in that block. The "device" and "library" under test were
> fake ones built in RAM: a jump table whose vectors lead to a two-NOP-and-return stub on which a debugger breakpoint
> read the registers and, per test, set D0, `io_Error`, `io_Flags` or other registers; two stand-ins of six
> instructions each made a device "reply from inside BeginIO" (clear IOF_QUICK or not, then call exec `ReplyMsg`
> through `AbsExecBase`). Real asynchronous completion used the ROM's `timer.device` (UNIT_VBLANK, TR_ADDREQUEST).
> Forbid/Disable use was measured with a data watchpoint on the IDNestCnt/TDNestCnt word, logging every value
> written during the call. The ROM code was **not** read, disassembled or traced for this page. No program was
> written; the probe to write on the implementation side is described in §9.
> This document describes **behaviours**, **values**, **register contracts** and **test vectors**. It contains no
> ROM instruction sequence, no pseudo-code of a routine and no ROM address.
> Related pages: `exec-spec.md` (ExecBase layout, list primitives), `exec-scheduling-v34.md` (`Signal`, `Wait`,
> `Cause`, softint contract, Procure/Vacate on a `PA_IGNORE` port), `ramlib-v34.md` (the 1.3 disk-loading layer
> patched over `OpenLibrary`/`OpenDevice`/`CloseLibrary`/`CloseDevice`/`RemLibrary`/`RemDevice`), the device pages
> (`timer-v34.md`, `gameport-v34.md`, `console-keymap-v34.md` §2.4, `audio-device-v34.md`) for the device halves.
>
> **Levels of proof**: **[O]** observed on the real ROM · **[D]** deduced from observations (reasoning, stated) ·
> **[P]** public documentation (AutoDocs, RKRM, `exec/*.i`) · **[S]** assumption, not verified.
>
> Offsets are the public ones (`exec/nodes.i`, `exec/ports.i`, `exec/io.i`, `exec/libraries.i`): `ln_Type` +8,
> `ln_Pri` +9, `ln_Name` +10; MsgPort `mp_Flags` +14, `mp_SigBit` +15, `mp_SigTask` +16, `mp_MsgList` +20;
> Message `mn_ReplyPort` +14, `mn_Length` +18; IORequest `io_Device` +20, `io_Unit` +24, `io_Command` +28,
> `io_Flags` +30, `io_Error` +31; Library `lib_Flags` +14, `lib_NegSize` +16, `lib_Version` +20, `lib_Sum` +28,
> `lib_OpenCnt` +32. Node types: NT_INTERRUPT 2, NT_MSGPORT 4, NT_MESSAGE 5, NT_FREEMSG 6, NT_REPLYMSG 7,
> NT_SOFTINT 11. Test ids (P1, IO3, …) refer to §8.

## 0. Summary for the implementer

- **PutMsg** (−366, A0 port, A1 message): under **Disable**, `ln_Type := NT_MESSAGE`, message appended at the
  **tail** of `mp_MsgList`, then the port action. **The action is `mp_Flags AND 3`** (bits 2–7 ignored):
  0 = `Signal(mp_SigTask, 1 << mp_SigBit)` (bit number taken **modulo 32**), 1 = `Cause(mp_SigTask)`, 2 = nothing,
  **3 = JSR to the address in `mp_SigTask`** (undocumented; A0 = that address, A1 = port, A6 = ExecBase, caller's
  mode, still under Disable; what it leaves in D0/D1/A0/A1 is what PutMsg returns). **A NULL `mp_SigTask` means
  "queue only", for every action.** [O]
- **GetMsg** (−372, A0 port): under Disable, unlinks and returns the first message (D0, 0 if empty). `ln_Type` and
  the message's own `ln_Succ`/`ln_Pred` are left as they were. [O]
- **ReplyMsg** (−378, A1 message): `mn_ReplyPort` ≠ 0 → exactly PutMsg to that port but with `ln_Type :=
  NT_REPLYMSG`. `mn_ReplyPort` = 0 → `ln_Type := NT_FREEMSG`, nothing else (no Disable, no list), D0 = 0. The
  previous `ln_Type` is not checked (a message replied twice is queued twice). [O]
- **WaitPort** (−384, A0 port): if the list is not empty, returns the first message at once in D0 **and A1**, without
  removing it and **without touching the signal bit** (a set bit stays set). If empty: `Wait(1 << mp_SigBit)`,
  retest, repeat; a spurious signal costs one extra `Wait`. [O]
- **AddPort** (−354, A1): under **Forbid**, **re-initialises `mp_MsgList` (NewList)** and `Enqueue`s the port on
  `PortList` (priority order, FIFO among equals). It does **not** set `ln_Type`. **RemPort** (−360): Forbid +
  Remove, nothing else. **FindPort** (−390, A1 name): no Forbid/Disable of its own, D0 = port or 0. [O]
- **DoIO** (−456, A1 IORequest): `io_Flags := IOF_QUICK` (the **whole byte** is replaced by 1), `ln_Type` untouched,
  calls the device's **BeginIO** (A1 = request, A6 = `io_Device`) with no Forbid/Disable; then, if IOF_QUICK is
  still set, returns at once; otherwise it does what WaitIO does. D0 = `io_Error` **sign-extended** to 32 bits. DoIO
  restores A1 and A6; every other register comes back as BeginIO left it. [O]
- **SendIO** (−462): `io_Flags := 0` (whole byte), calls BeginIO, returns; no result (D0 is not set by exec). Only
  A6 is restored. [O]
- **WaitIO** (−474): IOF_QUICK set → returns `io_Error` (sign-extended) at once, **nothing else is touched** (not even
  a copy of the request that sits in a port). Otherwise: while `ln_Type` ≠ NT_REPLYMSG, `Wait(1 << mp_SigBit of
  mn_ReplyPort)`; then **`Remove` the request under Disable, unconditionally** (it trusts `ln_Succ`/`ln_Pred`, even if
  the request was already taken with GetMsg), and return `io_Error`. A signal bit that is already set when the request
  is already replied is **left set**. [O]
- **CheckIO** (−468): D0 = the request if `io_Flags` bit 0 (IOF_QUICK) is set **or** `ln_Type` = NT_REPLYMSG,
  otherwise 0. Nothing else read or changed. [O]
- **AbortIO** (−480): calls the device's AbortIO vector (−36) with A1 = request, A6 = `io_Device`, no check, no
  Forbid/Disable; **D0 is whatever the device returns** (exec adds nothing). [O]
- **OpenDevice** (−444, A0 name, D0 unit, A1 request, D1 flags): under **Forbid**, `FindName(DeviceList)` (first
  match only). Not found: `io_Device := 0`, `io_Error := −1` (IOERR_OPENFAIL), D0 = −1, nothing else touched. Found:
  `io_Device := device`, **`io_Unit := 0`**, `io_Error := 0`, then the device's Open (A6 = device, A1 = request,
  D0 = unit, D1 = flags, A0 = device), still under Forbid; D0 on return = `io_Error` sign-extended (the device's D0 is
  ignored). **A failed device Open leaves `io_Device` set.** `io_Flags` is not set from D1. [O]
- **CloseDevice** (−450, A1): Forbid, device's Close (A6 = `io_Device`, A1 = request), Permit; D0 = the Close
  vector's D0 (the seglist for ramlib, `ramlib-v34.md` §2.2). `io_Device`/`io_Unit` are **not** cleared. [O]
- **OpenLibrary** (−552, A1 name, D0 version): under **Forbid**, walks `LibList` for nodes with that name; the first
  one whose **`lib_Version`, compared as a signed 16-bit word, is ≥ the low word of D0 (signed)** is opened by
  calling its Open vector (A6 = base, **D0 = base, not the version**, A0 = base, A1 = D1 = name) under Forbid; the
  result in D0 is **the Open vector's D0 as is**. A too-low version **continues the walk** to later nodes of the same
  name; an Open that returns 0 does not. None found → 0. **OldOpenLibrary** (−408) = version 0 (D0 ignored). [O]
- **CloseLibrary** (−414, A1): Forbid, Close vector (A6 = A1 = base), result passed through. **No NULL test**:
  CloseLibrary(NULL) crashes (illegal instruction, Guru `00000004`). **RemLibrary**/**RemDevice** (−402/−438):
  Forbid, Expunge vector (A6 = A1 = D0 = base), result passed through; exec does **not** unlink the node itself. [O]
- **AddLibrary**/**AddDevice** (−396/−432): Forbid, `Enqueue` on LibList/DeviceList; `ln_Type` **not** set; if
  `LIBF_SUMUSED` is set they do what **SumLibrary** does: with `LIBF_CHANGED` the sum is recomputed and CHANGED
  cleared, without it the sum is **verified and a mismatch is the dead-end alert `$81000003`**. The V34 sum is the
  **16-bit sum of the `lib_NegSize` bytes of the jump table, stored in the upper word of `lib_Sum`** (lower word
  untouched). [O]
- **OpenResource** (−498, A1 name): Forbid, FindName on ResourceList, D0 = node or 0; **D0 on entry (version) is
  ignored**, no open count. **AddResource** (−486): Forbid + Enqueue, `ln_Type` not set. **RemResource** (−492):
  Forbid + Remove. [O]
- **Exec never touches `lib_OpenCnt`** in any of these calls; counting is the library's/device's own Open/Close. [O]

## 1. Ports and messages

### 1.1 PutMsg (−366): A0 = port, A1 = message [O]

Order of effects (Disable/Enable writes seen by the watchpoint: IDNestCnt 0, then 1 inside Signal/Cause, then 0, −1):

1. `Disable`.
2. `ln_Type := NT_MESSAGE` (5) whatever it was; the message is linked at the **tail** of `mp_MsgList` (AddTail).
   `mn_ReplyPort`, `mn_Length`, `ln_Pri`, `ln_Name` untouched.
3. If `mp_SigTask` = 0: nothing more (P9–P12: all four actions with a NULL `mp_SigTask` only queue; nothing is
   written in low memory).
4. Otherwise, by `mp_Flags AND 3`:

| Action | Observed effect |
|---|---|
| 0 PA_SIGNAL | `Signal(mp_SigTask, 1 << (mp_SigBit AND 31))`: bit 33 signals bit 1, bit 96+29 signals bit 29 (P5, P6). The task is woken/rescheduled by the ordinary `Signal` rules (`exec-scheduling-v34.md` §2.7). |
| 1 PA_SOFTINT | `Cause(mp_SigTask)`: the `Interrupt` node's `ln_Type` becomes NT_SOFTINT (11) while queued and NT_INTERRUPT (2) again after it ran. With interrupts enabled the software interrupt ran **before PutMsg returned** (when the Disable ended), in supervisor mode, SR = `$2000`, A1 = `is_Data`, A6 = ExecBase (the contract of `exec-scheduling-v34.md` §8). With the caller already disabled it stays pending (seen once, from a task that called `Wait` under Disable). |
| 2 PA_IGNORE | nothing |
| 3 (no public name) | **JSR to the address held in `mp_SigTask`**, from inside the Disable, in the caller's mode (user mode in the tests), with A0 = that address, A1 = port, A6 = ExecBase, D0 low byte = `mp_Flags`. The message is already linked when it runs (P8). D0, D1, A0, A1 left by the routine come back to the PutMsg caller unchanged (P8: values written by the debugger at the routine's return were the PutMsg results). A `mp_SigTask` pointing to a Task structure executed the Task as code: Guru `00000004` (illegal instruction) in the calling task (P7). |

   Bits 2–7 of `mp_Flags` are ignored: `$04`, `$40`, `$80` behaved as 0 (Signal), `$81` as 1, `$82` as 2, `$07` and
   `$83` as 3 (P13). `mp_Flags` itself is not modified.
5. `Enable`.

Registers [O] (markers in D0–D7, A2–A4; A6 = ExecBase): D2–D7, A2–A4, A6 preserved. D0, D1, A0, A1 change: after a
Signal they hold Signal's leftovers (D0 = the target task's previous `tc_SigRecvd`, D1 = 0, A0 = address of the
target's `tc_SigRecvd`, A1 = the target task); after Cause or nothing, other leftovers; with a NULL `mp_SigTask`,
D0 = A0 = address of `mp_MsgList`, D1 = 0, A1 = port. PutMsg has **no documented result**; treat D0, D1, A0, A1 as
scratch. (A5 held the trampoline's call address in every test and was not checked.)

### 1.2 GetMsg (−372): A0 = port → D0 [O]

- Disable/Enable around the unlink (IDNestCnt 0 then −1), even when the port is empty.
- Returns the **first** message and unlinks it; D0 = 0 for an empty list.
- The returned message keeps its old `ln_Succ`/`ln_Pred` (stale pointers to its former neighbours) and its
  `ln_Type` (5 or 7 as it was). This matters for WaitIO (§2.3, test WI3).
- The signal bit is not touched (G1–G4: set before, still set after every GetMsg).
- Registers: D0 result; A0 = address of `mp_MsgList`; A1 = the new first node, or the list's `lh_Tail` address when
  the list is (or becomes) empty; D1–D7, A2–A4, A6 preserved.

### 1.3 ReplyMsg (−378): A1 = message [O]

- `mn_ReplyPort` ≠ 0: same path as PutMsg to that port (Disable, AddTail, action by `mp_Flags AND 3`, NULL
  `mp_SigTask` = queue only, Enable) with `ln_Type := NT_REPLYMSG` (7). Registers as PutMsg.
- `mn_ReplyPort` = 0: `ln_Type := NT_FREEMSG` (6); `ln_Succ`/`ln_Pred` untouched, no Disable/Forbid, D0 = 0, every
  other register preserved (R2).
- No check of the current `ln_Type`: a message of type 7 or 6 is queued again as 7 (R4, R5); a message replied twice
  ends up linked twice (list corruption is the caller's problem).

### 1.4 WaitPort (−384): A0 = port → D0 [O]

- Non-empty port: D0 = **A1** = first message, not removed; no Disable/Forbid; the signal bit is left as it is (set or
  clear, WP1/WP2); D1, A0 and the rest preserved.
- Empty port: `Wait(1 << mp_SigBit)`; on wake-up the list is tested again; while empty, Wait again (WP3: one Wait; WP4:
  with the bit already set by a spurious signal, the first Wait returned at once and a second Wait was made). On
  return: D0 = A1 = first message (not removed), D1 = the signal mask, A0 changed; the signal bit was consumed by Wait
  (clear).
- `mp_Flags` is not looked at: the wait is on `mp_SigBit` whatever the action [D, the empty-port tests used PA_SIGNAL
  ports only].

### 1.5 AddPort (−354), RemPort (−360), FindPort (−390) [O]

- **AddPort** (A1 = port): Forbid (TDNestCnt 0 then −1); **NewList(`mp_MsgList`)** (garbage in the three list longs
  was replaced by an empty list); `Enqueue` on `ExecBase->PortList` by `ln_Pri` (higher first; a new port goes after
  existing ports of the same priority, A2). `ln_Type`, `mp_Flags`, `mp_SigBit`, `mp_SigTask` untouched (a port given
  `ln_Type` `$33` kept it, A1). Registers: D0 = A0 = the node the port was inserted after (leftover of Enqueue),
  D1 low byte = the port's priority (upper 24 bits preserved); A1 preserved.
- **RemPort** (A1 = port): Forbid, Remove; the port keeps stale `ln_Succ`/`ln_Pred`; D0, D1 preserved, A0 = old
  successor, A1 = old predecessor.
- **FindPort** (A1 = name): FindName on PortList, case-sensitive, first match; **no Forbid or Disable** of its own
  (the caller must Forbid, as the AutoDoc says [P]); D0 = port or 0; D1, A0 changed, A1 preserved.
- On the insert-disk screen `PortList` is empty (no public port exists before dos) [O].

## 2. I/O requests

### 2.1 DoIO (−456): A1 = IORequest → D0 [O]

1. `io_Flags := 1` (IOF_QUICK): the **whole byte** is written; a request with `io_Flags` = `$F0` reaches BeginIO with
   `$01` (IO1). `ln_Type` is **not** changed (a request with `ln_Type` `$55` reached BeginIO and came back with `$55`).
2. Calls the device's BeginIO vector (−30) with **A1 = request, A6 = `io_Device`**; D0, D1, A0 as the caller left
   them. **No Forbid, no Disable** (no write to the nest counters; BeginIO entered with −1/−1).
3. On return, if IOF_QUICK is still set: return. Otherwise the WaitIO path (§2.3): wait for NT_REPLYMSG, Remove under
   Disable. A device that cleared IOF_QUICK and replied from inside BeginIO: no Wait at all, the request was removed
   from the port, the signal bit **stayed set** (IO6). A device that replied but left IOF_QUICK set: DoIO returned at
   once and the request **stayed in the reply port** with `ln_Type` 7 (IO7).
4. D0 = `io_Error` **sign-extended** to a long (`$05` → 5, `$FE` → −2, `$F9` → −7).

Registers: A1 and A6 are restored by DoIO; D0 is the result; **all other registers are whatever BeginIO (and, on the
wait path, WaitIO) left**: a BeginIO that changed D1, D2, A0, A2 made DoIO return those values (IO8). The timer's
TR_GETSYSTIME came back with D1 and A0 changed. A well-behaved device preserves D2–D7/A2–A5 [P], so DoIO's own
contract is: D0 result, D1/A0 scratch, A1 preserved.

### 2.2 SendIO (−462): A1 = IORequest [O]

- `io_Flags := 0` (whole byte, from `$F1`, `$01` or `$00`), `ln_Type` untouched, BeginIO called as in DoIO, return.
- No result: D0 is left as BeginIO left it (the caller's D0 when BeginIO does not change it).
- Only A6 is restored: a BeginIO that changed D1, D2, A0, **A1**, A2 made all five come back changed (IO9).
- No Forbid/Disable.

### 2.3 WaitIO (−474): A1 = IORequest → D0 [O]

1. If `io_Flags` bit 0 (IOF_QUICK) is set: return D0 = `io_Error` sign-extended. Nothing else is read or written:
   the request was also linked in its reply port (by a PutMsg made for the test) and stayed there; no Wait, no Disable,
   the signal bit unchanged; only D0 changes (WI1).
2. Otherwise, while `ln_Type` ≠ NT_REPLYMSG (7): `Wait(1 << mn_ReplyPort->mp_SigBit)`. The type is tested **before**
   the first Wait: an already replied request causes no Wait (WI2), a pending one one Wait per wake-up (WI4: one Wait
   for a 100 ms timer request; WI5: with the bit set beforehand by a spurious signal, two Waits).
3. `Disable`, **Remove(request)**, `Enable` (watchpoint: IDNestCnt 0 then −1). The Remove is unconditional and uses
   the request's own `ln_Succ`/`ln_Pred`: a type-7 request whose links pointed at two unrelated nodes X and Y had them
   joined (X.pred := Y, Y.succ := X, WI3). So **WaitIO after GetMsg of the same request corrupts the port list or
   whatever the stale links reach**; 1.3 callers must use one or the other.
4. D0 = `io_Error` sign-extended.

Signal bit: when no Wait was needed (WI2), the reply port's signal bit is **left as it was** (set stays set; a later
`Wait` on it returns at once). When a Wait was made, Wait consumed it (clear). Registers: D0 result; A1 preserved; D1
and A0 changed on the non-quick path (D1 = the signal mask after a Wait, or the caller's D1 with its **low byte
replaced by `mp_SigBit`** when no Wait was needed); D2–D7, A2–A4, A6 preserved.

### 2.4 CheckIO (−468): A1 = IORequest → D0 [O]

D0 = A1 if `(io_Flags AND 1) ≠ 0` **or** `ln_Type` = 7; otherwise 0. Only bit 0 of `io_Flags` counts (`$FE` with type
7 → request; `$80` with type 5 → 0; `$FF` with type 0 → request). `ln_Type` 6 (NT_FREEMSG) or 0 without IOF_QUICK →
0. No other register changed, no Forbid/Disable, nothing removed (CK1–CK9). On a pending timer request: 0; after
WaitIO: the request (CK10, CK11).

### 2.5 AbortIO (−480): A1 = IORequest → D0 [O]

- Calls the device's AbortIO vector (−36) with **A1 = request, A6 = `io_Device`**, D0/D1/A0 as the caller left them;
  no test of `io_Flags` or `ln_Type` (a quick or already-replied request is passed on too), no Forbid/Disable.
- D0 on return = **the device's D0, unchanged** (a stub returning `$AB0127ED` made AbortIO return it; the ROM's
  timer.device returned 0 after aborting). The 1.3 AutoDoc gives AbortIO no result [P]; callers must not rely on D0.
- Only A6 is restored; D1 and A1 changed by the device come back changed.
- timer.device example (AB2): AbortIO of a pending 5 s request replied it at once with `io_Error` = −2
  (IOERR_ABORTED), `ln_Type` 7, signal set; the following WaitIO made no Wait, removed it and returned −2.

### 2.6 What exec does not do [O]

- No call sets `ln_Type` of a request except ReplyMsg/PutMsg (5/7/6): DoIO and SendIO leave it, so a request that was
  never sent has whatever type the caller gave it (CheckIO only looks at type 7).
- No call clears `io_Error` except OpenDevice (§3.1).
- BeginIO and AbortIO run in the caller's context, without Forbid or Disable: the device protects its own queues.

## 3. Devices

### 3.1 OpenDevice (−444): A0 = name, D0 = unit, A1 = IORequest, D1 = flags → D0 [O]

1. `Forbid` (TDNestCnt 0) — also when the name is not found.
2. `FindName(DeviceList, name)`: **first** node of that name only; a second device of the same name is never tried,
   even when the first one's Open fails (OD7).
3. Not found: `io_Device := 0`, `io_Error := −1` (IOERR_OPENFAIL); `io_Unit`, `io_Command`, `io_Flags` and the
   message header untouched; Permit; D0 = −1; A0 = 0, A1 = the name pointer on return (OD5, OD9).
4. Found: `io_Device := device`, `io_Unit := 0`, `io_Error := 0` (seen at the entry of the device's Open; bytes
   28–30, `io_Command` and `io_Flags`, untouched, D1 is **not** copied into `io_Flags`), then the device's Open vector
   (−6) with **A6 = device, A1 = request, D0 = unit, D1 = flags, A0 = device**, TDNestCnt still 0 (under Forbid).
5. Permit. D0 = `io_Error` **sign-extended** (the device's D0 is ignored: a device returning `$12345678` with
   `io_Error` 0 gave 0; `io_Error` `$FD` → −3; `$05` → 5).
6. **`io_Device` is left set when the device's Open fails** (OD2, OD3); only the not-found path clears it.

Registers: D0 result; A0 = device (found) or 0 (not found); A6 restored; D1 and A1 preserved unless the device's Open
changes them (they then leak, OD8). `lib_OpenCnt` of the device is not touched by exec.

Condition codes [O, one sample, 2026-11-11]: dos's Delay opening `timer.device` in a booted system (ramlib's
OpenDevice in front) got D0 = 0 back with **Z set** (N clear). A failing OpenDevice (D0 negative) was not observed
at the return, so whether N follows the sign-extended `io_Error` is not established [?].

With ramlib installed (after dos starts) the vector is ramlib's replacement, which calls this exec function and then
loads from `DEVS:` on failure (`ramlib-v34.md` §3); a 1.3 caller sees the values of the last attempt.

### 3.2 CloseDevice (−450): A1 = IORequest → D0 [O]

Forbid; the device's Close vector (−12) with **A6 = `io_Device`, A1 = request** (D0, D1, A0 as the caller left them);
Permit; D0 = the Close vector's D0 unchanged. `io_Device`, `io_Unit`, `io_Flags`, `io_Error`, `ln_Type` untouched by
exec. Only A6 is restored. No test of `io_Device` [D: a NULL or −1 `io_Device` would call through a bogus table; not
tried].

### 3.3 AddDevice (−432), RemDevice (−438) [O]

- **AddDevice** (A1 = device): Forbid; the SumLibrary step of §4.4 when `LIBF_SUMUSED` is set; `Enqueue` on
  DeviceList (a priority-3 device went first, ahead of the ROM devices of priority 0). `ln_Type` is **not** set (`$77`
  stayed `$77`), `lib_OpenCnt` untouched. Registers as AddPort (D0 = A0 = predecessor, D1 low byte = priority).
- **RemDevice** (A1 = device): Forbid; the device's Expunge vector (−18) with **A6 = A1 = D0 = device**; Permit;
  D0 = Expunge's D0 unchanged. **Exec does not unlink the node**: the device was still in DeviceList after an Expunge
  stub that returned a value without removing it (RD1). Unlinking is Expunge's job; freeing the returned seglist is
  ramlib's (`ramlib-v34.md` §2.2).

## 4. Libraries and resources

### 4.1 OpenLibrary (−552): A1 = name, D0 = version → D0 [O]

1. `Forbid` (also when nothing is found).
2. Walk `LibList` from the head. For every node whose name matches (case-sensitive): if **(WORD)`lib_Version` ≥
   (WORD)D0**, signed, open it (step 3); otherwise **continue with the next nodes** (OL13: a version-40 library
   followed by a version-50 one of the same name: request 45 opened the second, request 40 the first).
3. Call the library's Open vector (−6) with **A6 = base, D0 = base, A0 = base, A1 = D1 = the name pointer** (the
   requested version is **not** passed), under Forbid. Its D0 is the result **as returned** (0 → 0; `$1234` →
   `$1234`). An Open that returns 0 ends the call with 0: later nodes of the same name are not tried (OL15).
4. Nothing suitable: D0 = 0 (the Open vector is not called for a too-low version).
5. `Permit`.

Version test vectors on a library of version 40 (OL1–OL10): 0, 39, 40 open; 41 fails; `$10028` opens and `$10029`
fails (**only the low word of D0 counts**); `$8000`, `$FFFF`, `$FFFFFFFF`, `$10000` open (negative or zero as signed
words). Other pairs (OL11): `lib_Version` `$8001` with 40 → fail; `$FFFF` with 1 → fail; 40 with `$7FFF` → fail;
`$7FFF` with `$8000` → open; `$8000` with `$8001` → fail; `$8001` with `$8000` → open; 0 with 0 → open; 0 with 1 →
fail. Rule: open iff `(signed 16-bit) lib_Version >= (signed 16-bit) D0`.

Registers: D0 result; D1 = the name pointer; A0 = the library opened, or a pointer left by the name scan when nothing
was opened; A1 and A6 restored by exec only for A6 (A1 changed by an Open vector leaks out, OL16). **A2 must be
preserved by the Open vector** [O, 2026-11-10]: in a booted system (ramlib's OpenLibrary replacement in front of
exec's), an Open that returned with A2 changed made the OpenLibrary call unwind through a stack frame derived from
that A2: SP was loaded from the junk A2 and the CPU ran off into low memory before returning to the caller. Whether
exec's own OpenLibrary or ramlib's wrapper relies on A2 was not separated. D2 changed by the Open vector was restored
before the return. OpenDevice (OD8), AbortIO (AB3) and DoIO/SendIO (IO8/IO9) tolerated an A2 change (passed it on
or restored it). `lib_OpenCnt` is
not touched by exec: counting is the library's Open (graphics.library 34 itself left its count at 1 across an
OpenLibrary/CloseLibrary pair, OL17).

**OldOpenLibrary** (−408, A1 = name): the same with version 0; D0 on entry is ignored (D0 = 99 opened a version-40
library, OL12).

**Condition codes on return** [O, 2026-11-11]: the implementation-side probe `tests/explvo_probe.s` (line `EXP OLZ`),
run unchanged on the real ROM from a booted probe disk (so through ramlib's OpenLibrary replacement in front of this
function), printed `000000FF`: **Z clear** after a successful `OpenLibrary("graphics.library", 0)` and **Z set** after
`OpenLibrary("graphics.library", 999)` (present, version too low, so no disk load). Programs branch on the flags
straight after the call (a `movea.l d0,a6` then `beq` was seen in a third-party program), so the result must leave
Z = (D0 = 0). Exec's own function without ramlib in front was not checked separately.

With ramlib installed, the vector is ramlib's replacement (`ramlib-v34.md` §3): it calls this exec function first, then
its base name, then loads from `LIBS:`; its step 2 ("name present, version too low → fail without disk access") and
step 10 (final attempt = the version test of this section) rely on the rule above.

### 4.2 CloseLibrary (−414), RemLibrary (−402) [O]

- **CloseLibrary** (A1 = base): Forbid; the Close vector (−12) with **A6 = A1 = base**, D0/D1/A0 as the caller left
  them; Permit; D0 = Close's D0 unchanged. No test of A1: **CloseLibrary(NULL) calls through the top of the address
  space and ended in an illegal-instruction exception** (Guru `00000004`, N1). Only A6 is restored.
- **RemLibrary** (A1 = base): Forbid; the Expunge vector (−18) with **A6 = A1 = D0 = base**; Permit; D0 = Expunge's
  D0. The node is **not** unlinked by exec (RL1).

### 4.3 AddLibrary (−396) [O]

Forbid; the SumLibrary step (§4.4) when `LIBF_SUMUSED` is set; `Enqueue` on LibList (priority 0 goes after the
existing priority-0 libraries, i.e. last on the insert-disk screen). `ln_Type` is **not** set: a library given type
`$66` kept it. Registers: D0 = A0 = the predecessor node, D1 low byte = the priority.

Consequence seen on the running 1.3 [O]: `exec.library` and `mathffp.library` have `ln_Type` 9 (NT_LIBRARY),
`graphics`, `layers`, `intuition` and `romboot` have **0** and `expansion.library` has **8** (NT_RESOURCE): whatever
their own init left, since neither MakeLibrary/InitResident nor AddLibrary fix it [D]. Code that tests `ln_Type ==
NT_LIBRARY` on a ROM library fails on 1.3.

### 4.4 The checksum step (SumLibrary −426, and Add* with LIBF_SUMUSED) [O]

| `lib_Flags` on entry | Effect |
|---|---|
| SUMUSED (4) clear (0, 1, 2, `$FB`) | nothing: flags and `lib_Sum` unchanged |
| SUMUSED and CHANGED (6) | sum recomputed and stored, CHANGED cleared (flags become 4) |
| SUMUSED only (4), sum correct | nothing written; D0 low word = the sum |
| SUMUSED only (4), sum wrong | **`Alert($81000003)`** (AN_LibChkSum, dead-end): seen from AddLibrary on a library with `lib_Sum` = `$5A5A5A5A` |

- **The sum**: the 16-bit wrap-around sum of the words of the `lib_NegSize` bytes just below the base (the jump
  table), stored as a **word in the upper half of `lib_Sum`**; the lower word is not written (a `$5A5A5A5A` field
  became `$xxxx5A5A`). Checked on tables of 5, 6 and 9 vectors and on a 6-vector table declared with `lib_NegSize` =
  30 (only 30 bytes summed). The ROM libraries show `lib_Flags` = 4 and `lib_Sum` = `$xxxx0000`.
- Registers (SumLibrary): with SUMUSED, D1 = the sum and A0 changed; on the verify path (SUMUSED without CHANGED) D0's
  low word = the sum too (upper word preserved), on the recompute path D0 is unchanged; without SUMUSED nothing changes.
- AddDevice follows the same table (a device with flags 6 came back with flags 4 and a word sum).

### 4.5 Resources [O]

- **AddResource** (−486, A1): Forbid; `Enqueue` on ResourceList (priority 7 went first); `ln_Type` not set (`$44`
  kept); no checksum step observed (the test resource had `lib_Flags` 0). Registers as AddPort.
- **OpenResource** (−498, A1 = name, D0 ignored): Forbid; FindName on ResourceList (first match); D0 = node or 0.
  A request with D0 = 99 returned a resource whose `lib_Version` is 5: **no version test**, no open count, no vector
  called. D1, A0 changed; A1 preserved.
- **RemResource** (−492, A1): Forbid; Remove; D0, D1 preserved, A0 = old successor, A1 = old predecessor.

## 5. Calling-context summary

### 5.1 Forbid / Disable used by exec itself [O]

| Call | Exclusion | Callee run inside it |
|---|---|---|
| PutMsg, ReplyMsg (port ≠ 0) | Disable (Signal/Cause nest one more level) | the action of `mp_Flags AND 3` (Signal, Cause, or the JSR of action 3) |
| ReplyMsg (no port) | none | — |
| GetMsg | Disable (also when empty) | — |
| WaitPort | none (Wait when empty) | — |
| WaitIO | Disable around the Remove only (Wait when pending) | — |
| DoIO, SendIO, AbortIO, CheckIO | none | BeginIO / AbortIO vectors run **without** Forbid/Disable |
| AddPort, RemPort, AddLibrary, AddDevice, AddResource, RemResource, OpenResource | Forbid | — |
| FindPort | none (caller's job) | — |
| OpenLibrary, OpenDevice | Forbid (also when not found) | Open vector **under Forbid** |
| CloseLibrary, CloseDevice | Forbid | Close vector under Forbid |
| RemLibrary, RemDevice | Forbid | Expunge vector under Forbid |
| SumLibrary | not watched | — |

Open/Close/Expunge vectors therefore start with TDNestCnt ≥ 0; a vector that Waits (a device Open that does I/O, a
library Open that loads something) breaks the Forbid for the duration of the Wait (`exec-scheduling-v34.md` §2.4).

### 5.2 Registers at a glance [O]

"Leak" = the value the callee (device/library vector) left comes back to the caller. D2–D7, A2–A4 were preserved by
every exec call when the callee preserved them; A6 = ExecBase on return of every call.

| Call | D0 | D1 | A0 | A1 | Notes |
|---|---|---|---|---|---|
| PutMsg, ReplyMsg | changed | changed | changed | changed | action 3: the routine's D0/D1/A0/A1 |
| ReplyMsg, no port | 0 | kept | kept | kept | |
| GetMsg | message / 0 | kept | changed | changed | |
| WaitPort | message | kept / mask | kept / changed | = D0 | second value: empty-port path |
| AddPort, AddLibrary, AddDevice, AddResource | changed | low byte = pri | changed | kept | |
| RemPort, RemResource | kept | kept | changed | changed | |
| FindPort, OpenResource | result | changed | changed | kept | |
| DoIO | io_Error (ext.) | leak | leak | **kept** | quick path; wait path also changes D1/A0 |
| SendIO | leak | leak | leak | leak | |
| WaitIO | io_Error (ext.) | changed* | changed* | kept | *non-quick path only |
| CheckIO | result | kept | kept | kept | |
| AbortIO, CloseDevice, CloseLibrary, RemDevice, RemLibrary | callee's D0 | leak | leak | leak | |
| OpenDevice | io_Error (ext.) | leak | device / 0 | leak / name | |
| OpenLibrary, OldOpenLibrary | Open's D0 / 0 | name | base / scan leftover | leak | |
| SumLibrary (SUMUSED) | low word = sum (verify path) / kept | sum | changed | kept | |

A 1.3-compatible implementation may preserve more; it must not rely on the callee preserving D0, D1, A0, A1, and it
must give the results above in D0 (including the **sign-extended** `io_Error` and the passed-through callee values).

## 6. Differences from the public documentation and from 2.0+ [O vs. P]

1. `mp_Flags AND 3` = 3 is a working **"call a routine"** action in V34 (A0 = routine = `mp_SigTask`, A1 = port, under
   Disable). The 1.3 includes define only PA_SIGNAL/PA_SOFTINT/PA_IGNORE and PF_ACTION = 3.
2. A NULL `mp_SigTask` disables the action (queue only), whatever the action (`gameport-v34.md` §1.1 relies on it for
   its unit ports).
3. `ReplyMsg` with no reply port sets NT_FREEMSG and returns; it is not an error.
4. `AddPort` does not set NT_MSGPORT (but it does empty `mp_MsgList`); `AddLibrary`/`AddDevice`/`AddResource` do not set
   the node type either.
5. The library Open vector receives **D0 = library base**, not the requested version (the RKRM describes the version
   in D0 for later systems).
6. OpenLibrary's version test is a **signed 16-bit** comparison and it **keeps searching** past a too-low version.
7. OpenDevice clears `io_Unit` and `io_Error` before calling the device, and leaves `io_Device` set when the device's
   Open fails; only "device not found" clears it.
8. `CloseLibrary(NULL)` is not safe on 1.3 (2.0+ accepts it).
9. `lib_Sum` is a 16-bit word in the upper half of the field; a wrong sum with SUMUSED alone is a dead-end alert at
   Add time.
10. DoIO/SendIO overwrite the whole `io_Flags` byte (1 / 0), not only IOF_QUICK.
11. WaitIO removes the request unconditionally, even when it is not in a list any more.
12. AbortIO returns whatever the device's AbortIO returns.

## 7. Known users [D]

| User | Calls and what they rely on | Spec |
|---|---|---|
| dos packets, every handler | PutMsg/GetMsg/WaitPort/ReplyMsg on PA_SIGNAL ports; `returnpkt` = PutMsg to `dp_Port` | `dos-v34-spec.md` §2a, `handlers-v34.md` |
| BCPL runtime, dos | DoIO on trackdisk/console requests | `bcpl-runtime-v34.md` §8.4.2 |
| intuition requesters, input timing | CheckIO/WaitIO, AbortIO of timer requests | `intuition-requesters-v34.md` §7.1, `intuiticks-repeat-v34.md` §2.1 |
| gameport/keyboard/input unit queues | PutMsg to a PA_SIGNAL port with NULL `mp_SigTask` = queue only | `gameport-v34.md` §1.1 |
| console/gameport CMD_CLEAR | a request left with IOF_QUICK by BeginIO is "done" for DoIO/WaitIO/CheckIO; without IOF_QUICK it is never replied | `console-keymap-v34.md` §2.4, `gameport-device-v34.md` |
| audio.device OpenDevice | OpenDevice's Open running under Forbid, then WaitIO inside Open | `audio-device-v34.md` §1.3 |
| Procure/Vacate | a PA_IGNORE port used as a bid queue (PutMsg/GetMsg/ReplyMsg) | `exec-scheduling-v34.md` §6 |
| FastFonts, Preferences | AddPort/FindPort/RemPort on a PA_IGNORE port they mark NT_MSGPORT themselves | `fastfonts-ff.md` §2, `preferences-13.md` §4 |
| ramlib | calls the exec OpenLibrary/OpenDevice and relies on the version rule and on `io_Error`/`io_Device` values | `ramlib-v34.md` §3 |
| timer.device, uae-int2, disk.resource users | AddDevice, AddResource, OpenResource | `timer-v34.md` §1.1, `uae-int2-v34.md` §2.2, `setpatch-disk-resource.md` §1 |

## 8. Test vectors

All were run as described in the header. "Markers" = D0–D7, A0–A4 loaded with `$1111000n` (n = register index)
except the arguments; "sig" = the port's signal bit in the hijacked task's `tc_SigRecvd`. The fake device has six
vectors, the fake library five; their stubs preserve every register unless the vector says otherwise.

#### V1 PutMsg / GetMsg (port: PA_SIGNAL to the calling task, bit b)

| # | Setup | Call | Expected |
|---|---|---|---|
| P1 | empty port, M1 type `$55`, sig clear | PutMsg(P, M1) | M1 type 5, list = [M1], sig set; D0 = previous `tc_SigRecvd`, D1 = 0, A0/A1 changed |
| P2 | after P1 | PutMsg(P, M2) | list = [M1, M2] (tail) |
| P3 | flags 2 (PA_IGNORE) | PutMsg | queued, type 5, sig not set |
| P4 | flags 1, `mp_SigTask` = Interrupt (type 2, `is_Data` = `$DA7A0000`) | PutMsg | queued; is_Code runs before PutMsg returns with A1 = `$DA7A0000`, A6 = ExecBase, SR `$2000`; Interrupt type 2 afterwards |
| P5 | flags 0, `mp_SigBit` = 33 | PutMsg | bit 1 signalled |
| P6 | flags 0, `mp_SigBit` = 96 + b | PutMsg | bit b signalled |
| P7 | flags 3, `mp_SigTask` = a Task | PutMsg | Guru `00000004` (the Task is executed) |
| P8 | flags 3, `mp_SigTask` = a routine that returns D0 = `$13579BDF`, D1 = `$2468ACE0`, A0 = `$0A0A0A0A`, A1 = `$0B0B0B0B` | PutMsg | routine entered with A0 = routine, A1 = port, D0 low byte 3, message already the list head, Disabled; PutMsg returns the four values |
| P9–P12 | flags 0, 1, 2, 3 with `mp_SigTask` = 0 | PutMsg | queued, type 5, nothing else; D0 = A0 = `&mp_MsgList`, D1 = 0, A1 = port; low memory unchanged |
| P13 | `mp_SigTask` = routine; flags `$04`, `$40`, `$80` / `$81` / `$82` / `$07`, `$83` | PutMsg | treated as action 0 / 1 / 2 / 3 |
| G1–G3 | [M1, M2, M3] queued, sig set | GetMsg ×3 | M1, M2, M3 in order; each keeps type 5 and stale links; sig still set |
| G4 | empty | GetMsg | D0 = 0, A1 = `&lh_Tail` |
| G5 | any | GetMsg | IDNestCnt written 0 then −1 |

#### V2 ReplyMsg

| # | Setup | Expected |
|---|---|---|
| R1 | `mn_ReplyPort` = PA_SIGNAL port | type 7, appended, sig set; Disable as PutMsg |
| R2 | `mn_ReplyPort` = 0, type `$55`, links 0 | type 6, links still 0; D0 = 0, other registers unchanged; no nest-counter write |
| R3 | reply port PA_SOFTINT | type 7, queued, softint ran |
| R4 | reply port PA_IGNORE | type 7, queued, sig unchanged |
| R5 | message already type 7, then one of type 6 | both queued with type 7 |
| R6 | reply port PA_SIGNAL with `mp_SigTask` = 0 | type 7, queued, nothing signalled |

#### V3 WaitPort

| # | Setup | Expected |
|---|---|---|
| WP1 | M1 queued, sig set | D0 = A1 = M1, M1 still queued, sig still set, no Wait, no nest write |
| WP2 | M1 queued, sig clear | same, sig still clear |
| WP3 | empty port, timer request (100 ms) sent with this port as reply port | one Wait(mask); returns the timer request (type 7, still queued); sig clear; D1 = mask |
| WP4 | same, sig set beforehand | two Waits; same result |

#### V4 AddPort / RemPort / FindPort

| # | Setup | Expected |
|---|---|---|
| AP1 | port "r12.port", pri 5, `ln_Type` `$33`, list longs `$11111111 $22222222 $33333333` | type still `$33`; `mp_MsgList` = empty list; in PortList; Forbid only |
| AP2 | ports of priority 0, 10, −10, 10 added in that order | PortList order: 10 (first added), 10 (second), 0, −10 |
| AP3 | FindPort("r12.port") / FindPort("r12.none") | the port / 0; no nest write |
| AP4 | RemPort, then FindPort | removed; FindPort → 0; Forbid only |

#### V5 DoIO / SendIO / WaitIO / CheckIO / AbortIO (fake device unless stated)

| # | Setup | Call | Expected |
|---|---|---|---|
| IO1 | `io_Flags` `$F0`, type `$55`, BeginIO leaves IOF_QUICK, sets `io_Error` 0 | DoIO | BeginIO sees flags `$01`, type `$55`, A6 = device, A1 = request; D0 = 0; no Wait; no nest write |
| IO2 | same, `io_Error` 5 | DoIO | D0 = 5 |
| IO3 | same, `io_Error` `$FE` | DoIO | D0 = −2 |
| IO4 | timer TR_ADDREQUEST 100 ms | DoIO | one Wait; type 7; removed from port; sig clear; D0 = 0 |
| IO5 | timer TR_GETSYSTIME | DoIO | no Wait; flags `$01`; `ln_Type` **5 on return even when it was `$55` before** (2026-11-10, §8a): timer.device writes NT_MESSAGE on this quick path; exec's DoIO itself leaves `ln_Type` alone (IO1) |
| IO6 | BeginIO clears IOF_QUICK and calls ReplyMsg | DoIO | no Wait; type 7; removed; sig **set**; D0 = `io_Error` |
| IO7 | BeginIO keeps IOF_QUICK and calls ReplyMsg | DoIO | no Wait; type 7; request **still in the port**; flags `$01` |
| IO8 | BeginIO (quick) sets D1, D2, A0, A1, A2 to junk | DoIO | D1, D2, A0, A2 come back as junk; A1 = request |
| IO9 | same | SendIO | D1, D2, A0, A1, A2 come back as junk; D0 = caller's |
| IO10 | BeginIO changes A6 | DoIO, SendIO | A6 = ExecBase on return |
| IO11 | `io_Flags` `$F1`, `$00`, `$01` | SendIO | BeginIO sees `$00`; D0 = caller's |
| WI1 | IOF_QUICK set, type 5, `io_Error` `$F9`, request also queued in its port, sig set | WaitIO | D0 = −7; still queued; sig set; no Wait; only D0 changed |
| WI2 | ReplyMsg'd (type 7, queued), sig set / clear | WaitIO | D0 = `io_Error`; removed; no Wait; sig unchanged (set / clear); D1 low byte = `mp_SigBit` |
| WI3 | type 7, links → nodes X, Y (not a list) | WaitIO | X.pred = Y, Y.succ = X |
| WI4 | timer 100 ms pending | WaitIO | one Wait(mask); type 7; removed; sig clear; D0 = 0 |
| WI5 | same, sig set beforehand | WaitIO | two Waits |
| WI6 | any non-quick, replied | WaitIO | IDNestCnt written 0 then −1 |
| CK1–CK9 | (`io_Flags`, type) = (1,5) (1,7) (0,5) (0,7) (0,6) (0,0) (`$FE`,7) (`$FF`,0) (`$80`,5) | CheckIO | request, request, 0, request, 0, 0, request, request, 0; only D0 changes |
| CK10, CK11 | timer request pending / after WaitIO | CheckIO | 0 / request |
| AB1 | device AbortIO returns D0 `$AB0127ED` (pending and quick/replied requests) | AbortIO | D0 = `$AB0127ED`; flags/type/error untouched by exec; A1 = request and A6 = device in the vector |
| AB2 | timer request 5 s pending | AbortIO, then WaitIO | AbortIO D0 = 0, request type 7 with `io_Error` −2, sig set; WaitIO: no Wait, −2, removed |
| AB3 | device AbortIO changes A6, A1, D1, returns 7 | AbortIO | D0 = 7, A1/D1 junk, A6 = ExecBase |

#### V6 Devices

| # | Setup | Call | Expected |
|---|---|---|---|
| OD1 | request filled with `$80..$AF` (byte i = `$80`+i), device found, Open leaves fields | OpenDevice(name, 2, ior, 3) | at Open: bytes 20–23 = device, 24–27 = 0, 28–30 unchanged (`$9C $9D $9E`), 31 = 0; A6 = A0 = device, A1 = ior, D0 = 2, D1 = 3, TDNestCnt 0; D0 = 0 |
| OD2 | Open sets `io_Error` `$FD`, D0 `$0BADBAD0` | OpenDevice | D0 = −3, `io_Device` = device |
| OD3 | Open sets `io_Error` 5 | OpenDevice | D0 = 5, `io_Device` = device |
| OD4 | Open sets `io_Error` 0, D0 `$12345678` | OpenDevice | D0 = 0 |
| OD5 | name not in DeviceList, request filled as OD1 | OpenDevice | D0 = −1; byte 31 = `$FF`; bytes 20–23 = 0; 24–30 unchanged; A0 = 0, A1 = name; Forbid/Permit seen. Under ramlib (booted system, its failed `DEVS:` load included): the same except **A0 = a RAM pointer, not 0** (2026-11-10) |
| OD6 | Open leaves `io_Error` (`$77` before the call) | OpenDevice | D0 = 0 (exec cleared it before Open) |
| OD7 | two devices of the same name, the first Open fails | OpenDevice | only the first Open called; D0 = −1; `io_Device` = first |
| OD8 | Open changes A6, A1, D1 | OpenDevice | A1, D1 leak; A6 = ExecBase |
| CD1 | Close returns D0 `$C105ED` | CloseDevice | D0 = `$C105ED`; Close entered with A6 = device, A1 = ior, TDNestCnt 0; `io_Device`/`io_Unit` unchanged. Under ramlib, with a vector returning the BPTR of a one-hunk 16-byte seglist: that seglist is freed and **the caller gets D0 = 16**, not the BPTR (2026-11-10, `ramlib-v34.md` §2.2) |
| ADV1 | device pri 3, type `$77`, flags 0 | AddDevice | first in DeviceList; type `$77`; flags/sum unchanged; Forbid |
| ADV2 | flags 6, `lib_Sum` `$5A5A5A5A` | AddDevice | flags 4, `lib_Sum` = word sum in the upper half, `$5A5A` kept |
| RD1 | Expunge returns `$5E6`, does not unlink | RemDevice | D0 = `$5E6`; still listed; Expunge entered with A6 = A1 = D0 = device, TDNestCnt 0. Under ramlib, with a vector returning the BPTR of a one-hunk 16-byte seglist: that seglist is freed and **the caller gets D0 = 16**, not the BPTR (2026-11-10, `ramlib-v34.md` §2.2) |

#### V7 Libraries, checksum, resources

| # | Setup | Call | Expected |
|---|---|---|---|
| OL1–OL10 | library version 40; D0 = 0, 39, 40, 41, `$10028`, `$10029`, `$8000`, `$FFFF`, `$FFFFFFFF`, `$10000` | OpenLibrary | open, open, open, 0, open, 0, open, open, open, open |
| OL11 | (lib_Version, D0) = (`$8001`,40) (`$FFFF`,1) (40,`$7FFF`) (`$7FFF`,`$8000`) (`$8000`,`$8001`) (`$8001`,`$8000`) (0,0) (0,1) | OpenLibrary | 0, 0, 0, open, 0, open, open, 0 |
| OL12 | D0 = 99 | OldOpenLibrary | opens the version-40 library |
| OL13 | "r12" v40 pri 0, then "r12" v50 pri −5 | OpenLibrary(45) / (40) | the v50 one / the v40 one |
| OL14 | Open returns 0 / `$1234` | OpenLibrary | 0 / `$1234` |
| OL15 | two libraries of the same name, first Open returns 0 | OpenLibrary(0) | 0; second Open not called |
| OL16 | Open changes A6, A1, A0, D1, returns `$1234` | OpenLibrary | D0 `$1234`; A0, A1, D1 leak; A6 = ExecBase. **An Open that also changes A2 crashes the caller** (booted system, 2026-11-10, §4.1); D2 changed by Open is restored |
| OL17 | `graphics.library` (count 1) | OpenLibrary(34) / (35), CloseLibrary | base / 0; count stays 1 throughout |
| OL18 | any found library | OpenLibrary | Open entered with A6 = A0 = D0 = base, A1 = D1 = name, TDNestCnt 0 |
| OL19 | name absent | OpenLibrary | D0 = 0; Forbid/Permit seen |
| OL20 | `graphics.library` version 0 / version 999 (booted system) | OpenLibrary, flags tested right after | Z clear / Z set (2026-11-11) |
| CL1 | Close returns `$C105ED` | CloseLibrary | D0 = `$C105ED`; A6 = A1 = base in Close; TDNestCnt 0. Under ramlib, with a vector returning the BPTR of a one-hunk 16-byte seglist: that seglist is freed and **the caller gets D0 = 16**, not the BPTR (2026-11-10, `ramlib-v34.md` §2.2) |
| RL1 | Expunge returns `$5E6` | RemLibrary | D0 = `$5E6`; node still listed; A6 = A1 = D0 = base in Expunge. Under ramlib, with a vector returning the BPTR of a one-hunk 16-byte seglist: that seglist is freed and **the caller gets D0 = 16**, not the BPTR (2026-11-10, `ramlib-v34.md` §2.2) |
| N1 | — | CloseLibrary(NULL) | illegal-instruction exception (Guru `00000004`) |
| AL1 | pri 0, type `$66`, flags 0 | AddLibrary | last in LibList, type `$66`, flags/sum unchanged, Forbid |
| AL2 | flags 6 / 2 / 1 / `$FB`, `lib_Sum` `$5A5A5A5A` | AddLibrary | `lib_Sum` upper word = word sum and flags 4 / unchanged ×3 |
| AL3 | flags 4 with the sum left by AL2 | AddLibrary | accepted, nothing changed |
| AL4 | flags 4, `lib_Sum` `$5A5A5A5A` (wrong) | AddLibrary | dead-end `Alert($81000003)`: from a CLI program on a booted 1.3 the screen showed "Software Failure.   Press left mouse button to continue." / "Guru Meditation #81000003.00000000"; nothing on the serial port (2026-11-10) |
| SL1–SL4 | flags 0 / 2 / 4 (correct sum) / 6 | SumLibrary | nothing / nothing / D0 low word = D1 = sum / sum stored, flags 4 |
| SL5 | 6 vectors, `lib_NegSize` = 30 | AddLibrary (flags 6) | sum of the 30 bytes only |
| AR1 | resource pri 7, type `$44`, `lib_Version` 5 | AddResource | first in ResourceList; type `$44`; Forbid |
| OR1 | D0 = 99 / unknown name | OpenResource | the node / 0; Forbid; no field changed |
| RR1 | — | RemResource | unlinked; Forbid; D0, D1 kept |

Vector count: 13 PutMsg (P1–P13, P13 = 7 flag values), 5 GetMsg, 6 ReplyMsg, 4 WaitPort, 4 port-list, 11 DoIO/SendIO,
6 WaitIO, 11 CheckIO, 3 AbortIO, 12 device, 31 library/checksum/resource.

### 8a. Run of `tests/exec_msgio_probe.s` on the real ROM (2026-11-10) [O]

`tests/exec_msgio_probe.s` assembled and run unchanged (argument "" so that N1 is skipped) from the startup-sequence
of an OFS floppy with empty `libs`/`devs` directories, on `kick34005.A500` (Amiberry A500, cycle-exact, 512 KB chip +
512 KB slow; booted system, so ramlib's replacements sit in front of OpenLibrary/OpenDevice/Close*/Rem*). Output
checked with `exec_msgio_check.py check13`.

- **First run**: the probe stopped at **OL16**: its fake Open vector clobbers D1, D2, A0, A1, A2 and A6; the system
  crashed before OpenLibrary returned. A per-instruction trace from the vector's return (registers only) showed A6
  and D2 restored, then SP taken from the clobbered A2 (§4.1). Every line printed before OL16 (P*, G*, R*, WP*, AP*,
  IO*, WI*, CK*, AB*, OD*, CD1, RD1, ADV*, AL1–AL3, SL*, OL1–OL15) was kept from this run; IO8/IO9 (A2 leak through
  DoIO/SendIO) pass there.
- **Second run** with the debugger turning the fake vector's A2 clobber into no-ops before the probe started (the
  only change; IO8/IO9 then naturally show A2 unchanged): reached the end: **130 vectors, 122 pass**; the 8 others are IO8/IO9 (expected once the A2 clobber is gone) and the six below.
- Differences from §8 (rows updated above): **IO5** (`ln_Type` set to 5 by timer.device on the quick
  TR_GETSYSTIME path); **OD5** (A0 not 0 under ramlib); **CD1, RD1, CL1, RL1** (with a Close/Expunge returning a
  real seglist BPTR, ramlib frees it and the caller gets D0 = 16 (equal to the size longword of the freed hunk [D]) instead of the
  BPTR: `ramlib-v34.md` §2.2 corrected). The §8 rows themselves, observed without ramlib, stay valid for exec.
- **AL4** (separate boot with the argument `A`): dead-end alert, Guru `#81000003.00000000` shown on screen. The
  real ROM prints nothing on the serial port for it, so the harness's serial check of AL4 cannot be used as is on
  the real ROM (a screenshot is the oracle).
- For the probe (implementation side): the OL16 fake Open must not clobber A2 (it crashes 1.3); `check13`
  expectations for IO5, OD5's A0 and the D0 of CD1/RD1/CL1/RL1 must follow the rows above.

## 9. Probe to write on the implementation side (`tests/exec_msgio_probe.s`)

A CLI program (KS 1.x hunk executable, `vasmm68k_mot -Fhunkexe -kick1hunks`) that runs the vectors of §8 and prints one
line per vector through dos `Write` (its own hex routine; no RawDoFmt), `ML <id> <values in hex>`, ending with
`ML DONE`. The same program gives the oracle on the real ROM (through an analysis agent) and the result on ours. Run it
from a startup-sequence **without SetPatch**; under ramlib (any booted 1.3) OpenLibrary/OpenDevice/CloseLibrary/
CloseDevice/RemLibrary/RemDevice go through ramlib's replacements, which call exec's functions first: the vectors
below were chosen so that the result is the same (no disk load is triggered: every name is in memory, or the
not-found cases use names whose load fails quickly — print `IoErr()` too).

1. **Set-up**: AllocSignal a bit; build in a MEMF_PUBLIC|MEMF_CLEAR block: two ports, messages, an `Interrupt` node
   whose code increments a counter and records A1/A6 and the SR into a table, a routine for action 3 that records
   A0/A1/D0 and whether the message is already the list head, then loads four known values into D0/D1/A0/A1.
2. **Fake device** "msgio.device" (6 vectors) and **fake libraries** "msgio.library" (5 vectors, two nodes of the same
   name for OL13/OL15): each vector records its entry registers, **`ExecBase->IDNestCnt` and `TDNestCnt`** and the
   request bytes 20–31; its behaviour
   (what to put in D0, `io_Error`, `io_Flags`, whether to call `ReplyMsg`, which registers to clobber) is selected by a
   byte the probe sets before each call. Build the tables with `MakeLibrary` or by hand; use priorities that do not
   collide with the system ones; remove everything (Remove under Forbid) before exit.
3. **Register checks**: before each call load D2–D7, A2–A4 with markers; after the call compare and print the changed
   registers; compare D0/D1/A0/A1 only where §5.2 gives a value (the "changed/leak" cells are free on our side).
4. **Nest checks**: read IDNestCnt/TDNestCnt inside the vectors (OL18, OD1, CL1, RD1, RL1, IO1) and after each call;
   expected: 0 for TDNestCnt inside Open/Close/Expunge, −1 inside BeginIO/AbortIO, −1/−1 after every call.
5. **Ports** P1–P13, G1–G5, R1–R6, WP1–WP2, AP1–AP4 as in §8, reading `tc_SigRecvd` of `FindTask(0)` with
   `SetSignal(0, 0)`. P7 (crash) only when given the argument `CRASH`.
6. **Timer cases** WP3–WP4, IO4–IO5, WI4–WI5, AB2, CK10–CK11 with `timer.device` UNIT_VBLANK. The number of `Wait`
   calls cannot be read directly from a program: for WP4/WI5 set the bit with `SetSignal` before the call and check
   that it is clear afterwards and that the call still returned only after the timer fired (read `VBlank`-based time
   with TR_GETSYSTIME before and after: at least 100 ms elapsed).
7. **Checksum** AL2–AL3, SL1–SL5 on throw-away libraries; AL4 only with argument `CRASH` (dead-end alert).
8. **N1** only with argument `CRASH`.
9. Print for each vector the expected value from §8 next to the observed one, and `OK`/`DIFF`.

## Open points

1. **Action 3 of `mp_Flags`**: entry registers and the pass-through of D0/D1/A0/A1 were observed with a routine in
   user mode; whether the routine may change D2–D7/A2–A6 safely, and whether anything in 1.3 or in known software uses
   action 3, is unknown [S: nothing does].
2. **WaitPort/WaitIO on a reply port whose action is not PA_SIGNAL** (softint or ignore): they still Wait on
   `mp_SigBit` [D]; not run (it would hang the test task unless someone signals the bit).
3. **Library Open D0 = base**: observed on the fake library through exec's vector (no ramlib). Whether any 1.3 disk
   library reads D0 in its Open is unknown; passing the version instead would be a visible difference only to such a
   library.
4. **CloseDevice/AbortIO/DoIO with `io_Device` = 0 or −1**: not tried; expected to call through a bogus table [S].
5. **SumLibrary's Forbid/Disable use** was not watched; the alert path was seen only from AddLibrary (the same
   behaviour from SumLibrary itself is [D]).
6. **graphics.library 34 not counting its opens** (OL17) is a property of graphics' Open/Close, not of exec; the
   graphics specs did not mention it (noted in `graphics-display-v34.md` §1.8 since 2026-11-05).
7. `PutMsg` with `mp_SigBit` ≥ 32 behaves as bit modulo 32 (P5, P6); behaviour with an unallocated bit is just
   `Signal`'s.
8. ~~The probe of §9 has not been run on the real ROM.~~ Run 2026-11-10, §8a.

## Clean-room review

Review of 2026-11-05.

- [x] No 68000 instruction sequence of the ROM transcribed or paraphrased, no disassembly excerpt, no ROM routine or
  data address. The ROM code was not read: every fact comes from calls through the public library vectors with
  debugger-built inputs, from what the fake vectors saw at their entry, from watchpoint logs of the public
  IDNestCnt/TDNestCnt fields, and from the memory and registers read back.
- [x] The test scaffolding (two-NOP-and-return vector stubs, a six-instruction "clear IOF_QUICK and ReplyMsg" stand-in
  calling exec through `AbsExecBase`, the return trampoline) was written by the debugger into emulated RAM for the
  session only; it is generic, follows the public BeginIO contract, is not ROM content, and §9 describes the probe in
  words only.
- [x] The ordered effects of §1–§4 are observable effects at the public interfaces (fields written, vectors called with
  which registers, values returned), not a description of the ROM's internal structure.
- [x] The only numbers are LVOs, public structure offsets and constants, the public alert code `$81000003`, Guru
  `00000004`, register values and the inputs/outputs of our own test vectors (the RAM addresses of the test buffers
  are not given).
- [x] No probe code was written by the analysis track.
- [x] 2026-11-10 (§8a, OL16 note of §4.1): the existing implementation-side probe was assembled and run unchanged
  (one debugger patch turned its own A2-clobbering instruction into no-ops in RAM); its output buffer was read back.
  The OL16 crash was located with a per-instruction register trace whose program counters were only classified
  as ROM / RAM; no ROM code was read or disassembled, no address is recorded.
