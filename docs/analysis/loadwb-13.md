# loadwb-13.md — `c/loadwb` (Monkey Island, 2,784 bytes) vs `C:LoadWB` 1.3.3 (2,780 bytes), and `EndCLI`

> ANALYSIS track ("dirty"). Sources:
> - Monkey Island disk, disk 1/4 [cr Defjam]: `c/loadwb` (header block 891), `c/endcli` (block
>   903), `s/startup-sequence` (block 997);
> - `assets/wb133.adf`: `C:LoadWB` (block 1039), `C:EndCLI` (block 979);
> - ROM `kick34005.A500`: CLI loop in the BCPL section of dos, workbench.task.
>
> Files extracted by the tolerant OFS reader, relocated flat at $100000 and compared byte by
> byte. **Legend**: **[O]** observed · **[D]** deduced · **[S]** assumed. Public calls and
> behaviour; no instruction sequence copied.

---

## 1. Monkey Island's `c/loadwb`: complete sequence [O]

C executable of **12 hunks**, with a structure identical to that of 1.3.3 (§2). The globals are
SysBase (exec) and DOSBase. The sequence of `main(argc, argv)`:

1. exec **OpenLibrary("icon.library", 0)** (−552). Failure ⇒ silent **exit(20)**, without
   a message.
2. exec **OpenLibrary("intuition.library", 0)**. On success:
   - **AllocMem(160, MEMF_PUBLIC|MEMF_CLEAR)** (−198), which will receive the replacement code;
   - in-place decoding of two obfuscated strings (XOR $9E): a screen "Easter egg" text
     and its replacement;
   - **CopyMem(code, block, 160)** (−624);
   - **Forbid** (−132), **SetFunction(IntuitionBase, −276 = SetWindowTitles, block+4)** (−420),
     the old vector being stored at the head of the block, **Permit** (−138);
   - **CloseLibrary(intuition)** (−414).

   The replacement is examined in §2. Failure of OpenLibrary or AllocMem ⇒ the patch is not
   installed, and the program continues.
3. exec **FindTask(NULL)** (−294): its Process, of which `&pr_MsgPort` (+$5C) and
   `BADDR(pr_CLI)` (+$AC) are kept.
4. If **argc = 2 and argv[1] = "-debug"** (exact comparison, case-sensitive) ⇒ debug flag
   := 1.
5. exec **FindResident("workbench.task")** (−96). Failure ⇒ writes **"Cannot find resident tag for
   workbench.task"** to **Output()** (dos −60, Write −48, via RawDoFmt −522), then exit(20).
6. Copy of the command path: for each node of `cli_CommandDir` (CLI +$08),
   AllocMem(8, MEMF_CLEAR), then **DupLock** (dos −96) of the lock. The whole forms a BPTR list.
7. dos **CreateProc("workbench.task", pri 1, seglist = (RomTag + $2A) >> 2, stack 5000)** (−138).
   The shift is arithmetic and the address is not aligned: this is the ROM's "selector 2",
   see `workbench-task-v34.md` §1.3. Failure ⇒ **"Cannot start tool (error %ld)"** with
   **IoErr()** (−132) on Output(), then exit(20).
8. 28-byte startup message **on its stack**:
   - `mn_ReplyPort` = its `pr_MsgPort`;
   - +$14 = the path list;
   - +$18 = the debug flag;
   - `mn_Length` is not initialised.

   It is sent by **PutMsg(port returned by CreateProc, msg)** (−366).
9. **WaitPort(&pr_MsgPort)** (−384) then **GetMsg** (−372): **blocking** wait for the
   reply. There is no timeout.
10. **FindTask("Workbench")**. If the task is found: **`pr_ConsoleTask` (+$A4) := 0** in
    this process. Otherwise, nothing.
11. If **argc = 2 and argv[1] = "delay"** ⇒ dos **Delay(150)** (−198), i.e. 3 s.
12. Return, code 0.

**What it does not do**:
- it does not open any workbench.library;
- it does not look for a "Workbench" port;
- it does neither Execute, nor LoadSeg, nor OpenWorkBench;
- it does not check for an already-running Workbench: a second `loadwb` launches a second process.

**Silent exits**: only the failure of OpenLibrary(icon), with code 20. The two
other failures write a message.

## 2. Differences from `C:LoadWB` 1.3.3 (2,780 bytes, md5 f10020d8…) [O]

- **The same program**: same 12 hunks, same `main` byte for byte. The only bytes that
  differ in `main` are relocated addresses, shifted by the sizes of hunks 4 and 6.
- **No difference for `delay`, `-debug`, FindResident, CreateProc, the message, WaitPort,
  FindTask("Workbench") and pr_ConsoleTask.**
- **Hunk 4, the replacement of SetWindowTitles(win A0, title A1, screen title A2)**:
  - **in both versions**: if the screen title is $FFFFFFFF, direct call of
    the original. Otherwise:
    - if it is the 1.2 version text, a few characters are rewritten in the
      caller's string (+$11…+$15);
    - if it is the Easter egg text, the title is replaced by the other string;
    - then call of the original with the same registers;
  - **only difference**: the 1.3.3 version also exits if **A2 = NULL**. The Monkey version does
    not test NULL: with A2 = NULL, it **reads** byte $14 and compares the string at address 0.
    These are reads in low memory, without writes, since no comparison succeeds [D].
    Both versions display a text "Workbench release 1.2.".
- **Hunk 6** (formatted-write helper): 36 bytes instead of 28, same function.
- **Conclusion**: with this loadwb, the Workbench should start as with the 1.3.3 one. What
  changes in the Monkey startup-sequence is **the absence of `delay`** and **`endcli` without
  `>NIL:`**.

## 3. `EndCLI` (696 bytes): **identical** to the C:EndCLI of WB 1.3.3 (same md5 34adda82…) [O]

### 3.1 What the command does

BCPL command: one stub hunk, plus a module of 82 longs, max global 145. With the global
numbers of `bcpl-runtime-v34.md`:

1. rdargs with an empty template; process number read for the message.
2. **`cli_StandardInput`→fh_End (FileHandle +$14) := 0**: empties the console input
   buffer.
3. If **cli_CurrentInput ≠ cli_StandardInput** (we are in a script): **endstream(CurrentInput)**
   (Close), then CurrentInput := StandardInput.
4. **`cli_Background` := −1 (TRUE)** (global 145 = CLI field +$2C).
5. If **cli_Interactive ≠ 0**: **writef("CLI process %N ending")** on the current output.
6. Forbid (−132); in the DosInfo resident segment list (via rootstruct), search for the
   node named **"CLI"** and **decrement of its use count** if it is > 0; Permit
   (−138).
7. Return.

**EndCLI does not close the console**, sends no ACTION_END and touches neither Output() nor Input().
The message "CLI process 1 ending" is **normal**: it is also displayed on the real 1.3, just
before the window closes. With `>NIL:`, the command's current output is NIL: and the
message does not appear.

### 3.2 Who actually closes the window: the CLI loop in ROM [O]

In the BCPL loop of the CLI (dos), when reading a command line
returns **end of stream**:
- **CurrentInput ≠ StandardInput**: end of a script ⇒ endread, then back to StandardInput.
- **CurrentInput = StandardInput and Background = 0**: normal interactive CLI ⇒ fh_End := −1,
  i.e. "buffer to be reloaded", and next read; it continues.
- **CurrentInput = StandardInput and Background ≠ 0**: **end of the CLI**:
  1. **endread()** (global 63): Close of the current input stream, the console;
  2. **endwrite()** (global 64): Close of the current output stream, the console;
  3. **currentdir(0, …)** then **freeobj(lock)** (globals 51 and 109): **UnLock of the CLI's
     current directory**;
  4. deallocations, then end of the process. Another path handles a CLI launched by packet
     (NewCLI/Run) with returnpkt.
- **The CON: window closes** when the console handler receives the **last ACTION_END**, its
  two FileHandles (input and output) being closed [D, handler behaviour].

**Key point (BCPL FileHandle convention)**:
- `fh_End = 0` means "**stream exhausted**": the next `rdch` returns end of stream
  **immediately, without reading the console**;
- `fh_End = −1` means "**buffer empty, to be reloaded** by ACTION_READ".

EndCLI sets 0. That is what makes the CLI exit **without waiting for a keystroke**, as soon as the
command has finished.

## 4. Leads for our discrepancy [D]

The real sequence of events is the following:
1. `loadwb` returns as soon as the **immediate reply** from workbench.task arrives. This reply arrives
   before any screen is opened (`workbench-task-v34.md` §2.4).
2. `endcli` runs **during** the Workbench init.
3. The CLI reads end of stream, closes its two console handles, UnLocks its current
   directory and terminates.
4. The window closes and the Workbench finishes opening.

On our side ("CLI process 1 ending", window open, no Workbench):
1. **`fh_End = 0` must mean EOF without reading.** If our rdch or our reload treats
   fh_End = 0 as "buffer empty", the CLI goes back to ACTION_READ on the console and **waits for a
   keystroke**. The window then stays open, with the message displayed: this is exactly what we
   observe.
   - With `endcli >NIL:`, we go through the redirection path, then the closing of the redirected
     streams (endstream). This sequence could hide the discrepancy.
   - **To test: `endcli` without `>NIL:` after `LoadWB delay` on the WB 1.3.3 disk.**
2. **End of the CLI ⇒ endread + endwrite, then the console handler closes the window at the last
   ACTION_END.** We must check that our CLI end does these two Closes and that our handler
   counts its opens correctly.
3. **Shared current directory.** The end of the CLI does an **UnLock of its current directory**. If
   our CreateProc gives the Workbench process the **same lock** as the CLI (instead of 0 or a
   DupLock), the UnLock pulls the Workbench out of its directory in the middle of its init. The Workbench
   would then remain invisible or stuck. With `delay`, the Workbench has finished its init before the UnLock,
   which would explain why our reference case works.
   - **To test: `loadwb` then `endcli >NIL:` without `delay`.**
4. **`FindTask("Workbench")`.** On the real ROM, the process is already called "Workbench" when
   LoadWB receives the reply. Otherwise, `pr_ConsoleTask` is not reset to 0. This is harmless as long
   as our Workbench does not use `pr_ConsoleTask`; the ROM never reads it.
5. The process is created with **stack 5000 and priority 1**: check that our CreateProc respects
   the priority, since the Workbench must run ahead of the CLI (pri 0) that is terminating.

---

## Clean-room review

- [x] No instruction sequence copied: public calls with LVO and arguments, fields of
  public structures (Process, CommandLineInterface, FileHandle, Message), conditions.
- [x] No program data reproduced, apart from short strings. The obfuscated texts are
  described by their role only.
- [x] **Correction of 2026-10-29**: removed the 3 ROM addresses (CLI loop, endstream calls);
  behaviour unchanged.
