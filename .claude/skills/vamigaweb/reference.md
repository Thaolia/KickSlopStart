# vAmigaWeb reference: page API, RetroShell, messages

Read in the vAmigaWeb sources (`vAmigaWeb/vAmigaWeb` `9e2a2ea`, site `vAmigaWeb/vAmigaWeb.github.io` `a83eb53`,
2026-11-04) and checked against the live site on 2026-11-09 (vAmiga core 4.3.6) where marked "checked".
`V=.claude/skills/vamigaweb/scripts/vamigaweb-session`.

## How the daemon drives the page

1. Opens `VAMIGAWEB_URL#{"navbar":false,"dialog_on_missing_roms":false,"dialog_on_disk":false,
   "wait_for_kickstart_injection":true,"mouse":true}` (URL-encoded JSON, the same mechanism as the README link)
   with service workers blocked. `wait_for_kickstart_injection` keeps the page from loading a ROM of its own.
2. An init script wraps the global `message_handler(msg, d1, d2)` (every core message, `MSG_*`) and replaces the
   serial handler with `set_serial_port_out_handler`, before the wasm has compiled: nothing is lost.
3. Waits for `MSG_ROM_MISSING`, then `wasm_configure_multi("AGNUS_REVISION=..\nDENISE_REVISION=..\nCHIP_RAM=..
   \nSLOW_RAM=..\nFAST_RAM=..\nCPU_REVISION=0")`, the floppies (`wasm_loadfile(name, bytes, drive)`), the ROM
   (`wasm_loadfile("kick.rom_file", bytes)`), optional `amiga set VIDEO_FORMAT NTSC`, then `wasm_reset()`. The page
   itself starts the emulation on `MSG_READY_TO_RUN`.
4. Every 40 ms, drains the buffered serial bytes and messages into `serial.log` / `messages.log`.

## Page API used (globals of `js/vAmiga_ui.js`, raw exports `Module._wasm_*`)

| Call | Use |
|---|---|
| `wasm_loadfile(name, Uint8Array, drive=0)` | by suffix: `*.rom_file` Kickstart, `*.rom_ext_file` extension ROM, `.adf/.adz/.dms/.exe` → `df<drive>`, `.hdf` → hard disk, snapshot bytes detected by header |
| `wasm_configure(opt, value)` / `wasm_configure_multi("K=V\n...")` | `CHIP_RAM` `SLOW_RAM` `FAST_RAM` (KB), `AGNUS_REVISION` (`OCS_OLD OCS ECS_1MB ECS_2MB`), `DENISE_REVISION` (`OCS ECS`), `CPU_REVISION`, `CPU_OVERCLOCKING`, `WARP_MODE` (`AUTO NEVER ALWAYS`), `SER_DEVICE`, `DRIVE_SPEED`, `BLITTER_ACCURACY`, `floppy_drive_count`, `warp_to_frame`. RAM and revision changes power the machine off first. Returns an error string, empty on success |
| `wasm_get_config_item(opt)` | read an option back |
| `wasm_reset()` | hard reset · `wasm_halt()` / `wasm_run()` pause / resume · `Module._wasm_execute_one_frame()` one frame, returns true when a trap stopped it |
| `wasm_peek(a)`, `wasm_peek16(a)` | side-effect-free reads (spypeek) · `wasm_poke(a, byte)` · `wasm_mem_patch(a, bytes)` |
| `wasm_key(rawcode, 1\|0)` | Amiga raw keycode down/up (applied at once) |
| `wasm_mouse(port, dx, dy)` | relative move, port 1 or 2, scaled by `MOUSE_VELOCITY` (100 = 1:1) |
| `wasm_mouse_button(port, 1 left\|2 middle\|3 right, 1\|0)` | buttons |
| `wasm_joystick("1PULL_UP")` | port digit + `PULL_UP/DOWN/LEFT/RIGHT`, `RELEASE_X/Y/XY`, `PRESS_FIRE`, `RELEASE_FIRE` |
| `wasm_write_string_to_ser(s)`, `Module._wasm_write_byte_to_ser(b)` | serial input |
| `wasm_eject_disk("df0")`, `wasm_has_disk("df0")` | floppies |
| `wasm_take_user_snapshot()` → `{address,size,...}`, then `wasm_delete_user_snapshot()` | snapshot bytes in `Module.HEAPU8` |
| `Module._wasm_pixel_buffer()` | RGBA texture, 1824 x 313 (`HPIXELS = 912*2`, `VPIXELS = 313`); the daemon halves the width and doubles the lines |
| `Module._wasm_frame_info()` | `(frame << 2) \| (prevlof << 1) \| lof` |
| `Module._wasm_is_warping()`, `wasm_get_cpu_cycles()` (BigInt), `wasm_get_core_version()` | state |
| `wasm_retro_shell_press_key(charCode)` | type into RetroShell; runs the command queue at once, even paused (`10` = Return) |
| `wasm_retro_shell_get_text()` | the console text |

Serial output: Paula's UART raises `MSG_SER_OUT` with the SERDAT word for every byte whatever `SER_DEVICE` is; the
default page handler keeps only the last 4 KB, ours keeps everything. The frame loop is `requestAnimationFrame`
driven: a hidden or throttled page runs slowly, hence the Chromium flags against background throttling.

## RetroShell commands (debugger console, from `DebuggerConsole.cpp`)

| Command | Use |
|---|---|
| `break at A` / `break delete N` / `break toggle N` / `break` | CPU breakpoints (checked) |
| `watch at A` / `watch delete N` / `watch` | data watchpoints (checked) |
| `catch vector N` / `catch interrupt N` / `catch trap N` / `catch delete N` | exception catchpoints (`catch vector 3` checked) |
| `cbreak at` / `cwatch at` | copper breakpoints / watchpoints |
| `btrap at` | beam traps |
| `step` (`s`), `next` (`n`), `goto A` (`g`), `pause` (`p`) | execution |
| `r cpu` (checked), `r agnus`, `r blitter`, `r ciaa`, `r ciab`, `r copper`, `r denise`, `r paula`, `r rtc` | registers |
| `m[.b\|.w\|.l] A`, `d A` | memory dump, disassembly (analysis work on the Commodore ROM) |
| `os execbase`, `os tasks`, `os libraries` (checked); `os devices`, `os resources`, `os interrupts`, `os processes`, `os info` | exec state |
| `os set diagboard true` then `os catch NAME` | pause when a task named NAME starts (needs vAmiga's diagnose board) |
| `? cpu`, `? memory`, `? memory bankmap`, `? zorro`, `? zorro board`, `? cia`, `? copper list`, `? paula uart`, `? serial`, `? df0`, `? mouse`, `? keyboard` | inspectors |
| `commander` | back to the configuration console (`amiga`, `amiga set VIDEO_FORMAT NTSC` checked) |

Prompt lines read `(beam v,h) $PC:`. An unknown command answers `Syntax error`, a missing argument
`Too few arguments.`

## Core messages (`messages.log`)

`MSG_BREAKPOINT_REACHED`, `MSG_WATCHPOINT_REACHED`, `MSG_CATCHPOINT_REACHED`, `MSG_SWTRAP_REACHED`,
`MSG_BEAMTRAP_REACHED` (each followed by `MSG_PAUSE`), `MSG_RUN`, `MSG_PAUSE`, `MSG_RESET`, `MSG_DISK_INSERT`,
`MSG_DISK_EJECT`, `MSG_VIDEO_FORMAT`, `MSG_MEM_LAYOUT`, `MSG_SNAPSHOT_RESTORED`. Page `alert()` dialogs appear as
`DIALOG alert: ...` and are dismissed.
