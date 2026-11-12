# CPU and FPU handling in Kickstart 1.3 (exec 34.2) on 68010-68040 — behavioural spec

> **ANALYSIS** track. Drives `REMAINING-WORK.md` item C15. Black-box only: the real ROM was run under Amiberry
> 8.4.2 (`amiberry-session start --analysis`, A500 preset, 512 KB chip + 512 KB slow, cycle-exact flags forced by
> the script, Workbench 1.3.3 boot disk copy), and observed through **RAM reads** (IPC `READ_MEM`, gdb `x`),
> emulator **save states** (CPU and FPU register chunks decoded with the emulator's documented layout), gdb
> register stops and screenshots. No ROM code was read or disassembled; no ROM address appears here.
> Legend: **[S]** observed on the real ROM as above · **[D]** public documentation (1.3/2.0 NDK includes,
> 68000-family manuals) · **[I]** inferred from [S] + [D] · **[?]** uncertain, not settled.
>
> Emulator options used (after `--`): `-s cpu_model=68010|68020|68030|68040`, `-s fpu_model=68881|68882|68040`,
> `-s cpu_24bit_addressing=true` (68010/68020) or `false` (68030/68040). Amiberry accepted all of them.

---

## 1. `ExecBase->AttnFlags` (UWORD at `+$128`)

### 1.1 Observed values [S]

Read after boot (Workbench desktop, or the insert-disk screen for the no-disk runs). ExecBase was at `$C00276`
(slow RAM) in every configuration.

| CPU / FPU configuration | AttnFlags | Bits set |
|---|---:|---|
| 68000 | `$0000` | none |
| 68010 | `$0001` | 0 |
| 68020, no FPU | `$0003` | 0, 1 |
| 68020 + 68881 | `$0013` | 0, 1, 4 |
| 68020 + 68882 | `$0013` | 0, 1, 4 (bit 5 **not** set) |
| 68030, no FPU | `$0003` | 0, 1 (bit 2 **not** set) |
| 68030 + 68882 | `$0013` | 0, 1, 4 |
| 68040 (internal FPU) | `$0013` | 0, 1, 4 (bits 2, 3, 6 **not** set) |

- 1.3 knows exactly three bits: **68010** (bit 0), **68020** (bit 1), **68881** (bit 4). A 68030 or 68040 is
  reported as a 68020; any FPU (68881, 68882, or the 68040's internal one) is reported as a 68881. [S]
- Bit 0 is set together with bit 1 on every 68020+ (cumulative flags). [S]
- The high byte stays 0: no PAL/50 Hz bits in V34 (the runs were PAL). [S]
- `AttnResched` and the rest of ExecBase were not examined here.

### 1.2 Bit definitions in the public includes [D]

- 1.3 NDK `exec/execbase.i`/`.h`: `AFB_68010` = 0, `AFB_68020` = 1, `AFB_68881` = 4 (with their `AFF_` masks).
- Added later (2.0/V37 includes, **not** set by 1.3): `AFB_68030` = 2, `AFB_68040` = 3, `AFB_68882` = 5;
  `AFB_FPU40` = 6 is V39. Whether the 1.3 include files already *declared* bits 2/3/5 as reserved names is
  **[?]**; 1.3 never sets them in any case.
- Programs of the 1.3 era test bit 4 to decide whether to use FPU instructions (the 1.3 IEEE math libraries
  on the Workbench disk do so). A V34-compatible exec should therefore set bit 4 whenever **any** FPU answers,
  and keep 2/3/5/6 clear if strict 1.3 parity is the goal; setting them is a V37 behaviour that 1.3 programs
  ignore. [I]

## 2. Booting on 68030 and 68040

- **All eight configurations of §1.1 reach the Workbench 1.3.3 desktop** (screen title "Workbench release.",
  RAM DISK and Workbench1.3 icons, about 860 KB free) under Amiberry. No Guru, no hang. [S]
- **Caveat for the 68040** [I]: the emulator configuration had no data-cache emulation (`cpu_data_cache=false`)
  and the MMU off. On real hardware, the problems that 1.3 is known for on a 68040 (copyback data cache and
  self-modifying or freshly loaded code; FPU instructions that the 68040 does not implement in hardware, e.g.
  transcendental functions, which trap as line-F with no 68040.library to emulate them in 1.3) are therefore
  not reproduced here. See §5: 1.3 leaves the 68040 caches **disabled**, which removes the cache-coherency
  risk for code that runs under 1.3 alone.
- On the 68040 the ROM-to-desktop time was visibly longer than on the 68020/030 runs (cycle-exact settings,
  not measured precisely). [S]

## 3. FPU context across task switches

### 3.1 What is saved [S]

On a system with an FPU (AttnFlags bit 4), exec saves the FPU state of the outgoing task **on that task's user
stack, below the integer context** described in `exec-scheduling-v34.md` §2.4/§4. `tc_SPReg` then points at
the FPU part, and the integer context (PC, SR, D0-D7, A0-A6) follows it unchanged.

Observed layout, ascending from `tc_SPReg`:

**a) The task has never used the FPU (FSAVE gives a *null* frame)** — every waiting system task on the
68020+68881, 68020+68882 and 68040 runs:

| Offset | Size | Content |
|---:|---|---|
| `+0` | 4 | FSAVE null frame (first byte = version 0) |
| `+4` | … | integer context: PC long, SR word, D0-D7, A0-A6 (same layout as on a 68000) |

Without an FPU (68000/010/020/030 alone) the integer context starts directly at `tc_SPReg`, as on the A500.
The emulator writes the null frame as `$00000000` on a 68040 and as `$00180000` (68881) / `$00380000` (68882):
the size byte is an emulator quirk; real 6888x hardware writes `$00000000`. What identifies a null frame is the
**version byte 0**. [S][D]

**b) The task has used the FPU (non-null FSAVE frame)** — provoked by giving the running user-mode task an
FPU state with known FP0-FP7 and FPCR values (emulator save state edited, then reloaded; no code executed),
then catching the next write of that task's `tc_SPReg` with a gdb watchpoint:

| Offset | Size | Content |
|---:|---|---|
| `+0` | 2 | word `$FFFF` (flag: FPU registers follow) |
| `+2` | 12 | FPCR, FPSR, FPIAR (in that order, `FMOVEM.L` layout) |
| `+14` | 96 | FP0 … FP7, 12 bytes each, extended-precision memory format, FP0 first |
| `+110` | frame size | the FSAVE frame (68881 idle frame: 28 bytes, version `$1F`, size byte `$18`) |
| after it | … | integer context: PC, SR, D0-D7, A0-A6 |

The injected FP0-FP7 values and FPCR (`$00000030`) were found intact at those places. [S]

### 3.2 Restore and isolation

- The layout is self-describing: the first word is `$FFFF` when registers follow, otherwise it is the first word
  of an FSAVE frame whose version byte is 0 (null). A restore therefore reloads the registers only in the first
  case, then FRESTOREs the frame. [I]
- After the injected task was switched out and other tasks ran, the live FPU of the system showed the reset
  state again (FP registers cleared, FPCR/FPSR 0): restoring another task's null frame resets the FPU, so the
  injected values did **not** leak into tasks that never used the FPU. [S]
- The return of the saved values when the injected task itself is dispatched again was not captured. [?]
- Consequence for a reimplementation: **1.3 does preserve FP0-FP7/FPCR/FPSR/FPIAR per task**, saving the full
  register set only for tasks whose FSAVE frame is not null. No `tc_Flags` bit is involved (none is defined for
  this in V34 includes). [S][D]
- `exec-scheduling-v34.md` §2.4 calls this "an extra long (FPU state marker)"; that is the null-frame case (a)
  only. A task that used the FPU has a larger context (b); debuggers and stack checkers that assume PC at
  `tc_SPReg + 0` are wrong on FPU systems with 1.3 too. [S]

### 3.3 Probe to confirm the restore on real hardware (description only, not written)

Two tasks (or a task and the CLI process) loop forever: each loads a distinct constant into FP0-FP7 and a
distinct rounding mode into FPCR, calls `Delay(1)` or `Wait` on a timer signal to force a switch, then
compares all registers with its constants and counts mismatches in a RAM long. After a minute both counters
must be zero; a non-zero counter means FPU state leaked across the switch.

## 4. Exceptions on 68020/030/040

### 4.1 Observed Gurus [S]

Exceptions were provoked in the `input.device` task (user mode) by stopping it with a gdb register condition
(SR bit 13 clear) and moving its PC onto a data word already present in RAM (no code written):

| CPU | Word executed | Exception | Guru shown |
|---|---|---|---|
| 68020, no FPU | `$00FF` (illegal effective address) | illegal instruction (4) | `#00000004.<task>` |
| 68030, no FPU | `$FF3F` (line F, coprocessor id 7) | line F (11) | `#0000000B.<task>` |
| 68020 + 68881 | `$FF3F` | line F (11) | `#0000000B.<task>` |
| 68040 (FPU) | `$FF3F` | line F (11) | `#0000000B.<task>` |

- `<task>` is the address of the faulting task, as on the 68000 (`coldstart-hardware-v34.md` §8.1); `$100`
  holds the vector number and `$104` the task address during the display. "Software Failure. Press left mouse
  button to continue." is displayed normally on all CPUs: the larger 68020+ stack frames do not disturb the
  default trap path. [S]
- A line-F word whose coprocessor id is not 1 traps as line F even when an FPU is present; that is CPU
  behaviour, not ROM behaviour. [D]

### 4.2 Not observed

- Divide by zero (5), CHK (6), TRAPV (7): not provoked (it needs an instruction that is not present as data).
  The exception vectors 5, 6 and 7 each point at their own ROM entry, like 4 and 11 above, so the expected
  result is `#00000005`, `#00000006`, `#00000007` with the task address. [I]
- Address error on 68020+: the gdb server refused an odd PC; not provoked. [?]
- An FPU instruction on a system **with** an FPU executes normally (it is how §3.1 b arises); FPU arithmetic
  exceptions do not occur by default because the reset FPCR has all exception enables clear. [D]

### 4.3 Vector table left by the ROM [S]

Read in RAM after a boot without disk (no SetPatch), 68020 + 68881, VBR = 0:

- Vectors 2 to 47 all point into the ROM. Bus and address error share one entry; vectors 16 to 24
  (reserved, spurious) share one entry; every other vector from 4 to 15 and each TRAP (32-47) has its own
  entry; 25-31 are the autovectors.
- **Vectors 48 to 63 are zero** (FPU exceptions 48-54, MMU 55-57, reserved 58-63). An FPU exception enabled
  by a program, or a 68030 MMU configuration error, would therefore jump to address 0. SetPatch 1.38 fills
  exactly this range on exec ≤ 35 ("Exec 68881/68882 exceptions patched", `setpatch-138.md` §3.1). [S]
- Vectors 13 (coprocessor protocol violation) and 14 (format error) are installed. [S]

## 5. Caches, VBR and other control registers after boot [S]

Read from the emulator's CPU state (save state), on the insert-disk screen with no disk, and again on the
Workbench desktop:

| CPU | CACR | VBR | Notes |
|---|---:|---:|---|
| 68010 | — | `$0` | |
| 68020 | `$00000001` | `$0` | instruction cache **enabled** |
| 68030 (± 68882) | `$00000001` | `$0` | instruction cache enabled; data cache (bit 8) off; burst bits off; MMU TC 0 |
| 68040 | `$00000000` | `$0` | both caches off; TC, ITT0/1, DTT0/1 all 0 |

- The emulator's CPU reset leaves CACR = 0, so the value 1 is written during the ROM's boot (it is already there
  at the insert-disk screen, before any disk software runs). [S]
- On the 68040 the same value 1 has no meaning (only bits 15 and 31 exist), so the 68040 caches stay off. [I]
- CAAR = 0, MSP = 0, the CPU stays on the interrupt stack (M bit clear) on 68020/030. [S]
- No exec call to manage caches exists in V34 (`CacheClearU`/`CacheControl` are V37). [D]

## 6. Summary for C15

1. AttnFlags: bit 0 on 68010+, bits 0+1 on any 68020/030/040, bit 4 when an FPU is present (including the
   68040's). Never bits 2, 3, 5, 6 or the high byte.
2. CACR := 1 at boot on 68020+ (instruction cache on, data cache off; harmless no-op on the 68040). VBR 0.
3. On FPU systems, the task switch saves an FSAVE frame on the task stack below the integer context, plus
   `$FFFF` + FPCR/FPSR/FPIAR + FP0-FP7 when the frame is not null; restore mirrors it.
4. Unhandled exceptions give `#000000vv.<task>` on every CPU; vectors 48-63 are left zero.
5. The real 1.3 boots the Workbench 1.3.3 disk on 68010, 68020, 68030 and 68040 under Amiberry.
