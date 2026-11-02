KickSlopStart is a clean-room reimplementation of a **Kickstart 1.3-compatible** ROM for the Amiga 500 (256 KiB,
mapped at `$FC0000`, plain 68000). This image is built automatically from the tagged source by the repository's
release workflow.

**This is not a Commodore ROM.** It contains no Commodore code; see the [clean-room audit](https://github.com/Thaolia/KickSlopStart/blob/main/docs/AUDIT.md)
for the measured evidence. It is released under the MIT License.

## Using it

- **Emulators:** select the `.rom` file as the Kickstart ROM in FS-UAE (`kickstart_file`) or WinUAE, with an A500
  configuration (68000, OCS, 512 KiB chip RAM; 512 KiB slow RAM recommended). It boots Workbench 1.3.3 and a number
  of games and tools; see the README for what works.
- **Soft-kick disk:** the `.adf` loads KickSlopStart into slow RAM from an A500 that keeps its Kickstart 1.3
  (512 KiB slow RAM at `$C00000` required), then waits on its insert-disk screen for the disk to boot. A reset comes
  back to KickSlopStart; switching off returns to the Kickstart in ROM.
- **Real hardware:** the soft-kick disk boots on a real A500 (minimum 512 KiB chip + 512 KiB slow RAM). The `.rom`
  in an EPROM is not tested yet: a 256 KiB image is what a Kickstart 1.3 socket expects; EPROM adapters may need the
  image doubled or byte-swapped, depending on the chip.

## Status

Work in progress: large parts of exec, graphics, layers, intuition, dos and the Workbench run, but some programs
still fail. Bug reports are welcome as GitHub issues; the [reporting guide](https://github.com/Thaolia/KickSlopStart/blob/main/docs/ISSUE.md)
lists what to include.

Some differences are deliberate and are not bugs: the green Workbench colours, the kitten boot screen and the cat
symbols in menus. See "Deliberate differences" in the README.
