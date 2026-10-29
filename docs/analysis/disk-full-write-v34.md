# Disk full on write: Join, Write, OFS handler (V34) — behavioural spec

> ANALYSIS track. Everything that follows was **observed** by running the real ROM
> (`assets/kick34005.A500`, read only) under FS-UAE, or read in the `C:Join` command of the
> Workbench 1.3.3 disk (BCPL program, list of its global calls only). No instruction
> sequence transcribed, no ROM routine address. Legend: **[O]** observed on screen or on
> the disk image, **[J]** read in `C:Join` (list of the globals called), **[?]** not established.

## 1. Setup

- ADF: copy of WB 1.3.3 + files `a` (8772 bytes) and `b` (9972 bytes) at the root, 287 free blocks.
  startup-sequence: 5 × `join a b a as jN` + `echo "JN"`, then `echo "FIN"`.
  Each `jN` is 27516 bytes = 57 OFS data blocks (488 bytes per block) + 1 header = 58 blocks.
  After 4 joins 55 blocks remain → the 5th is 3 blocks short.
- Probe `tests/diskfull.s` (ASSET DE TEST): dos Open/Write and raw `ACTION_WRITE` (87) packets
  sent directly to the handler's port (`fh_Type`, `dp_Arg1 = fh_Args`), with display of
  dp_Res1/dp_Res2, Write()/IoErr(), `Seek(fh,0,OFFSET_CURRENT)` and `id_NumBlocksUsed`.
  Disk: blank WB 1.3.3 (325 free blocks), write of a 200000-byte source.
- The requesters were closed from the keyboard with **left Amiga + B** (= right button, "Cancel").

## 2. Q1 — What one sees during and after the join that runs out of space [O]

1. Joins 1 to 4 run normally ("J1"… "J4").
2. During the 5th join a **system requester** appears: window titled "System Request",
   placed at the top left **on the screen of the CLI window** (window of the requesting process),
   text on three lines:
   ```
   Volume
   Workbench1.3
   is full
   ```
   buttons **Retry** (left) and **Cancel** (right). The Join process is blocked as long as the requester
   is open (verified: it stays displayed at least 5 min without an answer).
3. Each **Cancel** makes the requester disappear; it **reappears for each subsequent Write** that
   fails. In this scenario: **3 requesters** (see the count in §4).
4. After the last Cancel, Join **displays nothing** (no error message), ends **without a visible
   error code**: the startup-sequence **continues** ("J5" then "FIN" are displayed, then the
   `1>` prompt; FailAt 10 is not triggered). Join therefore returns 0 (cf. §5: it does not examine the
   result of its writes).
5. Disk image after the run:
   - `j1`…`j4` = 27516 bytes each; **`j5` = 26344 bytes** in the file header.
   - Contents of `j5`: the first 26344 bytes = exactly the start of `a+b+a`.
   - The header has **54 data blocks**, the last block carries a data size of **488**
     (full) whereas the file size (26344) only counts 480 of it. The remaining 8 bytes of the
     last block contain **the first 8 bytes of the last refused write** (start of the
     last 372-byte chunk of `a`), not the logical continuation of the file. → header/block inconsistency
     produced by the real 1.3 (xdftool reports it: "file size mismatch got=26352 want=26344").
   - Root block: **bitmap valid flag = 0** (bitmap marked invalid on the disk), the bitmap
     on disk stayed in its state from before the joins (xdftool `info` reads 287 free whereas the
     disk is full). Run killed ~60 s after "FIN": it is not known whether 1.3 would have rewritten it
     later **[?]**.

## 3. Q2 — Results of the handler and of Write() when space runs out

### 3.1 Probe vectors (real ROM) [O]

Blank WB disk, `df0:big` in MODE_NEWFILE, source 200000 bytes (more than the free space).
`used` = id_NumBlocksUsed (the disk counts **1758** usable blocks, value at saturation).

| Step | Call | Res1 / returned value | Res2 / IoErr | pos after | used after | Requester |
|---|---|---|---|---|---|---|
| A | Open NEWFILE | fh (≠ 0) | $1574 (residue, not meaningful) | 0 | 1434 | no |
| B | raw ACTION_WRITE packet, 200000 bytes, pos 0 | **−1** | **221** (ERROR_DISK_FULL) | **0** | **1758** (disk full) | **no** |
| C | raw ACTION_WRITE packet, 1000 bytes | **1000** | $FFFF (not meaningful) | 1000 | 1758 | no |
| D | dos `Write(fh, 1000)` | **1000** | $FFFF | 2000 | 1758 | no |
| E (run v3) | dos `Write(fh, 200000)` from pos 2000 | **does not return** | — | — | — | **yes, one** ("Volume Workbench1.3 is full"); after Cancel no more requester, Write still blocked > 4 min |

Reading of these vectors:

- **Failure = all or nothing on the result side**: a write that does not fit returns **Res1 = −1** and
  **Res2 = 221**, and the **file position does not advance** (pos stays 0 after B) — never a
  partial number of bytes.
- But the **blocks allocated during the failed write stay attached to the file** (used goes to
  1758; the image shows 320 data blocks chained in the header of `big`, size 0 as long as the
  file is not closed). The following writes **reuse** these blocks: C and D succeed
  (1000 bytes each) although the disk is full.
- The contents of the blocks were indeed copied until the space ran out (cf. the 8 bytes of `j5`):
  the copy is not cancelled, only the position and the size are not advanced.
- dos `Write()` returns the handler's **Res1** (1000 here); `IoErr()` returns Res2. The Res2 of
  **successful** writes are not meaningful ($FFFF observed): do not rely on them.
- On Join (writes of ≤ 400 bytes via Write), each chunk that no longer fits is refused entirely:
  20th chunk of the 3rd copy of `a` (400 bytes) while 8 bytes remained → refused, then the 2
  following chunks (400 bytes, 372 bytes) → refused, hence 3 requesters and the size 26344 = 18744 + 19×400.

### 3.2 Not established [?]

- **E blocked**: a **large** dos `Write()` that overflows after reusing the already allocated blocks
  does not return after Cancel (observed once, run v3; run v2 identical with Seek/Info in addition).
  Join's Writes (≤ 400 bytes, one block to allocate) do return. Cause not elucidated: probe v4
  (same overflow by **raw** packet, to find out whether the blocking and the requester come from the handler
  or from dos) was interrupted before a result.
- Res1/Res2 returned by `Write()` **after Cancel**: not measured directly (Join does not test them,
  and step E of the probe does not return). Hypothesis consistent with B: −1 / 221.
- Effect of **Retry**: not tested.
- Close of a file whose last write failed: the recorded size = position reached
  by the successful writes (j5 = 26344) **[O]**; the rest (bitmap revalidated or not) **[?]**.

## 4. Q4 — Does the "Volume … is full" requester exist in 1.3, and who displays it? [O] / [?]

- **Yes**, it exists and appears on a disk full on write (§2). Text: `Volume` / volume
  name / `is full`, buttons `Retry` / `Cancel`, on the screen of the window of the writing process.
- **A raw ACTION_WRITE packet that fails (B) causes NO requester**: it returns −1/221 straight
  away. The dos `Write()`s that fail (Join, E) cause one.
  → Strong hint that the requester is posted **on the dos side (Write function / its retry loop)** and not
  by the handler, on the model of the other dos disk requesters (global 114, "errorreq",
  cf. `bcpl-runtime-v34.md` §8.2). **Caveat**: B is the first write of an empty file and E
  a write beyond already allocated blocks; probe v4 which was to remove this ambiguity (raw
  packet in E's situation) did not succeed → attribution **[?]**, to be confirmed.
- One requester per failing Write; Cancel → the Write returns the failure to the caller (Join case: the
  program continues); no extra requester on close.

## 5. Q3 — How Join writes and detects failure [J]

`C:Join` (1056 bytes, BCPL, data in the ROM runtime's globals):

1. Stores `output()` (global 66), reads the arguments with `rdargs` (78) on the template
   `,,,,,,,,,,,,,,,AS=TO/K` (15 sources + destination). Failure or no 1st source or no AS:
   `writef` (74) "Bad args" then `stop(20)`.
2. Opens the destination by `findoutput` (60); failure: "Can't open %S" then `stop(20)`.
   Otherwise `selectoutput` (62).
3. For each non-empty source (at most 15): `findinput` (59); failure: `endwrite` (64, closes the
   partial destination — **it is not deleted**), reselects the old output,
   "Can't open %S", `stop(20)`. Otherwise `selectinput` (61), then loop:
   - `readbytes` (40) into a local buffer of **400 bytes** (read first),
   - then `testflags(1)` (37, Ctrl-C): if set → closes the source (`endstream`, 93), `endwrite`,
     reselects the old output, `writes` (73) "**BREAK", `stop(10)`;
   - if the number read is ≤ 0 → end of this source (`endstream`);
   - otherwise **`writebytes(buffer, n)`** (43 = direct `Write(output(), …)`, without `wrch`'s 200-byte
     buffer), **whose return value is ignored**; loop again.
4. End: `endwrite` then `stop(0)`.

Consequences:
- Join **does not detect** the write failure: neither the value returned by Write nor Result2 are
  tested; no message, return code **0**; the startup-sequence continues.
- The only visible feedback to the user is the requester posted during each failed Write.
- The destination file is closed normally and keeps what was written successfully.

## 6. What our ROM must reproduce

1. OFS handler, `ACTION_WRITE` without enough space: **Res1 = −1, Res2 = 221**, file position and
   size **unchanged** (no partial result).
2. The blocks allocated during the failed write stay with the file and are reused by the following
   writes (C/D succeed on a full disk). (Reproducing the partial copy into the last block
   and the size-block inconsistency is not necessary: artefact, not a contract.)
3. dos `Write()` returns the handler's Res1 and IoErr = Res2.
4. Requester "Volume / <volume name> / is full", Retry / Cancel, on the process's screen, **once
   per failing Write**; Cancel → the Write returns the failure (−1, IoErr 221 assumed); Retry →
   new attempt **[?]**. A raw packet does not produce one (at least in case B).
5. Join: writes of 400 bytes via Write, result ignored, exit 0, startup-sequence continues,
   no error text. End-to-end vector: on the jw ADF, `j5` = **26344 bytes**, screen
   "J1…J5", "FIN", 3 requesters to cancel.

## 7. Test vectors

| Vector | Input | Expected (real 1.3) |
|---|---|---|
| V1 | jw ADF (startup 5 × join), Cancel at each requester | 3 "Volume Workbench1.3 is full" requesters; screen J1…J5, FIN; `j5` = 26344 bytes = prefix of a+b+a |
| V2 | probe, step B | `B FFFFFFFF 000000DD`; pos 0; used 1758; no requester |
| V3 | probe, steps C, D | `000003E8` each; pos 1000 then 2000 |
| V4 | probe, `Write` 200000 from pos 2000 | 1 requester; **does not return** after Cancel (observed 1.3 behaviour, not necessarily to be reproduced) **[?]** |

## Clean-room review

- [x] No instruction sequence of the ROM nor of `C:Join` transcribed: only BCPL global
      numbers (ABI already documented), ABI constants (87, 221, 1006) and
      observed behaviours.
- [x] No ROM routine address.
- [x] The elements not established are marked **[?]**.
- [x] Probe `tests/diskfull.s`: author code, header "ASSET DE TEST, PAS du code ROM".
