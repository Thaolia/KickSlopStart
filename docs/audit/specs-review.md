# Clean-room audit of the analysis specs — 2026-10-29

Scope: `docs/analysis/` (50 files). Method: review of texts only (the ROM was not
opened, no disassembler run); comparison with `src/` by searching for values.

Criteria (see `docs/CLEANROOM.md`): a spec describes behaviour and ABI; it contains no
instruction sequence transcribed or paraphrased step by step, no disassembly, and no routine address/offset in
the ROM. Allowed: hardware addresses (`$DFFxxx`, `$BFxxxx`), RAM addresses, LVOs, offsets of
public or private structures, values written to registers.

---

## 1. Review of the 19 specs without a "Clean-room review" section

Each file received a "## Clean-room review" section dated 2026-10-29.

| File | Problems found | Correction |
|---|---|---|
| `module-map.md` | (a) For the 24 ROMTags: file offset and ROM address of the tag, of `rt_Name`, `rt_IdString`, `rt_Init`, `rt_EndSkip`; addresses of the auto-init tables (`vectors`, `structure`, `initFunction`); value of the reset PC; bounds of the exec range; tie-breaks illustrated by addresses (≈ 164 occurrences). (c) Full text of the copyright banner, value of the image checksum, example of a negative offset of the mathffp table. | Table rewritten without any address (flags, type, pri, revision); auto-init table reduced to size / encoding / number of LVOs / presence of the fields; tie-breaks expressed in relative order; banner and checksum removed. |
| `dos-boot-sequence.md` | (a) dos ROMTag and `rt_Init`; ROM address of each of the quoted strings (≈ 45 occurrences). | Addresses removed; strings kept (ABI names, rendered texts). Copyright not reproduced. |
| `trackdisk-official-timing.md` | (a) ROMTag, `rt_Init`, module bounds, "routine map" (12 addresses), default tables, locations of the ADKCON writes and of the constants, location of the `/RDY` test (≈ 57 occurrences). (b) The `/STEP` pulse was described by the instructions ("two `NOP`s", idiom "write CIA → 2 NOP → CIA access"); headings "exact sequence / routine". | Map replaced by a list of functions by role; pulse described by its duration (≈ 1 µs deliberate wait); sequences rephrased as observable effects on the registers. |
| `dos-v34-spec.md` | (a) ROMTag, `rt_Init`/`rt_EndSkip`, `rt_Name`, `rt_IdString` and addresses of the BSTR strings (9 occurrences). | Addresses removed; relation `rt_Init == rt_EndSkip` kept without value. |
| `test-vectors.md` | (a) Reset PC (A2), exec `rt_Init`/`rt_EndSkip` (B5), addresses of the three pri 0 tags (C1), reference to the tags' "offsets". | Assertions rephrased in relative terms (reset PC = `rt_Init`, position order). |
| `boot-sequence.md` | (a) Address of the coldstart entry point (3 occurrences) and bounds of the exec range. | Replaced by "address in the ROM" / "range of the exec module". |
| `coldstart-hardware-v34.md` | (a) Value of the reset PC. (b) Name and opcode of the instruction placed before the entry point, mention "no BSR/JSR", iteration counts of the delay loops. (c) RAM/stack test patterns (`$F2D4B698`, `$F1E2D3C4`), with no ABI relevance. | Entry point without address; instruction replaced by its effect; iterations replaced by the durations; patterns replaced by "test pattern". |
| `exec-spec.md` | (a) ROM address of exec's `rt_IdString`. | Removed. Substantive remark (not corrected): the "Delta V34 → 2.0" list contradicts §5 on `AddMemList`/`CopyMem`/`CopyMemQuick`. |
| `fault-v34.md` | (a) ROM "landmarks": entry of `fault()`, BCPL segment, BSTR strings, offsets of the globin table; header presenting the ROM addresses as landmarks. | Removed; global numbers and emitted strings kept. |
| `alert-v34.md` | None. | — |
| `audio-device-v34.md` | None. | — |
| `autoconfig-v34.md` | None (Zorro II / slow RAM / UAE board addresses only). | — |
| `fastfonts-ff.md` | None (third-party software; no Kickstart data). | — |
| `graphics-blitter-v34.md` | None. | — |
| `graphics-display-v34.md` | None; point of attention: formulas of §4.4 and merge of §5.2 very fine-grained, to be used through the probed vectors. | — |
| `octamed-v34.md` | None (third-party software; ROM only executed). | — |
| `setpatch-disk-resource.md` | None (disk program); reported: two ROM code patterns expected by SetPatch (`$70E56000`, `$E2EF`) quoted as conditions for applying it. | — |
| `sysinfo-44.md` | None (third-party software; "H0+..." offsets internal to SysInfo). | — |
| `trackdisk-write-v34.md` | None (public MFM format, order of hardware accesses). | — |

Final check: no `$FCxxxx`–`$FFxxxx` address of a ROM routine or ROM data remains in these 19
files (what remains: the base `$FC0000`, the header offsets `$FC0004`/`$FC000C`, the generic range
`$FC0000–$FFFFFF` and masks such as `$00FF0001`).

### 1.1 Initial finding on the other specs (corrected, see §1.2)

These specs already had a "Clean-room review" section but still contained addresses of
ROM routines or data (often in a header "Landmarks" block):

| File | Occurrences | Where |
|---|---:|---|
| `workbench-task-v34.md` | 47 | header, §1.1 ROMTag, table of init steps, miscellaneous |
| `intuition-prefs-v34.md` | 37 | "Landmarks" header (including the default pointer image and the default prefs), body |
| `handlers-v34.md` | 21 | dos `rt_Init`, `cliinit`, globals table |
| `intuition-prop-v34.md` | 17 | header |
| `bcpl-runtime-v34.md` | 15 | ROM segarray, globals table by segment |
| `keyboard-handshake-v34.md` | 15 | header, body |
| `intuition-gzz-v34.md` | 13 | header |
| `intuition-frame-v34.md` | 12 | header |
| `boot-clock-v34.md` | 5 | validator landmarks |
| `caesar-boot.md` | 4 | graphics landmarks (VBlank server, copinit) |
| `cracktros-exit.md` | 3 | graphics landmarks |
| `loadwb-13.md` | 3 | CLI loop, endstream |
| `monkey-startup.md` | 2 | timer.device, trackdisk |

### 1.2 Cleanup of the 13 specs (2026-10-29, second pass)

Same rules as §1. Each file received, in its existing review section, a line
"Correction of 2026-10-29". The type (ii) data of §2 were not modified.

| File | Removed | Rephrasing |
|---|---|---|
| `workbench-task-v34.md` | 47 addresses: ROMTag and its pointers, entry points, `main`, main loop, abort / title / Info routines, "Landmark" column of §3.1, exec AddTask, "Workbench" string; description of the encoding of the entry points ("padding", operation on D0) | Positions **relative to the tag** kept (+26/+34/+42/+44) because mandated by `c:LoadWB` (disk program); observable effect kept (selector, `D0 := D0 OR 2`, requirement D0 = 0); Kickstart version read through the size field of the ROM footer, without address |
| `intuition-prefs-v34.md` | 37: "Landmarks" block (vectors and bodies of Set/Get/GetDefPrefs, default table, pointer image, TextAttr, mouse, NEWPREFS, init, `cliinit`) and body addresses | List of the functions covered; table §4.3 unchanged |
| `handlers-v34.md` | 21: dos `rt_Init`, `cliinit`, local routines, environment table, console-handler, makeglobvec, starthandler, deviceproc, "object" routine, "Address" column | Global numbers and contracts kept |
| `intuition-prop-v34.md` | 17: "Landmarks" block | List of the functions covered |
| `bcpl-runtime-v34.md` | 15: ROM segarray, "Landmark" column, start of the ROM CLI | Globals, GV offsets and carrier segments kept; hunk offset of `c:Run` (disk) kept |
| `keyboard-handshake-v34.md` | 15: "Landmarks" block + 2 in the body | List of the modules; CIA registers (hardware) kept |
| `intuition-gzz-v34.md` | 13: header | List of the functions studied |
| `intuition-frame-v34.md` | 12: header | List of the functions; §5.3 (type (ii)) intact |
| `boot-clock-v34.md` | 5: landmarks of the validator and of the FS | — |
| `caesar-boot.md` | 4: VBlank server, copinit | Function names |
| `cracktros-exit.md` | 3: header | Function names |
| `loadwb-13.md` | 3: CLI loop, endstream | — |
| `monkey-startup.md` | 2: timer.device, ciab.resource | — |

The mentions "ROM addresses are only landmarks" in the headers and the review sections
were replaced by "no ROM address (removed on 2026-10-29)".

### 1.3 Final recount over the 50 specs

Search for any `$FCxxxx`–`$FFxxxx` value (with or without `$00`, or `0x`), excluding the base `$FC0000`,
the header offsets `$FC0004`/`$FC000C`, the range bounds `$FCFFFF`/`$FFFFFF`/`$F80000` and the values
`…FFFF`:

| Result | Count | Detail |
|---|---:|---|
| Addresses of ROM routines or data | **0** | — |
| False positives (not addresses) | 3 | mask `$00FF0001` (`alert-v34.md`, `coldstart-hardware-v34.md`) and data pattern `$00FF0F0F` (`graphics-blitter-v34.md`) |
| **Justified** ROM address references kept | — | base `$FC0000` and range `$FC0000–$FFFFFF` (public memory map), header offsets `+$0C/+$0E`, positions relative to the `workbench.task` tag (+26...+46, contract mandated by `c:LoadWB`), SetPatch conditions `$FC0000–$FFFFFF` / `$F80000`, `lib_IdString` within the first 64 KB (`sysinfo-44.md`) |

No unjustified ROM address remains in `docs/analysis/`.

---

## 2. Inventory of data taken from the Kickstart ROM (50 specs)

Classification: **(i)** ABI or observable-format data, mandated for compatibility (rendered
values, structures, displayed texts); **(ii)** reproduced creative or functional data, which
would be better described than copied. These passages were **not** modified (decision of the person in charge).
Lines: state as of 2026-10-29 after the two correction passes.

| File | Lines | Nature | Size | Opinion |
|---|---|---|---|---|
| `console-keymap-v34.md` | 492–497 | "usa" keymap: raw Capsable/Repeatable Lo and Hi bytes | 30 bytes | (i) — but the raw bytes could be replaced by the list of keys they designate (already given alongside) |
| `console-keymap-v34.md` | 499–612 | "usa" keymap: value returned by RawKeyConvert for 104 codes × 8 qualifiers (+ type, Caps, Rep.) | ≈ 115 table rows | (i) — observable output of RawKeyConvert, verified by probe; functional content of a keyboard layout |
| `console-keymap-v34.md` | 614–631 | "usa" dead keys: 5 accents × 8 modifiable keys, codes of the space | ≈ 15 lines | (i) — observable output |
| `intuition-input-menus-v34.md` | 517–530 | **ROM images** in ASCII art: hires checkmark 15×8 and lores 9×8, Amiga symbol hires 23×8 and lores 14×8 | 4 images, 32 pixel rows | **(ii)** — drawings from the ROM; describing the format (size, PlanePick, bit order, LeftEdge) would be enough |
| `intuition-input-menus-v34.md` | 477, 511, 788 | Menu ghosting pattern `$4444/$1111` | 2 words | (ii) minor — visual effect; a description ("one line in two, one pixel in four") would be enough |
| `intuition-frame-v34.md` | 145–197 (§5.3) | **Pixel geometry of the pictograms** of the system gadgets (depth front/back, close, size; hires and lores): exact coordinates of each rectangle | 8 pictograms | **(ii)** — pixel-exact transcription of the ROM images, equivalent to a copy; a description of principle ("black square behind a hollow square", box sizes) would be enough |
| `intuition-frame-v34.md` | 74–83, 96–103 | Drag pattern (8 lines, lines 2-3 and 6-7 solid) and inactivity veil (1 pixel in 4, offset) | 2 patterns described | (ii) minor — already described, not copied as values |
| `intuition-prefs-v34.md` | 196–234 (§4) | Table of the ROM's **default Preferences** (field by field, 232 bytes) | ≈ 38 lines | (i) — values returned by GetDefPrefs |
| `intuition-prefs-v34.md` | 36, 86–99 | Default colours (`$05A $FFF $002 $F80`, pointer `$D22 $000 $FCA`), ROM / file comparison | 7 colours | (i) |
| `intuition-screens-v34.md` | 250–257 | Palette of a new screen (32 colours = prefs + graphics table) | 32 words | (i) — values returned by GetRGB4 |
| `graphics-display-v34.md` | 183–185 | graphics default colour table | 32 words | (i) — returned by GetColorMap/GetRGB4 |
| `graphics-display-v34.md` | 152–177 (§2) | Contents of **copinit** (startup copper list, 92 bytes) | ≈ 25 lines | (i) — in chip RAM, observable, programs depend on it (`caesar-boot.md` §2.7) |
| `graphics-display-v34.md` | 349–368 | Copper lists produced (probed examples) | 4 excerpts | (i) — probed outputs |
| `alert-v34.md` | 135–138, 186–199 | Guru: palette `$111`/`$F20`, three headers, "Press left mouse button to continue.", format `Guru Meditation #%08lx.%08lx`, x/y positions of the blocks | 5 short strings, 6 numbers | (i) — observable display |
| `alert-v34.md` | 139–147, 238 | Frame geometry, blink counter 26,633 | a few numbers | geometry (i); counter (ii) minor — the observed period (≈ 0.9 s/phase) is enough |
| `coldstart-hardware-v34.md` | 310–317, 335–344 | alert.hook texts (duplicate of alert); screen colours `$444`, `$888`, `$CC0`, `$0C0` | 4 colours | (i) — observable |
| `module-map.md` / `test-vectors.md` | module-map 15–19, test-vectors 13–19 | Header `0x11114EF9`, version `0x00220005`, size `0x00040000` | 3 longs | (i) — image format verified by `romtool` |
| `dos-v34-spec.md` | 29–32 | BSTR templates `{3,"DFX"}`, `{11,"File System"}`, `{11,"FileHandler"}`, `{24,"CON:0/0/640/200/AmigaDOS"}` | 4 strings | (i) — ABI names / visible window title |
| `dos-boot-sequence.md` | 35–57, 60–70, 84–95 | Names (libraries, devices, `L:`, `C:`, assigns), messages of the CLI and of the disk requesters | ≈ 30 short strings | (i) — ABI names and displayed texts |
| `bcpl-runtime-v34.md` | 268–282, 331, 481, 540, 590–591 | ROM CLI messages ("Error in command name", "Unknown command %S", "Unable to load %S:", "too many > or <", "command too long", "%S failed returncode %N"...), `abort`/`deviceproc` requesters | ≈ 12 strings | (i) — displayed texts |
| `handlers-v34.md` | 96–101, 144, 249, 295 | Mount templates (`L:RAM-HANDLER`, `L:PORT-HANDLER`, CON), requester "Please insert volume … in any drive" | ≈ 6 strings | (i) |
| `disk-change-v34.md`, `disk-full-write-v34.md` | disk-change 182–205, 335–336; disk-full 66, 146, 157 | Observed requester texts ("Please replace volume", "Error validating disk", "Key 880 checksum error", "Volume … is full") | ≈ 8 strings | (i) — screenshots |
| `fault-v34.md` | 20, 36, 79 | Fallback string `Error code %N\n` | 1 string | (i) |
| `intuition-requesters-v34.md` | 228, 324 | "System Request", "=LEFT BUTTON OK=", "=RIGHT BUTTON CANCEL=" | 3 strings | (i) |
| `intuition-screens-v34.md` | 433, 442, 540–541 | Title "Workbench Screen"; border bytes recorded `0B 01 05 02 04 02 04 04 02` | 1 string, 9 bytes | (i) — values read back from memory |
| `workbench-task-v34.md` | 278, 436, 458, 476–481, 525, 627, 667–669, 715–717 | ROM Workbench texts: title "Workbench release 1.2.  %ld free memory", "Kickstart version %ld.%ld. Workbench version %ld.%ld", "Enter the new name.  Press return when done.", "Error while %s: %ld" + table of 9 actions, "Do not use '%lc' in names", "Cannot read info file %s", "Ran out of memory.  Please free some and try again.", "This disk cannot be copied", "Info not available"... | ≈ 20 strings | (i) — observable screen titles |
| `octamed-v34.md` | 261, 326 | Banner of the initial CLI ("Copyright © 1987 Commodore-Amiga, Inc." / "All rights reserved." / "Release 1.3") | 3 lines | (i) — displayed text; contains a copyright notice |
| `setpatch-disk-resource.md` | 125, 106–109 | ROM code patterns expected by SetPatch: long `$70E56000` (head of the dos LVO −222 entry), word `$E2EF` (exception handler) | 6 bytes | (ii) — ROM instruction bytes, seen through SetPatch; useful as conditions for applying it |

Outside the ROM (not inventoried as Kickstart data): message table of `c/Fault` (`fault-v34.md` §4),
strings "We made Amiga, T" / "Still a Champion" (LoadWB 1.3.3, disk, `workbench-task-v34.md`
490–494), palettes and strings of OctaMED, SysInfo, FastFonts, Preferences, games and cracktros, UAE memory
dump (`uae-int2-v34.md` 221). No spec contains a font glyph (topaz) or an image
of the default pointer: these data are only mentioned (size), with an address in
`intuition-prefs-v34.md` (see §1.1).

---

## 3. Check of `src/`: identical data

Search for the values above in `src/` (read-only, no modification). The line
numbers are those of the working tree of 2026-10-29 (`menus.s` has uncommitted changes there;
the checkmark data are the same as in the last commit).

### 3.1 Exact or near-exact matches

1. **System gadget pictograms** — `src/intuition/screens.s` l. 1563–1580 (`pic_front_h`,
   `pic_back_h`, `pic_close_h`, `pic_size_h` and lores variants). The comment states "drawn
   freely from their geometric description (spec §5.3)", but the rectangles reproduce **the
   exact coordinates** of `intuition-frame-v34.md` §5.3. Examples: hires back, hollow square
   x 4–17 y 1–6 and black rectangle x 8–21 y 3–8 ⇔ `0,4,1,17,6` / `2,8,3,21,8`; hires close, frame
   x 8–23 y 1–8, black square x 14–17 y 4–5, bars x 4–5 and 26–27 ⇔ `0,8,1,23,8` / `2,14,4,17,5` /
   `0,4,0,5,9` / `0,26,0,27,9`; hires size x 2–7 y 1–3 and x 6–13 y 3–7 ⇔ `0,2,1,7,3` / `0,6,3,13,7`.
   The expected rendering is **pixel-identical** to the ROM images.
2. **Menu checkmark** — `src/intuition/menus.s` l. 1025–1039 (`mn_chk_hi_data`, `mn_chk_lo_data`).
   The comment says "drawn for KickSlopStart (not the ROM image)". Comparison with
   `intuition-input-menus-v34.md` l. 522–529 (15 useful bits per line):
   - hires: src lines 1, 2, 3 and 7 (`$FFE7`, `$FFCF`, `$FF9F`, `$F1FF`) are **identical**
     to ROM lines 2, 3, 4 and 8 (`$FFE6`, `$FFCE`, `$FF9E`, `$F1FE`, apart from the padding bit):
     same drawing shifted one line up; src lines 5 and 6 (`$CE7F`, `$E4FF`) differ
     by a single pixel from ROM lines 6 and 7 (`$C67E`, `$E0FE`); src line 4 and src line 8
     differ;
   - lores: src line 5 (`$33FF`) is identical to ROM line 5 (`$3380`) over 9 bits; src line
     4 (`$79FF`) differs by one pixel from ROM line 4 (`$F980`); the rest differs.
   Shape very close to the original in hires; to be redrawn if clear independence is wanted.
   The **Amiga symbol** is not reproduced (replaced by a cat, `mn_cat_*`, no match).
3. **Default palette** — `src/intuition/screens.s` l. 3180–3184 (`sc_palette`): entries 4–16,
   18 and 20–31 (`$00F $F0F $0FF $FFF $620 $E50 $9F1 $EB0 $55F $92F $0F8 $CCC $000 … $444 … $FFF`)
   **identical** to the graphics table (`graphics-display-v34.md` l. 184–185,
   `intuition-screens-v34.md` l. 255–256); entries 0, 17, 19 different (project theme). (i).
4. **Default Preferences** — `src/intuition/prefs.s` l. 286–309: FontHeight 9, BaudRate 5,
   KeyRptSpeed 0.1 s, KeyRptDelay 0.8 s, DoubleClick 1.5 s, PointerTicks 2, PrinterType 7,
   `"generic"`, margins 5/75, PrintShade 1, PrintThreshold 2, PaperSize `$20`, PaperLength 66:
   **identical** to `intuition-prefs-v34.md` §4; colours 0, 17, 19 and XOffset/YOffset different.
   (i).
5. **Strings** — 50 strings of `src/` (≥ 8 characters, excluding library/device names) are found
   identically in the specs, in particular:
   - Guru: `src/exec/execmisc.s` l. 592–600 ("Not enough memory.", "Recoverable Alert.",
     "Software Failure.", "Press left mouse button to continue.", "Guru Meditation #") and
     x/y positions 38/234/142, y 15/30 (l. 244–267); palette `$111`/`$F20` (`src/intuition/alert.s`);
   - Workbench: `src/dos/workbench.s` l. 4325–4414 (title "Workbench release 1.2.  %ld free
     memory", Version text, Rename, "Error while %s: %ld" and the 9 actions, "Do not use '%lc' in
     names", "Cannot read info file %s", "Ran out of memory.  Please free some and try again.",
     "This disk cannot be copied", "Info not available", menus "Duplicate", "Clean Up",
     "Last Error", "Snapshot", "Initialize");
   - DOS: `src/dos/shell.s` l. 1065, 1503–1506 ("Can't open", "Unknown command", "Unable to
     load", "failed returncode"), `src/dos/dos_lib.s` l. 1708–1710 ("Please insert volume",
     "Please replace volume", "in any drive"), l. 1998/2079 (`L:RAM-HANDLER`, `L:PORT-HANDLER`),
     `src/dos/bcpl.s` l. 2878 ("Error code");
   - miscellaneous: "expansion ram", "Fast Memory", "Chip Memory", "Workbench Screen",
     "System Request", `devs:system-configuration`.
   All are displayed texts or ABI names: (i).
6. **copinit** — `src/graphics/graphics_lib.s` l. 318–322: WAIT `$0C01,$FFFE`, MOVE COPJMP2, end
   `$FFFF,$FFFE` = the end of the ROM copinit (`graphics-display-v34.md` §2, offsets `$48`–`$57`); reduced
   list (no sprite pointers). (i).
7. **Exception handler in the SetPatch shape** — `src/exec/interrupts.s` l. 658–670: shape
   "bsr.s + subtraction of 6 bytes + `lsr.w 2(sp)` (`$E2EF $0002`)", mandated by SetPatch
   (`setpatch-disk-resource.md` §5.3, source = SetPatch, not the ROM); interoperability constraint.
   The pattern `$70E56000` does not appear in `src/`.
8. **Instruction placed before the entry point** — `src/rom/start.s` l. 45 and `src/exec/boot.s`
   l. 167 (`dc.w $4E70`, RESET): same layout as the one `coldstart-hardware-v34.md` described in
   §1.1 (rephrased today as an observable effect). One word.

### 3.2 No match

- **Keymap**: `src/exec/keymapdata.s` (generated by `tests/mk_keymaps.py`) is a simple table
  96 codes × (unshifted, shifted), without a KeyMap structure or Capsable/Repeatable bits. Of the 132
  comparable values, 106 coincide with the spec's "usa" keymap — these are the ASCII
  characters of the US layout — and 26 differ (numeric keypad, key `$30` which gives `<`/`>` in the
  ROM). Alt and Ctrl columns, dead keys, Capsable/Repeatable bytes: absent from `src/`.
  Coincidence mandated by the layout, not a copy.
- Amiga symbol, ghosting pattern `$4444/$1111` (src: home-made stripes), texts of the copyright banner,
  ROM banner, `$70E56000`, counter 26,633 (src: 46 frames per phase): absent from `src/`.

### 3.3 Strings in `src/` with no provenance in the specs

`src/dos/workbench.s` l. 4294–4296 ("Warning: you cannot get back", "what you discard!",
"OK to discard") resemble the Workbench 1.3 texts but appear in no spec of
`docs/analysis/` (added with step 10). Their provenance (screenshot, public
documentation) should be noted.

---

## 4. Recommendations

1. ~~Cleanup pass on the 13 specs of §1.1~~: done on 2026-10-29 (§1.2).
2. Decide what to do with the (ii) data: images of the checkmark and of the Amiga symbol
   (`intuition-input-menus-v34.md` 517–530) and pixel geometry of the pictograms
   (`intuition-frame-v34.md` §5.3) — to be replaced by a description of principle if we want
   `src/` to redraw freely.
3. On the `src/` side: the hires checkmark (`menus.s`) and the pictograms (`screens.s`) are, respectively,
   very close to and identical to the ROM images; to be redrawn if the goal is graphical
   independence, to be documented as a reproduction of appearance otherwise.
