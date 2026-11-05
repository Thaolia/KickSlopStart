# Memory usage compared with Kickstart 1.3

Reference: `docs/analysis/memory-budget-v34.md` (the real Kickstart 1.3 measured as a black box, 2026-11-05). This
page measures KickSlopStart in the same configuration and explains the difference line by line.

**Summary (2026-11-05, `17da6ee`, Workbench 1.3.3 idle at least 130 s):**

| Configuration | KickSlopStart free | Kickstart 1.3 free | Gap |
|---------------|-------------------:|-------------------:|----:|
| A/2: 512 KB chip + 512 KB slow, DF0 + empty DF1 (Amiberry A500 preset, the skill's default) | **836,152** | 861,048 (staged run) / 860,992 (unmodified disk) | **24,896** / 24,840 |
| A/1: same, DF0 only (`-- -s floppy1type=-1`) | **841,672** | 884,424 | **42,752** |

**Update (2026-11-05, after the console handler changes):** A/2 idle is now **839,024** (gap 22,024 / 21,968), 2,872 bytes
more: 824 from closing the initial CLI's console FileHandle at EndCLI (FileHandle 312 + write buffer 512) and 2,048
from the console handler's smaller stack (4,096 -> 2,048). Production ROM, unmodified disk, 150 s after the
"Incorrect Revision" line, MemList walked through gdb (chip 465,360, slow 373,664, largest slow 336,800); the
Workbench title shows the same figure. A/1 was not remeasured (expected 844,544). The tables below are those of
`17da6ee` unless a line says otherwise.

The A/2 gap is smaller only because an empty DF1 costs 1.3 23,432 bytes (MFM buffer and file system buffers) and
us 5,520. With one drive, 42,752 bytes separate us from 1.3: 36,408 inside the MemHeaders (section 4) and 6,344 of
RAM that never enters a MemHeader (section 3). In **chip** RAM we are better: 465,360 bytes free at idle against
429,512 on 1.3 (+35,848), because our track cache is in slow RAM and we have no file system buffers. The slow RAM is
also more fragmented: largest free block 334,752 against 399,464.

**Update (2026-11-05, `4f456b7`): one input task.** The keyboard feeder process is gone: its work runs in the
intuition input task (section 6.3). A/2 idle title: **840,536** (836,152 before, same harness), so the A/2 gap is
now 20,512. The 4,384 bytes are the feeder's TCB (240), stack (4,096) and MemList (32), plus 16 bytes from merging
its state, port and timer request into one 248-byte block. The tables below are those of the `17da6ee`
measurement, except the "Input handling tasks" row.

## How this was measured

- ROMs: production `make kick-prod` (`build/kick13-prod.rom`, md5 `bd5c11a3…`) for the free figures, and the
  diagnostic ROM for the callers:
  `make BUILD=build/mtp VASMDEF="-DMEMTRACK=1 -DPROD=1" KICK_ROM=build/kick13-mtp.rom VLINK="vlink -Mbuild/mtp/kick.map" kick`
  (is_kick ok; the `VLINK` override writes the map used to resolve callers).
- `MEMTRACK` (in `src/exec/memory.s`) records every live allocation in a table of 12-byte entries: address, size,
  and the return address of the `AllocMem` caller. The table itself is 36,000 bytes of chip RAM. Every figure of the
  diagnostic ROM below has these 36,000 bytes removed; after that, the diagnostic and production ROMs gave
  **identical** free chip and slow figures at all ten stages and at idle, so the caller tables describe the
  production ROM exactly. The sum of the live MEMTRACK entries equals the used part of the MemHeaders to the byte.
- Emulator: `amiberry` skill, `--model A500` preset (cycle-exact OCS PAL), 512 KB chip + 512 KB slow at
  `$C00000`; DF1 is present and empty by default (as in the 1.3 page); A/1 adds `-- -s floppy1type=-1`.
- Disk: a copy of `Workbench 1.3.3 (34.34) - Boot (Commodore) (1991) [m2].adf`. For the staged run, its
  startup-sequence was rewritten with xdftool, with `echo "MBn …"` + `wait 25` after each step of the 1.3 page; the
  RAM was dumped (`dump binary memory` through `amiberry-session gdb`, CPU stopped) 3 s after `MBn` appeared on the
  serial log. The idle dump is taken 152 s after the last step (stage 9) or 150 s after the "Incorrect Revision"
  line (unmodified disk); both gave 836,152.
- Why not `ask` as on 1.3: on our ROM, `ask` as the first startup-sequence line never returned. Cause found and
  fixed on 2026-11-05: the boot console handler ended its lines with CR and Ask reads up to LF (docs/PLAN.md).
- Walks done offline on the dump (scripts kept out of the tree): exec MemList (free, largest chunk), LibList /
  DeviceList / ResourceList, ThisTask + TaskReady + TaskWait with `tc_MemEntry`, PortList, IntuitionBase
  FirstScreen with its BitMap and windows, and the MEMTRACK table resolved against the map; stage-to-stage
  differences of the MEMTRACK table give exact per-step attribution.

**Pause overhead.** The `wait` used to pause costs us 5,400 to 6,208 bytes at stages 1-8 (Wait's hunks 1,392 +
the 4,008-byte stack every command gets from `sh_exec_cmd` + sometimes a BCPL global vector of 808), against about
600 for `Ask` on 1.3, which runs on the CLI's own stack. So the stage 1-8 gaps below are about 5 KB too large; the
step deltas and stage 9 are not affected.

## 1. Free memory by stage (A/2)

| # | Stage | Chip free | Slow free (largest) | Total free | 1.3 total free | Gap |
|---|-------|---------:|--------------------:|-----------:|---------------:|----:|
| 0 | Insert-disk screen, no disk | 460,232 | 490,112 (490,112) | 950,344 | 975,656 | 25,312 |
| 1 | First startup-sequence line | 467,088 | 421,984 (419,608) | 889,072 | 918,336 | 29,264 |
| 2 | after `SetPatch r` | 467,088 | 417,096 (414,808) | 884,184 | 913,448 | 29,264 |
| 3 | after `AddBuffers df0: 10` | 467,088 | 417,096 (414,808) | 884,184 | 908,008 | 23,824 |
| 4 | after echo, FastMemFirst, BindDrivers, SetClock, FF | 466,128 | 409,752 (402,264) | 875,880 | 899,704 | 23,824 |
| 5 | after `resident CLI`, `resident Execute`, `mount newcon:` | 466,128 | 397,840 (390,824) | 863,968 | 887,792 | 23,824 |
| 6 | after StartupII | 466,128 | 369,104 (346,552) | 835,232 | 863,208 | 27,976 |
| 7 | after `path`, `SYS:MountMF` | 466,128 | 368,328 (346,552) | 834,456 | 859,432 | 24,976 |
| 8 | after `LoadWB delay` | 465,360 | 352,120 (337,424) | 817,480 | 847,768 | 30,288 |
| 9 | after `endcli`, Workbench idle | 465,360 | 370,792 (337,424) | 836,152 | 861,048 | 24,896 |
| 9' | unmodified disk, idle | 465,360 | 370,792 (334,752) | 836,152 | 860,992 | 24,840 |

Chip is never fragmented on our side (largest = free).

### What each step costs (used bytes, chip + slow, A/2)

| Step | Ours | 1.3 | Difference and cause (MEMTRACK diff) |
|------|-----:|----:|--------------------------------------|
| Boot (0 → 1) | +61,272 | +57,320 | +3,952. Both open the Workbench screen (40,960 chip) and free the insert-disk picture (ours 48,024 chip + its copper lists; 1.3's whole stage-0 display and boot chip is about 29,900). We allocate the track cache (45,056) at the first read, 1.3 the DF1 MFM buffer (16,392) and 10 file system buffers. Our initial shell process has an 8,192-byte stack (1.3 1,600 + a CON handler of 2,800). |
| SetPatch r | +4,888 | +4,888 | identical (35 hunks + port "SetPatch-01") |
| AddBuffers df0: 10 | 0 | +5,440 | −5,440: our file system has no block buffers; ACTION_MORE_CACHE is accepted and allocates nothing |
| echo … FF | +8,304 | +8,304 | identical. icon.library (base 154 + 4,812 of code) is loaded **here** on our side, by BindDrivers, and the 960-byte chip block of this step is an icon.library allocation; since the step is byte-identical on 1.3 (+960 chip there too), 1.3 most likely loads it here as well, not at LoadWB as the 1.3 page says (to be rechecked by the analysis track) |
| resident CLI, Execute, mount newcon | +11,912 | +11,912 | identical |
| StartupII | +28,736 | +24,584 | +4,152: the RAM handler process. 1.3: 1,388 (stack 1,200). Ours: TCB 240 + stack 5,296 (`pr_StackSize` 1,200 + `CP_STKEXTRA` 4,096, `src/dos/bcpl.s`) + MemList 32 |
| path, MountMF | +776 | +3,776 | −3,000: on our ROM MountMF prints "Incorrect Revision" (TDPatch13 refuses our trackdisk) and installs no patch |
| LoadWB delay | +16,976 | +11,664 | +5,312: Workbench process 5,272 (1.3 5,204); our ROM Workbench allocates a 9,126-byte state block (`WBS_SIZE`: 8 volume records and 6 drawer records of 1,084 bytes, all reserved up front) + CLI structure, two ports and a 128-byte chip image (272); window, layers, DiskObjects, locks 2,304; chip only 768 (1.3: 3,432) |
| endcli | −18,672 | −13,280 | −5,392: we free a larger initial shell (8,192 stack + 240 TCB + `sh_make_cli` 1,344 + its window). We did **not** free its console FileHandle (312), that FileHandle's 512-byte write buffer and its BCPL global vector (808): 1,632 bytes left behind. Since 2026-11-05 the FileHandle and its buffer are freed (−19,496); the GV stays, it is shared (section 5, item 8) |

Running sum of the differences: 25,312 at stage 0, then +3,952, 0, −5,440, 0, 0, +4,152, −3,000, +5,312, −5,392 =
24,896 at idle.

## 2. Where the stage 0 gap comes from

At the insert-disk screen, 1.3 has, besides the module bases, only its boot task, the insert-disk display and the
DF0 MFM buffer. Our DOS is already running: two file
system processes (DF0, DF1), the console handler, the keyboard feeder and the "DF0 watch" process (5 × 240-byte TCB
+ 4 × 4,096 + 1 × 1,024 of stack + MemLists; the console handler's stack is 2,048 since 2026-11-05), the intuition input task (4,192) and the insert-disk picture (47,872 +
152 chip, against about 29,900 on 1.3). Total used 83,432 against 64,464, plus the 6,344 bytes of section 3.

## 3. Memory outside the MemHeaders (never counted by AvailMem)

| Region | Ours | 1.3 |
|--------|-----:|----:|
| Chip below `mh_Lower` | 13,568 (`$0`-`$3500`) | 1,056 (`$0`-`$420`) |
| Slow below `mh_Lower` (ExecBase + slow MemHeader) | 1,232 | 1,256 |
| Supervisor stack | inside the chip area above (4,096 at `$2500`) | 6,144 at the top of slow RAM |
| **Total** | **14,800** | **8,456** |

Of our 13,568 low chip bytes: vectors and low-RAM variables up to `$800`; `$800`-`$2500` (7,424 bytes) holds
nothing once slow RAM exists (ExecBase and its jump table then live in slow RAM; the dump shows the untouched
power-up `$FF` fill up to `$1500` and, from `$1500` to `$2500`, the multi-header self-test region `FTEST_LO`/
`FTEST_HI`, identical from the insert-disk screen to idle); `$2500`-`$3500` is the supervisor stack.

## 4. Idle state by category (A/1, one drive)

Used inside the MemHeaders: ours **192,104** (chip 45,360, slow 146,744), 1.3 **155,696** (chip 74,608, slow
81,088). Categories follow the 1.3 page; ours are exact (MEMTRACK callers), 1.3's "rest" is its unattributed slow
memory.

| Category | Ours | 1.3 | Difference | Ours: callers |
|----------|-----:|----:|-----------:|---------------|
| Screen bitplanes 640 × 256 × 2 | 40,960 chip | 40,960 chip | 0 | OpenScreen (`intuition_end` in the map) |
| Track buffer / cache | 45,056 slow | 16,392 chip | **+28,664** | `td_cachebuf` (8 × 5,632); our raw MFM buffer is chip, allocated per read and freed |
| File system buffers | 0 | 8,160 chip | −8,160 | none (no block cache in our handler) |
| Other chip (copper lists, gadget images, pointer, chip icon images, boot leftovers) | 4,400 | 9,096 | −4,696 | `gfx_MrgCop` 1,112, `gfx_MakeVPort` 1,032, `sc_mkimage` 208, `wb_desktop` 128, `d2_done` 128, `init_task` 96, `it_ptrinit` 72, `graphics_initfunc` 24, disk programs 1,600 |
| Module bases (libraries, devices, resources) | 7,744 | ≈ 7,840 | ≈ −96 | `exec_MakeLibrary` 7,016 (incl. icon.library), `init_ints` 224, `build_reslist` 136, `dos_initfunc` 184, `gfx_fontinit` 104, `km_init` 80 |
| Input handling tasks (since `4f456b7`) | 4,440 | ≈ 4,192 (input.device task inside its base) | **+248** | intuition input task 4,192 (`it_startinput`), which also runs the keyboard feeder; feeder state 248 (`fd_init`). At `17da6ee`: 8,824 (+4,632), with a separate feeder process (TCB 240 + stack 4,096 + MemList 32 + `feeder_main` 264) |
| Loaded code: resident Shell-Seg, List, Execute, Resident, CD; SetPatch; icon.library; L:Ram-Handler | 42,216 | 42,216 | 0 | `ls_load_stream` (the same hunks: same files) |
| Other process TCBs + stacks + MemLists | 19,576 | 8,672 | **+10,904** | DF0 file system 4,368 (stack 4,096; 1.3: 1,028 with 840 of stack), console handler 4,368 (stack 4,096, 2,048 since 2026-11-05; 1.3 has none at idle), RAM handler 5,568 (stack 5,296; 1.3: 1,388), Workbench 5,272 (1.3: 5,204); 1.3's figure also holds the trackdisk unit task (924) that we do not have |
| Rest (slow) | 23,328 | 18,168 | +5,160 | Workbench state 9,272 (`wb_entry` 9,126 block + CLI 64 + ports); file system data 4,544 (`hnd_init` 848, OFS write context `ow_ctx` 1,776 + bitmap `ow_bmalloc` 520, locks 384, DevInfo nodes 848, volume 80, `fl_node` 64, boot node 24); BCPL getvec and resident nodes of disk programs 2,632; disk programs' own blocks 3,064 (FastFonts, SetPatch, icon.library); screen, window and layer structures 1,872; initial CLI leftovers 1,632 (808 since 2026-11-05: the shared GV); console handler data 312 |
| **Total** | **192,104** | **155,696** | **+36,408** | |

Plus section 3 (+6,344): 42,752 in all. In A/2 the empty DF1 adds 5,520 on our side (a second file system process
4,368, its handler data 912, a disk-program block 240) and 23,432 on 1.3.

ROM-module bases walked from the lists (NegSize + PosSize) where they differ from 1.3 by more than 100 bytes:
input.device 112 (1.3: 4,694, it holds its task), trackdisk.device 616 (1.3: 204; the 412-byte unit block of 1.3 is
separate), audio.device 402 (670), timer.device 136 (268). Our keymap.resource reads as a 2,228-byte block (1.3's
is not Library-shaped and was not counted).

## 5. Reduction candidates, ranked by size (idle, A/2 unless stated)

Item 2 overlaps items 5 and 6 (the DF1 file system and console handler stacks are counted in both).

| # | Candidate | Saving | Risk |
|---|-----------|-------:|------|
| 1 | Track cache: `TD_NCACHE` 8 → 4 (or 2) slots | 22,528 (33,792) slow | Low for correctness, medium for speed: the cache is a performance feature (the Workbench boot was 87 s with 8 slots; re-measure). It is already given back when an `AllocMem` fails (`td_lowmem`, ef259e5), but it stays allocated at idle, so `AvailMem` and the largest slow block show it. In A/2, 1.3 spends 32,784 chip on two MFM buffers, so 8 slots cost us only 12,272 more there; in A/1 28,664 more |
| 2 | Process stacks larger than 1.3's: file system handler 4,096 per drive (1.3: 840), console handler 4,096 (1.3: 2,800, and only while a CON window is open), RAM handler +4,096 `CP_STKEXTRA` over its 1,200 (1.3: none) | up to ≈ 3,250 per drive + 1,296 + 4,096 | High unless the stack high-water mark of each process is measured first (fill pattern, then a long Workbench session, copy, DiskCopy): an overflow corrupts the neighbouring block silently |
| 3 | Low chip `$800`-`$2500` (7,424 bytes) unused when slow RAM exists: add it to the chip MemHeader (and optionally move the supervisor stack to the top of slow RAM like 1.3, freeing `$2500`-`$3500` too, 4,096 chip for 6,144 slow) | 7,424 chip | Low to medium: check that nothing addresses `$800`-`$2500` after boot (a watchpoint over a full Workbench session), and that games which load over low chip still work (1.3's heap starts at `$420`, so they cannot rely on that area) |
| 4 | Workbench state: the 9,126-byte block reserves 6 drawer records (6 × 1,084 = 6,504) and 8 volume records at start; allocate a drawer record when its window opens | ≈ 6,500 | Low to medium (workbench.s only; drawer open/close and Close-on-error paths to re-test) |
| 5 | Empty DF1: start its file system process on first use only | 5,520 (A/2 only) | Medium (DOS mount order, disk-change handling). Already far below 1.3's 23,432 |
| 6 | Console handler process kept at idle with no window: exit it when its last window closes, or shrink its stack | 4,648 (or 1,296) | **Done 2026-11-05: stack 4,096 -> 2,048, 2,048 saved.** Deepest use 982 bytes, measured with a pattern-filled stack (section 6.5). Exiting was not chosen: processes hold its port in pr_ConsoleTask |
| 7 | **Done (2026-11-05, `4f456b7`).** Keyboard feeder process merged into the intuition input task (one input task, as on 1.3) | 4,384 measured | Section 6.3 |
| 8 | Initial CLI leftovers after `endcli`: console FileHandle 312, its 512-byte write buffer, BCPL global vector 808 | 1,632 | **Done 2026-11-05 for the FileHandle and its buffer, 824 saved.** The GV is not a leak: CreateProc copies the creator's pr_GlobVec, and the idle Workbench process points at this GV |
| 9 | Command stack: every command gets its own 4,008-byte stack (`sh_exec_cmd`) while 1.3 runs it on the CLI process stack; transient only, but the initial shell also has an 8,192-byte stack (1.3: 1,600) during the whole startup-sequence | ≈ 6,600 during startup, 0 at idle | Medium (programs that need large stacks, see `SH_STK`) |

Not candidates: loaded code and SetPatch / FF / resident steps are byte-identical to 1.3; screen bitplanes identical;
bases, other chip and file system buffers are already below 1.3.

## 6. Notes on single items

### 6.1 trackdisk track cache — 45,056 bytes (kept on purpose)

`trackdisk.device` keeps the last `TD_NCACHE` = 8 decoded tracks in an LRU cache (`TD_CACHEBUF`, 8 × 5,632
bytes). See `src/exec/trackdisk.s` and `TD_NCACHE` in `src/exec/exec.i`.

**Why it exists.** The OFS file system reads 512-byte blocks and keeps switching between the directory track and
the data tracks. Without a cache, every block costs a full track read: motor spin-up, seek, a DMA of the whole
track and MFM decoding of its 11 sectors. When the Workbench boot was measured with a single cached track, it
did 222 track reads for 58 distinct tracks. With the cache, a track already decoded is served straight from
memory.

**How it behaves.**
- It is allocated at the first `CMD_READ`, not at boot.
- The 8 slots are taken only from fast memory (`MEMF_FAST`, which includes the A501 slow RAM at `$C00000`).
  Without fast memory, or if 45 KB of it is not available, it falls back to a single slot of 5,632 bytes (1.3
  instead keeps a 16,388-byte raw MFM buffer per drive in chip RAM; our raw buffer is allocated in chip for each
  track read and freed right after). On a 512 KB chip-only A500 the 45 KB cache came out of the chip RAM that games
  need: Bubble Bobble could not start (its last chip requests failed). With one slot, the free chip RAM at the
  game's startup-sequence is 411,392 bytes, against 395,392 on the original Kickstart 1.3 (black-box
  measurement, 2026-11-02).
- A track enters the cache only if all 11 sectors decoded and carry the requested track number.
- A disk change (`/CHNG`) or `CMD_CLEAR` empties the cache.
- Writes (`CMD_WRITE`) update cached tracks and mark them dirty. Only `CMD_UPDATE` writes them back;
  turning the motor off keeps them in the cache.

**Size choice.** 8 slots is the knee of the curve. Going to 16 slots only took the measured Workbench boot from
87 s to 83 s, for another 45 KB.

**Trade-off.** The original 1.3 trackdisk keeps one track buffer per unit and relies on the file system's own
buffers instead. Lowering `TD_NCACHE` gives memory back at the cost of disk speed.

**Released under memory pressure (2026-11-05).** When an `AllocMem` fails, exec calls `td_lowmem` before it
expunges unused modules and retries: the multi-track cache is freed if no drive access is under way and no
slot waits for `CMD_UPDATE` (a single-slot cache is kept). The next disk access allocates it again, with 8 slots
if 45 KB of fast memory is free, otherwise one. `tests/lowmem_probe.s` (AvailMem(MEMF_FAST) around an
AllocMem that cannot succeed) on the Workbench 1.3.3 disk: 136 bytes released before (mathffp only), 45,192
after (cache + mathffp); after a `dir` the cache is back and a second failure releases it again.

### 6.2 Fixed: console bitmap left by the boot self-test — 10,240 bytes of chip RAM

The console self-test #3a in `src/exec/boot.s` ran in production ROMs too. It writes to a console unit that has
no window, and that makes `con_putglyph` allocate a 640×128 one-plane bitmap in chip RAM. The test closed the
unit but never freed the bitmap.

The test now frees `CONB_BITMAP` (`CON_BMSIZE` bytes) and resets the cursor when it finishes. After the fix,
`MEMTRACK` shows no live `con_putglyph` block once the Workbench is idle.

### 6.3 Intuition input task — 4,192 bytes, also the keyboard feeder's task

`it_startinput` (`src/intuition/screens.s`) creates a dedicated task at priority 20, like input.device's, with a
4,096-byte stack plus its TCB. It handles mouse buttons, gadgets, menus, window dragging and sizing, and since
2026-11-05 it also does the work of the keyboard feeder (`src/dos/feeder.s`): injecting the raw keys into
input.device, the IECLASS_TIMER tick and the key repeat. The separate feeder process (priority 4, 4,096-byte
stack) is gone.

**Why a task.** These actions draw and take layer locks, so they can block. They cannot run in the VBlank
interrupt or inside the input handler chain. A task of its own gives them a context that is allowed to wait.

**How the two jobs share it.** The task waits for its event signal and for the feeder's signal (keyboard
interrupt and timer deadline share one). At each turn, before it takes the next item of its ring, it calls
`fd_service`: keys first, then the due tick and repeat. The input handlers (console.device, intuition's own) run
then, at the top of the loop, never inside an action. A long action (a verification waiting for its reply, a layer
lock held by another task) only delays the keyboard: the keys wait in the 16-entry raw keyboard ring, and a release
already there still stops the repeat before it fires. On 1.3 a verification freezes the whole input system the
same way (`intuition-input-menus-v34.md`, §1 point 4). Menus held open, window drags and requesters are handled
event by event, so they do not hold the loop.

**Stack.** One 4,096-byte stack serves both. High-water mark measured on `kick-prod`, Workbench 1.3.3, the stack
filled with a pattern through the debugger once the desktop was idle (324 bytes used during boot): 916 bytes after
opening the disk window, a drag and a resize, right-button menus, opening the Utilities and Prefs drawers, a Shell
with `info`, `dir`, `echo` and a held key, Preferences, Rename with a held Backspace and Info. 3,180 bytes were
never touched.

### 6.4 AllocEntry failures leak their MemList (as on 1.3)

When one entry of an `AllocEntry` cannot be allocated, the entries already obtained are freed but the new MemList
(16 + 8 bytes per entry, rounded to 8) stays allocated, exactly as on 1.3 (exec-memory-semaphores-v34 §2.8; dos
`CreateProc` failures lose 24 bytes each this way). Programs can observe the 1.3 return codes and free memory, so
this is reproduced on purpose; it only happens when memory has already run out.

### 6.5 Console handler stack — 2,048 bytes (measured 2026-11-05)

The boot console handler (`src/dos/conhandler.s`, created in `src/exec/boot.s` with `CON_STK`) serves the initial
CLI's AmigaSlopDOS window and, after `endcli`, every "*" opened by a process whose pr_ConsoleTask is its port.

**Measurement.** Production ROM, Amiberry A500 preset. A gdb hardware breakpoint on `shell_main` (vlink map of the
same build) stops the CPU before the initial CLI opens its console; the console handler's stack, from `tc_SPLower`
to 16 bytes below its saved SP, is filled with `$A5`; at the end of the session the stack is scanned from the bottom
for the first byte that is not `$A5`. Sessions: a copy of the Workbench 1.3.3 disk whose startup-sequence runs
SetPatch, FastMemFirst, BindDrivers, SetClock, FastFonts, resident/mount, StartupII, MountMF, `dir sys: all`,
`list c:`, `type`, `info`, `avail`, `ask`, LoadWB, then at the prompt `dir c:`, a 110-character `echo` (wrapped),
`list s:`, the window shrunk and grown again with the mouse, `info`, and `endcli`. Deepest use: **982 bytes** in
every run (also 981 with the zero method on the MEMF_CLEAR stack, dev and production ROMs, unmodified disk).
With 2,048 bytes, 1,062 bytes stay untouched. `tests/con_probe.sh` (CON_ROM = production ROM) gives the same
output as the previous ROM except three addresses moved down by 2,048.

## 7. Rerunning the measurement

Rebuild both ROMs (section "How this was measured"), boot the staged disk copy in two sessions (production and
diagnostic), dump chip `$0`-`$80000` and slow `$C00000`-`$C80000` at each `MBn` marker, and compare: the
diagnostic ROM's free chip minus 36,000 must equal the production ROM's. A regression shows up as a new caller, or
a caller whose total grew, in the MEMTRACK table at idle; compare it caller by caller with section 4.
