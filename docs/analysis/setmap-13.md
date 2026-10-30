# setmap-13.md — Workbench 1.3.3 `System/SetMap` and the keymap file format

> ANALYSIS track ("dirty"). Sources: the **disk software** `System/SetMap` (German Workbench 1.3.3,
> 4060 bytes, md5 `19b1116414ea728056d18ae94bf59105`, dated 14.03.1989) and `devs/keymaps/d` (1516 bytes, md5
> `5123505e0e910f8670f50dcaa74e10b0`), read as hunk files and disassembled under radare2 in a scratch folder;
> black-box probe **on the real ROM 34.5** under FS-UAE (`tests/setmap_probe.s` + `tests/setmap_probe.sh`,
> author code, results in §5). We describe behaviour, call order and ABI layouts. No instruction
> listing, no ROM routine address.
>
> **Legend**: **[O]** observed (in the SetMap/keymap files, or by the probe on the real ROM: **[O probe]**);
> **[D]** deduced; **[S]** assumed.
>
> Neighbouring specs: `console-keymap-v34.md` (console.device and keymap.resource V34: §1.1 resource layout,
> §5.2 key translation, §5.4 keymap commands); `handlers-v34.md` §2 (CON: handler); `loadseg-v34`-style
> hunk loading is assumed known (HUNK_HEADER / CODE / RELOC32 / END).
>
> The English Workbench 1.3.3 image in `assets/test_adf/` (`[m2]`) has **no** `System/SetMap` and only
> `devs/keymaps/usa1`; the comparison of two SetMap binaries could therefore not be made. `usa1` has the same
> file layout as `d` (§3) [O].

---

## 0. Executive summary

1. SetMap is a Lattice C program (13 hunks; startup code + main + library stubs). It calls only public
   LVOs (list in §2.6). [O]
2. CLI use: `SetMap <name>` — exactly one argument, otherwise `Usage: <argv0> <keymap id>` + LF on Output(),
   **return code 10**. The name is **lower-cased in place** (A–Z, À–Ö, Ø–Þ). [O + O probe]
3. It looks the name up in **keymap.resource's `kr_List`** (the `List` at resource **+$0E**) with exec
   **FindName**, **without Forbid**. Not found ⇒ `LoadSeg("DEVS:keymaps/" + name)`, the first hunk of the
   segment **is** a KeyMapNode, and it is linked with exec **AddHead** (not AddTail) into `kr_List`, again
   without Forbid. The segment is **never unloaded**. [O + O probe]
4. It always sends **CD_SETDEFAULTKEYMAP (12)** with `io_Data = &node->kn_KeyMap`, `io_Length = 32`, on an
   IOStdReq opened with **OpenDevice("console.device", unit −1)** (so `io_Unit` is whatever unit −1 leaves:
   −1 on the real ROM). [O + O probe]
5. From a CLI it then sends the packet **ACTION_DISK_INFO (25)** to **`pr_ConsoleTask`**, waits for the reply
   with **WaitPort on a static port whose signal bit is hard-wired to 16 (never allocated)**, takes the
   **IOStdReq pointer that the CON: handler stores in `id_InUse`**, copies its `io_Unit` into its own
   request and sends **CD_SETKEYMAP (10)** to that unit (the CLI window's console). [O + O probe]
6. Errors are reported with an intuition **AutoRequest** (two text lines + a single `Cancel` gadget) that
   blocks until clicked; return code **20**. [O + O probe]
7. A keymap file is a one-hunk load file (hunk type CODE, no code inside) starting with a
   **KeyMapNode** (14-byte Node + 32-byte KeyMap), all pointers being RELOC32 to the hunk itself. [O]
8. **Hang points** (§6): FindName on a `kr_List` that is not a proper exec List; the unconditional WaitPort for
   the console handler's reply; the blocking error requester. [O for the mechanisms]

---

## 1. Program structure [O]

- Load file: 13 hunks. Hunk 0 = C startup (argument parsing, dos.library, Workbench message), hunk 1 = startup
  globals (SysBase, DOSBase, WBenchMsg, stdin/stdout handles), hunk 2 = `main` + cleanup + error requester,
  hunk 3 = initialised data (strings, a static MsgPort, a static IOStdReq, IntuiText/TextAttr for the
  requester), hunks 4–12 = library glue (dos, exec, icon, intuition stubs; a `printf` over exec RawDoFmt +
  dos Write). Relocations are plain HUNK_RELOC32. The file loads with a 1.3 LoadSeg.
- Memory used at run time: the startup allocates **$19C bytes** (MEMF_PUBLIC | MEMF_CLEAR) for its argv
  block; SetMap allocates 68 + 36 bytes for the DISK_INFO packet (§2.5). Everything else is static in the
  segment.

### 1.1 Startup (C runtime) [O]

In order:

1. AllocMem($19C, MEMF_PUBLIC|MEMF_CLEAR) — failure ⇒ return 20 at once.
2. FindTask(NULL); OpenLibrary("dos.library", 0) — failure ⇒ **Alert($00038007)** (AG_OpenLib | AO_DOSLib,
   recoverable) and return 100.
3. **CLI** (`pr_CLI ≠ 0`): argv[0] = the BSTR `cli_CommandName` (NUL-terminated in place); the argument line
   (A0/D0 of the command) is split on space/tab; a word starting with `"` runs to the closing `"`, inside it
   `*N`/`*n` ⇒ LF and `*E`/`*e` ⇒ ESC, `*x` ⇒ `x`. Trailing spaces/control chars of the line are cut first.
   argc = number of words + 1. Then dos **Input()** and **Output()** are saved as stdin / stdout / stderr.
4. **Workbench** (`pr_CLI = 0`): WaitPort + GetMsg on `pr_MsgPort` (the WBStartup), **CurrentDir**(lock of
   `sm_ArgList[0]`), **Open("NIL:", MODE_OLDFILE)** used as stdin/stdout/stderr and stored in `pr_CIS`,
   `pr_COS`; `pr_ConsoleTask` := `fh_Type` of that file handle if non-zero. argc = 0, argv = WBStartup.
5. main(argc, argv).
6. Exit (normal return or `exit(code)`): stack restored from `pr_ReturnAddr`; WB case: Close(NIL: handle);
   CloseLibrary(dos); WB case: **Forbid + ReplyMsg(WBStartup)**; FreeMem($19C). The exit code is the
   process return code (CLI `cli_ReturnCode`).

---

## 2. main: sequence of calls

### 2.1 Libraries and arguments [O + O probe]

1. OpenLibrary("intuition.library", 0) — failure ⇒ exit 20, **silent** (direct C exit, no cleanup).
2. argc = 0 (**Workbench**): OpenLibrary("icon.library", 0) (failure ⇒ requester "Internal system error" /
   "Cannot open icon.library", exit 20). For each WBArg in order: GetDiskObject(`wa_Name`); if it returns an
   object, FindToolType(`do_ToolTypes`, "KEYMAP"); the first non-NULL value is the name (that DiskObject is
   kept until the cleanup's FreeDiskObject); otherwise FreeDiskObject and next. No KEYMAP ⇒ requester
   "No KEYMAP specified in icons TOOL TYPES" / `e.g. Enter "KEYMAP=usa" in Info menu`, exit 20.
3. argc = 2 (**CLI**, one argument): name = argv[1].
4. Any other argc ⇒ formatted print **`Usage: %s <keymap id>` + LF** with argv[0] on Output(), exit **10**.
   Probe: `sys:System/SetMap` alone prints `Usage: sys:System/SetMap <keymap id>`, `cli_ReturnCode` = 10.
5. The name is lower-cased **in place**: bytes `$41–$5A`, `$C0–$D6`, `$D8–$DE` get bit 5 set. Probe:
   `SetMap D` finds the node `"d"`.

### 2.2 keymap.resource and console.device [O + O probe]

6. **OpenResource("keymap.resource")** — NULL ⇒ requester "Cannot open keymap.resource" / "This program
   requires at least 1.2 roms", exit 20.
7. **OpenDevice("console.device", unit −1, &ioreq, flags 0)** on a **static IOStdReq** (48 bytes in the data
   hunk; `mn_ReplyPort` statically = the static port below; nothing else initialised). Non-zero return ⇒
   requester "Internal system error" / "Cannot open console.device", exit 20.
8. The **static MsgPort** (34 bytes in the data hunk) is initialised **statically**: `ln_Type` = 4
   (NT_MSGPORT), `mp_Flags` = 0 (PA_SIGNAL), **`mp_SigBit` = 16**, `mp_MsgList` an empty list. SetMap only
   writes `mp_SigTask` = FindTask(NULL). **Signal 16 is never allocated** (no AllocSignal).

### 2.3 Finding or loading the keymap [O + O probe]

9. **FindName(resource + $0E, name)** — `kr_List` of keymap.resource, **not** protected by Forbid.
10. **Found**: that node is used; nothing is loaded (probe: `SetMap usa` uses the ROM node; a second
    `SetMap d` / `SetMap D` reuses the loaded node, the list keeps two nodes).
11. **Not found**:
    - path = `"DEVS:keymaps/"` + name, built in a 32-byte buffer. A name of **18 characters or more** ⇒
      exit **10, silent** (no message; direct C exit **without the cleanup**: console.device stays open,
      intuition stays open). Up to 17 characters are accepted.
    - **LoadSeg(path)** — 0 ⇒ requester line 1 "Cannot open keymap file:", line 2 = the full path, exit 20
      (probe: `SetMap nosuch` ⇒ requester "Cannot open keymap file:" / "DEVS:keymaps/nosuch").
    - **64 KB check (only if the console.device `lib_Version` ≤ 34)**: for the first hunk, with `seg` = address
      of its link long and `size` = the long just before it (the hunk's allocation size), if `size < $10000`
      and `seg` and `seg + size` are in different 64 KB pages, the segment is **kept aside** (recorded in a
      table of 4) and **LoadSeg is called again** to obtain another copy at another address; after 4
      rejected copies the next one is accepted whatever its address. Rejected copies are UnLoadSeg'ed at exit;
      the accepted one never is. (The walk to "next hunk" follows the BPTR link as if it were an address, so
      in practice only the first hunk is tested; keymap files have one hunk.) This is a SetMap workaround for
      keymap tables straddling a 64 KB boundary on console ≤ V34 [O SetMap; D: the V34 console mishandles
      such tables — not verified in the ROM, see §7]. Our console reporting version 34 makes SetMap apply it.
    - node = `seg + 4` (first byte of the hunk data). **AddHead(resource + $0E, node)** — exec LVO −240,
      **no Forbid**. Probe: after `SetMap d`, `lh_Head` = the `"d"` node, whose `ln_Succ` = the ROM `"usa"`
      node and `ln_Pred` = `&lh_Head`; `"usa"` keeps `ln_Succ = &lh_Tail`.
    - The segment stays allocated for ever (the tables are referenced by the console).

### 2.4 Default keymap [O + O probe]

12. On the static ioreq: `io_Command` = **12 (CD_SETDEFAULTKEYMAP)**, `io_Data` = **node + 14** (the KeyMap
    inside the KeyMapNode), `io_Length` = **32**, **DoIO**. `io_Unit` is left as OpenDevice(−1) set it
    (−1 on the real ROM: `console-keymap-v34.md` §2.1). `io_Error` is not checked.
    Probe: after `SetMap d`, CD_ASKDEFAULTKEYMAP returns the 8 pointers of the `"d"` node; after `SetMap usa`
    the 8 ROM pointers again.

### 2.5 The current CLI's console [O + O probe]

13. Done only if **all** hold: the task is a process (`ln_Type` = 13, read through `mp_SigTask`), argc ≠ 0
    (not Workbench), `pr_ConsoleTask` ≠ 0.
14. AllocMem(**68**, MEMF_CLEAR) (StandardPacket) and AllocMem(**36**, MEMF_CLEAR) (InfoData); either failure
    ⇒ this step is skipped silently (what was obtained is freed).
15. Packet: `mn_Node.ln_Name` = `&sp_Pkt`, `dp_Link` = the Message, **`dp_Port` = the static port**,
    `dp_Type` = **25 (ACTION_DISK_INFO)**, `dp_Arg1` = **BPTR** of the InfoData. `mn_ReplyPort` is not set.
16. **PutMsg(pr_ConsoleTask, message)** then **WaitPort(static port)** — **no GetMsg**: the reply stays queued
    on the port (inside the segment, which is unloaded at exit) and **signal 16 stays set** in the process's
    `tc_SigRecvd` (probe: after SetMap, bit 16 of the CLI's SigRecvd is set and remains so). `dp_Res1` is not
    checked.
17. If **`id_InUse` (InfoData + $20)** ≠ 0, it is taken as a pointer to the **console IOStdReq of the CON:
    handler**: its **`io_Unit` (+$18)** is copied into SetMap's ioreq, then `io_Command` = **10 (CD_SETKEYMAP)**,
    `io_Data` = node + 14, `io_Length` = 32, **DoIO**. `id_InUse` = 0 ⇒ nothing (no error).
18. FreeMem(InfoData, 36), FreeMem(packet, 68).

What the real ROM's CON: handler returns to ACTION_DISK_INFO [O probe, both before and after SetMap]:
`dp_Res1` = −1, `dp_Res2` = 25 (residue, not meaningful); InfoData: `id_DiskType` (+$18) = `'CON\0'`,
**`id_VolumeNode` (+$1C) = the window**, **`id_InUse` (+$20) = the handler's console IOStdReq** (its
`io_Device` = console.device base, `io_Unit` = the window's ConUnit, whose `cu_Window` = the same window);
the other six longs are left as the caller cleared them (0). The handler answers at once (probe: reply
present at the first poll).

### 2.6 Cleanup and exit [O]

19. `io_Unit` := **−1** (so that CloseDevice does not see the CLI's unit); exit(0) through the cleanup:
    UnLoadSeg of each rejected copy (§2.3), **CloseDevice** if `io_Device` ≠ 0, FreeDiskObject + CloseLibrary
    (icon) if opened, CloseLibrary(intuition), then the startup exit (§1.1). Return code **0** on success
    (probe: `cli_ReturnCode` = 0 after `SetMap d`, `SetMap D`, `SetMap usa`).

Error requester (all error cases): **AutoRequest(window NULL, body, positive NULL, negative "Cancel",
pflags 0, nflags 0, width 440, height 60)** — body = two IntuiTexts in `topaz.font` size 9 attribute,
line 1 pen 0 at (6, 3), line 2 pen 2 at (6, 15), both JAM2 BackPen 1; "Cancel" pen 0 at (6, 3). It appears
on the Workbench screen and **blocks until Cancel is clicked**, then exit **20** through the cleanup.
Probe (`SetMap nosuch` from the startup-sequence): "System Request" window, line 1 "Cannot open keymap file:",
line 2 "DEVS:keymaps/nosuch", gadget "Cancel"; the CLI stays blocked.

Complete list of library calls [O]:

| Library | LVOs used |
|---|---|
| exec | AllocMem −198, FreeMem −210, FindTask −294, PutMsg −366, WaitPort −384, GetMsg −372 (startup, WB), ReplyMsg −378 (startup, WB), Forbid −132 (startup exit, WB), OpenLibrary −552, CloseLibrary −414, OpenResource −498, OpenDevice −444, CloseDevice −450, DoIO −456, FindName −276, **AddHead −240**, RawDoFmt −522, Alert −108 |
| dos | Input −54, Output −60, Write −48, LoadSeg −150, UnLoadSeg −156, Open −30 / Close −36 / CurrentDir −126 (WB start only) |
| intuition | AutoRequest −348 |
| icon (WB start only) | GetDiskObject −78, FindToolType −96, FreeDiskObject −90 |
| console.device | OpenDevice unit −1; DoIO CD_SETDEFAULTKEYMAP (12) and CD_SETKEYMAP (10), io_Length 32 |
| CON: handler | ACTION_DISK_INFO (25), reply on `dp_Port` |

---

## 3. Keymap file format (`devs/keymaps/<name>`) [O]

### 3.1 Load file

- HUNK_HEADER (no resident library names), **1 hunk**; HUNK_CODE (type CODE, although it holds only data),
  `d`: 327 longs (1308 bytes), `usa1`: 281 longs; one HUNK_RELOC32 block **to hunk 0** (39 offsets in `d`),
  HUNK_END. No HUNK_SYMBOL/DEBUG. A 1.3 LoadSeg is enough (no short relocations).
- After LoadSeg: segment = BPTR to the link long; **the KeyMapNode starts at segment + 4** (offset 0 of the
  hunk data). There is no code and no magic: SetMap trusts the file.

### 3.2 Layout (offsets from the start of the hunk data, `d`; `usa1` has the same KeyMap offsets, its name at `$45E`)

| Offset | Content |
|---|---|
| `$00` | `kn_Node`: ln_Succ 0, ln_Pred 0, **ln_Type 0**, ln_Pri 0, ln_Name → `$51A` (`"d"`, NUL) |
| `$0E` | `kn_KeyMap` (32 bytes, `console-keymap-v34.md` §1.1): LoKeyMapTypes → `$4C`, LoKeyMap → `$C4`, LoCapsable → `$2E`, LoRepeatable → `$3D`, HiKeyMapTypes → `$8C`, HiKeyMap → `$1C4`, HiCapsable → `$36`, HiRepeatable → `$45` |
| `$2E` | LoCapsable (8 bytes), `$36` HiCapsable (7), `$3D` LoRepeatable (8, **odd address**), `$45` HiRepeatable (7) |
| `$4C` | LoKeyMapTypes (64 bytes, codes `$00–$3F`), `$8C` HiKeyMapTypes (56 bytes, `$40–$77`) |
| `$C4` | LoKeyMap (64 longs), `$1C4` HiKeyMap (56 longs) |
| `$2A4–$47D` | dead-key descriptors and their modifiable tables (`d` only; usa1 has none) |
| `$47E–$519` | string descriptors (cursor, function keys, Tab, Help) |
| `$51A` | name |

- The byte arrays sit at **odd addresses** (`$3D`, `$45`); the KeyMap longs and the map longs are
  long-aligned relative to the hunk start. Consumers must read the bit arrays and type arrays bytewise.
- RELOC32 covers: ln_Name, the 8 KeyMap pointers, and **every map long whose type has KCF_DEAD or
  KCF_STRING** (they are pointers to descriptors). 1 + 8 + 14 dead + 16 string = 39 in `d`.
- **ln_Type is 0** (no NT_KEYMAP in 1.3): a consumer must not filter on ln_Type.

### 3.3 Types and data used by `d` (German) — enough to validate a console

- Capsable Lo `00 00 FF 07 FF 07 FE 00` (adds `$1A`, `$29`, `$2A` = ü ö ä to the usa set), Hi all 0.
  Repeatable Lo `FF BF FF EF FF EF FF F7`, Hi `47 F4 FF 7F 00 00 00`.
- Types present: `$07` (VANILLA, letters and some symbols), `$03` (SHIFT|ALT, digits and punctuation:
  4 combinations, byte 0 = none … byte 3 = Shift+Alt), `$00` (one value: keypad digits, Backspace `$41`,
  Enter `$43`, Del `$46`, keypad `- / * +`), `$01` (`$30` `<`/`>`), `$04` (`$44` Return: `$0D`, Ctrl ⇒ `$0A`),
  `$02` (`$45` Esc: `$1B`, Alt ⇒ `$9B`), `$05` (keypad `$5A`/`$5B`: SHIFT|CONTROL, 4 combinations: `[` `{`
  and Ctrl `$1B`, `]` `}` and Ctrl `$1D`), `$80` NOP (`$0E`, `$1C`, `$2C`, `$3B`, `$47–$49`, `$4B`,
  `$60–$77`), `$22`/`$23`/`$27` (DEAD with ALT, SHIFT|ALT, VANILLA), `$40`/`$41` (STRING without / with
  SHIFT).
- **STRING** descriptor: per combination a pair (length byte, offset byte), offset relative to the
  descriptor start, then the strings: e.g. `$4C` ↑ ⇒ `9B 41`, Shift ⇒ `9B 54`; `$50` F1 ⇒ `9B 30 7E`,
  Shift ⇒ `9B 31 30 7E`; `$42` Tab ⇒ `09`, Shift ⇒ `9B 5A`; `$5F` Help ⇒ `9B 3F 7E` (same strings as the
  ROM usa map).
- **DEAD** descriptor: per combination a pair (flag, value): flag 0 ⇒ plain byte; **DPF_DEAD (8)** ⇒ the key
  is dead with **index = value**; **DPF_MOD (1)** ⇒ value = offset (from the descriptor start) of a
  translation table.
- Dead keys of `d`: key **`$0C`** (right of ß) unshifted ⇒ dead **`$61`** (acute), Shift ⇒ dead **`$62`**
  (grave), Alt ⇒ `=`, Shift+Alt ⇒ `+`; **Alt-f ⇒ `$61`, Alt-g ⇒ `$62`, Alt-h ⇒ 3 (circumflex), Alt-j ⇒ 4
  (tilde), Alt-k ⇒ 5 (diaeresis)** (with or without Shift).
  **Indices `$61`/`$62` have a non-zero high nibble (6)**: they are "double dead" capable.
- Modifiable keys of `d` (type `$27`: a, e, i, o, u, y(`$31`), n(`$36`); type `$22`: space `$40`): MOD
  tables of **18 bytes** = index 0 (no dead key) + indices 1–5 (single dead key) + 12 entries for a pair of
  dead keys (two rows of 6, for a last dead key of low index 1 or 2). Example e: `65 E9 E8 EA 65 EB` then
  `E9 E9 EA E9 E9 E9 E8 EA E8 E8 E8 E8`; Shift-e: `45 C9 C8 CA 45 CB` + 12. Space has only 6 entries
  (`20 B4 60 5E 7E A8`), Alt-space ⇒ `$A0`.
- Translation index (matches `console-keymap-v34.md` §5.2, confirmed by the probe §5.3): with `p1` = dead
  index of the key pressed just before (`ie_Prev1DownCode/Qual`) and `p2` = that of the key before it
  (`ie_Prev2DownCode/Qual`): `p1` not dead ⇒ k = 0; `p1` dead with high nibble 0 ⇒ k = p1; `p1` dead with high
  nibble h ≠ 0 ⇒ if `p2` is dead, **k = h × (p1 & 15) + (p2 & 15)**, otherwise k = p1 & 15.
- Main German positions: `$15` ⇒ z/Z, `$31` ⇒ y/Y (swap), `$29` ⇒ ö/Ö (Alt `;`/`:`), `$2A` ⇒ ä/Ä
  (Alt `'`/`"`), `$1A` ⇒ ü/Ü (Alt `[`/`{`), `$1B` ⇒ `+`/`*` (Alt `]`/`}`), `$0B` ⇒ ß/`?` (Alt `-`/`_`),
  `$2B` ⇒ `#`/`^`, `$00` ⇒ `` ` ``/`~`.

---

## 4. Probe (`tests/setmap_probe.s`, `tests/setmap_probe.sh`)

- `sp <tag>` is an AmigaDOS command (author code, public ABI only). It logs: return code of the previous
  command (`cli_ReturnCode`), keymap.resource and `kr_List` (each node: name, pointers, LoadSeg size),
  CD_ASKDEFAULTKEYMAP on a unit −1 request, ACTION_DISK_INFO to `pr_ConsoleTask` (InfoData), CD_ASKKEYMAP on
  the unit found in `id_InUse`, and 39 RawKeyConvert vectors with the default keymap (NULL) and with the
  CLI unit's keymap.
- The harness copies a German WB 1.3.3 disk (given by `SETMAP_ADF`, never modified), replaces the
  startup-sequence by: `failat 21`, `sp a`, `SetMap` (no argument), `sp b`, `SetMap d`, `sp c`, `SetMap D`,
  `sp d`, `SetMap usa`, `sp e`, `SetMap d`, `sp W` (plain WaitPort), `SetMap nosuch` (requester),
  boots the **real ROM**, screen shots at each step.
- Command: `SETMAP_ADF=<German WB adf> tests/setmap_probe.sh <out> 400`. Run (2026-10-30) in
  `scratchpad/an_setmap/run5`: all steps reached, requester captured.
- **Harness pitfall**: a dense burst of direct SERDAT writes from the probe makes FS-UAE lose CIA
  interrupts ("out of event2" in `~/FS-UAE/Cache/Logs/fs-uae.log.txt`, see the timer-microhz memory note):
  the machine then spins in the level-6 handler and **looks like a hang right after a packet**. Three early
  runs "hung" that way, including control runs **without any SetMap**. The probe therefore buffers its log
  and drips it out one line per Delay(1). `floppy_drive_speed = 0` (turbo) made it worse. **An apparent
  SetMap hang under FS-UAE must be checked against this artefact before being attributed to the ROM.**

## 5. Probe results (real ROM 34.5) [O probe]

### 5.1 Lists and keymaps

| Step | kr_List (head → tail) | Default keymap (CD_ASKDEFAULTKEYMAP) | CLI unit keymap (CD_ASKKEYMAP) | rc of previous |
|---|---|---|---|---|
| a (boot) | usa (ROM node at resource + $1C) | ROM usa tables | ROM usa | 0 |
| b (after `SetMap`, no arg) | usa | ROM usa | ROM usa | **10** |
| c (after `SetMap d`) | **d, usa** (d at head) | d tables (in the loaded hunk) | **d** | 0 |
| d (after `SetMap D`) | d, usa (no reload) | d | d | 0 |
| e (after `SetMap usa`) | d, usa | **ROM usa** | **ROM usa** | 0 |
| W (after `SetMap d` again) | d, usa | d | d | 0 |

- The `"d"` node = LoadSeg segment + 4; the long before the segment = **$524** (1308 + 8).
- InfoData from the CON: handler, identical at every step: `id_DiskType` `'CON\0'`, `id_VolumeNode` = window,
  `id_InUse` = IOStdReq (io_Device = console base, io_Unit = ConUnit with `cu_Window` = that window), other
  fields 0; `dp_Res1` −1, `dp_Res2` 25.
- CLI process `tc_SigRecvd`: bit 16 set from step c on (left by SetMap's unconsumed reply).

### 5.2 RawKeyConvert after `SetMap d` (identical with keymap NULL and with the CLI unit's keymap)

| Raw code, qualifier | Before (usa) | After (d) |
|---|---|---|
| `$15` / Shift | `y` / `Y` | **`z` / `Z`** |
| `$31` / Shift | `z` / `Z` | **`y` / `Y`** |
| `$29` / Shift | `;` / `:` | **`$F6` ö / `$D6` Ö** |
| `$2A` / Shift | `'` / `"` | **`$E4` ä / `$C4` Ä** |
| `$1A` / Shift / Alt | `[` / `{` / `[` | **`$FC` ü / `$DC` Ü** / `[` |
| `$0B` / Shift | `-` / `_` | **`$DF` ß / `?`** |
| `$0C` / Shift / Alt | `=` / `+` / `=` | **0 bytes (dead) / 0 bytes (dead)** / `=` |
| `$2B` | 0 bytes (NOP) | `#` |
| `$30` / Shift | `<` / `>` | `<` / `>` |
| `$00` | `` ` `` | `` ` `` |
| keypad `$5A`, `$5D` | 0 bytes (NOP) | `[`, `*` |

### 5.3 Dead keys after `SetMap d` (event built with ie_X = Prev1, ie_Y = Prev2)

| Key | Prev1 | Prev2 | usa | d |
|---|---|---|---|---|
| e | `$0C` | – | e | **é `$E9`** |
| e | Shift-`$0C` | – | e | **è `$E8`** |
| Shift-e | `$0C` | – | E | **É `$C9`** |
| a | `$0C` | – | a | **á `$E1`** |
| space | `$0C` | – | space | **´ `$B4`** |
| q | `$0C` | – | q | q |
| e | Alt-f / Alt-g / Alt-h | – | é / è / ê | é / è / ê |
| u | Alt-k | – | ü | ü |
| o | Alt-j | – | õ | õ |
| e | `$0C` | `$0C` | e | é (k = 7) |
| e | `$0C` | Shift-`$0C` | e | **ê (k = 8)** |
| e | `$0C` | Alt-h | e | é (k = 9) |
| e | Alt-h | `$0C` | ê | ê (k = 3) |
| a | Alt-h | `$0C` | â | â |
| e | `$0C` | Alt-f | e | é (k = 7) |

The double-dead results are exactly the bytes of the 18-byte tables at index k = 6 × 1 + (p2 & 15)
(§3.3), which confirms the rule of `console-keymap-v34.md` §5.2 on a real double-dead keymap.

---

## 6. What could hang SetMap (question 4)

1. **FindName on `kr_List`** (resource + $0E): the walk only ends on a node whose `ln_Succ` is NULL (the
   List's tail). If `resource + $0E` is not a real exec List header (lh_Head, lh_Tail = 0, lh_TailPred),
   FindName follows arbitrary pointers: endless loop, bus/address error, or a false match. A
   library-style base (Library node + `lib_Flags`/`lib_pad`/`lib_NegSize` at +$0E) gives
   `lh_Head` = `$0000000C`-like values (here the 68000 exception vectors), i.e. a walk through vector-table
   and ROM-code "pointers". **This is the most likely cause of the reported hang** [D]. Even without a hang,
   AddHead then writes `lh_Head` (+$0E) and the node's `ln_Pred` = resource + $0E, corrupting a library-style
   base.
2. **WaitPort for the CON: handler's reply** (§2.5 step 16) is unconditional: a console handler that does not
   reply to ACTION_DISK_INFO (or replies to `mn_ReplyPort` instead of `dp_Port`, or never runs) blocks
   SetMap for ever. The wait is on **signal 16, which the process never allocated**: Wait/WaitPort must
   work with an unallocated bit (the 1.3 exec does not check tc_SigAlloc) and PutMsg must signal
   `1 << mp_SigBit` of `mp_SigTask` regardless.
3. **`id_InUse` must be 0 or a real IOStdReq of console.device**: a non-zero garbage value makes SetMap
   use `garbage->io_Unit` as a ConUnit for CD_SETKEYMAP (wild write of 32 bytes into "cu_KeyMapStruct").
4. **CD_SETDEFAULTKEYMAP on the unit −1 request**: the console must accept the keymap commands on a request
   opened with unit −1 (whatever its `io_Unit` value) and not treat that request as a window unit; a
   console that dereferences `io_Unit` as a ConUnit here writes into the device base or crashes.
5. **The error requester** blocks until Cancel: if `DEVS:keymaps/d` cannot be loaded (DEVS: not assigned
   to `SYS:devs`, LoadSeg failure, file not found) or `OpenResource("keymap.resource")` /
   `OpenDevice("console.device", −1)` fail, an AutoRequest appears; if AutoRequest does not render or cannot
   receive the click, the startup-sequence appears frozen.
6. The 64 KB retry loop (§2.3) is bounded (at most 4 retries) and cannot hang; it only costs extra LoadSegs.

## 7. ROM behaviours SetMap needs (contract for the implementation)

1. **keymap.resource**: OpenResource("keymap.resource") ≠ NULL; at **resource + $0E** a genuine exec
   **List** (`kr_List`, 14 bytes) whose nodes are KeyMapNodes (Node 14 bytes + KeyMap 32 bytes) and which
   initially holds the ROM node named **`"usa"`** (exact, lower case) — `console-keymap-v34.md` §1.1. The list
   must stay walkable by FindName and modifiable by AddHead **without Forbid** from the caller; nodes may
   have `ln_Type` 0. The resource needs no functions.
2. **console.device**: OpenDevice(unit −1) succeeds and leaves a request on which **CD_SETDEFAULTKEYMAP (12)**
   and **CD_SETKEYMAP (10, with io_Unit replaced by a real ConUnit)** work with `io_Length` = 32 by DoIO;
   CloseDevice with `io_Unit` = −1 afterwards. Only the 8 pointers are copied; the tables stay in the
   segment SetMap leaves loaded. RawKeyConvert / the CDInputHandler must then honour every type of §3.3:
   VANILLA, the 1/2/3-qualifier types, NOP, STRING, DEAD with DPF_DEAD/DPF_MOD and **double dead keys
   (high nibble of the index, 18-byte tables)**, Capsable/Repeatable bit arrays at **odd addresses**.
   `lib_Version` ≤ 34 triggers SetMap's 64 KB retry; our console must simply not have a 64 KB limitation.
3. **CON: handler** (the one behind the CLI's `pr_ConsoleTask`, including the boot CLI): answer
   **ACTION_DISK_INFO (25)** by replying the packet to **`dp_Port`**, with `id_InUse` = its console
   IOStdReq (so that `io_Unit` is the window's ConUnit) — or 0, in which case SetMap silently skips
   the CLI console (then that console keeps the old keymap until a new console is opened, see
   `console-keymap-v34.md` §5.4).
4. **exec**: FindName, AddHead, PutMsg/WaitPort with a statically initialised port using an **unallocated
   signal bit 16**, DoIO, OpenResource, AllocMem/FreeMem, RawDoFmt (usage message), Alert only on dos failure.
5. **dos**: LoadSeg of a one-hunk CODE file with RELOC32 from `DEVS:keymaps/` (DEVS: assigned at boot);
   UnLoadSeg; Input/Output/Write; `cli_CommandName`, `cli_ReturnCode`, `pr_ConsoleTask`, `pr_CLI`,
   `pr_ReturnAddr` as in the 1.3 ABI (C startup).
6. **intuition**: AutoRequest with a NULL window, two-line body, negative gadget only, for the error paths.

## 8. Open points

1. The supposed V34 console bug with keymap tables crossing a 64 KB boundary (reason for SetMap's retry) was
   not looked for in the ROM nor probed.
2. The Workbench (icon) start path was read but not probed.
3. Keystrokes typed for real (keyboard → input.device → console) after SetMap were not probed; the
   translation was validated through RawKeyConvert only (same code path as the input handler,
   `console-keymap-v34.md` §6.1).

---

## Clean-room review

- [x] No instruction sequence transcribed or paraphrased, from the ROM or from SetMap; no ROM routine
  address. SetMap is described by its calls, arguments, order and visible effects.
- [x] Data reproduced are ABI/interoperability data: structure offsets and sizes (KeyMapNode, KeyMap,
  InfoData, StandardPacket, IOStdReq), LVO numbers and command/packet codes, message strings, and a few
  bytes of the `d` keymap file needed as test vectors (disk data, not ROM).
- [x] The probe is author code (`tests/setmap_probe.s`, header "TEST ASSET, NOT ROM code") using only the
  public ABI; results are black-box observations of the real ROM.
