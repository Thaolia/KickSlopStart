# task-held-v34.md — the "Software error - task held" requester (Kickstart 1.3, 34.5)

> **Behavioural** spec (ANALYSIS track). Answers REMAINING-WORK A12. Complements `alert-v34.md` (what happens
> once the Guru path is taken) and `intuition-requesters-v34.md` §5 (how a system requester is built and drawn).
> No instruction sequence, no ROM address or offset: only displayed texts, measured geometry, observable state
> and orders of effects.
>
> Legend: **[S]** black-box observation of the real ROM under Amiberry (A500 preset, 68000, cycle-exact,
> screenshots read by the agent, exec state read with the emulator debugger) · **[D]** deduced from [S]
> observations, not observed directly.

---

## 0. Short answer

- On a CPU exception in a **DOS process** (CLI command, `Run` command, any process that dos created), the real 1.3
  does **not** go straight to the Guru: the faulting process opens a system requester titled `System Request`
  with three lines `Software error - task held` / ` Finish ALL disk activity` / `Select CANCEL to reset/debug` and
  the gadgets **Retry** (left) and **Cancel** (right). **[S]**
- It comes from the **trap handler that dos installs in every process it creates** (`tc_TrapCode`); a plain exec
  task keeps exec's default trap handler and gets the Guru path directly. **[S]**
- **Retry** closes the requester and opens it again at once; the task is **never resumed**. **Cancel** calls the
  normal exec Alert with the exception vector number as alert number and the task address as second number, i.e.
  exactly the Guru `#0000000N.<task>` that a task without the requester would get. **[S]**
- While the requester is up, only the faulting task is stopped (it sleeps inside the requester); every other task
  keeps running. **[S]**

## 1. Who raises it, and when

### 1.1 The switch is `tc_TrapCode`, not the node type [S]

Observed on a booted system (boot CLI, `Run`, two File System processes, CON and SER handlers, input.device and
two trackdisk.device tasks):

| Task | `ln_Type` | `tc_TrapCode` compared with `ExecBase->TaskTrapCode` |
|---|---|---|
| input.device, trackdisk.device (×2) | NT_TASK (1) | **equal** (exec default) |
| Initial CLI, CON, File System (×2) | NT_PROCESS (13) | **different**, and the **same** value for all processes |

Discriminating experiments, all with an illegal instruction placed at the entry of a CLI command (§5):

| Change made with the debugger just before the fault | Result |
|---|---|
| none | requester |
| `ln_Type` of the faulting process forced to NT_TASK (trap code untouched) | requester (identical) |
| `tc_TrapCode` of the faulting process replaced by `ExecBase->TaskTrapCode` | **no requester**, Guru path at once |
| `pr_WindowPtr` of the faulting process set to −1 | **no requester**, Guru path at once (as if Cancel) |

Consequences for an implementation:
- The requester belongs to the trap handler that dos stores in `tc_TrapCode` when it creates a process
  (`CreateProc`/BCPL `createproc`: every process observed has it, handlers included). The node type is not
  tested. **[S]**
- A **plain exec task** (AddTask without dos) faults straight into exec's default handler → Alert → Guru, no
  requester. Observed indirectly: the handler swap above gives exactly that; the trackdisk/input tasks carry the
  exec default. Not observed by faulting such a task directly. **[S]/[D]**
- A program that installs **its own** `tc_TrapCode` (debuggers, JST-like loaders, C start-up code with signal
  handling) gets its handler called instead; the dos requester is then shown only if that handler chains to the
  previous value. **[D]** (follows from the swap experiment).
- `pr_WindowPtr = −1` (the usual "no requesters" setting of a process) suppresses this requester too: the
  process goes directly to the Alert, with the same alert numbers as after Cancel. `pr_WindowPtr = 0` (the
  default) puts it on the Workbench screen. A `pr_WindowPtr` pointing to a window on a custom screen was **not
  tested** (other dos requesters use that window's screen; assumed the same here, **[D]**).

### 1.2 Exception classes [S]

Each row: one boot of the real ROM, fault in the boot CLI process ("Initial CLI") at the entry of `C:Echo`,
requester observed, then Cancel, then alert number read back from low memory and from the Guru text.

| Exception (how it was caused) | Vector | Requester | Alert number after Cancel |
|---|---|---|---|
| address error (jump to an odd address) | 3 | yes | `00000003` |
| illegal instruction (`$4AFC`) | 4 | yes | `00000004` |
| divide by zero (DIVU by an immediate 0) | 5 | yes | `00000005` |
| privilege violation (RTE in user mode) | 8 | yes | `00000008` |
| line-A opcode (`$A000`) | 10 | yes | `0000000A` |
| line-F opcode (`$F000`) | 11 | yes | `0000000B` |
| TRAP #0 | 32 | yes | `00000020` |

- The requester text is the same for every class (it does not name the exception). **[S]**
- Not tested: bus error (none on a plain A500), CHK (6), TRAPV (7), trace (9), TRAP #1-#15. Expected to behave
  the same, since the requester does not look at the class. **[D]**
- Same requester for a command started with `Run` (the faulting process is then "Background CLI"; the second
  alert number is that process). **[S]**
- `SetPatch 1.38` run before the fault changes nothing. **[S]**
- A program started from the Workbench (a process created by the Workbench task) was **not tested**; it is a dos
  process, so the requester is expected. **[D]**

## 2. What is displayed

### 2.1 Window and screen [S]

- A system requester window (the AutoRequest/BuildSysRequest kind, `intuition-requesters-v34.md` §5) titled
  **`System Request`**, with depth gadgets at the right of the title bar, opened on the **Workbench screen**
  (in the runs: the screen of the boot CLI window, no `LoadWB`).
- Position **(0,0)** of the screen, outer size **320 × 72** (320 high-resolution pixels, 72 non-interlaced lines),
  measured on the emulator picture (±1 pixel). The CLI window behind changes its title bar look while the
  requester is up (consistent with the requester window being activated; activation itself not checked).
- Body, in the requester's white area, Topaz 8, three lines, text pen blue on white (Workbench 1.3 palette):

| Line | Exact text (between the quotes) | Left edge of the text (x) | Glyph rows (y) |
|---|---|---|---|
| 1 | `"Software error - task held"` | 20 | 16-22 |
| 2 | `" Finish ALL disk activity"` (**one leading space**) | 28 | 26-33 |
| 3 | `"Select CANCEL to reset/debug"` | 20 | 36-43 |

  Lines are 10 lines apart. Line 2 is not centred: its leading space is part of the string. (Coordinates are
  relative to the window's top-left corner; the text x is where the first glyph cell starts.)
- Gadgets: **`Retry`** at the left (outer highlight box about x 17-70, y 50-65) and **`Cancel`** at the right
  (about x 227-288, y 50-65), both boxed as in every 1.3 AutoRequest. Retry is the positive gadget, Cancel the
  negative one. **[S]** (positive/negative from the effects in §3, **[D]**)
- No other text, no exception number, no task name in the requester. **[S]**

### 2.2 Related text in the same component

- dos also holds `Disk corrupt - task held` (same second and third lines, see `alert-v34.md` §3). Its trigger was
  **not** observed in these runs (not a CPU exception: presumably a file-system validation failure). **[D]**

## 3. Behaviour while it is up, Retry, Cancel

### 3.1 State of the system while the requester is shown [S]

- The faulting process is in the **waiting** list, waiting on a single signal (bit 31, the signal of the
  requester window's IDCMP port): the requester runs **in the context of the faulting process itself**, which
  sleeps in it. **[S]** (that it is the window port signal: **[D]**)
- All other tasks keep running normally (input.device current, file systems and handlers waiting on their
  ports); the mouse pointer moves, other windows could be used. "task held" means only that one task is stopped.
  "Finish ALL disk activity" is advice to the user before Cancel resets the machine. **[S]/[D]**

### 3.2 Retry [S]

- The requester window closes and an identical one opens at once (a screenshot 0.15 s after the click shows the
  new window frame being redrawn, empty; 0.2 s later it is complete again).
- The faulting task is **not** resumed: with the faulting instruction restored in memory by the debugger before
  clicking Retry, the command still did not run (no output) and the requester came back. Repeated three times,
  same result. So Retry is an endless "show again"; only Cancel leaves.

### 3.3 Cancel [S]

- The requester window closes, then exec `Alert(vector number, A5 → task)` is taken exactly as for a task
  without the requester (`alert-v34.md` §1): alert number = the exception vector number (high word 0, no
  dead-end bit), second number = the address of the faulting task (`#0000000N.<task address>`). Low memory after
  the run: `$100` = vector number, `$104` = task address.
- What follows depends only on exec's Alert decision (`alert-v34.md` §1.1):
  - **ExecBase in slow RAM** (A500 with 512 KB at `$C00000`, the configuration of the JST study): hard path. The
    display stays **frozen as it is** (Workbench screen with the CLI window, requester gone) for about
    **10-13 s** of wall clock in these runs (emulator under load, so only indicative), then the machine resets
    (grey, then white coldstart screens), and on the new boot alert.hook shows the black full-display Guru
    `Software Failure.   Press left mouse button to continue.` / `Guru Meditation #00000004.00C05128` (example
    for vector 4, task in slow RAM). Left button → the boot continues normally. The serial DEL → ROM-Wack branch
    of that phase ("reset/**debug**") was not exercised.
  - **ExecBase in chip RAM** (512 KB chip only): immediate display: the Guru box at the top of the display with
    the Workbench screen pushed down below it, frame blinking, waiting for a button. Left button → reset; the
    next boot shows **no** second Guru and runs the startup-sequence normally. Right button (ROM-Wack) not
    tested.

## 4. Test vectors (for our ROM; expected results = real 1.3)

Configuration: A500, Workbench 1.3.3 disk copy, startup-sequence of the probe below, chip 512 KB + slow 512 KB
unless stated.

| # | Stimulus | Expected |
|---|---|---|
| T1 | illegal instruction in a CLI command | requester of §2; Cancel → Guru `#00000004.<process>` |
| T2 | same, Retry clicked N times | requester closes and reopens each time; command never continues |
| T3 | same, after Cancel, chip-only machine | immediate Guru at top, left button → reset, normal reboot |
| T4 | vectors 3, 5, 8, 10, 11, 32 | same requester; alert number = vector (`3`, `5`, `8`, `A`, `B`, `20`) |
| T5 | fault in a command started with `Run` | same requester; second number = the Background CLI process |
| T6 | process with `pr_WindowPtr = −1` | no requester; Guru path at once |
| T7 | process whose `tc_TrapCode` was set to `ExecBase->TaskTrapCode` | no requester; Guru path at once |
| T8 | plain exec task (no dos) faulting | no requester; Guru path at once (**[D]**, see §1.1) |
| T9 | process whose `ln_Type` was changed to NT_TASK | requester as T1 |

## 5. How it was observed, and a probe for our side

- Real-ROM runs: boot from a copy of the Workbench 1.3.3 disk whose startup-sequence is `Wait 10`, then
  `Echo >SER: "P2 target"`, then markers. The emulator debugger stopped the CPU at the entry of the `Echo`
  program (the WB 1.3.3 `Echo` starts with ordinary machine code in RAM), wrote the faulting opcode(s) there in
  RAM, and resumed. Variants: `Run Echo ...`, `SetPatch` first, 512 KB chip only, and the debugger changes of
  §1.1. Screenshots were read; `$100`/`$104` were read after the Guru.
- A standalone probe for our ROM (to be written outside the analysis track, from this description): a tiny CLI
  command whose first instruction is an illegal opcode (or a DIVU by zero, a line-A word, a TRAP #0…), run from
  the startup-sequence; an optional argument makes it first set its own `pr_WindowPtr` to −1, or replace its own
  `tc_TrapCode` with `ExecBase->TaskTrapCode`, or start a plain exec task (AddTask) that executes the illegal
  opcode. Expected results: §4.

## 6. Open points

- The `Disk corrupt - task held` trigger.
- Bus error / CHK / TRAPV / trace, and a Workbench-started program (expected identical, not run).
- Requester placement when `pr_WindowPtr` is a window on a custom screen.
- The DEL → ROM-Wack branch after Cancel (hard path) and the right button of the immediate Guru.
