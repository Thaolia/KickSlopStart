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
project) is shown during a drop and Empty Trash. While DiskCopy runs, the inhibited drives show "DF0:BUSY" /
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

### A5. Boot time — done 2026-11-09; Clock speed — [doc], S

- **Boot:** the Workbench title bar of Workbench 1.3.3 now appears after 61.7 s (two runs), against 68.5–69.0 s on
  the real 1.3 and 71.0–71.3 s before. Cause: the file system fetched the current data block again from trackdisk at
  every READ, and the CLI reads `s/Startup-Sequence` in small pieces (818 of the boot's 1,460 block reads were its two
  data blocks). Each READ now reuses the block already in the handle's buffer (`SS_BUFBLK`, `src/dos/ofs.s`).
  PLAN "Boot time (2026-11-09)".
- Clock's speed parity with 1.3 is still open (PLAN "Drawing acceleration").

### A6. Memory — [src], M — Shell gap closed to 416 bytes 2026-11-10

- **Shell cost:** opening a Shell from the Workbench takes 33,896 bytes here (35,944 before, 47,152 at the start of
  2026-11-09), against 33,480 on 1.3 (newshell-memory-v34 §2): `CP_STKEXTRA` 2048 -> 1024 for the Background CLI and
  the NEWCON handler (and every other BCPL process or handler). Their 68000 side used at most 668 (NEWCON) and 516
  (Background CLI) bytes in a long Shell session with a "No disk present" requester, `Run`, `type`, `copy`,
  `newshell`/`endcli` (868 at most in the 2026-11-09 measurement), and more than 1,500 bytes of their BCPL part stay
  untouched under that. The remaining 416 bytes are not chased further.
- **Idle desktop:** 1,024 bytes more than before (the RAM handler's stack): about 13,384 above 1.3 (860,992).
- **Reduction candidates:** listed in `docs/MEMORY-USAGE.md`.

### A7. Workbench 1.2 Lines and Clock — [doc], S–M

- After a shrink, Clock can leave a sliver drawn at its old size.
- Lines draws slowly into its 1008 × 512 SuperBitMap.
- The frame of a non-GZZ SUPER_BITMAP window is not copied into the SuperBitMap.
- Source: ARCHITECTURE (7h).

### A8. Real A500 with Workbench 1.2: right button flicker and frozen pointer — [doc], unknown size

A badly seated mouse is suspected. Retest first; if it persists, try the same mouse on the real 1.3. Source: PLAN
"First run on real hardware".

### A9. Bubble Bobble: two allocations missing — [doc], unknown size

1.3 makes two allocations (9,876 and 177,152 bytes) that our ROM does not; the cause is unknown. The game runs.

### A10. Cluedo — analysis probe needed

Cluedo reaches player selection. Two points must be confirmed on 1.3: whether dos LVOs also return their result in
D1, and how trackdisk recovers after a program moved the head.

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
  - PORTS/EXTER are acknowledged before the server chain;
  - unclaimed sources are acknowledged;
  - SetIntVector(NULL) stores 0.
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
(intuition-input-menus §3.6-§3.9), checked with `tests/menucat.s` against the §5 vectors (steps 3-5). Left: the
working flags are not reset when a window is activated (only when a menu opens).

### C4. Display — done 2026-11-10

- DIW/DDF, fine scroll, clipping, modulos and the colour count (ncol, SPRITES colours) follow graphics-display
  §4.2-4.4 (`tests/mvport_probe.sh`, the 13 probed rows equal).
- MrgCop merges the streams of all ViewPorts by line (fragment, VSprites, UCopList read directly), with the §5.2 tie
  rule, the line-255 crossing and repeated WAITs dropped (`tests/mrgcop_probe.sh`, nine cases of §5.2-5.4 and §7.3).
- The insert-disk picture shows its middle 216 lines on NTSC, logo whole.
- The pointer counts interlaced lines since the high-resolution pointer units (2026-11-09, v0.2.35).
- Left, small: MrgCop rebuilds the lists even when no ViewPort has a CopList (1.3 then leaves the old lists alone,
  §5.1); ClrIns is not merged (we never build one).

### C5. exec scheduling — done 2026-11-10 but one point

Signal and AddTask reschedule when the task becomes the head of TaskReady, AUTOINIT goes through
AddLibrary/AddDevice/AddResource, WaitIO returns the signal bit in D1 (2026-11-09). Since 2026-11-10 timer.device
counts the quantum (Elapsed/TQE, never a preemption in the production ROM; the dev ROM keeps a round-robin server for
its spinning demo tasks), software interrupts run at SR $2000 with SOFTINT masked, and Signal returns the previous
tc_SigRecvd (`tests/sched_probe.sh`). Left: the software interrupts sit in one FIFO list instead of the five
priority queues of ExecBase SoftInts (exec-scheduling §8).

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
requester and failed at once with 218. Left in the file system:
- only 512-byte blocks (1.3 reads `de_SizeBlock`; every OFS offset, buffer and table size here assumes 128 longs);
- a FINDINPUT (MODE_OLDFILE) handle is read-only (WRITE -> 212), while rom-filesystem §5.1 says 1.3 accepts writes
  on it;
- Cancel on the "in unit  n" requester fails the access at once; 1.3 shows the requester once more first, and a
  cancelled `Copy` then meets "No disk present / in unit  n" (§2.4.1 point 2).

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
(`tests/lineclip_probe.sh`: same pixels, 24 % less time for 1,000 patterned lines in a covered window). Left:
- VSTART of a VSprite includes `vp_DyOffset`, which gels §5.8 says 1.3 does not add.
- The rest of the VERTB cost is gameport's input injection and unit emulation, which 1.3 does not run there.
- Patterned lines are walked by the CPU; only solid lines use the blitter's line mode.

### C11. Coldstart — done 2026-11-10 but one point

LED toggle after ColdCapture, RAM zeroed on the cold path, and no self-test while KickMem areas must survive. Left:
CoolCapture runs in supervisor mode without tasks, because our InitCode(RTF_COLDSTART) still runs before the first
task exists; moving it into the initial task in user mode is larger than S.

### C12. Paula autovectors — done 2026-11-10

INTEN test at entry, 1.3 service order, 22-byte chain headers (custom-chips §3.3). We still serve every pending
source of a level per entry where 1.3 serves one and is re-interrupted, and acknowledge VERTB before its chain.

### C13. trackdisk — S

TD_FORMAT without a floppy: done 2026-11-10 (29 before anything is cached). Left:
- ETD sector labels.
- Error codes 22/27.
- No unit task for change polling (larger than S).
- TD_MOTOR, whose spec is partial.

### C14. dos — S

- Retry resends the packet; 1.3 restarts the whole call, name resolution included (dos-lvo-partial §1.4). It only
  differs when the volume moved meanwhile; every name-based LVO would have to loop on its resolution.
- On a CLI-only boot, the mouse does not move the pointer while a dos requester is up.
- The GV of a makeglobvec handler is not freed: 1.3 frees pr_GlobVec when it differs from dl_GV, but our createproc
  gives a child its creator's GV (Execute needs it), so that rule would free a parent's GV; ownership has to be
  recorded first.

### C15. CPU — M–L, optional

- No 68030/68040 support.
- AFF_68881 is never set.
- No 512 KB ROM image for an A1200.
- Source: issue #20.

## D. Analysis-side gaps that block implementation

These need a spec or a probe on the real ROM first, run by an analysis agent.

### D1. Workbench selection and menu rules

Neither is in workbench-task-v34:
- extended selection (Shift-click);
- the 1.3 rule for enabling or ghosting Workbench menu items when nothing is selected.

### D2. VSprite allocation by band in DrawGList

graphics-gels open points 3 and 9; the CLI probe stopped at G9b.

### D3. Empty Trash and Initialize

How 1.3 runs them: what it deletes or launches, and which requesters it shows.

### D4. File system

- The validator's requester text for "key met twice", and Retry on "Disk structure corrupt".
- 1.3's handling of a bad bitmap checksum under a valid flag.
- TD_CHANGESTATE / PROTSTATUS / CHANGENUM on a device that rejects them.
- rom-filesystem §12.
- The text of the requester for an ejection with a write-back pending.

### D5. trackdisk

- Decoder cases for error codes 22/27.
- trackdisk-write §9: write protection was never seen running.

### D6. Smaller questions

- The Cluedo items (A10).
- Whether S: and SYS: get a lock-0 assign when missing.
- Whether Left Amiga + B closes a dos requester on 1.3.
- Whether every window of a screen gets MouseX/Y updates.

### D7. 28 LVOs still only partly specified (all P3)

- exec: SetSR/SuperState/UserState/GetCC, AllocTrap/FreeTrap, AllocSignal/FreeSignal, SetFunction,
  InitStruct/MakeLibrary details.
- graphics: AllocRaster/FreeRaster, InitBitMap.
- intuition: Begin/EndRefresh, Alloc/FreeRemember.
- TD_MOTOR is partial too.

### D8. Probes described but never written

- dos-lvo-partial §4. Item 4, overlay UnLoadSeg, is now useful to check PR #28.
- dos-memory §8, P1–P6.
- The exec-messages-io, exec-rawdofmt and mathffp probes were never run on the real ROM.

### D9. Real-hardware points

- Recoverable Alert without slow RAM.
- DMRequest and SIZEVERIFY are described from the ROM only.

## Test ADFs (`assets/test_adf/`) on our ROM

### No documented failure

- **Workbench 1.3.3:** boots; its remaining gaps are A1–A6.
- **Workbench 1.2:** reaches its desktop (A7, A8).
- **Applications:**
  - SysInfo and OctaMED v4 work.
  - Directory Opus 4.12 runs.
  - Deluxe Paint III v3.00 (since PR #28, 2026-11-08): reaches the paint screen, quits to the CLI and can be run
    again. Selected requester gadgets are drawn without their text.
- **Games:**
  - Holiday Lemmings: menu and a playable level. The Lemmings demo works too.
  - Caesar reaches its game menu.
  - Monkey Island disk 1: the intro returns to the Workbench, and the title screen opens from the CLI. Disk 4 is not
    a boot disk.
  - SimCity reaches its menu.
  - Zool behaves as on 1.3 (fire on port 2).
  - Tintin and Shanghai run.
  - Bubble Bobble runs (A9 still open).
  - Cluedo reaches player selection (A10).
- **Demos:**
  - Spaceballs, Desert Dream and Sanity-Arte run.
  - Andromeda "D.O.S.": fixed in `2a86dda`. The "AmigaDOS" frame shown during the demo is its own artwork.

### Partly documented

- **Scooby-Doo:** reaches its title screen; nothing is documented beyond that.
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
