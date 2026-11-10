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
   **`bn_Flags` is never read** during this walk: `ADNF_STARTPROC` and any other flag bit are
   ignored by dos init. **No handler process is started here.** **[R; S]** (ROM disassembly
   confirmed: the chain-walk loop only tests `ln_Succ`, `bn_DeviceNode` and `dn_Next`; there is no
   access to offset `$0E` = `bn_Flags`. Black-box probe: at 5 emulated seconds — after dos init and
   before the initial CLI's startup-sequence has executed any commands — all DeviceNodes in
   `di_DevInfo` including the Copperline `HOSTFS0` node have `dn_Task = 0`; see §4.4 and §9.)
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
- if `flags & 1` (ADNF_STARTPROC): **starts the handler synchronously** via BCPL global 112
  (`starthandler`), the same routine called by DeviceProc on first access. `starthandler` creates
  the handler process (C handler: `dn_StackSize` in bytes; BCPL handler: `dn_StackSize` in longs),
  sends the startup packet to the new process's `pr_MsgPort`, and **blocks** (synchronous) until
  the handler replies with `dp_Res1 ≠ 0` (success) or `dp_Res1 = 0` (failure). If the handler
  never replies the calling task deadlocks (no timeout). On a **successful** reply, `starthandler`
  writes `dn_Task` with the handler's `pr_MsgPort` before returning (black-box probe: the write to
  `dn_Task` originates from ROM code in the Initial CLI context, not from the handler process
  itself). Full startup packet contents: §4.4. **[R; S]**
- CloseLibrary(dos); since dos's CloseLibrary returns 0, the function **additionally enqueues** a BootNode in
  `eb_MountList` (`ln_Pri = bootPri`, `bn_Flags = flags`, `ln_Name` = C name of the device) and returns **1**.
  This extra BootNode is harmless: dos only re-reads `eb_MountList` at its init, and the remaining
  BootNodes in `eb_MountList` are never re-processed by any V34 component after dos init. **[R+S]** (vector ADN)

### 4.3 Before dos init

`AddDosNode` ⇒ uncleared 20-byte BootNode enqueued in `eb_MountList` (`autoconfig-v34.md` §7); it will be
chained and mounted by §4.1, and may even become SYS: if it is at the head; it is not bootable by romboot
(§2.2), lacking `ln_Type = NT_BOOTNODE` and a ConfigDev.

If `flags & 1` (ADNF_STARTPROC): `bn_Flags` is set to 1 in the BootNode, but **dos init ignores `bn_Flags`**
(§4.1). The handler is **not** started at dos init time. It starts on **first access** via `deviceproc`
(global 102) → `starthandler` (global 112), with the same synchronous protocol and startup packet as §4.4.
The DeviceNode remains in `di_DevInfo` with `dn_Task = 0` until `starthandler` writes it on the
first successful handler reply.

**Timing relative to the initial CLI**: dos init runs before the initial CLI. After dos init the CLI
starts, runs `S:CLI-Startup`, then `S:Startup-Sequence`. The handler is started the first time any
process calls `deviceproc` for the device. **[S]** (probe on a full WB 1.3.3 ADF: at 5 emulated
seconds all device handlers including the Copperline board's HOSTFS0 node had `dn_Task = 0`; the
HOSTFS0 handler started at ~9.44s, triggered by the Initial CLI during the final phase of the
startup-sequence — `LoadWB delay` or `endcli` — before the Workbench task was started; see §9.3.)
The calling process blocks synchronously until the handler replies. The Workbench task therefore
finds the handler already running (dn_Task ≠ 0) when it starts its device scan and shows the
volume icon without having to trigger a handler start itself. **[S]** (§9.3)

**Practical case — Copperline-style board (`AddDosNode(-128, ADNF_STARTPROC, dn)` from an `rt_Init`
during romboot, pri −40):** dos does not exist yet, so the before-dos path is taken and `bn_Flags = 1` is
stored. After dos starts and chains the DeviceNodes, the first `deviceproc` call for the device triggers
`starthandler`. For a C handler with `dn_GlobalVec = −1` and `dn_SegList = BPTR of the handler code`: the
handler process is created with `dn_StackSize` bytes of stack; the startup packet is sent (§4.4);
the calling process blocks synchronously until the reply; on success `starthandler` writes `dn_Task`.

**Uncertain**: whether a boot path exists in which dos init starts handlers directly (not via global 112)
with a different packet format (some third-party board documentation describes this case; the probe did
not reproduce it). **[Uncertain]** See §8.

### 4.4 Startup packet sent by starthandler (global 112) **[R; S]** (see `handlers-v34.md` §3.1–§3.5)

This applies to **both** the after-dos `ADNF_STARTPROC` path and the on-demand `deviceproc` path.
The same global 112 is used in both cases.

| Field | Value |
|---|---|
| `dp_Type` | **0** (ACTION\_STARTUP; zero both for V34 deferred/ADNF path) |
| `dp_Port` | reply port = `pr_MsgPort` of the calling process (set by `qpkt`) |
| `dp_Res2` | BPTR of the handler's GV (BCPL branch); **uninitialized residue** in the C branch (`dn_GlobalVec = −1`) |
| `dp_Arg1` | **Garbage** — a residue from the BCPL calling convention, not a device name. Two independent probes observed a 1-character BSTR `'S'` from a ROM constant table (not "HOSTFS0" or any device name). **A handler must not use dp_Arg1; use dp_Arg2 instead. [S]** |
| `dp_Arg2` | `dn_Startup` (BPTR to `FileSysStartupMsg`) |
| `dp_Arg3` | **NULL (0)** — confirmed by `last_writer` on the field: the most recent write set it to 0 from within the BCPL dispatch prologue; no subsequent write set it to a DeviceNode BPTR **[S]** |
| `dp_Link`, `dp_Res1` | stack-frame residues until the handler fills `dp_Res1` with its reply |

The handler must reply with `dp_Res1 ≠ 0` (conventionally `−1` = `DOSTRUE`) for success, or
`dp_Res1 = 0` for failure. On a successful reply, `starthandler` **writes `dn_Task`** with the
handler's `pr_MsgPort`, then sets `Result2 := dn_Lock` and returns the port. On failure, returns 0;
`Result2` = the handler's `dp_Res2`. `dn_Task` is not written on failure.

**A handler designed for V34 must locate its unit via `dp_Arg2`** (the `FileSysStartupMsg`): `dp_Arg3`
is NULL, so `dp_Arg2 → FileSysStartupMsg` is the only reliable path to the mount's configuration.

Note on the "boot path" distinct from global 112: some third-party documentation describes a dos-init
startup path where `dp_Type` = seglist BPTR, `dp_Res1` = stack size, and `dp_Arg3` = NULL — matching
the BCPL `createproc` calling convention rather than ACTION\_STARTUP. That path was not reproduced by
the probe (the probe used a C handler with a Copperline board, and the handler was always started via
global 112 on first `deviceproc` access). It may apply only when dos init starts the handler itself in
some configurations; this remains uncertain. **[Uncertain]**

Note on V36: AmigaDOS 2.0+ revised the protocol (`dp_Arg3` = BPTR DeviceNode). A V34-compatible
handler must not rely on `dp_Arg3`; use `dp_Arg2 → FileSysStartupMsg` instead.

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
- BootPoint of a DiagArea with `da_BootPoint = 0`: ROM only (jump to the start of the copy).
- A **BYTEWIDE/NIBBLEWIDE** DiagArea board with a ROMTag: romboot scans the RAM copy, so it makes no difference;
  not probed.
- `$F00000–$F7FFFF` scan by exec and `$1111` jump at `$F00000`: ROM only (no cartridge ROM
  available in the emulator).
- The "uninitialised" ln_Type of AddDosNode's BootNodes was 0 in the probes (AllocMem without CLEAR); a
  residual value of 16 would make the node eligible for RomBoot with an ln_Name that is not a ConfigDev — not
  reproduced.
- **Boot path with BCPL `createproc` packet format**: some third-party board documentation describes a
  startup packet with `dp_Type` = seglist BPTR, `dp_Res1` = stack size, `dp_Arg3` = NULL — matching
  the BCPL `createproc` register convention rather than `ACTION_STARTUP` = 0. This path was not
  reproduced in the Copperline probe: the board's C handler was always started via global 112 on first
  `deviceproc` access with `dp_Type` = 0 and `dp_Arg3` = NULL. Whether a distinct dos-init-driven
  startup path exists for certain board configurations is uncertain.
- **Exact trigger** for the first `deviceproc` call to a before-dos BootNode device: observed at ~9s
  emulated time in a boot from WB 1.3.3 ADF with startup-sequence `echo X >SER: / wait 60`; the
  specific call chain was not traced.

---

## 9. Amiberry runs (2026-11-05) [O, O-inj]

Real ROM under Amiberry (cycle-exact A500, `hardfile2=rw,DH0:<file>,32,1,2,512,-128,,uae0`), debugger
breakpoints on `uaehf.device` BeginIO and exec ReplyMsg, IPC watch on the DiagPoint.

- **DiagPoint and LibList**: when the board's DiagPoint gets control, exec's LibList contains only
  exec.library; the ExpansionBase given in A5 is not linked yet (`autoconfig-v34.md` §6 point 7). A DiagPoint
  cannot OpenLibrary expansion.library; the base in A5 is the one romboot and dos use later.
- Amiberry's `uaehf` differs from FS-UAE 3.2.35 here: **only the `$E90000` board ConfigDev** is in
  `eb_BoardList` after boot (no extra ConfigDev at `$F00000`). The DiagArea copy is in slow RAM as in §5
  (DiagPoint at copy + `$1E0`, BootPoint at copy + `$1F0`).
- The DH0: DeviceNode created by uaehf (no RDB) carries a 16-long environment: 128-long blocks, 1 surface,
  32 blocks per track, 2 reserved, LowCyl 0, HighCyl = size − 1 cylinders, 50 buffers, BufMemType 1, MaxTransfer
  `$7FFFFFFF`, Mask `$FFFFFFFF`, BootPri −128, DosType `'DOS\0'`; `dn_SegList` 0, so dos starts the ROM file
  system for it. With the Workbench floppy booting, the DH0: file system was already running (volume mounted)
  when the startup-sequence began.
- What the ROM file system sends to `uaehf` (TD_REMOVE, TD_CHANGESTATE, TD_PROTSTATUS, CMD_CLEAR, CMD_UPDATE,
  TD_MOTOR, single-block CMD_READ/CMD_WRITE; never TD_CHANGENUM) and how it reads rejected commands:
  `rom-filesystem-v34.md` §1.4. Partitions above 25 bitmap blocks (> 101,602 blocks of 512 bytes) do not work
  on 1.3: `rom-filesystem-v34.md` §8.6.
- Test-harness trap: Amiberry caches hardfile writes on the host; a hardfile read while the emulator runs can
  lag far behind what the Amiga wrote. Read images after stopping the session.

## 9.2 Copperline CCP probe (2026-11-10) **[S]**

Real KS 1.3 (kick34005.A500) under Copperline (headless, control protocol), 512 KB chip + 2 MB fast,
Copperline services board with 1 `[[filesys]]` HOSTFS0 mount (bootpri −128, C handler in board window,
`dn_GlobalVec = −1`), modified WB 1.3.3 ADF (`s/startup-sequence` = `echo X >SER: / wait 60`).
Memory read with `mem.read`; write timing with write watchpoints and `last_writer`.

```
ExecBase = $676  (chip RAM, 512 KB chip + 2 MB fast: exec base in low chip RAM)
DosBase  = $203538  (fast RAM)
HOSTFS0 DeviceNode = $202F80  (RAM), dn_SegList = BPTR to board window, dn_GlobalVec = −1
HOSTFS0 dn_Task:
  at  5.0s emulated (before CLI startup-sequence): 0x00000000  (handler not started)
  at  9.258s                                       0x0020611C  (handler started)
Write at 9.258s: PC in KS ROM, CurrentTask = 'Initial CLI'  → deferred/DeviceProc path
dp_Arg3 (last write before 9.258s, via last_writer): $0000FFFF → $00000000 from BCPL dispatch prologue
dp_Type (starthandler's send): 0x00000000  (ACTION_STARTUP = 0)
dp_Arg2 (FileSysStartupMsg BPTR): 0x003A9E00  ✓
dp_Arg3 at moment of handler reply: 0x00000000  (NULL)
eb_MountList at 9.258s: BootNode for HOSTFS0 still present (pri=−128, bn_Flags=0x0001)
```

Conclusions confirmed: (1) `dn_Task = 0` before the Initial CLI ran any startup-sequence command →
dos init does not start handlers. (2) `dp_Arg3 = NULL` via `last_writer` on the field → the BCPL
dispatch (global 112) never writes a DeviceNode BPTR there. (3) The write to `dn_Task` came from ROM
code in the Initial CLI context → `starthandler` writes `dn_Task` (before the handler process gets
its first scheduled instruction, under Forbid during the CreateProc/PutMsg sequence).

## 9.3 Who triggers the first HOSTFS0 start — CCP probe, full WB 1.3.3 ADF (2026-11-10) **[S]**

Same Copperline configuration as §9.2, but with the **unmodified Workbench 1.3.3 ADF**
(`build/copperline-ppaint/wb133-official.adf`, original `s/startup-sequence`). The dn_Task watchpoint
was armed from cold start. The board's AddDosNode calls were also logged via breakpoints.

```
AddDosNode calls logged before dn_Task write:
  t=2.88s  AddDosNode(pri=0,  flags=0, dn=board) task='exec.library'  → before-dos path
  t=3.92s  AddDosNode(pri=0,  flags=0, dn=board) task='exec.library'  → before-dos path
  (no AddDosNode with ADNF_STARTPROC in CLI context observed)
dn_Task write:
  t=9.44s  CurrentTask='Initial CLI'  cli_Module=0 (no external cmd)  Workbench task: absent
Handler process entry (0xEA0008):
  t=9.48s  CurrentTask='HOSTFS0'  (0.04s after dn_Task write)
```

**Conclusions**:
- The two before-dos AddDosNode calls (exec.library context, t=2.88s, t=3.92s) are the board's
  `rt_Init` during romboot — both before dos; no ADNF_STARTPROC after-dos call was observed.
- The handler was started by the **deferred DeviceProc path** (access watchpoint only fired at the
  *write* to `dn_Task`, not at any prior *read*; see §8 note).
- The Workbench task **does not exist** at the moment `dn_Task` is written. The handler is started
  while the **Initial CLI** is running and no external command is loaded, before the Workbench
  task is ever scheduled. The exact cause is **open** (see §9.4).
- Workbench therefore **sees the volume as already mounted** (dn_Task ≠ 0) when it first scans the
  DosList, and shows the icon without triggering a handler start itself. This confirms
  `workbench-task-v34.md` §3.3 is correct: Workbench only displays devices that are already live.
- The dn_Task write happens under Forbid (before the handler process gets its first instruction
  0.04s later), consistent with starthandler writing dn_Task under Forbid as part of the
  CreateProc+Permit+PutMsg sequence (the handler process runs and calls WaitPort before PutMsg).

## 9.4 dp_Arg1, device-sweep check, and trigger identification (2026-11-10) **[S]**

Additional probes on the same real KS 1.3 + WB 1.3.3 configuration. Three experiments:

**Startup packet dp_Arg1:**

```
dp_Arg1: BPTR that points into the Kickstart ROM image — a constant 1-character BSTR ('S'),
         not related to "HOSTFS0" or any device name.  Garbage for the handler.
dp_Arg2: dn_Startup = FileSysStartupMsg BPTR  (the only reliable field)
dp_Arg3: NULL (0)   (confirmed again)
```

dp_Arg1 is **not a device name**: it is a residue from the BCPL calling convention — a pointer
into the ROM that happened to hold a constant BSTR when the BCPL dispatcher saved the function
arguments into the packet. Its content ('S') is not related to "HOSTFS0" or the deviceproc
argument. **A V34 handler must not interpret dp_Arg1 and must use dp_Arg2 (FileSysStartupMsg)
to locate its unit. [S]**

**Device-sweep check:**

Write watchpoints were placed on the dn_Task of **all 7 DLT_DEVICE nodes with dn_Task = 0**
at the time of the trigger (PRT, PAR, SER, RAW, CON, RAM, HOSTFS0):

| Device | dn_Task written at first trigger (~9.4s) | Later start |
|---|---|---|
| HOSTFS0 | YES (Initial CLI context) | — |
| CON | No | Yes (~58s, Workbench opening its console) |
| RAW | No | Yes (~58s, Workbench) |
| SER | No | Yes (~58s, via Workbench/user) |
| PAR | No | Yes (~58s) |
| PRT | No | Yes (~58s) |
| RAM | No | Yes (~46s, first RAM: access) |

This confirms: the initial trigger is **not a sweep over all zero-task devices** but a targeted
DeviceProc call for HOSTFS0 specifically. CON, RAW, SER, PAR, PRT, RAM are started later on
their respective first accesses (RAM by user/Workbench at ~46s, the others by Workbench at ~58s).

The selection criterion that distinguishes HOSTFS0 from the other zero-task devices is **unknown
from this probe alone**. Possible candidates: HOSTFS0 has dn_Startup ≠ 0 (FileSysStartupMsg)
while RAM does not; HOSTFS0 has dn_SegList ≠ 0 while PRT/PAR/SER have dn_SegList = 0 (they
use a shared GV, not a loadable SegList). **[Uncertain]**

**Timing: LoadWB vs endcli vs neither:**

Three startup-sequence variants were run:
```
Variant A: echo * >SER: / LoadWB delay          → dn_Task written at t=9.23s
Variant B: echo * >SER: / endcli >NIL:          → dn_Task written at t=9.23s
Variant C: echo * >SER: / wait 60              → dn_Task written at t=9.25s (from §9.2)
```

All three fire at effectively the same emulated time (~9.2–9.4s), with CurrentTask = 'Initial
CLI' and no external command loaded. The trigger is therefore **independent of both
`LoadWB delay` and `endcli >NIL:`** and precedes both. It also cannot be `echo * >SER:`
itself: in the same boot, SER:'s handler is not started until ~58s (via Workbench), so the
SER: open at ~2s does not lead to HOSTFS0 being started at ~9.2s. The cause of the ~9.2s
start is **not established by these probes**: the CLI's command-name buffer was freed at that
time and the call chain was not traced. **[S — observation confirmed; cause open]**

- [x] No instruction sequence transcribed or paraphrased; no ROM routine address (only
  offsets of public/private structures, ABI constants and hardware ranges).
- [x] The probes cited are author code (`tests/`, header "ASSET DE TEST, PAS du code ROM").
- [x] §9 (2026-11-05): debugger observations of list contents and device calls; breakpoint addresses not
  given; emulator RAM addresses only.
- [x] §4.1 addition (2026-11-10): ROM disassembly observation that the chain walk does not read `bn_Flags`
  — no instruction sequence given, only the structural fact that offset `$0E` of the BootNode is not
  accessed in the loop.
- [x] §4.2–§4.4 addition (2026-11-10): expansion.library AddDosNode: BCPL dispatch mechanics described as
  observable ABI (function number 112, D1 = BPTR DeviceNode); no instruction sequences from the BCPL
  code body; no ROM addresses. §4.4 startup packet from §3.1 of handlers-v34.md (now itself corrected
  by probe).
- [x] §9.2 (2026-11-10): Copperline CCP probe — only RAM addresses from guest memory, no ROM content.
  dp_Arg3 observation via `last_writer` reports a write value and writing address in the guest address
  space; the PC of the last write (a ROM address) is not given in the spec.
- [x] §9.3 (2026-11-10): same probe constraints; timing figures, task names, and "absent Workbench
  task" are observable state, not ROM analysis.
- [x] §9.4 (2026-11-10): dp_Arg1 described as "points into the Kickstart ROM image, 1-char BSTR,
  garbage" — no ROM address cited, no instruction sequences. Device-sweep and timing tables from
  watchpoint/breakpoint stops; cause of ~9.2s trigger left open.
