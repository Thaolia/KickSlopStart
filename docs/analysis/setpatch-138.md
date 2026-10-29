# SetPatch 1.38 (SysInfo floppy): installed replacements, ABI contracts, cause of the `jsr -$24(a6)`

**ANALYSIS** track ("dirty"). This document describes **behaviours and ABI contracts only**:
expected registers, fields read/written, calls made, conditions. **No instruction sequence is
copied into it** and it contains no line-by-line pseudo-code. The Kickstart ROM (`assets/kick34005.A500`)
was **not** opened. It complements `docs/analysis/setpatch-disk-resource.md` (same binary, earlier
analysis) without replacing it.

## Provenance

- File: `C:SetPatch_1.38` from `assets/test_adf/SysInfo.adf` (read only), extracted with
  `xdftool … read c/SetPatch_1.38` into a scratch directory. 5964 bytes, md5
  `b78212216d1ddac4901d72199981b942`, version string "SetPatch 1.38 (24-Sep-90)".
- LOADSEG hunk format, 35 hunks. I relocated the hunks to a fictitious base with a Python script
  (`python3 -I`), then disassembled with radare2 (`-a m68k`). All the functions cited below were
  read in that disassembly.
- Invocation on this disk (`s/startup-sequence`): **`C:SetPatch_1.38 > NIL:`**, hence **without the `r`
  argument**. Next come `C:Initialize` then `SYS:SysInfo/SysInfo`.

### Map of the useful hunks

"File" = offset of the hunk's first data byte in the file. "+x" = offset within the hunk.

| Hunk | Type, size | File | Content (behaviour) |
|---|---|---|---|
| 0 | CODE $218 | $0A8 | C startup: argument parsing, Workbench path, and `_exit` at +$1B2. **Only `jsr -$24(a6)` in the file, at +$1DC (file $284)** |
| 1 | DATA $10 | $300 | Global variables: +0 SysBase, +4 **DOSBase** |
| 2 | CODE $224 | $31C | Embedded BCPL "RUN" segment (stored size $22C, first long $89) |
| 3 | CODE $3DC | $54C | `printf` at +0, `main` at +$30 |
| 4 | DATA $28C | $B70 | Strings (messages) |
| 5 | CODE $54 | $E08 | New **Alert** at +0. Old vector stored at +$4E |
| 6 | CODE $1C | $E68 | New **UserState** at +0, supervisor callback at +$10 |
| 7 | CODE $B4 | $E90 | AllocEntry installer at +0, new **AllocEntry** at +$1E |
| 8 | CODE $E0 | $F50 | RAD installer at +0, 44-byte ColdCapture stub at +$B4 (the only copied code) |
| 9 | CODE $78 | $103C | FPU vector installer at +0, stored ROM address at +$38, 16 stubs at +$3C, common part at +$5E |
| 10 | CODE $CC | $10D8 | Scanner for "word whose high byte is $61" at +0, branch decoder at +$1E, DeleteLayer analysis at +$76 |
| 11 | DATA $0C | $11D8 | 3 pointers to "internal" layers routines |
| 12 | CODE $3C | $11F0 | New **DeleteLayer** at +0 |
| 13 | CODE $CC | $1254 | disk.resource installer at +0, new **GetUnit** at +$7C, new **GiveUnit** at +$94, owner at +$B0 (initial value -1), old GetUnit at +$B4, old GiveUnit at +$B8, name at +$BC |
| 14 | CODE $54 | $1348 | New **MrgCop** at +0, old one at +$4E |
| 16 | CODE $3C | $13B4 | Pointer to the RUN segment at +0, **Execute** glue at +4 |
| 17 | CODE $14 | $1410 | New **SetFont** at +0, old one at +$0E |
| 18 | CODE $30 | $1430 | New **FindName** at +0 |
| 19 | CODE $28 | $146C | "Location zero" at +0, supervisor callback at +$16 |
| 20 | CODE $38 | $14A0 | New **SetSoftStyle** at +0, old one stored at +$32 (never used) |
| 29/30/31/28 | CODE | — | exec/dos call stubs (C convention → registers) and RawDoFmt/Write |

Execution order in `main` (hunk 3): test for `?`, then RAD if the argument is `r`/`R`. Then
`FindPort("SetPatch-01")` and, if the port exists, exit with code 5. Otherwise the port is created and added.
Then come, in this order, disk.resource, Alert, graphics, layers, the exec block (FPU, then
AllocEntry, UserState, FindName), "location zero" and DOS Execute. At the end of `main` (+$3C0),
**`cli_Module` (CLI +$3C) is set to 0**, then `_exit(0)`.

---

## 1. Allocated memory, copied code, contracts of each replacement

### 1.1 All AllocMem calls in the program

| Where | Size | Flags | Use | Freed? |
|---|---|---|---|---|
| Hunk 0 (startup) | $184 | `MEMF_PUBLIC\|MEMF_CLEAR` ($10001) | Argument buffer (argv + copy of the line). Long +0 is used for the "NIL:" filehandle of the Workbench path | Yes, in `_exit` |
| Hunk 3 (`main`) | 34 | `MEMF_PUBLIC\|MEMF_CLEAR` | "SetPatch-01" marker MsgPort (`ln_Type` = NT_MSGPORT, then AddPort) | Never |
| Hunk 8 (RAD) | 44 | AllocAbs near `SysStkLower`, otherwise `MEMF_PUBLIC\|MEMF_CHIP` (3) | **Only copied code**: ColdCapture stub | Never |
| Hunk 7 (new AllocEntry, at runtime) | 16 + 8×n | `MEMF_CLEAR` only ($10000) | Copy of the MemList on behalf of the caller, then one AllocMem per entry | By the caller's FreeEntry |

**Conclusion.** Outside the RAD path, SetPatch **copies no code** into allocated memory. All the
replacements installed by SetFunction (and the 16 FPU stubs) run **in place, in the hunks
loaded by LoadSeg**. Yet those hunks are themselves AllocMem blocks filled by copying from the
file: this is very probably the "allocated and copied block" observed (see §2). The RAD path is not
taken here, for three reasons: there is no `r` argument, it requires exec `lib_Version` < 35, and it requires
`MaxLocMem` > $80000 (512K of chip gives exactly $80000).

### 1.2 Common conventions

- All replacements installed by SetFunction hand control back to the **old function**, when they
  call it, through **the value returned by SetFunction** (d0), stored in a variable of the hunk. They have
  no fixed ROM address and do not re-read the vector table. Exceptions: Alert (§1.3, jumps to
  old+$30 or +$88), DeleteLayer (§1.8, routines deduced from the old one's code) and the FPU vectors (§3).
- **SysBase read at $4**: by all installers, by the new GetUnit/GiveUnit (`ThisTask`), by the
  new Alert (validity test only) and by "location zero". **Not read** (a6 assumed to hold
  SysBase on entry) by the new **AllocEntry** and **UserState**. FindName does not use a6.
- No replacement reads `AttnFlags`.

### 1.3 Alert (exec -108). Condition: exec `lib_Version` is 33 or 34

- Installation: SetFunction, then test of the old vector. If it is **not** in
  `$FC0000..$FFFFFF`, a new SetFunction with the old one (cancellation) and the message "skipped (vector in use)".
  Our ROM is at $FC0000, so the replacement is **installed** (the message "Alert patched" confirms it).
- Entry: d7 = alert number, a5 = parameter pointer (Alert convention). a6 is not used.
- Behaviour: switches off the INTENA master ($4000). If the long at $0 already holds `'HELP'`, jumps directly
  to the second entry point. Otherwise it writes `'HELP'` at $0, the alert number (bit 31 forced) at $100 and
  **the long pointed to by a5** at $104. a5 must therefore be even, otherwise an address error.
- It then tests the validity of SysBase at $4 (the pointer must have a null high byte and be even).
  If it is valid, it **jumps to oldAlert + $30**, otherwise to **oldAlert + $88**. These are **entry
  points internal to the 1.3 ROM, computed from the old vector**. It never returns.

### 1.4 AllocEntry (exec -222). Condition: exec ≤ 35

- Entry: a0 = source MemList, **a6 = SysBase assumed** (no read of $4).
- Behaviour: allocates a new MemList of 16 + 8×`ml_NumEntries` bytes (`MEMF_CLEAR`). It receives
  `ml_NumEntries` (offset 14) and zeroed node fields. For each entry (at 16 + 8i), the length
  (+4) is copied. If it is null, the address is 0; otherwise the address is the one returned by
  `AllocMem(me_Length, me_Reqs)`.
- If an entry fails, it frees, in reverse order, the entries already obtained, then the list
  (same size), and returns **the `me_Reqs` of the failing entry with bit 31 set**. If the allocation of the
  list itself fails, it returns $80000000.
- Exit: d0 = new MemList. d2-d3/a2-a4 preserved; d1/a0/a1 lost. **The old AllocEntry is
  never called.**

### 1.5 UserState (exec -156). Condition: exec ≤ 35

- Entry: called **in supervisor mode**, d0 = supervisor stack to restore, **a6 = SysBase assumed**.
- Behaviour: removes the return address from the stack, puts the current stack into USP, then takes d0 as
  the new SSP. It then calls **exec Supervisor (-30) via a6 while already in supervisor
  mode**, with a5 = callback (the caller's a5 saved aside then restored).
- The callback finds at sp the 68000 exception frame (SR.w, PC.l) that Supervisor pushed. It replaces
  the PC there with the caller's return address and clears the S bit of the stacked SR. The RTE then returns
  the caller in user mode, on its own stack.
- It never calls the old UserState.

### 1.6 FindName (exec -276). Condition: exec ≤ 35

- Entry: a0 = list, a1 = name. a6 is not used.
- Behaviour: walks from `lh_Head` to the sentinel node (null `ln_Succ`) **skipping
  nodes whose `ln_Name` (+10) is NULL**. The comparison is case-sensitive.
- Exit: d0 = node or 0. **a1 restored**, a2 preserved. **a0 and d1 are destroyed** (a0 points into a
  string). It never calls the old FindName.

### 1.7 disk.resource GetUnit (-18) and GiveUnit (-24). Condition: `lib_Version` ≤ 35

This fix is already detailed in `setpatch-disk-resource.md` §1-3, and the disassembly confirms it:

- Hand-made critical section: INTENA $4000 and `IDNestCnt` (+$126) +1, then -1 and INTENA $C000 if
  the counter becomes negative again.
- New GetUnit: calls the old one, passing it the registers (a0 is overwritten). If the old one returns
  d0 ≠ 0, the owner becomes `ThisTask` (+$114 read via $4).
- New GiveUnit: jumps to the old one if the owner is `ThisTask` or -1. Otherwise it **swallows the call**.
- **Neither of them calls anything via a6.** The original GiveUnit is reached by a jump
  to the stored pointer (hunk 13 +$B8). No `dr_*` field is touched.

### 1.8 layers DeleteLayer (-90). Condition: `lib_Version` ≤ 35

- After SetFunction, **analysis of the code of the old DeleteLayer** (hunk 10 +$76):
  - the word at entry+2 is decoded as a branch (8-bit displacement, or 16-bit if the low
    byte is null);
  - from the target, the scanner looks for the first word whose high byte is $61 (BSR) and decodes its
    target, which gives routine no. 1. It resumes after that BSR for routine no. 2, then for no. 3.
  - The three addresses are stored in hunk 11.
- New DeleteLayer: entry a1 = Layer. It calls routine no. 1 with `Layer->LayerInfo` (+$44)
  **passed on the stack** (C convention). If it returns a result ≠ 0, it calls routine no. 2 with the
  Layer, then no. 3 with the LayerInfo, and returns 1. Otherwise it returns 0. It never calls the old one.
- **Total dependence on the shape of the 1.3 ROM code.** On our layers, the three targets are
  quasi-arbitrary addresses: they point into our ROM, near the DeleteLayer code.

### 1.9 graphics MrgCop (-210), SetFont (-66), SetSoftStyle (-90). Condition: `lib_Version` ≤ 35

- **MrgCop**: entry a1 = View, **a6 = GfxBase assumed**. It compares the LACE bit ($0004) of `View->Modes`
  (+16) with that of `GfxBase->Modes` (+$9E). If LACE has just appeared in the View, it walks the
  ViewPorts from `View->ViewPort` (+0) via `vp_Next` (+0). For each ViewPort whose `Modes` (+32) has
  both $2000 and LACE, it calls **MakeVPort (-216) via a6**. It ends by **jumping to the old MrgCop**
  (stored pointer), a1 restored.
- **SetFont**: entry a0 = font, a1 = RastPort. If either of them is NULL, immediate return. Otherwise jump to
  the old one (stored pointer), registers unchanged.
- **SetSoftStyle**: entry a1 = RastPort, d0 = style, d1 = mask, **a6 = GfxBase assumed**. It calls
  AskSoftStyle (-84) via a6 to obtain the algorithmically possible bits. The new `AlgoStyle` (+$38)
  is the old `AlgoStyle` without the bits (mask ∩ possible), plus the bits (style ∩ mask ∩
  possible). It stores it and returns `AlgoStyle | tf_Style` of `rp->Font` (+$34, field +$16), d2 preserved.
  The old one is never called, although its pointer is stored.

### 1.10 General remark

None of these replacements does a `jsr` via a6 with a displacement of -24 (decimal). The only calls
via a6 made inside the replacements are AllocMem/FreeMem (AllocEntry), Supervisor
(UserState), AskSoftStyle (SetSoftStyle) and MakeVPort (MrgCop).

---

## 2. Who can execute a `jsr -24(a6)` / `jsr -$24(a6)` with a6 = 0 or 1

**Finding 1: there is no `jsr -24(a6)` (decimal, -$18) anywhere in the file.** The only occurrence
of $FFE8 (-24) is the **offset passed to SetFunction** for GiveUnit (hunk 13 +$56, file $12AA), and it
is not a call.

**Finding 2: there is exactly one `jsr -$24(a6)` (hexadecimal, i.e. -36, dos `Close`)**: hunk 0 +$1DC
(file $284), in the **C startup's `_exit`** (+$1B2). UAE debuggers display displacements in
hexadecimal (`-$0024`). It is therefore very likely that "-24" is this `-$24`. Contract of `_exit`:

- It redoes `FindTask(NULL)` (a6 = SysBase reloaded from $4) and takes **`pr_ReturnAddr` (+$B0) of the
  current task**. It sets sp = `pr_ReturnAddr` − 12, then pops two longs pushed by the startup: the
  Workbench message (a2) and the argument buffer (a5).
- If long +0 of the buffer (the "NIL:" filehandle of the Workbench path) is non-null, it loads **a6 from the
  global variable DOSBase (hunk 1 +4)** and calls `Close` (-$24). It then calls CloseLibrary(DOS),
  then, if a2 ≠ 0, ReplyMsg of the Workbench message under Forbid. It frees the buffer ($184 bytes) and does an
  `rts` to the address located at `pr_ReturnAddr` − 4.
- **The expected value of a6 is DOSBase**, which no entry register supplies. It comes from a
  variable of DATA hunk 1, filled at start-up by `OpenLibrary("dos.library", 0)`. If a6 is 0 or 1,
  that variable has been **overwritten**, which implies that the hunk 1 block was freed and then reallocated.
- Launched from a CLI, long +0 of the buffer is 0 (`MEMF_CLEAR`), so this call **is normally
  never executed**. It only is if `_exit` pops a bogus buffer. That is the case when `pr_ReturnAddr`
  is wrong, or when the "current task" is not this process: a plain Task has no +$B0 field,
  which falls outside the structure.

**Most probable cause: SetPatch's hunks are freed after it has run.**

- SetPatch assumes that the CLI **does not unload** its seglist: it itself sets `cli_Module` (CLI +$3C,
  via `pr_CLI` +$AC) to 0 just before `_exit`. All its resident code (replacements, "old vector"
  variables, disk.resource owner, FPU stubs for vectors $C0-$FC, DOSBase in hunk 1) lives
  in these hunks.
- Reading our `src/dos/shell.s`: the command is unloaded via the seglist saved at launch
  (`XF_SEG`), **without re-reading `cli_Module`** (`sh_cli_end` actually resets it to 0 itself). SetPatch's
  hunks are therefore returned to free memory while these vectors still point into them:
  - exec FindName, AllocEntry, UserState and Alert;
  - graphics SetFont, SetSoftStyle and MrgCop;
  - layers DeleteLayer;
  - disk.resource GetUnit and GiveUnit.
- These blocks are then reallocated by LoadSeg (`C:Initialize`, then SysInfo, which are also "allocated
  and copied"), by task stacks or by small allocations (semaphores, messages, IORequest).
  Any task that calls a patched vector then executes whatever occupies the space, or SetPatch's old code
  whose variables are corrupted.
- FindName is called internally by OpenLibrary, OpenDevice (audio.device...), OpenResource, FindPort and
  FindTask(name). The disk controller goes through GetUnit/GiveUnit on every trackdisk access. **All the
  tasks therefore converge on the same addresses**, which matches the symptom "same crash everywhere".
- To decide, **compare the PC of the crash with the addresses of SetPatch's hunks** recorded during its
  LoadSeg (start of block + 8 = hunk data). If the PC equals hunk0 + $1DC, or falls into one of hunks
  5 to 20, the cause is confirmed. Counter-test: do not unload the seglist when `cli_Module` is 0
  on return; the crash should then disappear.

**Possible secondary causes, to be considered only after this one:**

- (a) **Alert** is installed and jumps to old+$30 / +$88 **in the middle of our ROM code**. It also reads
  (a5), which causes an address error if a5 is odd. But the PC would then land in ROM, not in RAM.
- (b) **DeleteLayer** is installed and jumps to the three targets deduced from our code. The PC would
  also land in ROM.
- (c) **UserState** and **AllocEntry** use a6 as received. An internal caller that does not pass
  a6 = SysBase would make a call to a6+displacement (-30, -198 or -210), but never -24 nor -$24.

---

## 3. "Exec 68881/68882 exceptions patched" and "DOS Execute call already patched"

### 3.1 FPU exception vectors (exec ≤ 35, without SetFunction or AttnFlags test)

- SetPatch reads **CPU vector 5** ($14, divide by zero). It takes the **low byte** of the handler's first
  word as a short branch displacement and computes the target, then advances 6 bytes and
  **requires the word $E2EF** at that place. Otherwise it does a word access at the odd address $1: address
  error, deliberate crash. Since the message was displayed, our ROM passes this test.
- It stores the address "target + 6" (hunk 9 +$38) and **writes 16 longs directly at $C0..$FC**
  (vectors 48 to 63) pointing to 16 2-byte stubs in hunk 9. It writes neither to the ExecBase
  fields nor to the `tc_*` ones.
- A stub pushes a long equal to **2 × vector number** (96 to 126), then joins "target + 6" in the
  ROM. The ROM's common handler must therefore accept at that place a "2 × vector" long on top
  of the supervisor stack.
- On a 68000, these vectors are never triggered (no FPU/MMU, autovectored interrupts). They
  nevertheless point into SetPatch's hunks and stay dangling once those are unloaded.

### 3.2 DOS Execute (dos -222)

- Condition: DOSBase `lib_Version` ≤ 35. SetPatch walks **its own seglist** starting from
  `cli_Module` (CLI +$3C, via `pr_CLI` +$AC of the current process) to find the segment whose long at −4
  (block size) is $22C and whose first data long is $89. This is the BCPL RUN of hunk 2; if it
  is found, it displays "DOS Execute call".
- It then reads **the first long of the -222 entry of DOSBase's jump table** and compares it with
  **$70E56000**, the signature of the 1.3 ROM's BCPL jump table entries (loading of the function
  index followed by a long branch to the common dispatcher). If equal, it does SetFunction
  to the glue in hunk 16 and displays "patched to use resident RUN". Otherwise it displays "**already
  patched**" and **installs nothing**. This is our case.
- If the glue were installed, here is what it would do. It would reserve a BCPL stack of $5DC bytes
  **below** the current sp (without allocating it) and load a2/a5/a6 from DOSBase+$2A/+$2E/+$32 (`dl_A2`,
  `dl_A5`, `dl_A6`). It would take a4 = code of the resident RUN, a0 = 0 and d0 = 12, then make a BCPL
  call through a5, with Execute's d1/d2/d3 passed on and the result returned in d0 from d1. It does not run
  on our system.

---

## 4. Signatures and ROM addresses looked for

| Fix | Assumption about the 1.3 ROM |
|---|---|
| Alert | The old vector must be in `$FC0000..$FFFFFF`. The internal entry points **old + $30** and **old + $88** are fixed. Exec version exactly 33 or 34 |
| FPU | The vector 5 handler starts with a short branch. At its target + 6 there must be the word **$E2EF**. The common entry point is target + 6 ("2 × vector" long on the stack) |
| Layers DeleteLayer | Entry + 2 = branch (short or 16-bit). The targeted body contains **three words with high byte $61** (BSR), which designate three internal routines with C convention |
| DOS Execute | The first long of the -222 entry is **$70E56000** |
| Location zero | Write of a word 0 to the fixed address **$F80000** (ROM area, no effect expected) under Supervisor, then $0 reset to 0 if it was non-null |
| RAD (not taken) | Exec < 35, `MaxLocMem` (+$3E) > $80000, `ColdCapture` (+$2A) null. The copied stub recomputes `ChkSum` (+$52) over words +$22..+$4F. At reset, it compares the long located at (a5)+$1E (ROM code calling ColdCapture) with **$B7FC0004**; if equal, it takes `a3 := MaxLocMem` and resumes at a5+$1E, which skips a piece of the ROM code |
| disk.resource, gfx, UserState, FindName, AllocEntry | No ROM signature or address. Only `lib_Version` ≤ 35 is tested. Never `lib_Revision` |

No ROM checksum, no revision and no `AttnFlags` are tested.

---

## Requirements for our ROM

**DOS / CLI (main cause):**

1. On return from a command, **re-read `cli_Module` and unload only that value**. If it is 0, do not
   unload anything: the command has made itself resident. This also applies to any
   Execute/Run/BCPL path that unloads a seglist. Do not clear `cli_Module` before re-reading it.
2. `pr_ReturnAddr` (+$B0) must point such that `pr_ReturnAddr` − 4 contains the return address to
   the CLI: the C startup pushes two longs below it and `_exit` restarts from `pr_ReturnAddr` − 12. It must
   remain valid throughout the command.
3. `pr_CLI` (+$AC) → `cli_Module` (+$3C) must designate the seglist of the current command, chained as BPTRs,
   with the block size at −4 of each link (SetPatch looks for its RUN there). DOSBase+$2A/$2E/$32
   (`dl_A2`/`dl_A5`/`dl_A6`) are only used if the -222 entry carries the BCPL signature. That is not our
   case, so nothing is required here.

**Exec:**

4. SetFunction must return the complete old address. This is already the case; all the replacements
   call the old one back through this value.
5. **Alert**: either place vector -108 **outside `$FC0000..$FFFFFF`** (trampoline in RAM), so that
   SetPatch cancels its fix itself ("skipped"); or guarantee that old+$30 and old+$88 are
   valid entry points. They would be reached with INTENA off, with d7 = alert, $0 = 'HELP' and
   $100/$104 filled in; +$30 if $4 is valid, +$88 otherwise or in case of recursion. The trampoline is the
   simplest and safest solution.
6. **UserState** replaced: Supervisor (-30) must work **when called from supervisor mode**. It
   must push a standard 68000 frame (SR.w, PC.l) on the current SSP, with no extra word, enter
   at a5, and the RTE of the a5 code must consume that frame directly. Callers of UserState must
   pass a6 = SysBase.
7. **AllocEntry** replaced: a6 = SysBase in all callers. FreeEntry must free
   16 + 8×`ml_NumEntries` bytes for the list, the size allocated by SetPatch. Do not rely on the
   node fields of the returned MemList (zeroed).
8. **FindName** replaced: no internal caller may rely on a0 or d1 after FindName (a1 is
   kept). Nodes with a NULL `ln_Name` are skipped.
9. `IDNestCnt` at +$126 with the convention "−1 = enabled" and `ThisTask` at +$114: already conformant.
10. Vector 5: the current form already passes the $E2EF test. If it is modified, a short branch must be kept
    at the start and the word $E2EF at target + 6, otherwise SetPatch deliberately crashes.

**Graphics / layers / disk.resource:**

11. MrgCop, SetSoftStyle and SetFont must be called with a6 = GfxBase. `GfxBase->Modes` (+$9E) must
    reflect the LACE of the active view, MakeVPort (-216) and AskSoftStyle (-84) must be real
    vectors, and the RastPort offsets `Font` +$34 / `AlgoStyle` +$38 and ViewPort `Modes` +32 must be
    respected.
12. **DeleteLayer**: with a real SetFunction, the replacement is **installed** and its three targets are
    deduced from our code. **Any DeleteLayer (closing a window or a screen) is therefore currently
    dangerous.** A countermeasure must be chosen: either a shape of our DeleteLayer that provides, from
    entry + 2, a branch to a body whose first three words with high byte $61 are real
    BSRs to three C-convention routines (no. 1(LayerInfo) → ≠ 0 to continue, no. 2(Layer), no. 3(LayerInfo));
    or make the version guard fail (layers > 35), if that is acceptable for compatibility.
13. disk.resource: the same task must do GetUnit and GiveUnit, otherwise GiveUnit is swallowed (see
    `setpatch-disk-resource.md` §3). Our GetUnit must return d0 ≠ 0 on immediate acquisition.

## Clean-room review

Reviewed: this document contains no transcribed instruction sequence and no line-by-line pseudo-code.
It contains only offsets, register contracts, fields, signature constants
(values tested by SetPatch) and behaviour descriptions.
