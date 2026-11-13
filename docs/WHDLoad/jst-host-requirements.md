# JST (JOTD Startup) on a Kickstart 1.3 host (black-box runs and host-side requirements)

Analysis-track page. JST, its loaders and the WHDLoad Slaves were treated like the Commodore ROM: only the analysis
agent downloaded, ran and disassembled them. Behaviour and ABI only: no instruction listing, no address or offset
inside the JST binaries or inside the Commodore ROM. Companion page: `whdload-host-requirements.md` (same setup).

Verdict in one line: **an old JST (0.8c, 1997) runs a JST loader on Kickstart 1.3 up to a playable game, on the real
ROM and on our production ROM alike; the JST versions that accept WHDLoad Slaves do not run on 1.3** (3.1 crashes on
a V36 dos call on both ROMs, 4.7 cannot be loaded by the 1.3 `LoadSeg`).

## Material

| Item | Source | Licence / status |
|---|---|---|
| JST 4.7 (2001), user package; `OSEmu.400` | Aminet `game/patch/jst.lha` | freeware since 4.7 (author's statement in the guide) |
| JST 3.1 (2000), binary of the developer package listed on Aminet as "V3.2b" | Aminet `game/patch/jst32b_dev.lha` | shareware at the time; on Aminet |
| JST 0.8c (1997) | Aminet `game/patch/jst_hdinstalls.lha` (`bin/`) | shareware at the time; on Aminet |
| JST copy bundled with the Cadaver demo install (packed executable, version string not readable) | same archive | same |
| "Cadaver" coverdisk demo as a JST loader with its data inside (one executable, about 270 KB), by the JST author | same archive | coverdisk demo, distributed on Aminet in that archive |
| Arte (Sanity 1993) WHDLoad Slave, Slave version 10, plus disk image | see the WHDLoad page | scene demo |
| Gamebench 2.00 ("WB 1.3 front end for WHDLoad and JST") | Aminet `util/misc/Gamebench.lha` | Aminet |

## Observed results

Same setup as the WHDLoad page (A500, 68000, cycle-exact, chip 512 KB + slow 512 KB, DH0: = host directory through
the UAE file system, startup-sequence reduced to `SetPatch` + `execute DH0:test`, output to `SER:`). "Our ROM" = the
production build unless stated; the development build is discussed in its own section below.

| Run | Real Kickstart 1.3 | Our ROM (production) |
|---|---|---|
| JST 4.7 + Arte Slave | `Unable to load JST47: file is not an object module`; the script is aborted | identical |
| JST 3.1 + Arte Slave | nothing printed; "Software error - task held / Finish ALL disk activity / Select CANCEL to reset/debug" requester; Cancel resets the machine | nothing printed; Guru `#00000004.<task>` (illegal instruction in task `JOTDStartup`) shown directly |
| JST 3.1 + Cadaver demo loader | same crash | same crash |
| JST 0.8c + Cadaver demo loader | registration notice, then the game takes over: the first room ("Entrance hall", "Day 1") is shown and the dwarf moves with the joystick | identical; the game appears 25 s after the command against 20 s on the real ROM (same emulator, wall clock, one run each) |
| JST 0.8c + Arte Slave (JST 0.8c predates Slave support) | registration notice, then `** Object Arte.Slave is executable but not a JOTD loader` / `Check for HD_PARAMS location in the source`; returns to the CLI with return code 0 | identical |
| Bundled JST + Cadaver demo | `** Object  not found or empty!!` (the argument is not taken), then Guru `#81000005` (memory list corrupt) | identical text and Guru |
| Gamebench 2.00 started with `run` | its window ("CLI", "Game List", "Load Game", "Exit", five favourites) opens; the script continues | identical |
| JST 0.8c + Cadaver, 2 MB fast RAM added | game reached | game reached (development build) |

Quit key: F10 (held or tapped) did not leave the Cadaver demo on either ROM, so the return to the OS from a running
game was **not** observed. The demo readme announces F10 as the quit key; the reason it did not work here is not
known (uncertain whether it needs a newer JST).

The OS-swap path (JST re-enabling the OS during the game to read a file) was not exercised: the Cadaver loader has
its data inside the executable.

## JST versions and Kickstart 1.x (official guide of 4.7, history section)

- 0.3: "1.3 compatibility restored". 0.4-0.8: JST loaders only.
- 1.3: "added WHDLoad slave support" (beta). The guide says compatibility is best for Slave versions 6 and 7, "most
  of V11"; 2.5 adds WHDLoad expansion memory (Slave v8); 4.0 "some slaves in v12 format"; 4.5b "Supports WHDLoad
  slaves v13". Emulated `resload` functions named in the history: Decrunch (partial), Relocate, ListFiles, Patch,
  Delay, DeleteFile, plus the Slave flags/tags CBAF, CBSWITCH and a keymap tag.
- 4.5: "JST is no longer Kick 1.x compatible". 4.7 prints `JST needs Kickstart V37 or higher` (text in the binary),
  but on 1.3 it never runs: like WHDLoad 20.x, its executable uses the V37 short relocation hunk type (`$3F7`),
  which the 1.3 `LoadSeg` rejects (observed on both ROMs).
- So a JST that could run a WHDLoad Slave on 1.3 would have to be between 1.3 and 4.4. Only 3.1 was found on Aminet,
  and it is **not** 1.3-safe (next section). Whether any 1.3-4.4 release really ran on 1.3 is unknown.

## Why JST 3.1 crashes on Kickstart 1.3

- Observed on both ROMs with the exception catcher of the emulator (vector 4, illegal instruction, in task
  `JOTDStartup`) and by reading the caller's return address back to the JST code: early in its start (before it
  prints anything or opens the object), JST 3.1 calls `dos.library` `AllocDosObject(DOS_FIB, NULL)` (V36) without
  testing the dos version. A V34 dos library has no such entry: the call lands below the dos jump table, in
  whatever memory lies there, and the CPU soon meets an illegal opcode.
- The two ROMs fail the same way; only the presentation differs (next point).
- Presentation difference (our ROM vs 1.3, not specific to JST): for a user-task exception the real 1.3 first shows
  the "Software error - task held" system requester (Retry/Cancel) and only Cancel leads on; our ROM goes straight
  to the Software Failure Guru. This requester is already described in `docs/analysis/alert-v34.md`.
- Static reading of the 3.1 and 4.7 binaries finds the same unguarded V36+ dos set in both: AllocDosObject,
  FreeDosObject, Flush, LockDosList, UnLockDosList, FindDosEntry, ReadArgs (the argument template is a ReadArgs
  template), FreeArgs, GetVar; plus lowlevel.library (V40) for the CD32 joypad emulation, opened on demand.

## Host-side requirements of JST 0.8c (the version that works on 1.3)

Method: the run above, plus a static reading of the 0.8c code hunk with the same heuristic as the WHDLoad page
(library bases are kept in absolute variables; each OpenLibrary site names its library; LVO slots named from the
AROS `.conf` lists, icon.library functions up to BumpRevision counted as V34). Uncertain attributions are left out.

- Libraries: dos, icon, graphics, intuition, all opened with version 0 except one intuition open with version 36
  whose failure is tolerated (the run proves 1.3 is accepted). No device is opened by name in the parts read.
- exec: Supervisor, SuperState, UserState, SetSR, Disable/Enable, Forbid/Permit, AllocMem (with chip, clear and
  public requirements), FreeMem, AvailMem, FindTask, WaitPort/GetMsg/ReplyMsg (Workbench start), OpenLibrary,
  CloseLibrary, RawDoFmt. V36+ exec functions present: CacheControl and ColdReboot; the code holds exec
  `lib_Version` tests against 39 near the cache/degrader parts, and the run shows they are skipped on 1.3.
- dos: Open, Close, Read, Write, Output, Seek, DeleteFile, Lock, UnLock, Examine, ExNext, CurrentDir, Delay,
  Execute. AddPart (V36) is referenced; it was not reached in the runs (guard not checked).
- icon: GetDiskObject, FreeDiskObject, FindToolType (tool types of the loader icon, Workbench start).
- graphics: LoadView (to blank the display before the takeover), WaitTOF; V36/V39 degrader calls (VideoControl,
  SetChipRev) behind the version tests above.
- intuition: MakeScreen / RethinkDisplay (display restore), possibly others not attributed.
- Hardware, from the code: direct accesses to both CIAs (keyboard and timers) and to the custom registers (INTENA,
  INTREQ, DMACON, colours, beam position, the Denise/Lisa ID register for the AGA test). The loader then owns the
  machine: the game replaces the autovectors in low memory (seen as game-owned vector values in the running game on
  our ROM), and runs at interrupt mask 7 between its own interrupts.
- Exit: per the guide, JST restores the OS state it saved (custom chips, copper list, vectors, caches), reloads the
  battery clock (registered feature until 4.7) and returns to the CLI or Workbench. Not observed here (see "Quit
  key").

## Our development ROM (`build/kick13.rom`) is not representative here

- With the development build, JST 0.8c reaches the Cadaver game only after several minutes, and with the Arte Slave
  it had still not printed its "not a JOTD loader" message after several minutes, while the production build behaves
  like the real ROM in both cases. Gamebench under the development build also left the script's `wait 20` after
  `run GameBench` unfinished; under the production build it completes.
- During the stall the CPU was sampled repeatedly with the debugger: every sample was in interrupt code (level 6
  dispatch and the CIA-B interrupt server, the development-only level-6 proof handler, the level 3 dispatch and the
  gameport VBlank server); `INTREQR` showed EXTER (and PORTS) pending and enabled each time, and the ready list held
  the development harness tasks next to `JOTDStartup`. This points at the interrupt load of the development harness,
  not at an OS function JST lacks. It was not investigated further.

## What this means for a 1.3-compatible ROM

- Nothing blocking was found on our side for JST 0.8c-class loaders: same messages, same takeover, same game, close
  timing, on the production build.
- JST + WHDLoad Slave on 1.3 is blocked by JST itself (3.1: unguarded V36 dos call; 4.5+: V37-only by design), not
  by our ROM. Supporting it would mean providing the V36 dos functions listed above, with the same caveats as
  WHDLoad.
- Differences seen on the way, outside JST's own needs: the missing "task held" requester before the Guru; the boot
  CLI prompt is `> ` on our ROM where the real ROM prints `1> ` in the same reduced startup-sequence (cosmetic,
  noted for completeness).

## Open points

- Return to the OS (quit key) and the OS swap during a game were not observed on either ROM.
- No JST release between 1.3 and 3.0 was available to test whether WHDLoad Slaves ever ran under JST on 1.3.
