# dos-cli-v34.md — CLI numbering, EndCLI and per-Shell memory on Workbench 1.3.3 (black box)

> ANALYSIS track ("dirty"). Source: black-box run of the real Kickstart 1.3 (`kick34005.A500`) under
> Amiberry (`amiberry-session --analysis`), 2026-11-02, for GitHub issue #13. Disk:
> `Workbench 1.3.3 (34.34) - Boot (Commodore) (1991) [m2].adf` (session copy), 512 KB chip + 512 KB
> slow RAM, no fast RAM, default (non cycle-exact) Amiberry settings. Every figure below was read on
> an emulator screenshot. No ROM content, address or instruction is given.
>
> **Legend**: **[O]** directly observed · **[D]** deduced from converging observations.
> Related: `bcpl-runtime-v34.md` (EndCLI, Run, `rn_TaskArray` slot search), `loadwb-13.md`
> (EndCLI of the startup-sequence), `workbench-task-v34.md`.

## 1. Procedure

1. Boot, wait ~90 s until the Workbench desktop is idle (two screenshots ~30 s apart identical).
2. Double-click the `Workbench1.3` disk icon (disk window opens).
3. Double-click the `Shell` project icon of that window three times, once per Shell; after each
   one, push the new Shell window to the back with its depth gadget and click an empty part of the
   Workbench backdrop so the Workbench title bar (with the free-memory figure) is shown again.
4. Commands typed in the Shells: `status`, `avail`, `endcli`, `endcli >ram:e`, `type ram:e hex`.

The free-memory figure is only visible while the Workbench backdrop window is the active window;
when a Shell is active the screen title `Workbench Screen` is shown instead. [O]

## 2. Free memory in the Workbench title bar [O]

| Step | Title bar figure | Delta from previous |
|------|-----------------:|--------------------:|
| (a) desktop idle after boot (no CLI window left) | 860 992 | — |
| (b) disk window `Workbench1.3` open | 848 592 | −12 400 |
| (c) Shell #1 open (prompt `1.SYS:> `) | 808 616 | −39 976 |
| (d) Shell #2 open (prompt `2.SYS:> `) | 769 408 | −39 208 |
| (e) Shell #3 open (prompt `3.SYS:> `) | 736 776 | −32 632 |
| (f) Shell #3 closed by `endcli` | 769 352 | +32 576 (56 bytes less than (d)) |
| (g) new Shell opened again (prompt `3.SYS:> `) | 736 720 | −32 632 |

- The first Shell costs ~40 KB, the second ~39 KB, the third and later ~32.6 KB. Opening then
  closing a Shell leaves 56 bytes allocated. [O] Why the first two cost more is not established.
- The figure was stable while idle (same value on two screenshots ~30 s apart at step (a)). [O]
- The prompt is `<n>.SYS:> ` (CLI number, a dot, the current directory name `SYS:`, `> `). [O]

## 3. CLI numbering [O]

- When the desktop is idle after boot, **no CLI is alive**: the boot CLI has ended (the
  startup-sequence ends with EndCLI), and the first Shell opened from the Workbench gets number **1**.
  [O: `status` in Shell #3 listed exactly processes 1, 2, 3.]
- A new Shell takes the **lowest free** number:
  - after `endcli` in Shell 3 (Shells 1 and 2 alive), the next Shell got **3**;
  - after `endcli` in Shell 1 (Shell 2 alive, 3 already ended), the next Shell got **1**, not 3 or 4.
  This matches the "first free slot of `rn_TaskArray`" search described in `bcpl-runtime-v34.md`. [O]

## 4. EndCLI in a Workbench Shell [O]

- Typing `endcli` + Return in Shell #3 closes its window: it was gone on a screenshot taken 1.5 s
  later, without any key press or other input. No text was visible before closing (none could be
  caught at that sampling rate).
- The text EndCLI writes is `CLI process <n> ending` followed by a line feed, **no full stop**,
  21 bytes for n = 3: captured with `endcli >ram:e` in a Shell numbered 3, then `type ram:e hex`
  from Shell 1 (bytes `CLI process 3 ending` + `$0A`; the `.` in the dump's ASCII column is the
  line feed). With the redirection the window closed too.
- After the window closed, the active window was none (screen title shown), then the Workbench
  title bar showed the free-memory figure again (step (f)). [O]
- The remaining Shells keep running and keep their numbers. [O]

## 5. `status` output [O]

From Shell #3 with Shells 1, 2, 3 alive (one line per alive CLI, ascending number):

```
Process  1: No command loaded
Process  2: No command loaded
Process  3: Loaded as command: status
```

From Shell 1 with Shells 1 and 2 alive (3 ended):

```
Process  1: Loaded as command: status
Process  2: No command loaded
```

The number is right-aligned in a 2-character field after `Process`. [O]

## 6. `avail` output (C:Avail present on the disk) [O]

From Shell #3 with three Shells and the disk window open:

```
Type  Available    In-Use   Maximum   Largest
chip     394136    129096    523232    394056
fast     336656    180232    516888    335928
total    730792    309328   1040120    394056
```

- The 512 KB slow RAM is reported on the `fast` line. [O]
- Maximum chip = 523 232 and maximum "fast" (slow) = 516 888: the memory headers' totals, i.e.
  what each region offers after the system's own structures at its bottom were carved out. [D]
- `total Available` (730 792) is ~6 KB below the title-bar figure of step (e) (736 776): the
  difference is Avail itself being loaded while it runs. [D]

## 7. Stack sizes of CLI processes [O]

Measured on the real 1.3 (details and method: `dos-v34-spec.md` §4a). `pr_StackSize` is the CLI
process's **own** stack, fixed at creation: Initial CLI 1600 bytes; "Background CLI" (Run), "New
CLI" (NewCLI) and "AmigaShell" (NewShell) 3200 bytes. Commands run on a separate stack of
`cli_DefaultStack × 4` bytes (default 1000 longs = 4000 bytes), passed at `4(SP)`. Neither running a
command nor `Stack N` changes `pr_StackSize`; `Stack N` only sets `cli_DefaultStack := N / 4`
(truncated), which `Run`/`NewCLI`/`NewShell` copy into the new CLI.
