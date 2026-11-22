# A600/A1200 IDE hard disk

*[Version française](IDE-HARDDISK.fr.md)*

KickSlopStart has a driver for the built-in IDE port of the A600 and A1200 (`scsi.device`, units 0 and 1). It only
starts when the machine's Gayle chip answers, so nothing changes on an A500 or A2000. It works the same in the ROM
and in the soft-kick image, so an A600 or A1200 soft-kicked from its own Kickstart reads its hard disk or CF card.

- Partitions of the disk's Rigid Disk Block are mounted as DH0:, DH1: and so on, under the names given by the
  partitioning tool, with OFS or FFS (DOS\0 to DOS\3, international modes included), read and write.
- They are mounted only: the machine always boots from a floppy, even when a partition is marked bootable, because an
  A600's boot partition usually holds a 2.x/3.x Workbench that cannot run on a 1.3 system.
- Not supported: WHDLoad (it needs Kickstart 2.0, which is also true of the real 1.3), PFS3, SFS and other
  third-party filesystems, DOS\4 to DOS\7 (directory caches, long names), disks beyond 4 GB, PCMCIA cards, the A4000
  IDE port.
- Transfers are polled PIO, one 512-byte block at a time in the filesystem: about 115 KB/s on a 68000 under
  emulation, five times a floppy.
- Memory does not grow with the partition: about 4 bytes per bitmap block plus a cache of 8 blocks (a 1.1 GB
  partition costs about 6 KB). Rebuilding the bitmap of a big partition after a crash takes a few minutes.
- Tested under emulation (Amiberry, A600 and A1200 profiles) with our ROM as host and with a 3.1 Kickstart as
  soft-kick host, on partitions from 8 MB to 3.9 GB; not tried yet on real hardware, feedback is welcome.

The same filesystem also reads and writes FFS floppies (formatted under 2.x/3.x), on any machine.
