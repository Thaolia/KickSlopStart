# resources-v34.md — cia.resource, disk.resource, potgo.resource, misc.resource (Kickstart 1.3, 34.5)

> **ANALYSIS track ("dirty").** Behavioural spec: entry registers, return values, side effects, base layouts
> (offsets = ABI), hardware registers. No instruction listing, no ROM address.
>
> **Evidence levels.** **[O]** read unambiguously in the ROM. **[P]** observed at run time on the real ROM under
> Amiberry (memory of the running system read through the GDB stub after a Workbench 1.3.3 boot; session
> `build/amiberry/analysis/tdres_an/`, 2026-11-02). **[D]** deduced. **[S]** not verified.
>
> All four are `RTF_COLDSTART` residents of type `NT_RESOURCE` (8) built with `MakeLibrary` (memory
> `MEMF_PUBLIC|MEMF_CLEAR`, so every field not mentioned is 0) and published with `AddResource`. Calls use A6 =
> the resource base. Related: `timer-v34.md` §6 (who owns which CIA bit), `keyboard-handshake-v34.md` §1–§2,
> `setpatch-disk-resource.md` (SetPatch patches GetUnit/GiveUnit), `trackdisk-raw-changeint-v34.md`.

---

## 1. cia.resource → `ciaa.resource` and `ciab.resource`

One resident (`cia 34.1`, priority 80) creates **two** resources with identical code and separate bases.

### 1.1 Base layout (positive size `$7C` = 124, negative size 24 = 4 vectors) [O, P]

| Offset | Size | Contents | ciaa | ciab |
|---|---|---|---|---|
| `+$00` | 34 | struct Library: only `LN_TYPE` = 8, `LN_PRI` = 0, `LN_NAME` set. **`lib_Version` = 0, `lib_Revision` = 0, `lib_Flags` = 0, `lib_IdString` = NULL** | `"ciaa.resource"` | `"ciab.resource"` |
| `+$22` | long | CIA hardware base; register *r* is at base + *r* × `$100` | `$BFE001` | `$BFD000` |
| `+$26` | word | INTENA/INTREQ bit of the CIA's level | `$0008` (PORTS, level 2) | `$2000` (EXTER, level 6) |
| `+$28` | byte | **enabled mask** (software copy of the ICR mask, bits 0–4) | | |
| `+$29` | byte | **pending mask** (ICR flags read but not yet dispatched) | | |
| `+$2A` | 22 | struct Interrupt of the exec server: `NT_INTERRUPT`, pri 0, name = resource name, `is_Data` = base | | |
| `+$40` | 5 × 12 | one IntVector per ICR bit 0–4 (TA, TB, ALRM, SP, FLG): `+0` iv_Data, `+4` iv_Code, `+8` iv_Node (owner Interrupt) | | |

Version 0 confirmed at run time for both CIA resources. [P]

### 1.2 Initialisation [O]

1. ciaa: base built, server added with `AddIntServer(INTB_PORTS = 3)`, then `AddResource`.
2. ciab: CIA-B DDRA bits 6–7 set to output and PRA bits 6–7 set to 1 (`/DTR`, `/RTS` inactive), server added on
   `INTB_EXTER = 13`, `AddResource`.
3. **No ICR write** at init: the enabled mask starts at 0.

### 1.3 Server (exec interrupt server, one per CIA) [O]

1. Reads ICR **once** (this acknowledges the CIA), drops bit 7, ORs the result into the pending mask.
2. *active* = pending AND enabled. If 0 → returns.
3. Clears the *active* bits from the pending mask (bits pending but **disabled stay latched** in software).
4. Calls the vectors of the active bits in order **0, 1, 2, 3, 4**, each with A1 = `iv_Data`, A5 = `iv_Code`
   (`jsr`). Bits 5–6 are never dispatched. There is no check that a vector is installed: an enabled bit with no
   vector calls whatever `iv_Code` holds (0 at boot).
5. Returns with the Z flag set (chain continues) except possibly after the FLG vector, whose own return flags
   pass through. D0 is not set explicitly. [O]

### 1.4 `AddICRVector(iCRBit: D0, interrupt: A1)` — LVO −6 [O]

- Under a hand-made `Disable` (INTENA `$4000`, `IDNestCnt`+1, restored at the end).
- If `iv_Node` of that bit is non-NULL → **returns D0 = that owner's Interrupt pointer**, nothing changed.
- Otherwise: `iv_Node` = A1, and **`is_Code` and `is_Data` are copied** into the vector at this moment (later
  changes to the caller's Interrupt are not seen); then `AbleICR($80 | 1<<bit)` (§1.6), i.e. the bit is
  **enabled immediately**, in hardware and in the mask, and a latched pending flag fires at once. Returns
  **D0 = 0**.
- No range check: D0 > 4 writes beyond the vector table.

### 1.5 `RemICRVector(iCRBit: D0, interrupt: A1)` — LVO −12 [O]

- Under Disable: `iv_Node` := NULL (`iv_Code`/`iv_Data` left stale), then `AbleICR(1<<bit)`: the bit is
  **disabled**. A1 is **not compared** with the owner: any caller removes any vector. Returns D0 = 0 (no
  documented result).

### 1.6 `AbleICR(mask: D0)` — LVO −18 [O]

1. Under Disable, writes D0 **as is** to the CIA ICR (bit 7 = 1: enable the listed bits, bit 7 = 0: disable
   them; D0 = 0 writes 0, a no-op for the CIA).
2. **Result = the enabled mask before the change** (byte, zero-extended into D0).
3. Updates the enabled mask: bit 7 set → OR the bits 0–6; clear → AND NOT. D0 = 0 → unchanged (so
   `AbleICR(0)` = read the current enabled mask).
4. If (enabled AND pending) ≠ 0 → INTREQ ← `$8000 | +$26` (PORTS or EXTER): the level-2/level-6 interrupt is
   **re-triggered by software** so that latched flags of newly enabled bits are serviced.

### 1.7 `SetICR(mask: D0)` — LVO −24 [O]

1. Under Disable, **reads the hardware ICR** (acknowledging it) and ORs bits 0–6 into the pending mask. Nothing is
   lost: flags read here will be dispatched by the server later (step 4).
2. **Result = pending mask after that merge, before the change** (byte, zero-extended). `SetICR(0)` = sample the
   flags without changing them.
3. Bit 7 set → pending |= bits (a **software-generated** CIA interrupt); clear → pending &= ~bits (clears latched
   flags, e.g. trackdisk's `SetICR($10)` before enabling FLG).
4. Same re-trigger rule as AbleICR (INTREQ set if enabled AND pending ≠ 0).

### 1.8 State after a Workbench 1.3.3 boot [P]

| | enabled | pending | vectors |
|---|---|---|---|
| ciaa | `$0A` | `$04` (ALRM latched, not enabled) | bit 1 timer.device, bit 3 keyboard.device |
| ciab | `$04` | `$00` | bit 2 graphics (unnamed Interrupt), bit 4 disk.resource `dr_Index` (unnamed, disabled) |

---

## 2. disk.resource

Resident `disk 34.1`, priority 70. Base = NDK `struct DiscResource`; units use `struct DiscResourceUnit`.

### 2.1 Base layout (positive size `$90` = 144, 5 vectors) [O, P]

| Offset | Field | Value / role |
|---|---|---|
| `+$00` | Library | `NT_RESOURCE`, name `"disk.resource"`, `lib_Version` 34, `lib_Revision` 1 (via InitStruct) |
| `+$22` | `dr_Current` | last DRU that obtained the channel; **initialised to `$FFFFFFFF`**, never cleared |
| `+$26` | `dr_Flags` | bits 0–3 `DRF_ALLOC0..3` (AllocUnit), bit 7 `DRF_ACTIVE` (channel held) |
| `+$28` | `dr_SysLib` | ExecBase |
| `+$2C` | `dr_CiaResource` | ciab.resource |
| `+$30` | `dr_UnitID[4]` | drive IDs read at init (§2.5) |
| `+$40` | `dr_Waiting` | List of queued DRUs (`lh_Type` 0) |
| `+$4E` | `dr_DiscBlock` | Interrupt installed with `SetIntVector(INTB_DSKBLK = 1)` |
| `+$64` | `dr_DiscSync` | Interrupt installed with `SetIntVector(INTB_DSKSYNC = 12)` |
| `+$7A` | `dr_Index` | Interrupt given to ciab `AddICRVector(4)` |

The three Interrupts have only `is_Data` (= resource base) and `is_Code` set (type, priority, name = 0).

DiscResourceUnit (caller-owned, `$56` bytes): `+$00` struct Message (`mn_ReplyPort` must be valid),
`+$14` `dru_DiscBlock`, `+$2A` `dru_DiscSync`, `+$40` `dru_Index` (struct Interrupt each; only `is_Data`/`is_Code`
are used).

### 2.2 Initialisation order [O]

1. `OpenResource("ciab.resource")`; failure → Alert `$21058020`, no resource.
2. `MakeLibrary`; failure → Alert `$21020000`.
3. `SetIntVector` for DSKBLK, then DSKSYNC (these **replace** the exec vectors: handlers, not servers).
4. CIA-B PRB ← `$FF`, DDRB ← `$FF` (all drive lines outputs, inactive); CIA-A DDRA &= `$C3` (bits 2–5 `/CHNG`,
   `/WPRO`, `/TK0`, `/RDY` inputs).
5. Under Disable: `AddICRVector(4, dr_Index)` on ciab (result ignored), then `AbleICR($10)` (FLG **disabled**).
6. DSKLEN ← `$4000`; **DMACON ← `$8010`** (DSKEN; the only DMACON write of the disk subsystem).
7. `dr_Waiting` initialised, `dr_UnitID[0]` := 0, IDs of units 1–3 read (§2.5), `AddResource`.

### 2.3 Interrupt dispatch [O]

| Source | Acknowledge | Dispatch |
|---|---|---|
| DSKBLK (level 1) | INTREQ ← `$0002` first | to `dr_Current->dru_DiscBlock`: A1 = its `is_Data`, A5 = its `is_Code`, **jump** (the unit code returns straight to exec) |
| DSKSYNC (level 5) | INTREQ ← `$1000` first | to `dr_Current->dru_DiscSync` likewise |
| index (CIA-B FLG, via ciab) | (CIA acknowledged by ciab) | to `dr_Current->dru_Index` likewise |

- Dispatch goes to `dr_Current` **whether or not `DRF_ACTIVE` is set**: the last owner keeps receiving disk
  interrupts after `GiveUnit`.
- `dr_Current` = NULL: DSKBLK/DSKSYNC → Alert `$21000002` (`AN_DRIntNoAct`, recoverable) and return; index →
  plain return. `dr_Current` = `$FFFFFFFF` (no GetUnit ever done) is **not** caught. [O]
- Other registers set by exec's dispatcher pass through unchanged. [O]

### 2.4 Functions [O]

| LVO | Function | Behaviour |
|---:|---|---|
| −6 | `AllocUnit(unitNum: D0)` | `bset` of bit *unit* in `dr_Flags`; **D0 = `$000000FF` if the bit was clear** (allocated), 0 if already allocated. No Disable, no range check (unit 7 would hit `DRF_ACTIVE`). |
| −12 | `FreeUnit(unitNum: D0)` | clears the bit; no owner check, no result (D0 unchanged). |
| −18 | `GetUnit(unitPtr: A1)` | under Disable: if `DRF_ACTIVE` was clear → set it, **D0 = previous `dr_Current`** (the last DRU that held the channel; `$FFFFFFFF` at the very first call), `dr_Current` := A1. If active → `AddTail(dr_Waiting, A1)` and **D0 = 0**; if A1 *is* `dr_Current`, Alert `$21000001` (`AN_DRHasDisk`, recoverable) first, then queued anyway. |
| −24 | `GiveUnit()` | under Disable: CIA-B PRB ← `$FF` (all `/SELx` and `/MTR` high, i.e. drives deselected; motors keep their latched state), clears `DRF_ACTIVE`, `RemHead(dr_Waiting)`; after Enable, `ReplyMsg` of the removed DRU, if any. No owner check. |
| −30 | `GetUnitID(unitNum: D0)` | D0 = `dr_UnitID[unit]`; no range check, no hardware access. |

Queueing semantics (important):
- The returned "previous owner" lets a driver decide whether to reprogram shared state; trackdisk resets ADKCON
  (`$0600`, `$9100`) when it differs from its own DRU.
- `GiveUnit` **does not transfer** the channel: the woken DRU only gets its message replied (to its
  `mn_ReplyPort`), `dr_Current` and `DRF_ACTIVE` are not set for it. The waiter must call `GetUnit` **again**
  (trackdisk loops: `GetUnit` → 0 → `Wait` on its reply port's signal → `GetMsg` → `GetUnit` again). Another
  caller may take the channel in between. [O]
- Only one waiter is woken per `GiveUnit` (FIFO).

### 2.5 Drive IDs (`dr_UnitID`) [O, P]

- Read **once**, at resource init (cold start). Unit 0 (internal) is never read: always `$00000000`.
- Units 1–3 (`/SEL1..3` = PRB bits 4–6): PRB written `$7F`, then `$7F` with that `/SEL` low (motor-on latched),
  `$FF`, `$FF` with `/SEL` low (motor-off latched: resets the drive's ID shift register), `$FF`; then 32 times:
  `/SEL` low (motor off), sample CIA-A PRA bit 5 (`/RDY`), `/SEL` high. Each sample is shifted in **MSB first**,
  the **raw line level** (1 = high). No delay between accesses other than CIA access time.
- Values: `$00000000` Amiga 3.5" DD, `$55555555` 5.25" 40-track, `$FFFFFFFF` no drive (line pulled up).
- Run time (Amiberry, DF1 enabled): `dr_UnitID` = `0, 0, $FFFFFFFF, $FFFFFFFF`; `dr_Flags` = `$03` (units 0 and 1
  allocated by trackdisk). [P]

---

## 3. potgo.resource

Resident `potgo 34.1`, priority 100.

### 3.1 Base layout (positive size 41, negative 18 = 3 vectors) [O, P]

| Offset | Size | Contents |
|---|---|---|
| `+$00` | 34 | Library: `NT_RESOURCE`, name `"potgo.resource"`, `lib_Flags` 6, **`lib_Version` 0** |
| `+$22` | long | ExecBase (stored by the init routine) |
| `+$26` | word | **allocated bits** |
| `+$28` | word | **POTGO shadow** (only bits 8–15 are kept) |

No POTGO write at init; both words start at 0. `MakeLibrary` failure → no resource, no alert. After a Workbench
boot: allocated = `$0F00`, shadow = `$0F00` (port-0 lines taken by the system input path). [P]

POTGO bits: 15 OUTRY, 14 DATRY, 13 OUTRX, 12 DATRX, 11 OUTLY, 10 DATLY, 9 OUTLX, 8 DATLX, 0 START. Below,
"DAT bits" = `$5500`, "OUT bits" = `$AA00`; each OUT bit pairs with the DAT bit just below it.

### 3.2 `AllocPotBits(bits: D0)` — LVO −6 [O]

Under `Disable`/`Enable` (exec calls). Starting from the requested word:
1. Remove bits already allocated, **and** remove OUT bits whose paired DAT bit is allocated (owning a DAT line
   also reserves its OUT bit).
2. If START is still requested and some DAT bit is allocated **without** its OUT bit (a line used as a
   proportional input by its owner), START is refused.
3. If START is **already allocated** by someone, only complete OUT+DAT pairs remain grantable: lone DAT or lone
   OUT bits are dropped.
4. Keep only bits 8–15 and 0 (`$FF01`).
5. allocated |= granted. **Returns D0 = granted bits** (subset of the request, possibly 0).

### 3.3 `FreePotBits(bits: D0)` — LVO −12 [O]

No Disable. Keeps only DAT bits and START from D0 (`$5501`), adds the OUT bit of each DAT bit kept, and clears
them from the allocated word. Consequences: freeing a DAT bit also frees its OUT bit; **freeing an OUT bit alone
frees nothing**. No owner check, no result.

### 3.4 `WritePotgo(word: D0, mask: D1)` — LVO −18 [O]

Under Disable: shadow := (shadow AND NOT mask) OR (word AND mask); POTGO (`$DFF034`) ← that value; then the shadow
keeps only its high byte (START and the other low bits are one-shot and never re-sent). **No check** that the
caller owns the bits in `mask`. No result.

---

## 4. misc.resource

Resident `misc 34.1`, priority 70.

### 4.1 Base layout (positive size 50, negative 12 = 2 vectors) [O, P]

| Offset | Contents |
|---|---|
| `+$00` | Library: `NT_RESOURCE`, name `"misc.resource"`, `lib_Flags` 6, `lib_Version` 34, `lib_Revision` 1 |
| `+$22` | owner of `MR_SERIALPORT` (0): pointer to owner name, NULL = free |
| `+$26` | `MR_SERIALBITS` (1) |
| `+$2A` | `MR_PARALLELPORT` (2) |
| `+$2E` | `MR_PARALLELBITS` (3) |

`MakeLibrary` failure → Alert `$22020000`. All four free after a plain Workbench boot (serial.device not
loaded). [P]

### 4.2 Functions [O]

| LVO | Function | Behaviour |
|---:|---|---|
| −6 | `AllocMiscResource(unit: D0, name: A1)` | under Disable: if slot *unit* is NULL → slot := A1, **D0 = 0** (success); else **D0 = current owner's name pointer**, slot unchanged. Passing A1 = NULL "succeeds" but leaves the unit free. No range check (unit > 3 writes past the base). |
| −12 | `FreeMiscResource(unit: D0)` | slot := NULL, no Disable, **no owner check**; no result. |

---

## 5. Test vectors

| Call (real ROM) | Expected |
|---|---|
| `AddICRVector(1, x)` on ciaa after boot | D0 = timer.device's Interrupt (owner), no change |
| `AddICRVector(0, x)` on ciab, then `AbleICR(0)` | 0, then `$05` (TA enabled by the add, ALRM already) |
| `SetICR(0)` on ciaa after boot | `$04` or more (ALRM latched) [P for the `$04`] |
| `SetICR($81)` on ciab with bit 0 vector installed and enabled | vector called at the next level-6 service |
| `RemICRVector(0, anything)` | bit 0 disabled, `iv_Node` NULL |
| `GetUnitID(2)` with no DF2 | `$FFFFFFFF` [P] |
| `AllocUnit(0)` while trackdisk has DF0 open | 0; `AllocUnit(3)` with DF3 never opened: `$FF` |
| `GetUnit(dru)` with channel free | D0 = previous `dr_Current` (non-zero); busy → 0, then a reply after the owner's `GiveUnit`, after which `GetUnit` must be repeated |
| `AllocPotBits($C000)` after boot | `$C000`; `FreePotBits($8000)` frees nothing; `FreePotBits($4000)` frees both |
| `AllocMiscResource(0, "A")` then `(0, "B")` | 0, then pointer to `"A"` |

---

## 6. Open points

- cia server return when the FLG vector is the last one called: whether a non-zero Z-clear return from that vector
  ever stops the server chain in practice (only ciaa/ciab are on PORTS/EXTER at boot, so no visible effect).
- disk.resource ID read: not compared against a real 5.25" drive (only the code path and the empty-port value
  `$FFFFFFFF` were observed).
- Who owns the potgo bits `$0F00` after boot (gameport.device or input path) was not traced; only the value.

## Clean-room review

- [x] No ROM addresses; no instruction listing; behaviour described as effects and results.
- [x] Kept: LVOs, register conventions, structure offsets (ABI), hardware register values, alert numbers,
  run-time values.
