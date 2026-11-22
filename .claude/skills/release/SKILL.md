---
name: release
description: Use when the user explicitly asks to cut a release of this Kickstart, to "tag v0.2.xx", or to "publish the version" — validates the commit, pushes the tag, and follows the GitHub release workflow to its published assets.
---

# Release

A release is a `v*` tag pushed to GitHub. `.github/workflows/release.yml` then builds `make kick-prod` and
`make adf` with `KSS_VERSION=<tag>`, checks `build/kick13-prod.rom` (`is_kick ok`) and `build/kick13-ram.bin`
(`chk_sum ok`) with `romtool`, and publishes `KickSlopStart-<tag>.rom`, `KickSlopStart-<tag>.adf` and
`SHA256SUMS`, with notes made of `.github/release-notes.md` plus the commits since the previous `v*` tag (the
notes also print `SHA256SUMS` and `MD5SUMS`). This skill validates the same images locally, tags, and checks
that the published files are the ones it validated.

## When to use
- The user asks for a release, a tag (`v0.2.71`), or to publish the current state.
- Not for: an ordinary push (`prepush-check` alone), a dev or trace ROM, a PR merge (audit gate in `CLAUDE.md`).
- Never start it on your own: a tag is created only when the user asks for that release (`CLAUDE.md`, "Commits and
  releases").

## Inputs
- Version: the one the user names. Default: the next patch after `git tag -l 'v*' --sort=-v:refname | head -1`;
  say which one you picked before tagging.
- Commit: `origin/main` HEAD. If the working tree holds another session's uncommitted work, validate in a worktree
  at that commit, never on the shared tree.
- `<last>` below is `git describe --tags --abbrev=0 --match 'v*' HEAD`, the base the workflow's notes use.

## Steps
1. Sync — `git fetch`, then `git pull --ff-only`; nothing of yours left uncommitted;
   `git rev-parse -q --verify refs/tags/<tag>` and `git ls-remote origin refs/tags/<tag>` print nothing.
   Record `SHA=$(git rev-parse HEAD)`.
   Gate: `$SHA` equals `git rev-parse origin/main`. Stop otherwise.
2. Build the released images — `make`, then `make kick-prod KSS_VERSION=<tag>` and `make adf KSS_VERSION=<tag>`
   (the same variable the workflow passes); check each exit code, never pipe a build to `/dev/null`. Then
   `make verify` (dev ROM), `romtool info build/kick13-prod.rom` (`is_kick ok`, `chk_sum ok`) and
   `romtool info build/kick13-ram.bin` (`chk_sum ok`, the image the soft-kick disk carries).
   Gate: every command exits 0, the three romtool checks are ok, and
   `strings build/kick13-prod.rom | grep -F "KickSlopStart <tag>"` finds the ID (proof the image was rebuilt for
   this tag). Record `sha256sum build/kick13-prod.rom build/KickSlopStart.adf`.
3. Regression, dev ROM — `.claude/skills/amiberry/scripts/prepush-check` (set `PP_PREFIX` if another session runs
   it).
   Gate: exit 0, no `FAIL` line in its logs (count `FAIL`, not only `FAILED`), and you have looked at the
   Lemmings menu screenshot.
4. Regression, released ROM — `prepush-check` cannot judge `build/kick13-prod.rom`: the production ROM does not copy
   console output to the serial port, so its markers never arrive. Invoke `/amiberry` instead: boot the Workbench
   1.3.3 boot disk on `build/kick13-prod.rom` (the skill's example: `wait-serial … "Incorrect Revision" 150`, then
   a screenshot of the opened disk window), plus the ADFs the changes since `<last>` touch.
   Gate: each run reaches its end state on a screenshot you have looked at.
5. Soft-kick hosts — only when `git diff <last>..$SHA --stat` touches coldstart, `src/softkick/`, CIA or memory
   setup; otherwise record "skipped: no soft-kick change". The host Kickstarts are Commodore ROMs: the main
   context never runs them. Spawn a **separate agent** with this brief (adapt the paths, keep the limits):
   > Clean-room Kickstart 1.3 project in <repo>. Read CLAUDE.md first. Task: boot test only, no analysis. With the
   > `/amiberry` skill, `--analysis` sessions, boot `build/KickSlopStart.adf` from the host ROMs
   > `assets/kick37350.A600` (2.05) and `assets/kick39106.A1200` (3.x; add `-- -s cpu_model=68020 -s chipset=aga`),
   > each twice: as started (cycle-exact) and with `-s cpu_compatible=false -s cpu_cycle_exact=false
   > -s cycle_exact=false`. For each of the 4 runs, look at a screenshot and say whether it shows the KickSlopStart
   > insert-disk screen (yes/no, and what is shown instead). Do not disassemble, dump or trace the host ROMs; write
   > no file outside the session directories; stop only the sessions you started. Report in English: the 4
   > verdicts and the commands you ran, nothing else.
   Read only its final report, never its session directories.
   Gate: 4 verdicts "yes".
6. Public text — the `.claude/rules/public-repo.md` pattern on the commit messages, which land in the release
   notes, without that rule's `^\+` filter (message lines have no leading `+`):
   ```sh
   PAT=$(grep -o "grep -nE '[^']*'" .claude/rules/public-repo.md | tail -1 | sed "s/^grep -nE '//; s/'\$//")
   [ -n "$PAT" ] || echo "PAT EMPTY"
   git log <last>..$SHA --format=%B | grep -nE "${PAT:-.}"
   ```
   (The pattern is read from the rule so it stays in one place; `PAT EMPTY` means the rule changed shape, and the
   `.` fallback then prints every line so the gate cannot pass silently.)
   If the "What works" state changed, `.github/release-notes.md`, `README.md` and `README.fr.md` are updated and
   committed first, then start again at step 1.
   Gate: no output.
7. Tag — `git tag <tag> $SHA`, then `git push origin refs/tags/<tag>`. Never `--force`, never `git push --tags`.
   Gate: `git ls-remote origin refs/tags/<tag>` prints `$SHA`.
8. Workflow — `gh` is not installed here; the repository is public, so read the GitHub REST API with `curl`
   (`R=https://api.github.com/repos/Thaolia/KickSlopStart`). Poll
   `curl -s "$R/actions/workflows/release.yml/runs?branch=<tag>&per_page=5"` (a tag push files its run under
   `head_branch` = the tag) until a run with `head_sha == $SHA` appears (give up after 2 minutes and report), then
   poll that run, `curl -s "$R/actions/runs/<id>"`, about every 30 s until `status` is `completed` (the build takes
   a few minutes; use Monitor with an until-loop, not a foreground sleep).
   Gate: `conclusion` is `success`.
9. Published files — `curl -s "$R/releases/tags/<tag>"` lists the assets `KickSlopStart-<tag>.rom`,
   `KickSlopStart-<tag>.adf` and `SHA256SUMS`; then
   `curl -sL https://github.com/Thaolia/KickSlopStart/releases/download/<tag>/SHA256SUMS` gives the hashes to compare
   with those recorded in step 2 (checked on v0.2.70: a local `KSS_VERSION=<tag>` build is byte-identical to the
   workflow's).
   Gate: both hashes match. A mismatch means the shipped files are not the validated ones: report it to the user
   at once.

## Stop on failure
- Report the failing step, its real output, and what was NOT done after it.
- Never skip a gate to finish the sequence. A tag pushed before a failed workflow or a hash mismatch stays: tell
  the user, never delete or move a published tag yourself.

## Report
- Tag, `$SHA`, release URL; result of each gate (marker counts, screenshots looked at, the agent's 4 verdicts or
  why step 5 was skipped, hash comparison).
- Tell the user in French.
