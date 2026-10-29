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
curl -fsSLO http://sun.hasenbraten.de/vasm/release/vasm.tar.gz
curl -fsSLO http://sun.hasenbraten.de/vlink/release/vlink.tar.gz
tar xzf vasm.tar.gz && tar xzf vlink.tar.gz
make -C vasm CPU=m68k SYNTAX=mot      # -> vasmm68k_mot
make -C vlink                          # -> vlink
cp vasm/vasmm68k_mot vlink/vlink ~/.local/bin/
```
Validated versions: vasm **2.0f**, vlink **V0.18a**. Useful vlink option from M2 on: `-kick1` (Kickstart 1.x
loader compat) and `rawbin`/`ados` outputs. C alternative (modules in C later): gcc
**bebbo** `m68k-amigaos-gcc` (KS1.3 runtime: `-mcrt=nix13`).

### amitools (already installed, pipx)
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

### Analysis (dirty track)
**radare2 6.1.3** (`r2 -a m68k -e cfg.bigendian=true`, base `$FC0000`). Ghidra headless optional for
the decompiler (see the ghidra-mcp rule: one dedicated instance per binary).
