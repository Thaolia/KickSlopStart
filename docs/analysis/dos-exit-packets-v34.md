# dos-exit-packets-v34.md — dos.library V34: Exit, WaitForChar, GetPacket / QueuePacket

> ANALYSIS track ("dirty"). Sources: ROM `kick34005.A500` (read-only, radare2 static reading of the
> dos kernel, BLIB, console handler and file system segments) and the Workbench 1.3.3 disk
> (`assets/wb133.adf`, files extracted to the session scratch directory, scanned for library calls).
> No probe was run for this page, except §1.3 (Exit(−1), black-box probe of 2026-11-02, marked
> "[O] (probe)"). We describe the **what**: entry/exit registers, fields, packet contents, order of
> observable effects, return values. No instruction sequence, no ROM address.
>
> **Legend**: **[O]** observed (read in the ROM / WB binaries) · **[D]** deduced · **[S]** assumed.
>
> Related specs, not repeated here: `bcpl-runtime-v34.md` §1.4 (LVO → BCPL bridge, LVO/global table),
> §2.4 (BCPL process start), §4.3–§4.4 (runcommand, what the CLI does with the return code), §8
> (globals); `dos-v34-spec.md` §3 (Process layout); `workbench-task-v34.md` §3.5 (WBStartup reply
> handling on the Workbench side).

---

## 0. Executive summary

1. **Exit(code)** (−144, D1) = BCPL global 2 (`stop`) of `dl_GV`. It does **one thing**: it resets the
   stack pointer to `pr_ReturnAddr − 4` and returns from there with **D0 = code**. Nothing is
   closed, freed or unlocked. Where it lands depends only on what sits at `pr_ReturnAddr − 4`:
   - CLI command: the return point of `runcommand` ⇒ exactly like a normal `rts` of the command
     with D0 = code (the CLI stores it in `cli_ReturnCode`);
   - process started by `CreateProc` (including every Workbench-started tool): the task's
     **finalPC** (dos's `endtask`) ⇒ the process ends; the code is **discarded**. [O]
2. **WaitForChar(fh, timeout)** (−204, D1/D2) = global 87: if `fh_Type` (FileHandle +$08) is 0 ⇒
   returns **0** at once (no packet). Otherwise sends **ACTION_WAIT_CHAR (20)** to `fh_Type` with
   **dp_Arg1 = timeout in microseconds** and returns **dp_Res1 raw** (console: −1 or 0). `fh_Arg1`
   is **not** passed. The ROM file system answers 0 with IoErr **209**. [O]
3. ROM console handler: a character "is available" only when the **read buffer** is non-empty, i.e.
   in cooked mode a **complete line** (Return) has been typed; in raw mode any key. Timeout 0 ⇒
   immediate answer. Otherwise a timer.device (unit 0, MICROHZ) request is armed; the packet is
   answered −1 as soon as data becomes available, or 0 at expiry. [O]
4. **GetPacket (−162)** and **QueuePacket (−168)** are **not** packet functions in V34. The two vectors
   are wired to BCPL globals −20 and −21: −162 clears memory (`clearvec(D1, D2)`), −168 loads a segment
   by BSTR name without requesters. Nothing in `pr_MsgPort` is touched. **No program of the
   Workbench 1.3.3 disk calls them.** [O]

---

## 1. Exit (LVO −144)

### 1.1 Call path [O]

- The vector loads global **2** and enters the common LVO bridge (`bcpl-runtime-v34.md` §1.4): C registers
  saved on the **caller's** stack, BCPL frame built 1500 bytes below the caller's SP, A2 := `dl_GV`
  (**not** the caller's `pr_GlobVec`), then call with **D1 = code**.
- Global 2 of `dl_GV` (kernel `stop`):
  1. finds the current process (FindTask(0));
  2. sets the stack pointer to **`pr_ReturnAddr` (process +$B0) − 4**;
  3. returns (pops the long found there as return address) with **D0 = D1 = code**.
- The registers saved by the bridge, the BCPL frame and everything between the old SP and
  `pr_ReturnAddr` are simply abandoned. No register other than D0 is defined on arrival. [O]
- Consequence: `Exit` never returns to its caller. It works the same whether the caller is C or BCPL,
  at any call depth. [O]
- The code is passed **as is** (32-bit, no clamping); negative values are allowed. [O]

### 1.2 What lies at `pr_ReturnAddr − 4` [O]

| Context | Who set `pr_ReturnAddr` | Long at `pr_ReturnAddr − 4` | Effect of Exit(code) |
|---|---|---|---|
| Command run by a CLI (`runcommand`, global 121) | `runcommand`, for the duration of the call; old value saved and restored afterwards | return address pushed by the call into the command | identical to the command returning with D0 = code |
| Process from C `CreateProc` (LVO −138, global −18) | CreateProc: address of the long holding the **stack size in bytes**, at the top of the new stack; also the initial SP | the **finalPC** pushed by exec AddTask = dos `endtask` | end of the process (§1.4) |
| Process from BCPL `createproc` (global 33: CLIs, handlers, Initial CLI) | createproc: initial SP (just below the task name copied at the top of the stack) | finalPC = `endtask` | end of the process (§1.4) |
| Workbench-started tool | = C CreateProc (the Workbench calls LVO −138) | finalPC = `endtask` | end of the process; code lost |

- Entry state of a C CreateProc process, for reference [O]: (SP) = finalPC, 4(SP) = stack size in
  bytes, `pr_ReturnAddr` = SP + 4, PC = `BADDR(seglist) + 4`, D0 = 0 (cf. `workbench-task-v34.md` §1.3).
  A program that simply returns (`rts`) therefore ends up in the same `endtask` as one that calls Exit.
- **Nested commands**: `Execute()` (global 101) and the CLI run C:Run / the command through
  `runcommand`, which installs its own `pr_ReturnAddr` and restores the previous one afterwards. Exit
  always targets the **innermost** active `runcommand` of the calling process. [O]
- **BCPL commands** do not reach this routine through `stop`: their stub replaces global 2 of their
  **private** GV (`bcpl-runtime-v34.md` §3.3 step 8). A BCPL command that called LVO −144 would still
  get the kernel `stop` (the bridge uses `dl_GV`), with the same result: back to `runcommand`. [O/D]

### 1.3 CLI command case: return code propagation [O]

- `runcommand` gets D0 = code, frees the command stack, restores `pr_ReturnAddr`, A1/A2/A5/A6 and the
  old SP, and returns the code; **pr_Result2 is not touched** (the value left by the program stays).
- The CLI then applies `bcpl-runtime-v34.md` §4.4: `cli_ReturnCode` := code; `cli_Result2` :=
  `pr_Result2` if code ≠ 0, else 0; "failed returncode" + script abandon if code ≥ `cli_FailLevel` and
  the CLI is not interactive; `UnLoadSeg(cli_Module)`.
- Code **−1** is the special value "command could not be started" (§4.4 there). A program that ends
  with Exit(−1) is treated by the CLI **exactly like a command that could not be loaded**. Observed on the
  real ROM (probe `tests/dosexit_test.s` modes `e`/`u`/`v`/`w`: Exit(−1) from four nested 512-byte frames,
  with pr_Result2 = 205 / 0 / 103 / 218 set just before; mode `e` on Amiberry and FS-UAE, modes `u`/`v`/`w` on
  Amiberry, 2026-11-02) [O] (probe):
  - **message**: chosen from the **pr_Result2** value left by the program, exactly as for a lookup failure
    (`bcpl-runtime-v34.md` §4.1) [O] (probe):

    | pr_Result2 at Exit(−1) | Line printed by the CLI |
    |---|---|
    | 205 (object not found) | `Unknown command <name>` |
    | 218 (not mounted) | `Unknown command <name>` |
    | 0 | `Unknown command <name>` |
    | 103 (insufficient free store) | `Unable to load <name>: Error code 103` |

    `<name>` = the command name as typed (e.g. `df0:dosexit_test`). So 0, 205 and 218 give the same text as a
    command that does not exist; any other tested value gives "Unable to load", whose error text in 1.3 is
    the plain form `Error code <n>` (decimal). No "failed returncode" line is printed in any case.
  - **cli_ReturnCode = 0** afterwards in every case, as read by the next command typed in an interactive
    CLI (a previous cli_ReturnCode of 20 is overwritten with 0; in a script the next line never runs, see
    below). **cli_Result2** depends on the message path [O] (probe): **0** after an "Unknown command" line
    (pr_Result2 = 0, 205 or 218: the 205/218 left by the program is **not** copied), but **103** after
    `Unable to load … Error code 103` (the program's pr_Result2 **is** kept). A genuinely missing command
    gives 0 / 0.
  - **script**: in a non-interactive CLI (startup-sequence) the script is **abandoned** at once, whichever
    message is printed (observed for pr_Result2 = 0, 103, 205 and 218 under the default FailAt), and this
    does **not** depend on `cli_FailLevel`: abandoned with the default FailAt 10 and also after `FailAt 30`
    (the Workbench 1.3.3 `C:FailAt`, which in the same run let an Exit(20) command continue silently). A genuinely missing command
    (`Unknown command df0:nosuchcmd`) abandons the script the same way under FailAt 30. In an interactive
    CLI there is no abandon; the prompt comes back.
  - **Uncertain**: only pr_Result2 = 0, 103, 205 and 218 were probed; other values are expected to follow
    the 103 row (rule of `bcpl-runtime-v34.md` §4.1, which the 0 row shows also routes 0 to "Unknown
    command"). The FailAt-independence was checked with pr_Result2 = 205 only, and FailAt values above 30
    were not tried.

### 1.4 Process case: `endtask` (= finalPC) [O]

Order of effects:
1. `freevec(pr_SegList)` (process +$80): frees the **segarray vector** (for a C CreateProc process: the
   4-entry vector `[2, kernel, BLIB, seglist]` allocated by CreateProc). The vector's hidden size
   header is checked; a bad header raises alert **$07000005**.
2. If `pr_GlobVec` (process +$88) ≠ `dl_GV`: frees the private GV (its block starts 50 longs below
   slot 0). C CreateProc processes use `dl_GV`, so nothing is freed for them.
3. `RemTask(0)`: exec frees `tc_MemEntry`, i.e. the single block holding the Process structure and its
   stack (allocated by CreateProc). Never returns.

**Not done** (all versions of the process): the code seglist is **not** unloaded (for a Workbench
tool the Workbench does it when the WBStartup message comes back, `workbench-task-v34.md` §3.5);
`pr_CIS`/`pr_COS` are not closed; `pr_CurrentDir` is not unlocked (CreateProc gives the child the
parent's lock without DupLock, cf. `loadwb-13.md`); `pr_MsgPort` is not emptied; the code in D0 is not
stored anywhere (V34 has no exit code field). [O]

### 1.5 Workbench-started tools [O/D]

- The process is a plain C CreateProc process (§1.2). Exit(code) ends it via `endtask`; the code is lost.
- The tool must reply the WBStartup message **before** ending (classic sequence: Forbid, ReplyMsg,
  then return/Exit, the Forbid lasting until RemTask). If it calls Exit without replying, the Workbench
  never sees the message again: the segment is never unloaded and the arguments never freed. [D]
- Calling Exit while still holding a Forbid is fine: RemTask switches away. [D]

### 1.6 Edge cases [O/D]

- Caller is a plain Task (not a Process): `pr_ReturnAddr` is read beyond the Task structure ⇒ wild
  stack pointer, crash. [D]
- Process whose `pr_ReturnAddr` is 0 (process built by hand): SP becomes −4 ⇒ crash. [D]
- Exit from inside an exec exception/interrupt context: undefined. [D]

### 1.7 Test vectors [D]

| Scenario | Expected |
|---|---|
| CLI: C command calls Exit(7) after setting IoErr 205 | `cli_ReturnCode` = 7, `cli_Result2` = 205, next prompt normal (interactive) |
| Execute script (non-interactive), `failat` 10: command calls Exit(20) | "<name> failed returncode 20", rest of the script skipped |
| CLI: C command calls Exit(0) from a deeply nested routine with 2 KB of local stack | back at the prompt, stack freed, no leak beyond what the program itself allocated |
| CreateProc'd process calls Exit(5) | process disappears from the task lists; its segment remains loaded; creator gets no notification |

---

## 2. WaitForChar (LVO −204)

### 2.1 dos side (global 87) [O]

- Entry: **D1 = FileHandle (BPTR)**, **D2 = timeout (microseconds)**. Return in D0 (via the bridge).
- If `fh_Type` (FileHandle +$08, handler MsgPort) = **0** (e.g. `NIL:`): returns **0** immediately; no
  packet; **pr_Result2 unchanged**.
- Otherwise: synchronous `sendpkt` to `fh_Type` with:

| Packet field | Value |
|---|---|
| dp_Type | **20** (ACTION_WAIT_CHAR) |
| dp_Arg1 | **timeout** (D2), unchanged |
| dp_Arg2… | not meaningful (stale frame contents) |

- Returns **dp_Res1 as is** (no normalisation to −1/0), and `pr_Result2` := dp_Res2 (sendpkt rule).
- `fh_Interactive` is **not** tested, and `fh_Arg1` is **not** sent: the handler cannot tell which of its
  streams is meant. The call blocks the caller until the handler replies. [O]

### 2.2 ROM console handler (CON:/RAW:) [O]

The handler keeps a **read buffer** (characters ready for ACTION_READ) separate from the line being
edited.

- **Availability rule**: "data available" ⇔ the read buffer is non-empty.
  - cooked mode (CON:): characters typed enter the read buffer only when the line is terminated by
    **Return** (CR, stored as LF) — or by Ctrl-\ (end of file), which moves the edited text in but adds
    no character. So WaitForChar returns TRUE only once a **whole line** is ready. A Ctrl-\ on an
    empty line makes nothing available (WaitForChar stays FALSE although the next Read returns 0);
  - raw mode (RAW:, or after ACTION_SCREEN_MODE 994 with Arg1 ≠ 0): every incoming character goes
    straight to the read buffer ⇒ TRUE after any key.
- **Packet handling** (on reception of ACTION_WAIT_CHAR):
  1. data available ⇒ reply at once, **dp_Res1 = −1**;
  2. else timeout = 0 ⇒ reply at once, **dp_Res1 = 0**;
  3. else: opens **timer.device unit 0 (UNIT_MICROHZ)** on a handler-private request, keeps the packet
     as "pending wait", sends `TR_ADDREQUEST` (9) with **tv_secs = timeout / 1 000 000, tv_micro =
     timeout mod 1 000 000** (signed division), and does not reply yet.
- **Completion of a pending wait** (checked after each event the handler processes):
  - data becomes available **and no ACTION_READ is pending** ⇒ AbortIO of the timer request, reply
    **−1**; when the aborted request comes back the timer device is closed;
  - the timer request completes first ⇒ reply **0**, close timer.device.
  - If a READ is pending when the line arrives, the line goes to the READ; the wait stays pending until
    more data arrives or the timer expires. [O]
- **dp_Res2** in all these replies is **not set** by the handler (stale value) ⇒ IoErr() after
  WaitForChar on a console is meaningless. [O]
- One pending wait at a time: a second WAIT_CHAR arriving while one is pending replaces the stored
  packet (the first is never answered) and re-arms the same timer request while it is still in flight —
  undefined. [D]
- Negative timeout: passes the ≠ 0 test, gives a negative tv_secs/tv_micro — undefined timer
  behaviour. [D]

### 2.3 Other handlers [O]

- ROM file system (DF0: etc.): action 20 is not in its dispatch ⇒ **dp_Res1 = 0, dp_Res2 = 209**
  (ERROR_ACTION_NOT_KNOWN). WaitForChar on a disk file therefore returns 0 and IoErr() = 209.
- `NIL:`: 0, no packet (§2.1).
- Disk-based handlers (Newcon-Handler, Ram-Handler, Aux-Handler, Pipe-Handler) were not examined [—].

### 2.4 Users on the Workbench 1.3.3 disk [O]

- **System/DiskCopy** (CLI mode): `WaitForChar(fh, 30)` on its console handle, in a loop that reads one
  character per TRUE answer — it **drains type-ahead** before prompting, then does a blocking Read.
  With the cooked-mode rule above, a pending typed line is discarded.
- **Utilities/More** and **System/Format** link the amiga.lib WaitForChar stub (D1/D2 convention). [O for
  the stub presence; D that it is called]
- No BCPL command of the disk uses global 87.

### 2.5 Test vectors [D]

| Scenario | Expected |
|---|---|
| WaitForChar(Input(), 0) on an idle CON: | 0 immediately |
| WaitForChar(Input(), 2 000 000) on CON:, nothing typed | 0 after ~2 s |
| same, user types "ab" without Return | 0 after ~2 s |
| same, user types "ab" + Return after 0.5 s | −1 at ~0.5 s; next Read returns "ab\n" |
| WaitForChar on a RAW: handle, one key after 0.5 s | −1 at ~0.5 s |
| WaitForChar(Open("NIL:",…), 100) | 0, IoErr unchanged |
| WaitForChar on a file of DF0: | 0, IoErr = 209 |

---

## 3. GetPacket (−162) and QueuePacket (−168)

### 3.1 What the vectors really do [O]

The two vectors exist (dos has 37 vectors, `dos-v34-spec.md` §5) but are wired through the bridge to
BCPL globals **−20** and **−21**, which are unrelated utilities:

| LVO | Name (fd) | Global | Real behaviour with the C registers |
|---|---|---|---|
| −162 | GetPacket(wait) (D1) | −20 `clearvec(v, n)` | if **D2 ≥ 0**: clears **D2 + 1 longs** starting at byte address **D1 × 4**; D2 < 0: nothing. Returns D0 = **D1 × 4** if D2 ≥ 0, otherwise D1 unchanged. |
| −168 | QueuePacket(packet) (D1) | −21 (segment load without requester) | treats **D1 as a BPTR to a BSTR name**; saves `pr_WindowPtr`, sets it to **−1** (no requesters), loads the file with the BCPL `load` (global 81), restores `pr_WindowPtr`. Returns the **seglist BPTR** (0 on failure, IoErr from the load). |

- Neither touches `pr_MsgPort`, `pr_PktWait` or any packet; neither waits for a message. A caller
  that follows the 2.0 documentation (GetPacket = take a packet from the process port) gets **random
  memory clearing** (D2 is whatever the caller left there). [O]
- The BCPL runtime itself uses −20 (clearing vectors) and −21 (command lookup by the CLI, C:FAULT
  lookup) internally through the GV, not through the LVOs (`bcpl-runtime-v34.md` §8.3). [O]

### 3.2 Users on the Workbench 1.3.3 disk [O]

- All hunk executables of the disk (c/, l/, libs/, devs/, System/, Utilities/, Prefs/…) were scanned for
  calls to offsets −162/−168 (both `jsr` and `jmp` forms). Every hit uses another library base: exec
  (`serial.device`, SetIntVector pattern) or a non-dos register pattern (Preferences). **No program
  calls dos −162 or −168.** BCPL programs never use LVOs.
- Packet-level code of the disk (handlers, DiskCopy) talks to ports directly with PutMsg/WaitPort/GetMsg
  and `dp_Port`, not through these vectors.

### 3.3 Implementation guidance [D]

- A reimplementation may give −162/−168 any harmless behaviour for 1.3 software; reproducing
  `clearvec` through the public vector is not required by any known program. The internal globals −20
  and −21 must keep their BCPL semantics for the CLI and C:FAULT.
- Returning 0 from both vectors without side effects is the safest choice.

---

## 4. Open points

- Behaviour of disk-based handlers (Newcon-Handler from L:, Ram-Handler, Aux-Handler, Pipe-Handler) for
  ACTION_WAIT_CHAR: not examined.
- The interaction "WAIT_CHAR pending + ACTION_READ arriving later" was read but not probed: it should
  be checked with a black-box probe (a probe description is in the analysis report, not here).
- The callers of the WaitForChar stub in More/Format were not traced (presence of the linked stub only).

## Clean-room review

- [x] No instruction sequence transcribed or paraphrased; no ROM address or offset inside the ROM. The
  routines are described as inputs, outputs and ordered observable effects.
- [x] Values given are ABI/interoperability elements: LVOs, BCPL global numbers, structure offsets of
  Process (+$80/+$88/+$B0/+$B8) and FileHandle (+$08), packet type and argument use, timer.device
  unit/command, error code 209, alert $07000005.
- [x] Workbench binaries were only scanned for library call offsets in a scratch copy; no code from them is
  reproduced.
