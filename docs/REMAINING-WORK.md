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

### A1. Workbench 1.3.3: dropping an icon into another window does nothing — [src], L

`wb_dragend` only handles a release inside the window the drag started in. As a result, none of these works:
- moving an icon to another drawer;
- copying it to another disk;
- dropping it on the trashcan;
- dropping a disk onto a disk to start DiskCopy.

This is specified in workbench-task-v34 ("Dragging an icon into another window", and DiskCopy with 3 WBArgs). Most of
it can reuse existing pieces: the Rename packet, the Duplicate copy and the DiskCopy launch.

### A2. Workbench 1.3.3: Special → Empty Trash and Initialize are ghosted (`WBM_OFF`) — [src], M

They need an analysis pass first (D3).

### A3. Workbench 1.3.3: no extended selection — [src], M

There is no Shift-click multi-selection and no group drag (`workbench.s` header: "a single selected icon"). Not
specified yet (D1).

### A4. Workbench 1.3.3: Open, Info and Discard stay enabled with nothing selected — [doc], S

The 1.3 rule still has to be probed (D1).

### A5. Boot time and Clock speed — [doc], M

- With 4 track-cache slots, Workbench 1.3.3 reaches the end of its startup-sequence in 63–64 s. It took 54 s with
  8 slots. Source: PLAN "Track cache 8 -> 4 slots".
- The desktop appears after 72–73 s with both the `2c613e7` and `2a86dda` production ROMs (measured 2026-11-08). The
  forced long frame is therefore not the cause.
- Clock's speed parity with 1.3 is still open (PLAN "Drawing acceleration").
- Next step: measure 6 and 4 slots, and the console/text path, on `make kick-prod`.

### A6. Memory — [src], M

- **Shell cost:** a Shell costs about 52 KB here, against 33–40 KB on 1.3, because of `CP_STKEXTRA` = 4096 in
  `bcpl.s`.
- **Idle desktop:** it has 12,264 bytes less free memory than on 1.3.
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

### C1. Floppy write-back lost on ejection — [doc], M, data loss

1.3 shows a requester and keeps the volume. Source: PLAN "Write-back as on 1.3"; disk-change §2.2.1.

### C2. trackdisk allocates a 12.8 KB chip buffer on every read — [src], S–M

`td_read_track` calls AllocMem on each read. A game that fills chip RAM can lose its disk reads. A persistent buffer
would remove this failure mode.

### C3. Menus — [src], M

- No MutualExclude.
- No NextSelect multi-selection.
- HIGHBOX/HIGHIMAGE are drawn as COMPLEMENT.
- Specified in intuition-input-menus §3.7–3.8.

### C4. Display — [doc], M–L

- DIW/DDF come from three fixed windows, so other DWidths and left/right clipping are ignored.
- The colour count is min(Count, 32) instead of the ncol rule.
- MrgCop copies fragments whole instead of interleaving their WAITs by line.
- The pointer moves in non-interlaced lines on LACE screens.
- The 272-line boot picture is cut on NTSC.
- Source: PLAN "HAM/dual playfield", "Issue #19"; custom-chips §7.0.

### C5. exec scheduling — [src] partly, S–M

- From a task, Signal() and AddTask() only set SAR; they do not reschedule at once.
- The quantum is counted by our own VBlank server, not by timer.device's.
- The PA_SOFTINT softint runs at SR $2100 instead of $2000.
- InitResident's AUTOINIT path does an Enqueue instead of AddLibrary/AddDevice, so LIBF_SUMUSED libraries are not
  summed at init.
- WaitIO keeps D1.

### C6. strap (partial) — [src], S–M

- After the insert-disk screen, inserting a floppy reboots the machine; 1.3 retries DF0: without a reset. This is
  the root of the vAmiga fast-RAM memo workaround.
- A bootblock that returns D0 ≠ 0 gets the insert-disk screen instead of Alert $30000001.
- Source: uae-hd-boot §3.

### C7. Drives and file system — [src] partly, M

- DF2: and DF3: are never mounted (only `mount_df1`).
- Writes to DF1: have not been exercised.
- File system:
  - only 512-byte blocks;
  - files over 65,535 data blocks are not followed;
  - the bitmap block does not move at each write-back;
  - ExNext is stateless;
  - locks of an absent volume are kept in dl_LockList.

### C8. console.device — [src], S–M

- One 16-byte input ring is shared by every unit (`CON_RBSIZE`); 1.3 has 255 bytes per unit.
- CMD_READ with io_Length 0 waits instead of replying −4.
- MULTIBROADCAST raw events go to the active unit only.
- The RastPort copy in the ConUnit is not kept.

### C9. intuition leftovers — S each

- String gadgets:
  - STRINGCENTER/STRINGRIGHT;
  - GADGHBOX/GADGHIMAGE cursors;
  - ghost pattern of a disabled gadget being edited;
  - activation deferred to the next input event;
  - no spaces written past the NUL.
- AddGadget on a REQGADGET goes to the window list.
- IDCMP ports are not in the public port list.
- A window holds only one REFRESHWINDOW at a time.
- Each drawer has its own IDCMP port.
- MOUSEBUTTONS carries qualifier 0.
- it_scrxy ignores the screen's TopEdge.
- Menu texts assume 8-pixel characters.
- Preferences row/column size adjustment.

### C10. graphics leftovers — S each

- QBSBlit is the same as QBlit.
- GfxBase BlitLock is not kept.
- TmpRas is not used as Text's line buffer.
- A removed font replied without a port gets NT_REPLYMSG.
- VSprites go through our own SprIns stream, and one partly above its ViewPort is not clipped.
- The VERTB chain costs about 19 lines.
- ClipBlit walks ClipRects in list order.
- rp_minterms is recomputed at call time instead of read.
- Patterned lines and clipped line pieces are not accelerated.

### C11. Coldstart — S

- CoolCapture runs in supervisor mode without tasks.
- The memory self-test writes before the KickMem areas are reserved.
- The cold path does not clear RAM.
- There is no LED toggle.

### C12. Paula autovectors — S

- Level 3 and 4 service order.
- No INTEN test at entry.
- 14-byte `iv_Data` List.
- Source: custom-chips §7.2 item 5.

### C13. trackdisk — S

- ETD sector labels.
- Error codes 22/27.
- TD_FORMAT without a floppy.
- No unit task for change polling.
- TD_MOTOR, whose spec is partial.

### C14. dos — S

- Retry restarts the whole call instead of resending the packet.
- On a CLI-only boot, the mouse does not move the pointer while a dos requester is up.
- The GV of a makeglobvec handler is not freed.

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

### Never tried on our ROM

Crazy Cones, Shinobi, Hardwired1 and aros-bootdisk.

## Suggested order

1. **A1, Workbench drag into another window.** It is the most visible gap, it is already specified, and most of the
   pieces exist.
2. **C1, requester on ejection with a write-back pending.** It is a data-loss issue.
3. **C2, persistent trackdisk DMA buffer.** Small, and it removes a chip-RAM failure mode for games.
4. **A5 and A6, boot time and Shell memory.** Both are visible in daily use.
5. **Sweep the never-tried ADFs.** It costs little and is the only way to find more class-A gaps.
6. **A2, A3 and A4 after D1/D3.** They finish the Workbench menus and selection.
7. **C3, menu MutualExclude, multi-selection and HIGHBOX/HIGHIMAGE.** Already specified.
8. **C5, exec reschedule from a task, and AUTOINIT through AddLibrary.** Low cost.
9. **C6 and C7, strap retry without a reset, Alert $30000001, DF2:/DF3:.** They finish the two partial residents.
10. **C8, per-unit console input buffers of 255 bytes.**
