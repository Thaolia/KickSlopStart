# bcpl-runtime-v34.md — BCPL runtime of dos.library V34 (behavioural spec)

> ANALYSIS track ("dirty"). Sources: the ROM `assets/kick34005.A500` (dos 34.3) and the
> `c:` / `l:Shell-Seg` commands of the disk `assets/wb133.adf` (Workbench 1.3.3).
> Downstream goal: allow our ROM to run the BCPL commands of Workbench 1.3
> (AddBuffers, CD, Path, Execute, Run, Wait, Resident, Mount, EndCLI, Shell-Seg).
>
> **Certainty legend** (on each statement):
> **[O]** observed directly (ROM or WB binary) · **[D]** deduced from converging observations ·
> **[S]** assumed (plausible, not verified).
> Provenance: **ROM** = Kickstart, **WB** = binary from the Workbench disk.
>
> This document describes behaviours, ABI layouts, global numbers and
> constants. **No instruction sequence is reproduced or paraphrased**, and no ROM address is
> cited (removed on 2026-10-29).

---

## 0. Executable summary (what must absolutely be respected)

1. **The CLI does not distinguish** a BCPL executable from a C/asm executable. It always calls the
   first hunk with the same convention (§4). The "BCPL side" of a 1.3 `c:` command is carried
   by **its own hunk 0** (316-byte startup stub, identical in the 14 commands
   examined), which builds itself a **private global vector** then calls its global 1 (§3.3).
2. This stub **requires** on entry: A2 = a valid GV containing at least the globals
   **28 (globin), 29 (getvec), 89 (findsegarray)**; A5/A6 = BCPL call/return routines;
   the process's `pr_SegList` = a **segarray** whose entries 1..`V!0` are segments in
   **BCPL format** (global init table at the end of the hunk) which provide the whole runtime
   (including global **134 findCLI**, **30 freevec**). [O WB + D]
3. The arguments of a BCPL command are read by `rdargs`/`rditem` **via `rdch` on `input()`**.
   The CLI has **temporarily replaced the buffer** of the input FileHandle with a copy of the rest of
   the line (fh_Buf/fh_Pos=0/fh_End=n). The same copy is passed in A0/D0 to C programs. (§5) [O ROM]
4. Globals **134..149** of a command's private GV are a **copy of the 16 longs of the
   `CommandLineInterface`**: copied on entry, **copied back into the real structure on return**.
   This is how Failat/Prompt/Stack/Path/CD/Execute/EndCLI modify the CLI. (§3.3, §8) [O WB]

---

## 1. BCPL calling conventions (confirmation / corrections of the public table)

### 1.1 Registers [O ROM + WB]

| Register | Role | Status |
|---|---|---|
| A0 | **always 0** (addressing base: BCPL memory accesses are done as "0 + byte address", address = BPTR×4) | [O] |
| A1 | current BCPL frame pointer (byte address, not a BPTR) | [O] |
| A2 | (byte) address of **slot 0** of the current global vector | [O] |
| A4 | entry address of the routine **currently executing** (serves as the base for strings and PC-independent local calls) | [O] |
| A5 | **call** routine; A5+$10 = multiply, A5+$12 = divide | [O] |
| A6 | **return** routine; a BCPL routine gives control back by a jump to A6 | [O] |
| D0 | at the call: **size in bytes of the caller's frame** = offset of the new A1 relative to the current one | [O] |
| D1–D4 | first 4 arguments; **D1 = result** on return | [O] |
| A7 | 68000 stack; **unchanged** across a BCPL call (the call routine immediately removes the return address pushed by the `jsr`) | [O] |

Registers not preserved by a call: D0, D2–D7, A3 (scratch). A0 must stay 0; A2/A5/A6 are
invariant; A1/A4 are restored by the return routine. [D]

### 1.2 Frame [O ROM]

On a call with D0 = *t*: the new frame starts at `A1 + t`. The call routine stores, in
the 3 longs **preceding** the new frame:

| Offset / new frame | Contents |
|---|---|
| −12 | A1 of the caller (caller's frame) |
| −8 | return address |
| −4 | **A4 of the callee** = entry address of the routine owning this frame |

then stores D1..D4 at offsets 0, 4, 8, 12 of the new frame and jumps to A4.
Arguments 5, 6, … are written **by the caller** directly into memory at offsets 16, 20, …
of the future frame (= `A1_caller + t + 16`, …) before the call. There is **no limit** on the
number of arguments (writef, sendpkt use ≥ 6).

On return (jump to A6): A1 and the return address are re-read at offsets −12/−8 of the current
frame, then **A4 is re-read at offset −4 of the caller's frame** (so A4 recovers the entry
of the calling routine).

> **Correction of the public table**: "−4 = old A4" is imprecise. Slot −4 of a frame
> contains the **entry of the routine that owns the frame** (A4 of the callee), and A4 is restored
> from the frame **of the caller**. [O ROM]

### 1.3 Arithmetic (A5+$10, A5+$12) [O ROM]

- **A5+$10 multiply**: D1 := D1 × D2 (low 32 bits, sign irrelevant). The other registers are preserved.
- **A5+$12 divide**: **signed** division, quotient truncated towards 0 in **D1**, remainder in **D2** (sign
  of the remainder = sign of the dividend, C semantics). Both results are usable.
- A5+$14 exists (internal variant "divisor assumed ≥ 0"); no command examined
  uses it. The WB commands only use +$10 and +$12. [O WB]

### 1.4 LVO → BCPL bridge (for the record) [O ROM]

Each public dos LVO vector (−30 Open … −222 Execute) loads a **global number** then
jumps into a common bridge which: saves D2–D7/A2–A6 on the C stack, sets A0 = 0, installs a BCPL
frame **1500 bytes ($5DC) below the current SP** (even-aligned), loads A2/A5/A6 from
`dl_A2`/`dl_A5`/`dl_A6` (base +$2A/+$2E/+$32), calls the global with D1–D4 **as supplied
by the C caller**, and returns D1 in D0. Consequence: any C caller of a dos LVO must
have at least ~1.5 KB of free stack. Observed LVO → global correspondence:

| LVO | Function | Gl. | | LVO | Function | Gl. |
|---|---|---|---|---|---|---|
| −30 | Open | −1 | | −132 | IoErr | −17 |
| −36 | Close | **93** | | −138 | CreateProc | −18 |
| −42 | Read | −3 | | −144 | Exit | **2** |
| −48 | Write | −6 | | −150 | LoadSeg | −19 |
| −54 | Input | **65** | | −156 | UnLoadSeg | **82** |
| −60 | Output | **66** | | −162 | GetPacket | −20 (!) |
| −66 | Seek | −8 | | −168 | QueuePacket | −21 (!) |
| −72 | DeleteFile | −9 | | −174 | DeviceProc | −22 |
| −78 | Rename | −10 | | −180 | SetComment | −23 |
| −84 | Lock | −11 | | −186 | SetProtection | −24 |
| −90 | UnLock | **109** | | −192 | DateStamp | −25 |
| −96 | DupLock | **113** | | −198 | Delay | **47** |
| −102 | Examine | −12 | | −204 | WaitForChar | **87** |
| −108 | ExNext | −13 | | −210 | ParentDir | **35** |
| −114 | Info | −14 | | −216 | IsInteractive | −26 |
| −120 | CreateDir | −15 | | −222 | Execute | −27 |
| −126 | CurrentDir | −16 | | | | |

(!) **V34 anomaly**: global −20 is `clearvec` (BCPL utility) and −21 serves as "LoadSeg
without requester"; the 1.3 GetPacket/QueuePacket LVOs therefore end up in functions unrelated
to their documented name. [O ROM for the wiring, D for −21]

The **negative** globals are "C ABI" adapters (C arguments: C strings, APTR); the
positive ones are the BCPL ABI (BPTR/BSTR). The positive globals cited in bold are shared: the LVO
calls the BCPL global directly (arguments already in BPTR format, e.g. FileHandle/lock). [O]

---

## 2. Q1 — The global vector (GV)

### 2.1 General format [O ROM + WB]
- A GV is a block of longs indexed from **−N_neg to +N_max**. A2 (and `dl_GV`, `pr_GlobVec`)
  point to **slot 0** (byte address, not BPTR).
- **GV[0] = number of the highest allowed global** ("slot count"). `globin` refuses
  to install a global with a number > GV[0] (signed comparison: negative numbers always
  pass). [O ROM]
- Negative part: **50 longs** (slots −50..−1) in all the GVs observed (dos and commands). [O]

### 2.2 The dos GV (`dl_GV`) [O ROM]
- Allocated by dos's init code (rt_Init): a block `AllocMem(804 bytes = 201 longs,
  MEMF_PUBLIC)` **not cleared**; `dl_GV` (base+$26) = start of the block + 200 bytes (50 negative
  longs) → slots −50..+150. **GV[0] = 150**.
- Undefined slots keep **the undefined contents of the memory** (no filling). [O]
- It is filled by `globin` of the ROM's BCPL segments when the **first process** starts
  (§2.4).
- It is **the same GV** as: the first process ("Initial CLI"), all the CLIs created by
  Run/NewCLI (which pass their parent's GV, cf. §8), and the LVO bridge. [O ROM + WB]
- **Shared GV ≠ command GV**: a BCPL command **never** works in `dl_GV`; its
  stub creates a private GV (§3.3). The CLI process's `pr_GlobVec` is not modified during the command. [O WB]

### 2.3 Storage [O ROM]
- `pr_GlobVec` (process +$88) = **APTR** (byte address of slot 0), not a BPTR. (Run reads it
  back and converts it to a BPTR before passing it to createproc.) [O]
- `dl_GV` (DosLibrary +$26) = APTR likewise. `dl_A2` (+$2A) = same value; `dl_A5` (+$2E) / `dl_A6`
  (+$32) = addresses of the call / return routines. [O]

### 2.4 Segarray (`pr_SegList`) and initialisation [O ROM]
- `pr_SegList` (process +$80) = **BPTR to a "segarray"**: `V!0 = n`, `V!1..V!n` = BPTRs of
  segment chains. Global 89 (`findsegarray`) returns it.
- ROM segarray: `V!0 = 4`, but **7 useful entries**:
  1. BCPL kernel (chain of 4 segments: memory, process, I/O devices, coroutines, strings…),
  2. dos ("BLIB": streams, rdargs, writef, files…),
  3. `cliinit` (global 133; startup-sequence, CON: window…),
  4. the **CLI** (global 1),
  5. console-handler, 6. file system (chain of 10 segments, globals up to 266), 7. validator.
  Only entries 1..4 (`V!0`) are "installed" in the GVs; 5..7 serve as segments
  for other processes (handlers). [O for the contents, D for the exact role of 5..7]
- Start of a BCPL process (created by global 33): filling of its stack with the pattern
  **$ABABABAB**, creation of the BCPL base frame at the **bottom** of the stack (`!1 = −1`, `!2` = upper
  limit), GV[12] := BPTR of that base, then `globin(V!i)` for i = 1..V!0 into **pr_GlobVec**,
  then **wait for the startup packet** (taskwait), then `start(pkt)` (global 1, frame of 32
  bytes). On return from start: end of the process. [O]
- The first process is created by the dos init with: ROM segarray, stack **400 longs (1600
  bytes)**, pri 0, BSTR name **"Initial CLI"**, GV = `dl_GV`. [O]

---

## 3. Q3 — Format of a BCPL segment, `globin`, command stub

### 3.1 Format of a BCPL hunk [O ROM + WB]
For a code hunk of *N* longs (the loaded data of the hunk, i.e. `BADDR(seg)+4`):

| Position (in longs, from the start of the hunk's data) | Contents |
|---|---|
| 0 | **N** = length of the section in longs (equal to the size of the hunk) |
| 1 … | code (the global 1 routine typically starts at byte 4) |
| … | (BSTR strings aligned on 4, data) |
| N−2k−2 | **0** (terminator) |
| N−2k−1, N−2k | pair k: **global number**, then **byte offset** |
| … | … other pairs (number at the lower address, offset at the higher address) |
| N−1 | **highest global referenced** by this segment |

- The **offset is relative to the start of the hunk's data** (the "N" long), in bytes. Value
  installed = absolute address `BADDR(seg)+4+offset` (a **machine address**, not a BPTR). [O]
- Examples [O WB]: AddBuffers (127 longs): pair (1, $4), max 102. CD: (84, $2B8), (1, $4),
  max 153. Execute: (166, $582), (1, $4), max 168. Resident: (1, $CC), max 109.
  Shell-Seg (1 hunk of 1770 longs): (1, $4), max 133.
- A BCPL command executable = ordinary hunk file (HUNK_HEADER/HUNK_CODE), **without
  relocations** in the cases examined, with two hunks: hunk 0 = stub (79 longs), hunk 1 = the
  BCPL module in the format above. Nothing in the file marks it as "BCPL" (no magic). [O]

### 3.2 `globin(seg)` — global 28 (GV +$70) [O ROM]
- Walks the **chain** of segments starting from `seg` (BPTR; follows the link at the head of each
  segment until 0). For each segment, walks the table from the end (skipping the "max"
  long) towards the 0 terminator, and for each pair writes `GV[num] := address`.
  `seg = 0`: nothing to do, success.
- **No check** of the "max" long; the only check: `num > GV[0]` → failure.
- Returns **−1 (TRUE)** if everything is installed; otherwise **0** with **Result2 = 111** (value not
  publicly documented). The pairs already processed before the error remain installed.
- The pairs are processed from the last to the first: if the same number appears twice,
  **the pair at the lowest address wins**. [D]

### 3.3 Startup stub of the `c:` commands (hunk 0, 316 bytes) [O WB]
Identical (md5 `d6b59e0e42e7bc95b5f0dd07c9697e85`) in AddBuffers, CD, Echo, EndCLI, Execute,
Failat, Mount, NewCLI, Path, Prompt, Resident, Run, Stack, Wait. Observable effects, in order:

1. Reads the process's segarray via global **89** of the calling GV (A2 on entry).
2. Computes `max` = the largest of the "max" longs of the hunks **of the command** (hunks following the
   stub in the seglist), with a **floor of 149**. (The ROM segments are not taken into account.)
3. Allocates via global **29** of the calling GV a vector of `max + 50` longs (→ 50 negative slots
   + slots 0..max). Failure → the command returns **−1** in D0.
4. Initialises **GV[0] = max** and **GV[i] = $474C0001 + 2·i** for i = 1..max ("GL" marker +
   odd number: calling an undefined global jumps to an **odd** address → 68000 address
   error). **The negative slots are not initialised** (except by globin afterwards).
5. Builds the base BCPL frame **at the bottom of the command's stack**: base = (entry A7 + 8)
   − stack size in bytes (read at 4(A7) on entry); `base!1 = −1`, `base!2 = base + size
   − 160` (limit); **GV[12] := BPTR(base)** ("currco"/stackbase).
6. With global **28** of the **calling** GV (but A2 = new GV), installs: entries
   1..`V!0` of the segarray (the runtime), then the command's seglist (starting from hunk 1). Any
   failure → D0 = −1.
7. Calls global **134** (findCLI) of the **new** GV. If non-zero: copies the **16 longs** of
   the `CommandLineInterface` into **GV[134..149]**.
8. Replaces **GV[2] (stop)** with its own exit routine (stop(n) makes step 9 return
   with code n, whatever the nesting level — A7 not having moved).
9. Calls **GV[1] (start)** with D1 = 0, frame of 32 bytes. Normal return ⇒ return code **0** (the
   D1 returned by start is **ignored**); exit by stop(n) ⇒ code **n**.
10. If step 7 had found a CLI: **copies GV[134..149] back into the `CommandLineInterface`**.
11. Frees the private GV (global 30 of the new GV) and returns (`rts`) with the code in **D0**.

Correspondence GV[134+i] ↔ CLI field (offset 4·i) [O WB by use: Failat→139, Prompt→140,
Stack→147, Path→136, CD→135, EndCLI→141/142/145, Execute→142/143]:

| Gl. | CLI | Gl. | CLI | Gl. | CLI | Gl. | CLI |
|---|---|---|---|---|---|---|---|
| 134 | Result2 | 138 | CommandName | 142 | CurrentInput | 146 | CurrentOutput |
| 135 | SetName | 139 | FailLevel | 143 | CommandFile | 147 | DefaultStack |
| 136 | CommandDir | 140 | Prompt | 144 | Interactive | 148 | StandardOutput |
| 137 | ReturnCode | 141 | StandardInput | 145 | Background | 149 | Module |

The commands also use globals **≥ 150** as private static variables (CD 150–153,
Execute 150–168, Mount 150–158) — hence the point of the private GV. [O WB]

### 3.4 Distinguishing BCPL / C [O ROM]
- **The CLI makes no difference**: it loads (LoadSeg), then calls the first hunk via
  global 121 (§4) in all cases.
- `dn_GlobalVec` (DeviceNode) is dos's only "BCPL flag", and only concerns the
  **handlers** launched by dos (cf. `dos-v34-spec.md`), not the commands.
- A directly BCPL segment **without stub** (e.g. `l:Shell-Seg`, the ROM CLI, the handlers) is only
  executable as a **segarray entry of a process** (createproc + globin at startup), not
  as a command. [O/D]

---

## 4. Q4 — Launch of a command by the CLI

### 4.1 Lookup [O ROM]
- Name read by `rditem` into `cli_CommandName` (buffer of 25 longs → ≤ 103 characters). Empty item
  → line ignored; error → message "Error in command name".
- Lookup: current directory, then each node of the **`cli_CommandDir` path** (list of nodes
  `!0` = next BPTR, `!1` = lock), then `C:` (via deviceproc + the lock returned in Result2). A
  second pass takes place if the failure is not 218 (device not mounted). **No Resident list** in
  the ROM CLI (it is Shell-Seg that manages it). [O]
- Not found: if the error is 205 (object not found) or 218 → "Unknown command %S"; otherwise
  "Unable to load %S: " + error message (global 104). [O]

### 4.2 Preparation (CLI-local "run" routine) [O ROM]
1. Reads characters after the name (the name's terminator was put back by `unrdch`), skips blanks
   and tabs, handles the redirections **`<file`** (findinput) and **`>file`**
   (findoutput) — only **before** the arguments; a second redirection in the same direction →
   "too many > or <"; open failure → "Unable to open redirection file".
2. Copies **the rest of the line** (up to the `\n` included or EOF) into a local buffer of **256
   bytes** (overflow → "command too long") with these rules:
   - `"` toggles the "inside quotes" state (the `"` is copied);
   - `;` outside quotes **stops the copy** (comment), reading continues up to the `\n`;
   - `+` immediately followed by `\n`: the `\n` is copied **and reading continues on the next
     line** (continuation); `+` otherwise: copied as is;
   - the final `\n` is copied (unless it falls inside a comment).
3. The command's input = the `<` file otherwise **`cli_StandardInput`** (not CurrentInput: in an
   Execute script, the command reads the console). Output = the `>` file otherwise the current `output()`.
4. **Injection of the arguments**: saves `fh_Buf`, `fh_Pos`, `fh_End` of the input FileHandle,
   then `fh_Buf` := BPTR of the local buffer, `fh_Pos` := 0, `fh_End` := *n* (bytes copied).
   `selectinput`/`selectoutput` on these streams; **pr_Result2 := 0**.
5. Call `runcommand(seg, cli_DefaultStack, BPTR buffer, n)` (global 121).
6. On return: restores `fh_Buf` (only if it still points to the local buffer) and `fh_Pos`;
   restores `fh_End` **unless it is 0** (a command can force EOF, cf. EndCLI); closes the
   possible `<`/`>` files.

### 4.3 `runcommand(seg, stack, args, len)` — global 121 (GV +$1E4) [O ROM]
- Allocates the stack by `getvec(stack)` (stack in **longs**; failure → returns **−1** without calling).
- Top of stack = end of the vector. On the new stack (from top to bottom): the old A7, then the
  **stack size in bytes** (= stack×4); **`pr_ReturnAddr` := address of this "size" long**
  (the old value is saved and restored on return).
- Call by `jsr` of `BADDR(seg)+4` (first hunk). **State on entry to the command**:

| Element | Value |
|---|---|
| (A7) | return address |
| 4(A7) | stack size in bytes (= cli_DefaultStack × 4) |
| 8(A7) | (internal: old A7) |
| A0 | byte address of the copy of the arguments |
| D0 | length of the arguments (**includes** the final `\n`) |
| D2 | stack size in bytes (same value as 4(A7)) [O, not contractual] |
| A1 | caller's BCPL frame (in the CLI's stack) |
| A2 | GV of the CLI (= `dl_GV` for the ROM CLI) |
| A5 / A6 | BCPL call / return routines |
| A3 | BADDR(seg) [O, not contractual] |
| input()/output() | streams prepared in §4.2, input buffer = arguments |
| pr_Result2 | 0 |

- **BCPL stack = 68000 stack**: same memory block. The BCPL stub builds its frames **from the bottom**
  (start of the getvec vector) upwards, while A7 goes down from the top. [O WB]
- The program gives control back by `rts` with **D0 = return code**. `runcommand` itself restores
  A1/A2/A5/A6, `pr_ReturnAddr` and the old A7: the command has **no register to preserve**. [O]
- Early exit: global 2 of `dl_GV` (= LVO Exit) resets A7 to `pr_ReturnAddr − 4` and
  executes an `rts` with D0 = code → return to the same point as the normal `rts`. [O]
- Frees the stack, returns the code in D1. **Does not touch pr_Result2.** [O]

### 4.4 After the command (CLI) [O ROM]
- `cli_ReturnCode` := code; `cli_Result2` := pr_Result2 if code ≠ 0, otherwise 0.
- `selectoutput(cli_StandardOutput)`, `selectinput(cli_CurrentInput)`.
- If code ≥ `cli_FailLevel` **and CLI not interactive**: displays "%S failed returncode %N", then
  handles the current input **as at end of file** (abandon of the Execute script, §4.5). In
  interactive mode, no effect (neither message nor abandon).
- Resynchronises on the end of line: `unrdch()` then reads up to `\n`/EOF (normally only 1
  character, since the line has already been consumed by step §4.2).
- `unloadseg(cli_Module)`, `cli_Module` := 0.
- Code **−1** = special case "cannot be launched" (treated as a load failure).

### 4.5 Loop and end of stream of the CLI [O ROM]
- `cli_Interactive` := (not `cli_Background`) **and** (`cli_StandardInput` = `cli_CurrentInput`).
- Interactive: writes character 15, then `writef(cli_Prompt, task number)`, then `wrch(0)`
  (the NUL forces the flush of the console buffer). Non-interactive: tests CTRL-D →
  "**BREAK - CLI" and abandon of the script.
- EOF on the current input:
  - script (CurrentInput ≠ StandardInput): closes the script, **deletes `cli_CommandFile`** if it
    is not empty (Execute's temporary file) then empties it, returns to StandardInput,
    **FailLevel := 10**;
  - console, non-Background CLI: `fh_End` := −1 on stdin (the next read asks the
    handler again) and writes 1 at offset $24 of the FileHandle [O, meaning not elucidated];
  - **Background**: end of the CLI (flush of the output, closings, freeing of the path
    list, `rn_TaskArray[n]` := 0, end of the process).

---

## 5. Q5 — Reading the arguments: streams, rdargs, rditem

### 5.1 FileHandle as seen by the BCPL runtime [O ROM]
FileHandle = `getvec` vector of **11 longs** (44 b) + getvec header, allocated cleared:

| Off. | Field | Runtime use |
|---|---|---|
| $04 | fh_Interactive (fh_Port) | ≠ 0 ⇒ interactive stream (returned as is by IsInteractive, gl. −26) |
| $08 | fh_Type | MsgPort of the handler (0 for NIL:) |
| $0C | fh_Buf | **BPTR** of the buffer |
| $10 | fh_Pos | **byte** index of the next character |
| $14 | fh_End | byte index of the end of data (read) / capacity (write) |
| $18 | fh_Funcs | **machine address** of a BCPL "fill" routine (read) |
| $1C | fh_Func2 | address of a BCPL "flush" routine (write) |
| $20 | fh_Func3 | address of a BCPL "close" routine |
| $24 | fh_Args | handler argument (fh_Arg1) passed in the packets |

- On open (`findinput`/`findoutput`, mode 1005/1006): `fh_Pos = fh_End = −1`, the three
  routines installed. `*` → console (`pr_ConsoleTask`); `NIL:` → no handler, routines at 0
  (read = immediate EOF, write = characters ignored). Otherwise deviceproc + packet
  ACTION_FINDINPUT/OUTPUT (arg1 = FileHandle, arg2 = lock returned by deviceproc, arg3 = name). [O]
- Buffer allocated **lazily** at the first fill/flush: `getvec(49)` = **200 bytes**.
  Fill = Read of ≤ 200 bytes; `fh_Pos` := 0, `fh_End` := bytes read. Allocation failure:
  EOF, Result2 = 103. [O]
- Close (global 93 = LVO Close): flushes if necessary, frees the buffer, sends ACTION_END
  (1007, arg1 = fh_Args) (with retry requester), then **freevec of the FileHandle** (Result2
  preserved). Clarification: flush, freeing of the buffer and ACTION_END are done by the
  **fh_Func3** routine; endstream only calls it if it is non-zero, then always does the freevec
  of the FileHandle (case of Run's memory FileHandle, §13.6.4). [O ROM]
  ⇒ FileHandles must be **getvec** blocks (size header at −4). [O]

### 5.2 rdch / unrdch [O ROM]
- **rdch()** (54) **always** operates **on `input()`**. If `fh_Pos < fh_End`: returns the byte
  `buf[fh_Pos]` (unsigned) and increments `fh_Pos`. Otherwise: if `fh_End = 0` → **−1 (EOF)** without
  contacting the handler; otherwise calls fh_Funcs; success → returns the first byte (fh_Pos = 1);
  failure → `fh_Pos = fh_End = 0` and −1.
- **unrdch()** (55): if `fh_Pos > 0` → `fh_Pos−1`, returns TRUE; otherwise returns TRUE iff
  `fh_End = 0` ("re-readable" EOF), FALSE otherwise.
- Consequence for the injection of arguments: a command reads exactly the *n* copied bytes;
  reading beyond triggers a real fill from the handler (this is how rdargs's `?`
  re-reads a line from the keyboard). [D]

### 5.3 rditem(v, size) — global 79 (GV +$13C) [O ROM]
- `v` = BPTR of a vector of *size*+1 longs, **cleared** at the start (clearvec); the item is
  stored in it as a **BSTR** (length in byte 0). Capacity: (size+1)·4 − 1 characters.
- Skips blanks/tabs. Initial `"` ⇒ quoted item.
- Unquoted: ends on `\n`, EOF, `;`, space, tab or `=`; the terminator is **put back**
  (unrdch).
- Quoted: ends on the closing `"` (consumed, **not** put back); `*N`/`*n` → LF, `*E`/`*e` →
  ESC (27), `*x` → literal x; `\n`/EOF before the closing `"` ⇒ error.
- Results: **1** normal item; **2** quoted item; **0** end (nothing read before `\n`/`;`/EOF —
  terminator put back); **−2** `=` encountered without an item (the `=` is consumed); **−1** error
  (overflow or unclosed quote).

### 5.4 rdargs(template, argv, size) — global 78 (GV +$138) [O ROM]
- Arguments: D1 = **BSTR** of the template, D2 = **BPTR** argv, D3 = size of argv in **longs**.
- **Template**: keys separated by `,`; aliases by `=` (`SEC=SECS/S`, `TO=AS`); case-insensitive
  qualifiers `/A` (mandatory), `/K` (keyword required), `/S` (switch). **Empty names
  are allowed** (pure positional key: Path `",,,,,,,,,,ADD/S,SHOW/S,RESET/S,QUIET/S"`, Wait
  `",SEC=SECS/S,MIN=MINS/S,UNTIL/K"`). An empty template `""` consumes the line (EndCLI).
- **Result vector**: `argv!i` (i = 0..nkeys−1) =
  - **0**: key absent (after the /A check);
  - **−1**: /S switch present;
  - otherwise **BPTR of a BSTR** stored in the **free area of argv** (starting at `argv!nkeys`).
  During parsing, `argv!i` temporarily contains the key's flags (bit0 /A, bit1 /K,
  bit2 /S), hence the value 0..7 tested for "not filled".
- Observable algorithm: each unquoted item is first looked up as a keyword (findarg,
  case-insensitive, aliases included). /S keyword → −1. Other keyword → the **next** item
  (possibly after `=`) is its value. Otherwise (or quoted item) → positional value assigned
  to the **first unfilled key that is neither /K nor /S**. A non-key item equal to `?` followed by `\n` →
  writes `"<template>: "` and continues parsing on a new read.
- End (rditem = 0): any unfilled /A key ⇒ error; otherwise consumes the terminator
  (`\n` or `;`) and returns **non-zero** (BPTR of the first free long of argv).
- Error (unknown extra key, missing /A, item too long, no more room): **skips the rest
  of the line** up to `\n`, `;` or EOF, **Result2 = 120**, returns **0**.
- [O] The remaining size passed to rditem is computed **once** at the start (not decremented
  as the items go by): an argv that is too small can overflow. To be reproduced as is or hardened.

### 5.5 findarg(template, item) — global 80 (GV +$140) [O ROM]
Returns the (0-based) index of the key one of whose aliases equals `item` (case-insensitive), or −1.

---

## 6. Q6 — Output: wrch, writes, writef, newline…

### 6.1 wrch(c) — global 56 [O ROM]
- Operates on `output()`. If `fh_Pos ≥ fh_End`: calls fh_Func2 (flush) then `fh_Pos` restarts
  at 0; if fh_Func2 is null (NIL:), the character is lost. Stores `c` (low byte) in `buf[fh_Pos++]`.
- Then, if `c < 32` **and** interactive stream **and** `c ∈ {0, 10, 12, 13}`: flushes immediately and
  `fh_Pos := 0`.
- First flush = allocation of the 200-byte buffer (`fh_Pos = 0`, `fh_End = 200`), without writing.
  Following flush = Write of `fh_Pos` bytes. The flush **ignores** write errors and
  preserves Result2. Close = final flush if `fh_Pos > 0`.
- ⇒ Files: buffered by 200, flushed at close. Console: flushed at each LF/CR/FF/NUL.

### 6.2 Write functions [O ROM]

| Gl. | Off. | Function | Semantics |
|---|---|---|---|
| 53 | $0D4 | writet(s, w) | writes the BSTR `s` then spaces up to `w` columns (no truncation) |
| 68 | $110 | newline() | wrch(10) |
| 69 | $114 | writed(n, w) | signed decimal, right-aligned on `w` (spaces before the `-`), no truncation |
| 70 | $118 | writen(n) | writed(n, 0) |
| 71 | $11C | writehex(n, d) | exactly `d` **upper-case** hex digits (leading zeros; d ≤ 1 → 1 digit; high bits truncated) |
| 72 | $120 | writeoct(n, d) | same in octal |
| 73 | $124 | writes(s) | writes the BSTR `s` (D1 = BPTR) |
| 74 | $128 | writef(fmt, a1, a2, …) | see below |

### 6.3 writef [O ROM]
`fmt` = BSTR; the arguments are the consecutive longs following `fmt` in the frame (unlimited
number). Each `%` reads the next letter (case-insensitive):

| Code | Effect | Consumes an arg | Reads a width digit |
|---|---|---|---|
| `%S` | writes(arg) (BSTR) | yes | no |
| `%T` | writet(arg, w) | yes | **yes** |
| `%C` | wrch(arg) | yes | no |
| `%N` | writen(arg) | yes | no |
| `%I` | writed(arg, w) | yes | **yes** |
| `%U` | **unsigned** decimal, width w | yes | **yes** |
| `%X` | writehex(arg, w) | yes | **yes** |
| `%O` | writeoct(arg, w) | yes | **yes** |
| `%$` | **skips** an argument, writes nothing | yes | no |
| other | writes the letter itself (`%%` → `%`) | no | no |

Width digit: `0`–`9` → 0–9; a letter → value `10 + (code − 'A')` (`A`=10, `B`=11…).
Examples: `"%N> "` (prompt), `"[CLI %N]\n"`, `"%S failed returncode %N\n"`, `"%TH %I3"` (Resident:
name on 17 columns, number on 3).

### 6.4 Numeric reading — readn() (67) [O ROM]
Skips spaces/tab/LF, accepts `+`/`-`, reads the decimal digits, puts the next character back.
Success: Result2 = 0, returns the value. No digit: puts the character back, Result2 = −1, returns 0.

---

## 7. Q7 — Coroutines

**No.** None of the commands examined (AddBuffers, CD, Echo, EndCLI, Execute, Failat, Mount,
NewCLI, Path, Prompt, Resident, Run, Stack, Wait) nor `l:Shell-Seg` calls globals 23–27
(createco, deleteco, callco, cowait, resumeco). [O WB] They exist in the ROM kernel (global 12
= current coroutine / stack base, updated by the stub). [O ROM]

---

## 8. Q2 — Table of the globals (ROM V34)

Number → byte offset = 4×n. Units: **BPTR** (address/4), **BSTR** (BPTR to a length-prefixed
string), **APTR** (byte address), **taskid** = address of a process's MsgPort (process+$5C).
"R2" = effect on Result2 (`pr_Result2`). "Cmd" column: target commands that call it
(A=AddBuffers, C=CD, P=Path, X=Execute, R=Run, W=Wait, E=EndCLI, S=Resident, M=Mount, H=Shell-Seg).

### 8.1 Kernel (ROM segments entry 1)

| Gl. | Off. | Name | Arguments → result (D1) | R2 | Cert. | Cmd |
|---|---|---|---|---|---|---|
| 0 | $000 | globsize | (value) maximum number of globals | | O | |
| 1 | $004 | start | entry of the program/process | | O | all |
| 2 | $008 | stop(code) | dl_GV: exits up to pr_ReturnAddr with D0=code (= LVO Exit); command GV: replaced by the stub | | O | A C P X R W S M |
| 3 | $00C | muldiv: mult(a,b) | a×b | | O | |
| 4 | $010 | div(a,b) | a/b (truncation towards 0) | | O | |
| 5 | $014 | rem(a,b) | remainder (sign of the dividend) | | O | |
| 6 | $018 | setio(iob, cmd, data, len, offset) | fills io_Command (word), io_Data (BPTR→APTR), io_Length, io_Offset (5th arg) | | O | |
| 8 | $020 | getlongbytes(adr, n) | assembles *n* big-endian bytes read at the **APTR** adr | | O | |
| 9 | $024 | putlongbytes(adr, n, v) | inverse | | O | |
| 10 | $028 | result2(set, v) | set=0: returns pr_Result2; set≠0: returns the old one and writes v | read/write | O | C P X R H… |
| 12 | $030 | currco | (value) BPTR of the current coroutine / BCPL stack base | | O | |
| 13 | $034 | makeglobvec(segarray) | allocates a GV (max of the segments' "max", floor 15, +50 negative), GV[0]=max, rest **not initialised**; returns BPTR of slot 0; 0 on failure | 103 | O | |
| 14 | $038 | taskid() | MsgPort of the current process (APTR) | | O | X R E P |
| 15/16 | $03C/$040 | getbyte(v,i) / putbyte(v,i,b) | byte `i` starting from BADDR(v) | | O | |
| 17 | $044 | level() | caller's frame (APTR) | | O | X |
| 18 | $048 | longjump(level, label) | resumes at `label` (APTR) in frame `level` | | O | X |
| 19 | $04C | getmem(n, flags) | like getvec with AllocMem flags (e.g. $10001) | 103 | O | S |
| 20 | $050 | aptovec(f, n) | calls f(v, n) with v = vector of n+1 longs taken on the BCPL stack | | O | |
| 22 | $058 | sendio(iob, pkt) | links iob↔pkt (ln_Name = pkt, pkt!0 = iob) then SendIO | | O | |
| 23–27 | $05C–$06C | createco, deleteco, callco, cowait, resumeco | coroutines (not used) | | D | — |
| 28 | $070 | globin(seg) | §3.2 → −1 / 0 | 111 | O | stub |
| 29 | $074 | getvec(n) | vector of n+1 longs (indices 0..n), **not cleared**, MEMF_PUBLIC; hidden header at −4 = total size in bytes; returns BPTR, 0 on failure | 103 | O | P R M H stub |
| 30 | $078 | freevec(v) | v=0: nothing; invalid header (bits $FF000003) → alert $07000005 | | O | P R S M H stub |
| 31 | $07C | opendevice(iob, name, unit, flags) | reply port = MsgPort of the process; → −1 success / 0 | | O | |
| 32 | $080 | closedevice(iob) | | | O | |
| 33 | $084 | createproc(segarray, stack, pri, name, gv) | stack in **longs**; BSTR name; gv BPTR (5th arg); process + stack in one block; inherits ConsoleTask/FileSystemTask/WindowPtr; startup §2.4; → **taskid** (0 on failure) | 103 | O | R (NewCLI) |
| 34 | $088 | endtask() | end of the current process | | D | |
| 35 | $08C | parentdir(lock) | = LVO ParentDir (ACTION_PARENT 29) | handler | O | C P |
| 36 | $090 | setflags(taskid, m) | Signal of the CTRL bits (m bit0=C…bit3=F) | | O | |
| 37 | $094 | testflags(m) | **tests and clears** the CTRL bits of m; → −1 if one was set | | O | X W H |
| 38 | $098 | abort(code) | requester "Software error / Disk corrupt - task held" (retry), then Alert if code < 0 | | O | |
| 39 | $09C | rootstruct() | BPTR of the RootNode | | O | R E S M H |
| 40 | $0A0 | readbytes(adr, n) | Read(input(), APTR adr, n) → bytes read | handler | O | |
| 41 | $0A4 | taskwait() | waits for a packet (pr_PktWait if defined, otherwise the process's port) → BPTR packet | | O | |
| 42 | $0A8 | qpkt(pkt) | sends the packet to dp_Port, dp_Port := reply port of the process; dp_Link ≤ 0 → 0 | 101 | O | |
| 43 | $0AC | writebytes(adr, n) | Write(output(), APTR, n) | handler | O | H |
| 44/45 | $0B0/$0B4 | packstring(v,s) / unpackstring(s,v) | character vector ↔ BSTR | | O | |
| 47 | $0BC | delay(ticks) | 1/50 s, via timer.device (= LVO Delay) | | O | W |
| 48 | $0C0 | sendpkt(_, port, type, r1, r2, a1, a2, …) | the packet **is the argument frame** (DosPacket layout: Link, Port, Type, Res1, Res2, Arg1…); send + synchronous wait; → dp_Res1 | := dp_Res2 | O | A C P R S H |
| 49 | $0C4 | returnpkt(pkt, r1, r2) | | | O | |
| 51 | $0CC | currentdir(set, lock) | set=0: returns pr_CurrentDir; otherwise returns the old one and writes lock | | O | C X R H |
| 52 | $0D0 | requester(l1, l2, l3) | 3 BSTRs; → TRUE = "Retry" | | D | |
| 88 | $160 | callexec(lvo, d0, d1, a0, a1, a2) | exec call (e.g. Forbid −132, Permit −138) → D0 | | O | R E S M |
| 89 | $164 | findsegarray() | pr_SegList (BPTR) | | O | R stub |
| 103 | $19C | calllib(base, lvo, d0, d1, a0, a1) | call of any library → D0 | | O | |
| 105/106 | $1A4/$1A8 | consoletask() / filesystemtask() | pr_ConsoleTask / pr_FileSystemTask | | O | |
| 110 | $1B8 | getlong(b, off) | long at `BADDR(b) + off` (**off in bytes**) | | O | P R S H |
| 111 | $1BC | putlong(b, off, v) | write likewise | | O | P R E H |
| 121 | $1E4 | runcommand(seg, stack, args, len) | §4.3 → return code, −1 if stack impossible | | O | H |
| 134 | $218 | findcli() | pr_CLI (BPTR) — **in a command GV, this slot is overwritten by cli_Result2** | | O | stub |
| −18 | −$48 | CreateProc (C) | segarray `[2, V!1, V!2 of the parent, seglist]`, direct entry into the code | | O | |

### 8.2 dos / BLIB (ROM segment entry 2) and utilities

| Gl. | Off. | Name | Arguments → result | R2 | Cert. | Cmd |
|---|---|---|---|---|---|---|
| 53 | $0D4 | writet(s, w) | §6.2 | | O | |
| 54/55/56 | $0D8/$0DC/$0E0 | rdch / unrdch / wrch | §5.2, §6.1 | | O | X M H |
| 57 | $0E4 | readwords(v, n) | readbytes in longs; → longs read (or code ≤ 0) | | O | |
| 58 | $0E8 | writewords(v, n) | | | O | |
| 59/60 | $0EC/$0F0 | findinput(name) / findoutput(name) | BSTR; → FileHandle BPTR or 0; retry requester on disk error | handler | O | X M |
| 61/62 | $0F4/$0F8 | selectinput(fh) / selectoutput(fh) | writes pr_CIS / pr_COS | | O | X M H |
| 63/64 | $0FC/$100 | endread() / endwrite() | endstream(input()) / endstream(output()) (reselects nothing) | | O | X M H |
| 65/66 | $104/$108 | input() / output() | pr_CIS / pr_COS | | O | X R M H |
| 67 | $10C | readn() | §6.4 | 0/−1 | O | |
| 68–74 | $110–$128 | newline, writed, writen, writehex, writeoct, writes, writef | §6 | | O | all |
| 75 | $12C | capitalch(c) | a–z → A–Z | | O | X M |
| 76 | $130 | compch(a, b) | capitalch(a) − capitalch(b) | | O | H |
| 77 | $134 | compstring(s1, s2) | case-insensitive BSTR comparison; 0 = equal | | O | E S M H |
| 78 | $138 | rdargs(tpl, argv, n) | §5.4 | 120 | O | all |
| 79 | $13C | rditem(v, n) | §5.3 | | O | X H |
| 80 | $140 | findarg(tpl, item) | §5.5 | | O | X M |
| 81 | $144 | load(name) | BCPL LoadSeg (BSTR name) → seglist | handler | O | S H |
| 82 | $148 | unloadseg(seg) | handles the overlay case ($ABCD); = LVO UnLoadSeg | | O | S H |
| 85 | $154 | (addition of a device node) | used by Mount | | S | M |
| 87 | $15C | waitforchar(fh, µs) | = LVO WaitForChar | | O | |
| 90 | $168 | deleteobj(name) | ACTION_DELETE_OBJECT (16) | handler | O | X H |
| 93 | $174 | endstream(fh) | = LVO Close (§5.1) | preserved | O | E H |
| 100 | $190 | taskwait (alias of 41) | | | O | |
| 101 | $194 | execute(cmd, in, out) | loads **C:RUN**, selects in/out, **pr_Result2 := cmd (BSTR)**, runcommand(stack 600 longs) | | O | |
| 102 | $198 | deviceproc(name) | → MsgPort of the handler; Result2 = associated lock (assign/directory); unknown name → 0 and 218; absent volume → requester "Please insert volume … in any drive" (retry); `NIL:` → 0 | 218 / lock | O | A S M H |
| 104 | $1A0 | fault(code) | code≠0: runs **C:FAULT** (stack 400 longs) with pr_Result2 = code; if C:FAULT not found → `"Error code %N\n"` | := code | O | C P H |
| 107 | $1AC | splitname(prefix, char, string, pos) | extracts up to `char` (≤ 30 chars) into the prefix BSTR; → position after `char` or 0 | | O | M |
| 108 | $1B0 | locateobj(name) | **shared** lock (−2) via ACTION_LOCATE_OBJECT (8) | handler | O | P S H |
| 109 | $1B4 | freeobj(lock) | ACTION_FREE_LOCK (15) to the lock's fl_Task; lock 0 → nothing; Result2 preserved | preserved | O | C P X E S H |
| 112 | $1C0 | starthandler(node, name) (§13.3) | | | O | |
| 113 | $1C4 | copydir(lock) | DupLock: ACTION_COPY_DIR (19); 0 → 0 | handler | O | R (NewCLI) |
| 114 | $1C8 | errorreq(…) | disk error requester according to Result2 (protected, full, not DOS…) → TRUE = retry | | D | C P |
| 115 | $1CC | copystring(src, dst) | copies a BSTR (length+1 bytes) — **order (source, destination)** | | O | C P M |
| 123 | $1EC | lock(name, mode) | calls locateobj (the mode is ignored: always shared) | | O | C X |
| 124 | $1F0 | (lookup in the DevInfo list) | | | S | M |
| 125 | $1F4 | createdir(name) | ACTION_CREATE_DIR (22) | handler | O | X |
| 127 | $1FC | timerio(cmd, iob, secs, µs) — synchronous timer.device request (§8.4) | | | O | |
| 133 | $214 | cliinit(pkt) | init of the initial CLI (startup-sequence…); FailLevel 10, **DefaultStack 1000 longs** | | O | |

### 8.3 Negative globals ("C" ABI, ROM segments 2–4)

| Gl. | Off. | Name | Cert. |
|---|---|---|---|
| −1 | −$04 | Open (C name) | O |
| −2 | −$08 | copyvec(src, dst, n): copies n+1 longs (BPTR) | O |
| −3 | −$0C | Read | O |
| −6 | −$18 | Write | O |
| −8 | −$20 | Seek | O |
| −9 … −16 | −$24 … −$40 | DeleteFile, Rename, Lock, Examine, ExNext, Info, CreateDir, CurrentDir | O (LVO wiring) |
| −17 | −$44 | IoErr | O |
| −18 | −$48 | CreateProc | O |
| −19 | −$4C | LoadSeg | O |
| −20 | −$50 | clearvec(v, n): sets n+1 longs to 0 (also wired to LVO GetPacket) | O |
| −21 | −$54 | segment loading **without requester**, **BSTR** name → seglist (used by the CLI to look up commands and by fault for C:FAULT; also wired to LVO QueuePacket) | O (use) / D (without requester) |
| −22 … −27 | −$58 … −$6C | DeviceProc, SetComment, SetProtection, DateStamp, IsInteractive, Execute | O (LVO wiring) |
| −26 | −$68 | IsInteractive(fh): returns fh!1 (fh_Interactive) **raw**, not normalised to −1 | O |
| −31 | −$7C | C string → BSTR (dest BPTR), length capped at 255 | O |
| −32 | −$80 | BSTR → C string **in place** (shifts by one byte, adds NUL), returns the APTR | O |
| −33 | −$84 | sysrequest (C entry) | O |

Globals defined in ROM and characterised further on: 21, 46, 50, 86, 91, 94/95, 126, 127, 128 →
§8.4; 85/124/112 → §13. None is called by the target commands of §9 except 85/124 (Mount);
**C:Date calls 86 and 128** (§8.4.3). [O]

### 8.4 Globals 21–128 and C:Date (2026-10-21)

Sources: ROM `kick34005.A500` (globin tables of the segarray's segments, §3.1) and `c:Date`,
`c:SetClock` from the Workbench 1.3.3 disk. Contracts only.

#### 8.4.1 Where these globals live [O ROM]

| Gl. | Off. | Carrying segment (ROM segarray) |
|---|---|---|
| 21, 46, 86, 91, 127, 128, −25 | $054, $0B8, $158, $16C, $1FC, $200, −$64 | entry 2 (dos "BLIB") |
| 94, 95, 126 | $178, $17C, $1F8 | entry 1, 2nd segment of the chain |
| 50 | $0C8 | entry 1, 3rd segment (with −33 sysrequest and 52 requester) |
| 34 (reminder) | $088 | entry 1, 1st segment |

Neither 83 nor 84 is defined in ROM (84 is supplied by C:Date itself). Global **92** is
in no globin table: it is a **datum** (IntuitionBase, APTR) written by `cliinit` (133). [O]

#### 8.4.2 Contracts [O ROM unless stated]

Units as in §8; "datestamp vector" = 3 consecutive longs **[days, minutes, ticks]**
(days since 1-Jan-1978, minutes since midnight 0..1439, ticks of 1/50 s within the minute 0..2999).

- **128 `setdatstamp(v)`** — D1 = **BPTR** of a datestamp vector. Sets the system time:
  1. seconds = v!0 × 86400 + v!1 × 60 + v!2 / 50; microseconds = (v!2 mod 50) × 20000
     (signed 32-bit arithmetic, **no range validation**, v is not modified);
  2. **Forbid**, then timer request **TR_SETSYSTIME (11)** via global 127 (seconds,
     microseconds) on an IORequest vector **local to its frame**;
  3. re-reads the time by global **86** on that same local vector — which **refreshes
     `rn_Time` of the RootNode** (cf. −25 below);
  4. **Permit**.
  D1 result: **not meaningful** (residue of the Permit call; Date ignores it). Result2 unchanged.
  No DOS packet, no access to the battery-backed clock (RTC $DC0000): writing the RTC is the
  role of `SetClock save`. Callers: C:Date **and the ROM's validator** (time setting at the mount of
  DF0:, cf. [boot-clock-v34.md](boot-clock-v34.md) — correction of the mention "the ROM does not call it").
- **86 `datstamp(v)`** — D1 = BPTR of a vector of 3 longs; calls the C adapter **−25
  (DateStamp)** on `BADDR(v)`; **returns v** (the BPTR received). Callers: C:Date and the file
  system (entry 6).
- **−25 `DateStamp(ds)`** (LVO −192, C ABI: D1 = APTR of 3 longs):
  1. timer request **TR_GETSYSTIME (10)** via 127 → (seconds, microseconds) of the system time;
  2. **Forbid**; computes days = s / 86400, minutes = (s / 60) mod 1440,
     ticks = (s mod 60) × 50 + µs / 20000;
  3. writes these 3 values **into the RootNode's `rn_Time`** (RootNode +$08 days, +$0C minutes,
     +$10 ticks), then copies them into ds[0], ds[1], ds[2];
  4. **Permit**.
  The D0 returned to a C caller is **not** ds (residue of Permit) — divergence from the AutoDoc;
  do not use it. `rn_Time` is therefore only a **cache** updated at each DateStamp;
  the source of truth is the system time of timer.device. [O]
- **127 `timerio(cmd, iob, secs, micros)`** — synchronous request to timer.device:
  `iob` = BPTR of a vector **of at least 12 longs (48 bytes)** supplied by the caller (in practice
  a vector of its BCPL frame). Effects in order: `opendevice(iob, "timer.device", unit 0 =
  UNIT_MICROHZ, flags 0)` (global 31: ln_Succ/ln_Pred := 0, ReplyPort = MsgPort of the process,
  mn_Length = 12; **result not tested**); `setio` (global 6): io_Command := cmd,
  io_Length (+$24 = **tv_micro**) := micros, io_Data (+$28) and io_Offset (+$2C) receive
  **residual** values (hence the 48-byte requirement); +$20 (**tv_secs**) := secs;
  **doio** (21); **closedevice** (32). Result: not meaningful. On return, +$20/+$24 contain
  the timer's reply. The device is **opened and closed at each call**. Commands used:
  **9 TR_ADDREQUEST** (delay, global 47: secs = ticks/50, µs = (ticks mod 50) × 20000),
  **10 TR_GETSYSTIME** (−25), **11 TR_SETSYSTIME** (128).
- **21 `doio(iob)`** — D1 = BPTR of an IORequest; exec **DoIO** (−456); → **io_Error** (byte +$1F,
  unsigned). Callers: 127, console-handler, validator.
- **126 `compstamp(a, b)`** — two BPTRs of datestamp vectors; signed lexicographic comparison
  (days, then minutes, then ticks); → **0** if equal, **+1 if a is more recent than b**, **−1 if a
  is older**. No side effect. Caller: validator (entry 7).
- **94 `getword(v, i)`** / **95 `putword(v, i, w)`** — 16-bit word (unsigned on read) at
  `BADDR(v) + 2·i`. [O]
- **46 `unloadseg(seg)` + `endtask()`** — `unloadseg(seg)` (82) then endtask (34); does not return;
  if the endtask returned: `abort($87000002)`. No caller found in the ROM. [O]
- **34 `endtask()`** (complement to §8.1) — **arguments ignored**: freevec of `pr_SegList` (the
  segarray); if `pr_GlobVec` ≠ `dl_GV`, freevec of the GV (whole block, 50 negative slots included);
  then `RemTask(0)`. [O]
- **50 `openwindow(left, top, width, height, title)`** — intuition **OpenWindow** (−204) with
  **global 92** (IntuitionBase) as base. NewWindow: LeftEdge/TopEdge/Width/Height = the first 4
  arguments (words), DetailPen = BlockPen = −1, IDCMPFlags = 0, Flags = **$00021007**
  (WINDOWSIZING | WINDOWDRAG | WINDOWDEPTH | ACTIVATE | NOCAREREFRESH, smart refresh), no
  gadget nor checkmark, Title = `BADDR(5th arg)` (NUL-terminated text expected), Screen/BitMap =
  0, MinWidth 120, MinHeight 50, MaxWidth = MaxHeight = $FFFF, Type = WBENCHSCREEN (1).
  → **Window\*** (APTR) or 0. Caller: console-handler (entry 5). [O]
- **91 `renameobj(old, new)`** — two BSTRs. `deviceproc` on each (Result2 of each call
  = reference lock); either one at 0 → **0**; different ports → **Result2 := 215**
  (ERROR_RENAME_ACROSS_DEVICES) and **0**; otherwise `sendpkt` **ACTION_RENAME_OBJECT (17)** with
  Arg1 = old lock, Arg2 = old BSTR, Arg3 = new lock, Arg4 = new BSTR → dp_Res1.
  If Res1 = 0: `errorreq` (114); **if it returns 0 the whole operation is restarted**, otherwise
  returns 0. (Meaning of 114's boolean observed here: 0 = start again — to be compared with the 114 line
  of §8.2, marked [D].) Caller: the adapter **−10 (Rename, LVO −78)**. [O]
- **112**: see §13.3.

#### 8.4.3 C:Date (Workbench 1.3.3) [O WB]

File of 4208 bytes (md5 `16b1601e143f86663d2ec14151d6951d`): hunk 0 = standard stub (§3.3,
md5 `d6b59e0e…`), hunk 1 = BCPL module of 960 longs, max = **152**, globin pairs
**(84, $4D4)** and **(1, $44)**. Ordinary BCPL command: only 86 and 128 distinguish it from the
commands of §9.

**Globals used by the module** (exhaustive list of the `GV` accesses of hunk 1):

| Gl. | Use | Gl. | Use |
|---|---|---|---|
| 1 | start (defined by Date) | 74 | writef |
| 2 | stop(20) on error | 78 | rdargs (vector of 50 longs) |
| 10 | result2 (read / write of a flag, cf. below) | 80 | findarg |
| 60 | findoutput (TO argument) | **84** | restoration of the output (defined by Date) |
| 62 | selectoutput | **86** | **datstamp** |
| 64 | endwrite | **128** | **setdatstamp** |
| 66 | output | 150 | static: initial output stream |
| 73 | writes | 151, 152 | statics: parsed time string, read index |

Plus, via the stub: 28, 29, 30, 89, 134 and the CLI copy 134..149. Arithmetic A5+$10/+$12.
**No direct access** to timer.device, the RootNode or the RTC; no global 126/127.

**Behaviour**:
1. G150 := output(); `rdargs("TIME,DATE,TO=VER/K")`. Failure → "usage": three `writes`
   (`***Bad args \n`, `- use DD-MMM-YY or <dayname> or yesterday etc. to set date\n`,
   `      HH:MM:SS OR HH:MM to set time\n`), global 84, **stop(20)**.
2. TO present: `findoutput(TO)`; 0 → `writef("***Can't open %S\n", TO)` then stop(20);
   otherwise `selectoutput`.
3. **Neither TIME nor DATE** → read: `datstamp(v)` (local vector), local conversion into three
   strings, then `writef("%S %S %S\n", day_of_week, date, time)` (date `DD-MMM-YY`, time
   `HH:MM:SS`, day = `Sunday…Saturday` indexed by days mod 7, 1-Jan-1978 being a Sunday;
   fallback strings `<unset>` / `<invalid>` present).
4. Otherwise, **argv!0 (TIME) then argv!1 (DATE)** are processed in that order, each according to its
   contents and not its position: presence of a `:` → **time setting**, otherwise **date setting**.
   - **Time** `HH:MM[:SS]`: HH **mandatory** ∈ 0..23; MM and SS ∈ 0..59 (MM/SS absent → 0;
     HH absent or any out-of-range value → usage + stop(20)). `datstamp(w)` (current time),
     then w!1 := HH×60+MM, w!2 := SS×50, **w!0 kept**, then **`setdatstamp(w)`** (128).
   - **Date**: on entry to the parsing `result2` is set to 0. Forms: `DD-MMM-YY` (month
     `Jan…Dec`; **YY < 78 → 20YY, otherwise 19YY**; days counted since 1978 with leap years
     = divisible by 4), `findarg("Tomorrow,Today,Yesterday")` → current days +1 / 0
     / −1, `findarg("Sunday,…,Saturday")` → day of that week within the **previous** 7 days,
     with **Result2 := 1**. Both relative forms require a non-zero current date (days =
     0 → usage + stop(20)). Parsing failure → usage. Then `datstamp(w)`, **w!0 := days (+7 if
     Result2 = 1)** — so day name = next occurrence, today included [D] —, w!1/w!2
     kept, then **`setdatstamp(w)`** (128).
5. End: **global 84** = if `output()` ≠ G150: `endwrite()` then `selectoutput(G150)`. Normal
   return from start (code 0).

**Exact call of global 128**: D1 = BPTR of a vector of 3 longs (in Date's frame)
already filled by `datstamp` then partly replaced; calling frame of $34 (date) or $30
(time) bytes; result ignored. `date 21-Oct-26 10:00:00` ⇒ **two** successive calls:
(17825, current minutes, current ticks) then (17825, 600, 0) — the latter sets the system
time to 1,540,116,000 s ($5BCC4E20), 0 µs. With a command GV whose GV[128] keeps the
marker `$474C0001 + 2·128` (§3.3), the first setting jumps to an odd address. `date` without
argument only requires 86 (and hence −25/127/21).

#### 8.4.4 C:SetClock (`SetClock load`) [O WB, D for the identification of the library calls]

File of 4884 bytes (md5 `f2775b9198d12db532b935cb70682cd4`), **C executable (17 hunks, with
relocations), not BCPL**: it uses **no global**; it goes through dos.library (LVO) and
timer.device. Syntax: `setclock load|save|reset` (otherwise usage text, code 0).

- **Clock**: MSM6242 at **$DC0000**, 16 4-bit registers, **one register per long** (register
  *i* in the low nibble of the long `base + 4·i`): 0/1 seconds, 2/3 minutes, 4/5 hours, 6/7 day,
  8/9 month, 10/11 year (2 digits), 12 day of week, 13/14/15 = control registers D/E/F
  (+$34/+$38/+$3C). Values written as longs `$FFFxFFFx` (useful nibble repeated).
- **Detection**: reads the seconds register, waits ~1.5 s (dos call of 75 ticks, D), reads again;
  value changed ⇒ clock present. Otherwise retries at **$D80000** (message
  `Warning: Clock is at old address`); absent at both addresses ⇒ `Battery Backed up Clock not
  found` and return code **5**. A `SetClock load` without an emulated RTC therefore exits with 5 (startup-sequence:
  without consequence if FailAt ≥ 5, default case 10).
- **load**: freezes the clock (HOLD bit of register D, wait for BUSY = 0), reads the 12 digits,
  releases; seconds since 1-Jan-1978 (years since 78, month tables of 365/366 days,
  leap = year mod 4 = 0; years 00–77 not handled); then timer.device unit 0, IORequest of
  40 bytes on a port created for the occasion, **TR_SETSYSTIME (11)**, tv_secs = seconds,
  **tv_micro = 0**, DoIO, close. **No passage through dos**: `rn_Time` is only updated at the
  next DateStamp.
- **save**: **TR_GETSYSTIME (10)** → tv_secs decomposed into date/time, written into the registers of
  the RTC (under HOLD). **reset**: reinitialisation sequence of the control registers D/E/F.

#### 8.4.5 Consequences for our runtime [D]

- A ROM that wants to run C:Date must provide **86** (or −25) and **128** in the segments
  installed by globin; 128 only needs timer.device **TR_SETSYSTIME** + the re-read that
  refreshes `rn_Time`.
- 127 does not need to be exported for Date, but any implementation of −25/128/47 must
  provide an IORequest buffer ≥ 40 bytes (≥ 48 if `setio` is reproduced).
- The D1 results of 128 and D0 of DateStamp are not meaningful in V34: returning v / ds is
  compatible.

---

## 9. Q8 — Other behaviours needed by the target commands

### 9.1 Minimal globals per command [O WB]
(calls through the GV table; to which are added 28/29/30/89/134 used by the stub)

| Command | Globals called | CLI fields (GV 134–149) |
|---|---|---|
| AddBuffers | 2, 48, 73, 74, 78, 102 (+ mult) | — |
| CD | 2, 10, 35, 48, 51, 73, 74, 78, 104, 109, 114, 115, 123 (+ 84 private) | 135 SetName (read/write of the buffer) |
| Path | 2, 10, 14, 29, 30, 35, 48, 73, 74, 78, 104, 108, 109, 110, 111, 114, 115 | 136 CommandDir |
| Wait | 2, 37, 39, 47, 73, 78 (+ mult/div) | — |
| EndCLI | 14, 39, 74, 77, 78, 88, 93, 110 | 141, 142, 144, 145 |
| Execute | 2, 10, 14, 17, 18, 37, 51, 54, 55, 56, 59–66, 70, 73–75, 78–80, 90, 109–111, 123, 125 (+ div) | 142 CurrentInput, 143 CommandFile, 144 |
| Run | −26, 2, 10, 14, 29, 30, 33, 39, 48, 51, 60, 65, 66, 73, 74, 77, 88, 89, 110, 111, 113, 134 (+ div) | — (via packet) |
| Resident | 2, 19, 30, 39, 48, 73, 74, 77, 81, 82, 88, 102, 108, 109 | — |
| Mount | −2, 2, 14, 29, 30, 37, 39, 54–56, 59–64, 68, 73–75, 77, 78, 80, 85, 102, 107, 110, 115, 124 (+ 84 private) | — |
| Shell-Seg | −20, −8, −1, 10, 14, 29, 30, 34, 37, 39, 43, 48, 49, 51, 54–56, 61–66, 73, 74, 76, 77, 79, 81, 82, 90, 93, 102, 104, 108–111, 121 | — (process segment) |

### 9.2 Peculiarities per command [O WB unless stated]
- **AddBuffers**: `rdargs("DRIVE/A,BUFFERS/A")`, deviceproc(DRIVE) ("Drive %S not found"),
  local decimal conversion ("Invalid char '%C' in number"), then `sendpkt(−, port,
  ACTION_MORE_CACHE = 18, −, −, n)`; result 0 → "Warning: Insufficient memory for buffers".
  Failures: stop(20).
- **CD**: template `"DIR"`. Uses ACTION_EXAMINE_OBJECT (23) via sendpkt, parentdir to
  rebuild the full name, currentdir(TRUE, lock), freeobj of the old one; writes the name into the
  **BSTR buffer pointed to by cli_SetName** (copystring). Messages: "Can't find %S",
  "%s is a file not a directory", "Unable to find current directory name". [O/D]
- **Path**: template `",,,,,,,,,,ADD/S,SHOW/S,RESET/S,QUIET/S"`. Sets **pr_WindowPtr := −1**
  (process +$B8 via putlong) during execution to suppress the requesters, then restores it.
  Manages the `cli_CommandDir` list: nodes `getvec(1)` = `[next BPTR, lock]` (the CLI frees these
  nodes by freevec + unlock at its end). Examine (23) to refuse files.
- **Wait**: template `",SEC=SECS/S,MIN=MINS/S,UNTIL/K"`; delay() loop with testflags(CTRL-C)
  → "**BREAK"; UNTIL reads the time via the RootNode (rn_Time) [D].
- **EndCLI**: `rdargs("")`; **stdin.fh_End := 0** (forced EOF, which the CLI does not restore); if
  CurrentInput ≠ StandardInput: closes the script and CurrentInput := StandardInput;
  **cli_Background := TRUE**; if cli_Interactive: `"CLI process %N ending\n"`; under Forbid,
  decrements the usage counter of the "CLI" resident if it exists and is > 0. The CLI then exits at the
  next read (§4.5).
- **Execute**: reads the script name by **rditem** (not rdargs); opens the file (findinput),
  otherwise retries relative to `S:`; "Can't open %S".
  - Script **without directive** (first non-blank character ≠ `.`) and no nesting
    (CurrentInput = StandardInput): puts the character back, **cli_CurrentInput := the script**, stop(0).
    The CLI then executes the lines of the script. The parameters of the Execute line are ignored.
  - Otherwise: processes the directives `.KEY/.K`, `.DEFAULT/.DEF`, `.BRA`, `.KET`, `.DOLLAR`, `.DOT`
    (default delimiters `<` `>` `$` `.`), writes the substituted script into a temporary file
    `T:Command-<n>-T<m>` (fallback `:T/Command-0-Tnn`), copies the rest of the enclosing script in case
    of nesting, then CurrentInput := temporary and **cli_CommandFile := its name** (deleted by
    the CLI at EOF). Internal errors handled by level()/longjump. [O/D]
- **Run** (protocol for creating a background CLI):
  1. Command text: if pr_Result2 ≠ 0 on entry, it is a **command BSTR** (case of
     global 101 / LVO Execute); otherwise the **injected input buffer** (fh_Buf[0..fh_End−1]) followed
     by a `\n`, placed in a hand-built memory FileHandle (getvec; `fh_Buf` = internal
     data, `fh_Pos` = 0, `fh_End` = length+1, no routine).
  2. New segarray `getvec(4)`: `[4, V!1, V!2 of the parent, 0, CLI]` where CLI = segment of the resident
     named **"CLI"** if it exists in the Resident list (its usage counter may be
     incremented, never if it is −1 = system; exact condition in §13.6.5 [O]), otherwise
     `rn_ConsoleSegment` (RootNode +4).
  3. Under Forbid: first free slot of `rn_TaskArray` (`[0]` = size); failure → "Unable to
     create background process".
  4. createproc(segarray, **800 longs**, pri of the parent, `"Background CLI"`, **GV of the parent**
     = pr_GlobVec of the calling CLI); `rn_TaskArray[slot]` := taskid; `pr_TaskNum` of the new
     process (+$8C) := slot. Permit.
  5. **Startup packet** (synchronous sendpkt): `dp_Type` = **machine address of a BCPL init
     routine** contained in Run; Arg1 = pr_CLI of the parent, Arg2 = input(), Arg3 = output(),
     Arg4 = FileHandle of the commands, Arg5 = DupLock of the current directory (if parent CLI), Arg6 =
     initial command BSTR (or 0).
  6. On the new CLI's side: `start(pkt)` calls `init = pkt.dp_Type` (or GV[133] if pkt = 0) with
     pkt; if `init` returns a value **> 0**, the CLI calls it as a function with
     pr_Result2 as argument (Run thus returns `qpkt` after putting pkt in Result2 → **immediate**
     reply, Run continues); a value **< 0** = flags, the packet is only returned at the
     **end** of the CLI (synchronous Execute() case). [O ROM + WB; bits and full contract: §13.6]
  7. Run displays `"[CLI %N]\n"` (if no initial BSTR) then stop(0).
  The background CLI reads its commands from the memory FileHandle; at its EOF, being Background, it
  terminates.
- **NewCLI**: creates an **interactive** CLI in a window (`"Window,From"`, default
  `CON:0/0/640/100/New CLI`); the window is opened **by the new process** (findinput then
  findoutput(`*`)) in an init routine specific to NewCLI (global 133 of its private GV). Full
  contract: **§13.7**.
- **Resident**: list of resident segments = chain starting from **DosInfo +$10** (DosInfo = BADDR
  of rn_Info, RootNode +$18). Node: `!0` next BPTR, `!1` usage counter (−1 = SYSTEM), `!2`
  seglist, `!3…` BSTR name (byte +12). Requires the **p** protection bit ("Pure bit not set").
  Template `"Name,File,Remove/S,Add/S,Replace/S,Pure/S,SYSTEM/S"`. [O/D]
- **Mount**: reads `devs:mountlist` (template `"DEVICE/A,FROM/K"`) by findinput/rdch; keywords
  `Handler, StackSize, Priority, GlobVec, FileSystem, Startup, …`; creates DeviceNode/environment.
  Not analysed in detail. [S]
- **Shell-Seg**: BCPL segment of **a single hunk without stub** (global 1, max 133); it installs itself
  as the "CLI" resident and is used as entry 4 of the segarray (like the ROM CLI); it manages
  the Resident list itself and calls runcommand (121). Shares the CLI's GV. [O/D]

### 9.3 Interoperability constraints for our ROM [D]
- Our FileHandles must respect the §5.1 layout (BPTR buffer, byte indices) because the CLI
  **injects** the arguments into them and the commands (EndCLI, Run) write `fh_End`/`fh_Buf` directly.
  If our BCPL rdch/wrch are native, they must apply exactly the rules of §5.2/§6.1 on these
  fields; if the fh_Funcs/Func2/Func3 routines are called, they must be **callable
  in BCPL** (entry A4, return through A6).
- The FileHandles and nodes allocated by the commands are allocated by getvec and freed by freevec
  (and vice versa): the getvec header (size at −4) must be compatible with all the blocks
  exchanged (FileHandle, path nodes, segarray, GV).
- The runtime must exist in the form of **segments in the §3.1 format** listed in the segarray of
  each CLI (entries 1..V!0), because it is the command's globin that installs them into its private
  GV.
- Default `cli_DefaultStack` = 1000 longs; the stub takes its BCPL stack **within** that stack.

---

## 10. Divergences from the public table (Kinnersley/AROS)

| Point | Public table | V34 observed |
|---|---|---|
| Frame −4 | "old A4" | A4 **of the callee**; A4 restored from the caller's frame [O] |
| Global 1 Start | (commented in AROS) | **confirmed**: start(D1) [O] |
| $0C/$10/$14 | multiply/divide/mod | confirmed (3/4/5) [O] |
| $48 (18) | longcall | **longjump(level, label)** [O] |
| $50 (20) | longjump | **aptovec(f, n)** [O] |
| $1A0 (104) | writeErr | **fault(code)**: launches C:FAULT, fallback `"Error code %N"` [O] |
| $13C (79) | rditem (K: rdline) | rditem confirmed [O] |
| $140 (80) | subString (K: parseline) | **findarg(template, item)** [O] |
| $1E4 (121) | runCommand (K: runloaded) | confirmed, convention §4.3 [O] |
| $204 (129) | DOSBase (value) | **does not exist in V34**: no reference in the ROM nor in the commands [O] |
| $218 (134) | findCLI | confirmed in dl_GV; **in a command's GV, 134..149 = copy of the CLI** [O] |
| −$08 (−2) | copyvec (K: strncpy) | copyvec (n+1 longs) [O] |
| −$50 (−20) | clearvec (K: clearmem) | clearvec; **also LVO GetPacket** [O] |
| −$54 (−21) | NoReqLoadSeg (K: queuepkt) | segment loading (BSTR name) — NoReqLoadSeg confirmed by use; **also LVO QueuePacket** [O/D] |
| −$58 (−22) | DeviceProc | confirmed [O] |
| GV size | — | dl_GV: 0..150 (+50 negative); command: 0..max(149, cmd max) (+50) [O] |
| Undefined slots | — | dl_GV: undefined; command: $474C0001+2n [O] |
| BCPL stack | "distinct from the C stack" (dos-v34-spec §4) | **same block** as the 68000 stack; BCPL frames from the bottom, A7 from the top [O] — to be corrected in dos-v34-spec.md |

---

## 11. Test vectors (observable)

1. `Failat 15` in a CLI: after the command, `cli_FailLevel` (CLI +$14) = 15 (written via GV[139]
   then copied back by the stub). [D]
2. Command `Echo "a b"` (BCPL) launched by the CLI: on entry to the stub, A0 points to `"a b"\n`
   (with the quotes), D0 = 6; input().fh_Pos = 0, fh_End = 6. [D from §4.2]
3. rdargs(`"DRIVE/A,BUFFERS/A"`, v, 20) on the input `DF0: 30\n` → v!0 = BSTR "DF0:", v!1 = BSTR
   "30", result ≠ 0, line consumed up to the `\n` included. On `DF0:\n` → 0, Result2 = 120.
4. rdargs(`",SEC=SECS/S,MIN=MINS/S,UNTIL/K"`, v, n) on `5 MINS\n` → v!0 = "5", v!1 = 0,
   v!2 = −1, v!3 = 0.
5. writef(`"%X4|%I5|%T8|%%|%$%N"`, 255, −42, "ab", 7, 9) → `00FF|  -42|ab      |%|9`.
6. An undefined global in a command GV contains $474C0001+2n (e.g. GV[7], defined by
   no ROM segment, is $474C000F in the GV of any command that does not define it).
7. getvec(9) → block of 44 bytes whose hidden long (BADDR(v)−4) is 44.
8. After `EndCLI` in the initial (interactive) CLI: message `"CLI process 1 ending"`, then the
   CLI process terminates at the next read.

---

## 13. Complements (globals 85/124/112, c:Mount, starting of handlers and of background CLIs)

V34 DeviceNode (DevInfo) layout used below, in longs (byte offset) [O ROM + WB]:
`!0` dn_Next ($00) · `!1` dn_Type ($04, 0 = DLT_DEVICE, 2 = volume) · `!2` dn_Task ($08) ·
`!3` dn_Lock ($0C) · `!4` dn_Handler ($10, BSTR) · `!5` dn_StackSize ($14) · `!6` dn_Priority ($18) ·
`!7` dn_Startup ($1C) · `!8` dn_SegList ($20) · `!9` dn_GlobalVec ($24) · `!10` dn_Name ($28, BSTR).
The list of nodes starts from **DosInfo +$04** (di_DevInfo; DosInfo = BADDR of rn_Info, RootNode +$18).

### 13.1 Global 85 (GV +$154) — `makedevnode(name)` [O ROM]
- **Argument**: D1 = BSTR of the name **without `:`** (Mount passes it in upper case).
- Allocates the node by **getvec(10)** (11 longs, **not cleared**) and a copy of the name by a cleared
  getmem of `(length+1)/4` longs (+1 implicit), so the copy is followed by at least one
  NUL byte. Copies the BSTR (copystring).
- Initialises: dn_Name := the copy; **dn_Type, dn_Task, dn_Lock, dn_Handler, dn_StackSize,
  dn_Priority, dn_Startup, dn_SegList := 0**. **dn_GlobalVec is not initialised** (undefined
  contents: the caller must write it).
- Under Forbid/Permit: inserts the node **at the head** of the di_DevInfo list.
- **Result**: BPTR of the node; 0 if an allocation fails (both blocks are then freed,
  Result2 = 103 left by getvec). No other effect on Result2.

### 13.2 Global 124 (GV +$1F0) — `finddevinfo(name)` [O ROM]
- **Argument**: D1 = BSTR of the name without `:`. **Case-insensitive** comparison (compstring) with
  the dn_Name of each node, under Forbid/Permit.
- **Result**: the **first node of type DLT_DEVICE (0)** bearing that name; failing that, the
  **last** node with the same name of another type (volume, assign); 0 if none. Result2 unchanged.
- (deviceproc uses the same lookup in "first node of that name, whatever the type" mode.)

### 13.3 Global 112 (GV +$1C0) — `starthandler(node, name)` [O ROM]
Called by **deviceproc** (global 102) when the node found is of type 0, has dn_Lock = 0 and
dn_Task = 0. Arguments: D1 = BPTR of the DeviceNode, D2 = **the complete BSTR passed to deviceproc**
(e.g. `NEWCON:0/0/640/200/Titre` for an Open). Result: MsgPort of the handler, or 0.
1. **Segment**: if dn_SegList = 0, loads dn_Handler by global 81 (load, BSTR name); failure →
   0 (Result2 = error of the load). The segment is **stored in dn_SegList** (loaded only
   once, never unloaded here).
2. **dn_GlobalVec = −1 → C handler**: C ABI CreateProc (global −18) with name = text of
   dn_Name **as a C string** (BADDR+1, terminated by the NUL guaranteed by 13.1), pri = dn_Priority,
   seglist = dn_SegList, stack = dn_StackSize **in bytes**. Direct entry into the code of the first
   segment (no globin).
3. **Otherwise → BCPL handler**: builds a segarray `getvec(3)` = `[3, V!1, V!2 of the calling
   process, dn_SegList]` (kernel + dos + handler); GV = dn_GlobalVec if it is non-zero (**shared existing
   GV**, BPTR), otherwise **makeglobvec(segarray)** (global 13: new GV sized on
   the segments' "max", floor 15, not initialised apart from globin); then **createproc(segarray,
   dn_StackSize in longs, dn_Priority, dn_Name BSTR, GV)**. The process starts according to §2.4: globin
   of V!1..V!3 into this GV, then wait for the startup packet.
4. Creation failure → frees the segarray, returns 0. Success → **Result2 := dn_Lock**.
5. **Startup packet** (synchronous sendpkt to the created port): **Arg1 = complete BSTR of the name**
   (D2), **Arg2 = dn_Startup**, **Arg3 = BPTR of the DeviceNode**; dp_Res2 = GV (BCPL case);
   **dp_Type, dp_Res1 and the rest are not initialised** by the ROM (residual values of
   the frame: a handler must not interpret them). If the handler replies with Res1 ≠ 0:
   Result2 := dn_Lock and returns the port; otherwise returns 0.
6. **dn_Task is never written by dos**: it is up to the handler to fill it in (via Arg3) if it wants
   to remain shared. Otherwise each deviceproc relaunches a new process (behaviour of the
   CON:/NEWCON: type, one window per Open). [O for the absence of a write, D for the consequence]

> Unit asymmetry observed: **dn_StackSize is in bytes for a C handler but in longs
> (×4) for a BCPL handler**. [O]

### 13.4 c:Mount — sequence for `mount newcon:` [O WB, D for the reading of the file]
1. `rdargs("DEVICE/A,FROM/K")`. File = FROM, otherwise **`devs:mountlist`** (findinput; failure →
   "Could not open %S for input").
2. Reading of the mountlist by rdch: `/* */` comments, search for the entry whose name equals
   DEVICE (case-insensitive), then reading of the `Keyword = value` assignments up to `#`.
   Keywords recognised by findarg on the template
   `",BlockSize,,Surfaces,,BlocksPerTrack,Reserved,PreAlloc,Interleave,LowCyl,HighCyl,Buffers,
   BufMemType,MaxTransfer,Mask,BootPri,DosType,Device,Unit,Flags,Handler,StackSize,Priority,
   GlobVec,FileSystem,Startup,Mount,Baud,Controlr"` (index = position, Handler = 20, StackSize =
   21, Priority = 22, GlobVec = 23, FileSystem = 24, Startup = 25).
3. Default values of the absent fields (internal "not supplied" marker replaced):
   **StackSize = 600, Priority = 10, GlobVec = −3** (= "GV of the calling process"), Handler = 0,
   Startup = 0, FileSystem = 0, Mount = 0; for the FSes: BlockSize = 512, Reserved = 2,
   Interleave = 0, Buffers = 5, BufMemType = 3, MaxTransfer = $7FFFFFFF, Mask = $FFFFFFFF,
   DosType = `'DOS\0'`, Baud = 1200, Unit/Flags/LowCyl/HighCyl/PreAlloc… = 0.
4. Creation of the node: extracts the name before `:` (splitname, global 107), **puts it in
   upper case**, `finddevinfo` (124) → already present ⇒ "Device %S already mounted", end.
   Otherwise `makedevnode` (85) (failure ⇒ "Unable to create new node"); then dn_Lock = dn_Type =
   dn_Task = 0, **dn_StackSize = StackSize, dn_Priority = Priority**.
5. **Entry without `Device =` (NEWCON case)**: dn_SegList = 0, **dn_Startup = Startup value**
   (0 here), **dn_Handler = BSTR of Handler** (`L:Newcon-Handler`), **dn_GlobalVec** deduced from
   GlobVec: −3 (default) or 2 → **BPTR of the Mount process's `pr_GlobVec`** (= GV of the CLI, hence
   `dl_GV` for the ROM CLI); 0 → 0; any other value (e.g. −1) → **−1**.
   For NEWCON (WB mountlist: `Handler = L:Newcon-Handler`, `Priority = 5`, `StackSize = 1000`,
   no GlobVec): **dn_Handler = "L:Newcon-Handler", dn_StackSize = 1000, dn_Priority = 5,
   dn_Startup = 0, dn_SegList = 0, dn_GlobalVec = BPTR(GV of the CLI)**, dn_Type = 0, dn_Name =
   "NEWCON", inserted at the head of di_DevInfo. Mount **does not load** the handler (the
   `Mount =` keyword has not been examined).
6. **Entry with `Device =` (file system)**: builds a FileSysStartupMsg (unit,
   device name, environment copied from the numeric fields); **dn_Startup = BPTR of this
   message**; if FileSystem absent → **dn_SegList = rn_FileHandlerSegment** (RootNode +$1C, the ROM
   FS) and dn_Handler = 0, otherwise dn_SegList = 0 and dn_Handler = FileSystem; dn_GlobalVec deduced
   from GlobVec with "calling GV" replaced by **0** (−3/2/0 → 0 ⇒ dos will build a new GV;
   other → −1). [O for the assignments, D for the detail of the FSSM]
7. The disk's `l:Newcon-Handler` binary is a **single-hunk BCPL segment** (global 1 at
   offset 4, max 111, no stub) — consistent with a BCPL start on a shared GV. [O WB]

First access to `NEWCON:` (e.g. Open("NEWCON:0/0/640/100/x")): BCPL open → deviceproc → DLT_DEVICE
node without task or lock → **global 112** (13.3): loading of `L:Newcon-Handler` into
dn_SegList, segarray `[3, kernel, dos, handler]`, **createproc with the shared GV** (dn_GlobalVec ≠
0, ≠ −1), stack 1000 longs, pri 5, name "NEWCON"; globin of the kernel, dos and the handler **into this
shared GV** (the handler overwrites global 1 in it, without effect on the already started processes [D]);
startup packet (Arg1 = complete name, Arg2 = 0, Arg3 = node); on the reply, deviceproc
returns the port and the open continues with ACTION_FINDINPUT/OUTPUT.

### 13.5 Start of a CLI (ROM or Shell-Seg in entry 4 of the segarray) [O ROM + WB]
- createproc → start §2.4: stack filled with $ABABABAB, globin of V!1..V!0 (kernel, dos,
  [cliinit or 0], CLI) into the supplied GV, **taskwait** for the packet, then **start(pkt)**.
- `start(pkt)` of the ROM CLI **and** of Shell-Seg (same behaviour observed): the init function is
  **`pkt.dp_Type`** (machine address of a BCPL routine), or **GV[133] (cliinit)** if pkt = 0. The
  CLI is first allocated **in the CLI's frame** (cleared, internal Prompt/CommandName/
  CommandFile/SetName buffers) and stored in pr_CLI; then `r = init(pkt)`:
  - `r > 0`: `r` is a routine, called with **pr_Result2** as argument (Run: init puts pkt
    into Result2 and returns the address of `qpkt` ⇒ **immediate reply** to the creator);
  - `r ≤ 0`: flags kept; the packet is **returned at the end** of the CLI (returnpkt, Res2 =
    cli_Result2); bit 1 of `r` = do not do endread, bit 0 = do endwrite (§13.6.4). [O]
- What Run's init (routine passed in dp_Type) consumes from the packet and writes: see the
  **exact contract of §13.6** (Arg1 = parent CLI: Prompt/SetName/DefaultStack/CommandDir copied,
  FailLevel **not** inherited (10); output `*` if Arg3 = StandardOutput of the parent, otherwise **NIL:**;
  Arg4 ⇒ cli_StandardInput = cli_CurrentInput; Arg5 ⇒ current directory; Arg6 = mode
  selector). [O]
- A background CLI whose input (memory FileHandle, null routines) runs out receives EOF; being
  Background it terminates (§4.5), frees its rn_TaskArray slot and exits the process.
- The [D] points above about Run's init are **replaced** by the contract observed in §13.6.

### 13.6 Run's init routine: exact contract [O WB (c:Run, l:Shell-Seg) + O ROM (CLI, entry 4)]

Analysis landmarks: in c:Run (hunk 1, BCPL, only global 1 defined, max 134), the init
routine is at offset **$4B8** of the hunk; Run places its **machine address** (not a BPTR) in
dp_Type. It uses two local subroutines (copy of the parent CLI's settings, copy of the
path list). On the CLI side: start of the ROM CLI = its global 1, start of Shell-Seg = global 1 of its hunk.

#### 13.6.1 Calling contract (Q1)
- **Location of the CLI to fill: exclusively through `findcli()` (global 134, GV +$218)
  called in the GV designated by A2.** It uses neither an argument of the packet, nor the frame of
  the caller, nor a variable supplied by start. `findcli()` must therefore return the **BPTR**
  stored in **pr_CLI of the current process** (= the new CLI; process +$AC). The ROM reads it
  raw from the current process (no conversion). [O]
  ⇒ start must have stored the CLI in pr_CLI **before** the call, and global 134 of the current
  GV must be the findcli *function* (this is the case for the shared GV; in a command GV
  this slot contains a datum, cf. §3.3 — init must therefore never run on a private GV).
- The **current process** is obtained by `taskid()` (global 14); only the "Execute
  mode" use (13.6.2) needs it (write of pr_ConsoleTask by putlong). [O]
- Assumptions about the caller (all necessary) [O for the use, D for the necessity]:
  - standard BCPL call (§1.1/§1.2): **A0 = 0**, A2 = (shared) GV of the new process,
    A5/A6 = call/return routines, **A4 = exactly the entry address** (= dp_Type) —
    the routine addresses its strings (`"NIL:"`, `"*"`, `"%N> "`, `"SYS:"`) and its subroutines
    **relative to A4**;
  - **D1 = BPTR of the packet**, and the packet also present in slot 0 of the new frame (the routine
    re-reads the packet from that slot: the call routine must have stored D1..D4 in the frame,
    §1.2);
  - **long-aligned frame**: a subroutine takes the BPTR of one of its frame variables
    (tail of a linked list);
  - **D0 sufficient** so that init's frame and those of its callees (path copy →
    getvec, copydir → sendpkt) **overlap neither the CLI nor its buffers** if those are in
    start's frame. Own depth of init + subroutines ≈ $30 + $34 + $24 bytes before
    the runtime calls. Observed values: **ROM CLI D0 = $1A4** (CLI at frame+$154..$193),
    **Shell-Seg D0 = $2BC** (CLI at frame+$25C..$29B). [O]
  - no read of the caller's frame, nor of any other global of the GV than those listed
    below; **pr_CIS/pr_COS are neither read nor written**.
- Globals used (GV of A2): **134** findcli, **14** taskid, **60** findoutput, **−26**
  IsInteractive, **111** putlong, **51** currentdir, **89** findsegarray, **10** result2,
  **29** getvec, **113** copydir; the **value** of slot **42** (address of qpkt) is read but
  not called. [O]
- Prerequisites on the CLI: cleared except the 4 buffer BPTRs already installed and writable:
  **cli_Prompt ($18)**, **cli_SetName ($04)**, **cli_CommandFile ($24)** (and cli_CommandName ($10),
  not used by init). Init **copies into** these buffers; it does not allocate them. Sizes of the
  buffers of the ROM start and of Shell-Seg (identical): Prompt 68 b, CommandName 108 b, CommandFile
  48 b, SetName 84 b. [O]

#### 13.6.2 Fields filled (Q2)
Notation: `pkt` = BADDR(D1); Arg1..Arg6 = pkt+$14..$28; `par` = Arg1 (parent CLI or 0);
`cli` = findcli(). Two modes depending on **Arg6**: **Arg6 = 0 ⇒ Run mode** (launch by c:Run
from a CLI); **Arg6 ≠ 0 ⇒ Execute mode** (Run launched by global 101 / LVO Execute,
Arg6 = command BSTR). Effects in this order [O]:

1. **cli_StandardInput ($1C) := Arg4** and **cli_CurrentInput ($20) := Arg4** (unconditional).
2. Choice of the output stream `out` and of the flags (initial value **$FFFFFFFC** = −4):
   - *Run mode*: if **Arg3 = par.cli_StandardOutput** (BADDR(Arg1)+$38 — Run passes its
     output() in Arg3) ⇒ `out := findoutput("*")`; otherwise (Run's output redirected)
     ⇒ `out := findoutput("NIL:")`. Bit 0 of the flags set. Arg2 is **ignored**.
   - *Execute mode*: if **Arg2 ≠ 0**: **cli_StandardInput := Arg2** (CurrentInput stays
     Arg4), **pr_ConsoleTask (process +$A4) := Arg2.fh_Type** (FileHandle +$08), interactive
     input := IsInteractive(Arg2) (raw fh_Interactive value), bit 1 set. Then
     `out := Arg3`; if Arg3 = 0 ⇒ `out := findoutput("*")` and bit 0 set.
3. **cli_Background ($2C) := NOT( IsInteractive(out) AND interactive_input )** (bitwise
   operations on the raw values; interactive_input = 0 in Run mode) ⇒ **always TRUE (−1)
   in Run mode**.
4. **currentdir(TRUE, Arg5)** ⇒ pr_CurrentDir := Arg5 (the old one is not freed).
5. Inherited settings (local subroutine, arguments cli, out, par):
   - if `par ≠ 0`: source Prompt = par.cli_Prompt, SetName = par.cli_SetName, stack =
     par.cli_DefaultStack, path = **deep copy** of par.cli_CommandDir (new nodes
     getvec(1) `[next, copydir(lock)]`, same order; stops silently if getvec
     fails);
   - if `par = 0`: Prompt `"%N> "`, SetName `"SYS:"`, stack **1000**, path 0;
   - writes: **cli_StandardOutput ($38) := out**, **cli_CurrentOutput ($30) := out**,
     **cli_FailLevel ($14) := 10** (not inherited), **length of the cli_CommandFile BSTR := 0**,
     **cli_DefaultStack ($34)**, **cli_CommandDir ($08)**, then **copy of the bytes** of the Prompt
     BSTR into the buffer pointed to by cli_Prompt and of the SetName BSTR into that of cli_SetName
     (length + text; no size check).
6. **Entry 3 of the segarray (findsegarray()!3) := 0**.
7. **pr_Result2 := D1 (the packet)** (result2(TRUE, pkt)).

Fields **not touched**: cli_Result2 ($00), cli_ReturnCode ($0C), cli_CommandName ($10),
**cli_Interactive ($28)**, cli_Module ($3C); pr_CIS, pr_COS; dp_Res1/dp_Res2. [O]

Correspondence with globals 134..149 of a command GV (§3.3): StandardInput ↔ 141,
CurrentInput ↔ 142, Background ↔ 145, CurrentOutput ↔ 146, StandardOutput ↔ 148, FailLevel ↔
139, DefaultStack ↔ 147, CommandDir ↔ 136, Prompt ↔ 140, SetName ↔ 135, CommandFile ↔ 143
(init does not write via these globals but directly into the structure).

#### 13.6.3 Returned value (Q3)
- **Run mode (Arg6 = 0)**: returns the **contents of slot 42** of the current GV, i.e. the machine
  address of **qpkt** (> 0). [O]
- **Execute mode (Arg6 ≠ 0)**: returns the flags **$FFFFFFFC | bit0 | bit1**, i.e. **−4,
  −3, −2 or −1**: bit 0 = "the output was opened by init (`*`) and will have to be closed",
  bit 1 = "the input was supplied by the caller (Arg2) and must not be closed". [O]
- **Arg6** is used **only** as a mode selector (its BSTR contents are not read by
  init: it is Run itself that turned it into the contents of the Arg4 FileHandle). [O]
- **Diagnosis**: −1 is only produced if init read **Arg6 ≠ 0, Arg2 ≠ 0 and Arg3 = 0**
  (or if slot 42 is −1). With the packet emitted by Run (Arg6 = 0, Arg3 ≠ 0), a return of −1
  **and** an intact CLI indicate that the **routine's indirect reads/writes
  do not reach the expected structures** — they all go through "A0 + BPTR×4", whereas
  result2/qpkt go through A2 and remain correct. Causes compatible with the observations, to be
  checked on the caller's side: **A0 ≠ 0** on entry (single cause explaining at the same time the return of
  −1, the unchanged CLI and a correct pr_Result2); D1 not a BPTR; findcli() returning an APTR, 0
  or the CLI of another process. Revealing side effect in that case: pr_CurrentDir overwritten by
  a stray value (step 4) and stray writes into low memory or elsewhere. [D]

#### 13.6.4 What start() must do around the call (Q4) [O ROM ≡ O Shell-Seg]
Identical behaviour in the start of the ROM CLI and in that of Shell-Seg:

*Before*:
1. Reserve in its own frame the 4 buffers (Prompt, CommandName, CommandFile, SetName) and
   the CLI (16 longs), **clear the CLI** (clearvec, global −20, 16 longs).
2. **pr_CLI := BPTR of the CLI** (putlong on the current process).
3. Install the buffer BPTRs in cli_Prompt, cli_CommandName, cli_CommandFile, cli_SetName.
4. `init := pkt ? pkt.dp_Type : GV[133]`; `r := init(pkt)` (BCPL call, D1 = pkt, D0 = size
   covering CLI + buffers, cf. 13.6.1).

*After*:
5. **If r > 0**: call `r(result2(FALSE))` — in Run mode: qpkt(pkt) ⇒ **the packet is
   returned immediately** to Run (the dp_Port of the received packet already designates the sender, because the qpkt
   of the sender replaced dp_Port with its own port; taskwait does not modify it). The
   result of this call is ignored; **r remains stored** (value > 0) for the end.
6. Read pr_TaskNum (process +$8C) for the prompt/messages.
7. **Store cli_StandardOutput** (value set by init): it is **this copy** that will be
   reselected as output after each command.
8. **cli_Interactive := NOT cli_Background AND (cli_StandardInput = cli_CurrentInput)** ⇒ FALSE
   for a CLI from Run (no prompt nor banner).
9. **selectinput(cli_CurrentInput)** ⇒ **pr_CIS := Arg4** (the memory FileHandle of the
   commands); **selectoutput(stored StandardOutput)** ⇒ **pr_COS := `out`** (`*` or NIL:).
   It is start, not init, that sets pr_CIS/pr_COS.
10. If cli_Interactive: banner/prompt (not concerned here). Then read loop by rdch
    on input(); **at each round** start reselects `cli_CurrentInput` as input and the
    stored output (step 7).

*End* (EOF at the top level):
- if cli_CurrentInput ≠ cli_StandardInput (end of an Execute script): endread, deletion of the
  cli_CommandFile file if it is not empty then length := 0, CurrentInput := StandardInput,
  FailLevel := 10, continue;
- otherwise, if **not Background**: the CLI continues (the console is "re-armed": fh_End := −1,
  fh_Args := 1 on StandardInput);
- otherwise (**Background**, Run case): exit of the CLI:
  - **r < 0** (Execute mode): flush the current output if fh_Pos > 0 (writebytes) then fh_Pos
    := 0; **endread() unless bit 1**; **endwrite() if bit 0**; then **returnpkt(pkt,
    res1, cli_Result2)** ⇒ the caller of Execute() is only unblocked now; in
    Shell-Seg, res1 is the **residual value of a local variable of the loop** (old
    current directory saved around a command, often 0): **not meaningful**,
    only dp_Res2 = cli_Result2 has a meaning;
  - **r ≥ 0** (Run mode, r = qpkt): **endread() and endwrite()** unconditional (closes the
    memory FileHandle and `out`), no returnpkt;
  - then: freeobj(current directory), freeing of the cli_CommandDir list (freeobj of the lock
    + freevec of the node), freeing of the CLI's other resources, **rn_TaskArray[pr_TaskNum] :=
    0**, end of the process. [O]

Consequence for the Arg4 FileHandle built by Run (`getvec(n/4 + 11)`, n = length of the
text without the added `\n`, block not cleared; buffer **inline** starting at index 11): fh_Link/fh_Interactive/fh_Type/fh_Pos/fh_Funcs/
fh_Func3 = 0, fh_Buf = BPTR(FH)+11, fh_End = n+1; **fh_Func2 and fh_Args are not
initialised**. Hence: rdch at fh_Pos = fh_End must treat **fh_Funcs = 0 as EOF**;
**endstream (global 93)** calls fh_Func3 only if it is non-zero, then **freevec of the
FileHandle** (Result2 preserved) — the inline buffer goes with the block, nothing else is
freed or sent; fh_Func2/fh_Args must never be used on this stream. [O ROM + WB]

#### 13.6.5 Complements on c:Run (sender side) [O WB]
- Arg5 = copydir(current lock) **only if Run's pr_CLI ≠ 0**, otherwise 0.
- Arg6 = value of **pr_Result2 on entry to Run** (0 expected when the CLI launches Run as a
  command ⇒ the command launcher must leave pr_Result2 = 0; BSTR when Run is launched
  by global 101).
- Usage counter of the "CLI" resident: incremented **only** if Arg6 ≠ 0 **and** the command BSTR
  has length 0 (and counter ≠ −1); decremented (if ≠ −1) on the failure path
  "Unable to create background process". The start of Shell-Seg sets to −1 the counter of the resident
  "CLI" node obtained by one of its local subroutines (not analysed). [O]
- In the new process's segarray, entry 3 is already 0 on Run's side; init sets it to 0 again.
- After the reply to the packet, Run displays `"[CLI %N]\n"` (N = slot) only if Arg6 = 0,
  then stop(0).

### 13.7 NewCLI: contract [O WB (c:NewCLI) + O ROM (findinput/findoutput, endtask)]

Analysis landmarks: c:NewCLI = standard stub (§3.3) + BCPL hunk 1 of 605 longs, **max 136**,
which defines **two** globals: **1** (start, offset $4) and **133** (offset **$544**: the init routine
of the new CLI). Since the stub installs the module into the **private GV**, global 133
of that private GV (≠ cliinit) designates NewCLI's init routine; the shared GV is not
touched. [O]

#### 13.7.1 NewCLI side (calling process) — order of the effects [O]
1. Reads **pr_StackSize** (process +$84, bytes) and converts it to longs; reads **pr_GlobVec**
   (+$88, APTR) and converts it to a BPTR (access by getlong 110 with the index in longs relative to the
   taskid: 10 → +$84, 11 → +$88).
2. **New segarray `getvec(4)`**: copy of indices **0..V!0** of the current process's segarray
   (findsegarray 89) — hence `[V!0, V!1, V!2, V!3, V!4]` of the calling CLI. **No check**:
   if V!0 > 4 the copy overflows the 5-long block. [O]
3. CLI segment: search in the Resident list (DosInfo +$10, case-insensitive compstring comparison
   with the node name at +12) for the **2nd** node named **"CLI"**, failing that the
   **1st**. Found ⇒ entry 4 := seglist of the node (`!2`) and usage counter (`!1`) incremented
   **only if it is ≥ 1**. Not found ⇒ entry 4 stays **that of the calling CLI** (copy from
   step 2). `rn_ConsoleSegment` is read but **not used** (≠ Run, §9.2). [O]
4. `rdargs("Window,From", v, 50)`; failure ⇒ freevec of the segarray, `"NEWCLI failed\n"`, stop(20)
   (no specific message). **Window absent ⇒ `"CON:0/0/640/100/New CLI"`**. [O]
5. Under **Forbid**: first null slot of `rn_TaskArray[1..[0]]`; none ⇒ Permit, freevec,
   `"Too many processes\n"`. [O]
6. **createproc(segarray, max(stack, 800) longs, pri 0, BSTR "New CLI", GV = pr_GlobVec of the
   NewCLI process)** — i.e. the **shared GV** of the CLI that launched NewCLI (pr_GlobVec is not
   modified by the stub). Pri **0 constant** (≠ Run). Failure ⇒ Permit, freevec,
   `"Unable to create new process\n"`. Success ⇒ `rn_TaskArray[slot] := taskid`,
   **pr_TaskNum (+$8C) of the new one := slot**, Permit. [O]
7. Prepares: Arg1 = **copydir(current currentdir)** (DupLock; even if 0); Arg3 = **deep
   copy of the path list** read in global 136 of the private GV (= cli_CommandDir of the
   calling CLI; nodes `getvec(1)` = `[next, copydir(lock)]`, same order, silent stop if
   getvec fails — same algorithm as Run); Arg5 = **filesystemtask()** (106). [O]
8. **Startup packet** (sendpkt 48, synchronous, to the taskid of the new process):

| Field | Value |
|---|---|
| dp_Type | **machine address** of the init routine (value of global 133 of the private GV) |
| dp_Res1 | **−1 pre-filled** by NewCLI (it is this value that NewCLI sees on success) |
| dp_Res2 | 0 |
| Arg1 | DupLock of the current directory |
| Arg2 | **BPTR of NewCLI's rdargs vector**: `!0` = Window BSTR (or the default), `!1` = From BSTR or 0 (vector **in NewCLI's stack**, valid as long as NewCLI is waiting for the reply) |
| Arg3 | copied path list |
| Arg4 | **BPTR of private_GV[134]**: the 16 longs = copy of the calling CLI's CommandLineInterface (§3.3; GV[134+i] ↔ CLI field +4·i) |
| Arg5 | pr_FileSystemTask of NewCLI |
| Arg6.. | not initialised |

9. Result of sendpkt (= dp_Res1 of the reply):
   - **≠ 0 ⇒ stop(0)**, no message on NewCLI's side;
   - **= 0 ⇒ `"Unable to open new window\n"` then `"NEWCLI failed\n"`**, `rn_TaskArray[slot] := 0`,
     usage counter of the resident found **decremented if ≠ −1** (even if it had not been
     incremented), **stop(20)**. The segarray, the DupLock and the path copy are **not**
     freed by NewCLI (the segarray is freed by endtask in the new process, cf. 13.7.3). [O]

⇒ **Q2 — "Unable to open new window" = the reply to the startup packet has dp_Res1 = 0.**
Only the init routine (13.7.2) produces this reply, in three cases: findinput of the
window = 0, non-interactive window (fh_Interactive = 0), or findoutput(`*`) = 0. [O]

#### 13.7.2 NewCLI's init routine (in the new process) [O]
Same calling contract as Run's init (§13.6.1: called by start with D1 = pkt, A4 = its
address, A2 = shared GV, A0 = 0, aligned frame; it addresses its strings `"*"`,
`"Cannot open From file %S\n"`, `"s:cli-startup"`, `"New CLI process %N\n"` and its subroutine
relative to A4). CLI to fill = **findcli()** (134) of the shared GV. `par` = BADDR(Arg4).
Effects in order:

1. **currentdir(TRUE, Arg1)** ⇒ pr_CurrentDir := DupLock.
2. **pr_FileSystemTask (+$A8) := Arg5**; **pr_WindowPtr (+$B8) := 0** (putlong 111, indices 19
   and 23 relative to the taskid).
3. **Opening of the window = `findinput(Arg2!0)`** (global 59, **in the new process**),
   name = the Window BSTR as is (e.g. `CON:0/80/480/100/MyCLI`).
   - **Failure A**: findinput returns 0;
   - **Failure B**: `IsInteractive(fh)` (global −26, raw value **fh_Interactive**, FH +$04)
     = 0 ⇒ endstream(fh) then **Result2 := 206**.
   In both cases: **returnpkt(pkt, 0, Result2)** (⇒ NewCLI displays "Unable to open new
   window"), then Result2 := taskid, and init **returns the contents of slot 34 of the GV** (address
   of **endtask**) ⇒ start calls it (r > 0, §13.5) ⇒ the process terminates.
4. Success: **cli_StandardInput ($1C) := fh**, selectinput(fh), **pr_ConsoleTask (+$A4) :=
   fh_Type** (FH +$08: the port of the handler that served the open).
5. **cli_StandardOutput ($38) := findoutput("*")** (global 60) — hence a **2nd open, on the
   console that has just been set**. Failure (0) ⇒ endread() (closes the input window),
   **returnpkt(pkt, 0, Result2)** ⇒ same message "Unable to open new window", Result2 :=
   taskid, returns endtask (as in 3). Success ⇒ selectoutput(cli_StandardOutput).
6. **cli_CurrentInput ($20) := cli_StandardInput**. Then:
   - **From supplied** (Arg2!1 ≠ 0): findinput(From); failure ⇒ `writef("Cannot open From file
     %S\n", From)` (in the new window), continue; success ⇒ cli_CurrentInput := that stream;
   - **From absent**: "silent open" subroutine: saves pr_WindowPtr, sets it to
     **−1** (no requester), `findinput("s:cli-startup")`, restores pr_WindowPtr; result ≠ 0
     ⇒ cli_CurrentInput := that stream. (`s:cli-startup` is not looked for if From is given.)
7. **cli_CurrentOutput ($30) := cli_StandardOutput**; **cli_Background ($2C) := 0** (FALSE,
   explicit, ≠ Run); **cli_CommandDir ($08) := Arg3**; **cli_ReturnCode ($0C) := 0**;
   **cli_FailLevel ($14) := par.FailLevel** (GV[139]: **inherited**, ≠ Run which forces 10);
   **cli_Result2 ($00) := 0**; length of the cli_CommandFile BSTR := 0; **cli_DefaultStack ($34)
   := par.DefaultStack** (GV[147]); **cli_Module ($3C) := 0**; copy of the bytes (length +
   text, without size check) of `par`'s **Prompt** (GV[140]) into the cli_Prompt buffer and
   of `par`'s **SetName** (GV[135]) into the cli_SetName buffer.
8. `writef("New CLI process %N\n", pr_TaskNum)` (on the new window).
9. **findsegarray()!3 := 0**; **Result2 := pkt**; returns **the contents of slot 42** (address of
   qpkt) ⇒ start does qpkt(pkt) ⇒ immediate reply, **dp_Res1 = −1** (value pre-filled by
   NewCLI, init does not modify it), dp_Res2 = 0. [O]

Not touched by init: cli_CommandName ($10), **cli_Interactive ($28)** (computed afterwards by
start: NOT Background AND StandardInput = CurrentInput, §13.6.4 step 8 ⇒ FALSE as long as
s:cli-startup is the current input, TRUE afterwards); pr_CIS/pr_COS **are** set
(selectinput/selectoutput) but start reselects them anyway. [O]

Globals of the **shared GV** used by init (all must exist in the GV of the CLI that
launches NewCLI): **10, 14, 49, 51, 59, 60, 61, 62, 63, 74, 89, 93, 110, 111, 134, −26**, and the
**values** of slots **34** (endtask) and **42** (qpkt), which must be machine addresses
**> 0** (start calls them as functions). [O]

#### 13.7.3 Start and end of the new CLI (Q3) [O ROM + WB]
- Start §2.4/§13.5 on the segarray `[V!0, V!1, V!2, V!3, CLI]`: globin of V!1..V!V!0
  **into the shared GV** (including entry 3 = cliinit of the parent, not yet cleared at that
  moment), taskwait, then start(pkt) which allocates the CLI, pr_CLI := it, calls `pkt.dp_Type`.
- Return contract identical to Run (r > 0 = function called with Result2) but two possible
  values: **qpkt** (success, 13.7.2 step 9) or **endtask** (failure, steps 3/5).
- **endtask** (global 34, ROM): frees (freevec) the **segarray** (pr_SegList) of the current
  process, frees the **GV** if it differs from `dl_GV` (shared GV ⇒ not freed), then
  **RemTask(current)**. Does not return. [O; freeing of the process/stack memory: S]
- **pr_ConsoleTask of the new process := fh_Type of the window stream** (step 4): this is what
  makes `*` valid in the new CLI (and in its children, which inherit it via createproc). NewCLI
  itself does not touch its own pr_ConsoleTask. [O]
- **Interactive, non-Background** CLI: it only terminates at EOF after EndCLI (which forces
  Background, §9.2); on exit, r = qpkt ≥ 0 ⇒ unconditional endread + endwrite (close the
  two window streams), no returnpkt, rn_TaskArray[slot] := 0 (§13.6.4 *End*). [O/D]

#### 13.7.4 findinput / findoutput as seen from the handler (ROM, globals 59/60) [O ROM]
Common routine (mode 1005 / 1006):
- FileHandle **getmem(10, $10001)** (11 **cleared** longs), fh_Pos = fh_End = −1, routines
  fh_Funcs/Func2/Func3 installed (Func3 according to the mode).
- **Name = `*`** (compstring): port := **pr_ConsoleTask** (consoletask 105); **no
  deviceproc** ⇒ **Arg2 = residual value of Result2** (in practice the dp_Res2 of the last
  packet received, not meaningful: **do not interpret it as a lock**).
- **Name = `NIL:`**: no packet, fh_Type 0, routines 0, returns the FileHandle.
- Otherwise: deviceproc(name) ⇒ port, Arg2 = Result2 (deviceproc's lock; 0 for CON:/RAW:).
- port = 0 ⇒ freevec, returns 0. Otherwise **fh_Type := port**, then sendpkt(port, mode,
  **Arg1 = BPTR of the FileHandle, Arg2 = lock/residue, Arg3 = BSTR of the complete name**).
- **dos writes neither fh_Interactive nor fh_Args**: it is up to the handler to fill them in the
  FileHandle received in Arg1. Res1 = 0 ⇒ freevec, then `errorreq(2, Result2, port)` (114); Retry ⇒
  everything starts again; otherwise returns 0. Res1 ≠ 0 ⇒ returns the FileHandle (BPTR).

#### 13.7.5 What the console handler must provide for NewCLI to succeed (Q4) [O/D]
1. **Start** (global 112, packet Arg1 = `CON:0/80/480/100/MyCLI`, Arg2 = 0/1, Arg3 =
   node): open the window, **Res1 ≠ 0**. [O]
2. **ACTION_FINDINPUT (1005)** received next (Arg1 = FileHandle, Arg2 = 0, Arg3 = same name):
   **write fh_Interactive (FH +$04) ≠ 0** (the ROM console-handler puts −1 there [D]) and fh_Args
   (FH +$24) = key of the stream; reply **Res1 = −1**. A null fh_Interactive ⇒ failure B ⇒ "Unable
   to open new window" **even if the window is open** (it is then closed again by END). [O]
3. **ACTION_FINDOUTPUT (1006) on the same port with Arg3 = BSTR `"*"`** and Arg2 = residue:
   the handler must accept it as **a second stream on the already open window** (without
   parsing `*` as a window specification, without requiring a lock), fill fh_Interactive
   ≠ 0 and fh_Args, **Res1 = −1**. Refusal ⇒ "Unable to open new window". [O for the success
   requirement, D for the filling of fh_Interactive on this stream]
4. **fh_Type** of the input stream must be the **port of the handler process** (set by dos, §13.7.4)
   since it becomes pr_ConsoleTask: if our findinput stores the port elsewhere than FH +$08,
   step 5 targets a wrong port. [O]
5. The handler must **stay alive as long as a stream remains open**: two ACTION_ENDs arrive at
   the end (input then output, endread then endwrite), plus possibly those of `*` streams
   opened by the commands. Closing the window/terminating at the first END breaks the output. [D]
6. Then, the usual console packets: READ, WRITE, WAIT_CHAR (20), SCREEN_MODE (994),
   DISK_INFO (25), END (1007) (cf. handlers-v34 §2). [O/D]

Diagnosis for our ROM (symptom "Unable to open new window" + "NEWCLI failed", Run/
Execute OK) [D]: the Res1 = 0 reply necessarily comes from NewCLI's init executed **in the
new process on the shared GV**. Causes to check, in order of probability: (a) the
`"*"` FINDOUTPUT to pr_ConsoleTask is refused by our handler, or our findoutput("*") does not
target pr_ConsoleTask; (b) fh_Interactive (+$04) or fh_Type (+$08) of the input stream not
filled in on return from our findinput; (c) global −26 (IsInteractive) absent/incorrect
in the shared GV; (d) findinput(`CON:…`) fails in a process that is not that of a "standard"
CLI (pr_CurrentDir = DupLock, pr_WindowPtr = 0, pr_FileSystemTask = Arg5 already set).
Run goes through none of these paths (it opens `*`/`NIL:` as output only, never a
window as input), hence the observed difference.

---

## 12. Clean-room review

I certify, after a full re-reading of this document, that:
- it contains **no 68000 instruction sequence copied or paraphrased line by line**,
  neither from the ROM nor from the Workbench disk binaries, no disassembly excerpt, no opcode
  nor instruction encoding;
- the descriptions of routines are formulated as **functional specifications**
  (inputs, outputs, effects, order of the observable effects), without pseudo-code modelled on the
  structure of the original code (loops, branches and internal working registers are not
  described);
- the only values reproduced are **ABI and interoperability elements**: numbers and
  offsets of globals, layouts (frame, GV, FileHandle, CLI, segarray, BCPL hunk, list nodes),
  register conventions, constants (packet action codes, error codes, sizes of
  buffers/stacks, value of the undefined-global marker), message strings and templates
  (needed for output compatibility);
- the ROM was not modified; only temporary extractions of the Workbench disk files
  (and, for §13.6, a temporary read copy of the ROM, deleted after
  analysis) were made in the session scratch directory, outside the repository.
- **§13.6 (re-read on 2026-10-20)**: the contract of c:Run's init routine and of the CLIs' start
  is expressed as inputs/outputs, fields written (structure offsets and global numbers),
  return values and order of the observable effects; no encoding, no instruction
  sequence, no internal working register name appears in it (only the registers of
  the public calling convention §1.1 are cited). The c:Run hunk offsets ($4B8) and the
  observed frame sizes ($1A4, $2BC) are analysis landmarks and ABI elements
  (sizing of D0), not code.
- **§13.7 (re-read on 2026-10-20)**: the contract of c:NewCLI (calling process, init routine of the
  new CLI, findinput/findoutput and endtask of the ROM) is expressed as ordered observable effects,
  fields written (Process/CLI/FileHandle offsets, global numbers), contents of the
  startup packet, message strings and failure conditions; no encoding, no instruction
  sequence, no internal working register. The hunk offsets $4/$544 are analysis
  landmarks. Sources: temporary extraction of `c/NewCLI` from a **copy** of the ADF in the session
  scratch; ROM read in place, read only (not copied, not modified).
- **Correction of 2026-10-29**: removed the 15 remaining ROM addresses (ROM segarray, "Landmark"
  column of the table of globals per segment, start of the ROM CLI) and the mention "ROM addresses =
  landmarks"; global numbers, offsets in the global vector and carrying segments kept.
