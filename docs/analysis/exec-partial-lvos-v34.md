# exec-partial-lvos-v34.md — exec 34.2: the last partly specified LVOs

> **ANALYSIS** track ("dirty"). Written 2026-11-10 for REMAINING-WORK D7. Sources: **static reading** of the exec
> vector bodies of `kick34005.A500` (radare2, read only), plus a few **black-box calls** made on the real ROM under
> Amiberry (A500, cycle-exact) by setting registers and the PC from the debugger in a task context and stepping
> until the return address. No program was written; the probe to write on the implementation side is in §8.
> This page describes **behaviours**, **registers**, **orders of effects** and **ABI layouts**. It contains no
> ROM instruction sequence, no routine address and no transcription of a routine.
>
> **Levels of proof**: **[R]** read in the ROM code (static) · **[O]** observed by a black-box call on the real
> ROM · **[D]** deduced from [R]/[O] facts or from other analysis pages (cited) · **[S]** assumption.
>
> Covered: `Supervisor` −30, `InitStruct` −78, `MakeLibrary` −84, `MakeFunctions` −90, `FindResident` −96,
> `SetSR` −144, `SuperState` −150, `UserState` −156, `Insert` −234, `RemHead` −258, `RemTail` −264, `FindTask`
> −294, `AllocSignal` −330, `FreeSignal` −336, `AllocTrap` −342, `FreeTrap` −348, `SetFunction` −420, `GetCC`
> −528. Neighbouring pages: `exec-spec.md` (ExecBase layout), `exec-scheduling-v34.md` (§1 call graph, privilege
> violation path), `exec-messages-io-v34.md` §4.4 (SumLibrary), `exec-memory-semaphores-v34.md` (AllocMem/FreeMem
> registers and size-0 rules), `module-map.md` (auto-init tables), `setpatch-138.md` §1.5–§1.6 (SetPatch
> replacements of UserState and FindName).
>
> Task structure offsets used below are the public ones (`exec/tasks.i`): `tc_SigAlloc` +$12, `tc_SigWait`
> +$16, `tc_SigRecvd` +$1A, `tc_SigExcept` +$1E, `tc_TrapAlloc` +$22 (UWORD), `tc_TrapAble` +$24. ExecBase:
> `ThisTask` +$114, `AttnFlags` +$128, `ResModules` +$12C, `TaskSigAlloc` +$13C, `TaskTrapAlloc` +$140.

## 0. Summary for the implementer (what an AutoDoc-based clone gets wrong)

1. **Bit numbers are taken modulo 32 and only the low byte is tested for −1** in AllocSignal/AllocTrap; FreeSignal
   and FreeTrap have **no −1 test at all**: `FreeSignal(-1)` **frees signal 31**. [R]
2. **AllocSignal(n)/AllocTrap(n) return D0 exactly as passed** on success (no normalisation): `AllocSignal(48)`
   allocates bit 16 and returns 48. [R]
3. **AllocTrap(16…31) depends on the caller's D1**: the trap mask is a word, but the bit is set in a 32-bit register
   whose upper half is the caller's D1. With that D1 bit clear the call "succeeds" and returns n **without
   allocating anything**; with it set, it returns −1. FreeTrap(16…31) does nothing. [R]
4. **AllocSignal(−1) gives 31 first, then 30, … down to 0** (any free bit, the low 16 included if a program freed
   them); **AllocTrap(−1) gives 14 first** (trap 15 is reserved by `TaskTrapAlloc = $8000`). AddTask overwrites
   `tc_SigAlloc` with `$0000FFFF` and `tc_TrapAlloc` with `$8000`. [R]
5. A successful AllocSignal **clears the bit in tc_SigRecvd, tc_SigExcept and tc_SigWait**. [R]
6. **GetCC returns `SR & $00FF` in the low word of D0 and leaves the upper word of D0 untouched.** [O]
7. **SetSR returns the whole old SR** (S, T and the interrupt mask included, upper word 0), computes
   `new SR = (old & ~mask) | (newSR & mask)` and leaves **D1 = mask with its low word complemented**. Changing the S
   bit through SetSR returns on the wrong stack (crash); 1.3 does not guard it. [R]
8. **SuperState from supervisor mode returns 0 and changes nothing**; from user mode it returns the **system stack
   pointer as it was before the call** and continues in supervisor mode **on the user stack** (interrupts then
   push their frames on that stack). **UserState only works on a 68000**: with the 68010 Supervisor frame it
   returns through a wrong stack slot (SetPatch 1.38 replaces it for that reason). [R]
9. **Insert ignores the list argument** unless `pred = NULL`; a `pred` whose successor field is NULL (the list's
   tail sentinel `&lh_Tail`) inserts **before** it, i.e. at the tail. [R]
10. **RemHead/RemTail do not clear the removed node's links**; on an empty list they return 0 with A1 left
    pointing into the header. [R]
11. **FindTask(name) searches the ready list, then the waiting list, and the running task last**, under Disable,
    calling FindName **through its vector** (so SetPatch's FindName is used). [R]
12. **SetFunction always sets LIBF_CHANGED**, writes a fresh `JMP` opcode in the slot (whatever was there), and
    re-sums only when `LIBF_SUMUSED` is set (then CHANGED is cleared again and no alert is possible). Without
    SUMUSED the library stays marked CHANGED and `lib_Sum` is untouched. No Forbid around the write. [R]
13. **MakeLibrary**: NegSize = 6 × (number of vectors), **not rounded**: with an odd number of vectors the library
    base is only word-aligned (base ≡ 2 mod 4). Memory is `MEMF_PUBLIC|MEMF_CLEAR`. **vectors = NULL is not
    supported** (MakeFunctions then reads its table from location 0). The init routine's D0 **becomes the
    result**; a NULL from it leaks the block. [R]
14. **InitStruct** clears `size >> 1` **words** (an odd last byte is not cleared, sizes ≥ 64 KB are truncated to the
    low word), then interprets the table; the `ss = 11` size code raises the dead-end alert `$81000007`; a
    24-bit-offset command must sit at an **even** address; byte-repeat does not re-align the table, byte-copy does.
    [R]

## 1. Supervisor-state functions

### 1.1 Supervisor (−30) — `Supervisor(userFunc A5)` [R]

- From **user mode** the entry deliberately raises a privilege violation. The privilege-violation handler
  recognises the faulting PC as one of the ROM's two Supervisor entries (68000 frame or 68010 frame), rewrites the
  stacked PC to a one-instruction "return" stub that returns to Supervisor's caller, and jumps to A5 **without
  touching any register**. Any other privilege violation goes to the task's trap code as trap 8 with the
  interrupt mask raised to 7 (`exec-scheduling-v34.md` §1). [R]
- From **supervisor mode** no exception occurs: Supervisor builds the same kind of frame itself on the **current**
  stack (SR as it is, PC = the return stub; on a 68010+ also the format word `$0020`) and jumps to A5. [R]
- The routine at A5 runs in supervisor mode, finds the frame at SP (68000: SR word then PC long; 68010+: SR, PC,
  format/vector word `$0020`), must end with `RTE`, and returns to Supervisor's caller. D0–D7/A0–A6 reach it
  unchanged and come back as it left them. The interrupt mask is the caller's (an exception does not change it).
- On a 68010+ (`AttnFlags` bit 0) exec puts the 68010-frame variant in the jump-table slot at coldstart. [R]
- A `SetFunction` on −30 breaks every user-mode call: the handler does not recognise the new PC (Guru
  `$00000008`, see `exec-scheduling-v34.md` §1).

### 1.2 SetSR (−144) — `oldSR = SetSR(newSR D0, mask D1)` [R]

- Goes through Supervisor (so the work is done on the exception frame). The stacked SR becomes
  `(oldSR & ~mask) | (newSR & mask)` (16-bit), then RTE applies it.
- Returns **D0 = old SR, zero-extended** (the caller's SR at the call: S = 0 from user mode, 1 from supervisor
  mode; T; interrupt mask; CCR).
- Registers on return: D0 = old SR; **D1 = original D1 with its low word complemented** (`~mask`); **A0 = old SR
  sign-extended** (scratch); A5 preserved; everything else preserved.
- **S bit**: no guard. Setting S from user mode makes RTE return in supervisor mode on the system stack, where the
  return stub then pops a wrong return address; clearing S from supervisor mode returns on the user stack.
  Either way the caller is lost. Only CCR, T and the interrupt-mask bits are usable. [D]
- Typical uses and vectors: `SetSR(0,0)` = read SR without change; `SetSR($0700,$0700)` = raise the mask to 7,
  returns the old SR to restore with `SetSR(old,$0700)`.

### 1.3 SuperState (−150) — `sysStack = SuperState()` [R]

- From **supervisor mode**: returns **D0 = 0**, mode and stacks unchanged.
- From **user mode**: enters supervisor mode (through Supervisor, keeping the caller's interrupt mask), drops the
  exception frame, sets **A7 = the user stack pointer** (the caller keeps running on its own stack, now as
  supervisor stack) and returns **D0 = the supervisor stack pointer as it was before the trap** (frame size
  accounted for, 6 bytes on a 68000, 8 on a 68010+ per `AttnFlags` bit 0).
- While in this state, interrupts and traps push their frames on the **task's stack**; the system stack is unused
  until UserState.
- Registers: D0 = result; **A0 = A5** (copy, scratch); A5 preserved; D1 and the rest preserved.

### 1.4 UserState (−156) — `UserState(sysStack D0)` [R]

- Must be called from supervisor mode (normally after SuperState), with D0 = SuperState's result.
- Effect: the current stack (minus Supervisor's frame) becomes **USP**, **SSP = D0**, S is cleared in the current
  SR (interrupt mask and CCR kept), and the caller resumes in user mode on its own stack.
- Registers: **D1 low word = the SR now in force** (S cleared, upper word unchanged); **A0 = A5**; others
  preserved.
- **68000 only**: the routine assumes Supervisor's 6-byte frame. On a 68010+ (8-byte frame) it returns through the
  format word and crashes; SetPatch 1.38 replaces this vector (`setpatch-138.md` §1.5). An implementation for a
  68010+ build must handle the larger frame.
- Called from user mode it goes through the privilege-violation path with a wrong stack: undefined (crash). [D]

### 1.5 GetCC (−528) — `ccr = GetCC()`

- 68000: D0 **low word** = `SR & $00FF` (CCR in bits 0–4, bits 5–7 always 0), **upper word of D0 unchanged**. No
  other register touched. Observed: D0 = `$C0000000` and SR = `$0018` on entry give D0 = `$C0000018`. [O]
- 68010+: at coldstart exec overwrites the **slot itself** with an inline `MOVE CCR,D0` + return (user mode cannot
  read SR there). Same register result. Consequence: the slot is no longer a `JMP abs.l`, so `SetFunction` on −528
  returns a meaningless "old" value on those CPUs (§4). [R]

## 2. List functions

`struct List`: `lh_Head` +0, `lh_Tail` +4 (always 0), `lh_TailPred` +8. The **head sentinel** is the list header
itself (as a node, its successor is `lh_Head`); the **tail sentinel** is `&lh_Tail` (as a node, its successor field
is `lh_Tail` = 0 and its predecessor field is `lh_TailPred`).

### 2.1 Insert (−234) — `Insert(list A0, node A1, pred A2)` [R]

| `pred` | Result | D0 / A0 on return |
|---|---|---|
| NULL | AddHead(list, node) | D0 = A0 = the old first node (new successor) |
| a node whose successor is non-NULL (a real node, or the list header itself) | node inserted **after** pred | D0 = A0 = node's new successor |
| a node whose successor is NULL (the tail sentinel `&list->lh_Tail`) | node inserted **before** pred, i.e. **at the tail** | D0 = 0, A0 = node's new predecessor |

- **A0 (the list) is not read** in the two `pred ≠ NULL` cases. A1, A2, D1 preserved. No result (D0 is
  scratch). No locking.
- `pred` = the list header ⇒ AddHead; `pred` = `&list->lh_Tail` ⇒ AddTail; a node already removed (stale
  links) or uninitialised ⇒ corruption, not detected.

### 2.2 RemHead (−258) — `node = RemHead(list A0)` [R]

- Non-empty: unlinks the first node, returns it in **D0**; **A1 = the new first node** (or the tail sentinel if the
  list became empty); the removed node's `ln_Succ`/`ln_Pred` are **left as they were**.
- Empty: **D0 = 0**, **A1 = `&list->lh_Tail`**, nothing written.
- A0 and D1 preserved. No locking.

### 2.3 RemTail (−264) — `node = RemTail(list A0)` [R]

- Non-empty: unlinks the last node, returns it in **D0**; **A1 = the new last node** (or the list header when the
  list became empty); the new last node's successor is set to `&lh_Tail`; the removed node's links are left as
  they were.
- Empty: **D0 = 0**, **A1 = the list header**, nothing written.
- A0 and D1 preserved.

### 2.4 Test vectors

List L with nodes N1, N2 (in order):
- `Insert(L, X, NULL)` → L = X, N1, N2.
- `Insert(anything, X, N1)` → N1, X, N2 (A0 ignored: pass a bogus pointer, same result).
- `Insert(anything, X, (Node*)&L.lh_Tail)` → N1, N2, X; D0 = 0.
- `Insert(anything, X, (Node*)&L)` → X, N1, N2.
- `RemHead(L)` → D0 = N1, A1 = N2, N1's links still point to L-header/N2.
- `RemTail(L)` → D0 = N2, A1 = N1, `N1.ln_Succ = &L.lh_Tail`.
- Empty L: `RemHead` → D0 = 0, A1 = `&L.lh_Tail`; `RemTail` → D0 = 0, A1 = `&L`.

## 3. FindTask (−294) — `task = FindTask(name A1)` [R]

- `name = NULL`: **D0 = ThisTask**, nothing else is read or changed (no Disable).
- Otherwise, under **Disable** (INTENA master bit off, `IDNestCnt` +1; re-enabled only when the count drops below
  0, as the Disable/Enable pair):
  1. `FindName(TaskReady, name)` **through the FindName vector**;
  2. if not found, `FindName(TaskWait, name)` through the vector;
  3. if not found, compares `name` with `ThisTask->ln_Name` (exact, case-sensitive byte compare up to the NUL).
  Returns the first match in D0, or 0.
- Order consequence: when a ready or waiting task has the same name as the running task, **the other task is
  returned**, not the caller.
- Registers: D0 = result; A0 scratch; A1 advanced past the compared bytes when step 3 ran (scratch); D1 preserved
  in the NULL case, scratch otherwise (FindName uses it).
- Tasks in no list (removed, or being added) are not found. The running task's name pointer is read without a
  NULL check.

## 4. Signals and traps

### 4.1 Defaults [R]

- Coldstart sets **`TaskSigAlloc = $0000FFFF`** (signals 0–15 reserved for the system) and **`TaskTrapAlloc =
  $8000`** (trap 15 reserved).
- **AddTask overwrites** `tc_SigAlloc` with `TaskSigAlloc` and `tc_TrapAlloc` with `TaskTrapAlloc`, and clears
  `tc_SigWait`, `tc_SigRecvd`, `tc_SigExcept` and `tc_TrapAble` (values preset by the creator are lost). Observed:
  the input.device task holds `tc_SigAlloc = $C000FFFF`, `tc_TrapAlloc = $8000` at the boot screen. [R/O]
- All four functions act on **ThisTask only** and take **no lock** (a task cannot allocate for another; an
  interrupt that changes the same masks races with them).

### 4.2 AllocSignal (−330) — `signalNum = AllocSignal(signalNum D0)` [R]

- "Any signal" is requested by a D0 whose **low byte is `$FF`** (−1, but also `$000000FF`, `$123456FF`).
  Then the free bits of `tc_SigAlloc` are searched **from 31 down to 0**; the first clear bit is allocated and its
  number returned in D0 (0–31, upper bits 0). None free ⇒ **D0 = −1**.
- A specific request uses bit **`D0 mod 32`**. Bit clear ⇒ allocated, and **D0 is returned unchanged** (e.g.
  `AllocSignal(48)` allocates bit 16 and returns 48). Bit already set (allocated or reserved) ⇒ **D0 = −1**.
- On success, after writing `tc_SigAlloc`, the bit is **cleared in `tc_SigRecvd`, `tc_SigExcept` and
  `tc_SigWait`**. On failure nothing changes.
- Registers: D0 = result; **A1 = ThisTask**; D1 = the new `tc_SigAlloc` on failure, or the mask `~(1 << n)` on
  success (scratch); A0 preserved.
- The low 16 signals are allocatable if a program cleared their bits (e.g. by FreeSignal), including by −1 once
  16–31 are taken.

### 4.3 FreeSignal (−336) — `FreeSignal(signalNum D0)` [R]

- Clears bit **`D0 mod 32`** of `tc_SigAlloc`. **No −1 test: `FreeSignal(-1)` clears bit 31.** No range or
  ownership check: `FreeSignal(4)` frees a system signal. Recvd/Wait/Except bits are not touched.
- Registers: A1 = ThisTask, D1 = new `tc_SigAlloc` (scratch); D0, A0 preserved.

### 4.4 AllocTrap (−342) — `trapNum = AllocTrap(trapNum D0)` [R]

- Works on the **word** `tc_TrapAlloc`, but through a 32-bit register: the **upper 16 bits come from the caller's
  D1**.
- "Any trap": D0 low byte `$FF` ⇒ search **from 15 down to 0**, first clear bit allocated, number returned (0–15);
  with the defaults the first answer is **14**. None free ⇒ D0 = −1.
- Specific: bit `D0 mod 32`.
  - 0–15: allocated if clear, **D0 returned unchanged**; −1 if already set (15 by default).
  - **16–31**: the bit tested is bit (n − 16) of the caller's **D1 upper word**; if it is clear the call returns
    **D0 unchanged (success) without allocating anything**; if it is set, −1. `tc_TrapAlloc` is never changed.
- `tc_TrapAlloc` is rewritten in every case (unchanged value on failure). `tc_TrapAble` is **not** touched (the
  trap is allocated but not enabled).
- Registers: D0 = result; A1 = ThisTask; D1 low word = new `tc_TrapAlloc`, upper word = caller's (scratch).

### 4.5 FreeTrap (−348) — `FreeTrap(trapNum D0)` [R]

- Clears bit `D0 mod 32` of a 32-bit copy whose low word is `tc_TrapAlloc`, then writes the low word back: 0–15
  free that trap; **16–31 (−1 included) do nothing**. No ownership check; `FreeTrap(15)` frees the reserved trap.
- Registers: A1 = ThisTask, D1 scratch; D0, A0 preserved.

### 4.6 Test vectors (fresh task: `tc_SigAlloc = $0000FFFF`, `tc_TrapAlloc = $8000`)

Rows run in order on the same task, except those marked "fresh task" (a new task from AddTask).

| Call (D0, D1) | D0 returned | Mask after |
|---|---|---|
| AllocSignal(−1) | 31 | SigAlloc `$8000FFFF` |
| AllocSignal(−1) again | 30 | `$C000FFFF` |
| AllocSignal($000000FF) | 29 | `$E000FFFF` |
| AllocSignal(4) | −1 | unchanged |
| AllocSignal(20), SigRecvd bit 20 set before | 20 | bit 20 allocated; SigRecvd bit 20 cleared |
| AllocSignal(20) again | −1 | unchanged |
| AllocSignal(52) on a fresh task | 52 | bit 20 allocated |
| fresh task: AllocSignal(−1) ×16, then once more | 31 … 16, then −1 | `$FFFFFFFF` |
| then FreeSignal(3); AllocSignal(−1) | 3 | `$FFFFFFFF` |
| then FreeSignal(−1) | — | `$7FFFFFFF` (bit 31 freed) |
| AllocTrap(−1), AllocTrap(−1) | 14, 13 | TrapAlloc `$E000` |
| AllocTrap(15) | −1 | unchanged |
| AllocTrap(20), D1 = 0 | 20 | **unchanged** |
| AllocTrap(20), D1 = `$00100000` | −1 | unchanged |
| AllocTrap(36), D1 = 0 | 36 | bit 4 allocated (`$E010`) |
| FreeTrap(−1) | — | unchanged |
| FreeTrap(14) | — | bit 14 cleared |

## 5. SetFunction (−420) — `oldFunc = SetFunction(library A1, funcOffset A0, funcEntry D0)` [R]

Order of effects:
1. Sets **LIBF_CHANGED** (bit 1 of `lib_Flags`, +$0E).
2. Slot = library + (**low word of A0, sign-extended**); the upper word of A0 is ignored; no check of the offset
   (a positive or misaligned offset patches whatever is there).
3. Reads the 4 bytes at slot+2 as the **old value**, writes the opcode word `$4EF9` (`JMP abs.l`) at the slot and
   D0 at slot+2. The opcode is written **whatever the slot held** (e.g. GetCC's inline code on a 68010+, §1.5).
4. Runs the SumLibrary logic (`exec-messages-io-v34.md` §4.4) directly (not through the −426 vector):
   - `LIBF_SUMUSED` clear ⇒ nothing more: **CHANGED stays set, `lib_Sum` untouched**.
   - `LIBF_SUMUSED` set ⇒ Forbid; CHANGED cleared and, since it was set, the stored sum word zeroed; the word sum
     of the `lib_NegSize` bytes below the base recomputed and stored in the upper word of `lib_Sum` (+$1C); Permit
     **through the −138 vector**. The mismatch alert `$81000003` cannot fire from SetFunction (the stored word was
     just zeroed).
5. Returns **D0 = the old value**.

- **No Forbid/Disable around step 3**: callers that patch vectors other tasks may be calling should Forbid
  themselves (FastFonts, ramlib and SetPatch do).
- Registers: D0 = old value; A1 preserved; A0 and D1 scratch (A0 = the slot, or the start of the table after a
  sum; D1 = the sum when SUMUSED); D2–D7/A2–A6 preserved.
- Restoring a patch is just another SetFunction with the old value; chains are the caller's business (ramlib
  §2.1).
- Test vectors: library with `lib_Flags = LIBF_SUMUSED` and a valid sum: `SetFunction(lib, -30, X)` → returns the
  previous address; slot = `$4EF9`, X; `lib_Flags` without CHANGED; upper word of `lib_Sum` = the new 16-bit word
  sum of the table, lower word unchanged; a following `SumLibrary(lib)` does not alert. Same library with
  `lib_Flags = 0`: flags become `LIBF_CHANGED`, `lib_Sum` unchanged. `A0 = $0001FFE2` is offset −30.

## 6. Auto-initialisation helpers

### 6.1 InitStruct (−78) — `InitStruct(initTable A1, memory A2, size D0)` [R]

1. **Clears** `(size & $FFFF) >> 1` **words** from `memory` (an odd final byte is not cleared; `memory` must be even
   when size ≥ 2; only the low word of `size` counts). Size 0 or 1 clears nothing.
2. Interprets the table from A1 with a current destination starting at `memory`. Each command byte
   `dd ss nnnn` (bits 7-6, 5-4, 3-0), count = nnnn + 1 (1–16):
   - **byte `$00` ends the table** (so "copy one long at the current destination" cannot be expressed);
   - `dd = 00`: **copy** count elements from the table to the current destination;
   - `dd = 01`: **repeat**: one element is read from the table and stored count times;
   - `dd = 10`: destination = `memory` + the next table byte (0–255), then copy;
   - `dd = 11`: destination = `memory` + a **24-bit offset** made of the three bytes after the command byte; the
     command byte and its offset are read as one long, so the command byte must be at an **even** address (68000
     address error otherwise); then copy.
   - `ss`: 00 long, 01 word, 10 byte; **`ss = 11` raises `Alert($81000007)`** (dead-end).
   - Alignment of the **table** pointer: before reading a long or word element (copy or repeat) the table pointer
     is rounded up to even; after a **byte copy** it is rounded up to even; after a **byte repeat** it is **not**
     (the next command byte may then sit at an odd address).
   - The **destination is never aligned**: a long or word store at an odd destination is a 68000 address error.
   - The destination advances by what was written; after an offset command it continues from the new place.
3. No result. D0, D1, A0, A1 scratch (A1 ends after the terminator, A0 after the last store).

Test vector (memory 16 bytes of `$FF`, table at an even address): `$C0,$00,$00,$04` (24-bit offset 4, one long)
`$12,$34,$56,$78`, `$A1,$0A` (byte offset 10, copy 2 bytes) `$AB,$CD`, `$62` (repeat one byte 3 times) `$77`,
`$00` (end, read right after `$77`; to see the missing re-alignment, put one more byte-repeat command before
it so that the end byte falls on an odd address: it is still taken as the end) → with size 16:
memory = `00 00 00 00 12 34 56 78 00 00 AB CD 77 77 77 00`; with size 15: the same except the last byte, which
stays `$FF` (7 words cleared).

### 6.2 MakeFunctions (−90) — `size = MakeFunctions(target A0, functionArray A1, funcDispBase A2)` [R]

- `funcDispBase ≠ 0`: the array is **signed 16-bit offsets** relative to `funcDispBase`, ended by the word −1
  (the array must **not** start with the −1 marker word: MakeFunctions does not skip it, it would stop at once).
- `funcDispBase = 0`: the array is **absolute 32-bit addresses**, ended by the long −1.
- Entries are written **downwards** from `target`: entry k at `target − 6(k+1)`, as `$4EF9` + address.
- Returns **D0 = 6 × entries** (bytes written). A0 ends at the lowest slot, A1 after the terminator, D1 = −1
  (scratch); A2, A3 and the rest preserved. No cache flush (68000).

### 6.3 MakeLibrary (−84) — `library = MakeLibrary(vectors A0, structure A1, init A2, dataSize D0, segList D1)` [R]

1. Counts the vectors: if the first word of `vectors` is −1, word-offset format (entries after the marker, up to
   the next −1 word); otherwise longs up to the −1 long. **NegSize = 6 × count** (no rounding).
2. `AllocMem(dataSize + NegSize, MEMF_PUBLIC|MEMF_CLEAR)` (the full 32-bit `dataSize`). Failure ⇒ **D0 = 0**,
   nothing else.
3. Base = block + NegSize. **With an odd count the base is ≡ 2 (mod 4)** (the block is 8-aligned). Writes
   `lib_NegSize` (+$10) = NegSize and `lib_PosSize` (+$12) = **low word of dataSize**. No other library field is
   set (type, name, version, flags come only from `structure` or `init`).
4. MakeFunctions(base, …): word format with `funcDispBase` = the address of `vectors` itself (offsets relative to
   the −1 marker word), long format with `funcDispBase` = 0.
5. If `structure ≠ NULL`: `InitStruct(structure, base, 0)` (no clearing; the block is already zero).
6. If `init ≠ NULL`: calls it with **D0 = base, A0 = segList**, A6 = ExecBase; **its D0 becomes MakeLibrary's
   result**. A NULL result does not free the block.
7. Returns D0. Not added to any list (AddLibrary/AddDevice/AddResource is the caller's job).

- **`vectors = NULL` is not supported in 1.3**: the count is 0 but step 4 still reads a table at location 0 and
  writes jump slots below the block (memory corruption). [R/D]
- Registers: D0 = result; D1, A0, A1 scratch; D2–D7/A2–A3 preserved; A4–A6 preserved unless `init` changes
  them.
- Test vectors: 5 long vectors, dataSize 34 → block of 64 bytes, base = block + 30, NegSize 30, PosSize 34,
  base mod 4 = 2, five `$4EF9` slots below. Word format `-1, o1, o2, o3, o4, -1` (4 entries) → slot k jumps to
  `vectors + ok`, NegSize 24.

### 6.4 FindResident (−96) — `resident = FindResident(name A1)` [R]

- Walks the `ResModules` array (ExecBase +$12C): a 0 long ends it; a long with bit 31 set is a **link** to a
  further array (address = the long with bit 31 cleared); any other long is a RomTag pointer whose `rt_Name`
  (+$0E) is compared with `name` (exact, case-sensitive, up to the NUL).
- Returns the **first** match in array order (the array is sorted by priority, so the highest-priority RomTag of
  a duplicated name wins), or 0. No lock.
- Registers: D0 = result; A0, A1 scratch; A2, A3 preserved.

## 7. Notes for a clone (AutoDocs and AROS vs V34)

1. Reproduce the **modulo-32 / low-byte −1** quirks of §4 only if a program depends on them; the observable
   differences that do matter: AllocSignal(−1) order (31 first), AllocTrap(−1) = 14 first, signal bits cleared in
   Recvd/Except/Wait, `FreeSignal(-1)` freeing signal 31 (2.0+ made it a no-op; a 1.3 program calling
   `FreeSignal(AllocSignal(-1))` after a failed allocation really loses signal 31).
2. GetCC: keep the upper word of D0.
3. SetSR: return the full old SR; D1 = `~mask` low word is harmless to reproduce.
4. Insert/RemHead/RemTail: never clear removed nodes' links (programs re-insert nodes and some inspect stale
   links); honour the `&lh_Tail` predecessor case.
5. FindTask order (ready, waiting, self) and the call through the FindName vector.
6. SetFunction: CHANGED is left set on non-SUMUSED libraries; a library made with LIBF_SUMUSED is re-summed.
7. MakeLibrary: unrounded NegSize (base alignment), `init` result returned, NULL vectors unsupported. A clone that
   longword-aligns library bases is compatible with every known program but differs in base addresses.

## 8. Probe to write (implementation side)

A HUNK executable run from the startup-sequence of a test floppy, results on the serial port, final marker
`EXP fin`. Everything through the LVOs with A6 = SysBase, in the probe's own task (CreateTask a helper task first
so that its `tc_SigAlloc`/`tc_TrapAlloc` start at the AddTask defaults; run §4.6 in that task and report through a
message).

1. §4.6 table, printing D0 and D1 after each call and `tc_SigAlloc`, `tc_TrapAlloc`, `tc_SigRecvd`.
2. GetCC with D0 preset to `$C0000000` after setting CCR to `$15` (expect `$C0000015`); SetSR(0,0) and
   SetSR($0700,$0700)/restore, printing D0/D1/A0.
3. SuperState from user mode (print D0, SP, SR), then UserState(D0) (print SR, SP); SuperState from supervisor (via
   Supervisor) → D0 = 0.
4. §2.4 list vectors, printing D0/A0/A1 and all links.
5. FindTask with a helper task named like the probe's own task.
6. SetFunction vectors of §5 on a MakeLibrary'd test library (with and without LIBF_SUMUSED), printing flags and
   `lib_Sum`.
7. MakeLibrary with 5 long vectors (print base mod 4, NegSize, PosSize) and the InitStruct vector of §6.1.

## 9. Open points

- §4 and §5–§6 come from reading the code; only GetCC (§1.5) and the task defaults were checked by a black-box call
  on the real ROM. The §8 probe has not been run.
- SuperState/UserState were not run on a 68010+ emulation (the UserState defect is deduced from the frame sizes).
- Whether any 1.3 program relies on AllocTrap(16…31) or on the stale links left by RemHead/RemTail is not known.

## Clean-room review

Review of 2026-11-10.

- [x] No 68000 instruction sequence transcribed or paraphrased, no disassembly excerpt, no ROM routine or data
  address. Behaviour is given as registers, fields, ordered effects and results.
- [x] The only numbers are public LVOs and structure offsets (`exec/tasks.i`, `exec/libraries.i`,
  `exec/lists.i`, `exec/resident.i`, ExecBase as in `exec-spec.md`), flag bits, alert numbers, the `JMP abs.l`
  opcode word as the public jump-table format, and our own test values.
- [x] §1.5 states that exec writes "an inline MOVE CCR,D0 plus a return" into the GetCC slot on 68010+: this names
  the effect (the slot's content as observable data in RAM), not a routine of the ROM.
- [x] No probe code was written by the analysis track; §8 describes one in words.
