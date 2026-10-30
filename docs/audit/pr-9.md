# Clean-room audit of PR #9 (DF1 support) — 2026-10-30

Outside contribution by warpdesign, head `2dc68e4`, base `2c64df4`. Audit gate of `CLAUDE.md` ("Pull requests").

**Verdict: PASS for what the PR adds.** The PR adds no match with the original ROM that is longer than its base's
longest one, its AROS similarity figures are those of its base, and the manual review found nothing. One match
above the notable threshold exists in BOTH ROMs; it comes from our own keymap data (commit `2ad7da5`), not from
this PR, and is followed up separately (section 4).

## 1. Binary similarity (separate analysis agent)

Reference: a Kickstart 1.3 (34.5) A500 ROM image, not in the repository. Reported here: statistics, plus offsets and symbols
in OUR ROMs only.

### Inputs

| role | tree | ROM sha1 | relinked map image |
|---|---|---|---|
| PR (head 2dc68e4) | PR worktree | aa08a378c2f87cd5f2e3c9ce85117e75b9d869ad | 203,252 bytes, `cmp` = head of `build/kick13-prod.rom` |
| base (2c64df4) | base worktree | 0ce05f9786399b88c06f6bd76316a79804850e3b | 202,700 bytes, `cmp` = head of `build/kick13-prod.rom` |

The PR does not change the `Makefile`, so both trees use the object list from `docs/audit/rom-similarity.md`.
Controls are the ones from the original audit (the file lists of `docs/audit/rom-similarity.md`): tiers 21 hunks / 596,048 B,
commodore 390 / 413,374 B, aros 50 / 1,167,084 B. These numbers match the original run.

### Commands

```sh
# in each worktree (wt, base); OBJS = list from docs/audit/rom-similarity.md
vlink -b rawbin1 -T src/exec/kick.ld -M<work>/kick-prod-<pr|base>.map -o <work>/kick-prod-<pr|base>.bin $L
cmp <work>/kick-prod-<n>.bin <(head -c $(stat -c%s <work>/kick-prod-<n>.bin) build/kick13-prod.rom)   # OK for both
# measurement (groups as in docs/audit/rom-similarity.md, run from the repository root)
python3 -I tests/audit_rom_similarity.py <rom> assets/kick34005.A500 --temoin tiers ... --temoin commodore ... \
    --temoin aros ".../adf/aros/AROS Kickstart" --map <map> --base tiers --selftest      # -> audit-<pr|base>.txt
# extra: list every match of >= 8 tokens (same tool, --seuil 8, no controls)          # -> all8-<pr|base>.txt
python3 -I tests/audit_rom_similarity.py <rom> assets/kick34005.A500 --map <map> --seuil 8
```

### Figures (our ROM vs reference)

| stream | metric | base | PR | threshold (tiers max + 1) |
|---|---|---|---|---|
| mots | A tokens | 98,143 | 98,419 | |
| mots | max code/table | 76 | 76 | 40 |
| mots | code >= 8 / >= 16 / >= 32 | 74 / 7 / 2 | 71 / 6 / 2 | |
| mots | 4/8/16-gram | 2.6 / 0.9 / 0.4 % | 2.6 / 0.9 / 0.4 % | |
| instr | max code/table | 17 | 17 | 19 |
| instr | code >= 8 / >= 16 | 6 / 2 | 6 / 2 | |
| instr-souple | max code/table | 17 | 17 | 19 |
| instr-souple | code >= 8 / >= 16 | 14 / 2 | 14 / 2 | |
| self-test | relocated fragments found | 12/12 | 12/12 | |

The control rows (tiers, commodore and aros vs reference) are identical to the original audit. The "our ROM vs
control" rows differ by at most one match or 0.1 %.

### Matches at or above the notable threshold

- **instr / instr-souple:** none in either ROM.
- **mots (40 words):** two code/table matches of 76 words in both ROMs, `keymapdata.o` `km_us_s42+$0` and
  `km_fr_s42+$0`. In the PR they are at $0B328 and $0B660; in base, at $0B14C and $0B484. They are keymap
  string-table data (`dc.b` key sequences) that the classifier cannot recognise. They came in with commit 2ad7da5
  (real keymaps), after the published audit (ec9f9ab), and the PR does not touch `keymapdata.s`.
  The same symbols are also the longest `instr` matches (17 tokens). The 9 classified-data rows
  (inittabs, `topaz8_loc`, `dos_rtinit`) and the 2 low-entropy instr-souple rows are unchanged, apart from address shifts.

### PR code matches longer than base's longest code match

Base longest code match: mots 76, instr 17, instr-souple 17. **None.** No PR match exceeds these values.

For completeness, here are the matches of >= 8 tokens that appear only in the PR, compared by symbol with base.
All of them are below the base maxima:
- `handler.o` `hnd_init+$12`, 8 words. This is code the PR changed: the `tst.l d0` that replaces `move.l d0,HND_CTX`
  ends the matched span. The span is the generic sequence `move.l #MEMF,d1 / jsr AllocMem(a6) / tst.l d0 / beq`.
- `input.o` `input_romtag+$2`, 14 words, a RomTag in a file the PR does not change. Base instead lists
  `timer_romtag+$C` (13) and `trackdisk_romtag+$C` (16), which the PR does not report. These are layout-dependent
  boundary effects on ABI-fixed RomTags.
- `dos_lib.o` `dos_initfunc+$1C`, 8 words. It was `+$20` in base: the same match, moved because the PR deletes one line.
- Gone in the PR: `boot.o` `fnt_ta8`, `setup_demo_tasks` ×2. `km_fr_s42` instr/instr-souple is 16 instead of 17,
  because the linear disassembly lines up differently.

### Verdict (binary)

**FAIL (literal rule), inherited from base; PR delta = PASS.** The only match above the threshold is the 76-word
`km_us_s42`/`km_fr_s42` keymap data. It is identical in base 2c64df4 and does not come from this PR. The PR adds no
match longer than the base's longest in any stream, and its only new match in changed code (`hnd_init`, 8 words)
is a generic AllocMem idiom. Separately from PR #9, the keymap-data match needs its own review: a classifier
rule, or re-documenting it as mandated data.

## 2. AROS similarity

`tests/audit_aros_similarity.py <src> <aros-clone>` on the `src/` of the PR and of its base, same AROS clone as
`docs/audit/aros-similarity.md`. Every table row and every "longest passage" is the same in both runs; the only
differences are line-number shifts inside files the PR edits (for instance `dos/handler.s:963` becomes `:997`).
Longest passages, PR = base: exact 39 tokens (the ABI-fixed `bcpl_call`), norm 42, struct 49.

## 3. Manual review of the diff

- No ROM routine address or offset, no "seen in the ROM" wording, no instruction listing in comments or docs.
- One comment mentions the "original trackdisk" motor timer; it predates the PR and was only rewrapped.
- The external-drive identification follows the Hardware Reference Manual (public). New data: the string
  `"dos.handler.df1"` and the device base layout; nothing taken from the ROM.
- No new file under `docs/analysis/`.

## 4. Follow-up outside this PR: keymap string tables

The 76-word matches `km_us_s42` / `km_fr_s42` are the string tables of the cursor keys, F1-F10, Help and
Shift-Tab in `src/exec/keymapdata.s`, generated by `tests/mk_keymaps.py` from the CSI sequences documented for
console.device, in the public `struct KeyMap` string format (length, offset pairs, then the bytes). Almost every
byte is fixed by the documented sequences, the key order and that layout, which explains the match (to be
confirmed by the follow-up review). They are mandated data, not code, but
`docs/audit/rom-similarity.md` was measured before they existed (`ec9f9ab`) and must be updated to list them.
