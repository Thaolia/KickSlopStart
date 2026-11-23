# ReloKick 1.4a: running a relocated Kickstart 1.3 from RAM

Analysis-track page. Behaviour and ABI only: no instruction listing, no pseudo-code transcription, no address or
offset inside the Commodore ROM, and none inside the ReloKick binary. Addresses below are standard hardware
addresses, exec structure fields from the public NDK, or RAM addresses chosen by the tool.

## Summary

- ReloKick 1.4a (1994) is a CLI loader derived from an earlier "Kick13" loader (version string "Version 2.0 for ROM
  34.5", 1992). It loads a **raw 256 KB Kickstart 34.5 image from a file** (default `DEVS:ROM1.3`), places it in a
  256 KB-aligned RAM block, relocates it with a **relocation list carried inside the loader**, recomputes the
  Kickstart checksum, arms **ExecBase->ColdCapture** with the copy's reset entry, and reboots through the real ROM.
  On every reset the real ROM honours ColdCapture and jumps into the RAM copy.
- The image shipped on the disk is **not** the stock 34.5 ROM: it is a pre-patched 34.5 image (397 bytes differ, in
  21 runs). The patches are what make the copy reset-proof and keep its RAM out of the free lists; the loader only
  relocates and fixes up addresses.
- The tool targets A1200/A4000 owners (cache disabling, NTSC switch, 2 MB chip RAM). Its own docs claim it runs on
  "any Amiga with enough free memory". Nothing in it re-configures an autoconfig board before the copy is entered
  after a reset (see "Limitations").
- No support for, or mention of, Commodore's ReKick file format.

## How it was observed

- The disk was unpacked with `xdftool`. Files of interest: the loader executable (LOADSEG, two code hunks and a BSS
  hunk; the second code hunk holds only message strings), the 256 KB image `devs/rom1.3`, a short text document, a
  tiny "wait for left mouse button" program (`lmb`), a tiny `KickBack` program, and `s/startup-sequence`
  (`FastMemFirst`, show a text, wait for a click, run the loader). The bootblock is an ordinary DOS bootblock
  (finds the DOS resident and returns); the tool does not live there.
- The loader's code hunks were extracted and disassembled with radare2 (`-a m68k`). Its two embedded tables were
  decoded with a script to obtain statistics only (counts, classes of relocated values).
- The shipped image was compared byte by byte with the stock 34.5 image to find the patched runs. Each run was
  attributed to a module by the RomTag ranges of the image and its effect was read in a disassembly; for a few runs
  the stock bytes at the same place were read to understand what was replaced. Only the **category** of each patch
  is reported here.
- Nothing was run under emulation. Every reset-path statement is derived from the code, not from a probe.

## Input format

- **File**: plain 256 KB (262144 bytes) Kickstart image, no header. Default path `DEVS:ROM1.3`; the CLI template
  (parsed through arp.library) is `NAME,ADR/K` (`Kick13 [[NAME] kickstart file name] [ADR upper word of loading
  addr]`).
- **Read**: exactly 262144 bytes into the allocated block; a short read is an error ("Error reading input file.").
- **Check**: one check only. The version/revision pair of the Kickstart header (public layout, as `romtool info`
  reports it) must be 34/5. Anything else is "Incorrect Kickstart file.". The input checksum is **not** verified,
  and the loader does not read the running ROM at `$FC0000`; it always uses the file.
- Because the relocation list is fixed, the loader is only valid for one exact 34.5 layout. The check on 34/5 is the
  only guard; a different 34.5 build would be mis-relocated silently.
- A stock 34.5 file would pass the check and be relocated, but would lack the reset-proofing and memory patches
  described below (inferred, not tested).

## Memory placement

- **ADR given**: a hexadecimal value (optional leading `$`) that is the **upper word** of the load address. It must
  be non-zero and a multiple of 4, i.e. the address is **256 KB-aligned**. The block is taken with
  `AllocAbs(256 KB, address)` (exec -204); failure is "No space to load ROM into...".
- **ADR omitted (AUTO)**: the loader tries `AllocAbs(256 KB, a)` at 256 KB steps, from the top downwards, in three
  ranges, and keeps the first success:
  1. Zorro II fast RAM space: `$9C0000` down to `$200000`.
  2. "Ranger"/trapdoor slow RAM: `$D80000` down to `$C00000`.
  3. Chip RAM: `$1C0000` down to `$040000`.
  The top-down order places the copy at the top of the highest memory that exists, so the RAM lost below or above it
  is minimised. 32-bit RAM above 16 MB is never considered (1.3 is a 24-bit system). On an A1200/A4000 without
  Zorro II RAM the copy therefore lands at the top of the 2 MB chip RAM.
- The block is never freed on success: the old system is discarded by the reboot.
- **Keeping the block out of the relocated system's free lists** (three cases, by where the copy sits):
  - **Chip RAM** (upper word of address up to `$1C`): the loader writes the copy's base address into the image as
    the **upper bound of the chip RAM sizing/test at coldstart**. Exec then sizes, clears and frees chip RAM only up
    to the copy. WHY: 1.3 coldstart writes test patterns while sizing chip RAM and clears it; without the bound it
    would destroy its own code.
  - **Slow RAM at `$C00000`** (upper word `$C0` or more): same treatment on the **upper bound of the slow-RAM
    sizing**. Slow RAM is sized from `$C00000` up to the copy only.
  - **Zorro II space**: handled by a patch in the image (not by the loader). The single call from expansion.library
    to `AddMemList` (exec -618) for an autoconfig memory board goes through a small wrapper that **clips the board's
    range at the copy's base**: a board wholly below the copy, or wholly above it, is added unchanged; a board that
    contains the copy is added only from its base up to the copy (RAM above the copy on that board is lost, which is
    why AUTO puts the copy at the top). The wrapper's comparison constant is the relocated image base, so it follows
    the copy wherever it is loaded.

## Relocation method and categories of fixups

### Method

- **Not a heuristic scan.** The loader carries a curated list of **3609 locations** (stored compactly as
  byte/word/long deltas between successive locations, ended by a sentinel). For each location the loader adds
  `(upper word of load address - $00FC)` to the **upper word** of the longword there. This only works because the
  load address is at least 64 KB-aligned (the low word of every pointer is kept as is).
- Statistics of the relocated longwords in the shipped image: their upper words are `$00FC` (703), `$00FD` (1061),
  `$00FE` (1192), `$00FF` (650) and `$0100` (3, the "end of ROM" bound `$01000000`, which must move too).
- By context, about two thirds of the locations (2433) are operands of absolute subroutine calls (`jsr` to a
  32-bit address, typical of the compiler-generated parts of the ROM); the rest are pushed/loaded absolute addresses,
  data pointers and table entries. All 120 ROM-pointing fields of the image's RomTags are in the list.
- 37 even-aligned places in the image start with the word `$00FC` but are **not** in the list: they are parts of
  instructions or data that merely look like ROM pointers. A blind scan would have corrupted them; this is the reason
  for a hand-made list.
- A **second list of 19 locations** holds **BCPL pointers** (BPTR = address / 4) into the ROM, found in the DOS/BCPL
  part of the image (global-vector / segment links). Their upper word is `$003F` (= `$FC0000 >> 2`). The loader
  overwrites that upper word with `(upper word of load address) >> 2`. This is only correct when the load address is
  **256 KB-aligned** (so that `base >> 2` has a zero low word): this is the real reason for the 256 KB alignment
  rule.
- Position-independent constructs need no fixup: PC-relative code, and the 1.3 libraries' relative (word-offset)
  function tables.
- After relocation the **standard Kickstart checksum** (the longword in the ROM footer, same algorithm as amitools
  `romtool`: 32-bit sum with end-around carry over the whole 256 KB, complemented) is recomputed with the copy at its
  final address.

### Categories of absolute references that must move (and why)

From the classes of locations in the list (by module and context; no positions given):

- **RomTag (resident) structures**: `rt_MatchTag`, `rt_EndSkip`, `rt_Name`, `rt_IdString`, `rt_Init`. WHY: exec's
  resident scan validates each tag by comparing `rt_MatchTag` with the tag's own address, and follows the pointers.
- **Resident scan bounds**: the start and end (`$01000000`) of the ROM range exec scans for RomTags. WHY: exec must
  scan the copy, not the real ROM.
- **Absolute function/vector tables and InitStruct-style data** (longword function pointers given to MakeLibrary,
  device/resource vector tables, interrupt server and handler code pointers, absolute string pointers such as library
  names and ID strings). WHY: these land in RAM structures (library vectors, IS_CODE, etc.) and are called later.
- **Absolute jumps/loads in code** (`jmp`/`jsr`/`lea`/`move` with a 32-bit operand into the ROM): including the
  copy's reset entry jump and coldstart jumps between phases (coldstart runs without a stack in places, so it uses
  absolute targets).
- **"Is this inside the ROM?" range checks** (comparisons against ROM start/end constants). WHY: such checks decide,
  for instance, whether a pointer is a ROM resident or RAM data; after relocation "ROM" means the copy.
- **BCPL pointers (BPTRs)** into the ROM's DOS segments (second list). WHY: BCPL code multiplies them by 4 at run
  time; they are not plain addresses so the first list cannot handle them.
- **Kickstart checksum** (recomputed, see above).
- **Not relocated on purpose**: references that must keep pointing at the real ROM (the fallback to the real ROM's
  entry, below) and at hardware (`$DFF000`, `$BFE001`, `$C00000`/`$DC0000` slow-RAM bounds, `$F00000` area).

### Patches carried by the shipped image (categories)

The code for the new behaviour is placed over text that the system does not need (module ID/version strings, a
copyright notice of the floating-point firmware text, one DOS/Workbench error message, part of the CLI banner). Some
module ID strings are therefore garbage in the copy.

1. **Reset entry self-check**: the original power-on delay and the `$F00000` diagnostic-cartridge check at the start
   of coldstart are replaced by a checksum test of the copy itself. If the copy's 256 KB checksum is not valid
   (RAM corrupted, copy overwritten), control jumps to the **real** ROM's entry (computed from the size field of the
   real ROM footer, so it works with 256 KB and 512 KB ROMs); otherwise coldstart goes on in the copy.
2. **ColdCapture re-arm**: in the coldstart step that keeps the old ExecBase fields (both the warm and the cold paths
   pass through it), the copy stores its own reset entry into **ExecBase->ColdCapture (offset `$2A`)**. The stock
   step also set COLOR00 to grey there; that write was dropped to make room. WHY: ColdCapture is one-shot (the
   ROM clears it before calling it, which is why it must be re-armed on every boot); re-arming makes every later reset
   come back to the copy. ExecBase->ChkSum is computed later by the normal ExecBase initialisation, so the field is
   covered.
3. **Software reboot without RESET**: the exec path that ends in "RESET, then jump through the reset vector" is
   changed to jump straight to the copy's reset entry (point 1) with no RESET instruction. WHY: after RESET with
   overlay on, the vector would lead into the real ROM; skipping RESET keeps a software reboot inside the copy (and a
   RESET also de-configures autoconfig boards).
4. **Warm-start ExecBase bound widened**: coldstart's sanity check of the old ExecBase's `MaxLocMem` (offset `$3E`)
   accepts up to 2 MB of chip RAM instead of 512 KB. WHY: on 2 MB chip machines (A1200/A4000) a valid old ExecBase
   was otherwise rejected, turning every reset into a cold start.
5. **ExecBase pointer mask in exec's alert path** widened from "below 64 KB" to "anywhere in the 24-bit space". WHY
   (inferred): an ExecBase left by a 2.x/3.x host lies higher in memory.
6. **expansion AddMemList clip** (see "Memory placement").
7. **trackdisk.device**: one `io_Length` comparison that in the stock image reads the longword at a fixed chip-RAM
   location is changed to compare with the constant 32768. Purpose not established (looks like a bug fix).
8. **Boot-time options**, hooked into trackdisk.device initialisation (so they act early in every boot, before the
   insert-disk screen): right mouse button held clears `BEAMCON0` (`$DFF1DC`) to select NTSC; left mouse button held
   flashes COLOR00 from VHPOSR and calls a routine that, through `Supervisor()`, clears cache-enable bits in CACR:
   instruction and data cache enables of the 68020/68030 when ExecBase->AttnFlags says 68020, the 68040 ones when it
   says 68040; on a 68010 it only reads control registers. Nothing happens on a 68000 (AttnFlags tested first).
9. **Cosmetic**: CLI banner / copyright text and the "AmigaDOS" name in one string changed.

## Reset survival sequence

Observable order of effects when the loader runs (derived from the code):

1. Messages "Searching for appropriate space...", "Space found at address $xxxxxxxx.", "Reading kickstart file...",
   "Relocating...", "Patching..." (the chip/slow-RAM sizing bound), "Computing checksum...", "All operations OK,
   kicking up !".
2. `Delay(100)` (2 s). If the left mouse button is held at the end of it, the loader exits with code 0 **without**
   rebooting and without freeing the block.
3. Otherwise: `SuperState()`, interrupts masked (SR = `$2700`). If the right mouse button is held, exec `Debug()` is
   called first (ROM-Wack of the running system).
4. ExecBase->ColdCapture = copy base + entry (the reset entry of the image, i.e. what a 256 KB ROM presents to the
   CPU), then ExecBase->ChkSum (offset `$52`, complement of the word sum of `$22`..`$50`, public NDK rule) is
   recomputed so the running system's ExecBase stays valid.
5. Jump to the **real** ROM's reboot entry: the initial PC published in the real ROM's reset vector at `$F80004`,
   minus one instruction (the RESET that precedes the entry, as in the documented ColdReboot convention). The
   hardware is reset and the real ROM starts.
6. Real ROM coldstart: finds a valid ExecBase at `$4`, calls ColdCapture → the copy's entry.
7. Copy entry: checksum self-test (patch 1). Bad → back to the real ROM entry (ColdCapture was consumed, so the real
   ROM boots normally). Good → normal 1.3 coldstart in the copy.
8. Copy coldstart: warm-start test of the old ExecBase (version, checksums, memory bounds). The host's ExecBase (for
   example a 3.x one) fails the version test, so the first entry is a cold start; later resets of the copy are warm
   starts. Both paths re-arm ColdCapture (patch 2). Chip/slow RAM sizing stops at the copy when it lives there.
9. expansion.library configures the boards; a board containing the copy is added only up to it (patch 6).
10. Any later reset (keyboard reset, software reboot) repeats from step 6 (or goes straight to step 7 for a
    software reboot, patch 3).

**Going back to the real ROM**: the `KickBack` program clears ExecBase->ColdCapture (without fixing ChkSum, so the
ExecBase also becomes invalid) and jumps to `$FC0000` in the real ROM. A power cycle also works (RAM content lost or
ExecBase invalid).

## CPU/chipset notes

- **68000**: the loader and the patched image are 68000-safe; all control-register code is behind AttnFlags tests.
- **68010+**: the cache-disable option relies on ExecBase->AttnFlags. 1.3 exec itself only knows 68010/68020/68881;
  whether the 68030/68040 bits are set when the copy runs is **not established** (see "Uncertain points"). The
  loader does not flush or disable caches itself before the reboot; the hardware reset does.
- **2 MB chip (A1200/A4000)**: supported through patch 4 and the chip-RAM placement case.
- **NTSC/PAL**: the NTSC option writes BEAMCON0 (ECS/AGA register); the docs say a reset returns to PAL.
- **Zorro II**: no autoconfig ordering logic in the tool; it relies on 1.3 expansion.library and the AddMemList clip.

## Limitations

- Exactly one ROM: Kickstart 34.5 with the layout of the relocation list.
- Load address 256 KB-aligned (BPTR fixups), below 16 MB; AUTO only tries the three ranges listed.
- RAM lost: the 256 KB of the copy, plus on a Zorro II board any RAM above it, plus on chip/slow placement all
  RAM above the copy.
- **Autoconfig RAM across a hardware reset (derived, not tested)**: ColdCapture points straight into the copy. A
  hardware reset (the loader's own reboot, keyboard reset) de-configures Zorro II autoconfig boards, and the real ROM
  calls ColdCapture before expansion.library has re-configured anything. A copy in autoconfig Zorro II RAM would then
  be unreachable at the moment the CPU jumps to it. The tool has no stub in chip RAM to re-configure the board first.
  It is expected to work only where the RAM keeps its address across reset: chip RAM, `$C00000` slow RAM, or
  fixed-decode memory in `$200000`-`$9FFFFF` (for example an A1200 PCMCIA SRAM card). This explains why, in
  practice, the A1200/A4000 copy sits in chip RAM.
- No ReKick support; no 2.x/3.x images.

## Requirements for a Kickstart that wants to run from `$200000`

Checklist for an implementer (behaviour, not code):

- [ ] **Position independence or a relocation list**: every absolute pointer into the image (RomTags and their
      fields, resident scan bounds including the end bound, function/vector tables, absolute jumps and loads,
      library/ID string pointers, ROM-range comparisons) must follow the load address. A list produced by the linker
      (exact) is preferable to a scan of `$00F8xxxx`/`$00FCxxxx`-looking words (false positives exist).
- [ ] **BPTRs into the image** (BCPL code/data) need their own fixup (address / 4); require 256 KB alignment or
      relocate them as full values.
- [ ] **Checksum** recomputed at the final address; a self-check at the entry that falls back to the real ROM entry
      when it fails.
- [ ] **Reset-proof entry**: re-arm ExecBase->ColdCapture with the copy's entry on every boot (it is one-shot), and
      keep ExecBase->ChkSum valid.
- [ ] **Software reboot path** that does not execute RESET (or that accepts landing in the real ROM, which then
      re-enters through ColdCapture).
- [ ] **Memory exclusion**: the copy's RAM must never be sized, tested, cleared or freed: bound chip/slow-RAM sizing
      when the copy lives there, and clip any memory added by expansion (or by a host-provided memory list) at the
      copy's range.
- [ ] **Warm-start ExecBase checks** must accept the memory layout of the machine (e.g. MaxLocMem up to 2 MB) and
      an ExecBase located anywhere in 24-bit space, or every reset becomes a cold start.
- [ ] **Autoconfig RAM**: if the copy lives in Zorro II autoconfig RAM (e.g. `$200000`), the code reached by
      ColdCapture must first be in memory that survives reset (chip RAM) and re-configure the board at the same
      address before jumping into the copy. ReloKick does not do this.
- [ ] Hardware addresses (custom chips, CIAs, `$C00000` slow RAM, `$F00000` diagnostic area, the real ROM footer)
      must **not** be relocated.

## Uncertain points

- The autoconfig-across-reset failure is derived from the code and general hardware behaviour; no run confirmed it.
  A probe (copy forced at `$200000` on an A500 with an autoconfig Zorro II board, then a keyboard reset) would
  settle it.
- The one-shot nature of ColdCapture is inferred from the patch that re-arms it on every boot; not observed here.
- Whether 1.3 exec sets the 68030/68040 AttnFlags bits (needed by the 68040 branch of the cache option) is not
  established; on a 68040 the 68020/68030 branch would clear bits that are not the 68040 cache enables.
- Purpose of the trackdisk `io_Length` constant fix (patch 7) and of the alert-path ExecBase mask (patch 5).
- `KickBack` jumps to `$FC0000`; on a machine with a 512 KB ROM that address is not an entry point, so it probably
  only works with a 256 KB ROM.
- Exiting with the left button held leaves the 256 KB block allocated; whether this is intended is unknown.
