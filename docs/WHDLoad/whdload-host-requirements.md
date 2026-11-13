# WHDLoad on a Kickstart 1.3 host (black-box runs and host-side requirements)

Analysis-track page. WHDLoad, its Slaves and JST were treated like the Commodore ROM: only the analysis agent
downloaded, ran and disassembled them. This page states behaviour and ABI only: no instruction listing, no address
or offset inside the WHDLoad binaries or inside the Commodore ROM. Companion page: `jst-host-requirements.md`.

Verdict in one line: **no WHDLoad version runs on Kickstart 1.3**, on the real ROM or on ours, and the reason is
not a bug of either ROM: WHDLoad is a Kickstart 2.0 (V37) program from its first public release on.

## Material

| Item | Source | Licence / status |
|---|---|---|
| WHDLoad 20.1 user package (current, October 2026 build) | whdload.de download page | free download; copyright Bert Jahn, commercial use only with written permission |
| WHDLoad 0.41 (first public release, 1996) and 0.88 (1996) | whdload.de "old-whdload" directory | same author, same terms |
| Install of the demo "Arte" (Sanity, 1993): one Slave, Slave version 10 | whdload.de demo installs | install: free download from whdload.de; the demo is a freely distributed scene production |
| Disk image of that demo, cut to the length the install's DIC step makes (872,960 bytes) | the project's local test disks | scene demo, local copy only |

Kickstart emulation installs (kickemu, which load an original Kickstart image) were out of scope and not used.

## Setup of the runs

- Headless Amiberry v8.4.2 through `amiberry-session` (A500 preset, 68000, cycle-exact). Chip 512 KB + slow 512 KB;
  a second series with 2 MB of fast RAM added.
- DF0: a copy of the Workbench 1.3.3 boot disk whose startup-sequence is reduced to `SetPatch`, `path DH0:C add`
  and `execute DH0:test`; every program's output is redirected to `SER:`, followed by `why >SER:`.
- DH0: a host directory mounted through the UAE file system (`filesystem2`, boot priority -128). The UAE boot ROM
  mounts it on both ROMs.
- Targets: the real Kickstart 1.3 (34.5) image; our ROM, development build (`build/kick13.rom`, md5 `194fd9b5...`
  for the first series, `374c70ca...` later) and production build (`make kick-prod`, md5 `22198c4a...`), as built by
  the implementation side (not rebuilt for these runs).

## Observed results

| Program | Real Kickstart 1.3 | Our ROM (dev and prod) |
|---|---|---|
| WHDLoad 20.1 + Arte Slave | the CLI prints `Unable to load WHDLoad: file is not an object module`; the `execute` script is aborted (the following lines do not run even with `failat 30`) and the boot CLI prompt comes back | same message, same abort of the script |
| WHDLoad 0.41 + Arte Slave | returns at once, prints nothing (console or serial); `why` says `The last command did not set a return code` | identical |
| WHDLoad 0.88 + Arte Slave | identical to 0.41 | identical |

No WHDLoad version reaches the stage where it reads the Slave, allocates memory or touches the hardware. Nothing
was taken over, no requester was opened, there was nothing to quit from.

Equivalence: on these three programs our ROM behaves exactly like the real 1.3 (same message, same return code,
same script abort).

## Why it stops: the two gates

### Gate 1: the executable format (WHDLoad 20.x, and every recent version)

- The current `WHDLoad` executable contains relocation hunks of the short 32-bit type (hunk type `$3F7`, which the
  V37 `LoadSeg` accepts as "RELOC32SHORT"; V39 later added the alias `$3FC`). The 1.3 loader does not know this hunk
  type, so `LoadSeg` fails and the CLI reports "file is not an object module" (error 121). Observed on both ROMs;
  hunk types read from the file headers with a small host-side lister.
- Its last hunk is an `HUNK_OVERLAY` (`$3F5`) followed by data that WHDLoad reads itself; the loader never gets
  that far on 1.3.
- Consequence for a 1.3-compatible ROM: rejecting `$3F7` is the 1.3 behaviour. Accepting it would only move the
  failure to gate 2.

### Gate 2: the version check (all versions)

- **WHDLoad 20.1** (static reading of its main code hunk): right at entry, after the usual Workbench-start handling
  (FindTask(NULL); if `pr_CLI` is 0, WaitPort + GetMsg on `pr_MsgPort`), it compares the `lib_Version` field of
  ExecBase with 37. Below 37 it opens `dos.library` (any version), writes the fixed text
  `Sorry, WHDLoad requires Kickstart 2.0 or better.` to `Output()`, closes dos and returns (the Workbench message
  is replied). It never gets to run on 1.3 because of gate 1, so this text is never seen there.
- **WHDLoad 0.41 and 0.88** (static reading, confirmed by the runs): after the same Workbench-start handling they
  call `OpenLibrary("dos.library", 37)`. On failure they return at once with return code 0 and print nothing,
  which is exactly the silent exit observed on both ROMs. When started from Workbench they next open
  `icon.library` version 37 as well.
- Official documentation, all versions: the "Requirements" page asks for "Kickstart 2.0 (version 37)", a 68000 or
  better (68010+ recommended so that the quit key can work through the VBR) and at least 1 MiB of RAM. The 0.41
  guide (1996) already said "Kickstart 2.0 (version 37+)". No entry of the version history (read up to the first
  public release, 0.41 of 5 September 1996) mentions Kickstart 1.x support for WHDLoad itself; the only 1.x items
  concern the kickemu (a Kickstart 1.2/1.3 *image* run inside WHDLoad on a 2.0+ host).

## Host-side requirements once the gates are passed (WHDLoad 20.1)

Method: the library-call sites of the main code hunk were attributed to libraries by following which base register
value each call uses (the library bases live in a context block allocated at entry; OpenLibrary sites name each
library). The attribution is a heuristic: about 85 call sites stay unattributed and a few attributions may be
wrong. Function names and minimum versions come from the AROS `.conf` function lists (LVO slot -> name, `.version`
markers). Treat the lists as "functions referenced", not as an execution trace.

### Libraries opened unconditionally at start, all with version 37

dos, graphics, intuition, gadtools, keymap, utility. Any of them missing ends WHDLoad. gadtools, keymap (the
library) and utility do not exist at all on a 1.3 system. Right after that it calls exec `CreateMsgPort` and
`CreateIORequest` (V36).

Optional or conditional libraries and devices named in the binary: icon, expansion, lowlevel, xpkmaster (packed
data files), reqtools (decryption of some files, version 38), openurl, bsdsocket, rtg; `input.device`,
`timer.device`, `trackdisk.device`, `cdtv.device`, `x-surf.device`; resources `ciaa.resource`, `ciab.resource`,
`misc.resource`, `battclock.resource`, `keymap.resource`, `aca.resource`.

### Functions referenced, by library (V36+ ones marked)

- exec, V34-level: Supervisor, FindResident, Disable/Enable, Forbid/Permit, AllocMem, AllocAbs, FreeMem, AvailMem,
  FindName, FindTask, Wait, Signal, AllocSignal, GetMsg, ReplyMsg, WaitPort, OpenLibrary, CloseLibrary,
  SetFunction, OpenDevice, CloseDevice, RemDevice, DoIO, SendIO, CheckIO, WaitIO, OpenResource, TypeOfMem.
  **V36+**: CacheClearE, CreateIORequest, DeleteIORequest, CreateMsgPort, DeleteMsgPort, AllocVec, FreeVec,
  CreatePool, DeletePool, AllocPooled, FreePooled, StackSwap.
- dos, V34-level: Open, Close, Read, Write, Input, Output, Seek, DeleteFile, Lock, UnLock, Examine, Info,
  CreateDir, CurrentDir, IoErr, UnLoadSeg, DateStamp, Delay, IsInteractive. **V36+**: AllocDosObject,
  FreeDosObject, FGets, FPuts, NameFromLock, SetMode, ExAll, SetIoErr, Fault, PrintFault, CreateNewProc,
  GetCurrentDirName, SystemTagList, LockDosList, UnLockDosList, NextDosEntry, DateToStr, ReadArgs (the command
  line is parsed with a ReadArgs template), MatchFirst, MatchEnd, FreeArgs, AddPart, GetVar, PutStr;
  **V37**: ParsePatternNoCase, MatchPatternNoCase.
- intuition, V34-level: CloseScreen, CloseWindow, CurrentTime, OpenWindow, PrintIText, SetPointer,
  IntuiTextLength, RethinkDisplay, LockIBase, UnlockIBase, RefreshGList, AddGList. **V36+**: LockPubScreen,
  UnlockPubScreen, EasyRequestArgs (its error requesters), OpenWindowTagList, OpenScreenTagList.
- graphics, V34-level: RectFill, SetAPen, SetBPen, SetDrMd, CBump, CMove, CWait, FreeVPortCopLists,
  UCopperListInit. **V36+**: GetVPModeID. **V39** (only on 3.0+ hosts, presumably behind a version test):
  ObtainBestPenA, SetChipRev, ReleasePen, FindColor.
- gadtools (all V36+): CreateGadgetA, FreeGadgets, GT_SetGadgetAttrsA, GT_GetIMsg, GT_ReplyIMsg,
  GT_RefreshWindow, CreateContext, GetVisualInfoA, FreeVisualInfo (the splash window and its gadgets).
- keymap.library (V36+): AskKeyMapDefault, MapRawKey (used to compare the user keymap with the one the installed
  program expects).
- utility (V36+): UMult32, UDivMod32.

### Behaviour from the official documentation (not re-observed here, since nothing ran)

- Start sequence ("How does it work"): load and check the Slave; allocate the memory of the installed program;
  with `Preload/S`, load disk images and files into RAM as far as memory allows; then switch the OS off: disable
  multitasking and interrupts, degrade the graphics hardware to OCS, initialise all hardware with defined values,
  and jump into the Slave.
- Memory: the installed program gets `BaseMem` = address 0 up to `ws_BaseMemSize` of chip memory (the Arte Slave
  asks for about 484 KB) and an optional `ExpMem` block (`ws_ExpMem`, about 488 KB for Arte) anywhere. The low chip
  area must therefore be taken over (AllocAbs calls are present) and its content saved for the return to the OS.
  The documentation warns that resident data at the end of chip memory gets in the way.
- OS switch during the game: when the program loads data that was not preloaded, WHDLoad re-enables the OS
  "partially" (restores hardware registers, display and memory), lets dos read the file, then switches it off
  again. This needs a fully working dos/handler stack under the restored OS, many times per game.
- Exceptions and vectors: on 68010+ WHDLoad may move the VBR; on a 68000 the vectors at address 0 are used. It
  reads the NMI vector once at start for freezer support. Quit key: a keyboard interrupt patched by the Slave or
  WHDLoad; on a 68000 without VBR some installs cannot quit.
- On exit it restores the hardware, display and memory and returns to the OS (Workbench or CLI).
- Workbench: an icon whose default tool is WHDLoad and whose tool types carry the options; the Slave name comes
  from the icon (WHDLoad opens `icon.library` V37 for it).

## What this means for a 1.3-compatible ROM

- Nothing to fix in our ROM for WHDLoad: the real 1.3 refuses it at the same two gates, and our ROM reproduces
  both gates exactly.
- Running WHDLoad would require exposing a Kickstart 2.04-level API: exec V36/37 (message port and IO request
  constructors, AllocVec, memory pools, caches, StackSwap), most of dos V36/37 (DOS objects, ReadArgs, buffered
  I/O, pattern matching, DOS list locking, CreateNewProc, SystemTagList, local variables), intuition V36 (public
  screens, tag-based Open*, EasyRequest), plus three libraries absent from 1.3 (gadtools, keymap, utility), the V37
  `LoadSeg` hunk types, and `lib_Version` >= 37 in ExecBase and in each of these libraries. That is a 2.0 ROM, not a
  1.3 one.

## Open points

- The Slave-side `resload_*` API and the OS-switch details were not exercised (no run passed gate 2). A 2.0 host
  would be needed for that, which is outside this project.
- The call attribution above is static and heuristic; it was not confirmed by tracing.
