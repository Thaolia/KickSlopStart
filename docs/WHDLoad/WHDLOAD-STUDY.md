# WHDLoad on KSS — feasibility study (2026-11-13)

French version: `WHDLOAD-STUDY.fr.md`.

User question: can WHDLoad be used with our ROM? Study only: no change to `src/`.

## Method

- WHDLoad, JST (JOTD Startup, its predecessor) and their Slaves were handled like the Commodore ROM: one separate
  analysis agent downloaded, ran and disassembled them, and wrote two behaviour-only pages:
  `docs/WHDLoad/whdload-host-requirements.md` and `docs/WHDLoad/jst-host-requirements.md`.
- The implementation side read only those two pages (checked: no instruction listing, no address inside the
  binaries or the ROM; `$3F5`/`$3F7` are public hunk-format constants) and the official whdload.de documentation.
- Runs: Amiberry A500, 68000 cycle-exact, 512 KB chip + 512 KB slow (one series with 2 MB fast), DH0: = host
  directory through the UAE file system, on the real Kickstart 1.3 and on our dev and production ROMs.

## Results

| Program | Real 1.3 | KSS (production) |
|---|---|---|
| WHDLoad 20.1 | "file is not an object module" (V37 hunk type `$3F7`) | identical |
| WHDLoad 0.41 / 0.88 | silent exit (OpenLibrary dos 37 fails) | identical |
| JST 4.7 | "file is not an object module" | identical |
| JST 3.1 | crash: unguarded V36 dos call (AllocDosObject) | same crash, Guru without the "task held" requester |
| JST 0.8c + JST loader (Cadaver demo) | game running | game running (25 s against 20 s) |
| JST 0.8c + WHDLoad Slave | "not a JOTD loader" (predates Slave support) | identical |
| Gamebench 2.00 (WB 1.3 front end) | window opens | identical |

## Conclusions

1. **WHDLoad cannot run on any Kickstart 1.3, ours included, and this is not a KSS bug.** Every version since the
   first public one (0.41, 1996) requires Kickstart 2.0 (V37). Our ROM refuses it at exactly the same two gates as
   the real 1.3: the V37 hunk type in `LoadSeg`, then the version check.
2. **Using KSS as the Kickstart image of WHDLoad's kickemu is impossible**: the kickemu only accepts an unaltered
   Commodore image with its `.RTB` relocation file, and it patches that image's internals (out of clean-room bounds).
3. **What KSS can run today: old JST loaders.** JST 0.8c runs a JST loader up to a playable game on the production
   ROM, as on the real 1.3. The quit key and the OS swap during a game were not observed on either ROM.
4. **JST versions that run WHDLoad Slaves (1.3 to 4.4) are not 1.3-safe** in the only one available (3.1); from 4.5
   JST requires V37 by design.

## Options

| Option | What it takes | Size | Verdict |
|---|---|---|---|
| A. Nothing (1.3 strict) | KSS already matches 1.3 on all these programs | — | **recommended** |
| B. A separate `-DV37` build exposing a 2.04-level API | exec V36/37 (CreateMsgPort, CreateIORequest, AllocVec, pools, CacheClearE, StackSwap), 26 dos V36/37 functions (ReadArgs, AllocDosObject, DOS list locking, pattern matching, CreateNewProc, SystemTagList, GetVar...), intuition V36 (public screens, tag-based Open*, EasyRequestArgs), graphics GetVPModeID, three new libraries (gadtools, keymap, utility), V37 hunk types in LoadSeg, `lib_Version` >= 37 everywhere | L+ (effectively a 2.0 ROM) | out of the 1.3 mission; 1.3 programs that test the version would take their 2.0 paths |
| C. Only the nine V36 dos functions JST 3.1/4.7 call (AllocDosObject, FreeDosObject, Flush, LockDosList, UnLockDosList, FindDosEntry, ReadArgs, FreeArgs, GetVar) | larger dos jump table, so a 1.3 ROM that is no longer 1.3 | M | not worth it: JST 4.7 still needs V37 hunks and version 37, and 3.1 is shareware-era beta Slave support |
| D. kickemu with KSS as image | — | — | impossible (see conclusion 2) |

## Side findings on KSS (implementation side, outside WHDLoad)

- **Missing "Software error - task held" requester**: on a user-task exception 1.3 shows it before the Guru; KSS goes
  straight to the Guru. Described in `docs/analysis/alert-v34.md`. Listed in `docs/REMAINING-WORK.md` A12.
- **Dev ROM stalls under JST 0.8c and Gamebench** (minutes instead of seconds), while the production ROM behaves
  like 1.3. PC samples were all in interrupt code (level 6 dispatch, the dev-only level-6 proof handler, the gameport
  VBlank server) with EXTER/PORTS pending: points at the dev test harness. Not investigated. Listed in A13.
- Boot CLI prompt `> ` where 1.3 prints `1> ` with the same reduced startup-sequence (cosmetic, not confirmed on our
  side yet). Listed in A14.

## Sources

- whdload.de: `docs/en/need.html` (Kickstart 2.0 V37, 68000, 1 MiB), `docs/en/opt.html`, `docs/en/howto.html`,
  `docs/History.html`.
- Aminet: `game/patch/jst.lha`, `game/patch/jst32b_dev.lha`, `game/patch/jst_hdinstalls.lha`,
  `util/misc/Gamebench.lha`.
- Analysis pages above (black-box runs on both ROMs plus static reading, behaviour only).
