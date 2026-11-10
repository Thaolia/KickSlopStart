# Soft-kick disk on the real Kickstart 1.3 (black-box check)

Analysis-track page: behaviour observed only (screens, serial log, memory reads of ExecBase fields, a logging
instruction-fetch watch on our own image). No ROM addresses, no disassembly.

Note (implementation side, same day): this check used the first version of the disk, whose boot code booted the disk
normally when the image already ran, hence the green shell after each boot below. The boot code now fails in that
case, so the image shows its insert-disk screen instead; the paths through the real ROM are unchanged.

## Setup

- Emulator: headless Amiberry (v8.4.2) through `amiberry-session --analysis`, A500, 68000, not cycle-exact.
- ROM: the Commodore Kickstart 1.3 (34.5) image. DF0: `build/KickSlopStart.adf` as built (not rebuilt).
- Chip RAM 512 KB; slow RAM 512 KB (tests 1-2), 0 KB (test 3), 1024 KB (test 4).
- Our image is linked at `$C00000`; its cold-start entry is `$C000D2`. A logging watch on instruction fetches of
  `$C000D2` (set through IPC, survives resets) counts every entry into our image and records where the jump came
  from.
- ColdCapture = long at ExecBase + `$2A` (ExecBase = long at 4), read through IPC `READ_MEM`.
- Timings are wall-clock seconds of the emulator host, sampled with one screenshot per ~1.1 s.

## Test 1: first boot, slow 512 KB

- The real ROM boots the disk; our bootblock loads the image, which starts: serial
  `EXEC coldstart: overlay off, stack live (RAM)` 18 s after the session start, `E2 SHELL READY` 17.6 s later
  (about 36 s in total). Serial also reports `MEM SLOW KB=0200` (512 KB).
- Screen: green `AmigaSlopDOS` shell window with its prompt. The shell runs typed commands (`ver` answers
  `E2 SHELL ver OK ...`).
- ExecBase = `$1276` (our image's own low ExecBase), ColdCapture = `$C000D2`.
- **Pass.**

## Test 2: resets with our image resident (slow 512 KB)

| Reset | Watch hit on `$C000D2` | Screens after the reset | Our shell back after | ColdCapture after |
|---|---|---|---|---|
| IPC `RESET` (default) | yes, 1 hit, a jump from the ROM | green shell (fresh, responsive) | not timed (hit seen within 5 s) | `$C000D2` |
| IPC `RESET SOFT` | yes, 1 hit, a jump from the ROM | cyan at ~1 s, white ~2-8 s, then a fresh green shell (`ver` output gone) | ~9-10 s | `$C000D2` |
| Keyboard Ctrl+Amiga+Amiga (`input`, held 600 ms) | yes, 1 hit, a jump from the ROM | same sequence as `RESET SOFT` | ~9-10 s | `$C000D2` |
| IPC `RESET HARD` | yes, 1 hit, from chip RAM (the disk loader), not from the ROM | grey, white (~2-18 s), blue (~19 s, disk loading), cyan then white (~28 s), green shell | ~37 s | `$C000D2` |

- In the three warm resets the real ROM honoured ExecBase->ColdCapture (so ExecBase, its checksum fields and the
  ColdCapture vector re-armed by our image were all accepted) and jumped into our image without touching the disk:
  no Commodore insert-disk screen, no Commodore CLI.
- `RESET HARD` in Amiberry clears memory (power-cycle equivalent): the resident image is gone, the ROM goes through a
  full cold start and a normal disk boot, and our bootblock reloads the image. This is the expected fallback, not a
  failure.
- Serial after a reset: as expected from the known emulator quirk, the boot lines of our image are missing from the
  log after each reset, but later shell output (the `ver` echo and its reply) is logged. Screens and the fetch watch
  are the evidence for these tests.
- **Pass** (all four reset kinds end in our shell; the three warm ones go straight through ColdCapture).

## Test 3: slow 0 KB

- The bootblock refuses (no slow RAM at `$C00000`) and hands back to the ROM's normal disk boot: the standard
  Commodore `AmigaDOS` CLI window (Copyright 1987 Commodore-Amiga, Release 1.3, prompt `1>`) is up after ~8 s.
- No guru, no crash. The CLI is live: typing `cd` answers `Unknown command cd` (the volume has no `C:`).
- ExecBase is the ROM's own (not our `$1276`); ColdCapture = 0. Serial log empty (our image never ran).
- **Pass** (clean fallback).

## Test 4: slow 1024 KB

- Boot as in test 1: `(RAM)` line after 20.5 s, `E2 SHELL READY` 20 s later; serial `MEM SLOW KB=0400` (1024 KB);
  green shell on screen; ColdCapture = `$C000D2`.
- IPC `RESET`: one fetch-watch hit (a jump from the ROM), green shell back, ColdCapture = `$C000D2`.
- **Pass.**

## Conclusions

- The soft-kick works on the real Kickstart 1.3: the disk boots our image into slow RAM, and every warm reset
  (IPC default/soft, keyboard Ctrl+Amiga+Amiga) returns to our image through ColdCapture, which our image re-arms
  each time with a checksum the real ROM accepts.
- Without slow RAM the disk degrades to the ordinary Commodore boot (CLI), no crash.
- A memory-clearing reset reloads the image from the disk (about 37 s here), as designed.
- Point to check on the implementation side: our image reports the whole slow RAM size (`MEM SLOW KB=0200` /
  `0400`) although it occupies `$C00000`-`$C3FFFF` itself. Nothing went wrong in these short runs, but whether that
  256 KB is kept out of the free memory pool was not tested here (a long run with heavy allocations would show it).
  Implementation-side answer: `MEM SLOW KB` prints the detected size by design; under `RAMKICK` the slow MemHeader
  starts at `$C40000` (`SLOW_RSV`), and when the image boots the same disk again the bootblock finds
  `TypeOfMem($C20000) = 0` and falls back to a normal boot, which shows that the image area is not free memory.

## 2026-11-10: user report from a real A500 (SysInfo, Andromeda D.O.S.), replayed with the real ROM as host

Report: soft-kick disk v0.2.44 on a real A500 (Kickstart 1.3 in ROM, 512 KB chip + 512 KB slow at `$C00000`). After
the image started, (1) SysInfo: clicking MEMORY or BOARDS did nothing (the pointer still moved), and after SPEED then
EXPAND no key worked any more; (2) Andromeda D.O.S.: the "AmigaDOS"-style window frame drawn by the demo (its own
scenery, also shown by the real 1.3) was missing. Neither had been reproduced with our ROM as the host.

### Setup

- Headless Amiberry through `amiberry-session --analysis`, `--model A500` preset (68000, OCS, cycle-exact forced),
  `--slow 512`. Host ROM: the Commodore Kickstart 1.3 (34.5). DF0: the soft-kick ADF.
- Two images: the v0.2.44 disk the user ran, and the fix build of the same day (`v0.2.44-3-gc299d44-dirty` on its
  insert-disk screen). The v0.2.44 image was rebuilt from its tag with a link map: byte-identical to the image in the
  ADF.
- Disk swap after the insert-disk screen: IPC `EJECT_FLOPPY 0`, `INSERTFLOPPY <copy of the ADF> 0`.
- Mouse aimed in small steps, with the position checked through our own pointer variables (`PTR_X`/`PTR_Y` at
  `$684`/`$686`) and the window's `wd_MouseX/Y`; every click relied on was checked on an IPC screenshot.
- Comparison runs: our `build/kick13-prod.rom` (md5 `04b2acaf…`) as the host of the same soft-kick ADF, and as the ROM
  running Andromeda directly.

### Results

| Check | v0.2.44, real host | fix build, real host |
|---|---|---|
| Insert-disk screen | **Recoverable Alert `30000001`** (boot-error alert; the boot code refused the disk because the image already runs) shown first; dismissed with the left button (the 200 ms `click` of the harness did not do it; holds of 0.5-1.5 s did), then the insert-disk screen with the pointer visible | insert-disk screen directly, no alert |
| SysInfo starts after the swap | yes | yes |
| MEMORY | page shown: slow RAM header `$C40000`-`$C7EFFF` (252 KB, pri -5, "Fast Memory"), NEXT shows chip RAM 512 KB | same |
| BOARDS | "NO AUTOCONFIG BOARDS FOUND", EXIT back to the main page | same |
| SPEED | 543 Dhrystones, 0.56 Mips, chip speed 1.03, 7.09 MHz | 542 Dhrystones, same figures |
| EXPAND | toggles to SHRINK, graph rescaled | same |
| Keyboard afterwards | QUIT, then `dir` typed in the shell: echoed, `Unknown command dir` | same; keys typed while SysInfo was in front (also during the SPEED test) reached the shell after QUIT |

- **SysInfo symptoms: not reproduced** with either image. Two clicks first looked dead; in both cases the pointer
  hot spot (the arrow tip, which is the sprite's top-left corner, as expected) was 1 to 3 lines above the gadget
  (e.g. `wd_MouseY` = 187 against an EXIT gadget whose top edge is 188, or 173 against QUIT at 176-185) while the arrow
  body covered the button. Moving 4 lines down made the same click work. Intuition's state at that time was sound:
  the input task's event ring empty and consumed after each click, the SysInfo process waiting on its IDCMP signal
  (window `UserPort` with the right `mp_SigTask`/`mp_SigBit`, IDCMP `GADGETUP`), empty message list. A user who aims
  with the middle of the arrow could hit this on a small button, but it is the same on every host and on the real 1.3.
- **Andromeda: not reproduced.** Screenshots 15 s apart from 15 to 150 s after the insertion: the frame is visible
  in every picture with v0.2.44 (real host), the fix build (real host) and our ROM running the demo directly; the
  demo's scenes follow in the same order (frame alone, "Andromeda" eye, "D.O.S." logo, scroller), v0.2.44 a few
  seconds behind.

### Variants of the hardware, all with the real host and the fix build

| Variant | SysInfo MEMORY/BOARDS/SPEED/EXPAND/keys | Andromeda frame |
|---|---|---|
| Slow RAM above the image (`$C40000`-`$C7FFFF`) filled with random bytes at the first instruction of our image (what a real power-up leaves where the emulator has zeros) | all work | not run |
| ECS Agnus (8372A, `chipset=ecs_agnus`) | all work | visible |
| Full ECS (`chipset=ecs`) | not run | visible |
| `keyboard_handshake=302` (Amiberry logs every keyboard handshake shorter than 302 colour clocks, about 85 µs) | all work | — |

- Handshake log: the only short pulses (275 colour clocks, about 77 µs) were the two power-up codes acknowledged by
  the host ROM about 2 s after the start, long before our image runs. Our keyboard interrupt never produced a pulse
  under 85 µs (its delay loop is about 2560 CPU cycles, about 360 µs).
- An RTC (`rtc=MSM6242B`) could not be enabled: the A500 preset kept "Battery backed up clock (none)" in the memory
  map. SysInfo's "Clock" line (it polls `$DC0001` directly because no `battclock.resource` exists, see
  `sysinfo-44.md`) read FOUND in some runs and NOT FOUND in others with the same setup: it depends on the emulator's
  open-bus value, not on our image.

### Machine state at the first instruction of our image (`$C000D2`), real host vs our ROM as host

Hardware breakpoint on `$C000D2` (the bootblock jumps there directly: no 68000 `RESET` in between, so the CIAs and
the custom chips keep what the host left), registers read through IPC while gdb held the CPU.

| Register | Real 1.3 host | Our ROM as host |
|---|---|---|
| CIA-A PRA / DDRA / PRB / DDRB | `$FC` / `$03` / `$FF` / `$00` | same |
| CIA-A CRA / CRB | `$00` / `$08` (timer B one-shot, stopped) | same |
| CIA-B PRA / DDRA / PRB / DDRB | `$C7` / `$C0` / `$FF` / `$FF` | same |
| CIA-B CRA / CRB | `$00` / `$80` (TOD writes target the alarm) | same |
| DMACON / INTENA | `$0000` / `$0000` (the bootblock stub cleared them) | same |
| INTREQ | **`$2020`** (EXTER + VERTB) | `$0020` (VERTB) |
| CIA-A ICR (read once, which clears it) | `$00` | `$00` |
| CIA-B ICR (read once, which clears it) | **`$94`**: IR set, FLG (disk index) and ALRM (TOD alarm) pending | `$14`: FLG and ALRM pending, **IR clear** |
| ExecBase at entry (A6, long at 4) | `$C00276` | `$C00276` |

- The only difference: the real host leaves at least one of the CIA-B sources FLG / ALRM **enabled in the chip's ICR
  mask**, so CIA-B is already pulling INT6 (INTREQ EXTER) when our image starts. Our ROM as host leaves them
  disabled. (The mask itself cannot be read back; IR = 1 proves that an enabled flag is set.)
- Our image never puts the CIA ICR masks in a known state: `cia_init` (src/exec/cia.s) creates both resources with an
  all-clear software mask (`CIAR_ICRMASK`) and restarts the TODs, but writes nothing to either ICR. After a real reset
  the 8520s come up with all masks clear, so this only matters on the soft-kick path. With the real host, the chip
  keeps raising INT6 for every disk index pulse (whenever a drive motor turns) and for the TOD alarm, although no
  vector is attached: `cia_dispatch` reads the ICR (acknowledge) and latches those flags in `CIAR_PENDING`. When a
  later `AbleICR($80|FLG)` (trackdisk, disk.resource) enables FLG, `cia_retrig` fires at once for an index pulse that
  may be seconds old.
- In these emulated runs this difference had no visible effect (all checks above passed), so it is **not shown to be
  the cause** of the user's symptoms. It is the one hardware-state difference between the two hosts that the
  emulator exposes.

### Conclusions

- Neither symptom reproduces under emulation with the real Kickstart 1.3 as host (v0.2.44 or fix build, OCS or ECS
  Agnus, zeroed or random slow RAM). Differences left that the emulator does not model: the user's real keyboard and
  mouse, the real RAM board, an RTC if the trapdoor board has one, and the real drive.
- v0.2.44 on a real host always shows Recoverable Alert `30000001` before the insert-disk screen; the user must have
  dismissed it. The fix build no longer shows it.
- Implementation-side points from these runs:
  1. At coldstart, write `$7F` to both CIA ICRs (all sources disabled) and read each ICR once to drop stale flags,
     before the CIA resources are created, so that the hardware masks match `CIAR_ICRMASK`; also clear INTREQ EXTER
     and PORTS after that. On the soft-kick path the host's masks otherwise stay live.
  2. Do not latch flags read while their bit is disabled across the first `AbleICR` of a source that was never
     enabled since coldstart (or clear `CIAR_PENDING` for that bit before enabling it), so that a stale index pulse or
     alarm is not delivered.
- To go further on the real machine, a probe could report, on the serial line or on screen after the swap: the INT6
  count per second while the drive is idle, the CIA-B ICR read at the first `AbleICR`, and for SysInfo, after a dead
  MEMORY click, the window list, the SysInfo process's `tc_SigWait`/`tc_SigRecvd` and its IDCMP port (as read above
  through the debugger), plus `PTR_X`/`PTR_Y` against the gadget box, to tell a missed aim from a lost event.
