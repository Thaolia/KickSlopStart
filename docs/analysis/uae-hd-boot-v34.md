# uae-hd-boot-v34.md — booting and mounting from a board with a DiagArea (FS-UAE "uaehf" case)

> ANALYSIS track ("dirty"). Sources: ROM `kick34005.A500` (exec 34.2, expansion 34.1, romboot 34.1,
> strap 34.4, dos 34.3) read under radare2; black-box probes on the real ROM under FS-UAE 3.2.35
> (`tests/bootlist.s`, `tests/adn.s`, `tests/cfgdev2.s`, vectors §7); GPL source code of FS-UAE 3.2.35
> (`src/filesys.cpp`, `src/filesys.asm` — software independent of the ROM) for the emulator side.
> We describe the **what**; no instruction sequence transcribed, no routine address.
>
> Legend: **[R]** ROM analysis · **[S]** probe · **[U]** FS-UAE source · **[D]** public documentation.
> Prerequisite: `autoconfig-v34.md` (ConfigChain, DiagArea, `er_Reserved0c`, MakeDosNode/AddDosNode).

---

## 0. Short answer: why "nothing appears" on our ROM

On the real 1.3, the UAE board's DiagPoint **does almost nothing**: it builds a **ROMTag**
(`uaehf.device`, RTF_AUTOINIT|RTF_COLDSTART, NT_DEVICE) in the **RAM copy of its DiagArea** (at
`copy + $10`) and returns D0 = 1 **[U]**. It is **romboot.library** (COLDSTART resident pri −40) that, at its
init, looks for this ROMTag in the DiagArea copy of each configured board and **InitResident()**s it **[R]**.
The init of `uaehf.device` (UAE code) then opens expansion.library, **adds the "dummy" ConfigDev at
$F00000** (AddConfigDev), creates the DeviceNodes (MakeDosNode) and **enqueues one BootNode per bootable unit in
`eb_MountList`** **[U]**. Then strap tries DF0:, then calls romboot which jumps to the board's **BootPoint**;
and **dos.library, at its init, chains the DeviceNodes of `eb_MountList`** into its device list
(DH0: mounted); **the head of `eb_MountList` becomes SYS:** — after a successful DF0: bootblock, strap has added
a DF0: BootNode of priority 5 there, so that a board of priority ≥ 5 boots even with a bootable
floppy **[R+S]**. What is missing, in order: (1) romboot's ROMTag scan, (2) the call of the
BootPoint by romboot from strap (and strap's DF0: BootNode), (3) the consumption of `eb_MountList` by
dos.

---

## 1. Residents outside the Kickstart ROM (exec, coldstart) **[R; S]**

- At coldstart, before any resident init, exec builds `ExecBase->ResModules` (+$12C) by scanning a
  table of **[start, end)** ranges: **`$FC0000–$1000000`** (twice, entry repeated in the 34.5 table) then
  **`$F00000–$F80000`**. So **yes, the `$F00000–$F7FFFF` area is scanned**, in the **same** sort as the ROM.
- Criterion: word `RTC_MATCHWORD = $4AFC` at an **even** address and `rt_MatchTag == address of the structure`;
  after a recognised ROMTag, scanning resumes at `rt_EndSkip`. No condition on `rt_Flags` for
  registration.
- Duplicates (same `rt_Name`): the new one replaces the old one if `rt_Version` is **higher**, or equal with
  `rt_Pri` **≥**; otherwise it is ignored. The final sort is by decreasing `rt_Pri` (rule of
  `module-map.md`). The ROMTags of `KickTagPtr` (if `KickCheckSum` is valid) are merged in the same way.
- Then `InitCode(RTF_COLDSTART, 0)` initialises, by priority, all entries having RTF_COLDSTART, whether they
  come from `$FC…` or from `$F0…`.
- Independently (at the very start of reset, even before RAM): if exec is not already running from `$F00000`
  and the word at `$F00000` is **`$1111`**, it jumps to `$F00002` (diagnostic/cartridge ROM).
- **This is NOT how the UAE board installs itself**: UAE's `$F00000` area ("rtarea") contains no
  ROMTag visible to this scan (probe §7: no ResModules entry outside `$FC…–$FF…`) and does not start
  with `$1111`. **[S]** (vector C1: 24 entries, all in `$FC…`–`$FF…`; `uaehf.device` is not in
  ResModules but in DeviceList.)

---

## 2. romboot.library 34.1 **[R]**

COLDSTART resident, NT_LIBRARY, pri **−40** (after intuition, before strap). A single public function (LVO
−30, "RomBoot"), plus Open/Close/Expunge.

### 2.1 Init: board ROMTags ("InitResidents")

1. `OpenLibrary("expansion.library", 33)`; failure ⇒ nothing.
2. For each ConfigDev of `eb_BoardList` (list order) with `cd_Flags & CDF_CONFIGME ($02)`:
   1. `ObtainConfigBinding()`; `SetCurrentBinding({cb_ConfigDev = cd, FileName = 0, ProductString = 0,
      ToolTypes = 0}, 16)`;
   2. if `er_Type & ERTF_DIAGVALID ($10)` and `cd_Rom.er_Reserved0c` (pointer to the **RAM copy** of the
      DiagArea, set by expansion, `autoconfig-v34.md` §6) is non-zero, and `da_Config & DAC_CONFIGTIME
      ($10)`: search, in 2-byte steps from the start of the copy and over `da_Size` bytes, for the
      **first** ROMTag (`$4AFC` + `rt_MatchTag` = itself); if found: **`InitResident(tag, 0)`**
      (only one per board);
   3. `ReleaseConfigBinding()`.
3. `CloseLibrary(expansion)`. `CDF_CONFIGME` is not cleared (BindDrivers does that).

At this point all ROM libraries/devices are initialised (expansion is in LibList, graphics,
intuition, timer, trackdisk… exist), **but not dos**.

### 2.2 RomBoot (LVO −30): calling the BootPoints

1. `OpenLibrary("expansion.library", 33)`.
2. Walk of `eb_MountList` in order (Enqueue ⇒ decreasing `ln_Pri`). A node is kept if
   `bn_DeviceNode ≠ 0`, **`ln_Type == NT_BOOTNODE (16)`** and `ln_Name ≠ 0` (in a BootNode, `ln_Name` carries
   the board's **ConfigDev**). For each kept node, with this ConfigDev:
   - if `er_Type & DIAGVALID`, DiagArea copy non-zero, and `da_Config & DAC_CONFIGTIME`: call of
     **`copy + da_BootPoint`** (`da_BootPoint` = UWORD at +6, unsigned) with **A0 = called address,
     A1 = ConfigDev**, the ConfigDev also as an argument on the stack (4(SP)), **A6 = ExecBase**.
   - **no `da_BootPoint == 0` test**: a DiagArea without a BootPoint would jump to the start of the copy
     (do not reproduce as is: treating 0 as "no BootPoint" is safer and invisible in practice).
   - if the BootPoint **returns**, the walk continues with the next node (its return value is ignored).
3. `CloseLibrary`; return (D0 = 0) to the caller.

The BootNodes set by `AddDosNode` before dos (`ln_Type` uninitialised, `ln_Name` = C name of the device,
`autoconfig-v34.md` §7) **are not** bootable BootNodes for romboot (type ≠ 16 in practice):
only those enqueued by the driver itself with `ln_Type = NT_BOOTNODE` and `ln_Name = ConfigDev` are.

---

## 3. strap 34.4: floppy attempt, RomBoot, DF0: BootNode **[R; S]**

1. Allocates a block of `$488` bytes (MEMF_CHIP|MEMF_CLEAR, boot buffer + variables), a port, opens
   trackdisk.device unit 0.
2. **DF0: attempt** (CMD_CLEAR, TD_CHANGENUM, read of 1024 bytes): word `'DOS\0'` and checksum
   (sum with carry of the 256 longs, complemented = 0) ⇒ execution of the bootblock (A1 = IORequest,
   A6 = ExecBase). If D0 ≠ 0 on return ⇒ Alert `$30000001`. If D0 = 0:
   - strap **creates the DF0: DeviceNode and declares it as a BootNode**: `OpenLibrary("expansion.library", 33)`,
     `MakeDosNode` with the packet {`"DF0"`, `"trackdisk.device"`, unit 0, flags 0, environment
     `de_TableSize = 12`, SizeBlock 128, SecOrg 0, Surfaces 2, SectorPerBlock 1, BlocksPerTrack 11,
     Reserved 2, PreAlloc 0, Interleave 0, LowCyl 0, HighCyl 79, NumBuffers 5, BufMemType 2 (CHIP)}, then
     **`AddDosNode(5, 0, dn)`** — dos not existing yet, it is a BootNode **`ln_Pri = 5`**, `ln_Type`
     uninitialised, `ln_Name = "DF0"`, enqueued (Enqueue) **behind** the nodes of priority ≥ 5 already present;
   - then jump to the entry point returned by the bootblock in A0 (the dos init).
3. **If DF0: is not bootable** (no disk, not DOS, wrong checksum): **only once**,
   `OpenLibrary("romboot.library")` → **RomBoot()** (§2.2) → CloseLibrary. No DF0: BootNode is created on this
   path. A BootPoint that starts dos does not return.
4. If RomBoot returns: new DF0: attempt, then "insert a disk" screen and wait for a disk
   change, subsequent DF0: attempts **without** calling romboot again.

The **choice of the boot volume** is therefore not made by strap but by dos (§4.1): the **head of
`eb_MountList`** wins. The bootblock of a bootable floppy is always executed first, but
**a board whose BootNode has `ln_Pri ≥ 5` still becomes SYS:** (its node precedes that of DF0:, pri 5,
enqueued later); with `ln_Pri < 5`, DF0: becomes SYS: and the board is only mounted. **[R+S]**
(vectors P10, P5, P1, C1, C2).

---

## 4. dos.library 34.3 and `eb_MountList` **[R; S]**

### 4.1 At dos init (called by the DF0: bootblock or by the board's BootPoint)

In the assembler part of the init, before the initial CLI is started:
1. `OpenLibrary("expansion.library", 0)` (never closed; no failure test).
2. **Chaining**: walk of `eb_MountList`; for each pair of consecutive nodes (N, N+1) as long as
   `N.bn_DeviceNode ≠ 0`, `N.bn_DeviceNode->dn_Next == 0` and `(N+1).bn_DeviceNode ≠ 0`:
   `N.bn_DeviceNode->dn_Next = BPTR((N+1).bn_DeviceNode)`. The DeviceNodes of **all** nodes (whatever
   `ln_Type`) thus form a chain in list order.
3. **`RemHead(eb_MountList)`**: the **first** node is removed (not freed); its `bn_DeviceNode` (APTR) is
   passed to the BCPL part of the init (stored temporarily in `RootNode+$1C`, which later takes back its
   normal value `rn_FileHandlerSegment`). This DeviceNode is the **boot device** (SYS:) and the chain
   starting at it is placed in `DosInfo->di_DevInfo`, at the **bottom** of the list (the nodes created later
   by dos — RAM, CON, RAW, SER, PAR, PRT, volumes, assigns — are inserted in front). **[R+S]**
4. The other nodes **remain** in `eb_MountList` (probe: after a DF0: boot with DH0 pri 0 or 1, the
   DH0 BootNode is still there). **[S]**
5. If the boot device is not strap's DF0: (boot via BootPoint, or priority board), dos
   creates **its own** DF0: DeviceNode (inserted in front); if a strap DF0: BootNode was also present
   (priority board + bootable floppy), **DF0 appears twice** in the device list (both
   mounted on the same floppy) — a faithful artefact of 1.3. **[S]** (vector P10/P5)

### 4.2 AddDosNode after dos init **[R; S]**

`AddDosNode(bootPri, flags, dn)` (expansion −150) first tries `OpenLibrary("dos.library")`; if dos exists:
- if `dn_Task`, `dn_Handler` and `dn_SegList` are all zero: `dn_SegList = rn_FileHandlerSegment` (the
  ROM's OFS handler);
- under Forbid, **insertion at the head** of `di_DevInfo` (`dn_Next = old head`);
- if `flags & 1`: internal dos call (private entry, D1 = BPTR of the DeviceNode) — not probed;
- CloseLibrary(dos); since dos's CloseLibrary returns 0, the function **additionally enqueues** a BootNode in
  `eb_MountList` (`ln_Pri = bootPri`, `ln_Name` = C name of the device) and returns **1**. This extra BootNode is
  harmless (dos only re-reads `eb_MountList` at its init). **[R+S]** (vector ADN)

### 4.3 Before dos init

`AddDosNode` ⇒ uncleared 20-byte BootNode enqueued in `eb_MountList` (`autoconfig-v34.md` §7); it will be
chained and mounted by §4.1, and may even become SYS: if it is at the head; it is not bootable by romboot
(§2.2), lacking `ln_Type = NT_BOOTNODE` and a ConfigDev.

---

## 5. Complete sequence observed for the UAE board (`hard_drive_0 = <directory>`)

1. exec: ROMTag scan (ROM + `$F00000–$F7FFFF`) — no UAE ROMTag found —, COLDSTART init;
   **expansion** (pri 110): ConfigChain ⇒ UAE board at `$E90000` (`er_Type $D1`, manuf. 2011,
   `InitDiagVec $2000`), copy of the DiagArea in slow RAM (`$C01AE0`), **DiagPoint** called (A0/A2/A3/A5/A6,
   `autoconfig-v34.md` §6) ⇒ ROMTag `uaehf.device` written at copy+$10 (`$C01AF0`); D0 = 1. **[S+U]**
2. … ROM residents (graphics … intuition, alert.hook, mathffp) …
3. **romboot init** (pri −40): ROMTag found in the copy ⇒ `InitResident` ⇒ device `uaehf.device` in
   DeviceList, whose init (UAE code) does `AddConfigDev` of a ConfigDev at **`$F00000`** (64 KB, `er_Type $01`,
   product 4, manuf. 2011, serial 1), then per unit MakeDosNode + BootNode (`ln_Type = 16`, `ln_Pri =
   bootpri`, `ln_Name` = **ConfigDev of the `$E90000` board**) Enqueue into `eb_MountList`. **[U; S]**
4. **strap** (pri −60): DF0: bootable ⇒ bootblock + DF0: BootNode pri 5 + dos init; otherwise RomBoot ⇒
   BootPoint of the UAE board ⇒ `FindResident("dos.library")` + call of its `rt_Init`. **[R+U; S]**
5. **dos init**: chaining + RemHead of `eb_MountList` ⇒ SYS: = head of list, DH0: mounted in all cases.
   **[R+S]**

Minimum for our ROM: (a) romboot §2.1 (scan of the DiagArea copy + InitResident under
ConfigBinding); (b) strap §3 (including the DF0: BootNode pri 5 after a successful bootblock) + RomBoot §2.2;
(c) dos §4.1 (chaining of `eb_MountList`, head = SYS:, DF0: created by dos if it is not the boot
device); (d) an InitResident of an AUTOINIT NT_DEVICE called from a resident must work (AddDevice);
(e) exec's `$F00000` scan is not needed for UAE but is part of the 1.3 behaviour.

---

## 6. Emulator side (FS-UAE 3.2.35) — landmarks **[U]**

- Log `~/FS-UAE/Cache/Logs/fs-uae.log.txt`: `filesystem: diagentry <copy+$10> configdev <ConfigDev>`
  at DiagPoint time.
- `filesys_init` (called by the init of `uaehf.device`) tries `OpenLibrary("expansion.library", 36)` then 0;
  creates the dummy ConfigDev (unless the "hide autoconfig" option is set); `make_dev` per unit; on KS ≥ 34 also creates
  a mounting task.
- UAE BootPoint = `FindResident("dos.library")` then call of `rt_Init` (A6 = ExecBase required).
- The UAE DiagPoint also installs `uae.resource` and two interrupt servers (PORTS pri 20, VERTB pri −10);
  "uae_int" mechanism (PORTS) and level-2 blocking of our ROM: see `uae-int2-v34.md`.

---

## 7. Test vectors

Probes: `tests/bootlist.s`, `tests/cfgdev2.s`, `tests/adn.s` (+ commands C:CD/Assign/Info), on the real
ROM 34.5, FS-UAE 3.2.35, `slow_memory = 512`, `fast_memory = 2048`, `hard_drive_0 = <host dir>` (containing
`s/startup-sequence`, `c/`, `l/Port-Handler`, `devs/serial.device`, the probes). Floppy = copy of WB
1.3.3 (probes in its startup-sequence) or blank formatted ADF without bootblock. Formats:
`BN node type<<24|pri<<16|bn_Flags ln_Name bn_DeviceNode`; `DN addr type task lock handler startup seglist gv name`.

```
=== C1 : bootable WB + DH0 (bootpri 0)
FLOPPYBOOT                                   (startup of the floppy)
RM … 24 lines, all $FC…/$FF… (none at $F0…)
DV 00C04A34 uaehf.device                     (device initialised, absent from ResModules)
BN 00C04DD8 10000000 00C01620 00C04E10       UAE BootNode: type 16, pri 0, ln_Name = ConfigDev $E90000 (C01620)
DN … RAM / DF0 00C04D80 / DH0 00C04E10 at the end of the list
DN 00C04E10 00000000 00C0757C 00000000 003C3F94 0030117A 003C0002 FFFFFFFF DH0
CD 00E90000 00010000 02D15240 000007DB 00E90001 00002000 00C01AE0 …
CD 00F00000 00010000 00010400 000007DB 00000000 …               ConfigDev added by uaehf
Assign : SYS = Workbench1.3:      Info : DF0: Workbench1.3, DH0: hddir
AD 00C0A070 00000001                         AddDosNode(0,0,"ZZ0") after dos: returns 1
BN 00C04DD8 10000000 00C01620 00C04E10
BN 00C0A038 00000000 00C014D1 00C0A070       + BootNode enqueued (type 0, name "ZZ0")
DN 00C0A070 … 003FE9E2 … ZZ0                 at head of DevInfo, dn_SegList = rn_FileHandlerSegment
=== C2 : blank non-bootable ADF + DH0 (bootpri 0)
HDBOOT                                        (startup of DH0 ⇒ BootPoint called)
(no BN line: eb_MountList empty)
DN 00C0097C … DF0                            DF0 created by dos, at head
DN 00C04E10 … DH0                            at the bottom of the list
Assign : SYS = hddir:
=== P1 : bootable WB + DH0 bootpri 1
FLOPPYBOOT ; BN 00C04DD8 10010000 00C01620 00C04E10 (remains) ; SYS = Workbench1.3:
=== P5 and P10 : bootable WB + DH0 bootpri 5 / 10 (identical results)
HDBOOT                                        (DF0 bootblock executed, but SYS = DH0)
BN 00C04D48 00050000 00C04DB1 00C04D80       remaining strap DF0: BootNode: type 0, pri 5, "DF0"
DN 00C08F5C … DF0                            DF0 recreated by dos
DN 00C04E10 … DH0
DN 00C04D80 … DF0                            strap's DF0 chained behind DH0 ⇒ DF0 listed 2 times
Assign : SYS = hddir:
```

FS-UAE log (C1): `filesystem: diagentry 00c01af0 configdev 00c01620` then `Mounting uaehf.device 0 (0)`.
Proposed non-regression for our ROM: C2 (DH0 boot via BootPoint, SYS = DH0) and C1 (floppy boot, DH0 mounted,
ConfigDev `$F00000` present).

---

## 8. Not probed / uncertain

- **Exact mechanism of the SYS: choice in the BCPL part of dos**: deduced (head of `eb_MountList` removed by
  RemHead and passed to the BCPL) and confirmed by the five vectors, but the BCPL code was not followed.
- "Priority board + bootable floppy" case: the floppy's bootblock is executed (strap) before dos
  starts on DH0; a non-standard bootblock (that does not return the dos init) would short-circuit everything — not probed.
- `AddDosNode` with `flags & 1` (internal dos call): ROM only, not probed.
- BootPoint of a DiagArea with `da_BootPoint = 0`: ROM only (jump to the start of the copy).
- A **BYTEWIDE/NIBBLEWIDE** DiagArea board with a ROMTag: romboot scans the RAM copy, so it makes no difference;
  not probed.
- `$F00000–$F7FFFF` scan by exec and `$1111` jump at `$F00000`: ROM only (no cartridge ROM
  available in the emulator).
- The "uninitialised" ln_Type of AddDosNode's BootNodes was 0 in the probes (AllocMem without CLEAR); a
  residual value of 16 would make the node eligible for RomBoot with an ln_Name that is not a ConfigDev — not
  reproduced.

---

## Clean-room review

- [x] No instruction sequence transcribed or paraphrased; no ROM routine address (only
  offsets of public/private structures, ABI constants and hardware ranges).
- [x] The probes cited are author code (`tests/`, header "ASSET DE TEST, PAS du code ROM").
