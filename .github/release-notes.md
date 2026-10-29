KickSlopStart is a clean-room reimplementation of a **Kickstart 1.3-compatible** ROM for the Amiga 500 (256 KiB,
mapped at `$FC0000`, plain 68000). This image is built automatically from the tagged source by the repository's
release workflow.

**This is not a Commodore ROM.** It contains no Commodore code; see the [clean-room audit](https://github.com/Thaolia/KickSlopStart/blob/main/docs/AUDIT.md)
for the measured evidence. It is released under the MIT License.

## Using it

- **Emulators:** select the `.rom` file as the Kickstart ROM in FS-UAE (`kickstart_file`) or WinUAE, with an A500
  configuration (68000, OCS, 512 KiB chip RAM; 512 KiB slow RAM recommended). It boots Workbench 1.3.3 and a number
  of games and tools; see the README for what works.
- **Real hardware:** not tested yet. A 256 KiB image is what a Kickstart 1.3 socket expects; EPROM adapters may need
  the image doubled or byte-swapped, depending on the chip.

## Status

Work in progress: large parts of exec, graphics, layers, intuition, dos and the Workbench run, but some programs
still fail. Bug reports with the disk image name and a screenshot are welcome as GitHub issues.
