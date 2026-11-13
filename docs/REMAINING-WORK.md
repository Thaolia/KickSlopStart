# Remaining work for Kickstart 1.3 parity

State at `e6d7bcb` (2026-11-08). This page lists what our ROM still lacks **beyond the presence of the LVOs**.

## How this inventory was made

- **Sources read:**
  - the "Open points", "Implementation gaps" and "Deviations" sections of the `docs/analysis/` pages (42 sections);
  - the "Open:" notes and deliberate-difference lists of `docs/PLAN.md`;
  - `docs/ARCHITECTURE.md`.
- **Filtering:** an item is dropped when a later PLAN entry or `src/` shows it as done.
- **Tags:** **[src]** means the gap was confirmed in `src/`; **[doc]** means it comes from the docs only.
- **Sizes:** S = small, M = medium, L = large.
- **Clean-room:** implementation side only. The Commodore ROM was not read for this page.

## Summary

- **LVOs:** 386 of the 390 V34 LVOs have a dedicated routine, and none is a stub (`docs/analysis/coverage-v34.md` §0).
  - The 4 null vectors have no known caller: graphicsPrivate1/2 (already stubs in 1.3) and dos GetPacket/QueuePacket.
- **Device commands:** all 80 are implemented, as are timer.device and audio.device.
- **Ranked gaps:** all 15 ranks of coverage-v34 §7 are specified, implemented and checked by probes.
- **Residents:** 22 of the 24 are complete; romboot.library and strap are partial.
- **Where the work is:** mostly **workbench.task**, plus behaviour details listed in the specs' open points.

## A. Gaps that break or visibly change a known program

### A1. Workbench 1.3.3: dropping an icon into another window — done 2026-11-09

Done (workbench-task-v34 §10.2-§10.4): the target comes from the pointer hot spot; drawer, trashcan or disk icon ->
into that directory (position NO_ICON_POSITION); background of another drawer window -> there, at the drop point;
same volume = rename of the object and its .info, other volume = copy under the same name; the .info is rewritten at
the drop; "Error while moving <name>: 203" when the name exists on the same volume; a disk or trashcan never leaves
its window; a window that is not ours refuses the drop. An icon dropped on the backdrop is left out there (kept in
memory only, as in 1.3: not written to disk) and can be launched from there or dropped back into a window; a disk
dropped on another disk starts DiskCopy with FROM = the dragged disk and TO = the target (§10.6). A drop on a disk or
drawer icon whose window is open places the icon in a free slot of that window (§10.5's grid, checked against its
test vectors; the rule itself is still marked [S] in the spec), and the busy pointer (an hourglass drawn for this
project) is shown during a drop, Empty Trash and the opening of icons (§11). While DiskCopy runs, the inhibited drives show "DF0:BUSY" /
"DF1:BUSY" device icons (any non-DOS disk gets its "DFn:<type>" icon), placed as probed on 1.3 (V15/V16).

### A2. Workbench 1.3.3: Disk menu — done 2026-11-09

Empty Trash empties the selected trashcan (the ".info" icon-list file stays) and Initialize starts SYS:System/Format
on the selected disk with the 1.3 WBArgs (§10.9). The menu items are enabled or ghosted from the selection (§10.8).

### A3. Workbench 1.3.3: extended selection — done 2026-11-09

Shift+click adds an icon, a press with Shift held moves the whole selection (in its window or into another directory,
each icon by the same delta), a double-click opens every selected icon, and the menus follow the "several icons"
row of §10.8. Intuition now gives MOUSEBUTTONS (and every IntuiMessage) the qualifier of the input event, and
gameport's system mouse events carry the keyboard's qualifiers (C9's "MOUSEBUTTONS carries qualifier 0" is fixed).
Discard of several icons asks for each one in turn, then re-reads the windows. Shift+click adds icons of other
windows too; Open, Snapshot, Discard and a group drag work on the whole selection (§10.7 did not test this case on
1.3: a group released on the background of the drag's own window only repositions that window's icons). The "button
held" qualifier bits of mouse events are not set yet.

### A4. Workbench 1.3.3: menu ghosting — done 2026-11-09 (single selection)

### A5. Boot time — done 2026-11-09; Clock speed — pass 2 and total done 2026-11-13, pass 1 open — [src], S

- **Boot:** the Workbench title bar of Workbench 1.3.3 now appears after 61.7 s (two runs), against 68.5–69.0 s on
  the real 1.3 and 71.0–71.3 s before. Cause: the file system fetched the current data block again from trackdisk at
  every READ, and the CLI reads `s/Startup-Sequence` in small pieces (818 of the boot's 1,460 block reads were its two
  data blocks). Each READ now reuses the block already in the handle's buffer (`SS_BUFBLK`, `src/dos/ofs.s`).
  PLAN "Boot time (2026-11-09)".
- Clock's speed parity with 1.3 is still open (PLAN "Drawing acceleration"). 1.3 baselines (wb12-demos §3,
  2026-11-11): growing the Workbench 1.2 Clock from 170 × 105 to 300 × 200 takes 38 frames from the button release
  to the last EndRefresh (one refresh pass per message), a per-second tick 1.94-2.10 frames at 300 × 200. Ours,
  same method and production ROM (2026-11-11): NEWSIZE pass 20.0 frames (1.3: 15.1), REFRESHWINDOW pass 12.7
  (10.4), release to last EndRefresh 48.8 (38; the first poll came 16 frames after the release, 1.3: 11.7). The
  passes are 1.2-1.3 times slower. A PC-sampling profile of the two passes (trace build `PCPROF`, 2026-11-12)
  shows no single hot spot: Clock's own code about 18 % of the busy time, the line path (Draw set-up, ClipRect
  walk, blitter set-up) about 25 %, waits for the blitter about 7 %, the rest spread over area fill, text and exec.
  Re-measured after the line changes of 2026-11-12: unchanged (20.0 / 12.4 frames; Clock's SIMPLE window uses the
  direct Draw path, which those changes do not touch). SizeLayer starts 2.5 frames after the release (1.3: 1);
  the wait for Clock's first poll depends on its 10-frame Delay phase on both ROMs. Then (2026-11-12, third pass):
  the copies that ClipBlit makes during the resize, before Clock's first poll (300 × 80, 130 × 105 and 170 × 105
  pixels, two planes), ran on the CPU row by row because `br_blit` took only word-aligned sources; it now takes any
  source whose phase in its word is not beyond the destination's (B shift = destination phase - source phase):
  release to last EndRefresh 48.4 → 44.5 frames, first poll 15.9 → 12.1 (1.3: 11.7), Clock pixel-identical, and
  `tests/bltrp_probe.sh` checks every pixel of 122 such copies (a ROM with the old shift fails it). Measured and
  ruled out the same day: the clip walk (0.5 ClipRect per generic line), the line set-up before the blitter wait
  (no change), letting `dl_fast` take lines between BeginRefresh and EndRefresh (pass 2 12.4 → 12.9). Of the 456
  Draw calls of the two passes, 222 take the direct path, 222 the generic one (layer being refreshed) and 12 are
  horizontal. Left: the passes themselves, still 20.0 / 12.4 frames (1.3: 15.1 / 10.4).
- 2026-11-13 (`src/graphics/draw.s`): a Draw into a layer with no ClipRect and no SuperBitMap whose lock the
  caller holds (BeginRefresh with an empty damage) only updates cp and the pattern counter, as the generic path
  does when nothing is drawn; BltTemplate takes the blitter at any size (Clock's 12 dial diamonds went through the
  CPU loop); the line engine computes each plane's minterm before waiting for the previous plane and keeps
  CON1/APT/SIZE in registers; Forbid/Permit inline in `dr_directdraw` (Permit's vector only when a reschedule is
  due). Clock, production ROM, same harness: pass 1 19.8 → 18.6 frames (1.3: 15.1), pass 2 12.4 → 6.8 (10.4),
  release to last EndRefresh 43.3 → 36.4 (38); ticks unchanged. drawcheck, lineclip, graster (156 vectors) and
  settled Clock screenshots identical to HEAD. Left: pass 1 = 228 Draw calls at about 2,800 colour clocks each
  (entry and clip tests ~580, bitmap and minterm checks ~300, blitter ownership ~270, set-up ~460, blitter waits
  ~300); parity needs a leaner dedicated Draw path.

### A6. Memory — [src], M — Shell gap closed to 416 bytes 2026-11-10

- **Shell cost:** opening a Shell from the Workbench takes 33,896 bytes here (35,944 before, 47,152 at the start of
  2026-11-09), against 33,480 on 1.3 (newshell-memory-v34 §2): `CP_STKEXTRA` 2048 -> 1024 for the Background CLI and
  the NEWCON handler (and every other BCPL process or handler). Their 68000 side used at most 668 (NEWCON) and 516
  (Background CLI) bytes in a long Shell session with a "No disk present" requester, `Run`, `type`, `copy`,
  `newshell`/`endcli` (868 at most in the 2026-11-09 measurement), and more than 1,500 bytes of their BCPL part stay
  untouched under that. The remaining 416 bytes are not chased further.
- **Idle desktop:** 1,024 bytes more than before (the RAM handler's stack): about 13,384 above 1.3 (860,992). Since
  2026-11-12 the Workbench allocates a drawer record only while its window is open: 5,480 bytes back at idle
  (Workbench 1.3.3, one drive: 860,424 → 865,904 free; open/close cycles end at the same value). The floppy file
  system stacks went from 4,096 to 3,072 bytes after measuring their deepest use (1,687 bytes, with a "You MUST
  replace volume" requester opened by the handler; 521 otherwise): → 867,952 free, 7,528 bytes in all.
- **RAM handler stack (measured 2026-11-12, kept):** 2,220 bytes (`DN_STACKSIZE` 300 longs + `CP_STKEXTRA`). After
  eight nested directories, a copy of `c` into the deepest, `dir all`, `rename`, `protect` and `delete all` on
  RAM:, its BCPL frames reached 384 bytes from the bottom and our 68000 runtime 161 bytes from the top: 545 bytes,
  less than 1.3's 1,200-byte stack. Shrinking it would give back about 1,000 bytes, but the 2026-11-09 measurement
  saw 868 bytes at the top of a BCPL process stack, so the margin stays.
- **Command stacks of the ROM shell (fixed 2026-11-12):** the shell that runs the startup-sequence gave a command
  only `cli_DefaultStack` bytes, while `runcommand` adds `RC_STKEXTRA` (2,048) for our runtime's 68000 side.
  `delete ram:a all quiet` on eight nested directories needs 4,440 bytes of BCPL frames plus 876 at the top: with
  the default 4,000 it ended in a SOFTWARE FAILURE. The real 1.3 overflows too, one level later: `delete ... all`
  survives 5 levels at the default stack and crashes or hangs from 6 (dos-cli §7, probed 2026-11-12); ours stopped
  at 5 (hang) before the fix. The shell now adds the same margin (`RC_STKEXTRA`, `dos.i`): 8 levels pass, a
  deliberate leniency over 1.3.
- **Reduction candidates:** listed in `docs/MEMORY-USAGE.md`.

### A7. Workbench 1.2 Lines and Clock — mostly done 2026-11-10, Lines within 2.5 % of 1.3 since 2026-11-12

`docs/analysis/wb12-demos-v34.md`, probed on the real 1.3:
- Clock (SIMPLE_REFRESH): shrinking and growing it with the size gadget on the Workbench 1.2 disk leaves no sliver
  on our ROM (checked on screenshots, 2026-11-10); the resized SIMPLE layer is already cleared and damaged since the
  #10 work.
- Lines draws 431 lines per second on 1.3. Each line is one Move + one Draw, solid, JAM2; 81 % lie inside one
  SuperClipRect, 19 % are split into two or three pieces (wb12-demos §3.1, 2026-11-11). Since 2026-11-10 each
  clipped piece goes to the blitter (`ln_cblit`), pixel-identical to the CPU walk. Ours went from 93 to 274 lines per
  emulated second. A profile (2026-11-12) showed 36 % of the time waiting for the blitter at the end of every
  blitted line: `lb_core` now hands the blitter back while the last plane is still drawing, as a V34 Draw does, and
  the next user waits first (`ln_draw` included). Lines: +19 % on the same trace build (229 → 273 Draw calls per
  emulated second with the sampling interrupt running), pixels unchanged (`tests/lineclip_probe.sh`). Then
  (2026-11-12, second pass): `db_enter` checks the planes against ExecBase MaxLocMem instead of a TypeOfMem walk at
  every blit, and Draw skips the direct path of a SuperBitMap layer before taking its lock (it used to lock, give
  up and lock again in the generic path): 273 → 314 on the trace build, `lineclip` 229 → 215 ticks, same pixels.
  Then the lean layered line path (2026-11-12, measured on the production ROM over the same 5,000 Draw calls of
  Lines, frames counted with the debugger): `dl_fast` draws a line whose two ends lie in one usable ClipRect with a
  single context set-up and one `lb_core` blit (371.8 → 386.8 lines per second); the layer lock and the blitter
  semaphore take an inline path when nobody else holds them (→ 393.3, → 404.6); a line `dl_fast` cannot take after
  setting up its context goes to the generic engine with that context (→ 408-410). 1.3: 431. Clock is unchanged
  (passes 19.9 / 12.4 frames, as before: lines drawn between BeginRefresh and EndRefresh skip `dl_fast`). Then
  (2026-11-12, third pass) `lb_core` computes BLTSIZE and BLTAPT once per line and each plane's minterm and address
  before waiting for the previous plane, so the blitter idles less between the two planes: 416.2 / 413.3 → 419.7 /
  421.0 lines per second (production ROM, two runs each), same pixels (`lineclip`, `gline`). Left: about 2.5 %; a
  profile shows 29 % of the time waiting for the blitter, which 1.3 waits for too.
- Found on the way: an internal blitter user (`gfx_tryblitter`, ScrollRaster's blit) did not count itself in GfxBase
  BlitLock while DisownBlitter took one off, so BlitLock drifted (−15,588 after a minute of Lines; 1.3 shows −1 at
  rest, graphics-blitter §3). Fixed: `tests/gline_probe.sh` L7 now reads blitlock FFFF (the previous ROM FFD0).
- Lines is GIMMEZEROZERO | SUPER_BITMAP, so it cannot show the frame-copy case: only programs with non-GZZ
  SUPER_BITMAP windows meet our missing frame copy (intuition-gzz §2.5).

### A8. Real A500 with Workbench 1.2: right button flicker and frozen pointer — [doc], unknown size

A badly seated mouse is suspected. Retest first; if it persists, try the same mouse on the real 1.3. Source: PLAN
"First run on real hardware".

### A9. Bubble Bobble: not a gap (2026-11-10)

memory-budget §9: the 177,152-byte block is the game's own MEMF_CHIP allocation and is made on our ROM too (the old
measurement lost it); the 9,876 bytes are 1.3 LoadSeg's short-lived getvec buffer for a 2,467-offset RELOC32 group,
which our LoadSeg does not need (it relocates while reading).

### A10. Cluedo — done 2026-11-10

`docs/analysis/cluedo-v34.md`, dos-lvo-partial §1.1a: every dos LVO returns D1 = D0 and A0 = 0 (now applied to all of
them through relays in the vector table, Exit, Execute and DateStamp excepted); after the game steps the head itself
(35 outward pulses on DF0), 1.3's trackdisk seeks from the cylinder it remembers, reads the wrong track four times,
then recalibrates and succeeds, silently. Ours recalibrates after the first wrong track (TDU_CYLOK), same outcome.

### A11. Workbench window and icon placement (issue #39) — done 2026-11-12

"China Challenge III" has no Disk.info and one icon without position: its window opened at 10, 20, 400 × 120 with
the icon on top of the other one. workbench-task §8.6 (probed on the real 1.3): default window 50, 50, 400 × 100,
remembered while the volume's icon lives; icons without position placed in 96-pixel columns from the left. Ours
now does the same: CC3 at 117, 0 (read with the debugger, as on 1.3), the window back where it was dragged after a
close; the Workbench 1.3.3 window is pixel-identical to v0.2.50.

### A12. "Software error - task held" requester — done 2026-11-13

Spec `docs/analysis/task-held-v34.md` (probed on the real 1.3). Every process dos creates (`proc_create`) now has
dos's trap handler in tc_TrapCode (`dos_trap`, `src/dos/dos_lib.s`): after exec's usual SOFTWARE FAILURE report on
the serial port, the faulting process resumes in user mode in `dos_taskheld`, which opens the 320 x 72 "System
Request" "Software error - task held / Finish ALL disk activity / Select CANCEL to reset/debug" (Retry / Cancel)
through `vr_req`; Retry shows it again (the process never resumes), Cancel gives the Guru #<vector>.<process>. A
plain exec task, a process with pr_WindowPtr = -1 or with exec's TaskTrapCode, and an exception in supervisor mode
take exec's Guru path at once. `tests/taskheld_probe.sh` (screenshots) checks T1 and T4-T8 of the spec: illegal
instruction (Retry, then Cancel), divide by zero (Guru #00000005), a command started with Run (second number = the
Background CLI), pr_WindowPtr = -1, TaskTrapCode, a plain task. Kept: after Cancel our Guru is shown at once
whatever memory ExecBase is in (1.3 resets first and shows it at the next boot when ExecBase is in slow RAM,
alert-v34 §1.1).

### A13. Dev ROM stalls under JST 0.8c and Gamebench — [doc], unknown size — half explained (2026-11-13)

With `build/kick13.rom` (dev), JST 0.8c needs minutes to reach the Cadaver demo and Gamebench's `wait 20` after
`run GameBench` never ends; the production ROM behaves like 1.3. A/B by the analysis track
(`docs/WHDLoad/jst-host-requirements.md`, "A/B of 2026-11-13"), with a dev build whose level-6 test handler
(`m7_int6_probe`, `src/exec/boot.s`) no longer re-arms CIA-B timer A at every interrupt: Cadaver then comes as fast
as on the production ROM (11 s), so the continuous level-6 source of the dev harness is that cause. Gamebench still
never ends on both dev builds: its busy-looping AMOS process runs with ExecBase TDNestCnt at 0 (one Forbid level
held), so the `wait 20` shell never gets the CPU; the code that takes that base Forbid level is not found yet (only
nested 0 -> 1 -> 0 pairs were seen). Dev ROM only; the earlier "every CPU sample in interrupt code" was partly an
artefact of attaching the debugger (it stops inside the VBlank interrupt).

### A14. Boot CLI prompt `> ` instead of `1> ` — done 2026-11-13

The boot CLI's loop wrote a fixed `> ` and never read cli_Prompt, so the Prompt command had no effect there either.
Its CLI structure now starts with the prompt `%N> ` and the loop prints cli_Prompt through the same formatter as
the other CLIs (`cli_fmtprompt`, `src/dos/shell.s`): `1> ` after a startup-sequence of one `echo`, `W1> ` after
`prompt "W%N> "` (screenshots, production ROM). 1.3's NewCLI copies the parent's prompt as ours does; the
`2> ` seen on Workbench 1.3.3 comes from its `s/CLI-Startup`, which sets `%N> ` (`bcpl-runtime-v34.md`).

### A15. PAL A500 sometimes detected as NTSC — [src], S — open (2026-11-13)

Seen during the A5 measurements: 2 of 6 plain boots of the production ROM under Amiberry (A500 PAL, no debugger)
came up NTSC (GfxBase DisplayFlags = 1, Clock's window 170 × 89, pointer stopped at line 199). Suspected cause, not
confirmed: `gfx_detect_std` (`src/graphics/graphics_lib.s`) decides NTSC as soon as the beam wraps below line 50
after being above 100 without having been seen above 270, so any interruption of the loop longer than about 41
lines (~2.6 ms) gives NTSC. vAmigaWeb and Amiberry users would see it.

## B. Deliberate deviations

These are not work unless a doc says they should change.

- **Theme:** CDE colours, a purple pointer and our own boot art.
- **Track cache:** 4 slots, released under memory pressure. 1.3 has no cache.
- **Input:** one input task replaces the keyboard feeder process.
- **Validator:** runs in ROM inside the handler, instead of `L:Disk-Validator`. It also rebuilds a bitmap with a bad
  checksum and follows bitmap extension blocks.
- **V34 defects not reproduced:**
  - RectFill: reversed bounds draw nothing, and there is no 64-word / 1024-row truncation.
  - ScrollRaster: negative corners are clamped.
  - RawDoFmt: stops at the NUL.
  - CloseLibrary(NULL) returns 0.
  - Allocations whose size rounds to 0 fail; AllocEntry with 0 entries; AddSemaphore uses A1.
  - GELs: four V34 defects are not reproduced.
  - AndRectRegion: MaxX/MaxY follow the real rectangle.
  - SIMPLE-layer damage is exact.
- **intuition windows:**
  - Move/Size/ToFront/ToBack and the close-time activation run at once (1.3 defers them).
  - Windows are kept on the screen.
  - CloseWindow ends the window's requesters.
- **Console resize:** each unit checks its window size at its next write.
- **ramlib:**
  - libraries are searched as "LIBS:" + name;
  - ROM libraries are never expunged;
  - there is no ramlib node and no SetFunction patches.
- **Interrupts:**
  - every pending source of a level is served per entry (1.3 serves one and is re-interrupted), and VERTB is
    acknowledged before its chain;
  - PORTS/EXTER are acknowledged before the server chain;
  - unclaimed sources are acknowledged;
  - SetIntVector(NULL) stores 0.
- **Coldstart:** InitCode(RTF_COLDSTART) runs in supervisor mode before the first task; only CoolCapture is called
  in user mode as on 1.3.
- **Drives:** no unit task polls for disk changes (the handler's 1 s tick does it); the decoder keeps the good
  sectors across retries where 1.3 fails the whole read; de_SizeBlock other than 128 on a 512-byte device is "Not a
  DOS disk" where 1.3 says "Error validating disk / Key n checksum error" (rom-filesystem §8.7, only reachable with a
  patched environment, and which check fails on 1.3 is not established).
- **MrgCop:** an SHF list too small is reallocated (1.3 overflows it into the LOF list, gels §13.7).
- **VERTB cost:** gameport's input injection and unit emulation run in the VERTB server.
- **Small ones:**
  - input.device CMD_CLEAR replies 0.
  - GetPacket/QueuePacket are null.
  - alert.hook's role is played from the boot code.
  - The initial CLI stack is 8192 bytes (1600 on 1.3).
  - Debug has no ROM-Wack behind it.
- **Not a ROM fault:** on the soft-kick disk, Spaceballs and Desert Dream reset back to the real Kickstart, because
  they overwrite slow RAM or `$4`.

## C. Missing or partial features with no known victim (most impactful first)

### C1. Ejection with unwritten tracks — done 2026-11-09

Probed on 1.3 (disk-change §2.2.1 point 2): a disk ejected with only a pending write-back is lost silently, and the
"You MUST replace volume / <name> / in unit  n !!!" requester (Retry / Cancel) appears only for an ejection during a
transfer. Ours shows it whenever the volume was modified since its last write-back, because our data tracks wait in
trackdisk's cache for the same 2-3 s (maintainer decision): Retry with the disk back writes everything, Cancel drops
it and the next mount revalidates the disk. trackdisk keeps modified tracks across a disk change until the file
system writes them or sends CMD_CLEAR.

### C2. trackdisk DMA buffer — done 2026-11-09

The MFM buffer of the disk DMA (13,630 bytes of chip, the size of an encoded track) is allocated once when
trackdisk initialises and kept, for reads and for track writes, so a game that fills chip RAM keeps its disk access.
1.3 keeps one 16,388-byte buffer per opened drive; ours is shared by all drives (one access at a time).

### C3. Menus — done 2026-11-09

NextSelect chain, MENUTOGGLED, MutualExclude, drag-selection with the left button, HIGHBOX and HIGHIMAGE
(intuition-input-menus §3.6-§3.9), checked with `tests/menucat.s` against the §5 vectors (steps 3-5). Since
2026-11-12 the working flags of a window's menu strip are also reset when the window is activated (§1.11 step 3,
`mn_actclr`; `tests/explvo_probe.sh` "EXP MACT 00000000 00000000", the previous ROM kept $0100 / $7000).

### C4. Display — done 2026-11-10

- DIW/DDF, fine scroll, clipping, modulos and the colour count (ncol, SPRITES colours) follow graphics-display
  §4.2-4.4 (`tests/mvport_probe.sh`, the 13 probed rows equal).
- MrgCop merges the streams of all ViewPorts by line (fragment, VSprites, UCopList read directly), with the §5.2 tie
  rule, the line-255 crossing and repeated WAITs dropped (`tests/mrgcop_probe.sh`, nine cases of §5.2-5.4 and §7.3).
- The insert-disk picture shows its middle 216 lines on NTSC, logo whole.
- The pointer counts interlaced lines since the high-resolution pointer units (2026-11-09, v0.2.35).
- Since 2026-11-12 MrgCop leaves the View's lists alone when no ViewPort has a CopList (§5.1;
  `tests/mrgcop_probe.sh` "MC KEEP 00000001", the previous ROM rebuilt the list). ClrIns is not merged (we never
  build one).

### C5. exec scheduling — done 2026-11-10

Signal and AddTask reschedule when the task becomes the head of TaskReady, AUTOINIT goes through
AddLibrary/AddDevice/AddResource, WaitIO returns the signal bit in D1 (2026-11-09). Since 2026-11-10 timer.device
counts the quantum (Elapsed/TQE, never a preemption in the production ROM; the dev ROM keeps a round-robin server for
its spinning demo tasks), software interrupts run at SR $2000 with SOFTINT masked, and Signal returns the previous
tc_SigRecvd. Cause queues in the five ExecBase SoftInts lists by `LN_PRI and $F0` and the SOFTINT server runs the
head of the highest non-empty one, rescanning after each call (exec-scheduling §8); priorities outside -32..+47,
which make 1.3 write outside the array, are clamped. `tests/sched_probe.sh` checks it all (order CEBDFA).

### C6. strap — done 2026-11-09

The strap runs in the initial task, in user mode with multitasking on, as on 1.3; a floppy inserted on the
insert-disk screen gets a new attempt without a reset; a bootblock returning D0 ≠ 0 gets Alert $30000001 before
the insert-disk screen (uae-hd-boot §3). Side effect: the soft-kick disk left in DF0: shows that alert once per
soft-kicked boot, as 1.3 would. The dev ROM booted with no disk at all reaches the insert-disk screen too since
2026-11-10: its D3 test clients, which read files of the test disk, are created only when a floppy is present
(before, their Open raised the "No disk present" requester and held the boot).

### C7. Drives and file system — [src] partly, S

Done 2026-11-09: DF2: and DF3: are mounted, writes to DF1: are exercised by `tests/writeback_probe.sh`, ExNext is
stateless (rom-filesystem §4), locks of an ejected volume go to `dl_LockList` and come back to the drive that sees
the disk again.
Done 2026-11-10: files over 65,535 data blocks (block counts and positions divided in two steps,
`tests/bigfile_probe.sh`: a 33.6 MB file on a 40 MiB partition read, sought and rewritten in place); each modified
bitmap block moves to a newly allocated block at the write-back, the old one freed and the root's entry updated
(`tests/writeback_probe.sh`: DF1 bitmap 881 -> 1429); an open FileHandle whose disk moves to another drive stays with
the handler that opened it, as on 1.3 (disk-change §2.4.1): every access waits behind "Please replace volume /
<name> / in unit  n" naming that handler's unit, even while another drive holds the volume, and resumes once the disk
is back in that drive (`tests/fhmove_probe.sh`). Until then a refused READ/WRITE/SEEK (Res1 = -1) never reached the
requester and failed at once with 218. Writes through a FINDINPUT (MODE_OLDFILE) handle are accepted as on 1.3
(§5.1): the first WRITE opens the file in place at the read position and that write state serves the handle from
then on (`tests/oldwrite_probe.sh`); they used to fail with 212. Block sizes: 1.3 only ever transfers 512 bytes at key × 512 (rom-filesystem
§8.7, probed 2026-11-10), so a partition of 1024- or 2048-byte sectors is "Unreadable Disk" / "Not a DOS disk" there
and here; until then this handler refused to open such a device and the partition looked empty ("No disk present").
Cancel on the "in unit  n" requester already ended the call at once, which a single-call probe of 1.3 confirms
(disk-change §2.4.1 point 6: the second requester seen with `Type`/`Copy` is the program's next call); what differed
was the close: an END on a file whose volume is out of its drive is now refused like READ/WRITE, so Close shows
"Please replace volume … in unit  n" and, after a Retry with the disk back, writes the file; a Cancel resends the END
marked as given up and the handle is freed with nothing written. The handler of every partition mounted by its
driver now starts during the Initial CLI set-up, as on 1.3 (rom-filesystem §1.4): the first `Info` lists
"DH0: 10M 7 20471 0% 0 Read/Write Work", or "DH0: Unreadable Disk" with no requester at boot. Left in the file
system:
- de_SizeBlock other than 128 is kept as a deviation (section B).
- IoErr 286 (disk-change §2.4.2, probed 2026-11-11): 1.3's file system ends the READ it held during "You MUST
  replace volume" with -1 / 286 after Cancel. Ours raises that requester between packets, so since 2026-11-11 a
  READ or WRITE already queued when it is cancelled gets -1 / 286 (`HC_CX286`, `src/dos/handler.s`); not staged
  by a test (our ejection only meets a queued transfer by chance).

### C8. console.device — done 2026-11-09

Each unit has its own 255-byte input ring (one more for the readers without a window), CMD_READ with io_Length 0
replies −4, MULTIBROADCAST events go to every unit, and a write keeps the unit's copy of the RastPort state
(cu_Mask … cu_TxSpacing) and leaves the window's RastPort as the program set it (console-keymap §2.2, §6).
`tests/concmd_probe.sh`: ZERO FC, RING FF (255 bytes), RP 03 02.

### C9. intuition leftovers — S each

- String gadgets: STRINGCENTER/STRINGRIGHT padding, GADGHBOX/GADGHIMAGE/GADGHNONE cursors, the spaces left past the
  NUL (which also leaves the ghost pattern outside the text cells of an edited disabled gadget, checked on the probe
  screenshot) and ActivateGadget's activation at the next input event: done 2026-11-09 (`tests/strg_probe.sh`,
  intuition-strgad §1.2, §4.3-4.4).
- AddGadget of a REQGADGET gadget goes to the window list: kept, the spec leaves this case undefined on 1.3 and
  allows it (intuition-gadgets §2).
- IDCMP ports named "IDCMP" in the public port list, REFRESHWINDOW sent at each repair while one is unread, and the
  Workbench drawers on the desktop's shared IDCMP port: done 2026-11-09 (`tests/iwin_probe.sh` step 4 `inl`; port
  list read with gdb through Shell and drawer open/close).
- IND_WRITEEVENT pointer events, event timestamps, keyboard mouse, background click, empty bar, MENUPICK IAddress,
  HIGHITEM after a check change, high-resolution pointer positions, and the time / qualifier / mouse position of
  the activation messages a program causes (OpenWindow, ActivateWindow, CloseWindow: input-menus §1.10, probed
  with `CT` lines and step A2): done 2026-11-09 (`tests/imenu_probe.s`; read its serial log with the "w" wait marks
  stripped). Since 2026-11-10 the whole log matches the 1.3 log of the same probe line by line (IAddress 0 for the
  verifications and the menu-close MENUUP, menu shortcut time / qualifier / MENUPICK position, keyboard-mouse
  MOUSEMOVE qualifiers, SetMenuStrip's JazzX/JazzY/BeatX/BeatY), apart from real tick times and the addresses of
  the RAWKEY / VANILLAKEY copies.
- it_scrxy's TopEdge and the menu texts' character width: already handled (screen chosen by TopEdge since the stacked
  screens of 2026-11-03; menus in the screen font with the native `test-intuition-menufont` since PR #29).
- Preferences: RowSizeChange and ColumnSizeChange applied once (system-configuration) to NormalDisplayRows/Columns,
  the Workbench screen and the pointer bounds, done 2026-11-10 (+16/+32: screen 672 × 272, pointer to 671 × 543,
  only 640 columns displayed with the default ViewXOffset; the real 1.3 shows the same, probed the same day:
  intuition-prefs §3.3).

### C10. graphics leftovers — S each

Done 2026-11-10: GfxBase BlitLock, CloseFont of a removed font (replied once, at 0 accessors, NT_FREEMSG without a
port), ClipBlit's ClipRect order and same-BitMap pieces (`tests/clipblit_probe.sh`). rp_minterms are read by
RectFill and the line engines since PRs #30/#32.
Done the same day: QBSBlit waits (busy, as long as the VBlank server runs) until the beam reaches `bn_BeamSync` before
it queues like QBlit; Text takes its line buffer from `rp_TmpRas` when it is large enough, and allocates one
otherwise; a VSprite partly above its ViewPort was already clipped (`tests/gels_probe.sh` vector G9c, gels §5.8);
the gameport VERTB server returns at once when nothing moved, which brings the end of the VERTB chain from line 19 to
line 14 and WaitTOF's earliest return from line 18 to 16 (1.3: 12; `tests/waittof_probe.sh`); a clipped line piece
starts at the first point whose major coordinate is inside its ClipRect instead of walking from the line's start
(`tests/lineclip_probe.sh`: same pixels, 24 % less time for 1,000 patterned lines in a covered window). Later the
same day: a VSprite's VSTART is its clipped top plus the View's DyOffset only, without the ViewPort's DyOffset or a
LACE halving (gels §5.8; vector G9d: LACE ViewPort with DyOffset 20 gives POS $3659 / CTL $3B01 as G9a). Since 2026-11-11 patterned lines use the blitter's line mode too: LinePtrn is the texture in B, BSH starts it at the
bit the CPU walk would use (LN_PH, or linpatcnt − major coordinate + C for a clipped piece), and Agnus walks it one
bit per pixel downwards as `ln_plot` does (`tests/lineclip_probe.sh`: same plane fingerprints, 1,150 → 390 ticks;
`tests/gline_probe.sh`: same output as the previous ROM). ONE_DOT and the COMPLEMENT first dot keep the CPU walk.
Kept: the rest of the VERTB cost is gameport's input injection and unit emulation, which 1.3 does not run there
(section B).
Open (found 2026-11-12): `tests/graster_probe.sh` gives 3 FAIL on v0.2.53 and v0.2.54, all horizontal ScrollRaster in
a layer ("L d -3,-2,2,1,40,20", "L d 2,0,0,0,45,24", "L d 2,1,0,0,45,24": pixels near the right or left edge of the
scrolled area), after 0 FAIL in an earlier run (PLAN line "rawdofmt (205) and graster (156) probes 0 FAIL"). Bisect
from that commit before changing `sr_horiz`.
Fixed 2026-11-13: bisected to 7b06a34, where ClipBlit within one RastPort started re-sorting the layer's ClipRect
list (`cb_sort`). ScrollRaster had cached the list head in DC_FIRST before its ClipBlit moves, so the strip fill
walked from a ClipRect now in the middle of the list and skipped those sorted before it. `sr_move` reloads DC_FIRST
from the layer after its copies; graster_probe 156 vectors, 0 FAIL.

### C11. Coldstart — done 2026-11-11

LED toggle after ColdCapture, RAM zeroed on the cold path, and no self-test while KickMem areas must survive. Since
2026-11-11 CoolCapture runs in user mode as on 1.3 (coldstart-hardware §4.4), A6 = ExecBase, on a 4 KB stack of its
own; Supervisor() brings the boot back (`cool_call`, `src/exec/boot.s`). `tests/kicktag_test.s` stores the SR it
saw: $0000 after a warm reset (the previous ROM: $2000). InitCode(RTF_COLDSTART) itself still runs in supervisor
mode (section B).

### C12. Paula autovectors — done 2026-11-11

INTEN test at entry, 1.3 service order, 22-byte chain headers (custom-chips §3.3). Since 2026-11-11 EXTER (INT6)
is a server chain holding ciab.resource at priority 0, as on 1.3: a program's AddIntServer(INTB_EXTER) joins it
instead of replacing the CIA-B dispatcher (`tests/explvo_probe.sh` "EXP INT6 00000002 00000001"; the previous ROM:
1 server). Serving every pending source per entry and acknowledging VERTB before its chain are kept (section B).

### C13. trackdisk — done 2026-11-10 but one point

TD_FORMAT without a floppy: 29 before anything is cached. Later the same day, from the analysis track's probes
(trackdisk-write §10, raw-changeint §13):
- TD_MOTOR: io_Length 0 off, any other value on at once; io_Actual = previous state $FF / 0; io_Error always 0.
- Read codes: the first defect met in rotation order wins; 27 when the first sector found has a bad header, 22 when
  the preamble or syncs are missing at the 1088-byte pitch after a good sector (`tests/td_decode_test.py`: two new
  cases, 0 failures). Our decoder still keeps the good sectors across retries, where 1.3 fails the whole read.
Kept deliberately:
- Sector labels: none are stored; ETD_READ never fills iotd_SecLabel, as on 1.3, but ETD_WRITE writes zero labels where
  1.3 writes the constant $AAAAAAAA ×4 (only a raw read of the track can see it).
- Write protection is checked at CMD_WRITE (28 at once); 1.3 fills its single track buffer and fails at the flush,
  then every other track fails with 28 until CMD_CLEAR. Our multi-track cache has no such stuck state.
- The motor-off timer: 1.3's trackdisk has none, its file system sends TD_MOTOR 0; ours only does after a write-back.
Kept (section B): no unit task for change polling (the handler's 1 s tick does it), and the decoder keeps the good
sectors across retries where 1.3 fails the whole read.

### C14. dos — done 2026-11-10

- Retry after a 218 refusal of a lock: once the volume is mounted again, in any drive, the packet goes to the handler
  that has it now (its locks were handed over), without a requester when that happened meanwhile; until then it went
  back to the refusing handler, which refused again. 1.3 restarts the whole call (dos-lvo-partial §1.4); with a
  lock argument that reaches the same handler. A FileHandle stays with its own handler (§2.4.1).
- OpenLibrary returns with the condition codes of D0 (2026-11-11, issue #35): Paccer's `CLS` does `movea.l d0,a6`
  then `beq`, and stopped the game's startup-sequence since v0.2.20 because the flags left by Permit said zero.
  `tests/explvo_probe.sh` "EXP OLZ 000000FF" (the previous ROM: 0000FFFF). Paccer reaches its game screen and plays.
- The mouse moves the pointer while a dos requester is up on a CLI-only boot (checked 2026-11-10 with Cancel clicks
  on "Please replace volume" over the boot CLI).
- The GV that bcpl_starthandler makes for a handler goes into the handler process's tc_MemEntry, so RemTask frees it
  when the handler ends (1.3's endtask frees a pr_GlobVec other than dl_GV); a shared or inherited GV is never
  freed. Eight `echo >newcon:…` opening and closing NEWCON windows: no loss (the previous ROM lost 186 bytes each).

### C15. CPU — done 2026-11-12

`docs/analysis/cpu-fpu-v34.md`, probed on the real 1.3 (68000 to 68040, with and without 68881/68882): AttnFlags
$13 with an FPU (a 68030/68040 reads as a 68020, any FPU as a 68881), CACR 1 on a 68020/68030, the FPU state of each
task saved below its integer context. Ours now does the same: `tests/fpuctx_probe.sh` passes on 68000, 68020,
68020 + 68881, 68030 + 68882 and 68040 (two tasks of the same priority keep their FP0-FP7 and FPCR across about 60
switches; a ROM without the save shows 15 bad rounds per task). Both ROMs already reached the Workbench 1.3.3 desktop
on a 68030 and a 68040 under Amiberry. `make kick-a1200` builds the 512 KB image (the ROM twice); it boots the
Workbench 1.3.3 disk on a 68020 + 68882 with AGA and 2 MB of chip RAM. The exception table now covers vectors 2-23
and 32-47 as on 1.3 (12-23 used to be left alone) and clears 48-63, which 1.3 leaves zero for SetPatch to fill (§4.3).
Not covered: Amiberry emulates neither the 68040's data cache nor its missing FPU instructions, so a real 68040
board stays untested.
Source: issue #20.

## D. Analysis-side gaps that block implementation

These need a spec or a probe on the real ROM first, run by an analysis agent.

### D1. Workbench selection and menu rules — done

Specified and implemented with A3/A4 (2026-11-09).

### D2. VSprite allocation by band in DrawGList — done 2026-11-11

graphics-gels §13: G9c/G9d on 1.3 match ours; MrgCop already emits the `$F000|reg` MOVEs as `reg & $1FE` and halves
the VSprite WAITs of a LACE ViewPort. §13.7 (2026-11-11) settles the last point: 1.3's MrgCop reuses an existing SHF
list whatever its size and overflows into the LOF list, a 1.3 defect; ours sizes both lists (kept, section B).

### D3. Empty Trash and Initialize — done

Specified and implemented (`wb_emptytrash`, `wb_initialize`, `src/dos/workbench.s`).

### D4. File system — specified 2026-11-10

rom-filesystem §2.5.1-§2.5.2, §5.2, §12. Applied: "Key n already set" for a block met twice (was "already used");
Retry on "Disk structure corrupt" already restarted the validation; READ checks each data block's checksum and fails
with Res2 296, which dos shows as "Volume / <name> / has a read/write error" (Copy then prints "Error while Reading"),
and no longer stops at a block whose type is not DATA (1.3 ignores the type). Kept: a bad bitmap checksum under a
valid flag is repaired here, where 1.3 stops with "Key n checksum error" and leaves the volume "Validating". Not
testable: a device rejecting TD_CHANGESTATE/PROTSTATUS/CHANGENUM. An ejection with a write-back pending loses it
silently on 1.3 (disk-change §2.2.1); ours asks "You MUST replace volume" instead (C1, maintainer decision).

### D5. trackdisk — specified 2026-11-10

Decoder rules for codes 21-27 and write protection running: trackdisk-write §10 (see C13).

### D6. Smaller questions — done 2026-11-10

- Cluedo: A10.
- S:, L:, FONTS:, DEVS:, LIBS: get a lock-0 assign when the directory is missing, SYS: is always a root lock, in the
  order S L C FONTS DEVS LIBS SYS (dos-boot-sequence.md): already so here.
- Left Amiga + B = Cancel and Left Amiga + V = Retry on dos requesters, only while the requester window is active
  (dos-lvo-partial §1.4): already so here (sysreq.s).
- MouseX/MouseY of every window of the screen follow the pointer, and GZZMouseX/Y = MouseX/Y − BorderLeft/BorderTop
  for every window, not only GIMMEZEROZERO ones (intuition-input-menus §1.4): the latter fixed here.

### D7. The 28 partly specified LVOs — done 2026-11-10

All specified (exec-partial-lvos-v34.md, graphics-raster §10, intuition-misc §6b-6c; coverage-v34 390/390) and
aligned here: AllocSignal(-1) from bit 31 down and a low byte of $FF meaning "any", AllocTrap's 32-bit register (14
first, 16-31 testing the caller's d1), AddTask setting tc_SigAlloc/tc_TrapAlloc from ExecBase TaskSigAlloc
($0000FFFF) / TaskTrapAlloc ($8000) and clearing tc_TrapAble, GetCC keeping d0's upper word, SetSR leaving the old SR
in a0, Insert after a list's tail sentinel (it wrote to location 4 before), FindTask also matching the running task,
MakeFunctions choosing its format from funcDispBase, InitStruct clearing (size & $FFFF) / 2 words and not realigning
after a byte repeat (size code 11: alert $81000007), InitBitMap leaving Flags/pad/Planes, AllocRaster
CHIP|PUBLIC, graphicsPrivate1/2 returning a6, BeginRefresh under LockLayerInfo with WINDOWREFRESH and the GZZ border
layer locked, EndRefresh's word `complete` and LAYERREFRESH, AllocRemember nodes with requirements 0 and
FreeRemember's word `reallyForget`. `tests/explvo_probe.sh`: EXPLVO OK (the previous ROM crashed in Insert).
Kept: FreeRaster(NULL) is ignored (1.3: dead-end alert); SetFunction keeps its Forbid.

### D8. Probes described but never written — done 2026-11-12

Run on the real ROM by the analysis track on 2026-11-10 and 2026-11-11 (pages updated, each marked [O]):
- mathffp probe: 264 checks, 0 failures. rawdofmt probe: R3/R4 were artefacts of the probe's own PutChProcs, R5
  shows that 1.3 RawDoFmt does not save D7 (ours restoring it is harmless); `rawdofmt_check.py check13` now expects
  that.
- exec-messages-io probe (§8a): its OL16 fake Open no longer clobbers A2 (that crashes OpenLibrary on 1.3);
  `exec_msgio_check.py check13` follows the ramlib values (D0 = 16 for CD1/RD1/CL1/RL1, OD5's A0); timer.device
  sets `ln_Type` 5 on TR_GETSYSTIME as 1.3 does (IO5). Our ROM: 131 vectors, 0 failures.
- `tests/dosmisc_probe.sh` (new, dos-lvo-partial §4 items 2, 3, 7, dos-memory §8 P1, P3) prints the same lines as
  the real 1.3 since 2026-11-11 (`DOSMISC OK`): a negative Delay waits as long as the timer allows (1.3 never came
  back within 30 minutes; ours used to return at once), DISK_INFO's id_InUse is the head of the lock list (was 0),
  and a hunk header with size bits 31-30 = 11 fails with 103 (1.3 asks AllocMem for flag 8 and never reads the
  attribute long; ours said 121). Seek on the console, RAW:, NEWCON:, after a buffered read, Info into a buffer + 2,
  UnLoadSeg(0) and LoadSeg of a missing file already matched.
- dos-lvo-partial §4 items 1, 4, 5, 6 (T22–T26); dos-memory P4 re-measured (no Shell leak, the 56 bytes were an
  IntuiMessage of the disk window), P5, P6. OpenLibrary and AllocMem return their flags for D0 on 1.3 (EXP OLZ).
- dos-memory P2 (2026-11-12, debugger-injected getvec on the real 1.3): getvec(−1) allocates a 4-byte header,
  sizes (n+2)×4 ≤ 0 fail with pr_Result2 = 103 without allocating. Ours refused every n < 0 and left Result2;
  since 2026-11-12 `rt_getvec_raw` / `g_getvec` follow 1.3 (no automatic test: a BCPL call is needed).
- Done 2026-11-10: the exec-partial-lvos §8 probe, as `tests/explvo_probe.sh` (with the graphics §10 and intuition
  §6c vectors).

### D9. Real-hardware points — observed in emulation 2026-11-12

- Recoverable Alert without slow RAM: on the real 1.3 (`--slow 0`) it shows, returns D0 = 1 on the left button and
  the system goes on (alert-v34 §6); ours gives the same screen and the same return (coldhw mode 2 under Amiberry).
  The FS-UAE freeze seen earlier was an emulator artefact. Left for real hardware only.
- SIZEVERIFY and DMRequest are now observed black-box on the real 1.3 (intuition-input-menus §2.5, §3.12): the
  input task waits for the reply with no time-out and the drag/requester only starts after it, as ours does.

## Test ADFs (`assets/test_adf/`) on our ROM

### No documented failure

- **Workbench 1.3.3:** boots; its remaining gaps are A1–A6.
- **Workbench 1.2:** reaches its desktop (A7, A8).
- **Applications:**
  - SysInfo and OctaMED v4 work.
  - Directory Opus 4.12 runs.
  - Deluxe Paint III v3.00 (since PR #28, 2026-11-08): reaches the paint screen, quits to the CLI and can be run
    again. Selected requester gadgets show their text (format chooser checked on a screenshot, 2026-11-12; fixed
    by the RectFill minterm work of 2026-11-09). The picture under a menu stays as on 1.3 (2026-11-12, menu box
    save/restore).
- **Games:**
  - Holiday Lemmings: menu and a playable level. The Lemmings demo works too.
  - Caesar reaches its game menu.
  - Monkey Island disk 1: the intro returns to the Workbench, and the title screen opens from the CLI. Disk 4 is not
    a boot disk.
  - SimCity reaches its menu.
  - Zool behaves as on 1.3 (fire on port 2).
  - Tintin and Shanghai run.
  - Bubble Bobble runs (A9: not a gap).
  - Cluedo reaches player selection (A10).
- **Demos:**
  - Spaceballs, Desert Dream and Sanity-Arte run.
  - Andromeda "D.O.S.": fixed in `2a86dda`. The "AmigaDOS" frame shown during the demo is its own artwork.

### Partly documented

- **Scooby-Doo and Scrappy-Doo, disk 1:** since 2026-11-12 checked beyond its title screen: fire starts the game,
  the first level loads and scrolls, the joystick moves the character (screenshots).
- **bootdisk-amiga-m68k:** still "Open" in an old PLAN note, but the C:Assign hang was only a speed effect.

### Swept on 2026-11-09

Crazy Cones (title, then a game started with fire), Hardwired (disk 1 runs to its "insert disk 2" screen), Shinobi
(intro, title, game: "MISSION ONE" about 24 s and gameplay about 45 s after fire, 1.3: 24 s and 41 s,
cracktros-exit §7) work. The AROS m68k boot disk stops on "Unable to load boot/amiga/AROSBootstrap: Error code 121",
as on the real 1.3 (`HUNK_RELRELOC32`, dos-v34-spec §4b). No ADF is left untried.

## Suggested order

1. **The S-sized leftovers** (C7, C10, C11, C13, C14), one subsystem at a time.
2. **The analysis-side gaps** (A7-A10, D1-D4), each through an analysis agent first.

A5, A6, C1, C2, C3, C4, C5, C6, C7 (main part), C8, C9, C12 and the ADF sweep are done;
D1/D3 are specified.
