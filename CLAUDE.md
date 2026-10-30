# CLAUDE.md — operating rules (clean-room Kickstart 1.3)

Mission: reimplement a **1.3-compatible** Kickstart (256K @ `$FC0000`, 68000) in a clean room.
Roadmap → `docs/PLAN.md`. Architecture → `docs/ARCHITECTURE.md`. Discipline → `docs/CLEANROOM.md`.

## Clean-room firewall — ABSOLUTE RULE

- Two **sealed** tracks. NEVER write `src/` code based on the ROM disassembly.
- **ANALYSIS** track ("dirty"): reads the ROM (`assets/`, radare2/ghidra), writes ONLY to `docs/analysis/` (and its
  probes in `tests/`). Describes behaviour + ABI layout; never copied instruction sequences, never ROM routine
  addresses.
- **IMPLEMENTATION** track ("clean"): reads public docs (RKRM/NDK/AutoDocs/`.fd`), AROS (`third_party/`, read-only)
  and `docs/analysis/`; writes `src/`. NEVER reads the ROM or its disassembly.
- Before an analysis spec feeds the implementation: check that it contains **no transcribed code** and no ROM
  addresses. ROM *data* shown in a spec (images, tables) is described, never redrawn from memory right after reading
  it (see `docs/AUDIT.md`).
- The proprietary ROM is NEVER committed (gitignore) nor modified (it is `chmod 444`).

## Pull requests — clean-room audit gate (BEFORE any merge)

Outside contributors are not bound by our firewall. A PR is merged only after this audit, even when it looks clean.
1. **Isolate**: `git fetch origin pull/<N>/head:pr-<N>`, then a worktree in the scratchpad. Never merge, rebase or
   build the PR inside the main tree before the verdict.
2. **Build** in the worktree: `make` and `make kick-prod` (`is_kick ok`), plus the vlink map of the production ROM
   (commands in `docs/audit/rom-similarity.md`, "Commands"). Build `main` the same way: it is the baseline.
3. **Binary audit = separate analysis agent** (it reads the ROM, so never inline). Brief it to:
   - run `tests/audit_rom_similarity.py` on the PR ROM AND on the `main` ROM, with the same controls, `--map` and
     `--base tiers` as in `docs/audit/rom-similarity.md`;
   - report only statistics, offsets and symbols from the map, never ROM content;
   - write in English.
4. **Verdict rules**:
   - FAIL if any code/table match reaches the "notable" threshold: the longest `tiers` match + 1, currently
     19 instructions / 40 words.
   - Otherwise, any code match that is new compared with `main` and longer than `main`'s longest code match (13
     instructions) must be located with the map. If it falls inside lines changed by the PR, review it before
     going on.
5. **AROS audit**: `tests/audit_aros_similarity.py` on the files changed by the PR (`docs/audit/aros-similarity.md`).
   ABI-imposed sequences (`bcpl_call`/`bcpl_ret`) are expected; anything else above the baseline is reviewed.
6. **Manual diff review** (implementation side, no ROM). Reject or ask about:
   - ROM routine addresses, offsets inside the ROM, or "taken from / seen in the ROM" wording;
   - instruction listings in comments or docs;
   - data tables, strings, images or fonts whose provenance is not stated (see the data cases in `docs/AUDIT.md`);
   - `docs/analysis/` specs added by the PR, which need the same "no transcribed code" check.
7. **Provenance**: ask the contributor, in a PR comment drafted for the user to post, to confirm they did not use
   the ROM or its disassembly.
8. **Record** the result in `docs/audit/pr-<N>.md` (English: commands, figures, verdict). Give the user the verdict
   in French. Merge only with the user's go-ahead, then rerun the full validation on the merged tree.

## Routing: when to delegate to a dedicated agent

- Any **ROM analysis** task → a separate "analysis" agent, to keep the wall. Do not mix analysis and implementation
  in the same context.
- A module's implementation can be done inline, but its context must hold only specs + public docs.

## Language

- **Code comments** (`src/`, `tests/`, `Makefile`, scripts) and **everything under `docs/`** are written in
  **English**. Exception: the French counterparts `*.fr.md` (`README.fr.md`, `docs/AUDIT.fr.md`), kept in sync with
  their English version.
- Never translate **string literals** in code (displayed text, serial markers, script output parsed by harnesses).
- Analysis agents write their specs in English; tell them so in every brief.
- Conversation with the user stays in French.

## Build / test (reference)

- `make hello` → `build/kick13-hello.rom` · `make verify` (romtool `is_kick`) · `tests/boot_test.sh` (FS-UAE boot).
- End-of-step ADF suite: `tests/adf_suite_winuae.sh` (WinUAE Linux, cycle-exact A500, see `docs/HARDWARE.md`).
- Toolchain required in PATH: `vasmm68k_mot`, `vlink`, `romtool` (amitools), `python3`, `fs-uae`, `Xvfb`.
- Asm syntax check = the `vasm` build itself (no `py_compile`). Python reading data: `python3 -I`.

## Code conventions

- Assembly in **vasm Motorola** syntax, **strict 68000** (no instruction above 68000: no 060-only `RESET`, no 020+
  addressing). Low-level code runs without a stack until RAM/overlay is set up.
- `correctness > maintainability > performance > brevity`. No dead code, no unused variable.
- No comment unless the WHY is non-obvious.

## Quality gate before declaring "done"

- Every ROM image produced MUST pass `romtool info` (**is_kick = ok**) before being tested.
- Behaviour milestone: proven by an **FS-UAE boot** (captured screen and/or serial marker), never "assumed". Record
  the result (command + output) in the `.superpowers/sdd/` ledger.

## After any significant change

- Update `docs/ARCHITECTURE.md` and `docs/PLAN.md` in the SAME session (in English).
