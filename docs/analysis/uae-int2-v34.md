# uae-int2-v34.md — UAE board interrupt (PORTS, level 2) and UAE DiagPoint

> ANALYSIS track ("dirty"). Sources: black-box probes on the real ROM `kick34005.A500` under FS-UAE 3.2.35
> (`tests/intports.s`, `tests/bootlist.s`); FS-UAE console debugger on the real ROM **and** on our ROM
> (`prod.rom` of 26/10, black box: hardware registers and memory, no reading of `src/`); GPL source code
> of FS-UAE 3.2.35 (`src/filesys.cpp`, `src/filesys.asm`, `src/custom.cpp`, `src/newcpu.cpp`,
> `src/native2amiga.cpp`, `src/autoconf.cpp`, `src/expansion.cpp` — software independent of the ROM).
> We describe the **what**; no instruction sequence transcribed, no routine address of the original ROM.
>
> Legend: **[S]** probe/debugger · **[U]** FS-UAE source · **[D]** public documentation (RKRM).
> Prerequisites: `autoconfig-v34.md` §6 (DiagPoint call), `uae-hd-boot-v34.md` (romboot, BootPoint).

---

## 0. Short answer

**The UAE board does NOT raise an interrupt during boot.** On our hung ROM, the UAE indicator
`$F0FFEB` is 0 (no request was ever issued) and level 2 is fed by **CIA-A timer A**,
which our ROM runs at that moment **in continuous mode with a latch of `$00FF`** (256 E cycles, i.e.
≈ 361 µs ≈ 2,560 CPU cycles) **with the TA interrupt enabled** (ICR mask `$03`). **[S]**

What the board adds is **one more PORTS server** ("UAE filesystem", pri 20, placed **in front of** that
of ciaa.resource) which the DiagPoint installs itself. This server does nothing as long as UAE has requested nothing, but
it lengthens every pass through the PORTS chain. With TA at 361 µs, this is enough for a new
TA interrupt to arrive before processing has finished: level 2 is raised again immediately and the main code never
regains control (the code that would stop TA is therefore never executed). Proof by intervention in the
debugger on the hung machine (§4): **stopping TA** ⇒ boot resumes; **removing the UAE server from the
chain** ⇒ resumes; **lengthening the TA period ×16** (latch `$0FFF`) ⇒ resumes; touching nothing ⇒ still
hung. **[S]**

On the real 1.3, **CIA-A TA is never started during boot** (CRA `$00`, latch `$FFFF`, ICR mask
`$0A` = TB + SP): level 2 only sees rare events (keyboard, MICROHZ on demand), and the UAE server
costs nothing. **[S]**

**What our ROM must do** (§5): not leave a high-frequency CIA-A source with its interrupt
enabled during resident init (or at any time: the real 1.3 has none); secondarily, keep the
level 2 / PORTS chain path short and resilient to additional servers. **Our DiagPoint
call is compliant**: the ROMTag, `uae.resource` and the two UAE servers are in place on our ROM as on
the real one (§3, §4).

---

## 1. UAE side: the "uae_int" source **[U]**

- FS-UAE keeps an emulator variable `uae_int_requested`. **As long as its low byte is non-zero, the emulator
  re-asserts INTREQ PORTS (`$8008`) on every line (hsync) and in the CPU loop**: it is a **level**
  source, not a pulse. (Its `$FF00` byte drives EXTER/level 6 for other boards, irrelevant here.)
- Bit 0 is set by UAE's "native → Amiga" functions (Signal, PutMsg, ReplyMsg, Cause, file
  notification): replies to file handler packets, signal of the mounting task, clipboard
  sharing, hardfiles. **None of these sources exists before the init of `uaehf.device`** (romboot) and
  mounting: nothing sets the bit during autoconfig/DiagPoint.
- Each time the bit is set, UAE also copies the state of bit 0 into byte **`$F0FFEB`** of its "rtarea"
  (`$F00000–$F0FFFF`). This byte is **never reset to zero afterwards**: it is an "at least one request
  was issued" indicator usable by a probe or debugger (real ROM after boot: `01`; our hung ROM: `00`).
- **Acknowledgement on the 68k side**: only by the "UAE filesystem" PORTS interrupt server (§2.3). This
  server calls an emulator trap (code in the rtarea, at `$F0xxxx`) which, if bit 0 is set and no
  other UAE processing is in progress, **clears the bit** and answers "this is for me"; the server then pops the
  pending actions (PutMsg/Signal/ReplyMsg/Cause…) then releases the lock and returns Z = 0. Otherwise it returns Z = 1
  (D0 = 0) without doing anything. No read/write of a register of the `$E90000` board acknowledges anything;
  clearing INTREQ by the CPU is not enough as long as the UAE bit stays set (it is set again on the next line).
- Consequence: if some day UAE requests an interrupt while the "UAE filesystem" server is not in the
  PORTS chain (or is never called), the machine hangs at level 2 for good. This is **not** the case
  observed here (indicator at 0).

---

## 2. UAE board DiagPoint: contract **[U; S]**

### 2.1 Expected inputs

The board's DiagArea (`er_InitDiagVec = $2000`) has `da_Config = $90` (DAC_WORDWIDE | DAC_CONFIGTIME),
`da_Flags = 0`, **`da_Size = $0200`**, `da_DiagPoint = $01E0`, `da_BootPoint = $01E6`, name at +14 (`"UAE"`).
At `+$1E0` as at `+$1E6` there is an **absolute jump into the rtarea**: the code executed next is not
relocated, it works on the **copy** designated by A2.

| Register | Use by UAE |
|---|---|
| **A2** | address of the **RAM copy** of the DiagArea. UAE **writes** into it (ROMTags + code, §2.2): the copy must be in writable RAM and be at least `da_Size` = 512 bytes. |
| **A3** | ConfigDev of the board: stored by UAE (it reuses it as the `ln_Name` of the BootNodes and logs it: `filesystem: diagentry <A2+$10> configdev <A3>`). |
| **A5** | ExpansionBase: only tested (≠ 0 = normal path; 0 = UAE's "KS 1.2" path) and used for the "hide autoconfig" option. Must be non-zero. |
| **A6** | ExecBase: used as is for InitResident, AllocMem and AddIntServer (not re-read from `4.w`). |
| A0 | ignored (overwritten). |

Return: **D0 = 1**; D0/D1/A0/A1 are destroyed, the other registers are returned intact.

### 2.2 What it does, in order

1. Writes at **copy+$10** the ROMTag `uaehf.device` ("UAE hardfile.device 0.4"): flags `$81`
   (RTF_COLDSTART | RTF_AUTOINIT), version 50, NT_DEVICE, pri 5, `rt_EndSkip` = copy+$2A; name, idstring and
   init table in rtarea. **It does not initialise it** (romboot does, `uae-hd-boot-v34.md` §2.1).
2. Writes at **copy+$2A** a second ROMTag **`uae.resource`** ("UAE resource 3.3.0"): flags `$81`, version 1,
   **NT_RESOURCE**, pri 120 (other ROMTags may follow depending on UAE options: bsdsocket, uaescsi,
   uaenet, uaeserial… — none in the test config).
3. Writes after that, in the copy, a small piece of code which is **executed immediately**:
   - **`InitResident(tag, 0)` for each ROMTag after the first** (here `uae.resource` ⇒ MakeLibrary +
     **AddResource** during expansion's init; on the real 1.3 it is the **first** entry of
     ResourceList, before potgo.resource);
   - installation of the UAE servers (§2.3);
   - return D0 = 1.

### 2.3 The two servers installed during the DiagPoint

| Node (AllocMem PUBLIC\|CLEAR) | Vector | Pri | `is_Data` / `is_Code` | Behaviour |
|---|---|---|---|---|
| **"UAE filesystem"**, 26 bytes, NT_INTERRUPT | **INTB_PORTS (3)** via **AddIntServer** | **20** | both in the rtarea | §1: Z = 1 as long as UAE has requested nothing; Z = 0 after serving a request. Preserves A2; destroys D0/D1/A0/A1 and A6 (reloaded with ExecBase from `4.w`). |
| **"UAE heart beat"**, 22 bytes, NT_INTERRUPT | **INTB_VERTB (5)** via **AddIntServer** | **−10** | `is_Data` = a long in the rtarea, `is_Code` in rtarea | increments the long pointed to by A1 (= `is_Data`) and returns Z = 1 (the chain continues). UAE uses it to know that the OS is running. |

Plus, depending on the config: a "mousehack" test (emulator trap) which may create a mouse integration task
(inactive in the test config: no corresponding task). The InitCode patch for the clipboard
is only applied if exec ≥ 37: nothing on 1.3.

Resulting requirements for exec/expansion **at DiagPoint time** (before all residents of
priority < 110): AllocMem operational; **PORTS and VERTB server lists already initialised** and
AddIntServer functional (the addition must survive the later init of ciaa.resource, gameport, timer…);
InitResident of an AUTOINIT **NT_RESOURCE** ROMTag functional (AddResource).

Allocation order observed on the real ROM (slow RAM, increasing addresses): ConfigDev `$C01620` →
`uae.resource` `$C0166E` → "UAE filesystem" node `$C016A0` → "UAE heart beat" node `$C016C0` →
`potgo.resource` `$C016EA` (resident pri 100) → … → ciaa.resource node `$C017AA`. The UAE servers therefore exist
**from the DiagPoint on**, well before ciaa.resource (pri 80) and romboot (pri −40). **[S]**

---

## 3. Real 1.3 ROM: interrupt state **[S]**

- **PORTS chain** after boot: "UAE filesystem" (pri 20) **then** ciaa.resource (pri 0). **VERTB**:
  graphics server (pri 10), gameport.device (0), timer.device (0), "UAE heart beat" (−10). **EXTER**:
  ciab.resource (0).
- The chain stops at the first server that returns Z = 0 (1.x server behaviour, RKRM **[D]**): the UAE
  server only returns Z = 0 when it has actually served a UAE request.
- **CIA-A during and after boot** (debugger at 5 s and at 25 s): CRA `$00` (TA stopped, never loaded:
  latch `$FFFF`), CRB `$08` (TB one-shot, latch `$02CB` = MICROHZ), ICR mask **`$0A`** (TB + SP). INTENA
  `$602C` (INTEN, EXTER, VERTB, PORTS, SOFTINT).
- After booting from DH0:, `$F0FFEB` = 1 (UAE has already issued requests: mounting, packets), and the system
  runs: the uae_int source is acknowledged by the UAE server as expected.
- Between the DiagPoint and the init of `uaehf.device` by romboot, the uae_int source has **no reason** to be active
  (§1); in any case the UAE server has been in the PORTS chain since the DiagPoint (§2.3). 1.3 therefore never
  hangs, whether the source is active or not. (Not observed instant by instant on the real ROM: the debugger
  only arrives after several seconds; deduced from the allocation addresses + UAE source + indicator at 0 on our
  ROM.)

---

## 4. Our hung ROM: black-box observations **[S]**

Config: A500, chip 512 KB, slow 512 KB, fast 2 MB, `hard_drive_0 = <dir>`, blank ADF; debugger at 25 s
(white screen, boot frozen).

- `INTENA $402C` (INTEN, VERTB, PORTS, SOFTINT; EXTER not yet enabled), `INTREQ $1009`/`$1029` (PORTS
  pending), IPL 2 or 3, CPU in supervisor mode, mask 2 or 3, in the walk of the PORTS chain.
- **CIA-A: CRA `$01` (TA started, continuous mode), TA latch `$00FF`, ICR mask `$03` (TA + TB)**, ICR read as 0
  (already acknowledged by the server, then re-armed at each underflow).
- `$F0FFEB = $00`: **UAE never requested an interrupt**. `$F0FFEC` (long) = `$00E92000` (address of the
  board's DiagArea, set by UAE at configuration).
- ExecBase's PORTS chain: "UAE filesystem" (pri 20, `is_Code` at `$F00300`) → a pri 10 server → a pri 0
  server. The "UAE heart beat" VERTB server is present too. **The DiagPoint therefore executed correctly
  on our ROM.**
- Interventions in the debugger, then resume with a memory write breakpoint on SERDAT (`$DFF030`, our
  ROM writes to serial as soon as it makes progress), 20 s wait:

| Intervention | Result |
|---|---|
| none | **no** SERDAT write: still hung |
| CRA ← `$00` and TA mask removed (ICR ← `$7F`) | SERDAT write, CPU mask 0: **boot resumes** |
| "UAE filesystem" node removed from the PORTS chain (TA unchanged) | **resumes** |
| TA latch ← `$0FFF` (period ×16, ≈ 5.8 ms), UAE server left in place | **resumes** |

- Without `hard_drive_0` (same ROM, 25 s, normal boot): CIA-A CRA `$00`, mask `$0A`, TA latch `$00FF`
  — so TA was used during boot and then stopped by the main code; without the UAE server, the
  processing of each TA interrupt fits (just barely) within the 361 µs.

Conclusion: the cost of a level-2 pass (entry, acknowledgement, walk of the PORTS chain with 3 servers,
including ciaa.resource's dispatch) exceeds the TA period as soon as the UAE server is added; INTREQ PORTS is
set again by CIA-A before the return, hence a perpetual level 2.

---

## 5. What our ROM must do

1. **Remove the continuous CIA-A TA source at `$00FF` with its interrupt enabled** during boot. The real
   1.3 does not start CIA-A's TA (ICR mask `$0A` = TB + SP only). If a delay is needed,
   use one-shot mode, a long period, or a wait without interrupts.
2. More generally, no periodic interrupt source should have a period of the order of the cost of
   processing it: any driver or board can add servers to any chain (UAE adds one to PORTS
   at pri 20 and one to VERTB at pri −10 from the DiagPoint on).
3. Keep what is already compliant (verified §4): DiagPoint call with A2 = writable RAM copy of
   ≥ `da_Size` bytes, A3 = ConfigDev, A5 = ExpansionBase, A6 = ExecBase; PORTS/VERTB server lists
   initialised before expansion; AddIntServer and InitResident(NT_RESOURCE) usable at that point.
4. Server chain: stop at the first server that returns Z = 0 (1.x), otherwise full walk; acknowledging
   INTREQ before the walk is correct (a level source such as uae_int or an unread CIA-A reasserts itself).

---

## 6. Test vectors

Real ROM 34.5, FS-UAE 3.2.35, `slow_memory = 512`, `fast_memory = 2048`, `hard_drive_0 = <dir>` (startup:
`intports >SER:`), blank ADF ⇒ DH0: boot. Format of `tests/intports.s`: `IE intenar intreqr $F0FFEB` (read
under Disable, hence INTEN absent); `SV vector node type<<8|pri is_Data is_Code name`; `RT addr
flags.ver.type.pri name idstring`; `RS addr name`.

```
=== R1 : real ROM, after DH0: boot
IE 0000282C 00000041 00000001
SV 00000003 00C016A0 00000214 00F00300 00F00300 UAE filesystem
SV 00000003 00C017AA 00000200 00C01780 …        ciaa.resource
SV 00000005 00C02140 0000000A 00C020F6 …                      (graphics)
SV 00000005 00C0258C 00000200 00C0245C … gameport.device
SV 00000005 00C02688 00000200 00C0265E … timer.device
SV 00000005 00C016C0 000002F6 00F0FFFC 00F00408 UAE heart beat
SV 0000000D 00C01D22 00000200 00C01CF8 … ciab.resource
RT 00C01AF0 81320305 uaehf.device UAE hardfile.device 0.4
RT 00C01B0A 81010878 uae.resource UAE resource 3.3.0
RS 00C0166E uae.resource     (1st in ResourceList)
RS 00C016EA potgo.resource / 00C01718 keymap / 00C01780 ciaa / 00C01CF8 ciab / 00C01D96 disk /
   00C01E34 misc / 00C04DB8 FileSystem.resource (created by uaehf at romboot init)
Log: "filesystem: diagentry 00c01af0 configdev 00c01620" then "Mounting uaehf.device 0".
=== R2 : real ROM, debugger at 5 s and at 25 s
A: CRA 00 CRB 08 IM 0a TA ffff (ffff) TB 02cb (02cb)     INTENA 602c
=== N1 : our ROM + hard_drive_0, hung (debugger at 25 s)
A: CRA 01 CRB 08 ICR 00 IM 03 TA 0028 (00ff)             INTENA 402c  INTREQ 1009  IPL 2
$F0FFE0 : 0000 0000 0000 0000 0000 0000 00E9 2000         ($F0FFEB = 00)
PORTS chain: UAE filesystem (pri 20) → pri 10 → pri 0
=== N2 : interventions (then "w 0 dff030 2 w", g, 20 s)
none: no break; CRA←00 + ICR←7F: break SERDAT, IMASK 0;
UAE removed from the chain: break SERDAT; TA latch ←0FFF: break SERDAT
=== N3 : our ROM without hard_drive_0, 25 s
A: CRA 00 CRB 08 IM 0a TA 00fd (00ff)                    INTENA 602c
```

Proposed non-regression for our ROM: N1 must boot up to the CLI; `intports` must then show
"UAE filesystem" pri 20 at the head of PORTS, "UAE heart beat" pri −10 in VERTB, `uae.resource` in
ResourceList, `$F0FFEB = 1`; and CIA-A at rest must have TA stopped (as in R2).

---

## 7. Not probed / uncertain

- Instantaneous state of the real ROM **between** DiagPoint and romboot (INTENA, INTREQ): not observed directly (no
  reset controllable from the FS-UAE debugger); deduced from the allocation order and the UAE source.
- Exact cost, in cycles, of a level-2 pass on our ROM: not measured; only the crossing of the threshold
  (≈ 2,560 CPU cycles for a latch of `$00FF`) is established by the interventions.
- FS-UAE mouse integration / clipboard option enabled: would add a task and uae_int requests
  after boot, still served by the same PORTS server; not tested.
- On the real 1.3, AddIntServer enables the vector's INTENA bit: not verified in isolation (final INTENA consistent).

---

## Clean-room review

- [x] No instruction sequence of the ROM transcribed or paraphrased; no routine address of the original
  ROM (only observed data/allocation addresses, hardware registers and addresses of the
  emulator area `$F0xxxx`).
- [x] The UAE code (GPL, independent of the ROM) is described by its behaviour, without copying.
- [x] Observations of our ROM are black box (hardware registers, memory), without reading `src/`.
- [x] The probe cited is author code (`tests/intports.s`, header "ASSET DE TEST, PAS du code ROM").
