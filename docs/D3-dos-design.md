# D3 — Design: dos.library packets / handler / process → "run a command"

> IMPLEMENTATION track ("clean"). Design validated (user, 2026-10-17) **approach 1**: faithful observable packet
> ABI, processes in C (no internal BCPL runtime) — like AROS `rom/dos` and 2.0.
> Inputs: `docs/analysis/dos-v34-spec.md` + `dos-boot-sequence.md` (analysis track, reviewed, no code),
> public docs (RKRM/NDK/`dos_lib.fd`), AROS `rom/dos` (read-only). **No ROM reading.**
> Target: dos opens/reads a file THROUGH a file-handler process via DOS packets, and loads+runs
> ONE executable from DF0: via dos. **NO** interactive shell, **NOT** the real bootblock→dos bootstrap.

## V34 constraints to respect (from the analysis spec)
- **No public `DoPkt`/`SendPkt`/`WaitPkt` in V34** → packet exchange done internally via exec `PutMsg`/`WaitPort`/
  `GetMsg` (helper `dos_sendpkt`). dos jump table = 37 LVOs (-6..-222).
- `Open()` mode = ACTION code (`MODE_OLDFILE 1005 = ACTION_FINDINPUT`; `READ='R'=82`; `END=1007`).
- `FileHandle` 44 bytes: `fh_Type`@0x08 = the handler's MsgPort (APTR, no `fh_Port`); `fh_Arg1`@0x24 = handler-side
  private file key. `DosPacket` 48 bytes, `StandardPacket` 68 bytes (`sp_Msg` 20 + `sp_Pkt` 48).
- V34 boundaries (do not overrun): `Process` → `pr_WindowPtr` (~188 bytes; `pr_MsgPort`@0x5C, `pr_SegList`@0x80,
  `pr_CurrentDir`@0x98, `pr_CLI`@0xAC); `RootNode` → `rn_FileHandlerSegment` (~32); `DosInfo` → `di_NetHand`
  (~20; `di_DevInfo`@0x04; device list under Forbid/Permit, no semaphores). `DeviceNode` 44 bytes
  (`dn_Next`@0, `dn_Task`@0x08 = handler port, `dn_SegList`@0x20, `dn_Name`@0x28 BSTR).
- **BPTR/APTR asymmetry**: `Open`→BPTR FileHandle (BADDR=×4 to dereference); `CreateProc`/`DeviceProc`→
  APTR MsgPort (NO BADDR; `Process = port − 92`). BSTR = BPTR→length-prefixed string.
- Packet cycle: fill `dp_Type`/`dp_Arg*` + **`dp_Port = &caller.pr_MsgPort`** (refilled on every send);
  `PutMsg` to the handler's port; `WaitPort`/`GetMsg` on the reply port; read `dp_Res1`/`dp_Res2`.

## Components (src/dos/, proven from the boot scaffold, serial markers, gated on disk d4)
1. **Process + CreateProc** (`process.s`): `Process` = exec `Task` + embedded `pr_MsgPort` @0x5C + V34 fields
   up to `pr_WindowPtr`. `CreateProc(name,pri,segList,stack)`: AllocMem(Process + stack), init Task
   (tc_SPLower/Upper/SPReg), init `pr_MsgPort` (AllocSignal for the SigBit, type NT_MSGPORT), `AddTask`
   with entry = process body, returns the **APTR** `&pr_MsgPort`.
2. **`dos_sendpkt`** (internal helper): sets up a `StandardPacket`, `dp_Port=&reply`, `PutMsg(handlerPort)`,
   `WaitPort(reply)`/`GetMsg`, returns `dp_Res1` (+ `dp_Res2` in pr_Result2/IoErr).
3. **DF0: file-handler** (`handler.s`): process body that loops `WaitPort`/`GetMsg` on its `pr_MsgPort`,
   serves `FINDINPUT`/`READ`/`END` via `ofs.s` (D1). Deliberate simplification: `FINDINPUT` reads the WHOLE file
   via `ofs_read_file` into a handler buffer, `fh_Arg1` → {buffer, size, pos}; `READ` copies buffer+pos;
   `END` frees. (Incremental OFS reads deferred.)
4. **User-facing dos** (`dos_lib.s`, extended M6d): `Open`(-30)/`Read`(-42)/`Close`(-36) build the packets
   (via `dos_sendpkt`), resolve DF0: through `di_DevInfo`→`dn_Task`, set `fh_Type`/`fh_Arg1`.
5. **Wiring**: extend the M6d init (`DosBase`/`RootNode`/`DosInfo`) to mount a DF0: `DeviceNode` whose
   `dn_Task` = the D3b handler's port.

## Open→Read→Close flow
`Open("kickslop",OLDFILE)` → resolves DF0: → allocates FileHandle (4-aligned), `fh_Type=dn_Task` → packet
`FINDINPUT(ARG1=BPTR(FileHandle), ARG2=0 lock, ARG3=BSTR name)` → handler opens (key → `fh_Arg1`), `dp_Res1=
DOSTRUE` → returns BPTR(FileHandle). `Read(fh,buf,len)` → `READ(fh_Arg1,buf,len)` → bytes in `dp_Res1`
(0=EOF, -1=err). `Close(fh)` → `END(fh_Arg1)` → frees FileHandle.

## Breakdown (each GREEN/RED/NODISK/COOP, committed)
- **D3a** — Process + CreateProc + packet round-trip. Trivial "echo" handler + client (boot task + temporary reply
  port) sends a packet, receives the reply. Marker `D3A`. RED: reply not returned → absent.
- **D3b** — DF0: file-handler process serving FINDINPUT/READ/END via ofs.s. Direct sending of packets → reads back
  "KickSlop" (1024 bytes, markers @0/488/976). Marker `D3B`. RED: READ not served → wrong bytes → absent.
- **D3c** — dos `Open`/`Read`/`Close` (LVO) via packets + mounted DF0: DeviceNode; **called from a client
  process** (CreateProc'd, because dos requires ThisTask=Process for `pr_MsgPort`). Marker `D3C`. RED: `Open` does
  not set `fh_Type` → routing fails → absent.
- **D3d** — `LoadSeg` rewired through dos `Open`/`Read` (handler/packets) + run "D2Test". Marker =
  "D2LOADSEG OK" emitted by the command loaded through the full packet path. RED: path broken → absent.

## Robustness / errors
`FINDINPUT` name failure → `DOSFALSE` → `Open`→0. Validate fields/bounds (see D1/D2). The handler always replies
(a mute handler would block `WaitPort` — tolerated, like the real dos which blocks on packets). Inherited anti-hang
guards. Processes in user mode on a shared SSP (M7c); `WaitPort` = synchronous switch (M3d) — already proven.

## Out of scope (deferred, deliberate)
Real bootblock→dos bootstrap (manual init `rt_Flags=0`, DeviceNode mounting from ROM templates, Initial CLI,
`CON:`, startup-sequence, disk-validator, intuition requesters); interactive shell/prompt; incremental OFS
reads; `Write`/`Lock`/`Examine`/`Seek` beyond what is needed; faithful `ACTION_STARTUP` (we start
our handler our own way). → CLI milestones + real boot integration.

## Fidelity deviation (noted)
`dos.library` remains a resident initialised in our bringup (M6d, AUTOINIT) and not the manual-init-driven-by-
bootblock of the real V34 (`rt_Flags=0`). D3 proves the packet/handler/Open/Read/LoadSeg-run MACHINERY; the faithful
bootstrap + CLI come later.
