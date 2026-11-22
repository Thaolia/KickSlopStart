# Soft-kick into chip RAM from a Kickstart 3.1 host (black-box check)

Analysis-track page: behaviour observed only (screens, serial log, memory reads of ExecBase fields and free lists,
a logging instruction-fetch watch on our own image). No ROM addresses, no disassembly. Addresses below are inside
our image or in RAM, or ExecBase field values.

Companion page for the real Kickstart 1.3 host: `softkick-real-ks13.md`, section "2026-11-21".

## Subject

The soft-kick ADF (session copy of the disk whose original md5 is `e7882e57…`) with the chip-RAM fallback: when no
slow RAM covers `$C00000`-`$C3FFFF` and ExecBase->MaxLocMem is at least 1 MB, its boot code tries AllocAbs of
256 KB at (MaxLocMem - 256 KB) rounded down to 64 KB, then 64 KB lower each time down to `$80000`, relocates our
image into the first block it gets and jumps to it. The image puts its reset entry (image start + `$D2`) in
ColdCapture (ExecBase + `$2A`).

## Setup

- Headless Amiberry v8.4.2 through `amiberry-session --analysis`.
- Host ROM: `assets/kick40060.CD32`, a 512 KB Kickstart of the 3.1 family (its insert-disk screen reads
  "3.1 ROM 40.060, Copyright © 1985-1993 Commodore-Amiga, Inc."), used as a proxy for an A1200 with KS 3.x.
  No CD32 extended ROM was loaded.
- **Configuration that boots it from a floppy (first try, kept for every test)**: `--model A500` preset (as the
  script always passes it) with `--chip 2048 --slow 0 -- -s cpu_model=68020 -s chipset=aga
  -s cpu_24bit_addressing=false`. Amiberry reports `CPU=68020, FPU=0, MMU=0`, "~cycle-exact"; DF0 present (the
  preset's drive). The CD32 model with a floppy drive was therefore not tried.
- Memory read with IPC `READ_MEM` (ExecBase = long at 4; ColdCapture `+$2A`, SysStkUpper `+$36`, SysStkLower `+$3A`,
  MaxLocMem `+$3E`, MemList `+$142`); free lists walked through `mh_First`/`mc_Next`.
- Entries into our image: IPC logging fetch watch on the reset entry (`PAUSE`, `MONITOR "watch range 1b00d2 2 4 1 0
  0 0 0 1"`, `RESUME`, reset, `MONITOR "watch events"`), removed while paused at the end. "From the ROM" means the
  fetching instruction's PC lay inside the 512 KB Kickstart range; "from chip RAM" means it lay in low chip RAM (the
  disk's boot code). The 68020 logs these fetches as 4-byte accesses.
- Every screen named below was looked at (IPC screenshots, 752x574).

## B1: does 3.1 run our bootblock, and where does the image land?

3.1 state read in its own ExecBase before the bootblock ran (first boot, polled every second; and again 5 s after a
memory-clearing `RESET HARD`, emulation paused, black screen):

| Field | 3.1 host value |
|---|---|
| ExecBase (long at 4) | `$14B0` (`$758` for about one second during early init) |
| MaxLocMem | `$200000` (2 MB) |
| SysStkUpper / SysStkLower | **`$200000` / `$1FE800`** (6 KB supervisor stack at the very top of chip RAM) |
| ColdCapture | 0 |
| Chip MemHeader | attributes `$703`, `mh_Lower` `$420`, `mh_Upper` `$200000`, free `$1F6BA0` in **one chunk `$7C60`-`$1FE800`** |

- The header's upper bound covers the stack, but the free list stops at `$1FE800`: the stack area is not free.
- **Yes, 3.1 runs our bootblock** from DF0, and the image starts about 23 s after power-on.
- **ColdCapture = `$1B00D2`**: the image sits at `$1B0000`-`$1EFFFF`. The first candidate (`$1C0000`-`$1FFFFF`)
  overlaps the 3.1 supervisor stack and was not taken; **one 64 KB step lower was used**. Same placement on three
  loads (first boot, after `RESET HARD` with the disk in, and after re-inserting the disk on the 3.1 insert-disk
  screen).
- Once our image runs: its ExecBase is `$1276`, MaxLocMem `$200000` (its own sizing), supervisor stack
  `$2500`-`$3500`. Its chip MemHeader spans `$3500`-`$200000`; the free list has a hole exactly over the image (a
  chunk ends at `$1B0000`, the next one is `$1F0000`-`$1FFFFF`, 64 KB free above the image).
- **Pass.**

## B2: does our image run, and do resets come back to it?

- Serial: `EXEC coldstart: overlay off, stack live (RAM)`, `MEM SLOW KB=0000`, then the usual boot self-test lines
  up to `M6S BOOTSCR OK` and `M6R WIRED OK`; no FAIL line.
- Screen: our insert-disk (cat) screen with the soft-kick disk still in DF0 (the boot code refuses because the image
  already runs). **Pass.**

| Reset | Fetch-watch hit on `$1B00D2` | Screens after the reset | ColdCapture / ExecBase after |
|---|---|---|---|
| IPC `RESET` (default) | 1 hit, from the ROM | dark purple at 1 s, white at 4 and 10 s, cat screen at 25 s | `$1B00D2` / `$1276` |
| IPC `RESET SOFT` | 1 hit, from the ROM | white at 4 s, cat screen at 25 s | `$1B00D2` / `$1276` |
| IPC `RESET HARD`, disk in | 1 hit, from chip RAM (disk boot code), not from the ROM | 3.1 ExecBase `$14B0` at 5 s (black), white at 35 s, cat screen at 50 s | `$1B00D2` / `$1276` |
| IPC `RESET HARD`, DF0 empty | no hit | the 3.1 insert-disk screen (rainbow check mark, floppy picture, "3.1 ROM 40.060") at 20 s | ExecBase `$14B0` |

- In both warm resets the 3.1 ROM **honoured the ColdCapture vector of our V34 ExecBase** (which therefore passed
  3.1's ExecBase validity checks) and jumped into our image without reading the disk.
- A hard reset (memory cleared) **returns to 3.1**: with the disk in, 3.1 boots it and the bootblock reloads the
  image at the same place; with DF0 empty, 3.1 shows its own insert-disk screen.
- Not tested: the keyboard reset (Ctrl+Amiga+Amiga).
- **Pass.**

## B3: Workbench 1.3.3 on our image

- From the cat screen (image reloaded from the 3.1 insert-disk screen), DF0 swapped to a copy of the Workbench 1.3.3
  disk (IPC `EJECT_FLOPPY 0`, `INSERTFLOPPY`).
- Serial: `M6Y STRAP BOOTED OK`, `E2 SHELL READY`. At 90 s the AmigaSlopDOS window shows the startup-sequence output
  (release line, a date line `Saturday 21-Nov-26 …`, `[CLI 2]`, the trackdisk "Incorrect Revision" lines, devices
  mounted); a later screenshot (about 30-40 s after that) shows the **Workbench desktop**: title "Workbench release.
  1667624 free memory", RAM DISK and Workbench1.3 icons.
- ColdCapture still `$1B00D2` afterwards.
- **Pass.**

## Summary

| Question | Result |
|---|---|
| Configuration booting the 3.1 ROM from floppy | A500 preset + `cpu_model=68020`, `chipset=aga`, `cpu_24bit_addressing=false`, chip 2 MB, slow 0: works |
| B1 bootblock runs; placement | pass; image at `$1B0000` (ColdCapture `$1B00D2`), top 256 KB refused because 3.1's supervisor stack is at `$1FE800`-`$1FFFFF` |
| B2 image runs (serial + cat screen) | pass |
| B2 IPC `RESET` / `RESET SOFT` through ColdCapture | pass / pass (hit from the 3.1 ROM each time) |
| B2 hard reset returns to 3.1 | yes (3.1 insert-disk screen with DF0 empty; disk reload with the disk in) |
| B3 Workbench 1.3.3 | pass |

## Uncertain points and remarks

- Only the 3.1 CD32 main ROM (40.060) was used, without its extended ROM, on an A500-preset machine with a 68020 and
  AGA: an A1200 ROM of the 3.x family, an A1200 IDE controller, a 68020 with its cache settings, or fast RAM on a
  trapdoor board were not exercised. With fast RAM present, MaxLocMem still describes chip RAM only, so the same
  placement is expected, but this was not run.
- The date line in the startup-sequence output of B3 (where the 1.3 host run of A1 printed "Battery Backed up Clock
  not found") was seen although Amiberry's memory map listed "Battery backed up clock (none)". Its source was not
  investigated.
- Timings are wall-clock seconds of the emulator host, sampled by single screenshots; they only bound when a screen
  was reached.
- On both hosts (1.3 with 1 MB, 3.1 with 2 MB) the top candidate block is always refused because the ROM keeps its
  6 KB supervisor stack at the top of chip RAM, so the image always lands 64 KB lower and leaves the top 64 KB free in
  our image's pool. This is consistent with the design (it falls back step by step) and not a failure.

## A600-like machine (68000, ECS, 1 MB chip), 3.1 host

Date: 2026-11-22. Disk: `build/KickSlopStart.adf` v0.2.69 (sha256 `e252b7d2…d52e608`, checked), used through a session
copy. Host ROM: the same `assets/kick40060.CD32` (3.1, 40.060). Chip 1 MB, no slow RAM, no fast RAM, DF0 only, no
hard disk.

### A1: does the 3.1 ROM run on a 68000?

- **Not testable in Amiberry: the emulator itself refuses this ROM on a 68000.** Every 68000 attempt (Amiberry's
  `--model A600` preset; `chipset=ecs` + `chipset_compatible=A600`; plain A500 preset with chip 512 KB; `chipset=ecs`
  without cycle-exact; and 68000 + `chipset=aga`) and the 68010 (`cpu_model=68010` + `chipset=ecs`) never produced a
  single emulated frame: IPC answered `PING` but `SCREENSHOT` failed, the GDB server never started (it is polled from
  the emulation loop), and the host process spun at full CPU until the start timeout (also with a 150 s timeout).
- Cause, from the emulator's sources (not from the ROM): Amiberry identifies this image in its ROM database as
  "CD32 KS ROM v3.1" and, when the database marks a Kickstart as needing a 68020/68EC020, it calls `notify_user`
  ("The selected system ROM requires a 68020 or later CPU") and restarts the emulation instead of running it. With
  `use_gui=no` that becomes an endless restart. So **nothing was observed of the ROM on a 68000**; whether this
  particular 3.1 image would run on a real 68000 remains **unknown** from this test bench.
- Single change needed: **CPU 68000 -> 68020**. With `cpu_model=68020` (24-bit addressing kept, i.e. a 68EC020-like
  part), OCS or ECS, 1 MB or 2 MB chip, the ROM starts at once, with 24-bit or 32-bit addressing. The chipset (OCS/ECS/AGA)
  made no difference to the refusal on a 68000.

### Configuration used for A2-A5 (closest to an A600 that runs)

```
amiberry-session start --analysis --rom <path>/assets/kick40060.CD32 --adf build/KickSlopStart.adf \
  --chip 1024 --slow 0 -- -s chipset=ecs -s chipset_compatible=A600 -s cpu_model=68020 -s cpu_24bit_addressing=true
```

- Amiberry log: `CPU=68020, FPU=0, MMU=0, JIT=0. ~cycle-exact 24-bit`, chipset mask 3 (ECS Agnus + ECS Denise).
- `chipset_compatible=A600` turns on, per the emulator's sources, Gayle IDE (A600/A1200 type), PCMCIA, the A600 CIA
  types and the Kickstart mirror at `$A80000`. The memory map shows "Gayle (low)" at `$D80000` and `$DD0000`,
  "Gayle (high)" at `$DE0000`, "Battery backed up clock (none)". No IDE drive, no PCMCIA card.
- Only departure from an A600: the 68EC020-like CPU instead of the 68000.

### A2: bootblock, placement, image start

- 3.1 state (its ExecBase `$14B0`, polled from 1 s after power-on): MaxLocMem `$100000`, SysStkUpper `$100000`,
  SysStkLower `$FE800` (6 KB supervisor stack at the top of chip RAM, as with 2 MB).
- Chip free list of 3.1, read while paused 4 s after a `RESET HARD`, when the bootblock had already taken its block:
  MemHeader attributes `$703`, `mh_Lower` `$420`, `mh_Upper` `$100000`, free `$AD3F8` in two chunks, `$11408`-`$B0000`
  and `$F0000`-`$FE800`. So the **free list ends at `$FE800`**, and the hole `$B0000`-`$EFFFF` is the block the boot
  code allocated.
- **ColdCapture = `$B00D2`** (image at `$B0000`-`$EFFFF`): the top candidate `$C0000` overlaps the stack, one 64 KB
  step lower was used. Same on three loads. The image starts about 15 s after power-on.
- Serial: `EXEC coldstart: overlay off, stack live (RAM)`, `MEM SLOW KB=0000`, self-test lines up to `M6R WIRED OK`,
  no FAIL. Our ExecBase `$1276`, its MaxLocMem `$100000`, its stack `$2500`-`$3500`; its chip free list ends a chunk at
  `$B0000` and has `$F0000`-`$FFFFF` free (the image area is not in its pool).
- Screen: cat insert-disk screen, version line `v0.2.69`. **Pass.**

### A3: resets

| Reset | Fetch-watch hit on `$B00D2` | Screen | ColdCapture / ExecBase after |
|---|---|---|---|
| IPC `RESET` | 1, from the ROM | cat screen at 25 s | `$B00D2` / `$1276` |
| IPC `RESET SOFT` | 1, from the ROM | cat screen at 25 s | `$B00D2` / `$1276` |
| IPC `RESET HARD`, disk in | 1, from chip RAM (disk boot code) | 3.1 runs (ExecBase `$14B0` at 4 s), cat screen at 50 s | `$B00D2` / `$1276` |
| IPC `RESET HARD`, DF0 empty | none | 3.1 insert-disk screen ("3.1 ROM 40.060") at 20 s | ExecBase `$14B0` |

**Pass**: warm resets return to our image through ColdCapture; a hard reset returns to 3.1.

### A4: Workbench 1.3.3

- After re-inserting the soft-kick disk on the 3.1 screen (image reloaded, ColdCapture `$B00D2`), DF0 swapped to a copy
  of the Workbench 1.3.3 disk: `E2 SHELL READY` 9 s after the insertion; screenshot at 109 s shows the **Workbench
  desktop**, title "Workbench release. **619072 free memory**", RAM DISK and Workbench1.3 icons (the same figure as
  the 1 MB chip run on the real 1.3 host). ColdCapture still `$B00D2` at the end. **Pass.**

### A5: Gayle IDE / PCMCIA present

- With Gayle IDE and PCMCIA enabled (no drive, no card), every step above passed; no FAIL line on serial, no alert,
  no hang. **Pass** (absence of trouble only: our image was not checked for doing anything with the Gayle hardware).

### Uncertain points

- The 68000 itself was never exercised with this ROM (emulator refusal, above). Our image ran here on a 68EC020-like
  CPU; it was not run on a 68000 with a 3.x host in this series. On the real 1.3 host it runs on a 68000
  (`softkick-real-ks13.md`).
- A real A600 ships with Kickstart 2.05 (37.x); a 3.1 A600 ROM was not available, so the CD32 3.1 ROM stands in for
  it. A 2.05 host was not tested.

## Soft-kick with the IDE hard disk on an A600-like machine, 3.1 host

Date: 2026-11-22. Question: does our image (now with an IDE `scsi.device` for the Gayle port that mounts RDB partitions,
and an FFS-capable ROM filesystem) work when soft-kicked from a 3.1 host whose own `scsi.device` has already read the
RDB and set up the partitions before our bootblock runs?

### Setup

- Soft-kick disk: `build/KickSlopStart.adf` (sha256 `e1f08975…`, checked; a production build, its screen reads
  `v0.2.69-2-g…-dirty`), session copy.
- Hard disk: a copy of a 32 MiB RDB image. Partitions (from `rdbtool`): `DH0` cylinders 1-1023, DOS1 (FFS), bootable,
  boot priority 0, volume "Work" with `hello.txt` (19 bytes) and `big.bin` (150,000 bytes); `DH1` cylinders 1024-2046,
  DOS0 (OFS), not bootable, volume "Data" with `hello.txt` and `big.bin`. **Before the run, `big.bin` was deleted from
  DH1 in the copy** (host-side, `xdftool … open part=1 + delete big.bin`), so that its presence afterwards proves the
  write by our image. The original image file was never written.
- Test disk: a copy of the Workbench 1.3.3 test disk whose startup-sequence is `echo "P4 BEGIN"`,
  `type DH0:hello.txt`, `copy DH0:big.bin DH1:big.bin`, `copy DH0:big.bin RAM:big.bin`, `info`, `echo "P4 END"`.
- Host and machine: `assets/kick40060.CD32` (3.1, 40.060), the A600-like configuration of the previous section plus
  the IDE drive:

```
amiberry-session start --analysis --rom <path>/assets/kick40060.CD32 --adf build/KickSlopStart.adf \
  --chip 1024 --slow 0 -- -s chipset=ecs -s chipset_compatible=A600 -s cpu_model=68020 -s cpu_24bit_addressing=true \
  -s ide=a600/a1200 -s "hardfile2=rw,DH0:<copy of the hdf>,0,0,0,512,0,,ide0_mainboard"
```

  Amiberry log: `CPU=68020 … ~cycle-exact 24-bit`, "Adding IDE HD 'ide_mb' unit 0, controller 0", the HDF opened
  read/write, 32 MB.

### Q1: 3.1 sees the drive first; our bootblock still runs

- Emulation paused a few seconds after power-on, 3.1 ExecBase `$14B0`, ColdCapture 0 (before our bootblock):
  - device list: gameport, timer, keyboard, input, ramdrive, trackdisk, carddisk, **scsi.device**, console;
  - library list: no dos.library yet (the floppy bootblock had not run);
  - expansion.library's mount list (BootNodes, name taken from each DeviceNode): `DF0` pri 5, `CC0` pri 3 (PCMCIA),
    **`DH0` pri 0**, `DF1` pri -10, **`DH1` pri -128**. So 3.1 had already read the RDB and created both partitions'
    nodes, with DH0 bootable at priority 0 and DH1 at -128 (not bootable).
- DF0 (priority 5) wins: our bootblock runs, the image starts about 15 s after power-on. **ColdCapture = `$B00D2`**
  (image at `$B0000`, as without the drive). Serial: `EXEC coldstart: overlay off, stack live (RAM)`,
  `MEM SLOW KB=0000`, then `IDE UNIT 000000010000`, `IDE MOUNT DH0`, `IDE MOUNT DH1`; no FAIL line.
- Screen: the cat insert-disk screen. **Pass.**

### Q2: test disk on our image, data written to DH1

- DF0 swapped to the test disk copy. Screens: at 20 s only `P4 BEGIN` in the AmigaSlopDOS window; at 40 s the run is
  complete:

```
P4 BEGIN
hello from DH0 ffs
Mounted disks:
Unit      Size    Used    Free Full Errs   Status   Name
RAM:      155K     310       0 100%   0  Read/Write RAM DISK
DF0:      880K    1430     328  81%   0  Read/Write Workbench1.3
DF1:      No disk Present
DH0:       16M     310   32424   0%   0  Read/Write Work
DH1:       16M     325   32409   0%   0  Read/Write Data
Volumes available:
RAM DISK [Mounted]  Data [Mounted]  Work [Mounted]  Workbench1.3 [Mounted]
P4 END
1>
```

  (volume lines condensed here; on screen one per line).
- Host check of the HDF copy (snapshot while running, and again after the session stopped): DH1 lists
  `big.bin` 150,000 bytes again; its md5 (`ca5dcee4…`) equals DH0's `big.bin` and the original file, `cmp` reports
  them identical. Bitmap counts from `xdftool … bitmap info`: DH0 310 used / 32424 free, DH1 325 used / 32409 free,
  the same as Info's Used/Free columns. DH0 is unchanged (FFS, read only by the script). **Pass.**

### Q3: resets

| Reset | Fetch-watch hit on `$B00D2` | Screens | Result |
|---|---|---|---|
| IPC `RESET`, test disk in DF0 | 1, from the ROM | fresh window, script re-run: P4 BEGIN, hello, Info with DH0/DH1 (same figures), P4 END at 70 s | pass; ColdCapture `$B00D2` |
| IPC `RESET SOFT`, test disk in DF0 | 1, from the ROM | empty window at 30 s, full run with DH0/DH1 rows and P4 END at 70 s | pass; ColdCapture `$B00D2` |
| IPC `RESET HARD`, soft-kick disk in DF0 | 1, from chip RAM (disk boot code) | 3.1 running at 3 s (ExecBase `$14B0`, ColdCapture 0, black), then cat screen | pass; image reloaded at `$B0000` |
| then test disk again | — | full run, DH0/DH1 rows identical, P4 END | pass |

After the warm resets the script copied `big.bin` to DH1 again (overwrite); the final host check above was made after
all of them.

### Q4: hangs, requesters, alerts

- None seen in any screenshot of this series (cat screens, the AmigaSlopDOS window, the 3.1 boot); no "Not a DOS disk"
  requester for DH0 (FFS) or DH1, no software failure, no recoverable alert. Serial shows no FAIL line. **Pass.**

### Uncertain points

- 3.1's own use of the drive was observed through its BootNode list and `scsi.device` in its device list, not by
  watching IDE register traffic; whether 3.1 left the drive in a particular state (e.g. a pending command) was not
  examined. Our image's IDE driver found unit 0 and mounted both partitions anyway.
- Dates: the files and the Data volume written by our image carry a 2026-11-22 03:37 time stamp (from `xdftool`
  listings), earlier than the wall-clock time of the run (about 03:50). Where our image's clock started from (no RTC
  on this configuration) was not investigated.
- The CPU is a 68EC020-like part, not a 68000 (see the previous section); a real A600 ships with Kickstart 2.05, not
  tested.
- Only the A600/A1200 Gayle IDE with a single drive (master, unit 0) and one RDB layout (two partitions, 512-byte
  blocks) was exercised.
