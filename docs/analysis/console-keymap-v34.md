# console-keymap-v34.md — console.device ("console ri 34.1") and keymap.resource ("keymap ri 34.1")

> ANALYSIS track ("dirty"). Sources: ROM `assets/kick34005.A500` read under radare2 (base `$FC0000`) and
> black-box probe **on the real ROM** under FS-UAE (`tests/con_probe.s` + `tests/con_probe.sh`, author
> code, vectors in §8). We describe the **what**: values, sequences, ABI layouts, order of the visible
> effects. No instruction sequence transcribed or paraphrased, no ROM routine address.
>
> **Legend**: **[O]** observed directly (reading of the data/behaviour in the ROM, or output
> of the probe) — specified as **[O ROM]**, **[O probe]** or **[O ROM+probe]** when both agree;
> **[D]** deduced from converging observations; **[S]** assumed.
>
> Neighbouring specs (not duplicated): `handlers-v34.md` §2 (CON:/RAW: on the dos side: it is the handler, not
> console.device, that does the line editing and the echo); `intuiticks-repeat-v34.md` (key repeat
> and IEQUALIFIER_REPEAT qualifier produced by input.device); `keyboard-handshake-v34.md`
> (raw keyboard codes); `monkey-startup.md` §6 (RawKeyConvert(RETURN) = `$0D`).
>
> Probe conditions: PAL A500, 512 KB chip + 512 KB slow, no system floppy (ROM default
> Preferences: **topaz 9** font, **10 × 9** pixel cell), 640 × 200 Workbench screen with
> 2 planes (colours 0 blue, 1 white, 2 black, 3 orange).

---

## 0. Executable summary

1. console.device is a COLDSTART resident pri 20 that **requires keymap.resource** (at its
   init it copies the KeyMap of the **first** node of keymap.resource's list as the default keymap; empty
   list ⇒ init fails) and installs itself in input.device's chain as a **pri 0** handler. [O ROM]
2. OpenDevice: unit **−1** ⇒ mere access to the functions (io_Unit = −1); any other unit ⇒
   io_Data **must** be a Window (otherwise io_Error = −1); io_Unit receives the **ConUnit** (677 bytes,
   public part = `devices/conunit.h` 1.3). The unit number and io_Length are ignored. [O ROM+probe]
3. Drawing is done **directly in the window's RastPort** (RastPort state saved then
   restored at each operation, layer locked by LockLayerRom); there is **no character
   buffer**: nothing is redrawn after a REFRESHWINDOW. [O ROM]
4. CMD_WRITE interprets a subset of ANSI/ECMA-48 (complete tables in §3–§4); after ESC c:
   **LNM, ASM and AWM active** (LF = CR+LF, automatic scrolling, automatic line wrap). [O ROM+probe]
5. CMD_READ returns **already cooked bytes** (RawKeyConvert with the unit's keymap, or
   `CSI … |` / `CSI … R` / `CSI … r` reports) as soon as at least one byte is available; circular buffer of
   255 bytes; **no echo, no line editing**. [O ROM+probe]
6. RawKeyConvert (LVO −48) walks **the whole chain** of events, only processes IECLASS_RAWKEY, returns
   the number of bytes or **−1** if the buffer is too short; one-level dead keys (double dead key
   provided for by the format but unused by "usa"). Model validated on 1,680 combinations (§6). [O ROM+probe]
7. keymap.resource V34 has **no functions**: 74 bytes (Node + List + one KeyMapNode "usa" whose
   KeyMap points into the ROM). [O ROM+probe]

---

## 1. Initialisation and structures

### 1.1 keymap.resource [O ROM+probe]

- Resident "keymap.resource", COLDSTART, **pri 100**, version 34 (idString "keymap ri 34.1 (18 Aug 1987)").
- Init: AllocMem(**74**, **MEMF_CLEAR** only — not MEMF_PUBLIC), then:
  - `+$00` Node: ln_Type = **8** (NT_RESOURCE), ln_Pri 0, ln_Name = `"keymap.resource"`;
  - `+$0E` List `kr_List` (14 bytes; lh_Type left at 0);
  - `+$1C` **KeyMapNode** (46 bytes) copied from the ROM: Node (succ/pred updated to be the
    only element of kr_List, ln_Type 0, ln_Pri 0, ln_Name = `"usa"`) followed by the **KeyMap** (8 pointers
    to the ROM tables, §5);
  - AddResource. No vector table (0 LVOs, no MakeFunctions).
- Probe: OpenResource("keymap.resource") ⇒ ln_Type 8; lh_Head = resource + `$1C`; ln_Succ of that
  node = address of lh_Tail; name "usa".

KeyMap layout (public ABI `devices/keymap.h`, 32 bytes): `+0` km_LoKeyMapTypes, `+4` km_LoKeyMap,
`+8` km_LoCapsable, `+12` km_LoRepeatable, `+16` km_HiKeyMapTypes, `+20` km_HiKeyMap, `+24` km_HiCapsable,
`+28` km_HiRepeatable. "Lo" = codes `$00–$3F` (tables of 64 types, 64 longs, 8 + 8 bytes of bits),
"Hi" = codes `$40–$77` (56 types, 56 longs, 7 + 7 bytes of bits). Bit of a code `c` in a bit
array: byte `(c & $3F) >> 3`, bit `c & 7`.

### 1.2 console.device: resident and base [O ROM]

- Resident "console.device", COLDSTART, **pri 20**, NT_DEVICE, version 34, idString
  "console ri 34.1 (18 Aug 1987)". Base of 184 bytes (lib_PosSize), 6 standard vectors + 2:
  **−42 CDInputHandler**, **−48 RawKeyConvert**.
- Init, in order: opens graphics.library (failure ⇒ init fails); OpenResource("keymap.resource")
  (absent or empty list ⇒ closes graphics, init fails); **copies the 32 bytes of the KeyMap of the first
  node** as the device's default keymap; initialises the list of units; opens **input.device
  unit 0** and sends it **IND_ADDHANDLER** (9) with an Interrupt structure: ln_Type NT_INTERRUPT,
  **ln_Pri 0**, ln_Name `"console.device"`, is_Data = device base, is_Code = vector −42 (hence
  CDInputHandler(A0 = events, A1 = base)). Failure to open input.device: the device is still
  returned (without handler). intuition.library is only opened at the **first OpenDevice** on a window.
- Expunge: refused (LIBF_DELEXP flag set) as long as lib_OpenCnt ≠ 0; otherwise IND_REMHANDLER (10),
  closing of input.device, intuition and graphics, freeing of the base.

### 1.3 ConUnit (public ABI `devices/conunit.h` 1.3) [O ROM+probe]

Allocated size: **677 bytes** (`$2A5`), MEMF_PUBLIC, cleared. The public part occupies `$00–$127`;
the rest is private (buffers, parser state). Public fields and actual use:

| Off. | Field | V34 use |
|---|---|---|
| `$00` | cu_MP (MsgPort, 34 b) | ln_Name `"console.device"`, NT_MSGPORT; its list receives the pending CMD_READs |
| `$22` | cu_Window | io_Data of the OpenDevice |
| `$26/$28` | cu_XCP / cu_YCP | logical cursor position (column/line, base 0) |
| `$2A/$2C` | cu_XMax / cu_YMax | last column / last line (base 0) |
| `$2E/$30` | cu_XRSize / cu_YRSize | cell size = TxWidth + TxSpacing / TxHeight of the RastPort |
| `$32/$34` | cu_XROrigin / cu_YROrigin | origin of the text area, pixels relative to the window |
| `$36/$38` | cu_XRExtant / cu_YRExtant | last pixel of the text area (inclusive) |
| `$3A/$3C` | cu_XMinShrink / cu_YMinShrink | smallest size (useful pixels) seen since the last recomputation; 9999 = "nothing to clear" |
| `$3E/$40` | cu_XCCP / cu_YCCP | cell where the cursor block is **drawn** (= XCP/YCP after each write) |
| `$42` | cu_KeyMapStruct (32 b) | the unit's keymap (copy of the default keymap at open) |
| `$62` | cu_TabStops[80] (UWORD) | tab stops sorted in increasing order, terminated by `$FFFF` |
| `$102–$121` | cu_Mask … cu_TxSpacing | copy of the console's RastPort state (§2.2) |
| `$122` | cu_Modes[3] | bit n ⇒ byte n/8, bit n%8; **20 = LNM, 21 = ASM, 22 = AWM** |
| `$125` | cu_RawEvents[3] | bit n = IECLASS class n reported raw (n ≤ 18) |

Probe, just after OpenDevice on a bordered 640 × 200 window (BorderLeft 4, Top 12, Right 18,
Bottom 2), topaz 9: XCP = YCP = 0, **XMax = 60, YMax = 19**, XRSize 10, YRSize 9, XROrigin 4,
YROrigin 12, XRExtant 613, YRExtant 191, Modes = `00 00 70`, RawEvents = 0, FgPen 1, BgPen 0,
DrawMode 1 (JAM2), AlgoStyle 0, Mask `$FF`, tab stops 0, 8, 16, … (§3.4).

---

## 2. OpenDevice, CloseDevice, BeginIO

### 2.1 OpenDevice [O ROM+probe]

- lib_OpenCnt is incremented **first, in all cases**, including on failure (it is
  never decremented again: leak of one count per failure; probe: 2 → 3 after a failure). [O]
- **unit = −1**: io_Unit := −1, io_Error unchanged (0), success. Used to obtain io_Device in order to call
  RawKeyConvert / CDInputHandler. CloseDevice of such a request only does the decrement. [O]
- **other unit (any value)**: io_Data = 0 ⇒ **io_Error = −1** (IOERR_OPENFAIL) and
  io_Device := 0; insufficient memory ⇒ same. Otherwise:
  1. allocates/initialises the ConUnit (MsgPort, cu_Window := io_Data, keymap := **copy of the device's current
     default keymap**); io_Unit := ConUnit;
  2. inserts the unit **at the head** of the device's list of units;
  3. performs the equivalent of **ESC c** (§3.6): font = current font of the window's RastPort at the
     time of opening (stored, restored by each ESC c), geometry computed, text area
     cleared (SMART_REFRESH window), cursor displayed at (0,0);
  4. opens intuition.library if not already done;
  5. the unit becomes the **active unit** (recipient of the keys) if no active window is
     yet known to the device **or** if its window is the known active window (§6.1).
  io_Length (size of the Window) is ignored. [O ROM; probe: io_Error 0, io_Unit = ConUnit]
- Several units can share a window; each has its own cursor and tab stops, and draws
  into the same RastPort. [O probe]

### 2.2 Access to the RastPort [O ROM; probe §8.4]

Each drawing operation (and each whole CMD_WRITE): LockLayerRom(rp->Layer), saving of
`cp_x/cp_y`, Mask/FgPen/BgPen/AOlPen, DrawMode/AreaPtSz, AreaPtrn, Minterms, Font, AlgoStyle/TxFlags,
TxHeight/TxWidth, TxBaseline/TxSpacing of the window's RastPort, installation of the ConUnit's values
(`$102–$121`), drawing, copy of the RastPort's values back into the ConUnit, restoration of the RastPort,
UnlockLayerRom. These locks are nestable (counter). The program that shares the window therefore
finds its RastPort intact.

### 2.3 CloseDevice [O ROM]

Unit −1: nothing. Otherwise: removes the unit from the list; if it was the active unit, **no unit
is active any more** (even if another unit is open on the same window — probe §8.6); frees the 677
bytes. The cursor block **is not erased** from the window; the pending CMD_READs are not
replied to (up to the caller to cancel them before). io_Unit and io_Device := 0; lib_OpenCnt decremented;
deferred Expunge executed if requested.

### 2.4 BeginIO, AbortIO, standard commands [O ROM+probe]

Code shared with keyboard/gameport/input: io_Flags &= `$0F`, io_Error := 0; command ≥ **13** ⇒
treated as 0. Each command is "immediate" except **CMD_READ** (queued on the unit's MsgPort;
executed at once if it is at the head and the unit is not stopped, otherwise IOF_QUICK cleared
and return). Reply: io_Error set, removal from the queue, ReplyMsg only if IOF_QUICK is absent.

| No. | Command | V34 behaviour |
|---:|---|---|
| 0 | CMD_INVALID | io_Error = −3 (IOERR_NOCMD) |
| 1 | CMD_RESET | = CMD_STOP + CMD_FLUSH + CMD_START, a single reply; io_Error **not initialised** (see below the table) |
| 2 | CMD_READ | §6.3 |
| 3 | CMD_WRITE | §3 |
| 4 | CMD_UPDATE | **like CMD_INVALID**: io_Error = −3 |
| 5 | CMD_CLEAR | empties the unit's input buffer; **never replies**: io_Error stays 0, IOF_QUICK stays set; sent without IOF_QUICK (SendIO), the request is **never** returned (ln_Type stays NT_MESSAGE) [O probe] |
| 6 | CMD_STOP | marks the unit stopped: the CMD_READs stay queued (CMD_WRITE keeps working) |
| 7 | CMD_START | restarts: executes the CMD_READ at the head of the queue if there is one |
| 8 | CMD_FLUSH | replies **−2** (IOERR_ABORTED) to all the queued CMD_READs |
| 9 | CD_ASKKEYMAP | §5.4 |
| 10 | CD_SETKEYMAP | §5.4 |
| 11 | CD_ASKDEFAULTKEYMAP | §5.4 |
| 12 | CD_SETDEFAULTKEYMAP | §5.4 |

**io_Error of CMD_STOP, CMD_START, CMD_FLUSH, CMD_RESET**: these commands reply without setting a code:
io_Error receives the **low byte of the caller's D0** at the time of BeginIO (probe, BeginIO called with
D0 = command no.: io_Error = 1, 6, 7, 8; for FLUSH after at least one abort: −2). A
reimplementation must return 0. [O ROM+probe]

AbortIO: replies **−2** to the request if it has not already been returned (no check that it is
queued); returns 0.

---

## 3. CMD_WRITE: display

### 3.1 Contract [O ROM+probe]

- io_Data = bytes, io_Length = number of bytes, or **−1** ⇒ NUL-terminated string (io_Length is
  then replaced by the length). io_Length = 0 ⇒ nothing is written (but a pending resize
  is applied, §3.9). io_Actual = bytes consumed (probe: "xyz", −1 ⇒ 3). io_Error = 0.
- The parser state (incomplete ESC/CSI sequence) **persists from one write to the next**.
- During the whole write, the layer is locked and the RastPort saved (§2.2).
- At the end, if the input buffer is not empty (reports produced by `6n` or `SP q`) and a
  CMD_READ is waiting, it is served immediately.
- No NUL handling in explicit-length mode: `$00` is an ignored control character.

### 3.2 Automaton (all 8-bit bytes) [O ROM+probe]

States: **normal**, **ESC** (after `$1B`), **ESC-intermediate**, **CSI-parameters**, **CSI-intermediate**.

| State | Byte | Effect |
|---|---|---|
| normal | `$00–$1F` | C0 control (§3.3) |
| normal | `$20–$7F` | printable character (`$7F` too: glyph of the font) |
| normal | `$80–$9F` | C1 control (§3.3) |
| normal | `$A0–$FF` | printable character |
| ESC | `$00–$1F`, `$80–$FF` | ESC abandoned, the byte is reprocessed in the normal state (ESC ESC = new ESC) |
| ESC | `$20–$2F` | intermediate stored ⇒ ESC-intermediate |
| ESC | `$30–$3F` | **ignored, stays in the ESC state** (ESC 7 B: the B is consumed as `ESC B`) |
| ESC | `$40–$5F` | equivalent to the C1 `byte + $40` (ESC [ = CSI, ESC D = IND, ESC E = NEL, ESC H = HTS, ESC M = RI; the others are ignored) |
| ESC | `$60–$7F` | only **`c`** (RIS, §3.6) is recognised; the others are consumed without effect |
| ESC-interm. | `$20–$2F` | one more intermediate (at most 7 stored) |
| ESC-interm. | `$30–$7E` | end of sequence **ignored** (ESC ( 0, ESC # 8… without effect) |
| CSI-param. | `0–9` | digit of the current parameter (base 10) |
| CSI-param. | `;` | next parameter |
| CSI-param. | `:` | ignored |
| CSI-param. | `<` `=` `>` `?` | the current parameter takes the value −1, −2, −3, −4 (the following digits are added "negatively": `>1` = −31, `?7` = −47) |
| CSI-param. | `$20–$2F` | intermediate ⇒ CSI-intermediate |
| CSI-param. | `$40–$7E` | final byte ⇒ execution (§3.5) |
| CSI-param. | C0/C1 control (including CSI, ESC) | **abandon** of the sequence and reprocessing of the byte (CSI 2 LF ⇒ LF; CSI 1 CSI 2C ⇒ CSI 2C) |
| CSI-interm. | `$20–$2F` | one more intermediate |
| CSI-interm. | `$30–$3F` | abandon and reprocessing (CSI ! 2 C D ⇒ displays "2CD") |
| CSI-interm. | `$40–$6F` | sequence **ignored** |
| CSI-interm. | `$70–$7E` | executed only if the single intermediate is the space (`SP p`, `SP q`, §3.5); otherwise ignored |

Parameters: at most **24** (the following ones are lost); an absent parameter is "default" (internal
value −5); 16-bit signed values (overflow not checked). For the movement commands,
**default, 0 and negative are 1**. [O ROM; probe: CSI 0A = CSI A, CSI 65535C bounded]

### 3.3 C0 and C1 controls [O ROM+probe]

| Byte | Name | Effect |
|---|---|---|
| `$07` | BEL | DisplayBeep(the window's screen) |
| `$08` | BS | cursor left by 1 (non-destructive); in column 0 with AWM: last column of the previous line (on line 0: line 0, column XMax, and scroll down by one line if ASM — like CUU; this last case not probed); without AWM: nothing |
| `$09` | HT | next tab stop (§3.4) |
| `$0A` | LF | if LNM: like NEL (`$85`); otherwise like IND (`$84`) |
| `$0B` | VT | **previous line** (= RI `$8D`), column unchanged |
| `$0C` | FF | cursor at (0,0) and **clearing of the whole text area** (colour §3.7) |
| `$0D` | CR | column 0 |
| `$0E` | SO | "shifted" set: the characters `$20–$7F` are displayed as `byte | $80` |
| `$0F` | SI | back to the normal set |
| `$1B` | ESC | start of sequence |
| other `$00–$1F` | — | ignored (including NUL, `$1C`, `$1F`) |
| `$84` | IND | next line, column unchanged; at the bottom: scroll if ASM. **Absorbed** if the cursor has just been wrapped automatically (§3.8) |
| `$85` | NEL | next line + column 0; absorbed (entirely) after an automatic wrap |
| `$88` | HTS | sets a tab stop at the current column |
| `$8D` | RI | previous line; at the top: reverse scroll if ASM |
| `$9B` | CSI | start of control sequence |
| other `$80–$9F` | — | ignored |

### 3.4 Tab stops [O ROM+probe]

- Default (ESC c, open): columns **0, 8, 16, …, 632** (80 tab stops; the 81st word is `$FFFF`).
- HT: goes to the first tab stop **strictly greater** than XCP. If it exceeds XMax (or if there are no more):
  with AWM, column 0 of the next line (scroll if necessary) and **automatic wrap stored**
  (an immediately following LF/NEL is absorbed); without AWM, column XMax.
- HTS (`$88`, ESC H, `CSI W`/`CSI 0W`): inserts XCP into the sorted list (no duplicate; if the list
  is full, the last tab stop is lost).
- `CSI 2W` and `CSI g`/`CSI 0g`: removes the tab stop of the current column — **except in column 0** (the
  tab stop 0 is indelible).
- `CSI 5W`, `CSI 4W`, `CSI 3g`: clears everything; only tab stop 0 remains (list = `0, $FFFF`).
- `CSI W` and `CSI g` process each parameter of the list (`CSI 0;2W` …); unlisted values
  are ignored.
- `CSI n I` (CHT): n times HT. `CSI n Z` (CBT): n times "previous tab stop": first tab stop
  strictly lower than XCP; in column 0 with AWM: goes up one line (reverse scroll if ASM)
  and searches from the end of that line; in column 0 without AWM: nothing.

### 3.5 Recognised CSI sequences [O ROM+probe]

Notation: `Pn` = parameter (default/0/negative ⇒ 1 for movements). Any final absent from the table
is **ignored** (including `G`, `d`, `X`, `p` without space, `s`, `r`, `|`, `~`…). [O probe: G, d, X, CSI 0p, CSI p]

| Sequence | Name | Exact V34 effect |
|---|---|---|
| `CSI Pn @` | ICH | inserts Pn empty cells at XCP (shift right of the current line up to XRExtant, what goes out is lost); cursor fixed |
| `CSI Pn A` | CUU | YCP −= Pn; if < 0: YCP = 0 and, **if ASM, scroll down** by the deficit (CUU beyond the top makes empty lines appear) |
| `CSI Pn B` | CUD | YCP += Pn; if > YMax: YMax and, if ASM, scroll up by the excess |
| `CSI Pn C` | CUF | XCP += Pn; if > XMax: with AWM, back to column 0 of the next line (scroll if needed) and continuation of the rest, automatic wrap stored; without AWM: XMax |
| `CSI Pn D` | CUB | XCP −= Pn; if < 0: with AWM, last column of the previous line and continuation; without AWM: 0 |
| `CSI Pn E` | CNL | Pn lines down (like CUD) then column 0; **entirely absorbed** just after an automatic wrap |
| `CSI Pn F` | CPL | Pn lines up (like CUU) then column 0; absorbed just after an automatic wrap |
| `CSI Pl;Pc H`, `CSI Pl;Pc f` | CUP | line Pl, column Pc (base 1); default/0 ⇒ 1; **bounded** to YMax/XMax (no scrolling) |
| `CSI Pn I` | CHT | Pn tabulations |
| `CSI J` | ED | clears from the cursor to the end of the line then all the following lines of the area; **parameter ignored** (`1J`, `2J` = `J`) |
| `CSI K` | EL | clears from the cursor to the end of the line; **parameter ignored** (`1K`, `2K` = `K`) |
| `CSI Pn L` | IL | inserts Pn empty lines at the current line (the bottom of the area is lost); cursor fixed |
| `CSI Pn M` | DL | deletes Pn lines starting from the current line, the bottom fills with empty lines |
| `CSI Pn P` | DCH | deletes Pn characters at XCP, the end of the line shifts left, empty cells on the right |
| `CSI Pn S` | SU | scrolls the whole area up by Pn lines; cursor fixed |
| `CSI Pn T` | SD | scrolls the whole area down by Pn lines; cursor fixed |
| `CSI Ps;… W` | CTC | 0/default: HTS; 2: clears the current tab stop; 4 or 5: clears all (§3.4) |
| `CSI Pn Z` | CBT | Pn backward tabulations |
| `CSI Ps;… g` | TBC | 0/default: clears the current tab stop; 3: clears all |
| `CSI Ps;… h` / `l` | SM / RM | sets / clears bit Ps of cu_Modes for 0 ≤ Ps ≤ 20; `>1` (−31) ⇒ bit 21 **ASM**; `?7` (−47) ⇒ bit 22 **AWM**; other values ignored. Only 20/21/22 have an effect |
| `CSI Ps;… m` | SGR | §3.7 |
| `CSI 6n` | DSR | puts `CSI <YCP+1>;<XCP+1>R` into the input buffer (only the first parameter is examined: `6;6n` replies, `5n` and `n` do not) |
| `CSI Pn t` | — | Pn > 0: fixed page length, **YMax = Pn−1**; default/≤ 0: back to automatic computation |
| `CSI Pn u` | — | Pn > 0: fixed line length, **XMax = Pn−1**; default/≤ 0: automatic |
| `CSI Pn x` | — | Pn ≥ 0: **XROrigin = Pn pixels** (from the left edge of the window, border included); default: automatic |
| `CSI Pn y` | — | Pn ≥ 0: **YROrigin = Pn pixels**; default: automatic |
| `CSI Ps;… {` | — | sets the raw-report bit of each class Ps (0 ≤ Ps ≤ 18; others ignored) |
| `CSI Ps;… }` | — | clears these bits |
| `CSI 0 SP p` | — | **cursor invisible** (the block is erased) |
| `CSI SP p`, `CSI Pn SP p` (Pn ≠ 0) | — | cursor visible |
| `CSI SP q`, `CSI Pn SP q` | — | puts `CSI 1;1;<YMax+1>;<XMax+1> r` into the input buffer (window bounds report; parameter ignored) |

After `t`, `u`, `x`, `y`, the geometry is recomputed immediately (§3.9).

### 3.6 RIS — `ESC c` [O ROM+probe]

In visible order: cursor hidden; default tab stops; normal set (SI); parser reset;
XCP = YCP = 0; cu_XCCP/YCCP = 0; page/line length and origins become automatic again;
cursor **visible**; cu_Modes = 0 then **LNM, ASM, AWM set** (`00 00 70`); font, algorithmic
style, TxHeight/TxWidth/TxBaseline/TxSpacing **restored** from those stored at
OpenDevice; XRSize = TxWidth + TxSpacing, YRSize = TxHeight; SGR 0; recomputation of the geometry
with "smallest size seen" = 0, which **clears the whole area** (including the partial margin on the
right/at the bottom) **if the window is SMART_REFRESH**; nothing is cleared for SIMPLE_REFRESH or
SUPER_BITMAP (§8.7); cursor drawn at (0,0). cu_RawEvents is **not** reset.

### 3.7 SGR (`CSI Ps;… m`) [O ROM+probe]

Each parameter is processed in order; default/negative ⇒ 0; values > 49 ignored.

| Ps | Effect on the console's RastPort |
|---:|---|
| 0 | Mask = `$FF`, DrawMode = JAM2, SetSoftStyle(0, mask 7) (bold/italic/underline removed), APen = 1, BPen = 0 |
| 1 | algorithmic bold (FSF_BOLD) |
| 2 | **APen = 2** ("faint" = colour 2, not a style) |
| 3 | algorithmic italic (FSF_ITALIC) |
| 4 | underline (FSF_UNDERLINED) |
| 7 | DrawMode = JAM2 \| INVERSVID (5) |
| 8 | **Mask = 0** ("concealed": nothing is drawn any more, neither text nor clears; see the pitfall below) |
| 30–37 | APen = Ps − 30 |
| 39 | APen = 1 |
| 40–47 | BPen = Ps − 40 |
| 49 | BPen = 0 |
| 5, 6, 9–29 (including 22, 23, 24, 27), 38, 48 | **no effect** (no individual cancellation in V34) |

- Pen ≥ number of colours: masked by the depth (probe: 34 ⇒ colour 0, 37 ⇒ colour 3).
- **Clearing colour** (FF, ED, EL, ESC c, resize margin): **BPen if DrawMode is
  exactly JAM2**, otherwise colour 0 (in inverse, EL clears in 0). ICH/DCH/IL/DL/SU/SD and automatic
  scrolling go through ScrollRaster, which fills with **BPen** whatever the mode. [O probe]
- SGR 8 pitfall: the cursor block is drawn/erased in complement **with the current Mask**; with Mask 0
  the cursor erase does not take place and the block stays on screen at the old position. [O probe]

### 3.8 Writing characters, automatic wrap, scrolling [O ROM+probe]

- Consecutive printable bytes are displayed by **Text()** in one go, in slices limited to
  the end of the line (XMax − XCP + 1), at the pixel position (XROrigin + XCP × XRSize, YROrigin + YCP × YRSize
  + TxBaseline). In SO mode, one character at a time (byte | `$80`).
- After each slice, cursor advanced like `CSI Pn C`: **if AWM**, the character written in the last
  column **immediately** sends the cursor back to column 0 of the next line (scroll if we
  were at the bottom and ASM) and **stores** this "automatic wrap"; otherwise the cursor stays on XMax and
  the following characters **overwrite the last column**.
- The automatic-wrap marker is cleared as soon as the cursor changes cell. As long as it is
  set, **LF, IND, NEL, CNL and CPL are absorbed** (a line of exactly XMax+1 characters followed by
  LF leaves no empty line). CR moves nothing (already in column 0) and does not clear it, so
  "full line + CR LF" also only advances by one line. [O ROM; probe §8.3]
- At the bottom (YCP = YMax), a line feed **with ASM** scrolls the whole area up by one line
  (ScrollRaster over XROrigin..XRExtant × YROrigin..YRExtant, BPen fill); **without ASM** the
  cursor stays on the last line which is overwritten.
- Scrolling is limited to the page defined by `t`/`u` (probe: page 20 × 5, scrolling only touches
  those 20 columns × 5 lines).

### 3.9 Geometry and resizing [O ROM+probe]

Recomputation (at open, ESC c, `t u x y`, and at the start of the first write after an
IECLASS_SIZEWINDOW):

- **Non-GIMMEZEROZERO** window: XROrigin = BorderLeft (unless `x`), YROrigin = BorderTop (unless `y`);
  useful width = Width − XROrigin − BorderRight; useful height = Height − YROrigin − BorderBottom.
- **GIMMEZEROZERO** window: XROrigin = 0 and YROrigin = 0 (unless `x`/`y`); useful width = Width −
  BorderLeft − BorderRight − XROrigin; useful height = Height − BorderTop − BorderBottom − **XROrigin**
  (V34 subtracts the **horizontal** origin from the height: bug visible only after `CSI Pn x`). [O ROM; probe §8.7]
- XMax = useful width / XRSize − 1 (unless `u`); YMax = useful height / YRSize − 1 (unless `t`);
  XRExtant = (XMax+1) × XRSize − 1 + XROrigin; YRExtant = (YMax+1) × YRSize − 1 + YROrigin.
- SMART_REFRESH window only: if the window has grown, clearing (colour §3.7) of the band to the
  right of the whole columns that existed at the smallest size seen, and of the band below the corresponding
  whole lines (removes the half-characters revealed).
- Cursor: if it was in the kept part it is erased normally, otherwise it is considered
  gone. Then (except SUPER_BITMAP): XCP > XMax ⇒ column 0 of the next line; YCP > YMax ⇒
  YCP = YMax, column 0 and **scroll of a single line** (no recentring); cursor redrawn.
- The console learns of the resize through the **IECLASS_SIZEWINDOW** event passed to it by
  input.device's chain: it is applied to the **active unit**, whatever window was resized
  (for a non-active console, the recomputation does not take place before the next `ESC c`/`t u x y`). The
  actual recomputation is deferred to the **start of the next CMD_WRITE** (even of length 0). [O ROM; D for the effect on an inactive window; probe §8.5]
- No other reaction to refresh: IECLASS_REFRESHWINDOW is only used for the raw
  report; a SIMPLE_REFRESH window hidden then revealed loses its text. [O ROM]

### 3.10 Cursor [O ROM+probe]

Solid one-cell block (XRSize × YRSize) drawn by **RectFill in COMPLEMENT mode** (colour 0 ⇒ 3
on 2 planes: the orange 1.3 cursor), at (cu_XCCP, cu_YCCP). Hidden during any drawing operation,
redisplayed at the XCP/YCP position at the end. Visible by default; `CSI 0 SP p` hides it. There is no
"ghost" cursor when the window is inactive (same drawing whatever the activation state). [O ROM]

---

## 4. Reports inserted into the input stream [O ROM+probe]

Formats (ASCII decimal, `CSI` = byte `$9B`):

| Origin | Format |
|---|---|
| `CSI 6n` | `CSI` *line* `;` *column* `R` (base 1; probe after "xyz" on line 1 column 9: `9B 31 3B 39 52`) |
| `CSI SP q` | `CSI 1;1;` *lines* `;` *columns* ` r` (space before `r`; probe: `CSI 1;1;20;61 r`) |
| raw event | `CSI` *class* `;` *subclass* `;` *code* `;` *qualifier* `;` *x* `;` *y* `;` *seconds* `;` *microseconds* `|` |

Raw report: one per event of the class enabled by `CSI n{`, for the active unit (or all the
units if the qualifier carries IEQUALIFIER_MULTIBROADCAST `$0800`); x and y = ie_X/ie_Y **unsigned**
(for RAWKEY: codes/qualifiers of the previous keys); seconds and microseconds with bit 31
forced to 0. An event reported raw is **not** cooked as well. The bytes go through the same
255-byte buffer as the keys; if it is full, the end of the report is **truncated** (byte by
byte), whereas a key translation that does not fit is **discarded entirely**.

---

## 5. Keymaps

### 5.1 Types (byte of km_*KeyMapTypes) [O ROM; public ABI]

`KCF_SHIFT 1`, `KCF_ALT 2`, `KCF_CONTROL 4`, `KCF_DOWNUP 8`, `KCF_DEAD $20`, `KCF_STRING $40`,
`KCF_NOP $80`, `KC_VANILLA 7`. Combination index: bits 0 to 3 of the type are walked (SHIFT, ALT,
CONTROL, DOWNUP); each bit present in the type is worth 1, 2, 4… in the order encountered, and counts
if it is also present in the current state. Number of combinations = 2^(bits present).

### 5.2 Translation of a code (RawKeyConvert) [O ROM; model validated by probe §6]

For a RAWKEY event (code `c`, qualifier `q`):

1. code = `c & $7F`; > `$77` ⇒ 0 bytes. Lo tables if < `$40`, otherwise Hi.
2. `q & $0200` (IEQUALIFIER_REPEAT) and key not "Repeatable" ⇒ 0 bytes.
3. type `KCF_NOP` ⇒ 0 bytes.
4. Release (`c & $80`): 0 bytes if the type does not have KCF_DOWNUP; otherwise the DOWNUP bit counts.
5. State: Shift if `q & 3` (LSHIFT|RSHIFT); Alt if `q & $30` (LALT|RALT); **Caps Lock (`q & 4`) on a
   Capsable key ⇒ Shift** (Caps + Shift = Shift, no inversion); Ctrl if `q & 8`. The Amiga keys
   (`$40/$80`) and the keypad (`$100`) have no effect.
6. Depending on the type:
   - **STRING**: the long is a pointer to pairs (length, offset) — one per combination —
     the offset being relative to the start of the descriptor; length > remaining room ⇒ **−1**.
   - **DEAD**: the long points to pairs (flag, value), one per combination:
     flag 0 ⇒ value = the byte returned; flag `DPF_DEAD` (8) ⇒ dead key: **0 bytes** (even with
     a buffer of length 0), its value = index of the dead key; flag `DPF_MOD` (1) ⇒ modifiable
     key: value = offset of a translation table; the byte returned is `table[k]`, where k =
     dead-key index of the **previous key** (ie_Prev1DownCode/Qual = bytes of ie_X) if it was
     dead, otherwise 0. If the index of the previous one has a non-zero high nibble (double dead key), k =
     (high × low) + low index of the key before that (ie_Prev2DownCode/Qual = bytes of ie_Y); the
     "usa" keymap only uses indices 1 to 5, so only one dead key counts.
   - **VANILLA (7)** without Ctrl: byte no. (index) of the long starting from the **least significant**
     byte (0 = no qualifier, 1 = Shift, 2 = Alt, 3 = Shift+Alt).
   - **VANILLA with Ctrl**: start from the byte selected by Shift/Alt and search, rotating towards
     the more significant bytes (at most 4, wrapping around), for the first byte of the form `%01xxxxxx`
     (`$40–$7F`); result = that byte **& `$1F`**. None ⇒ the selected byte as is. (Ctrl-2 ⇒
     `$00` via "@", Ctrl-6 ⇒ `$1E`, Ctrl-Alt-q ⇒ `$11`.)
   - **Other type without STRING/DEAD**: ≤ 4 combinations ⇒ byte no. index of the long (least significant = 0);
     more than 4 (type with DOWNUP and 2 or more qualifiers, outside VANILLA) ⇒ the long is a pointer to
     an indexed byte array.
7. Remaining room 0 for a one-byte result ⇒ **−1**.

### 5.3 RawKeyConvert function (console LVO −48) [O ROM+probe]

`actual = RawKeyConvert(events A0, buffer A1, length D1, keyMap A2)`, A6 = console.device base
(obtained by OpenDevice unit −1).

- keyMap = NULL ⇒ **the device's current default keymap** (the one that CD_SETDEFAULTKEYMAP replaces).
- Walks **the whole** ie_NextEvent **chain**; only events of class 1 (RAWKEY) produce
  bytes, concatenated; length decreases from one event to the next.
- Returns the total (word, high part zero), or **−1 (long) as soon as a result does not fit** (the start
  already written stays in the buffer). Probe: chain "a", "Shift b" ⇒ 2 bytes `61 42`; same chain with
  length 1 ⇒ −1; first event RAWMOUSE ⇒ only `42` (1).
- Neither reads nor modifies any global state: dead keys rely solely on ie_X/ie_Y of
  the event.

### 5.4 Keymap commands [O ROM+probe]

- io_Length must be **exactly 32**; otherwise io_Error = **−4** (IOERR_BADLENGTH), nothing is copied,
  io_Actual unchanged. Success: io_Actual = 32.
- **CD_ASKKEYMAP** (9): copies the unit's KeyMap (`cu_KeyMapStruct`) to io_Data.
- **CD_SETKEYMAP** (10): copies io_Data to the unit's KeyMap (immediate effect on the keys of
  that unit).
- **CD_ASKDEFAULTKEYMAP** (11): copies the device's default keymap to io_Data.
- **CD_SETDEFAULTKEYMAP** (12): copies io_Data to the device's default keymap. Effects: (a)
  RawKeyConvert(…, NULL) uses it at once; (b) the units **opened afterwards** receive it; (c) the
  units **already open do not change**; (d) keymap.resource **is not modified**.
- Only the 8 pointers are copied (under Forbid): the tables must stay in memory as long as they
  are used (case of `SetMap`, which loads them into RAM).
- Probe: SETDEFAULT of a copy where the long of `$21` (s) is `$5A7A5A7A` ⇒ RawKeyConvert(s, NULL) = `z`;
  ASKKEYMAP of the existing unit = ROM pointers; new unit ⇒ modified pointer; restoration ⇒ `s`.

### 5.5 ROM "usa" keymap: raw tables [O ROM+probe]

- Capsable Lo (8 bytes): `00 00 FF 03 FF 01 FE 00` ⇒ `$10–$19`, `$20–$28`, `$31–$37`; Hi: all 0.
- Repeatable Lo: `FF BF FF EF FF EF FF F7` ⇒ all except `$0E`, `$1C`, `$2C`, `$3B`;
  Hi: `47 F4 FF 03 00 00 00` ⇒ `$40 $41 $42 $46 $4A $4C–$4F $50–$59` (**Return, Enter, Esc, Help and
  the modifiers do not repeat**).

### 5.6 "usa" keymap: result per key and per qualifier [O ROM+probe]

Values **returned by RawKeyConvert** (press, sufficient buffer), identical to the probe on the
14 qualifiers tested × 120 codes. "—" = nothing; "dead n" = dead key of index n (nothing is
returned); "†" = modifiable key (the value shown is the one without a preceding dead key, see §5.7);
`SP` = space `$20`; `$xx` = non-printable or ambiguous byte; `CSI` = `$9B`. Caps Lock = Shift for the
keys marked "Caps". Codes `$68–$77`: type outside the table, always nothing.

| Code | Key | Type | Caps | Rep. | — | Shift | Alt | Shift+Alt | Ctrl | Ctrl+Shift | Ctrl+Alt | Ctrl+Shift+Alt |
|---|---|---|:-:|:-:|---|---|---|---|---|---|---|---|
| $00 | `` ` `` (left of 1) | $07 |  | x | `` ` `` | ~ | `` ` `` | ~ | $00 | $1E | $00 | $1E |
| $01 | 1 | $03 |  | x | 1 | ! | ¹ | ! | 1 | ! | ¹ | ! |
| $02 | 2 | $07 |  | x | 2 | @ | ² | @ | $00 | $00 | $00 | $00 |
| $03 | 3 | $03 |  | x | 3 | # | ³ | # | 3 | # | ³ | # |
| $04 | 4 | $03 |  | x | 4 | $ | ¢ | $ | 4 | $ | ¢ | $ |
| $05 | 5 | $03 |  | x | 5 | % | ¼ | % | 5 | % | ¼ | % |
| $06 | 6 | $07 |  | x | 6 | ^ | ½ | ^ | $1E | $1E | $1E | $1E |
| $07 | 7 | $03 |  | x | 7 | & | ¾ | & | 7 | & | ¾ | & |
| $08 | 8 | $03 |  | x | 8 | * | · | * | 8 | * | · | * |
| $09 | 9 | $03 |  | x | 9 | ( | « | ( | 9 | ( | « | ( |
| $0A | 0 | $03 |  | x | 0 | ) | » | ) | 0 | ) | » | ) |
| $0B | - | $07 |  | x | - | _ | - | _ | $1F | $1F | $1F | $1F |
| $0C | = | $01 |  | x | = | + | = | + | = | + | = | + |
| $0D | \\ | $07 |  | x | \\ | \\| | \\ | \\| | $1C | $1C | $1C | $1C |
| $0E | (unused) | $80 |  |  | — | — | — | — | — | — | — | — |
| $0F | keypad 0 | $00 |  | x | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| $10 | q | $07 | x | x | q | Q | å | Å | $11 | $11 | $11 | $11 |
| $11 | w | $07 | x | x | w | W | ° | ° | $17 | $17 | $17 | $17 |
| $12 | e | $27 | x | x | e† | E† | © | © | $05 | $05 | $85 | $85 |
| $13 | r | $07 | x | x | r | R | ® | ® | $12 | $12 | $12 | $12 |
| $14 | t | $07 | x | x | t | T | þ | Þ | $14 | $14 | $14 | $14 |
| $15 | y | $27 | x | x | y† | Y† | ¤ | ¥ | $19 | $19 | $99 | $99 |
| $16 | u | $27 | x | x | u† | U† | µ | µ | $15 | $15 | $95 | $95 |
| $17 | i | $27 | x | x | i† | I† | ¡ | ¦ | $09 | $09 | $89 | $89 |
| $18 | o | $27 | x | x | o† | O† | ø | Ø | $0F | $0F | $8F | $8F |
| $19 | p | $07 | x | x | p | P | ¶ | ¶ | $10 | $10 | $10 | $10 |
| $1A | [ | $07 |  | x | [ | { | [ | { | $1B | $1B | $1B | $1B |
| $1B | ] | $07 |  | x | ] | } | ] | } | $1D | $1D | $1D | $1D |
| $1C | (unused) | $80 |  |  | — | — | — | — | — | — | — | — |
| $1D | keypad 1 | $00 |  | x | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 |
| $1E | keypad 2 | $00 |  | x | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 |
| $1F | keypad 3 | $00 |  | x | 3 | 3 | 3 | 3 | 3 | 3 | 3 | 3 |
| $20 | a | $27 | x | x | a† | A† | æ | Æ | $01 | $01 | $81 | $81 |
| $21 | s | $07 | x | x | s | S | ß | § | $13 | $13 | $13 | $13 |
| $22 | d | $07 | x | x | d | D | ð | Ð | $04 | $04 | $04 | $04 |
| $23 | f | $27 | x | x | f | F | dead 1 | dead 1 | $06 | $06 | $86 | $86 |
| $24 | g | $27 | x | x | g | G | dead 2 | dead 2 | $07 | $07 | $87 | $87 |
| $25 | h | $27 | x | x | h | H | dead 3 | dead 3 | $08 | $08 | $88 | $88 |
| $26 | j | $27 | x | x | j | J | dead 4 | dead 4 | $0A | $0A | $8A | $8A |
| $27 | k | $27 | x | x | k | K | dead 5 | dead 5 | $0B | $0B | $8B | $8B |
| $28 | l | $07 | x | x | l | L | £ | £ | $0C | $0C | $0C | $0C |
| $29 | ; | $01 |  | x | ; | : | ; | : | ; | : | ; | : |
| $2A | ' | $01 |  | x | ' | " | ' | " | ' | " | ' | " |
| $2B | intl. (near Return) | $80 |  | x | — | — | — | — | — | — | — | — |
| $2C | (unused) | $80 |  |  | — | — | — | — | — | — | — | — |
| $2D | keypad 4 | $00 |  | x | 4 | 4 | 4 | 4 | 4 | 4 | 4 | 4 |
| $2E | keypad 5 | $00 |  | x | 5 | 5 | 5 | 5 | 5 | 5 | 5 | 5 |
| $2F | keypad 6 | $00 |  | x | 6 | 6 | 6 | 6 | 6 | 6 | 6 | 6 |
| $30 | intl. (left of Z) | $03 |  | x | < | > | « | » | < | > | « | » |
| $31 | z | $07 | x | x | z | Z | ± | ¬ | $1A | $1A | $1A | $1A |
| $32 | x | $07 | x | x | x | X | × | ÷ | $18 | $18 | $18 | $18 |
| $33 | c | $07 | x | x | c | C | ç | Ç | $03 | $03 | $03 | $03 |
| $34 | v | $07 | x | x | v | V | ª | ª | $16 | $16 | $16 | $16 |
| $35 | b | $07 | x | x | b | B | º | º | $02 | $02 | $02 | $02 |
| $36 | n | $27 | x | x | n† | N† | $AD | ¯ | $0E | $0E | $8E | $8E |
| $37 | m | $07 | x | x | m | M | ¸ | ¿ | $0D | $0D | $0D | $0D |
| $38 | , | $01 |  | x | , | < | , | < | , | < | , | < |
| $39 | . | $01 |  | x | . | > | . | > | . | > | . | > |
| $3A | / | $01 |  | x | / | ? | / | ? | / | ? | / | ? |
| $3B | (unused) | $80 |  |  | — | — | — | — | — | — | — | — |
| $3C | keypad . | $00 |  | x | . | . | . | . | . | . | . | . |
| $3D | keypad 7 | $00 |  | x | 7 | 7 | 7 | 7 | 7 | 7 | 7 | 7 |
| $3E | keypad 8 | $00 |  | x | 8 | 8 | 8 | 8 | 8 | 8 | 8 | 8 |
| $3F | keypad 9 | $00 |  | x | 9 | 9 | 9 | 9 | 9 | 9 | 9 | 9 |
| $40 | Space | $22 |  | x | SP† | SP† | $A0 | $A0 | SP† | SP† | $A0 | $A0 |
| $41 | Backspace | $00 |  | x | $08 | $08 | $08 | $08 | $08 | $08 | $08 | $08 |
| $42 | Tab | $41 |  | x | $09 | CSI Z | $09 | CSI Z | $09 | CSI Z | $09 | CSI Z |
| $43 | Enter (keypad) | $00 |  |  | $0D | $0D | $0D | $0D | $0D | $0D | $0D | $0D |
| $44 | Return | $04 |  |  | $0D | $0D | $0D | $0D | $0A | $0A | $0A | $0A |
| $45 | Esc | $02 |  |  | $1B | $1B | CSI | CSI | $1B | $1B | CSI | CSI |
| $46 | Del | $00 |  | x | $7F | $7F | $7F | $7F | $7F | $7F | $7F | $7F |
| $47 | (unused) | $80 |  |  | — | — | — | — | — | — | — | — |
| $48 | (unused) | $80 |  |  | — | — | — | — | — | — | — | — |
| $49 | (unused) | $80 |  |  | — | — | — | — | — | — | — | — |
| $4A | keypad - | $00 |  | x | - | - | - | - | - | - | - | - |
| $4B | (unused) | $80 |  |  | — | — | — | — | — | — | — | — |
| $4C | ↑ | $41 |  | x | CSI A | CSI T | CSI A | CSI T | CSI A | CSI T | CSI A | CSI T |
| $4D | ↓ | $41 |  | x | CSI B | CSI S | CSI B | CSI S | CSI B | CSI S | CSI B | CSI S |
| $4E | → | $41 |  | x | CSI C | CSI SP @ | CSI C | CSI SP @ | CSI C | CSI SP @ | CSI C | CSI SP @ |
| $4F | ← | $41 |  | x | CSI D | CSI SP A | CSI D | CSI SP A | CSI D | CSI SP A | CSI D | CSI SP A |
| $50 | F1 | $41 |  | x | CSI 0 ~ | CSI 1 0 ~ | CSI 0 ~ | CSI 1 0 ~ | CSI 0 ~ | CSI 1 0 ~ | CSI 0 ~ | CSI 1 0 ~ |
| $51 | F2 | $41 |  | x | CSI 1 ~ | CSI 1 1 ~ | CSI 1 ~ | CSI 1 1 ~ | CSI 1 ~ | CSI 1 1 ~ | CSI 1 ~ | CSI 1 1 ~ |
| $52 | F3 | $41 |  | x | CSI 2 ~ | CSI 1 2 ~ | CSI 2 ~ | CSI 1 2 ~ | CSI 2 ~ | CSI 1 2 ~ | CSI 2 ~ | CSI 1 2 ~ |
| $53 | F4 | $41 |  | x | CSI 3 ~ | CSI 1 3 ~ | CSI 3 ~ | CSI 1 3 ~ | CSI 3 ~ | CSI 1 3 ~ | CSI 3 ~ | CSI 1 3 ~ |
| $54 | F5 | $41 |  | x | CSI 4 ~ | CSI 1 4 ~ | CSI 4 ~ | CSI 1 4 ~ | CSI 4 ~ | CSI 1 4 ~ | CSI 4 ~ | CSI 1 4 ~ |
| $55 | F6 | $41 |  | x | CSI 5 ~ | CSI 1 5 ~ | CSI 5 ~ | CSI 1 5 ~ | CSI 5 ~ | CSI 1 5 ~ | CSI 5 ~ | CSI 1 5 ~ |
| $56 | F7 | $41 |  | x | CSI 6 ~ | CSI 1 6 ~ | CSI 6 ~ | CSI 1 6 ~ | CSI 6 ~ | CSI 1 6 ~ | CSI 6 ~ | CSI 1 6 ~ |
| $57 | F8 | $41 |  | x | CSI 7 ~ | CSI 1 7 ~ | CSI 7 ~ | CSI 1 7 ~ | CSI 7 ~ | CSI 1 7 ~ | CSI 7 ~ | CSI 1 7 ~ |
| $58 | F9 | $41 |  | x | CSI 8 ~ | CSI 1 8 ~ | CSI 8 ~ | CSI 1 8 ~ | CSI 8 ~ | CSI 1 8 ~ | CSI 8 ~ | CSI 1 8 ~ |
| $59 | F10 | $41 |  | x | CSI 9 ~ | CSI 1 9 ~ | CSI 9 ~ | CSI 1 9 ~ | CSI 9 ~ | CSI 1 9 ~ | CSI 9 ~ | CSI 1 9 ~ |
| $5A | keypad ( (A500/A2000) | $80 |  |  | — | — | — | — | — | — | — | — |
| $5B | keypad ) | $80 |  |  | — | — | — | — | — | — | — | — |
| $5C | keypad / | $80 |  |  | — | — | — | — | — | — | — | — |
| $5D | keypad * | $80 |  |  | — | — | — | — | — | — | — | — |
| $5E | keypad + | $80 |  |  | — | — | — | — | — | — | — | — |
| $5F | Help | $40 |  |  | CSI ? ~ | CSI ? ~ | CSI ? ~ | CSI ? ~ | CSI ? ~ | CSI ? ~ | CSI ? ~ | CSI ? ~ |
| $60 | Left Shift | $80 |  |  | — | — | — | — | — | — | — | — |
| $61 | Right Shift | $80 |  |  | — | — | — | — | — | — | — | — |
| $62 | Caps Lock | $80 |  |  | — | — | — | — | — | — | — | — |
| $63 | Ctrl | $80 |  |  | — | — | — | — | — | — | — | — |
| $64 | Left Alt | $80 |  |  | — | — | — | — | — | — | — | — |
| $65 | Right Alt | $80 |  |  | — | — | — | — | — | — | — | — |
| $66 | Left Amiga | $80 |  |  | — | — | — | — | — | — | — | — |
| $67 | Right Amiga | $80 |  |  | — | — | — | — | — | — | — | — |

### 5.7 Dead keys ("usa" keymap) [O ROM+probe]

Dead keys (Alt or Alt+Shift on f, g, h, j, k): index **1 = Alt-f acute accent**, **2 = Alt-g grave**,
**3 = Alt-h circumflex**, **4 = Alt-j tilde**, **5 = Alt-k diaeresis**. Ctrl-Alt-f etc. are not dead
(`$86`…). Modifiable keys and their table (index 0 = without dead key, then 1 to 5):

| Key | Without Shift: 0, 1, 2, 3, 4, 5 | With Shift (or Caps): 0, 1, 2, 3, 4, 5 |
|---|---|---|
| Space (`$40`, also with Shift; Ctrl without effect) | SP ´ ` ^ ~ ¨ | same |
| a (`$20`) | a á à â ã ä | A Á À Â Ã Ä |
| e (`$12`) | e é è ê e ë | E É È Ê E Ë |
| i (`$17`) | i í ì î i ï | I Í Ì Î I Ï |
| o (`$18`) | o ó ò ô õ ö | O Ó Ò Ô Õ Ö |
| u (`$16`) | u ú ù û u ü | U Ú Ù Û U Ü |
| y (`$15`) | y ý y y y ÿ | Y Ý Y Y Y Y |
| n (`$36`) | n n n n ñ n | N N N N Ñ N |

Codes returned for the space: `$B4`, `$60`, `$5E`, `$7E`, `$A8`. Only the combinations without Alt and without
Ctrl are modifiable (Alt-e = "©" ignores the dead key). A dead key followed by a non-modifiable key:
the dead key is lost, the key gives its normal value (probe: Alt-f then q ⇒ `q`). The dead key must be
**the key pressed immediately before** (ie_Prev1DownCode) with its Alt qualifier (Prev1DownQual):
"f" without Alt before "e" ⇒ `e`.

---

## 6. CDInputHandler (LVO −42) and input stream

### 6.1 Contract [O ROM]

`events = CDInputHandler(events A0, consoleDevice A1)` — called by input.device (pri 0, after
intuition pri 50). For each event of the chain:

1. **IECLASS_EVENT (3) / IECODE_NEWACTIVE (1)**: the window ie_EventAddress becomes the "known active
   window"; the active unit becomes the **first unit of the list** (= the most recently opened)
   whose cu_Window is that window, or none.
2. Qualifier with **IEQUALIFIER_MULTIBROADCAST (`$0800`)**: the event is processed for **all**
   the units; otherwise for the active unit only (nothing if there is none).
3. **IECLASS_SIZEWINDOW (12)** (outside multibroadcast): stores the minimal size seen and flags a
   geometry recomputation for the active unit (§3.9).
4. Processing for a unit: if class ≤ 18 and the corresponding cu_RawEvents bit ⇒ raw report (§4);
   otherwise RawKeyConvert of **this event alone** (ie_NextEvent temporarily masked) with the
   unit's keymap into a 127-byte buffer; if at least 1 byte and **everything** fits in the free room
   of the input buffer, it is added; otherwise silent abandon.
5. After the chain: if something was added, the pending CMD_READs of the active unit (or of
   all the units after a multibroadcast) are served.

The handler **returns NULL**: it consumes the whole chain (last standard handler). [O ROM]

### 6.2 What really arrives from intuition 1.3 [O probe]

- What the console receives is the list **returned by intuition** (`intuition-input-menus-v34.md` §1–§2):
  the RAWKEYs intended for the active window, IECLASS_EVENT/NEWACTIVE (emitted by ActivateWindow **even if the
  window is already active**), IECLASS_SIZEWINDOW (also emitted by SizeWindow()), the NULL events;
  **not** the RAWMOUSE mouse buttons nor POINTERPOS nor TIMER (swallowed by intuition). Probe: `CSI 2{`
  + injected buttons ⇒ no report; `CSI 0{ 4{ 6{` ⇒ only a class 0 report. [O probe]
- Keys injected by IND_WRITEEVENT keep ie_X/ie_Y as they are: an injected dead key only acts
  if the injector fills Prev1DownCode/Qual itself (probe: Alt-f then e injected ⇒ `e`; e with
  ie_X = `$2310` ⇒ `é`). For real keystrokes, it is input.device that fills these fields
  (`intuiticks-repeat-v34.md` §2.1). [O probe]
- Cooking observed in CMD_READ (active unit, "usa" keymap): a ⇒ `61`; Shift a ⇒ `41`; ↑ ⇒ `9B 41`;
  Shift ↑ ⇒ `9B 54`; F1 ⇒ `9B 30 7E`; Shift F1 ⇒ `9B 31 30 7E`; Help ⇒ `9B 3F 7E`; Shift Tab ⇒ `9B 5A`;
  Alt Esc ⇒ `9B`; Ctrl Return ⇒ `0A`; Backspace ⇒ `08`; Del ⇒ `7F`; releases produce
  nothing. [O probe]
- Raw report (`CSI 1{`, RAWKEY `$20`, qualifier `$8000`, ie_X/ie_Y = `$1234`/`$5678`, timestamp
  0): `CSI 1;0;32;32768;4660;22136;0;0|`. [O probe]
- **Active unit pitfall**: opening then closing a second unit on the active window leaves the
  device **without an active unit** (the close does not look for another unit); keystrokes are lost
  until the next NEWACTIVE (ActivateWindow, click). Probe: active unit = 0 after the close, `a`
  injected ⇒ nothing; after ActivateWindow ⇒ `a`. [O ROM+probe]

### 6.3 CMD_READ [O ROM+probe]

- io_Length > 0: under Forbid, copies at most io_Length bytes of the input buffer to io_Data,
  io_Actual = number copied, immediate reply **as soon as at least one byte** is available; empty buffer ⇒
  the request stays queued (IOF_QUICK cleared) until bytes arrive (key, report); the
  queued requests are served in order.
- Input buffer: ring of **255 useful bytes** per unit, emptied by CMD_CLEAR (probe: 60 reports of
  5 bytes = 300 bytes written ⇒ 255 bytes read back (51 reports), the rest lost).
- **io_Length = 0**: V34 bug — the "−4" reply is made then the code reads the unit's queue via a
  **non-initialised** register (value left by the caller) ⇒ undefined behaviour (probe: Guru
  `#00000003` with A2 = 1 at the BeginIO call). A reimplementation must reply −4 (IOERR_BADLENGTH) cleanly. [O ROM+probe]
- io_Length = −1: treated as "1 byte at most". [O ROM]
- No echo, no editing, no CR → LF conversion: that is the console-handler's (CON:) job.

---

## 7. What differs on a real A500

- **No direct hardware dependency**: console.device touches neither CIA nor custom registers; everything
  goes through graphics (Text, RectFill, ScrollRaster → blitter), layers, intuition and input.device. The
  behaviour is therefore identical on a real A500; only the speed changes (ScrollRaster and Text on the
  real blitter). [O ROM]
- **Real raw codes**: a US A500 keyboard produces `$00–$0D`, `$0F–$1B` (`$1D–$1F` keypad), `$20–$2A`,
  `$2D–$2F`, `$31–$3A`, `$3C–$46`, `$4A`, `$4C–$5F`, `$60–$67`; non-US keyboards add `$2B`
  (next to Return) and `$30` (left of Z). The ROM keymap gives `$2B` ⇒ **nothing** (NOP) and `$30` ⇒
  `<`/`>`. **The A500 keypad keys `( ) / * +` (`$5A–$5E`) are NOP in the ROM keymap**: they
  produce nothing until a `SetMap` (disk keymap, e.g. usa1) has been loaded. [O ROM+probe;
  list of physical codes: D, public documentation]
- **Non-US keyboards** (the user is on AZERTY): the ROM only knows "usa"; the startup-sequence's `SetMap f`
  loads a keymap into RAM and passes it to **CD_SETDEFAULTKEYMAP** (and, for the console of the
  current CLI, CD_SETKEYMAP) — only the units opened **afterwards** inherit the default (§5.4). [O ROM for
  the device; D for the SetMap mechanism, not probed here]
- **Real repeat**: repeats come from input.device with IEQUALIFIER_REPEAT; on the ROM keymap,
  **Return, Enter, Esc and Help do not repeat** (Repeatable table), unlike the
  letters, arrows and F1–F10. [O ROM+probe]
- **Font and size**: the cell follows the font of the window's RastPort at open (Preferences:
  topaz 8 ⇒ 8 × 8, topaz 9 ⇒ 10 × 9 on this ROM without a system disk); in NTSC the screen has 200 lines,
  in PAL with a 256-line screen YMax changes accordingly. [O probe for topaz 9; D for the rest]
- **Input injection under FS-UAE**: xdotool "alt+…" keystrokes do not arrive as Amiga Alt in
  this harness (Alt-k ⇒ `k`), and F1/F10 produced nothing; dead keys and Fn were therefore validated
  through RawKeyConvert and IND_WRITEEVENT, not through the emulated keyboard. [O probe]

---

## 8. Test vectors (real ROM 34.5, FS-UAE, probe `tests/con_probe.s`)

Probe: `tests/con_probe.sh <sortie> 600` (real ROM by default). 640 × 200 window (borders 4/12/18/2),
topaz 9 ⇒ 10 × 9 cell, XMax 60, YMax 19. Each test starts with `ESC c FF`. Notation of the results:
text recognised per line and cursor position (XCP, YCP).

### 8.1 Controls and cursor

| Input (after ESC c FF) | Result |
|---|---|
| `AB LF CD CR LF EF` (LNM) | `AB` / `CD` / `EF`, cursor (2,2) |
| `CSI 20l AB LF CD LF CR EF` | `AB` / `··CD` / `EF` |
| `ABC BS BS X CR Y` | `YXC`, cursor (1,0) |
| `AB LF BS X` (AWM) | X at (60,0), cursor (0,1) after wrap |
| `CSI ?7l AB LF BS X` | X at (0,1) |
| `HT A HT B HT HT C` | A col 8, B col 16, C col 32 |
| `CSI 3;10H CSI A A CSI 2B B CSI 5C C CSI 3D D CSI 0A E CSI -2B F` | A (9,1); B (10,3); C (16,3); D (14,3); "E2BF" at (15,2) (the intermediate `-` abandons the sequence) |
| `ABCDEF CSI H 1 CSI 2H 2 CSI ;5H 3 CSI 3;f 4 CSI 0;0H 5` | `5BCD3F` / `2` / `4` |
| `CSI 99;999H X` | X at (60,19), wrap + scroll: cursor (0,19) |
| `L1 L2 L3` (3 lines) `CSI 1;1H CSI 2A T` | scroll down by 2: `T` / empty / `L1` / `L2` / `L3` |
| same with `CSI >1l` | no scroll: `T` replaces L1 |
| `CSI 1;78H CSI 5C X` | X at (4,1) |
| `CSI 2;3H CSI 5D X` | X at (58,0) |
| `CSI 3;10H CSI E A CSI 2F B CSI 0E C` | A (0,3), B (0,1), C (0,2) |
| `CSI 3;5H A VT B $8D C` | A (4,2), B (5,1), C (6,0) |
| `CSI 20l A $84 B $85 C` | A (0,0), B (1,1), C (0,2) |
| `AB ESC D C ESC E D ESC M E ESC [2;8H F` | `AB` / `·EC····F` / `D` |
| `A ESC 7B ESC (0C ESC #8D ESC =E ESC aF ESC ESC [2CG` | `ACD` / `F··G` (ESC 7 B = ESC B ignored; ESC = E = NEL) |
| `A CSI 2 LF B CSI 1; ESC [CC CSI !pD CSI 5 HE CSI 1 CSI 2CF` | `A` / `B·CDE··F` |
| `A CSI 2!CB CSI 3 CC CSI !2CD` | `ABC2CD` |
| `ABC CSI 10GX CSI 3dY CSI 2XZ` | `ABCXYZ` (G, d, X ignored) |
| `A $80 $81 $86 $90 $9A $9F B $7F C` | `AB` + glyph `$7F` + `C` |
| `A $01 B $1C C $1F D` | `ABCD` |

### 8.2 Clears, insertions, scrolls

| Input | Result |
|---|---|
| `ABCDEFGH CR LF IJKLMNOP CSI 1;4H CSI K CSI 2;4H CSI 1K` | `ABC` / `IJK` |
| `ABCDEFGH CSI 1;4H CSI 2K` | `ABC` |
| 3 lines `CSI 2;4H CSI J` | `ABCDEFGH` / `IJK` / empty |
| `ABCDEFGH CSI 1;3H CSI @ CSI 1;7H CSI 3@ x` | `AB·CDEx··FGH` |
| `ABCDEFGH CSI 1;3H CSI P CSI 1;4H CSI 2P x` | `ABDxH` |
| `L1 L2 L3 CSI 2;2H CSI L x` | `L1` / `·x` / `L2` / `L3` |
| `L1 L2 L3 L4 CSI 2;2H CSI 2M x` | `L1` / `Lx` (L4) / empty |
| `L1 L2 L3 L4 CSI S CSI 2T x` | empty / empty / `L2` / `L3x` (cursor fixed at (2,3)) |
| `TOP CSI 24;1H BOT LF N` | TOP gone, `BOT` line 18, `N` line 19 |
| same with `CSI >1l` | `TOP` stays; `N` overwrites `B` on line 19 |
| `CSI 5t CSI 20u` + A…Z + `CSI 5;1H X LF Y` | XMax 19, YMax 4, XRExtant 203, YRExtant 56; `UVWXYZ` / empty / empty / `X` / `Y` |
| then `CSI t CSI u Q` | XMax 60, YMax 19; Q at (1,4) |
| `CSI 16x CSI 20y AB` | XROrigin 16, YROrigin 20, XMax 59, YMax 18 |
| then `CSI x CSI y C CSI 0x CSI 0y D` | XROrigin 0, YROrigin 0, XMax 61, YMax 21 |

### 8.3 Automatic wrap (20-column page: `CSI 20u`)

| Input (20 characters = full line) | Result |
|---|---|
| 20 chars `LF B` | B at (0,1) (LF absorbed) |
| 20 chars `CR LF B` | B at (0,1) |
| 20 chars `B LF C` | B (0,1), C (0,2) |
| 20 chars `CSI E B` / `CSI F B` | B at (0,1) (absorbed) |
| 20 chars `LF LF B` | B at (0,2) (only the first LF is absorbed) |
| 20 chars `VT B` | B at (0,0) (VT is **not** absorbed) |
| `CSI 20l` + 20 chars `LF B` | B at (0,1) (IND absorbed) |
| 18 chars `HT LF B` | B at (0,1) (HT wrapped the line) |
| 20 chars `BS X` | X replaces T at (19,0), cursor (0,1) |
| `CSI 1;19H CSI 2C LF B` | B at (0,1) |
| `CSI ?7l` + 23 chars | `ABCDEFGHIJKLMNOPQRS` + `W` in column 19, cursor (19,0) |

### 8.4 SGR and colours (mask of the colours present in the cell)

| Input | Result |
|---|---|
| `CSI 2m D` | D in colour 2 |
| `CSI 7m R` | R in inverse (background 1, text 0) |
| `CSI 8m H CSI 0m N` | H not drawn; **residual cursor block** in column 0 |
| `CSI 30m A … CSI 37m F CSI 39m G` | colours 0, 1, 2, 3, 0 (34), 3 (37), 1 |
| `CSI 41m B`, `42m C`, `43m D`, `44m E`, `49m F` | backgrounds 1, 2, 3, 0, 0 |
| `CSI ;32m N` | SGR 0 then APen 2 (FgPen = 2) |
| `CSI 1;4;7m A CSI 22;24;27m B` | B still bold/underlined/inverse |
| `ABCDEFGH CSI 43m CSI 1;4H CSI K` | columns 3+ filled in colour 3 |
| `CSI 42m FF A` | the whole line in colour 2 |
| `CSI 43m L1 L2 CSI 1;1H CSI T` | freed line 0 filled in colour 3 (ScrollRaster ⇒ BPen) |
| `ABCDEF CSI 43m CSI 1;2H CSI 2@` | inserted cells in colour 3 |
| `ABCDEFGH CSI 7m CSI 1;4H CSI K` | clearing in colour 0 (DrawMode ≠ JAM2) |
| `AB CSI 0 SP p` | no more cursor block |
| `C CSI SP p D CSI 0p E CSI p` | cursor visible (`0p`/`p` without space ignored) |

### 8.5 Reports, modes, input

| Input | Result |
|---|---|
| `xyz` with io_Length −1 | io_Actual 3, io_Error 0; io_Length 0 ⇒ io_Actual 0 |
| `CSI 6n` then CMD_READ | `9B 31 3B 35 52` (line 1, column 5) |
| `CSI 5n CSI n CSI 6;6n ESC [6n` | two reports |
| `CSI SP q` | `CSI 1;1;20;61 r` |
| `CSI 0 q`, `CSI q`, `CSI ␠␠q` | a single report (the first) |
| CMD_READ without data, abort after 10 frames | io_Error −2, io_Actual 0 |
| `CSI 20l CSI >1l CSI ?7l CSI 3h` | cu_Modes `08 00 00` |
| `CSI 20h CSI >1h CSI ?7h CSI 3l CSI 1;2;19h` | cu_Modes `06 00 78` |
| `CSI 1;2;18;19;-1{` | nothing is executed: the `-` is an intermediate, the `1` that follows abandons the sequence and `1{` is displayed; cu_RawEvents stays `00 00 00` |
| SizeWindow(−200, −64) then empty CMD_WRITE | XMax 40, YMax 12, XRExtant 413, YRExtant 128; report `CSI 1;1;13;41 r`; before the write: unchanged |
| SizeWindow(+200, +64) then empty write | XMax 60, YMax 19; revealed area cleared |

### 8.6 Commands (direct BeginIO, IOF_QUICK)

| Command | io_Flags after | io_Error |
|---|---|---|
| 0, 4, 13, 14, `$7FFF` | `$81` | −3 |
| 1, 6, 7, 8 | `$81` | 1, 6, 7, 8 (residual D0) |
| 5 (CLEAR) | `$01` (no reply) | 0 |
| 5 without IOF_QUICK | request never returned (ln_Type 5) | — |
| 4 without IOF_QUICK | returned (ln_Type 7) | −3 |
| CMD_STOP then CMD_READ (report available) | READ not served (abort −2); after CMD_START: served | — |
| CMD_READ io_Length 0 (A2 = 1) | Guru `#00000003` | — |

### 8.7 SIMPLE_REFRESH and GIMMEZEROZERO windows (400 × 100)

| Window / input | Result |
|---|---|
| SIMPLE_REFRESH: `HELLO CR LF WORLD` then `ESC c X` | `XELLO`…: **nothing is cleared** by ESC c, cursor (1,0) |
| GZZ: open | XROrigin 0, YROrigin 0, XMax 36, YMax 8, YRExtant 80 |
| GZZ: `CSI 16x` | XMax 35, **YMax 6** (the height loses 16 pixels) |
| GZZ: `CSI x CSI 16y` | **YMax 8**, YRExtant 96 > inner height 86 (the vertical origin is not subtracted) |

---

## 9. Open points

1. **Cooking of real keystrokes** (chain keyboard.device → input.device → intuition → console) not
   probed end to end with Alt and the function keys: this harness's xdotool injection does not
   transmit Alt as Amiga Alt and F1/F10 gave nothing. The contents of ie_X/ie_Y rely on
   `intuiticks-repeat-v34.md` §2.1. To be redone with another injection means (debugger, or
   keyboard.device directly).
2. **Resized window not active**: the recomputation is applied to the active unit, not to that of the
   resized window [O ROM]; the visible effect on an inactive console has not been probed.
3. **SUPER_BITMAP**: not probed (the recomputation clears nothing and does not reposition the cursor; cursor
   possibly not redisplayed — to be checked).
4. **SetMap of Workbench 1.3.3**: whether it calls CD_SETDEFAULTKEYMAP and/or CD_SETKEYMAP and on which
   unit has not been verified on the disk (D, documented use).
5. **Overflow of parameter values** (> 32767): CSI 65535C bounded the cursor as expected,
   but the exact arithmetic (16 × 16 signed product, partial saturation) is not specified beyond that.
6. **BEL**: DisplayBeep read in the ROM, visual effect (screen flash) not captured.
7. **Order of the units for NEWACTIVE**: the first unit of the list (the most recently opened) on the
   window becomes active [O ROM]; not probed with two units open simultaneously.

---

## Clean-room review

- [x] No 68000 instruction sequence transcribed or paraphrased, no disassembly excerpt,
  no ROM routine address. The only ROM data reproduced are **functional ABI data**:
  contents of the "usa" keymap (values per key, as a table), strings returned/emitted, sizes and
  offsets of public structures (`conunit.h`, `keymap.h`) and constants.
- [x] The automata and algorithms (§3.2, §5.2) are described by their **inputs/outputs and visible
  effects**, verified by the black-box probe, not by the structure of the code.
- [x] The probe cited is author code (`tests/con_probe.s`, header "ASSET DE TEST, PAS du code ROM").
