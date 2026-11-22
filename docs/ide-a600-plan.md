# A600/A1200 IDE hard disk support (plan, 2026-11-22)

Status: P0-P5 done under emulation (2026-11-22); not yet tried on real hardware.

## Goal

KickSlopStart, soft-kicked from the A600's own Kickstart (or burnt in a ROM), mounts the partitions of the hard disk
on the A600/A1200 built-in IDE port, so that programs and HD-installed games can be read and started from it, and the
disk can be booted from when it is bootable. A500 behaviour must not change: without a Gayle, nothing new runs.

Out of scope (stated in the README when done): WHDLoad (needs Kickstart 2.0, impossible on 1.3 even with the real
ROM), PFS3/SFS and other third-party filesystems, DOS\4-DOS\7 (dircache, long names), disks beyond 4 GB (no 64-bit
commands on 1.3), PCMCIA cards, the A4000 IDE port (same chip family, other addresses: a later step).

## What already exists

- `expansion.library` V34 (MakeDosNode, AddDosNode, AddBootNode, eb_MountList) and `romboot` (BootPoint of a
  BootNode), proven with the UAE hard-disk board (`docs/analysis/uae-hd-boot-v34.md`).
- dos: `dos_mountlist` takes the head of eb_MountList as SYS:, `dos_startmounts` starts the handler of each
  partition before the startup-sequence; `bcpl_starthandler` runs a handler from dn_SegList (BCPL, or C with
  dn_GlobalVec = -1) or our ROM filesystem.
- The ROM filesystem (`src/dos/handler.s`, `ofs.s`, `ofswrite.s`) already opens the device, unit and flags of the
  FileSysStartupMsg, takes its geometry from the DosEnvec (partition offset = de_LowCyl), and handles bitmap
  extension blocks. It only knows OFS (DOS\0).
- About 41 KB are free in the production ROM.

## Public sources (implementation track)

- Gayle IDE register map: Linux `drivers/ata/pata_gayle.c`, `arch/m68k/amiga/platform.c`,
  `arch/m68k/include/asm/amigayle.h` (GPL, read for hardware facts only, no code copied): task file at `$DA0000`,
  register n at `$DA0000 + 2 + 4n` (data word at `$DA0000`), device control / alternate status at `$DA101A`, Gayle
  interrupt request at `$DA9000` (bit 7 = IDE; acknowledged by writing `$7C` after reading the status), interrupt
  enable at `$DAA000`.
- ATA/ATAPI-4 or later (public drafts): IDENTIFY DEVICE, READ/WRITE SECTORS (PIO, LBA28 and CHS), status bits,
  software reset through device control, master/slave selection.
- NDK `devices/hardblocks.h` (RigidDiskBlock, PartitionBlock, FileSysHeaderBlock), `devices/trackdisk.h`,
  `devices/scsidisk.h`, `dos/filehandler.h` (DosEnvec), AutoDocs expansion (MakeDosNode, AddBootNode).
- FFS on-disk format: public descriptions (the ADF FAQ "The .ADF (Amiga Disk File) format FAQ", NDK
  `dos/dos.h`/`dosextens.h`): data blocks without header for DOS\1, international hash for DOS\2/DOS\3.
- Gayle presence test, from Amiberry's GPL `src/gayle.cpp` (hardware fact only): a write to `$DE1000` restarts the
  ID sequence, then each read of `$DE1000` gives one bit of the ID in bit 7, most significant first: `$D0` for a
  Gayle, `$D1` for the AA Gayle (A1200). Measured 2026-11-22 under Amiberry: A500 preset reads `$FF` at `$DE1000`
  (fails the test), A600 compatibility reads `$80` first; IDE status `$50` with a hardfile on `ide0_mainboard`.

No Commodore ROM is read. If a behaviour of the real `scsi.device` (2.05/3.1) matters (unit numbering, commands
programs use), an analysis agent observes it black-box and documents it in `docs/analysis/`.

## Steps

### P0. Test harness (no ROM change)

- Amiberry: `ide=a600/a1200`, hardfile on `ide0_mainboard` (`-s hardfile2=...` after `--` in `amiberry-session`),
  68000, ECS, 1 MB chip, no slow RAM: an A600. Check whether `amiberry-session` needs an option for it.
- Test hard disks built with amitools: `rdbtool` (RDB, two partitions), `xdftool` (format OFS and FFS, copy files).
  Script under `tests/mk_hdf.py` or `.sh`, images in the scratchpad or `build/`, never committed.
- Proof that the emulated drive answers: gdb/IPC reads of the task file with our current ROM (status, IDENTIFY by
  hand through gdb writes).

### P1. Gayle IDE driver: `scsi.device` (new resident in `src/exec/`)

- Name `scsi.device`, version 34: the name A600/A1200 software opens. Resident pri below trackdisk, init only when
  a Gayle is present; otherwise the resident returns without adding the device.
- Units 0 (master) and 1 (slave), found with a software reset + IDENTIFY; a unit without a drive fails OpenDevice.
- Commands: CMD_READ, CMD_WRITE, TD_FORMAT (= write), CMD_UPDATE, CMD_CLEAR, TD_MOTOR, TD_CHANGESTATE (0),
  TD_PROTSTATUS (0), TD_CHANGENUM, TD_GETGEOMETRY? (V36: decide), HD_SCSICMD (minimal: READ CAPACITY / INQUIRY
  emulation, or IOERR_NOCMD: decide after checking what HDToolBox-free 1.3 tools need). io_Offset in bytes, 32-bit
  (4 GB limit), requests split in runs of 256 sectors maximum.
- PIO, polled status (BSY/DRQ/ERR) with timeouts first; Gayle interrupts stay masked. LBA28 when IDENTIFY says so,
  CHS otherwise. A request runs in the caller's context (quick) or in a unit task: decide by measuring how long a
  64 KB read blocks the caller.
- Errors mapped to io_Error (IOERR_*, TDERR_*), never a hang: every wait has a timeout.

### P2. RDB scan and mount

- At the driver's init (or a COLDSTART resident after it): read blocks 0-15 of each unit for `RDSK`, check its
  checksum, walk the PartitionBlock list (`PART`), and for each partition not marked "no mount": MakeDosNode with
  the partition's DosEnvec (device `scsi.device`, unit, flags), then AddBootNode (bootable flag and boot priority)
  or AddDosNode.
- dn_SegList: 0 so that our ROM filesystem serves DOS\0-DOS\3. FileSysHeader/LSEG blocks are not loaded (a later
  option for unsupported dostypes; a partition with another dostype is not mounted and is reported on serial).
- Boot: never from the hard disk (user decision, 2026-11-22: an A600's boot partition usually holds a 2.x/3.x
  system). Every partition goes into eb_MountList with priority -128, behind strap's DF0: BootNode (pri 5), so
  SYS: is always the floppy; no ConfigDev/BootPoint is provided.

### P3. FFS in the ROM filesystem

- Read: DOS\1/DOS\3 data blocks are raw 512-byte blocks (no OFS header), file size from the header; DOS\2/DOS\3
  international hash for names. Write: same, plus the FFS allocation rules (data blocks have no back link).
- Partitions of hundreds of MB: bitmap of many blocks with extensions; check the validator and Info on a 100 MB and
  a 1 GB partition (time and memory: the bitmap in memory must not grow with the partition).
- Block sizes other than 512 (de_SizeBlock) stay refused, as now.

### P4. Soft-kick on an A600

- From the A600's own Kickstart (3.1 host as proxy, analysis agent): the IDE drive was used by the host before the
  soft-kick; the driver resets it at init. Check Workbench on DH0: after a warm reset back to the image.
- The A1200 (68020, same Gayle) with the same disk.

### P5. Docs, tests, release

- `docs/ARCHITECTURE.md`, `docs/PLAN.md`, README (EN/FR) "Hard disk on A600/A1200" with the limits above.
- Probe script in `tests/` (mount, dir, copy to and from DH0:, type a file, boot from DH0:), Amiberry sessions with
  screenshots, `prepush-check` (the A500 profiles must be unchanged: no Gayle there).
- Ledger in `.superpowers/sdd/`.

## Risks

- Gayle detection on a machine without it: a wrong positive would hang the boot on a floating bus. Mitigation: Gayle
  ID check, then an ATA signature check with a timeout.
- Some CF cards and drives need a delay after reset or refuse CHS: IDENTIFY decides, timeouts are generous.
- 1 MB chip RAM machines (stock A600) with the soft-kick image take 256 KB: buffers of the driver stay small (no
  track cache for IDE).
