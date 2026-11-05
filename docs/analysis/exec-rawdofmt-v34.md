# exec.library 34.2 — RawDoFmt: behavioural spec

> **ANALYSIS** track ("dirty"), `coverage-v34.md` §7 rank 11. Source: **black-box calls on the real ROM**
> `assets/kick34005.A500` under Amiberry (A500 preset, cycle-exact, 512 KB chip + 512 KB slow, no disk), 2026-11-05.
> Method: the ROM was left at its "insert disk" picture; the debugger stopped a task at the entry of exec `Wait`
> (user mode), masked interrupts in SR for the duration of the experiment, allocated a work block with an injected
> `AllocMem` call, then called `RawDoFmt` through the library vector (`ExecBase − 522`) once per test, with a return
> trampoline and the caller's stack in that block. The PutChProc routines were three debugger-written stand-ins of
> one or two instructions each: "store the byte at A3 and advance A3", "add one to the long at A3" (to count very
> long outputs), and a bare return on which a debugger breakpoint read (and, for §3.3, overwrote) the registers at
> every character. Output, registers after the call and the lowest stack byte written were read back each time;
> interrupts and the saved task state were restored afterwards. The ROM code was **not** read, disassembled or
> traced for this page. No program was written; the probe to write on the implementation side is described in §8.
> This document describes **behaviours**, **values**, **register contracts** and **test vectors**. It contains no
> ROM instruction sequence, no pseudo-code of the routine and no ROM address.
> Related pages: `alert-v34.md` §3 (Guru text built with `%08lx`), `workbench-task-v34.md` §6.2–§6.4 (memory title),
> `setmap-13.md` (usage message through a `printf` glue), `loadwb-13.md` (error message to `Output()`).
>
> **Levels of proof**: **[O]** observed on the real ROM · **[D]** deduced from observations (reasoning, stated) ·
> **[S]** assumption, not verified.
>
> Notation: `␣` is a space, `\0` a zero byte, `\|` a vertical bar (table escaping). "W $xxxx" is a 16-bit data item,
> "L $xxxxxxxx" a 32-bit one, "L →"text"" a 32-bit pointer to that NUL-terminated string. Test ids (E1, D3, …) refer
> to the tables of §7.

## 0. Summary for the implementer

- **LVO −522** `RawDoFmt(FormatString A0, DataStream A1, PutChProc A2, PutChData A3)`. A6 need not be ExecBase
  (a call with A6 = an arbitrary value works). No documented result. [O]
- **Grammar** (§2): `%` `[-]` `[0]` `[width digits]` `[.limit digits]` `[l]` *type*, in exactly this order. Known
  types: **`d`** (signed decimal), **`x`** (hexadecimal, **upper-case** digits, unsigned), **`s`** (C string),
  **`c`** (character). **No `%b`, `%u`, `%X`, `%o`, `%i`, `%p`, `*`, `+`, space or `#`** in V34. [O]
- **Any other type character is echoed** (sent to PutChProc as is), reads no data and gets no padding — `%%` is just
  this rule. A type character that is the **terminating zero** is echoed too and the scan **continues past the end
  of the format string** (§2.6). [O]
- **Data**: `d`, `x`, `c` read a **word** (2 bytes) or, with `l`, a **long** (4 bytes); `s` always reads a long
  pointer. Items are **packed**, no alignment: `%d%ld` reads 2 then 4 bytes. `%d` sign-extends the word, `%x` does
  not. `%c` sends the low byte; a **zero byte gives an empty field** (nothing sent). A NULL `%s` pointer is not
  special: the string at address 0 is printed (empty on a running 1.3, whose location 0 holds a zero long). [O]
- **Width and limit** are taken modulo 65536. Padding = width − length of the field text, computed in **16 bits and
  signed**: no padding when it is ≤ 0 or ≥ 32768. The **limit** (`.n`, 0 = none) truncates the text of **every**
  type to its first *n* characters, sign included (`%.2d` of 12345 → `12`, `%.1ld` of −5 → `-`). [O]
- **`0` flag**: pads with `0` instead of a space, for **every** type including `%s` and `%c`, **on the padding side
  only**: right-justified zeros go **before** the sign (`%05d` of −42 → `00-42`), left-justified zeros go **after**
  the text (`%-05d` of 42 → `42000`). [O]
- **PutChProc** (§3) is called once per output character with the character in the **low byte of D0** (upper 24
  bits not cleared) and **A3 = PutChData as left by the previous call** (the `move.b d0,(a3)+` idiom works). The
  **terminating zero is sent** (last call). Inside PutChProc, **A6 is a pointer into RawDoFmt's stack frame, not
  ExecBase**. RawDoFmt relies on PutChProc preserving **D2, D3, D5, D6, A2, A4, A5, A6** (A6 corrupted = crash); it
  does not rely on D0, D1, D4, D7, A0, A1, nor on A3 being preserved. [O]
- **Exit** (§1.2): D2–D7 and A2, A4–A6 preserved, **A3 restored** to its entry value; D0, D1, A0 undefined; **A1 =
  address just past the last data item read** (when PutChProc preserves A1). Stack: PutChProc is entered **68 bytes**
  below the caller's SP (72 when padding is involved), return addresses included. [O]

## 1. Calling contract

### 1.1 Entry [O]

| Register | Contents |
|---|---|
| A0 | format string (NUL-terminated; see §2.6 for a format that ends inside a conversion) |
| A1 | data stream (packed words and longs, §4) |
| A2 | PutChProc (§3) |
| A3 | PutChData, passed to PutChProc in A3 |
| A6 | not used as ExecBase: a call with A6 = `$12345678` gave the same output (`%ld-%s` of 42, "abc" → `42-abc\0`) |

The other registers are ignored. RawDoFmt was called in user mode with the interrupt mask raised to 7 by the
debugger; the mask was still 7 on return, so it does not lower it [O]. Calls from supervisor mode (the Guru text,
`alert-v34.md` §3) are a known use [D]; whether RawDoFmt touches anything but its stack frame and PutChProc was not
checked beyond the guard areas around the output buffer and the stack [S: it writes nothing else].

### 1.2 Exit [O]

Markers `$1111000n` were placed in D0–D7, A4, A5 before every call of §7 (A0–A3, A6 carrying the arguments):

| Register | After the call |
|---|---|
| D2–D7, A2, A4, A5, A6 | preserved (every vector) |
| A3 | **restored to its entry value**, even when PutChProc advanced it (store PutChProc: A3 back at the buffer start; a PutChProc that only added 1 to A3 at each of 4 calls: A3 back to its entry value) |
| A1 | **just past the last data item read** (vectors: "Data read" column = A1 after − A1 before). It is the A1 left by the **last PutChProc call**: a PutChProc that changed A1 at every call made A1 on exit equal to that value, while the output stayed right (RawDoFmt keeps its data cursor elsewhere) |
| D0 | undefined: the D0 of the last PutChProc call (the terminating zero), upper bits varying (`$00000000`, `$FFFF0000`, `$FFFFFF00`, or the caller's upper bits when no conversion ran) |
| D1 | undefined (`$FFFFFFFF`, `$00000000`, or the caller's D1 seen) |
| A0 | undefined: unchanged when no `d`/`x`/`c`/`s` conversion ran, else a pointer into RawDoFmt's (released) stack frame or into the last `%s` string |
| SR | condition codes undefined (Z was set on every return observed) |

V34 has no documented return value; later AutoDocs describe one in D0, which a V34 caller cannot rely on [D].

### 1.3 Stack [O]

Stack depth was measured as the lowest byte modified in a pattern-filled area below the caller's SP:

- PutChProc is entered with **SP = caller's SP − 68**: 4 bytes of return address to the caller, 60 bytes of
  RawDoFmt frame, 4 bytes of return address to RawDoFmt. Same figure for every vector without padding, the
  11-character `-2147483648` included.
- Every vector with padding (width larger than the text) reached **72 bytes**, and every vector without padding
  68: 4 more bytes are in use while pad characters are sent.
- Total requirement: 72 bytes + what PutChProc itself uses. The digit buffer lives inside the 60-byte frame (A0 on
  exit pointed into it).

## 2. Format syntax

### 2.1 Grammar [O]

Characters other than `%` are sent to PutChProc one by one; the terminating zero is sent and ends the call. A `%`
starts a conversion, read in this fixed order:

1. optional `-` (left-justify),
2. optional `0` (zero fill),
3. optional width: decimal digits,
4. optional `.` followed by optional decimal digits (limit; `.` with no digits = limit 0),
5. optional `l` (long data),
6. the **type**: the next character, whatever it is.

There is no other flag and no repetition: in `%0-5d` the `0` is the flag and the type is `-` (output `-5d`); in
`%--5d` the type is the second `-`; in `%l5d` (l before the width) the type is `5` (output `5d`); in `%ll d` the
type is the second `l` (output `l d`). Extra leading zeros are width digits: `%005d` of 3 → `00003` (W12),
`%00005d` of 5 → `00005` (M7).

### 2.2 Types [O]

| Type | Data read | Field text |
|---|---|---|
| `d` | word, sign-extended; with `l`: long | signed decimal, `-` for negatives, no `+`, no leading zeros (`0` for zero) |
| `x` | word, zero-extended; with `l`: long | hexadecimal with **upper-case** `A`–`F`, no prefix, no leading zeros (`0` for zero) |
| `c` | word; with `l`: long | one character = the **low byte**; a zero byte gives an **empty** text |
| `s` | long pointer (with or without `l`) | the bytes up to the first zero; a NULL pointer reads address 0 like any other |
| anything else | nothing | the type character itself, sent once, **no padding, no limit** (§2.5) |

`%x` of the word `$FFFF` is `FFFF` (not sign-extended); `%x` given a long `$12345678` reads only `$1234`.

### 2.3 Width and padding [O]

- The width digits are accumulated and only their value **modulo 65536** matters (`%65536d` and `%2147483648d` behave
  as width 0, M20/M38).
- Padding count = (width − length of the field text after the limit), as a **signed 16-bit** value. Padding happens
  only when it is positive: `%32768d` of 5 sends 32 767 pads + `5`; `%32769d` of 5 sends no pad (32 768 is negative
  in 16 bits); `%40000s` of "abc" sends no pad (K1–K8, counted with a counting PutChProc).
- Pad character: space, or `0` with the `0` flag. Pads go **before** the text, or **after** it with `-`. The `0`
  flag does not move the sign: `%05d` of −42 → `00-42`, `%012ld` of −123456 → `00000-123456`; with `-` the zeros
  follow the text: `%-05d` of 42 → `42000`, `%-05ld` of −5 → `-5000`, `%-06x` of 15 → `F00000`.
- The `0` flag applies to strings and characters: `%08s` of "hello" → `000hello`, `%03c` of `A` → `00A`.
- A text longer than the width is printed whole (`%2d` of 12345 → `12345`).
- Width and padding apply to an empty field: `%5s` of "" → five spaces, `%3c` of a zero byte → three spaces.

### 2.4 Limit (precision) [O]

- `.n` keeps at most the first *n* characters of the field text, for **all four types**: `%.3s` of "hello" →
  `hel`; `%.2d` of 12345 → `12`; `%5.1d` of 123 → `␣␣␣␣1`; `%.2x` of `$ABCD` → `AB`; `%8.2ld` of −1234 →
  `␣␣␣␣␣␣-1`; `%3.5d` of −32768 → `-3276`. It never adds digits (`%.3d` of 5 → `5`).
- `.0`, `.` alone, and values that are 0 modulo 65536 mean **no limit**. `.65537` acts as `.1` (M21).
- Values 32768–65535 printed a 5-character string whole (K9–K11, M35); whether they mean "no limit" or a very large
  limit was not distinguished (it would take a string longer than 32 767 bytes) [O for the vectors, S beyond].
- The limit is applied before the padding is computed (`%9.1s` of "hello" → 8 spaces + `h`).
- For `%c` it has no visible effect (one character at most).

### 2.5 Unknown types and `%%` [O]

The type character is sent to PutChProc and the scan resumes after it; flags, width, limit and `l` are discarded and
no data is read. Seen with `%`, `u`, `X`, `b`, `q`, `y`, `D`, `i`, `o`, `p`, `*`, `+`, space, `h`, `L`, `l` (second
`l`), `-` (second flag), and digits after `l`. Hence `%%` → `%`, `%5%` → `%` (no padding), `%l%` → `%`, `%lu` → `u`,
`%X` → `X`, and **`%b` → `b` with its BPTR left unread** (vector A6 of V9: a conversion after it would take the
BPTR as its data).

### 2.6 A format that ends inside a conversion [O]

When the zero byte that terminates the format string comes where the **type** is expected (`"abc%"`, `"abc%5"`,
`"abc%l"`, `"abc%-"`, `"abc%0"`, `"abc%."`, `"abc%5.2"`), it is handled as an unknown type: the **zero byte is sent
to PutChProc** as a character, and the scan **continues with the bytes that follow the terminator**, as format text,
until a zero byte in normal text position, which is sent and ends the call. Vectors (format bytes in hex, including
what follows the terminator in memory):

| Format bytes | Data | Output bytes (hex) | Data read |
|---|---|---|--:|
| `61 62 63 25 00` `58 59 5A 00` (`abc%`, then `XYZ`) | — | `61 62 63 00 58 59 5A 00` | 0 |
| `61 62 63 25 35 00` `58 59 00` (`abc%5`, then `XY`) | — | `61 62 63 00 58 59 00` | 0 |
| `61 62 63 25 6C 00` `51 00` (`abc%l`, then `Q`) | — | `61 62 63 00 51 00` | 0 |
| `61 62 25 00` `25 6C 64 21 00` (`ab%`, then `%ld!`) | L $0000004D | `61 62 00 37 37 21 00` | 4 |
| `61 25 2E 00` `52 00` (`a%.`, then `R`) | — | `61 00 52 00` | 0 |
| `78 25 00` `00` (`x%`, then a zero) | — | `78 00 00` | 0 |
| `61 25 2D 00` `53 00` (`a%-`, then `S`) | — | `61 00 53 00` | 0 |
| `61 25 30 00` `54 00` (`a%0`, then `T`) | — | `61 00 54 00` | 0 |

A format ending in a lone `%` therefore reads past its end: a caller (or our implementation, if it chooses to stop
there) must know which bytes follow. The V10 vectors of §7 had zero bytes after the terminator.

## 3. PutChProc

### 3.1 Call [O]

- Called with `JSR` through **A2 as it stands at that moment**: a PutChProc that changed A2 to another routine
  redirected every following character to it.
- One call per output character, in order, including pad characters and the **final zero byte** (sent once, last).
  A zero byte is also sent for the case of §2.6. `%c` with a zero byte sends nothing.
- **D0**: the character in the **low byte**; the upper 24 bits are **not cleared** (seen: the caller's D0 upper bits
  for the leading literal characters, `$FFFF00xx` while a number is sent, `$000000xx` for strings). PutChProc must use
  only the low byte.
- **A3**: PutChData; on the first call the entry A3, afterwards **whatever the previous PutChProc call left in A3**
  (a PutChProc adding 1 to A3 saw `A3`, `A3+1`, `A3+2`, `A3+3` on its four calls). On return from RawDoFmt, A3 is
  the entry value again (§1.2).
- **A6**: a pointer into RawDoFmt's own stack frame, **not ExecBase**, even when RawDoFmt was entered with A6 =
  ExecBase. A PutChProc that needs a library base must load it itself.
- **A1**: the data pointer, already past the item being printed. **A2**: PutChProc. **A4**: just past the format
  character being processed. **A5**: just past the field-text character being sent. The other registers carry
  RawDoFmt's working values. These are observations, not a contract.
- SP: 68 or 72 bytes below the caller's SP (§1.3).

### 3.2 What PutChProc may change [O]

Each register was overwritten at **every** PutChProc call (D registers with `$DEAD0000`, address registers with
the address of a zeroed area; A2 with the address of another valid PutChProc) during
`A%ldB%sC%5dD%xE%-4s|` with L 123456, L →"hello", W −9, W $001F, L →"abc" (normal output:
`A123456BhelloC␣␣␣-9D1FEabc␣\|\0`, 16 data bytes read):

| Register overwritten | Result |
|---|---|
| D0, D1, D4, D7, A0 | output unchanged |
| A1 | output unchanged; A1 on exit = the overwritten value |
| A3 | (each call sees the previous call's A3, §3.1) |
| D2 | pad characters after the first become zero bytes (`C␣\0\0-9`) |
| D3 | the left-justified padding is lost (`abc\|` instead of `abc␣\|`) |
| D5 | conversions cut short after their first character (`A1BhC␣␣␣D1Ea␣\|`; the `-9` is lost) |
| D6 | right-justified padding shortened (`C␣-9` instead of `C␣␣␣-9`) and left padding lost |
| A2 | the following characters go to the new routine |
| A4 | output ends after the first character (the format is read from the zeroed area) |
| A5 | after its first character, each field text is replaced by zero bytes |
| A6 | crash (the machine went to an exception and lost the debugger connection) |

So a 1.3-compatible PutChProc must preserve D2–D7 and A2, A4–A6 (D4/D7 are not used by this RawDoFmt but are
callee-saved by convention) and may change D0, D1, A0, A1 and A3 (A3 changes are kept for the next call) [O for the
table; the rule is the usual exec convention, D for D4/D7].

### 3.3 Common PutChProcs [D]

- `move.b d0,(a3)+` then return: stores the text **and its terminating zero** in the buffer at PutChData; the buffer
  needs `length + 1` bytes (more with the §2.6 case). This is how the Workbench builds its memory title
  (`workbench-task-v34.md` §6.4).
- A PutChProc that writes to a file or the serial port receives the final zero byte too and must skip it if it is
  not wanted.

## 4. Data stream [O]

- The cursor starts at A1 and advances by 2 for `d`, `x`, `c` without `l`, by 4 with `l`, and by 4 for every `s`;
  unknown types (including `b`) read nothing. Items are **contiguous**: `%c%ld` reads a word at +0 and a long at +2
  (A5: `A7`), `%ld%d` a long then a word (A3: 6 bytes).
- Callers that pass arguments as consecutive longs (C `printf` glue, the Workbench title: `workbench-task-v34.md`
  §6.4) must use `%ld`, `%lx`, `%lc`; a `%d` on such a stream prints the **high word** of the long (D10: `%d` of the
  long `$00010002` prints `1` and reads 2 bytes).
- Alignment of A1 is not checked: a word or long item at an odd address would raise an address error on a 68000
  [S, not tried].

## 5. Differences from the usual descriptions [O vs. public documentation]

What V34 does where the later (2.0+) AutoDocs or a C `printf` would suggest otherwise:

1. **No `%b`** (BSTR): echoed as `b`, and its argument is not consumed, which shifts every following argument.
2. **No `%u`, no `%X`**; `%x` is upper-case.
3. The **limit applies to numbers** (truncation from the right, sign included), not only to strings.
4. The **`0` flag** pads strings and characters too, puts zeros **before the sign**, and with `-` pads **zeros on
   the right**.
5. **Flag order is fixed** (`-` then `0`); anything else after `%` is the type.
6. **Unknown types are echoed** without consuming data; `%%` is that rule.
7. A **lone `%` at the end** swallows the terminator and keeps reading past the end of the format (§2.6).
8. `%c` with a **zero byte** sends nothing.
9. **No result in D0**; the next data address is in A1 on exit.
10. PutChProc receives **D0 with garbage in the upper bits** and **A6 ≠ ExecBase**; RawDoFmt depends on PutChProc
    preserving A6, A4, A5, A2 and D2, D3, D5, D6.
11. Width and limit are 16-bit quantities (§2.3, §2.4).

## 6. Known users and the vectors that matter to them [D]

| User | Format and data | Vectors |
|---|---|---|
| Guru text (`alert-v34.md` §3) | `%08lx` twice on longs | X8, M54 |
| Workbench memory title (`workbench-task-v34.md` §6.4) | `"Workbench release 1.2.  %ld free memory"`, long argument, store PutChProc | M53 |
| LoadWB 1.3 error message (`loadwb-13.md`) | text to `Output()` through RawDoFmt | V1, V2 |
| SetMap 1.3 usage message (`setmap-13.md`) | `printf` glue over RawDoFmt (longs on the stack) | V2, V5, V9 |
| CLI commands and C programs with a `printf` over RawDoFmt | any; `%ld`/`%s` mostly | all |

## 7. Test vectors

All outputs below are the exact bytes sent to PutChProc (store PutChProc into a buffer pre-filled with `$AA`), in
call order, final zero included. "Data read" = A1 after − A1 before, in bytes. Strings: "hello", "abc" and "" are
NUL-terminated, longword-aligned C strings. B3/B0/B5 are BPTRs to the BSTRs `\x03abc` (followed by `XYZ`), `\x00`,
`\x05Hello`. Unless a format string ends with `%` (V10), the bytes after its terminator are zero.

#### V1 Plain text, %% and the terminator

| # | Format | Data | Output bytes | Data read |
|---|---|---|---|--:|
| E1 | (empty) | — | `\0` | 0 |
| E2 | `abc` | — | `abc\0` | 0 |
| E3 | `%%` | — | `%\0` | 0 |
| E4 | `a%%b%%` | — | `a%b%\0` | 0 |

#### V2 %d and %ld

| # | Format | Data | Output bytes | Data read |
|---|---|---|---|--:|
| D1 | `%d` | W $04D2 | `1234\0` | 2 |
| D2 | `%d` | W $FFFB | `-5\0` | 2 |
| D3 | `%d` | W $8000 | `-32768\0` | 2 |
| D4 | `%d` | W $0000 | `0\0` | 2 |
| D5 | `%d` | W $FFFF | `-1\0` | 2 |
| D6 | `%ld` | L $FFFFFFFF | `-1\0` | 4 |
| D7 | `%ld` | L $80000000 | `-2147483648\0` | 4 |
| D8 | `%ld` | L $7FFFFFFF | `2147483647\0` | 4 |
| D9 | `%ld` | L $00000000 | `0\0` | 4 |
| D10 | `%d\|` | W $0001, ($0002 not read) | `1\|\0` | 2 |
| D11 | `%ld` | L $000186A0 | `100000\0` | 4 |
| M25 | `%ld\|` | L $80000001 | `-2147483647\|\0` | 4 |
| M50 | `%d` | W $8000 | `-32768\0` | 2 |
| M39 | `%ldx%dx` | L $00010000, W $7FFF | `65536x32767x\0` | 6 |

#### V3 %x and %lx

| # | Format | Data | Output bytes | Data read |
|---|---|---|---|--:|
| X1 | `%x` | W $ABCD | `ABCD\0` | 2 |
| X2 | `%lx` | L $DEADBEEF | `DEADBEEF\0` | 4 |
| X5 | `%x` | W $0000 | `0\0` | 2 |
| X6 | `%x` | W $FFFF | `FFFF\0` | 2 |
| X7 | `%lx` | L $00000000 | `0\0` | 4 |
| X8 | `%08lx` | L $0000001F | `0000001F\0` | 4 |
| X9 | `%8lx\|` | L $00000ABC | `␣␣␣␣␣ABC\|\0` | 4 |
| X10 | `%-8lx\|` | L $00000ABC | `ABC␣␣␣␣␣\|\0` | 4 |
| X11 | `%04x` | W $000A | `000A\0` | 2 |
| M16 | `%08x\|` | W $8000 | `00008000\|\0` | 2 |
| M17 | `%lx\|` | L $0A0B0C0D | `A0B0C0D\|\0` | 4 |
| M26 | `%x\|` | W $1234, ($5678 not read) | `1234\|\0` | 2 |
| M51 | `%-06x\|` | W $000F | `F00000\|\0` | 2 |
| M52 | `%0x\|` | W $0000 | `0\|\0` | 2 |
| M54 | `%08lx.%08lx` | L $0000000B, L $00C026E2 | `0000000B.00C026E2\0` | 8 |

#### V4 %c and %lc

| # | Format | Data | Output bytes | Data read |
|---|---|---|---|--:|
| C1 | `%c` | W $0041 | `A\0` | 2 |
| C2 | `%c%c` | W $0041, W $0042 | `AB\0` | 4 |
| C3 | `%lc` | L $00000043 | `C\0` | 4 |
| C4 | `%c` | W $4142 | `B\0` | 2 |
| C5 | `%5c\|` | W $0041 | `␣␣␣␣A\|\0` | 2 |
| C6 | `%-3c\|` | W $0041 | `A␣␣\|\0` | 2 |
| C7 | `%03c` | W $0041 | `00A\0` | 2 |
| C8 | `%lc` | L $41424344 | `D\0` | 4 |
| M9 | `%c\|` | W $0000 | `\|\0` | 2 |
| M24 | `%c` | W $00E9 | `\xE9\0` | 2 |
| M27 | `%-5c\|` | W $0041 | `A␣␣␣␣\|\0` | 2 |
| M28 | `%.3c\|` | W $0041 | `A\|\0` | 2 |
| M29 | `%.0c\|` | W $0041 | `A\|\0` | 2 |
| M45 | `%lc%c` | L $00004142, W $0043 | `BC\0` | 6 |
| M46 | `A%cB` | W $0000 | `AB\0` | 2 |
| M47 | `%3c\|` | W $0000 | `␣␣␣\|\0` | 2 |
| M55 | `%c%c%c` | W $000A, W $000D, W $00FF | `\n\r\xFF\0` | 6 |
| M18 | `%05c\|` | W $002A | `0000*\|\0` | 2 |

#### V5 %s

| # | Format | Data | Output bytes | Data read |
|---|---|---|---|--:|
| S1 | `%s` | L →"hello" | `hello\0` | 4 |
| S2 | `%s\|` | L →"" | `\|\0` | 4 |
| S3 | `%8s\|` | L →"hello" | `␣␣␣hello\|\0` | 4 |
| S4 | `%-8s\|` | L →"hello" | `hello␣␣␣\|\0` | 4 |
| S5 | `%.3s\|` | L →"hello" | `hel\|\0` | 4 |
| S6 | `%8.3s\|` | L →"hello" | `␣␣␣␣␣hel\|\0` | 4 |
| S7 | `%-8.3s\|` | L →"hello" | `hel␣␣␣␣␣\|\0` | 4 |
| S8 | `%3s\|` | L →"hello" | `hello\|\0` | 4 |
| S9 | `%08s\|` | L →"hello" | `000hello\|\0` | 4 |
| S10 | `%.0s\|` | L →"hello" | `hello\|\0` | 4 |
| S11 | `%.9s\|` | L →"hello" | `hello\|\0` | 4 |
| S12 | `%ls\|` | L →"hello" | `hello\|\0` | 4 |
| S13 | `%5s\|` | L →"" | `␣␣␣␣␣\|\0` | 4 |
| M3 | `%-.2s\|` | L →"hello" | `he\|\0` | 4 |
| M10 | `%10.0s\|` | L →"abc" | `␣␣␣␣␣␣␣abc\|\0` | 4 |
| M13 | `%-1s\|` | L →"abc" | `abc\|\0` | 4 |
| M14 | `%.1s%.1s\|` | L →"abc", L →"hello" | `ah\|\0` | 8 |
| M21 | `%.65537s\|` | L →"hello" | `h\|\0` | 4 |
| M30 | `%05.2s\|` | L →"hello" | `000he\|\0` | 4 |
| M35 | `%.32768s\|` | L →"hello" | `hello\|\0` | 4 |
| M42 | `%-8.0s\|` | L →"abc" | `abc␣␣␣␣␣\|\0` | 4 |
| M49 | `%9.1s\|` | L →"hello" | `␣␣␣␣␣␣␣␣h\|\0` | 4 |

#### V6 Field width and flags

| # | Format | Data | Output bytes | Data read |
|---|---|---|---|--:|
| W1 | `%5d\|` | W $002A | `␣␣␣42\|\0` | 2 |
| W2 | `%-5d\|` | W $002A | `42␣␣␣\|\0` | 2 |
| W3 | `%05d\|` | W $002A | `00042\|\0` | 2 |
| W4 | `%05d\|` | W $FFD6 | `00-42\|\0` | 2 |
| W5 | `%-05d\|` | W $002A | `42000\|\0` | 2 |
| W6 | `%0-5d\|` | ($002A not read) | `-5d\|\0` | 0 |
| W7 | `%2d\|` | W $3039 | `12345\|\0` | 2 |
| W8 | `%5ld\|` | L $FFFFFFD6 | `␣␣-42\|\0` | 4 |
| W9 | `%012ld\|` | L $FFFE1DC0 | `00000-123456\|\0` | 4 |
| W10 | `%30d\|` | W $0007 | `␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣7\|\0` | 2 |
| W11 | `%1d\|` | W $FFF9 | `-7\|\0` | 2 |
| W12 | `%005d\|` | W $0003 | `00003\|\0` | 2 |
| W13 | `%10x\|` | W $BEEF | `␣␣␣␣␣␣BEEF\|\0` | 2 |
| W14 | `%-10lx\|` | L $0000BEEF | `BEEF␣␣␣␣␣␣\|\0` | 4 |
| W15 | `%010lx\|` | L $0000BEEF | `000000BEEF\|\0` | 4 |
| M5 | `%5ld\|` | L $00000005 | `␣␣␣␣5\|\0` | 4 |
| M6 | `%--5d\|` | ($0005 not read) | `-5d\|\0` | 0 |
| M7 | `%00005d\|` | W $0005 | `00005\|\0` | 2 |
| M8 | `%300d\|` | W $0001 | `␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣␣1\|\0` | 2 |
| M11 | `%0.2d\|` | W $FFFB | `-5\|\0` | 2 |
| M12 | `%-05ld\|` | L $FFFFFFFB | `-5000\|\0` | 4 |
| M19 | `%-0d\|` | W $0005 | `5\|\0` | 2 |
| M20 | `%65536d\|` | W $0005 | `5\|\0` | 2 |
| M33 | `%65535d\|` | W $0005 | `5\|\0` | 2 |
| M38 | `%2147483648d\|` | W $0005 | `5\|\0` | 2 |
| M40 | `%05ld\|` | L $00000000 | `00000\|\0` | 4 |

#### V7 Precision on numbers

| # | Format | Data | Output bytes | Data read |
|---|---|---|---|--:|
| P1 | `%.3d\|` | W $0005 | `5\|\0` | 2 |
| P2 | `%.2d\|` | W $3039 | `12\|\0` | 2 |
| P3 | `%5.1d\|` | W $007B | `␣␣␣␣1\|\0` | 2 |
| P4 | `%.3ld\|` | L $0001E240 | `123\|\0` | 4 |
| P5 | `%.2x\|` | W $ABCD | `AB\|\0` | 2 |
| P6 | `%8.2ld\|` | L $FFFFFB2E | `␣␣␣␣␣␣-1\|\0` | 4 |
| M1 | `%.0d\|` | W $007B | `123\|\0` | 2 |
| M2 | `%.d\|` | W $007B | `123\|\0` | 2 |
| M15 | `%3.5d\|` | W $8000 | `-3276\|\0` | 2 |
| M31 | `%-08.3lx\|` | L $00ABCDEF | `ABC00000\|\0` | 4 |
| M37 | `%10.8ld\|` | L $F8A432EB | `␣␣-1234567\|\0` | 4 |
| M41 | `%08.3ld\|` | L $0001E240 | `00000123\|\0` | 4 |
| M48 | `%.1ld\|` | L $FFFFFFFB | `-\|\0` | 4 |

#### V8 Conversions V34 does not know

| # | Format | Data | Output bytes | Data read |
|---|---|---|---|--:|
| U1 | `%u` | ($FFFF not read) | `u\0` | 0 |
| U2 | `%lu` | ($FFFF $FFFF not read) | `u\0` | 0 |
| U3 | `%u\|` | ($0005 not read) | `u\|\0` | 0 |
| X3 | `%X` | ($ABCD not read) | `X\0` | 0 |
| X4 | `%lX` | ($0000 $001F not read) | `X\0` | 0 |
| B1 | `%b\|` | (L →B3, not read) | `b\|\0` | 0 |
| B2 | `%b\|` | (L →B0, not read) | `b\|\0` | 0 |
| B3 | `%6b\|` | (L →B3, not read) | `b\|\0` | 0 |
| B4 | `%-6b\|` | (L →B3, not read) | `b\|\0` | 0 |
| B5 | `%.2b\|` | (L →B5, not read) | `b\|\0` | 0 |
| B6 | `%lb\|` | (L →B5, not read) | `b\|\0` | 0 |
| B7 | `%2b\|` | (L →B5, not read) | `b\|\0` | 0 |
| Q1 | `%q\|` | ($0041 not read) | `q\|\0` | 0 |
| Q2 | `%y\|` | — | `y\|\0` | 0 |
| Q3 | `%D\|` | ($0005 not read) | `D\|\0` | 0 |
| Q4 | `%i\|` | ($0005 not read) | `i\|\0` | 0 |
| Q5 | `%5q\|` | ($0005 not read) | `q\|\0` | 0 |
| Q6 | `%5%\|` | — | `%\|\0` | 0 |
| Q7 | `%l%\|` | — | `%\|\0` | 0 |
| Q8 | `%lq\|` | — | `q\|\0` | 0 |
| Q9 | `%-q\|` | — | `q\|\0` | 0 |
| Q10 | `%o\|` | ($0008 not read) | `o\|\0` | 0 |
| Q11 | `%p\|` | ($0000 $1234 not read) | `p\|\0` | 0 |
| Q12 | `%ll␣d\|` | — | `l␣d\|\0` | 0 |
| Q13 | `%lld\|` | ($0000 $0005 $0000 $0006 not read) | `ld\|\0` | 0 |
| Q14 | `%h␣d` | — | `h␣d\0` | 0 |
| Q15 | `%*d\|` | ($0005 $0009 not read) | `*d\|\0` | 0 |
| Q16 | `%␣d\|` | ($0005 not read) | `␣d\|\0` | 0 |
| Q17 | `%+d\|` | ($0005 not read) | `+d\|\0` | 0 |
| M4 | `%l5d\|` | ($0000 $0005 not read) | `5d\|\0` | 0 |
| M22 | `%L␣d\|` | ($0005 not read) | `L␣d\|\0` | 0 |
| M32 | `%5.3%\|` | — | `%\|\0` | 0 |
| M36 | `%-l5d\|` | ($0000 $0005 not read) | `5d\|\0` | 0 |
| M43 | `%5%\|` | — | `%\|\0` | 0 |
| M44 | `%-5%\|` | — | `%\|\0` | 0 |

#### V9 Data stream layout

| # | Format | Data | Output bytes | Data read |
|---|---|---|---|--:|
| A1 | `%d%d` | W $0001, W $0002 | `12\0` | 4 |
| A2 | `%d%ld` | W $0001, L $00000002 | `12\0` | 6 |
| A3 | `%ld%d` | L $00000001, W $0002 | `12\0` | 6 |
| A4 | `%d%s` | W $0001, L →"abc" | `1abc\0` | 6 |
| A5 | `%c%ld` | W $0041, L $00000007 | `A7\0` | 6 |
| A6 | `%d␣%x␣%c␣%s␣%b` | W $0001, W $002A, W $005A, L →"abc", (L →B3, not read) | `1␣2A␣Z␣abc␣b\0` | 10 |
| A7 | `%ld%ld%ld` | L $00000001, L $00000002, L $00000003 | `123\0` | 12 |
| M53 | `Workbench␣release␣1.2.␣␣%ld␣free␣memory` | L $00064190 | `Workbench␣release␣1.2.␣␣410000␣free␣memory\0` | 4 |

#### V10 Format ending inside a conversion (see §2.6 for what follows)

| # | Format | Data | Output bytes | Data read |
|---|---|---|---|--:|
| Z1 | `abc%` | — | `abc\0\0` | 0 |
| Z2 | `abc%5` | — | `abc\0\0` | 0 |
| Z3 | `abc%l` | — | `abc\0\0` | 0 |
| Z4 | `abc%-` | — | `abc\0\0` | 0 |
| Z5 | `abc%0` | — | `abc\0\0` | 0 |
| Z6 | `abc%.` | — | `abc\0\0` | 0 |
| Z7 | `abc%5.2` | — | `abc\0\0` | 0 |

#### V11 Very large widths and limits (counting PutChProc)

PutChProc added 1 to the long at A3 per character; the count includes the final zero byte.

| # | Format | Data | Characters sent | Data read |
|---|---|---|--:|--:|
| K1 | `%32768d` | W $0005 | 32 769 (32 767 spaces, `5`, `\0`) | 2 |
| K2 | `%32769d` | W $0005 | 2 | 2 |
| K3 | `%32768d` | W $000C | 32 769 (32 766 spaces, `12`, `\0`) | 2 |
| K4 | `%32767d` | W $0005 | 32 768 | 2 |
| K5 | `%32770d` | W $FFFB | 3 | 2 |
| K6 | `%40000s` | L →"abc" | 4 | 4 |
| K7 | `%32770s` | L →"abc" | 32 771 | 4 |
| K8 | `%-32768d` | W $0005 | 32 769 | 2 |
| K9 | `%.32768s` | L →"hello" | 6 | 4 |
| K10 | `%.65535s` | L →"hello" | 6 | 4 |
| K11 | `%.32769s` | L →"hello" | 6 | 4 |

#### V12 NULL pointers

| # | Setup | Format | Data | Output bytes |
|---|---|---|---|---|
| N1 | location 0 holds its normal 1.3 contents (a zero long, then ExecBase at 4) | `[%s]` | L $00000000 | `[]\0` |
| N2 | the debugger wrote `Z\0` at location 0 for the call | `[%s]` | L $00000000 | `[Z]\0` |
| N3 | same | `[%5s]` | L $00000000 | `[␣␣␣␣Z]\0` |
| N4 | normal location 0; **A0 = 0** (format pointer NULL) | — | — | `\0` |

N2/N3 show that a NULL `%s` is not special-cased: the bytes at address 0 are printed. N4 follows from the zero
byte at address 0.

#### V13 Registers

| # | Test | Observation |
|---|---|---|
| R1 | every vector of V1–V10 with markers in D0–D7, A4, A5 | exit registers as in §1.2 |
| R2 | A6 = `$12345678` on entry, `%ld-%s` with L 42, L →"abc" | `42-abc\0`, 8 data bytes read |
| R3 | bare PutChProc traced on `Ab%ld%s` with L −7, L →"abc", caller's D0 = `$11110000` | 8 calls; D0 = `$11110041`, `$11110062`, `$FFFF002D`, `$FFFF0037`, `$00000061`, `$00000062`, `$00000063`, `$00000000`; A3 = entry A3 at every call; A1 = data start for the first two, data + 4 for the number, data + 8 afterwards; A6 = the same stack address at every call, not ExecBase; SP = caller's SP − 68 |
| R4 | PutChProc adding 1 to A3 at each call, format `xyz` | A3 seen: entry, +1, +2, +3; A3 on exit = entry value |
| R5 | per-register overwrite at every PutChProc call | §3.2 table |
| R6 | stack depth | 68 bytes without padding, 72 with (§1.3), every vector |

Vector count: 162 in V1–V10, 8 in §2.6, 11 in V11, 4 in V12, and the register tests R2–R6 (R5 = 15 runs).

## 8. Probe to write on the implementation side (`tests/rawdofmt_probe.s`)

A CLI program (KS 1.x hunk executable) that runs the vectors above against `RawDoFmt` (LVO −522) and writes one
line per vector, so that the same program gives the oracle on the real ROM and the result on ours:

1. **Buffers**: a 1 KB output buffer filled with `$AA` before each call; a data block written per vector with the
   items of the table (words and longs packed in order, pointers to the probe's own strings "hello", "abc", "" and
   to the BSTRs of §7, all longword-aligned); the format string copied into a 64-byte area that is **zeroed** first,
   so that the bytes after its terminator are zero (V10), or filled with the exact bytes of §2.6 for those eight
   vectors.
2. **Store PutChProc**: store the low byte of D0 at A3 and advance A3, then return. After the call, print the id,
   the output bytes up to the first `$AA` in hex, and A1 after − A1 before. Compare with the tables.
3. **Exit registers (R1)**: load D0–D7, A4, A5 with distinct markers before the call, save them after, report each
   register that changed (expected: D0, D1, A0, A1 only, A3 equal to its entry value).
4. **A6 (R2)**: call once with A6 = `$12345678` (restore it afterwards).
5. **Recording PutChProc (R3)**: a PutChProc that appends D0 (whole long), A3, A6 and SP to a table in memory, for
   `Ab%ld%s`; check the low bytes, that A3 never changes, that A6 differs from ExecBase, and print SP difference with
   the SP saved just before the call (expected 68).
6. **A3 bump (R4)**: a PutChProc that adds 1 to A3 and records it.
7. **Tolerance (R5)**: one PutChProc per register among D0, D1, D4, D7, A0, A1 that stores the character through a
   copy of A3 and then sets that register to `$DEAD0000` (address registers: the address of a zeroed area); the
   output must stay `A123456BhelloC␣␣␣-9D1FEabc␣|\0`. The registers RawDoFmt depends on (D2, D3, D5, D6, A2, A4, A5,
   A6) are **not** to be clobbered by the probe on our side: a different but better-behaved implementation may
   tolerate more, and A6 crashes the real ROM.
8. **Counting PutChProc (V11)**: add 1 to the long at A3; print the count.
9. **NULL (V12)**: N1 and N4 as is; N2/N3 under `Disable()`, writing `Z\0` at address 0 and restoring the two
   original bytes before `Enable()`.
10. **Stack (R6)**: run each padding/no-padding pair with SP at the top of a 256-byte area filled with `$5A` (switch
    the stack inside the probe around the call) and print the lowest byte written; expected 68/72 on the real ROM,
    any value is acceptable on ours as long as it is documented (it is part of the budget callers allow).

Output must not use RawDoFmt itself (print through dos `Write` with the probe's own hex routine).

## Open points

1. **Limit values 32768–65535**: printed a 5-character string whole; whether they act as "no limit" or as a large
   limit is not known (§2.4).
2. **Odd DataStream or odd `%s` pointer**: not tried; expected address error / byte reads respectively [S].
3. **Calls from supervisor mode and interrupts**: not exercised here (the Guru path uses RawDoFmt in supervisor
   mode, `alert-v34.md` §3); no difference expected, since RawDoFmt needs no library base [S].
4. **PutChProc preserving D4 and D7**: this RawDoFmt does not need it (§3.2); whether any 1.3 user relies on
   RawDoFmt tolerating a PutChProc that changes them is unknown.
5. Whether RawDoFmt writes anything besides its stack frame was only checked around the output buffer and the stack
   area [S].
6. The observations were made with debugger-injected calls in the boot strap task with interrupts masked; the
   probe of §8 run from a CLI process should give the same figures but has not been run on the real ROM.

## Clean-room review

Review of 2026-11-05.

- [x] No 68000 instruction sequence transcribed or paraphrased, no disassembly excerpt, no ROM routine or data
  address. The ROM code was not read: every fact comes from calls through the public library vector with
  debugger-written inputs, and from the outputs, registers and stack contents read back.
- [x] The PutChProc stand-ins (one or two instructions written by the debugger, see the page header) are generic idioms of the
  public RawDoFmt contract, not ROM code; §8 describes the probe in words only.
- [x] The register observations of §3.1 (which register holds which cursor at PutChProc entry) are values seen at
  the public PutChProc boundary, given as observations and not as a design to copy; §3.2 states the contract.
- [x] The only numbers are the public LVO, register names, stack depths, counts, and inputs/outputs of our own test
  vectors (the RAM addresses of the test buffers are not given).
- [x] No probe code was written by the analysis track.
