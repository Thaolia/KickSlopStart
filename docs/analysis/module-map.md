# module-map.md — Map of the 24 ROMTags (Kickstart 1.3 / V34.5, `kick34005.A500`)

> ANALYSIS track ("dirty"). Facts derived SOLELY from reading the ROM with radare2
> (256 KB, 68000 big-endian, base $FC0000). No instruction listing is reproduced, nor
> any address of a routine or structure in the ROM: only flags, types, priorities, sizes,
> counts and ABI constants appear here.
>
> Provenance: all columns are **measured in the ROM** except the nominal decomposition
> of flags/types (public ABI constants, `exec/resident.i`, `exec/nodes.i`).

## ROM header (longwords at the start of the image)

| Offset | Measured value | Meaning |
|-------:|----------------|------|
| +0x00 | `0x11114EF9` | Initial SSP as seen at reset = ROM-ID word `0x1111` + opcode `0x4EF9` (JMP abs.l) — 256 KB Kickstart header format, verified by the tools (`romtool`) |
| +0x04 | ROM address | Reset PC → entry point of the exec coldstart (= exec's `rt_Init`, see below) |
| +0x08 | `0x0000FFFF` | — |
| +0x0C | `0x00220005` | **ROM version = 34.5** (major `0x22`=34, minor `0x0005`=5) → Kickstart 1.3 |
| +0x10 | `0x00220002` | Secondary marker 34.2 (coincides with exec's own revision) |
| +0x14 | `0xFFFFFFFF` | — |
| +0x18 | ASCII | exec's `rt_IdString` ("exec 34.2" + date + CR/LF) |
| +0x38 | ASCII | Commodore-Amiga copyright banner (text not reproduced) |

ROM footer (last 24 bytes of the image): size field `0x00040000` (256 KB) + one image checksum
longword. Not analysed further (outside spec scope).

## Decoding constants (public ABI)

- `rt_Flags`: `RTF_AUTOINIT=0x80` · `RTF_AFTERDOS=0x04` · `RTF_SINGLETASK=0x02` · `RTF_COLDSTART=0x01`.
- `rt_Type` (`exec/nodes.i`): `NT_UNKNOWN=0` · `NT_TASK=1` · `NT_DEVICE=3` · `NT_RESOURCE=8` · `NT_LIBRARY=9`.
- `rt_Version` is a **UBYTE** = **major** number only (34). The revision (`.1`/`.2`/`.3`/`.4`)
  exists only in `rt_IdString`; it is NOT stored in the Resident struct in V34.

## Table of the 24 ROMTags (decreasing priority order = init order, see sorting rule below)

All: `rt_MatchWord=0x4AFC`, `rt_MatchTag`→itself, `rt_Version=34`.

| # | Module | `rt_Flags` | Decoded flags | `rt_Type` | Pri | Revision (`rt_IdString`) |
|--:|--------|:----------:|---------------|:---------:|----:|--------------------------|
| 1 | exec.library | `0x00` | *(none)* | `9` LIBRARY | 120 | 34.2 |
| 2 | expansion.library | `0x81` | AUTOINIT+COLDSTART | `9` LIBRARY | 110 | 34.1 |
| 3 | potgo.resource | `0x01` | COLDSTART | `8` RESOURCE | 100 | 34.1 |
| 4 | keymap.resource | `0x01` | COLDSTART | `8` RESOURCE | 100 | 34.1 |
| 5 | cia.resource | `0x01` | COLDSTART | `8` RESOURCE | 80 | 34.1 |
| 6 | disk.resource | `0x01` | COLDSTART | `8` RESOURCE | 70 | 34.1 |
| 7 | misc.resource | `0x01` | COLDSTART | `8` RESOURCE | 70 | 34.1 |
| 8 | ramlib.library | `0x80` | AUTOINIT *(not COLDSTART)* | `9` LIBRARY | 70 | 34.1 |
| 9 | graphics.library | `0x01` | COLDSTART | `9` LIBRARY | 65 | 34.1 |
| 10 | keyboard.device | `0x01` | COLDSTART | `3` DEVICE | 60 | 34.1 |
| 11 | gameport.device | `0x01` | COLDSTART | `3` DEVICE | 60 | 34.1 |
| 12 | timer.device | `0x01` | COLDSTART | `3` DEVICE | 50 | 34.1 |
| 13 | audio.device | `0x81` | AUTOINIT+COLDSTART | `3` DEVICE | 40 | 34.1 |
| 14 | input.device | `0x01` | COLDSTART | `3` DEVICE | 40 | 34.1 |
| 15 | layers.library | `0x01` | COLDSTART | `9` LIBRARY | 31 | 34.1 |
| 16 | console.device | `0x01` | COLDSTART | `3` DEVICE | 20 | 34.1 |
| 17 | trackdisk.device | `0x01` | COLDSTART | `3` DEVICE | 20 | 34.1 |
| 18 | intuition.library | `0x81` | AUTOINIT+COLDSTART | `9` LIBRARY | 10 | 34.3 |
| 19 | alert.hook | `0x01` | COLDSTART | `0` UNKNOWN | 5 | *(name only, `rt_IdString` = `rt_Name`)* |
| 20 | mathffp.library | `0x81` | AUTOINIT+COLDSTART | `9` LIBRARY | 0 | 34.1 |
| 21 | workbench.task | `0x00` | *(none)* | `1` TASK | 0 | wb 34.1 |
| 22 | dos.library | `0x00` | *(none)* | `9` LIBRARY | 0 | 34.3 |
| 23 | romboot.library | `0x01` | COLDSTART | `9` LIBRARY | -40 | 34.1 |
| 24 | strap | `0x01` | COLDSTART | `0` UNKNOWN | -60 | 34.4 |

### Notable facts (measured)

- **exec**: `rt_Flags=0` (neither AUTOINIT nor COLDSTART), and its `rt_Init` **is** the reset PC of
  the header. exec is therefore NOT initialised by the resident scan: the reset vector jumps
  directly into its `rt_Init`, which IS the kernel's coldstart routine. Its `rt_EndSkip` designates
  the next ROMTag (`alert.hook`): the scan resumes right after exec's range.
- **Timing bits present in this ROM**: only `RTF_COLDSTART` (0x01) among the three
  "when to start" bits. **No** module has `RTF_SINGLETASK` (0x02) or `RTF_AFTERDOS` (0x04).
- **Without any timing bit**: exec (0x00), **ramlib** (0x80 = AUTOINIT only), workbench.task
  (0x00), dos (0x00). These four are not started by the generic `InitCode(RTF_COLDSTART)`
  pass; they are handled by dedicated paths (exec = the kernel itself; ramlib,
  dos and workbench.task by the DOS/strap bootstrap). See `boot-sequence.md`.
- **"UNKNOWN" types (0)**: `alert.hook` (pri 5) and `strap` (pri -60) are neither library nor
  device nor resource — they are boot hooks invoked via `rt_Init`.
- **alert.hook**: `rt_Name` and `rt_IdString` designate the same string ("alert.hook"); its
  `rt_Init` is located before the tag itself (no ABI constraint: `rt_Init` is a free pointer).
- **dos**: `rt_Init == rt_EndSkip` (same pointer value).
- Revisions per module (from `rt_IdString`): exec **34.2**, intuition **34.3**, dos **34.3**,
  strap **34.4**; all others **34.1**. The ROM as a whole identifies itself as **34.5 / Release 1.3**.

### Sorting rule of the resident list (= initialisation order)

Sort key: **`rt_Pri` decreasing, then position in the ROM increasing** (the ROM scan
builds the list in increasing address order, the sort by priority is stable). Confirmed by
the measured priority ties (order observed at equal priority):
- pri 100: potgo before keymap
- pri 70: disk before misc before ramlib
- pri 60: keyboard before gameport
- pri 40: audio before input
- pri 20: console before trackdisk
- pri 0: mathffp before workbench.task before dos

The order of the table above is therefore the exact order the reimplementation must reproduce (a
reimplementation can place its own tags in this address order to obtain the same
tie-breaks).

## Auto-init structures (RTF_AUTOINIT modules)

For the 5 modules with `rt_Flags & RTF_AUTOINIT`, `rt_Init` points to a table of 4 longwords
(`exec/resident.i`, so-called "auto-init" structure consumed by `InitResident`→`MakeLibrary`):

```
+0  LONG  dataSize     size (bytes) of the library/device base to allocate
+4  APTR  vectors      pointer to the function vector table (jump table)
+8  APTR  structure    pointer to InitStruct data (init of the base fields), or NULL
+12 APTR  initFunction pointer to routine run after allocation/init, or NULL
```

Format of the `vectors` table (`MakeFunctions` convention): if the **first word = `0xFFFF`**,
the entries are **signed WORD displacements** (16 bits) relative to the address of `vectors`,
terminated by `0xFFFF`; otherwise they are **absolute LONG addresses** (32 bits) terminated by
`0xFFFFFFFF`. The number of entries = number of LVOs exposed by the module.

| Module | `dataSize` | `vectors` encoding | **No. of vectors (LVO)** | `structure` | `initFunction` |
|--------|-----------:|----------|:---------------------:|-------------|----------------|
| expansion.library | `0x1C8` = 456 | absolute LONG | **25** | present | present |
| ramlib.library | `0x0B2` = 178 | relative WORD | **11** | present | present |
| audio.device | `0x27A` = 634 | relative WORD | **6** | present | present |
| intuition.library | `0x564` = 1380 | absolute LONG | **78** | **NULL** | present |
| mathffp.library | `0x022` = 34 | relative WORD *(signed offsets, some negative)* | **16** | present | present |

Measured remarks:
- The vector counts are **exact** (counted up to the terminator in the ROM).
- **intuition**: `structure = NULL` → no InitStruct table; the base fields are set
  by `initFunction` alone. It is the only one of the five in this case.
- **mathffp**: `dataSize = 0x22 = sizeof(struct Library)` (34) → no instance data beyond
  the library node; its vector table uses **signed** WORD offsets (functions
  may precede the table — the format allows it).
- expansion/intuition use the **absolute LONG** format; ramlib/audio/mathffp the
  **relative WORD** format. Both formats coexist in the same ROM.
- The other modules (graphics, dos, layers, keymap/potgo/cia/disk/misc resources, keyboard/
  gameport/timer/input/console/trackdisk devices, romboot) have `rt_Flags` **without** AUTOINIT:
  their `rt_Init` points to manual init code (no standard auto-init table), so their
  number of LVOs is not measurable without tracing their `MakeLibrary` — not reproduced here.

## Clean-room review

Review of 2026-10-29.

- [x] No 68000 instruction sequence transcribed or paraphrased, no disassembly excerpt.
- [x] **Fixed**: the initial version gave, for each of the 24 ROMTags, the file offset and
  the address in the ROM of the tag, of `rt_Name`, `rt_IdString`, `rt_Init` and `rt_EndSkip`, as well as
  the addresses of the auto-init tables (`vectors`, `structure`, `initFunction`), the value of the reset PC,
  the bounds of exec's range and the addresses used to illustrate the tie-break rule. All these
  ROM routine/data addresses have been removed; the behavioural information is kept
  (flags, type, priority, revision, presence/absence of fields, LVO counts, tie-break order at
  equal priority expressed as relative order).
- [x] **Fixed**: removed the full text of the copyright banner, the value of the image checksum
  and the example negative offset of the mathffp table (ROM data with no ABI use).
- [x] Remaining: header `0x1111`/`0x4EF9`, version 34.5, size 256 KB (Kickstart image format
  verified by `romtool`), public constants `exec/resident.i` / `exec/nodes.i`, base sizes.
