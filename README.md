# KickSlopStart — a clean-room Kickstart 1.3 for the Amiga 500

*[Version française](README.fr.md)*

<p align="center"><img src="assets/boot_screen/cat_amiga_kickslopstart.jpg" alt="KickSlopStart boot screen" width="480"></p>

KickSlopStart is an open-source reimplementation of the Amiga **Kickstart 1.3** ROM (34.5), written from scratch in
68000 assembly using **clean-room** methods. The image is **256 KiB, loaded at `$FC0000`** and runs on a plain
**68000**. It is meant as a drop-in replacement for the original Kickstart on the A500/A1000/A2000. It boots in an
emulator today; booting it on a real A500 from an EPROM is a later goal.

This repository contains **no Commodore code** and does **not** ship the original ROM. Because the code was written
with an LLM that may have seen leaked Kickstart sources, this claim is checked by measurement rather than taken on
trust: see the [clean-room audit](docs/AUDIT.md) (binary comparison with the 1.3 ROM, source comparison with AROS,
review of the analysis notes, and the list of ROM data deliberately kept for compatibility).

## What works

All results below come from booting the ROM in an emulator (FS-UAE, and WinUAE in cycle-exact A500 mode), with
screenshots or serial output as evidence.

- **exec**: the full V34 function table, a preemptive scheduler, user-mode tasks, interrupt servers, resident
  modules, libraries and devices, semaphores and a memory allocator.
- **Devices and resources**: trackdisk (read and write, interrupt-driven DMA), timer (VBLANK and MICROHZ), keyboard,
  input, console, gameport (mouse), audio, cia, disk, misc, potgo, keymap (US and French AZERTY), expansion (Zorro II
  autoconfig), romboot.
- **Graphics**: graphics.library (views, copper lists, blitter, text, regions, GELs) and layers.library.
- **Intuition**: screens, windows with 1.3-style frames, gadgets (boolean, proportional), menus, requesters,
  AutoRequest, Preferences.
- **AmigaDOS**: dos.library with a BCPL runtime, an OFS filesystem handler (read and write), LoadSeg, the CLI and
  shell, RAM:, PIPE:, AUX:, NEWCON:, a disk validator, and booting from a UAE hard disk (DH0:).
- **Workbench 1.3.3** boots to its desktop: disk and drawer icons, Shell, menus, Info, Duplicate/DiskCopy, Clean Up
  and Preferences all work.
- **Software tested**: SetPatch 1.38, SysInfo, Holiday Lemmings (playable), Caesar, SimCity 1.2, The Secret of Monkey
  Island (disk 1), Scooby-Doo and Scrappy-Doo.

Known gaps and the detailed roadmap are in [`docs/PLAN.md`](docs/PLAN.md).

## Clean-room method

The work is split into two tracks that never mix (see [`docs/CLEANROOM.md`](docs/CLEANROOM.md)):

- **Analysis track**: observes the original ROM (disassembly, probes, debugger) and writes **behaviour and ABI
  descriptions only** to [`docs/analysis/`](docs/analysis/). No instruction sequences are ever copied.
- **Implementation track**: writes `src/` from public documentation (RKRM, NDK, AutoDocs, `.fd` files), AROS as a
  read-only reference, and the analysis specs. It never reads the ROM or its disassembly.

## Building

Requirements, all in the `PATH`:

- `vasmm68k_mot` and `vlink` (Frank Wille's assembler and linker, built from source)
- `romtool` (from [amitools](https://github.com/cnvogelg/amitools))
- `python3`

Installation instructions are in [`docs/HARDWARE.md`](docs/HARDWARE.md).

```sh
make             # build/kick13.rom       development ROM (includes the self-test harness)
make kick-prod   # build/kick13-prod.rom  production ROM (-DPROD=1, no test harness)
make verify      # checks the size (256 KiB) and that romtool reports is_kick = ok
```

Use `build/kick13-prod.rom` for everyday use in an emulator. The development ROM also runs demo tasks and test
probes during boot.

For a French AZERTY keymap, set `KEYMAP_AZERTY` to 1 in `src/exec/exec.i` before building.

## Testing

The tests boot the ROM headless under Xvfb and check serial markers or screenshots. They need `fs-uae`, `Xvfb`,
`socat`, `xwd` and ImageMagick.

```sh
tests/boot_test.sh                       # boots FS-UAE and checks the serial log
WINUAE=/path/to/AppRun tests/adf_suite_winuae.sh build/kick13-prod.rom 120
                                         # boots every ADF in assets/test_adf/ in WinUAE (cycle-exact A500)
```

`tests/adf_suite_winuae.sh` looks for WinUAE in the `WINUAE` variable, or as `winuae` in the `PATH`. You supply the
disk images yourself; they are not included.

## Repository layout

```
src/exec/        exec.library, devices and resources
src/graphics/    graphics.library, layers.library, boot screen
src/intuition/   intuition.library
src/dos/         dos.library, handlers, CLI/shell, Workbench
src/rom/         ROM packer (padding, footer, checksum) and the M0 hello ROM
docs/            plan, architecture, hardware/toolchain, clean-room rules
docs/analysis/   specs written by the analysis track
tests/           emulator harnesses and test programs
assets/          boot screen image; your own ROM and ADF files go here (git-ignored)
```

## Legal

- The original Kickstart ROM is copyrighted. It is **not** included and must never be committed. For analysis and
  comparison, put your own copy of `kick34005.A500` in `assets/`; it is git-ignored.
- Game and Workbench disk images are not included either.
- AROS is consulted as a reference only; none of its code is copied into `src/` (measured in
  [docs/audit/aros-similarity.md](docs/audit/aros-similarity.md)).
- Amiga is a trademark of its respective owner. This project is not affiliated with it.

## License

The code in this repository is released under the [MIT License](LICENSE). This covers only the files in this
repository; it grants no rights over the original Kickstart ROM, AmigaOS or any disk image.
