# keyboard-handshake-v34.md — receiving a keyboard byte and the handshake (KS 1.3)

> ANALYSIS track ("dirty"). Source: ROM `assets/kick34005.A500`. Modules covered:
> - keyboard.device: resident, init, CRA setup, interrupt handler, end of handshake;
> - ciaa.resource: server, AddICRVector, AbleICR/SetICR;
> - exec: walk of the server chain;
> - timer.device (for CIA-A timer B).
> No ROM addresses (removed on 2026-10-29).
>
> **Legend**: **[O]** observed · **[D]** deduced · **[S]** assumed. CIA-A registers:
> PRA $BFE001, TBLO $BFE601, TBHI $BFE701, **SDR $BFEC01**, **ICR $BFED01**, **CRA $BFEE01**,
> CRB $BFEF01. Behaviour only.

---

## 1. Where the interrupt is serviced [O]

1. CIA-A /IRQ ⇒ Paula **INTREQ PORTS (bit 3)** ⇒ **level 2** ⇒ exec's PORTS server chain.
2. The **ciaa.resource server** does, in order:
   - **a single read of the ICR ($BFED01)**, at the very beginning. This read clears all the
     CIA's flags;
   - bit 7 removed, OR with the remembered flags (the resource's "pending"), then AND with the
     enabled mask;
   - the bits handled are removed from pending;
   - calls the vectors **in bit order**: 0 TA, 1 TB, 2 ALRM, **3 SP**, 4 FLG. Each
     vector receives A1 = is_Data and A5 = is_Code.
   - **The ICR is not re-read at any other point of the service.**
3. Exec acknowledges **INTREQ PORTS only after** walking the whole server chain. If the CIA receives a new byte during the service, its /IRQ stays active and the
   PORTS bit is raised again. The new byte is therefore not lost, since its SP flag has not been
   re-read [D].
4. keyboard.device installs its handler with **AddICRVector(CIAICRB_SP = 3, &interrupt)**
   (ciaa.resource −6), the Interrupt being at keyboard+$5A with is_Data = the device base. The
   resource enables the SP bit in the ICR (write $80|$08).

## 2. Initialisation (keyboard.device, once) [O]

On CIA-A, in this order:
1. **CRA := $00, then CRA := $00, then CRA := $40.** These are full-byte writes:
   timer A stopped (START 0), RUNMODE 0, INMODE 0, PBON 0, LOAD 0, **SPMODE 1 (output)**.
2. AddICRVector(3, …).
3. **CRA := $00.**

Together, these two steps form **a handshake pulse at init**, lasting as long as the
AddICRVector call, which acknowledges any byte already pending. Afterwards:
- **CRA is $00 permanently**, apart from bit 6 during a handshake;
- **CIA-A timer A never runs**: keyboard.device does not use it;
- timer.device 1.3 uses **CIA-A timer B** (CRB/TBLO/TBHI), never CRA.

## 3. Receiving a byte: exact order of accesses [O]

The handler is called by the ciaa.resource server, at level 2, with the ICR already read:
1. **Read of SDR ($BFEC01).**
2. **Immediately, CRA |= $40**: SPMODE to output, KDAT pulled low, start of the handshake. It is a
   read-modify-write of CRA, done **at the instruction following** the SDR read.
   The other CRA bits stay at 0.
3. Decoding: code = **NOT(byte) then rotate right by one bit**, i.e. bit 7 = release and
   bits 6–0 = key code.
4. **Case $78 (reset warning)**: see §5.
5. Update of the key matrix (13-byte bitmap at +$106) for codes ≤ $67, and of the
   qualifier word.
6. **Disable** (exec −120). Insertion of (code, qualifier) into the circular buffer (32
   entries of 4 bytes, 7-bit index). If the buffer is full, the last entry is
   replaced by an overflow code. **Enable** (−126).
7. If a KBD_READEVENT request is pending (in practice always, input.device's) and
   none is already being serviced: copy of the InputEvents into the request's buffer,
   then **ReplyMsg** (−378).
8. **CRA &= $BF**: SPMODE to input, KDAT released, **end of the handshake**.
9. Return to the ciaa.resource server.

What is **never** done along this path:
- writing SDR;
- reading or writing the ICR (already read by the resource);
- touching timers A or B;
- touching PRA or DDRA, reading VHPOSR, running a wait loop.

## 4. Pulse duration [O for the structure, D for the value]

- **No explicit delay.** The duration is simply the **execution time of steps
  3 to 7**: decoding, matrix, Disable/Enable and, usually, delivery of the events to
  input.device with ReplyMsg.
- Estimate on a 7.09 MHz 68000, without contention [D]:
  - around **100 µs** with no request to satisfy;
  - **150–300 µs** with the usual event copy and ReplyMsg.
- It is always longer than the **≈ 85 µs** minimum required by the keyboard [D, value from the
  public hardware specification]. It is **never fixed**.
- Our pulse of about 360 µs is therefore **within the plausible range**. The duration is
  probably not the discriminating factor [D].

## 5. Keyboard reset ($78) and special codes [O]

- First **$78**: a "1st warning" flag is set, then normal processing; the code
  is queued and the handshake ends.
- A **second consecutive $78** (flag already set):
  - "reset in progress" flag set;
  - for each handler in the KBD_ADDRESETHANDLER list: counter +$102 incremented, then
    **Cause** (exec −180);
  - **the handshake is NOT ended**: CRA bit 6 stays at 1;
  - it only ends at the last **KBD_RESETHANDLERDONE** (counter brought back to 0 ⇒ CRA &= $BF). If there is no handler, it ends immediately.
  - The keyboard waits for this handshake (at most about 10 s) before doing the hardware reset [D,
    public keyboard behaviour].
- Any code other than $78 clears the "1st warning" flag.
- **$79 to $7E** (after decoding: $F9 last code bad, $FA buffer full, $FC self-test
  failure, $FD/$FE start and end of the power-up sequence): no matrix update
  (code > $67). They are queued **like ordinary events**, then the
  handshake ends normally. **There is no software resynchronisation, no read of
  KCLK, and no access to DDRA/PRA.**

## 6. Comparison with our handshake and WinUAE leads [D]

Our sequence (read SDR, CRA |= $40, loop of about 360 µs, CRA &= ~$40) has the same order as
the ROM. The possible differences lie elsewhere:

1. **State of the other CRA bits.** The ROM keeps **CRA = $00**, with timer A stopped. If
   our CRA has **START = 1** (CIA-A timer A used for something else) or another RUNMODE,
   switching SPMODE to output with timer A running **starts an output shift** on SP,
   clocked by timer A. A cycle-exact emulator such as WinUAE may then see KDAT toggling instead
   of staying low, and reject the handshake.
   - **To check: CRA = $00 outside the handshake, and no use of CIA-A timer A.**
2. **Re-reading the ICR after the handshake.** WinUAE may send the next byte (the release
   $92) **very shortly after** the end of the handshake, while we are still in
   the interrupt.
   - A second read of **$BFED01** by our code clears the new byte's SP flag. This
     may be our dispatch re-reading the ICR after the handlers, an ICR poll for a
     timer, or an AbleICR/SetICR.
   - If our code also acknowledges PORTS before the end, or does not re-read the remembered flags,
     **the byte is lost** and the keyboard waits for a handshake that will never come.
   - FS-UAE is more tolerant of this delay.
   - **ROM rule**: a single ICR read per pass through the server, at the start, with
     the unhandled bits remembered.
3. **Acknowledging INTREQ PORTS**: it must be done after the service, and the CIA-level IRQ must
   be able to raise the bit again.
4. **Init**: start-up handshake pulse (CRA $00, $00, $40, … $00), which
   resynchronises a keyboard that has already sent a byte before the handler is installed (for example
   the power-up sequence $FD…$FE).

---

## Clean-room review

- [x] No instruction sequence copied: order of register accesses and values, structure of the
  interrupt service, conditions (reset, special codes) and duration estimate.
- [x] No ROM data reproduced (qualifier tables only mentioned).
- [x] **Correction of 2026-10-29**: removed the header "Landmarks" block (routine addresses of
  keyboard.device, ciaa.resource, exec, timer.device) and the addresses cited in the body;
  CIA registers (hardware addresses) kept.
