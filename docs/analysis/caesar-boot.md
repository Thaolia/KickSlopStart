# caesar-boot.md — Caesar (Impressions) [cr FLT]: `caesar.boot` and `flt.exe`

> ANALYSIS track ("dirty"). Source: `assets/test_adf/Caesar (1992)(Impressions)[cr FLT].adf`,
> files extracted by a tolerant OFS reader (file header blocks 899 and 966). Disassembled
> with r2. `flt.exe` is packed: it was unpacked offline, in Python, by reproducing the
> unpacker. ROM functions concerned: graphics 34 (VBlank server, construction of copinit).
>
> **Legend**: **[O]** observed · **[D]** deduced · **[S]** assumed. Behaviour, registers and
> values only; no copied instruction sequence, no image data or text
> reproduced (apart from short strings).

---

## 1. `caesar.boot` (488 bytes, 1 CODE hunk of $C4, RELOC32, HUNK_SYMBOL) [O]

Small "gain CHIP memory" utility: it reduces the active screen to 1 plane.

1. exec **OpenLibrary("graphics.library", 0)** (−552). The result **is not tested**.
2. exec **OpenLibrary("intuition.library", 0)** (−552). The result is not tested and it is
   dereferenced immediately.
3. Read of **IntuitionBase+$38 = ActiveScreen** (public field). No NULL test.
4. On that screen, it reads `Screen.RastPort.BitMap` (Screen +$58, i.e. RastPort +$04).
5. If **BitMap.Depth (+$05) = 1**: nothing is done.
6. Otherwise:
   - **BitMap.Depth := 1**, written directly into the screen structure;
   - graphics **FreeRaster(BitMap.Planes[1] (+$0C), Screen.Width (+$0C), Screen.Height
     (+$0E))** (−498). The **2nd plane is returned to the allocator**, but **its pointer stays in
     Planes[1]**;
   - intuition **RemakeDisplay()** (−384).
7. CloseLibrary(intuition), CloseLibrary(graphics) (−414). Return D0 = 0.

- The string "dos.library" is present but unused.
- No direct hardware access, no allocation, no wait.

**Expected effect on a conforming ROM [D]**:
- The Workbench screen (that of the initial console) switches to **1 plane, 2 colours**.
- This switch relies on three points:
  - MakeVPort/MrgCop (via RemakeDisplay) derive the number of planes (BPU of BPLCON0) and the
    BPLxPT pointers from **`ViewPort.RasInfo->BitMap->Depth`**;
  - all rendering (console, layers, Text, RectFill, ScrollRaster…) only writes into
    `rp->BitMap->Depth` planes;
  - the ViewPort, the screen's RastPort and those of the windows (layers) share **the same**
    BitMap, `&Screen.BitMap`.

**How it can corrupt the display or the memory on our side [D]**:
- **(a)** Our display construction does not re-read `BitMap.Depth`: fixed number of planes, or
  internal copy of the depth made at OpenScreen. The DMA then keeps displaying plane 2,
  which is **freed memory** and quickly reused (LoadSeg of flt.exe, buffers…). One sees
  stray pixels in colours 2/3, which corresponds to the theme's "green".
- **(b)** Worse: our console, our layers or our primitives still write into 2 planes. They
  **then write into freed memory**: corruption of the allocator's free list or of
  what was loaded there (the code of flt.exe), hence a possible freeze.
- **(c)** Our `IntuitionBase+$38` is not the WB screen, or is NULL. The program then reads
  some arbitrary "BitMap" (low address), writes 1 there and frees an arbitrary pointer.

**Tests to do**:
- after caesar.boot: `ActiveScreen->BitMap.Depth = 1`;
- the effective BPLCON0 of the copper list has BPU = 1;
- no more writes into the old Planes[1] (memory probe);
- console still functional, in 2 colours.

## 2. `flt.exe` (1,552 bytes, 1 CODE hunk of $5EC, no relocation) [O]

### 2.1 Unpacking to a fixed address

- The hunk is an **unpacker** followed by the packed data: 1,316 packed bytes for
  2,046 unpacked.
- It **writes the result at the absolute address `$4A000`**: from `$4A000` to `$4A7FE`, **without
  AllocMem or AllocAbs**. It unpacks from the end towards the beginning.
- During unpacking, it writes control bytes into **COLOR00 ($DFF180)**, which
  produces a flickering of the background.
- It then jumps to `$4A000`, in **user mode, without any library call**.

### 2.2 The unpacked code: 100 % hardware, no system call

The code opens no library: neither graphics, nor intuition, nor dos. It does **no
OpenScreen, no View, no LoadView, no OpenFont**. It reads **no GfxBase field**. It
does not call Forbid/Disable/OwnBlitter.

Sequence:
1. **Clearing of `$53000`–`$63FFF`** by longs, at a fixed address, without allocation. That is
   68 KB of CHIP.
2. Saving of **DMACONR** OR $8000 into an internal word.
3. **INTENA := $4000**: clearing of the **INTEN** master bit, hence **no more interrupts at all**.
   No more VBlank, keyboard, timer, disk, serial. **The system is frozen**
   until exit.
4. **COP2LC ($DFF084) := $4A16A**: address of its copper list, inside the unpacked
   code. **There is no write to COPJMP2 nor write to COP1LC.**
5. **DMACON := DMACONR | $00F0 | $8000**: DSKEN, SPREN, BLTEN and COPEN set to 1, nothing
   cleared. BPLEN is not touched: it is assumed to be already active.
6. Display of the text (§2.4), wait for the button (§2.5), then exit (§2.6).

### 2.3 Home-made copper list (at `$4A16A`)

It contains only MOVEs, without WAIT, and ends with $FFFF,$FFFE:

| Register | Value |
|---|---|
| DMACON | $0020 (clears SPREN: sprites turned off) |
| DIWSTRT / DIWSTOP | $3081 / $30C1 (lines $30–$130: 256 PAL lines) |
| DDFSTRT / DDFSTOP | $0038 / $00D0 (hires, 80 bytes per line) |
| BPLCON1, BPL1MOD, BPLCON2, BPL2MOD | 0 |
| BPLCON0 | **$A400**: HIRES, **2 planes**, **DBLPF** (dual playfield), PF2PRI = 0 |
| COLOR00 | $000 |
| COLOR01 | variable (fade, §2.4), rewritten by the CPU in the list |
| BPL1PT / BPL2PT | **$53000 / $53000** (the same plane for both) |

In dual playfield, plane 1 forms playfield 1, whose colours are 0 and 1, and it is
in front. The text therefore appears in **COLOR01 on black COLOR00**. This is the "white on black"
observed on the real ROM.

### 2.4 Text and font

- **Embedded font** at the end of the code: 8 bytes per character, of which 7 lines are used, starting
  from character $20. There is **no OpenFont, no DefaultFont, no read of tf_CharData**.
- The glyphs are copied byte by byte into the `$53000` plane:
  - column = 2 + number of the character in the line;
  - text line n at raster line 8·n + 13 (stride of 80 bytes, 7 raster lines per glyph).
- Text format:
  - byte 0 = end of line;
  - **$FF = end of page**;
  - **$FE = end of text**.
- There is here **a single page** of 25 lines. Short visible strings: "F A I R L I G H T",
  "PRESENTS", "CAESAR FROM IMPRESSIONS".
- **Fade**: COLOR01 is increased by $111 per step, from $000 to $FFF. At each step, COP2LC is
  rewritten with the same value and the program does a **CPU wait loop** of $6000
  iterations (`dbra`): the duration depends on the CPU speed.

### 2.5 Wait

- **Left mouse button only**: **CIA-A PRA ($BFE001) bit 6**, active at 0.
- There is no POTINP test (right button), no keyboard read, no interrupt.
- During drawing, before each line: button pressed ⇒ **immediate exit**.
- After the fade-in: **busy wait as long as bit 6 is 1**. It does not wait for the
  button to be released.
- Then: fade-out (−$111 per step down to 0), new clearing of `$53000`–`$63FFF`,
  and COLOR01 of the list reset to $FFF.
- `$FE` ⇒ end (otherwise next page).

### 2.6 Exit and restoration

- **DMACON := saved value** (with SET): the sprites come back.
- **INTENA := $C000**: the INTEN master bit is set back to 1.
- Return to the CLI with the entry registers restored: D0 = length of the arguments, hence a very
  low return code.
- **Nothing else is restored**: neither COP1LC, nor COP2LC, nor LoadView, nor gb_copinit.

### 2.7 Why the FLT screen appears on the real ROM: dependency on the graphics 1.3 copper scheme [O ROM]

Everything relies on the copper organisation of graphics 34:
1. **copinit** (gb_copinit, loaded into COP1LC and restarted by the hardware at each frame)
   ends with:
   - a WAIT on line 12 ($0C01,$FFFE);
   - then a **MOVE COPJMP2** ($008A);
   - then the end of list.
   The copper **therefore jumps to the address contained in COP2LC** at each frame.
2. **COP2LC is never written by the copper.** It is the **graphics VBlank server**
   (VERTB interrupt) that writes it at each frame, via the CPU:
   - **gb_LOFlist** (GfxBase +$32);
   - or, in interlace, gb_LOFlist or gb_SHFlist (+$36) depending on the LOF bit of VPOSR.
3. FLT turns off INTEN: the VBlank server no longer runs and **its COP2LC stays in place**. The
   system copinit jumps to it at each frame and displays the FLT screen.
4. On exit, INTEN is re-enabled: from the next VBlank on, graphics rewrites gb_LOFlist into
   COP2LC. **The system display comes back on its own**, without any call.

**Consequence for our ROM [D]**: if our display does not use this scheme, FLT's write to
COP2LC has no effect. This is the case if, for example:
- the view's list is put directly into COP1LC;
- copinit has no COPJMP2;
- COP2LC is reloaded by the copper itself;
- or an interrupt not maskable by INTEN rewrites COP2LC.

We then keep our view on screen while the program has turned off interrupts and is waiting for
a left click. This corresponds to the symptom: **system "frozen", no echo**. In practice, a
left click should release it, after the fade of about 1 s.

To reproduce:
- COP1LC = copinit, with at the end MOVE COPJMP2 then $FFFF,$FFFE;
- COP2LC loaded by the CPU in the VBlank server (gb_LOFlist / gb_SHFlist);
- LoadView only updates gb_LOFlist / gb_SHFlist (+ gb_ActiView) and COP2LC.

## 3. Dependencies on fixed addresses and fields [O]

| Dependency | Program | Risk on our side |
|---|---|---|
| Code unpacked at **$4A000–$4A7FE**, without allocation | flt.exe | overwrites what our ROM put there (screen bitmap, copper list, stack, handler buffers) |
| Display plane cleared and written at **$53000–$63FFF**, without allocation | flt.exe | same, over 68 KB |
| CHIP ≥ $64000 (512 KB) | flt.exe | — |
| copinit → COPJMP2 → COP2LC loaded by the gfx VBlank | flt.exe | §2.7 |
| INTENA master turned off during the whole intro | flt.exe | the whole system is suspended |
| CIA-A PRA bit 6 (left button) | flt.exe | must reflect the button on direct read |
| `IntuitionBase+$38` (ActiveScreen), Screen +$0C/+$0E/+$58, BitMap +$05/+$0C | caesar.boot | §1, public fields |
| BitMap.Depth actually re-read by MakeVPort and by all rendering | caesar.boot | §1 (a)/(b) |
| No private field of GfxBase or IntuitionBase, no call to a ROM address | both | — |

**On the real 1.3 [D]**: at the time flt.exe runs, the exec allocator serves CHIP from the
bottom. The WB and console bitmaps and lists are rather below $4A000, and the area
$4A000–$64000 is free in practice. **A ROM whose boot allocations go higher, or
which places fixed structures in this area, will see corruption.** This is a direct candidate
for the "stray pixels in the console". Plane 2 freed by caesar.boot (§1) is
another.

**Recommended diagnosis**:
1. Record the location of our screen bitmaps, our copper lists and the segments loaded
   after the startup-sequence, and compare it with $4A000–$64000.
2. Check BitMap.Depth = 1 after caesar.boot (§1).
3. Check the COPJMP2 / VBlank scheme (§2.7).
4. During the "freeze", a left click must give control back: the program exits and the echoes
   arrive.

---

## Clean-room review

- [x] No copied instruction sequence: library calls with LVO, hardware registers
  and values, fixed addresses, wait and exit conditions.
- [x] The unpacker is only named, its algorithm is not described step by step. No
  font data or text reproduced, apart from three short strings.
- [x] The copper list is described as a register → value table (public hardware
  data).
- [x] **Correction of 2026-10-29**: removed the 4 addresses of ROM graphics routines
  (VBlank server, construction of copinit); behaviour unchanged.
