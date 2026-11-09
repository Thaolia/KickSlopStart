---
name: vamigaweb
description: Run this project's Kickstart ROM (or a disk on it) in the live vAmigaWeb site (vAmiga core in the browser), driven headless by Playwright/Chromium, several sessions at once, with the serial output logged to a file, RetroShell debugging (breakpoints, watchpoints, catchpoints, registers, exec task list), memory peek/poke, frame stepping, snapshots, screenshots and scripted keyboard/mouse/joystick input. Use when the user wants to reproduce what vAmigaWeb users see (the README link), test a vAmiga-only bug, compare vAmiga with Amiberry, or debug our ROM under vAmiga. In reverse engineering, or for anything that runs the Commodore ROM, delegate to a separate analysis agent (clean-room firewall).
metadata:
  version: "1.0"
  tags: amiga, vamiga, vamigaweb, emulator, playwright, serial, debugging, clean-room
---

# vAmigaWeb sessions (serial log, RetroShell debugger, memory, snapshots, screenshots, input)

Everything goes through one script, run from the repository root:

```bash
V=.claude/skills/vamigaweb/scripts/vamigaweb-session
$V start --name v1 --adf assets/boot_c.adf        # ROM defaults to build/kick13.rom
$V wait-serial v1 "E3 CMD RAN OK" 120
$V shell v1 debugger "os tasks"
$V shot v1 screen.png
$V stop v1
```

`$V` alone prints the usage. API, RetroShell commands and messages: [reference.md](reference.md).

Why this skill exists: users run our ROM in vAmigaWeb through the README link, and some bugs only showed there
(fast RAM lost after vAmiga's soft RESET, a 2 MB chip + 2 MB fast configuration, LOF at reset). This is the same site
and the same vAmiga core as theirs, not a local build.

## Setup and network

- `$V setup` once: `npm ci` in the skill directory (Playwright **1.62.1**, pinned in `package-lock.json`;
  `node_modules/` is git-ignored) and `playwright install chromium`. `$V config` checks it.
- The page is the **live site** `https://vamigaweb.github.io/` (`VAMIGAWEB_URL` in [config.env](config.env), or
  `start --url`). It changes under our feet: `start` and `status` print the vAmiga core version (4.3.6 on
  2026-11-09); quote it with any vAmiga finding.
- The ROM and the ADFs are read locally by the daemon and handed to the page with `wasm_loadfile`: **nothing is
  uploaded** to the site. Only the site's own files are downloaded.

## Clean-room firewall (read first)

- **Our ROM** (`build/*.rom`) and third-party programs on it: sessions may run in the main context. Long debugging
  is better **delegated to an agent** that returns only conclusions.
- **The Commodore ROM** (`assets/kick34005.A500`, also recognised by its SHA-256 under any name): `start` refuses it
  unless `--analysis` is given, and `--analysis` may only be used **inside a separate analysis agent** (CLAUDE.md,
  "Routing"). Such a session lives in `build/vamigaweb/analysis/<name>/`, which the implementation side never reads.
  The agent writes **no code**, only documentation in `docs/analysis/`, in English: behaviour and ABI, never
  instruction sequences, never ROM addresses.
- RetroShell disassembly (`d`), `m` dumps and `r cpu` PCs of ROM code are analysis work. On our own ROM they are fine.

Brief template for an analysis agent (adapt the goal; always say "English"):

> You are the ANALYSIS track of the clean-room Kickstart 1.3 project in <repo>. Read CLAUDE.md and
> docs/CLEANROOM.md. Use the vamigaweb skill (`.claude/skills/vamigaweb/SKILL.md`): start the real ROM with
> `--analysis`, observe it as a black box (serial log, screenshots, `shell ... "os tasks"`, catchpoints). Goal:
> <question>. Write no code: documentation only, in docs/analysis/, in English, behaviour only: no instruction
> listings, no ROM addresses. Stop the sessions you started (`vamigaweb-session stop <name>...`). Report back:
> findings as behaviour and figures, the vAmiga core version, and the spec sections you changed.

## Sessions

- `start` options: `--name N` (default `v<n>`), `--rom ROM`, `--adf ADF` (up to 4: DF0-DF3, copied into the
  session directory; more than one connects that many drives), `--model A500|A500+` (A500 = OCS, 512 KB chip +
  512 KB slow, the default; A500+ = ECS 2 MB Agnus + ECS Denise, 1 MB chip), `--chip KB`, `--slow KB`, `--fast KB`
  (**KB**, not MB as in amiberry), `--agnus OCS_OLD|OCS|ECS_1MB|ECS_2MB`, `--ntsc`, `--warp auto|never|always`
  (the site's default is `never`), `--url URL`, `--visible` (a real Chromium window), `--analysis`,
  `--timeout S` (startup, 120). The CPU is always a 68000.
- The user reports of 2026-11-04 used `--model A500+ --chip 2048 --fast 2048` (vAmigaWeb's "A500+ boost").
- Each session = one detached Node daemon (its own process group) + one Chromium, controlled through a Unix socket
  in `/tmp/vw<uid>/`. Sessions are independent and can run at once (two in parallel checked on 2026-11-09).
- Files in `build/vamigaweb/sessions/<name>/`: `serial.log` (raw bytes, from the first one: the serial hook is in
  place before the ROM is loaded), `messages.log` (core messages `MSG_*` with time, and every `alert()` the page
  raised as `DIALOG`), `shell.log` (RetroShell commands and output), `console.log` (browser console), `daemon.log`,
  `session.json`, floppy copies, screenshots and snapshots with relative names. Logs stay after `stop`.
- `list`, `status <name>` (running, frame, warp, cycles, RAM sizes, core version), `serial <name> [--follow]`,
  `wait-serial <name> [--new] TEXT [s]` and `wait-msg <name> [--new] MSG [s]` (exit 1 on timeout; without
  `--new` anything already logged matches), `stop <name>...` (kills only that session's process group).

## Debugging

The browser has no sockets, so there is no gdb here: debugging goes through vAmiga's **RetroShell**.
`$V shell <name> LINE...` types each line into it (key by key, so it works while the emulation is paused) and prints
only the console text that the lines produced.

- Two consoles: `commander` (configuration: `amiga`, `amiga set VIDEO_FORMAT NTSC`, `memory`, `df0`...) and
  `debugger` (`break`, `watch`, `catch`, `r`, `m`, `d`, `os`, `step`, `next`). Lines go to the current console:
  switch first (`$V shell v1 debugger "os tasks"`). Unknown commands answer `Syntax error`.
- Breakpoint, then where it stopped:
  ```bash
  $V shell v1 debugger 'break at $fc70c6'          # an address from our vlink map
  $V wait-msg v1 --new MSG_BREAKPOINT_REACHED 60   # the emulation is now paused
  $V shell v1 "r cpu"                              # PC, SR, D0-D7, A0-A7
  $V shell v1 "break delete 0"; $V run v1
  ```
  Watchpoints (`watch at ADDR`) and catchpoints (`catch vector 3`) report `MSG_WATCHPOINT_REACHED` /
  `MSG_CATCHPOINT_REACHED` the same way. Our exec enters supervisor through deliberate privilege violations
  (EXEC_SVC): do not catch vector 8.
- Exec state: `os execbase`, `os tasks`, `os libraries` (debugger console; checked), and the other `os`
  subcommands listed in reference.md. There is no command to write CPU registers.
- Memory: `$V peek v1 ADDR [b|w|l] [COUNT]` (hex address, side-effect-free reads: custom registers can be read
  without acknowledging anything), `$V poke v1 ADDR VALUE [b|w|l]`. ExecBase: `$V peek v1 4`.
- Execution: `pause`, `run`, `reset` (hard reset), `frames v1 K` (pause, run exactly K frames, stay paused; stops
  early on a trap).
- Snapshots: `snapshot v1 save s.vAmiga` / `snapshot v1 load s.vAmiga` (restores the machine, screen included;
  checked pixel-identical on 2026-11-09). A snapshot is tied to the core version.
- Floppies: `eject v1 0`, `insert v1 x.adf 0` (a fresh copy each time; `MSG_DISK_EJECT` / `MSG_DISK_INSERT` logged).
- Serial input: `ser-in v1 TEXT`. Raw page access: `js v1 'EXPRESSION'` (result as JSON).

## Screenshots

`$V shot <name> <file.png> [--via heap|canvas|page]` (relative names go into the session directory):

- `heap` (default) — the whole emulator texture, overscan and blanking included, **912 x 626** (one hires pixel per
  column, each line doubled). Works while paused. The picture used for mouse aiming below.
- `canvas` — the picture as the page shows it (clipped and scaled, 1244 x 960 with the default viewport).
- `page` — the whole page (vAmigaWeb UI included).

Zoom: `convert in.png -crop 300x200+380+300 +repage -scale 300% z.png`. Change test: `compare -metric AE a b null:`.

## Input sequences for tests

`$V input <name> <script>` (or `-` for stdin): the same language as the amiberry skill.

| Action | Effect |
|---|---|
| `key:44` | press and release a raw Amiga keycode (hex) |
| `down:60` / `up:60` | hold / release a key |
| `text:dir df0:` | type a string (US layout, shift handled) |
| `mouse:DX,DY` | relative move in mouse counts (sent in steps of 32, 40 ms apart) |
| `click`, `dclick`, `rclick` | left click (held 200 ms), double-click, right click |
| `ldown` / `lup`, `rdown` / `rup` | hold / release a mouse button |
| `joy:2,fire,1` | joystick port, direction (`left right up down fire`), 1 press / 0 release |
| `wait:500` | pause in milliseconds |
| `frames:5` | pause, run exactly 5 frames, resume |
| `shot:name.png` | heap screenshot into the session directory |
| `wait-serial:TEXT[,s]` | wait (default 60 s) for TEXT in serial output since the script started or since the previous wait |

Raw keycodes: Return `44`, Space `40`, Backspace `41`, Tab `42`, Esc `45`, Del `46`, cursor `4c 4d 4e 4f`, Help
`5f`, Shift `60 61`, Caps `62`, Ctrl `63`, Alt `64 65`, Amiga `66 67`, F1-F10 `50`-`59`.

Mouse aiming (measured 2026-11-09 on our ROM, A500, core 4.3.6): go to the top-left corner first
(`mouse:-2000,-1000`); the pointer's tip is then at **(188,88) of the heap picture**. Two mouse counts move it one
pixel of that picture, on both axes: to put the tip on heap pixel (X,Y), move `mouse:2*(X-188),2*(Y-88)` (checked:
`mouse:624,424` lands the tip on (500,300)). The mouse is on port 1.

```bash
printf 'text:ver\nkey:44\nwait-serial:E2 SHELL ver OK,30\n' | $V input v1 -
```

## Pitfalls already met

- The site's service worker reloads the page on first visit and caches by version: the daemon blocks service
  workers. A Chromium without WebAssembly exnref is sent to `/legacy/` (the start fails with that message).
- Status values may be 64-bit (cycle counter): the daemon converts BigInt before replying.
- `wasm_peek16`/long peeks need an even address; `peek` refuses an odd one.
- vAmiga's 68000 RESET instruction is a soft reset that does **not** put Zorro boards back into autoconfig (a hard
  reset does): a ROM that reboots with RESET loses its fast RAM under vAmiga only.
- vAmiga starts with LOF = 1, Amiberry and WinUAE with LOF = 0: a frame-type dependency shows as a difference
  between the two skills.
- `wait-serial` without `--new` matches anything already in the log.
