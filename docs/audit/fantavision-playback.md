# Clean-room audit of the Fantavision playback speed-up — 2026-11-17

Commit `9d4b7a6` ("Speed up Fantavision playback: blitter for left-clipped templates, no redundant ClearPointer"),
base `8bbb195`. Source files changed: `src/graphics/draw.s` (`bt_blit`, +14/−6) and `src/intuition/pointer.s`
(`it_ptrapply`, +16/−3); docs: `docs/ARCHITECTURE.md`, `docs/PLAN.md`.

**Clean-room verdict: PASS.** No match reaches the notable threshold, no code/table match of 4 tokens or more falls
in the changed bytes, and the AROS longest passages are unchanged.

**Follow-up (2026-11-18).** After review, the `it_ptrapply` change was dropped: it hid the pointer after the
Workbench 1.3.3 boot until the mouse moved. `src/intuition/pointer.s` is back to the base byte for byte, so the
remaining source change is `bt_blit` alone. `draw.o` is the object measured below, unchanged; the binary figures
of §1 therefore cover it (no rerun). §2 gives the AROS figures for the final diff as well.

## 1. Binary similarity (separate analysis agent)

| role | prod ROM sha1 | linked size |
|---|---|---|
| base `8bbb195` | `272d8af44f91f25938f57bdb131e0cd88cabb692` | 218,672 |
| commit `9d4b7a6` | `f2f1cac87485b5d056f70f7f7747fbaa52e45a18` | 218,712 (+40) |

Built with `make` and `make kick-prod` in detached worktrees; `romtool info`: is_kick ok, chk_sum ok. Relinks
byte-identical to `build/prod/kick.bin`; only `draw.o` and `pointer.o` differ. Commands as in
`docs/audit/pr-42.md` §1. No control-group disk was available on the machine and capstone is not importable
under `python3 -I`, so only the `mots` stream was measured, against the thresholds of the last full run
(`docs/audit/pr-44.md`: 40 words / 19 instructions / 19 loose).

| metric (`mots`) | base | commit |
|---|---|---|
| A tokens | 108,331 | 108,356 |
| max code-table | 449 (`topaz9_loc+$2`, data) | same |
| max code, data excluded | 19 (`exp_cpbinding+$22`) | same |
| code ≥ 8 / ≥ 16 / ≥ 32 | 113 / 9 / 5 | 113 / 9 / 5 |
| `--seuil 4` code/table rows | 1,344 | 1,346 |

- `--seuil 8` lists identical in content (offsets shifted after `draw.o` and `pointer.o`).
- Changed bytes: `bt_blit` and `it_ptrapply`. The three `--seuil 4` rows inside them (`bt_blit+$14A`,
  `bt_blit+$1DA`, `it_ptrapply+$1C`, 4 tokens each) are low-entropy; **no code/table row overlaps them**.
- The two extra `--seuil 4` code/table rows are classification flips in unchanged code (`pointer_input_handler+$4C`
  and one `gadgets.o` row), same lengths as in the base.

## 2. AROS similarity

`tests/audit_aros_similarity.py <dir> third_party/aros -k 12 20 30 --limit 20 --json <out>` on a directory holding
`draw.s` and `pointer.s` of the base, then of the commit. Query 35,075 → 35,157 tokens (exact).

| level, k | covered tokens vs comparable / unrelated / third-party, base → commit | longest passage |
|---|---|---|
| exact, 12 | 1,127 / 813 / 813 → identical | 19 / 19 / 19, identical |
| norm, 12 | 2,089 / 2,430 / 2,185 → identical | 24 / 28 / 28, identical |
| struct, 12 | 10,159 / 13,613 / 11,189 → 10,206 / 13,676 / 11,232 | 30 / 31 / 28, identical |
| k = 20 and 30, all levels | identical | identical |

Final diff (`draw.s` only): query 35,100 tokens (exact); exact and norm k=12 identical to the base; struct k=12
10,184 / 13,643 / 11,201; longest passages 19 / 19 / 19, 24 / 28 / 28 and 30 / 31 / 28, identical to the base.

Only the structural k=12 coverage moves, by about the same amount against unrelated AROS code as against the
comparable code (branch/test idioms).

## 3. Manual review

No ROM address, instruction listing or "taken from the ROM" wording; the comments state the behaviour and the
Fantavision observation that motivates it. Public-repo check: no hit. The change was profiled on our production
ROM only; the comparison with Kickstart 1.3 was a visual one by the user.
