# Amiberry reference: GDB monitor commands, IPC, recipes

Checked against the installed build (Amiberry v8.4.2, sources `376b22c`) and the wiki pages "GDB Remote
Debugging" and "IPC Socket Support" of BlitterStudio/amiberry. `A=.claude/skills/amiberry/scripts/amiberry-session`.

## GDB monitor commands (`$A gdb <name> -ex 'monitor ...'`)

Arguments are **hex without `0x`** unless stated; replies are mostly JSON with **decimal** numbers. All need the CPU
stopped (attaching stops it) except `capabilities`, `execution-status` and `input ...`.

| Command | Use |
|---|---|
| `capabilities` | command list of this build |
| `execution-status` | `running` / `stopped` / `host-paused`, frame, beam position, cycles |
| `memory-map` | RAM / ROM / IO regions |
| `disasm ADDR COUNT` | disassembly (COUNT decimal, 1-100) |
| `screenshot PATH` | PNG of the emulated screen |
| `tasks` | exec tasks: current, ready, waiting (name, state, stack, signals) |
| `segments [PROCESS]` | segments of the current (or given) process |
| `process-break name NAME` / `address A` / `status` / `clear` | one-shot stop at the entry of an AmigaDOS program |
| `exception-mask MASK` / `exception` | stop on selected vectors (bit N = vector N; `c` = bus + address error) and read the registers before the frame, with the faulting access |
| `history on` / `off` / `read COUNT` | per-instruction trace (500 entries, COUNT hex up to `80`) |
| `condition add REG OP VALUE MASK SIGNED` / `list` / `remove ID` | stop when a register matches (REG 0-7 = D0-D7, 8-15 = A0-A7, 21 = SR; OP 0 `==` 1 `!=` 2 `<=` 3 `>=` 4 `<` 5 `>`) |
| `step-over` | run to the instruction after a JSR/BSR |
| `watch add ADDR SIZE ACCESS SOURCES VEN VALUE VMASK CHANGE LOG` | exact watch (SIZE 1/2/4; ACCESS 1 r, 2 w, 3 rw; LOG 1 = record without stopping) |
| `watch range ADDR LEN ACCESS SOURCES VEN VALUE VMASK CHANGE LOG` | any access overlapping LEN bytes (up to `10000`); ACCESS bit 2 = instruction fetch |
| `watch list` / `events` / `last` / `remove ID` / `clear-events` | watches and their hit ring (64 hits) |
| `dma-watch add ADDR LEN MODE MASK` / `list` / `remove ID` | DMA accesses (MASK from the source table) |
| `guest-output on` / `read` / `clear` / `off` | strings written by uaelib function 86 |
| `checkpoint save PATH` / `restore PATH` | save state / restore it, keeping the connection |
| `input event KIND PORT CODE VALUE` | KIND 0 key (raw code, 1 down / 0 up), 1 mouse (CODE 0 x / 1 y, signed count as 32-bit hex: -1 = `ffffffff`), 2 joystick (CODE 0 left 1 right 2 up 3 down 4 fire) |
| `input sequence D K P C V;D K P C V` | frame-exact sequence (D = frames after the previous step; kind 3 = pure delay); GDB only |
| `input status` / `release` | held keys/buttons, sequence state |

Watch / DMA source mask: `1` CPU instruction fetch, `2` CPU data read, `4` CPU data write, `8` blitter A, `10` B,
`20` C, `40` D, `80` D line, `100` D fill, `200` copper, `400` disk, `800`-`4000` audio 0-3, `8000`-`400000`
bitplanes 0-7, `800000`-`40000000` sprites 0-7.

Limits: 20 breakpoint slots (gdb breakpoints + conditions + built-in debugger), 20 memwatch slots, watch end at or
below `$1000000` (24-bit addressing). Custom registers `$DFF000-$DFF1FF` are readable once
`set mem inaccessible-by-default off` (done by `m68k.gdb`): `x/2xh 0xdff004`.

## IPC (`$A ipc <name> COMMAND [ARGS...]`)

One line per command, fields separated by TAB (the script joins its arguments with TABs); reply `OK\t...` or
`ERROR\t...` (exit 1).

| Command | Use |
|---|---|
| `PING`, `GET_VERSION`, `GET_STATUS` | liveness, versions, paused flag and floppies |
| `PAUSE`, `RESUME`, `FRAME_ADVANCE [n]`, `RESET [HARD\|SOFT]`, `QUIT` | emulation control |
| `SCREENSHOT PATH` | emulated picture (what `shot --via ipc` uses) |
| `SAVESTATE STATE CONFIG`, `LOADSTATE STATE` | save states (not while the debugger has the CPU stopped) |
| `INSERTFLOPPY PATH DRIVE`, `EJECT_FLOPPY DRIVE`, `LIST_FLOPPIES` | floppies (DRIVE 0-3); disk change during a test |
| `HELP` | list of the IPC commands of this build |
| `SEND_KEY CODE STATE` | raw keycode in **decimal**, 1 press / 0 release |
| `SEND_MOUSE DX DY BUTTONS` | relative move (host-scaled) and buttons (bit 0 left, 1 right, 2 middle) |
| `READ_MEM ADDR WIDTH`, `WRITE_MEM ADDR WIDTH VALUE` | memory access (WIDTH 1/2/4) |
| `GET_CPU_REGS`, `DISASSEMBLE ADDR [n]`, `GET_CUSTOM_REGS`, `GET_COPPER_STATE` | state without gdb |
| `DEBUG_ACTIVATE`, `DEBUG_STATUS`, `DEBUG_STEP [n]`, `DEBUG_STEP_OVER`, `DEBUG_CONTINUE`, `DEBUG_DEACTIVATE` | native debugger |
| `MONITOR <text>` | the GDB monitor commands above without a gdb client (state changes need `PAUSE` first; `step-over`, `checkpoint` and `input sequence` are refused) |

## Recipes

Stop at a crash and see where it came from:
```bash
GDB_TIMEOUT=600 $A gdb s1 -ex 'monitor exception-mask c' -ex 'monitor history on' -ex continue \
  -ex 'monitor exception' -ex 'monitor history read 20' -ex 'info registers'
```

Who writes a memory location (here a long at `$7F0`): one-shot stop on the write, then where the CPU was:
```bash
GDB_TIMEOUT=300 $A gdb s1 -ex 'watch *(int *)0x7f0' -ex continue -ex 'info registers pc' -ex 'x/4i $pc'
```
Everything gdb installs is removed at detach. A watch that must outlive a gdb run, logging hits without stopping,
goes through IPC instead:
`$A ipc s1 PAUSE; $A ipc s1 MONITOR "watch add 7f0 4 2 4 0 0 0 0 1"; $A ipc s1 RESUME`, then later
`$A ipc s1 MONITOR "watch events"` (and `MONITOR "watch remove ID"`; a gdb connection is refused while it exists).

Stop when a program starts (Workbench or CLI), then step through it:
```bash
GDB_TIMEOUT=300 $A gdb s1 -ex 'monitor process-break name Lines' -ex continue -ex 'monitor segments' \
  -ex 'x/10i $pc' -ex stepi -ex 'info registers'
```

Exec state while it runs: `$A gdb s1 -ex 'monitor tasks'` (decode with `python3 -c` and `json.JSONDecoder().raw_decode`
on the text after the first `{`: gdb appends "[Inferior 1 (Remote target) detached]" on the same line).

Frame-exact key press (Space down, up 5 frames later): `$A gdb s1 -ex 'monitor input sequence 0 0 0 40 1;5 0 0 40 0'`.
