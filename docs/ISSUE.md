# Reporting a problem

*[Version française](ISSUE.fr.md)*

Thank you for testing KickSlopStart. A report we can reproduce is the fastest way to a fix. Open an issue from
the [issue chooser](https://github.com/Thaolia/KickSlopStart/issues/new/choose): the forms ask for everything
below.

## Before reporting

- Try the latest release from the [Releases](https://github.com/Thaolia/KickSlopStart/releases) page (or the
  vAmigaWeb link of the README, which always runs the latest one).
- Check the [deliberate differences](../README.md#deliberate-differences-not-bugs): the green Workbench, the kitten
  boot screen, the cat symbols in menus, the "AmigaSlopDOS" window and the purple pointer are on purpose.
- Look at the known gaps in [`docs/PLAN.md`](PLAN.md), and search the existing issues.

## What to include

- **The ROM**: the release tag (e.g. `v0.2.6`), or the file name and its SHA-256.
- **How it was loaded**: emulator, soft-kick disk, or EPROM on real hardware.
- **The emulator** and its version (FS-UAE, WinUAE, Amiberry, vAmiga/vAmigaWeb...).
- **The machine configuration**: CPU, chipset and Agnus revision, chip / slow / fast RAM sizes. An OCS Agnus
  (A500) addresses at most 512 KB of chip RAM, whatever size the emulator is given.
- **The program**: its name and the exact disk image name, and where the image comes from.
- **Steps to reproduce**, from power-on.
- **Expected vs observed**: what the same program does on a real Kickstart 1.3 with the same configuration, and
  what it does on KickSlopStart.
- **A screenshot** of the problem.
- **The serial output** if you can capture it (KickSlopStart prints boot messages on the serial port; FS-UAE and
  WinUAE can log it to a file).

## Numbers and messages

Quote the exact value or message and where it is shown, for example "the Workbench title bar shows 4009448 free
memory" or "the demo says: not enough chip memory". A number without the place it comes from cannot be checked.

## Clean-room rules

KickSlopStart is written without Commodore code (see [`docs/CLEANROOM.md`](CLEANROOM.md) and the
[clean-room audit](AUDIT.md)). To keep it that way, please **never attach or paste**:

- the original Kickstart ROM or any part of it;
- a disassembly or decompilation of it;
- Commodore source code, leaked or not.

Describing what the original ROM **does** is welcome: a screenshot, a message, a value, the order of events.

## Feature requests

Name the program that needs the feature and, if you know it, the library or device and the function it calls
(e.g. `graphics.library ScrollVPort`). Say what happens today on KickSlopStart.

## Language

English is preferred; French is welcome too.
