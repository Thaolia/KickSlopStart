# DiskMaster graphics fixes: clean-room audit (2026-11-09)

Verdict: **PASS** for the measured implementation snapshot against upstream `c5074c8`.
The binary comparison ran in a separate analysis context. This report contains only aggregate statistics,
our symbols and artifact hashes; no reference ROM code, bytes, addresses or artwork.

## Scope and provenance

The implementation changes are confined to `src/intuition/screens.s`, `gadgets.s` and `menus.s`:

- Preserve short positive window heights instead of imposing a 16-pixel minimum.
- Initialize ordinary window fonts and `IFont` from the screen. Preserve the 1.3 GIMMEZEROZERO exception:
  the border port and `IFont` use the screen font while the inner port retains the global default.
- Clear string gadgets only within valid complete text cells and their buffer padding capacity.
- Preserve pens, drawing mode and coherent per-plane minterms during the initial proportional-knob press.
- Initialize the menu bar, item box and submenu ports with the screen font and style.

The fixes were authored from public interfaces, existing behavior specifications and behavior-only reports
from isolated reference runs. No official ROM implementation or artwork was copied. Regression glyphs,
patterns and guard pixels are authored test data. Generic code adds no CPU-specific conditionals or dependencies.
Edited files have no copyright year requiring extension; the public API library version remains unchanged.
The build continues to generate its release identification from Git.

## Binary comparison

Both base and candidate were built as development and production ROMs. All four images are 262,144 bytes
and pass `romtool info` (`is_kick` and `chk_sum`). Production link maps were generated from the same object
lists as their builds and checked against the corresponding raw linked binaries.

| Artifact | SHA-256 |
|---|---|
| Base production ROM | `b08756489a9573b6e769ee23bcea148ac34eeef71d0c634a0573d959426607fb` |
| Candidate production ROM | `6070c8a3e1f56ef1953f629ffae9395fc7d718b3d344d5c1a12235fee173ffec` |
| Candidate raw link | `dbc4a5daf349d060b252630825f3dc8e0bb3a7f3e16464c23ea3f03c081db612` |

The audited candidate is the uncommitted implementation snapshot with build ID `v0.2.32-dirty`.
Subsequent documentation or commit-ID changes may alter the ROM identification and checksum; the source hashes
and raw implementation link must remain identical to this audited snapshot.

Commands (paths are placeholders):

```sh
python3 -I tests/audit_rom_similarity.py <base-or-head.rom> <reference256.rom> \
  --map <matching.map> --temoin wb13-available <same-controls> \
  --temoin aros-available <same-controls> --base tiers --seuil 8 --selftest
python3 -I tests/audit_rom_similarity.py <base-or-head.rom> <reference256.rom> \
  --map <matching.map> --temoin wb13-available <same-controls> \
  --temoin aros-available <same-controls> --base tiers --seuil 4
```

Capstone 5.0.7 measured words, exact instructions and normalized instructions.
After the established generated/public-data exclusions:

| Metric | Base | Candidate |
|---|---:|---:|
| Longest code match, words | 19 | 19 |
| Longest code match, exact instructions | 13 | 13 |
| Longest code match, normalized instructions | 13 | 13 |
| Relocated-fragment self-check | 12/12 | 12/12 |

No code match reaches the established notable thresholds of 40 words or 19 instructions.
No new code match exceeds the 13-instruction baseline. The only added row in the eight-token listings is an
8-word RomTag-classified match in an unchanged component; no added code/table row occurs in a changed object.
The lower-threshold helper and relocated-body rows do not indicate increased code matches.

**Limit:** the original unrelated `tiers` corpus was unavailable, so its empirical maxima were not recomputed.
The established fixed thresholds were applied, as in the previous unavailable-corpus audit. The same available
Workbench and AROS selections were used for both artifacts as diagnostic controls; this is not a full `tiers` run.
A binary similarity check cannot prove independent origin after arbitrary semantic rewriting.

## AROS source comparison

The same existing AROS comparison checkout (`4dbf6509`) was used for base and candidate: 65 comparable assembler
files / 22,757 tokens, 202 unrelated assembler files / 374,229 tokens, 2,439 comparable C files and 1,308 unrelated
C files, with a 599-file ABI whitelist. This is the existing sparse comparison corpus, not a newly reconstructed
full checkout.

```sh
python3 -I tests/audit_aros_similarity.py <base-or-head-src> <aros-corpus> \
  -k 12 20 30 --limit 20 --json <result.json>
```

| Exact match coverage against comparable AROS assembler | Base | Candidate |
|---|---:|---:|
| k=12, matched tokens | 8,196 | 8,196 |
| k=20, matched tokens | 132 | 132 |
| k=30, matched tokens | 69 | 69 |

Exact matched-token counts are unchanged at all tested lengths, including the unrelated control groups.
At k=20/30 the comparable coverage remains 0.044% / 0.023%. Reported normalized and structural passages were
reviewed against the changed-line ranges; none intersects a changed line. Existing BCPL calling-convention,
copy-loop and register-save idioms remain in the baseline. No new notable source similarity was found.

## Behavioral validation

`make test-quick` passed with the installed Copperline 1.0.1 and native 68000 toolchain. This includes the existing
blitter pixels/state/performance, raster lifetime and allocation-priority tests, plus:

- `LONGFRAME`: PAL scanline 312 is reachable after `LoadView(NULL)` from a short-frame state.
- `SMALLWIN`: short requested heights, layer bounds and pixels below the window are preserved.
- `WINFONT`: ordinary/borderless window fonts, the GZZ font exception, text advance and sentinel lines.
- `STRBOUNDS`: string-gadget extra rows/columns and buffer-capacity guards, including shortened-text refresh.
- `PROPSTATE`: real raw-input knob press/drag/release, both button messages, preserved pens/mode/minterms and
  replacement template pixels.
- `MENUFONT`: real right-button input, menu bar, item box and submenu rendered widths using a word-aligned,
  authored six-pixel font.

The new behavior probes reproduced the corresponding failures on the pre-fix ROMs. Isolated official-ROM
probes confirmed short-window behavior, the GZZ font exception, string bounds, proportional-knob state and
the word-aligned authored menu-font probe (bar, items and submenu).
Live DiskMaster checks and user verification confirmed the helper height, button labels, path-field lower border,
horizontal refresh and menu rendering fixes.

**Unavailable validation:** the legacy Amiberry pre-push script was not run. Its boot and Lemmings disk fixtures
are not present on this machine, as confirmed by the user; its existing session helper also assumes Linux tools.
The native quick suite and targeted emulator results above are reported separately and do not claim that legacy
suite passed. No proprietary ROM or disk image is included in this change.
