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
