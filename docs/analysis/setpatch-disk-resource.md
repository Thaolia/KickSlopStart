# SetPatch 1.38 (Workbench 1.3.3) — disk.resource, layers and related patches

**ANALYSIS** track. Source: `C/SetPatch` extracted from a **copy** of `assets/wb133.adf`
(`xdftool … read C/SetPatch`, 5964 bytes, 35 hunks, version string "SetPatch 1.38 (24-Sep-90)").
Hunks relocated to a dummy base, then disassembled with radare2 (m68k). The Kickstart ROM was **not**
opened. This document describes **behaviours** (vectors touched, offsets read/written, expectations);
no instruction sequence is copied.

Actual invocation: the disk's `Startup-Sequence` runs **`c:SetPatch >NIL: r`** (argument `r`).

## 0. Overall flow (execution order)

1. Opens `dos.library`. If argument 1 starts with `?` → usage + exit. If `r`/`R` and exec
   `lib_Version ≤ 35` → attempt of the RAD patch (§6).
2. `FindPort("SetPatch-01")`: if found → "already installed", exit code 5.
3. `AllocMem(34, MEMF_PUBLIC|MEMF_CLEAR)` → MsgPort named `SetPatch-01`, `ln_Type = NT_MSGPORT`,
   `mp_SigTask = NULL`, `mp_Flags = 0` (PA_SIGNAL) → `AddPort`. Presence marker, never freed;
   nobody is supposed to send a message to it (a PutMsg on it would do `Signal(NULL)`).
4. **disk.resource patch** (§1-3) → prints "disk resource patched" if applied.
5. Alert patch if exec `lib_Version` = 33 or 34 (§5.1).
6. graphics.library ≤ 35: MrgCop / SetFont / SetSoftStyle (§5.2).
7. layers.library ≤ 35: DeleteLayer (§4).
8. exec ≤ 35: FPU exception vectors (direct write, §5.3) then UserState / FindName / AllocEntry (§5.4).
9. "Location zero" (§5.5).
10. DOS `Execute` → resident RUN (§5.6).
11. **`cli_Module` of the calling CLI set to 0**: SetPatch's seglist is never unloaded (all the patch
    code lives in its hunks). Exit code 0.

All vector installations go through **exec `SetFunction` (-420)**, except the FPU exception
vectors (direct write in low memory) and the DOS pattern test.

## 1. Locating disk.resource and conditions

- `OpenResource("disk.resource")` (exec -498). NULL result → patch skipped, nothing is printed.
- Only condition: `lib_Version` (offset 20 of the base) **≤ 35**. No test of revision, `dr_Flags`,
  size, or code pattern. Our resource (version 34) **passes** the test.
- Returned value: non-zero (-1) if applied → message; 0 otherwise.

## 2. Replaced vectors and method

- Critical section **done by hand**: write `INTENA = $4000` (turns off the master) then
  `ExecBase->IDNestCnt` (offset $126) **+1**; at the end **-1**, and only if the counter becomes
  negative again, `INTENA = $C000`. Neither `Disable()` nor `Enable()` is called (so no deferred reschedule).
  Assumes `IDNestCnt` at $126 and the convention "-1 = interrupts allowed" (our exec: compliant).
- **`SetFunction(diskres, -18, newGetUnit)`** → old vector stored in a private variable of the hunk.
- **`SetFunction(diskres, -24, newGiveUnit)`** → same.
- AllocUnit (-6), FreeUnit (-12), GetUnitID (-30): **not touched**. No direct write to the resource's jump
  table, no access to the `dr_*` fields during installation.

## 3. What the replacements do

Private "owner" variable (long, in the SetPatch hunk), **initialised to -1**.

- **newGetUnit(a1 = DiscResourceUnit, a6 = resource)**: calls the **complete old vector** (normal
  call, return address pushed), input registers passed through unchanged except **a0** (overwritten by
  the address of the old routine). On return, if `d0 ≠ 0` (controller obtained immediately) →
  owner := `ExecBase->ThisTask` (offset $114). Returns the original `d0`.
- **newGiveUnit()**: compares owner and `ThisTask`; if equal **or** owner = -1 → **jump**
  (with no intermediate return) to the complete old GiveUnit; otherwise **immediate return, GiveUnit swallowed**.
  Clobbers d0/d1/a0. The owner is **never** reset to -1 or cleared.
- **No field of the DiscResource structure is read or written** by SetPatch (neither `dr_Current`, nor
  `dr_Flags`, nor `dr_Waiting`, nor the `dr_DiscBlock/dr_DiscSync/dr_Index` interrupts, nor `dr_CurrTask`).
- **No jump into the middle of the ROM routine**: the old vector is called/jumped to at its entry
  point. No ROM-internal address, no expected code pattern.
- Imposed semantics: "only the task that obtained the controller through an immediate GetUnit (`d0≠0`) may
  give it back". A **queued** GetUnit (`d0 = 0`, then deferred ReplyMsg) does not update the owner.

## 4. "Layers patched" patch (DeleteLayer, -90)

- `OpenLibrary("layers.library", 0)`, condition `lib_Version ≤ 35`.
- `SetFunction(layers, -90, newDeleteLayer)` then **analysis of the code of the old DeleteLayer**:
  - decodes the instruction located **2 bytes after the entry point** as a branch (8-bit
    displacement, or 16-bit if the low byte is zero) and goes to its target;
  - from there, scans word by word up to the first word whose high byte is **$61 (BSR)**, decodes its target
    → **ROM-internal routine no. 1**; resumes after that BSR → routine no. 2; then → routine no. 3.
  - The three addresses (internal to the ROM, not public) are stored in the hunk.
- **newDeleteLayer(a1 = Layer)**: **does not call** the old vector again. Calls routine no. 1 with
  `layer->LayerInfo` (offset 68 of struct Layer) passed on the stack (C convention); if result ≠ 0:
  routine no. 2 with the Layer, then routine no. 3 with the LayerInfo; returns 1. Otherwise returns 0.
  No other Layer / Layer_Info / ClipRect field is touched directly by SetPatch.
- **Total dependency on the ROM's internal code**: shape of the prologue, presence and order of three BSRs.
  On another implementation, the "routines" are arbitrary addresses → any DeleteLayer
  (window/screen close) would jump into arbitrary code or data.
- With a `SetFunction` that returns 0 (current case, cf. §7): the scan starts at address 2 (low memory,
  read only, harmless) and the vector is not replaced.

## 5. Other patches of the same program (for reference)

### 5.1 Alert (-108), exec version 33/34 only
- `SetFunction(exec, -108, newAlert)`. If the old vector is **not** in `$FC0000-$FFFFFF` →
  re-SetFunction with the old one (cancellation) + "skipped (vector in use)".
- newAlert: turns off INTENA, writes `'HELP'` at `$0`, the alert code (bit 31 forced) at `$100`, a long read
  via a5 at `$104`, then **jumps to oldAlert + $30 or + $88** (depending on the validity of the ExecBase pointer at
  `$4`) → **ROM-internal addresses computed from the old vector**. Since our ROM is at `$FC0000`, with
  a real SetFunction this patch **would be installed** and any `Alert()` would jump into the middle of our code.

### 5.2 graphics.library ≤ 35
- MrgCop (-210): compares `View->Modes` (offset 16) with a GfxBase field (offset $9E) on the LACE bit;
  if LACE has just appeared, walks the ViewPorts (`vp_Next`, `vp->Modes` offset 32, bits $2000 and LACE)
  and calls MakeVPort (-216); then **jumps to the old MrgCop** (normal entry).
- SetFont (-66): NULL guard (rastport or font NULL → return) then **old SetFont**.
- SetSoftStyle (-90): complete reimplementation via AskSoftStyle (-84); reads `rp->Font` (52),
  reads/writes `rp->AlgoStyle` (56), reads `tf_Style` (22); does not call the old one.

### 5.3 FPU exception vectors (exec ≤ 35) — direct write
- Reads vector **5** (`$14`), follows the handler's `bsr.s`/8-bit branch, advances 6 bytes and
  requires the word `$E2EF`; otherwise a word access at an odd address (**deliberate crash**, address error).
- Writes **16 longs at `$C0-$FC`** (vectors 48-63) pointing to a table of stubs in the SetPatch hunk;
  these stubs join the common ROM handler **6 bytes after its start** with 2×vector number on
  the stack. Never triggers on a 68000 (no FPU/MMU). Our exec already has the expected shape.

### 5.4 exec ≤ 35: UserState (-156), FindName (-276), AllocEntry (-222)
- Self-contained reimplementations: UserState via Supervisor (-30) + RTE; FindName that skips nodes with
  NULL `ln_Name`; AllocEntry that frees cleanly on partial failure (bit 31 of the result).
  No ROM-internal address.

### 5.5 "Location zero reset to zero"
- Via `Supervisor` (-30): word write of 0 at `$F80000` (ROM area, ignored), then if the long at `$0`
  is non-zero → `$0 := 0`. Message if that was the case.

### 5.6 DOS Execute (-222) → resident RUN
- Searches **its own seglist** (from `cli_Module` of `pr_CLI`, offset $AC of the Process) for the hunk whose
  size stored **at -4** of the link is $22C and whose first code long is $89 (BCPL segment
  header) = the embedded BCPL RUN.
- Requires the dos -222 **jump table entry** to start with the long `$70E56000` (the ROM's BCPL stub);
  otherwise "already patched". If so: SetFunction to a glue that calls the BCPL (registers a2/a5/a6
  taken from DOSBase+$2A, BCPL stack ~1500 bytes **below** the current sp) with the resident RUN.

### 6. RAD (argument `r`)
- Only if exec < 35 **and** `MaxLocMem` (ExecBase+$3E) > `$80000` **and** `ColdCapture` (+$2A) is zero:
  copies a 44-byte stub (AllocAbs near `SysStkLower` (+$3A) or chip AllocMem), installs it as
  ColdCapture and recomputes `ChkSum` (+$52). The stub, on reset, searches for a pattern in the ROM code.
  Our exec sets `MaxLocMem = $80000` → **skipped**.

## 7. Comparison with our implementation (reading `src/`, without the ROM)

- `SetFunction` (-420) is **not implemented**: the vector points to the generic stub that returns
  `d0 = 0`. Consequence: **no** patch via SetFunction is actually installed; SetPatch stores
  0 as the "old vector" everywhere, and still prints its messages. For disk.resource, the only real
  effect is the manual critical section (INTENA + IDNestCnt +1/-1, consistent with our exec) and
  **one extra line of output** (to NIL:).
- Real direct effects regardless of the resource: port `SetPatch-01`, vectors `$C0-$FC`, `$0`
  reset to 0, SetPatch seglist made resident (if our CLI re-reads `cli_Module` after the command).
- **Therefore, in the current tree, the disk.resource patch cannot, by itself, corrupt the stack
  of another process**: it writes nothing into the resource, and its replacements are never hooked in.

## 8. Hypotheses for the "execute" crash (PC in its own stack)

Ranked from most to least likely given the analysis above:

1. **Cause outside SetPatch, tied to the presence of the resource itself**: the difference with/without
   the resource does not come from the patched vectors (not installed). To check on the resource side: the
   exclusive DSKBLK/DSKSYNC vectors set by SetIntVector and the CIA-B FLG (index) vector; the relay jumps to
   `IS_CODE` read in the DRU designated by `dr_Current` as soon as the "active" bit is set. If a
   `dr_Current` points to a DRU **on a stack** (case of the boot self-test, DRU on the
   supervisor/boot stack) or to freed memory and the active bit stays/becomes true, a disk/index
   interrupt executed **in the context of the current task** would jump to a value read from a stack
   area → PC in a stack, attributed to the interrupted task (here the BCPL `execute`). BCPL frames
   precisely contain stack addresses. Discriminating experiment: keep the resource but
   remove `SetPatch` from the startup-sequence (or the reverse: SetPatch present, resource renamed so that
   OpenResource fails but interrupts are kept).
2. **Side effect of the extra output** "disk resource patched" to NIL: (one more Write):
   to be considered only if (1) is ruled out.
3. **Future, as soon as SetFunction is implemented**:
   - disk.resource: the replacements are sound (call the whole vector) but **swallow any GiveUnit
     issued by a task other than** the one that obtained the controller through an immediate GetUnit (or after a
     queued GetUnit). The controller would remain "active" with `dr_Current` frozen → disk hang, and
     with a stack/freed DRU → scenario (1) guaranteed. Our trackdisk must therefore do GetUnit **and**
     GiveUnit from the same task.
   - layers DeleteLayer and Alert: dependency on **ROM-internal code** (BSR pattern / offsets +$30/+$88) →
     arbitrary jumps. Countermeasure on the implementation side: make SetPatch's guards fail cleanly
     (e.g. Alert: vector outside `$FC0000-$FFFFFF` → SetPatch cancels by itself; DeleteLayer: no
     guard other than the version — provide a prologue shape that yields harmless targets, or a
     layers version > 35 if acceptable).
   - Since the replacements live in SetPatch's seglist, our CLI must **re-read `cli_Module` after the
     command** and not unload if 0; otherwise all patched vectors would point to freed memory,
     later reallocated (e.g. as the stack of a new process) → PC in a stack.

## Clean-room review

Review of 2026-10-29.

- [x] Source = `C/SetPatch` 1.38 (program from the Workbench disk, not the Kickstart ROM); the ROM was
  not opened. The addresses/offsets cited (`$FC0000-$FFFFFF`, `$F80000`, `$C0-$FC`, offsets
  `+$30`/`+$88` relative to the old Alert vector, 6-byte displacement in the exception
  handler) describe **SetPatch's guards and dependencies**, useful for compatibility; they are
  not addresses of routines taken from the ROM.
- [x] No instruction sequence transcribed: the "BSR" scan of the DeleteLayer patch and the BCPL
  glue of `Execute` are described by their effect (what SetPatch looks for and where it jumps).
- [x] Point flagged, not modified: two code patterns expected by SetPatch in the ROM are cited
  as values (`$70E56000` at the head of dos LVO entry -222, word `$E2EF` in the exception
  handler). They come from the SetPatch binary (they are its application conditions) and are used
  to decide whether the ROM "looks patchable"; they must NOT be deliberately reproduced in
  `src/` (cf. check in `docs/audit/specs-review.md`).
- [x] Offsets of public structures (ExecBase, Layer, RastPort, View/ViewPort, Process) and LVOs:
  ABI.
