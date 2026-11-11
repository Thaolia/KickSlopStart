# mathffp.library 34.1 — Motorola fast floating point: behavioural spec

> **ANALYSIS** track ("dirty"), `coverage-v34.md` §7 rank 15. Source: **black-box calls on the real ROM**
> `assets/kick34005.A500` under Amiberry (A500 preset, cycle-exact, 512 KB chip + 512 KB slow, no disk), 2026-11-05.
> Method: the ROM was left at its "insert disk" picture; the debugger stopped a task at the entry of exec `Wait`
> (user mode, found through the public `Wait` vector), raised the interrupt mask to 7 in SR, wrote a two-instruction
> call stub in unused low memory ("call through A4, then branch back to the call"), and, for each test, loaded D0/D1
> with the operands, D2–D7/A0–A3/A5 with markers, A6 with the library base (taken from the exec library list), A4
> with the address of the library vector (base − LVO), then let the CPU run the stub once and stop after the return.
> D0, every other register, SR and a pattern-filled area below the stack pointer were read back. **4,554 calls**
> were observed (155 SPFix, 46 SPFlt, 899 SPCmp, 54 SPTst, 54 SPAbs, 54 SPNeg, 728 SPAdd, 728 SPSub, 817 SPMul,
> 735 SPDiv, 142 SPFloor, 142 SPCeil), plus the library vectors Open/Close/Expunge/Null. Calls that took a CPU
> exception were caught with the debugger's exception stop and the session was then discarded. The exact
> arithmetic rules of §4 are **models fitted to these outputs** and checked against every observed vector
> (counts given with each rule); they describe results, not the ROM's code. The ROM code was **not** read,
> disassembled or traced for this page; no program was written; the probe to write on the implementation side is
> described in §8. This document contains no ROM instruction sequence, no pseudo-code of a ROM routine and no ROM
> address.
> Related pages: `module-map.md` (resident, AUTOINIT table, 16 vectors), `workbench-task-v34.md` §2.2/§8.3 (the
> Workbench opens mathffp and computes its scroll bars with it), `dos-memory-v34.md` §1.2 and `ramlib-v34.md` §6
> (mathffp is expunged under memory pressure), `exec-messages-io-v34.md` (ln_Type of the base).
>
> **Levels of proof**: **[O]** observed on the real ROM · **[D]** deduced from observations (reasoning, stated) ·
> **[S]** assumption, not verified · **[Doc]** public documentation (AutoDocs 3.1 text of the 1.3 functions,
> `mathffp_lib.fd`, AROS `mathffp.conf`).
>
> Notation: FFP values are written as 32-bit hex `$MMMMMMSE` (M = mantissa, S/E = sign and exponent byte) followed
> by their decimal value. "Low byte" = bits 7–0 (sign + exponent). "ulp" = one unit of the last mantissa bit at the
> exponent in question. Condition codes are shown as the set of **N, Z, V** that are set ("–" = none); X and C are
> not part of the contract (§3.3). Test ids (X3, D14, …) refer to §7.

## 0. Summary for the implementer

- **Library** (§1): ROM resident `mathffp.library`, version **34**, revision **1**, ID string
  `mathffp 34.1 (18 Aug 1987)` + CR LF; in the exec library list from boot with **open count 0**; base = a bare
  `struct Library` (PosSize 34, NegSize 96 = 16 vectors), `lib_Flags` = `$04` (LIBF_SUMUSED). Open counts, Close
  returns 0, Expunge removes it only when the open count is 0. **No function needs A6** (all twelve gave the same
  results with A6 = 0). [O]
- **Format** (§2): bits 31–8 mantissa (normalised: bit 31 set), bit 7 sign, bits 6–0 exponent excess 64; value =
  mantissa / 2^24 × 2^(exponent − 64). Zero is `$00000000`. Range 2.71e−20 … 9.22e18. [Doc + O]
- **The ROM treats a value as zero when its low byte is zero** (positive sign and exponent 0), whatever the mantissa
  field holds — in SPTst, SPFix, SPAbs/SPNeg, SPAdd/SPSub/SPMul and SPDiv's divisor (SPCmp has its own order). `$00000080`
  ("−0") is **not** zero for any function. [O]
- **Registers** (§3): arguments in D0 (and D1); result in **D0**; condition codes N/Z/V meaningful. SPTst reads its
  argument from **D1**. SPFix, SPFlt, SPCmp, SPTst, SPFloor, SPCeil change **D1**; SPAbs, SPNeg, SPAdd, SPSub,
  SPMul, SPDiv leave D1 intact; all other registers (D2–D7, A0–A6) are preserved by every function. Stack: at most
  32 bytes below the caller's SP, return address included. [O]
- **Two-operand order**: D1 = first fd argument, D0 = second. **SPSub returns D0 − D1, SPDiv returns D0 / D1**;
  **SPCmp returns +1 when D1 > D0**, −1 when D1 < D0, and sets the codes as for "D0 compared with D1" (signed
  branches only). [O, matches the fd and the AutoDoc text]
- **Rounding** (§4): SPFlt and SPMul round to nearest, **ties away from zero**; SPDiv rounds to nearest (no tie is
  possible with normalised operands); **SPAdd/SPSub round before normalising** (see the exact rule, §4.7), ignore an
  operand whose exponent is 24 or more below the other's, and truncate on a carry-out; **SPFix truncates toward zero**;
  SPFloor/SPCeil are exact for normalised inputs. [O, fitted on every vector]
- **Overflow**: SPAdd/SPSub/SPMul/SPDiv return **`$FFFFFF7F` / `$FFFFFFFF` (±MAX)** (largest magnitude) with **V set**. SPMul
  overflows as soon as the **sum of the exponents is ≥ 192**, even when the product would fit (M11, M13, M14). SPDiv
  takes the **divisor's sign** when the overflow only comes from the mantissa step (V12). SPFix saturates to
  `$7FFFFFFF` (V) or `$80000000` (**Z and V set, N clear**). [O]
- **Underflow**: result `$00000000` with Z, no V. A result whose exponent lands exactly on 0 is returned as is when
  negative (low byte `$80`) and as `$00000000` when positive (§4.8, §4.9). [O]
- **Division by zero** (divisor low byte 0, or mantissa field 0): the 68000 **zero-divide exception** is taken inside SPDiv; in a task
  this is a "Software Failure" Guru `#00000005.<task>`. No result is returned. A divisor `$00000080` gives −MAX with
  V instead. [O]

## 1. Library and base [O]

| Item | Observed |
|---|---|
| Name / type | `mathffp.library`, `ln_Type` 9 (NT_LIBRARY), `ln_Pri` 0 |
| Version / revision | 34 / 1 |
| `lib_IdString` | `mathffp 34.1 (18 Aug 1987)` followed by CR LF |
| `lib_NegSize` / `lib_PosSize` | 96 (16 vectors × 6) / 34 (`sizeof(struct Library)`: no private data) |
| `lib_Flags` at rest | `$04` (LIBF_SUMUSED) |
| `lib_OpenCnt` after boot | 0 (no ROM module keeps it open; the Workbench opens it later, `workbench-task-v34.md` §2.2) |
| Presence | in the exec library list from cold start (resident pri 0, AUTOINIT, `module-map.md`) |

Library vectors (Open and Close exercised through exec `OpenLibrary`/`CloseLibrary`; Expunge and Null called
directly through the base with A6 = base):

| LVO | Function | Observed behaviour |
|---:|---|---|
| −6 | Open | `OpenLibrary("mathffp.library", 0)` and `(…, 34)` return the base and increment the open count (0 → 1 → 2). `OpenLibrary(…, 35)` returns 0, count unchanged (exec's version check). |
| −12 | Close | decrements the open count, returns **D0 = 0**. With LIBF_DELEXP set and the count reaching 0, the library **stayed in the list** (no delayed expunge on close). |
| −18 | Expunge | open count 1: sets **LIBF_DELEXP** (`lib_Flags` `$04` → `$0C`), returns D0 = 0, library stays. Open count 0: the library is **removed from the library list**, D0 = 0 (no segment list). Its 130-byte block is freed (`dos-memory-v34.md` §1.2). |
| −24 | Null (reserved) | returns with **D0 unchanged** (a marker in D0 came back as is), no other register changed. |

Whether Open clears LIBF_DELEXP was not tested (open point 3).

## 2. Number format

### 2.1 Motorola FFP [Doc]

| Bits | Field |
|---|---|
| 31–8 | mantissa, 24 bits, unsigned magnitude; normalised numbers have bit 31 set |
| 7 | sign (1 = negative) |
| 6–0 | exponent, excess 64 |

Value = (mantissa / 2^24) × 2^(exponent − 64). Normalised magnitudes therefore lie in [2^(e−65), 2^(e−64)), from
`$80000000` (exponent 0: 2^−65 ≈ 2.71e−20) to `$FFFFFF7F` ((1 − 2^−24) × 2^63 ≈ 9.22e18). Examples: 1.0 =
`$80000041`, −1.0 = `$800000C1`, 0.5 = `$80000040`, 1.5 = `$C0000041`, 3.0 = `$C0000042`, 10.0 = `$A0000044`.
Zero results are `$00000000`, except where a non-canonical input passes through ("−0" + 0 = `$00000080`, D23; 2 × "−0" = `$00000081`, M8).

### 2.2 How the V34 functions classify an input [O]

| Input | Treated as |
|---|---|
| low byte `$00` (sign 0, exponent 0), any mantissa | **zero** by SPTst, SPAbs/SPNeg (flags and SPNeg's result), SPAdd, SPSub, SPMul, SPDiv's divisor (trap), SPFix (returned unchanged, §4.1). SPDiv's **dividend** is zero only when the whole long is 0 (V18). SPCmp has its own order (§4.3). |
| `$00000080` ("−0") | **not** zero: a negative number with exponent 0 and mantissa 0 (T2, C12, M8, V6) |
| exponent ≠ 0, mantissa field 0 (e.g. `$00000041`) | not zero (T7, C17), divisor of SPDiv traps (V8) |
| mantissa bit 31 clear, exponent ≠ 0 (unnormalised) | used as is; no function normalises it (C16, V20, F18, E18, X24, X25) |

Results for inputs outside "normalised or `$00000000`" are given by the vectors only; no general rule is claimed for
them beyond this table.

## 3. Calling contracts

### 3.1 Entry [Doc + O]

`##bias 30`; registers from `mathffp_lib.fd` and AROS `mathffp.conf`, confirmed by the observations:

| LVO | Function | Inputs | Result (D0) |
|---:|---|---|---|
| −30 | SPFix | D0 = FFP | 32-bit signed integer |
| −36 | SPFlt | D0 = 32-bit signed integer | FFP |
| −42 | SPCmp | D1 = fnum1, D0 = fnum2 | +1 / 0 / −1 (long) |
| −48 | SPTst | **D1** = FFP (D0 ignored) | +1 / 0 / −1 (long) |
| −54 | SPAbs | D0 | FFP |
| −60 | SPNeg | D0 | FFP |
| −66 | SPAdd | D1, D0 | D1 + D0 |
| −72 | SPSub | D1, D0 | **D0 − D1** |
| −78 | SPMul | D1, D0 | D1 × D0 |
| −84 | SPDiv | D1 = divisor, D0 = dividend | **D0 / D1** |
| −90 | SPFloor | D0 | FFP |
| −96 | SPCeil | D0 | FFP |

A6 is not used by any of the twelve: each gave the reference result with A6 = 0 (one vector per function), and A6
came back unchanged. Calls were made in user mode with the interrupt mask at 7; the mask was unchanged on return.

### 3.2 Exit registers [O]

Markers were placed in D2–D7, A0–A3, A5 before every call (A4 held the vector address, A6 the base):

| Function | Changed besides D0 and CCR | Stack used (bytes below the caller's SP, return address included) |
|---|---|---|
| SPFix, SPFlt | D1 | 4 |
| SPCmp, SPTst | D1 | 12 |
| SPAbs, SPNeg | — | 4 |
| SPAdd, SPSub, SPMul, SPDiv | — (**D1 preserved**) | 16 |
| SPFloor | D1 | 4 or 28 (depending on the value) |
| SPCeil | D1 | 8 or 32 |

A0, A1, D2–D7, A2–A6 were preserved by every function on every vector. D1 after SPFix/SPFlt/SPCmp/SPTst/SPFloor/
SPCeil holds an internal value (e.g. the result's sign/exponent byte, sign-extended, after SPFlt); it is
**undefined**. The public ABI lets every function clobber D0/D1/A0/A1; the V34 behaviour above is stricter [D].

### 3.3 Condition codes [O]

| Function | N | Z | V | C, X |
|---|---|---|---|---|
| SPFix | result negative | result 0 **or** returned-unchanged input (X20, X21) **or** negative saturation | saturation | undefined |
| SPFlt | result negative | result 0 | always 0 | C 0; X undefined |
| SPCmp | see below | equal | see below | C undefined; X unchanged |
| SPTst | negative (bit 7) | low byte 0 | 0 | C 0 |
| SPAbs, SPNeg | bit 7 of the result | low byte of the result 0 | 0 | C 0 |
| SPAdd, SPSub, SPMul, SPDiv | bit 7 of the result | low byte of the result 0 | overflow (saturation) | C 0; X undefined |
| SPFloor, SPCeil | bit 7 of the result | low byte of the result 0 | 0 | C 0 |

- **SPCmp**: Z set iff the result is 0; when the result is +1 (D1 > D0) the codes satisfy **LT** (N ≠ V), when it is
  −1 they satisfy **GT** (N = V, Z = 0). All 899 SPCmp vectors obey this; the individual N and V bits vary (N only,
  V only, or N V C). Only the signed conditions (EQ NE GT GE LT LE) are meaningful, as the AutoDoc lists. [O]
- X: on some paths the incoming X is left as it was (SPCmp on every vector tried; SPAdd/SPSub/SPMul/SPDiv with a zero operand), on
  others it is changed. C is set by SPFix and SPCmp on some values. Neither is part of the contract. [O]
- The incoming condition codes do not change D0 or N/Z/V: 40 vectors run with CCR = `$1F` on entry gave the same
  results as with CCR = 0. [O]

## 4. Function behaviour

Every rule below states its evidence. "Normalised" = mantissa bit 31 set and exponent ≠ 0.

### 4.1 SPFix (−30) [O]

- **Truncation toward zero** for in-range values: 1.5 → 1, −1.5 → −1, 2.5 → 2, −2.5 → −2, 0.99999994 → 0 (X5–X10).
  154 of 155 observations fit "truncate toward zero" plus the rules below.
- |value| < 1 (exponent ≤ 64) → 0, Z set.
- Positive, exponent ≥ `$60` (value ≥ 2^31, also for unnormalised mantissas): `$7FFFFFFF`, **V** set (X15, X17,
  X24).
- Negative, exponent `$60`: the result is −(mantissa × 2^8) when that magnitude is between 1 and 2^31 (−2^31 exactly
  gives `$80000000` with N only, X14; unnormalised X25); otherwise (magnitude > 2^31, or mantissa field 0) it
  saturates. Negative, exponent ≥ `$61`: saturates.
- **Negative saturation = `$80000000` with Z and V set and N clear** (X16, X18, X23) — not the flags a
  `$80000000` result would normally get.
- **Low byte 0** (positive, exponent 0, any mantissa): the input long is **returned unchanged** with Z set:
  `$80000000` → `$80000000`, `$12345600` → `$12345600` (X20, X21). `$00000000` → 0 is the same rule.
- Mantissa field 0 with exponent `$41`–`$5F` → 0 (X22).

### 4.2 SPFlt (−36) [O]

- Exact for |i| ≤ 2^24. Above, **round to nearest, ties away from zero** (on the magnitude): 16777217 → 16777218,
  16777219 → 16777220, −16777217 → −16777218, 33554434 → 33554436 (L10–L15). All 46 observations fit.
- `$7FFFFFFF` and every value from 2147483584 up round to 2^31 = `$80000060` (L16, L20); `$80000000` (−2^31) →
  `$800000E0` (L17).
- 0 → `$00000000` with Z. V never set.

### 4.3 SPCmp (−42) [O]

Result **+1 when D1 > D0**, 0 when equal, −1 when D1 < D0, under this order (fits all 899 observations, ±0 and
unnormalised values included):

1. Different signs (bit 7): the positive one (bit 7 clear) is greater. Hence **`$00000000` > `$00000080`** (C11,
   C12) and 0 is greater than every negative number.
2. Same sign, then compare exponents (7-bit, unsigned), then the **mantissa field as a signed 24-bit number** (bit
   31 acting as its sign); for two negative operands the outcome is reversed.

For normalised operands this is the numeric order. Consequences for the others: an exponent-0 value with mantissa
bit 31 set is **less than** `$00000000` (C13, C14), an unnormalised mantissa is greater than a normalised one of the
same exponent (C16), and a zero mantissa with exponent `$41` is greater than 1.0 (C17). Equality requires identical
longs: `+0` and `−0` compare unequal.

Codes: §3.3.

### 4.4 SPTst (−48) [O]

Argument in **D1**. Result −1 if bit 7 is set (whatever the rest: `$00000080` → −1, T2), else 0 if the low byte is 0
(whatever the mantissa: `$80000000`, `$12345600` → 0, T5, T6), else +1 (`$00000041` → +1, T7). N/Z as the result;
V = 0. All 54 observations fit.

### 4.5 SPAbs (−54) [O]

Result = input with bit 7 cleared, every other bit unchanged (`$00000080` → `$00000000`, `$12345680` →
`$12345600`). Z = low byte of the result 0, N = 0. All 54 observations fit.

### 4.6 SPNeg (−60) [O]

If the low byte is 0, the input is returned unchanged (Z set); otherwise bit 7 is inverted. So `$00000080` →
`$00000000` (N2) and `$80000080` → `$80000000` (N7), while `$80000000` stays (N6). N = bit 7 of the result, Z =
low byte 0. All 54 observations fit.

### 4.7 SPAdd (−66) and SPSub (−72) [O]

SPSub(D1, D0) behaves as SPAdd(D1 with bit 7 inverted, D0): the rule below, applied that way, matches every SPSub
vector with normalised operands. It is stated for an addition of two operands (D1, sign-inverted for SPSub, and D0).

**Zero operands** (low byte 0): if D1 is zero the result is D0 unchanged (D21, D24, D25, S9); otherwise if D0
is zero the result is D1 (SPAdd: D22, D23) or D1 with bit 7 inverted (SPSub: S8, and S10 where "−0" becomes `$00000000`). `$00000080` is not zero (D23).

**Normalised operands** — the result equals the following computation (fitted, matches all **1,114** observed
SPAdd/SPSub calls with two normalised operands, saturations and underflows included):

1. Let A be the operand with the larger exponent (equal exponents: the larger mantissa field), B the other, d =
   exponent(A) − exponent(B), and MA, MB their 24-bit mantissas.
2. **d ≥ 24: the result is A, bit for bit.** B is ignored even when it is half an ulp of A or more (D9 = 0.75 ulp,
   D16 = 0.5 ulp, S11).
3. Otherwise align B on A's scale keeping **8 bits below A's last mantissa bit**; bits of MB further down are
   dropped: B' = ⌊MB × 2^(8−d)⌋ / 2^8 (in units of A's ulp).
4. T = MA + B' (same signs) or MA − B' (different signs), exact. T = 0 → result `$00000000`, Z (D4, S3).
5. **Round T to a whole number of A-ulps first**: add 1/2 and truncate (ties go up in magnitude, D6).
6. Then normalise: if the rounded T ≥ 2^24, halve it **dropping the bit shifted out** (no second rounding) and add
   1 to the exponent (D5, D7); while it is < 2^23, double it (zeros come in) and subtract 1 from the exponent. The
   bits lost in step 5 are not recovered: 2 − 1.00000012 gives **1.0** (exact 0.99999988 is representable, S4),
   1 − 0.99999994 gives **2^−23** (exact 2^−24, D14).
7. The sign is A's sign; the exponent starts at A's exponent.
8. Exponent > 127 → **saturation** `$FFFFFF7F` / `$FFFFFFFF` (±MAX) with V (D15, D18, D19, S7). Exponent < 0 → `$00000000` with Z
   (D20). [The case "final exponent exactly 0" was not reached; see open point 2.]

In other words: for addition of same-sign operands the result is correctly rounded (half up) except after a
carry-out, where it is truncated; for cancellation the result is rounded to the larger operand's precision and then
normalised, so it can be off by up to one ulp of the larger operand from the exact difference. [D]

### 4.8 SPMul (−78) [O]

**Zero operands**: if D0's low byte is 0, D0 is returned unchanged (M7: `$80000000` stays `$80000000`); otherwise if
D1's low byte is 0, the result is `$00000000` (M4–M6). `$00000080` is not zero: 2 × "−0" gives `$00000081` (M8).

**Normalised operands** (fits all **720** observed calls with normalised or zero operands):

1. S = exponent(D1) + exponent(D0). **S ≥ 192 → saturation** `$FFFFFF7F` / `$FFFFFFFF` (±MAX) with V, with the product's sign —
   decided on the exponents alone, before the mantissa product is known: 1 × MAX, 2^31 × 2^31 and a product of
   ≈ 6.5e18 all saturate (M11, M13, M14).
2. Exponent E = S − 64; mantissa product MA × MB / 2^24, in [2^22, 2^24). If it is < 2^23, double it and E = E − 1.
3. Round to 24 bits, to nearest, **ties away from zero** (100 tie vectors observed, M9, M10). Rounding never
   carries out.
4. E < 0 → `$00000000`, Z. **E = 0**: positive result → `$00000000`, Z (M15, M17); **negative result → returned
   with exponent 0** (low byte `$80`, N set: M16, M18).

### 4.9 SPDiv (−84) [O]

D0 / D1.

- **Divisor with low byte 0** (`$00000000`, `$80000000`, any positive exponent-0 value) or with **mantissa field 0**
  (`$00000041`): the CPU takes the **zero-divide exception** (vector 5) inside the function, also for 0 / 0 (24
  vectors, every one trapped). Without a debugger, in a task, the screen shows "Software Failure. Press left mouse
  button to continue." / "Guru Meditation #00000005.<task address>" (V5, V8, V9).
- Divisor `$00000080` ("−0"): treated as a number with exponent 0 → overflow, −MAX with V for 1 / −0 (V6); 0 / −0
  → 0 (V7).
- **Dividend `$00000000`** (whole long) with a non-zero divisor → `$00000000`, Z (V4). A dividend with low byte 0
  but a non-zero mantissa is a number with exponent 0: `$80000000` / 0.5 → `$80000001` (V18).

**Normalised operands** (fits all **602** observed calls):

1. Q = exponent(D0) − exponent(D1) + 64. **Q ≥ 128 → saturation** with the quotient's sign and V. **Q < 0 →
   `$00000000`**, Z (V15).
2. Mantissa quotient MD / MV; if MD ≥ MV it is halved and the exponent becomes Q + 1, else Q.
3. Rounded to nearest (no tie can occur with normalised operands: the exact quotient never needs 25 bits [D]).
4. If the exponent has become **128** (observed only through step 2, open point 1), the result saturates to MAX with V and
   the **sign of the divisor**, not of the quotient: (−MAX) / 0.5 → **+MAX** (V12), (−MAX) / (−0.5) → **−MAX**
   (V13), MAX / 0.5 → +MAX (V11).
5. Exponent 0: positive → `$00000000` (V17), negative → kept with exponent 0 (V16), as SPMul.

### 4.10 SPFloor (−90) and SPCeil (−96) [O]

- Normalised inputs: **exact** floor and ceiling (127 observations each), on negative values too: SPFloor(−1.5) =
  −2, SPFloor(−0.5) = −1, SPFloor(−2^−64) = −1; SPCeil(−1.5) = −1, SPCeil(0.5) = 1, SPCeil(2^−64) = 1.
- A zero result is always `$00000000` (SPCeil(−0.5) = +0, E10, E13; SPFloor(−0) = +0, F2).
- Values ≥ 2^23 in magnitude are already integers and come back unchanged (F14–F16).
- Non-canonical inputs (vectors F17–F19, E17–E19): an exponent-0 negative value becomes `$80000000`; the
  unnormalised 0.5 `$40000041` floors to `$00000041` (a zero mantissa with exponent `$41`) and ceils to 1;
  `$00000001` floors to 0 and ceils to 1.

The AutoDoc identity Ceil(x) = −Floor(−x) holds on every normalised vector. [O]

## 5. Differences from the public documentation [O vs Doc]

- 3.1 AutoDoc synopsis of SPCmp prints the registers as "D0 D1"; the fd and the observed behaviour use **fnum1 = D1,
  fnum2 = D0** (+1 when D1 > D0).
- SPTst takes its argument in **D1**, as the fd says (easy to miss: every other one-argument function uses D0).
- SPFix "returns the truncated integer": true, but out-of-range values saturate with V (and Z on the negative side),
  and exponent-0 values come back unchanged.
- The AutoDocs say nothing about overflow, underflow or division by zero: saturation with V, flush to zero, and a
  **zero-divide trap** respectively.
- "−0" (`$00000080`) has no documented status; the ROM does not treat it as zero (but SPNeg and SPAbs map it to 0).
- AROS's SPFix autodoc header says "absolute value of fnum1" as the result: a copy slip; the V34 function returns
  the signed truncation.

## 6. Known users and the vectors that matter to them [D]

- **Workbench 1.3** (`workbench-task-v34.md` §2.2, §8.3): opens mathffp at start-up (failure = Alert `$31038005`)
  and computes the drawer scroll bars with Flt/Mul/Div/Fix: Body = Fix(65535 × visible / range), Pot =
  Fix(65535 × pos / (range − visible)). Matters: SPFlt exactness for small integers, SPDiv rounding, SPFix
  truncation (vectors L*, V1–V3, X5–X12).
- A game in `dos-v34-spec.md` §4 keeps mathffp open while running (open count observed, use unknown).
- Compiled programs using FFP (Lattice/Manx/Aztec C FFP libraries, AmigaBASIC, the disk-based `mathtrans.library`
  which works on FFP numbers) [S: none analysed yet]. Such code typically relies on SPCmp's codes (signed branches),
  SPFix truncation and SPFlt.

## 7. Test vectors

All results below were observed on the real ROM with the method of the header; the "Flags" column lists N, Z, V
(X and C omitted, §3.3). Decimal values are approximate (the hex is authoritative). Inputs not listed in the
"Input" column hold markers and are ignored.

#### V1 SPFix (D0 → D0, integer)

| Id | Input | Result | Flags | Note |
|---|---|---|---|---|
| X1 | D0=`$00000000` (0) | `$00000000` (0) | Z |  |
| X2 | D0=`$00000080` (-0) | `$00000000` (0) | Z | "−0" |
| X3 | D0=`$80000041` (1) | `$00000001` (1) | – |  |
| X4 | D0=`$800000C1` (-1) | `$FFFFFFFF` (-1) | N |  |
| X5 | D0=`$C0000041` (1.5) | `$00000001` (1) | – | truncation |
| X6 | D0=`$C00000C1` (-1.5) | `$FFFFFFFF` (-1) | N | toward zero |
| X7 | D0=`$A0000042` (2.5) | `$00000002` (2) | – |  |
| X8 | D0=`$A00000C2` (-2.5) | `$FFFFFFFE` (-2) | N |  |
| X9 | D0=`$FFFFFF40` (0.99999994) | `$00000000` (0) | Z |  |
| X10 | D0=`$80000040` (0.5) | `$00000000` (0) | Z |  |
| X11 | D0=`$FFFFFF58` (16777215) | `$00FFFFFF` (16777215) | – |  |
| X12 | D0=`$FFFFFF5F` (2.14748352e+09) | `$7FFFFF80` (2147483520) | – | largest in range |
| X13 | D0=`$FFFFFFDF` (-2.14748352e+09) | `$80000080` (-2147483520) | N |  |
| X14 | D0=`$800000E0` (-2.14748365e+09) | `$80000000` (-2147483648) | N | exactly −2^31 |
| X15 | D0=`$80000060` (2.14748365e+09) | `$7FFFFFFF` (2147483647) | V | 2^31: saturates |
| X16 | D0=`$800001E0` (-2.1474839e+09) | `$80000000` (-2147483648) | ZV | below −2^31 |
| X17 | D0=`$FFFFFF7F` (9.22337149e+18) | `$7FFFFFFF` (2147483647) | V |  |
| X18 | D0=`$FFFFFFFF` (-9.22337149e+18) | `$80000000` (-2147483648) | ZV |  |
| X19 | D0=`$80000001` (5.42101086e-20) | `$00000000` (0) | Z |  |
| X20 | D0=`$80000000` (2.71050543e-20) | `$80000000` (-2147483648) | Z | exponent 0: returned unchanged |
| X21 | D0=`$12345600` (3.85493954e-21) | `$12345600` (305419776) | Z | exponent 0: returned unchanged |
| X22 | D0=`$00000041` (0) | `$00000000` (0) | Z | zero mantissa |
| X23 | D0=`$000000E0` (-0) | `$80000000` (-2147483648) | ZV | zero mantissa, exponent $60, negative |
| X24 | D0=`$40000060` (1.07374182e+09) | `$7FFFFFFF` (2147483647) | V | unnormalised |
| X25 | D0=`$7FFFFFE0` (-2.14748339e+09) | `$80000100` (-2147483392) | N | unnormalised |

#### V2 SPFlt (D0 integer → D0)

| Id | Input | Result | Flags | Note |
|---|---|---|---|---|
| L1 | D0=`$00000000` (0) | `$00000000` (0) | Z |  |
| L2 | D0=`$00000001` (1) | `$80000041` (1) | – |  |
| L3 | D0=`$FFFFFFFF` (-1) | `$800000C1` (-1) | N |  |
| L4 | D0=`$00000003` (3) | `$C0000042` (3) | – |  |
| L5 | D0=`$00000007` (7) | `$E0000043` (7) | – |  |
| L6 | D0=`$00000064` (100) | `$C8000047` (100) | – |  |
| L7 | D0=`$FFFFFF01` (-255) | `$FF0000C8` (-255) | N |  |
| L8 | D0=`$00FFFFFF` (16777215) | `$FFFFFF58` (16777215) | – | exact |
| L9 | D0=`$01000000` (16777216) | `$80000059` (16777216) | – |  |
| L10 | D0=`$01000001` (16777217) | `$80000159` (16777218) | – | tie → away from zero |
| L11 | D0=`$01000002` (16777218) | `$80000159` (16777218) | – |  |
| L12 | D0=`$01000003` (16777219) | `$80000259` (16777220) | – | tie → away from zero |
| L13 | D0=`$FEFFFFFF` (-16777217) | `$800001D9` (-16777218) | N | tie → away from zero |
| L14 | D0=`$02000002` (33554434) | `$8000015A` (33554436) | – | tie |
| L15 | D0=`$02000006` (33554438) | `$8000025A` (33554440) | – | tie |
| L16 | D0=`$7FFFFFFF` (2147483647) | `$80000060` (2.14748365e+09) | – | rounds up to 2^31 |
| L17 | D0=`$80000000` (-2147483648) | `$800000E0` (-2.14748365e+09) | N |  |
| L18 | D0=`$80000001` (-2147483647) | `$800000E0` (-2.14748365e+09) | N |  |
| L19 | D0=`$7FFFFFBF` (2147483583) | `$FFFFFF5F` (2.14748352e+09) | – | below the tie |
| L20 | D0=`$7FFFFFC0` (2147483584) | `$80000060` (2.14748365e+09) | – | tie → 2^31 |
| L21 | D0=`$12345678` (305419896) | `$91A2B45D` (305419904) | – |  |

#### V3 SPCmp (D1 = fnum1, D0 = fnum2 → +1 if D1 > D0)

| Id | Input | Result | Flags | Note |
|---|---|---|---|---|
| C1 | D1=`$80000041` (1), D0=`$00000000` (0) | `$00000001` (+1) | N |  |
| C2 | D1=`$00000000` (0), D0=`$80000041` (1) | `$FFFFFFFF` (-1) | – |  |
| C3 | D1=`$80000041` (1), D0=`$80000041` (1) | `$00000000` (0) | Z |  |
| C4 | D1=`$00000000` (0), D0=`$00000000` (0) | `$00000000` (0) | Z |  |
| C5 | D1=`$800000C1` (-1), D0=`$80000041` (1) | `$FFFFFFFF` (-1) | NV |  |
| C6 | D1=`$80000041` (1), D0=`$800000C1` (-1) | `$00000001` (+1) | N |  |
| C7 | D1=`$800000C1` (-1), D0=`$800000C2` (-2) | `$00000001` (+1) | N |  |
| C8 | D1=`$800000C2` (-2), D0=`$800000C1` (-1) | `$FFFFFFFF` (-1) | – |  |
| C9 | D1=`$80000041` (1), D0=`$80000141` (1.00000012) | `$FFFFFFFF` (-1) | – | 1 ulp |
| C10 | D1=`$FFFFFF7F` (9.22337149e+18), D0=`$FFFFFFFF` (-9.22337149e+18) | `$00000001` (+1) | N |  |
| C11 | D1=`$00000000` (0), D0=`$00000080` (-0) | `$00000001` (+1) | N | +0 vs −0 |
| C12 | D1=`$00000080` (-0), D0=`$00000000` (0) | `$FFFFFFFF` (-1) | NV |  |
| C13 | D1=`$80000000` (2.71050543e-20), D0=`$00000000` (0) | `$FFFFFFFF` (-1) | NV | exponent-0 value vs 0 |
| C14 | D1=`$00000000` (0), D0=`$80000000` (2.71050543e-20) | `$00000001` (+1) | N |  |
| C15 | D1=`$00000080` (-0), D0=`$80000080` (-2.71050543e-20) | `$FFFFFFFF` (-1) | NV |  |
| C16 | D1=`$40000042` (1), D0=`$80000042` (2) | `$00000001` (+1) | V | unnormalised |
| C17 | D1=`$00000041` (0), D0=`$80000041` (1) | `$00000001` (+1) | N | zero mantissa |

#### V4 SPTst (D1 → D0)

| Id | Input | Result | Flags | Note |
|---|---|---|---|---|
| T1 | D1=`$00000000` (0) | `$00000000` (0) | Z |  |
| T2 | D1=`$00000080` (-0) | `$FFFFFFFF` (-1) | N | "−0" |
| T3 | D1=`$80000041` (1) | `$00000001` (+1) | – |  |
| T4 | D1=`$800000C1` (-1) | `$FFFFFFFF` (-1) | N |  |
| T5 | D1=`$80000000` (2.71050543e-20) | `$00000000` (0) | Z | low byte 0 |
| T6 | D1=`$12345600` (3.85493954e-21) | `$00000000` (0) | Z | low byte 0 |
| T7 | D1=`$00000041` (0) | `$00000001` (+1) | – | zero mantissa |
| T8 | D1=`$000000C1` (-0) | `$FFFFFFFF` (-1) | N |  |
| T9 | D1=`$FFFFFF7F` (9.22337149e+18) | `$00000001` (+1) | – |  |
| T10 | D1=`$FFFFFFFF` (-9.22337149e+18) | `$FFFFFFFF` (-1) | N |  |

#### V5 SPAbs

| Id | Input | Result | Flags | Note |
|---|---|---|---|---|
| A1 | D0=`$00000000` (0) | `$00000000` (0) | Z |  |
| A2 | D0=`$00000080` (-0) | `$00000000` (0) | Z |  |
| A3 | D0=`$800000C1` (-1) | `$80000041` (1) | – |  |
| A4 | D0=`$80000041` (1) | `$80000041` (1) | – |  |
| A5 | D0=`$FFFFFFFF` (-9.22337149e+18) | `$FFFFFF7F` (9.22337149e+18) | – |  |
| A6 | D0=`$80000080` (-2.71050543e-20) | `$80000000` (2.71050543e-20) | Z |  |
| A7 | D0=`$000000C1` (-0) | `$00000041` (0) | – |  |
| A8 | D0=`$12345680` (-3.85493954e-21) | `$12345600` (3.85493954e-21) | Z |  |

#### V6 SPNeg

| Id | Input | Result | Flags | Note |
|---|---|---|---|---|
| N1 | D0=`$00000000` (0) | `$00000000` (0) | Z |  |
| N2 | D0=`$00000080` (-0) | `$00000000` (0) | Z | "−0" becomes +0 |
| N3 | D0=`$80000041` (1) | `$800000C1` (-1) | N |  |
| N4 | D0=`$800000C1` (-1) | `$80000041` (1) | – |  |
| N5 | D0=`$FFFFFF7F` (9.22337149e+18) | `$FFFFFFFF` (-9.22337149e+18) | N |  |
| N6 | D0=`$80000000` (2.71050543e-20) | `$80000000` (2.71050543e-20) | Z | low byte 0: unchanged |
| N7 | D0=`$80000080` (-2.71050543e-20) | `$80000000` (2.71050543e-20) | Z |  |
| N8 | D0=`$00000041` (0) | `$000000C1` (-0) | N |  |
| N9 | D0=`$12345600` (3.85493954e-21) | `$12345600` (3.85493954e-21) | Z |  |

#### V7 SPAdd (D1 + D0)

| Id | Input | Result | Flags | Note |
|---|---|---|---|---|
| D1 | D1=`$80000041` (1), D0=`$80000041` (1) | `$80000042` (2) | – |  |
| D2 | D1=`$80000041` (1), D0=`$80000042` (2) | `$C0000042` (3) | – |  |
| D3 | D1=`$C0000041` (1.5), D0=`$C0000041` (1.5) | `$C0000042` (3) | – |  |
| D4 | D1=`$80000041` (1), D0=`$800000C1` (-1) | `$00000000` (0) | Z | exact cancellation |
| D5 | D1=`$80000141` (1.00000012), D0=`$80000041` (1) | `$80000042` (2) | – | carry, tie: truncated |
| D6 | D1=`$80000141` (1.00000012), D0=`$80000042` (2) | `$C0000142` (3.00000024) | – | tie at alignment: rounded up |
| D7 | D1=`$80000141` (1.00000012), D0=`$C0000041` (1.5) | `$A0000042` (2.5) | – | carry: truncated |
| D8 | D1=`$80000028` (2.98023224e-08), D0=`$80000041` (1) | `$80000041` (1) | – | d = 25 |
| D9 | D1=`$C0000029` (8.94069672e-08), D0=`$80000041` (1) | `$80000041` (1) | – | d = 24: 0.75 ulp dropped |
| D10 | D1=`$800000A8` (-2.98023224e-08), D0=`$80000041` (1) | `$80000041` (1) | – | d = 25 |
| D11 | D1=`$80000027` (1.49011612e-08), D0=`$80000041` (1) | `$80000041` (1) | – | d = 26 |
| D12 | D1=`$80000028` (2.98023224e-08), D0=`$80000141` (1.00000012) | `$80000141` (1.00000012) | – |  |
| D13 | D1=`$800000A8` (-2.98023224e-08), D0=`$80000141` (1.00000012) | `$80000141` (1.00000012) | – |  |
| D14 | D1=`$FFFFFFC0` (-0.99999994), D0=`$80000041` (1) | `$8000002A` (1.1920929e-07) | – | 1 + (−(1−2^-24)): cancellation |
| D15 | D1=`$80000068` (5.49755814e+11), D0=`$FFFFFF7F` (9.22337149e+18) | `$FFFFFF7F` (9.22337149e+18) | V | d = 23, sum reaches 2^63 |
| D16 | D1=`$80000029` (5.96046448e-08), D0=`$80000041` (1) | `$80000041` (1) | – | d = 24: half ulp dropped |
| D17 | D1=`$80000029` (5.96046448e-08), D0=`$80000141` (1.00000012) | `$80000141` (1.00000012) | – | d = 24 |
| D18 | D1=`$FFFFFF7F` (9.22337149e+18), D0=`$FFFFFF7F` (9.22337149e+18) | `$FFFFFF7F` (9.22337149e+18) | V | overflow |
| D19 | D1=`$FFFFFFFF` (-9.22337149e+18), D0=`$FFFFFFFF` (-9.22337149e+18) | `$FFFFFFFF` (-9.22337149e+18) | NV | overflow |
| D20 | D1=`$80000081` (-5.42101086e-20), D0=`$80000101` (5.42101151e-20) | `$00000000` (0) | Z | underflow |
| D21 | D1=`$00000000` (0), D0=`$80000041` (1) | `$80000041` (1) | – |  |
| D22 | D1=`$80000041` (1), D0=`$00000000` (0) | `$80000041` (1) | – |  |
| D23 | D1=`$00000080` (-0), D0=`$00000000` (0) | `$00000080` (-0) | N | −0 + 0 |
| D24 | D1=`$80000000` (2.71050543e-20), D0=`$80000041` (1) | `$80000041` (1) | – | exponent-0 operand ignored |
| D25 | D1=`$00000000` (0), D0=`$00000000` (0) | `$00000000` (0) | Z |  |

#### V8 SPSub (D0 − D1)

| Id | Input | Result | Flags | Note |
|---|---|---|---|---|
| S1 | D1=`$80000041` (1), D0=`$80000042` (2) | `$80000041` (1) | – | 2 − 1 |
| S2 | D1=`$80000042` (2), D0=`$80000041` (1) | `$800000C1` (-1) | N | 1 − 2 |
| S3 | D1=`$80000041` (1), D0=`$80000041` (1) | `$00000000` (0) | Z |  |
| S4 | D1=`$80000141` (1.00000012), D0=`$80000042` (2) | `$80000041` (1) | – | rounded before normalisation |
| S5 | D1=`$80000141` (1.00000012), D0=`$C0000042` (3) | `$80000042` (2) | – |  |
| S6 | D1=`$80000042` (2), D0=`$80000141` (1.00000012) | `$800000C1` (-1) | N |  |
| S7 | D1=`$FFFFFF7F` (9.22337149e+18), D0=`$FFFFFFFF` (-9.22337149e+18) | `$FFFFFFFF` (-9.22337149e+18) | NV | overflow |
| S8 | D1=`$80000041` (1), D0=`$00000000` (0) | `$800000C1` (-1) | N | 0 − 1 |
| S9 | D1=`$00000000` (0), D0=`$80000041` (1) | `$80000041` (1) | – |  |
| S10 | D1=`$00000080` (-0), D0=`$00000000` (0) | `$00000000` (0) | Z |  |
| S11 | D1=`$800000A9` (-5.96046448e-08), D0=`$80000041` (1) | `$80000041` (1) | – | d = 24 |

#### V9 SPMul (D1 × D0)

| Id | Input | Result | Flags | Note |
|---|---|---|---|---|
| M1 | D1=`$C0000041` (1.5), D0=`$C0000041` (1.5) | `$90000042` (2.25) | – |  |
| M2 | D1=`$C0000042` (3), D0=`$C0000042` (3) | `$90000044` (9) | – |  |
| M3 | D1=`$80000042` (2), D0=`$800000C1` (-1) | `$800000C2` (-2) | N |  |
| M4 | D1=`$00000000` (0), D0=`$C0000041` (1.5) | `$00000000` (0) | Z |  |
| M5 | D1=`$C0000041` (1.5), D0=`$00000000` (0) | `$00000000` (0) | Z |  |
| M6 | D1=`$80000000` (2.71050543e-20), D0=`$80000041` (1) | `$00000000` (0) | Z | D1 exponent 0: result 0 |
| M7 | D1=`$80000041` (1), D0=`$80000000` (2.71050543e-20) | `$80000000` (2.71050543e-20) | Z | D0 exponent 0: D0 returned |
| M8 | D1=`$80000042` (2), D0=`$00000080` (-0) | `$00000081` (-0) | N | "−0" is not zero |
| M9 | D1=`$881000BD` (-0.0664367676), D0=`$800400C9` (-256.03125) | `$88144145` (17.0098896) | – | tie → away from zero |
| M10 | D1=`$900100B2` (-3.43332067e-05), D0=`$C84000CE` (-12816) | `$E149913F` (0.440014392) | – | tie |
| M11 | D1=`$80000041` (1), D0=`$FFFFFF7F` (9.22337149e+18) | `$FFFFFF7F` (9.22337149e+18) | V | exponent sum overflow |
| M12 | D1=`$80000040` (0.5), D0=`$FFFFFF7F` (9.22337149e+18) | `$FFFFFF7E` (4.61168574e+18) | – |  |
| M13 | D1=`$80000060` (2.14748365e+09), D0=`$80000060` (2.14748365e+09) | `$FFFFFF7F` (9.22337149e+18) | V | 2^62 representable, still saturates |
| M14 | D1=`$800000F0` (-1.40737488e+14), D0=`$B504F3D0` (-46340.9492) | `$FFFFFF7F` (9.22337149e+18) | V | product ≈ 6.5e18 fits, still saturates |
| M15 | D1=`$80000021` (2.32830644e-10), D0=`$80000020` (1.16415322e-10) | `$00000000` (0) | Z | result exponent 0, positive → 0 |
| M16 | D1=`$80000138` (0.00195312523), D0=`$B504F389` (-1.96261554e-17) | `$B504F480` (-3.8332338e-20) | N | result exponent 0, negative → kept |
| M17 | D1=`$C00000BD` (-0.09375), D0=`$B504F483` (-3.06658704e-19) | `$00000000` (0) | Z | exponent sum 64, positive → 0 |
| M18 | D1=`$C00000A0` (-1.74622983e-10), D0=`$C0000020` (1.74622983e-10) | `$90000080` (-3.04931861e-20) | N | exponent sum 64, negative → kept |

#### V10 SPDiv (D0 / D1)

| Id | Input | Result | Flags | Note |
|---|---|---|---|---|
| V1 | D1=`$C0000042` (3), D0=`$80000041` (1) | `$AAAAAB3F` (0.333333343) | – | 1/3 |
| V2 | D1=`$80000042` (2), D0=`$80000041` (1) | `$80000040` (0.5) | – |  |
| V3 | D1=`$C0000041` (1.5), D0=`$80000041` (1) | `$AAAAAB40` (0.666666687) | – | 2/3 |
| V4 | D1=`$80000041` (1), D0=`$00000000` (0) | `$00000000` (0) | Z |  |
| V5 | D1=`$00000000` (0), D0=`$80000041` (1) | **trap: 68000 zero-divide exception (vector 5)** | — |  |
| V6 | D1=`$00000080` (-0), D0=`$80000041` (1) | `$FFFFFFFF` (-9.22337149e+18) | NV | divisor "−0" |
| V7 | D1=`$00000080` (-0), D0=`$00000000` (0) | `$00000000` (0) | Z |  |
| V8 | D1=`$00000041` (0), D0=`$80000041` (1) | **trap: 68000 zero-divide exception (vector 5)** | — | zero mantissa |
| V9 | D1=`$80000000` (2.71050543e-20), D0=`$80000041` (1) | **trap: 68000 zero-divide exception (vector 5)** | — | exponent 0 |
| V10 | D1=`$FFFFFF7F` (9.22337149e+18), D0=`$80000041` (1) | `$80000102` (1.0842023e-19) | – |  |
| V11 | D1=`$80000040` (0.5), D0=`$FFFFFF7F` (9.22337149e+18) | `$FFFFFF7F` (9.22337149e+18) | V | overflow from mantissa step |
| V12 | D1=`$80000040` (0.5), D0=`$FFFFFFFF` (-9.22337149e+18) | `$FFFFFF7F` (9.22337149e+18) | V | sign of divisor, not of quotient |
| V13 | D1=`$800000C0` (-0.5), D0=`$FFFFFFFF` (-9.22337149e+18) | `$FFFFFFFF` (-9.22337149e+18) | NV |  |
| V14 | D1=`$80000080` (-2.71050543e-20), D0=`$80000041` (1) | `$FFFFFFFF` (-9.22337149e+18) | NV | divisor exponent 0, negative |
| V15 | D1=`$80000042` (2), D0=`$80000001` (5.42101086e-20) | `$00000000` (0) | Z | underflow |
| V16 | D1=`$FFFFFFC1` (-1.99999988), D0=`$80000001` (5.42101086e-20) | `$80000180` (-2.71050575e-20) | N | exponent 0, negative → kept |
| V17 | D1=`$FFFFFF41` (1.99999988), D0=`$80000001` (5.42101086e-20) | `$00000000` (0) | Z | exponent 0, positive → 0 |
| V18 | D1=`$80000040` (0.5), D0=`$80000000` (2.71050543e-20) | `$80000001` (5.42101086e-20) | – | dividend exponent 0 is a number |
| V19 | D1=`$F7698CBF` (-0.483227134), D0=`$EC30A533` (0.000112624177) | `$F46361B4` (-0.000233066748) | N |  |
| V20 | D1=`$40000041` (0.5), D0=`$80000041` (1) | `$00000040` (0) | – | unnormalised divisor |

#### V11 SPFloor

| Id | Input | Result | Flags | Note |
|---|---|---|---|---|
| F1 | D0=`$00000000` (0) | `$00000000` (0) | Z |  |
| F2 | D0=`$00000080` (-0) | `$00000000` (0) | Z |  |
| F3 | D0=`$80000041` (1) | `$80000041` (1) | – |  |
| F4 | D0=`$800000C1` (-1) | `$800000C1` (-1) | N |  |
| F5 | D0=`$C0000041` (1.5) | `$80000041` (1) | – |  |
| F6 | D0=`$C00000C1` (-1.5) | `$800000C2` (-2) | N |  |
| F7 | D0=`$A0000042` (2.5) | `$80000042` (2) | – |  |
| F8 | D0=`$A00000C2` (-2.5) | `$C00000C2` (-3) | N |  |
| F9 | D0=`$80000040` (0.5) | `$00000000` (0) | Z |  |
| F10 | D0=`$800000C0` (-0.5) | `$800000C1` (-1) | N |  |
| F11 | D0=`$FFFFFF41` (1.99999988) | `$80000041` (1) | – |  |
| F12 | D0=`$80000001` (5.42101086e-20) | `$00000000` (0) | Z |  |
| F13 | D0=`$80000081` (-5.42101086e-20) | `$800000C1` (-1) | N |  |
| F14 | D0=`$FFFFFF58` (16777215) | `$FFFFFF58` (16777215) | – |  |
| F15 | D0=`$FFFFFFD8` (-16777215) | `$FFFFFFD8` (-16777215) | N |  |
| F16 | D0=`$FFFFFF7F` (9.22337149e+18) | `$FFFFFF7F` (9.22337149e+18) | – |  |
| F17 | D0=`$80000080` (-2.71050543e-20) | `$80000000` (2.71050543e-20) | Z |  |
| F18 | D0=`$40000041` (0.5) | `$00000041` (0) | – |  |
| F19 | D0=`$00000001` (0) | `$00000000` (0) | Z |  |

#### V12 SPCeil

| Id | Input | Result | Flags | Note |
|---|---|---|---|---|
| E1 | D0=`$00000000` (0) | `$00000000` (0) | Z |  |
| E2 | D0=`$00000080` (-0) | `$00000000` (0) | Z |  |
| E3 | D0=`$80000041` (1) | `$80000041` (1) | – |  |
| E4 | D0=`$800000C1` (-1) | `$800000C1` (-1) | N |  |
| E5 | D0=`$C0000041` (1.5) | `$80000042` (2) | – |  |
| E6 | D0=`$C00000C1` (-1.5) | `$800000C1` (-1) | N |  |
| E7 | D0=`$A0000042` (2.5) | `$C0000042` (3) | – |  |
| E8 | D0=`$A00000C2` (-2.5) | `$800000C2` (-2) | N |  |
| E9 | D0=`$80000040` (0.5) | `$80000041` (1) | – |  |
| E10 | D0=`$800000C0` (-0.5) | `$00000000` (0) | Z |  |
| E11 | D0=`$FFFFFF41` (1.99999988) | `$80000042` (2) | – |  |
| E12 | D0=`$80000001` (5.42101086e-20) | `$80000041` (1) | – |  |
| E13 | D0=`$80000081` (-5.42101086e-20) | `$00000000` (0) | Z |  |
| E14 | D0=`$FFFFFF58` (16777215) | `$FFFFFF58` (16777215) | – |  |
| E15 | D0=`$FFFFFFD8` (-16777215) | `$FFFFFFD8` (-16777215) | N |  |
| E16 | D0=`$FFFFFF7F` (9.22337149e+18) | `$FFFFFF7F` (9.22337149e+18) | – |  |
| E17 | D0=`$80000080` (-2.71050543e-20) | `$80000000` (2.71050543e-20) | Z |  |
| E18 | D0=`$40000041` (0.5) | `$80000041` (1) | – |  |
| E19 | D0=`$00000001` (0) | `$80000041` (1) | – |  |

#### V13 Library vectors and registers

| Id | Call | Observed |
|---|---|---|
| B1 | `OpenLibrary("mathffp.library", 0)` | base returned, open count 0 → 1 |
| B2 | `OpenLibrary("mathffp.library", 34)` | base returned, count 2 |
| B3 | `OpenLibrary("mathffp.library", 35)` | 0, count unchanged |
| B4 | `CloseLibrary(base)` | D0 = 0, count 1 |
| B5 | Expunge (−18) with count 1 | D0 = 0, `lib_Flags` `$04` → `$0C`, still listed |
| B6 | `CloseLibrary(base)` with DELEXP set | D0 = 0, count 0, **still listed** |
| B7 | Null (−24) | D0 unchanged |
| B8 | Expunge (−18) with count 0 | D0 = 0, removed from the library list |
| R1 | each of the 12 functions with A6 = 0 | same results as with A6 = base: SPFix(3.0) = 3, SPFlt(7) = `$E0000043`, SPCmp(D1 = 2, D0 = 1) = +1, SPTst(−1) = −1, SPAbs(−1) = 1, SPNeg(1) = −1, SPAdd(2, 1) = 3, SPSub(D1 = 2, D0 = 1) = −1, SPMul(2, 3) = 6 `$C0000043`, SPDiv(D1 = 3, D0 = 1) = `$AAAAAB3F`, SPFloor(−1.5) = −2, SPCeil(−1.5) = −1 |
| R2 | markers in D2–D7, A0–A3, A5 | preserved by every call; D1 changed only by SPFix, SPFlt, SPCmp, SPTst, SPFloor, SPCeil (§3.2) |
| R3 | entry CCR `$1F` vs `$00` | same D0 and N/Z/V on 40 vectors; X kept on some paths (§3.3) |
| R4 | 1.0 / 0, no debugger | Guru `#00000005.<task>` "Software Failure" |

## 8. Probe to write on the implementation side (`tests/mathffp_probe.s`)

A CLI program (KS 1.x hunk executable, `-kick1hunks`) that runs the vectors of §7 against mathffp.library and prints
one line per vector, so that the same binary gives the oracle on the real ROM and the result on ours:

1. **Open**: `OpenLibrary("mathffp.library", 0)`; print version, revision, open count, NegSize/PosSize, `lib_Flags`.
   Then try version 35 (expect 0). Keep the base in A6 for the calls.
2. **Vector table in the probe**: one record per vector = LVO, D0 input, D1 input, expected D0, expected N/Z/V.
   Generate it from the tables of §7 (a small script can turn them into `dc.l`/`dc.w` lines).
3. **Call**: load D2–D7, A0–A3, A5 with distinct markers, D0/D1 with the inputs, call the function through its LVO with A6 = base; immediately
   capture the codes with conditional set instructions (one for MI, one for EQ, one for VS, and one for LT/GT for
   SPCmp) rather than by reading SR, so that the probe also works on a 68010+ where reading SR is privileged; then
   save D0, D1 and the markers.
4. **Print**: id, D0 in hex, the three flags, `OK`/`DIFF` against the table, and the names of any marker register
   that changed (expected: none; D1 only for the six functions of §3.2).
5. **Stack**: for one vector of each function, switch SP to the top of a 256-byte area filled with `$5A` around the
   call and print the depth of the lowest modified byte (expected 4 to 32, §3.2; any value is acceptable on our side
   if documented).
6. **A6**: one call per function with A6 = 0 (vector R1), restoring A6 afterwards.
7. **Incoming CCR**: repeat ten vectors with all condition codes set before the call (load the CCR with an explicit
   move to CCR) and check that D0/N/Z/V do not change.
8. **Zero divide**: install a task trap handler (`tc_TrapCode`) that, on vector 5, records "trap" and resumes after
   the call (by replacing the return PC of the exception frame with a recovery label); run V5, V8, V9 and 0 / 0, then
   restore the original handler. Print `TRAP` or the returned D0.
9. **Library vectors** at the very end: Close/Open counts, Expunge with count 1 (flags), Close, Null (D0 marker
   unchanged), and last Expunge with count 0 followed by `FindName` on the exec library list (expect absent) — then
   re-open from the ROM is impossible until reboot, so this step must be the last.

Output must not use mathffp itself (print through dos `Write` with the probe's own hex routine).

## Open points

1. **SPDiv rounding carry into exponent 128**: the "divisor's sign" saturation (§4.9 step 4) was observed only when
   the exponent reaches 128 through the halving step; a quotient that reaches 128 by rounding up to 2^24 was not
   produced. Same rule expected [S].
2. **SPAdd/SPSub result with final exponent exactly 0**: not produced (only exponents < 0 → 0). Whether a positive
   result there becomes `$00000000` and a negative one is kept, as in SPMul/SPDiv, is unknown [S].
3. **Open after Expunge-with-DELEXP**: whether Open clears LIBF_DELEXP was not tested; mathffp's Close does not
   expunge, so the flag has no visible effect observed.
4. **Unnormalised inputs and "−0"** are only covered by vectors (§2.2); no rule is claimed. SPDiv with dividend
   `$00000080` was not tried.
5. **Supervisor mode and interrupts**: the functions were called in user mode with interrupts masked; no state is
   kept between calls (no register or memory other than the stack was seen to change), so they are expected to be
   re-entrant and mode-independent [S].
6. **Known users**: only the Workbench use is documented on our side; FFP-compiled programs were not analysed.
7. ~~The probe of §8 has not been run on the real ROM.~~ Done 2026-11-10 [O]: `tests/mathffp_probe.sh` run
   unchanged with its analysis switch on `kick34005.A500` (Amiberry A500, cycle-exact, 512 KB chip + 512 KB
   slow, the probe started from a floppy's startup-sequence, i.e. from a CLI process with interrupts enabled):
   `mathffp_check.py check` gave **264 checks, 0 failures**. Every value, flag and register expectation of §7
   holds on the real ROM; no correction to this page.

## Clean-room review

Review of 2026-11-05.

- [x] No 68000 instruction sequence transcribed or paraphrased, no disassembly excerpt, no ROM routine or data
  address. The ROM code was not read: every fact comes from calls through the public library vectors with
  debugger-written inputs, and from the results, registers, condition codes and stack contents read back.
- [x] The rounding/overflow rules of §4 are arithmetic models fitted to the observed outputs (with the number of
  vectors each one matches), written as mathematical definitions; they were not derived from the ROM's code and do
  not describe its instruction structure.
- [x] The call stub (two instructions written by the debugger) is a generic call-and-loop idiom, not ROM code; §8
  describes the probe in words only.
- [x] The only numbers are the public LVOs, register names, the library's public base fields (version, sizes,
  flags, ID string as visible to any program), stack depths, counts, and the inputs/outputs of our own test vectors.
  RAM addresses of the base, the stub and the stopped task are not given.
- [x] No probe code was written by the analysis track.
- [x] 2026-11-10: the existing implementation-side probe was assembled and run unchanged on the real ROM; only
  its output buffer was read back. No ROM code read, no address recorded.
