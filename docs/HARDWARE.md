# Hardware target & toolchain

## Amiga 500 (target)

- **Motorola 68000** CPU, big-endian, no MMU.
- **Kickstart ROM 256 KiB** mapped at **`$FC0000`–`$FFFFFF`**; mirrored at `$0` on reset (OVL overlay,
  driven by the CIA). Chip RAM from `$000000` (512 KiB on the original A500).
- Chipset (OCS): custom addresses from `$DFF000` (e.g. `$DFF096` DMACON, `$DFF09A` INTENA,
  `$DFF09C` INTREQ, `$DFF180` COLOR00, `$DFF030/032/018` SERDAT/SERPER/SERDATR). CIA 8520 at `$BFE001`/`$BFD000`.
- At power-on: DMA and interrupts must be neutralised very early (the hello coldstart does it).

### Real ROM (EPROM) — note for M7
A 256K Kickstart is replaced by a suitable EPROM/flash (typically a 27C400 4 Mbit with handling
of the address lines, or an adapter). To be detailed at hardware-porting time; the emulator
is enough until then.

## Toolchain (host, WSL2 Debian)

### 68k assembler / linker — vasm + vlink (Frank Wille)
Not packaged: built from source, installed in `~/.local/bin`.

```sh
mkdir -p ~/.cache/amiga-tc && cd ~/.cache/amiga-tc
curl -fsSLO https://slackware.uk/sbosrcarch/by-name/development/vasm/vasm2_0f.tar.gz
echo "c84b2de1cbb87831795fe64a85c5d9a7002a766e3a7c30b0a2d7d5e99d878f49  vasm2_0f.tar.gz" | sha256sum -c -
tar xzf vasm2_0f.tar.gz
git init -q vlink && git -C vlink fetch -q --depth 1 https://github.com/AmigaPorts/vlink.git \
  ce46ccfda0e30eda5b12b9a5d0259d8eaefdefe9 && git -C vlink checkout -q FETCH_HEAD   # vlink 0.18
make -C vasm CPU=m68k SYNTAX=mot      # -> vasmm68k_mot
make -C vlink                          # -> vlink
cp vasm/vasmm68k_mot vlink/vlink ~/.local/bin/
```
Validated versions: vasm **2.0f**, vlink **V0.18a**, then **V0.18** (2026-11-09: `sun.hasenbraten.de` and
`phoenix.owl.de` serve no tarball any more; the vasm 2.0f SlackBuilds archive and vlink 0.18 from the AmigaPorts
mirror give a production ROM and a soft-kick ADF byte-identical to the phoenix 2.0f / 0.18a builds). The vbcc
binary bundle's vlink 0.17a rejects vasm 2.0f objects ("Relocation type 34 is not supported"). Useful vlink option from M2 on: `-kick1` (Kickstart 1.x
loader compat) and `rawbin`/`ados` outputs. C alternative (modules in C later): gcc
**bebbo** `m68k-amigaos-gcc` (KS1.3 runtime: `-mcrt=nix13`).

### amitools (pipx)
`pipx install amitools`.
`romtool` (ROM info/build/split/copy, checksum), `fdtool` (LVOs from `.fd`), `xdftool` (ADF),
`vamos` (runs AmigaOS binaries on the host — can NOT host our own exec).

### Emulator
**FS-UAE 3.2.35** (Debian) + **Xvfb** for headless boot / CI. Screen capture via `xwd` + ImageMagick
(`convert`). On the Windows side, `WinUAE.exe` (WSL2 interop) remains an option, especially for a robust serial log
from M2 on. FS-UAE config keys: `amiga_model`, `kickstart_file`, `chip_memory` (see `tests/boot_test.sh`).

**WinUAE Linux** (Unix port of WinUAE, AppImage extracted wherever you like; its `AppRun` launcher is given to
`tests/adf_suite_winuae.sh` through the `WINUAE` variable, or placed in the PATH under the name `winuae`) for a hardware-faithful A500: config file `-f a500.uae` with `use_gui=no`, `cpu_model=68000`,
`cpu_cycle_exact=true`, `cycle_exact=true`, `chipset=ocs`, `chipmem_size=1` + `bogomem_size=2` (512 KB chip + 512 KB
slow), `floppy_speed=100` (floppy at real speed), under Xvfb with `QT_QPA_PLATFORM=xcb SDL_AUDIODRIVER=dummy`.
Serial: **`unix.serial_port=TCP://127.0.0.1:<port>`** (the `serial_port` key of Windows WinUAE is unknown to this
port), read by `socat -u TCP:127.0.0.1:<port> -`; the coldstart arrives from the very first line. Keyboard injected by
xdotool: `SDL_VIDEO_X11_XINPUT2=0 QT_XCB_NO_XI2=1` and focus on the window under the mouse; the mouse is only captured
after a first click. ADF suite: `tests/adf_suite_winuae.sh [rom] [seconds]`.

### Amiberry (`/amiberry` skill, `prepush-check`)
**Amiberry v8.4.2**, built from source where `.claude/skills/amiberry/config.env` expects it. It needs SDL3, not SDL2.
```sh
sudo apt install ninja-build libsdl3-dev libsdl3-image-dev libflac-dev libmpg123-dev libmpeg2-4-dev libpng-dev \
  libjpeg-dev libavcodec-dev libavformat-dev libavutil-dev libswresample-dev libswscale-dev libwebp-dev \
  libserialport-dev libportmidi-dev libenet-dev libpcap-dev libzstd-dev zlib1g-dev libcurl4-openssl-dev \
  nlohmann-json3-dev libgl-dev
git clone https://github.com/BlitterStudio/amiberry ~/dev/tools/amiberry && cd ~/dev/tools/amiberry
git checkout v8.4.2 && cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release && cmake --build build
```
Other host packages used by the harnesses: `fs-uae gdb-multiarch socat pipx python3-unicorn` (plus `Xvfb`, `xdotool`,
`x11-apps` for `xwd`, ImageMagick). Copperline (`make test-graphics`) is not packaged and not covered here.

### vAmigaWeb (`/vamigaweb` skill)
The live site `https://vamigaweb.github.io/` (vAmiga core 4.3.6 on 2026-11-09), driven in headless Chromium by
**Playwright 1.62.1** (pinned in `.claude/skills/vamigaweb/package-lock.json`). Needs **Node.js** (v24 used) and
network access; `.claude/skills/vamigaweb/scripts/vamigaweb-session setup` runs `npm ci` and installs Playwright's
Chromium. The ROM and ADFs are handed to the page locally, never uploaded. Debugging goes through vAmiga's
RetroShell (no gdb in a browser).

### Analysis (dirty track)
**radare2 6.1.3** (`r2 -a m68k -e cfg.bigendian=true`, base `$FC0000`). Ghidra headless optional for
the decompiler (see the ghidra-mcp rule: one dedicated instance per binary).
