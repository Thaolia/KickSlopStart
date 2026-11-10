# cluedo-v34.md — Cluedo Master Detective (French) on the real Kickstart 1.3; trackdisk after a head move

> ANALYSIS track ("dirty"). Date: 2026-11-10. Sources: the real Kickstart 1.3 ROM (`kick34005.A500`, read-only)
> run under Amiberry v8.4.2 (A500 preset, 512 KB chip + 512 KB slow RAM, cycle-exact), observed as a black box:
> screenshots looked at, hardware breakpoints on the dos library's jump-table entries (in RAM) and on callers'
> return addresses, a debugger watch on the CIA-B port B register, emulator logging watches, and the emulator's
> report of the drive head's cylinder (IPC `GET_DRIVE_STATE`). No disassembly of ROM code, no ROM address, no
> code written. The game disk is named by its title only (public repository rules).
>
> **Legend**: **[O]** observed · **[D]** deduced · **[?]** uncertain.
>
> Related pages: `dos-lvo-partial-v34.md` §1.1a (D1 = D0 after every dos LVO, with Cluedo's `Type` as the program
> that needs it), `trackdisk-official-timing.md`, `trackdisk-raw-changeint-v34.md`, `disk-change-v34.md`.

---

## 1. What the disk does at boot on 1.3 [O]

The boot floppy (OFS, standard boot block) has `c`, `devs`, `l`, `libs`, `s` and `saved_games` directories, the
game program `clue` (187,612 bytes), five 40,000-byte picture files and a 107,092-byte sound file. Its
startup-sequence, in order: a `border` command (turns the boot CLI window's border off), a `type` of a text file
followed by `mouse` (waits for a left click), a second `type` + `mouse`, `binddrivers`, `loadwb`, `clue`,
`endcli >NIL:`. `border`, `mouse` and `Type` are the disk's own small commands (not the Workbench ones).

What is seen on the real 1.3:

1. About 25 s after power-on: a black screen (the borderless CLI window) with a small two-colour logo at the top
   left and two centred text lines framed by two dashed lines (the release's text page). Nothing moves until the
   left button is clicked.
2. A second page of the same kind; again a click is needed.
3. After the second click: BindDrivers and LoadWB run (a Workbench process named "Workbench" opens and reads its
   icons with Open/Read/Close), then `clue` starts. The game detaches itself: its dos calls come from a process
   named **"BackGround_Process"**.
4. The game loads its picture files with `Open(name, MODE_OLDFILE)`, one `Read` of 40,000 bytes, `Close`
   (several times), and one larger read of 107,000 bytes; no Seek was seen in the game's own calls (dos LVOs
   sampled with breakpoints, 2 runs).
5. Without any further input it reaches the **player selection screen**: ten suspect portraits in two rows of
   five, each with a name label above it ("COL. MUSTARD", "PROF. PLUM", "MR. GREEN", "M. BRUNETTE", "MISS PEACH",
   "MRS. PEACOCK", "MME ROSE", "MISS SCARLET", "MRS. WHITE", "SGT. GRAY"), the word "NEUTRE" and an empty box under
   each, and a "START" button between the rows. This is the point our ROM also reaches (PLAN, 2026-11-03).

The startup-sequence's `Type` (1380 bytes) reads the file length with **Seek(fh, 0, OFFSET_END) called twice**
and takes the second result (the previous position = the length, 315 for the first text file) from **D1**. On 1.3
both D0 and D1 hold it (`dos-lvo-partial-v34.md` §1.1a). [O]

---

## 2. trackdisk when the head was moved behind its back [O]

### 2.1 Method

Real ROM, a CLI-only boot floppy made with xdftool (OFS, standard boot block, a `c` directory with a few Workbench
1.3.3 commands and a 336,000-byte file). After the boot (head left near cylinder 40 by the root block reads),
the head of DF0: was stepped **by the debugger**, with no Amiga code involved: emulator memory writes to CIA-B
port B (drive 0 selected, direction inwards, STEP pulsed low then high, ~0.1–0.25 s apart, then all drives
deselected). The emulator reported the new cylinder; trackdisk was not told anything. Then a CLI command was typed
that needed a block not in the file system's buffers. Logged: every write that pulsed STEP with drive 0
selected (direction bit), every DSKLEN write (disk DMA start), and the head cylinder about every 0.1 s.

### 2.2 What trackdisk does [O]

Three runs, same result each time (trackdisk believing the head on cylinder 39–43, the head moved to 56, 67 and 63):

1. **No check before seeking.** trackdisk seeks **relatively from the cylinder it remembers**, not from where the
   head is: it believed the head was on cylinder 41 and wanted 43, so it gave exactly 2 inward steps (63 → 65).
   It does not look at the track-0 sensor or re-read a header first.
2. **It reads the wrong track several times.** At the wrong cylinder it started **4 full-track DMA reads** (each:
   DSKLEN cleared, then the read length written twice, the same value as for a normal track read; counted in the
   one run where every DSKLEN write was logged); 1.0–1.3 s were spent at the wrong cylinder in the two runs whose head position was timed.
3. **Then it recalibrates.** It steps **outwards until the track-0 sensor** (65 steps from cylinder 65 — exactly
   the distance, so it stops on the sensor, not after a fixed count), then **inwards to the wanted cylinder**
   (43 steps), reads once, and the read succeeds.
4. **No error reaches the program.** The commands (`dir`, `info`, `wait 1`) printed normal results; no requester;
   `Info` showed **0** in the "Errs" (soft errors) column of DF0: afterwards.
5. After the recovery the remembered cylinder is right again: the next accesses seek normally from it.

### 2.3 Rules for an implementation [D]

- Keep the remembered cylinder and seek relatively; do not recalibrate before every seek.
- When the sectors read come from another cylinder than the one asked (sector header track number), treat it as a
  read error: retry the read a few times (1.3: 4 reads in total at the wrong cylinder, one fully logged run), then recalibrate (step
  out until the track-0 sensor, at most the drive's cylinder count + a margin), seek again, read.
- The recovery is invisible to the caller: success, no requester, no soft-error count.
- [?] Not tested: a head moved behind trackdisk's back followed by a **write** to the track trackdisk already holds
  in its buffer (it may write without seeking, to the wrong cylinder); a head moved to the other side of the
  target so that the relative seek runs into track 0; the exact retry count when the wrong cylinder's sectors
  partly match.

---

## 3. What Cluedo itself does to the drive, and how 1.3 copes [O]

Method: a copy of the disk whose startup-sequence was cut to `binddrivers`, `loadwb`, `clue`, `endcli` (the two
text pages and their clicks removed, so that no input is needed); real ROM; emulator logging watches on every
CIA-B port B write that pulses STEP with drive 0 selected and on every DSKLEN write, each event tagged ROM code /
RAM code by the writing instruction's location (only the ROM/RAM split is kept here); head cylinder sampled about
every 0.05 s. Two runs (the second one with the DSKLEN and head logs), no event lost (the hit ring was emptied
every ~0.45 s with the emulation paused, "dropped" stayed 0). The game reached its player selection in both.

1. Up to then all stepping is trackdisk's (ROM code): it loads `clue` and the first files, moving the head one
   cylinder at a time downwards from 40 (the files lie on consecutive cylinders), two DMA track reads per
   cylinder.
2. **Once, about 52 s after power-on** (before the player selection appears), **the game's own code** (RAM)
   pulses STEP **35 times outwards** on DF0: — the head goes from cylinder 35, where trackdisk had left it, to
   **cylinder 0** — and then **starts disk DMA itself** (DSKLEN writes from RAM code: three with DMAEN clear, then
   two with DMAEN set, the usual "start a read" sequence). Its purpose is not established (a track-0 or protection
   read is likely) [?]. The motor went off then on again within 0.2 s right after [O; which code did it is not
   known].
3. This happens behind trackdisk's back: trackdisk still believes the head is on cylinder 35. Its next request
   (cylinder 40) gives **5 inward steps** (head now on cylinder 5), then **4 DMA reads** of the wrong cylinder, then
   **5 outward steps** (stopped by the track-0 sensor), **40 inward steps**, one read, and the loading goes on
   normally (exactly the recovery of §2.2). About 2 s are lost; nothing is shown to the user.
4. No other step pulse or DSKLEN write from the game's code was seen up to the player selection (the rest of the
   loading, cylinders 1 to 77, is trackdisk's).

So on 1.3 Cluedo depends on trackdisk recovering from a wrong cylinder by itself; a trackdisk that trusts its
remembered cylinder forever would read cylinder 5 instead of 40 and fail the game's load. [D]

---

## Clean-room review

- [x] No instruction sequence, no ROM address, no ROM data. Figures are cylinder numbers, step counts, read
  counts, file sizes and register values on return from dos calls.
- [x] The game disk is named by its title; no release name, group name or dump tag; the text pages of the release
  are described, not quoted.
- [x] Probes: commands typed in a CLI, debugger writes to a CIA register, breakpoints on RAM jump-table entries and
  callers, emulator watches; no program written.
