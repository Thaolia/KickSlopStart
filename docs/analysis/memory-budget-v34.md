# Memory budget of Kickstart 1.3 (V34) with Workbench 1.3.3: black-box measurement

Status: measured 2026-11-05 on the real Kickstart 1.3 (34.5, A500) under Amiberry, cycle-exact A500 preset.
Purpose: give the implementation side a reference budget to compare with KickSlopStart (see
`docs/MEMORY-USAGE.md`). Everything here is behaviour and sizes. No ROM code was read; no ROM address appears.

## 1. Method (how every figure was obtained)

- **[MH]** Free memory per type: the exec memory list (ExecBase `MemList`) was walked from RAM with gdb while the
  CPU was stopped. For each MemHeader: `mh_Lower`, `mh_Upper`, `mh_Free`, and the full MemChunk chain (sum of
  chunks = `mh_Free` at every stage, so the lists were consistent). "Largest" is the largest MemChunk, i.e. what
  `AvailMem(type|MEMF_LARGEST)` returns. "Used" = `mh_Upper − mh_Lower − mh_Free`.
- **[LIST]** Libraries, devices, resources: `LibList`, `DeviceList`, `ResourceList` walked from RAM; base size =
  `lib_NegSize + lib_PosSize`.
- **[TASK]** Tasks: `ThisTask`, `TaskReady`, `TaskWait`; stack = `tc_SPUpper − tc_SPLower`; the `tc_MemEntry`
  MemLists give the exact blocks a task owns. Processes: `pr_StackSize`, `pr_SegList`, `cli_Module`.
- **[DOS]** DOS: `DosInfo` device list (DevInfo nodes) and the 1.3 resident segment list (it hangs off the
  DosInfo field that 2.0 calls `di_NetHand`; each node: next BPTR, use count, seglist BPTR, BSTR name). Segment
  sizes are the allocation length longword that precedes each hunk.
- **[HUNK]** Disk programs kept in memory: identified by matching the hunk allocation sizes (hunk size × 4 + 8, from
  the program's own hunk header on the Workbench disk) against a chain of segments found in a RAM dump.
- **[SCR]** Screens: `IntuitionBase.FirstScreen`, its embedded BitMap (`BytesPerRow × Rows` per plane).
- **[DELTA]** Difference between two stages of the same run.
- **[GAP]** Allocated regions = the holes between consecutive free chunks of a MemHeader. A hole may hold many
  allocations; only blocks recognised by the walks above are attributed, the rest is listed as "unattributed".

Configurations (Amiberry `--model A500`, OCS, PAL):

| Name | Memory | Drives |
|------|--------|--------|
| **A/2** | 512 KB chip + 512 KB slow at `$C00000` | DF0 + empty DF1 (the Amiberry A500 preset enables DF1) |
| **A/1** | 512 KB chip + 512 KB slow | DF0 only (`floppy1type=-1`) |
| **C/2** | 512 KB chip only | DF0 + empty DF1 |
| **C/1** | 512 KB chip only | DF0 only |

Disk: a copy of `Workbench 1.3.3 (34.34) - Boot (Commodore) (1991) [m2].adf`. For the staged runs the
`startup-sequence` of the copy was rewritten (xdftool) with an `ask "MBn ..."` line between steps; the run paused
on each `ask`, the dump was taken, then `y` + Return was typed. The measured state therefore includes the loaded
`Ask` command (about 600 bytes, `cli_Module` = 324 + 288 bytes) at stages 1 to 8. The idle state was also measured
on the unmodified disk: it matches the staged run within 56 bytes.

## 2. Memory outside the MemHeaders (never counted by AvailMem)

[MH], lower/upper bounds of each MemHeader.

| Config | Region | Bytes | Probable content |
|--------|--------|------:|------------------|
| A | chip below `mh_Lower` | 1,056 | CPU vectors and low system area (chip MemHeader starts at `$420`) |
| A | slow RAM below `mh_Lower` | 1,256 | ExecBase (negative + positive part) and the slow MemHeader |
| A | top of slow RAM above `mh_Upper` | 6,144 | supervisor stack |
| C | chip below `mh_Lower` | 2,280 | vectors + ExecBase + chip MemHeader |
| C | top of chip above `mh_Upper` | 6,144 | supervisor stack |

So with slow RAM present, ExecBase and the supervisor stack move to slow RAM and the whole chip RAM above `$420`
is in the chip MemHeader (523,232 bytes); without it, the chip MemHeader holds 515,864 bytes.

## 3. Free memory by stage

[MH]. Bytes. "Used" counts only what is allocated inside the MemHeaders.

### 3.1 512 KB chip + 512 KB slow, two drives (A/2)

| # | Stage | Chip free | Chip largest | Slow free | Slow largest | Total used |
|---|-------|---------:|-------------:|---------:|-------------:|-----------:|
| 0 | Insert-disk screen, no disk | 476,944 | 476,944 | 498,712 | 498,712 | 64,464 |
| 1 | First startup-sequence line | 439,344 | 439,272 | 478,992 | 478,840 | 121,784 |
| 2 | after `SetPatch r` | 439,344 | 439,272 | 474,104 | 472,896 | 126,672 |
| 3 | after `AddBuffers df0: 10` | 433,904 | 433,832 | 474,104 | 472,896 | 132,112 |
| 4 | after echo, FastMemFirst, BindDrivers, SetClock load, FF -0 | 432,944 | 432,872 | 466,760 | 462,736 | 140,416 |
| 5 | after `resident CLI` (Shell-Seg), `resident Execute`, `mount newcon:` | 432,944 | 432,872 | 454,848 | 451,296 | 152,328 |
| 6 | after StartupII (run execute + wait) | 432,944 | 432,872 | 430,264 | 410,040 | 176,912 |
| 7 | after `path`, `SYS:MountMF` (before LoadWB) | 432,944 | 432,872 | 426,488 | 399,464 | 180,688 |
| 8 | after `LoadWB delay` (before endcli) | 429,512 | 428,984 | 418,256 | 399,464 | 192,352 |
| 9 | after `endcli`, Workbench idle 130 s | 429,512 | 428,984 | 431,536 | 399,464 | 179,072 |
| 9' | same, unmodified disk, idle | 429,512 | 428,984 | 431,480 | 398,712 | 179,128 |

At stage 9 the Workbench title bar reads "861048 free memory" (= 429,512 + 431,536): AvailMem(0) agrees with the
MemHeader walk.

### 3.2 512 KB chip only, two drives (C/2)

| # | Stage | Chip free | Chip largest | Total used |
|---|-------|---------:|-------------:|-----------:|
| 0 | Insert-disk screen | 451,400 | 451,400 | 64,464 |
| 1 | First startup-sequence line | 394,080 | 393,936 | 121,784 |
| 2 | after SetPatch | 389,192 | 387,992 | 126,672 |
| 3 | after AddBuffers 10 | 383,752 | 382,056 | 132,112 |
| 4 | after FastMemFirst … FF | 375,448 | 370,056 | 140,416 |
| 5 | after resident CLI/Execute, mount newcon | 363,536 | 358,616 | 152,328 |
| 6 | after StartupII | 338,952 | 318,984 | 176,912 |
| 7 | before LoadWB | 335,176 | 308,408 | 180,688 |
| 8 | after LoadWB | 323,512 | 308,408 | 192,352 |
| 9 | Workbench idle 130 s | 336,736 | 308,408 | 179,128 |
| 9' | same, unmodified disk | 336,792 | 314,240 | 179,072 |

The "total used" column is identical (±56 bytes) in both memory configurations: the 1.3 allocations do not depend on
the presence of slow RAM, only their placement does.

### 3.3 One drive only (A/1 and C/1), Workbench idle, unmodified disk

Measured about 110 s and again about 170 s after the Workbench appeared; identical both times.

| Config | Chip free | Chip largest | Slow free | Slow largest | Total used |
|--------|---------:|-------------:|---------:|-------------:|-----------:|
| A/1 | 448,624 | 448,096 | 435,800 | 403,504 | 155,696 |
| C/1 | 360,112 | 336,472 | — | — | 155,752 |

**The empty DF1 drive costs 23,432 bytes** [DELTA A/2 − A/1]: 19,112 chip (16,392 MFM buffer + 2,720 = 5 file
system buffers) and 4,320 slow (trackdisk unit task and its unit structure, second File System process, its
global data and DevInfo). Any comparison with KickSlopStart must use the same drive count.

## 4. What each step costs (A/2, [DELTA])

| Step | Chip | Slow | Attribution |
|------|-----:|-----:|-------------|
| Boot (0 → 1): DOS start, initial CLI window | +37,600 | +19,720 | WB screen bitplanes 40,960 chip (opened by the initial CLI window) minus the freed insert-disk display; DF1 trackdisk unit opened by DOS (16,392 chip MFM buffer); 2 × 5 FS buffers (5,440 chip); dos.library and ramlib bases; Initial CLI process, CON handler process, 2 File System processes, DevInfo nodes, console unit and window |
| SetPatch r | 0 | +4,888 | SetPatch stays loaded: its 35 hunks = 4,784 bytes [HUNK] + its port "SetPatch-01" |
| AddBuffers df0: 10 | **+5,440** | 0 | 10 buffers × 544 bytes, **in chip RAM** although slow RAM was first in the list |
| echo, FastMemFirst, BindDrivers, SetClock, FF | +960 | +7,344 | mostly FastFonts (FF keeps code and a port "FF2:)" resident; its seglist was not found intact, so FF copies itself into its own allocations) |
| resident CLI L:Shell-Seg, resident Execute, mount newcon: | 0 | +11,912 | Shell-Seg 7,088 + Execute 4,676 [DOS] + NEWCON DevInfo |
| StartupII | 0 | +24,584 | residents Resident 2,656, List 9,936, CD 1,720 [DOS]; RAM handler process 1,388 + its code 6,428; ram:t, ram:env, ram:clipboards; T:, ENV:, CLIPS: assigns; SPEAK/AUX/PIPE DevInfo |
| path, MountMF | 0 | +3,776 | CrossDOS DevInfo DI0/DI1 and the TDPatch13 patch it installs (not further split) |
| LoadWB delay | +3,432 | +8,232 | Workbench process 5,204; icon.library base 160 + code 4,812 [HUNK]; Workbench backdrop window, icons (some in chip) |
| endcli (→ idle) | 0 | −13,280 | Initial CLI process 1,788, CON handler 2,988, AmigaDOS window, its layer and console unit, `Ask` |

## 5. Breakdown of the idle state (A/1, one drive, Workbench idle)

Total used inside the MemHeaders: **155,696 bytes** (chip 74,608, slow 81,088), plus 8,456 bytes outside them
(section 2).

### 5.1 By category

| Category | Bytes | Memory | How |
|----------|------:|--------|-----|
| Workbench screen bitplanes, 640 × 256 × 2 planes (PAL) | 40,960 | chip | [SCR] |
| trackdisk MFM buffer, DF0 | 16,388 (16,392 rounded) | chip | [TASK] trackdisk unit task's MemEntry |
| DF0 file system buffers: 5 default + 10 AddBuffers = 15 × 544 | 8,160 | chip | [DELTA] (AddBuffers, DF1) |
| Other chip (graphics boot block that starts with copinit: 5,560; WB copper list; Workbench ports and icon images placed in chip; pointer) | 9,096 | chip | [GAP], not split |
| ROM-module bases (libraries, devices, resources) incl. input.device task | 12,032 | slow | [LIST] |
| Resident commands (DOS list): Shell-Seg 7,088, List 9,936, Execute 4,676, Resident 2,656, CD 1,720, plus node overhead | 26,104 | slow | [DOS] |
| Disk code kept by programs: SetPatch 4,784, icon.library 4,812 (allocations rounded to 8) | 9,680 | slow | [HUNK] |
| RAM handler code (L:Ram-Handler) | 6,432 | slow | [TASK] process seglist |
| Task/process control blocks + stacks (table 5.3) | 8,672 | slow | [TASK] |
| Unattributed slow: FastFonts, CrossDOS/TDPatch13, DevInfo nodes and locks, BCPL global data of the File System, RAM: directories, Workbench window/layers/objects/DiskObjects, ports, IORequests | 18,168 | slow | [GAP] |

On C/1 the same items are all in chip (total used 155,752).

### 5.2 Library, device and resource bases ([LIST], `lib_NegSize + lib_PosSize`)

| Module | Neg | Pos | Total |
|--------|----:|----:|------:|
| exec.library | 630 | 588 | 1,218 (outside the MemHeaders, section 2) |
| expansion.library | 150 | 456 | 606 |
| graphics.library | 654 | 328 | 982 |
| layers.library | 174 | 42 | 216 |
| intuition.library | 468 | 1,380 | 1,848 |
| mathffp.library | 96 | 34 | 130 |
| romboot.library | 30 | 68 | 98 |
| dos.library | 222 | 124 | 346 |
| ramlib.library | 66 | 178 | 244 |
| icon.library (disk, LIBS:) | 108 | 46 | 154 |
| keyboard.device | 36 | 275 | 311 |
| gameport.device | 36 | 333 | 369 |
| timer.device | 54 | 214 | 268 |
| audio.device | 36 | 634 | 670 |
| input.device | 36 | 4,658 | 4,694 (contains the input.device task: TCB + 4,096-byte stack sit inside the device base, no separate allocation) |
| console.device | 48 | 184 | 232 |
| trackdisk.device | 36 | 168 | 204 |
| potgo / ciaa / ciab / disk / misc .resource | | | 59 / 148 / 148 / 174 / 62 |

keymap.resource is not Library-shaped in 1.3 (its NegSize/PosSize fields read as list data); it is small and not
counted.

### 5.3 Tasks and processes at Workbench idle ([TASK])

| Name | Kind | Pri | Stack | Block(s) owned (MemEntry) | Memory |
|------|------|----:|------:|---------------------------|--------|
| input.device | task | 20 | 4,096 | none (inside the device base) | slow |
| trackdisk.device (one per unit) | task | 5 | 512 | 412 (unit/TCB block) + 512 (stack) + **16,388 (MFM track buffer)** | buffer in chip, rest any |
| File System (one per floppy unit, ROM BCPL handler) | process | 10 | 840 | 1,028 (TCB + stack) | any |
| RAM (L:Ram-Handler) | process | 0 | 1,200 | 1,388 + code 6,428 | any |
| Workbench | process | 1 | 5,000 | 5,204 | any |
| Initial CLI (until endcli) | process | 0 | 1,600 (CLI default command stack 1,000) | 1,788 | any |
| CON handler of the initial window (until endcli) | process | 5 | 2,800 | 2,988 | any |

Notes:
- No separate Intuition task exists in 1.3; Intuition runs inside the input.device task.
- At the insert-disk screen there is also the boot task ("exec.library", 4,096-byte stack, 4,196-byte block); it is
  gone once DOS runs.
- The trackdisk MFM buffer is allocated per unit when the unit is opened; DF0's already exists at the insert-disk
  screen (stage 0 chip use = 46,288 bytes, of which 16,388 is this buffer); DF1's is allocated when DOS mounts DF1.
- DevInfo stack sizes as left by the system: DF0 600 (BCPL longword units), CON/RAW 700, RAM 300 before start.

### 5.4 Allocated chip regions at idle (A/1, [GAP])

| Region | Bytes | Content |
|--------|------:|---------|
| first block above the chip MemHeader start | 5,560 | allocated at boot before the trackdisk buffer; starts with graphics `copinit`; rest not identified |
| main block | 67,664 | trackdisk MFM buffer 16,392 + 2 bitplanes 2 × 20,480 + 10,312 other (15 FS buffers 8,160, WB copper list, Workbench ports and data) |
| small block | 1,384 | Workbench data placed in chip (allocated by LoadWB) |

## 6. Points worth noting for the comparison with KickSlopStart

1. **1.3 keeps exactly one raw track buffer per drive, 16,388 bytes, in chip RAM**, allocated when the unit is
   opened, even for an empty DF1. There is no decoded-track cache; caching is the file system's job.
2. **File system buffers are 544 bytes each and come from chip RAM** even when slow RAM is available and first in
   the memory list. Default 5 per floppy unit; the Workbench 1.3.3 startup-sequence adds 10 to DF0 (15 total).
3. **The Workbench 1.3.3 disk itself leaves about 36 KB of resident code, plus FastFonts and CrossDOS**: Shell-Seg, Execute, Resident, List, CD
   (26,104 with nodes), SetPatch (4,784), icon.library (4,812), FastFonts, CrossDOS/TDPatch13. These are disk
   choices, identical on any Kickstart that honours the same commands; a difference here would mean a difference in
   resident/LoadSeg behaviour, not in the OS footprint.
4. input.device's task lives inside the device base; Intuition has no task of its own.
5. ExecBase and the supervisor stack are placed in slow RAM when it exists (not counted by AvailMem).
6. The free total depends on the drive count by 23,432 bytes (section 3.3).
7. Fragmentation at idle (A/2): largest slow block 399,464 of 431,536 free; chip stays almost unfragmented
   (largest 428,984 of 429,512) because nearly every system allocation goes to slow RAM first, except display,
   track and file-system buffers.

## 7. Uncertain points

- The unattributed slow memory (18,168 bytes on A/1) is not split; FastFonts' and MountMF's own allocations were
  not isolated.
- The chip "other" amount (9,096 bytes beyond bitplanes, track buffer and FS buffers) is inferred by subtraction;
  only copinit's start position and the copper list of the Workbench view were identified directly.
- The file-system buffer size (544) and count are inferred from two independent deltas (AddBuffers 10 → +5,440
  chip; DF1 → 2,720 chip beyond its track buffer), not from walking the buffer list.
- Measurements are from one emulator (Amiberry, cycle-exact A500 preset, PAL). The idle figures were stable
  between 60 s and 170 s of idling.

## 8. Boot time to the Workbench (wall clock)

Measured 2026-11-08 on the real Kickstart 1.3 (34.5) under Amiberry: `amiberry-session start --analysis`, which runs
`--model A500` (OCS, PAL, 68000) and additionally forces `cpu_compatible`, `cpu_cycle_exact` and `cycle_exact`
(the emulator log reports "prefetch and cycle-exact 24-bit"). The A500 preset alone is already fully cycle-exact
(amiberry skill, checked 2026-11-04), so the figures are comparable with a ROM started with the plain preset.
Memory 512 KB chip + 512 KB slow, DF0 = a fresh copy of the unmodified
`Workbench 1.3.3 (34.34) - Boot (Commodore) (1991) [m2].adf` for each run, DF1 enabled and empty (preset default),
one emulator running at a time.

Method: t = 0 when `start` returns; every 2 s (on a fixed schedule from t = 0) `amiberry-session shot <name> x.png
--via ipc`; crop `230x16+78+38` of each picture; `compare -metric AE` against a crop of the idle desktop title bar
taken from the end of run 1 (about 130 s). The crop covers "Workbench release." and the first digits of the free
memory figure. A fourth run polled every 0.5 s to narrow the edges.

| Run | Poll | CLI window ("AmigaDOS") first seen | Title bar first seen | Crop identical to idle reference (AE = 0) |
|-----|------|------------------------------------|----------------------|-------------------------------------------|
| 1 | 2 s | 12.0 s | 70.0 s (prev. shot 68.0 s: CLI still open) | 72.0 s |
| 2 | 2 s | 12.0 s | 70.0 s (68.0 s: CLI) | 72.0 s |
| 3 | 2 s | 12.0 s | 70.0 s (68.0 s: CLI) | 72.0 s |
| 4 | 0.5 s | 11.5 s (11.0 s: not yet) | 69.0 s (68.5 s: CLI) | 71.0 s (70.5 s: not yet) |

Result: the Workbench title bar appears between **68.5 s and 69.0 s** after `start` returns; the three 2 s runs
are identical shot for shot (cycle-exact emulation is deterministic here, the spread is the poll period).

What the screen shows over time:

- About the first 2 s: blank (black at t = 0), then from 2.0-2.5 s a plain white screen (no insert-disk picture: the disk is already in DF0) until the CLI
  window opens at 11.0-11.5 s.
- The startup-sequence then runs in the "AmigaDOS" CLI window (version banner, CrossDOS banner, TDPatch13 lines,
  DI0:/DI1: mounted).
- **End of the startup-sequence**: the CLI window disappears in the same 0.5 s interval as the Workbench title bar
  appears (the title bar is the screen's own title, uncovered when the window closes); the RAM DISK and
  Workbench1.3 icons are already drawn in that first frame. So "title bar visible" and "startup-sequence window
  closed" are the same event at this resolution: 68.5-69.0 s.
- The first title bar reads 842,400 free memory; about 2 s later (70.5-71.0 s) it is redrawn with 860,992, the
  idle value (the memory released by the ending CLI). A comparison that requires AE = 0 against an idle reference
  therefore triggers about 2 s after the title bar first appears; one that only looks for the change away from the
  CLI window triggers at the first appearance.
- The serial port stays silent for the whole boot (0 bytes).

Uncertain: wall-clock figures assume Amiberry runs at real-time speed (no warp); the host was otherwise idle of
emulators but not of other processes.
