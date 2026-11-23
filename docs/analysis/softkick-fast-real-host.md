# Soft-kick disk in Zorro II fast RAM on real Commodore hosts

Black-box test of our soft-kick disk (`build/KickSlopStart.adf`, md5 `53faa70c7046d3ae3bfcc001aca60ca6`, image
reporting `v0.2.71-2-9110c8e4-dirty` on its boot screen) booted from real Commodore Kickstarts (1.3, 2.05, 3.0,
3.1) used as the host ROM. Observed on 2026-11-23 under Amiberry v8.4.2 (headless analysis sessions,
`amiberry-session start --analysis`), with IPC memory reads, an IPC fetch watch and IPC screenshots only. The host
ROMs were not disassembled or read; this page records only behaviour and addresses in our own image, relay and chip
RAM, plus standard hardware addresses. The statement "from the host ROM" below only means the instruction that
reached our relay was executing in the ROM address space; no ROM address is given.

## Method

1. Boot the host ROM with a copy of the soft-kick disk in DF0:, wait for our coldstart serial line
   (`EXEC coldstart: overlay off, stack live (RAM)`), then about 25 s more.
2. With the emulation paused (IPC `PAUSE`, `READ_MEM`, `GET_CPU_REGS`, `RESUME`): PC, ExecBase (`$4`),
   ExecBase->ColdCapture (ExecBase+$2A), the bootblock record at `$C00` (magic `$4B535352`, image base at `$C04`,
   board count at `$C08`, 20-byte entries from `$C10`), and exec's MemList (ExecBase+$142).
3. Reset test: a logging instruction-fetch watch on `$D00` (the relay), then IPC `RESET` with no argument, which
   is Amiberry's keyboard reset (RAM kept, CPU reset through the host ROM). After 55 s: watch events, then the same
   reads as step 2.
4. Insert a copy of the Workbench 1.3.3 boot disk in DF0: (IPC `INSERTFLOPPY`), wait 90 s, IPC screenshot. This
   was done after the reset, so the Workbench run also exercises the image re-entered through the relay.

## Results

| # | Host | Machine (Amiberry) | Memory | Image base | Boards at `$C00` | Relay fetched after reset | Image running after reset | Workbench 1.3.3 | Free memory (WB title) |
|---|------|--------------------|--------|-----------:|-----------------:|---------------------------|---------------------------|-----------------|-----------------------:|
| 1 | KS 1.3 | A500, cycle-exact | 512K chip, 2 MB fast | `$3C0000` | 1 | yes, from the host ROM | yes | yes | 2174840 |
| 2 | KS 1.3 | A500, cycle-exact | 512K chip, 512K slow, 2 MB fast | `$3C0000` | 1 | yes, from the host ROM | yes | yes | 2441128 |
| 3 | KS 2.05 | A600 (ECS Agnus) | 1 MB chip, 2 MB fast | `$3C0000` | 1 | yes, from the host ROM | yes | yes | 2698904 |
| 4 | KS 3.0 | A1200, 68020, AGA | 2 MB chip, 4 MB fast | `$5C0000` | 1 | yes, from the host ROM | yes | yes | 5844632 |
| 5 | KS 3.1 | A1200, 68030, AGA | 2 MB chip, 4 MB fast | `$5C0000` | 1 | yes, from the host ROM | yes | yes | 5844632 |
| 6 | KS 3.1 | A1200, 68040 + FPU, AGA | 2 MB chip, 4 MB fast | `$5C0000` | 1 | yes (caller not identifiable, see below) | yes | yes | 5844632 |

All six configurations passed every step. `cpu_24bit_addressing=false` was not needed on the 68040.

### Details common to all runs

- Coldstart serial line reached within the 300 s budget in every run (three sessions in parallel).
- PC sampled after boot was inside our image (between the image base and base+`$40000`), SR `$2000` (`$2700` once,
  on the 68040 after reset, sampled inside a masked section of our code).
- ColdCapture = `$D00` before and after the reset.
- Record at `$C00`: magic `$4B535352`, base = the top 256 KB of the fast board (`$3C0000` for a 2 MB board at
  `$200000`, `$5C0000` for a 4 MB board), one Zorro II board. Its entry: cd_Rom with er_Type `$E6` (2 MB) or `$E7`
  (4 MB), product `$51`, manufacturer `$07DB`, serial 1; slot `$20` (board at `$200000`). cd_Flags as left by the
  host: `$0002` under KS 1.3, `$000A` under KS 2.05/3.0/3.1.
- Fast-RAM MemHeader: attributes `$0005` (MEMF_PUBLIC|MEMF_FAST), lower `$200020`, upper = the image base. The image
  is outside the free pool in every run, before and after the reset.
- Chip MemHeader: lower `$3500` (ExecBase in chip RAM), or `$1000` when slow RAM holds ExecBase (run 2: ExecBase
  `$C40276`, slow-RAM header `$C404D0`-`$C7F000`, attributes `$0005`). Upper = end of chip RAM.
- MemList values were identical before and after the reset in every run, and the free-byte counts of the fast
  headers also matched (the reset gave the same layout as the cold boot).
- After the reset our boot screen (KSS cat, "Insert disk in DF0:", version) was displayed again, and inserting the
  Workbench disk booted it to the desktop with the RAM DISK and Workbench1.3 icons.

### Reset path

- Exactly one instruction fetch at `$D00` was logged per reset, with the relay's first word in place, and the image
  then ran from the same base. The host therefore called ColdCapture early enough for the relay to re-configure the
  recorded board and re-enter the image on every host tested, 1.3 through 3.1.
- Runs 1-5: the fetching instruction was executing in the host ROM address space (the host called ColdCapture).
- Run 6 (68040): the logged `instruction_pc` equals `$D00` itself, so this emulated core does not tell who
  jumped there. The rest of the evidence (fetch present, image running again at `$5C0000`, MemList unchanged,
  Workbench reached afterwards) shows the reset path works, but the caller was not observed directly.
- The coldstart serial line was not logged a second time after the reset (known Amiberry pitfall: boot lines after
  an emulated reset can be missing from `serial.log`); the fetch watch and the memory state are the proof.

### Free memory

The Workbench title figures are consistent with the image being excluded from the fast pool: for example run 1,
2 MB fast board minus the 256 KB image and the 32-byte header (`$1BFFE0` bytes) plus the free chip RAM after boot.
The three A1200 configurations report the same figure regardless of CPU.

## Several Zorro II boards

Same disk (md5 `53faa70c7046d3ae3bfcc001aca60ca6`) and same method as above, observed on 2026-11-23 under Amiberry
v8.4.2, two sessions at a time. Extra boards come from Amiberry's `fastmem2_size`/`fastmem3_size` (Zorro II RAM
boards) and `a2065=slirp` (an Ethernet I/O board without RAM). Differences from the method above: the Workbench
disk was inserted after the reset and the screenshot taken 180 s later; besides the record at `$C00` and exec's
MemList, the ConfigDev list of our image's expansion.library (V34, ExpansionBase+`$3C`) was read, and from config 3
on, Amiberry's own memory map (IPC `MONITOR memory-map`), which shows which boards are actually mapped.

### Configurations

| # | Host | Amiberry options (after `--analysis`) | Boards in the emulator |
|---|------|----------------------------------------|------------------------|
| 1 | KS 1.3, A500 | `--chip 512 --slow 0 --fast 2 -- -s fastmem2_size=2` | 2 MB RAM, 2 MB RAM |
| 2 | KS 1.3, A500 | `--chip 512 --slow 0 --fast 1 -- -s fastmem2_size=4 -s fastmem3_size=1` | 4 MB, 1 MB, 1 MB RAM |
| 3 | KS 1.3, A500 | `--chip 512 --slow 0 --fast 2 -- -s a2065=slirp` | 2 MB RAM, A2065 Ethernet (I/O, 64 KB) |
| 4 | KS 1.3, A500 | `--chip 512 --slow 0 --fast 8 -- -s fastmem2_size=2` | 8 MB RAM, 2 MB RAM (cannot fit) |
| 5 | KS 2.05, A600 | `--chip 1024 --slow 0 --fast 2 -- -s fastmem2_size=2 -s chipset=ecs_agnus -s chipset_compatible=A600` | 2 MB RAM, 2 MB RAM |
| 6 | KS 3.1, A1200 68030 | `--chip 2048 --slow 0 --fast 1 -- -s fastmem2_size=4 -s fastmem3_size=1 -s cpu_model=68030 -s chipset=aga -s chipset_compatible=A1200` | 4 MB, 1 MB, 1 MB RAM |

### Results

| # | Boards at `$C00` (count; slot / cd_Flags in chain order) | Image base | Fast MemHeaders (lower-upper, attrs `$0005`) | Relay fetched after reset | Image running after reset | Workbench 1.3.3 | Free memory (WB title) |
|---|---|---:|---|---|---|---|---:|
| 1 | 2; `$0020`/`$0002`, `$0040`/`$0002` | `$5C0000` | `$200020`-`$400000`, `$400020`-`$5C0000` | yes, from the host ROM | yes | yes | 4271888 |
| 2 | 3; `$0020`/`$0002`, `$0060`/`$0002`, `$0070`/`$0002` | `$7C0000` | `$200020`-`$600000`, `$600020`-`$700000`, `$700020`-`$7C0000` | yes, from the host ROM | yes | yes | 6368936 |
| 3 | 2; `$0020`/`$0002`, `$00E9`/`$0002` | `$3C0000` | `$200020`-`$3C0000` | yes, from the host ROM | yes | yes | 2174768 |
| 4 | 2; `$0020`/`$0002`, `$FF00`/`$0001` (shut up) | `$9C0000` | `$200020`-`$9C0000` | yes, from the host ROM | yes | yes | 8466224 |
| 5 | 2; `$0020`/`$000A`, `$0040`/`$000A` | `$5C0000` | `$200020`-`$400000`, `$400020`-`$5C0000` | yes, from the host ROM | yes | yes | 4795952 |
| 6 | 3; `$0020`/`$000A`, `$0060`/`$000A`, `$0070`/`$000A` | `$7C0000` | `$200020`-`$600000`, `$600020`-`$700000`, `$700020`-`$7C0000` | yes, from the host ROM | yes | yes | 7941576 |

All six configurations passed every step; there is no failure to analyse.

### Details

- **Record at `$C00`.** Magic `$4B535352` in every run; the count equals the number of boards the host configured
  or shut up, entries in the host's chain order. Board ids in cd_Rom: RAM boards er_Type `$E5` (1 MB), `$E6`
  (2 MB), `$E7` (4 MB), `$E0` (8 MB), product `$51`, manufacturer `$07DB`, serial 1; the A2065 er_Type `$C1` (no
  "link into memory list" bit), product `$70`, manufacturer `$0202`. cd_Flags as left by the host: `$0002` for a
  configured board under KS 1.3, `$000A` under KS 2.05/3.1, `$0001` for the board KS 1.3 shut up.
- **Shut-up board (config 4).** The 8 MB board fills the Zorro II space (`$200000`-`$9FFFFF`), so the host shut the
  2 MB board up; its entry has bit 0 of cd_Flags set and slot `$FF00` (no address assigned). Before and after the
  reset, Amiberry's memory map showed only the 8 MB board mapped and no autoconfig area pending at `$E80000`: the
  2 MB board was shut up again and stayed off the bus.
- **Image base.** The top 256 KB of the last RAM board in chain order (`$5C0000` = top of the board at `$400000`;
  `$7C0000` = top of the 1 MB board at `$700000`; `$9C0000` = top of the 8 MB board). The I/O board of config 3 is
  never chosen.
- **MemList.** One MemHeader per configured RAM board, attributes `$0005` (MEMF_PUBLIC|MEMF_FAST), priority 0,
  lower = board base + `$20`, upper = board end, except the board holding the image, whose upper bound is the image
  base. The image's 256 KB is therefore outside every free pool. No MemHeader for the A2065 (I/O) nor for the
  shut-up board. Chip MemHeader `$3500` to the end of chip RAM (`$80000`, `$100000`, `$200000`), attributes `$0003`,
  priority -10.
- **Image's expansion.library.** Its ConfigDev list has one node per entry at `$C00`, in the same order: cd_BoardAddr
  = slot << 16, cd_BoardSize = the board size (`$10000` for the A2065 at `$E90000`), cd_SlotAddr = the slot, cd_Flags
  `$02` for configured boards; for the shut-up board cd_Flags `$01` and cd_BoardAddr/BoardSize/SlotAddr 0. The first
  ConfigDev sits in chip RAM, the following ones in the first fast board, just after its MemHeader.
- **Before vs after reset.** The record, the ConfigDev list, the MemList (bounds and free-byte counts) and the
  Amiberry memory map were identical before and after the reset in all six runs, and PC was inside the image
  (base to base+`$40000`, SR `$2000`) both times. ColdCapture = `$D00` before and after.
- **Reset path.** Exactly one logged instruction fetch at `$D00` per reset, the fetching instruction executing in
  the host ROM address space, on all three hosts. On the 68030 (config 6) the watch logged a 4-byte fetch, on the
  68000 a 2-byte one (fetch width of the emulated core).
- **Free memory cross-check.** The Workbench figures match the single-board runs above to the byte once the extra
  boards are accounted for: each extra RAM board adds its size minus 104 bytes (a 32-byte MemHeader and a 72-byte
  allocation for its ConfigDev), and an I/O or shut-up board costs 72 bytes (its ConfigDev). Config 1 = run 1 +
  2097048; config 5 = run 3 + 2097048; config 6 = run 5 + 2 MB - 208; config 2 = run 1 + 4 MB - 208; config 3 =
  run 1 - 72; config 4 = run 1 + 6 MB - 72. No board RAM is lost or counted twice, and the image stays excluded.
- **Amiberry quirk (A1200 profile).** Config 6 shows an "Autoconfig Z2" region at `$E80000` in Amiberry's memory map
  before and after the reset. A control run of the same configuration with no disk (host alone, at its insert-disk
  screen) shows the same region, so it comes from the emulated machine or the host, not from the soft-kick disk.
  The A500 and A600 profiles do not show it. Not investigated further.
- Configs 1 and 2 were read before the memory-map check was added; for them the evidence that every board is back
  is the ConfigDev list, the MemList and the Workbench free-memory figure.

## Zorro III and 68060

Same disk (md5 `53faa70c7046d3ae3bfcc001aca60ca6`) and same method, observed on 2026-11-23 under Amiberry v8.4.2,
two sessions at a time, host ROMs KS 3.1 (40.68) and KS 3.0 (39.106), both the A1200 images (no A3000/A4000
Kickstart was available). All runs: `--chip 2048 --slow 0`, `cpu_24bit_addressing=false`, `chipset=aga`; Amiberry
reports `MMU=0` (no MMU emulated) in every run. Zorro III RAM comes from `z3mem_size=16` (one 16 MB board, er_Type
`$A0`, product `$53`, manufacturer `$07DB`, which the host places at `$40000000` when it configures it). Additions
to the method: the image's reset entry was watched instead of `$D00` when the image sat in chip RAM; in configs 5
and 6 the watch was a **stopping** one (last argument 0), so the machine could be inspected at the moment the host
handed over to ColdCapture (then IPC `DEBUG_CONTINUE` and `DEBUG_DEACTIVATE` to go on); the configuration spaces
were read byte-wise with IPC `READ_MEM` at `$E80000` (Zorro II style) and `$FF000000` (Zorro III style); the host's
own board list was read in control sessions without a disk (below).

### Configurations

| # | Host | CPU | Profile (`chipset_compatible`) | Fast memory | Boards in the emulator |
|---|------|-----|--------------------------------|-------------|------------------------|
| 1 | KS 3.1 | 68060 + FPU | A1200 | `--fast 4` | 4 MB Zorro II RAM |
| 2 | KS 3.0 | 68060 + FPU | A1200 | `--fast 4` | 4 MB Zorro II RAM |
| 3 | KS 3.1 | 68040 + FPU | A4000 | `--fast 2`, `z3mem_size=16` | 2 MB Zorro II RAM, 16 MB Zorro III RAM |
| 4 | KS 3.1 | 68040 + FPU | A4000 | `--fast 0`, `z3mem_size=16` | 16 MB Zorro III RAM |
| 5 | KS 3.1 | 68060 + FPU | A4000 | `--fast 2`, `z3mem_size=16` | 2 MB Zorro II RAM, 16 MB Zorro III RAM |
| 6 | KS 3.1 | 68040 + FPU | A1200 | `--fast 2`, `z3mem_size=16` | 2 MB Zorro II RAM, 16 MB Zorro III RAM |

The A1200 Kickstart ran on the A4000 profile without complaint (configs 3-5). Config 6 was added because on the A4000
profile the host never configured the Zorro III board (next sections), so configs 3-5 did not exercise the refusal;
config 5 was run anyway for the 68060.

### Results

| # | Host configured | Image base | ColdCapture | `$C00` record | Image MemList | Reset entry fetched | Running after reset | Workbench 1.3.3 (after reset), free |
|---|---|---:|---|---|---|---|---|---:|
| 1 | Z2 4 MB | `$5C0000` | `$D00` (relay) | magic, 1 entry: er_Type `$E7`, slot `$20`, flags `$0A` | fast `$200020`-`$5C0000`, chip `$3500`-`$200000` | `$D00`, once | yes, same base | yes, 5844632 |
| 2 | Z2 4 MB | `$5C0000` | `$D00` (relay) | same as 1 | same as 1 | `$D00`, once | yes, same base | yes, 5844632 |
| 3 | Z2 2 MB only (Z3 left unconfigured) | `$3C0000` | `$D00` (relay) | magic, 1 entry: er_Type `$E6`, slot `$20`, flags `$0A` | fast `$200020`-`$3C0000`, chip `$3500`-`$200000` | `$D00`, once | yes, same base | yes, 3747728 |
| 4 | nothing (Z3 left unconfigured) | `$1B0000` (chip) | `$1B00D2` (image's reset entry) | none (stale bytes, no magic) | chip `$3500`-`$200000`, image range not free | `$1B00D2`, once | yes, same base | yes, 1667576 |
| 5 | Z2 2 MB only (Z3 left unconfigured) | `$3C0000` | `$D00` (relay) | same as 3 | same as 3 | `$D00` (stopped there) | yes, same base | yes, 3747728 |
| 6 | Z2 2 MB, then Z3 16 MB at `$40000000` | `$1C0000` (chip) | `$1C00D2` (image's reset entry) | none (stale bytes, no magic) | before reset: chip `$3500`-`$200000` only; after reset: fast `$200020`-`$400000` added | `$1C00D2` (stopped there) | yes, same base | yes, 3747480 |

MemList attributes: `$0005` for fast headers, `$0003` (priority -10) for chip. No configuration crashed or failed to
start the image; the coldstart serial line came within the 300 s budget in all six. Every Workbench screenshot shows
the desktop with the RAM DISK and Workbench1.3 icons.

### Details

- **68060 (configs 1, 2, 5).** Same placement, record, MemList, relay behaviour and free memory as the 68030/68040
  runs of the first table. The image's exec reports AttnFlags `$0003` on the 68060 (it classifies the CPU as a
  68020 and sees no FPU) and `$0013` on the 68040. The fetch watch on `$D00` logged `instruction_pc` = `$D00`
  itself on the 68060 as on the 68040, so the caller is again not identifiable from the watch. PC sampled after boot
  and after reset was inside the image (SR `$2000`, once `$2700` inside a masked section).
- **Why config 3 kept the fast placement.** The A1200 Kickstarts on the A4000 profile configure only the Zorro II
  board: Amiberry's log shows "Card 2: Z2 0x00200000 2048K RAM" and no configured Zorro III card, and the Zorro III
  board keeps answering at `$FF000000` (er_Type `$A0` there) for the whole run, before and after the reset, while
  `$E80000` reads 0. The host's list therefore holds the Zorro II board only, the record has one Zorro II entry, and
  the fast placement is consistent with the design. The 16 MB Zorro III RAM is used by neither the host nor the image.
- **Config 4 (no Zorro II RAM).** No usable fast RAM, so the chip fallback: image at `$1B0000`-`$1F0000`,
  ColdCapture = image base + `$D2`. The chip free list has a hole exactly over the image (last chunk below it ends at
  `$1B0000`, next chunk at `$1F0000`, size `$10000`): the top 64 KB stays free, the image is excluded. The reset watch
  logged one fetch at the image's reset entry and the image ran again from `$1B0000`.
- **Config 6, the refusal path.** On the A1200 profile the Zorro III board answers at `$E80000` (Amiberry maps an area
  named "Z3Fast" there while it is pending), so the A1200 Kickstart configures it: log "Card 3: Z2 0x00200000" then
  "Card 4: Z3 0x40000000 16M". The bootblock refused the fast placement (no record at `$C00`; ColdCapture points into
  a chip image at `$1C0000`), as the rule "any non-Zorro II board in the list" requires. Before the reset the image's
  MemList has the chip header only: the 2 MB Zorro II board, already configured by the host, no longer answers at
  `$E80000`, so the image's V34 expansion does not find it (2 MB of Zorro II RAM unused until the first reset).
  **Fixed** in the later disk (md5 `eb26a47f90eb5d3f5fd753c939faead5`): the board is now recorded for the chip
  placement too and is in the image's MemList before any reset; see "Board record in every placement (re-test)",
  config A. The Zorro III board left pending after a reset (next item) is unchanged.
- **Config 6 after the reset.** Stopped at the image's reset entry: the Zorro II board was back in configuration state
  at `$E80000` (er_Type `$E6`, Amiberry area "Z2Fast"), `$FF000000` read 0. 40 s later the image's expansion had
  configured that board at `$200000` (log "Card 3: Z2 0x00200000" again; fast MemHeader `$200020`-`$400000` added),
  and the Zorro III board then answered at `$E80000` (er_Type `$A0`, area "Z3Fast"), left pending: neither configured
  nor shut up, so any board behind it in the chain would stay invisible. The Workbench still booted (3747480 free:
  chip minus the 256 KB image, plus the whole Zorro II board).
- **Config 5 at the relay entry.** Stopped at the first fetch of `$D00`: the Zorro II board answered at `$E80000`
  (er_Type `$E6`) and `$FF000000` read 0 (the Zorro III board is behind it in the chain). After the relay had
  configured the Zorro II board, the Zorro III board answered at `$FF000000` (er_Type `$A0`) and `$E80000` read 0.
- **Free memory.** Configs 3 and 5 match to the byte (CPU does not matter). The Zorro III RAM never appears in any
  free figure.

### Host board list (control sessions, no disk)

Read from RAM with IPC `READ_MEM` only: the library in exec's LibList whose list at offset `$3C` (eb_BoardList in the
public expansionbase layout) holds ConfigDev-shaped nodes, then each ConfigDev's cd_Flags (+14), cd_Rom er_Type
(+16), product (+17), manufacturer (+20), cd_BoardAddr (+32), cd_BoardSize (+36), cd_SlotAddr/cd_SlotSize (+40/+42).
Library names were not read.

| Host, profile, boards | Host's list, in order |
|---|---|
| KS 3.1, A4000, Z2 2 MB + Z3 16 MB | 1. er_Type `$E6`, `$200000`, size `$200000`, slot `$20`/`$20`, cd_Flags `$0A` (nothing else) |
| KS 3.0, A4000, same boards | the same single Zorro II entry |
| KS 3.1, A1200, Z2 2 MB + Z3 16 MB | 1. er_Type `$E6`, `$200000`, slot `$20`/`$20`, cd_Flags `$0A`; 2. er_Type `$A0`, product `$53`, `$40000000`, size `$1000000`, slot `$4000`/`$100`, cd_Flags `$0A` |
| KS 3.1, A1200, Z3 16 MB only | 1. er_Type `$A0`, `$40000000`, size `$1000000`, cd_Flags `$0A` |

- Order: the Zorro II board first, then the Zorro III board, which is also Amiberry's configuration-chain order (its
  log numbers the cards the same way).
- With the Zorro III board configured, the KS 3.1 host's ExecBase was in Zorro III RAM (`$40000810`); with only the
  Zorro II board it was in Zorro II RAM (`$200810` under 3.1, `$200804` under 3.0).
- **Where a Zorro III board answers at configuration time, under Amiberry:** on the A1200 profile at `$E80000` (Zorro
  II space, and the A1200 Kickstart configures it from there); on the A4000 profile at `$FF000000` only (and the A1200
  Kickstart never configures it). After a reset the de-configured board answers again at the same place, only once
  every board ahead of it in the chain is configured or shut up (config 6: Zorro II board at `$E80000` first, the
  Zorro III board at `$E80000` after it). Real hardware was not tested; on a real A3000/A4000 with its own Kickstart
  the board would be expected at `$FF000000`, which these runs could not check.

## Board record in every placement (re-test)

Rebuilt disk, `build/KickSlopStart.adf` md5 `eb26a47f90eb5d3f5fd753c939faead5`. Design change under test: the
bootblock now records the host's Zorro II boards at `$C00` for the fast **and** the chip placement (non-Zorro II
boards skipped; fast still refused when one had to be skipped); the image's expansion.library rebuilds the recorded
boards on its first boot and, when the image is not in Zorro II space, then clears the magic at `$C00` so that after
a reset its own ConfigChain finds the boards. Observed on 2026-11-23 under Amiberry v8.4.2, two sessions at most,
same method as above: IPC reads (PAUSE/READ_MEM/GET_CPU_REGS/RESUME) about 25 s after the coldstart serial line, a
logging instruction-fetch watch on the reset entry (the image's entry for a chip image, `$D00` for the fast one),
IPC `RESET` (keyboard reset), the same reads about 60 s later, then a copy of the Workbench 1.3.3 disk inserted and
an IPC screenshot 180 s later. Board lists read through public structures only (ExpansionBase found by name in
exec's LibList, eb_BoardList at +`$3C`); Amiberry's memory map with IPC `MONITOR memory-map`.

### Configurations

| # | Host | Amiberry options (after `--analysis`) | Boards in the emulator |
|---|------|----------------------------------------|------------------------|
| A | KS 3.1, A1200 profile, 68040 + FPU | `--chip 2048 --slow 0 --fast 2 -- -s cpu_model=68040 -s fpu_model=68040 -s cpu_24bit_addressing=false -s z3mem_size=16 -s chipset=aga -s chipset_compatible=A1200` (former Zorro III config 6) | 2 MB Zorro II RAM, 16 MB Zorro III RAM |
| B | KS 1.3, A500 | `--chip 1024 --slow 0 --fast 0 -- -s a2065=slirp` | A2065 Ethernet (I/O, 64 KB), no fast RAM |
| C | KS 3.1, A1200 profile, 68030 | `--chip 2048 --slow 0 --fast 4 -- -s cpu_model=68030 -s chipset=aga -s chipset_compatible=A1200` | 4 MB Zorro II RAM |

### Results

| # | Image base | ColdCapture | `$C00` magic (first boot) | Record entries | Image MemList | Image board list | Reset entry fetched | Same state after reset | Workbench 1.3.3, free |
|---|---:|---|---|---|---|---|---|---|---:|
| A | `$1C0000` (chip) | `$1C00D2` (image's reset entry) | 0 (consumed) | 1: er_Type `$E6`, slot `$20`, cd_Flags `$0A` | fast `$200020`-`$400000`, chip `$3500`-`$200000` | Z2 RAM at `$200000`, size `$200000`, flags `$02` | `$1C00D2`, once | yes | yes, 3747480 |
| B | `$B0000` (chip) | `$B00D2` (image's reset entry) | 0 (consumed) | 1: er_Type `$C1`, product `$70`, manufacturer `$0202`, slot `$E9`, cd_Flags `$02` | chip `$3500`-`$100000` only | A2065 at `$E90000`, size `$10000`, slot `$E9`/`$01`, flags `$02` | `$B00D2`, once, from the host ROM | yes | yes, 618928 |
| C | `$5C0000` (fast) | `$D00` (relay) | `$4B535352` (kept) | 1: er_Type `$E7`, slot `$20`, cd_Flags `$0A` | fast `$200020`-`$5C0000`, chip `$3500`-`$200000` | Z2 RAM at `$200000`, size `$400000`, flags `$02` | `$D00`, once, from the host ROM | yes | yes, 5844632 |

All MemHeaders: attributes `$0005` (fast) / `$0003` (chip). PC sampled inside the image (SR `$2000`) before and after
each reset. Every Workbench screenshot shows the desktop with the RAM DISK and Workbench1.3 icons; all three
configurations reached their coldstart serial line within the 300 s budget.

### Details

- **Config A (former config 6): fixed.** With the image in chip RAM, the Zorro II board the host had configured is
  now in the image's MemList **before** any reset (fast header `$200020`-`$400000`, the whole board free apart from
  the image's own allocations) and in its expansion board list; the record's entry is still in RAM but the magic
  at `$C00` reads 0, as designed. The Zorro III board is not in the image's list (skipped by the bootblock). The chip
  free list ends exactly at `$1C0000` (last chunk `$12E08`+`$1AD1F8`), so the image is outside the chip pool.
  After the reset: one fetch of `$1C00D2` (the 68040 core logs the entry itself as `instruction_pc`, so the caller is
  again not identifiable), the image ran again from `$1C0000`, and Amiberry's log shows "Card 3: Z2 0x00200000"
  configured once more (by the image's own expansion, the record being gone); MemList, free-byte counts and the board
  list were identical to the first boot. The Workbench free figure (3747480) is the one the old disk reached only
  after a reset; it is now reached on the first boot path as well.
- **Config A, the Zorro III board after the reset: unchanged.** Before the reset Amiberry's map shows the host's
  "Zorro III Fast RAM" at `$40000000` and `$E80000` reads `$FF` (nothing pending). After the reset the Zorro III
  board answers at `$E80000` (er_Type nibbles read `$A0`, Amiberry area "Z3Fast") and stays pending: neither
  configured nor shut up by the image, as in the old config 6. Amiberry's memory map still lists "Zorro III Fast
  RAM" at `$40000000` after the reset (a stale mapping of the emulator or a real one, not determined); the image
  never uses it.
- **Config B (1.3 host, I/O board, chip placement).** The A2065 the host configured at `$E90000` is recorded (one
  entry) and present in the image's board list before the reset, with the magic consumed. The chip free list has a
  hole exactly over the image: the chunk below ends at `$B0000`, the next one is `$F0000`+`$10000` (the top 64 KB of
  chip RAM stays free). After the reset (fetch of `$B00D2` from the host ROM address space) Amiberry's log shows
  "Card 1: Z2 0x00e90000 64K IO 7990 Ethernet" configured again by the image, Amiberry's map has the "7990 Ethernet"
  area at `$E90000`, `$E80000` reads 0, and the image's board list is identical (one ConfigDev at the same place with
  the same fields).
- **Config C (fast path regression).** Unchanged behaviour: record kept with its magic (the image is in Zorro II
  space, so it does not clear it), ColdCapture = `$D00`, one fetch of `$D00` from the host ROM address space per
  reset, MemList, free counts and board list identical before and after the reset. The "Autoconfig Z2" area at
  `$E80000` in Amiberry's map on the A1200 profile is the emulator quirk already noted above.
  Workbench free memory 5844632, the same figure as run 5 of the first table (same host, profile and memory).

## Slow-RAM placement with a board record (real 1.3 host)

Rebuilt disk, `build/KickSlopStart.adf` md5 `fb8f61c20b8d6bee9d6986d779758cd7`. Design change under test: when slow
RAM covers `$C00000`, the bootblock copies the image there and now also writes the host's Zorro II board record at
`$C00` (magic `$4B535352`, image base `$C00000` at `$C04`, count at `$C08`, 20-byte entries from `$C10`); the final
copy runs from a copy of the bootblock's copy routine placed in the chip buffer after the image and the record. The
image's expansion.library rebuilds the recorded boards on its first boot and then clears the magic; after a reset its
own ConfigChain finds the boards. Before this change the slow-path image did not see the host's boards until the
first reset. Observed on 2026-11-23 under Amiberry v8.4.2, host KS 1.3 on the A500 profile, cycle-exact
(`amiberry-session start --analysis`), two sessions at most. Same method as "Board record in every placement": IPC
reads (PAUSE/READ_MEM/GET_CPU_REGS/RESUME) about 25 s after the coldstart serial line, a logging instruction-fetch
watch on the reset entry (`$C000D2` for the slow image, `$D00` for the fast one), IPC `RESET` (keyboard reset), the
same reads about 60 s later, then a copy of the Workbench 1.3.3 disk inserted and an IPC screenshot 180 s later.
Board lists read through public structures only (ExpansionBase found by name in exec's LibList, eb_BoardList at
+`$3C`); Amiberry's memory map with IPC `MONITOR memory-map`, card configuration lines from Amiberry's log.

### Configurations

| # | Amiberry options (after `--analysis`) | Boards in the emulator |
|---|----------------------------------------|------------------------|
| A | `--chip 512 --slow 512 --fast 0 -- -s a2065=slirp` | A2065 Ethernet (I/O, 64 KB), no fast RAM |
| B | `--chip 512 --slow 512 --fast 0` | none |
| C | `--chip 512 --slow 512 --fast 2` | 2 MB Zorro II RAM |

### Results

| # | Image base | ColdCapture | `$C00` / `$C04` / `$C08` (first boot) | Record entry | Image MemList (attrs) | Image board list | Reset entry fetched | Same state after reset | Workbench 1.3.3, free |
|---|---:|---|---|---|---|---|---|---|---:|
| A | `$C00000` (slow) | `$C000D2` (image's reset entry) | 0 (consumed) / `$C00000` / 1 | er_Type `$C1`, product `$70`, slot `$E9`, cd_Flags `$0002` | slow `$C404D0`-`$C7F000` (`$0005`), chip `$1000`-`$80000` (`$0003`) | A2065 at `$E90000`, size `$10000`, flags `$02` | `$C000D2`, once, from the host ROM | yes | yes, 617416 |
| B | `$C00000` (slow) | `$C000D2` (image's reset entry) | 0 / `$C00000` / 0 | none | same as A | empty | `$C000D2`, once, from the host ROM | yes | yes, 617488 |
| C | `$3C0000` (fast) | `$D00` (relay) | `$4B535352` (kept) / `$3C0000` / 1 | er_Type `$E6`, product `$51`, slot `$20`, cd_Flags `$0002` | fast `$200020`-`$3C0000`, slow `$C404D0`-`$C7F000`, chip `$1000`-`$80000` | Z2 RAM at `$200000`, size `$200000`, flags `$02` | `$D00`, once, from the host ROM | yes | yes, 2441128 |

ExecBase was `$C40276` (slow RAM, just above the 256 KB at `$C00000`) in all three. PC sampled before and after each
reset was inside the image (`$C0xxxx` for A/B, `$3Cxxxx` for C), SR `$2000`. Every screenshot shows the Workbench
desktop with the RAM DISK and Workbench1.3 icons. All three reached the coldstart serial line within the 300 s budget.

### Details

- **Config A: fixed.** The A2065 the host configured at `$E90000` is in the image's board list on the first boot,
  before any reset (one ConfigDev, cd_BoardAddr `$E90000`, cd_BoardSize `$10000`, cd_Flags `$02`), and the magic at
  `$C00` reads 0 with the entry itself still in RAM, as designed. After the reset Amiberry's log shows "Card 1: Z2
  0x00e90000 64K IO 7990 Ethernet" a second time (configured again by the image's own expansion, the record being
  gone), its memory map has the "7990 Ethernet" area, and the image's board list, MemList and free-byte counts are
  identical to the first boot (ConfigDev at the same address with the same fields).
- **Config B (no board).** `$C00` reads 0 with the count at `$C08` = 0 and `$C04` = `$C00000`; whether the magic was
  written and then cleared, or never written, cannot be told from the final state. The board list is empty before
  and after the reset; nothing else differs from A.
- **Free memory, A vs B.** 617416 vs 617488: A has 72 bytes less, the size of one ConfigDev allocation, the same
  per-board cost as in "Several Zorro II boards".
- **Slow image and the free pool.** In A and B the slow MemHeader starts at `$C404D0` (after the image's 256 KB and
  ExecBase) and ends at `$C7F000`; the chip header is `$1000`-`$80000`. The image is outside every free pool. The top
  4 KB of slow RAM (`$C7F000`-`$C80000`) is also outside the pool (the supervisor stack pointer sampled at boot was
  `$C80000`).
- **Config C (fast path regression).** Unchanged: fast placement chosen over slow, record kept with its magic,
  ColdCapture = `$D00`, one fetch of `$D00` from the host ROM address space, state identical before and after the
  reset. The Workbench figure 2441128 is the same as run 2 of the first table (same memory). The Zorro II board was
  configured twice in Amiberry's log (host boot, then the relay after the reset).
- **Observation (config C, unchanged from run 2).** With the image in fast RAM, ExecBase still sits at `$C40276` and
  the slow MemHeader still starts at `$C404D0`: the 256 KB of slow RAM at `$C00000`-`$C40000` is in no free pool
  although the image is not there. The Workbench figure matches the old disk, so this is not new with this change.
  Addressed by the change tested in the next section.

## Full revalidation after the slow-RAM reserve change

Rebuilt disk, `build/KickSlopStart.adf` md5 `1002431a411373889cab1b878f017585`. Design change under test: the first
256 KB of slow RAM (`$C00000`-`$C3FFFF`) is now reserved only when the image itself lies at `$C00000` (slow-RAM
placement). With the image elsewhere, the image's ExecBase goes to the bottom of slow RAM (`$C00276` instead of
`$C40276`) and the whole slow RAM is in the free pool. Observed on 2026-11-23 under Amiberry v8.4.2 (headless
`amiberry-session start --analysis`), two sessions at a time while another session ran its own emulators. Same
method as "Board record in every placement": IPC reads (PAUSE/READ_MEM/GET_CPU_REGS/RESUME) after the coldstart
serial line; a logging instruction-fetch watch on ColdCapture (`$D00` for the relay, the image's reset entry for a
chip or slow image), IPC `RESET` (keyboard reset), the same reads 60 s later; then a copy of the Workbench 1.3.3 disk
inserted and IPC screenshots 180, 240 and 330 s later (180 s and 240 s for configs 1 and 2). Board lists read through
public structures only (ExpansionBase found by name in exec's LibList, eb_BoardList at +`$3C`).

### Results

| # | Host, profile | Amiberry options (after `--analysis`) | Image base | ExecBase | ColdCapture | `$C00` magic / count | Image MemList (lower-upper) | Image board list | Reset entry fetched | Same state after reset | Workbench 1.3.3, free | Verdict |
|---|---|---|---:|---:|---|---|---|---|---|---|---:|---|
| 1 | KS 1.3, A500 | `--chip 512 --slow 512 --fast 2` | `$3C0000` (fast) | `$C00276` | `$D00` | `$4B535352` / 1 | fast `$200020`-`$3C0000`, slow `$C004D0`-`$C7F000`, chip `$1000`-`$80000` | Z2 RAM `$200000`, size `$200000`, flags `$02` | `$D00`, once, from the host ROM | yes | yes, **2703272** | PASS |
| 2 | KS 1.3, A500 | `--chip 512 --slow 512 --fast 0 -- -s a2065=slirp` | `$C00000` (slow) | `$C40276` | `$C000D2` | 0 (consumed) / 1 | slow `$C404D0`-`$C7F000`, chip `$1000`-`$80000` | A2065 `$E90000`, size `$10000`, flags `$02` | `$C000D2`, once, from the host ROM | yes | yes, 617416 | PASS |
| 3 | KS 1.3, A500 | `--chip 512 --slow 0 --fast 2` | `$3C0000` (fast) | `$1276` | `$D00` | `$4B535352` / 1 | fast `$200020`-`$3C0000`, chip `$3500`-`$80000` | Z2 RAM `$200000`, size `$200000`, flags `$02` | `$D00`, once, from the host ROM | yes | yes, 2174840 | PASS |
| 4 | KS 2.05, A600 | `--chip 1024 --slow 0 --fast 2 -- -s chipset=ecs_agnus -s chipset_compatible=A600` | `$3C0000` (fast) | `$1276` | `$D00` | `$4B535352` / 1 | fast `$200020`-`$3C0000`, chip `$3500`-`$100000` | Z2 RAM `$200000`, size `$200000`, flags `$02` | `$D00`, once, from the host ROM | yes | yes, 2698904 | PASS |
| 5 | KS 3.1, A1200 68030 | `--chip 2048 --slow 0 --fast 4 -- -s cpu_model=68030 -s chipset=aga -s chipset_compatible=A1200` | `$5C0000` (fast) | `$1276` | `$D00` | `$4B535352` / 1 | fast `$200020`-`$5C0000`, chip `$3500`-`$200000` | Z2 RAM `$200000`, size `$400000`, flags `$02` | `$D00`, once, from the host ROM | yes | yes, 5844632 | PASS |
| 6 | KS 3.1, A1200 68040, Z2 + Z3 | `--chip 2048 --slow 0 --fast 2 -- -s cpu_model=68040 -s fpu_model=68040 -s cpu_24bit_addressing=false -s z3mem_size=16 -s chipset=aga -s chipset_compatible=A1200` | `$1C0000` (chip) | `$1276` | `$1C00D2` | 0 (consumed) / 1 | fast `$200020`-`$400000`, chip `$3500`-`$200000` | Z2 RAM `$200000`, size `$200000`, flags `$02` | `$1C00D2`, once (caller not identifiable) | yes | yes, 3747480 | PASS |
| 7 | KS 3.0, A1200 68060 | `--chip 2048 --slow 0 --fast 4 -- -s cpu_model=68060 -s fpu_model=68060 -s cpu_24bit_addressing=false -s chipset=aga -s chipset_compatible=A1200` | `$5C0000` (fast) | `$1276` | `$D00` | `$4B535352` / 1 | fast `$200020`-`$5C0000`, chip `$3500`-`$200000` | Z2 RAM `$200000`, size `$400000`, flags `$02` | `$D00`, once (caller not identifiable) | yes | yes, 5844632 | PASS |
| 8 | KS 1.3, A500, two Z2 boards | `--chip 512 --slow 0 --fast 2 -- -s fastmem2_size=2` | `$5C0000` (fast) | `$1276` | `$D00` | `$4B535352` / 2 | fast `$200020`-`$400000`, fast `$400020`-`$5C0000`, chip `$3500`-`$80000` | Z2 RAM `$200000` and `$400000`, size `$200000` each, flags `$02` | `$D00`, once, from the host ROM | yes | yes, 4271888 | PASS |

All MemHeaders: attributes `$0005` for fast and slow (slow priority -5), `$0003` for chip (priority -10). Record entries
(cd_Rom er_Type / slot / cd_Flags as left by the host) were the same as in the earlier sections: `$E6`/`$E7` RAM
boards at slot `$20` (and `$40` in config 8), `$0002` under KS 1.3 and `$000A` under KS 2.05/3.0/3.1; the A2065
entry er_Type `$C1`, product `$70`, manufacturer `$0202`, slot `$E9`. PC sampled before and after each reset was
inside the image (base to base+`$40000`), SR `$2000` (`$2700` in config 7, sampled inside a masked section). Every
configuration reached its coldstart serial line within the 300 s budget (29-97 s for configs 3-8), and every
Workbench screenshot that was looked at for the verdict shows the desktop with the RAM DISK and Workbench1.3 icons.

### Details

- **Config 1 (the change).** ExecBase now sits at `$C00276`, and the slow MemHeader (node at `$C004B0`) runs from
  `$C004D0`, just above ExecBase, to `$C7F000`: the whole slow RAM below the top 4 KB is in the free pool (517792
  bytes free in that header, before and after the reset). Before the change the same configuration had ExecBase at
  `$C40276` and the slow header at `$C404D0`-`$C7F000` (section "Slow-RAM placement with a board record", config C).
  Workbench free memory: **2441128 before, 2703272 now, a gain of exactly 262144 bytes (256 KB)**, as expected.
  The fast header still ends at the image base (`$3C0000`), so the image remains outside every free pool.
- **Config 1, sampling note.** The pre-reset read was taken a few seconds after the coldstart line instead of about
  25 s later, so its free-byte counts (fast 1800408, chip 506240) were sampled earlier in the boot than the
  post-reset ones (fast 1782296, chip 457608); the MemHeader bounds, the record, ColdCapture and the board list were
  identical before and after the reset, and the slow header's count (517792) matched.
- **Config 2 (slow placement).** Unchanged by design: the 256 KB reserve is kept because the image is at `$C00000`,
  ExecBase is still `$C40276`, slow header `$C404D0`-`$C7F000`. The A2065 is in the image's board list before the
  reset (magic consumed, entry still in RAM), Amiberry's log shows the card configured again after the reset, and the
  Workbench figure 617416 is the same as before.
- **Workbench delay.** Config 2's desktop came up between 180 s and 240 s after the insertion (at 180 s the
  startup-sequence was still running in the AmigaSlopDOS window); configs 3 and 4 needed between 240 s and 330 s,
  while four emulators were running on the machine. Slow, not stuck: each reached the desktop.
- **Configs 3-8 (no slow RAM).** Identical to the earlier runs: same image base, MemList, record, board list and
  Workbench figures (2174840, 2698904, 5844632, 3747480, 5844632, 4271888). ExecBase is `$1276` in chip RAM; the
  chip header starts at `$3500` as before.
- **Reset path.** One logged fetch of the watched entry per reset in every configuration. On the 68000 and 68030
  cores (configs 1-5, 8) the fetching instruction was executing in the host ROM address space. On the 68040
  (config 6) the logged `instruction_pc` is inside our image just after the entry, and on the 68060 (config 7) it is
  `$D00` itself: as noted earlier, these cores do not tell who jumped there.
- **Config 6, Zorro III board after the reset: unchanged.** Before the reset Amiberry's map has "Zorro III Fast RAM"
  at `$40000000` and nothing pending at `$E80000`; after the reset the Zorro III board answers at `$E80000` ("Z3Fast")
  and stays pending, as in "Board record in every placement", config A.

## Not covered

- A real power cycle (RAM lost): only the keyboard reset was tested; with RAM cleared the image is gone by design.
- CPU-slot memory; an I/O board with a boot ROM (DiagArea) or one that needs a driver bound by `BindDrivers` (the
  A2065 here is configured and listed, but no driver was bound or used).
- A Kickstart that configures Zorro III boards at `$FF000000` (A3000/A4000 Kickstart): none was available, so the
  refusal path was only exercised with a Zorro III board answering in Zorro II space (config 6 above).
- An emulated MMU (`MMU=0` in every run): the bootblock's cache/TC/TTR shutdown on the 68040/68060 was not exercised
  against active translation, and whether the host's AttnFlags had the 68040 bit on the 68060 was not observed.
- KS 2.04 on an A500+ profile.
- Uncertain point: the 68040/68060 caller of `$D00` (see "Reset path").
