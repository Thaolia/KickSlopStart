# dos-boot-sequence.md — DOS-side bootstrap (Kickstart 1.3 / V34.5)

> ANALYSIS track ("dirty"). **Picks up where `boot-sequence.md` stops** (the
> `InitCode(RTF_COLDSTART)` pass → the `strap` resident pri -60 boots the disk). This document describes the
> **DOS flow**: init of `dos.library`, wiring of the structures, start of the DF0: file-handler, and
> the "load + launch a command" path. **Behavioural** description (order of
> operations, side effects, fields touched). **No opcode or instruction sequence.** Provenance:
> **[ROM]** = string/data measured in `assets/kick34005.A500`; **[ABI]** = public contract
> (`dos/*`, RKRM); **[inferred]** = known 1.3 behaviour, not verified line by line. The offsets of the
> structures cited are in `dos-v34-spec.md`.

## Reminder of the junction point (from `boot-sequence.md`)

`strap` (resident, type UNKNOWN, pri -60, last of the COLDSTART pass) looks for a bootable
device, reads and validates the **bootblock** of DF0: and hands control to it (project milestone C/M6y: "it
boots"). dos.library and workbench.task have `rt_Flags = 0`: they are **not** started by
`InitCode` — they are brought in by this disk bootstrap. The bootblock's role is to **locate and
initialise dos**, then hand control to it.

## Phase A — Initialisation of `dos.library` ([ROM] anchors + [inferred] sequence)

Trigger: the bootstrap code (bootblock + `strap`) locates the dos resident
(`FindResident "dos.library"`) and initialises it (`InitResident` → jump into its `rt_Init`,
**manual** init since `rt_Flags` has no AUTOINIT). Observable effects:

1. Allocation + init of the `DosLibrary` base (`lib_Version=34`, `lib_Revision=3` → [ROM] "dos 34.3"),
   insertion into `ExecBase.LibList`, construction of the **jump table** (37 LVOs, cf. `dos-v34-spec.md`
   §5) and of the **BCPL global vector** (`dl_GV`, registers `dl_A2/A5/A6`).
2. Construction of the `RootNode` (pointed to by `dl_Root`): `rn_TaskArray` (CLI table),
   `rn_ConsoleSegment`, `rn_Time`, `rn_RestartSeg` (**[ROM]** disk-validator seglist, cf. Phase D),
   `rn_Info` → `DosInfo`, `rn_FileHandlerSegment` (**[ROM]** code of the resident OFS handler —
   task named "FileHandler").
3. Construction of the `DosInfo` (`di_DevInfo` = head of the device/volume/assign list). **In V34 the
   list is protected by `Forbid()/Permit()`**, not by semaphores (cf. boundary §1b of the spec).
4. **[ROM]** Opening of the libraries dos depends on — strings measured near the init code:
   `"expansion.library"`, `"ramlib.library"`, `"intuition.library"`, `"timer.device"`,
   `"console.device"`, `"input.device"`. expansion provides the config of the mountable units; ramlib
   (`LDDemon`) allows `LoadSeg` of disk handlers/commands; intuition is used for disk error
   **requesters** (cf. Phase D).

## Phase B — Mount table: devices, volumes, assigns ([ROM] anchors)

dos publishes in `di_DevInfo` a chain of `DeviceNode`s (cf. `dos-v34-spec.md` §1a). ROM measurements:

- **DFx:** — BSTR name template `{0x03,'D','F','X'}`, the `'X'` (`0x58`) patched with the
  unit no. `0`..`3`. Each DFx `DeviceNode` has:
  - `dn_SegList` = `rn_FileHandlerSegment` (resident OFS handler) and `dn_GlobalVec` (BCPL prog);
  - `dn_Handler` = BSTR `{0x0B,"File System"}` — name loaded if the seglist were NULL;
  - `dn_Startup` → `FileSysStartupMsg` with `fssm_Device` = `"trackdisk.device"`,
    `fssm_Unit` = drive no., `fssm_Environ` = geometry (OFS 880 KB);
  - `dn_Task` = NULL initially ⇒ **handler started on 1st access** (Phase D).
- **Handlers loaded from disk** (`L:`): `"L:PORT-HANDLER"`, `"L:RAM-HANDLER"`
  → nodes whose `dn_Handler` points to a file to `LoadSeg`; `"NIL:"`.
- **Console**: template `{0x18,"CON:0/0/640/200/AmigaDOS"}` — the window of the initial CLI.
- **System assigns**: `"LIBS"`, `"DEVS"`, `"FONTS"`,
  and the reading of `"devs:system-configuration"` for the config.

## Phase C — First process ("Initial CLI") and startup script ([ROM] + [inferred])

1. **[ROM]** dos creates the initial CLI process — string `"Initial CLI"`. This process
   (a `Process`, cf. §1b) receives a `CommandLineInterface` (`pr_CLI`), a current directory
   (`pr_CurrentDir`), and `pr_CIS`/`pr_COS` streams connected to a **CON:** window (template
   Phase B) via the console handler.
2. **[ROM/inferred]** The CLI runs the bootstrap script: `":S/STARTUP-SEQUENCE"`, read via
   the `Execute` mechanism. The commands are loaded from `C:` (`"C:RUN"`,
   `"C:FAULT"`). The banner `"Release 1.3"` + a copyright line is displayed.
3. **[ROM]** CLI diagnostics present: `"Unknown command %S"`, `"Unable to load %S: "`
  , `"%S failed returncode %N"`, `"**BREAK - CLI"`,
   `"CLI error: %S"` — they confirm a CLI able to load+launch external
   commands and to report return codes.

## Phase D — Start of the DF0: file-handler on 1st access ([ABI] + [ROM] + [inferred])

When a path on DFx: is referenced for the 1st time (e.g. `Open("DF0:…")` or the startup's
`Execute`):

1. `DeviceProc`/`Open` looks up the DF0: `DeviceNode` in `di_DevInfo`. If `dn_Task` is **NULL**:
2. dos **starts the handler** via `CreateProc` using `dn_SegList` (= `rn_FileHandlerSegment`,
   resident OFS handler), `dn_GlobalVec`, `dn_StackSize`, `dn_Priority`. It places a **startup
   packet** (`ACTION_STARTUP`) at the new process's port, referring to the `DeviceNode`/`dn_Startup`
   (exact distribution of the `dp_Arg`s = uncertainty, cf. `dos-v34-spec.md` §6).
3. The handler initialises itself: `OpenDevice("trackdisk.device", fssm_Unit, …)` (from
   `FileSysStartupMsg`), reads the root block, and **validates the disk** — if validation is needed, it launches
   the **disk-validator** process (`rn_RestartSeg`; **[ROM]** `"L:Disk-Validator"`,
   `"Validator"`, `"Error validating disk"`). Then it loops in
   `WaitPort/GetMsg` on its `MsgPort` to serve the packets.
4. dos sets **`dn_Task` = the handler's `MsgPort`**. The subsequent `Open/Read/Close` on DF0: are
   routed to this port (cf. `dos-v34-spec.md` §2–§3).

**[ROM]** Handler error/media management (intuition requesters) — measured strings:
`"Volume"`/`"in unit 0X "`/`"is not validated"`/`"is write protected"`/`"Please replace volume"`/
`"is full"`/`"Not a DOS disk"`/`"No disk present"`/`"has a read/write error"`/`"You MUST replace
volume"`/`"Please insert volume"`, `"Error code %N"`,
`"Disk corrupt - task held"`/`"Software error - task held"`, buttons
`"Retry"`/`"Cancel"`. Associated return codes (`dos/dos.i`): `ERROR_DISK_WRITE_PROTECTED`
214, `ERROR_NOT_A_DOS_DISK` 225, `ERROR_NO_DISK` 226, `ERROR_DISK_FULL` 221, etc.

## Phase E — Load + launch ONE command (LoadSeg + Run flow) ([ABI] + [inferred])

"What it takes to launch a command" path:

1. The CLI resolves the command name (current directory then `C:` via `cli_CommandDir`).
2. `LoadSeg(name)` opens the file **through the handler** (packets `FINDINPUT` → `READ` → `END`,
   cf. §2b), reads the **hunk** executable, allocates/relocates, returns the **BPTR of the 1st segment** (project
   milestone D2). The seglist is stored in `cli_Module`.
3. **Execution**:
   - **Foreground command**: launched on **the CLI process itself** (no new process) —
     dos switches the stack to `cli_DefaultStack`, enters the loaded segment according to the startup
     conventions (command line passed as argument, BPTR/BCPL registers; cf. `dos-v34-spec.md`
     §4), retrieves the return code in `cli_ReturnCode`.
   - **`RUN` (asynchronous)**: **[ROM]** `"C:RUN"` — a **new** CLI process is created
     (`CreateProc`) to run the command in the background (`cli_Background` true).
4. `UnLoadSeg(seglist)` frees the code at the end of execution; `IoErr()`/`pr_Result2` carries any
   secondary error.

## Summary of the order (DOS oracle)

```
strap (COLDSTART, pri -60) → valid DF0: bootblock
   → FindResident("dos.library") + InitResident → rt_Init (manual init)
      → DosLibrary (dl_Root, dl_GV) + RootNode + DosInfo + jump table + BCPL GV
      → OpenLibrary expansion / ramlib / intuition + OpenDevice timer/console/input
      → mount table: DeviceNode DFx (resident handler "File System", trackdisk startup),
        CON:, NIL:, L:RAM-HANDLER / L:PORT-HANDLER, assigns LIBS/DEVS/FONTS
   → creation of the "Initial CLI" process (CON: window, pr_CLI/pr_CIS/pr_COS)
   → Execute ":S/STARTUP-SEQUENCE" (commands from C:)
        └─ 1st access to DF0: → CreateProc(handler, rn_FileHandlerSegment) → ACTION_STARTUP
              → OpenDevice trackdisk + validation (L:Disk-Validator) → dn_Task = handler port
command challenge: LoadSeg(C:name) [FINDINPUT/READ/END] → run (CLI or RUN) → UnLoadSeg
```

## Uncertainties

- **[inferred]** The precise bootblock → dos junction point (who calls `FindResident`/`InitResident`,
  and what the "boot" entry point returned by the dos init is) is not traced line by line
  (clean-room constraint). Consistent with milestone C/M6y but to be confirmed by behaviour.
- **[inferred]** The exact order of the `OpenLibrary` calls/mounts in the dos init is deduced from the strings
  present and from standard 1.3 behaviour, not from a code trace.
- **`ACTION_STARTUP`**: exact `dp_Arg` slots not pinned down (cf. `dos-v34-spec.md` §6).
- **[inferred]** Exact entry convention of a command (registers/stack on the jump into the segment,
  format of the argument line) described at the behavioural level; to be validated on a real 1.3.
- The observable phases (process creation, open/read through the handler, LoadSeg+run)
  are provable by **FS-UAE boot** + marker; the internal BCPL details are not, and
  need not be for the reimplementation (functional equivalent, not a copy).

## Clean-room review

Review of 2026-10-29.

- [x] No 68000 instruction sequence transcribed or paraphrased, no disassembly excerpt:
  phases A-E describe an order of operations and effects (fields set, packets exchanged),
  marked [inferred] where they are not observed.
- [x] **Fixed**: removed all the ROM addresses (about forty): dos ROMTag and `rt_Init`,
  and the location in the ROM of each of the cited strings (library/device names, BSTR
  templates, `L:`/`C:`/`S:` paths, requester and CLI messages). The strings remain cited: they
  are ABI names (libraries, devices, handlers, assigns) or texts rendered to/observable by
  the user.
- [x] Remaining ROM data (short, inventoried in `docs/audit/specs-review.md`): BSTR
  templates `DFX`/`File System`/`CON:0/0/640/200/AmigaDOS`, requester and CLI messages. The
  copyright text is not reproduced.
