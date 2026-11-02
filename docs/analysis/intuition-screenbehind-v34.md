# intuition-screenbehind-v34.md — NewScreen type bit `$0080` (SCREENBEHIND) on intuition 34.3

> **ANALYSIS** track ("dirty"). Black-box observation of the real ROM `assets/kick34005.A500` under Amiberry
> (`amiberry-session --analysis`), with SimCity v1.2 as the client program. Behaviour only: no instruction
> sequence, no ROM address. Addresses quoted below are **RAM** addresses of the observed run (examples).
> Complements `intuition-screens-v34.md` §2.1 step 21, §2.6 and §5.2, which already state the rule from the
> binary and a probe; this page confirms it with a real program and gives the timeline.

## 1. Setup

- A500, 68000, 512 KB chip + 512 KB slow, PAL, not cycle-exact. Disk
  `SimCity v1.2 (1990)(Infogrames)[cr RZR].adf`: RAZOR cracktro (left click), boot to the Workbench 1.3,
  open the `SimCity1.2` disk, double-click the `SimCity` icon.
- During the load, a host script polled through the Amiberry IPC socket, about 10 times per second:
  an IPC screenshot; the screen list (IntuitionBase found by name in exec's LibList, `FirstScreen` at
  IB+60, then `NextScreen` +0, `Flags` +20, `Width`/`Height` +12/+14, `Title` +22);
  `GfxBase->ActiView` (+34) and its ViewPort chain (`Modes` at ViewPort+32); for the 320-wide screen, colours
  0–3 of its ColorMap and a sample of 10 words per bitplane (Screen.BitMap at +184).
- Second run: hardware breakpoints on intuition's **library vectors** (jump table in RAM) for OpenScreen
  (LVO −198) and ScreenToFront (LVO −252), reading A0 and the return address.
- Two runs, same results (timings within ~1.5 s of each other).

## 2. Observations

### 2.1 What the user sees

Run 1, times from the double-click (screenshots compared pixel by pixel; the only changes before the title are
the Workbench busy pointer and the screen title):

| t (s) | Display |
|---:|---|
| 0 – 26 | Workbench only (busy pointer, title "Workbench Screen" from ~16 s) |
| ~21 | SimCity screen opened (not visible) |
| ~26 | title picture appears **complete, with its final palette, in one frame** |
| 26 – 79 | unchanged |

No intermediate picture was ever displayed: no plane-by-plane build-up and no wrong-colour stages.

### 2.2 OpenScreen call (run 2)

NewScreen passed by the game (RAM structure, 32 bytes): LeftEdge 0, TopEdge 0, Width 320, Height 200,
Depth 5, DetailPen 0, BlockPen 1, ViewModes `$0000`, **Type `$008F`**, Font 0, DefaultTitle 0, Gadgets 0,
CustomBitMap 0.

### 2.3 Screen list, ViewPorts and drawing, run 2 (t from the double-click)

| t (s) | Screen list, front → back (Flags) | ViewPort chain of ActiView (Modes) | SimCity colours 0–3 | Non-zero samples per plane 0..4 |
|---:|---|---|---|---|
| < 22.2 | WB (`$0011`) | WB `$C000` | — | — |
| 22.2 | WB (`$0011`) (not yet linked) | SimCity `$4000`, WB `$C000` | — | — |
| 22.3 | WB (`$0011`), **SimCity (`$009F`)** | SimCity **`$6000`** (VP_HIDE), WB `$C000` | `000 FFF 04B F80` | 2 1 0 0 0 |
| 23.1 | same | same | same | 1 1 0 0 0 |
| 23.8 | same | same | same | 8 2 0 0 0 |
| 24.6 | same | same | same | 8 10 0 0 0 |
| 25.3 | same | same | same | 8 10 5 0 0 |
| 26.1 | same | same | same | 8 10 8 4 0 |
| 26.8 | same | same | same | 8 10 8 10 4 |
| 27.0 | same | same | same | 8 10 8 10 8 (picture complete) |
| 27.2 | same | same | **`000 FFF F00 F00`** (palette loaded) | complete |
| 27.3 | **SimCity (`$009F`)**, WB (`$0011`) | SimCity `$4000`, WB **`$E000`** (VP_HIDE) | final | complete |

(The run-2 clock started ~1 s before the double-click; the table subtracts it.)

- The breakpoint on ScreenToFront hit **once**, with A0 = the SimCity screen (`$C07998`) and a return
  address inside the game's code in RAM: the screen comes to the front because **the game calls
  ScreenToFront** after loading its palette. No other path brought it forward.
- ActiView stayed intuition's View for the whole run.
- The ViewPort of the new screen is chained at the head of the View even though the screen is at the tail of
  the screen list (as in `intuition-screens-v34.md` §2.6); display order follows the screen list via
  VP_HIDE, not the ViewPort chain.
- Flags stay `$009F` after ScreenToFront: the SCREENBEHIND bit remains set in `Screen.Flags`.
- One poll during each ScreenToFront saw the list with only the WB while the ViewPorts were already in their
  final state. The poll is not atomic (one IPC read per field), so this is a torn read of the
  unlink/relink, not a state to reproduce.

## 3. The rule (intuition 34.3)

1. `Screen.Flags = NewScreen.Type | SHOWTITLE ($10)`: `$008F` gives `$009F`. The `$0080` bit is kept in Flags
   for the life of the screen; ScreenToFront does not clear it.
2. With `$0080`, OpenScreen links the new screen at the **tail** of the IntuitionBase screen list (behind every
   existing screen) instead of the head. Its ViewPort is still chained into the View, and OpenScreen still
   remakes the display.
3. The normal layout then applies (`intuition-screens-v34.md` §5.2): a screen behind a full-height screen
   (here the Workbench, TopEdge 0, 256 lines) gets **VP_HIDE** and is not shown. Nothing the program draws or
   loads into its palette is visible meanwhile.
4. The screen stays hidden until something reorders the list: here the program's own **ScreenToFront**. That
   call moves the screen to the head, clears its VP_HIDE, hides the Workbench behind it (VP_HIDE, it starts at
   the same line) and remakes the display: the finished picture appears in one frame.
5. SCREENBEHIND does not make the screen invisible by itself: a SCREENBEHIND screen whose TopEdge is below the
   bottom-minus-3-lines of the screens in front of it would show its upper part (layout rule of §5.2). With
   SimCity (TopEdge 0 behind a TopEdge-0 Workbench) it is fully hidden.

Consequence for a 1.3-compatible ROM: putting a `$0080` screen at the head of the list (or showing it before
ScreenToFront) exposes SimCity's plane-by-plane drawing and palette changes; the real ROM keeps it behind the
Workbench for the ~5 s of drawing.
