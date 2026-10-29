# fault() (BCPL global 104) and C:Fault — V34 / Workbench 1.3.3 behaviour

ANALYSIS track. Sources: ROM `kick34005.A500` (read-only) and `c/Fault`, `c/Copy` extracted from
`assets/wb133.adf` (Workbench 1.3.3) into a temporary directory. Observable contracts only;
no ROM routine address is cited.

Legend: **[O]** observed in the binary · **[D]** deduced (reasoning on what was observed, not executed).

Internal references: BCPL calling convention (§1), `runcommand` (§4.3), globals (§8.2/8.3),
`rdargs` (§5.4), `writef` (§6.3) in [bcpl-runtime-v34.md](bcpl-runtime-v34.md).

---

## 1. Summary

- `fault(code)` contains **no error text**: for `code ≠ 0` it loads **`C:FAULT`** from
  disk (without requester, no search in the Resident list), sets **pr_Result2 := code**,
  runs it via `runcommand` with a stack of **400 longs**, then unloads the segment. [O]
- If `C:FAULT` could not be loaded (or if `runcommand` returns −1), fallback:
  `writef("Error code %N\n", code)` — **with** a newline. [O]
- `code = 0`: does nothing, writes nothing. [O]
- `C:Fault` distinguishes its two modes by **pr_Result2 on entry**:
  - **≠ 0** (call by `fault()`): writes **the text alone** + `\n`, without prefix, without reading any argument; [O]
  - **= 0** (command line, the CLI sets Result2 to 0): reads up to 10 numbers via `rdargs` and writes
    `Fault %I3: <text>\n` for each. [O]
- Unknown code: text `Error <n>` (format `"Error %N"`). [O]
- C:Copy example: `Can't open zzz for input - ` comes from **Copy** (without `\n`), `object not found\n`
  comes from **C:Fault** called by `fault(205)`. [O]

---

## 2. `fault(code)` — global 104 (GV +$1A0), ROM

Landmarks: `fault()` is defined in a resident BCPL segment of dos whose globin table provides
globals 104 (`fault`) and −21 (load without requester, §2.2). BSTR strings used:
`"C:FAULT"` and `"Error code %N\n"` (length 14: the `\n` is **in** the string). [O]

### 2.1 Observable sequence

| Step | Behaviour | Cert. |
|---|---|---|
| 1 | `code = 0` → immediate return, nothing is written, Result2 unchanged. | O |
| 2 | Loading of the segment named by the BSTR **`C:FAULT`** (7 characters, upper case, path via the `C:` assign) by global **−21**. | O |
| 3 | **pr_Result2 := code** (via `result2(TRUE, code)`, global 10), **after** the load (so any Result2 set by LoadSeg is overwritten). Done even if the load failed. | O |
| 4 | If seglist ≠ 0: `runcommand(seg, 400, ?, ?)` (global 121). Stack = **400 longs** (1600 bytes). Return code stored. | O |
| 5 | `unloadseg(seg)` (global 82) **always called**, including with seg = 0. | O (call) / D (no effect for 0) |
| 6 | If seglist = 0 **or** if the return code of `runcommand` is **−1** (stack impossible to allocate, or command exited with −1): `writef("Error code %N\n", code)`. | O |
| 7 | Return to the caller. | O |

### 2.2 Interface details

- **Loading (global −21)** [O]: saves **pr_WindowPtr**, sets it to **−1** (suppresses the
  system requesters, e.g. "Please insert volume"), calls `load(name)` (global 81 = BCPL LoadSeg,
  BSTR name), restores pr_WindowPtr, returns the seglist (0 on failure). **No** consultation
  of the Resident list, **no** search in the CLI's command path: only the literal name
  `C:FAULT`.
- **Command arguments** [O]: `fault()` supplies only the first two parameters of
  `runcommand`; parameters 3 and 4 (argument address/length → A0/D0 on entry to the
  command) are **undetermined** (residual register values). `runcommand` copies nothing, it
  only converts the 3rd into a byte address. No argument buffer is injected into the input
  stream (unlike the CLI §4.2). C:Fault reads neither A0/D0 nor the input in this mode, so
  this is without consequence. **Clean recommendation** [D]: pass address 0 / length 0.
- **Streams** [O]: `fault()` touches neither `input()` nor `output()`: the command writes to the
  **caller's current** `output()` (pr_COS) and inherits its `input()` (pr_CIS) without reading it.
- **Stack**: 400 longs, allocated/freed by `runcommand` (§4.3). [O]
- **pr_Result2 before the call** = `code`. [O]
- **Return code**: only the "= −1" test is used (triggers the fallback). Otherwise ignored. [O]
- **Value returned by fault()**: no explicit value; D1 on return = result of the last internal
  call (unloadseg or writef). Not contractual; no observed caller uses it (Copy ignores it). [O]
- **pr_Result2 after fault()**: `fault()` does not restore it. It equals `code` as set in step 3,
  unless modified by C:Fault's I/O (console write) or by the `writef` fallback. C:Fault in
  fault() mode does not rewrite it itself. [O for fault/C:Fault, D for the effect of the I/O]
- **CLI**: `fault()` does not modify cli_ReturnCode / cli_Result2. C:Fault's stub copies on its
  exit GV[134..149] to the CLI structure (§3 of bcpl-runtime), but C:Fault modifies none of
  these globals → values unchanged. [O stub / D null effect]

### 2.3 Fallback without C:FAULT

Exact text: `Error code ` + signed decimal code (`%N`) + `\n`. Example: `fault(205)` without C:FAULT
→ `Error code 205\n`. [O]

---

## 3. `C:Fault` (Workbench 1.3.3, `c/Fault`, 2688 bytes)

Standard BCPL command: hunk 0 = command stub (§3.3 bcpl-runtime, 0x13C bytes), hunk 1 = BCPL
code (0x910 bytes), globin: **global 1 (start)** only, max global 138. Internal data:
template `",,,,,,,,,"` (10 anonymous positional keys), argument vector of 25 longs. [O]

### 3.1 Mode selection

On entry, `start` reads **pr_Result2** (read only, `result2(FALSE)`), `input()` and `output()`. [O]

- If `output() = 0`: opens `"*"` (findoutput) and selects it; it will be closed (`endwrite`) at the
  end. Applies to both modes. [O]
- **Result2 ≠ 0 → "fault()" mode**: list of codes = { Result2 }; **no** reading
  of arguments (no rdargs, no access to `input()`). [O]
- **Result2 = 0 → "command line" mode** (`FAULT n …`): see §3.2. [O]

### 3.2 Command-line mode

| Case | Behaviour | Cert. |
|---|---|---|
| `input() = 0` or `rdargs` fails (e.g. more than 10 numbers) | writes `"%S failed - bad args\n"` with %S = **cli_CommandName** (GV 138, name as typed), closes the `*` output if opened, `stop(20)` → return code **20**. | O |
| Each argument present (in order, stops at the first absent one) | converted to a decimal number; success → added to the list **unless it is already there** (duplicates silently ignored); failure → `"argument %S ignored\n"`. | O |
| No argument | nothing is written, return code 0. | O |

Number conversion [O]: non-empty string; a `+` or `-` sign is accepted **only in first
position** and **not alone**; then only digits `0`–`9`; any other character → failure.
`-` makes the value negative. No overflow check. (The conversion passes the value through
Result2 internally, without external effect since Result2 is not re-read afterwards.)

### 3.3 Writing a code

For each code in the list, in order:

1. command-line mode only: `writef("Fault %I3: ", code)` (signed decimal, right-aligned
   on at least 3 columns); [O]
2. `writef(text, code, code)` — the text from the §4 table (without `%`, hence written as is), or
   `"Error %N"` for an unknown code; [O]
3. `wrch('\n')`. [O]

Then closing of the `*` output if it had been opened, and normal return of `start` → return
code **0**. [O]

---

## 4. Message table (C:Fault 1.3.3) [O]

| Code | Text |
|---|---|
| 103 | `insufficient free store` |
| 105 | `task table full` |
| 120 | `argument line invalid or too long` |
| 121 | `file is not an object module` |
| 122 | `invalid resident library during load` |
| 202 | `object in use` |
| 203 | `object already exists` |
| 204 | `directory not found` |
| 205 | `object not found` |
| 206 | `invalid window description` |
| 209 | `packet request type unknown` |
| 210 | `stream name component invalid` |
| 211 | `invalid object lock` |
| 212 | `object not of required type` |
| 213 | `disk not validated` |
| 214 | `disk write-protected` |
| 215 | `rename across devices attempted` |
| 216 | `directory not empty` |
| 218 | `device (or volume) not mounted` |
| 219 | `seek failure` |
| 220 | `comment too big` |
| 221 | `disk full` |
| 222 | `file is protected from deletion` |
| 223 | `file is write protected` |
| 224 | `file is read protected` |
| 225 | `not a valid DOS disk` |
| 226 | `no disk in drive` |
| 232 | `no more entries in directory` |
| any other (including 0 on the command line, 104, 207, 208, 217, 227–231, **303**, negatives) | `Error <n>` (format `"Error %N"`) |

Remarks: 303 does not exist in 1.3 → `Error 303`. The texts are in lower case, without a final full stop.
The newline is not in the strings: it is added by `wrch('\n')`.

---

## 5. C:Copy example: `Can't open zzz for input - object not found`

- C:Copy (1.3.3) has a common error routine: it **reads Result2 first** (to
  protect it from the subsequent I/O), writes Copy's message by `writef(fmt, a, b, c)`, then calls
  **`fault(saved Result2)`** (the only call to global 104 in Copy). [O]
- Copy's format is `"Can't open %S for input - "`: it ends with `" - "` **without** `\n`. [O]
  Other Copy formats followed by fault: `"Can't open %S - "`, `"Could not get information for \"%S\" - "`,
  `"Unable to create directory %S - "`. [O]
- `Open("zzz")` fails with Result2 = 205 → `fault(205)` → C:Fault in fault() mode writes
  `object not found` + `\n`. [O/D for the value 205, standard ERROR_OBJECT_NOT_FOUND]

Final line: `Can't open zzz for input - ` (Copy) + `object not found\n` (C:Fault).
Without an accessible `C:FAULT`: `Can't open zzz for input - Error code 205\n` (ROM fallback).

---

## 6. Test vectors (input → expected output)

`⏎` = `\n`. "C: present" = a C:Fault conforming to §3 accessible under `C:FAULT`.

| # | Situation | Expected output on output() | Return code / Result2 |
|---|---|---|---|
| T1 | `fault(0)` | (nothing) | Result2 unchanged |
| T2 | `fault(205)`, C: present | `object not found⏎` | Result2 = 205 [D if I/O neutral] |
| T3 | `fault(303)`, C: present | `Error 303⏎` | |
| T4 | `fault(232)`, C: present | `no more entries in directory⏎` | |
| T5 | `fault(205)`, C:FAULT absent (no requester even if C: is assigned to an absent volume) | `Error code 205⏎` | Result2 = 205 |
| T6 | `fault(205)` while `output()` = 0, C: present | opens `*`, writes `object not found⏎` to it, closes it | |
| T7 | CLI: `FAULT 205` | `Fault 205: object not found⏎` | rc 0 |
| T8 | CLI: `FAULT 205 303` | `Fault 205: object not found⏎Fault 303: Error 303⏎` | rc 0 |
| T9 | CLI: `FAULT 205 205` | `Fault 205: object not found⏎` (only once) | rc 0 |
| T10 | CLI: `FAULT 5` | `Fault   5: Error 5⏎` | rc 0 |
| T11 | CLI: `FAULT abc 103` | `argument abc ignored⏎Fault 103: insufficient free store⏎` | rc 0 |
| T12 | CLI: `FAULT` | (nothing) | rc 0 |
| T13 | CLI: `fault 1 2 3 4 5 6 7 8 9 10 11` | `fault failed - bad args⏎` | rc 20 |
| T14 | CLI: `FAULT -205` | `Fault -205: Error -205⏎` | rc 0 |
| T15 | `copy zzz to ram:x` (zzz non-existent) | `Can't open zzz for input - object not found⏎` | |

Notes: T13 depends on `rdargs` (§5.4: positional item with no free key → error); the name displayed
is cli_CommandName as typed. T10/T14: `%I3` right-aligns on 3 columns, the width
extends if necessary.

---

## 7. Points for the clean implementation [D]

- `fault()` must **load from disk** (`C:FAULT`), not embed the texts: this is what
  makes the output identical to 1.3 when the Workbench disk provides C:Fault. A home-made C:Fault
  must follow §3 (mode selection by Result2, no prefix in fault() mode).
- Order to respect: load **then** set Result2 (otherwise LoadSeg overwrites it).
- Suppression of requesters during the load (pr_WindowPtr = −1, restored afterwards).
- The fallback contains its own `\n`; so does C:Fault's text (via wrch): the caller must
  not add one.

## Clean-room review

Review of 2026-10-29.

- [x] No 68000 instruction sequence transcribed, no disassembly excerpt.
- [x] **Fixed**: removed the ROM "landmarks" of §2 (entry address of `fault()`, address of the
  BCPL segment, addresses of the BSTR strings, internal offsets of the globin table) and the header
  mention that presented the ROM addresses as landmarks. Kept: global numbers (ABI of the BCPL
  global vector), emitted strings.
- [x] The §2.1 table describes the **observable effects** in their order (load then setting of
  Result2, fallback, unload), an order that conditions the output; it is not an instruction
  walk-through.
- [x] The §4 message table comes from `c/Fault` (Workbench disk), not from the ROM. The only
  ROM data reproduced is the fallback string `Error code %N\n` (emitted, observable text).
