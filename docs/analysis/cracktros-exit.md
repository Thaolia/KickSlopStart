# cracktros-exit.md — exit of the NOMAD/QUARTEX (Scooby-Doo), defjam (Monkey Island), RAZOR (SimCity) intros

> ANALYSIS track ("dirty"). Files extracted from the ADFs by a tolerant OFS reader. The four
> executables are **a single CODE hunk without relocation, packed** (home-made unpacker at the head).
> They were unpacked **by 68000 emulation** (Unicorn, analysis-track scratch: flat
> RAM, custom/CIA registers simulated and logged, dummy ExecBase that logs the LVOs
> called), then disassembled. ROM functions concerned: graphics 34 (VBlank server,
> installation of the interrupts).
>
> **Legend**: **[O]** observed · **[D]** deduced · **[S]** assumed. Behaviour, registers and
> values; no copied instruction sequence, no image or music data.
> "Absolute" = fixed address written **without** AllocMem/AllocAbs.

---

## 0. Common points [O]

- None of the four allocates the memory it uses. Each one **unpacks itself to an absolute
  address** in CHIP (table §5).
- The click is always read **by polling CIA-A PRA ($BFE001) bit 6** (active at 0). None
  goes through an interrupt, gameport.device or input.device.
- The only other button read is the right button (POTINP $DFF016 bit 10), by RAZOR, and only
  in its dos.library open-failure path.
- They take control in **supervisor** mode in two ways:
  - `trap #0` after having written vector $80 (NOMAD, defjam);
  - or a MOVE to SR that triggers a privilege violation, whose vector $20 has been
    redirected to the next instruction (QUARTEX).

---

## 1. Scooby-Doo [cr QTX]: `NOMAD` (5,872 b) then `QUARTEX` (58,740 b)

### 1.1 NOMAD = the displayed intro (click → return to the CLI)

**Startup**:
- unpacking to **$50000–$5E150**;
- writing of vector **$80** (trap #0) = $50038, then `trap #0`.

**In supervisor mode**:
- saving of SR, **DMACONR** and **INTENAR**;
- SR := $2700;
- **DMACON := $7FFF** (everything off), **INTENA := $7FFF** (everything off, INTEN included);
- COLOR31 := 0; INTREQ := $0020 (acknowledges VERTB);
- **COP2LC := $50D80** (its list);
- init of the tables, clearing of a keyboard port (CIA-A SDR := 0);
- **COPJMP2 strobe** ($DFF08A): it starts its list itself and does not depend on copinit;
- **DMACON := $87C0** (DMAEN, BPLEN, COPEN, BLTEN, BLTPRI; sprites, disk and audio off);
- PRA bit 1 set to 1 (LED / filter).

**Per-frame loop**, all interrupts masked:
1. **busy wait on INTREQR bit 5 (VERTB)**, raised by the hardware even with INTENA at 0;
2. the frame's work, then INTREQ := $0020;
3. keyboard read: if INTREQR bit 3 (PORTS) is 1, read of CIA-A SDR, handshake via CRA
   bit 6 with a CPU wait, decoding of the code. **Neither ICR nor INTREQ is acknowledged**;
4. **exit if code = $40 (space bar) or if PRA bit 6 = 0 (left button)**.

**Exit**:
- PRA bit 1 reset to 0;
- DMACON := $7FFF, INTENA := $7FFF;
- DIWSTRT/DIWSTOP := $2C81/$2CC1, DDFSTRT/DDFSTOP := $0038/$00D0, BPL1MOD = BPL2MOD := 0;
- **copy of a loader routine (≈1 KB) to the absolute $7F000**;
- **COPJMP1 strobe** ($DFF088), **without writing COP1LC**: restart of the already loaded system
  copinit;
- **DMACON := saved DMACONR \| $8000**, **INTENA := saved INTENAR \| $8000**;
- SR restored, RTE, return D0 = 0.

**No system call**: no Forbid, no LoadView, no read of GfxBase. After the exit, the
restarted copinit jumps (COPJMP2) to **COP2LC, which still points to $50D80**. It is the first
VBlank, once INTEN is re-enabled, that puts gb_LOFlist back into COP2LC (cf. `caesar-boot.md` §2.7).

### 1.2 QUARTEX = game loader (total takeover, no return)

**Takeover**:
- DMACON, INTENA and ADKCON := $7FFF;
- CIA-B PRB := $87;
- vector $20 := continuation, then SR := $2700;
- **SP := $7FFFE**;
- copy of an unpacker to **$7E000**;
- unpacking into **$2000–$5C00, $3FC00–$50800, $64000–$6C000, $7FC00–$80000**. It
  **overwrites the user vectors from $100 on**. The area $400–$1000 could not be
  observed: the emulator places its dummy ExecBase there. The OS is abandoned afterwards [D].

**At $40000**:
- SR := $2700; INTENA and DMACON := $7FFF; PRA bit 1 := 1;
- **COP1LC := $40664** (home-made list: DIW $4081/$08C1, DDF $38/$D0, BPLCON0 $4200…),
  read of COPJMP1 ($DFF088), which serves as the strobe;
- wait for VPOS < $40;
- DMACON := $7FFF then $87FF;
- **jump to the game ($49D0E)**. The game rewrites vectors $80/$84/$24 (trap #0, trace) and
  drives the drive itself (CIA-B PRB, track loader).

**Consequences**:
- the Scooby title screen is displayed by this code, without any dependency on the ROM;
- the only dependencies are hardware ones, plus the fact that **QUARTEX's hunk itself must
  not be located in the areas it overwrites** (§5).

### 1.3 Leads for "the click is ignored, the intro stays displayed" [D]

1. **NOMAD may well have exited.** Only one thing brings back the system display: the graphics
   VBlank that rewrites COP2LC. If our VBlank only refreshes COP2LC after a LoadView, the
   copinit keeps jumping into NOMAD's list ($50D80), and the intro's image stays frozen
   while the CLI launches QUARTEX. **To check: the VBlank server writes gb_LOFlist into
   COP2LC at every frame.**
2. **QUARTEX destroys itself.** It copies and unpacks to $2000–$80000. If our LoadSeg
   places its 58 KB hunk in low CHIP (between $40000 and $80000), the unpacker overwrites its
   own source and everything hangs.
   - On the real 1.3 [S], AllocMem(MEMF_PUBLIC) first serves the $C00000 RAM, of higher priority
     than CHIP: hunks without a memory flag end up outside CHIP.
   - **To check: the address of QUARTEX's (and NOMAD's) segment given by our LoadSeg.**
3. NOMAD's button test only takes place **once per frame**, after the wait for VERTB in
   INTREQR. If the image is **frozen** (no scrolling), the program is stuck elsewhere.

---

## 2. Monkey Island [cr Defjam]: `defjam` (5,080 b)

**Startup**:
- unpacking to **$50000–$53000**;
- vector **$80** := $501FE, then `trap #0`.

**Init**:
- CIA-B PRB := $87 (motors off);
- exec **Forbid** (−132);
- **saving of vector $6C** (level 3 autovector), of **INTENAR \| $C000** and of
  **DMACONR \| $8100**;
- clearing of **absolute $64FFC–$72000**;
- construction of its copper list in its code ($51152; planes at $65028, $672B0, $6E380;
  sprites at $64FFC; double buffer $65000/$699C0).

**Taking the display**:
- INTENA := $3FFF then **$C018**: INTEN + **COPER** + **PORTS**. VERTB, BLIT and the disk
  are off; **PORTS remains served by the OS** (vector $68 unchanged);
- DMACON := $3FFF then $83E0 (DMAEN, BPL, COP, BLT, SPR);
- BPLCON2 := $0040; DIW $2984/$29D0; DDF $0038/$00D0;
- **COP1LC := $51152** + COPJMP1 strobe;
- sprite colours;
- **vector $6C := $5056E**. Its handler only does something if INTREQR bit 4 (COPER)
  is 1, then acknowledges COPER. **The copper list contains no MOVE to INTREQ**: this
  handler therefore never does any work [O].

**Main loop**, in supervisor mode and under Forbid:
1. busy wait for **VHPOSR high byte = 0**, i.e. line 0 or 256;
2. animation (blitter, with BBUSY wait on DMACONR bit 14);
3. **PRA bit 6 = 0 ⇒ exit**, otherwise loop again.

The click is therefore only seen **once per frame**, and only if the loop is running.

**Exit**:
1. wait for the end of the blitter;
2. **vector $6C restored**;
3. **INTENA := saved value** (with SET). The COPER and PORTS bits set by the intro **are not
   cleared**;
4. **DMACON := $7FFF**;
5. **COP1LC := GfxBase->copinit**, where GfxBase is obtained in a roundabout way:
   **`ExecBase->IntVects[INTB_BLIT].iv_Data`** (ExecBase +$9C), then **+$26 (gb_copinit)**;
6. COPJMP1 strobe;
7. DMACON := saved value \| $8100;
8. exec **Permit** (−138), RTE, return D0 = 0.

**Private dependency [O ROM]**: on the real ROM, graphics installs its blitter server by
**SetIntVector(INTB_BLIT = 6, &GfxBase+$76)** (−162), with is_Data = GfxBase. This is how
`IntVects[6].iv_Data` equals GfxBase. In the same init block, graphics adds its VBlank server
by AddIntServer(5, &GfxBase+$4A) (−168).

**Leads [D]**:
- "The intro keeps animating, click ignored": it is the main loop that animates (the
  $6C handler does nothing). So it is running, and the only test is PRA bit 6 once per frame.
  To check by probe:
  - the value read from $BFE001 during the click;
  - CIA-A **DDRA**: bit 6 must be an input. On the real ROM DDRA = $03 [S];
  - that no PORTS server of our ROM (still active here) modifies DDRA or PRA.
- **After** the exit: if our `IntVects[6].iv_Data` is not GfxBase (no SetIntVector
  BLIT, or different is_Data), COP1LC receives an arbitrary pointer, which gives a garbage
  screen. It is the same mechanism as SimCity (§3): **it must be reproduced.**

---

## 3. SimCity [cr RZR]: `S/RAZOR.EXE` (22,196 b)

**Startup**:
- INTENA := $4000 (INTEN off), DMACON := $0200 (DMAEN off);
- CIA-B PRB := $FD/$87/$FD; CIA-B CRA bit 1 set to 1;
- **copy of an unpacker into the absolute $100–$316** (user vectors, cf. §5);
- unpacking to **$59C00–$6E800** (code at $60000, music player at $5A000);
- DMACON := $8200, INTENA := $C000.

**Init** (still within the OS):
- exec **OldOpenLibrary("dos.library")** (−408);
- if the open fails: loop COLOR00 := VHPOSR until the **right button** (POTINP bit 10);
- dos **Open("SECTOR9.TXT", MODE_OLDFILE)** (−30) in the current directory (`cd s`);
- **Read(fh, buffer at an odd address, $FFFFFF)** (−42): requested length of 16 MB;
  the file is 1,284 b;
- Close (−36);
- CIA-B PRB := $FB then $F5 (DF0 selection, motor off);
- music init; planes at $70000 and beyond.

**Taking the display**:
- BLTCON1 := 0;
- DMACON, INTENA and INTREQ := $7FFF;
- **DMACON := $83E0**, **INTENA := $C010** (COPER only);
- **vector $6C saved then := $600CE**. The handler, triggered by COPER from its copper
  list, animates, plays the music and acknowledges COPER;
- **COP1LC := $632E4** + COPJMP1 strobe.

**Wait**: **tight loop on PRA bit 6** (left click), without frame or interrupt.

**Exit**:
1. wait for the end of the blitter;
2. **vector $6C restored**;
3. **INTENA := $E03C**, a **hard-coded** value (INTEN, EXTER, VERTB, COPER, PORTS, SOFTINT):
   **BLIT, DSKBLK, TBE, RBF, audio remain off**;
4. **DMACON := $83F0 then $8020** (hard-coded);
5. **COP1LC := `(*(*(*(ExecBase))))`+$26**, that is:
   - ExecBase→LibNode.ln_Succ (the library that follows exec in LibList);
   - →ln_Succ (the next one);
   - read as a GfxBase: +$26 = gb_copinit.

   **No COPJMP1**: the new list is taken at the next frame;
6. stop of the music, return D0 = 0 (no Forbid/Permit nor RTE: it stayed in
   user mode).

**Dependency on the LibList order [O hack, D for the ROM]**:
- This hack assumes that the **3rd library** of the chain starting from ExecBase is
  **graphics.library**.
- On the real 1.3, the ROM libraries are added in resident order:
  exec, then **expansion.library (pri 110)**, then **graphics.library (pri 65)**, then layers,
  intuition…
- Whether LibList is sorted by priority or FIFO, one gets exec → expansion → graphics.
- **On our side, if the order differs, COP1LC receives +$26 of another library.** The possible
  cases:
  - exec is not at the head;
  - no expansion.library before graphics;
  - another library is inserted between the two;
  - different node priorities.

  The copper then executes arbitrary memory: this is **exactly the "screen full of
  red patterns"**.
- **To reproduce**: LibList = exec, expansion, graphics, … in that order, at least at the time
  the startup-sequence runs.

**Other consequence [D]**: the hard-coded INTENA leaves **TBE/RBF, DSKBLK and BLIT off**. If
our ROM waits for one of these interrupts (serial output, end of disk DMA, blitter), it
hangs after RAZOR. On the real ROM, trackdisk, serial and graphics re-enable them on demand.
- To check: SetPatch and LoadWB behind it do not depend on an INTENA bit set once and for
  all at boot.

---

## 4. Table of restorations

| | NOMAD | QUARTEX | defjam | RAZOR |
|---|---|---|---|---|
| Supervisor | trap #0 (vector $80) | privilege violation (vector $20) | trap #0 | no |
| Forbid/Permit | no | no | **yes** (−132/−138) | no |
| INTENA during the intro | $0000 (everything off) | $0000 | $C018 (COPER+PORTS) | $C010 (COPER) |
| Interrupt used | none (polling INTREQR VERTB) | — | $6C installed but never triggered | **$6C + COPER from the copper list** |
| Click detection | PRA bit 6 (+ space), 1×/frame | (game) | PRA bit 6, 1×/frame (VPOS = 0) | PRA bit 6, tight loop |
| INTENA on exit | saved \| $8000 | — | saved \| $8000 (COPER/PORTS remain) | **$E03C hard-coded** |
| DMACON on exit | saved \| $8000 | — | $7FFF then saved \| $8100 | **$83F0 + $8020 hard-coded** |
| Copper on exit | COPJMP1 only (COP1LC unchanged); COP2LC stays its own until the VBlank | — | **COP1LC := IntVects[6].iv_Data + $26** + COPJMP1 | **COP1LC := 3rd lib of LibList + $26**, without strobe |
| Vectors restored | $80 not restored | — | $6C yes, $80 no | $6C yes |

---

## 5. Absolute areas written (without allocation) [O, emulation]

| Program | Areas |
|---|---|
| NOMAD | $50000–$56400 (unpacked code, copper list $50D80), planes at $37000 and beyond (copper list), **$7F000–$7F800** (routine copied on exit, left in place) |
| QUARTEX | **$100–$3FF (user vectors)**, $2000–$5C00, $3FC00–$50800, $64000–$6C000, $7E000–$7E400, $7FC00–$80000; SP = $7FFFE |
| defjam | $50000–$53000, **$64FFC–$72000** (cleared: planes, sprites) |
| RAZOR | **$100–$316** (unpacker), $59C00–$5E800, $60000–$60800, $62C00–$65000, $68000–$6E800, planes at $70000 and beyond |

- The user vectors $100–$3FF are not used by the real 1.3. **If our ROM stores
  something there** (ExecBase, tables, stack), RAZOR destroys it as soon as it is launched.
- Likewise, the areas $50000–$72000 must be free. Neither the screen bitmaps, nor the copper
  lists, nor the **segments of the intros themselves** may be located there.

## 6. Private or misused fields

- **defjam**: `ExecBase+$9C` = IntVects[6].iv_Data, assumed to be GfxBase, then `+$26` =
  gb_copinit. Also reads ExecBase+4 for Forbid/Permit (normal).
- **RAZOR**: `ExecBase->ln_Succ->ln_Succ`, assumed to be GfxBase, then `+$26`.
- **NOMAD, QUARTEX**: no system field. They rely on the COP1LC/COP2LC registers
  left by the OS: copinit in COP1LC, and the VBlank that rewrites COP2LC (NOMAD).

---

## Clean-room review

- [x] No copied instruction sequence: public calls with LVO, registers and values,
  vectors touched, wait and exit conditions, fields read, memory areas.
- [x] The unpackers are not described; no graphics or music data, no intro
  text reproduced (only file names).
- [x] **Correction of 2026-10-29**: removed the 3 addresses of ROM graphics routines
  (header); behaviour unchanged.
