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
