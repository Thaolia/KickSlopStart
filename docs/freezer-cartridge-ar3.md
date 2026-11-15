# Action Replay MK III: what the cartridge requires from the Kickstart

Reported on the English Amiga Board (2026-11-15): with an Action Replay MK III plugged in, KickSlopStart did not
boot (black screen, nothing on the serial port). This page records what the cartridge expects at reset and how
`coldstart` meets it.

## Provenance

Everything here comes from the cartridge, which is a third-party program: its v3.17 ROM (256 KB, mapped at
`$400000`, its RAM at `$440000`-`$44FFFF`) was disassembled on the implementation side, with the GAL equations of a
public replica board and Amiberry runs of our ROM. The Commodore ROM was not read. The two Kickstart offsets below
are constants **inside the cartridge**; the ROM layout they impose is a compatibility interface, in the same way as
the reset entry at `$FC00D2` and the `RESET` word at `$FC00D0`.

## Reset contract

1. After a reset the cartridge traps the first CPU access to `$8`-`$B` with an NMI (the replica's GALs decode any
   read or write there; Amiberry's emulation fires on the first such write). The NMI vector comes from the
   cartridge, so the Kickstart needs an even supervisor stack in RAM at that moment.
2. It compares the **stacked PC** with `$FC0144` (1.3) or `$F80160` (2.04). Any other value is taken as an ordinary
   press of the freeze button: the cartridge opens its user interface and the machine never boots. That was our bug:
   our first `$8` access was `diag_vectors`, at another address.
3. It expects that access to be an exception-vector fill loop: a long store `A1 -> (A0)+` that ends at `$FC0144`,
   followed by `dbra d1` back to it. Depending on its state and settings it then
   - resumes at `$FC0144` with all registers as frozen except A3 (= `$FC0144`) and A7 (= `$40000`);
   - or completes the loop itself from D1/A0/A1 and enters the Kickstart at `$FC0240` with A3 = chip RAM top,
     A4/D0 = end of the slow RAM (0 = none), A6 = where 1.3 puts ExecBase, D6/D7 = the numbers of a dead-end alert
     whose `'HELP'` mark it consumed at `$0` (D6 = -1 when there is none), A7 = `$40000`, SR still the NMI's;
   - or, at power-on, initialises itself and restarts the Kickstart at the reset PC of its header, through
     `$F80004`, without a hardware reset.
4. Other uses of 1.3 internals are features, not boot requirements: its reset command jumps to `$FC00D0` after
   making `$4` odd (our `RESET` word and odd-ExecBase handling already cover it), and its virus checker compares
   exec's DoIO vector with 1.3's DoIO address (a virus killer that writes that address into DoIO would break our
   ROM; not handled). On every reset its virus check clears ColdCapture, CoolCapture, WarmCapture and the three
   KickMem/KickTag fields of a valid ExecBase when any of them is set (default setting), whatever the Kickstart does.

## What `coldstart` does (`src/exec/boot.s`)

- Right after the overlay is switched off, it sets SP to `STACKTOP` and fills vectors 2-47 with `diag_anyvec`
  (`src/exec/diag.s`: the early exception screen, vector number unknown) in a `move.l a1,(a0)+` / `dbra d1` loop
  placed so that the `dbra` sits at ROM offset `$144` (`VEC_FILL_AT`, checked by an assembly-time `fail`). This is
  now the first access to `$8`, before ColdCapture runs, and `diag_vectors` still gives each vector its own stub
  a little later.
- `ar_reentry` sits at offset `$240` (`AR_REENTRY_AT`, checked the same way). It puts the `'HELP'` mark and its
  numbers (`$100`/`$104`) back when D6 is not -1, then joins the normal path after the loop. The memory sizes and
  the ExecBase address the cartridge passes are not used: our own sizing runs as usual. So a cartridge setting that
  hides or adds memory is **not honoured**.
- Between the loop and `ar_reentry` the image holds zero padding (about 240 bytes).

Amiberry, when it finds this loop in the Kickstart, rewrites the PC constant inside the cartridge image to the
loop's address ("AR ROM patched for KS2.0+" in its log). With our loop at the 1.3 place, the value is unchanged.

## Verification (2026-11-15, dev ROM, Amiberry 8.4.2, cartridge image `assets/ar3.rom`)

- 512 KB chip + 512 KB slow RAM, Workbench 1.3.3 disk: the boot reaches the end of the startup-sequence. The freeze
  key (Pause) shows the cartridge screen ("No known virus in memory! Ready."), and `x` returns to the Workbench.
- Which path a reset takes: a throw-away copy of the ROM where `$FC0240` paints the screen red and stops. After an
  emulated reset, the screen is red with 512 KB of slow RAM (the cartridge enters at `$FC0240`). Without slow RAM
  it is not red: the cartridge resumes at the loop. At power-on neither (first install, then a restart of the
  Kickstart that the trap does not catch again under Amiberry).
- Real ROM, cartridge, then an emulated reset, in both memory configurations: the Workbench boots again.

Not verified: a real cartridge or the replica board, the cartridge's memory settings, a dead-end alert across a
reset with the cartridge.

Command used:

```sh
A=.claude/skills/amiberry/scripts/amiberry-session
$A start --name ar3 --adf <Workbench 1.3.3 boot disk> -- -s cart_file=$PWD/assets/ar3.rom
# freeze: the Pause key in the Amiberry window (xdotool on the session's Xvfb display)
```
