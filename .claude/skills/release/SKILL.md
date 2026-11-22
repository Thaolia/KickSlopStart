---
name: release
description: Use when the user explicitly asks to cut a release of this Kickstart, to "tag v0.2.xx", or to "publish the version" — validates the commit, pushes the tag, and follows the GitHub release workflow to its published assets.
---

# Release

A release is a `v*` tag pushed to GitHub. `.github/workflows/release.yml` then builds `make kick-prod adf` with
`KSS_VERSION=<tag>`, checks the images with `romtool`, and publishes the ROM and the soft-kick ADF with notes made
of `.github/release-notes.md` plus the commits since the previous `v*` tag. This skill only validates, tags and
watches; the build that ships is the workflow's.

## When to use
- The user asks for a release, a tag (`v0.2.71`), or to publish the current state.
- Not for: an ordinary push (`prepush-check` alone), a dev or trace ROM, a PR merge (audit gate in `CLAUDE.md`).
- Never start it on your own: a tag is created only when the user asks for that release (`CLAUDE.md`, "Commits and
  releases").

## Inputs
- Version: the one the user names. Default: the next patch after `git tag --sort=-creatordate | head -1`; say which
  one you picked before tagging.
- Commit: `origin/main` HEAD. If the working tree holds another session's uncommitted work, validate in a worktree
  at that commit, never on the shared tree.

## Steps
1. Sync — `git fetch`, then `git pull --ff-only`; `git status` shows nothing of yours left uncommitted, and the
   tag does not exist yet (`git rev-parse -q --verify refs/tags/<tag>` prints nothing).
   Gate: the commit to tag is on `origin/main`. Stop otherwise.
2. Build — `make`, `make kick-prod`, `make adf`; check each exit code, then `make verify` (dev ROM) and
   `romtool info build/kick13-prod.rom` (`is_kick ok`, `chk_sum ok`). Never pipe a build to `/dev/null`.
   Gate: both ROMs pass, and their md5 differs from the images present before this step, if any (the ROM ID carries
   `git describe`, so a stale image keeps the old md5).
3. Regression — `.claude/skills/amiberry/scripts/prepush-check` (set `PP_PREFIX` if another session runs it).
   Gate: exit 0, no `FAIL` line in its logs (count `FAIL`, not only `FAILED`), and you have looked at the
   Lemmings menu screenshot. Then run targeted `/amiberry` sessions on the ADFs the changes since the last tag touch.
4. Soft-kick hosts — only when `git diff <last tag>..HEAD --stat` touches coldstart, `src/softkick/`, CIA or
   memory setup; otherwise record "skipped: no soft-kick change". Invoke `/amiberry` to boot
   `build/KickSlopStart.adf` from the A600 (2.05) and A1200 (3.x) host ROMs in `assets/` (user-approved for tests
   only, never for reverse engineering), the A1200 with `-- -s cpu_model=68020 -s chipset=aga`, each once
   cycle-exact and once not (`-s cpu_compatible=false -s cpu_cycle_exact=false -s cycle_exact=false`).
   Gate: every run reaches the KickSlopStart insert-disk screen, seen on a screenshot you looked at.
5. Public text — run the `.claude/rules/public-repo.md` pattern on `git log <last tag>..HEAD --format=%B`
   (commit messages land in the release notes). If the "What works" state changed, `.github/release-notes.md`,
   `README.md` and `README.fr.md` are updated and committed first (back to step 1).
   Gate: no hit.
6. Tag — `git tag <tag>` on the validated commit, then `git push origin <tag>`. Never `--force`, never
   `git push --tags`.
   Gate: `git ls-remote --tags origin <tag>` shows the commit.
7. Workflow — `gh run list --workflow release --limit 1`, then `gh run watch <id> --exit-status`; then
   `gh release view <tag>`.
   Gate: run green, the release lists `KickSlopStart-<tag>.rom`, the `.adf`, `SHA256SUMS` and `MD5SUMS`.

## Stop on failure
- Report the failing step, its real output, and what was NOT done after it.
- Never skip a gate to finish the sequence. A tag pushed before a failed workflow stays: tell the user, never
  delete or move a published tag yourself.

## Report
- Tag, commit, release URL; result of each gate (marker counts, screenshots looked at, skipped steps and why).
- Tell the user in French.
