# Architecture

## ROM model (Kickstart 1.3, 256K)

- Image of **262,144 bytes**, loaded at **`$FC0000`** (also mapped at `$0` on reset via the OVL overlay).
- Reset header in the first 8 bytes: longword `$0` = initial SSP (`0x11114EF9`, ROM-ID word
  `0x1111` + opcode `0x4EF9`), longword `$4` = initial PC = coldstart address (`$FC00D2` on an
  authentic ROM; `RESET` instruction `$4E70` at `$FC00D0`).
- Footer (container format, see amitools): checksum longword at `taille-0x18`, size field at
  `taille-0x14`, 8 words `0x0018..0x001F` at `taille-0x10`. Valid checksum = sum of the longwords
  (carry folded back) equal to `0xFFFFFFFF`. **Not verified by the OS before V37**, but required by the tools.

## Resident modules (ROMTags)

The OS builds itself through a scan of resident modules (struct `Resident`, matchword `0x4AFC`) in
**decreasing priority** order. The 24 modules of 34.5 and the ABI details are in
`docs/analysis/` (analysis track). Summary of the init order:

`exec`(120) → `expansion`(110) → `potgo`/`keymap`(100) → `cia`(80) → `disk`/`misc`/`ramlib`(70) →
`graphics`(65) → `keyboard`/`gameport`(60) → `timer`(50) → `audio`/`input`(40) → `layers`(31) →
`console`/`trackdisk`(20) → `intuition`(10) → `alert.hook`(5) → `mathffp`/`workbench.task`/`dos`(0) →
`romboot`(-40) → `strap`(-60).

## `src/` structure (clean track)

| Folder | Planned contents |
|---------|---------------|
| `src/rom/` | M0 hello-ROM (`start.s`) + `mkrom.py` (padding + footer + checksum) |
| `src/exec/` | exec.library, split into modules linked by vlink: `exec.i` (constants/ABI), `boot.s` (header/reset, coldstart, ExecBase, init_task, publish, selftest), `lists.s` (lists + Enqueue/Insert/RemHead/RemTail), `memory.s` (multi-header AllocMem/FreeMem, AvailMem, TypeOfMem), `library.s` (Open/Close/Forbid/Permit/Disable/Enable with yield-on-reschedule, jump table; **`OpenLibrary`/`CloseLibrary`/`OldOpenLibrary`**: opening by name = Forbid + `FindName(LibList)` + version gate (`lib_Version >= version`, otherwise 0) + call of the lib's Open/-6 vector; ramlib disk loading if non-resident deferred to M6), `tasks.s` (AddTask, FindTask, signals, Signal waking blocked tasks + requesting a reschedule if higher priority, SetTaskPri), `ports.s` (AddPort/RemPort under Forbid; M7d: PutMsg/GetMsg/ReplyMsg INTERRUPT-SAFE = Disable/raw_enable, atomic vs an IRQ that touches the same MP_MSGLIST), `interrupts.s` (init_ints + INT2/INT3/INT6/TRAP handlers sharing a **common prologue** `movem` (at the **native** IPL since M7e) and a **common epilogue** `intr_exit`; M7f: the 3 autovectors in use are UNIFORM — `int2_dispatch`(PORTS)/`int3_dispatch`(level 3)/`int6_dispatch`(EXTER) go through `intr_dispatch_number` -> server chain; the round-robin decision is `sched_server`, a server of the VERTB chain; M7g: `int3_dispatch` decodes `INTREQR` and dispatches EACH pending level-3 source (COPER/VERTB/BLIT); M7c: **user-mode** tasks on a **shared SSP**, `dispatch` **relocates** the context frame SSP↔user stack and saves the per-task nesting, `dispatch_in` rte's into user mode; voluntary switch via `trap #0`/`#1`; **deferred dispatch flag** `intr_isr_defer` at IRQ exit when a server sets `AttnResched`; M7e: critical section of the switch raised to a **brief IPL7** = re-entrancy gate of the lists, instantaneous vs INTENA's propagation delay; dispatcher by number `SetIntVector`/`AddIntServer`/`intr_chain_walker`, M7b), `resident.s` (ROM scan of the ROMTags → pri-sorted `ResModules`, `FindResident`/`InitResident`/`InitCode`), `libinit.s` (`MakeLibrary`/`MakeFunctions`/`InitStruct` — lib/device creation, AUTOINIT path), `resident.s` also adds `AddResource`/`OpenResource`; **`cia.s`** (`cia.resource`: 1st real resident module — ciaa/ciab + PORTS/EXTER servers `ciaa_server`/`ciab_server` + ICR dispatch), **`timer.s`** (`timer.device`: 2nd real resident, AUTOINIT device + VBLANK unit + MICROHZ unit via CIA-B/INT6), **`trackdisk.s`** (`trackdisk.device` — **B1/M6t**: 2nd device, ROMTag AUTOINIT pri 20 → DeviceList; `Open` validates the unit number (DF0-3 → io_Unit = unit area, io_Device = base, OpenCnt++; unit ≥ 4 → OpenDevice failure io_Error/io_Device=0); `BeginIO` (**B4/M6w** then **multi-track M6z**: handles **`CMD_READ`** — converts the byte offset into (track, sector) via `bloc=offset/512`, `piste=bloc/11`, `secteur=bloc%11`, loops over EACH touched track via td_read_track+td_decode_track, copies up to the end of the track and advances → a request CROSSING a track boundary is served in several reads; guards `IOERR_BADLENGTH` (offset/length multiples of TD_SECTOR) and `TD_DISKBYTES` (bound); other commands → IOERR_NOCMD; **ReplyMsg if non-quick** written but only the QUICK path is proven for now — the non-quick one will be exercised by a real `DoIO` in C); units = placeholders → Unit+MsgPort in B2. **B2/M6u**: `td_read_track0` reads a raw MFM track from DF0 — CIA-B DDRB=$FF + PRB motor/select DF0 (latched via the SEL0 edge), spin-up (DSKRDY poll with timeout), **Paula disk DMA** (ADKCON WORDSYNC, DSKSYNC=$4489, DSKPT, DSKLEN×2), poll `INTREQR` DSKBLK with timeout; registers/bits in `disk.i`. Writes ONLY CIA-B PRB (MICROHZ/M7a timers intact). **B2b/M6x**: `td_read_track(n°)` seeks first — recalibration to track 0 (step OUT via DSKDIREC until DSKTRACK0) then step IN up to the target cylinder + side-select (DSKSIDE according to track&1) → reads any track; `td_decode_track` returns the decoded track no. (seek oracle). **B3/M6v**: `td_decode_track` scans the $4489 syncs, decodes each sector (odd/even combine `((odd&$55555555)<<1)|(even&$55555555)`), checks the header AND data checksums (XOR of the MFM longs & mask), stores the 512 bytes by sector no. → 11 sectors decoded+verified, sector 0 = bootblock "DOS\0"; algorithm locked by a Python round-trip), **`strap.s`** (`strap_boot` — **M6r**: SCAFFOLD of the boot decision; returns 0 = no bootable volume → the caller **routes** the display of the insert-disk screen through this decision; `FindName(trackdisk)` + CMD_READ + validation/execution of the bootblock will come in increments B/C); linker script `kick.ld`, `execmisc.s` (complementary V34 exec LVOs: SetFunction, Cause/SOFTINT, Alert, SuperState...) |
| `src/graphics/` | graphics track (M4+): `graphics.i` (OCS display registers derived from `CUSTOM`: COP1LC/COPJMP1/DIW/DDF (overscan 352×272)/BPLCON0/1/BPL1-2MOD/BPL1PT/COLOR00-01 + DMACON bits; boot screen dimensions), `gfx.s` (`gfx_display_init` — **M6s**: allocates 5 chip bitplanes, COPIES the **boot screen** into them (kitten image "KickSlopStart" 352×272×5 = 32 colours, overscan) from the ROM, sets up BitMap/ViewPort/View/ColorMap(32), `FindName("graphics.library")`, then `MakeVPort`/`MrgCop`/`LoadView` **through the jump table** → the copper list (5 plane pointers + 32 colours) is GENERATED by the ABI; restores `a6`=SysBase. M4a/M4b/M4c2 history: 1-plane striped screen, replaced here by the image), **`graphics_lib.s`** (`graphics.library` — ROMTag AUTOINIT pri 65 → `MakeLibrary` into `LibList`, **M4c1**; **M4c2** display engine, **M6s**: `MakeVPort` made **GENERIC** — emits one BPLxPT pointer per plane (depth) + `cm_Count` colours COLOR00.. → supports 1 plane/2 colours as well as 5 planes/32 colours; `MrgCop` merges → `v_LOFCprList`, `LoadView` installs COP1LC + `DMACON`), `mk_bootscreen.py` (Pillow pipeline generating the boot screen data: user JPEG → 352×272 → quantize 32 colours → 5 planar bitplanes, **self-checking**; outputs `bootscreen.raw` + OCS palette + reference PNG) + `bootscreen_data.s` (GENERATED: palette + `incbin bootscreen.raw`). VISUAL discriminant (number of unique captured colours); proof by elimination (RED `BOOTSCR_ONE_PLANE`); **`draw.s`** (WB step 6): drawing primitives in a RastPort (Move/Draw/RectFill/SetRast/WritePixel/Text/ScrollRaster...), clipping by the bounds of `rp_Layer`; fills by `dr_rect` (once per ClipRect and per plane, longs/words) and segments by `dr_line` (Bresenham with incremental address), "string" path of Text in all modes, BltTemplate by fixed operation per plane, see probes `tests/drawcheck.s` (pixels) and `tests/drawperf.s` (timing) |
| `src/intuition/` | intuition track (M5+): `intuition.i` (V34 `IntuitionBase` layout — stable 1st-generation fields: `ib_LibNode`/`ib_ViewLord` (embedded View = the "ViewLord")/ActiveWindow/ActiveScreen/FirstScreen/Flags/Mouse/Seconds/Micros; `INTUITIONBASE_SIZE`=80; LVO `ViewAddress`=-294), **`intuition_lib.s`** (`intuition.library` — resident module ROMTag AUTOINIT pri 10 → `MakeLibrary` into `LibList` (NT_LIBRARY branch), **M5**: Open/Close/Expunge skeleton + `ViewAddress` (vector 49) returning `&ib_ViewLord`). SERIAL discriminant (marker M5I); proof by elimination (RED `M5I_BAD_VIEWADDR`). **`screens.s`** (WB step 6): OpenScreen/CloseScreen/OpenWorkBench/GetScreenData, drawn OpenWindow/CloseWindow (RastPort + pseudo-layer per window); `requester.s`/`pointer.s`: clickable insert-disk requester and pointer accumulator |
| `src/dos/` | dos track (M6+): `dos.i` (layout of `DosLibrary`/`RootNode`/`DosInfo` (dosextens.i) + **BPTR** convention (`addr>>2`) + `DateStamp` + LVO `DateStamp`=-192; scaffold `DL_DISHADOW` = raw DosInfo APTR for BPTR self-check without dereferencing), **`dos_lib.s`** (`dos.library` — resident module ROMTag AUTOINIT pri 0 → `MakeLibrary` into `LibList`, **M6**: Open/Close/Expunge skeleton + initfunc that allocates RootNode + DosInfo **separately** via AllocMem (long-aligned, required for BPTR), wires `dl_Root` (APTR) and `rn_Info` (BPTR), + `DateStamp` (vector 32) filling (0,0,0) "clock not set" (faithful to V34) and returning the pointer. Deliberate clean-room deviation: C-style init instead of the original BCPL glue — observable ABI reproduced, not the mechanism). Deferred: packets/LoadSeg/handlers, Open/Read/Lock, strap/trackdisk, insert-disk screen. SERIAL discriminant (marker M6D); proof by elimination (RED `M6D_BAD_BPTR`). **`ofs.i` + `ofs.s`** (**D1**: read-only OFS — INTERNAL filesystem machinery, NO BCPL packets/handler = D3): `ofs_read_file(name, dest, max)` reads a file by name by walking root@880 → hash table (hash `h=(h*13+toupper(c))&$7FF`, idx=`h%ht_size`) → header (BCPL name, sec_type ST_FILE, first_data, hash_chain) → chain of OFS data blocks (type 8, data_size, next, data @+24), via trackdisk `CMD_READ` (M6z). Case-insensitive; validates type/sec_type/block bounds before each read; capped loops (anti-hang). Format locked empirically on a test ADF. SERIAL discriminant (marker **D1**, size==1024 + multi-block markers); proof by elimination (RED `OFS_NO_DATACHAIN` → size 488). **`loadseg.s`** (**D2**: LoadSeg — INTERNAL machinery, no packets = D3): `dos_loadseg(name)` → BPTR seglist | 0, `dos_unloadseg(BPTR)`. Loads a "hunk" executable from the OFS (via `ofs_read_file`), allocates one segment per hunk, copies the contents, **applies the HUNK_RELOC32 relocations** ($3EC; $3FC/SYMBOL/DEBUG → clean failure), builds the BPTR seglist (`[taille][next BPTR][contenu]`, BPTR → block+4, contents at `(BPTR<<2)+4`). Hunk format locked empirically. SERIAL discriminant (marker **D2LOADSEG**, emitted by the loaded+relocated code running from RAM); proof by elimination (RED `D2_NO_RELOC` → reloc not applied → pointer to low RAM → marker absent), `ofswrite.s` (OFS writing: creation, stream, deletion, renaming, Info) |
| `src/resources/` | cia, disk, misc, potgo, keymap |
| `src/devices/` | timer, keyboard, gameport, input, audio, console, trackdisk |
| `src/libs/` | expansion, graphics, layers, intuition, mathffp, dos |

## Build pipeline

1. **Main ROM** (`make kick`): `vasmm68k_mot -Fvobj` assembles each exec module into a relocatable
   object, then `vlink -b rawbin1 -T src/exec/kick.ld` links them at `$FC0000` into a raw image.
   **Load-bearing order**: `boot.o` is passed first → its CODE carries the reset header at `$FC0000`.
2. **Production ROM** (`make kick-prod`): same pipeline with `-DPROD=1` (`PROD` flag in
   `src/exec/exec.i`, default 0 protected by `ifnd` → override without editing the source). Objects isolated
   in `build/prod/`, image `build/kick13-prod.rom`; the dev ROM stays **byte-identical**. The `ifeq PROD`
   gates of `boot.s` remove the **RUNTIME harness** from the boot path: M7 demo tasks
   (`task_h/l/s/timer/port/fa/fb`, spinners), D3 test clients/drivers (echo `d3a`, fs-driver `d3b`,
   `d3c_client`, `d3d..d3j` — they read test files absent from a real disk), proof probes
   (VERTB tail server `vbl_tail`, COPER source), M7d port stress (neutralised via `ifne PROD`).
   **Kept**: the whole real OS — `build_reslist`+`InitCode` mounts ALL the real modules (the "M4 scan"
   covers the whole ROM, not only demo residents), CIA-B/MICROHZ timer, live gameport, DF0: mounting
   (OFS handler + DeviceNode), con_handler, feeder, strap (floppy boot OR insert-disk screen), Initial CLI.
   The final hand-off (`RemHead(TASKREADY)`+`dispatch_in`) is generic; in prod the system idles via
   `.d_idle` instead of spinners. `kick-prod` **removes the harness, adds no OS capability**: booting
   a complete game remains a separate milestone (identical dev/prod — see the Lemmings smoke test in the ledger).
3. **hello-ROM** (`make hello`): single file via `vasmm68k_mot -Fbin` (M0 smoke test).
4. `src/rom/mkrom.py` pads to 256K, writes the footer + size field + checksum.
5. `romtool info` validates the container (`is_kick = ok`, `chk_sum = ok`) — hard gate of `make verify`.
6. `tests/boot_test.sh` boots the image under FS-UAE and asserts the **serial log** (primary channel, captured
   via a `socat` PTY bridge on `serial_port`): success marker present + failure marker absent;
   automatic fallback to the screen colour if there is no serial emission (e.g. hello-ROM). The ROM emits
   checkpoints (`chk core`/`chk mem`/`chk m24a|b|c` → `self-test passed`) locating any failure.

## Status

- **M0** (hello-ROM): delivered, verified (`is_kick` + green-screen boot).
- **M2.0→M2.3** (exec coldstart, `src/exec/`): delivered, verified (**white** screen boot = self-test passed).
  The reset enters at `$FC00D2`, switches to supervisor + freezes the hardware, **turns off the overlay** (chip RAM at
  `$0`), sets a stack below the jump table, builds **ExecBase** at `$7F000` (library node 34.2,
  `ChkBase=~base`, `MaxLocMem=$80000`, `AttnFlags=0`, `VBlankFrequency=50`, 9 system lists `NEWLIST`),
  builds the **V34 LVO jump table** (105 vectors, `lib_NegSize $276`, see `docs/exec-lvo-table.md`)
  with 13 LVOs implemented (Open/Close/Expunge, Forbid/Permit, Disable/Enable, AddHead/AddTail/Remove/
  FindName, AllocMem/FreeMem), initialises a **chip MemHeader** + MemList, publishes `SysBase` at `$4`,
  then **self-checks** and **self-tests** the functions through the jump table (dispatch + behaviour +
  coalescing). Phases traced in colour (red→blue→cyan→white; magenta = failure).
- **M2.4**: **multi-MemHeader** memory (selection by attribute, AvailMem, TypeOfMem);
  list primitives (Enqueue sorted by priority, Insert, RemHead, RemTail); non-blocking **tasks + signals**
  (TCB `ThisTask`, FindTask, AllocSignal/FreeSignal/SetSignal/Signal, SetTaskPri);
  non-blocking **ports/messages** (AddPort/RemPort/FindPort, PutMsg+Signal, FIFO GetMsg, ReplyMsg).
  ⚠️ "green" = structures handled correctly, NOT real scheduling. **Deferred to M3**
  (requires interrupts): blocking `Wait`/`WaitPort`, `AddTask`/`RemTask`, dispatch
  (`Switch`/`Dispatch`/`Cause`), waking a task on a signal.
- **M3a**: **interrupt plumbing**. 68000 level-3 autovector (`$6C`) → VBlank handler,
  `INTENA = VERTB|INTEN` ($C020), `SR=$2000` → the interrupt chain runs (VBlank counter that
  advances, proven over serial).
- **M3b**: **preemptive scheduler** (**supervisor** tasks). The VBlank handler is the preemption
  point: round-robin (saves the outgoing task's SP in `TC_SPREG`, Enqueue into `TaskReady`, RemHead
  the incoming one, restores its SP + GPRs, `RTE`). `AddTask` (-282) sets up the initial frame mirroring the dispatcher's
  pop. Proven by 2 demo tasks that **alternate** on serial (preemption) **while preserving
  their context** (register sentinels).
- **M3c** (mutual exclusion, prerequisite #1): `Forbid()` is now **honoured** by the scheduler.
  The VBlank handler defers the switch if a critical section is active — double guard `EB_TDNEST >= 0`
  (Forbid) **or** `EB_IDNEST >= 0` (Disable, closes the `addq`/`INTENA` window). These counters are
  **global** (ExecBase): legitimate because a forbidden task is never switched out, so `EB_TDNEST`
  always reflects the current task; since the switch does not touch these counters, no task is
  resumed with another one's count. **Defer-to-next-VBlank** model (no immediate yield on
  `Permit` in this milestone): the deferred switch is picked up at the next tick, never lost (`Permit`/`Enable`
  remain simple decrements/increments). exec critical sections wrapped in **Forbid/Permit** (task-vs-task
  exclusion; `Disable` is NOT used in this milestone — it would disturb `INTENA` during the
  pre-interrupt selftest) with a **single exit**: `AllocMem`/`FreeMem`/`AvailMem`/`TypeOfMem`
  (memory lists) + `AddPort`/`RemPort`/`PutMsg`/`GetMsg`/`ReplyMsg` (PortList + message queues).
  The raw list primitives and `FindName`/`FindPort` remain **unwrapped** (building blocks
  arbitrated by the caller, V34 exec contract; and the handler calls them -> wrapper = re-entry).
  Proven **deterministically** (shared counter observed across a forbidden window, independent of
  serial timing): `M3C LIVE` emitted iff Forbid honoured (A) AND no starvation (B). REDs verified:
  Forbid guard removed -> `FAILED`; `Permit` removed -> `EB_TDNEST` drift caught right at the
  Forbid/Permit assertion of the selftest.
- **M3d** (`Wait`/`WaitPort` + wake-on-signal): a task can now **block**.
  `Wait(sigset)` does a **SYNCHRONOUS switch** (voluntary): if no awaited signal is present,
  it pushes on ITS stack a frame that is an **exact mirror** of `vbl_handler`'s (`[d0-d7/a0-a6][SR][PC]`),
  puts the task in `TS_WAIT` in `TaskWait`, `RemHead`s the incoming one from `TaskReady` and switches — the
  two dispatch paths (preemptive + voluntary) share this format and `interrupts.s`. All the
  surgery is at **IPL 7** (atomic vs VBlank). `WaitPort(port)` loops `Wait(1<<MP_SIGBIT)` as long as
  the queue is empty; no lost wakeup (PutMsg does `AddTail` BEFORE `Signal`, and `Wait`'s recheck
  is atomic). `Signal` **wakes** a `TS_WAIT` task whose awaited bits arrive
  (`TaskWait` → `TaskReady`, `TS_READY`); the woken task runs at the **next scheduling point**
  ("defer" model, see yield-on-Permit below). Proven **deterministically** by a 2-port **request/reply
  ping-pong** (deadlock-free: exactly one task ready at each block):
  `M3D LIVE` emitted after `M3D_THRESH` round trips (repeated correct blocks+wakes); invariant
  `GetMsg != NULL` after `WaitPort`. REDs verified: wake-up disabled (`Signal`) → deadlock, marker
  absent; blocking disabled (`WaitPort` returns on an empty queue) → `GetMsg` NULL → `M3D FAILED`.
  Deliberate V34 assumption: `Wait` called outside `Forbid`/`Disable` (which it would break); return at IPL 0.
- **M3e** (immediate yield on `Permit`): a **higher-priority** woken task now runs **right at the
  `Permit`** that closes the waker's critical section, instead of waiting for the next tick. `Signal`,
  when it wakes a task with priority > the current one, sets `EB_ATTNRESCHED` (exec ABI `$12A`).
  `Permit`/`Enable`, on returning to the permitted state (`TDNest`/`IDNest` < 0, the other one not locked), if
  `AttnResched` is set, call `reschedule`: a **SYNCHRONOUS switch without blocking** that requeues the
  current task in `TaskReady` (round-robin by priority) and switches to the head (the higher-priority woken task).
  `reschedule` reuses the **common switch tail `dispatch_head`** (shared with `Wait`) and sets the
  same dispatcher-mirror frame; it works **independently of `SCHED_ON`** (direct switch, no
  IRQ). Proven in **COOPERATIVE** mode (`SCHED_ON=0`, no periodic preemption) to **isolate** the
  proof: task_L (pri 0, never blocks) `Forbid`/`Signal(task_H)`/`Permit`; task_H (pri 10) loops on
  `Wait`. The ONLY dispatcher of task_H is `Permit`'s `reschedule` → `M3E LIVE` emitted after 500 yields
  ⟺ yield-on-Permit correct. RED: yield disabled in `Permit` → task_H starves (marker absent).
- **M3f** (recombination of yield + preemption): periodic preemption (`SCHED_ON=1`) and
  yield-on-`Permit` **coexist without context corruption**. The three switch paths are
  unified: `dispatch_head` (RemHead + switch + `rte`, common to all three) and `requeue_and_dispatch`
  (round-robin requeue of the outgoing task + `clr AttnResched` + `dispatch_head`, shared by the handler and
  `reschedule`). The handler **clears `AttnResched` on every switch** (a tick satisfies a pending yield
  request → no redundant `reschedule` at the next `Permit`); `reschedule` re-tests
  `AttnResched` at IPL 7 (idempotent, closes the read-at-IPL0/call race). Proven by 3 tasks
  (`SCHED_ON=1`): task_H (pri 10, yield target), task_L (pri 0, signals+yields), task_S (pri 0,
  pure spinner dispatched ONLY by preemption). Context sentinel (d7) checked after
  every switch in all three tasks → `M3F FAILED` if corrupted. `M3F LIVE` emitted when `WP_CONS`≥100
  (repeated yield) AND `WP_SPIN`≥5 (task_S ran via preemption). **Preemption confirmed load-bearing**
  by the RED (`SCHED_ON=0` → task_S monopolises → task_L no longer signals task_H → `WP_CONS` freezes →
  marker absent). Scope of the proof: M3f validates the **mechanics** of the yield and the coexistence without
  corruption; the **necessity** of the yield remains proven by M3e (cooperative demo, commit 18cba43), because
  under `SCHED_ON=1` a tick would dispatch task_H anyway (proof not isolable in a single mode).
  The anti-race code (handler clears a set `AttnResched`, `.rs_none` branch) is correct by
  inspection but **inert** in this demo (task_L signals under Forbid → the tick defers).
- **M4** (resident scan + InitResident): the **data-driven discovery machinery** of the modules.
  `build_reslist` (`resident.s`) scans `[RESSCAN_LO,RESSCAN_HI)` (the whole ROM) for ROMTags —
  `RTC_MATCHWORD` word ($4AFC) at an even address whose `RT_MATCHTAG` points to itself (rejects a
  stray `$4AFC`, e.g. the immediate of the scan's own `cmp.w`) — resumes at `RT_ENDSKIP`, builds the
  NUL-terminated array `ExecBase->ResModules` sorted by **decreasing** `RT_PRI` (stable bubble sort).
  `InitCode` walks it and calls `InitResident` on each module (version filter). `InitResident`
  validates the matchword then, for direct-init (RTF_AUTOINIT clear), jumps to `RT_INIT` with the
  ABI convention **`D0=0, A0=segList, A6=ExecBase`** (the resident is not passed); **AUTOINIT (MakeLibrary +
  InitStruct) is DEFERRED** (no-op). `FindResident` searches by name in `ResModules`. Proven by 3
  demo residents (pri 60/10/-20) **placed in memory in a different order** (mid, lo, hi) so that
  the sort is load-bearing: names emitted `hi→mid→lo` (priority order), `RES_COUNT==3`, FindResident
  finds the right one. RED: sort disabled → init in scan order → order check fails; `InitResident`
  dispatch disabled → `RES_COUNT=0`. ⚠️ **This is NOT yet the boot handoff**: the M4 phase
  runs then the hard-coded M3f demo executes (real launching by a resident will come with the
  real modules). Direct-init convention **checked** against the exec AutoDoc (corrected along the way).
- **M5a** (AUTOINIT: `MakeLibrary` + `MakeFunctions` + `InitStruct`): the AUTOINIT path of
  `InitResident`. `MakeLibrary(vectors, structure, init, dataSize, segList)` allocates negSize (jump table)
  + dataSize (`MEMF_CLEAR`), base = alloc+negSize, builds the jump table via `MakeFunctions` (vectors
  **absolute** longword OR **relative** word if the 1st word = -1, terminated by -1), sets
  `LIB_NEGSIZE`/`LIB_POSSIZE`, `InitStruct`s the data table then calls the init function (**D0=base,
  A0=segList, A6=ExecBase**). `InitStruct` interprets the `ddssnnnn` stream (INITBYTE/WORD/LONG path:
  dd=11 24-bit offset, ss size, single item, + word re-alignment + 00 terminator). `InitResident`
  AUTOINIT: `MakeLibrary` then Enqueue of the base in the list according to `RT_TYPE`, **without** filling
  name/type/version (V34 quirk — the module does it). Direct-init calling convention (D0=0/A0=segList)
  vs MakeLibrary init (D0=base/A0=segList): **checked against the AutoDoc** (distinct). Proven by
  a demo AUTOINIT resident (`demo.autolib`, relative vector table): jump table built (func0 returns
  $5A via `jsr -6(base)`, the order of the vectors is load-bearing), `InitStruct` sets version+type, init
  func sets revision+name, lib found in `LibList`. RED: `InitStruct` disabled → version wrong; init
  func call removed → name wrong.
- **M5b** (`cia.resource` — 1st real resident module): ROMTag `cia.resource` (direct-init, pri 80)
  scanned by `build_reslist`; `cia_init` creates `ciaa.resource` + `ciab.resource` via `MakeLibrary`
  (library-like base + jump table `AddICRVector`/`RemICRVector`/`AbleICR`/`SetICR`), names them, sets the
  CIA hardware base (`$BFE001`/`$BFD000`), `AddResource`. Exec exposes `AddResource` (-486, Enqueue
  `ResourceList`) and `OpenResource` (-498, `FindName`). The functions manage the 5 ICR vector slots
  + the ICR mask shadow + the chip's ICR register (`AbleICR` bit7=enable). Proven: `OpenResource`
  ("ciab.resource") finds the base, correct hardware base, `AbleICR($81)` sets bit0 of the shadow,
  `AddICRVector` registers (returns NULL, free slot). RED: `AddResource` broken → not found; `AbleICR`
  broken → shadow wrong. ⚠️ **DEFERRED**: the **INT2/INT6 dispatch** (the registered vectors do not
  fire — Paula INTENA PORTS/EXTER + autovectors `$68`/`$78` not set → inert and safe).
  `SetICR` is a stub (interrupt status deferred). CIA vector table **absolute** (the demo
  M5a AUTOINIT demo being relative, both branches of `MakeFunctions` remain exercised).
- **M5c** (`timer.device` — 2nd real resident, 1st device): ROMTag `timer.device` **AUTOINIT** (pri 50)
  scanned then created by the AUTOINIT path of `InitResident` (`MakeLibrary` + Enqueue into `DeviceList` by
  `RT_TYPE`=NT_DEVICE). Its data table (`InitStruct`) sets `LN_TYPE`=NT_DEVICE + `LIB_VERSION`; its init
  func sets `LN_NAME`="timer.device" (V34 quirk: `InitResident` does not fill the fields). Standard
  device vectors (Open/Close/Expunge/ExtFunc/BeginIO/AbortIO), stubs. Proven: `FindName(DeviceList,
  "timer.device")` finds the base, `LIB_VERSION`/`LN_TYPE` (InitStruct), `Open` via `jsr -6(base)`
  increments `LIB_OPENCNT`. RED: name not set → not found; `Open` broken → count wrong. ⚠️ **SCOPE**:
  device **created + named + listed + jump table (Open)**. **DEFERRED**: units (VBLANK/MICROHZ/ECLOCK),
  request queue, functional `BeginIO` (stub). The scan thus produces the OS by instantiating REAL
  resident modules — but neither `cia.resource` nor `timer.device` does any functional work yet
  (named/listed skeletons). The **demo** residents (`demo.res.*` + `demo.autolib`) are **kept**
  in the scan as M4/M5a non-regression coverage (they interleave by priority and strengthen
  the proof of the sort) — to be removed when the real modules cover these proofs.
- **M6a** (**functional** VBLANK unit of `timer.device`, without CIA): **first observable OS
  behaviour** produced by the resident machinery + interrupt + messages. `BeginIO(TR_ADDREQUEST)`
  converts the timeval into ticks (`secs*50 + micro/20000` for the VBLANK unit; M7l separates the conversion of
  the MICROHZ unit into real µs, see the M7l bullet), stores the countdown in `TR_TIME`, enqueues
  the request on the VBLANK unit's queue (under `Disable` — queue shared with the handler). The VBlank
  handler calls `timer_vblank_service` every tick (originally the `VBL_SVC` hook; **M7f**: became a
  server of the VERTB chain); the service decrements each request and, at 0, removes it and **replies** to it.
  KEY POINT (originally M6a): the reply in interrupt context could NOT use `PutMsg`/
  `ReplyMsg` because they called `Permit` -> `reschedule` **synchronously in the middle of the interrupt**;
  M6a therefore used a bespoke routine (`timer_reply`) that only set `AttnResched`. **M7d** made
  `PutMsg`/`ReplyMsg` interrupt-safe (Disable/`raw_enable`, without yield) and **M7i** removed `timer_reply`
  in favour of direct `ReplyMsg` (see the M7i bullet). Proven (M6a): a request of
  100000 µs (= 5 ticks) is replied to after ~5 VBlanks (measured delay ∈ [3..40]) **and** `exec_Signal`
  from the handler does set the bit (checked in the boot task's `TC_SIGRECVD`). RED: hook cut →
  timeout; reply removed → timeout. **SCOPE**: proven = timer+interrupt+messages+`exec_Signal`
  from the IRQ; **NOT yet shown** = a task that **blocks** on a timer and is woken
  (`Wait`→timer-wake) — requires a real waiting task (the boot task is `TS_RUN`, no-wake branch).
- **M6b** (CIA interrupt dispatch, INT2/CIA-A): the ICR vectors registered in `cia.resource`
  now **fire**. `init_ints` installs the 68000 autovectors `$68` (INT2/CIA-A) and `$78`
  (INT6/CIA-B) and enables Paula INTENA PORTS (not EXTER — see below). `int2_handler` raises IPL 7,
  reads the chip's ICR register **only once** (ACK + clears all pending bits), then `cia_dispatch`
  calls the vector of each set bit (`a1`=IS_DATA, `a5`=IS_CODE, `a6`=SysBase), and acknowledges Paula.
  Same mid-handler discipline as M6a (a vector that `Signal`s does not reschedule inside the IRQ; loop
  state in d2/d3/a2, which the server convention preserves). Proven **end to end**: `AddICRVector`
  (timer A, bit 0) + start of CIA-A Timer A one-shot → underflow → /IRQ CIA-A → INT2 → autovector →
  `cia_dispatch` → the test vector increments a counter (detected by the boot). RED: vector call
  cut → timeout; **chip ICR enable cut → timeout** (this RED proves the whole chain, because it can
  only pass if the emulated CIA really drives the interrupt). Cleanup after the proof (RemICRVector +
  timer stop + PORTS disabled).
  ⚠️ **Gate (M6b → requalified by M7a)**: M6b ran in a **cooperative** context (`SCHED_ON=0`) +
  CIA disabled before M3f, because an active CIA source of level > 3 under preemption posed a hazard
  (see M7a for its exact nature, which was not the one originally written here). `int6_handler`/EXTER
  (CIA-B) remained wired but not enabled. **M7a lifts this blocker for list re-entrancy.**
- **M7a** (list re-entrancy gate + MICROHZ unit via CIA-B/INT6 + task blocking on a timer):
  **the real hazard was not the stack** (in the supervisor-tasks-same-stack model, the interrupt
  frames unstack correctly; stack corruption through a shared SSP remains **latent**
  until user mode = M7c). The real hazard = **re-entrancy of the scheduler lists**: `vbl_handler`
  did its TaskReady `Enqueue`/`RemHead` at **IPL3**, so INT6/CIA-B (level 6 > 3) could
  preempt it right in the middle, and the `exec_Signal` of the MICROHZ wake-up also did `Enqueue(TaskReady)` on
  the same half-updated list → corruption. **Fix 1**: `requeue_and_dispatch` raises IPL7 around
  the critical section only (not the whole `vbl_handler` — INT6 must preempt the VBlank elsewhere);
  `exec_Wait`/`reschedule` already entered it at IPL7. **Fix 2**: `timer_reply` does its `AddTail`
  (reply-port msglist, shareable between the VBLANK and MICROHZ units) at IPL7. The **MICROHZ unit**
  (2nd queue `TIMER_MICROQ`, decremented by `timer_micro_service` registered as the ICR vector of CIA-B's
  timer A) wakes a **blocked task** (`task_timer`: `BeginIO`→`Wait`→wake by the IRQ). **Structural**
  proof via `VBL_INSURG`/`VBL_CLASH`: at IPL7 INT6 is masked during the surgery →
  `VBL_CLASH==0` is **guaranteed** (not probabilistic). GREEN "M7A TIMER OK" (wake-ups + `VBL_CLASH==0` +
  5 s time gate). RED#1 (gate removed, IPL3) → clash < 1 s → "M7A FAILED". RED#2 (wake-up broken) →
  `task_timer` frozen, "M3F LIVE" still present → isolates the wake-up path. Yield re-proven in
  **cooperative** mode (`SCHED_ON=0`, `task_S` removed → `task_timer` woken by the yield alone): my change
  to the shared tails did not regress the reschedule. `int6_handler`/EXTER now **enabled and tested**.
  MICROHZ in M7a = "1 tick = 1 CIA-B IRQ" (IRQ/wake-up path proven; **real µs calibration delivered in M7l**).
- **M7b** (interrupt dispatcher BY NUMBER): table `IntVects[16]` (AllocMem'd, pointer in
  `EB_INTVECTS`) + `SetIntVector` (exclusive vector: copies IS_DATA/IS_CODE) + `AddIntServer` (server
  chain sorted by `LN_PRI`, walked by `intr_chain_walker`; Z clear on return = "handled, stop", Z set =
  continue, see AutoDoc). The hardcoded autovectors `int2_handler`/`int6_handler` are replaced by
  **generic** `int2_dispatch` ($68/PORTS) / `int6_dispatch` ($78/EXTER) that dispatch via `IntVects`.
  cia.resource is re-expressed as SERVERS: `ciaa_server` (PORTS, via `AddIntServer`) and `ciab_server`
  (EXTER, via `SetIntVector`) — i.e. cia.resource IS the PORTS/EXTER handler, as in the real exec.
  CAVEAT: dispatch by NUMBER + chain, NOT PER-LEVEL IPL fidelity (the handlers stay at IPL7 on
  entry, M7a gate discipline); VERTB keeps a dedicated `vbl_handler` (VERTB→chain refactor + switch-on-
  IRQ-exit deferred). PROOF: GREEN "M7B PORTS OK" (chain [ciaa_server pri 10, srv2 pri 0], the 2
  called in order) + "M7A TIMER OK" now via `SetIntVector`/EXTER + "M3F LIVE". RED: 2nd
  server not added → M7B FAILED; EXTER vector removed → M7A absent; M7a gate (IPL7 removed) re-proven
  through the new EXTER path → `VBL_CLASH>0` → M7A FAILED. Two bugs caught during bringup:
  (1) vasm truncates an EQU operand at the space -> `INTVECTS_TOTAL` underestimated (128 instead of 352) ->
  under-allocation; (2) `move.l (an),Ax` = MOVEA which does NOT AFFECT the CCs -> `beq` on stale flags ->
  read `node->Succ` into a DATA register first.
- **M7c** (USER-MODE tasks on a shared SSP + DEFERRED switch): tasks run in user mode
  (SR bit S=0), each on **its own user stack**; interrupts + kernel on **ONE shared supervisor stack**
  (STACKTOP region). Derived from the public "The Exec Microkernel" spec (AROS) + 68000 mechanics, zero
  transcribed code. Common prologue (IPL7 + `movem` → frame `[GPR][SR][PC]` 66 bytes on the SSP); the `intr_exit` epilogue
  dispatches ONLY at the **user boundary** (S bit of the saved SR == 0 = a user task was interrupted,
  not a nested IRQ — this is the nest count, read from the S bit). `dispatch` **relocates** the SSP frame→user
  stack of the outgoing task (`TC_SPREG` now points into a user stack), saves/restores the PER-TASK nesting
  (`TC_IDNESTCNT`/`TC_TDNESTCNT`↔`EB_*`) and synchronises INTENA → the SSP is NEVER shared between task
  contexts (hazard neutralised). VOLUNTARY switch (Wait/reschedule) via `trap #0`/`#1`. `AddTask` sets SR=$0000
  + nesting=-1. `exec_Signal`/`exec_Wait`/`timer_reply` move from SR atomicity to a **bare critical section**
  (Disable INTENA + `raw_enable`, user-safe, callable from an IRQ without scheduler re-entrancy). Launching
  the 1st task = supervisor→user transition. **Deferred dispatch flag** (exec spec): an IRQ server that
  wakes a higher-priority task (AttnResched set by Signal) causes the switch at interrupt EXIT,
  without waiting for a Permit or the VBlank — otherwise the wake-up depends on phase luck (resonance). PROOF: GREEN
  "M7C USERMODE OK" (user mode proven by `move sr` → S bit==0, + N preemptions survived) with M3F/M7A/M7B
  still GREEN on the new model (7/7 runs, `VBL_CLASH==0`, d7 sentinels intact). RED: tasks in
  supervisor ($2000) → hang; relocation bypassed (inline sp-swap on the shared SSP) → crash; prologue IPL7
  removed → crash. Cooperative (SCHED_ON=0, task_s removed) re-proven: M3F LIVE via the yield alone + M7A.
- **M7d** (INTERRUPT-SAFE ports): `PutMsg`/`GetMsg`/`ReplyMsg` manipulate `MP_MSGLIST`, which can be touched
  from an INTERRUPT (IRQ-driven device). Forbid (TDNest) does NOT mask interrupts -> an IRQ
  that `PutMsg`/`ReplyMsg`s can interleave with a task's `GetMsg` on the same doubly linked list
  (RemHead vs AddTail) -> corruption. FIX: BARE critical section (Disable INTENA + `raw_enable`, without the reschedule
  tail -> no scheduler re-entrancy from the IRQ), which ALSO masks interrupts. AddPort/
  RemPort stay Forbid (PortList not touched by IRQs). ReplyMsg->PutMsg->Signal nesting: only the outermost
  `raw_enable` turns INTEN back on. PROOF: serial "M7D PORTS OK" — a shared port (K=4 messages, MAGIC +
  IN_HAND + lost-node detector) hammered by task_port (TASK) AND timer_micro_service (INTERRUPT,
  GetMsg+PutMsg on each INT6) coexisting with M3F/M7A/M7C (4/4 runs, zero corruption). RED (A/B under dedicated
  MAX CONTENTION — task_port high pri, no rate limit, 90 s window): ports in Forbid -> "M7D FAILED:
  shared-port list corrupted"; SAME contention, ports in Disable -> clean. The race is statistical
  (sub-µs RemHead/AddTail window, CUMULATIVE corruption on a doubly linked list): deterministic under
  max contention + long window, not triggered by the lightened coexistence demo.
- **M7e** (PER-LEVEL IPL fidelity): handlers no longer raise IPL7 in the prologue — they run at their **native**
  IPL (VBlank=3, PORTS=2, EXTER=6, set by the CPU when taking the autovector). Consequence: a higher-level
  source preempts the **body** of a lower handler (INT6 preempts the body of `vbl_handler`). The
  switch's critical section (`dispatch`: relocation then TaskReady Enqueue/RemHead) is masked by a **brief
  IPL7** (`move #imm,sr`), NOT by INTENA-off. **Empirical discovery (FS-UAE)**: masking with INTENA-off leaves
  a race — the INTENA write has a **propagation delay** (Amiga quirk), so an INT6 already asserted on the
  IPL lines overlaps the surgery window. The SR (IPL) write, on the other hand, is **internal to the CPU = instantaneous**.
  **Privilege argument** (why IPL here but INTENA elsewhere): the surgery runs in SUPERVISOR mode (reached
  via `intr_exit`/trap) → `move to SR` legal → IPL7 possible. `Signal`/`PutMsg`/`GetMsg`/`Wait`/`timer_reply` are
  callable from a USER-MODE task where `move to SR` is **privileged** (68000 manual) → they cannot raise
  the IPL → they keep INTENA-Disable. **Honesty (M7d consistency)**: the write-delay window therefore affects EVERY
  INTENA-masked section callable in user mode — Signal, the M7d ports, Wait, timer_reply — by necessity; it is
  tolerated by the re-check (Wait re-tests on wake-up) and empirically benign for the M7d ports even under max
  contention. ONLY the supervisor-side switch was promoted to IPL. The frame relocation (SSP→user stack) stays at the native
  IPL without a mask: INT6 nests BELOW `sp`, the outgoing frame `[sp,sp+66)` is intact. PROOF: serial
  "M7E IPL OK" gated on `VBL_PREEMPT_COUNT>0` (INT6 preempts the vbl body, `timer_micro_service` detector) AND
  `VBL_CLASH==0` (zero INT6/surgery overlap — `VBL_CLASH` is an OVERLAP proxy, a precondition of corruption,
  NOT a corruption detector). GREEN 3/3; RED1 (`M7E_SURGERY_INTENA=1`, surgery with INTENA-off) → `VBL_CLASH>0`
  "M7A FAILED" 3/3 (proves IPL7 load-bearing); RED2 (`M7E_PROLOGUE_IPL7=1`, IPL7 in the prologue) → `M7E IPL OK`
  absent 2/2 without crash (proves the native IPL load-bearing, not cosmetic); cooperative non-regression
  (`M7E_COOP=1`, `SCHED_ON=0`, yield-only) re-proven. The dispatcher idle (reached only if TaskReady is empty
  after a Wait) is not exercised by these demos (the round-robin/spin tasks keep TaskReady populated) — documented.
- **M7f** (VERTB AS A SERVER CHAIN): the dedicated VBlank handler `vbl_handler` is replaced by
  `int3_dispatch`, a generic dispatcher mirroring `int2_dispatch`/`int6_dispatch` -> `intr_dispatch_number`
  `(INTB_VERTB=5)` -> **server chain by priority**. Model now UNIFORM for the 3 autovectors
  in use: PORTS(int2)/VERTB(int3)/EXTER(int6). The **scheduling decision** (round-robin quantum) becomes
  `sched_server`, a pri 20 VERTB server that sets `EB_ATTNRESCHED` (under the same guards as the old
  `vbl_handler`: `SCHED_ON && !Forbid && !Disable && TaskReady` non-empty -> the round-robin RESPECTS Forbid);
  `intr_isr_defer` consumes it at IRQ exit (like an INT6 wake-up). Faithful: the real exec has a VBlank
  server that sets the AttnResched flag. `timer.device` registers its VBLANK service via `AddIntServer(VERTB,
  timer_vblank_int)` (pri 0) instead of the `VBL_SVC` hook (removed); `timer_vblank_service` returns Z set
  ("continue the chain"). **Key risk handled**: `intr_chain_walker` re-supplies `a6` BEFORE each server
  but does NOT restore it after the last one (the servers only preserve d2-d7/a2-a4) -> `intr_isr_defer`
  **reloads `a6=SysBase`** before reading `EB_ATTNRESCHED` (otherwise dispatch decisions on a clobbered a6). The
  Interrupt structs live in reserved low RAM (< `HEAP_LOWER`, outside the AllocMem pool; AddIntServer Enqueues them).
  PROOF: serial "M7F VERTB OK" gated on `VERTB_CHAIN_N` (counter of the TAIL server `vbl_tail`, pri -10)
  -> proves that the walker goes through the WHOLE chain (sched(20) + timer(0) before tail(-10), in priority order);
  the scheduler (M3F LIVE) AND the timer (M7A/M6A via `timer_vblank`) work THROUGH the chain. GREEN
  3/3 (0 FAILED); RED (`M7F_SCHED_STOPS_CHAIN=1`, sched returns Z clear) -> the walker STOPS the chain
  after sched -> `timer_vblank`/`vbl_tail` never called -> "M6A FAILED: timer VBLANK unit incorrect"
  2/2 (proof: the call-all Z-set semantics = the walk DOES dispatch the following servers in sequence).
  Non-regression of M3f + cooperative (`M7E_COOP=1`) + M7e ("M7E IPL OK") + M7a/M7c/M7d re-proven in the same
  boot. **Discovery (initial RED hypothesis invalidated empirically)**: removing the VBlank quantum ALONE
  (`sched_server`) does NOT stop preemption -> "M3F LIVE" is emitted anyway, because INT6 (MICROHZ ~140/s)
  co-drives the round-robin: ANY deferred dispatch (`intr_isr_defer`, d6=1) requeues the outgoing task and rotates the
  equal-priority tasks. The VBlank quantum is therefore redundant with a fast INT6 timer in this demo; it
  remains the right (faithful) place for the decision, but its effect cannot be isolated here. OUT OF SCOPE
  (M7g+): INT3 remains single-source VERTB (no COPER/BLIT INTREQR decoding).
- **M7g** (MULTI-SOURCE INTREQR DECODING): `int3_dispatch` no longer assumes VERTB alone — it reads
  `INTREQR & INTENAR` and dispatches+acks EACH pending level-3 source (COPER bit4 / VERTB bit5 /
  BLIT bit6) via `IntVects[n]`. VERTB -> M3a counter + chain (M7f); COPER/BLIT -> their vector. `int2`
  (PORTS) / `int6` (EXTER) remain single-source: their level has only ONE Paula source (correct optimisation,
  not a generic loop). The mask of pending sources is held in `d2`, preserved across the
  dispatches by the server convention (walker `movem d2/a2-a4`; `coper_test` only touches its counter);
  `a6` is reloaded after each dispatch (M7f lesson). **Correctness bonus**: on a SPURIOUS INT3 (ack
  propagation delay, see M7e) the 3 `btst`s fail -> no dispatch, vs M7f's unconditional VERTB
  dispatch. PROOF: a 2nd level-3 source (COPER) is TRIGGERED BY SOFTWARE (`INTREQ=SETCLR|COPER`
  from the VERTB server `vbl_tail`, rate-limited 1/4; no graphics required); `IntVects[COPER]` =
  `coper_test` (exclusive vector) increments `COPER_FIRED`. Serial "M7G MULTISRC OK" gated on
  `COPER_FIRED>=seuil` -> int3 serves EACH pending level-3 source (COPER on its own INT3, VERTB
  on its own), not only VERTB any more. **Exact scope**: SEQUENTIAL per-source is proven (vbl_tail sets
  COPER DURING the VERTB INT3 -> d2 is already sampled -> COPER served at the NEXT INT3); the
  co-pending case (VERTB+COPER on the SAME INT3) is NOT isolated. BLIT: path present but by inspection
  only (no BLIT source in the demo; identical to the proven COPER path). GREEN 3/3 (0 FAILED);
  RED (`M7G_MONO_SOURCE=1`) -> int3 decodes+acks COPER but does NOT dispatch it -> "M7G" absent,
  `COPER_FIRED` frozen, everything else identical WITHOUT a storm (proof: dispatch by decoded source is
  load-bearing). Note: a real single-source (ack VERTB only) WOULD LIVELOCK the machine (level-3 COPER
  pending-not-acked -> INT3 in a loop); hence the "dispatch-skip" RED, which cleanly isolates the variable.
  Non-regression of M3f + cooperative + M7a..M7f re-proven in the same boot.
- **M7h** (REAL QUANTUM): `sched_server` no longer sets `AttnResched` on EVERY tick — it counts
  `QUANTUM_ELAPSED` and only preempts after `M7H_QUANTUM` time-slice ticks (default 4, like
  exec's SysBase.Quantum). `dispatch_in` resets `QUANTUM_ELAPSED` on a REAL task change
  (incoming != outgoing; no reset on dispatch-to-self). Strict priority was ALREADY correct
  (RemHead picks the highest pri, Enqueue requeues by pri, Signal preempts on a higher-priority wake-up) ->
  no priority gap, M7h = quantum only. **Observability (direct consequence of M7f)**: in the NORMAL
  demo, INT6 (task_timer ~140/s) dispatches -> `dispatch_in` resets `QUANTUM_ELAPSED` before it
  reaches the quantum -> the quantum ALMOST NEVER fires (QUANTUM_EXPIRE_N≈0); it is a
  quasi no-op and the rotation stays driven by INT6 (non-regression M3F..M7G OK). The quantum is only
  OBSERVABLE in ISOLATION (`M7H_QUANTUM_DEMO=1`): `setup_demo_tasks` creates only task_s + task_q2
  (2 spinners pri 0, no higher-priority preempter nor yield; INT6 runs but Signals nobody ->
  does not rotate) -> the VBlank quantum becomes the ONLY rotator. PROOF: "M7H QUANTUM OK" gated on
  `QUANTUM_EXPIRE_N*2 < VBL_COUNT` (rate ≈ VBL/4 for QUANTUM=4 -> quantum > ~2 ticks) AND `WP_SPIN>0`
  (task_s ran = real rotation, not monopolised). GREEN-default 3/3 (non-reg, M7H absent);
  GREEN-isolation 2/2 ("M7H QUANTUM OK"); RED-isolation `M7H_QUANTUM=1` -> rotation every tick ->
  `QUANTUM_EXPIRE_N≈VBL_COUNT` -> discriminant fails -> "M7H" absent 2/2; cooperative OK. Honest
  framing: FAITHFUL quantum, observable only in isolation; quasi no-op by default = correct consequence of
  the architecture (INT6 co-drives), not a weakness.
- **M7i** (`timer_reply` -> `ReplyMsg`): the bespoke reply routine `timer_reply` (M7c) is REMOVED.
  It existed because at the time `PutMsg`/`ReplyMsg` called `Permit` -> a SYNCHRONOUS reschedule
  forbidden in the middle of an interrupt. M7d made these primitives interrupt-safe (Disable INTENA +
  `raw_enable`, WITHOUT the Permit/yield tail) -> the hack no longer has a reason to exist. The 2 services that
  replied (timer_vblank_service / timer_micro_service, interrupt path) now call
  `LVO_REPLYMSG` directly (AddTail + Signal + NT_REPLYMSG mark, atomic, no yield in IRQ).
  `timer_beginio` was NOT a caller (it forces min 1 tick -> deferred reply, and runs in task
  context). Register-safe: ReplyMsg clobbers d0/d1/a0/a1, preserves d2-d7/a2-a6 (the loop invariants
  d2/a2/a4, and d3/a5 for the micro path, survive). PROOF = EQUIVALENCE: set of markers
  IDENTICAL to the M7h default demo (M3F/M6A/M7A/M7C/M7D/M7E/M7F/M7G, 0 FAILED) on GREEN 3/3 +
  cooperative — the swap is observably inert (refactor, not a new mechanism; no RED apart from a
  planted bug). The inverted justification ("we do NOT use ReplyMsg because Permit yields") was corrected
  everywhere (timer.s header, service comments, this document).
- **M7j** (`RemTask` — LIFE CYCLE): `RemTask(task a1)` removes a task and frees its stack
  (`TC_SPLOWER..TC_SPUPPER`) + its TCB (`TC_SIZE`). Two paths. **SELF** (`a1`=0 or ThisTask — the case
  "a task ends": its body RTSes -> `task_exit` -> `RemTask(self)`): `trap #2` -> supervisor.
  Implementation of the advisor's option (D): once in supervisor we run on the **shared SSP**, so
  the outgoing task's user stack is NO LONGER used and can be freed; we `FreeMem` the stack then the TCB, then we
  switch to the next task exactly like launching the 1st task (`RemHead` + `dispatch_in`,
  DOES NOT RETURN). **Traps handled**: (1) `FreeMem` uses Forbid/Permit and Permit YIELDS -> we wrap
  the teardown in an OUTER `Forbid` (the inner Permit sees TDNEST>=0 -> no yield) + IPL7 (masks
  IRQs); (2) we clear `EB_THISTASK` BEFORE `FreeMem(TCB)` because `dispatch_in` reads it (cmp QUANTUM_ELAPSED M7h)
  -> no read of a freed TCB; (3) QUANTUM_ELAPSED is global -> `dispatch_in` resets it on the switch
  (M7h note closed). **NON-SELF** (`a1` != ThisTask, ready/waiting task): no trap nor switch — Forbid
  (anti-yield) + Disable (vs IRQ) + `Remove` + `FreeMem` stack+TCB + raw_enable + Permit, return to the caller.
  PROOF: "M7J REMTASK OK" — task_rm (pri 0) runs `RM_THRESH` times then RTSes -> `task_exit` ->
  `RemTask(self)`; task_timer (survivor) captures `AvailMem` BEFORE creating task_rm, then confirms
  that after the self-removal `AvailMem` has risen by at least `M7J_RECOVER` (stack 2048 + TCB) = successful free.
  GREEN 2/2 + default non-regression (M3F..M7G, 0 FAILED, M7J absent because task_rm is outside the default config) 3/3
  + cooperative; RED (`M7J_NOFREE=1`, FreeMem skipped) -> `AvailMem` does not rise -> "M7J" absent 2/2,
  WITHOUT crash (task_rm properly removed from scheduling, only the memory leaks). **Limits**: non-self by
  inspection (the demo exercises self); `tc_MemEntry` not freed (no demo task allocates one) -> out of scope.
  **Fixed in step 10** (see "Faithful memory releases"): RemTask now frees only `tc_MemEntry`, like the
  real exec; stack and structure are described in it by `task_alloc`.
- **M7l** (REAL µs MICROHZ CALIBRATION): before M7l, `timer_beginio` converted `TV_MICRO` into ticks via
  `/20000` (the 50 Hz VBLANK factor) for BOTH units -> on the MICROHZ unit (CIA-B, latch `$00FF` = 255
  E-clock ticks) `TV_MICRO` was NOT worth real µs (a "400000 µs" request lasted ~7 ms, not 400 ms).
  M7l SEPARATES the conversion per unit: MICROHZ counts in CIA-B interrupts via `US_PER_INT`=359 /
  `INTS_PER_SEC`=2782 (PAL E-clock 709379 Hz = CPU/10, latch 255 -> ~359.5 µs/int); VBLANK keeps `/20000`.
  `TV_MICRO` therefore means real µs, at the resolution of one interrupt (~360 µs). (Replaced in step 10:
  one-shot armed on the deadline, stays in E ticks — see "STEP 10 — PERFORMANCE".) PROOF = CROSS-CLOCK
  (NOT tautological: CPU E-clock vs display raster, different hardware): a 0.5 s MICROHZ request must
  elapse in ~25 VBLANK ticks (independent 50 Hz clock). GREEN "M7L MICROHZ CALIB OK" = elapsed ∈ band
  [22,28] (3/3). RED (`M7L_OLD_CONV=1`, VBLANK conversion restored on MICROHZ): the 0.5 s request expires in
  ~25 interrupts ≈ 9 ms < 1 VBLANK tick -> elapsed ~0-1 -> M7L ABSENT, M3F..M7G green (2/2, surgical RED:
  the request value of the `task_timer` loop is gated in parallel via `TT_MICRO_REQ` to keep the PERIOD
  ~7 ms under both conversions). COOP: non-regression of all earlier markers (M3F/M6A/M7A/M7E/M7F/
  M7G, 0 FAILED); M7L is a proof of the DEFAULT build (just as M7C/M7D depend on the spinners, M7H on
  isolation): in cooperative mode the wake-up latency (task_timer pri 10 does not preempt task_h pri 10 — Signal at
  equal pri does not set AttnResched -> waits for task_h's yield) inflates the measured VBLANK window beyond the
  tight band -> M7L not emitted. This is a MEASUREMENT artefact, not a calibration error — PROVEN BY CONSTRUCTION:
  the countdown is 1392 CIA-B interrupts on the hardware timer (latch `$00FF`, not gated, identical in EVERY
  build) so completion is fixed at ~0.5 s ≈ 25 ticks whatever `SCHED_ON` is; hence `elapsed = 25 + head(<1) +
  wake-up-latency`, and only the wake-up latency differs between preemptive and cooperative (immaterial magnitude, deductive
  mechanism; also confirmed empirically: band widened to [22,250] -> M7L reappears in coop). **Limits**: sub-interrupt
  resolution (< 360 µs, live read of the E latch) + ECLOCK unit deferred; the `secs` path of the conversion
  is not exercised by the demos (both requests have secs=0) -> correct by construction, not proven empirically.
- **M4 graphics DONE** (Copper → bitplane → resident graphics.library → display generated by the ABI). **M5 intuition: resident skeleton + `ViewAddress` DONE** (`src/intuition/`); the "insert Workbench disk" screen is postponed to **M6** (its real trigger = no bootable volume; the public docs confirm it is NOT an intuition function — refuse the synthetic screen, see the M7k-postponed logic).
- **exec `OpenLibrary` DONE** (`library.s`: `OpenLibrary`/`CloseLibrary`/`OldOpenLibrary`; serial marker M5O: success version 34 + OpenCnt+1, version gate 99→0, non-existent lib→0, CloseLibrary→OpenCnt-1; RED `OPENLIB_NO_VERCHECK`). The M4c1/M5 proofs (FindName+Open by hand) can now be refactored to go through `OpenLibrary` (follow-up).
- **dos.library resident skeleton DONE** (`src/dos/`: `DosBase`+`RootNode`+`DosInfo` linked by **BPTR**, structures separately AllocMem'd/long-aligned; `DateStamp`-192 → (0,0,0) clock not set + returns the pointer; serial marker **M6D**: AUTOINIT→LibList + BPTR round-trip `rn_Info<<2==&DosInfo` (compute-then-compare, without dereferencing) + DateStamp; RED `M6D_BAD_BPTR` isolates the BPTR encoding; checksum `0x929C804F`). 1st M6 increment.
- **Boot screen DONE** (`src/graphics/`: kitten image "KickSlopStart" 352×272×5 = 32 colours in overscan, displayed at handoff through the graphics.library ABI; `MakeVPort` made generic N planes/M colours; serial marker **M6S** (liveness) + VISUAL discriminant (unique colours: GREEN ~18-19k vs RED one-plane ~36); RED `BOOTSCR_ONE_PLANE` isolates multi-bitplane rendering; self-checking `mk_bootscreen.py` pipeline). ⚠️ Displayed **unconditionally** at handoff for now: the real "no bootable volume" trigger remains for the strap increment.
- **Strap (romboot) — routing DONE (M6r)** then **reading+validation+execution of the bootblock DONE (C/M6y)** (`src/exec/strap.s`). M6r: `strap_boot` routes the insert-disk display through its decision. **C**: `strap_boot` now REALLY reads sectors 0+1 of DF0: (`CMD_READ` offset 0 len 1024, via `BeginIO`-30, M6w pattern), validates the "DOS" magic + **additive checksum** (end-around-carry sum of the 256 longs == `$FFFFFFFF` — ADDITIVE, not XOR like the MFM checksums), then **jumps to the boot code at +12** (A6=SysBase, A1=IORequest; dos handoff A0 IGNORED, no dos in C). Bootable → returns "booted" (**M6Y**, no insert-disk); invalid checksum (formatted ADF without install = checksum 0) or no disk → returns 0 → insert-disk (**M6R**) = the REAL 1.3 trigger. RED `STRAP_FAKE_BOOTDEV` (routes without reading), `STRAP_NO_EXEC` (validates without jumping → isolates execution), `STRAP_BAD_CSUM` (rejects a good block → isolates validation). Proof: the **CBOOT** marker is emitted by the bootblock ITSELF → proves the jump. Regenerable custom bootable test ADF (`tests/mk_boot_adf.sh` + `tests/bootblock_c.s` + `tests/patch_bootblock.py`, round-trip).
- **trackdisk.device — skeleton (B1) DONE** (`src/exec/trackdisk.s`: 2nd device, AUTOINIT pri 20 → DeviceList, `Open` validates units DF0-3; serial marker **M6T**; RED `TD_NO_UNITCHECK` isolates unit validation). Foundation of disk reading.
- **trackdisk raw track read (B2) DONE** (`td_read_track0`: the ROM really READS an MFM track from DF0 via Paula disk DMA — 22 `$4489` sync words found on a test ADF; serial marker **M6U** + sync count; RED `TD_NO_DMA` isolates the arming of the DMA; harness `tests/boot_test.sh` extended with an optional floppy in DF0). 1st time the ROM accesses the disk hardware.
- **trackdisk MFM decoding (B3) DONE** (`td_decode_track`: 11 sectors × 512 bytes decoded+verified, sector 0 = bootblock "DOS\0"; serial marker **M6V**; RED `MFM_BAD_DECODE`).
- **trackdisk CMD_READ (B4) DONE** (`BeginIO` handles `CMD_READ`; serial marker **M6W**; RED `TD_READ_NOCMD`).
- **MULTI-TRACK trackdisk CMD_READ (M6z, D prerequisite) DONE**: `BeginIO` converts the byte offset into (track, sector) and loops over the touched tracks (crosses track boundaries); guards `IOERR_BADLENGTH`/`TD_DISKBYTES`. Serial proof **M6Z** = root block @block 880 (track 80, +0==T_SHORT, +508==ST_ROOT) + spanning read of blocks 10+11 (markers "SPAN0010"/"SPAN0011" straddling the track 0/1 boundary). RED `TD_NOSEEK` (always reads track 0, without crash) → M6Z absent (isolates the offset→track mapping).
- **trackdisk seek + side-select (B2b) DONE** (`td_read_track(n°)`: seek to an arbitrary track + side; proven by reading track 2 → decoded sectors carry track==2; serial marker **M6X** + TRACK= diagnostic; RED `SEEK_NOSTEP`). **trackdisk.device is now complete**: it reads any logical sector of any track of DF0.
- **trackdisk — CYLINDER-TRACKING**: `td_read_track` tracks the current cylinder (`TD_CURCYL`/`TD_CYLVALID`) and steps the **delta** to the target (recalibration to 0 only if the position is unknown) — CLEANLY fixes the "read after a seek read the wrong track" bug (the delta brings the head back to the right cylinder) AND removes the 85-step recalibration on every read (fast reads, required under the scheduler). RED `TD_NO_CYLTRACK` (systematic recalibration → D3B absent at WAIT=90). "Absent/empty drive" detection via the **DSKRDY timeout** (return before the seek). Multi-track `CMD_READ` offset→track wiring delivered (M6z). Debt: no invalidation on disk change (real eject/swap → periodic recalibration, M7).
- **trackdisk — SEEK/INTERRUPT RACE FIX (CIA-B)**: the seek's step pulses write `CIAB_PRB`; the MICROHZ source (CIA-B timer A, INT6) shares the SAME chip. An INT6 IRQ falling between the PRB writes of a step corrupts the head positioning → the next read **falls over** (hang). Invisible as long as the boot only reads low blocks (small seeks): exposed by a **large seek to a high block** on a real full disk (e.g. opening `flt-intro` on a Lemmings floppy). FIX = **`Disable`/`Enable` critical section around the SEEK only** (`td_read_track`, `.rd_seek`→`.rd_dma`); the downstream DMA polls `INTREQR` → no IRQ required → minimal IRQ latency (vs masking the whole read). **Cause proven by bisection, not assumed**: a PURE inter-step delay does NOT fix it (so not a settle defect), masking IRQs DOES (3/3). Non-regression: complete GREEN (D1/D3B/OFS STREAM/M7A/M7L/FORBID ATOMIC/E3/F1BOOTOK, 0 FAILED) unchanged.
- **"It boots!" (C/M6y) DONE**: see the Strap line above — the strap reads+validates+executes the bootblock of a bootable ADF, proven by the **CBOOT** marker emitted by the bootblock. First EXTERNAL (disk) code executed by the ROM.
- **LEMMINGS FAIRLIGHT CRACKTRO DISPLAYED (real game milestone)**: the ROM boots the *Holiday Lemmings 1993 [h FLT]* floppy, its `s/startup-sequence` launches `flt-intro` (FLT cracktro), which **IS DISPLAYED ON SCREEN** (FAIRLIGHT logo + BBS list, proven by capture). It required three pieces: (1) the trackdisk seek race fix above (flt-intro, block 1597, finally loaded); (2) **graphics.library** — jump table extended to vectors 38-77 + `WaitBlit`(-228)/`OwnBlitter`(-456)/`DisownBlitter`(-462) (stubs: the intro does not use the blitter) + `LoadView`(-222) handles the **NULL view** (turns off bitplane+copper DMA instead of dereferencing address 0); (3) **exec `Supervisor`(-30)** (`library.s` + `trap3_handler` in `interrupts.s`): `trap #3` → supervisor → `jmp (a5)`; the routine (the intro) ends with `RTE`, which unstacks the trap frame → return to the caller. The intro drives copper/bitplanes/DMACON/BEAMCON0 **100% directly** in supervisor mode (no rendering through graphics.library; ActiView/copinit/LOFlist only SAVED-for-restoring, never dereferenced — GfxBase layout intact). Clean-room analysis of the bootblock + the unpacked cracktro (r2, GAME disk = outside the Kickstart firewall). Complete GREEN non-regression unchanged. **Honest scope**: it is the CRACKTRO that runs; the game `HolidayLemmings` (145 KB > 16 KB shell buffer + LoadSeg cap) remains a separate "large loader" milestone.
- **LOADING SCREEN (large file) — GATED DEMO DONE** (`src/graphics/loadscreen.s`, flag `LOADSCREEN_DEMO`): `loadscreen_demo` sets up a **View** on console.device's text bitplane (`FindName` console → repoints `CONB_BITMAP` to a 352×272 plane = fixed geometry of `gfx_MakeVPort`, stride 44; `MakeVPort`/`MrgCop`/`LoadView` through the graphics.library ABI) then writes "Chargement <name>..." (console `CMD_WRITE`, 8×8 glyphs) + a **progress bar** (one '#' per 4 KB chunk) during a **real STREAMING** read of the file (`ofs_stream_read`, data block by data block, without a whole-file buffer), then "OK". **FS-UAE boot** proof: screen capture — readable white text on a midnight-blue background (`loadscreen_final.png`). **Clean gating**: `loadscreen.o` is linked ONLY under `make VASMDEF=-DLOADSCREEN_DEMO=1 kick` (`findstring` condition in the Makefile + `xref`/trigger guarded by `ifne LOADSCREEN_DEMO` in boot.s) → the default ROM stays **byte-identical** to the commit (md5 `d4c1784c…` unchanged, zero dead code). **Goes beyond** the "visual rendering deferred" limitation noted in #3a: the console text IS displayed in a capturable FS-UAE window as soon as the View is set up with the right geometry (352×272, stride 44) — the old `gfx_text_display` did not set up the View correctly. **Honest scope**: standalone DEMO (name `bigseg` hard-coded, sets up its own display, holds the screen, DOES NOT RETURN) — NOT yet wired into `dos_loadseg`, so it does not trigger automatically "when it loads an image". *Live* wiring = follow-up (the loadscreen will have to RETURN, free its allocations, and reuse the current display instead of setting up a dedicated one).
- **TRACKDISK ON TIMING-EXACT (WinUAE / real A500) — FAST FIX** (commit 4590cb1): the ADKCON read mode was `$8400` (FAST=0 = 4 µs/bit) → Paula sampled at the wrong rate, garbage bitstream, `$4489` never matched, no read on WinUAE (FS-UAE tolerated it). Now `$9500` (= official KS1.3 read mode `$9100` SETCLR|MFMPREC|FAST + WORDSYNC). Also: no more hard failure on `/RDY` timeout (the official one never reads `/RDY`), `/STEP` pulse widened. Proven: Lemmings [h FLT] boots on timing-exact WinUAE, cracktro displayed, game loading started (blocks further on, ~sector 46 = next work item). Clean-room reference: `docs/analysis/trackdisk-official-timing.md`. The loadscreen **turns off bitplane+copper DMA during each `ofs_stream_read`**: on WinUAE, reading the disk with our View set up returned an empty DMA buffer; with the cut → `######`/`OK` proven on WinUAE and FS-UAE.
- **THE HOLIDAY LEMMINGS GAME STARTS (real game milestone)**: on the *Holiday Lemmings 1993 [h FLT]* floppy (A500 512 KB chip + 512 KB slow), the startup-sequence chains `flt-intro` (cracktro) → **left click** → `HolidayLemmings` (145 KB), which loads and **displays its menu** (PLAY/QUIT/NEW LEVEL..., scroller active), proven by an FS-UAE capture (keyboard/mouse harness). Four pieces: (1) **slow RAM** (`add_slow_memory`, `memory.s`): probes `$C00000` in 512 KB blocks (probes at `$1FE`/`$3FE` = NO-OP register if custom mirror, two crossed patterns, aliases rejected), added **AT THE HEAD** of the MemList as `MEMF_FAST|MEMF_PUBLIC` → allocations without `MEMF_CHIP` go there first, chip stays for the program; serial marker `MEM SLOW KB=`. (2) **shell**: command buffer of the file's **real size** (`Lock`+`Examine` → `FIB_SIZE`, no more fixed 16 KB buffer), `Read` loop until EOF, buffer freed **before** running. (3) **LoadSeg** honours the hunks' **memory flags** (bit 30 → `MEMF_CHIP`, bit 31 → `MEMF_FAST`, `11` = V37 extended attributes → clean failure) and masks the flags **copied into the hunk id** of the body (`$400003EB` = chip BSS — this was the cause of the "?" at launch); guards `hidx`/`ref < hunkcount`. (4) **trackdisk track cache**: the sectorbuf becomes persistent (`TD_CACHEBUF`) and keeps the last decoded track (`TD_CACHETRK`), validated only if the 11 sectors are decoded AND carry the requested track no., invalidated by `/CHNG` (CIA-A PRA bit 2, read by selecting DF0 with motor OFF) — each 512-byte OFS block re-read a whole track (spin-up+seek+DMA), ~300 track reads for the executable. GREEN non-regression with and without slow RAM. **Launching a level confirmed by the user** (2026-10-18, manual test; no automated proof in the harness). **Honest scope**: without slow RAM the game does not fit in memory (as on a real 512 KB A500).
- **WORKBENCH 1.3.3 — STEP 1: DOS NAMES, ASSIGNS, CLI, TRAPS (SetPatch runs)**: (1) **name resolution** (`dos_resolve`, `dos_lib.s`): "xxx:rest" → DosList node (case-insensitive); assign (DLT_DIRECTORY) → its lock + its handler, "rest" is passed on; device/volume → handler, lock 0, full name; ":rest" → root of the current volume; without ':' → relative to `pr_CurrentDir` (lock 0 → `pr_FileSystemTask`, otherwise DF0:). Unknown prefix → `ERROR_DEVICE_NOT_MOUNTED`. Open/Lock finally pass the **parent lock** (ARG2 of FINDINPUT, ARG1 of LOCATE_OBJECT); BSTR names up to 255. (2) **OFS**: `ofs_name_to_block`/`ofs_stream_open` start from the lock's directory ("xxx:" → root, empty path → the directory itself, empty component "/" → parent via long[125], trailing '/' neutral). (3) **DosList**: DeviceNode named `DF0`; when the initial CLI starts, `dos_boot_assigns` creates the **volume** node (name read by Examine of the root), the assigns **SYS: C: S: L: DEVS: LIBS: FONTS:** (if the directory exists) and `pr_CurrentDir` = root. (4) **Initial CLI**: `pr_CIS`/`pr_COS` = console FileHandle, **`pr_CLI` = CommandLineInterface** (without it, C startup code believes it was launched by the Workbench and waits for the WBStartup message → hang), `cli_CommandName`/`cli_Module`/`cli_ReturnCode` kept up to date; commands looked up as is then in **C:**; CLI calling convention (a0 = arguments terminated by '\n', d0 = length, 4(sp) = stack size, **`pr_ReturnAddr`** pointing to this long: `exit()` finds the entry stack there); redirections `>`/`<` and `;` comments removed from the arguments; CLI stack 8 KB. (5) **CPU exceptions** (`interrupts.s`): vectors 2-11 and TRAP #4-15 → trap no. pushed → `tc_TrapCode` (0 → `ExecBase.TaskTrapCode`); default handler = "SOFTWARE FAILURE trap= pc= addr= code= task=" on serial then task put on hold (before: jump to some arbitrary address, machine frozen). **Shape imposed by SetPatch**: vector n → `bsr.s` of a table (2 bytes/vector), common routine = `subi.l` 6 bytes (→ 2n) then `lsr.w 2(sp)` (`$E2EF`); SetPatch checks this word (otherwise deliberate crash) and hooks its FPU stubs there. (6) **exec `RawDoFmt` (-522)** (`rawdofmt.s`): %[-][0][width][.limit][l]d/u/x/s/b/c, a2/a3 returned; self-test "RAWDOFMT OK" (RED verified). Proof: on the *Workbench 1.3.3* disk, `c:SetPatch` (found via C:) runs in full, displays its messages and returns; the startup-sequence then stops at `AddBuffers` (a **BCPL** command → step 2). **Honest scope**: `SetFunction` not implemented → the fixes announced by SetPatch are not really installed; no layers.library; no real redirection nor NIL: yet.
- **WORKBENCH 1.3.3 — STEP 2: BCPL RUNTIME (`src/dos/bcpl.s`)**: BCPL call/return (A5 = `bcpl_call`, multiply at +$10, divide at +$12; A6 = `bcpl_ret`), global vector of the CLI (804 bytes, slots −50..+150, GV[0] = 150, undefined slots = stubs "BCPL GLOBAL xxxx NON IMPL" on serial) in `pr_GlobVec`, and **runtime segment in BCPL format** (`(global, offset)` table + max at the end of the hunk) published in the **segarray** `pr_SegList` = [1, runtime]: the startup stub of the c: commands (hunk 0, identical in all of them) creates a PRIVATE GV there through findsegarray/getvec/globin and installs the runtime into it, then its own seglist. ~60 globals: stop, result2, taskid, level/longjump, getmem, globin, getvec/freevec, parentdir, testflags, rootstruct, delay, sendpkt (the argument frame IS the DosPacket), currentdir, rdch/unrdch/wrch, findinput/findoutput, select/end*, input/output, writet/newline/writed/writen/writehex/writeoct/writes/**writef**, capitalch/compch/compstring, **rdargs/rditem/findarg**, load/unloadseg, makedevnode/finddevinfo, callexec/calllib, findsegarray, deleteobj/createdir (failure: read-only FS), endstream, deviceproc, fault (fallback "Error code %N"), splitname, locateobj/freeobj/lock, getlong/putlong, copydir, errorreq (FALSE), copystring, findcli, copyvec. The CLI launches each command as **runcommand** (spec §4.3): dedicated stack of `cli_DefaultStack` longs (1000), [old SP][size] at the top, `pr_ReturnAddr` → size, arguments injected into the input FileHandle (`fh_Buf`/`fh_Pos`/`fh_End`, restored on return), A1/A2/A3/A4/A5/A6 set. An undefined slot of a command GV is worth `$474C0001+2n`: the address fault directly gives n = (addr − $474C0001)/2. Handler: ACTION_MORE_CACHE (accepted), ACTION_PARENT, ACTION_COPY_DIR. dos: jump table completed up to −222 (Delay, WaitForChar, ParentDir, IsInteractive, Execute — the call beyond DateStamp fell below the table: SetClock's fault). exec AddTask no longer overwrites `ln_Type` (processes stay NT_PROCESS). SOFTWARE FAILURE also displays `cmd=`, `a6=`, `(usp)=`. Spec: `docs/analysis/bcpl-runtime-v34.md` (clean-room reviewed, sections 1-13). **createproc (33) + background CLI (Run)**: `bcpl_proc_entry` (spec §2.4: stack filled with `$ABABABAB`, base frame, GV[12], globin of each segment of the segarray, wait for the startup packet, `start(pkt)` with `pr_ReturnAddr` set for `stop`, RemTask on return); the GV is **shared** with the parent CLI (as per the spec); `rn_TaskArray` (20 slots) allocated by dos, `pr_TaskNum`; qpkt/returnpkt/taskwait, runcommand (121) as a global. Fixes revealed by Run: **getlong/putlong(i, base[, v])** = long at `base + 4*i` (spec §8.1 said "offset in bytes", contradicted by Run); **FileHandles are getvec blocks** (size at −4) because BCPL commands build and close them (Run's in-memory FileHandle) — Open allocates with getvec, Close frees through the header; the CLI **reinstalls its streams** around each command (before: selectinput(cli_StandardInput), after: selectoutput(cli_StandardOutput)/selectinput(cli_CurrentInput), spec §4.2.3/§4.4); **Delay blocks on timer.device** (VBLANK unit, port and request on the stack) instead of a busy wait that starved the background CLI during `wait`; the handler fills the **FIB like a packet handler**: name and comment as **BSTR**, `fib_Protection`, `fib_EntryType`, `fib_NumBlocks`, `fib_Date` (Shell-Seg reads the protection of a file found through the search path); the Examine/ExNext LVOs convert BSTR → C string (like AROS's `fixfib`). Proof (WB 1.3.3, FS-UAE): SetPatch, **AddBuffers**, **cd c:** (BCPL), echo, FastMemFirst, BindDrivers, SetClock, FF, **resident** ×2, **mount newcon:**, **failat**, then **run execute s:StartupII** creates "Background CLI" (`[CLI 2]`), which runs **Execute** and the six **resident** commands of StartupII (return code 0 for each, temporary trace of the command names); it stops at `makedir ram:t` (code 10: no RAM: device) and the script is abandoned (failat); the main CLI waits in `wait 5 mins`. **Honest scope**: no starting of BCPL handlers (global 112: RAM: = `L:Ram-Handler`, NEWCON:), read-only FS, unbuffered writef, C:FAULT not launched.
- **WORKBENCH 1.3.3 — STEP 3: DEVICE HANDLERS (RAM:, PIPE:) AND EXEC I/O**: (1) **`bcpl_starthandler`** (`bcpl.s`, global 112, spec `docs/analysis/handlers-v34.md` + `bcpl-runtime-v34.md` §13.3) called by `dos_resolve` for any DLT_DEVICE node without a task (hence by Open/Lock/CreateDir/... and by `deviceproc`): loads `dn_Handler` into `dn_SegList` (only once); `dn_GlobalVec = -1` → **C handler** (process launched on the code of the first hunk, stack in bytes); otherwise **BCPL handler**: segarray `[3, runtime, 0, seglist]`, shared GV (`dn_GlobalVec`) or **`makeglobvec`** (global 13: max of the segments' "max" values, floor 15, slots −50..max), `createproc` (stack in longs); synchronous startup packet (Arg1 = BSTR of the full name, Arg2 = `dn_Startup`, Arg3 = node, Res2 = GV); success if Res1 ≠ 0, Result2 := `dn_Lock`; `dn_Task` is never written by dos (the handler does it if it wants to be shared). The core of createproc is factored out (`rt_createproc`). (2) **RAM node** created when the initial CLI starts (`ba_ramnode`: `L:RAM-HANDLER`, stack 300 longs, pri 0, new GV); Ram-Handler writes `dn_Task` itself and creates the "RAM DISK" volume. (3) **exec** (`src/exec/io.s`): **OpenDevice / CloseDevice / DoIO / SendIO / CheckIO / WaitIO / AbortIO** (AutoDocs; OpenDevice only searches the DeviceList) and **CopyMem / CopyMemQuick** (Ram-Handler copies all its data with CopyMem, global 156, which it defines itself). timer.device now handles **TR_GETSYSTIME / TR_SETSYSTIME** (system time = reference + VBL_COUNT/50) and rejects the other commands (IOERR_NOCMD), replying if the request is not quick; TR_ADDREQUEST clears IOF_QUICK (otherwise DoIO returned immediately — SetClock blocked). (4) **dos**: LVOs **DeleteFile (−72), Rename (−78), CreateDir (−120)** through packets (factored `dos_namepkt` with Lock; `dos_sendpkt` passes ARG4); real globals **createdir/deleteobj/rename**, **setio (6), doio (21), sendio (22), opendevice (31), closedevice (32), setflags (36: `break`), datstamp (86)**. **errorreq (114) returns TRUE** = abort (c:Dir loops on ExNext as long as errorreq returns 0: the spec's "TRUE = retry" was inverted). (5) **LoadSeg** ignores HUNK_NAME / HUNK_DEBUG / HUNK_SYMBOL (MountMF starts with a HUNK_NAME). (6) **shell**: empty line or comment alone after spaces (rest of line ";...") ignored instead of displaying "?". Proofs (FS-UAE): the **complete Workbench 1.3.3 startup-sequence** runs — StartupII in the background CLI (makedir/assign on RAM:, mount speak:/aux:/pipe:, resident remove, **`break 1 C`** interrupts the main CLI's `wait`: `**BREAK`), then path, **SYS:MountMF** (CrossDOS), LoadWB (no effect: no workbench/layers), endcli ("CLI process 1 ending"), without any "NON IMPL" or fault; test disk (copy of the ADF, startup-sequence replaced): `copy` to RAM:, `type`, `makedir`, `dir`, `rename`, `list`, `delete` correct on RAM:; **PIPE:** (C handler): `run copy s:StartupII to pipe:x` + `type pipe:x` transfer the whole file up to EOF. **Honest scope**: NEWCON: (global 50 openwindow + console.device on a window) and AUX:/SER:/PAR:/PRT: (serial.device/parallel.device to be loaded from DEVS:, no device loading from disk) cannot be started; ROM CON/RAW/SER/PAR/PRT nodes not created; LoadWB has no effect.
- **WORKBENCH 1.3.3 — STEP 4: DEVS: DEVICES, AUX:, NEWCON:**: (1) **loading from disk** (`src/exec/ramlib.s`, ramlib's role): OpenLibrary / OpenDevice of a name absent from the lists, called by a process, do `LoadSeg("LIBS:nom" / "DEVS:nom")`, look for the ROMTag (RT_MATCHTAG = itself) in the segments and call `InitResident(romtag, seglist)`; failure -> UnLoadSeg. (2) **exec**: AddLibrary/RemLibrary/AddDevice/RemDevice (a module that does its own MakeLibrary registers through AddDevice), **complete InitStruct** (prior clearing, forms dd = 00/01/10/11, counter, re-alignment: only INITBYTE/WORD/LONG were handled), **level 1/4/5 autovectors** (TBE/DSKBLK/SOFTINT, AUD0-3, RBF/DSKSYNC: enabled and pending sources -> SetIntVector's exclusive handler, which acknowledges INTREQ itself; without a handler -> acknowledged; trackdisk and the serial console poll with INTENA off). (3) **misc.resource** (`src/exec/misc.s`, pri 70): AllocMiscResource / FreeMiscResource (serial/parallel units) — without it serial.device's init fails. RESMAX raised to 24. (4) **intuition**: GetPrefs / GetDefPrefs (default V34 Preferences, 232 bytes: 9600 baud, 8N1 — serial.device reads its rate there when opened), **minimal** OpenWindow / CloseWindow (Window structure filled from the NewWindow, without layer, rastport or rendering). (5) **console.device**: a request coming from OpenDevice (io_Unit = the window) follows standard exec semantics (ReplyMsg reply outside IOF_QUICK, CMD_READ queued until a character arrives, AbortIO); the historical synchronous callers (null io_Unit: conhandler, probes) keep the immediate behaviour; ESC/CSI sequences ignored when rendering. (6) **expansion.library**: vector table completed to the V34 set (up to AddDosNode −150: real Set/GetCurrentBinding, Obtain/ReleaseConfigBinding with no effect, the rest neutral) — it stopped at −84 and BindDrivers, now able to load icon.library, called ObtainConfigBinding (−120) below the jump table. **dos Lock**: the `dos_namepkt` factoring overwrote the caller's d3 (mode copied before saving) — BindDrivers then re-read IconBase at $FFFFFFFE; ARG3 now goes through d2. (7) **BCPL**: global 50 **openwindow** (the spec's NewWindow: Flags $21007, Min 120x50, WBENCHSCREEN) with **GV[92] = IntuitionBase** set in the CLI's GV. SOFTWARE FAILURE also displays the USP value. Proofs (FS-UAE, copies of the WB 1.3.3 ADF): **AUX:** — `copy s:StartupII to aux:`: Aux-Handler (BCPL, shared GV) -> serial.device **loaded from DEVS:** -> the text comes out on the serial line; **NEWCON:** — `copy s:StartupII to newcon:0/0/640/100/Test`: Newcon-Handler opens its window (global 50), console.device on the window, CMD_WRITEs completed, pending CMD_READ aborted on closing, CloseWindow, the script continues. Complete WB 1.3.3 boot: **BindDrivers runs in full** (icon.library loaded from LIBS:, examination of SYS:Expansion), **LoadWB** answers "Cannot find resident tag for workbench.task" (resident module absent: next step). **Honest scope**: no display of windows (no layers.library nor Workbench screen: console.device's text goes into its single bitplane, shared by all windows, not read back by the harness), NEWCON keyboard reading not proven, ROM CON/RAW/SER/PAR/PRT nodes not created (CON: would require the ROM's BCPL console-handler), SetIntVector does not return the old vector, ramlib reserved for processes.
- **WORKBENCH 1.3.3 — STEP 5: workbench.task RESIDENT (LoadWB)**: (1) **`src/dos/workbench.s`** (spec `docs/analysis/workbench-task-v34.md`): ROMTag NT_TASK **without a class flag** (present in ResModules for FindResident, never initialised at boot); LoadWB does CreateProc with the seglist BPTR(ROMTag+42) -> fake segment at ROMTag+40 (link 0) and entry point at ROMTag+44 (ROMTag aligned on 4). The process renames itself "Workbench" (LoadWB finds it again through FindTask), moves to priority 1, gives itself a fake CLI (pr_CLI; the path received, message +$14, goes into cli_CommandDir), **replies immediately** to LoadWB's message (without a reply LoadWB stays blocked in WaitPort), then serves a public "Workbench" port by replying to every message, and lives indefinitely like the real one. (2) **exec InitCode filters by class**: only initialises the residents whose RT_FLAGS have a bit in common with startClass; all our ROMTags now carry **RTF_COLDSTART** and the boot calls InitCode(RTF_COLDSTART) (before: startClass ignored, d0 overwritten). (3) **exec AddPort initialises the message list** (NEWLIST, AutoDoc). Proof (FS-UAE, WB 1.3.3): "Cannot find resident tag for workbench.task" disappears; LoadWB launches the Workbench, receives its reply and returns; the startup-sequence ends with endcli. **Honest scope**: **minimal** Workbench, **without a desktop** — no Workbench screen, backdrop window, disk icons, menus or tool launching (the real one opens dos/graphics/layers/intuition/mathffp/icon and restarts the machine if one of them is missing: layers.library, mathffp.library, the real Intuition screens and windows, InitGels, OpenFont/Text are still to be done).
- **WORKBENCH 1.3.3 — STEP 7: AMIGASLOPDOS AT STARTUP AND DESKTOP**: (1) **AmigaSlopDOS window** — the initial CLI opens its console under the name `CON:0/0/640/200/AmigaSlopDOS` (Arg3 of FINDINPUT); the console handler (`conhandler.s`) then opens a window on the Workbench screen (`con_openwin`: geometry and title read from the name, flags of a CON: window) and renders output and echo there through console.device (the serial mirror stays for the harness); named openings are counted, the last END closes the window — the CLI sends it when EndCLI has moved it to the background (`cli_Background`); after that the fallback serial shell no longer reads the keyboard (end of the double consumption). The test banner "E2 SHELL READY" goes directly to serial; the built-in `echo` behaves like c:Echo (without enclosing quotes, newline). (2) **project theme** — colour 0 apple green ($7C3), colour 2 pure black, titles in pen 2 (the Workbench's DetailPen), console text on pen 2 by default. (3) **intuition without layers** — a window only clears the part of its rectangle that no window placed in front covers (`it_clearvis`, sweep by segments); on closing, the screen bar and the frames of the uncovered windows are redrawn if they are not covered, and these windows receive **REFRESHWINDOW**; **minimal IDCMP** (UserPort created if IDCMPFlags ≠ 0, IntuiMessage embedded in the window, reused once replied to); **BACKDROP** window placed at the back; `DrawImage` (−114, planes according to PlanePick/PlaneOnOff, same-colour segments), `AllocRemember`/`FreeRemember` (−396/−408); a screen loads its 32 colours. (4) **mouse pointer** — graphics: SPR0-7 pointers at the head of the master copper list (empty sprite by default, rewritten by LoadView, modifiable by ChangeSprite), sprite DMA, `GetSprite`/`ChangeSprite`/`MoveSprite` (−408/−420/−426, coordinates relative to the display window of the active ViewPort); intuition: arrow drawn for the project (colours 17-18), channel 0, moved by the pointer handler (`it_ptrmoved`, ib_MouseX/Y), now also installed on the floppy boot (`ptr_wire`). (5) **desktop** (`workbench.task`) — borderless BACKDROP background window under the screen bar (IDCMP REFRESHWINDOW), boot disk icon read by the **disk's icon.library** (`GetDiskObject("SYS:Disk")`) drawn by DrawImage at the top right (no position stored in Disk.info) with the volume name (Examine of SYS:) centred below; skipped as long as a window placed in front covers it, redrawn on REFRESHWINDOW. (6) **interaction** — the pointer handler passes the left button on to intuition (`it_button`): frontmost window under the pointer, close gadget -> **CLOSEWINDOW**, otherwise activation + **MOUSEBUTTONS** (SELECTDOWN/SELECTUP, relative coordinates, timestamp taken from the VBlank counter); pool of 4 IntuiMessages per window; **DoubleClick** (−102). The Workbench selects the disk icon on click (inverted rectangle), opens it on double-click: disk window (geometry from the DrawerData of Disk.info, title = volume name) with the root's icons (Examine/ExNext, `nom.info` -> GetDiskObject, positions from the .info files, name below), drawn within the inner bounds of the window; the close gadget closes it and the desktop is repaired. (7) **graphics** — `BltBitMapRastPort` (−606, CPU copy byte by byte with shift, clipped, NULL plane = 0 / −1 = 1): DrawImage builds a temporary BitMap and makes a single call (the old pixel-by-pixel rendering was visibly slow on WinUAE); BPLCON2 = $24 (sprites in front of the playfields: the pointer no longer goes under the title bar). (8) **floppy inserted on the insert-disk screen** — process `disk_watch` (pri −1): every 0.5 s `td_disk_present` (read of /CHNG; if it is low, a step pulse — the drive's "click" — re-arms the latch then re-read); drive seen empty then floppy present -> cold restart (Supervisor: RESET + jump to the ROM entry, in the same long word); a non-bootable floppy already present does not cause a loop. (9) **chip RAM** — MakeLibrary, the resident table and the demonstration tasks move to MEMF_PUBLIC (slow RAM first), console.device's historical bitplane is only allocated at the first write: Holiday Lemmings (chip hunk of 363 KB + 37 KB) gets its room back despite the Workbench screen. Proofs (FS-UAE, copy of WB 1.3.3, production ROM): green AmigaSlopDOS window with black text during loading (SetPatch, FastFonts...), closed at `endcli`; green desktop with title bar, "Workbench1.3" icon and red pointer; mouse driven by xdotool: double-click -> disk window with its 8 icons, click on the close gadget -> closed, desktop repaired; disk_watch: empty drive -> 0 continuously, non-bootable floppy -> present without restart, restart path proven (test ROM). **Honest scope**: no layers.library (SetPatch reports it), no OpenFont/topaz (FastFonts reports it), no menus, nested drawers, tool launching or scrolling of drawer windows (MountMF cut), no Ram Disk icon; the contents of an uncovered window not subscribed to REFRESHWINDOW are not restored; real insertion of a floppy could not be simulated under FS-UAE (key action not working): to be confirmed under WinUAE.
- **M7+ (MISSING RESIDENT MODULES) AND L4 (INTUITION ON LAYERS)**: (1) **new residents** — `mathffp.library` (`src/exec/mathffp.s`, pri 0, AUTOINIT, 12 FFP functions at LVOs −30..−96); `disk.resource` (`diskres.s`, pri 70: AllocUnit/FreeUnit, GetUnit with a `dr_Waiting` queue and GiveUnit that replies to the next requester, GetUnitID read from CIA-B at startup for DF1-3, DSKBLK/DSKSYNC/index relays to the current DiscResourceUnit); `potgo.resource` (`potgo.s`, pri 100: AllocPotBits/FreePotBits/WritePotgo); `keyboard.device` (`kbddev.s`, pri 60: READEVENT with a 16-event buffer and pending requests served by `kbd_devevent` called from the keyboard interrupt, READMATRIX, CMD_CLEAR, AbortIO, ADD/REMRESETHANDLER); `audio.device` (`audio.s`, pri 40: allocation by precedence with channel stealing and locks, DMA WRITE with cycles counted by the AUDn interrupts, WAITCYCLE, FINISH, PERVOL, STOP/START, FLUSH, RESET, READ, CLEAR, UPDATE, AbortIO). RESMAX goes to 32. (2) **exec** — signal semaphores (`semaphores.s`: Init/Obtain/Release/Attempt/Add/Rem/FindSemaphore, LVOs −558..−606; the releasing Release hands ownership directly to the first queued requester). (3) **graphics** — regions (`src/graphics/regions.s`: NewRegion, DisposeRegion, ClearRegion, Or/And/Clear/XorRectRegion, Or/Xor/AndRegionRegion; common union, difference and intersection engine over RegionRectangle lists); general `BltBitMap` (minterms, line buffer if source = destination), ReadPixel, LockLayerRom/UnlockLayerRom; all drawing in a layered RastPort goes through its ClipRects (layer lock taken by the call; ScrollRaster by pairs of ClipRects, a hidden source marks damage). (4) **`layers.library`** (`src/graphics/layers.s`, pri 31, 28 LVOs −30..−168, offsets checked against the Free Pascal unit `layers.pas`): simple, smart (saving of hidden parts; superbitmap treated as smart) and backdrop layers; rebuilding of the ClipRects on every stack change, uncovered background cleared, DamageList relative to the layer, BeginUpdate/EndUpdate, Move/Size/Upfront/Behind/MoveLayerInFrontOf/DeleteLayer, WhichLayer, SwapBitsRastPortClipRect, locks. (5) **L4** — intuition opens layers.library; a screen carries its LayerInfo and a simple backdrop layer for its bar; OpenWindow creates the window's layer (simple or smart according to the flags, a superbitmap being treated as smart; at the back if BACKDROP); CloseWindow destroys it and redraws; new functions WindowToFront/WindowToBack/MoveWindow/BeginRefresh/EndRefresh; step 7's clearing by segments (`it_clearvis`) disappears. (6) **fix of a latent memory overwrite** (`shell.s`): the BCPL command stub places the base of its frames at (top − 4) − size; the stack the shell allocated was exactly "size" bytes, so the first frame overwrote the last long of the previous memory block. At Workbench boot, it was the "old SP" slot of Execute's stack -> SOFTWARE FAILURE, depending on the ROM layout only (adjacent blocks). The block now has one more long (like runcommand's getvec vector). Boot probes: MATHFFP OK, DISKRES OK, POTGO OK, KBDDEV OK, AUDIO ALLOC OK, AUDIO PLAY OK, SEM OK, SEM WAIT OK, REGIONS OK, LAYERS OK (the last two compared pixel for pixel with a Python model). **Honest scope**: SetFunction remains a stub (SetPatch's fixes are not installed); no SizeWindow; neither ObtainSemaphoreList/Procure/Vacate nor InstallClipRegion.
- **WORKBENCH STEP 8 (INTERACTION)**: (1) **intuition** — task "intuition input" (pri 20) fed by an event ring filled by `it_event` (called by the pointer handler for each RAWMOUSE; movements are only reported during tracking); click: activation of the window hit (BACKDROP included), system gadgets (close -> CLOSEWINDOW, depth -> WindowToBack/Front, WINDOWDRAG title bar -> moving, size gadget -> resizing), otherwise MOUSEBUTTONS. Moving and resizing under LockLayers with an XOR ghost frame, applied on release. `SizeWindow` (−288: SizeLayer, borders and gadgets redrawn, NEWSIZE, repair) and `WindowLimits` (−318). **Menus** (`src/intuition/menus.s`): SetMenuStrip/ClearMenuStrip/ItemAddress/OnMenu/OffMenu/PrintIText/IntuiTextLength; right button -> menu bar and dropped-down menu in simple layers, highlighting by complement, inactive items ghosted by stripes, MENUPICK (menu/item code, NOSUB) on release, CHECKIT/MENUTOGGLE. (2) **gameport** — right button read on POTINP bit 10 (POTGO $0C00 via potgo.resource), IECODE_RBUTTON. (3) **graphics** — fast path of `BltBitMap` for the simple byte-aligned copy (restoring a window ×6 faster); fix of `lr_fill` (a0 overwritten by lr_damage -> infinite loop when a smart layer grows). (4) **dos** — `Execute` (global 101 and LVO): command passed to C:Run through the resident segment "CLI"; `CreateProc` inherits the global vector and frees its block when the process exits; stack of a process: last long = size, pr_ReturnAddr points to it (contract of the C startup code); `NIL:`; buffered writing (512 bytes per FileHandle, flushed before Read/Seek/Close); BCPL globals 3/4/5 (mult/div/rem). (5) **workbench.task** — up to 6 open drawers (double-click on a drawer, nested), resizable drawer windows, icons drawn as loading proceeds, launching of tools and projects through a WBStartup message (LoadSeg + CreateProc, freeing when the message comes back), Workbench menus (Open, Close), Disk (ghosted), Special (Redraw). Proven under FS-UAE: nested System drawer, double-click on Shell -> interactive AmigaShell (`echo`, `dir`), moving and resizing windows, menus, closing by gadget and by Workbench/Close. **Honest scope**: no icon dragging, nor Info/Rename/Discard/Format; repair after closing in 4 to 6 s; a launched tool takes 30 to 60 s to appear (floppy access); OpenFont/topaz and InitGels are still to be done.
- **STEP 9 — FONTS AND GELS**: (1) **fonts** (`src/graphics/text.s`) — topaz 8 is a real TextFont: hand-authored glyphs from `font8x8` also emitted in strike format (`topaz8_strike`, modulo 98, default glyph after HiChar) by `tests/mk_font8x8.py`; ROM template copied into RAM at graphics init, linked into `gb_TextFonts` (public offset 140) and set as `gb_DefaultFont` (154), GfxBase raised to 158 bytes. OpenFont (case-insensitive name, closest height, counted accesses), CloseFont, AskFont, AddFont, RemFont, AskSoftStyle/SetSoftStyle (bold and underline), AllocRaster/FreeRaster. Text/TextLength read the RastPort's font (CharLoc/CharSpace/CharKern, rp_TxSpacing, glyphs up to 32 pixels); fast path kept for aligned 8-pixel glyphs in JAM2. (2) **GELs** (`src/graphics/gels.s`) — list sorted by (Y, X) between two sentinels, Bobs drawn by rows of pixels (`gfx_putrow` from draw.s, through the layers) with background saved/restored, OVERLAY mask, PlanePick/PlaneOnOff; InitMasks, DoCollision (borders then pairs by CollMask, routines called with the C convention), animation (AddAnimOb, Animate with sequence change, Get/FreeGBuffers, InitGMasks). Boot probes FONTS OK and GELS OK. **Honest scope**: hardware VSprites not displayed; Before/After order, double buffering and italics not handled; Bob rendering per pixel (correct, not fast). Measurement (VBL_COUNT, production ROM): closing a drawer window costs ~1.4 s in DeleteLayer (phase A: copying back all the saves of the smart layers) and ~0.2 s in the intuition repair.
- **SETPATCH 1.38 / SYSINFO 4.4 — COMPLETE V34 EXEC**: (1) **34 missing exec LVOs** (`src/exec/execmisc.s`, AutoDocs):
  SetFunction (real: JMP rewritten, LIBF_CHANGED, sum recomputed), SumLibrary, Cause + software interrupt
  queue (`EXEC_SOFTLIST`, level 1 SOFTINT server, masking by INTENA and not Disable since callable from an
  interrupt), Alert (serial message "Software Failure / Recoverable Alert", stop if dead-end), SetSR,
  SuperState/UserState, GetCC, RemIntServer, AllocEntry/FreeEntry, SetExcept, AllocTrap/FreeTrap, RemResource,
  RawIOInit/RawMayGetChar/RawPutChar, Obtain/ReleaseSemaphoreList; `src/exec/memory.s` reworked: AllocMem/FreeMem
  rest on **Allocate/Deallocate** (per MemHeader), plus **AllocAbs** and **AddMemList**. Still `_unimpl`: the
  private ones (ExitIntr..Exception), Debug, Procure/Vacate, SumKickData. (2) **Alert vector relayed in RAM**
  (`EXEC_ALERTSTUB` $766): SetPatch only replaces Alert if the old vector is in ROM, and its replacement jumps
  into the 1.3 ROM's code; outside the ROM, it cancels its own fix. (3) **DeleteLayer in three steps**
  (`ly_dl_lock`/`ly_dl_remove`/`ly_dl_unlock`, arguments on the stack) behind an entry word + branch: SetPatch's
  DeleteLayer finds these three routines (shape checked on the binary). (4) **Shell**: on return from a
  command, only the seglist still in `cli_Module` is unloaded (SetPatch sets it to 0 to stay resident; unloading
  it left its replacements pointing into reused memory → simultaneous crashes of all the
  tasks); redirection `> nom` with a space accepted. (5) **GfxBase with the public V34 layout** (LOFlist +50,
  Modes +158 updated by LoadView, VBlank, system_bplcon0, DisplayFlags = PAL +206, normal dimensions,
  MicrosPerLine); private fields (sprites) moved after the public part (they occupied copinit/cia/blitter/
  LOFlist). (6) **CIA TODs started** in `cia_init` (CRB ALARM = 0, TODHI, TODMID, TODLO last, by MOVE:
  CLR would read TODHI and freeze the reading) — SysInfo waits under Forbid for the CIA-A TOD to advance by 60.
  (7) **DF0 FileSysStartupMsg** (`boot.s`, `FSSM_*` from `dospkt.i`): dn_Startup = BPTR of an FSSM (unit 0,
  fssm_Device = BSTR "trackdisk.device" + NUL, fssm_Environ = DD DosEnvec of 13 longs in ROM, flags 0), like
  V34 (`handlers-v34.md`). It was 0: SysInfo read the device name through an FSSM at $0 and its unbounded string copy
  swept the whole memory (custom registers included → grey screen, $FC/"f" bytes on serial). Diagnosed
  with a write breakpoint on SERDAT in FS-UAE's console debugger (`console_debugger`, F12+D injected).
  **Result**: SysInfo 4.4 displays its whole page (CLOCK FOUND, STD AGNUS 512K, PAL, STD DENISE, 15.72 kHz,
  EClock 709379, 50/50 Hz).
- **STEP 10 — TEXT GADGETS AND RENAME**: (1) **STRGADGET** (gadgets.s, public StringInfo structures): a click
  in the gadget or `ActivateGadget` (LVO -462) makes it the active text gadget (IB_STRGAD/IB_STRWIN, cursor placed under
  the click, text copied into the undo buffer, GADGETDOWN if GADGIMMEDIATE). The **keyboard** is routed to it by the
  pointer handler (input.device, pri 50, before the console): as long as a text gadget is active, each RAWKEY is
  neutralised (IECLASS_NULL, the console does not receive it) and the pressed key goes into the ring of intuition's input
  task (code IT_KEYCODE + keycode, qualifier), which applies it (`str_key`): insertion (kbd_cook),
  Backspace, Del, arrows (Shift: start / end), Right Amiga + X (clear) / + Q (undo), Return / Enter
  (LONGINT converted into si_LongInt, GADGETUP if RELVERIFY). A click outside the gadget deactivates it without a message;
  closing the window / RemoveGadget forget it. Rendering: text visible from si_DispPos (which follows the cursor),
  cursor in COMPLEMENT. Scope: left alignment only (STRINGCENTER/RIGHT ignored), no ALTKEYMAP.
  (2) **Workbench Rename** (workbench.s, `wb_rename`): "Rename" window with a prefilled and activated text gadget;
  Return renames the object then its ".info" and re-reads the drawer, the close box cancels. Proven under FS-UAE
  (prod ROM, WB disk): drawer Empty renamed "Vide", checked with xdftool (Vide + Vide.info).
  (3) **Serialised handler startup** (dos_lib.s, DOS_HSEM semaphore in low RAM $76C): the handler only sets
  dn_Task on receiving its startup packet (spec §13.3) and loading its segment takes a long time; two
  processes opening the same device without a task ("run copy x to pipe:a" then "type pipe:a") each launched an
  instance of L:Pipe-Handler — the writer and the reader did not see each other, `type` waited forever. The
  dn_Task = 0 path of the resolution takes the semaphore and re-reads dn_Task before starting. Race revealed by a
  mere shift of the boot timing (RT_ENDSKIP of workbench.task moved: the ROMTag scan skips 416 fewer bytes
  ); diagnosed by walking the exec lists in the FS-UAE debugger (4 PIPE processes -> 1 after the fix).
  Limit: a handler that, during its own startup, would start ANOTHER handler from another process
  would block (none in the known 1.3).
  (4) **"Please insert volume" requester** (dos_lib.s, `dos_volreq`, spec handlers-v34 §4.1): prefix unknown
  to the DosList, or known volume without a task (disk absent) -> AutoRequest "Please insert volume / <name> / in any
  drive", Retry / Cancel (DISKINSERTED counts as Retry); Retry restarts the resolution, Cancel returns 218. No
  requester for a plain task, if pr_WindowPtr = -1, or for "NIL:". Compared with the real KS 1.3 (black-box
  probe, `type foo:x` then click on Cancel): same text, same buttons, same sequel ("Can't open foo:x", "type failed
  returncode 20"). Differences: position of the window; no prior FLUSH to the file-handler (nothing pending on our
  side).
  (5) **Redirections only before the arguments** (shell.s, `sh_build_args`, spec §4.2): after the first
  argument (or quote), ">" and "<" are ordinary characters. Compared with the real 1.3: `echo "A" >ram:x`
  -> "Invalid argument to ECHO" on both sides. No ">>" in 1.3 (`>>x` = ">" to a name starting with
  ">").
  (6) **Error texts through C:FAULT** (bcpl.s, `rt_fault`, spec docs/analysis/fault-v34.md): global 104
  `fault(code)` loads C:FAULT without a requester (pr_WindowPtr = -1 while loading), sets pr_Result2 = code
  AFTER loading (C:Fault reads the code there and then only writes the text), launches it through runcommand (400 longs, without
  arguments, the caller's outputs) then unloads it; fallback "Error code <n>" if not found. The shell also uses it
  for "Unable to load X:". Compared with the real 1.3: `copy zzz to ram:` -> "Can't open zzz for input -
  object not found" on both sides; disk without C:Fault -> "Error code 121".
  (7) **System time at mount** (handler.s, `hnd_bootclock`, spec boot-clock-v34): at the first packet of the
  DF0: file-handler, the time takes the most recent of the root block's dates (root directory and disk) if it
  is still on the first day and earlier; never moved back. Compared with the real 1.3: `date` at boot displays the date
  of last modification of the disk on both sides ("<unset>" before). Redone at every mount since the
  disk change (below).
  (7b) **Disk change** (spec `docs/analysis/disk-change-v34.md`, 2026-10-27): the DF0: handler wakes up
  on a packet or on a 1 s timer tick (UNIT_VBLANK) and queries trackdisk (TD_CHANGESTATE, TD_CHANGENUM; trackdisk
  gives a probe step with the motor stopped when /CHNG is low). Ejection: volume detached (node removed from the DosList if it
  has neither a lock nor an open file — usage count in dol_unused, +$24 —, otherwise dl_Task := 0), IECLASS_DISKREMOVED.
  Insertion: block 0 ("DOS\0", otherwise the type as is / "BAD\0"), root block checked ("NDOS" otherwise), node with the
  same name and same creation date reactivated or created at the head of the list (DL_VOLUME), bitmap forgotten, time set,
  IECLASS_DISKINSERTED (also for a non-DOS disk). A lock or a file of another volume is refused (218), the
  root without a disk too (226 / 225). ACTION_INHIBIT detaches without an event and remounts when lifted. Context of the
  handler in low RAM (HND_CTX, $7C0); the volume node is no longer created by dos at boot. intuition broadcasts
  DISKINSERTED / DISKREMOVED to all windows that request them (it_diskbc). Workbench: one icon per mounted
  volume (table WBS_VOLS, 8 at most), "<volume>:Disk.info" otherwise a default icon drawn by hand, placement in
  96 px columns from the right; surveyed at startup, at the 5 s tick and on these IDCMPs; RAM DISK appears there.
  Requester "Please replace volume / <name> / in any drive" (2026-10-27, spec §2.4): the handler keeps in
  HND_REFVOL ($7C4) the volume of a refused lock or file (218); `dos_pktretry` (dos_lib.s), called by the
  two packet-sending paths (`dos_sendpkt` and the BCPL runtime's `sendpkt`), displays the system requester (Retry /
  Cancel, window pr_WindowPtr, nothing if -1 or for a plain task) if this volume is still absent; Retry or
  DISKINSERTED (the handler keeps ticking while the caller waits) resend the packet, Cancel returns 0 / 218.
  Proven under FS-UAE (dskchg LA probe, V11): ejection -> requester; reinsertion -> closed by itself, Examine = -1,
  IoErr 0, Lock("Workbench1.3:c") and Lock("DF0:") succeed; Cancel -> Examine = 0, IoErr 218.
  Known differences: no "DF0:NDOS" icon, a volume whose window is open still loses its icon on
  ejection if it has no lock; a Lock by the name of a known but absent volume gives "Please insert volume"
  (insert/replace split not settled by the spec).
  (7g) **Polygon and ellipse fills, Flood, Amiga-key cat** (2026-10-28; spec
  `docs/analysis/graphics-area-v34.md`).
  - graphics (`src/graphics/area.s`): InitArea (−282), InitTmpRas (−468), AreaMove/AreaDraw/AreaEnd (−252..−264),
    AreaEllipse (−186), DrawEllipse (−180), Flood (−330). The vertices are recorded as in 1.3:
    - flags $00 move, $02/$03 draw, | $04 outline, $83 then $02 ellipse;
    - −1 when the table is full;
    - closing by AreaDraw through its LVO, isolated AreaMove replaced.
    AreaEnd builds a one-plane mask with the processor, in three passes:
    - crossing points in XOR (lines [top, bottom[ of each non-horizontal edge, line bounds of the ellipses);
    - filling of each line;
    - complete edges drawn by Draw's unified Bresenham, in the direction of the edge (pentagram pixels
      identical to 1.3). They are erased if DrawMode = JAM1 and AreaPtSz = 2, like 1.3.
    Then rendered line by line by RectFill, then Draw/Move outline in AOlPen if AREAOUTLINE. DrawEllipse:
    Kennedy's algorithm in two sets, points set through the WritePixel LVO. Flood: 4-connected fill by
    lines (ReadPixel), boundary AOlPen (mode 0) or starting colour (mode 1). Differences kept:
    - the table is not translated and no entry beyond Count is read (no stray point, T27);
    - without TmpRas (or with too small a TmpRas), AreaEnd allocates its mask instead of writing into low memory;
    - Flood does not allocate TmpRas.Size bytes of chip: it succeeds where 1.3 returns 0 (T32).
  - RectFill: AREAOUTLINE outline (interior shrunk by one pixel in COMPLEMENT, Move/Draw in AOlPen and JAM1, cp in
    (xmin, ymin)); multicolour pattern (negative AreaPtSz, 2^n words per plane).
  - Probe `tests/garea_probe.sh` on our ROM: 34 tests; T1–T6, T8–T10, T13–T16, T18–T26, T29–T31 and T33
    identical to the spec's vectors, T27/T32 = differences above.
  - intuition (`menus.s`): a COMMSEQ item displays its letter on the right, preceded by the Amiga key symbol. This
    symbol is a small cat (23 × 8 in hires, 14 × 8 in lowres, drawn for KickSlopStart). Right-Amiga keyboard
    shortcuts are handled (next point). Visual probe `tests/menucat.s`.
  - intuition, Right-Amiga shortcuts (spec intuition-input-menus-v34 §3.11, 2026-10-28):
    - **handler** (`it_keyin` then `mn_keyshort`): the key pressed with RCOMMAND is converted by the keymap
      (`kbd_cook`). An active window with a bar is required, without a requester, without an open menu and without RMBTRAP.
      The search goes in the order menus, items, sub-items; it compares `Command & $5F` (COMMSEQ is not
      tested) and an item with sub-items only compares those. Found: the event is swallowed (IECLASS_NULL,
      the release goes through normally) and the ring receives IT_MENUKEYCODE (x = code, y = qualifier).
    - **input task** (`mn_keypick`): if menu, item and sub-item are enabled, `mn_select` (CHECKIT, as
      with the mouse) then MENUPICK with the code; otherwise MENUPICK MENUNULL. The key's qualifier goes into
      im_Qualifier.
    - No MENUVERIFY (absent from the mouse path too).
    - Probe `tests/menucat.s` and the `keyraw` command of `tests/dskchg_run.sh` (Super_R = Right Amiga): O → $F800,
      S → $F820, disabled item → MENUNULL, Q alone → nothing; mouse choice unchanged ($F800).
  - intuition, menu checkmarks (§3.5): OpenWindow sets `Window->CheckMark` (+$64) = NewWindow.CheckMark, otherwise our
    internal checkmark (hires 15 × 8 or lores 9 × 8 depending on the screen, LeftEdge 2, cat format): a cat paw
    print. The first drawing (a tick stroke) looked too much like the 1.3 image, which the spec shows: replaced
    after the audit of 2026-10-29 (docs/audit/specs-review.md).
    A CHECKIT and CHECKED item receives it at (x of the item, y of the item + TopEdge of its ItemFill). The
    toggling is still done on closing (mouse) or on the shortcut: no redrawing in an open box. Probe
    `tests/menucat.s`, menu "Option": "Coche" checked at the start, "Bascule" checked then unchecked by Right-Amiga+B.
  - intuition, submenus (§3.5, §3.7): pointer on an item that has sub-items → sub-item box
    (simple layer on top; the item box is now a SMART layer, restored as is when the sub-item box
    closes). Extent of the sub-items (relative to the item) widened by the margin, bounded so as to
    touch the item, placed on it then brought back into the screen. Tracking: a touched sub-item is highlighted and
    re-highlights its parent item; outside the sub-items the box stays; another item or a title removes it. Item drawing
    factored out (`mn_drawitems`, origin IB_DOX/IB_DOY, whole box ghosted if the menu or the parent item
    is disabled). MENUPICK = sub-item << 11 | item << 5 | menu; item with sub-items without a chosen sub-item
    → MENUNULL. Probe `tests/menucat.s`, "Export": Texte → $0080 (mouse and Right-Amiga+T), Image → $0880, back on
    "Quitter": box removed, item box intact.
  (7f) **Blitter and alerts according to the graphics-blitter-v34 and alert-v34 specs** (2026-10-28).
  - graphics: BltMaskBitMapRastPort (−636: three passes of BltBitMapRastPort, source in $90, mask with the caller's
    minterm through a dummy BitMap whose planes all point to the mask, source in $90; NULL mask: nothing),
    ClipBlit (−552: clipping by the ClipRects of the source layer, hidden piece without a save = destination
    intact, then destination clipping by BltBitMapRastPort; differences: neither source SuperBitMap nor reordering of the
    ClipRects for an overlapping copy), BltBitMapRastPort and ClipBlit return 1, BltBitMap only handles the planes
    common to both BitMaps, QBlit/QBSBlit (−276/−294: immediate call in the caller's context, A0 = $DFF000,
    A1 = node, called again as long as Z = 0, cleanup if CLEANUP; difference: a blit in progress is waited for instead of being relayed
    by the BLIT interrupt). Probe tests/gblit_probe.sh: T1, T2, T8, T10, T11 identical to the real ROM; differences
    kept: T3/T4 (zero width or height: 1.3 writes 1024 lines / 64 words), T6 (1.3 truncates a BltClear at
    1024 lines), T7 (BltTemplate without a layer: we keep xSrc, see fastfonts-ff), T9 (BlitLock not held).
  - intuition DisplayAlert (−90, src/intuition/alert.s): raster 640 × height, 1 plane, background $111, text and frame
    $F20, 6 px / 3 lines frame blinking (COMPLEMENT, 46 frames counted on the beam, so interrupts off
    possible), "x, y, text, continuation" blocks read byte by byte, buttons through CIA-A PRA bit 6 / POTGOR bit 10 (left
    1, right 0, left takes priority, no timeout), sprite DMA off during the wait; raster impossible:
    0, or exec Alert for a dead-end alert. Difference: own copper list (gb_LOFlist and COP2LC diverted) instead
    of a ViewPort under which the screens slide: the rest of the display is in the background during the alert, and the screen
    comes back afterwards even after a dead-end alert.
  - exec Alert: recoverable (and exception number with a null high word) -> LastAlert, Guru "Recoverable Alert." /
    "Not enough memory." / "Software Failure." + "Press left mouse button to continue." + "Guru Meditation
    #XXXXXXXX.YYYYYYYY" (DisplayAlert(0, text, 40)), d0 = button; dead-end -> 'HELP' at $0, number at $100,
    second number (long pointed to by A5, if it is in chip) at $104, six LED blinks, RESET + jump to word 2
    of the ROM (same long); alert_boothook (role of alert.hook) displays this Guru at the next boot, before the strap.
  - Task exception (exc_default): Guru "Software Failure." #<vector>.<task>; left = restart like
    1.3, right = task suspended (no ROM-Wack); exception in supervisor: dead-end alert (before: silent
    stop). Proven by tests/alert_probe.sh (modes 0 and 2) on our ROM, by a capture of the Guru at the next
    boot ("Software Failure. … Guru Meditation #80000000.00000000", blinking frame) and by a bootblock with an
    illegal instruction (Guru #00000004.<task>). DisplayAlert goes through COP1LC (at boot, no view chains
    to COP2LC yet) and then restores the chaining of the loaded view, or the previous DMA bits.
  (7e) **Floppy writing in the real 1.3 format, complete graphics table** (2026-10-27, before a trial on a real
  A500; spec `docs/analysis/trackdisk-write-v34.md`). Track written: gap of 1,660 bytes, 11 sectors, tail word
  `$AAA8` = 6,815 words (~218 ms, exceeds one revolution: no remnant of the old track even on a slow drive; before:
  gap of 700 bytes, 6,334 words, fragile beyond ~1.5% slowness). Precompensation 140 ns from track
  81 on (TD_PCTRACK). TD_FORMAT no longer touches io_Actual. Probe `tests/tdwrite_run.sh` on our ROM: same DSKLEN
  ($DA9F) and ADKCON ($1100 / $3100) as the real ROM, steps A-N identical except H (1.3 writes a sector for a
  CMD_WRITE of length 0) and O (its TD_PROTSTATUS always turns the motor off), differences kept. graphics: the table
  stopped at −636 (106 vectors): a call to −642..−654 jumped out of the table; it has the 109 V34 vectors,
  SetRGB4CM (−630) and AttemptLockLayerRom (−654, AttemptSemaphore of the layer lock); BltMaskBitMapRastPort
  (−636) remains to be done (spec graphics-blitter-v34).
  (7d) **trackdisk: long tracks and incomplete tracks** (2026-10-27, reported on the ESP32 emulator
  amiga500-esp32: "Unable to load …: Error code 121" on WB 1.2, SysInfo, Caesar). Its track is 6,399 words
  (gap of 830 bytes): our decoder stopped its search 1,200 bytes before the end of the raw buffer, and the last
  sector of a read started before the gap was ignored; `td_fill` then returned a "partial" track that the
  read copied anyway, missing sector included (stale buffer contents -> invalid hunks, 121). Now:
  a header is accepted as long as header + data (TD_SECBODY, 1,080 bytes) fit in the buffer; the decoder returns
  the mask of DISTINCT sectors (a0); `td_fill` re-reads an incomplete track up to TD_FILLTRIES (4) times,
  accumulating the good sectors (a read of the wrong track cancels the accumulation); a read is only served if
  every requested sector is good, otherwise TDERR_NotSpec. Test `tests/td_decode_test.py` (unicorn, 68000): the
  real ROM code on synthetic tracks (gaps 532/700/830, tracks 0/41/159, start at each of the 11
  sectors): 99/99; the old decoder failed in 30 cases out of 33 with the 830 gap.
  (7c) **OctaMED Professional v4** (spec `docs/analysis/octamed-v34.md`, 2026-10-27): a CUSTOMSCREEN 640 x 256
  x 3 screen and a BACKDROP|BORDERLESS|RMBTRAP window; the buttons are zones tested on MOUSEBUTTONS. Fixes:
  - **boot self-tests that give back what they take**: M7B resets the CIA-A timer A latch to $FFFF (power-on
    value) after its 255-tick one-shot. OctaMED starts this timer without reloading it: at $00FF it
    ran at ~2.8 kHz, the machine saturated and the editor was never drawn. M7B also removes its test PORTS
    server, M5B its dummy vector (CIA-B bit 1, disabled).
  - **proportional gadgets**: `prop_render` and `prop_update` go through `prop_keep`, which restores FgPen, BgPen and
    DrawMode of the gadget's RastPort, often the window's. OctaMED redraws its file list after
    RefreshGList of its scroller without resetting its pens: it came out in the background pen, hence invisible.
  - **graphics**: SetRGB4 patches the master copper list for every ViewPort of the view (fragment of
    GFX_FRAG_SIZE per ViewPort); WaitTOF (−270), BltClear (−300), PolyDraw (−336), VBeamPos (−384, VPOSR/VHPOSR),
    FreeSprite (−414), GetRGB4 (−582).
  - **intuition**: ShowTitle (−282, title bar layer in front or behind, then refresh),
    ViewPortAddress (−300).
  - Proven under FS-UAE (`tests/dskchg_run.sh`): welcome screen and palette as expected, editor, FILES (disk
    list, volumes, gauge), PLAY, PLAY SONG (playback, TIMER advancing), STOP, keyboard arrows.
  - Harness: `DSKCHG_SERIAL=1` captures the serial line (ROM `-DDOSTRACE=1`), `key` command, FS-UAE keyboard joystick
    turned off (`joystick_port_1 = none`: otherwise the arrows never reach the CIA), F12+D retried.
  - Harness limitation: FS-UAE does not pass Ctrl-F1 through.
  (8) **Faithful memory releases (exec)**. Revealed by the time-at-mount change: the WB boot crashed ("Background CLI",
  global 133 absent) as soon as a non-zero time preceded SetClock, because a stack block of the background CLI had been
  reallocated. Three causes, found with the MEMTRACK tracer:
  - **RemTask only frees `tc_MemEntry`**, like the real exec. Before, RemTask and `trap2_handler` automatically freed
    the stack and `TC_SIZE`: a leak for a process (0xBC returned as 0x5C), and a double free for a task created by a
    program, which describes its memory in `tc_MemEntry` or frees it itself. Our creators (`proc_create`, demo
    tasks) go through `task_alloc` (tasks.s): AllocEntry {structure, stack} added at the head of `tc_MemEntry`, and
    `SPLOWER`/`SPUPPER` set. `task_freemem` frees each MemList with FreeEntry, computing the end of the list beforehand,
    because the list head lives in the task that the last MemList frees.
  - **FreeEntry takes the MemList in A0** (exec_lib.fd), not in A1. icon.library chains RemHead then FreeEntry,
    with the MemList in A0 and the list still in A1. With A1, we freed the list header located inside
    its DiskObject block: 16 bytes of a block still allocated (BindDrivers case with the invalid `.info` of
    SYS:Expansion). Probed on the real ROM (breakpoint on the FreeEntry vector): A0 = MemList of 10 entries.
  - **Execute** (bcpl.s) lost d5 (BPTR of the command) across runcommand, hence a freevec(0) and a leak of
    64 longs per call.
  `timer_abortio` is real: the request still queued is removed, IO_ERROR = IOERR_ABORTED, then ReplyMsg.
  **MEMTRACK tracer** (memory.s, diagnostic ROM only, the normal ROM is unchanged):
  `make BUILD=build/mt VASMDEF=-DMEMTRACK=1 KICK_ROM=build/kick13-mt.rom kick`. Each successful AllocMem or AllocAbs
  is recorded (table of 3000 entries in chip memory, pointer at `MT_TABLE`). FreeMem emits on serial:
  - "MTSZ address returned-size recorded-size caller" if the size differs;
  - "MTUNK address size caller task" if the address is unknown.
  The complete WB 1.3.3 boot no longer emits any line.
  (9) **Workbench: Clean Up and Snapshot** (workbench.s), probed on the real 1.3.
  - Probing method: measurement with the mouse and capture; positions are recorded by comparing the same icons before
    and after, at the scale of 100 screen px for 96 hires px.
  - **Clean Up**: the drawer's icons are sorted by position (X then Y), then arranged in columns from top to bottom.
    Each cell is 96 px wide and the icon is centred in it: X = 96·k + (96 − width)/2. Vertical gap: 11
    below each icon. Column change beyond the inner height of a 1.3 window (height − 20).
    The positions stay in memory.
  - On SYS: of WB 1.3.3, the result is identical to the real ROM: Utilities (11,0) and Shell (21,29), MountMF
    (104,0), System and Prefs (203), Expansion and Empty (299).
  - **Snapshot**: the position of the selected icon is written into its `.info` by PutDiskObject, without a
    requester (`pr_WindowPtr` = −1). For the disk or a drawer whose window is open, the geometry of this
    window also goes into `dd_NewWindow`.
  - The `.info` files written are read back by the real 1.3.
  (10) **Workbench screen title, Version and Last Error** (spec workbench-task-v34 §6, clean-room reviewed):
  - **5 s tick**: VBLANK timerequest, reply on the "Workbench" port. At each tick, AvailMem(0); if the value
    has changed, `RawDoFmt("Workbench release 1.2.  %ld free memory")` then SetWindowTitles(window, −1, title) on the
    backdrop and each open drawer.
  - The SetWindowTitles diverted by the disk's LoadWB turns the text into "Workbench release.      N free
    memory", as on the real ROM.
  - **Frozen message** ("message displayed" bit): DisplayBeep, then formatting into a dedicated buffer. The tick does not touch
    the title any more until the next left click or menu choice.
  - **Version**: "Kickstart version %ld.%ld. Workbench version %ld.%ld". The first two numbers are read from
    the ROM header (words +$0C/+$0E; base = $1000000 − size at $FFFFEC). The other two are lib_Version and
    lib_Revision of version.library, loaded from LIBS:, or −1 without it.
  - **Last Error** redisplays the last message, without a beep.
  - **Rename** locks the title and displays the prompt "Enter the new name.  Press return when done.".
  - **Intuition**:
    - **SetWindowTitles** (−276) and `wd_ScreenTitle`: the screen bar shows the screen title of the active
      window, otherwise that of the screen.
    - **DisplayBeep** (−96): colour 0 is complemented for 6 frames.
    - **Activation, intuition 34.3 rule**: OpenWindow only activates if ACTIVATE is requested, and places the window
      after the active one in the Parent/Descendant chain. CloseWindow of the active window activates its Parent, otherwise the
      first window of the screen (on our side, the frontmost), otherwise none.
    - Consequence: after `endcli`, the backdrop is active and its menus respond without a click, as on the real ROM.
  - **LoadView** now preserves d2: it was overwritten by the rewriting of the sprite pointers, which disturbed
    the callers.
  (11) **ScrollRaster with the blitter** (draw.s, `.sc_blit`): in the fast path (a single visible ClipRect covers the
  rectangle), if all the planes are in chip memory (TypeOfMem), the moved rectangle is copied with one blit per plane.
  - Channels: A constant $FFFF with the first- and last-word masks, B = source, C = D = destination, minterm
    AB + ~AC. Downwards, in descending mode: end addresses, masks swapped.
  - Otherwise, the old line-by-line CPU copy applies.
  - The blitter is taken through **OwnBlitter / DisownBlitter**, now a real lock: private semaphore `gb_BlitSem`
    in GfxBase. DisownBlitter has no effect for a task that does not own it.
  - Measurement in emulated time, 400 lines of `type ram:` in the boot window: 89 s → 70 s. The real 1.3 takes 38 s.
    Final screen identical to the pixel.
  - con.handler's serial mirror only accounts for about 3 s.
  (12) **Workbench error messages** (spec workbench-task-v34 §6.9): `wb_error(action, nom)` reads IoErr before any
  other dos call, formats the action (1.3 table), then displays "Error while %s: %ld" as a frozen message. The first
  message displayed wins.
  - **Opening a drawer**: Lock or Examine fails → "examining <drawer>"; ExNext fails (other than 232) →
    "examining directory".
  - **Launching**: LoadSeg fails → "opening <tool name>"; for a project, Default Tool as is.
  - **Rename**: ":" or "/" → "Do not use '%lc' in names"; failure other than 205 → "moving <old name>".
  - **Discard**: 205 counts as success, otherwise "removing <name>", then "removing <name>.info".
  - **Snapshot**: PutDiskObject failure → "writing <name>".
  - **Difference**: no errorreq requester before the Rename message.
  - **dos LoadSeg** now sets IoErr: 121 if the file is not an executable, 103 without memory. The code is
    set after the Close, whose reply reset `pr_Result2` to 0.
  - Compared with the real 1.3 (non-executable tool "Bad"): "Error while opening Bad: 121" on both sides.
  (13) **Workbench Info and GIMMEZEROZERO windows** (specs workbench-task-v34 §7/§7.8 and intuition-gzz-v34, clean-room
  reviewed).
  - **Info** (`wb_info`, Workbench menu item 4): Lock of the directory that contains the icon, OpenLibrary("info.library"),
    CurrentDir, GetWBObject (name "Disk" for the disk), name copied and stored through AddFreeList, lock set in the
    WBObject (+$A4; for the disk, also in the DrawerData +$1BA). Call of function −30 (A0 = A6 = InfoBase,
    A1 = WBObject), then FreeWBObject, current directory restored, CloseLibrary, drawer reloaded, UnLock.
    Without info.library: message "Info not available".
  - **Borders enlarged by the gadgets** (all windows): a gadget whose Activation carries LEFT/RIGHT/TOP/
    BOTTOMBORDER widens the corresponding border. Relative positions (GREL*): edge of the domain − 1.
  - **GIMMEZEROZERO** (screens.s): the frame layer is always SIMPLE; an inner layer is created in front of
    it, and WLayer/RPort designate it; `wd_BorderRPort` (+58) is the frame's. Close, depth,
    moving and resizing act on both layers. GZZGADGET gadgets are in the frame, the
    others relative to the interior (`gad_rect`, `gad_rp`).
  - **Gadget drawing order like intuition 34.3** (`gad_drawrev`): a range is drawn in reverse order, so that the
    first gadget of the list ends up on top. This behaviour is used by OpenWindow, by the frame repair and by
    RefreshGadgets. info.library needs it: SAVE and QUIT are at the head of the list, in front of a filler that
    covers them.
  - **Bug fixed**: `gad_comp` (highlighting by complement) saved 9 registers and only restored 8.
    Any click on a GADGHCOMP gadget of this path would have ended in SOFTWARE FAILURE.
  - Proven under FS-UAE (WB 1.3.3 disk, Expansion drawer): window identical to the real 1.3. QUIT closes the window.
    SAVE writes the comment typed in, which reappears on reopening.
  (14) **Text: "string" path** (draw.s, `.tx_try` / `.tx_str`). It applies in JAM2 without COMPLEMENT, without
  style, fixed 8-pixel font (no CharSpace nor CharKern, zero TxSpacing), and only if the whole range
  fits in one ClipRect. This is the case for the console.
  - Per slice of 16 characters at most, the glyph pointers are computed once.
  - Then, plane by plane and line by line: byte = (glyph AND m1) XOR m2. m1 is 1 if pens A and
    B differ on this plane, m2 is the bit of pen B; INVERSVID does m2 ^= m1.
  - The stream is shifted by x & 7; the out-of-range bits of the two edge bytes are kept.
  - A glyph of another width, or not byte-aligned, falls back to character-by-character rendering.
    A range straddling ClipRects disables the path for the rest of the call.
  - Measurement, 400 lines of `type` in the boot window (production ROM, emulated time): 70 s → 45 s. The real
    1.3 takes 38 s. Final screen identical to the pixel.
  - Breakdown before the fix, obtained through variants: without `Text` 35 s, without scrolling 59 s.
  - Side effect on a dev probe: the "AUDIO PLAY" probe (pri 0) observes by polling the window
    "w1 rendered, w2 in progress" (~210 ms). With a faster console, the `hnd` boot displays more, with its
    serial copy under Forbid; the probe only ran about 1,300 times over 420 ms and missed the window
    (`d5` = 1). It now runs at pri 5, above the shell and the console. audio.device is not at fault.
  (15) **Workbench Duplicate** (spec workbench-task-v34 §6.6 and §7.9, clean-room reviewed; probed on the real 1.3).
  - **Object** (`wb_duplicate`): CurrentDir of the drawer, Lock of the original (failure: "accessing <name>"), new name through
    icon BumpRevision (−108, "copy of …", truncated to 25 characters).
  - **Icon**: the original's WBObject is read (GetWBObject), shifted by +30/+15 and written under the new name by
    PutWBObject (−36) **before** the data, then restored and returned. The icon is then read back; on failure,
    "Cannot read info file <name>" and nothing is copied.
  - **Display**: the icon is added to the drawer and drawn without re-reading the drawer; the original stays selected.
    An icon with the same name already displayed is replaced, and the drawer redrawn.
  - **Copy** (`wb_cptree`): recursive, Open/Read/Write with a 4 KB buffer. 1.3 reads and writes 512 bytes at a time through
    two coroutines, which changes nothing observable. Messages "accessing / opening / reading / writing /
    examining" like 1.3. Protection, date and comment are not copied, as in 1.3.
  - **Disk**: launches its default tool (DiskCopy) with the disk as argument; without a tool, "This disk cannot be
    copied".
  - **dos DeviceProc** (−174): returns the handler's port. IoErr is the lock of an assign, 0 otherwise. DiskCopy needs it.
  - Compared with the real 1.3 (Duplicate of the Expansion drawer): same name, same `.info` (position 233,15) written before the
    directory. Copy of Prefs: 8 files identical byte for byte.
  - **DiskCopy 1.4 works** from Duplicate of the disk (spec intuition-requesters-v34 §5-§7). Three fixes:
    1. **DF0: handler — returnpkt reply**: the packet goes back to `dp_Port` through PutMsg, and `dp_Port` receives the handler's
       port. Before, ReplyMsg went through `mn_ReplyPort`, which DiskCopy does not fill for its ACTION_INHIBIT:
       it waited forever.
    2. **ACTION_INHIBIT** (31) accepted. On inhibition, the modified bitmap is written; when lifted, it is forgotten
       and will be re-read (`ow_inhibit`).
    3. **AutoRequest conforming to BuildSysRequest**:
       - window at (0,0), title of the calling window ("System Request" without it), pens of that window;
       - flags NOCAREREFRESH, ACTIVATE, SIMPLE_REFRESH, DEPTH, DRAG and SIZING, minimum size 88×24;
       - IDCMP pflag | nflag | GADGETUP | RAWKEY;
       - requester over the whole interior: background in pen 1, frame inset by one pixel in pen 0 (uprights two
         pixels wide), body at its corner;
       - buttons: text + 12 wide, font + 6 high, positive at 14 from the left edge, negative at 13 from the right edge,
         4 pixels above the bottom; inner rule in pen 0 and outer frame in pen 3;
       - Amiga-V / Amiga-B handled (no effect as long as RAWKEY is not routed to the windows).
    - Difference at the time (requester drawn in the window, without a layer): lifted in (30), AutoRequest now goes through
      BuildSysRequest and Request.
  - Proven under FS-UAE:
    - the "Put SOURCE disk" prompt is identical to the real ROM, apart from the window dressing (right border and
      size gadget);
    - Cancel ends DiskCopy, Continue starts the reading;
    - Discard's confirmation is displayed in the new format.
  (16) **Keyboard to the windows (RAWKEY) and Alt/Amiga qualifiers.**
  - **keyboard.s**: `KBD_QUAL` also tracks left/right Alt and left/right Amiga ($64-$67), according to the public bits
    IEQUALIFIER LALT $10, RALT $20, LCOMMAND $40 and RCOMMAND $80. The conversion to characters (kbd_cook) still only uses
    Shift, Caps and Ctrl.
  - **intuition**: when no text gadget is active and the active window has requested RAWKEY, the key is
    reserved for it:
    - the event is neutralised for the console;
    - the key goes through the input ring, releases included;
    - it is sent as a RAWKEY IntuiMessage, with the raw code and the qualifier (`wn_sendkey`).
  - AutoRequest therefore responds to Amiga-V and Amiga-B. Proven by DiskCopy: Amiga-V is equivalent to Continue, as on the
    real 1.3.
  - **Harness**: the `keyraw:` token sends a key without releasing the held modifiers. `xdotool key
    --clearmodifiers` released Super before the V.
  (17) **Window frame like intuition 34.3** (spec intuition-frame-v34, clean-room reviewed: geometry only,
  no bitmap transcribed).
  - **graphics RectFill + SetAfPt**: a non-null `rp_AreaPtrn` makes a patterned fill. The pattern is anchored at
    the layer's origin (line y modulo 2^AreaPtSz, bit 15 = x ≡ 0 modulo 16); bits at 1 go to pen A, bits at 0 to
    pen B in JAM2 (left as is otherwise).
  - **wn_border**, in the spec's order:
    1. left, right and bottom borders cleared in pen 0;
    2. outline in BlockPen: uprights of BorderLeft/2 pixels at both edges, top and bottom lines. The right
       border of a resizable window therefore looks thin, as on 1.3;
    3. title bar background down to BorderTop − 2;
    4. title at the start of the title area (30 after the close gadget in hires);
    5. with WINDOWDRAG, drag pattern (double lines in DetailPen) from the end of the title + 3 to the end of the area − 3;
    6. application gadgets;
    7. system gadgets **on top** (at the head of the list in 1.3);
    8. on an inactive window, a veil of one pixel in four in BlockPen.
  - **Activation** (`it_setactive`, the only point of change): the old window receives the veil, the bar of the
    new one is redrawn.
  - **System pictograms** (close, depth back and front, size; hires and lores): redrawn from their
    geometric description, as lists of rectangles. Their positions and the click zones come from a table per
    resolution (`wn_geo` / `sc_geo`), shared by the screen bar.
  - When RefreshGadgets starts from the head of the list, and when repairing the interior of a GZZ window, the system
    gadgets are redrawn last. Without this, Info's filler covered the size gadget.
  - Compared with the real 1.3: title bar (pattern, veil, pictograms) of the disk drawer and of the Info window;
    activation by click; close and depth-to-back on a drawer.
  - **Click on a system gadget** (close, depth):
    - on press, its box is inverted (GADGHCOMP); `IB_SYSACT` and `IB_SYSWIN` remember the gadget and its window;
    - on release, the box returns to its normal look, and the action (CLOSEWINDOW, WindowToBack, WindowToFront) only happens
      if the pointer is still on this gadget;
    - closing the window in the meantime forgets the press (`gad_forget`).
  - **Info's WindowToBack**: nothing changes on screen, exactly as on the real 1.3 (probed). The revealed drawer
    is SIMPLE_REFRESH, and only the Workbench redraws it; it is blocked in info.library as long as Info is open.
  (18) **Proportional gadgets, drawer scroll bars, extensible LoadSeg** (specs intuition-prop-v34 and
  workbench-task-v34 §8, clean-room reviewed: behaviour and geometry only).
  - **intuition (gadgets.s)**: PROPGADGET (type 3) with PropInfo (Flags, HPot/VPot, HBody/VBody, CWidth/CHeight,
    HPotRes/VPotRes, LBorder/TBorder).
    - AUTOKNOB, FREEHORIZ, FREEVERT, PROPBORDERLESS, KNOBHIT.
    - Knob geometry in the inner area (`prop_prep`, `prop_knob`), drawing (`prop_render`).
    - Click outside the knob: move by one page. Click on the knob: live-tracked dragging (`prop_track`, called
      from movement tracking), FOLLOWMOUSE relayed.
    - `ModifyProp` (−156) and `NewModifyProp` (−468). `gad_propinit` at OpenWindow and AddGList.
  - **workbench.task**: each drawer has 6 gadgets (horizontal and vertical bar, four arrows, images in CHIP)
    and a scroll origin (DR_SX/SY).
    - The extent of the contents (`wb_content`) sets Body and Pot (`wb_bars`); arrows and knob scroll (`wb_scrollto`).
    - The origin is applied to drawing, to clicks and to icon drops, and saved on snapshot (dd_CurrentX/Y).
    - Drawer of a disk: fill gauge (Info → InfoData, `wb_gauge`), as on the real 1.3.
    - Compared with the real ROM: icon positions, gauge and bars identical; scrolling 49 px per arrow.
  - **dos LoadSeg**: extensible read buffer (32 KB, doubled as needed). A file of more than 32 KB (Preferences,
    56,180 bytes) was truncated and crashed.
  - **Remaining differences**:
    - the held knob is invisible (our DetailPen is 2);
    - a partially visible icon was not drawn: fixed in (29) (DamageList + BeginUpdate, not InstallClipRegion);
    - the arrows did not repeat (INTUITICKS absent): fixed in (28).
  (19) **Preferences: SetPrefs, loading of devs:system-configuration, PointerTicks** (spec intuition-prefs-v34,
  clean-room reviewed; Preferences 34.66 is displayed and shows the same values as the real 1.3).
  - **graphics SetFont** no longer touches D0: Preferences tests on return the D0 left by its OpenFont (silent
    exit otherwise). **SetRGB4** (−288): ColorTable, MOVE of the ViewPort's fragment and of the master list.
  - **intuition (prefs.s)**: current 232-byte copy in IntuitionBase.
    - GetPrefs (−132) copies it; GetDefPrefs (−126) copies the default values and the pointer image; bounded
      signed copy, ViewInitX/Y replaced by the view offsets.
    - SetPrefs (−324): copy, ext_size at 0, then default font (topaz 8 or 9 according to FontHeight), font of
      the WB screen, view offset, colours 0-3 and 17-19 of the WB screen (SetRGB4), pointer image and offset;
      `inform`: NEWPREFS to each window that requested it.
    - Read on the fly: DoubleClick (Preferences delay), PointerTicks, XOffset/YOffset, WB colours at OpenScreen.
  - **Pointer**: one mouse count is worth one hires pixel (half a line in Y) divided by PointerTicks, as on
    1.3 (measured on the real ROM); our positions being lores, each delta is divided by 2 × PointerTicks with the remainder
    carried over. The pointer previously moved twice too fast.
  - **dos (initial CLI)**: after the assigns, `devs:system-configuration` (exactly 232 bytes) goes to
    SetPrefs(…, 232, TRUE). Intended differences: colours 0 to 3 remain those of the project theme; the
    ext_size extension is ignored (V34 intuition caps at 232).
  - Default values from the spec, except colours (theme), pointer colours and offset (our image).
  - Preferences' centring frame (PROPGADGET without AUTOKNOB, background in the window's DetailPen, inherited from the screen)
    is black on our side instead of colour 0: consequence of the theme (DetailPen 2 on the WB screen), not a rendering bug.
  - **Not done**: RemakeDisplay (the view offset has no visible effect), rows/columns adjustment,
    passing of KeyRptDelay/Speed to input.device (no key repeat on our side).
  (20) **Caesar loads from the floppy** (spec caesar-boot, clean-room reviewed; path identical to the real
  1.3: FAIRLIGHT intro, click, `play caesar`, language choice, title screen, game menu).
  - **graphics, 1.3 copper scheme**: COP1LC points to a copinit (wait for line 12, MOVE COPJMP2); LoadView
    and a VBlank server (pri 10) write COP2LC with the list of the displayed view. A program that writes COP2LC
    with interrupts off (Caesar's FLT intro) has its list displayed until it re-enables them.
  - **intuition RemakeDisplay / RethinkDisplay** (−384/−390): copper list rebuilt from the front screen.
    `caesar.boot` switches the active screen to 1 plane (Depth := 1, FreeRaster of plane 2) then calls RemakeDisplay; without
    it, the copper displayed the freed plane (stray pixels).
  - **streaming dos LoadSeg** (`ls_load_stream`): 2 KB read buffer refilled by Read, large hunks read
    directly in place, IoErr 103 (memory) or 121 (format). The shell loads its commands with LoadSeg instead
    of reading the whole file. `csr.exe` (126 KB packed, 657 KB of hunks) did not fit with a whole-file
    buffer and exited with "Error code 121".
  - After `caesar.boot`, the WB screen has only one plane: the theme's pen 2 merged with the background (invisible text,
    "blind" typing). The console now takes the colour next to the background when text and background fall on the
    same colour once reduced to the planes of the BitMap (white on green).
  (21) **exec/dos compatibility with the intros and games of the ADF suite** (spec cracktros-exit, loadwb-13; black-box
  probes `tests/memmap.s` and `tests/reslist.s` on the real ROM). Scooby-Doo gets to the title screen, Monkey Island and
  SimCity return to the Workbench after their intro, as on the real 1.3.
  - **ExecBase in LibList** (first library, before expansion then graphics): some programs find
    GfxBase there through `ExecBase->ln_Succ->ln_Succ` to restore the copinit.
  - **Public IntVects** at ExecBase+$54 (16 × {iv_Data, iv_Code, iv_Node}); SetIntVector returns the old Interrupt; the
    server lists stay in a private block (EB_INTSVL). graphics installs `bltsrv` (GfxBase+$76) through
    SetIntVector(INTB_BLIT) with is_Data = GfxBase and its VBlank server in `vbsrv` (+$4A): some intros read
    `IntVects[INTB_BLIT].iv_Data` to find GfxBase.
  - **ExecBase, jump table and supervisor stack in low chip**: table $1000-$1276, ExecBase $1276, region of the
    multi-header test $1500-$2500 (margin below the stack afterwards), supervisor stack $2500-$3500, heap $3500-$80000. The top of
    chip stays free as on the real 1.3 (intros: routine at $7F000, stack at $7FFFE, planes at $70000+).
  - **No TRAP vector used by exec**: Wait/yield/RemTask(self)/Supervisor enter supervisor mode through a
    privilege violation at a known site in the ROM (EXEC_SVC macro: `ori.w #0,sr`, magic word, address of the
    service; handler at vector $20). Programs often install their code at the TRAP #0 vector to switch
    to supervisor; TRAP #0-#15 now all go to the task's tc_TrapCode.
  - **Initial Resident list**: system "CLI" node (usage -1, seglist = ROM CLI). EndCLI decrements there the counter
    of the "CLI" node it looks for; without it, it decremented address 4 (ExecBase pointer) and everything collapsed
    (end of startup "endcli" without a prior `resident CLI`). The real ROM has FileHandler, Restart and CLI; we do not
    have BCPL seglists for the first two.
  - The exception handler restores SERPER before writing "SOFTWARE FAILURE" (a program may have changed the
    port speed).
  (22) **SimCity and Monkey Island launched from the CLI** (spec monkey-startup; dos trace `-DDOSTRACE=1`). SimCity
  reaches its menu, Monkey Island its title screen ("Appuyez sur ENTER", credits).
  - **console.device**: OpenDevice on unit -1 (CONU_LIBRARY, without a window) and **RawKeyConvert** (−48): character through
    kbd_cook, CSI sequences for the arrows, F1-F10 and Help (Shift variants), 0 on a release, -1 if the buffer is
    too short.
  - **graphics**: LoadRGB4 (−192); user copper lists **UCopperListInit** (−594), **CMove**, **CWait**, **CBump**
    (−372/−378/−366); MakeVPort copies `vp_UCopIns` at the end of the fragment (WAIT brought back to the real line, crossing of
    line 255, CEND), FreeVPortCopLists frees them. Monkey places a COP1LC/COPJMP1 jump there to its own lists.
    **Blitter DMA active from init**: a program that saves then restores DMACON (defjam intro) otherwise turned it off
    for good, and the game's first WaitBlit never returned.
  - **OFS**: direct Seek through the block tables of the header and of the extension blocks (block pos/488), instead of
    following the chain of data blocks.
  - Remaining: Monkey's music player takes vector $78 (level 6) without chaining; our MICROHZ is on
    CIA-B (level 6), the real timer.device on CIA-A. The keyboard feeder and the console handler wait on MICROHZ.
  (23) **Keyboard under WinUAE** (reported by the user; spec keyboard-handshake-v34 for reference). The indexes
  of the feeder's buffer (KBD_FHEAD/KBD_FTAIL) were never initialised: FS-UAE zeroes RAM at power-on,
  WinUAE (like a real machine) does not; an odd index caused an address error in the keyboard interrupt at the
  first key press, which stayed stuck at level 2 (no more handshake, no more keys at all, mouse intact). The
  coldstart now zeroes the whole low-RAM variable area ($500-$800). Diagnosed under WinUAE Linux
  (Xvfb, `SDL_VIDEO_X11_XINPUT2=0 QT_XCB_NO_XI2=1`, window focus) with colour milestones (COLOR00 of the
  displayed copper list) in the interrupt, for lack of serial and debugger.
  (24) **PrintIText/DrawBorder leave the RastPort intact; ClearEOL/ClearScreen** (reported by the user: SysInfo's
  MEMORY page unreadable after NEXT/PREV). SysInfo erases its values by writing spaces, relying on
  the pen and JAM2 mode set once and for all in its window's RastPort; the rendering of the clicked gadget
  (internal PrintIText) left pen 1 / JAM1 there -> invisible spaces, overlapping values. Black-box probe
  `tests/itextstate.s`: on the real 1.3, PrintIText and DrawBorder leave pen A, pen B and mode intact;
  ours now save and restore them. graphics: `ClearEOL` (−42: from cp_x to the right edge, over the
  height of the font aligned on the baseline) and `ClearScreen` (−48: same then everything below), colour =
  pen B in JAM2, 0 otherwise; pixels identical to the real ROM (probe `tests/cleareol.s`).
  (25) **SCREENQUIET screen: never a title bar**. SysInfo opens its screen as CUSTOMSCREEN | SCREENBEHIND |
  SCREENQUIET (trace of the OpenScreen/OpenWindow calls: Type $118F; BORDERLESS non-BACKDROP window; ShowTitle
  never called). OpenScreen did not create a bar layer, but activating a window (`wn_scrtitle`) called
  `sc_drawbar`, which fell back on the RastPort of the whole screen: black bar drawn over the window at the
  first click. `sc_drawbar` no longer does anything without a bar layer (like the real 1.3, which displays no bar).
  End-of-step ADF suite now under **WinUAE Linux** (`tests/adf_suite_winuae.sh`, serial through
  `unix.serial_port`) instead of Amiberry.
  (26) **Zorro II autoconfig** (`src/exec/expansion.s`, spec `docs/analysis/autoconfig-v34.md` produced by a separate
  analysis agent, reviewed for no transcribed code). ExpansionBase with the V34 layout ($1C8: eb_BoardList $3C, eb_MountList
  $4A, table of 256 slots of 64 KB $58, binding semaphore $158). The resident's init (pri 110, after the slow RAM)
  frees the memory space $200000-$9FFFFF and the I/O space $E90000-$EFFFFF, then ConfigChain($E80000): reading of
  each board's ROM (17 bytes, type not inverted, validation + 11 re-reads), first-fit slots (I/O
  first below 8 slots; 4 MB at $200000 then $600000), address written to register $48 (high nibble last),
  RAM added by AddMemList(MEMF_FAST|MEMF_PUBLIC, pri 0, "expansion ram"), DiagArea copied (nibble /
  byte / word width) and DiagPoint called (A0 board, A2 copy, A3 ConfigDev, A5 ExpansionBase, A6 ExecBase); without room:
  sleep (CDF_SHUTUP); NOSHUTUP board without room: chain blocked, without post-configuration (deliberate difference: the
  1.3 would do it at address -1). The 25 LVOs are implemented (Read/WriteExpansionByte, ReadExpansionRom,
  ConfigBoard/Chain, Alloc/FreeExpansionMem, Alloc/FreeBoardMem, RemConfigDev, bindings, MakeDosNode, AddDosNode:
  DOS list if dos.library is there, otherwise BootNode in eb_MountList). exec: chip at pri -10, MemHeaders named
  "Fast Memory" (slow RAM) and "Chip Memory" as in 1.3. The spec's vectors reproduced (probe
  `tests/cfgdev.s`, FS-UAE): 64K/$E9, 256K/$EC, 2 MB, 8 MB (with and without slow RAM), 1 MB + 4 MB ($600000), 8 MB
  + 1 MB (sleep, $FF000000). UAE disk board: configured at $E90000, DiagArea copied and executed, but no
  ConfigDev at $F00000 nor DH0: (to be investigated: scan of residents outside the ROM / BootPoint). Slow RAM and
  chip bounds different from 1.3 (our exec's own layout, outside autoconfig).
  (27) **timer.device: MICROHZ on CIA-A timer B** (spec `docs/analysis/timer-v34.md`, analysis agent, reviewed;
  ROM addresses removed). The init takes bit 1 of ciaa.resource (AddICRVector): MICROHZ is served at level 2,
  like 1.3. No CIA-B timer is programmed in production any more: a game that hijacks $78 without chaining (Monkey
  Island's music) no longer breaks delays (probe `tests/timerprobe.s`, test HJ6: MICROHZ 0.5 s intact). The dev ROM
  keeps a level-6 proof source (CIA-B timer A, m7_int6_probe) for M7d/M7e. Additions: AddTime / SubTime /
  CmpTime (LVO -42/-48/-54, exact 1.3 semantics), AbortIO returns -1 when not queued, Open sets io_Unit (0/1) and refuses
  unit >= 2 (IOERR_OPENFAIL; before, a VBLANK open fell into MICROHZ), Close resets io_Device/io_Unit to -1,
  VBLANK completed at the k-th VBLANK (k = max(1, ⌈T/20 ms⌉)), strictly increasing time (+1 µs per read within a
  frame, reset by SETSYSTIME). Interrupt fixes found along the way: INTREQ PORTS/EXTER acknowledged
  BEFORE the chain (otherwise a CIA event occurring during servicing was cleared); fallback on VBLANK when the one-shot
  has finished without an interrupt being served (FS-UAE loses the ICR event when its 10-slot "event2" queue overflows:
  the CIA-A IR bit stayed raised and no level-2 interrupt — keyboard included — arrived any more).
  MICROHZ accuracy (measured on 2026-10-26, tests/timerprobe.s, prod ROM, in 64 µs lines): the ~5% deviation under
  load came from the keyboard feeder's ~110 services/s; since (28) the feeder waits on VBLANK. {1,0} = 15,733 lines
  (1.0069 s; real 1.3: 15,820, 1.0125 s, nominal countdown and NTSC constant), {0,100000} = 1,591 (identical to
  1.3), {0,250000} = 3,946-3,951 (1.3: 3,959), even with a `list sys: all` in the background. There remains a fixed overhead
  per request of about 8 lines more than 1.3 (0 µs request: 20 lines against 12). ExecBase's Quantum/Elapsed
  not set.
  (28) **Key repeat and INTUITICKS** (spec `docs/analysis/intuiticks-repeat-v34.md`, analysis agent, reviewed;
  probe `tests/ticks.s`). The feeder (`src/dos/feeder.s`) plays the role of the 1.3 input.device task: it waits one
  frame on VBLANK (no more MICROHZ every 10 ms), sends an IECLASS_TIMER every 5 frames and repeats the
  last key pressed with code < $60 (copy of the event + IEQUALIFIER_REPEAT $0200), first after the delay
  then at input.device's period. Stop: pressing a qualifier (>= $60), releasing the repeated key,
  or qualifier changed ((repeated & $05FF) != (current & $07FF)). Events are timestamped (TR_GETSYSTIME).
  input.device: IND_SETTHRESH / IND_SETPERIOD (12/13, timeval of the request; defaults 0.8 s / 0.1 s); Preferences
  (`pf_keyrpt`) sends KeyRptDelay / KeyRptSpeed there. `kbd_interrupt` now passes ALL events to the feeder
  (releases and qualifiers included); the repeat also drops its character into the cooked ring of the screen
  CLI (`kbd_pushcooked`, under Disable). Intuition: IECLASS_TIMER -> input task -> INTUITICKS to the active window
  only if it requested it and if its previous INTUITICKS has been returned (only one in circulation);
  **ModifyIDCMP** (-150) implemented. Workbench: scroll arrow held without Shift -> INTUITICKS added to the IDCMP,
  one step per INTUITICKS or MOUSEMOVE as long as the arrow is SELECTED, removed at GADGETUP. Proven: "a" held 2 s
  -> ~50 "a", Shift+b -> "BBB…"; a drawer's left arrow held 3 s -> continuous scrolling, stops on release.
  (29) **InstallClipRegion and clipping of WB icons** (specs `docs/analysis/installclipregion-v34.md` and
  `wb-icon-clipping-v34.md`, analysis agents, reviewed; probe `tests/clipreg.s`). layers.library: **InstallClipRegion**
  (-174, `ly_ClipRegion` +$7E); `lr_clip` replaces the normal list (kept in `_cliprects`) by its ClipRects ∩ C,
  C = ClipRegion, or DamageList (∩ ClipRegion) during BeginUpdate; the hidden parts with a save take the original
  BitMap again (borrowed: drawing into it writes the save, nothing to copy back on removal); empty region -> no
  ClipRect; insufficient memory -> LAYER_CLIPRECTS_LOST. `lr_unclip` undoes it. BeginUpdate/EndUpdate go through these
  two routines (EndUpdate puts back the list reduced to the region); LockLayers undoes the reduced lists at the first level
  (`LayerInfo+$5B`), UnlockLayers rebuilds them at the last: layer operations see the normal lists and the
  region follows the layer. Probe T0-T6: same ClipRects and pixels as the real 1.3 (order of the ClipRects not normative).
  intuition: `it_unclip`/`it_reclip` (layer lock + region removed at the first level, counter per window) around
  the frame, the title bar, system and application gadgets, knobs and text gadgets. Workbench (spec
  §1-§6): no more "whole icon" test; each drawing goes through `wb_updopen`/`wb_updclose` (DamageList replaced by
  the contents rectangle, real damage kept in Window->UserData, BeginUpdate; mode 0 = damage ∩ contents for
  REFRESHWINDOW, only if LAYERREFRESH): an icon straddling the edge is drawn entirely and clipped cleanly, name
  included; only an icon more than 4 × the screen size away is skipped; the click is only taken in the contents. The
  gauge of a disk is drawn outside the update. Difference: icon drawing order = array order (1.3 goes from
  the tail to the head of its list).
  (30) **Requesters** (spec `docs/analysis/intuition-requesters-v34.md`, reviewed; probe `tests/reqtest.s`).
  `src/intuition/request.s`: **Request** (-240: LAYERSMART layer at the LeftEdge/TopEdge corner, interior of a GZZ
  window, clipped to the window, in front of the previous requester otherwise in front of the window; a single layer operation
  when this layer is already frontmost; BackFill background, ReqBorder, ReqText, gadgets in reverse order, ImageBMap if
  PREDRAWN; REQGADGET set; chain, ReqCount, INREQUEST; REQSET), **EndRequest** (-120: removal even when not at the head,
  DeleteLayer, REQCLEAR and INREQUEST cleared at the last one, window repaired), **InitRequester** (-138), **SetDMRequest** /
  **ClearDMRequest** (-258/-48, refused if the DMRequest is displayed). gadgets.s: a requester gadget has the
  requester as its domain and is drawn in its layer (`gad_reqof`, `rq_origin`); during a requester the window's gadgets
  are inert, only those of the most recent one respond (click on its layer); an **ENDGADGET** released on it
  ends it (REQCLEAR every time). screens.s: without NOISYREQ, RAWKEY / MOUSEBUTTONS / MOUSEMOVE / INTUITICKS /
  MENUPICK are swallowed (`wn_post`) and the menus do not open; closing is refused; the layers of the
  requesters follow MoveWindow and depth changes; CloseWindow removes the remaining requesters.
  sysreq.s: **BuildSysRequest** (-360: "System Request" window + NOISYREQ requester, memory in a Remember list
  in Window->UserData), **FreeSysRequest** (-372), **AutoRequest** built on top (ScreenToFront of its screen).
  **ScreenToFront / ScreenToBack** (-252/-246): head / tail of the screen list, the front screen is displayed.
  Probe: Request ×2, EndRequest not at the head, ENDGADGET, AutoRequest (Amiga-V / Amiga-B, AvailMem identical before /
  after), screens: all conforming; DiskCopy displays its prompt and Cancel ends it. Differences: no DisplayAlert fallback
  (FALSE), SizeWindow does not clip a requester's layer, the gadgets of a PREDRAWN requester are drawn right
  away.
  (31) **Boot on the UAE disk board (DH0:)** (specs `docs/analysis/uae-hd-boot-v34.md` and `uae-int2-v34.md`, analysis
  agents, reviewed). `src/exec/romboot.s`: **romboot.library** (COLDSTART pri -40); at its init, for each CONFIGME
  ConfigDev with a copied DiagArea (valid Diag, CONFIGTIME), the first ROMTag of the copy is initialised (InitResident)
  under ObtainConfigBinding / SetCurrentBinding (under UAE: uaehf.device, which mounts DH0 and enqueues its BootNode
  NT_BOOTNODE in eb_MountList); **RomBoot** (-30) calls the BootPoint of each bootable BootNode (A0 = address,
  A1 = ConfigDev, also at 4(sp), A6 = ExecBase; null BootPoint ignored). strap: bootable DF0: -> DF0: BootNode of
  priority 5 enqueued (`dos_df0bootnode`); otherwise RomBoot once before the insert-disk screen. **dos.library**: its
  ROMTag now has an rt_Init in code (no longer AUTOINIT): on the first call (InitCode) it builds the library, on the
  following ones (UAE BootPoint, which does FindResident then calls rt_Init) it jumps to `boot_dos_start` (rest of the startup,
  no return). `dos_mountlist`: the head of eb_MountList is removed and its DeviceNode becomes the boot
  device (DL_BOOTDEV); the DeviceNodes of the BootNodes are added at the end of di_DevInfo. `dos_boot_assigns`: SYS:,
  C:, S:, L:, DEVS:, LIBS:, FONTS: and the current directory on this device; volume node of the DF0: floppy
  created in all cases (our handler does not do it). M7B proof: CIA-A timer A in one-shot (running continuously at
  360 µs, it saturated level 2 as soon as the UAE DiagPoint added its PORTS server; the real 1.3 never arms it
  at boot). Proven (prod ROM, FS-UAE `hard_drive_0`): blank floppy -> DH0 boot, SYS: = hddir:; bootable
  Workbench + DH0 pri 0 -> Workbench on the floppy, DH0 mounted; DH0 pri 5 -> bootblock executed then SYS: = hddir:.
  Differences: exec does not sweep $F00000-$F7FFFF nor the cartridge $1111 jump; dos exists before romboot (1.3 only
  creates it at startup); DF0 does not appear twice (1.3 artefact with a higher-priority board); the Workbench
  only displays the boot disk's icon.
  (32) **trackdisk: end of DMA by interrupt** (`td_dmawait`): with multitasking running, reading and writing
  a track unmask DSKBLK (level 1 exclusive vector, `td_dskblk_int`) and the task waits for SIGF_SINGLE; the
  trackdisk VBlank server wakes it after 1 s without end of DMA (no disk). Before, the DF0: handler (pri 6)
  polled INTREQR during each revolution: no lower-priority task (CLI, applications) got the
  processor as long as the disk was working. At boot (strap): polling unchanged. "Hang" of two
  `list sys: all`: in fact tests/timerprobe.s expected an exact equality of its frame counter, missed as soon as
  the CLI lost the processor for more than one frame; its expectations are now "at least".
  (33) **Full volume** (spec `docs/analysis/disk-full-write-v34.md`, analysis agent, reviewed; probe `tests/diskfull.s`).
  "Intermittent" failure of `join`: 25 joins of 27.5 KB on a free disk are byte-exact; on an almost
  full disk, the file was truncated without displaying anything (only reproduction found; nothing proves that the original
  failure had this cause). The real 1.3 does no better on Join's side (it does not check its writes, returns 0) but dos opens, on each
  Write that fails for lack of space, the "Volume / <name> / is full" requester (Retry / Cancel) and blocks until the
  answer. `dos_rawwrite`: Res1 = -1 and IoErr 221 -> `dos_fullreq` (volume = DLT_VOLUME node of the same handler; fallback
  "?"); Retry resends the packet, Cancel returns -1 (IoErr 221 kept). The system requester is shared with "Please
  insert volume" (`vr_req`). Deferred writes of the BCPL runtime (`dos_bufwrite`): a failing flush makes the
  current write return -1 (before, the failure was swallowed). Proven (ADF jw, 5 × join a b a on an almost full WB):
  three requesters cancelled with the keyboard (Amiga-B), then J5 and FIN as on 1.3; j1-j4 byte-identical,
  j5 = exact beginning (26,352 bytes; 26,344 on 1.3, end-of-block artefact not reproduced).
  Other intermittent failures noted earlier, re-measured on 2026-10-26: dev ROM hang at boot with SysInfo
  (0 out of 20 boots) and DiskCopy's LoadSeg returning 121 (0 out of 18 launches through Duplicate): not reproduced.
- **STEP 10 — PERFORMANCE (CPU, CONSOLE)**: (1) **timer.device MICROHZ in one-shot mode**: CIA-B timer A ran
  continuously (latch 255, ~2,780 INT6/s) even without a request, which cost more than half of the CPU (measurement: `copy ram:x to *`
  9.9 s -> 4.8 s just by slowing this timer down). Now each request keeps its remainder in (seconds, E ticks at
  709,379 Hz); `tm_account` reads the counter (time elapsed since arming), counts down and replies to the expired requests,
  `tm_rearm` arms the one-shot on the nearest deadline (at most `TIMER_CAP` = $FFFF ≈ 92 ms). Called with INT6
  masked from BeginIO (accounting BEFORE adding the new request) and from the ICR vector. Empty queue: timer
  stopped in production; re-armed every `TIMER_IDLE` = 255 ticks in dev (M7a/M7d/M7e proofs). Arming wide matters:
  a cap of 255 made M7L drift by more than 12% (underflow -> re-arm latency not counted). (2) **Buffered BCPL console
  output** (V34 wrch rule): `dos_bufwrite` also buffers interactive FileHandles and flushes them as soon as
  an LF, CR, FF or NUL is written; `rdch` flushes the current output before reading the input again (prompt without a
  newline); the shell's initial console is allocated as a dos FileHandle (`DOS_FH_ALLOC`) to benefit from it.
  Before: one ACTION_WRITE packet per character (~35 ms each). (3) **Text**: fast path generalised (any abscissa,
  glyph shifted over two masked bytes; JAM1 and JAM2). Production ROM measurements (WB disk, without FastFonts):
  `copy ram:x to *` 27 s -> 4.6 s; `type ram:x` (1.4 KB) 68 s -> 9.3 s. SysInfo: 552 Dhrystones, 1.04 × A600 (169
  before) — the "3× below an A500" came from the continuous timer. **ScrollRaster**: middle of the line copied by longs when
  source and destination have the same parity; fast path when one visible ClipRect contains the whole rectangle
  (uncovered window: no more walking of the ClipRects on every line) -> `type` 9.3 -> 6.9 s. One scroll
  of the console still costs ~5 frames (CPU copy): the blitter remains the real solution.
  (4) **Command failures faithful to 1.3** (`sh_report`, shell.s), behaviours recorded by a black-box probe
  on the real KS 1.3 (test startup-sequence, screenshots): command not found -> "Unknown command
  <name>"; file that cannot be loaded (LoadSeg refuses, e.g. V39 hunk $3FD) -> "Unable to load <name>: Error code 121"
  (ERROR_FILE_NOT_OBJECT; "Error code" for lack of C:Fault); in both cases a non-interactive script is
  abandoned without any other message. Return code >= cli_FailLevel in non-interactive mode -> "<name> failed returncode <n>" then
  abandon. Applied to the startup-sequence, to Execute scripts and to the ROM CLI. Remaining difference: the commands' error
  messages ("Error code 205" instead of "object not found": 1.3 gets the text through C:Fault).
- **STEP 10 (CONTINUED) — DATES, DISCARD, FASTFONTS**: (1) **system time**: `timer_now`/`timer_setnow` (timer.s),
  real `DateStamp` (dos_now: days/minutes/ticks since 1-1-1978, copy in the RootNode's rn_Time); BCPL globals
  **128 setdatstamp** (TR_SETSYSTIME) and **126 compstamp** (spec bcpl-runtime-v34.md §8.4): `C:Date` sets and reads
  the time. (2) **OFS dates** (`ow_stamp`/`ow_touch`): header dated at creation and when closing a written file,
  parent directory when adding / deleting an entry, root: modification + last alteration of the disk.
  (3) **AutoRequest** (`src/intuition/sysreq.s`, LVO -348): "System Request" window, PrintIText body, positive /
  negative gadgets sized to their text, answer by GADGETUP or IDCMP flags. (4) **Workbench Discard**:
  confirmation, recursive deletion of a drawer (`wb_rmtree`) and of the ".info", drawer re-read (`wb_reload`). Proven
  with the mouse on a copy of the WB disk (Empty drawer) and read back by xdftool. (5) **BltTemplate** (graphics -36):
  one-plane template with the current pens and mode, clipped by the ClipRects — FastFonts (the WB startup's C:FF) draws
  all its text through it: with a real SetFunction, the WB's text was invisible (spec `docs/analysis/fastfonts-ff.md`).
  LockLayerRom/UnlockLayerRom ignore a null layer. Finding: `list df0:` ~1 min for 26 entries (slowness, not a
  hang) — to be measured with the production ROM.
- **APPLICATION GADGETS (intuition)** (`src/intuition/gadgets.s`): the `wd_FirstGadget` list (taken over from
  `nw_FirstGadget`) is drawn with the window frame (Border through DrawBorder or Image, IntuiText, GADGHCOMP/GADGHBOX
  highlighting by inversion, SelectRender in GADGHIMAGE); GRELRIGHT/GRELBOTTOM/GRELWIDTH/GRELHEIGHT
  positions/sizes. Left button on an active gadget (neither SYSGADGET nor GADGDISABLED): selection (toggle in TOGGLESELECT),
  GADGETDOWN if GADGIMMEDIATE; release: deselection, GADGETUP if RELVERIFY and the pointer is still over it;
  `im_IAddress` = the gadget (`wn_sendgad`); no MOUSEBUTTONS for a click taken by a gadget. LVOs: AddGadget,
  AddGList, RemoveGadget, RemoveGList, RefreshGadgets, RefreshGList, OnGadget, OffGadget, DrawBorder. Limits: all
  handled as buttons (no PROP/STRGADGET), no ghost pattern for a disabled gadget, highlighting not tracked
  while dragging. Proof: click on SysInfo's SPEED → speed test run (prod ROM: 68000 7.09 MHz,
  169 Dhrystones, Chip 0.32 × A600 — performance gap to be studied).
  Analysis specs: `docs/analysis/setpatch-138.md`, `docs/analysis/sysinfo-44.md`. Bench: `tests/adf_suite.sh`
  (boot of each ADF of `assets/test_adf/`, writable copies, summary + captures).
- **STEP 10 (IN PROGRESS) — FLOPPY WRITING**: (1) **trackdisk**: CMD_WRITE into the track cache (partially
  covered track read first), TD_FORMAT, CMD_UPDATE/CLEAR, TD_MOTOR/PROTSTATUS/CHANGENUM/CHANGESTATE/
  GETNUMTRACKS; AmigaDOS MFM encoding (gap 700 bytes + 11 sectors of 1088 bytes, header/data odd then even, XOR
  sums, clock bits); write DMA with precompensation from cylinder 40 on; refusal if /WPRO. (2) **OFS
  writing** (`src/dos/ofswrite.s`): single context (`DOS_OWCTX`), bitmap kept in memory (refusal if bm_flag invalid),
  allocation starting from the root, file/directory creation (hash chain, replacement of an existing
  file), deletion (empty directory required), renaming/moving (return to the origin if the destination fails),
  protection, comment, disk information; write stream per handle (data blocks type 8, tables filled
  from the end, T_LIST extensions beyond 72 blocks). (3) **DF0: handler**: FINDOUTPUT/FINDUPDATE, WRITE, END
  of a write state, DELETE_OBJECT, RENAME_OBJECT, CREATE_DIR, SET_PROTECT, SET_COMMENT, INFO/DISK_INFO.
  (4) **dos**: DupLock, Info, SetComment, SetProtection. Proven under FS-UAE (`writable_floppy_images`) and read back on
  the host by `xdftool`: makedir, `echo >fichier`, copy (byte-identical), join (file > 72 blocks), rename,
  protect, filenote, delete. **Open**: an intermittent failure of `join` to DF0: (1 time, then 23/23 successful;
  symptom consistent with a trackdisk write refused in the middle of a packet), `list` blocked on a written directory
  (DateStamp always returns 0), header dates not set.
- **STEP 9 (CONTINUED) — CLI, CONSOLES, ICONS**: (1) **ROM CLI** (`src/dos/shell.s`, `rcli_*`): segment in BCPL format (global 1 = `start(pkt)`) set as `rn_ConsoleSegment` and as entry 4 of the initial CLI's segarray; contract §13.6/§13.7 of the analysis: cleared CLI with its 4 buffers (including cli_CommandFile) stored in pr_CLI, BCPL call of the packet's init with **A0 = 0**, `r > 0` called with pr_Result2, cli_Interactive computed (recomputed at the end of a script), remembered output reselected at each round, prompt `%N`, character-by-character reading of cli_CurrentInput (BCPL buffer then Read), end of a background CLI according to r (Run: closing of the streams; Execute: bits 0/1 then returnpkt), freeing of cli_CommandDir, of the current directory and of the slot. Run, Execute() and NewCLI work without a "CLI" resident. (2) **Initial shell**: redirections `<nom` / `>nom` (arguments injected into the redirected input, "Can't open"), Execute scripts (`sh_runscript`: cli_CurrentInput followed to its end, temporary file deleted), pr_ConsoleTask = initial console (`*` output of the background CLIs), Forbid around commands reserved for the dev ROM. (3) **DOS nodes** CON, RAW (ROM handler `src/dos/conwin.s`, one process and one window per Open, line editing in CON, raw in RAW, asynchronous console reading, READ/WRITE/END/WAIT_CHAR/SCREEN_MODE/DISK_INFO), SER, PAR, PRT (the disk's `L:PORT-HANDLER`), shared GV of the initial CLI. (4) **console.device**: list of open units, keys served to the unit of the active window (otherwise head of the queue); the initial console only takes the keyboard ring if its window is active. (5) **intuition**: ReportMouse, MOUSEMOVE (a pending message is updated, not duplicated), SELECTUP sent to the active window. (6) **Workbench**: draggable icons (XOR ghost frame, position updated in memory, window redrawn). (7) **layers**: a visible ClipRect that stayed in place and is partly uncovered is copied directly from the saves to the screen (closing a drawer ≈ 0.5-1 s in production instead of 1.5-2 s). **Honest scope**: no floppy writing (Rename, Discard, Snapshot impossible), no `>>`, VSprites not displayed, Info not done.
- **WORKBENCH 1.3.3 — STEP 6: WORKBENCH SCREEN AND VISIBLE WINDOWS**: (1) **graphics.library** — CPU drawing primitives in a RastPort (`src/graphics/draw.s`: SetAPen/SetBPen/SetDrMd/Move/Draw (Bresenham)/WritePixel/RectFill/SetRast/Text/TextLength/SetFont/InitRastPort/InitBitMap/vertical ScrollRaster), without layers.library: if `rp_Layer` is set, its bounds give the offset AND the clipping; single 8x8 font (font8x8, hand-authored); fast paths (byte-aligned JAM2 Text: direct writing; RectFill/ScrollRaster: full bytes in a tight loop, only the edges masked); complete V34 vector table (106); generic `MakeVPort` (HIRES 640 window, low resolution 320 or overscan 352x272, height = DHeight, modulo = BytesPerRow − bytes read), reuse of the copper lists (vp_DspIns, v_LOFCprList), `FreeVPortCopLists` (−540). (2) **intuition.library** (`src/intuition/screens.s`) — `OpenScreen`/`CloseScreen` (V34 Screen struct of 346 bytes + private RasInfo/ColorMap/palette extension, chip planes, title bar and depth gadgets drawn, 1.3 preferences palette), `OpenWorkBench` (640x256, 2 planes, HIRES), `GetScreenData` (−426), front screen displayed through `ib_ViewLord`; real `OpenWindow`/`CloseWindow` (window brought back into the screen, borders according to the flags, own RastPort + pseudo-layer at the window bounds, frame/title bar/gadgets drawn, window active; CloseWindow clears its area); table extended to the V34 set (−468); GfxBase kept at init (`IB_GFXBASE`). (3) **console.device** — a unit opened on a window receives a **ConUnit** (devices/conunit.h: cu_Window, cursor, bounds) and renders its text in the window's RastPort: printable runs through Text, automatic line wrap, scrolling through ScrollRaster, BS/TAB/LF/VT/FF/CR, IND/NEL/RI, ESC c, CSI A-F/H/f/J/K/L/M/m/SPACE p (CSI P = clear to end of line, without shifting), orange cursor by complement; `io_Length = -1` (NUL-terminated string). (4) **dos** — `Open("*")` targets `pr_ConsoleTask`; non-zero dp_Res1 = success; **packets aligned on a long** (`dos_sendpkt` and starthandler's startup packet: a BCPL handler receives the packet as a BPTR — on a word-aligned C stack, the packet was truncated by 2 bytes and the reply went off into the weeds); `fl_Volume` of DF0: locks = volume node (`DL_VOLUME`, otherwise CD rebuilt the volume name from address 0). (5) **BCPL** — globals 105 consoletask / 106 filesystemtask; qpkt sets `message.ln_Name := packet`. (6) **workbench.task** opens the Workbench screen (`OpenWorkBench`). Proofs (FS-UAE, copies of the WB 1.3.3 ADF, production ROM): `copy … to newcon:0/0/640/100/Test` displays the "Test" window with StartupII scrolling; `NewShell NEWCON:0/11/640/150/AmigaShell FROM s:Demo` opens the AmigaShell window on the Workbench screen, runs `echo` and `dir c:` (two columns, scrolling), prompt "2.Workbench1.3:c>"; a command typed on the **real emulated keyboard** (xdotool) is displayed in the window and runs. **Honest scope**: no layers.library (no overlapping nor refreshing of windows, no moving/resizing, no IDCMP), no visible mouse pointer, a single font, no Workbench desktop (icons); the fallback serial shell (E2) also reads the keyboard after the end of the initial CLI.
- **TRACKDISK — FLOPPY READING ×5** (`src/exec/trackdisk.s`, `TD_*` constants from `exec.i`): (1) **motor kept on**: a read leaves the DF0 motor on (`TD_MOTORON`); the next one skips the spin-up; a VBlank server (`td_motor_server`, `TD_VBLINT`) turns it off after 2 s of inactivity (`TD_MOTORIDLE`, counter `TD_MOTORCNT`, never during an access: `TD_BUSY`); `td_check_change` preserves the motor state. (2) **seek at the drive's timings**: 3 ms between two steps (`TD_STEPWAIT`), 18 ms of settling after the last one (`TD_SETTLE`), instead of very wide delays. (3) **LRU cache of 8 decoded tracks** (`TD_NCACHE` × 5632 bytes in `MEMF_PUBLIC`, slot per track `TD_CTRK`, age `TD_CAGE`/`TD_CTICK`; fallback to 1 slot if memory is short; flushed on `/CHNG`): replaces the single-track cache — the OFS FAT (root, bitmap, headers, chains) kept coming back to the same tracks. Measurement, complete WB 1.3.3 boot (FS-UAE, real time): SetPatch 78 s → 12 s, end of startup-sequence > 400 s → 87 s; physical reads 222 → 103 (58 distinct tracks; 16 slots: 83 s, marginal gain). Non-regression: complete GREEN with and without slow RAM, AUX:/NEWCON:/PIPE:/handlers, WB boot, Holiday Lemmings up to the menu.
- **Read-only OFS (D1) DONE** (`src/dos/ofs.s` + `ofs.i`): `ofs_read_file` reads a file by name from DF0: (root → hash → header → data block chain) via trackdisk `CMD_READ`. OFS format locked empirically. Serial marker **D1** (size 1024 + markers @0/@488/@976); RED `OFS_NO_DATACHAIN` (size 488). INTERNAL machinery (no packets).
- **OFS subdirectories DONE**: `ofs_read_file` now takes a '/'-separated PATH. `ofs_split` splits component by component; `ofs_dir_lookup(dir, comp)` hashes+walks the chain of the CURRENT directory (intermediate USERDIR = sectype 2 → becomes the next directory; last component = file, sectype -3). `ht_size`: read from the block for the root (72), but USERDIRs leave long[3]=0 (measured) → fallback `OFS_HTDEF`=72. The single-component lookups (kickslop/D3DTest/e3cmd) go through the same driver (last=1, root) = non-reg. The shell opens "s/startup-sequence" (the ADF's `s/` subdirectory). Markers **F1BOOTOK**+**E3 CMD RAN OK** now sourced from the subdirectory; RED `OFS_NO_SUBDIR` ('/' = normal char → path looked up in the root → not found → F1BOOTOK/E3 absent, D1/E2 SHELL READY intact).
- **LoadSeg (D2) DONE** (`src/dos/loadseg.s`): `dos_loadseg`/`dos_unloadseg` load a hunk executable from the OFS, apply the relocations (RELOC32 $3EC) and build the BPTR seglist. Hunk format locked empirically. Serial marker **D2LOADSEG** (emitted by the loaded+relocated code); RED `D2_NO_RELOC`. INTERNAL machinery.
- **dos packets / process / handler (D3) COMPLETE** (`src/dos/process.s`, `handler.s`, `dos_lib.s`, `loadseg.s`, `dospkt.i`): **D3a** `proc_create` (Process = Task + embedded `pr_MsgPort` @0x5C; port initialised by the parent, reserved sigbit `DOS_PORTSIG`=8) + packet round-trip (marker **D3A**, RED `D3A_NO_REPLY`); **D3b** DF0: file-handler process `dos_handler_df0` serving `ACTION_FINDINPUT`/`READ`/`END` via `ofs_read_file`, + helper `dos_sendpkt` (no public DoPkt in V34) (marker **D3B**, RED `D3B_NO_READ`); **D3c** user-facing `dos.library` `Open`(-30)/`Read`(-42)/`Close`(-36) via packets — resolves the handler through `DosInfo.di_DevInfo`→`DeviceNode`→`dn_Task`, called from a client process (marker **D3C**, RED `D3C_NO_FHTYPE`); **D3d** running a command loaded *through dos*: `ls_load_hunks` (extracted from `dos_loadseg`) parses a buffer read via `Open`/`Read` (packets→handler→OFS), relocates, then `JSR` to the seglist — the whole dos chain exercised end to end (marker **D3D**, RED `D3D_NO_RUN`). Processes proven in the scheduled phase (created with the demo tasks). **cylinder-tracking** delivered → fast reads (WAIT=90).
- **dos.library `LoadSeg`(-150)/`UnLoadSeg`(-156) through the real LVO vectors DONE** (`src/dos/dos_lib.s`): `dos_fn_loadseg(name d1)` → BPTR seglist | 0 opens the file via the real `Open`(-30, MODE_OLDFILE), reads it WHOLE via the real `Read`(-42, loop until EOF — the file-handler is sequential) into an AllocMem'd buffer, parses it via `ls_load_hunks` (hunks + RELOC32 relocations → BPTR seglist), closes via `Close`(-36), frees the buffer. `dos_fn_unloadseg(seglist d1)` → `dos_unloadseg`. Vectors 25/26 of the jump table are wired (M6D = canary: DateStamp -192 stays at vector 32 → the table has not slipped). Proof **D3E LOADSEG LVO OK**: a client process `d3e_client` loads "D3DTest" via `jsr DOS_LVO_LOADSEG(a6)` → non-null seglist (opened+read+parsed+relocated through the real LVO path) → `UnLoadSeg`. `d3d_client` (inline Open/Read/ls_load_hunks load) REMAINS the baseline independent of the layer below; RED `LOADSEG_LVO_UNWIRED` (vector -150 → dos_null) → D3E absent, **D3D baseline intact** → isolates the wiring of the LVO vector. **Scope (see Lemmings)**: loads OUR hunk executables through the real LVO path; whole-file buffered (≤ 16 KB, no streaming), DF0: OFS handler only → NOT enough to run commercial software (missing `Lock`/`Seek`/`Examine`/`Write`, `expansion.library`, streaming, and our boot.s is a dev harness, not a production reset path). `sh_exec_cmd` (shell E3) keeps its inline load (not touched so as not to risk E3/F1/F2b; DRY refactor to LoadSeg = possible follow-up).
- **Interactive CLI on serial (E) IN PROGRESS** (`src/dos/conhandler.s`): **E1** serial-console handler `con_handler` — process serving `FINDINPUT`(open)/`WRITE`(emits on serial, bounded TBE poll)/`READ`(reads a line from RX with echo)/`END`, same shape as `dos_handler_df0`. It is the **console.device substitute**: the CLI does all its IO via DOS FileHandles (DOS packets → this handler), never directly on `SERDAT` — in the Real bootstrap (F) we replace this handler by a real console.device without touching the shell. READ blocks cleanly via polling on a **timer.device MICROHZ** tick (BeginIO `TR_ADDREQUEST` + Wait, `task_timer` precedent) — no busy-poll (COOP-safe), no level-5 RBF interrupt (deferred to F). Global port `DOS_CONPORT`. Marker **E1 CON WRITE OK** (RED `E1_NO_WRITE`) proven in the 4 standard scenarios; **READ** proven in the interactive harness (`tests/boot_test_interactive.sh` injects into `ser_cap` → Paula RX via `SERDATR` bit 14 RBF): "hello" injected → "E1 CON READ=hello". **E2** shell `shell_main` (`src/dos/shell.s`): opens the console, banner **E2 SHELL READY**, prompt loop `> ` → read line → parse 1st word → dispatch builtins (`ver` → "E2 SHELL ver OK"; `echo <args>` → re-emits) otherwise `?`. Replaces the E1 proof client as the only consumer of the console. RED `E2_NO_DISPATCH` (everything → `?`). **E3** the "unknown command" branch null-terminates the 1st word and calls `sh_exec_cmd` (OpenLibrary dos → Open/Read of the name from DF0: → `ls_load_hunks` → reloc → `JSR` → UnLoadSeg) — same stack as D3d but triggered by the TYPED NAME; if not found → `?`. Typed command "e3cmd" → **E3 CMD RAN OK** (loaded from disk via dos + run). RED `E3_NO_EXEC` (loaded but not run). **Interactive CLI reached**: prompt, typed commands, builtins + external commands from the disk.
- **Real bootstrap (F) IN PROGRESS**: **F1** the Initial CLI is now created BY THE BOOT PATH — `shell_main` is no longer created unconditionally in `setup_demo_tasks` but in the `.m6r_booted` branch of boot.s, AFTER `strap_boot` and ONLY if a bootable disk is present (the F vs "E4" line = the gating). On a non-bootable disk → M6R insert-disk, no Initial CLI. The shell first runs `sh_run_startup` (Open/Read "s/startup-sequence" in the OFS `s/` subdirectory via dos — subdirectory traversal, see above — then `sh_dispatch_line` on each line: builtins + external commands, empty/`;` ignored) BEFORE the interactive prompt. Markers **F1BOOTOK** (echo from the script) + **E3 CMD RAN OK** (e3cmd launched by the script). RED `F1_NO_STARTUP` (CLI created but script skipped). **F2a** CIA-A keyboard reception+decoding (`src/exec/keyboard.s`): `kbd_selftest` called very early at boot (IRQs masked -> no race with the `cia_wrapper`), bounded poll of CIA-A (ICR bit 3 = SP), reads SDR, decodes `NOT(ROR.b #1, brut)`, handshake (CRA bit 6 pulse ~75us), collects the emulated keyboard's power-up stream ($FD initiate + $FE terminate) -> **F2 KBD OK**. Proven WITHOUT an injector (the emulated keyboard sends its power-up sequence at reset; preliminary spike confirmed). RED `F2A_NO_HANDSHAKE`. **F2b** LIVE interrupt-driven keyboard driver: `kbd_install` (after M7B) does `OpenResource` "ciaa.resource" + `AddICRVector(bit 3 = SP)` → `kbd_interrupt`, then re-enables PORTS/INT2 (turned off after the M7B demo); `ciaa_server` (still on the PORTS chain) acknowledges the ICR and routes bit 3 to `kbd_interrupt`. `kbd_interrupt` decodes (F2a), mandatory handshake, ignores key-ups (bit 7), maps keycode→ASCII (**minimal US keymap**, checked against the keycodes measured under FS-UAE: v=$34 e=$12 r=$13 Return=$44 space=$40) and pushes into a **lock-free SPSC ring** (`KBD_RING`/`KBD_HEAD`/`KBD_TAIL` in low RAM; producer = INT2, writes the data BEFORE advancing `KBD_TAIL`). `con_handler` READ drains this ring via `con_ring_get` (consumer, advances `KBD_HEAD`) IN ADDITION to the serial RBF → the CLI is driven by the **real keyboard**, without masking (SPSC). Marker **F2B KBD OK** (install OK). **E2E** proof: `xdotool key v e r Return` (XTEST on the FS-UAE window under Xvfb — not `--window`/XSendEvent which SDL ignores; injection + keycodes recorded by a preliminary spike) → echo "ver" + **E2 SHELL ver OK**; harness `tests/boot_test_kbd.sh`. RED `F2B_NO_FEED` (handler decodes but does not push into the ring → "E2 SHELL ver OK" absent, "F2 KBD OK"/"F2B KBD OK" intact → keyboard→console wiring load-bearing). GREEN+NODISK+COOP, 0 FAILED. **Coming up**: real console.device (screen rendering; plug the keyboard into it via input.device), disk-validator, Intuition requesters, complete keymap (keymap.resource, + AZERTY variant). In F we will replace the serial-console handler by a console.device WITHOUT touching the shell (IO already goes through DOS FileHandles). D3 = architectural core reached; D prerequisites delivered (M6z/D1/D2).
- **console.device WRITE (#3a) DONE** (`src/exec/console.s` + `src/graphics/font8x8.s`): AUTOINIT resident device NT_DEVICE pri 20. `initfunc` allocates a 1-plane bitplane (chip RAM). `BeginIO`/`CMD_WRITE` interprets the stream via `con_putglyph`: printable → **8x8 glyph blitter** (synchronous CPU copy of 8 bytes from `font8x8` into the bitplane at `cury*stride+curx`) + column advance; CR → col 0; LF/wrap → line +8 (clamped, no scroll). graphics.library has no `Text()` → rendering here. **HAND-AUTHORED font** (`tests/mk_font8x8.py` → `font8x8.s`, public domain, 96 glyphs 0x20-0x7F) — NEVER the ROM topaz (clean-room trap). Headless **READBACK** proof: CMD_WRITE of a known string then read-back of each bitplane cell compared with the expected glyph → **CONSOLE WRITE OK** (validates the address math + the font, without display/Xvfb); RED `CON_NO_BLIT` (blit skipped → mismatch → absent). **On-screen (visual) rendering deferred**: `gfx_text_display` (Copper on the bitplane via the M6S pipeline) exists but FS-UAE/Xvfb does not display the Amiga framebuffer in a capturable X window (capture of the M6S kitten identical) → pixel verification not viable in headless CI; correctness proven by readback.
- **console.device READ via input.device (#3b) DONE** (`src/exec/console.s`): `console.device` registers at init a handler on **input.device** (`IND_ADDHANDLER`, `console_input_handler`, struct `CONB_INT` in the base). Each RAWKEY key-down received via the input.device chain is cooked keycode→ASCII (reuses F2b's `kbd_keymap`) and pushed into a **read buffer** (`CONB_RBUF` ring); `CMD_READ` serves it back. console.device is therefore the REAL `IND_ADDHANDLER` consumer that makes chain #2 load-bearing. Marker **CONSOLE READ=v** (IND_WRITEEVENT of a RAWKEY $34 through the public path → console handler → cook → read buffer → CMD_READ); RED `CON_NO_READBUF` (cooks without buffering → CMD_READ empty → absent). The keyboard→input.device feeder (from a task) = F integration (the keyboard already reaches the ROM in F2b, WRITEEVENT propagates in #2).
- **Clickable Intuition "insert disk" requester DONE** (`src/intuition/requester.s`): Requester struct + Gadget struct (NDK layout); `req_hittest(x,y)` = hit-test of the gadget's absolute box; `req_input_handler` on input.device → LEFT BUTTON click (IECLASS_RAWMOUSE/IECODE_LBUTTON) hit-tested → sets `REQ_HIT`; `req_draw` renders border + text "INSERT DISK"/"RETRY" via `font8x8` into a bitplane. Markers **REQUESTER DRAWN OK** (readback border+glyph 'I') / **REQUESTER CLICK OK** (RAWMOUSE INSIDE→hit, OUTSIDE→miss via IND_WRITEEVENT); RED `REQ_NO_HITTEST`. Click proof = public IND_WRITEEVENT path, same chain as console.device. Hardware mouse + live M6R wiring now DONE (gameport.device entry below).
- **gameport.device (hardware mouse) + live M6R wiring DONE** (`src/exec/gameport.s` + `src/intuition/pointer.s`): AUTOINIT resident device NT_DEVICE pri 60. Mouse not observable headless (RELATIVE JOY0DAT deltas + no injectable movement + invisible framebuffer) → we FACTOR OUT the pure logic of the hardware shim. **`gp_delta8(cur,prev)`**: signed delta with 8-bit wraparound (`sub.b`+`ext.w` — the JOY0DAT quadrature counters wrap). **`gp_poll(JOY0DAT, CIAA_PRA)`**: pure logic — dx/dy via gp_delta8, edge detection of the left button (CIAA PRA bit 6, active-low), and if movement/edge → InputEvent RAWMOUSE ($68 down / $E8 up / $FF movement) injected into input.device via `IND_WRITEEVENT` (keyboard feeder pattern; no input.task — documented deviation). **`gp_vblank_server`**: thin hardware shim (reads the real registers → gp_poll), registered by `gp_install` on the VERTB chain of the running system (persistent LIVE wiring, counterpart of the keyboard feeder); `GP_PREV_JOY` primed with the current reading (avoids the frame-1 glitch). **`pointer_input_handler`** (intuition, pri 50 > requester 0): accumulates the RELATIVE deltas into an ABSOLUTE position `PTR_X/PTR_Y` clamped to the screen and rewrites ie_X/ie_Y → the `req_input_handler` (pri 0, UNCHANGED) hit-tests in absolute terms = the live M6R wiring. Proofs: **GAMEPORT OK** (gp_delta8 wraparound + button edge + event captured by a handler, via IND_WRITEEVENT); **M6R LIVE OK** (relative RAWMOUSE deltas → accumulator → clamped absolute position → gadget hit-test: on the gadget→hit, outside→miss); **GP VBLANK LIVE OK** (gp_vblank_server runs on the REAL VBlanks of the running system: GP_POLLS advances). REDs: `GP_NO_WRAP` (word sub without sign-extend → wrong delta at wrap → GAMEPORT OK absent), `GP_NO_EDGE` (event on every held poll → edge counter 2→3 → GAMEPORT OK absent), `PTR_NO_CLAMP` (no clipping → position off screen → hit-test misses → M6R LIVE OK absent). Headless JOY0DAT static → the live server injects nothing (prev primed = current) → inert with respect to M7 (non-reg M7A/M7E/M7F/M7G + E3 CMD RAN OK/F1BOOTOK confirmed, 0 FAILED). RIGHT button (POTINP) and real click on a displayed screen deferred (unverifiable headless; waiting for a real display).
- **Shell screen swap (F integration, item 2) DONE** (`src/dos/conhandler.s`, gated by `SHELL_ON_SCREEN`): achieved by GATING con_handler (no new handler nor repointing; `DOS_CONPORT` stays con_handler, which becomes the SCREEN handler). Flag=1: WRITE renders the buffer via `console.device CMD_WRITE` (#3a rendering) **+ unconditional serial mirror** (proof channel); READ sources `console.device CMD_READ` (keyboard via feeder→input.device→console.device) instead of `KBD_RING`, with screen+serial echo + line discipline (helpers `con_scr_read`/`con_scr_emit`, state `CS_CONBASE`/`CS_CONIO`). Shell binary INTACT. Proofs: GREEN (SHELL_ON_SCREEN=1) "ver" typed → **E2 SHELL ver OK** (shell driven by the keyboard via the new path); RED (+FEEDER_NO_WRITEEVENT) → input cut → E2 SHELL ver OK absent, E3 CMD RAN OK present (discriminates the input path); flag off → serial con_handler unchanged. Screen ROM: `make kick` with `SHELL_ON_SCREEN=1`.
- **Keyboard feeder → input.device (F integration, item 1) DONE** (`src/dos/feeder.s`): process (COOP poll every frame, timer.device VBLANK since step 10 (28); IECLASS_TIMER tick and key repeat) that drains the **RAW ring** `KBD_FEEDRING` (fed by `kbd_interrupt` via a raw tap at the SAME point as the cooked push → snapshot `(KBD_QUAL<<8 | keycode)`, a single qualifier authority) and injects each keystroke as a RAWKEY InputEvent into input.device (`IND_WRITEEVENT`) → input.device = single source of the keyboard, `console_input_handler` cooks. Two transitional rings (cooked `KBD_RING`+serial con_handler remain the shell's path until the swap). Self-test (ifeq `SHELL_ON_SCREEN`): reads console.device CMD_READ and emits **FEEDER OK=<char>**; proven by 'v'→`FEEDER OK=v` and **Shift+v→`FEEDER OK=V`** (qualifier snapshot + shift cook); RED `FEEDER_NO_WRITEEVENT`. Timer poll (no Signal from the CIA ICR).
- **keymap.resource + cook + AZERTY ROM (#5) DONE** (`src/exec/keymap.s` + `src/exec/keymapdata.s`): resident `keymap.resource` (direct-init pri 100, `MakeLibrary` + jump table `SetKeyMapDefault`/`AskKeyMapDefault`) holds the default keymap (US QWERTY, or FR AZERTY if `KEYMAP_AZERTY=1`) and publishes `KM_RESBASE`. `kbd_cook(keycode, qualifiers)→ASCII`: SHIFT (`_hi` table), CAPS (upper-case letters), CTRL (char&$1F). **HAND-AUTHORED** tables (`tests/mk_keymaps.py`→`keymapdata.s`, `km_us_lo/hi`, `km_fr_lo/hi`, 96 bytes each) — NEVER the ROM. Wired LIVE: `kbd_interrupt` tracks the qualifiers ($60-$67 → `KBD_QUAL`) then cooks via `kbd_cook` (replaces F2b's flat table); `console_input_handler` (#3b) cooks via `kbd_cook(keycode, ie_Qualifier)`. Markers **KEYMAP OK** (US: q/Q/Q, 1/!, ctrl-C=$03) / **KEYMAP AZERTY OK** (same keycodes → a, &/1, é: proves that the table drives); F2b E2E "ver" replayed on both ROMs (live non-reg); RED `KM_NO_SHIFT`. AZERTY ROM: `make kick` with `KEYMAP_AZERTY=1`. Deviation: simplified representation (2 tables + rules) vs complete V34 KeyMap struct (dead keys deferred).
- **OFS disk-validator (#4) DONE** (`src/dos/diskvalidator.s`): `dv_validate` validates the allocation bitmap of DF0: via trackdisk — OFS checksum of the rootblock (Σ 128 longs == 0), sec_type ST_ROOT, `bm_flag`==$FFFFFFFF, OFS checksum of the bitmap block (`bm_pages[0]`), and CONSISTENCY (rootblock 880 marked ALLOCATED bit=0: idx=878 → long[28] bit 14, LSB-first). Offsets/convention (bm_flag@312, bm_pages@316, 1=free/0=allocated) checked on the test ADF. Marker **DISK VALID OK**; RED `DV_CORRUPT` (flip of one byte of the bitmap block → checksum fails → rejection → absent); NODISK → absent. Revalidation (bm_flag=0 → rebuild) deferred. INTERNAL machinery (no packets).
- **Serial emission lock (bench) DONE** (`src/exec/boot.s` `ser_lock`/`ser_unlock`): `ser_puts` had no mutex and several concurrent emitters (d3x proof clients, the shell's `con_handler` WRITE, feeder, loaded binaries e3cmd/d3d) interleaved the markers byte by byte → a GREEN marker could become non-greppable (false GREEN/false red). Fix = mutual exclusion through **Forbid** (no task switch during an emission; no lock byte+spin to avoid deadlock with nested Forbids — Forbid-around-emit is already `task_timer`'s pattern). `ser_lock`/`ser_unlock` (xdef, Forbid/Permit gated by `SCHED_ON` → no-op before multitasking, preserve all registers) are called by ALL the concurrent emitters: `ser_puts`/`ser_puthex`, `con_handler` WRITE, `feeder` fd_selftest, and the loaded binaries through their caller's Forbid (`sh_exec_cmd` for e3cmd/E3, `d3d_client` for D3D) — hence **without regenerating the ADF or editing the test binaries**. Proven by cross-run STABILITY (all markers greppable on every run, where E3/D3B/DOS-IOERR were flaky). The pri 5 of the d3e/d3f clients becomes defence in depth. Note: a finer granularity (lock byte letting the other tasks run during an emission) remains a possible refinement if the Forbid stalls ever become a problem.
- **LoadSeg cap bump 16K → 32K DONE** (`exec.i` `DOS_FILEMAX`, `handler.s`, `dos_lib.s`, `loadseg.s`): the READ cap of an executable was the handler's whole-file buffer (`HND_FILEMAX`) + LoadSeg's (`LS_LOADMAX`), both 16 KB. Raised to a shared `DOS_FILEMAX`=32 KB (2 concurrent buffers = 64 KB transient, safe on the ~500 KB A500 heap). **This is NOT streaming**: the file stays buffered in full; real incremental OFS reading (data block by data block, without a whole-file buffer) was then a deferred DEBT (large blast radius on the proven `ACTION_READ` path — D1/D3B/D3C/D3D/E3/F1 depend on it). **DEBT LIFTED since**: see "REAL OFS streaming" below (the whole-file buffer + the `HND_FILEMAX` cap have disappeared from the handler). Proof **LOADSEG BIG OK**: `tests/loadseg_big.s` = hunk executable > 16 KB (large 24 KB DATA hunk + sentinel `$B16B00B5` at the end + 1 RELOC32), written to the ADF (`bigseg`), loaded by `d3h_client` via `LoadSeg`(-150) + executed → the binary checks the sentinel (so the whole large DATA was read into the segment) and emits the marker. RED `LOADSEG_CAP16K` (re-caps at 16 KB → bigseg truncated at FINDINPUT → sentinel absent → no emission; d3dtest < 16 KB stays OK). Non-reg: D3E/E3/D1/M6Z intact, ADF layout preserved (spanning blocks 10/11 not disturbed).
- **dos.library `Write`(-48) + `Input`(-54) + `Output`(-60) + `CurrentDir`(-126) DONE** (`src/dos/dos_lib.s`): **Write** sends `ACTION_WRITE` to the `fh_Type` port (to con_handler → serial emission; to the read-only OFS → error), mirror of Read. **Input/Output** return ThisTask's `pr_CIS`/`pr_COS` (standard FileHandles). **CurrentDir** sets `pr_CurrentDir` and returns the old one. Vectors 8/9/10/21 wired (DateStamp -192 stays vector 32 = M6D canary). Proof **DOS WRITE OK** (`d3g_client`): CurrentDir round-trip ($1234→0→$1234) + Input (pr_CIS=$5678 read back) + `pr_COS = console FileHandle` (fh_Type=`DOS_CONPORT`) → `Output()` returns this BPTR → `Write(Output(), msg, len)` → **the "DOS WRITE OK" marker is emitted BY the Write itself via con_handler** (proves all 4 at once). RED `DOS_NO_WRITE` (dos_fn_write does not send the packet → nothing emitted).
- **dos.library `IoErr`(-132) + `Seek`(-66) DONE** (`src/dos/dos_lib.s`, `process.s`, `handler.s`): **IoErr** returns ThisTask's `pr_Result2`; wired in `dos_sendpkt`, which now copies `dp_Res2 → pr_Result2` after EACH packet (faithful, a single place); the OFS handler sets `DP_RES2 = ERROR_OBJECT_NOT_FOUND`(205) on an Open not found. **Seek** sends `ACTION_SEEK` to the handler (ARG1=key, ARG2=position, ARG3=mode OFFSET_BEGINNING/-CURRENT/-END) → the handler adjusts `HS_POS` (it buffers the whole file) bounded to [0,size], returns the OLD position. Vectors 11 (-66) + 22 (-132) wired in the jump table (DateStamp -192 stays vector 32). Proof **DOS IOERR SEEK OK** (`d3f_client`, pri 5, emits under Forbid): Open of absent file → 0 + `IoErr`≠0; Open d3dtest → `IoErr`=0; Read 4 → `Seek(0,BEGINNING)` (returns the old pos 4) → Read 4 identical. REDs: `DOS_NO_IOERR` (dos_sendpkt does not propagate dp_Res2 → IoErr=0 after failure), `HND_NO_SEEK` (handler ignores ACTION_SEEK → the 2nd read does not start again from the beginning). **Write(-48) DEFERRED** (advisor): read-only OFS → a file Write would only prove the clean failure; a real Write requires the console wiring (con_handler + Output -60), more than this increment justifies.
- **dos.library `Lock`(-84) + `UnLock`(-90) + `Examine`(-102) + `ExNext`(-108) DONE** (`src/dos/dos_lib.s`, `handler.s`, `ofs.s`, `ofs.i`, `dospkt.i`): locks + OFS directory reading. **Lock** resolves the device (DF0:) for the handler's port, converts the name into a long-aligned BSTR and sends `ACTION_LOCATE_OBJECT`; the handler resolves the path via `ofs_name_to_block` (`xxx:` prefix ignored, empty/":" → root OFS_ROOTBLK, `/`-separated subdirectories, final component file OR dir), allocates a `FileLock` {fl_Key=block, fl_Access=mode, fl_Task=handler port, private cursor flp_Bucket/flp_ChainBlk=0} and returns its BPTR. **UnLock** gets the port back through the lock's `fl_Task`, sends `ACTION_FREE_LOCK` (FreeMem). **Examine** sends `ACTION_EXAMINE_OBJECT` → `ofs_fill_fib` (DiskKey=block, DirEntryType=sec_type, FileName=BCPL name→C string, Size=byte_size@324 if file otherwise 0) + cursor reset. **ExNext** sends `ACTION_EXAMINE_NEXT` → `ofs_dir_next` (state machine: walks the current hash chain then advances bucket by bucket in the hashtable, fills the FIB of the entry, advances the cursor stored INSIDE the lock). Vectors 14/15/17/18 wired (DateStamp -192 stays vector 32 = canary). **Offset `OFSB_FILESIZE`=324 verified** on the test ADF (kickslop block 866 → 1024) BEFORE building, reconfirmed by the boot assertion. Proof **DOS LOCK EXAMINE OK** (`d3i_client`, pri 5, emits under ser_lock): (A) Lock("kickslop")→Examine → DirEntryType<0 (file) AND fib_Size==1024 (oracle read@324→write@124→readback); (B) Lock(":")[root]→Examine (DirEntryType>0, directory)→ExNext in a loop finds the 1024-byte file entry (= kickslop specifically). RED `OFS_NO_DIRNEXT` (ofs_dir_next returns found=0 straight away → ExNext never finds anything → marker absent, **D1 OFS READ stays GREEN** = isolates enumeration from the proven read path). **DELIBERATE clean-room deviation**: the real AmigaDOS keeps ExNext's cursor in the FIB (fib_DiskKey); we keep it in the lock (one lock = one enumeration; enough for the harness, documented in `dospkt.i`).
- **REAL OFS streaming DONE** (`src/dos/ofs.s`, `handler.s`, `ofs.i`): the DF0: handler NO LONGER buffers the whole file at FINDINPUT. New primitives `ofs_stream_open`/`ofs_stream_read`/`ofs_stream_seek`: one state per FileHandle (`SS_*`, a single AllocMem = fields + IOStdReq + 512-byte block buffer) holds a cursor {byte_size, pos, first_data, cur_block, blk_base}. `ofs_stream_read` loops incrementally — loads the current data block (512 bytes), advances via `next_data` when exhausted, copies `min(rest of block, rest requested, rest to EOF)` — O(1)=512-byte footprint per handle instead of O(file size). `ofs_stream_seek` = "dumb seek": rewind to the 1st data block if the target is backwards, otherwise `pos=cible`; forward movement is done lazily by `ofs_stream_read`'s advance loop. **No size cap any more** (the old `HND_FILEMAX`=`DOS_FILEMAX`=32 KB disappears from the handler; `DOS_FILEMAX` remains for LoadSeg's buffer `LS_LOADMAX`). `ofs_read_file` (D1) + `dos_loadseg` (D2) remain INTACT (direct call, outside the handler) → independent anchoring. Proof **OFS STREAM OK** (`d3j_client`, pri 5, under ser_lock): opens "BigData" (48000 bytes **> old 32 KB cap**, 99 OFS data blocks), reads it ENTIRELY in 4096-byte chunks (12 Reads, cursor maintained between calls) → total==48000 AND sentinel `$B16B00B5` in the last 4 bytes; then cross-block `Seek`(500, BEGINNING) + `Read`(4)==`$A5EE3780`. The old whole-file handler would have truncated at 32 KB → **self-sufficient** proof of the lifted cap (which the old code could physically not produce). RED `STREAM_CAP32K` (re-caps reading at 32 KB → BigData truncated → "OFS STREAM OK" absent; all files < 32 KB — kickslop/d3dtest/e3cmd/bigseg/startup — are still read ENTIRELY → D3B/D3C/D3D/E3/F1/D3E/LOADSEG BIG GREEN = isolates PRECISELY the raising of the cap). Test file added to the ADF (`tests/mk_bigdata.py`) without disturbing the layout (spanning blocks 10/11 checked intact).
- **Forbid atomicity at the preemption point DONE** (`src/exec/interrupts.s`) — PRE-EXISTING bug revealed by streaming. `ser_puts`/`ser_lock` relied on `Forbid` to serialise serial emissions, BUT the preemption path did not respect Forbid: `intr_isr_defer` (common int2/int3/int6 tail) consumed an `EB_ATTNRESCHED` set BEFORE the Forbid (stale quantum) or by `exec_Signal` of a higher-priority task DURING the Forbid, and switched at IRQ exit testing ONLY the S bit of the saved SR — NOT `EB_TDNEST`. Consequence: an emitting task under Forbid got preempted in the middle of `ser_puts` → markers interleaved char by char (invisible as long as the emissions were short/separated in time; streaming lengthened the emission windows → D3B/DOS-IOERR collision). **Fix**: `EB_TDNEST`/`EB_IDNEST` guard added in `intr_isr_defer` (if Forbid or Disable active → no deferred dispatch; AttnResched stays pending, consumed at the next non-forbidden IRQ exit or by Permit's voluntary yield via `trap #1`). Same guards as `sched_server` (which, for its part, already tested them before SETTING AttnResched). VOLUNTARY switches (Wait `trap #0` / yield-Permit `trap #1`) go directly to `intr_exit` without going through the guard → unchanged (correct). DETERMINISTIC proof **FORBID ATOMIC OK** (`task_fa` pri 3: Forbid → Signal(`task_fb` pri 7, arms AttnResched since 7>3) → waits 2 VBlanks UNDER Forbid ≥1 IRQ exit → `task_fb` did NOT run → emits). RED `SCHED_NO_FORBID_GATE` (removes the guard → fb preempts during the Forbid → flag set → marker absent; **M3F LIVE stays GREEN** = the scheduler is not broken, only the guard is missing). Timing proofs M7A/M7L/M3F non-reg. ⚠️ Corrects the earlier belief "ser_lock = total atomicity" (it was temporal separation, not mutual exclusion).
- **expansion.library (autoconfig, parity) DONE** (`src/exec/expansion.s` + `expansion.i`): AUTOINIT NT_LIBRARY resident module pri 110 (1st after exec). ExpansionBase = Library + `eb_Flags`(34) + list of ConfigDevs. Real functions at the real LVO offsets (confirmed on AROS `rom/expansion/expansion.conf`): `AddConfigDev`(-30, AddTail into the list), `AllocConfigDev`(-48, AllocMem CD_SIZEOF CLEAR), `FindConfigDev`(-72, walks the list, matches `er_Manufacturer` UWORD + `er_Product` UBYTE, -1 = wildcard), `FreeConfigDev`(-84); the rest (ConfigBoard/ReadExpansionRom/MakeDosNode/AddBootNode...) = `exp_null` (hardware probe/volume mounting deferred). Proof **EXPANSION OK** (synchronous, early): `OpenLibrary("expansion.library",37)` → 0 (KS 2.0 gate) + `(...,34)` → base; `AllocConfigDev`→sets manufacturer/product→`AddConfigDev`→`FindConfigDev` exact + product wildcard + absent ID = miss; cleanup guarded (Remove only if `ln_Succ`≠0). RED `EXP_NO_ENQUEUE` (AddConfigDev adds nothing → FindConfigDev fails → EXPANSION OK absent, no crash). **Lemmings NOTE**: the bootblock opens `expansion.library` at **v37** (KS 2.0) → our V34 gate returns 0 → the bootblock skips its expansion branch (it tolerates it). This module is **honest parity**, it does NOT unblock Lemmings. 15/16 resident ROMTags (RESMAX).
- **input.device (#2) DONE** (`src/exec/input.s`): AUTOINIT resident device NT_DEVICE pri 40, `BeginIO` by io_Command. **Handler chain** of InputEvents sorted by pri (struct List, Enqueue): `IND_ADDHANDLER`/`IND_REMHANDLER` insert/remove an Interrupt struct; `IND_WRITEEVENT` walks the chain (handler: a0=event list, a1=is_Data, a5=is_Code → d0=list for the next one — server idiom, robust to a chain change via the saved Succ). `IND_WRITEEVENT` = PUBLIC injection point (Intuition uses it) → proof in isolation = the real mechanism. Marker **INPUT OK** (FindName input.device + 2 handlers pri 10/0 + WRITEEVENT of a RAWKEY $34 → call order h1<h2 + keycode relayed); RED `INPUT_NO_PROPAGATE` (chain not walked → INPUT OK absent, device+ADDHANDLER intact). Deliberate #2 deviation: no input.task nor opening of keyboard/gameport (chain executed in the context of WRITEEVENT's caller); the LIVE keyboard → input.device → console wiring will be done in #3 (real console.device = natural consumer of IND_ADDHANDLER).
  **M7k postponed** (decision 2026-10-15): the INTREQR decoding of levels INT1/INT4/INT5 has no real consumer
  today (audio=M4+, disk=M6, serial later) -> folded into the relevant subsystem when it
  arrives, with a real consumer and a real test (not a throwaway synthetic self-test).

See `docs/PLAN.md` for what comes next and `docs/CLEANROOM.md` for the wall.
