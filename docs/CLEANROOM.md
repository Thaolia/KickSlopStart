# Clean-room discipline

## The principle

"Clean room" has a precise legal meaning: a **wall** separates whoever reads the copyrighted original from whoever
writes the replacement. The implementer must never have seen the original expression, so that the
result is not a derivative work. Disassembling the ROM *and* writing its code in the same flow
is the exact opposite: it is what we forbid ourselves here.

## The two tracks

### ANALYSIS track ("dirty")
- **Inputs**: the ROM `assets/kick34005.A500` (read-only), radare2 / Ghidra headless.
- **Outputs**: exclusively `docs/analysis/*.md`.
- **Allowed**: addresses, offsets, sizes and layout of structures (= ABI, interoperability),
  orders of operations, values of ABI constants, observable behaviours, test vectors.
- **Forbidden**: writing to `src/`; copying disassembled instruction sequences; producing
  implementation code.

### IMPLEMENTATION track ("clean")
- **Inputs**: public docs (RKRM, AutoDocs, NDK, `.fd`/SFD files = ABI contract), AROS source
  (`third_party/`, **read-only**), and the **behavioural** specs in `docs/analysis/`.
- **Outputs**: `src/`.
- **Forbidden**: reading the original ROM or its disassembly.

## Spec review gate

Before a spec from `docs/analysis/` is consumed by the implementation track, it is reviewed
to confirm that it **contains no instruction sequence transcribed** from the ROM. It is this
check that gives the wall its real value.

## Why public docs first

The `.fd` files and the AutoDocs/RKRM **already define** the API (names, LVOs, signatures) in a
legal way: they are the basis of the implementation. The ROM only serves to **resolve behavioural
ambiguities** that the public docs — which mostly describe 2.0/3.x — do not cover for
1.3. This delta (what V34 actually does vs what the 2.0 docs say) is captured *by the analysis
track in the specs*, since the implementation track cannot go and fetch it from the ROM.

## Licences

- **AROS** is under **APL v1.1** (per-file copyleft, non-OSI, GPL-incompatible): we **read** it, we
  do **not copy** its sources into `src/` → our licence stays free.
- **NDK / RKRM**: proprietary licences, **consulted**, **never redistributed** in the repository.
- The **Kickstart ROM** is proprietary: never committed, never modified.

## Honesty about the scope

Two agent roles in the same session *approach* the wall (the implementer does not see the original
expression) without amounting to a "court-grade" separation of people. For a maximal legal
posture, analysis and implementation should be entrusted to different people.
