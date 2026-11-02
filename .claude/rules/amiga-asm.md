---
description: 68000 assembly rules for the clean-room Kickstart — ABI, exec/DOS/BCPL conventions, hardware traps
globs: ["src/**/*.s", "src/**/*.i", "tests/**/*.s"]
---

# Assembly rules — clean-room Kickstart 1.3

> Scoped to the assembly sources. General rules (strict 68000, vasm syntax, no dead code, comments only for the WHY)
> live in `CLAUDE.md`; nothing here may be taken from the ROM disassembly.

## Registers and stack

- In every LVO entry point, preserve d2-d7/a2-a6: real callers (icon.library, CIA dispatch loops) rely on it.
- Take arguments in the exact registers of the `.fd` (FreeEntry takes its list in A0, not A1). A wrong register
  corrupts the allocator far from the faulty code.
- After any edit, check that matching `movem` push/pop lists are identical; one register off ends in a
  SOFTWARE FAILURE much later.
- `move.l (sp)+,Dn` changes the Z flag: restore with `movem` when a flag must survive the pop.
- Keep stack adjustments even (`lea -(255+4)(sp)` gives an odd SP, so an address error on 68000).
- With `link aN,#-N`, locals sit at **negative** offsets from aN.
- No `bsr`/`jsr` before RAM and the stack exist at coldstart: inline everything up to that point.

## vasm specifics

- Use an explicit `bra.w` in fixed-size stubs and jump tables; `bsr.s` to the next instruction (displacement 0)
  assembles as `.w`.
- Fix every error 2029 (`.s` branch out of ±127 range) in one pass; the build otherwise leaves a truncated image.
- `and.w An,Dn` and other address-register ALU forms do not exist on 68000: the assembler is the syntax check.

## Libraries, jump tables, hunks

- LVO = `-6*(slot+1)` with the 30-byte bias; check each slot against the `.fd`/AROS `.conf`.
- Keep a canary vector near the end of a jump table (e.g. DateStamp in dos): if it stops answering, the table slid
  by one slot (typically an off-by-one `dcb.l`).
- Mask hunk ids with `$3FFFFFFF` before comparing: bits 30/31 carry CHIP/FAST memory flags, honour them when
  allocating.
- Allocate system structures that never feed DMA with MEMF_PUBLIC: games need large contiguous chip RAM blocks.
- Do not place ExecBase or the supervisor stack at the top of chip RAM; keep ExecBase in LibList.
- Do not consume TRAP vectors in the OS: programs hook them directly.

## DOS and BCPL

- Packets and BSTRs passed as BPTR must be longword-aligned; round a BSTR built on the stack.
- A handler answers with returnpkt: PutMsg to `dp_Port`, then set `dp_Port` to the handler's port. Never ReplyMsg
  to `mn_ReplyPort`, and never write into the packet beyond the result fields.
- Calling BCPL from assembly: A0 = 0, A4 = exact routine address; `getlong/putlong(i,base)` address `base+4*i`.
- A fault at `$474C0001+2n` means BCPL global n is undefined.
- A BCPL command launcher allocates one longword more than the size announced at 4(sp).

## Interrupts and hardware

- Acknowledge INTREQ **before** walking the server chain, or an event raised during service is lost.
- The preemptive exit of an interrupt must honour Forbid/Disable nesting; voluntary yields (Wait, Permit) still run.
- No fast periodic interrupt source left running at boot; arm CIA timers one-shot.
- Around the trackdisk seek step pulses only, Disable when a timer of the same CIA can interrupt.
- Any copper list shown at boot goes through COP1LC; keep a copinit that jumps to COP2LC for programs that only
  write COP2LC.
- Write POTGO through potgo.resource, or the right/middle button reads as held.
- Restore every register a boot self-test touched (CIA latches, DMACON) to its power-up value.
- Clear the low-RAM variables at coldstart: only FS-UAE starts with zeroed RAM.
- Drawing calls preserve RastPort state (pens, draw mode) and the registers the 1.3 call leaves intact.
