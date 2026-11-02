# custom-chips-v34.md — How Kickstart 1.3 (34.5) uses Agnus, Denise and Paula

> ANALYSIS track ("dirty"). Cross-cutting map of every access the official ROM (`kick34005.A500`) makes to
> the OCS custom chip registers (`$DFF000`-`$DFF1FE`), attributed to modules and public entry points (LVOs,
> device commands). Behaviour and ABI only: no ROM address, no ROM offset, no instruction sequence. Register
> names, offsets and bit names are the public ones of the Hardware Reference Manual (HRM) and
> `hardware/custom.i`, `hardware/intbits.i`, `hardware/dmabits.i`, `hardware/adkbits.i`.
>
> Tags: **[M:s]** measured statically (Ghidra decompiler / disassembly), **[M:d]** measured dynamically
> (real ROM in Amiberry, register watchpoints), **[M:sd]** both, **[D]** deduced, **[HRM]** public hardware
> fact (not a measurement of the ROM).
>
> This page does not repeat what other specs already describe; it links to them:
> [coldstart-hardware-v34.md](coldstart-hardware-v34.md), [graphics-display-v34.md](graphics-display-v34.md),
> [graphics-blitter-v34.md](graphics-blitter-v34.md), [audio-device-v34.md](audio-device-v34.md),
> [trackdisk-official-timing.md](trackdisk-official-timing.md), [trackdisk-write-v34.md](trackdisk-write-v34.md),
> [alert-v34.md](alert-v34.md), [timer-v34.md](timer-v34.md), [keyboard-handshake-v34.md](keyboard-handshake-v34.md),
> [uae-int2-v34.md](uae-int2-v34.md), [graphics-area-v34.md](graphics-area-v34.md).

## 0. Short answer

- Thirteen modules touch the custom chips: exec, graphics, intuition, layers, audio.device, disk.resource,
  potgo.resource, gameport.device, trackdisk.device and strap do real register work; cia.resource,
  misc.resource and timer.device only use the inline DISABLE/ENABLE (INTENA). keyboard.device, input.device,
  console.device, keymap, expansion, ramlib, mathffp, romboot, dos and workbench.task make **no** custom
  register access. [M:s]
- Most accesses are the inline **DISABLE/ENABLE** sequence of `exec/ables.i` (INTENA `$4000` and
  IDNestCnt++, IDNestCnt-- then INTENA `$C000` if negative), present in ~50 places. [M:s]
- After boot, the display registers (BPLCONx, DIW/DDF, modulos, colours, sprite pointers) are written **by the
  copper only**; the CPU writes them only in the coldstart, the graphics init, `LoadView(NULL)` and
  `SetRGB4`/`LoadRGB4` with a NULL ViewPort. [M:sd]
- **Never touched** by the ROM: DENISEID, CLXCON/CLXDAT, JOYTEST, POT0DAT/POT1DAT, DSKSYNC, DSKBYTR, COPCON,
  COPJMP1/COPJMP2 (by the CPU), the STRxxx strobes, REFPTR, VHPOSW, SPRxDATA/DATB, BPLxPT (by the CPU),
  BLTCDAT, BLTDDAT. [M:sd] (§2.4)
- Interrupt acknowledge: exec acknowledges INTREQ **after** a server chain, with a single CLR write; vectors
  installed with `SetIntVector` acknowledge **themselves**, always **before** doing their work. [M:s] (§3.4)
- **V34 bug**: `RemIntServer` clears the wrong INTENA bit when a chain becomes empty (§3.1). [M:s]
- PAL/NTSC is decided by observing the beam in graphics; the Agnus identification bits of VPOSR and
  DENISEID are never examined. [M:s]

## 1. Method (reproducible)

**Static.** Ghidra 12 headless (GhidraMCP server dedicated to this ROM), raw 68000 big-endian image at base
`$FC0000`, full auto-analysis. Auto-analysis alone misses most code reached only through tables, so function
starts were added by hand from:
- the 24 ROMTag `rt_Init` pointers and the reset PC ([module-map.md](module-map.md));
- every library/device vector table, located by scanning the image for word-relative (with and without a
  leading `$FFFF`) and absolute-long tables whose entry counts match the public LVO counts of
  [coverage-v34.md](coverage-v34.md) §1 (exec 105, graphics 109, intuition 78, layers 29, expansion 25,
  mathffp 16, ramlib 11, timer 9, console 8, audio 6, cia 4, disk 5, potgo 3) and the device command tables
  of keyboard (14), gameport (14) and input (17);
- interrupt handlers found through the run-time `ExecBase->IntVects[]` contents (dynamic part below).

Then, for each function, every operand addressing the custom area was classified:
1. absolute long operands `$DFFxxx` (the ROM never uses a 16-bit absolute form for them);
2. register-relative operands whose base register was loaded with `$DFF000` (or with a register address, e.g.
   an audio channel base) earlier in the same function, with a simple linear register tracker (bases held in
   data registers and moved to address registers are followed);
3. inter-procedural propagation: when a call is made while a register holds the custom base, the callee is
   re-analysed with that register seeded (iterated to a fixpoint), plus the controller-type dispatch table of
   gameport, whose targets receive the base in A0;
4. interrupt code entered by exec with A0 = `$DFF000` (§3.3) was read by hand.

Effective-address computations of a register address (`LEA`/`PEA` of `$DFF1xx`) were kept apart: they never
access the chips, they produce the **register operand of copper MOVE instructions** (graphics builds and patches
copper lists that way). Each accessing function was mapped to public entry points by walking its callers up to
the vector tables (`.fd` names from amitools/NDK, truncated before the first V36 entry). The 223 absolute
custom references of the image were checked to be all covered.

**Dynamic.** Amiberry 8.4 (analysis sessions, default A500 PAL, 512 KB chip + 512 KB slow, not cycle-exact),
real ROM. Emulator memory watchpoints (the WinUAE GDB-server "memwatch" facility, driven in log-only mode
through IPC so that they survive a hard reset) on one or several registers at a time, with CPU-write (or
CPU-read) source only, then **hard reset** and polling of the hit ring every 0.15 s for 12-150 s. Each hit gives
the writing PC and the value; PCs were mapped to the functions above. Runs: reset → insert-disk screen (no
disk), and reset → Workbench 1.3.3 desktop (`Workbench 1.3.3 (34.34) - Boot` ADF). `ExecBase->IntVects[]` and
the server lists were read from emulated memory at both stages. Limit: the hit ring holds 64 events; INTENA
and INTREQ watches overflow (tens of thousands of DISABLE/ENABLE writes), so their dynamic lists show
the frequent writers and values but may miss rare writes; those come from the static analysis.

## 2. Per-chip tables

Columns: register (HRM name, public offset), access, who (module — public function or command), how. "init"
= the module's ROMTag initialisation.

### 2.1 Agnus (DMA, copper, blitter, beam, disk DMA pointer)

| Register | R/W | Who | How | Spec |
|---|---|---|---|---|
| DMACON `$096` | W | exec coldstart | `$7FFF` twice (all off, DMAEN included), then `$8200` (DMAEN only) at the end of the coldstart. [M:sd] | coldstart §1.2, §4.4 |
| | W | disk.resource init | `$8010` (SET DSKEN) — disk DMA stays enabled forever after. [M:sd] | — |
| | W | graphics init | `$0080` (copper off), `$8040` (BLTEN), `$81A0` (SET BPLEN, COPEN, SPREN). [M:sd] | graphics-display §2 |
| | W | audio.device init and CMD_RESET/ADCMD_FREE/STOP | `$000F` at init, then one CLR per channel (`$0001`…`$0008`), SET\|mask to start; never DMAEN. [M:sd] | audio §5, §8 |
| | W | intuition — `OpenIntuition`, screen display (OpenScreen/CloseScreen/MoveScreen/RemakeDisplay paths), `DisplayAlert` | `$0100` (BPLEN off) and `$0020` (SPREN off) when the display is torn down / the pointer hidden; `$8100`, `$8020` when a screen is shown. `DisplayAlert` writes `$0020` before its button loop. [M:sd] | alert §2 |
| | W | strap | `$0100` before drawing the insert-disk picture, `$8100` after. [M:sd] | — |
| DMACONR `$002` | R | graphics — `WaitBlit` and every blitter user (BltBitMap, BltTemplate, BltClear, BltPattern, SetRast, RectFill/AreaEnd/Flood, ReadPixel, WritePixel, DoCollision, QBlit handler…) | BBUSY (bit 14) read **twice** before looping. [M:sd] | blitter §2 |
| BLTCON0/1, BLTAFWM/ALWM, BLTxMOD, BLTxPT (long writes), BLTADAT, BLTBDAT, BLTSIZE `$040-$074` | W | graphics (blit engine, BltTemplate, BltClear, BltPattern, SetRast, area fill, Read/WritePixel, DoCollision, QBlit/QBSBlit users) | Order and values in the blitter spec. [M:s] | blitter, area |
| | W | layers — Create{Upfront,Behind}Layer, Upfront/BehindLayer, MoveLayer, SizeLayer, DeleteLayer, MoveLayerInFrontOf | **Direct** blits (D-only clear of a layer area, minterm 0, one plane at a time, and a variant combining a constant A word with source C), framed by graphics `OwnBlitter`, `WaitBlit` before each plane, `DisownBlitter` — all through the graphics LVOs. [M:s] | blitter §12 |
| COP1LC `$080` | W | graphics init | Once: copinit. [M:sd] | graphics-display §2 |
| COP2LC `$084` | W | graphics init; graphics VBlank server | Init value, then LOF/SHF list each vertical blank. [M:sd] | graphics-display §7.2 |
| COPJMP1/2 `$088/$08A` | — | — | Never strobed by the CPU (the copper restarts from COP1LC at each frame; copinit jumps to COP2LC by a copper MOVE to COPJMP2). [M:sd] | graphics-display §2 |
| COPCON `$02E` | — | — | Never written: CDANG stays 0 (copper cannot write `$040-$07E`, [HRM]). [M:s] | — |
| DIWSTRT/DIWSTOP/DDFSTRT/DDFSTOP `$08E-$094` | W | graphics init, `LoadView(NULL)` | `$2C81`/`$F4C1`/`$38`/`$D0` by the CPU; otherwise copper MOVEs built by MakeVPort/MrgCop. [M:sd] | graphics-display §2, §4 |
| VPOSR `$004` | R | graphics — `VBeamPos`, init (PAL and genlock detection), `LoadView` (LOF bit, short-frame wait), VBlank server (LOF in interlace), `QBSBlit` (beam position vs blit line) | Only the vertical position and bit 15 (LOF) are used; the Agnus ID bits (8-14) are never tested. [M:sd] | graphics-display §7.4, §8 |
| VHPOSR `$006` | R | graphics — init, `LoadView`, VBlank server | Beam line (read together with VPOSR as one long by VBeamPos). [M:sd] | graphics-display §7 |
| VPOSW `$02A` | W | graphics init, `LoadView(NULL)` | VPOSR \| `$8000` (forces a long frame; V8 is written back as read — observed `$8001`). [M:sd] | graphics-display §2 |
| DSKPT `$020` (long) | W | trackdisk | Per transfer. [M:s] | trackdisk-timing §3 |
| DSKLEN `$024` | W | disk.resource init; trackdisk | `$4000` (disarmed) at disk.resource init; trackdisk: disarm `$4000`, arm by **double write** (`$8000`\|words, observed `$9CBE` for a read), disarm. [M:sd] | trackdisk-timing §3 |
| SPRxPT `$120-$13E` | — | — | Never written by the CPU: copinit's copper MOVEs (installed by GetSprite/ChangeSprite) and VSprite copper lists. [M:sd] | §4.1 |
| REFPTR, VHPOSW, STREQU/STRVBL/STRHOR/STRLONG | — | — | Never. [M:s] | — |

### 2.2 Denise (bitplanes, sprites, colours, collisions)

| Register | R/W | Who | How | Spec |
|---|---|---|---|---|
| BPLCON0 `$100` | W | exec coldstart (and its error-colour routine) | `$0200` (colour on, 0 planes), BPL1DAT := 0. [M:sd] | coldstart §1.2, §8.6 |
| | W | graphics init | Genlock probe `$0102` (ERSY) then `$0000` when no external sync; then system_bplcon0 \| `$1200`. [M:sd] | graphics-display §2, §8.1 |
| | W | graphics `LoadView(NULL)` | system_bplcon0 \| `$1200`. [M:s] | graphics-display §7.1 |
| BPLCON1/2, BPL1MOD/BPL2MOD `$102-$10A` | W | graphics init, `LoadView(NULL)` | `0`, `$24`, `0`, `0`; otherwise copper. [M:s] | graphics-display §2 |
| BPL1DAT `$110` | W | exec coldstart | 0 (with BPLCON0 `$0200`). [M:s] | coldstart §1.2 |
| COLOR00 `$180` | W | exec coldstart | `$444` then `$888`; error routine `$CC0`/`$0C0`. [M:sd] | coldstart §8.6 |
| COLOR00/01 | W | graphics init | `$FFF`, `$FFF`. [M:sd] | graphics-display §2 |
| COLOR00-31 | W | graphics `SetRGB4(vp=NULL)`, `LoadRGB4(vp=NULL)` | Direct register write; with a ViewPort, only copper lists are patched. [M:s] | graphics-display §3 |
| SPRxPOS/SPRxCTL `$140+8n` | W | graphics init | Once, all 8 sprites parked (`$FE00`/`$FF00`, observed for sprite 0). [M:sd] | graphics-display §2 |
| SPRxDATA/DATB | — | — | Never (sprite DMA does it). [M:s] | — |
| CLXCON `$098` / CLXDAT `$00E` | — | — | Never written / never read, at boot and on the Workbench. GEL collisions are software (§4.1). [M:sd] | — |
| DENISEID `$07C` | — | — | Never read (it does not exist on OCS Denise anyway, [HRM]). [M:sd] | — |

### 2.3 Paula (interrupts, audio, disk, serial, pots, ADKCON)

| Register | R/W | Who | How | Spec |
|---|---|---|---|---|
| INTENA `$09A` | W | everyone using DISABLE/ENABLE (exec: Disable, Enable, AddTask, RemTask, FindTask, SetTaskPri, Signal, SetSignal/SetExcept, Wait, PutMsg/GetMsg/ReplyMsg, WaitIO, Cause, SetIntVector, AddIntServer, RemIntServer, Switch/Dispatch, Exception; cia, disk, misc, potgo, timer, trackdisk, audio, graphics) | `$4000` / `$C000` with IDNestCnt. [M:sd] | — |
| | W | exec coldstart | `$7FFF`; slow-RAM probe `$3FFF`/`$BFFF`/`$7FFF` into the register mirror; `$8004` (SOFTINT) after building the server chains; `$C000` at the end. [M:sd] | coldstart §3, §4.4 |
| | W | exec `AddIntServer` / `RemIntServer` | SET of the chain's bit at every add; CLR when the chain becomes empty (buggy, §3.1). [M:s] | §3.1 |
| | W | exec softint dispatcher | `$0004` (CLR SOFTINT) while processing the queues, `$8004` at the end. [M:s] | §3.3 |
| | W | exec Switch/Dispatch | `$C000`, then `$4000` again if the incoming task was switched out while disabled (its saved IDNestCnt ≥ 0). [M:sd] | exec-spec |
| | W | exec `Debug` (ROM-Wack) | Saves INTENAR, clears TBE\|RBF (`$0801`) for the session; the exit write has no SET bit, so TBE/RBF stay disabled (*corrected 2026-11-02, see `exec-scheduling-v34.md` §9*). [M:s] | §4.3 |
| | W | graphics `LoadView` | `$0020` (VERTB off) … `$8020`. [M:sd] | graphics-display §7.1 |
| | W | graphics `QBlit`/`QBSBlit`, BLIT handler | `$8040` (BLIT) when a queue starts (if INTENAR shows BLIT off); the BLIT handler writes `$0040` when both queues are empty. The beam-sync path also tests INTREQR VERTB. [M:s] | blitter §9 |
| | W | audio.device | Per-channel bits 7-10 SET/CLR. [M:s] | audio §5-§6 |
| | W | trackdisk | DSKBLK `$8002`/`$0002` around each transfer. [M:s] | trackdisk-timing §3 |
| | W | cia.resource `AbleICR`/`SetICR`/`AddICRVector`/`RemICRVector` | DISABLE/ENABLE only (CIA ICR handled in the CIA). [M:s] | timer §1 |
| INTENAR `$01C` | R | exec autovector handlers (levels 1-6) | First read of every interrupt (§3.3). [M:sd] | — |
| | R | exec coldstart (slow-RAM probe), `Debug`, graphics `QBlit` (BLIT enabled?), audio (channel bit enabled?) | [M:sd] | coldstart §3, audio §5.3 |
| INTREQ `$09C` | W | exec coldstart | `$7FFF`. [M:sd] | coldstart §1.2 |
| | W | exec server-chain dispatcher | Chain's mask, **after** the chain: `$0008` PORTS, `$0010` COPER, `$0020` VERTB, `$2000` EXTER; nothing for NMI. [M:sd] | §3.4 |
| | W | exec softint dispatcher; `Cause`; Reschedule (LVO −48) | `$0004` at entry and before each pass; `Cause` and Reschedule post `$8004`. [M:sd] | §3.3 |
| | W | exec `RawMayGetChar` (−510) | `$0800` (clear RBF) when a byte was read. [M:s] | §4.3 |
| | W | disk.resource interrupt code | `$0002` (DSKBLK) / `$1000` (DSKSYN), first thing. [M:s] | §3.4 |
| | W | graphics BLIT handler, `QBlit` | `$0040` before calling each queued blit routine. [M:s] | blitter §9.3 |
| | W | audio.device level-4 code | Per-channel acknowledge. [M:s] | audio §6 |
| | W | cia.resource `SetICR`/`AbleICR` | **Re-posts** the Paula request (`$8008` for CIA-A, `$A000` for CIA-B) when pending ICR bits become enabled. [M:s] | §3.4 |
| | W | trackdisk | Acknowledge DSKBLK around the transfer. [M:s] | trackdisk-timing §3.2 |
| INTREQR `$01E` | R | exec autovector handlers | ANDed with INTENAR (§3.3). [M:sd] | — |
| ADKCON `$09E` | W | audio.device CMD_RESET (and init) | CLR of the modulation bits of the channel and its predecessor: `$0011`, `$0033`, `$0066`, `$00CC` for channels 0-3; never SET. [M:sd] | audio §5.1 |
| | W | trackdisk | `$0600` (CLR WORDSYNC, MSBSYNC) then `$9100` (SET MFMPREC, FAST) before each read; precompensation bits when writing. [M:sd] | trackdisk-timing §3, trackdisk-write §3.1 |
| ADKCONR `$010` | — | — | Never read. [M:sd] | — |
| AUDxLC/LEN/PER/VOL/DAT `$0A0-$0DA` | W | audio.device | Through a per-channel base (`$DFF0A0` + 16·n). [M:s] | audio §8 |
| DSKSYNC `$07E`, DSKBYTR `$01A`, DSKDAT/DSKDATR | — | — | Never (trackdisk finds the sync in software). [M:sd] | trackdisk-timing §3.1 |
| SERPER `$032` | W | exec `RawIOInit` (−504), called by the coldstart, `Debug` and `Alert` | `$0174` (372), once at boot. [M:sd] | §4.3 |
| SERDAT `$030` | W | exec `RawPutChar` (−516) | Byte \| `$0100`. Never written during a normal boot (no serial output). [M:sd] | §4.3 |
| SERDATR `$018` | R | exec `RawPutChar`, `RawMayGetChar`, `Debug` | TBE (bit 13), RBF (bit 14), data. [M:s] | §4.3 |
| POTGO `$034` | W | potgo.resource `WritePotgo` (−18) only — called each vertical blank by gameport.device | `$0000` on the first vertical blanks (no pot bits allocated yet), then `$0F00` every frame once the port-0 controller is the mouse. [M:sd] | §4.2 |
| POTGOR `$016` | R | gameport.device (button reader); intuition `DisplayAlert` (right button) | DATLX/DATLY (port 0) or DATRX/DATRY (port 1). [M:sd] | §4.2 |
| JOY0DAT/JOY1DAT `$00A/$00C` | R | gameport.device — `GPD_SETCTYPE` (reference sample) and its VBlank server | JOY0DAT read every frame on the Workbench; JOY1DAT only if a unit-1 controller is set (never at boot). [M:sd] | §4.2 |
| POT0DAT/POT1DAT `$012/$014`, JOYTEST `$036` | — | — | Never (no proportional controller support in the ROM). [M:sd] | §4.2 |

### 2.4 Registers the ROM never touches (CPU)

DENISEID, CLXCON, CLXDAT, JOYTEST, POT0DAT, POT1DAT, ADKCONR, DSKSYNC, DSKBYTR, DSKDAT, DSKDATR, COPCON,
COPJMP1, COPJMP2, COPINS, STREQU, STRVBL, STRHOR, STRLONG, REFPTR, VHPOSW, BLTCDAT, BLTDDAT, SPRxPT,
SPRxDATA/DATB, BPLxPT, BPL2DAT-BPL6DAT. The low-word halves of the long pointers (BLTxPTL, DSKPTL, COPxLCL) are
written as part of 32-bit writes. Registers reached by copper MOVEs built by graphics (not CPU accesses):
BPLxPT, BPLCON0-2, BPLxMOD, DIW/DDF, COLORxx, SPRxPT, SPRxPOS/CTL (VSprites), COPJMP2. [M:sd]

## 3. Cross-cutting behaviour

### 3.1 Shared ownership of DMACON, INTENA, INTREQ, ADKCON

**DMACON** — every writer uses explicit SET/CLR masks touching only its own bits [M:s]:

| Bit(s) | Set by | Cleared by |
|---|---|---|
| DMAEN (9) | exec coldstart (`$8200`) | exec coldstart only (`$7FFF`) — never again |
| DSKEN (4) | disk.resource init | never after boot |
| BLTEN (6) | graphics init | never |
| COPEN (7) | graphics init | graphics init (before COP1LC is loaded) |
| BPLEN (8) | graphics init, intuition (screen shown), strap | intuition (display torn down, OpenIntuition), strap (while drawing) |
| SPREN (5) | graphics init, intuition (screen shown) | intuition (init, OpenIntuition, DisplayAlert) |
| AUD0-3 (0-3) | audio.device (start, one grouped SET) | audio.device (init, CMD_RESET, STOP, FREE, end of a non-cycling sound) |
| BLTPRI (10) | never | — |

Observed states [M:d]: DMACONR `$03D0` on the insert-disk screen (DMAEN, BPLEN, COPEN, BLTEN, DSKEN; sprites
off, no pointer), `$03F0` on the Workbench (SPREN added).

**INTENA** — exec owns the master bit through DISABLE/ENABLE; each module enables only its own source:

| Bit | Enabled by | Notes |
|---|---|---|
| INTEN (14) | exec (end of coldstart, ENABLE, Switch) | Cleared by DISABLE and by Switch for a disabled task |
| SOFTINT (2) | exec coldstart | CLR/SET by the softint dispatcher around queue processing |
| PORTS (3), EXTER (13), VERTB (5), COPER (4) | `AddIntServer` (each call) | ciaa/ciab resources and gameport/timer/graphics servers; COPER has no server at boot so stays off |
| VERTB (5) | also graphics `LoadView` (CLR … SET) | |
| BLIT (6) | graphics QBlit/QBSBlit | only while a blit queue is active |
| DSKBLK (1) | trackdisk | around each DMA transfer |
| AUD0-3 (7-10) | audio.device | per channel |
| TBE (0), RBF (11), DSKSYN (12) | never | `Debug` clears TBE/RBF; serial is polled |

Observed INTENAR [M:d]: `$602C` (INTEN, EXTER, VERTB, PORTS, SOFTINT) on the insert-disk screen and on the
Workbench desktop.

**`RemIntServer` bug** [M:s]: when the removed server was the last one of its chain, exec clears in INTENA the
bit numbered *(interrupt number × 12) modulo 32* instead of the interrupt number (the index scaled for the
`IntVects` array is reused for the bit). Effects for the five chains: PORTS (3) → bit 36 mod 32 = 4, so
**COPER is disabled instead of PORTS**; VERTB, COPER, EXTER, NMI → bit ≥ 16, so the word written is `$0000`
(**no effect**: the emptied chain's bit stays enabled). `AddIntServer` computes the bit correctly. A
reimplementation should implement the documented behaviour (clear the right bit); software relying on the
V34 effect is not known [D].

**INTREQ** — writes are acknowledgements (CLR) except the deliberate SET postings: `Cause` and Reschedule
(`$8004`), cia.resource re-posting PORTS/EXTER (§3.4). [M:s]

**ADKCON** — split between audio (bits 0-7, only cleared) and trackdisk (bits 8-14). Nobody touches UARTBRK
(11). [M:sd]

### 3.2 Chip initialisation order (cold boot to insert-disk) [M:d]

1. **exec coldstart**: INTENA/INTREQ/DMACON `$7FFF`, BPLCON0 `$0200`, BPL1DAT 0, COLOR00 `$444`; slow-RAM probe
   in the register mirror; COLOR00 `$888`, DMACON `$7FFF` and BPLCON0 again; `RawIOInit` (SERPER `$0174`);
   server chains built, INTENA `$8004`, DMACON `$8200`, INTENA `$C000`.
   ([coldstart-hardware-v34.md](coldstart-hardware-v34.md) §1-§4)
2. **disk.resource** (pri 70): DSKLEN `$4000`, DMACON `$8010`; installs its DSKBLK and DSKSYNC vectors.
3. **graphics** (pri 65): DMACON `$0080`, COP1LC, sprites parked, COP2LC, BLTEN, genlock probe (BPLCON0
   `$0102`/`$0000`), PAL/NTSC beam test, display registers, VPOSW, DMACON `$81A0`, COLOR00/01 `$FFF`; BLIT
   vector and VERTB server (pri 10).
4. **keyboard/gameport** (pri 60): gameport VERTB server (pri 0), which writes POTGO `$0000` while no controller is set.
5. **timer** (pri 50): VERTB server (pri 0, UNIT_VBLANK), CIA timers ([timer-v34.md](timer-v34.md)).
6. **audio** (pri 40): DMACON `$000F`, per-channel reset (DMACON CLR, ADKCON CLR), four level-4 vectors.
7. **input** (pri 40): opens gameport, sets the port-0 controller to mouse (JOY0DAT reference sample, POTGO
   `$0F00` every frame from then on).
8. **trackdisk** (pri 20): its unit tasks do the disk accesses later (ADKCON/DSKLEN per read, observed from the
   first boot-block read on).
9. **intuition** (pri 10): DMACON `$8100`/`$8020` then `$0020`.
10. **strap** (pri −60): DMACON `$0100`, draws the insert-disk picture, `$8100`.

Resulting vector map: §3.3.

### 3.3 Paula autovector dispatch (levels 1-7) [M:sd]

exec installs one handler per 68000 autovector. Levels 1-6 share one contract: save D0/D1/A0/A1/A5/A6,
A0 := `$DFF000`, A6 := ExecBase, read INTENAR; **if INTEN (bit 14) is clear, return (RTE) immediately without
any acknowledge**; otherwise D1 := INTENAR AND INTREQR and test, in a fixed order, the sources of the level.
The **first** pending-and-enabled source wins: its `IntVects[n]` entry is entered with A1 := `iv_Data`,
A5 := `iv_Code`, and the return address set to exec's interrupt exit (`ExitIntr`, LVO −36, which performs a
pending reschedule when returning to user mode with task switching allowed). Only one source is dispatched per
entry: another pending source of the same level re-interrupts at once. If none matches, plain RTE (no
acknowledge). Both early exits (INTEN clear, no matching source) restore the registers and RTE **directly, not
through `ExitIntr`**, so no schedule check is made on them (*Corrected 2026-11-02, see
`exec-scheduling-v34.md` §8*). Register contract at `iv_Code` entry: A0 = `$DFF000`, A1 = `iv_Data`, A5 =
`iv_Code`, A6 = ExecBase, D1 = INTENAR AND INTREQR (all levels' bits); the handler ends with RTS, may destroy
D0/D1/A0/A1/A5/A6 and must preserve D2-D7/A2-A4 (`exec-scheduling-v34.md` §8).

| Level | Sources tested, in this order | Vectors at boot (insert-disk and Workbench, identical) |
|---|---|---|
| 1 | TBE (0), DSKBLK (1), SOFTINT (2) | TBE: none (`iv_Code` 0); DSKBLK: disk.resource; SOFTINT: exec softint dispatcher |
| 2 | PORTS (3) | exec server chain: ciaa.resource (pri 0) |
| 3 | BLIT (6), VERTB (5), COPER (4) | BLIT: graphics (QBlit engine); VERTB chain: graphics (pri 10, unnamed), gameport.device (0), timer.device (0); COPER chain: empty |
| 4 | AUD1 (8), AUD3 (10), AUD0 (7), AUD2 (9) — **loops** | audio.device on all four |
| 5 | DSKSYN (12), RBF (11) | DSKSYN: disk.resource; RBF: none |
| 6 | INTEN (14), EXTER (13) | INTEN: none; EXTER chain: ciab.resource (pri 0) |
| 7 | — (NMI) | the `IntVects[15]` code is called directly as a subroutine, then RTE (no INTENAR/INTREQR read, no `ExitIntr`); NMI chain empty |

Level 4 is special: the return address of an audio handler is a re-check loop that re-reads INTENAR AND
INTREQR masked with the four audio bits (`$0780`) and dispatches again in the same order until none is pending,
then leaves through `ExitIntr`.

**Server chains.** For PORTS, VERTB, COPER, EXTER and NMI, the coldstart builds a 22-byte list header per
chain and installs exec's server dispatcher as `iv_Code` with the header as `iv_Data`. Layout [M:sd]: a
standard `List` (14 bytes), then the CLR mask word (`1 << n`), the SET mask word (`$8000 | 1 << n`), the
**acknowledge** word (PORTS `$0008`, VERTB `$0020`, COPER `$0010`, EXTER `$2000`, NMI `$0000`) and a spare word.
The dispatcher saves the acknowledge word, calls each server in list (priority) order with A1 := `is_Data`,
A5 := `is_Code`, **stops early when a server returns with Z clear**, then writes the saved word to
INTREQ (CLR form) — once, **after** the whole chain, and not at all for NMI. The stop test is the **Z flag** of
the condition codes on return, not an explicit test of D0 (a server returning D0 = 0 with Z clear stops the
chain). A0, A6 and D1 are not reloaded between servers: only the first server can rely on A0 = `$DFF000`,
A6 = ExecBase and D1 = pending mask (the ROM's own servers do not rely on A0); D0 at server entry is non-zero
garbage. The dispatcher walks the list with A2, so **a server must preserve A2** (and D2-D7/A3/A4). [M:s]
(*Corrected 2026-11-02, see `exec-scheduling-v34.md` §8: Z-flag test, A6/D1 not reloaded, A2 preserved.*)

**Software interrupts.** The SOFTINT vector code: acknowledges INTREQ `$0004`, then tests the "software
interrupt pending" SysFlags bit (bit 5 at ExecBase `$124`); if clear it returns (the SOFTINT was a reschedule
request, handled by `ExitIntr`). Otherwise INTENA `$0004` (SOFTINT off), then for the five `SoftInts` queues
(ExecBase `$1D2`, 16 bytes each, highest priority first) dequeue at IPL 7, mark the node, call it at IPL 0
(supervisor) with A1 := `is_Data`, A5 := `is_Code`, re-acknowledge INTREQ `$0004` before each re-scan; at the
end IPL 1 and INTENA `$8004`. `Cause(intr)`: under DISABLE, if the node is not already `NT_SOFTINT`, sets the
type, appends it to the queue chosen by `(ln_Pri & $F0)`, sets the pending bit and writes INTREQ `$8004`.
Reschedule (LVO −48): sets the reschedule bit (SysFlags bit 7); if task switching is allowed and interrupts
are enabled the switch is made at once (through the supervisor path) when the caller is in user mode, while a
caller already in supervisor mode (interrupt or Supervisor code) just returns and the switch is made by
`ExitIntr` (*corrected 2026-11-02, see `exec-scheduling-v34.md` §2.1*); if interrupts are disabled INTREQ
`$8004` is posted once (only when the bit was not already set), if task switching is forbidden only the flag
is set. [M:s]

**`SetIntVector(n, intr)`**: under DISABLE, copies `is_Data`/`is_Code` into `IntVects[n]` (`-1`/`-1` when
`intr` is NULL — so a NULL vector left enabled would jump to address `$FFFFFFFF`), stores the node, returns the
previous one; **INTENA is not touched**. Vectors never set keep `iv_Code` = 0. [M:s]

### 3.4 INTREQ acknowledge rules [M:s]

| Code | When it acknowledges | How |
|---|---|---|
| exec server dispatcher (PORTS, VERTB, COPER, EXTER) | after the full chain | one write of the chain mask, CLR |
| NMI chain | never | ack word 0 |
| exec softint dispatcher | at entry, then before each queue re-scan | `$0004` |
| disk.resource DSKBLK / DSKSYNC | **before** calling the unit owner's routine (no owner: Alert `AN_DRIntNoAct`, `$21000002`) | `$0002` / `$1000` |
| graphics BLIT handler and QBlit | before each queued routine | `$0040` (through A0) |
| audio level-4 code | in its per-channel automaton | channel bit |
| RawMayGetChar | after reading the byte | `$0800` |
| cia.resource server (on PORTS/EXTER chains) | does not touch INTREQ: reads (clears) the CIA ICR, merges into its pending shadow, dispatches enabled bits in order TA, TB, ALRM, SP, FLG; exec acknowledges after the chain | — |
| cia.resource `SetICR`/`AbleICR` | re-posts PORTS/EXTER by a SET write if enabled pending bits remain | `$8008` / `$A000` |

No acknowledge is ever written twice in a row by the same code; there is no "double write" rule for INTREQ (the
only double write in the ROM is DSKLEN). [M:s]

### 3.5 PAL/NTSC and Agnus detection

- Decided **only** in graphics init by watching the beam (VBeamPos above 270 ⇒ PAL), plus the genlock probe;
  results in GfxBase DisplayFlags/MaxDisplayRow and ExecBase VBlankFrequency
  ([graphics-display-v34.md](graphics-display-v34.md) §1.8, §8.1). [M:s]
- Nothing reads the Agnus ID field of VPOSR or DENISEID; no ECS register (BEAMCON0, DIWHIGH…) is written.
  timer.device calibrates the mains frequency separately ([timer-v34.md](timer-v34.md) §1.3). [M:s]
- What the standard changes: MaxDisplayRow/capping of copper WAITs and WaitBOVP, NormalDisplayRows, and the
  VBlank-based timing (VBlankFrequency, UNIT_VBLANK). SERPER is **not** adapted (same `$0174` in PAL and NTSC).
  [M:s]

### 3.6 Beam reading

- `VBeamPos` (−384): VPOSR:VHPOSR read as one 32-bit access, shifted and masked to 9 bits (V8 included).
  [M:s] ([graphics-display-v34.md](graphics-display-v34.md) §7.4)
- `WaitTOF` (−270): signal-based, woken by the graphics VBlank server; `WaitBOVP` (−402): busy loop on
  `VBeamPos`. [M:s] (same spec §7.4)
- `LoadView`: busy waits on VPOSR bit 15 (short frame) and on the line (≥ 10) when leaving interlace. [M:sd]
- `QBSBlit` compares the beam line with the requested line before starting or deferring a blit. [M:s]
  ([graphics-blitter-v34.md](graphics-blitter-v34.md) §9.4)
- The graphics VBlank server copies the line number into CIA-B TOD each frame (same spec §7.2).

## 4. Areas not specified elsewhere

### 4.1 Hardware sprites and GELs (graphics)

- **No CPU access to sprite registers after init.** graphics init parks the eight sprites by writing
  SPRxPOS/SPRxCTL directly (once) and copinit carries the eight SPRxPT copper MOVEs. [M:sd]
- `GetSprite(sprite, pick)` (−408): allocation in the GfxBase SpriteReserved bitmap (byte): `pick = -1` ⇒ first
  free sprite 0-7; else `pick & 7` if free; stores the number in `SimpleSprite.num`, returns it or −1. [M:s]
- `FreeSprite(pick)` (−414): clears the reserved bit. [M:s]
- `ChangeSprite(vp, s, newdata)` (−420): stores `newdata` as `posctldata`, then behaves as `MoveSprite` with the
  current x/y. [M:s]
- `MoveSprite(vp, s, x, y)` (−426): records the sprite in the GfxBase SimpleSprite table; if the sprite is the
  even half of an attached pair (attach bit of the odd sprite), moves the partner too; stores x/y; with a
  ViewPort, x is halved for HIRES and y for LACE; VSTART = ActiView DyOffset + y (+ vp DyOffset), clamped to a
  minimum of **21**; HSTART = ActiView DxOffset + x; VSTOP = VSTART + height. The two control words are written
  **into the sprite data in memory** (`posctldata`, first long) in the HRM encoding (POS: VSTART[7:0],
  HSTART[8:1]; CTL: VSTOP[7:0], VSTART8 → bit 2, VSTOP8 → bit 1, HSTART0 → bit 0, the old CTL bits 3-7
  — ATTACH included — preserved). Then, if there is no ViewPort, or the ViewPort is not hidden and y does not
  exceed its DHeight, the copinit SPRxPT MOVE of that sprite (and of its attached partner) is pointed at the
  data; otherwise it is pointed at the empty sprite (the sprite disappears). Sprite DMA picks the change up at
  the next frame. No direct register write. [M:s]
- **VSprites** (`DrawGList`, −114): the VSprite engine emits copper MOVEs to SPRxPT, SPRxPOS and the sprite
  colour registers into the ViewPort's sprite copper list (merged by `MrgCop`) [M:s]; it reuses hardware
  sprites by vertical band [D]. Details of the allocation are not covered here.
- **Collisions**: `DoCollision` (−108) is entirely software (GEL bounding boxes, then a blitter mask-overlap
  test, waiting on BBUSY); `SetCollision` (−144) only fills the GelsInfo collision table. **CLXCON is never
  written and CLXDAT never read** — at boot, on the Workbench, and in all static code. [M:sd]
- Bobs are drawn with the blitter through the same engine as BltBitMap ([graphics-blitter-v34.md](graphics-blitter-v34.md)).

### 4.2 Gameport, potgo, mouse path

**potgo.resource** (3 LVOs; base: ExecBase pointer, allocated-bits word, POTGO shadow word) [M:s]:
- `AllocPotBits(bits)` (−6): under DISABLE. Bits already allocated are refused; allocating a DATxx bit also
  reserves its OUTxx partner. START (bit 0) is refused if some pin is allocated as a pot input (DAT without OUT);
  if START is **already allocated** (by anyone), only complete DAT/OUT pairs are granted. Returns the granted
  bits. (*Corrected 2026-11-02, see resources-v34.md §3.2: the pair-only rule depends on START being already
  allocated, not on the caller obtaining it.*)
- `FreePotBits(bits)` (−12): clears the DAT bits and START given (a DAT bit frees its OUT partner too); **an OUT
  bit passed alone frees nothing** (*corrected 2026-11-02, see resources-v34.md §3.3*).
- `WritePotgo(word, mask)` (−18): under DISABLE, `POTGO := (shadow AND NOT mask) OR (word AND mask)`; the shadow
  keeps only the high byte (START is never remembered). No check against the allocated bits.

**gameport.device** [M:sd]:
- `GPD_SETCTYPE`: allocates the unit's four pot bits (`$0F00 << (4·unit)`, i.e. OUTLY/DATLY/OUTLX/DATLX for
  port 0) through `AllocPotBits`, frees them on change; for the mouse, takes a reference sample of
  JOYxDAT. input.device sets unit 0 to `GPCT_MOUSE` at boot; unit 1 is never configured by the ROM.
- **VERTB server** (pri 0, after graphics): for unit 0 then unit 1, if a controller is set, calls the
  type-specific reader with A0 = `$DFF000`, then calls `WritePotgo` with its shadow and allocated mask — hence
  POTGO `$0F00` **every frame** (observed). [M:sd]
- Reader, mouse: X/Y deltas = 8-bit differences of the JOYxDAT counter bytes against the previous sample
  (wrap-around handled by the byte arithmetic); joysticks (absolute/relative types): direction decoded from
  JOYxDAT bits 0/1/8/9 per the HRM formula through a small lookup table. Buttons: left/fire = CIA-A PRA bit 6
  (port 0) / bit 7 (port 1), active low; right = POTGOR DATLY (bit 10) / DATRY (bit 14); middle = DATLX
  (bit 8) / DATRX (bit 12), active low. Events are stored in the unit's ring and `GPD_READEVENT` requests
  are satisfied according to the trigger (`GPD_SETTRIGGER` timeout/deltas, key transitions).
- POT0DAT/POT1DAT and JOYTEST are never accessed; the START bit is never set in practice — no proportional
  joystick/paddle support in the 1.3 ROM. [M:sd]

**Mouse path**: VBlank → gameport server samples JOY0DAT and buttons → gameport event → `GPD_READEVENT` reply to
input.device's pending request → input event stream → intuition. input.device and intuition do **not** read
JOY0DAT themselves. intuition reads POTGOR directly in one place only: `DisplayAlert`, which waits for both
buttons released (left = CIA-A, right = POTGOR bit 10 low) then for a press, with a timeout counter
([alert-v34.md](alert-v34.md) §2.6). [M:s]

### 4.3 exec raw serial I/O and ROM-Wack

Private exec LVOs (`.fd`: RawIOInit/RawMayGetChar/RawPutChar) [M:s]:
- **`RawIOInit` (−504)**: SERPER := `$0174` (372) and nothing else (no ADKCON/UARTBRK, no INTENA). Baud =
  colour clock / (SERPER + 1) [HRM]: **9509 Bd on PAL** (3.546895 MHz), **9597 Bd on NTSC** (3.579545 MHz), 8
  data bits (LONG = 0). Called once by the coldstart (observed), and again by `Debug` and by the serial path of
  `Alert`.
- **`RawMayGetChar` (−510)**: if SERDATR RBF (bit 14) is set: INTREQ := `$0800`, return `SERDATR AND $7F`
  (**7-bit**); otherwise −1. Non-blocking.
- **`RawPutChar` (−516)**: busy-waits TBE (SERDATR bit 13), writes SERDAT := byte \| `$0100` (one stop bit).
  Then polls the receiver: a received **Ctrl-S** (`$13`) blocks output until any other byte arrives (XOFF/any);
  a received **DEL** (`$7F`) enters `Debug`. No LF→CR translation, no NUL filtering.
- **`Debug` (−114, ROM-Wack)**: saves INTENAR, clears TBE and RBF enables for the session, re-runs RawIOInit,
  then runs a polled serial monitor. On exit it writes the saved value back to INTENA, but that value is
  INTENAR masked to TBE/RBF and carries **no SET bit** (bit 15), so the write can only clear: TBE and RBF are
  **not** re-enabled and stay disabled after a Debug session (*corrected 2026-11-02, see
  `exec-scheduling-v34.md` §9*; the earlier wording "restores INTENA on exit" was imprecise). Serial interrupts
  are therefore never used by the ROM.
- During a normal boot the real ROM sends **nothing** on the serial port (SERDAT never written, [M:d]).

### 4.4 Background colour

- CPU writes to COLOR00: coldstart `$444`, `$888`, error colours `$CC0`/`$0C0`
  ([coldstart-hardware-v34.md](coldstart-hardware-v34.md) §8.6); graphics init `$FFF` (and COLOR01 `$FFF`);
  `SetRGB4`/`LoadRGB4` with a NULL ViewPort. Nothing else. [M:sd]
- From graphics init on, the visible COLOR00 comes from the copper: the first instruction of copinit is
  rewritten by LoadView/SetRGB4/LoadRGB4 to load the topmost ViewPort's colour 0
  ([graphics-display-v34.md](graphics-display-v34.md) §2). [M:s]
- Alerts: `DisplayAlert` builds its own display through graphics (ViewPort colours, copper lists) — **no direct
  COLOR write** in intuition. [M:s] ([alert-v34.md](alert-v34.md) §2.5)
- strap draws the insert-disk picture with BPLEN off and its own ViewPort colours (copper). [M:sd]

### 4.5 Disk registers

DSKPT, DSKLEN and ADKCON bits 8-14 are written only by trackdisk (plus the DSKLEN `$4000` of disk.resource
init); DSKSYNC and DSKBYTR are never accessed; DSKBLK/DSKSYN interrupts belong to disk.resource, which forwards
them to the current unit owner (trackdisk via `GetUnit`). All timing and values:
[trackdisk-official-timing.md](trackdisk-official-timing.md), [trackdisk-write-v34.md](trackdisk-write-v34.md).
[M:sd]

## 5. Real A500 risks (OCS, PAL/NTSC)

1. **Blitter BBUSY**: the ROM always reads DMACONR twice before trusting BBUSY (old Agnus may show BBUSY = 0
   right after BLTSIZE). A reimplementation must keep the dummy read. [M:s] [HRM]
2. **VPOSR/VHPOSR long read**: the 68000 splits the 32-bit read into VPOSR then VHPOSR; at the line where V8
   changes the pair can be inconsistent (V8 from before, H/V low from after). The ROM accepts this; callers
   comparing beam positions (WaitBOVP, QBSBlit) may be off by one frame-section on real hardware. [D]
3. **Spurious / unclaimed interrupts**: a level 1-6 handler that finds no enabled-and-pending source returns
   without acknowledging. On real hardware a request whose source keeps the line asserted re-enters forever
   (livelock). Enabling TBE, RBF, COPER or INTEN-in-INTREQ without installing a vector jumps through a NULL
   (`0`) or `-1` `iv_Code`. Writing INTREQ with bit 14 set raises a level-6 request that exec dispatches to the
   empty `IntVects[14]` (code 0) → crash. Same behaviour as the original; do not "fix" silently. [M:s][D]
4. **CIA lines are level-sensitive** [HRM]: exec acknowledges PORTS/EXTER after the chain, after the CIA ICR
   has been read. A CIA event arriving between the ICR read and the INTREQ write re-asserts /INT2 or /INT6, so
   Paula sets the bit again on real hardware and nothing is lost. An emulator that treats CIA interrupts as edges
   can lose that event (see the FS-UAE note in [timer-v34.md](timer-v34.md) and [uae-int2-v34.md](uae-int2-v34.md)). [D]
5. **INTREQ ack after the server chain**: a VERTB server that runs longer than a frame will have its next VERTB
   cleared by the late acknowledge (frame lost, not re-entered). Same on real hardware. [D]
6. **POTGO every frame**: gameport rewrites POTGO `$0F00` each VBlank (OUTLY/DATLY/OUTLX/DATLX, port 0 pins
   driven high through Paula's output drivers). Reading the right/middle button relies on the button pulling
   the pin low against this weak drive [HRM]. Software that drives port-0 pot pins differently is overridden at
   every frame unless it allocates the bits through potgo.resource (it cannot while gameport holds them). [M:sd][D]
7. **Serial speed**: SERPER `$0174` is not adapted to the standard: 9509 Bd (PAL, −0.95 %) or 9597 Bd (NTSC,
   −0.03 %). Both are within UART tolerance for a 9600 Bd terminal; RawMayGetChar returns only 7 bits. [M:s][D]
8. **Copper danger**: COPCON is never written, so CDANG = 0 after reset — copper lists cannot program the
   blitter. A reimplementation must not depend on copper writes to `$040-$07E`. [M:s][HRM]
9. **No ECS register**: on an 8372A (ECS Agnus, late A500s) the ROM behaves as on OCS; BEAMCON0 keeps its reset
   value (PAL or NTSC by jumper), DIWHIGH is reset by DIWSTRT/DIWSTOP writes. DENISEID is not read, so an
   8373 ECS Denise is not detected either. [M:s][HRM]
10. **DMAEN never cleared after boot** and BLTPRI never set: the CPU always gets cycles back from a running blit.
    [M:s]
11. **`RemIntServer` INTENA bug** (§3.1): on real hardware removing the last PORTS server disables COPER, and
    removing the last VERTB server leaves VERTB enabled with an empty chain (acknowledged by exec every frame,
    harmless). [M:s][D]

## 6. Probes that would refine this page (described, not written)

- Interrupt priority probe: a program that sets two sources of the same level at once with INTREQ (e.g. BLIT
  and VERTB, or AUD0 and AUD1 under DISABLE), records the order in which the vectors run (counters in RAM), then
  prints them. Expected: §3.3 order.
- RemIntServer probe: add then remove a single PORTS server on a test chain (e.g. after saving the CIA-A
  server list), print INTENAR before/after. Expected on V34: COPER cleared, PORTS still set.
- Serial probe: send DEL and Ctrl-S at the real ROM during `RawPutChar` output (kprintf from a test program)
  to confirm the XOFF/DEL behaviour on hardware.

## Open points

- Exact VSprite band/allocation algorithm in `DrawGList` (only its register targets are mapped here).
- ~~The gameport START-bit path~~ resolved: no 1.3 command or controller type ever sets the flag
  ([gameport-v34.md](gameport-v34.md) §7.3).
- The dynamic INTENA/INTREQ lists may miss rare writers (watch ring overflow); rare writes rely on the static pass.

## Clean-room review

Review of 2026-11-02.

- [x] No 68000 instruction sequence transcribed or paraphrased line by line; no disassembly or decompiler
  excerpt. Behaviour is described as effects, orders of register writes and values.
- [x] No ROM routine or data address, no ROM offset. Addresses that appear are public custom-chip register
  offsets (`$DFFxxx`), public ExecBase field offsets (`IntVects` `$54`, `SysFlags` `$124`, `SoftInts` `$1D2`),
  public LVOs and command names, and the CIA-A port bits of the HRM.
- [x] Values cited (DMACON/INTENA/INTREQ/ADKCON masks, SERPER `$0174`, POTGO `$0F00`, DSKLEN `$4000`/`$9CBE`,
  BPLCON0, COLOR00) are register values observed on the bus or ABI-level constants, not ROM data tables.
  The joystick decode table is described by its public HRM formula only, not redrawn.
- [x] The private exec server-list header (22 bytes) is given as a layout (ABI-style), with no code.
- [x] Tools, scripts and raw outputs (Ghidra project, watch logs) stayed outside the repository (scratch area
  and `build/amiberry/analysis/`); nothing under `src/` or `tests/` was read or written.

## 7. Implementation gaps (clean side, from `src/`)

Written by the implementation track **after** the clean-room check above, by reading only this page and our
own `src/` (never the ROM). Each line compares the behaviour described in §2-§4 with what our code does today.
Ordered by expected impact on real software / a real A500.

### 7.0 Status (2026-11-02)

Items 1-4 are **done** (see §7.1 for what was changed), and so are the POTGO part of item 6 and the NTSC screen
height (2026-11-02, second pass):
- **POTGO**: gameport allocates `$0F00` (OUTLY|DATLY|OUTLX|DATLX) and its VBlank server calls `WritePotgo($0F00,
  $0F00)` after reading the mouse, every frame (watch on POTGO: ~50 writes of `$0F00` per second, all from the
  server). The middle button (POTGOR DATLX, active low) produces RAWMOUSE `$6A` / `$EA` (dev marker
  `GAMEPORT OK` now covers it). potgo.resource `WritePotgo` uses the inline DISABLE/ENABLE of `exec/ables.i`:
  the `Enable` LVO may reschedule, which is not allowed from the interrupt that now calls it.
- **NTSC screens**: `OpenScreen` with Height ≤ 0 takes GfxBase NormalDisplayRows (doubled with LACE,
  intuition-screens-v34 §2.2) and the Workbench screen is opened with Height −1: 640 × 200 on NTSC, 640 × 256 on
  PAL (checked under Amiberry: the whole Workbench is visible on NTSC). The pointer is bounded by the same
  height (low-RAM word `PTR_YLIM`, written by graphics init).

Done too (2026-11-02, third pass): gameport units 0/1 with every GPD_* command (gameport-v34), and the exec raw
serial I/O of item 7 (RawIOInit sets SERPER 372 and the coldstart calls it, RawMayGetChar 7 bits, RawPutChar waits
for TBE then honours Ctrl-S and calls Debug on DEL; Debug itself is still an empty LVO, no ROM-Wack).

Still open: the rest of §7.2 (item 5) and the boot serial markers of item 7; the boot picture (352 × 272 PAL overscan art) loses its bottom rows on
NTSC; `LoadView(NULL)` does not force a long frame through VPOSW; `gb_VBlank` holds the frame rate instead of being
a per-frame flag.

### 7.1 High (done)

- **Done 1**: `AddIntServer` SETs the chain's source in INTENA after the insertion, interrupts masked during the
  insertion; `RemIntServer` CLRs the source (the right bit) when the chain becomes empty. Dev-ROM proof:
  serial marker `INTSRV INTENA OK` (COPER chain: on after the add, off after the last remove).
- **Done 2**: `LoadView(NULL)` keeps the DMA on, points `gb_LOFlist`/COP2LC at the copinit's final WAIT (an empty
  list) and resets BPLCON0-2, the modulos and DIW/DDF by CPU; the VBlank server reloads COP2LC from `gb_LOFlist`
  even with no active View. Proof: Holiday Lemmings (FLT cracktro, which calls `LoadView(NULL)`) shows the same
  cracktro and the same game menu as before. The COPJMP1 strobe of a non-NULL `LoadView` is kept.
- **Done 3**: disk.resource init disarms DSKLEN and enables DSKEN (plus the master bit that the 1.3 coldstart
  sets) for good; trackdisk no longer clears DSKEN and only re-SETs it before arming (no master bit), and its read
  path clears ADKCON bits 8-14 only (it used to clear the audio bits 0-7 as well). Production ROM on the
  Workbench: DMACONR `$03F0`, INTENAR `$602C`, the values of §3.1. The trackdisk write probe gives the same
  results as before.
- **Done 4**: graphics init decides PAL/NTSC from the beam (§3.5) and fills DisplayFlags, MaxDisplayRow,
  NormalDisplayRows, NormalDPMX/Y and ExecBase VBlankFrequency with the values of graphics-display-v34 §1.8
  (MaxDisplayColumn `$1D1`, MicrosPerLine `$3F9D`, MinDisplayColumn `$30` for both). Checked under Amiberry: PAL
  50/4/311/256/`$4CA`/`$513`, NTSC 60/1/261/200/`$500`/`$44A`.

Original findings:

1. **`AddIntServer` never enables the INTENA bit** (`src/exec/interrupts.s`, `exec_AddIntServer`): §3.1 shows the
   official exec SETs the chain's bit at every add. Software that adds a COPER (or VERTB/PORTS/EXTER) server
   and relies on the OS to enable it gets no interrupt on our ROM. Fix: SET `1 << n` for the five chain numbers.
   `RemIntServer` (`src/exec/execmisc.s`) clears nothing: keep clearing nothing or clear the *right* bit when the
   chain empties; reproducing the V34 wrong-bit effect is not recommended (§3.1, no known dependent software).
2. **`LoadView(NULL)` stops copper, bitplane and sprite DMA** (`src/graphics/graphics_lib.s`, `.lv_null`): the
   official one leaves COPEN/BPLEN on and writes the system display registers by CPU (§2.1, §2.2: BPLCON0
   system | `$1200`, DIW/DDF, BPLCON1/2, modulos, VPOSW). A program that does `LoadView(NULL)` then only loads
   COP1LC (without touching DMACON) gets a black screen on our ROM. Our normal `LoadView` also strobes COPJMP1,
   which the official ROM never does (it lets the copper restart from COP1LC at the next frame).
3. **trackdisk toggles DSKEN (and sets DMAEN) around every transfer** (`src/exec/trackdisk.s`): officially
   disk.resource sets DSKEN once at init and it stays on forever (§3.1); disk DMA is armed by DSKLEN only.
   Programs that save/restore DMACON around their own disk code may restore a state our trackdisk does not
   expect. Low cost to align: DSKEN once in `src/exec/diskres.s`, DSKLEN-only arming in trackdisk.
4. **PAL is hard-coded** (`src/graphics/graphics_lib.s`: `gb_VBlank` 50, `DISPF_PAL`, `MaxDisplayRow` 312):
   §3.5 decides PAL/NTSC by watching the beam in graphics init (VBeamPos above 270). On an NTSC A500 our
   display, VBlankFrequency and UNIT_VBLANK timing are wrong. Fix: beam test at graphics init, never the Agnus
   ID bits.

### 7.2 Medium

5. **Paula autovector dispatch differs** (`src/exec/interrupts.s`):
   - level 3 order is VERTB, COPER, BLIT (official: BLIT, VERTB, COPER); level 4 serves AUD0..AUD3 ascending
     (official: AUD1, AUD3, AUD0, AUD2 with a re-check loop); we serve every pending source per entry where the
     official handler serves one and re-enters. Observable only through relative timing of same-level sources.
   - we acknowledge VERTB, PORTS and EXTER **before** the chain (PORTS/EXTER on purpose, for the emulator edge
     problem documented in `uae-int2-v34.md`); official: once **after** the chain (§3.4). Keep ours for
     PORTS/EXTER (harmless on hardware, the CIA line is level-sensitive), but note the difference for VERTB
     (a VERTB server that overruns a frame is re-entered on ours, skipped on the official ROM).
   - unclaimed sources of levels 1/4/5 are acknowledged by us, never by the official handler (§5.3): ours is
     safer; keep it.
   - no INTEN test at entry (official: RTE without acknowledge when INTEN is clear).
   - server chains use a bare 14-byte `List` as `iv_Data` (official: 22-byte header with CLR/SET/ack words,
     §3.3). Only software that reads past the `List` would notice.
   - `SetIntVector(n, NULL)` stores 0/0 (official: `-1`/`-1`); ours is safer since the dispatcher skips code 0.
6. **Mouse buttons / POTGO** (`src/exec/gameport.s`; POTGO and middle button **done**, see §7.0): we allocate and write POTGO `$0C00` (OUTLY|DATLY) **once**
   at init; official gameport writes `$0F00` (adds OUTLX|DATLX, the middle button) **every vertical blank**
   through `WritePotgo` (§4.2). A program that writes POTGO directly and exits leaves our right button broken
   until reboot; the middle button is never read. Unit 1 (JOY1DAT, joystick types) and `GPD_*` commands are
   not implemented (already listed in `coverage-v34.md` §6).

### 7.3 Low

7. **exec raw serial** (`src/exec/execmisc.s`, `src/exec/exec.i`): `RawIOInit` is a no-op and SERPER is 368
   (9613 Bd PAL) instead of 372 set by `RawIOInit` (§4.3); `RawMayGetChar` returns 8 bits (official: 7);
   `RawPutChar` has a bounded TBE wait and no Ctrl-S/DEL handling (no ROM-Wack). Our ROM also prints serial
   markers during boot where the official one sends nothing (dev harness; check what `make kick-prod` still
   emits).
8. **Already aligned** (no action): WaitBlit double DMACONR read; COPCON, CLXCON/CLXDAT, DENISEID, BLTPRI never
   touched; GEL collisions in software; sprite registers reached through copinit MOVEs only.
