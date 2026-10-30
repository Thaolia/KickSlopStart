# Memory usage compared with Kickstart 1.3

With the English Workbench 1.3.3 booted and idle, KickSlopStart leaves about 60 KB less free memory than the
original Kickstart 1.3. This page explains where that memory goes. The two largest items below are deliberate
design choices, not leaks.

## How this was measured

- Diagnostic ROM:
  `make BUILD=build/mtp VASMDEF="-DMEMTRACK=1 -DPROD=1" KICK_ROM=build/kick13-mtp.rom kick`.
- `MEMTRACK` (in `src/exec/memory.s`) records every live allocation in a table of 12-byte entries: address,
  size, and the return address of the `AllocMem` caller.
- The table is dumped with the FS-UAE debugger after the Workbench has been idle for 130 s. Each caller is
  resolved against the linker map (`vlink -M`).
- Result: 198,760 bytes live, after removing the waste described in "Fixed" below.

| Caller                         | Bytes  | What it is                                                       |
|--------------------------------|--------|------------------------------------------------------------------|
| `trackdisk_beginio`            | 45,056 | Track cache (1 below)                                            |
| `ls_load_stream`               | 42,216 | Loaded program hunks (Workbench, handlers, resident commands)     |
| `intuition_end`                | 41,400 | Screen bitmaps and intuition structures                          |
| `exec_AllocEntry`              | 21,376 | Task stacks and TCBs of processes                                |
| `wb_entry`                     |  9,232 | Workbench objects and icons                                      |
| `exec_MakeLibrary`             |  5,280 | Library and device bases                                         |
| `it_startinput`                |  4,192 | Intuition input task (3 below)                                   |

## 1. trackdisk track cache — 45,056 bytes (kept on purpose)

`trackdisk.device` keeps the last `TD_NCACHE` = 8 decoded tracks in an LRU cache (`TD_CACHEBUF`, 8 × 5,632
bytes). See `src/exec/trackdisk.s` and `TD_NCACHE` in `src/exec/exec.i`.

**Why it exists.** The OFS file system reads 512-byte blocks and keeps switching between the directory track and
the data tracks. Without a cache, every block costs a full track read: motor spin-up, seek, a DMA of the whole
track and MFM decoding of its 11 sectors. When the Workbench boot was measured with a single cached track, it
did 222 track reads for 58 distinct tracks. With the cache, a track already decoded is served straight from
memory.

**How it behaves.**
- It is allocated at the first `CMD_READ`, not at boot.
- If 45 KB is not available, it falls back to a single slot of 5,632 bytes.
- A track enters the cache only if all 11 sectors decoded and carry the requested track number.
- A disk change (`/CHNG`) or `CMD_CLEAR` empties the cache.
- Writes (`CMD_WRITE`) update cached tracks and mark them dirty. Only `CMD_UPDATE` writes them back;
  turning the motor off keeps them in the cache.

**Size choice.** 8 slots is the knee of the curve. Going to 16 slots only took the measured Workbench boot from
87 s to 83 s, for another 45 KB.

**Trade-off.** The original 1.3 trackdisk keeps one track buffer per unit and relies on the file system's own
buffers instead. Lowering `TD_NCACHE` gives memory back at the cost of disk speed. The cache is not freed while
the device is open.

## 2. Fixed: console bitmap left by the boot self-test — 10,240 bytes of chip RAM

The console self-test #3a in `src/exec/boot.s` ran in production ROMs too. It writes to a console unit that has
no window, and that makes `con_putglyph` allocate a 640×128 one-plane bitmap in chip RAM. The test closed the
unit but never freed the bitmap.

The test now frees `CONB_BITMAP` (`CON_BMSIZE` bytes) and resets the cursor when it finishes. After the fix,
`MEMTRACK` shows no live `con_putglyph` block once the Workbench is idle.

## 3. Intuition input task — 4,192 bytes (architecture choice)

`it_startinput` (`src/intuition/screens.s`) creates a dedicated task at priority 20, like input.device's, with a
4,096-byte stack plus its TCB. It handles mouse buttons, gadgets, menus, window dragging and sizing.

**Why a task.** These actions draw and take layer locks, so they can block. They cannot run in the VBlank
interrupt or inside the input handler chain. A task of its own gives them a context that is allowed to wait.

**Trade-off.** In the original 1.3, this work runs inside input.device's own task, so it costs no extra stack.
Folding it into our input.device task would save these 4 KB, but every input handler would then share that task
and could be blocked by intuition's drawing.

## What else differs

The rest of the gap is not broken down further. The other callers in the table are expected allocations,
and none of them has been identified as a leak. To check for a regression, rerun the measurement above and
compare the table caller by caller.
