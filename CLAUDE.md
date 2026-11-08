# CLAUDE.md — operating rules (clean-room Kickstart 1.3)

Mission: reimplement a **1.3-compatible** Kickstart (256K @ `$FC0000`, 68000) in a clean room.
Where to look for what → "File References" below. Scoped rules: `.claude/rules/amiga-asm.md` (assembly sources),
`.claude/rules/cleanroom-analysis.md` (`docs/analysis/` specs).

## Core Principles

### Clean-room firewall — ABSOLUTE RULE

- Two **sealed** tracks. NEVER write `src/` code based on the ROM disassembly.
- **ANALYSIS** track ("dirty"): reads the ROM (`assets/`, radare2/ghidra, Amiberry), only inside a dedicated agent
  (next section), writes ONLY documentation in `docs/analysis/`. Describes behaviour + ABI layout; never copied
  instruction sequences, never ROM routine addresses.
- **IMPLEMENTATION** track ("clean"): reads public docs (RKRM/NDK/AutoDocs/`.fd`), AROS (`third_party/`, read-only)
  and `docs/analysis/`; writes `src/`. NEVER reads the ROM or its disassembly.
- Before an analysis spec feeds the implementation: check that it contains **no transcribed code** and no ROM
  addresses. ROM *data* shown in a spec (images, tables) is described, never redrawn from memory right after reading
  it (see `docs/AUDIT.md`).
- Never extract data embedded in the ROM (fonts, keymaps, images, strings): author it by hand or with a generator
  script under `tests/mk_*.py`, and state its provenance.
- The proprietary ROM is NEVER committed (gitignore) nor modified (it is `chmod 444`).

### Official Kickstart: reverse engineering only in a dedicated documentation agent — ABSOLUTE RULE

- FORBIDDEN in the main context and in any implementation agent: reading, disassembling, decompiling, running,
  debugging or probing the official Kickstart ROM (`assets/kick34005.A500`, or any copy of it under another name).
  Black-box observation (a probe run, a trace, an emulator log of the real ROM) counts as probing too.
- Such work runs ONLY in a **separate agent spawned for that purpose**. That agent writes **no code at all** (nothing
  in `src/`, `tests/`, scripts, `Makefile`): **documentation only**, in `docs/analysis/`, in English, behaviour and
  ABI, with no ROM address and no transcribed instruction. If a probe program would help, the agent describes it in
  its report; it is written outside the agent, from that description only.
- To run the ROM, the agent uses the `/amiberry` skill when it is available (`amiberry-session start --analysis`:
  sessions in `build/amiberry/analysis/`). The main context never reads those sessions, nor any raw output of the
  agent (disassembly, dumps, logs): only its final report and the `docs/analysis/` pages, after the
  "no transcribed code" check above.

## Routing & Delegation

### Direct execution (main context)
- Implementing a module from specs + public docs + AROS; building, booting and debugging **our** ROM.
- Running third-party programs (games, intros, Workbench tools) on our ROM, and disassembling them to learn their
  behaviour. Keep only behaviour, never their code.

### Separate agent
- Any **ROM analysis** task → a separate "analysis" agent that writes documentation only (Core Principles), to keep
  the wall. Do not mix analysis and implementation in the same context. Tell it to write in English, every time.
- PR binary audits (Operational Protocols), because they read the ROM.
- Long debugging or disassembly sessions on our ROM or a third-party program: delegate so dumps stay out of the main
  context; the agent returns conclusions only.

### Ask the user
- Before merging a PR, deleting a test ADF, or replacing a validation harness the user chose.
- When a spec and the observed behaviour of a real program disagree and no oracle probe can settle it.

## Operational Protocols

### Pull requests — clean-room audit gate (BEFORE any merge)

Outside contributors are not bound by our firewall. A PR is merged only after this audit, even when it looks clean.
1. **Isolate**: `git fetch origin pull/<N>/head:pr-<N>`, then a worktree in the scratchpad. Never merge, rebase or
   build the PR inside the main tree before the verdict. Audit the PR against **its own base**, not today's `main`.
2. **Build** in the worktree: `make` and `make kick-prod` (`is_kick ok`), plus the vlink map of the production ROM
   (commands in `docs/audit/rom-similarity.md`, "Commands"). Build the base the same way: it is the baseline.
3. **Binary audit = separate analysis agent** (it reads the ROM, so never inline). Brief it to:
   - run `tests/audit_rom_similarity.py` on the PR ROM AND on the base ROM, with the same controls, `--map` and
     `--base tiers` as in `docs/audit/rom-similarity.md`;
   - report only statistics, offsets and symbols from the map, never ROM content;
   - write in English.
4. **Verdict rules**:
   - FAIL if any code/table match reaches the "notable" threshold: the longest `tiers` match + 1, currently
     19 instructions / 40 words.
   - Otherwise, any code match that is new compared with the base and longer than the base's longest code match (13
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

### Behaviour oracle

- When the expected 1.3 behaviour is unclear, ask an analysis agent for a black-box probe on the real ROM (a probe
  described in its report, a copied ADF with a rewritten startup-sequence, a screenshot) before calling it a bug.
- Never treat a spec as proven: several specs turned out wrong. When a probe refutes a spec, have the analysis agent
  fix the page in `docs/analysis/` in the same session.
- For a third-party program that hangs, ask for its exact call sequence and exit conditions, then check each call on
  our side.

### Debugging

- Install exception vectors that report on the serial line early; in a burst of exceptions, chase the **first** one.
- Prefer low-RAM counters read back at the end of a run to breakpoints; when serial is silent, trace into an
  AllocMem'd buffer whose pointer sits at a fixed address and dump it with the debugger.
- Build trace variants with `-D` flags (`MEMTRACK`, `DOSTRACE`, `GFXTRACE`) in a separate `BUILD=` directory and
  resolve addresses with the `vlink -M` map. Never leave a trace flag on in the dev or prod ROM.
- Name the cause with a discriminating experiment (pure delay vs interrupt mask, A/B variant removing one
  component). An unexplained timing fix is not a fix.
- When a regression follows an unrelated diff or depends on ROM layout, suspect a latent race or an out-of-block
  write: bisect by padding/layout and look at the stuck state, not at the diff.
- Slow is not stuck: check DMACONR (blitter busy), give it time, compare with HEAD and with the real ROM (through
  the analysis agent) before reporting a regression. Measure performance on `make kick-prod` only.

### Concurrent sessions and emulators

- Another Claude session may edit the tree: validate in a worktree (HEAD + my own hunks only) and check the ROM md5
  before committing.
- Never kill an emulator by name and never `amiberry-session stop --all`: stop only the sessions or PIDs you started.
- One X display per harness: two harnesses on the same display mix their screenshots.
- Test on **copies** of ADFs (scratchpad or session directory); FS-UAE ties its write overlay to the ADF file name,
  so use a fresh name per run.

## Coding Standards

- Assembly in **vasm Motorola** syntax, **strict 68000** (no instruction above 68000: no 060-only `RESET`, no 020+
  addressing). Low-level code runs without a stack until RAM/overlay is set up. Detailed ABI and hardware rules:
  `.claude/rules/amiga-asm.md`.
- Check every LVO offset against the `.fd`/AROS `.conf`, never against memory or a web summary.
- Build probes and executables for KS 1.x with `vasmm68k_mot -Fhunkexe -kick1hunks`.
- Check the exit code of `vasmm68k_mot`/`vlink` and that the ROM md5 changed: a branch-range error (2029) or a link
  failure can leave a stale or truncated ROM behind.
- `correctness > maintainability > performance > brevity`. No dead code, no unused variable.
- No comment unless the WHY is non-obvious.

### Language

- **Code comments** (`src/`, `tests/`, `Makefile`, scripts) and **everything under `docs/`** are written in
  **English**. Exception: the French counterparts `*.fr.md` (`README.fr.md`, `docs/AUDIT.fr.md`), kept in sync with
  their English version.
- Never translate **string literals** in code (displayed text, serial markers, script output parsed by harnesses).
- Analysis agents write their specs in English; tell them so in every brief.
- Conversation with the user stays in French.

## Build / Test (reference)

- `make` → dev ROM `build/kick13.rom` · `make kick-prod` → production ROM (no runtime test harness, `-DPROD=1`) ·
  `make kick-ram` → image linked at `$C00000` · `make adf` → soft-kick disk ·
  `make hello` → smoke ROM · `make verify` (size, `is_kick`, checksum).
- Pre-push regression: `.claude/skills/amiberry/scripts/prepush-check [rom]` (3 parallel Amiberry sessions).
- Targeted runs: `/amiberry` skill (headless sessions, serial log, gdb, screenshots, scripted input);
  `tests/boot_test.sh` (FS-UAE boot) for the older harnesses.
- Toolchain required in PATH: `vasmm68k_mot`, `vlink`, `romtool` (amitools), `python3`, `fs-uae`, `Xvfb`.
- Asm syntax check = the `vasm` build itself (no `py_compile`). Python reading data: `python3 -I`.

## Quality Gates

- Every ROM image produced MUST pass `romtool info` (**is_kick = ok**, checksum ok) before being tested.
- Behaviour milestone: proven by a boot under emulation with a **serial marker AND a screenshot you have looked
  at**, never "assumed". A harness "OK", an `ls` of the capture or identical colour counts prove nothing.
- Before a push: `prepush-check` passes; count `FAIL` (not only `FAILED`) in its logs and look at the Lemmings
  menu capture. Then run targeted Amiberry sessions on the ADFs the change touches. The WinUAE ADF suite is no
  longer run (user decision, 2026-11-02).
- Performance claims: measured on `make kick-prod`, compared with HEAD on the same harness.
- Record the result (command + output) in the `.superpowers/sdd/` ledger.

## File References

Plain links, no `@`: these files are long and are read when the question comes up, not at every session start.

| Question | Document |
|----------|----------|
| What is next, what is done | `docs/PLAN.md` · `docs/REMAINING-WORK.md` (gaps to 1.3 parity) |
| Module layout, memory map, boot flow | `docs/ARCHITECTURE.md` · `docs/analysis/module-map.md` |
| Clean-room method, what a spec may contain | `docs/CLEANROOM.md` · `docs/AUDIT.md` (`docs/AUDIT.fr.md`) |
| Similarity audits, PR records | `docs/audit/rom-similarity.md` · `docs/audit/aros-similarity.md` · `docs/audit/pr-*.md` |
| Behaviour of a 1.3 subsystem | `docs/analysis/<subsystem>-v34.md` · `docs/analysis/coverage-v34.md` |
| Emulators, toolchain versions, hardware | `docs/HARDWARE.md` |
| exec LVO table, DOS design, memory budget | `docs/exec-lvo-table.md` · `docs/D3-dos-design.md` · `docs/MEMORY-USAGE.md` |
| Running and debugging a ROM live | `.claude/skills/amiberry/SKILL.md` · `.claude/skills/amiberry/reference.md` |

## Self-Improvement

- After any significant change: update `docs/ARCHITECTURE.md` and `docs/PLAN.md` in the SAME session (in English).
- A refuted spec is fixed in `docs/analysis/` by an analysis agent, never patched from the implementation side.
- A new trap (emulator quirk, ABI subtlety, harness pitfall) goes into the scoped rule it belongs to
  (`.claude/rules/`), or into memory if it is a one-off; keep this file for instructions, not facts.
- When a user decision makes a harness or procedure obsolete, remove it here and in the amiberry skill in the same
  session.
- Personal preferences (local paths, aliases, tooling) go into `CLAUDE.local.md` (add it to `.gitignore`
  first, it is not ignored yet), never into this file.
