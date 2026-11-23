KickSlopStart is a clean-room reimplementation of a **Kickstart 1.3-compatible** ROM for the Amiga 500 (256 KiB,
mapped at `$FC0000`, plain 68000). This image is built automatically from the tagged source by the repository's
release workflow.

**This is not a Commodore ROM.** It contains no Commodore code; see the [clean-room audit](https://github.com/Thaolia/KickSlopStart/blob/main/docs/AUDIT.md)
for the measured evidence. It is released under the MIT License.

## Using it

- **Emulators:** select the `.rom` file as the Kickstart ROM in FS-UAE (`kickstart_file`) or WinUAE, with an A500
  configuration (68000, OCS, 512 KiB chip RAM; 512 KiB slow RAM recommended). It boots Workbench 1.3.3 and a number
  of games and tools; see the README for what works.
- **Soft-kick disk:** boot the `.adf` from the Kickstart already in the machine. It loads KickSlopStart into Zorro II
  fast RAM (`$200000`-`$9FFFFF`, an A500/A2000 memory board or an A600/A1200 trapdoor board) when there is some,
  otherwise into slow RAM at `$C00000`, otherwise into chip RAM above 512 KiB (at least 1 MiB of chip RAM: A500 with
  a 1 MiB Agnus, A1200; 256 KiB of chip RAM are taken), then waits on its insert-disk screen for the disk to boot. A
  reset comes back to KickSlopStart (a small relay in low chip RAM configures the fast RAM boards again first);
  switching off returns to the Kickstart in ROM. Tested under emulation from Kickstart 1.3, 2.05 (A600), 3.0 (A1200)
  and 3.1 hosts, 68000 to 68060, cycle-exact or not; fast RAM placement is not tried yet on real hardware. On an A600/A1200 the built-in IDE hard disk or CF card is mounted (RDB partitions read and write,
  FAT12/16/32 read-only), the machine still boots from a floppy; PCMCIA is not supported. See
  [IDE-HARDDISK.md](https://github.com/Thaolia/KickSlopStart/blob/main/docs/IDE-HARDDISK.md).
- **Real hardware:** the soft-kick disk boots on a real A500 (512 KiB chip + 512 KiB slow RAM). The `.rom`
  in an EPROM is not tested yet: a 256 KiB image is what a Kickstart 1.3 socket expects; EPROM adapters may need the
  image doubled or byte-swapped, depending on the chip.

## Status

Work in progress: large parts of exec, graphics, layers, intuition, dos and the Workbench run, but some programs
still fail. Bug reports are welcome as GitHub issues; the [reporting guide](https://github.com/Thaolia/KickSlopStart/blob/main/docs/ISSUE.md)
lists what to include.

Some differences are deliberate and are not bugs: the CDE-like Workbench colours, the kitten boot screen and the cat
symbols in menus. See "Deliberate differences" in the README.
