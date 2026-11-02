---
name: amiberry
description: Run this project's Kickstart ROM (or a disk on it) in headless Amiberry sessions, several at once, with the serial output logged to a file, live debugging through gdb-multiarch (WinUAE GDB server: breakpoints, watchpoints, exec task list, exception capture), the IPC socket, screenshots and scripted keyboard/mouse input for tests. Use when the user wants to boot a ROM or ADF in Amiberry, debug a crash or hang live, set a breakpoint/watchpoint in the emulated 68000, follow the serial log, take a screenshot of the emulated screen, or drive the Workbench with keys and mouse clicks for a test. In reverse engineering, or for anything that runs the Commodore ROM, delegate to a separate analysis agent (clean-room firewall).
metadata:
  version: "1.0"
  tags: amiga, amiberry, emulator, gdb, serial, debugging, clean-room
---

# Amiberry sessions (serial log, live GDB, IPC, screenshots, input)

Everything goes through one script, run from the repository root:

```bash
A=.claude/skills/amiberry/scripts/amiberry-session
$A start --name s1 --adf assets/boot_c.adf      # ROM defaults to build/kick13.rom
$A wait-serial s1 "E3 CMD RAN OK" 120
$A gdb s1 -ex 'info registers' -ex 'monitor tasks'
$A shot s1 screen.png --via ipc
$A stop s1
```

`$A` alone prints the usage. Command reference for the GDB monitor and IPC: [reference.md](reference.md).
Since 2026-11-02 validation runs here: `scripts/prepush-check` before a push, then targeted sessions on the ADFs a
change touches (the WinUAE ADF suite is no longer run).

## Clean-room firewall (read first)

- **Our ROM** (`build/*.rom`) and third-party programs running on it: a session may run in the main context
  (implementation track). Long debugging sessions are still better **delegated to an agent**, which returns only
  its conclusions and keeps disassembly dumps out of the main context.
- **The Commodore ROM** (`assets/kick34005.A500`, also recognised by its SHA-256 under any name): `start` refuses
  it unless `--analysis` is given, and `--analysis` may only be used **inside a separate analysis agent**
  (CLAUDE.md, "Routing"). Such a session lives in `build/amiberry/analysis/<name>/`, which the implementation side
  never reads. The agent writes **no code** (no `src/`, `tests/`, scripts), only documentation in `docs/analysis/`,
  in English: behaviour and ABI, never instruction sequences, never ROM addresses (`docs/CLEANROOM.md`,
  `docs/AUDIT.md`).
- Live disassembly (`monitor disasm`, gdb `x/i`) of ROM code is analysis work. On our own ROM it is fine.

Brief template for an analysis agent (adapt the goal; always say "English"):

> You are the ANALYSIS track of the clean-room Kickstart 1.3 project in <repo>. Read CLAUDE.md and
> docs/CLEANROOM.md. Use the amiberry skill (`.claude/skills/amiberry/SKILL.md`): start the real ROM with
> `--analysis`, observe it as a black box (serial log, screenshots, `monitor tasks`/`watch`/`exception` through
> `amiberry-session gdb`). Goal: <question>. Write no code: documentation only, in docs/analysis/, in English, behaviour only: no
> instruction listings, no ROM addresses. Stop the sessions you started at the end (`amiberry-session stop <name>...`, never `--all`). Report
> back: findings as behaviour and figures, and the spec sections you changed.

## Sessions

- `start` options: `--name N` (default `s<slot>`), `--rom ROM`, `--adf ADF` (up to 4: DF0-DF3, each copied into the
  session directory, the original is never written), `--chip KB` (512), `--slow KB` (512), `--fast MB` (0),
  `--cycle-exact` (CPU, memory and blitter cycle-exact, slower), `--visible` (window on the current DISPLAY
  instead of a private Xvfb), `--analysis`, `--timeout S` (startup, 30), and after `--` any Amiberry argument
  (`-- -s key=value`).
- Up to 16 sessions at once. Slot `i` owns serial port `24100+2i`, GDB port `24101+2i`, an Xvfb display and the IPC
  socket `/tmp/ab<uid>-<i>/amiberry.sock`. Slots are taken under a lock, so concurrent `start`s are safe.
- Files in `build/amiberry/sessions/<name>/`: `serial.log` (everything the Amiga sent: the serial port waits for
  the logger, nothing is lost from the first byte), `amiberry.log`, `gdb.log` (every gdb run and its output),
  `xvfb.log`, `session.env`, the floppy copies, screenshots with relative names. Logs stay after `stop`; delete the
  directory yourself when done.
- `list`, `status <name>` (processes, ports, IPC PING and GET_STATUS), `serial <name> [--follow]`,
  `wait-serial <name> [--new] <text> [seconds]` (exit 1 on timeout; `--new` ignores what is already logged),
  `stop <name>... | --all`. Always stop your sessions; `stop` sends QUIT, then kills only the recorded PIDs.
- Configuration: [config.env](config.env) sets the Amiberry binary (`AMIBERRY_BIN`) and its working directory
  (`AMIBERRY_CWD`, empty = parent of the binary's directory, where Amiberry finds its `data/`). Priority:
  `start --amiberry PATH --cwd DIR` > environment variables of the same names > `config.env` > default
  (`~/dev/tools/amiberry/build/amiberry`). `$A config` prints what is resolved and checks the tools.

## Live debugging with gdb-multiarch

`$A gdb <name> [gdb arguments]` runs gdb-multiarch in batch mode, already connected (big endian, m68k, unmapped
memory readable: `scripts/m68k.gdb`), then detaches. `GDB_TIMEOUT` (default 120 s) bounds the run; `--interactive`
is for a human at a terminal.

```bash
$A gdb s1 -ex 'info registers' -ex 'x/8xw 0x4' -ex 'monitor disasm fc00d2 10'
$A gdb s1 -ex 'hbreak *0xfc7eda' -ex continue -ex 'info registers pc' -ex 'x/16xw $sp'
GDB_TIMEOUT=300 $A gdb s1 -ex 'monitor exception-mask c' -ex continue -ex 'monitor exception'
$A gdb s1 -ex 'monitor process-break name Lines' -ex continue -ex 'monitor segments'
```

- Attaching **stops the CPU**; `detach` (or gdb exiting, even when cut by the timeout) resumes it and removes what
  gdb installed (breakpoints, watches, conditions, exception mask). A reset of the Amiga drops the connection.
- Register names under gdb-multiarch: `d0`-`d7`, `a0`-`a5`, `fp` (= A6), `sp` (= A7), `ps` (= SR), `pc`.
- Addresses are physical. Our ROM is at `$FC0000`. Symbols: relink with a map (commands in
  `docs/audit/rom-similarity.md`, "Commands", with `build/` objects for the dev ROM) and read the address of a
  label, e.g. `int3_dispatch`. Only for our ROM.
- Breakpoints: `break`/`hbreak` at an even address below `$1000000`; 20 slots shared with watches and conditions.
  Data watchpoints: `watch`/`rwatch`/`awatch` (CPU accesses), or `monitor watch add|range` for value predicates,
  log-only hits, DMA sources (blitter, copper, disk) — see reference.md.
- While gdb has the CPU stopped, IPC still answers queries but refuses state changes and `input event`.

## Screenshots

`$A shot <name> <file.png> [--via xwd|ipc|gdb]` (relative names go into the session directory):

- `ipc` — the emulated picture only (752x574), while the Amiga runs. Best for looking at the screen and for aiming
  the mouse (one mouse count = one pixel of this picture).
- `xwd` (default) — the whole Xvfb screen (1024x768) with the Amiberry window in it; works whatever the emulator
  state, the image used inside `input` scripts.
- `gdb` — `monitor screenshot` with the CPU stopped: freezes the frame at a breakpoint.

Look at a picture with Read. To zoom on a region: `convert in.png -crop 300x200+380+300 +repage -scale 300% z.png`.
To tell whether the screen changes: `compare -metric AE a.png b.png null:` on two crops (0 = identical).

## Input sequences for tests

`$A input <name> <script>` (or `-` for stdin) sends keyboard, mouse and joystick input through IPC while the Amiga
runs, without a gdb client. Actions are separated by spaces or newlines; `#` starts a comment; `text:` and
`wait-serial:` take the rest of their line.

| Action | Effect |
|---|---|
| `key:44` | press and release a raw Amiga keycode (hex) |
| `down:60` / `up:60` | hold / release a key (Shift, Ctrl, Amiga...) |
| `text:dir df0:` | type a string (US layout, shift handled) |
| `mouse:DX,DY` | relative move in mouse counts (sent in small steps, one per frame) |
| `click`, `dclick`, `rclick` | left click (held 200 ms), Workbench double-click, right click |
| `ldown` / `lup`, `rdown` / `rup` | hold / release a mouse button (drag, menus) |
| `joy:1,fire,1` | joystick port, direction (`left right up down fire` or 0-6), 1 press / 0 release |
| `wait:500` | pause in milliseconds |
| `frames:5` | pause the Amiga, advance 5 frames, resume |
| `shot:name.png` | xwd screenshot into the session directory |
| `wait-serial:TEXT[,s]` | wait (default 60 s) for TEXT in serial output produced since the script started or since the previous wait; the script fails with exit 1 if it does not come |

Raw keycodes: Return `44`, Enter (keypad) `43`, Space `40`, Backspace `41`, Tab `42`, Esc `45`, Del `46`,
cursor up/down/right/left `4c 4d 4e 4f`, Help `5f`, left/right Shift `60 61`, Caps `62`, Ctrl `63`, left/right Alt
`64 65`, left/right Amiga `66 67`, F1-F10 `50`-`59`, `1`-`9` `01`-`09`, `0` `0a`, `A` `20`.

Mouse aiming: the start position is unknown, so go to the top-left corner first (`mouse:-900,-400`), take
`shot --via ipc`, read the target's pixel position on that picture and move by its offset from the pointer's tip:
one mouse count is one pixel of the IPC picture, in both directions (measured with the Workbench pointer).
Aim at the **middle of the icon image**: only the image is clickable, not its label, and the hot spot is the
pointer's tip, so a pointer whose body covers the icon can still miss it. On the Workbench 1.3.3 desktop,
`mouse:565,90` lands a few pixels left of the "Workbench1.3" disk image (the click deselects, the double-click
opens nothing); `mouse:591,97` hits it.

A test is: input, then `wait-serial` for the expected serial line, then a screenshot to look at:

```bash
cat > /tmp/wb_open.txt <<'EOF'
# Workbench 1.3.3: open the boot disk's window
mouse:-900,-400 wait:300
mouse:591,97 wait:300 dclick wait:8000
shot:wb_open.png
EOF
$A start --name wb --rom build/kick13-prod.rom --adf "assets/test_adf/Workbench 1.3.3 (34.34) - Boot (Commodore) (1991) [m2].adf"
$A wait-serial wb "Incorrect Revision" 150      # end of the Workbench startup-sequence
$A input wb /tmp/wb_open.txt && echo "input ok"
# then Read build/amiberry/sessions/wb/wb_open.png
```

On the shell of `assets/boot_c.adf`: `printf 'text:ver\nkey:44\nwait-serial:E2 SHELL ver OK,20\n' | $A input s1 -`.

For frame-exact input, use the GDB variant `monitor input sequence` (reference.md).

Keys (`key`, `down`/`up`, `text`) use IPC `SEND_KEY`, which works even while a gdb run holds the connection: arm
`monitor process-break name PROG` in a background `$A gdb ... -ex continue`, then type the command with `$A input`.
Mouse moves and joystick use `MONITOR input event`, refused while gdb is attached: move the mouse before or after.

## Pitfalls already met

- Unix socket paths are limited to 108 bytes: the IPC socket lives in a short `/tmp/ab<uid>-<i>` directory.
- Under WSLg, `Xvfb -displayfd` stalls on display `:0`; the script picks a free `/tmp/.X<n>-lock` under its lock.
- SDL must use x11 (`SDL_VIDEO_DRIVER`): with its own `XDG_RUNTIME_DIR` Amiberry would otherwise try Wayland.
- The GDB server is refused with `cpu_threaded=true`; the script forces it off.
- A new gdb connection is refused while IPC holds monitor state (watches, history...) and vice versa.
- `wait-serial` without `--new` matches anything already in the log, including an earlier run of the same command.
- After an emulated reset (`ipc RESET`, keyboard reset), the boot lines of the next boot may be missing from
  `serial.log` although later output arrives. To prove what ran after a reset, set a logging fetch watch through IPC
  before it (`PAUSE`, `MONITOR "watch range ADDR 2 4 1 0 0 0 0 1"`, `RESUME`, `RESET`, then `MONITOR "watch events"`):
  the hit gives the fetching `instruction_pc`. A reset also drops a gdb connection: reset first, then attach.
- Our exec enters supervisor through deliberate privilege violations (EXEC_SVC sites: `ori.w #0,sr` followed by
  `$4AFC`, handled by `priv_handler`). Leave vector 8 out of an exception mask (`exception-mask c`, not `dfc`) or
  every exec call stops the CPU.
