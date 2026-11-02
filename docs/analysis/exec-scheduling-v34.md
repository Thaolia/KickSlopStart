# exec V34 scheduling, private LVOs and interrupt exit — behaviour spec

ANALYSIS track. Source: ROM `kick34005.A500` (exec 34.2), read-only, static reading with radare2, plus one
black-box Amiberry session on the real ROM (`--analysis`, insert-disk screen, ExecBase and task structures
read through gdb). No instruction listing, no ROM address. Offsets are public ABI offsets (`exec/execbase.i`,
`exec/tasks.i`, `exec/ports.i`, `exec/semaphores.i` V34) or offsets inside RAM structures.

Legend: **[S]** read statically in the ROM · **[M]** measured on the running real ROM · **[D]** deduced from
[S] (not executed) · **[P]** public documentation.

Related pages: [exec-spec.md](exec-spec.md) (ExecBase layout), [custom-chips-v34.md](custom-chips-v34.md) §3.1,
§3.3, §3.4, §4.3 (autovector dispatch, server chains, softints, RawIOInit/Debug: **not repeated here**, only
complemented in §8), [timer-v34.md](timer-v34.md) §1, §3 (the quantum tick), [coldstart-hardware-v34.md](coldstart-hardware-v34.md)
§4.4, §5 (KickMem/KickTag at reset).

---

## 0. Short answer

- Field/bit names used below: `SysFlags` (ExecBase `$124`, word): **SAR** = bit 15 (`$8000`, "reschedule
  pending"), **TQE** = bit 14 (`$4000`, "quantum elapsed"), **SINT** = bit 13 (`$2000`, "softint pending").
  Seen as the byte at `$124`, these are bits 7, 6 and 5. `IDNestCnt` (`$126`) and `TDNestCnt` (`$127`) are
  signed bytes, −1 = enabled / switching allowed; exec often reads and writes them **as one word**. [S]
- `tc_Flags` (`$0E`) bits used: `TF_EXCEPT` `$20` (bit 5), `TF_SWITCH` `$40` (bit 6), `TF_LAUNCH` `$80`
  (bit 7). `tc_State` (`$0F`): ADDED 1, RUN 2, READY 3, WAIT 4, REMOVED 6. [S][P]
- A task switch only happens when **SAR is set**. SAR is set by `Reschedule` (LVO −48) and by the idle loop of
  the dispatcher; it is cleared only by `Schedule`. **TQE never causes a switch on its own** (§2.3). [S]
- Preemption rule (in `Schedule`): the head of `TaskReady` replaces the running task when its priority is
  **greater than or equal to** the running task's priority. Equal priority therefore preempts. [S]
- The task context is 66 bytes (`$42`) on the task's **user** stack, `tc_SPReg` pointing at it: PC (long),
  SR (word), D0-D7, A0-A6 (§4). [S][M]
- `Exception` is not an entry point anyone calls: it is an internal step of the dispatcher, entered when the
  dispatched task has `TF_EXCEPT` (§5). [S]
- `Procure`/`Vacate` implement the **old message-based `Semaphore`** (a `MsgPort` plus `sm_Bids`), not the 2.0
  `SignalSemaphore` form (§6). `SumKickData` = additive 32-bit sum starting at `$FFFFFFFF` over the KickMem
  MemLists and the KickTag **pointers** (§7).

---

## 1. Who reaches what (call graph through the jump table)

Which callers go **through the LVO vector** (so a `SetFunction` on that LVO intercepts them) and which jump
**directly** into the ROM body (not interceptable). [S]

| LVO | Name | Reached through its vector by | Reached directly (bypassing the vector) by |
|---:|---|---|---|
| −30 | `Supervisor` | `Wait`, `Permit`, `Reschedule`, `RemTask` (self), `Debug`, the exception-return path (§5) | — |
| −36 | `ExitIntr` | every level 1-6 autovector handler: the address **of the jump-table entry** is pushed as the handler's return address; the level-4 re-check loop also leaves through it | — |
| −42 | `Schedule` | `Permit`, `Reschedule` (both only when the caller was in user mode) | `ExitIntr` (continues into the body of Schedule, registers already saved) |
| −48 | `Reschedule` | `Signal`, `SetSignal`/`SetExcept` (exception path), `SetTaskPri`, `AddTask` | — |
| −54 | `Switch` | `Wait` (via `Supervisor` with A5 = the jump-table entry itself), `Schedule` (reads the vector's address field and returns into it) | — |
| −60 | `Dispatch` | `RemTask` of the running task | `Switch` falls through into the dispatcher body: **a SetFunction on −60 does not see normal switches** |
| −66 | `Exception` | nobody | the dispatcher (subroutine call), §5 |

Consequences for programs that patch these vectors [D]:
- Patching **−54** catches every voluntary (Wait) and involuntary (Schedule) switch-out.
- Patching **−60** catches only "running task removed itself"; a task monitor that wants every dispatch must
  use `tc_Launch`, or patch −54 and follow what happens after it.
- Patching **−42** misses all interrupt-exit preemptions (the common case).
- Patching **−36** is effective at once for all levels 1-6 (the pushed return address is the vector).
- Patching **−66** has no effect.
- `Supervisor` must stay where the privilege-violation handler expects it: from user mode, `Supervisor` works by
  deliberately raising a privilege violation, and the handler recognises it by comparing the faulting PC with
  the ROM's own `Supervisor` entry (two variants: 68000 and 68010 frame). A `Supervisor` replaced in RAM and
  called from user mode ends in a real privilege-violation Guru (`$00000008`). [S][D]
- SetPatch 1.38 patches none of these LVOs ([setpatch-138.md](setpatch-138.md) §1). [S]

---

## 2. The scheduling primitives

### 2.1 `Reschedule` (−48) [S]

Entry: A6 = ExecBase. No arguments, no result (D0 destroyed). Effects, in order:
1. Set SAR, remembering whether it was already set.
2. If `TDNestCnt` ≥ 0 (Forbid): return. SAR stays set; the switch happens at the next `Permit` that brings the
   count back to −1, or at the next interrupt exit after that.
3. If `IDNestCnt` < 0 (interrupts enabled): enter supervisor through `Supervisor`; if the caller was already in
   supervisor mode (interrupt code, Supervisor code), return at once (RTE) — the switch will be made by
   `ExitIntr`; otherwise go to `Schedule` through its vector.
4. If interrupts are disabled: when SAR was **not** already set, post a software interrupt (INTREQ `$8004`),
   so that the switch happens as soon as `Enable` lets the level-1 interrupt in (its exit runs `ExitIntr`).
   When SAR was already set, nothing more.

### 2.2 `Schedule` (−42) [S]

Entry contract: supervisor mode, the system stack holds an **exception frame** (SR word, PC long) describing the
code to return to, all registers = the values of that code. A6 need not be ExecBase.

1. Save D0/D1/A0/A1/A5/A6 on the system stack (the same 24-byte block the autovector handlers save; `ExitIntr`
   joins here with it already saved). Raise to IPL 7.
2. Clear SAR.
3. If the running task (`ThisTask`) has `TF_EXCEPT`: go to step 6 whatever the ready list contains.
4. If `TaskReady` is empty: restore, RTE.
5. Compare the head of `TaskReady` with `ThisTask` (signed `LN_PRI`):
   - head priority **≥** running priority → step 6;
   - head priority lower: if TQE is set → step 6, otherwise restore, RTE.
6. `Enqueue` `ThisTask` on `TaskReady` (priority order, after tasks of equal priority), set its state READY,
   back to IPL 0 (SR `$2000`), restore D0/D1/A0/A1/A5 and A6, and continue in `Switch` (through the −54 vector)
   with only the exception frame left on the system stack.

Note on step 5 [D]: when the head has a lower priority and TQE is set, the running task is enqueued **ahead**
of it (higher priority) and immediately re-dispatched. The only effects are `DispCount`+1, `Elapsed` reloaded,
TQE cleared and the `tc_Switch`/`tc_Launch` hooks called.

### 2.3 Time slicing in V34 [S][D]

- `Quantum` and `Elapsed` are set to 16 by timer.device init; its VERTB server decrements `Elapsed` and, at 0,
  reloads it from `Quantum` and sets TQE ([timer-v34.md](timer-v34.md)). exec never decrements `Elapsed`; the
  dispatcher reloads it (`Elapsed := Quantum`) and clears TQE on every dispatch.
- Nothing sets SAR when TQE becomes set, and `ExitIntr` tests SAR only. So **TQE alone never preempts**. With
  the ≥ rule of §2.2, TQE only matters when a lower-priority task is at the head, where it changes nothing
  visible (note above).
- Round-robin between equal-priority CPU-bound tasks happens as a side effect of preemptions: when a
  higher-priority task wakes (e.g. input.device, trackdisk), the running task is re-enqueued **behind** the
  ready tasks of its own priority; when the high-priority task waits again, the dispatcher takes the next one.
  Also, SAR left set by the idle loop (§2.5) causes one schedule check at the next interrupt exit to user
  mode.
- Measured on the real ROM at the insert-disk screen [M]: `Quantum` = `$0010`, `Elapsed` counting down
  (`$000C`, then `$0010`), `SysFlags` = 0, `IDNestCnt`/`TDNestCnt` = −1/−1, `IdleCount` 13, `DispCount` 251 then
  395 a few seconds later.
- Open point: a probe (§10) should confirm on hardware that two busy-looping tasks of equal priority do not
  alternate when nothing else runs.

### 2.4 `Switch` (−54) [S]

Entry contract: supervisor mode; system stack top = SR (word) then PC (long) of the outgoing task (exception
frame shape, as left by a trap, an interrupt, or `Supervisor`); D0-D7/A0-A6 = the outgoing task's registers;
USP = its stack. `ThisTask` = the outgoing task, **already** placed on `TaskReady` or `TaskWait` by the caller
with its state set. Never returns to the caller.

Order of effects:
1. IPL 0 (SR `$2000`).
2. Push D0-D7/A0-A6 on the **user** stack (A5's real value is preserved), then move the SR and PC of the
   system-stack frame below them on the user stack: the 66-byte context of §4. The frame is popped from the
   system stack.
3. Save ExecBase's `IDNestCnt`/`TDNestCnt` word into the task's `tc_IDNestCnt`/`tc_TDNestCnt` (`$10`/`$11`),
   then set ExecBase's word to `$FFFF` (both −1) and write INTENA `$C000` (master on).
4. `tc_SPReg` (`$36`) := address of the context.
5. If `TF_SWITCH`: call `tc_Switch` (`$42`) as a subroutine (§3).
6. Continue into the dispatcher (§2.5).

On 68000 systems with a 68881 (AttnFlags bit 4) the coldstart replaces the −54 and −60 vectors by variants that
also save/restore the FPU state; irrelevant to an A500 [S]. On a 68010 the CPU's format word is not part of the
saved context (the variant handling is outside the A500 scope).

### 2.5 `Dispatch` (−60) and the dispatcher loop [S]

Entry through the vector (RemTask of self): supervisor mode, nothing to save. First sets the ExecBase
nest-count word to `$FFFF` and INTENA `$C000`, then joins the loop that `Switch` falls into:

1. IPL 7. If `TaskReady` is empty: `IdleCount` + 1, set SAR, `STOP` with SR `$2000` (supervisor, IPL 0), and
   repeat step 1 after the interrupt. Interrupts taken here return without scheduling (`ExitIntr` sees
   supervisor mode). `IdleCount` therefore counts idle wake-ups, not time. `ThisTask` keeps pointing at the
   last task during idle, even if that task was just removed and its memory freed.
2. Remove the head of `TaskReady`; `DispCount` + 1; `ThisTask` := it; `Elapsed` := `Quantum`; clear TQE;
   state := RUN; ExecBase `IDNestCnt`/`TDNestCnt` := the task's saved word; if the task's `IDNestCnt` ≥ 0,
   INTENA `$4000` (master off).
3. IPL 0 (SR `$2000`).
4. If `TF_LAUNCH`: call `tc_Launch` (`$46`) (§3). Then, if `TF_EXCEPT`: run the exception step (§5).
5. Restore the context from `tc_SPReg`: USP := `tc_SPReg + $42`, registers reloaded, RTE with the saved SR and
   PC.

SAR is **not** cleared by the dispatcher.

### 2.6 `ExitIntr` (−36) [S]

Entry contract (the autovector handlers' frame): system stack = D0, D1, A0, A1, A5, A6 (24 bytes, D0 at +0,
A6 at +20), then the interrupt frame: SR at +24, PC at +26.

1. If the interrupted code was in **supervisor** mode (S bit of the stacked SR): restore the 6 registers, RTE.
2. A6 := ExecBase (from address 4). If `TDNestCnt` ≥ 0: restore, RTE.
3. If SAR is clear: restore, RTE.
4. Otherwise IPL 0 and continue in `Schedule` at its step 1-after-save (§2.2), the 6 registers being already on
   the stack.

`IDNestCnt` is not tested (an interrupt cannot normally reach here while the interrupted task is disabled).
Level 7 (NMI) does not use `ExitIntr`.

### 2.7 The other callers [S]

| Function | Scheduling behaviour |
|---|---|
| `Forbid` (−132) | `TDNestCnt` + 1, nothing else. |
| `Permit` (−138) | `TDNestCnt` − 1. If now ≥ 0, or `IDNestCnt` ≥ 0, or SAR clear: return. Otherwise `Supervisor`; caller in supervisor mode → plain return; caller in user mode → `Schedule` via its vector. |
| `Disable` (−120) | INTENA `$4000` **then** `IDNestCnt` + 1. |
| `Enable` (−126) | `IDNestCnt` − 1; if < 0, INTENA `$C000`. **Never schedules directly**: a pending switch arrives through the software interrupt posted by `Reschedule` (§2.1) or at the next interrupt exit. |
| `Wait(D0)` (−318) | `tc_SigWait` := D0; Disable; loop: if `tc_SigRecvd AND tc_SigWait` = 0 → state WAIT, append to `TaskWait` (tail), switch through `Supervisor` + the −54 vector, then re-read the mask and retest. When satisfied: clear the matched bits in `tc_SigRecvd`, Enable, return them in D0. **Forbid is not tested**: Wait under Forbid or Disable switches anyway, the counts being saved per task. A task suspended in Wait has `tc_IDNestCnt` = 0 (Wait's own Disable) [S][M]. `Wait(0)` sleeps until an exception signal arrives. |
| `Signal(A1 task, D0 sigs)` (−324) | Disable; `tc_SigRecvd` OR= D0. If `D0 AND tc_SigExcept` ≠ 0: set `TF_EXCEPT`; if the task is WAITing, wake it (below) **whatever tc_SigWait is**; otherwise Enable and `Reschedule`. Else if state = WAIT and `D0 AND tc_SigWait` ≠ 0 (only the **new** bits count): remove from `TaskWait`, state READY, `Enqueue` on `TaskReady`; if it is now the head, Enable then `Reschedule` (tail call); otherwise Enable, return. D0 on return = the previous `tc_SigRecvd` (undocumented). |
| `SetSignal(D0 new, D1 mask)` (−306) / `SetExcept` (−312) | Disable, update `tc_SigRecvd` / `tc_SigExcept` of `ThisTask` under the mask, return the old value in D0; then the same "exception pending?" test as Signal on the current received set → `TF_EXCEPT` + `Reschedule`. |
| `SetTaskPri(A1, D0)` (−300) | Disable; store the new `LN_PRI`; if the task is `ThisTask` → `Reschedule`; else if READY → re-`Enqueue`, and `Reschedule` if it became the head; Enable. Returns the old priority **zero-extended** (e.g. −1 → `$000000FF`). `SetTaskPri(FindTask(0), same)` yields to ready tasks of equal priority (§2.2 ≥ rule). |
| `AddTask(A1, A2 initPC, A3 finalPC)` (−282) | Initialises the task (§4.2), Disable, state READY, `Enqueue` on `TaskReady`, Enable; if the task is now the head → `Reschedule`. A new task of the **same** priority as the caller runs at once only if no other task of that priority is ready. D0 on return = the head of `TaskReady` (not "the task" as in 2.0). |
| `RemTask(A1)` (−288) | A1 = 0 → `ThisTask`. Another task: Disable, `Remove` from its list, Enable. State := REMOVED (6). Self: `Forbid`. Then `FreeEntry` on each `tc_MemEntry` node. Self: enter supervisor, drop the frame, `Dispatch` via −60 (no context saved, `tc_Switch` **not** called). Otherwise D0 = 0. |

Interrupt code that calls `Signal`/`Cause` only sets SAR (step 3 of §2.1 returns at once): the switch is made by
`ExitIntr` when the interrupt returns to user mode with `TDNestCnt` < 0.

---

## 3. `tc_Switch` and `tc_Launch` hooks [S]

| | `tc_Switch` (`$42`), when `TF_SWITCH` | `tc_Launch` (`$46`), when `TF_LAUNCH` |
|---|---|---|
| When | the task loses the CPU through `Switch` (Wait, preemption); context already saved, `tc_SPReg` up to date; **not** called for RemTask(self) | every time the task is dispatched, after it became `ThisTask` and its nest counts were loaded, **before** its exception (if any) and before its context is restored |
| Mode | supervisor, IPL 0, called with JSR, system stack | same |
| Interrupts | enabled (exec just set INTENA `$C000`, nest counts −1/−1) | as the task's saved `IDNestCnt` says |
| Registers in | A3 = task, A6 = ExecBase | A3 = task, A6 = ExecBase, D0 = `tc_Flags` |
| Must preserve | A4, A6 (used by exec afterwards); D0-D3/A0-A3/A5 free | D2, A3, A4, A6 |
| Return | RTS, no result | RTS, no result |

The task's own registers are not in the CPU registers during the hooks; they are in the saved context (§4).

---

## 4. Task context layout

### 4.1 Saved context (68000, no FPU) [S][M]

`tc_SPReg` points at the lowest byte. Offsets from `tc_SPReg`:

| Offset | Size | Content |
|---:|---|---|
| `+$00` | long | PC to resume at |
| `+$04` | word | SR to resume with (normally user mode) |
| `+$06` | 8 longs | D0 … D7 (D0 at `+$06`, D7 at `+$22`) |
| `+$26` | 7 longs | A0 … A6 (A0 at `+$26`, A5 at `+$3A`, A6 at `+$3E`) |
| `+$42` | — | the task's stack pointer value at the moment of the switch (USP restored = `tc_SPReg + $42`) |

The system stack holds nothing for a switched-out task. On a 68881 system an extra long (FPU state marker)
sits below the PC and everything above shifts by 4 [S]; not on an A500.

Measured on the real ROM [M] (trackdisk.device task, waiting at the insert-disk screen): `tc_State` 4,
`tc_IDNestCnt` 0, `tc_TDNestCnt` −1; at `tc_SPReg`: PC = a return stub inside exec's `Supervisor` path (ROM),
SR = `$0010` (user mode, IPL 0), A6 slot = ExecBase, and the long at `+$42` = a return address inside `Wait`.
A task switched by an interrupt instead shows the interrupted PC and SR.

What third-party task monitors and debuggers rely on [D]: `tc_SPReg` → PC at `+0` (where the task sleeps) and
SR at `+4`; the 15 registers at `+6`; `tc_SPReg` compared with `tc_SPLower`/`tc_SPUpper` for stack checks;
`ThisTask`, `TaskReady`/`TaskWait` membership and `tc_State`; `DispCount`/`IdleCount` for CPU-load meters. A
reimplementation must keep this layout and keep the context on the user stack.

### 4.2 Initial context built by `AddTask` [S]

Field initialisation: `tc_State` := ADDED then READY, `tc_Flags` := 0, `tc_IDNestCnt`/`tc_TDNestCnt` := −1/−1,
`tc_SigAlloc` := ExecBase `TaskSigAlloc`, `tc_SigWait`/`tc_SigRecvd`/`tc_SigExcept` := 0, `tc_TrapAlloc` :=
`TaskTrapAlloc`, `tc_TrapAble` := 0, `tc_TrapCode` := `TaskTrapCode` if 0, `tc_ExceptCode` := `TaskExceptCode`
if 0. `tc_Switch`/`tc_Launch`/`tc_ExceptData`/`tc_MemEntry` are not touched (caller's responsibility).

Stack, built downward from the caller-supplied `tc_SPReg` (not `tc_SPUpper`): the final PC (A3, or
`TaskExitCode` when A3 = 0), then 15 zero longs, a zero SR word, the initial PC (A2) — i.e. exactly the §4.1
layout with all registers 0 (A6 included), SR = 0 (user mode, IPL 0), and the final PC sitting at `+$42` as the
return address of the task's code. `tc_SPReg` := the new lowest address.

---

## 5. Exception processing (`tc_ExceptCode`) [S]

Triggered at dispatch (§2.5 step 4) when `TF_EXCEPT` is set. `Signal`/`SetExcept`/`SetSignal` set the flag;
`Schedule` forces a switch of the running task when it carries the flag (§2.2 step 3), so a task signalling
itself with an exception signal gets its handler at once if switching is allowed.

Order of effects:
1. Clear `TF_EXCEPT`.
2. Under a Disable: `sigs := tc_SigRecvd AND tc_SigExcept`; those bits are removed from **both** `tc_SigExcept`
   and `tc_SigRecvd`.
3. Push on the task's user stack (below its saved context) the long at `tc_Flags` (`tc_Flags`, `tc_State`,
   `tc_IDNestCnt`, `tc_TDNestCnt`), then a return address into exec.
4. If ExecBase `IDNestCnt` is exactly 0 (typical: the task was suspended inside `Wait`), set it to −1 and write
   INTENA `$C000`, so the handler runs with interrupts enabled. A positive count is left as is.
5. Enter `tc_ExceptCode` (`$2A`) **in user mode**, SR = `$0000`, with:
   - D0 = `sigs` (the signals that caused the exception), A1 = `tc_ExceptData` (`$26`), A6 = ExecBase;
   - other registers undefined (they are **not** the task's registers);
   - USP = `tc_SPReg − 8` (return address on top, then the 4 saved bytes).
6. The handler returns with RTS; D0 = signal mask to **re-arm**: it is ORed into `tc_SigExcept`. No register
   needs to be preserved.
7. exec re-enters supervisor (through `Supervisor`), pops the 4 bytes back into `tc_Flags`/`tc_State`/nest counts,
   sets `tc_SPReg` back to the context, reloads ExecBase's nest counts from the task (INTENA `$4000` if
   `IDNestCnt` ≥ 0), and resumes the saved context.

Edge cases [D]:
- Restoring `tc_Flags` at step 7 overwrites a `TF_EXCEPT` set by a new exception signal during the handler,
  unless a switch happened meanwhile (then the handler itself was preempted and the nested exception was taken
  at its re-dispatch). Signal bits are never lost: they stay in `tc_SigRecvd`.
- A Waiting task woken only by an exception signal returns to `Wait`, retests its wait mask, and sleeps again.
- `TDNestCnt` is not changed: a handler of a task that was in Forbid runs forbidden.
- On a 68010, a format word is added to the frame used to enter the handler (not on an A500).

---

## 6. `Procure` (−540) / `Vacate` (−546): V34 message semaphore [S]

V34 structure (`exec/semaphores.i`, old form): `struct Semaphore` = `MsgPort` (34 bytes) + `sm_Bids` (WORD at
`$22`); `sm_LockMsg` is the port's `mp_SigTask` field (`$10`).

**`Procure(A0 semaphore, A1 bidMessage) → D0`**
- `sm_Bids` + 1. If the result is **0** (it was −1: free): `sm_LockMsg` := A1, return **D0 = 1** (owned at once,
  the message is not queued).
- Otherwise `PutMsg(semaphore, A1)` (the bid queues on the port), return **D0 = 0**.
- No Forbid/Disable around the increment: the caller provides the atomicity it needs (single 68000
  read-modify-write).

**`Vacate(A0 semaphore)`**
- `sm_LockMsg` := 0; `sm_Bids` − 1. If the result is < 0: return (free).
- Otherwise `GetMsg(semaphore)` → the next bid; `sm_LockMsg` := it; if non-NULL, `ReplyMsg` it: the bidder learns
  through its reply port that it now owns the semaphore. D0 undefined.

Required set-up by the user (no V34 init function for this form) [D][P]: `sm_Bids` := −1, the port's message list
initialised, and `mp_Flags` = `PA_IGNORE` — with `PA_SIGNAL`, `PutMsg` would signal "the task" stored in
`mp_SigTask`, which here is the lock message. This has nothing in common with the 2.0+ `Procure` (which takes a
`SignalSemaphore` and a `SemaphoreMessage`).

Test vectors [D]: fresh semaphore (`sm_Bids` −1): Procure(m1) → 1, `sm_LockMsg` = m1, `sm_Bids` 0.
Procure(m2) → 0, `sm_Bids` 1, m2 queued. Vacate → m2 replied, `sm_LockMsg` = m2, `sm_Bids` 0. Vacate →
`sm_LockMsg` 0, `sm_Bids` −1.

---

## 7. `SumKickData` (−612) [S]

Entry A6 = ExecBase; result in D0; D1/A0 destroyed.

1. `KickMemPtr` (`$222`) and `KickTagPtr` (`$226`) are read, both fields are **zeroed during the computation**,
   and written back unchanged at the end.
2. Sum := `$FFFFFFFF`, 32-bit addition with carries discarded.
3. For each `MemList` of the `KickMemPtr` chain (linked through its `LN_SUCC`, end at 0): add the
   `2 × ml_NumEntries + 4` longs starting at the MemList, i.e. the whole structure: Node header and
   `ml_NumEntries` (4 longs, the `LN_SUCC` link included) plus every `MemEntry` (2 longs each).
4. Walk the `KickTagPtr` table of longs: 0 = end; bit 31 clear = a ROMTag pointer, **the pointer value** is added
   (the ROMTag contents are not summed); bit 31 set = link: continue at that address with bit 31 cleared (the
   link long is not added).
5. Return the sum.

Use at reset (coldstart, after the ROM residents were collected) [S]: the KickMem/KickTag data are honoured only
if `SumKickData()` equals `KickCheckSum` (`$22A`, full 32 bits). Then every `MemEntry` of every KickMem MemList
is claimed with `AllocAbs(me_Length, me_Addr)`; if any claim fails, the KickTag residents are **not** added.
Otherwise each KickTag ROMTag is merged into the resident list by name: an existing resident of the same name
is replaced when the new `rt_Version` is higher, or equal with `rt_Pri` ≥ the old one; a lower version, or same
version and lower priority, is ignored. Software that installs reset-proof code sets the two pointers and then
`KickCheckSum := SumKickData()`.

Test vectors [D]: both pointers 0 → `$FFFFFFFF`. KickTagPtr → table {P, 0} → `$FFFFFFFF + P`. KickTagPtr →
{P, `$80000000 | T2`} with T2 → {Q, 0} → `$FFFFFFFF + P + Q`. One MemList with 1 entry → `$FFFFFFFF` + the
sum of its 6 longs.

---

## 8. Interrupt dispatch — complements to custom-chips-v34 §3.3/§3.4

All of custom-chips-v34 §3.3 was re-checked and is confirmed (orders per level, one source per entry except the
level-4 loop, INTEN test, server chain header, softints, `SetIntVector(NULL)` = −1/−1, `RemIntServer` wrong-bit
bug). Additional contract details [S]:

- **Registers at `iv_Code` entry (levels 1-6)**: A0 = `$DFF000`, A1 = `iv_Data`, A5 = `iv_Code`, A6 = ExecBase,
  D1 = INTENAR AND INTREQR as read at entry (all levels' bits, not only this level's), D0 = scratch. The handler
  is entered by a jump with the return address on the stack (the `ExitIntr` jump-table entry, or the level-4
  loop), so it ends with RTS. It may destroy D0/D1/A0/A1/A5/A6 (saved by the level handler) and must preserve
  D2-D7/A2-A4. Below the return address: the 24-byte register block and the interrupt frame (§2.6).
- **Unclaimed / spurious**: INTEN clear at entry, or no pending-and-enabled source of the level → registers
  restored and RTE **directly**, not through `ExitIntr` (no schedule check). Nothing is acknowledged.
- **Level 6, `IntVects[14]`**: tested before EXTER, against INTREQR bit 14. Whether Paula ever reports bit 14
  in INTREQR (a CPU write of INTREQ `$C000`) is not verified here.
- **Level 7**: no INTENAR/INTREQR read, `IntVects[15].iv_Code` called by JSR with A1 = `iv_Data`, A5 =
  `iv_Code`, A6 = ExecBase (A0 not loaded), then RTE. Must return with RTS.
- **Server dispatcher (PORTS, VERTB, COPER, EXTER, NMI)**: the acknowledge word (header `+$12`) is read **before**
  the chain and written to INTREQ once **after** it (VERTB: `$0020` after all VERTB servers). Each server is
  called with A1 = `is_Data`, A5 = `is_Code`; A0, A6 and D1 are **not reloaded** between servers (only the first
  server is guaranteed A0 = `$DFF000`, A6 = ExecBase, D1 = pending mask); D0 at server entry is non-zero
  garbage. The dispatcher walks the list with A2: **a server must preserve A2** (and D2-D7/A3/A4). The
  continue/stop test is the **Z flag** of the condition codes on return (Z set = continue, Z clear = stop),
  not an explicit test of D0. An implementation should test the flags the same way.
- **Server chain header (`iv_Data`, 22 bytes)**: `List` (14), CLR mask `1<<n`, SET mask `$8000|1<<n`,
  acknowledge word, spare word 0 (custom-chips §3.3). Built by the coldstart in one 110-byte
  `MEMF_PUBLIC|MEMF_CLEAR` block for PORTS, VERTB, COPER, EXTER, NMI (allocation failure: Alert `$81000006`).
  `AddIntServer` assumes `iv_Data` is such a list: called on a non-chain number (e.g. BLIT, whose `iv_Data` is
  GfxBase) it would `Enqueue` into foreign memory.
- **`AddIntServer(D0 n, A1)`**: under Disable, `Enqueue` (priority, FIFO among equals), then INTENA
  `$8000 | 1<<n` on every call (even if the chain was not empty). `RemIntServer`: under Disable, `Remove`, then
  if the chain is empty the wrong-bit INTENA clear (custom-chips §3.1).
- **`SetIntVector(D0 n, A1)` → D0 old node**: under Disable; `iv_Node` := A1; `iv_Data`/`iv_Code` :=
  `is_Data`/`is_Code`, or `$FFFFFFFF`/`$FFFFFFFF` when A1 = NULL. INTENA untouched. A source left enabled with a
  NULL vector makes the CPU jump to an odd address (address-error Guru). Vectors never set have `iv_Code` = 0
  (ExecBase zeroed at coldstart).
- **Softint call contract**: supervisor, SR `$2000` (IPL 0: every hardware level, including level 1, can nest
  over a software interrupt; the SOFTINT source itself is disabled in INTENA meanwhile), JSR with A1 =
  `is_Data`, A5 = `is_Code`; the node's `LN_TYPE` is reset to `NT_INTERRUPT` (2) **before** the call, so the
  code may `Cause` itself again. A6 = ExecBase and **must be preserved** (the dispatcher re-scans the queues
  through it). After each call the scan restarts from the highest-priority queue.
- **`Cause` priority mapping**: queue offset = `(LN_PRI AND $F0)` sign-extended as a byte, relative to the middle
  queue: −32, −16, 0, +16, +32 → the five queues; priorities 1..15 → 0, −1..−15 → −16, −17..−31 → −32,
  17..31 → +16. Priorities ≥ 48 or ≤ −33 index **outside** the `SoftInts` array (ExecBase corruption): only the
  five documented values are safe.
- **Reschedule through SOFTINT**: when the softint vector finds SINT clear it returns at once; the useful work is
  done by `ExitIntr`, reached as the level-1 handler's return address.

---

## 9. `Debug` (−114) and `RawIOInit` (−504) — complements to custom-chips §4.3 [S]

- `RawIOInit`: writes SERPER `$0174` only; no other register, no return value (D0 unchanged). Called by the
  coldstart (through ROM-Wack's initialisation), by `Debug` on each entry and by the serial path of `Alert`.
- Coldstart set-up of ROM-Wack: its work area is the low-memory block **`$200`-`$2EB`** (236 bytes, cleared at
  every cold and warm start); ExecBase `DebugEntry` (`$42`) := ROM-Wack's exception entry; the −114 vector is
  (re)written to `Debug`. Low memory `$200`-`$2EB` therefore belongs to exec in V34.
- `Debug()` from user or supervisor mode: enters supervisor through `Supervisor`, pushes a "reason" long 0,
  checks that the system stack is writable (if not, switches to a stack at `$40000`), saves all registers, saves
  INTENAR and writes INTENA `$0801` (TBE and RBF off), runs `RawIOInit`, prints a banner (`rom-wack`, preceded by
  a line feed) and runs the polled serial monitor. The session installs its own TRAP #15 (vector `$BC`,
  breakpoints) and trace (vector `$24`) handlers. On resume the registers (possibly edited) are restored and it
  returns to the caller of `Debug` with RTE, all registers preserved.
- The INTENA "restore" at exit writes the saved value masked to TBE/RBF **without** the SET bit, so it cannot
  re-enable them [D]: after a Debug session, TBE and RBF interrupts stay disabled (the ROM never uses them).
  custom-chips §4.3 says "restores INTENA on exit"; this is the precise effect.

---

## 10. Probes that would refine this page (described, not written)

1. **Equal-priority time slicing**: on the real ROM, from a CLI at pri 0, `Forbid`, create two tasks at pri −1
   that each increment their own counter in a tight loop, lower the CLI below them, `Permit`, wait ~5 s using
   a timer at a higher priority (or busy-wait elsewhere), then print both counters. Prediction (§2.3): with no
   higher-priority wake-ups only one counter advances; with the mouse moving (input.device wakes) both advance.
2. **≥ preemption**: from a pri-0 task, `AddTask` a pri-0 task that sets a flag; check the flag immediately after
   `AddTask` returns (prediction: already set when no other pri-0 task is ready).
3. **Exception delivery**: a task with `tc_ExceptCode` recording D0, A1, SR and USP − `tc_SPReg`, and returning a
   mask; another task signals it while it Waits on an unrelated signal. Prediction: D0 = the signal, A1 =
   `tc_ExceptData`, SR = 0, USP = `tc_SPReg` − 8, the returned mask re-armed in `tc_SigExcept`.
4. **Server Z-flag rule**: a VERTB server at high priority returning D0 = 0 with the Z flag clear; prediction: the
   lower-priority VERTB servers (graphics, timer) stop running.
5. **Procure/Vacate** test vectors of §6 on a hand-built V34 semaphore.

## Open points

- §2.3 (no time slicing by quantum alone) is a static deduction; probe 1 should confirm it.
- INTREQR bit 14 / level-6 `IntVects[14]` reachability on real Paula (§8).
- The ROM-Wack command set is out of scope (not used by software we target).

## Clean-room review

Review of 2026-11-02 (author check).

- [x] No 68000 instruction sequence transcribed or paraphrased line by line; behaviour is given as ordered
  effects, entry/exit contracts and ABI layouts.
- [x] No ROM routine or data address, no offset inside the ROM. Addresses present: public ExecBase/Task/MsgPort
  field offsets, custom registers (`$DFFxxx`), 68000 exception vectors (`$24`, `$BC`), low-memory work area
  `$200`-`$2EB` and the fallback stack `$40000` (RAM, behaviour), Alert code `$81000006`.
- [x] The context and server-header layouts are ABI-level data layouts, not code.
- [x] Session `schedA` (real ROM, `--analysis`) stayed under `build/amiberry/analysis/`; nothing in `src/`,
  `tests/` or scripts was read or written.
