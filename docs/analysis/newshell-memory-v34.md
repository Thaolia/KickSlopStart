# newshell-memory-v34.md — Workbench Shell open/close memory cycle and screen-bar behaviour at the end of boot (real 1.3, black box)

> ANALYSIS track ("dirty"). Written for GitHub issue #22. Source: black-box runs of the real Kickstart 1.3
> (`kick34005.A500`) under Amiberry (`amiberry-session --analysis`, cycle-exact A500), 2026-11-04.
> Disk: session copies of `Workbench 1.3.3 (34.34) - Boot (Commodore) (1991) [m2].adf` (a modified
> 1.3.3 disk: its startup-sequence also runs CrossDOS, TDPatch13 and mounts DI0:/DI1:; the boot CLI
> window is titled `AmigaDOS`). 512 KB chip + 512 KB slow RAM at `$C00000`, no fast RAM.
>
> Method: free memory read (a) on the Workbench title bar in screenshots and (b) from the public exec
> memory lists, while the emulation was paused: ExecBase `MemList` → each `MemHeader` (`mh_Attributes`,
> `mh_Free`) and its free-chunk chain (`mc_Next`, `mc_Bytes`), read through the emulator's memory-read
> command. Both agreed to the byte whenever the title was visible. Mouse and keyboard were scripted;
> each step was checked on a screenshot. No ROM code was read; no ROM content, address or instruction
> is given.
>
> **Legend**: **[O]** directly observed · **[D]** deduced from converging observations · **[S]** assumed.
> Related: `dos-cli-v34.md` §2 (same kind of measurement, non cycle-exact, several Shells open at once),
> `dos-memory-v34.md` §4 (allocation inventory of NewCLI/EndCLI), `workbench-task-v34.md` §3.4/§6.4
> (the 5 s free-memory title), `intuition-input-menus-v34.md`, `intuition-screens-v34.md`.

## 1. Memory headers on this configuration [O]

| Header | `mh_Attributes` | Region | `mh_Free` idle desktop after boot |
|---|---|---|---:|
| first in `MemList` | `MEMF_PUBLIC\|MEMF_FAST` (5) | slow RAM `$C00000`… | 431 480 |
| second | `MEMF_PUBLIC\|MEMF_CHIP` (3) | chip RAM | 429 512 |
| total = title figure | | | **860 992** |

The slow-RAM header comes first in `MemList`, so `MEMF_PUBLIC`/`MEMF_ANY` requests are served from slow
RAM first. [O for the order, D for the consequence: every Shell-related allocation below came from slow RAM]

## 2. NewShell / EndCLI cycles [O]

Procedure per boot: desktop idle (≥ 20 s after the disk icon appeared) → double-click the `Workbench1.3`
disk icon, wait 30 s → double-click the `Shell` icon of that window (an `AmigaShell` window opens with
prompt `1.SYS:> `), wait 12 s → type `endcli` + Return (the window closes; the Workbench title with the
free-memory figure comes back, the Shell icon stays highlighted) → wait 15–30 s → repeat.
Figures are total / slow / chip `mh_Free`, in bytes.

### 2.1 Boot 1

| Step | Total | Slow | Chip |
|---|---:|---:|---:|
| (a) idle desktop after boot | 860 992 | 431 480 | 429 512 |
| disk window open (6 s after the double-click) | 846 968 | 425 952 | 421 016 |
| (b) Shell #1 open | 813 488 | 392 472 | 421 016 |
| (c) after `endcli`, +8 s | 839 296 | 418 280 | 421 016 |
| (c) same, +15 s (title bar showed the same figure) | **837 672** | 416 656 | 421 016 |
| (d) Shell #2 open | 811 808 | 390 792 | 421 016 |
| (e) after `endcli` | **837 672** | 416 656 | 421 016 |
| (f) Shell #3 open | 811 808 | 390 792 | 421 016 |
| (g) after `endcli` | **837 672** | 416 656 | 421 016 |
| Shell #4 open / after `endcli` | 811 808 / **837 672** | | |

### 2.2 Boot 2

| Step | Total | Slow | Chip |
|---|---:|---:|---:|
| (a) idle desktop after boot | 860 992 | 431 480 | 429 512 |
| disk window open, +30 s and +45 s | 846 968 | 425 952 | 421 016 |
| (b) Shell #1 open | 813 488 | 392 472 | 421 016 |
| (c) after `endcli`, +15 s | 839 296 | 418 280 | 421 016 |
| (d) Shell #2 open | 811 808 | 390 792 | 421 016 |
| (e) after `endcli`, +15 s | **837 672** | 416 656 | 421 016 |
| (f) Shell #3 open | 811 808 | 390 792 | 421 016 |
| (g) after `endcli` | **837 672** | 416 656 | 421 016 |
| Shell #4 open | 811 808 | 390 792 | 421 016 |
| after `endcli`, and again 35 s later | **837 672** | 416 656 | 421 016 |

### 2.3 Boot 3 (perturbed boot)

During this boot the emulation was paused and resumed every ~10 s by the measuring script until the
desktop was idle; its idle figure came out **1 648 bytes lower** than in boots 1 and 2 (and in two more
undisturbed boots used for §3, which also showed 860 992). Kept as a noise sample.

| Step | Total | Slow | Chip |
|---|---:|---:|---:|
| (a) idle desktop | 859 344 | 429 832 | 429 512 |
| disk window open, +30 s | 845 824 | 424 808 | 421 016 |
| (b) Shell #1 open | 812 344 | 391 328 | 421 016 |
| (c) after `endcli`, +8 s | 838 208 | 417 192 | 421 016 |
| (c) same, +45 s | **835 520** | 414 504 | 421 016 |
| (d)/(e) Shell #2 open / after `endcli` | 809 544 / **835 408** | | |
| (f)/(g) Shell #3 open / after `endcli` | 809 544 / **835 408** | | |
| disk window then closed (close gadget), +15 s | 850 256 | 420 744 | 429 512 |

### 2.4 Findings

1. **The first NewShell/EndCLI cycle costs 9 296 bytes once** (boots 1 and 2): 846 968 (disk window
   open, before any Shell) → 837 672 after the first `endcli` has settled. Every later cycle returns
   **to the byte** to 837 672: no cumulative loss over 3 further cycles, on two boots. Boot 3: 10 304
   on the first cycle, 112 more on the second, then 0. [O]
2. The one-time cost is entirely **slow RAM** (`MEMF_PUBLIC`); chip RAM is unchanged by every Shell
   cycle (421 016 throughout). The disk window itself costs 14 024 (5 528 slow + 8 496 chip) and stays.
   [O] Breakdown of the disk window's cost (12 400 on a first open without queued messages, 11 936 on
   later opens; the 1 624 difference here is 29 IntuiMessage blocks): `workbench-task-v34.md` §9.
3. The one-time cost appears in **two steps**: 7 672 bytes are still held right after the first
   `endcli` (839 296), and a further **1 624 bytes** are taken a few seconds later (boot 1: between 8 s
   and 15 s after `endcli`; boot 2: later than 15 s, before Shell #2 had opened). Shell #1 open is
   accordingly 1 680 bytes above the later Shells (813 488 vs 811 808). [O] What holds the memory: §2.5.
4. A Shell open costs 25 864 bytes in the steady state (837 672 → 811 808), all slow RAM. [O]
5. Boots 1 and 2 give identical figures to the byte at every settled step; the only variation is
   *when* the 1 624-byte step happens. Boot 3 shows that the size of the one-time cost itself varies
   from boot to boot by multiples of 56 bytes (§2.5). [O]
6. `dos-cli-v34.md` §2 (non cycle-exact run, Shells kept open) read 848 592 with the disk window open;
   this is 846 968 + 1 624, i.e. most probably a reading taken before the same 1 624-byte allocation
   happened. Its "56 bytes left per Shell" was measured with other Shells still open and is not
   contradicted here (with no other Shell open, cycles 2–4 left 0 bytes). [D]

### 2.5 What the one-time cost is (boot 3, free-list comparison) [O unless stated]

The free-chunk lists were captured with the disk window open before Shell #1 and again after the first
`endcli` had settled; the ranges free before and in use after were then identified from their contents
and from public structures:

| Bytes held | What | How identified |
|---:|---|---|
| **7 504** | The code segment of `L:Newcon-Handler`, loaded on the first `NEWCON:` open and **kept**: it is the `dn_SegList` of the `NEWCON` DeviceNode in the DOS device list afterwards (`mount newcon:` in the startup-sequence only creates the node: the block was still free memory before Shell #1). | The block's first long is its own size (7 504, LoadSeg block format, `dos-memory-v34.md` §3.2), next-segment link 0; the file on the disk is 7 532 bytes = one 7 496-byte code hunk + 36 bytes of hunk headers; the NEWCON DeviceNode's `dn_SegList` points at it. |
| **2 800** (= 50 × 56) | **IntuiMessages of the `Workbench1.3` disk window**, kept by Intuition for reuse: node type `NT_REPLYMSG`, `mn_ReplyPort` = that window's `WindowPort`, `mn_Length` 32, `IDCMPWindow` = the disk window. 56 bytes per block. They are **freed when that window is closed** (the same ranges were free again after the close gadget was used). | Contents of the blocks (exec Message header + IntuiMessage fields), window structure fields (`WindowPort`, title `Workbench1.3`). |
| 0 (net) | two 40-byte blocks moved | |

- 7 504 + 2 800 = 10 304, the boot-3 first-cycle cost. The 112 bytes of the second cycle are two more
  56-byte message blocks. [O]
- In boots 1 and 2, 9 296 = 7 504 + 1 792 = NEWCON segment + **32** message blocks [D: same split
  assumed; the free lists were not captured in those boots]. That split also fits the timing of §2.4
  item 3: 7 672 right after `endcli` = 7 504 + 3 × 56, and the 1 624-byte late step = 29 × 56 (more
  messages queued to the disk window when it is refreshed after the Shell window has gone). [D]
- So the **only truly permanent part** is the NEWCON handler segment (7 504 bytes, slow RAM), which
  stays loaded for the rest of the session like any handler loaded from `L:`. The message part depends on
  how many events Intuition had to queue to the disk window at once while the Shell window opened and
  closed over it, and is returned when the window closes. [D]
- After closing the disk window (boot 3), free memory was 850 256: 9 088 below the idle figure, i.e. the
  7 504 NEWCON segment plus 1 584 bytes not attributed (the Workbench may keep objects of a drawer it
  has opened; not investigated). [O for the figure, S for the explanation]

## 3. Right mouse button and screen dragging at the end of the startup-sequence [O]

Second report of issue #22 ("at the end of the Workbench 1.3 disk loading, pulling down the main bar
gives graphic glitches"). Observed on the real ROM in eight boots, with screenshots every ~0.15–0.25 s.

### 3.1 Transition from the boot CLI to the Workbench (no input)

- During the startup-sequence the boot CLI window (`AmigaDOS`) covers the screen's title bar.
- When the CLI window closes, the next frames show the Workbench screen title bar with
  `Workbench release.  NNNNNN free memory` (a lower figure than at rest, e.g. 842 400 / 842 576,
  because the Workbench is still loading) over an empty blue desktop; the `RAM DISK` and
  `Workbench1.3` icons appear about 0.2–1 s later. The title figure settles at 860 992 when loading
  ends.
- In one boot a single frame caught exactly at the window close showed the whole screen blue with **no
  title bar and no icons** (only the pointer); the next sample (~1 s later) had the title bar and icons.
  At 0.2 s sampling in another boot no such frame was seen. A momentary blank screen while the window is
  removed and the bar redrawn is therefore normal 1.3 behaviour. [O]
- No stray pixels, no leftover pieces of the CLI window, no colour changes were seen in any frame. Colour
  census of the frames: only the four Workbench colours (blue, white, black-blue, orange) plus the
  pointer colours and the black overscan edge. [O]

### 3.2 Right button held

- **While the boot CLI window is active** (right button pressed while it was still open): the screen
  bar is drawn as an **empty white bar** over the top of the CLI window (no title text, no menu titles:
  the CLI window has no menu strip). The CLI window's own title bar is hidden under it. On release, the
  CLI window's title bar comes back. Held for 12 s while the startup-sequence continued: no artefact. [O]
- **Right button pressed at the moment the CLI window closes** and held 15 s while the Workbench loads:
  the bar immediately shows the Workbench menu titles `Workbench  Disk  Special` (black text on white)
  instead of the screen title; the icons keep appearing underneath normally; on release the title
  `Workbench release.  NNNNNN free memory` comes back. No artefact. [O]
- Menus pulled down on the idle desktop: `Workbench` → Open, Close, Duplicate, Rename, Info, Discard;
  `Disk` → Empty Trash, Initialize; `Special` → Clean Up, Last Error, Redraw, Snapshot, Version. With no
  icon selected the items are drawn **ghosted** (dot pattern over the text); the selected menu title is
  drawn complemented (orange on black-blue). The menu box is white with blue text and a thin border;
  what was under it is restored exactly on release. [O]
- Using the menus without selecting anything left the free memory unchanged (860 992 again on the next
  title refresh; one title read 859 456 just after release, transiently). [O]

### 3.3 Dragging the screen with the left button on the title bar

- At rest: the Workbench screen follows the pointer down (title bar, icons and everything move as one
  block); **the area above the dragged screen is plain colour 0 of the Workbench (the same blue)**, with
  no other screen, garbage or pattern visible; the part of the screen below the display bottom is simply
  cut off. Released, the screen stays where it was dropped; dragging up stops with the title bar at the
  top of the display. [O]
- At the end of the startup-sequence (button pressed just after the CLI window closed, pointer moved down
  100 counts and held 15 s): the screen moved down and stayed there while the Workbench went on loading;
  the icons appeared at their place inside the moved screen; no artefact. In one other attempt the screen
  did not move at all (the pointer did not move either: the injected moves were probably lost on the
  host; not taken as a 1.3 behaviour). [O]

### 3.4 Conclusion for issue #22

On the real 1.3 neither the right-button menu bar nor screen dragging at the end of the Workbench boot
shows graphic artefacts. Expected appearance: blank white bar while a menu-less window is active; menu
titles `Workbench Disk Special` once the Workbench is active; screen drag shows uniform colour 0 above
the screen. Anything else drawn by our ROM in those situations (garbage, stale window pieces, wrong
colours, damage left after release) is a difference from 1.3. [O]

## Clean-room review

- [x] Only public structures (ExecBase `MemList`, `MemHeader`, `MemChunk` fields) and on-screen
  observations are used; no ROM routine, address or instruction is quoted.
- [x] Screenshots are described in words; no image data reproduced.
