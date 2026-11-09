---
description: Public repository hygiene — no disk image file names, dump or crack tags, or personal paths in anything committed
globs: ["**/*"]
---

# Public repository hygiene

> Applies to every committed file (docs, specs, tests, scripts, sources) and to commit messages, PR texts and
> GitHub comments. The repository is public.

## Disk images

- Never write the full file name of a disk image: no TOSEC-style names with year and publisher in parentheses
  (`Title (1991)(Publisher)(...)`), and no dump or release tags: `[cr X]`, `[h X]`, `[t +N X]`, `[a]`, `[m]`,
  `[m2]`, `[f]`, `[b]`.
- Name a disk by its title ("Holiday Lemmings 1993", "Deluxe Paint III v3.00, disk 1", "the Workbench 1.3.3 boot
  disk"), or by its short local alias in `assets/` (`wb133.adf`, `boot_c.adf`).
- Never name the group behind a cracked release. When a cracktro is the subject of an analysis, name the program
  file on the disk (`NOMAD`, `flt-intro`), not the release tag.
- Scripts find their disks through a short alias in `assets/` or an environment variable, never a full image name.
  `assets/` and `assets/test_adf/` stay git-ignored; their file names are local only.

## Personal data

- No local path (`/mnt/c/Users`, `/home/<user>`, the scratchpad), e-mail address or machine name in a committed file
  or a commit message.

## Check before every commit and push

```sh
git diff --cached -- . ':!.claude/rules/public-repo.md' | grep -nE '^\+' | grep -nE '\[(cr|h|t) [^]]+\]|[ )`]\[(a|m|m2|f|b)\]|\([0-9]{4}\)\([A-Z]|/mnt/c/Users|/home/[a-z]+/|claude-1000'
```

No output is expected. Fix any hit before committing; old commits are not rewritten.
