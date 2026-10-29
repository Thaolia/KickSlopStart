# monkey-startup.md — `monkey_island` (Monkey Island FR [cr Defjam]): startup up to "Appuyez sur ENTER"

> ANALYSIS track ("dirty"). Source: disk 1/4, root file `monkey_island` (108,408 bytes, header
> block 881), extracted by the tolerant OFS reader and relocated flat at $100000.
>
> The executable **is not packed**. It is a C program (Lattice, data addressed through A4 =
> start of hunk 4) with 5 hunks:
> - #0: stub added by the crack;
> - #1: stub;
> - #2: CODE of 98,800 bytes;
> - #3: **DATA in CHIP** of 296 bytes (copper lists);
> - #4: DATA + BSS of 29,312 bytes.
>
> Library bases: SysBase (4), IntuitionBase (A4+$7258), GfxBase (A4+$725C),
> DOSBase (A4+$726C), ConsoleDevice (A4+$6FAC). **Legend**: **[O]** observed · **[D]** deduced ·
> **[S]** assumed. Public calls and behaviour; no instruction sequence copied, no
> data.

---

## 0. Crack addition (hunk 0) [O]

Before the C startup, the crack's stub **copies a 50-byte routine to the absolute address
$300–$35F**, in the user vector area. It is called later by the game code in
place of the protection. **$300–$360 must therefore remain free and intact.**

## 1. C startup (Lattice) [O]

- Clearing of the BSS; SetSignal(0, $3000) (exec −306).
- OpenLibrary("dos.library", 0) (−552). Failure ⇒ exit, code 100.
- ExecBase->ThisTask (+$114): pr_CurrentDir is kept.
- **Launched from the CLI** (pr_CLI ≠ 0): argv is built from `cli_CommandName` and
  the argument line. There is **neither Open nor WaitPort**.
- **Launched from the WB**:
  - WaitPort/GetMsg (−384/−372) of the WBStartup on pr_MsgPort;
  - CurrentDir(sm_ArgList→wa_Lock) (−126);
  - if sm_ToolWindow exists: Open(ToolWindow, MODE_OLDFILE) (−30), and pr_ConsoleTask receives the
    port of its handler.
- Call of `main`. The exit goes through CloseLibrary, Forbid and ReplyMsg of the WBStartup if there is
  one.

## 2. Initialisation (function $11414C), in order [O]

1. AllocMem(n, MEMF_PUBLIC) (exec −198). Failure ⇒ return 0, **silent exit**.
2. Internal init (settings, then mouse and pointer tables).
3. **OpenLibrary("intuition.library", 1)** and **OpenLibrary("graphics.library", 1)**. A failure
   closes whatever is open, then silent exit.
   - **GfxBase+$CF bit 2** is tested: it is the low byte of `gb_DisplayFlags`, **PAL** bit. The
     program derives two parameters from it: (5, 5) in PAL, (4, 6) in NTSC.
4. **OpenDevice("console.device", −1, local ioreq, 0)** (exec −444): io_Device is kept as
   **ConsoleDevice**, which will only be used for RawKeyConvert. **The result of OpenDevice is not
   tested.**
5. Intuition **CloseWorkBench()** (−78). The result is not tested.
6. **Game bitmaps** ($114436):
   - graphics **InitBitMap(bm1 = A4+$6FE6, depth 5, 320, 200)** (−390);
   - graphics **InitBitMap(bm2 = A4+$700E, depth 5, 320, …)**;
   - for each one, **AllocMem(40,000, MEMF_CHIP|MEMF_PUBLIC)** (−198), split by hand into
     5 planes of 8,000 bytes, at +0, +$1F40, +$3E80, +$5DC0 and +$7D00. There is no AllocRaster.
   - Failure of an allocation ⇒ DisplayAlert (point 11) with code 6, then exit.
7. AllocMem($24, PUBLIC|CLEAR) (code 5 on failure).
8. **OpenScreen(NewScreen)** (−198), with the NewScreen at A4+$151A:

   | Field | Value |
   |---|---|
   | LeftEdge, TopEdge, Width, Height | 0, 0, **320, 200** |
   | Depth | **5** |
   | DetailPen, BlockPen | 0, 1 |
   | ViewModes | **$4000 (SPRITES)**: lores, neither HIRES nor LACE |
   | Type | **$004F = CUSTOMSCREEN \| CUSTOMBITMAP**. **Neither SCREENQUIET ($0100) nor SHOWTITLE ($0010)** |
   | Font | **TextAttr { "topaz.font", 8, style 0, FPF_ROMFONT }** |
   | DefaultTitle, Gadgets | NULL, NULL |
   | **CustomBitMap** | **bm1 (A4+$6FE6)**, filled in just before the call |

   Failure ⇒ code 4, exit.
9. **ShowTitle(screen, FALSE)** (−282): the title bar goes behind BACKDROP windows.
10. **OpenWindow(NewWindow)** (−204), with the NewWindow at A4+$153A and `Screen` = this screen:

    | Field | Value |
    |---|---|
    | LeftEdge, TopEdge, Width, Height | 0, 0, 320, 200 |
    | DetailPen, BlockPen | 0, 1 |
    | **IDCMPFlags** | **$0004840C**: REFRESHWINDOW, MOUSEBUTTONS, **RAWKEY**, DISKINSERTED, ACTIVEWINDOW |
    | **Flags** | **$00011940**: SIMPLE_REFRESH ($40), **BACKDROP** ($100), **BORDERLESS** ($800), **ACTIVATE** ($1000), **RMBTRAP** ($10000) |
    | FirstGadget, CheckMark, Title, BitMap | NULL |
    | Min / Max | 48×24 / 320×189 |
    | Type | CUSTOMSCREEN |

    Failure ⇒ code 2, exit.
11. Every exit on error goes through routine $11430E. It does **DisplayAlert(0 =
    RECOVERY, text, 50)** (−90), then closes in reverse order: RemIntServer, pointer,
    CloseWindow, CloseScreen, FreeMem, **OpenWorkBench** (−210), CloseLibrary.
12. **Display setup ($114ED0)**: see §3.
13. FindTask(NULL) (−294): **pr_WindowPtr (+$B8) := the window**, the old value being
    kept. dos requesters therefore open on this screen.
14. Internal tables; pointer init ($113BA8: AllocMem, **SetPointer** −270, ClearPointer
    −60, FreeMem).
15. **AddIntServer(INTB_VERTB = 5, &interrupt)** (exec −168):
    - Interrupt: ln_Type 2, **ln_Pri −60**, is_Data = A4+$59C4;
    - the server **adds a speed to a counter and increments a frame counter**, then
      returns 0, which lets the chain continue;
    - **the game times everything with this counter.**
16. Media detection ($114568):
    - dos **CurrentDir(0)** then CurrentDir(old) (−126);
    - **Info(lock, InfoData)** (−114);
    - **id_NumBlocks (+$0C) = 1758** ⇒ "floppy" flag.
17. **GetPrefs(buf, 232)** (−132): ViewXOffset/ViewYOffset (+$76/+$77) and ViewInitX/ViewInitY
    (+$78/+$7A) are used to place the split line of the copper list (§3).

The game then reads its data (§4) and reaches the "Appuyez sur ENTER" screen. This text is
**not** a string of the program: it comes from the game data (charsets and SCUMM scripts in the
Rooms files). It is **drawn by the game itself into bm1/bm2**, with the CPU and the blitter:
- **OwnBlitter (−456) / WaitBlit (−228) / DisownBlitter (−462)**;
- blitter registers written directly.

**There is no Text(), no Move(), no SetAPen, no SetRast, no OpenFont, no OpenDiskFont.**

## 3. Building the display: user copper list + home-made copper lists in CHIP [O]

$114ED0, called with the window:
1. **LoadRGB4(&Screen.ViewPort, table, 1)** (−192): **a single colour** (COLOR00). The other
   colours are written later by the game, in its own copper lists.
2. **Reading of the 5 plane pointers of `Screen.BitMap`** (Screen +$B8, Planes at +8), copied
   into home-made copper list no. 1 of hunk 3 (CHIP, $118240). The 5 planes of **bm2** are copied
   into list no. 2 ($118320).
3. **Reading of gb_copinit (GfxBase +$26)**, copied into both home-made lists to reload
   COP1LC there.
4. AllocMem(12, MEMF_CHIP? $10002 = CLEAR|CHIP), then graphics **UCopperListInit(ucl, 12)**
   (−594), then the instructions:
   - **CWait(v = −1, h = $24)** (−378) and CBump (−366);
   - **CMove(BPLCON0, $0200)** (−372) and CBump;
   - **CMove(COP1LCH, high part of list no. 1)**, CMove(COP1LCL, low part), **CMove(COPJMP1, 0)**:
     **the system copper jumps into the home-made list**;
   - CWait(100, 128), CWait(10000, 255): end of list.
5. **Screen.ViewPort.UCopIns (Screen +$40) := ucl**, then intuition **RethinkDisplay()** (−390).

Home-made copper lists (hunk 3, CHIP), described in terms of registers:

| List no. 1 ($118240) | List no. 2 ($118320) |
|---|---|
| BPLCON2/BPLCON1 := 0 | |
| **COLOR00–COLOR31** (32 MOVEs, values set by the game) | |
| DMACON := $0000; **COP1LC := list no. 2 and COPJMP1** (this MOVE is enabled or disabled by the game, by rewriting its register) | |
| DMACON := $8100 (BPLEN); **BPLCON0 := $5200** (5 planes, COLOR) | DMACON := $8100; **BPLCON0 := $5200** |
| **BPL1PT…BPL5PT := planes of Screen.BitMap** | **BPL1PT…BPL5PT := planes of bm2** |
| **COP1LC := gb_copinit** | **COP1LC := gb_copinit** |
| WAIT split line ($80E1 or $00E1, then (200 + offset) << 8) | same |
| BPLCON0 := $0200 (display off below the area); end | same |

**What this requires from the ROM**:
- **(a)** OpenScreen with **CUSTOMBITMAP** must **display the BitMap provided**. Intuition copies
  `*ns_CustomBitMap` into `Screen.BitMap` and **allocates no plane**. The game reads
  `Screen.BitMap.Planes[]` and draws into bm1. If our OpenScreen allocates its own planes:
  - the copper displays our planes, empty, hence **a black screen without text**;
  - the game draws elsewhere.
- **(b)** MakeVPort/MrgCop (via RethinkDisplay) must **insert `vp_UCopIns`** into the view's copper
  list, at the position of the CWait relative to the ViewPort. If UCopIns is ignored:
  - the home-made lists never run;
  - only the intuition screen is visible: title bar, gadgets, our planes;
  - this is **exactly the symptom described**.
- **(c)** `gb_copinit` (GfxBase +$26) must be the real copinit, restarted by the hardware at
  every frame, as for the cracktros.
- **(d)** ShowTitle(FALSE) with a full-screen BACKDROP window must hide the title bar.
  This is secondary: on the real ROM, the home-made list takes over from the top of the screen.

## 4. Files [O]

All I/O goes through the Lattice wrappers:
- **open**: Lock(name, SHARED −2) to test existence, then UnLock, DeleteFile if creating,
  and Open(MODE_OLDFILE 1005 / MODE_NEWFILE 1006);
- **read** and **write** (−42/−48): Read(fh, buf, n); result −1 ⇒ IoErr (−132);
- **lseek**: **Seek(fh, pos, mode − 1)** (−66), so C 0/1/2 ⇒ OFFSET_BEGINNING −1, CURRENT 0,
  END 1. Value returned:
  - SEEK_SET ⇒ pos;
  - SEEK_CUR ⇒ **old position returned by Seek + pos**;
  - SEEK_END ⇒ a second **Seek(fh, 0, OFFSET_CURRENT)**.

  **This requires Seek to return the OLD position**, like dos 1.3, and −1 on error.
  A Seek that returns the new position corrupts all relative offsets and sizes.
- **close** (−36).

Names built (program strings):
- "Rooms/%s" and "%sRooms/%s" (volume prefix);
- **"music.dat"** and **"sample.dat"** ("Can't open …" messages if they are missing);
- "%s.%d\\%s" and "XXX.lfl" (rooms);
- **"diskXX.lec"** (DISK01.LEC, 365 KB, read by Seek + Read);
- "savegame._x_".

Engine messages on failure: "Room %d not in disk%02d.LEC", "Please Insert Disk %c",
"Unable to find '%s' Press ENTER". They are also displayed in the game's bitmaps.

Disk drive (DISKINSERTED in the IDCMP): floppy changes.

## 5. Hardware accesses and vectors (music player, $100F20–$1017BE) [O]

The music player, activated at the first tune, takes over the hardware **directly**:
- **Autovectors written directly** (saved, then restored on stop):
  - **$6C (level 3)** := its handler. It calls the player on COPER, or on VERTB if
    VHPOSR < line $0A, then **chains to the old vector**. The OS's VERTB chain therefore
    continues;
  - **$70 (level 4, audio)** := its handler, **without chaining**: audio.device no longer sees its
    interrupts;
  - **$78 (level 6, EXTER)** := its handler. It reads CIA-B's ICR, acknowledges INTREQ $2000,
    calls the player and does RTE, **without chaining to the OS**.
- **CIA-B**:
  - timer B ($BFD600/$BFD700) := $2E2E if ExecBase->VBlankFrequency (+$212) = 50, adjusted according to
    a configuration bit (values $2E2E or $37F0);
  - **CRB ($BFDF00) := $11** (start, continuous mode);
  - **ICR ($BFDD00) := $82** (enables the timer B interrupt);
  - **INTENA := $A000** (EXTER).
- INTENA $8020, DMACON of the audio channels, audio registers $A8/$B8/$C8/$D8, ADKCON $00FF.
- CIA-A PRA bit 1 (filter) set to 1.

**Consequence for our ROM [D, to be verified]**:
- **As long as the music plays, everything that goes through the OS's level 6 interrupt is dead.**
  - Our timer.device **UNIT_MICROHZ uses CIA-B / INT6** (project notes). Once the music
    starts, **any MICROHZ request, or any code that depends on it, is never
    served again**.
  - This applies to a trackdisk waiting for MICROHZ delays, a Delay() if it goes through MICROHZ,
    key repeat… ⇒ **silent hang of the loading**.
- **On the real 1.3, timer.device uses ciaa.resource**: the string "ciaa.resource" is
  in timer.device. Level 6 is not used there for MICROHZ, and the game's takeover of vector $78
  has no effect on disk loading.
  - trackdisk does open ciab.resource, but nothing indicates that it needs
    the interrupt to read [S].
- **Recommendation**: MICROHZ and any disk delay must go through CIA-A (level 2, PORTS).
  Otherwise, nothing may depend on a level 6 interrupt during reads.

## 6. Waiting for ENTER [O]

Event reading loop ($1136B8), through **GetMsg(window->UserPort)** (−372). It is
polling: the game does no WaitPort on this path. Then ReplyMsg (−378).
- **im_Class = RAWKEY ($400)**:
  - code 50 (`$32`, with qualifiers $30) ⇒ internal code $12D;
  - **codes $50–$59 (F1–F10)** ⇒ internal codes, taking Shift into account;
  - **bit 7 of the code at 1 (key released) ⇒ ignored**;
  - otherwise, construction of an **InputEvent on the stack**:
    - ie_Class = 1 (RAWKEY), ie_SubClass = 0;
    - ie_Code = im_Code, ie_Qualifier = im_Qualifier;
    - **ie_EventAddress = *(im_IAddress)**: the long pointed to by IAddress, i.e. the
      previous keys for dead keys;
    - then **RawKeyConvert(ie, buf, 8, keymap NULL)** (console −48). **Only a result of
      exactly 1** is taken: the character. ENTER/RETURN ⇒ $0D.
- **im_Class = MOUSEBUTTONS ($8)**: SELECTDOWN ($68) / MENUDOWN ($69) with a double-click
  test on im_Seconds/im_Micros. The right button is trapped by RMBTRAP.
- Other classes: ignored.

**Requirements [D]**:
- the RAWKEY IDCMP must reach this BACKDROP ACTIVATE window;
- **im_IAddress must be a valid pointer** (dereferenced). A NULL reads address 0, which
  is harmless but gives an arbitrary value;
- RawKeyConvert must return **1** and `$0D` for RETURN ($44) and keypad ENTER ($43), with the
  default keymap.

## 7. Summary of possible hang or black-screen points [D]

| # | Condition | Effect on our side |
|---|---|---|
| 1 | OpenScreen **CUSTOMBITMAP** not honoured (planes allocated by us) | black screen, no text, game alive |
| 2 | **vp_UCopIns** ignored by MakeVPort/MrgCop/RethinkDisplay | intuition screen visible (bar, gadgets), no game display |
| 3 | gb_copinit (GfxBase+$26) wrong, or COP1LC not restarted per frame | inconsistent display |
| 4 | **Vector $78 taken by the music, and MICROHZ or disk delays on CIA-B/INT6** | loading frozen without a message |
| 5 | VBlank server (AddIntServer 5, pri −60) never called, or frame counter frozen | engine frozen (everything is timed in frames) |
| 6 | **Seek** returning the new position instead of the old one | wrong reads in DISK01.LEC, room not found |
| 7 | RawKeyConvert ≠ 1 character for ENTER, or RAWKEY not delivered | ENTER has no effect (after the display) |
| 8 | Area $300–$35F overwritten (crack routine) | crash when passing the protection |

Recommended order:
1. probe `Screen.BitMap.Planes[0]` against the planes of bm1 (A4+$6FE6+8);
2. check the presence of the UCopIns list in the system copper list (MOVE COP1LC then COPJMP1
   to an address in hunk 3);
3. check that vector $78 is modified during loading, and the state of our MICROHZ
   requests.

---

## Clean-room review

- [x] No instruction sequence copied: public calls with LVO and arguments, NewScreen and
  NewWindow field by field, hardware registers and values, conditions.
- [x] No game data (image, music, text) reproduced; the copper lists are described
  as register → role tables.
- [x] **Correction of 2026-10-29**: removed the 2 ROM addresses (string in timer.device,
  opening of ciab.resource by trackdisk); finding unchanged.
