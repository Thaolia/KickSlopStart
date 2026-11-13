---
description: Clean-room rules for analysis specs — what a docs/analysis page may and may not contain
globs: ["docs/analysis/**/*.md", "docs/audit/**/*.md", "docs/WHDLoad/**/*.md"]
---

# Analysis specs — clean-room rules

> Scoped to `docs/analysis/`, `docs/audit/` and `docs/WHDLoad/`. The firewall itself (who may read the ROM) is in
> `CLAUDE.md`, "Core Principles"; the method is in `docs/CLEANROOM.md` and `docs/AUDIT.md`.
> WHDLoad, JST and their Slaves sit behind the same wall as the ROM (user decision, 2026-11-13): only an analysis
> agent downloads, runs or disassembles them, and its pages about them go to `docs/WHDLoad/` under the rules below
> (no address or offset inside those binaries either).

## Writing a spec (analysis agent only)

- Describe behaviour and ABI: entry/exit registers, structure layouts and field offsets, ordering of observable
  effects, return values, error cases, test vectors.
- Never write an instruction listing, a pseudo-code transcription of a routine, or a ROM address/offset.
- Describe ROM data (images, fonts, tables) in words and dimensions; never reproduce it.
- Write in English. State how each fact was observed (black-box probe, AutoDocs, third-party program behaviour).
- Mark uncertain points as such instead of guessing; an implementation will rely on every sentence.

## Consuming a spec (implementation side)

- Before using a new or changed page, check it for transcribed code and ROM addresses; reject it if it has any.
- Do not draw or author data right after reading its description in a spec: choose a design of a different nature.
- A spec contradicted by a real program is reported back to the analysis track; never patch it from this side.

## Audit records (`docs/audit/`)

- Statistics, thresholds, offsets inside **our** ROM and symbols from our map only; never ROM content.
- Record the exact commands, both baselines and the verdict, in English.
